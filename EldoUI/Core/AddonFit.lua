-- EldoUI addon fit: the active layout places and sizes the frames of other
-- addons the player uses, so a loot window, a rare popup or a bag window
-- of another addon sits in a designed spot of the layout and follows every
-- layout switch.
--
-- A slot is a spot every layout has for one kind of frame (the rare card,
-- the bag corner, the edge bar). Most slots are the spot of an EldoUI
-- frame that does the same job: while the player keeps another addon for
-- that job, EldoUI's frame stands back and the other addon's frame takes
-- its place. Each slot has an invisible named frame, EldoUI_Fit<Slot>,
-- that sits on the slot's mover (or, while that mover's module is off, on
-- the spot the mover would have), so an addon can also anchor to it by
-- name.
--
-- An adapter tells the engine how to place one addon (Data/AddonFit.lua;
-- plugins can add their own):
--
--   EldoUI:RegisterAddonFit("<id>", {         -- the adapter's id: the kind of
--                                              -- addon it places ("bags", "loot")
--       folder  = "<AddOn folder>",            -- the addon it places (the id when
--                                              -- left out)
--       title   = <the addon's name>,          -- shown on the Other addons page
--       version = <release checked>,           -- the newest release checked
--       job     = "Bags" or "Module.feature",  -- optional: the EldoUI job it
--                                              -- replaces; placed only while the
--                                              -- player keeps the addon for it
--       frames  = {                            -- one row per frame it places
--           { slot = "bags", frame = "GlobalName" or function() end,
--             point = "BOTTOMRIGHT",            -- the corner laid on the slot's (CENTER)
--             ready = function(frame) end,      -- optional: false while the addon
--                                               -- is not done with it yet
--             free  = function() end,           -- optional: false or a reason while
--                                               -- the spot is not free for it
--             measure = function(frame) end,    -- optional: width, height, scale of
--                                               -- what shows (another frame hangs on it)
--             scale = function(frame, s) end,   -- optional: the addon's own scale
--             place = function(frame, x, y, s) end, -- optional: put it there itself
--             noScale = true,                   -- optional: never scaled (edge bars)
--             noPull = true,                    -- optional: a drag of it never moves the
--                                               -- slot's mover (a small part of a bigger spot)
--             after = { "UpdatePosition" },     -- optional: the frame's own methods that
--                                               -- put it back on the addon's spot; the
--                                               -- fit places it again after each
--           },
--       },
--       watch = { "ToggleAllBags" },           -- optional: global functions after
--                                              -- which frames built on first use
--                                              -- are looked for again
--       changes = { key = change },            -- optional: changes to the addon's
--                                              -- own saved position, Apply and Undo
--                                              -- on the Other addons page (the
--                                              -- change model of Modules/Integrations.lua)
--       managed = function() return state end, -- optional: an addon a module places
--                                              -- itself (a damage meter, boss
--                                              -- warnings): the engine
--                                              -- only reports its state
--   })
--
-- Rules:
--   * Presentation only: an adapter changes where a frame is and how big,
--     never what it shows, and reads no combat data.
--   * Out of combat and never during a boss encounter: every move waits.
--   * Hook, never replace: post-hooks and the addon's public functions only.
--   * Reversible: a value written into another addon's saved settings is a
--     change the player applies, with Undo.
--   * Two switches: the whole layer and each addon (Other addons page,
--     /eui addons fit). Live placement is on for the addons the player has.
--   * No hard dependency: a missing frame or function leaves that addon
--     alone, and the page says "not placed".
--   * The player's own moves win: when the player drags the addon's frame,
--     the slot's mover follows; without a mover the frame stays where they
--     put it until they pick a layout again.
--   * Every frame read that can be secret (GetRect, GetPoint, GetScale,
--     GetEffectiveScale) is checked first; a secret answer leaves the
--     frame alone.
--   * The box rule: an occupant keeps its own size while it fits its slot;
--     a larger one is scaled down to the slot, never up and never below
--     75 %. One that would need less keeps its size and is noted in
--     /eui diag as a layout question.
local _, E = ...
local L = E.L

local Key = E.Key

local Fit = {
	adapters = {},  -- id -> adapter
	order = {},     -- ids in the order registered (the ranking order)
	slots = {},     -- key -> slot
	slotOrder = {},
	frames = {},    -- slot key -> its EldoUI_Fit<Slot> frame
	placed = {},    -- slot key -> id of the occupant
	notes = {},     -- id -> lines for /eui diag
}
E.addonFit = Fit

local MIN_SCALE = 0.75 -- the lowest scale the box rule may give
local EMPTY = {}

---------------------------------------------------------------------------
-- Settings: account-wide, like the player's picks on the Other addons page.
--   enabled  the whole layer
--   off      id -> true for an addon the player keeps out of the fit
--   told     id -> true once the first-placement notice showed
--   placed   id -> { row index -> true } for frames the fit has placed
---------------------------------------------------------------------------
E:RegisterGlobal("addonFit", { enabled = true, off = {}, told = {}, placed = {} }, { title = "Layout spots for other addons" })

