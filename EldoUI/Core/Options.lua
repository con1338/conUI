-- EldoUI entry in the game's Settings window (Esc > Options > AddOns).
-- Logo, version, the active layout and profile, and how to open EldoUI's
-- own config window (/eui only), plus move, keybind and installer buttons.
local _, E = ...
local L = E.L

local panel

-- EldoUI's own look inside Blizzard's panel: theme
-- fonts and the skinned kit buttons, never the game's fonts.
-- A footer-height kit button as wide as its label (at least minWidth), so
-- Large text never clips it.
local function Button(parent, text, minWidth, onClick)
	return E.WindowKit.Button(parent, { text = text, minWidth = minWidth, onClick = onClick, large = true })
end

-- Close the Settings window the way its own close button does, then run
-- the action on the next frame, outside Blizzard's click path. Never
-- HideUIPanel from addon code (a known taint source).
local function CloseSettingsThen(fn)
	local settings = _G.SettingsPanel
	if settings and settings:IsShown() then
		if type(settings.Close) == "function" then
			settings:Close(true)
		else
			settings:Hide()
		end
	end
	C_Timer.After(0, fn)
end
E.CloseSettingsThen = CloseSettingsThen

-- The Settings panel page.
function E:SettingsPanel()
	return panel
end

function E:InitializeOptions()
	panel = CreateFrame("Frame")
	panel.name = (E.brand or "EldoUI") -- no-L: addon name in the Settings list

	local logo = panel:CreateTexture(nil, "ARTWORK")
	logo:SetTexture(E.media.logo)
	logo:SetSize(256, 64)
	logo:SetPoint("TOP", 0, -24)

	local version = E:CreateText(panel, E.tokens.size.small, "CENTER")
	version:SetTextColor(unpack(E.tokens.text.secondary))
	version:SetPoint("TOP", logo, "BOTTOM", 0, -2)
	version:SetText("v" .. E.version)

	-- The options open only from /eui and EldoUI's own buttons (design
	-- decision), so this page says how, and offers only the tools that
	-- aren't the options.
	local how = E:CreateText(panel, E.tokens.size.dialogTitle, "CENTER")
	E:SetHeaderFont(how, E.tokens.size.dialogTitle)
	how:SetPoint("TOP", version, "BOTTOM", 0, -24)
	how:SetText(L["Type %s in chat or use the EldoUI button in the Game Menu to open the EldoUI options."]:format(E:Highlight("/eui")))

	panel.how = how
	local why = E:CreateText(panel, E.tokens.size.body, "CENTER")
	why:SetTextColor(unpack(E.tokens.text.secondary))
	why:SetPoint("TOP", how, "BOTTOM", 0, -6)
	why:SetText(L["Every EldoUI setting lives there, with a search over all of them."])

	panel.status = E:CreateText(panel, E.tokens.size.body, "CENTER")
	panel.status:SetPoint("TOP", why, "BOTTOM", 0, -18)

	local quick = {
		{ L["Move mode"], L["Drag EldoUI's frames where you want them. Right-click a frame for its exact position."],
			function() CloseSettingsThen(function() E:ToggleMoveMode() end) end },
		{ L["Keybind mode"], L["Hover any EldoUI button and press a key to bind it. Out of combat only."],
			function() CloseSettingsThen(function() E:ToggleKeybindMode() end) end },
		{ L["Run the setup again"], L["The setup again: scale, layout, look, role and chat. It asks before it changes anything."],
			function() CloseSettingsThen(function() E:ShowInstaller() end) end },
	}
	-- One centered row; each button takes the width its label needs.
	local firstRow, buttons, total, gap = nil, {}, 0, 10
	panel.quick = buttons
	for index, entry in ipairs(quick) do
		local button = Button(panel, entry[1], 200, entry[3])
		E.UIKit.Tooltip(button, entry[1], entry[2])
		buttons[index] = button
		total = total + button:GetWidth() + (index > 1 and gap or 0)
		firstRow = firstRow or button
	end
	local x = -total / 2
	for _, button in ipairs(buttons) do
		button:SetPoint("TOPLEFT", panel.status, "BOTTOM", math.floor(x + 0.5), -18)
		x = x + button:GetWidth() + gap
	end
	panel.firstRow = firstRow

	panel:SetScript("OnShow", function()
		local layout = E.layouts[E.db.general.layout]
		panel.status:SetText(L["Layout: %s     Profile: %s"]:format(
			E:Highlight(layout and layout.title or E.db.general.layout), E:Highlight(E.profileName)))
		E:LayoutSettingsButtons()
	end)

	local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
	Settings.RegisterAddOnCategory(category)
	self.optionsCategory = category
