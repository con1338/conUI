-- EldoUI keybind mode: hover any EldoUI button and press a key (or a mouse
-- button or the wheel) to bind it. Escape clears the button's keys. Save
-- writes them to the current binding set; Discard reloads the saved set.
-- Bindings can't change in combat, so the mode closes when combat starts.
local _, E = ...
local L = E.L

local buttons = {}   -- button -> binding command (e.g. "ACTIONBUTTON1")
local active = false
local changed = false
local current        -- the button under the mouse
local returnToConfig -- keybind mode hid the options window; it comes back after

-- Keys that only modify another key are never bound on their own.
local IGNORED = {
	LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
	LALT = true, RALT = true, LMETA = true, RMETA = true, UNKNOWN = true,
}
-- Left and right click stay clicks.
local MOUSE = {
	MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5",
}

local function Chord(key)
	if CreateKeyChordStringUsingMetaKeyState then
		return CreateKeyChordStringUsingMetaKeyState(key)
	end
	local prefix = ""
	if IsAltKeyDown() then prefix = prefix .. "ALT-" end
	if IsControlKeyDown() then prefix = prefix .. "CTRL-" end
	if IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
	return prefix .. key
end

local function KeysText(command)
	local keys = { GetBindingKey(command) }
	if #keys == 0 then return E:TextHex("secondary") .. L["Not bound"] .. "|r" end
	for i, key in ipairs(keys) do keys[i] = GetBindingText(key, "KEY_") end
	return table.concat(keys, ", ")
end

---------------------------------------------------------------------------
-- The overlay that sits on the hovered button and catches keys
---------------------------------------------------------------------------
local bind = CreateFrame("Button", "EldoUI_KeybindOverlay", UIParent)
bind:SetFrameStrata("DIALOG")
bind:EnableMouse(true)
bind:EnableKeyboard(true)
bind:EnableMouseWheel(true)
bind:RegisterForClicks("AnyDown")
bind:Hide()
bind.texture = bind:CreateTexture(nil, "OVERLAY")
bind.texture:SetAllPoints()
-- The hovered button is tinted with the accent (recolored with the theme).
local function TintOverlay()
	if E.AccentTexture and E.media and E.media.accentColor then
		E:AccentTexture(bind.texture, 0.3)
	else
		bind.texture:SetColorTexture(1, 1, 1, 0.25)
	end
end
TintOverlay()

-- The readable name of a binding command, e.g. "Action Bar 2 Button 5".
local function CommandName(command)
	local name = GetBindingName and GetBindingName(command)
	if type(name) == "string" and name ~= "" and name ~= command then return name end
	return command
end

local function ShowTooltip()
	if not current then return end
	GameTooltip:SetOwner(bind, "ANCHOR_TOP")
	GameTooltip:AddLine(CommandName(buttons[current]), E:TokenColor("accent"))
	GameTooltip:AddLine(KeysText(buttons[current]), E:TokenColor("body"))
	GameTooltip:AddLine(L["Press a key to bind it. Escape clears."], E:TokenColor("secondary"))
	GameTooltip:Show()
end

local banner
-- The last key set or cleared, on the banner (never in chat).
local function ShowStatus(text)
	if not (banner and banner.status) then return end
	banner.status:SetText(text or "")
end

-- A module's own hint on the open banner ("hover the quest item button").
function E:KeybindStatus(text)
	ShowStatus(text)
end

local function Bind(key)
	if not current or InCombatLockdown() then return end
	local command = buttons[current]
	if key == "ESCAPE" then
		for _, old in ipairs({ GetBindingKey(command) }) do SetBinding(old) end
		ShowStatus(L["Cleared %s."]:format(CommandName(command)))
	else
		SetBinding(key, command)
		ShowStatus(L["%s bound to %s."]:format(E:Highlight(GetBindingText(key, "KEY_") or key), CommandName(command)))
	end
	changed = true
	ShowTooltip()
end

