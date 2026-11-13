-- Gamepad Mode UI: EldoUI's frames placed for controller play while the
-- game's gamepad interface is on.
--
-- The gamepad interface is the player's own game setting ("Enable Gamepad
-- UI" in the game's Controller settings). EldoUI only reads it
-- (E:GamepadUIActive) and never turns it on or off. This file holds what
-- the rest of Gamepad Mode UI builds on:
--
--   E:GamepadActionSlots()     the game's gamepad action slots: a list, and
--                              the first one (no pet or possess slot)
--   E:GamepadDeviceKnown()     the game knows a controller
--   E:ControllerAddon()        folder and title of a loaded addon that binds
--                              the controller's buttons itself (the
--                              "controller" entries in Data/Competitors.lua);
--                              Gamepad Mode UI then only places frames
--   E:GamepadModeActive()      on: the gamepad interface is on and the
--                              profile uses Gamepad Mode UI
--   E:GetGamepadMoverPoint(name)  while on, the spot Data/GamepadOverlay.lua
--                              gives a frame for the layout in use, or nil
--                              (Core/Movers.lua asks it after a module's
--                              own rule and before the role and layout)
--   E:GamepadOverlayOwns(name) the overlay places the frame in this layout
--   E:SetGamepadModeAlways(on) the profile's choice
--   E:GamepadSettingsChanged() the Layouts page changed the switches
--   E:OnGamepadModeChange(fn)  fn(active) when it turns on or off
--   E:OfferGamepadMode(reason) the question, when nothing keeps it closed
--   E:OpenControllerSettings() the game's Controller settings
--   E:GamepadReturn()          the Edit Mode layout to go back to, while one
--                              waits: { key, name, status = "pending" }
--   E:RestoreGamepadReturn()   Restore now: switch Edit Mode back to it
--   E:OfferGamepadReturn(again) the Restore now notice, when one waits and
--                              Modern is on; once per session unless again
--
-- Going back: when the game's gamepad interface turns off, the game sets
-- Edit Mode to Modern itself. While Gamepad Mode UI was on, EldoUI keeps
-- the Edit Mode layout the player had before (a character record, kept
-- across a reload) and then offers Restore now. Only the player's click
-- switches the layout, once combat ends, never while Edit Mode is open;
-- a layout the player picked in the meantime, or one that no longer
-- exists, is left alone.
--
-- The question: once, when the player starts using a controller. It opens
-- when the game reports controller input that lasts three seconds, or when
-- the player switches the game to its gamepad interface. Never in combat
-- (it waits for the fight to end), never over Edit Mode, the setup or a
-- scene, once per session after Not now, never again on a character that
-- ticked "Don't ask again", and never while "Ask" is off. It changes
-- nothing until the player picks Use Gamepad Mode UI.
local _, E = ...
local L = E.L

local issecret = issecretvalue or function() return false end

E:RegisterPrivate("gamepadMode", { never = false })

local function Prefs()
	local db = E.db and E.db.gamepadUI
	return type(db) == "table" and db or E.defaults.gamepadUI
end

---------------------------------------------------------------------------
-- The game's gamepad action slots
---------------------------------------------------------------------------
-- The player's own action slots end at 180 (bars 6 to 8). The gamepad
-- interface keeps its own slots above them. The game names the first one
-- and says which slots are valid, so nothing here is a fixed number.
local LAST_PLAYER_SLOT = 180
local GAMEPAD_SPAN = 240

local function GamepadCall(name, ...)
	local api = C_GamepadUI
	local fn = api and api[name]
	if type(fn) ~= "function" then return nil end
	local ok, value = pcall(fn, ...)
	if ok and not issecret(value) then return value end
	return nil
end

-- Read once per frame at most: the spell rank glow asks for every button
-- it meets.
local slotCache = { time = -1 }

