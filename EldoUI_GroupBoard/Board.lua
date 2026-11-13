-- EldoUI Group Board: the posts and the module.
--
-- Every line in the public channels the player watches (LookingForGroup,
-- General, Trade, and joined channels by name such as "World") goes
-- through Parse.Read. A group post is kept per sender, newest first, for a
-- set time (10 minutes by default); a sender who posts again replaces the
-- older post and moves it to the top. The window (Window.lua), the info bar
-- block and the notice read the same list through Board:Matching().
--
-- Filters: groups (LFM) and players (LFG); places that fit the character's
-- level; the roles a group needs or a player offers; dungeons, raids,
-- quests and the rest; a search over names, places and the text.
--
-- Rules (WoW: Forever): only chat lines the game hands to addons are read,
-- and a secret line is never read (while the game holds chat back from
-- addons, in boss fights, PvP matches or a chat lockdown, the window says
-- so). Nothing is sent: whisper and
-- invite are the player's clicks (the game's own whisper box and
-- C_PartyInfo.InviteUnit, out of combat). The notice is off by default and
-- stays quiet in combat. Posts live for the session only.
-- Written from scratch for this fork of EldoUI.
local addonName, ns = ...
local E = EldoUI
if not (E and E.apiVersion and E.apiVersion >= 1) then return end
local L = E.L
local Key = E.Key

local Catalog, Parse = ns.Catalog, ns.Parse
local Secret = E.Secret

local MAX_POSTS = 300
local TICK = "GroupBoardTick"
local LFG_ZONE_CHANNEL, GENERAL_ZONE_CHANNEL, TRADE_ZONE_CHANNEL = 26, 1, 2
-- The LookingForGroup channel by name, for clients that give no zone ID.
local LFG_NAMES = { lookingforgroup = true, suchenachgruppe = true, recherchedegroupe = true, buscargrupo = true,
	procurandogrupo = true, cercagruppo = true }

local M = E:NewModule("GroupBoard", {
	title = "Group Board",
	desc = "Collects group posts from the public chat channels in one window: who looks for which dungeon, which roles a group needs, how long ago.",
	plugin = addonName,
	defaults = {
		enabled = true,
		channels = { lfg = true, general = true, trade = false, custom = true },
		customNames = "World, Welt",
		keep = 10,                         -- minutes a post stays
		filter = { lfm = true, lfg = true, fit = true, tank = false, heal = false, dps = false,
			dungeon = true, raid = true, quest = true, other = true },
		notify = { on = false, chat = true, sound = "eldo:EldoChime" },
		window = {},
	},
})
ns.M = M

local Board = { posts = {}, hidden = {} }
ns.Board = Board
M.board = Board

local noticed = {} -- post key -> signature the notice told about

local function Now() return GetTime() end

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
end

local function Readable(value)
	if Secret(value) then return nil end
	return value
end

local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end

---------------------------------------------------------------------------
-- Channels
---------------------------------------------------------------------------
local customCache, customSource

local function CustomNames()
	local source = M.db and M.db.customNames or ""
	if customCache and customSource == source then return customCache end
	customCache, customSource = {}, source
	for part in tostring(source):gmatch("[^,;]+") do
		local name = Catalog.Fold(part)
		if name ~= "" then customCache[name] = true end
	end
	return customCache
end

-- "4. LookingForGroup" and "LookingForGroup" both give "lookingforgroup".
local function BareChannel(name)
	if type(name) ~= "string" or Secret(name) then return nil end
	name = name:gsub("^%d+%.%s*", ""):gsub("%s+%-%s+.*$", "")
	local folded = Catalog.Fold(name)
	return folded ~= "" and folded or nil
end
Board.BareChannel = BareChannel

-- Does the player watch this channel? zoneID, the base name and the shown
-- name come from CHAT_MSG_CHANNEL.
function Board:Watches(zoneID, baseName, channelName)
	local channels = M.db.channels
	zoneID = tonumber(Readable(zoneID))
	local bare = BareChannel(Readable(baseName)) or BareChannel(Readable(channelName))
	if zoneID == LFG_ZONE_CHANNEL or (bare and LFG_NAMES[bare:gsub(" ", "")]) then return channels.lfg == true end
	if zoneID == GENERAL_ZONE_CHANNEL then return channels.general == true end
	if zoneID == TRADE_ZONE_CHANNEL then return channels.trade == true end
	if zoneID and zoneID > 0 then return false end
	return channels.custom == true and bare ~= nil and CustomNames()[bare] == true
