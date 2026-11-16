-- EldoUI key sets: five ways to put keys on the main action block, bars 1
-- to 3 (bar 1 and bar 2 with 12 buttons, bar 3 with 9) and the three
-- Consumable Bar keys after them. Bar 4 and every other bar stay manual:
-- the sets never write their keys and never take a key from them unless
-- you choose so.
--
-- A set stores key places (Data/KeyboardLayouts.lua), not letters, so it
-- keeps the same fingers on every keyboard: one key list per bar, each
-- with its modifier. The keys belong to the button numbers, so a layout
-- switch never changes a key, and a button a layout hides keeps its key.
--
--   E:KeybindPlan(id[, opts])       what a set would do, read only and
--                                   worked out from your current keys:
--                                   slots (with visible = false for a
--                                   button the layout hides), movement,
--                                   where every game shortcut it takes
--                                   goes, keys of manual bars it leaves
--                                   alone. opts: keyboard, thumb, pageKeys,
--                                   take (manual keys you give it)
--   E:ApplyKeybindPlan(plan[, spells])  the keys, out of combat, with an
--                                   empty cursor, after checking the plan
--                                   still matches your keys; backs them up
--                                   first. spells: a class spell plan
--                                   (Core/KeybindSpells.lua) to place on
--                                   empty buttons in the same step
--   E:RestoreKeybinds([report])     back to the keys before the last set
--                                   (each earlier set can be undone too)
--   E:GameKeysList([plan])          the game keys card: bags, map and the
--                                   other shortcuts, read live, and where
--                                   a set moves them
--   E:OpenKeybindPreview([id])      the keys and spells preview (Core/KeybindPreview.lua)
--
-- Only key bindings change here, plus the class spells when the player
-- ticks them in the preview (empty buttons only). Bar positions never
-- change, and nothing is applied without the player pressing Apply.
-- "I manage my own keys" (keymap.preset "none") and the gamepad UI stop
-- every key write; the preview still shows your keys.
local _, E = ...
local L = E.L

local Key = E.Key
-- Binding commands and action pages of action bars 1-8 (the action slot of
-- button n on a bar is (page - 1) * 12 + n).
local BARS = {
	{ binding = "ACTIONBUTTON", page = 1 },
	{ binding = "MULTIACTIONBAR1BUTTON", page = 6 },
	{ binding = "MULTIACTIONBAR2BUTTON", page = 5 },
	{ binding = "MULTIACTIONBAR3BUTTON", page = 3 },
	{ binding = "MULTIACTIONBAR4BUTTON", page = 4 },
	{ binding = "MULTIACTIONBAR5BUTTON", page = 13 },
	{ binding = "MULTIACTIONBAR6BUTTON", page = 14 },
	{ binding = "MULTIACTIONBAR7BUTTON", page = 15 },
}
E.keybindBars = BARS
-- The bars a set binds; every other bar is manual.
E.keybindManagedBars = { 1, 2, 3 }
-- Action buttons a set binds per bar: bar 3 is the 9-button box, and its
-- keys 10 to 12 press the Consumable Bar instead.
E.keybindBarButtons = { 12, 12, 9 }
-- The modifier each bar has in most sets (the side-button mouse set has
-- its own).
E.keybindLayers = {
	{ key = "base", prefix = "", label = "Base" },
	{ key = "shift", prefix = "SHIFT-", label = "Shift" },
	{ key = "ctrl", prefix = "CTRL-", label = "Ctrl" },
}

-- Bar 3's keys 10 to 12: the Consumable Bar button each one presses
-- (EldoUI_ConsumableButton<button>), by category. Warriors and Rogues use
-- no mana: their third key is the bandage.
E.keybindConsumableKeys = {
	{ key = "healthPotion", button = 3 },
	{ key = "healthstone", button = 6 },
	{ key = "manaPotion", button = 4, WARRIOR = { key = "bandage", button = 5 }, ROGUE = { key = "bandage", button = 5 } },
}

function E:KeybindActionSlot(bar, button)
	local info = BARS[bar]
	return info and (info.page - 1) * 12 + button or nil
end

-- The game's binding commands this file writes (the Forever client's own
-- names, as its key binding list shows them).
local CMD = {
	forward = "MOVEFORWARD", backward = "MOVEBACKWARD", turnLeft = "TURNLEFT", turnRight = "TURNRIGHT",
	strafeLeft = "STRAFELEFT", strafeRight = "STRAFERIGHT", character = "TOGGLECHARACTER0", sheath = "TOGGLESHEATH",
}
E.keybindCommands = CMD

-- Places (Data/KeyboardLayouts.lua) the sets use.
local function NumberRow(i) return "r1c" .. i end
local Q, W, KE, R, T = "r2c1", "r2c2", "r2c3", "r2c4", "r2c5"
local A, S, D, F, G = "r3c1", "r3c2", "r3c3", "r3c4", "r3c5"
local Z, X, C, V = "r4c1", "r4c2", "r4c3", "r4c4"
local N1, N2, N3, N4, N5 = NumberRow(1), NumberRow(2), NumberRow(3), NumberRow(4), NumberRow(5)
-- The fixed homes of two game shortcuts: the Character pane on the comma's
-- place, Sheath on the period's place.
local COMMA, PERIOD = "r4c8", "r4c9"

local function Same3(keys)
	return { { mod = "", keys = keys }, { mod = "SHIFT-", keys = keys }, { mod = "CTRL-", keys = keys } }
end
local GRID = {}
for i = 1, 12 do GRID[i] = "g" .. i end
local NUMBERS = {}
for i = 1, 12 do NUMBERS[i] = NumberRow(i) end

