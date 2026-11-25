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
-- next to a model of RestedXP. The model is written after what RestedXP
-- v4.11.36 does (SettingsPanel.lua: settings:IsStepListShown, a window
-- taller than 35 shows the list, and settings:SetStepListShown, which sets
-- the window and profile.frameHeight to 125 or 10 and does nothing for a
-- guide with `hidewindow`), not RestedXP's code.
-- Checked: the button is drawn, gathered in the bin after EldoUI's own and
-- named in "Manage buttons"; a click folds the list and the next one gives
-- it back at the player's height (RestedXP's default when none was saved);
-- the key does the same; a guide without a list stays as it is; the new
-- guide window gets only the switch; the button goes with the integration,
-- its own switch, the Minimap module and a RestedXP without the switch,
-- and comes back; with the bin off it sits on the map's edge at its saved
-- angle; no errors on the way.
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
local function TooltipHas(text)
	for _, line in ipairs(tooltip) do
		if line:find(text, 1, true) then return true end
	end
	return false
end

World.phase = "load"
World.LoadAddOn("EldoUI")
local E = World.addons.EldoUI.ns

---------------------------------------------------------------------------
-- Model of RestedXP (after v4.11.36)
---------------------------------------------------------------------------
local calls = 0
local RXPFrame = CreateFrame("Frame", "RXPFrame", UIParent)
RXPFrame:SetSize(235, 125)
local rxp = { height = 125, RXPFrame = RXPFrame, updateBottomFrame = false }
local settings = { profile = {} }
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
rxp.settings = settings

local AceAddon = LibStub:NewLibrary("AceAddon-3.0", 1)
function AceAddon:GetAddon(name, silent)
	if name == "RXPGuides" then return rxp end
	if not silent then error("no addon " .. tostring(name)) end
end

World.addons.RXPGuides = { name = "RXPGuides", meta = { Title = "RestedXP Guides" }, files = {}, demand = false }
table.insert(World.addonList, "RXPGuides")
World.LoadAddOn("RXPGuides")

-- As after the setup: EldoUI may place the minimap buttons (Blizzard UI >
-- Minimap buttons, Replace), so the bin gathers them.
local state = E.db and E.db.blizzard and E.db.blizzard["minimap-buttons"]
Check(state ~= nil, "the saved settings have the minimap buttons' element")
if state then state.enabled, state.replace = true, true end

World.phase = "PLAYER_LOGIN"
World.loggedIn = true
World.Fire("PLAYER_LOGIN")
World.phase = "PLAYER_ENTERING_WORLD"
World.Fire("PLAYER_ENTERING_WORLD", true, false)
World.phase = "timers"
World.RunTimers(5)

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

local function Refresh()
	integrations:OnProfileChanged()
	World.RunTimers(3)
end
local function Click(mouse)
	local onClick = button:GetScript("OnClick")
	onClick(button, mouse or "LeftButton")
	World.RunTimers(3)
end

-- Drawn, shown and in the bin, right after EldoUI's own button.
Check(button:IsShown(), "the button shows while RestedXP has the switch")
Check(button:GetParent() == bin, "the bin gathers the button")
Check(minimap.ownButtons[1] and minimap.ownButtons[1].button == button, "the Minimap module lists it as an added button")
Check(rawget(button, "icon") ~= nil, "the button has its icon")
local manage
for _, option in ipairs(minimap.options or {}) do
	if option.key == "binManage" then manage = option end
end
if manage and type(manage.values) == "function" then
	local found = false
	local values = manage.values()
	for _, entry in pairs(values) do
		if type(entry) == "string" and entry:find("RestedXP step list", 1, true) then found = true end
		if type(entry) == "table" then
			for _, text in pairs(entry) do
				if type(text) == "string" and text:find("RestedXP step list", 1, true) then found = true end
			end
		end
	end
	Check(found, "\"Manage buttons\" names it \"RestedXP step list\"")
else
	Check(false, "the Minimap page has \"Manage buttons\"")
end
Check(_G.BINDING_NAME_ELDOUI_RXP_STEPLIST == "Show or hide RestedXP's step list", "the key has its name in the Key Bindings window")

-- The tooltip says what a click does.
button:GetScript("OnEnter")(button)
Check(TooltipHas("RestedXP step list"), "the tooltip has the title")
Check(TooltipHas("fold the list of every step away"), "the tooltip offers to fold the shown list")

