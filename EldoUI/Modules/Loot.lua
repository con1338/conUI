-- EldoUI Loot: the loot window, the group roll bars, the loot history and
-- loot toasts, in the EldoUI look with the shared slide animation.
--
-- Two Blizzard elements belong to this module (Core/Blizzard.lua):
--   loot-window       Blizzard's LootFrame. Skin it, move and scale it,
--                     hide it, or replace it with EldoUI's loot window.
--   group-loot-rolls  Blizzard's roll frames and loot history. Skin,
--                     move and scale, hide, replace with EldoUI's roll bars,
--                     and upgrade arrows (improve).
-- With an element's master switch off this module leaves Blizzard's frames
-- exactly as Blizzard made them: no hooks that change them, no skin, no CVar.
--
--   * Loot window: quality-colored rows, opens at the cursor or a fixed
--     spot, rows fade away as you loot them, a Loot all button you click,
--     a Link button that posts the items to your group on your click,
--     the master looter's give menu, faster auto loot.
--   * Group rolls: bars with icon, timer, BoP mark, upgrade arrow and
--     Need/Greed/Transmog/Disenchant/Pass; a rolled bar stays until the
--     game's loot history names the winner. Rolls are always manual: only
--     the player's own click on a roll button calls RollOnLoot, and EldoUI
--     never answers Blizzard's bind or disenchant confirmations.
--   * Toasts and loot feed: items, money, reputation, currencies and
--     skill-ups as cards or as a compact feed (EldoUI_LootFeed), repeats
--     merged, matched through the client's localized strings.
-- Written from scratch for EldoUI; no code or media from other addons.
local _, E = ...
local L = E.L

local Key = E.Key
local LOOT_ID, ROLL_ID = "loot-window", "group-loot-rolls"

local M = E:NewModule("Loot", {
	title = "Loot",
	desc = "Loot window, group roll bars, loot history and loot toasts in the EldoUI look.",
	conflicts = { "XLoot", "XLoot_Frame", "XLoot_Group", "XLoot_Monitor" },
	frames = {
		"EldoUI_Loot", "EldoUI_LootAnchor", "EldoUI_LootFeed", "EldoUI_LootRolls", "EldoUI_LootToasts",
	},
	movers = { "EldoUI_LootAnchor", "EldoUI_LootFeed", "EldoUI_LootRolls", "EldoUI_LootToasts" },
	blizzard = { "loot-window", "group-loot-rolls" },
	savedKeys = { "profile.modules.Loot" },
	optionsPage = "module:Loot",
	presets = { "BlizzardSkinned", "Compact", "EldoUI", "Feed", "Fixed", "Large", "Quiet" },
	defaults = {
		-- Loot window
		lootMode = "blizzard",  -- mirror of the loot-window switches: blizzard, skin, eldoui
		window = true,          -- v0.5.0 setting, read once by the update to the element switches
		atCursor = true,
		iconSize = 32,
		width = 240,
		fontSize = 14,
		lootAll = true,         -- a Loot all button on EldoUI's window (you click it)
		lootLink = true,        -- a Link button that posts the items to chat (you click it)
		lootLinkChannel = "GROUP", -- GROUP (instance, raid or party), PARTY, RAID or SAY
		lootLinkQuality = 2,    -- lowest item quality the Link button posts (2 = uncommon)
		masterLoot = true,      -- EldoUI's give menu for the master looter (you pick who gets it)
		masterBanker = "",      -- a name the menu lists first as Banker, when that player is a candidate
		masterDisenchanter = "", -- the same for the Disenchanter
		masterAnnounce = false, -- posts who got the item to the group after you give it
		fastLoot = false,       -- takes every slot for you while auto loot is on: off by default (DESIGN.md 5)
		skipBindConfirm = false,
		lootBindTag = true,     -- row marks, each from what the game reports: bind tag on the icon
		lootDetails = false,    -- a second line with the equip slot and item type
		lootValue = false,      -- vendor price of the stack
		lootRoomNotice = true,  -- names a low-value bag stack after the game reports no room
		lootUpgrade = true,     -- the Upgrades module's arrow on the icon
		lootNewLook = true,     -- "New look" for an appearance you have not collected (Appearances)
		lootQuestStart = true,  -- "Starts a quest" on items that begin a quest
		blizzScale = 1,         -- Blizzard loot window scale (Move switch)
		-- Rolls
		rollMode = "blizzard",  -- mirror of the group-loot-rolls switches
		rolls = true,           -- v0.5.0 setting, read once by the update
		rollWidth = 320,
		rollHeight = 40,
		rollGrow = "DOWN",
		rollArrows = true,
		rollBoP = true,
		rollKeep = true,        -- a rolled bar waits for the winner from the game's loot history
		rollWonTime = 6,        -- seconds the result stays when you won
		rollLostTime = 3,       -- seconds the result stays when someone else won or all passed
		rollItemLevel = true,   -- item level on the icon of weapons and armor
		rollMarkBorder = true,  -- icon border: green for an upgrade, the accent for a new look
		rollUrgent = true,      -- the timer turns red in its last quarter
		rollChoices = true,     -- how many in the group picked Need, Transmog, Greed or Pass so far
		blizzRollScale = 1,
		-- Toasts and the loot feed
		toasts = true,
		toastMode = "toast",    -- toast (cards at the right edge) | feed (compact rows)
		toastQuality = 2,       -- lowest item quality shown (2 = uncommon)
		toastMoney = true,      -- source: money
		feedItems = true,       -- source: items
		feedRep = true,         -- source: reputation
		feedCurrency = true,    -- source: currencies
		feedSkill = true,       -- source: skill-ups
		feedCrafted = true,     -- source: items you create
		feedXP = false,         -- source: experience, added up in one row
		feedHonor = false,      -- source: honor
		feedOthers = false,     -- source: what party and raid members loot
		feedOthersQuality = 3,  -- lowest quality of their loot (3 = rare)
		feedOthersTime = 4,     -- seconds their rows stay
		feedCapped = true,      -- "Capped" on a currency at its cap
		feedBagCount = false,   -- the item's total in the bags on the icon
		feedMerge = true,       -- a repeat adds to the row that is still shown
		feedItemLevel = true,   -- item level of weapons and armor
		feedValue = false,      -- vendor price of the looted stack
		feedStyle = "rows",     -- rows | bar | tiles | cards
		feedQualityBorder = true,
		feedRowHeight = 24,
		feedWidth = 280,
		feedFontSize = 13,
		feedRows = 8,
		feedGrow = "UP",
		toastTime = 4,
		toastMax = 4,           -- toast cards at once; more gains wait their turn
		toastLegendary = true,  -- "Legendary!" on a legendary item's card
		toastSound = "none",    -- media id for a new card or row, once per burst
		toastSoundLegendary = "none", -- its own sound for a legendary item ("none": the sound above)
	},
})

local hider = CreateFrame("Frame")
hider:Hide()

local function QualityColor(quality)
	local color = ITEM_QUALITY_COLORS[quality or 1] or ITEM_QUALITY_COLORS[1]
	return color.r, color.g, color.b
end

local function HasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function IconBox(parent, size)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(size, size)
	E:SetTemplate(holder)
	holder.icon = holder:CreateTexture(nil, "ARTWORK")
	holder.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	holder.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(holder.icon)
	holder.count = E:CreateText(holder, E.tokens.size.label, "RIGHT")
	holder.count:SetPoint("BOTTOMRIGHT", -2, 2)
	return holder
end

---------------------------------------------------------------------------
-- Mode selects: one choice on the module page that sets the element's
-- switches (Blizzard UI page), and follows them when they change there.
---------------------------------------------------------------------------
local MODE_KEY = { [LOOT_ID] = "lootMode", [ROLL_ID] = "rollMode" }
local lastMode = {}
local pushing = false

local function DerivedMode(id)
	if E:BlizzardAllowed(id, "replace") then return "eldoui" end
	if E:BlizzardAllowed(id, "skin") then return "skin" end
	return "blizzard"
end

local function PushMode(id, mode)
	local state = E:BlizzardState(id)
	if not state then return end
	pushing = true
	if mode ~= "blizzard" and not state.enabled then E:SetBlizzardElement(id, "enabled", true) end
	if state.enabled then
		E:SetBlizzardElement(id, "replace", mode == "eldoui")
		E:SetBlizzardElement(id, "skin", mode == "skin")
		if mode == "eldoui" or mode == "skin" then E:SetBlizzardElement(id, "hide", false) end
	end
	pushing = false
end

function M:SyncModes()
	if pushing then return end
	for id, key in pairs(MODE_KEY) do
		local derived = DerivedMode(id)
		if self.db[key] ~= derived then
			if lastMode[id] == derived then
				-- The player picked a mode on this page: set the switches.
				PushMode(id, self.db[key])
			end
			self.db[key] = DerivedMode(id)
		end
		lastMode[id] = self.db[key]
	end
end

---------------------------------------------------------------------------
-- EldoUI loot window
---------------------------------------------------------------------------
local ROW = { gap = 4, title = 30 } -- the gap between rows; the title's height

-- A small text button in the window's title (Loot all, Link).
local function TitleButton(frame, text, width)
	local button = CreateFrame("Button", nil, frame)
	button:SetSize(width, 16)
	E:SetTemplate(button, true)
	button.text = E:CreateText(button, E.tokens.size.small)
	button.text:SetPoint("CENTER")
	button.text:SetText(text)
	button.hover = button:CreateTexture(nil, "HIGHLIGHT")
	button.hover:SetAllPoints()
	E:AccentTexture(button.hover, 0.18)
	return button
end

-- The chat the Link button posts to: GROUP picks the instance group, raid
-- or party you are in. Nil when you are not where the choice points.
local function LinkChannel(choice)
	if choice == "SAY" then return "SAY" end
	if choice == "RAID" then return IsInRaid() and "RAID" or nil end
	if choice == "PARTY" then return IsInGroup() and "PARTY" or nil end
	local instance = rawget(_G, "LE_PARTY_CATEGORY_INSTANCE")
	if instance and IsInGroup(instance) then return "INSTANCE_CHAT" end
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
	return nil
end

local CHANNEL_NAMES = {
	INSTANCE_CHAT = E:GameText(_G.INSTANCE_CHAT, L["Instance"]), RAID = E:GameText(_G.RAID, L["Raid"]),
	PARTY = E:GameText(_G.PARTY, L["Party"]), SAY = E:GameText(_G.SAY, L["Say"]),
}

local LINE_MAX, LINE_COUNT = 255, 3 -- the game's chat line limit; lines per click

