-- EldoUI Farming: a farming session bar. While a session runs it counts the
-- gold you loot, the items you loot and what they are worth (vendor price or
-- your saved auction prices), and the XP you gain, each also per hour.
-- Sessions are kept per zone with the best gold per hour.
--
-- Only your own money, loot messages and XP are read. Nothing is sold,
-- looted or clicked for you.
--
-- Corpses looted: the corpses whose loot window you opened in the open
-- world, out of combat, each one once per session. They come from the loot
-- window's own sources (GetLootSourceInfo); a hidden source is skipped. It
-- counts what you looted, not what you killed.
--
-- A saved session also keeps which of your characters farmed it (c =
-- charKey), so My Adventure reads it as the journal source
-- "farming": one "farm" row per session (older sessions count for all your
-- characters and stay out of the journal).
local _, E = ...
local L = E.L

local issecret = issecretvalue or function() return false end
local floor, max = math.floor, math.max

local M = E:NewModule("Farming", {
	title = "Farming",
	category = "Quality of Life",
	desc = "A farming session bar: time, looted gold, item value and XP, each per hour, with sessions saved per zone.",
	conflicts = { "KiwiFarm" },
	frames = { "EldoUI_FarmBar" },
	movers = { "EldoUI_FarmBar" },
	blizzard = {},
	savedKeys = { "profile.modules.Farming", "global.FarmSessions", "private.Farming" },
	optionsPage = "module:Farming",
	presets = { "DataTextOnly", "Gold", "Levelling", "Manual", "Standard" },
	uiAmount = "moderate",
	reload = false,
	defaults = {
		autoStart = true,     -- start a session on the first loot
		afkPause = true,      -- the timer stops while you are away
		valueSource = "max",  -- vendor | auction | max
		showGold = true,
		showItems = true,
		showXP = true,
		alwaysShow = false,   -- the bar also shows when no session runs
		goal = 0,             -- gold goal in gold (0 = none)
		goalSound = "none",
		keepSessions = 20,
		barWidth = 360,
	},
})
E.Farming = M

local Clean = E.Plain

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d, e, f, g, h, i, j, k = pcall(fn, ...)
	if ok then return a, b, c, d, e, f, g, h, i, j, k end
end

local function Money(copper)
	return E:FormatMoney(floor((copper or 0) + 0.5))
end
M.Money = Money

local function Clock(seconds)
	seconds = max(0, floor(seconds or 0))
	local h, m, s = floor(seconds / 3600), floor(seconds / 60) % 60, seconds % 60
	if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
	return ("%d:%02d"):format(m, s)
end
M.Clock = Clock

local function Short(n)
	n = n or 0
	if n >= 1e6 then return ("%.1fm"):format(n / 1e6) end
	if n >= 1e4 then return ("%.0fk"):format(n / 1e3) end
	if n >= 1e3 then return ("%.1fk"):format(n / 1e3) end
	return tostring(floor(n + 0.5))
end

---------------------------------------------------------------------------
-- The session
---------------------------------------------------------------------------
-- session = { started, elapsed (seconds before the current run), running
-- since, paused, gold, value, items, xp, zone, looted = { itemID = count } }
M.session = nil

local function Now() return GetTime() end

function M:Elapsed()
	local s = self.session
	if not s then return 0 end
	return s.elapsed + (s.runningSince and (Now() - s.runningSince) or 0)
end

local function ZoneName()
	local mapID = C_Map and C_Map.GetBestMapForUnit and Clean(Try(C_Map.GetBestMapForUnit, "player"))
	local info = mapID and C_Map.GetMapInfo and Try(C_Map.GetMapInfo, mapID)
	local name = info and Clean(info.name)
	if type(name) == "string" and name ~= "" then return name end
	local zone = GetRealZoneText and Clean(GetRealZoneText())
	return type(zone) == "string" and zone ~= "" and zone or "Unknown"
end

function M:Start()
	if self.session and self.session.runningSince then return end
	if not self.session then
		self.session = { elapsed = 0, gold = 0, value = 0, items = 0, xp = 0, kills = 0, corpses = {}, zone = ZoneName(), looted = {}, startedAt = time() }
		self.goalReached = false
	end
	self.session.runningSince = Now()
	self.session.paused = nil
	self:Refresh()
end

function M:Pause(reason)
	local s = self.session
	if not (s and s.runningSince) then return end
	s.elapsed = s.elapsed + (Now() - s.runningSince)
	s.runningSince = nil
	s.paused = reason or "paused"
	self:Refresh()
end

function M:Toggle()
	if self.session and self.session.runningSince then self:Pause() else self:Start() end
end

function M:Running()
	return self.session and self.session.runningSince ~= nil
end

-- Stop: save the session under its zone and clear the bar.
function M:Stop()
	local s = self.session
	if not s then return nil end
	self:Pause()
	local record
	if self:Elapsed() >= 60 and (s.gold > 0 or s.value > 0 or s.xp > 0) then
		record = { t = s.startedAt, d = floor(s.elapsed), g = floor(s.gold), v = floor(s.value), x = s.xp, i = s.items,
			k = (s.kills or 0) > 0 and s.kills or nil, c = E.charKey }
		local store = self:Store()
		store.zones[s.zone] = store.zones[s.zone] or {}
		local list = store.zones[s.zone]
		table.insert(list, 1, record)
		for i = #list, self.db.keepSessions + 1, -1 do list[i] = nil end
	end
	self.session = nil
	self:Refresh()
	if record and E.Journal and E.Journal.Changed then E.Journal:Changed("farming") end
	if record and self.history and self.history:IsShown() then self:RefreshHistory() end
	return record
