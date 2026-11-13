-- EldoUI keys and spells: the How to play preview of a key set, the
-- class spells and macros, and the spell rank upgrades, shown before
-- anything changes. Every launcher (the Keybinds options page, /eui kb,
-- the strip under Quick Keybind, the rank offer, /eui ranks, the setup's
-- Keys and spells step) opens this window.
--
--   +-------------------------------------------------------------+
--   | Key sets                                                  x |
--   |=============================================================|
--   | [Classic] [A/D strafe] [Number row] [Mouse] [Shifted]  [Plain][Shift][Ctrl][Alt]
--   | how you move with this set                                  |
--   | [Keyboard] [Controller]                                     |
--   | [US][UK][Nordic][German][French]  [Check my keyboard]       |
--   | the keyboard of that layout with the mouse beside it: each  |
--   | key's category, movement, game keys, hidden buttons        |
--   | game keys: bags, map ... and where the set moves them       |
--   | bars 1-3 (bar 3: 9 buttons and 3 Consumable Bar keys)       |
--   | the selected key: chord, category, intended spell, now/next |
--   | How to play                                                 |
--   | [x] Also put class spells on empty buttons                  |
--   | [ ] Mouse 4 and 5 ...   [x] Turn off the bar page keys      |
--   | changes: shortcuts that move, manual keys, hidden buttons,  |
--   | the class spells that go on empty buttons                   |
--   | Spell ranks: [x] bar 1-3 buttons, [ ] manual bars, Keep     |
--   | Protected: buttons and keys that stay, with the reason      |
--   |-------------------------------------------------------------|
--   | status   [Take back spells] [Undo last Apply] [Apply]       |
--   +-------------------------------------------------------------+
--
-- Opening, switching sets, keyboards or layers, hovering and closing
-- never change a key or a button; the plans it shows are the ones Apply
-- checks again and writes (Core/KeybindPresets.lua, Core/KeybindSpells.lua,
-- Core/Premades.lua, Modules/ActionBars/Ranks.lua).
-- Arrow keys move between keys, Tab switches the layer. The Controller
-- switch shows the class spells on the game's controller bars instead
-- (Core/KeybindPreviewPad.lua).
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local Key = E.Key
-- spells: the "class spells on empty buttons" box (on by default; it only
-- counts when you press Apply). macros: the class macros box (off until
-- you tick it). ranks: your rank ticks by action slot.
-- view: "keyboard" or "controller" (the controller bars; chosen when the
-- window first opens in the game's gamepad interface).
local P = { id = "movement", layer = 1, take = {}, spells = true, macros = false, ranks = {} }
E.KeybindPreview = P

-- The layers of the drawing: the keys without a modifier, with Shift,
-- with Ctrl and with Alt (where the game shortcuts a set takes go).
local LAYERS = {
	{ prefix = "", label = Key("Plain keys"), tip = Key("The keys without a modifier.") },
	{ prefix = "SHIFT-", label = Key("Shift"), tip = Key("The keys with Shift held.") },
	{ prefix = "CTRL-", label = Key("Ctrl"), tip = Key("The keys with Ctrl held.") },
	{ prefix = "ALT-", label = Key("Alt"), tip = Key("The keys with Alt held: where the game shortcuts a set takes go.") },
}
P.LAYERS = LAYERS
-- The modifier keys that light up on their layer.
local LAYER_KEYS = { lshift = 2, rshift = 2, lctrl = 3, rctrl = 3, lalt = 4, ralt = 4 }
local GAP = 4
local PAD = 4

local MOVE_TAGS = {
	MOVEFORWARD = Key("Fwd"), MOVEBACKWARD = Key("Back"), TURNLEFT = Key("Turn"), TURNRIGHT = Key("Turn"),
	STRAFELEFT = Key("Strafe"), STRAFERIGHT = Key("Strafe"),
}
-- Bar 3's keys 10-12: what the Consumable Bar button holds.
local CONSUMABLE_TEXT = {
	healthPotion = { short = Key("Potion"), label = Key("Health potion") },
	healthstone = { short = Key("Stone"), label = Key("Healthstone") },
	manaPotion = { short = Key("Mana"), label = Key("Mana potion") },
	bandage = { short = Key("Bandage"), label = Key("Bandage") },
}
P.CONSUMABLE_TEXT = CONSUMABLE_TEXT

local function Kit() return E.UIKit end

---------------------------------------------------------------------------
-- What a key or button means in the plan shown
---------------------------------------------------------------------------
local function Plain(value)
	if E.Secret and E.Secret(value) then return nil end
	return value
end

-- The action now on an action slot: name and icon.
local function SlotAction(slot)
	if not slot then return nil end
	local getTexture = C_ActionBar and C_ActionBar.GetActionTexture or GetActionTexture
	local texture = type(getTexture) == "function" and Plain(getTexture(slot)) or nil
	local kind, id
	if type(GetActionInfo) == "function" then
		local ok, k, i = pcall(GetActionInfo, slot)
		if ok then kind, id = Plain(k), Plain(i) end
	end
	if not kind then return nil, texture end
	local name
	if kind == "spell" then
		name = C_Spell and C_Spell.GetSpellName and Plain(C_Spell.GetSpellName(id))
	elseif kind == "item" then
		name = C_Item and C_Item.GetItemNameByID and Plain(C_Item.GetItemNameByID(id))
	elseif kind == "macro" then
		local getText = C_ActionBar and C_ActionBar.GetActionText or GetActionText
		name = type(getText) == "function" and Plain(getText(slot)) or L["Macro"]
	end
	return type(name) == "string" and name ~= "" and name or L["Something"], texture
end
P.SlotAction = SlotAction

-- The game shortcuts of the game keys card, by command.
local GAME_COMMANDS
local function GameCommand(command)
	if not GAME_COMMANDS then
		GAME_COMMANDS = {}
		for _, spec in ipairs(E.keybindGameKeys or {}) do
			for _, name in ipairs(spec.commands or {}) do GAME_COMMANDS[name] = spec end
			if spec.row then
				for n = 1, 10 do GAME_COMMANDS[spec.row .. n] = spec end
			end
		end
	end
	return GAME_COMMANDS[command]
end

-- Plan entries by key, for the keyboard.
local function Index(plan)
	local byKey = {}
	for _, list in ipairs({ plan.slots, plan.moves, plan.homes or {}, plan.pages or {} }) do
		for _, entry in ipairs(list) do
			if entry.key and (entry.state ~= "taken" or not byKey[entry.key]) then byKey[entry.key] = entry end
		end
	end
	plan.byKey = byKey
	return byKey
end

-- The plan entry of a bar button (bar 3 buttons 10-12: the Consumable Bar).
local function SlotEntry(plan, bar, button)
	return plan and plan.slots[(bar - 1) * 12 + button] or nil
end
P.SlotEntry = SlotEntry

local function Role()
	return E.GetRole and E:GetRole() or "none"
end

-- The detail of one key: what the preview shows for it.
function P.Describe(plan, key)
	local entry = key and (plan.byKey and plan.byKey[key] or Index(plan)[key])
	local out = { key = key, keyText = E:KeybindKeyText(key), entry = entry }
	local current = E:KeybindActionOf(key)
	out.current, out.currentName = current, E:KeybindCommandName(current)
	if not entry then
		out.kind = "free"
		if GameCommand(current) then out.kind, out.tag = "game", L["Game"] end
		return out
	end
	if entry.kind == "movement" then
		out.kind, out.tag = "movement", E:Translate(MOVE_TAGS[entry.command])
		out.proposedName = E:KeybindCommandName(entry.command)
	elseif entry.kind == "character" then
		out.kind, out.tag = "character", L["Char"]
		out.proposedName = E:KeybindCommandName(entry.command)
	elseif entry.kind == "home" then
		out.kind, out.tag = "home", L["Game"]
		out.proposedName = E:KeybindCommandName(entry.command)
	elseif entry.kind == "page" then
		out.kind, out.tag = "page", L["Off"]
		out.proposedName = L["nothing"]
	elseif entry.consumable then
		out.kind = "consumable"
		out.bar, out.button = entry.bar, entry.button
		local text = CONSUMABLE_TEXT[entry.consumable]
		out.tag = text and L[text.short] or ""
		out.consumable = entry.consumable
		out.proposedName = E:KeybindCommandName(entry.command)
	else
		out.kind = "slot"
		out.bar, out.button = entry.bar, entry.button
		out.intended = E.keybindCategories and E.keybindCategories.Resolve(entry.bar, entry.button, nil, Role()) or {}
		local info = out.intended.info
		out.tag = info and E:Translate(info.short) or ""
		-- Numbered groups (rotation 1-5) carry their number on the cap.
		local catKey = out.intended.key
		if info and catKey and not E.keybindCategories.info[catKey] and catKey:match("%d$") then out.tag = out.tag .. catKey:match("(%d)$") end
		out.onButton, out.icon = SlotAction(entry.action)
		out.proposedName = E:KeybindCommandName(entry.command)
	end
	out.state, out.visible = entry.state, entry.visible
	return out
end

---------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------
local STATE_TEXT = {
	bind = Key("changes"), same = Key("already set"), manual = Key("kept: belongs to a manual bar"), off = Key("skipped: the bar is turned off"),
	free = Key("stays free: the Consumable Bar is off"), taken = Key("kept: the key holds something of yours"), unbind = Key("taken off"),
}

local function IntendedText(intended)
	if not intended or not intended.info then return L["Your choice."] end
	local state = intended.state
	if state == "ready" then
		return intended.name or L["Something"]
	elseif state == "unlearned" then
		return L["%s (not learned yet)"]:format(intended.name or L["a class spell"])
	elseif state == "reserved" then
		return L["Kept free: %s"]:format(intended.reason or "")
	elseif state == "missing" then
		return intended.reason or ""
	end
	return intended.reason or L["Your choice."]
end
P.IntendedText = IntendedText

-- What Apply does with a button's class spell, or nil when the category
-- names no known spell.
local SPELL_TEXT = {
	place = Key("goes on this empty button when you apply"),
	placed = Key("placed here by an earlier Apply"),
	onbar = Key("already on your bars: not moved"),
	kept = Key("not placed: the button holds your own action"),
	hidden = Key("not placed: the button is hidden"),
	paged = Key("not placed: bar 1 shows your stance page"),
	noform = Key("not placed: learn the form first"),
}
function P.SpellText(bar, button)
	local entry = P.spellPlan and E:KeybindSpellEntry(P.spellPlan, bar, button)
	local text = entry and E:Translate(SPELL_TEXT[entry.status])
	if not text then return nil end
	if entry.status == "place" and not P.spells then text = L["would go on this empty button (check the box below)"] end
	return ("%s: %s"):format(entry.name or L["a class spell"], text)
end

-- A key inside a sentence: punctuation keys get their name.
local KEY_WORDS = { [","] = Key("comma (,)"), ["."] = Key("period (.)"), ["-"] = Key("minus (-)"), ["="] = Key("equals (=)") }
local function KeyWord(key)
	if type(key) ~= "string" then return L["no key"] end
	local plain = key:match("^[A-Z]+%-(.+)$") or key
	if KEY_WORDS[plain] then return (key:sub(1, #key - #plain)) .. L[KEY_WORDS[plain]] end
	return E:KeybindKeyText(key)
end
P.KeyWord = KeyWord

-- Bar 3's own buttons 10-12 keep what they hold; the set gives them no key.
local function KeptBar3(button)
	local name = SlotAction(E:KeybindActionSlot(3, button))
	return name and L["Bar 3 button %d keeps its action (%s), no key from the set."]:format(button, name) or nil -- no-plural (a button number)
end

function P.DetailLines(plan, key)
	local d = P.Describe(plan, key)
	local lines = {}
	local function Add(label, value) lines[#lines + 1] = { label = label, value = value } end
	if d.kind == "free" or d.kind == "game" then
		lines.title = d.keyText
		Add(L["This key set"], L["leaves this key as it is."])
		Add(L["Key now"], d.currentName)
		return lines, d
	end
	if d.kind == "slot" then
		lines.title = L["%s: bar %d, button %d"]:format(d.keyText, d.bar, d.button)
		local info = d.intended.info
		Add(L["Category"], info and ("%s: %s"):format(L[info.label], L[info.desc]) or "")
		local intended = IntendedText(d.intended)
		if d.intended.formName then intended = intended .. " " .. L["(%s)"]:format(d.intended.formName) end
		if d.intended.note then intended = intended .. " " .. d.intended.note end
		Add(L["Intended"], intended)
		Add(L["On this button now"], d.onButton or L["empty"])
		local spell = P.SpellText(d.bar, d.button)
		if spell then Add(L["Class spell"], spell) end
		if d.visible == false and d.state ~= "off" then Add(L["On screen"], L["hidden in this layout, key works"]) end
	elseif d.kind == "consumable" then
		lines.title = L["%s: bar 3, key %d"]:format(d.keyText, d.button)
		local text = CONSUMABLE_TEXT[d.consumable]
		Add(L["Category"], L["Consumable Bar: %s, the best one in your bags."]:format(text and L[text.label] or ""))
		if d.state == "free" then Add(L["Consumable Bar"], L["The Consumable Bar is off, so this key stays free."]) end
		local kept = KeptBar3(d.button)
		if kept then Add(L["Bar 3"], kept) end
	elseif d.kind == "home" or d.kind == "character" then
		lines.title = d.keyText
		local from = d.entry.from and KeyWord(d.entry.from)
		Add(L["Category"], from and L["Game shortcut, moved from %s"]:format(from) or L["Game shortcut, moved with the pet bar"])
	elseif d.kind == "page" then
		lines.title = d.keyText
		Add(L["Category"], L["Bar page key: taken off, so bar 1 never swaps its spells in a fight."])
	else
		lines.title = d.keyText
		Add(L["Category"], L["Movement"])
	end
	Add(L["Key now"], ("%s  >  %s (%s)"):format(d.currentName, d.proposedName or "", E:Translate(STATE_TEXT[d.state]) or ""))
	return lines, d
end

-- How to play: a few lines for the set shown and your class.
function P.HowToPlay(plan)
	local preset = plan.preset
	local lines = { L[preset.movementText] }
	local function KeyOf(button)
		local entry = SlotEntry(plan, 1, button)
		return entry and entry.key and E:KeybindKeyText(entry.key) or L["no key"]
	end
	lines[#lines + 1] = L["Keys %s to %s hold your rotation or heals, in the order you press them most."]:format(KeyOf(1), KeyOf(5))
	local Resolve = E.keybindCategories and E.keybindCategories.Resolve
	local function Spell(bar, button)
		local r = Resolve and Resolve(bar, button, nil, Role())
		if r and (r.state == "ready" or r.state == "unlearned") and r.name then return r.name end
	end
	local kick, move = Spell(1, 6), Spell(1, 7)
	lines[#lines + 1] = L["%s interrupts%s, %s is your movement ability%s."]:format(KeyOf(6), kick and (" (" .. kick .. ")") or "",
		KeyOf(7), move and (" (" .. move .. ")") or "")
	lines[#lines + 1] = L["%s controls, %s and %s are your defensives, %s is your main cooldown."]:format(KeyOf(8), KeyOf(9), KeyOf(10), KeyOf(12))
	if preset.grid then
		lines[#lines + 1] = L["The side buttons hold bar 1 and Shift + the side buttons bar 2. Bar 3 sits on the keys around your movement hand."]
	else
		lines[#lines + 1] = L["Hold Shift for bar 2 (group help, cleanse, second spells) and Ctrl for bar 3 (utility, travel, resurrection, class buff)."]
	end
	lines[#lines + 1] = L["Bar 3 has 9 buttons; its last three keys use the Consumable Bar: health potion, healthstone, and mana potion or bandage."]
	lines[#lines + 1] = L["Every game shortcut a set takes gets the same new key in every set: the same key with Alt, the Character pane on the comma, Sheath on the period."]
	lines[#lines + 1] = L["Every character uses the same keys for the same job, so an alt plays the same way."]
	lines[#lines + 1] = L["Bar 4 and the other bars stay manual: their keys and spells are yours."]
	lines[#lines + 1] = L["Apply can also put your known class spells on empty buttons of bars 1 to 3. A button with your own action keeps it, and nothing moves by itself later: after you learn new spells, apply again to fill their buttons."]
	return lines
end

-- The key changes: { text, take = key (a manual key you may give) }.
function P.KeyChangeLines(plan)
	local out = {}
	if plan.blocked then out[#out + 1] = { text = plan.blockedText } end
	-- The pet bar gets one line for the whole row, below.
	for _, lost in ipairs(plan.displaced) do
		if not lost.pet then
			if lost.movedTo then
				out[#out + 1] = { text = L["%s moves from %s to %s."]:format(lost.name, KeyWord(lost.key), KeyWord(lost.movedTo)) }
			elseif lost.homeTaken and lost.homeTaken ~= "" then
				out[#out + 1] = { text = L["%s loses its key %s: its new key %s holds something of yours, so it gets none."]:format(lost.name,
					KeyWord(lost.key), KeyWord(lost.homeTaken)) }
			elseif lost.manualBar then
				out[#out + 1] = { text = L["%s gives its key %s to this key set, as you chose."]:format(lost.name, KeyWord(lost.key)), take = lost.key, on = true }
			else
				out[#out + 1] = { text = L["%s loses its key %s."]:format(lost.name, KeyWord(lost.key)) }
			end
		end
	end
	if plan.petMoved then
		out[#out + 1] = { text = L["The pet bar moves from Ctrl + the number row to Alt + the number row."] }
	end
	for _, entry in ipairs(plan.manual) do
		local where = type(entry.manualBar) == "number" and L["bar %d"]:format(entry.manualBar)
			or entry.manualBar == "pet" and L["the pet bar"] or L["the stance bar"]
		local what = entry.kind == "character" and L["Character pane"] or E:KeybindCommandName(entry.command)
		out[#out + 1] = { text = L["%s stays on %s (%s), so %s gets no key."]:format(KeyWord(entry.key), entry.currentName, where, what),
			take = entry.key, on = false }
	end
	if #(plan.pages or {}) > 0 then
		local keys = {}
		for _, entry in ipairs(plan.pages) do keys[#keys + 1] = E:KeybindKeyText(entry.key) end
		out[#out + 1] = { text = L["The bar page keys (%s) are taken off, so bar 1 never swaps its spells in a fight."]:format(table.concat(keys, ", ")) }
	end
	if #plan.hidden > 0 then
		out[#out + 1] = { text = E:Plural(#plan.hidden, "%d button is hidden in this layout: it gets its key, and the key works.",
			"%d buttons are hidden in this layout: they get their keys, and the keys work."):format(#plan.hidden) }
	end
	if #(plan.off or {}) > 0 then
		out[#out + 1] = { text = E:Plural(#plan.off, "%d button is on a bar you turned off and gets no key. Turn the bar on under Action Bars first.",
			"%d buttons are on a bar you turned off and get no key. Turn the bar on under Action Bars first."):format(#plan.off) }
	end
	if #(plan.free or {}) > 0 then
		local keys = {}
		for _, entry in ipairs(plan.free) do keys[#keys + 1] = KeyWord(entry.key) end
		out[#out + 1] = { text = E:ModuleOffNote("ConsumableBar", L["Until it is on, %s stay free; then they use your potion, healthstone, and mana potion or bandage."]:format(table.concat(keys, ", "))),
			consumable = true }
	end
	if #(plan.noKey or {}) > 0 then
		out[#out + 1] = { text = E:Plural(#plan.noKey, "%d place has no usable key on your keyboard (an accent key that types nothing): it gets no key. Check my keyboard finds the keys your game uses.",
			"%d places have no usable key on your keyboard (an accent key that types nothing): they get no key. Check my keyboard finds the keys your game uses."):format(#plan.noKey) }
	end
	for button = 10, 12 do
		local kept = KeptBar3(button)
		if kept then out[#out + 1] = { text = kept } end
	end
	return out
end

-- The changes list of the window: the key changes, then the class spells
-- when that box is ticked.
function P.ChangeLines(plan)
	local out = P.KeyChangeLines(plan)
	local spells = P.spellPlan
	if spells and P.spells then
		local names = {}
		for _, entry in ipairs(spells.places) do names[#names + 1] = entry.name or tostring(entry.spell) end
		if #names > 0 then
			out[#out + 1] = { text = L["Class spells on empty buttons: %s."]:format(table.concat(names, ", ")) }
		end
		if spells.counts.kept > 0 then
			out[#out + 1] = { text = E:Plural(spells.counts.kept, "%d button holds your own action: it keeps it.",
				"%d buttons hold your own actions: they keep them."):format(spells.counts.kept) }
		end
		if spells.counts.paged > 0 then
			out[#out + 1] = { text = L["Bar 1 shows your stance page, so its class spells are only shown: put them on the stance you use."] }
		end
	end
	local unassigned = E.keybindCategories and E.keybindCategories.Unassigned(nil, Role()) or {}
	if #unassigned > 0 then
		local names = {}
		for _, spell in ipairs(unassigned) do names[#names + 1] = spell.name or tostring(spell.spell) end
		out[#out + 1] = { text = L["Your class setup also places %s; give them a free button."]:format(table.concat(names, ", ")) }
	end
	if #out == 0 then out[1] = { text = L["Nothing else changes."] } end
	return out
end

---------------------------------------------------------------------------
-- Keys and spells together: one plan, one Apply, one Undo
---------------------------------------------------------------------------
-- The four read-only plans in one: the key set (bars 1-3), the
-- class spells on empty buttons (Core/KeybindSpells.lua), the class
-- setup's spells and macros (Core/Premades.lua) and the spell rank
-- upgrades (Modules/ActionBars/Ranks.lua).
--
--   E:KeysAndSpellsPlan([opts])      read only. opts: id (preset), take
--                                    (manual keys you give), spells (class
--                                    spells on empty buttons, the class
--                                    setup's too; on unless false), macros
--                                    (the class setup's macros), ranks
--                                    ({ [slot] = true/false }: your ticks),
--                                    keys (false: no key changes, only
--                                    spells and macros), upgrades (false:
--                                    no rank ticked)
--   E:ApplyKeysAndSpells(plan)       checks the plan again and writes it,
--                                    out of combat (a click in combat waits
--                                    for its end)
--   E:RestoreKeysAndSpells([report]) puts back what the last Apply did,
--                                    only where it still holds what it put
--   E:OpenKeysAndSpells([focus])     the window ("ranks": at the ranks)
--
-- Bars 1 to 3 are managed: their keys and spells change with Apply. Bar 4
-- and the other bars are manual: their keys stay, and a lower rank on
-- them is listed but unticked. Buttons with a macro, an item or your own
-- action, ranks kept on purpose and keys of manual bars are protected and
-- named with the reason. The class setup's spells follow the keybind
-- categories: a spell a category names goes on that category's button,
-- so there is one grid. Nothing casts, trains or spends talents.
E:RegisterPrivate("keysAndSpells", {})

local HISTORY = 5

-- Action pages of the bars (the game's numbering): page -> bar.
local PAGE_BAR = { [1] = 1, [2] = 1, [3] = 4, [4] = 5, [5] = 3, [6] = 2, [13] = 6, [14] = 7, [15] = 8 }

-- The bar of an action slot, and whether a preset manages it (bars 1 to 3
-- and the stance pages of bar 1).
function E:KeybindSlotBar(slot)
	if type(slot) ~= "number" then return nil, false end
	local page = math.floor((slot - 1) / 12) + 1
	if page >= 7 and page <= 10 then return 1, true end
	return PAGE_BAR[page], page == 1 or page == 5 or page == 6
end

-- What a button holds that keeps it from changing: "macro", "item" or
-- "own" (your own action).
local function Holds(slot)
	if type(GetActionInfo) ~= "function" then return "own" end
	local ok, kind = pcall(GetActionInfo, slot)
	kind = ok and Plain(kind) or nil
	if kind == "macro" or kind == "item" then return kind end
	return "own"
end

local function ActionBars()
	local module = E.modules and E.modules.ActionBars
	return module and module.RankPlan and module or nil
end

local function SpellNameOf(id)
	local name = C_Spell and C_Spell.GetSpellName and Plain(C_Spell.GetSpellName(id))
	return type(name) == "string" and name ~= "" and name or nil
end

local function CursorBusy()
	if type(GetCursorInfo) ~= "function" then return false end
	local ok, kind = pcall(GetCursorInfo)
	return ok and kind ~= nil
end

function E:KeysAndSpellsPlan(opts)
	opts = opts or {}
	local id = self:KeybindPresetKey(opts.id) or self.keybindPresetOrder[1]
	local plan = {
		opts = { id = id, take = opts.take or {}, spells = opts.spells ~= false, macros = opts.macros and true or false, ranks = opts.ranks or {},
			keyboard = opts.keyboard, thumb = opts.thumb, pageKeys = opts.pageKeys,
			keys = opts.keys ~= false, upgrades = opts.upgrades ~= false },
		protected = {}, ranks = {}, premade = { bars = {}, macros = {}, adds = 0 },
	}
	plan.keys = self:KeybindPlan(id, { take = plan.opts.take, keyboard = plan.opts.keyboard, thumb = plan.opts.thumb, pageKeys = plan.opts.pageKeys })
	-- Spells and macros only: the keys stay as they are.
	if not plan.opts.keys then
		plan.keys.writes, plan.keys.manual, plan.keys.displaced, plan.keys.signature = {}, {}, {}, "keep"
	end
	plan.spells = self.KeybindSpellPlan and self:KeybindSpellPlan() or nil
	-- The signature covers what Apply would write, so Apply can tell the
	-- plan shown still holds.
	local sig = { plan.keys.signature }
	local function Protect(entry)
		plan.protected[#plan.protected + 1] = entry
	end
	-- Keys a manual bar holds: the preset leaves them (the changes list
	-- offers to give them).
	for _, entry in ipairs(plan.keys.manual) do
		Protect({ key = entry.key, reason = "binding", name = entry.currentName, manualBar = entry.manualBar })
	end
	-- Buttons of bars 1-3 with something of yours on them.
	local grid, taken = {}, {}
	for _, entry in ipairs(plan.spells and plan.spells.entries or {}) do
		if entry.status == "kept" and entry.slot then
			Protect({ slot = entry.slot, reason = Holds(entry.slot), spell = entry.spell, name = entry.name })
		end
		if entry.spell and entry.status ~= "paged" and entry.status ~= "unlearned" then
			grid[entry.spell] = true
			if entry.name then grid[entry.name] = true end
		end
		if entry.status == "place" and entry.slot then taken[entry.slot] = true end
	end
	-- The class setup: a spell the categories place stays on the grid; the
	-- rest goes on its own empty button of bar 1.
	local premade = self.GetClassPremade and self:GetClassPremade() and self.PremadePlan and self:PremadePlan() or nil
	for _, bar in ipairs(premade and premade.bars or {}) do
		local _, managed = self:KeybindSlotBar(bar.slot)
		local onGrid = grid[bar.spell] or (bar.name and grid[bar.name]) or taken[bar.slot]
		if managed and not onGrid then
			if bar.status == "place" then
				plan.premade.bars[#plan.premade.bars + 1] = bar
			elseif bar.status == "kept" then
				Protect({ slot = bar.slot, reason = Holds(bar.slot), spell = bar.spell, name = bar.name })
			end
		end
	end
	for _, macro in ipairs(premade and premade.macros or {}) do
		plan.premade.macros[#plan.premade.macros + 1] = macro
		if macro.status == "add" then plan.premade.adds = plan.premade.adds + 1 end
	end
	-- Spell ranks: bars 1-3 and the gamepad bars ticked, the other bars
	-- listed unticked.
	local module = ActionBars()
	for _, entry in ipairs(module and module:RankPlan() or {}) do
		local bar, managed = self:KeybindSlotBar(entry.slot)
		if not managed and module.GamepadSlotIndex and module:GamepadSlotIndex(entry.slot) then managed = true end
		entry.bar, entry.managed = bar, managed
		if entry.status == "upgrade" then
			local tick = plan.opts.ranks[entry.slot]
			if tick == nil then tick = managed end
			entry.tick = plan.opts.upgrades and tick and true or false
		else
			entry.tick = false
			Protect({ slot = entry.slot, reason = entry.status == "macro" and "macro" or "rank", spell = entry.from, name = entry.name,
				rankMacro = entry.status == "macro" or nil })
		end
		plan.ranks[#plan.ranks + 1] = entry
		if entry.tick then sig[#sig + 1] = ("r%d=%s>%s"):format(entry.slot, tostring(entry.from), tostring(entry.to)) end
	end
	local counts = { keys = #plan.keys.writes, spells = 0, premade = 0, macros = plan.opts.macros and plan.premade.adds or 0, ranks = 0 }
	if plan.opts.spells then
		counts.spells = plan.spells and #plan.spells.places or 0
		counts.premade = #plan.premade.bars
	end
	for _, entry in ipairs(plan.ranks) do if entry.tick then counts.ranks = counts.ranks + 1 end end
	counts.total = counts.keys + counts.spells + counts.premade + counts.macros + counts.ranks
	plan.counts = counts
	if counts.spells > 0 then sig[#sig + 1] = plan.spells.signature end
	if counts.premade > 0 then
		for _, bar in ipairs(plan.premade.bars) do sig[#sig + 1] = ("b%d=%s"):format(bar.slot, tostring(bar.spell)) end
	end
	if counts.macros > 0 then
		for _, macro in ipairs(plan.premade.macros) do
			if macro.status == "add" then sig[#sig + 1] = "m" .. macro.name end
		end
	end
	plan.signature = table.concat(sig, "|")
	return plan
end

-- Why a plan can't be applied right now, or nil.
function E:KeysAndSpellsBlocked(plan)
	if InCombatLockdown() then return "combat", L["Keys and action buttons can't change in combat."] end
	if CursorBusy() then return "cursor", L["Put down what is on your cursor first."] end
	if not plan then return "missing", L["This key set is not there any more."] end
	if self:KeysAndSpellsPlan(plan.opts).signature ~= plan.signature then
		return "stale", L["Your keys or action buttons changed since the preview. Look at the preview again before you apply."]
	end
	return nil
end

local function Store()
	local store = E:GetPrivate("keysAndSpells")
	if type(store) ~= "table" then return nil end
	store.history = type(store.history) == "table" and store.history or {}
	return store
end

-- The newest Apply that can still be undone, or nil.
function E:KeysAndSpellsRecord()
	local store = Store()
	local history = store and store.history
	return history and history[#history] or nil
end

function E:HasKeysAndSpells()
	return self:KeysAndSpellsRecord() ~= nil or self:HasKeybindBackup()
end

local function Copy(list)
	local out = {}
	for key, value in pairs(list or {}) do out[key] = value end
	return out
end

-- The writers, after the plan is checked once more. Out of combat only.
local function ApplyNow(self, plan, report)
	local why, notice = self:KeysAndSpellsBlocked(plan)
	if why then
		if report ~= false then self:ConfigNotice(notice, true) end
		return false, why
	end
	local counts = plan.counts
	local record = { time = time() }
	local parts = {}
	local spells = counts.spells > 0 and plan.spells or nil
	if counts.keys > 0 or spells then
		local ok, result = self:ApplyKeybindPlan(plan.keys, spells, { quiet = true })
		if ok then
			record.keys = counts.keys > 0 and result.stamp or nil
			record.spells = result.spells and result.spells.placed > 0 or nil
			parts[#parts + 1] = result.text
		end
	end
	if counts.premade + counts.macros > 0 then
		local only = {}
		for _, bar in ipairs(plan.premade.bars) do only[bar.slot] = true end
		local before = self:PremadeApplied()
		local beforeBars, beforeMacros = Copy(before and before.bars), Copy(before and before.macros)
		self:ApplyPremade(nil, { bars = counts.premade > 0, macros = counts.macros > 0, only = only, barsOnly = true })
		local after = self:PremadeApplied()
		local bars, macros = {}, {}
		local placed, added = 0, 0
		for slot, spell in pairs(after and after.bars or {}) do
			if beforeBars[slot] == nil then bars[slot], placed = spell, placed + 1 end
		end
		for name, body in pairs(after and after.macros or {}) do
			if beforeMacros[name] == nil then macros[name], added = body, added + 1 end
		end
		if placed + added > 0 then record.premade = { bars = bars, macros = macros } end
		if placed > 0 then
			parts[#parts + 1] = E:Plural(placed, "%d class setup spell placed on an empty button.", "%d class setup spells placed on empty buttons."):format(placed)
		end
		if added > 0 then parts[#parts + 1] = E:Plural(added, "%d class macro added.", "%d class macros added."):format(added) end
	end
	local module = ActionBars()
	if counts.ranks > 0 and module then
		local list = {}
		for _, entry in ipairs(plan.ranks) do
			if entry.tick then list[#list + 1] = { slot = entry.slot, from = entry.from, to = entry.to, name = entry.name } end
		end
		module:UpgradeRanks(list)
		local done = {}
		for _, entry in ipairs(list) do
			local ok, kind, id = pcall(GetActionInfo, entry.slot)
			if ok and Plain(kind) == "spell" and Plain(id) == entry.to then done[#done + 1] = entry end
		end
		if #done > 0 then
			record.ranks = done
			parts[#parts + 1] = E:Plural(#done, "%d button moved to its highest rank.", "%d buttons moved to their highest rank."):format(#done)
		end
	end
	if record.keys or record.spells or record.premade or record.ranks then
		local store = Store()
		if store then
			local history = store.history
			history[#history + 1] = record
			-- The newest few stay; each can be put back in turn.
			while #history > HISTORY do table.remove(history, 1) end
		end
	end
	if #parts == 0 then parts[1] = L["Nothing needed to change."] end
	if report ~= false then
		self:PushAlert({
			key = "keybind-preset",
			title = L["Keys and spells"],
			text = table.concat(parts, "\n"),
			actions = {
				{ label = L["Undo"], tip = L["Put back the keys you had before, take the placed spells and macros off again and put back the old ranks."],
					func = function() E:RunOutOfCombat(function() E:RestoreKeysAndSpells(false) end, "KeysAndSpells:undo") end },
				{ label = L["Keep"] },
			},
		})
	end
	if self.KeybindPreviewChanged then self:KeybindPreviewChanged() end
	return true, record
end

-- report: false says nothing (the setup reports for itself).
function E:ApplyKeysAndSpells(plan, report)
	if not plan then return false, "missing" end
	local generation = self:NewApplyGeneration("keys")
	local ok, why
	local ran = self:RunOutOfCombat(function()
		ok, why = ApplyNow(self, plan, report)
	end, "KeysAndSpells:apply", { generation = generation, lane = "keys" })
	if not ran then
		if report ~= false then self:ConfigNotice(L["Your keys and spells change when combat ends."]) end
		return false, "queued"
	end
	return ok, why
end

-- parts (optional): { keys, spells, premade, ranks } to put back only
-- those; the record goes once nothing is left in it. report as
-- E:RestoreKeybinds. Returns true when something was put back.
function E:RestoreKeysAndSpells(report, parts)
	local function Report(text, warn)
		if report == false then return end
		if type(report) == "function" then report(text, warn) else self:Print(text) end
	end
	local store = Store()
	local record = self:KeysAndSpellsRecord()
	if not record then
		-- Keys set by a preset before: the keybind backup puts them back.
		if self:HasKeybindBackup() then return self:RestoreKeybinds(report) end
		Report(L["There is nothing to put back on this character."], true)
		return false
	end
	if InCombatLockdown() then
		Report(L["Keys and action buttons can't change in combat."], true)
		return false
	end
	parts = parts or { keys = true, spells = true, premade = true, ranks = true }
	if parts.ranks and record.ranks then
		local place = self.PremadeSlots and self.PremadeSlots.Place
		for _, entry in ipairs(record.ranks) do
			local ok, kind, id = pcall(GetActionInfo, entry.slot)
			if place and ok and Plain(kind) == "spell" and Plain(id) == entry.to then place(entry.slot, entry.from) end
		end
		record.ranks = nil
	end
	if parts.premade and record.premade then
		local applied = self:PremadeApplied()
		local keep = { bars = {}, macros = {} }
		for slot, spell in pairs(applied and applied.bars or {}) do
			if record.premade.bars[slot] == nil then keep.bars[slot] = spell end
		end
		for name, body in pairs(applied and applied.macros or {}) do
			if record.premade.macros[name] == nil then keep.macros[name] = body end
		end
		self:RevertPremadeParts({ bars = true, macros = true }, keep)
		record.premade = nil
	end
	if parts.spells and record.spells then
		self:RevertKeybindSpells(false)
		record.spells = nil
	end
	if parts.keys and record.keys then
		-- Only the backup this Apply made: a later preset keeps its own.
		if self:KeybindBackupStamp() == record.keys then self:RestoreKeybinds(false) end
		record.keys = nil
	end
	if store and not (record.keys or record.spells or record.premade or record.ranks) then
		for index = #store.history, 1, -1 do
			if store.history[index] == record then table.remove(store.history, index) end
		end
	end
	Report(L["Keys and spells put back as they were on %s."]:format(E:ShortDate(record.time)))
	if self.KeybindPreviewChanged then self:KeybindPreviewChanged() end
	return true
end

-- The last question before anything changes, with what Apply does.
function E:ConfirmKeysAndSpells(plan)
	if not plan then return end
	local c = plan.counts
	local parts = {}
	if c.keys > 0 then parts[#parts + 1] = E:Plural(c.keys, "%d key changes", "%d keys change"):format(c.keys) end
	local placed = c.spells + c.premade
	if placed > 0 then
		parts[#parts + 1] = E:Plural(placed, "%d class spell goes on an empty button", "%d class spells go on empty buttons"):format(placed)
	end
	if c.macros > 0 then parts[#parts + 1] = E:Plural(c.macros, "%d class macro is added", "%d class macros are added"):format(c.macros) end
	if c.ranks > 0 then
		parts[#parts + 1] = E:Plural(c.ranks, "%d button moves to its highest rank", "%d buttons move to their highest rank"):format(c.ranks)
	end
	local kept = #plan.protected
	if kept > 0 then parts[#parts + 1] = E:Plural(kept, "%d protected button or key stays", "%d protected buttons and keys stay"):format(kept) end
	if c.total == 0 then return end
	local text = L["Apply %s?\n\n%s.\n\nOnly empty buttons get a spell and your own actions stay. Your current keys are saved first, and Undo puts everything back."]:format(
		E:Highlight(L[plan.keys.title]), table.concat(parts, ", "))
	self:ShowConfirm({ title = L["Keys and spells"], text = text, accept = L["Apply"], data = plan,
		onAccept = function(data) E:ApplyKeysAndSpells(data) end })
end

-- The words for why a button or key stays as it is.
local PROTECTED_TEXT = {
	macro = Key("holds a macro"), item = Key("holds an item"), own = Key("holds your own action"),
	rank = Key("kept at its rank on purpose"), binding = Key("the key belongs to a manual bar"),
	macrorank = Key("a macro with a lower rank: update it in /eui macros"),
}
P.PROTECTED_TEXT = PROTECTED_TEXT

-- Where a slot is, in words: "Bar 2, button 4".
local function SlotWords(slot)
	local module = ActionBars()
	local gamepad = module and module.GamepadSlotIndex and module:GamepadSlotIndex(slot)
	if gamepad then return P.ControllerSlotWords and P.ControllerSlotWords(slot) or L["Gamepad bars, button %d"]:format(gamepad) end
	local button = (slot - 1) % 12 + 1
	local page = math.floor((slot - 1) / 12) + 1
	if page >= 7 and page <= 10 then return L["Bar 1 stance page %d, button %d"]:format(page - 6, button) end
	if page == 2 then return L["Bar %d page 2, button %d"]:format(1, button) end
	return L["Bar %d, button %d"]:format(E:KeybindSlotBar(slot) or 0, button)
end
P.SlotWords = SlotWords

-- One line per protected button or key.
function P.ProtectedLines(plan)
	local out = {}
	for _, entry in ipairs(plan.protected) do
		local where = entry.slot and SlotWords(entry.slot) or KeyWord(entry.key)
		local what = entry.name and (" (" .. entry.name .. ")") or ""
		local reason = entry.rankMacro and "macrorank" or entry.reason
		out[#out + 1] = ("%s%s: %s"):format(where, what, E:Translate(PROTECTED_TEXT[reason] or reason))
	end
	return out
end

-- A rank upgrade in words: where, and from which rank to which.
function P.RankText(entry)
	local module = ActionBars()
	local from = module and module.RankLabel and module.RankLabel(entry.from, entry.name) or entry.name or "?"
	local to = module and module.RankLabel and module.RankLabel(entry.to, entry.name) or entry.name or "?"
	local text = L["%s: %s to %s"]:format(SlotWords(entry.slot), from, to)
	if not entry.managed then text = text .. " " .. L["(a manual bar: changes only when you check it)"] end
	return text
end

-- What the class setup adds, in lines.
function P.PremadeLines(plan)
	local out = {}
	if plan.counts.premade > 0 then
		local names = {}
		for _, bar in ipairs(plan.premade.bars) do names[#names + 1] = bar.name or SpellNameOf(bar.spell) or tostring(bar.spell) end
		out[#out + 1] = L["Class setup spells on empty buttons of bar 1: %s."]:format(table.concat(names, ", "))
	end
	if plan.premade.adds > 0 then
		local names = {}
		for _, macro in ipairs(plan.premade.macros) do
			if macro.status == "add" then names[#names + 1] = macro.name end
		end
		local text = plan.opts.macros and L["Class macros added: %s."] or L["Class macros you can add with the box above: %s."]
		out[#out + 1] = text:format(table.concat(names, ", "))
	end
	return out
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local win

local function NewText(parent, size, kind, justify)
	local fs = Kit().Text(parent, size or E.tokens.size.body, justify or "LEFT", kind)
	return fs
end

local function Wrap(fs, width)
	fs:SetWordWrap(true)
	fs:SetWidth(math.max(width, 10))
	return math.ceil(fs:GetStringHeight() or 0)
end

-- A one-line text at its token size, made smaller when it is wider than
-- its box (Large text on a narrow key cap).
local function FitText(fs, width, size)
	E:SetWindowFont(fs, size)
	local w = fs:GetStringWidth() or 0
	if width > 0 and w > width then
		E:SetWindowFont(fs, math.max(1, math.floor(size * width / w)))
	end
end

-- The layout drawn: the keyboard of the chosen layout.
local function Layout()
	return E.keyboardLayouts[P.keyboard or ""] or E.keyboardLayouts[E:KeyboardGuess()]
end

local function PaintCap(cap)
	local K = Kit()
	local d = cap.detail
	local back = E.media.backdropColor
	if cap.kind == "movement" or cap.kind == "layer" then
		cap:SetBackdropColor(E:SelectedTabColor(0.85))
		cap:SetBackdropBorderColor(K.Accent())
	elseif cap.kind == "fixed" then
		cap:SetBackdropColor(back[1], back[2], back[3], 0.3)
		cap:SetBackdropBorderColor(unpack(E.media.borderColor))
	else
		cap:SetBackdropColor(back[1], back[2], back[3], 0.6)
		cap:SetBackdropBorderColor(unpack(E.media.borderColor))
	end
	local busy = d and d.kind ~= "free"
	K.Paint(cap.label, cap.kind == "fixed" and "dim" or busy and "body" or "dim")
	-- Game shortcuts have their own color on every layer.
	local tagKind = "secondary"
	if cap.kind == "movement" then tagKind = "header"
	elseif cap.kind == "game" or cap.kind == "home" or cap.kind == "character" then tagKind = "good"
	elseif cap.kind == "page" then tagKind = "warn" end
	K.Paint(cap.tag, tagKind)
end

local function Select(kind, key)
	if not key then return end
	P.selected = key
	if win then P.Refresh() end
end
P.Select = Select

-- The chord of a drawn key on the layer shown ("SHIFT-R" on Shift).
function P.ChordOf(key)
	local layer = LAYERS[P.layer] or LAYERS[1]
	local plan = P.plan
	-- Movement and Character keys are plain keys on every layer.
	if plan and plan.byKey and plan.byKey[key] and plan.byKey[key].kind and plan.byKey[key].kind ~= "home" then return key end
	return layer.prefix .. key
end

local function BuildCap(parent, info)
	local cap = CreateFrame("Button", nil, parent)
	E:SetTemplate(cap, true)
	cap.info = info
	cap.key, cap.place, cap.fixed = info.name, info.place, info.fixed
	cap.label = NewText(cap, E.tokens.size.body, "body")
	cap.label:SetPoint("TOPLEFT", 4, -3)
	cap.tag = NewText(cap, E.tokens.size.small, "secondary", "CENTER")
	cap.tag:SetPoint("BOTTOMLEFT", 2, 3)
	cap.tag:SetPoint("BOTTOMRIGHT", -2, 3)
	cap.tag:SetWordWrap(false)
	-- A shape that says "this key changes", "kept" or "hidden", never color alone.
	cap.mark = NewText(cap, E.tokens.size.small, "header", "RIGHT")
	cap.mark:SetPoint("TOPRIGHT", -3, -3)
	cap:SetScript("OnClick", function(self)
		if self.key and not self.fixed then Select("key", P.ChordOf(self.key)) end
	end)
	cap:SetScript("OnEnter", function(self)
		local K = Kit()
		K.AnchorTooltip(self, GameTooltip)
		if self.fixed or not self.key then
			K.TipTitle(GameTooltip, self.label:GetText() or "")
			K.TipText(GameTooltip, self.key and L["A key the key sets never take."] or L["No key here can be bound alone on this keyboard."])
			GameTooltip:Show()
			return
		end
		P.hover = P.ChordOf(self.key)
		P.Highlight()
		local lines = P.DetailLines(P.plan, P.ChordOf(self.key))
		K.TipTitle(GameTooltip, lines.title)
		for _, line in ipairs(lines) do K.TipPair(GameTooltip, line.label, line.value) end
		GameTooltip:Show()
	end)
	cap:SetScript("OnLeave", function()
		P.hover = nil
		P.Highlight()
		GameTooltip:Hide()
	end)
	E:SkinHoverPress(cap)
	return cap
end

local function BuildTile(parent, bar, button)
	local tile = CreateFrame("Button", nil, parent)
	tile.bar, tile.button = bar, button
	tile.slot = Kit().Icon(tile, 20)
	tile.slot:SetPoint("TOP", 0, -2)
	tile.chord = NewText(tile, E.tokens.size.small, "body", "CENTER")
	tile.chord:SetWordWrap(false)
	tile.short = NewText(tile, E.tokens.size.small, "secondary", "CENTER")
	tile.short:SetWordWrap(false)
	-- "+" on a button that gets its class spell when you apply, "~" on a
	-- button the layout hides (its key works).
	tile.mark = NewText(tile, E.tokens.size.small, "header", "RIGHT")
	tile.mark:SetPoint("TOPRIGHT", -2, -2)
	local function KeyOf(self)
		local entry = SlotEntry(P.plan, self.bar, self.button)
		return entry and entry.key
	end
	tile:SetScript("OnClick", function(self) Select("key", KeyOf(self)) end)
	tile:SetScript("OnEnter", function(self)
		P.hover = KeyOf(self)
		P.Highlight()
	end)
	tile:SetScript("OnLeave", function()
		P.hover = nil
		P.Highlight()
	end)
	return tile
end

-- The key caps of the chosen layout and the mouse: built once per layout.
local function BuildCaps()
	local layout = Layout()
	win.capsFor = win.capsFor or {}
	if win.caps then
		for _, cap in ipairs(win.caps) do cap:Hide() end
	end
	local set = win.capsFor[layout.id]
	if not set then
		set = { caps = {}, mouse = {}, grid = {} }
		for r, row in ipairs(layout.rows) do
			local x = 0
			for i, info in ipairs(row) do
				x = x + (info.gap or 0)
				local cap = BuildCap(win.body, info)
				cap.row, cap.col, cap.x, cap.width = r, i, x, info.width or 1
				x = x + (info.width or 1)
				set.caps[#set.caps + 1] = cap
			end
		end
		win.capsFor[layout.id] = set
	end
	if not win.mouseCaps then
		win.mouseCaps, win.gridCaps = {}, {}
		local rows = { m4 = 1, m5 = 2, m3 = 3, wu = 4, wd = 5 }
		for _, info in ipairs(E.keyboardMouse) do
			if rows[info.place] then
				local cap = BuildCap(win.body, info)
				cap.mouseRow = rows[info.place]
				win.mouseCaps[#win.mouseCaps + 1] = cap
			end
		end
		for i = 1, 12 do
			local cap = BuildCap(win.body, { place = "g" .. i, legend = tostring(i) })
			cap.gridIndex = i
			win.gridCaps[i] = cap
		end
	end
	win.caps = {}
	for _, cap in ipairs(set.caps) do
		cap:Show()
		win.caps[#win.caps + 1] = cap
	end
	for _, cap in ipairs(win.mouseCaps) do
		cap:Show()
		win.caps[#win.caps + 1] = cap
	end
	local grid = P.plan and P.plan.preset.grid
	for _, cap in ipairs(win.gridCaps) do
		cap.key = E:KeyboardKeyName(cap.place, layout.id)
		cap:SetShown(grid and true or false)
		if grid then win.caps[#win.caps + 1] = cap end
	end
	win.capsLayout = layout.id
end

local function Build()
	local K = Kit()
	win = K.CreateToolWindow("EldoUI_KeybindPreview", { title = L["Key sets"], width = 900, height = 680, strata = "DIALOG",
		footer = K.TOOL_FOOTER, resizable = { minWidth = 760, minHeight = 460 }, onClose = function() P.hover = nil end })
	P.window = win
	win.area = K.ScrollArea(win.content)
	win.area:SetAllPoints()
	local c = win.area.child
	win.body = c

	local chips = {}
	for _, id in ipairs(E.keybindPresetOrder) do
		local preset = E.keybindPresets[id]
		chips[#chips + 1] = { id, preset.recommended and L["%s (recommended)"]:format(L[preset.title]) or L[preset.title], L[preset.desc] }
	end
	win.templates = K.ChipBar(c, { chips = chips, selected = P.id, onChange = function(_, key)
		P.id = key
		wipe(P.take)
		win.templates:SetSelected(key)
		P.Refresh()
	end })
	local layers = {}
	for index, layer in ipairs(LAYERS) do layers[#layers + 1] = { index, L[layer.label], L[layer.tip] } end
	win.layers = K.ChipBar(c, { chips = layers, selected = P.layer, onChange = function(_, key)
		P.layer = key
		win.layers:SetSelected(key)
		P.Refresh()
	end })
	win.summary = NewText(c, E.tokens.size.body, "body")
	win.keyboardLabel = K.SectionLabel(c, L["Keyboard"])
	local boards = {}
	for _, id in ipairs(E.keyboardLayoutOrder) do
		local layout = E.keyboardLayouts[id]
		boards[#boards + 1] = { id, L[layout.title], L[layout.desc] }
	end
	win.keyboards = K.ChipBar(c, { chips = boards, selected = E:KeyboardGuess(), onChange = function(_, key)
		E.keymapOptionProxy.keyboard = key
		P.Refresh()
	end })
	win.check = K.Button(c, { text = L["Check my keyboard"],
		tip = L["Press three keys, and EldoUI finds your keyboard layout from the names the game reports."],
		onClick = function() E:OpenKeyboardCheck() end })
	win.view = K.ChipBar(c, { chips = {
		{ "keyboard", L["Keyboard"], L["Your key set: the keys of bars 1 to 3 and the class spells on them."] },
		{ "controller", L["Controller"], L["The game's controller bars: your class spells in the same order, for play with a controller."] },
	}, selected = P.view or "keyboard", onChange = function(_, key)
		P.view = key
		win.view:SetSelected(key)
		P.Refresh()
	end })
	win.gameLabel = K.SectionLabel(c, L["Game keys"])
	win.gameLines = {}
	win.barsLabel = K.SectionLabel(c, L["Main action block"])
	win.rows, win.tiles = {}, {}
	for bar = 1, 3 do
		local label = NewText(c, E.tokens.size.small, "secondary")
		win.rows[bar] = label
		for button = 1, 12 do
			local tile = BuildTile(c, bar, button)
			win.tiles[#win.tiles + 1] = tile
		end
	end
	win.manual = NewText(c, E.tokens.size.small, "secondary")
	win.detailLabel = K.SectionLabel(c, L["Selected key"])
	win.detail = CreateFrame("Frame", nil, c)
	E:SetTemplate(win.detail, true)
	win.detailTitle = NewText(win.detail, E.tokens.size.cardTitle, "body")
	win.detailLines = {}
	win.howLabel = K.SectionLabel(c, L["How to play"])
	win.how = {}
	win.changesLabel = K.SectionLabel(c, L["Changes before you apply"])
	win.spellsCheck = K.Check(c, L["Also put class spells on empty buttons"],
		L["Your known class spells go on the empty buttons of their category on bars 1 to 3. A button with your own action keeps it, and a spell already on your bars is not moved."],
		function(on)
			P.spells = on and true or false
			P.Refresh()
		end)
	win.macrosCheck = K.Check(c, L["Also add the class macros"],
		L["Your class setup's character macros, each under its own name. A macro you already have by that name is never changed."],
		function(on)
			P.macros = on and true or false
			P.Refresh()
		end)
	win.thumbCheck = K.Check(c, L["Mouse 4 and 5 for interrupt and movement"],
		L["A/D strafe only: Mouse 4 and Mouse 5 press buttons 6 and 7 of bars 1 to 3, with Shift and Ctrl for bars 2 and 3."],
		function(on)
			if E.db and E.db.keymap then E.db.keymap.thumb = on and true or false end
			P.Refresh()
		end)
	win.pageCheck = K.Check(c, L["Turn off the bar page keys"],
		L["Shift + mouse wheel and Shift + arrow keys would swap bar 1's spells in a fight. With this on, a key set takes them off."],
		function(on)
			E.keymapOptionProxy.pageKeysOff = on and true or false
			P.Refresh()
		end)
	win.changes = {}
	win.consumableOn = K.Button(c, { text = L["Turn on the Consumable Bar"],
		tip = L["Your potion, healthstone and mana potion or bandage on a small bar, each used by one key of bar 3."],
		onClick = function()
			E:SetModuleEnabled("ConsumableBar", true)
			P.Refresh()
		end })
	win.ranksLabel = K.SectionLabel(c, L["Spell ranks"])
	win.ranksNone = NewText(c, E.tokens.size.body, "secondary")
	win.rankRows = {}
	win.protectedLabel = K.SectionLabel(c, L["Kept as they are"])
	win.protectedLines = {}
	win.ring = K.FocusRing(c)
	win.link = K.FocusRing(c)
	if P.BuildController then P.BuildController(win, c) end

	win.apply = K.Button(win.footer, { text = L["Apply"], kind = "primary",
		tip = L["Asks once more, then sets the keys shown, the class spells and macros you checked and the checked spell ranks."],
		onClick = function()
			-- The question names what the bars and keys hold right now.
			P.Refresh()
			if P.view == "controller" and P.ConfirmController then return P.ConfirmController() end
			E:ConfirmKeysAndSpells(P.combined)
		end })
	win.apply:SetPoint("RIGHT", -28, 0)
	win.restore = K.Button(win.footer, { text = L["Undo last Apply"],
		tip = L["Put back the keys, spells, macros and ranks of the last Apply. A button or key you changed since stays yours."],
		onClick = function()
			E:RunOutOfCombat(function() E:RestoreKeysAndSpells(function(text, warn) E:ConfigNotice(text, warn) end) end, "KeybindPreview:restore")
		end })
	win.restore:SetPoint("RIGHT", win.apply, "LEFT", -8, 0)
	win.takeBack = K.Button(win.footer, { text = L["Take back spells"], tip = L["Take the class spells this window placed off your bars again. A button you changed since keeps your action."],
		onClick = function()
			local controller = P.view == "controller"
			E:RunOutOfCombat(function()
				local Report = function(text, warn) E:ConfigNotice(text, warn) end
				if controller then E:RevertGamepadSpells(P.ControllerNotice) else E:RevertKeybindSpells(Report) end
			end, controller and "KeybindPreview:padspells" or "KeybindPreview:spells")
		end })
	win.takeBack:SetPoint("RIGHT", win.restore, "LEFT", -8, 0)
	win.footerText:ClearAllPoints()
	win.footerText:SetPoint("LEFT", 12, 0)
	win.footerText:SetPoint("RIGHT", win.takeBack, "LEFT", -8, 0)

	-- Arrows move between keys, Tab and Shift-Tab switch the layer. Other
	-- keys go on to the game.
	win.keys = K.KeyHandler(win, function(name)
		if P.view == "controller" then return false end
		if name == "TAB" or name == "SHIFT-TAB" then
			local count = #LAYERS
			P.layer = (P.layer + (name == "TAB" and 0 or count - 2)) % count + 1
			win.layers:SetSelected(P.layer)
			P.Refresh()
			return true
		end
		local dir = ({ LEFT = { 0, -1 }, RIGHT = { 0, 1 }, UP = { -1, 0 }, DOWN = { 1, 0 } })[name]
		if not dir then return false end
		P.Move(dir[1], dir[2])
		return true
	end)
	win.area:HookScript("OnSizeChanged", function() if win:IsShown() then P.Layout() end end)
	-- Apply and Undo change many keys and buttons at once, and each change
	-- sends one of these events: the window draws again once after the
	-- burst, not once per key (a full plan each time froze the game).
	win:RegisterEvent("UPDATE_BINDINGS")
	win:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
	win:SetScript("OnEvent", function(self)
		if self:IsShown() then P.QueueRefresh() end
	end)
	E:RegisterThemed(win, function(self) if self:IsShown() then P.Refresh() end end)
	return win
end

-- Keyboard moves: the next key cap left, right, up or down (keys that can
-- be bound only).
function P.Move(dRow, dCol)
	local layout = Layout()
	local chord = P.selected or "R"
	local key = chord:match("^[A-Z]+%-(.+)$") or chord
	local row, col = 3, 5
	for r, data in ipairs(layout.rows) do
		for i, info in ipairs(data) do if info.name == key and not info.fixed then row, col = r, i end end
	end
	local rows = layout.rows
	row = math.max(2, math.min(#rows - 1, row + dRow))
	col = math.max(1, math.min(#rows[row], col + dCol))
	local info = rows[row][col]
	-- Step over keys a set never takes.
	local step = dCol ~= 0 and dCol or 1
	while info and (info.fixed or not info.name) do
		col = col + step
		info = rows[row][col]
	end
	if info then Select("key", P.ChordOf(info.name)) end
end

-- The ring on the selected key cap and tile, the second ring on what the
-- pointer links to (a key cap's button or a button's key cap).
function P.Highlight()
	if not win then return end
	if P.view == "controller" then
		win.ring:Attach(nil)
		win.link:Attach(nil)
		return
	end
	local function CapFor(chord)
		local plain = chord and (chord:match("^[A-Z]+%-(.+)$") or chord)
		for _, cap in ipairs(win.caps or {}) do if cap.key == plain and not cap.fixed then return cap end end
	end
	local function TileFor(chord)
		local entry = chord and P.plan.byKey[chord]
		if not (entry and entry.bar) then return nil end
		return win.tiles[(entry.bar - 1) * 12 + entry.button]
	end
	local selected = P.selected
	win.ring:Attach(CapFor(selected) or nil)
	local hover = P.hover or selected
	win.link:Attach(TileFor(hover) or nil)
end

-- Place everything for the width shown (Large text widens key caps and
-- tiles; the page scrolls when it gets taller than the window).
function P.Layout()
	if not win then return end
	local c = win.body
	local width = math.floor(win.area.scroll:GetWidth() or 0)
	if width < 50 then width = (win:GetWidth() or 900) - 2 * Kit().TOOL_PAD - 16 end
	c:SetWidth(width)
	local scale = E:TextScale()
	local y = -PAD
	local labelH = math.ceil(E.tokens.size.small * scale) + 6
	-- Chips follow the text size: measure and line them up again.
	for _, bar in ipairs({ win.templates, win.layers, win.keyboards, win.view }) do
		local x = 0
		for _, chip in ipairs(bar.chips) do
			local h = math.ceil(E.tokens.size.small * scale) + 8
			chip:SetSize(math.ceil(chip.text:GetStringWidth()) + 12, h)
			chip:ClearAllPoints()
			chip:SetPoint("LEFT", bar, "LEFT", x, 0)
			x = x + chip:GetWidth() + 4
		end
		bar:SetSize(math.max(x - 4, 1), math.ceil(E.tokens.size.small * scale) + 8)
	end
	local chipH = win.templates:GetHeight()
	local function Place(region, x, h)
		region:ClearAllPoints()
		region:SetPoint("TOPLEFT", c, "TOPLEFT", x or 0, y)
		y = y - (h or 0)
	end
	if P.view == "controller" and P.LayoutController then
		Place(win.summary, 0, Wrap(win.summary, width) + 10)
		Place(win.view, 0, chipH + 8)
		y = P.LayoutController(win, c, width, y, labelH)
		c:SetHeight(-y + PAD)
		win.area:Update()
		P.Highlight()
		return
	end
	Place(win.templates, 0, 0)
	win.layers:ClearAllPoints()
	if win.templates:GetWidth() + win.layers:GetWidth() + 16 <= width then
		win.layers:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, y)
		y = y - chipH - 8
	else
		y = y - chipH - 6
		win.layers:SetPoint("TOPLEFT", c, "TOPLEFT", 0, y)
		y = y - chipH - 8
	end
	Place(win.summary, 0, Wrap(win.summary, width) + 10)
	-- The Keyboard | Controller switch, above the keyboard's row.
	Place(win.view, 0, chipH + 8)
	Place(win.keyboardLabel, 0, labelH)
	-- The layout chips, with Check my keyboard after them (or below).
	Place(win.keyboards, 0, 0)
	win.check:ClearAllPoints()
	if win.keyboards:GetWidth() + win.check:GetWidth() + 12 <= width then
		win.check:SetPoint("LEFT", win.keyboards, "RIGHT", 12, 0)
		y = y - math.max(chipH, win.check:GetHeight()) - 8
	else
		y = y - chipH - 6
		win.check:SetPoint("TOPLEFT", c, "TOPLEFT", 0, y)
		y = y - win.check:GetHeight() - 8
	end
	-- Key caps: 15 key widths for the keyboard, one more for the mouse
	-- column and three for the side grid of the mouse set.
	local grid = P.plan and P.plan.preset.grid
	local units = 15 + 1.5 + (grid and 3.5 or 0)
	local cap = math.floor(math.min(52 * scale, (width + GAP) / units - GAP))
	P.capSize = cap
	local step = cap + GAP
	local smallSize, bodySize = E.tokens.size.small, E.tokens.size.body
	local top = y
	local rowsCount = #Layout().rows
	-- The key caps exist once the keyboard view has drawn; the first Show
	-- (and the controller view) lays out before that.
	for _, button in ipairs(win.caps or {}) do
		local w, x, rowY
		if button.gridIndex then
			local i = button.gridIndex - 1
			w = cap
			x = math.floor((16.75 + (i % 3)) * step)
			rowY = 1 + math.floor(i / 3)
		elseif button.mouseRow then
			w = math.floor(1.25 * step - GAP)
			x = math.floor(15.25 * step)
			rowY = button.mouseRow
		else
			w = math.floor(button.width * step - GAP)
			x = math.floor(button.x * step)
			rowY = button.row - 1
		end
		button:SetSize(w, cap)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", c, "TOPLEFT", x, top - rowY * step)
		FitText(button.label, w - 8, bodySize)
		FitText(button.tag, w - 4, smallSize)
		FitText(button.mark, w / 2, smallSize)
	end
	y = top - rowsCount * step - 8
	-- The game keys card: two columns when there is room.
	Place(win.gameLabel, 0, labelH)
	local columns = width >= 600 and 2 or 1
	local colW = math.floor((width - (columns - 1) * 16) / columns)
	local shown = {}
	for _, fs in ipairs(win.gameLines) do if fs:IsShown() then shown[#shown + 1] = fs end end
	local perColumn = math.ceil(#shown / columns)
	local colTop, tallest = y, 0
	for index, fs in ipairs(shown) do
		local column = math.floor((index - 1) / math.max(perColumn, 1))
		if (index - 1) % math.max(perColumn, 1) == 0 then y = colTop end
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", c, "TOPLEFT", column * (colW + 16), y)
		y = y - Wrap(fs, colW) - 2
		tallest = math.max(tallest, colTop - y)
	end
	y = colTop - tallest - 8
	Place(win.barsLabel, 0, labelH)
	local tileW = math.floor((width - 11 * GAP) / 12)
	local icon = math.floor(math.min(28 * scale, tileW - 8))
	local tileH = icon + math.ceil(E.tokens.size.small * scale) * 2 + 10
	P.tileWidth, P.tileHeight = tileW, tileH
	for bar = 1, 3 do
		Place(win.rows[bar], 0, Wrap(win.rows[bar], width) + 4)
		for button = 1, 12 do
			local tile = win.tiles[(bar - 1) * 12 + button]
			tile:SetSize(tileW, tileH)
			tile:ClearAllPoints()
			tile:SetPoint("TOPLEFT", c, "TOPLEFT", (button - 1) * (tileW + GAP), y)
			tile.slot:SetSize(icon, icon)
			tile.chord:ClearAllPoints()
			tile.chord:SetPoint("TOP", tile.slot, "BOTTOM", 0, -2)
			tile.chord:SetWidth(tileW)
			FitText(tile.chord, tileW, smallSize)
			tile.short:ClearAllPoints()
			tile.short:SetPoint("TOP", tile.chord, "BOTTOM", 0, -1)
			tile.short:SetWidth(tileW)
			FitText(tile.short, tileW, smallSize)
		end
		y = y - tileH - GAP
	end
	Place(win.manual, 0, Wrap(win.manual, width) + 10)
	Place(win.detailLabel, 0, labelH)
	local inner = width - 16
	local dy = -8
	win.detailTitle:ClearAllPoints()
	win.detailTitle:SetPoint("TOPLEFT", win.detail, "TOPLEFT", 8, dy)
	dy = dy - Wrap(win.detailTitle, inner) - 6
	for _, line in ipairs(win.detailLines) do
		if line:IsShown() then
			line:ClearAllPoints()
			line:SetPoint("TOPLEFT", win.detail, "TOPLEFT", 8, dy)
			dy = dy - Wrap(line, inner) - 4
		end
	end
	win.detail:ClearAllPoints()
	win.detail:SetPoint("TOPLEFT", c, "TOPLEFT", 0, y)
	win.detail:SetSize(width, -dy + 4)
	y = y - (-dy + 4) - 10
	Place(win.howLabel, 0, labelH)
	for _, line in ipairs(win.how) do
		if line:IsShown() then Place(line, 0, Wrap(line, width) + 4) end
	end
	y = y - 6
	Place(win.changesLabel, 0, labelH)
	for _, check in ipairs({ win.spellsCheck, win.macrosCheck, win.thumbCheck, win.pageCheck }) do
		if check:IsShown() then
			Place(check, 0, math.max(check:GetHeight(), math.ceil(check.label:GetStringHeight() or 0)) + 6)
		end
	end
	for _, row in ipairs(win.changes) do
		if row:IsShown() then
			local textX = row.check:IsShown() and (row.check:GetWidth() + 4) or 0
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", c, "TOPLEFT", 0, y)
			row.text:ClearAllPoints()
			row.text:SetPoint("TOPLEFT", row, "TOPLEFT", textX, -3)
			local h = math.max(Wrap(row.text, width - textX), row.check:IsShown() and row.check:GetHeight() or 0)
			row:SetSize(width, h + 4)
			y = y - h - 6
		end
	end
	if win.consumableOn:IsShown() then Place(win.consumableOn, 0, win.consumableOn:GetHeight() + 6) end
	y = y - 6
	P.ranksTop = -y
	Place(win.ranksLabel, 0, labelH)
	if win.ranksNone:IsShown() then Place(win.ranksNone, 0, Wrap(win.ranksNone, width) + 6) end
	for _, row in ipairs(win.rankRows) do
		if row:IsShown() then
			local keepW = math.ceil(row.keep:GetWidth())
			local textX = row.check:GetWidth() + 4
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", c, "TOPLEFT", 0, y)
			row.text:ClearAllPoints()
			row.text:SetPoint("TOPLEFT", row, "TOPLEFT", textX, -3)
			local h = math.max(Wrap(row.text, width - textX - keepW - 8), row.check:GetHeight(), row.keep:GetHeight())
			row:SetSize(width, h + 4)
			y = y - h - 6
		end
	end
	y = y - 6
	Place(win.protectedLabel, 0, labelH)
	for _, line in ipairs(win.protectedLines) do
		if line:IsShown() then Place(line, 0, Wrap(line, width) + 4) end
	end
	c:SetHeight(-y + PAD)
	win.area:Update()
	P.Highlight()
end

local function ChangeRow(index)
	local row = win.changes[index]
	if row then return row end
	row = CreateFrame("Frame", nil, win.body)
	row.text = NewText(row, E.tokens.size.body, "body")
	row.check = Kit().Check(row, "", L["Give this key to the key set. The manual bar loses it."], function(on)
		if row.takeKey then
			P.take[row.takeKey] = on or nil
			P.Refresh()
		end
	end)
	row.check:SetPoint("TOPLEFT", 0, 0)
	win.changes[index] = row
	return row
end

-- A spell rank row: the tick, the words and "Keep this rank".
local function RankRow(index)
	local row = win.rankRows[index]
	if row then return row end
	row = CreateFrame("Frame", nil, win.body)
	row.text = NewText(row, E.tokens.size.body, "body")
	row.check = Kit().Check(row, "", L["Move this button to the highest rank you know when you apply."], function(on)
		if row.slot then
			P.ranks[row.slot] = on and true or false
			P.Refresh()
		end
	end)
	row.check:SetPoint("TOPLEFT", 0, 0)
	row.keep = Kit().Button(row, { text = L["Keep this rank"],
		tip = L["Keeps this one button at its rank on purpose (a low rank for mana, for example). It is never upgraded or lit up until you change what it holds."],
		onClick = function()
			local module = E.modules and E.modules.ActionBars
			if row.slot and row.from and module and module.KeepRank then
				module:KeepRank(row.slot, row.from)
				P.ranks[row.slot] = nil
				P.Refresh()
			end
		end })
	row.keep:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
	win.rankRows[index] = row
	return row
end

-- The words of a bar's row: which keys press it.
local MOD_NAMES = { ["SHIFT-"] = Key("Shift"), ["CTRL-"] = Key("Ctrl"), ["ALT-"] = Key("Alt") }
local function BarRowText(plan, bar)
	local preset = plan.preset
	local layer = preset.layers[bar]
	local text
	if preset.grid and bar < 3 then
		text = layer.mod == "" and L["Bar %d: the side buttons"]:format(bar) or L["Bar %d: Shift + side button"]:format(bar)
	elseif layer.mod == "" then
		text = L["Bar %d: plain keys"]:format(bar)
	else
		text = L["Bar %d: %s + key"]:format(bar, L[MOD_NAMES[layer.mod]])
	end
	if bar == 3 then text = text .. "  " .. L["(keys 10 to 12: the Consumable Bar)"] end
	if not plan.capacity[bar].enabled then text = text .. "  " .. L["(turned off: no keys)"] end
	return text
end

local CONSUMABLE_ICONS
local function ConsumableIcon(key)
	if not CONSUMABLE_ICONS then
		CONSUMABLE_ICONS = {}
		local module = E.modules and E.modules.ConsumableBar
		for _, category in ipairs(module and module.CATEGORIES or {}) do CONSUMABLE_ICONS[category.key] = category.icon end
	end
	return CONSUMABLE_ICONS[key]
end

-- The keyboard view's parts, hidden while the Controller view shows. The
-- lists the refresh fills show only the rows in use again.
function P.ShowKeyboardView(on)
	for _, region in ipairs({ win.templates, win.layers, win.keyboardLabel, win.keyboards, win.check, win.gameLabel, win.barsLabel,
		win.manual, win.detailLabel, win.detail, win.howLabel, win.changesLabel, win.spellsCheck, win.pageCheck, win.ranksLabel,
		win.protectedLabel, win.restore }) do
		region:SetShown(on)
	end
	for _, list in ipairs({ win.rows, win.tiles }) do
		for _, region in ipairs(list) do region:SetShown(on) end
	end
	if not on then
		for _, list in ipairs({ win.caps or {}, win.gameLines, win.how, win.changes, win.rankRows, win.protectedLines }) do
			for _, region in ipairs(list) do region:Hide() end
		end
		for _, region in ipairs({ win.macrosCheck, win.thumbCheck, win.consumableOn, win.ranksNone }) do region:Hide() end
	end
	if P.ShowControllerView then P.ShowControllerView(win, not on) end
end

-- Rebuild the plan from the keys you have now and draw it.
function P.QueueRefresh()
	E:Debounce("KeybindPreview:refresh", 0.05, function()
		if win and win:IsShown() then P.Refresh() end
	end)
end

function P.Refresh()
	if not win then return end
	win.view:SetSelected(P.view or "keyboard")
	if P.view == "controller" and P.RefreshController then
		P.ShowKeyboardView(false)
		P.RefreshController(win)
		P.Layout()
		return
	end
	P.ShowKeyboardView(true)
	P.id = E:KeybindPresetKey(P.id) or E.keybindPresetOrder[1]
	P.keyboard = E:KeyboardGuess()
	local combined = E:KeysAndSpellsPlan({ id = P.id, take = P.take, spells = P.spells, macros = P.macros, ranks = P.ranks })
	P.combined = combined
	local plan = combined.keys
	P.plan = plan
	Index(plan)
	P.spellPlan = combined.spells
	local K = Kit()
	win.templates:SetSelected(P.id)
	win.layers:SetSelected(P.layer)
	win.keyboards:SetSelected(P.keyboard)
	local preset = plan.preset
	win:SetTitle(L["Key sets"], L[preset.title])
	win.summary:SetText(L[preset.movementText])
	BuildCaps()
	if type(P.selected) ~= "string" then
		local entry = SlotEntry(plan, 1, 6)
		local plain = entry and entry.key and (entry.key:match("^[A-Z]+%-(.+)$") or entry.key)
		P.selected = plain and P.ChordOf(plain) or nil
	end
	local layerOf = P.layer
	for _, cap in ipairs(win.caps) do
		if cap.fixed or not cap.key then
			cap.detail = nil
			cap.kind = (cap.fixed and LAYER_KEYS[cap.place] == layerOf) and "layer" or "fixed"
			cap.label:SetText(cap.info.legend and E:Translate(cap.info.legend) or "")
			cap.tag:SetText(cap.key and "" or L["no key"])
			cap.mark:SetText("")
		else
			local chord = P.ChordOf(cap.key)
			local d = P.Describe(plan, chord)
			cap.detail, cap.kind = d, d.kind
			local legend = cap.info.legend and E:Translate(cap.info.legend)
			cap.label:SetText(legend or E:KeybindKeyText(cap.key))
			cap.tag:SetText(d.tag or "")
			local mark = ""
			if d.visible == false and d.state ~= "off" then mark = "~"
			elseif d.state == "bind" or d.state == "unbind" then mark = "+"
			elseif d.state == "manual" or d.state == "taken" then mark = "M"
			elseif d.state == "off" then mark = "x" end
			cap.mark:SetText(mark)
		end
		PaintCap(cap)
	end
	-- The game keys card.
	local rows = E:GameKeysList(plan)
	for index, row in ipairs(rows) do
		local fs = win.gameLines[index]
		if not fs then
			fs = NewText(win.body, E.tokens.size.body, "body")
			win.gameLines[index] = fs
		end
		fs:SetText(E:GameKeyRowText(row))
		fs:Show()
	end
	for index = #rows + 1, #win.gameLines do win.gameLines[index]:Hide() end
	for bar = 1, 3 do
		win.rows[bar]:SetText(BarRowText(plan, bar))
		for button = 1, 12 do
			local tile = win.tiles[(bar - 1) * 12 + button]
			local entry = SlotEntry(plan, bar, button)
			local d = P.Describe(plan, entry and entry.key)
			local key = entry and entry.key
			if entry and entry.consumable then
				local text = CONSUMABLE_TEXT[entry.consumable]
				tile.slot:SetIcon(ConsumableIcon(entry.consumable))
				tile.slot.icon:SetDesaturated(entry.state == "free")
				tile.short:SetText(text and L[text.short] or "")
				tile.mark:SetText("")
				tile:SetAlpha(entry.state == "free" and E.tokens.disabledAlpha or 1)
			else
				local intended = d.intended or {}
				if d.kind == "free" and entry then
					intended = E.keybindCategories and E.keybindCategories.Resolve(bar, button, nil, Role()) or {}
					local info = intended.info
					d.tag = info and E:Translate(info.short) or ""
				end
				local icon = (intended.state == "ready" or intended.state == "unlearned") and intended.icon or d.icon
				tile.slot:SetIcon(icon)
				local hidden = entry and entry.visible == false
				tile.slot.icon:SetDesaturated(intended.state == "unlearned" or hidden)
				tile.short:SetText(d.tag or "")
				local spell = P.spellPlan and E:KeybindSpellEntry(P.spellPlan, bar, button)
				local mark = P.spells and spell and spell.status == "place" and "+" or ""
				if hidden and entry.state ~= "off" then mark = "~" end
				tile.mark:SetText(mark)
				tile:SetAlpha((entry and entry.state == "off") and E.tokens.disabledAlpha or 1)
			end
			tile.chord:SetText(key and E:KeybindKeyText(key) or L["no key"])
		end
	end
	win.manual:SetText(L["Bar 4 and the other bars: Manual. They keep their keys and spells; a key they hold stays theirs unless you give it below. A button marked ~ is hidden in this layout: its key works."])
	-- Selected key.
	local lines = P.DetailLines(plan, P.selected)
	win.detailTitle:SetText(lines.title or "")
	for index, line in ipairs(lines) do
		local fs = win.detailLines[index]
		if not fs then
			fs = NewText(win.detail, E.tokens.size.body, "body")
			win.detailLines[index] = fs
		end
		fs:SetText(("%s%s:|r %s"):format(E:TextHex("secondary"), line.label, line.value or ""))
		fs:Show()
	end
	for index = #lines + 1, #win.detailLines do win.detailLines[index]:Hide() end
	-- How to play.
	local how = P.HowToPlay(plan)
	for index, text in ipairs(how) do
		local fs = win.how[index]
		if not fs then
			fs = NewText(win.body, E.tokens.size.body, "body")
			win.how[index] = fs
		end
		fs:SetText("- " .. text)
		fs:Show()
	end
	for index = #how + 1, #win.how do win.how[index]:Hide() end
	-- Changes.
	local changes = P.ChangeLines(plan)
	if P.spells then
		for _, text in ipairs(P.PremadeLines(combined)) do
			if changes[1] and changes[1].text == L["Nothing else changes."] then table.remove(changes, 1) end
			changes[#changes + 1] = { text = text }
		end
	end
	for index, change in ipairs(changes) do
		local row = ChangeRow(index)
		row.text:SetText(change.text)
		row.takeKey = change.take
		row.check:SetShown(change.take ~= nil)
		row.check:SetChecked(change.take ~= nil and P.take[change.take] and true or false)
		row:Show()
	end
	for index = #changes + 1, #win.changes do win.changes[index]:Hide() end
	win.consumableOn:SetShown(not plan.consumableOn and E.modules and E.modules.ConsumableBar ~= nil)
	-- Spell ranks.
	local rankIndex = 0
	for _, entry in ipairs(combined.ranks) do
		if entry.status == "upgrade" then
			rankIndex = rankIndex + 1
			local row = RankRow(rankIndex)
			row.slot, row.from = entry.slot, entry.from
			row.text:SetText(P.RankText(entry))
			row.check:SetChecked(entry.tick)
			row:Show()
		end
	end
	for index = rankIndex + 1, #win.rankRows do win.rankRows[index]:Hide() end
	win.ranksNone:SetText(L["Every spell on your action bars uses the highest rank you know."])
	win.ranksNone:SetShown(rankIndex == 0)
	-- Protected buttons and keys.
	local protected = P.ProtectedLines(combined)
	if #protected == 0 then protected[1] = L["Nothing: every button and key in the plan is free to change."] end
	for index, text in ipairs(protected) do
		local fs = win.protectedLines[index]
		if not fs then
			fs = NewText(win.body, E.tokens.size.body, "body")
			win.protectedLines[index] = fs
		end
		fs:SetText("- " .. text)
		fs:Show()
	end
	for index = #protected + 1, #win.protectedLines do win.protectedLines[index]:Hide() end
	-- Footer.
	local counts = combined.counts
	local places = counts.spells + counts.premade
	local db = E.db and E.db.keymap or E.defaults.keymap
	win.spellsCheck:SetChecked(P.spells)
	win.macrosCheck:SetShown(combined.premade.adds > 0 or P.macros)
	win.macrosCheck:SetChecked(P.macros)
	win.thumbCheck:SetShown(preset.thumb and true or false)
	win.thumbCheck:SetChecked(db.thumb and true or false)
	win.pageCheck:SetChecked(db.pageKeys ~= "keep")
	local blocked, why
	if counts.total > 0 then blocked, why = E:KeysAndSpellsBlocked(combined) end
	local keyCounts = plan.counts
	local status = E:Plural(#plan.writes, "%d key changes", "%d keys change"):format(#plan.writes)
	local left = keyCounts.manual + keyCounts.off
	if left > 0 then
		status = status .. ", " .. E:Plural(left, "%d left alone", "%d left alone"):format(left)
	end
	if places > 0 then status = status .. ", " .. E:Plural(places, "%d spell placed", "%d spells placed"):format(places) end
	if counts.macros > 0 then status = status .. ", " .. E:Plural(counts.macros, "%d macro added", "%d macros added"):format(counts.macros) end
	if counts.ranks > 0 then status = status .. ", " .. E:Plural(counts.ranks, "%d rank upgraded", "%d ranks upgraded"):format(counts.ranks) end
	if blocked then status = why elseif plan.blocked then status = plan.blockedText end
	win.footerText:SetText(status)
	win.apply:SetEnabled(not blocked and counts.total > 0)
	win.restore:SetEnabled(E:HasKeysAndSpells())
	win.takeBack:SetShown(E:HasKeybindSpells())
	K.Paint(win.footerText, (blocked or plan.blocked) and "warn" or "secondary")
	P.Layout()
	-- Opened for the ranks: show them first.
	if P.focus == "ranks" and P.ranksTop and win.area.SetScroll then
		P.focus = nil
		win.area:SetScroll(P.ranksTop)
	end
end

function E:OpenKeybindPreview(id)
	local key = id and self:KeybindPresetKey(id)
	if key and key ~= P.id then
		P.id = key
		wipe(P.take)
		P.selected = nil
	end
	if P.view == nil then P.view = E:GamepadUIActive() and "controller" or "keyboard" end
	if not win then Build() end
	win:Open()
	P.Refresh()
	return win
end

-- focus: "ranks" opens it at the spell ranks. opts: id (preset), spells,
-- macros (the boxes) and ranks (the ticks), as the setup's Keys and
-- spells step passes them; view ("keyboard" or "controller") opens that
-- view.
function E:OpenKeysAndSpells(focus, opts)
	opts = opts or {}
	if opts.spells ~= nil then P.spells = opts.spells and true or false end
	if opts.macros ~= nil then P.macros = opts.macros and true or false end
	if opts.view == "keyboard" or opts.view == "controller" then P.view = opts.view end
	if opts.ranks then
		wipe(P.ranks)
		for slot, tick in pairs(opts.ranks) do P.ranks[slot] = tick end
	end
	P.focus = focus
	return self:OpenKeybindPreview(opts.id)
end

function E:CloseKeybindPreview()
	if win and win:IsShown() then win:Hide() end
end

-- Keys changed elsewhere (apply, restore, the keyboard): draw the new plan
-- once the writes are done, in a run of its own. Drawing inside the writer
-- built the whole plan again before the restore had finished, and the
-- game stopped the script half way.
function E:KeybindPreviewChanged()
	if win and win:IsShown() then P.QueueRefresh() end
end
