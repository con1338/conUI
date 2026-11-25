-- Offline test for RestedXP's step list on a click (EldoUI/Modules/
-- Integrations.lua, section "RestedXP's step list on a click") and the
-- minimap buttons other modules add (EldoUI/Modules/Minimap.lua,
-- E:AddMinimapButton). Run from the repository root:
--   lua5.1 tools/integrations/test_rxp_steplist.lua
-- Asked for on 25.11.2026: on a 4K screen the player scaled RestedXP's
-- classic guide window up to read it, and then the whole guide filled the
-- left side. Wanted: only the current step and the arrow, the list of every
-- step on a click, from a button in the minimap's addon button bin.
-- This starts all of EldoUI in the offline game (tools/harness/wow.lua)
-- next to a model of RestedXP, written after what RestedXP v4.11.36 does,
-- not RestedXP's code:
--   * SettingsPanel.lua: settings:IsStepListShown (a saved window height
--     under 35 is folded), settings:SetStepListShown (window and
--     profile.frameHeight to 125 or 10, a new layout asked for, nothing for
--     a guide with `hidewindow`), GetSettingsDB (the profile's name);
--   * GuideWindow.lua: BottomFrame.UpdateFrame on RestedXP's next update (a
--     list under 30 hides and the window keeps 28; a hidden list shows
--     again at the saved height, at least 50), the empty guide;
--   * the game: a size change runs the frame's OnSizeChanged.
-- Checked: the button is drawn, gathered in the bin right after EldoUI's
-- own (before another addon's button found first), named in "Manage
-- buttons", kept on the map's edge from there; a click folds the list and
-- the next one gives it back at the player's height (RestedXP's default
-- when none was saved), noted by RestedXP profile, also after RestedXP's
-- own switch and an Alt-drag; the icon follows RestedXP's own switch; the
-- key does the same as a click; Ctrl-click opens the setting; no guide or a
-- guide without a list stays as it is; the new guide window gets only the
-- switch; a fight with a protected window waits; the button goes with the
-- integration, its own switch, the Integrations and Minimap modules and a
-- RestedXP without the switch, and comes back; a refresh with nothing new
-- neither shows the button again nor takes it from another addon; with the
-- bin off it sits on the map's edge at its saved angle; no errors.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/integrations/") or "./"

local passed, failed = 0, 0
local function Check(ok, what)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. what) end
end

local World = dofile(ROOT .. "tools/harness/wow.lua")
World.root = ROOT
World.locale = "enUS"
World.globalNames = dofile(ROOT .. "tools/ci/globals.lua")
assert(World.AddAddon("EldoUI"), "EldoUI/EldoUI.toc not found")
for _, name in ipairs({ "EldoUI_Locale_daDK", "EldoUI_Locale_deDE" }) do World.AddAddon(name) end
World.Install()

