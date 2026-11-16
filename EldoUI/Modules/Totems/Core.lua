-- EldoUI Shaman Totems: a totem bar with one button per element and a
-- picker for each, a Drop All button, the running totems' timers, a
-- cooldown bar for shields, weapon imbues and the shaman's cooldowns, up
-- to eight totem loadouts, totem buff squares on the group frames and a
-- group plan for resistance totems and Mana Tide.
--
--   Core.lua       the module, spell knowledge, picks, the Call of the
--                  Elements sync and the hand-over of Blizzard's totem bar
--   Bar.lua        the totem bar, the pickers and Drop All
--   Cooldowns.lua  the cooldown bar
--   Loadouts.lua   loadouts, their menu, share codes and the content rule
--   Party.lua      totem buff squares on group frames, button tooltips
--   Assign.lua     the group plan, the Ready Check Report columns and
--                  the shaman group panel
--   Options.lua    options and style presets
--
-- How it stays within the rules (WoW: Forever, Midnight restrictions):
--   * Every totem, call and spell is cast by a secure action button the
--     player clicks (SecureActionButtonTemplate). EldoUI never casts. The
--     buttons' spells, the pickers and loadout switches are written out of
--     combat only (E:RunOutOfCombat); in combat the bar keeps its spells.
--   * Timers come from the game's own duration objects (GetTotemDuration),
--     drawn by the cooldown widget. A totem's element is known only from
--     the spell the game names for its slot; when the game hides that,
--     the timer waits instead of being guessed. No pulse or tick timers.
--   * Cooldowns use the game's own flags and duration objects, read
--     through EldoUI's one cooldown source (E.CombatKit.Cooldowns), which
--     also says when a cooldown or a totem changed; nothing is compared
--     or computed on a value that may be secret.
--   * Call of the Elements is set only when the player picks a totem or a
--     loadout, or by the opt-in rule that switches loadouts by content;
--     never from what the bar read while the game loaded.
-- Public API (E.Totems, also EldoUI.Totems): see Loadouts.lua and below.
-- Written from scratch for EldoUI: ideas from a public addon's feature
-- list, no code, strings, textures or data from it.
local _, E = ...
local L = E.L
local D = E.ShamanData

