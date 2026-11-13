-- EldoUI Macros: the editor window.
--
--   +----------------------------------------------------------------+
--   | Macro Editor   Edit   Icon                                   ? x |
--   |----------------------------------------------------------------|
--   | [Account][Character] | [icon] [Name        ]         87 / 255  |
--   |  Buff Party          | +------------------------------------+  |
--   |  Sheep Focus         | | #showtooltip                       |  |
--   |                      | | /cast [@mouseover,help] Renew      |  |
--   |                      | +------------------------------------+  |
--   |                      | [@mouseover] [harm] [mod:shift] ...     |
--   |                      | 1 #showtooltip                          |
--   |                      | 2 /cast [@mouseover,help] Renew         |
--   |                      |   ! Renew is not in your spellbook      |
--   |                      | [Save] [Revert] [Duplicate] [Update]    |
--   |----------------------------------------------------------------|
--   | Saving happens out of combat.                                //|
--   +----------------------------------------------------------------+
--
-- An E.UIKit tabbed window. It stays open in combat so you can keep
-- writing; Save and Duplicate wait for you to leave combat and say so.
-- "Update to Rank N" shows when the macro names a lower spell rank
-- (Ranks.lua): on a saved macro it writes the new rank at once, on text
-- you are still editing it changes the text for your Save. "Undo rank
-- update" puts back the text from before the last update.
local _, E = ...
local L = E.L
local M = E.Macros
local Kit = E.UIKit

local WIDTH, HEIGHT = 880, 560
local LIST_WIDTH = 210

local win
local current          -- { index, name, icon, body } as the game has it
local pendingIcon      -- an icon picked but not saved yet
local listKind = "account"
local iconSources

local function DB() return M.db end

local function Toast(text, warn)
	if win and win.frame then Kit.Toast(win.frame, text, { anchor = win.frame.footer, point = "TOP", y = 4, warn = warn }) end
end

local function EditFrame()
	local tab = win and win:GetTab("edit")
	return tab and tab.frame
end

---------------------------------------------------------------------------
-- The check view
---------------------------------------------------------------------------
local function ProblemText(problem)
	if problem.kind == "rank" then return Kit.AccentHex() .. "^ " .. problem.text .. "|r" end
	local color = problem.kind == "error" and E:TokenHex(E.tokens.text.bad) or E:TokenHex(E.tokens.text.warn)
	return color .. (problem.kind == "error" and "x " or "! ") .. problem.text .. "|r"
end

