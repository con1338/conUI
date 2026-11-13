-- EldoUI key map: the player's choice of keys and spells, kept with the
-- profile, so it follows the player to every layout, pack, style preset,
-- profile copy, import string and character.
--
--   E.db.keymap           the choice (profile): which key set, class
--                         spells on empty buttons, what happens with
--                         spells learned later and on other characters,
--                         keys shown on bars 1 to 3, the quiet bar filled
--                         with spare spells. A key set of "none"
--                         means "I manage my own keys": EldoUI then never
--                         writes a key. The keyboard is the account's
--                         (E.global.keymap); the defaults of both are in
--                         Core/Database.lua.
--   E:KeymapSetting(name) one value of the choice, with its default
--   E:KeymapManaged()     false while the player manages their own keys
--   E:KeymapPlan([id])    the key set's plan (Core/KeybindPresets.lua)
--                         without the keys the player set by hand
--   E:KeymapCheck(reason) compares this character's keys with the choice
--                         and offers to put the set on, once
--   E:KeymapIssues()      what keeps a key set from working well: a bar
--                         that pages on a key set's modifier, key text
--                         hidden on bars 1 to 3
--
-- Layouts, packs, style presets and roles never write a key: keys follow
-- the button number, so a layout switch keeps every key. A character
-- whose keys differ from the choice (a new character, keys the game
-- reset) gets one offer with a preview; only "automatic" in the choice
-- puts them on by itself, out of combat, with a backup and Undo. A key the
-- player set by hand after a key set was applied stays theirs: no check,
-- offer or automatic step ever writes over it. Written from scratch for
-- EldoUI.
local _, E = ...
local L = E.L
local Key = E.Key

-- Read when a profile has no record yet (an older profile, a plugin
-- reading early): the same values the profile defaults give.
local FALLBACK = {
	version = 1, preset = "", spells = true, newSpells = "offer", alts = "offer", showKeys = false, quietFill = false,
}

-- Per character: applied (what the last key set Apply wrote here: key set,
-- version and every key it holds), overrides (keys changed by hand since:
-- key -> what the key set wanted there), never (no offers on this
-- character), declined (the key set an Undo took back here; no offer for
-- it again until the choice changes).

local MODES = { offer = true, auto = true, off = true }
E.keymapModes = { "offer", "auto", "off" }
E.keymapModeText = {
	offer = Key("Ask me"), auto = Key("Automatic"), off = Key("Off"),
}
local ALERT = "keymap-sync"
local ISSUES_ALERT = "keymap-issues"
local ROLE_ALERT = "keymap-role"
-- GetCurrentBindingSet: 1 keys for the whole account, 2 for this character.
local ACCOUNT_SET = 1

-- "Not now" on the offer: no offer again until the next login or a new
-- choice.
local notNow = false

local function Plain(value)
	if E.Secret and E.Secret(value) then return nil end
	return value
end

---------------------------------------------------------------------------
-- The choice (profile)
---------------------------------------------------------------------------
function E:KeymapRecord()
	local db = self.db
	if type(db) ~= "table" then return nil end
	if type(db.keymap) ~= "table" then db.keymap = {} end
	return db.keymap
end

function E:KeymapSetting(name)
	local record = self:KeymapRecord()
	local value = record and record[name]
	if value == nil then value = FALLBACK[name] end
	if (name == "newSpells" or name == "alts") and not MODES[value] then value = "offer" end
	return value
end

function E:KeymapManaged()
	return self:KeymapSetting("preset") ~= "none"
end

-- The key set of the choice, or nil (none chosen yet, or managed by the
-- player).
function E:KeymapPreset()
	local preset = self:KeymapSetting("preset")
	if type(preset) ~= "string" or preset == "" or preset == "none" then return nil end
	return self:KeybindPresetKey(preset)
end

