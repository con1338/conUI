-- EldoUI Loot Guide: the window.
--
--   +--------------------------------------------------------------+
--   | Loot Guide  For You  Journal  ...  Wishlist 3   [search] ? ⚙ x|
--   |--------------------------------------------------------------|
--   |                                                              |
--   |                  the open page (or a designed                |
--   |                  empty state)                                |
--   |                                                              |
--   |--------------------------------------------------------------|
--   | EldoUI 0.6.0 · Loot: Classic values (...) · drops seen by you  //|
--   +--------------------------------------------------------------+
--
-- 920x600 at scale 1; the corner grip makes it bigger (the pages reflow)
-- and Ctrl+mouse wheel on the top bar zooms from 70 to 150 % (the same
-- value as the Window scale option). Drag by the top bar; Esc closes; the
-- book sounds play through E:PlayMedia when Window sounds is on. The window
-- is not a layout mover: it opens at TOP 0,-140 until the player drags it,
-- and the place is kept in EldoUIDB.lootGuideCache.window. It hides when
-- combat starts and never reopens by itself.
--
-- Router: LG:Open(page, arg). With no page: inside a dungeon or raid (and
-- "Open the dungeon you are in" on) the page that knows the instance opens
-- on it; otherwise the "Open on" page, or the last one. Search, the item
-- page and the detail page have no tab (`hidden`); they open from the
-- search box, links and commands. The top-bar search box gets its quick
-- dropdown from Search.lua (LG:AttachSearchBox).
--
-- First open per character: a small card asks how to rate items (when more
-- than one rating mode exists) and which loot counts as "your list".
-- Closing it keeps Weights and the realistic list.
--
-- While My Adventure runs the window is the Journal: its title
-- reads "Journal", the hub "My Adventure" is the first tab, the dungeon
-- tab is labeled "Dungeons" (its key `journal`, routes and /eui journal
-- stay) and the footer shows the journal data line on the hub. LG:Open on
-- a hub section key (such as "attune" while it lives in the hub) opens
-- the hub on that section (LG:HubRoute, Adventure/UI/Hub.lua).
local _, E = ...
local LG = E.LootGuide
local Kit = LG.Kit
local L = E.L

local WIDTH, HEIGHT = 920, 600
local TOPBAR = 36
local FOOTER = 24
local PAD = 8
local DEFAULT_TOP = -140
local HELP_URL = "https://github.com/Eldodeldo/EldoUI/issues"
local SOUND_OPEN, SOUND_CLOSE, SOUND_PAGE = "kit:IG_SPELLBOOK_OPEN", "kit:IG_SPELLBOOK_CLOSE", "kit:IG_ABILITY_PAGE_TURN"

local window          -- the frame, built on first open
local current         -- key of the page on show
local tabs = {}       -- pool of tab buttons

local function Clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

local function Sound(id)
	if LG.db and LG.db.sounds then E:PlayMedia(id) end
end

---------------------------------------------------------------------------
-- Geometry
---------------------------------------------------------------------------
local function Scale()
	return Clamp(tonumber(LG.db and LG.db.scale) or 1, LG.SCALE_MIN, LG.SCALE_MAX)
end

-- Place the window: the saved top-left corner (in UIParent units), or the
-- default spot. Positions are kept independent of the window scale.
local function ApplyPosition()
	if not window then return end
	local scale = Scale()
	window:SetScale(scale)
	window:ClearAllPoints()
	local geo = LG:Cache().window
	if type(geo) == "table" and tonumber(geo.x) and tonumber(geo.y) then
		window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", geo.x / scale, geo.y / scale)
	else
		window:SetPoint("TOP", UIParent, "TOP", 0, DEFAULT_TOP / scale)
	end
end

local function SavePosition()
	if not window then return end
	local scale = window:GetScale()
	local left, top = window:GetLeft(), window:GetTop()
	if not left or not top then return end
	LG:Cache().window = { x = math.floor(left * scale + 0.5), y = math.floor(top * scale + 0.5) }
end

function LG:ResetWindow()
	self:Cache().window = nil
	if self.db then self.db.scale = 1 end
	if window and window.grip then window.grip:ResetSize() end
	ApplyPosition()
	if E.RefreshConfig then E:RefreshConfig() end
