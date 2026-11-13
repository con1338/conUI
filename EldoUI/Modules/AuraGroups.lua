-- EldoUI aura groups: free-standing rows of aura icons, each with
-- its own mover. A group shows the auras from a spell list on one unit
-- (you, your target, focus or pet), each spell in a fixed place in list
-- order: buffs and debuffs in one row, up to 20 icons, optionally only the
-- ones you cast.
--
-- How (WoW: Forever, Midnight rules): every spell is one aura slot of the
-- client's aura container (E.AuraWidget.CreateSlots, candidate filters
-- with that spell's ID). The client shows the slot's button while the aura
-- is on the unit and hides it otherwise; it draws the icon, the time and
-- the stack count. EldoUI never reads an aura.
--   Missing look   a faded copy of the spell's icon sits *under* each slot
--                  (our own frame, always there). While the aura is up the
--                  client's button covers it; while it is gone the faded
--                  icon shows. Nothing checks the aura. "Hide" leaves the
--                  place empty instead.
--   Timer bars     the slot's button is a bar the client runs from the
--                  aura's own duration (StatusBar:SetTimerDuration inside
--                  the client); the faded row under it shows the spell
--                  while the aura is missing.
--   Refresh glow   the client's pandemic flag shows a glow region on the
--                  button (General > Glows, "Aura groups: refresh window");
--                  only auras the game marks as refreshable ever glow.
--   Visibility     each group has the shared visibility rules (combat,
--                  group, instance, talent group and the rest) and can
--                  show only in one of your stances or forms. They change
--                  the holder's alpha only: the client's aura container is
--                  never hidden, moved or rebuilt for them. Move mode
--                  always shows the groups.
--   Sounds         a sound when one of the group's auras starts or ends is
--                  handed to the client (C_UnitAuras.AddAuraSound, one per
--                  spell and trigger, registered out of combat): the game
--                  plays it, also in combat, and EldoUI never learns
--                  whether the aura is up. Sound files only; the client
--                  limits each to one play per THROTTLE seconds.
-- The client applies spell lists only where Blizzard allows it (buffs on
-- friendly units, debuffs on enemies); that limit is kept, not worked
-- round.
-- Written from scratch for EldoUI.
-- The spell IDs here are checked against the WoW: Forever client tables of
-- build 1.60.1.70862.
local _, E = ...
local L = E.L

local W = E.AuraWidget

local MAX_GROUPS = 6
local MAX_ICONS = 20
local UNIT_EVENTS = { target = "PLAYER_TARGET_CHANGED", focus = "PLAYER_FOCUS_CHANGED" }

local function Group(index, extra)
	local group = {
		enabled = false,
		name = ("Group %d"):format(index),
		unit = "player",
		spells = "",          -- spell names or IDs, in order
		list = "",            -- an allow list from the Aura filters page, after the typed spells
		kind = "HELPFUL",     -- HELPFUL | HARMFUL | BOTH
		mine = true,          -- only auras you or your pet cast
		missing = "faded",    -- faded | hide
		missingAlpha = 35,
		display = "ICONS",    -- ICONS | BARS
		size = 36, spacing = 4, perRow = 10, growth = "RIGHT",
		barWidth = 180, barHeight = 18,
		duration = "SWIPE",   -- SWIPE | TEXT | BOTH | NONE
		durationSize = 12, countSize = 12,
		example = "",         -- the example that filled the group (kept through edits)
		form = 0,             -- 0 any, -1 no stance or form, else the form's spell ID
		soundStart = "none",  -- a file sound the game plays when an aura comes on
		soundEnd = "none",    -- and when it goes
		visibility = E:VisibilityDefaults(),
	}
	for key, value in pairs(extra or {}) do group[key] = value end
	return group
end

local defaults = { edit = 1, example = "", groups = {} }
for index = 1, MAX_GROUPS do defaults.groups["g" .. index] = Group(index) end

-- One mover per group, EldoUI_AuraGroup1 to 6 (Core/Movers.lua, mover
-- families): group n keeps its slot, so its saved position stays its own.
local MOVER_BASE = "EldoUI_AuraGroup"
E:RegisterMoverFamily(MOVER_BASE, { module = "AuraGroups", slots = MAX_GROUPS })

local M = E:NewModule("AuraGroups", {
	title = "Aura Groups",
	desc = "Your own rows of aura icons, each with its own mover: pick the spells, the unit and whether only yours count. The game shows each aura; EldoUI only places and dresses the icons.",
	category = "Combat",
	frames = {},
	movers = {
		"EldoUI_AuraGroup1", "EldoUI_AuraGroup2", "EldoUI_AuraGroup3", "EldoUI_AuraGroup4",
		"EldoUI_AuraGroup5", "EldoUI_AuraGroup6",
	},
	blizzard = {},
	savedKeys = { "profile.modules.AuraGroups" },
	optionsPage = "module:AuraGroups",
	presets = { "Bars", "Compact", "Icons", "Large", "OnlyUp" },
	reload = false,
	defaults = defaults,
})

E:RegisterGlowUser("auraRefresh", {
	title = "Aura groups: refresh window",
	desc = "Icons in your aura groups while the game marks the aura as safe to refresh early. Only auras the game marks ever glow.",
	order = 45,
	button = true,
	default = { style = "pulse", colorMode = "custom", color = { 1, 0.82, 0 } },
})

local built = {}   -- index -> { holder, mover, container, sig, places = { frame, ... } }

