-- EldoUI quiet HUD: General > Visibility, the OLED pixel shift and
-- the idle dim. The "When active" rule, the Show HUD key and the activity
-- test live in Core/Visibility.lua; this file holds the page, the HUD-wide
-- visibility presets and the slow pixel shift.
--
-- Pixel shift (OLED care, off by default): every few minutes every EldoUI
-- mover moves by one or two screen pixels along a small loop, so static
-- bars don't burn in. It works on EldoUI's own mover roots only:
-- E:GetMoverAnchor() hands out a shift frame laid over the usual anchor
-- (UIParent or the safe area, Core/Scale.lua), and a step moves that one
-- frame. Blizzard frames move only when their element already hangs them
-- on an EldoUI mover. Movers hold protected frames, so a step only runs
-- out of combat, and it pauses in move mode. A step is counted in screen
-- pixels (E.pixel), so it follows the UI scale.
--
-- Idle dim: after a long idle (no combat, target, movement, cast or loot)
-- every attached HUD frame drops to a share of its opacity; any activity
-- or the Show HUD key brings it back. Alpha only.
local _, E = ...
local L = E.L

local Settings = E.QuietSettings

---------------------------------------------------------------------------
-- Pixel shift
---------------------------------------------------------------------------
-- One loop of offsets (in steps of the range): the center, then around it.
local LOOP = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 } }
E.PIXEL_SHIFT_LOOP = LOOP

local shifters = {}   -- base frame -> shift frame
local shift = { step = 1, x = 0, y = 0, last = nil, on = false }
E.pixelShiftState = shift

local function ShiftOn()
	return Settings().pixelShift == true
end

local function Range()
	local range = math.floor(tonumber(Settings().shiftRange) or 1)
	return math.max(1, math.min(2, range))
end

local function Place(base, frame)
	local px = E.pixel or 1
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", base, "TOPLEFT", shift.x * px, shift.y * px)
	frame:SetPoint("BOTTOMRIGHT", base, "BOTTOMRIGHT", shift.x * px, shift.y * px)
end

local function Shifter(base)
	local frame = shifters[base]
	if frame then return frame end
	frame = CreateFrame("Frame", base == UIParent and "EldoUI_HUDShift" or nil, UIParent)
	frame:EnableMouse(false)
	shifters[base] = frame
	Place(base, frame)
	return frame
end

-- Wrap the anchor Core/Scale.lua gives: while the shift is on, movers hang
-- from the shift frame over it.
local baseAnchor = E.GetMoverAnchor
function E:GetMoverAnchor(relPoint)
	local base = baseAnchor and baseAnchor(self, relPoint) or UIParent
	if not shift.on then return base end
	return Shifter(base)
end

-- The current offset in screen pixels (for diagnostics).
function E:PixelShiftOffset()
	return shift.x, shift.y
end

local function SetOffset(x, y)
	if shift.x == x and shift.y == y then return end
	E:RunOutOfCombat(function()
		shift.x, shift.y = x, y
		for base, frame in pairs(shifters) do Place(base, frame) end
	end)
end

-- One step along the loop (out of combat; not in move mode).
function E:PixelShiftStep()
	if not shift.on or InCombatLockdown() then return false end
	if self.IsMoveMode and self:IsMoveMode() then return false end
	shift.step = shift.step % #LOOP + 1
	local range = Range()
	SetOffset(LOOP[shift.step][1] * range, LOOP[shift.step][2] * range)
	shift.last = GetTime()
	return true
end

-- Turn the shift on or off from the settings. Switching moves every mover
-- onto (or off) the shift frame, out of combat.
function E:UpdatePixelShift()
	local want = ShiftOn()
	if want == shift.on then
		if not want then return end
		-- A smaller range takes the offset back inside it.
		local range = Range()
		if math.abs(shift.x) > range or math.abs(shift.y) > range then
			SetOffset(LOOP[shift.step][1] * range, LOOP[shift.step][2] * range)
		end
		return
	end
	self:RunOutOfCombat(function()
		shift.on = ShiftOn()
		shift.step, shift.last = 1, GetTime()
		shift.x, shift.y = 0, 0
		for base, frame in pairs(shifters) do Place(base, frame) end
		self:RefreshMovers()
	end)