-- Writes answers into the choice. Unknown modes are left out.
function E:SetKeymap(fields)
	local record = self:KeymapRecord()
	if not (record and type(fields) == "table") then return end
	notNow = false
	for key, value in pairs(fields) do
		if key == "newSpells" or key == "alts" then
			if MODES[value] then record[key] = value end
		elseif key == "preset" then
			if value == "none" or value == "" or self:KeybindPresetKey(value) then
				record.preset = value == "none" and "none" or (value == "" and "" or self:KeybindPresetKey(value))
			end
		elseif key == "spells" or key == "showKeys" or key == "quietFill" then
			record[key] = value and true or false
		elseif key == "keyboard" and type(value) == "string" then
			local global = self.global and self.global.keymap
			if type(global) == "table" then
				local chosen = (self.keyboardLayouts and self.keyboardLayouts[value]) and value or ""
				-- Another keyboard: the names Check my keyboard found no longer apply.
				if chosen ~= global.keyboard then global.checked = false end
				global.keyboard = chosen
			end
		end
	end
	local module = self.modules and self.modules.ActionBars
	if fields.showKeys ~= nil and module then self:RefreshModule(module, true) end
end

---------------------------------------------------------------------------
-- This character's record
---------------------------------------------------------------------------
local function Char()
	local private = E.private
	if type(private) ~= "table" then return { overrides = {} } end
	if type(private.keymap) ~= "table" then private.keymap = {} end
	local record = private.keymap
	record.overrides = type(record.overrides) == "table" and record.overrides or {}
	return record
end
E.KeymapCharacter = function() return Char() end

local function ActionOf(key)
	return E:KeybindActionOf(key)
end

local function Tag(id, version)
	return tostring(id) .. "@" .. tostring(version)
end

