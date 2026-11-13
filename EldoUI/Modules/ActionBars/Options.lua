-- EldoUI Action Bars options page. Every setting of Modules/ActionBars*
-- lives here, in tabs. What EldoUI may do to Blizzard's own bars (skin,
-- move, hide, replace) is set per element on the "Blizzard UI" page; the
-- options below say which switch they follow.
--
-- Shared blocks (options rules, plan section 6): fade and visibility come
-- from Core/Visibility.lua, the proc glow look from General > Glows,
-- "Copy from" between bars from the options window. Rare
-- settings sit behind a cog.
local _, E = ...
local L = E.L

local M = E:GetModule("ActionBars")
if not M then return end

local NUM_BARS = M.NUM_BARS or 8

---------------------------------------------------------------------------
-- Value lists
---------------------------------------------------------------------------
local ANCHORS = {
	TOPLEFT = "Top left", TOP = "Top", TOPRIGHT = "Top right",
	LEFT = "Left", CENTER = "Center", RIGHT = "Right",
	BOTTOMLEFT = "Bottom left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom right",
}
local GROWTH = {
	TOPLEFT = "Right, then down", TOPRIGHT = "Left, then down",
	BOTTOMLEFT = "Right, then up", BOTTOMRIGHT = "Left, then up",
}
local FILL_ORDER = { rows = "Rows first", columns = "Columns first" }
local ASPECT = {
	["1:1"] = "Square", ["5:4"] = "Slightly wide (5:4)", ["4:3"] = "Wide (4:3)",
	["3:2"] = "Wider (3:2)", ["2:1"] = "Flat (2:1)",
}
local BLIZZARD_BAR = {
	auto = "Hide when EldoUI replaces it",
	show = "Always keep Blizzard's",
	hide = "Hide (follows the Hide switch)",
}
local FLYOUT = { AUTO = "Automatic", UP = "Up", DOWN = "Down", LEFT = "Left", RIGHT = "Right" }
local SPECIAL_MODE = { eldoui = "EldoUI bar", blizzard = "Blizzard's bar", hide = "Hidden" }
local STYLE = { fill = "Soft fill", accent = "Accent border", none = "None" }
local OUTLINE = { theme = "Theme (Fonts and text page)", NONE = "None", OUTLINE = "Outline", THICKOUTLINE = "Thick outline" }

local function PageValues()
	local values = { [0] = "Off" }
	for index = 1, NUM_BARS do values[index] = L["Bar %d"]:format(index) end
	return values
end

local function BarValues()
	local values = {}
	for index = 1, NUM_BARS do
		local db = M.db and M.db.bars and M.db.bars[index]
		if not (db and db.enabled) then
			values[index] = L["Bar %d (off)"]:format(index)
		elseif not M:BarShown(index) then
			values[index] = L["Bar %d (hidden)"]:format(index)
		else
			values[index] = L["Bar %d"]:format(index)
		end
	end
	return values
end

-- Sibling bars for "Copy settings from" (paths into the settings).
local function BarPaths()
	local values = {}
	for index = 1, NUM_BARS do values["bars." .. index] = L["Bar %d"]:format(index) end
	return values
end

local function TextPresetValues()
	local values = { custom = "Custom" }
	for key, preset in pairs(M.TEXT_PRESETS or {}) do values[key] = preset.title end
	return values
end

local function Settings() return M.db end

-- The shared visibility rows for the block at `prefix` (the rare settings
-- sit in the gear of "Show"). `tweak(row)` may adjust single rows.
local function VisibilityRows(prefix, hidden, tweak, disabled)
	local rows = E:VisibilityOptions(prefix, { secure = true, db = Settings, hidden = hidden, label = "Visibility", disabled = disabled })
	if tweak then
		for _, row in ipairs(rows) do tweak(row) end
	end
	return rows
end

