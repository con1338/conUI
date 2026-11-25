-- Offline test for two RestedXP helpers asked for on 25.11.2026 (C10, C11):
--   * "Sizes to fit EldoUI" (EldoUI/Modules/Integrations.lua, section
--     "RestedXP's sizes to fit EldoUI's text"): RestedXP's guide text and
--     arrow text at EldoUI's text size, its arrow, active items and targets
--     grown by as much, a window scale back to 100 %; asked first, Undo;
--   * RestedXP's arrow, active items and targets on layout spots
--     (EldoUI/Data/AddonFit.lua, adapter guideParts; the item and target
--     movers in Integrations.lua beside the "RestedXP Guide" mover), with
--     the addon fit's rows that give back a lost spot, pull only on a real
--     drag and leave a frame the player placed until they choose the
--     layout's spot (EldoUI/Core/AddonFit.lua, Core/OtherAddons.lua).
-- Run from the repository root:
--   lua5.1 tools/integrations/test_rxp_parts.lua
-- This starts all of EldoUI in the offline game (tools/harness/wow.lua)
-- next to a model of RestedXP, written after what RestedXP v4.11.36 does,
-- not RestedXP's code: its saved settings (RXPSettings: profiles and
-- profileKeys; AceDB keeps no value equal to a default and drops one at
-- logout), settings:LoadScales and settings:LoadFramePositions, the
-- arrow's text, the frames RXPFrame, RXPG_ARROW, RXPItemFrame and
-- RXPTargetFrame, each press ending with StopMovingOrSizing. The offline
-- game has no screen positions (GetRect is 0, 0, width, height), so the
-- checks look at the points the fit sets and the movers it pulls, and a
-- drag is a GetRect the test gives the frame.
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
	rawset(frame, "StopMovingOrSizing", function() end)
	-- As in the game: the scale times UIParent's (the offline game keeps
	-- each frame's own).
	rawset(frame, "GetEffectiveScale", function(self) return self:GetScale() * UIParent:GetEffectiveScale() end)
	return frame
end
local guide = Movable("RXPFrame", 235, 125)
local arrow = Movable("RXPG_ARROW", 32, 32)
local items = Movable("RXPItemFrame", 80, 43)
local targets = Movable("RXPTargetFrame", 150, 36)
local arrowFont
arrow.text = CreateFrame("Frame", nil, arrow)
rawset(arrow.text, "SetFont", function(_, font, size, flags) arrowFont = { font, size, flags } end)

local charKey = E.charKey
local profile = {}
local function Saved()
	return { profiles = { ["Tester - Realm"] = profile }, profileKeys = { [charKey] = "Tester - Realm" } }
end
rawset(_G, "RXPSettings", Saved())
local scalesLoaded = 0
local settings = { profile = profile }
function settings:LoadScales() scalesLoaded = scalesLoaded + 1 end
function settings:LoadFramePositions() end
function settings:IsStepListShown() return true end
function settings:SetStepListShown() end
local rxp = { settings = settings, font = "Interface\\AddOns\\RXPGuides\\Fonts\\font.ttf", RXPFrame = guide }
function rxp.ResetArrowPosition() end
local AceAddon = LibStub:NewLibrary("AceAddon-3.0", 1)
function AceAddon:GetAddon(name, silent)
	if name == "RXPGuides" then return rxp end
	if not silent then error("no addon " .. tostring(name)) end
end
-- AceDB at logout: no value equal to its default stays stored.
local DEFAULTS = { guideFontSize = 9, arrowText = 9, arrowScale = 1, activeItemsScale = 1, activeTargetScale = 1, windowScale = 1 }
local function Logout()
	for field, default in pairs(DEFAULTS) do
		if profile[field] == default then profile[field] = nil end
	end
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
Check(Row(plan, "guideFontSize") and Row(plan, "guideFontSize").from == 9 and Row(plan, "guideFontSize").to == 13,
	"guide text: from RestedXP's 9 to EldoUI's 13")
