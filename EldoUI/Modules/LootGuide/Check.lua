-- EldoUI Loot Guide: the item check and roll advice.
--
--   E:GetLootVerdict(link[, canNeed]) -> verdict (one answer for the roll
--       box, the check card and the tooltip line):
--       { itemID, link, kind, text, color, gainText, percent, dps, delta,
--         upgrade, usable, bis, wish, fromLevel, replaces = { link, ... },
--         suggestion = "NEED" | "GREED" | "PASS" | nil, reason }
--       kind: "upgrade", "empty" (fills an empty slot), "same", "down",
--       "worn", "level" (from level N), "notforyou", "unknown" (not rated
--       yet), "nogear" (not equipment).
--   LG:OpenCheck(link)   the check card (mover EldoUI_LootCheck): icon, name,
--       what it replaces, the verdict, a source line and Wishlist / Set 1 /
--       Set 2 buttons. Esc or 20 s without the mouse over it close it.
--   E:UpdateRollVerdict(bar, rollID)  the roll box (168 x 40) beside a roll
--       bar or a Blizzard roll frame (Modules/Loot.lua calls it).
--   Alt-click (or Ctrl+Alt, the Item check option) on an item in bags, the
--       loot window, chat or any Loot Guide list opens the card. The click
--       itself is not changed (a post-hook), and nothing happens at a
--       merchant or a mailbox.
--
-- Advice only. The suggestion is a word in a separate box: nothing here
-- rolls (RollOnLoot / ConfirmLootRoll are never called), presses, glows,
-- locks or preselects a roll button.
local _, E = ...
local LG = E.LootGuide
local L = E.L

local Key = E.Key
local CARD_W, CARD_H = 300, 140
local BOX_W, BOX_H = 168, 40
local IDLE_CLOSE = 20
local SAME_PERCENT = 1

local Secret = E.Secret

local function Hex(r, g, b)
	return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

local GOOD = E.tokens.text.good
local WARN = E.tokens.text.warn
local BAD = E.tokens.text.bad
local GREY = E.tokens.text.secondary
local WHITE = { 0.92, 0.92, 0.94 }

-- Slot names: the client's own strings (INVTYPE_*), else ours.
local SLOT_NAME = {
	{ "INVTYPE_HEAD", Key("Head") }, { "INVTYPE_NECK", Key("Neck") }, { "INVTYPE_SHOULDER", Key("Shoulder") },
	{ "INVTYPE_BODY", Key("Shirt") }, { "INVTYPE_CHEST", Key("Chest") }, { "INVTYPE_WAIST", Key("Waist") },
	{ "INVTYPE_LEGS", Key("Legs") }, { "INVTYPE_FEET", Key("Feet") }, { "INVTYPE_WRIST", Key("Wrist") },
	{ "INVTYPE_HAND", Key("Hands") }, { "INVTYPE_FINGER", Key("Finger") }, { "INVTYPE_FINGER", Key("Finger") },
	{ "INVTYPE_TRINKET", Key("Trinket") }, { "INVTYPE_TRINKET", Key("Trinket") }, { "INVTYPE_CLOAK", Key("Back") },
	{ "INVTYPE_WEAPONMAINHAND", Key("Main hand") }, { "INVTYPE_WEAPONOFFHAND", Key("Off hand") },
	{ "INVTYPE_RANGED", Key("Ranged") }, { "INVTYPE_TABARD", Key("Tabard") },
}
function LG:SlotLabel(slot)
	local entry = SLOT_NAME[slot or 0]
	if not entry then return (L["Slot %d"]):format(slot or 0) end
	local name = rawget(_G, entry[1])
	return type(name) == "string" and name or L[entry[2]]
end

---------------------------------------------------------------------------
-- The verdict
---------------------------------------------------------------------------
local function ItemIDOf(link)
	if Secret(link) then return end
	if type(link) == "number" then return link end
	if type(link) ~= "string" then return end
	return tonumber(link:match("item:(%d+)")) or tonumber(link)
end

local function SpecName()
	local engine = E.ItemScore
	local spec = engine and engine.PlayerSpec and engine:PlayerSpec()
	local info = spec and engine:SpecInfo(spec)
	return info and info.name, info and info.role
end

local function GainText(result)
	if type(result.dps) == "number" then return L["%+.1f DPS"]:format(result.dps) end
	if type(result.percent) == "number" then return ("%+.1f%%"):format(result.percent) end
	if type(result.delta) == "number" then return ("%+.1f"):format(result.delta) end