end

function M:Reset()
	self.session = nil
	self:Refresh()
end

-- Saved sessions name their character in the row (c); when the character
-- moves to its full-name key, its sessions follow.
E:RegisterCharacterKeyMove(function(db, oldKey, newKey)
	local store = type(db.global) == "table" and db.global.FarmSessions
	local zones = type(store) == "table" and store.zones
	if type(zones) ~= "table" then return end
	for _, list in pairs(zones) do
		if type(list) == "table" then
			for _, row in ipairs(list) do
				if type(row) == "table" and row.c == oldKey then row.c = newKey end
			end
		end
	end
end)

function M:Store()
	local store = E:GetGlobal("FarmSessions") or { zones = {} }
	store.zones = store.zones or {}
	return store
end

-- Best gold (looted gold + item value) per hour for a zone, or nil.
function M:BestPerHour(zone)
	local best
	for _, r in ipairs(self:Store().zones[zone] or {}) do
		if r.d and r.d > 0 then
			local perHour = (r.g + r.v) * 3600 / r.d
			if not best or perHour > best then best = perHour end
		end
	end
	return best
end

function M:PerHour(amount)
	local seconds = self:Elapsed()
	if seconds < 10 then return nil end
	return amount * 3600 / seconds
end

---------------------------------------------------------------------------
-- What gets counted
---------------------------------------------------------------------------
-- Money: positive changes while no merchant, mail, trade, auction or bank
-- window is open (those are sales and post, not loot).
local openWindows = {}
local WINDOW_EVENTS = {
	MERCHANT_SHOW = { "merchant", true }, MERCHANT_CLOSED = { "merchant", false },
	MAIL_SHOW = { "mail", true }, MAIL_CLOSED = { "mail", false },
	TRADE_SHOW = { "trade", true }, TRADE_CLOSED = { "trade", false },
	AUCTION_HOUSE_SHOW = { "auction", true }, AUCTION_HOUSE_CLOSED = { "auction", false },
	BANKFRAME_OPENED = { "bank", true }, BANKFRAME_CLOSED = { "bank", false },
	QUEST_COMPLETE = { "quest", true }, QUEST_FINISHED = { "quest", false },
}
-- The quest reward's PLAYER_MONEY can arrive just after QUEST_FINISHED
-- closes the quest window, so money stays "not loot" this long after it.
local QUEST_GRACE = 1
local questGraceUntil = 0
-- The window behind each kind: a flag whose window is closed again is stale
-- (a missed close event) and is dropped.
local WINDOW_FRAMES = { merchant = "MerchantFrame", mail = "MailFrame", trade = "TradeFrame",
	auction = "AuctionHouseFrame", bank = "BankFrame", quest = "QuestFrame" }

local function WindowOpen()
	if Now() < questGraceUntil then return true end
	for kind in pairs(openWindows) do
		local frame = rawget(_G, WINDOW_FRAMES[kind])
		if type(frame) == "table" and frame.IsShown and not frame:IsShown() then
			openWindows[kind] = nil
		else
			return true
		end
	end
	return false
end

function M:OnMoney()
	local money = GetMoney and Clean(GetMoney())
	if type(money) ~= "number" then return end
	local last = self.lastMoney
	self.lastMoney = money
	if not last or money <= last or WindowOpen() then return end
	if not self:Running() then
		if not (self.db.autoStart and not self.session) then return end
		self:Start()
	end
	self.session.gold = self.session.gold + (money - last)
	self:CheckGoal()
	self:Refresh()
end

function M:ItemValue(itemID, count)
	local sell = select(11, Try(C_Item and C_Item.GetItemInfo or rawget(_G, "GetItemInfo"), itemID))
	sell = type(Clean(sell)) == "number" and sell or 0
	local auction = 0
	local module = E.GetModule and E:GetModule("Auction")
	if module and module.GetPrice then auction = Clean(Try(module.GetPrice, module, itemID)) or 0 end
	local source = self.db.valueSource
	local each = source == "vendor" and sell or source == "auction" and (auction > 0 and auction or sell) or max(sell, auction)
	return each * (count or 1)
end

-- A Lua pattern from a global format string, the way Blizzard builds them:
-- escape every magic character (the % of %s and %d too), then turn the
-- escaped %s into (.-) and %d into (%d+), the positional %1$s forms too.
local function FormatToPattern(format)
	local p = format:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
	p = p:gsub("%%%%%d%%%$s", "(.-)"):gsub("%%%%%d%%%$d", "(%%d+)")
	p = p:gsub("%%%%s", "(.-)"):gsub("%%%%d", "(%%d+)")
	return "^" .. p .. "$"
end
M.FormatToPattern = FormatToPattern