-- The sets. id stays the same across versions; version goes up when the
-- keys of a set change, and the backup records which one you took.
-- layers: per bar, its modifier and the places of its 12 keys (bar 3
-- keys 10-12: the Consumable Bar). movement: the movement keys it sets,
-- by place (modified movement keys are never touched). hand: the places
-- the movement hand rests on; no button ever gets one of them.
E.keybindPresets = {
	movement = {
		version = 3,
		recommended = true,
		title = "Classic movement",
		desc = "W and S move, A and D turn, Q and E strafe. Bar 1: 1-5 R F G V X Z C, bar 2: Shift + the same keys, bar 3: Ctrl + the same keys. Character moves to the comma key.",
		short = Key("W S move, A D turn. Bar 1: 1-5 R F G V X Z C."),
		movementText = Key("W and S move forward and back, A and D turn, Q and E strafe: the game's own movement keys."),
		layers = Same3({ N1, N2, N3, N4, N5, R, F, G, V, X, Z, C }),
		movement = { [W] = CMD.forward, [S] = CMD.backward, [A] = CMD.turnLeft, [D] = CMD.turnRight, [Q] = CMD.strafeLeft, [KE] = CMD.strafeRight },
		hand = { W, A, S, D, Q, KE },
	},
	strafe = {
		version = 3,
		title = "A/D strafe",
		desc = "W and S move, A and D strafe, and you turn with the mouse. Bar 1: 1-5 R F E Q Z X C, bar 2: Shift + the same keys, bar 3: Ctrl + the same keys. Character moves to the comma key.",
		short = Key("W S move, A D strafe. Bar 1: 1-5 R F E Q Z X C."),
		movementText = Key("W and S move forward and back, A and D strafe. You turn with the right mouse button held, which frees Q and E for abilities."),
		layers = Same3({ N1, N2, N3, N4, N5, R, F, KE, Q, Z, X, C }),
		movement = { [A] = CMD.strafeLeft, [D] = CMD.strafeRight },
		hand = { W, A, S, D },
		-- Mouse 4 and Mouse 5 can take buttons 6 and 7 (the thumb option).
		thumb = true,
	},
	numbers = {
		version = 3,
		title = "Number row",
		desc = "Bar 1: 1 to =, bar 2: Shift + 1 to =, bar 3: Ctrl + 1 to =. Movement keys stay as they are.",
		short = Key("Bar 1: 1 to =. Shift and Ctrl for bars 2 and 3."),
		movementText = Key("Your movement keys stay as they are. The keys 7 to = sit farther from your movement hand."),
		layers = Same3(NUMBERS),
		movement = {},
		hand = { W, A, S, D, Q, KE },
	},
	mouse = {
		version = 1,
		title = "Side-button mouse",
		desc = "For a mouse with 12 side buttons that send 1 to =. Bar 1: the side buttons, bar 2: Shift + the side buttons, bar 3: Q E R F T, Mouse 4, G Z X C V, Mouse 5. W and S move, A and D strafe.",
		short = Key("Bar 1 on 12 side buttons, Shift for bar 2."),
		movementText = Key("W and S move forward and back, A and D strafe, and you turn with the mouse. The side buttons send the number row keys, so 1 to = on the keyboard press the same buttons."),
		layers = {
			{ mod = "", keys = GRID },
			{ mod = "SHIFT-", keys = GRID },
			{ mod = "", keys = { Q, KE, R, F, T, "m4", G, Z, X, C, V, "m5" } },
		},
		movement = { [A] = CMD.strafeLeft, [D] = CMD.strafeRight },
		hand = { W, A, S, D },
		grid = true,
	},
	esdf = {
		version = 1,
		title = "Shifted hand",
		desc = "Your hand rests one key to the right: E and D move, S and F strafe, and you turn with the mouse. Bar 1: R T G W 2 Q A V C X Z 4, bar 2: Shift + the same keys, bar 3: Ctrl + the same keys.",
		short = Key("E D move, S F strafe. Bar 1: R T G W 2 Q A V C X Z 4."),
		movementText = Key("E and D move forward and back, S and F strafe, and you turn with the mouse. W, A and Q become spell keys; 1, 3, 5 and 6 stay free for your own bars."),
		layers = Same3({ R, T, G, W, N2, Q, A, V, C, X, Z, N4 }),
		movement = { [KE] = CMD.forward, [D] = CMD.backward, [S] = CMD.strafeLeft, [F] = CMD.strafeRight },
		hand = { KE, D, S, F },
	},
}
E.keybindPresetOrder = { "movement", "strafe", "numbers", "mouse", "esdf" }
-- Older and other names (slash command words, saved choices).
E.keybindPresetAliases = { pro = "strafe", classic = "numbers", wasd = "movement", number = "numbers", grid = "mouse", shifted = "esdf" }
for id, preset in pairs(E.keybindPresets) do
	preset.id = id
	-- base: the twelve keys of bar 1 as on a US keyboard, for help texts.
	preset.base = {}
	for button, place in ipairs(preset.layers[1].keys) do
		preset.base[button] = E:KeyboardKeyName(place, "us") or place
	end
end

-- Keys a set never takes, and that no shortcut is moved onto: system keys
-- by name, the game window keys by place (B M N P L O J Y U H I K on a US
-- keyboard).
local RESERVED_NAMES = {
	ESCAPE = true, ENTER = true, PRINTSCREEN = true, TAB = true, SPACE = true, NUMLOCK = true, BACKSPACE = true,
	CAPSLOCK = true, LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
	["/"] = true, NUMPADDIVIDE = true, NUMPADENTER = true, BUTTON1 = true, BUTTON2 = true, ["ALT-Z"] = true,
}
for i = 1, 12 do RESERVED_NAMES["F" .. i] = true end
local RESERVED_PLACES = {
	r4c5 = true, r4c7 = true, r4c6 = true, r2c10 = true, r3c9 = true, r2c9 = true,
	r3c7 = true, r2c6 = true, r2c7 = true, r3c6 = true, r2c8 = true, r3c8 = true,
}
E.keybindReserved = { names = RESERVED_NAMES, places = RESERVED_PLACES }

-- True for a chord ("ALT-Z", "TAB") or a place no set may take.
function E:KeybindReservedKey(chord, place)
	if place and RESERVED_PLACES[place] then return true end
	if type(chord) ~= "string" then return false end
	if RESERVED_NAMES[chord] then return true end
	local plain = chord:match("^.*%-(.+)$") or chord
	return RESERVED_NAMES[plain] or false
end

function E:KeybindPresetKey(id)
	if type(id) ~= "string" then return nil end
	id = id:lower()
	if self.keybindPresets[id] then return id end
	-- A set's title as the page shows it ("classic movement", "a/d strafe").
	for key, preset in pairs(self.keybindPresets) do
		if id == preset.title:lower() or id == L[preset.title]:lower() then return key end
	end
	local alias = self.keybindPresetAliases[id]
	return alias and self.keybindPresets[alias] and alias or nil
end

-- The saved key map choices, with what a plan was asked for on top.
local function Settings()
	local db = E.db and E.db.keymap
	return type(db) == "table" and db or E.defaults.keymap
end

local function Options(opts)
	opts = opts or {}
	local db = Settings()
	local keyboard = opts.keyboard
	if not (type(keyboard) == "string" and E.keyboardLayouts[keyboard]) then keyboard = E:KeyboardGuess() end
	local thumb = opts.thumb
	if thumb == nil then thumb = db.thumb end
	local pageKeys = opts.pageKeys or db.pageKeys
	if pageKeys ~= "keep" then pageKeys = "off" end
	return { keyboard = keyboard, thumb = thumb and true or false, pageKeys = pageKeys, take = opts.take or {} }
end

-- The place of a button's key in a set (the thumb option moves buttons 6
-- and 7 of the A/D strafe set to Mouse 4 and Mouse 5).
function E:KeybindSlotPlace(preset, bar, button, thumb)
	local layer = preset and preset.layers[bar]
	if not layer then return nil end
	if thumb and preset.thumb then
		if button == 6 then return "m4", layer.mod end
		if button == 7 then return "m5", layer.mod end
	end
	return layer.keys[button], layer.mod
end

-- The key of a slot: "SHIFT-R" for bar 2 button 6 of A/D strafe, nil when
-- the keyboard has no usable key in that place. opts: keyboard, thumb.
function E:KeybindSlotKey(preset, bar, button, opts)
	if type(preset) == "string" then preset = self.keybindPresets[self:KeybindPresetKey(preset) or ""] end
	if not preset then return nil end
	local o = Options(opts)
	local place, mod = self:KeybindSlotPlace(preset, bar, button, o.thumb)
	local name = place and self:KeyboardKeyName(place, o.keyboard)
	return name and mod .. name or nil
end

---------------------------------------------------------------------------
-- Reading the current keys
---------------------------------------------------------------------------
local function Plain(value)
	if E.Secret and E.Secret(value) then return nil end
	return value
end

local function ActionOf(key)
	if type(key) ~= "string" or type(GetBindingAction) ~= "function" then return "" end
	local ok, action = pcall(GetBindingAction, key)
	action = ok and Plain(action) or nil
	return type(action) == "string" and action or ""
end
E.KeybindActionOf = function(_, key) return ActionOf(key) end

function E:KeybindCommandName(command)
	if type(command) ~= "string" or command == "" then return L["nothing"] end
	local name = type(GetBindingName) == "function" and Plain(GetBindingName(command))
	if type(name) == "string" and name ~= "" then return name end
	return command
end

-- The key as the game writes it ("Shift-R", ",").
function E:KeybindKeyText(key)
	if type(key) ~= "string" then return "" end
	local text = type(GetBindingText) == "function" and Plain(GetBindingText(key, "KEY_"))
	if type(text) == "string" and text ~= "" then return text end
	return key
end

local function PlayerClass()
	if type(UnitClass) ~= "function" then return nil end
	local _, class = UnitClass("player")
	return Plain(class)
end

-- The Consumable Bar entry of bar 3 key 10, 11 or 12 for a class: its
-- category key, the button and the binding command.
function E:KeybindConsumable(index, class)
	local entry = self.keybindConsumableKeys[index]
	if not entry then return nil end
	local own = entry[class or PlayerClass() or ""]
	if own then entry = own end
	return entry.key, entry.button, ("CLICK EldoUI_ConsumableButton%d:LeftButton"):format(entry.button)
