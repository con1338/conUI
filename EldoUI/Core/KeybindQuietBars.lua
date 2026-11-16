-- EldoUI keybind setup, bars 4 and 5: when the player turns on "Fill bars
-- 4 and 5", the class spells that have no key of their own go on the
-- empty buttons of bars 4 and 5, the bars most layouts keep out of sight.
-- Those are the spells the key map gives an off-bar home
-- (Data/KeybindCategories.lua, C.offBar) that are cast outside a fight:
-- travel (teleports and portals), the spellbook spells for outside a
-- fight, tracking, poisons and the like, and pet care. Stances, forms,
-- totems and passives keep their own bars.
--
--   E:QuietFillOn()          the profile setting (off by default)
--   E:SetQuietFill(on)       turns it on (and fills now) or off
--   E:QuietSpellPlan(names)  read only: the spells and the buttons they
--                            would take, in the class's order
--   E:FillQuietBars(names)   places them, out of combat; one chat line;
--                            kept for Undo
--   E:UndoQuietBars()        takes the last fill off again, only where a
--                            button still holds it
--
-- Only an empty button gets a spell: a button the player filled is never
-- touched, and a spell already on any bar is never doubled. Nothing is
-- cast or chosen for a fight. A combat start stops the fill; the rest
-- follows after combat. A spell learned later goes to the next empty
-- button there (Core/KeybindNewSpells.lua notices it). The buttons keep
-- their spells and keys on layouts that hide bars 4 and 5.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local issecret = issecretvalue or function() return false end

-- Bars 4 and 5, in the order their buttons fill. Bar 3 is the quiet
-- box of between-pull spells the key map places itself.
local QUIET_BARS = { 4, 5 }
-- The off-bar homes cast outside a fight, in the order they fill; spells
-- of the spellbook home count only when the key map marks them for
-- outside a fight (tier 5).
local HOME_ORDER = { "travelmenu", "book", "track", "craft", "pet" }
local OUTSIDE_TIER = 5

-- Per character: slots = { [slot] = spellID } of the last fill (for
-- Undo), done = the first fill ran here, skip = { [name] = true } for
-- spells the player took off with Undo (never put back until the setting
-- is turned on again).
E:RegisterPrivate("quietBars", {})

local function Plain(value)
	if issecret(value) then return nil end
	return value
end

local function SpellName(spellID)
	local name = C_Spell and C_Spell.GetSpellName and Plain(C_Spell.GetSpellName(spellID))
	return type(name) == "string" and name ~= "" and name or nil
end

local function PlayerClass()
	local _, class = UnitClass("player")
	return Plain(class)
end

local function Record()
	local record = E:GetPrivate("quietBars")
	return type(record) == "table" and record or {}
end

function E:QuietFillOn()
	if self.KeymapSetting then
		local on = self:KeymapSetting("quietFill")
		if on ~= nil then return on == true end
	end
	local keymap = self.db and self.db.keymap
	return type(keymap) == "table" and keymap.quietFill == true or false
end

-- True when the key map's class data this needs is loaded.
function E:QuietFillAvailable()
	local C = self.keybindCategories
	return type(C) == "table" and type(C.offBar) == "table" and type(C.Home) == "function" or false
end

