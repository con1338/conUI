-- EldoUI controller spells: the key map's class spells on the game's
-- controller bars, by the grid in Data/GamepadBindings.lua, so a spell
-- keeps its place in the order with keys or with a controller.
--
--   E:GamepadSpellPlan([opts])      what Apply would place, read only, for
--                                   this character, class and role: per
--                                   key map button the spell, its
--                                   controller slot and what happens
--   E:GamepadSpellEntry(plan, bar, button[, page])
--                                   one button's entry; bar 1 of a class
--                                   with stance, Stealth or form pages has
--                                   one per page under the stance bar
--   E:GamepadSpellsBlocked(plan)    why Apply can't run now, or nil
--   E:ApplyGamepadSpells(plan[, report])
--                                   places the planned spells, out of
--                                   combat, with an empty cursor, after
--                                   checking the plan still matches
--   E:RevertGamepadSpells([report]) takes the placed spells off again,
--                                   only where a slot still holds them
--   E:HasGamepadSpells()            something to take back
--   E:GamepadStorageSlot(page, slot) the game's action slot of a
--                                   controller page slot, through the
--                                   game's own helper, or nil
--
-- The same rules as the keyboard's class spells: only empty slots get a
-- spell, a slot with your own action keeps it, a spell already on your
-- controller bars is never moved or doubled, and nothing happens until you
-- press Apply. Stance, Stealth and form spells go on the game's stance
-- bar, which takes the place of one controller bar while the stance or
-- form is on: Apply fills the stance bar of the stance or form you are in,
-- and the others wait until you switch and press Apply again. When the
-- game's stance bar setting moves it to another bar, bar 1's first eight
-- spells follow it there. Consumables get no controller slot: the
-- Consumable Bar stays on screen. No key binding is written, for the
-- keyboard or the controller. The record of what was placed belongs to
-- the character.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

E:RegisterPrivate("gamepadSpells", {})

local issecret = issecretvalue or function() return false end

local function Plain(value)
	if issecret(value) then return nil end
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
local function Data() return E.gamepadBindings end

-- The player's own action slots end at 180; the controller's lie above.
local LAST_PLAYER_SLOT = 180

local function GamepadCall(name, ...)
	local api = C_GamepadUI
	local fn = api and api[name]
	if type(fn) ~= "function" then return nil end
	local ok, value = pcall(fn, ...)
	if ok then return Plain(value) end
	return nil
end

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

local function ValidSlot(slot)
	return type(slot) == "number" and slot > LAST_PLAYER_SLOT and GamepadCall("IsValidGamepadActionStorageSlotIndex", slot) == true
end

function E:GamepadStorageSlot(page, pageSlot)
	local util = rawget(_G, "GamepadActionBarBindingUtil")
	local fn = type(util) == "table" and util.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID
	if type(fn) ~= "function" then return nil end
	local ok, slot = pcall(fn, page, pageSlot)
	slot = ok and Plain(slot) or nil
	return ValidSlot(slot) and slot or nil
end

-- The page and bar the game's stance bar covers, or nil when it is off.
local function StanceCover()
	local data = Data()
	local ok, value = pcall(GetCVar, "GamepadStanceBarOverride")
	value = ok and tonumber(Plain(value)) or data.stanceDefault
	local cover = data.stanceBar[value]
	if not cover then return nil end
	return cover[1], cover[2]
end

-- The bonus bar offset of the stance or form you are in, or nil.
local function ActiveOffset()
	local bar = C_ActionBar
	if not (bar and bar.HasBonusActionBar and bar.GetBonusBarOffset) then return nil end
	local ok, has = pcall(bar.HasBonusActionBar)
	if not (ok and Plain(has)) then return nil end
	local okOffset, offset = pcall(bar.GetBonusBarOffset)
	offset = okOffset and Plain(offset) or nil
	return type(offset) == "number" and offset > 0 and offset or nil
end

-- A key map button's controller page, bar and page slot. Bar 1's first
-- buttons always sit under the stance bar: when the game's setting moves
-- the stance bar from page 1's right bar, the two bars trade places.
local function Target(bar, button, coverPage, coverBar)
	local data = Data()
	local spot = data.grid[bar] and data.grid[bar][button]
	if not spot then return nil end
	local page, name = spot[1], spot[2]
	if coverPage then
		if page == 1 and name == "right" then
			page, name = coverPage, coverBar
		elseif page == coverPage and name == coverBar then
			page, name = 1, "right"
		end
	end
	return page, name, data.bars[name] + spot[3] - 1
end

