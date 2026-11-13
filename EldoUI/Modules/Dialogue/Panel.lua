-- EldoUI Dialog: the view.
--
-- One panel at the top center (mover EldoUI_Dialogue): the NPC's model and
-- name, the text shown sentence by sentence (instant, fast or slow; a click
-- on the text or Space shows all of it), numbered choices, reward cards and
-- the two buttons with their keys. Height follows the page; the width is a
-- setting. A screen dim behind it is optional.
--
-- Keys (only while the view shows and out of combat; every other key goes
-- on to the game): 1-9 pick a choice or a reward, Space shows all text and
-- then accepts, continues or completes, Esc leaves, R (when turned on) shows
-- or hides the rewards, Ctrl+C puts the text in a copy box. Each acts on the player's
-- key press only.
local _, E = ...
local L = E.L
local Key = E.Key
local D = E:GetModule("Dialogue")
local UI = E.UIKit
local WK = E.WindowKit
local Read = D.Read

local HOLDER_WIDTH, HOLDER_HEIGHT = 600, 180
local MODEL = 76
local CARD_HEIGHT = 40

local SPEED = { instant = 0, fast = 0.45, slow = 1.1 } -- seconds per sentence

D.LOOK_TITLE = {
	cinematic = Key("Cinematic"),
	book = Key("Book"),
	compact = Key("Compact"),
	large = Key("Large text"),
	bronze = Key("Forever bronze"),
	minimal = Key("Minimal"),
}
D.SPEED_TITLE = { instant = Key("Instant"), fast = Key("Fast"), slow = Key("Slow") }

local function Bronze()
	if E:SkinFlag("bronze") then return E:SkinBronze() end
	-- EldoUI's named Bronze accent (the palette token).
	return unpack(E.tokens.palette.bronze)
end
D.BronzeColor = Bronze

local function NameColor()
	if D.db.look == "bronze" then return Bronze() end
	return UI.Accent()
end

local function Pad()
	local look = D.db.look
	if look == "compact" then return 10 end
	if look == "large" then return 22 end
	return 16
end