Check(Row(plan, "arrowText") and Row(plan, "arrowText").to == 13, "arrow text: 13")
Check(Row(plan, "arrowScale") and Row(plan, "arrowScale").to == 1.45, "arrow grows by as much as the text (13 / 9: 145 %)")
Check(Row(plan, "activeItemsScale") and Row(plan, "activeItemsScale").to == 1.45, "active items: 145 %")
Check(Row(plan, "activeTargetScale") and Row(plan, "activeTargetScale").to == 1.45, "targets: 145 %")
Check(Row(plan, "windowScale") == nil, "no window scale row while RestedXP keeps its default")
Check(M:ChangeOffered("rxpSize"), "offered")
local question = plan and M:ChangeQuestion(plan) or ""
Check(question:find("Guide font size: from 9 to 13", 1, true) ~= nil, "the question names the guide font size with RestedXP's default")
Check(question:find("Arrow scale: from 100 % to 145 %", 1, true) ~= nil, "the question shows scales in percent")
Check(question:find("Tester - Realm", 1, true) ~= nil, "the question names the RestedXP profile")
Check(M:ChangeStatus("rxpSize"):find("RXPGuides", 1, true) == nil, "the status names RestedXP, not its folder")

-- A window scale the player set goes back to 100 %, shown as 100 %.
profile.windowScale = 1.3
plan = M:ChangePlan("rxpSize")
Check(Row(plan, "windowScale") and Row(plan, "windowScale").from == 1.3 and Row(plan, "windowScale").to == 1,
	"a window scale of 130 % goes back to 100 %")
Check(M:ChangeQuestion(plan):find("Window scale: from 130 % to 100 %", 1, true) ~= nil, "a whole scale shows in percent too")

-- A default RestedXP was told to give new characters (AceDB defaults).
profile.windowScale = nil
setmetatable(profile, { __index = { windowScale = 1.2 } })
plan = M:ChangePlan("rxpSize")
Check(Row(plan, "windowScale") and Row(plan, "windowScale").from == 1.2, "a window scale from RestedXP's profile defaults counts too")
setmetatable(profile, nil)
profile.windowScale = 1.3

-- Large text counts.
local general = E.db.general
general.textScale = 1.4
plan = M:ChangePlan("rxpSize")
Check(Row(plan, "guideFontSize").to == 18 and Row(plan, "arrowText").to == 18, "Large text 140 %: 18 (RestedXP's highest guide font)")
Check(Row(plan, "arrowScale").to == 2 and Row(plan, "activeItemsScale").to == 2, "and twice the size (the arrow's highest)")
Check(M:ChangeQuestion(plan):find("Arrow scale: from 100 % to 200 %", 1, true) ~= nil, "200 % reads 200 %, not 2")
general.textScale = 1

-- Apply: written, shown at once where RestedXP can, a reload for the text.
local ok = M:ApplyChange("rxpSize")
Check(ok, "applied")
Check(profile.guideFontSize == 13 and profile.arrowText == 13 and profile.arrowScale == 1.45
	and profile.activeItemsScale == 1.45 and profile.activeTargetScale == 1.45 and profile.windowScale == 1,
	"every value is in RestedXP's profile")
Check(scalesLoaded > 0, "RestedXP lays out its scales again (settings:LoadScales)")
Check(arrowFont and arrowFont[1] == rxp.font and arrowFont[2] == 13 and arrowFont[3] == "OUTLINE", "the arrow's text takes 13 at once, as RestedXP's own option sets it")
Check(reloads == 1, "a reload is offered for the guide text")
Check(M:ChangeApplied("rxpSize") and not M:ChangeOffered("rxpSize"), "applied, nothing more to offer")