-- The spell's controller slots, through the game's controller search
-- set; without the set, the slots above the player's own.
local function ControllerSlots(spellID)
	local find = C_ActionBar and C_ActionBar.FindSpellActionButtons
	if type(find) ~= "function" then return {} end
	local set = Enum and Enum.ActionBarSet and Enum.ActionBarSet.Gamepad
	local ok, slots
	if set then ok, slots = pcall(find, spellID, set) else ok, slots = pcall(find, spellID) end
	if not (ok and type(slots) == "table" and not issecret(slots)) then return {} end
	local out = {}
	for _, slot in ipairs(slots) do
		if type(slot) == "number" and slot > LAST_PLAYER_SLOT then out[#out + 1] = slot end
	end
	return out
end

-- Is the spell on your controller bars already? For a stance bar entry:
-- on that stance bar, or on a bar the stance bar never covers.
local function OnControllerBars(spellID, stanceFirst, stanceCount, covered)
	for _, slot in ipairs(ControllerSlots(spellID)) do
		if not stanceFirst then return true end
		if (slot >= stanceFirst and slot < stanceFirst + stanceCount) or not covered[slot] then return true end
	end
	return false
end

---------------------------------------------------------------------------
-- The plan (read only)
---------------------------------------------------------------------------
-- Entry status as the keyboard's class spells ("place", "onbar", "kept",
-- "placed", "noform" and the category states), plus "otherform" (a
-- stance bar spell of a stance or form you are not in now: switch to it
-- and press Apply again) and "noslot" (the game has no controller slot
-- there). plan.unavailable: the game's controller bars aren't there.
function E:GamepadSpellPlan(opts)
	opts = opts or {}
	local C, data, slots = self.keybindCategories, Data(), Slots()
	local class, role = opts.class or PlayerClass(), opts.role or Role()
	local plan = { class = class, role = role, char = self.charKey, entries = {}, pageEntries = {}, places = {}, byButton = {},
		counts = { place = 0, onbar = 0, kept = 0, placed = 0, noform = 0, otherform = 0, noslot = 0, unlearned = 0 } }
	if not (C and data and slots and class) then
		plan.signature = "none"
		return plan
	end
	if not self:GamepadStorageSlot(1, data.bars.right) then
		plan.signature, plan.unavailable = "none", true
		return plan
	end
	local record = self:GetPrivate("gamepadSpells")
	local mine = record and record.class == class and record.slots or {}
	local coverPage, coverBar = StanceCover()
	-- The top bar's right group is the game's own, so a stance bar there
	-- takes no spells.
	if coverBar == "top" then coverPage, coverBar = nil, nil end
	local stanceCount = data.stanceButtons
	local covered = {}
	if coverPage then
		plan.stanceBar = { page = coverPage, bar = coverBar }
		for index = 0, stanceCount - 1 do
			local slot = self:GamepadStorageSlot(coverPage, data.bars[coverBar] + index)
			if slot then covered[slot] = true end
		end
	end
	local pages, active = C.pages[class], ActiveOffset()
	local stanceFirst = coverPage and active and GamepadCall("GetFirstGamepadActionBarStorageSlotIndexForActiveStance") or nil
	if type(stanceFirst) ~= "number" then stanceFirst = nil end
	local used, sig = {}, { class, role, tostring(self.charKey), tostring(coverPage) .. tostring(coverBar), tostring(stanceFirst) }
	local function Entry(bar, button, page)
		local r = C.Resolve(bar, button, class, role, page)
		local targetPage, targetBar, pageSlot = Target(bar, button, coverPage, coverBar)
		local entry = { bar = bar, button = button, page = r.page, category = r.key, info = r.info, spell = r.spell, name = r.name,
			icon = r.icon, state = r.state, reason = r.reason, formName = r.formName, gamepadPage = targetPage, gamepadBar = targetBar,
			gamepadButton = pageSlot and pageSlot - data.bars[targetBar] + 1 }
		if r.state == "ready" and r.key then
			local slot, first
			if r.offset and coverPage and button <= stanceCount then
				entry.stanceBar = true
				if not C.Known(r.form) then
					entry.status = "noform"
				elseif r.offset ~= active or not stanceFirst then
					entry.status = "otherform"
				else
					first, slot = stanceFirst, stanceFirst + button - 1
					if not ValidSlot(slot) then entry.status = "noslot" end
				end
			else
				slot = pageSlot and self:GamepadStorageSlot(targetPage, pageSlot)
				if not slot then entry.status = "noslot" end
			end
			if not entry.status then
				entry.slot = slot
				local seen = (first or 0) .. ":" .. r.spell
				if mine[slot] == r.spell and SlotSpell(slot) == r.spell then
					entry.status = "placed"
				elseif used[seen] or OnControllerBars(r.spell, first, stanceCount, covered) then
					entry.status = "onbar"
				elseif not slots.Empty(slot) then
					entry.status = "kept"
				else
					entry.status = "place"
					used[seen] = true
					plan.places[#plan.places + 1] = entry
				end
			end
		else
			entry.status = r.state
		end
		plan.counts[entry.status] = (plan.counts[entry.status] or 0) + 1
		sig[#sig + 1] = ("%d.%d.%s=%s:%s:%s"):format(bar, button, tostring(entry.page), entry.status, tostring(entry.spell), tostring(entry.slot))
		return entry
	end
	local barButtons = self.keybindBarButtons or { 12, 12, 9 }
	for bar = 1, #data.grid do
		plan.byButton[bar] = {}
		for button = 1, math.min(barButtons[bar] or 12, #data.grid[bar]) do
			local main
			if bar == 1 and pages and coverPage and button <= stanceCount then
				-- Under the stance bar: the page of the stance or form you
				-- are in is the button's entry, the other pages follow.
				local shown = C.CurrentPage(class)
				main = Entry(bar, button, shown)
				for _, page in ipairs(pages) do
					if page ~= shown then plan.pageEntries[#plan.pageEntries + 1] = Entry(bar, button, page) end
				end
			elseif bar == 1 and pages then
				-- A bar the stance bar never covers shows in every stance:
				-- the first page's spells (the page you see now when the
				-- stance bar is off).
				main = Entry(bar, button, coverPage and pages[1] or C.CurrentPage(class))
			else
				main = Entry(bar, button)
			end
			plan.entries[#plan.entries + 1] = main
			plan.byButton[bar][button] = main
		end
	end
	plan.signature = table.concat(sig, ";")
	return plan
end

function E:GamepadSpellEntry(plan, bar, button, page)
	local entry = plan and plan.byButton and plan.byButton[bar] and plan.byButton[bar][button]
	if page == nil or (entry and entry.page == page) then return entry end
	for _, other in ipairs(plan.pageEntries or {}) do
		if other.bar == bar and other.button == button and other.page == page then return other end
	end
	return nil
end

---------------------------------------------------------------------------
-- Apply and take back
---------------------------------------------------------------------------
function E:GamepadSpellsBlocked(plan)
	if InCombatLockdown() then return "combat", L["Spells can't move onto your bars in combat."] end
	if CursorBusy() then return "cursor", L["Put down what is on your cursor first."] end
	local addon, title
	if self.ControllerAddon then addon, title = self:ControllerAddon() end
	if addon then
		return "addon", L["%s sets up your controller's buttons, so EldoUI leaves the controller bars to it."]:format(title or addon)
	end
	if not plan or plan.unavailable then return "unavailable", L["The game's controller bars aren't available right now."] end
	if plan.char ~= self.charKey or plan.class ~= PlayerClass() then
		return "other", L["This plan was made for another character. Look at the preview again."]
	end
	local fresh = self:GamepadSpellPlan({ role = plan.role })
	if fresh.signature ~= plan.signature then return "stale", L["Your bars changed since the preview. Look at the preview again before you apply."] end
	return nil
end

-- Places the plan's spells. Returns true and { placed, failed, kept,
-- onbar, otherform }, or false and why. report: false says nothing.
function E:ApplyGamepadSpells(plan, report)
	local function Report(text, warn)
		if report == false then return end
		if type(report) == "function" then report(text, warn) else self:ConfigNotice(text, warn) end
	end
	local why, notice = self:GamepadSpellsBlocked(plan)
	if why then
		Report(notice, true)
		return false, why
	end
	local record = self:GetPrivate("gamepadSpells")
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
	Report(E:Plural(placed, "%d spell placed on your controller bars.", "%d spells placed on your controller bars."):format(placed))
	if self.KeybindPreviewChanged then self:KeybindPreviewChanged() end
	return true, { placed = placed, failed = failed, kept = plan.counts.kept, onbar = plan.counts.onbar, otherform = plan.counts.otherform }
end

function E:HasGamepadSpells()
	local record = self:GetPrivate("gamepadSpells")
	return record and record.slots and next(record.slots) ~= nil or false
end

-- Takes the placed spells off the slots that still hold them; a slot you
-- changed since keeps your action. report as E:RevertKeybindSpells.
function E:RevertGamepadSpells(report)
	local function Report(text, warn)
		if report == false then return end
		if type(report) == "function" then report(text, warn) else self:Print(text) end
	end
	local record = self:GetPrivate("gamepadSpells")
	if not (record and record.slots and next(record.slots)) then
		Report(L["No placed controller spells to take back on this character."], true)
		return false
	end
	if InCombatLockdown() then
		Report(L["Spells can't move onto your bars in combat."], true)
		return false
	end
	if CursorBusy() then
		Report(L["Put down what is on your cursor first."], true)
		return false
	end
	local cleared = 0
	for slot, spell in pairs(record.slots) do
		if Slots().Clear(slot, spell) then cleared = cleared + 1 end
	end
	record.class, record.slots, record.time = nil, nil, nil
	Report(E:Plural(cleared, "%d placed spell taken off your controller bars.", "%d placed spells taken off your controller bars."):format(cleared))
	if self.KeybindPreviewChanged then self:KeybindPreviewChanged() end
	return true
end
