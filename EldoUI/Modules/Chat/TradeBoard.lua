-- A session list of offers read from chat lines the game shows.
local _, E = ...
local L, M, Kit = E.L, E:GetModule("Chat"), E.UIKit
local Plain, Call = E.Plain, E.PlainCall
local MAX_OFFERS, MAX_LINES, MAX_BODY, MAX_ITEMS = 300, 600, 1024, 8

-- The native channel ID is independent of the chat slot and game language.
local CHANNELS = { [1] = "tradeGeneral", [2] = "tradeChannel", [26] = "tradeLooking" }
local MARKERS = {
	wts = "sell", selling = "sell", saelger = "sell", verkaufe = "sell", vends = "sell", vendo = "sell",
	wtb = "buy", buying = "buy", kober = "buy", koeber = "buy", kaufe = "buy", achete = "buy", compro = "buy",
	lf = "find", lfw = "find", soger = "find", soeger = "find", suche = "find", cherche = "find", busco = "find",
}
local SERVICES = {
	{ function() return L["Enchanting"] end, 7411, "enchant", "enchanting", "fortryllelse", "fortryller" },
	{ function() return L["Lockpicking"] end, 1804, "lockpick", "lockpicking", "pick lock", "låseåbning" },
	{ function() return L["Tailoring"] end, 3908, "tailoring", "tailor", "skrædder" },
	{ function() return L["Leatherworking"] end, 2108, "leatherworking", "leatherworker", "læderarbejde" },
	{ function() return L["Blacksmithing"] end, 2018, "blacksmithing", "blacksmith", "smedearbejde" },
	{ function() return L["Alchemy"] end, 2259, "alchemy", "alchemist", "alkymi" },
	{ function() return L["Engineering"] end, 4036, "engineering", "engineer", "ingeniørkunst" },
	{ function() return L["Cooking"] end, 2550, "cooking", "cook", "madlavning" },
}
local COINS = { g = 1, gold = 1, guld = 1, s = 2, silver = 2, ["sølv"] = 2, c = 3, copper = 3, kobber = 3 }
local COIN_GLOBALS = { "GOLD_AMOUNT", "SILVER_AMOUNT", "COPPER_AMOUNT" }
local WORD = "[%w\128-\255]"

local function HasWord(text, word)
	local first, last = text:find(word, 1, true)
	while first do
		if (first == 1 or not text:sub(first - 1, first - 1):match(WORD))
			and not text:sub(last + 1, last + 1):match(WORD) then return true end
		first, last = text:find(word, first + 1, true)
	end
	return false
end

local function PlainTable(value)
	return not E.Secret(value) and type(value) == "table" and (not canaccesstable or canaccesstable(value))
end

local function PositiveInteger(value)
	return type(value) == "number" and value > 0 and value % 1 == 0
end

local function Enabled()
	return M.active and M.db and M.db.tradeBoard == true and M:Allowed("improve")
end

local function ChatOpen()
	return Call(C_ChatInfo and C_ChatInfo.InChatMessagingLockdown) == false
end

local function IsIgnored(guid)
	return Call(C_FriendList and C_FriendList.IsIgnoredByGuid, guid) ~= false
end

-- One contiguous explicit amount, in descending coin order. A second
-- amount elsewhere in the line cannot be attributed to this offer.
local function Price(text, coins)
	local folded = text:lower()
	local first, finish, lastCoin, at = nil, nil, 0, 1
	while true do
		local from, to, digits, unit = folded:find("(%d+[.,]?%d*)%s*([%a\128-\255]+)", at)
		if not from then break end
		at = to + 1
		local coin = coins[unit]
		local before = folded:sub(from - 1, from - 1)
		if coin and (from == 1 or from == (finish or 0) + 1 or not before:match(WORD)) then
			if #digits > 9 or coin <= lastCoin or (finish and not folded:sub(finish + 1, from - 1):match("^%s*,?%s*$")) then return end
			first, finish, lastCoin = first or from, to, coin
		end
	end
	if first then return text:sub(first, finish), first, finish end
end

