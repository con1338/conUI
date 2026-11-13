-- EldoUI window mover: one engine that moves and scales Blizzard's windows
-- (character, spellbook, friends, quest dialogs, settings, maps, ...).
--
-- Every window in Data/MovableWindows.lua (and every window a module or a
-- plugin registers) works the same way:
--   drag          by the title bar, or by any empty part of the window
--   Ctrl+wheel    over the title bar: scale (per window, within the limits)
--   Shift+right-click on the title bar: back to Blizzard's place
--   Ctrl+right-click on the title bar: back to normal size
--   Alt+drag      on a side panel (the calendar's event window, the raid
--                 info, ...): detach it; Alt+right-click puts it back
-- Each key is a setting, and "Lock windows" turns all of them off.
--
-- Switches: one "Move Blizzard windows" switch on the Move windows page, with
-- a tick per window under it. A window's tick drives its Blizzard UI
-- element: ticking it turns on Move and scale for that element (only Move
-- when the element was off), and turning Move off on the Blizzard UI page
-- unticks the element's windows. So each window keeps its own per-element
-- opt-in, and the player only needs the Move windows page.
--
-- Rules:
--   * A window is only touched while its Blizzard UI switch allows "Move
--     and scale" (E:BlizzardAllowed(element, "move")); every element is
--     opt-in, and the switches are checked again on every drag, wheel,
--     reset and re-apply.
--   * Blizzard places, then EldoUI places: after Blizzard's panel manager
--     (one shared post-hook set on ShowUIPanel, HideUIPanel and
--     UpdateUIPanelPositions), on OnShow and the next frame, after UI scale
--     and display size changes and after loading screens.
--   * Never in combat on a protected window: the work waits in
--     E:RunOutOfCombat, and a drag or wheel is refused.
--   * Blizzard's scripts stay: EldoUI only uses HookScript and
--     hooksecurefunc, its own title strip, and state in local weak tables.
--     Nothing is written into Blizzard frames, panel attributes or Edit
--     Mode data. Edit Mode systems and forbidden frames are refused.
--
-- Positions are saved per profile as the top-left corner in UIParent
-- units, plus the scale: windows[key] = { pos = { x, y }, scale, on,
-- children = { [panel] = { x, y } } }.
--
-- API (also on the global EldoUI for plugins):
--   E:RegisterWindow(def)          a window (see Data/MovableWindows.lua)
--   E:WindowMoverApply([target])   re-check and re-apply: a key, a frame,
--                                  or nil for all
--   E:ResetWindow(key[, what])     what = "position" | "scale" | "all"
--   E:ResetAllWindows([what])
--   E:GetWindowState(key)          read-only copy of the saved state
--   E:IsWindowAllowed(key)         may EldoUI move it right now
--   E:IterateWindows()             key, def, frame (or nil)
--   E:GetWindowFrames(key)         the window and its title strip, once attached
-- Written from scratch for EldoUI; no code from other addons.
local _, E = ...
local L = E.L

local Key = E.Key
local VERSION = 1             -- saved-data format; raises run the migration
local SCALE_FLOOR, SCALE_CEIL = 0.3, 2.5
local CLAMP_MARGIN = 40       -- pixels of a window that stay on screen
local EDGE_SNAP = 12          -- pixels to the screen edge that snap to it
local MODS = { NONE = Key("No key"), SHIFT = Key("Shift"), CTRL = Key("Ctrl"), ALT = Key("Alt") }
local MODS_KEY = { SHIFT = Key("Shift"), CTRL = Key("Ctrl"), ALT = Key("Alt"),
	CTRL_SHIFT = Key("Ctrl+Shift"), CTRL_ALT = Key("Ctrl+Alt"), SHIFT_ALT = Key("Shift+Alt") }
-- Two keys at once: offered for dragging only, where a plain drag of a
-- window by mistake (instead of a click on its button) is what to stop.
local MODS_PAIR = { CTRL_SHIFT = Key("Ctrl+Shift"), CTRL_ALT = Key("Ctrl+Alt"), SHIFT_ALT = Key("Shift+Alt") }

E.defaults.windowMover = {
	enabled = true,          -- "Move Blizzard windows": the one switch for all of them
	lock = false,            -- no drag, scale or reset
	dragMode = "anywhere",   -- title | anywhere
	dragMod = "NONE",        -- key held to drag outside move mode (NONE, a key or a pair from MODS_PAIR)
	scaleMod = "CTRL",       -- key held for wheel scaling and the scale reset
	resetMod = "SHIFT",      -- key held for the position reset (right-click)
	detachMod = "ALT",       -- key held to detach and attach side panels
	hints = true,            -- help tooltip on the title bar
	scaleMin = 0.5,
	scaleMax = 2,
	scaleStep = 0.05,
	fitScreen = true,        -- shrink a window that would be taller than the screen
	remember = "always",     -- always | session | close
	clamp = true,
	snap = 1,                -- grid in pixels for dropped windows
	edgeSnap = true,
	fadeMoving = 1,          -- alpha while the character moves (1 = no fade)
	fadeCombat = 1,          -- alpha in combat (1 = no fade)
	fadeHover = true,        -- full alpha under the mouse
	windows = {},            -- [key] = { on, scale, pos, children, center }
	migrated = 0,
	movesAllowed = false,    -- every window's Move switch was turned on once
}

local defs = {}              -- key -> def
local order = {}             -- keys in registration order
local entries = {}           -- key -> runtime state
local byFrame = setmetatable({}, { __mode = "k" })    -- window -> entry
local presses = setmetatable({}, { __mode = "k" })    -- frame the mouse went down on -> { entry, target }
local childOf = setmetatable({}, { __mode = "k" })    -- side panel -> { entry, path }
local dragging = setmetatable({}, { __mode = "k" })   -- frame being moved -> { entry, path, left, top }
-- A drag normally ends on the mouse-up of the frame it started on. When that
-- frame hides mid-drag (a side panel closes, a tab switches) no mouse-up
-- comes, so while a drag runs the next left-button release anywhere ends it
-- too (the event is watched only then).
local releaseWatch = CreateFrame("Frame")
local function WatchRelease() releaseWatch:RegisterEvent("GLOBAL_MOUSE_UP") end
local busy = setmetatable({}, { __mode = "k" })       -- frames we are placing right now
local faded = setmetatable({}, { __mode = "k" })      -- frames we faded
local session = {}           -- key -> { pos, children } when positions aren't kept in the profile
local moveMode = false
local hooksDone = false
local reapplying = false
local situation = { moving = false, combat = false }
local owner = {}             -- event owner

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local function DB()
	return E.db and E.db.windowMover
end

local function Usable(frame)
	return type(frame) == "table" and type(frame.GetObjectType) == "function"
		and not E.FrameCheck(frame, "IsForbidden")
end

local function Num(value)
	if type(value) ~= "number" then return nil end
	if issecretvalue and issecretvalue(value) then return nil end
	return value
end

