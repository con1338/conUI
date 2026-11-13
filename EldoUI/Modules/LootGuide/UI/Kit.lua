-- EldoUI Loot Guide: the page kit. Every Loot Guide page builds
-- from these parts, so all pages share one look (DESIGN.md) and one way of
-- handling items:
--   Kit.Text, Kit.Button, Kit.IconButton, Kit.Divider, Kit.Chip, Kit.Tooltip
--   Kit.EmptyState    a designed "nothing here" block (icon, title, text, buttons)
--   Kit.CreateList    a virtual list (the core one, rows follow the density)
--   Kit.SectionHost   a rail of sections beside one section page (UI/Catalogue.lua)
--   Kit.CreateTable   sortable columns on top of the list (Database page)
--   Kit.ItemCell      the shared item row: icon with owned mark and quality
--                     border, name in quality color, sub-line, gain chip,
--                     drop chance or reward tag, wishlist star, dimmed when
--                     unusable; Ctrl shows the inspect cursor, Alt-click opens
--                     the item check, other modified clicks go to the game
--                     (link in chat, dress up); right-click opens the item menu
--   Kit.ItemMenu      that menu (wishlist, link, try on, plan sets, and
--                     entries pages add with LG:RegisterItemMenu)
--   Kit.LevelFit      a level-fit bar (green: right for you, yellow: a little
--                     high or low, gray: far off)
-- Colors: quality and quest difficulty come from the game; status and
-- chance colors are EldoUI's semantic ones; the accent is read when drawn.
local _, E = ...
local LG = E.LootGuide
local L = E.L

local Kit = {}
LG.Kit = Kit

-- One kit: the colors, texts, buttons, tooltips, dividers,
-- empty states, lists and tables are E.UIKit's (Core/UIKit.lua); this
-- table adds only the Loot Guide parts (density, item cell, item menu,
-- level fit, chance and level colors).
local UI = E.UIKit
Kit.TEXT = E.tokens.text.body
Kit.SECONDARY = E.tokens.text.secondary
Kit.DIM = E.tokens.text.dim
Kit.GOOD = E.tokens.text.good
Kit.WARN = E.tokens.text.warn
Kit.BAD = E.tokens.text.bad

local Secret = E.Secret

-- The client's atlases do not change in a session; asked once per name
-- (each answer is a new table, and rows ask on every draw).
local atlasKnown = {}
local function HasAtlas(name)
	local known = atlasKnown[name]
	if known == nil then
		known = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil or false
		if name ~= nil then atlasKnown[name] = known end
	end
	return known
end
Kit.HasAtlas = HasAtlas

function Kit.Accent()
	return unpack(E.media.accentColor)
end

function Kit.Hex(r, g, b)
	return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

-- Height of one list row for the density setting.
function Kit.RowHeight()
	return LG.ROW_HEIGHT[LG.db and LG.db.density or "comfortable"] or 20
end

---------------------------------------------------------------------------
-- Small parts: the core kit's, repainted on a theme change.
---------------------------------------------------------------------------
-- kind: "body" (white), "secondary" (gray), "header" (accent), "dim"
Kit.Text = UI.Text
Kit.Paint = UI.Paint
Kit.Tooltip = UI.Tooltip
Kit.TooltipHint = UI.TooltipHint
Kit.Button = UI.Button
Kit.FitButton = UI.FitButton
Kit.IconButton = UI.IconButton
Kit.RemoveButton = UI.RemoveButton
Kit.Divider = UI.Divider
Kit.Check = UI.Check
Kit.Chevron = UI.Chevron
Kit.SetGlyph = UI.SetGlyph
Kit.Icon = UI.Icon
Kit.PaintThumb = UI.PaintThumb
Kit.ScrollBar = UI.ScrollBar

