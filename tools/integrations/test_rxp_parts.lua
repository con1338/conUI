-- Offline test for two RestedXP helpers asked for on 25.11.2026 (C10, C11):
--   * "Sizes to fit EldoUI" (EldoUI/Modules/Integrations.lua, section
--     "RestedXP's sizes to fit EldoUI's text"): RestedXP's guide text and
--     arrow text at EldoUI's text size, its arrow, active items and targets
--     grown by as much, a window scale back to 100 %; asked first, Undo;
--   * RestedXP's arrow, active items and targets on layout spots
--     (EldoUI/Data/AddonFit.lua, adapter guideParts; the item and target
--     movers in Integrations.lua beside the "RestedXP Guide" mover).
-- Run from the repository root:
--   lua5.1 tools/integrations/test_rxp_parts.lua
-- This starts all of EldoUI in the offline game (tools/harness/wow.lua)
-- next to a model of RestedXP, written after what RestedXP v4.11.36 does,
-- not RestedXP's code: its saved settings (RXPSettings: profiles and
-- profileKeys, values at their default not stored), settings:LoadScales and
-- settings:LoadFramePositions, the arrow's text, the frames RXPFrame,
-- RXPG_ARROW, RXPItemFrame and RXPTargetFrame, dragged with StartMoving
-- (user placed). The offline game has no real screen positions, so the
-- placement checks look at the points the fit sets and the movers it pulls.
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

World.phase = "load"
World.LoadAddOn("EldoUI")
local E = World.addons.EldoUI.ns

---------------------------------------------------------------------------
-- Model of RestedXP (after v4.11.36)
---------------------------------------------------------------------------
local function Movable(name, width, height)
	local frame = CreateFrame("Frame", name, UIParent)
	frame:SetSize(width, height)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	-- Dragged before with StartMoving: the game calls it user placed.
	rawset(frame, "IsUserPlaced", function() return true end)
	rawset(frame, "StopMovingOrSizing", function() end)
	return frame
end
local guide = Movable("RXPFrame", 235, 125)
local arrow = Movable("RXPG_ARROW", 32, 32)
local items = Movable("RXPItemFrame", 80, 30)
local targets = Movable("RXPTargetFrame", 150, 36)
local arrowFont
arrow.text = CreateFrame("Frame", nil, arrow)
rawset(arrow.text, "SetFont", function(_, font, size, flags) arrowFont = { font, size, flags } end)
rawset(arrow.text, "GetObjectType", function() return "FontString" end)

local charKey = E.charKey
local profile = {}
rawset(_G, "RXPSettings", { profiles = { ["Tester - Realm"] = profile }, profileKeys = { [charKey] = "Tester - Realm" } })
local scalesLoaded, positionsLoaded, arrowReset = 0, 0, 0
local settings = { profile = profile }
function settings:LoadScales() scalesLoaded = scalesLoaded + 1 end
function settings:LoadFramePositions() positionsLoaded = positionsLoaded + 1 end
function settings:IsStepListShown() return true end
function settings:SetStepListShown() end
local rxp = { settings = settings, font = "Interface\\AddOns\\RXPGuides\\Fonts\\font.ttf", RXPFrame = guide }
function rxp.ResetArrowPosition() arrowReset = arrowReset + 1 end
local AceAddon = LibStub:NewLibrary("AceAddon-3.0", 1)
function AceAddon:GetAddon(name, silent)
	if name == "RXPGuides" then return rxp end
	if not silent then error("no addon " .. tostring(name)) end
end

World.addons.RXPGuides = { name = "RXPGuides", meta = { Title = "RestedXP Guides" }, files = {}, demand = false }
table.insert(World.addonList, "RXPGuides")
World.LoadAddOn("RXPGuides")

local reloads = 0
local ShowReloadPrompt = E.ShowReloadPrompt
E.ShowReloadPrompt = function(self, ...) reloads = reloads + 1 return ShowReloadPrompt(self, ...) end

World.phase = "PLAYER_LOGIN"
World.loggedIn = true
World.Fire("PLAYER_LOGIN")
World.phase = "PLAYER_ENTERING_WORLD"
World.Fire("PLAYER_ENTERING_WORLD", true, false)
World.phase = "timers"
World.RunTimers(6)
World.phase = "test"

local M = E.modules.Integrations
local Fit = E.addonFit
Check(M and M.active, "the Integrations module runs")
Check(M:RXPWanted(), "the layout places RestedXP's guide (Automatic picks RestedXP)")

---------------------------------------------------------------------------
-- Sizes to fit EldoUI
---------------------------------------------------------------------------
local function Row(plan, field)
	for _, row in ipairs(plan and plan.rows or {}) do
		if row.field == field then return row end
	end
end

local plan = M:ChangePlan("rxpSize")
Check(plan ~= nil, "the size change has a plan while RestedXP is loaded")
Check(plan and plan.place == "Tester - Realm", "on this character's RestedXP profile")
Check(Row(plan, "guideFontSize") and Row(plan, "guideFontSize").to == 13 and Row(plan, "guideFontSize").from == nil,
	"guide text: from RestedXP's default to EldoUI's 13")