---------------------------------------------------------------------------
-- Sentences: the text comes in a piece at a time
---------------------------------------------------------------------------
function D.Sentences(text)
	local list = {}
	if type(text) ~= "string" or text == "" then return list end
	local rest = text
	while rest ~= "" do
		local stop = rest:find("[%.!?][%s\n]")
		if not stop then
			list[#list + 1] = rest
			break
		end
		local piece = rest:sub(1, stop + 1)
		list[#list + 1] = piece
		rest = rest:sub(stop + 2)
	end
	return list
end

function D:IsRevealing()
	return self.reveal ~= nil and self.reveal.shown < #self.reveal.parts
end

function D:RevealAll()
	local reveal = self.reveal
	if not reveal then return end
	reveal.shown = #reveal.parts
	self:PaintReveal()
end

function D:PaintReveal()
	local view, reveal = self.view, self.reveal
	if not (view and reveal) then return end
	view.body:SetText(table.concat(reveal.parts, "", 1, reveal.shown))
	view.more:SetShown(reveal.shown < #reveal.parts)
end

local function OnRevealUpdate(_, elapsed)
	local reveal = D.reveal
	if not reveal or reveal.shown >= #reveal.parts then return end
	reveal.wait = reveal.wait - elapsed
	if reveal.wait > 0 then return end
	reveal.wait = reveal.step
	reveal.shown = reveal.shown + 1
	D:PaintReveal()
end

---------------------------------------------------------------------------
-- Parts
---------------------------------------------------------------------------
local function RowButton(parent)
	local row = CreateFrame("Button", nil, parent)
	row.number = UI.Text(row, 13, "RIGHT", "header")
	row.number:SetPoint("LEFT", 2, 0)
	row.number:SetWidth(20)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("LEFT", row.number, "RIGHT", 6, 0)
	row.label = UI.Text(row, 13, "LEFT")
	row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.label:SetPoint("RIGHT", -4, 0)
	row.label:SetWordWrap(false)
	E:SkinHoverPress(row)
	row:SetScript("OnClick", function(self, mouse)
		if E:IsOptionsLinkClick(self, mouse) then return end
		D:Pick(self.index)
	end)
	-- Ctrl-click opens the module options (reward cards are items: their
	-- modified clicks stay the game's).
	E:BindOptionsLink(row, { page = "module:Dialogue" })
	return row
end

local function CardTooltip(card)
	local item = card.item
	if not item then return end
	GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
	if item.link then
		GameTooltip:SetHyperlink(item.link)
	else
		E.UIKit.TipTitle(GameTooltip, item.name ~= "" and item.name or L["Reward"])
	end
	if item.kind == "choice" then
		local sr, sg, sb = unpack(E.tokens.text.secondary)
		E:TooltipHint(GameTooltip, { L["Click or press %d"]:format(card.index), L["pick this reward"] })
	end
	GameTooltip:Show()
end

local function RewardCard(parent)
	local card = CreateFrame("Button", nil, parent)
	card:SetHeight(CARD_HEIGHT)
	E:SetTemplate(card, true)
	card.icon = card:CreateTexture(nil, "ARTWORK")
	card.icon:SetSize(CARD_HEIGHT - 8, CARD_HEIGHT - 8)
	card.icon:SetPoint("LEFT", 4, 0)
	E:TrimIcon(card.icon)
	card.count = UI.Text(card, 11, "RIGHT")
	card.count:SetPoint("BOTTOMRIGHT", card.icon, "BOTTOMRIGHT", -1, 1)
	card.name = UI.Text(card, 12, "LEFT")
	card.name:SetPoint("LEFT", card.icon, "RIGHT", 6, 0)
	card.name:SetPoint("RIGHT", -6, 0)
	card.name:SetWordWrap(true)
	card.name:SetMaxLines(2)
	-- The sell value (the quality of life "Sell value on quest rewards").
	card.value = UI.Text(card, 11, "RIGHT")
	card.value:SetPoint("BOTTOMRIGHT", -6, 4)
	card.value:SetWordWrap(false)
	E:SkinHoverPress(card)
	card:SetScript("OnEnter", CardTooltip)
	card:SetScript("OnLeave", function() GameTooltip:Hide() end)
	card:SetScript("OnClick", function(self)
		if self.item and self.item.kind == "choice" then D:PickChoice(self.index) end
	end)
	return card
end

local function Pool(list, parent, make, count)
	for index = 1, math.max(#list, count) do
		local part = list[index]
		if index <= count and not part then
			part = make(parent)
			list[index] = part
		end
		if part then part:SetShown(index <= count) end
	end
	return list
end

---------------------------------------------------------------------------
-- The view
---------------------------------------------------------------------------
function D:CreateView()
	if self.view then return self.view end
	local holder = CreateFrame("Frame", "EldoUI_Dialogue", UIParent)
	holder:SetSize(HOLDER_WIDTH, HOLDER_HEIGHT)
	self.holder = holder
	E:CreateMover(holder, "EldoUI_Dialogue", L["NPC Dialog"], { "TOP", "UIParent", "TOP", 0, -288 }, { sample = false })

	local dim = CreateFrame("Frame", nil, UIParent)
	dim:SetAllPoints(UIParent)
	dim:SetFrameStrata("BACKGROUND")
	dim:EnableMouse(false)
	dim.fill = dim:CreateTexture(nil, "BACKGROUND")
	dim.fill:SetAllPoints()
	dim.fill:SetColorTexture(0, 0, 0, 1)
	dim:Hide()
	self.dim = dim

	local view = CreateFrame("Frame", "EldoUI_DialogueView", UIParent)
	view:SetFrameStrata("DIALOG")
	view:SetClampedToScreen(true)
	view:EnableMouse(true)
	view:SetPoint("TOP", holder, "TOP", 0, 0)
	view:SetSize(HOLDER_WIDTH, HOLDER_HEIGHT)
	E:SetPanelTemplate(view)
	view:Hide()
	self.view = view

	view.model = CreateFrame("PlayerModel", nil, view)
	view.model:SetSize(MODEL, MODEL)
	view.modelBox = CreateFrame("Frame", nil, view)
	view.modelBox:SetPoint("TOPLEFT", view.model, -E.pixel, E.pixel)
	view.modelBox:SetPoint("BOTTOMRIGHT", view.model, E.pixel, -E.pixel)
	E:SetTemplate(view.modelBox, true)
	view.modelBox:SetFrameLevel(math.max(view.model:GetFrameLevel() - 1, 0))

	view.name = UI.Text(view, 18, "LEFT")
	E:SetHeaderFont(view.name, 18)
	view.name:SetWordWrap(false)
	view.title = UI.Text(view, 15, "LEFT")
	view.title:SetWordWrap(true)
	view.chain = E.QuestTint and E.QuestTint.ChainButton and E.QuestTint:ChainButton(view) or nil
	view.line = UI.Divider(view)

	-- The text: a click shows all of it.
	view.textArea = CreateFrame("Button", nil, view)
	view.textArea:SetScript("OnClick", function() D:RevealAll() end)
	view.body = UI.Text(view.textArea, 15, "LEFT")
	view.body:SetPoint("TOPLEFT")
	view.body:SetPoint("TOPRIGHT")
	view.body:SetJustifyV("TOP")
	view.body:SetWordWrap(true)
	view.body:SetSpacing(3)
	view.more = UI.Text(view, 11, "RIGHT", "secondary")
	view.more:SetText(L["Space or click: all of the text"])
	view.extraHeading = UI.Text(view, 13, "LEFT", "header")
	view.extraText = UI.Text(view, 13, "LEFT")
	view.extraText:SetWordWrap(true)
	view.extraText:SetJustifyV("TOP")
	view.rewardHeading = UI.Text(view, 13, "LEFT", "header")
	view.rewardLine = UI.Text(view, 12, "LEFT", "secondary")
	view.rows, view.cards, view.fixed = {}, {}, {}

	view.primary = WK.Button(view, "", 150, function() D:Continue(true) end)
	view.secondary = WK.Button(view, "", 120, function() D:Leave() end)
	view.primaryKey = UI.Text(view, 10, "CENTER", "secondary")
	view.secondaryKey = UI.Text(view, 10, "CENTER", "secondary")

	view:SetScript("OnUpdate", OnRevealUpdate)
	view:EnableKeyboard(false)
	view:SetScript("OnKeyDown", function(frame, key)
		if InCombatLockdown() then return end
		local handled = D:Key(key)
		frame:SetPropagateKeyboardInput(not handled)
	end)
	self:ApplyLook()
	return view
end

function D:ApplyLook()
	local view = self.view
	if not view then return end
	local look = self.db.look
	if look == "minimal" then
		E:SetTemplateAlpha(view, 0)
		view:SetBackdropBorderColor(0, 0, 0, 0)
	else
		E:SetPanelTemplate(view, look == "book")
		if look == "bronze" then
			local r, g, b = Bronze()
			view:SetBackdropBorderColor(r, g, b, 1)
		end
	end
	view.line:SetShown(look ~= "minimal")
end

-- Places every part for the page and sets the height.
function D:Render(keepReveal)
	local view, page = self.view, self.page
	if not (view and page) then return end
	local db = self.db
	local size = db.fontSize
	local pad = Pad()
	local width = db.width
	view:SetWidth(width)
	local inner = width - pad * 2
	local y = pad

	-- Model and name.
	local showModel = db.model and Read(UnitExists, "npc") and true or false
	view.model:SetShown(showModel)
	view.modelBox:SetShown(showModel)
	if not showModel then self.modelGUID = nil end
	local left = pad
	if showModel then
		view.model:ClearAllPoints()
		view.model:SetPoint("TOPLEFT", pad, -pad)
		-- The model loads again only for another NPC (or after the view
		-- was closed), so a page change keeps it still.
		local guid = Read(UnitGUID, "npc")
		if E.Secret(guid) then guid = nil end
		local ok = true
		if not guid or guid ~= self.modelGUID then
			ok = pcall(view.model.SetUnit, view.model, "npc")
			self.modelGUID = ok and guid or nil
		end
		if not ok then
			view.model:Hide()
			view.modelBox:Hide()
		else
			left = pad + MODEL + 12
		end
	end
	local textWidth = width - left - pad
	E:SetHeaderFont(view.name, size + 3)
	view.name:SetTextColor(NameColor())
	view.name:ClearAllPoints()
	view.name:SetPoint("TOPLEFT", left, -y)
	view.name:SetWidth(textWidth)
	view.name:SetText(page.name or "")
	y = y + size + 7
	view.title:SetShown(page.title ~= nil and page.title ~= "")
	if view.title:IsShown() then
		E:SetFont(view.title, size + 1)
		view.title:ClearAllPoints()
		view.title:SetPoint("TOPLEFT", left, -y)
		view.title:SetWidth(textWidth)
		view.title:SetText(page.title)
		y = y + math.ceil(view.title:GetStringHeight() or size) + 6
	end
	if view.chain then
		E.QuestTint:ShowChain(view.chain, page.chain)
		if page.chain then
			view.chain:ClearAllPoints()
			view.chain:SetPoint("TOPLEFT", left, -y)
			view.chain:SetWidth(textWidth)
			y = y + 18
		end
	end
	view.line:ClearAllPoints()
	view.line:SetPoint("TOPLEFT", left, -y)
	view.line:SetPoint("TOPRIGHT", -pad, -y)
	y = y + 8

	-- The text, measured whole so the panel does not grow while it comes in.
	if db.look == "book" then E:SetHeaderFont(view.body, size) else E:SetFont(view.body, size) end
	view.textArea:ClearAllPoints()
	view.textArea:SetPoint("TOPLEFT", left, -y)
	view.textArea:SetWidth(textWidth)
	view.body:SetWidth(textWidth)
	local text = (not self.rewardsOnly and page.text) or ""
	view.body:SetText(text)
	local textHeight = text ~= "" and math.ceil(view.body:GetStringHeight() or size) or 0
	view.textArea:SetHeight(math.max(textHeight, 1))
	if not (keepReveal and self.reveal and self.reveal.page == page) then
		local parts = D.Sentences(text)
		local step = SPEED[db.textSpeed] or 0
		self.reveal = { page = page, parts = parts, shown = step > 0 and math.min(1, #parts) or #parts, step = step, wait = step }
	end
	self:PaintReveal()
	y = y + textHeight + (textHeight > 0 and 8 or 0)
	view.more:ClearAllPoints()
	view.more:SetPoint("TOPRIGHT", view.textArea, "BOTTOMRIGHT", 0, -1)
	if showModel and y < pad + MODEL + 8 then y = pad + MODEL + 8 end

	-- Objectives.
	local extra = page.extra
	view.extraHeading:SetShown(extra ~= nil and not self.rewardsOnly)
	view.extraText:SetShown(extra ~= nil and not self.rewardsOnly)
	if extra and not self.rewardsOnly then
		E:SetFont(view.extraHeading, size - 1)
		view.extraHeading:SetTextColor(NameColor())
		view.extraHeading:ClearAllPoints()
		view.extraHeading:SetPoint("TOPLEFT", pad, -y)
		view.extraHeading:SetText(extra.heading)
		y = y + size + 4
		E:SetFont(view.extraText, size - 1)
		view.extraText:ClearAllPoints()
		view.extraText:SetPoint("TOPLEFT", pad, -y)
		view.extraText:SetWidth(inner)
		view.extraText:SetText(extra.text)
		y = y + math.ceil(view.extraText:GetStringHeight() or size) + 8
	end

	-- Numbered rows (gossip and greeting).
	local rowHeight = size + 10
	Pool(view.rows, view, RowButton, #page.rows)
	for index, data in ipairs(page.rows) do
		local row = view.rows[index]
		row.index = index
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", pad, -y)
		row:SetSize(inner, rowHeight)
		E:SetFont(row.number, size)
		E:SetFont(row.label, size)
		row.number:SetText(index <= 9 and (index .. ".") or "")
		row.number:SetTextColor(NameColor())
		row.icon:SetTexture(data.icon)
		row.label:SetText(data.label)
		if data.dim then UI.Paint(row.label, "secondary") else UI.Paint(row.label) end
		y = y + rowHeight + 2
	end

	-- Rewards: choices (numbered, one is picked) and fixed rewards.
	local choices, fixed = page.choices or {}, page.rewards or page.required or {}
	local hasRewards = #choices + #fixed > 0 or page.rewardLine ~= nil
	view.rewardHeading:SetShown(hasRewards)
	view.rewardLine:SetShown(page.rewardLine ~= nil)
	local columns = width >= 560 and 2 or 1
	local cardWidth = math.floor((inner - (columns - 1) * 8) / columns)
	-- Sell values follow the quality of life setting "Sell value on quest
	-- rewards"; the most valuable choice's value is in the accent color unless
	-- the Upgrades module marks quest rewards (it owns the marker then).
	local qol = E.modules and E.modules.QoL
	local showValue = qol and qol.active and type(qol.db) == "table" and qol.db.rewardValue and true or false
	local upgradesMark = qol and qol.UpgradesMarksRewards and qol:UpgradesMarksRewards() or false
	local function PlaceCards(pool, items, numbered)
		Pool(pool, view, RewardCard, #items)
		local bestCard, bestValue = nil, 0
		for index, item in ipairs(items) do
			local card = pool[index]
			card.item, card.index = item, index
			local column = (index - 1) % columns
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", pad + column * (cardWidth + 8), -y)
			card:SetWidth(cardWidth)
			card.icon:SetTexture(item.icon)
			card.count:SetText(item.count and item.count > 1 and item.count or "")
			local label = item.name
			if numbered and index <= 9 then label = ("%d. %s"):format(index, label) end
			card.name:SetText(label)
			if item.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality] then
				local c = ITEM_QUALITY_COLORS[item.quality]
				card.name:SetTextColor(c.r, c.g, c.b)
			else
				UI.Paint(card.name)
			end
			if not item.usable then card.icon:SetVertexColor(unpack(E.tokens.text.bad)) else card.icon:SetVertexColor(1, 1, 1) end
			local picked = numbered and page.choice == index
			if picked then
				card:SetBackdropBorderColor(NameColor())
			else
				card:SetBackdropBorderColor(unpack(E.media.borderColor))
			end
			if E.SetUpgradeArrow and item.link then pcall(E.SetUpgradeArrow, E, card, item.link, { best = false }) end
			local value = 0
			if showValue and item.link and item.kind ~= "required" and C_Item and C_Item.GetItemInfo then
				local price = select(11, Read(C_Item.GetItemInfo, item.link))
				if type(price) == "number" and price > 0 then value = price * math.max(tonumber(item.count) or 1, 1) end
			end
			card.name:ClearAllPoints()
			card.name:SetPoint("LEFT", card.icon, "RIGHT", 6, 0)
			if value > 0 then
				card.value:SetText(E:FormatMoney(value))
				UI.Paint(card.value)
				card.value:Show()
				card.name:SetPoint("RIGHT", card.value, "LEFT", -4, 0)
				if numbered and value > bestValue then bestCard, bestValue = card, value end
			else
				card.value:SetText("")
				card.value:Hide()
				card.name:SetPoint("RIGHT", -6, 0)
			end
			if column == columns - 1 or index == #items then y = y + CARD_HEIGHT + 6 end
		end
		if bestCard and #items > 1 and not upgradesMark then bestCard.value:SetTextColor(E:TokenColor("accent")) end
		-- The Upgrades module's marks on the choices: best upgrade or best seller.
		if numbered and #items > 1 and E.MarkQuestRewards then
			local list = {}
			for index, item in ipairs(items) do list[index] = { button = pool[index], link = item.link } end
			pcall(E.MarkQuestRewards, E, list, "quest")
		end
	end
	if hasRewards then
		local heading = page.kind == "progress" and L["Required items"]
			or (#choices > 1 and L["Choose a reward (1-%d)"]:format(math.min(#choices, 9))) or L["Rewards"]
		E:SetFont(view.rewardHeading, size - 1)
		view.rewardHeading:SetTextColor(NameColor())
		view.rewardHeading:ClearAllPoints()
		view.rewardHeading:SetPoint("TOPLEFT", pad, -y)
		view.rewardHeading:SetText(heading)
		y = y + size + 6
	end
	PlaceCards(view.cards, choices, #choices > 1)
	PlaceCards(view.fixed, fixed, false)
	if page.rewardLine then
		view.rewardLine:ClearAllPoints()
		view.rewardLine:SetPoint("TOPLEFT", pad, -y)
		view.rewardLine:SetText(page.rewardLine)
		y = y + 18
	end

	-- Buttons.
	y = y + 6
	local primary, secondary = page.primary, page.secondary
	view.primary:SetShown(primary ~= nil)
	view.primaryKey:SetShown(primary ~= nil and db.spaceKey)
	if primary then
		view.primary:SetText(primary.label)
		view.primary:ClearAllPoints()
		view.primary:SetPoint("TOPRIGHT", -pad, -y)
		local ready = self:PrimaryReady()
		view.primary:SetEnabled(ready)
		view.primary:SetAlpha(ready and 1 or E.tokens.disabledAlpha)
		view.primaryKey:ClearAllPoints()
		view.primaryKey:SetPoint("TOP", view.primary, "BOTTOM", 0, -2)
		view.primaryKey:SetText(L["Space"])
	end
	view.secondary:SetShown(secondary ~= nil)
	view.secondaryKey:SetShown(secondary ~= nil)
	if secondary then
		view.secondary:SetText(secondary.label)
		view.secondary:ClearAllPoints()
		if primary then
			view.secondary:SetPoint("RIGHT", view.primary, "LEFT", -8, 0)
		else
			view.secondary:SetPoint("TOPRIGHT", -pad, -y)
		end
		view.secondaryKey:ClearAllPoints()
		view.secondaryKey:SetPoint("TOP", view.secondary, "BOTTOM", 0, -2)
		view.secondaryKey:SetText(L["Esc"])
	end
	y = y + E.tokens.height.button + 14 + pad
	view:SetHeight(math.max(y, 80))
end

function D:ShowView()
	local view = self.view or self:CreateView()
	self.rewardsOnly = false
	self:Render()
	self.showing = true
	view:Show()
	local dim = self.db.dim or 0
	self.dim.fill:SetAlpha(dim)
	self.dim:SetShown(dim > 0)
	if not InCombatLockdown() then view:EnableKeyboard(true) end
end

function D:HideView()
	self.showing = false
	self.reveal = nil
	self.modelGUID = nil
	if self.dim then self.dim:Hide() end
	local view = self.view
	if not view then return end
	if not InCombatLockdown() then view:EnableKeyboard(false) end
	view:Hide()
end

---------------------------------------------------------------------------
-- Keys
---------------------------------------------------------------------------
local NUMBER = {}
for index = 1, 9 do
	NUMBER[tostring(index)] = index
	NUMBER["NUMPAD" .. index] = index
end

function D:Key(key)
	if not (self.showing and self.page) then return false end
	local db = self.db
	if key == "ESCAPE" then
		self:Leave()
		return true
	end
	if key == "SPACE" and db.spaceKey then
		self:Continue()
		return true
	end
	if NUMBER[key] and db.numberKeys then
		return self:Pick(NUMBER[key]) and true or false
	end
	-- R only when the player turned it on and with no modifier, so R
	-- (Reply), Shift+R (Re-whisper) and other R bindings keep working.
	if key == "R" and db.rewardsKey and not (IsShiftKeyDown() or IsAltKeyDown() or IsControlKeyDown()) then
		local page = self.page
		local count = #(page.choices or {}) + #(page.rewards or {}) + #(page.required or {})
		if count == 0 and not page.rewardLine then return false end
		self.rewardsOnly = not self.rewardsOnly
		self.reveal = nil
		self:Render()
		return true
	end
	if key == "C" and IsControlKeyDown() and db.copyKey then
		E:ShowCopyBox(self.page.name ~= "" and self.page.name or L["NPC Dialog"], L["The text is selected: press Ctrl+C to copy it."], self:PlainText())
		return true
	end
	return false
end