-- "You receive loot: [Item]x3." with the game's own patterns. Built on the
-- first loot line; setting M.lootPatterns = nil builds them again.
local function LootPatterns()
	if M.lootPatterns then return M.lootPatterns end
	local list = {}
	local function Pattern(name, multiple)
		local format = _G[name]
		if type(format) ~= "string" or issecret(format) then return end
		list[#list + 1] = { FormatToPattern(format), multiple }
	end
	Pattern("LOOT_ITEM_SELF_MULTIPLE", true)
	Pattern("LOOT_ITEM_PUSHED_SELF_MULTIPLE", true)
	Pattern("LOOT_ITEM_SELF", false)
	Pattern("LOOT_ITEM_PUSHED_SELF", false)
	if #list == 0 then
		list = { { "^You receive loot: (.-)x(%d+)%.$", true }, { "^You receive loot: (.-)%.$", false } }
	end
	M.lootPatterns = list
	return list
end

function M:ParseLoot(text)
	text = Clean(text)
	if type(text) ~= "string" then return nil end
	for _, pattern in ipairs(LootPatterns()) do
		local link, count = text:match(pattern[1])
		if link then
			link = E.ChatParse and E.ChatParse:ItemLink(link) or link
			local itemID = tonumber(link:match("item:(%d+)"))
			if itemID then return itemID, pattern[2] and tonumber(count) or 1 end
		end
	end
	return nil
end

function M:OnLoot(text)
	local itemID, count = self:ParseLoot(text)
	if not itemID then return end
	-- "You receive item:" also comes for purchases, mail and quest rewards.
	if WindowOpen() then return end
	if not self:Running() then
		if not (self.db.autoStart and not self.session) then return end
		self:Start()
	end
	local s = self.session
	s.items = s.items + count
	s.value = s.value + self:ItemValue(itemID, count)
	s.looted[itemID] = (s.looted[itemID] or 0) + count
	self:CheckGoal()
	self:Refresh()
end

-- Corpses looted: creature sources of the open loot window, each once.
-- Open world and out of combat only; a secret source is skipped untouched.
local function IsCorpse(guid)
	if E:IsSecret(guid) or type(guid) ~= "string" then return false end
	return guid:find("^Creature%-") ~= nil or guid:find("^Vehicle%-") ~= nil
end

function M:OnLootWindow()
	if InCombatLockdown() then return end
	if IsInInstance and Clean(Try(IsInInstance)) ~= false then return end
	if not (GetNumLootItems and GetLootSourceInfo) then return end
	local slots = Clean(Try(GetNumLootItems))
	if type(slots) ~= "number" or slots < 1 then return end
	local found
	for slot = 1, slots do
		local sources = { Try(GetLootSourceInfo, slot) }
		for index = 1, 11, 2 do
			local guid = sources[index]
			if guid == nil then break end
			if IsCorpse(guid) then
				found = found or {}
				found[guid] = true
			end
		end
	end
	if not found then return end
	if not self:Running() then
		if not (self.db.autoStart and not self.session) then return end
		self:Start()
	end
	local s = self.session
	s.corpses = s.corpses or {}
	local added = false
	for guid in pairs(found) do
		if not s.corpses[guid] then
			s.corpses[guid] = true
			s.kills = (s.kills or 0) + 1
			added = true
		end
	end
	if added then self:Refresh() end
end

function M:OnXP()
	local xp, maxXP = UnitXP and Clean(UnitXP("player")), UnitXPMax and Clean(UnitXPMax("player"))
	if type(xp) ~= "number" then return end
	local last, lastMax = self.lastXP, self.lastXPMax
	self.lastXP, self.lastXPMax = xp, maxXP
	if not (last and self:Running()) then return end
	local gained = xp - last
	if gained < 0 and lastMax then gained = (lastMax - last) + xp end -- leveled up
	if gained > 0 then
		self.session.xp = self.session.xp + gained
		self:Refresh()
	end
end

function M:CheckGoal()
	local goal = (self.db.goal or 0) * 10000
	local s = self.session
	if goal <= 0 or not s or self.goalReached then return end
	if s.gold + s.value >= goal then
		self.goalReached = true
		M:PushAlert({ key = "farm-goal", title = L["Farming goal"], text = (L["You reached %s."]):format(Money(goal)), icon = 133784, duration = 8 })
		if self.db.goalSound and self.db.goalSound ~= "none" then E:PlayMedia(self.db.goalSound) end
	end
end

---------------------------------------------------------------------------
-- The bar
---------------------------------------------------------------------------
function M:Text()
	local s = self.session
	if not s then return L["Farming: no session. Click to start."] end
	local parts = { Clock(self:Elapsed()) .. (s.paused and " " .. E:TextHex("secondary") .. "(" .. s.paused .. ")|r" or "") }
	if self.db.showGold then
		local perHour = self:PerHour(s.gold)
		parts[#parts + 1] = Money(s.gold) .. (perHour and (" " .. E:TextHex("secondary") .. "(" .. Money(perHour) .. "/h)|r") or "")
	end
	if self.db.showItems then
		local itemsHour, perHour = self:PerHour(s.items), self:PerHour(s.value)
		parts[#parts + 1] = E:Plural(s.items, "%d item", "%d items"):format(s.items) .. (itemsHour and (" " .. E:TextHex("secondary") .. "(" .. Short(itemsHour) .. "/h)|r") or "")
			.. " " .. Money(s.value) .. (perHour and (" " .. E:TextHex("secondary") .. "(" .. Money(perHour) .. "/h)|r") or "")
	end
	if self.db.showXP and s.xp > 0 then
		local perHour = self:PerHour(s.xp)
		parts[#parts + 1] = ("%s XP"):format(Short(s.xp)) .. (perHour and (" " .. E:TextHex("secondary") .. "(" .. Short(perHour) .. "/h)|r") or "")
	end
	return table.concat(parts, "  ·  ")
end

-- The kit's icon button in a flat box: a glyph (play, pause) or a flat
-- square (stop), secondary gray, accent on hover.
local function SmallButton(parent, art, onClick, tip)
	local button = E.UIKit.IconButton(parent, 16, art, onClick, tip)
	button:SetSize(18, 16)
	E:SetTemplate(button)
	return button
end

local BAR_TICK = "EldoUI.Farming.bar" -- the shared ticker key of the bar text

function M:BuildBar()
	if self.bar then return end
	local bar = CreateFrame("Button", "EldoUI_FarmBar", UIParent)
	bar:SetSize(self.db.barWidth, 20)
	bar:SetFrameStrata("MEDIUM")
	bar:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	E:SetTemplate(bar, true)
	E:SetStyleEdge(bar) -- WoW Forever art style frame line
	bar.text = E:CreateText(bar, E.tokens.size.small, "LEFT")
	bar.text:SetPoint("LEFT", 6, 0)
	bar.stop = SmallButton(bar, E.media.flat, function() M:Stop() end, L["Stop and save the session"])
	bar.stop.square = bar.stop.icon
	bar.stop.square:SetSize(6, 6)
	bar.stop:SetPoint("RIGHT", -2, 0)
	bar.toggle = SmallButton(bar, "pause", function() M:Toggle() end, L["Pause or go on"])
	bar.toggle:SetPoint("RIGHT", bar.stop, "LEFT", -2, 0)
	bar.text:SetPoint("RIGHT", bar.toggle, "LEFT", -4, 0)
	bar:SetScript("OnClick", function(_, button)
		if E:IsOptionsLinkClick(bar, button) then return end
		if button == "RightButton" then M:OpenMenu(bar) else M:Toggle() end
	end)
	bar:SetScript("OnEnter", function(b) M:Tooltip(b) end)
	bar:SetScript("OnLeave", GameTooltip_Hide)
	E:BindOptionsLink(bar, { page = "module:Farming" })
	-- The session text once a second on the shared ticker, only while the
	-- bar is on screen.
	bar:SetScript("OnShow", function()
		E.Ticker:Subscribe(BAR_TICK, 1, function()
			if M:Running() then bar.text:SetText(M:Text()) end
		end, M)
	end)
	bar:SetScript("OnHide", function() E.Ticker:Unsubscribe(BAR_TICK) end)
	bar:Hide()
	self.bar = bar
	E:CreateMover(bar, "EldoUI_FarmBar", L["Farming Bar"], { "TOP", "UIParent", "TOP", 300, -8 }, { sample = { kind = "icons" } })
end

-- The session's tooltip rows: { label, value, kind } (kind "item" for the
-- top loot, "best" for the zone's best).
function M:TooltipLines()
	local lines = {}
	local s = self.session
	if not s then return lines end
	local function Add(label, value, kind) lines[#lines + 1] = { label, value, kind } end
	Add(L["Zone"], s.zone)
	Add(L["Time"], Clock(self:Elapsed()))
	Add(L["Looted gold"], Money(s.gold))
	Add(L["Item value"], Money(s.value))
	Add(L["Total per hour"], Money(self:PerHour(s.gold + s.value) or 0))
	Add(L["Items looted"], tostring(s.items))
	local itemsHour = self:PerHour(s.items)
	if itemsHour then Add(L["Items per hour"], Short(itemsHour)) end
	if (s.kills or 0) > 0 then
		Add(L["Corpses looted"], tostring(s.kills))
		local killsHour = self:PerHour(s.kills)
		if killsHour then Add(L["Corpses looted per hour"], Short(killsHour)) end
	end
	if s.xp > 0 then
		Add(L["XP"], Short(s.xp))
		local xpHour = self:PerHour(s.xp)
		if xpHour then Add(L["XP per hour"], Short(xpHour)) end
	end
	local top = {}
	for itemID, count in pairs(s.looted) do top[#top + 1] = { itemID, count, self:ItemValue(itemID, count) } end
	table.sort(top, function(a, b) return a[3] > b[3] end)
	for i = 1, math.min(5, #top) do
		local name = C_Item and C_Item.GetItemNameByID and Clean(Try(C_Item.GetItemNameByID, top[i][1]))
		if type(name) ~= "string" then name = (L["Item %d"]):format(top[i][1]) end
		Add(("%s x%d"):format(name, top[i][2]), Money(top[i][3]), "item")
	end
	local best = self:BestPerHour(s.zone)
	if best then Add(L["Best here"], Money(best) .. "/h", "best") end
	return lines
end

function M:Tooltip(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
	GameTooltip:AddLine(L["Farming"], E:TokenColor("body"))
	for _, line in ipairs(self:TooltipLines()) do
		local kind = line[3]
		local lr, lg, lb = E:TokenColor(kind == "item" and "dim" or "secondary")
		local rr, rg, rb = E:TokenColor(kind == "best" and "accent" or "body")
		GameTooltip:AddDoubleLine(line[1], line[2], lr, lg, lb, rr, rg, rb)
	end
	local dr, dg, db = E:TokenColor("dim")
	E.UIKit.TipText(GameTooltip, L["The square button saves the session."])
	E:TooltipHint(GameTooltip, { L["Click"], L["start or pause"] }, { L["Right-click"], L["the session history"] })
	GameTooltip:Show()
end

-- On a flight path the bar steps aside: the layouts give the flight bar
-- and the farming bar one spot in the top notice row.
local function OnTaxi()
	return UnitOnTaxi ~= nil and Clean(UnitOnTaxi("player")) == true
end

function M:Refresh()
	local bar = self.bar
	if not bar then return end
	local moveMode = E.IsMoveMode and E:IsMoveMode()
	local show = self.active and (self.session ~= nil or self.db.alwaysShow or moveMode) and (moveMode or not OnTaxi())
	if not show then bar:Hide() return end
	bar:SetWidth(self.db.barWidth)
	bar.text:SetText(self:Text())
	bar.toggle:SetArt(self:Running() and "pause" or "play")
	bar.stop:SetShown(self.session ~= nil)
	bar:Show()
end

---------------------------------------------------------------------------
-- The bar's menu (right-click)
---------------------------------------------------------------------------
function M:OpenMenu(owner)
	local items = {
		{ text = L["Farming"], isTitle = true },
		{ text = self:Running() and L["Pause"] or L["Start"], func = function() M:Toggle() end },
		{ text = L["Stop and save"], disabled = not self.session, func = function() M:Command("stop") end },
		{ text = L["Reset session"], disabled = not self.session, func = function() M:ConfirmReset() end },
		{ divider = true },
		{ text = L["Session history"], func = function() M:OpenHistory() end },
	}
	E.UIKit.OpenMenu(owner, items)
end

function M:ConfirmReset()
	if not self.session then return end
	E:ShowConfirm({
		key = "farm-reset", danger = true,
		title = L["Reset this session?"],
		text = L["The running session is cleared without saving it."],
		accept = L["Reset"],
		onAccept = function() M:Reset() end,
	})
end

---------------------------------------------------------------------------
-- Session history: every saved session per zone, with totals
---------------------------------------------------------------------------
local ALL_ZONES = "*"

-- Saved sessions as rows, newest first. zone nil or "*": every zone.
function M:HistoryRows(zone)
	local rows = {}
	for name, list in pairs(self:Store().zones) do
		if (zone == nil or zone == ALL_ZONES or name == zone) and type(list) == "table" then
			for _, r in ipairs(list) do
				local seconds = tonumber(r.d) or 0
				local function Hour(amount)
					amount = tonumber(amount)
					if not amount or seconds <= 0 then return nil end
					return floor(amount * 3600 / seconds + 0.5)
				end
				rows[#rows + 1] = {
					zone = name, record = r, t = tonumber(r.t) or 0, d = seconds,
					gold = tonumber(r.g) or 0, value = tonumber(r.v) or 0, xp = tonumber(r.x) or 0,
					items = tonumber(r.i) or 0, kills = tonumber(r.k),
					goldHour = Hour(r.g or 0), valueHour = Hour(r.v or 0), xpHour = Hour(r.x or 0),
					itemsHour = Hour(r.i or 0), killsHour = Hour(r.k),
				}
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.t ~= b.t then return a.t > b.t end
		return a.zone < b.zone
	end)
	return rows
end

function M:HistoryTotals(rows)
	local totals = { sessions = #rows, seconds = 0, gold = 0, value = 0, xp = 0, items = 0, kills = 0 }
	for _, row in ipairs(rows) do
		totals.seconds = totals.seconds + row.d
		totals.gold = totals.gold + row.gold
		totals.value = totals.value + row.value
		totals.xp = totals.xp + row.xp
		totals.items = totals.items + row.items
		totals.kills = totals.kills + (row.kills or 0)
	end
	if totals.seconds > 0 then totals.perHour = floor((totals.gold + totals.value) * 3600 / totals.seconds + 0.5) end
	return totals
end

local function HistoryZones()
	local names, counts = {}, {}
	for name, list in pairs(M:Store().zones) do
		if type(list) == "table" and #list > 0 then
			names[#names + 1] = name
			counts[name] = #list
		end
	end
	table.sort(names)
	local values = { { ALL_ZONES, L["All zones"] } }
	for _, name in ipairs(names) do values[#values + 1] = { name, ("%s (%d)"):format(name, counts[name]) } end
	return values
end

function M:HistoryFooter(rows)
	local totals = self:HistoryTotals(rows)
	if totals.sessions == 0 then return "" end
	local parts = {
		E:Plural(totals.sessions, "%d session", "%d sessions"):format(totals.sessions),
		Clock(totals.seconds),
		(L["gold %s"]):format(Money(totals.gold)),
		(L["items worth %s"]):format(Money(totals.value)),
		(L["%s per hour"]):format(Money(totals.perHour or 0)),
		E:Plural(totals.items, "%d item", "%d items"):format(totals.items),
	}
	if totals.kills > 0 then parts[#parts + 1] = (L["%d corpses looted"]):format(totals.kills) end
	if totals.xp > 0 then parts[#parts + 1] = (L["%s XP"]):format(Short(totals.xp)) end
	return table.concat(parts, "  ·  ")
end

local function OrDash(value, format)
	if value == nil then return "-" end
	return format(value)
end

function M:BuildHistory()
	if self.history then return self.history end
	local Kit = E.UIKit
	local win = Kit.CreateToolWindow("EldoUI_FarmHistory", {
		title = L["Farming history"], width = 780, height = 420, footer = Kit.TOOL_FOOTER,
		resizable = { minWidth = 640, minHeight = 260, maxWidth = 1200, maxHeight = 900 },
		store = function()
			local store = M:Store()
			store.window = type(store.window) == "table" and store.window or {}
			return store.window
		end,
	})
	local pad = Kit.TOOL_PAD
	win.zone = Kit.Dropdown(win.content, {
		width = 240,
		values = HistoryZones,
		get = function() return M.historyZone end,
		set = function(value)
			M.historyZone = value
			M:RefreshHistory()
		end,
	})
	win.zone:SetPoint("TOPLEFT", pad, -pad)
	Kit.Tooltip(win.zone, L["Zone"], L["Show the sessions of one zone, or of all zones."])
	win.hint = Kit.Text(win.content, E.tokens.size.small, "RIGHT", "secondary")
	win.hint:SetPoint("LEFT", win.zone, "RIGHT", 12, 0)
	win.hint:SetPoint("RIGHT", win.content, "RIGHT", -pad, 0)
	win.hint:SetText(L["Right-click a session to delete it."])
	local function When(row, pattern) return row.t > 0 and date(pattern, row.t) or "-" end
	win.table = Kit.CreateTable(win.content, {
		{ key = "t", title = L["Date"], width = 118, text = function(row) return When(row, "%Y-%m-%d %H:%M") end },
		{ key = "zone", title = L["Zone"] },
		{ key = "d", title = L["Time"], width = 70, align = "RIGHT", text = function(row) return Clock(row.d) end },
		{ key = "goldHour", title = L["Gold/h"], width = 112, align = "RIGHT", desc = L["Looted gold per hour."],
			text = function(row) return OrDash(row.goldHour, Money) end },
		{ key = "valueHour", title = L["Value/h"], width = 112, align = "RIGHT", desc = L["Looted item value per hour."],
			text = function(row) return OrDash(row.valueHour, Money) end },
		{ key = "xpHour", title = L["XP/h"], width = 64, align = "RIGHT", desc = L["XP gained per hour."],
			text = function(row) return row.xp > 0 and OrDash(row.xpHour, Short) or "-" end },
		{ key = "items", title = L["Items"], width = 92, align = "RIGHT", desc = L["Items looted, and items per hour."],
			text = function(row) return ("%d  %s%s/h|r"):format(row.items, E:TextHex("secondary"), OrDash(row.itemsHour, Short)) end },
		{ key = "kills", title = L["Corpses"], width = 64, align = "RIGHT", desc = L["Corpses looted in the open world, each one once."],
			value = function(row) return row.kills or 0 end,
			text = function(row) return row.kills and tostring(row.kills) or "-" end },
	}, {
		sortKey = "t", sortDown = true, rowHeight = 22,
		empty = { L["No saved sessions"], L["Stop a session with the square button on the Farming bar to save it here. A session needs a minute and some loot or XP to be saved."] },
		onClick = function(row, button)
			if button ~= "RightButton" then return end
			Kit.OpenMenu(nil, {
				{ text = ("%s, %s"):format(row.zone, When(row, "%Y-%m-%d")), isTitle = true },
				{ text = L["Delete this session"], func = function() M:ConfirmDelete(row) end },
			})
		end,
	})
	win.table:SetPoint("TOPLEFT", win.zone, "BOTTOMLEFT", 0, -pad)
	win.table:SetPoint("BOTTOMRIGHT", win.content, "BOTTOMRIGHT", -pad, pad)
	self.history = win
	return win
end

function M:RefreshHistory()
	local win = self.history
	if not win then return end
	local zone = self.historyZone or ALL_ZONES
	if zone ~= ALL_ZONES and not self:Store().zones[zone] then
		zone = ALL_ZONES
		self.historyZone = zone
	end
	local rows = self:HistoryRows(zone)
	win.zone:Refresh()
	win.table:SetData(rows)
	win.footerText:SetText(self:HistoryFooter(rows))
end

-- Open the history on a zone (default: the session's zone or this zone
-- when it has saved sessions, else all zones).
function M:OpenHistory(zone)
	local win = self:BuildHistory()
	local zones = self:Store().zones
	if not zone then
		local here = self.session and self.session.zone or ZoneName()
		zone = type(zones[here]) == "table" and #zones[here] > 0 and here or ALL_ZONES
	end
	self.historyZone = zone
	self:RefreshHistory()
	win:Open()
	return win
end

function M:DeleteSession(zone, record)
	local zones = self:Store().zones
	local list = zones[zone]
	if type(list) ~= "table" then return false end
	for index, r in ipairs(list) do
		if r == record then
			table.remove(list, index)
			if #list == 0 then zones[zone] = nil end
			if E.Journal and E.Journal.Changed then E.Journal:Changed("farming") end
			if self.history and self.history:IsShown() then self:RefreshHistory() end
			return true
		end
	end
	return false
end

function M:ConfirmDelete(row)
	if not (row and row.record) then return end
	E:ShowConfirm({
		key = "farm-delete", danger = true,
		title = L["Delete this session?"],
		text = (L["%s, %s: %s in %s. This can't be undone."]):format(row.zone, row.t > 0 and E:ShortDate(row.t) or "-",
			Money(row.gold + row.value), Clock(row.d)),
		accept = L["Delete"],
		onAccept = function() M:DeleteSession(row.zone, row.record) end,
	})
end

---------------------------------------------------------------------------
-- Events, datatext, commands
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, a)
	if not M.active then return end
	local window = WINDOW_EVENTS[event]
	if window then
		openWindows[window[1]] = window[2] or nil
		if event == "QUEST_FINISHED" then questGraceUntil = Now() + QUEST_GRACE end
		-- Money that moves while a window is open is not loot.
		M.lastMoney = GetMoney and Clean(GetMoney()) or M.lastMoney
	elseif event == "PLAYER_MONEY" then
		M:OnMoney()
	elseif event == "CHAT_MSG_LOOT" then
		M:OnLoot(a)
	elseif event == "PLAYER_XP_UPDATE" then
		M:OnXP()
	elseif event == "LOOT_OPENED" or event == "LOOT_READY" then
		M:OnLootWindow()
	elseif event == "PLAYER_FLAGS_CHANGED" then
		if not M.db.afkPause or not M.session then return end
		local afk = UnitIsAFK and Clean(UnitIsAFK("player"))
		if afk and M:Running() then
			M:Pause("away")
		elseif not afk and M.session.paused == "away" then
			M:Start()
		end
	elseif event == "PLAYER_CONTROL_LOST" or event == "PLAYER_CONTROL_GAINED" then
		-- A flight starts or ends; the taxi state can follow a moment later.
		M:Refresh()
		C_Timer.After(0.5, function() if M.active then M:Refresh() end end)
	elseif event == "PLAYER_LOGOUT" then
		M:SaveSession()
	elseif event == "PLAYER_ENTERING_WORLD" then
		wipe(openWindows)
		M.lastMoney = GetMoney and Clean(GetMoney()) or nil
		M:OnXP()
		M:Refresh()
	end
end)

function M:Command(arg)
	arg = (arg or ""):lower():match("^%s*(.-)%s*$")
	if arg == "start" then
		self:Start()
	elseif arg == "pause" then
		self:Pause()
	elseif arg == "stop" then
		local record = self:Stop()
		E:Print(record and (L["Session saved: %s in %s."]):format(Money(record.g + record.v), Clock(record.d)) or L["Session ended (too short to save)."])
	elseif arg == "reset" then
		self:Reset()
	elseif arg == "history" then
		self:OpenHistory()
	elseif arg == "" or arg == "status" then
		E:Print(self:Text())
	else
		E:Print(L["/eui farm [start | pause | stop | reset | history]"])
	end
end

E:AddCommand("farm", "[start | pause | stop | reset | history]  the farming session bar and its history", function(arg)
	if M.active then M:Command(arg) else E:Print(E:ModuleOffHint("Farming")) end
end)

---------------------------------------------------------------------------
-- Keeping the session over /reload
---------------------------------------------------------------------------
-- At logout (also /reload) the session goes to this character's saved data
-- and is picked up again when the module starts: a running session goes on,
-- a paused one stays paused. One older than RESUME_LIMIT (a real logout,
-- not a reload) is saved under its zone instead, as if it was stopped.
local RESUME_LIMIT = 30 * 60

function M:SaveSession()
	local store = E:GetPrivate("Farming")
	if not store then return end
	local s = self.session
	if not s then
		store.session = nil
		return
	end
	store.session = {
		elapsed = self:Elapsed(), running = self:Running() or nil, paused = s.paused,
		gold = s.gold, value = s.value, items = s.items, xp = s.xp, kills = s.kills, corpses = s.corpses, zone = s.zone,
		looted = s.looted, startedAt = s.startedAt, savedAt = time(), goalReached = self.goalReached or nil,
	}
end

function M:RestoreSession()
	local store = E:GetPrivate("Farming")
	if not store then return end
	local saved = store.session
	store.session = nil
	if self.session or type(saved) ~= "table" or type(saved.elapsed) ~= "number" then return end
	self.session = {
		elapsed = saved.elapsed, gold = tonumber(saved.gold) or 0, value = tonumber(saved.value) or 0,
		items = tonumber(saved.items) or 0, xp = tonumber(saved.xp) or 0, zone = saved.zone or ZoneName(),
		kills = tonumber(saved.kills) or 0, corpses = type(saved.corpses) == "table" and saved.corpses or {},
		looted = type(saved.looted) == "table" and saved.looted or {}, startedAt = saved.startedAt or time(),
		paused = saved.paused or (not saved.running and "paused") or nil,
	}
	self.goalReached = saved.goalReached and true or false
	if type(saved.savedAt) ~= "number" or time() - saved.savedAt > RESUME_LIMIT then
		self:Stop()
	elseif saved.running then
		self.session.runningSince = Now()
	end
end

---------------------------------------------------------------------------
-- The journal source (My Adventure): this character's saved sessions.
---------------------------------------------------------------------------
function M:JournalRows(charKey, from, to)
	local rows = {}
	for zone, list in pairs(self:Store().zones) do
		for _, r in ipairs(type(list) == "table" and list or {}) do
			local t = tonumber(r.t)
			if r.c == charKey and t and t >= from and t <= to then
				rows[#rows + 1] = { t = t, kind = "farm", seconds = r.d, money = (r.g or 0) + (r.v or 0), zone = zone,
					ref = ("farming:%s:%d"):format(zone, t) }
			end
		end
	end
	return rows
end

function M:JournalFacts(charKey)
	local sessions, seconds, money, best, bestRate = 0, 0, 0, nil, 0
	for zone, list in pairs(self:Store().zones) do
		for _, r in ipairs(type(list) == "table" and list or {}) do
			if r.c == charKey and (r.d or 0) > 0 then
				sessions, seconds = sessions + 1, seconds + r.d
				local value = (r.g or 0) + (r.v or 0)
				money = money + value
				local rate = value * 3600 / r.d
				if rate > bestRate then best, bestRate = zone, rate end
			end
		end
	end
	return { farmSessions = sessions, farmSeconds = seconds, farmMoney = money, bestFarmZone = best,
		bestFarmPerHour = best and floor(bestRate) or nil }
end

local function RegisterJournalSource()
	local J = E.Journal
	if not (J and J.RegisterSource) then return end
	J:RegisterSource("farming", {
		title = L["Farming sessions"],
		module = "Farming",
		scope = "char",
		kinds = { "farm" },
		read = function(charKey, from, to) return M:JournalRows(charKey, from, to) end,
		summarize = function(charKey) return M:JournalFacts(charKey) end,
	})
end

function M:OnInitialize()
	E:RegisterPrivate("Farming", {})
	E:RegisterGlobal("FarmSessions", { zones = {} })
	RegisterJournalSource()
	if E.RegisterDataText then
		E:RegisterDataText("Farming", {
			title = "Farming",
			label = "Farm",
			poll = true,
			text = function()
				if not (M.active and M.session) then return "-" end
				return ("%s %s/h"):format(Clock(M:Elapsed()), Money(M:PerHour(M.session.gold + M.session.value) or 0))
			end,
			tooltip = function() M:Tooltip(GameTooltip:GetOwner() or UIParent) end,
			onClick = function(_, mouseButton)
				if not M.active then return end
				if mouseButton == "RightButton" then M:OpenHistory() else M:Toggle() end
			end,
		})
	end
end

function M:OnEnable()
	self:BuildBar()
	local list = { "PLAYER_MONEY", "CHAT_MSG_LOOT", "LOOT_OPENED", "LOOT_READY", "PLAYER_XP_UPDATE", "PLAYER_FLAGS_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT",
		"PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED" }
	for event in pairs(WINDOW_EVENTS) do list[#list + 1] = event end
	for _, event in ipairs(list) do pcall(events.RegisterEvent, events, event) end
	self.lastMoney = GetMoney and Clean(GetMoney()) or nil
	self:OnXP()
	self:RestoreSession()
	self:Refresh()
end

function M:OnDisable()
	events:UnregisterAllEvents()
	if self.session then self:Pause() end
	if self.bar then self.bar:Hide() end
	E.Ticker:UnsubscribeOwner(self)
end

function M:OnProfileChanged()
	if self.active then self:Refresh() end
end

---------------------------------------------------------------------------
-- Options and styles
---------------------------------------------------------------------------
M.options = {
	{ type = "description", label = "A session counts looted gold, items and their worth, and XP, also per hour. Stop saves it in the session history. Also: /eui farm." },
	{ type = "header", label = "Session" },
	{ type = "toggle", key = "autoStart", label = "Start on the first loot", desc = "Begin a session by itself when you loot money or an item and none is running. Off: start it with a click." },
	{ type = "toggle", key = "afkPause", label = "Pause while away", desc = "The timer stops while you are marked away and goes on when you are back." },
	{ type = "select", key = "valueSource", label = "Item value", values = { vendor = "Vendor price", auction = "Auction price", max = "The higher of both" }, desc = "How looted items are valued. Auction prices are the ones EldoUI saved when you searched the auction house." },
	{ type = "range", key = "goal", label = "Gold goal", unit = "g", zeroText = "No goal", min = 0, max = 1000, step = 5,
		desc = "A note when the session's gold plus item value reaches this much." },
	{ type = "media", key = "goalSound", label = "Goal sound", mediaKind = "sound", none = true, desc = "A sound with the goal note. None for silence.",
		disabled = function() return (M.db.goal or 0) == 0 and L["Set a gold goal first."] end },
	{ type = "range", key = "keepSessions", label = "Sessions kept per zone", min = 1, max = 50, step = 1, desc = "How many saved sessions each zone keeps." },
	{ type = "execute", label = "Session history", testSafe = true,
		desc = "Your saved sessions per zone with gold, item value, XP, items and corpses looted per hour, and the totals. Also from the bar's right-click menu and the Farming info bar text.",
		func = function() M:OpenHistory() end },
	{ type = "header", label = "Bar" },
	{ type = "toggle", key = "alwaysShow", label = "Always show", desc = "Show the bar also when no session runs, to start one with a click. On a flight path it steps aside for the flight bar. Move it in move mode (Farming Bar)." },
	{ type = "toggle", key = "showGold", label = "Looted gold", desc = "Show the gold you looted and gold per hour." },
	{ type = "toggle", key = "showItems", label = "Items and their value", desc = "Show the items you looted, their value and value per hour." },
	{ type = "toggle", key = "showXP", label = "XP", desc = "Show the XP you gained and XP per hour." },
	{ type = "range", unit = "px", key = "barWidth", label = "Width", min = 200, max = 600, step = 10, desc = "Width of the panel with your gold, items and XP." },
}

E:RegisterStyles("Farming", {
	{ key = "Standard", title = "Standard", desc = "Gold, items and XP; starts on the first loot.",
		settings = { autoStart = true, showGold = true, showItems = true, showXP = true, alwaysShow = false, barWidth = 360 } },
	{ key = "Gold", title = "Gold farmer", desc = "Gold and items only, valued at the higher of vendor and auction price.",
		settings = { showXP = false, valueSource = "max", barWidth = 300 } },
	{ key = "Levelling", title = "Leveling", desc = "XP per hour first, with looted gold.",
		settings = { showItems = false, showXP = true, showGold = true, barWidth = 280 } },
	{ key = "Manual", title = "Manual", desc = "Sessions start only with a click; the bar stays on screen.",
		settings = { autoStart = false, alwaysShow = true } },
	{ key = "DataTextOnly", title = "Info bar only", desc = "No bar unless a session runs; use the Farming info bar text.",
		settings = { alwaysShow = false, barWidth = 240 } },
})