local function Try(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then geterrorhandler()(err) end
	return ok
end

-- Protected right now and the game is in combat: hands off.
local function Locked(frame)
	return InCombatLockdown() and frame and E.FrameCheck(frame, "IsProtected") and true or false
end

local function ModDown(mod)
	if mod == "SHIFT" then return IsShiftKeyDown() end
	if mod == "CTRL" then return IsControlKeyDown() end
	if mod == "ALT" then return IsAltKeyDown() end
	if mod == "CTRL_SHIFT" then return IsControlKeyDown() and IsShiftKeyDown() end
	if mod == "CTRL_ALT" then return IsControlKeyDown() and IsAltKeyDown() end
	if mod == "SHIFT_ALT" then return IsShiftKeyDown() and IsAltKeyDown() end
	return true
end

-- A drag may start: always in move mode, else with the "Key to drag" held.
local function DragKeyHeld()
	return moveMode or ModDown(DB().dragMod)
end
E.WindowDragKeyHeld = DragKeyHeld

local function ModText(mod, action)
	local key = MODS_KEY[mod]
	return key and (L[key] .. "+" .. action) or (action:sub(1, 1):upper() .. action:sub(2))
end

-- "Parent.Child.Grandchild" from the globals (parentKeys after the first).
local function Resolve(path)
	if type(path) == "table" then return path end
	if type(path) ~= "string" then return nil end
	local obj
	for part in path:gmatch("[^%.]+") do
		if obj == nil then
			obj = _G[part]
		elseif type(obj) == "table" then
			obj = obj[part]
		else
			return nil
		end
		if obj == nil then return nil end
	end
	return obj
end

-- UIParent units per unit of this frame.
local function Ratio(frame)
	local ui = UIParent:GetEffectiveScale()
	local eff = Num(frame:GetEffectiveScale()) or 1
	return eff / ((ui and ui > 0) and ui or 1)
end

local function CapturePoints(frame)
	local points = {}
	for i = 1, frame:GetNumPoints() do points[i] = { frame:GetPoint(i) } end
	return points
end

local function RestorePoints(frame, points)
	if not points or #points == 0 then return end
	busy[frame] = true
	frame:ClearAllPoints()
	for _, point in ipairs(points) do pcall(frame.SetPoint, frame, unpack(point)) end
	busy[frame] = nil
end

local function Maximized(frame)
	return type(frame.IsMaximized) == "function" and frame:IsMaximized() and true or false
end

local function Round(value, step)
	step = step or 1
	return math.floor(value / step + 0.5) * step
end

---------------------------------------------------------------------------
-- Saved state
---------------------------------------------------------------------------
local function Record(key)
	local db = DB()
	if not db then return nil end
	db.windows = db.windows or {}
	local rec = db.windows[key]
	if type(rec) ~= "table" then
		rec = { on = true, scale = 1 }
		db.windows[key] = rec
	end
	return rec
end

-- Where positions live: the profile, or this session only.
local function Places(key, create)
	local db = DB()
	if not db then return nil end
	if db.remember == "always" then
		if create then return Record(key) end
		return db.windows and db.windows[key]
	end
	if create and not session[key] then session[key] = {} end
	return session[key]
end

local function SavedPos(key)
	local places = Places(key)
	local pos = places and places.pos
	if type(pos) == "table" and Num(pos[1]) and Num(pos[2]) then return pos end
end

local function SavedChild(key, path)
	local places = Places(key)
	local pos = places and type(places.children) == "table" and places.children[path]
	if type(pos) == "table" and Num(pos[1]) and Num(pos[2]) then return pos end
end

local function WantedScale(key)
	local rec = DB() and DB().windows and DB().windows[key]
	local scale = rec and Num(rec.scale) or 1
	if scale <= 0 then scale = 1 end
	return math.max(SCALE_FLOOR, math.min(SCALE_CEIL, scale))
end

-- Only the recap's cooperating pin supplies pre-pin originals. Failed
-- advertised admission stops the operation instead of capturing its holder.
local WindowPin = {}
do
	local baselineDepth = 0
	function WindowPin.BaselineBusy() return baselineDepth ~= 0 end
	function WindowPin.BaselineBoundary(entry, fn, ...)
		if entry.def.key ~= "deathRecap" then return fn(entry, ...) end
		baselineDepth = baselineDepth + 1
		local result = { pcall(fn, entry, ...) }
		baselineDepth = baselineDepth - 1
		if not result[1] then error(result[2], 0) end
		return unpack(result, 2)
	end
	local function Plain(value) return not issecretvalue or not issecretvalue(value) end
	local function Number(value)
		return Plain(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
	end
	function WindowPin.Scale(frame, owns)
		local value = frame:GetScale()
		if owns and (not Number(value) or value <= 0 or not owns()) then error("Death recap window scale is unavailable", 0) end
		return value
	end
	function WindowPin.Ratio(frame, owns)
		if not owns then return Ratio(frame) end
		local effective, root = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
		if not Number(effective) or not Number(root) or effective <= 0 or root <= 0 or not owns() then
			error("Death recap window scale is unavailable", 0)
		end
		return effective / root
	end
	WindowPin.Number = Number
	local anchors = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
		RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
	local function PointsCopy(points)
		if not Plain(points) or type(points) ~= "table" or type(getmetatable(points)) ~= "nil" or #points > 9 then return end
		local count = 0
		for key in pairs(points) do
			if not Number(key) or key < 1 or key > 9 or key % 1 ~= 0 then return end
			count = count + 1
			if count > 9 then return end
		end
		if count ~= #points then return end
		local copy = {}
		for i = 1, count do
			local p = points[i]
			if not Plain(p) or type(p) ~= "table" or type(getmetatable(p)) ~= "nil" then return end
			for field in pairs(p) do
				if not Number(field) or field < 1 or field > 5 or field % 1 ~= 0 then return end
			end
			for field = 1, 5 do if not Plain(p[field]) then return end end
			if type(p[1]) ~= "string" or type(p[3]) ~= "string" or not anchors[p[1]] or not anchors[p[3]]
				or (p[2] ~= nil and type(p[2]) ~= "table") or not Number(p[4]) or not Number(p[5]) then return end
			copy[i] = { p[1], p[2], p[3], p[4], p[5] }
		end
		return copy
	end
	WindowPin.CopyPoints = PointsCopy
	local function EqualPoints(a, b)
		if #a ~= #b then return false end
		for i, p in ipairs(a) do for field = 1, 5 do if p[field] ~= b[i][field] then return false end end end
		return true
	end
	function WindowPin.Context(entry)
		local frame, key = entry.frame, entry.def.key
		local spec = E.BlizzardKeep and E.BlizzardKeep.pins[frame]
		if key ~= "deathRecap" or not spec or spec.windowOriginal == nil then return end
		if type(spec.windowOriginal) ~= "function" or type(spec.admit) ~= "function" then error("Death recap original channels are unavailable", 0) end
		local profile, definition = DB(), entry.def
		local record = profile and profile.windows and profile.windows[key]
		local pos, scale = SavedPos(key), WantedScale(key)
		local x, y = pos and pos[1], pos and pos[2]
		local callback = spec.windowOriginal
		local guard = spec.admit(frame, "window")
		if type(guard) ~= "function" then error("Death recap original channels are unavailable", 0) end
		local function Stable()
			if entries[key] ~= entry or entry.frame ~= frame or entry.def ~= definition or DB() ~= profile
				or (profile.windows and profile.windows[key]) ~= record or E.BlizzardKeep.pins[frame] ~= spec
				or spec.windowOriginal ~= callback or SavedPos(key) ~= pos or WantedScale(key) ~= scale
				or (pos and (pos[1] ~= x or pos[2] ~= y)) then return false end
			return true
		end
		local function Owns() return Stable() and guard() and Stable() end
		if not Owns() then error("Death recap original channel ownership changed", 0) end
		return { frame = frame, spec = spec, callback = callback, owns = Owns }
	end
	function WindowPin.Original(entry, channel)
		local context = WindowPin.Context(entry)
		if not context then return channel == "scale" and entry.frame:GetScale() or CapturePoints(entry.frame) end
		local answer = context.callback(context.frame, channel)
		if not context.owns() or not Plain(answer) or type(answer) ~= "table" or type(getmetatable(answer)) ~= "nil"
			or not Plain(answer.kind) then error("Death recap original channel ownership changed", 0) end
		if answer.kind == "native" then
			local value = channel == "scale" and context.frame:GetScale() or CapturePoints(context.frame)
			if not context.owns() or (channel == "scale" and (not Number(value) or value <= 0)) then
				error("Death recap original channel ownership changed", 0)
			end
			return value
		end
		if answer.kind ~= "original" then error("Death recap original channel is unavailable", 0) end
		if channel == "scale" then
			local current = context.frame:GetScale()
			if not Number(answer.value) or answer.value <= 0 or not Number(answer.applied) or not Number(current) or current ~= answer.applied
				or not context.owns() then error("Death recap original scale is unavailable", 0) end
			return answer.value
		end
		local value, applied = PointsCopy(answer.value), PointsCopy(answer.applied)
		local current = PointsCopy(CapturePoints(context.frame))
		if not value or not applied or not current or not EqualPoints(current, applied) or not context.owns() then
			error("Death recap original anchors are unavailable", 0)
		end
		return value
	end
end

---------------------------------------------------------------------------
-- Rules
---------------------------------------------------------------------------
-- May EldoUI move this window at all right now?
local function Allowed(entry)
	local db = DB()
	if not db or not db.enabled then return false end
	local def = entry.def
	if def.element and not E:BlizzardAllowed(def.element, "move") then return false end
	local rec = db.windows and db.windows[def.key]
	if rec and rec.on == false then return false end
	if def.allowed then
		local ok, yes = pcall(def.allowed)
		if not ok or not yes then return false end
	end
	return true
end

-- May the player drag, scale or reset it right now? (false, reason)
local function CanAct(entry, frame)
	if not Allowed(entry) then return false end
	if Locked(frame or entry.frame) then return false, "combat" end
	if DB().lock and not moveMode then return false, "locked" end
	return true
end

local noticeTime = 0
local function Notice(reason)
	if reason ~= "combat" or GetTime() - noticeTime < 5 then return end
	noticeTime = GetTime()
	E:Print(L["This window can't be moved or scaled in combat."])
end

---------------------------------------------------------------------------
-- Placing
---------------------------------------------------------------------------
local function ClampPos(frame, x, y)
	local db = DB()
	if not (db and db.clamp) then return x, y end
	local ratio = Ratio(frame)
	local width = (Num(frame:GetWidth()) or 0) * ratio
	local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
	x = math.max(-width + CLAMP_MARGIN, math.min(screenW - CLAMP_MARGIN, x))
	y = math.max(CLAMP_MARGIN, math.min(screenH, y))
	return x, y
end

local function SnapPos(frame, x, y)
	local db = DB()
	local grid = db and Num(db.snap) or 1
	if grid > 1 then x, y = Round(x, grid), Round(y, grid) else x, y = Round(x), Round(y) end
	if db and db.edgeSnap then
		local ratio = Ratio(frame)
		local width = (Num(frame:GetWidth()) or 0) * ratio
		local height = (Num(frame:GetHeight()) or 0) * ratio
		local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
		if math.abs(x) < EDGE_SNAP then x = 0 end
		if math.abs(x + width - screenW) < EDGE_SNAP then x = Round(screenW - width) end
		if math.abs(y - screenH) < EDGE_SNAP then y = Round(screenH) end
		if math.abs(y - height) < EDGE_SNAP then y = Round(height) end
	end
	return x, y
end

local function Place(frame, x, y, owns)
	if owns then WindowPin.Ratio(frame, owns) end
	x, y = ClampPos(frame, x, y)
	local ratio = WindowPin.Ratio(frame, owns)
	if owns and not owns("before") then error("Death recap window ownership changed", 0) end
	busy[frame] = true
	local function Write()
		frame:ClearAllPoints()
		if owns and not owns("cleared") then error("Death recap window ownership changed", 0) end
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / ratio, y / ratio)
		if owns and not owns("placed", x / ratio, y / ratio) then error("Death recap window ownership changed", 0) end
	end
	if owns then
		local ok, err = pcall(Write)
		busy[frame] = nil
		if not ok then error(err, 0) end
	else
		Write()
		busy[frame] = nil
	end
end

-- SetScale, then snap the window's skinned edges to the screen pixel at
-- the new scale (the edges are sized for the old one).
local function SetFrameScale(frame, scale, owns)
	frame:SetScale(scale)
	if owns and not owns() then error("Death recap window ownership changed", 0) end
	if E.SnapBorders then E:SnapBorders(frame) end
	if owns and not owns() then error("Death recap window ownership changed", 0) end
end

-- Scale a window and keep its top-left corner where it is.
local function ScaleKeepCorner(frame, scale, owns)
	local old = WindowPin.Scale(frame, owns)
	if owns and not owns() then error("Death recap window ownership changed", 0) end
	if math.abs(old - scale) < 0.001 then return end
	local left = Num(frame:GetLeft())
	if owns and not owns() then error("Death recap window ownership changed", 0) end
	local top = Num(frame:GetTop())
	if owns and not owns() then error("Death recap window ownership changed", 0) end
	busy[frame] = true
	local function Write()
		SetFrameScale(frame, scale, owns)
		if left and top then
			frame:ClearAllPoints()
			if owns and not owns() then error("Death recap window ownership changed", 0) end
			frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / scale, top * old / scale)
			if owns and not owns() then error("Death recap window ownership changed", 0) end
		end
	end
	if owns then
		local ok, err = pcall(Write)
		busy[frame] = nil
		if not ok then error(err, 0) end
	else
		Write()
		busy[frame] = nil
	end
