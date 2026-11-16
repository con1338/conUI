-- EldoUI Finder: the search box.
--
--   +------------------------------------------------------+
--   | Find  [ mount_                                   ]  x |
--   |======================================================|
--   | [i] Swift Gryphon                            Mount   |
--   | [i] Mounts                                   Panel   |
--   |------------------------------------------------------|
--   | Enter: open or use  Shift+Enter: second  Right: pin  |
--   +------------------------------------------------------+
--
-- An E.WindowKit window on the mover EldoUI_Finder (upper center in every
-- layout). The rows are plain buttons. A result that uses something gets
-- a secure action button laid over its row, set out of combat: the
-- player's click on it is the action. Enter on such a result leaves the
-- search box and binds Enter to that button while the box is open, so the
-- next Enter press uses it (one press, one action). Combat start takes the
-- secure buttons and the Enter binding away; the box then shows only
-- results that need no secure button.
local _, E = ...
local L = E.L
local M = E.Finder
local Kit = E.UIKit
local WKit = E.WindowKit

local MOVER = "EldoUI_Finder"
local HEADER, FOOTER = 34, 22
local CHROME = 8 + HEADER + 16 + 12 + FOOTER + 8 -- window height without the list
local SECURE_ATTRS = { "spell", "item", "toy", "macro" }

local win, anchor, dim, toggleButton, bindOwner
local results = {}
local selected = 1
local armed       -- the secure button Enter is bound to

local function DB() return M.db end

local function MaxRows()
	return math.max(3, math.min(20, tonumber(DB().results) or 8))
end

local function RowHeight()
	return math.max(18, math.min(48, tonumber(DB().rowHeight) or 28))
end

local function WindowWidth()
	return math.max(360, math.min(1000, tonumber(DB().width) or 560))
end

local function AnchorHeight()
	return CHROME + MaxRows() * RowHeight()
end

---------------------------------------------------------------------------
-- Secure buttons
---------------------------------------------------------------------------
-- The holder and the binding owner are secure state frames: the game hides
-- the holder and drops the Enter binding itself when combat starts, so
-- EldoUI never touches a protected frame in combat.
local secureHolder
local secureButtons = {}

local function Disarm()
	armed = nil
	if bindOwner and not InCombatLockdown() then ClearOverrideBindings(bindOwner) end
end

local function UseDown()
	if C_CVar and C_CVar.GetCVarBool then return C_CVar.GetCVarBool("ActionButtonUseKeyDown") and true or false end
	return false
end

local function Holder()
	if secureHolder then return secureHolder end
	secureHolder = CreateFrame("Frame", "EldoUIFinderSecure", UIParent, "SecureHandlerStateTemplate")
	secureHolder:SetAllPoints(UIParent)
	secureHolder:SetFrameStrata("DIALOG")
	RegisterStateDriver(secureHolder, "visibility", "[combat] hide; show")
	return secureHolder
end
M.SecureHolder = Holder

local function SecureButton(slot)
	local button = secureButtons[slot]
	if button then return button end
	button = CreateFrame("Button", "EldoUIFinderUse" .. slot, Holder(), "SecureActionButtonTemplate")
	button:RegisterForClicks("LeftButtonUp", "LeftButtonDown", "RightButtonUp")
	button:SetFrameStrata("DIALOG")
	button:Hide()
	-- After the game ran the action (the click edge the game uses), the
	-- result counts as recent and the box closes. Right-click pins.
	button:SetScript("PostClick", function(self, mouse, down)
		local entry = self.entry
		if not entry then return end
		if mouse == "RightButton" then
			if not down then M:PinEntry(entry) end
			return
		end
		if (down and true or false) ~= UseDown() then return end
		M:Remember(entry)
		M:Close()
	end)
	button:SetScript("OnEnter", function(self)
		if self.row and self.row.index then M:Select(self.row.index) end
	end)
	secureButtons[slot] = button
	return button
end