local function Store()
	local store = E.GetGlobal and E:GetGlobal("addonFit")
	if type(store) ~= "table" then return nil end
	if type(store.off) ~= "table" then store.off = {} end
	if type(store.told) ~= "table" then store.told = {} end
	if type(store.placed) ~= "table" then store.placed = {} end
	return store
end

-- Has the fit placed this row's frame before (this session or an earlier
-- one)? Only a frame it has not placed yet is asked whether the player
-- placed it.
function Fit:PlacedBefore(adapter, row)
	local store = Store()
	local rows = store and store.placed[adapter.id]
	return type(rows) == "table" and rows[row.index] == true
end

local function NotePlaced(adapter, row)
	local store = Store()
	if not store then return end
	local rows = store.placed[adapter.id]
	if type(rows) ~= "table" then
		rows = {}
		store.placed[adapter.id] = rows
	end
	rows[row.index] = true
end

function Fit:LayerOn()
	local store = Store()
	return store ~= nil and store.enabled ~= false
end

-- The player's switch for one addon, whatever the layer's switch says.
function Fit:AddonSwitch(id)
	local store = Store()
	return store == nil or not store.off[id]
end

function Fit:AddonOn(id)
	local store = Store()
	return store ~= nil and store.enabled ~= false and not store.off[id]
end

