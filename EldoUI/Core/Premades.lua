-- EldoUI class premades: apply and revert a class's full setup (data in
-- Data/ClassPremades.lua).
--
--   E:GetClassPremade([class])        the premade of a class (yours when nil)
--   E:PremadePlan([role])             what applying would do, read only:
--                                     { modules, loadout, bars, macros,
--                                     counters, restock }
--   E:ApplyPremade([role], [opts])    out of combat; opts.bars, opts.macros
--                                     (true to place them), opts.replace
--                                     ({ [slot] = true }: slots of your own
--                                     you opted to give up), opts.only
--                                     ({ [slot] = true }: place only these
--                                     slots), opts.barsOnly (leave modules
--                                     and settings as they are). Returns
--                                     the plan
--   E:RevertPremade()                 puts back what still holds the
--                                     premade's value
--   E:RevertPremadeParts(parts, keep) the same for some parts only
--                                     (settings, modules, bars, macros),
--                                     leaving the entries in keep
--   E:PremadeApplied()                the record of what was applied, or nil
--
-- The Role step's "Class details" applies the class layer (the premade's
-- settings) and, through a role callback, turns the modules on, sets the
-- style and the totem loadout for the role, and adds the premade's
-- counters and restock items (they go with the settings on a revert). Bars and macros change only
-- from the setup page's Apply (the player ticks them). Nothing here acts
-- during play.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local Key = E.Key
local Secret = E.Secret
local MACRO_NAME_MAX = 16

E:RegisterPrivate("premade", {})

local function PlayerClass()
	local _, class = UnitClass("player")
	if Secret(class) then return nil end
	return class
end

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return E.Plain(a), E.Plain(b), E.Plain(c) end
end

local function Known(id)
	local book = C_SpellBook
	if not book then return false end
	return (Try(book.IsSpellKnown, id) or Try(book.IsSpellInSpellBook, id)) and true or false
end

local function SpellName(id)
	local name = Try(C_Spell and C_Spell.GetSpellName, id)
	return type(name) == "string" and name ~= "" and name or nil
end

local function FirstKnown(ids)
	for _, id in ipairs(ids or {}) do
		if Known(id) then return id end
	end
end

-- roles: nil or "all", one role key, or a list of role keys. "damage"
-- stands for Melee and Ranged alike.
local function RoleListed(key, role)
	return key == role or (key == "damage" and E.RoleGroup and E:RoleGroup(role) == "damage")
end

local function ForRole(item, role)
	local roles = item.roles
	if roles == nil or roles == "all" or RoleListed(roles, role) then return true end
	if type(roles) == "table" then
		for _, key in ipairs(roles) do
			if RoleListed(key, role) then return true end
		end
	end
	return false
end

-- The premade's entry for a role: its own, then the one for both damage
-- roles, then the one without a role.
local function RoleInfo(premade, role)
	local roles = premade.roles
	if not roles then return nil end
	return roles[role] or (E.RoleGroup and E:RoleGroup(role) == "damage" and roles.damage) or roles.none
end

local function Level()
	local level = Try(UnitLevel, "player")
	return type(level) == "number" and level or 1
end

-- minLevel and maxLevel of a counter, restock item or macro.
local function ForLevel(item)
	local level = Level()
	return not ((item.minLevel and level < item.minLevel) or (item.maxLevel and level > item.maxLevel))
end