-- An icon slot for an item or spell: the icon trimmed inside a 1 px
-- template box, in its own colors (no tint), with the white `hover.control`
-- overlay on hover. Use it for game icons; `Kit.IconButton` is for glyphs.
function Kit.IconSlot(parent, size, onClick, tipTitle, tipText)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(size, size)
	E:SetTemplate(button)
	local inner = E.pixel or 1
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", inner, -inner)
	icon:SetPoint("BOTTOMRIGHT", -inner, inner)
	E:TrimIcon(icon)
	button.icon = icon
	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints(icon)
	hover:SetColorTexture(1, 1, 1, E.tokens.hover.control)
	button.hover = hover
	button.plain = true
	if onClick then button:SetScript("OnClick", onClick) end
	Kit.Tooltip(button, tipTitle, tipText)
	return button
end

-- A small rounded-less box with a label ("Rare", "Quest", "Set 1").
function Kit.Chip(parent, text)
	local chip = CreateFrame("Frame", nil, parent)
	E:SetTemplate(chip, true)
	chip.text = Kit.Text(chip, 10, "CENTER", "secondary")
	chip.text:SetPoint("CENTER")
	function chip:SetLabel(label, r, g, b)
		self.text:SetText(E:Translate(label) or "")
		if r then self.text:SetTextColor(r, g, b) else Kit.Paint(self.text, "secondary") end
		self:SetSize(math.ceil(self.text:GetStringWidth()) + 10, 16)
	end
	chip:SetLabel(text)
	return chip
end

---------------------------------------------------------------------------
-- Colors
---------------------------------------------------------------------------
function Kit.QualityColor(quality)
	if type(quality) == "number" and C_Item.GetItemQualityColor then
		local r, g, b = C_Item.GetItemQualityColor(quality)
		if r then return r, g, b end
	end
	return unpack(Kit.TEXT)
end

-- The game's quest difficulty color for a level against the player's.
function Kit.LevelColor(level)
	if type(level) == "number" and GetQuestDifficultyColor then
		local color = GetQuestDifficultyColor(level)
		if color then return color.r, color.g, color.b end
	end
	return unpack(Kit.SECONDARY)
end

-- Drop chance: green from 20 %, white from 5 %, gray below.
function Kit.ChanceColor(chance)
	if type(chance) ~= "number" then return unpack(Kit.SECONDARY) end
	if chance >= 20 then return unpack(Kit.GOOD) end
	if chance >= 5 then return unpack(Kit.TEXT) end
	return unpack(Kit.SECONDARY)
end

function Kit.ChanceText(chance)
	if type(chance) ~= "number" then return end
	if chance < 0.1 then return "<0.1%" end
	if chance >= 10 or chance == math.floor(chance) then return ("%d%%"):format(math.floor(chance + 0.5)) end
	return ("%.1f%%"):format(chance)
end

---------------------------------------------------------------------------
-- Empty state: the core one with the Loot Guide icon as the default.
-- Set(title, text, icon, { { label, onClick, tip }, ... }, lines)
---------------------------------------------------------------------------
function Kit.EmptyState(parent)
	local frame = UI.EmptyState(parent)
	local set = frame.Set
	function frame:Set(title, text, icon, buttons, lines)
		return set(self, title, text, icon or LG.ICON, buttons, lines)
	end
	-- Texts are kit texts: E:RefreshTheme repaints them already.
	function frame:Restyle() end
	return frame
end

---------------------------------------------------------------------------
-- Virtual list: the core list (E.UIKit.CreateList), with the row height
-- following the Loot Guide's density setting unless the page gives one.
-- Kit.CreateList(parent, { rowHeight = n or nil (density), create = fn(row),
--   update = fn(row, item, index), gap = 0 })
-- Variable heights and row kinds: pass `height` (and `kind`) as in
-- Core/UIKit.lua; then the rows have their own heights.
-- list:SetData(items), list:Refresh(), list:ScrollTo(index)
---------------------------------------------------------------------------
local function DensityHeight()
	return Kit.RowHeight()
end

function Kit.CreateList(parent, opts)
	opts = opts or {}
	if not opts.height and opts.rowHeight == nil then opts.rowHeight = DensityHeight end
	return E.UIKit.CreateList(parent, opts)
