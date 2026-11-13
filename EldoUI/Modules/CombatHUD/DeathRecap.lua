-- Combat HUD: death recap window and the ghost "Return to Graveyard" button.
-- Skin and movers only. EldoUI never releases, resurrects or
-- returns to the graveyard for the player and never clicks these buttons.
-- The death popup ("Release Spirit") belongs to the dialogs element.
-- DeathRecapFrame lives in the load-on-demand Blizzard_DeathRecap.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local K = E.CombatKit
local M = E.CombatHUD

local ID = "death-recap-ghost"
local GROUP = "death"
local RECAP_MOVER = "EldoUI_DeathRecap"
local GHOST_MOVER = "EldoUI_GhostButton"

local F = { key = "death", id = ID, title = "Death recap",
	install = { skin = true, move = true }, reload = { skin = true, move = true } }

F.defaults = {
	recap = true, ghost = true,
	scale = 100,
	hideRecap = true, hideGhost = false,
}

local function DB() return M.db.death end
local function Allowed(action) return M.active and E:BlizzardAllowed(ID, action) end

local RECAP_BORDERS = { "BorderTopLeft", "BorderTopRight", "BorderBottomLeft", "BorderBottomRight",
	"BorderTop", "BorderBottom", "BorderLeft", "BorderRight" }

---------------------------------------------------------------------------
-- Death recap
---------------------------------------------------------------------------
-- The skin's font on a name (K.Font), then the name font of that font, so
-- a name in another alphabet keeps its letters.
local function NameFont(fs, size, outline, font)
	K.Font(GROUP, fs, size, outline, font)
	if type(fs) == "table" and fs.GetFont then
		local path, height, flags = fs:GetFont()
		if path then E:SetNameFont(fs, path, height, flags) end
	end
end

local function SkinEntry(entry)
	if not Allowed("skin") or not DB().recap then return end
	local spell = entry.SpellInfo
	if spell then
		K.TexCoord(GROUP, spell.Icon)
		K.Alpha0(GROUP, spell.IconBorder)
		if spell.Icon then
			local holder = spell.Icon:GetParent()
			if holder then K.Backdrop(GROUP, holder, spell.Icon, E.pixel) end
		end
		K.Font(GROUP, spell.Name, nil, nil, E.media.font)
		NameFont(spell.Caster, nil, nil, E.media.font)
	end
	local damage = entry.DamageInfo
	if damage then
		K.Font(GROUP, damage.Amount, nil, nil, E.media.font)
		K.Font(GROUP, damage.AmountLarge, nil, nil, E.media.font)
	end
end

local recapSkinned = false
local function SkinRecap()
	local frame = DeathRecapFrame
	if not frame or not Allowed("skin") or not DB().recap then return end
	for _, suffix in ipairs(RECAP_BORDERS) do K.Alpha0(GROUP, _G["DeathRecapFrame" .. suffix]) end
	K.Alpha0(GROUP, frame.Background, frame.BackgroundInnerGlow, frame.Divider)
	K.Font(GROUP, frame.Title, 14, nil, E.media.font)
	K.Font(GROUP, frame.Unavailable, nil, nil, E.media.font)
	if not recapSkinned then
		recapSkinned = true
		-- Core skin helpers (a reload undoes them).
		E:SkinPanel(frame, { strip = false, insets = false, close = false, title = false, accentOffset = 32 })
		E:SkinCloseButton(frame.CloseXButton)
		E:SkinButton(frame.CloseButton)
		E:SkinScrollBar(frame.ScrollBar)
		E:HookScrollBoxRows(frame.ScrollBox, SkinEntry)
	end
end

---------------------------------------------------------------------------
-- Ghost button
---------------------------------------------------------------------------
local ghostSkinned = false
local function SkinGhost()
	local button = GhostFrame
	if not button or not Allowed("skin") or not DB().ghost then return end
	K.TexCoord(GROUP, GhostFrameContentsFrameIcon)
	K.Font(GROUP, GhostFrameContentsFrameText, nil, nil, E.media.font)
	if not ghostSkinned then
		ghostSkinned = true
		E:SkinButton(button)
	end
end

---------------------------------------------------------------------------
-- Feature
---------------------------------------------------------------------------
function F:Setup()
	self.recapHolder = K.Holder(M, RECAP_MOVER, L["Death Recap"], { "CENTER", "UIParent", "CENTER", 0, 80 }, 410, 326, { sample = false })
	self.ghostHolder = K.Holder(M, GHOST_MOVER, L["Return to Graveyard"], { "TOP", "UIParent", "TOP", 0, -110 }, 130, 46, { sample = { kind = "panel" } })
