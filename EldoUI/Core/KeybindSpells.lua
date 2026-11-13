-- EldoUI keybind setup, class spells: the How to play preview can also
-- put your class's known spells on the empty buttons of their category
-- (Data/KeybindCategories.lua), so an alt finds them under the same keys.
--
--   E:KeybindSpellPlan([opts])      what Apply would place, read only, for
--                                   this character, class and role: per
--                                   button the spell and what happens
--                                   (place, already on your bars, kept
--                                   because the button holds your own
--                                   action, not learned yet, ...)
--   E:KeybindSpellEntry(plan, bar, button[, page])
--                                   one button's entry; bar 1 of a class
--                                   with stance, Stealth or form pages has
--                                   one per page (the page shown now when
--                                   page is left out)
--   E:ApplyKeybindSpells(plan)      places the planned spells, out of
--                                   combat, with an empty cursor, after
--                                   checking the plan still matches your
--                                   bars, class and character
--   E:RevertKeybindSpells([report]) takes the placed spells off again,
--                                   only where a button still holds them
--   E:HasKeybindSpells()            something to take back
--
-- Only empty buttons get a spell; a button with your own action keeps it,
-- and a spell already on your bars is never moved or doubled. Bar 1's
-- spells go on the page they are used on: a Warrior's on each stance's
-- page, a Rogue's Stealth spells on the Stealth page, a Druid's cat and
-- bear spells on the Cat Form and Bear Form pages, once you know that
-- stance or form. Bar 3 has nine buttons: its keys 10 to 12 press the
-- Consumable Bar, so nothing is placed there. Nothing happens on login,
-- level-up or a role change: spells are placed only when you tick them in
-- the preview and press Apply. The record of what was placed belongs to
-- the character, so a profile shared with another character never carries
-- its spells over.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

E:RegisterPrivate("keybindSpells", {})

local function Plain(value)
	if E.Secret and E.Secret(value) then return nil end
	return value
end

local function PlayerClass()
	local _, class = UnitClass("player")
	return Plain(class)
end

local function Role()
	return E.GetRole and E:GetRole() or "none"
end

local function Slots() return E.PremadeSlots end

-- The spell on an action slot, or nil.
local function SlotSpell(slot)
	if type(GetActionInfo) ~= "function" then return nil end
	local ok, kind, id = pcall(GetActionInfo, slot)
	if ok and Plain(kind) == "spell" then return Plain(id) end
	return nil
end

local function CursorBusy()
	if type(GetCursorInfo) ~= "function" then return false end
	local ok, kind = pcall(GetCursorInfo)
	return ok and kind ~= nil
end

