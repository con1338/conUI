-- Combat Text on enemy nameplates: every hit an enemy takes rises
-- off its plate. The game's UNIT_COMBAT for nameplateN tokens names no
-- attacker, so these are all hits on that enemy (yours, your group's,
-- anyone's) and the options say so. "Only my damage" is not offered: it
-- would mean guessing who hit.
--   * Only nameplateN tokens are read (the event also fires for aliases
--     such as "target"; reading one kind avoids double lines). Target
--     mode keeps the hits whose plate is the target's plate.
--   * EldoUI plates: the line is a child of EldoUI's plate root (plain
--     frame), so it follows the plate's scale and fade. Blizzard plates:
--     the line stays EldoUI's own frame, only anchored to the plate; no
--     field or child is ever put into Blizzard's frame.
--   * Lines are released when the plate goes, the target changes (target
--     mode), the plate mode changes, the profile changes or the module stops.
--   * At most `maxPerPlate` lines per plate and 64 in all.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local M = E:GetModule("CombatText")
local issecret = M.issecret

local MAX_LINES = 64
local RISE = 40       -- room the plate styles move in (height)
local SPREAD = 30     -- sideways room (fountain)

local holder = CreateFrame("Frame", nil, UIParent) -- parent for lines on Blizzard plates
holder:SetAllPoints(UIParent)
holder:SetFrameStrata("LOW")
local active = {}
local pool = {}
local listener = CreateFrame("Frame")
local driver = CreateFrame("Frame")
driver:Hide()
local sides = {} -- unit -> last side (fountain alternates)

M.plateStats = { shown = 0, skipped = 0 }

local function Nameplates()
	local module = E:GetModule("Nameplates")
	return module and module.active and module or nil
end

local function BlizzardPlate(unit)
	if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
	local plate = C_NamePlate.GetNamePlateForUnit(unit, false)
	if not plate or E.FrameCheck(plate, "IsForbidden") then return nil end
	return plate
end

-- Where a line hangs: frame, y offset, and whether it is EldoUI's plate.
local function Anchor(unit)
	local blizzard = BlizzardPlate(unit)
	if not blizzard then return nil end
	local NP = Nameplates()
	if NP and NP.GetPlateAnchor then
		local frame, _, _, y = NP:GetPlateAnchor(unit, "text")
		if frame then return frame, y or 0, frame ~= blizzard end
		return nil
	end
	return blizzard, 0, false
end

local function NewLine()
	local frame = CreateFrame("Frame", nil, holder)
	frame:SetSize(120, 20)
	frame:Hide()
	local text = frame:CreateFontString(nil, "OVERLAY")
	text:SetPoint("CENTER")
	text:SetWordWrap(false)
	return { frame = frame, text = text }
end