-- Logout: AceDB drops the window scale (now its default). Nothing to
-- offer again, and Undo still gives back 130 %.
Logout()
Check(profile.windowScale == nil, "the model drops the 100 % at logout, as AceDB does")
Check(not M:ChangeOffered("rxpSize"), "after the logout nothing new to offer")
profile.arrowText = 11
local undone, kept = M:UndoChange("rxpSize")
Check(undone, "undone")
Check(profile.windowScale == 1.3, "the player's 130 % is back after the logout dropped EldoUI's 100 %")
Check(profile.guideFontSize == 9 and profile.arrowScale == 1 and profile.activeItemsScale == 1 and profile.activeTargetScale == 1,
	"RestedXP's defaults are back (AceDB drops them again at logout)")
Check(profile.arrowText == 11 and type(kept) == "table" and #kept == 1 and kept[1] == "Arrow text size",
	"only the arrow text the player set since stays, and is named")
Check(reloads == 1, "no reload in between: RestedXP still shows 9, so Undo offers none")
Logout()
profile.arrowText, profile.windowScale = nil, nil

-- Applied, reloaded (RestedXP built with 13), then undone: a reload again.
M:ApplyChange("rxpSize")
M.rxpBuiltFont = 13
reloads = 0
M:UndoChange("rxpSize")
Check(reloads == 1, "after a reload with 13, Undo to 9 offers a reload")
Logout()
M.rxpBuiltFont = 9

-- Only the scales change (the guide text is 13 already, as RestedXP built
-- it): no reload offered.
profile.guideFontSize = 13
M.rxpBuiltFont = 13
reloads = 0
M:ApplyChange("rxpSize")
Check(profile.arrowScale == 1.45 and reloads == 0, "only scales changed: no reload offered")
M:UndoChange("rxpSize")
Logout()
profile.guideFontSize = nil
M.rxpBuiltFont = 9

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
rawset(_G, "RXPSettings", Saved())

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
local function Own(frame)
	local p, relative, relativePoint = frame:GetPoint(1)
	return p == "CENTER" and relative == UIParent and relativePoint == "CENTER"
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
Check(PlacedAt(arrow, "TOP"), "the arrow is placed by its top")
local slotLeft, slotBottom, slotWidth = Fit.RectOf(Fit.frames.arrow)
local ratio = E.GetLayoutRatio and E:GetLayoutRatio() or 1
local _, _, _, ax, ay = arrow:GetPoint(1)
Check(math.abs(ax - (slotLeft + slotWidth / 2)) < 0.01 and math.abs(ay - (slotBottom - 4 * ratio)) < 0.01,
	"the arrow's top sits right under the waypoint arrow spot, so EldoUI's own arrow keeps the spot")
Check(PlacedAt(items, "TOPLEFT"), "the active items are on their spot")
Check(PlacedAt(targets, "TOPLEFT"), "the targets are on their spot")
local state = Fit:StateText(adapter)
Check(state:find("Waypoint arrow", 1, true) and state:find("RestedXP active items", 1, true) and state:find("RestedXP targets", 1, true),
	"the page names the three spots: " .. state)

-- The item and target spots hang beside the guide; the item mover takes
-- the item window's size, so the targets start under it.
local itemsMover, targetsMover = E.movers.EldoUI_RXPItems, E.movers.EldoUI_RXPTargets
Check(itemsMover ~= nil and targetsMover ~= nil, "the item and target movers exist")
local itemsPoint = E:GetMoverDefaultPoint("EldoUI_RXPItems") or {}
Check(itemsPoint[1] == "TOPLEFT" and itemsPoint[2] == "EldoUI_RXPMover" and itemsPoint[3] == "TOPRIGHT", "the item spot starts right of the guide's top")
local targetsPoint = E:GetMoverDefaultPoint("EldoUI_RXPTargets") or {}
Check(targetsPoint[2] == "EldoUI_RXPItemsMover" and targetsPoint[3] == "BOTTOMLEFT" and targetsPoint[5] <= -24,
	"the target spot sits under the item spot, with room for the target window's title")