---------------------------------------------------------------------------
-- The plan (read only)
---------------------------------------------------------------------------
-- Entry status: "place" (goes on the empty button), "onbar" (already on
-- your bars: not moved), "kept" (the button holds your own action),
-- "hidden" (the button is turned off), "noform" (its page needs a stance
-- or form you have not learned), "placed" (put there by an earlier Apply
-- and still there), or the category state when there is no known spell:
-- "unlearned", "reserved", "missing", "open".
function E:KeybindSpellPlan(opts)
	opts = opts or {}
	local C = self.keybindCategories
	local slots = Slots()
	local class, role = opts.class or PlayerClass(), opts.role or Role()
	local plan = { class = class, role = role, char = self.charKey, entries = {}, pageEntries = {}, places = {},
		counts = { place = 0, onbar = 0, kept = 0, hidden = 0, paged = 0, noform = 0, placed = 0, unlearned = 0 } }
	if not (C and slots and class) then
		plan.signature = "none"
		return plan
	end
	local capacity = self.KeybindBarCapacity and self:KeybindBarCapacity() or {}
	local record = self:GetPrivate("keybindSpells")
	local mine = record and record.class == class and record.slots or {}
	local used, sig = {}, { class, role, tostring(self.charKey) }
	local pages = C.pages[class]
	local shown = pages and C.CurrentPage(class)
	local function Entry(bar, button, page, cap)
		local r = C.Resolve(bar, button, class, role, page)
		local entry = { bar = bar, button = button, page = r.page, category = r.key, info = r.info, spell = r.spell, name = r.name,
			icon = r.icon, state = r.state }
		if r.state == "ready" and r.key then
			local slot, stance = self:KeybindActionSlot(bar, button), nil
			if r.offset then
				stance = r.offset
				slot = slots.StanceSlot(stance, button)
				if not C.Known(r.form) then entry.status = "noform" end
			end
			entry.slot, entry.stance = slot, stance
			local seen = (stance or 0) .. ":" .. r.spell
			if entry.status == "noform" then
				entry.slot = nil
			elseif not cap.enabled or button > (cap.buttons or 12) then
				entry.status = "hidden"
			elseif mine[slot] == r.spell and SlotSpell(slot) == r.spell then
				entry.status = "placed"
			elseif used[seen] or slots.OnBars(r.spell, stance) then
				entry.status = "onbar"
			elseif not slots.Empty(slot) then
				entry.status = "kept"
			else
				entry.status = "place"
				used[seen] = true
				plan.places[#plan.places + 1] = entry
			end
		else
			entry.status = r.state
		end
		plan.counts[entry.status] = (plan.counts[entry.status] or 0) + 1
		sig[#sig + 1] = ("%d.%d.%s=%s:%s:%s"):format(bar, button, tostring(entry.page), entry.status, tostring(entry.spell), tostring(entry.slot))
		return entry
	end
	for _, bar in ipairs(self.keybindManagedBars) do
		local cap = capacity[bar] or { enabled = true, buttons = 12 }
		for button = 1, 12 do
			if bar == 1 and pages then
				-- The page shown now is the button's entry; the other pages
				-- follow in their own list.
				plan.entries[#plan.entries + 1] = Entry(bar, button, shown, cap)
				for _, page in ipairs(pages) do
					if page ~= shown then plan.pageEntries[#plan.pageEntries + 1] = Entry(bar, button, page, cap) end
				end
			else
				plan.entries[#plan.entries + 1] = Entry(bar, button, nil, cap)
			end
		end
	end
	plan.signature = table.concat(sig, ";")
	return plan
end

-- The entry of one bar button in a plan: on bar 1 of a class with pages,
-- the entry of that page (the page shown now when page is left out).
function E:KeybindSpellEntry(plan, bar, button, page)
	if not plan then return nil end
	local entry = plan.entries[(bar - 1) * 12 + button]
	if page == nil or (entry and entry.page == page) then return entry end
	for _, other in ipairs(plan.pageEntries or {}) do
		if other.bar == bar and other.button == button and other.page == page then return other end
	end
	return nil
end

---------------------------------------------------------------------------
-- Apply and take back
---------------------------------------------------------------------------
-- Why a plan can't be applied right now, or nil.
function E:KeybindSpellsBlocked(plan)
	if InCombatLockdown() then return "combat", L["Spells can't move onto your bars in combat."] end
	if CursorBusy() then return "cursor", L["Put down what is on your cursor first."] end
	if not plan or plan.char ~= self.charKey or plan.class ~= PlayerClass() then
		return "other", L["This plan was made for another character. Look at the preview again."]
	end
	local fresh = self:KeybindSpellPlan({ role = plan.role })
	if fresh.signature ~= plan.signature then return "stale", L["Your bars changed since the preview. Look at the preview again before you apply."] end
	return nil
end

-- Places the plan's spells. Returns true and { placed, failed }, or false
-- and why. report: false says nothing (the combined Apply reports once).
function E:ApplyKeybindSpells(plan, report)
	local why, notice = self:KeybindSpellsBlocked(plan)
	if why then
		if report ~= false then self:ConfigNotice(notice, true) end
		return false, why
	end
	local record = self:GetPrivate("keybindSpells")
	-- A record of another class (never on one character) starts over.
	if record.class ~= plan.class then
		record.class, record.slots = plan.class, {}
	end
	record.slots = record.slots or {}
	local placed, failed = 0, 0
	for _, entry in ipairs(plan.places) do
		if Slots().Place(entry.slot, entry.spell) then
			record.slots[entry.slot] = entry.spell
			placed = placed + 1
		else
			failed = failed + 1
		end
	end
	record.time = time()
	if not next(record.slots) then record.class, record.slots, record.time = nil, nil, nil end
	if self.KeybindPreviewChanged then self:KeybindPreviewChanged() end
	return true, { placed = placed, failed = failed, kept = plan.counts.kept, onbar = plan.counts.onbar }
end

function E:HasKeybindSpells()
	local record = self:GetPrivate("keybindSpells")
	return record and record.slots and next(record.slots) ~= nil or false
end

-- Takes the placed spells off the buttons that still hold them; a button
-- you changed since keeps your action. report as E:RestoreKeybinds.
function E:RevertKeybindSpells(report)
	local function Report(text, warn)
		if report == false then return end
		if type(report) == "function" then report(text, warn) else self:Print(text) end
	end
	local record = self:GetPrivate("keybindSpells")
	if not (record and record.slots and next(record.slots)) then
		Report(L["No placed spells to take back on this character."], true)
		return false
	end
	if InCombatLockdown() then
		Report(L["Spells can't move onto your bars in combat."], true)
		return false
	end
	local cleared = 0
	for slot, spell in pairs(record.slots) do
		if Slots().Clear(slot, spell) then cleared = cleared + 1 end
	end
	record.class, record.slots, record.time = nil, nil, nil
	Report(E:Plural(cleared, "%d placed spell taken off your bars.", "%d placed spells taken off your bars."):format(cleared))
	if self.KeybindPreviewChanged then self:KeybindPreviewChanged() end
	return true
end