end

-- UI scale changes change E.pixel: put the shift frames on the new size.
if E.RegisterPixelCallback then
	E:RegisterPixelCallback(function()
		E:RunOutOfCombat(function()
			for base, frame in pairs(shifters) do Place(base, frame) end
		end)
	end)
end

---------------------------------------------------------------------------
-- The timer: idle dim and the shift steps, every few seconds
---------------------------------------------------------------------------
function E:QuietTick()
	local settings = Settings()
	if settings.idleDim then
		local after = (tonumber(settings.idleDimAfter) or 5) * 60
		self:SetIdleDimmed(not self:IsHUDHeld() and self:IdleSeconds() >= after)
	elseif self:IsIdleDimmed() then
		self:SetIdleDimmed(false)
	end
	if shift.on then
		-- Move mode puts everything back on its true point.
		if self:IsMoveMode() then
			SetOffset(0, 0)
		elseif not shift.last or GetTime() - shift.last >= (tonumber(settings.shiftInterval) or 3) * 60 then
			self:PixelShiftStep()
		end
	end
end

E:RegisterEvent("PLAYER_LOGIN", function()
	E:UpdatePixelShift()
	if C_Timer and C_Timer.NewTicker then
		C_Timer.NewTicker(5, function() E:QuietTick() end)
	end
end, shift, "modules")

---------------------------------------------------------------------------
-- HUD-wide visibility: every attached frame at once
---------------------------------------------------------------------------
local BACK_KEYS = { "preset", "show", "fadedAlpha", "fadeTime", "delay" }

