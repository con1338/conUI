-- EldoUI Action Bars: hidden bars. A bar that is On but not Shown (a
-- layout's hidden list, or the bar's own "Show on screen" switch) keeps
-- every action and every key; it only steps out of the way:
--   * It follows the rule "Mouse over, out of combat": its state driver
--     hides it in combat, so no stray click can reach it in a fight, and
--     out of combat it stays faded out until the mouse points at it. The
--     bar's own visibility settings stay saved for when it shows again.
--   * Bar 3 draws its first nine buttons as a small 3x3 box, smaller than
--     bar 1, in the bottom-right corner next to the bags and the menu.
--     Buttons 10 to 12 are not drawn and keep their keys.
--   * Bars 4 to 8 stand upright at the right edge of the screen, under the
--     quest list; when that edge is full they become small boxes beside
--     bar 3's.
--   * A bar the player dragged stays where it was dragged, and so does a
--     bar another frame of the layout hangs from.
-- The spot is picked from where the frames sit on screen, clear of every
-- frame that shows there, so it fits every layout and screen size.
local _, E = ...

local M = E:GetModule("ActionBars")
if not M then return end

local BOX = 3            -- buttons per row of a hidden box
local BOX_COUNT = 9      -- buttons bar 3 draws while hidden
local SPACING = 3
local GAP = 8            -- space kept to every other frame
local EDGE = 19          -- distance to the right edge of the screen
local STEP = 8           -- search grid
local MOVED = { 3, 4, 5, 6, 7, 8 } -- bars that move aside while hidden

-- Frames that may cover the box: the bag window opens on top of everything.
local IGNORE = { EldoUI_BagsAnchor = true, EldoUI_BankAnchor = true }

-- [bar] = { shape = "box" | "column", size, point, rect } from the last
-- placement, or nil while the bar keeps its own spot.
local plans = {}
M.hiddenPlans = plans -- exposed for inspection

-- Read-only provenance for the passive dock; point hooks keep their authority.
do
	local function Same(a, b) return not E.Secret(a) and not E.Secret(b) and rawequal(a, b) end
	local function Plain(v) return not E.Secret(v) and type(v) == "table" and getmetatable(v) == nil end
	M:RegisterDockHiddenSource(function(index)
		local db, active, plan = M.db, M.active, plans[index]
		if E.Secret(db) or type(db) ~= "table" then return end
		local bars = rawget(db, "bars")
		if not Plain(bars) or not Same(M.hiddenPlans, plans) then return end
		local cfg = rawget(bars, index)
		if not Plain(cfg) or E.Secret(plan) or (plan ~= nil and not Plain(plan)) then return end
		local enabled, shown, mouse = rawget(cfg, "enabled"), rawget(cfg, "shown"), rawget(cfg, "hiddenMouseover")
		if E.Secret(enabled) or E.Secret(shown) or E.Secret(mouse) then return end
		local point, shape, size, values
		if plan then
			point, shape, size = rawget(plan, "point"), rawget(plan, "shape"), rawget(plan, "size")
			if not Plain(point) or E.Secret(shape) or (shape ~= "box" and shape ~= "column") or E.Secret(size) or type(size) ~= "number" then return end
			values = {};for i = 1, 5 do local v = rawget(point, i);if E.Secret(v) then return end;values[i] = v end
		end
		local function Current()
			if not Same(M.db, db) or not Same(rawget(db, "bars"), bars) or not Same(rawget(bars, index), cfg)
				or not Same(M.active, active) or not Same(M.hiddenPlans, plans) or not Same(plans[index], plan)
				or not Same(rawget(cfg, "enabled"), enabled) or not Same(rawget(cfg, "shown"), shown)
				or not Same(rawget(cfg, "hiddenMouseover"), mouse) then return false end
			if plan then
				if not Same(rawget(plan, "point"), point) or not Same(rawget(plan, "shape"), shape) or not Same(rawget(plan, "size"), size) then return false end
				for i = 1, 5 do if not Same(rawget(point, i), values[i]) then return false end end
			end
			return true
		end
		return { kind = "live", current = Current }
	end)
