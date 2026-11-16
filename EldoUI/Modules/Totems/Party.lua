-- EldoUI Shaman Totems: who your totems reach. Small squares on the party
-- frames (one per element whose running totem gives a buff): filled while
-- the member has the totem's buff, hollow while not, "?" while the game
-- doesn't say. The totem buttons' tooltips list the members without it.
-- Counter hints on enemy tooltips: the counter totem for what a mob was
-- seen casting (Mob Abilities log), out of combat.
--
-- Reading group members' auras is allowed out of combat only on this
-- client, so the squares show "?" during a fight instead of a stale
-- answer; totems without a buff (Searing, Windfury) get no square.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local M = E:GetModule("ShamanTotems")
local D = E.ShamanData
local Try = M.Try
local Plain = E.Plain
local Secret = E.Secret

local Party = {}
M.Party = Party
M:AddPart("party", Party)

local MAX_UNITS = 5

---------------------------------------------------------------------------
-- What runs and what it gives
---------------------------------------------------------------------------
-- element -> totem entry of each running totem the game names.
function M:RunningTotems()
	local running = {}
	local count = Plain(Try(GetNumTotemSlots)) or D.MAX_SLOTS
	for slot = 1, math.min(type(count) == "number" and count or D.MAX_SLOTS, 8) do
		local have, _, _, _, _, _, spellID = Try(GetTotemInfo, slot)
		if not Secret(have) and have then
			local entry = self:TotemOfSpell(Plain(spellID))
			if entry then running[entry.element] = entry end
		end
	end
	return running
end

-- The names that count as covered for a totem: its buff and its own name.
local function CoverNames(entry)
	local names = {}
	local buff = entry.buff and M.SpellName(entry.buff)
	if buff then names[buff] = true end
	local own = M.SpellName(entry.id)
	if own then names[own] = true end
	return names
end

-- The group: you, then party1-4 (raid groups use the same five: the totem
-- reaches your own party only).
local function Units()
	local units = { "player" }
	for index = 1, MAX_UNITS - 1 do
		local unit = "party" .. index
		if Plain(Try(UnitExists, unit)) then units[#units + 1] = unit end
	end
	return units
end

-- Helpful aura names on a unit; nil when the game doesn't say (combat,
-- secret answers).
local function AuraNames(unit)
	if InCombatLockdown() then return nil end
	local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if not get then return nil end
	local names = {}
	for index = 1, 60 do
		local ok, aura = pcall(get, unit, index, "HELPFUL")
		if not ok or Secret(aura) then return nil end
		if not aura then break end
		local name = aura.name
		if Secret(name) then return nil end
		if type(name) == "string" then names[name] = true end
	end
	return names
end
M.AuraNames = AuraNames

-- unit -> element -> true (covered), false (not), nil (unknown).
function M:Coverage()
	local running = self:RunningTotems()
	local result = {}
	for _, unit in ipairs(Units()) do
		local auras = AuraNames(unit)
		local row = {}
		for element, entry in pairs(running) do
			if entry.buff then
				if auras then
					local covered = false
					for name in pairs(CoverNames(entry)) do
						if auras[name] then covered = true break end
					end
					row[element] = covered
				else
					row[element] = "?"
				end
			end
		end
		result[unit] = row
	end
	return result, running
end

-- Tooltip lines for an element button: who the totem doesn't reach.
function M:CoverageLines(tooltip, element)
	if not (self.db.coverageTip and IsInGroup and Plain(Try(IsInGroup))) then return end
	local coverage, running = self:Coverage()
	local entry = running[element]
	if not (entry and entry.buff) then return end
	local missing, unknown = {}, false
	for unit, row in pairs(coverage) do
		if row[element] == "?" then
			unknown = true
		elseif row[element] == false then
			local name = Plain(Try(UnitName, unit))
			missing[#missing + 1] = type(name) == "string" and name or unit
		end
	end
	table.sort(missing)
	if unknown then
		E.UIKit.TipText(tooltip, L["Who it reaches shows again after combat."])
	elseif #missing == 0 then
		E.UIKit.TipText(tooltip, L["It reaches your whole party."])
	else
		E.UIKit.TipText(tooltip, L["Not reached: %s"]:format(table.concat(missing, ", ")))
	end
end

---------------------------------------------------------------------------
-- Squares on the group frames
---------------------------------------------------------------------------
local marks = setmetatable({}, { __mode = "k" }) -- group button -> our square row

local function Row(button)
	local row = marks[button]
	if row or InCombatLockdown() then return row end
	row = CreateFrame("Frame", nil, button)
	row:SetFrameLevel(button:GetFrameLevel() + 6)
	row.squares = {}
	for index = 1, #D.ELEMENTS do
		local square = CreateFrame("Frame", nil, row)
		E:SetTemplate(square)
		square.fill = square:CreateTexture(nil, "ARTWORK")
		square.fill:SetPoint("TOPLEFT", E.pixel, -E.pixel)
		square.fill:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
		square.fill:SetTexture(E.media.flat)
		square.text = E:CreateText(square, E.tokens.size.tiny, "CENTER")
		square.text:SetPoint("CENTER", 0, 0)
		row.squares[index] = square
	end
	marks[button] = row
	return row
end

local function Paint(row, size, states)
	local shown = 0
	for index, element in ipairs(D.ELEMENTS) do
		local square, state = row.squares[index], states[element]
		if state == nil then
			square:Hide()
		else
			shown = shown + 1
			square:SetSize(size, size)
			square:ClearAllPoints()
			square:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(shown - 1) * (size + 1), 0)
			local color = E.tokens.element[element]
			square.fill:SetVertexColor(color[1], color[2], color[3], 1)
			square.fill:SetShown(state == true)
			square.text:SetText(state == "?" and "?" or "")
			square:Show()
		end
	end
	row:SetShown(shown > 0)