---------------------------------------------------------------------------
-- Slots
---------------------------------------------------------------------------
--   Fit:RegisterSlot(key, {
--       mover    = "EldoUI_RareAlert",       -- the mover whose spot it is
--       title    = <a Key() text>,           -- in the player's words
--       box      = { 280, 88 },              -- 1440-canvas units, while the mover is
--                                            -- missing or has no size
--       corner   = "BOTTOMRIGHT",            -- optional: a corner, not a box; the
--                                            -- occupant grows away from it
--       fallback = { "CENTER", "UIParent", "CENTER", 0, 0 }, -- where the spot is
--                                            -- when no point of the layout is found
--       module, feature                      -- optional: the EldoUI job of the spot
--   })
function Fit:RegisterSlot(key, slot)
	if type(key) ~= "string" or type(slot) ~= "table" or type(slot.mover) ~= "string" then return nil end
	slot.key = key
	E:TranslateFields({ slot }, "title")
	if not self.slots[key] then self.slotOrder[#self.slotOrder + 1] = key end
	self.slots[key] = slot
	return slot
end

local function FrameName(key)
	return "EldoUI_Fit" .. key:gsub("^%l", string.upper)
end

-- The slot's own frame: named, invisible and never mouse-enabled.
function Fit:SlotFrame(key)
	local frame = self.frames[key]
	if frame then return frame end
	local slot = self.slots[key]
	if not slot then return nil end
	frame = CreateFrame("Frame", FrameName(key), UIParent)
	frame:EnableMouse(false)
	frame:SetSize(slot.box and slot.box[1] or 40, slot.box and slot.box[2] or 40)
	frame.slot = key
	self.frames[key] = frame
	return frame
end

-- The frame a layout point hangs from: UIParent, or another mover that
-- exists; nil when the chain target is missing.
local function Relative(name)
	if name == nil or name == "UIParent" then return UIParent end
	local frame = type(name) == "string" and rawget(_G, name)
	if type(frame) == "table" and type(frame.GetObjectType) == "function" then return frame end
	return nil
end

-- Puts the slot frame on the slot's mover, or on the spot that mover would
-- have (the player's dragged spot, the role's, the layout's), else on the
-- slot's fallback point.
function Fit:LaySlot(key)
	local slot, frame = self.slots[key], self:SlotFrame(key)
	if not (slot and frame) then return nil end
	local ratio = E.GetLayoutRatio and E:GetLayoutRatio() or 1
	local mover = E.movers[slot.mover]
	frame:ClearAllPoints()
	if mover and mover:GetLeft() then
		frame:SetAllPoints(mover)
		frame.onMover = true
		return frame
	end
	frame.onMover = nil
	if slot.box then frame:SetSize(slot.box[1] * ratio, slot.box[2] * ratio) end
	local point = E.db and E.db.movers and E.db.movers[slot.mover]
	if type(point) ~= "table" or type(point[1]) ~= "string" then
		point = E.GetMoverDefaultPoint and E:GetMoverDefaultPoint(slot.mover) or nil
	end
	local relative = type(point) == "table" and Relative(point[2])
	if relative and type(point[4]) == "number" and type(point[5]) == "number" then
		frame:SetPoint(point[1], relative, point[3] or point[1], point[4], point[5])
	else
		local spot = slot.fallback or { "CENTER", "UIParent", "CENTER", 0, 0 }
		frame:SetPoint(spot[1], UIParent, spot[3], spot[4] * ratio, spot[5] * ratio)
	end
	return frame
end

---------------------------------------------------------------------------
-- Secret-safe reads of another addon's frame
---------------------------------------------------------------------------
local function Usable(frame)
	return type(frame) == "table" and type(frame.GetObjectType) == "function"
		and not E.FrameCheck(frame, "IsForbidden")
end
Fit.Usable = Usable

-- The frame's size in its own units and its scale relative to UIParent, or
-- nil when one of them is secret (or the frame has no size yet).
local function Measure(frame)
	local width, height = E.PlainCallAll(frame.GetSize, frame)
	local effective = E.PlainCall(frame.GetEffectiveScale, frame)
	local own = E.PlainCall(frame.GetScale, frame)
	if type(width) ~= "number" or type(height) ~= "number" or type(effective) ~= "number" or type(own) ~= "number" then return nil end
	if width < 1 or height < 1 or effective <= 0 or own <= 0 then return nil end
	return width, height, effective / UIParent:GetEffectiveScale(), own
end
Fit.Measure = Measure

-- A frame's rectangle in UIParent units, or nil when it is secret.
function Fit.RectOf(frame)
	local left, bottom, width, height = E.PlainCallAll(frame.GetRect, frame)
	local effective = E.PlainCall(frame.GetEffectiveScale, frame)
	if type(left) ~= "number" or type(bottom) ~= "number" or type(width) ~= "number" or type(height) ~= "number"
		or type(effective) ~= "number" then return nil end
	local scale = effective / UIParent:GetEffectiveScale()
	return left * scale, bottom * scale, width * scale, height * scale, scale
end

-- The frame's own points, or nil when it has none or one is secret. Read
-- before the fit first moves a frame, so Release can put it back.
local function PointsOf(frame)
	local count = E.PlainCall(frame.GetNumPoints, frame)
	if type(count) ~= "number" or count < 1 then return nil end
	local points = {}
	for index = 1, count do
		local point, relativeTo, relativePoint, x, y = E.PlainCallAll(frame.GetPoint, frame, index)
		if type(point) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then return nil end
		points[index] = { point, relativeTo, relativePoint or point, x, y }
	end
	return points
end
Fit.PointsOf = PointsOf

-- Where `point` of a rectangle is, in the same units.
local function PointOf(point, left, bottom, width, height)
	local x, y = left + width / 2, bottom + height / 2
	if point:find("LEFT") then x = left elseif point:find("RIGHT") then x = left + width end
	if point:find("BOTTOM") then y = bottom elseif point:find("TOP") then y = bottom + height end
	return x, y
end
Fit.PointOf = PointOf

---------------------------------------------------------------------------
-- Adapters
---------------------------------------------------------------------------
function E:RegisterAddonFit(id, adapter)
	if type(id) ~= "string" or id == "" or type(adapter) ~= "table" then return nil end
	adapter.id = id
	adapter.folder = type(adapter.folder) == "string" and adapter.folder or id
	adapter.title = adapter.title or adapter.folder
	adapter.frames = type(adapter.frames) == "table" and adapter.frames or {}
	for index, row in ipairs(adapter.frames) do row.index = index end
	if not Fit.adapters[id] then Fit.order[#Fit.order + 1] = id end
	Fit.adapters[id] = adapter
	adapter.state = adapter.state or {}
	return adapter
end

local function Loaded(folder)
	return C_AddOns.IsAddOnLoaded(folder) and true or false
end

-- The frame of a row right now, or nil.
local function RowFrame(row)
	local frame = row.frame
	if type(frame) == "function" then
		local ok, result = pcall(frame)
		frame = ok and result or nil
	elseif type(frame) == "string" then
		frame = rawget(_G, frame)
	end
	return Usable(frame) and frame or nil
end
Fit.RowFrame = RowFrame

local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d = pcall(fn, ...)
	if not ok then
		geterrorhandler()(a)
		return nil
	end
	return a, b, c, d
end

-- Does EldoUI stand back for this adapter's job, for this addon? A job of
-- a module that is not loaded, or no job at all, counts as yes.
function Fit:Kept(adapter)
	local job = adapter.job
	if type(job) ~= "string" then return true end
	local module, feature = job:match("^([^%.]+)%.?(.*)$")
	if feature == "" then feature = nil end
	if not E.modules[module] then return true end
	return E:CompetitorHolds(adapter.folder, module, feature)
end

local function Note(adapter, line)
	local notes = Fit.notes[adapter.id] or {}
	Fit.notes[adapter.id] = notes
	for _, old in ipairs(notes) do
		if old == line then return end
	end
	notes[#notes + 1] = line
	if #notes > 6 then table.remove(notes, 1) end
end

---------------------------------------------------------------------------
-- Placing
---------------------------------------------------------------------------
-- The scale the box rule gives a frame of `width` x `height` (UIParent
-- units at its scale now) in the slot frame: 1 when it fits, the factor
-- that makes it fit while that is at least 75 %, else nil (too big: it
-- keeps its size).
function Fit.BoxScale(slot, slotFrame, width, height)
	local boxWidth, boxHeight
	if slot.corner then
		-- A corner: the room from the corner to the far screen edges, less
		-- the top band the layout keeps clear.
		local left, bottom, w, h = Fit.RectOf(slotFrame)
		if not left then return 1 end
		local x, y = PointOf(slot.corner, left, bottom, w, h)
		local ratio = E.GetLayoutRatio and E:GetLayoutRatio() or 1
		local top = UIParent:GetHeight() - (slot.topBand or 120) * ratio
		boxWidth = slot.corner:find("RIGHT") and x or (UIParent:GetWidth() - x)
		boxHeight = slot.corner:find("BOTTOM") and (top - y) or y
	else
		boxWidth, boxHeight = slotFrame:GetSize()
	end
	if not (boxWidth and boxHeight) or boxWidth <= 0 or boxHeight <= 0 then return 1 end
	local fit = math.min(1, boxWidth / width, boxHeight / height)
	if fit >= 1 - 1e-3 then return 1 end
	if fit < MIN_SCALE then return nil end
	return fit
end

-- Which point of the frame goes where: row.point names the frame's point
-- (or is a function(frame) that returns it, the slot's point and an offset
-- in 1440-canvas units); else the slot's corner, else the centers.
function Fit.Spot(row, slot, frame, left, bottom, width, height)
	local point, to, dx, dy = row.point, row.to, nil, nil
	if type(point) == "function" then point, to, dx, dy = Call(point, frame) end
	point = type(point) == "string" and point or slot.corner or "CENTER"
	to = type(to) == "string" and to or point
	local ratio = E.GetLayoutRatio and E:GetLayoutRatio() or 1
	local x, y = PointOf(to, left, bottom, width, height)
	return point, to, x + (tonumber(dx) or 0) * ratio, y + (tonumber(dy) or 0) * ratio
end

-- Places one row's frame on its slot. Returns true, or false and a reason.
function Fit:PlaceRow(adapter, row, frame)
	local slot = self.slots[row.slot]
	if not slot then return false, "missing" end
	local slotFrame = self:LaySlot(row.slot)
	local left, bottom, width, height = self.RectOf(slotFrame)
	if not left then return false, "secret" end
	local w, h, scale, own = Measure(frame)
	if not w then return false, "secret" end
	local state = adapter.state
	state.base = state.base or {}
	local base = state.base[row.index]
	if not base then
		base = own
		state.base[row.index] = base
	end
	-- What shows at the frame's own scale, before any fit, in UIParent
	-- units: measured by the adapter when another frame hangs on this one.
	local shownWidth, shownHeight
	if row.measure then
		shownWidth, shownHeight = Call(row.measure, frame)
	else
		shownWidth, shownHeight = w * scale / own * base, h * scale / own * base
	end
	if type(shownWidth) ~= "number" or type(shownHeight) ~= "number" then return false, "secret" end
	local fit = 1
	if not row.noScale then
		fit = self.BoxScale(slot, slotFrame, shownWidth, shownHeight)
		if not fit then
			fit = 1
			Note(adapter, L["%s does not fit its spot at 75 %%; it keeps its own size."]:format(adapter.title))
		end
	end
	local point, to, x, y = Fit.Spot(row, slot, frame, left, bottom, width, height)
	state.fit = fit
	state.fits = state.fits or {}
	state.fits[row.index] = fit
	if row.place then
		local done = Call(row.place, frame, x, y, fit, point)
		if done == false then return false, "missing" end
		return true
	end
	-- The frame's own points, kept from before the first move (false: none
	-- that can be read, so Release gives back only the scale).
	state.points = state.points or {}
	if state.points[row.index] == nil then state.points[row.index] = PointsOf(frame) or false end
	if row.guard and Call(row.guard, frame, "begin") ~= true then return false, "busy" end
	local targetScale = own
	if not row.noScale then
		if row.scale then
			Call(row.scale, frame, fit)
		elseif math.abs(own - base * fit) > 1e-3 then
			targetScale = base * fit
			frame:SetScale(targetScale)
		end
	end
	if row.guard and Call(row.guard, frame, "scale", targetScale) ~= true then return false, "busy" end
	-- Offsets are in the frame's own units: UIParent units over its scale.
	local _, _, now = Measure(frame)
	now = now or scale
	frame:ClearAllPoints()
	if row.guard and Call(row.guard, frame, "clear") ~= true then return false, "busy" end
	frame:SetPoint(point, UIParent, "BOTTOMLEFT", x / now, y / now)
	if row.guard and Call(row.guard, frame, "point", { point, UIParent, "BOTTOMLEFT", x / now, y / now }) ~= true then return false, "busy" end
	if row.afterPlace and Call(row.afterPlace, frame) ~= true then return false, "busy" end
	return true
end

-- Gives a frame back its own scale and its own points (the fit is off for
-- it now). The status is cleared: the next pass says why it is not placed.
function Fit:Release(adapter)
	local state = adapter.state
	for _, row in ipairs(adapter.frames) do
		local base = state.base and state.base[row.index]
		local points = state.points and state.points[row.index]
		local frame = (base or points) and RowFrame(row)
		if frame and row.guard and Call(row.guard, frame, "release") ~= true then frame = nil end
		if frame and base and not row.noScale then
			if row.scale then Call(row.scale, frame, 1) else frame:SetScale(base) end
		end
		if frame and row.guard and Call(row.guard, frame, "scale", base) ~= true then frame = nil end
		if frame and points then
			frame:ClearAllPoints()
			if row.guard and Call(row.guard, frame, "clear") ~= true then frame = nil end
			for _, p in ipairs(points) do
				if not frame then break end
				frame:SetPoint(p[1], p[2], p[3], p[4], p[5])
				if row.guard and Call(row.guard, frame, "point", p) ~= true then frame = nil end
			end
		end
		if frame then Call(row.afterRelease, frame) end
	end
	state.base = nil
	state.rowPlaced = nil
	state.points = nil
	state.fit = nil
	state.fits = nil
	state.status, state.why = nil, nil
end

-- Why an adapter is not placed right now, or nil when it may be.
function Fit:Blocked(adapter)
	if not Loaded(adapter.folder) then return "absent" end
	if not self:LayerOn() then return "layer" end
	if not self:AddonOn(adapter.id) then return "off" end
	if not self:Kept(adapter) then return "eldoui" end
	if adapter.moved then return "moved" end
	return nil
end

-- One pass over every adapter: who gets which slot, then the moves.
function Fit:PlaceAll()
	if InCombatLockdown() or self.encounter then
		self.pending = true
		return
	end
	self.pending = nil
	wipe(self.placed)
	for _, key in ipairs(self.slotOrder) do self:LaySlot(key) end
	for _, id in ipairs(self.order) do
		local adapter = self.adapters[id]
		local ok, err = pcall(self.PlaceAdapter, self, adapter)
		if not ok then
			adapter.state.status, adapter.state.why = "missing", nil
			geterrorhandler()(err)
		end
	end
	local sign = {}
	for _, id in ipairs(self.order) do
		local state = self.adapters[id].state
		sign[#sign + 1] = tostring(state.status) .. tostring(state.why)
	end
	sign = table.concat(sign, "|")
	if sign ~= self.sign then
		self.sign = sign
		if E.competitors and E.competitors.FitChanged then E.competitors.FitChanged() end
	end
end

function Fit:PlaceAdapter(adapter, onlyRow)
	local state = adapter.state
	local blocked = self:Blocked(adapter)
	if adapter.observe then
		local ready = Call(adapter.observe, not blocked)
		if not blocked and ready ~= true then
			state.status, state.why = "waiting", "missing"
			return
		end
	end
	if adapter.managed then
		-- Placed by its own module, with that module's switches.
		local status, why = Call(adapter.managed)
		if E:IsSecret(status) or type(status) ~= "string" or status == "" then status = "kept" end
		state.status = blocked == "absent" and "absent" or status
		state.why = blocked ~= "absent" and not E:IsSecret(why) and type(why) == "string" and why ~= "" and why or nil
		return
	end
	if blocked then
		if state.status == "placed" then self:Release(adapter) end
		state.status, state.why = blocked, nil
		return
	end
	local placed, waiting, why = 0, 0, nil
	for _, row in ipairs(adapter.frames) do
		if not onlyRow or row == onlyRow then
		if adapter.observe then
			state.rowPlaced = state.rowPlaced or {}
			state.rowPlaced[row.index] = nil
		end
		local frame = RowFrame(row)
		local free = row.free and Call(row.free)
		local taken = self.placed[row.slot]
		if not frame then
			waiting = waiting + 1
		elseif row.ready and not Call(row.ready, frame) then
			waiting = waiting + 1
		elseif not self:PlacedBefore(adapter, row) and E.PlainCall(frame.IsUserPlaced, frame) == true then
			-- The player placed this frame before the fit ever did: the game
			-- saves its spot and sets it again at login, also without EldoUI,
			-- so the fit leaves it there. A frame the fit placed and the
			-- player dragged since counts as moved by the player: picking a
			-- layout puts it back, though the drag set the same flag.
			why = why or "userPlaced"
		elseif free == false or type(free) == "string" then
			why = why or (type(free) == "string" and free or "busy")
		elseif taken and taken ~= adapter.id then
			why = why or "taken"
			state.takenBy = taken
		else
			self:Hook(adapter, row, frame)
			local ok, reason = self:PlaceRow(adapter, row, frame)
			if ok then
				placed = placed + 1
				if state.rowPlaced then state.rowPlaced[row.index] = true end
				self.placed[row.slot] = adapter.id
				NotePlaced(adapter, row)
			else
				why = why or reason
			end
		end
		end
	end
	if onlyRow and state.rowPlaced then
		placed = 0
		for _, owned in pairs(state.rowPlaced) do if owned then placed = placed + 1 end end
	end
	local before = state.status
	if placed > 0 then
		state.status, state.why = "placed", why
		if before ~= "placed" then self:FirstPlaced(adapter) end
	elseif waiting > 0 and not why then
		state.status, state.why = "waiting", nil
	else
		state.status, state.why = why == "secret" and "secret" or why == "missing" and "missing" or "kept", why
	end
end

---------------------------------------------------------------------------
-- Hooks on the other addon's frames: shown again (the addon put it back
-- on its own spot), and dragged by the player (the pull).
---------------------------------------------------------------------------
local hooked = setmetatable({}, { __mode = "k" })

function Fit:Hook(adapter, row, frame)
	if hooked[frame] then return end
	hooked[frame] = true
	frame:HookScript("OnShow", function() Fit:Schedule(0) end)
	for _, method in ipairs(row.after or EMPTY) do
		if type(frame[method]) == "function" then
			hooksecurefunc(frame, method, function() Fit:Schedule(0) end)
		end
	end
	if type(frame.StopMovingOrSizing) == "function" then
		hooksecurefunc(frame, "StopMovingOrSizing", function(f) Fit:Pull(adapter, row, f) end)
	end
end

-- The player dragged the addon's own frame: the slot's mover follows, so
-- the next layout pick or Reset puts both back. Without a mover the frame
-- stays where the player put it until a layout is picked again.
function Fit:Pull(adapter, row, frame)
	if self.pulling or adapter.state.status ~= "placed" or InCombatLockdown() then return end
	local slot = self.slots[row.slot]
	local mover = slot and E.movers[slot.mover]
	local left, bottom, width, height = self.RectOf(frame)
	if not left then return end
	if row.noPull or not mover or (E.IsMoverLocked and E:IsMoverLocked(slot.mover)) then
		adapter.moved = true
		adapter.state.status = "moved"
		return
	end
	-- Where the frame's point is now, and where the slot's point would be.
	local mleft, mbottom, mwidth, mheight = self.RectOf(mover)
	if not mleft then return end
	local point, _, wantX, wantY = Fit.Spot(row, slot, frame, mleft, mbottom, mwidth, mheight)
	local x, y = PointOf(point, left, bottom, width, height)
	self.pulling = true
	E:SaveMoverFromRect(slot.mover, mleft + x - wantX, mbottom + y - wantY)
	self.pulling = false
end

---------------------------------------------------------------------------
-- When to place: debounced, out of combat, never during a boss encounter.
---------------------------------------------------------------------------
function Fit:Schedule(delay)
	if self.scheduled or not self.started then return end
	self.scheduled = true
	C_Timer.After(delay or 0.2, function()
		Fit.scheduled = nil
		E:RunOutOfCombat(function() Fit:PlaceAll() end, "AddonFit")
	end)
end

-- Frames some addons build late (on first use, a while after login): a
-- few looks after login and after the addon loads, and after the global
-- functions an adapter names.
local LOOKS = { 1, 3, 10, 30 }
function Fit:LookLater()
	for _, delay in ipairs(LOOKS) do
		C_Timer.After(delay, function() Fit:Schedule(0) end)
	end
end

local watched = {}
function Fit:Watch(adapter)
	for _, name in ipairs(adapter.watch or EMPTY) do
		if not watched[name] and type(rawget(_G, name)) == "function" then
			watched[name] = true
			hooksecurefunc(name, function() Fit:Schedule(0.1) end)
		end
	end
end

local moverHooks = {}
local function FollowMovers()
	for _, key in ipairs(Fit.slotOrder) do
		local name = Fit.slots[key].mover
		if not moverHooks[name] then
			moverHooks[name] = true
			E:RegisterMoverCallback(name, function()
				if not Fit.pulling then Fit:Schedule(0) end
			end)
		end
	end
end

function Fit:Start()
	if self.started then return end
	self.started = true
	FollowMovers()
	self:RegisterChanges()
	for _, id in ipairs(self.order) do
		local adapter = self.adapters[id]
		if Loaded(adapter.folder) then self:Watch(adapter) end
	end
	self:LookLater()
end

local owner = {}
E:RegisterEvent("PLAYER_LOGIN", function()
	Fit:Start()
	Fit:Schedule(1)
end, owner, "modules")

E:RegisterEvent("ADDON_LOADED", function(_, _, name)
	if not Fit.started then return end
	local found = false
	for _, adapter in pairs(Fit.adapters) do
		if adapter.folder == name then
			Fit:Watch(adapter)
			found = true
		end
	end
	if found then Fit:LookLater() end
end, owner)

for _, event in ipairs({ "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "GROUP_ROSTER_UPDATE" }) do
	E:RegisterEvent(event, function() Fit:Schedule(0.5) end, owner)
end

E:RegisterEvent("PLAYER_REGEN_ENABLED", function()
	if Fit.pending then Fit:Schedule(0.2) end
end, owner)

-- A fight that ended while the player was elsewhere (a release, a
-- hearth, a disconnect) sends no ENCOUNTER_END here: the next loading
-- screen asks the game whether one is still on.
E:RegisterEvent("PLAYER_ENTERING_WORLD", function()
	local api = C_InstanceEncounter
	if Fit.encounter and api and E.PlainCall(api.IsEncounterInProgress) == false then Fit.encounter = nil end
	Fit:Schedule(0.5)
end, owner)

E:RegisterEvent("ENCOUNTER_START", function() Fit.encounter = true end, owner)
E:RegisterEvent("ENCOUNTER_END", function()
	Fit.encounter = nil
	if Fit.pending then Fit:Schedule(0.5) end
end, owner)

-- A layout picked again puts back what the player moved by hand.
E:RegisterLayoutCallback(function(_, _, silent)
	if silent then return end
	for _, adapter in pairs(Fit.adapters) do adapter.moved = nil end
	Fit:Schedule(0.2)
end)
E:RegisterRoleCallback(function() Fit:Schedule(0.2) end)
E:OnCompetitorsChanged(function() Fit:Schedule(0.2) end)

---------------------------------------------------------------------------
-- Switches
---------------------------------------------------------------------------
function Fit:SetLayerOn(on)
	local store = Store()
	if not store then return end
	store.enabled = on and true or false
	if not on then
		for _, adapter in pairs(self.adapters) do Call(adapter.observe, false) end
		-- Checked again when it runs: a switch made later in combat wins.
		E:RunOutOfCombat(function()
			for _, adapter in pairs(Fit.adapters) do
				if adapter.state.status == "placed" and Fit:Blocked(adapter) then Fit:Release(adapter) end
			end
		end)
	end
	self:Schedule(0)
end

function Fit:SetAddonOn(id, on)
	local store, adapter = Store(), self.adapters[id]
	if not (store and adapter) then return end
	store.off[id] = (not on) or nil
	if not on then Call(adapter.observe, false) end
	if not on and adapter.state.status == "placed" then
		-- Checked again when it runs: a switch made later in combat wins.
		E:RunOutOfCombat(function()
			if adapter.state.status == "placed" and Fit:Blocked(adapter) then Fit:Release(adapter) end
		end)
	end
	self:Schedule(0)
end

-- The first time an addon is placed: one notice that says where, with Undo
-- (which keeps that addon out of the fit).
function Fit:FirstPlaced(adapter)
	local store = Store()
	if not store or store.told[adapter.id] then return end
	store.told[adapter.id] = true
	local slot = self.slots[adapter.frames[1] and adapter.frames[1].slot or ""]
	local where = slot and slot.title or ""
	local text = L["The layout placed %s on its %s spot. Undo leaves it where the addon puts it."]:format(adapter.title, where)
	local shown = E.PushAlert and E:PushAlert({
		key = "EldoUI_AddonFit:" .. adapter.id,
		title = L["%s placed in the layout"]:format(adapter.title),
		text = text,
		options = { page = "addons" },
		actions = {
			{ label = L["Undo"], tip = L["Leaves this addon where its own settings put it. Turn it on again on the Other addons page."],
				func = function() Fit:SetAddonOn(adapter.id, false) end },
			{ label = L["OK"] },
		},
	})
	if not shown then E:Print(text) end
end

---------------------------------------------------------------------------
-- Changes to the addon's own saved position (Apply and Undo)
---------------------------------------------------------------------------
-- They use the change model of Modules/Integrations.lua (M.changes,
-- M:ApplyChange, M:UndoChange): a backup of every field it writes, a
-- question before Apply, and an Undo that keeps what the player changed
-- since. The keys are "fit:<id>:<change>".
local function Changes()
	local module = E.modules.Integrations
	return module and type(module.changes) == "table" and module or nil
end

function Fit:RegisterChanges()
	local module = Changes()
	if not module then return end
	for _, id in ipairs(self.order) do
		local adapter = self.adapters[id]
		local folder = adapter.folder
		for name, change in pairs(adapter.changes or EMPTY) do
			local key = ("fit:%s:%s"):format(id, name)
			if not rawget(module.changes, key) then
				change.addonTitle = change.addonTitle or adapter.title
				local on = change.On
				change.On = function()
					return Loaded(folder) and (on == nil or on())
				end
				module.changes[key] = change
			end
		end
	end
end

-- The change keys of an adapter that can be shown now.
function Fit:ChangeKeys(adapter)
	local module, keys = Changes(), {}
	if not module then return keys end
	for name in pairs(adapter.changes or EMPTY) do
		local key = ("fit:%s:%s"):format(adapter.id, name)
		if module.changes[key] and module:ChangeShown(key) then keys[#keys + 1] = key end
	end
	table.sort(keys)
	return keys
end

---------------------------------------------------------------------------
-- What the Other addons page and /eui addons fit say
---------------------------------------------------------------------------
local REASON = {
	eldoui = Key("EldoUI's own frame has this spot"),
	taken = Key("another addon has this spot"),
	moved = Key("you moved it; picking a layout again puts it back"),
	busy = Key("the spot is in use"),
	waiting = Key("placed once it opens the first time"),
	missing = Key("not placed: this release of the addon works differently"),
	secret = Key("not placed: the game hides its position right now"),
	off = Key("kept where the addon puts it (your choice)"),
	layer = Key("kept where the addon puts it (the layout spots are off)"),
	userPlaced = Key("kept where you placed it; the game saves its spot"),
}
-- Shown translated: L["EldoUI's own frame has this spot"], L["another addon has this spot"],
-- L["you moved it; picking a layout again puts it back"], L["the spot is in use"],
-- L["placed once it opens the first time"], L["not placed: this release of the addon works differently"],
-- L["not placed: the game hides its position right now"], L["kept where the addon puts it (your choice)"],
-- L["kept where the addon puts it (the layout spots are off)"], L["kept where you placed it; the game saves its spot"]

-- The detected adapters, in ranking order.
function Fit:Detected()
	local list = {}
	for _, id in ipairs(self.order) do
		local adapter = self.adapters[id]
		if Loaded(adapter.folder) then list[#list + 1] = adapter end
	end
	return list
end

function Fit:SlotTitles(adapter)
	local titles, seen = {}, {}
	for _, row in ipairs(adapter.frames) do
		local slot = self.slots[row.slot]
		if slot and not seen[slot.key] then
			seen[slot.key] = true
			titles[#titles + 1] = L[slot.title]
		end
	end
	return table.concat(titles, ", ")
end

function Fit:StateText(adapter)
	local state = adapter.state
	local status = state.status or self:Blocked(adapter) or "waiting"
	if status == "placed" then
		local where = self:SlotTitles(adapter)
		if where == "" then return L["Placed by the layout"] end
		return L["Placed by the layout: %s"]:format(where)
	end
	if status == "managed" then return L["Placed by the layout (its own section on the Integrations page)"] end
	if status == "kept" and type(state.why) == "string" and REASON[state.why] then return L[REASON[state.why]] end
	if REASON[status] then return L[REASON[status]] end
	if type(state.why) == "string" then return L[state.why] end
	return L["Kept where the addon puts it"]
end

E:RegisterDiagnostics("Addon fit", function()
	local lines = { ("layer %s"):format(Fit:LayerOn() and "on" or "off") }
	for _, adapter in ipairs(Fit:Detected()) do
		local state = adapter.state
		lines[#lines + 1] = ("%s: %s%s%s"):format(adapter.title, tostring(state.status or "-"),
			state.why and (" (" .. tostring(state.why) .. ")") or "",
			state.fit and state.fit < 1 and (" at %d%%"):format(math.floor(state.fit * 100 + 0.5)) or "")
		for _, line in ipairs(Fit.notes[adapter.id] or EMPTY) do lines[#lines + 1] = "  " .. line end
	end
	return lines
end)

-- /eui addons fit [on | off] [addon]
function E:AddonFitCommand(arg)
	arg = strtrim(arg or "")
	local word, rest = arg:match("^(%S*)%s*(.-)$")
	word = (word or ""):lower()
	if word == "on" or word == "off" then
		local on = word == "on"
		if rest == "" then
			Fit:SetLayerOn(on)
			self:Print(on and L["Layout spots for other addons: on."] or L["Layout spots for other addons: off. Every addon stays where its own settings put it."])
			return
		end
		local wanted = rest:lower()
		for _, adapter in ipairs(Fit:Detected()) do
			if adapter.folder:lower() == wanted or adapter.title:lower() == wanted then
				Fit:SetAddonOn(adapter.id, on)
				self:Print((on and L["%s: placed by the layout again."] or L["%s: stays where its own settings put it."]):format(adapter.title))
				return
			end
		end
		self:Print(L["No addon named %s is placed by the layouts. Type %s for the list."]:format(rest, self:Highlight("/eui addons fit")))
		return
	end
	local detected = Fit:Detected()
	if #detected == 0 then
		self:Print(L["None of the addons the layouts can place is loaded."])
		return
	end
	self:Print(Fit:LayerOn() and L["Layout spots for other addons (on):"] or L["Layout spots for other addons (off):"])
	local frame = _G.DEFAULT_CHAT_FRAME
	for _, adapter in ipairs(detected) do
		if frame then frame:AddMessage(("  %s: %s"):format(adapter.title, Fit:StateText(adapter))) end
	end
end