end

---------------------------------------------------------------------------
-- The rule a hidden bar follows
---------------------------------------------------------------------------
-- Two rules: "Mouse over, out of combat" (the default), or "Never" when the
-- player keeps the bar hidden. Either way its keys keep working.
local blocks = { mouse = {}, never = {} }

function M:HiddenFadeBlock(index)
	local barDB = self.db.bars[index]
	local mode = barDB and barDB.hiddenMouseover == false and "never" or "mouse"
	local block = blocks[mode][index]
	if not block then
		block = E:VisibilityDefaults({ show = mode == "never" and "never" or "mouseoverNoCombat",
			fadedAlpha = 0, fadeTime = 0.2, delay = 0.5, hideVehicle = true })
		blocks[mode][index] = block
	end
	return block
end

-- How buttons out of sight are kept, for the whole account
-- (E.global.keymap.hiddenButtons): "hide" (the normal way) hides them;
-- "invisible" keeps the buttons of a hidden bar and those past a shortened
-- bar's end shown at alpha 0 with mouse clicks off. "invisible" exists for
-- a client where a key binding does not reach a hidden secure button.
local MODES = { hide = true, invisible = true }
E:AddGlobalDefaults("keymap", { hiddenButtons = "hide" })

function E:HiddenButtonsMode()
	local keymap = self.GetGlobal and self:GetGlobal("keymap")
	local mode = type(keymap) == "table" and keymap.hiddenButtons
	return MODES[mode] and mode or "hide"
end

-- Set the mode and lay the bars out again (out of combat). False for an
-- unknown mode.
function E:SetHiddenButtonsMode(mode)
	if not MODES[mode] then return false end
	local keymap = self:GetGlobal("keymap")
	if type(keymap) ~= "table" then return false end
	keymap.hiddenButtons = mode
	self:RunOutOfCombat(function()
		if M.active then M:Apply() end
		-- The Consumable Bar holds the key set's last three bar 3 keys.
		local consumable = E:GetModule("ConsumableBar")
		if consumable and consumable.active and consumable.UpdateVisibility then consumable:UpdateVisibility() end
	end)
	return true
end

-- True while hidden buttons are kept invisible instead of hidden.
function M:HiddenAlphaFallback()
	return E:HiddenButtonsMode() == "invisible"
end

local always
-- The block the bar's state driver follows. With "invisible" a hidden bar
-- is never hidden by its driver; its fade keeps it out of sight.
function M:HiddenDriverBlock(index)
	if self:HiddenAlphaFallback() and self:BarHidden(index) then
		always = always or E:VisibilityDefaults({ show = "always", hideVehicle = true })
		return always
	end
	return self:FadeBlock(index)
end

-- May the drawn buttons of bar `index` take mouse clicks now? While hidden
-- buttons are kept invisible, a hidden bar takes clicks only out of combat,
-- and only while it shows on mouse over.
function M:HiddenMouseAllowed(index)
	if not (self:HiddenAlphaFallback() and self:BarHidden(index)) then return true end
	return self.db.bars[index].hiddenMouseover ~= false and not InCombatLockdown()
end

-- With "invisible", clicks on a hidden bar turn off as a fight starts
-- (still allowed at that moment) and back on after it.
local function FallbackMouse(fight)
	if not (M.active and M.bars and M:HiddenAlphaFallback()) then return end
	for index = 3, 8 do
		local header = M.bars[index]
		if header and M:BarHidden(index) then
			local barDB = M.db.bars[index]
			local on = not fight and not barDB.clickThrough and barDB.hiddenMouseover ~= false
			local count = M:BarGrid(index).count
			for slot, button in ipairs(header.buttons) do button:EnableMouse(on and slot <= count) end
		end
	end
end
local events = {}
E:RegisterEvent("PLAYER_REGEN_DISABLED", function() FallbackMouse(true) end, events)
E:RegisterEvent("PLAYER_REGEN_ENABLED", function() FallbackMouse(false) end, events)