end

---------------------------------------------------------------------------
-- Posts
---------------------------------------------------------------------------
local function ShortName(sender)
	local short = Ambiguate and Readable(Try(Ambiguate, sender, "none")) or nil
	if type(short) ~= "string" or short == "" then short = sender:match("^([^%-]+)") or sender end
	return short
end

local function ClassOf(guid)
	guid = Readable(guid)
	if type(guid) ~= "string" or guid == "" or not GetPlayerInfoByGUID then return nil end
	local _, class = Try(GetPlayerInfoByGUID, guid)
	if type(class) == "string" and not Secret(class) and class ~= "" then return class end
end

-- What makes two posts of a sender the same post (a repeat, not news).
local function Signature(info)
	return info.kind .. "|" .. table.concat(info.places, ",") .. "|" .. Catalog.Fold(info.text)
end

-- Adds or refreshes a post. Returns the post and whether it is news (a new
-- sender, or a sender who now posts something else).
function Board:Add(sender, info, extra)
	extra = extra or {}
	local key = sender:lower()
	local post = self.posts[key]
	local signature = Signature(info)
	local news = not post or post.signature ~= signature
	if not post then
		post = { key = key, sender = sender, first = Now(), count = 0 }
		self.posts[key] = post
	end
	if news then post.first = Now() end
	post.name = ShortName(sender)
	post.class = extra.class or post.class
	post.channel = extra.channel or post.channel
	post.kind, post.category, post.places, post.maybe = info.kind, info.category, info.places, info.maybe
	post.roles, post.need, post.have, post.size = info.roles, info.need, info.have, info.size
	post.text, post.signature = info.text, signature
	post.last = Now()
	post.count = post.count + 1
	if news and self.hidden[key] and self.hidden[key] ~= signature then self.hidden[key] = nil end
	self:Trim()
	return post, news
end

function Board:Remove(key)
	self.posts[key] = nil
end

-- Hides a post until its sender posts something else.
function Board:Hide(post)
	if post then self.hidden[post.key] = post.signature end
	self:Changed()
end

function Board:Clear()
	wipe(self.posts)
	wipe(self.hidden)
	wipe(noticed)
	self:Changed()
end