function E:GamepadActionSlots()
	local now = GetTime()
	if slotCache.time == now then return slotCache.slots, slotCache.first end
	slotCache.time, slotCache.slots, slotCache.first = now, nil, nil
	local first = GamepadCall("GetFirstGamepadActionStorageSlotIndex")
	if type(first) ~= "number" or first <= LAST_PLAYER_SLOT then return nil end
	local pet = GamepadCall("GetFirstGamepadPetActionStorageSlotIndex")
	if type(pet) ~= "number" or pet <= first then pet = nil end
	local slots = {}
	for slot = first, first + GAMEPAD_SPAN - 1 do
		if pet and slot >= pet then break end
		if GamepadCall("IsValidGamepadActionStorageSlotIndex", slot) == true
			and GamepadCall("IsValidGamepadPossessBarStorageSlotIndex", slot) ~= true then
			slots[#slots + 1] = slot
		end
	end
	slotCache.slots, slotCache.first = slots, first
	return slots, first
end

---------------------------------------------------------------------------
-- Controller, controller addons and the state
---------------------------------------------------------------------------
function E:GamepadDeviceKnown()
	local pad = C_GamePad
	if not (pad and type(pad.GetAllDeviceIDs) == "function") then return false end
	local ok, ids = pcall(pad.GetAllDeviceIDs)
	return ok and type(ids) == "table" and not issecret(ids) and next(ids) ~= nil or false
end

local function Loaded(addon)
	return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addon) and true or false
end

function E:ControllerAddon()
	for _, entry in ipairs(self:CompetitorEntries()) do
		if entry.feature == "controller" and Loaded(entry.addon) then
			return entry.addon, self:AddonTitle(entry.addon)
		end
	end
	return nil
end

function E:GamepadModeActive()
	return self:GamepadUIActive() and Prefs().always == true
end

---------------------------------------------------------------------------
-- The overlay's frame spots
---------------------------------------------------------------------------
local function OverlayPoints()
	local data = E.gamepadOverlay
	if not data then return nil end
	local layoutKey = E.db and E.db.general and E.db.general.layout
	local layout = layoutKey and E.layouts[layoutKey]
	local family = type(layout) == "table" and layout.family or layoutKey
	return data.variants[data.families[family] or "center"], layout
end

function E:GamepadOverlayOwns(name)
	local points = OverlayPoints()
	return points ~= nil and points[name] ~= nil
end

function E:GetGamepadMoverPoint(name)
	if not self:GamepadModeActive() then return nil end
	local points, layout = OverlayPoints()
	local point = points and points[name]
	if not point then return nil end
	return self:ScaleLayoutPoint(point, self:GetLayoutRatio(layout))
end

local callbacks = {}
local lastActive = false

