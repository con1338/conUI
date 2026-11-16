-- EldoUI Party Quests: the panel.
--
-- A small panel (mover EldoUI_PartyQuests) while you are in a group: a
-- section per kind of card (Shared, Only mine, Only theirs) and one card
-- per quest with each member's progress, a bar of your own, and the Share
-- or Ask button. Rows are a UIKit virtual list (no Blizzard scroll bar).
--
-- Looks (the style presets): cards (boxed cards with bars), list (one line
-- a quest), tracker (no panel, like the objective tracker), bronze (cards
-- in a bronze frame) and minimal (no panel, one line a quest, no bars).
-- Colors come from the tokens and the accent, read when drawn.
local _, E = ...
local L = E.L
local Key = E.Key
local PQ = E:GetModule("PartyQuests")
local UI = E.UIKit

local WIDTH, HEIGHT = 260, 240
local HEADER = 24
local PAD = 6

function PQ.BronzeColor()
	if E:SkinFlag("bronze") then return E:SkinBronze() end
	-- EldoUI's named Bronze accent (the palette token).
	return unpack(E.tokens.palette.bronze)
end

local function EdgeColor(look)
	if look == "bronze" then return PQ.BronzeColor() end
	return UI.Accent()
end

PQ.LOOK_TITLE = {
	cards = Key("Cards"),
	list = Key("Compact list"),
	tracker = Key("Tracker-style"),
	bronze = Key("Forever bronze"),
	minimal = Key("Minimal"),
}

PQ.GROUP_TITLE = E:TranslateValues({
	shared = E.Key("Shared"),
	mine = E.Key("Only mine"),
	theirs = E.Key("Only theirs"),
})

local GROUP_OPTION = { shared = "showShared", mine = "showMine", theirs = "showTheirs" }
local GROUP_ORDER = { "shared", "mine", "theirs" }

local function Boxed(look)
	return look == "cards" or look == "bronze"
end

local function TwoLines(look)
	return look == "cards" or look == "bronze" or look == "tracker"
end

---------------------------------------------------------------------------
-- Text of a card
---------------------------------------------------------------------------
local function Count(done, total, complete)
	if complete then return E:TokenHex(E.tokens.text.good) .. L["done"] .. "|r" end
	if total and total > 0 then return ("%d/%d"):format(done or 0, total) end
	return nil
end