end

-- A window taller than the screen at its scale gets a smaller one (not saved).
local function FitScale(frame, scale, owns)
	local db = DB()
	if not (db and db.fitScreen) then return scale end
	local height = Num(frame:GetHeight())
	local own = Num(WindowPin.Scale(frame, owns))
	if not height or height <= 0 or not own or own <= 0 then return scale end
	local base = WindowPin.Ratio(frame, owns) / own           -- UIParent units per frame unit at scale 1
	local screenH = UIParent:GetHeight()
	if height * scale * base > screenH then
		scale = math.max(SCALE_FLOOR, math.floor(screenH / (height * base) * 100) / 100)
	end
	return scale
end

---------------------------------------------------------------------------
-- Fading by situation (moving, combat); full alpha under the mouse
---------------------------------------------------------------------------
local hoverDriver

local function TargetAlpha(entry)
	local db = DB()
	if entry.def.noAlpha or not db then return 1 end
	local alpha = 1
	if situation.combat then alpha = math.min(alpha, Num(db.fadeCombat) or 1) end
	if situation.moving then alpha = math.min(alpha, Num(db.fadeMoving) or 1) end
	if alpha < 1 and db.fadeHover and entry.frame:IsMouseOver() then alpha = 1 end
	return alpha
end

local function ApplyAlpha(entry)
	local frame = entry.frame
	if not frame then return end
	local alpha = 1
	if frame:IsShown() and Allowed(entry) then alpha = TargetAlpha(entry) end
	if alpha < 1 then
		frame:SetAlpha(alpha)
		faded[frame] = true
	elseif faded[frame] then
		frame:SetAlpha(1)
		faded[frame] = nil
	end
end

local function UpdateAlphas()
	local any = false
	for _, entry in pairs(entries) do
		if entry.attached then
			ApplyAlpha(entry)
			if entry.frame and faded[entry.frame] then any = true end
		end
	end
	local db = DB()
	local watch = any or (db and ((situation.combat and (Num(db.fadeCombat) or 1) < 1)
		or (situation.moving and (Num(db.fadeMoving) or 1) < 1)))
	watch = watch and db and db.fadeHover
	if watch then
		if not hoverDriver then
			hoverDriver = CreateFrame("Frame")
			hoverDriver.elapsed = 0
			hoverDriver:SetScript("OnUpdate", function(self, elapsed)
				self.elapsed = self.elapsed + elapsed
				if self.elapsed < 0.15 then return end
				self.elapsed = 0
				for _, entry in pairs(entries) do
					if entry.attached and entry.frame and entry.frame:IsShown() then ApplyAlpha(entry) end
				end
			end)
		end
		hoverDriver:Show()
	elseif hoverDriver then
		hoverDriver:Hide()
	end
end

---------------------------------------------------------------------------
-- Apply and release
---------------------------------------------------------------------------
local Apply, Release

local function UpdateHandle(entry)
	local handle = entry.handle
	if not handle then return end
	local allowed = Allowed(entry)
	handle:SetShown(allowed)
	local glow = moveMode and allowed
	handle.glow:SetShown(glow)
	handle.label:SetShown(glow)
	if glow then E:AccentTexture(handle.glow, 0.25) end
end

local function Queue(entry)
	if entry.queued then return end
	entry.queued = true
	E:RunOutOfCombat(function()
		entry.queued = false
		Apply(entry)
	end)
end

local function ChildFrame(entry, path)
	local kid = entry.kids and entry.kids[path]
	return kid and kid.frame
end

local function ChildMouseDown(child, button)
	local info = childOf[child]
	if not info or button ~= "LeftButton" then return end
	local entry, db = info.entry, DB()
	local ok, reason = CanAct(entry, child)
	if not ok then Notice(reason) return end
	local kid = entry.kids[info.path]
	if (moveMode or ModDown(db.detachMod)) or SavedChild(entry.def.key, info.path) then
		if not kid.orig then kid.orig = CapturePoints(child) end
		presses[child] = { entry = entry, target = child, path = info.path }
	elseif db.dragMode == "anywhere" and DragKeyHeld() then
		presses[child] = { entry = entry, target = entry.frame }
	end
	local press = presses[child]
	if press then
		local target = press.target
		if Locked(target) then
			presses[child] = nil
			Notice("combat")
			return
		end
		if target == entry.frame and not entry.orig then entry.orig = WindowPin.Original(entry, "points") end
		dragging[target] = { entry = entry, path = press.path, left = Num(target:GetLeft()), top = Num(target:GetTop()) }
		if not target:IsMovable() then target:SetMovable(true) end
		target:StartMoving()
		WatchRelease()
	end
end

local StopDrag

local function ReattachChild(entry, path)
	local kid = entry.kids and entry.kids[path]
	local places = Places(entry.def.key)
	if places and type(places.children) == "table" then places.children[path] = nil end
	local child = kid and kid.frame
	if child and kid.orig then
		if Locked(child) then Queue(entry) return end
		RestorePoints(child, kid.orig)
	end
	if kid then kid.orig = nil end
end

local function ChildMouseUp(child, button)
	local press = presses[child]
	if press then
		presses[child] = nil
		StopDrag(press.target)
		return
	end
	local info = childOf[child]
	if info and button == "RightButton" and ModDown(DB().detachMod) and SavedChild(info.entry.def.key, info.path) then
		if CanAct(info.entry, child) then
			ReattachChild(info.entry, info.path)
			E:Print(L["Panel attached to its window again."])
		end
	end
end

local function ApplyChildren(entry)
	for _, path in ipairs(entry.def.children or {}) do
		entry.kids = entry.kids or {}
		local kid = entry.kids[path]
		if not kid then
			local child = Resolve(path)
			if Usable(child) and not E.FrameCheck(child, "IsProtected") then
				kid = { frame = child }
				entry.kids[path] = kid
				childOf[child] = { entry = entry, path = path }
				child:HookScript("OnMouseDown", ChildMouseDown)
				child:HookScript("OnMouseUp", ChildMouseUp)
				child:HookScript("OnHide", function(self) if dragging[self] then StopDrag(self) end end)
				child:HookScript("OnShow", function()
					C_Timer.After(0, function() if entry.frame and entry.frame:IsShown() then Apply(entry) end end)
				end)
			end
		end
		local child = kid and kid.frame
		local pos = child and SavedChild(entry.def.key, path)
		if pos and child:IsShown() and not dragging[child] and not Locked(child) then
			if not kid.orig then kid.orig = CapturePoints(child) end
			Place(child, pos[1], pos[2])
		end
	end
end

local function ApplyNowBody(entry)
	local frame, key = entry.frame, entry.def.key
	local context = WindowPin.Context(entry)
	local owns = context and context.owns
	local pos = SavedPos(key)
	local wanted = WantedScale(key)
	-- Scale 1 means "Blizzard's own size": a window EldoUI never scaled
	-- keeps the size Blizzard gave it (the panel manager shrinks some to fit).
	local scale
	if math.abs(wanted - 1) < 0.001 then
		scale = entry.origScale
		entry.origScale = nil
	else
		scale = FitScale(frame, wanted, owns)
		if entry.origScale == nil and math.abs(WindowPin.Scale(frame, owns) - scale) > 0.001 then entry.origScale = WindowPin.Original(entry, "scale") end
	end
	if scale and math.abs(WindowPin.Scale(frame, owns) - scale) > 0.001 then
		if pos then
			busy[frame] = true
			if owns then
				local ok, err = pcall(SetFrameScale, frame, scale, owns)
				busy[frame] = nil
				if not ok then error(err, 0) end
			else
				SetFrameScale(frame, scale)
				busy[frame] = nil
			end
		else
			ScaleKeepCorner(frame, scale, owns)
		end
	end
	-- A center offset carried over from the old System windows format.
	local rec = DB().windows[key]
	if not pos and rec and type(rec.center) == "table" and Num(rec.center[1]) and Num(rec.center[2]) then
		local ratio = Ratio(frame)
		local width, height = (Num(frame:GetWidth()) or 0) * ratio, (Num(frame:GetHeight()) or 0) * ratio
		local x = UIParent:GetWidth() / 2 + rec.center[1] - width / 2
		local y = UIParent:GetHeight() / 2 + rec.center[2] + height / 2
		rec.pos = { Round(x), Round(y) }
		rec.center = nil
		pos = SavedPos(key)
	end
	if pos then
		if not entry.orig then entry.orig = WindowPin.Original(entry, "points") end
		Place(frame, pos[1], pos[2], owns)
		entry.applied = true
	end
	ApplyChildren(entry)
	ApplyAlpha(entry)