-- Chat lines EldoUI prints.
local printed = {}
local chat = _G.DEFAULT_CHAT_FRAME
rawset(chat, "AddMessage", function(_, line) printed[#printed + 1] = tostring(line) end)
local function PrintedSince(count, text)
	for index = count + 1, #printed do
		if printed[index]:find(text, 1, true) then return true end
	end
	return false
end

-- Tooltip lines.
local tooltip = {}
local tip = _G.GameTooltip
rawset(tip, "SetOwner", function(self, owner) self.__owner = owner wipe(tooltip) end)
rawset(tip, "IsOwned", function(self, owner) return self.__owner == owner end)
rawset(tip, "SetText", function(_, text) tooltip[#tooltip + 1] = tostring(text) end)
rawset(tip, "AddLine", function(_, text) tooltip[#tooltip + 1] = tostring(text) end)
rawset(tip, "NumLines", function() return #tooltip end)
local function TooltipHas(text)
	for _, line in ipairs(tooltip) do
		if line:find(text, 1, true) then return true end
	end
	return false
end

-- Another addon's minimap button, there before EldoUI gathers.
local foreign = CreateFrame("Button", "Foo_MinimapButton", Minimap)
foreign:SetSize(31, 31)

World.phase = "load"
World.LoadAddOn("EldoUI")
local E = World.addons.EldoUI.ns

---------------------------------------------------------------------------
-- Model of RestedXP (after v4.11.36)
---------------------------------------------------------------------------
local calls = 0
local RXPFrame = CreateFrame("Frame", "RXPFrame", UIParent)
RXPFrame:SetSize(235, 125)
-- The game runs OnSizeChanged after a size change.
local SetHeight = RXPFrame.SetHeight
rawset(RXPFrame, "SetHeight", function(self, height)
	local old = self:GetHeight()
	SetHeight(self, height)
	local script = self:GetScript("OnSizeChanged")
	if height ~= old and script then script(self, self:GetWidth(), height) end
end)
local bottomShown = true
local rxp = { height = 125, RXPFrame = RXPFrame, updateBottomFrame = false }
local profiles = { ["Tester - Realm"] = {} }
local profileName = "Tester - Realm"
local settings = { profile = profiles[profileName] }
function settings:IsStepListShown()
	local frameHeight = self.profile and self.profile.frameHeight
	return frameHeight == nil or frameHeight >= 35
end
function settings:SetStepListShown(value)
	calls = calls + 1
	if rxp.currentGuide and rxp.currentGuide.hidewindow then return end
	rxp.RXPFrame:SetHeight(value and rxp.height or 10)
	self.profile.frameHeight = value and rxp.height or 10
	rxp.updateBottomFrame = true
end
settings.GetSettingsDB = function() return profileName end
rxp.settings = settings
local function UseProfile(name)
	profiles[name] = profiles[name] or {}
	profileName, settings.profile = name, profiles[name]
end

-- RestedXP's next update: BottomFrame.UpdateFrame (the list is the window
-- less 17 units).
local function RXPUpdate()
	if not rxp.updateBottomFrame then return end
	rxp.updateBottomFrame = false
	local guide = rxp.currentGuide
	if RXPFrame:GetHeight() - 17 < 30 then
		bottomShown = false
		if RXPFrame:GetHeight() < 28 then RXPFrame:SetHeight(28) end
	elseif guide and guide.hidewindow then
		bottomShown = false
		RXPFrame:SetHeight(28)
	elseif not bottomShown then
		if settings.profile.frameHeight then RXPFrame:SetHeight(math.max(settings.profile.frameHeight, 50)) end
		bottomShown = true
	end
end

-- An Alt-drag in RestedXP: the size changes, the release saves it.
local function AltDrag(height)
	RXPFrame:SetHeight(height)
	settings.profile.frameHeight = RXPFrame:GetHeight()
	rxp.updateBottomFrame = true
	RXPUpdate()
end

local AceAddon = LibStub:NewLibrary("AceAddon-3.0", 1)
function AceAddon:GetAddon(name, silent)
	if name == "RXPGuides" then return rxp end
	if not silent then error("no addon " .. tostring(name)) end
end

-- As after the setup: EldoUI may place the minimap buttons (Blizzard UI >
-- Minimap buttons, Replace), so the bin gathers them.
local state = E.db and E.db.blizzard and E.db.blizzard["minimap-buttons"]
Check(state ~= nil, "the saved settings have the minimap buttons' element")
if state then state.enabled, state.replace = true, true end

World.addons.RXPGuides = { name = "RXPGuides", meta = { Title = "RestedXP Guides" }, files = {}, demand = false }
table.insert(World.addonList, "RXPGuides")
World.LoadAddOn("RXPGuides")

World.phase = "PLAYER_LOGIN"
World.loggedIn = true
World.Fire("PLAYER_LOGIN")
World.phase = "PLAYER_ENTERING_WORLD"
World.Fire("PLAYER_ENTERING_WORLD", true, false)
World.phase = "timers"
World.RunTimers(5)
World.phase = "test"

local minimap = E.modules.Minimap
local integrations = E.modules.Integrations
Check(minimap and minimap.active, "the Minimap module runs")
Check(integrations and integrations.active, "the Integrations module runs")

local button = _G.EldoUI_RXPStepListMinimapButton
Check(button ~= nil, "the step list button is made")
if not button then
	print(("%d checks passed, %d failed"):format(passed, failed))
	os.exit(1)
end
local bin = _G.EldoUI_ButtonBin
local cfg = integrations.db.rxp
-- A button that registered for clicks takes them, as in the game.
rawset(button, "IsMouseClickEnabled", function() return true end)

local function Refresh()
	integrations:OnProfileChanged()
	World.RunTimers(3)
end
local function Click(mouse)
	local onClick = button:GetScript("OnClick")
	onClick(button, mouse or "LeftButton")
	RXPUpdate()
	World.RunTimers(3)
end
local function Key()
	_G.EldoUI:ToggleRXPStepList()
	RXPUpdate()
	World.RunTimers(3)
end
local function Noted() return type(cfg.listHeights) == "table" and cfg.listHeights[profileName] or nil end

-- Drawn, shown and in the bin, right after EldoUI's own button and before
-- the other addon's button the bin found first.
Check(button:IsShown(), "the button shows while RestedXP has the switch")
Check(button:GetParent() == bin, "the bin gathers the button")
Check(foreign:GetParent() == bin, "the bin gathers the other addon's button too")
local order = minimap.Bin.Visible()
Check(order[1] == _G.EldoUI_MinimapButton and order[2] == button and order[3] == foreign,
	"bin order: EldoUI's button, the step list, then the other addon's")
Check(rawget(button, "icon") ~= nil, "the button has its icon")
local manage
for _, option in ipairs(minimap.options or {}) do
	if option.key == "binManage" then manage = option end
end
local function ManageNames(text)
	local values = manage and type(manage.values) == "function" and manage.values() or {}
	for _, entry in pairs(values) do
		if type(entry) == "string" and entry:find(text, 1, true) then return true end
		if type(entry) == "table" then
			for _, value in pairs(entry) do
				if type(value) == "string" and value:find(text, 1, true) then return true end
			end
		end
	end
	return false
end
Check(ManageNames("RestedXP step list: in the bin"), "\"Manage buttons\" names it \"RestedXP step list\"")
Check(_G.BINDING_NAME_ELDOUI_RXP_STEPLIST == "Show or hide RestedXP's step list", "the key has its name in the Key Bindings window")

-- The tooltip says what a click does.
button:GetScript("OnEnter")(button)
Check(TooltipHas("RestedXP step list"), "the tooltip has the title")
Check(TooltipHas("fold the list of every step away"), "the tooltip offers to fold the shown list")
Check(TooltipHas("Ctrl"), "the tooltip names Ctrl-click for the setting")

-- The player's own height: folded, then given back.
local gray
rawset(button.icon, "SetDesaturated", function(_, value) gray = value and true or false end)
AltDrag(400)
Check(Noted() == 400, "an Alt-drag in RestedXP is noted while the list shows")
Click()
Check(settings.profile.frameHeight == 10 and RXPFrame:GetHeight() == 28, "a click folds the list (RestedXP's switch; its window keeps 28)")
Check(Noted() == 400, "the fold keeps the list's height, not RestedXP's 10 or 28")
Check(gray == true, "folded, the icon is grayed")
Check(TooltipHas("show the list of every step"), "after the click the tooltip offers to show the list")
Check(TooltipHas("Ctrl"), "and still names Ctrl-click")
Click()
Check(settings.profile.frameHeight == 400 and RXPFrame:GetHeight() == 400 and bottomShown,
	"the next click gives the list back at 400, not RestedXP's 125")
Check(gray == false, "shown, the icon is in color again")

-- No height saved: RestedXP's default.
settings.profile.frameHeight = nil
RXPFrame:SetHeight(125)
cfg.listHeights = nil
Click()
Check(settings.profile.frameHeight == 10, "folded from RestedXP's default height")
Check(Noted() == nil, "nothing noted when RestedXP had no height saved")
Click()
Check(settings.profile.frameHeight == 125 and RXPFrame:GetHeight() == 125, "opened at RestedXP's default height")

-- RestedXP's own switch and an Alt-drag in between.
AltDrag(400)
Click()
settings:SetStepListShown(true)
RXPUpdate()
World.RunTimers(3)
Check(gray == false, "RestedXP's own switch opened it: the icon is in color")
AltDrag(600)
settings:SetStepListShown(false)
RXPUpdate()
World.RunTimers(3)
Check(gray == true, "RestedXP's own switch folded it: the icon is gray")
Check(Noted() == 600, "the height of the list RestedXP showed is noted, not EldoUI's older 400")
Click()
Check(settings.profile.frameHeight == 600 and RXPFrame:GetHeight() == 600, "EldoUI opens it at 600")

-- One note per RestedXP profile (one per character unless shared).
AltDrag(400)
Click()
UseProfile("Other - Realm")
settings.profile.frameHeight = 200
RXPFrame:SetHeight(200)
Click()
Check(Noted() == 200, "the other profile notes its own height")
UseProfile("Tester - Realm")
RXPFrame:SetHeight(28)
Click()
Check(settings.profile.frameHeight == 400 and RXPFrame:GetHeight() == 400, "back on the first profile: its own 400, not 200")
UseProfile("Other - Realm")
RXPFrame:SetHeight(28)
Click()
Check(settings.profile.frameHeight == 200, "and the other profile gets its 200")
UseProfile("Tester - Realm")
RXPFrame:SetHeight(400)

-- The key does the same.
local before = calls
Key()
Check(calls == before + 1 and settings.profile.frameHeight == 10, "the key folds the list")
Key()
Check(settings.profile.frameHeight == 400, "the key opens it again at the noted height")

-- Ctrl-click is the options link, not a toggle.
before = calls
local ctrl = _G.IsControlKeyDown
rawset(_G, "IsControlKeyDown", function() return true end)
local opened = false
local open = E.OpenConfigFromLink
E.OpenConfigFromLink = function() opened = true end
Click()
local onMouseUp = button:GetScript("OnMouseUp")
if onMouseUp then onMouseUp(button, "LeftButton") end
rawset(_G, "IsControlKeyDown", ctrl)
E.OpenConfigFromLink = open
Check(calls == before, "Ctrl-click leaves the list alone")
Check(opened, "Ctrl-click opens the setting")

-- No guide loaded, and a guide RestedXP shows without a list.
for _, case in ipairs({
	{ guide = { empty = true, hidewindow = true, name = "" }, text = "No RestedXP guide is loaded.", what = "no guide loaded" },
	{ guide = { hidewindow = true, name = "A guide" }, text = "This RestedXP guide shows no step list.", what = "a guide without a list" },
}) do
	rxp.currentGuide = case.guide
	local count = #printed
	before = calls
	Click()
	Check(calls == before and settings.profile.frameHeight == 400, case.what .. ": the list stays as it is")
	Check(PrintedSince(count, case.text), case.what .. ": and says why")
	button:GetScript("OnEnter")(button)
	Check(TooltipHas(case.text), case.what .. ": the tooltip says it too")
end
rxp.currentGuide = nil

-- A fight while the window is protected: the change waits.
local combat = _G.InCombatLockdown
rawset(_G, "InCombatLockdown", function() return true end)
rawset(RXPFrame, "IsProtected", function() return true, true end)
local count = #printed
before = calls
Key()
Check(calls == before, "in a fight with a protected window: no change yet")
Check(PrintedSince(count, "The step list changes after combat."), "and says when")
rawset(_G, "InCombatLockdown", combat)
World.Fire("PLAYER_REGEN_ENABLED")
RXPUpdate()
World.RunTimers(3)
rawset(RXPFrame, "IsProtected", nil)
Check(calls == before + 1 and settings.profile.frameHeight == 10, "after the fight it folds")
Key()

-- The new guide window: only RestedXP's switch, its own open height.
local beta = CreateFrame("Frame", "RXPV2GuideWindowFrame", UIParent)
rawset(_G, "RXPV2GuideWindow", { frame = beta })
settings.profile.frameHeight = 300
RXPFrame:SetHeight(300)
cfg.listHeights[profileName] = 400
Click()
Check(settings.profile.frameHeight == 10 and Noted() == 400, "new window: folded, the classic height note stays")
Click()
Check(settings.profile.frameHeight == 125, "new window: RestedXP opens it by itself")
rawset(_G, "RXPV2GuideWindow", nil)
settings.profile.frameHeight = 400
RXPFrame:SetHeight(400)

-- The button goes with the integration, its own switch and both modules,
-- and comes back.
cfg.enabled = false
Refresh()
Check(not button:IsShown(), "integration off: no button")
count = #printed
before = calls
Key()
Check(calls == before, "integration off: the key leaves RestedXP alone")
Check(PrintedSince(count, "The RestedXP integration is off"), "and says so")
cfg.enabled = true
Refresh()
Check(button:IsShown(), "integration on: the button is back")

cfg.listButton = false
Refresh()
Check(not button:IsShown(), "\"Step list button on the minimap\" off: no button")
before = calls
Key()
Check(calls == before + 1, "the key works without the button")
Key()
cfg.listButton = true
Refresh()
Check(button:IsShown(), "switch on: the button is back")

E:SetModuleEnabled("Integrations", false)
World.RunTimers(3)
Check(not button:IsShown(), "Integrations module off: no button")
count = #printed
before = calls
Key()
Check(calls == before and PrintedSince(count, "Integrations"), "Integrations module off: the key names the module")
E:SetModuleEnabled("Integrations", true)
World.RunTimers(3)
Check(button:IsShown() and button:GetParent() == bin, "Integrations module on: the button is back in the bin")

E:SetModuleEnabled("Minimap", false)
World.RunTimers(3)
Check(not button:IsShown(), "Minimap module off: no button")
E:SetModuleEnabled("Minimap", true)
World.RunTimers(3)
Check(button:IsShown() and button:GetParent() == bin, "Minimap module on: the button is back in the bin")

-- A RestedXP without the switch.
local switch = settings.SetStepListShown
settings.SetStepListShown = nil
Refresh()
Check(not button:IsShown(), "a RestedXP without the switch: no button")
count = #printed
Key()
Check(PrintedSince(count, "This RestedXP version has no step list switch."), "the key says why")
settings.SetStepListShown = switch
Refresh()
Check(button:IsShown(), "the switch is there again: the button too")

-- A refresh with nothing new runs none of the bin's show hooks.
local shows = 0
local Show, SetShown = button.Show, button.SetShown
rawset(button, "Show", function(self) shows = shows + 1 return Show(self) end)
rawset(button, "SetShown", function(self, value) shows = shows + 1 return SetShown(self, value) end)
Refresh()
Key()
Key()
Check(shows == 0, "a refresh or a click with the button shown leaves it alone (" .. shows .. " show calls)")
rawset(button, "Show", nil)
rawset(button, "SetShown", nil)

-- "Manage buttons": kept on the map's edge, then gathered again.
Minimap:SetSize(200, 200)
minimap.db.ownAngles.RXPStepList = 90
minimap.db.binExclude.EldoUI_RXPStepListMinimapButton = true
minimap:CollectButtons()
World.RunTimers(3)
local point, relative, _, x, y = button:GetPoint(1)
Check(button:GetParent() == Minimap and point == "CENTER" and relative == Minimap and math.abs(x or 99) < 1 and (y or 0) > 0,
	"kept on the map: on its edge at its saved angle (90 degrees: above the map)")
Check(ManageNames("RestedXP step list: kept on the map"), "\"Manage buttons\" says it is kept on the map")
minimap.db.binExclude.EldoUI_RXPStepListMinimapButton = nil
minimap:CollectButtons()
World.RunTimers(3)
Check(button:GetParent() == bin, "gathered again")

-- The bin off: on the map's edge, where another addon that gathers
-- minimap buttons may take it; a click or a refresh leaves it there.
minimap.db.binMode = "off"
minimap:OnProfileChanged()
World.RunTimers(3)
minimap:Apply()
World.RunTimers(3)
point, relative, _, x, y = button:GetPoint(1)
Check(button:GetParent() == Minimap, "bin off: the button sits on the map")
Check(point == "CENTER" and relative == Minimap and math.abs(x or 99) < 1 and (y or 0) > 0, "at its saved angle")
Check(button:IsShown(), "and shows")
local other = CreateFrame("Frame", "OtherButtonBag", UIParent)
button:SetParent(other)
button:ClearAllPoints()
button:SetPoint("TOPLEFT", other, "TOPLEFT", 2, -2)
Key()
Key()
Refresh()
Check(button:GetParent() == other and select(2, button:GetPoint(1)) == other, "another addon took it: a click or a refresh leaves it there")
minimap.db.binMode = "drawer"
minimap:OnProfileChanged()
World.RunTimers(3)
minimap:Apply()
World.RunTimers(3)
Check(button:GetParent() == bin, "bin on again: gathered again")

local errors = {}
for _, entry in ipairs(World.errors) do errors[#errors + 1] = ("[%s] %s"):format(entry.phase, entry.message:match("^[^\n]*")) end
Check(#errors == 0, "no errors (" .. #errors .. ")")
for index = 1, math.min(#errors, 20) do print("  " .. errors[index]) end

print(("%d checks passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