local M = E:NewModule("ShamanTotems", {
	title = "Shaman Totems",
	desc = "A totem bar with a picker per element, Drop All and timers, a cooldown bar for shields, imbues and shaman cooldowns, totem loadouts and totem buff squares on group frames. Shamans only.",
	category = "Combat",
	conflicts = { "ShamanPower", "TotemTimers" },
	frames = { "EldoUI_ShamanTotemsHolder", "EldoUI_ShamanTotems", "EldoUI_ShamanCooldownsHolder", "EldoUI_ShamanCooldowns" },
	movers = { "EldoUI_ShamanTotems", "EldoUI_ShamanCooldowns" },
	savedKeys = { "profile.modules.ShamanTotems" },
	optionsPage = "module:ShamanTotems",
	presets = { "CombatOnly", "Compact", "IconsOnly", "Large", "Standard", "TimerBars", "Vertical" },
	reload = false,
	defaults = {
		enabled = false,           -- a new bar on screen: the player (or the shaman setup) turns it on
		picks = { EARTH = "", FIRE = "", WATER = "", AIR = "" }, -- totem key per element ("" = first known)
		hideBlizzard = true,       -- hide Blizzard's totem bar and totem timers while this bar is on
		keepTimers = false,        -- keep Blizzard's totem timers even then
		dropAll = "call",          -- "call": Call of the Elements when known; "sequence": one totem per press
		size = 28,
		spacing = 4,
		vertical = false,
		flyout = "UP",             -- where the pickers open: UP, DOWN, LEFT, RIGHT
		showKeys = true,
		timerText = true,          -- the time left as numbers on the sweep
		timerBars = false,         -- a thin bar under each button
		elementColors = true,      -- a thin element-colored edge under each button
		emptyFade = true,          -- dim an element with no totem down
		visibility = E:VisibilityDefaults(),
		cooldowns = {
			enabled = true,
			size = 28,
			spacing = 4,
			shield = true,
			shieldPick = "",       -- shield key ("" = the first you know)
			imbueMain = true,
			imbuePick = "",        -- main-hand imbue key ("" = the first you know)
			imbueOffPick = "",     -- off-hand imbue key ("" = the main hand's)
			imbueOff = true,
			roleSet = "auto",      -- the spell set: "auto" (your role), "healer", "melee" or "caster"
			filledFor = "",        -- the set the ticks below were filled for ("<set>:<role>", or "<set>:own")
			spells = { recall = true, reincarnation = true, swiftness = true, manatide = true, mastery = true, rage = true },
			ready = false,         -- ready icons for key spells
			readySpells = { earthshock = true, stormstrike = true, riptide = true, firenova = true },
			missingGlow = true,    -- soft glow while the shield or an imbue is missing
		},
		loadouts = {},             -- up to 8: { name, EARTH, FIRE, WATER, AIR }
		activeLoadout = 0,
		contentRule = false,       -- switch loadout by content (acts for the player)
		contentLoadouts = { world = 0, party = 0, raid = 0, pvp = 0 },
		squares = false,           -- totem buff squares on the party frames
		squareSize = 6,
		coverageTip = true,        -- who is covered, on the totem buttons' tooltips
		counterHint = true,        -- counter totems on enemy tooltips (out of combat)
		tremorHint = true,         -- light the earth button while you are feared
		-- Group plan: who drops Mana Tide and each resistance totem (names).
		plan = { enabled = false, share = true, manatide = "", FIRE = "", FROST = "", NATURE = "" },
		groupWindow = {},          -- the shaman group panel's place and size
	},
})

-- "Reset to defaults" keeps the player's own data and window places
-- (E:ResetModuleSettings, Core/Config.lua).
M.keepOnReset = { "loadouts", "activeLoadout", "contentLoadouts" }
M.keepOnResetNote = E.Key("Your totem loadouts are kept too.")
E.Totems = M
E:RegisterVisibilityFacet("EldoUI_ShamanTotems", "rules", { module = "ShamanTotems", setting = "visibility" })
E:RegisterVisibilityFacet("EldoUI_ShamanCooldowns", "rules", { module = "ShamanTotems", setting = "visibility" })
M.MAX_LOADOUTS = 8

local Secret = E.Secret
local Plain = E.Plain

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d, e, f, g = pcall(fn, ...)
	if ok then return a, b, c, d, e, f, g end
end
M.Try = Try

-- Every value a call returns (no cap on how many), or an empty list.
local function TryAll(fn, ...)
	if type(fn) ~= "function" then return {} end
	local result = { pcall(fn, ...) }
	if not result[1] then return {} end
	table.remove(result, 1)
	return result
end
M.TryAll = TryAll

function M:IsShaman()
	local _, class = UnitClass("player")
	return not Secret(class) and class == "SHAMAN"
end

-- On and drawing: the module is on and the character is a shaman.
function M:Drawing()
	return self.active and self:IsShaman()
end

---------------------------------------------------------------------------
-- Spell knowledge (cached until the spellbook changes)
---------------------------------------------------------------------------
local cache = {}

local function KnownId(id)
	if type(id) ~= "number" then return false end
	local book = C_SpellBook
	if not book then return false end
	for _, check in ipairs({ book.IsSpellKnown, book.IsSpellInSpellBook }) do
		if Plain(Try(check, id)) then return true end
	end
	return false
end

local function SpellName(id)
	local name = C_Spell and C_Spell.GetSpellName and Plain(Try(C_Spell.GetSpellName, id))
	return type(name) == "string" and name ~= "" and name or nil
end
M.SpellName = SpellName

local function SpellIcon(id)
	local icon = C_Spell and C_Spell.GetSpellTexture and Plain(Try(C_Spell.GetSpellTexture, id))
	return icon
end

-- { known, id (the highest rank known), name, icon } for a rank 1 spell.
-- The highest rank comes from the spell's name: the game's spell info for
-- a name is the rank in your spellbook.
function M:Spell(id)
	local info = cache[id]
	if info then return info end
	local name = SpellName(id)
	info = { id = id, name = name, icon = SpellIcon(id), known = KnownId(id) }
	if name and C_Spell and C_Spell.GetSpellInfo then
		local byName = Try(C_Spell.GetSpellInfo, name)
		if type(byName) == "table" then
			local best = Plain(byName.spellID)
			if type(best) == "number" and best ~= id and KnownId(best) then
				info.id, info.known = best, true
				info.icon = Plain(byName.iconID) or info.icon
			end
		end
	end
	cache[id] = info
	return info
end

function M:Known(id)
	return self:Spell(id).known
end

function M:ForgetSpells()
	wipe(cache)
	self.nameMap = nil
end

-- Spell name -> totem entry (every rank shares the name).
local function NameMap()
	if M.nameMap then return M.nameMap end
	local map = {}
	for _, entry in pairs(D.byId) do
		local name = SpellName(entry.id)
		if name then map[name] = entry end
	end
	M.nameMap = map
	return map
end

-- The totem entry a cast spell belongs to (any rank), or nil.
function M:TotemOfSpell(spellID)
	if type(spellID) ~= "number" or Secret(spellID) then return nil end
	if D.byId[spellID] then return D.byId[spellID] end
	local name = SpellName(spellID)
	return name and NameMap()[name] or nil
end

-- The totems you know for one element, in the data's order: entries with
-- .spell (highest rank), .name and .icon. The game's own list for the
-- element (GetMultiCastTotemSpells) counts as known too.
function M:KnownTotems(element)
	local list, seen = {}, {}
	local fromGame = {}
	local get = rawget(_G, "GetMultiCastTotemSpells")
	if type(get) == "function" then
		for _, id in ipairs(TryAll(get, D.SLOT[element])) do
			local entry = self:TotemOfSpell(Plain(id))
			if entry and entry.element == element then fromGame[entry.key] = Plain(id) end
		end
	end
	for _, entry in ipairs(D.TOTEMS[element] or {}) do
		local info = self:Spell(entry.id)
		if (info.known or fromGame[entry.key]) and not seen[entry.key] then
			seen[entry.key] = true
			list[#list + 1] = { key = entry.key, entry = entry, element = element,
				spell = info.known and info.id or fromGame[entry.key], name = info.name, icon = info.icon }
		end
	end
	return list
end

-- The picked totem of an element (a known one), else the first known.
function M:Pick(element)
	local list = self:KnownTotems(element)
	local wanted = self.db and self.db.picks[element]
	for _, item in ipairs(list) do
		if item.key == wanted then return item end
	end
	return list[1]
end

---------------------------------------------------------------------------
-- Call of the Elements: the game's multi-cast slots. Written only when the
-- player picks a totem or a loadout (out of combat), never from what was
-- read while the game loaded.
---------------------------------------------------------------------------
-- The first call you know (Call of the Elements first).
function M:CallSpell()
	for _, id in ipairs(D.CALLS) do
		if self:Known(id) then return self:Spell(id).id end
	end
end

-- The game's action slot for an element in the first call (page 1). The
-- call's four action slots follow the game's totem slot numbers (fire 1,
-- earth 2, water 3, air 4), not the bar's display order: the game refuses
-- a totem of another element in a slot.
function M:CallAction(element)
	local bar = C_ActionBar and C_ActionBar.GetMultiCastBarIndex and Plain(Try(C_ActionBar.GetMultiCastBarIndex))
	if type(bar) ~= "number" or bar <= 0 then bar = 12 end
	return (bar - 1) * 12 + D.SLOT[element]
end

-- Write the picks of these elements into the call's slots. True when the
-- game took them (or there was nothing to write).
function M:SyncCall(elements)
	local set = rawget(_G, "SetMultiCastSpell")
	if type(set) ~= "function" or not self:CallSpell() then return false end
	if InCombatLockdown() then return false end
	local ok = true
	for _, element in ipairs(elements or D.ELEMENTS) do
		local pick = self:Pick(element)
		if pick and pick.spell then
			local done = pcall(set, self:CallAction(element), pick.spell)
			ok = ok and done
		end
	end
	return ok
end

-- The totem in the call's slot for an element, read once to seed an
-- empty pick (read only: nothing is written back).
function M:CallTotem(element)
	if type(GetActionInfo) ~= "function" then return nil end
	local kind, id = Try(GetActionInfo, self:CallAction(element))
	if Plain(kind) ~= "spell" then return nil end
	local entry = self:TotemOfSpell(Plain(id))
	return entry and entry.element == element and entry or nil
end

---------------------------------------------------------------------------
-- Picks
---------------------------------------------------------------------------
-- Pick a totem for an element (out of combat; queued in combat). sync
-- false leaves Call of the Elements alone.
function M:SetPick(element, key, sync)
	if not (self.db and self.db.picks[element] ~= nil) then return false end
	self.db.picks[element] = key or ""
	self.db.activeLoadout = 0
	E:RunOutOfCombat(function()
		if sync ~= false then M:SyncCall({ element }) end
		M:Refresh()
	end, "ShamanTotems:pick:" .. element)
	return true
end

-- Empty picks take the totem already in the game's call, once.
-- True when `key` names an entry of `list`.
local function Listed(list, key)
	for _, item in ipairs(list or {}) do
		if item.key == key then return true end
	end
	return false
end

-- A saved pick of a spell WoW: Forever does not have (Earth Shield, Fire
-- Nova Totem, Tranquil Air Totem) goes back to "the first one you know",
-- so no picker is left showing an empty choice.
function M:ForgetRemovedPicks()
	local db = self.db
	for _, element in ipairs(D.ELEMENTS) do
		local key = db.picks[element]
		if key and key ~= "" and not Listed(D.TOTEMS[element], key) then db.picks[element] = "" end
	end
	local cd = db.cooldowns
	if type(cd) == "table" then
		for field, list in pairs({ shieldPick = D.SHIELDS, imbuePick = D.IMBUES, imbueOffPick = D.IMBUES }) do
			local key = cd[field]
			if key and key ~= "" and not Listed(list, key) then cd[field] = "" end
		end
	end
end

function M:SeedPicks()
	self:ForgetRemovedPicks()
	for _, element in ipairs(D.ELEMENTS) do
		if (self.db.picks[element] or "") == "" then
			local entry = self:CallTotem(element)
			if entry then self.db.picks[element] = entry.key end
		end
	end
end

---------------------------------------------------------------------------
-- Totem slots: which element each running totem belongs to. Only the
-- spell the game names for the slot decides; a secret answer leaves the
-- slot unresolved (its timer waits), never guessed.
---------------------------------------------------------------------------
function M:SlotState(slot)
	local have, _, _, _, _, _, spellID = Try(GetTotemInfo, slot)
	if Secret(have) then return nil, true end
	if not have then return nil, false end
	local entry = self:TotemOfSpell(Plain(spellID))
	if entry then return entry.element, false end
	return nil, true
end

-- element -> slot of its running totem; unresolved: slots the game hides.
function M:ElementSlots()
	local map, unresolved = {}, 0
	local count = Plain(Try(GetNumTotemSlots)) or D.MAX_SLOTS
	for slot = 1, math.min(type(count) == "number" and count or D.MAX_SLOTS, 8) do
		local element, hidden = self:SlotState(slot)
		if element then map[element] = slot elseif hidden then unresolved = unresolved + 1 end
	end
	return map, unresolved
end

---------------------------------------------------------------------------
-- Blizzard's totem bar and totem timers: hidden while this bar is on.
---------------------------------------------------------------------------
function M:OwnsBlizzard()
	return self:Drawing() and self.db.hideBlizzard and true or false
end

local claimed = {}
local function Keep(frame, hide)
	if not frame then return end
	if hide then
		if not claimed[frame] and not E:IsBlizzardFrameHidden(frame) then
			claimed[frame] = true
			E:HideBlizzardFrame(frame, { check = function() return claimed[frame] == true end })
		end
	elseif claimed[frame] then
		claimed[frame] = nil
		E:UnhideBlizzardFrame(frame)
	end
end

-- Does this bar hold `frame` hidden? (Another part may hide it too.)
function M:HoldsBlizzard(frame)
	return frame ~= nil and claimed[frame] == true
end

function M:ApplyBlizzard()
	E:RunOutOfCombat(function()
		local own = M:OwnsBlizzard()
		-- Action Bars puts its own totem bar holder away first, so the
		-- frame is not hidden and anchored at once.
		local bars = E.modules.ActionBars
		if bars and bars.active and bars.ApplySpecial then pcall(bars.ApplySpecial, bars) end
		Keep(rawget(_G, "MultiCastActionBarFrame"), own)
		Keep(rawget(_G, "TotemFrame"), own and not M.db.keepTimers)
		-- Player Power places Blizzard's totem timers above a totem bar:
		-- which one shows changed, so it places them again.
		local power = E.modules.ClassPower
		if power and power.active and power.ApplyBlizzard then pcall(power.ApplyBlizzard, power) end
	end, "ShamanTotems:Blizzard")
end

---------------------------------------------------------------------------
-- Refresh: every part re-reads what it shows; secure parts out of combat.
---------------------------------------------------------------------------
M.parts = {}
function M:AddPart(name, part)
	self.parts[#self.parts + 1] = part
	part.name = name
end

local function Each(method, ...)
	for _, part in ipairs(M.parts) do
		if part[method] then
			local ok, err = pcall(part[method], part, ...)
			if not ok then geterrorhandler()(err) end
		end
	end
end
M.Each = Each

-- Layout and secure attributes (out of combat).
function M:Refresh()
	E:RunOutOfCombat(function()
		Each("Apply")
		M:ApplyBlizzard()
	end, "ShamanTotems:Refresh")
	Each("Update")
end

-- Display only (timers, cooldowns, states); safe in combat.
function M:Update()
	Each("Update")
	self:UpdateTicker()
end

local events = CreateFrame("Frame")
-- Cooldown and totem changes come from the one cooldown source (below).
local EVENTS = {
	"SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_LEVEL_UP",
	"UNIT_AURA", "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
	"PLAYER_ENTERING_WORLD", "UPDATE_MULTI_CAST_ACTIONBAR", "UPDATE_BINDINGS", "GROUP_ROSTER_UPDATE",
	"LOSS_OF_CONTROL_ADDED", "LOSS_OF_CONTROL_UPDATE", "ZONE_CHANGED_NEW_AREA",
}
local SPELLBOOK = { SPELLS_CHANGED = true, LEARNED_SPELL_IN_SKILL_LINE = true, PLAYER_LEVEL_UP = true }
events:SetScript("OnEvent", function(_, event, unit)
	if not M.active then return end
	if event == "UNIT_AURA" or event == "UNIT_INVENTORY_CHANGED" then
		unit = Plain(unit)
		if type(unit) ~= "string" then return end
		if unit ~= "player" then
			local party = tonumber(unit:match("^party([1-4])$"))
			local raid = tonumber(unit:match("^raid(%d+)$"))
			if party or (raid and raid >= 1 and raid <= 40 and unit == "raid" .. raid) then
				Each("OnGroupAura", unit)
			end
			return
		end
	end
	if SPELLBOOK[event] then
		M:ForgetSpells()
		M:Refresh()
		return
	end
	if event == "PLAYER_REGEN_ENABLED" or event == "UPDATE_BINDINGS" or event == "UPDATE_MULTI_CAST_ACTIONBAR" then
		M:Refresh()
		return
	end
	Each("OnEvent", event, unit)
	M:Update()
end)

-- A slow tick for the imbue bars and the coverage squares (no per-frame
-- work), on the shared ticker and only while something counts down: a
-- totem is out (or the game hides a slot, which may hold one) or a weapon
-- imbue runs. Display only.
local TICK = "ShamanTotems:tick"
local COOLDOWNS = "ShamanTotems"

function M:NeedsTick()
	if not (self.active and self:IsShaman() and self:Drawing()) then return false end
	local count = Plain(Try(GetNumTotemSlots)) or D.MAX_SLOTS
	for slot = 1, math.min(type(count) == "number" and count or D.MAX_SLOTS, 8) do
		local have = Try(GetTotemInfo, slot)
		if Secret(have) or have then return true end
	end
	local cooldowns = self.Cooldowns
	return cooldowns and cooldowns.ImbueRunning and cooldowns:ImbueRunning() or false
end

local function Tick()
	if not M.active then
		E.Ticker:Unsubscribe(TICK)
		return
	end
	Each("Tick")
	M:UpdateTicker()
end

function M:UpdateTicker()
	local ticker = E.Ticker
	if not ticker then return end
	if self:NeedsTick() then
		if not ticker:IsSubscribed(TICK) then ticker:Subscribe(TICK, 1, Tick, M) end
	else
		ticker:Unsubscribe(TICK)
	end
end

-- What the cooldown source hands out once per frame: a spell cooldown or
-- a totem slot changed.
local function OnCooldowns()
	if M.active then M:Update() end
end

function M:OnInitialize()
	-- The cross-class part (the Aura Groups example) lives in Aura Groups;
	-- nothing here runs for other classes.
	self.db.loadouts = type(self.db.loadouts) == "table" and self.db.loadouts or {}
end

function M:OnEnable()
	if not self:IsShaman() then
		-- On for a non-shaman (a shared profile): nothing to draw.
		Each("Disable")
		self:ApplyBlizzard()
		return
	end
	for _, event in ipairs(EVENTS) do pcall(events.RegisterEvent, events, event) end
	self:ForgetSpells()
	self:SeedPicks()
	local source = E.CombatKit and E.CombatKit.Cooldowns
	if source then source.Subscribe(COOLDOWNS, OnCooldowns, { totems = true }) end
	Each("Enable")
	self:Refresh()
end

function M:OnDisable()
	events:UnregisterAllEvents()
	local source = E.CombatKit and E.CombatKit.Cooldowns
	if source then source.Unsubscribe(COOLDOWNS) end
	if E.Ticker then E.Ticker:UnsubscribeOwner(M) end
	if self.groupWindow then self.groupWindow:Close() end
	Each("Disable")
	self:ApplyBlizzard()
end

function M:OnProfileChanged()
	if not self.active then return end
	if not self:IsShaman() then return end
	self:Refresh()
end

-- Feature conflicts: parts of other addons that already do one of these.
E:RegisterFeatureConflicts("totemcoverage", { "ShamanPower_PartyRange", "ShamanPower_SPRange" })
E:RegisterFeatureConflicts("totemreminders", { "ShamanPower_ReadyReminders", "ShamanPower_ExpiringAlerts", "ShamanPower_ShieldCharges" })
E:RegisterFeatureConflicts("totemgroup", { "ShamanPower_RaidCooldowns" })
E:RegisterFeatureConflicts("totemplates", { "ShamanPower_TotemPlates", "ShamanPower_TremorReminder", "ShamanPower_ReactiveTotems" })