-- Drops posts older than the set time, and the oldest past MAX_POSTS.
function Board:Trim()
	local keep = (tonumber(M.db and M.db.keep) or 10) * 60
	local now, count = Now(), 0
	for key, post in pairs(self.posts) do
		if now - post.last > keep then
			self.posts[key] = nil
			self.hidden[key] = nil
			noticed[key] = nil
		else
			count = count + 1
		end
	end
	if count <= MAX_POSTS then return end
	local list = {}
	for _, post in pairs(self.posts) do list[#list + 1] = post end
	table.sort(list, function(a, b) return a.last > b.last end)
	for index = MAX_POSTS + 1, #list do self.posts[list[index].key] = nil end
end

function Board:Count()
	local count = 0
	for _ in pairs(self.posts) do count = count + 1 end
	return count
end

---------------------------------------------------------------------------
-- Filters
---------------------------------------------------------------------------
local ROLES = { "tank", "heal", "dps" }
Board.ROLES = ROLES
local CATEGORY_CHIP = { dungeon = "dungeon", raid = "raid", quest = "quest", pvp = "other", other = "other" }

local function PlayerLevel()
	local level = Try(UnitLevel, "player")
	if Secret(level) then return nil end
	return tonumber(level)
end

local function AnyOn(filter, keys)
	for _, key in ipairs(keys) do
		if filter[key] then return true end
	end
	return false
end

-- The places a post may mean: its places, and the other reading of a bare
-- "DM" (Dire Maul).
local function PostPlaces(post)
	local places = post.places or {}
	if not post.maybe then return places end
	local list = { unpack(places) }
	list[#list + 1] = post.maybe
	return list
end

-- Place names, folded, for the search.
local function PlaceText(post)
	local names = {}
	for _, key in ipairs(PostPlaces(post)) do
		local entry = Catalog:Get(key)
		names[#names + 1] = Catalog:Name(key)
		if entry then
			names[#names + 1] = entry.en
			if entry.de then names[#names + 1] = entry.de end
			if entry.client then names[#names + 1] = entry.client end
		end
	end
	return Catalog.Fold(table.concat(names, " "))
end

-- Does a post pass the filters? search is folded text or nil.
function Board:Passes(post, filter, search, level)
	if self.hidden[post.key] == post.signature then return false end
	if AnyOn(filter, { "lfm", "lfg" }) and not filter[post.kind] then return false end
	local categories = { "dungeon", "raid", "quest", "other" }
	if AnyOn(filter, categories) and not filter[CATEGORY_CHIP[post.category] or "other"] then return false end
	if filter.fit and level and #post.places > 0 then
		local fits = false
		for _, key in ipairs(PostPlaces(post)) do
			if Catalog:Fits(key, level) then fits = true end
		end
		if not fits then return false end
	end
	-- Roles: a group that needs one of them (or names none), a player who
	-- offers one of them (or names none).
	if AnyOn(filter, ROLES) and post.roles then
		local any = false
		for _, role in ipairs(ROLES) do
			if filter[role] and post.roles[role] then any = true end
		end
		if not any then return false end
	end
	if search and search ~= "" then
		local haystack = Catalog.Fold(post.name or "") .. " " .. PlaceText(post) .. " " .. Catalog.Fold(post.text or "")
		if not haystack:find(search, 1, true) then return false end
	end
	return true
end

-- The posts the filters let through, newest first.
function Board:Matching(search)
	self:Trim()
	local filter = M.db.filter
	local folded = search and Catalog.Fold(search) or nil
	local level = PlayerLevel()
	local list = {}
	for _, post in pairs(self.posts) do
		if self:Passes(post, filter, folded, level) then list[#list + 1] = post end
	end
	table.sort(list, function(a, b)
		if a.last ~= b.last then return a.last > b.last end
		return a.key < b.key
	end)
	return list
end

---------------------------------------------------------------------------
-- Texts shared by the window, the block and the notice
---------------------------------------------------------------------------
local ROLE_LABELS = { tank = Key("Tank"), heal = Key("Healer"), dps = Key("Damage") }
Board.ROLE_LABELS = ROLE_LABELS

function Board.PlacesText(post, limit)
	local places = post.places or {}
	if #places == 0 then
		if post.category == "quest" then return L["Quests"] end
		if post.category == "raid" then return L["Raid"] end
		if post.category == "pvp" then return L["PvP"] end
		return L["Group"]
	end
	if post.maybe and #places == 1 then
		return L["%s or %s"]:format(Catalog:Name(places[1]), Catalog:Name(post.maybe))
	end
	limit = limit or 2
	local names = {}
	for index = 1, math.min(#places, limit) do names[index] = Catalog:Name(places[index]) end
	local text = table.concat(names, ", ")
	if #places > limit then text = text .. " " .. L["+%d more"]:format(#places - limit) end
	return text
end

-- "Tank, Healer" (with counts: "2 Damage"), or "".
function Board.RolesText(post)
	if not post.roles then return "" end
	local parts = {}
	for _, role in ipairs(ROLES) do
		local value = post.roles[role]
		if value then
			local label = L[ROLE_LABELS[role]]
			parts[#parts + 1] = type(value) == "number" and value > 1 and ("%d %s"):format(value, label) or label
		end
	end
	return table.concat(parts, ", ")
end

-- "Group, needs 2: Tank, Healer" / "Player: Healer" — the line under the name.
function Board.WhatText(post)
	local roles = Board.RolesText(post)
	if post.kind == "lfm" then
		if post.need and roles ~= "" then return L["Group, needs %d: %s"]:format(post.need, roles) end
		if post.need then return L["Group, needs %d"]:format(post.need) end
		if roles ~= "" then return L["Group, needs %s"]:format(roles) end
		return L["Group"]
	end
	if roles ~= "" then return L["Player: %s"]:format(roles) end
	return L["Player"]
end

function Board.AgeText(post)
	local minutes = math.floor((Now() - (post.last or Now())) / 60)
	if minutes < 1 then return L["just now"] end
	return L["%d min ago"]:format(minutes)
end

function Board.NameText(post)
	local name = post.name or post.sender or "?"
	if post.class then return E:WrapClassColor(post.class, name) end
	return name
end

-- True while the game holds chat back from addons (boss fights, PvP
-- matches, a chat lockdown: E:CommRestricted), so the list may stay empty.
function Board.Hidden()
	return E.CommRestricted and E:CommRestricted() or false
end

---------------------------------------------------------------------------
-- The player's clicks
---------------------------------------------------------------------------
function Board:Whisper(post)
	if not (post and post.sender) then return false end
	local util = rawget(_G, "ChatFrameUtil")
	local tell = util and util.SendTell or rawget(_G, "ChatFrame_SendTell")
	if type(tell) ~= "function" then return false end
	return pcall(tell, post.sender)
end

-- One invite through the game's own call; never in combat.
function Board:Invite(post)
	if not (post and post.sender) or InCombat() then return false, "combat" end
	local party = C_PartyInfo
	local invite = party and party.InviteUnit or rawget(_G, "InviteUnit")
	if type(invite) ~= "function" then return false, "unavailable" end
	return pcall(invite, post.sender), nil
end

---------------------------------------------------------------------------
-- Changes and the notice
---------------------------------------------------------------------------
local pending = false
function Board:Changed()
	if pending then return end
	pending = true
	C_Timer.After(0.5, function()
		pending = false
		if ns.Window then ns.Window:Refresh() end
		local bar = E:GetModule("InfoBar")
		if bar and bar.active and bar.RefreshDataText then pcall(bar.RefreshDataText, bar, "GroupBoard") end
	end)
end

function Board:Notice(post)
	local notify = M.db.notify
	if not notify.on or InCombat() or post.kind ~= "lfm" then return end
	if noticed[post.key] == post.signature then return end
	if not self:Passes(post, M.db.filter, nil, PlayerLevel()) then return end
	noticed[post.key] = post.signature
	if notify.chat then
		local what = Board.WhatText(post)
		E:Print(L["Group board: %s for %s (%s)."]:format(Board.NameText(post), Board.PlacesText(post), what))
	end
	if notify.sound and notify.sound ~= "none" and E.PlayMedia then E:PlayMedia(notify.sound) end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- CHAT_MSG_CHANNEL: text, sender, language, channel, target, flags,
-- zone channel ID, channel index, channel base name, language ID, line
-- ID, guid.
function Board:OnChannelLine(text, sender, _, channelName, _, _, zoneID, _, baseName, _, _, guid)
	if Secret(text) or Secret(sender) or type(text) ~= "string" or type(sender) ~= "string" or sender == "" then return end
	if E.IsMe and E:IsMe(sender) then return end
	if not self:Watches(zoneID, baseName, channelName) then return end
	local info = Parse.Read(text)
	if not info then return end
	local channel = Readable(baseName) or Readable(channelName)
	if type(channel) == "string" then channel = channel:gsub("^%d+%.%s*", ""):gsub("%s+%-%s+.*$", "") end
	local post, news = self:Add(sender, info, { class = ClassOf(guid), channel = channel })
	if news then self:Notice(post) end
	self:Changed()
end

function M:OnEnable()
	self:RegisterEvent("CHAT_MSG_CHANNEL", function(_, _, ...) Board:OnChannelLine(...) end)
	self:RegisterEvent("LFG_UPDATE_RANDOM_INFO", function() Catalog:ReadClient() end)
	self:RegisterEvent("PLAYER_LEVEL_UP", function() Board:Changed() end)
	Catalog:ReadClient()
	E.Ticker:Subscribe(TICK, 15, function()
		Board:Trim()
		Board:Changed()
	end, self)
end

function M:OnDisable()
	E.Ticker:Unsubscribe(TICK)
	wipe(Board.posts)
	wipe(Board.hidden)
	wipe(noticed)
	if ns.Window then ns.Window:Close() end
end

function M:OnProfileChanged()
	customCache = nil
	Board:Changed()
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local function Open()
	if not M.active then
		E:Print(L["The group board is off. Turn it on on the Plugins page."])
		return
	end
	if ns.Window then ns.Window:Open() end
end

M.options = {
	{ type = "execute", label = "Open the group board", func = Open,
		desc = "Opens the board window. /eui board and the Group board block on the info bar open it too." },
	{ type = "header", label = "Channels" },
	{ type = "toggle", key = "channels.lfg", label = "LookingForGroup channel",
		desc = "Reads group posts in the LookingForGroup channel, when you have joined it." },
	{ type = "toggle", key = "channels.general", label = "General channel",
		desc = "Reads group posts in the General channel of the zone you are in." },
	{ type = "toggle", key = "channels.trade", label = "Trade channel",
		desc = "Reads group posts in the Trade channel of the city you are in." },
	{ type = "toggle", key = "channels.custom", label = "Other channels by name",
		desc = "Reads group posts in joined channels whose names you list below, such as World." },
	{ type = "input", key = "customNames", label = "Channel names", dependsOn = "channels.custom",
		desc = "Names of joined channels to read, separated by commas. Upper and lower case don't matter." },
	{ type = "header", label = "Posts" },
	{ type = "range", key = "keep", label = "Minutes a post stays", min = 2, max = 30, step = 1,
		desc = "A post leaves the board this many minutes after its sender last posted it." },
	{ type = "header", label = "Notice" },
	{ type = "toggle", key = "notify.on", label = "Tell me about new groups",
		desc = "A chat line and a sound when a new group post passes the board's filters. Never in combat." },
	{ type = "toggle", key = "notify.chat", label = "Chat line", dependsOn = "notify.on",
		desc = "One line in your chat window with the sender, the place and the roles the group needs." },
	{ type = "media", key = "notify.sound", label = "Sound", mediaKind = "sound", none = true, dependsOn = "notify.on",
		desc = "The sound for a new group post. None plays nothing." },
}

---------------------------------------------------------------------------
-- Command, info bar block, Finder, diagnostics, other addons
---------------------------------------------------------------------------
E:AddCommand("board", "open or close the group board", function()
	if not M.active then
		E:Print(L["The group board is off. Turn it on on the Plugins page."])
		return
	end
	if ns.Window then ns.Window:Toggle() end
end)

if E.RegisterDataText then
	E:RegisterDataText("GroupBoard", {
		title = "Group board",
		label = "LFG",
		icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
		poll = true,
		interval = 15,
		text = function()
			if not M.active then return E:TextHex("secondary") .. L["Off"] .. "|r" end
			local groups = 0
			for _, post in ipairs(Board:Matching()) do
				if post.kind == "lfm" then groups = groups + 1 end
			end
			return E:Plural(groups, "%d group", "%d groups"):format(groups)
		end,
		tooltip = function(tooltip)
			local Kit = E.UIKit
			if not M.active then
				Kit.TipText(tooltip, L["The group board is off. Turn it on on the Plugins page."])
				return
			end
			local list = Board:Matching()
			if #list == 0 then
				Kit.TipText(tooltip, Board.Hidden() and L["The game holds chat back from addons right now, in boss fights for example."]
					or L["No group posts that pass your filters yet."])
				return
			end
			for index = 1, math.min(#list, 8) do
				local post = list[index]
				tooltip:AddDoubleLine(Board.NameText(post), Board.PlacesText(post, 1), 1, 1, 1, 1, 1, 1)
			end
			if #list > 8 then Kit.TipText(tooltip, E:Plural(#list - 8, "and %d more", "and %d more"):format(#list - 8)) end
		end,
		hint = function() return { L["Click"], L["open the group board"] } end,
		onClick = function() if M.active and ns.Window then ns.Window:Toggle() end end,
	})
end

if E.RegisterFinderProvider then
	E:RegisterFinderProvider("groupboard", function()
		if not M.active then return {} end
		return { { id = "groupboard:open", text = L["Group board"], sub = L["Group posts from chat"],
			icon = "Interface\\Icons\\INV_Misc_GroupNeedMore", open = Open } }
	end, { label = "Group board", order = 80 })
end

if E.RegisterDiagnostics then
	E:RegisterDiagnostics("GroupBoard", function()
		local channels = {}
		for _, key in ipairs({ "lfg", "general", "trade", "custom" }) do
			if M.db and M.db.channels[key] then channels[#channels + 1] = key end
		end
		local client = 0
		for _, key in ipairs(Catalog.order) do
			if Catalog:Get(key).client then client = client + 1 end
		end
		return { ("   Group Board: %d posts, channels %s, %d places known, %d named by the client"):format(Board:Count(),
			#channels > 0 and table.concat(channels, ",") or "none", #Catalog.order, client) }
	end)
end

-- LFG Bulletin Board reads the same channels into its own window: both can
-- run side by side.
if E.RegisterCompetitor then
	E:RegisterCompetitor({ addon = "GroupBulletinBoard", module = "GroupBoard", scope = "alongside", covers = "part",
		note = "LFG Bulletin Board lists chat group posts in its own window." })
end
