-- EldoUI Bags, part six: the category editor.
--
-- A tool window "Bag categories": on the left every section of the
-- Categories view in its order (own categories with their color, the
-- built-in sections), with buttons to move the selected one up, down or to
-- the top; on the right the selected section: an own category's name,
-- color, search, priority, bag and bank switches, the items filed into it
-- and its left-out items, or a built-in section's on/off switch. The
-- footer makes, deletes, exports and imports categories. The data and the
-- matching are in Modules/Bags/Categories.lua. Written from scratch for
-- EldoUI.
local _, E = ...
local L = E.L

local M = E:GetModule("Bags")
if not M then return end

local LIST_WIDTH = 250
local LABEL_WIDTH = 92
local GAP = 8

local editor
local selected -- the selected section key

-- Player text shown as typed: a "|" (the search's "or") is not a text code.
local function Plain(text)
	return (tostring(text or ""):gsub("|", "||"))
end

-- The rows of the left list: { key, cat } in section order (without Free).
local function Rows()
	local rows = {}
	for _, key in ipairs(M:SectionOrder()) do
		if key ~= "free" then rows[#rows + 1] = { key = key, cat = M:OwnCategory(key) } end
	end
	return rows
end

local function BuiltInTitle(key)
	local index = key:match("^custom(%d)$")
	if index then
		local custom = M.db.custom and M.db.custom[tonumber(index)]
		return custom and custom.name ~= "" and custom.name or L["Custom %s"]:format(index)
	end
	return M.CATEGORY_TITLE[key] or key
end

local function Count(set)
	local count = 0
	for _, on in pairs(set or {}) do
		if on then count = count + 1 end
	end
	return count
end

-- The short line under a row's name.
local function Summary(row)
	local cat = row.cat
	if not cat then
		local on = M.db.categories[row.key]
		return on == false and L["Built-in, off"] or L["Built-in"]
	end
	local parts = {}
	if cat.query ~= "" then parts[#parts + 1] = Plain(cat.query) end
	local filed = Count(cat.items)
	if filed > 0 then parts[#parts + 1] = E:Plural(filed, "%d item", "%d items"):format(filed) end
	if cat.bags == false then
		parts[#parts + 1] = L["bank only"]
	elseif cat.bank == false then
		parts[#parts + 1] = L["bags only"]
	end
	if #parts == 0 then return L["Empty: add a search or drop items on its title"] end
	return table.concat(parts, "  ·  ")
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
local function CreateRow(row)
	local Kit = E.UIKit
	local hover = E:SkinHoverPress(row)
	if hover then hover:SetColorTexture(1, 1, 1, E.tokens.hover.row) end
	row.select = row:CreateTexture(nil, "BACKGROUND", nil, -5)
	row.select:SetAllPoints()
	row.select:Hide()
	row.swatch = row:CreateTexture(nil, "ARTWORK")
	row.swatch:SetSize(10, 10)
	row.swatch:SetPoint("LEFT", 8, 0)
	row.name = Kit.Text(row, E.tokens.size.body, "LEFT")
	row.name:SetPoint("BOTTOMLEFT", row, "LEFT", 26, 1)
	row.name:SetPoint("BOTTOMRIGHT", row, "RIGHT", -6, 1)
	row.name:SetWordWrap(false)
	row.sub = Kit.Text(row, E.tokens.size.small, "LEFT", "secondary")
	row.sub:SetPoint("TOPLEFT", row, "LEFT", 26, -2)
	row.sub:SetPoint("TOPRIGHT", row, "RIGHT", -6, -2)
	row.sub:SetWordWrap(false)
	row:SetScript("OnClick", function(own)
		if own.item then M:SelectCategoryRow(own.item.key) end
	end)
end

local function UpdateRow(row, item)
	row.item = item
	local cat = item.cat
	if cat then
		row.swatch:SetColorTexture(cat.color[1], cat.color[2], cat.color[3], 1)
		row.name:SetText(Plain(M:CategoryName(cat)))
		row.name:SetTextColor(cat.color[1], cat.color[2], cat.color[3])
	else
		local gray = E.tokens.text.secondary
		row.swatch:SetColorTexture(gray[1], gray[2], gray[3], 0.6)
		row.name:SetText(BuiltInTitle(item.key))
		E.UIKit.Paint(row.name, "body")
	end
	row.sub:SetText(Summary(item))
	local on = item.key == selected
	if on then
		local r, g, b = E.UIKit.Accent()
		row.select:SetColorTexture(r, g, b, E.tokens.pressed)
	end
	row.select:SetShown(on)
	row:SetAlpha(not cat and M.db.categories[item.key] == false and E.tokens.disabledAlpha or 1)
end

---------------------------------------------------------------------------
-- The form
---------------------------------------------------------------------------
local function Label(parent, text)
	local label = E.UIKit.Text(parent, E.tokens.size.label, "LEFT", "secondary")
	label:SetWidth(LABEL_WIDTH)
	label:SetText(text)
	return label
end

-- Commits a text field on Enter and when it loses focus.
local function Commit(box, apply)
	box:HookScript("OnEditFocusLost", function(own)
		if own.eldoQuiet then return end
		apply(own:GetText() or "")
	end)
end

local function CreateItemRow(row)
	local Kit = E.UIKit
	local hover = E:SkinHoverPress(row)
	if hover then hover:SetColorTexture(1, 1, 1, E.tokens.hover.row) end
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("LEFT", 4, 0)
	E:TrimIcon(row.icon)
	row.name = Kit.Text(row, E.tokens.size.label, "LEFT")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.name:SetPoint("RIGHT", -28, 0)
	row.name:SetWordWrap(false)
	row.remove = Kit.RemoveButton(row, function()
		local cat = M:OwnCategory(selected)
		if cat and row.item then
			cat.items[row.item] = nil
			M:CategoriesChanged()
		end
	end, L["Take it out"], L["The item goes back to the section its search or type gives it."])
	row.remove:SetPoint("RIGHT", -4, 0)
	row:SetScript("OnEnter", function(own)
		if not own.item then return end
		GameTooltip:SetOwner(own, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(own.item)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
end

local function UpdateItemRow(row, id)
	row.item = id
	row.icon:SetTexture(C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) or nil)
	local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
	if not name and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
	row.name:SetText(name or ("item:" .. id))
	local quality = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
	local r, g, b = E.UIKit.QualityColor(quality)
	if r then row.name:SetTextColor(r, g, b) else E.UIKit.Paint(row.name, "body") end
end

local function PickColor(cat)
	local picker = rawget(_G, "ColorPickerFrame")
	if not (picker and picker.SetupColorPickerAndShow) then return end
	local previous = { cat.color[1], cat.color[2], cat.color[3] }
	local function Apply(r, g, b)
		cat.color = { r, g, b }
		M:CategoriesChanged()
	end
	picker:SetupColorPickerAndShow({
		r = previous[1], g = previous[2], b = previous[3],
		swatchFunc = function() Apply(picker:GetColorRGB()) end,
		cancelFunc = function() Apply(previous[1], previous[2], previous[3]) end,
	})
end

local function CreateForm(parent)
	local Kit = E.UIKit
	local form = CreateFrame("Frame", nil, parent)
	form.title = Kit.Title(form, E.tokens.size.dialogTitle)
	form.title:SetPoint("TOPLEFT", 0, -2)
	form.title:SetPoint("TOPRIGHT", 0, -2)
	form.title:SetWordWrap(false)

	-- Own category.
	local own = CreateFrame("Frame", nil, form)
	own:SetPoint("TOPLEFT", 0, -30)
	own:SetPoint("BOTTOMRIGHT")
	form.own = own
	-- A labeled row; `wide` controls run to the form's right edge.
	local function Row(label, control, y, wide)
		local text = Label(own, label)
		text:SetPoint("TOPLEFT", 0, y - 4)
		control:SetPoint("TOPLEFT", LABEL_WIDTH + GAP, y)
		if wide then control:SetPoint("TOPRIGHT", 0, y) end
		return text
	end
	own.name = Kit.Input(own, { width = 200, maxLetters = 40, hint = L["Name"],
		onEnter = function(text) M:SetCategoryField("name", text) end })
	Commit(own.name, function(text) M:SetCategoryField("name", text) end)
	Row(L["Name"], own.name, 0, true)
	own.color = CreateFrame("Button", nil, own)
	own.color:SetSize(36, 16)
	E:SetTemplate(own.color)
	own.color:SetScript("OnClick", function()
		local cat = M:OwnCategory(selected)
		if cat then PickColor(cat) end
	end)
	Kit.Tooltip(own.color, L["Color"], L["The color of the section's title and of its row here."])
	Row(L["Color"], own.color, -30)
	own.query = Kit.Input(own, { width = 200, hint = L["e.g. t:herb or q>=rare"],
		onEnter = function(text) M:SetCategoryField("query", text) end, tipTitle = L["Search"],
		tip = L["Items this search finds go into the category. The bag window's Search help lists every word."] })
	Commit(own.query, function(text) M:SetCategoryField("query", text) end)
	Row(L["Search"], own.query, -54, true)
	own.priority = Kit.Slider(own, { width = 150, min = 0, max = 10, step = 1,
		onChange = function(value) M:SetCategoryField("priority", value) end, tipTitle = L["Priority"],
		tip = L["When two categories' searches find the same item, the higher priority gets it."] })
	Row(L["Priority"], own.priority, -88)
	own.priorityValue = Kit.Text(own, E.tokens.size.label, "LEFT")
	own.priorityValue:SetPoint("LEFT", own.priority, "RIGHT", 10, 0)
	own.bags = Kit.Check(own, L["In the bag window"], L["Off: these items go to their next section in the bag window."],
		function(on) M:SetCategoryField("bags", on) end)
	own.bags:SetPoint("TOPLEFT", LABEL_WIDTH + GAP - 4, -108)
	own.bank = Kit.Check(own, L["In the bank window"], L["Off: these items go to their next section in the bank window."],
		function(on) M:SetCategoryField("bank", on) end)
	own.bank:SetPoint("TOPLEFT", own.bags, "BOTTOMLEFT", 0, -2)
	own.itemsTitle = Label(own, "")
	own.itemsTitle:SetWidth(0)
	own.itemsTitle:SetPoint("TOPLEFT", 0, -168)
	own.itemsHint = Kit.Text(own, E.tokens.size.small, "LEFT", "dim")
	own.itemsHint:SetPoint("TOPLEFT", own.itemsTitle, "TOPRIGHT", 8, 0)
	own.itemsHint:SetPoint("TOPRIGHT", own, "TOPRIGHT", 0, -168)
	own.itemsHint:SetWordWrap(false)
	own.itemsHint:SetText(L["Drop an item on the section's title in the bag window."])
	local box = CreateFrame("Frame", nil, own)
	box:SetPoint("TOPLEFT", 0, -186)
	box:SetPoint("BOTTOMRIGHT", 0, 34)
	E:SetTemplate(box, true)
	own.itemsBox = box
	own.items = Kit.CreateList(box, { rowHeight = 22, create = CreateItemRow, update = UpdateItemRow,
		empty = { title = L["No items filed"], text = L["Its search alone fills it."] } })
	own.items:SetPoint("TOPLEFT", 2, -2)
	own.items:SetPoint("BOTTOMRIGHT", -2, 2)
	own.forget = Kit.Button(own, "", { onClick = function()
		local cat = M:OwnCategory(selected)
		if cat then
			wipe(cat.ignore)
			M:CategoriesChanged()
		end
	end, tipTitle = L["Left-out items"], tip = L["Items you left out of this category from a section title's menu. Forgetting them lets its search find them again."] })
	own.forget:SetPoint("BOTTOMLEFT", 0, 0)

	-- Built-in section.
	local builtin = CreateFrame("Frame", nil, form)
	builtin:SetPoint("TOPLEFT", 0, -30)
	builtin:SetPoint("BOTTOMRIGHT")
	form.builtin = builtin
	builtin.text = Kit.Text(builtin, E.tokens.size.body, "LEFT", "secondary")
	builtin.text:SetPoint("TOPLEFT", 0, 0)
	builtin.text:SetPoint("TOPRIGHT", 0, 0)
	builtin.text:SetWordWrap(true)
	builtin.text:SetJustifyV("TOP")
	builtin.show = Kit.Check(builtin, L["Show this section"], L["Off: its items go to Other."], function(on)
		if M.db.categories[selected] ~= nil then
			M.db.categories[selected] = on
			M:CategoriesChanged()
		end
	end)
	builtin.show:SetPoint("TOPLEFT", -4, -54)
	return form
end

function M:SetCategoryField(field, value)
	local cat = self:OwnCategory(selected)
	if not cat then return end
	if field == "name" then
		value = strtrim(value or ""):sub(1, 40)
	elseif field == "query" then
		value = strtrim(value or "")
	elseif field == "priority" then
		value = math.floor(math.min(math.max(tonumber(value) or 0, 0), 10))
	elseif field == "bags" or field == "bank" then
		value = value and true or false
	end
	if cat[field] == value then return end
	cat[field] = value
	self:CategoriesChanged()
end

local function FillForm()
	local form = editor.form
	local cat = M:OwnCategory(selected)
	form.own:SetShown(cat ~= nil)
	form.builtin:SetShown(cat == nil and selected ~= nil)
	if cat then
		form.title:SetText(Plain(M:CategoryName(cat)))
		form.title:SetTextColor(cat.color[1], cat.color[2], cat.color[3])
		local own = form.own
		own.name.eldoQuiet = true
		if not own.name:HasFocus() then own.name:SetText(cat.name) end
		if not own.query:HasFocus() then own.query:SetText(cat.query) end
		own.name.eldoQuiet = nil
		own.color:SetBackdropColor(cat.color[1], cat.color[2], cat.color[3], 1)
		own.priority:SetQuiet(cat.priority)
		own.priorityValue:SetText(tostring(cat.priority))
		own.bags:SetChecked(cat.bags ~= false)
		own.bank:SetChecked(cat.bank ~= false)
		local ids = {}
		for id, on in pairs(cat.items) do
			if on then ids[#ids + 1] = id end
		end
		table.sort(ids)
		own.itemsTitle:SetText(L["Filed items (%d)"]:format(#ids))
		own.items:SetData(ids)
		local left = Count(cat.ignore)
		own.forget:SetText(L["Forget left-out items (%d)"]:format(left))
		E.UIKit.FitButton(own.forget)
		own.forget:SetEnabled(left > 0)
		own.forget:SetAlpha(left > 0 and 1 or E.tokens.disabledAlpha)
	elseif selected then
		form.title:SetText(BuiltInTitle(selected))
		E.UIKit.Paint(form.title, "body")
		local switch = M.db.categories[selected]
		form.builtin.text:SetText(L["A built-in section: the game's item types fill it. Your own categories come first, then the built-in sections; drop an item on its title to keep it here."])
		form.builtin.show:SetShown(switch ~= nil)
		form.builtin.show:SetChecked(switch ~= false)
	else
		form.title:SetText("")
	end
end

local function UpdateButtons()
	local rows = editor.list.data
	local at
	for index, row in ipairs(rows) do
		if row.key == selected then at = index end
	end
	local function Set(button, on)
		button:SetEnabled(on and true or false)
		button:SetAlpha(on and 1 or E.tokens.disabledAlpha)
	end
	Set(editor.up, at and at > 1)
	Set(editor.top, at and at > 1)
	Set(editor.down, at and at < #rows)
	Set(editor.delete, M:OwnCategory(selected) ~= nil)
	Set(editor.new, #M:CategoryList() < M.MAX_CATEGORIES)
end

function M:RefreshCategoryEditor()
	if not (editor and editor:IsShown()) then return end
	local rows = Rows()
	local found = false
	for _, row in ipairs(rows) do
		if row.key == selected then found = true end
	end
	if not found then selected = rows[1] and rows[1].key or nil end
	editor.list:SetData(rows, true)
	FillForm()
	UpdateButtons()
end

function M:SelectCategoryRow(key)
	selected = key
	self:RefreshCategoryEditor()
	local rows = editor.list.data
	for index, row in ipairs(rows) do
		if row.key == key then editor.list:ScrollTo(index) end
	end
end

local function Move(delta)
	if selected and M:MoveSection(selected, delta) then M:SelectCategoryRow(selected) end
end

local function CreateEditor()
	local Kit = E.UIKit
	editor = Kit.CreateToolWindow("EldoUI_BagCategories", { title = L["Bag categories"], width = 680, height = 500,
		footer = Kit.TOOL_FOOTER, resizable = { minWidth = 620, minHeight = 440 } })
	-- Ctrl-click anywhere on the window opens the Bags options.
	E:BindOptionsLink(editor, { page = "module:Bags" })
	local content = editor.content
	local listBox = CreateFrame("Frame", nil, content)
	listBox:SetPoint("TOPLEFT", 0, 0)
	listBox:SetPoint("BOTTOMLEFT", 0, 30)
	listBox:SetWidth(LIST_WIDTH)
	E:SetTemplate(listBox, true)
	editor.listBox = listBox
	editor.list = Kit.CreateList(listBox, { rowHeight = Kit.TwoLineRowHeight, create = CreateRow, update = UpdateRow })
	editor.list:SetPoint("TOPLEFT", 2, -2)
	editor.list:SetPoint("BOTTOMRIGHT", -2, 2)
	local size = E.tokens.height.button
	editor.up = Kit.IconButton(content, size, nil, function() Move(-1) end, L["Move up"], L["One place earlier in the bag window."], "chevron-up")
	editor.up:SetPoint("BOTTOMLEFT", 0, 0)
	editor.down = Kit.IconButton(content, size, nil, function() Move(1) end, L["Move down"], L["One place later in the bag window."], "chevron-down")
	editor.down:SetPoint("LEFT", editor.up, "RIGHT", 4, 0)
	editor.top = Kit.Button(content, L["To the top"], { onClick = function() Move("top") end,
		tipTitle = L["To the top"], tip = L["The first section in the bag window."] })
	editor.top:SetPoint("LEFT", editor.down, "RIGHT", 8, 0)
	editor.form = CreateForm(content)
	editor.form:SetPoint("TOPLEFT", listBox, "TOPRIGHT", 14, 0)
	editor.form:SetPoint("BOTTOMRIGHT", 0, 0)

	local footer = editor.footer
	editor.footerText:Hide()
	editor.new = Kit.Button(footer, L["New category"], { kind = "primary", onClick = function()
		local cat = M:NewCategory(L["New category"])
		if cat then M:SelectCategoryRow(M:OwnKey(cat)) end
	end })
	editor.new:SetPoint("LEFT", 12, 0)
	editor.delete = Kit.Button(footer, L["Delete"], { kind = "danger", onClick = function()
		local cat = M:OwnCategory(selected)
		if not cat then return end
		E:ShowConfirm({ title = L["Delete this category?"], text = Plain(M:CategoryName(cat)), danger = true,
			accept = L["Delete"], onAccept = function() M:DeleteCategory(cat) end })
	end })
	editor.delete:SetPoint("LEFT", editor.new, "RIGHT", 8, 0)
	editor.import = Kit.Button(footer, L["Import"], { onClick = function() E:ShowImport() end,
		tipTitle = L["Import"], tip = L["Paste a bag category string. You see what it holds before anything changes."] })
	editor.import:SetPoint("RIGHT", -28, 0)
	editor.export = Kit.Button(footer, L["Export"], { onClick = function()
		local text = M:ExportCategories()
		if text then E:ShowCopyBox(L["Bag categories"], L["Everything is selected. Press Ctrl+C and share it. It holds your own categories and the order of the sections."], text) end
	end, tipTitle = L["Export"], tip = L["Your own categories and the section order as a string to share."] })
	editor.export:SetPoint("RIGHT", editor.import, "LEFT", -8, 0)
	E:RegisterThemed(editor, function() M:RefreshCategoryEditor() end)
end

-- Opens the editor, with `key` selected when given.
function M:ShowCategoryEditor(key)
	if not self.db then return end
	if not editor then CreateEditor() end
	self:RebuildCategories()
	if key then selected = key end
	editor:Open()
	self:RefreshCategoryEditor()
	if key then self:SelectCategoryRow(key) end
end

function M:CategoryEditorWindow()
	return editor, selected
end