-- The player's own height: folded, then given back.
local gray
rawset(button.icon, "SetDesaturated", function(_, value) gray = value and true or false end)
settings.profile.frameHeight = 400
RXPFrame:SetHeight(400)
Click()
Check(settings.profile.frameHeight == 10 and RXPFrame:GetHeight() == 10, "a click folds the list (RestedXP's switch)")
Check(integrations.db.rxp.listHeight == 400, "EldoUI notes the list's height before folding it")
Check(gray == true, "folded, the icon is grayed")
button:GetScript("OnEnter")(button)
Check(TooltipHas("show the list of every step"), "folded, the tooltip offers to show the list")
Click()
Check(settings.profile.frameHeight == 400 and RXPFrame:GetHeight() == 400, "the next click gives the list back at 400, not RestedXP's 125")
Check(rxp.updateBottomFrame == true, "RestedXP lays its list out again")
Check(gray == false, "shown, the icon is in color again")

-- No height saved: RestedXP's default.
settings.profile.frameHeight = nil
RXPFrame:SetHeight(125)
Click()
Check(settings.profile.frameHeight == 10, "folded from RestedXP's default height")
Check(integrations.db.rxp.listHeight == nil, "nothing noted when RestedXP had no height saved")
Click()
Check(settings.profile.frameHeight == 125 and RXPFrame:GetHeight() == 125, "opened at RestedXP's default height")

-- The key does the same.
local before = calls
_G.EldoUI:ToggleRXPStepList()
World.RunTimers(3)
Check(calls == before + 1 and settings.profile.frameHeight == 10, "the key folds the list")
_G.EldoUI:ToggleRXPStepList()
World.RunTimers(3)
Check(settings.profile.frameHeight == 125, "the key opens it again")

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

-- A guide RestedXP shows without a list.
rxp.currentGuide = { hidewindow = true }
local count = #printed
before = calls
Click()
Check(calls == before and settings.profile.frameHeight == 125, "a guide without a list stays as it is")
Check(PrintedSince(count, "This RestedXP guide shows no step list."), "and says why")
button:GetScript("OnEnter")(button)
Check(TooltipHas("This RestedXP guide shows no step list."), "the tooltip says it too")
rxp.currentGuide = nil

-- The new guide window: only RestedXP's switch, its own open height.
local beta = CreateFrame("Frame", "RXPV2GuideWindowFrame", UIParent)
rawset(_G, "RXPV2GuideWindow", { frame = beta })
settings.profile.frameHeight = 300
RXPFrame:SetHeight(300)
integrations.db.rxp.listHeight = 400
Click()
Check(settings.profile.frameHeight == 10 and integrations.db.rxp.listHeight == 400, "new window: folded, the classic height note stays")
Click()
Check(settings.profile.frameHeight == 125, "new window: RestedXP opens it by itself")
rawset(_G, "RXPV2GuideWindow", nil)

-- The button goes with the integration, its own switch and the Minimap
-- module, and comes back.
integrations.db.rxp.enabled = false
Refresh()
Check(not button:IsShown(), "integration off: no button")
count = #printed
before = calls
_G.EldoUI:ToggleRXPStepList()
Check(calls == before, "integration off: the key leaves RestedXP alone")
Check(PrintedSince(count, "The RestedXP integration is off"), "and says so")
integrations.db.rxp.enabled = true
Refresh()
Check(button:IsShown(), "integration on: the button is back")

integrations.db.rxp.listButton = false
Refresh()
Check(not button:IsShown(), "\"Step list button on the minimap\" off: no button")
before = calls
_G.EldoUI:ToggleRXPStepList()
Check(calls == before + 1, "the key works without the button")
_G.EldoUI:ToggleRXPStepList()
integrations.db.rxp.listButton = true
Refresh()
Check(button:IsShown(), "switch on: the button is back")

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
_G.EldoUI:ToggleRXPStepList()
Check(PrintedSince(count, "This RestedXP version has no step list switch."), "the key says why")
settings.SetStepListShown = switch
Refresh()
Check(button:IsShown(), "the switch is there again: the button too")

-- The bin off: on the map's edge at its own saved angle.
Minimap:SetSize(200, 200)
minimap.db.ownAngles.RXPStepList = 90
minimap.db.binMode = "off"
minimap:OnProfileChanged()
World.RunTimers(3)
minimap:Apply()
World.RunTimers(3)
local point, relative, _, x, y = button:GetPoint(1)
Check(button:GetParent() == Minimap, "bin off: the button sits on the map")
if not (point == "CENTER" and math.abs(x or 99) < 1 and (y or 0) > 0) then print("  point", point, relative, x, y, minimap.db.shape) end
Check(point == "CENTER" and relative == Minimap and math.abs(x or 99) < 1 and (y or 0) > 0, "at its saved angle (90 degrees: above the map)")
Check(button:IsShown(), "and shows")
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