-- Their buttons, bar 4 then bar 5, button 1 to 12.
local function QuietSlots()
	local slots = {}
	if not E.KeybindActionSlot then return slots end
	for _, bar in ipairs(QUIET_BARS) do
		for button = 1, 12 do
			local slot = E:KeybindActionSlot(bar, button)
			if slot then slots[#slots + 1] = slot end
		end
	end
	return slots
end
E.QuietBarSlots = QuietSlots

local function KnownNames()
	local module = E.modules and E.modules.ActionBars
	local scan = module and module.RankScan and module:RankScan()
	return scan and scan.best or {}
end

-- The player's own button for a spell (key map homes) wins: such a spell
-- is left to the new spells helper.
local function HasOwnHome(name)
	local keymap = E.db and E.db.keymap
	local homes = type(keymap) == "table" and type(keymap.homes) == "table" and keymap.homes[PlayerClass() or ""]
	homes = type(homes) == "table" and homes[E.GetRole and E:GetRole() or "none"]
	if type(homes) ~= "table" then return false end
	for head in pairs(homes) do
		if type(head) == "number" and SpellName(head) == name then return true end
	end
	return false
end

-- The class's quiet spells the player knows, in the class's order:
-- { name, spell } with the highest known rank. names (optional): only
-- these spell names.
local function QuietSpells(names)
	local out = {}
	local C = E.keybindCategories
	local class = PlayerClass()
	if not (E:QuietFillAvailable() and class) then return out end
	local list = C.offBar[class]
	if type(list) ~= "table" then return out end
	local known, skip, seen = KnownNames(), Record().skip or {}, {}
	for _, home in ipairs(HOME_ORDER) do
		for _, item in ipairs(list) do
			if item.home == home and type(item.spells) == "table" then
				for _, id in ipairs(item.spells) do
					local name = SpellName(id)
					local best = name and known[name]
					-- C.Home answers for the player's role: a spell this
					-- role keeps on bars 1 to 3 has a button there.
					local bar, where = C.Home(class, nil, id)
					local tierOk = home ~= "book" or (C.Tier and C.Tier(class, nil, id) == OUTSIDE_TIER)
					if best and not seen[name] and not bar and where == home and tierOk
						and not skip[name] and (not names or names[name]) and not HasOwnHome(name) then
						seen[name] = true
						out[#out + 1] = { name = name, spell = best }
						break
					end
				end
			end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- The plan (read only)
---------------------------------------------------------------------------
-- Entries { name, spell, slot } for the spells that go on an empty quiet
-- button; spells already on any bar are left out. More spells than empty
-- buttons: the class's order decides, the rest stays in the spellbook.
function E:QuietSpellPlan(names)
	local plan = { entries = {} }
	local slots = self.PremadeSlots
	if not slots then return plan end
	local free = {}
	for _, slot in ipairs(QuietSlots()) do
		if slots.Empty(slot) then free[#free + 1] = slot end
	end
	local index = 1
	for _, spell in ipairs(QuietSpells(names)) do
		if not free[index] then break end
		if not slots.OnBars(spell.spell) then
			plan.entries[#plan.entries + 1] = { name = spell.name, spell = spell.spell, slot = free[index] }
			index = index + 1
		end
	end
	return plan
end

---------------------------------------------------------------------------
-- Filling and taking back
---------------------------------------------------------------------------
-- A fill a combat start stopped: what it placed so far, finished after
-- combat.
local pending

local function Finish(placed, words)
	local record = Record()
	record.slots, record.time = placed, time()
	E:Print(L["Bars 4 and 5 filled: %s. /eui fillbars undo takes them off again."]:format(table.concat(words, ", ")))
	if E.KeybindPreviewChanged then E:KeybindPreviewChanged() end
end

-- Places the plan. Returns how many were placed, or 0 and why ("combat",
-- "cursor").
function E:FillQuietBars(names)
	local place = self.PremadeSlots and self.PremadeSlots.Place
	if not place then return 0 end
	if InCombatLockdown() then return 0, "combat" end
	if GetCursorInfo and GetCursorInfo() then return 0, "cursor" end
	local run = pending or { placed = {}, words = {}, count = 0 }
	pending = nil
	for _, entry in ipairs(self:QuietSpellPlan(names).entries) do
		local ok, why = place(entry.slot, entry.spell)
		if ok then
			run.placed[entry.slot] = entry.spell
			run.words[#run.words + 1] = entry.name
			run.count = run.count + 1
		elseif why == "combat" then
			-- A fight started: the rest follows after it.
			pending = run
			self:RunOutOfCombat(function() E:FillQuietBars(names) end, "KeybindQuietBars:fill")
			return run.count, "combat"
		end
	end
	if run.count > 0 then Finish(run.placed, run.words) end
	return run.count
end

function E:HasQuietBarsUndo()
	local record = Record()
	return type(record.slots) == "table" and next(record.slots) ~= nil or false
end

-- Takes the last fill off the buttons that still hold it; those spells
-- stay off until the setting is turned on again.
function E:UndoQuietBars()
	if not self:HasQuietBarsUndo() then
		self:Print(L["There are no spells from the last fill to take off."])
		return 0
	end
	if InCombatLockdown() then
		self:Print(L["Spells can't move onto your bars in combat."])
		return 0
	end
	local clear = self.PremadeSlots and self.PremadeSlots.Clear
	if not clear then return 0 end
	local record = Record()
	record.skip = record.skip or {}
	local count = 0
	for slot, spellID in pairs(record.slots) do
		if clear(slot, spellID) then count = count + 1 end
		local name = SpellName(spellID)
		if name then record.skip[name] = true end
	end
	record.slots, record.time = nil, nil
	self:Print(E:Plural(count, "%d spell taken off bars 4 and 5.", "%d spells taken off bars 4 and 5."):format(count))
	if self.KeybindPreviewChanged then self:KeybindPreviewChanged() end
	return count
end

-- A fill out of combat with an empty cursor; a busy cursor waits a little.
local function FillSoon(names, tell)
	E:RunOutOfCombat(function()
		local count, why = E:FillQuietBars(names)
		if count == 0 and why == "cursor" then
			E:Debounce("keybind:quietbars:cursor", 2, function() FillSoon(names, tell) end)
		elseif count == 0 and not why and tell then
			E:Print(L["Nothing to place: bars 4 and 5 have no empty button, or your out-of-combat spells are already on your bars."])
		end
	end, "KeybindQuietBars:fill")
end

-- Set from the options page and the setup (the profile's key map record).
-- Turning it on fills the empty buttons of bars 4 and 5 now and forgets earlier
-- Undos; turning it off leaves the buttons as they are.
local lastOn

local function TurnedOn()
	local record = Record()
	record.skip, record.done = nil, true
	FillSoon()
end

function E:SetQuietFill(on)
	if type(self.db) ~= "table" then return end
	local record = self.NewSpellsRecord and self:NewSpellsRecord() or self.db.keymap
	if type(record) ~= "table" then return end
	record.quietFill = on and true or false
	lastOn = record.quietFill
	if on then TurnedOn() end
end

-- After the options page, a profile switch or a synced key map changed
-- the record: turning it on there fills now, like SetQuietFill.
function E:QuietFillChanged()
	local on = self:QuietFillOn()
	if lastOn == nil or on == lastOn then
		lastOn = on
		return
	end
	lastOn = on
	if on then TurnedOn() end
end

-- One call for the Action Bars refresh: new spells and the fill.
function E:KeymapAutomationChanged()
	if self.NewSpellsModeChanged then self:NewSpellsModeChanged() end
	self:QuietFillChanged()
end

-- Spells learned after login (Core/KeybindNewSpells.lua): those with a
-- home for outside a fight go to the next empty button of bars 4 and 5.
function E:QuietBarsLearned(names)
	if not (self:QuietFillOn() and next(names or {})) then return 0 end
	return (self:FillQuietBars(names))
end

-- At login: a character whose profile has the setting on (a synced
-- profile, another character) gets its first fill once.
local owner = {}
E:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
	if not (isLogin or isReload) then return end
	lastOn = E:QuietFillOn()
	if C_Timer then
		C_Timer.After(3, function()
			local record = Record()
			if E:QuietFillOn() and not record.done then
				record.done = true
				FillSoon()
			end
		end)
	end
end, owner)

E:AddCommand("fillbars", "[undo]  fill the empty buttons of bars 4 and 5 with your out-of-combat class spells now; undo takes the last fill off again", function(args)
	if type(args) == "string" and strtrim(args):lower() == "undo" then
		E:RunOutOfCombat(function() E:UndoQuietBars() end, "KeybindQuietBars:undo")
		return
	end
	Record().skip = nil
	FillSoon(nil, true)
end, "Keys and spells")