end

---------------------------------------------------------------------------
-- Table: the core sortable table (chevron sort marks), rows following the
-- density unless the page gives a height.
---------------------------------------------------------------------------
function Kit.CreateTable(parent, columns, opts)
	opts = opts or {}
	if opts.rowHeight == nil then opts.rowHeight = DensityHeight end
	return UI.CreateTable(parent, columns, opts)
end

---------------------------------------------------------------------------
-- Item cell
-- Kit.ItemCell(parent) -> cell; Kit.SetItem(cell, data)
-- data = { itemID, link, sub = "Ras Frostwhisper", chance = 12.5, tag =
--   "Reward" | "Choice" | nil, onClick = fn(data, button) }
---------------------------------------------------------------------------
local STAR_ATLAS = "PetJournal-FavoritesIcon"
local OWNED_ATLAS = "common-icon-checkmark"
local ARROW_ATLAS = "bags-greenarrow"

local function ArrowMarkup()
	if HasAtlas(ARROW_ATLAS) and CreateAtlasMarkup then return CreateAtlasMarkup(ARROW_ATLAS, 10, 10) .. " " end
	return "+"
end

-- Does the player have the item (worn, bags, bank, an equipment set or an
-- alt; see LG:Owns)?
function Kit.Owned(itemID)
	if not itemID then return false end
	if LG.Owns then return LG:Owns(itemID) ~= nil end
	local count = C_Item.GetItemCount and C_Item.GetItemCount(itemID, true) or 0
	if Secret(count) then return false end
	if (count or 0) > 0 then return true end
	if C_Item.IsEquippedItem then
		local ok, worn = pcall(C_Item.IsEquippedItem, itemID)
		if ok and not Secret(worn) and worn then return true end
	end
	return false
end

-- Gain against what you wear, from the shared scoring engine (the same
-- number the Upgrades arrows show): "+6.2%", "+12.4 DPS" or nil.
function Kit.GainText(link)
	local engine = E.ItemScore
	if not (engine and link) then return end
	local result = engine:Rate(link)
	if not (result and result.upgrade) then return end
	if type(result.dps) == "number" then return L["+%.1f DPS"]:format(result.dps) end
	if type(result.percent) == "number" then return ("+%.1f%%"):format(result.percent) end
	return ("+%.1f"):format(result.delta or 0)
end

local function CellLink(data)
	if data.link then return data.link end
	if data.itemID then
		local _, link = C_Item.GetItemInfo(data.itemID)
		if not Secret(link) and link then return link end
		return ("item:%d"):format(data.itemID)
	end
end
Kit.CellLink = CellLink

local function UpdateCursor(cell)
	if IsControlKeyDown() then
		if ShowInspectCursor then ShowInspectCursor() end
	elseif ResetCursor then
		ResetCursor()
	end
	cell.ctrl = IsControlKeyDown()
end