end

---------------------------------------------------------------------------
-- Size grip (bottom-right corner): dragging changes the window's size and
-- the open page reflows; the size is kept for the account. Ctrl+mouse
-- wheel on the top bar zooms (70 to 150 %), like every tabbed window.
---------------------------------------------------------------------------
local function CreateGrip(frame)
	return E.UIKit.SizeGrip(frame, {
		resize = true, width = WIDTH, height = HEIGHT,
		store = function() return E.UIKit.WindowSizeStore("EldoUILootGuide") end,
		tipTitle = L["Window size"],
		tip = L["Drag to make the window bigger or smaller; the content follows. Ctrl+mouse wheel on the title bar zooms."],
		onStop = function()
			SavePosition()
			ApplyPosition()
		end,
	})
end

-- One wheel step is 5 %; the top-left corner stays put.
local function Zoom(delta)
	if not (window and LG.db) then return end
	SavePosition()
	local value = Clamp(math.floor((Scale() + delta * 0.05) * 100 + 0.5) / 100, LG.SCALE_MIN, LG.SCALE_MAX)
	LG.db.scale = value
	ApplyPosition()
	if E.RefreshConfig then E:RefreshConfig() end
end

---------------------------------------------------------------------------
-- Names: "Journal" and "Dungeons" while My Adventure runs
---------------------------------------------------------------------------
local function AdventureOn()
	local A = E.Adventure
	return A and A.started and LG:GetPage("adventure") ~= nil or false
end

function LG:WindowTitle()
	return AdventureOn() and L["Journal"] or L["Loot Guide"]
end

-- The dungeon page's title follows (tab, "Open on" and help texts read it).
function LG:SyncWindowNames()
	local page = self:GetPage("journal")
	if page then
		page.baseTitle = page.baseTitle or page.title
		page.title = AdventureOn() and E.Key("Dungeons") or page.baseTitle
	end
	if window then window.title:SetText(self:WindowTitle()) end
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------
local function TabLabel(page)
	local label = page.title and L[page.title] or page.key
	if page.count then
		local ok, count = pcall(page.count)
		if ok and type(count) == "number" and count > 0 then label = ("%s " .. E:TextHex("secondary") .. "%d|r"):format(label, count) end
	end
	return label
end