end

function Party:Squares()
	return M.db.squares and M:Drawing()
end

-- Many events land at once (cooldowns, auras): draw at most twice a second.
function Party:Update()
	local now = GetTime()
	if self.last and now - self.last < 0.5 then return end
	self.last = now
	self:Draw()
end

function Party:Draw()
	local frames = E.modules.GroupFrames
	if not (frames and frames.IterateButtons) then return end
	local on = self:Squares()
	local coverage = on and M:Coverage() or {}
	local size = M.db.squareSize
	for _, button in frames.IterateButtons() do
		local unit = button.unit or (button.GetAttribute and button:GetAttribute("unit"))
		local row = marks[button]
		if on and type(unit) == "string" and not Secret(unit) then
			-- A party frame shows the row of the unit it holds.
			local states
			for groupUnit, list in pairs(coverage) do
				if Plain(Try(UnitIsUnit, unit, groupUnit)) then states = list break end
			end
			row = row or Row(button)
			if row then
				row:ClearAllPoints()
				row:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
				row:SetSize(4 * (size + 1), size)
				Paint(row, size, states or {})
			end
		elseif row then
			row:Hide()
		end
	end
end

function Party:Tick()
	if self:Squares() then self:Draw() end
end

local auraTimer

function Party:OnGroupAura()
	if auraTimer or not self:Squares() or InCombatLockdown() then return end
	auraTimer = C_Timer.NewTimer(0, function()
		auraTimer = nil
		if M.active and self:Squares() and not InCombatLockdown() then self:Update() end
	end)
end

function Party:Disable()
	if auraTimer then auraTimer:Cancel() auraTimer = nil end
	for _, row in pairs(marks) do row:Hide() end
end

---------------------------------------------------------------------------
-- Counter hints on enemy tooltips (from what the mob was seen casting)
---------------------------------------------------------------------------
-- kind -> true for the mob a unit is (out of combat; nil otherwise).
function M:CounterKindsOf(unit)
	local mobs = E.MobAbilities
	if not (mobs and mobs.HostileNpc and mobs.Seen) or InCombatLockdown() then return nil end
	local npc = mobs.HostileNpc(unit)
	if not npc then return nil end
	local kinds, any = {}, false
	for _, spell in ipairs(mobs:Seen(npc)) do
		local kind = D.counterOf[spell.id]
		if kind then kinds[kind], any = true, true end
	end
	return any and kinds or nil
end

-- For the loadout menu: the counter kinds of your target.
function M:CounterKinds()
	if not self.db.counterHint then return nil end
	return self:CounterKindsOf("target")
end

if E.RegisterTooltipSection then
	E:RegisterTooltipSection("totemCounters", {
		order = 45,
		title = "Counter totems",
		desc = "Shamans: on a mob's tooltip, the totem that answers what you saw it cast (Tremor, Poison Cleansing, Disease Cleansing). Out of combat.",
		default = "always",
		module = "ShamanTotems",
		option = "counterHint",
		unit = function(_, unit, add)
			if not (M:Drawing() and M.db.counterHint) then return end
			local kinds = M:CounterKindsOf(unit)
			if not kinds then return end
			for _, kind in ipairs({ "fear", "poison", "disease" }) do
				local entry = kinds[kind] and D.byKey[D.COUNTER_TOTEM[kind]]
				if entry and M:Known(entry.id) then
					add(L["Counter"], M.SpellName(entry.id) or "")
				end
			end
		end,
	})
end