Check(Row(plan, "arrowText") and Row(plan, "arrowText").to == 13, "arrow text: 13")
Check(Row(plan, "arrowScale") and Row(plan, "arrowScale").to == 1.45, "arrow grows by as much as the text (13 / 9: 145 %)")
Check(Row(plan, "activeItemsScale") and Row(plan, "activeItemsScale").to == 1.45, "active items: 145 %")
Check(Row(plan, "activeTargetScale") and Row(plan, "activeTargetScale").to == 1.45, "targets: 145 %")
Check(Row(plan, "windowScale") == nil, "no window scale row while RestedXP keeps its default")
Check(M:ChangeOffered("rxpSize"), "offered")
local question = plan and M:ChangeQuestion(plan) or ""
Check(question:find("Guide font size: from RestedXP's default to 13", 1, true) ~= nil, "the question names the guide font size")
Check(question:find("Arrow scale: from RestedXP's default to 145 %", 1, true) ~= nil, "the question shows scales in percent")
Check(question:find("Tester - Realm", 1, true) ~= nil, "the question names the RestedXP profile")

-- A window scale the player set goes back to 100 %.
profile.windowScale = 1.3
plan = M:ChangePlan("rxpSize")
Check(Row(plan, "windowScale") and Row(plan, "windowScale").from == 1.3 and Row(plan, "windowScale").to == 1,
	"a window scale of 130 % goes back to 100 %")

-- Large text counts.
local general = E.db.general
general.textScale = 1.4
plan = M:ChangePlan("rxpSize")
Check(Row(plan, "guideFontSize").to == 18 and Row(plan, "arrowText").to == 18, "Large text 140 %: 18 (RestedXP's highest guide font)")
Check(Row(plan, "arrowScale").to == 2 and Row(plan, "activeItemsScale").to == 2, "and twice the size (the arrow's highest)")
general.textScale = 1

-- Apply: written, shown at once where RestedXP can, a reload for the rest.
local ok = M:ApplyChange("rxpSize")
Check(ok, "applied")
Check(profile.guideFontSize == 13 and profile.arrowText == 13 and profile.arrowScale == 1.45
	and profile.activeItemsScale == 1.45 and profile.activeTargetScale == 1.45 and profile.windowScale == 1,
	"every value is in RestedXP's profile")
Check(scalesLoaded > 0, "RestedXP lays out its scales again (settings:LoadScales)")
Check(arrowFont and arrowFont[1] == rxp.font and arrowFont[2] == 13 and arrowFont[3] == "OUTLINE", "the arrow's text takes 13 at once, as RestedXP's own option sets it")
Check(reloads > 0, "a reload is offered for the guide text")
Check(M:ChangeApplied("rxpSize") and not M:ChangeOffered("rxpSize"), "applied, nothing more to offer")
Check(M:ChangeStatus("rxpSize"):find("Undo", 1, true) ~= nil, "the status says Undo puts it back")

-- Undo: back as it was; a value the player changed since stays theirs.
profile.arrowText = 11
local undone, kept = M:UndoChange("rxpSize")
Check(undone, "undone")
Check(profile.guideFontSize == nil and profile.arrowScale == nil and profile.activeItemsScale == nil and profile.activeTargetScale == nil,
	"RestedXP's defaults are back (not stored)")
Check(profile.windowScale == 1.3, "the player's window scale is back")
Check(profile.arrowText == 11 and type(kept) == "table" and kept[1] == "Arrow text size", "the arrow text the player set since stays, and is named")
profile.arrowText, profile.windowScale = nil, nil

-- The options rows.
local rows = {}
for _, option in ipairs(M.options) do
	if type(option.label) == "string" then rows[option.label] = option end
end
local apply, undo = rows["Sizes to fit EldoUI"], rows["Undo the size change"]
Check(apply and apply.type == "execute" and not apply.hidden(), "\"Sizes to fit EldoUI\" shows while it would change something")
Check(undo and undo.hidden(), "\"Undo the size change\" hides while nothing is applied")

-- No RestedXP profile: nothing to offer.
rawset(_G, "RXPSettings", nil)
Check(M:ChangePlan("rxpSize") == nil and not M:ChangeShown("rxpSize"), "no RestedXP settings: no plan, no rows")
rawset(_G, "RXPSettings", { profiles = { ["Tester - Realm"] = profile }, profileKeys = { [charKey] = "Tester - Realm" } })

---------------------------------------------------------------------------
-- Arrow, active items and targets on layout spots
---------------------------------------------------------------------------
local adapter = Fit.adapters.guideParts
Check(adapter ~= nil, "the fit has RestedXP's arrow and windows")
Check(adapter and adapter.title == "RestedXP arrow and windows", "named \"RestedXP arrow and windows\"")
local detected = false
for _, entry in ipairs(Fit:Detected()) do if entry == adapter then detected = true end end
Check(detected, "listed on the Other addons page while RestedXP is loaded")

local function PlacedAt(frame, point)
	local p, relative, relativePoint = frame:GetPoint(1)
	return frame:GetNumPoints() == 1 and p == point and relative == UIParent and relativePoint == "BOTTOMLEFT"