-- A stance page's spell: one ID, or a list (Dire Bear Form, else Bear
-- Form), the first one you know.
local function StanceSpell(premade, stance)
	local spell = stance and premade.stances and premade.stances[stance]
	if type(spell) == "table" then return FirstKnown(spell) or spell[#spell], spell end
	return spell
end

function E:GetClassPremade(class)
	return self.classPremades and self.classPremades[class or PlayerClass() or ""] or nil
end

function E:PremadeApplied()
	local record = self:GetPrivate("premade")
	return type(record) == "table" and record.applied or nil
end

---------------------------------------------------------------------------
-- The plan (read only)
---------------------------------------------------------------------------
local function SlotEmpty(slot)
	local hasAction = C_ActionBar and C_ActionBar.HasAction or HasAction
	if type(hasAction) ~= "function" then return GetActionInfo and Try(GetActionInfo, slot) == nil end
	return not Try(hasAction, slot)
end

-- A stance, form or stealth page of bar 1 (the game's bonus bars 1 to 4)
-- holds the action slots 73 to 120: twelve per page.
local function StanceSlot(stance, slot)
	return (5 + stance) * 12 + slot
end

-- Where a premade's bar entry goes: the button of its keybind category
-- (bar 1 to 3, Data/KeybindCategories.lua), so the class setup and the
-- key sets share one grid. Returns the action slot, the bar, the
-- button, and the stance page it lands on (only bar 1 pages).
local function EntryPlace(entry)
	local slots = E.keybindCategories and E.keybindCategories.slots
	for bar, keys in ipairs(type(entry.category) == "string" and slots or {}) do
		for button, key in ipairs(keys) do
			if key == entry.category then
				if bar == 1 then
					return entry.stance and StanceSlot(entry.stance, button) or button, bar, button, entry.stance
				end
				local slot = E.KeybindActionSlot and E:KeybindActionSlot(bar, button)
				return slot, bar, button, nil
			end
		end
	end
	return nil
end
E.PremadeEntryPlace = EntryPlace -- exposed for inspection

-- Is the spell on your bars already? For a stance page: on that page, or
-- on a bar that never pages (bars 2 to 5, and 6 to 8), so it shows in
-- every stance. Only the keyboard's bars count: the game's search takes in
-- its controller bars too unless it is asked for the keyboard set, and
-- without that set only the player's own action slots count.
local function OnBars(spellID, stance)
	local find = C_ActionBar and C_ActionBar.FindSpellActionButtons
	if type(find) ~= "function" then return false end
	local set = Enum and Enum.ActionBarSet and Enum.ActionBarSet.Mkb
	local ok, slots
	if set then ok, slots = pcall(find, spellID, set) else ok, slots = pcall(find, spellID) end
	if not (ok and type(slots) == "table" and not Secret(slots)) then return false end
	if not stance then
		for _, slot in ipairs(slots) do
			if (slot >= 1 and slot <= 120) or (slot > 144 and slot <= 180) then return true end
		end
		return false
	end
	local first = StanceSlot(stance, 1)
	for _, slot in ipairs(slots) do
		if (slot >= first and slot < first + 12) or (slot > 24 and slot <= 72) or (slot > 144 and slot <= 180) then return true end
	end
	return false
end

local function MacroIndex(name)
	local index = Try(GetMacroIndexByName, name)
	return type(index) == "number" and index or 0
end

local function MacroRoom()
	local _, perChar = Try(GetNumMacros)
	local c = rawget(_G, "Constants") and Constants.MacroConsts
	local max = (c and c.MAX_CHARACTER_MACROS) or rawget(_G, "MAX_CHARACTER_MACROS") or 18
	return math.max(0, max - (tonumber(perChar) or 0))
end

-- Pet commands a macro may give (the game's own slash commands).
local PET_COMMANDS = {
	attack = "/petattack", follow = "/petfollow", stay = "/petstay",
	passive = "/petpassive", defensive = "/petdefensive", aggressive = "/petaggressive",
}
E.PremadePetCommands = PET_COMMANDS

local function Carried(id)
	local count = Try(C_Item and C_Item.GetItemCount, id)
	return type(count) == "number" and count > 0
end

-- The first item of a list you carry (the list goes from the best down).
local function FirstCarried(ids)
	for _, id in ipairs(ids or {}) do
		if Carried(id) then return id end
	end
end

-- The macro text, or nil plus why ("noitem": none of an item line is in
-- your bags yet). Lines in order: casts, uses, pet commands, click.
local function MacroBody(macro)
	local lines = { "#showtooltip" }
	if macro.click then
		lines[#lines + 1] = "/click " .. macro.click
		return table.concat(lines, "\n")
	end
	for _, ids in ipairs(macro.casts or {}) do
		local name = SpellName(FirstKnown(ids) or 0)
		if not name then return nil end
		lines[#lines + 1] = (macro.self and "/cast [@player] %s" or "/cast %s"):format(name)
	end
	for _, ids in ipairs(macro.uses or {}) do
		local id = FirstCarried(ids)
		if not id then return nil, "noitem" end
		lines[#lines + 1] = "/use item:" .. id
	end
	for _, command in ipairs(macro.pet or {}) do
		if not PET_COMMANDS[command] then return nil end
		lines[#lines + 1] = PET_COMMANDS[command]
	end
	return #lines > 1 and table.concat(lines, "\n") or nil
end
E.PremadeMacroBody = MacroBody

local function ItemName(id)
	local name = Try(C_Item and C_Item.GetItemNameByID, id)
	if type(name) == "string" and name ~= "" then return name end
	Try(C_Item and C_Item.RequestLoadItemDataByID, id)
end

local function CounterKey(counter)
	return (counter.kind or "item") .. ":" .. (counter.id or 0)
end

local function HasCounter(entries, key)
	for _, entry in ipairs(entries or {}) do
		if CounterKey(entry) == key then return true end
	end
	return false
end

-- The Merchant restock list: { { id, name, amount }, ... }.
local function RestockEntries()
	local module = E.modules.Merchant
	return module and type(module.db) == "table" and type(module.db.restock) == "table" and module.db.restock or nil, module
end

local function OnRestock(entries, id)
	for _, entry in ipairs(entries or {}) do
		if entry.id == id then return true end
	end
	return false
end

function E:PremadePlan(role, class)
	local premade = self:GetClassPremade(class)
	if not premade then return nil end
	role = role or (self.GetRole and self:GetRole()) or "none"
	role = self.ResolveRoleKey and self:ResolveRoleKey(role, class) or role
	local roleInfo = RoleInfo(premade, role) or {}
	local plan = { class = class or PlayerClass(), role = role, version = premade.version, modules = {}, bars = {}, macros = {},
		counters = {}, restock = {}, loadout = roleInfo.loadout }
	for _, name in ipairs(premade.modules or {}) do
		local module = self.modules[name]
		if module then plan.modules[#plan.modules + 1] = { name = name, title = module.title, on = module:IsEnabled() and true or false } end
	end
	local used = {}
	for _, bar in ipairs(premade.bars or {}) do
		local stanceSpell = StanceSpell(premade, bar.stance)
		local id = ForRole(bar, role) and (not bar.stance or (stanceSpell and Known(stanceSpell))) and FirstKnown(bar.spells)
		local slot, barIndex, button, page = EntryPlace(bar)
		if id and slot and not used[slot] then
			used[slot] = true
			local status = OnBars(id, page) and "onbar" or SlotEmpty(slot) and "place" or "kept"
			plan.bars[#plan.bars + 1] = { slot = slot, bar = barIndex, button = button, category = bar.category, stance = page,
				stanceName = page and stanceSpell and SpellName(stanceSpell) or nil, spell = id, name = SpellName(id), status = status }
		end
	end
	local counters = self.modules.Counters
	local entries = counters and type(counters.db) == "table" and counters.db.entries
	local record = self:PremadeApplied()
	for _, counter in ipairs(entries and premade.counters or {}) do
		if ForRole(counter, role) and ForLevel(counter) then
			local key = CounterKey(counter)
			local mine = record and record.counters and record.counters[key]
			plan.counters[#plan.counters + 1] = { key = key, kind = counter.kind or "item", id = counter.id, goal = counter.goal,
				name = ItemName(counter.id) or E:Translate(counter.name) or key, status = (HasCounter(entries, key) and not mine) and "exists" or "add" }
		end
	end
	local restock = RestockEntries()
	for _, item in ipairs(restock and premade.restock or {}) do
		if ForRole(item, role) and ForLevel(item) then
			local mine = record and record.restock and record.restock[item.id]
			plan.restock[#plan.restock + 1] = { id = item.id, amount = item.amount, name = ItemName(item.id) or E:Translate(item.name) or tostring(item.id),
				status = (OnRestock(restock, item.id) and not mine) and "exists" or "add" }
		end
	end
	local room = MacroRoom()
	for _, macro in ipairs(premade.macros or {}) do
		if ForRole(macro, role) and ForLevel(macro) and (not macro.needs or FirstKnown(macro.needs)) then
			local body, why = MacroBody(macro)
			if why == "noitem" then
				plan.macros[#plan.macros + 1] = { name = macro.name:sub(1, MACRO_NAME_MAX), status = MacroIndex(macro.name) > 0 and "exists" or "noitem" }
			elseif body then
				local status
				if MacroIndex(macro.name) > 0 then
					status = "exists"
				elseif room > 0 then
					status, room = "add", room - 1
				else
					status = "full"
				end
				plan.macros[#plan.macros + 1] = { name = macro.name:sub(1, MACRO_NAME_MAX), body = body, status = status }
			end
		end
	end
	return plan
end

---------------------------------------------------------------------------
-- Apply and revert (out of combat)
---------------------------------------------------------------------------
local function Flatten(settings, prefix, out)
	for key, value in pairs(settings) do
		local path = { unpack(prefix) }
		path[#path + 1] = key
		if type(value) == "table" and next(value) and #value == 0 then
			Flatten(value, path, out)
		else
			out[#out + 1] = { path = path, value = value }
		end
	end
	return out
end

local function Walk(root, path)
	local node = root
	for index = 1, #path - 1 do
		if type(node[path[index]]) ~= "table" then return nil end
		node = node[path[index]]
	end
	return node, path[#path]
end

-- Write role settings and remember the values before (first one wins).
local function SetSettings(settings, record)
	for moduleName, values in pairs(settings or {}) do
		local module = E.modules[moduleName]
		if module and type(module.db) == "table" then
			for _, item in ipairs(Flatten(values, {}, {})) do
				local defaults = Walk(module.defaults or {}, item.path)
				local node, key = Walk(module.db, item.path)
				if node and defaults and defaults[key] ~= nil then
					local pathText = moduleName .. "." .. table.concat(item.path, ".")
					if record.settings[pathText] == nil then record.settings[pathText] = { old = node[key] } end
					node[key] = item.value
					record.settings[pathText].set = item.value
				end
			end
			if module.active and module.OnProfileChanged then pcall(module.OnProfileChanged, module) end
		end
	end
end

-- The premade's counters: appended to your list (one you have already
-- stays as it is), taken out again only while still in the list.
local function CounterEntries()
	local module = E.modules.Counters
	return module and type(module.db) == "table" and type(module.db.entries) == "table" and module.db.entries or nil, module
end

local function RefreshCounters(module)
	if module and module.active and module.OnProfileChanged then pcall(module.OnProfileChanged, module) end
end

local function AddCounters(plan, record)
	local entries, module = CounterEntries()
	if not entries then return end
	record.counters = record.counters or {}
	for _, counter in ipairs(plan.counters or {}) do
		if counter.status == "add" and not HasCounter(entries, counter.key) then
			entries[#entries + 1] = { kind = counter.kind, id = counter.id, goal = counter.goal or 0 }
			record.counters[counter.key] = true
		end
	end
	RefreshCounters(module)
end

local function UndoCounters(record)
	local entries, module = CounterEntries()
	if entries then
		for key in pairs(record.counters or {}) do
			for index = #entries, 1, -1 do
				if CounterKey(entries[index]) == key then table.remove(entries, index) end
			end
		end
		RefreshCounters(module)
	end
	record.counters = {}
end

-- The premade's restock items: appended to the Merchant list (one you
-- have already keeps your amount), taken out again only while still there.
local function RefreshRestock(module)
	if module and module.active and module.RestockChanged then pcall(module.RestockChanged, module) end
end

local function AddRestock(plan, record)
	local entries, module = RestockEntries()
	if not entries then return end
	record.restock = record.restock or {}
	for _, item in ipairs(plan.restock or {}) do
		if item.status == "add" and not OnRestock(entries, item.id) then
			entries[#entries + 1] = { id = item.id, name = item.name, amount = item.amount or 20 }
			record.restock[item.id] = true
		end
	end
	RefreshRestock(module)
end

local function UndoRestock(record)
	local entries, module = RestockEntries()
	if entries then
		for id in pairs(record.restock or {}) do
			for index = #entries, 1, -1 do
				if entries[index].id == id then table.remove(entries, index) end
			end
		end
		RefreshRestock(module)
	end
	record.restock = {}
end

local function UndoSettings(record)
	for pathText, entry in pairs(record.settings or {}) do
		local parts = { strsplit(".", pathText) }
		local module = E.modules[table.remove(parts, 1)]
		if module and type(module.db) == "table" then
			local node, key = Walk(module.db, parts)
			if node and node[key] == entry.set then node[key] = entry.old end
			if module.active and module.OnProfileChanged then pcall(module.OnProfileChanged, module) end
		end
	end
	record.settings = {}
	UndoCounters(record)
	UndoRestock(record)
end

-- Match a placement to the resulting slot change so a different button
-- the player fills during the same moment can still keep its rank.
local actionWrites = {}
function E:NoteActionWrite(slot, spellID)
	if GetTime then actionWrites[slot] = { spellID = spellID, at = GetTime() } end
end

function E:RecentActionWrite(slot, spellID, seconds)
	local write = actionWrites[slot]
	actionWrites[slot] = nil
	return write and write.spellID == spellID and GetTime() - write.at <= seconds
end

-- Put the player's own spell on an action slot: out of combat, only with
-- an empty cursor (what the player holds is never dropped), only when the
-- game really put that spell on the cursor, and the cursor is always left
-- empty. Returns true when the spell was placed, otherwise false and why:
-- "combat", "cursor", "pickup" or "place" (the game refused the slot).
local function PlaceSpell(slot, spellID)
	if not (C_Spell and C_Spell.PickupSpell and PlaceAction and ClearCursor and GetCursorInfo) then return false, "api" end
	if InCombatLockdown() then return false, "combat" end
	if GetCursorInfo() then return false, "cursor" end
	pcall(C_Spell.PickupSpell, spellID)
	if GetCursorInfo() ~= "spell" then
		ClearCursor()
		return false, "pickup"
	end
	E:NoteActionWrite(slot, spellID)
	local ok = pcall(PlaceAction, slot)
	ClearCursor()
	if not ok then return false, "place" end
	return true
end

-- Take a placed spell off its slot again, only while the slot still holds
-- it (a slot the player changed since stays as it is).
local function ClearPlaced(slot, spellID)
	local kind, id = Try(GetActionInfo, slot)
	if kind == "spell" and id == spellID and PickupAction then
		PickupAction(slot)
		ClearCursor()
		return true
	end
	return false
end

-- Shared with the keybind setup's class spells (Core/KeybindSpells.lua),
-- so both place and take back spells the same way.
E.PremadeSlots = { Place = PlaceSpell, Clear = ClearPlaced, Empty = SlotEmpty, OnBars = OnBars, StanceSlot = StanceSlot,
	StanceSpell = StanceSpell }

-- The profile part: modules, style, role settings, loadout.
local function ApplyProfilePart(premade, plan, record)
	for _, info in ipairs(plan.modules) do
		if not info.on then
			record.modules[info.name] = true
			E:SetModuleEnabled(info.name, true)
			local style = premade.styles and premade.styles[info.name]
			if style then E:ApplyStyle(info.name, style, true) end
		end
	end
	local roleInfo = RoleInfo(premade, plan.role)
	SetSettings(roleInfo and roleInfo.settings, record)
	local totems = E.Totems
	if plan.loadout and totems and totems.DefaultLoadout and totems.db then
		totems:ApplyLoadout(totems:DefaultLoadout(plan.loadout), true)
	end
	AddCounters(plan, record)
	AddRestock(plan, record)
end

function E:ApplyPremade(role, opts)
	opts = opts or {}
	local premade = self:GetClassPremade()
	if not premade then return nil end
	local plan = self:PremadePlan(role)
	local store = self:GetPrivate("premade")
	if not store then return nil end
	self:RunOutOfCombat(function()
		local record = store.applied
		-- A record from before the four roles names "damage": the same role
		-- as the class's Melee or Ranged.
		local recordRole = record and self.ResolveRoleKey and self:ResolveRoleKey(record.role, record.class) or (record and record.role)
		if record and recordRole ~= plan.role then
			UndoSettings(record)
		end
		record = record or { class = plan.class, modules = {}, settings = {}, bars = {}, macros = {}, counters = {}, restock = {} }
		record.version, record.role = premade.version, plan.role
		-- The keys and spells preview places bars and macros only: the
		-- class's modules and settings follow the Role step.
		if not opts.barsOnly then ApplyProfilePart(premade, plan, record) end
		if opts.bars then
			for _, bar in ipairs(plan.bars) do
				local place = bar.status == "place" or (bar.status == "kept" and opts.replace and opts.replace[bar.slot])
				if place and opts.only and not opts.only[bar.slot] then place = false end
				if place and PlaceSpell(bar.slot, bar.spell) then record.bars[bar.slot] = bar.spell end
			end
		end
		if opts.macros and CreateMacro then
			for _, macro in ipairs(plan.macros) do
				if macro.status == "add" and pcall(CreateMacro, macro.name, "INV_MISC_QUESTIONMARK", macro.body, true) then
					record.macros[macro.name] = macro.body
				end
			end
		end
		store.applied = record
	end, "Premade:apply")
	return plan
end

-- One revert for every caller. `parts` names what to take back:
-- { settings = true, modules = true, bars = true, macros = true }; the
-- counters go with the settings. `keep`
-- lists entries to leave in place: { bars = { [slot] = ... }, macros =
-- { [name] = ... } }. A slot or macro is cleared only while it still holds
-- what was placed; one the player changed since stays, and leaves the
-- record either way. The record goes once nothing is left in it. Out of
-- combat (waits for the end of combat). Returns false when nothing was
-- applied.
function E:RevertPremadeParts(parts, keep)
	local store = self:GetPrivate("premade")
	if not (store and store.applied) then return false end
	parts = parts or {}
	local keepBars = keep and keep.bars or {}
	local keepMacros = keep and keep.macros or {}
	self:RunOutOfCombat(function()
		local record = store.applied
		if not record then return end
		if parts.settings then UndoSettings(record) end
		if parts.modules then
			for name in pairs(record.modules or {}) do
				local module = E.modules[name]
				if module and module:IsEnabled() then E:SetModuleEnabled(name, false) end
			end
			record.modules = {}
		end
		if parts.bars then
			for slot, spellID in pairs(record.bars or {}) do
				if keepBars[slot] == nil then
					ClearPlaced(slot, spellID)
					record.bars[slot] = nil
				end
			end
		end
		if parts.macros then
			for name, body in pairs(record.macros or {}) do
				if keepMacros[name] == nil then
					local index = MacroIndex(name)
					if index > 0 and DeleteMacro and Try(GetMacroBody, index) == body then pcall(DeleteMacro, index) end
					record.macros[name] = nil
				end
			end
		end
		if not (next(record.settings or {}) or next(record.modules or {}) or next(record.bars or {}) or next(record.macros or {})
			or next(record.counters or {}) or next(record.restock or {})) then
			store.applied = nil
		end
	end)
	return true
end

function E:RevertPremade()
	return self:RevertPremadeParts({ settings = true, modules = true, bars = true, macros = true })
end

-- The Role step's "Class details": the premade's profile part follows the
-- role (on with the class layer, back when it goes). Bars and macros stay:
-- they came from their own Apply.
E:RegisterRoleCallback(function(role, classLayer)
	if not E:GetClassPremade() then return end
	if classLayer then
		E:ApplyPremade(role)
	else
		E:RevertPremadeParts({ settings = true, modules = true })
	end
end)

---------------------------------------------------------------------------
-- The setup page: bars and macros (opt-in), with what applying does
---------------------------------------------------------------------------
local picks = { bars = true, macros = true, replace = {} }

local function PlanText(plan)
	local lines = {}
	local good, warn = E.tokens.text.good, E.tokens.text.warn
	local Good = function(text) return E:TokenHex(good) .. text .. "|r" end
	local Warn = function(text) return E:TokenHex(warn) .. text .. "|r" end
	for _, info in ipairs(plan.modules) do
		lines[#lines + 1] = info.on and L["%s: already on"]:format(L[info.title]) or Good(L["%s: turns on"]:format(L[info.title]))
	end
	if plan.loadout then lines[#lines + 1] = L["Totem loadout: %s"]:format(L[E.ShamanData and E.ShamanData.DEFAULT_LOADOUTS[plan.loadout].name or plan.loadout]) end
	-- A stance page gets one line with what goes on it, so a warrior's
	-- three pages stay short.
	local pages, pageOrder = {}, {}
	for _, bar in ipairs(plan.bars) do
		local name = bar.name or "?"
		if bar.stance and bar.status == "place" then
			if not pages[bar.stance] then
				pages[bar.stance] = { title = bar.stanceName or "?", names = {} }
				pageOrder[#pageOrder + 1] = bar.stance
			end
			table.insert(pages[bar.stance].names, name)
		elseif bar.status == "place" then
			lines[#lines + 1] = Good(L["Bar %d, button %d: %s"]:format(bar.bar or 1, bar.button or bar.slot, name))
		elseif bar.status == "kept" then
			lines[#lines + 1] = Warn(bar.stance and L["%s page, slot %d: kept your own action (%s not placed)"]:format(bar.stanceName or "?", bar.button, name)
				or L["Bar %d, button %d: kept your own action (%s not placed)"]:format(bar.bar or 1, bar.button or bar.slot, name))
		elseif bar.stance then
			lines[#lines + 1] = L["%s: already on your bars (%s)"]:format(name, bar.stanceName or "?")
		else
			lines[#lines + 1] = L["%s: already on your bars"]:format(name)
		end
	end
	for _, stance in ipairs(pageOrder) do
		lines[#lines + 1] = Good(L["%s page: %s"]:format(pages[stance].title, table.concat(pages[stance].names, ", ")))
	end
	for _, counter in ipairs(plan.counters or {}) do
		lines[#lines + 1] = counter.status == "add" and Good(L["Counter %s: added"]:format(counter.name))
			or L["Counter %s: you have one, kept"]:format(counter.name)
	end
	for _, item in ipairs(plan.restock or {}) do
		lines[#lines + 1] = item.status == "add" and Good(L["Restock at vendors: keep %d %s"]:format(item.amount or 20, item.name))
			or L["Restock at vendors: %s is on your list, kept"]:format(item.name)
	end
	for _, macro in ipairs(plan.macros) do
		if macro.status == "add" then
			lines[#lines + 1] = Good(L["Macro %s: added"]:format(macro.name))
		elseif macro.status == "exists" then
			lines[#lines + 1] = L["Macro %s: you have one by that name, kept"]:format(macro.name)
		elseif macro.status == "noitem" then
			lines[#lines + 1] = L["Macro %s: carry the item first, then run the class setup again"]:format(macro.name)
		else
			lines[#lines + 1] = Warn(L["Macro %s: no room for another character macro"]:format(macro.name))
		end
	end
	return table.concat(lines, "\n")
end
E.PremadePlanText = PlanText

local function RefreshPlan(frame)
	local plan = E:PremadePlan()
	if not (frame.planText and plan) then return end
	local premade = E:GetClassPremade()
	frame.introText:SetText(L[premade.detail or premade.text] .. ".")
	-- Its height is its text, so the checks sit right under it.
	frame.introText:SetHeight(math.max(1, frame.introText:GetStringHeight() or 0))
	local width = math.max((frame.planScroll:GetWidth() or 0), 100)
	frame.planChild:SetWidth(width)
	frame.planText:SetWidth(width)
	frame.planText:SetText(PlanText(plan))
	local height = math.max(1, frame.planText:GetStringHeight() or 0)
	frame.planText:SetHeight(height)
	frame.planChild:SetHeight(height + 4)
end

-- Is `itemID` one of your class setup's counters?
local function IsCounterItem(itemID)
	local premade = E:GetClassPremade()
	for _, counter in ipairs(premade and premade.counters or {}) do
		if (counter.kind or "item") == "item" and counter.id == itemID then return true end
	end
	for _, item in ipairs(premade and premade.restock or {}) do
		if item.id == itemID then return true end
	end
	return false
end

E:RegisterInstallStep({
	key = "EldoUI:classPremade",
	title = "Class setup",
	short = Key("Class"),
	desc = "Your class's bars, totems, reminders and macros in one step.",
	order = 60,
	when = function() return E:GetClassPremade() ~= nil end,
	Build = function(frame, kit)
		local intro = kit.Paragraph(frame, 13, "")
		intro:SetPoint("TOPLEFT")
		intro:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
		frame.introText = intro
		local bars = kit.Check(frame, L["Put key spells on empty action slots"],
			L["Each spell goes on the button of its keybind category on bars 1 to 3, the same key on every class. Only empty buttons get a spell; a button with your own action is kept."],
			function(on) picks.bars = on and true or false end)
		bars:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -12)
		bars:SetChecked(true)
		local macros = kit.Check(frame, L["Add the class macros"],
			L["Character macros with their own names. A macro you already have by that name is never changed."],
			function(on) picks.macros = on and true or false end)
		macros:SetPoint("TOPLEFT", bars, "BOTTOMLEFT", 0, -6)
		macros:SetChecked(true)
		-- What applying does, in a scroll area: a class with stance pages
		-- and several roles can list more than the page has room for.
		local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", macros, "BOTTOMLEFT", 0, -12)
		scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -22, 0)
		if scroll.ScrollBar then E:SkinScrollBar(scroll.ScrollBar) end
		local child = CreateFrame("Frame", nil, scroll)
		child:SetSize(1, 10)
		scroll:SetScrollChild(child)
		local text = kit.Paragraph(child, 13, "")
		text:SetPoint("TOPLEFT")
		frame.planScroll, frame.planChild, frame.planText = scroll, child, text
		-- A counter's item name can arrive after the page asked for it: the
		-- list then shows the game's own name.
		local watcher = CreateFrame("Frame", nil, frame)
		watcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		watcher:SetScript("OnEvent", function(_, _, itemID)
			itemID = E.Plain(itemID)
			if frame:IsVisible() and IsCounterItem(itemID) then RefreshPlan(frame) end
		end)
	end,
	Refresh = RefreshPlan,
	Apply = function()
		E:ApplyRole(E:GetRole(), { classLayer = true })
		E:ApplyPremade(nil, { bars = picks.bars, macros = picks.macros, replace = picks.replace })
	end,
	Summary = function() return L["Class setup"] end,
})
