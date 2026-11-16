-- EldoUI Trade: the Blizzard trade window (element "trade").
--
-- Nothing changes unless the player ticks "Let EldoUI change this" for the
-- trade window under Blizzard UI:
--   skin     EldoUI look for the window, its item slots and buttons (a
--            reload undoes it). The green "accepted" glow stays the game's.
--   move     a mover and a scale for the window
--   improve  a strip under the window with who you trade with (class
--            colored name, level, race, guild, and a friend or guild-mate
--            tag) and what each side offers is worth: the vendor value and,
--            with the Auction House module, the value at your saved prices.
-- Plus a gold trade log (works without the Blizzard UI switch): every
-- completed trade that moved gold is saved account-wide with who, where and
-- how much each way, shown in the Trade log window (/eui trades) and, if
-- wanted, as one line in chat.
-- Presentation only: it shows what the game tells every player, never
-- clicks Trade or Accept, and never changes what is traded.
-- Written from scratch for EldoUI; no code or media from other addons.
local _, E = ...
local L = E.L

local M = E:NewModule("Trade", {
	title = "Trade",
	category = "Items & Economy",
	desc = "Trade window look, mover, who you trade with, what each side's items are worth, and a gold trade log.",
	frames = { "EldoUI_TradeInfo" },
	movers = { "EldoUI_TradeWindow" },
	blizzard = { "trade" },
	savedKeys = { "profile.modules.Trade", "EldoUIDB.trades" },
	optionsPage = "module:Trade",
	presets = { "Standard", "Compact", "Header", "Large", "Partner" },
	defaults = {
		partnerInfo = true,
		classColor = true,
		partnerTags = true,
		valueLine = true,
		valueAuction = true,
		valueMoney = "general", -- general (Fonts and text > Money) / icons / letters / short
		position = "below",     -- below or above the window
		fontSize = 12,
		infoHeight = 40,
		accentBorder = false,
		-- Gold trade log
		tradeLog = true,
		tradeChat = true,
		tradeLogSize = 300,
		exportTime = true,
		exportZone = true,
		exportAgo = false,
	},
})

-- "Reset to defaults" keeps the player's own data and window places
-- (E:ResetModuleSettings, Core/Config.lua).
M.keepOnReset = { "tradeLogPoint" }

local floor = math.floor
local PARTNER = "NPC"           -- the game's unit token for your trade partner
local SLOTS = 6                 -- slot 7 is "will not be traded"

local function Allowed(action)
	return M.active and E:BlizzardAllowed("trade", action)
end

local IsSecret = E.Secret