-- "You 3/10  Mira 6/10  Joe done"; a member without sync shows the name only.
function PQ.MembersText(card)
	local parts = {}
	if card.mine then
		parts[#parts + 1] = L["You"] .. (Count(card.mine.done, card.mine.total, card.mine.complete) and (" " .. Count(card.mine.done, card.mine.total, card.mine.complete)) or "")
	end
	for _, member in ipairs(card.members) do
		local count = member.synced and Count(member.done, member.total, member.complete)
		if count then
			parts[#parts + 1] = member.name .. " " .. count
		else
			parts[#parts + 1] = member.name
		end
	end
	return table.concat(parts, "   ")
end

function PQ.CardTitle(card)
	local level = card.level and card.level > 0 and ("[%d] "):format(card.level) or ""
	return level .. (card.title or L["Quest %d"]:format(card.id))
end

-- What the card's button does: "share", "ask" or nil.
function PQ.CardAction(card, group)
	if group == "theirs" then
		return #card.members > 0 and "ask" or nil
	end
	return card.pushable and "share" or nil
end

---------------------------------------------------------------------------
-- The rows
---------------------------------------------------------------------------
function PQ:Items()
	local items = {}
	local cache = self.cache or {}
	for _, group in ipairs(GROUP_ORDER) do
		local list = cache[group] or {}
		if self.db[GROUP_OPTION[group]] and #list > 0 then
			items[#items + 1] = { kind = "section", group = group, count = #list }
			for _, card in ipairs(list) do
				items[#items + 1] = { kind = "card", group = group, card = card }
			end
		end
	end
	return items
end

local function RowHeight(item)
	local db = PQ.db
	local size = db.fontSize
	if item.kind == "section" then return size + 10 end
	local look = db.look
	if TwoLines(look) then
		local height = size * 2 + 14
		if db.bars and Boxed(look) and item.card.mine then height = height + 6 end
		return height
	end
	return size + 10
end

-- Ctrl-click on a card or its button opens the Party Quests options.
local PANEL_LINK = { page = "module:PartyQuests" }

local function OnActionClick(button, mouse)
	if E:IsOptionsLinkClick(button, mouse) then return end
	local row = button:GetParent()
	local item = row and row.item
	if not item or item.kind ~= "card" then return end
	local card = item.card
	if button.action == "share" then
		PQ:Share(card.id)
	elseif button.action == "ask" then
		local member = card.members[1]
		if member and PQ:Ask(card.id, member.key) then
			UI.Toast(PQ.frame, L["Asked %s to share %s."]:format(member.name, card.title or ""))
		end
	end
end

local function CardTooltip(tooltip, card, group)
	local sr, sg, sb = unpack(E.tokens.text.secondary)
	E.UIKit.TipTitle(tooltip, PQ.CardTitle(card))
	tooltip:AddLine(PQ.GROUP_TITLE[group], sr, sg, sb)
	if card.mine then
		tooltip:AddDoubleLine(L["You"], Count(card.mine.done, card.mine.total, card.mine.complete) or "", 1, 1, 1, 1, 1, 1)
	end
	for _, member in ipairs(card.members) do
		local right = member.synced and Count(member.done, member.total, member.complete) or L["on the quest"]
		tooltip:AddDoubleLine(member.name, right, 1, 1, 1, sr, sg, sb)
	end
	if not PQ.db.sync then
		tooltip:AddLine(" ")
		tooltip:AddLine(L["Turn on Sync with group to see how far the others are."], sr, sg, sb, true)
	end
end

local function CreateRow(row, kind)
	row:EnableMouse(true)
	if kind == "section" then
		row.label = UI.Text(row, PQ.db.fontSize, "LEFT", "header")
		row.label:SetPoint("LEFT", PAD, 0)
		row.label:SetPoint("RIGHT", -PAD, 0)
		return
	end
	row.box = CreateFrame("Frame", nil, row)
	row.box:SetPoint("TOPLEFT", PAD, -2)
	row.box:SetPoint("BOTTOMRIGHT", -PAD, 2)
	E:SetTemplate(row.box, true)
	row.box:SetFrameLevel(math.max(row:GetFrameLevel() - 1, 0))
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetPoint("TOPLEFT", row.box)
	row.hover:SetPoint("BOTTOMRIGHT", row.box)
	row.hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	row.title = UI.Text(row, PQ.db.fontSize, "LEFT")
	row.title:SetWordWrap(false)
	row.members = UI.Text(row, PQ.db.fontSize - 1, "LEFT", "secondary")
	row.members:SetWordWrap(false)
	row.bar = E:CreateStatusBar(row)
	row.bar:SetHeight(3)
	row.bar:SetMinMaxValues(0, 1)
	row.action = UI.Button(row, "", 46, 18, OnActionClick)
	row:SetScript("OnEnter", function(self)
		if not (self.item and self.item.card) then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		CardTooltip(GameTooltip, self.item.card, self.item.group)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	E:BindOptionsLink(row, PANEL_LINK)
	E:BindOptionsLink(row.action, PANEL_LINK)
end

local function UpdateRow(row, item, _, kind)
	local db = PQ.db
	local size = db.fontSize
	local look = db.look
	if kind == "section" then
		E:SetFont(row.label, size)
		row.label:SetTextColor(EdgeColor(look))
		row.label:SetText(("%s (%d)"):format(PQ.GROUP_TITLE[item.group], item.count))
		return
	end
	local card = item.card
	E:SetFont(row.title, size)
	E:SetNameTextFont(row.members, math.max(size - 1, 9))
	local boxed = Boxed(look)
	row.box:SetShown(boxed)
	if boxed then
		local alpha = look == "bronze" and 1 or nil
		if alpha then
			local r, g, b = PQ.BronzeColor()
			row.box:SetBackdropBorderColor(r, g, b, alpha)
		else
			row.box:SetBackdropBorderColor(unpack(E.media.borderColor))
		end
	end
	local action = PQ.CardAction(card, item.group)
	local inset = boxed and PAD + 6 or PAD
	row.action.action = action
	row.action:SetShown(action ~= nil)
	if action then
		row.action:SetText(action == "share" and L["Share"] or L["Ask"])
		UI.FitButton(row.action, 46)
		row.action:ClearAllPoints()
		row.action:SetPoint("TOPRIGHT", row, "TOPRIGHT", -inset, -4)
		local member = card.members[1]
		UI.Tooltip(row.action, action == "share" and L["Share"] or L["Ask"],
			action == "share" and L["Shares the quest with your party through the game's own share."]
			or L["Sends %s one message asking to share this quest with you."]:format(member and member.name or ""))
	end
	row.title:ClearAllPoints()
	row.members:ClearAllPoints()
	local right = action and -(inset + row.action:GetWidth() + 4) or -inset
	if TwoLines(look) then
		row.title:SetPoint("TOPLEFT", row, "TOPLEFT", inset, -6)
		row.title:SetPoint("TOPRIGHT", row, "TOPRIGHT", right, -6)
		-- The members line runs under the action button too.
		row.members:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
		row.members:SetPoint("TOPRIGHT", row.title, "BOTTOMRIGHT", -inset - right, -3)
		row.members:Show()
		row.members:SetText(PQ.MembersText(card))
		row.title:SetText(PQ.CardTitle(card))
	else
		row.title:SetPoint("LEFT", row, "LEFT", inset, 0)
		row.title:SetPoint("RIGHT", row, "RIGHT", right, 0)
		row.members:Hide()
		-- One line: the title and how many of you are on it.
		local who = #card.members + (card.mine and 1 or 0)
		row.title:SetText(("%s  %s"):format(PQ.CardTitle(card), E:TokenHex(E.tokens.text.secondary) .. who .. "|r"))
	end
	if look == "tracker" then
		row.title:SetTextColor(E:TokenColor("accent"))
	else
		UI.Paint(row.title)
	end
	local bar = db.bars and boxed and card.mine and card.mine.total > 0
	row.bar:SetShown(bar and true or false)
	if bar then
		row.bar:ClearAllPoints()
		row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", inset, 7)
		row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -inset, 7)
		row.bar:SetValue(card.mine.complete and 1 or card.mine.done / card.mine.total)
		local c = card.mine.complete and E.tokens.text.good or E.media.accentColor
		row.bar:SetStatusBarColor(c[1], c[2], c[3])
	end
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------
function PQ:CreatePanel()
	if self.frame then return self.frame end
	local frame = CreateFrame("Frame", "EldoUI_PartyQuests", UIParent)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	E:SetPanelTemplate(frame, true)
	self.frame = frame

	frame.title = UI.Text(frame, E.tokens.size.section, "LEFT", "header")
	frame.title:SetPoint("TOPLEFT", PAD + 2, -6)
	frame.title:SetText(L["Party Quests"])
	frame.count = UI.Text(frame, E.tokens.size.small, "RIGHT", "secondary")
	frame.count:SetPoint("TOPRIGHT", -PAD - 2, -8)
	frame.line = UI.Divider(frame)
	frame.line:SetPoint("TOPLEFT", 1, -HEADER)
	frame.line:SetPoint("TOPRIGHT", -1, -HEADER)

	frame.list = UI.CreateList(frame, {
		height = function(item) return RowHeight(item) end,
		kind = function(item) return item.kind end,
		create = CreateRow,
		update = UpdateRow,
	})
	frame.list:SetPoint("TOPLEFT", 0, -HEADER - 2)
	frame.list:SetPoint("BOTTOMRIGHT", 0, 4)

	frame.empty = UI.Text(frame, E.tokens.size.label, "CENTER", "secondary")
	frame.empty:SetPoint("TOPLEFT", frame.list, "TOPLEFT", 12, -24)
	frame.empty:SetPoint("TOPRIGHT", frame.list, "TOPRIGHT", -12, -24)
	frame.empty:SetWordWrap(true)

	E:CreateMover(frame, "EldoUI_PartyQuests", L["Party Quests"], { "TOP", "UIParent", "TOP", -502, -150 })
	-- Dragging the title bar moves the panel and saves its spot the way a
	-- move-mode drag does (a locked spot stays put; not in combat, where the
	-- saved spot would wait for the fight to end).
	local drag = CreateFrame("Frame", nil, frame)
	drag:SetPoint("TOPLEFT")
	drag:SetPoint("TOPRIGHT")
	drag:SetHeight(HEADER)
	drag:EnableMouse(true)
	drag:RegisterForDrag("LeftButton")
	drag:SetScript("OnDragStart", function()
		if InCombatLockdown() or E:IsMoverLocked("EldoUI_PartyQuests") then return end
		frame:SetMovable(true)
		frame:StartMoving()
		frame.dragging = true
	end)
	drag:SetScript("OnDragStop", function()
		if not frame.dragging then return end
		frame.dragging = nil
		frame:StopMovingOrSizing()
		frame:SetUserPlaced(false)
		local mover = E.movers.EldoUI_PartyQuests
		local left, bottom = frame:GetLeft(), frame:GetBottom()
		if mover and left and bottom then
			local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
			local width, height = mover:GetSize()
			E:SaveMoverFromRect(mover, left * scale + (frame:GetWidth() * scale - width) / 2,
				bottom * scale + (frame:GetHeight() * scale - height) / 2)
		end
		frame:ClearAllPoints()
		if mover then frame:SetPoint("CENTER", mover, "CENTER") end
	end)
	frame.dragHandle = drag
	E:RegisterHideable(frame, "EldoUI_PartyQuests", { mouse = true })
	frame:Hide()
	self:ApplyLook()
	return frame
end

function PQ:ApplyLook()
	local frame = self.frame
	if not frame then return end
	local look = self.db.look
	local panel = look ~= "tracker" and look ~= "minimal"
	if panel then
		E:SetPanelTemplate(frame, true)
		if look == "bronze" then
			local r, g, b = PQ.BronzeColor()
			frame:SetBackdropBorderColor(r, g, b, 1)
		end
	else
		E:SetTemplateAlpha(frame, 0)
		frame:SetBackdropBorderColor(0, 0, 0, 0)
	end
	frame.line:SetShown(panel)
	frame.title:SetTextColor(EdgeColor(look))
	frame.list.dirty = true
end

-- The panel follows the shared visibility rules (alpha only).
function PQ:ApplyVisibility()
	local frame = self.frame
	if not frame then return end
	local block = self.db.visibility
	if type(block) ~= "table" then
		block = E:VisibilityDefaults()
		self.db.visibility = block
	end
	if self.visibilityBlock ~= block then E:DetachVisibility(frame) end
	if E:IsVisibilityAttached(frame) then
		E:UpdateVisibility(frame)
	else
		E:AttachVisibility(frame, block, { forceShow = function() return E:IsMoveMode() end })
	end
	self.visibilityBlock = block
end

function PQ:PanelShown()
	return self.active and self.db.panel and self:InScope() and true or false
end

function PQ:UpdatePanel()
	local frame = self.frame
	if not frame then return end
	if not self:PanelShown() then
		frame:Hide()
		return
	end
	local items = self:Items()
	local cache = self.cache or {}
	local shared = cache.shared and #cache.shared or 0
	frame.count:SetText(L["%d shared"]:format(shared))
	if #items == 0 then
		frame.empty:SetText(self.db.sync and L["No quests to compare yet. Quests you or your party take show here."]
			or L["No quests to compare yet. Turn on Sync with group to see the quests only your party has."])
		frame.empty:Show()
	else
		frame.empty:Hide()
	end
	frame.list:SetData(items, true)
	frame:Show()
end

function PQ:TogglePanel()
	self.db.panel = not self.db.panel
	self:Refresh()
	if E.RefreshConfig then E:RefreshConfig() end
	return self.db.panel
end

E:AddCommand("party", "show or hide the Party Quests panel", function()
	if not PQ.active then
		E:Print(E:ModuleOffHint("PartyQuests"))
		return
	end
	if PQ:TogglePanel() then
		E:Print(L["Party Quests panel on. It shows while you are in a group."])
	else
		E:Print(L["Party Quests panel off."])
	end
end)