function M:CheckView(body)
	local check = self:Check(body)
	local lines = {}
	local byLine = {}
	for _, problem in ipairs(check.problems) do
		byLine[problem.line] = byLine[problem.line] or {}
		table.insert(byLine[problem.line], problem)
	end
	for _, problem in ipairs(byLine[0] or {}) do lines[#lines + 1] = ProblemText(problem) end
	local dim = E:TokenHex(E.tokens.text.dim)
	for number, text in ipairs(check.colored) do
		local prefix = DB().lineNumbers and (dim .. ("%2d"):format(number) .. "|r  ") or ""
		lines[#lines + 1] = prefix .. text
		for _, problem in ipairs(byLine[number] or {}) do
			lines[#lines + 1] = (DB().lineNumbers and "      " or "   ") .. ProblemText(problem)
		end
	end
	if #check.problems == 0 and body ~= "" then
		lines[#lines + 1] = E:TokenHex(E.tokens.text.good) .. L["No problems found."] .. "|r"
	end
	return table.concat(lines, "\n"), check
end

local function UpdateCheck()
	local frame = EditFrame()
	if not frame then return end
	local body = frame.box:GetText() or ""
	local text, check = M:CheckView(body)
	frame.check:SetText(text)
	local over = check.length > M.MAX_LENGTH
	local color = over and E:TokenHex(E.tokens.text.bad) or (check.length > M.MAX_LENGTH - 20 and E:TokenHex(E.tokens.text.warn) or E:TokenHex(E.tokens.text.secondary))
	frame.count:SetText(color .. ("%d / %d"):format(check.length, M.MAX_LENGTH) .. "|r")
	local dirty = current and (body ~= current.body or strtrim(frame.nameBox:GetText() or "") ~= current.name or pendingIcon ~= nil)
	frame.save:SetEnabled(current ~= nil and dirty and true or false)
	frame.revert:SetEnabled(current ~= nil and dirty and true or false)
	frame.duplicate:SetEnabled(current ~= nil)
	-- The rank buttons, after Duplicate.
	local ranks = current ~= nil and check.rankBody ~= nil
	if ranks then
		frame.rankUpdate:SetText(E:MacroRankButtonText(check.rankChanges))
		Kit.RefitButton(frame.rankUpdate)
	end
	frame.rankUpdate:SetShown(ranks)
	local undo = current ~= nil and E:HasMacroRankUndo(current.index)
	frame.rankUndo:ClearAllPoints()
	frame.rankUndo:SetPoint("LEFT", ranks and frame.rankUpdate or frame.duplicate, "RIGHT", 6, 0)
	frame.rankUndo:SetShown(undo and true or false)
	if win then win:UpdateFooter() end
end
M.UpdateCheck = UpdateCheck

---------------------------------------------------------------------------
-- Loading, saving
---------------------------------------------------------------------------
local function ShowIcon(frame, icon)
	frame.icon.tex:SetTexture(E:ClientIcon(icon, "Interface\\Icons\\INV_Misc_QuestionMark"))
end

function M:Load(index)
	local frame = EditFrame()
	local macro = self:Get(index)
	current = macro
	pendingIcon = nil
	if not frame then return macro end
	if macro then
		listKind = macro.character and "character" or "account"
		frame.nameBox:SetText(macro.name)
		frame.box:SetText(macro.body)
		ShowIcon(frame, macro.icon)
	else
		frame.nameBox:SetText("")
		frame.box:SetText("")
		ShowIcon(frame, nil)
	end
	frame.kinds:SetSelected(listKind)
	frame.list:SetData(self:ListFor(listKind))
	-- The Icon tab shows once a macro is loaded.
	if win.LayoutTabs then win:LayoutTabs() end
	UpdateCheck()
	return macro
end

function M:ListFor(kind)
	local out = {}
	for _, macro in ipairs(self:List()) do
		if (kind == "character") == macro.character then out[#out + 1] = macro end
	end
	return out
end

function M:SaveCurrent()
	local frame = EditFrame()
	if not (frame and current) then return false end
	local index, why = self:Save(current.index, frame.nameBox:GetText(), pendingIcon or current.icon, frame.box:GetText())
	if not index then
		Toast(why, true)
		return false
	end
	self:Load(index)
	Toast(L["Macro saved."])
	return true
end

-- Raise the lower spell ranks: a saved macro is written at once (out of
-- combat, with Undo); text you are still editing changes in the box only,
-- and your Save writes it.
function M:UpdateRanksCurrent()
	local frame = EditFrame()
	if not (frame and current) then return false end
	local body = frame.box:GetText() or ""
	local changes, newBody = E:MacroRankChanges(body)
	if not newBody then return false end
	if body ~= current.body then
		if #newBody > self.MAX_LENGTH then
			Toast(L["With the new rank the macro would have %d characters, and a macro holds %d. Shorten it first."]:format(#newBody, self.MAX_LENGTH), true) -- no-plural: always over the macro limit
			return false
		end
		frame.box:SetText(newBody)
		UpdateCheck()
		Toast(E:Plural(#changes, "Spell rank raised in the text. Save to keep it.", "Spell ranks raised in the text. Save to keep them."))
		return true
	end
	local index, why = E:UpdateMacroRanks(current.index)
	if not index then
		Toast(why, true)
		return false
	end
	self:Load(index)
	Toast(why)
	return true
end

function M:UndoRanksCurrent()
	if not current then return false end
	local index, why = E:UndoMacroRanks(current.index)
	if not index then
		Toast(why, true)
		UpdateCheck()
		return false
	end
	self:Load(index)
	Toast(why)
	return true
end

function M:RevertCurrent()
	if not current then return end
	self:Load(current.index)
	Toast(L["Back to the saved macro."])
end

function M:DuplicateCurrent()
	if not current then return end
	local index, why = self:Duplicate(current.index)
	if not index then
		Toast(why, true)
		return
	end
	self:Load(index)
	Toast(L["Copy made: %s."]:format(current and current.name or ""))
end

-- Insert a condition at the cursor: inside or right after a [...] it joins
-- that bracket; elsewhere it gets its own.
function M:InsertCondition(condition)
	local frame = EditFrame()
	if not frame then return end
	local box = frame.box
	local text = box:GetText() or ""
	local cursor = box:GetCursorPosition() or #text
	local before, after = text:sub(1, cursor), text:sub(cursor + 1)
	local open = before:match(".*()%[") or 0
	local close = before:match(".*()%]") or 0
	local insert
	if open > close then
		-- Inside brackets: add with a comma.
		local last = before:sub(-1)
		insert = (last == "[" or last == ",") and condition or ("," .. condition)
	elseif before:sub(-1) == "]" then
		before = before:sub(1, -2)
		insert = "," .. condition .. "]"
	else
		local last = before:sub(-1)
		insert = ((last ~= "" and last ~= " " and last ~= "\n") and " " or "") .. "[" .. condition .. "]"
	end
	box:SetText(before .. insert .. after)
	box:SetCursorPosition(#before + #insert)
	box:SetFocus()
	UpdateCheck()
end

---------------------------------------------------------------------------
-- Edit tab
---------------------------------------------------------------------------
local function CreateListRow(row)
	E:SkinRow(row)
	row.select = row:CreateTexture(nil, "BACKGROUND", nil, -5)
	row.select:SetAllPoints()
	row.select:Hide()
	row.iconBox = CreateFrame("Frame", nil, row)
	row.iconBox:SetSize(16, 16)
	row.iconBox:SetPoint("LEFT", 4, 0)
	E:SetTemplate(row.iconBox)
	row.icon = row.iconBox:CreateTexture(nil, "ARTWORK")
	row.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	row.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(row.icon)
	row.text = Kit.Text(row, E.tokens.size.label, "LEFT")
	row.text:SetPoint("LEFT", row.iconBox, "RIGHT", 6, 0)
	row.text:SetPoint("RIGHT", -4, 0)
	row.text:SetWordWrap(false)
	row:SetScript("OnClick", function(self)
		if self.item then M:Load(self.item.index) end
	end)
end

local function UpdateListRow(row, macro)
	row.icon:SetTexture(E:ClientIcon(macro.icon, "Interface\\Icons\\INV_Misc_QuestionMark"))
	row.text:SetText(macro.name)
	if current and current.index == macro.index then
		local r, g, b = Kit.Accent()
		row.select:SetColorTexture(r, g, b, E.tokens.pressed)
		row.select:Show()
	else
		row.select:Hide()
	end
end

local function ApplyFont(frame)
	local db = DB()
	local size = math.max(10, math.min(20, tonumber(db.fontSize) or 13))
	-- Window text: grows with General > Large text.
	E:SetMediaFont(frame.box, db.font, size, nil, true)
	E:SetMediaFont(frame.check, db.font, size, nil, true)
end

local function CreateEditTab(content)
	local frame = CreateFrame("Frame", nil, content)
	frame:SetAllPoints()
	-- Left: the macro lists.
	frame.kinds = Kit.ChipBar(frame, {
		chips = {
			{ "account", L["Account"], L["Macros every character of the account shares."] },
			{ "character", L["Character"], L["Macros of this character only."] },
		},
		selected = listKind,
		onChange = function(selected, key)
			if not selected[key] then frame.kinds:SetSelected(key) end
			listKind = key
			frame.list:SetData(M:ListFor(listKind))
		end,
	})
	frame.kinds:SetPoint("TOPLEFT", 0, -2)
	frame.list = Kit.CreateList(frame, { rowHeight = 22, create = CreateListRow, update = UpdateListRow })
	frame.list:SetPoint("TOPLEFT", 0, -26)
	frame.list:SetPoint("BOTTOMLEFT", 0, 0)
	frame.list:SetWidth(LIST_WIDTH)
	frame.list:SetEmpty(L["No macros"], L["Make one in Blizzard's macro window (New), then edit it here."])
	local divider = Kit.Divider(frame)
	divider:SetPoint("TOPLEFT", frame.list, "TOPRIGHT", 8, 26)
	divider:SetPoint("BOTTOMLEFT", frame.list, "BOTTOMRIGHT", 8, 0)
	divider:SetWidth(E.pixel)

	local left = LIST_WIDTH + 20
	-- Name, icon and counter.
	frame.icon = CreateFrame("Button", nil, frame)
	frame.icon:SetSize(32, 32)
	frame.icon:SetPoint("TOPLEFT", left, 0)
	E:SetTemplate(frame.icon)
	frame.icon.tex = frame.icon:CreateTexture(nil, "ARTWORK")
	frame.icon.tex:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	frame.icon.tex:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(frame.icon.tex)
	E:SkinHoverPress(frame.icon)
	frame.icon:SetScript("OnClick", function() if current then win:Open("icon") end end)
	Kit.Tooltip(frame.icon, L["Icon"], nil, { { L["Click"], L["search an icon by spell or item name"] } })
	frame.nameBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	frame.nameBox:SetSize(200, 22)
	frame.nameBox:SetAutoFocus(false)
	frame.nameBox:SetMaxLetters(M.NAME_LENGTH)
	frame.nameBox:SetPoint("LEFT", frame.icon, "RIGHT", 12, 0)
	E:SkinEditBox(frame.nameBox)
	frame.nameBox:SetScript("OnTextChanged", function() UpdateCheck() end)
	frame.nameBox:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
	Kit.Tooltip(frame.nameBox, L["Name"], L["The macro's name (up to 16 letters)."])
	frame.count = Kit.Text(frame, E.tokens.size.label, "RIGHT", "secondary")
	frame.count:SetPoint("RIGHT", frame, "TOPRIGHT", -4, -16)

	-- The text.
	frame.editBox = CreateFrame("Frame", nil, frame)
	frame.editBox:SetPoint("TOPLEFT", left, -42)
	frame.editBox:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -42)
	frame.editBox:SetHeight(150)
	E:SetTemplate(frame.editBox, true)
	frame.box = CreateFrame("EditBox", nil, frame.editBox)
	frame.box:SetMultiLine(true)
	frame.box:SetAutoFocus(false)
	frame.box:SetMaxLetters(1023)
	frame.box:SetPoint("TOPLEFT", 6, -6)
	frame.box:SetPoint("BOTTOMRIGHT", -6, 6)
	frame.box:SetTextInsets(0, 0, 0, 0)
	frame.box:SetScript("OnTextChanged", function() UpdateCheck() end)
	frame.box:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
	-- Tab goes from the name to the text and back.
	Kit.TabOrder(frame.nameBox, frame.box)
	frame.editBox:EnableMouse(true)
	frame.editBox:SetScript("OnMouseDown", function() frame.box:SetFocus() end)

	-- The condition builder.
	frame.chips = CreateFrame("Frame", nil, frame)
	frame.chips:SetPoint("TOPLEFT", frame.editBox, "BOTTOMLEFT", 0, -8)
	frame.chips:SetPoint("TOPRIGHT", frame.editBox, "BOTTOMRIGHT", 0, -8)
	frame.chips:SetHeight(42)
	frame.chipButtons = {}
	for index, chip in ipairs(M.CHIPS) do
		local button = Kit.Chip(frame.chips, "[" .. chip[1] .. "]")
		button:SetHeight(18)
		button:SetScript("OnClick", function() M:InsertCondition(chip[1]) end)
		Kit.Tooltip(button, "[" .. chip[1] .. "]", L[chip[2]], { { L["Click"], L["insert it at the cursor"] } })
		E:SkinHoverPress(button)
		E:PadHitRect(button, 2)
		frame.chipButtons[index] = button
	end
	frame.chips:SetScript("OnSizeChanged", function(chips)
		local width = chips:GetWidth() or 0
		local x, y = 0, 0
		for _, button in ipairs(frame.chipButtons) do
			local w = button:GetWidth()
			if x > 0 and x + w > width then x, y = 0, y - 22 end
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", x, y)
			x = x + w + 4
		end
	end)

	-- The check view.
	frame.checkBox = CreateFrame("Frame", nil, frame)
	frame.checkBox:SetPoint("TOPLEFT", frame.chips, "BOTTOMLEFT", 0, -8)
	frame.checkBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 34)
	E:SetTemplate(frame.checkBox, true)
	frame.check = Kit.Text(frame.checkBox, E.tokens.size.body, "LEFT")
	frame.check:SetPoint("TOPLEFT", 8, -6)
	frame.check:SetPoint("BOTTOMRIGHT", -8, 6)
	frame.check:SetJustifyV("TOP")
	frame.check:SetWordWrap(true)

	-- Buttons.
	frame.save = Kit.Button(frame, L["Save"], 90, E.tokens.height.button, function() M:SaveCurrent() end,
		L["Save"], L["Writes the name, icon and text to the game's macro (out of combat)."])
	frame.save:SetPoint("BOTTOMLEFT", left, 0)
	frame.revert = Kit.Button(frame, L["Revert"], 90, E.tokens.height.button, function() M:RevertCurrent() end,
		L["Revert"], L["Throws away your changes and shows the saved macro again."])
	frame.revert:SetPoint("LEFT", frame.save, "RIGHT", 6, 0)
	frame.duplicate = Kit.Button(frame, L["Duplicate"], 90, E.tokens.height.button, function() M:DuplicateCurrent() end,
		L["Duplicate"], L["Makes a copy of the saved macro in the same list (out of combat)."])
	frame.duplicate:SetPoint("LEFT", frame.revert, "RIGHT", 6, 0)
	for _, button in ipairs({ frame.save, frame.revert, frame.duplicate }) do Kit.FitButton(button, 90) end
	frame.rankUpdate = Kit.Button(frame, { text = L["Update spell ranks"], kind = "primary", minWidth = 90,
		onClick = function() M:UpdateRanksCurrent() end,
		tip = { L["Update spell ranks"], L["The macro names a lower rank of a spell you know at a higher rank. Changes only the rank number to the highest rank you know (out of combat). Undo puts the old text back."] } })
	frame.rankUpdate:SetPoint("LEFT", frame.duplicate, "RIGHT", 6, 0)
	frame.rankUpdate:Hide()
	frame.rankUndo = Kit.Button(frame, { text = L["Undo rank update"], minWidth = 90,
		onClick = function() M:UndoRanksCurrent() end,
		tip = { L["Undo rank update"], L["Puts back the macro text from before its last spell rank update (out of combat, until you log out)."] } })
	frame.rankUndo:SetPoint("LEFT", frame.duplicate, "RIGHT", 6, 0)
	frame.rankUndo:Hide()
	ApplyFont(frame)
	return frame
end

---------------------------------------------------------------------------
-- Icon tab
---------------------------------------------------------------------------
local ICON_SIZE, ICON_GAP = 36, 4

local function CreateIconTab(content)
	local frame = CreateFrame("Frame", nil, content)
	frame:SetAllPoints()
	frame.search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
	E:SearchHint(frame.search)
	frame.search:SetSize(260, 22)
	frame.search:SetAutoFocus(false)
	frame.search:SetPoint("TOPLEFT", 4, -2)
	E:SkinEditBox(frame.search)
	frame.search:SetScript("OnTextChanged", function(box)
		if SearchBoxTemplate_OnTextChanged then pcall(SearchBoxTemplate_OnTextChanged, box) end
		frame.offset = 0
		M:UpdateIcons()
	end)
	Kit.Tooltip(frame.search, L["Search icons"], L["Type a spell or item name. Empty shows every icon the game offers."])
	frame.hint = Kit.Text(frame, E.tokens.size.small, "LEFT", "secondary")
	frame.hint:SetPoint("LEFT", frame.search, "RIGHT", 12, 0)
	frame.grid = CreateFrame("Frame", nil, frame)
	frame.grid:SetPoint("TOPLEFT", 0, -32)
	frame.grid:SetPoint("BOTTOMRIGHT")
	frame.grid:EnableMouseWheel(true)
	frame.grid:SetScript("OnMouseWheel", function(_, delta)
		frame.offset = math.max(0, (frame.offset or 0) - delta * (frame.columns or 1))
		M:UpdateIcons()
	end)
	frame.buttons = {}
	frame.offset = 0
	return frame
end

local function IconButton(frame, index)
	local button = frame.buttons[index]
	if button then return button end
	button = CreateFrame("Button", nil, frame.grid)
	button:SetSize(ICON_SIZE, ICON_SIZE)
	E:SetTemplate(button)
	button.tex = button:CreateTexture(nil, "ARTWORK")
	button.tex:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	button.tex:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(button.tex)
	E:SkinHoverPress(button, nil, button)
	button:SetScript("OnClick", function(self) M:PickIcon(self.entry) end)
	button:SetScript("OnEnter", function(self)
		if not self.entry then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		Kit.TipTitle(GameTooltip, self.entry.name or L["Game icon"])
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	frame.buttons[index] = button
	return button
end

function M:UpdateIcons()
	local tab = win and win:GetTab("icon")
	local frame = tab and tab.frame
	if not frame then return end
	iconSources = iconSources or self:IconSources()
	local results = self:SearchIcons(frame.search:GetText(), iconSources)
	frame.results = results
	local width, height = frame.grid:GetWidth() or 0, frame.grid:GetHeight() or 0
	local columns = math.max(1, math.floor((width + ICON_GAP) / (ICON_SIZE + ICON_GAP)))
	local rows = math.max(1, math.floor((height + ICON_GAP) / (ICON_SIZE + ICON_GAP)))
	frame.columns = columns
	local maxOffset = math.max(0, math.ceil(#results / columns) * columns - columns * rows)
	frame.offset = math.min(frame.offset or 0, maxOffset)
	for slot = 1, math.max(columns * rows, #frame.buttons) do
		local entry = slot <= columns * rows and results[frame.offset + slot]
		local button = entry and IconButton(frame, slot) or frame.buttons[slot]
		if entry then
			button.entry = entry
			button.tex:SetTexture(E:ClientIcon(entry.icon, "Interface\\Icons\\INV_Misc_QuestionMark"))
			button:ClearAllPoints()
			local col, row = (slot - 1) % columns, math.floor((slot - 1) / columns)
			button:SetPoint("TOPLEFT", col * (ICON_SIZE + ICON_GAP), -row * (ICON_SIZE + ICON_GAP))
			button:Show()
		elseif button then
			button.entry = nil
			button:Hide()
		end
	end
	frame.hint:SetText(E:Plural(#results, "%d icon", "%d icons"):format(#results) .. "   " .. L["Mouse wheel scrolls."])
end

function M:PickIcon(entry)
	if not (entry and current) then return end
	pendingIcon = entry.icon
	win:Open("edit")
	local frame = EditFrame()
	if frame then ShowIcon(frame, entry.icon) end
	UpdateCheck()
	Toast(L["Icon picked. Save to keep it."])
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function CreateWindow()
	if win then return win end
	win = Kit.CreateTabbedWindow({
		name = "EldoUIMacroEditor",
		options = { page = "module:Macros" },
		title = L["Macro Editor"],
		width = WIDTH, height = HEIGHT,
		store = function() return M.db.window end,
		hideInCombat = false,
		transparent = function() return M.db.transparent end,
		tabs = {
			{ key = "edit", title = L["Edit"], desc = L["Write the macro with a live check and the condition builder."],
				create = CreateEditTab,
				show = function(frame)
					ApplyFont(frame)
					frame.chips:SetShown(DB().chips)
					frame.checkBox:ClearAllPoints()
					frame.checkBox:SetPoint("TOPLEFT", DB().chips and frame.chips or frame.editBox, "BOTTOMLEFT", 0, -8)
					frame.checkBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 34)
					frame.list:SetData(M:ListFor(listKind))
					UpdateCheck()
				end },
			{ key = "icon", title = L["Icon"], desc = L["Find an icon by spell or item name."],
				hidden = function() return current == nil end,
				create = CreateIconTab,
				show = function(frame)
					iconSources = nil
					frame.offset = 0
					M:UpdateIcons()
				end },
		},
		help = { text = function(tooltip)
			local c = Kit.SECONDARY
			tooltip:AddLine(L["Red lines stop the macro from working; orange words are only a warning (a spell you learn later is fine)."], c[1], c[2], c[3], true)
			tooltip:AddLine(" ")
			tooltip:AddLine(L["Saving happens out of combat. Running a macro is always your own key press."], c[1], c[2], c[3], true)
		end },
		footer = function()
			if InCombatLockdown() then return L["In combat: keep writing, Save waits until combat ends."] end
			local frame = EditFrame()
			if frame and current then
				local check = M:Check(frame.box:GetText() or "")
				if check.errors > 0 then return E:Plural(check.errors, "%d problem to fix before saving.", "%d problems to fix before saving."):format(check.errors) end
				if check.rankBody then return L["A lower spell rank: %s changes only the rank number."]:format(E:MacroRankButtonText(check.rankChanges)) end
				if check.warnings > 0 then return E:Plural(check.warnings, "%d warning. You can still save.", "%d warnings. You can still save."):format(check.warnings) end
				return L["No problems found."]
			end
			return L["Pick a macro on the left."]
		end,
	})
	return win
end

function M:Window() return win end
function M:Current() return current end
function M:PendingIcon() return pendingIcon end

-- Open the editor at a macro (index), or at Blizzard's selection.
function M:OpenEditor(index)
	if not self.active then return false end
	local window = CreateWindow()
	local first = not window.frame
	window:Open("edit")
	index = index or self:BlizzardSelection() or (current and current.index)
	if not index then
		local list = self:List()
		index = list[1] and list[1].index
	end
	self:Load(index)
	-- Next to Blizzard's macro window, until you move it yourself.
	local macro = rawget(_G, "MacroFrame")
	local store = self.db.window
	if first and macro and macro:IsShown() and not (store.x and store.y) then
		window.frame:ClearAllPoints()
		window.frame:SetPoint("TOPLEFT", macro, "TOPRIGHT", 8, 0)
	end
	return true
end

function M:CloseEditor()
	if win then win:Close() end
end

---------------------------------------------------------------------------
-- Blizzard's macro window: an "Edit in EldoUI" button, and the editor
-- following its selection.
---------------------------------------------------------------------------
local hooked
function M:AttachBlizzard()
	local frame = rawget(_G, "MacroFrame")
	if not frame then return end
	if self.blizzButton and self.blizzButton:GetParent() ~= frame then
		self.blizzButton:Hide()
		self.blizzButton = nil
	end
	if not self.blizzButton then
		local anchor = rawget(_G, "MacroDeleteButton")
		local button = Kit.Button(frame, L["Edit in EldoUI"], 110, E.tokens.height.button, function() M:OpenEditor() end,
			L["Edit in EldoUI"], L["Opens the selected macro in EldoUI's editor with the syntax check, condition builder and icon search."])
		Kit.FitButton(button, 110)
		if anchor then button:SetPoint("LEFT", anchor, "RIGHT", 4, 0) else button:SetPoint("BOTTOMLEFT", 90, 4) end
		self.blizzButton = button
	end
	self.blizzButton:SetShown(self.active and true or false)
	if hooked ~= frame then
		hooked = frame
		if frame.SelectMacro then
			hooksecurefunc(frame, "SelectMacro", function()
				if M.active and win and win:IsOpen() then
					local index = M:BlizzardSelection()
					if index and (not current or current.index ~= index) then M:Load(index) end
				end
			end)
		end
		frame:HookScript("OnShow", function()
			if M.active and M.db.autoOpen then M:OpenEditor() end
		end)
		frame:HookScript("OnHide", function()
			if M.active and M.db.autoOpen then M:CloseEditor() end
		end)
	end
end

function M:OnEnable()
	E:OnBlizzardAddOn("Blizzard_MacroUI", function() M:AttachBlizzard() end)
	self:RegisterEvent("UPDATE_MACROS", function()
		if win and win:IsOpen() then
			local frame = EditFrame()
			if frame then frame.list:SetData(M:ListFor(listKind)) end
		end
	end)
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function() if win then win:UpdateFooter() end end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() if win then win:UpdateFooter() end end)
end

function M:OnDisable()
	self:CloseEditor()
	if self.blizzButton then self.blizzButton:Hide() end
end

function M:OnProfileChanged()
	if not self.active then return end
	if self.blizzButton then self.blizzButton:Show() end
	if win and win.frame then
		win:Restyle()
		local frame = EditFrame()
		if frame and win:IsOpen() and win:Current() == "edit" then
			local tab = win:GetTab("edit")
			tab.show(frame)
		end
	end
end

E:AddCommand("macros", "  open the EldoUI macro editor", function()
	if not M.active then
		E:Print(E:ModuleOffHint("Macros"))
		return
	end
	M:OpenEditor()
end, "Tools")