end

local function ApplyNow(entry) return WindowPin.BaselineBoundary(entry, ApplyNowBody) end

function Apply(entry)
	local frame = entry.frame
	if not entry.attached or not frame then return end
	UpdateHandle(entry)
	if not Allowed(entry) then
		Release(entry)
		return
	end
	if not frame:IsShown() or dragging[frame] then return end
	if Locked(frame) then
		Queue(entry)
		return
	end
	if entry.def.maximized and Maximized(frame) then
		if entry.origScale and math.abs(frame:GetScale() - entry.origScale) > 0.001 then
			busy[frame] = true
			SetFrameScale(frame, entry.origScale)
			busy[frame] = nil
		end
		return
	end
	Try(ApplyNow, entry)
end

-- Give the window back to Blizzard: its scale, its place (Blizzard places
-- it again the next time it opens anyway), panels attached.
local function ReleaseBody(entry)
	local frame = entry.frame
	if not frame then return end
	if entry.handle then entry.handle:Hide() end
	local kidsOut = false
	for _, kid in pairs(entry.kids or {}) do
		if kid.orig then kidsOut = true end
	end
	if not (entry.origScale or entry.applied or kidsOut or faded[frame]) then return end
	if Locked(frame) then
		Queue(entry)
		return
	end
	if faded[frame] then
		frame:SetAlpha(1)
		faded[frame] = nil
	end
	if entry.origScale then
		if math.abs(frame:GetScale() - entry.origScale) > 0.001 then ScaleKeepCorner(frame, entry.origScale) end
		entry.origScale = nil
	end
	if entry.applied and entry.orig then RestorePoints(frame, entry.orig) end
	entry.applied, entry.orig = false, nil
	for _, kid in pairs(entry.kids or {}) do
		if kid.orig and kid.frame and not Locked(kid.frame) then
			RestorePoints(kid.frame, kid.orig)
			kid.orig = nil
		end
	end
end

function Release(entry) return WindowPin.BaselineBoundary(entry, ReleaseBody) end

local function ReapplyShown()
	if reapplying then return end
	reapplying = true
	for _, key in ipairs(order) do
		local entry = entries[key]
		if entry and entry.attached and entry.frame:IsShown() then Apply(entry) end
	end
	reapplying = false
end

---------------------------------------------------------------------------
-- Dragging, wheel and reset
---------------------------------------------------------------------------
local function StartDrag(entry, frame)
	local ok, reason = CanAct(entry, frame)
	if not ok then
		Notice(reason)
		return
	end
	if dragging[frame] then return end
	if frame == entry.frame and not entry.orig then entry.orig = WindowPin.Original(entry, "points") end
	dragging[frame] = { entry = entry, left = Num(frame:GetLeft()), top = Num(frame:GetTop()) }
	if not frame:IsMovable() then frame:SetMovable(true) end
	frame:StartMoving()
	WatchRelease()
end

function StopDrag(frame)
	local drag = frame and dragging[frame]
	if not drag then return end
	dragging[frame] = nil
	frame:StopMovingOrSizing()
	-- EldoUI keeps the place, not the game's layout cache.
	if frame.SetUserPlaced then pcall(frame.SetUserPlaced, frame, false) end
	local entry = drag.entry
	local left, top = Num(frame:GetLeft()), Num(frame:GetTop())
	if not left or not top then return end
	if drag.left and drag.top and math.abs(left - drag.left) < 1 and math.abs(top - drag.top) < 1 then
		-- A click, not a drag: nothing to remember.
		if entry.frame:IsShown() then Apply(entry) end
		return
	end
	local ratio = Ratio(frame)
	local x, y = SnapPos(frame, left * ratio, top * ratio)
	x, y = ClampPos(frame, x, y)
	local places = Places(entry.def.key, true)
	if drag.path then
		places.children = type(places.children) == "table" and places.children or {}
		places.children[drag.path] = { x, y }
	else
		places.pos = { x, y }
	end
	Apply(entry)
end

local function SetScaleOf(entry, scale)
	local rec = Record(entry.def.key)
	rec.scale = Round(math.max(SCALE_FLOOR, math.min(SCALE_CEIL, scale)), 0.01)
	Apply(entry)
end

local function Wheel(entry, delta)
	local db = DB()
	if not (moveMode or ModDown(db.scaleMod)) then return end
	local ok, reason = CanAct(entry)
	if not ok then
		Notice(reason)
		return
	end
	local low, high = Num(db.scaleMin) or 0.5, Num(db.scaleMax) or 2
	if low > high then low, high = high, low end
	local step = Num(db.scaleStep) or 0.05
	local current = WantedScale(entry.def.key)
	local scale = math.max(low, math.min(high, current + (delta > 0 and step or -step)))
	SetScaleOf(entry, scale)
end

local ShowHint

local function RightClick(entry, from)
	local db = DB()
	local ok, reason = CanAct(entry)
	if not ok then
		Notice(reason)
		return
	end
	local did = false
	if ModDown(db.resetMod) and db.resetMod ~= "NONE" then
		E:ResetWindow(entry.def.key, "position")
		did = true
	end
	if ModDown(db.scaleMod) and db.scaleMod ~= "NONE" then
		E:ResetWindow(entry.def.key, "scale")
		did = true
	end
	if did and from and from.entry and from:IsMouseOver() then ShowHint(from) end
end

---------------------------------------------------------------------------
-- The title strip (an EldoUI frame) and the mouse hooks
---------------------------------------------------------------------------
function ShowHint(handle)
	local entry = handle and handle.entry
	local db = DB()
	if not entry or not db or E.FrameCheck(GameTooltip, "IsForbidden") then return end
	if not (db.hints or moveMode) then return end
	GameTooltip:SetOwner(handle, "ANCHOR_TOP")
	GameTooltip:SetText(entry.def.title and L[entry.def.title] or L["Window"], 1, 1, 1)
	if Locked(entry.frame) then
		GameTooltip:AddLine(L["Can't be moved or scaled in combat."], E:TokenColor("warn", true))
	elseif db.lock and not moveMode then
		GameTooltip:AddLine(L["Windows are locked (/eui windows unlock)."], E:TokenColor("warn", true))
	else
		local children = entry.def.children and #entry.def.children > 0
		E:TooltipHint(GameTooltip,
			{ ModText(moveMode and "NONE" or db.dragMod, L["drag"]), L["move"] },
			{ ModText(db.scaleMod, L["mouse wheel"]), L["scale (%d%%)"]:format(WantedScale(entry.def.key) * 100 + 0.5) },
			{ ModText(db.resetMod, L["right-click"]), L["Blizzard's place"] },
			{ ModText(db.scaleMod, L["right-click"]), L["normal size"] },
			children and { ModText(db.detachMod, L["drag a side panel"]), L["detach it"] } or nil)
	end
	GameTooltip:Show()
end

local function HandleRegion(frame, spec)
	if spec == nil then
		if Usable(frame.TitleContainer) then return frame.TitleContainer end
		if Usable(frame.Header) then return frame.Header end
	elseif spec == "Header" and Usable(frame.Header) then
		return frame.Header
	end
end

local function MakeHandle(entry)
	local frame, spec = entry.frame, entry.def.drag
	local host = frame
	if type(spec) == "table" and spec.parent and Usable(frame[spec.parent]) then host = frame[spec.parent] end
	local handle = CreateFrame("Frame", nil, host)
	handle.entry = entry
	local region = HandleRegion(frame, spec)
	if region then
		handle:SetPoint("TOPLEFT", region, "TOPLEFT")
		handle:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT")
	else
		spec = type(spec) == "table" and spec or {}
		handle:SetPoint("TOPLEFT", host, "TOPLEFT", spec.left or 58, spec.top or -1)
		if spec.width then
			handle:SetWidth(spec.width)
		else
			handle:SetPoint("TOPRIGHT", host, "TOPRIGHT", -(spec.right or 50), spec.top or -1)
		end
		handle:SetHeight(spec.height or 22)
	end
	handle:SetFrameLevel(host:GetFrameLevel() + (type(spec) == "table" and spec.level or 2))
	handle:EnableMouse(true)
	handle:EnableMouseWheel(true)
	handle:RegisterForDrag("LeftButton")
	handle:SetScript("OnDragStart", function()
		if DragKeyHeld() then StartDrag(entry, frame) end
	end)
	handle:SetScript("OnDragStop", function() StopDrag(frame) end)
	handle:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then RightClick(entry, self) end
	end)
	handle:SetScript("OnMouseWheel", function(self, delta)
		Wheel(entry, delta)
		if self:IsMouseOver() then ShowHint(self) end
	end)
	handle:SetScript("OnEnter", ShowHint)
	handle:SetScript("OnLeave", function() if not E.FrameCheck(GameTooltip, "IsForbidden") then GameTooltip:Hide() end end)
	handle:SetScript("OnHide", function() if dragging[frame] then StopDrag(frame) end end)
	-- Move mode: an accent strip and a label on the title bar.
	handle.glow = handle:CreateTexture(nil, "OVERLAY")
	handle.glow:SetAllPoints()
	handle.glow:Hide()
	handle.label = E:CreateText(handle, E.tokens.size.small, "CENTER")
	handle.label:SetPoint("CENTER")
	handle.label:SetText(L["Drag to move (EldoUI)"])
	handle.label:Hide()
	entry.handle = handle
	UpdateHandle(entry)
end

