-- EldoUI keyboard layouts: the five keyboards the key sets know, drawn in
-- the keys and spells preview and used to turn a key's place into the
-- name the game gives that key.
--
-- A key set stores places, not letters: "r2c4" is row 2 (the top letter
-- row), column 4 (R on a US keyboard). The layout in use turns a place
-- into the game's key name, so W A S D are Z Q S D on a French keyboard
-- and the bottom-left letter is Y on a German one, with the same fingers.
--
--   Rows: r0 Esc and the F keys, r1 the number row (c0 left of 1, c1-c10
--   the digits, c11 and c12 the two keys after them), r2 the top letter
--   row, r3 the home row, r4 the bottom row (c0 the extra key of an ISO
--   keyboard, left of the first letter), r5 Ctrl, Alt and Space.
--   Mouse places: m1-m5 the mouse buttons, wu and wd the wheel, g1-g12
--   the 12-button side grid of a gaming mouse (it sends the number row).
--
--   E.keyboardLayouts[id]      { id, title, iso, rows = { { keys } }, byPlace }
--   E.keyboardLayoutOrder      us, uk, nordic, de, fr
--   E:KeyboardKeyName(place[, layout])  the game's key name, or nil for a
--                              place with no usable key (an accent key that
--                              types nothing on its own)
--   E:KeyboardGuess()          the layout in use: your choice, else a guess
--                              from the game's language
--   E:KeyboardLanguageGuess()  the guess alone
--
-- Each key: place, legend (what is printed on it), name (the game's key
-- name; nil when the game can't bind it alone), width in key units, and
-- fixed = true for keys a key set never takes (Tab, Shift, Space ...).
-- Written from scratch for EldoUI.
local _, E = ...

local Key = E.Key

-- Keys that are the same on every layout.
local function Fixed(place, legend, name, width)
	return { place = place, legend = legend, name = name, width = width or 1, fixed = true }
end

local function Char(place, legend, name, width)
	if name == nil then name = legend end
	if name == false then name = nil end
	return { place = place, legend = legend, name = name, width = width or 1 }
end

-- The F key row: Esc, a gap, F1 to F12 in three groups.
local function FRow()
	local row = { Fixed("esc", "Esc", "ESCAPE") }
	for i = 1, 12 do
		local key = Fixed("f" .. i, "F" .. i, "F" .. i)
		if i == 1 then key.gap = 1 elseif i == 5 or i == 9 then key.gap = 0.5 end
		row[#row + 1] = key
	end
	return row
end

-- One layout from its own legends.
-- spec: num = { c0, c11, c12 } (legend, or { legend, name }), top, home,
-- bottom = letter lists of rows 2-4; extras for the ISO keys.
local function Build(id, title, spec)
	local iso = spec.iso and true or false
	local function Item(place, value)
		if type(value) == "table" then return Char(place, value[1], value[2]) end
		return Char(place, value)
	end
	local rows = { FRow() }
	-- r1: the number row.
	local r1 = { Item("r1c0", spec.num[1]) }
	for i = 1, 10 do r1[#r1 + 1] = Char("r1c" .. i, tostring(i % 10)) end
	r1[#r1 + 1] = Item("r1c11", spec.num[2])
	r1[#r1 + 1] = Item("r1c12", spec.num[3])
	r1[#r1 + 1] = Fixed("backspace", Key("Back"), "BACKSPACE", 2)
	rows[#rows + 1] = r1
	-- r2: Tab and the top letter row.
	local r2 = { Fixed("tab", "Tab", "TAB", 1.5) }
	for i, value in ipairs(spec.top) do r2[#r2 + 1] = Item("r2c" .. i, value) end
	if iso then
		r2[#r2 + 1] = Fixed("enter", "Enter", "ENTER", 1.5)
	else
		r2[#r2 + 1] = Item("r2c13", spec.backslash)
		r2[#r2].width = 1.5
	end
	rows[#rows + 1] = r2
	-- r3: Caps Lock and the home row.
	local r3 = { Fixed("caps", Key("Caps"), "CAPSLOCK", 1.75) }
	for i, value in ipairs(spec.home) do r3[#r3 + 1] = Item("r3c" .. i, value) end
	r3[#r3 + 1] = Fixed(iso and "enter2" or "enter", "Enter", "ENTER", iso and 1.25 or 2.25)
	rows[#rows + 1] = r3
	-- r4: Shift, the ISO extra key and the bottom row.
	local r4 = { Fixed("lshift", "Shift", "LSHIFT", iso and 1.25 or 2.25) }
	if iso then r4[#r4 + 1] = Item("r4c0", spec.extra) end
	for i, value in ipairs(spec.bottom) do r4[#r4 + 1] = Item("r4c" .. i, value) end
	r4[#r4 + 1] = Fixed("rshift", "Shift", "RSHIFT", 2.75)
	rows[#rows + 1] = r4
	-- r5: the modifier row.
	rows[#rows + 1] = {
		Fixed("lctrl", "Ctrl", "LCTRL", 1.25), Fixed("lwin", "Win", nil, 1.25), Fixed("lalt", "Alt", "LALT", 1.25),
		Fixed("space", Key("Space"), "SPACE", 6.25), Fixed("ralt", iso and "AltGr" or "Alt", "RALT", 1.25),
		Fixed("rwin", "Win", nil, 1.25), Fixed("menu", Key("Menu"), nil, 1.25), Fixed("rctrl", "Ctrl", "RCTRL", 1.25),
	}
	local layout = { id = id, title = title, iso = iso, rows = rows, byPlace = {} }
	for _, row in ipairs(rows) do
		for _, key in ipairs(row) do layout.byPlace[key.place] = key end
	end
	return layout
end

local US_TOP = { "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]" }
local US_HOME = { "A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'" }
local US_BOTTOM = { "Z", "X", "C", "V", "B", "N", "M", ",", ".", "/" }

local function With(list, changes)
	local out = {}
	for i, value in ipairs(list) do out[i] = value end
	for i, value in pairs(changes or {}) do out[i] = value end
	return out
end

E.keyboardLayouts = {
	us = Build("us", Key("US"), { num = { "`", "-", "=" }, top = US_TOP, home = US_HOME, bottom = US_BOTTOM, backslash = "\\" }),
	uk = Build("uk", Key("UK"), { iso = true, num = { "`", "-", "=" }, top = US_TOP, home = With(US_HOME, { [12] = "#" }),
		bottom = US_BOTTOM, extra = "\\" }),
	-- The accent keys (right of + and right of Å) type nothing alone.
	nordic = Build("nordic", Key("Nordic"), { iso = true, num = { "½", "+", { "´", false } },
		top = With(US_TOP, { [11] = "Å", [12] = { "¨", false } }), home = With(US_HOME, { [10] = "Æ", [11] = "Ø", [12] = "'" }),
		bottom = With(US_BOTTOM, { [10] = "-" }), extra = "<" }),
	de = Build("de", Key("German"), { iso = true, num = { { "^", false }, "ß", { "´", false } },
		top = With(US_TOP, { [6] = "Z", [11] = "Ü", [12] = "+" }), home = With(US_HOME, { [10] = "Ö", [11] = "Ä", [12] = "#" }),
		bottom = With(US_BOTTOM, { [1] = "Y", [10] = "-" }), extra = "<" }),
	fr = Build("fr", Key("French"), { iso = true, num = { "²", ")", "=" },
		top = { "A", "Z", "E", "R", "T", "Y", "U", "I", "O", "P", { "^", false }, "$" },
		home = { "Q", "S", "D", "F", "G", "H", "J", "K", "L", "M", "Ù", "*" },
		bottom = { "W", "X", "C", "V", "B", "N", ",", ";", ":", "!" }, extra = "<" }),
}
E.keyboardLayoutOrder = { "us", "uk", "nordic", "de", "fr" }
E.keyboardLayouts.us.desc = Key("US English keyboard (ANSI): a long Shift key, no key left of Z.")
E.keyboardLayouts.uk.desc = Key("UK English keyboard (ISO): a tall Enter key and a key left of Z.")
E.keyboardLayouts.nordic.desc = Key("Danish, Norwegian, Swedish and Finnish keyboards (ISO), with Æ Ø Å or Ö Ä Å.")
E.keyboardLayouts.de.desc = Key("German keyboard (QWERTZ): Z and Y swap places.")
E.keyboardLayouts.fr.desc = Key("French keyboard (AZERTY): A, Z, Q, W and M sit in other places.")

-- The mouse: places shared by every layout. The side grid sends the
-- number row, so its places resolve to the number row of the layout.
E.keyboardMouse = {
	{ place = "m1", legend = Key("Left"), fixed = true },
	{ place = "m2", legend = Key("Right"), fixed = true },
	{ place = "m3", legend = Key("Middle"), name = "BUTTON3" },
	{ place = "wu", legend = Key("Wheel up"), name = "MOUSEWHEELUP" },
	{ place = "wd", legend = Key("Wheel down"), name = "MOUSEWHEELDOWN" },
	{ place = "m4", legend = Key("Mouse 4"), name = "BUTTON4" },
	{ place = "m5", legend = Key("Mouse 5"), name = "BUTTON5" },
}
E.keyboardMouseByPlace = {}
for _, key in ipairs(E.keyboardMouse) do E.keyboardMouseByPlace[key.place] = key end

---------------------------------------------------------------------------
-- Which keyboard
---------------------------------------------------------------------------
local function Store()
	return E.GetGlobal and E:GetGlobal("keymap") or nil
end

-- The guess from the game's language (and EldoUI's language for Danish).
function E:KeyboardLanguageGuess()
	local locale = type(GetLocale) == "function" and GetLocale() or "enUS"
	if locale == "enGB" then return "uk" end
	if locale == "deDE" then return "de" end
	if locale == "frFR" then return "fr" end
	local language = self.GetLanguage and self:GetLanguage() or nil
	if language == "daDK" then return "nordic" end
	return "us"
end

-- The layout in use: the one you chose (or Check my keyboard found),
-- else the guess.
function E:KeyboardGuess()
	local store = Store()
	local chosen = store and store.keyboard
	if type(chosen) == "string" and self.keyboardLayouts[chosen] then return chosen end
	return self:KeyboardLanguageGuess()
end

-- The key name of a place on a layout, or nil. A name the game reported
-- in Check my keyboard wins for the keyboard it was found on ("" there
-- means the game reported no usable key).
function E:KeyboardKeyName(place, layout)
	if type(place) ~= "string" then return nil end
	local mouse = self.keyboardMouseByPlace[place]
	if mouse then return mouse.name end
	local grid = place:match("^g(%d+)$")
	if grid then place = "r1c" .. grid end
	layout = self.keyboardLayouts[layout or ""] and layout or self:KeyboardGuess()
	local store = Store()
	if store and store.checked and store.keyboard == layout and type(store.names) == "table" then
		local reported = store.names[place]
		if reported == "" then return nil end
		if type(reported) == "string" then return reported end
	end
	local info = self.keyboardLayouts[layout].byPlace[place]
	return info and info.name or nil
end

-- What is printed on a place's key (for the drawing and help texts).
function E:KeyboardLegend(place, layout)
	local mouse = self.keyboardMouseByPlace[place or ""]
	if mouse then return E:Translate(mouse.legend) end
	local grid = type(place) == "string" and place:match("^g(%d+)$")
	if grid then place = "r1c" .. grid end
	layout = self.keyboardLayouts[layout or ""] and layout or self:KeyboardGuess()
	local info = self.keyboardLayouts[layout].byPlace[place or ""]
	return info and E:Translate(info.legend) or nil
end