items:SetScale(1.45)
local onSize = items:GetScript("OnSizeChanged")
Check(onSize ~= nil, "EldoUI follows the item window's size")
if onSize then onSize(items, 80, 43) end
World.RunTimers(4)
local proxy = M.proxies.EldoUI_RXPItems
Check(proxy and math.abs(proxy:GetWidth() - 116) < 1 and math.abs(proxy:GetHeight() - 62) < 1,
	"the item mover is as big as the item window at 145 % (" .. (proxy and (proxy:GetWidth() .. " x " .. proxy:GetHeight()) or "-") .. ")")
items:SetScale(1)
if onSize then onSize(items, 80, 43) end
World.RunTimers(4)

-- RestedXP puts its saved spots back: placed again.
Away(arrow)
settings:LoadFramePositions()
World.RunTimers(4)
Check(PlacedAt(arrow, "TOP"), "after RestedXP's LoadFramePositions the arrow is placed again")

-- A click is no drag; a drag pulls the spot's mover.
local pulled = {}
local Save = E.SaveMoverFromRect
E.SaveMoverFromRect = function(self, name, ...) pulled[#pulled + 1] = name return Save(self, name, ...) end
local wantX, wantY = slotLeft + slotWidth / 2, slotBottom - 4 * ratio
rawset(arrow, "GetRect", function() return wantX - 16, wantY - 32, 32, 32 end)
arrow:StopMovingOrSizing()
Check(#pulled == 0, "a click on the arrow (StopMovingOrSizing, no move) moves no mover")
rawset(arrow, "GetRect", function() return wantX - 16 + 50, wantY - 32 - 30, 32, 32 end)
arrow:StopMovingOrSizing()
Check(pulled[1] == "EldoUI_WaypointArrow", "a drag of the arrow moves the waypoint arrow spot's mover")
rawset(arrow, "GetRect", nil)
local itemsSpot = { Fit.RectOf(Fit.frames.rxpItems) }
rawset(items, "GetRect", function() return itemsSpot[1], itemsSpot[2] + itemsSpot[4] - 43, 80, 43 end)
items:StopMovingOrSizing()
Check(#pulled == 1, "a click on the active items moves no mover, so their spot stays chained to the guide")
rawset(items, "GetRect", function() return itemsSpot[1] + 40, itemsSpot[2] + itemsSpot[4] - 43 - 20, 80, 43 end)
items:StopMovingOrSizing()
Check(pulled[2] == "EldoUI_RXPItems", "a drag of the active items moves their mover")
rawset(items, "GetRect", nil)
Again()

-- A locked spot: only that frame stays where the player dragged it.
local IsMoverLocked = E.IsMoverLocked
E.IsMoverLocked = function(_, name) return name == "EldoUI_WaypointArrow" end
rawset(arrow, "GetRect", function() return 500, 500, 32, 32 end)
arrow:StopMovingOrSizing()
rawset(arrow, "GetRect", nil)
E.IsMoverLocked = IsMoverLocked
Away(arrow)
Away(items)
Again()
Check(Own(arrow), "a drag with the spot locked: the arrow stays where the player put it")
Check(PlacedAt(items, "TOPLEFT"), "the active items still follow their spot")
adapter.state.moved = nil
Again()
Check(PlacedAt(arrow, "TOP"), "a layout pick (moved cleared) puts the arrow back")
E.SaveMoverFromRect = Save

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

-- Another addon on the arrow spot first (as TomTom, registered before):
-- RestedXP's arrow goes back to its own spot, and a drag of it pulls nothing.
local rival = CreateFrame("Frame", "RivalArrow", UIParent)
rival:SetSize(40, 40)
E:RegisterAddonFit("testRival", { folder = "RXPGuides", title = "Rival", frames = { { slot = "arrow", frame = function() return rival end, point = "TOP" } } })
table.remove(Fit.order, #Fit.order)
table.insert(Fit.order, 1, "testRival")
Again()
Check(PlacedAt(rival, "TOP") and Own(arrow), "the spot taken: RestedXP's arrow is back where RestedXP had it")
Check(not Fit:StateText(adapter):find("Waypoint arrow", 1, true), "the page no longer names the arrow spot for RestedXP")
pulled = {}
E.SaveMoverFromRect = function(self, name, ...) pulled[#pulled + 1] = name return Save(self, name, ...) end
rawset(arrow, "GetRect", function() return 700, 700, 32, 32 end)
arrow:StopMovingOrSizing()
rawset(arrow, "GetRect", nil)
E.SaveMoverFromRect = Save
Check(#pulled == 0, "dragging RestedXP's arrow then moves nothing of the other addon's spot")
table.remove(Fit.order, 1)
Fit.adapters.testRival = nil
Again()
Check(PlacedAt(arrow, "TOP"), "the spot free again: RestedXP's arrow comes back")

-- The guide not placed by EldoUI: all three go back where RestedXP had them.
M.db.rxp.move = false
M:OnProfileChanged()
World.RunTimers(4)
Again()
Check(not itemsMover:IsShown() and not targetsMover:IsShown(), "guide kept in RestedXP: no item and target movers")
Check(Own(arrow) and Own(items) and Own(targets), "guide kept in RestedXP: the arrow and both windows are back on RestedXP's spots")
Check(Fit:StateText(adapter) == "kept where RestedXP puts it, like its guide window", "the page says why: " .. Fit:StateText(adapter))
M.db.rxp.move = true
M:OnProfileChanged()
World.RunTimers(4)
Again()
Check(itemsMover:IsShown() and PlacedAt(items, "TOPLEFT") and PlacedAt(arrow, "TOP"), "guide placed again: all three are back")

-- The integration off: EldoUI leaves RestedXP alone.
M.db.rxp.enabled = false
M:OnProfileChanged()
World.RunTimers(4)
Again()
Check(Own(arrow) and Own(items), "integration off: RestedXP's own spots")
M.db.rxp.enabled = true
M:OnProfileChanged()
World.RunTimers(4)
Again()
Check(PlacedAt(arrow, "TOP"), "integration on: placed again")

-- The guide waits under the player frame for the setup: the arrow still
-- goes on its spot, the windows wait with the guide.
M.rxpHeld = true
Again()
Check(PlacedAt(arrow, "TOP") and Own(items) and Own(targets), "guide held for the setup: the windows wait, the arrow does not")
M.rxpHeld = nil
Again()
Check(PlacedAt(items, "TOPLEFT"), "setup done: the windows are beside the guide")

-- A frame the player placed before the fit did stays, until they choose
-- the layout's spot on the Other addons page.
Fit:SetAddonOn("guideParts", false)
World.RunTimers(4)
Check(Own(arrow) and Own(items) and Own(targets), "switched off: RestedXP's own spots come back")
local store = E:GetGlobal("addonFit")
store.placed.guideParts = nil
rawset(arrow, "IsUserPlaced", function() return true end)
Fit:SetAddonOn("guideParts", true)
Again()
Check(Own(arrow) and PlacedAt(items, "TOPLEFT"), "the arrow the player placed stays; the windows are placed")
Check(adapter.state.userPlaced and adapter.state.userPlaced[1], "the fit notes the arrow as placed by the player")
local options = {}
E:AddonFitOptions(options)
local takeOver
for _, option in ipairs(options) do
	if option.label == "Put it on the layout spot" then takeOver = option end
end
Check(takeOver and not takeOver.hidden(), "the Other addons page offers \"Put it on the layout spot\"")
takeOver.func()
World.RunTimers(4)
Check(PlacedAt(arrow, "TOP"), "chosen: the arrow goes on the layout's spot")
Check(takeOver.hidden(), "and the button goes")
rawset(arrow, "IsUserPlaced", nil)

local errors = {}
for _, entry in ipairs(World.errors) do errors[#errors + 1] = ("[%s] %s"):format(entry.phase, entry.message:match("^[^\n]*")) end
Check(#errors == 0, "no errors (" .. #errors .. ")")
for index = 1, math.min(#errors, 20) do print("  " .. errors[index]) end

print(("%d checks passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