function E:OnGamepadModeChange(fn)
	if type(fn) == "function" then callbacks[#callbacks + 1] = fn end
end

local function OfferFirstHelp()
	C_Timer.After(1, function()
		if E:GamepadModeActive() then E.Tour:Offer("gamepad:first") end
	end)
end

local function Changed()
	local active = E:GamepadModeActive()
	if active == lastActive then return end
	lastActive = active
	E:RefreshMovers()
	for _, fn in ipairs(callbacks) do
		local ok, err = pcall(fn, active)
		if not ok then geterrorhandler()(err) end
	end
	if active then OfferFirstHelp() end
end

function E:SetGamepadModeAlways(on)
	if not (self.db and type(self.db.gamepadUI) == "table") then return false end
	self.db.gamepadUI.always = on and true or false
	Changed()
	return true
end

-- The Layouts page writes the profile's switches itself.
function E:GamepadSettingsChanged()
	Changed()
end

-- The Layouts page shows the state; it reads it again when that changes.
local function RefreshPage()
	if E.RefreshConfig then E:RefreshConfig() end
end

---------------------------------------------------------------------------
-- The game's Controller settings
---------------------------------------------------------------------------
-- Opens the game's settings on its Controller category, scrolled to the
-- gamepad interface switch, so the player ticks it. Out of combat only.
function E:OpenControllerSettings()
	if InCombatLockdown() or not (Settings and Settings.OpenToCategory) then return false end
	local panel, label, id = _G.SettingsPanel, _G.GAMEPAD_LABEL, nil
	if panel and panel.GetAllCategories and label then
		local ok, list = pcall(panel.GetAllCategories, panel)
		for _, category in ipairs(ok and type(list) == "table" and list or {}) do
			if category.GetName and category:GetName() == label and category.GetID then
				id = category:GetID()
				break
			end
		end
	end
	return (pcall(Settings.OpenToCategory, id, id and _G.ENABLE_GAMEPAD_UI or nil))
end

---------------------------------------------------------------------------
-- The question
---------------------------------------------------------------------------
local PROMPT_KEY = "gamepad-mode"
local DEBOUNCE = 3
local notNow = false
-- True while EldoUI itself closes or redraws the question: that is no
-- answer, so Not now does not count.
local quiet = false

local function Installed()
	return type(EldoUIDB) == "table" and type(EldoUIDB.installed) == "table" and EldoUIDB.installed[E.charKey] ~= nil
end

local function SetupOpen()
	local installer = E.Installer
	local window = installer and installer.GetWindow and installer.GetWindow()
	return window and window:IsShown() or false
end

-- The game plays a scene or a movie.
local function ScenePlaying()
	if (InCinematic and InCinematic()) or (IsInCinematicScene and IsInCinematicScene()) then return true end
	local movie = _G.MovieFrame
	return type(movie) == "table" and type(movie.IsShown) == "function" and movie:IsShown() or false
end

local function PromptShown()
	local frame = E:GetConfirm()
	return frame ~= nil and frame:IsShown() and frame.key == PROMPT_KEY
end

-- Why the question stays closed right now, or nil.
function E:GamepadPromptBlocked()
	local db = Prefs()
	if not db.ask then return "ask" end
	if db.always then return "always" end
	local char = self:GetPrivate("gamepadMode")
	if type(char) == "table" and char.never then return "never" end
	if notNow then return "notnow" end
	if self:ControllerAddon() then return "addon" end
	if not Installed() or SetupOpen() then return "setup" end
	if self.IsEditModeActive and self:IsEditModeActive() then return "editmode" end
	if ScenePlaying() then return "scene" end
	-- Another EldoUI question waits for an answer.
	local open = self:GetConfirm()
	if open and open:IsShown() and open.key ~= PROMPT_KEY then return "busy" end
	if InCombatLockdown() then return "combat" end
	return nil
end

local function Answer(choice, never)
	if never then
		local char = E:GetPrivate("gamepadMode")
		if type(char) == "table" then char.never = true end
	end
	if choice == "use" then
		E:SetGamepadModeAlways(true)
		if not E:GamepadUIActive() then
			E:Print(L["Gamepad Mode UI is on. It starts when you turn on the game's gamepad interface in the game's Controller settings."])
		end
	elseif choice == "settings" then
		-- The switch to the gamepad interface asks again, with its own text.
		E:OpenControllerSettings()
	else
		notNow = true
	end
end

local function Checked()
	local frame = E:GetConfirm()
	return frame and frame.check and frame.check:GetChecked() and true or false
end

local function ShowPrompt()
	local style = E:GamepadUIActive()
	local text = L["You are playing with a controller. EldoUI can place its frames for controller play: centered above the game's gamepad bar and clear of its radial menu. Your normal layout and dragged frames stay saved, and everything goes back when the game's gamepad interface is turned off."]
	if not style then
		text = text .. "\n\n" .. L["The game's gamepad interface is off. You can turn it on in the game's Controller settings."]
	end
	quiet = PromptShown()
	E:ShowConfirm({
		key = PROMPT_KEY,
		title = L["Gamepad Mode UI"],
		text = text,
		accept = L["Use Gamepad Mode UI"],
		cancel = L["Not now"],
		extra = not style and { L["Open controller settings"], function(_, _, checked) Answer("settings", checked) end } or nil,
		check = { label = L["Don't ask again on this character"], checked = false },
		onAccept = function(_, _, checked) Answer("use", checked) end,
		onCancel = function()
			if quiet then return end
			Answer("notnow", Checked())
		end,
	})
	quiet = false
end

-- reason: "controller" (the game's controller event), "style" (the switch
-- to the gamepad interface) or "login". Returns "shown", "combat" (it waits
-- for the fight to end) or why it stays closed.
function E:OfferGamepadMode(reason)
	if self:GamepadModeActive() then return "active" end
	if InCombatLockdown() then
		self:RunOutOfCombat(function() E:OfferGamepadMode(reason) end, "GamepadMode:prompt")
		return "combat"
	end
	local why = self:GamepadPromptBlocked()
	if why then return why end
	ShowPrompt()
	return "shown"
end

local function ClosePrompt()
	if not PromptShown() then return end
	quiet = true
	E:CancelConfirm(PROMPT_KEY)
	quiet = false
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local owner = {}
local activeSince
-- Going back to the Edit Mode layout (below).
local NoteLayout, CheckReturn

-- The game reports controller input (in either interface) and that it
-- stopped after a while. Input that lasts three seconds counts, so a
-- controller that only wakes up does not ask.
E:RegisterEvent("GAME_PAD_ACTIVE_CHANGED", function(_, _, isActive)
	if issecret(isActive) then return end
	if not isActive then
		activeSince = nil
		return
	end
	local stamp = GetTime()
	activeSince = stamp
	C_Timer.After(DEBOUNCE, function()
		if activeSince == stamp then E:OfferGamepadMode("controller") end
	end)
end, owner)

E:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION", function()
	if E:GamepadUIActive() then
		-- The game sets its gamepad interface up first.
		C_Timer.After(1, function()
			if E:GamepadUIActive() then E:OfferGamepadMode("style") end
		end)
	else
		ClosePrompt()
		C_Timer.After(0.5, CheckReturn)
	end
	Changed()
	RefreshPage()
end, owner)

