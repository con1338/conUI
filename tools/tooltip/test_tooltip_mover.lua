-- Offline test for moving the tooltip (EldoUI/Modules/Tooltip.lua, section
-- "Anchor"). Run from the repository root:
--   lua5.1 tools/tooltip/test_tooltip_mover.lua
-- Asked for on 26.11.2026: the tooltip seemed stuck on the right side.
-- With Fixed or Smart it rests on the Tooltip mover, but move mode opens in
-- Combat mode, which left that mover out (its box showed only under All
-- frames, as the coordinate box's did, F25). And the tooltip always grew
-- from the mover's bottom-right corner, so a mover dragged to the left or
-- the top still had the tooltip hang off its right side, and Smart put it
-- on top of the open bags wherever the mover was.
-- This starts all of EldoUI in the offline game (tools/harness/wow.lua).
-- Checked: the mover is part of Combat mode; the tooltip grows from the
-- corner of the mover's own anchor point when it sits on the screen by a
-- corner or an edge (the layouts' bottom-right spot as before, top left,
-- left, top), also after a drag in move mode; a mover measured from the
-- middle (an imported spot) or attached to another one gets the corner from
-- the screen third it sits in; Smart sits on top of open bags only while
-- they cover the mover's spot, and on them when they can't be measured;
-- the cursor modes and Blizzard's spot are untouched; the options page's
-- Move opens move mode in its view with the box selected, and hides for the
-- modes without a mover; without the Move switch nothing moves; no errors.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/tooltip/") or "./"

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

-- As after the setup: EldoUI may skin and move Blizzard's tooltips.
local state = E.db and E.db.blizzard and E.db.blizzard.tooltips
Check(state ~= nil, "the saved settings have the tooltips' element")
if state then state.enabled, state.skin, state.move = true, true, true end

World.phase = "PLAYER_LOGIN"
World.loggedIn = true
World.Fire("PLAYER_LOGIN")
World.phase = "PLAYER_ENTERING_WORLD"
World.Fire("PLAYER_ENTERING_WORLD", true, false)
World.phase = "timers"
World.RunTimers(5)
World.phase = "test"

local M = E.modules.Tooltip
Check(M and M.active, "the Tooltip module runs")
local mover = E.movers.EldoUI_Tooltip
Check(mover ~= nil, "the Tooltip mover exists")
M:Apply()

---------------------------------------------------------------------------
-- Move mode shows the mover in the view it opens in
---------------------------------------------------------------------------
Check(E:IsCombatMover("EldoUI_Tooltip"), "the Tooltip mover is part of Combat mode")
Check(E:GetMoveView() == "combat" and E:MoverInMoveView(mover), "move mode's first view takes the Tooltip mover")
Check(mover:IsShown(), "Smart (the default): the mover shows")

---------------------------------------------------------------------------
-- The corner the tooltip grows from
---------------------------------------------------------------------------
local tip = _G.GameTooltip
-- The game's default anchor for a frame's tooltip; EldoUI's hook places it.
local function Show(owner)
	_G.GameTooltip_SetDefaultAnchor(tip, owner or UIParent)
	local point, relative, relativePoint, x, y = tip:GetPoint(1)
	return { point = point, relative = relative, relativePoint = relativePoint, x = x, y = y, count = tip:GetNumPoints() }
end
local function Place(point, x, y)
	E:SaveMoverPosition("EldoUI_Tooltip", point, "UIParent", point, x, y)
	local placed = mover:GetPoint(1)
	Check(placed == point, ("the mover takes the spot %s (got %s)"):format(point, tostring(placed)))
end

M.db.anchor = "fixed"
local function Expect(where, point)
	local shown = Show()
	Check(shown.count == 1 and shown.point == point and shown.relative == M.anchor and shown.relativePoint == point,
		("%s: the tooltip grows from the mover's %s corner (got %s on %s)"):format(where, point, tostring(shown.point), tostring(shown.relativePoint)))
end
Expect("the layout's spot", "BOTTOMRIGHT")
Place("TOPLEFT", 20, -20)
Expect("a mover at the top left", "TOPLEFT")
Place("LEFT", 20, 0)
Expect("a mover on the left", "BOTTOMLEFT")
Place("TOP", 0, -20)
Expect("a mover at the top", "TOP")
-- Where a mover sits on screen (the offline game has no layout).
local screenW, screenH = UIParent:GetSize()
-- In the game a mover's effective scale is UIParent's (the offline game
-- does not pass it on).
local function At(x, y)
	rawset(mover, "GetCenter", function() return x, y end)
	rawset(mover, "GetEffectiveScale", function() return UIParent:GetEffectiveScale() end)
end
Place("CENTER", 0, 0)
At(screenW / 2, screenH / 2)
Expect("a mover in the middle", "BOTTOM")
At(screenW - 150, 200)
Expect("an imported spot measured from the middle, sitting bottom right", "BOTTOMRIGHT")
At(150, screenH - 100)
Expect("an imported spot measured from the middle, sitting top left", "TOPLEFT")
-- Attached to another mover: the point is the link's side, not the screen's.
local other = CreateFrame("Frame", "TestOtherFrame", UIParent)
mover:ClearAllPoints()
mover:SetPoint("LEFT", other, "RIGHT", 4, 0)
At(400, screenH - 100)
Expect("attached to the right of a frame at the top left", "TOPLEFT")
mover:ClearAllPoints()
mover:SetPoint("TOP", other, "BOTTOM", 0, -4)
At(screenW - 150, 300)
Expect("attached below a frame at the bottom right", "BOTTOMRIGHT")
rawset(mover, "GetCenter", nil)
rawset(mover, "GetEffectiveScale", nil)
Place("BOTTOMRIGHT", -67, 538)
Expect("back on the layout's spot", "BOTTOMRIGHT")

-- A drag in move mode saves the point of the screen third the mover is in.
local width, height = mover:GetSize()
E:SaveMoverFromRect("EldoUI_Tooltip", 10, screenH - height - 10)
Check(mover:GetPoint(1) == "TOPLEFT", "dragged to the top left: the mover is measured from TOPLEFT (got " .. tostring(mover:GetPoint(1)) .. ")")
Expect("dragged to the top left", "TOPLEFT")
E:SaveMoverFromRect("EldoUI_Tooltip", screenW - width - 10, 10)
Expect("dragged to the bottom right", "BOTTOMRIGHT")

---------------------------------------------------------------------------
-- Smart and the open bags
---------------------------------------------------------------------------
local bags = CreateFrame("Frame", "EldoUI_Bags", UIParent)
bags:SetSize(400, 500)
bags:Show()
-- Edges on screen (the offline game has no layout).
local function SetEdges(frame, left, bottom, right, top)
	rawset(frame, "GetLeft", function() return left end)
	rawset(frame, "GetRight", function() return right end)
	rawset(frame, "GetBottom", function() return bottom end)
	rawset(frame, "GetTop", function() return top end)
end
local bagModule = E.modules.Bags
local ownFrame = bagModule and bagModule.frame
if bagModule then bagModule.frame = nil end
SetEdges(bags, 1500, 60, 1900, 560)
M.db.anchor = "smart"
SetEdges(M.anchor, 1650, 400, 1900, 520)
local shown = Show()
Check(shown.relative == bags and shown.point == "BOTTOMRIGHT" and shown.relativePoint == "TOPRIGHT",
	"Smart: bags that cover the mover's spot take the tooltip on top of them")
SetEdges(M.anchor, 20, 900, 270, 1020)
Place("TOPLEFT", 20, -20)
shown = Show()
Check(shown.relative == M.anchor and shown.point == "TOPLEFT",
	"Smart: with the mover dragged away from the bags, the tooltip stays on the mover")
bags:Hide()
shown = Show()
Check(shown.relative == M.anchor and shown.point == "TOPLEFT", "Smart: bags closed, on the mover")
bags:Show()
rawset(bags, "GetLeft", function() return nil end)
shown = Show()
Check(shown.relative == bags, "Smart: bags that can't be measured take the tooltip, as before")
bags:Hide()
for _, frame in ipairs({ bags, M.anchor }) do
	for _, edge in ipairs({ "GetLeft", "GetRight", "GetBottom", "GetTop" }) do rawset(frame, edge, nil) end
end
if bagModule then bagModule.frame = ownFrame end

---------------------------------------------------------------------------
-- The modes without the mover, and no Move switch
---------------------------------------------------------------------------
local owner = CreateFrame("Frame", nil, UIParent)
local cursorAnchor
rawset(tip, "SetOwner", function(_, _, anchor) cursorAnchor = anchor end)
M.db.anchor = "cursorRight"
tip:ClearAllPoints()
shown = Show(owner)
Check(cursorAnchor == "ANCHOR_CURSOR_RIGHT" and shown.count == 0, "Cursor right: the tooltip follows the cursor, not the mover")
M:Apply()
Check(not mover:IsShown(), "Cursor right: move mode leaves the mover out")

M.db.anchor = "blizzard"
M:Apply()
tip:ClearAllPoints()
shown = Show()
Check(shown.count == 0, "Blizzard's spot: EldoUI leaves the tooltip where the game puts it")
Check(not mover:IsShown(), "Blizzard's spot: move mode leaves the mover out")

M.db.anchor = "fixed"
M:Apply()
state.move = false
M:Apply()
tip:ClearAllPoints()
shown = Show()
Check(shown.count == 0, "no Move switch: EldoUI leaves the tooltip where the game puts it")
Check(not mover:IsShown(), "no Move switch: move mode leaves the mover out")
state.move = true
M:Apply()

---------------------------------------------------------------------------
-- The options page's Move
---------------------------------------------------------------------------
local moveRow
for _, option in ipairs(M.options) do
	if option.type == "execute" and option.label == "Move" then moveRow = option end
end
Check(moveRow ~= nil, "the Position section has Move")
if moveRow then
	M.db.anchor = "cursor"
	Check(moveRow.hidden(), "Move hides with Cursor")
	M.db.anchor = "blizzard"
	Check(moveRow.hidden(), "Move hides with Blizzard's spot")
	M.db.anchor = "smart"
	Check(not moveRow.hidden(), "Move shows with Smart")
	M.db.anchor = "fixed"
	Check(not moveRow.hidden(), "Move shows with Fixed")
	M:Apply()
	local selected
	local Select = E.SelectMover
	E.SelectMover = function(self, which) selected = which return Select and Select(self, which) end
	moveRow.func()
	Check(E:IsMoveMode(), "Move opens move mode")
	Check(E:MoverInMoveView(mover), "the Tooltip mover is in the view move mode opened in")
	Check(selected == mover, "Move selects the Tooltip mover's box")
	E.SelectMover = Select
	E:ToggleMoveMode(false)
end

local errors = {}
for _, entry in ipairs(World.errors) do errors[#errors + 1] = ("[%s] %s"):format(entry.phase, entry.message:match("^[^\n]*")) end
Check(#errors == 0, "no errors (" .. #errors .. ")")
for index = 1, math.min(#errors, 20) do print("  " .. errors[index]) end

print(("%d checks passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
