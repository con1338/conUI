-- EldoUI Action Bars: spell cues.
--
-- Two cues on the action buttons, off by default:
--   * Proc flash: when the game lights a spell with its own spell alert (a
--     proc or a reactive spell), the buttons that hold it flash once, with
--     an optional sound (off by default).
--   * Buffs on the button: a buff of yours that changes a spell (Maelstrom
--     Weapon on Lightning Bolt, Clearcasting, Nightfall) glows on that
--     spell's buttons with its stack count, and your own effects (a damage
--     or heal over time, a shield, a seal) glow on their own button while
--     they last. The pairs are per class (CueData.lua).
--
-- Rules: the game draws every buff cue. Each one is an aura slot of the
-- game's own aura container (E.AuraWidget) that the client fills while the
-- aura is there and empties when it goes; EldoUI never reads an aura,
-- cooldown or resource, never guesses what to press, never casts. The
-- flash follows the game's own spell alert event only.
--
-- Buttons: EldoUI's bars, every bar built on LibActionButton, other bar
-- addons' buttons and Blizzard's own bars (while Blizzard UI > "Action
-- button look" allows Improve), like the spell rank check. Cue frames are EldoUI's own: the
-- buttons are never moved, resized, shown, hidden or written to. Slots are
-- made out of combat for every page a button can show; in combat a page
-- change only points each slot at its unit or at none. Bars or talents
-- changed in combat are picked up when it ends.
-- Written from scratch for EldoUI.
local _, E = ...

local M = E:GetModule("ActionBars")

local issecret = issecretvalue or function() return false end

local FEATURE = "cues"
local GLOW_BUFF, GLOW_OWN = "cueBuff", "cueOwn"
local SOUND_GAP = 0.5

E:RegisterGlowUser(GLOW_BUFF, {
	title = "Spell cues: buff",
	desc = "Buttons of a spell that one of your buffs changes, while you have it (Action Bars, Spell cues). Its stacks show on the button.",
	order = 16,
	button = true,
	default = { style = "pixel", colorMode = "custom", color = { 0.35, 0.8, 1 } },
})
E:RegisterGlowUser(GLOW_OWN, {
	title = "Spell cues: your effect",
	desc = "An action button while its effect on you or your target lasts: a damage or heal over time, a shield, a seal (Action Bars, Spell cues).",
	order = 17,
	button = true,
	default = { style = "pixel", colorMode = "custom", color = { 0.4, 1, 0.45 } },
})

local function Settings()
	return M.db and M.db.cues
end

local function Setting(key, default)
	local settings = Settings()
	local value = settings and settings[key]
	if value == nil then return default end
	return value
end

local function Plain(value)
	return not issecret(value) and value ~= nil
end

-- Is this part of the cues on right now?
function M:CuesOn(part)
	if not Setting("enabled", false) or E:StandsBack(self, FEATURE) then return false end
	if part == nil then return true end
	return Setting(part, part ~= "sound") and true or false
end

---------------------------------------------------------------------------
-- Spells and slots
---------------------------------------------------------------------------
local function SpellName(id)
	if not (C_Spell and C_Spell.GetSpellName) or not Plain(id) then return nil end
	local name = C_Spell.GetSpellName(id)
	if type(name) == "string" and not issecret(name) and name ~= "" then return name end
end

-- The spell on `slot` (a spell, or a macro that shows one right now).
local function SlotSpell(slot)
	if not GetActionInfo or type(slot) ~= "number" or issecret(slot) then return nil end
	local kind, id, subType = GetActionInfo(slot)
	if issecret(kind) or issecret(id) or type(id) ~= "number" then return nil end
	if kind == "spell" or (kind == "macro" and subType == "spell") then return id end
end

-- Every action slot a button can show, its current one included:
-- LibActionButton's action states, Blizzard's main bar pages (bar pages,
-- stances and forms), and the one slot of every other button.
-- Storage slots above 180 belong to the controller's own bar pages; only
-- the ones the game confirms as the player's own count.
local function GamepadSlot(slot)
	local slots = E.GamepadActionSlots and E:GamepadActionSlots()
	if type(slots) ~= "table" then return false end
	for _, valid in ipairs(slots) do
		if valid == slot then return true end
	end
	return false
end

local function Candidates(button, current)
	local list, seen = {}, {}
	local function Add(slot)
		if type(slot) == "number" and not issecret(slot) and not seen[slot]
			and (slot >= 1 and slot <= 180 or slot > 180 and GamepadSlot(slot)) then
			seen[slot] = true
			list[#list + 1] = slot
		end
	end
	Add(current)
	local types, actions = rawget(button, "state_types"), rawget(button, "state_actions")
	if type(types) == "table" and type(actions) == "table" then
		for state, kind in pairs(types) do
			if kind == "action" then Add(tonumber(actions[state])) end
		end
	end
	local name = button.GetName and button:GetName()
	local index = type(name) == "string" and not issecret(name) and tonumber(name:match("^ActionButton(%d+)$"))
	if index and index <= 12 then
		for page = 1, 10 do Add(index + (page - 1) * 12) end
	end
	return list
end

-- The slot a button shows now (read in combat too: plain fields only).
local function CurrentSlot(button)
	local kind = rawget(button, "_state_type")
	if type(kind) ~= "nil" then
		if issecret(kind) or kind ~= "action" then return nil end
		local slot = rawget(button, "_state_action")
		if type(slot) == "number" and not issecret(slot) then return slot end
		return nil
	end
	local slot = button.action
	if type(slot) == "number" and not issecret(slot) then return slot end
end

---------------------------------------------------------------------------
-- What shows on which spell (out of combat, from the class data)
---------------------------------------------------------------------------
local function AddIDs(set, ids)
	for _, id in ipairs(ids or {}) do
		if type(id) == "number" then set[id] = true end
	end
end

-- name -> list of { unit, kind, mine, ids = { [spellID] = true }, glow }
local function CueTable(scan)
	local _, class = UnitClass("player")
	local data = E.SpellCueData and E.SpellCueData[class]
	local cues = {}
	if not data then return cues end
	local function Ranks(id)
		local name = SpellName(id)
		return name and scan.ids and scan.ids[name]
	end
	local function Add(name, cue)
		if not name then return end
		cues[name] = cues[name] or {}
		table.insert(cues[name], cue)
	end
	if M:CuesOn("buffs") then
		for _, pair in ipairs(data.pairs or {}) do
			local ids = {}
			AddIDs(ids, pair.auras)
			for _, id in ipairs(pair.ranksOf or {}) do AddIDs(ids, Ranks(id)) end
			for _, on in ipairs(pair.on or {}) do
				Add(SpellName(on), { unit = pair.unit, kind = pair.kind, mine = pair.mine, ids = ids, glow = GLOW_BUFF })
			end
		end
	end
	if M:CuesOn("own") then
		for _, own in ipairs(data.own or {}) do
			local id, unit, kind, mine = own[1], own[2], own[3], own[4]
			local ids = { [id] = true }
			AddIDs(ids, Ranks(id))
			Add(SpellName(id), { unit = unit, kind = kind, mine = mine, ids = ids, glow = GLOW_OWN })
		end
	end
	return cues
end

-- The aura ids of a spell's cues, sorted: a newly learned rank changes
-- them, and with them the plan, even when the button and slot stay.
local function CueIDs(list)
	local ids = {}
	for _, cue in ipairs(list) do
		for id in pairs(cue.ids) do ids[#ids + 1] = id end
	end
	table.sort(ids)
	return table.concat(ids, "/")
end

---------------------------------------------------------------------------
-- Cue frames
---------------------------------------------------------------------------
-- button -> { overlay = frame, slots = { [slot] = { [unit] = container } } }
local built = setmetatable({}, { __mode = "k" })
local signature
local pending = false

local function Overlay(button, entry)
	if entry.overlay then return entry.overlay end
	local overlay = CreateFrame("Frame", nil, button)
	overlay:SetAllPoints(button)
	overlay:EnableMouse(false)
	entry.overlay = overlay
	return overlay
end

-- A slot frame covers its button and carries the glow; the stack count
-- sits in its top right corner (the action count keeps the bottom right).
local function Initializer(target, glowKey, stacks)
	return function(frame)
		frame:ClearAllPoints()
		frame:SetAllPoints(target)
		local level = target:GetFrameLevel()
		if type(level) == "number" and not issecret(level) then frame:SetFrameLevel(level + 2) end
		if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(false) end
		if frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(false) end
		E:ShowUserGlow(frame, glowKey)
		if stacks and frame.SetApplicationCount then
			local count = frame:CreateFontString(nil, "OVERLAY")
			E:SetFont(count, E.tokens.size.label, "OUTLINE")
			count:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -2)
			pcall(frame.SetApplicationCount, frame, count, {})
		end
	end
end

local function ReleaseAll()
	local widget = E.AuraWidget
	for _, entry in pairs(built) do
		for _, units in pairs(entry.slots) do
			for _, container in pairs(units) do
				if widget then widget.Release(container) end
			end
		end
		entry.slots = {}
	end
end

local function UpdateActive()
	local widget = E.AuraWidget
	if not widget then return end
	for button, entry in pairs(built) do
		-- A hidden button hides its cue frames with it (they are its
		-- children), so only the slot counts here.
		local current = CurrentSlot(button)
		for slot, units in pairs(entry.slots) do
			local on = slot == current
			for unit, container in pairs(units) do
				if container.cueUnitOn ~= on then
					container.cueUnitOn = on
					widget.SetUnit(container, on and unit or "none")
				end
			end
		end
	end
end
M.UpdateCueSlots = UpdateActive

-- The cues on this button's current slot (for the options preview):
-- { [unit] = container }, or nil.
function M:CueContainers(button)
	local entry = built[button]
	local current = button and CurrentSlot(button)
	return entry and current and entry.slots[current] or nil
end

function M:RefreshCues()
	if InCombatLockdown() then
		pending = true
		return false
	end
	pending = false
	local widget = E.AuraWidget
	local cues = {}
	if self:CuesOn() and (self:CuesOn("buffs") or self:CuesOn("own")) and widget and widget.SlotsAvailable() then
		cues = CueTable(self:RankScan())
	end
	-- What would be built: button, slot, spell name per cue.
	local plan, parts = {}, {}
	if next(cues) then
		M.ForEachActionButton(function(button, current)
			for _, slot in ipairs(Candidates(button, current)) do
				local name = SpellName(SlotSpell(slot))
				if name and cues[name] then
					plan[#plan + 1] = { button = button, slot = slot, cues = cues[name] }
					parts[#parts + 1] = tostring(button) .. ":" .. slot .. ":" .. name .. ":" .. CueIDs(cues[name])
				end
			end
		end, Setting("otherBars", true))
	end
	table.sort(parts)
	local sig = table.concat(parts, ",") .. "|" .. tostring(Setting("stacks", true)) .. "|" .. tostring(Setting("buffs", true))
		.. tostring(Setting("own", true)) .. "|" .. (E.pixel or 1)
	if sig == signature then
		UpdateActive()
		return true
	end
	ReleaseAll()
	signature = sig
	local stacks = Setting("stacks", true)
	for _, item in ipairs(plan) do
		local entry = built[item.button] or { slots = {} }
		built[item.button] = entry
		local overlay = Overlay(item.button, entry)
		local byUnit = {}
		for index, cue in ipairs(item.cues) do
			local filter = (cue.kind == "HARMFUL" and "HARMFUL" or "HELPFUL") .. (cue.mine and "|PLAYER" or "")
			byUnit[cue.unit] = byUnit[cue.unit] or {}
			table.insert(byUnit[cue.unit], {
				key = "cue" .. index, filter = filter,
				candidateFilters = { includeSpellIDs = CopyTable(cue.ids) },
				initialize = Initializer(item.button, cue.glow, stacks),
			})
		end
		local units = {}
		for unit, slots in pairs(byUnit) do
			-- A released container comes back only for the same button and
			-- the same slots (its frames cover that button), so a rebuild
			-- that keeps a cue makes no new frames.
			local keyParts = { tostring(item.button), unit, tostring(stacks) }
			for _, slot in ipairs(slots) do
				local ids = {}
				for id in pairs(slot.candidateFilters.includeSpellIDs) do ids[#ids + 1] = id end
				table.sort(ids)
				keyParts[#keyParts + 1] = slot.key .. "=" .. slot.filter .. ":" .. table.concat(ids, ".")
			end
			local key = "cue:" .. table.concat(keyParts, "|")
			local container = widget.FromPool(key, overlay)
			if container then
				container:ClearAllPoints()
				container:SetPoint("TOPLEFT", overlay, "TOPLEFT")
				container:Show()
			else
				container = widget.CreateSlots(overlay, { unit = "none", slots = slots })
				if container then widget.PoolAs(container, key) end
			end
			if container then
				widget.SetUnit(container, "none")
				container.cueUnitOn = false
				units[unit] = container
			end
		end
		entry.slots[item.slot] = units
	end
	UpdateActive()
	return true
end

local function QueueRefresh()
	E:Debounce("bars:cues", 0.2, function() M:RefreshCues() end)
end

local function QueueActive()
	E:Debounce("bars:cues:active", 0.05, UpdateActive)
end

---------------------------------------------------------------------------
-- Proc flash
---------------------------------------------------------------------------
local flashOverlays = setmetatable({}, { __mode = "k" })
local lastSound = 0

local function FlashOwner(button)
	local owner = flashOverlays[button]
	if owner or InCombatLockdown() then return owner end
	owner = CreateFrame("Frame", nil, button)
	owner:SetAllPoints(button)
	owner:EnableMouse(false)
	flashOverlays[button] = owner
	return owner
end

-- Make the flash frames out of combat, so a proc in combat finds them.
local function PrepareFlash()
	if InCombatLockdown() or not M:CuesOn("flash") then return end
	M.ForEachActionButton(function(button) FlashOwner(button) end, Setting("otherBars", true))
end

function M:FlashProc(spellID)
	if not self:CuesOn("flash") or not Plain(spellID) then return 0 end
	local name = SpellName(spellID)
	local count = 0
	M.ForEachActionButton(function(button, slot)
		if not (button.IsVisible and button:IsVisible()) then return end
		local id = SlotSpell(slot)
		if id and (id == spellID or (name and SpellName(id) == name)) then
			local owner = FlashOwner(button)
			if owner and E.FrameFX then
				E.FrameFX.Flash(owner, button, { enabled = true, duration = 0.35 })
				count = count + 1
			end
		end
	end, Setting("otherBars", true))
	if count > 0 and self:CuesOn("sound") then
		local now = GetTime()
		if now - lastSound >= SOUND_GAP then
			lastSound = now
			E:PlayMedia(Setting("soundFile", "eldo:EldoChime"), Setting("soundChannel", "Master"))
		end
	end
	return count
end

---------------------------------------------------------------------------
-- Settings changed (options page, profile switch, a Blizzard UI switch)
---------------------------------------------------------------------------
function M:ApplyCues()
	signature = nil
	PrepareFlash()
	QueueRefresh()
end

---------------------------------------------------------------------------
-- Events. Registered on our own owner key, so the cues work while the
-- Action Bars module is off (on Blizzard's bars).
---------------------------------------------------------------------------
local owner = {}
M.cuesOwner = owner

local function Rebuild()
	if not Setting("enabled", false) and not signature then return end
	if InCombatLockdown() then
		pending = true
		QueueActive()
		return
	end
	PrepareFlash()
	QueueRefresh()
end

for _, event in ipairs({ "ACTIONBAR_SLOT_CHANGED", "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE",
	"PLAYER_TALENT_UPDATE", "PLAYER_ENTERING_WORLD", "UPDATE_MACROS" }) do
	E:RegisterEvent(event, Rebuild, owner)
end

-- Pages, stances and forms: the slots only switch their unit.
for _, event in ipairs({ "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM",
	"UPDATE_SHAPESHIFT_FORMS", "UPDATE_OVERRIDE_ACTIONBAR", "UPDATE_POSSESS_BAR" }) do
	E:RegisterEvent(event, function()
		if next(built) then QueueActive() end
		if not InCombatLockdown() then Rebuild() end
	end, owner)
end

E:RegisterEvent("PLAYER_REGEN_ENABLED", function()
	if pending then
		PrepareFlash()
		QueueRefresh()
	end
end, owner)

-- A new target or pet: the client reads the new unit.
local function RefreshUnit(unit)
	local widget = E.AuraWidget
	if not widget then return end
	for _, entry in pairs(built) do
		for _, units in pairs(entry.slots) do
			if units[unit] and units[unit].cueUnitOn then widget.Refresh(units[unit]) end
		end
	end
end
E:RegisterEvent("PLAYER_TARGET_CHANGED", function() RefreshUnit("target") end, owner)
E:RegisterUnitEvent("UNIT_PET", "player", function() RefreshUnit("pet") end, owner)

E:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", function(_, _, spellID) M:FlashProc(spellID) end, owner)

-- LibActionButton buttons that change state (a stance, a page) report it.
E:RegisterEvent("PLAYER_LOGIN", function()
	for _, libName in ipairs(M.LAB_NAMES or { "LibActionButton-1.0" }) do
		local lib = LibStub and LibStub(libName, true)
		if lib and lib.RegisterCallback then
			lib.RegisterCallback(owner, "OnButtonUpdate", function() if next(built) then QueueActive() end end)
		end
	end
	if Setting("enabled", false) then M:ApplyCues() end
end, owner)

E:RegisterBlizzardHandler("action-button-look", {
	apply = function() M:ApplyCues() end,
	undo = function() M:ApplyCues() end,
})

M.CueCandidates = Candidates