-- The chat lines for the items in the loot window from the lowest quality
-- up: highest quality first, as few lines as fit, at most three; what does
-- not fit is counted at the end. Nil when there is nothing to link.
function M:LootLinkLines()
	local items = {}
	for slot = 1, GetNumLootItems() do
		local link = E.PlainCall(GetLootSlotLink, slot)
		local _, _, _, quantity, _, quality = pcall(GetLootSlotInfo, slot)
		quantity, quality = E.Plain(quantity), E.Plain(quality)
		if type(link) == "string" and type(quality) == "number"
			and quality >= (self.db.lootLinkQuality or 2) then
			local count = (type(quantity) == "number" and quantity > 1) and ("x" .. quantity) or ""
			items[#items + 1] = { text = link .. count, quality = quality, slot = slot }
		end
	end
	if #items == 0 then return nil end
	table.sort(items, function(a, b)
		if a.quality ~= b.quality then return a.quality > b.quality end
		return a.slot < b.slot
	end)
	local prefix = L["Loot:"]
	local function Join(parts, index, tail)
		local text = table.concat(parts, " ")
		if index == 1 then text = text == "" and prefix or (prefix .. " " .. text) end
		if tail then text = text == "" and tail or (text .. " " .. tail) end
		return text
	end
	local lines, placed = { {} }, 0
	for _, item in ipairs(items) do
		local parts = lines[#lines]
		if #parts > 0 and #Join(parts, #lines) + 1 + #item.text > LINE_MAX then
			if #lines == LINE_COUNT then break end
			parts = {}
			lines[#lines + 1] = parts
		end
		if #Join(parts, #lines) + 1 + #item.text > LINE_MAX then break end
		parts[#parts + 1] = item.text
		placed = placed + 1
	end
	local more = #items - placed
	local last, tail = lines[#lines], nil
	if more > 0 then
		tail = L["+%d more"]:format(more)
		while #last > 0 and #Join(last, #lines, tail) > LINE_MAX do
			last[#last] = nil
			more = more + 1
			tail = L["+%d more"]:format(more)
		end
	end
	local out = {}
	for index, parts in ipairs(lines) do
		out[index] = Join(parts, index, index == #lines and tail or nil)
	end
	return out
end

-- One chat line the player asked for, through EldoUI's one chat gate
-- (Core/Comm.lua): the game's chat restriction is checked first, and a
-- refused line is never sent later.
local function ChatPost(text, channel)
	return E:TryChatPost(text, channel)
end

-- The Link button's click: the lines go to the chosen chat, in order.
function M:PostLootLinks()
	local channel = LinkChannel(self.db.lootLinkChannel)
	if not channel then
		E:Print(L["You are not in a group."])
		return false
	end
	local lines = self:LootLinkLines()
	if not lines then return false end
	for _, line in ipairs(lines) do
		local sent, why = ChatPost(line, channel)
		if not sent then
			if why == "restricted" then
				E:Print(L["Could not link the loot: the game doesn't allow chat messages right now."])
			end
			return false
		end
	end
	return true
end

-- The title buttons that apply right now, right to left beside the close
-- button; the title text ends where they begin.
function M:UpdateTitleButtons()
	local frame, db = self.lootFrame, self.db
	if not frame then return end
	frame.lootAll:SetShown(db.lootAll and GetNumLootItems() > 1)
	frame.lootLink:SetShown(db.lootLink and LinkChannel(db.lootLinkChannel) ~= nil and self:LootLinkLines() ~= nil)
	local anchor = frame.close
	for _, button in ipairs({ frame.lootAll, frame.lootLink }) do
		if button:IsShown() then
			button:ClearAllPoints()
			button:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
			anchor = button
		end
	end
	frame.title:ClearAllPoints()
	frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -7)
	-- The 16- and 20-high buttons share a center, so both text corners stay level.
	frame.title:SetPoint("TOPRIGHT", anchor, "LEFT", -4, 5)
end

function M:CreateLootFrame()
	local frame = CreateFrame("Frame", "EldoUI_Loot", UIParent)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetToplevel(true)
	frame:EnableMouse(true)
	E:SetPanelTemplate(frame)
	frame.title = E:CreateText(frame, E.tokens.size.cardTitle, "LEFT")
	E:UseNameFont(frame.title)
	E:SetHeaderFont(frame.title, 14) -- theme outline; follows theme changes
	frame.title:SetPoint("TOPLEFT", 8, -7)
	frame.title:SetPoint("TOPRIGHT", -70, -7)
	frame.accent = frame:CreateTexture(nil, "ARTWORK")
	frame.accent:SetPoint("TOPLEFT", E.pixel, -24)
	frame.accent:SetPoint("TOPRIGHT", -E.pixel, -24)
	frame.accent:SetHeight(E.pixel * 2)
	frame.roomNotice = E:CreateText(frame, E.tokens.size.small, "LEFT")
	frame.roomNotice:SetPoint("TOPLEFT", 8, -ROW.title)
	frame.roomNotice:SetWordWrap(true)
	frame.roomNotice:Hide()
	frame:HookScript("OnHide", function()
		M:EndLootRoomNotice()
		-- Closing the window (Escape, the close button, a hidden interface)
		-- ends the loot, as the game's own window does; otherwise the loot
		-- stays open with nothing on screen to take it.
		if M.lootOpen then
			M.lootOpen = nil
			CloseLoot()
		end
	end)
	-- Escape closes it like the game's own windows.
	table.insert(UISpecialFrames, "EldoUI_Loot")
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButtonNoScripts")
	close:SetSize(20, 20)
	close:SetPoint("TOPRIGHT", 0, -2)
	close:SetScript("OnClick", function() CloseLoot() end)
	E:SkinCloseButton(close)
	frame.close = close
	-- Loot all: takes every slot, on the player's click only.
	local all = TitleButton(frame, E:GameText(_G.LOOT_ALL or ALL, L["All"]), 46)
	all:SetScript("OnClick", function(clicked, mouse)
		if E:IsOptionsLinkClick(clicked, mouse) then return end
		M.DrainLoot()
	end)
	all:SetScript("OnEnter", function(button)
		GameTooltip:SetOwner(button, "ANCHOR_TOP")
		GameTooltip:SetText(E:GameText(_G.LOOT_ALL, L["Loot all"]))
		E.UIKit.TipTitle(GameTooltip, L["Takes every item you can take."], true)
		GameTooltip:Show()
	end)
	all:SetScript("OnLeave", GameTooltip_Hide)
	-- Ctrl-click opens the setting (the loot rows are items: their
	-- Ctrl-click stays the game's dressing room preview).
	E:BindOptionsLink(all, { page = "module:Loot", key = "lootAll" })
	frame.lootAll = all
	-- Link: posts the items to chat, on the player's click only.
	local link = TitleButton(frame, L["Link"], 40)
	link:SetScript("OnClick", function(clicked, mouse)
		if E:IsOptionsLinkClick(clicked, mouse) then return end
		self:PostLootLinks()
	end)
	link:SetScript("OnEnter", function(button)
		GameTooltip:SetOwner(button, "ANCHOR_TOP")
		GameTooltip:SetText(L["Link"])
		local channel = LinkChannel(self.db.lootLinkChannel)
		E.UIKit.TipTitle(GameTooltip, L["Posts the items to %s."]:format(CHANNEL_NAMES[channel] or channel or ""), true)
		GameTooltip:Show()
	end)
	link:SetScript("OnLeave", GameTooltip_Hide)
	E:BindOptionsLink(link, { page = "module:Loot", key = "lootLink" })
	frame.lootLink = link
	frame.rows = {}
	frame:Hide()
	self.lootFrame = frame
	-- The fixed position is a normal EldoUI mover; Blizzard's loot window
	-- uses the same spot when its Move switch is on.
	self.lootAnchor = CreateFrame("Frame", "EldoUI_LootAnchor", UIParent)
	self.lootAnchor:SetSize(240, 40)
	E:CreateMover(self.lootAnchor, "EldoUI_LootAnchor", L["Loot Window"], { "LEFT", "UIParent", "LEFT", 380, 120 }, { sample = false })
end

local function CreateRow(frame, index)
	local row = CreateFrame("Button", nil, frame)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.iconBox = IconBox(row, 32)
	row.iconBox:SetPoint("LEFT")
	row.name = E:CreateText(row, E.tokens.size.cardTitle, "LEFT")
	row.name:SetWordWrap(false)
	-- The marks: a bind tag in the icon's free corner (the upgrade arrow
	-- takes the top left, the appearance mark the top right, the count the
	-- bottom right), and a second line under the name: slot and type on
	-- the left, the tags and the value on the right.
	row.iconBox.bind = E:CreateText(row.iconBox, E.tokens.size.tiny, "LEFT")
	row.iconBox.bind:SetPoint("BOTTOMLEFT", 2, 2)
	row.detail = E:CreateText(row, E.tokens.size.small, "LEFT")
	row.detail:SetWordWrap(false)
	row.detail:SetTextColor(E:TokenColor("secondary"))
	row.right = E:CreateText(row, E.tokens.size.small, "RIGHT")
	row.glow = row:CreateTexture(nil, "BACKGROUND")
	row.glow:SetAllPoints()
	row.glow:SetTexture(E.media.statusbar)
	row.glow:SetAlpha(0)
	row:SetScript("OnEnter", function(self)
		self.glow:SetAlpha(0.25)
		if not self.slot then return end
		local slotType = GetLootSlotType and GetLootSlotType(self.slot)
		if Enum.LootSlotType and slotType == Enum.LootSlotType.Currency and GameTooltip.SetLootCurrency then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetLootCurrency(self.slot)
			GameTooltip:Show()
		elseif GetLootSlotLink(self.slot) then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetLootItem(self.slot)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function(self)
		self.glow:SetAlpha(0)
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self)
		if not self.slot then return end
		if IsModifiedClick() and HandleModifiedItemClick(GetLootSlotLink(self.slot)) then return end
		-- A confirm left from another slot closes first, as in the game's
		-- own window; the game asks the master looter whom to give this
		-- slot to.
		M.HideLootPopup("CONFIRM_LOOT_DISTRIBUTION")
		M.masterSlot, M.masterRow = self.slot, self
		LootSlot(self.slot)
	end)
	frame.rows[index] = row
	return row
end

function M:LayoutLoot()
	local frame, db = self.lootFrame, self.db
	local y = -ROW.title - self:LayoutLootRoomNotice(frame)
	local shown = 0
	for _, row in ipairs(frame.rows) do
		if row:IsShown() and row.slot then
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 6, y)
			row:SetPoint("TOPRIGHT", -6, y)
			y = y - db.iconSize - ROW.gap
			shown = shown + 1
		end
	end
	frame:SetSize(db.width, -y + 4)
	return shown
end

-- The bind tag of an item, from the bind type the game reports.
local BIND_TAGS = { [1] = Key("BoP"), [2] = Key("BoE"), [3] = Key("BoU") }

-- True when the game's own tooltip for the slot says the item begins a
-- quest. Secret or missing tooltip data counts as no.
local function StartsQuest(slot)
	local info = C_TooltipInfo and C_TooltipInfo.GetLootItem
	local wanted = rawget(_G, "ITEM_STARTS_QUEST")
	if not (info and wanted) then return false end
	local ok, data = pcall(info, slot)
	if not ok or type(data) ~= "table" or E:IsSecret(data.lines) or type(data.lines) ~= "table" then return false end
	for _, line in ipairs(data.lines) do
		local text = type(line) == "table" and line.leftText
		if not E:IsSecret(text) and text == wanted then return true end
	end
	return false
end

-- What the right side of a row says: the stack's value, "New look" and
-- "Starts a quest", each only when its switch is on and the game says so.
local function RowTags(db, slot, link, quantity, sellPrice)
	local parts = {}
	if db.lootQuestStart and StartsQuest(slot) then
		parts[#parts + 1] = E:TextHex("gold") .. L["Starts a quest"] .. "|r"
	end
	if db.lootNewLook and link and E.Appearances and E.Appearances.State then
		local ok, state = pcall(E.Appearances.State, E.Appearances, link)
		if ok and state == "unknown" then parts[#parts + 1] = E:TextHex("accent") .. L["New look"] .. "|r" end
	end
	if db.lootValue and (sellPrice or 0) > 0 then
		parts[#parts + 1] = E:FormatMoney(sellPrice * math.max(quantity or 1, 1))
	end
	return table.concat(parts, "  ")
end

local function SetupRow(row, slot, db)
	row.roomItem = nil
	-- A slot the game cannot describe (a failed read, no icon) gets no row;
	-- a protected value is shown as given and never tested or compared.
	local ok, texture, name, quantity, currencyID, quality, locked, isQuestItem = pcall(GetLootSlotInfo, slot)
	if not ok or (not E:IsSecret(texture) and not texture) then return false end
	currencyID, quality, locked, isQuestItem = E.Plain(currencyID), E.Plain(quality), E.Plain(locked), E.Plain(isQuestItem)
	if currencyID and CurrencyContainerUtil and CurrencyContainerUtil.GetCurrencyContainerInfo then
		local read, cName, cTexture, cQuantity, cQuality = pcall(CurrencyContainerUtil.GetCurrencyContainerInfo, currencyID, quantity, name, texture, quality)
		if read then name, texture, quantity, quality = cName, cTexture, cQuantity, E.Plain(cQuality) end
	end
	row.slot = slot
	row.waitingInfo = nil
	row:SetHeight(db.iconSize)
	row.iconBox:SetSize(db.iconSize, db.iconSize)
	row.iconBox.icon:SetTexture(texture)
	row.iconBox.icon:SetDesaturated(locked and true or false)
	if E:IsSecret(quantity) then
		row.iconBox.count:SetText(quantity)
	else
		row.iconBox.count:SetText(type(quantity) == "number" and quantity > 1 and quantity or "")
	end
	if not E:IsSecret(quantity) and type(quantity) ~= "number" then quantity = nil end
	local qr, qg, qb = QualityColor(quality)
	if isQuestItem then qr, qg, qb = 1, 0.82, 0 end
	row.iconBox:SetBackdropBorderColor(qr, qg, qb, 1)
	row.glow:SetVertexColor(qr, qg, qb)
	E:SetFont(row.name, db.fontSize)
	if E:IsSecret(name) then
		row.name:SetText(name)
	else
		row.name:SetText(type(name) == "string" and (name:gsub("\n", " ")) or "")
	end
	row.name:SetTextColor(qr, qg, qb)

	-- Item marks: only what the game reports for this slot.
	local link = not currencyID and GetLootSlotLink(slot) or nil
	if E:IsSecret(link) or type(link) ~= "string" then link = nil end
	row.roomItem = link ~= nil and link ~= ""
	local bindType, equipLoc, subType, sellPrice
	if link then
		local _, _, _, _, _, _, itemSubType, _, itemEquipLoc, _, price, _, _, bind = C_Item.GetItemInfo(link)
		bindType, equipLoc, subType, sellPrice = bind, itemEquipLoc, itemSubType, price
		if bindType == nil then row.waitingInfo = true end
	end
	row.iconBox.bind:SetText(db.lootBindTag and BIND_TAGS[bindType] and E:Translate(BIND_TAGS[bindType]) or "")
	local detail = ""
	if db.lootDetails and link then
		local slotName = equipLoc and equipLoc ~= "" and _G[equipLoc] or nil
		local parts = {}
		if type(slotName) == "string" and slotName ~= "" then parts[#parts + 1] = slotName end
		if type(subType) == "string" and subType ~= "" and subType ~= slotName then parts[#parts + 1] = subType end
		detail = table.concat(parts, " · ")
	end
	E:SetFont(row.detail, math.max(9, db.fontSize - 3))
	row.detail:SetText(detail)
	E:SetFont(row.right, math.max(9, db.fontSize - 3))
	row.right:SetText(link and RowTags(db, slot, link, E.Plain(quantity), sellPrice) or "")
	-- The name keeps the whole first line; the slot and type, the tags and
	-- the value share a second line under it when there are any.
	row.name:ClearAllPoints()
	row.detail:ClearAllPoints()
	row.right:ClearAllPoints()
	local tags = row.right:GetText() ~= ""
	if detail ~= "" or tags then
		row.name:SetPoint("TOPLEFT", row.iconBox, "TOPRIGHT", 8, -1)
		row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -1)
		row.right:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 2)
		row.detail:SetPoint("BOTTOMLEFT", row.iconBox, "BOTTOMRIGHT", 8, 2)
		if tags then
			row.detail:SetPoint("BOTTOMRIGHT", row.right, "BOTTOMLEFT", -6, 0)
		else
			row.detail:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 2)
		end
	else
		row.name:SetPoint("LEFT", row.iconBox, "RIGHT", 8, 0)
		row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
		row.right:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	end
	row.detail:SetShown(detail ~= "")
	if E.SetUpgradeArrow then E:SetUpgradeArrow(row.iconBox, db.lootUpgrade and link or nil, { noTint = true }) end
	-- A row still sliding out from the last loot is taken back first, so
	-- its slide never hides it under the new item.
	if row.eldoAnim and row.eldoAnim.out then row.eldoAnim.out:Stop() end
	row:SetAlpha(1)
	row:Show()
	return true
end

-- The game reports that loot did not fit. Free-space estimates only tell
-- when to retire that warning after the player's bags change.
do
	local function HasItem(frame)
		for _, row in ipairs(frame.rows) do
			if row.slot and row.roomItem and row:IsShown() then return true end
		end
		return false
	end

	local function GeneralFree()
		local bags = E.BagCache
		local free, _, known = bags:GeneralSlots(bags:BagIDs(), false, true)
		free = E.Plain(free)
		if E.Plain(known) == true and type(free) == "number" and free >= 0 and free < math.huge then return free end
	end

	local function ClearWarning(frame, session)
		if session and session.full then
			session.full, session.free = nil, nil
			E.BagCache:UnregisterCallback(frame.roomNotice)
		end
		frame.roomNotice:SetText("")
		frame.roomNotice:Hide()
	end

	function M:EndLootRoomNotice()
		local frame = self.lootFrame
		local session = frame and frame.roomSession
		if not session then return end
		frame.roomSession = nil
		self:UnregisterEvent("UI_ERROR_MESSAGE")
		ClearWarning(frame, session)
	end

	function M:LayoutLootRoomNotice(frame)
		local session = frame.roomSession
		if not (session and session.full) then return 0 end
		if session.profile ~= self.db or not self.db.lootRoomNotice or not HasItem(frame) then
			ClearWarning(frame, session)
			return 0
		end
		local bags = E.modules.Bags
		local item = bags and bags.LowestValueItem and bags:LowestValueItem()
		local name, value
		if type(item) == "table" and not E.Secret(item) and (not canaccesstable or canaccesstable(item)) then
			name, value = E.Plain(item.name), E.Plain(item.value)
		end
		if frame.roomSession ~= session or not session.full then return 0 end
		local text = frame.roomNotice
		if type(name) ~= "string" or name == "" or type(value) ~= "number" or not (value >= 0 and value < math.huge) then
			text:SetText("")
			text:Hide()
			return 0
		end
		text:SetWidth(self.db.width - 16)
		text:SetTextColor(E:TokenColor("warn"))
		text:SetText(L["No room. Lowest value in your bags is %s (%s)."]:format(name:gsub("[\r\n]", " "), E:FormatMoney(value)))
		text:Show()
		return math.ceil(text:GetStringHeight() or 0) + ROW.gap
	end

	function M:BeginLootRoomNotice()
		local frame = self.lootFrame
		local session = { profile = self.db }
		frame.roomSession = session
		self:RegisterEvent("UI_ERROR_MESSAGE", function(_, _, _, message)
			if frame.roomSession ~= session or self.db ~= session.profile or not self.db.lootRoomNotice
				or not self.active or not frame:IsShown() or not E:BlizzardAllowed(LOOT_ID, "replace") then return end
			local full = E.Plain(rawget(_G, "ERR_INV_FULL"))
			message = E.Plain(message)
			if type(full) ~= "string" or full == "" or message ~= full or not HasItem(frame) then return end
			session.full, session.free = true, GeneralFree()
			E.BagCache:RegisterCallback(frame.roomNotice, function()
				if frame.roomSession ~= session or not session.full then return end
				local free = GeneralFree()
				if free and session.free and free > session.free then
					ClearWarning(frame, session)
				elseif free then
					session.free = free
				end
				self:LayoutLoot()
			end)
			self:LayoutLoot()
		end)
	end
end

-- A loot confirmation the game left on screen for a loot that is over
-- (the bind warning, the master looter's confirm) closes with it.
function M.HideLootPopup(which)
	local find = rawget(_G, "StaticPopup_FindVisible")
	if type(find) ~= "function" or type(StaticPopup_Hide) ~= "function" then return end
	local ok, dialog = pcall(find, which)
	if ok and not E:IsSecret(dialog) and type(dialog) == "table" then StaticPopup_Hide(which) end
end

function M:ShowLoot(autoLoot)
	local frame, db = self.lootFrame, self.db
	self.lootOpen = true
	self:EndLootRoomNotice()
	local r, g, b = unpack(E.media.accentColor)
	frame.accent:SetColorTexture(r, g, b, 1)
	frame.title:SetText(UnitExists("target") and UnitIsDead("target") and UnitName("target") or LOOT)
	for _, row in ipairs(frame.rows) do row:Hide(); row.slot = nil end
	local waiting = false
	for slot = 1, GetNumLootItems() do
		local row = frame.rows[slot] or CreateRow(frame, slot)
		SetupRow(row, slot, db)
		waiting = waiting or row.waitingInfo
	end
	-- An item the client has not loaded yet gets its marks once it has.
	if waiting then
		self:RegisterEvent("GET_ITEM_INFO_RECEIVED", function() self:RefreshLootRows(true) end)
	else
		self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
	end
	self:UpdateTitleButtons()
	if self:LayoutLoot() == 0 then
		-- Nothing to take: the loot ends at once, as with the game's own
		-- window, instead of staying open with no window to close it.
		if E.PlainCall(GetNumLootItems) == 0 then
			self.lootOpen = nil
			if frame:IsShown() then frame:Hide() end
			CloseLoot(not E.Plain(autoLoot))
		end
		return
	end
	frame:ClearAllPoints()
	if db.atCursor then
		local x, y = GetCursorPosition()
		local scale = frame:GetEffectiveScale()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale - 30, y / scale + 20)
	else
		frame:SetPoint("TOPLEFT", self.lootAnchor, "TOPLEFT")
	end
	E:SlideIn(frame, "LEFT")
	self:BeginLootRoomNotice()
end

function M:UpdateLootSlot(slot)
	local frame = self.lootFrame
	local row = frame and frame.rows[slot]
	if row and row.slot == slot then
		SetupRow(row, slot, self.db)
		if frame.roomSession and frame.roomSession.full then self:LayoutLoot() end
	end
end

-- Draw the shown rows again (an item's data arrived, a mark switch moved).
-- onlyWaiting: just the rows whose item was not loaded yet.
function M:RefreshLootRows(onlyWaiting)
	local frame = self.lootFrame
	if not (frame and frame:IsShown()) then return end
	local waiting = false
	for _, row in ipairs(frame.rows) do
		if row.slot and row:IsShown() and (not onlyWaiting or row.waitingInfo) then SetupRow(row, row.slot, self.db) end
		waiting = waiting or (row.slot and row.waitingInfo)
	end
	if not waiting then self:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
	self:UpdateTitleButtons()
	self:LayoutLoot()
end

---------------------------------------------------------------------------
-- Master loot: the game asks the master looter whom an item goes to. Its
-- own menu reads the slot from Blizzard's loot window, so with EldoUI's
-- window EldoUI shows the menu instead. Giving is always the player's
-- pick; items from the game's distribution threshold up ask first.
---------------------------------------------------------------------------
local function BareName(name)
	return type(name) == "string" and (name:match("^([^%-]+)") or name):lower() or nil
end

-- The candidates for a slot, in the game's order: { index, name, class, classFile }.
local function MasterCandidates(slot)
	local list = {}
	local max = rawget(_G, "MAX_RAID_MEMBERS") or 40
	for index = 1, max do
		local name, class, classFile = GetMasterLootCandidate(slot, index)
		if type(name) == "string" and not E:IsSecret(name) then
			list[#list + 1] = { index = index, name = name, class = class or "", classFile = classFile }
		end
	end
	return list
end

-- " (SR)", " (TMB)" after a name with a reserve or a list entry on the item.
local function ReserveTags(itemID)
	local tags = {}
	local RaidLoot = E.RaidLoot
	if not (RaidLoot and RaidLoot.active and itemID) then return tags end
	for _, which in ipairs({ "sr", "tmb" }) do
		local ok, entries = pcall(RaidLoot.Entries, RaidLoot, which, itemID)
		for _, entry in ipairs(ok and entries or {}) do
			local key = BareName(entry.name)
			if key then tags[key] = (tags[key] or "") .. " (" .. (which == "sr" and L["SR"] or L["TMB"]) .. ")" end
		end
	end
	return tags
end

local function ClassColored(name, classFile)
	local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if not color then return name end
	return ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, name)
end

-- Gives the slot to a candidate, asking first from the threshold up.
function M:GiveMasterLoot(slot, candidate)
	local _, _, itemName, _, _, quality = pcall(GetLootSlotInfo, slot)
	itemName, quality = E.Plain(itemName), E.Plain(quality)
	local link = E.PlainCall(GetLootSlotLink, slot)
	local function Give()
		GiveMasterLoot(slot, candidate.index)
		if self.db.masterAnnounce and link then
			local channel = LinkChannel("GROUP")
			if channel then ChatPost(L["%s goes to %s."]:format(link, candidate.name), channel) end
		end
	end
	local consts = Constants and Constants.LootConsts
	local threshold = consts and consts.MasterLootQualityThreshold or 4
	if type(quality) == "number" and quality >= threshold then
		local item = link or itemName or ""
		E:ShowConfirm({
			title = rawget(_G, "MASTER_LOOTER") or L["Master looter"],
			accept = L["Give"],
			text = L["Give %s to %s?"]:format(item, ClassColored(candidate.name, candidate.classFile)),
			onAccept = Give,
		})
	else
		Give()
	end
end

-- The give menu for a slot: the Banker, the Disenchanter and you first when
-- they can take it, then everyone (by class in a raid), then Request roll.
function M:OpenMasterLootMenu(slot)
	local candidates = MasterCandidates(slot)
	if #candidates == 0 then return false end
	local db = self.db
	local link = GetLootSlotLink(slot)
	local itemID = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
	local tags = ReserveTags(itemID)
	local function Label(candidate) return ClassColored(candidate.name, candidate.classFile) .. (tags[BareName(candidate.name)] or "") end
	local byName = {}
	for _, candidate in ipairs(candidates) do byName[BareName(candidate.name)] = candidate end
	local me = BareName(UnitName("player"))
	local quick = {}
	for _, pick in ipairs({
		{ key = BareName(db.masterBanker), label = L["Banker"] },
		{ key = BareName(db.masterDisenchanter), label = L["Disenchanter"] },
		{ key = me, label = L["Me"] },
	}) do
		local candidate = pick.key and pick.key ~= "" and byName[pick.key]
		if candidate and not quick[candidate] then
			quick[candidate] = true
			quick[#quick + 1] = { label = pick.label .. ": " .. Label(candidate), candidate = candidate }
		end
	end
	local raid = IsInRaid()
	self.masterMenu = E.UIKit.ContextMenu(self.masterRow or self.lootFrame, function(_, root)
		root:CreateTitle(link or rawget(_G, "MASTER_LOOTER") or L["Master looter"])
		for _, entry in ipairs(quick) do
			root:CreateButton(entry.label, function() self:GiveMasterLoot(slot, entry.candidate) end)
		end
		if #quick > 0 then root:CreateDivider() end
		if raid then
			local classes, order = {}, {}
			for _, candidate in ipairs(candidates) do
				if not classes[candidate.class] then
					classes[candidate.class] = {}
					order[#order + 1] = candidate
				end
				local list = classes[candidate.class]
				list[#list + 1] = candidate
			end
			table.sort(order, function(a, b) return a.class < b.class end)
			for _, first in ipairs(order) do
				local list = classes[first.class]
				table.sort(list, function(a, b) return a.name < b.name end)
				local sub = root:CreateButton(ClassColored(first.class, first.classFile))
				for _, candidate in ipairs(list) do
					sub:CreateButton(Label(candidate), function() self:GiveMasterLoot(slot, candidate) end)
				end
			end
		else
			for _, candidate in ipairs(candidates) do
				root:CreateButton(Label(candidate), function() self:GiveMasterLoot(slot, candidate) end)
			end
		end
		root:CreateDivider()
		root:CreateButton(rawget(_G, "REQUEST_ROLL") or L["Request roll"], function() DoMasterLootRoll(slot) end)
	end, { at = "cursor" })
	return true
end

-- The game's master loot question while EldoUI's window is open: on the
-- next frame Blizzard's own menu (which cannot see EldoUI's rows) is closed
-- and EldoUI's opens for the slot the player clicked.
function M:OnMasterLootList()
	local slot = self.masterSlot
	if not (slot and self.db.masterLoot and self.lootFrame and self.lootFrame:IsShown()) then return end
	C_Timer.After(0, function()
		if not (self.lootFrame:IsShown() and self.masterSlot == slot) then return end
		local manager = Menu and Menu.GetManager and Menu.GetManager()
		if manager and manager.CloseMenus then pcall(manager.CloseMenus, manager) end
		self:OpenMasterLootMenu(slot)
	end)
end

-- Faster auto loot: when the game is auto looting, take the slots one per
-- short tick from the last down (a whole pile in one frame can trip the
-- server's flood guard). The auto-loot decision and the slot count come
-- from a loot's first LOOT_READY; a repeat with the same count is ignored.
-- LOOT_CLOSED stops the drain. Under master loot it stands back: the
-- master looter hands the items out.
local FAST_TICK = 0.03
local fast = {}

local function MasterLoot()
	local party = C_PartyInfo
	if not (party and party.GetLootMethod) then return false end
	local ok, method = pcall(party.GetLootMethod)
	if not ok or E.Secret(method) then return false end
	local master = Enum and Enum.LootMethod and Enum.LootMethod.Masterlooter or 2
	return method == master
end

local function StopDrain()
	if fast.ticker then fast.ticker:Cancel() end
	fast.ticker, fast.slot = nil, nil
end

-- One LootSlot per call: the next unlocked slot, going down.
local function DrainStep()
	while fast.slot and fast.slot >= 1 do
		local slot = fast.slot
		fast.slot = slot - 1
		-- A slot whose state can't be read counts as locked and is skipped.
		local read, _, _, _, _, _, locked = pcall(GetLootSlotInfo, slot)
		if read and not E:IsSecret(locked) and not locked then
			LootSlot(slot)
			if fast.slot < 1 then StopDrain() end
			return
		end
	end
	StopDrain()
end

-- Take every unlocked slot: the first now, the rest one per tick.
local function DrainLoot()
	StopDrain()
	local count = GetNumLootItems() or 0
	if type(count) ~= "number" or E.Secret(count) or count < 1 then return end
	fast.slot = count
	DrainStep()
	if fast.slot and fast.slot >= 1 then fast.ticker = C_Timer.NewTicker(FAST_TICK, DrainStep) end
end
M.DrainLoot = DrainLoot

local function FastLoot(_, _, autoLoot)
	if not (M.db.fastLoot and E:BlizzardAllowed(LOOT_ID)) or E:StandsBack(M, "fastloot") then return end
	local count = GetNumLootItems() or 0
	if type(count) ~= "number" or E.Secret(count) then return end
	if fast.count == nil then
		if autoLoot == nil then autoLoot = GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE") end
		fast.auto = autoLoot and true or false
	elseif fast.count == count then
		return
	end
	fast.count = count
	if not fast.auto or MasterLoot() then return end
	DrainLoot()
end

-- Solo confirmation follows the clicked slot across the next frame, after
-- the native event handler has shown its matching question.
local bindPending, bindGeneration, bindOwner = {}, 0, {}

local function ClearBindConfirmations()
	bindGeneration = bindGeneration + 1
	for slot, timer in pairs(bindPending) do
		timer:Cancel()
		bindPending[slot] = nil
	end
end

local function SoloBindConfirm(_, _, slot)
	if not (M.active and M.db.skipBindConfirm and E:BlizzardAllowed(LOOT_ID)) then return end
	if E.PlainCall(IsInGroup) ~= false then return end
	slot = E.Plain(slot)
	local count = E.PlainCall(GetNumLootItems)
	if type(slot) ~= "number" or slot % 1 ~= 0 or slot < 1
		or type(count) ~= "number" or not (slot <= count and count < math.huge) then return end
	local link = E.PlainCall(GetLootSlotLink, slot)
	if type(link) ~= "string" or link == "" or bindPending[slot] then return end
	local generation = bindGeneration
	bindPending[slot] = C_Timer.NewTimer(0, function()
		bindPending[slot] = nil
		if generation ~= bindGeneration or not (M.active and M.db.skipBindConfirm and E:BlizzardAllowed(LOOT_ID)) then return end
		if E.PlainCall(IsInGroup) ~= false or E.PlainCall(GetLootSlotLink, slot) ~= link then return end
		local dialog = E.PlainCall(StaticPopup_FindVisible, "LOOT_BIND")
		if type(dialog) ~= "table" or (canaccesstable and not canaccesstable(dialog)) then return end
		if E.PlainCall(dialog.IsShown, dialog) ~= true or E.Plain(dialog.data) ~= slot then return end
		if generation ~= bindGeneration or not (M.active and M.db.skipBindConfirm and E:BlizzardAllowed(LOOT_ID))
			or E.PlainCall(IsInGroup) ~= false or type(ConfirmLootSlot) ~= "function" then return end
		local accepted, result = pcall(ConfirmLootSlot, slot)
		if accepted and not E.Secret(result) and result ~= false and generation == bindGeneration
			and E.PlainCall(StaticPopup_FindVisible, "LOOT_BIND") == dialog
			and E.Plain(dialog.data) == slot and type(StaticPopup_Hide) == "function" then
			StaticPopup_Hide("LOOT_BIND", slot)
		end
	end)
end

function M:ApplyBindConfirmations()
	ClearBindConfirmations()
	if self.active and self.db.skipBindConfirm and E:BlizzardAllowed(LOOT_ID) then
		E:RegisterEvent("LOOT_BIND_CONFIRM", SoloBindConfirm, bindOwner)
		E:RegisterEvent("LOOT_CLOSED", ClearBindConfirmations, bindOwner)
	else
		E:UnregisterEvent("LOOT_BIND_CONFIRM", bindOwner)
		E:UnregisterEvent("LOOT_CLOSED", bindOwner)
	end
end

-- A closed loot ends its drain and forgets its state.
E:RegisterEvent("LOOT_CLOSED", function()
	StopDrain()
	fast.count, fast.auto = nil, nil
end, fast)

---------------------------------------------------------------------------
-- Blizzard's loot window: hide, skin, move
---------------------------------------------------------------------------
local lootEventsOff = false
local lootHooked = false
local blizzLootScale
local skinnedLootRows = setmetatable({}, { __mode = "k" })

-- Hide or Replace: Blizzard's LootFrame stops listening for loot. Fully
-- undone by registering the two events again.
local function SetBlizzardLootEvents(listen)
	if not LootFrame then return end
	if listen and lootEventsOff then
		LootFrame:RegisterEvent("LOOT_OPENED")
		LootFrame:RegisterEvent("LOOT_CLOSED")
		lootEventsOff = false
	elseif not listen and not lootEventsOff then
		LootFrame:UnregisterEvent("LOOT_OPENED")
		LootFrame:UnregisterEvent("LOOT_CLOSED")
		lootEventsOff = true
	end
end

local function SkinLootRow(frame)
	if skinnedLootRows[frame] or not E:BlizzardAllowed(LOOT_ID, "skin") then return end
	skinnedLootRows[frame] = true
	E:SkinAlphaZero(frame.NameFrame, frame.BorderFrame, frame.QualityStripe, frame.HighlightNameFrame, frame.PushedNameFrame)
	E:SkinRow(frame, { stripe = 0.04 })
	local item = frame.Item
	if item then
		local icon = item.icon or item.Icon
		if icon and icon.SetTexCoord then E:TrimIcon(icon) end
		E:SkinAlphaZero(item.GetNormalTexture and item:GetNormalTexture())
	end
	if frame.Text and frame.Text.SetFont then E:SetFont(frame.Text, E.tokens.size.body) end
	if frame.QualityText and frame.QualityText.SetFont then E:SetFont(frame.QualityText, E.tokens.size.tiny) end
end

local function SkinBlizzardLoot()
	if not LootFrame or E:GetSkin(LootFrame, "panel") then return end
	E:SkinPanel(LootFrame)
	E:SkinCloseButton(LootFrame.ClosePanelButton)
	E:SkinScrollBar(LootFrame.ScrollBar)
	local box = LootFrame.ScrollBox
	if box then
		if box.GetUpperShadowTexture then E:SkinAlphaZero(box:GetUpperShadowTexture(), box:GetLowerShadowTexture()) end
		E:HookScrollBoxRows(box, SkinLootRow)
	end
end

-- After Blizzard opened its window (and placed it by Edit Mode), put it on
-- EldoUI's loot spot when the Move switch is on.
local function PlaceBlizzardLoot()
	if not LootFrame or not E:BlizzardAllowed(LOOT_ID, "move") or E:BlizzardHidden(LOOT_ID) then return end
	-- LootFrame is an Edit Mode system: the plain widget methods, so Edit
	-- Mode's overrides never run from EldoUI.
	local Keep = E.BlizzardKeep
	if not blizzLootScale then blizzLootScale = LootFrame:GetScale() end
	Keep.SetScale(LootFrame, M.db.blizzScale)
	if M.db.atCursor or not M.lootAnchor then return end -- the lootUnderMouse CVar places it
	Keep.ClearAllPoints(LootFrame)
	Keep.SetPoint(LootFrame, "TOPLEFT", M.lootAnchor, "TOPLEFT")
end

-- Restores one CVar EldoUI changed for this element (Core only restores all
-- of an element's CVars at once, when its master switch goes off).
local function RestoreCVar(name, id)
	local snapshot = EldoUIDB and EldoUIDB.cvarSnapshot
	local saved = snapshot and snapshot[name]
	if not saved or saved.owner ~= id then return end
	if saved.value ~= nil and C_CVar and C_CVar.SetCVar then C_CVar.SetCVar(name, saved.value) end
	snapshot[name] = nil
end

-- Another addon that loots faster: that part stands back while it runs.
function M:OnStandBack(feature)
	if feature == "fastloot" then self:ApplyLootWindow() end
end

function M:ApplyLootWindow()
	local own = self.active and E:BlizzardAllowed(LOOT_ID, "replace")
	-- EldoUI's window
	if own then
		if not self.lootFrame then self:CreateLootFrame() end
		local roomSession = self.lootFrame.roomSession
		if roomSession and roomSession.profile ~= self.db then
			self:EndLootRoomNotice()
			self:BeginLootRoomNotice()
		end
		self:RegisterEvent("LOOT_OPENED", function(_, _, autoLoot) self:ShowLoot(autoLoot) end)
		self:RegisterEvent("LOOT_SLOT_CLEARED", function(_, _, slot)
			for _, row in ipairs(self.lootFrame.rows) do
				if row.slot == slot then
					row.slot = nil
					E:SlideOut(row, "LEFT", function() self:LayoutLoot() end)
				end
			end
			self:UpdateTitleButtons()
		end)
		self:RegisterEvent("LOOT_SLOT_CHANGED", function(_, _, slot) self:UpdateLootSlot(slot) end)
		self:RegisterEvent("OPEN_MASTER_LOOT_LIST", function() self:OnMasterLootList() end)
		self:RegisterEvent("LOOT_CLOSED", function()
			self:EndLootRoomNotice()
			self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
			if self.masterMenu and E.UIKit.MenuShown() then E.UIKit.CloseMenu() end
			self.masterSlot, self.masterRow, self.masterMenu = nil, nil, nil
			-- The loot is over: hiding the window must not close it again.
			self.lootOpen = nil
			M.HideLootPopup("LOOT_BIND")
			M.HideLootPopup("CONFIRM_LOOT_DISTRIBUTION")
			E:SlideOut(self.lootFrame, "LEFT")
			GameTooltip:Hide()
		end)
		self:RefreshLootRows()
	else
		self:EndLootRoomNotice()
		for _, event in ipairs({ "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_SLOT_CHANGED", "LOOT_CLOSED", "GET_ITEM_INFO_RECEIVED", "OPEN_MASTER_LOOT_LIST" }) do
			self:UnregisterEvent(event)
		end
		if self.lootFrame then
			self.lootOpen = nil
			if self.lootFrame:IsShown() then self.lootFrame:Hide() end
		end
	end
	if not self.lootAnchor then
		-- The mover exists even without EldoUI's window: Blizzard's window uses it.
		self:CreateLootFrame()
	end
	if self.lootFrame then
		local r, g, b = unpack(E.media.accentColor)
		self.lootFrame.accent:SetColorTexture(r, g, b, 1)
	end
	self.lootAnchor:SetWidth(self.db.width)

	-- Blizzard's window
	SetBlizzardLootEvents(not (self.active and E:BlizzardHidden(LOOT_ID)))
	if self.active and E:BlizzardAllowed(LOOT_ID, "skin") then SkinBlizzardLoot() end
	if self.active and E:BlizzardAllowed(LOOT_ID, "move") then
		if not lootHooked and LootFrame and LootFrame.Open then
			lootHooked = true
			hooksecurefunc(LootFrame, "Open", PlaceBlizzardLoot)
		end
		E:SetCVar("lootUnderMouse", self.db.atCursor and 1 or 0, LOOT_ID)
		if LootFrame and LootFrame:IsShown() then PlaceBlizzardLoot() end
	else
		RestoreCVar("lootUnderMouse", LOOT_ID)
		if LootFrame and blizzLootScale then
			-- The plain widget method: Edit Mode's override never runs from EldoUI.
			E.BlizzardKeep.SetScale(LootFrame, blizzLootScale)
			blizzLootScale = nil
		end
	end

	-- Faster auto loot works with either window.
	if self.active and E:BlizzardAllowed(LOOT_ID) and self.db.fastLoot and not E:StandsBack(self, "fastloot") then
		self:RegisterEvent("LOOT_READY", FastLoot)
	else
		self:UnregisterEvent("LOOT_READY")
	end
end

---------------------------------------------------------------------------
-- EldoUI roll bars
---------------------------------------------------------------------------
local ROLL_NEED, ROLL_GREED, ROLL_DE, ROLL_PASS, ROLL_TRANSMOG = 1, 2, 3, 0, 4
local ROLL_BUTTONS = {
	{ type = ROLL_NEED, atlas = "lootroll-toast-icon-need-up", file = "Interface\\Buttons\\UI-GroupLoot-Dice-Up", label = NEED or Key("Need"), key = "canNeed" },
	{ type = ROLL_GREED, atlas = "lootroll-toast-icon-greed-up", file = "Interface\\Buttons\\UI-GroupLoot-Coin-Up", label = GREED or Key("Greed"), key = "canGreed" },
	{ type = ROLL_TRANSMOG, atlas = "lootroll-toast-icon-transmog-up", file = "Interface\\Buttons\\UI-GroupLoot-Coin-Up", label = TRANSMOGRIFY or Key("Transmog"), key = "canTransmog" },
	{ type = ROLL_DE, atlas = nil, file = "Interface\\Buttons\\UI-GroupLoot-DE-Up", label = ROLL_DISENCHANT or Key("Disenchant"), key = "canDisenchant" },
	{ type = ROLL_PASS, atlas = "lootroll-toast-icon-pass-up", file = "Interface\\Buttons\\UI-GroupLoot-Pass-Up", label = PASS or Key("Pass") },
}
local rollBars = {}
M.rollBars = rollBars -- exposed for inspection
local hideWarned = false
local MarkRollBar -- set below, with the loot history
local ROLL_TIME = {
	tick = "EldoUI.Loot.rolls", -- the shared ticker key of the roll timers
	step = 0.1,                 -- the timer bars move this often
	grace = 10,                 -- seconds a rolled bar waits for its result after the roll's time is up
	restored = 120,             -- seconds a bar rebuilt after a reload waits for its result
}

-- The time left on every open roll, ten times a second on the shared
-- ticker. Only while a roll is open: the last one to end stops it.

-- The timer's color: the accent, the bad color in the last quarter.
local function TimerColor(bar, left, total)
	local urgent = M.db.rollUrgent and total and total > 0 and left < total / 4 or false
	if bar.urgent == urgent then return end
	bar.urgent = urgent
	if urgent then
		bar.timer:SetStatusBarColor(E:TokenColor("bad"))
	else
		bar.timer:SetStatusBarColor(unpack(E.media.accentColor))
	end
end

local function RollTick()
	local open = false
	local now = GetTime()
	for _, bar in ipairs(rollBars) do
		if bar.rollID then
			open = true
			local left = GetLootRollTimeLeft(bar.rollID)
			-- A secret answer (an addon restriction is on): the bar keeps its time.
			if type(left) == "number" and not E:IsSecret(left) and left <= 0 then
				-- The roll's time is up: the bar ends (or waits for the winner)
				-- even when the game's end event is late.
				M:EndRoll(bar.rollID)
			elseif type(left) == "number" and not E:IsSecret(left) then
				bar.timer:SetValue(left)
				bar.endsAt = now + left / 1000
				local _, total = bar.timer:GetMinMaxValues()
				TimerColor(bar, left, total)
			end
		elseif bar.waiting and not bar.result then
			open = true
			local left = (bar.endsAt or now) - now
			bar.timer:SetValue(math.max(0, left * 1000))
			if left < -(bar.grace or ROLL_TIME.grace) then M:ReleaseRollBar(bar) end
		end
	end
	-- Once a second, the game's open rolls are checked against the bars.
	if open and now >= (M.nextRollSync or 0) and M.SyncRolls then
		M.nextRollSync = now + 1
		M:SyncRolls()
	end
	if not open then E.Ticker:Unsubscribe(ROLL_TIME.tick) end
end

local function WatchRolls()
	for _, bar in ipairs(rollBars) do
		if bar.rollID or (bar.waiting and not bar.result) then
			if not E.Ticker:IsSubscribed(ROLL_TIME.tick) then E.Ticker:Subscribe(ROLL_TIME.tick, ROLL_TIME.step, RollTick, M) end
			return
		end
	end
	E.Ticker:Unsubscribe(ROLL_TIME.tick)
end

local function RollTexture(button, info)
	if info.atlas and HasAtlas(info.atlas) then
		button:SetNormalAtlas(info.atlas)
		button:SetHighlightAtlas(info.atlas)
	else
		button:SetNormalTexture(info.file)
		button:SetHighlightTexture(info.file)
	end
	local highlight = button:GetHighlightTexture()
	if highlight then highlight:SetAlpha(0.4) end
end

local LayoutRolls
local rollViewportOwner
local rollViewportContext
local rollLayoutBusy = false
-- A roll can arrive while a layout is running (the game sends several at
-- once). The request is remembered and the layout runs once more after.
local rollLayoutAgain, rollLayoutRerun = false, false

local function RollNumber(value, positive)
	return not E:IsSecret(value) and type(value) == "number" and value == value
		and math.abs(value) < math.huge and (not positive or value > 0)
end

-- Sizes the client derives from two anchors come back as 32-bit floats
-- (239.99998 for 240 at some UI scales). Treat sizes within a hundredth of
-- a UI unit as the same, so that rounding never reads as a foreign change.
local ROLL_SIZE_TOLERANCE = 0.01

local function SameRollSize(a, b)
	return RollNumber(a) and RollNumber(b) and math.abs(a - b) <= ROLL_SIZE_TOLERANCE
end

local function RollRect(frame)
	local ok, left, bottom, width, height, scale = pcall(function()
		local l, b, w, h = frame:GetRect()
		return l, b, w, h, frame:GetEffectiveScale()
	end)
	local rootScale = UIParent:GetEffectiveScale()
	if not ok or not RollNumber(left) or not RollNumber(bottom) or not RollNumber(width, true)
		or not RollNumber(height, true) or not RollNumber(scale, true) or not RollNumber(rootScale, true) then return end
	local ratio = scale / rootScale
	if not RollNumber(ratio, true) then return end
	local rect = { left * ratio, bottom * ratio, (left + width) * ratio, (bottom + height) * ratio }
	for index = 1, 4 do if not RollNumber(rect[index]) then return end end
	return rect
end

local function RollPose(frame)
	local ok, pose = pcall(function()
		local p = { frame:GetParent(), frame:GetWidth(), frame:GetHeight(), frame:GetScale(), frame:IsShown(), {} }
		local count = frame:GetNumPoints()
		if not RollNumber(count) or count < 0 or count > 2 then return end
		for index = 1, count do
			local point = { frame:GetPoint(index) }
			for field = 1, 5 do if E:IsSecret(point[field]) then return end end
			p[6][index] = point
		end
		return p
	end)
	if not ok or not pose then return end
	for index = 1, 5 do if E:IsSecret(pose[index]) then return end end
	return pose
end

local function SameRollPose(frame, expected, alternateWidth, anchoredSize)
	local actual = expected and RollPose(frame)
	if not actual then return false end
	for index = 1, 5 do
		local sameSize = (index == 2 or index == 3) and SameRollSize(actual[index], expected[index])
		local sameAlternate = index == 2 and alternateWidth and SameRollSize(actual[index], alternateWidth)
		if not (anchoredSize and (index == 2 or index == 3)) and not sameSize and actual[index] ~= expected[index]
			and not sameAlternate then return false end
	end
	if #actual[6] ~= #expected[6] then return false end
	for index, point in ipairs(actual[6]) do
		for field = 1, 5 do if point[field] ~= expected[6][index][field] then return false end end
	end
	return true
end

local function RollRowOwned(bar, child)
	if bar:GetParent() ~= child or E:IsSecret(bar:GetScale()) or bar:GetScale() ~= bar.rollViewportScale then return false end
	local expected, count = bar.rollViewportPoint, bar:GetNumPoints()
	if E:IsSecret(count) then return false end
	if not expected then return count == 0 end
	if count ~= 1 then return false end
	local actual = { bar:GetPoint(1) }
	for field = 1, 5 do if E:IsSecret(actual[field]) or actual[field] ~= expected[field] then return false end end
	return true
end

local function RollViewportOwned()
	local own = rollViewportOwner
	return own and M.rollAnchor == own.anchor and M.rollViewport == own.area
		and E.modules.Loot == M and not E:IsSecret(own.anchor:GetScale()) and own.anchor:GetScale() == own.anchorScale
		and own.area:GetParent() == UIParent and own.area.scroll == own.scroll and own.area.child == own.child
		and own.scroll:GetParent() == own.area and own.scroll:GetScrollChild() == own.child and own.child:GetParent() == own.scroll
		and SameRollPose(own.area, own.pose) and SameRollPose(own.scroll, own.scrollPose, nil, true)
		and SameRollPose(own.child, own.childPose, own.writingWidth)
		and not E:IsSecret(own.scroll:GetHorizontalScroll()) and own.scroll:GetHorizontalScroll() == 0
end

-- The bars on screen, in the order their rolls started.
local function LiveRollRows()
	local rows = {}
	for _, bar in ipairs(rollBars) do
		if bar.rollID or bar.waiting or bar.rollPreview then rows[#rows + 1] = bar end
	end
	table.sort(rows, function(a, b) return (a.rollOrder or 0) < (b.rollOrder or 0) end)
	return rows
end

-- The visible viewport is separate from the one-row size handle.
function M:RollViewportBounds()
	if self ~= M then return nil, nil, "owner-changed" end
	local state = self.rollViewportState
	if not state or not state.qualified then return nil, nil, state and state.reason or "not-laid-out" end
	if state.rows == 0 then return nil, nil, "empty" end
	if not RollViewportOwned() then return nil, nil, "owner-changed" end
	local context = rollViewportContext
	if not context or E.db ~= context.profile or self.db ~= context.db
		or E:IsSecret(self.db.rollWidth) or E:IsSecret(self.db.rollHeight) or E:IsSecret(self.db.rollGrow)
		or self.db.rollWidth ~= context.width or self.db.rollHeight ~= context.height or self.db.rollGrow ~= context.growth then
		return nil, nil, "settings-changed"
	end
	if self.rollViewport.updating then return nil, nil, "scroll-update-incomplete" end
	local index = 0
	for _, bar in ipairs(LiveRollRows()) do
		do
			index = index + 1
			if not bar.rollViewportPoint or context.rows[index] ~= bar or not RollRowOwned(bar, self.rollViewport.child) then
				return nil, nil, "row-owner-changed"
			end
			local width, height = bar:GetSize()
			if not RollNumber(width, true) or not RollNumber(height, true) or width ~= context.width or height ~= context.height then
				return nil, nil, "row-size-changed"
			end
		end
	end
	if index ~= state.rows then return nil, nil, "rows-changed" end
	local rect, screen = RollRect(self.rollViewport), RollRect(UIParent)
	if not rect or not screen then return nil, nil, "geometry-unavailable" end
	local epsilon = 4 * 2 ^ -52 * math.max(1, math.abs(screen[3]), math.abs(screen[4]))
	if rect[1] < screen[1] - epsilon or rect[2] < screen[2] - epsilon
		or rect[3] > screen[3] + epsilon or rect[4] > screen[4] + epsilon then return nil, nil, "clamp-unverified" end
	return self.rollViewport, rect
end

function M:CreateRollAnchor()
	self.rollAnchor = CreateFrame("Frame", "EldoUI_LootRolls", UIParent)
	self.rollAnchor:SetSize(self.db.rollWidth, self.db.rollHeight)
	local options = { step = self.db.rollHeight + 4 }
	local area = E.UIKit.ScrollArea(UIParent, options)
	area:SetSize(self.db.rollWidth + E.UIKit.SCROLL_WIDTH + 4, self.db.rollHeight)
	area:SetFrameStrata("HIGH")
	area:SetClampedToScreen(true)
	area:Hide()
	self.rollViewport = area
	rollViewportOwner = { anchor = self.rollAnchor, anchorScale = self.rollAnchor:GetScale(), area = area,
		scroll = area.scroll, child = area.child, options = options, pose = RollPose(area),
		scrollPose = RollPose(area.scroll), childPose = RollPose(area.child) }
	E:AddMoverContent("EldoUI_LootRolls", area)
	E:CreateMover(self.rollAnchor, "EldoUI_LootRolls", L["Loot Rolls"], { "TOP", "UIParent", "TOP", 0, -260 },
		{ sizeKeys = { width = { key = "rollWidth", min = 240, max = 480 }, height = { key = "rollHeight", min = 28, max = 56 } },
			onMoved = function() if LayoutRolls then LayoutRolls() end end })
end

LayoutRolls = function()
	if rollLayoutBusy then rollLayoutAgain = true; return end
	M.rollViewportState = { qualified = false, reason = "geometry-unavailable" }
	if not RollViewportOwned() then M.rollViewportState.reason = "owner-changed"; return end
	local db, profile, own = M.db, E.db, rollViewportOwner
	local width, height, growth = db.rollWidth, db.rollHeight, db.rollGrow
	local function Current()
		return RollViewportOwned() and M.db == db and E.db == profile
			and not E:IsSecret(db.rollWidth) and not E:IsSecret(db.rollHeight) and not E:IsSecret(db.rollGrow)
			and db.rollWidth == width and db.rollHeight == height and db.rollGrow == growth
	end
	if not RollNumber(width, true) or not RollNumber(height, true) or E:IsSecret(growth)
		or (growth ~= "UP" and growth ~= "DOWN") then return end
	local rows = LiveRollRows()
	for _, bar in ipairs(rows) do
		if not RollRowOwned(bar, own.child) then M.rollViewportState.reason = "row-owner-changed"; return end
	end
	local area = own.area
	local function ViewWrite(method, ...)
		if not Current() then return false end
		local p, args = own.pose, { ... }
		local expected = { p[1], p[2], p[3], p[4], p[5], p[6] }
		if method == "SetSize" then expected[2], expected[3] = args[1], args[2]
		elseif method == "ClearAllPoints" then expected[6] = {}
		elseif method == "SetPoint" then expected[6] = { args }
		elseif method == "Show" then expected[5] = true
		elseif method == "Hide" then expected[5] = false end
		own.pose = expected
		local ok, failure = pcall(area[method], area, ...)
		if not ok then
			if SameRollPose(area, p) then own.pose = p end
			error(failure, 0)
		end
		return Current()
	end
	local function ChildHeight(value)
		if not Current() then return false end
		local previous = own.childPose[3]
		own.childPose[3] = value
		local ok, problem = pcall(own.child.SetHeight, own.child, value)
		if not ok then
			local read, current = pcall(own.child.GetHeight, own.child)
			if read and not E:IsSecret(current) and current == previous then own.childPose[3] = previous end
			error(problem, 0)
		end
		return Current()
	end
	local content, view
	if #rows > 0 then
		local screen, anchor = RollRect(UIParent), RollRect(own.anchor)
		if not screen or not anchor then return end
		content = #rows * (height + 4) - 4
		local available = growth == "UP" and screen[4] - anchor[2] or anchor[4] - screen[2]
		if not RollNumber(content, true) or not RollNumber(available) then return end
		-- The shared scroll range uses whole UI units. Round the capacity
		-- outward and the available view inward, without shrinking any row.
		content = math.ceil(content)
		-- Every open roll shows at once; only rolls that no longer fit on the
		-- screen scroll.
		view = math.max(math.ceil(height), math.min(content, math.floor(available)))
		if not RollNumber(view, true) then return end
	end
	rollLayoutBusy = true
	-- Update may size the child only after the viewport acquires its anchors.
	-- During this owned pass allow only its previous width or that exact target.
	own.writingWidth = #rows > 0 and width or own.childPose[2]
	local ok, failure = pcall(function()
		if #rows == 0 then
			local reset, problem = pcall(function()
				if not ChildHeight(1) then return end
				if Current() then area:Update();area:ScrollToTop() end
			end)
			local hidden = ViewWrite("Hide")
			if not reset then error(problem, 0) end
			if hidden then rollViewportContext = nil;M.rollViewportState = { qualified = true, rows = 0 } end
			return
		end
		local oldRange, offset = area:Range(), area.scroll:GetVerticalScroll() or 0
		own.options.step = height + 4
		if not ViewWrite("SetSize", width + E.UIKit.SCROLL_WIDTH + 4, view) or not ViewWrite("ClearAllPoints") then return end
		local edge = growth == "UP" and "BOTTOMLEFT" or "TOPLEFT"
		if not ViewWrite("SetPoint", edge, own.anchor, edge, 0, 0) then return end
		if not ChildHeight(content) then return end
		for index, bar in ipairs(rows) do
			if not Current() or not RollRowOwned(bar, own.child) then return end
			bar.rollViewportPoint = nil
			bar:ClearAllPoints()
			if not Current() or not RollRowOwned(bar, own.child) then return end
			local point = growth == "UP" and "BOTTOM" or "TOP"
			bar.rollViewportPoint = { point, area.child, point, 0, (index - 1) * (height + 4) * (growth == "UP" and 1 or -1) }
			bar:SetPoint(unpack(bar.rollViewportPoint))
			if not Current() or not RollRowOwned(bar, own.child) then return end
		end
		area:Update()
		if not Current() then return end
		if not rollViewportContext or rollViewportContext.growth ~= growth then
			offset = growth == "UP" and area:Range() or 0
		elseif growth == "UP" then offset = offset + area:Range() - oldRange end
		area:SetScroll(offset)
		if not Current() then return end
		if not ViewWrite("Show") then return end
		rollViewportContext = { profile = profile, db = db, width = width, height = height, growth = growth, rows = rows }
		local childWidth = own.child:GetWidth()
		if not SameRollSize(childWidth, width) then return end
		own.childPose[2], own.writingWidth = childWidth, nil
		M.rollViewportState = { qualified = true, rows = #rows, contentHeight = content, viewHeight = view }
		local frame, _, reason = M:RollViewportBounds()
		if not frame then M.rollViewportState.qualified, M.rollViewportState.reason = false, reason end
	end)
	if own.writingWidth then
		local read, current = pcall(own.child.GetWidth, own.child)
		if read and SameRollSize(current, own.writingWidth) then own.childPose[2] = current
		elseif not read and ok then ok, failure = false, current end
	end
	own.writingWidth = nil
	rollLayoutBusy = false
	local again = rollLayoutAgain
	rollLayoutAgain = false
	if not ok then M.rollViewportState = { qualified = false, reason = "layout-error" };error(failure, 0) end
	-- One more pass for a request made during this one; never more, so a
	-- request made by the layout itself cannot keep it running.
	if again and not rollLayoutRerun then
		rollLayoutRerun = true
		local done, problem = pcall(LayoutRolls)
		rollLayoutRerun = false
		if not done then error(problem, 0) end
	end
end

local function SizeRollBar(bar)
	local db = M.db
	local height = db.rollHeight
	bar:SetSize(db.rollWidth, height)
	bar.iconBox:SetSize(height - 4, height - 4)
	local buttonSize = math.max(18, math.min(30, height - 12))
	local x = -6
	for i = #bar.buttons, 1, -1 do
		local button = bar.buttons[i]
		button:SetSize(buttonSize, buttonSize)
		if button:IsShown() then
			button:ClearAllPoints()
			button:SetPoint("RIGHT", bar, "RIGHT", x, 0)
			x = x - buttonSize - 4
		end
	end
	if bar.status:IsShown() then x = math.min(-8, -bar.status:GetStringWidth() - 14) end
	-- A top anchor on both sides keeps the name one line high, above the
	-- Bind on Pickup line and the timer.
	bar.name:SetPoint("TOPRIGHT", bar, "TOPRIGHT", x - 2, -5)
	bar.timer:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", x - 2, 5)
end

local function CreateRollBar()
	if not M.rollAnchor then M:CreateRollAnchor() end
	local bar = CreateFrame("Frame", nil, M.rollViewport.child)
	bar.rollViewportScale = bar:GetScale()
	bar:SetFrameStrata("HIGH")
	E:SetTemplate(bar)
	bar.iconBox = IconBox(bar, 36)
	bar.iconBox:SetPoint("LEFT", 2, 0)
	bar.iconBox:EnableMouse(true)
	bar.iconBox:SetScript("OnEnter", function(self)
		if not bar.rollID then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetLootRollItem(bar.rollID)
		GameTooltip:Show()
	end)
	bar.iconBox:SetScript("OnLeave", GameTooltip_Hide)
	-- Shift-click links the item, like Blizzard's roll frame.
	bar.iconBox:SetScript("OnMouseUp", function()
		if bar.rollID and IsModifiedClick() then HandleModifiedItemClick(GetLootRollItemLink(bar.rollID)) end
	end)
	bar.name = E:CreateText(bar, E.tokens.size.body, "LEFT")
	bar.name:SetWordWrap(false)
	bar.name:SetPoint("TOPLEFT", bar.iconBox, "TOPRIGHT", 6, -3)
	bar.bop = E:CreateText(bar, E.tokens.size.tiny, "LEFT")
	bar.bop:SetWordWrap(false)
	bar.bop:SetPoint("BOTTOMLEFT", bar.iconBox, "BOTTOMRIGHT", 6, 12)
	bar.bop:SetPoint("BOTTOMRIGHT", bar.timer, "TOPRIGHT", 0, 3)
	bar.bop:SetTextColor(E:TokenColor("bad"))
	bar.timer = E:CreateStatusBar(bar)
	bar.timer:SetPoint("BOTTOMLEFT", bar.iconBox, "BOTTOMRIGHT", 6, 3)
	bar.timer:SetHeight(6)
	-- Item level in the icon's top; the roll's state or result where the
	-- buttons were, once the player has rolled.
	bar.iconBox.level = E:CreateText(bar.iconBox, E.tokens.size.tiny, "CENTER")
	bar.iconBox.level:SetPoint("TOP", 0, -2)
	bar.status = E:CreateText(bar, E.tokens.size.small, "RIGHT")
	bar.status:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
	bar.status:Hide()
	bar.buttons = {}
	for i, info in ipairs(ROLL_BUTTONS) do
		local button = CreateFrame("Button", nil, bar)
		RollTexture(button, info)
		button:SetMotionScriptsWhileDisabled(true)
		button.info = info
		-- The only place EldoUI rolls: the player's own click on this button.
		-- The bar remembers the choice to show while the others roll.
		button:SetScript("OnClick", function()
			if not bar.rollID then return end
			bar.choice = info.type
			RollOnLoot(bar.rollID, info.type)
		end)
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(E:Translate(info.label))
			if self.reason then GameTooltip:AddLine(self.reason, E:TokenColor("bad", true)) end
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", GameTooltip_Hide)
		bar.buttons[i] = button
	end
	bar:Hide()
	return bar
end

-- Upgrade arrow on a bar, through the Upgrades module's API.
local function UpdateBarArrow(bar)
	-- The Loot Guide's roll box (gain and a suggestion, advice only).
	if E.UpdateRollVerdict then E:UpdateRollVerdict(bar, bar.rollID) end
	if not E.SetUpgradeArrow then return end
	local link = M.db.rollArrows and bar.rollID and GetLootRollItemLink and GetLootRollItemLink(bar.rollID) or nil
	if E:IsSecret(link) then link = nil end
	E:SetUpgradeArrow(bar.iconBox, link, { noTint = true })
end

function M:RefreshRollArrows()
	for _, bar in ipairs(rollBars) do
		if bar.rollID then UpdateBarArrow(bar) end
	end
end

---------------------------------------------------------------------------
-- After the roll: the game's loot history (C_LootHistory) lists each drop
-- with every player's choice and, once everyone has rolled, the winner.
-- A bar finds its drop by the item (its ID and random suffix) among the
-- drops no other bar holds, newest encounter first.
---------------------------------------------------------------------------
local STATE = Enum and Enum.EncounterLootDropRollState or {}
-- A choice's name: the client's own string, else EldoUI's text. Read when
-- shown, like every other text of the bar.
local ROLL_LABEL = {
	need = { "NEED", Key("Need") },
	greed = { "GREED", Key("Greed") },
	transmog = { "TRANSMOGRIFY", Key("Transmog") },
	pass = { "PASS", Key("Pass") },
}
local STATE_LABEL = {
	[STATE.NeedMainSpec or 0] = ROLL_LABEL.need,
	[STATE.NeedOffSpec or 1] = { nil, Key("Need (off spec)") },
	[STATE.Transmog or 2] = ROLL_LABEL.transmog,
	[STATE.Greed or 3] = ROLL_LABEL.greed,
	[STATE.Pass or 5] = ROLL_LABEL.pass,
}
local CHOICE_LABEL = {
	[ROLL_NEED] = ROLL_LABEL.need, [ROLL_GREED] = ROLL_LABEL.greed, [ROLL_TRANSMOG] = ROLL_LABEL.transmog,
	[ROLL_DE] = { "ROLL_DISENCHANT", Key("Disenchant") }, [ROLL_PASS] = ROLL_LABEL.pass,
}
local function LabelText(label)
	if not label then return nil end
	local text = label[1] and rawget(_G, label[1])
	if type(text) == "string" and text ~= "" then return text end
	return E:Translate(label[2])
end

-- The group's choices on a bar, in this order; Need counts main and off
-- spec together. Forever's history has no Disenchant state.
local GROUP_CHOICES = {
	{ label = ROLL_LABEL.need, atlas = "lootroll-toast-icon-need-up", file = "Interface\\Buttons\\UI-GroupLoot-Dice-Up" },
	{ label = ROLL_LABEL.transmog, atlas = "lootroll-toast-icon-transmog-up", file = "Interface\\Buttons\\UI-GroupLoot-Coin-Up" },
	{ label = ROLL_LABEL.greed, atlas = "lootroll-toast-icon-greed-up", file = "Interface\\Buttons\\UI-GroupLoot-Coin-Up" },
	{ label = ROLL_LABEL.pass, atlas = "lootroll-toast-icon-pass-up", file = "Interface\\Buttons\\UI-GroupLoot-Pass-Up" },
}
local CHOICE_GROUP = {
	[STATE.NeedMainSpec or 0] = 1, [STATE.NeedOffSpec or 1] = 1, [STATE.Transmog or 2] = 2,
	[STATE.Greed or 3] = 3, [STATE.Pass or 5] = 4,
}
local NO_ROLL = STATE.NoRoll or 4

-- Pointing at the counts: the names per choice and who has not chosen.
local function ChoicesTooltip(frame)
	GameTooltip:SetOwner(frame, "ANCHOR_TOP")
	GameTooltip:SetText(L["Group choices"])
	local r, g, b = E:TokenColor("body")
	for index, choice in ipairs(GROUP_CHOICES) do
		local list = frame.names[index]
		if list and #list > 0 then
			GameTooltip:AddLine(LabelText(choice.label) .. ": " .. table.concat(list, ", "), r, g, b, true)
		end
	end
	if #frame.waiting > 0 then
		GameTooltip:AddLine(L["Not chosen yet: %s"]:format(table.concat(frame.waiting, ", ")), E:TokenColor("secondary", true))
	end
	GameTooltip:Show()
end

local function BuildChoices(bar)
	local frame = CreateFrame("Frame", nil, bar)
	frame:SetSize(1, 12)
	frame:SetPoint("BOTTOMRIGHT", bar.timer, "TOPRIGHT", 0, 1)
	frame:EnableMouse(true)
	frame:SetScript("OnEnter", ChoicesTooltip)
	frame:SetScript("OnLeave", GameTooltip_Hide)
	frame.slots, frame.names, frame.waiting = {}, {}, {}
	for index, choice in ipairs(GROUP_CHOICES) do
		local slot = {}
		slot.icon = frame:CreateTexture(nil, "ARTWORK")
		slot.icon:SetSize(12, 12)
		if HasAtlas(choice.atlas) then slot.icon:SetAtlas(choice.atlas) else slot.icon:SetTexture(choice.file) end
		slot.count = E:CreateText(frame, E.tokens.size.tiny, "LEFT")
		frame.slots[index] = slot
	end
	frame:Hide()
	bar.choices = frame
	return frame
end

-- The Bind on Pickup line ends where the counts begin.
local function PlaceBoP(bar)
	bar.bop:SetPoint("BOTTOMLEFT", bar.iconBox, "BOTTOMRIGHT", 6, 12)
	if bar.choices and bar.choices:IsShown() then
		bar.bop:SetPoint("BOTTOMRIGHT", bar.choices, "BOTTOMLEFT", -6, 2)
	else
		bar.bop:SetPoint("BOTTOMRIGHT", bar.timer, "TOPRIGHT", 0, 3)
	end
end

-- The counts so far, right to left: Pass at the right end. A decided bar
-- shows its result instead.
local function UpdateChoices(bar, drop)
	local frame = bar.choices
	if not (M.db.rollChoices and drop and type(drop.rollInfos) == "table") or bar.result then
		if frame then frame:Hide() end
		bar.bop:ClearAllPoints()
		PlaceBoP(bar)
		return
	end
	frame = frame or BuildChoices(bar)
	local counts, names, waiting = {}, {}, {}
	for _, info in ipairs(drop.rollInfos) do
		local state = type(info) == "table" and info.state or nil
		local name = type(info) == "table" and info.playerName or nil
		if not E:IsSecret(state) and not E:IsSecret(name) and type(state) == "number" and type(name) == "string" then
			local group = CHOICE_GROUP[state]
			local shown = ClassColored(name, info.playerClass)
			if group then
				counts[group] = (counts[group] or 0) + 1
				names[group] = names[group] or {}
				table.insert(names[group], shown)
			elseif state == NO_ROLL then
				waiting[#waiting + 1] = shown
			end
		end
	end
	local x, any = 0, false
	for index = #GROUP_CHOICES, 1, -1 do
		local slot, count = frame.slots[index], counts[index]
		slot.count:ClearAllPoints()
		slot.icon:ClearAllPoints()
		if count then
			any = true
			slot.count:SetText(count)
			slot.count:SetPoint("RIGHT", frame, "RIGHT", x, 0)
			x = x - math.ceil(slot.count:GetStringWidth()) - 1
			slot.icon:SetPoint("RIGHT", frame, "RIGHT", x, 0)
			x = x - 12 - 6
		end
		slot.count:SetShown(count ~= nil)
		slot.icon:SetShown(count ~= nil)
	end
	frame:SetWidth(math.max(1, -x))
	frame.names, frame.waiting = names, waiting
	frame:SetShown(any)
	bar.bop:ClearAllPoints()
	PlaceBoP(bar)
end

-- The item's ID and random suffix from a link, the part a roll and its
-- history entry share.
local function ItemKey(link)
	if type(link) ~= "string" or E:IsSecret(link) then return nil end
	local body = link:match("item:([^|]+)")
	if not body then return nil end
	local fields = {}
	for field in (body .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = field end
	return fields[1] .. ":" .. (fields[7] or "")
end

-- Every drop in the game's loot history, newest encounter first.
local function HistoryDrops()
	local history = C_LootHistory
	if not (history and history.GetAllEncounterInfos and history.GetSortedDropsForEncounter) then return {} end
	local ok, encounters = pcall(history.GetAllEncounterInfos)
	if not ok or type(encounters) ~= "table" then return {} end
	local list = {}
	for _, encounter in ipairs(encounters) do
		if type(encounter) == "table" and type(encounter.encounterID) == "number" then list[#list + 1] = encounter end
	end
	table.sort(list, function(a, b) return (tonumber(a.startTime) or 0) > (tonumber(b.startTime) or 0) end)
	local out = {}
	for _, encounter in ipairs(list) do
		local okDrops, drops = pcall(history.GetSortedDropsForEncounter, encounter.encounterID)
		if okDrops and type(drops) == "table" then
			for _, drop in ipairs(drops) do
				if type(drop) == "table" and type(drop.lootListKey) == "number" then
					out[#out + 1] = { encounterID = encounter.encounterID, drop = drop }
				end
			end
		end
	end
	return out
end

local function DropKey(encounterID, lootListKey) return encounterID .. ":" .. lootListKey end

-- The bar's drop, found once and then read fresh each time.
local function BarDrop(bar)
	local history = C_LootHistory
	if bar.dropEncounter and history and history.GetSortedInfoForDrop then
		local ok, drop = pcall(history.GetSortedInfoForDrop, bar.dropEncounter, bar.dropList)
		if ok and type(drop) == "table" then return drop end
	end
	local key = ItemKey(bar.link)
	if not key then return nil end
	local held = {}
	for _, other in ipairs(rollBars) do
		if other ~= bar and other.dropEncounter then held[DropKey(other.dropEncounter, other.dropList)] = true end
	end
	-- In the newest encounter that has the item: a drop still rolling
	-- first, else one already decided (the player may have rolled last).
	local open, decided, encounter
	for _, entry in ipairs(HistoryDrops()) do
		if encounter and entry.encounterID ~= encounter then break end
		local drop = entry.drop
		if not held[DropKey(entry.encounterID, drop.lootListKey)] and ItemKey(drop.itemHyperlink) == key then
			encounter = entry.encounterID
			if drop.winner or drop.allPassed then
				decided = decided or entry
			else
				open = open or entry
			end
		end
	end
	local found = open or decided
	if not found then return nil end
	bar.dropEncounter, bar.dropList = found.encounterID, found.drop.lootListKey
	return found.drop
end

-- Icon border and item level: the quality color, green for an upgrade
-- (Upgrades), the accent for a look not collected yet (Appearances).
MarkRollBar = function(bar)
	local db = M.db
	local link = bar.link
	local serial, rollID = bar.serial, bar.rollID
	local function Current()
		return bar.serial == serial and bar.rollID == rollID and bar.link == link
	end
	local r, g, b = QualityColor(bar.quality)
	if db.rollMarkBorder and link then
		local upgrade = E.GetItemUpgrade and E:GetItemUpgrade(link)
		if not Current() then return end
		if upgrade and upgrade.upgrade then
			r, g, b = E:TokenColor("good")
		elseif E.Appearances and E.Appearances.State then
			local ok, state = pcall(E.Appearances.State, E.Appearances, link)
			if not Current() then return end
			if ok and state == "unknown" then r, g, b = E:TokenColor("accent") end
		end
	end
	local level = ""
	if db.rollItemLevel and link then
		local _, _, _, _, _, _, _, _, equipLoc, _, _, classID = C_Item.GetItemInfo(link)
		if not Current() then return end
		if (classID == 2 or classID == 4) and type(equipLoc) == "string" and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" then
			local itemLevel = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
			if not Current() then return end
			if type(itemLevel) == "number" and not E:IsSecret(itemLevel) then level = tostring(itemLevel) end
		end
	end
	if not Current() then return end
	bar.iconBox:SetBackdropBorderColor(r, g, b, 1)
	if not Current() then return end
	bar.iconBox.level:SetText(level)
end

-- A bar for a new roll: a free one, or a new one. Bars stand in the order
-- their rolls started, so a new roll joins at the end instead of taking a
-- freed place above rolls already on screen.
function M:FreeRollBar()
	local bar
	for _, b in ipairs(rollBars) do
		if not b.rollID and not b.waiting and not b.rollPreview then bar = b break end
	end
	if not bar then
		bar = CreateRollBar()
		table.insert(rollBars, bar)
	end
	bar.serial = (bar.serial or 0) + 1
	M.rollOrder = (M.rollOrder or 0) + 1
	bar.rollOrder = M.rollOrder
	bar.choice, bar.result, bar.waiting, bar.grace, bar.rollPreview = nil, nil, nil, nil, nil
	bar.dropEncounter, bar.dropList, bar.needsInfo, bar.askedItem, bar.infoFailure = nil, nil, nil, nil, nil
	bar.status:SetText("")
	bar.status:Hide()
	bar.timer:Show()
	bar.iconBox:SetAlpha(1)
	bar.name:SetAlpha(1)
	if bar.choices then bar.choices:Hide() end
	return bar
end

function M:ReleaseRollBar(bar)
	bar.rollID, bar.waiting, bar.result, bar.choice, bar.rollPreview = nil, nil, nil, nil, nil
	bar.dropEncounter, bar.dropList, bar.needsInfo = nil, nil, nil
	if E.UpdateRollVerdict then E:UpdateRollVerdict(bar, nil) end
	E:SlideOut(bar, "RIGHT", LayoutRolls)
end

-- What the bar says while the others roll.
local function WaitingText(choice)
	local label = LabelText(choice)
	local text = E:TextHex("secondary") .. L["Rolling..."]
	if label then text = text .. " |r" .. label else text = text .. "|r" end
	return text
end

-- The player rolled: the buttons give way to the choice and, later, the
-- winner. The timer keeps counting the others' time.
function M:WaitForRoll(bar, grace)
	bar.rollID = nil
	bar.waiting = true
	bar.grace = grace
	for _, button in ipairs(bar.buttons) do button:Hide() end
	bar.iconBox:SetAlpha(0.6)
	bar.name:SetAlpha(0.6)
	bar.status:SetText(WaitingText(bar.choiceLabel or CHOICE_LABEL[bar.choice]))
	bar.status:Show()
	SizeRollBar(bar)
	if E.UpdateRollVerdict then E:UpdateRollVerdict(bar, nil) end
	self:CheckRollResults()
	WatchRolls()
end

function M:ShowRollResult(bar, drop)
	local db = self.db
	local text, hold
	if drop.allPassed then
		text, hold = E:TextHex("secondary") .. L["Everyone passed"] .. "|r", db.rollLostTime
	else
		local winner = drop.winner
		if type(winner) ~= "table" or E:IsSecret(winner.playerName) or type(winner.playerName) ~= "string" then return end
		local how = LabelText(STATE_LABEL[winner.state]) or ""
		if type(winner.roll) == "number" and not E:IsSecret(winner.roll) then
			how = how ~= "" and (how .. " " .. winner.roll) or tostring(winner.roll)
		end
		if winner.isSelf then
			text, hold = E:TextHex("good") .. L["You won"] .. "|r", db.rollWonTime
		else
			text, hold = L["%s won"]:format(ClassColored(winner.playerName, winner.playerClass)), db.rollLostTime
		end
		if how ~= "" then text = text .. " " .. E:TextHex("secondary") .. how .. "|r" end
	end
	bar.result = true
	bar.status:SetText(text)
	bar.timer:Hide()
	UpdateChoices(bar, nil)
	SizeRollBar(bar)
	local serial = bar.serial
	C_Timer.After(hold, function()
		if bar.serial == serial and bar.result then self:ReleaseRollBar(bar) end
	end)
end

-- LOOT_HISTORY_UPDATE_DROP: every bar takes the group's choices so far,
-- and a waiting bar its winner.
function M:CheckRollResults()
	for _, bar in ipairs(rollBars) do
		if bar.rollID then
			UpdateChoices(bar, BarDrop(bar))
		elseif bar.waiting and not bar.result then
			local drop = BarDrop(bar)
			UpdateChoices(bar, drop)
			if drop then
				local state = drop.playerRollState
				if STATE_LABEL[state] and not E:IsSecret(state) then
					bar.choiceLabel = STATE_LABEL[state]
					bar.status:SetText(WaitingText(bar.choiceLabel))
				end
				if drop.winner or drop.allPassed then self:ShowRollResult(bar, drop) end
			end
		end
	end
end

-- After a reload: the drops the player already rolled on, still open,
-- come back as waiting bars.
function M:RestoreWaitingRolls()
	local history = C_LootHistory
	if not (self.db.rollKeep and history and history.GetLootHistoryTime) then return end
	local ok, now = pcall(history.GetLootHistoryTime)
	if not ok or type(now) ~= "number" then return end
	local held = {}
	for _, bar in ipairs(rollBars) do
		if bar.dropEncounter then held[DropKey(bar.dropEncounter, bar.dropList)] = true end
	end
	for _, entry in ipairs(HistoryDrops()) do
		local drop = entry.drop
		local state = drop.playerRollState
		local link = drop.itemHyperlink
		if STATE_LABEL[state] and not E:IsSecret(state) and not drop.winner and not drop.allPassed
			and not held[DropKey(entry.encounterID, drop.lootListKey)] and type(link) == "string" and not E:IsSecret(link)
			and (tonumber(drop.startTime) or 0) + (tonumber(drop.duration) or 0) > now then
			local name, _, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(link)
			if name then
				local bar = self:FreeRollBar()
				bar.link, bar.quality = link, quality
				bar.dropEncounter, bar.dropList = entry.encounterID, drop.lootListKey
				bar.choiceLabel = STATE_LABEL[state]
				bar.endsAt = GetTime()
				SizeRollBar(bar)
				bar.iconBox.icon:SetTexture(texture)
				bar.iconBox.count:SetText("")
				MarkRollBar(bar)
				local r, g, b = QualityColor(quality)
				bar.name:SetText(name)
				bar.name:SetTextColor(r, g, b)
				bar.bop:SetText("")
				bar.timer:Hide()
				if E.SetUpgradeArrow then E:SetUpgradeArrow(bar.iconBox, nil) end
				self:WaitForRoll(bar, ROLL_TIME.restored)
				LayoutRolls()
				E:SlideIn(bar, "RIGHT")
			end
		end
	end
end

-- The game can start a roll before the item's details have reached the
-- client (often when several items go up for roll at once). When the roll
-- names its item, EldoUI asks the client for it and builds the bar once
-- its details are ready. Item events wake it immediately; one shared
-- retry keeps rolls moving when the item was cached before the roll data.
-- Pending rolls are watched only while their time remains.
local ROLL_RETRY = 0.25
local PENDING_ROLL_TICK = "EldoUI.Loot.pending"
local pendingRolls = {} -- [rollID] = { rollTime, item, reading }
local RetryPendingRolls

-- The time left in milliseconds, or nil once the roll is over. While an
-- addon restriction is on the game answers with a secret value: the roll
-- is still open, its time unknown (returns true).
local function RollTimeLeft(rollID)
	local left = GetLootRollTimeLeft(rollID)
	if E:IsSecret(left) then return true end
	if type(left) ~= "number" or left <= 0 then return nil end
	return left
end

-- A value EldoUI may compare or count with: nil for a secret one.
local function Plain(value)
	if E:IsSecret(value) then return nil end
	return value
end

local function RollItemID(rollID)
	local link = GetLootRollItemLink and Plain(GetLootRollItemLink(rollID))
	if type(link) ~= "string" or E:IsSecret(link) then return nil end
	return tonumber(link:match("|Hitem:(%d+)"))
end

local function WatchPendingRolls()
	if not (M.active and E:BlizzardAllowed(ROLL_ID, "replace")) then wipe(pendingRolls) end
	if next(pendingRolls) then
		if not E.Ticker:IsSubscribed(PENDING_ROLL_TICK) then
			E.Ticker:Subscribe(PENDING_ROLL_TICK, ROLL_RETRY, RetryPendingRolls, M)
		end
	else
		E.Ticker:Unsubscribe(PENDING_ROLL_TICK)
	end
end

local function OwnsPendingRoll(rollID, wait)
	if pendingRolls[rollID] ~= wait then return false end
	local own = M.active and E:BlizzardAllowed(ROLL_ID, "replace")
	return own and pendingRolls[rollID] == wait
end

-- A read can deliver another roll event before returning. Keep its record
-- until the bar is complete so a nested start cannot admit the same roll.
local function BeginRollRead(rollID, rollTime, expected)
	if not (M.active and E:BlizzardAllowed(ROLL_ID, "replace")) then return nil end
	local wait = pendingRolls[rollID]
	if expected and wait ~= expected then return nil end
	if wait and wait.reading then return nil end
	for _, bar in ipairs(rollBars) do if bar.rollID == rollID then return nil end end
	wait = wait or {}
	wait.rollTime = rollTime or wait.rollTime
	wait.reading = true
	wait.bar, wait.serial, wait.link = nil, nil, nil
	pendingRolls[rollID] = wait
	return wait
end

local function FinishRollRead(wait)
	wait.reading = nil
	WatchPendingRolls()
end

local function ContinueRollRead(rollID, wait, bar, serial)
	local sameBar = not bar or (bar.rollID == rollID and bar.serial == serial and bar.link == wait.link)
	if OwnsPendingRoll(rollID, wait) and sameBar then return true end
	if pendingRolls[rollID] == wait then pendingRolls[rollID] = nil end
	if bar and sameBar then M:ReleaseRollBar(bar) end
	FinishRollRead(wait)
	return false
end

-- A failed read stays visible to the caller and leaves this roll retryable.
-- A newer roll or reused bar keeps its own state when the old call unwinds.
local function RunRollRead(read, self, rollID, wait)
	local ok, failure = pcall(read, self, rollID, wait)
	if ok then return end
	local cleaned, cleanupFailure = pcall(function()
		if pendingRolls[rollID] == wait then
			local bar = wait.bar
			if bar and bar.rollID == rollID and bar.serial == wait.serial and bar.link == wait.link then self:ReleaseRollBar(bar) end
		end
	end)
	local finished, finishFailure = pcall(FinishRollRead, wait)
	if not cleaned then failure = tostring(failure) .. "\n" .. tostring(cleanupFailure) end
	if not finished then failure = tostring(failure) .. "\n" .. tostring(finishFailure) end
	error(failure, 0)
end

local function PendingRollSnapshot(itemID)
	local pending = {}
	for rollID, wait in pairs(pendingRolls) do
		if not itemID or wait.item == itemID then pending[#pending + 1] = { rollID, wait } end
	end
	return pending
end

local function ResumePendingRoll(rollID, wait)
	if wait.reading or not OwnsPendingRoll(rollID, wait) then return end
	local left = RollTimeLeft(rollID)
	if not OwnsPendingRoll(rollID, wait) then return end
	if left then M:StartRoll(rollID, wait.rollTime, wait)
	else pendingRolls[rollID] = nil end
end

local function TryResumePendingRoll(rollID, wait)
	local ok, failure = pcall(ResumePendingRoll, rollID, wait)
	if not ok and failure ~= wait.lastFailure then
		wait.lastFailure = failure
		geterrorhandler()(failure)
	end
end

local function SyncOpenRoll(rollID)
	local wait = pendingRolls[rollID]
	if wait then
		TryResumePendingRoll(rollID, wait)
	else
		M:StartRoll(rollID)
	end
end

RetryPendingRolls = function()
	for _, entry in ipairs(PendingRollSnapshot()) do TryResumePendingRoll(entry[1], entry[2]) end
	WatchPendingRolls()
end

-- An item the client was asked for arrived: the rolls waiting on it go on.
local function ItemArrived(_, _, itemID, success)
	if type(itemID) ~= "number" or E:IsSecret(itemID) then return end
	for _, entry in ipairs(PendingRollSnapshot(itemID)) do
		local rollID, wait = entry[1], entry[2]
		if pendingRolls[rollID] == wait then
			if not E:IsSecret(success) and success == false then
				wait.item = nil
			else TryResumePendingRoll(rollID, wait) end
		end
	end
	WatchPendingRolls()
end
E:RegisterEvent("GET_ITEM_INFO_RECEIVED", ItemArrived, pendingRolls)

local function RetryRollRead(_, rollID, wait)
	local left = RollTimeLeft(rollID)
	if not ContinueRollRead(rollID, wait) then return end
	if not left then
		pendingRolls[rollID] = nil
		FinishRollRead(wait)
		return
	end
	local itemID = RollItemID(rollID)
	if not ContinueRollRead(rollID, wait) then return end
	if itemID and C_Item and C_Item.RequestLoadItemDataByID then
		if wait.item ~= itemID then
			wait.item = itemID
			local ok = pcall(C_Item.RequestLoadItemDataByID, itemID)
			if not ok and pendingRolls[rollID] == wait then wait.item = nil end
		end
	else wait.item = nil end
	FinishRollRead(wait)
end

function M:RetryRoll(rollID, rollTime, expected)
	local wait = BeginRollRead(rollID, rollTime, expected)
	if not wait then return end
	RunRollRead(RetryRollRead, self, rollID, wait)
end

local StartRollRead
do
	-- What the game says about a roll's item. Values EldoUI tests or compares
	-- come back plain or nil; the name and icon go to the bar as the game
	-- gives them. `known` is false while the client has not loaded the item
	-- (or the read failed): the bar shows at once and fills in later.
	local function ReadRollItem(rollID)
		local ok, texture, name, count, quality, bindOnPickUp, canNeed, canGreed, canDisenchant,
			reasonNeed, reasonGreed, reasonDisenchant, _, canTransmog = pcall(GetLootRollItemInfo, rollID)
		if not ok then return { known = false, failure = texture } end
		local known = E:IsSecret(name) or (type(name) == "string" and name ~= "")
		if E:IsSecret(canTransmog) then canTransmog = false end
		if E:IsSecret(canDisenchant) then canDisenchant = false end
		if E:IsSecret(canNeed) then canNeed = true end
		if E:IsSecret(canGreed) then canGreed = true end
		if not known then
			-- Until the item is known the game's own checks decide: Need, Greed
			-- and Pass are offered, Transmog and Disenchant are not.
			canNeed, canGreed, canDisenchant, canTransmog = true, true, false, false
		end
		return {
			known = known, texture = texture, name = known and name or nil,
			count = Plain(count), quality = Plain(quality), bindOnPickUp = Plain(bindOnPickUp),
			canNeed = canNeed and true or false, canGreed = canGreed and true or false,
			canDisenchant = canDisenchant and true or false, canTransmog = canTransmog and true or false,
			reasonNeed = Plain(reasonNeed), reasonGreed = Plain(reasonGreed), reasonDisenchant = Plain(reasonDisenchant),
		}
	end

	-- The bar's item part: name, icon, count, color, binding and which roll
	-- buttons are open. A roll whose item is not known yet says so and keeps
	-- Need, Greed and Pass; the details come in once the client has them.
	local function FillRollBar(bar, item)
		local can = { canNeed = item.canNeed, canGreed = item.canGreed and not item.canTransmog,
			canDisenchant = item.canDisenchant, canTransmog = item.canTransmog }
		local reasons = { canNeed = item.reasonNeed, canGreed = item.reasonGreed, canDisenchant = item.reasonDisenchant }
		for _, button in ipairs(bar.buttons) do
			local key = button.info.key
			local shown = true
			-- Like Blizzard: Transmog takes Greed's place, Disenchant shows only when offered.
			if key == "canTransmog" then shown = item.canTransmog end
			if key == "canGreed" then shown = not item.canTransmog end
			if key == "canDisenchant" then shown = item.canDisenchant end
			button:SetShown(shown)
			local enabled = not key or can[key] and true or false
			button:SetEnabled(enabled)
			button:SetAlpha(enabled and 1 or 0.4)
			local normal = button:GetNormalTexture()
			if normal then normal:SetDesaturated(not enabled) end
			local reason = key and reasons[key]
			button.reason = not enabled and reason and _G["LOOT_ROLL_INELIGIBLE_REASON" .. reason] or nil
		end
		SizeRollBar(bar)
		local texture = item.texture
		if not E:IsSecret(texture) and not texture then texture = E:ClientIcon(134400) end
		bar.iconBox.icon:SetTexture(texture)
		local count = item.count
		bar.iconBox.count:SetText(type(count) == "number" and count > 1 and count or "")
		bar.quality = item.quality
		local r, g, b = QualityColor(item.quality)
		if item.known then
			bar.name:SetText(item.name)
			bar.name:SetTextColor(r, g, b)
		else
			bar.name:SetText(E:GameText(rawget(_G, "RETRIEVING_ITEM_INFO"), L["Retrieving item information"]))
			bar.name:SetTextColor(E:TokenColor("secondary"))
		end
		bar.bop:SetText(M.db.rollBoP and item.bindOnPickUp and (E:GameText(ITEM_BIND_ON_PICKUP, L["Binds when picked up"])) or "")
		bar.needsInfo = not item.known or nil
	end

	-- Bars whose item the client had not loaded: ask for it, and fill the bar
	-- in as soon as the game knows it (item event, or a short shared retry).
	local ROLL_INFO_TICK = "EldoUI.Loot.rollInfo"
	local RefreshRollInfo

	local function AskForRollItem(bar)
		local itemID = RollItemID(bar.rollID)
		if itemID and itemID ~= bar.askedItem and C_Item and C_Item.RequestLoadItemDataByID then
			bar.askedItem = itemID
			-- A request that fails is made again on the next retry.
			if not pcall(C_Item.RequestLoadItemDataByID, itemID) and bar.askedItem == itemID then bar.askedItem = nil end
		end
	end

	local function OwnsRollBars()
		return M.active and E:BlizzardAllowed(ROLL_ID, "replace")
	end

	-- A read can deliver an item event that refreshes again; that refresh
	-- runs once the current one is done instead of inside it.
	local refreshing, refreshAgain
	local function RefreshPass()
		local waiting = false
		for _, bar in ipairs(rollBars) do
			if not OwnsRollBars() then return false end
			local rollID, serial = bar.rollID, bar.serial
			if rollID and bar.needsInfo then
				local item = ReadRollItem(rollID)
				if not OwnsRollBars() then return false end
				if bar.rollID ~= rollID or bar.serial ~= serial then item = { known = false } end
				if item.failure ~= nil and item.failure ~= bar.infoFailure then
					bar.infoFailure = item.failure
					geterrorhandler()(item.failure)
				end
				if item.known then
					bar.link = GetLootRollItemLink and Plain(GetLootRollItemLink(bar.rollID)) or nil
					FillRollBar(bar, item)
					MarkRollBar(bar)
					UpdateBarArrow(bar)
					UpdateChoices(bar, BarDrop(bar))
				elseif bar.rollID == rollID and bar.serial == serial then
					AskForRollItem(bar)
					waiting = true
				end
			end
		end
		return waiting
	end

	RefreshRollInfo = function()
		if refreshing then refreshAgain = true return end
		refreshing = true
		local ok, waiting, failure
		repeat
			refreshAgain = nil
			ok, failure = pcall(RefreshPass)
			waiting = ok and failure
		until not refreshAgain or not ok
		refreshing = nil
		if waiting and OwnsRollBars() then
			if not E.Ticker:IsSubscribed(ROLL_INFO_TICK) then E.Ticker:Subscribe(ROLL_INFO_TICK, ROLL_RETRY, RefreshRollInfo, M) end
		else
			E.Ticker:Unsubscribe(ROLL_INFO_TICK)
		end
		if not ok then error(failure, 0) end
	end
	M.RefreshRollInfo = function() RefreshRollInfo() end
	E:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(_, _, itemID, success)
		if E:IsSecret(itemID) or E:IsSecret(success) then itemID, success = nil, nil end
		local waiting = false
		for _, bar in ipairs(rollBars) do
			if bar.rollID and bar.needsInfo then
				waiting = true
				-- The client could not load it: ask again on the next retry.
				if success == false and itemID ~= nil and bar.askedItem == itemID then bar.askedItem = nil end
			end
		end
		if waiting and success ~= false then RefreshRollInfo() end
	end, rollBars)

	-- Every open roll gets its bar at once: a roll is never left unshown
	-- because its item details are late or hidden.
	function StartRollRead(self, rollID, wait)
		local left = RollTimeLeft(rollID)
		if not ContinueRollRead(rollID, wait) then return end
		if not left then
			pendingRolls[rollID] = nil
			FinishRollRead(wait)
			return
		end
		local item = ReadRollItem(rollID)
		if not ContinueRollRead(rollID, wait) then return end
		if item.failure ~= nil and item.failure ~= wait.lastFailure then
			wait.lastFailure = item.failure
			geterrorhandler()(item.failure)
		end
		local link = GetLootRollItemLink and Plain(GetLootRollItemLink(rollID)) or nil
		if not ContinueRollRead(rollID, wait) then return end
		local duration = Plain(wait.rollTime) or (C_Loot and C_Loot.GetLootRollDuration and Plain(C_Loot.GetLootRollDuration(rollID)))
		if not ContinueRollRead(rollID, wait) then return end
		left = RollTimeLeft(rollID)
		if not ContinueRollRead(rollID, wait) then return end
		if not left then
			pendingRolls[rollID] = nil
			FinishRollRead(wait)
			return
		end
		if left == true then left = nil end
		if type(duration) ~= "number" or duration <= 0 then duration = left or 60000 end
		left = left or duration
		local now = GetTime()
		if not ContinueRollRead(rollID, wait) then return end
		local bar = self:FreeRollBar()
		local serial = bar.serial
		if not ContinueRollRead(rollID, wait) then return end
		bar.rollID = rollID
		bar.link = link
		bar.askedItem, bar.infoFailure = nil, item.failure
		wait.bar, wait.serial, wait.link = bar, serial, link
		FillRollBar(bar, item)
		MarkRollBar(bar)
		if not ContinueRollRead(rollID, wait, bar, serial) then return end
		bar.urgent = nil
		bar.timer:SetMinMaxValues(0, duration)
		bar.timer:SetValue(left)
		bar.endsAt = now + left / 1000
		TimerColor(bar, left, duration)
		UpdateBarArrow(bar)
		if not ContinueRollRead(rollID, wait, bar, serial) then return end
		UpdateChoices(bar, BarDrop(bar))
		if not ContinueRollRead(rollID, wait, bar, serial) then return end
		LayoutRolls()
		if not ContinueRollRead(rollID, wait, bar, serial) then return end
		E:SlideIn(bar, "RIGHT")
		if not ContinueRollRead(rollID, wait, bar, serial) then return end
		pendingRolls[rollID] = nil
		FinishRollRead(wait)
		WatchRolls()
		if bar.needsInfo then
			AskForRollItem(bar)
			RefreshRollInfo()
		end
	end
end

function M:StartRoll(rollID, rollTime, expected)
	if E:IsSecret(rollID) or rollID == nil then return end
	local wait = BeginRollRead(rollID, rollTime, expected)
	if not wait then return end
	RunRollRead(StartRollRead, self, rollID, wait)
end

-- Rolls the game ended for the player (CANCEL_LOOT_ROLL): the open-roll
-- list may still name them while the others roll, so they never get a
-- second bar.
local endedRolls = {}

-- Every roll the game has open gets a bar, whatever happened to its start
-- event: a burst of rolls, a roll that started while a restriction hid its
-- details, or one missed while the switch was off. Runs after roll events,
-- after combat and boss fights, and every second while a roll is shown.
function M:SyncRolls()
	if not (self.active and E:BlizzardAllowed(ROLL_ID, "replace") and GetActiveLootRollIDs) then return end
	local ok, ids = pcall(GetActiveLootRollIDs)
	if not ok or type(ids) ~= "table" or E:IsSecret(ids) then return end
	local open = {}
	for _, rollID in ipairs(ids) do
		if not E:IsSecret(rollID) and rollID ~= nil then
			open[rollID] = true
			local shown = false
			for _, bar in ipairs(rollBars) do
				if bar.rollID == rollID then shown = true break end
			end
			if not endedRolls[rollID] and not shown then
				local started, failure = pcall(SyncOpenRoll, rollID)
				if not started then geterrorhandler()(failure) end
			end
		end
	end
	if not next(open) then wipe(endedRolls) end
	-- A bar whose roll the game no longer lists and whose time is up ends.
	for _, bar in ipairs(rollBars) do
		local rollID = bar.rollID
		if rollID and not open[rollID] and not RollTimeLeft(rollID) then self:EndRoll(rollID) end
	end
	WatchPendingRolls()
end

function M.SyncRollsSoon()
	E:Debounce("Loot:SyncRolls", 0.1, function() M:SyncRolls() end)
end

-- The game ended a roll: CANCEL_LOOT_ROLL once the player rolled (or the
-- time ran out), CANCEL_ALL_LOOT_ROLLS (rollID nil) when every roll is
-- off. A bar the player rolled on waits for the winner when Keep is on.
function M:EndRoll(rollID)
	if E:IsSecret(rollID) then return end
	if rollID == nil then wipe(pendingRolls) else pendingRolls[rollID] = nil; endedRolls[rollID] = true end
	WatchPendingRolls()
	for _, bar in ipairs(rollBars) do
		if bar.rollID and (rollID == nil or bar.rollID == rollID) then
			if rollID ~= nil and self.db.rollKeep and bar.choice ~= nil then
				self:WaitForRoll(bar)
			else
				self:ReleaseRollBar(bar)
			end
		elseif rollID == nil and (bar.waiting or bar.rollPreview) then
			self:ReleaseRollBar(bar)
		end
	end
	WatchRolls()
end

-- Shows a few fake bars so the look and spot can be checked without a group.
-- Their buttons do nothing: there is no roll behind them.
function M:TestRolls()
	if not self.rollAnchor then self:CreateRollAnchor() end
	local previews = {}
	for _, bar in ipairs(rollBars) do if bar.rollPreview then previews[#previews + 1] = bar end end
	for i = 1, 3 do
		local bar = previews[i] or self:FreeRollBar()
		bar.serial = (bar.serial or 0) + 1
		bar.rollPreview = true
		bar.rollID, bar.waiting, bar.result, bar.choice = nil, nil, nil, nil
		bar.status:Hide()
		bar.timer:Show()
		bar.iconBox:SetAlpha(1)
		bar.name:SetAlpha(1)
		bar.iconBox.level:SetText("")
		for _, button in ipairs(bar.buttons) do
			button:SetShown(button.info.key ~= "canTransmog" and button.info.key ~= "canDisenchant")
			button:SetEnabled(false)
		end
		SizeRollBar(bar)
		local quality = i + 1
		local r, g, b = QualityColor(quality)
		bar.iconBox.icon:SetTexture(E:ClientIcon(134400)) -- INV_Misc_QuestionMark
		bar.iconBox:SetBackdropBorderColor(r, g, b, 1)
		bar.name:SetText(_G["ITEM_QUALITY" .. quality .. "_DESC"] or L["Item"])
		bar.name:SetTextColor(r, g, b)
		bar.bop:SetText("")
		bar.timer:SetStatusBarColor(unpack(E.media.accentColor))
		bar.timer:SetMinMaxValues(0, 1)
		bar.timer:SetValue(1 - i * 0.25)
		E:SlideIn(bar, "RIGHT")
		local serial = bar.serial
		C_Timer.After(6, function()
			if bar.serial == serial and bar.rollPreview and not bar.rollID and not bar.waiting then self:ReleaseRollBar(bar) end
		end)
	end
	LayoutRolls()
end

---------------------------------------------------------------------------
-- Blizzard's roll frames: hide, skin, move
---------------------------------------------------------------------------
local rollsBlocked = false
local rollHooked = false
local blizzRollScale = {}
local skinnedRollFrames = setmetatable({}, { __mode = "k" })

local function BlizzardRollFrames()
	local list = {}
	for index = 1, 4 do -- GroupLootFrame1-4 (Forever has no NUM_GROUP_LOOT_FRAMES)
		local frame = _G["GroupLootFrame" .. index]
		if frame then list[#list + 1] = frame end
	end
	return list
end

-- The Loot Guide's roll box beside Blizzard's roll frames: our own
-- frame, anchored beside theirs; their frame and buttons are not changed.
local verdictHooked = setmetatable({}, { __mode = "k" })
local function BlizzardVerdict(frame)
	if not E.UpdateRollVerdict then return end
	local on = M.active and E:BlizzardAllowed(ROLL_ID) and not E:BlizzardHidden(ROLL_ID)
	E:UpdateRollVerdict(frame, on and frame.rollID or nil)
end

local function HookBlizzardVerdicts()
	for _, frame in ipairs(BlizzardRollFrames()) do
		if not verdictHooked[frame] then
			verdictHooked[frame] = true
			frame:HookScript("OnShow", BlizzardVerdict)
		end
		if frame:IsShown() then BlizzardVerdict(frame) end
	end
end

-- Hide or Replace: Blizzard stops opening its roll frames. Blizzard routes
-- START_LOOT_ROLL through its own event table; taking the event out of it
-- is the one clean way. Undone by /reload (the handler's reload table).
local function BlockBlizzardRolls()
	if rollsBlocked then return end
	if GameEvent and GameEvent.UnregisterInternalEvent then
		GameEvent.UnregisterInternalEvent("START_LOOT_ROLL")
		rollsBlocked = true
	end
end

local function SkinRollFrame(frame)
	if skinnedRollFrames[frame] or not E:BlizzardAllowed(ROLL_ID, "skin") then return end
	skinnedRollFrames[frame] = true
	E:SkinPanel(frame, { accentLine = false, insets = false, close = false, title = false })
	E:SkinAlphaZero(frame.Background, frame.Border)
	local iconFrame = frame.IconFrame
	if iconFrame then
		E:SkinAlphaZero(iconFrame.Border)
		if iconFrame.Icon then E:TrimIcon(iconFrame.Icon) end
		local box = CreateFrame("Frame", nil, iconFrame)
		box:SetAllPoints(iconFrame.Icon or iconFrame)
		box:SetFrameLevel(math.max(iconFrame:GetFrameLevel() - 1, 0))
		E:SetTemplate(box)
		box:SetBackdropColor(0, 0, 0, 0)
	end
	local timer = frame.Timer
	if timer then
		timer:SetStatusBarTexture(E.media.statusbar)
		timer:SetStatusBarColor(unpack(E.media.accentColor))
		E:SkinAlphaZero(timer.Background)
		local bg = CreateFrame("Frame", nil, timer)
		bg:SetAllPoints()
		bg:SetFrameLevel(math.max(timer:GetFrameLevel() - 1, 0))
		E:SetTemplate(bg, true)
	end
	if frame.Name and frame.Name.SetFont then E:SetFont(frame.Name, E.tokens.size.body) end
end

-- Blizzard re-anchors its frames whenever a roll starts or ends, and it
-- does so before a new frame is shown. With the Move switch on, every frame
-- in the game's list goes to EldoUI's roll spot by its own place in that
-- list, shown yet or not: a new frame opens on the spot instead of above
-- the action bars, and a frame stays where it is while the rolls around it
-- start and end.
local function PlaceBlizzardRolls()
	if not M.active or not E:BlizzardAllowed(ROLL_ID, "move") or E:BlizzardHidden(ROLL_ID) or not M.rollAnchor then return end
	local container = GroupLootContainer
	if not container or type(container.rollFrames) ~= "table" then return end
	local scale = M.db.blizzRollScale
	local up = M.db.rollGrow == "UP"
	local point = up and "BOTTOM" or "TOP"
	local step = type(container.reservedSize) == "number" and container.reservedSize or 100
	for slot = 1, container.maxIndex or 0 do
		local frame = container.rollFrames[slot]
		if frame and frame.SetPoint then
			if not blizzRollScale[frame] then blizzRollScale[frame] = frame:GetScale() end
			frame:SetScale(scale)
			frame:ClearAllPoints()
			-- The offset is in the frame's own scaled units: one reserved
			-- height per place in the list.
			frame:SetPoint(point, M.rollAnchor, point, 0, (slot - 1) * step * (up and 1 or -1))
		end
	end
end

do
	-- Blizzard also opens its roll frames outside the start event: after a
	-- loading screen or a reload it reopens every roll still running. With its
	-- roll frames hidden or replaced, such a frame closes as it opens and leaves
	-- the game's list of open frames, so it never stands over the action bars.
	-- Leaving the list lays out the game's bottom frames again, which waits for
	-- the end of combat.
	local function DropBlizzardRoll(frame)
		frame:Hide()
		E:RunOutOfCombat(function()
			local container = GroupLootContainer
			if not container or type(container.rollFrames) ~= "table" or not GroupLootContainer_RemoveFrame then return end
			if not (M.active and E:BlizzardHidden(ROLL_ID)) then return end
			for _ = 1, 8 do
				local listed = false
				for _, other in pairs(container.rollFrames) do
					if other == frame then listed = true break end
				end
				if not listed or frame:IsShown() then return end
				GroupLootContainer_RemoveFrame(container, frame)
			end
		end, frame)
	end

	-- Every time a Blizzard roll frame opens: closed again while its frames
	-- are hidden or replaced, otherwise skinned and placed with the switches.
	local function BlizzardRollShown(frame)
		if not M.active or not E:BlizzardAllowed(ROLL_ID) then return end
		if E:BlizzardHidden(ROLL_ID) then
			DropBlizzardRoll(frame)
			return
		end
		if E:BlizzardAllowed(ROLL_ID, "skin") then SkinRollFrame(frame) end
		PlaceBlizzardRolls()
	end

	local rollShowHooked = setmetatable({}, { __mode = "k" })
	function M:WatchBlizzardRollFrames()
		for _, frame in ipairs(BlizzardRollFrames()) do
			if not rollShowHooked[frame] then
				rollShowHooked[frame] = true
				frame:HookScript("OnShow", BlizzardRollShown)
			end
			if frame:IsShown() and E:BlizzardHidden(ROLL_ID) then DropBlizzardRoll(frame) end
		end
	end
end

-- Move switched off: back to the game's own spacing above the container.
local function RestoreBlizzardRolls()
	local container = GroupLootContainer
	for frame, scale in pairs(blizzRollScale) do frame:SetScale(scale) end
	wipe(blizzRollScale)
	if not container or type(container.rollFrames) ~= "table" then return end
	local reserved = container.reservedSize or 100
	for i = 1, container.maxIndex or 0 do
		local frame = container.rollFrames[i]
		if frame then
			frame:ClearAllPoints()
			frame:SetPoint("CENTER", container, "BOTTOM", 0, reserved * (i - 1 + 0.5))
		end
	end
end

---------------------------------------------------------------------------
-- Blizzard's loot history: skin (moving is the window mover's)
---------------------------------------------------------------------------
local function SkinHistory()
	local frame = GroupLootHistoryFrame
	if not frame or E:GetSkin(frame, "panel") then return end
	E:SkinPanel(frame)
	E:SkinCloseButton(frame.ClosePanelButton)
	E:SkinScrollBar(frame.ScrollBar)
	E:SkinDropdown(frame.EncounterDropdown)
	local timer = frame.Timer
	if timer then
		E:SkinAlphaZero(timer.Background, timer.Border)
		if timer.Fill then
			timer.Fill:SetTexture(E.media.statusbar)
			timer.Fill:SetVertexColor(unpack(E.media.accentColor))
		end
	end
	E:HookScrollBoxRows(frame.ScrollBox, function(row)
		if not E:BlizzardAllowed(ROLL_ID, "skin") then return end
		local art = row.BackgroundArtFrame
		if art then E:SkinAlphaZero(art.NameFrame, art.BorderFrame) end
		E:SkinRow(row, { stripe = 0.04 })
		local item = row.Item
		local icon = item and (item.icon or item.Icon)
		if icon and icon.SetTexCoord then E:TrimIcon(icon) end
	end)
end

-- The loot history window moves and scales through the window mover
-- (Data/MovableWindows.lua, key "lootHistory"), like every other
-- Blizzard window.

function M:ToggleHistory()
	if ToggleLootHistoryFrame then
		ToggleLootHistoryFrame()
	elseif GroupLootHistoryFrame then
		GroupLootHistoryFrame:SetShown(not GroupLootHistoryFrame:IsShown())
	end
end

-- Moments a roll can have started without a bar: the end of combat, of a
-- boss fight or of an addon restriction, a loading screen, a group change.
-- They have their own owner: the loot feed listens to the end of combat too.
local missedRolls = { "PLAYER_REGEN_ENABLED", "ENCOUNTER_END", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE",
	"ADDON_RESTRICTION_STATE_CHANGED", "LOOT_HISTORY_UPDATE_ENCOUNTER" }
function missedRolls.Listen(on)
	for _, event in ipairs(missedRolls) do
		if on then E:RegisterEvent(event, M.SyncRollsSoon, missedRolls) else E:UnregisterEvent(event, missedRolls) end
	end
end

function M:ApplyRolls()
	local own = self.active and E:BlizzardAllowed(ROLL_ID, "replace")
	if not self.rollAnchor then self:CreateRollAnchor() end
	self.rollAnchor:SetSize(self.db.rollWidth, self.db.rollHeight)
	if own then
		-- A failed bar never takes the next start event or the check after
		-- it down with it.
		self:RegisterEvent("START_LOOT_ROLL", function(_, _, rollID, rollTime)
			if not E:IsSecret(rollID) and rollID ~= nil then endedRolls[rollID] = nil end
			M.SyncRollsSoon()
			self:StartRoll(rollID, rollTime)
		end)
		self:RegisterEvent("CANCEL_LOOT_ROLL", function(_, _, rollID) self:EndRoll(rollID) M.SyncRollsSoon() end)
		self:RegisterEvent("CANCEL_ALL_LOOT_ROLLS", function() self:EndRoll(nil) end)
		self:RegisterEvent("LOOT_HISTORY_UPDATE_DROP", function() self:CheckRollResults() M.SyncRollsSoon() end)
		missedRolls.Listen(true)
		-- Rolls that started before a /reload or before the switch went on.
		self:SyncRolls()
		self:RestoreWaitingRolls()
		for _, bar in ipairs(rollBars) do
			if bar.rollID or bar.waiting or bar.rollPreview then
				SizeRollBar(bar)
				if bar.rollID then UpdateBarArrow(bar) end
				if bar.rollID or bar.waiting then MarkRollBar(bar);UpdateChoices(bar, BarDrop(bar)) end
			end
		end
		LayoutRolls()
	else
		for _, event in ipairs({ "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS", "LOOT_HISTORY_UPDATE_DROP" }) do self:UnregisterEvent(event) end
		missedRolls.Listen(false)
		self:EndRoll(nil)
	end

	if self.active and E:BlizzardAllowed(ROLL_ID) then self:WatchBlizzardRollFrames() end
	if self.active and E:BlizzardHidden(ROLL_ID) then
		BlockBlizzardRolls()
		if not own and not hideWarned then
			hideWarned = true
			self:Print(L["Blizzard's roll frames are hidden and EldoUI's roll bars are off, so loot rolls are not shown. Type %s for EldoUI's bars."]:format(E:Highlight("/eui blizz group-loot-rolls replace on")))
		end
	end
	if self.active and E:BlizzardAllowed(ROLL_ID) and not E:BlizzardHidden(ROLL_ID) then HookBlizzardVerdicts() end
	if self.active and E:BlizzardAllowed(ROLL_ID, "skin") then
		for _, frame in ipairs(BlizzardRollFrames()) do
			SkinRollFrame(frame)
		end
		SkinHistory()
	end
	if self.active and E:BlizzardAllowed(ROLL_ID, "move") then
		if not rollHooked and GroupLootContainer_Update then
			rollHooked = true
			hooksecurefunc("GroupLootContainer_Update", PlaceBlizzardRolls)
		end
		PlaceBlizzardRolls()
	elseif next(blizzRollScale) then
		RestoreBlizzardRolls()
	end
end

---------------------------------------------------------------------------
-- Toasts and the loot feed
--
-- One pipeline for everything you gain: looted items, money, reputation,
-- currencies and skill-ups. The game prints each gain as a chat system
-- message; EldoUI matches the line against the client's own localized
-- format strings (LOOT_ITEM_SELF, YOU_LOOT_MONEY, FACTION_STANDING_INCREASED,
-- CURRENCY_GAINED, SKILL_RANK_UP and friends), never against English text,
-- so it works in every client language. A line that arrives as a secret
-- string (chat lockdown) is skipped, not parsed.
--
-- Two ways to show a gain (toastMode):
--   toast  cards that slide in beside the right edge (EldoUI_LootToasts)
--   feed   a compact stack of rows (EldoUI_LootFeed) in one of four looks:
--          rows, accent bar, icon tiles or cards
-- A repeat of something still on screen adds to its row (count, money,
-- reputation) instead of opening a new one. Toast cards show at most
-- toastMax at once; more gains wait in a queue, first in, first out, and
-- show as earlier cards leave. The feed is a list: its oldest row makes
-- room. Toast cards for gains in combat wait until it ends (the feed shows
-- them at once). A card or row keeps its time while the mouse is over it,
-- and a right-click closes it. An optional sound plays once per burst;
-- Fanfare's loot sounds are its own.
-- Optional sources: experience (from the player's own XP values, so kills,
-- quests and exploring all count), honor, and what group members loot
-- (from the game's loot lines about them, with their own quality floor and
-- time on screen). A loot line the game hides adds nothing.
---------------------------------------------------------------------------
-- The feed's mover, its fixed icons and the gray of secondary text.
local FEED = {
	MOVER = "EldoUI_LootFeed",
	MONEY_ICON = "Interface\\Icons\\INV_Misc_Coin_01",
	REP_ICON = "Interface\\Icons\\Achievement_Reputation_01",
	SKILL_ICON = "Interface\\Icons\\INV_Misc_Book_11",
	XP_ICON = "Interface\\Icons\\Spell_Holy_SurgeOfLight",
	HONOR_ICONS = { Alliance = "Interface\\Icons\\INV_BannerPVP_02", Horde = "Interface\\Icons\\INV_BannerPVP_01" },
	UNKNOWN_ICON = 134400, -- INV_Misc_QuestionMark, in every client
	GREY_TEXT = { 0.65, 0.65, 0.7 },
}
local function CoinString(copper) return E:FormatMoney(copper) end -- the Money style (Fonts and text page)

-- Lines are matched by the shared parser (Core/ChatParse.lua): the
-- client's own format strings, secret text never read.
local ChatParse = E.ChatParse
local function Readable(text) return ChatParse:Readable(text) end
local function Parse(kind, text) return (ChatParse:Parse(kind, text)) end
local function MoneyFromText(text) return ChatParse:Money(text) end

-- What group members loot, in the client's own strings.
ChatParse:AddKind("lootOthers", {
	{ "LOOT_ITEM_MULTIPLE", { "name", "link", "count" } },
	{ "LOOT_ITEM_PUSHED_MULTIPLE", { "name", "link", "count" } },
	{ "CREATED_ITEM_MULTIPLE", { "name", "link", "count" } },
	{ "LOOT_ITEM", { "name", "link" } },
	{ "LOOT_ITEM_PUSHED", { "name", "link" } },
	{ "CREATED_ITEM", { "name", "link" } },
})

-- The quality an item link carries in its color, for an item the client
-- has not loaded yet.
local function LinkQuality(link)
	local hex = link:match("|c(%x%x%x%x%x%x%x%x)")
	if not (hex and ITEM_QUALITY_COLORS) then return nil end
	hex = hex:lower()
	for quality = 0, 8 do
		local color = ITEM_QUALITY_COLORS[quality]
		if color and type(color.hex) == "string" and color.hex:lower():find(hex, 1, true) then return quality end
	end
	return nil
end

---------------------------------------------------------------------------
-- Entries: { kind, key, icon, name, r, g, b, count, amount, link, ilvl, value }
---------------------------------------------------------------------------
local function ItemEntry(link, count, floor)
	link = ChatParse:ItemLink(link) or link
	local name, _, quality, itemLevel, _, _, _, _, _, texture, sellPrice, classID = C_Item.GetItemInfo(link)
	if not quality then
		-- Not cached yet: show the link as it came, in its link's color.
		local id = tonumber(link:match("item:(%d+)"))
		texture = id and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) or FEED.UNKNOWN_ICON
		quality = LinkQuality(link) or 1
	end
	if quality < (floor or M.db.toastQuality) then return nil end
	local r, g, b = QualityColor(quality)
	local plainName = name or link:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
	local entry = { kind = "item", key = "item:" .. (link:match("item:([%-%d:]+)") or plainName), icon = texture or FEED.UNKNOWN_ICON,
		name = plainName, r = r, g = g, b = b, count = count or 1, link = link, quality = quality }
	local weaponOrArmor = classID == (Enum.ItemClass and Enum.ItemClass.Weapon or 2) or classID == (Enum.ItemClass and Enum.ItemClass.Armor or 4)
	if weaponOrArmor then
		local detailed = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
		entry.ilvl = tonumber(detailed) or tonumber(itemLevel)
	end
	entry.price = tonumber(sellPrice) or 0
	return entry
end

local function CurrencyEntry(link, count)
	local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfoFromLink and C_CurrencyInfo.GetCurrencyInfoFromLink(link)
	local id = link:match("currency:(%d+)")
	local name = info and info.name or link:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
	local r, g, b = QualityColor(info and info.quality or 1)
	local maxQuantity = info and tonumber(info.maxQuantity) or 0
	local capped = maxQuantity > 0 and (tonumber(info.quantity) or 0) >= maxQuantity
	return { kind = "currency", key = "currency:" .. (id or name), icon = info and info.iconFileID or FEED.UNKNOWN_ICON,
		name = name, r = r, g = g, b = b, count = count or 1, link = link, capped = capped }
end

local function SkillIcon(skill)
	if GetProfessions and GetProfessionInfo then
		local slots = { GetProfessions() }
		for slot = 1, 5 do
			local index = slots[slot]
			if index then
				local name, icon = GetProfessionInfo(index)
				if name == skill then return icon end
			end
		end
	end
	return FEED.SKILL_ICON
end

-- A group member's loot: their own floor and time, their name beside it.
local function OthersLoot(text)
	local fields = Parse("lootOthers", text)
	local who = fields and fields.name
	if not (fields and fields.link and type(who) == "string") then return end
	local player = UnitName("player")
	if not E:IsSecret(player) and BareName(who) == BareName(player) then return end
	local entry = ItemEntry(fields.link, tonumber(fields.count), M.db.feedOthersQuality)
	if not entry then return end
	local _, classFile = UnitClass(who)
	entry.who = ClassColored(who, not E:IsSecret(classFile) and classFile or nil)
	entry.key = "other:" .. who .. ":" .. entry.key
	entry.hold = M.db.feedOthersTime
	M:AddGain(entry)
end

local function OnLootMessage(_, _, text)
	text = Readable(text)
	if not text then return end
	local fields, format = ChatParse:Parse("item", text)
	if not (fields and fields.link) then
		if M.db.feedOthers then OthersLoot(text) end
		return
	end
	if not M.db.feedItems then return end
	if not M.db.feedCrafted and type(format) == "string" and format:find("^LOOT_ITEM_CREATED") then return end
	local entry = ItemEntry(fields.link, tonumber(fields.count))
	if entry then M:AddGain(entry) end
end

-- Experience from the player's own values: a level-up adds what was left
-- of the old level.
local function ReadXP()
	local xp, max, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
	if E:IsSecret(xp) or E:IsSecret(max) or E:IsSecret(level) then return nil end
	return tonumber(xp), tonumber(max), tonumber(level)
end

function M:ResetXP()
	self.xpLast, self.xpMax, self.xpLevel = ReadXP()
end

local function OnXPUpdate(_, _, unit)
	if unit and unit ~= "player" then return end
	local xp, max, level = ReadXP()
	local last, lastMax, lastLevel = M.xpLast, M.xpMax, M.xpLevel
	M.xpLast, M.xpMax, M.xpLevel = xp, max, level
	if not (M.db.feedXP and xp and last and level and lastLevel) then return end
	local gained = xp - last
	if level > lastLevel then gained = (lastMax or last) - last + xp end
	if gained > 0 then
		M:AddGain({ kind = "xp", key = "xp", icon = FEED.XP_ICON, amount = gained, r = 0.6, g = 0.45, b = 1 })
	end
end

local function OnHonorMessage(_, _, text)
	text = Readable(text)
	if not text or not M.db.feedHonor then return end
	local fields = Parse("honor", text)
	local amount = fields and not fields.dishonor and tonumber(fields.honor)
	if not (amount and amount > 0) then return end
	local faction = UnitFactionGroup("player")
	M:AddGain({ kind = "honor", key = "honor", icon = FEED.HONOR_ICONS[faction] or FEED.HONOR_ICONS.Alliance, amount = amount, r = 1, g = 0.82, b = 0 })
end

local function OnMoneyMessage(_, _, text)
	text = Readable(text)
	if not text or not M.db.toastMoney then return end
	local fields = Parse("money", text)
	local copper = MoneyFromText(fields and fields.money or text)
	if copper and copper > 0 then
		M:AddGain({ kind = "money", key = "money", icon = FEED.MONEY_ICON, amount = copper, r = 1, g = 0.82, b = 0 })
	elseif fields then
		M:AddGain({ kind = "money", key = "money:" .. fields.money, icon = FEED.MONEY_ICON, name = fields.money, r = 1, g = 0.82, b = 0 })
	end
end

local function OnFactionMessage(_, _, text)
	text = Readable(text)
	if not text or not M.db.feedRep then return end
	local fields = Parse("rep", text)
	if not fields or not fields.faction then return end
	local amount = tonumber(fields.amount) or (fields.loss and -tonumber(fields.loss)) or nil
	M:AddGain({ kind = "rep", key = "rep:" .. fields.faction, icon = FEED.REP_ICON, name = fields.faction, amount = amount,
		r = amount and amount < 0 and 1 or 0.4, g = amount and amount < 0 and 0.3 or 0.6, b = amount and amount < 0 and 0.3 or 1 })
end

local function OnCurrencyMessage(_, _, text)
	text = Readable(text)
	if not text or not M.db.feedCurrency then return end
	local fields = Parse("currency", text)
	if fields and fields.link then M:AddGain(CurrencyEntry(fields.link, tonumber(fields.count))) end
end

local function SkillGain(skill, rank)
	M:AddGain({ kind = "skill", key = "skill:" .. skill, icon = SkillIcon(skill), name = skill, rank = rank, r = 0.4, g = 0.8, b = 1 })
end

local function OnSkillMessage(_, _, text)
	text = Readable(text)
	if not text or not M.db.feedSkill then return end
	local fields = Parse("skill", text)
	if fields and fields.skill then SkillGain(fields.skill, tonumber(fields.rank)) end
end

-- In dungeons and raids the skill line is hidden: the skills list says it.
local function OnSkillLines()
	local risen = E.ChatParse:RisenSkills("loot")
	if not M.db.feedSkill then return end
	for _, skill in ipairs(risen) do SkillGain(skill.name, skill.rank) end
end

---------------------------------------------------------------------------
-- Text of a row
---------------------------------------------------------------------------
local function Hex(r, g, b)
	return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

-- Main text and the gray detail on the right.
local function EntryText(entry, db, look)
	local kind = entry.kind
	if kind == "money" then
		if entry.amount then return CoinString(entry.amount), "" end
		return entry.name or "", ""
	end
	if kind == "rep" then
		local amount = entry.amount
		local sign = amount and (amount >= 0 and "+" or "") or ""
		local main = amount and (sign .. BreakUpLargeNumbers(amount) .. " " .. entry.name) or entry.name
		return main, E:GameText(_G.REPUTATION, L["Reputation"])
	end
	if kind == "skill" then
		return entry.name, entry.rank and tostring(entry.rank) or ""
	end
	if kind == "xp" or kind == "honor" then
		local word = kind == "xp" and (rawget(_G, "XP") or L["XP"]) or (rawget(_G, "HONOR") or L["Honor"])
		local amount = math.floor((entry.amount or 0) + 0.5)
		return "+" .. BreakUpLargeNumbers(amount) .. " " .. word, ""
	end
	local main = entry.name or ""
	if (entry.count or 1) > 1 then main = main .. " |cffffffffx" .. entry.count .. "|r" end
	local detail = {}
	if kind == "currency" and db.feedCapped and entry.capped then
		detail[#detail + 1] = E:TextHex("warn") .. L["Capped"] .. "|r"
	end
	if kind == "item" then
		if entry.who then detail[#detail + 1] = entry.who end
		if look and look.toast and db.toastLegendary and (entry.quality or 0) >= 5 then
			detail[#detail + 1] = Hex(entry.r or 1, entry.g or 1, entry.b or 1) .. L["Legendary!"] .. "|r"
		end
		if db.feedItemLevel and entry.ilvl and entry.ilvl > 0 then detail[#detail + 1] = (E:GameText(_G.ITEM_LEVEL_ABBR, L["iLvl"])) .. " " .. entry.ilvl end
		if db.feedValue and (entry.price or 0) > 0 then detail[#detail + 1] = CoinString(entry.price * (entry.count or 1)) end
	end
	return main, table.concat(detail, "  ")
end

---------------------------------------------------------------------------
-- The stack renderer, shared by toast cards and the feed
---------------------------------------------------------------------------
local stacks = {}
M.gainStacks = stacks

-- A toast card and the gap between cards. The Loot Toasts box is as tall
-- as the cards it can show at once, so move mode and the layout checks see
-- its real reach; the cards grow up from its bottom edge.
local TOAST_W, TOAST_H, TOAST_GAP = 260, 40, 4
local function ToastReach()
	local count = math.max(1, math.floor(tonumber(M.db.toastMax) or 4))
	return count * (TOAST_H + TOAST_GAP) - TOAST_GAP
end

-- Look of a stack from the settings.
local function StackLook(mode)
	local db = M.db
	if mode == "toast" then
		return { anchor = M.toastAnchor, style = "cards", height = TOAST_H, width = TOAST_W, gap = TOAST_GAP, grow = "UP", max = db.toastMax or 4,
			fontSize = 14, border = true, toast = true }
	end
	return { anchor = M.feedAnchor, style = db.feedStyle, height = db.feedRowHeight, width = db.feedWidth, gap = db.feedStyle == "bar" and 2 or 4,
		grow = db.feedGrow, max = db.feedRows, fontSize = db.feedFontSize, border = db.feedQualityBorder }
end

local function CreateGainRow(stack)
	local row = CreateFrame("Frame", nil, UIParent)
	E:AddMoverContent(stack.mode == "feed" and FEED.MOVER or "EldoUI_LootToasts", row)
	row:SetFrameStrata("MEDIUM")
	row:SetClampedToScreen(true)
	E:SetTemplate(row)
	row.fill = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.fill:SetAllPoints()
	row.edge = row:CreateTexture(nil, "ARTWORK")
	row.edge:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	row.edge:SetPoint("BOTTOMLEFT", E.pixel, E.pixel)
	row.iconBox = IconBox(row, 24)
	row.text = E:CreateText(row, E.tokens.size.body, "LEFT")
	row.text:SetWordWrap(false)
	row.detail = E:CreateText(row, E.tokens.size.small, "RIGHT")
	row.detail:SetTextColor(FEED.GREY_TEXT[1], FEED.GREY_TEXT[2], FEED.GREY_TEXT[3])
	row.stack = stack
	row:EnableMouse(true)
	-- The mouse over a row stops its time (and brings it back while it
	-- fades); leaving starts a fresh hold.
	row:SetScript("OnEnter", function(self)
		if self.inUse then
			self.hover = true
			self.token = {}
			local out = self.eldoAnim and self.eldoAnim.out
			if out and out:IsPlaying() then E:SlideIn(self, "RIGHT") end
		end
		local entry = self.entry
		if not entry or not entry.link then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetHyperlink(entry.link)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function(self)
		GameTooltip_Hide()
		self.hover = nil
		if self.inUse then M:HoldGainRow(self) end
	end)
	-- Shift-click links the item in chat, like a bag slot; a right-click
	-- closes the row.
	row:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then
			if self.inUse then M:DismissGainRow(self) end
			return
		end
		if self.entry and self.entry.link and IsModifiedClick() then HandleModifiedItemClick(self.entry.link) end
	end)
	row:Hide()
	return row
end

-- Draw one row in the stack's look.
local function PaintRow(row, look)
	local entry = row.entry
	local db = M.db
	local height = look.height
	local style = look.style
	local r, g, b = entry.r or 1, entry.g or 1, entry.b or 1
	row:SetSize(look.width, style == "tiles" and math.floor(height * 1.5 + 0.5) or height)
	E:SetTemplate(row)
	local iconSize = style == "tiles" and math.floor(height * 1.5 + 0.5) - 4 or height - 4
	row.iconBox:SetSize(iconSize, iconSize)
	row.iconBox:ClearAllPoints()
	-- Through E:ClientIcon: an icon this client lacks gets its stand-in.
	row.iconBox.icon:SetTexture(E:ClientIcon(entry.icon, FEED.UNKNOWN_ICON))
	local total = db.feedBagCount and entry.kind == "item" and not entry.who and entry.link and C_Item.GetItemCount and C_Item.GetItemCount(entry.link)
	row.iconBox.count:SetText(type(total) == "number" and not E:IsSecret(total) and total > 0 and tostring(total) or "")
	row.text:ClearAllPoints()
	row.detail:ClearAllPoints()
	E:SetFont(row.text, look.fontSize)
	E:SetFont(row.detail, math.max(9, look.fontSize - 2))
	local main, detail = EntryText(entry, db, look)
	row.text:SetText(main)
	row.text:SetTextColor(r, g, b)
	row.detail:SetText(detail or "")
	local quality = look.border and entry.kind == "item"
	row.edge:Hide()
	row.fill:SetColorTexture(0, 0, 0, 0)

	if style == "bar" then
		-- No box: an accent (or quality) bar on a fading background.
		row:SetBackdropColor(0, 0, 0, 0)
		row:SetBackdropBorderColor(0, 0, 0, 0)
		local ar, ag, ab = unpack(E.media.accentColor)
		if quality then ar, ag, ab = r, g, b end
		row.edge:SetColorTexture(ar, ag, ab, 1)
		row.edge:SetWidth(3)
		row.edge:Show()
		if row.fill.SetGradient and CreateColor then
			row.fill:SetColorTexture(1, 1, 1, 1)
			row.fill:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0.6), CreateColor(0, 0, 0, 0))
		else
			row.fill:SetColorTexture(0, 0, 0, 0.4)
		end
		row.iconBox:SetPoint("LEFT", 6, 0)
		row.iconBox:SetBackdropBorderColor(0, 0, 0, 1)
	elseif style == "tiles" then
		-- A big icon tile with the name and detail stacked beside it.
		row:SetBackdropColor(0, 0, 0, 0)
		row:SetBackdropBorderColor(0, 0, 0, 0)
		row.iconBox:SetPoint("LEFT", 0, 0)
		if quality then row.iconBox:SetBackdropBorderColor(r, g, b, 1) else row.iconBox:SetBackdropBorderColor(unpack(E.media.borderColor)) end
		row.text:SetPoint("BOTTOMLEFT", row.iconBox, "RIGHT", 6, 1)
		row.text:SetPoint("BOTTOMRIGHT", row, "RIGHT", -4, 1)
		row.detail:SetPoint("TOPLEFT", row.iconBox, "RIGHT", 6, -2)
		row.detail:SetJustifyH("LEFT")
		return
	elseif style == "cards" then
		-- Framed card with a colored edge (the toast look).
		row.edge:SetColorTexture(r, g, b, 1)
		row.edge:SetWidth(3)
		row.edge:Show()
		row.iconBox:SetPoint("LEFT", 6, 0)
		row:SetBackdropBorderColor(unpack(quality and { r, g, b, 1 } or E.media.borderColor))
		row.iconBox:SetBackdropBorderColor(r, g, b, 1)
	else
		-- rows: a bordered box per gain, quality-colored border.
		row.iconBox:SetPoint("LEFT", 2, 0)
		if quality then
			row:SetBackdropBorderColor(r, g, b, 1)
			row.iconBox:SetBackdropBorderColor(r, g, b, 1)
		else
			row.iconBox:SetBackdropBorderColor(unpack(E.media.borderColor))
		end
	end
	row.detail:SetJustifyH("RIGHT")
	row.detail:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	row.text:SetPoint("LEFT", row.iconBox, "RIGHT", 6, 0)
	row.text:SetPoint("RIGHT", row.detail, "LEFT", -6, 0)
end

local function LayoutStack(stack)
	local look = StackLook(stack.mode)
	if not look.anchor then return end
	local offset = 0
	local direction = look.grow == "DOWN" and -1 or 1
	for _, row in ipairs(stack.rows) do
		if row.inUse then
			row:ClearAllPoints()
			if direction > 0 then
				row:SetPoint("BOTTOM", look.anchor, "BOTTOM", 0, offset)
			else
				row:SetPoint("TOP", look.anchor, "TOP", 0, offset)
			end
			offset = offset + direction * (row:GetHeight() + look.gap)
		end
	end
end

local function GetStack(mode)
	local stack = stacks[mode]
	if not stack then
		stack = { mode = mode, rows = {} }
		stacks[mode] = stack
	end
	return stack
end

local ShowGain -- below

local function ReleaseRow(stack, row)
	row.inUse = false
	row.entry = nil
	row.token = nil
	row.hover = nil
	row:Hide()
	LayoutStack(stack)
	-- A card left: the next waiting gain takes its place.
	local queue = stack.queue
	if queue and queue[1] and stack.mode == "toast" and not InCombatLockdown() then ShowGain(stack, table.remove(queue, 1)) end
end

-- Start (or restart) the row's time on screen.
local function HoldRow(stack, row)
	local token = {}
	row.token = token
	C_Timer.After(row.entry and row.entry.hold or M.db.toastTime, function()
		if row.token ~= token or row.hover then return end
		row.token = nil
		E:SlideOut(row, "RIGHT", function()
			if row.token == nil then ReleaseRow(stack, row) end
		end)
	end)
end

function M:HoldGainRow(row)
	if row.stack then HoldRow(row.stack, row) end
end

function M:DismissGainRow(row)
	if not row.stack then return end
	GameTooltip_Hide()
	ReleaseRow(row.stack, row)
end

-- One sound per burst: gains within a second play once. A legendary item
-- plays its own pick when one is set, even right after a plain sound.
local function GainSound(entry)
	local db = M.db
	local legendary = entry.kind == "item" and (entry.quality or 0) >= 5 and db.toastSoundLegendary and db.toastSoundLegendary ~= "none"
	local id = legendary and db.toastSoundLegendary or db.toastSound
	if not id or id == "none" then return end
	local now = GetTime()
	local last = M.lastGainSound
	if legendary then last = M.lastLegendarySound end
	if last and now - last < 1 then return end
	M.lastGainSound = now
	if legendary then M.lastLegendarySound = now end
	E:PlayMedia(id)
end

-- Add up a repeat into an entry that is shown or waiting.
local function MergeEntry(old, entry)
	if entry.count then old.count = (old.count or 1) + entry.count end
	if entry.amount and old.amount then old.amount = old.amount + entry.amount end
	if entry.rank then old.rank = entry.rank end
end

-- A waiting toast card. The queue holds at most three times the cards
-- shown at once, so a long fight or a big pull never leaves minutes of
-- cards to play out; the oldest go first (the loot feed lists them all).
local function Enqueue(stack, entry)
	local queue = stack.queue or {}
	stack.queue = queue
	queue[#queue + 1] = entry
	local cap = 3 * math.max(1, math.floor(tonumber(M.db.toastMax) or 4))
	while #queue > cap do table.remove(queue, 1) end
end

local function UsedRows(stack)
	local used = 0
	for _, r in ipairs(stack.rows) do
		if r.inUse then used = used + 1 end
	end
	return used
end

-- Adds one gain to the stack of the current mode, merging a repeat.
function M:AddGain(entry)
	if not (self.active and self.db.toasts) or not entry then return end
	local mode = self.db.toastMode == "feed" and "feed" or "toast"
	if mode == "feed" and not self.feedAnchor then self:CreateFeedAnchor() end
	if mode == "toast" and not self.toastAnchor then self:CreateToastAnchor() end
	local stack = GetStack(mode)
	local look = StackLook(mode)
	-- Merge into a row of the same thing that is still shown, or waiting.
	if self.db.feedMerge and entry.key then
		for _, row in ipairs(stack.rows) do
			local old = row.inUse and row.entry
			if old and old.key == entry.key then
				MergeEntry(old, entry)
				PaintRow(row, look)
				-- Fading out already: bring it back.
				local out = row.eldoAnim and row.eldoAnim.out
				if out and out:IsPlaying() then E:SlideIn(row, "RIGHT") end
				if not row.hover then HoldRow(stack, row) end
				return row
			end
		end
		for _, old in ipairs(stack.queue or {}) do
			if old.key == entry.key then
				MergeEntry(old, entry)
				return nil
			end
		end
	end
	-- Toast cards wait out a fight (they play out, with their sound, when
	-- it ends; the feed lists loot as it drops).
	if mode == "toast" and InCombatLockdown() then
		Enqueue(stack, entry)
		return nil
	end
	GainSound(entry)
	-- Toast cards: when all are taken, the gain waits its turn.
	if mode == "toast" and UsedRows(stack) >= look.max then
		Enqueue(stack, entry)
		return nil
	end
	return ShowGain(stack, entry)
end

-- After a fight: the toast cards that waited show, as many as fit, in the
-- order they came; the rest follow as cards leave.
function M:PlayWaitingToasts()
	local stack = stacks.toast
	local queue = stack and stack.queue
	if not (queue and queue[1]) or InCombatLockdown() then return end
	if self.db.toastMode == "feed" then return end
	GainSound(queue[1])
	local look = StackLook("toast")
	while queue[1] and UsedRows(stack) < look.max do
		ShowGain(stack, table.remove(queue, 1))
	end
end

-- Put a gain on a free row, or on the oldest one when the stack is full.
ShowGain = function(stack, entry)
	local look = StackLook(stack.mode)
	local row, used = nil, 0
	for _, r in ipairs(stack.rows) do
		if r.inUse then used = used + 1 elseif not row then row = r end
	end
	if used >= look.max then
		for index = #stack.rows, 1, -1 do
			local r = stack.rows[index]
			if r.inUse then
				r.token = nil
				r.hover = nil
				r.inUse = false
				r:Hide()
				row = r
				break
			end
		end
	end
	if not row then row = CreateGainRow(stack) end
	-- Newest next to the anchor.
	for index, r in ipairs(stack.rows) do
		if r == row then table.remove(stack.rows, index) break end
	end
	table.insert(stack.rows, 1, row)
	row.inUse = true
	row.entry = entry
	PaintRow(row, look)
	LayoutStack(stack)
	E:SlideIn(row, "RIGHT")
	HoldRow(stack, row)
	return row
end

-- Re-draw every shown row after a look change (option, theme).
function M:RefreshGains()
	for mode, stack in pairs(stacks) do
		local look = StackLook(mode)
		for _, row in ipairs(stack.rows) do
			if row.inUse and row.entry then PaintRow(row, look) end
		end
		LayoutStack(stack)
		-- More cards allowed now: waiting gains show at once.
		local queue = stack.queue
		while mode == "toast" and queue and queue[1] and UsedRows(stack) < look.max and not InCombatLockdown() do
			ShowGain(stack, table.remove(queue, 1))
		end
	end
end

function M:ClearGains()
	for _, stack in pairs(stacks) do
		stack.queue = nil
		for _, row in ipairs(stack.rows) do
			row.token = nil
			row.hover = nil
			row.inUse = false
			row.entry = nil
			row:Hide()
		end
	end
end

function M:CreateToastAnchor()
	self.toastAnchor = CreateFrame("Frame", "EldoUI_LootToasts", UIParent)
	self.toastAnchor:SetSize(TOAST_W, ToastReach())
	E:CreateMover(self.toastAnchor, "EldoUI_LootToasts", L["Loot Toasts"], { "RIGHT", "UIParent", "RIGHT", -360, 0 }, { sample = { kind = "toast" } })
end

function M:CreateFeedAnchor()
	self.feedAnchor = CreateFrame("Frame", FEED.MOVER, UIParent)
	self.feedAnchor:SetSize(self.db.feedWidth, self.db.feedRowHeight)
	E:CreateMover(self.feedAnchor, FEED.MOVER, L["Loot Feed"], { "RIGHT", "UIParent", "RIGHT", -700, 0 },
		{ sizeKeys = { width = { key = "feedWidth", min = 160, max = 480 } }, sample = { kind = "toast" } })
end

local FEED_EVENTS = {
	CHAT_MSG_LOOT = OnLootMessage,
	CHAT_MSG_MONEY = OnMoneyMessage,
	CHAT_MSG_COMBAT_FACTION_CHANGE = OnFactionMessage,
	CHAT_MSG_CURRENCY = OnCurrencyMessage,
	CHAT_MSG_SKILL = OnSkillMessage,
	SKILL_LINES_CHANGED = OnSkillLines,
	CHAT_MSG_COMBAT_HONOR_GAIN = OnHonorMessage,
	PLAYER_XP_UPDATE = OnXPUpdate,
	PLAYER_REGEN_ENABLED = function() M:PlayWaitingToasts() end,
}

function M:ApplyToasts()
	if not self.toastAnchor then self:CreateToastAnchor() end
	if not self.feedAnchor then self:CreateFeedAnchor() end
	self.feedAnchor:SetSize(self.db.feedWidth, self.db.feedRowHeight)
	self.toastAnchor:SetSize(TOAST_W, ToastReach())
	if self.active and self.db.toasts then
		for event, handler in pairs(FEED_EVENTS) do self:RegisterEvent(event, handler) end
		E.ChatParse:RisenSkills("loot")
		self:ResetXP()
		-- The bag total follows the bags.
		if self.db.feedBagCount then
			self:RegisterEvent("BAG_UPDATE_DELAYED", function() self:RefreshGains() end)
		else
			self:UnregisterEvent("BAG_UPDATE_DELAYED")
		end
	else
		for event in pairs(FEED_EVENTS) do self:UnregisterEvent(event) end
		self:UnregisterEvent("BAG_UPDATE_DELAYED")
		self:ClearGains()
	end
	-- A mode switch: the other stack empties.
	local mode = self.db.toastMode == "feed" and "feed" or "toast"
	-- Only the mover of the shown mode is on screen (both may sit at the
	-- same spot; move mode shows just the one in use).
	local showToasts = self.active and self.db.toasts and true or false
	for anchorMode, anchor in pairs({ toast = self.toastAnchor, feed = self.feedAnchor }) do
		local shown = showToasts and anchorMode == mode
		anchor:SetShown(shown)
		local mover = E.movers[anchorMode == "feed" and FEED.MOVER or "EldoUI_LootToasts"]
		if mover then mover:SetShown(shown) end
	end
	for other, stack in pairs(stacks) do
		if other ~= mode then
			stack.queue = nil
			for _, row in ipairs(stack.rows) do
				row.token = nil
				row.hover = nil
				row.inUse = false
				row:Hide()
			end
		end
	end
	self:RefreshGains()
end

-- One sample row per enabled source, so the look can be checked anywhere.
function M:ShowSamples()
	local db = self.db
	local samples = {}
	if db.feedItems then
		for quality = math.max(db.toastQuality, 1), 4 do
			local r, g, b = QualityColor(quality)
			samples[#samples + 1] = { kind = "item", key = "sample:item" .. quality, icon = FEED.UNKNOWN_ICON,
				name = _G["ITEM_QUALITY" .. quality .. "_DESC"] or L["Item"], r = r, g = g, b = b, count = quality == 1 and 5 or 1,
				ilvl = quality > 1 and (20 + quality * 5) or nil, price = 1250 * quality }
		end
	end
	if db.toastMoney then samples[#samples + 1] = { kind = "money", key = "sample:money", icon = FEED.MONEY_ICON, amount = 12345, r = 1, g = 0.82, b = 0 } end
	if db.feedRep then samples[#samples + 1] = { kind = "rep", key = "sample:rep", icon = FEED.REP_ICON, name = E:GameText(_G.FACTION, L["Faction"]), amount = 250, r = 0.4, g = 0.6, b = 1 } end
	if db.feedCurrency then
		local r, g, b = QualityColor(1)
		samples[#samples + 1] = { kind = "currency", key = "sample:currency", icon = FEED.UNKNOWN_ICON, name = E:GameText(_G.CURRENCY, L["Currency"]), count = 3, r = r, g = g, b = b }
	end
	if db.feedSkill then samples[#samples + 1] = { kind = "skill", key = "sample:skill", icon = FEED.SKILL_ICON, name = E:GameText(_G.SKILL, L["Skill"]), rank = 150, r = 0.4, g = 0.8, b = 1 } end
	if db.feedXP then samples[#samples + 1] = { kind = "xp", key = "sample:xp", icon = FEED.XP_ICON, amount = 1450, r = 0.6, g = 0.45, b = 1 } end
	if db.feedHonor then samples[#samples + 1] = { kind = "honor", key = "sample:honor", icon = FEED.HONOR_ICONS.Alliance, amount = 62, r = 1, g = 0.82, b = 0 } end
	if db.feedOthers then
		local r, g, b = QualityColor(db.feedOthersQuality)
		samples[#samples + 1] = { kind = "item", key = "sample:other", icon = FEED.UNKNOWN_ICON, name = _G["ITEM_QUALITY" .. db.feedOthersQuality .. "_DESC"] or L["Item"],
			r = r, g = g, b = b, count = 1, who = L["Group member"], hold = db.feedOthersTime }
	end
	if not (self.active and db.toasts) then
		self:Print(L["Turn on \"Show what you loot\" to see the samples."])
		return
	end
	for _, entry in ipairs(samples) do self:AddGain(entry) end
end

---------------------------------------------------------------------------
-- Saved data: loot rolls are always manual. An old QoL version could save
-- an automatic greed choice (modules.QoL.greedGreens). Nothing reads it any
-- more, and it must never come back to life in an older EldoUI. Once per
-- profile it moves out of the settings into the profile's kept values
-- (profile._quarantine): gone from play, but the value is not lost. When a
-- different value is already kept there, the setting stays where it is.
---------------------------------------------------------------------------
local GREED_PATH = "modules.QoL.greedGreens"

function M.RetireGreedGreens(profile)
	local modules = type(profile) == "table" and profile.modules
	local qol = type(modules) == "table" and modules.QoL
	if type(qol) ~= "table" or qol.greedGreens == nil then return end
	if profile._quarantine ~= nil and type(profile._quarantine) ~= "table" then return end
	local kept = profile._quarantine or {}
	profile._quarantine = kept
	local entry = kept[GREED_PATH]
	if entry == nil then
		kept[GREED_PATH] = { value = qol.greedGreens, at = time and time() or 0, why = "retired" }
	elseif not (type(entry) == "table" and entry.value == qol.greedGreens) then
		return
	end
	qol.greedGreens = nil
end
E:RegisterProfileMigration(M.RetireGreedGreens, "Loot:greedGreens", 1)

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:Apply()
	self:ApplyLootWindow()
	self:ApplyBindConfirmations()
	self:ApplyRolls()
	self:ApplyToasts()
end

function M:OnInitialize()
	for id in pairs(MODE_KEY) do lastMode[id] = DerivedMode(id) end
	-- The loot history's own saved spot; the window mover keeps it now.
	self.db.historyPoint = nil
end

function M:OnEnable()
	self:SyncModes()
	self:Apply()
	if E.RegisterUpgradeRefresh and not self.upgradeHooked then
		self.upgradeHooked = true
		E:RegisterUpgradeRefresh(function() if M.active then M:RefreshRollArrows() end end)
	end
end

function M:OnDisable()
	self:ApplyBindConfirmations()
	self:EndLootRoomNotice()
	self:ClearGains()
	if self.lootFrame then self.lootFrame:Hide() end
	self:EndRoll(nil)
	missedRolls.Listen(false)
	E.Ticker:UnsubscribeOwner(self)
	-- Blizzard's loot window listens again at once; its roll frames after a reload.
	SetBlizzardLootEvents(true)
	RestoreCVar("lootUnderMouse", LOOT_ID)
	if rollsBlocked then
		E:ShowReloadPrompt(L["Loot switched off. Blizzard's roll frames come back after a reload."])
	end
end

function M:OnProfileChanged()
	if not self.db then return end
	self:SyncModes()
	if self.active then self:Apply() end
end

---------------------------------------------------------------------------
-- Blizzard element handlers (Blizzard UI page)
---------------------------------------------------------------------------
E:RegisterBlizzardHandler(LOOT_ID, {
	owner = "Loot",
	apply = function() if M.active then M:Apply() end end,
	undo = function()
		M:ApplyBindConfirmations()
		M:EndLootRoomNotice()
		SetBlizzardLootEvents(true)
		if M.lootFrame then M.lootFrame:Hide() end
		M:UnregisterEvent("LOOT_READY")
		if LootFrame and blizzLootScale then
			-- The plain widget method: Edit Mode's override never runs from EldoUI.
			E.BlizzardKeep.SetScale(LootFrame, blizzLootScale)
			blizzLootScale = nil
		end
	end,
	reload = { skin = true },
	install = { replace = true, move = true },
	-- v0.5.0 replaced the loot window whenever the module and its window were on.
	legacy = function() return M.db and M.db.enabled ~= false and M.db.window and true or false end,
})

E:RegisterBlizzardHandler(ROLL_ID, {
	owner = "Loot",
	apply = function() if M.active then M:Apply() end end,
	undo = function()
		M:EndRoll(nil)
		for _, event in ipairs({ "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS" }) do M:UnregisterEvent(event) end
		missedRolls.Listen(false)
		if next(blizzRollScale) then RestoreBlizzardRolls() end
	end,
	reload = { skin = true, hide = true, replace = true },
	install = { replace = true, move = true, improve = true },
	legacy = function() return M.db and M.db.enabled ~= false and M.db.rolls and true or false end,
})

E:AddCommand("loothistory", "open or close Blizzard's loot history", function() M:ToggleHistory() end, "Tools")

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local function LootOff() return not E:BlizzardAllowed(LOOT_ID) end
local function OwnLootOff() return not E:BlizzardAllowed(LOOT_ID, "replace") end
local function BlizzLootMoveOff() return not E:BlizzardAllowed(LOOT_ID, "move") or E:BlizzardHidden(LOOT_ID) end
local function OwnRollsOff() return not E:BlizzardAllowed(ROLL_ID, "replace") end
local function BlizzRollMoveOff() return not E:BlizzardAllowed(ROLL_ID, "move") or E:BlizzardHidden(ROLL_ID) end

local MODES = { blizzard = "Blizzard's", skin = "Blizzard's, EldoUI skin", eldoui = "EldoUI's own" }

-- Preview: three sample rows of EldoUI's loot window in its width, row
-- height and text size, named in their quality colors (E:ConfigSample,
-- Core/MoverSamples.lua).
local function UpdatePreview(canvas)
	local db = M.db
	if not (canvas and db) then return end
	local icons, rows = E.ConfigSampleIcons.items, {}
	for index, quality in ipairs({ 2, 3, 4 }) do
		rows[index] = { icons[index], _G["ITEM_QUALITY" .. quality .. "_DESC"] or L["Item"], quality }
	end
	E:ConfigSample(canvas, "feed", { width = db.width, rowHeight = db.iconSize, fontSize = db.fontSize, items = rows })
end

M.options = {
	{ type = "tab", label = "Loot window" },
	{ type = "preview", label = "Preview", height = 112, create = UpdatePreview, update = UpdatePreview,
		desc = "Sample rows of EldoUI's loot window in its width, row height and text size." },
	{ type = "header", label = "Loot window" },
	{ type = "description", label = "Which loot window you use. This sets the Loot window switches on the Blizzard UI page (Move, Hide and the rest live there too)." },
	{ type = "select", key = "lootMode", label = "Window", values = MODES,
		desc = "Blizzard's window, Blizzard's window in the EldoUI look, or EldoUI's own quality-colored window." },
	{ type = "toggle", key = "atCursor", label = "Open at the mouse", hidden = LootOff,
		desc = "Off uses the spot you set in move mode (/eui move). For Blizzard's window this needs the Move switch and sets the game's \"loot under mouse\" option." },
	{ type = "range", unit = "px", key = "iconSize", label = "Row height", min = 20, max = 48, step = 1, hidden = OwnLootOff,
		desc = "Height of each row and size of its icon in EldoUI's window." },
	{ type = "range", unit = "px", key = "width", label = "Width", min = 180, max = 400, step = 2, hidden = OwnLootOff,
		desc = "Width of EldoUI's loot window." },
	{ type = "range", key = "fontSize", label = "Text size", min = 10, max = 18, step = 1, hidden = OwnLootOff,
		desc = "Size of the item names in EldoUI's window." },
	{ type = "toggle", key = "lootAll", label = "Loot all button", hidden = OwnLootOff,
		desc = "A small button in the title that takes every item when you click it." },
	{ type = "toggle", key = "lootLink", label = "Link button", hidden = OwnLootOff,
		desc = "A small button in the title that posts the items' links to chat when you click it, highest quality first. It shows when there is something to link and a chat to post to." },
	{ type = "select", key = "lootLinkChannel", label = "Link to", dependsOn = "lootLink", hidden = OwnLootOff,
		values = { GROUP = "Your group", PARTY = "Party", RAID = "Raid", SAY = "Say" },
		desc = "Your group posts to the instance group, raid or party you are in." },
	{ type = "select", key = "lootLinkQuality", label = "Lowest quality to link", dependsOn = "lootLink", hidden = OwnLootOff,
		values = { [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic" },
		desc = "Items below this quality are left out of the post." },
	{ type = "header", label = "Master loot", hidden = OwnLootOff },
	{ type = "toggle", key = "masterLoot", label = "Give menu", hidden = OwnLootOff,
		desc = "When you are the master looter and click an item, a menu lists who can take it (by class in a raid) and Request roll. Items from Epic up ask before they are given." },
	{ type = "input", key = "masterBanker", label = "Banker", dependsOn = "masterLoot", hidden = OwnLootOff,
		desc = "A character name the menu lists first as Banker when that player can take the item." },
	{ type = "input", key = "masterDisenchanter", label = "Disenchanter", dependsOn = "masterLoot", hidden = OwnLootOff,
		desc = "A character name the menu lists first as Disenchanter when that player can take the item." },
	{ type = "toggle", key = "masterAnnounce", label = "Post who gets it", dependsOn = "masterLoot", hidden = OwnLootOff,
		desc = "After you give an item, posts the item and the player's name to your group. Off by default." },
	{ type = "header", label = "Item marks", hidden = OwnLootOff },
	{ type = "description", label = "Each mark shows only what the game reports for the item; with all of them off the rows show the name alone.", hidden = OwnLootOff },
	{ type = "toggle", key = "lootBindTag", label = "Bind tag", hidden = OwnLootOff,
		desc = "BoP, BoE or BoU in the icon's corner: the item binds when picked up, when equipped or when used." },
	{ type = "toggle", key = "lootDetails", label = "Slot and type", hidden = OwnLootOff,
		desc = "A second line under the name with where the item is worn and what kind it is." },
	{ type = "toggle", key = "lootValue", label = "Vendor price", hidden = OwnLootOff,
		desc = "What a vendor pays for the whole stack, at the right of the row." },
	{ type = "toggle", key = "lootRoomNotice", label = "Lowest value when loot does not fit", hidden = OwnLootOff,
		desc = "Names the lowest-value stack in your bags when the game says your inventory is full. On by default." },
	{ type = "toggle", key = "lootUpgrade", label = "Upgrade arrow", hidden = OwnLootOff,
		desc = "A green arrow on items that beat what you wear (Upgrades module)." },
	{ type = "toggle", key = "lootNewLook", label = "New look", hidden = OwnLootOff,
		desc = "\"New look\" on items whose appearance you have not collected yet (Appearances module)." },
	{ type = "toggle", key = "lootQuestStart", label = "Starts a quest", hidden = OwnLootOff,
		desc = "\"Starts a quest\" on items that begin a quest when you use them." },
	{ type = "range", percent = true, key = "blizzScale", label = "Blizzard window scale", min = 0.6, max = 1.5, step = 0.05, hidden = BlizzLootMoveOff,
		desc = "Size of Blizzard's loot window while EldoUI moves it." },
	{ type = "toggle", acts = true, key = "fastLoot", label = "Faster auto loot", hidden = LootOff,
		disabled = function()
			local standing, _, title = E:StandsBack(M, "fastloot")
			return standing and L["Handled by %s. Type %s to choose."]:format(title, E:Highlight("/eui addons")) or nil
		end,
		desc = "Acts for you when turned on: when the game auto loots, takes every item at once instead of one by one. Works with either window. Off by default: turn it on here or in the setup." },

	{ type = "toggle", acts = true, key = "skipBindConfirm", label = "Skip solo loot confirmation", hidden = LootOff,
		desc = "Acts for you when turned on: confirms Bind on Pickup items when you loot alone. Group loot and other confirmations still ask. Off by default." },

	{ type = "tab", label = "Rolls" },
	{ type = "header", label = "Group loot rolls" },
	{ type = "description", label = "You always roll yourself: EldoUI never picks Need, Greed or Pass for you." },
	{ type = "select", key = "rollMode", label = "Roll frames", values = MODES, reload = true,
		desc = "Blizzard's roll frames, Blizzard's in the EldoUI look, or EldoUI's roll bars. Going back from EldoUI's bars takes effect after a reload." },
	{ type = "range", unit = "px", key = "rollWidth", label = "Roll bar width", min = 240, max = 480, step = 4, hidden = OwnRollsOff,
		desc = "Width of each EldoUI roll bar." },
	{ type = "range", unit = "px", key = "rollHeight", label = "Roll bar height", min = 28, max = 56, step = 1, hidden = OwnRollsOff,
		desc = "Height of each EldoUI roll bar; the icon and buttons follow it." },
	{ type = "select", key = "rollGrow", label = "New rolls go", values = { DOWN = "Below", UP = "Above" },
		desc = "Which way more rolls stack from the roll spot (EldoUI's bars, and Blizzard's frames with the Move switch)." },
	{ type = "toggle", key = "rollArrows", label = "Upgrade arrows", hidden = OwnRollsOff,
		desc = "A green arrow on items that beat what you wear (Upgrades module)." },
	{ type = "toggle", key = "rollBoP", label = "Mark Bind on Pickup", hidden = OwnRollsOff,
		desc = "A red \"Binds when picked up\" line on items that bind when you win them." },
	{ type = "toggle", key = "rollItemLevel", label = "Item level", hidden = OwnRollsOff,
		desc = "The item level of weapons and armor in the top of the icon." },
	{ type = "toggle", key = "rollMarkBorder", label = "Upgrade and new look border", hidden = OwnRollsOff,
		desc = "The icon's border turns green for an upgrade (Upgrades module) and takes the accent color for an appearance you have not collected (Appearances module)." },
	{ type = "toggle", key = "rollUrgent", label = "Urgent timer", hidden = OwnRollsOff,
		desc = "The timer turns red in the last quarter of the roll's time." },
	{ type = "toggle", key = "rollChoices", label = "Group choices", hidden = OwnRollsOff,
		desc = "How many in your group picked Need, Transmog, Greed or Pass so far, from the game's loot history, above the timer. Point at the counts for the names and who has not chosen yet." },
	{ type = "toggle", key = "rollKeep", label = "Keep after rolling", hidden = OwnRollsOff,
		desc = "After you roll, the bar shows your choice and stays until the game's loot history names the winner, or everyone passed. Without a result it leaves when the roll's time is up." },
	{ type = "range", unit = "s", key = "rollWonTime", label = "Won: seconds shown", min = 1, max = 30, step = 1, dependsOn = "rollKeep", hidden = OwnRollsOff,
		desc = "How long the result stays when you won the item." },
	{ type = "range", unit = "s", key = "rollLostTime", label = "Lost: seconds shown", min = 1, max = 30, step = 1, dependsOn = "rollKeep", hidden = OwnRollsOff,
		desc = "How long the result stays when someone else won or everyone passed." },
	{ type = "range", percent = true, key = "blizzRollScale", label = "Blizzard roll frame scale", min = 0.6, max = 1.4, step = 0.05, hidden = BlizzRollMoveOff,
		desc = "Size of Blizzard's roll frames on EldoUI's roll spot." },
	{ type = "execute", label = "Test bars", desc = "Three sample bars on the roll spot for six seconds. Their buttons do nothing.",
		hidden = OwnRollsOff, func = function() M:TestRolls() end },
	{ type = "header", label = "Loot history" },
	{ type = "description", label = "Blizzard's loot history gets the EldoUI look with the Skin switch, and remembers where you drag it with the Move switch." },
	{ type = "execute", label = "Open loot history", desc = "Opens or closes Blizzard's loot history (also /eui loothistory).",
		func = function() M:ToggleHistory() end },

	{ type = "tab", label = "Toasts and feed" },
	{ type = "header", label = "What you gain" },
	{ type = "toggle", key = "toasts", label = "Show what you loot", desc = "A short card or row for each item, money, reputation, currency and skill-up you gain." },
	{ type = "select", key = "toastMode", label = "Show as", dependsOn = "toasts",
		values = { toast = "Toast cards", feed = "Loot feed" },
		desc = "Toast cards slide in beside the right edge (mover \"Loot Toasts\"). The loot feed is a compact stack of rows in the look you pick (mover \"Loot Feed\")." },
	{ type = "toggle", key = "feedItems", label = "Items", dependsOn = "toasts", desc = "Items you loot, receive or create." },
	{ type = "select", key = "toastQuality", label = "Lowest item quality", dependsOn = "toasts",
		values = { [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic" },
		desc = "Items below this quality are not shown." },
	{ type = "toggle", key = "toastMoney", label = "Money", dependsOn = "toasts", desc = "Money you loot, including your share of a group's money." },
	{ type = "toggle", key = "feedRep", label = "Reputation", dependsOn = "toasts", desc = "Reputation you gain or lose, per faction." },
	{ type = "toggle", key = "feedCurrency", label = "Currencies", dependsOn = "toasts", desc = "Currencies you receive (honor, tokens and the like)." },
	{ type = "toggle", key = "feedSkill", label = "Skill-ups", dependsOn = "toasts", desc = "Weapon and profession skills going up." },
	{ type = "toggle", key = "feedCrafted", label = "Items you make", dependsOn = "toasts", desc = "Items you create, such as crafted goods and conjured food." },
	{ type = "toggle", key = "feedXP", label = "Experience", dependsOn = "toasts", desc = "Experience from kills, quests and exploring, added up in one row." },
	{ type = "toggle", key = "feedHonor", label = "Honor", dependsOn = "toasts", desc = "Honor you gain." },
	{ type = "toggle", key = "feedOthers", label = "Group members' loot", dependsOn = "toasts",
		desc = "What party and raid members loot, with their name in class colors. A loot line the game hides adds nothing.",
		cog = {
			{ type = "select", key = "feedOthersQuality", label = "Lowest item quality",
				values = { [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic" },
				desc = "Their items below this quality are not shown." },
			{ type = "range", unit = "s", key = "feedOthersTime", label = "Seconds on screen", min = 2, max = 10, step = 1,
				desc = "How long a row of their loot stays." },
		} },
	{ type = "toggle", key = "feedCapped", label = "Capped currencies", dependsOn = "toasts", desc = "Capped on a currency row when you are at its cap." },
	{ type = "toggle", key = "feedBagCount", label = "Total in bags", dependsOn = "toasts", desc = "How many of the item you now have in your bags, on the row's icon." },
	{ type = "toggle", key = "feedMerge", label = "Add up repeats", dependsOn = "toasts",
		desc = "A second gain of the same item, money or faction while its row is still shown adds to that row instead of opening a new one." },
	{ type = "toggle", key = "feedItemLevel", label = "Item level", dependsOn = "toasts", desc = "The item level of weapons and armor, in gray beside the name." },
	{ type = "toggle", key = "feedValue", label = "Vendor price", dependsOn = "toasts", desc = "What a vendor pays for the looted stack, beside the name." },
	{ type = "range", unit = "s", key = "toastTime", label = "Seconds on screen", min = 2, max = 10, step = 1, dependsOn = "toasts", desc = "How long each card or row stays. Its time stops while the mouse is over it, and a right-click closes it." },
	{ type = "range", key = "toastMax", label = "Toasts at once", min = 1, max = 10, step = 1, dependsOn = "toasts", hidden = function() return M.db.toastMode == "feed" end,
		desc = "How many toast cards show at once. More wait their turn, and cards for loot in combat wait until the fight ends. The Loot Toasts mover is as tall as these cards." },
	{ type = "toggle", key = "toastLegendary", label = "Legendary title", dependsOn = "toasts", hidden = function() return M.db.toastMode == "feed" end,
		desc = "\"Legendary!\" in the legendary color on the card of a legendary item." },
	{ type = "media", mediaKind = "sound", none = true, key = "toastSound", label = "Sound", dependsOn = "toasts",
		desc = "A sound when a new card or row appears; several at once play it once. Fanfare's loot sounds are separate." },
	{ type = "media", mediaKind = "sound", none = true, key = "toastSoundLegendary", label = "Legendary sound", dependsOn = "toasts",
		desc = "Its own sound for a legendary item. None plays the sound above." },
	{ type = "execute", label = "Show samples", desc = "One sample for every source you have on, in the current look.", testSafe = true,
		func = function() M:ShowSamples() end },
	{ type = "header", label = "Loot feed look", hidden = function() return M.db.toastMode ~= "feed" end },
	{ type = "select", key = "feedStyle", label = "Look", dependsOn = "toasts", hidden = function() return M.db.toastMode ~= "feed" end,
		values = { rows = "Rows", bar = "Accent bar", tiles = "Icon tiles", cards = "Cards" },
		desc = "Rows: a bordered box per gain. Accent bar: a colored bar on a fading background. Icon tiles: a big icon with the name beside it. Cards: framed like the toasts." },
	{ type = "range", key = "feedRows", label = "Rows at most", min = 3, max = 15, step = 1, dependsOn = "toasts", hidden = function() return M.db.toastMode ~= "feed" end,
		desc = "When the feed is full, the oldest row makes room." },
	{ type = "select", key = "feedGrow", label = "New rows go", dependsOn = "toasts", hidden = function() return M.db.toastMode ~= "feed" end,
		values = { UP = "Up (newest at the bottom)", DOWN = "Down (newest at the top)" }, desc = "Which way the feed grows from its mover." },
	{ type = "toggle", key = "feedQualityBorder", label = "Quality border", dependsOn = "toasts", hidden = function() return M.db.toastMode ~= "feed" end,
		desc = "Item rows take the item's quality color on their border.",
		cog = {
			{ type = "range", unit = "px", key = "feedRowHeight", label = "Row height", min = 16, max = 40, step = 1, desc = "Height of each row; the icon follows it." },
			{ type = "range", unit = "px", key = "feedWidth", label = "Width", min = 160, max = 480, step = 4, desc = "Width of the feed." },
			{ type = "range", key = "feedFontSize", label = "Text size", min = 9, max = 18, step = 1, desc = "Text size in the feed." },
		} },
}

-- Faster auto loot acts for the player: listed for the setup's Convenience
-- step and the Conveniences page (Core/Conveniences.lua), off until ticked.
E:RegisterConvenience({ id = "fastLoot", module = "Loot", setting = "fastLoot", order = 50,
	label = "Faster auto loot",
	desc = "Acts for you: when the game auto loots, every item is taken at once instead of one by one.",
	suits = E.ConvenienceRules.Everyone,
	blocked = function()
		local standing, _, title = E:StandsBack(M, "fastloot")
		if standing then return L["Handled by %s. Type %s to choose."]:format(title, E:Highlight("/eui addons")) end
		return E:BlizzardNeedsReason(LOOT_ID)
	end })

E:RegisterConvenience({ id = "skipBindConfirm", module = "Loot", setting = "skipBindConfirm", order = 55,
	label = "Skip solo loot confirmation",
	desc = "Acts for you: confirms Bind on Pickup items when you loot alone. Group loot and other confirmations still ask. Change this in Loot settings.",
	blocked = function() return E:BlizzardNeedsReason(LOOT_ID) end })

---------------------------------------------------------------------------
-- Style presets
---------------------------------------------------------------------------
E:RegisterStyles("Loot", {
	{ key = "EldoUI", title = "EldoUI", desc = "EldoUI's loot window at the mouse, roll bars, toasts from Uncommon.",
		settings = { lootMode = "eldoui", rollMode = "eldoui", atCursor = true, iconSize = 32, width = 240, fontSize = 14,
			lootAll = true, rollWidth = 320, rollHeight = 40, rollGrow = "DOWN", rollArrows = true, rollBoP = true,
			toasts = true, toastMode = "toast", toastQuality = 2, toastMoney = true, toastTime = 4 } },
	{ key = "Compact", title = "Compact", desc = "Small rows and slim roll bars, fewer toasts.",
		settings = { lootMode = "eldoui", rollMode = "eldoui", iconSize = 24, width = 200, fontSize = 12,
			rollWidth = 260, rollHeight = 30, toasts = true, toastQuality = 3, toastMoney = false, toastTime = 3 } },
	{ key = "Large", title = "Large", desc = "Big rows and roll bars for high resolutions.",
		settings = { lootMode = "eldoui", rollMode = "eldoui", iconSize = 40, width = 300, fontSize = 16,
			rollWidth = 400, rollHeight = 50, toasts = true, toastQuality = 2, toastTime = 5 } },
	{ mode = true, key = "Fixed", title = "Fixed spot", desc = "The loot window always opens on its mover; rolls stack upwards.",
		settings = { lootMode = "eldoui", rollMode = "eldoui", atCursor = false, rollGrow = "UP" } },
	{ key = "BlizzardSkinned", title = "Blizzard, skinned", desc = "Blizzard's own loot and roll frames in the EldoUI look.",
		settings = { lootMode = "skin", rollMode = "skin", toasts = true } },
	{ mode = true, key = "Quiet", title = "Quiet", desc = "EldoUI windows without toasts.",
		settings = { lootMode = "eldoui", rollMode = "eldoui", toasts = false } },
	{ key = "Feed", title = "Loot feed", desc = "EldoUI windows and a compact loot feed of everything you gain, repeats added up.",
		settings = { lootMode = "eldoui", rollMode = "eldoui", toasts = true, toastMode = "feed", feedStyle = "rows", feedRows = 8,
			feedRowHeight = 24, feedWidth = 280, feedMerge = true, feedItems = true, toastMoney = true, feedRep = true,
			feedCurrency = true, feedSkill = true, toastQuality = 1 } },
})