function Kit.ItemCell(parent)
	local cell = CreateFrame("Button", nil, parent)
	cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	E:SkinRow(cell)
	cell.iconBox = CreateFrame("Frame", nil, cell)
	cell.iconBox:SetPoint("LEFT", 2, 0)
	E:SetTemplate(cell.iconBox)
	cell.icon = cell.iconBox:CreateTexture(nil, "ARTWORK")
	cell.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	cell.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(cell.icon)
	cell.owned = cell.iconBox:CreateTexture(nil, "OVERLAY")
	cell.owned:SetSize(10, 10)
	cell.owned:SetPoint("BOTTOMRIGHT", 2, -2)
	if HasAtlas(OWNED_ATLAS) then cell.owned:SetAtlas(OWNED_ATLAS) else cell.owned:SetColorTexture(unpack(Kit.GOOD)) end
	cell.star = cell:CreateTexture(nil, "OVERLAY")
	cell.star:SetSize(12, 12)
	if HasAtlas(STAR_ATLAS) then cell.star:SetAtlas(STAR_ATLAS) else cell.star:SetColorTexture(E:TokenColor("gold")) end
	cell.right = Kit.Text(cell, 11, "RIGHT")
	cell.right:SetPoint("RIGHT", -6, 0)
	cell.gain = Kit.Text(cell, 11, "RIGHT")
	cell.gain:SetPoint("RIGHT", cell.right, "LEFT", -8, 0)
	cell.name = Kit.Text(cell, 12, "LEFT")
	cell.name:SetWordWrap(false)
	cell.sub = Kit.Text(cell, 10, "LEFT", "secondary")
	cell.sub:SetWordWrap(false)
	cell.star:SetPoint("LEFT", cell.name, "RIGHT", 3, 0)

	cell:SetScript("OnEnter", function(self)
		local data = self.data
		if not data then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local link = CellLink(data)
		if link and link:find("|H", 1, true) then
			GameTooltip:SetHyperlink(link)
		elseif data.itemID then
			GameTooltip:SetItemByID(data.itemID)
		end
		GameTooltip:Show()
		UpdateCursor(self)
		self:SetScript("OnUpdate", function(own)
			if IsControlKeyDown() ~= own.ctrl then UpdateCursor(own) end
		end)
	end)
	cell:SetScript("OnLeave", function(self)
		self:SetScript("OnUpdate", nil)
		GameTooltip:Hide()
		if ResetCursor then ResetCursor() end
	end)
	cell:SetScript("OnClick", function(self, button)
		local data = self.data
		if not data then return end
		local link = CellLink(data)
		if button == "RightButton" then
			Kit.ItemMenu(self, data.itemID, link)
			return
		end
		if LG.IsCheckClick and LG:IsCheckClick() then
			LG:OpenCheck(link)
			return
		end
		if IsModifiedClick() and link and HandleModifiedItemClick and HandleModifiedItemClick(link) then return end
		if data.onClick then data.onClick(data, button, self) end
	end)

	function cell:Layout()
		local height = self:GetHeight()
		local size = math.max(height - 4, 12)
		self.iconBox:SetSize(size, size)
		local compact = height < 20
		self.name:ClearAllPoints()
		self.sub:ClearAllPoints()
		if compact or not self.hasSub then
			self.name:SetPoint("LEFT", self.iconBox, "RIGHT", 6, 0)
			self.name:SetPoint("RIGHT", self.gain, "LEFT", -18, 0)
			self.sub:Hide()
		else
			-- The icon and the gain sit on the row's middle: the two lines
			-- take their top and bottom from the icon's edges.
			self.name:SetPoint("TOPLEFT", self.iconBox, "TOPRIGHT", 6, 1)
			self.name:SetPoint("TOPRIGHT", self.gain, "LEFT", -18, size / 2 + 1)
			self.sub:SetPoint("BOTTOMLEFT", self.iconBox, "BOTTOMRIGHT", 6, -1)
			self.sub:SetPoint("BOTTOMRIGHT", self.gain, "LEFT", -6, -(size / 2 + 1))
			self.sub:Show()
		end
	end
	cell:SetScript("OnSizeChanged", function(self) self:Layout() end)
	return cell
end