local function ClearSecure(button)
	button:Hide()
	button:ClearAllPoints()
	button.entry, button.row = nil, nil
	button:SetAttribute("type", nil)
	button:SetAttribute("type1", nil)
	for _, key in ipairs(SECURE_ATTRS) do button:SetAttribute(key, nil) end
end

-- Lay a secure button over every shown row that uses something (out of
-- combat only).
local function PlaceSecure()
	if InCombatLockdown() then return end
	for _, button in pairs(secureButtons) do ClearSecure(button) end
	if not (win and win:IsShown() and win.list) then return end
	for slot, row in ipairs(win.list:ShownRows()) do
		local entry = row.item
		if entry and entry.secure then
			local button = SecureButton(slot)
			button.entry, button.row = entry, row
			button:SetAttribute("type1", entry.secure.type)
			for _, key in ipairs(SECURE_ATTRS) do button:SetAttribute(key, entry.secure[key]) end
			button:SetAllPoints(row)
			button:SetFrameLevel(row:GetFrameLevel() + 5)
			button:Show()
		end
	end
end

-- Combat start: the holder hides itself (state driver) and the binding
-- owner clears its Enter binding in its own secure snippet; here only the
-- state of the box is forgotten.
local function DropSecure()
	armed = nil
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function PaintSelection()
	if not (win and win.list) then return end
	for _, row in ipairs(win.list.rows) do
		if row:IsShown() and row.index == selected then
			local r, g, b = Kit.Accent()
			row.select:SetColorTexture(r, g, b, E.tokens.pressed)
			row.select:Show()
		elseif row.select then
			row.select:Hide()
		end
	end
end

local function CreateRow(row)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	E:SkinRow(row)
	row.select = row:CreateTexture(nil, "BACKGROUND", nil, -5)
	row.select:SetAllPoints()
	row.select:Hide()
	row.iconBox = CreateFrame("Frame", nil, row)
	E:SetTemplate(row.iconBox)
	row.icon = row.iconBox:CreateTexture(nil, "ARTWORK")
	row.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	row.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(row.icon)
	row.kindText = Kit.Text(row, E.tokens.size.small, "RIGHT", "secondary")
	row.kindText:SetPoint("RIGHT", -8, 0)
	row.text = Kit.Text(row, E.tokens.size.body, "LEFT")
	row.text:SetWordWrap(false)
	row.sub = Kit.Text(row, E.tokens.size.small, "LEFT", "secondary")
	row.sub:SetWordWrap(false)
	row:SetScript("OnClick", function(self, mouse)
		if not self.item then return end
		if mouse == "RightButton" then
			M:PinEntry(self.item)
		else
			M:Activate(self.index, IsShiftKeyDown())
		end
	end)
	row:SetScript("OnEnter", function(self) if self.index then M:Select(self.index) end end)
end