-- Keys the player set by hand since the last Apply of this key set: the
-- key held what the set put there and now holds something else. An
-- empty key is a lost key, not the player's. When most of the set's keys
-- changed at once, the game reset them (new binding set, keys set back to
-- the game's defaults): nothing is learned, and the offer puts them back.
local RESET_SHARE = 0.25

local function LearnOverrides(char, id)
	local applied = char.applied
	if not (applied and applied.preset == id and type(applied.keys) == "table") then return 0 end
	local total, changed = 0, {}
	for key, command in pairs(applied.keys) do
		total = total + 1
		local now = ActionOf(key)
		if now ~= command and char.overrides[key] == nil then changed[#changed + 1] = { key = key, command = command, now = now } end
	end
	if #changed > math.max(3, total * RESET_SHARE) then return 0 end
	local learned = 0
	for _, entry in ipairs(changed) do
		if entry.now ~= "" then
			char.overrides[entry.key] = entry.command
			learned = learned + 1
		end
	end
	return learned
end

-- What a plan put on this character, after an Apply.
local function Remember(plan)
	local char = Char()
	local keys = {}
	for _, list in ipairs({ plan.slots or {}, plan.moves or {} }) do
		for _, entry in ipairs(list) do
			if entry.key and entry.command and ActionOf(entry.key) == entry.command then keys[entry.key] = entry.command end
		end
	end
	if not next(keys) then return end
	local applied = char.applied
	-- The key set's own Apply may have written the record already.
	if not (applied and applied.signature == plan.signature and applied.keys) then
		char.applied = { preset = plan.id, version = plan.version, signature = plan.signature, keys = keys, time = time() }
	end
	-- A key the set holds again is not the player's own any more.
	for key in pairs(char.overrides) do
		if keys[key] then char.overrides[key] = nil end
	end
	char.declined = nil
end

---------------------------------------------------------------------------
-- The plan without the player's own keys
---------------------------------------------------------------------------
-- Drops the writes of keys the player set by hand from a key plan, and
-- the new key of a game shortcut that only moved because the set wanted
-- one of those keys. The plan's signature stays as it was, so Apply still
-- checks the keys shown.
function E:KeymapFilterPlan(plan)
	if not plan then return plan end
	local overrides = Char().overrides
	if not next(overrides) then return plan end
	local moved = {}
	for _, entry in ipairs(plan.homes or {}) do
		if entry.state == "bind" and entry.key and entry.from and overrides[entry.from] then
			moved[entry.key] = entry.command
			entry.state = "own"
		end
	end
	local writes, kept = {}, {}
	for _, write in ipairs(plan.writes) do
		if overrides[write.key] or moved[write.key] == write.command then kept[#kept + 1] = write else writes[#writes + 1] = write end
	end
	local displaced = {}
	for _, entry in ipairs(plan.displaced or {}) do
		if not overrides[entry.key] then displaced[#displaced + 1] = entry end
	end
	plan.displaced = displaced
	if #kept == 0 then return plan end
	plan.writes, plan.own = writes, kept
	for _, entry in ipairs(plan.slots) do
		if entry.state == "bind" and overrides[entry.key] then
			entry.state = "own"
			plan.counts.bind = (plan.counts.bind or 0) - 1
			plan.counts.own = (plan.counts.own or 0) + 1
		end
	end
	for _, entry in ipairs(plan.moves) do
		if entry.state == "bind" and overrides[entry.key] then entry.state = "own" end
	end
	return plan
end

function E:KeymapPlan(id)
	id = id or self:KeymapPreset()
	local plan = id and self:KeybindPlan(id)
	return plan and self:KeymapFilterPlan(plan) or nil
end

-- A keys and spells plan (Core/KeybindPreview.lua) for the choice: the
-- player's own keys are left out, and with "I manage my own keys" no key
-- at all, while spells, macros and ranks stay.
function E:KeymapKeysAndSpells(plan, own)
	if not (plan and plan.keys) then return plan end
	if own then
		plan.keys.own = plan.keys.writes
		plan.keys.writes = {}
	else
		self:KeymapFilterPlan(plan.keys)
	end
	local c = plan.counts
	c.keys = #plan.keys.writes
	c.total = c.keys + c.spells + c.premade + c.macros + c.ranks
	return plan
end

---------------------------------------------------------------------------
-- What keeps a key set from working well
---------------------------------------------------------------------------
local MOD_OF = { pageShift = "SHIFT", pageCtrl = "CTRL", pageAlt = "ALT" }
local MOD_TEXT = { SHIFT = Key("Shift"), CTRL = Key("Ctrl"), ALT = Key("Alt") }

-- The modifiers the key set's bars use (Shift for bar 2, Ctrl for bar 3).
local function SetModifiers(id)
	local used = {}
	local preset = id and E.keybindPresets[id]
	if not preset then return used end
	for _, bar in ipairs(E.keybindManagedBars) do
		for button = 1, 12 do
			local key = E:KeybindSlotKey(preset, bar, button)
			for mod in pairs(MOD_TEXT) do
				if type(key) == "string" and key:find(mod .. "-", 1, true) then used[mod] = true end
			end
		end
	end
	return used
end

-- Returns a list: { kind = "paging", bar, field, mod } for a bar of 1 to 3
-- that shows another bar while a modifier the key set uses is held, and
-- { kind = "keytext", bars } when bars 1 to 3 hide their keys.
function E:KeymapIssues(id)
	local list = {}
	local module = self.modules and self.modules.ActionBars
	if not (module and module.active and module.db and module.db.bars) then return list end
	id = id or self:KeymapPreset()
	local used = SetModifiers(id)
	for _, bar in ipairs(self.keybindManagedBars) do
		local db = module.db.bars[bar]
		if db then
			for field, mod in pairs(MOD_OF) do
				if used[mod] and (tonumber(db[field]) or 0) > 0 then
					list[#list + 1] = { kind = "paging", bar = bar, field = field, mod = mod }
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.bar == b.bar and a.field < b.field or a.bar < b.bar end)
	if not self:KeymapSetting("showKeys") then
		local hidden = self:KeymapStyleHidesKeys()
		if hidden then list[#list + 1] = { kind = "keytext", bars = hidden } end
	end
	return list
end

-- The bars of 1 to 3 whose text style hides the keys (whatever the key
-- map's "show keys" says), or nil.
function E:KeymapStyleHidesKeys()
	local module = self.modules and self.modules.ActionBars
	if not (module and module.active and module.BarText and module.db and module.db.bars) then return nil end
	local hidden = {}
	for _, bar in ipairs(self.keybindManagedBars) do
		local db = module.db.bars[bar]
		if db and db.enabled and not module:BarText(db, true).showHotkey then hidden[#hidden + 1] = bar end
	end
	return #hidden > 0 and hidden or nil
end

function E:KeymapIssueText(issue)
	if issue.kind == "paging" then
		return L["Bar %d shows another bar while %s is held, and %s is part of your keys there."]:format(issue.bar, -- no-plural: a bar number
			L[MOD_TEXT[issue.mod]], L[MOD_TEXT[issue.mod]])
	end
	return L["Bars 1 to 3 hide their keys, so you can't see the keys you just set."]
end

-- Fixes the listed issues, out of combat: paging off on those bars, keys
-- shown on bars 1 to 3.
function E:FixKeymapIssues(list)
	local module = self.modules and self.modules.ActionBars
	if not (module and module.db and type(list) == "table") then return end
	self:RunOutOfCombat(function()
		for _, issue in ipairs(list) do
			if issue.kind == "paging" and module.db.bars[issue.bar] then
				module.db.bars[issue.bar][issue.field] = 0
			elseif issue.kind == "keytext" then
				self:KeymapRecord().showKeys = true
			end
		end
		self:RefreshModule(module)
	end, "Keymap:fix")
end

local function OfferIssues(id)
	local list = E:KeymapIssues(id)
	if #list == 0 then return end
	local lines = {}
	for _, issue in ipairs(list) do lines[#lines + 1] = "- " .. E:KeymapIssueText(issue) end
	E:PushAlert({
		key = ISSUES_ALERT, title = L["Keys and spells"], options = { page = "keybinds" },
		text = L["Two things get in the way of your keys:"] .. "\n" .. table.concat(lines, "\n"),
		actions = {
			{ label = L["Fix it"], tip = L["Turns the paging off on those bars and shows the keys on bars 1 to 3. Both can be changed back on the Action Bars page."],
				func = function() E:FixKeymapIssues(list) end },
			{ label = L["Leave it"] },
		},
	})
end

---------------------------------------------------------------------------
-- After every key set Apply and Undo
---------------------------------------------------------------------------
-- The choice follows the key set the player applied anywhere (the
-- preview, the Keybinds page, the setup), so other characters and other
-- layouts know it.
E:OnKeymapChange(function(kind, data)
	if not E.db then return end
	local char = Char()
	if kind == "applied" then
		local plan = data
		if not (plan and plan.id) then return end
		Remember(plan)
		E:DismissAlert(ALERT)
		C_Timer.After(0.5, function() OfferIssues(plan.id) end)
	elseif kind == "restored" then
		-- Undo put the keys and the record of before back; the set the
		-- player undid is not offered again on this character until it changes.
		if data and data.template then char.declined = Tag(E:KeybindPresetKey(data.template) or data.template, data.version) end
	end
end)

---------------------------------------------------------------------------
-- The check: a character whose keys differ from the choice
---------------------------------------------------------------------------
local function Installed()
	return type(EldoUIDB) == "table" and type(EldoUIDB.installed) == "table" and EldoUIDB.installed[E.charKey] ~= nil
end

local function SetupOpen()
	local installer = E.Installer
	local window = installer and installer.GetWindow and installer.GetWindow()
	return window and window:IsShown() or false
end

local function BindingSet()
	if type(GetCurrentBindingSet) ~= "function" then return nil end
	local ok, set = pcall(GetCurrentBindingSet)
	return ok and Plain(set) or nil
end

-- "these keys are saved for all your characters" or "for this character".
function E:KeymapBindingSetText()
	if BindingSet() == ACCOUNT_SET then return L["Your keys are saved for all your characters."] end
	return L["Your keys are saved for this character only."]
end

local function ApplyAuto(plan)
	E:RunOutOfCombat(function()
		local fresh = E:KeymapPlan(plan.id)
		if not fresh or #fresh.writes == 0 then return end
		local ok = E:ApplyKeybindPlan(fresh, nil, { quiet = true })
		if not ok then return end
		local title = E:Highlight(L[fresh.title])
		E:Print(L["%s keys set for this character (%d)."]:format(title, #fresh.writes))
		E:PushAlert({
			key = ALERT, title = L["Keys and spells"], options = { page = "keybinds" },
			text = L["Your profile uses %s, so this character got its keys: %s. Keys you set yourself stayed."]:format(title,
				E:Plural(#fresh.writes, "%d key", "%d keys"):format(#fresh.writes)),
			actions = {
				{ label = L["Undo"], tip = L["Put back the keys this character had before."],
					func = function() E:RunOutOfCombat(function() E:RestoreKeybinds(false) end, "Keymap:undo") end },
				{ label = L["Keep"] },
			},
		})
	end, "Keymap:auto")
end

local function Offer(plan)
	local title = E:Highlight(L[plan.title])
	local count = #plan.writes
	E:PushAlert({
		key = ALERT, title = L["Keys and spells"], options = { page = "keybinds" },
		text = L["Your profile uses %s, and %s on this character differ from it. Look at the keys before anything changes."]:format(title,
			E:Plural(count, "%d key", "%d keys"):format(count)),
		actions = {
			{ label = L["Preview"], tip = L["Shows every key first; nothing changes until you press Apply there."],
				func = function()
					if E.OpenKeysAndSpells then
						E:OpenKeysAndSpells(nil, { id = plan.id, spells = E:KeymapSetting("spells") })
					else
						E:OpenKeybindPreview(plan.id)
					end
				end },
			{ label = L["Not now"], tip = L["Asks again at your next login."], func = function() notNow = true end },
			{ label = L["Never on this character"], tip = L["No more offers about keys on this character. The Keybinds page still applies a key set."],
				func = function() Char().never = true end },
		},
	})
end

local function OfferOwnKeys(id, count)
	local title = E:Highlight(L[E.keybindPresets[id].title])
	E:PushAlert({
		key = ALERT, title = L["Keys and spells"], options = { page = "keybinds" },
		text = L["%s of %s were changed outside EldoUI. They stay yours: EldoUI never writes over a key you set."]:format(
			E:Plural(count, "%d key", "%d keys"):format(count), title),
		actions = {
			{ label = L["Keep mine"] },
			{ label = L["Put the set back"], tip = L["Forgets your own keys for this key set and shows the preview, where Apply puts them back."],
				func = function()
					wipe(Char().overrides)
					E:OpenKeybindPreview(id)
				end },
		},
	})
end

-- reason: "login", "attach" (a character joined a profile), "profile" (a
-- profile switch) or "manual" (the Keybinds page: no answer is skipped).
-- Returns what it found: "off", "own", "match", "never", "declined",
-- "offer", "auto", "learned" or nil (nothing to check yet).
function E:KeymapCheck(reason)
	reason = reason or "manual"
	if not self.db then return nil end
	local result = self:KeymapCompare(reason)
	if reason == "manual" then
		if result == "own" then
			self:Print(L["You manage your own keys: EldoUI leaves them as they are."])
		elseif result == "match" then
			self:Print(L["This character's keys match your key set."])
		elseif result == nil then
			self:Print(L["No key set chosen yet. The Keybinds page and the setup's Keys and spells step offer them."])
		end
	end
	return result
end

function E:KeymapCompare(reason)
	local record = self:KeymapRecord()
	-- A key set applied before this record existed is the choice.
	if record.preset == nil or record.preset == "" then
		local template = self.KeybindBackupTemplate and self:KeybindPresetKey(self:KeybindBackupTemplate())
		if template then record.preset = template end
	end
	if record.preset == "none" then return "own" end
	local id = self:KeymapPreset()
	if not id then return nil end
	if reason ~= "manual" then
		if self:KeymapSetting("alts") == "off" then return "off" end
		if reason == "login" and (not Installed() or SetupOpen()) then return nil end
		if self.GamepadUIActive and self:GamepadUIActive() then return nil end
	end
	local char = Char()
	local learned = LearnOverrides(char, id)
	local plan = self:KeymapPlan(id)
	if not plan then return nil end
	if learned > 0 then
		OfferOwnKeys(id, learned)
		return "learned"
	end
	if #plan.writes == 0 then
		if not (char.applied and char.applied.preset == id) then Remember(plan) end
		return "match"
	end
	if reason ~= "manual" then
		if char.never then return "never" end
		if char.declined == Tag(id, plan.version) then return "declined" end
		if notNow then return nil end
	end
	if self:KeymapSetting("alts") == "auto" and reason ~= "manual" then
		ApplyAuto(plan)
		return "auto"
	end
	Offer(plan)
	return "offer"
end

-- Once per login, after the world shows and out of combat.
local Sync = {}
E:RegisterEvent("PLAYER_LOGIN", function()
	C_Timer.After(6, function()
		E:RunOutOfCombat(function() E:KeymapCheck("login") end, "Keymap:login")
	end)
end, Sync)

hooksecurefunc(E, "SetProfile", function(self)
	if not self.db then return end
	C_Timer.After(1, function()
		E:RunOutOfCombat(function() E:KeymapCheck("profile") end, "Keymap:login")
	end)
end)

---------------------------------------------------------------------------
-- Role change: the class spells of the new role
---------------------------------------------------------------------------
-- Buttons where EldoUI placed a spell of the old role and the new role
-- has another spell for that button. Only those, and empty buttons,
-- change; a button with your own action keeps it.
function E:KeymapRoleSwaps()
	local swaps = {}
	if not (self.KeybindSpellPlan and self.PremadeSlots) then return swaps end
	local record = self:GetPrivate("keybindSpells")
	local placed = type(record) == "table" and type(record.slots) == "table" and record.slots or {}
	local plan = self:KeybindSpellPlan()
	for _, entry in ipairs(plan.entries) do
		local slot = entry.slot
		if entry.status == "kept" and slot and entry.spell and placed[slot] and placed[slot] ~= entry.spell then
			local ok, kind, id = pcall(GetActionInfo, slot)
			if ok and Plain(kind) == "spell" and Plain(id) == placed[slot] and not self.PremadeSlots.OnBars(entry.spell, entry.stance) then
				swaps[#swaps + 1] = { slot = slot, from = placed[slot], to = entry.spell, name = entry.name }
			end
		end
	end
	return swaps
end

-- Takes the old role's spells off their buttons, then places the new
-- role's spells on the empty buttons. Returns how many changed.
function E:ApplyKeymapRole(swaps)
	if InCombatLockdown() then return 0 end
	local slots = self.PremadeSlots
	local record = self:GetPrivate("keybindSpells")
	local undo = {}
	for _, swap in ipairs(swaps or {}) do
		if slots.Clear(swap.slot, swap.from) then
			if type(record.slots) == "table" then record.slots[swap.slot] = nil end
			undo[#undo + 1] = swap
		end
	end
	local plan = self:KeybindSpellPlan()
	local ok, result = self:ApplyKeybindSpells(plan, false)
	local placed = ok and result and result.placed or 0
	return placed, undo
end

local function UndoRole(undo)
	local slots = E.PremadeSlots
	local record = E:GetPrivate("keybindSpells")
	for _, swap in ipairs(undo) do
		slots.Clear(swap.slot, swap.to)
		if slots.Empty(swap.slot) and slots.Place(swap.slot, swap.from) and type(record.slots) == "table" then
			record.slots[swap.slot] = swap.from
		end
	end
end

local function OfferRole(role)
	if not (E.db and E:KeymapSetting("spells")) then return end
	if not (E.KeybindSpellPlan and E.PremadeSlots) then return end
	local swaps = E:KeymapRoleSwaps()
	local plan = E:KeybindSpellPlan()
	local count = #swaps + #plan.places
	if count == 0 then return end
	local name = E.roleProfiles and E.roleProfiles[role] and L[E.roleProfiles[role].title] or role
	E:PushAlert({
		key = ROLE_ALERT, title = L["Keys and spells"], options = { page = "keybinds" },
		text = L["Your role is now %s. %s of this role can go on your bars: on empty buttons, and on buttons where EldoUI put a spell of your old role. Your own actions stay."]:format(
			E:Highlight(name), E:Plural(count, "%d class spell", "%d class spells"):format(count)),
		actions = {
			{ label = L["Place them"], func = function()
				E:RunOutOfCombat(function()
					local placed, undo = E:ApplyKeymapRole(E:KeymapRoleSwaps())
					if placed + #undo == 0 then return end
					E:PushAlert({ key = ROLE_ALERT, title = L["Keys and spells"], options = { page = "keybinds" },
						text = E:Plural(placed, "%d class spell placed for your new role.", "%d class spells placed for your new role."):format(placed),
						actions = {
							{ label = L["Undo"], func = function()
								E:RunOutOfCombat(function()
									E:RevertKeybindSpells(false)
									UndoRole(undo)
								end, "Keymap:roleundo")
							end },
							{ label = L["Keep"] },
						} })
				end, "Keymap:role")
			end },
			{ label = L["Preview"], func = function() if E.OpenKeysAndSpells then E:OpenKeysAndSpells() end end },
			{ label = L["Not now"] },
		},
	})
end

E:RegisterRoleCallback(function(role)
	if not E.db or role == "none" then return end
	C_Timer.After(1, function() OfferRole(role) end)
end)
