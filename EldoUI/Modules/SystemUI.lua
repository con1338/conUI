-- EldoUI System windows: the game's system and settings windows in the
-- EldoUI look, plus small opt-in helpers on top of them.
--
--   Game menu (Esc)        skin, move and scale, an "EldoUI" button under the menu
--   Settings window        skin of the window frame only, never its controls; move and scale
--   AddOn list             skin, move and scale, rows tagged when an addon keeps an
--                          EldoUI module off
--   Quick keybind mode     skin; EldoUI's own buttons can be bound while Blizzard's mode
--                          is open; EldoUI key sets under the window
--   Macros, click binding  skin, move and scale; a Click-Cast Tips line under the
--                          click-binding window
--   Pop-ups                skin pop-ups, color picker and stack split; a mover and a
--                          scale for the pop-up stack; DELETE typed in for you;
--                          the quest an item belongs to under the delete pop-up
--   Shop, help, report     never skinned or moved (secure store); only the Shop micro
--                          button can be hidden
--
-- Every Blizzard frame is touched only while its element switch in
-- Core/Blizzard.lua allows it (Blizzard UI > System and settings windows).
-- With the switch off nothing here hooks, skins, moves or hides it.
--
-- Presentation only. Nothing is clicked, accepted or confirmed for the
-- player: the DELETE helper only types the word, you still press Yes.
-- Blizzard art is made invisible with SetAlpha(0) through Core/Skin.lua,
-- hooks are hooksecurefunc / HookScript, per-frame state lives in local
-- weak tables, and the Settings and Edit Mode internals are never called.
-- Written from scratch for EldoUI; no code or media from other addons.
local _, E = ...
local L = E.L