local function UpdateRow(row, entry, index)
	local db = DB()
	local height = RowHeight()
	local iconSize = height - 6
	row.iconBox:SetShown(db.icons)
	row.iconBox:ClearAllPoints()
	row.iconBox:SetPoint("LEFT", 4, 0)
	row.iconBox:SetSize(iconSize, iconSize)
	row.icon:SetTexture(E:ClientIcon(entry.icon, "Interface\\Icons\\INV_Misc_QuestionMark"))
	local left = db.icons and (iconSize + 12) or 8
	local label = M:KindLabel(entry.kind)
	if db.pinned[entry.id] then label = L["Pinned"] .. "  " .. label end
	row.kindText:SetText(db.kindLabels and label or (db.pinned[entry.id] and L["Pinned"] or ""))
	row.text:ClearAllPoints()
	row.sub:ClearAllPoints()
	local showSub = db.subtitles and entry.sub and entry.sub ~= ""
	E:SetFont(row.text, math.max(11, math.min(18, height <= 22 and 12 or E.tokens.size.body)))
	row.text:SetText(entry.text)
	row.sub:SetText(showSub and entry.sub or "")
	-- Two lines meet at the row's middle, where the kind label sits.
	if showSub and height >= 30 then
		row.text:SetPoint("BOTTOMLEFT", row, "LEFT", left, 1)
		row.text:SetPoint("BOTTOMRIGHT", row.kindText, "LEFT", -8, 1)
		row.sub:SetPoint("TOPLEFT", row, "LEFT", left, -1)
		row.sub:SetPoint("TOPRIGHT", row.kindText, "LEFT", -8, -1)
	else
		row.text:SetPoint("LEFT", left, 0)
		row.text:SetPoint("RIGHT", row.kindText, "LEFT", -8, 0)
		if showSub then row.sub:SetPoint("LEFT", row.text, "RIGHT", 8, 0) end
		row.sub:SetPoint("RIGHT", row.kindText, "LEFT", -8, 0)
	end
	row.index = index
	if index == selected then
		local r, g, b = Kit.Accent()
		row.select:SetColorTexture(r, g, b, E.tokens.pressed)
		row.select:Show()
	else
		row.select:Hide()
	end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function Hint()
	local entry = results[selected]
	if armed and entry then return L["Press Enter again to use %s. Esc closes."]:format(entry.text) end
	if InCombatLockdown() then return L["In combat: only results that need no secure click."] end
	if entry and entry.second then
		return L["Enter: open   Shift+Enter: %s   Right-click: pin"]:format(entry.second.label or entry.second[1] or "")
	end
	return L["Enter: open or use   Up and down: pick   Right-click: pin"]
end

local function UpdateFooter()
	if win then win.hint:SetText(Hint()) end
end