local function OfferParts(body, state)
	local items, unique = {}, {}
	local text = body:gsub("(|H(%a+):([^|%c]+)|h%[([^|%c]+)%]|h)", function(link, kind, payload, label)
		if kind == "spell" or kind == "enchant" or kind == "trade" then return label end
		if kind ~= "item" or not payload:match("^[%d:%-]+$") then return link end
		local id = tonumber(payload:match("^(%d+):") or payload:match("^(%d+)$"))
		if not PositiveInteger(id) or #payload > 192 or #label > 180 then return link end
		if not unique[id] then
			if #items == MAX_ITEMS then return link end
			unique[id] = true
			items[#items + 1] = { id = id, link = link, label = label }
		end
		return label
	end)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	if text:find("[|%c]") then return end
	text = strtrim(text)
	local mark, subject = text:match("^%[?([%a\128-\255]+)%]?[%s:]+(.+)$")
	local kind = mark and MARKERS[E:FoldText(mark)]
	if not kind then return end

	local folded = E:FoldText(subject)
	local service
	for index, words in ipairs(state.services) do
		for _, word in ipairs(words) do
			if HasWord(folded, word) then service = index break end
		end
		if service then break end
	end
	if kind == "find" and not service and #items == 0 then return end
	kind = service and "service" or (kind == "find" and "buy" or kind)

	-- Item names can contain numbers and coin words that are not prices.
	local quote = #items > 0 and body:gsub("|H.-|h.-|h", " ") or subject
	local price, first, last = Price(quote, state.coins)
	if #items == 0 then
		local title = first and (subject:sub(1, first - 1) .. subject:sub(last + 1)) or subject
		title = strtrim((title:gsub("[%s:,%-%+]+$", "")))
		if #title < 3 or not title:find("[%a\128-\255]") then return end
		items[1] = { label = title }
	end
	return text, items, kind, service, #items == 1 and price or nil
end

local function ReadChannel(zone, slot)
	local info = Call(C_ChatInfo and C_ChatInfo.GetChannelInfoFromIdentifier, tostring(slot))
	local types = Enum and Enum.PermanentChatChannelType
	if not (types and PlainTable(info)) then return end
	if Plain(info.channelType) ~= types.Zone or Plain(info.zoneChannelID) ~= zone or Plain(info.localID) ~= slot then return end
	local name = Plain(info.shortcut)
	if type(name) ~= "string" or name == "" then name = Plain(info.name) end
	if type(name) ~= "string" or name == "" or #name > 96 or name:find("[|%c]") then return end
	return name
end

local function DisplayedSender(text, body, sender, slot, lineID)
	if #body == 0 or #body > MAX_BODY or #text <= #body or #text > MAX_BODY + 512 then return end
	if text:sub(-#body) ~= body then return end
	local prefix = text:sub(1, #text - #body)
	local channel = ("|Hchannel:channel:%d|h"):format(slot)
	local player = ("|Hplayer:%s:%d:CHANNEL:%d|h"):format(sender, lineID, slot)
	local _, channelEnd = prefix:find(channel, 1, true)
	if not channelEnd then return end
	local _, playerEnd = prefix:find(player, channelEnd + 1, true)
	if not playerEnd then return end
	local labelEnd = prefix:find("|h", playerEnd + 1, true)
	if not labelEnd then return end
	local label = prefix:sub(playerEnd + 1, labelEnd - 1):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	label = label:match("^%[(.+)%]$")
	if label and #label <= 128 and not label:find("[|%c]") then return label end
end

local function Remove(state, offer)
	local newer, older = offer.newer, offer.older
	if newer then newer.older = older else state.newest = older end
	if older then older.newer = newer else state.oldest = newer end
	state.offers[offer.key] = nil
	state.count = state.count - 1
	offer.newer, offer.older = nil, nil
end

local function Add(state, offer)
	local previous = state.offers[offer.key]
	if previous then Remove(state, previous) end
	if state.newest then state.newest.newer = offer else state.oldest = offer end
	offer.older, state.newest = state.newest, offer
	state.offers[offer.key] = offer
	state.count = state.count + 1
	if state.count > MAX_OFFERS then Remove(state, state.oldest) end
end

local function Cutoff(now)
	local minutes = tonumber(M.db.tradeMinutes) or 30
	return now - math.max(5, math.min(minutes, 60)) * 60
end

local function Expire(state, now)
	local cutoff = Cutoff(now)
	while state.oldest and state.oldest.at <= cutoff do Remove(state, state.oldest) end
end

local function RememberLine(state, id)
	local pos = state.lineSlot % MAX_LINES + 1
	local old = state.lineRing[pos]
	if old then state.lines[old] = nil end
	state.lineSlot, state.lineRing[pos], state.lines[id] = pos, id, true
end

local function WatchHit(text, state)
	for _, word in ipairs(state.watches) do
		if text:find(word, 1, true) then return true end
	end
	return false
end

local function Policy(db)
	local fields = { db.contentFilters, db.filterWholeWords, db.filterScope, db.filterDisguised,
		db.filterCyrillic, db.spamFilter, db.spamWindow, db.tradeGeneral, db.tradeChannel, db.tradeLooking }
	local parts = {}
	for index = 1, 10 do parts[index] = tostring(fields[index]) end
	local function Push(text)
		if type(text) == "string" then parts[#parts + 1] = #text .. ":" .. text end
	end
	for _, phrase in ipairs(db.filterPhrases or {}) do Push(phrase) end
	parts[#parts + 1] = "mutes"
	for _, mute in ipairs(db.channelMutes or {}) do
		if type(mute) == "table" then Push(mute.channel) Push(mute.name) end
	end
	return table.concat(parts, "\001")
end

local function NewState()
	local services, coins = {}, {}
	for index, def in ipairs(SERVICES) do
		local words = {}
		for word = 3, #def do words[#words + 1] = E:FoldText(def[word]) end
		local native = Call(C_Spell and C_Spell.GetSpellName, def[2])
		if type(native) == "string" and native ~= "" then words[#words + 1] = E:FoldText(native) end
		services[index] = words
	end
	for word, coin in pairs(COINS) do coins[word] = coin end
	for index, key in ipairs(COIN_GLOBALS) do
		local label = Plain(rawget(_G, key))
		local word = type(label) == "string" and label:lower():match("^%%d[ %c]*([%a\128-\255]+)$")
		if word then coins[word] = index end
	end
	return { db = M.db, profile = E.db, character = E.charKey, policy = Policy(M.db), offers = {}, count = 0, epoch = 0, lines = {}, lineRing = {}, lineSlot = 0,
		services = services, coins = coins, watches = {} }
end

local state, window, update, listening
local owner = {}

local function WatchedWords()
	local words = {}
	local text = Plain(M.db.tradeWatchWords)
	if type(text) ~= "string" then return words end
	for word in text:sub(1, 320):gmatch("[^,]+") do
		word = strtrim(E:FoldText(word))
		if word ~= "" and not word:find("[|%c]") then words[#words + 1] = word end
	end
	return words
end

local function ResetOffers()
	if not state then return end
	state.offers, state.count, state.newest, state.oldest = {}, 0, nil, nil
	state.epoch = state.epoch + 1
end

local function Current(owned)
	return owned and owned.db == M.db and owned.profile == E.db and owned.character == E.charKey
end

local function ResetBoard()
	state = nil
	if window then
		window:Hide()
		window.query, window.kind, window.service = nil, nil, nil
		window.search:SetText("")
		window.kindFilter:Refresh()
		window.serviceFilter:Refresh()
	end
end

function M:SyncTradeBoard()
	local on = Enabled() and true or false
	if (listening or false) ~= on then
		listening = on
		if on then
			E:RegisterEvent("IGNORELIST_UPDATE", function()
				ResetOffers()
				if update then update() end
			end, owner)
		else
			E:UnregisterEvent("IGNORELIST_UPDATE", owner)
		end
		local infoBar = E:GetModule("InfoBar")
		if infoBar and infoBar.active and infoBar.RefreshDataText then infoBar:RefreshDataText("TradeBoard") end
	end
	if not on then
		if state then ResetBoard() end
		return
	end
	if state and not Current(state) then ResetBoard() end
	if not state then state = NewState() end
	local signature = Policy(self.db)
	if signature ~= state.policy then ResetOffers() state.policy = signature end
	local watchText = Plain(self.db.tradeWatchWords)
	if state.watchText ~= watchText then
		state.watchText, state.watches = watchText, WatchedWords()
	end
	if update then update() end
end

-- The native formatter and metadata arrive only on the original chat line.
-- Its metadata preserves raw event arguments even when a filter replaced
-- what the player sees. Qualify the rendered line before reading an offer.
function M:ReadTradeLine(text, args, formatter)
	local current = state
	if not (Enabled() and Current(current) and type(formatter) == "function"
		and not E.Secret(formatter) and PlainTable(args)) then return end
	if E.Secret(text) or type(text) ~= "string" then return end
	local zone, slot, lineID = Plain(args[7]), Plain(args[8]), Plain(args[11])
	if not PositiveInteger(zone) or not PositiveInteger(slot) or not PositiveInteger(lineID) or current.lines[lineID] then return end
	local channel = CHANNELS[zone]
	if not channel or self.db[channel] ~= true then return end
	local body, sender, flags, guid = Plain(args[1]), Plain(args[2]), Plain(args[6]), Plain(args[12])
	if type(body) ~= "string" or type(sender) ~= "string" or #sender == 0 or #sender > 128 or sender:find("[|:%c]") then return end
	if type(flags) ~= "string" or flags == "GM" or flags == "DEV" or E.Secret(args[13]) then return end
	if args[13] ~= nil and args[13] ~= 0 then return end
	if type(guid) ~= "string" or not guid:match("^Player%-%d+%-%x+$") or guid == Call(UnitGUID, "player") then return end
	local shown = DisplayedSender(text, body, sender, slot, lineID)
	if not shown then return end
	local epoch = current.epoch
	if not ChatOpen() then return end
	local chat = C_ChatInfo
	if Call(chat.IsChatLineCensored, lineID) ~= false or Call(chat.GetChatLineSenderGUID, lineID) ~= guid or IsIgnored(guid) then return end
	local visible, items, kind, service, price = OfferParts(body, current)
	if not items then return end
	local name = ReadChannel(zone, slot)
	if not name or state ~= current or not Current(current) or current.epoch ~= epoch or not Enabled() or self.db[channel] ~= true then return end
	RememberLine(current, lineID)
	local now, search = GetTime(), E:FoldText(visible)
	Expire(current, now)
	for index = #items, 1, -1 do
		local item = items[index]
		local subject = item.id or E:FoldText(item.label)
		local key = guid .. "\001" .. tostring(subject)
		Add(current, { key = key, at = now, sender = sender, shown = shown, guid = guid, zone = zone, channel = name,
			item = item, kind = kind, service = service, price = price, text = visible, search = search })
	end
	if self.db.tradeWatchSound and WatchHit(search, current) and self.PlayChatAlertSound then
		self:PlayChatAlertSound(self.MediaSound(self.db.keywordSound))
	end
	if update then update() end
end

local function ShownSender(offer)
	local streamer = E:GetModule("Streamer")
	if streamer and streamer.db and streamer.db.chat and streamer.SenderAlias then
		local alias = streamer:SenderAlias(offer.sender, offer.guid)
		if alias then return alias end
	end
	return M:FormatSenderName(offer.shown)
end

local function Draft(offer)
	local current = state
	if not (Enabled() and Current(current) and window and window:IsShown() and offer and current.offers[offer.key] == offer) then return end
	if M.db[CHANNELS[offer.zone]] ~= true or offer.at <= Cutoff(GetTime()) or IsIgnored(offer.guid) or not ChatOpen() then return end
	if state ~= current or current.offers[offer.key] ~= offer then return end
	Call(ChatFrameUtil and ChatFrameUtil.SendTellWithMessage, offer.sender, offer.item.link or "")
end

local function KindLabel(kind)
	if kind == "sell" then return L["Selling"] end
	if kind == "buy" then return L["Buying"] end
	return L["Service"]
end

local function DrawRow(row, offer)
	if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
	local icon = offer.item.id and Call(C_Item and C_Item.GetItemIconByID, offer.item.id)
	local watched = WatchHit(offer.search, state)
	local age = math.max(0, math.floor((GetTime() - offer.at) / 60))
	local details = KindLabel(offer.kind) .. " · " .. ShownSender(offer) .. " · " .. offer.channel .. " · " .. L["%d min ago"]:format(age)
	if watched then details = L["Watched offer"] .. " · " .. details end
	row:SetRow({ name = offer.item.label, icon = icon, sub = details, statusText = offer.price })
	row:SetSelected(watched, offer.key)
end

local function CreateRow(row)
	row:SetScript("OnClick", function(self) Draft(self.item) end)
	row:HookScript("OnEnter", function(self)
		local offer = self.item
		if not offer then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		Kit.TipTitle(GameTooltip, offer.item.label)
		Kit.TipText(GameTooltip, offer.text)
		Kit.TipText(GameTooltip, L["Click to open a whisper draft."])
		GameTooltip:Show()
	end)
	local function HideTip(self)
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end
	row:HookScript("OnLeave", HideTip)
	row:HookScript("OnHide", HideTip)
end

update = function()
	if not (window and window:IsShown() and Current(state) and Enabled()) then return end
	Expire(state, GetTime())
	local rows, query = {}, window.query or ""
	local offer = state.newest
	while offer do
		if (not window.kind or window.kind == offer.kind) and (not window.service or window.service == offer.service)
			and (query == "" or offer.search:find(query, 1, true) or E:FoldText(ShownSender(offer)):find(query, 1, true)) then
			rows[#rows + 1] = offer
		end
		offer = offer.older
	end
	window.list:SetData(rows)
end

local function Layout()
	if not window then return end
	local height = math.ceil(E.tokens.height.button * E:TextScale())
	window.search:SetHeight(height)
	window.kindFilter:SetHeight(height)
	window.serviceFilter:SetHeight(height)
	window.title:SetText(L["Trade board"])
	window.search.hint:SetText(L["Search offers"])
	window.kindFilter:Refresh()
	window.serviceFilter:Refresh()
	window.list:SetEmpty(L["No offers found"])
	update()
end

local function CreateWindow()
	local win = Kit.CreateToolWindow("EldoUI_TradeBoard", { title = L["Trade board"], width = 650, height = 430, strata = "DIALOG" })
	window = win
	-- Ctrl-click anywhere on the board opens its Chat settings.
	E:BindOptionsLink(win, { page = "module:Chat", key = "tradeBoard" })
	win.search = Kit.Input(win, { maxLetters = 80, onChange = function(text)
		win.query = strtrim(E:FoldText(text))
		update()
	end })
	win.search:SetPoint("TOPLEFT", win.header, "BOTTOMLEFT", 12, -10)
	win.serviceFilter = Kit.Dropdown(win, { width = 224, values = function()
		local values = { { false, L["All professions"] } }
		for index, def in ipairs(SERVICES) do values[#values + 1] = { index, def[1]() } end
		return values
	end, get = function() return win.service or false end, set = function(value) win.service = value update() end })
	win.serviceFilter:SetPoint("TOPRIGHT", win.header, "BOTTOMRIGHT", -12, -10)
	win.kindFilter = Kit.Dropdown(win, { width = 150, values = function()
		return { { false, L["All offers"] }, { "sell", KindLabel("sell") },
			{ "buy", KindLabel("buy") }, { "service", KindLabel("service") } }
	end, get = function() return win.kind or false end, set = function(value) win.kind = value update() end })
	win.kindFilter:SetPoint("RIGHT", win.serviceFilter, "LEFT", -8, 0)
	win.search:SetPoint("TOPRIGHT", win.kindFilter, "TOPLEFT", -8, 0)
	win.list = Kit.CreateList(win, Kit.ListRow2Template({ create = CreateRow, update = DrawRow }))
	win.list:SetPoint("TOPLEFT", win.search, "BOTTOMLEFT", 0, -8)
	win.list:SetPoint("BOTTOMRIGHT", -12, 12)
	win:HookScript("OnShow", function(self)
		update()
		self.expiryTicker = C_Timer.NewTicker(15, update)
	end)
	win:HookScript("OnHide", function(self)
		if self.expiryTicker then self.expiryTicker:Cancel() self.expiryTicker = nil end
		self.search:ClearFocus()
		self.list:SetData({})
	end)
	Layout()
	return win
end

function M:ToggleTradeBoard()
	if not Enabled() then E:Print(L["Turn on the Trade board in Chat settings."]) return end
	self:SyncTradeBoard()
	local win = window or CreateWindow()
	win:SetShown(not win:IsShown())
end

E:OnThemeChanged("chatTradeBoard", Layout)
hooksecurefunc(E, "RefreshNames", update)
if Menu and Menu.ModifyMenu then
	Menu.ModifyMenu("MENU_CHAT_SHORTCUTS", function(_, root)
		if Enabled() then root:CreateButton(L["Trade board"], function() M:ToggleTradeBoard() end) end
	end)
end

E:AddCommand("trade", "open the Trade board", function() M:ToggleTradeBoard() end, "Tools")
E:RegisterDataText("TradeBoard", {
	title = "Trade board", collapseEmpty = true,
	text = function() return Enabled() and L["Trade board"] or "" end,
	onClick = function() M:ToggleTradeBoard() end,
	hint = { "Click", "open the Trade board" },
})