end
local function Again()
	Fit:Schedule(0)
	World.RunTimers(4)
end
local function Away(frame)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

Again()
Check(adapter.state.status == "placed", "placed (" .. tostring(adapter.state.status) .. ", " .. tostring(adapter.state.why) .. ")")
Check(PlacedAt(arrow, "TOP"), "the arrow is on the waypoint arrow spot, its top on the spot's top")
Check(PlacedAt(items, "TOPLEFT"), "the active items are on their spot")
Check(PlacedAt(targets, "TOPLEFT"), "the targets are on their spot")
Check(Fit.placed.arrow == "guideParts", "the arrow spot is RestedXP's")

-- The item and target spots hang beside the guide.
local itemsMover, targetsMover = E.movers.EldoUI_RXPItems, E.movers.EldoUI_RXPTargets
Check(itemsMover ~= nil and targetsMover ~= nil, "the item and target movers exist")
local itemsPoint = E:GetMoverDefaultPoint("EldoUI_RXPItems") or {}
local point, relative, relativePoint = itemsPoint[1], itemsPoint[2], itemsPoint[3]
Check(point == "TOPLEFT" and relative == "EldoUI_RXPMover" and relativePoint == "TOPRIGHT", "the item spot starts right of the guide's top")
local targetsPoint = E:GetMoverDefaultPoint("EldoUI_RXPTargets") or {}
Check(targetsPoint[2] == "EldoUI_RXPItemsMover" and targetsPoint[3] == "BOTTOMLEFT", "the target spot sits under the item spot")
Check(itemsMover:IsShown() and targetsMover:IsShown(), "their movers show while the guide's does")

-- RestedXP puts its saved spots back (login, profile switch, arrow reset):
-- placed again.
Away(arrow)
settings:LoadFramePositions()
World.RunTimers(4)
Check(PlacedAt(arrow, "TOP"), "after RestedXP's LoadFramePositions the arrow is placed again")
Away(arrow)
rxp.ResetArrowPosition()
World.RunTimers(4)
Check(PlacedAt(arrow, "TOP"), "after RestedXP's arrow reset it is placed again")

-- A drag pulls the spot's mover.
local pulled = {}
local Save = E.SaveMoverFromRect
E.SaveMoverFromRect = function(self, name, ...) pulled[#pulled + 1] = name return Save(self, name, ...) end
arrow:StopMovingOrSizing()
items:StopMovingOrSizing()
E.SaveMoverFromRect = Save
Check(pulled[1] == "EldoUI_WaypointArrow", "dragging the arrow moves the waypoint arrow spot's mover")
Check(pulled[2] == "EldoUI_RXPItems", "dragging the active items moves their mover")

-- Never in combat: the item window holds secure buttons.
local combat = _G.InCombatLockdown
rawset(_G, "InCombatLockdown", function() return true end)
Away(items)
Again()
Check(not PlacedAt(items, "TOPLEFT"), "in a fight nothing moves")
rawset(_G, "InCombatLockdown", combat)
World.Fire("PLAYER_REGEN_ENABLED")
World.RunTimers(4)
Check(PlacedAt(items, "TOPLEFT"), "after the fight the active items are placed")

-- The guide not placed by EldoUI: its windows stay where RestedXP puts them.
M.db.rxp.move = false
M:OnProfileChanged()
World.RunTimers(4)
Away(items)
Away(arrow)
Again()
Check(not itemsMover:IsShown() and not targetsMover:IsShown(), "guide kept in RestedXP: no item and target movers")
Check(not PlacedAt(items, "TOPLEFT"), "guide kept in RestedXP: the active items stay where RestedXP put them")
Check(PlacedAt(arrow, "TOP"), "the arrow still takes the layout's arrow spot")
Check(adapter.state.why == "kept where RestedXP puts it, like its guide window", "the page says why the windows stay")
M.db.rxp.move = true
M:OnProfileChanged()
World.RunTimers(4)
Again()
Check(itemsMover:IsShown() and PlacedAt(items, "TOPLEFT"), "guide placed again: the windows are back beside it")

-- The player's switch on the Other addons page.
Fit:SetAddonOn("guideParts", false)
World.RunTimers(4)
local arrowPoint, arrowTo, arrowToPoint = arrow:GetPoint(1)
Check(adapter.state.status ~= "placed" and arrowPoint == "CENTER" and arrowTo == UIParent and arrowToPoint == "CENTER",
	"switched off: RestedXP's own spot comes back (" .. tostring(adapter.state.status) .. ")")
Fit:SetAddonOn("guideParts", true)
Again()
Check(PlacedAt(arrow, "TOP"), "switched on: placed again")

local errors = {}
for _, entry in ipairs(World.errors) do errors[#errors + 1] = ("[%s] %s"):format(entry.phase, entry.message:match("^[^\n]*")) end
Check(#errors == 0, "no errors (" .. #errors .. ")")
for index = 1, math.min(#errors, 20) do print("  " .. errors[index]) end

print(("%d checks passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
