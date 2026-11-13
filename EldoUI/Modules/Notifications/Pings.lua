-- EldoUI Notifications: pings.
-- Everything here is optional and off by default, and only ever uses
-- Blizzard's own ping system (Blizzard_PingUI) with the player's own keys
-- and clicks. EldoUI never sends a ping by itself and never posts to chat.
--
--   Ping feed     a small movable list of the pings you receive (time,
--                 sender, text) from CHAT_MSG_PING. The text and sender can
--                 be secret values in combat: each goes on its own font
--                 string through SetText and is never joined, compared or
--                 stored anywhere else. Rows fade out; filters per content
--                 (world, dungeons, raids, battlegrounds, arenas); optional
--                 sound.
--   Pingable icons EldoUI's own cooldown icons answer the game's ping key
--                 like Blizzard's Cooldown Manager icons do: hover an icon,
--                 press your ping key, and the game pings that spell or
--                 item (its own receiver attribute and target info).
--   Ping keys     four key bindings (Key Bindings > AddOns > EldoUI Pings)
--                 that ping a spell or item you choose through Blizzard's own
--                 /pingspell and /pingitem commands on a secure button. One
--                 key press is one ping.
--
-- Written from scratch for EldoUI; no code, strings or data from other addons.
local _, E = ...
local L = E.L
local M = E:GetModule("Notifications")
local U = M.util

local PING_KEYS = 4

---------------------------------------------------------------------------
-- Ping feed
---------------------------------------------------------------------------
local feed
local ROW_GAP = 2