-- Does hidden bar `index` show on mouse over out of combat (true), or stay
-- out of sight (false)? Saved per bar; applied out of combat.
function M:SetHiddenBarMouseover(index, on)
	index = tonumber(index)
	local barDB = index and index >= 3 and self.db and self.db.bars and self.db.bars[index]
	if type(barDB) ~= "table" then return false end
	barDB.hiddenMouseover = on and true or false
	E:RunOutOfCombat(function()
		if self.active then self:ApplyChanges() end
	end)
	return true
end

---------------------------------------------------------------------------
-- Shape
---------------------------------------------------------------------------
-- Button size of a hidden bar: a fifth smaller than bar 1's buttons.
local function HiddenSize()
	local bar1 = M.db.bars[1]
	local width = M:ButtonSize(bar1)
	width = width * M.Clamp(bar1.scale, 50, 200, 100) / 100
	return math.max(24, math.min(36, math.floor(width * 0.8 + 0.5)))
end

local function Count(index)
	return math.floor(M.Clamp(M.db.bars[index].buttons, 1, 12, 12))
end

-- The grid a hidden bar draws (see M:BarGrid).
function M:HiddenGrid(index)
	local plan = plans[index]
	local size = plan and plan.size or HiddenSize()
	local count, perRow
	if index == 3 then
		count = math.min(BOX_COUNT, Count(index))
		perRow = BOX
	else
		count = Count(index)
		perRow = (plan and plan.shape == "box") and BOX or 1
	end
	return { count = count, perRow = perRow, width = size, height = size, spacing = SPACING, growth = "TOPLEFT", columns = false, scale = 1 }
end

local function GridSize(count, perRow, size)
	perRow = math.max(1, math.min(count, perRow))
	local rows = math.ceil(count / perRow)
	return perRow * size + (perRow - 1) * SPACING, rows * size + (rows - 1) * SPACING
end

---------------------------------------------------------------------------
-- Where it goes
---------------------------------------------------------------------------
local function MoverName(index) return "EldoUI_ActionBar" .. index end

-- Does a frame of the layout hang from this bar? Then the bar keeps its
-- spot, so that frame does not follow it into the corner.
local function Carries(name, moving)
	local target = name .. "Mover"
	for other in pairs(E.movers) do
		if other ~= name and not moving[other] then
			local pos = E.db.movers[other] or E:GetMoverDefaultPoint(other)
			if type(pos) == "table" and (pos[2] == target or (type(pos.link) == "table" and pos.link.to == name)) then return true end
		end
	end
	return false
end

local function Rect(frame)
	local left, bottom = frame:GetLeft(), frame:GetBottom()
	local width, height = frame:GetWidth(), frame:GetHeight()
	if type(left) ~= "number" or type(bottom) ~= "number" or E:IsSecret(left) or E:IsSecret(width) then return nil end
	if not (width and height and width > 0 and height > 0) then return nil end
	return { l = left, b = bottom, r = left + width, t = bottom + height }
end

local function Overlaps(a, b, pad)
	return a.l < b.r + pad and b.l < a.r + pad and a.b < b.t + pad and b.b < a.t + pad
end