end

-- What the item would replace: the worn item in its slot (rings and
-- trinkets: both slots), as links.
local function Replaces(itemID, slot)
	local out = {}
	local slots = LG:ItemSlots(itemID) or {}
	if #slots > 1 and slots[1] ~= 16 then
		for _, s in ipairs(slots) do
			local link = GetInventoryItemLink("player", s)
			if not Secret(link) and link then out[#out + 1] = link end
		end
	elseif slot or slots[1] then
		local link = GetInventoryItemLink("player", slot or slots[1])
		if not Secret(link) and link then out[1] = link end
	end
	return out
end

local NOT_FOR_YOU = {
	class = Key("Your class can't use it"), race = Key("Your race can't use it"),
	armor = Key("You can't wear this armor"), weapon = Key("You can't use this weapon type"),
	skill = Key("Needs a profession skill you don't have"),
}

local function Bound(link)
	local itemID = ItemIDOf(link)
	if not itemID then return false end
	local bind = select(14, C_Item.GetItemInfo(link))
	if Secret(bind) then return false end
	return bind == 1
end

function E:GetLootVerdict(link, canNeed)
	local itemID = ItemIDOf(link)
	if not itemID then return end
	if type(link) ~= "string" or not link:find("item:", 1, true) then
		local _, full = C_Item.GetItemInfo(itemID)
		link = (not Secret(full) and full) and full or ("item:" .. itemID)
	end
	local verdict = { itemID = itemID, link = link, replaces = {} }
	local active = LG.active
	verdict.wish = active and LG:WishlistOn() and LG:IsWished(itemID) or false
	local bis = active and LG.IsBiS and LG:IsBiS(itemID)
	verdict.bis = bis and true or false
	local slots = LG:ItemSlots(itemID)
	local specName, role = SpecName()
	local reason

	if not slots then
		verdict.kind, verdict.text, verdict.color = "nogear", L["Not equipment"], GREY
		verdict.usable = true
	else
		local engine = E.ItemScore
		local result = engine and engine:Rate(link, "player")
		local record = LG:ItemRecord(itemID)
		local ok, why = LG:CanUseRecord(record, true)
		local useLevel = LG:UseLevel(itemID) or 1
		local level = LG:Player().level
		verdict.replaces = Replaces(itemID, result and result.slot)
		if result then
			verdict.percent, verdict.dps, verdict.delta = result.percent, result.dps, result.delta
			verdict.usable = result.usable ~= false and ok
		else
			verdict.usable = ok
		end
		-- A tank in light armor: the class can wear it, the role should not.
		if verdict.usable and role == "TANK" and record and record.class == 4 and record.subclass and record.subclass > 0
			and record.subclass < LG:HeaviestArmor() and record.invType ~= 16 then
			verdict.usable, why = false, "light"
		end
		if not verdict.usable then
			verdict.kind, verdict.color = "notforyou", BAD
			local text = why == "light" and L["Armor too light for a tank"] or E:Translate(NOT_FOR_YOU[why or ""]) or L["You can't use this"]
			verdict.text = (L["Not for you: %s"]):format(text)
			reason = text
		elseif result and result.worn then
			verdict.kind, verdict.text, verdict.color = "worn", L["Already worn"], GREY
		elseif useLevel > level then
			verdict.kind, verdict.color, verdict.fromLevel = "level", WARN, useLevel
			verdict.text = (L["From level %d"]):format(useLevel)
			reason = verdict.text
		elseif not result then
			verdict.kind, verdict.text, verdict.color = "unknown", L["Not rated yet"], GREY
			reason = L["The game has not sent this item's stats yet."]
		elseif result.base == nil and not result.worn then
			verdict.kind, verdict.text, verdict.color, verdict.upgrade = "empty", L["Fills an empty slot"], GOOD, true
		elseif result.upgrade then
			verdict.kind, verdict.color, verdict.upgrade = "upgrade", GOOD, true
			verdict.text = L["Upgrade"]
		elseif type(result.percent) == "number" and math.abs(result.percent) < SAME_PERCENT then
			verdict.kind, verdict.text, verdict.color = "same", L["About the same"], WHITE
		else
			verdict.kind, verdict.text, verdict.color = "down", L["Not an upgrade"], GREY
		end
		if verdict.kind == "upgrade" or verdict.kind == "down" or verdict.kind == "same" then
			verdict.gainText = result and GainText(result)
		end
		if verdict.kind == "upgrade" then
			local worn = verdict.replaces[1]
			local wornName = worn and C_Item.GetItemInfo(worn)
			if Secret(wornName) then wornName = nil end
			local gain = verdict.gainText or ""
			if wornName then
				reason = (L["Upgrade for %s, beats your %s by %s"]):format(specName or L["your spec"], wornName, gain)
			else
				reason = (L["Upgrade for %s by %s"]):format(specName or L["your spec"], gain)
			end
		elseif verdict.kind == "empty" then
			reason = (L["Upgrade for %s: nothing is worn in that slot"]):format(specName or L["your spec"])
		elseif verdict.kind == "down" then
			reason = (L["Your gear is better for %s"]):format(specName or L["your spec"])
		elseif verdict.kind == "same" then
			reason = L["About as good as what you wear"]
		elseif verdict.kind == "worn" then
			reason = L["You wear this item"]
		end
	end

	-- Need when you can use it and it is an upgrade, best in slot or on
	-- your wishlist, and the roll lets you Need; else Greed, or Pass for a
	-- bound item that is no use to you.
	local wanted = verdict.usable and verdict.kind ~= "level" and verdict.kind ~= "worn"
		and (verdict.upgrade or verdict.bis or verdict.wish)
	if verdict.kind == "nogear" then wanted = verdict.wish end
	if wanted and canNeed ~= false then
		verdict.suggestion = "NEED"
		if verdict.wish and not verdict.upgrade then reason = reason or L["On your wishlist"] end
		if verdict.bis and not verdict.upgrade then reason = reason or L["Best in Slot for you"] end
	elseif not verdict.usable and Bound(link) then
		verdict.suggestion = "PASS"
	else
		verdict.suggestion = "GREED"
		if wanted and canNeed == false then reason = (reason and (reason .. ". ") or "") .. L["You can't Need on this roll."] end
	end
	verdict.reason = reason
	return verdict
end

LG.SUGGESTION = {
	NEED = { Key("Need"), GOOD }, GREED = { Key("Greed"), WHITE }, PASS = { Key("Pass"), GREY },
}

-- "+6.2%" green, "No gain" gray, with the BiS / Wish badges.
function LG:VerdictLine(verdict)
	if not verdict then return "" end
	local text
	if verdict.kind == "upgrade" and verdict.gainText then
		text = Hex(unpack(GOOD)) .. verdict.gainText .. "|r"
	elseif verdict.kind == "empty" then
		text = Hex(unpack(GOOD)) .. L["Empty slot"] .. "|r"
	elseif verdict.kind == "down" or verdict.kind == "same" then
		text = Hex(unpack(GREY)) .. L["No gain"] .. "|r"
	else
		text = Hex(unpack(verdict.color or GREY)) .. (verdict.text or "") .. "|r"
	end
	local badges = {}
	if verdict.bis then badges[#badges + 1] = E:TextHex("accent") .. L["BiS"] .. "|r" end
	if verdict.wish then badges[#badges + 1] = E:TextHex("accent") .. L["Wish"] .. "|r" end
	if #badges > 0 then text = text .. "  " .. table.concat(badges, " ") end
	return text
end

function LG:SuggestionText(verdict)
	local entry = verdict and verdict.suggestion and self.SUGGESTION[verdict.suggestion]
	if not entry then return "" end
	return Hex(unpack(GREY)) .. L["Suggest"] .. "|r " .. Hex(unpack(entry[2])) .. L[entry[1]] .. "|r"
end

---------------------------------------------------------------------------
-- Which click opens the card
---------------------------------------------------------------------------
function LG:CheckMode()
	local mode = self.db and self.db.check or "ALT"
	if mode ~= "ALT" and mode ~= "CTRLALT" then return "OFF" end
	return mode
end

function LG:IsCheckClick()
	if not self.active then return false end
	local mode = self:CheckMode()
	if mode == "OFF" then return false end
	if not IsAltKeyDown() or IsShiftKeyDown() then return false end
	if mode == "CTRLALT" then return IsControlKeyDown() and true or false end
	return not IsControlKeyDown()
end

-- The hint line in item tooltips ("Alt-click: open the item check"), in
-- the look of the kit's click hints, then its action and what it does.
function LG:CheckHint()
	local mode = self:CheckMode()
	local action
	if mode == "ALT" then action = L["Alt-click"] elseif mode == "CTRLALT" then action = L["Ctrl+Alt-click"] end
	if not action then return nil end
	local what = L["open the item check"]
	return L["%s: %s"]:format("|cffffffff" .. action .. "|r", what), action, what
end

---------------------------------------------------------------------------
-- The check card
---------------------------------------------------------------------------
local card

local function SetButton(index)
	local data = LG:Char()
	return data and data.sets[index]
end

local function InSet(index, itemID)
	local set = SetButton(index)
	for _, id in pairs(set and set.slots or {}) do
		if id == itemID then return true end
	end
	return false
end

local function ToggleSet(index, itemID)
	local set = SetButton(index)
	if not set then return end
	if InSet(index, itemID) then
		for slot, id in pairs(set.slots) do
			if id == itemID then set.slots[slot] = nil end
		end
		LG:Fire("sets")
	else
		LG:PutInSet(index, itemID)
	end
end

local function UpdateButtons()
	if not card or not card.itemID then return end
	local itemID = card.itemID
	local wished = LG:IsWished(itemID)
	card.wish:SetText(wished and L["Wished"] or L["Wishlist"])
	card.wish:SetShown(LG:WishlistOn())
	local gear = LG:ItemSlots(itemID) ~= nil and LG:BiSOn()
	for index = 1, 2 do
		local button = card.sets[index]
		button:SetShown(gear)
		local name = LG:SetName(index)
		button:SetText(InSet(index, itemID) and ((L["In %s"]):format(name)) or name)
	end
end

local function Fill()
	local link = card.link
	local verdict = E:GetLootVerdict(link)
	card.verdict = verdict
	if not verdict then return end
	local name, full, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(link)
	if Secret(name) then name, full, quality, icon = nil, nil, nil, nil end
	if not name then
		local record = LG:ItemRecord(verdict.itemID)
		name, quality = record and record.name, record and record.quality
		LG:RequestItem(verdict.itemID, function()
			if card and card:IsShown() and card.itemID == verdict.itemID then Fill() end
		end)
	end
	card.link = full or link
	card.icon:SetTexture(icon or C_Item.GetItemIconByID(verdict.itemID) or 134400)
	card.name:SetText(name or ("item:" .. verdict.itemID))
	local r, g, b = LG.Kit.QualityColor(quality)
	card.name:SetTextColor(r, g, b)
	-- vs. equipped
	local vs = {}
	for _, worn in ipairs(verdict.replaces) do
		local wornName, _, wornQuality = C_Item.GetItemInfo(worn)
		if Secret(wornName) then wornName = nil end
		if wornName then
			local wr, wg, wb = LG.Kit.QualityColor(wornQuality)
			vs[#vs + 1] = Hex(wr, wg, wb) .. wornName .. "|r"
		end
	end
	if verdict.kind == "nogear" then
		card.vs:SetText("")
	elseif #vs > 0 then
		card.vs:SetText(Hex(unpack(GREY)) .. L["vs. equipped"] .. "|r " .. table.concat(vs, Hex(unpack(GREY)) .. " / |r"))
	else
		card.vs:SetText(Hex(unpack(GREY)) .. L["Nothing worn in that slot"] .. "|r")
	end
	local line = LG:VerdictLine(verdict)
	if verdict.kind == "upgrade" or verdict.kind == "down" or verdict.kind == "same" then
		line = Hex(unpack(verdict.color)) .. verdict.text .. "|r  " .. line
	end
	card.verdictText:SetText(line)
	local P = LG.PageKit
	local sources = LG:ItemSources(verdict.itemID)
	card.source:SetText(P and sources and sources[1] and P.SourceLine(sources[1]) or "")
	card.itemID = verdict.itemID
	UpdateButtons()
end

local function Idle(self, elapsed)
	if self:IsMouseOver() or (self.wish and self.wish:IsMouseOver()) then
		self.idle = 0
		return
	end
	self.idle = (self.idle or 0) + elapsed
	if self.idle >= IDLE_CLOSE then self:Hide() end
end

local function BuildCard()
	if card then return card end
	local Kit = LG.Kit
	card = CreateFrame("Frame", "EldoUI_LootCheck", UIParent)
	card:SetSize(CARD_W, CARD_H)
	card:SetFrameStrata("DIALOG")
	card:SetToplevel(true)
	card:SetClampedToScreen(true)
	card:EnableMouse(true)
	card:Hide()
	E:SkinPanel(card, { accentOffset = 2, insets = false, title = false, close = false })
	table.insert(UISpecialFrames, "EldoUI_LootCheck")
	card.iconBox = CreateFrame("Frame", nil, card)
	card.iconBox:SetSize(36, 36)
	card.iconBox:SetPoint("TOPLEFT", 10, -12)
	E:SetTemplate(card.iconBox)
	card.icon = card.iconBox:CreateTexture(nil, "ARTWORK")
	card.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	card.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(card.icon)
	card.iconBox:EnableMouse(true)
	card.iconBox:SetScript("OnEnter", function(self)
		if not card.link then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		if card.link:find("|H", 1, true) then GameTooltip:SetHyperlink(card.link) else GameTooltip:SetItemByID(card.itemID) end
		GameTooltip:Show()
	end)
	card.iconBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
	card.close = CreateFrame("Button", nil, card, "UIPanelCloseButton")
	card.close:SetPoint("TOPRIGHT", -2, -4)
	E:SkinCloseButton(card.close)
	card.close:SetScript("OnClick", function() card:Hide() end)
	card.name = Kit.Text(card, 13, "LEFT")
	-- The room the close button takes at the top right, with its gaps.
	local closeGap = card.close:GetWidth() + 2 + 4
	card.name:SetPoint("TOPLEFT", card.iconBox, "TOPRIGHT", 8, 0)
	card.name:SetPoint("TOPRIGHT", -closeGap, -12)
	card.name:SetWordWrap(false)
	card.vs = Kit.Text(card, 11, "LEFT")
	card.vs:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
	card.vs:SetPoint("TOPRIGHT", card.name, "BOTTOMRIGHT", closeGap - 10, -4)
	card.vs:SetWordWrap(false)
	card.verdictText = Kit.Text(card, 12, "LEFT")
	card.verdictText:SetPoint("TOPLEFT", card.iconBox, "BOTTOMLEFT", 0, -8)
	card.verdictText:SetPoint("TOPRIGHT", -10, -(12 + 36 + 8))
	card.verdictText:SetWordWrap(false)
	local verdictHit = CreateFrame("Frame", nil, card)
	verdictHit:SetAllPoints(card.verdictText)
	verdictHit:EnableMouse(true)
	Kit.Tooltip(verdictHit, L["Verdict"], function(tooltip)
		local v = card.verdict
		local r, g, b = unpack(Kit.SECONDARY)
		if v and v.reason then tooltip:AddLine(v.reason, r, g, b, true) end
		tooltip:AddLine(L["Rated by your spec's stat weights, the same numbers the Upgrades arrows show."], r, g, b, true)
	end)
	card.source = Kit.Text(card, 11, "LEFT", "secondary")
	card.source:SetPoint("TOPLEFT", card.verdictText, "BOTTOMLEFT", 0, -4)
	card.source:SetPoint("TOPRIGHT", card.verdictText, "BOTTOMRIGHT", 0, -4)
	card.source:SetWordWrap(false)
	card.wish = Kit.Button(card, L["Wishlist"], 88, 20, function()
		if card.itemID then LG:ToggleWished(card.itemID) end
		C_Timer.After(0, function() if card:IsShown() then Fill() end end)
	end, L["Wishlist"], L["Adds the item to your active wishlist, or takes it off."])
	card.wish:SetPoint("BOTTOMLEFT", 10, 10)
	card.sets = {}
	for index = 1, 2 do
		local button = Kit.Button(card, LG:SetName(index), 88, 20, function()
			if card.itemID then ToggleSet(index, card.itemID) end
			C_Timer.After(0, function() if card:IsShown() then Fill() end end)
		end, (L["Plan set %d"]):format(index), L["Puts the item in this plan set on the Best in Slot page, or takes it out. Plan sets are plans, not equipment sets."])
		button:SetPoint("LEFT", index == 1 and card.wish or card.sets[1], "RIGHT", 6, 0)
		card.sets[index] = button
	end
	card:SetScript("OnShow", function(self) self.idle = 0 end)
	card:SetScript("OnUpdate", Idle)
	return card
end

function LG:OnEnableCheck()
	if self.checkMover then return end
	BuildCard()
	self.checkMover = E:CreateMover(card, "EldoUI_LootCheck", L["Item Check"], { "CENTER", "UIParent", "CENTER", -570, 380 }, { sample = false })
end

function LG:OpenCheck(link)
	if not self.active or Secret(link) or not link then return end
	BuildCard()
	if not self.checkMover then self:OnEnableCheck() end
	card.link = link
	card.itemID = ItemIDOf(link)
	if not card.itemID then return end
	card.idle = 0
	Fill()
	E:SlideIn(card, "DOWN")
end

function LG:CheckCard()
	return card
end

LG:On("check-card", function(changed)
	if card and card:IsShown() and (changed.wishlist or changed.sets or changed.gear or changed.spec or changed.items) then Fill() end
end)

---------------------------------------------------------------------------
-- Alt-click on items anywhere (post-hook, the click itself is unchanged)
---------------------------------------------------------------------------
local function AtVendorOrMail()
	local merchant = rawget(_G, "MerchantFrame")
	local mail = rawget(_G, "MailFrame")
	return (merchant and merchant:IsShown()) or (mail and mail:IsShown()) or false
end

local hooked
function LG:HookCheckClicks()
	if hooked or not hooksecurefunc or not rawget(_G, "HandleModifiedItemClick") then return end
	hooked = true
	hooksecurefunc("HandleModifiedItemClick", function(link)
		if not LG.active or Secret(link) or type(link) ~= "string" or not link:find("item:", 1, true) then return end
		if not LG:IsCheckClick() or AtVendorOrMail() then return end
		LG:OpenCheck(link)
	end)
end

---------------------------------------------------------------------------
-- Roll box: beside each roll bar (Loot module) or Blizzard roll frame
---------------------------------------------------------------------------
local function BuildBox(owner)
	local Kit = LG.Kit
	local box = CreateFrame("Frame", nil, owner)
	box:SetSize(BOX_W, BOX_H)
	box:SetFrameLevel(owner:GetFrameLevel() + 5)
	E:SetTemplate(box, true)
	box:EnableMouse(true)
	box.gain = Kit.Text(box, 12, "LEFT")
	box.gain:SetPoint("TOPLEFT", 8, -6)
	box.gain:SetPoint("TOPRIGHT", -6, -6)
	box.gain:SetWordWrap(false)
	box.suggest = Kit.Text(box, 11, "LEFT")
	box.suggest:SetPoint("BOTTOMLEFT", 8, 6)
	box.suggest:SetPoint("BOTTOMRIGHT", -6, 6)
	box.suggest:SetWordWrap(false)
	box:SetScript("OnEnter", function(self)
		local verdict = self.verdict
		if not verdict then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		E.UIKit.TipTitle(GameTooltip, L["Loot Guide"])
		local r, g, b = unpack(Kit.SECONDARY)
		if verdict.reason then GameTooltip:AddLine(verdict.reason, r, g, b, true) end
		GameTooltip:AddLine(L["Advice only: you roll yourself."], r, g, b, true)
		GameTooltip:Show()
	end)
	box:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return box
end

-- The side of the owner with room on screen.
local function PlaceBox(box, owner)
	box:ClearAllPoints()
	local left = owner:GetLeft()
	local scale = owner:GetEffectiveScale() / UIParent:GetEffectiveScale()
	if left and left * scale > BOX_W + 12 then
		box:SetPoint("RIGHT", owner, "LEFT", -4, 0)
	else
		box:SetPoint("LEFT", owner, "RIGHT", 4, 0)
	end
end

-- Roll frame -> its verdict box. Kept here, never as a field on the roll
-- frame (Blizzard's GroupLootFrameN would be tainted by a new key).
local verdictBoxes = setmetatable({}, { __mode = "k" })

function E:UpdateRollVerdict(owner, rollID)
	if not owner then return end
	local box = verdictBoxes[owner]
	local on = LG.active and LG.db and LG.db.rollBox and rollID ~= nil
	local link = on and GetLootRollItemLink and GetLootRollItemLink(rollID) or nil
	if Secret(link) or not link then
		if box then box:Hide() end
		return
	end
	local canNeed = select(6, GetLootRollItemInfo(rollID))
	if Secret(canNeed) then canNeed = nil end
	local verdict = E:GetLootVerdict(link, canNeed)
	if not verdict then
		if box then box:Hide() end
		return
	end
	box = box or BuildBox(owner)
	verdictBoxes[owner] = box
	box.verdict = verdict
	box.gain:SetText(LG:VerdictLine(verdict))
	box.suggest:SetText(LG.db.suggest and LG:SuggestionText(verdict) or "")
	box:SetHeight(LG.db.suggest and BOX_H or 24)
	PlaceBox(box, owner)
	box:Show()
	return box
end