local function Release(index)
	local line = active[index]
	if not line then return end
	table.remove(active, index)
	line.frame:Hide()
	line.frame:ClearAllPoints()
	line.frame:SetParent(holder)
	line.text:SetText("")
	line.anchor, line.unit = nil, nil
	line.shownScale, line.shownAlpha, line.shownX, line.shownY, line.visible = nil, nil, nil, nil, nil
	line.flash, line.color, line.crit = nil, nil, nil
	pool[#pool + 1] = line
end

function M:ReleasePlate(unit)
	for index = #active, 1, -1 do
		if not unit or active[index].unit == unit then Release(index) end
	end
	if not unit then wipe(sides) end
end

function M:PlateLineCount(unit)
	if not unit then return #active end
	local count = 0
	for _, line in ipairs(active) do if line.unit == unit then count = count + 1 end end
	return count
end

-- Only what changed since the last frame is set (E3, as in Engine.lua).
-- A line keeps one point, BOTTOM on its plate's anchor, so SetPoint moves
-- it without ClearAllPoints (Release clears it).
local function Update()
	local now = GetTime()
	for index = #active, 1, -1 do
		local line = active[index]
		local p = (now - line.t0) / line.duration
		if p >= 1 or not line.anchor then
			Release(index)
		else
			local x, y, alpha, scale = line.anim.position(p, line, SPREAD, RISE)
			if not scale or scale <= 0 then scale = 1 end
			local frame = line.frame
			if line.shownScale ~= scale then
				frame:SetScale(scale)
				line.shownScale = scale
			end
			x, y = (x or 0) / scale, (line.baseY + (y or 0)) / scale
			if line.shownX ~= x or line.shownY ~= y then
				frame:SetPoint("BOTTOM", line.anchor, "TOP", x, y)
				line.shownX, line.shownY = x, y
			end
			alpha = math.max(0, math.min(1, alpha or 1))
			if line.shownAlpha ~= alpha then
				frame:SetAlpha(alpha)
				line.shownAlpha = alpha
			end
			if line.flash then
				local r, g, b, done = M.FlashColor(line.color, now - line.t0)
				line.text:SetTextColor(r, g, b)
				if done then line.flash = false end
			end
			if not line.visible then
				frame:Show()
				line.visible = true
			end
		end
	end
	if #active == 0 then driver:Hide() end
end
M.UpdatePlateLines = Update -- for the offline test
driver:SetScript("OnUpdate", Update)

local GREEN, GREY = { 0.3, 1, 0.4 }, { 0.8, 0.8, 0.82 }
-- "Ivory, golden critical hits" (the Punchy style): plain hits ivory, so
-- they don't read as damage you take; critical hits gold; the other magic
-- schools in their colors.
local IVORY, GOLD = { 1, 0.95, 0.86 }, { 1, 0.82, 0.25 }

local function Color(kind, payload)
	local db = M.db.plates
	if kind == "heal" or kind == "healCrit" then return GREEN end
	if kind == "avoid" or kind == "mitigate" then return GREY end
	if db.colorMode == "warm" then
		if kind == "crit" then return GOLD end
		-- SchoolColor reads a secret school as no school.
		local school = M:SchoolColor(payload.school)
		if not school or school == M.SCHOOL_COLORS[1] then return IVORY end
		return school
	end
	if db.colorMode == "accent" then return E.media.accentColor end
	if db.colorMode == "school" then return M:SchoolColor(payload.school) or { 1, 1, 1 } end
	return { 1, 1, 1 }
end

-- One line on the plate of `unit`.
local function Add(unit, kind, payload)
	local db = M.db.plates
	local anchor, offset, ours = Anchor(unit)
	if not anchor then
		M.plateStats.skipped = M.plateStats.skipped + 1
		return nil
	end
	-- Room on this plate and in all.
	local count, oldest = 0, nil
	for index, line in ipairs(active) do
		if line.unit == unit then
			count = count + 1
			oldest = oldest or index
		end
	end
	if count >= math.max(1, db.maxPerPlate) and oldest then Release(oldest) end
	if #active >= MAX_LINES then Release(1) end
	for _, line in ipairs(active) do
		if line.unit == unit then line.slot = (line.slot or 0) + 1 end
	end

	local line = table.remove(pool) or NewLine()
	active[#active + 1] = line
	local crit = kind == "crit" or kind == "healCrit"
	local size = db.fontSize
	if crit then size = math.floor(size * db.critScale / 100 + 0.5) end
	line.unit, line.anchor = unit, anchor
	local style = db.style
	-- With motion reduced a pop or a throw rises like the plain style.
	if (style == "platePop" or style == "plateThrow") and not E:MotionOn() then style = "rise" end
	line.anim = M.animations[style] or M.animations.rise
	line.crit = crit
	line.shake = crit and E:MotionOn()
	line.duration = ((crit and line.anim.critDuration) or line.anim.duration) / math.max(0.1, M.db.scroll.speed / 100)
	line.t0 = GetTime()
	line.slot = 0
	line.lineHeight = size + 2
	sides[unit] = -(sides[unit] or 1)
	line.side = sides[unit]
	line.baseY = offset + db.offsetY
	local parent = (ours and db.followPlate) and anchor or holder
	line.frame:SetParent(parent)
	if parent == anchor then line.frame:SetFrameLevel(anchor:GetFrameLevel() + 30) end
	line.frame:SetSize(120, size + 4)
	local outline = db.outline or "OUTLINE"
	E:SetMediaFont(line.text, db.font or "THEME", size, outline == "NONE" and "" or outline)
	M.SetTextShadow(line.text, db.shadow, size)
	local color = Color(kind, payload)
	line.color = color
	-- A flashing critical hit starts white (the updater turns it to its color).
	line.flash = crit and db.flash and true or false
	if line.flash then
		line.text:SetTextColor(1, 1, 1)
	else
		line.text:SetTextColor(color[1], color[2], color[3])
	end
	line.shownScale, line.shownAlpha, line.shownX, line.shownY = nil, nil, nil, nil
	if payload.type then
		line.text:SetText(payload.type)
	else
		local amount = M:FormatNumber(payload.amount)
		if issecret(amount) then
			line.text:SetFormattedText("%s", amount)
		else
			line.text:SetText(((kind == "heal" or kind == "healCrit") and "+" or "") .. tostring(amount))
		end
	end
	line.frame:Hide()
	line.visible = false
	driver:Show()
	M.plateStats.shown = M.plateStats.shown + 1
	return line
end
M.AddPlateLine = Add

-- The plate lines on screen (read only).
function M:PlateLines()
	return active
end

local function InGroup()
	return IsInGroup and IsInGroup() or false
end

-- True when hits on `unit` may show (enemy, mode, group rule).
local function Wanted(unit)
	local db = M.db.plates
	if InGroup() and not db.inGroup then return false end
	local enemy = UnitCanAttack("player", unit)
	if issecret(enemy) or not enemy then return false end
	if db.units == "target" then
		local plate = BlizzardPlate(unit)
		return plate ~= nil and plate == BlizzardPlate("target")
	end
	return true
end

listener:SetScript("OnEvent", function(_, event, unit, action, flags, amount, school)
	if event == "NAME_PLATE_UNIT_REMOVED" then
		M:ReleasePlate(unit)
		return
	end
	if event == "PLAYER_TARGET_CHANGED" then
		if M.db.plates.units == "target" then M:ReleasePlate(nil) end
		return
	end
	if issecret(unit) or type(unit) ~= "string" or not unit:match("^nameplate%d+$") then return end
	local kind, payload = M.ParseUnitCombat(action, flags, amount, school)
	if not kind or kind == "energize" then return end
	local db = M.db.plates
	if (kind == "avoid" or kind == "mitigate") and not db.words then return end
	if (kind == "heal" or kind == "healCrit") and not db.heals then return end
	if not Wanted(unit) then return end
	M.probe.plates = M.probe.plates + 1
	Add(unit, kind, payload)
end)

local function OnPlateCallback(event, unit)
	if event == "REMOVED" and unit then
		M:ReleasePlate(unit)
	elseif event == "MODE" then
		M:ReleasePlate(nil)
	end
end

local callbackSet = false
local function Register()
	listener:UnregisterAllEvents()
	M:ReleasePlate(nil)
	local NP = E:GetModule("Nameplates")
	if not M:PlatesRunning() then
		if callbackSet and NP then NP:UnregisterPlateCallback("CombatText") end
		callbackSet = false
		return
	end
	listener:RegisterEvent("UNIT_COMBAT")
	listener:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
	listener:RegisterEvent("PLAYER_TARGET_CHANGED")
	if NP and NP.RegisterPlateCallback then
		NP:RegisterPlateCallback("CombatText", OnPlateCallback)
		callbackSet = true
	end
end
M.RegisterPlates = Register

-- Sample hits on your target's plate (from /eui sct test).
function M:PlateTest()
	if not self:PlatesRunning() then return end
	for index = 1, 40 do
		local unit = "nameplate" .. index
		if UnitExists(unit) and BlizzardPlate(unit) and BlizzardPlate(unit) == BlizzardPlate("target") then
			Add(unit, "damage", { amount = 1234, school = 1 })
			Add(unit, "crit", { amount = 4321, school = 4 })
			if self.db.plates.words then Add(unit, "avoid", { type = M.Word("PARRY") }) end
			return true
		end
	end
	return false
end

M:AddPart("Plates", {
	enable = Register,
	refresh = Register,
	disable = function()
		listener:UnregisterAllEvents()
		M:ReleasePlate(nil)
		local NP = E:GetModule("Nameplates")
		if callbackSet and NP then NP:UnregisterPlateCallback("CombatText") end
		callbackSet = false
		driver:Hide()
	end,
})