local function LayoutTabs()
	if not window then return end
	LG:SyncWindowNames()
	local list = LG:Pages()
	local x = 0
	-- Seven pages fit: the padding around each label shrinks (24 down to
	-- 10 px) when the labels would run past the search box.
	local pad, minimum = 24, 64
	local room = window.tabBar:GetWidth() or 0
	if room > 0 then
		local measure = window.tabBar.measure
		if not measure then
			measure = E:CreateText(window.tabBar, E.tokens.size.body)
			measure:Hide()
			window.tabBar.measure = measure
		end
		local text = 0
		for _, page in ipairs(list) do
			measure:SetText(TabLabel(page))
			text = text + math.ceil(measure:GetStringWidth() or 60)
		end
		local spare = room - text - 2 * #list
		if #list > 0 and spare < #list * pad then
			pad = math.max(10, math.floor(spare / #list))
			minimum = 0
		end
	end
	for index, page in ipairs(list) do
		local tab = tabs[index]
		if not tab then
			tab = CreateFrame("Button", nil, window.tabBar)
			tab:SetHeight(E.tokens.height.tab)
			tab:SetScript("OnClick", function(self) LG:Open(self.pageKey) end)
			-- The skin gives the tab the theme font (and Large text) before its first text.
			E:SkinTabs({ tab }, { isSelected = function(self) return self.pageKey == current end, size = E.tokens.size.body })
			tab:SetText(" ")
			tabs[index] = tab
		end
		tab.pageKey = page.key
		tab:SetText(TabLabel(page))
		local text = tab:GetFontString()
		tab:SetWidth(math.max(minimum, math.ceil((text and text:GetStringWidth() or 60) + pad)))
		tab:ClearAllPoints()
		tab:SetPoint("LEFT", window.tabBar, "LEFT", x, 0)
		x = x + tab:GetWidth() + 2
		Kit.Tooltip(tab, page.title, page.desc)
		tab:Show()
	end
	for index = #list + 1, #tabs do tabs[index]:Hide() end
	E:UpdateTabs()
end

---------------------------------------------------------------------------
-- Footer: version and where the loot numbers come from.
---------------------------------------------------------------------------
local function FooterText()
	local parts = { ("EldoUI %s"):format(E.version or "") }
	-- The hub: which journal data this client has (Quests.lua).
	if current == "adventure" and LG.JourneyDataText then
		local ok, text = pcall(LG.JourneyDataText, LG)
		if ok and type(text) == "string" and text ~= "" then
			parts[#parts + 1] = text
			return table.concat(parts, "  ·  ")
		end
	end
	local rates = LG.db.dropRates
	parts[#parts + 1] = (L["Loot: %s"]):format(LG:DataStatusText())
	if LG:ObservedAvailable() and (rates == "seen" or rates == "both") then parts[#parts + 1] = L["drops seen by you"] end
	return table.concat(parts, "  ·  ")
end

local function UpdateFooter()
	if window then window.footerText:SetText(FooterText()) end
end

---------------------------------------------------------------------------
-- No page: only when every page is switched off (the options keep one on,
-- so this is a safety net, not a page).
---------------------------------------------------------------------------
local function ShowNoPage()
	if not window then return end
	window.empty:Set(L["No pages switched on"],
		L["Every Loot Guide page is switched off. Turn pages on in /eui > Loot Guide."], LG.ICON)
	window.empty:Show()
end

---------------------------------------------------------------------------
-- First-run card (per character)
---------------------------------------------------------------------------
local function RadioRow(parent, label, desc, onClick)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(34)
	row.box = CreateFrame("Frame", nil, row)
	row.box:SetSize(14, 14)
	row.box:SetPoint("TOPLEFT", 2, -3)
	E:SetTemplate(row.box, true)
	row.dot = row.box:CreateTexture(nil, "OVERLAY")
	row.dot:SetPoint("TOPLEFT", 3, -3)
	row.dot:SetPoint("BOTTOMRIGHT", -3, 3)
	E:AccentTexture(row.dot, 1)
	row.label = Kit.Text(row, 13, "LEFT")
	row.label:SetPoint("TOPLEFT", row.box, "TOPRIGHT", 8, 1)
	row.label:SetText(E:Translate(label))
	row.desc = Kit.Text(row, 11, "LEFT", "secondary")
	row.desc:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -2)
	row.desc:SetJustifyV("TOP")
	row.desc:SetWordWrap(true)
	row.desc:SetText(E:Translate(desc) or "")
	-- The whole description shows, wrapped over as many lines as it needs;
	-- the row grows with it. width: the row's width.
	function row:Fit(width)
		self.desc:SetWidth(math.max(width - 28, 40))
		local height = 3 + (self.label:GetStringHeight() or 13) + 2 + (self.desc:GetStringHeight() or 0) + 4
		self:SetHeight(math.max(34, math.ceil(height)))
		return self:GetHeight()
	end
	local hover = row:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	row:SetScript("OnClick", onClick)
	Kit.Tooltip(row, label, desc)
	function row:SetSelected(on) self.dot:SetShown(on and true or false) end
	return row
end

local function BuildCard()
	local shade = CreateFrame("Frame", nil, window.content)
	shade:SetAllPoints()
	shade:SetFrameLevel(window.content:GetFrameLevel() + 30)
	shade:EnableMouse(true)
	local tint = shade:CreateTexture(nil, "BACKGROUND")
	tint:SetAllPoints()
	tint:SetColorTexture(0, 0, 0, 0.55)
	local card = CreateFrame("Frame", nil, shade)
	card:SetWidth(440)
	card:SetPoint("CENTER")
	E:SetTemplate(card)
	shade.card = card

	card.title = Kit.Text(card, 16, "LEFT")
	card.title:SetPoint("TOPLEFT", 16, -14)
	card.title:SetText(L["Welcome to the Loot Guide"])
	card.close = CreateFrame("Button", nil, card, "UIPanelCloseButton")
	card.close:SetPoint("TOPRIGHT", -2, -2)
	E:SkinCloseButton(card.close)
	card.close:SetScript("OnClick", function() LG:FinishFirstRun(nil, nil) end)
	Kit.Tooltip(card.close, L["Close"], L["Keeps stat weights and the realistic loot list. You can change both later."])
	card.intro = Kit.Text(card, 12, "LEFT", "secondary")
	card.intro:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -6)
	card.intro:SetWidth(440 - 32)
	card.intro:SetJustifyV("TOP")
	card.intro:SetText(L["Two quick choices for this character. Both can be changed later."])

	card.ratingHeader = Kit.Text(card, 12, "LEFT", "header")
	card.ratingHeader:SetText(L["Rate items by"])
	card.listHeader = Kit.Text(card, 12, "LEFT", "header")
	card.listHeader:SetText(L["Your loot list"])
	card.ratingRows = {}
	card.listRows = {}
	card.listRows.realistic = RadioRow(card, L["Realistic"], L["Quest rewards, dungeon and raid drops and crafted gear."], function()
		card.list = "realistic"
		card:Update()
	end)
	card.listRows.everything = RadioRow(card, L["Everything"], L["Also rare mobs and random world drops."], function()
		card.list = "everything"
		card:Update()
	end)
	card.start = Kit.Button(card, L["Start"], 120, 24, function() LG:FinishFirstRun(card.rating, card.list) end,
		L["Start"], L["Saves your choices for this character and opens the Loot Guide."])

	function card:Layout()
		local y = -64
		local rowWidth = (self:GetWidth() or 440) - 32
		local raters = E.ItemScore and E.ItemScore:Raters() or {}
		local showRating = #raters > 1
		self.ratingHeader:SetShown(showRating)
		for _, row in pairs(self.ratingRows) do row:Hide() end
		if showRating then
			self.ratingHeader:ClearAllPoints()
			self.ratingHeader:SetPoint("TOPLEFT", 16, y)
			y = y - 20
			for _, rater in ipairs(raters) do
				local row = self.ratingRows[rater.key]
				if not row then
					row = RadioRow(self, rater.title, rater.desc, function()
						card.rating = rater.key
						card:Update()
					end)
					self.ratingRows[rater.key] = row
				end
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", 16, y)
				row:SetPoint("TOPRIGHT", self, "TOPRIGHT", -16, y)
				row:Show()
				y = y - row:Fit(rowWidth) - 2
			end
			y = y - 8
		end
		self.listHeader:ClearAllPoints()
		self.listHeader:SetPoint("TOPLEFT", 16, y)
		y = y - 20
		for _, key in ipairs({ "realistic", "everything" }) do
			local row = self.listRows[key]
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 16, y)
			row:SetPoint("TOPRIGHT", self, "TOPRIGHT", -16, y)
			y = y - row:Fit(rowWidth) - 2
		end
		self.start:ClearAllPoints()
		self.start:SetPoint("TOPRIGHT", self, "TOPRIGHT", -16, y - 8)
		self:SetHeight(-(y - 8) + 24 + 16)
	end

	function card:Update()
		for key, row in pairs(self.ratingRows) do row:SetSelected(key == self.rating) end
		for key, row in pairs(self.listRows) do row:SetSelected(key == self.list) end
	end
	return shade
end

local function ShowFirstRun()
	local data = LG:Char()
	if not data or data.firstRun then
		if window.card then window.card:Hide() end
		return
	end
	window.card = window.card or BuildCard()
	local card = window.card.card
	card.rating = E.ItemScore and E.ItemScore:GetRating() or "weights"
	card.list = data.list.preset or "realistic"
	card:Layout()
	card:Update()
	window.card:Show()
end

-- rating, list: the choices (nil = keep the defaults: weights, realistic).
function LG:FinishFirstRun(rating, list)
	local data = self:Char()
	if not data then return end
	if E.ItemScore then E.ItemScore:SetRating(rating or "weights") end
	list = self.LIST_PRESETS[list or ""] and list or "realistic"
	data.list.preset = list
	data.list.sources = CopyTable(self.LIST_PRESETS[list])
	data.firstRun = true
	if window and window.card then window.card:Hide() end
	self:Fire("list")
end

---------------------------------------------------------------------------
-- Building the window
---------------------------------------------------------------------------
local function Restyle()
	if not window then return end
	E:SetPanelTransparent(window, LG.db.transparent)
	Kit.Paint(window.title)
	Kit.Paint(window.footerText, "secondary")
	window.empty:Restyle()
	if window.card then
		local card = window.card.card
		Kit.Paint(card.title)
		Kit.Paint(card.intro, "secondary")
		Kit.Paint(card.ratingHeader, "header")
		Kit.Paint(card.listHeader, "header")
		-- A new font or text size: the rows measure their text again.
		if window.card:IsShown() then card:Layout() end
	end
	E:UpdateTabs()
end

local function BuildSearch()
	if window.search or not LG:GetPage("search") then return end
	local box = CreateFrame("EditBox", nil, window.topBar, "SearchBoxTemplate")
	E:SearchHint(box)
	box:SetSize(170, 20)
	box:SetAutoFocus(false)
	box:SetPoint("RIGHT", window.help, "LEFT", -10, 0)
	E:SkinEditBox(box)
	box:SetScript("OnEnterPressed", function(self)
		local text = strtrim(self:GetText() or "")
		self:ClearFocus()
		if LG.OpenSearchSelection and LG:OpenSearchSelection() then return end
		if text ~= "" then LG:Open("search", text) end
	end)
	Kit.Tooltip(box, L["Search"], L["Dungeons, bosses, quests, zones, mobs and items. Results show as you type; Enter opens them all."])
	window.search = box
	if LG.AttachSearchBox then LG:AttachSearchBox(box) end
end

local function BuildWindow()
	if window then return window end
	local frame = CreateFrame("Frame", "EldoUILootGuide", UIParent)
	window = frame
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:Hide()
	table.insert(UISpecialFrames, "EldoUILootGuide")
	E:SkinPanel(frame, { transparent = LG.db.transparent, accentOffset = TOPBAR })

	-- Top bar: drag handle, title, tabs, search, help, settings, close.
	local bar = CreateFrame("Frame", nil, frame)
	bar:SetPoint("TOPLEFT")
	bar:SetPoint("TOPRIGHT")
	bar:SetHeight(TOPBAR)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function() frame:StartMoving() end)
	bar:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		if frame.SetUserPlaced then pcall(frame.SetUserPlaced, frame, false) end
		SavePosition()
		ApplyPosition()
	end)
	bar:EnableMouseWheel(true)
	bar:SetScript("OnMouseWheel", function(_, delta)
		if IsControlKeyDown() then Zoom(delta) end
	end)
	frame.topBar = bar
	frame.title = Kit.Text(bar, 16, "LEFT")
	frame.title:SetPoint("LEFT", 12, 0)
	frame.title:SetText(LG:WindowTitle())

	frame.close = CreateFrame("Button", nil, bar, "UIPanelCloseButton")
	frame.close:SetPoint("RIGHT", -4, 0)
	E:SkinCloseButton(frame.close)
	frame.close:SetScript("OnClick", function() LG:Close() end)
	Kit.Tooltip(frame.close, L["Close"], L["Esc closes the window too."])
	frame.help = Kit.IconButton(bar, 22, nil, function()
		E:ShowCopyBox(L["Loot Guide help"], L["Questions, ideas or a wrong drop? Copy this address (Ctrl+C) and open it in your browser."], HELP_URL)
	end, L["Help"], function(tooltip)
		local a = LG.AccentHex()
		E.UIKit.TipText(tooltip, (L["%s/lg|r opens or closes this window."]):format(a))
		E.UIKit.TipText(tooltip, (L["%s/lg data|r shows where the loot data comes from."]):format(a))
		E.UIKit.TipText(tooltip, (L["%s/lg reset|r puts the window back."]):format(a))
		E.UIKit.TipText(tooltip, (L["%s/eui lootguide|r opens the Loot Guide settings."]):format(a))
		E.UIKit.TipText(tooltip, L["Shift-click the Loot Guide button or datatext for the page you left, even inside a dungeon."])
		if #LG:Pages() > 0 then
			tooltip:AddLine(" ")
			Kit.ClickHelp(tooltip)
		end
		tooltip:AddLine(" ")
		E:TooltipHint(tooltip, { L["Click"], L["the address to report problems"] })
	end, "?", { options = { page = "module:LootGuide" } })
	frame.help:SetPoint("RIGHT", frame.close, "LEFT", -4, 0)

	frame.tabBar = CreateFrame("Frame", nil, bar)
	frame.tabBar:SetPoint("LEFT", frame.title, "RIGHT", 16, 0)
	frame.tabBar:SetPoint("RIGHT", frame.help, "LEFT", -190, 0)
	frame.tabBar:SetHeight(24)

	-- Page area.
	frame.content = CreateFrame("Frame", nil, frame)
	frame.content:SetPoint("TOPLEFT", PAD, -(TOPBAR + PAD))
	frame.content:SetPoint("BOTTOMRIGHT", -PAD, FOOTER + 2)
	frame.empty = Kit.EmptyState(frame.content)
	frame.empty:SetFrameLevel(frame.content:GetFrameLevel() + 20)
	frame.empty:Hide()

	-- Footer.
	local footer = CreateFrame("Frame", nil, frame)
	footer:SetPoint("BOTTOMLEFT")
	footer:SetPoint("BOTTOMRIGHT")
	footer:SetHeight(FOOTER)
	local line = Kit.Divider(footer)
	line:SetPoint("TOPLEFT", PAD, 0)
	line:SetPoint("TOPRIGHT", -PAD, 0)
	frame.footerText = Kit.Text(footer, 11, "LEFT", "secondary")
	frame.footerText:SetPoint("LEFT", 12, 0)
	frame.footerText:SetPoint("RIGHT", -28, 0)
	frame.footerText:SetWordWrap(false)
	frame.footer = footer
	frame.grip = CreateGrip(frame)
	frame.grip:Restore()

	frame:SetScript("OnShow", function()
		Sound(SOUND_OPEN)
	end)
	frame:SetScript("OnHide", function()
		Sound(SOUND_CLOSE)
		local page = current and LG:GetPage(current)
		if page and page.frame and page.hide then pcall(page.hide, page.frame) end
		if LG.CancelItemRequests then LG:CancelItemRequests() end
	end)

	BuildSearch()
	-- Keys: Ctrl+F to the search box, Esc clears a search before it closes
	-- the window, Ctrl+Tab and Ctrl+Shift+Tab switch pages.
	local UI = E.UIKit
	if UI and UI.WindowKeys then
		UI.WindowKeys(frame, { search = function() return frame.search end, handle = function(name)
			local step = (name == "CTRL-TAB" and 1) or (name == "CTRL-SHIFT-TAB" and -1)
			if not step then return false end
			local list = LG:Pages()
			if #list < 2 then return false end
			local at = 0
			for index, page in ipairs(list) do
				if page.key == current then at = index end
			end
			local target = (at == 0 and step < 0) and list[#list] or list[(at - 1 + step) % #list + 1]
			LG:Open(target.key)
			return true
		end })
	end
	ApplyPosition()
	Restyle()
	return frame
end

---------------------------------------------------------------------------
-- Pages on show
---------------------------------------------------------------------------
local function UpdateEmpty(page)
	local empty = window.empty
	if not (page and page.empty and page.frame) then
		empty:Hide()
		return
	end
	local ok, title, text, icon, buttons = pcall(page.empty, page.frame)
	if ok and title then
		empty:Set(title, text, icon, buttons)
		empty:Show()
	else
		empty:Hide()
	end
end

local function ShowPage(key, arg)
	local page = key and LG:GetPage(key)
	for _, other in ipairs(LG:Pages(true, true)) do
		if other.frame and other ~= page then
			if other.frame:IsShown() and other.hide then pcall(other.hide, other.frame) end
			other.frame:Hide()
		end
	end
	if not page then
		current = nil
		ShowNoPage()
		E:UpdateTabs()
		return
	end
	if not page.frame then
		local ok, frame = pcall(page.create, window.content)
		if not ok or type(frame) ~= "table" then
			geterrorhandler()(("EldoUI Loot Guide page %s failed to build: %s"):format(key, tostring(frame)))
			return
		end
		page.frame = frame
		if frame:GetNumPoints() == 0 then frame:SetAllPoints(window.content) end
	end
	if current and current ~= key and window:IsShown() then Sound(SOUND_PAGE) end
	current = key
	LG:UI().lastPage = key
	page.frame:Show()
	if page.show then
		local ok, err = pcall(page.show, page.frame, arg)
		if not ok then geterrorhandler()(err) end
	end
	UpdateEmpty(page)
	UpdateFooter()
	E:UpdateTabs()
end

-- Which page and argument an open without a page means.
function LG:DefaultRoute()
	if self.db.autoOpen and GetInstanceInfo then
		local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
		if (instanceType == "party" or instanceType == "raid") and not (issecretvalue and issecretvalue(instanceID)) then
			for _, page in ipairs(self:Pages()) do
				if page.instanceRoute then
					local ok, arg = pcall(page.instanceRoute, instanceID)
					if ok and arg then return page.key, arg end
				end
			end
		end
	end
	return self:StartPage()
end

function LG:IsOpen()
	return window ~= nil and window:IsShown()
end

function LG:CurrentPage()
	return current
end

-- The window frame (nil before the first open) and a page's tab (tours).
function LG:WindowFrame()
	return window
end

-- What a button did: a toast in the open window (the warn bar for a
-- problem), a chat line while the window is closed.
function LG:Notify(text, warn)
	if window and window:IsShown() then
		E.UIKit.Toast(window, text, { warn = warn })
	else
		E:Print(text)
	end
end

function LG:TabButton(key)
	for _, tab in ipairs(tabs) do
		if tab:IsShown() and tab.pageKey == key then return tab end
	end
end

function LG:FirstRunShown()
	return window ~= nil and window.card ~= nil and window.card:IsShown()
end

-- True until the player answered the first-run card (it shows on the
-- next open, after the page is drawn).
function LG:FirstRunPending()
	local data = self:Char()
	return data ~= nil and not data.firstRun
end

-- Open the window on a page (or the default route). Not in combat: the
-- window hides when combat starts and opens only when the player asks.
function LG:Open(key, arg)
	if not self.active then return end
	if InCombatLockdown() then
		E:Print(L["The Loot Guide opens out of combat."])
		return
	end
	if self.LoadData then self:LoadData() end
	BuildWindow()
	BuildSearch()
	if not key then key, arg = self:DefaultRoute() end
	-- A hub section with no tab of its own (Attunements inside My Adventure).
	if key and not self:GetPage(key) and self.HubRoute then
		local hub, hubArg = self:HubRoute(key, arg)
		if hub then key, arg = hub, hubArg end
	end
	if key and not self:IsPageOn(key) then key, arg = self:StartPage(), nil end
	LayoutTabs()
	UpdateFooter()
	if not window:IsShown() then E:SlideIn(window, "DOWN") end
	ShowPage(key, arg)
	ShowFirstRun()
end

function LG:Close()
	if window and window:IsShown() then E:SlideOut(window, "DOWN") end
end

function LG:Toggle()
	if self:IsOpen() then self:Close() else self:Open() end
end

---------------------------------------------------------------------------
-- Settings, messages, combat
---------------------------------------------------------------------------
function LG:ApplyWindowSettings()
	if not window then return end
	ApplyPosition()
	Restyle()
	LayoutTabs()
	UpdateFooter()
	if window:IsShown() then
		if current and not self:IsPageOn(current) then
			ShowPage(self:StartPage())
		elseif not current then
			ShowPage(self:StartPage())
		end
	end
end

LG:On("window", function(changed)
	if not window or not window:IsShown() then return end
	if changed.pages or changed.settings then
		BuildSearch()
		LayoutTabs()
		if not current and #LG:Pages() > 0 then ShowPage(LG:StartPage()) end
	elseif changed.wishlist then
		LayoutTabs()
	end
	if changed.data or changed.settings then UpdateFooter() end
	if not current then return end
	local page = LG:GetPage(current)
	if page and page.frame and page.refresh then
		local ok, err = pcall(page.refresh, page.frame, changed)
		if not ok then geterrorhandler()(err) end
	end
	UpdateEmpty(page)
end)

LG:Listen("PLAYER_REGEN_DISABLED", "window", function()
	if window and window:IsShown() then window:Hide() end
end)

function LG:OnEnableWindow()
	if window then Restyle() end
end

function LG:OnDisableWindow()
	if window then window:Hide() end
end