end

---------------------------------------------------------------------------
-- Module buttons: a second row of quick buttons for windows modules own,
-- shown while their module can open them (My Adventure).
--   E:RegisterSettingsButton(key, { label, desc, order, shown = fn, func = fn })
-- `label` and `desc` are shown as given (pass them through L[]). A click
-- closes the Settings window first, like the buttons above.
---------------------------------------------------------------------------
local extra, extraOrder = {}, {}

function E:RegisterSettingsButton(key, def)
	if type(key) ~= "string" or type(def) ~= "table" or type(def.func) ~= "function" then return end
	if not extra[key] then extraOrder[#extraOrder + 1] = key end
	extra[key] = { key = key, label = tostring(def.label or key), desc = def.desc, order = tonumber(def.order) or 50,
		shown = def.shown, func = def.func }
	table.sort(extraOrder, function(a, b)
		if extra[a].order ~= extra[b].order then return extra[a].order < extra[b].order end
		return a < b
	end)
	if panel and panel:IsShown() then self:LayoutSettingsButtons() end
end

function E:UnregisterSettingsButton(key)
	if not extra[key] then return end
	extra[key] = nil
	for index, name in ipairs(extraOrder) do
		if name == key then table.remove(extraOrder, index) break end
	end
	if panel and panel:IsShown() then self:LayoutSettingsButtons() end
end

local function Shown(def)
	if type(def.shown) ~= "function" then return true end
	local ok, shown = pcall(def.shown)
	return ok and shown and true or false
end

-- The buttons shown now, in order.
function E:SettingsButtons()
	local list = {}
	for _, key in ipairs(extraOrder) do
		if Shown(extra[key]) then list[#list + 1] = extra[key] end
	end
	return list
end

function E:LayoutSettingsButtons()
	if not (panel and panel.firstRow) then return end
	panel.extraButtons = panel.extraButtons or {}
	local list = self:SettingsButtons()
	-- Every button as wide as its label (at least 200); the columns take the widest.
	local step = 210
	for index, def in ipairs(list) do
		local button = panel.extraButtons[index]
		if not button then
			button = Button(panel, "", 200, function(own)
				local chosen = own.def
				CloseSettingsThen(function() if chosen then chosen.func() end end)
			end)
			button:SetScript("OnEnter", function(own)
				if not (own.def and own.def.desc) then return end
				E.UIKit.AnchorTooltip(own, GameTooltip)
				E.UIKit.TipTitle(GameTooltip, own.def.label)
				E.UIKit.TipText(GameTooltip, own.def.desc)
				GameTooltip:Show()
			end)
			button:SetScript("OnLeave", function() GameTooltip:Hide() end)
			panel.extraButtons[index] = button
		end
		button.def = def
		button:SetText(def.label)
		E.UIKit.FitButton(button, 200)
		step = math.max(step, button:GetWidth() + 10)
	end
	for index in ipairs(list) do
		local button = panel.extraButtons[index]
		button:ClearAllPoints()
		-- Three to a row under the quick buttons, centered like them.
		local row, column = math.floor((index - 1) / 3), (index - 1) % 3
		local inRow = math.min(#list - row * 3, 3)
		button:SetPoint("TOP", panel.status, "BOTTOM", (column - (inRow - 1) / 2) * step,
			-18 - panel.firstRow:GetHeight() - 10 - row * 36)
		button:Show()
	end
	for index = #list + 1, #panel.extraButtons do panel.extraButtons[index]:Hide() end
end