E:RegisterEvent("PLAYER_LOGIN", function()
	lastActive = E:GamepadModeActive()
	if lastActive then OfferFirstHelp() end
	-- A reload between the switch back and Restore now offers it again.
	C_Timer.After(3, function()
		NoteLayout()
		CheckReturn(true)
	end)
	-- A login in the gamepad interface sends no switch event.
	C_Timer.After(6, function()
		if E:GamepadUIActive() then E:OfferGamepadMode("login") end
	end)
end, owner)

hooksecurefunc(E, "SetProfile", function() Changed() end)

---------------------------------------------------------------------------
-- Going back to the Edit Mode layout
---------------------------------------------------------------------------
E:RegisterPrivate("gamepadReturn", {})

local MODERN = "preset:modern"
-- The Edit Mode layout last seen while the keyboard interface was on.
local keyboardLayout
-- The record whose notice this session showed (its "at"), so the many
-- layout updates around a switch show it once.
local offered

local function ReturnRecord()
	local record = E:GetPrivate("gamepadReturn")
	return type(record) == "table" and record or nil
end

function E:GamepadReturn()
	local record = ReturnRecord()
	if record and record.status == "pending" and type(record.key) == "string" then return record end
	return nil
end

local function Consume(record)
	if record then record.status = "consumed" end
	offered = nil
	E:DismissAlert("gamepad-return")
	RefreshPage()
end

function NoteLayout()
	if E:GamepadUIActive() or not E.EditModeLayoutKey then return end
	local key, name = E:EditModeLayoutKey()
	-- The game's own gamepad layout is the game's choice, never the player's.
	if key and key ~= "preset:gamepad" then keyboardLayout = { key = key, name = name } end