-- "Anywhere" mode: a press on the window's background (or a registered
-- sub-frame) drags it. Post-hooks only; Blizzard's own handlers run first.
local function FrameMouseDown(frame, button)
	local entry = byFrame[frame]
	local host = entry and entry.frame
	if not host then return end
	local db = DB()
	if button ~= "LeftButton" or db.dragMode ~= "anywhere" then return end
	if not DragKeyHeld() then return end
	presses[frame] = { entry = entry, target = host }
	StartDrag(entry, host)
	if not dragging[host] then presses[frame] = nil end
end

-- The frame's own mouse-up goes first; whatever drag is still running one
-- frame after the release lost its frame and ends here.
releaseWatch:SetScript("OnEvent", function(self, _, button)
	if button ~= "LeftButton" then return end
	self:UnregisterEvent("GLOBAL_MOUSE_UP")
	C_Timer.After(0, function()
		for frame in pairs(dragging) do StopDrag(frame) end
		for frame, press in pairs(presses) do
			if not dragging[press.target] then presses[frame] = nil end
		end
	end)
end)

local function FrameMouseUp(frame, button)
	local press = presses[frame]
	if press then
		presses[frame] = nil
		StopDrag(press.target)
		return
	end
	local entry = byFrame[frame]
	if entry and button == "RightButton" and DB().dragMode == "anywhere" then RightClick(entry) end
end

local subHandles = setmetatable({}, { __mode = "k" }) -- sub-frame -> entry
local function SubMouseDown(frame, button)
	local entry = subHandles[frame]
	if not entry then return end
	local db = DB()
	if button ~= "LeftButton" or db.dragMode ~= "anywhere" or not DragKeyHeld() then return end
	presses[frame] = { entry = entry, target = entry.frame }
	StartDrag(entry, entry.frame)
	if not dragging[entry.frame] then presses[frame] = nil end
end

local function HookHandles(entry)
	for _, path in ipairs(entry.def.handles or {}) do
		local sub = Resolve(path)
		if Usable(sub) and not subHandles[sub] and not E.FrameCheck(sub, "IsProtected") then
			subHandles[sub] = entry
			sub:HookScript("OnMouseDown", SubMouseDown)
			sub:HookScript("OnMouseUp", FrameMouseUp)
		end
	end
end

local function OnShow(frame)
	local entry = byFrame[frame]
	if not entry then return end
	HookHandles(entry)
	UpdateHandle(entry)
	Apply(entry)
	-- Blizzard's panel manager may place the window right after it shows.
	C_Timer.After(0, function() Apply(entry) end)
end

local function OnHide(frame)
	local entry = byFrame[frame]
	if not entry then return end
	if dragging[frame] then StopDrag(frame) end
	entry.applied, entry.orig = false, nil
	if DB() and DB().remember == "close" then session[entry.def.key] = nil end
	if faded[frame] then
		frame:SetAlpha(1)
		faded[frame] = nil
	end
end

local function PinHook(frame)
	if busy[frame] then return end
	local entry = byFrame[frame]
	if not entry or not SavedPos(entry.def.key) or not Allowed(entry) then return end
	if entry.def.maximized and Maximized(frame) then return end
	Apply(entry)
end

local function InstallHooks()
	if hooksDone then return end
	hooksDone = true
	-- After Blizzard's panel manager (these run after the secure placement).
	for _, name in ipairs({ "ShowUIPanel", "HideUIPanel", "UpdateUIPanelPositions", "UpdateScaleForFitForOpenPanels" }) do
		if type(_G[name]) == "function" then hooksecurefunc(name, ReapplyShown) end
	end
end

local function IsEditModeSystem(frame)
	return rawget(frame, "system") ~= nil and rawget(frame, "systemIndex") ~= nil
end

local function Attach(entry)
	if entry.attached then return true end
	local def = entry.def
	local frame = Resolve(def.frame)
	if not Usable(frame) then
		if not def.silent and not entry.missingNoted then
			entry.missingNoted = true
			E:Debug(("Window mover: %s is not on this client."):format(tostring(def.frame)))
		end
		return false
	end
	if IsEditModeSystem(frame) or (byFrame[frame] and byFrame[frame] ~= entry) then return false end
	entry.frame = frame
	entry.attached = true
	byFrame[frame] = entry
	InstallHooks()
	MakeHandle(entry)
	frame:HookScript("OnShow", OnShow)
	frame:HookScript("OnHide", OnHide)
	if not E.FrameCheck(frame, "IsProtected") then
		frame:HookScript("OnMouseDown", FrameMouseDown)
		frame:HookScript("OnMouseUp", FrameMouseUp)
	end
	HookHandles(entry)
	if def.pin then hooksecurefunc(frame, "SetPoint", PinHook) end
	if def.maximized then
		for _, method in ipairs({ "Maximize", "Minimize" }) do
			if type(frame[method]) == "function" then
				hooksecurefunc(frame, method, function()
					if method == "Maximize" then
						Apply(entry)
					else
						C_Timer.After(0, function() Apply(entry) end)
					end
				end)
			end
		end
	end
	return true
end

-- Attach (once the element allows it and the frame exists) and re-apply.
local function Refresh(entry)
	local def = entry.def
	if not entry.attached then
		local db = DB()
		local rec = db and db.windows and db.windows[def.key]
		local wanted = db and db.enabled and (not def.element or E:BlizzardAllowed(def.element, "move"))
			and not (rec and rec.on == false)
		if not wanted then return end
		if def.addon and not C_AddOns.IsAddOnLoaded(def.addon) then
			if not entry.waiting then
				entry.waiting = true
				E:OnBlizzardAddOn(def.addon, function()
					entry.waiting = false
					Refresh(entry)
				end)
			end
			return
		end
		if not Attach(entry) then return end
	end
	UpdateHandle(entry)
	if entry.frame:IsShown() then
		Apply(entry)
	elseif not Allowed(entry) then
		Release(entry)
	end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
