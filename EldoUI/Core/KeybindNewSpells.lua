-- EldoUI keybind setup, new spells on their key: a spell the player learns
-- (at the trainer, from a talent, a new form or stance) goes to the button
-- its key category names (Data/KeybindCategories.lua), or to the button
-- the player picked for that spell, so it sits under the same key on
-- every character of the class.
--
--   E:NewSpellsMode()        "offer" (default), "auto" or "off", from the
--                            profile's key map settings
--   E:NewSpellPlan(names)    read only: for each newly learned spell name,
--                            its button and what would happen there
--   E:PlaceNewSpells(plan)   places the plan's spells, out of combat, with
--                            an empty cursor; one chat line; kept for Undo
--   E:UndoNewSpells()        takes the last placed spells off again, only
--                            where a button still holds them
--
-- Offer: one notice names the new spells and their buttons, with a button
-- to put them there. Automatic (only when the player picks it): they are
-- placed after the learn, out of combat, and the game's own "put new
-- spells on the bars" setting is turned off meanwhile so nothing lands
-- twice; the player's value comes back when they pick another mode.
-- Off: nothing.
--
-- Only an empty button gets a spell. A button with the player's own action
-- keeps it (the notice says so), and a spell already on the bars is never
-- moved or doubled. A new rank of a spell is not a new spell: the spell
-- rank upgrade handles that (Modules/ActionBars/Ranks.lua). Placed spells
-- join the record of the keys and spells preview, so its Take back and
-- its "placed" marks include them. A new spell with a home for outside a
-- fight goes to bars 4 and 5 when the player turned that on
-- (Core/KeybindQuietBars.lua).
--
-- Talent reset: when the game asks the player to confirm a talent reset,
-- the button of every spell on their bars is saved for the talent group
-- (only the player accepts the reset, in the game's own dialog). A spell
-- that comes back as new afterwards, which after a reset means a talent
-- spell learned again, goes back to that button: the player's own home
-- first, then the button before the reset, then the category button. The
-- saved buttons are dropped once used, or after seven days.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local issecret = issecretvalue or function() return false end

local MODES = { offer = true, auto = true, off = true }
local CVAR, CVAR_OWNER = "AutoPushSpellToActionBar", "KeybindNewSpells"

-- The last placement on this character, for Undo: { slots = { [slot] =
-- spellID }, time }; and the buttons before a talent reset: talentReset =
-- { [talent group] = { spells = { [spell name] = slot }, time } }.
E:RegisterPrivate("newSpells", {})

function E:NewSpellsMode()
	if self.KeymapSetting then
		local mode = self:KeymapSetting("newSpells")
		if MODES[mode] then return mode end
	end
	local keymap = self.db and self.db.keymap
	local mode = type(keymap) == "table" and keymap.newSpells
	if MODES[mode] then return mode end
	return "offer"
end

-- The profile's key map record, with this setting filled in, for the
-- options rows that read and write it.
function E:NewSpellsRecord()
	if type(self.db) ~= "table" then return {} end
	local record = self.KeymapRecord and self:KeymapRecord()
	if type(record) ~= "table" then
		if type(self.db.keymap) ~= "table" then self.db.keymap = {} end
		record = self.db.keymap
	end
	if record.newSpells == nil then record.newSpells = self:NewSpellsMode() end
	return record
end

-- What the game's push follows: the mode last applied.
local appliedMode

function E:SetNewSpellsMode(mode)
	if not MODES[mode] then return end
	self:NewSpellsRecord().newSpells = mode
	appliedMode = mode
	self:ApplyNewSpellsCVar()
end

-- After the options page, a profile switch or a synced key map changed
-- the record (the Action Bars refresh calls it, Core/KeybindQuietBars.lua
-- adds the bar 4 and 5 fill).
function E:NewSpellsModeChanged()
	local mode = self:NewSpellsMode()
	if appliedMode == nil or mode == appliedMode then
		appliedMode = mode
		return
	end
	appliedMode = mode
	self:ApplyNewSpellsCVar()
end

-- While automatic, the game's own first-free-button push is off; the
-- player's value comes back otherwise.
function E:ApplyNewSpellsCVar()
	if self:NewSpellsMode() == "auto" then
		self:RunOutOfCombat(function() E:SetCVar(CVAR, "0", CVAR_OWNER) end, "KeybindNewSpells:cvar")
	else
		self:RestoreCVars(CVAR_OWNER)
	end
end

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

local function Role()
	return E.GetRole and E:GetRole() or "none"
end

-- The names of the spells the player knows now (one per spell, any rank).
local function KnownNames()
	local module = E.modules and E.modules.ActionBars
	local scan = module and module.RankScan and module:RankScan()
	local names = {}
	for name, spellID in pairs(scan and scan.best or {}) do names[name] = spellID end
	return names
end

-- The button the player picked for a spell (the key map's own homes),
-- by the spell's name: "b<bar>s<button>" -> action slot, or nil.
local function OwnHome(name)
	local keymap = E.db and E.db.keymap
	local homes = type(keymap) == "table" and type(keymap.homes) == "table" and keymap.homes[PlayerClass() or ""]
	homes = type(homes) == "table" and homes[Role()]
	if type(homes) ~= "table" then return nil end
	for head, where in pairs(homes) do
		if type(head) == "number" and type(where) == "string" and SpellName(head) == name then
			local bar, button = where:match("^b(%d+)s(%d+)$")
			bar, button = tonumber(bar), tonumber(button)
			if bar and button and E.KeybindActionSlot then return E:KeybindActionSlot(bar, button), bar, button end
		end
	end
	return nil
end

local function SlotEmpty(slot)
	local slots = E.PremadeSlots
	return slots and slots.Empty and slots.Empty(slot) or false
end

---------------------------------------------------------------------------
-- The buttons before a talent reset
---------------------------------------------------------------------------
local RESET_KEEP = 7 * 24 * 60 * 60

-- The action slots of bars 1 to 8 with bar 1's pages, and the stance,
-- Stealth and form pages (73 to 120).
local RESET_SLOTS = {}
for slot = 1, 120 do RESET_SLOTS[#RESET_SLOTS + 1] = slot end
for slot = 145, 180 do RESET_SLOTS[#RESET_SLOTS + 1] = slot end

local function TalentGroup()
	return E.TalentGroup and E:TalentGroup() or 1
end

-- The saved buttons of a talent group, or nil; a save older than seven
-- days is dropped here.
local function ResetSaved(group)
	local record = E:GetPrivate("newSpells")
	local all = type(record) == "table" and record.talentReset
	if type(all) ~= "table" then return nil end
	local saved = all[group]
	if type(saved) ~= "table" or type(saved.spells) ~= "table" or type(saved.time) ~= "number"
		or time() - saved.time > RESET_KEEP or not next(saved.spells) then
		all[group] = nil
		if not next(all) then record.talentReset = nil end
		return nil
	end
	return saved
end

-- The button a spell had before the last talent reset, or nil.
local function ResetSlot(name)
	local saved = ResetSaved(TalentGroup())
	local slot = saved and saved.spells[name]
	return type(slot) == "number" and slot or nil
end

-- A spell went back on its button: that saved button is used.
local function ResetUsed(name)
	local group = TalentGroup()
	local saved = ResetSaved(group)
	if not saved then return end
	saved.spells[name] = nil
	ResetSaved(group)
end

-- Saves the button of every spell on the player's bars for the active
-- talent group. A spell saved by an earlier reset and not learned again
-- yet keeps its button, unless another spell sits there now. Returns how
-- many buttons are saved.
function E:SaveTalentResetSlots()
	local record = self:GetPrivate("newSpells")
	if type(record) ~= "table" or not GetActionInfo then return 0 end
	local group = TalentGroup()
	local spells, used, count = {}, {}, 0
	for _, slot in ipairs(RESET_SLOTS) do
		local ok, kind, id = pcall(GetActionInfo, slot)
		if ok and Plain(kind) == "spell" and type(Plain(id)) == "number" then
			local name = SpellName(id)
			if name and not spells[name] then
				spells[name], used[slot], count = slot, true, count + 1
			end
		end
	end
	local before = ResetSaved(group)
	for name, slot in pairs(before and before.spells or {}) do
		if spells[name] == nil and not used[slot] then
			spells[name], used[slot], count = slot, true, count + 1
		end
	end
	if count == 0 then return 0 end
	if type(record.talentReset) ~= "table" then record.talentReset = {} end
	record.talentReset[group] = { spells = spells, time = time() }
	return count
end

-- Where a slot is, in words ("Bar 1, button 8").
function E:NewSpellSlotWords(slot)
	local P = self.KeybindPreview
	if P and P.SlotWords then return P.SlotWords(slot) end
	return tostring(slot)
end

-- Every button entry of a keys and spells plan: the buttons, and on bar 1
-- of a class with stance, Stealth or form pages the other pages too.
local function PlanEntries(plan)
	local list = {}
	for _, entry in ipairs(plan.entries or {}) do list[#list + 1] = entry end
	for _, entry in ipairs(plan.pageEntries or {}) do list[#list + 1] = entry end
	return list
end

-- One key per button and page.
local function ButtonKey(entry)
	return ("%d.%d.%s"):format(entry.bar, entry.button, tostring(entry.page))
end

---------------------------------------------------------------------------
-- The plan (read only)
---------------------------------------------------------------------------
-- names: { [name] = spellID } of newly learned spells; forms: { [button
-- key] = true } for the form and stance page buttons that waited for a form the
-- player has now. Entries { name, spell, slot, status, back }: "place"
-- (goes on the empty button), "kept" (the button holds the player's own
-- action), "onbar" (already on the bars); back is true for the button the
-- spell had before a talent reset.
function E:NewSpellPlan(names, forms)
	local plan = { char = self.charKey, entries = {}, places = {} }
	if not (self.KeybindSpellPlan and self.PremadeSlots) then return plan end
	local spells = self:KeybindSpellPlan()
	local done = {}
	local function Add(entry)
		plan.entries[#plan.entries + 1] = entry
		if entry.status == "place" then plan.places[#plan.places + 1] = entry end
	end
	local function Status(spellID, slot)
		if self.PremadeSlots.OnBars(spellID) then return "onbar" end
		if not SlotEmpty(slot) then return "kept" end
		return "place"
	end
	-- The player's own button for a spell wins over its category button,
	-- and so does the button the player gave it before a talent reset.
	for name, spellID in pairs(names or {}) do
		local slot = OwnHome(name)
		if slot then
			done[name] = true
			Add({ name = name, spell = spellID, slot = slot, status = Status(spellID, slot) })
		end
	end
	for name, spellID in pairs(names or {}) do
		local slot = not done[name] and ResetSlot(name)
		if slot then
			done[name] = true
			Add({ name = name, spell = spellID, slot = slot, status = Status(spellID, slot), back = true })
		end
	end
	for _, entry in ipairs(PlanEntries(spells)) do
		local name = entry.spell and SpellName(entry.spell)
		local new = name and names and names[name] and not done[name]
		local form = forms and forms[ButtonKey(entry)]
		if (new or form) and entry.slot and (entry.status == "place" or entry.status == "kept" or entry.status == "onbar") then
			done[name or entry.spell] = true
			Add({ name = name or tostring(entry.spell), spell = entry.spell, slot = entry.slot, status = entry.status })
		end
	end
	table.sort(plan.places, function(a, b) return a.slot < b.slot end)
	return plan
end

---------------------------------------------------------------------------
-- Placing and taking back
---------------------------------------------------------------------------
-- Places the plan's spells. Returns how many were placed, or 0 and why
-- ("combat", "cursor").
function E:PlaceNewSpells(plan, quiet)
	if InCombatLockdown() then return 0, "combat" end
	if GetCursorInfo and GetCursorInfo() then return 0, "cursor" end
	local place = self.PremadeSlots and self.PremadeSlots.Place
	if not (place and plan) then return 0 end
	local record = self:GetPrivate("newSpells")
	local spells = self:GetPrivate("keybindSpells")
	local class = PlayerClass()
	local placed, names = {}, {}
	for _, entry in ipairs(plan.places) do
		-- The button may have changed since the plan was made.
		if SlotEmpty(entry.slot) and not self.PremadeSlots.OnBars(entry.spell) and place(entry.slot, entry.spell) then
			placed[entry.slot] = entry.spell
			names[#names + 1] = (entry.back and L["%s back on %s"] or L["%s on %s"]):format(entry.name, self:NewSpellSlotWords(entry.slot))
			if entry.back then ResetUsed(entry.name) end
			-- The preview's record: its marks and Take back include them.
			if type(spells) == "table" and class then
				if spells.class ~= class then spells.class, spells.slots = class, {} end
				spells.slots = spells.slots or {}
				spells.slots[entry.slot] = entry.spell
				spells.time = time()
			end
		end
	end
	if #names == 0 then return 0 end
	if type(record) == "table" then record.slots, record.time = placed, time() end
	if not quiet then
		self:Print(L["New spells placed: %s. /eui spells undo takes them off again."]:format(table.concat(names, ", ")))
	end
	if self.KeybindPreviewChanged then self:KeybindPreviewChanged() end
	return #names
end

function E:HasNewSpellsUndo()
	local record = self:GetPrivate("newSpells")
	return type(record) == "table" and type(record.slots) == "table" and next(record.slots) ~= nil or false
end

-- Takes the last placed spells off the buttons that still hold them.
function E:UndoNewSpells()
	if not self:HasNewSpellsUndo() then
		self:Print(L["There are no new spells to take off your bars."])
		return 0
	end
	if InCombatLockdown() then
		self:Print(L["Spells can't move onto your bars in combat."])
		return 0
	end
	local clear = self.PremadeSlots and self.PremadeSlots.Clear
	if not clear then return 0 end
	local record = self:GetPrivate("newSpells")
	local spells = self:GetPrivate("keybindSpells")
	local count = 0
	for slot, spellID in pairs(record.slots) do
		if clear(slot, spellID) then count = count + 1 end
		if type(spells) == "table" and type(spells.slots) == "table" and spells.slots[slot] == spellID then spells.slots[slot] = nil end
	end
	if type(spells) == "table" and type(spells.slots) == "table" and not next(spells.slots) then
		spells.class, spells.slots, spells.time = nil, nil, nil
	end
	record.slots, record.time = nil, nil
	self:Print(E:Plural(count, "%d new spell taken off your bars.", "%d new spells taken off your bars."):format(count))
	if self.KeybindPreviewChanged then self:KeybindPreviewChanged() end
	return count
end

---------------------------------------------------------------------------
-- Noticing new spells
---------------------------------------------------------------------------
-- What the player knew at the last look, and the form page buttons that
-- waited for a form then. nil until the first look after login.
local knownBefore, waitingBefore

local function WaitingForms()
	local waiting = {}
	if not E.KeybindSpellPlan then return waiting end
	for _, entry in ipairs(PlanEntries(E:KeybindSpellPlan())) do
		if entry.status == "noform" then waiting[ButtonKey(entry)] = true end
	end
	return waiting
end

local function Snapshot()
	knownBefore, waitingBefore = KnownNames(), WaitingForms()
end

-- The offer: one notice for every new spell with a button.
local function Offer(plan)
	local lines, kept = {}, {}
	for _, entry in ipairs(plan.entries) do
		if entry.status == "place" then
			lines[#lines + 1] = (entry.back and L["%s back on %s"] or L["%s on %s"]):format(entry.name, E:NewSpellSlotWords(entry.slot))
		elseif entry.status == "kept" then
			kept[#kept + 1] = entry.name
		end
	end
	if #lines == 0 then return end
	local text = L["New spells have a button waiting: %s."]:format(table.concat(lines, ", "))
	if #kept > 0 then
		text = text .. " " .. L["Your own actions stay where they are: %s."]:format(table.concat(kept, ", "))
	end
	E:PushAlert({
		key = "keybind-new-spells",
		options = { page = "module:ActionBars" },
		title = L["New spells"],
		text = text,
		actions = {
			{ label = L["Put them there"], tip = L["Places these spells on their empty buttons now (out of combat). /eui spells undo takes them off again."],
				func = function()
					E:RunOutOfCombat(function()
						local fresh = E:NewSpellPlan(plan.names, plan.forms)
						local count, why = E:PlaceNewSpells(fresh)
						if count == 0 and why == "cursor" then E:Print(L["Put down what is on your cursor first."]) end
					end, "KeybindNewSpells:offer")
				end },
			{ label = L["Not now"] },
		},
	})
end

-- After a learn: the spells that are new since the last look.
function E:CheckNewSpells()
	local mode = self:NewSpellsMode()
	if not knownBefore then
		Snapshot()
		return 0
	end
	local now, names, any = KnownNames(), {}, false
	for name, spellID in pairs(now) do
		if not knownBefore[name] then
			names[name] = spellID
			any = true
		end
	end
	local waiting, forms = WaitingForms(), {}
	for key in pairs(waitingBefore or {}) do
		if not waiting[key] then
			forms[key] = true
			any = true
		end
	end
	if not any then
		knownBefore, waitingBefore = now, waiting
		return 0
	end
	-- Fill bars 4 and 5 (Core/KeybindQuietBars.lua) takes new spells
	-- with a home for outside a fight, whatever this mode is.
	local quiet = next(names) ~= nil and self.QuietFillOn and self:QuietFillOn()
	if mode == "off" and not quiet then
		knownBefore, waitingBefore = now, waiting
		return 0
	end
	if (mode == "auto" or quiet) and GetCursorInfo and GetCursorInfo() then
		-- Wait for the cursor: the new spells stay new until then.
		E:Debounce("keybind:newspells:cursor", 2, function()
			E:RunOutOfCombat(function() E:CheckNewSpells() end, "KeybindNewSpells:check")
		end)
		return 0
	end
	knownBefore, waitingBefore = now, waiting
	local count = 0
	if mode ~= "off" then
		local plan = self:NewSpellPlan(names, forms)
		plan.names, plan.forms = names, forms
		if mode == "auto" then
			count = self:PlaceNewSpells(plan)
		else
			Offer(plan)
		end
	end
	if quiet then count = count + self:QuietBarsLearned(names) end
	return count
end

-- A trainer teaches several spells at once, and the rank upgrade acts
-- first: wait a little longer than it does, then look once, out of combat.
-- In combat the look waits in the out-of-combat queue right away, once.
local function Check() E:CheckNewSpells() end
local function Changed()
	if InCombatLockdown() then
		E:RunOutOfCombat(Check, "KeybindNewSpells:check")
		return
	end
	E:Debounce("keybind:newspells", 1.5, function()
		E:RunOutOfCombat(Check, "KeybindNewSpells:check")
	end)
end

local owner = {}
E:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE", Changed, owner)
E:RegisterEvent("SPELLS_CHANGED", Changed, owner)
-- The game asks the player to confirm a talent reset: save the buttons
-- now, while the talent spells are still on them.
E:RegisterEvent("CONFIRM_TALENT_WIPE", function() E:SaveTalentResetSlots() end, owner)
E:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, _, isLogin, isReload)
	if not (isLogin or isReload) then return end
	-- What the player knows at login is the starting point: only spells
	-- learned from here on are new.
	knownBefore, waitingBefore = nil, nil
	appliedMode = E:NewSpellsMode()
	if C_Timer then
		C_Timer.After(2, function()
			Snapshot()
			E:ApplyNewSpellsCVar()
		end)
	end
end, owner)

E:AddCommand("spells", "  open the keys and spells preview; undo takes the last new spells EldoUI placed off your bars again", function(args)
	if type(args) == "string" and strtrim(args):lower() == "undo" then
		E:RunOutOfCombat(function() E:UndoNewSpells() end, "KeybindNewSpells:undo")
		return
	end
	if E.OpenKeysAndSpells then E:OpenKeysAndSpells() end
end, "Tools")
