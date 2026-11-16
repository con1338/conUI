-- EldoUI Bar Snapshots: save what is on your action bars, your macros, your
-- key bindings and your Edit Mode layout, and put it all back with a few
-- clicks. Snapshots are taken by hand and, if you switch it on, at every
-- login and logout, so a client that resets bars or keys (a known
-- WoW: Forever problem) costs one restore.
-- Snapshots travel as "!EUS1!" strings through EldoUI's import box, with a
-- checksum so a damaged or hand-edited string is refused.
--
-- Nothing changes on its own. A restore opens a preview window that lists
-- every slot it would change and lets the player pick the parts; only its
-- Restore button (a click, out of combat, through E:RunOutOfCombat) places
-- actions, adds macros, sets keys or switches the Edit Mode layout. After a
-- detected reset EldoUI only offers that window (option, default off).
-- Nothing is ever applied on a spec, stance or zone change.
local _, E = ...
local L = E.L

local MAX_SLOTS = 180
local MAX_MANUAL = 20
local MAX_NAME = 40
local MAX_LAYOUT_TEXT = 64 * 1024

local M = E:NewModule("Snapshots", {
	title = "Bar Snapshots",
	category = "Quality of Life",
	desc = "Save your action bars, macros, key bindings and Edit Mode layout, preview what a restore changes, and put them back with one click.",
	frames = { "EldoUISnapshotRestore" },
	savedKeys = { "profile.modules.Snapshots", "global.BarSnapshots" },
	optionsPage = "module:Snapshots",
	presets = { "Standard", "SafetyNet", "Careful", "BarsOnly", "KeysOnly", "LayoutOnly" },
	reload = false,
	defaults = {
		auto = false,          -- snapshot at login and logout when something changed
		keepAuto = 5,
		offerRestore = false,  -- offer a restore when bars, keys or the layout look reset
		restoreActions = true,
		restoreMacros = true,  -- add missing macros (never changes or deletes existing ones)
		restoreBindings = true,
		restoreEditMode = true,
		clearEmpty = true,     -- slots empty in the snapshot are emptied too
		selected = "1",
		source = "",           -- "" = this character; else another character's key
	},
})

---------------------------------------------------------------------------
-- Storage: account-wide, one list per character (newest first)
---------------------------------------------------------------------------
-- A character whose data moves to its full-name key takes its snapshot
-- list along, and a profile that showed its snapshots keeps showing them.
E:RegisterCharacterKeyMove(function(db, oldKey, newKey)
	local global = type(db.global) == "table" and db.global.BarSnapshots
	E.MoveCharacterEntry(type(global) == "table" and global.chars, oldKey, newKey)
	for _, settings in ipairs(E.EachProfileModule(db, "Snapshots")) do
		if settings.source == oldKey then settings.source = newKey end
	end
end)

-- Forget takes the character's snapshot list; a profile that showed it
-- goes back to this character's own.
E:RegisterCharacterForget(function(db, key)
	local global = type(db.global) == "table" and db.global.BarSnapshots
	if type(global) == "table" and type(global.chars) == "table" then global.chars[key] = nil end
	for _, settings in ipairs(E.EachProfileModule(db, "Snapshots")) do
		if settings.source == key then settings.source = nil end
	end
end)

local function Store()
	local global = E:GetGlobal("BarSnapshots") or { chars = {} }
	global.chars = global.chars or {}
	return global
end

function M:List(charKey)
	local store = Store()
	charKey = charKey or E.charKey or "?"
	store.chars[charKey] = store.chars[charKey] or {}
	return store.chars[charKey]
end

-- The character whose snapshots the options page shows.
function M:SourceKey()
	local source = self.db and self.db.source
	if type(source) == "string" and source ~= "" and source ~= E.charKey then return source end
	return E.charKey or "?"
end

local Clean = E.Plain

---------------------------------------------------------------------------
-- Reading the current state
---------------------------------------------------------------------------
-- Account and character macro slots (Constants.MacroConsts on this client).
local function MacroLimits()
	local c = rawget(_G, "Constants") and Constants.MacroConsts
	return (c and c.MAX_ACCOUNT_MACROS) or rawget(_G, "MAX_ACCOUNT_MACROS") or 120,
		(c and c.MAX_CHARACTER_MACROS) or rawget(_G, "MAX_CHARACTER_MACROS") or 18
end

local function MacroName(index)
	local name = Clean(GetMacroInfo(index))
	return type(name) == "string" and name or nil
end

-- The macro on an action slot, by name. GetActionInfo gives a macro slot's
-- spell or item id (subType "spell" / "item") on this client, not the macro
-- index, so the name comes from the slot's text; the index is used only
-- when the id really is one (no subType). C_ActionBar first: the old global
-- name exists only while the game loads its deprecation fallbacks.
local function ActionText(slot)
	local api = C_ActionBar and C_ActionBar.GetActionText or GetActionText
	if type(api) ~= "function" then return nil end
	return api(slot)
end

local function SlotMacroName(slot, id, subType)
	local text = Clean(ActionText(slot))
	if type(text) == "string" and text ~= "" then return text end
	if (subType == nil or subType == "" or subType == "macro") and type(id) == "number" then return MacroName(id) end
	return nil
end

-- What is on one slot now, in the snapshot's { kind, id, extra } form.
local function ReadSlot(slot)
	local kind, id, subType = GetActionInfo(slot)
	kind, id, subType = Clean(kind), Clean(id), Clean(subType)
	if not (kind and id) then return nil end
	local entry = { kind, id }
	if kind == "macro" then
		entry[3] = SlotMacroName(slot, id, subType)
	elseif kind == "equipmentset" then
		entry[3] = id -- the set's name
	elseif subType and subType ~= "" then
		entry[3] = subType
	end
	return entry
end

local function ReadActions()
	local actions, count = {}, 0
	if not GetActionInfo then return actions, 0 end
	for slot = 1, MAX_SLOTS do
		local entry = ReadSlot(slot)
		if entry then
			actions[slot] = entry
			count = count + 1
		end
	end
	return actions, count
end