end

function E:KeybindConsumableBarOn()
	local module = self.modules and self.modules.ConsumableBar
	return module and module.IsEnabled and module:IsEnabled() and true or false
end

-- A command of a bar the sets leave alone (bars 4-8, the pet bar, the
-- stance bar, pet commands): its bar number, or "pet" / "stance".
local function ManualBar(command)
	if type(command) ~= "string" then return nil end
	for index = 4, #BARS do
		if command:match("^" .. BARS[index].binding .. "%d+$") then return index end
	end
	if command:match("^BONUSACTIONBUTTON%d+$") or command:match("^PET") then return "pet" end
	if command:match("^SHAPESHIFTBUTTON%d+$") then return "stance" end
	return nil
end
E.KeybindManualBar = function(_, command) return ManualBar(command) end

-- A command of the managed bars (bars 1-3) or of the Consumable Bar
-- buttons: its bar and button.
local function ManagedButton(command)
	if type(command) ~= "string" then return nil end
	for _, index in ipairs(E.keybindManagedBars) do
		local button = command:match("^" .. BARS[index].binding .. "(%d+)$")
		if button then return index, tonumber(button) end
	end
	local consumable = command:match("^CLICK EldoUI_ConsumableButton(%d+):LeftButton$")
	if consumable then return "consumable", tonumber(consumable) end
	return nil
end

local MOVEMENT_COMMANDS = {
	MOVEFORWARD = true, MOVEBACKWARD = true, TURNLEFT = true, TURNRIGHT = true, STRAFELEFT = true, STRAFERIGHT = true,
}
-- Commands that get no new key when a set takes theirs: movement (the set
-- sets its own) and bar 1's page keys (EldoUI shows bars 1 to 3 at once).
local function NoHome(command)
	if MOVEMENT_COMMANDS[command] then return true end
	if command:match("^ACTIONPAGE%d+$") or command == "NEXTACTIONPAGE" or command == "PREVIOUSACTIONPAGE" then return true end
	return ManualBar(command) ~= nil and not command:match("^BONUSACTIONBUTTON%d+$")
end

-- The game's own pet bar keys: Ctrl + the number row, button n on the
-- n-th key. Those move as one row to Alt + the same keys.
local function PetRowIndex(key, command, keyboard)
	local n = type(command) == "string" and tonumber(command:match("^BONUSACTIONBUTTON(%d+)$"))
	if not (n and n >= 1 and n <= 10) then return nil end
	local name = E:KeyboardKeyName(NumberRow(n), keyboard)
	return name and key == "CTRL-" .. name and n or nil
end

-- Whether a button of an On bar is drawn. Every button of an On bar has
-- its key; a layout may still hide it.
local function ButtonShown(module, db, bar, button)
	if not (module and module.active) then return true end
	if type(module.ButtonShown) == "function" then
		local ok, shown = pcall(module.ButtonShown, module, bar, button)
		if ok then return shown and true or false end
		return true
	end
	if db and db.shown == false then return false end
	return button <= ((db and db.buttons) or 12)
end

-- Which managed bars are On, how many action buttons a set binds on each
-- (12, 12, 9) and which of them show. With the Action Bars module off the
-- game's own bars 1-3 hold them.
function E:KeybindBarCapacity()
	local bars = {}
	local module = self.modules and self.modules.ActionBars
	for _, index in ipairs(self.keybindManagedBars) do
		local count = self.keybindBarButtons[index] or 12
		local db = module and module.active and module.db.bars and module.db.bars[index]
		local enabled = true
		if module and module.active then enabled = db and db.enabled and true or false end
		local shown = {}
		for button = 1, count do shown[button] = enabled and ButtonShown(module, db, index, button) or false end
		bars[index] = { enabled = enabled, buttons = enabled and count or 0, shown = shown }
	end
	return bars
end

-- Why no set may write a key now, or nil: "gamepad" (the gamepad UI is
-- on) or "none" (you manage your own keys), with the line to show.
function E:KeymapStandsDown()
	if self.GamepadUIActive and self:GamepadUIActive() then
		return "gamepad", L["The gamepad UI is on, so the key sets stand down: your controller keeps its own buttons."]
	end
	if Settings().preset == "none" then
		return "none", L["You manage your own keys, so EldoUI writes no key. Untick \"I manage my own keys\" on the Keybinds page to use a key set."]
	end
	return nil
end

---------------------------------------------------------------------------
-- The plan (read only)
---------------------------------------------------------------------------
local PAGE_KEYS = { "SHIFT-MOUSEWHEELUP", "SHIFT-MOUSEWHEELDOWN", "SHIFT-UP", "SHIFT-DOWN" }
local PAGE_COMMANDS = { NEXTACTIONPAGE = true, PREVIOUSACTIONPAGE = true }