end

-- Window positions and nondefault window scales have their own saved
-- owner. The feature supplies only the channels that owner leaves unused.
local recapLease, recapParent, recapFrame
local function Number(value)
	return K.Plain(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function Channels(frame)
	if E.GetWindowState == nil and E.GetWindowFrames == nil then return false, false end
	if type(E.GetWindowState) ~= "function" or type(E.GetWindowFrames) ~= "function" then return nil end
	local state = E:GetWindowState("deathRecap")
	local attached = E:GetWindowFrames("deathRecap")
	if not K.Plain(state) or type(state) ~= "table" or not K.Plain(state.allowed, state.attached, state.scale, state.pos)
		or type(state.allowed) ~= "boolean" or type(state.attached) ~= "boolean" then return nil end
	if not state.allowed or not state.attached then return false, false end
	if attached ~= frame or not Number(state.scale) or state.scale <= 0 then return nil end
	local x, y
	if state.pos ~= nil then
		if type(state.pos) ~= "table" then return nil end
		x, y = state.pos[1], state.pos[2]
		if not Number(x) or not Number(y) then return nil end
	end
	return x ~= nil, state.scale ~= 1, x, y, state.scale
end

local function ParentState(frame)
	local state = E.BlizzardKeep.parents[frame]
	if not state then return function() return E.BlizzardKeep.parents[frame] == nil end end
	local parent, original, check, events = state.parent, state.original, state.check, state.events
	return function()
		return E.BlizzardKeep.parents[frame] == state and state.parent == parent
			and state.original == original and state.check == check and state.events == events
	end
end

local function Admission(frame, applying, phase)
	local profile, settings, db = E.db, M.db, DB()
	local lease = recapLease
	if not lease or lease.frame ~= frame then return end
	local holder, mover = lease.holder, lease.mover
	if not mover or mover.frame ~= holder or mover.module ~= "CombatHUD" then return end
	local methods = lease.methods
	if not methods then
		methods = {}
		for _, key in ipairs({ "GetParent", "SetParent", "GetScale", "SetScale", "GetSize", "SetSize",
			"GetPoint", "GetNumPoints", "ClearAllPoints", "SetPoint", "GetEffectiveScale", "IsShown", "IsVisible" }) do
			methods[key] = frame[key]
		end
		-- Core's one-time secure post-hooks are installed between remembering
		-- the original geometry and the first placement operation.
		if phase == "apply" then lease.methods = methods end
	end
	local function Stable()
		if E.CombatHUD ~= M or (E.modules and E.modules.CombatHUD) ~= M or DeathRecapFrame ~= frame
			or E.db ~= profile or M.db ~= settings or DB() ~= db
			or F.recapHolder ~= holder or (E.movers and E.movers[RECAP_MOVER]) ~= mover then return false end
		for key, method in pairs(methods) do if frame[key] ~= method then return false end end
		for key, callback in pairs(lease.callbacks) do if lease.spec[key] ~= callback then return false end end
		for key, callback in pairs(lease.readers) do if E[key] ~= callback then return false end end
		return true
	end
	if not Stable() then return end
	local position, scale, x, y, requested = Channels(frame)
	if not Stable() or position == nil or not Number(db.scale) or db.scale < 50 or db.scale > 150 then return end
	local featureScale = db.scale
	local parentOwned = ParentState(frame)
	local parent = frame:GetParent()
	if not Stable() or not parentOwned() then return end
	if parent ~= UIParent and (not recapParent or recapParent.frame ~= frame
		or parent ~= K.hider or not recapParent.owns()) then return end
	return function()
		if not Stable() or not parentOwned() or db.scale ~= featureScale then return false end
		if frame:GetParent() ~= parent or not Stable() or not parentOwned() then return false end
		if applying and (not Allowed("move") or not db.recap) then return false end
		if not Stable() then return false end
		local p, z, a, b, r = Channels(frame)
		return Stable() and parentOwned() and db.scale == featureScale
			and p == position and z == scale and a == x and b == y and r == requested
	end
end

local function SamePoints(frame, expected)
	if type(expected) ~= "table" then return false end
	local count = frame:GetNumPoints()
	if not Number(count) or count ~= #expected then return false end
	for i, p in ipairs(expected) do
		local actual = { frame:GetPoint(i) }
		if not K.Plain(unpack(actual)) then return false end
		for field = 1, 5 do if actual[field] ~= p[field] then return false end end
	end
	return true
end

local function Applied(frame, scale, points)
	local lease = recapLease
	local owns = Admission(frame, true)
	if not lease or lease.frame ~= frame or not owns or not owns() then return end
	if scale then
		local actual = frame:GetScale()
		if not owns() or not Number(actual) or math.abs(actual - scale) > .001 then
			error("Death recap scale changed during placement", 0)
		end
		lease.scale = actual
	end
	if points then
		local normalized = {}
		for i, p in ipairs(points) do normalized[i] = { p[1], p[2] or UIParent, p[3] or p[1], p[4] or 0, p[5] or 0 } end
		if not SamePoints(frame, normalized) or not owns() then error("Death recap anchors changed during placement", 0) end
		lease.points = normalized
	end
end

local function WindowOriginal(frame, channel)
	local lease = recapLease
	local owns = Admission(frame, true)
	if not lease or lease.frame ~= frame or not K.IsPinned(frame, lease.spec) or not owns or not owns() then return end
	local original = E:BlizzardPinOriginal(frame, lease.spec, channel)
	if not original or not owns() then return end
	if channel == "scale" then
		if lease.scale == nil then return { kind = "native" } end
		local current = frame:GetScale()
		if not owns() or not Number(current) or current ~= lease.scale then return end
		return { kind = "original", value = original.scale, applied = lease.scale }
	elseif channel == "points" then
		if lease.points == nil then return { kind = "native" } end
		if not SamePoints(frame, lease.points) or not owns() then return end
		local applied = {}
		for i, point in ipairs(lease.points) do applied[i] = { unpack(point) } end
		return { kind = "original", value = original.points, applied = applied }
	end
end

local function WindowBaseline(frame, channel)
	local lease = recapLease
	local owns = Admission(frame, true, "remember")
	if not lease or lease.frame ~= frame or not owns or not owns() or type(E.WindowMoverPinOriginal) ~= "function" then
		return { kind = "unavailable" }
	end
	local result = E:WindowMoverPinOriginal(frame, channel)
	if not owns() then return { kind = "unavailable" } end
	return result
end

local function ReleaseChannels(frame)
	local lease = recapLease
	if not lease or lease.frame ~= frame then return end
	local current = frame:GetScale()
	return { scale = Number(current) and current == lease.scale,
		points = SamePoints(frame, lease.points) }
end

local function ReleaseRecap()
	local lease = recapLease
	if lease and DeathRecapFrame == lease.frame and E.BlizzardKeep.Locked(lease.frame) then
		local queued = lease.releaseQueued
		local profile, settings, death = E.db, M.db, DB()
		if not queued or queued.profile ~= profile or queued.settings ~= settings or queued.death ~= death then
			queued = { profile = profile, settings = settings, death = death }
			lease.releaseQueued = queued
			E:RunOutOfCombat(function()
				if recapLease ~= lease or lease.releaseQueued ~= queued then return end
				lease.releaseQueued = nil
				if E.db == profile and M.db == settings and DB() == death and DeathRecapFrame == lease.frame then ReleaseRecap() end
			end, lease)
		end
		return false
	end
	local released = lease and DeathRecapFrame == lease.frame and K.IsPinned(lease.frame, lease.spec)
	local failure
	local function Step(fn)
		local ok, err = pcall(fn)
		if not ok and not failure then failure = err end
	end
	Step(function()
		if lease and DeathRecapFrame == lease.frame then
			local owns = Admission(lease.frame, false)
			if not owns or not owns() then return end
			local normalize
			if E.WindowMoverPinReturn and K.IsPinned(lease.frame, lease.spec) then
				normalize = E:WindowMoverPinReturn(lease.frame, lease.spec, ReleaseChannels(lease.frame))
			end
			if not owns() then return end
			K.Unpin(lease.frame, lease.spec)
			if normalize then normalize() end
		end
	end)
	Step(function()
		local parent = recapParent
		if parent and DeathRecapFrame == parent.frame and parent.owns() then
			E:ReleaseBlizzardParent(parent.frame, nil, parent.state, parent.owns)
			if not E.BlizzardKeep.parents[parent.frame] then recapParent = nil end
		end
	end)
	if lease and recapLease == lease and E.BlizzardKeep.pins[lease.frame] ~= lease.spec then recapLease = nil end
	if failure then error(failure, 0) end
	return released and not E.BlizzardKeep.pins[lease.frame] and not E.BlizzardKeep.parents[lease.frame]
end

local function ApplyRecap(self, db)
	local frame = DeathRecapFrame
	if not frame or (recapFrame and frame ~= recapFrame) then return end
	recapFrame = frame
	SkinRecap()
	if Allowed("move") and db.recap then
		if recapLease then recapLease.releaseQueued = nil end
		local current = E.BlizzardKeep.pins[frame]
		if current and (not recapLease or recapLease.frame ~= frame or current ~= recapLease.spec) then return end
		if not recapLease or recapLease.frame ~= frame then
			local holder = self.recapHolder
			local spec = {
				anchor = function()
					local position = Channels(frame)
					if position == false then return "CENTER", holder, "CENTER", 0, 0 end
				end,
				scale = function()
					local position, scale = Channels(frame)
					if position ~= nil and scale == false then return DB().scale / 100 end
				end,
				active = function() return Allowed("move") and DB().recap end,
				admit = function(_, phase) return Admission(frame, true, phase) end,
				releaseAdmit = function() return Admission(frame, false) end,
				releaseChannels = ReleaseChannels,
				applied = Applied,
				windowOriginal = WindowOriginal,
				baseline = WindowBaseline,
			}
			local callbacks = {}
			for key, callback in pairs(spec) do callbacks[key] = callback end
			local readers = { BlizzardPinOriginal = E.BlizzardPinOriginal,
				GetWindowState = E.GetWindowState, GetWindowFrames = E.GetWindowFrames,
				WindowMoverPinOriginal = E.WindowMoverPinOriginal }
			recapLease = { frame = frame, spec = spec, holder = holder, mover = E.movers and E.movers[RECAP_MOVER],
				callbacks = callbacks, readers = readers }
			K.Pin(frame, spec)
		elseif not current then
			K.Pin(frame, recapLease.spec)
		else
			K.ApplyPin(frame)
		end
	else
		ReleaseRecap()
	end
	if E:BlizzardHidden(ID) and db.recap and db.hideRecap then
		if not E.BlizzardKeep.parents[frame] then
			local profile, settings, death = E.db, M.db, db
			local claim
			local function Check()
				if E.db ~= profile or M.db ~= settings or DB() ~= death or DeathRecapFrame ~= frame then return false end
				if claim then return claim.owns() end
				local state = E.BlizzardKeep.parents[frame]
				if not state or state.parent ~= K.hider then return false end
				claim = { frame = frame, state = state, owns = ParentState(frame) }
				recapParent = claim
				return true
			end
			E:KeepBlizzardParent(frame, K.hider, { check = Check })
		end
	elseif recapParent and recapParent.owns() then
		E:ReleaseBlizzardParent(frame, nil, recapParent.state, recapParent.owns)
		if not E.BlizzardKeep.parents[frame] then recapParent = nil end
	end
end

-- Bounds describe capacity separately from a live native body. Unknown
-- placement never becomes a successful nominal reservation.
function M:DeathRecapBounds()
	local frame, holder = DeathRecapFrame, F.recapHolder
	if recapFrame and frame ~= recapFrame then return { kind = "unavailable" } end
	if not frame then
		-- The standard reservation is not a measurement of a resized or
		-- manually placed body that has not loaded yet.
		if not Number(DB().scale) or DB().scale ~= 100 then return { kind = "unavailable" } end
		if E.GetWindowState then
			local state = E:GetWindowState("deathRecap")
			if not K.Plain(state) or type(state) ~= "table" or not K.Plain(state.scale, state.pos)
				or state.scale ~= 1 or state.pos ~= nil then return { kind = "unavailable" } end
		end
		return { kind = "nominal", frame = holder }
	end
	-- Attachment and saved window preferences do not prove a current
	-- WindowMover pose. A present independent body needs its own admission.
	if not M.active or not DB().recap or not Allowed("move") then return { kind = "unavailable" } end
	local lease = recapLease
	if not lease or lease.frame ~= frame or not K.IsPinned(frame, lease.spec) then return { kind = "unavailable" } end
	local owns = Admission(frame, true)
	if not owns or not owns() then return { kind = "unavailable" } end
	local width, height = frame:GetSize()
	local effective, root = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
	if not owns() or not Number(width) or not Number(height) or width <= 0 or height <= 0
		or not Number(effective) or not Number(root) or effective <= 0 or root <= 0 then return { kind = "unavailable" } end
	local ratio = effective / root
	if not Number(ratio) or ratio <= 0 or holder:GetParent() ~= UIParent or holder:GetScale() ~= 1 then
		return { kind = "unavailable" }
	end
	local point, relative, relativePoint, x, y = frame:GetPoint(1)
	if not owns() or frame:GetNumPoints() ~= 1 or not K.Plain(point, relative, relativePoint)
		or not Number(x) or not Number(y) then return { kind = "unavailable" } end
	local l, top
	local manual = Channels(frame)
	if manual == true and point == "TOPLEFT" and relative == UIParent and relativePoint == "BOTTOMLEFT" then
		l, top = x * ratio, y * ratio
	elseif manual == false and point == "CENTER" and relative == holder and relativePoint == "CENTER" and x == 0 and y == 0 then
		local cx, cy = holder:GetCenter()
		if not Number(cx) or not Number(cy) then return { kind = "unavailable" } end
		l, top = cx - width * ratio / 2, cy + height * ratio / 2
	else
		return { kind = "unavailable" }
	end
	local shown, visible = frame:IsShown(), frame:IsVisible()
	if not owns() or not K.Plain(shown, visible) or not Number(l) or not Number(top)
		or not Number(width * ratio) or not Number(height * ratio) then return { kind = "unavailable" } end
	return { kind = "live", frame = frame, l = l, b = top - height * ratio,
		r = l + width * ratio, t = top, shown = shown, visible = visible }
end

function F:Apply(db)
	if not Allowed("skin") then K.Undo(GROUP) end
	local ghost = GhostFrame
	if ghost then
		SkinGhost()
		if Allowed("move") and db.ghost then
			local holder = self.ghostHolder
			K.Pin(ghost, {
				anchor = function() return "TOP", holder, "TOP", 0, 0 end,
				active = function() return Allowed("move") and DB().ghost end,
			})
		else
			K.Unpin(ghost)
		end
		if E:BlizzardHidden(ID) and db.ghost and db.hideGhost then
			K.Parent(ghost, K.hider)
		else
			K.RestoreParent(ghost)
		end
	end
	-- The recap window loads on demand (first click on the recap link).
	if not self.waitingRecap then
		self.waitingRecap = true
		E:OnBlizzardAddOn("Blizzard_DeathRecap", function()
			if M.active and E:BlizzardAllowed(ID) then ApplyRecap(F, M.db.death) end
		end)
	elseif DeathRecapFrame then
		ApplyRecap(self, db)
	end
end

function F:Restore()
	local failure
	local function Step(fn)
		local ok, err = pcall(fn)
		if not ok and not failure then failure = err end
	end
	Step(function() ReleaseRecap() end)
	local ghost = GhostFrame
	if ghost then
		Step(function() K.Unpin(ghost) end)
		Step(function() K.RestoreParent(ghost) end)
	end
	Step(function() K.Undo(GROUP) end)

	if failure then error(failure, 0) end
end

local NotMove, NotHide = M.Off(ID, "move"), M.Off(ID, "hide")
local function Off() return not E:BlizzardAllowed(ID) end

F.switches = {
	skin = L["EldoUI panel for the death recap, flat ghost button."],
	move = L["Own movers for the recap window and the Return to Graveyard button."],
	hide = L["Hide the parts checked below."],
}
F.note = L["EldoUI never releases your spirit for you: the buttons only work when you click them. The death popup is skinned with the dialogs."]
F.options = {
	{ type = "toggle", key = "death.recap", label = "Death recap window", hidden = Off,
		desc = "EldoUI skins and places Blizzard's death recap window. Off leaves it to Blizzard." },
	{ type = "toggle", key = "death.ghost", label = "Return to Graveyard button", hidden = Off,
		desc = "EldoUI skins and places the ghost button. Off leaves it to Blizzard." },
	{ type = "range", key = "death.scale", label = "Recap scale", unit = "%", min = 50, max = 150, step = 5, hidden = NotMove,
		desc = "Scale of the death recap window in percent." },
	{ type = "header", label = "Hide", hidden = NotHide },
	{ type = "toggle", key = "death.hideRecap", label = "Hide death recap", hidden = NotHide,
		desc = "The recap window stays hidden while the Hide switch is on." },
	{ type = "toggle", key = "death.hideGhost", label = "Hide Return to Graveyard", hidden = NotHide,
		desc = "Hides the ghost button. You can still return to the graveyard from the spirit healer." },
}

M:AddFeature(F)