-- Calls that may not exist on this client, or may return secret values.
local function Get(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d = pcall(fn, ...)
	if not ok or IsSecret(a) then return nil end
	return a, b, c, d
end

local function Money(copper)
	copper = floor((copper or 0) + 0.5)
	return E:FormatMoney(copper, M.db.valueMoney)
end

---------------------------------------------------------------------------
-- Partner info: only what the game shows every player about the unit.
---------------------------------------------------------------------------
local function PartnerText()
	if not UnitExists(PARTNER) then return nil end
	local name = Get(UnitName, PARTNER)
	if not name then return nil end
	local parts = {}
	local _, classFile = Get(UnitClass, PARTNER)
	local color = M.db.classColor and E:ClassColorObject(classFile)
	parts[#parts + 1] = color and color:WrapTextInColorCode(name) or name
	local level = Get(UnitLevel, PARTNER)
	local race = Get(UnitRace, PARTNER)
	local class = Get(UnitClass, PARTNER)
	local detail = {}
	if level and level > 0 then detail[#detail + 1] = LEVEL and (LEVEL .. " " .. level) or L["Level %d"]:format(level) end
	if race then detail[#detail + 1] = race end
	if class then detail[#detail + 1] = class end
	if #detail > 0 then parts[#parts + 1] = E:TextHex("secondary") .. table.concat(detail, " ") .. "|r" end
	local guild = Get(GetGuildInfo, PARTNER)
	if guild then parts[#parts + 1] = E:TextHex("accent") .. "<" .. guild .. ">|r" end
	if M.db.partnerTags then
		local tags = {}
		local guid = Get(UnitGUID, PARTNER)
		if guid and C_FriendList and Get(C_FriendList.IsFriend, guid) then tags[#tags + 1] = L["Friend"] end
		if guid and C_BattleNet and C_BattleNet.GetAccountInfoByGUID and Get(C_BattleNet.GetAccountInfoByGUID, guid) then
			tags[#tags + 1] = L["Battle.net friend"]
		end
		local mine = Get(GetGuildInfo, "player")
		if guild and mine and guild == mine then tags[#tags + 1] = L["Guild"] end
		if #tags > 0 then parts[#parts + 1] = E:TextHex("good") .. table.concat(tags, ", ") .. "|r" end
	end
	return table.concat(parts, "  ")
end

---------------------------------------------------------------------------
-- What each side offers is worth (slots 1-6 and the gold).
---------------------------------------------------------------------------
local function SideValue(linkFn, infoFn, moneyFn)
	local vendor, auction, missing = 0, 0, false
	local auctionModule = E.modules.Auction
	local useAuction = M.db.valueAuction and auctionModule and auctionModule.active and auctionModule.GetPrice
	for slot = 1, SLOTS do
		local link = Get(linkFn, slot)
		if link then
			local _, _, count = Get(infoFn, slot)
			count = (type(count) == "number" and count > 0) and count or 1
			local itemID = C_Item.GetItemInfoInstant(link)
			local sell = select(11, C_Item.GetItemInfo(link))
			if type(sell) == "number" then vendor = vendor + sell * count end
			if useAuction then
				local ok, price = pcall(auctionModule.GetPrice, auctionModule, itemID)
				if ok and type(price) == "number" then
					auction = auction + price * count
				else
					missing = true
				end
			end
		end
	end
	local money = Get(moneyFn) or 0
	return vendor, useAuction and auction or nil, missing, money
end

local function ValueText(linkFn, infoFn, moneyFn)
	local vendor, auction, missing, money = SideValue(linkFn, infoFn, moneyFn)
	local lines = {}
	if money > 0 then lines[#lines + 1] = L["Gold %s"]:format(Money(money)) end
	if vendor > 0 then lines[#lines + 1] = L["Vendor %s"]:format(Money(vendor)) end
	if auction and auction > 0 then lines[#lines + 1] = L["AH %s"]:format(Money(auction)) .. (missing and " " .. E:TextHex("secondary") .. "+?|r" or "") end
	if #lines == 0 then return E:TextHex("secondary") .. L["Nothing yet"] .. "|r" end
	return table.concat(lines, "   ")
end

---------------------------------------------------------------------------
-- The info strip
---------------------------------------------------------------------------
function M:CreateInfo()
	if self.info or not TradeFrame then return self.info end
	local info = CreateFrame("Frame", "EldoUI_TradeInfo", TradeFrame)
	E:SetPanelTemplate(info)
	info.partner = E:CreateText(info, E.tokens.size.label, "LEFT")
	info.mine = E:CreateText(info, E.tokens.size.label, "LEFT")
	info.theirs = E:CreateText(info, E.tokens.size.label, "RIGHT")
	self.info = info
	self:LayoutInfo()
	return info
end

function M:LayoutInfo()
	local info = self.info
	if not info then return end
	local db = self.db
	info:ClearAllPoints()
	if db.position == "above" then
		info:SetPoint("BOTTOMLEFT", TradeFrame, "TOPLEFT", 0, 2)
		info:SetPoint("BOTTOMRIGHT", TradeFrame, "TOPRIGHT", 0, 2)
	else
		info:SetPoint("TOPLEFT", TradeFrame, "BOTTOMLEFT", 0, -2)
		info:SetPoint("TOPRIGHT", TradeFrame, "BOTTOMRIGHT", 0, -2)
	end
	local rows = (db.partnerInfo and 1 or 0) + (db.valueLine and 1 or 0)
	info:SetHeight(math.max(db.infoHeight, math.max(rows, 1) * (db.fontSize + 6) + 8))
	for _, text in ipairs({ info.partner, info.mine, info.theirs }) do
		E:SetFont(text, db.fontSize)
		text:ClearAllPoints()
	end
	info.partner:SetPoint("TOPLEFT", 8, -6)
	info.partner:SetPoint("TOPRIGHT", -8, -6)
	local anchor = db.partnerInfo and info.partner or nil
	-- Each value takes one half of the line, split at the middle.
	if anchor then
		info.mine:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
		info.mine:SetPoint("TOPRIGHT", anchor, "BOTTOM", -4, -4)
		info.theirs:SetPoint("TOPLEFT", anchor, "BOTTOM", 4, -4)
		info.theirs:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
	else
		info.mine:SetPoint("TOPLEFT", 8, -6)
		info.mine:SetPoint("TOPRIGHT", info, "TOP", -4, -6)
		info.theirs:SetPoint("TOPLEFT", info, "TOP", 4, -6)
		info.theirs:SetPoint("TOPRIGHT", -8, -6)
	end
	E:SetPanelTemplate(info)
	if db.accentBorder then
		local r, g, b = unpack(E.media.accentColor)
		info:SetBackdropBorderColor(r, g, b, 1)
	end
	info.partner:SetShown(db.partnerInfo)
	info.mine:SetShown(db.valueLine)
	info.theirs:SetShown(db.valueLine)
end

function M:UpdateInfo()
	local on = Allowed("improve") and TradeFrame and TradeFrame:IsShown() and (self.db.partnerInfo or self.db.valueLine)
	if not on then
		if self.info then self.info:Hide() end
		return
	end
	local info = self:CreateInfo()
	if not info then return end
	if self.db.partnerInfo then info.partner:SetText(PartnerText() or "") end
	if self.db.valueLine then
		info.mine:SetText(ValueText(GetTradePlayerItemLink, GetTradePlayerItemInfo, GetPlayerTradeMoney))
		info.theirs:SetText(ValueText(GetTradeTargetItemLink, GetTradeTargetItemInfo, GetTargetTradeMoney))
	end
	info:Show()
end

---------------------------------------------------------------------------
-- Blizzard element "trade": skin, move and scale
---------------------------------------------------------------------------
local skinned = false

function M:SkinTrade()
	if skinned or not Allowed("skin") or not TradeFrame then return end
	skinned = true
	E:SkinPanel(TradeFrame)
	for _, inset in ipairs({ TradePlayerItemsInset, TradeRecipientItemsInset, TradePlayerEnchantInset,
		TradeRecipientEnchantInset, TradePlayerInputMoneyInset, TradeRecipientMoneyInset }) do
		E:SkinInset(inset)
	end
	if TradeRecipientMoneyBg then TradeRecipientMoneyBg:SetAlpha(0) end
	for _, side in ipairs({ "TradePlayerItem", "TradeRecipientItem" }) do
		for slot = 1, 7 do
			local item = _G[side .. slot]
			if item then
				-- The slot art goes; the name and the slot itself stay.
				E:EconomyStrip(item)
				local button = _G[side .. slot .. "ItemButton"]
				if button then E:EconomySlot(button, button.icon or _G[side .. slot .. "ItemButtonIconTexture"]) end
				local name = _G[side .. slot .. "Name"]
				if name then E:SetFont(name, E.tokens.size.label) end
			end
		end
	end
	for _, button in ipairs({ TradeFrameTradeButton, TradeFrameCancelButton }) do E:SkinButton(button) end
	for _, prefix in ipairs({ "TradePlayerInputMoneyFrame" }) do
		for _, coin in ipairs({ "Gold", "Silver", "Copper" }) do E:SkinEditBox(_G[prefix .. coin]) end
	end
	for _, text in ipairs({ TradeFramePlayerNameText, TradeFrameRecipientNameText }) do
		if text then E:SetNameTextFont(text, E.tokens.size.body) end
	end
end

M.window = E:EconomyWindow({
	id = "trade",
	key = "trade",
	frame = function() return TradeFrame end,
	mover = "EldoUI_TradeWindow",
	title = "Trade Window",
	point = { "TOPLEFT", "UIParent", "TOPLEFT", 20, -150 },
})

function M:ApplyBlizzard()
	if not self.active or not TradeFrame then return end
	self:SkinTrade()
	self.window:Apply()
	self:LayoutInfo()
	self:UpdateInfo()
end

function M:RestoreBlizzard()
	self.window:Restore()
	if self.info then self.info:Hide() end
end

E:RegisterBlizzardHandler("trade", {
	owner = "Trade",
	apply = function() M:ApplyBlizzard() end,
	undo = function() M:RestoreBlizzard() end,
	reload = { skin = true },
	install = { skin = true, improve = true },
	-- New in this version: nothing changed the trade window before.
	legacy = function() return false end,
})

---------------------------------------------------------------------------
-- Gold trade log: who you paid and who paid you. Read-only: the
-- amounts are what the trade window showed when both sides accepted, saved
-- once the game says "Trade complete". Canceled and failed trades are not
-- saved. Account-wide in the saved file under "trades" (the key it always
-- had), newest first; TradeStore() is the only place that writes the key
-- and E:GetTradeLog() is how other parts of EldoUI read it.
---------------------------------------------------------------------------
-- Server time, the clock Instances stamps runs with, so a trade lands in the
-- right run even when the PC clock is off.
local function Now()
	local now = GetServerTime and GetServerTime()
	if type(now) ~= "number" then now = time() end
	return now
end

local LOG_LINK = "addon:EldoUITradeLog"
local pending   -- the trade in the window: given, received, who, class, where, instance

E:RegisterStore("trades", { owner = "Trade", accessor = "TradeStore" })

local function TradeStore()
	if type(EldoUIDB) ~= "table" then return {} end
	if type(EldoUIDB.trades) ~= "table" then EldoUIDB.trades = {} end
	return EldoUIDB.trades
end

local function Where()
	local name, instanceType = GetInstanceInfo()
	if type(name) == "string" and not IsSecret(name) and instanceType and instanceType ~= "none" then
		return name, true
	end
	local zone = GetRealZoneText()
	if type(zone) ~= "string" or IsSecret(zone) then zone = "" end
	return zone, false
end

-- What the window shows right now (called on every money and accept update).
local function Snapshot()
	if not (M.db.tradeLog or M.db.tradeChat) then return end
	pending = pending or {}
	local given, received = Get(GetPlayerTradeMoney), Get(GetTargetTradeMoney)
	if type(given) == "number" then pending.given = given end
	if type(received) == "number" then pending.received = received end
	local name, realm = Get(UnitName, PARTNER)
	if type(name) == "string" and name ~= "" then
		pending.who = (type(realm) == "string" and realm ~= "") and (name .. "-" .. realm) or name
		local _, classFile = Get(UnitClass, PARTNER)
		pending.class = classFile
	end
	pending.where, pending.instance = Where()
	pending.closed = nil
end

local function ClassName(entry)
	local name = entry.who or "?"
	local short = Ambiguate and Ambiguate(name, "short") or name
	local color = E:ClassColorObject(entry.class)
	return color and color:WrapTextInColorCode(short) or short
end

local function Plain(copper)
	return E:EconomyMoney(copper or 0)
end

local function Record(entry)
	local log = TradeStore()
	table.insert(log, 1, entry)
	local size = math.max(10, math.floor(M.db.tradeLogSize or 300))
	while #log > size do table.remove(log) end
	if M.tradeWindow and M.tradeWindow:IsShown() then M:UpdateTradeLog() end
end

local function Announce(entry)
	local name = ClassName(entry)
	local text
	if entry.given > 0 and entry.received > 0 then
		text = L["Gave %s to %s and received %s."]:format(Plain(entry.given), name, Plain(entry.received))
	elseif entry.given > 0 then
		text = L["Gave %s to %s."]:format(Plain(entry.given), name)
	else
		text = L["Received %s from %s."]:format(Plain(entry.received), name)
	end
	local accent = E.media.accentColor
	local link = ("|cff%02x%02x%02x|H%s|h[%s]|h|r"):format(accent[1] * 255, accent[2] * 255, accent[3] * 255, LOG_LINK, L["Trade log"])
	M:Print(text .. " " .. link)
end

-- Trade window events: a new trade starts fresh, every money or accept
-- change updates the amounts, closing keeps them for the "complete" message.
function M:OnTradeLogEvent(name)
	if name == "TRADE_SHOW" then
		pending = nil
		Snapshot()
	elseif name == "TRADE_MONEY_CHANGED" or name == "TRADE_ACCEPT_UPDATE" then
		Snapshot()
	elseif name == "TRADE_CLOSED" and pending then
		pending.closed = pending.closed or GetTime()
	end
end

-- "Trade complete": save the trade if gold moved.
function M:TradeCompleted()
	local trade = pending
	pending = nil
	if not trade then return end
	if trade.closed and GetTime() - trade.closed > 10 then return end
	local given, received = trade.given or 0, trade.received or 0
	if given <= 0 and received <= 0 then return end
	local entry = {
		given = given, received = received, who = trade.who, class = trade.class,
		where = trade.where, instance = trade.instance or nil, time = Now(), char = E.charKey,
	}
	if self.db.tradeLog then Record(entry) end
	if self.db.tradeChat then Announce(entry) end
end

-- Messages the game sends about a trade, by the name of the message type.
local function MessageName(messageType)
	if not (GetGameMessageInfo and type(messageType) == "number") then return nil end
	local ok, name = pcall(GetGameMessageInfo, messageType)
	if ok and type(name) == "string" and not IsSecret(name) then return name end
end

local function IsMessage(messageType, message, key)
	if MessageName(messageType) == key then return true end
	local text = _G[key]
	return type(message) == "string" and not IsSecret(message) and text ~= nil and message == text
end

function M:OnTradeMessage(event, messageType, message)
	if not pending then return end
	if event == "UI_INFO_MESSAGE" then
		if IsMessage(messageType, message, "ERR_TRADE_COMPLETE") then
			self:TradeCompleted()
		elseif IsMessage(messageType, message, "ERR_TRADE_CANCELLED") then
			pending = nil
		end
	else
		-- A trade error (bags full, too far away, ...) ends this trade.
		local name = MessageName(messageType)
		if (name and name:find("^ERR_TRADE")) or IsMessage(messageType, message, "ERR_TRADE_BAG_FULL") then
			pending = nil
		end
	end
end

-- Trades between two times, for other modules (for example a dungeon run's
-- tooltip). Newest first; each entry: given, received, who, class, where,
-- instance, time, char.
function E:GetTradeLog(from, to)
	local list = {}
	for _, entry in ipairs(TradeStore()) do
		if type(entry) == "table" and (not from or (entry.time or 0) >= from) and (not to or (entry.time or 0) <= to) then
			list[#list + 1] = entry
		end
	end
	return list
end

---------------------------------------------------------------------------
-- The Trade log window (drag it to move it)
---------------------------------------------------------------------------
local ROWS = 14
local ROW_HEIGHT = 18

local function Ago(stamp)
	local diff = math.max(0, Now() - (stamp or 0))
	if diff < 60 then return L["now"] end
	if diff < 3600 then return L["%dm"]:format(diff / 60) end
	if diff < 86400 then return L["%dh"]:format(diff / 3600) end
	return L["%dd"]:format(diff / 86400)
end

local function CreateTradeWindow()
	-- The shared tool window shell; the whole window drags (below), so the
	-- shell's header drag is off.
	local window = E.UIKit.CreateToolWindow("EldoUI_TradeLogWindow", { title = L["Trade log"], width = 520,
		height = 64 + ROWS * ROW_HEIGHT + 40, strata = "HIGH", movable = false })
	window.line = window.headerLine

	-- Column headers: when, who, where, in, out.
	local function Columns(parent, size)
		local cols = {}
		cols.ago = E:CreateText(parent, size, "LEFT")
		cols.ago:SetPoint("LEFT", 6, 0)
		cols.ago:SetWidth(40)
		cols.who = E:CreateText(parent, size, "LEFT")
		cols.who:SetPoint("LEFT", 50, 0)
		cols.who:SetWidth(130)
		cols.where = E:CreateText(parent, size, "LEFT")
		cols.where:SetPoint("LEFT", 184, 0)
		cols.where:SetWidth(140)
		cols.received = E:CreateText(parent, size, "RIGHT")
		cols.received:SetPoint("RIGHT", -106, 0)
		cols.received:SetWidth(90)
		cols.given = E:CreateText(parent, size, "RIGHT")
		cols.given:SetPoint("RIGHT", -8, 0)
		cols.given:SetWidth(90)
		return cols
	end
	local header = CreateFrame("Frame", nil, window)
	header:SetPoint("TOPLEFT", 8, -36)
	header:SetPoint("TOPRIGHT", -8, -36)
	header:SetHeight(ROW_HEIGHT)
	header.cols = Columns(header, 11)
	for key, label in pairs({ ago = L["When"], who = L["Who"], where = L["Where"], received = L["In"], given = L["Out"] }) do
		header.cols[key]:SetText(label)
		header.cols[key]:SetTextColor(unpack(E.tokens.text.secondary))
	end

	window.rows = {}
	for index = 1, ROWS do
		local row = CreateFrame("Frame", nil, window)
		row:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -(index - 1) * ROW_HEIGHT)
		row:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -(index - 1) * ROW_HEIGHT)
		row:SetHeight(ROW_HEIGHT)
		row:EnableMouse(true)
		E:SkinRow(row)
		row.cols = Columns(row, 12)
		row.cols.ago:SetTextColor(unpack(E.tokens.text.secondary))
		row.cols.where:SetTextColor(unpack(E.tokens.text.secondary))
		row:SetScript("OnEnter", function(self)
			local entry = self.entry
			if not entry then return end
			local sr, sg, sb = unpack(E.tokens.text.secondary)
			E.UIKit.AnchorTooltip(self)
			GameTooltip:SetText(ClassName(entry))
			GameTooltip:AddLine(E:ShortDate(entry.time or 0), sr, sg, sb)
			if entry.where and entry.where ~= "" then GameTooltip:AddLine(entry.where, unpack(E.UIKit.TEXT)) end
			if entry.char then GameTooltip:AddLine(L["Your character: %s"]:format(entry.char), sr, sg, sb) end
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		E:BindOptionsLink(row, { page = "module:Trade", key = "tradeLog" })
		window.rows[index] = row
	end
	window.offset = 0
	window:EnableMouseWheel(true)
	window:SetScript("OnMouseWheel", function(self, delta)
		local count = #TradeStore()
		self.offset = math.max(0, math.min(math.max(0, count - ROWS), self.offset - delta * 3))
		M:UpdateTradeLog()
	end)

	window.totals = E.UIKit.Text(window, E.tokens.size.label, "LEFT")
	window.totals:SetPoint("BOTTOMLEFT", 10, 12)
	window.empty = E.UIKit.Text(window, E.tokens.size.label, "CENTER", "secondary")
	window.empty:SetPoint("CENTER", 0, 0)
	window.empty:SetText(L["No gold trades yet. Trades that move gold are listed here."])

	local function Button(label, width, onClick)
		return E.UIKit.Button(window, label, { width = width, onClick = onClick })
	end
	window.clear = Button(L["Clear"], 80, function() M:ConfirmClearTradeLog() end)
	window.clear:SetPoint("BOTTOMRIGHT", -8, 8)
	window.copy = Button(L["Copy"], 80, function() M:ExportTradeLog() end)
	window.copy:SetPoint("RIGHT", window.clear, "LEFT", -6, 0)

	-- Drag the window to move it; the spot is kept per profile, like the
	-- other EldoUI windows that open on demand.
	window:SetMovable(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint(1)
		if point then M.db.tradeLogPoint = { point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5) } end
	end)
	local saved = M.db.tradeLogPoint
	window:ClearAllPoints()
	if type(saved) == "table" and saved[1] then
		window:SetPoint(saved[1], UIParent, saved[2] or saved[1], tonumber(saved[3]) or 0, tonumber(saved[4]) or 0)
	else
		window:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	end
	return window
end

function M:UpdateTradeLog()
	local window = self.tradeWindow
	if not window then return end
	local log = TradeStore()
	window.offset = math.max(0, math.min(window.offset or 0, math.max(0, #log - ROWS)))
	local totalIn, totalOut = 0, 0
	for _, entry in ipairs(log) do
		totalIn = totalIn + (entry.received or 0)
		totalOut = totalOut + (entry.given or 0)
	end
	for index, row in ipairs(window.rows) do
		local entry = log[window.offset + index]
		row.entry = entry
		if entry then
			row.cols.ago:SetText(Ago(entry.time))
			row.cols.who:SetText(ClassName(entry))
			row.cols.where:SetText(entry.where or "")
			row.cols.received:SetText((entry.received or 0) > 0 and Plain(entry.received) or "")
			row.cols.given:SetText((entry.given or 0) > 0 and Plain(entry.given) or "")
			row:Show()
		else
			row:Hide()
		end
	end
	window.empty:SetShown(#log == 0)
	window.totals:SetText(L["%d trades   In %s   Out %s"]:format(#log, Plain(totalIn), Plain(totalOut)))
end

function M:ShowTradeLog()
	if not self.tradeWindow then self.tradeWindow = CreateTradeWindow() end
	self.tradeWindow.offset = 0
	self:UpdateTradeLog()
	self.tradeWindow:Show()
end

local function Coins(copper)
	copper = math.floor(copper or 0)
	local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	if gold > 0 then return ("%dg %ds %dc"):format(gold, silver, rest) end
	if silver > 0 then return ("%ds %dc"):format(silver, rest) end
	return ("%dc"):format(rest)
end

-- Plain text for the copy box; time, zone and "time ago" are optional.
function M:TradeLogText()
	local db = self.db
	local lines = {}
	for _, entry in ipairs(TradeStore()) do
		local parts = {}
		if db.exportTime then parts[#parts + 1] = date("%Y-%m-%d %H:%M", entry.time or 0) end
		if db.exportAgo then parts[#parts + 1] = L["%s ago"]:format(Ago(entry.time)) end
		parts[#parts + 1] = entry.who or "?"
		if db.exportZone and entry.where and entry.where ~= "" then parts[#parts + 1] = entry.where end
		parts[#parts + 1] = L["in %s"]:format(Coins(entry.received))
		parts[#parts + 1] = L["out %s"]:format(Coins(entry.given))
		lines[#lines + 1] = table.concat(parts, "  |  ")
	end
	return table.concat(lines, "\n")
end

function M:ExportTradeLog()
	E:ShowCopyBox(L["Trade log"], L["Press Ctrl+C to copy. Newest first."], self:TradeLogText():gsub("|", "||"))
end

-- Asks first: the log can't be brought back.
function M:ConfirmClearTradeLog()
	E:ShowConfirm({ key = "ELDOUI_TRADE_LOG_CLEAR", title = L["Trade log"], text = L["Clear the whole trade log? This can't be undone."],
		accept = E:GameText(YES, L["Yes"]), cancel = E:GameText(NO, L["No"]), danger = true, onAccept = function() M:ClearTradeLog() end })
end

function M:ClearTradeLog()
	wipe(TradeStore())
	self:UpdateTradeLog()
end

E:AddCommand("trades", "open the gold trade log", function() M:ShowTradeLog() end, "Tools")

-- The "trade log" link in the chat line. A hook can't be taken off again,
-- so it is added once, the first time the module turns on, and the log
-- opens from the link while the module is on.
local function OnItemRef(link)
	if M.active and type(link) == "string" and link:sub(1, #LOG_LINK) == LOG_LINK then M:ShowTradeLog() end
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
local EVENTS = { "TRADE_SHOW", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED", "TRADE_MONEY_CHANGED",
	"TRADE_ACCEPT_UPDATE", "TRADE_CLOSED", "GET_ITEM_INFO_RECEIVED", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE" }

function M:OnEnable()
	if not self.linkHooked and type(SetItemRef) == "function" then
		hooksecurefunc("SetItemRef", OnItemRef)
		self.linkHooked = true
	end
	for _, event in ipairs(EVENTS) do
		self:RegisterEvent(event, function(_, name, ...)
			if name == "UI_INFO_MESSAGE" or name == "UI_ERROR_MESSAGE" then
				M:OnTradeMessage(name, ...)
				return
			end
			M:OnTradeLogEvent(name)
			if name == "TRADE_SHOW" then
				M:ApplyBlizzard()
			elseif name == "TRADE_CLOSED" then
				if M.info then M.info:Hide() end
				return
			elseif name == "GET_ITEM_INFO_RECEIVED" and not (TradeFrame and TradeFrame:IsShown()) then
				return
			end
			-- Item info can arrive a moment after the slot changes.
			C_Timer.After(0, function() M:UpdateInfo() end)
		end)
	end
	E:OnBlizzardAddOn("Blizzard_UIPanels_Game", function() M:ApplyBlizzard() end)
end

function M:OnDisable()
	for _, event in ipairs(EVENTS) do self:UnregisterEvent(event) end
	self:RestoreBlizzard()
end

function M:OnProfileChanged()
	if not self.active then return end
	self:ApplyBlizzard()
end

---------------------------------------------------------------------------
-- Options and styles
---------------------------------------------------------------------------
M.options = {
	{ type = "description", label = "Changes Blizzard's trade window only when it is on under Blizzard UI. EldoUI never presses Trade or Accept for you." },
	{ type = "execute", label = "Open Blizzard UI switches", desc = "Choose here whether EldoUI skins, moves or extends the trade window (element \"Trade window\").",
		func = function() E:ToggleConfig("blizzard") end },
	{ type = "header", label = "Info strip" },
	{ type = "description", label = "Shown under (or above) the window while the Blizzard UI switch \"Improve (extra info)\" is on for the trade window." },
	{ type = "toggle", key = "partnerInfo", label = "Who you trade with", desc = "Name, level, race, class and guild of your trade partner." },
	{ type = "toggle", key = "classColor", dependsOn = "partnerInfo", label = "Class-colored name", desc = "Shows the partner's name in their class color." },
	{ type = "toggle", key = "partnerTags", dependsOn = "partnerInfo", label = "Friend and guild tags", desc = "Notes when the partner is on your friends list, your Battle.net friends or in your guild." },
	{ type = "toggle", key = "valueLine", label = "Value of each side", desc = "What the items each side offers sell for at a vendor, plus the gold offered." },
	{ type = "toggle", key = "valueAuction", dependsOn = "valueLine", label = "Auction value", desc = "Adds the items' worth at your saved auction prices (needs the Auction House module). \"+?\" means some items have no saved price." },
	{ type = "select", key = "valueMoney", dependsOn = "valueLine", label = "Money style", desc = "How the amounts are written. \"Use general setting\" follows Fonts and text > Money.",
		values = function() return E:MoneyStyleValues(true) end },
	{ type = "select", key = "position", label = "Strip position", desc = "Where the info strip sits.", values = { below = "Below the window", above = "Above the window" } },
	{ type = "range", key = "fontSize", label = "Text size", min = 9, max = 18, step = 1, desc = "Text size in the info strip." },
	{ type = "range", unit = "px", key = "infoHeight", label = "Minimum strip height", min = 20, max = 80, step = 1, desc = "The strip grows with the font size; this is its smallest height." },
	{ less = true, type = "toggle", key = "accentBorder", label = "Accent border", desc = "Draws the strip's border in the accent color instead of the normal panel border." },
	{ type = "header", label = "Gold trade log" },
	{ type = "toggle", key = "tradeLog", label = "Keep a trade log", desc = "Saves every finished trade that moved gold: who, where, and how much each way. Shared by all your characters." },
	{ type = "toggle", key = "tradeChat", label = "Gold line in chat", desc = "After a trade that moved gold, one line in chat (only you see it), such as \"Gave 5g to Name\", with a link to the log." },
	{ type = "range", key = "tradeLogSize", label = "Log size", min = 50, max = 1000, step = 50, desc = "How many trades the log keeps; the oldest go first.", dependsOn = "tradeLog" },
	{ type = "execute", label = "Open the trade log", desc = "The Trade log window, newest first (also /eui trades and the link in chat).", testSafe = true,
		func = function() M:ShowTradeLog() end },
	{ type = "execute", label = "Clear the trade log", desc = "Deletes every saved trade after you confirm.",
		func = function() M:ConfirmClearTradeLog() end },
	{ type = "toggle", key = "exportTime", label = "Copy: date and time", desc = "The Copy button in the log adds the date and time to each line." },
	{ type = "toggle", key = "exportZone", label = "Copy: zone", desc = "The Copy button adds the zone or instance to each line." },
	{ type = "toggle", key = "exportAgo", label = "Copy: time ago", desc = "The Copy button adds how long ago each trade was (\"3h ago\")." },
	{ type = "header", label = "Window" },
	{ type = "execute", label = "Open Windows", testSafe = true,
		desc = "The trade window. Its size (mouse wheel on the title bar), dragging and the resets are on the Move windows page, with every other Blizzard window; where it opens is its mover in move mode (/eui move).",
		func = function() E:ToggleConfig("windows") end },
}

E:RegisterStyles("Trade", {
	{ key = "Standard", title = "Standard", desc = "Partner and values below the window, coin icons.",
		settings = { partnerInfo = true, classColor = true, partnerTags = true, valueLine = true, valueAuction = true, position = "below", fontSize = 12, infoHeight = 40, accentBorder = false } },
	{ key = "Compact", title = "Compact", desc = "Smaller text in a slimmer info strip, without the friend and guild tags.",
		settings = { partnerInfo = true, classColor = true, partnerTags = false, valueLine = true, valueAuction = true, position = "below", fontSize = 10, infoHeight = 30, accentBorder = false } },
	{ key = "Header", title = "Header", desc = "The strip sits above the window like a title bar, with an accent border.",
		settings = { partnerInfo = true, classColor = true, partnerTags = true, valueLine = true, valueAuction = true, position = "above", fontSize = 12, infoHeight = 40, accentBorder = true } },
	{ key = "Large", title = "Large", desc = "Bigger text in a taller info strip, easy to read.",
		settings = { partnerInfo = true, classColor = true, partnerTags = true, valueLine = true, valueAuction = true, position = "below", fontSize = 15, infoHeight = 50, accentBorder = false } },
	{ key = "Partner", title = "Partner only", desc = "Only who you trade with; no values.",
		settings = { partnerInfo = true, classColor = true, partnerTags = true, valueLine = false, position = "below", fontSize = 12, infoHeight = 24, accentBorder = false } },
})