local function ModuleBlocks(name)
	local list, seen = {}, {}
	for _, entry in ipairs(E:VisibilityEntries()) do
		if not entry.exempt and (name == nil or entry.module == name) and not seen[entry.block] then
			seen[entry.block] = true
			list[#list + 1] = entry
		end
	end
	return list
end

local function Refresh(entries)
	for _, entry in ipairs(entries) do E:UpdateVisibility(entry.frame) end
end

-- "When active" for a block, keeping what it had so turning it off can
-- put it back.
local function MakeActive(block)
	if block.show == "active" then return end
	local back = {}
	for _, key in ipairs(BACK_KEYS) do back[key] = block[key] end
	block.quietBack = back
	-- Custom first, so the next normalize names the preset the new values
	-- match instead of writing the old one back.
	block.preset = "custom"
	block.show = "active"
	block.fadedAlpha = math.max(0, math.min(1, tonumber(Settings().idleAlpha) or 0.2))
	block.fadeTime = E.VISIBILITY_PRESETS.quiet.fadeTime
	block.delay = 0
end

local function MakeInactive(block)
	if block.show ~= "active" then return end
	local back = type(block.quietBack) == "table" and block.quietBack
	if back and back.show ~= "active" then
		for _, key in ipairs(BACK_KEYS) do
			if back[key] ~= nil then block[key] = back[key] end
		end
	else
		E:ApplyVisibilityPreset(block, "always")
	end
	block.quietBack = nil
end

-- Every frame of a module follows "When active" (or none does).
function E:ModuleFollowsActive(name)
	local list = ModuleBlocks(name)
	if #list == 0 then return false end
	for _, entry in ipairs(list) do
		if entry.block.show ~= "active" then return false end
	end
	return true
end

function E:SetModuleFollowsActive(name, on)
	local list = ModuleBlocks(name)
	for _, entry in ipairs(list) do
		if on then MakeActive(entry.block) else MakeInactive(entry.block) end
	end
	Refresh(list)
end

-- "Idle opacity" reaches every block this page made "When active" (the
-- ones that keep a way back); a block the player set up by hand in its
-- module keeps its own faded opacity.
function E:ApplyIdleAlpha()
	local alpha = math.max(0, math.min(1, tonumber(Settings().idleAlpha) or 0.2))
	local list = {}
	for _, entry in ipairs(ModuleBlocks(nil)) do
		local block = entry.block
		if block.show == "active" and type(block.quietBack) == "table" and block.fadedAlpha ~= alpha then
			block.fadedAlpha = alpha
			list[#list + 1] = entry
		end
	end
	Refresh(list)
end

-- Modules with attached frames, sorted by title.
function E:VisibilityModules()
	local names, seen = {}, {}
	for _, entry in ipairs(ModuleBlocks(nil)) do
		local name = entry.module
		if name and not seen[name] and self.modules[name] then
			seen[name] = true
			names[#names + 1] = name
		end
	end
	table.sort(names, function(a, b) return L[self.modules[a].title] < L[self.modules[b].title] end)
	return names
end

-- HUD presets (the 5 visibility presets). Each one writes one
-- visibility preset into every attached block (exempt frames stay) and
-- the OLED care switches.
E.HUD_VISIBILITY_PRESETS = {
	{ key = "always", title = "Always shown", block = "always", oled = false,
		desc = "Every EldoUI frame stays shown. Pixel shift and idle dim off." },
	{ key = "quiet", title = "Quiet", block = "quiet",
		desc = "Every frame shows while you fight, have a target, move, cast or loot, and fades a few seconds after." },
	{ key = "combat", title = "Combat only", block = "combat",
		desc = "Every frame shows in combat only. Hover a frame or hold the Show HUD key to see it." },
	{ key = "minimal", title = "Minimal HUD", block = "minimal",
		desc = "Every frame shows in combat or with a target and stays faint otherwise." },
	{ key = "oled", title = "OLED care", block = "quiet", oled = true,
		desc = "Quiet, plus the slow pixel shift and the idle dim, for OLED screens." },
}

function E:ApplyHUDVisibilityPreset(key)
	local preset
	for _, item in ipairs(self.HUD_VISIBILITY_PRESETS) do
		if item.key == key then preset = item break end
	end
	if not preset then return false end
	local list = ModuleBlocks(nil)
	for _, entry in ipairs(list) do
		entry.block.quietBack = nil
		self:ApplyVisibilityPreset(entry.block, preset.block)
	end
	local settings = self.db.general.quietHUD
	if preset.oled ~= nil then
		settings.pixelShift = preset.oled
		settings.idleDim = preset.oled
	end
	Refresh(list)
	self:UpdatePixelShift()
	self:QuietTick()
	return true
end

---------------------------------------------------------------------------
-- General > Visibility
---------------------------------------------------------------------------
-- Rows read and write through this proxy: "follow.<Module>" is worked out
-- from the module's blocks, every other key is general.quietHUD.
local followProxy = setmetatable({}, {
	__index = function(_, name) return E:ModuleFollowsActive(name) end,
	__newindex = function(_, name, value) E:SetModuleFollowsActive(name, value) end,
})
local proxy = setmetatable({}, {
	__index = function(_, key)
		if key == "follow" then return followProxy end
		return Settings()[key]
	end,
	__newindex = function(_, key, value)
		if key ~= "follow" and E.db and E.db.general then E.db.general.quietHUD[key] = value end
	end,
})
E.quietHUDProxy = proxy

local function BuildRows()
	local rows = {
		{ type = "description", label = "The HUD fades while nothing happens and comes back when you act. This page sets every module's Visibility at once." },
		{ type = "header", label = "HUD presets" },
	}
	for _, preset in ipairs(E.HUD_VISIBILITY_PRESETS) do
		rows[#rows + 1] = { type = "execute", label = preset.title, desc = preset.desc, width = 200,
			confirm = L["Set every module's Show rule to this preset? What you set in each module's own Visibility settings is replaced."],
			func = function()
				E:ApplyHUDVisibilityPreset(preset.key)
				if E.ConfigNotice then E:ConfigNotice(L["Visibility preset %s applied."]:format(L[preset.title])) end
				if E.RefreshConfig then E:RefreshConfig() end
			end }
	end
	rows[#rows + 1] = { type = "header", label = "When active" }
	rows[#rows + 1] = { type = "range", unit = "s", key = "idleDelay", label = "Idle delay", min = 0, max = 30, step = 1,
		desc = "Seconds frames set to When active stay shown after your last fight, target, movement, cast or loot." }
	rows[#rows + 1] = { type = "range", percent = true, key = "idleAlpha", label = "Idle opacity", min = 0, max = 1, step = 0.05, zeroText = "Invisible",
		desc = "How visible a frame stays while you are idle, for the modules you tick below." }
	rows[#rows + 1] = { type = "execute", label = "All modules", width = 200,
		desc = "Check every module below: all of them fade while you are idle.",
		func = function()
			for _, name in ipairs(E:VisibilityModules()) do E:SetModuleFollowsActive(name, true) end
			if E.RefreshConfig then E:RefreshConfig() end
		end }
	rows[#rows + 1] = { type = "execute", label = "No modules", width = 200,
		desc = "Uncheck every module below: each one goes back to the visibility it had before.",
		func = function()
			for _, name in ipairs(E:VisibilityModules()) do E:SetModuleFollowsActive(name, false) end
			if E.RefreshConfig then E:RefreshConfig() end
		end }
	local names = E:VisibilityModules()
	if #names == 0 then
		rows[#rows + 1] = { type = "description", label = "No module with a fading frame is on." }
	end
	for _, name in ipairs(names) do
		local title = L[E.modules[name].title]
		rows[#rows + 1] = { type = "toggle", key = "follow." .. name, label = title,
			desc = L["%s fades while you are idle (its Show rule becomes When active). Uncheck to put back what it had."]:format(title) }
	end
	rows[#rows + 1] = { type = "header", label = "Show HUD key" }
	rows[#rows + 1] = { type = "toggle", key = "holdKey", label = "Hold to show the HUD",
		desc = "While you hold the Show HUD key (Key Bindings > AddOns > EldoUI), every faded EldoUI frame shows. Works in combat. A protected frame its rule hides for real stays hidden." }
	rows[#rows + 1] = { type = "header", label = "OLED care" }
	rows[#rows + 1] = { type = "toggle", key = "pixelShift", label = "Pixel shift",
		desc = "Every few minutes every EldoUI frame moves by one or two pixels in a small loop, so still bars don't burn into an OLED screen. Only out of combat and not in move mode." }
	rows[#rows + 1] = { type = "range", key = "shiftInterval", label = "Shift every", unit = "min", min = 1, max = 15, step = 1, dependsOn = "pixelShift",
		desc = "Minutes between two pixel shift steps." }
	rows[#rows + 1] = { type = "range", key = "shiftRange", label = "Shift range", unit = "px", min = 1, max = 2, step = 1, dependsOn = "pixelShift",
		desc = "How far a frame moves from its point at most, in screen pixels." }
	rows[#rows + 1] = { type = "toggle", key = "idleDim", label = "Dim after a long idle",
		desc = "After the time below without a fight, target, movement, cast or loot, every EldoUI frame dims. Any of those, or the Show HUD key, brings it back." }
	rows[#rows + 1] = { type = "range", key = "idleDimAfter", label = "Dim after", unit = "min", min = 1, max = 30, step = 1, dependsOn = "idleDim",
		desc = "Minutes of idle before the HUD dims." }
	rows[#rows + 1] = { type = "range", percent = true, key = "idleDimAlpha", label = "Dimmed opacity", min = 0.1, max = 0.9, step = 0.05, dependsOn = "idleDim",
		desc = "Share of a frame's normal opacity while the HUD is dimmed." }
	return rows
end

local function Defaults()
	local defaults = CopyTable(E.defaults.general.quietHUD)
	defaults.follow = {}
	for _, name in ipairs(E:VisibilityModules()) do defaults.follow[name] = false end
	return defaults
end

E:RegisterEvent("PLAYER_LOGIN", function()
	if not E.RegisterConfigPage then return end
	local page = E:RegisterConfigPage("visibility", "Visibility", nil,
		function() return proxy end,
		function()
			E:ApplyIdleAlpha()
			E:UpdatePixelShift()
			E:QuietTick()
			E:RefreshVisibility()
		end, 3.2)
	if page then
		page.build = BuildRows
		page.defaults = Defaults
		page.desc = L["Fade the HUD while you are idle, the Show HUD key, and OLED care."]
	end
end, proxy, "pages")