---------------------------------------------------------------------------
-- "Totem buffs on you" (Aura Groups, for every class): the group dims
-- while the shamans of your party are out of range. The game answers that
-- (UnitInRange) and draws the dim itself (SetAlphaFromBoolean), so each
-- answer is used even while it is secret, and no two answers ever meet in
-- addon code: every party slot has its own gate frame around the group's
-- icons, and the client multiplies the gates' alphas. Each shaman out of
-- range dims the group one step; out of range of all of them, it is at
-- the full dim. EldoUI never measures a distance. Where the game gives no
-- answer for a shaman, that step stays off.
---------------------------------------------------------------------------
local Range = {}
M.TotemBuffRange = Range
Range.ALPHA = 0.45
Range.EXAMPLE = "totemBuffs"
Range.SLOTS = MAX_UNITS - 1

local gates = {} -- group index -> its gate frames, party1 first (innermost last)

-- The party units of the shamans in your party besides you (plain class
-- answers only), and how many there are.
function Range.Shamans()
	local units, count = {}, 0
	for index = 1, Range.SLOTS do
		local unit = "party" .. index
		if Plain(Try(UnitExists, unit)) then
			local _, class = Try(UnitClass, unit)
			if not Secret(class) and class == "SHAMAN" then
				units[unit] = true
				count = count + 1
			end
		end
	end
	return units, count
end

-- The first shaman's unit, or nil.
function Range.ShamanUnit()
	local units = Range.Shamans()
	for index = 1, Range.SLOTS do
		if units["party" .. index] then return "party" .. index end
	end
end

local function AuraGroups()
	local groups = E.modules.AuraGroups
	return groups and groups.built and groups.GroupExample and groups or nil
end

-- One gate per party slot, nested inside the group's holder, with the
-- icons under the innermost one. Built once per group, out of combat.
function Range.Gates(index)
	if gates[index] then return gates[index] end
	local groups = AuraGroups()
	local entry = groups and groups.built[index]
	if not entry or InCombatLockdown() then return nil end
	local list, parent = {}, entry.holder
	for slot = 1, Range.SLOTS do
		local gate = CreateFrame("Frame", nil, parent)
		gate:SetAllPoints(entry.holder)
		list[slot] = gate
		parent = gate
	end
	if not groups:SetContentParent(index, parent) then return nil end
	gates[index] = list
	return list
end

-- Dim one frame by the game's range answer for `unit`, down to `low`
-- (Range.ALPHA when nil). Returns "client" (the game set the alpha),
-- "plain" (a plain answer), or "none" (no answer: full alpha).
function Range.Apply(frame, unit, low)
	low = low or Range.ALPHA
	if not (unit and UnitInRange) then
		frame:SetAlpha(1)
		return "none"
	end
	local ok, inRange, checked = pcall(UnitInRange, unit)
	-- A plain "not checked" means the game did not measure: no answer.
	if not ok or type(inRange) == "nil" or (not Secret(checked) and checked == false) then
		frame:SetAlpha(1)
		return "none"
	end
	if frame.SetAlphaFromBoolean and pcall(frame.SetAlphaFromBoolean, frame, inRange, 1, low) then
		return "client"
	end
	if Secret(inRange) then
		frame:SetAlpha(1)
		return "none"
	end
	frame:SetAlpha(inRange and 1 or low)
	return "plain"
end

-- One group: dimmed by each shaman's gate while the example marks it.
function Range.UpdateGroup(index)
	local groups = AuraGroups()
	if not groups then return end
	local entry, list = groups.built[index], gates[index]
	local group = groups.db and groups.db.groups["g" .. index]
	local marked = groups.active and entry and group and group.enabled and groups:GroupExample(index) == Range.EXAMPLE
	if not marked then
		for _, gate in ipairs(list or {}) do gate:SetAlpha(1) end
		return
	end
	list = list or Range.Gates(index)
	if not list then
		E:RunOutOfCombat(function() Range.UpdateGroup(index) end, "totems:rangeGates:" .. index)
		return
	end
	local shamans, count = Range.Shamans()
	-- n shamans out of range together give the full dim: ALPHA^(1/n) each.
	local low = count > 0 and Range.ALPHA ^ (1 / count) or 1
	for slot, gate in ipairs(list) do
		local unit = "party" .. slot
		if shamans[unit] then
			Range.Apply(gate, unit, low)
		else
			gate:SetAlpha(1)
		end
	end
end

function Range.Update()
	local groups = AuraGroups()
	if not groups then return end
	for index in pairs(groups.built) do Range.UpdateGroup(index) end
end

local rangeEvents = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_IN_RANGE_UPDATE", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }) do
	pcall(rangeEvents.RegisterEvent, rangeEvents, event)
end
rangeEvents:SetScript("OnEvent", function(_, event, unit)
	if event == "UNIT_IN_RANGE_UPDATE" and not (type(unit) == "string" and not Secret(unit) and unit:find("^party")) then return end
	Range.Update()
end)