end

-- The switch to the gamepad interface with Gamepad Mode UI on.
local function Remember()
	local record = ReturnRecord()
	if not (record and keyboardLayout) or keyboardLayout.key == MODERN then return end
	record.key, record.name = keyboardLayout.key, keyboardLayout.name
	record.status, record.at = "pending", time and time() or 0
end

function E:RestoreGamepadReturn()
	local record = self:GamepadReturn()
	if not record then return false, "none" end
	if InCombatLockdown() then
		self:RunOutOfCombat(function() E:RestoreGamepadReturn() end, "GamepadMode:return")
		self:Print(L["Edit Mode goes back to your layout when the fight ends."])
		return false, "combat"
	end
	local ok, why = self:SetEditModeLayout(record.key)
	if ok then
		Consume(record)
	elseif why == "editmode" then
		-- The next layout update (Edit Mode closing) shows the notice again.
		offered = nil
		self:Print(L["Close Edit Mode first, then press Restore now again."])
	else
		Consume(record)
		self:Print(L["The Edit Mode layout %s no longer exists, so Edit Mode stays on Modern."]:format(self:Highlight(record.name or record.key)))
	end
	return ok, why
end

-- After the switch back: offer Restore now while the game's Modern is on.
function CheckReturn(again)
	local record = E:GamepadReturn()
	if not record or E:GamepadUIActive() or not E.EditModeLayoutKey then return end
	local current = E:EditModeLayoutKey()
	if not current then return end
	if current ~= MODERN then
		-- Back on its own, or the player picked a layout since.
		Consume(record)
		return
	end
	local index, name = E:EditModeLayoutIndex(record.key)
	if not index then
		Consume(record)
		E:Print(L["The Edit Mode layout %s no longer exists, so Edit Mode stays on Modern."]:format(E:Highlight(record.name or record.key)))
		return
	end
	if offered == record.at and not again then return end
	offered = record.at
	E:PushAlert({
		key = "gamepad-return",
		title = L["Gamepad Mode UI"],
		options = { page = "layouts" },
		text = L["The game set Edit Mode to Modern when its gamepad interface turned off. Restore now switches back to %s."]:format(E:Highlight(name or record.key)),
		actions = {
			{ label = L["Restore now"], tip = L["Switches Edit Mode back to the layout you used before, out of combat."],
				func = function() E:RestoreGamepadReturn() end },
			{ label = L["Keep Modern"], func = function() Consume(E:GamepadReturn()) end },
		},
	})
end

function E:OfferGamepadReturn(again)
	CheckReturn(again)
end

E:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", function()
	-- The game's own handlers run first.
	C_Timer.After(0, function()
		NoteLayout()
		CheckReturn()
	end)
end, owner)

if EventRegistry and EventRegistry.RegisterCallback then
	-- Restore now waits while Edit Mode is open; its close offers it again.
	EventRegistry:RegisterCallback("EditMode.Exit", function()
		C_Timer.After(0, function() CheckReturn() end)
	end, owner)
end

E:OnGamepadModeChange(function(active)
	if active then Remember() end
end)

---------------------------------------------------------------------------
-- The first time it is on
---------------------------------------------------------------------------
E.Tour:Register("gamepad:first", {
	form = "spot", word = "gamepad",
	offer = function(_, force)
		if not (force or E:GamepadModeActive()) then return false end
		return E.Tour:Spot("gamepad:first", {
			force = force,
			title = L["Gamepad Mode UI"],
			text = L["EldoUI places its frames for controller play while the game's gamepad interface is on. Your normal layout and dragged frames stay saved and come back when you turn the gamepad interface off."],
			buttons = {
				{ L["Turn off"], function() E:SetGamepadModeAlways(false) end,
					L["Your frames go back to your normal layout. The Layouts page turns Gamepad Mode UI on again."] },
			},
		})
	end,
	replay = function(def) def.offer(def, true) end,
})