-- Content type of where the player is now (IsInInstance's second value).
local CONTENT = { none = "world", party = "dungeon", scenario = "dungeon", raid = "raid", pvp = "battleground", arena = "arena" }

local function ContentAllowed()
	local _, kind = IsInInstance()
	local key = CONTENT[U.Safe(kind) or "none"] or "world"
	return M.db.pings.content[key] ~= false
end

-- A value for SetText: secrets pass through untouched (never tested).
local function Shown(value)
	if U.Secret(value) then return value end
	if type(value) == "string" then return value end
	return ""
end

local function FeedRow(index)
	local row = feed.rows[index]
	if row then return row end
	row = CreateFrame("Frame", nil, feed)
	row.time = E:CreateText(row, E.tokens.size.small, "LEFT")
	row.time:SetPoint("LEFT", 4, 0)
	row.time:SetWidth(40)
	row.sender = E:CreateText(row, E.tokens.size.label, "LEFT")
	row.sender:SetPoint("LEFT", row.time, "RIGHT", 4, 0)
	row.sender:SetWidth(96)
	row.text = E:CreateText(row, E.tokens.size.label, "LEFT")
	row.text:SetPoint("LEFT", row.sender, "RIGHT", 4, 0)
	row.text:SetPoint("RIGHT", -4, 0)
	row:Hide()
	feed.rows[index] = row
	return row
end

function M:LayoutPingFeed()
	if not feed then return end
	local db = self.db.pings
	local size = db.fontSize
	local height = math.ceil(size * E:TextScale()) + 6
	feed:SetSize(db.width, db.rows * (height + ROW_GAP) + 6)
	-- The columns follow the text size and Large text: the clock is
	-- measured in its own font, the sender gets its share of the feed.
	if not feed.measure then
		feed.measure = E:CreateText(feed, E.tokens.size.small, "LEFT")
		feed.measure:Hide()
	end
	E:SetFont(feed.measure, math.max(9, size - 1))
	feed.measure:SetText(E:FormatClock(12, 58, 58))
	local timeWidth = math.ceil(feed.measure.GetUnboundedStringWidth and feed.measure:GetUnboundedStringWidth() or feed.measure:GetStringWidth() or 40) + 2
	timeWidth = math.max(40, timeWidth)
	local senderWidth = math.floor(math.min(96 * size / 12 * E:TextScale(), db.width * 0.4) + 0.5)
	senderWidth = math.max(60, senderWidth)
	if db.backdrop then
		E:SetPanelTemplate(feed, true)
	elseif feed.SetBackdrop then
		feed:SetBackdrop(nil)
	end
	for index = 1, math.max(db.rows, #feed.rows) do
		local row = FeedRow(index)
		row:ClearAllPoints()
		-- Newest at the top.
		row:SetPoint("TOPLEFT", 3, -3 - (index - 1) * (height + ROW_GAP))
		row:SetPoint("TOPRIGHT", -3, -3 - (index - 1) * (height + ROW_GAP))
		row:SetHeight(height)
		E:SetFont(row.time, math.max(9, size - 1))
		E:SetNameTextFont(row.sender, size)
		E:SetFont(row.text, size)
		row.time:SetWidth(timeWidth)
		row.sender:SetWidth(senderWidth)
		row.time:SetTextColor(unpack(E.media.text.secondary))
		row.text:SetTextColor(1, 1, 1)
		if index > db.rows then row:Hide() end
	end
end

local function CreateFeed()
	feed = CreateFrame("Frame", "EldoUI_PingFeedFrame", UIParent)
	feed:SetFrameStrata("MEDIUM")
	feed:EnableMouse(false)
	feed.rows = {}
	feed.entries = {}   -- { at, time, sender (may be secret), text (may be secret), r, g, b }
	local previous = E.currentModule
	E.currentModule = M
	E:CreateMover(feed, "EldoUI_PingFeed", "Ping Feed", { "TOPLEFT", "UIParent", "TOPLEFT", 330, -200 })
	E.currentModule = previous
	M:LayoutPingFeed()
	return feed
end

-- Rows from the newest entry down; old rows fade during their last 3 s.
-- While rows are up and fade, the feed refreshes five times a second on
-- the shared ticker; an empty feed costs nothing.
local FEED_TICK = "Notifications:pingFeed"

local function FeedTicks(on)
	local ticker = E.Ticker
	if on then
		if not ticker:IsSubscribed(FEED_TICK) then
			ticker:Subscribe(FEED_TICK, 0.2, function() M:UpdatePingFeed() end, "Notifications")
		end
	else
		ticker:Unsubscribe(FEED_TICK)
	end
end

function M:UpdatePingFeed()
	if not feed then return end
	local db = self.db.pings
	local now = GetTime()
	local entries = feed.entries
	if db.fade > 0 then
		for index = #entries, 1, -1 do
			if now - entries[index].at > db.fade then table.remove(entries, index) end
		end
	end
	for index = 1, db.rows do
		local row = FeedRow(index)
		local entry = entries[index]
		if entry then
			row.time:SetText(entry.time)
			row.sender:SetText(entry.sender)
			row.sender:SetTextColor(entry.r, entry.g, entry.b)
			row.text:SetText(entry.text)
			local left = db.fade > 0 and (db.fade - (now - entry.at)) or 99
			row:SetAlpha(left < 3 and math.max(0, left / 3) or 1)
			row:Show()
		else
			row:Hide()
		end
	end
	feed:SetShown(#entries > 0)
	FeedTicks(#entries > 0 and db.fade > 0 and self.active)
end

function M:AddPing(text, sender, guid)
	if not feed then CreateFeed() end
	local db = self.db.pings
	local r, g, b = 1, 0.82, 0
	-- Class color only when the GUID is readable.
	if U.Safe(guid) and GetPlayerInfoByGUID then
		local ok, _, classFile = pcall(GetPlayerInfoByGUID, guid)
		local color = ok and E:ClassColorObject(classFile)
		if color then r, g, b = color.r, color.g, color.b end
	end
	-- sender and text go to SetText as they came, secret or not. A readable
	-- name loses its realm, so the name itself fits its column.
	if type(sender) == "string" and not U.Secret(sender) and Ambiguate then sender = Ambiguate(sender, "short") or sender end
	table.insert(feed.entries, 1, { at = GetTime(), time = E:FormatTime(nil, true), sender = Shown(sender), text = Shown(text), r = r, g = g, b = b })
	while #feed.entries > db.rows do table.remove(feed.entries) end
	if db.sound and db.soundID and db.soundID ~= "" then E:PlayMedia(db.soundID) end
	self:UpdatePingFeed()
end

U.On("CHAT_MSG_PING", function(_, text, sender, ...)
	local db = M.db.pings
	if not db.feed or not ContentAllowed() then return end
	M:AddPing(text, sender, (select(10, ...)))
end)

function M:ApplyPingFeed()
	local db = self.db.pings
	if self.active and db.feed then
		if not feed then CreateFeed() end
		self:LayoutPingFeed()
		self:UpdatePingFeed()
	elseif feed then
		wipe(feed.entries)
		feed:Hide()
		FeedTicks(false)
	end
end

-- Sample rows for placing the feed (/eui notify test pings).
M.tests.pings = function()
	local db = M.db.pings
	if not db.feed then
		E:Print(L["Turn on the ping feed first (Alerts and Banners > Pings)."])
		return
	end
	local name = UnitName("player") or L["You"]
	M:AddPing(L["Attack"], name, UnitGUID("player"))
	M:AddPing(L["On my way"], name, UnitGUID("player"))
	M:AddPing(L["Warning"], name, UnitGUID("player"))
end

---------------------------------------------------------------------------
-- Pingable icons: EldoUI frames that answer the game's ping key.
-- E:SetPingable(frame, info) gives `frame` the methods Blizzard's ping
-- manager asks for (GetIsPingable, GetAllowRadialWheel, GetTargetInfo);
-- info(frame) returns { spellID = n } or { itemID = n } or nil. The
-- frame becomes a ping receiver while the option is on. Only EldoUI's own
-- frames: nothing is written into Blizzard frames.
---------------------------------------------------------------------------
local pingables = setmetatable({}, { __mode = "k" })

local function PingableOn()
	return M.active and M.db.pings.pingableIcons
end

local function ApplyPingable(frame)
	if not frame.SetAttribute then return end
	if PingableOn() then
		frame:SetAttribute("ping-receiver", true)
	else
		frame:SetAttribute("ping-receiver", nil)
	end
end

function E:SetPingable(frame, info)
	if not (frame and frame.SetAttribute) or type(info) ~= "function" then return end
	pingables[frame] = info
	frame.GetIsPingable = function(button)
		local target = PingableOn() and pingables[button] and pingables[button](button)
		return type(target) == "table"
	end
	frame.GetAllowRadialWheel = function() return false end
	frame.GetTargetInfo = function(button)
		local target = pingables[button] and pingables[button](button)
		return type(target) == "table" and target or {}
	end
	ApplyPingable(frame)
end

function M:ApplyPingables()
	for frame in pairs(pingables) do ApplyPingable(frame) end
end

---------------------------------------------------------------------------
-- Ping keys: secure buttons with Blizzard's /pingspell or /pingitem.
---------------------------------------------------------------------------
local keyButtons = {}

E:NameBinding("BINDING_HEADER_ELDOUIPINGS", E.Key("EldoUI Pings"))
for index = 1, PING_KEYS do
	E:NameBinding(("BINDING_NAME_CLICK EldoUI_PingKey%d:LeftButton"):format(index), E.Key("Ping key %d (spell or item set in Alerts and Banners > Pings)"), index)
end

-- "Frost Nova", "122" or "item:6948" -> macro text, or nil.
function M.PingMacro(value)
	if type(value) ~= "string" then return nil end
	value = value:gsub("[\r\n/;%[%]]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if value == "" then return nil end
	local item = value:match("^[Ii]tem:%s*(.+)$")
	if item and item ~= "" then
		return (_G.SLASH_PING_ITEM1 or "/pingitem") .. " " .. item
	end
	return (_G.SLASH_PING_SPELL1 or "/pingspell") .. " " .. value
end

local function KeyButton(index)
	local button = keyButtons[index]
	if button then return button end
	button = CreateFrame("Button", "EldoUI_PingKey" .. index, UIParent, "SecureActionButtonTemplate")
	button:SetSize(1, 1)
	button:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:Hide()
	keyButtons[index] = button
	return button
end

function M:ApplyPingKeys()
	E:RunOutOfCombat(function()
		local db = self.db.pings
		for index = 1, PING_KEYS do
			local macro = (self.active and db.keys and M.PingMacro(db["keySpell" .. index])) or nil
			if macro or keyButtons[index] then
				local button = KeyButton(index)
				button:SetAttribute("type", macro and "macro" or nil)
				button:SetAttribute("macrotext", macro)
			end
		end
	end)
end

function M:ApplyPings()
	self:ApplyPingFeed()
	self:ApplyPingables()
	self:ApplyPingKeys()
end

U.OnEnable(function() M:ApplyPings() end)
U.OnDisable(function() M:ApplyPings() end)
U.OnProfile(function() M:ApplyPings() end)