---------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------
local options = {}
local function Add(option) options[#options + 1] = option end

-- Options for one bar, shown only while that bar is picked.
local function AddBar(index)
	local prefix = "bars." .. index .. "."
	local function hidden() return (M.db and M.db.optionsBar or 1) ~= index end
	local function opt(option)
		option.hidden = option.hidden or hidden
		if option.key then option.key = prefix .. option.key end
		Add(option)
	end
	opt({ type = "header", label = "Bar %d", labelFill = index })
	opt({ type = "toggle", key = "enabled", label = "Enable", desc = index == 1
		and E.Key("Show EldoUI's action bar %d, with the game's \"Action Button\" keys. It shows while Blizzard's bar is replaced or hidden, so there are never two bars. Turned off, its keys stop working.")
		or E.Key("Show EldoUI's action bar %d, with the game's \"Action Bar %d\" keys. It shows while Blizzard's bar is replaced, hidden or switched off, so there are never two bars. Turned off, its keys stop working."),
		descFill = index == 1 and index or { index, index } })
	if index >= 3 then
		-- Shown: a layout may hide the bar; its keys keep working.
		opt({ type = "toggle", key = "shown", label = "Show on screen",
			desc = "Off: the bar steps out of sight and its keys keep working. It shows when you point at it out of combat, near your bags or the right edge, and hides in combat.",
			disabled = function()
				if not (M.db and M.db.bars[index].enabled) then return L["Turn on \"%s\" first."]:format(L["Enable"]) end
				return nil
			end })
		opt({ type = "toggle", key = "hiddenMouseover", label = "Show on mouse over",
			desc = "While the bar is out of sight: it shows when you point at it out of combat. Off: it never shows, and its keys keep working.",
			disabled = function()
				if not (M.db and M.db.bars[index].enabled) then return L["Turn on \"%s\" first."]:format(L["Enable"]) end
				if M.db.bars[index].shown ~= false then return L["Turn off \"%s\" first."]:format(L["Show on screen"]) end
				return nil
			end })
	end
	opt({ type = "select", key = "blizzard", label = "Blizzard's bar", values = BLIZZARD_BAR,
		desc = "Blizzard's own bar %d. Hide when replaced: hidden while this EldoUI bar is on and the Replace switch is on. Keep: it stays. Hide: always hidden (needs the Hide switch).", descFill = index })

	opt({ type = "header", label = "Layout" })
	opt({ type = "range", key = "buttons", label = "Buttons", min = 1, max = index == 3 and 9 or 12, step = 1, desc = index == 3
		and E.Key("How many buttons the bar shows, up to nine. Keys 10 to 12 of the key sets use the Consumable Bar.")
		or E.Key("How many buttons the bar shows.") })
	opt({ type = "range", key = "perRow", label = "Buttons per row", min = 1, max = 12, step = 1, desc = "Buttons in each row: this sets how wide the grid is. With the fill order set to columns first, the same grid fills column by column." })
	opt({ type = "range", key = "size", label = "Button size", min = 16, max = 80, step = 1, desc = "Width of each button in pixels. Square buttons are as high as they are wide." })
	opt({ type = "select", key = "aspect", label = "Button shape", values = ASPECT,
		desc = "Width to height of the buttons. Wide shapes are lower than they are wide; the icon is cropped to fit, never stretched." })
	opt({ type = "range", key = "spacing", label = "Spacing", min = 0, max = 20, step = 1, desc = "Gap between buttons in pixels." })
	opt({ type = "range", key = "scale", label = "Scale", unit = "%", min = 50, max = 200, step = 5, desc = "Size of the whole bar in percent." })
	opt({ type = "select", key = "growth", label = "Growth direction", values = GROWTH, desc = "Corner the first button sits in and the direction the rest follow." })
	opt({ type = "select", key = "fillOrder", label = "Fill order", values = FILL_ORDER,
		desc = "Rows first: the buttons fill each row before the next row starts. Columns first: they fill each column from the first corner before the next column starts, as on an upright bar. Default: Rows first." })
	opt({ type = "select", key = "flyout", label = "Flyout direction", values = FLYOUT, cog = true, desc = "Which way spell flyouts (for example portals or pets) open from this bar." })
	opt({ type = "toggle", key = "showGrid", label = "Show empty slots", desc = "Show buttons with nothing on them. Empty slots always show while you drag a spell." })
	opt({ type = "toggle", key = "backdrop", label = "Background", desc = "Draw an EldoUI panel behind the bar.",
		cog = { { type = "range", key = prefix .. "backdropPadding", label = "Background padding", min = 0, max = 16, step = 1, desc = "Space between the buttons and the edge of the backdrop." } } })
	opt({ type = "toggle", key = "clickThrough", label = "Click through", desc = "Mouse clicks go through the bar to the world. Keybinds still work." })

	opt({ type = "header", label = "Text" })
	opt({ type = "toggle", key = "ownText", label = "Own text settings",
		desc = "Give this bar its own keybind, count and macro text (the gear). Off: the bar uses the Text tab.",
		cog = {
			{ type = "toggle", key = prefix .. "text.showHotkey", label = "Show keybind", desc = "Show the key bound to each button of this bar." },
			{ type = "range", key = prefix .. "text.hotkeySize", label = "Keybind size", min = 6, max = 24, step = 1, desc = "Text size of the keybind on this bar." },
			{ type = "select", key = prefix .. "text.hotkeyPosition", label = "Keybind position", values = ANCHORS, desc = "Where on the button the keybind sits on this bar." },
			{ type = "toggle", key = prefix .. "text.showCount", label = "Show count", desc = "Show charges and item counts on this bar." },
			{ type = "range", key = prefix .. "text.countSize", label = "Count size", min = 6, max = 24, step = 1, desc = "Text size of the count on this bar." },
			{ type = "select", key = prefix .. "text.countPosition", label = "Count position", values = ANCHORS, desc = "Where on the button the count sits on this bar." },
			{ type = "toggle", key = prefix .. "text.showMacro", label = "Show macro name", desc = "Show the name of macros on this bar." },
			{ type = "range", key = prefix .. "text.macroSize", label = "Macro name size", min = 6, max = 24, step = 1, desc = "Text size of macro names on this bar." },
		} })

	-- While the bar is hidden it follows the hidden-bar rule; its own
	-- settings stay for when it shows again.
	local function HiddenReason()
		if M.db and not M:BarShown(index) then return L["The bar is hidden: it shows on mouse over out of combat. Turn on Show on screen to use these settings."] end
		return nil
	end
	for _, row in ipairs(VisibilityRows(prefix .. "fade", hidden, function(row)
		if index == 1 and type(row.key) == "string" and row.key:sub(-12) == ".hideVehicle" then
			-- Bar 1 showing the vehicle's actions always stays.
			local own = row.hidden
			row.hidden = function() return (own and own()) or M:BarOneInVehicle() end
		end
	end, index >= 3 and HiddenReason or nil)) do Add(row) end
	opt({ type = "range", key = "alpha", label = "Opacity", unit = "%", min = 0, max = 100, step = 5, desc = "Opacity of the bar while it is shown and not faded." })
	opt({ type = "input", key = "customVisibility", label = "Custom conditions", cog = true,
		desc = "Advanced: macro conditions ending in show or hide, for example \"[mod:shift] show; hide\". When filled they replace the Show rule. The bar always hides in pet battles." })

	opt({ type = "header", label = "Paging" })
	opt({ type = "select", key = "pageShift", label = "Shift shows", values = PageValues, desc = "While Shift is held the bar shows the actions of another bar. Off keeps its own." })
	opt({ type = "select", key = "pageCtrl", label = "Ctrl shows", values = PageValues, desc = "While Ctrl is held the bar shows the actions of another bar." })
	opt({ type = "select", key = "pageAlt", label = "Alt shows", values = PageValues, desc = "While Alt is held the bar shows the actions of another bar." })
	opt({ type = "input", key = "customPaging", label = "Custom paging", cog = true, desc = "Advanced: macro conditions and page numbers, for example \"[mod:shift] 2; [form:1] 7\". Checked before the modifier paging." })
end

---------------------------------------------------------------------------
-- General
---------------------------------------------------------------------------
Add({ type = "tab", label = "General" })
Add({ type = "description", label = "What EldoUI may change on Blizzard's own bars is set on the Blizzard UI page, bar by bar. A bar at Blizzard default stays exactly as it is." })
Add({ type = "execute", label = "Open Blizzard UI switches", desc = "The per-element switches (skin, move, hide, replace, improve).", func = function() E:ToggleConfig("blizzard") end })
Add({ type = "execute", label = "Keybind mode", desc = "Hover any EldoUI button and press a key to bind it.", func = function() E:ToggleKeybindMode() end })
Add({ type = "header", label = "Bar 1" })
Add({ type = "toggle", key = "pageVehicle", label = "Vehicle actions on bar 1", desc = "Bar 1 shows the actions of vehicles, override bars and possessed units, like Blizzard's main bar, and stays shown in vehicles. Always on while EldoUI hides Blizzard's override bar." })
Add({ type = "toggle", key = "pageForms", label = "Stance and form pages", desc = "Bar 1 switches page with stance, form and stealth, like Blizzard's main bar." })
Add({ type = "header", label = "Behavior" })
Add({ type = "select", key = "tooltips", label = "Tooltips", values = { enabled = "Always", nocombat = "Out of combat only", disabled = "Never" }, desc = "When hovering a button shows its tooltip." })
-- Casting on key press is a protected game setting: no addon can change
-- it, but the player's own chat command can. The rows only read it.
local function KeyDownNow()
	if not (C_CVar and C_CVar.GetCVar) then return nil end
	local ok, value = pcall(C_CVar.GetCVar, "ActionButtonUseKeyDown")
	if not ok or E:IsSecret(value) or value == nil then return nil end
	return value == "1"
end
Add({ type = "description", hidden = function() return KeyDownNow() == nil end,
	label = function()
		return KeyDownNow() and L["Spells cast when the key goes down. This is a protected game setting: no addon can change it, but your own chat command can."]
			or L["Spells cast when the key comes back up. This is a protected game setting: no addon can change it, but your own chat command can."]
	end })
Add({ type = "execute", label = "Copy command", hidden = function() return KeyDownNow() == nil end,
	desc = "Shows the chat command that switches when spells cast, selected for copying. Paste it in chat and press Enter.",
	func = function()
		E:ShowCopyBox(L["Cast on"], L["Press Ctrl+C, open chat, paste the command and press Enter."],
			("/console ActionButtonUseKeyDown %d"):format(KeyDownNow() and 0 or 1))
	end })
Add({ type = "select", key = "lockBars", label = "Lock action bars", values = { game = "Game setting", locked = "Locked", unlocked = "Unlocked" },
	desc = "Locked bars only let you drag a spell off while you hold the pick-up key, on EldoUI's and Blizzard's bars alike. Game setting leaves Options > Action Bars > Lock action bars as it is.", disabled = E:BlizzardNeeds("action-button-look", "improve") })
Add({ type = "select", key = "pickupKey", label = "Pick-up key", values = { game = "Game setting", SHIFT = "Shift", CTRL = "Ctrl", ALT = "Alt" },
	desc = "The key to hold to drag a spell off a locked bar. Picking one changes the game's own \"Pick up action key\" setting.", disabled = E:BlizzardNeeds("action-button-look", "improve") })
Add({ type = "toggle", key = "linkMouseover", label = "Show mouse-over bars together",
	desc = "Bars whose Show rule is \"Mouse over\" appear together: hovering one of them shows all of them, the pet and stance bars too. Off: each bar fades in on its own." })
Add({ type = "toggle", key = "gamepadHide", label = "Hide with gamepad", desc = "Hide EldoUI's action bars while the game's gamepad interface is on, so the controller HUD takes over." })
Add({ type = "toggle", key = "castVFX", label = "Cast animation", desc = "Play the game's cast and targeting animation on EldoUI buttons." })

Add({ type = "header", label = "New spells" })
-- These two rows live in the profile's key map record, not in this
-- module's settings; the Action Bars refresh applies them.
local function KeymapRoot() return E:NewSpellsRecord() end
Add({ type = "select", key = "newSpells", root = KeymapRoot, -- lint: unused-key ok (read by Core/KeybindNewSpells.lua)
	label = "Put new spells on their key", values = { offer = "Offer", auto = "Automatically", off = "Off" },
	desc = "A spell you learn goes to its key on bars 1 to 3; a talent spell relearned after a talent reset returns to its old button. Offer asks first; Automatically places it out of combat. Empty buttons only." })
Add({ type = "execute", label = "Take off the last new spells", desc = "Take the spells EldoUI last put on your bars off again, where a button still holds them. Same as /eui spells undo.",
	func = function() E:RunOutOfCombat(function() E:UndoNewSpells() end, "KeybindNewSpells:undo") end,
	disabled = function() return not E:HasNewSpellsUndo() end })

Add({ type = "header", label = "Bars 4 and 5", hidden = function() return not E:QuietFillAvailable() end })
Add({ type = "toggle", key = "quietFill", root = KeymapRoot, -- lint: unused-key ok (read by Core/KeybindQuietBars.lua)
	label = "Fill bars 4 and 5",
	hidden = function() return not E:QuietFillAvailable() end,
	desc = "Put your class's out-of-combat spells (travel, tracking, poisons, pet care) on the empty buttons of bars 4 and 5, out of combat. Buttons you filled are never touched." })
Add({ type = "execute", label = "Take the spells off bars 4 and 5", desc = "Take the spells of the last fill off bars 4 and 5 again, where a button still holds them. Same as /eui fillbars undo.",
	func = function() E:RunOutOfCombat(function() E:UndoQuietBars() end, "KeybindQuietBars:undo") end,
	hidden = function() return not E:QuietFillAvailable() end,
	disabled = function() return not E:HasQuietBarsUndo() end })

Add({ type = "header", label = "Spell ranks" })
Add({ type = "description", label = "After you learn a new rank, the old one stays on your bars. EldoUI can offer to move those buttons to the new rank, or move them for you." })
Add({ type = "description", label = function()
	local addon = M:RankUpgradeConflict()
	return addon and L["%s moves your spell ranks, so EldoUI's offer and automatic upgrade leave it to that addon. The highlight and Check ranks still work."]:format(addon) or ""
end, hidden = function() return M:RankUpgradeConflict() == nil end })
Add({ type = "toggle", key = "ranks.offer", label = "Offer rank upgrades",
	desc = "After you learn a new spell rank, and once at login when lower ranks are on your bars, ask whether to show the changes. Nothing moves until you press Apply in that preview.",
	disabled = function() return M.db and M.db.ranks and M.db.ranks.auto end })
Add({ type = "toggle", acts = true, key = "ranks.auto", label = "Upgrade spell ranks automatically",
	desc = "Move lower ranks to the highest rank you know without asking, out of combat, after you learn one and at login. Macros, items and kept spells never change. Off by default." })
Add({ type = "select", key = "ranks.scope", label = "Which bars", wide = true, values = { used = "Every bar I use", main = "Bars 1 to 3 and the gamepad bars" },
	desc = "The bars the automatic upgrade may change. Every bar I use: bar 1 with its stance and form pages, the other bars that are on, and the gamepad bars. A lower rank you place yourself stays.",
	disabled = function() return not (M.db and M.db.ranks and M.db.ranks.auto) end })
Add({ type = "toggle", key = "ranks.chat", label = "Chat line", desc = "Write a line in chat after an upgrade: how many buttons changed and to which rank." })
Add({ type = "input", key = "ranks.exclude", label = "Keep these at their rank",
	desc = "Spell names, separated by commas, that are never upgraded, for example a low rank heal you keep for mana." })
Add({ type = "execute", label = "Show rank upgrades", desc = "Open the keys and spells preview at the spell ranks: check the buttons to move, then press Apply (out of combat). Same as /eui ranks.",
	func = function() M:UpgradeRanks() end })
Add({ type = "execute", label = "Undo last upgrade", desc = "Put back the spells the last automatic upgrade changed and keep those buttons at that rank. A button you changed since stays as it is. Same as /eui ranks undo.",
	func = function() E:RunOutOfCombat(function() M:UndoRankUpgrade() end, "ActionBars:rankUndo") end,
	disabled = function() return not M:HasRankUndo() end })
Add({ type = "select", key = "ranks.highlight", label = "Highlight lower ranks", values = { off = "Off", spellbook = "While the spellbook is open", always = "Always" },
	desc = "Light up the action buttons that hold a lower rank of a spell you know at a higher rank. Its look is on the Glows page (Lower spell ranks)." })
Add({ type = "toggle", key = "ranks.macros", label = "Include macros", desc = "Also light up and list macros that show or name a lower rank. A macro changes only when you click its Update button in the macro editor (/eui macros)." })
Add({ type = "toggle", key = "ranks.otherBars", label = "Other bar addons", desc = "Also light up buttons of Bartender4, ElvUI and Dominos. Blizzard's own bars follow Blizzard UI > Action button look: Improve." })
Add({ type = "toggle", key = "ranks.spellbookButton", label = "Button in the spellbook", desc = "A Check ranks button on the spellbook page: left-click lists and lights up the lower ranks, right-click shows the changes to apply.",
	disabled = E:BlizzardNeeds("player-spells", "improve") })
Add({ type = "toggle", key = "ranks.report", label = "Report in chat", desc = "A check lists each slot with a lower rank in chat (only you see it): where it is, its rank and the highest rank you know." })
Add({ type = "execute", label = "Check ranks now", desc = "List the action slots that hold a lower rank and light them up for a moment. Same as /eui rankcheck.",
	func = function() M:CheckRanks() end })

---------------------------------------------------------------------------
-- Bars
---------------------------------------------------------------------------
Add({ type = "tab", label = "Bars" })
-- Preview: the picked bar with sample spells, in its button count, grid,
-- size and spacing, with its keybind and count texts (E:ConfigSample,
-- Core/MoverSamples.lua).
local function UpdatePreview(canvas)
	local db = M.db
	local bar = db and db.bars and db.bars[db.optionsBar or 1]
	if not (canvas and bar) then return end
	local text = bar.ownText and bar.text or db
	E:ConfigSample(canvas, "icons", {
		count = bar.buttons, columns = bar.perRow, size = bar.size, spacing = bar.spacing,
		keys = text.showHotkey, counts = text.showCount, fontSize = text.hotkeySize or db.fontSize, cooldown = 0.4,
	})
end
Add({ type = "preview", label = "Preview", height = 96, create = UpdatePreview, update = UpdatePreview,
	desc = "The picked bar with sample spells, in its size, grid and texts." })
Add({ type = "select", key = "optionsBar", label = "Bar", values = BarValues, desc = "The bar whose settings show below." })
Add({ type = "description", label = "Bars 1 to 3 take the keys and spells of your key set. Bar 4 and up stay yours; Fill bars 4 and 5 only uses empty buttons." })
for _, row in ipairs(E:CopySettingsOptions({ path = function() return "bars." .. ((M.db and M.db.optionsBar) or 1) end,
	values = BarPaths, keep = { "enabled", "shown", "hiddenMouseover", "blizzard" },
	desc = "Copies every setting of another bar to this one after a preview, or applies this bar's settings to all bars. Its switch and position stay. Right-click a row to set only that row everywhere." })) do Add(row) end
for index = 1, NUM_BARS do AddBar(index) end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
Add({ type = "tab", label = "Buttons" })
Add({ type = "header", label = "Look" })
Add({ type = "range", key = "buttonZoom", label = "Icon zoom", min = 0, max = 20, step = 1, desc = "Percent of the icon edge cut away, so the round icon border doesn't show." })
Add({ type = "select", key = "highlightStyle", label = "Mouse-over highlight", values = STYLE, desc = "How a button shows that the mouse is over it." })
Add({ type = "select", key = "pushedStyle", label = "Pressed look", values = STYLE, desc = "How a button shows that it is pressed." })
Add({ type = "toggle", key = "flyoutSkin", label = "Skin flyouts", desc = "Give spell flyout buttons the EldoUI look. Blizzard's flyout follows the Skin switch of Action button look." })
Add({ type = "select", key = "endCaps", label = "Main bar end caps", values = { keep = "Keep", hide = "Hide" },
	desc = "The gryphons beside Blizzard's main bar (also with this module off; needs \"Let EldoUI change this\" on Main action bar) and, with Vanilla Original, beside EldoUI's bar 1." })
Add({ type = "toggle", key = "hudTray", label = "Tray behind bars 1 and 2",
	desc = "One panel in your skin's material behind bars 1 and 2, so both rows sit in a single tray. Twin Orbs turns it on; Vanilla Original keeps its classic tray under bar 1." })
Add({ type = "header", label = "State colors" })
Add({ type = "select", key = "rangeColoring", label = "Out of range", values = { button = L["Tint the icon"], hotkey = "Tint the keybind", off = "No tint" }, desc = "How a button shows that the target is out of range." })
Add({ type = "color", key = "rangeColor", label = "Out of range color", desc = "Tint for actions whose target is out of range." })
Add({ type = "color", key = "manaColor", label = "Not enough power color", desc = "Tint for actions you lack the mana, rage or energy for." })
Add({ type = "color", key = "unusableColor", label = "Not usable color", desc = "Tint for actions you can't use right now for another reason (wrong form, missing target type, and so on)." })
Add({ type = "toggle", key = "equippedBorder", label = "Equipped item border", desc = "A colored border on buttons that hold an item you are wearing (trinkets, for example)." })
Add({ type = "color", key = "equippedColor", label = "Equipped color", dependsOn = "equippedBorder", desc = "Border color for equipped items." })
Add({ type = "header", label = "Proc glow" })
Add({ type = "select", key = "procGlow", label = "Look", values = { blizzard = "As set on the Glows page", eldoui = "EldoUI accent pulse", none = "None" },
	desc = "How a button shows that its spell has procced. The look of \"As set\" is the \"Action bar procs\" row on the Glows page. The game says which spell; EldoUI only draws it." })
Add({ type = "description", label = "Assisted Highlight (the rotation helper) is off on WoW: Forever, so there is no option for it." })
Add({ type = "header", label = "Masque" })
Add({ type = "toggle", key = "masque", label = "Use Masque", reload = true,
	desc = "When the Masque addon is loaded, let it skin EldoUI's buttons (one Masque group per bar). EldoUI's own button art steps aside.",
	requires = function() return M:GetMasque() ~= nil end })

---------------------------------------------------------------------------
-- Spell cues (Cues.lua)
---------------------------------------------------------------------------
local function CuesOff()
	if not (M.db and M.db.cues and M.db.cues.enabled) then return L["Turn on \"%s\" first."]:format(L["Spell cues"]) end
	return nil
end
local function CuePartOff(key, label)
	return function()
		local off = CuesOff()
		if off then return off end
		if not M.db.cues[key] then return L["Turn on \"%s\" first."]:format(L[label]) end
		return nil
	end
end
Add({ type = "tab", label = "Spell cues" })
Add({ type = "description", label = "A flash when the game lights up a spell, and your buffs on the spells they change. Nothing is guessed or cast for you." })
Add({ type = "description", label = function()
	local _, _, title = E:StandsBack(M, "cues")
	return title and L["%s already shows cues on your buttons, so EldoUI's spell cues stay off while it runs."]:format(title) or ""
end, hidden = function() return not E:StandsBack(M, "cues") end })
Add({ type = "toggle", key = "cues.enabled", label = "Spell cues", desc = "Turn the spell cues on. Off by default." })
Add({ type = "header", label = "Proc flash" })
Add({ type = "toggle", key = "cues.flash", label = "Flash on a proc", disabled = CuesOff,
	desc = "When the game lights up a spell (a proc, or a spell you can use now), its buttons flash once. The game's own glow stays as set on the Buttons tab." })
Add({ type = "toggle", key = "cues.sound", label = "Sound on a proc", disabled = CuePartOff("flash", "Flash on a proc"),
	desc = "Play a sound with the flash, at most once every half second. Off by default." })
Add({ type = "media", mediaKind = "sound", key = "cues.soundFile", channel = "cues.soundChannel", label = "Proc sound",
	disabled = CuePartOff("sound", "Sound on a proc"), desc = "The sound the flash plays." })
Add({ type = "header", label = "Buffs on the button" })
Add({ type = "toggle", key = "cues.buffs", label = "Buffs on the spells they change", disabled = CuesOff,
	desc = "A buff of yours that changes a spell glows on that spell's buttons while you have it, such as Maelstrom Weapon on Lightning Bolt. Its look is on the Glows page (Spell cues: buff)." })
Add({ type = "toggle", key = "cues.own", label = "Your effects on their button", disabled = CuesOff,
	desc = "A button glows while the effect it put on you or your target lasts, such as a damage or heal over time, a shield or a seal. Its look is on the Glows page (Spell cues: your effect)." })
Add({ type = "toggle", key = "cues.stacks", label = "Stack count", disabled = CuesOff,
	desc = "Show the number of stacks in the button's top right corner, as the game counts them." })
Add({ type = "toggle", key = "cues.otherBars", label = "Other bar addons", disabled = CuesOff,
	desc = "Also show the cues on buttons of other bar addons. Blizzard's own bars follow Blizzard UI > Action button look: Improve." })

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
Add({ type = "tab", label = "Text" })
Add({ type = "select", key = "textPreset", label = "Text style", values = TextPresetValues,
	desc = "A ready-made set of the text settings below. Changing one of them turns this to Custom. Bars with their own text settings (Bars tab) keep those." })
Add({ type = "header", label = "Keybind" })
Add({ type = "toggle", key = "showHotkey", label = "Show keybind", desc = "Show the key bound to each button." })
Add({ type = "toggle", key = "hotkeyAbbrev", label = "Short key names", desc = "Write keys short: S for Shift, C for Ctrl, A for Alt, M4 for mouse button 4, MwU for wheel up." })
Add({ type = "range", key = "fontSize", label = "Keybind size", min = 6, max = 24, step = 1, desc = "Text size of the keybind." })
Add({ type = "select", key = "hotkeyPosition", label = "Keybind position", values = ANCHORS, desc = "Where on the button the keybind sits." })
Add({ type = "color", key = "hotkeyColor", label = "Keybind color", desc = "Color of the keybind text (out of range may tint it, Buttons tab)." })
Add({ type = "header", label = "Charges and count" })
Add({ type = "toggle", key = "showCount", label = "Show count", desc = "Show charges and item counts." })
Add({ type = "range", key = "countSize", label = "Count size", min = 6, max = 24, step = 1, desc = "Text size of the count." })
Add({ type = "select", key = "countPosition", label = "Count position", values = ANCHORS, desc = "Where on the button the count sits." })
Add({ type = "color", key = "countColor", label = "Count color", desc = "Color of charges and item counts." })
Add({ type = "header", label = "Macro name" })
Add({ type = "toggle", key = "showMacro", label = "Show macro name", desc = "Show the name of macros on their button." })
Add({ type = "range", key = "macroSize", label = "Macro name size", min = 6, max = 24, step = 1, desc = "Text size of the macro name." })
Add({ type = "color", key = "macroColor", label = "Macro name color", desc = "Color of macro names." })
Add({ type = "header", label = "Font" })
Add({ type = "select", key = "textOutline", label = "Outline", values = OUTLINE, desc = "Outline of every button text. Theme follows the outline set on the Fonts and text page.",
	cog = {
		{ type = "range", key = "textOffsetX", label = "Nudge sideways", min = -10, max = 10, step = 1, desc = "Moves the corner texts towards the middle of the button (positive) or towards its edge (negative)." },
		{ type = "range", key = "textOffsetY", label = "Nudge up or down", min = -10, max = 10, step = 1, desc = "Moves the top and bottom texts towards the middle of the button (positive) or towards its edge (negative)." },
	} })

---------------------------------------------------------------------------
-- Cooldowns
---------------------------------------------------------------------------
Add({ type = "tab", label = "Cooldowns" })
Add({ type = "description", label = "The game itself writes the cooldown numbers and draws the swipe; EldoUI only picks the format and colors, so they work in combat too." })
Add({ type = "header", label = "Cooldown numbers" })
Add({ type = "select", key = "cooldownText", label = "Drawn by", values = { eldoui = "EldoUI format", blizzard = "Game setting", off = "Off" },
	desc = "EldoUI format: seconds, minutes and hours with colors and tenths at the end. Game setting: follows Options > Action Bars > Show cooldown numbers. Off: no numbers.",
	cog = {
		{ type = "range", unit = "s", key = "cooldownMinDuration", label = "Minimum length", min = 0, max = 10, step = 0.5, desc = "Cooldowns shorter than this in total (seconds) show no numbers, so the global cooldown stays quiet. The game checks the length; EldoUI never reads it." },
	} })
Add({ type = "range", key = "cooldownSize", label = "Number size", min = 8, max = 32, step = 1, desc = "Text size of the cooldown numbers at the normal base size (smaller on small buttons). The Size under Fonts and text > Cooldown numbers scales it: 16 keeps this size, 24 makes it half again as big." })
Add({ type = "toggle", key = "cooldownOwnLook", label = "Own colors and thresholds",
	desc = "Off: the action bars use the cooldown colors and thresholds of the Fonts and text page, like every other cooldown. On: the rows below set them for the action bars only." })
Add({ type = "range", unit = "s", key = "cooldownExpiring", label = "Expiring below", min = 0, max = 30, step = 1, dependsOn = "cooldownOwnLook", desc = "Seconds left when the numbers turn the expiring color." })
Add({ type = "range", unit = "s", key = "cooldownTenths", label = "Tenths below", min = 0, max = 10, step = 1, dependsOn = "cooldownOwnLook", zeroText = "Never", desc = "Seconds left when tenths of a second show." })
Add({ type = "color", key = "cooldownColor", label = "Minutes and hours", dependsOn = "cooldownOwnLook", desc = "Color of cooldowns of a minute or more." })
Add({ type = "color", key = "cooldownSecondsColor", label = "Seconds", dependsOn = "cooldownOwnLook", desc = "Color of cooldowns under a minute." })
Add({ type = "color", key = "cooldownExpiringColor", label = "Expiring", dependsOn = "cooldownOwnLook", desc = "Color of cooldowns about to end." })
Add({ type = "header", label = "Swipe" })
Add({ type = "range", key = "swipeAlpha", label = "Swipe darkness", unit = "%", min = 0, max = 100, step = 5, desc = "How dark the cooldown swipe over the icon is." })
Add({ type = "toggle", key = "cooldownEdge", label = "Swipe edge", desc = "Draw a bright edge along the cooldown swipe." })
Add({ type = "toggle", key = "drawBling", label = "Flash when ready", desc = "Flash the button when its cooldown ends." })
Add({ type = "select", key = "chargeCooldown", label = "Charge recharge", values = { swipe = "Full swipe", edge = "Edge only", none = "Hidden" },
	desc = "How a spell with charges shows that a charge is coming back while you still have one: a light swipe, only the bright edge, or nothing." })
Add({ type = "toggle", key = "desaturateCooldown", label = "Gray while on cooldown",
	desc = "Show the icon in gray while its action is on cooldown. The game says when; the global cooldown alone doesn't gray it." })

---------------------------------------------------------------------------
-- Pet and stance
---------------------------------------------------------------------------
-- Whole sentences per bar, so translations never glue words together.
local SPECIAL_TEXTS = {
	pet = {
		mode = L["EldoUI bar: the pet bar buttons in an EldoUI frame you can move, resize and fade (needs the Replace switch). Blizzard's bar: left as it is. Hidden: needs the Hide switch."],
		fade = L["Pet bar: visibility and fade"],
	},
	stance = {
		mode = L["EldoUI bar: the stance bar buttons in an EldoUI frame you can move, resize and fade (needs the Replace switch). Blizzard's bar: left as it is. Hidden: needs the Hide switch."],
		fade = L["Stance bar: visibility and fade"],
	},
}

local function AddSpecialBar(key, title, hasHappiness)
	local prefix = key .. "."
	local texts = SPECIAL_TEXTS[key]
	local function modeNot(mode) return function() return M.db[key].mode ~= mode end end
	local eldoui = modeNot("eldoui")
	Add({ type = "header", label = title })
	Add({ type = "select", key = prefix .. "mode", label = "Bar", values = SPECIAL_MODE,
		desc = texts.mode })
	if key == "pet" then
		Add({ type = "range", key = prefix .. "buttons", label = "Buttons", min = 1, max = 10, step = 1, desc = "How many pet buttons show.", hidden = eldoui })
	end
	Add({ type = "range", key = prefix .. "perRow", label = "Buttons per row", min = 1, max = 10, step = 1, desc = "Buttons in each row: this sets how wide the grid is. With the fill order set to columns first, the same grid fills column by column.", hidden = eldoui })
	Add({ type = "range", key = prefix .. "size", label = "Button size", min = 16, max = 64, step = 1, desc = "Width and height of each button.", hidden = eldoui })
	Add({ type = "range", key = prefix .. "spacing", label = "Spacing", min = 0, max = 20, step = 1, desc = "Gap between buttons.", hidden = eldoui })
	Add({ type = "range", key = prefix .. "scale", label = "Scale", unit = "%", min = 50, max = 200, step = 5, desc = "Size of the whole bar in percent.", hidden = eldoui })
	Add({ type = "select", key = prefix .. "growth", label = "Growth direction", values = GROWTH, desc = "Corner the first button sits in.", hidden = eldoui })
	Add({ type = "select", key = prefix .. "fillOrder", label = "Fill order", values = FILL_ORDER,
		desc = "Rows first: the buttons fill each row before the next row starts. Columns first: they fill each column from the first corner before the next column starts, as on an upright bar. Default: Rows first.", hidden = eldoui })
	Add({ type = "toggle", key = prefix .. "backdrop", label = "Background", desc = "Draw an EldoUI panel behind the bar.", hidden = eldoui,
		cog = { { type = "range", key = prefix .. "backdropPadding", label = "Background padding", min = 0, max = 16, step = 1, desc = "Space around the buttons inside the backdrop." } } })
	if hasHappiness then
		Add({ type = "toggle", key = prefix .. "happiness", label = "Happiness border", desc = "Color the pet bar border by the happiness the game reports for your pet (green, yellow, red).", hidden = eldoui, disabled = E:BlizzardNeeds("pet-stance-bars", "improve") })
		Add({ type = "toggle", key = prefix .. "autocastGlow", label = "Autocast glow", desc = "Show the game's spinning glow on pet abilities set to autocast." })
	end
	for _, row in ipairs(VisibilityRows(prefix .. "fade", eldoui, function(row)
		if row.type == "header" then row.label = texts.fade end
	end)) do Add(row) end
	Add({ type = "range", key = prefix .. "alpha", label = "Opacity", unit = "%", min = 0, max = 100, step = 5, desc = "Opacity while shown and not faded.", hidden = eldoui })
	Add({ type = "input", key = prefix .. "customVisibility", label = "Custom conditions", cog = true, hidden = eldoui,
		desc = key == "pet" and L["Advanced: macro conditions ending in show or hide; when filled they replace the Show rule. The bar only ever shows while you have a pet with a bar."]
			or L["Advanced: macro conditions ending in show or hide; when filled they replace the Show rule. The bar only ever shows when you have stances or forms."] })
end

Add({ type = "tab", label = "Pet and stance" })
AddSpecialBar("pet", E.Key("Pet bar"), true)
AddSpecialBar("stance", E.Key("Stance bar"), false)

---------------------------------------------------------------------------
-- Vehicle, extra ability, totems and the rest
---------------------------------------------------------------------------
Add({ type = "tab", label = "Special" })
Add({ type = "header", label = "Vehicles" })
Add({ type = "select", key = "vehicle.overrideBar", label = "Vehicle bar", values = { eldoui = "Bar 1 shows vehicle actions", blizzard = "Blizzard's vehicle bar" },
	desc = "Bar 1: Blizzard's override and vehicle bar is hidden and EldoUI's bar 1 shows the vehicle's actions (needs the Hide switch of Vehicle bars and bar 1 on). Blizzard's: its own skinned vehicle bar shows." })
Add({ type = "select", key = "vehicle.exit", label = "Leave vehicle button", values = { auto = "When Blizzard's is hidden", always = "Always EldoUI's", never = "Never" },
	desc = "EldoUI's movable leave-vehicle button. Shown while you can leave a vehicle or a flight path early. Automatic: only when Blizzard's button is hidden with its bar." })
Add({ type = "range", key = "vehicle.exitSize", label = "Leave button size", min = 20, max = 64, step = 1, desc = "Size of EldoUI's leave-vehicle button." })
Add({ type = "select", key = "vehicle.seat", label = "Seat indicator", values = { keep = "Blizzard's place", move = "EldoUI mover", hide = "Hidden" },
	desc = "The vehicle seat picker. Mover needs the Move switch of Vehicle bars, Hidden the Hide switch." })
Add({ type = "range", key = "vehicle.seatScale", label = "Seat indicator scale", unit = "%", min = 50, max = 200, step = 5, desc = "Size of the seat indicator in percent while it uses the EldoUI mover." })
Add({ type = "header", label = "Possess bar" })
Add({ type = "select", key = "possess.mode", label = "Mode", values = { eldoui = "EldoUI frame", blizzard = "Blizzard's bar" },
	desc = "The cancel and attack buttons while you control another unit. EldoUI frame: Blizzard's buttons in a movable EldoUI frame (needs the Replace switch of Vehicle bars)." })
Add({ type = "range", key = "possess.size", label = "Button size", min = 16, max = 64, step = 1, desc = "Size of the possess buttons." })
Add({ type = "range", key = "possess.spacing", label = "Spacing", min = 0, max = 20, step = 1, desc = "Gap between the possess buttons." })
Add({ type = "range", key = "possess.scale", label = "Scale", unit = "%", min = 50, max = 200, step = 5, desc = "Size of the possess frame in percent." })
Add({ type = "header", label = "Zone ability" })
Add({ type = "range", key = "extra.scale", label = "Scale", unit = "%", min = 50, max = 200, step = 5, desc = "Size of the zone ability button in percent.", disabled = E:BlizzardNeeds("extra-zone-ability", "move") })
Add({ type = "toggle", key = "extra.hideArt", label = "Hide frame art", desc = "Hide the decorative frame around the zone ability; the button stays.", disabled = E:BlizzardNeeds("extra-zone-ability", "hide") })
Add({ type = "header", label = "Shaman totem bar" })
Add({ type = "range", key = "totem.scale", label = "Scale", unit = "%", min = 50, max = 200, step = 5, desc = "Size of the totem bar in percent while it uses the EldoUI mover (Move switch of Totem bar)." })
Add({ type = "header", label = "Proc alerts" })
Add({ type = "range", key = "proc.scale", label = "Scale", unit = "%", min = 50, max = 200, step = 5, desc = "Size of the spell alerts around your character while they use the EldoUI mover (Move switch of Action button look). The Hide switch turns them off." })
Add({ type = "range", key = "proc.alpha", label = "Opacity", unit = "%", min = 0, max = 100, step = 5, desc = "Opacity of the spell alerts while they use the EldoUI mover." })
Add({ type = "header", label = "Gamepad HUD" })
Add({ type = "range", key = "gamepad.scale", label = "Scale", unit = "%", min = 50, max = 200, step = 5, desc = "Size of the controller action bar while it uses the EldoUI mover (Move switch of Gamepad HUD)." })

M.options = options

-- End caps, spell ranks, the rank check, spell cues, new spells and the
-- bar 4 and 5 fill also work while the module is off.
M.refreshWhenOff = function(module)
	if module.UpdateEndCaps then module:UpdateEndCaps() end
	if module.ApplyRankCheck then module:ApplyRankCheck() end
	if module.ApplyCues then module:ApplyCues() end
	if E.KeymapAutomationChanged then E:KeymapAutomationChanged() end
end

---------------------------------------------------------------------------
-- Layout choices in each bar's move box menu (Core/MoveSetup.lua): they
-- set this page's "Buttons per row" for the bar, and Options… opens this
-- page on that bar.
---------------------------------------------------------------------------
local BAR_LAYOUTS = {
	{ key = "horizontal", label = "Horizontal", desc = "All buttons of the bar in one row." },
	{ key = "vertical", label = "Vertical", desc = "All buttons of the bar in one column." },
	{ key = "grid", label = "Grid", desc = "The buttons in two rows. Buttons per row on the options page sets any other grid." },
}
M.BAR_LAYOUTS = BAR_LAYOUTS -- exposed for inspection

local function BarLayout(index)
	local bar = M.db and M.db.bars and M.db.bars[index]
	if not bar then return nil end
	local buttons = math.max(1, tonumber(bar.buttons) or 12)
	local perRow = tonumber(bar.perRow) or buttons
	if perRow >= buttons then return "horizontal" end
	if perRow <= 1 then return "vertical" end
	return "grid"
end

local function SetBarLayout(index, key)
	local bar = M.db and M.db.bars and M.db.bars[index]
	if not bar then return end
	local buttons = math.max(1, tonumber(bar.buttons) or 12)
	if key == "horizontal" then
		bar.perRow = buttons
	elseif key == "vertical" then
		bar.perRow = 1
	else
		bar.perRow = math.max(1, math.ceil(buttons / 2))
	end
	E:RefreshModule(M, true)
end

-- Size and Spacing submenus beside Layout: the same settings as the
-- page's Button size and Spacing sliders, in a few common steps.
local SIZES = { 24, 28, 32, 36, 40, 44, 48 }
local SPACINGS = { 0, 2, 4, 6, 8 }
local function Pixels(value) return L["%d px"]:format(value) end
M.BAR_SIZES, M.BAR_SPACINGS = SIZES, SPACINGS -- exposed for inspection

local function Steps(store)
	local function Setter(key)
		return function(value)
			local db = store()
			if not db then return end
			db[key] = value
			E:RefreshModule(M, true)
		end
	end
	local function Getter(key)
		return function()
			local db = store()
			return db and tonumber(db[key])
		end
	end
	return {
		{ label = "Size", values = SIZES, get = Getter("size"), set = Setter("size"), format = Pixels },
		{ label = "Spacing", values = SPACINGS, get = Getter("spacing"), set = Setter("spacing"), format = Pixels },
	}
end

local function Refresh() E:RefreshModule(M, true) end

for index = 1, NUM_BARS do
	local function Store() return M.db and M.db.bars and M.db.bars[index] end
	E:SetMoverLayouts("EldoUI_ActionBar" .. index, {
		get = function() return BarLayout(index) end,
		set = function(key) SetBarLayout(index, key) end,
		choices = BAR_LAYOUTS,
		steps = Steps(Store),
		store = Store, keys = { "perRow", "size", "spacing" }, apply = Refresh,
		options = { page = "module:ActionBars", key = ("bars.%d.perRow"):format(index) },
		beforeOptions = function() if M.db then M.db.optionsBar = index end end,
	})
end

-- The pet and stance bars: the same choices while EldoUI draws them (Bar:
-- EldoUI bar). Their button count is the pet's buttons or your forms.
local function SpecialCount(key)
	local db = M.db and M.db[key]
	if not db then return 10 end
	if key == "stance" then
		local forms = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
		return math.max(1, forms > 0 and forms or 10)
	end
	return math.max(1, tonumber(db.buttons) or 10)
end

local function SpecialLayout(key)
	local db = M.db and M.db[key]
	if not db then return nil end
	local buttons = SpecialCount(key)
	local perRow = tonumber(db.perRow) or buttons
	if perRow >= buttons then return "horizontal" end
	if perRow <= 1 then return "vertical" end
	return "grid"
end

local function SetSpecialLayout(key, choice)
	local db = M.db and M.db[key]
	if not db then return end
	if choice == "horizontal" then
		-- Every button in one row, also when more forms are learned later.
		db.perRow = 10
	elseif choice == "vertical" then
		db.perRow = 1
	else
		db.perRow = math.max(1, math.ceil(SpecialCount(key) / 2))
	end
	E:RefreshModule(M, true)
end

local SPECIAL_LAYOUTS = {
	{ key = "horizontal", label = "Horizontal", desc = "All buttons of the bar in one row." },
	{ key = "vertical", label = "Vertical", desc = "All buttons of the bar in one column." },
	{ key = "grid", label = "Grid", desc = "The buttons in two rows. Buttons per row on the options page sets any other grid." },
}
M.SPECIAL_LAYOUTS = SPECIAL_LAYOUTS -- exposed for inspection

for key, name in pairs({ pet = "EldoUI_PetBar", stance = "EldoUI_StanceBar" }) do
	local function Store() return M.db and M.db[key] end
	E:SetMoverLayouts(name, {
		get = function() return SpecialLayout(key) end,
		set = function(choice) SetSpecialLayout(key, choice) end,
		choices = SPECIAL_LAYOUTS,
		steps = Steps(Store),
		store = Store, keys = { "perRow", "size", "spacing" }, apply = Refresh,
		options = { page = "module:ActionBars", key = key .. ".perRow" },
	})
end

---------------------------------------------------------------------------
-- Style presets
---------------------------------------------------------------------------
-- Looks only: button size and spacing on the three main rows, the button
-- text and the icon crop. Which bars are on and how many buttons a row
-- holds belong to the layout (its points are made for that shape), so a
-- style never turns on a bar the layout has no spot for. A style without
-- a size keeps the layout's own button size.
local TEXTS = {
	standard = { textPreset = "standard", showHotkey = true, fontSize = 13, hotkeyPosition = "TOPRIGHT",
		showCount = true, countSize = 14, countPosition = "BOTTOMRIGHT", showMacro = false, macroSize = 11 },
	compact = { textPreset = "compact", showHotkey = true, fontSize = 10, hotkeyPosition = "TOPRIGHT",
		showCount = true, countSize = 11, countPosition = "BOTTOMRIGHT", showMacro = false, macroSize = 9 },
	large = { textPreset = "large", showHotkey = true, fontSize = 16, hotkeyPosition = "TOPRIGHT",
		showCount = true, countSize = 17, countPosition = "BOTTOMRIGHT", showMacro = false, macroSize = 13 },
	macros = { textPreset = "macros", showHotkey = true, fontSize = 12, hotkeyPosition = "TOPRIGHT",
		showCount = true, countSize = 13, countPosition = "BOTTOMRIGHT", showMacro = true, macroSize = 10 },
	clean = { textPreset = "clean", showHotkey = false, fontSize = 13, hotkeyPosition = "TOPRIGHT",
		showCount = true, countSize = 14, countPosition = "BOTTOMRIGHT", showMacro = false, macroSize = 11 },
}
local function Buttons(text, zoom, size, spacing)
	local settings = CopyTable(TEXTS[text])
	settings.buttonZoom = zoom
	if size then
		local bar = { size = size, spacing = spacing }
		settings.bars = { CopyTable(bar), CopyTable(bar), CopyTable(bar) }
	end
	return settings
end

-- Which bars are on and how many buttons a row holds is placement: a
-- style that writes one of these keys is reported once and the key is
-- left out of it (Core/Styles.lua).
local LAYOUT_KEYS = { "enabled", "shown", "perRow", "buttons" }
local function LayoutOwned(settings, found)
	local bars = type(settings.bars) == "table" and settings.bars or {}
	for index = 1, 5 do
		local bar = bars[index]
		if type(bar) == "table" then
			for _, key in ipairs(LAYOUT_KEYS) do
				if bar[key] ~= nil then found[#found + 1] = { bar, key, ("bars[%d].%s"):format(index, key) } end
			end
		end
	end
end

E:RegisterStyles("ActionBars", {
	{ key = "Standard", title = "Standard", desc = "Keybinds and charges in the corners, at the layout's own button size.",
		settings = Buttons("standard", 8) },
	{ key = "Clean", title = "Clean", desc = "No keybind text and a tighter icon crop, at the layout's own button size.",
		settings = Buttons("clean", 12) },
	{ key = "Macros", title = "Macro names", desc = "Keybinds plus the macro name on each button, at the layout's own button size.",
		settings = Buttons("macros", 8) },
	{ key = "Compact", title = "Compact", desc = "36 px buttons with 2 px gaps on the three main rows, and smaller text.",
		settings = Buttons("compact", 8, 36, 2) },
	{ key = "Large", title = "Large", desc = "52 px buttons on the three main rows and bigger text, for big screens.",
		settings = Buttons("large", 8, 52, 4) },
}, { layoutOwned = LayoutOwned })