local function Layout()
	if not win then return end
	local count = math.max(#results, 2)
	count = math.min(count, MaxRows())
	win:SetWidth(WindowWidth())
	win:SetHeight(CHROME + count * RowHeight())
	if anchor then anchor:SetSize(WindowWidth(), AnchorHeight()) end
end

function M:Refresh()
	if not (win and win:IsShown()) then return end
	results = self:Search(win.box:GetText())
	if selected > #results then selected = math.max(#results, 1) end
	Layout()
	win.list:SetData(results)
	local text = strtrim(win.box:GetText() or "")
	if #results == 0 then
		win.empty:SetText(text == "" and L["Type to search. Pinned and recent results show here."] or L["Nothing found."])
		win.empty:Show()
	else
		win.empty:Hide()
	end
	Disarm()
	PlaceSecure()
	UpdateFooter()
end

function M:Select(index)
	if index < 1 or index > #results then return end
	if index ~= selected then Disarm() end
	selected = index
	if win and win.list then win.list:ScrollTo(index) end
	PaintSelection()
	UpdateFooter()
end

-- Enter or a click on a row. Secure results are used by their own button.
function M:Activate(index, second)
	local entry = results[index or selected]
	if not entry then return false end
	if second then
		if entry.second then
			self:Run(entry, true)
			self:Close()
			return true
		end
		return false
	end
	if entry.secure then
		if InCombatLockdown() then return false end
		-- Enter: bind it to the secure button; the next press uses it.
		local button
		for _, b in pairs(secureButtons) do
			if b.entry == entry and b:IsShown() then button = b end
		end
		if not button then return false end
		win.box:ClearFocus()
		ClearOverrideBindings(bindOwner)
		SetOverrideBindingClick(bindOwner, true, "ENTER", button:GetName(), "LeftButton")
		SetOverrideBindingClick(bindOwner, true, "NUMPADENTER", button:GetName(), "LeftButton")
		armed = button
		UpdateFooter()
		return true
	end
	local ok = self:Run(entry)
	if ok then self:Close() end
	return ok
end

function M:PinEntry(entry)
	local on = self:TogglePin(entry)
	if win then
		Kit.Toast(win, (on and L["%s pinned: it shows first."] or L["%s unpinned."]):format(entry.text), { anchor = win.footer, point = "TOP", y = 4 })
	end
	self:Refresh()
end

local function ApplyLook()
	if not win then return end
	local db = DB()
	if db.panelStyle ~= "theme" and E.artStyles and E.artStyles[db.panelStyle] then
		E:PaintArtStyleSample(win, db.panelStyle)
	else
		E:SetPanelTemplate(win, db.transparent)
	end
	E:SetFont(win.box, math.max(12, math.min(24, tonumber(db.fontSize) or 16)))
	if win.list then win.list:Refresh() end
	Layout()
end

local function CreateWindow()
	if win then return win end
	win = WKit.CreateWindow("EldoUIFinder", { width = WindowWidth(), height = CHROME + 2 * RowHeight(), headerHeight = HEADER, footer = FOOTER, strata = "DIALOG", dialog = false, options = { page = "module:Finder" } })
	-- The mover places it; no dragging the window itself.
	win:SetMovable(false)
	win:SetScript("OnDragStart", nil)
	win:SetScript("OnDragStop", nil)
	win.header:SetScript("OnDragStart", nil)
	win.header:SetScript("OnDragStop", nil)
	win:SetTitle(L["Find"])
	win.title:ClearAllPoints()
	win.title:SetPoint("LEFT", win.header, "LEFT", 0, 0)
	E:SetHeaderFont(win.title, E.tokens.size.dialogTitle)

	local box = CreateFrame("EditBox", "EldoUIFinderBox", win.header, "InputBoxTemplate")
	box:SetHeight(24)
	box:SetAutoFocus(false)
	box:SetPoint("LEFT", win.title, "RIGHT", 14, 0)
	box:SetPoint("RIGHT", win.header, "RIGHT", -32, 0)
	E:SkinEditBox(box)
	box:SetScript("OnTextChanged", function(_, user)
		if user then selected = 1 end
		M:Refresh()
	end)
	box:SetScript("OnEnterPressed", function() M:Activate(selected, IsShiftKeyDown()) end)
	box:SetScript("OnEscapePressed", function() M:Close() end)
	box:SetScript("OnArrowPressed", function(_, key)
		if key == "UP" then M:Select(selected - 1) elseif key == "DOWN" then M:Select(selected + 1) end
	end)
	box:SetScript("OnTabPressed", function()
		M:Select(IsShiftKeyDown() and selected - 1 or (selected % math.max(#results, 1)) + 1)
	end)
	Kit.Tooltip(box, L["Find"], L["Panels, settings, mounts, toys, items, macros, places and EldoUI commands. Start with = for a sum."])
	win.box = box

	win.list = Kit.CreateList(win.content, { rowHeight = RowHeight, create = CreateRow, update = UpdateRow })
	win.list:SetAllPoints(win.content)
	win.empty = Kit.Text(win.content, E.tokens.size.body, "CENTER", "secondary")
	win.empty:SetPoint("CENTER")
	win.hint = Kit.Text(win.footer, E.tokens.size.small, "LEFT", "secondary")
	win.hint:SetPoint("LEFT", 4, -2)
	win.hint:SetPoint("RIGHT", -16, -2)
	win.hint:SetWordWrap(false)

	-- Everything secure is re-laid when the list scrolls.
	hooksecurefunc(win.list, "Refresh", function() if win:IsShown() then PlaceSecure() end end)
	win:HookScript("OnShow", function()
		if anchor then anchor:Show() end
		if dim and DB().dim then dim:Show() end
	end)
	win:HookScript("OnHide", function()
		if anchor then anchor:Hide() end
		if dim then dim:Hide() end
		Disarm()
		if not InCombatLockdown() then
			for _, button in pairs(secureButtons) do ClearSecure(button) end
		end
	end)
	-- Spotlight style: the screen dims behind the box.
	dim = CreateFrame("Frame", nil, UIParent)
	dim:SetAllPoints(UIParent)
	dim:SetFrameStrata("DIALOG")
	dim:SetFrameLevel(math.max(win:GetFrameLevel() - 2, 0))
	dim.tex = dim:CreateTexture(nil, "BACKGROUND")
	dim.tex:SetAllPoints()
	-- The inset shade token, a little stronger over the whole screen.
	local shade = E.tokens.inset
	dim.tex:SetColorTexture(shade[1], shade[2], shade[3], math.min(1, (shade[4] or 0.25) + 0.1))
	dim:EnableMouse(true)
	dim:SetScript("OnMouseDown", function() M:Close() end)
	dim:Hide()
	ApplyLook()
	return win
end

function M:EnsureMover()
	if anchor then return anchor end
	anchor = CreateFrame("Frame", "EldoUI_FinderAnchor", UIParent)
	anchor:SetSize(WindowWidth(), AnchorHeight())
	-- Hidden while the box is closed, so it never covers anything.
	anchor:Hide()
	self.mover = E:CreateMover(anchor, MOVER, L["Finder"], { "TOP", "UIParent", "TOP", 0, -140 }, {
		sample = false,
		onMoved = function() M:ApplyPosition() end,
	})
	return anchor
end

function M:ApplyPosition()
	if not (win and anchor) then return end
	win:ClearAllPoints()
	win:SetPoint("TOP", anchor, "TOP", 0, 0)
end

function M:Open(text)
	if not self.active then return false end
	self:EnsureMover()
	CreateWindow()
	self:ApplyPosition()
	self:BuildIndex()
	selected = 1
	if not win:IsShown() then E:SlideIn(win, "DOWN") end
	win.box:SetText(text or "")
	win.box:SetFocus()
	self:Refresh()
	return true
end

function M:Close()
	Disarm()
	if win and win:IsShown() then win:Hide() end
end

function M:Toggle(text)
	if win and win:IsShown() then self:Close() else self:Open(text) end
end

function M:IsOpen()
	return win ~= nil and win:IsShown()
end

-- For plugins.
function M:Window() return win end
function M:Results() return results end
function M:Armed() return armed end
function M:SecureButtons() return secureButtons end

---------------------------------------------------------------------------
-- The key: an override binding on a plain button, set out of combat.
---------------------------------------------------------------------------
function M:ApplyKey()
	if not toggleButton then
		toggleButton = CreateFrame("Button", "EldoUIFinderToggle", UIParent)
		toggleButton:SetScript("OnClick", function() M:Toggle() end)
		bindOwner = CreateFrame("Frame", "EldoUIFinderBindings", UIParent, "SecureHandlerStateTemplate")
		bindOwner:SetAttribute("_onstate-combat", "if newstate == 'on' then self:ClearBindings() end")
		RegisterStateDriver(bindOwner, "combat", "[combat] on; off")
	end
	E:RunOutOfCombat(function()
		ClearOverrideBindings(toggleButton)
		local key = M.active and DB().key or ""
		if type(key) == "string" and key ~= "" then
			SetOverrideBindingClick(toggleButton, false, key, "EldoUIFinderToggle")
		end
	end)
end

function M:OnEnable()
	self:EnsureMover()
	self:ApplyKey()
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
		DropSecure()
		-- The lockdown starts after this event: redraw on the next frame, so
		-- the list drops the results that need a secure click.
		C_Timer.After(0, function()
			if M.active and M:IsOpen() then M:Refresh() end
		end)
	end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if M:IsOpen() then M:Refresh() end
	end)
end

function M:OnDisable()
	self:Close()
	self:ApplyKey()
end

function M:OnProfileChanged()
	if not self.active then return end
	self.index = nil
	ApplyLook()
	self:ApplyKey()
	if self:IsOpen() then
		self:BuildIndex()
		self:Refresh()
	end
end

E:AddCommand("go", "[text]  open the Finder search box (panels, settings, mounts, toys, items, macros, places)", function(rest)
	if not M.active then
		E:Print(E:ModuleOffHint("Finder"))
		return
	end
	M:Open(rest and strtrim(rest) or "")
end, "Tools")