local function ReadMacros()
	local macros = {}
	if not (GetNumMacros and GetMacroInfo) then return macros end
	local account, perChar = GetNumMacros()
	local accountMax = MacroLimits()
	local function Add(index, char)
		local name, icon, body = GetMacroInfo(index)
		name, icon, body = Clean(name), Clean(icon), Clean(body)
		if type(name) == "string" and type(body) == "string" then
			macros[#macros + 1] = { name = name, icon = icon, body = body, char = char or nil }
		end
	end
	for i = 1, account or 0 do Add(i, false) end
	for i = accountMax + 1, accountMax + (perChar or 0) do Add(i, true) end
	return macros
end

local function ReadBindings()
	local bindings = {}
	if not (GetNumBindings and GetBinding) then return bindings end
	for i = 1, GetNumBindings() do
		local command, _, key1, key2 = GetBinding(i)
		if type(command) == "string" and key1 then bindings[#bindings + 1] = { command, key1, key2 } end
	end
	return bindings
end

-- key -> command for a list of { command, key1, key2 }.
local function BindingMap(bindings)
	local map = {}
	for _, b in ipairs(bindings or {}) do
		if b[2] then map[b[2]] = b[1] end
		if b[3] then map[b[3]] = b[1] end
	end
	return map
end

---------------------------------------------------------------------------
-- Edit Mode (C_EditMode only; EditModeManagerFrame is never written)
---------------------------------------------------------------------------
local function NumPresetLayouts()
	return Enum and Enum.EditModePresetLayoutsMeta and Enum.EditModePresetLayoutsMeta.NumValues or 2
end

-- Every layout with its index in Edit Mode's numbering (presets first),
-- and the active index. Nil when the client has no Edit Mode layouts.
local function EditModeLayouts()
	if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.ConvertLayoutInfoToString) then return nil end
	local ok, data = pcall(C_EditMode.GetLayouts)
	if not ok or type(data) ~= "table" or type(data.layouts) ~= "table" then return nil end
	local all, presets = {}, NumPresetLayouts()
	local manager = rawget(_G, "EditModePresetLayoutManager")
	if manager and manager.GetCopyOfPresetLayouts then
		local okPresets, list = pcall(manager.GetCopyOfPresetLayouts, manager)
		if okPresets and type(list) == "table" then
			for i = 1, presets do
				if type(list[i]) == "table" then all[#all + 1] = { index = i, info = list[i], preset = true } end
			end
		end
	end
	for i, info in ipairs(data.layouts) do
		if type(info) == "table" then all[#all + 1] = { index = presets + i, info = info } end
	end
	return all, data.activeLayout
end

local function LayoutText(info)
	local ok, text = pcall(C_EditMode.ConvertLayoutInfoToString, info)
	if ok and type(text) == "string" then return text end
end

local function ReadEditMode()
	local all, active = EditModeLayouts()
	if not all then return nil end
	for _, layout in ipairs(all) do
		if layout.index == active then
			local text = LayoutText(layout.info)
			local name = layout.info.layoutName
			if text then
				return { name = type(name) == "string" and name or "?", text = text, preset = layout.preset or nil }
			end
		end
	end
end

---------------------------------------------------------------------------
-- Snapshots
---------------------------------------------------------------------------
-- A short fingerprint, so an automatic snapshot is only kept when
-- something changed.
local function Signature(snapshot)
	local parts = {}
	for slot = 1, MAX_SLOTS do
		local a = snapshot.actions[slot]
		if a then parts[#parts + 1] = slot .. ":" .. tostring(a[1]) .. ":" .. tostring(a[2]) end
	end
	for _, b in ipairs(snapshot.bindings) do parts[#parts + 1] = table.concat(b, "=") end
	for _, m in ipairs(snapshot.macros) do parts[#parts + 1] = m.name .. #m.body end
	local layout = snapshot.editMode
	if layout then parts[#parts + 1] = tostring(layout.name) .. #layout.text end
	return table.concat(parts, ";")
end

function M:Capture(label, auto)
	local actions, count = ReadActions()
	local _, class = UnitClass("player")
	local snapshot = {
		time = time(), label = label, auto = auto or nil, class = class, count = count,
		actions = actions, macros = ReadMacros(), bindings = ReadBindings(),
		bindingSet = GetCurrentBindingSet and GetCurrentBindingSet() or 1,
		editMode = ReadEditMode(),
	}
	snapshot.sig = Signature(snapshot)
	return snapshot
end

-- Take a snapshot and keep it. Automatic ones are kept only when they
-- differ from the newest snapshot, and only the newest keepAuto of them.
function M:Take(label, auto)
	local snapshot = self:Capture(label, auto)
	local list = self:List()
	if auto then
		if list[1] and list[1].sig == snapshot.sig then return nil end
		if snapshot.count == 0 then return nil end
	end
	table.insert(list, 1, snapshot)
	local autoSeen, manualSeen = 0, 0
	for i = #list, 1, -1 do
		local s = list[i]
		if s.auto then autoSeen = autoSeen + 1 else manualSeen = manualSeen + 1 end
	end
	for i = #list, 1, -1 do
		local s = list[i]
		if s.auto and autoSeen > self.db.keepAuto then
			table.remove(list, i)
			autoSeen = autoSeen - 1
		elseif not s.auto and manualSeen > MAX_MANUAL then
			table.remove(list, i)
			manualSeen = manualSeen - 1
		end
	end
	if not auto then
		E:Print((L["Snapshot saved: %d actions, %d macros, %d key bindings."]):format(snapshot.count, #snapshot.macros, #snapshot.bindings))
	end
	return snapshot
end

-- Give a snapshot a name (an empty name goes back to the automatic one).
function M:Rename(snapshot, name)
	if type(snapshot) ~= "table" then return false end
	name = strtrim(tostring(name or "")):gsub("[|\n\r]", "")
	name = E:Utf8Sub(name, MAX_NAME)
	snapshot.label = name ~= "" and name or nil
	return true
end

function M:Describe(snapshot)
	local when = snapshot.time and E:ShortDate(snapshot.time) or "?"
	local kind = snapshot.label or (snapshot.auto and L["automatic"] or L["manual"])
	return (L["%s · %s · %d actions, %d macros, %d keys"]):format(when, kind, snapshot.count or 0, #(snapshot.macros or {}), #(snapshot.bindings or {}))
end

---------------------------------------------------------------------------
-- What a restore would change (read only; the preview and the reset check)
---------------------------------------------------------------------------
local function SameEntry(now, entry)
	if not entry then return now == nil end
	if not now or now[1] ~= entry[1] then return false end
	if now[1] == "macro" then return now[3] == entry[3] end
	return now[2] == entry[2]
end

local function CurrentMatches(slot, entry)
	return SameEntry(ReadSlot(slot), entry)
end

local function MacroIndex(name)
	if not (GetMacroIndexByName and type(name) == "string") then return 0 end
	local index = Clean(GetMacroIndexByName(name))
	return type(index) == "number" and index or 0
end

local function SnapshotMacro(snapshot, name)
	for _, m in ipairs(snapshot.macros or {}) do
		if m.name == name then return m end
	end
end

-- Name and icon of an action for the preview. Read only.
function M:EntryInfo(entry, snapshot)
	local kind, id, extra = entry[1], entry[2], entry[3]
	local name, icon
	local function Try(fn, ...)
		if not fn then return nil end
		local ok, a, b, c = pcall(fn, ...)
		if ok then return Clean(a), Clean(b), Clean(c) end
	end
	if kind == "spell" and C_Spell then
		name = Try(C_Spell.GetSpellName, id)
		icon = Try(C_Spell.GetSpellTexture, id)
	elseif kind == "item" and C_Item then
		name = Try(C_Item.GetItemNameByID, id)
		icon = Try(C_Item.GetItemIconByID, id)
	elseif kind == "macro" then
		name = extra
		local m = snapshot and SnapshotMacro(snapshot, extra)
		if m then
			icon = m.icon
		elseif MacroIndex(extra) > 0 then
			local _
			_, icon = Try(GetMacroInfo, MacroIndex(extra))
		end
	elseif kind == "summonmount" and C_MountJournal then
		local mountName, _, mountIcon = Try(C_MountJournal.GetMountInfoByID, id)
		name, icon = mountName, mountIcon
	elseif kind == "equipmentset" then
		name = extra or id
	end
	if type(name) ~= "string" or name == "" then name = ("%s %s"):format(tostring(kind), tostring(id)) end
	if type(icon) ~= "number" and type(icon) ~= "string" then icon = 134400 end -- question mark
	return name, icon
end

-- Can this character put the action back? False only when we know it
-- can't (an unknown spell, a macro that won't exist, a kind we can't pick up).
local function Placeable(entry, snapshot, withMacros)
	local kind = entry[1]
	if kind == "spell" then
		local check = C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook
		if not check then return true end
		local ok, known = pcall(check, entry[2])
		return not ok or known ~= false
	elseif kind == "macro" then
		return MacroIndex(entry[3]) > 0 or (withMacros and SnapshotMacro(snapshot, entry[3]) ~= nil) or false
	end
	return kind == "item" or kind == "summonmount" or kind == "equipmentset"
end

-- A free layout name for an Edit Mode layout added from a snapshot.
local function FreeLayoutName(all, wanted, when)
	local taken = {}
	for _, layout in ipairs(all) do
		if type(layout.info.layoutName) == "string" then taken[layout.info.layoutName] = true end
	end
	if type(wanted) == "string" and wanted ~= "" and not taken[wanted] then return wanted end
	local base = (L["Snapshot %s"]):format(E:ShortDate(when or time()))
	local name, n = base, 1
	while taken[name] do
		n = n + 1
		name = base .. " " .. n
	end
	return name
end

-- What restoring the snapshot's Edit Mode layout would do:
-- status none | unsupported | same | activate | add | blocked.
function M:EditModePlan(snapshot)
	local layout = snapshot.editMode
	if type(layout) ~= "table" or type(layout.text) ~= "string" then return { status = "none" } end
	local all, active = EditModeLayouts()
	if not all then return { status = "unsupported", reason = L["this game client has no Edit Mode layouts"] } end
	local match
	for _, saved in ipairs(all) do
		if LayoutText(saved.info) == layout.text and (not match or saved.info.layoutName == layout.name) then match = saved end
	end
	local Import = E.Import
	if match and match.index == active then return { status = "same", name = match.info.layoutName } end
	if match then
		local blocker = Import and Import.EditModeBlocker and Import.EditModeBlocker(nil)
		return { status = blocker and "blocked" or "activate", index = match.index, name = match.info.layoutName, reason = blocker, text = layout.text }
	end
	local name = FreeLayoutName(all, not layout.preset and layout.name or nil, snapshot.time)
	local blocker = not (Import and Import.AddEditModeLayout) and L["this game client has no Edit Mode layouts"]
		or (Import.EditModeBlocker and Import.EditModeBlocker(name))
	return { status = blocker and "blocked" or "add", name = name, reason = blocker or nil, text = layout.text }
end

-- Everything a restore of `snapshot` would change. Reads only.
function M:Plan(snapshot)
	local plan = { actions = {}, place = 0, clear = 0, unknown = 0, macros = {}, macrosFull = 0, bindings = {} }
	if GetActionInfo then
		for slot = 1, MAX_SLOTS do
			local entry = snapshot.actions and snapshot.actions[slot]
			local now = ReadSlot(slot)
			if not SameEntry(now, entry) then
				if entry then
					local ok = Placeable(entry, snapshot, true)
					plan.actions[#plan.actions + 1] = { slot = slot, to = entry, from = now, status = ok and "place" or "unknown" }
					if ok then plan.place = plan.place + 1 else plan.unknown = plan.unknown + 1 end
				else
					plan.actions[#plan.actions + 1] = { slot = slot, from = now, status = "clear" }
					plan.clear = plan.clear + 1
				end
			end
		end
	end
	for _, macro in ipairs(snapshot.macros or {}) do
		if MacroIndex(macro.name) == 0 then plan.macros[#plan.macros + 1] = macro.name end
	end
	local now, want = BindingMap(ReadBindings()), BindingMap(snapshot.bindings)
	for key, command in pairs(want) do
		if now[key] ~= command then plan.bindings[#plan.bindings + 1] = { key = key, from = now[key], to = command } end
	end
	for key, command in pairs(now) do
		if want[key] == nil then plan.bindings[#plan.bindings + 1] = { key = key, from = command } end
	end
	table.sort(plan.bindings, function(a, b) return a.key < b.key end)
	plan.editMode = self:EditModePlan(snapshot)
	return plan
end

---------------------------------------------------------------------------
-- Restoring (a click, out of combat)
---------------------------------------------------------------------------
-- Put what the snapshot names on the cursor. True when something is there.
local function Pickup(entry)
	local kind, id, extra = entry[1], entry[2], entry[3]
	if kind == "spell" and C_Spell and C_Spell.PickupSpell then
		pcall(C_Spell.PickupSpell, id)
	elseif kind == "item" and C_Item and C_Item.PickupItem then
		pcall(C_Item.PickupItem, id)
	elseif kind == "macro" and extra and PickupMacro then
		local index = MacroIndex(extra)
		if index > 0 then PickupMacro(index) end
	elseif kind == "summonmount" and C_MountJournal and C_MountJournal.GetMountInfoByID and C_Spell and C_Spell.PickupSpell then
		local ok, _, spellID = pcall(C_MountJournal.GetMountInfoByID, id)
		if ok and type(spellID) == "number" then pcall(C_Spell.PickupSpell, spellID) end
	elseif kind == "equipmentset" and C_EquipmentSet and C_EquipmentSet.GetEquipmentSetID then
		local setID = C_EquipmentSet.GetEquipmentSetID(extra or id)
		if setID then pcall(C_EquipmentSet.PickupEquipmentSet, setID) end
	end
	return GetCursorInfo() ~= nil
end

function M:RestoreMacros(snapshot)
	local added, full = 0, 0
	if not (CreateMacro and GetMacroIndexByName) then return 0, 0 end
	for _, macro in ipairs(snapshot.macros or {}) do
		if MacroIndex(macro.name) == 0 then
			local account, perChar = GetNumMacros()
			local accountMax, charMax = MacroLimits()
			local room
			if macro.char then room = (perChar or 0) < charMax else room = (account or 0) < accountMax end
			if room and pcall(CreateMacro, macro.name, macro.icon or "INV_MISC_QUESTIONMARK", macro.body, macro.char) then
				added = added + 1
			else
				full = full + 1
			end
		end
	end
	return added, full
end

function M:RestoreActions(snapshot, clearEmpty)
	if clearEmpty == nil then clearEmpty = self.db.clearEmpty end
	local placed, missing, cleared = 0, {}, 0
	if not (GetActionInfo and PlaceAction and PickupAction) then return 0, missing, 0 end
	for slot = 1, MAX_SLOTS do
		local entry = snapshot.actions[slot]
		if not CurrentMatches(slot, entry) then
			if entry then
				if Pickup(entry) then
					if entry[1] == "spell" and E.NoteActionWrite then E:NoteActionWrite(slot, entry[2]) end
					PlaceAction(slot)
					placed = placed + 1
				else
					missing[#missing + 1] = entry
				end
				ClearCursor()
			elseif clearEmpty then
				PickupAction(slot)
				ClearCursor()
				cleared = cleared + 1
			end
		end
	end
	return placed, missing, cleared
end

function M:RestoreBindings(snapshot)
	if not (SetBinding and SaveBindings and GetBinding) then return 0 end
	-- Unbind every key in use, then bind the snapshot's keys.
	for i = 1, GetNumBindings() do
		local _, _, key1, key2 = GetBinding(i)
		if key1 then SetBinding(key1) end
		if key2 then SetBinding(key2) end
	end
	local count = 0
	for _, b in ipairs(snapshot.bindings or {}) do
		if b[2] then SetBinding(b[2], b[1]) count = count + 1 end
		if b[3] then SetBinding(b[3], b[1]) end
	end
	SaveBindings(snapshot.bindingSet or (GetCurrentBindingSet and GetCurrentBindingSet()) or 1)
	return count
end

-- Switch to (or add) the snapshot's Edit Mode layout. Returns a line for
-- the chat summary.
function M:RestoreEditMode(snapshot)
	local plan = self:EditModePlan(snapshot)
	if plan.status == "same" then return nil end
	if plan.status == "none" then return nil end
	if plan.status == "unsupported" or plan.status == "blocked" then
		return (L["Edit Mode layout not changed (%s)"]):format(tostring(plan.reason))
	end
	if plan.status == "add" then
		local ok, err = E.Import.AddEditModeLayout(plan.text, plan.name)
		if not ok then return (L["Edit Mode layout not changed (%s)"]):format(tostring(err)) end
		local all, active = EditModeLayouts()
		for _, layout in ipairs(all or {}) do
			if layout.info.layoutName == plan.name and layout.index ~= active then
				pcall(C_EditMode.SetActiveLayout, layout.index)
			end
		end
		return (L["Edit Mode layout %q added and active"]):format(plan.name)
	end
	if not (C_EditMode and C_EditMode.SetActiveLayout and pcall(C_EditMode.SetActiveLayout, plan.index)) then
		return (L["Edit Mode layout not changed (%s)"]):format(L["Edit Mode refused the layout"])
	end
	return (L["Edit Mode layout %q active again"]):format(tostring(plan.name))
end

-- The parts a restore starts with (the options page's ticks).
function M:DefaultParts()
	local db = self.db
	return { actions = db.restoreActions, clearEmpty = db.clearEmpty, macros = db.restoreMacros,
		bindings = db.restoreBindings, editMode = db.restoreEditMode }
end

local function ApplyRestore(self, snapshot, parts, notify)
	local _, class = UnitClass("player")
	-- Keep what is there now, so a restore can be undone.
	self:Take(L["before restore"], false)
	local lines = {}
	if parts.macros then
		local added, full = self:RestoreMacros(snapshot)
		if added > 0 then lines[#lines + 1] = (L["%d macros added"]):format(added) end
		if full > 0 then lines[#lines + 1] = (L["%d macros did not fit"]):format(full) end
	end
	if parts.actions then
		local placed, missing, cleared = self:RestoreActions(snapshot, parts.clearEmpty and true or false)
		lines[#lines + 1] = (L["%d actions placed"]):format(placed)
		if cleared > 0 then lines[#lines + 1] = (L["%d slots emptied"]):format(cleared) end
		if #missing > 0 then
			lines[#lines + 1] = (L["%d not known by this character"]):format(#missing)
		end
	end
	if parts.bindings then
		lines[#lines + 1] = (L["%d key bindings"]):format(self:RestoreBindings(snapshot))
	end
	if parts.editMode then
		local line = self:RestoreEditMode(snapshot)
		if line then lines[#lines + 1] = line end
	end
	if #lines == 0 then lines[1] = L["nothing to change"] end
	local text = L["Snapshot restored: "] .. table.concat(lines, ", ") .. "."
	if parts.actions and snapshot.class and class and snapshot.class ~= class then
		text = text .. "\n" .. L["That snapshot was taken on another class; its spells were skipped."]
	end
	notify(text)
	return true
end

-- Restore `snapshot`. `parts` picks what (default: the options page's
-- ticks). Only ever called from a click; refused in combat. `notify`
-- (text, warn) shows the result; chat when none is given.
function M:Restore(snapshot, parts, notify)
	if not snapshot then return false end
	notify = notify or function(text) E:Print(text) end
	if InCombatLockdown() then
		notify(L["Snapshots can be restored after combat."], true)
		return false
	end
	if GetCursorInfo and GetCursorInfo() then
		notify(L["Put down what is on your cursor first, then restore the snapshot."], true)
		return false
	end
	parts = parts or self:DefaultParts()
	local done = false
	-- Not in combat here, so this runs at once; never queued for later.
	E:RunOutOfCombat(function() done = ApplyRestore(self, snapshot, parts, notify) end)
	return done
end

---------------------------------------------------------------------------
-- The restore window: what changes, which parts, then Restore
---------------------------------------------------------------------------
local preview

local function SlotLabel(slot)
	return (L["Bar %d · %d"]):format(math.floor((slot - 1) / 12) + 1, (slot - 1) % 12 + 1)
end

local PART_ROWS = {
	{ key = "actions", label = "Action bars", desc = "Place every spell, item, macro and equipment set back on its slot." },
	{ key = "clearEmpty", label = "Empty the other slots", desc = "Slots that are empty in the snapshot are emptied too, so the bars match it exactly." },
	{ key = "macros", label = "Add missing macros", desc = "Create the snapshot's macros you no longer have. Existing macros are never changed or deleted." },
	{ key = "bindings", label = "Key bindings", desc = "Set every key binding to the snapshot's." },
	{ key = "editMode", label = "Edit Mode layout", desc = "Switch to the snapshot's Edit Mode layout, or add it as a new account layout when you no longer have it." },
}

local function TipLines(tooltip, lines, limit)
	for i, line in ipairs(lines) do
		if i > limit then
			tooltip:AddLine((L["... and %d more"]):format(#lines - limit), unpack(E.UIKit.SECONDARY))
			break
		end
		tooltip:AddLine(line, unpack(E.UIKit.TEXT))
	end
end

local function CreatePreview()
	local UI, WK = E.UIKit, E.WindowKit
	local window = WK.CreateWindow("EldoUISnapshotRestore", { width = 640, height = 560, resizable = true, options = { page = "module:Snapshots" } })
	window.parts = {}

	local list = UI.CreateList(window.content, {
		rowHeight = 24,
		empty = { L["The bars already match"], L["Every action slot is already the same as in this snapshot."] },
		create = function(row)
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(20, 20)
			row.icon:SetPoint("LEFT", 2, 0)
			E:TrimIcon(row.icon)
			row.slot = UI.Text(row, 12, "LEFT", "secondary")
			row.slot:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
			row.slot:SetWidth(80)
			row.name = UI.Text(row, 13, "LEFT")
			row.name:SetPoint("LEFT", row.slot, "RIGHT", 4, 0)
			row.name:SetWidth(200)
			row.name:SetWordWrap(false)
			row.note = UI.Text(row, 12, "RIGHT", "secondary")
			row.note:SetPoint("RIGHT", -4, 0)
			row.note:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
			row.note:SetWordWrap(false)
		end,
		update = function(row, item)
			local snapshot = window.snapshot
			local shown = item.to or item.from
			local name, icon = M:EntryInfo(shown, snapshot)
			row.icon:SetTexture(icon)
			row.icon:SetDesaturated(item.status ~= "place")
			row.slot:SetText(SlotLabel(item.slot))
			local was = item.from and (L["was %s"]):format((M:EntryInfo(item.from, snapshot))) or L["was empty"]
			if item.status == "clear" then
				row.name:SetText(L["(empty)"])
				UI.Paint(row.name, "dim")
				row.note:SetText((L["removes %s"]):format(name))
				UI.Paint(row.note, "secondary")
			else
				row.name:SetText(name)
				UI.Paint(row.name, "body")
				if item.status == "unknown" then
					row.note:SetText(L["not known here, skipped"])
					row.note:SetTextColor(unpack(UI.WARN))
				else
					row.note:SetText(was)
					UI.Paint(row.note, "secondary")
				end
			end
		end,
	})
	list:SetPoint("TOPLEFT", 0, -22)
	list:SetPoint("TOPRIGHT", 0, -22)
	list:SetPoint("BOTTOM", window.content, "BOTTOM", 0, #PART_ROWS * 26 + 34)
	window.list = list
	window.listTitle = UI.Text(window.content, 13, "LEFT", "header")
	window.listTitle:SetPoint("TOPLEFT", 0, 0)
	window.listTitle:SetPoint("TOPRIGHT", 0, 0)

	local partsTitle = UI.Text(window.content, 13, "LEFT", "header")
	partsTitle:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -10)
	partsTitle:SetText(L["Restore these parts"])
	local previous = partsTitle
	for i, part in ipairs(PART_ROWS) do
		local check = WK.Check(window.content, L[part.label], nil, function() window:UpdateButtons() end)
		check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, (i == 1) and -6 or -2)
		check.part = part
		check.count = UI.Text(window.content, 12, "LEFT", "secondary")
		check.count:SetPoint("LEFT", check.label, "RIGHT", 8, 0)
		UI.Tooltip(check, L[part.label], function(tooltip)
			tooltip:AddLine(L[part.desc], unpack(UI.SECONDARY))
			if check.detail and #check.detail > 0 then
				tooltip:AddLine(" ")
				TipLines(tooltip, check.detail, 15)
			end
		end)
		window.parts[part.key] = check
		previous = check
	end
	-- Edit Mode blocked: hand the layout text to Blizzard's own Import.
	window.copyLayout = UI.Button(window.content, L["Copy layout text"], 130, 20, function()
		local text = window.snapshot and window.snapshot.editMode and window.snapshot.editMode.text
		if text then
			E:ShowCopyBox(L["Edit Mode layout from a snapshot"],
				L["Blizzard's own layout text, selected. Press Ctrl+C, then use Edit Mode > Layouts > Import."], text)
		end
	end, L["Copy layout text"], L["Shows the snapshot's Edit Mode layout as text for Edit Mode > Layouts > Import."])
	window.copyLayout:SetPoint("LEFT", window.parts.editMode.count, "RIGHT", 10, 0)

	window.restore = UI.Button(window.footer, L["Restore"], 120, 24, function()
		local parts = {}
		for key, check in pairs(window.parts) do parts[key] = check:IsEnabled() and check:GetChecked() and true or false end
		if not parts.actions then parts.clearEmpty = false end
		-- A refusal shows in this window, which stays open; after a restore
		-- it closes and the result shows in the options window (or chat).
		local function Notify(text, warn)
			if warn then
				UI.Toast(window, text, { anchor = window.footer, point = "TOP", warn = true })
			else
				E:ConfigNotice(text)
			end
		end
		if M:Restore(window.snapshot, parts, Notify) then window:Hide() end
	end)
	window.restore:SetPoint("BOTTOMRIGHT", window.footer, "BOTTOMRIGHT", 0, 6)
	window.cancel = UI.Button(window.footer, CANCEL, 100, 24, function() window:Hide() end)
	window.cancel:SetPoint("RIGHT", window.restore, "LEFT", -8, 0)
	window.status = UI.Text(window.footer, 12, "LEFT", "secondary")
	window.status:SetPoint("BOTTOMLEFT", window.footer, "BOTTOMLEFT", 0, 12)
	window.status:SetPoint("BOTTOMRIGHT", window.cancel, "BOTTOMLEFT", -12, 6) -- the buttons stand 6 up, the text 12
	window.status:SetText(L["What is on your bars now is saved as a snapshot first, so you can go back."])

	function window:UpdateButtons()
		local any = false
		for key, check in pairs(self.parts) do
			if key ~= "clearEmpty" and check:IsEnabled() and check:GetChecked() then any = true end
		end
		local actions = self.parts.actions
		local clear = self.parts.clearEmpty
		clear:SetEnabledLook((self.plan and self.plan.clear or 0) > 0 and actions:GetChecked() and actions:IsEnabled() or false)
		if clear:IsEnabled() and clear:GetChecked() then any = true end
		local combat = InCombatLockdown()
		self.restore:SetEnabled(any and not combat)
		if combat then
			self.status:SetText(L["In combat: restore after combat."])
			self.status:SetTextColor(unpack(E.UIKit.WARN))
		else
			self.status:SetText(L["What is on your bars now is saved as a snapshot first, so you can go back."])
			E.UIKit.Paint(self.status, "secondary")
		end
	end

	window:RegisterEvent("PLAYER_REGEN_DISABLED")
	window:RegisterEvent("PLAYER_REGEN_ENABLED")
	window:SetScript("OnEvent", function(self) if self:IsShown() then self:UpdateButtons() end end)
	return window
end

local function SetPart(check, enabled, checked, countText, detail)
	check:SetEnabledLook(enabled)
	check:SetChecked(enabled and checked and true or false)
	check.count:SetText(countText or "")
	check.detail = detail
end

-- Show what `snapshot` would change and wait for the Restore click.
function M:ShowPreview(snapshot, reason)
	if not snapshot then return nil end
	preview = preview or CreatePreview()
	local window = preview
	local plan = self:Plan(snapshot)
	window.snapshot, window.plan = snapshot, plan
	window:SetTitle(L["Restore a snapshot"], (reason and (reason .. " ") or "") .. self:Describe(snapshot))
	window.listTitle:SetText((L["Action slots that change (%d)"]):format(#plan.actions))
	window.list.offset = 0
	window.list:SetData(plan.actions)

	local defaults = self:DefaultParts()
	local parts = window.parts
	local slotLines = {}
	for _, item in ipairs(plan.actions) do
		if item.status == "unknown" then
			slotLines[#slotLines + 1] = SlotLabel(item.slot) .. ": " .. (M:EntryInfo(item.to, snapshot)) .. " " .. L["(not known here)"]
		end
	end
	local changeText = (L["%d to place"]):format(plan.place)
	if plan.unknown > 0 then changeText = changeText .. ", " .. (L["%d skipped"]):format(plan.unknown) end
	SetPart(parts.actions, plan.place + plan.clear > 0, defaults.actions, changeText, slotLines)
	SetPart(parts.clearEmpty, plan.clear > 0, defaults.clearEmpty, (L["%d slots"]):format(plan.clear))
	SetPart(parts.macros, #plan.macros > 0, defaults.macros, (L["%d missing"]):format(#plan.macros), plan.macros)
	local keyLines = {}
	for _, b in ipairs(plan.bindings) do
		keyLines[#keyLines + 1] = b.key .. ": " .. (b.to and tostring(b.to) or L["(unbound)"])
	end
	SetPart(parts.bindings, #plan.bindings > 0, defaults.bindings, (L["%d keys change"]):format(#plan.bindings), keyLines)
	local em = plan.editMode
	local emText
	if em.status == "none" then emText = L["not in this snapshot"]
	elseif em.status == "same" then emText = L["already active"]
	elseif em.status == "activate" then emText = (L["switch to %q"]):format(tostring(em.name))
	elseif em.status == "add" then emText = (L["add as %q"]):format(tostring(em.name))
	else emText = tostring(em.reason) end
	SetPart(parts.editMode, em.status == "activate" or em.status == "add", defaults.editMode, emText)
	window.copyLayout:SetShown(em.status == "blocked")
	window:UpdateButtons()
	window:Show()
	window:Raise()
	return window
end

-- Open the restore window; with a reason (the login check) ask first.
function M:AskRestore(snapshot, reason)
	if not snapshot then return end
	if not reason then return self:ShowPreview(snapshot) end
	local text = reason .. "\n\n" .. L["Review what this snapshot would put back?"] .. "\n" .. self:Describe(snapshot)
	E:ShowConfirm({ key = "ELDOUI_SNAPSHOT_RESTORE", title = L["Bar Snapshots"], text = text, accept = L["Review"], cancel = L["Not now"],
		data = { snapshot = snapshot, reason = reason }, onAccept = function(data) M:ShowPreview(data.snapshot, data.reason) end })
end

function M:AskRename(snapshot)
	if not snapshot then return end
	E:ShowConfirm({ key = "ELDOUI_SNAPSHOT_RENAME", title = L["Bar Snapshots"], accept = ACCEPT,
		text = L["Name this snapshot (empty for the automatic name):"] .. "\n" .. self:Describe(snapshot),
		edit = { text = snapshot.label or "", maxLetters = MAX_NAME }, data = snapshot,
		onAccept = function(own, typed) M:Rename(own, typed or "") end })
end

---------------------------------------------------------------------------
-- Login, logout and the reset check
---------------------------------------------------------------------------
local RESET_FEW, RESET_MANY = 2, 10

-- Why the current setup looks reset compared to `snapshot` (a list of
-- reasons; empty when it looks fine). Reads only.
function M:ResetSigns(snapshot)
	local signs = {}
	if not snapshot then return signs end
	local _, count = ReadActions()
	if (snapshot.count or 0) >= RESET_MANY and count <= RESET_FEW then
		signs[#signs + 1] = L["your action bars came up empty"]
	end
	local want = snapshot.bindings or {}
	if #want >= RESET_MANY then
		local now, same = BindingMap(ReadBindings()), 0
		for _, b in ipairs(want) do
			if b[2] and now[b[2]] == b[1] then same = same + 1 end
		end
		if same * 2 < #want then signs[#signs + 1] = L["most of your key bindings are different"] end
	end
	local layout = snapshot.editMode
	if type(layout) == "table" and not layout.preset and type(layout.name) == "string" then
		local all = EditModeLayouts()
		if all then
			local found = false
			for _, saved in ipairs(all) do
				if saved.info.layoutName == layout.name then found = true end
			end
			if not found then signs[#signs + 1] = (L["your Edit Mode layout %q is gone"]):format(layout.name) end
		end
	end
	return signs
end

function M:CheckLogin()
	local newest = self:List()[1]
	if self.db.offerRestore and newest then
		local signs = self:ResetSigns(newest)
		if #signs > 0 then
			self:AskRestore(newest, (L["The game may have reset your setup: %s."]):format(table.concat(signs, ", ")))
			return
		end
	end
	if self.db.auto then self:Take(nil, true) end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	if not M.active then return end
	if event == "PLAYER_ENTERING_WORLD" then
		events:UnregisterEvent("PLAYER_ENTERING_WORLD")
		-- Action slots arrive a moment after login.
		C_Timer.After(5, function() if M.active then M:CheckLogin() end end)
	elseif event == "PLAYER_LOGOUT" then
		if M.db.auto then
			local _, count = ReadActions()
			if count > RESET_FEW then M:Take(nil, true) end
		end
	end
end)

---------------------------------------------------------------------------
-- Sharing: "!EUS1!" strings with a checksum
---------------------------------------------------------------------------
local function ParseArg(arg)
	local index, char = tostring(arg or ""):match("^(%d+)@(.+)$")
	if index then return tonumber(index), char end
	return tonumber(arg or ""), nil
end

local function SnapshotByArg(arg)
	local index, char = ParseArg(arg)
	local list = M:List(char or M:SourceKey())
	return list[index or tonumber(M.db.selected) or 1]
end

-- Adler-32 of a string (integrity only, not security).
local function Checksum(text)
	local a, b = 1, 0
	for i = 1, #text do
		a = (a + text:byte(i)) % 65521
		b = (b + a) % 65521
	end
	return b * 65536 + a
end

-- The parts of a cleaned snapshot the checksum covers.
local function Canonical(s)
	local parts = {}
	for slot = 1, MAX_SLOTS do
		local a = s.actions[slot]
		if a then parts[#parts + 1] = slot .. ":" .. tostring(a[1]) .. ":" .. tostring(a[2]) .. ":" .. tostring(a[3]) end
	end
	for _, m in ipairs(s.macros) do
		parts[#parts + 1] = m.name .. "\1" .. m.body .. "\1" .. tostring(m.char) .. "\1" .. tostring(m.icon)
	end
	for _, b in ipairs(s.bindings) do parts[#parts + 1] = b[1] .. "=" .. b[2] .. "=" .. tostring(b[3]) end
	parts[#parts + 1] = tostring(s.bindingSet)
	if s.editMode then parts[#parts + 1] = s.editMode.name .. "\1" .. s.editMode.text end
	return table.concat(parts, "\2")
end

-- An imported snapshot comes from a string anyone can edit: keep only
-- well-formed actions, macros (a name and a body), bindings and layout
-- text. Nil (and why) when there is nothing usable or the checksum fails.
local function CleanImport(data)
	if type(data) ~= "table" or type(data.actions) ~= "table" then return nil, L["That snapshot string holds no action bars."] end
	local actions, count = {}, 0
	for slot = 1, MAX_SLOTS do
		local a = data.actions[slot]
		if type(a) == "table" and type(a[1]) == "string" and (type(a[2]) == "number" or type(a[2]) == "string") then
			local extra = a[3]
			actions[slot] = { a[1], a[2], (type(extra) == "string" or type(extra) == "number") and extra or nil }
			count = count + 1
		end
	end
	local macros = {}
	for _, m in ipairs(type(data.macros) == "table" and data.macros or {}) do
		if type(m) == "table" and type(m.name) == "string" and m.name ~= "" and type(m.body) == "string" then
			local icon = (type(m.icon) == "number" or type(m.icon) == "string") and m.icon or nil
			macros[#macros + 1] = { name = m.name, icon = icon, body = m.body, char = m.char == true or nil }
		end
	end
	local bindings = {}
	for _, b in ipairs(type(data.bindings) == "table" and data.bindings or {}) do
		if type(b) == "table" and type(b[1]) == "string" and type(b[2]) == "string" then
			bindings[#bindings + 1] = { b[1], b[2], type(b[3]) == "string" and b[3] or nil }
		end
	end
	local layout
	local em = data.editMode
	if type(em) == "table" and type(em.name) == "string" and type(em.text) == "string"
		and em.text ~= "" and #em.text <= MAX_LAYOUT_TEXT then
		layout = { name = em.name:sub(1, 64), text = em.text, preset = em.preset == true or nil }
	end
	local clean = {
		class = type(data.class) == "string" and data.class or nil,
		time = type(data.time) == "number" and data.time or time(),
		count = count, actions = actions, macros = macros, bindings = bindings,
		bindingSet = (data.bindingSet == 1 or data.bindingSet == 2) and data.bindingSet or nil,
		editMode = layout,
		label = L["imported"],
	}
	if count == 0 and #macros == 0 and #bindings == 0 then return nil, L["That snapshot string holds no action bars."] end
	if data.sum ~= nil and data.sum ~= Checksum(Canonical(clean)) then
		return nil, L["That snapshot string was changed or damaged (the checksum doesn't match). Copy it again in full."]
	end
	return clean
end
M.CleanImport = CleanImport
M.Checksum = function(snapshot) return Checksum(Canonical(snapshot)) end

-- Add an imported snapshot to this character's list and open the restore
-- window for it. Nothing on the bars changes until Restore is clicked.
function M:Import(raw)
	local data, err = CleanImport(raw)
	if not data then
		E:Print(err)
		return nil
	end
	data.sig = Signature(data)
	table.insert(self:List(), 1, data)
	self.db.source, self.db.selected = "", "1"
	E:Print(L["Snapshot imported. Check what it changes, then click Restore."])
	self:ShowPreview(data)
	return data
end

if E.RegisterShareKind then
	E:RegisterShareKind("barsnapshot", {
		prefix = "!EUS1!",
		version = 1,
		title = function(data) return L["Bar snapshot"] .. (data and type(data.class) == "string" and (" (" .. data.class .. ")") or "") end,
		build = function(arg)
			local s = SnapshotByArg(arg) or M:Capture("export")
			local payload = { class = s.class, time = s.time, label = s.label, count = s.count, actions = s.actions,
				macros = s.macros, bindings = s.bindings, bindingSet = s.bindingSet, editMode = s.editMode }
			local clean = CleanImport(payload)
			if clean then payload.sum = Checksum(Canonical(clean)) end
			return payload
		end,
		describe = function(raw)
			local data, err = CleanImport(raw)
			if not data then return { err } end
			local plan = M:Plan(data)
			local lines = { M:Describe(data) }
			if data.editMode then lines[#lines + 1] = (L["Edit Mode layout: %s"]):format(data.editMode.name) end
			lines[#lines + 1] = (L["Here: %d action slots, %d macros and %d keys would change."]):format(#plan.actions, #plan.macros, #plan.bindings)
			lines[#lines + 1] = L["Importing only saves it; the restore window then shows every change and waits for your click."]
			return lines
		end,
		apply = function(raw) M:Import(raw) end,
	})
end

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
function M:Command(arg)
	local word, rest = strtrim(arg or ""):match("^(%S*)%s*(.-)$")
	word = (word or ""):lower()
	local list = self:List()
	if word == "" or word == "list" then
		if #list == 0 then E:Print(L["No snapshots yet. /eui snapshot take"]) return end
		for i, s in ipairs(list) do E:Print(("%d. %s"):format(i, self:Describe(s))) end
	elseif word == "take" or word == "save" then
		self:Take(rest ~= "" and rest:sub(1, MAX_NAME) or nil, false)
	elseif word == "restore" then
		local s = list[tonumber(rest) or 1]
		if s then self:ShowPreview(s) else E:Print(L["No such snapshot."]) end
	elseif word == "rename" then
		local index, name = rest:match("^(%d+)%s*(.-)$")
		local s = list[tonumber(index or "") or 0]
		if s then
			self:Rename(s, name)
			E:Print((L["Snapshot renamed: %s"]):format(self:Describe(s)))
		else
			E:Print(L["No such snapshot."])
		end
	elseif word == "export" then
		local index = tonumber(rest) or 1
		if list[index] then E:ShowExport("share:barsnapshot:" .. index) else E:Print(L["No such snapshot."]) end
	elseif word == "delete" then
		local index = tonumber(rest)
		local s = index and list[index]
		if not s then
			E:Print(L["No such snapshot."])
			return
		end
		E:ShowConfirm({ key = "ELDOUI_SNAPSHOT_DELETE", title = L["Bar Snapshots"],
			text = L["Delete the snapshot %s? This can't be undone."]:format(self:Describe(s)),
			accept = E:GameText(DELETE, L["Delete"]), danger = true,
			onAccept = function()
				-- The list may have changed while the question was open.
				for i, entry in ipairs(list) do
					if entry == s then
						table.remove(list, i)
						E:Print(L["Snapshot deleted."])
						return
					end
				end
			end })
	else
		E:Print(L["/eui snapshot [list | take [name] | restore N | rename N name | export N | delete N]"])
	end
end

E:AddCommand("snapshot", "[list | take [name] | restore N | rename N name | export N | delete N]  save and restore action bars, macros, key bindings and the Edit Mode layout", function(arg)
	if M.active then M:Command(arg) else E:Print(E:ModuleOffHint("Snapshots")) end
end)

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:OnInitialize()
	E:RegisterGlobal("BarSnapshots", { chars = {} }, { title = "Bar snapshots", desc = "Saved action bars, macros, key bindings and Edit Mode layouts of every character." })
end

function M:OnEnable()
	pcall(events.RegisterEvent, events, "PLAYER_LOGOUT")
	if not self.loginChecked then
		self.loginChecked = true
		if IsLoggedIn and IsLoggedIn() then
			C_Timer.After(5, function() if M.active then M:CheckLogin() end end)
		else
			pcall(events.RegisterEvent, events, "PLAYER_ENTERING_WORLD")
		end
	end
end

function M:OnDisable()
	events:UnregisterAllEvents()
	if preview then preview:Hide() end
end

-- Every setting is read when it is used. An open restore window keeps the
-- parts the player ticked and only takes the new profile's look and place.
function M:OnProfileChanged()
	if not preview then return end
	if preview.ApplyPosition then preview:ApplyPosition() end
	if preview.Restyle then preview:Restyle() end
end

-- Characters (other than this one) with snapshots.
local function OtherCharacters()
	local others = {}
	for key, list in pairs(Store().chars) do
		if key ~= E.charKey and type(list) == "table" and #list > 0 then others[#others + 1] = key end
	end
	table.sort(others)
	return others
end

local function SourceValues()
	local values = { [""] = (L["This character (%d)"]):format(#M:List()) }
	for _, key in ipairs(OtherCharacters()) do
		values[key] = ("%s (%d)"):format(key, #M:List(key))
	end
	return values
end

local function SnapshotValues()
	local values = {}
	for i, s in ipairs(M:List(M:SourceKey())) do values[tostring(i)] = ("%d. %s"):format(i, M:Describe(s)) end
	if not next(values) then values["1"] = L["No snapshots yet"] end
	return values
end

local function Selected() return M:List(M:SourceKey())[tonumber(M.db.selected) or 1] end
M.Selected = Selected

local function NoSelection()
	if not Selected() then return L["No snapshot chosen"] end
end

M.options = {
	{ type = "description", label = "A snapshot holds your action slots, macros, key bindings and Edit Mode layout. Restore shows each change first and can be undone." },
	{ type = "header", label = "Snapshots" },
	{ type = "execute", label = "Take a snapshot now", desc = "Save your action bars, macros, key bindings and Edit Mode layout as they are now.", func = function() M:Take(nil, false) end },
	{ type = "select", key = "source", label = "Character", values = SourceValues, desc = "Whose snapshots to list. A snapshot from another character copies that setup to this one; spells this character doesn't know are skipped.",
		hidden = function() return #OtherCharacters() == 0 end },
	{ type = "select", key = "selected", label = "Snapshot", values = SnapshotValues, desc = "The snapshot the buttons below use; the newest is first." },
	{ type = "execute", label = "Review and restore", desc = "Open the restore window: it lists every slot, macro, key and layout the chosen snapshot would change. Nothing changes until you click Restore there.", disabled = NoSelection, func = function() M:ShowPreview(Selected()) end },
	{ type = "execute", label = "Rename", desc = "Give the chosen snapshot a name, so it is easy to find in the list.", disabled = NoSelection, func = function() M:AskRename(Selected()) end },
	{ type = "execute", label = "Export", desc = "Show the chosen snapshot as a string to copy to another character or a friend.", disabled = NoSelection, func = function()
		if not Selected() then return end
		local index = tonumber(M.db.selected) or 1
		local source = M:SourceKey()
		E:ShowExport("share:barsnapshot:" .. index .. (source ~= E.charKey and ("@" .. source) or ""))
	end },
	{ type = "execute", confirm = true, label = "Delete", desc = "Delete the chosen snapshot.", disabled = NoSelection, func = function()
		local list = M:List(M:SourceKey())
		local index = tonumber(M.db.selected) or 1
		if list[index] then table.remove(list, index) end
		M.db.selected = "1"
	end },
	{ type = "header", label = "Automatic" },
	{ type = "toggle", key = "auto", label = "Snapshot at login and logout", desc = "Keep a snapshot whenever your bars, macros, keys or Edit Mode layout changed since the last one." },
	{ type = "range", key = "keepAuto", label = "Automatic snapshots kept", min = 1, max = 20, step = 1, desc = "How many automatic snapshots to keep per character; the oldest go first. Your own snapshots are kept (up to 20).", dependsOn = "auto" },
	{ type = "toggle", key = "offerRestore", label = "Offer a restore after a reset", desc = "At login, when your bars are empty, your key bindings differ or your Edit Mode layout is gone, offers to review a restore. Nothing is restored without your click." },
	{ type = "header", label = "What a restore starts with" },
	{ type = "toggle", key = "restoreActions", label = "Action bars", desc = "Checked in the restore window: place every spell, item, macro and equipment set back on its slot. Spells this character doesn't know are skipped." },
	{ type = "toggle", key = "clearEmpty", label = "Empty the other slots", desc = "Checked in the restore window: slots that were empty in the snapshot are emptied too, so the bars match it exactly.", dependsOn = "restoreActions" },
	{ type = "toggle", key = "restoreMacros", label = "Add missing macros", desc = "Checked in the restore window: create macros from the snapshot that you no longer have. Existing macros are never changed or deleted." },
	{ type = "toggle", key = "restoreBindings", label = "Key bindings", desc = "Checked in the restore window: set every key binding to the snapshot's." },
	{ type = "toggle", key = "restoreEditMode", label = "Edit Mode layout", desc = "Restores the snapshot's Edit Mode layout, or adds it as a new one (needs Improve for Edit Mode in Blizzard UI; otherwise you get the text for Edit Mode's Import)." },
}

E:RegisterStyles("Snapshots", {
	{ key = "Standard", title = "Standard", desc = "Snapshots only when you take them; a restore starts with every part checked.",
		settings = { auto = false, keepAuto = 5, offerRestore = false, restoreActions = true, restoreMacros = true, restoreBindings = true, restoreEditMode = true, clearEmpty = true } },
	{ key = "SafetyNet", title = "Safety net", desc = "Automatic snapshots at login and logout (10 kept) and a restore offer when the game resets your setup.",
		settings = { auto = true, keepAuto = 10, offerRestore = true } },
	{ key = "Careful", title = "Careful", desc = "A restore adds what is missing but never empties a slot.",
		settings = { clearEmpty = false } },
	{ key = "BarsOnly", title = "Bars only", desc = "A restore starts with only the action bars checked.",
		settings = { restoreActions = true, restoreMacros = false, restoreBindings = false, restoreEditMode = false } },
	{ key = "KeysOnly", title = "Keys only", desc = "A restore starts with only the key bindings checked.",
		settings = { restoreActions = false, restoreMacros = false, restoreBindings = true, restoreEditMode = false } },
	{ key = "LayoutOnly", title = "Layout only", desc = "A restore starts with only the Edit Mode layout checked.",
		settings = { restoreActions = false, restoreMacros = false, restoreBindings = false, restoreEditMode = true } },
})