function Kit.SetItem(cell, data)
	cell.data = data
	if not data then
		cell:Hide()
		return
	end
	local itemID = tonumber(data.itemID)
	local name, link, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(data.link or itemID)
	if Secret(name) then name, link, quality, icon = nil, nil, nil, nil end
	if not name then
		local record = LG.ItemRecord and LG:ItemRecord(itemID)
		name = record and record.name
		quality = quality or (record and record.quality)
		-- Ask for the item once; the page redraws when it arrives.
		if LG.RequestItem then LG:RequestItem(itemID) end
	end
	icon = icon or (itemID and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)) or 134400
	cell.icon:SetTexture(icon)
	cell.name:SetText(name or (itemID and ("item:" .. itemID) or "?"))
	local r, g, b = Kit.QualityColor(quality)
	cell.name:SetTextColor(r, g, b)
	if type(quality) == "number" and quality >= 2 then
		cell.iconBox:SetBackdropBorderColor(r, g, b, 1)
	else
		cell.iconBox:SetBackdropBorderColor(unpack(E.media.borderColor))
	end
	cell.owned:SetShown(Kit.Owned(itemID))
	cell.star:SetShown(LG:WishlistOn() and LG:IsWished(itemID))

	-- Usable: dimmed with a red sub-line when the player cannot use it.
	local usable = true
	if link and E.ItemScore and E.ItemScore.IsUsable then
		local ok, result = pcall(E.ItemScore.IsUsable, E.ItemScore, link)
		if ok and result == false then usable = false end
	end
	cell.icon:SetDesaturated(not usable)
	cell.icon:SetAlpha(usable and 1 or 0.6)
	local sub = data.sub
	if not usable then
		sub = Kit.Hex(unpack(Kit.BAD)) .. L["You can't use this"] .. "|r" .. (sub and sub ~= "" and ("  " .. sub) or "")
	end
	cell.sub:SetText(sub or "")
	cell.hasSub = sub ~= nil and sub ~= ""

	local gain = link and Kit.GainText(link)
	if gain and LG:BiSOn() then
		local gr, gg, gb = unpack(Kit.GOOD)
		cell.gain:SetText(ArrowMarkup() .. gain)
		cell.gain:SetTextColor(gr, gg, gb)
	else
		cell.gain:SetText("")
	end
	if data.tag then
		cell.right:SetText(data.tag)
		Kit.Paint(cell.right, "secondary")
	elseif data.chance then
		cell.right:SetText(Kit.ChanceText(data.chance) or "")
		cell.right:SetTextColor(Kit.ChanceColor(data.chance))
	else
		cell.right:SetText("")
	end
	-- "P3" before the right column for loot from a later phase.
	local badge = LG.PhaseBadge and LG:PhaseBadge(itemID)
	if badge then
		local right = cell.right:GetText() or ""
		cell.right:SetText(badge .. (right ~= "" and ("  " .. right) or ""))
	end
	cell:Layout()
	cell:Show()
end

---------------------------------------------------------------------------
-- Item menu (right-click). Pages add entries:
--   LG:RegisterItemMenu(key, fn(root, itemID, link)) -- root is E.UIKit.ContextMenu's
---------------------------------------------------------------------------
local menuEntries, menuOrder = {}, {}

function LG:RegisterItemMenu(key, fn)
	if not menuEntries[key] then table.insert(menuOrder, key) end
	menuEntries[key] = fn
end

-- Wishlist and plan sets follow their pages' switches (Wishlist off hides
-- stars and the menu entry; Best in Slot off hides sets and gain marks).
function LG:WishlistOn()
	local pagesOn = self.db and self.db.pages
	return not (type(pagesOn) == "table" and pagesOn.wishlist == false)
end

function LG:BiSOn()
	local pagesOn = self.db and self.db.pages
	return not (type(pagesOn) == "table" and pagesOn.bis == false)
end

local function InsertLink(link)
	if not link then return end
	local util = ChatFrameUtil
	if util and util.InsertLink and util.InsertLink(link) then return end
	if util and util.OpenChat then
		util.OpenChat(link)
	elseif ChatEdit_InsertLink then
		ChatEdit_InsertLink(link)
	end
end

Kit.InsertLink = InsertLink