bind:SetScript("OnKeyDown", function(self, key)
	if IGNORED[key] then return end
	if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
	Bind(key == "ESCAPE" and key or Chord(key))
end)
bind:SetScript("OnClick", function(_, mouseButton)
	local key = MOUSE[mouseButton]
	if key then Bind(Chord(key)) end
end)
bind:SetScript("OnMouseWheel", function(_, delta)
	Bind(Chord(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"))
end)
bind:SetScript("OnLeave", function(self)
	if not self:IsMouseOver() then
		current = nil
		self:Hide()
		GameTooltip:Hide()
	end
end)

local function OnButtonEnter(button)
	if not active or not buttons[button] or not button:IsVisible() then return end
	if InCombatLockdown() then return end
	current = button
	bind:ClearAllPoints()
	bind:SetAllPoints(button)
	bind:Show()
	ShowTooltip()
end

---------------------------------------------------------------------------
-- Banner with Save and Discard
---------------------------------------------------------------------------
local characterSet   -- save to the character's own binding set
-- The game's binding sets (account-wide 1, character 2).
local BINDING_SET = Enum and Enum.BindingSet
local ACCOUNT_SET = BINDING_SET and BINDING_SET.Account or 1
local CHARACTER_SET = BINDING_SET and BINDING_SET.Character or 2

local function BindingSet()
	if characterSet then return CHARACTER_SET end
	if ACCOUNT_SET then return ACCOUNT_SET end
	return GetCurrentBindingSet()
end

local function CreateBanner()
	banner = CreateFrame("Frame", "EldoUI_KeybindBanner", UIParent)
	banner:SetSize(460, 136)
	banner:SetPoint("TOP", 0, -120)
	banner:SetFrameStrata("DIALOG")
	E:SetPanelTemplate(banner)
	local title = E:CreateText(banner, E.tokens.size.display)
	title:SetPoint("TOP", 0, -10)
	banner.title = title
	local hint = E:CreateText(banner, E.tokens.size.body)
	hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
	hint:SetText(L["Hover a button and press a key, mouse button or wheel. Escape clears."])
	banner.hint = hint
	local status = E:CreateText(banner, E.tokens.size.label)
	status:SetPoint("TOP", hint, "BOTTOM", 0, -6)
	status:SetWidth(460 - 32)
	status:SetWordWrap(false)
	banner.status = status
	-- The kit's footer buttons (height.buttonLarge), as wide as their label.
	local function AddButton(text, x, onClick)
		local b = E.UIKit.Button(banner, { text = text, large = true, minWidth = 120, onClick = onClick })
		b:SetPoint("BOTTOM", x, 10)
		return b
	end
	AddButton(L["Save"], -66, function() E:ToggleKeybindMode(false, true) end)
	AddButton(L["Discard"], 66, function() E:ToggleKeybindMode(false, false) end)

	-- Character specific keys, like the game's own Key Bindings window.
	local check = CreateFrame("CheckButton", nil, banner, "UICheckButtonTemplate")
	check:SetSize(22, 22)
	check:SetPoint("BOTTOMLEFT", banner, "BOTTOM", -90, 38)
	E:SkinCheckBox(check)
	local label = E:CreateText(check, E.tokens.size.label)
	label:SetPoint("LEFT", check, "RIGHT", 2, 0)
	label:SetText(L["Character specific keybinds"])
	banner.label = label
	check:SetScript("OnClick", function(self) characterSet = self:GetChecked() and true or false end)
	check:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(L["Character specific keybinds"], E:TokenColor("accent"))
		GameTooltip:AddLine(L["Save these keys for this character only, like the game's Key Bindings window."], E:TokenColor("body", true))
		GameTooltip:Show()
	end)
	check:SetScript("OnLeave", function() GameTooltip:Hide() end)
	banner.check = check

	-- Escape closes the mode (and saves) when no button is hovered; every
	-- other key passes through to the game.
	banner:EnableKeyboard(true)
	banner:SetScript("OnKeyDown", function(self, key)
		if InCombatLockdown() then return end
		if key == "ESCAPE" and not bind:IsShown() then
			self:SetPropagateKeyboardInput(false)
			E:ToggleKeybindMode(false, true)
		else
			self:SetPropagateKeyboardInput(true)
		end
	end)
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------

-- Make a button bindable in keybind mode. `command` is a binding name from
-- Bindings.xml, such as "ACTIONBUTTON1" or "MULTIACTIONBAR1BUTTON5".
-- The OnEnter hook stays (hooks can't be removed) but does nothing once the
-- button is unregistered.
local hooked = setmetatable({}, { __mode = "k" })
function E:RegisterKeybindButton(button, command)
	if not button or not command then return end
	if not hooked[button] then
		hooked[button] = true
		button:HookScript("OnEnter", OnButtonEnter)
	end
	buttons[button] = command
end

-- Stop offering a button in keybind mode (for example a Blizzard button
-- EldoUI handed back).
function E:UnregisterKeybindButton(button)
	if not button then return end
	buttons[button] = nil
	if current == button then
		current = nil
		bind:Hide()
		GameTooltip:Hide()
	end
end

-- The binding command a button is registered with, or nil.
function E:GetKeybindCommand(button)
	return buttons[button]
end

function E:IsKeybindMode()
	return active
end

-- Theme font, outline and accent, read each time the banner opens so a
-- theme change since the last time shows.
local function StyleBanner()
	local title = banner.title
	E:SetHeaderFont(title, 18)
	title:SetText(L["%sEldoUI|r Keybind mode"]:format(E.color))
	E:SetFont(banner.hint, E.tokens.size.body)
	E:SetFont(banner.label, E.tokens.size.label)
	E:SetFont(banner.status, E.tokens.size.label)
	banner.status:SetTextColor(E:TokenColor("secondary"))
	TintOverlay()
end

-- What happened when the mode closed: a short notice in the options window
-- when it is open, else an alert. Never a chat line.
local function Notice(text, warn)
	if not text then return end
	local config = _G.EldoUIConfig
	if config and config:IsShown() and E.ConfigNotice then
		E:ConfigNotice(text, warn)
	else
		E:PushAlert({ key = "keybind-mode", title = L["Keybind mode"], text = text, options = { page = "keybinds" } })
	end
end

-- state: true/false/nil (toggle). save: keep the changes when leaving.
function E:ToggleKeybindMode(state, save)
	if state == nil then state = not active end
	if state and InCombatLockdown() then
		Notice(L["Keybind mode can't open in combat."], true)
		return
	end
	if state == active then return end
	active = state
	if state then
		changed = false
		if not banner then CreateBanner() end
		characterSet = GetCurrentBindingSet() == CHARACTER_SET
		banner.check:SetChecked(characterSet)
		ShowStatus(nil)
		StyleBanner()
		banner:Show()
		if self:IsMoveMode() then self:ToggleMoveMode(false) end
		-- The options window steps aside the way move mode does: no reload
		-- question on the way in, and it comes back afterwards.
		if self.CloseConfigForMoveMode then
			returnToConfig = self:CloseConfigForMoveMode() and true or nil
		elseif _G.EldoUIConfig then
			_G.EldoUIConfig:Hide()
		end
	else
		current = nil
		bind:Hide()
		GameTooltip:Hide()
		if banner then banner:Hide() end
		-- Leaving without a change needs no notice: the banner closing says it.
		local text
		if changed then
			if save == false then
				LoadBindings(GetCurrentBindingSet())
				text = L["Keybind changes discarded."]
			else
				SaveBindings(BindingSet())
				text = characterSet and L["Keybinds saved for this character."] or L["Keybinds saved."]
			end
		elseif save ~= false and characterSet ~= (GetCurrentBindingSet() == CHARACTER_SET) then
			-- Only the set changed: save the current keys into the chosen set.
			SaveBindings(BindingSet())
			text = characterSet and L["Keybinds are now character specific."] or L["Keybinds are now shared by your account."]
		end
		local back = returnToConfig
		returnToConfig = nil
		if back and not InCombatLockdown() and self.ReopenConfigAfterMoveMode then self:ReopenConfigAfterMoveMode() end
		Notice(text)
	end
end

E:RegisterEvent("PLAYER_REGEN_DISABLED", function()
	-- Combat starts: keys are saved and the options window stays closed.
	returnToConfig = nil
	if active then E:ToggleKeybindMode(false, true) end
end, buttons)