-- opts.take: { [key] = true } keys of manual bars the player chose to give
-- to the set (without it, those keys stay where they are).
function E:KeybindPlan(id, opts)
	id = self:KeybindPresetKey(id)
	local preset = id and self.keybindPresets[id]
	if not preset then return nil end
	local o = Options(opts)
	local take, keyboard = o.take, o.keyboard
	local thumb = o.thumb and preset.thumb and true or false
	local consumableOn = self:KeybindConsumableBarOn()
	local plan = { id = id, version = preset.version, preset = preset, title = preset.title, keyboard = keyboard,
		opts = { keyboard = keyboard, thumb = thumb, pageKeys = o.pageKeys, take = take }, consumableOn = consumableOn,
		slots = {}, moves = {}, homes = {}, pages = {}, writes = {}, displaced = {}, manual = {}, hidden = {}, off = {},
		free = {}, noKey = {}, capacity = self:KeybindBarCapacity(),
		counts = { bind = 0, same = 0, manual = 0, hidden = 0, off = 0, free = 0, nokey = 0, taken = 0, nohome = 0, unbind = 0 } }
	local seen, sig, written = {}, {}, {}
	local function Look(key)
		if type(key) ~= "string" then return "" end
		if not seen[key] then
			seen[key] = ActionOf(key)
			sig[#sig + 1] = key .. "=" .. seen[key]
		end
		return seen[key]
	end
	local function Write(key, command)
		plan.writes[#plan.writes + 1] = { key = key, command = command }
		written[key] = true
	end
	-- What a key loses: a manual bar's key is kept unless taken; a game
	-- command (not a button of bars 1-3, which get their own keys) is listed
	-- and gets its fixed new key below.
	local function Decide(entry)
		local current = Look(entry.key)
		entry.current, entry.currentName = current, self:KeybindCommandName(current)
		if current == entry.command then
			entry.state = "same"
			return
		end
		local manual = ManualBar(current)
		if manual == "pet" and PetRowIndex(entry.key, current, keyboard) then manual = nil end
		if manual and not take[entry.key] then
			entry.state, entry.manualBar = "manual", manual
			plan.manual[#plan.manual + 1] = entry
			return
		end
		entry.state = "bind"
		Write(entry.key, entry.command)
		if current ~= "" and not ManagedButton(current) then
			plan.displaced[#plan.displaced + 1] = { key = entry.key, command = current, name = entry.currentName,
				manualBar = manual, by = entry }
		end
	end
	local function Current(entry)
		local current = Look(entry.key)
		entry.current, entry.currentName = current, self:KeybindCommandName(current)
	end
	for _, bar in ipairs(self.keybindManagedBars) do
		local capacity = plan.capacity[bar]
		local count = self.keybindBarButtons[bar] or 12
		for button = 1, 12 do
			local place, mod = self:KeybindSlotPlace(preset, bar, button, thumb)
			local name = self:KeyboardKeyName(place, keyboard)
			local entry = { bar = bar, button = button, place = place, mod = mod, key = name and mod .. name or nil, visible = true }
			plan.slots[#plan.slots + 1] = entry
			if button > count then
				-- Bar 3 keys 10-12: the Consumable Bar.
				local category, consumable, command = self:KeybindConsumable(button - count)
				entry.consumable, entry.consumableButton, entry.command = category, consumable, command
				if not entry.key then
					entry.state = "nokey"
					plan.noKey[#plan.noKey + 1] = entry
				elseif not consumableOn then
					-- The module is off: the key stays as it is, free.
					entry.state = "free"
					Current(entry)
					plan.free[#plan.free + 1] = entry
				else
					Decide(entry)
				end
			else
				entry.command = BARS[bar].binding .. button
				entry.action = self:KeybindActionSlot(bar, button)
				if not capacity.enabled then
					-- A bar you turned off gets no key.
					entry.state, entry.visible = "off", false
					Current(entry)
					plan.off[#plan.off + 1] = entry
				elseif not entry.key then
					entry.state = "nokey"
					plan.noKey[#plan.noKey + 1] = entry
				else
					entry.visible = capacity.shown[button] ~= false
					Decide(entry)
					if not entry.visible then plan.hidden[#plan.hidden + 1] = entry end
				end
			end
		end
	end
	local movementPlaces = {}
	for place in pairs(preset.movement) do movementPlaces[#movementPlaces + 1] = place end
	table.sort(movementPlaces)
	for _, place in ipairs(movementPlaces) do
		local name = self:KeyboardKeyName(place, keyboard)
		local entry = { key = name, place = place, command = preset.movement[place], kind = "movement" }
		plan.moves[#plan.moves + 1] = entry
		if name then Decide(entry) else entry.state = "nokey" plan.noKey[#plan.noKey + 1] = entry end
	end
	-- Every shortcut the set takes gets one fixed new key, the same in every
	-- set: the same key with Alt; the Character pane on the comma's place,
	-- Sheath on the period's place; the pet bar on Alt + the number row. A
	-- new key that holds something of yours is never taken.
	local homeOf, handNames = {}, {}
	for _, place in ipairs(preset.hand or {}) do
		local name = self:KeyboardKeyName(place, keyboard)
		if name then handNames[name] = true end
	end
	for _, entry in ipairs(plan.moves) do if entry.key then handNames[entry.key] = true end end
	local function AddHome(command, home, lost, pet)
		if homeOf[command] then
			if lost then lost.movedTo, lost.home = homeOf[command].movedTo, homeOf[command] end
			return homeOf[command]
		end
		local entry = { key = home, command = command, kind = command == CMD.character and "character" or "home",
			from = lost and lost.key, lost = lost, pet = pet }
		homeOf[command] = entry
		if lost then lost.home = entry end
		-- A movement key with a modifier is never touched: no new key there.
		local plain = home and (home:match("^.*%-(.+)$") or home)
		if home and plain ~= home and handNames[plain] then
			entry.state, entry.key = "nohome", nil
			if lost then lost.noHome = home end
			plan.homes[#plan.homes + 1] = entry
			return entry
		end
		if not home or self:KeybindReservedKey(home) or written[home] then
			entry.state = "taken"
			if lost then lost.homeTaken = home or "" end
			plan.homes[#plan.homes + 1] = entry
			return entry
		end
		local current = Look(home)
		entry.current, entry.currentName = current, self:KeybindCommandName(current)
		local manual = ManualBar(current)
		if current == command then
			entry.state = "same"
		elseif current == "" or (manual and take[home]) then
			entry.state = "bind"
			Write(home, command)
		elseif manual then
			entry.state, entry.manualBar = "manual", manual
			plan.manual[#plan.manual + 1] = entry
		else
			entry.state = "taken"
		end
		if entry.state == "same" or entry.state == "bind" then
			entry.movedTo = home
			if lost then lost.movedTo = home end
		elseif lost and entry.state == "taken" then
			lost.homeTaken = home
		end
		plan.homes[#plan.homes + 1] = entry
		return entry
	end
	local petMoved = false
	for _, lost in ipairs(plan.displaced) do
		local command = lost.command
		if command == CMD.character then
			plan.character = AddHome(command, self:KeyboardKeyName(COMMA, keyboard), lost)
		elseif command == CMD.sheath then
			AddHome(command, self:KeyboardKeyName(PERIOD, keyboard), lost)
		elseif PetRowIndex(lost.key, command, keyboard) then
			local n = PetRowIndex(lost.key, command, keyboard)
			lost.pet = true
			petMoved = true
			AddHome(command, "ALT-" .. self:KeyboardKeyName(NumberRow(n), keyboard), lost, true)
		elseif not NoHome(command) then
			AddHome(command, "ALT-" .. lost.key, lost)
		end
	end
	-- The pet bar moves as one row: its keys the set did not take get the
	-- Alt keys too, so Alt-1 to Alt-0 all work.
	if petMoved then
		plan.petMoved = true
		for n = 1, 10 do
			local name = self:KeyboardKeyName(NumberRow(n), keyboard)
			local command = "BONUSACTIONBUTTON" .. n
			if name and not homeOf[command] and Look("CTRL-" .. name) == command then AddHome(command, "ALT-" .. name, nil, true) end
		end
	end
	-- Bar page keys: Shift + wheel and Shift + arrows would swap bar 1's
	-- spells in a fight; "off" takes them off with the set.
	if o.pageKeys == "off" then
		for _, key in ipairs(PAGE_KEYS) do
			local current = Look(key)
			if PAGE_COMMANDS[current] then
				local entry = { key = key, kind = "page", current = current, currentName = self:KeybindCommandName(current), state = "unbind" }
				plan.pages[#plan.pages + 1] = entry
				plan.writes[#plan.writes + 1] = { key = key, command = nil, unbind = true }
			end
		end
	end
	for _, list in ipairs({ plan.slots, plan.moves, plan.homes, plan.pages }) do
		for _, entry in ipairs(list) do plan.counts[entry.state] = (plan.counts[entry.state] or 0) + 1 end
	end
	plan.counts.hidden = #plan.hidden
	for _, bar in ipairs(self.keybindManagedBars) do
		local capacity = plan.capacity[bar]
		local shown = {}
		for button = 1, #capacity.shown do shown[button] = capacity.shown[button] and "1" or "0" end
		sig[#sig + 1] = ("bar%d=%s:%d:%s"):format(bar, tostring(capacity.enabled), capacity.buttons, table.concat(shown))
	end
	for key in pairs(take) do sig[#sig + 1] = "take=" .. key end
	table.sort(sig)
	local why, text = self:KeymapStandsDown()
	if why then
		-- Nothing can be written: the plan only shows what the set is.
		plan.blocked, plan.blockedText, plan.wouldWrite = why, text, #plan.writes
		plan.writes = {}
	end
	plan.signature = ("%s@%d|%s|%s|%s|%s|%s|"):format(id, preset.version, keyboard, tostring(thumb), o.pageKeys,
		tostring(consumableOn), tostring(why)) .. table.concat(sig, ";")
	return plan
end

---------------------------------------------------------------------------
-- Backup, apply and restore (keys only)
---------------------------------------------------------------------------
local BACKUP_DEPTH = 5

local function CopyTable2(source)
	if type(source) ~= "table" then return source end
	local out = {}
	for key, value in pairs(source) do out[key] = CopyTable2(value) end
	return out
end

local function Backup(applied, plan)
	local saved = {}
	local count = type(GetNumBindings) == "function" and GetNumBindings() or 0
	for i = 1, count do
		local command, _, key1, key2 = GetBinding(i)
		if key1 then saved[#saved + 1] = { command, key1, key2 } end
	end
	EldoUIDB.keybindBackup = EldoUIDB.keybindBackup or {}
	local previous = EldoUIDB.keybindBackup[E.charKey]
	-- stamp: tells this backup apart, so an Undo of the keys and spells
	-- preview only ever restores the backup its own Apply made.
	local stamp = ("%d.%d"):format(time(), math.floor((GetTime() or 0) * 1000))
	local private = E:GetPrivate("keymap")
	-- written: what the set put on each key ("" for a key it cleared), so
	-- Undo leaves a key alone that the player changed since.
	local written = {}
	for _, write in ipairs(plan and plan.writes or {}) do
		if write.key then written[write.key] = write.command or "" end
	end
	local backup = { bindings = saved, applied = applied, written = written, time = time(), template = plan and plan.id, version = plan and plan.version, stamp = stamp,
		-- The key map choice before this Apply, put back by Undo.
		keymap = { preset = Settings().preset, applied = private and CopyTable2(private.applied) or nil } }
	-- Earlier backups stay behind this one, so each set can be undone in turn.
	if type(previous) == "table" then
		backup.previous = previous
		local depth, node = 1, backup
		while node.previous do
			depth = depth + 1
			if depth >= BACKUP_DEPTH then node.previous = nil break end
			node = node.previous
		end
	end
	EldoUIDB.keybindBackup[E.charKey] = backup
	return backup
end

-- The stamp of the newest keybind backup of this character, or nil.
function E:KeybindBackupStamp()
	if not (EldoUIDB and type(EldoUIDB.keybindBackup) == "table" and type(EldoUIDB.keybindBackup[self.charKey]) == "table") then return nil end
	return EldoUIDB.keybindBackup[self.charKey].stamp
end

-- The set id of the newest keybind backup of this character, or nil.
function E:KeybindBackupTemplate()
	if not (EldoUIDB and type(EldoUIDB.keybindBackup) == "table" and type(EldoUIDB.keybindBackup[self.charKey]) == "table") then return nil end
	return EldoUIDB.keybindBackup[self.charKey].template
end

local function CursorBusy()
	if type(GetCursorInfo) ~= "function" then return false end
	local ok, kind = pcall(GetCursorInfo)
	return ok and kind ~= nil
end

-- Why a plan can't be applied right now, or nil.
function E:KeybindApplyBlocked(plan)
	if InCombatLockdown() then return "combat", L["Keybinds can't change in combat."] end
	local why, text = self:KeymapStandsDown()
	if why then return why, text end
	if CursorBusy() then return "cursor", L["Put down what is on your cursor first."] end
	local fresh = plan and self:KeybindPlan(plan.id, plan.opts)
	if not fresh then return "missing", L["This key set is not there any more."] end
	if fresh.signature ~= plan.signature then return "stale", L["Your keys changed since the preview. Look at the preview again before you apply."] end
	return nil
end

-- Other parts of EldoUI follow key map changes through one callback:
-- E:OnKeymapChange(fn) calls fn(kind, ...) with
--   "applied", plan, result, opts  after an Apply that went through (opts
--                                  .quiet: a step of a bigger Apply that
--                                  shows its own alert)
--   "restored", backup             after Restore or the alert's Undo put
--                                  keys back (backup.template, .version:
--                                  the set that was taken back)
-- An Apply that is refused (combat, cursor, a stale plan) calls nothing.
-- Returns a function that takes fn off again.
local listeners = {}
function E:OnKeymapChange(fn)
	if type(fn) ~= "function" then return function() end end
	listeners[#listeners + 1] = fn
	return function()
		for index = #listeners, 1, -1 do
			if listeners[index] == fn then table.remove(listeners, index) end
		end
	end
end

local function Notify(kind, ...)
	for _, fn in ipairs(listeners) do
		local ok, err = pcall(fn, kind, ...)
		if not ok then geterrorhandler()(err) end
	end
end

-- What the last Apply did, for the character: the set, its version and
-- plan, and the keys it wrote.
local function Record(plan)
	local db = E.db and E.db.keymap
	if type(db) == "table" then db.preset = plan.id end
	local private = E:GetPrivate("keymap")
	if type(private) ~= "table" then return end
	local keys = {}
	for _, write in ipairs(plan.writes) do keys[write.key] = write.command or "" end
	private.applied = { preset = plan.id, version = plan.version, signature = plan.signature, time = time(), keys = keys }
end

-- Apply a plan made by E:KeybindPlan, and with spells (a plan made by
-- E:KeybindSpellPlan) the class spells on empty buttons too. Both are
-- checked before anything changes. Returns true and the counts, or false
-- and why. opts.quiet: no alert (the keys and spells Apply shows one for
-- everything it did).
function E:ApplyKeybindPlan(plan, spells, opts)
	if not plan then return false, "missing" end
	local keys = not spells or #plan.writes > 0
	local why, notice
	if keys then why, notice = self:KeybindApplyBlocked(plan) end
	if not why and spells then why, notice = self:KeybindSpellsBlocked(spells) end
	if why then
		self:ConfigNotice(notice, true)
		return false, why
	end
	local result = { done = 0, failed = 0, skipped = plan.counts.manual + plan.counts.off, same = plan.counts.same }
	local parts = {}
	if keys then
		local applied = {}
		for _, write in ipairs(plan.writes) do applied[#applied + 1] = write.key end
		result.stamp = Backup(applied, plan).stamp
		for _, write in ipairs(plan.writes) do
			if SetBinding(write.key, write.command) == false then result.failed = result.failed + 1 else result.done = result.done + 1 end
		end
		SaveBindings(GetCurrentBindingSet())
		local done, failed = result.done, result.failed
		local text = L["%s applied: %s."]:format(E:Highlight(L[plan.title]), E:Plural(done, "%d key set", "%d keys set"):format(done))
		if result.skipped > 0 then text = text .. " " .. E:Plural(result.skipped, "%d left alone.", "%d left alone."):format(result.skipped) end
		if failed > 0 then text = text .. " " .. E:Plural(failed, "%d could not be set.", "%d could not be set."):format(failed) end
		local moved = {}
		for _, entry in ipairs(plan.displaced) do
			if entry.movedTo then
				moved[#moved + 1] = ("%s (%s > %s)"):format(entry.name, self:KeybindKeyText(entry.key), self:KeybindKeyText(entry.movedTo))
			else
				moved[#moved + 1] = ("%s (%s)"):format(entry.name, self:KeybindKeyText(entry.key))
			end
		end
		if #moved > 0 then text = text .. "\n" .. L["Keys taken from: %s"]:format(table.concat(moved, ", ")) end
		parts[#parts + 1] = text
	end
	if not plan.blocked then Record(plan) end
	if spells then
		local _, placed = self:ApplyKeybindSpells(spells, false)
		result.spells = placed
		local count = placed and placed.placed or 0
		parts[#parts + 1] = E:Plural(count, "%d class spell placed on an empty button.", "%d class spells placed on empty buttons."):format(count)
		if placed and placed.failed > 0 then
			parts[#parts + 1] = E:Plural(placed.failed, "%d spell could not be placed.", "%d spells could not be placed."):format(placed.failed)
		end
	end
	result.text = table.concat(parts, "\n")
	Notify("applied", plan, result, opts)
	if opts and opts.quiet then
		if self.KeybindPreviewChanged then self:KeybindPreviewChanged() end
		return true, result
	end
	local placedAny = result.spells and result.spells.placed > 0
	self:PushAlert({
		key = "keybind-preset",
		title = L["Key sets"],
		text = table.concat(parts, "\n"),
		actions = {
			{ label = L["Undo"], tip = placedAny and L["Put back the keys you had before and take the placed spells off again."]
				or L["Put back the keys you had before this key set."],
				func = function()
					E:RunOutOfCombat(function()
						if keys then E:RestoreKeybinds(false) end
						if placedAny then E:RevertKeybindSpells(false) end
					end, "KeybindPresets:undo")
				end },
			{ label = L["Keep"] },
		},
	})
	if self.KeybindPreviewChanged then self:KeybindPreviewChanged() end
	return true, result
end

-- The older one-call form (plugins, tests): plan and apply at once.
function E:ApplyKeybindPreset(id)
	local plan = self:KeybindPlan(id)
	if not plan then return end
	return (self:ApplyKeybindPlan(plan))
end

-- report: how to tell the player the result: nil prints it (the slash
-- command), a function(text, warn) shows it (the options window), false
-- says nothing (the alert's Undo button; the alert closing is enough).
-- Returns true when the keys came back.
function E:RestoreKeybinds(report)
	local function Report(text, warn)
		if report == false then return end
		if type(report) == "function" then report(text, warn) else self:Print(text) end
	end
	local backup = EldoUIDB.keybindBackup and EldoUIDB.keybindBackup[self.charKey]
	if not backup then
		Report(L["There is no keybind backup for this character."], true)
		return false
	end
	if InCombatLockdown() then
		Report(L["Keybinds can't change in combat."], true)
		return false
	end
	local kept = 0
	local written = type(backup.written) == "table" and backup.written
	if written then
		-- Only the keys that still hold what the set wrote go back; a key
		-- changed by hand since stays the player's.
		local before = {}
		for _, entry in ipairs(backup.bindings or {}) do
			if entry[2] then before[entry[2]] = entry[1] end
			if entry[3] then before[entry[3]] = entry[1] end
		end
		for _, keyName in ipairs(backup.applied or {}) do
			local now = GetBindingAction and GetBindingAction(keyName) or ""
			if (now or "") == (written[keyName] or "") then
				SetBinding(keyName)
				if before[keyName] then SetBinding(keyName, before[keyName]) end
			else
				kept = kept + 1
			end
		end
	else
		-- A backup from an older version: every key from its snapshot.
		for _, keyName in ipairs(backup.applied or {}) do SetBinding(keyName) end
		for _, entry in ipairs(backup.bindings or {}) do
			SetBinding(entry[2], entry[1])
			if entry[3] then SetBinding(entry[3], entry[1]) end
		end
	end
	SaveBindings(GetCurrentBindingSet())
	-- The key map choice goes back to what it was before that Apply.
	if type(backup.keymap) == "table" then
		local db = self.db and self.db.keymap
		if type(db) == "table" and type(backup.keymap.preset) == "string" then db.preset = backup.keymap.preset end
		local private = self:GetPrivate("keymap")
		if type(private) == "table" then private.applied = CopyTable2(backup.keymap.applied) or {} end
	end
	-- The backup before this one is next in line.
	EldoUIDB.keybindBackup[self.charKey] = backup.previous
	Notify("restored", backup)
	local text = L["Keybinds restored to how they were on %s."]:format(E:ShortDate(backup.time))
	if kept > 0 then text = text .. " " .. E:Plural(kept, "%d key you changed since stays yours.", "%d keys you changed since stay yours."):format(kept) end
	Report(text)
	if self.KeybindPreviewChanged then self:KeybindPreviewChanged() end
	return true
end

function E:HasKeybindBackup()
	return EldoUIDB and EldoUIDB.keybindBackup and EldoUIDB.keybindBackup[self.charKey] ~= nil or false
end

-- The last question before keys change, on the shared dialog shell
-- (E:ShowConfirm). plan: the one the preview showed (made here when nil).
-- spells: the class spell plan the preview showed, when its box is ticked.
function E:ConfirmKeybindPreset(id, plan, spells)
	plan = plan or self:KeybindPlan(id)
	if not plan then return end
	if plan.blocked then
		self:ConfigNotice(plan.blockedText, true)
		return
	end
	local parts = { E:Plural(#plan.writes, "%d key changes", "%d keys change"):format(#plan.writes) }
	local skipped = plan.counts.manual + plan.counts.off
	if skipped > 0 then parts[#parts + 1] = E:Plural(skipped, "%d is left alone", "%d are left alone"):format(skipped) end
	if #plan.displaced > 0 then parts[#parts + 1] = E:Plural(#plan.displaced, "%d game shortcut changes its key", "%d game shortcuts change their key"):format(#plan.displaced) end
	local places = spells and #spells.places or 0
	local text
	if places > 0 then
		parts[#parts + 1] = E:Plural(places, "%d class spell goes on an empty button", "%d class spells go on empty buttons"):format(places)
		text = L["Apply the %s keys and class spells?\n\n%s.\n\nOnly empty buttons get a spell: your own actions stay, and nothing moves. Your current keys are saved first, and Undo puts back the keys and takes the spells off again."]:format(
			E:Highlight(L[plan.title]), table.concat(parts, ", "))
	else
		spells = nil
		text = L["Apply the %s keys?\n\n%s.\n\nOnly keys change: spells and bars stay as they are. Your current keys are saved first, and Undo last key set puts them back."]:format(
			E:Highlight(L[plan.title]), table.concat(parts, ", "))
	end
	local scope = self.KeySetScopeText and self:KeySetScopeText()
	if scope then text = text .. "\n\n" .. scope end
	self:ShowConfirm({ title = L["Key sets"], text = text, accept = OKAY, data = plan,
		onAccept = function(data) E:ApplyKeybindPlan(data, spells) end })
end

---------------------------------------------------------------------------
-- The game keys card: where bags, the map and the other shortcuts are
---------------------------------------------------------------------------
-- label: the row's name; commands: the game commands it covers (the first
-- one the game knows is used when there are several names for it).
local GAME_KEYS = {
	{ id = "bags", label = "Open all bags", commands = { "OPENALLBAGS" } },
	{ id = "map", label = "World map", commands = { "TOGGLEWORLDMAP" } },
	{ id = "character", label = "Character", commands = { "TOGGLECHARACTER0" } },
	{ id = "spellbook", label = "Spellbook", commands = { "TOGGLESPELLBOOK" } },
	{ id = "talents", label = "Talents", commands = { "TOGGLETALENTS" } },
	{ id = "quests", label = "Quest log", commands = { "TOGGLEQUESTLOG" } },
	{ id = "social", label = "Social", commands = { "TOGGLESOCIAL" } },
	{ id = "group", label = "Group finder", commands = { "TOGGLEGROUPFINDER", "TOGGLELFGPARENT" }, first = true },
	{ id = "reply", label = "Reply to a whisper", commands = { "REPLY" } },
	{ id = "sit", label = "Sit or stand", commands = { "SITORSTAND" } },
	{ id = "sheath", label = "Sheath", commands = { "TOGGLESHEATH" } },
	{ id = "nameplates", label = "Nameplates", commands = { "NAMEPLATES", "FRIENDNAMEPLATES", "ALLNAMEPLATES" } },
	{ id = "pet", label = "Pet bar", row = "BONUSACTIONBUTTON" },
	{ id = "stance", label = "Stance bar", row = "SHAPESHIFTBUTTON" },
	{ id = "ui", label = "Hide the interface", commands = { "TOGGLEUI" } },
	{ id = "target", label = "Target nearest enemy", commands = { "TARGETNEARESTENEMY" } },
	{ id = "jump", label = "Jump", commands = { "JUMP" } },
	{ id = "chat", label = "Open chat", commands = { "OPENCHAT" } },
	{ id = "menu", label = "Game menu", commands = { "TOGGLEGAMEMENU" } },
	{ id = "autorun", label = "Autorun", commands = { "TOGGLEAUTORUN" } },
}
E.keybindGameKeys = GAME_KEYS

local function KeysOf(command)
	if type(GetBindingKey) ~= "function" then return {} end
	local ok, a, b, c = pcall(GetBindingKey, command)
	local out = {}
	if ok then
		for _, key in ipairs({ a, b, c }) do
			key = Plain(key)
			if type(key) == "string" and key ~= "" then out[#out + 1] = key end
		end
	end
	return out
end

-- The card's rows, read live from the game's keys. plan: the set to show
-- the new keys of (default: the set you use, else the recommended one).
-- Each row: { id, command, label, keys = { now }, home (the new key after
-- the set, when it moves), lost (the set takes it and leaves it no key),
-- taken (its new key is yours already) }. Buttons a layout hides come
-- last: their keys work.
function E:GameKeysList(plan)
	if not plan then
		local id = self:KeybindPresetKey(Settings().preset) or self.keybindPresetOrder[1]
		plan = self:KeybindPlan(id)
	end
	local moved, lost = {}, {}
	for _, entry in ipairs(plan and plan.displaced or {}) do
		if entry.movedTo then moved[entry.command] = entry.movedTo else lost[entry.command] = entry end
	end
	for _, home in ipairs(plan and plan.homes or {}) do
		if home.movedTo and not moved[home.command] then moved[home.command] = home.movedTo end
	end
	local rows = {}
	for _, spec in ipairs(GAME_KEYS) do
		local row = { id = spec.id, label = L[spec.label], keys = {} }
		local commands = spec.commands
		if spec.row then
			commands = {}
			for n = 1, 10 do commands[n] = spec.row .. n end
		end
		row.command = commands[1]
		local homes = {}
		for _, command in ipairs(commands) do
			local keys = KeysOf(command)
			if spec.first and #keys > 0 and #row.keys == 0 then row.command = command end
			if not (spec.first and #row.keys > 0) then
				for _, key in ipairs(keys) do row.keys[#row.keys + 1] = key end
			end
			if moved[command] then homes[#homes + 1] = moved[command] end
			if lost[command] then
				row.lost = true
				if lost[command].homeTaken then row.taken = lost[command].homeTaken end
			end
		end
		if #homes > 0 then
			row.home = homes[1]
			row.homes = homes
		end
		rows[#rows + 1] = row
	end
	if plan and #plan.hidden > 0 then
		local keys = {}
		for _, entry in ipairs(plan.hidden) do keys[#keys + 1] = entry.key end
		rows[#rows + 1] = { id = "hidden", label = L["Buttons hidden in this layout"], keys = keys, note = L["hidden in this layout, key works"] }
	end
	return rows, plan
end

-- Keys in words: "B", "V, Shift-V", and a row of keys as "Ctrl-1 to Ctrl-0".
local function KeyList(list, row)
	if #list == 0 then return L["no key"] end
	if row and #list > 2 then
		return L["%s to %s"]:format(E:KeybindKeyText(list[1]), E:KeybindKeyText(list[#list]))
	end
	local out = {}
	for _, key in ipairs(list) do out[#out + 1] = E:KeybindKeyText(key) end
	return table.concat(out, ", ")
end

-- One card row in words: "Reply to a whisper: R  >  Alt-R".
function E:GameKeyRowText(row)
	local isRow = row.id == "pet" or row.id == "stance" or row.id == "hidden"
	local text = ("%s: %s"):format(row.label, KeyList(row.keys, isRow))
	if row.note then return text .. " (" .. row.note .. ")" end
	if row.home then
		text = text .. "  >  " .. KeyList(row.homes or { row.home }, isRow)
	elseif row.taken then
		text = text .. "  >  " .. L["no key: its new key %s is yours already"]:format(self:KeybindKeyText(row.taken))
	elseif row.lost then
		text = text .. "  >  " .. L["no key"]
	end
	return text
end

-- /eui keys: the card in the chat.
function E:PrintGameKeys()
	local rows, plan = self:GameKeysList()
	if plan then
		self:Print(L["Game keys, and where %s moves them:"]:format(E:Highlight(L[plan.title])))
	else
		self:Print(L["Game keys:"])
	end
	for _, row in ipairs(rows) do self:Print("  " .. self:GameKeyRowText(row)) end
	if plan and plan.blocked then self:Print(plan.blockedText) end
end

---------------------------------------------------------------------------
-- Settings: the key map (profile), the keyboard (account) and what the
-- last Apply did (character)
---------------------------------------------------------------------------
E:RegisterGlobal("keymap", { keyboard = "", checked = false, names = {}, sets = {} })
E:RegisterPrivate("keymap", { applied = {}, overrides = {}, never = false })

-- Rows of the Keybinds page that read their value through a small proxy
-- (a tick for "I manage my own keys", the keyboard list with a guess, the
-- keys on bars 1 to 3, which redraws the bars, and the answer for the
-- other characters).
local proxy = setmetatable({}, {
	__index = function(_, key)
		local db = Settings()
		if key == "own" then return db.preset == "none" end
		if key == "pageKeysOff" then return db.pageKeys ~= "keep" end
		if key == "showKeys" then return E:KeymapSetting("showKeys") and true or false end
		if key == "alts" then return E:KeymapSetting("alts") end
		if key == "keyboard" then
			local store = E:GetGlobal("keymap")
			local chosen = store and store.keyboard
			return (type(chosen) == "string" and E.keyboardLayouts[chosen]) and chosen or "auto"
		end
	end,
	__newindex = function(_, key, value)
		local db = E.db and E.db.keymap
		if key == "own" and type(db) == "table" then
			if value then
				db.preset = "none"
			else
				local private = E:GetPrivate("keymap")
				local last = private and private.applied and private.applied.preset
				db.preset = E:KeybindPresetKey(last) or ""
			end
		elseif key == "pageKeysOff" and type(db) == "table" then
			db.pageKeys = value and "off" or "keep"
		elseif key == "showKeys" then
			E:SetKeymap({ showKeys = value and true or false })
		elseif key == "alts" then
			E:SetKeymap({ alts = value })
		elseif key == "keyboard" then
			local store = E:GetGlobal("keymap")
			if store then
				local chosen = (value ~= "auto" and E.keyboardLayouts[value]) and value or ""
				-- Another keyboard: the names Check my keyboard found no longer apply.
				if chosen ~= store.keyboard then store.checked = false end
				store.keyboard = chosen
			end
		end
		if E.KeybindPreviewChanged then E:KeybindPreviewChanged() end
	end,
})
E.keymapOptionProxy = proxy

local function KeyboardValues()
	local values = { auto = L["Guess from the game language (%s)"]:format(L[E.keyboardLayouts[E:KeyboardLanguageGuess()].title]) }
	for _, id in ipairs(E.keyboardLayoutOrder) do values[id] = L[E.keyboardLayouts[id].title] end
	return values
end

-- Config page: the sets open the keys and spells preview first.
E:RegisterEvent("PLAYER_LOGIN", function()
	local options = {
		{ type = "description", label = "Each key set binds bars 1 to 3 and three Consumable Bar keys. Other bars keep their keys. A preview shows every key first." },
	}
	for _, key in ipairs(E.keybindPresetOrder) do
		local preset = E.keybindPresets[key]
		table.insert(options, { type = "execute", label = preset.recommended and L["%s (recommended)"]:format(L[preset.title]) or preset.title,
			desc = preset.desc, width = 220, func = function() E:OpenKeybindPreview(key) end })
	end
	table.insert(options, { type = "toggle", key = "own", root = function() return proxy end, label = "I manage my own keys",
		desc = "EldoUI then never writes a key. The preview, the game keys and keybind mode still work." })
	table.insert(options, { type = "header", label = "Keyboard" })
	table.insert(options, { type = "select", key = "keyboard", root = function() return proxy end, label = "Keyboard layout", wide = true,
		desc = "The key sets use the keys in the same places on every keyboard. Pick yours, or let EldoUI guess from the game language.",
		values = KeyboardValues, order = function()
			local order = { "auto" }
			for _, id in ipairs(E.keyboardLayoutOrder) do order[#order + 1] = id end
			return order
		end })
	table.insert(options, { type = "execute", label = "Check my keyboard",
		desc = "Press three keys, and EldoUI finds your keyboard layout from the names the game reports.", func = function() E:OpenKeyboardCheck() end })
	table.insert(options, { type = "header", label = "Options" })
	table.insert(options, { type = "toggle", key = "keymap.thumb", label = "Mouse 4 and 5 for interrupt and movement",
		desc = "A/D strafe only: Mouse 4 and Mouse 5 press buttons 6 and 7 of bars 1 to 3, with Shift and Ctrl for bars 2 and 3." })
	table.insert(options, { type = "toggle", key = "pageKeysOff", root = function() return proxy end, label = "Turn off the bar page keys",
		desc = "Shift + mouse wheel and Shift + arrow keys would swap bar 1's spells in a fight. With this on, a key set takes them off." })
	table.insert(options, { type = "select", key = "alts", root = function() return proxy end, label = "Your other characters",
		values = { offer = "Ask me", auto = "Automatic", off = "Off" }, order = { "offer", "auto", "off" },
		desc = "What happens on a character whose keys differ from this key set. Ask me shows one alert with a preview; Automatic sets its keys out of combat, with a backup and Undo." })
	table.insert(options, { type = "toggle", key = "showKeys", root = function() return proxy end, label = "Show the keys on bars 1 to 3",
		desc = "Shows the keys on bars 1 to 3 even when the action bar text style hides them. Off, those bars follow Action Bars > Show keybind like the others." })
	table.insert(options, { type = "header", label = "Your own keys" })
	table.insert(options, { type = "execute", label = "Show the game keys",
		desc = "Lists in the chat where bags, map and the other game shortcuts are, and where a key set moves them.", func = function() E:PrintGameKeys() end })
	table.insert(options, { type = "execute", label = "Undo last key set",
		desc = "Put back the keys you had before the last key set. A key you changed since stays yours.",
		disabled = function() return not E:HasKeybindBackup() end,
		func = function()
			E:ShowConfirm({ title = L["Key sets"], text = L["Put back the keys you had before the last key set? A key you changed since stays yours."],
				accept = L["Undo last key set"], onAccept = function()
					E:RunOutOfCombat(function() E:RestoreKeybinds(function(text, warn) E:ConfigNotice(text, warn) end) end, "Keybinds:undo")
				end })
		end })
	table.insert(options, { type = "execute", label = "Keybind mode (hover and press)",
		desc = "Hover any EldoUI button (action, pet, stance, extra, vehicle exit) and press a key to bind it.", func = function() E:ToggleKeybindMode() end })
	E:RegisterConfigPage("keybinds", "Keybinds", options, function() return E.db end, function() if E.KeybindPreviewChanged then E:KeybindPreviewChanged() end end, 4)
end, E.keybindPresets, "pages")

---------------------------------------------------------------------------
-- Check my keyboard: press three keys, keep the names the game reports
---------------------------------------------------------------------------
-- The 12th key of the number row, the first letter of the bottom row and
-- the key left of it (an ISO keyboard's extra key; Shift on ANSI).
local CHECK_PLACES = { "r1c12", "r4c1", "r4c0" }
E.keyboardCheckPlaces = CHECK_PLACES
local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true }

-- The layout whose keys match the reported names best (ties keep the
-- order of E.keyboardLayoutOrder). A place with no key, or with an accent
-- key that types nothing, matches "" (no usable name).
function E:KeyboardFromNames(names)
	local best, bestScore
	for _, id in ipairs(self.keyboardLayouts and self.keyboardLayoutOrder or {}) do
		local layout = self.keyboardLayouts[id]
		local score = 0
		for _, place in ipairs(CHECK_PLACES) do
			local info = layout.byPlace[place]
			local want = info and info.name or ""
			if names[place] == want then score = score + 1 end
		end
		if not bestScore or score > bestScore then best, bestScore = id, score end
	end
	return best, bestScore
end

-- Keeps the names, picks the layout and marks the keyboard checked.
function E:KeyboardCheckDone(names)
	local store = self:GetGlobal("keymap")
	if not store then return nil end
	local layout = self:KeyboardFromNames(names)
	store.names = {}
	for place, name in pairs(names) do store.names[place] = name end
	store.keyboard, store.checked = layout, true
	if self.KeybindPreviewChanged then self:KeybindPreviewChanged() end
	return layout
end

local check
local function CheckLayout()
	local K = E.UIKit
	local w = check:GetWidth() - 2 * K.TOOL_PAD
	check.text:SetWidth(w)
	local step = check.step
	for index, cap in ipairs(check.caps) do
		local size = math.ceil(40 * E:TextScale())
		cap:SetSize(size, size)
		cap:ClearAllPoints()
		cap:SetPoint("TOP", check.content, "TOP", (index - 2) * (size + 12), -(math.ceil(check.text:GetStringHeight() or 0) + 16))
		local on = index == step
		-- A plain if: inside and/or Lua keeps only the first color value.
		if on then
			cap:SetBackdropBorderColor(K.Accent())
		else
			cap:SetBackdropBorderColor(unpack(E.media.borderColor))
		end
		K.Paint(cap.label, on and "header" or "secondary")
		local name = check.names[CHECK_PLACES[index]]
		cap.label:SetText(name and (name == "" and "-" or E:KeybindKeyText(name)) or "?")
	end
end

local function CheckStepText()
	local texts = {
		L["Press the 12th key of the number row: the second key right of 0 (= on a US keyboard)."],
		L["Press the first letter key of the bottom row (Z on a US keyboard)."],
		L["Press the key left of that letter. On a keyboard with Shift there, press Shift."],
	}
	return texts[check.step] or ""
end

local function CheckRefresh()
	if check.step > #CHECK_PLACES then
		local layout = E:KeyboardCheckDone(check.names)
		local title = layout and L[E.keyboardLayouts[layout].title] or ""
		check.text:SetText(L["Your keyboard: %s. The key sets use its keys from now on."]:format(E:Highlight(title)))
		check.done:SetText(L["Done"])
		check.skip:Hide()
	else
		check.text:SetText(L["Step %d of %d."]:format(check.step, #CHECK_PLACES) .. " " .. CheckStepText() .. "\n" .. L["Esc cancels."])
		check.done:SetText(L["Cancel"])
		check.skip:SetShown(check.step == 1)
	end
	CheckLayout()
end

-- A pressed key: kept for the step shown, then the next step.
function E:KeyboardCheckPress(key)
	if not (check and check:IsShown()) or check.step > #CHECK_PLACES then return false end
	if key == "ESCAPE" then
		check:Hide()
		return true
	end
	local place = CHECK_PLACES[check.step]
	if MODIFIER_KEYS[key] then
		-- Shift left of the first letter: no extra key there.
		if place ~= "r4c0" then return true end
		key = ""
	end
	check.names[place] = key
	check.step = check.step + 1
	CheckRefresh()
	return true
end

function E:OpenKeyboardCheck()
	if InCombatLockdown() then
		self:ConfigNotice(L["Check your keyboard out of combat."], true)
		return nil
	end
	local K = self.UIKit
	if not check then
		check = K.CreateToolWindow("EldoUI_KeyboardCheck", { title = L["Check my keyboard"], width = 420, height = 250, strata = "FULLSCREEN_DIALOG",
			footer = K.TOOL_FOOTER, resizable = false })
		check.text = K.Text(check.content, E.tokens.size.body, "LEFT", "body")
		check.text:SetPoint("TOPLEFT", 0, 0)
		check.text:SetWordWrap(true)
		check.caps = {}
		for index = 1, #CHECK_PLACES do
			local cap = CreateFrame("Frame", nil, check.content)
			E:SetTemplate(cap, true)
			cap.label = K.Text(cap, E.tokens.size.body, "CENTER", "body")
			cap.label:SetPoint("CENTER")
			check.caps[index] = cap
		end
		check.done = K.Button(check.footer, { text = L["Cancel"], kind = "primary", onClick = function() check:Hide() end })
		check.done:SetPoint("RIGHT", -28, 0)
		check.skip = K.Button(check.footer, { text = L["This key types nothing"],
			tip = L["Some keyboards have an accent key there that types nothing on its own. The key sets then leave that place without a key."],
			onClick = function()
				check.names[CHECK_PLACES[check.step]] = ""
				check.step = check.step + 1
				CheckRefresh()
			end })
		check.skip:SetPoint("RIGHT", check.done, "LEFT", -8, 0)
		check.keys = K.KeyHandler(check, function(_, key) return E:KeyboardCheckPress(key) end)
		check:RegisterEvent("PLAYER_REGEN_DISABLED")
		check:SetScript("OnEvent", function(frame) frame:Hide() end)
	end
	check.step, check.names = 1, {}
	check:Open()
	CheckRefresh()
	return check
end