local M = E:NewModule("SystemUI", {
	title = "System Windows",
	category = "Interface",
	desc = "Game menu, Settings, AddOn list, keybinds, macros and pop-ups in the EldoUI look, with a few safe extras.",
	defaults = {
		transparent = false,     -- see-through panels
		-- skins (each also needs the element's Skin switch)
		skinGameMenu = true,
		skinSettings = true,
		skinAddonList = true,
		skinQuickKeybind = true,
		skinMacro = true,
		skinClickBinding = true,
		skinPopups = true,
		skinColorPicker = true,
		skinStackSplit = true,
		-- extras
		menuButton = true,       -- "EldoUI" button in the game menu, above AddOns
		addonConflicts = true,   -- tag AddOn list rows that keep an EldoUI module off
		quickKeybindEldo = true, -- EldoUI buttons bindable in Blizzard's Quick Keybind mode
		quickKeybindPresets = true,
		clickCastLine = true,    -- Click-Cast Tips line under the click-binding window
		fillDelete = false,      -- type DELETE into the delete-item pop-up (acts for you: off until ticked)
		deleteContext = true,    -- quest context under the delete-item pop-up
		holdShiftRelease = false, -- require Shift for ordinary instance releases
		popupMover = true,       -- pop-ups follow the "Pop-up Dialogs" mover
		hideStoreButton = true,  -- hide the Shop micro button (needs the element's Hide switch)
		-- pop-up scale (needs the dialogs element's Move switch); windows are
		-- moved and scaled by the window mover (Core/WindowMover.lua)
		scale = { popups = 1 },
	},
})

---------------------------------------------------------------------------
-- State (never written into Blizzard frames)
---------------------------------------------------------------------------
local hooked = {}                                         -- [name] = true once a hook is installed
local skinned = {}                                        -- [name] = true once a window is skinned
local rowTags = setmetatable({}, { __mode = "k" })        -- AddOn list row -> { tag, tint }
local popupScaled = setmetatable({}, { __mode = "k" })    -- pop-up -> true while we scaled it
local own = {}                                            -- our own frames
local conflictMap                                         -- [addon name lower] = { module titles }
local storeHidden = false
local quickKeybind = {}                                   -- EldoUI keybind mode running inside Blizzard's

local DELETE_DIALOGS = { DELETE_GOOD_ITEM = true, DELETE_GOOD_QUEST_ITEM = true }
-- Every delete-item pop-up, with or without the typed word.
local ANY_DELETE = { DELETE_ITEM = true, DELETE_GOOD_ITEM = true, DELETE_QUEST_ITEM = true, DELETE_GOOD_QUEST_ITEM = true }
local contextStrips = setmetatable({}, { __mode = "k" })  -- pop-up -> our quest strip under it
local POPUP_COUNT = 4

local function Usable(frame)
	return type(frame) == "table" and type(frame.GetObjectType) == "function"
		and not E.FrameCheck(frame, "IsForbidden")
end

local function Try(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then geterrorhandler()(err) end
	return ok
end

-- Install a hook the first time an element is switched on. Hooks stay, and
-- each one checks the switch again every time it runs.
local function Once(name, fn)
	if hooked[name] then return end
	hooked[name] = true
	Try(fn)
end

-- The element switch, and only while this module is on.
local function Allowed(id, action)
	return M.active and E:BlizzardAllowed(id, action)
end

local function SkinOn(id, option)
	return Allowed(id, "skin") and M.db[option]
end

-- Every window skin here is recorded (E:SkinRecord in Core/Skin.lua), one
-- record per window: switching its look off puts Blizzard's window back at
-- once, and switching it on paints it again, both without a reload.
local RECORDS = {
	gameMenu = "game-menu", settings = "settings-panel", addonList = "addon-list", quickKeybind = "keybindings",
	macro = "macros-click-binding:macro", clickBinding = "macros-click-binding:click",
	popups = "dialogs:popups", colorPicker = "dialogs:colorPicker", stackSplit = "dialogs:stackSplit",
}

-- The record of one window to what is wanted. `build` runs inside the
-- record and skins what is not skinned yet.
local function Want(name, roots, want, build, ...)
	local key = RECORDS[name]
	if not want then
		E:SkinRecordOff(key)
		return false
	end
	E:SkinRecordOn(key)
	E:SkinRecord(key, roots, build, ...)
	return true
end

local function Skinned(name)
	return E:SkinRecordState(RECORDS[name]) == "on"
end

-- Protected frames are only changed out of combat.
local function Changeable(frame)
	return Usable(frame) and not (E.FrameCheck(frame, "IsProtected") and InCombatLockdown())
end

local function AccentHex()
	local c = E.media.accentText
	return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

local function SkinButtons(list, opts)
	for _, button in ipairs(list) do
		if Usable(button) then E:SkinButton(button, opts) end
	end
end

-- Dialog headers (DialogHeaderTemplate): art invisible, the title in the
-- theme font inside the panel instead of on its edge.
local function SkinHeader(header, parent, y)
	if not Usable(header) then return end
	E:StripTextures(header, nil, true)
	local text = header.Text
	if text and text.SetFont then
		E:SetFont(text, E.tokens.size.dialogTitle)
		text:SetTextColor(1, 1, 1)
		text:ClearAllPoints()
		text:SetPoint("TOP", parent, "TOP", 0, y or -9)
	end
end

---------------------------------------------------------------------------
-- Game menu
---------------------------------------------------------------------------
local function SkinGameMenuButtons()
	local menu = GameMenuFrame
	if not Skinned("gameMenu") or type(menu.buttons) ~= "table" then return end
	E:SkinRecord(RECORDS.gameMenu, menu, SkinButtons, menu.buttons, { size = 14 })
end

local function SkinGameMenu()
	local menu = GameMenuFrame
	if not Usable(menu) then return end
	Want("gameMenu", menu, SkinOn("game-menu", "skinGameMenu"), function()
		if skinned.gameMenu then return end
		skinned.gameMenu = true
		E:SkinPanel(menu, { transparent = M.db.transparent, accentOffset = 30, close = false, insets = false, title = false })
		E:SkinAlphaZero(menu.Border)
		SkinHeader(menu.Header, menu, -10)
	end)
	SkinGameMenuButtons()
end

-- More EldoUI buttons after EldoUI's own, each its own named frame (never
-- GameMenuFrame:AddButton, so Blizzard's list is not touched):
--   M:RegisterMenuButton(key, { name, text = fn, order, shown = fn,
--       tooltip = fn(tooltip), onClick = fn(mouseButton) })
-- They follow the same switch as the EldoUI button (Improve), and follow
-- it, or stand alone while that button is off (My Adventure).
--
-- Placement: the menu stacks its buttons by layoutIndex and grows to fit
-- them. While Blizzard UI > Game menu (Esc) lets EldoUI improve it, EldoUI's
-- buttons take a place in that stack right above AddOns, in the same
-- button look, so the menu's frame runs down around them. Otherwise, or
-- when the menu has no AddOns button, they hang under the menu by their
-- own anchors and no field of the menu or its buttons is written.
local menuButtons, menuButtonOrder = {}, {}
local UpdateMenuButton, PlaceMenuButtons

function M:RegisterMenuButton(key, def)
	if type(key) ~= "string" or type(def) ~= "table" or type(def.onClick) ~= "function" then return end
	if not menuButtons[key] then menuButtonOrder[#menuButtonOrder + 1] = key end
	local old = menuButtons[key]
	menuButtons[key] = { key = key, name = def.name, text = def.text, order = tonumber(def.order) or 50, shown = def.shown,
		tooltip = def.tooltip, onClick = def.onClick, button = old and old.button }
	table.sort(menuButtonOrder, function(a, b)
		if menuButtons[a].order ~= menuButtons[b].order then return menuButtons[a].order < menuButtons[b].order end
		return a < b
	end)
	if GameMenuFrame and GameMenuFrame:IsShown() then Try(UpdateMenuButton) end
end

function M:UnregisterMenuButton(key)
	local def = menuButtons[key]
	if not def then return end
	if def.button then def.button:Hide() end
	menuButtons[key] = nil
	for index, name in ipairs(menuButtonOrder) do
		if name == key then table.remove(menuButtonOrder, index) break end
	end
end

-- The button of a registered entry (for tours and plugins).
function M:MenuButton(key)
	local def = menuButtons[key]
	return def and def.button
end

local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, value = pcall(fn, ...)
	if ok then return value end
end

local sectionGap = setmetatable({}, { __mode = "k" }) -- AddOns button -> its section gap

-- Blizzard's AddOns button in the menu's stack, if the menu shows one.
local function AddOnsButton(menu)
	if type(menu.buttons) ~= "table" or type(menu.MarkDirty) ~= "function" then return nil end
	local label = _G.ADDONS
	for _, button in ipairs(menu.buttons) do
		if Usable(button) and button.GetText and type(button.layoutIndex) == "number" then
			local text = button:GetText()
			if label and type(text) == "string" and text == label then return button end
		end
	end
end

-- A button that looks like the menu's own: the menu's button template and
-- the size of its buttons.
local function NewMenuButton(name, menu)
	local ok, button = pcall(CreateFrame, "Button", name, menu, "GameMenuFrameButtonTemplate")
	if not ok or not button then button = CreateFrame("Button", name, menu, "UIPanelButtonTemplate") end
	local sample = type(menu.buttons) == "table" and menu.buttons[1]
	local width, height = 200, 28
	if Usable(sample) then
		local w, h = sample:GetSize()
		if type(w) == "number" and w > 0 then width = w end
		if type(h) == "number" and h > 0 then height = h end
	end
	button:SetSize(width, height)
	return button
end

-- Puts EldoUI's shown buttons (in order) right above AddOns, inside the
-- menu's own stack, taking over the section gap so AddOns sits under them.
-- Without an AddOns button, or while the game menu switch is off, they
-- stack under the menu.
function PlaceMenuButtons(menu, list)
	local anchor = Allowed("game-menu", "improve") and AddOnsButton(menu)
	if anchor then
		local base, count = anchor.layoutIndex, #list
		for index, button in ipairs(list) do
			button:ClearAllPoints()
			button.layoutIndex = base - 1 + index / (count + 1)
			button.topPadding = nil
		end
		-- The gap above AddOns moves to the first EldoUI button. Blizzard sets
		-- it again each time it rebuilds the menu (NoteMenuBuild); remember
		-- it in between. AddOns may have no gap at all (store button above it).
		if sectionGap[anchor] == nil then sectionGap[anchor] = anchor.topPadding or false end
		local gap = sectionGap[anchor] or nil
		if count > 0 then
			list[1].topPadding = gap
			anchor.topPadding = nil
		else
			anchor.topPadding = gap
		end
		menu:MarkDirty()
		return
	end
	local below
	for _, button in ipairs(list) do
		button.layoutIndex, button.topPadding = nil, nil
		button:ClearAllPoints()
		if below then
			button:SetPoint("TOP", below, "BOTTOM", 0, -4)
		else
			button:SetPoint("TOP", menu, "BOTTOM", 0, -6)
		end
		below = button
	end
end

-- The menu rebuilt its buttons (it does on every show and event): read the
-- AddOns gap afresh, since the pooled buttons can change roles.
local function NoteMenuBuild(menu)
	local anchor = AddOnsButton(menu)
	if anchor then sectionGap[anchor] = anchor.topPadding or false end
end

local function UpdateExtraButtons(menu, first, show)
	local placed = { first }
	for _, key in ipairs(menuButtonOrder) do
		local def = menuButtons[key]
		local wanted = show and (def.shown == nil or Call(def.shown))
		if not wanted then
			if def.button then def.button:Hide() end
		else
			local button = def.button
			if not button then
				button = NewMenuButton(def.name, menu)
				button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
				button:SetScript("OnClick", function(_, mouse)
					PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
					HideUIPanel(GameMenuFrame)
					def.onClick(mouse)
				end)
				button:SetScript("OnEnter", function(self)
					if type(def.tooltip) ~= "function" then return end
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					Call(def.tooltip, GameTooltip)
					GameTooltip:Show()
				end)
				button:SetScript("OnLeave", function() GameTooltip:Hide() end)
				def.button = button
			end
			-- Text first: the skin sets the font on the label, which a button
			-- only has once it has text.
			button:SetText(Call(def.text) or key)
			if Skinned("gameMenu") then E:SkinRecord(RECORDS.gameMenu, button, E.SkinButton, E, button, { size = 14 }) end
			button:Show()
			placed[#placed + 1] = button
		end
	end
	PlaceMenuButtons(menu, placed)
end

-- EldoUI's own buttons follow EldoUI's own setting, also before the
-- setup turns on Blizzard UI > Game menu (Esc); only the look and the place in
-- the menu's stack wait for that switch.
function UpdateMenuButton()
	local menu = GameMenuFrame
	local allowed = M.active and Usable(menu)
	local show = allowed and M.db.menuButton
	if not show then
		if own.menuButton then own.menuButton:Hide() end
		-- With the module off, the other EldoUI buttons leave the menu too.
		if menu then UpdateExtraButtons(menu, nil, allowed) end
		return
	end
	local button = own.menuButton
	if not button then
		button = NewMenuButton("EldoUI_GameMenuButton", menu)
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		button:SetScript("OnClick", function(_, mouse)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
			HideUIPanel(GameMenuFrame)
			-- Besides /eui, this button is the one way into the settings
			-- (Core/Config.lua); in combat they open when combat ends.
			if mouse == "RightButton" then
				E:ToggleMoveMode(true)
			else
				E:OpenConfigFromGameMenu()
			end
		end)
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(E.brand or "EldoUI") -- no-L: addon name
			E:TooltipHint(GameTooltip, { L["Click"], L["open the EldoUI options"] })
			E:TooltipHint(GameTooltip, { L["Right-click"], L["move EldoUI's frames"] })
			E.UIKit.TipText(GameTooltip, L["Also /eui in chat."])
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
		own.menuButton = button
	end
	button:SetText(E.brand or "EldoUI") -- no-L: addon name
	-- After the text, so the menu's button font reaches the label too.
	if Skinned("gameMenu") then E:SkinRecord(RECORDS.gameMenu, button, E.SkinButton, E, button, { size = 14 }) end
	button:Show()
	UpdateExtraButtons(menu, button, M.active)
end

local function ApplyGameMenu()
	local menu = GameMenuFrame
	if not Usable(menu) then return end
	if M.active then
		Once("gameMenu", function()
			-- The menu builds its buttons when it opens and when the store
			-- status changes; skin the pooled buttons after each build (the
			-- skin itself waits for the game menu switch).
			menu:HookScript("OnShow", function()
				if not M.active then return end
				NoteMenuBuild(menu)
				SkinGameMenuButtons()
				UpdateMenuButton()
			end)
			menu:HookScript("OnEvent", function()
				if not M.active then return end
				NoteMenuBuild(menu)
				SkinGameMenuButtons()
				if menu:IsShown() then UpdateMenuButton() end
			end)
		end)
	end
	SkinGameMenu()
	UpdateMenuButton()
end

---------------------------------------------------------------------------
-- Settings window: the frame only, never the settings controls
---------------------------------------------------------------------------
local function SkinSettingsPanel(panel)
	if skinned.settings then return end
	skinned.settings = true
	E:SkinPanel(panel, { transparent = M.db.transparent, accentOffset = 26, close = false, insets = false, title = false })
	-- The title lives on the nine-slice frame: keep the frame, hide its art.
	local nine = panel.NineSlice
	if Usable(nine) then
		nine:SetAlpha(1)
		E:StripTextures(nine, nil, true)
		if nine.Text and nine.Text.SetFont then
			E:SetFont(nine.Text, E.tokens.size.dialogTitle)
			nine.Text:SetTextColor(1, 1, 1)
		end
	end
	E:SkinAlphaZero(panel.Bg)
	E:SkinCloseButton(panel.ClosePanelButton)
	E:SkinTabs({ panel.GameTab, panel.AddOnsTab }, {
		size = 12,
		isSelected = function(tab) return tab.IsSelected and tab:IsSelected() end,
	})
	SkinButtons({ panel.CloseButton, panel.ApplyButton })
	if Usable(panel.SearchBox) then E:SkinEditBox(panel.SearchBox, { left = 2 }) end
	local list = panel.CategoryList
	if Usable(list) then
		E:SkinInset(list)
		if Usable(list.ScrollBar) then E:SkinScrollBar(list.ScrollBar) end
	end
	local container = panel.Container
	local settingsList = container and container.SettingsList
	if Usable(settingsList) and Usable(settingsList.ScrollBar) then E:SkinScrollBar(settingsList.ScrollBar) end
end

local function ApplySettings()
	local panel = SettingsPanel
	if not Usable(panel) then return end
	Want("settings", panel, SkinOn("settings-panel", "skinSettings"), SkinSettingsPanel, panel)
end

---------------------------------------------------------------------------
-- AddOn list
---------------------------------------------------------------------------
-- Which addons do which EldoUI module's job, whole or in part (the
-- registry, Core/AddonConflicts.lua), each module named once.
local function BuildConflicts()
	conflictMap = {}
	local seen = {}
	for _, entry in ipairs(E:CompetitorEntries()) do
		local module = entry.module and E.modules[entry.module]
		if module then
			local key = tostring(entry.addon):lower()
			local mark = key .. "|" .. module.name
			if not seen[mark] then
				seen[mark] = true
				conflictMap[key] = conflictMap[key] or {}
				table.insert(conflictMap[key], L[module.title])
			end
		end
	end
end

local function ConflictsFor(name)
	if type(name) ~= "string" then return end
	if not conflictMap then BuildConflicts() end
	return conflictMap[name:lower()]
end

local function ShowConflicts()
	return Allowed("addon-list") and M.db.addonConflicts
end

function M:TagAddonRow(entry)
	if not Usable(entry) then return end
	local index = entry:GetID()
	local name = ShowConflicts() and index and index > 0 and C_AddOns.GetAddOnName(index)
	local modules = name and ConflictsFor(name)
	local parts = rowTags[entry]
	if not modules then
		if parts then
			parts.tag:Hide()
			parts.tint:Hide()
		end
		return
	end
	if not parts then
		parts = {}
		parts.tint = entry:CreateTexture(nil, "BACKGROUND", nil, -4)
		parts.tint:SetAllPoints()
		parts.tag = E:CreateText(entry, E.tokens.size.tiny, "LEFT")
		if entry.Title then
			parts.tag:SetPoint("LEFT", entry.Title, "RIGHT", 4, 0)
		else
			parts.tag:SetPoint("RIGHT", -120, 0)
		end
		rowTags[entry] = parts
	end
	local loaded = C_AddOns.IsAddOnLoaded(name)
	if loaded then
		parts.tint:SetColorTexture(E:TokenColor("warn", 0.14))
		parts.tag:SetText(E:TextHex("warn") .. (#modules > 1 and L["EldoUI: keeps %d modules off"] or L["EldoUI: keeps %d module off"]):format(#modules) .. "|r")
	else
		parts.tint:SetColorTexture(E:TokenColor("gold", 0.07))
		parts.tag:SetText(E:TextHex("secondary") .. (#modules > 1 and L["EldoUI: would keep %d modules off"] or L["EldoUI: would keep %d module off"]):format(#modules) .. "|r")
	end
	parts.tint:Show()
	parts.tag:Show()
end

function M:AddonTooltipLine(owner)
	if not ShowConflicts() or not Usable(owner) or not AddonTooltip then return end
	local index = owner.GetID and owner:GetID()
	local name = index and index > 0 and C_AddOns.GetAddOnName(index)
	local modules = name and ConflictsFor(name)
	if not modules then return end
	AddonTooltip:AddLine(" ")
	local text = C_AddOns.IsAddOnLoaded(name)
		and L["EldoUI: %s is off while this addon is loaded, so the two never fight over the same frames."]
		or L["EldoUI: %s turns off while this addon is loaded, so the two never fight over the same frames."]
	AddonTooltip:AddLine(text:format(table.concat(modules, ", ")), E:TokenColor("warn", true))
	AddonTooltip:Show()
end

local function RefreshAddonRows()
	local box = AddonList and AddonList.ScrollBox
	if Usable(box) and box.ForEachFrame then
		pcall(box.ForEachFrame, box, function(row)
			if rowTags[row] or ShowConflicts() then M:TagAddonRow(row) end
		end)
	end
end

local function SkinAddonListFrame(list)
	if skinned.addonList then return end
	skinned.addonList = true
	E:SkinPanel(list, { transparent = M.db.transparent })
	SkinButtons({ list.CancelButton, list.OkayButton, list.EnableAllButton, list.DisableAllButton })
	if Usable(list.ForceLoad) then E:SkinCheckBox(list.ForceLoad) end
	if Usable(list.Dropdown) then E:SkinDropdown(list.Dropdown) end
	if Usable(list.SearchBox) then E:SkinEditBox(list.SearchBox, { left = 2 }) end
	if Usable(list.ScrollBar) then E:SkinScrollBar(list.ScrollBar) end
	if Usable(list.ScrollBox) then
		E:HookScrollBoxRows(list.ScrollBox, function(row) E:SkinRow(row) end)
	end
end

local function ApplyAddonList()
	local list = AddonList
	if not Usable(list) then return end
	if Allowed("addon-list") then
		Once("addonList", function()
			if type(AddonList_InitAddon) == "function" then
				hooksecurefunc("AddonList_InitAddon", function(entry) M:TagAddonRow(entry) end)
			end
			if type(AddonTooltip_Update) == "function" then
				hooksecurefunc("AddonTooltip_Update", function(owner) M:AddonTooltipLine(owner) end)
			end
			-- Plugins may register modules after login: read the conflicts again.
			list:HookScript("OnShow", function() conflictMap = nil end)
		end)
	end
	Want("addonList", list, SkinOn("addon-list", "skinAddonList"), SkinAddonListFrame, list)
	RefreshAddonRows()
end

---------------------------------------------------------------------------
-- Keybindings and Quick Keybind mode
---------------------------------------------------------------------------
local function SkinQuickKeybindFrame(frame)
	if skinned.quickKeybind then return end
	skinned.quickKeybind = true
	E:SkinPanel(frame, { transparent = M.db.transparent, strip = false, accentOffset = 30, close = false, insets = false, title = false })
	E:SkinAlphaZero(frame.BG)
	SkinHeader(frame.Header, frame, -10)
	SkinButtons({ frame.DefaultsButton, frame.CancelButton, frame.OkayButton })
	if Usable(frame.UseCharacterBindingsButton) then E:SkinCheckBox(frame.UseCharacterBindingsButton) end
end

-- A strip under Blizzard's window with EldoUI's key sets.
local function PresetRow()
	if own.presets then return own.presets end
	local row = CreateFrame("Frame", "EldoUI_QuickKeybindPresets", UIParent)
	row:SetFrameStrata("DIALOG")
	row:SetHeight(34)
	E:SetPanelTemplate(row, M.db.transparent)
	row.label = E:CreateText(row, E.tokens.size.label, "LEFT")
	row.label:SetPoint("LEFT", 10, 0)
	row.label:SetText(L["%sEldoUI|r presets"]:format(AccentHex()))
	row.buttons = {}
	local previous = row.label
	for _, key in ipairs(E.keybindPresetOrder or {}) do
		local preset = E.keybindPresets[key]
		local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		button:SetHeight(22)
		button:SetText(preset.title and L[preset.title] or key)
		button:SetWidth(math.max(90, button:GetFontString():GetStringWidth() + 24))
		button:SetPoint("LEFT", previous, "RIGHT", 8, 0)
		button:SetScript("OnClick", function() E:OpenKeybindPreview(key) end)
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(preset.title and L[preset.title] or key)
			if preset.desc then GameTooltip:AddLine(L[preset.desc], E.UIKit.TEXT[1], E.UIKit.TEXT[2], E.UIKit.TEXT[3], true) end
			E.UIKit.TipText(GameTooltip, L["Opens a preview of every key first; nothing changes until you apply."])
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
		E:SkinButton(button, { size = 12 })
		row.buttons[#row.buttons + 1] = button
		previous = button
	end
	row:Hide()
	own.presets = row
	return row
end

local function UpdatePresetRow()
	local frame = QuickKeybindFrame
	local show = Allowed("keybindings", "improve") and M.db.quickKeybindPresets and E.OpenKeybindPreview
		and Usable(frame) and frame:IsShown()
	if not show then
		if own.presets then own.presets:Hide() end
		return
	end
	local row = PresetRow()
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -4)
	row:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -4)
	row:Show()
end

-- While Blizzard's Quick Keybind window is open, EldoUI's hover-and-press
-- overlay binds EldoUI's own buttons too. Blizzard's Okay saves and its
-- Cancel reloads the saved set, so both modes end in the same state.
local function OnQuickKeybindShow()
	UpdatePresetRow()
	if not (Allowed("keybindings", "replace") and M.db.quickKeybindEldo) then return end
	if InCombatLockdown() or not E.ToggleKeybindMode or E:IsKeybindMode() then return end
	quickKeybind.active = true
	E:ToggleKeybindMode(true)
	-- Blizzard's window has the Okay and Cancel buttons; ours is not needed.
	local banner = _G.EldoUI_KeybindBanner
	if banner then banner:Hide() end
	local overlay = _G.EldoUI_KeybindOverlay
	if overlay then
		quickKeybind.strata = overlay:GetFrameStrata()
		overlay:SetFrameStrata("FULLSCREEN_DIALOG")
	end
end

local function OnQuickKeybindHide()
	if own.presets then own.presets:Hide() end
	if not quickKeybind.active then return end
	quickKeybind.active = false
	local overlay = _G.EldoUI_KeybindOverlay
	if overlay and quickKeybind.strata then overlay:SetFrameStrata(quickKeybind.strata) end
	-- Okay already saved and Cancel already reloaded: keep what is current.
	if E:IsKeybindMode() then E:ToggleKeybindMode(false, true) end
end

local function ApplyKeybindings()
	local frame = QuickKeybindFrame
	if not Usable(frame) then return end
	if Allowed("keybindings") then
		Once("quickKeybind", function()
			frame:HookScript("OnShow", function() if M.active then OnQuickKeybindShow() end end)
			frame:HookScript("OnHide", OnQuickKeybindHide)
		end)
	end
	if Changeable(frame) then
		Want("quickKeybind", frame, SkinOn("keybindings", "skinQuickKeybind"), SkinQuickKeybindFrame, frame)
	end
	UpdatePresetRow()
end

---------------------------------------------------------------------------
-- Macros and click binding
---------------------------------------------------------------------------
local function SkinMacroFrame(frame)
	if skinned.macro then return end
	skinned.macro = true
	E:SkinPanel(frame, { transparent = M.db.transparent })
	E:SkinTabs({ _G.MacroFrameTab1, _G.MacroFrameTab2 }, { owner = frame, edge = "BOTTOM" })
	SkinButtons({ _G.MacroEditButton, _G.MacroCancelButton, _G.MacroSaveButton, _G.MacroDeleteButton,
		_G.MacroNewButton, _G.MacroExitButton })
	E:SkinInset(_G.MacroFrameTextBackground)
	local scroll = _G.MacroFrameScrollFrame
	if Usable(scroll) and Usable(scroll.ScrollBar) then E:SkinScrollBar(scroll.ScrollBar) end
	local selector = frame.MacroSelector
	if Usable(selector) and Usable(selector.ScrollBar) then E:SkinScrollBar(selector.ScrollBar) end
end

local function SkinClickBindingFrame(frame)
	if skinned.clickBinding then return end
	skinned.clickBinding = true
	E:SkinPanel(frame, { transparent = M.db.transparent })
	E:SkinInset(frame.ScrollBoxBackground)
	SkinButtons({ frame.SaveButton, frame.AddBindingButton, frame.ResetButton })
	if Usable(frame.EnableMouseoverCastCheckbox) then E:SkinCheckBox(frame.EnableMouseoverCastCheckbox) end
	if Usable(frame.MouseoverCastKeyDropdown) then E:SkinDropdown(frame.MouseoverCastKeyDropdown) end
	if Usable(frame.ScrollBar) then E:SkinScrollBar(frame.ScrollBar) end
	if Usable(frame.ScrollBox) then
		E:HookScrollBoxRows(frame.ScrollBox, function(row) E:SkinRow(row, { divider = true }) end)
	end
end

-- Under the click-binding window: whether EldoUI's Click-Cast Tips show
-- these bindings on party and raid tooltips (set in /eui > Click-Cast).
local function ClickCastLine()
	if own.clickCast then return own.clickCast end
	local line = CreateFrame("Frame", "EldoUI_ClickCastLine", ClickBindingFrame)
	line:SetHeight(30)
	E:SetPanelTemplate(line, M.db.transparent)
	line.text = E:CreateText(line, E.tokens.size.label, "LEFT")
	line.text:SetPoint("LEFT", 10, 0)
	line.text:SetPoint("RIGHT", -10, 0)
	own.clickCast = line
	return line
end

local function UpdateClickCastLine()
	local frame = ClickBindingFrame
	local module = E:GetModule("ClickCast")
	local show = Allowed("macros-click-binding", "improve") and M.db.clickCastLine and module and Usable(frame)
	if not show then
		if own.clickCast then own.clickCast:Hide() end
		return
	end
	local line = ClickCastLine()
	line:ClearAllPoints()
	line:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -4)
	line:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -4)
	-- Active, not just switched on: another addon doing the same job holds it off.
	local state = module.active and E:TextHex("good") .. L["on"] .. "|r" or E:TextHex("secondary") .. L["off"] .. "|r"
	line.text:SetText(L["%s Click-Cast Tips (%s): these bindings in party and raid tooltips."]:format(AccentHex() .. "EldoUI|r", state))
	line:Show()
end

local function ApplyMacros()
	if Usable(MacroFrame) then
		Want("macro", MacroFrame, SkinOn("macros-click-binding", "skinMacro"), SkinMacroFrame, MacroFrame)
	end
	if Usable(ClickBindingFrame) then
		if Allowed("macros-click-binding") then
			Once("clickBinding", function()
				ClickBindingFrame:HookScript("OnShow", function() if M.active then UpdateClickCastLine() end end)
			end)
		end
		Want("clickBinding", ClickBindingFrame, SkinOn("macros-click-binding", "skinClickBinding"), SkinClickBindingFrame, ClickBindingFrame)
		UpdateClickCastLine()
	end
end

---------------------------------------------------------------------------
-- Pop-ups, color picker and stack split. Never confirms anything.
---------------------------------------------------------------------------
local function Popup(i)
	return _G["StaticPopup" .. i]
end

local function SkinPopupFrame(dialog)
	if skinned[dialog] then return end
	skinned[dialog] = true
	-- strip = false: the alert icon and progress bar are textures of the
	-- dialog itself and must stay.
	local bd = E:SkinPanel(dialog, { transparent = M.db.transparent, strip = false, accentLine = false, insets = false, title = false })
	-- The pop-up sizes itself to its shown children (ResizeLayoutFrame);
	-- our backdrop (our own frame) must not take part in that.
	if bd then bd.ignoreInLayout = true end
	E:SkinAlphaZero(dialog.BG, dialog.Border)
	local container = dialog.ButtonContainer
	if container then
		SkinButtons({ container.Button1, container.Button2, container.Button3, container.Button4 })
		E:SkinAlphaZero(container.Separator)
	end
	SkinButtons({ dialog.ExtraButton })
	if Usable(dialog.EditBox) then E:SkinEditBox(dialog.EditBox, { left = 2, right = 2, top = 2, bottom = 2 }) end
	if Usable(dialog.Dropdown) then E:SkinDropdown(dialog.Dropdown) end
	if dialog.Text and dialog.Text.SetTextColor then dialog.Text:SetTextColor(unpack(E.media.text.body)) end
end

local function SkinPopup(dialog)
	if Usable(dialog) then Want("popups", dialog, SkinOn("dialogs", "skinPopups"), SkinPopupFrame, dialog) end
end

local function SkinColorPickerFrame(frame)
	if skinned.colorPicker then return end
	skinned.colorPicker = true
	E:SkinPanel(frame, { transparent = M.db.transparent, strip = false, accentOffset = 30, close = false, insets = false, title = false })
	E:SkinAlphaZero(frame.Border)
	SkinHeader(frame.Header, frame, -10)
	local footer = frame.Footer
	if footer then SkinButtons({ footer.OkayButton, footer.CancelButton }) end
	local content = frame.Content
	if content and Usable(content.HexBox) then E:SkinEditBox(content.HexBox, { left = 2 }) end
end

local function SkinColorPicker()
	local frame = ColorPickerFrame
	if Usable(frame) then Want("colorPicker", frame, SkinOn("dialogs", "skinColorPicker"), SkinColorPickerFrame, frame) end
end

local function SkinStackSplitFrame(frame)
	if skinned.stackSplit then return end
	skinned.stackSplit = true
	E:SkinAlphaZero(frame.SingleItemSplitBackground, frame.MultiItemSplitBackground)
	E:SkinPanel(frame, { transparent = M.db.transparent, strip = false, accentLine = false, close = false, insets = false, title = false })
	SkinButtons({ frame.OkayButton, frame.CancelButton })
	if frame.StackSplitText and frame.StackSplitText.SetFont then E:SetFont(frame.StackSplitText, E.tokens.size.cardTitle) end
end

local function SkinStackSplit()
	local frame = StackSplitFrame
	if Usable(frame) then Want("stackSplit", frame, SkinOn("dialogs", "skinStackSplit"), SkinStackSplitFrame, frame) end
end

-- Keep the native release decision intact and cover its place until Shift.
local releaseGuards = setmetatable({}, { __mode = "k" })
local releaseButtons = setmetatable({}, { __mode = "k" })
local releaseEvents = {}
local releaseListening = false
local releaseEventNames = {
	"MODIFIER_STATE_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
}
local RefreshReleaseGuards
local refreshingRelease

local function ReleaseObject(frame)
	return not E.Secret(frame) and type(frame) == "table" and (not canaccesstable or canaccesstable(frame))
end

local function ReleaseFrame(frame)
	return ReleaseObject(frame) and Usable(frame) and not E.FrameCheck(frame, "IsProtected")
end

local function ReleaseEnabled()
	return Allowed("dialogs", "improve") and M.db.holdShiftRelease
end

local function ReleaseAllowed(dialog)
	if not (ReleaseEnabled()
		and E.PlainCall(dialog.IsShown, dialog) == true) then return false end
	local inside, kind = E.PlainCallAll(IsInInstance)
	if inside ~= true or (kind ~= "party" and kind ~= "raid") then return false end
	local rules = C_GameRules
	return rules and E.PlainCall(rules.IsHardcoreActive) == false
end

-- A known replacement retires the old lease. An unreadable owner keeps it.
local function ReleaseButton(dialog)
	if not ReleaseObject(dialog) or E.FrameCheck(dialog, "IsForbidden") then return end
	local which = dialog.which
	if E.Secret(which) then return end
	if which ~= "DEATH" then return false end
	local button = E.PlainCall(dialog.GetButton1, dialog)
	if not ReleaseObject(button) then return end
	local parent
	if not E.FrameCheck(button, "IsForbidden") then
		parent = E.PlainCall(button.GetParent, button)
	end
	return button, ReleaseObject(parent) and parent or nil
end

local function SameReleaseButton(guard, button, parent)
	if button == nil then return end
	if button ~= guard.button then return false end
	if parent ~= nil then return parent == guard.parent end
end

local function OwnsReleaseButton(guard)
	return SameReleaseButton(guard, ReleaseButton(guard.dialog))
end

local function CanChangeRelease(guard)
	return ReleaseFrame(guard.dialog) and ReleaseFrame(guard.button) and ReleaseFrame(guard.parent)
end

local function ForgetReleaseCover(guard)
	if guard.placeholder then guard.placeholder:Hide() end
	if guard.hint then guard.hint:Hide() end
end

local function SetReleaseShown(guard, shown)
	if OwnsReleaseButton(guard) ~= true or not CanChangeRelease(guard) then return false end
	local button = guard.button
	local current = E.PlainCall(button.IsShown, button)
	if type(current) ~= "boolean" then return false end
	if current == shown then return true end
	if not shown then guard.ownedHidden = true end
	guard.writing = true
	pcall(button.SetShown, button, shown)
	guard.writing = nil
	return OwnsReleaseButton(guard) == true and E.PlainCall(button.IsShown, button) == shown
end

local function ClearReleaseGuard(guard, owner)
	if guard.writing then return end
	ForgetReleaseCover(guard)
	guard.active = nil
	if guard.ownedHidden and owner ~= false then
		if owner ~= true then return end
		if guard.nativeVisibilityUnknown then
			if not CanChangeRelease(guard) or E.PlainCall(guard.button.IsShown, guard.button) ~= true then return end
		elseif not SetReleaseShown(guard, true) then
			return
		end
	end
	guard.ownedHidden, guard.nativeVisibilityUnknown = nil, nil
end

local function ReleasePlaceholder(guard)
	local button, parent, dialog = guard.button, guard.parent, guard.dialog
	if E.FrameCheck(button, "IsAnchoringRestricted") or E.FrameCheck(parent, "IsAnchoringRestricted")
		or E.FrameCheck(dialog, "IsAnchoringRestricted") then return end
	local placeholder = guard.placeholder
	if not placeholder then
		placeholder = CreateFrame("Button", nil, parent)
		placeholder:Hide()
		E:SkinButton(placeholder)
		placeholder:Disable()
		local text = E:CreateText(placeholder, E.tokens.size.body, "CENTER")
		text:SetAllPoints()
		guard.placeholder, guard.text = placeholder, text
		local hint = CreateFrame("Frame", nil, dialog)
		hint:SetPoint("TOPLEFT", dialog, "BOTTOMLEFT", 0, -2)
		hint:SetPoint("TOPRIGHT", dialog, "BOTTOMRIGHT", 0, -2)
		hint.ignoreInLayout = true
		E:SetPanelTemplate(hint)
		hint:Hide()
		guard.hint = hint
		guard.hintText = E:CreateText(hint, E.tokens.size.small, "CENTER")
		guard.hintText:SetPoint("TOPLEFT", 8, -6)
		guard.hintText:SetPoint("TOPRIGHT", -8, -6)
		guard.hintText:SetWordWrap(true)
	end
	if guard.anchor ~= button or guard.anchorParent ~= parent then
		if placeholder:GetParent() ~= parent then placeholder:SetParent(parent) end
		placeholder:SetAllPoints(button)
		guard.anchor, guard.anchorParent = button, parent
	end
	return placeholder
end

local function ApplyReleaseGuard(guard)
	local button = guard.button
	local shown = E.PlainCall(button.IsShown, button)
	if guard.nativeVisibilityUnknown then
		if shown ~= true then ForgetReleaseCover(guard) return end
		guard.ownedHidden, guard.nativeVisibilityUnknown = nil, nil
	end
	local held = E.PlainCall(IsShiftKeyDown)
	local enabled = E.PlainCall(button.IsEnabled, button)
	local text = E.PlainCall(button.GetText, button)
	if type(held) ~= "boolean" or type(shown) ~= "boolean"
		or type(enabled) ~= "boolean" or type(text) ~= "string" then
		ClearReleaseGuard(guard, OwnsReleaseButton(guard))
		return
	end
	if held or not (shown or guard.ownedHidden) then
		ForgetReleaseCover(guard)
		if guard.ownedHidden then
			if SetReleaseShown(guard, true) then guard.ownedHidden = nil
			else ClearReleaseGuard(guard, OwnsReleaseButton(guard)) end
		end
		return
	end
	local placeholder = ReleasePlaceholder(guard)
	if not placeholder or not SetReleaseShown(guard, false) then
		ClearReleaseGuard(guard, OwnsReleaseButton(guard))
		return
	end
	if guard.text:GetText() ~= text then guard.text:SetText(text) end
	local hint = L["Hold Shift to release your spirit."]
	if guard.hintText:GetText() ~= hint then guard.hintText:SetText(hint) end
	local height = guard.hintText:GetStringHeight() + 12
	if guard.hint:GetHeight() ~= height then guard.hint:SetHeight(height) end
	if not placeholder:IsShown() then placeholder:Show() end
	if not guard.hint:IsShown() then guard.hint:Show() end
end

local function WatchReleaseButton(guard, button, parent)
	if guard.button and releaseButtons[guard.button] == guard then releaseButtons[guard.button] = false end
	local watched = releaseButtons[button] ~= nil
	guard.button, guard.parent = button, parent
	releaseButtons[button] = guard
	if watched then return end

	local function Current()
		local current = releaseButtons[button]
		if current and current.button == button and not current.writing and (current.active or current.ownedHidden) then
			return current
		end
	end
	local function Changed(requested)
		local current = Current()
		if not current then return end
		local owner = OwnsReleaseButton(current)
		if owner ~= false then
			local shown = owner and E.PlainCall(button.IsShown, button)
			if requested ~= nil and type(shown) == "boolean" and requested == shown then
				-- The native owner has superseded the visibility lease.
				current.ownedHidden, current.nativeVisibilityUnknown = nil, nil
			elseif (type(shown) ~= "boolean" or requested == nil) and current.ownedHidden then
				-- An unreadable native write may be newer than our hide.
				current.nativeVisibilityUnknown = true
			end
		end
		RefreshReleaseGuards(current.dialog, current)
	end
	hooksecurefunc(button, "Show", function() Changed(true) end)
	hooksecurefunc(button, "Hide", function() Changed(false) end)
	hooksecurefunc(button, "SetShown", function(_, shown)
		shown = E.Plain(shown)
		if type(shown) ~= "boolean" then shown = nil end
		Changed(shown)
	end)
	hooksecurefunc(button, "SetText", function()
		local current = Current()
		if current then RefreshReleaseGuards(current.dialog, current) end
	end)
end

local function UpdateReleaseGuard(dialog, guard)
	if guard and guard.writing then return end
	local button, parent = ReleaseButton(dialog)
	local allowed = button and ReleaseFrame(dialog) and ReleaseFrame(button) and ReleaseFrame(parent) and ReleaseAllowed(dialog)
	if guard and guard.button then
		local owner = SameReleaseButton(guard, button, parent)
		if owner ~= true or not allowed then
			ClearReleaseGuard(guard, owner)
			if owner ~= false then return end
		end
	end
	if not allowed then return end
	if not guard then
		guard = { dialog = dialog }
		releaseGuards[dialog] = guard
	end
	if guard.button ~= button or guard.parent ~= parent then WatchReleaseButton(guard, button, parent) end
	guard.active = true
	ApplyReleaseGuard(guard)
end

local function SyncReleaseListeners()
	local needed = false
	for _, guard in pairs(releaseGuards) do
		if guard.active or guard.ownedHidden then needed = true break end
	end
	if needed == releaseListening then return end
	releaseListening = needed
	for _, event in ipairs(releaseEventNames) do
		if needed then E:RegisterEvent(event, function() RefreshReleaseGuards() end, releaseEvents)
		else E:UnregisterEvent(event, releaseEvents) end
	end
end

local function RefreshAllReleaseGuards()
	for dialog, guard in pairs(releaseGuards) do UpdateReleaseGuard(dialog, guard) end
	if ReleaseEnabled() then
		for i = 1, POPUP_COUNT do
			local dialog = Popup(i)
			if ReleaseObject(dialog) and not releaseGuards[dialog] then UpdateReleaseGuard(dialog) end
		end
	end
end

RefreshReleaseGuards = function(dialog, guard)
	if refreshingRelease then return end
	refreshingRelease = true
	if guard then Try(UpdateReleaseGuard, dialog, guard)
	else Try(RefreshAllReleaseGuards) end
	refreshingRelease = nil
	SyncReleaseListeners()
end

function M:ClearReleaseGuards()
	for _, guard in pairs(releaseGuards) do ClearReleaseGuard(guard, OwnsReleaseButton(guard)) end
	SyncReleaseListeners()
end

-- Type DELETE into the delete-item pop-up. The Yes button stays yours.
local function FillDelete(dialog)
	if not (Allowed("dialogs", "improve") and M.db.fillDelete) then return end
	if not DELETE_DIALOGS[dialog.which] or not DELETE_ITEM_CONFIRM_STRING then return end
	local box = dialog.EditBox
	if Usable(box) and box:IsShown() then box:SetText(DELETE_ITEM_CONFIRM_STRING) end
end

-- The item on the cursor (the one the pop-up would delete) and, when it
-- came from the bags, its slot: the slot the game locked for the pick-up.
local function CursorItem()
	if type(GetCursorInfo) ~= "function" then return nil end
	local kind, itemID = GetCursorInfo()
	if kind ~= "item" or type(itemID) ~= "number" or (issecretvalue and issecretvalue(itemID)) then return nil end
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID == itemID and info.isLocked then return itemID, bag, slot end
		end
	end
	return itemID
end

-- Lines for the strip: which quest the item belongs to and whether you
-- are on it. Quests you are on and the quest it starts come first.
function M:DeleteContextLines(itemID, bag, slot)
	if not (E.ItemQuestContext and itemID) then return {} end
	local list, isQuestItem = E:ItemQuestContext(itemID, bag, slot)
	table.sort(list, function(a, b)
		if a.onQuest ~= b.onQuest then return a.onQuest end
		if a.starts ~= b.starts then return a.starts end
		return a.questID < b.questID
	end)
	local lines = {}
	for index = 1, math.min(#list, 2) do
		local quest = list[index]
		local status
		if quest.onQuest then
			status = L["You are on this quest"]
		elseif quest.completed then
			status = L["Quest done"]
		else
			status = L["Not on this quest"]
		end
		local label = quest.starts and L["Starts the quest %s"] or L["Quest: %s"]
		lines[#lines + 1] = { text = label:format(quest.title), status = status, good = quest.onQuest }
	end
	if #lines == 0 and isQuestItem then
		lines[1] = { text = L["Quest item"], status = L["You are on this quest"], good = true }
	end
	if #list > 2 then
		lines[#lines + 1] = { text = L["Needed for %d more quests"]:format(#list - 2) }
	end
	return lines
end

local function ContextStrip(dialog)
	local strip = contextStrips[dialog]
	if strip then return strip end
	strip = CreateFrame("Frame", nil, dialog)
	strip:SetPoint("TOPLEFT", dialog, "BOTTOMLEFT", 0, -2)
	strip:SetPoint("TOPRIGHT", dialog, "BOTTOMRIGHT", 0, -2)
	E:SetPanelTemplate(strip)
	strip.rows = {}
	contextStrips[dialog] = strip
	return strip
end

-- Under a delete pop-up: the quest the item belongs to. Text only; the
-- pop-up and its buttons stay Blizzard's.
local function ShowDeleteContext(dialog)
	local strip = contextStrips[dialog]
	if strip then strip:Hide() end
	if not (Allowed("dialogs", "improve") and M.db.deleteContext and ANY_DELETE[dialog.which]) then return end
	local lines = M:DeleteContextLines(CursorItem())
	if #lines == 0 then return end
	strip = ContextStrip(dialog)
	local tokens = E.tokens
	local y = -8
	for index, line in ipairs(lines) do
		local row = strip.rows[index]
		if not row then
			row = { left = E:CreateText(strip, tokens.size.body, "LEFT"), right = E:CreateText(strip, tokens.size.label, "RIGHT") }
			strip.rows[index] = row
		end
		row.left:ClearAllPoints()
		row.right:ClearAllPoints()
		row.right:SetPoint("TOPRIGHT", -12, y)
		row.left:SetPoint("TOPLEFT", 12, y)
		row.left:SetPoint("TOPRIGHT", row.right, "TOPLEFT", -8, 0)
		row.left:SetText(line.text)
		local body = tokens.text.body
		row.left:SetTextColor(body[1], body[2], body[3])
		row.right:SetText(line.status or "")
		local color = line.good and tokens.text.good or tokens.text.secondary
		row.right:SetTextColor(color[1], color[2], color[3])
		row.left:Show()
		row.right:Show()
		y = y - tokens.height.row
	end
	for index = #lines + 1, #strip.rows do
		strip.rows[index].left:Hide()
		strip.rows[index].right:Hide()
	end
	strip:SetHeight(-y + 4)
	strip:Show()
end
M.ShowDeleteContext = ShowDeleteContext

-- The invisible frame the pop-up stack hangs from, on its own mover.
local function PopupAnchor()
	if own.popupAnchor then return own.popupAnchor end
	local anchor = CreateFrame("Frame", "EldoUI_PopupAnchor", UIParent)
	anchor:SetSize(320, 72)
	-- Movers created during a module's enable belong to it (export strings).
	local previous = E.currentModule
	E.currentModule = M
	E:CreateMover(anchor, "EldoUI_Popups", L["Pop-up Dialogs"], { "TOP", "UIParent", "TOP", 0, -150 })
	E.currentModule = previous
	own.popupAnchor = anchor
	return anchor
end

local function PopupMoveOn()
	return Allowed("dialogs", "move") and M.db.popupMover
end

-- Blizzard hangs the first free pop-up from the top of the screen and the
-- rest under it. Hang that first one from our mover instead. `opening` is
-- the dialog Blizzard is placing right before it shows.
local function PositionPopups(opening)
	local moveOn = PopupMoveOn()
	if moveOn then PopupAnchor() end
	for i = 1, POPUP_COUNT do
		local dialog = Popup(i)
		if Changeable(dialog) and (dialog:IsShown() or dialog == opening) then
			local point, relativeTo = dialog:GetPoint(1)
			if moveOn and point == "TOP" and relativeTo == UIParent then
				dialog:ClearAllPoints()
				dialog:SetPoint("TOP", own.popupAnchor, "TOP", 0, 0)
			elseif not moveOn and own.popupAnchor and relativeTo == own.popupAnchor then
				dialog:ClearAllPoints()
				dialog:SetPoint("TOP", UIParent, "TOP", 0, dialog.topOffset or -135)
			end
		end
	end
	if own.popupAnchor then own.popupAnchor:SetShown(moveOn and true or false) end
end

local function ScalePopup(dialog)
	if not Changeable(dialog) then return end
	if Allowed("dialogs", "move") then
		local scale = M.db.scale.popups or 1
		if math.abs(dialog:GetScale() - scale) > 0.001 then dialog:SetScale(scale) end
		popupScaled[dialog] = true
	elseif popupScaled[dialog] then
		popupScaled[dialog] = nil
		dialog:SetScale(1)
	end
end

local function OnPopupShow(dialog)
	if not M.active then RefreshReleaseGuards() return end
	SkinPopup(dialog)
	ScalePopup(dialog)
	FillDelete(dialog)
	ShowDeleteContext(dialog)
	RefreshReleaseGuards()
end

local function ApplyDialogs()
	if Allowed("dialogs") then
		Once("popups", function()
			for i = 1, POPUP_COUNT do
				local dialog = Popup(i)
				if Usable(dialog) then
					dialog:HookScript("OnShow", OnPopupShow)
					dialog:HookScript("OnHide", function(self)
						if contextStrips[self] then contextStrips[self]:Hide() end
						RefreshReleaseGuards()
					end)
				end
			end
			if type(StaticPopup_SetUpPosition) == "function" then
				hooksecurefunc("StaticPopup_SetUpPosition", function(dialog)
					if M.active then PositionPopups(dialog) end
				end)
			end
		end)
	end
	for i = 1, POPUP_COUNT do
		local dialog = Popup(i)
		if Usable(dialog) then
			if dialog:IsShown() or not SkinOn("dialogs", "skinPopups") then SkinPopup(dialog) end
			ScalePopup(dialog)
		end
	end
	PositionPopups()
	RefreshReleaseGuards()
	SkinColorPicker()
	SkinStackSplit()
end

local TEST_POPUP_TEXT = E.Key("EldoUI test pop-up. This is how pop-ups look and where they appear.")
StaticPopupDialogs.ELDOUI_SYSTEM_TEST = { -- luacheck: ignore 122 (popups are registered this way)
	text = TEST_POPUP_TEXT,
	button1 = E:GameText(OKAY, L["Okay"]),
	button2 = E:GameText(CANCEL, L["Cancel"]),
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

---------------------------------------------------------------------------
-- Shop, help and report windows: never skinned or moved; the Shop
-- micro button may be hidden.
---------------------------------------------------------------------------
local function HideStore()
	return Allowed("shop-help-report", "hide") and M.db.hideStoreButton
end

local function ApplyStore()
	local button = _G.StoreMicroButton
	if not Usable(button) then return end
	if HideStore() then
		Once("storeButton", function()
			button:HookScript("OnShow", function(self)
				if HideStore() and Changeable(self) then
					storeHidden = true
					self:Hide()
				end
			end)
		end)
		if button:IsShown() and Changeable(button) then
			storeHidden = true
			button:Hide()
		end
	elseif storeHidden and Changeable(button) then
		storeHidden = false
		button:Show()
	end
end

---------------------------------------------------------------------------
-- Everything at once: on enable, on every switch or setting change.
---------------------------------------------------------------------------
local function UpdateLook()
	for _, frame in ipairs({ GameMenuFrame, SettingsPanel, AddonList, MacroFrame, ClickBindingFrame,
		ColorPickerFrame, StackSplitFrame, QuickKeybindFrame, Popup(1), Popup(2), Popup(3), Popup(4) }) do
		if Usable(frame) and E:GetSkin(frame, "panel") then E:SetPanelTransparent(frame, M.db.transparent) end
	end
	for _, name in ipairs({ "presets", "clickCast" }) do
		if own[name] then E:SetPanelTemplate(own[name], M.db.transparent) end
	end
	if own.presets then own.presets.label:SetText(L["%sEldoUI|r presets"]:format(AccentHex())) end
end

function M:Apply()
	Try(ApplyGameMenu)
	Try(ApplySettings)
	Try(ApplyAddonList)
	Try(ApplyKeybindings)
	Try(ApplyMacros)
	Try(ApplyDialogs)
	Try(ApplyStore)
	Try(UpdateLook)
end

-- Put everything back: the recorded skins come off, the extras go.
function M:Restore()
	RefreshReleaseGuards()
	for _, key in pairs(RECORDS) do E:SkinRecordOff(key) end
	Try(UpdateMenuButton)
	Try(RefreshAddonRows)
	Try(UpdatePresetRow)
	Try(UpdateClickCastLine)
	Try(PositionPopups)
	for dialog in pairs(popupScaled) do Try(ScalePopup, dialog) end
	Try(ApplyStore)
	if quickKeybind.active then Try(OnQuickKeybindHide) end
end

function M:OnEnable()
	-- Load-on-demand windows: apply once they load (each step checks its switch).
	for _, addon in ipairs({ "Blizzard_MacroUI", "Blizzard_ClickBindingUI", "Blizzard_ColorPickerFrame", "Blizzard_AddOnList" }) do
		E:OnBlizzardAddOn(addon, function()
			if M.active then E:RunOutOfCombat(function() M:Apply() end) end
		end)
	end
	E:RunOutOfCombat(function()
		if M.active then M:Apply() end
	end)
end

function M:OnDisable()
	self:ClearReleaseGuards()
	E:RunOutOfCombat(function() M:Restore() end)
end

function M:OnProfileChanged()
	if not self.active then return end
	RefreshReleaseGuards()
	E:RunOutOfCombat(function()
		if M.active then M:Apply() end
	end)
end

---------------------------------------------------------------------------
-- Element switches (Core/Blizzard.lua)
---------------------------------------------------------------------------
local function Handler(id, install, legacy)
	E:RegisterBlizzardHandler(id, {
		owner = "SystemUI",
		apply = function() M:Apply() end,
		undo = function() M:Restore() end,
		-- The skins are recorded, so Skin off needs no reload.
		install = install,
		legacy = legacy,
	})
end

Handler("game-menu", { skin = true, improve = true })
Handler("settings-panel", { skin = true })
Handler("addon-list", { skin = true })
Handler("keybindings", { skin = true, replace = true, improve = true })
Handler("macros-click-binding", { skin = true, improve = true })
-- v0.5.0 filled in DELETE (Tweaks, since merged into Quality of Life,
-- which keeps the old setting): keep that helper on after the update,
-- without turning on the new pop-up skin for those players.
Handler("dialogs", { improve = true }, function()
	local modules = E.db and E.db.modules
	local old = modules and (modules.Tweaks or modules.QoL)
	return type(old) == "table" and old.enabled ~= false and old.autoDelete and true or false
end)
Handler("dialogs", { skin = true })
-- No installer default: hiding the Shop button is the player's choice.
Handler("shop-help-report")

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local function SwitchesButton()
	return { type = "execute", label = "Open Blizzard UI switches", width = 200,
		desc = "Open Blizzard UI > System and settings windows, where each window's 'Let EldoUI change this' switch lives.",
		func = function() E:ToggleConfig("blizzard") end }
end

local function ScaleOption(key, title, element)
	return { type = "range", percent = true, key = "scale." .. key, label = "%s scale", labelFill = title, min = 0.6, max = 1.5, step = 0.05,
		desc = "Size of the %s.", descFill = function() return E:InSentence(L[title]) end, disabled = E:BlizzardNeeds(element, "move") }
end

M.options = {
	{ type = "tab", label = "General" },
	{ type = "description", label = "Each window below changes only while its switch in Blizzard UI > System and settings windows is on." },
	SwitchesButton(),
	{ type = "header", label = "Look" },
	{ type = "toggle", key = "transparent", label = "See-through windows",
		desc = "Skinned windows let the game show through a little. How much: General > Panel opacity." },
	{ type = "header", label = "Moving windows" },
	{ type = "execute", label = "Open Windows", width = 200,
		desc = "Dragging, the mouse wheel scale and the resets of these windows are on the Move windows page, with every other Blizzard window.",
		func = function() E:ToggleConfig("windows") end },

	{ type = "tab", label = "Game menu" },
	{ type = "header", label = "Game menu (Esc)" },
	{ type = "toggle", key = "skinGameMenu", label = "EldoUI look",
		desc = L["Flat panel and flat buttons."], disabled = E:BlizzardNeeds("game-menu", "skin") },
	{ type = "toggle", key = "menuButton", label = "EldoUI button",
		desc = L["An EldoUI button in the game menu: click opens the EldoUI settings, right-click starts move mode. With Blizzard UI > Game menu (Esc) on, it sits right above AddOns."] },
	{ type = "header", label = "Settings window" },
	{ type = "toggle", key = "skinSettings", label = "EldoUI look",
		desc = L["Only the window frame, tabs, search box and buttons. The settings themselves stay Blizzard's, so nothing can break them."], disabled = E:BlizzardNeeds("settings-panel", "skin") },
	{ type = "description", label = "Esc > Options > AddOns > EldoUI is EldoUI's launcher page; it is always there." },

	{ type = "tab", label = "AddOn list" },
	{ type = "toggle", key = "skinAddonList", label = "EldoUI look",
		desc = L["Flat panel, rows, buttons and search box."], disabled = E:BlizzardNeeds("addon-list", "skin") },
	{ type = "toggle", key = "addonConflicts", label = "Mark addons that keep EldoUI modules off",
		desc = L["Rows of addons that an EldoUI module steps aside for get a tag, and their tooltip names the modules."], disabled = E:BlizzardNeeds("addon-list") },

	{ type = "tab", label = "Keybinds" },
	{ type = "toggle", key = "skinQuickKeybind", label = "EldoUI look for Quick Keybind",
		desc = L["Flat panel and buttons for Blizzard's Quick Keybind window."], disabled = E:BlizzardNeeds("keybindings", "skin") },
	{ type = "toggle", key = "quickKeybindEldo", label = "Bind EldoUI buttons in Quick Keybind",
		desc = L["While Blizzard's Quick Keybind window is open, hover an EldoUI button and press a key to bind it, as in EldoUI keybind mode. Blizzard's Okay keeps the keys, Cancel drops them."], disabled = E:BlizzardNeeds("keybindings", "replace") },
	{ type = "toggle", key = "quickKeybindPresets", label = "Key sets under Quick Keybind",
		desc = L["EldoUI's key sets in a strip under the window. Each opens a preview of every key before anything changes."], disabled = E:BlizzardNeeds("keybindings", "improve") },
	{ type = "execute", label = "EldoUI keybind mode", width = 200,
		desc = "Hover any EldoUI button and press a key. Out of combat only.",
		func = function() E:ToggleKeybindMode() end },

	{ type = "tab", label = "Macros" },
	{ type = "toggle", key = "skinMacro", label = "EldoUI look for the macro window",
		desc = L["Flat panel, tabs, buttons and text box."], disabled = E:BlizzardNeeds("macros-click-binding", "skin") },
	{ type = "toggle", key = "skinClickBinding", label = "EldoUI look for click casting",
		desc = L["Flat panel, rows and buttons for Blizzard's click-binding window."], disabled = E:BlizzardNeeds("macros-click-binding", "skin") },
	{ type = "toggle", key = "clickCastLine", label = "Click-Cast Tips line",
		desc = L["A line under the click-binding window: whether EldoUI shows these bindings on party and raid tooltips, with a button to its settings."], disabled = E:BlizzardNeeds("macros-click-binding", "improve") },
	{ type = "execute", label = "Click-Cast Tips settings", width = 200,
		desc = "Open the Click-Cast Tips module.",
		func = function() E:ToggleConfig("module:ClickCast") end },

	{ type = "tab", label = "Pop-ups" },
	{ type = "toggle", key = "skinPopups", label = "EldoUI look for pop-ups",
		desc = L["Flat panel, buttons and input box for Blizzard's pop-up dialogs."], disabled = E:BlizzardNeeds("dialogs", "skin") },
	{ type = "toggle", key = "skinColorPicker", label = "EldoUI look for the color picker",
		desc = L["Flat panel and buttons for the color picker."], disabled = E:BlizzardNeeds("dialogs", "skin") },
	{ type = "toggle", key = "skinStackSplit", label = "EldoUI look for stack splitting",
		desc = L["Flat panel and buttons for the split-stack box."], disabled = E:BlizzardNeeds("dialogs", "skin") },
	{ type = "toggle", acts = true, key = "fillDelete", label = "Fill in DELETE automatically",
		desc = L["Fills in the word on the 'delete this item' pop-up. You still press Yes yourself; EldoUI never confirms a pop-up. Off by default."], disabled = E:BlizzardNeeds("dialogs", "improve") },
	{ type = "toggle", key = "holdShiftRelease", label = "Hold Shift to release in instances",
		desc = "In dungeons and raids, hold Shift before pressing Release Spirit. The game must also allow release. Does not apply in Hardcore.",
		disabled = E:BlizzardNeeds("dialogs", "improve") },
	{ type = "toggle", key = "deleteContext", label = "Quest context when deleting",
		desc = L["Under the 'delete this item' pop-up: which quest the item belongs to or starts, and whether you are on it. Text only; you still decide."], disabled = E:BlizzardNeeds("dialogs", "improve") },
	{ type = "toggle", key = "popupMover", label = "Pop-ups follow their mover",
		desc = L["Pop-ups appear where the 'Pop-up dialogs' mover sits (/eui move)."], disabled = E:BlizzardNeeds("dialogs", "move") },
	ScaleOption("popups", E.Key("Pop-up"), "dialogs"),
	{ type = "execute", label = "Show a test pop-up", width = 200,
		desc = "A harmless pop-up to check the look and the position. It does nothing.",
		func = function()
			-- The text in the language shown now, not the one of the first load.
			StaticPopupDialogs.ELDOUI_SYSTEM_TEST.text = L[TEST_POPUP_TEXT] -- luacheck: ignore 122
			StaticPopup_Show("ELDOUI_SYSTEM_TEST")
		end },

	{ type = "tab", label = "Shop" },
	{ type = "description", label = "The shop, help, report and GM windows always keep the game's own look and place." },
	{ type = "toggle", key = "hideStoreButton", label = "Hide the Shop micro button",
		desc = L["Removes the Shop button from Blizzard's micro menu. The shop stays reachable from the game menu."], disabled = E:BlizzardNeeds("shop-help-report", "hide") },
}

---------------------------------------------------------------------------
-- Style presets
---------------------------------------------------------------------------
local ALL_SKINS = { skinGameMenu = true, skinSettings = true, skinAddonList = true, skinQuickKeybind = true,
	skinMacro = true, skinClickBinding = true, skinPopups = true, skinColorPicker = true, skinStackSplit = true }
local NO_SKINS = {}
for key in pairs(ALL_SKINS) do NO_SKINS[key] = false end

local function Style(base, extra)
	local settings = {}
	for key, value in pairs(base) do settings[key] = value end
	for key, value in pairs(extra or {}) do settings[key] = value end
	return settings
end

local function Scales(value)
	return { popups = value }
end

E:RegisterStyles("SystemUI", {
	{ key = "EldoUI", title = "EldoUI", desc = "Every window in the EldoUI look, solid panels, all helpers on, normal size.",
		settings = Style(ALL_SKINS, { transparent = false, menuButton = true, addonConflicts = true, quickKeybindEldo = true,
			quickKeybindPresets = true, clickCastLine = true, popupMover = true, scale = Scales(1) }) },
	{ key = "Glass", title = "Glass", desc = "The EldoUI look with see-through panels.",
		settings = Style(ALL_SKINS, { transparent = true, menuButton = true, addonConflicts = true, scale = Scales(1) }) },
	{ key = "Compact", title = "Compact", desc = "EldoUI look, pop-ups a little smaller for small screens. Window sizes are on the Move windows page.",
		settings = Style(ALL_SKINS, { transparent = false, scale = Scales(0.9) }) },
	{ key = "Large", title = "Large", desc = "EldoUI look, pop-ups a little bigger for high resolutions and easy reading. Window sizes are on the Move windows page.",
		settings = Style(ALL_SKINS, { transparent = false, scale = Scales(1.15) }) },
	{ key = "BlizzardPlus", title = "Blizzard plus", desc = "Blizzard's own look, with EldoUI's helpers: menu button, conflict tags, presets and DELETE.",
		settings = Style(NO_SKINS, { menuButton = true, addonConflicts = true, quickKeybindEldo = true,
			quickKeybindPresets = true, clickCastLine = true, scale = Scales(1) }) },
	{ key = "Minimal", title = "Minimal", desc = "EldoUI look only: no extra buttons, strips or tags.",
		settings = Style(ALL_SKINS, { menuButton = false, addonConflicts = false, quickKeybindPresets = false,
			clickCastLine = false, scale = Scales(1) }) },
})

-- Filling in DELETE acts for the player: listed for the setup's Convenience
-- step and the Conveniences page (Core/Conveniences.lua), off until ticked.
E:RegisterConvenience({ id = "fillDelete", module = "SystemUI", setting = "fillDelete", order = 180,
	label = "Fill in DELETE automatically",
	desc = "Acts for you: the word the game asks for before you destroy a rare item or a quest item is typed in. You still press Yes yourself.",
	blocked = function() return E:BlizzardNeedsReason("dialogs", "improve") end })