function Kit.ItemMenu(owner, itemID, link)
	itemID = tonumber(itemID) or (link and C_Item.GetItemInfoInstant(link))
	if not itemID then return end
	E.UIKit.ContextMenu(owner, function(_, root)
		local name = C_Item.GetItemInfo(itemID)
		if Secret(name) then name = nil end
		local record = not name and LG.ItemRecord and LG:ItemRecord(itemID)
		root:CreateTitle(name or (record and record.name) or ("item:" .. itemID))
		if LG:WishlistOn() then
			if LG:IsWished(itemID) then
				root:CreateButton(L["Remove from wishlist"], function() LG:SetWished(itemID, false) end)
			else
				root:CreateButton(L["Add to wishlist"], function() LG:SetWished(itemID, true) end)
			end
		end
		local full = link and link:find("|H", 1, true) and link or select(2, C_Item.GetItemInfo(itemID))
		if not Secret(full) and full then
			root:CreateButton(L["Link in chat"], function() InsertLink(full) end)
			if DressUpItemLink and LG:ItemSlots(itemID) then
				root:CreateButton(L["Try on"], function() DressUpItemLink(full) end)
			end
		end
		if LG:BiSOn() and LG:ItemSlots(itemID) then
			local sets = LG:SetsWith(itemID)
			for index = 1, 2 do
				if not (sets and sets[index]) then
					root:CreateButton((L["Put in %s"]):format(LG:SetName(index)), function() LG:PutInSet(index, itemID) end)
				end
			end
			if sets then
				root:CreateButton(L["Remove from plan sets"], function() LG:RemoveFromSets(itemID) end)
			end
		end
		-- The QoL module's Wowhead copy box (Wowhead site setting there).
		local qol = E.modules and E.modules.QoL
		if qol and qol.ShowWowhead and qol.db then
			root:CreateButton(L["Copy Wowhead link"], function() qol.ShowWowhead("item", itemID, name or (record and record.name)) end)
		end
		for _, key in ipairs(menuOrder) do
			local ok, err = pcall(menuEntries[key], root, itemID, full or link)
			if not ok then geterrorhandler()(err) end
		end
	end)
end

-- The fixed clicks on an item row (same as Bags and Loot), for help tooltips.
function Kit.ClickHelp(tooltip)
	local r, g, b = unpack(Kit.SECONDARY)
	E.UIKit.TipTitle(tooltip, L["On an item:"])
	E:TooltipHint(tooltip, { L["Right-click"], L["wishlist, link, try on, plan sets, Wowhead link"] })
	E:TooltipHint(tooltip, { L["Shift-click"], L["link in chat"] })
	E:TooltipHint(tooltip, { L["Ctrl-click"], L["try on"] })
	local hint = LG.CheckHint and LG:CheckHint()
	if hint then tooltip:AddLine(hint, r, g, b, true) end
end

---------------------------------------------------------------------------
-- Level fit bar: where the player's level sits in a level range.
---------------------------------------------------------------------------
function Kit.LevelFit(parent, width)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetSize(width or 120, 6)
	E:SetTemplate(bar, true)
	bar.fill = bar:CreateTexture(nil, "ARTWORK")
	bar.fill:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	bar.fill:SetPoint("BOTTOMLEFT", E.pixel, E.pixel)
	E:UseBarTexture(bar.fill)
	bar.mark = bar:CreateTexture(nil, "OVERLAY")
	bar.mark:SetSize(2, 10)
	bar.mark:SetColorTexture(1, 1, 1, 1)
	-- window: levels around the range that still count as "right for you".
	function bar:SetRange(minLevel, maxLevel, level, window)
		level = level or UnitLevel("player")
		if Secret(level) or not minLevel or not maxLevel then self:Hide() return end
		window = window or 3
		local low, high = minLevel - window, maxLevel + window
		local span = math.max(high - low, 1)
		local inner = math.max((self:GetWidth() or 120) - 2 * E.pixel, 1)
		local fraction = math.max(0, math.min(1, (level - low) / span))
		self.fill:SetWidth(math.max(inner * fraction, 1))
		local r, g, b
		if level >= minLevel and level <= maxLevel then
			r, g, b = unpack(Kit.GOOD)
		elseif level >= minLevel - window and level <= maxLevel + window then
			r, g, b = unpack(Kit.WARN)
		else
			r, g, b = unpack(Kit.DIM)
		end
		self.fill:SetVertexColor(r, g, b, 1)
		self.mark:ClearAllPoints()
		self.mark:SetPoint("CENTER", self, "LEFT", E.pixel + inner * fraction, 0)
		self:Show()
	end
	return bar
end