-- Every frame on screen that a hidden bar must keep clear of: the boxes
-- of modules that are on whose box or frame shows (a window's box counts
-- too), except the bars being placed now, and the statues beside the orbs
-- (they stand outside the unit frame's box).
local function InUse(mover)
	if mover:IsShown() then return true end
	local frame = mover.frame
	return not frame or (frame.IsVisible and frame:IsVisible()) and true or false
end

local function Obstacles(moving, region)
	local list = {}
	for name, mover in pairs(E.movers) do
		if not moving[name] and not IGNORE[name] and InUse(mover) then
			local module = mover.module and E.modules[mover.module]
			if not module or module.active then
				local rect = Rect(mover)
				if rect and Overlaps(rect, region, GAP) then list[#list + 1] = rect end
			end
		end
	end
	local statues = E.Orb and E.Orb.StatueFrames and E.Orb.StatueFrames() or {}
	for _, frame in ipairs(statues) do
		local rect = Rect(frame)
		if rect and Overlaps(rect, region, GAP) then list[#list + 1] = rect end
	end
	return list
end

local function Free(rect, obstacles)
	for _, other in ipairs(obstacles) do
		if Overlaps(rect, other, GAP) then return false end
	end
	return true
end

-- The screen EldoUI places on (the centered area on an ultrawide screen
-- limited to 16:9).
local function Screen()
	local anchor = E.GetMoverAnchor and E:GetMoverAnchor("BOTTOMRIGHT") or UIParent
	local rect = Rect(anchor)
	if not rect then
		local width, height = UIParent:GetSize()
		rect = { l = 0, b = 0, r = width or 0, t = height or 0 }
	end
	return rect, anchor
end

-- The bags and the menu: where the corner box goes next to.
local function BagColumn(screen)
	local column
	for _, name in ipairs({ "EldoUI_BagBar", "EldoUI_MicroMenu" }) do
		local mover = E.movers[name]
		local module = mover and mover.module and E.modules[mover.module]
		local rect = mover and mover:IsShown() and (not module or module.active) and Rect(mover)
		if rect then
			if column then
				column = { l = math.min(column.l, rect.l), b = math.min(column.b, rect.b), r = math.max(column.r, rect.r), t = math.max(column.t, rect.t) }
			else
				column = rect
			end
		end
	end
	-- Without either one: where they sit in most layouts.
	return column or { l = screen.r - 609, b = screen.b + 36, r = screen.r - 471, t = screen.b + 68 }
end

local function Distance(a, b)
	local dx = math.max(0, b.l - a.r, a.l - b.r)
	local dy = math.max(0, b.b - a.t, a.b - b.t)
	return dx + dy
end

-- The free spot of `width` x `height` in the bottom-right part of the
-- screen (`across` of its width, `up` of its height, 0.45 by default) that
-- is nearest to `near`, or nil.
local function CornerSpot(width, height, near, obstacles, screen, across, up)
	local w, h = screen.r - screen.l, screen.t - screen.b
	local best, bestScore
	local x0, y1 = screen.r - w * (across or 0.45), screen.b + h * (up or 0.45)
	local x = screen.r - 4 - width
	while x >= x0 do
		local y = screen.b + 4
		while y + height <= y1 do
			local rect = { l = x, b = y, r = x + width, t = y + height }
			local score = Distance(rect, near)
			if (not bestScore or score < bestScore) and Free(rect, obstacles) then best, bestScore = rect, score end
			y = y + STEP
		end
		x = x - STEP
	end
	return best
end

-- A free upright spot at the right edge under the quest list, highest
-- first, or nil.
local function EdgeSpot(width, height, obstacles, screen)
	local top = screen.b + (screen.t - screen.b) * 0.62
	local quests = E.movers.EldoUI_Quests
	local rect = quests and quests:IsShown() and Rect(quests)
	if rect and rect.b > screen.b + height then top = math.min(top, rect.b - GAP) end
	for column = 0, 2 do
		local x = screen.r - EDGE - width - column * (width + GAP)
		local y = top - height
		while y >= screen.b + 4 do
			local spot = { l = x, b = y, r = x + width, t = y + height }
			if Free(spot, obstacles) then return spot end
			y = y - STEP
		end
	end
	return nil
end

-- A point for a spot, measured from the bottom-right corner of the screen.
local function CornerPoint(rect, screen)
	return { "BOTTOMLEFT", "UIParent", "BOTTOMRIGHT", math.floor(rect.l - screen.r + 0.5), math.floor(rect.b - screen.b + 0.5) }
end

local function SamePlan(a, b)
	if not (a and b) then return a == b end
	return a.shape == b.shape and a.size == b.size and a.point[4] == b.point[4] and a.point[5] == b.point[5]
end

-- Pick the spot of every hidden bar 3 to 8. Out of combat only (it moves
-- protected bars). Bars the player dragged, and bars another frame hangs
-- from, keep their own spot.
function M:PlaceHiddenBars()
	if not (self.active and self.db) or InCombatLockdown() then return end
	local moving, changed = {}, {}
	for _, index in ipairs(MOVED) do
		local name = MoverName(index)
		if self.bars[index] and self:BarHidden(index) and not E.db.movers[name] and E.movers[name] then moving[name] = index end
	end
	for name in pairs(moving) do
		if Carries(name, moving) then moving[name] = nil end
	end
	local screen = Screen()
	local region = { l = screen.l + (screen.r - screen.l) * 0.5, b = screen.b, r = screen.r, t = screen.t }
	local placed = {}
	local column = BagColumn(screen)
	for _, index in ipairs(MOVED) do
		local name = MoverName(index)
		local old = plans[index]
		local plan
		if moving[name] then
			local obstacles = Obstacles(moving, region)
			for _, rect in ipairs(placed) do obstacles[#obstacles + 1] = rect end
			-- The bags' own place stays free, also while they are off.
			obstacles[#obstacles + 1] = column
			local size = HiddenSize()
			local count = index == 3 and math.min(BOX_COUNT, Count(index)) or Count(index)
			local spot, shape
			if index ~= 3 then
				-- Upright at the right edge, smaller buttons when it is short.
				for _, tryGrid in ipairs({ size, size - 4, 24 }) do
					local s = math.max(20, tryGrid)
					local width, height = GridSize(count, 1, s)
					spot = EdgeSpot(width, height, obstacles, screen)
					if spot then size, shape = s, "column" break end
				end
			end
			if not spot then
				local near = index == 3 and column or (plans[3] and plans[3].rect) or column
				-- In the corner; when it is crowded, smaller buttons, then
				-- further up the right half of the screen.
				for _, try in ipairs({ { size, 0.45, 0.45 }, { size - 4, 0.45, 0.45 }, { 24, 0.45, 0.45 }, { size, 0.5, 0.9 }, { 24, 0.5, 0.9 } }) do
					local s = math.max(20, try[1])
					local width, height = GridSize(count, BOX, s)
					spot = CornerSpot(width, height, near, obstacles, screen, try[2], try[3])
					if spot then size = s break end
				end
				shape = "box"
				-- Nothing free: next to the bags all the same.
				if not spot then
					local width, height = GridSize(count, BOX, size)
					spot = { l = column.l - GAP - width, b = column.b, r = column.l - GAP, t = column.b + height }
				end
			end
			plan = { shape = shape, size = size, rect = spot, point = CornerPoint(spot, screen) }
			placed[#placed + 1] = spot
		end
		plans[index] = plan
		if not SamePlan(old, plan) then changed[#changed + 1] = index end
	end
	for _, index in ipairs(changed) do
		if self.bars[index] then
			self.LayoutBar(self.bars[index], index)
			E:ApplyMover(MoverName(index))
		end
	end
	if #changed > 0 then M:PublishDockBounds() end
	return changed
end

-- The corner point while the bar is hidden and the player hasn't dragged it.
for _, index in ipairs(MOVED) do
	E:RegisterMoverPointHook(MoverName(index), function()
		local plan = plans[index]
		if plan and M.active and M:BarHidden(index) then return plan.point end
		return nil
	end)
end

-- Every frame is placed again (a layout, a reset, a new screen size): the
-- hidden bars look for their spot once the others stand where they go.
local function Replace()
	if M.active then E:RunOutOfCombat(function() M:PlaceHiddenBars() end) end
end
hooksecurefunc(E, "RefreshMovers", Replace)
hooksecurefunc(E, "ResetMovers", Replace)
hooksecurefunc(E, "ResetMover", Replace)

-- Another frame moved or changed its size on its own (a module turned on,
-- a menu grew): look again once, on the next frame.
local own, again = {}, false
for _, index in ipairs(MOVED) do own[MoverName(index)] = true end
hooksecurefunc(E, "ApplyMover", function(_, name)
	if again or own[name] or not M.active then return end
	again = true
	C_Timer.After(0, function()
		again = false
		Replace()
	end)
end)