function E:RegisterWindow(def)
	if type(def) ~= "table" or type(def.key) ~= "string" or def.frame == nil then return nil end
	if def.element and not (self.blizzardElements and self.blizzardElements[def.element]) then
		self:Debug(("Window mover: unknown element %s for %s"):format(tostring(def.element), def.key))
		return nil
	end
	if not defs[def.key] then order[#order + 1] = def.key end
	defs[def.key] = def
	local entry = entries[def.key]
	if entry then
		entry.def = def
	else
		entry = { def = def }
		entries[def.key] = entry
	end
	E.defaults.windowMover.windows[def.key] = { on = true, scale = 1 }
	local db = DB()
	if db then
		db.windows = db.windows or {}
		db.windows[def.key] = E.ApplyDefaults(type(db.windows[def.key]) == "table" and db.windows[def.key] or {}, { on = true, scale = 1 })
	end
	if self.windowMoverReady then Refresh(entry) end
	if self.windowPage then self:BuildWindowPage() end
	return entry
end

local function Targets(target)
	local list = {}
	if target == nil then
		for _, key in ipairs(order) do list[#list + 1] = entries[key] end
	elseif type(target) == "table" then
		if byFrame[target] then list[1] = byFrame[target] end
	elseif entries[target] then
		list[1] = entries[target]
	end
	return list
end

function E:WindowMoverApply(target)
	if not self.windowMoverReady then return end
	for _, entry in ipairs(Targets(target)) do Try(Refresh, entry) end
	UpdateAlphas()
end

-- Back to Blizzard's place ("position"), normal size ("scale"), or both.
local function ResetWindowBody(self, key, what)
	what = what or "all"
	local entry = entries[key]
	if not entry then return end
	if what ~= "scale" then
		for _, places in ipairs({ DB() and DB().windows[key], session[key] }) do
			if type(places) == "table" then
				places.pos, places.center, places.children = nil, nil, nil
			end
		end
		local frame = entry.frame
		if frame then
			if Locked(frame) then
				Queue(entry)
			else
				if entry.orig then RestorePoints(frame, entry.orig) end
				entry.applied, entry.orig = false, nil
				for path, kid in pairs(entry.kids or {}) do
					if kid.orig then ReattachChild(entry, path) end
				end
			end
		end
	end
	if what ~= "position" then
		local rec = Record(key)
		if rec then rec.scale = 1 end
	end
	Apply(entry)
end

function E:ResetWindow(key, what)
	local entry = entries[key]
	if not entry then return end
	return WindowPin.BaselineBoundary(entry, function() return ResetWindowBody(self, key, what) end)
end

function E:ResetAllWindows(what)
	for _, key in ipairs(order) do self:ResetWindow(key, what) end
	wipe(session)
	if what == "scale" then
		self:Print(L["Every window is back to its normal size."])
	else
		self:Print(L["Every window goes back to Blizzard's place."])
	end
end

-- The original is where the window was before EldoUI moved it, not where
-- it is now. A reset halfway through never passes off an empty anchor in
-- between as the game's own.
function E:WindowMoverPinOriginal(frame, channel)
	local function Result(kind, value) return { kind = kind, value = value } end
	if (issecretvalue and (issecretvalue(frame) or issecretvalue(channel))) or (channel ~= "scale" and channel ~= "points")
		or WindowPin.BaselineBusy() or busy[frame] then return Result("unavailable") end
	local entry = entries.deathRecap
	if not entry then return Result("native") end
	if type(getmetatable(entry)) ~= "nil" then return Result("unavailable") end
	local attached = entry.attached
	if (issecretvalue and issecretvalue(attached)) or (attached ~= nil and type(attached) ~= "boolean") then
		return Result("unavailable")
	end
	if not attached and entry.frame == nil and entry.origScale == nil and entry.orig == nil then return Result("native") end
	if entry.frame ~= frame or not entry.attached then return Result("unavailable") end
	local profile, rootProfile, definition = DB(), E.db, entry.def
	local originalScale, originalPoints = entry.origScale, entry.orig
	local function Stable()
		return E.db == rootProfile and DB() == profile and entries.deathRecap == entry
			and entry.frame == frame and entry.attached and entry.def == definition and not WindowPin.BaselineBusy()
	end
	if channel == "scale" then
		if originalScale == nil then return Stable() and Result("native") or Result("unavailable") end
		local current = entry.origScale
		if not WindowPin.Number(originalScale) or originalScale <= 0 or not WindowPin.Number(current)
			or not Stable() or current ~= originalScale then return Result("unavailable") end
		return Result("original", originalScale)
	end
	if originalPoints == nil then
		if entry.applied then return Result("unavailable") end
		return Stable() and Result("native") or Result("unavailable")
	end
	local copy = WindowPin.CopyPoints(originalPoints)
	if not copy or not Stable() or entry.orig ~= originalPoints then return Result("unavailable") end
	return Result("original", copy)
end

-- A one-use return guard for the recap's feature-owned scale. The saved
-- UIParent position stays owned by this entry and is normalized by Place.
function E:WindowMoverPinReturn(frame, spec, channels)
	local entry = entries.deathRecap
	if not entry or entry.frame ~= frame or not entry.attached or not Allowed(entry)
		or not channels.scale or channels.points or not SavedPos("deathRecap") or not entry.applied then return end
	local profile, rootProfile = DB(), E.db
	local record, pos = DB().windows.deathRecap, SavedPos("deathRecap")
	local x, y, requested = pos[1], pos[2], WantedScale("deathRecap")
	local originalScale, originalPoints = entry.origScale, entry.orig
	local pointsCopy = originalPoints and WindowPin.CopyPoints(originalPoints)
	if originalPoints and not pointsCopy then error("Death recap original anchors are unavailable", 0) end
	local release = spec.releaseAdmit
	if type(release) ~= "function" or E.BlizzardKeep.pins[frame] ~= spec then error("Death recap return ownership is unavailable", 0) end
	local guard = release(frame)
	if type(guard) ~= "function" then error("Death recap return ownership is unavailable", 0) end
	local function SamePoints(expected)
		if frame:GetNumPoints() ~= #expected then return false end
		for i, point in ipairs(expected) do
			local actual = { frame:GetPoint(i) }
			for field = 1, 5 do
				if issecretvalue and issecretvalue(actual[field]) then return false end
				if actual[field] ~= point[field] then return false end
			end
		end
		return true
	end
	local function Stable(released)
		if E.db ~= rootProfile or DB() ~= profile or entries.deathRecap ~= entry or entry.frame ~= frame
			or not entry.attached or not entry.applied or profile.windows.deathRecap ~= record
			or SavedPos("deathRecap") ~= pos or pos[1] ~= x or pos[2] ~= y or WantedScale("deathRecap") ~= requested
			or entry.origScale ~= originalScale or entry.orig ~= originalPoints or spec.releaseAdmit ~= release
			or (released and E.BlizzardKeep.pins[frame] ~= nil)
			or (not released and E.BlizzardKeep.pins[frame] ~= spec) then return false end
		if pointsCopy then
			if #originalPoints ~= #pointsCopy then return false end
			for i, p in ipairs(pointsCopy) do for field = 1, 5 do if originalPoints[i][field] ~= p[field] then return false end end end
		end
		return true
	end
	local function Owns(released) return Stable(released) and guard() and Stable(released) end
	if not Owns(false) then error("Death recap return ownership changed", 0) end
	local original = E:BlizzardPinOriginal(frame, spec, "scale")
	local ratio, scale = WindowPin.Ratio(frame, function() return Owns(false) end), Num(frame:GetScale())
	local cx, cy = ClampPos(frame, x, y)
	local before = { { "TOPLEFT", UIParent, "BOTTOMLEFT", cx / ratio, cy / ratio } }
	if not original or not Num(original.scale) or not scale or not SamePoints(before) or not Owns(false) then
		error("Death recap saved-position ownership is unavailable", 0)
	end
	local used = false
	return function()
		if used then error("Death recap return was already consumed", 0) end
		used = true
		local function After(phase, px, py)
			if not Owns(true) then return false end
			local current = frame:GetScale()
			if not WindowPin.Number(current) or current ~= original.scale then return false end
			local expected = before
			if phase == "cleared" then expected = {}
			elseif phase == "placed" then expected = { { "TOPLEFT", UIParent, "BOTTOMLEFT", px, py } } end
			return SamePoints(expected) and Owns(true)
		end
		if Locked(frame) or not After("before") then error("Death recap return ownership changed", 0) end
		Place(frame, x, y, After)
	end
end

function E:GetWindowState(key)
	local db = DB()
	local rec = db and db.windows and db.windows[key]
	local places = Places(key)
	return {
		on = not (rec and rec.on == false),
		scale = WantedScale(key),
		pos = places and places.pos and CopyTable(places.pos) or nil,
		children = places and type(places.children) == "table" and CopyTable(places.children) or nil,
		attached = entries[key] and entries[key].attached or false,
		allowed = entries[key] and Allowed(entries[key]) or false,
	}
end

-- May EldoUI move this window right now (main switch, its tick, its
-- Blizzard UI element)? The economy windows ask before they place.
function E:IsWindowAllowed(key)
	local entry = entries[key]
	return entry ~= nil and Allowed(entry) or false
end

-- The window and EldoUI's title strip on it (nil until it is attached).
function E:GetWindowFrames(key)
	local entry = entries[key]
	if entry and entry.attached then return entry.frame, entry.handle end
end

function E:IterateWindows()
	local i = 0
	return function()
		i = i + 1
		local key = order[i]
		if key then return key, defs[key], entries[key].frame end
	end
end

---------------------------------------------------------------------------
-- The window ticks and the Blizzard UI switches
---------------------------------------------------------------------------
-- Move on or off per element, as last seen, per profile table: a change
-- of an element's Move switch carries over to its windows' ticks.
local lastMoveOf = setmetatable({}, { __mode = "k" })

local function LastMove()
	local db = DB()
	if not db then return {} end
	lastMoveOf[db] = lastMoveOf[db] or {}
	return lastMoveOf[db]
end

-- Turn on Move and scale for one element. A switch that was off comes on
-- with only Move: no skin and no extras.
local function AllowElementMove(id)
	local data = id and E.blizzardElements[id]
	if not (data and data.allowed.move) or E:BlizzardAllowed(id, "move") then return end
	local state = E:BlizzardState(id)
	if not state then return end
	LastMove()[id] = true -- the element's other windows keep their ticks
	if not state.enabled then
		for _, action in ipairs({ "skin", "hide", "replace", "improve" }) do
			if data.allowed[action] then state[action] = false end
		end
	end
	E:SetBlizzardElement(id, "move", true)
	if not state.enabled then E:SetBlizzardElement(id, "enabled", true) end
end

-- Follow the Blizzard UI switches into the window ticks: an element whose
-- Move switch is off has its windows unticked; one that just came on
-- ticks them. `id` = one element, nil = all. The first look at a profile
-- (login, profile switch) also carries older saves over: a window counts
-- as ticked only when its own tick and its element's Move were both on.
function E:SyncWindowSwitches(id)
	local db = DB()
	if not (db and type(db.windows) == "table") then return end
	local last = LastMove()
	local seen = {}
	for _, key in ipairs(order) do
		local element = defs[key].element
		if element and (not id or element == id) then
			local now = self:BlizzardAllowed(element, "move")
			local before = last[element]
			if seen[element] == nil then seen[element] = now end
			if before ~= nil and before ~= now then
				Record(key).on = now
			elseif not now then
				local rec = db.windows[key]
				if type(rec) == "table" then rec.on = false else Record(key).on = false end
			end
		end
	end
	for element, now in pairs(seen) do last[element] = now end
end

-- After a change on the Move windows page: every ticked window gets Move and
-- scale on its element (while "Move Blizzard windows" is on), then all
-- windows re-apply.
function E:ApplyWindowSwitches()
	local db = DB()
	if db and db.enabled and type(db.windows) == "table" then
		for _, key in ipairs(order) do
			local element = defs[key].element
			local rec = db.windows[key]
			if element and not (type(rec) == "table" and rec.on == false) then AllowElementMove(element) end
		end
	end
	self:SyncWindowSwitches()
	self:WindowMoverApply()
end

-- Every window ticked, and Move and scale on for each window's Blizzard
-- UI switch (the installer's Recommended setup, and "Move every window").
function E:AllowAllWindowMoves()
	local db = DB()
	if db then
		db.windows = type(db.windows) == "table" and db.windows or {}
		for _, key in ipairs(order) do Record(key).on = true end
	end
	for _, key in ipairs(order) do AllowElementMove(defs[key].element) end
	self:SyncWindowSwitches()
	self:WindowMoverApply()
end

---------------------------------------------------------------------------
-- One-time move of the positions the old per-module movers saved:
--   Window Skins   positions[key] = { x, y }, windows[key].scale
--   Character      position = { x, y }, scale
--   Social         windows[key] = { pos = { x, y }, scale }
--   NPC windows    positions[frameName] = { x, y }, one scale for all
--   System windows positions[key] = CENTER offset { x, y }, scale[key]
--   Maps           worldMap.position / scale, flight.taxiPosition /
--                  flightMapPosition / scale
-- Each profile is moved the first time it is used.
---------------------------------------------------------------------------
local NPC_KEYS = { QuestFrame = "quest", GossipFrame = "gossip", ItemTextFrame = "itemText", TabardFrame = "tabard",
	GuildRegistrarFrame = "guildRegistrar", PetitionFrame = "petition", PetStableFrame = "stable" }
local SKIN_KEYS = { "spells", "professions", "trainer", "legacy", "achievements", "collections", "socketing", "interaction", "dressup", "inspect" }
local SYSTEM_KEYS = { "gameMenu", "settings", "addonList", "macro", "clickBinding" }

function E:MigrateWindowPositions(profile)
	profile = profile or self.db
	if type(profile) ~= "table" then return end
	profile.windowMover = type(profile.windowMover) == "table" and profile.windowMover or {}
	local wm = profile.windowMover
	if (tonumber(wm.migrated) or 0) >= VERSION then return end
	wm.windows = type(wm.windows) == "table" and wm.windows or {}
	local modules = type(profile.modules) == "table" and profile.modules or {}
	local function Point(value)
		if type(value) == "table" and tonumber(value[1]) and tonumber(value[2]) then
			return { tonumber(value[1]), tonumber(value[2]) }
		end
	end
	local function Put(key, pos, scale)
		local rec = type(wm.windows[key]) == "table" and wm.windows[key] or {}
		wm.windows[key] = rec
		pos = Point(pos)
		if pos and not rec.pos then rec.pos = pos end
		scale = tonumber(scale)
		if scale and scale > 0 and math.abs(scale - 1) > 0.001 and (rec.scale == nil or rec.scale == 1) then rec.scale = scale end
		return rec
	end
	local function Tab(t, key)
		return type(t) == "table" and type(t[key]) == "table" and t[key] or nil
	end

	local skins = Tab(modules, "Skins")
	if skins then
		local windows = Tab(skins, "windows")
		for _, key in ipairs(SKIN_KEYS) do
			local win = Tab(windows, key)
			Put(key, Tab(skins, "positions") and skins.positions[key], win and win.scale)
			if win then win.scale = nil end
		end
		skins.positions, skins.dragWindows = nil, nil
	end
	local character = Tab(modules, "Character")
	if character then
		Put("character", character.position, character.scale)
		character.position, character.scale, character.dragWindow = nil, nil, nil
	end
	local social = Tab(modules, "Social")
	if social and Tab(social, "windows") then
		for key, win in pairs(social.windows) do
			if type(win) == "table" then Put(key, win.pos, win.scale) end
		end
		social.windows = nil
	end
	local npc = Tab(modules, "NPCWindows")
	if npc then
		local positions = Tab(npc, "positions")
		for name, key in pairs(NPC_KEYS) do Put(key, positions and positions[name], npc.scale) end
		Put("playerChoice", nil, npc.scale)
		npc.positions, npc.scale = nil, nil
	end
	local system = Tab(modules, "SystemUI")
	if system then
		local scales, positions = Tab(system, "scale"), Tab(system, "positions")
		for _, key in ipairs(SYSTEM_KEYS) do
			local rec = Put(key, nil, scales and scales[key])
			local center = Point(positions and positions[key])
			if center and not rec.pos then rec.center = center end
			if scales then scales[key] = nil end
		end
		system.positions, system.dragWindows = nil, nil
	end
	local maps = Tab(modules, "Maps")
	if maps then
		local world, flight = Tab(maps, "worldMap"), Tab(maps, "flight")
		if world then
			Put("worldMap", world.position, world.scale)
			world.position, world.scale = nil, nil
		end
		if flight then
			Put("taxi", flight.taxiPosition, flight.scale)
			Put("flightMap", flight.flightMapPosition, flight.scale)
			flight.taxiPosition, flight.flightMapPosition, flight.scale = nil, nil, nil
		end
	end
	wm.migrated = VERSION
end

-- The Merchant, Mail, Trade and Auction House pages kept their own
-- "Window scale" before these windows joined the window mover. The scale
-- moves here once per profile; a scale already set on the Move windows page wins.
local ECONOMY_SCALES = { Merchant = "merchant", Mail = "mail", Trade = "trade", Auction = "auctionHouse" }

function E.MigrateEconomyScales(profile)
	if type(profile) ~= "table" then return end
	local modules = type(profile.modules) == "table" and profile.modules or nil
	if not modules then return end
	for module, key in pairs(ECONOMY_SCALES) do
		local db = type(modules[module]) == "table" and modules[module] or nil
		local scale = db and tonumber(db.windowScale)
		if db then db.windowScale = nil end
		if scale and scale > 0 and math.abs(scale - 1) > 0.001 then
			profile.windowMover = type(profile.windowMover) == "table" and profile.windowMover or {}
			local wm = profile.windowMover
			wm.windows = type(wm.windows) == "table" and wm.windows or {}
			local rec = type(wm.windows[key]) == "table" and wm.windows[key] or { on = true }
			wm.windows[key] = rec
			if rec.scale == nil or math.abs((tonumber(rec.scale) or 1) - 1) < 0.001 then
				rec.scale = math.max(SCALE_FLOOR, math.min(SCALE_CEIL, scale))
			end
		end
	end
end
E:RegisterProfileMigration(E.MigrateEconomyScales, "economyWindowScale", 1)

-- Called by E:SetProfile once the new profile is in E.db.
function E:WindowMoverProfileChanged()
	wipe(session)
	for _, key in ipairs(order) do
		E.db.windowMover.windows[key] = E.ApplyDefaults(type(E.db.windowMover.windows[key]) == "table"
			and E.db.windowMover.windows[key] or {}, { on = true, scale = 1 })
	end
	self:SyncWindowSwitches()
	self:WindowMoverApply()
end

---------------------------------------------------------------------------
-- Options: General settings, then the windows by Blizzard UI category
---------------------------------------------------------------------------
local GROUPS = {
	{ label = "Character and progression", categories = { character = true } },
	{ label = "Social", categories = { social = true, notifications = true } },
	{ label = "World and NPCs", categories = { map = true, economy = true } },
	{ label = "System", categories = { system = true, chat = true, combat = true } },
}

local function ModValues(withNone, withPairs)
	local values = {}
	for key, label in pairs(MODS) do
		if withNone or key ~= "NONE" then values[key] = label end
	end
	if withPairs then
		for key, label in pairs(MODS_PAIR) do values[key] = label end
	end
	return values
end

-- One tick per window, with its scale and reset in the gear.
local function WindowRows(options, key)
	local def = defs[key]
	local data = def.element and E.blizzardElements[def.element]
	local note = def.unsure and " " .. L["It may not exist on every Forever build."] or ""
	if def.protected then note = note .. " " .. L["It moves out of combat only."] end
	if def.children and #def.children > 0 then note = note .. " " .. L["Alt+drag its side panels to detach them."] end
	local desc = L["Let EldoUI move and scale this window."] .. note
	if data then desc = desc .. " " .. L["Also turns on Move and scale for %s in Blizzard UI."]:format(L[data.title]) end
	table.insert(options, { type = "toggle", key = "windows." .. key .. ".on", label = def.title or key, dependsOn = "enabled",
		keywords = data and data.title or nil, desc = desc })
	table.insert(options, { type = "range", percent = true, key = "windows." .. key .. ".scale", label = "Scale", min = SCALE_FLOOR, max = SCALE_CEIL, step = 0.05,
		cog = true, desc = "Size of this window. The mouse wheel on its title bar changes it too." })
	table.insert(options, { type = "execute", label = "Blizzard's place", cog = true, testSafe = true,
		desc = "Puts this window back where Blizzard places it and attaches its side panels again.",
		func = function() E:ResetWindow(key, "position") end })
end

local function SwitchOptions()
	return {
		{ type = "tab", label = "Windows" },
		{ type = "description", label = "Drag Blizzard's windows where you want them and scale them with the mouse wheel. Uncheck a window to leave it to Blizzard." },
		{ type = "toggle", key = "enabled", label = "Move Blizzard windows",
			desc = "The one switch for every window below. Off: EldoUI leaves every Blizzard window where Blizzard places it, at its own size. Your ticks stay for when you turn it on again." },
		{ type = "execute", label = "Check every window", dependsOn = "enabled",
			desc = "Checks every window below, so EldoUI may move all of them. Their Blizzard UI switches come on with only Move and scale where they were off: no skin and no extras.",
			func = function() E:AllowAllWindowMoves(); E:RefreshConfig() end },
		{ type = "toggle", key = "lock", label = "Lock windows", dependsOn = "enabled",
			desc = "No dragging, scaling or resetting until you unlock them. Saved places still apply. Also /eui windows lock." },
		{ type = "select", key = "dragMod", label = "Key to drag", values = ModValues(true, true), dependsOn = "enabled",
			desc = "Hold this key (or both keys) to drag a window, so a slipped click, on a quest's Accept button for example, never moves it. No key: a plain drag moves it. Move mode needs no key." },
	}
end

local function BehaviorOptions()
	return {
		{ type = "tab", label = "Behavior" },
		{ type = "header", label = "Mouse and keys" },
		{ type = "select", key = "dragMode", label = "Drag by", dependsOn = "enabled",
			values = { title = "The title bar", anywhere = "Any empty part of the window" },
			desc = "Where a press starts a drag. Windows with secure parts always drag by the title bar." },
		{ type = "select", key = "scaleMod", label = "Key to scale", values = ModValues(true), dependsOn = "enabled",
			desc = "Hold it and turn the mouse wheel over the title bar to scale the window; with a right-click it sets the normal size again." },
		{ type = "select", key = "resetMod", label = "Key to reset", values = ModValues(false), dependsOn = "enabled",
			desc = "Hold it and right-click the title bar to put the window back where Blizzard places it." },
		{ type = "select", key = "detachMod", label = "Key to detach side panels", values = ModValues(false), cog = true,
			desc = "Hold it and drag a side panel (calendar events, raid info, macro icons, ...) to place it on its own; with a right-click it goes back." },
		{ type = "toggle", key = "hints", label = "Help on the title bar", cog = true,
			desc = "Pointing at a movable window's title bar lists the keys and the window's scale." },

		{ type = "header", label = "Scale" },
		{ type = "range", key = "scaleMin", label = "Smallest scale", percent = true, min = SCALE_FLOOR, max = 1, step = 0.05, dependsOn = "enabled",
			desc = "The mouse wheel stops at this size." },
		{ type = "range", key = "scaleMax", label = "Largest scale", percent = true, min = 1, max = SCALE_CEIL, step = 0.05, dependsOn = "enabled",
			desc = "The mouse wheel stops at this size." },
		{ type = "range", percent = true, key = "scaleStep", label = "Wheel step", min = 0.01, max = 0.2, step = 0.01, cog = true,
			desc = "How much one notch of the mouse wheel changes the scale." },
		{ type = "toggle", key = "fitScreen", label = "Fit tall windows on screen", cog = true,
			desc = "A window that would be taller than the screen at its scale is shown a little smaller. Its saved scale stays." },

		{ type = "header", label = "Placing" },
		{ type = "select", key = "remember", label = "Remember places", dependsOn = "enabled",
			values = { always = "Always (in the profile)", session = "Until you log out", close = "Until the window closes" },
			desc = "Always keeps dragged places in the profile. The others forget them at logout or when the window closes. Scales are always kept." },
		{ type = "toggle", key = "clamp", label = "Keep windows on screen", dependsOn = "enabled",
			desc = "At least 40 pixels of every window stay on screen, so you can always grab it again." },
		{ type = "range", key = "snap", label = "Grid", min = 1, max = 32, step = 1, dependsOn = "enabled",
			desc = "A dropped window's corner lands on this grid, in pixels. 1 places it freely." },
		{ type = "toggle", key = "edgeSnap", label = "Snap to screen edges", cog = true,
			desc = "A window dropped close to a screen edge sits flush against it." },

		{ type = "header", label = "Fading" },
		{ type = "range", key = "fadeMoving", label = "While you move", percent = true, min = 0.1, max = 1, step = 0.05, dependsOn = "enabled",
			desc = "Opacity of open windows while your character moves. 100 % keeps them solid." },
		{ type = "range", key = "fadeCombat", label = "In combat", percent = true, min = 0.1, max = 1, step = 0.05, dependsOn = "enabled",
			desc = "Opacity of open windows in combat. 100 % keeps them solid. The world map keeps its own fade." },
		{ type = "toggle", key = "fadeHover", label = "Solid under the mouse", cog = true,
			desc = "A faded window becomes solid while you point at it." },

		{ type = "header", label = "Reset" },
		{ type = "execute", label = "Reset all positions",
			desc = "Every window goes back to where Blizzard places it, side panels attached.",
			func = function() E:ConfirmWindowsReset() end },
		{ type = "execute", label = "Reset all scales", testSafe = true, confirm = true,
			desc = "Every window back to its normal size.",
			func = function() E:ResetAllWindows("scale") end },
	}
end

function E:BuildWindowPage()
	local options = SwitchOptions()
	-- The windows under the switch, grouped like the Blizzard UI page.
	for _, group in ipairs(GROUPS) do
		local rows = {}
		for _, category in ipairs(self.blizzardCategories or {}) do
			if group.categories[category.id] then
				for _, id in ipairs(self.blizzardElementOrder) do
					if self.blizzardElements[id].category == category.id then
						for _, key in ipairs(order) do
							if defs[key].element == id then WindowRows(rows, key) end
						end
					end
				end
			end
		end
		if #rows > 0 then
			-- A group of windows folds away once its ticks are set.
			table.insert(options, { type = "header", label = group.label, fold = true })
			for _, row in ipairs(rows) do table.insert(options, row) end
		end
	end
	local plugins = {}
	for _, key in ipairs(order) do
		if not defs[key].element then WindowRows(plugins, key) end
	end
	if #plugins > 0 then
		table.insert(options, { type = "header", label = "Plugin windows", fold = true })
		for _, row in ipairs(plugins) do table.insert(options, row) end
	end
	for _, row in ipairs(BehaviorOptions()) do table.insert(options, row) end
	if self.windowPage then
		self.windowPage.options = options
		self.windowPage.tabs = nil
		return self.windowPage
	end
	local page = self:RegisterConfigPage("windows", "Move windows", options,
		function() return E.db.windowMover end,
		function() E:ApplyWindowSwitches() end, 1.65)
	page.desc = L["Move and scale Blizzard's windows: drag, mouse wheel, reset, side panels."]
	page.defaults = function() return E.defaults.windowMover end
	self.windowPage = page
	return page
end

-- The question on the shared dialog shell (E:ShowConfirm).
function E:ConfirmWindowsReset()
	return self:ShowConfirm({ title = L["Reset window positions"], text = L["Put every Blizzard window back where Blizzard places it?"],
		accept = YES, cancel = NO, danger = true, onAccept = function() E:ResetAllWindows("position") end })
end

E:AddCommand("windows", "[lock | unlock | reset | list]  move and scale Blizzard windows", function(arg)
	local word = strtrim((arg or ""):lower())
	local db = DB()
	if word == "lock" or word == "unlock" then
		db.lock = word == "lock"
		E:Print(db.lock and L["Windows locked."] or L["Windows unlocked."])
		E:WindowMoverApply()
	elseif word == "reset" then
		E:ConfirmWindowsReset()
	elseif word == "list" then
		for key, def, frame in E:IterateWindows() do
			local state = E:GetWindowState(key)
			print(("   %s  %s%s  %d%%%s"):format(key, def.title and L[def.title] or "",
				state.allowed and "" or " " .. E:TextHex("secondary") .. L["(not allowed)"] .. "|r", state.scale * 100 + 0.5,
				frame and "" or " " .. E:TextHex("secondary") .. L["(not loaded)"] .. "|r"))
		end
	else
		E:ToggleConfig("windows")
	end
end, "Layout & frames")

---------------------------------------------------------------------------
-- Start-up and events
---------------------------------------------------------------------------
for _, def in ipairs(E.movableWindowData or {}) do E:RegisterWindow(def) end

-- Element switches: each window's Blizzard UI element re-applies its windows.
local function ApplyElementWindows(id)
	Try(E.SyncWindowSwitches, E, id)
	if not E.windowMoverReady then return end
	for _, key in ipairs(order) do
		if defs[key].element == id then Try(Refresh, entries[key]) end
	end
	UpdateAlphas()
end

local seenElements = {}
for _, key in ipairs(order) do
	local id = defs[key].element
	if id and not seenElements[id] then
		seenElements[id] = true
		E:RegisterBlizzardHandler(id, {
			apply = function() ApplyElementWindows(id) end,
			undo = function() ApplyElementWindows(id) end,
		})
	end
end

-- Move mode: an accent strip on the title bar of every movable window,
-- and dragging needs no key.
hooksecurefunc(E, "ToggleMoveMode", function()
	moveMode = E:IsMoveMode() and true or false
	for _, entry in pairs(entries) do UpdateHandle(entry) end
end)

-- Before 0.6.5001 the installer turned on Move and scale only for the
-- character window, so the map, spellbook, friends and group finder never
-- moved. Characters that already ran the installer get every window
-- allowed once; the Blizzard UI switches turn single ones off again. Only
-- installs from before that version: an install since then (or a skipped
-- one) already chose its Blizzard UI switches, and they stay as chosen.
local FIRST_FIXED = { 0, 6, 5001 }

local function InstalledBeforeFix(installed)
	if installed == true then return true end -- the oldest saves kept a flag
	if type(installed) ~= "string" then return false end
	local parts = {}
	for number in installed:gmatch("%d+") do parts[#parts + 1] = tonumber(number) end
	if #parts == 0 then return false end -- "skipped", "dev"
	for index, fixed in ipairs(FIRST_FIXED) do
		local part = parts[index] or 0
		if part ~= fixed then return part < fixed end
	end
	return false
end
E.WindowMovesInstalledBeforeFix = InstalledBeforeFix -- read-only

function E:AllowWindowMovesOnce()
	local wm = self.db and self.db.windowMover
	if not wm or wm.movesAllowed then return end
	local installed = EldoUIDB and EldoUIDB.installed and EldoUIDB.installed[self.charKey]
	if not installed then return end
	wm.movesAllowed = true
	if InstalledBeforeFix(installed) then self:AllowAllWindowMoves() end
end

E:RegisterEvent("PLAYER_LOGIN", function()
	E.windowMoverReady = true
	E:BuildWindowPage()
	E:WindowMoverApply()
	Try(E.AllowWindowMovesOnce, E)
	Try(E.SyncWindowSwitches, E)
end, owner, "modules")

local function Later()
	C_Timer.After(0, ReapplyShown)
end
for _, event in ipairs({ "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "LOADING_SCREEN_DISABLED" }) do
	E:RegisterEvent(event, Later, owner)
end

E:RegisterEvent("PLAYER_REGEN_DISABLED", function()
	situation.combat = true
	for frame in pairs(dragging) do
		if E.FrameCheck(frame, "IsProtected") then StopDrag(frame) end
	end
	UpdateAlphas()
end, owner)
E:RegisterEvent("PLAYER_REGEN_ENABLED", function()
	situation.combat = false
	UpdateAlphas()
end, owner)
E:RegisterEvent("PLAYER_STARTED_MOVING", function()
	situation.moving = true
	UpdateAlphas()
end, owner)
E:RegisterEvent("PLAYER_STOPPED_MOVING", function()
	situation.moving = false
	UpdateAlphas()
end, owner)