local function GroupDB(index) return M.db.groups["g" .. index] end

---------------------------------------------------------------------------
-- Spells
---------------------------------------------------------------------------
-- Typed spells first, then the chosen list's spells (by ID), at most 20.
function M.Spells(group)
	local ids, seen = {}, {}
	local function Add(id)
		if id and not seen[id] and #ids < MAX_ICONS then
			seen[id] = true
			ids[#ids + 1] = id
		end
	end
	for word in tostring(group.spells or ""):gmatch("[^,;\n]+") do
		Add(E:ResolveSpell(word))
	end
	local list = group.list ~= "" and E:GetAuraFilterList(group.list)
	if list then
		local fromList = {}
		for id in pairs(list.spells) do fromList[#fromList + 1] = id end
		table.sort(fromList)
		for _, id in ipairs(fromList) do Add(id) end
	end
	return ids
end

local KINDS = { HELPFUL = { "HELPFUL" }, HARMFUL = { "HARMFUL" }, BOTH = { "HELPFUL", "HARMFUL" } }

---------------------------------------------------------------------------
-- Layout: place `index` of a group, and the size of the whole group.
---------------------------------------------------------------------------
local function Element(group)
	if group.display == "BARS" then return group.barWidth, group.barHeight end
	return group.size, group.size
end

local function Settings(group)
	local settings = {
		size = group.size, spacing = group.spacing,
		duration = group.duration, durationSize = group.durationSize, countSize = group.countSize,
		durationPoint = "BELOW", tooltip = true, refreshGlow = "auraRefresh",
	}
	if group.display == "BARS" then
		settings.bar = { width = group.barWidth, height = group.barHeight }
		if settings.duration == "SWIPE" then settings.duration = "TEXT" end
	end
	return settings
end

local function TextRoom(group)
	if group.display == "BARS" then return 0 end
	return W.TextRoom(Settings(group))
end

-- Returns point, x, y from the holder for spell number `index`.
function M.Place(group, index)
	local w, h = Element(group)
	local sp = group.spacing or 0
	local room = TextRoom(group)
	local perRow = math.max(1, group.perRow or 10)
	local col, line = (index - 1) % perRow, math.floor((index - 1) / perRow)
	local growth = group.growth
	if growth == "LEFT" then
		return "TOPRIGHT", -col * (w + sp), -line * (h + sp + room)
	elseif growth == "DOWN" then
		return "TOPLEFT", line * (w + sp), -col * (h + sp + room)
	elseif growth == "UP" then
		return "BOTTOMLEFT", line * (w + sp), col * (h + sp + room)
	end
	return "TOPLEFT", col * (w + sp), -line * (h + sp + room)
end

local function GroupSize(group, count)
	local w, h = Element(group)
	local sp = group.spacing or 0
	local room = TextRoom(group)
	local perRow = math.max(1, group.perRow or 10)
	count = math.max(count, 1)
	local along, lines = math.min(count, perRow), math.ceil(count / perRow)
	if group.growth == "DOWN" or group.growth == "UP" then
		return lines * (w + sp) - sp, along * (h + sp + room) - sp
	end
	return along * (w + sp) - sp, lines * (h + sp + room) - sp
end

---------------------------------------------------------------------------
-- Placeholders: our own faded icon (or bar row) under each slot.
---------------------------------------------------------------------------
local function Placeholder(entry, index)
	local frame = entry.places[index]
	if frame then return frame end
	frame = CreateFrame("Frame", nil, entry.content)
	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	E:TrimIcon(frame.icon)
	frame.icon:SetDesaturated(true)
	frame.bar = frame:CreateTexture(nil, "ARTWORK")
	frame.name = E:CreateText(frame, E.tokens.size.small, "LEFT")
	frame.name:SetWordWrap(false)
	entry.places[index] = frame
	return frame
end

local function DressPlaceholder(frame, group, index, spellID)
	local w, h = Element(group)
	frame:SetSize(w, h)
	frame:ClearAllPoints()
	local point, x, y = M.Place(group, index)
	frame:SetPoint(point, frame:GetParent(), point, x, y)
	E:SetTemplate(frame)
	frame.icon:SetTexture(C_Spell.GetSpellTexture(spellID))
	frame.icon:ClearAllPoints()
	if group.display == "BARS" then
		local side = math.max(h - 2 * E.pixel, 1)
		frame.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
		frame.icon:SetSize(side, side)
		frame.bar:ClearAllPoints()
		frame.bar:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", E.pixel, 0)
		frame.bar:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
		local c = E.media.backdropColor
		frame.bar:SetColorTexture(c[1] or 0, c[2] or 0, c[3] or 0, 1)
		frame.bar:Show()
		local name = C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
		E:SetFont(frame.name, math.max(math.min(h - 4, 13), 8))
		frame.name:ClearAllPoints()
		frame.name:SetPoint("LEFT", frame.bar, "LEFT", 3, 0)
		frame.name:SetPoint("RIGHT", frame.bar, "RIGHT", -3, 0)
		frame.name:SetText(type(name) == "string" and name or "")
		frame.name:Show()
	else
		frame.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
		frame.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
		frame.bar:Hide()
		frame.name:Hide()
	end
	frame:SetAlpha(math.max(0, math.min(100, tonumber(group.missingAlpha) or 35)) / 100)
	frame:SetShown(group.missing == "faded")
end

---------------------------------------------------------------------------
-- Build one group
---------------------------------------------------------------------------
local function Signature(group, ids)
	local parts = { tostring(group.enabled), group.unit, group.kind, tostring(group.mine), group.display, group.missing,
		group.missingAlpha, group.size, group.spacing, group.perRow, group.growth, group.barWidth, group.barHeight,
		group.duration, group.durationSize, group.countSize, E.pixel or 1, table.concat(ids, ","),
		-- Placeholders and slot icons carry the theme's colors and font.
		W.ThemeKey and W.ThemeKey() or "" }
	for index, value in ipairs(parts) do parts[index] = tostring(value) end
	return table.concat(parts, ":")
end

local function Holder(index)
	local entry = built[index]
	if entry then return entry end
	-- The layouts hang each group below the one before it, so that
	-- group's mover is made first; UpdateShown shows it once it is on.
	if index > 1 then Holder(index - 1) end
	entry = { places = {} }
	entry.holder = CreateFrame("Frame", nil, UIParent)
	entry.holder:SetSize(40, 40)
	-- The icons hang on this frame; an example's layout hook may put frames
	-- of its own between it and the holder (M:SetContentParent).
	entry.content = CreateFrame("Frame", nil, entry.holder)
	entry.content:SetAllPoints(entry.holder)
	-- Tag the mover with this module, so the module's export carries it.
	local previous = E.currentModule
	E.currentModule = M
	entry.mover = E:CreateMover(entry.holder, E:MoverFamilyName(MOVER_BASE, index), L["Aura Group %d"]:format(index),
		{ "CENTER", "UIParent", "CENTER", -320, 200 - (index - 1) * 64 })
	E.currentModule = previous
	entry.holder:Hide()
	entry.mover:Hide()
	built[index] = entry
	return entry
end

---------------------------------------------------------------------------
-- Visibility: the shared rules and the stance or form, on the holder's
-- alpha only. Everything read here is the player's own state.
---------------------------------------------------------------------------
local function InMoveMode() return E.IsMoveMode and E:IsMoveMode() or false end

-- The spell ID of the stance or form you are in, 0 for none, or nil while
-- the game does not say.
function M.CurrentForm()
	local index = E.PlainCall(GetShapeshiftForm)
	if type(index) ~= "number" then return nil end
	if index <= 0 then return 0 end
	local spellID = select(4, E.PlainCallEach(GetShapeshiftFormInfo, index))
	return type(spellID) == "number" and spellID or nil
end

-- Does the group's stance or form choice let it show now? An answer the
-- game keeps back counts as yes, so a group never vanishes by mistake.
function M.FormMatches(group)
	local want = tonumber(group.form) or 0
	if want == 0 then return true end
	local now = M.CurrentForm()
	if now == nil then return true end
	if want < 0 then return now == 0 end
	return now == want
end

local function Visibility(index)
	local group = GroupDB(index)
	if type(group.visibility) ~= "table" then group.visibility = E:VisibilityDefaults() end
	return group.visibility
end

local function ApplyVisibility(index, on)
	local entry = built[index]
	if not entry then return end
	local holder = entry.holder
	if not on then
		if E:IsVisibilityAttached(holder) then E:DetachVisibility(holder) end
		return
	end
	E:AttachVisibility(holder, Visibility(index), {
		forceShow = InMoveMode, forceShowFirst = true,
		alpha = function()
			if InMoveMode() then return 1 end
			return M.FormMatches(GroupDB(index)) and 1 or 0
		end,
	})
end

local function UpdateVisibility()
	for _, entry in pairs(built) do
		if E:IsVisibilityAttached(entry.holder) then E:UpdateVisibility(entry.holder) end
	end
end
M.UpdateVisibility = UpdateVisibility

hooksecurefunc(E, "ToggleMoveMode", function()
	if M.active then UpdateVisibility() end
end)

-- The holder shows only while its unit exists (a target group without a
-- target shows nothing, not a row of faded icons).
local function UpdateShown(index)
	local entry, group = built[index], GroupDB(index)
	if not entry then return end
	local on = M.active and group.enabled and entry.count and entry.count > 0
	local exists = group.unit == "player" or UnitExists(group.unit)
	entry.holder:SetShown(on and exists and true or false)
	if entry.mover then entry.mover:SetShown(on and true or false) end
	ApplyVisibility(index, on and true or false)
end

local function Release(entry)
	if entry.container then W.Release(entry.container) end
	entry.container = nil
end

-- The example's layout hook runs after every layout of a group it marks,
-- and once more for the example a group just lost, so it can let go.
local function RunLayoutHooks(index)
	local entry, group = built[index], GroupDB(index)
	if not entry then return end
	local key = group.example ~= "" and group.example or nil
	local keys = { key }
	if entry.example and entry.example ~= key then keys[#keys + 1] = entry.example end
	entry.example = key
	for _, name in ipairs(keys) do
		local def = M.examples[name]
		if def and type(def.onLayout) == "function" then
			local ok, err = pcall(def.onLayout, entry.holder, index)
			if not ok then geterrorhandler()(err) end
		end
	end
end

---------------------------------------------------------------------------
-- Sounds: the client plays them (see the top of the file).
---------------------------------------------------------------------------
local THROTTLE = 2 -- seconds; a burst of the same aura plays once
local sounds = {}  -- index -> { sig, handles = { ... } }
M.sounds = sounds

-- The value the client takes for a sound id: a path or a file ID. Sound
-- kits are refused (the call plays files only).
function M.SoundFile(id)
	if id == nil or id == "none" or id == "" then return nil end
	local entry = E:GetMedia("sound", id)
	if not entry or entry.type ~= "file" then return nil end
	local value = entry.value
	if type(value) == "string" or type(value) == "number" then return value end
	return nil
end

local function SoundApi()
	local auras = C_UnitAuras
	local triggers = Enum and Enum.UnitAuraSoundTrigger
	if auras and auras.AddAuraSound and auras.RemoveAuraSound and triggers then return auras, triggers end
end

local function ClearSounds(index)
	local list = sounds[index]
	if not list then return end
	local auras = C_UnitAuras
	for _, handle in ipairs(list.handles) do
		if auras and auras.RemoveAuraSound then pcall(auras.RemoveAuraSound, handle) end
	end
	sounds[index] = nil
end

-- Register the group's sounds again when anything they use changed.
-- Out of combat only (Layout runs through E:RunOutOfCombat).
local function SyncSounds(index)
	if InCombatLockdown() then return end
	local group, entry = GroupDB(index), built[index]
	local auras, triggers = SoundApi()
	local start, stop = M.SoundFile(group.soundStart), M.SoundFile(group.soundEnd)
	local ids = entry and entry.count and entry.count > 0 and M.Spells(group) or {}
	-- General > Mute EldoUI sounds silences these too.
	local muted = E.db.general.soundMute
	if not (auras and M.active and group.enabled and not muted and (start or stop) and #ids > 0) then
		ClearSounds(index)
		return
	end
	local channel = E:SoundChannel()
	local sig = table.concat({ group.unit, table.concat(ids, ","), tostring(start), tostring(stop), channel }, ":")
	if sounds[index] and sounds[index].sig == sig then return end
	ClearSounds(index)
	local list = { sig = sig, handles = {} }
	local function Add(trigger, file, spellID)
		if not (trigger and file) then return end
		local info = { unitToken = group.unit, spellID = spellID, outputChannel = channel, throttleSeconds = THROTTLE }
		if type(file) == "number" then info.soundFileID = file else info.soundFileName = file end
		local ok, handle = pcall(auras.AddAuraSound, trigger, info)
		if ok and handle ~= nil then list.handles[#list.handles + 1] = handle end
	end
	for _, spellID in ipairs(ids) do
		Add(triggers.Added, start, spellID)
		Add(triggers.Removed, stop, spellID)
	end
	sounds[index] = list
end

function M:BuildGroup(index)
	self:BuildGroupFrames(index)
	RunLayoutHooks(index)
	SyncSounds(index)
end

function M:BuildGroupFrames(index)
	local group = GroupDB(index)
	local entry = built[index]
	if not (self.active and group.enabled) then
		if entry then
			Release(entry)
			entry.sig, entry.count = nil, 0
			for _, frame in ipairs(entry.places) do frame:Hide() end
			UpdateShown(index)
		end
		return
	end
	entry = Holder(index)
	local ids = M.Spells(group)
	local sig = Signature(group, ids)
	if entry.sig == sig then
		UpdateShown(index)
		return
	end
	Release(entry)
	entry.sig = sig
	entry.count = #ids
	entry.holder:SetSize(GroupSize(group, #ids))
	for spot, id in ipairs(ids) do DressPlaceholder(Placeholder(entry, spot), group, spot, id) end
	for spot = #ids + 1, #entry.places do entry.places[spot]:Hide() end
	if #ids > 0 and W.SlotsAvailable() then
		local holder = entry.holder
		local settings = Settings(group)
		local slots = {}
		for spot, id in ipairs(ids) do
			local point, x, y = M.Place(group, spot)
			local function Place(button)
				button:ClearAllPoints()
				button:SetPoint(point, holder, point, x, y)
				button:SetFrameLevel(holder:GetFrameLevel() + 4)
			end
			for _, kind in ipairs(KINDS[group.kind] or KINDS.HELPFUL) do
				local filter, candidateFilters = E:AuraSpellSlotSpec(id, kind, group.mine)
				if filter then
					slots[#slots + 1] = {
						key = ("s%d%s"):format(spot, kind:sub(1, 1)),
						filter = filter, candidateFilters = candidateFilters,
						initialize = W.SlotIcon(settings, Place),
					}
				end
			end
		end
		entry.container = W.CreateSlots(entry.content, { unit = group.unit, slots = slots })
	end
	UpdateShown(index)
end

-- Read-only view of the built groups.
M.built = built

-- The example that filled group `index` and still marks it ("" when none).
function M:GroupExample(index)
	local group = self.db and GroupDB(index)
	return group and group.example or ""
end

-- Whether group `index` is on and shows now (its unit exists).
function M:GroupShown(index)
	local entry = built[index]
	return entry ~= nil and entry.holder:IsShown() and true or false
end

-- Put the group's icons under `parent` (a frame inside its holder), or
-- back on the holder (nil). Out of combat only; returns true when done.
function M:SetContentParent(index, parent)
	local entry = built[index]
	if not entry or InCombatLockdown() then return false end
	parent = parent or entry.holder
	if entry.content:GetParent() ~= parent then
		entry.content:SetParent(parent)
		entry.content:SetAllPoints(entry.holder)
	end
	return true
end

function M:Layout()
	for index = 1, MAX_GROUPS do self:BuildGroup(index) end
end

-- A unit changed (new target, focus or pet): the containers read it again.
local function UnitChanged(unit)
	for index = 1, MAX_GROUPS do
		local entry, group = built[index], GroupDB(index)
		if entry and group.unit == unit then
			if entry.container then W.Refresh(entry.container) end
			UpdateShown(index)
		end
	end
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:OnEnable()
	for unit, event in pairs(UNIT_EVENTS) do
		self:RegisterEvent(event, function() UnitChanged(unit) end)
	end
	self:RegisterEvent("UNIT_PET", function(_, _, owner)
		if owner == "player" then UnitChanged("pet") end
	end)
	self:RegisterEvent("SPELLS_CHANGED", function()
		if M:UpdateExampleRanks() then E:RunOutOfCombat(function() M:Layout() end, "AuraGroups:Ranks") end
	end)
	self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", UpdateVisibility)
	M:UpdateExampleRanks()
	E:RunOutOfCombat(function() M:Layout() end)
end

function M:OnDisable()
	for _, event in pairs(UNIT_EVENTS) do self:UnregisterEvent(event) end
	self:UnregisterEvent("UNIT_PET")
	self:UnregisterEvent("SPELLS_CHANGED")
	self:UnregisterEvent("UPDATE_SHAPESHIFT_FORM")
	E:RunOutOfCombat(function() M:Layout() end)
end

---------------------------------------------------------------------------
-- Examples: ready-made groups other parts of EldoUI offer (Shaman Totems:
-- "Totem buffs on you", for every class). Picking one fills the group the
-- options edit and marks it with the example; its look stays as it is, and
-- the mark stays through edits until another example fills the group.
--   M:AddExample(key, { title, desc, name, unit, kind, mine, spells,
--     lines, class, onLayout = fn(holder, index) })
--     spells   the spell text, or a function that returns it
--     lines    instead of spells: a list of spell lines, each the ranks of
--              one spell from lowest to highest. Each place gets the
--              highest rank you know; a line you don't know yet stays out.
--     class    only that class sees the example in the list
--     onLayout runs after every layout of a group the example marks (and
--              once when it loses the mark)
---------------------------------------------------------------------------
M.examples = {}
function M:AddExample(key, def)
	self.examples[key] = def
end

local function KnowsSpell(id)
	if not C_SpellBook then return false end
	for _, check in ipairs({ C_SpellBook.IsSpellKnown, C_SpellBook.IsSpellInSpellBook }) do
		local ok, known = pcall(check, id)
		if ok and not E.Secret(known) and known then return true end
	end
	return false
end

local function BestRank(ranks)
	for index = #ranks, 1, -1 do
		if KnowsSpell(ranks[index]) then return ranks[index] end
	end
end

-- The spell text an example fills in. For spell lines: the highest known
-- rank of each line; when you know none of them yet, the first rank of
-- each, so the group still shows what it is for.
function M.ExampleSpells(def)
	if type(def.spells) == "function" then return def.spells() or "" end
	if not def.lines then return def.spells or "" end
	local known, first = {}, {}
	for _, ranks in ipairs(def.lines) do
		local best = BestRank(ranks)
		if best then known[#known + 1] = tostring(best) end
		first[#first + 1] = tostring(ranks[1])
	end
	return table.concat(#known > 0 and known or first, ", ")
end

-- True while a group's spell text still holds only ranks of the example's
-- lines, in their order: nobody has edited it, so a new rank may move in.
local function StillExample(def, text)
	local position = 1
	for word in tostring(text or ""):gmatch("[^,;\n]+") do
		local id = tonumber(strtrim(word))
		if not id then return false end
		local found
		while def.lines[position] and not found do
			for _, rank in ipairs(def.lines[position]) do
				if rank == id then found = true break end
			end
			position = position + 1
		end
		if not found then return false end
	end
	return true
end

-- A spell learned: groups an example of spell lines filled, and nobody has
-- edited since, take the new rank or the new spell.
function M:UpdateExampleRanks()
	local changed
	for index = 1, MAX_GROUPS do
		local group = GroupDB(index)
		local def = group.example ~= "" and self.examples[group.example]
		if def and def.lines and StillExample(def, group.spells) then
			local spells = M.ExampleSpells(def)
			if spells ~= group.spells then
				group.spells = spells
				changed = true
			end
		end
	end
	return changed
end

local function ForMyClass(def)
	if not def.class then return true end
	local _, class = UnitClass("player")
	return not E.Secret(class) and def.class == class
end
M.ExampleForMyClass = ForMyClass

function M:ApplyExample(key, index)
	local def = self.examples[key]
	if not def then return false end
	local group = GroupDB(index or tonumber(self.db.edit) or 1)
	group.name = def.name or group.name
	group.unit = def.unit or "player"
	group.kind = def.kind or "HELPFUL"
	group.mine = def.mine and true or false
	group.spells = M.ExampleSpells(def)
	group.list = ""
	group.example = key
	group.enabled = true
	return true
end

-- Class examples (WoW: Forever ranks, from the trainer data).
M:AddExample("mageCrowdControl", {
	class = "MAGE",
	title = "Polymorph on your target",
	desc = "Your Polymorph on your target, with the time it has left, so you see when to cast it again.",
	name = "Polymorph",
	unit = "target", kind = "HARMFUL", mine = true,
	lines = { { 118, 12824, 12825, 12826 } },
})
M:AddExample("priestHeals", {
	class = "PRIEST",
	title = "Renew and shield on your target",
	desc = "Your Renew and Power Word: Shield on the friendly player you target, each with its time left.",
	name = "Renew and shield",
	unit = "target", kind = "HELPFUL", mine = true,
	lines = {
		{ 139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929 },
		{ 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901 },
	},
})
M:AddExample("priestPain", {
	class = "PRIEST",
	title = "Shadow Word: Pain on your target",
	desc = "Your Shadow Word: Pain on the enemy you target, with the time it has left.",
	name = "Shadow Word: Pain",
	unit = "target", kind = "HARMFUL", mine = true,
	lines = { { 589, 594, 970, 992, 2767, 10892, 10893, 10894 } },
})
M:AddExample("druidHeals", {
	class = "DRUID",
	title = "Heals over time on your target",
	desc = "Your Rejuvenation and Regrowth on the friendly player you target, each with its time left.",
	name = "Heals over time",
	unit = "target", kind = "HELPFUL", mine = true,
	lines = {
		{ 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841 },
		{ 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 },
	},
})
M:AddExample("druidDamage", {
	class = "DRUID",
	title = "Moonfire and more on your target",
	desc = "Your Moonfire, Insect Swarm and Faerie Fire on the enemy you target. Each joins the group once you know it.",
	name = "Druid debuffs",
	unit = "target", kind = "HARMFUL", mine = true,
	lines = {
		{ 8921, 8924, 8925, 8926, 8927, 8928, 8929, 9833, 9834, 9835 },
		{ 5570, 24974, 24975, 24976, 24977 },
		{ 770, 778, 9749, 9907 },
	},
})
M:AddExample("warlockDots", {
	class = "WARLOCK",
	title = "Damage over time on your target",
	desc = "Your Corruption, Bane of Agony and Immolate on the enemy you target. Each joins the group once you know it.",
	name = "Damage over time",
	unit = "target", kind = "HARMFUL", mine = true,
	lines = {
		{ 172, 6222, 6223, 7648, 11671, 11672 },
		{ 980, 1014, 6217, 11711, 11712, 11713 },
		{ 348, 707, 1094, 2941, 11665, 11667, 11668 },
	},
})
M:AddExample("hunterStings", {
	class = "HUNTER",
	title = "Sting and mark on your target",
	desc = "Your Serpent Sting and Hunter's Mark on the enemy you target. Each joins the group once you know it.",
	name = "Sting and mark",
	unit = "target", kind = "HARMFUL", mine = true,
	lines = {
		{ 1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555 },
		{ 1130, 14323, 14324, 14325 },
	},
})
M:AddExample("rogueSlice", {
	class = "ROGUE",
	title = "Slice and Dice on you",
	desc = "Your Slice and Dice with the time it has left, so you see when to refresh it.",
	name = "Slice and Dice",
	unit = "player", kind = "HELPFUL", mine = true,
	lines = { { 5171, 6774 } },
})
M:AddExample("warriorDebuffs", {
	class = "WARRIOR",
	title = "Sunder Armor and more on your target",
	desc = "Your Sunder Armor, Rend and Demoralizing Shout on the enemy you target. Each joins the group once you know it.",
	name = "Warrior debuffs",
	unit = "target", kind = "HARMFUL", mine = true,
	lines = {
		{ 7386, 7405, 8380, 11596, 11597 },
		{ 772, 6546, 6547, 6548, 11572, 11573, 11574 },
		{ 1160, 6190, 11554, 11555, 11556 },
	},
})
M:AddExample("paladinSeal", {
	class = "PALADIN",
	title = "Your seal",
	desc = "The seal on you with the time it has left, so you see when to judge or cast it again. Each seal joins the group once you know it.",
	name = "Seal",
	unit = "player", kind = "HELPFUL", mine = true,
	lines = {
		{ 20154, 20287, 20288, 20289, 20290, 20291, 20292, 20293 },
		{ 21082, 20162, 20305, 20306, 20307, 20308 },
		{ 20375, 20915, 20918, 20919, 20920 },
		{ 20165, 20347, 20348, 20349 },
		{ 20166, 20356, 20357 },
		{ 20164 },
		{ 1311649, 1311656, 20163, 20419, 20421, 20422, 20423 },
	},
})
M:AddExample("shamanShock", {
	class = "SHAMAN",
	title = "Flame Shock on your target",
	desc = "Your Flame Shock on the enemy you target, with the time it has left.",
	name = "Flame Shock",
	unit = "target", kind = "HARMFUL", mine = true,
	lines = { { 8050, 8052, 8053, 10447, 10448 } },
})

function M:OnProfileChanged()
	-- The example row is an action: apply it once, then clear it.
	if self.db.example and self.db.example ~= "" then
		self:ApplyExample(self.db.example)
		self.db.example = ""
	end
	E:RunOutOfCombat(function() M:Layout() end)
end
M.refreshWhenOff = function() M:OnProfileChanged() end

-- A spell list changed (General > Aura filters): groups that use it rebuild.
E:OnAuraFiltersChanged(M, function()
	if not M.active then return end
	E:RunOutOfCombat(function()
		for _, entry in pairs(built) do entry.sig = nil end
		M:Layout()
	end)
end)

---------------------------------------------------------------------------
-- Styles: the look of every group at once (spells and units stay).
---------------------------------------------------------------------------
local function AllGroups(look)
	local groups = {}
	for index = 1, MAX_GROUPS do groups["g" .. index] = CopyTable(look) end
	return { groups = groups }
end

E:RegisterStyles("AuraGroups", {
	{ key = "Icons", title = "Icons", desc = "36 px icons with a swipe and the time on them; missing auras show faded.",
		settings = AllGroups({ display = "ICONS", size = 36, spacing = 4, duration = "SWIPE", missing = "faded", missingAlpha = 35 }) },
	{ key = "Large", title = "Large", desc = "Big 48 px icons with the time under them; missing auras show faded.",
		settings = AllGroups({ display = "ICONS", size = 48, spacing = 6, duration = "TEXT", durationSize = 14, countSize = 14, missing = "faded", missingAlpha = 35 }) },
	{ key = "Compact", title = "Compact", desc = "Small 26 px icons close together with the time on them.",
		settings = AllGroups({ display = "ICONS", size = 26, spacing = 2, duration = "SWIPE", durationSize = 10, countSize = 10, missing = "faded", missingAlpha = 30 }) },
	{ key = "Bars", title = "Timer bars", desc = "Each aura as a timer bar with its name and time, one under the other.",
		settings = AllGroups({ display = "BARS", barWidth = 180, barHeight = 18, spacing = 2, growth = "DOWN", perRow = 20, duration = "TEXT", missing = "faded", missingAlpha = 40 }) },
	{ key = "OnlyUp", title = "Only while up", desc = "Icons show only while the aura is on; nothing marks a missing one.",
		settings = AllGroups({ display = "ICONS", size = 36, spacing = 4, duration = "SWIPE", missing = "hide" }) },
})

---------------------------------------------------------------------------
-- Options: one group at a time (Group), the rows below edit that group.
---------------------------------------------------------------------------
local function Editing()
	local index = M.db and tonumber(M.db.edit) or 1
	return math.max(1, math.min(MAX_GROUPS, index))
end
local function G(field) return function() return ("groups.g%d.%s"):format(Editing(), field) end end
local function Edit() return GroupDB(Editing()) end
local function Off() return not Edit().enabled end
local function NotIcons() return Off() or Edit().display == "BARS" end
local function NotBars() return Off() or Edit().display ~= "BARS" end

local function GroupValues()
	local values = {}
	for index = 1, MAX_GROUPS do
		local group = M.db and GroupDB(index)
		-- The stored default name stays English; it shows translated.
		local default = ("Group %d"):format(index)
		local name = group and group.name ~= "" and group.name ~= default and group.name or L["Group %d"]:format(index)
		values[index] = (group and group.enabled) and ("%d. %s"):format(index, name) or L["%d. %s (off)"]:format(index, name)
	end
	return values
end

local function AllowLists()
	local values = { [""] = "None" }
	for _, name in ipairs(E:GetAuraFilterLists("allow")) do values[name] = name end
	return values
end

M.options = {
	{ type = "description", label = "Rows of aura icons you put together yourself, each with its own mover. Buffs work on friends, debuffs on enemies." },
	{ type = "description", label = "This game client has no aura slots, so aura groups can't show here.",
		hidden = function() return W.SlotsAvailable() end },
	{ type = "select", key = "edit", label = "Group", values = GroupValues,
		desc = "The group the rows below change. Each group has its own mover named Aura group 1 to 6." },
	E:CopySettingsOptions({ path = function() return "groups.g" .. Editing() end,
		values = function()
			local values = {}
			for index, label in pairs(GroupValues()) do values["groups.g" .. index] = label end
			return values
		end,
		keep = { "enabled", "name", "unit", "spells", "list", "kind", "mine", "example", "form", "visibility", "soundStart", "soundEnd" },
		desc = "Copy the look of another group onto this one (icons or bars, size, growth, timers, missing auras), with a preview of what changes first. Its name, switch, unit, spells and visibility stay as they are." })[1],
	{ type = "select", key = "example", label = "Fill from an example", noUndo = true,
		values = function()
			local values = { [""] = "(pick one)" }
			for key, def in pairs(M.examples) do
				if ForMyClass(def) then values[key] = def.title end
			end
			return values
		end,
		valueDescs = function()
			local descs = {}
			for key, def in pairs(M.examples) do
				if ForMyClass(def) then descs[key] = def.desc end
			end
			return descs
		end,
		hidden = function()
			for _, def in pairs(M.examples) do
				if ForMyClass(def) then return false end
			end
			return true
		end,
		desc = "Fills the group above with a ready-made spell list and turns it on. Its look stays as it is." },
	{ type = "header", label = "Auras" },
	{ type = "toggle", key = G("enabled"), label = "Show this group",
		desc = "Turns the group on. Its mover appears in move mode while it is on." },
	{ type = "input", key = G("name"), label = "Name", hidden = Off,
		desc = "A name for this group, shown in the Group list above." },
	{ type = "select", key = G("unit"), label = "Unit", hidden = Off,
		values = { player = "You", target = "Target", focus = "Focus", pet = "Pet" },
		desc = "Whose auras the group shows." },
	{ type = "input", key = G("spells"), label = "Spells", hidden = Off,
		desc = "Spell names or IDs, separated by commas, in the order they should show (up to 20). Shift-click a spell link into the box works too." },
	{ type = "select", key = G("list"), label = "Add spells from", hidden = Off, values = AllowLists,
		desc = "An allow list from the Aura filters page. Its spells come after the ones typed above." },
	{ type = "select", key = G("kind"), label = "Shows", hidden = Off,
		values = { HELPFUL = "Buffs", HARMFUL = "Debuffs", BOTH = "Buffs and debuffs" },
		desc = "Which kind of aura each spell is looked for as. Buffs and debuffs finds either." },
	{ type = "toggle", key = G("mine"), label = "Only yours", hidden = Off,
		desc = "Only auras you or your pet applied. Off: the same spell from anyone counts." },
	{ type = "header", label = "Look" },
	{ type = "select", key = G("display"), label = "Show as", hidden = Off,
		values = { ICONS = "Icons", BARS = "Timer bars" },
		desc = "Icons, or timer bars with the spell's icon, name and time. The game runs the time." },
	{ type = "select", key = G("missing"), label = "When missing", hidden = Off,
		values = { faded = "Show the icon faded", hide = "Leave the place empty" },
		desc = "What a spell's place shows while its aura is not on the unit. The place never moves." },
	{ type = "range", key = G("missingAlpha"), label = "Faded opacity", unit = "%", min = 10, max = 80, step = 5,
		hidden = function() return Off() or Edit().missing ~= "faded" end,
		desc = "How visible a missing aura's icon is." },
	{ type = "range", key = G("size"), label = "Icon size", min = 16, max = 64, step = 1, hidden = NotIcons,
		desc = "Width and height of each icon." },
	{ type = "range", key = G("barWidth"), label = "Bar width", min = 80, max = 320, step = 2, hidden = NotBars,
		desc = "Width of each timer bar." },
	{ type = "range", key = G("barHeight"), label = "Bar height", min = 10, max = 32, step = 1, hidden = NotBars,
		desc = "Height of each timer bar." },
	{ type = "range", key = G("spacing"), label = "Spacing", min = 0, max = 20, step = 1, hidden = Off,
		desc = "Space between icons or bars." },
	{ type = "range", key = G("perRow"), label = "Per row", min = 1, max = 20, step = 1, hidden = Off,
		desc = "Icons in one row (or bars in one column) before a new one starts." },
	{ type = "select", key = G("growth"), label = "Growth direction", hidden = Off,
		values = { RIGHT = "Right", LEFT = "Left", DOWN = "Down", UP = "Up" },
		desc = "The direction the group grows from its mover." },
	{ type = "select", key = G("duration"), label = "Time left as", hidden = NotIcons,
		values = { SWIPE = "Swipe with numbers", TEXT = "Text under the icon", BOTH = "Swipe and text", NONE = "None" },
		desc = "How the time left shows on the icons." },
	{ type = "range", key = G("durationSize"), label = "Time text size", min = 8, max = 20, step = 1, cog = true, hidden = Off,
		desc = "Size of the time left." },
	{ type = "range", key = G("countSize"), label = "Stack size", min = 0, max = 20, step = 1, cog = true, hidden = Off, zeroText = "Off",
		desc = "Size of the stack count." },
}

-- Sounds: the game plays them, so the picks are sound files only.
local FILE_SOUNDS = { playable = "file" }
table.insert(M.options, { type = "header", label = "Sounds", hidden = Off, requiresAPI = "C_UnitAuras.AddAuraSound" })
table.insert(M.options, { type = "media", mediaKind = "sound", filter = FILE_SOUNDS, none = true, key = G("soundStart"),
	label = "Sound when an aura starts", hidden = Off, requiresAPI = "C_UnitAuras.AddAuraSound",
	desc = "The game plays it when one of the group's auras comes on, also in combat. It counts the spell from anyone. Sound files only." })
table.insert(M.options, { type = "media", mediaKind = "sound", filter = FILE_SOUNDS, none = true, key = G("soundEnd"),
	label = "Sound when an aura ends", hidden = Off, requiresAPI = "C_UnitAuras.AddAuraSound",
	desc = "The game plays it when one of the group's auras goes, also in combat. It counts the spell from anyone. Sound files only." })

-- Visibility: the stance or form row, then the shared rows, pointed at the
-- group being edited (the keys are read when a row draws).
local function SpellName(spellID)
	local name = E.PlainCall(C_Spell.GetSpellName, spellID)
	if type(name) == "string" and name ~= "" then return name end
end

local function FormValues()
	local values = { [0] = "Any", [-1] = "No stance or form" }
	local count = E.PlainCall(GetNumShapeshiftForms) or 0
	for index = 1, count do
		local spellID = select(4, E.PlainCallEach(GetShapeshiftFormInfo, index))
		local name = type(spellID) == "number" and SpellName(spellID)
		if name then values[spellID] = name end
	end
	-- A form chosen on another character stays readable, so it can be put back.
	local saved = M.db and tonumber(Edit().form) or 0
	if saved > 0 and not values[saved] then
		values[saved] = SpellName(saved) or ("#" .. saved)
	end
	return values
end

local function NoForms()
	if Off() then return true end
	return (E.PlainCall(GetNumShapeshiftForms) or 0) == 0 and (tonumber(Edit().form) or 0) == 0
end

table.insert(M.options, { type = "header", label = "Visibility", hidden = Off })
table.insert(M.options, { type = "select", key = G("form"), label = "Only in this stance or form",
	values = FormValues, order = function() return { 0, -1 } end, hidden = NoForms,
	desc = "Shows the group only while you are in this stance or form. Any: in every one." })
for _, row in ipairs(E:VisibilityOptions("visibility", { db = function() return Edit() end, hidden = Off, label = false })) do
	local key = row.key
	if type(key) == "string" then row.key = function() return ("groups.g%d.%s"):format(Editing(), key) end end
	table.insert(M.options, row)
end
