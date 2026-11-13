-- EldoUI Instant Messages (EIM): whispers and Battle.net whispers open in
-- their own small chat windows, like an instant messenger. Guild, officer,
-- party, raid and instance chat can get a window of their own too (each one
-- opt-in). A dock lists every conversation with unread counts, each
-- whisper window shows who the contact is (the name in the class color,
-- level, race and class, zone, friend or guild rank), and the history
-- browser (/eui eim) lists every saved conversation with search and
-- delete. A whisper window's title bar has buttons for the contact:
-- invite, add friend, who, ignore and the saved conversation. Each one is
-- your click and calls the game's own function once (C_PartyInfo,
-- C_FriendList); ignore asks first.
--
-- Windows take their theme from the active layout preset (accent color,
-- font and frame style) unless a theme is picked.
--
-- Midnight rule: some chat text is a "secret value" during encounters.
-- EIM only displays it and never reads, stores or compares it. A whisper
-- whose sender is secret stays in the main chat.
-- Reply (R and /r): an incoming whisper still goes through Blizzard's chat
-- frame in full, so the game itself sets the reply target, plays its
-- whisper sound and flashes the taskbar icon. EIM then takes only the
-- visible line out of the chat window, through the frame's secure
-- RemoveMessagesByPredicate. EIM never writes the reply target, so
-- R, /r and the chat edit box stay untainted.
-- EIM never sends anything by itself: a line goes out only when you press
-- Enter in a window.
-- Written from scratch for EldoUI; no code or media from other addons.
local _, E = ...
local L = E.L

local M = E:NewModule("Messages", {
	title = "Instant Messages",
	desc = "Whispers (and, if you like, guild and group chat) in their own messenger windows, with contact info and a history browser.",
	conflicts = { "WIM" },
	category = "Chat & Social",
	frames = { "EldoUI_EIM" },
	movers = { "EldoUI_EIM" },
	blizzard = {},
	savedKeys = { "profile.modules.Messages" },
	optionsPage = "module:Messages",
	presets = { "Classic", "Compact", "Glass", "Messenger", "PopUp", "Quiet", "Social" },
	reload = false,
	defaults = {
		theme = "auto",         -- auto (follows the layout preset), Eldo, Glass, Blizzard (art-style panel)
		hideFromChat = true,    -- whispers only show in EIM
		openOnReceive = "window", -- window (out of combat; after the fight when one arrives in combat), dock (open on click)
		openOnSend = true,
		timestamps = true,
		width = 340,
		height = 220,
		history = 50,           -- lines kept per contact, per character
		fontSize = 14,
		contactInfo = true,     -- the info line under a whisper window's title
		contactButtons = true,  -- invite, add friend, who, ignore and history in a whisper window's title bar
		dockSize = 8,           -- buttons shown in the dock
		-- Group windows (each opt-in)
		groups = { guild = false, officer = false, party = false, raid = false, instance = false },
		groupHideFromChat = false,
		groupHistory = false,
	},
})

-- Presets that look best with a particular theme. Other presets use Eldo.
local PRESET_THEMES = {
	EldoBlizz1000 = "Blizzard", EldoZen1000 = "Glass", EldoCozy1000 = "Glass", EldoHeritage2000 = "Blizzard",
	EldoClassic = "Blizzard", EldoBlizz = "Blizzard", EldoHeritage = "Blizzard",
	EldoZen = "Glass", EldoCozy = "Glass", EldoViolet = "Glass",
}

local THEMES = {
	Eldo = { alpha = 0.92, border = "accent" },
	Glass = { alpha = 0.55, border = "none" },
	Blizzard = { border = "panel" }, -- E:SetPanelTemplate: follows the art style
}

-- Group conversations: window key -> chat events, send type and title.
local GROUPS = {
	guild = { key = "CH:GUILD", title = GUILD or L["Guild"], chatType = "GUILD", events = { "CHAT_MSG_GUILD" } },
	officer = { key = "CH:OFFICER", title = OFFICER or L["Officer"], chatType = "OFFICER", events = { "CHAT_MSG_OFFICER" } },
	party = { key = "CH:PARTY", title = PARTY or L["Party"], chatType = "PARTY", events = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER" } },
	raid = { key = "CH:RAID", title = RAID or L["Raid"], chatType = "RAID",
		events = { "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING" } },
	instance = { key = "CH:INSTANCE", title = INSTANCE_CHAT or L["Instance"], chatType = "INSTANCE_CHAT",
		events = { "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" } },
}
local GROUP_ORDER = { "guild", "officer", "party", "raid", "instance" }
local EVENT_GROUP = {}
for group, def in pairs(GROUPS) do
	for _, event in ipairs(def.events) do EVENT_GROUP[event] = group end
end

local WHISPER_EVENTS = { "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM" }
local INCOMING = { CHAT_MSG_WHISPER = true, CHAT_MSG_BN_WHISPER = true }
local SENT = { CHAT_MSG_WHISPER_INFORM = true, CHAT_MSG_BN_WHISPER_INFORM = true }
local BNET = { CHAT_MSG_BN_WHISPER = true, CHAT_MSG_BN_WHISPER_INFORM = true }

local windows = {}   -- contact key -> window
local order = {}     -- contact keys, newest first
M.windows = windows  -- read-only for plugins

local IsSecret = E.Secret
local Key = E.Key

local Readable = E.Plain

local function ThemeName()
	local theme = M.db.theme
	if theme == "auto" then theme = PRESET_THEMES[E.db.general.layout] or "Eldo" end
	return THEMES[theme] and theme or "Eldo"
end

---------------------------------------------------------------------------
-- Saved conversations: EldoUIMessagesDB (per character, see
-- E:GetMessagesDB in ChatMessages.lua). contacts[key] is a list of
-- { time, incoming (1/0), text }; meta[key] = { title, class, last, battleTag,
-- guid } (guid: the contact's character, so a reopened window knows it).
---------------------------------------------------------------------------
local function Store()
	local db = E:GetMessagesDB()
	db.meta = db.meta or {}
	return db
end

local function History(key)
	local contacts = Store().contacts
	contacts[key] = contacts[key] or {}
	return contacts[key]
end

local function Meta(key)
	local meta = Store().meta
	meta[key] = meta[key] or {}
	return meta[key]
end

local function IsGroupKey(key)
	return key:find("^CH:") ~= nil
end

local function KeepHistory(key)
	if M.db.history <= 0 then return false end
	return not IsGroupKey(key) or M.db.groupHistory
end

---------------------------------------------------------------------------
-- Styling
---------------------------------------------------------------------------
local function StyleFrame(frame)
	local name = ThemeName()
	local theme = THEMES[name]
	local r, g, b = unpack(E.media.accentColor)
	if theme.border == "panel" then
		-- The art style's own panel (Modern, Blizzard, Classic, WoW Forever).
		E:SetPanelTemplate(frame)
	else
		-- Leaving the panel theme: no longer re-skinned on art style changes.
		if E.panels[frame] then
			E.panels[frame] = nil
			E:SetStyleEdge(frame, false)
			if E.UpdateShadow then E:UpdateShadow(frame, false) end
		end
		E:SetTemplate(frame)
		local br, bg, bb = unpack(E.media.backdropColor)
		frame:SetBackdropColor(br, bg, bb, theme.alpha)
		if theme.border == "accent" then
			frame:SetBackdropBorderColor(r, g, b, 1)
		else
			frame:SetBackdropBorderColor(0, 0, 0, 0.6)
		end
	end
	if frame.titleBar then frame.titleBar:SetColorTexture(r, g, b, theme.border == "panel" and 0 or 0.25) end
end

-- The kit's size grip (E.UIKit.SizeGrip): three short lines in the
-- secondary gray, accent on hover (no game texture).
local function SizeGrip(window)
	return E.UIKit.SizeGrip(window, { resize = true, size = 14, minWidth = 240, minHeight = 140, maxWidth = 800, maxHeight = 600 })
end

-- A flat input box in the name font of the theme font (conversation windows).
local function FlatInput(parent, size)
	local input = CreateFrame("EditBox", nil, parent)
	input:SetAutoFocus(false)
	-- What the player writes to another player, in the name font.
	E:SetNameTextFont(input, size)
	input:SetTextInsets(6, 6, 0, 0)
	E:SetTemplate(input)
	input:SetScript("OnEscapePressed", input.ClearFocus)
	input:SetScript("OnEditFocusGained", function(box) box:SetBackdropBorderColor(unpack(E.media.accentColor)) end)
	input:SetScript("OnEditFocusLost", function(box) box:SetBackdropBorderColor(unpack(E.media.borderColor)) end)
	return input
end

---------------------------------------------------------------------------
-- Contact info: who is this? The name in the class color, then level,
-- race and class, zone, and whether they are a friend or in your guild,
-- from what the game already lists. Nothing is asked of the server.
---------------------------------------------------------------------------
local function GuildEntry(name)
	if not IsInGuild() or not GetNumGuildMembers then return end
	for index = 1, GetNumGuildMembers() do
		local full, rank, _, level, className, zone, _, _, online, _, class = GetGuildRosterInfo(index)
		full = Readable(full)
		if full and Ambiguate(full, "none") == name then
			return { rank = Readable(rank), level = Readable(level), zone = Readable(zone), online = Readable(online),
				className = Readable(className), class = Readable(class) }
		end
	end
end

local function FriendEntry(name)
	if not (C_FriendList and C_FriendList.GetFriendInfo) then return end
	local info = C_FriendList.GetFriendInfo(name)
	if type(info) == "table" then
		return { level = Readable(info.level), className = Readable(info.className), zone = Readable(info.area),
			online = Readable(info.connected), note = Readable(info.notes) }
	end
end

-- The plain, non-empty texts among the values given, joined with the
-- separator. A missing value anywhere in the list is skipped, so a
-- contact without a known level still shows race and class.
local function Join(separator, ...)
	local list = {}
	for index = 1, select("#", ...) do
		local part = select(index, ...)
		if not IsSecret(part) and type(part) == "string" and part ~= "" then list[#list + 1] = part end
	end
	return table.concat(list, separator)
end

-- Levels seen this session, by GUID: from the friends list, the guild
-- roster, the chat's own level list, or a unit the game shows (your
-- group, target, focus, mouse-over or a nameplate). Never saved.
local seenLevels = {}

local function PlainLevel(level)
	level = Readable(level)
	if type(level) == "number" and level > 0 then return level end
end

-- The level of the unit with this GUID while the game shows that unit.
local function UnitLevelByGUID(guid)
	if type(guid) ~= "string" or not (UnitTokenFromGUID and UnitLevel) then return end
	local unit = E.PlainCall(UnitTokenFromGUID, guid)
	if type(unit) ~= "string" then return end
	return PlainLevel(E.PlainCall(UnitLevel, unit))
end

-- The level the chat keeps for its own name labels (when that is on).
local function ChatLevel(guid, name)
	local chat = E.modules and E.modules.Chat
	if not (chat and chat.LevelOf) then return end
	local ok, level = pcall(chat.LevelOf, chat, guid, name)
	return ok and PlainLevel(level) or nil
end

-- Class, localized class and race of a player GUID, when the game has them.
local function GUIDInfo(guid)
	guid = Readable(guid)
	if type(guid) ~= "string" or not GetPlayerInfoByGUID then return end
	local className, class, race = E.PlainCallEach(GetPlayerInfoByGUID, guid)
	return class, className, race
end

local function ClassColor(guid, fallbackClass)
	local class = GUIDInfo(guid)
	return E:ClassColorObject(class) or E:ClassColorObject(fallbackClass)
end

local function ClassHex(guid)
	local color = ClassColor(guid)
	return color and color:GenerateHexColor():sub(3) or nil
end

-- A whisper window's title in the contact's class color (it also colors
-- the contact's name in the lines). Group and Battle.net windows, and a
-- contact whose class the game has not given, keep the kit's title color.
local function ColorTitle(window, fallbackClass)
	local color
	if not (window.group or window.bnetID) then
		color = ClassColor(window.guid, fallbackClass)
		if color then window.color = color:GenerateHexColor():sub(3) end
	end
	if color then
		window.title:SetTextColor(color.r, color.g, color.b)
	else
		E.UIKit.Paint(window.title, "title")
	end
end

local function PlayerInfoText(window)
	local name = window.key
	local guid = window.guid
	local friend = FriendEntry(name)
	local guild = GuildEntry(name)
	local level = PlainLevel(friend and friend.level) or PlainLevel(guild and guild.level)
		or UnitLevelByGUID(guid) or ChatLevel(guid, window.target or name)
	if type(guid) == "string" then
		if level then seenLevels[guid] = level else level = seenLevels[guid] end
	end
	local _, className, race = GUIDInfo(guid)
	className = className or (friend and friend.className) or (guild and guild.className)
	local who = Join(" ", level and L["Level %d"]:format(level), race, className)
	local note = friend and friend.note
	return Join(" · ", who,
		(friend and friend.zone) or (guild and guild.zone),
		friend and (friend.online and L["Friend"] or L["Friend (offline)"]),
		guild and (guild.rank and L["Guild: %s"]:format(guild.rank) or L["Guild"]),
		type(note) == "string" and note ~= "" and ('"' .. note .. '"')), guild and guild.class
end

local function BNetInfoText(window)
	if not (window.bnetID and C_BattleNet and C_BattleNet.GetAccountInfoByID) then return "" end
	local info = C_BattleNet.GetAccountInfoByID(window.bnetID)
	if type(info) ~= "table" then return "" end
	local character, who, place, status
	local game = info.gameAccountInfo
	if type(game) == "table" and Readable(game.isOnline) and Readable(game.characterName) then
		local level = PlainLevel(game.characterLevel)
		character = Readable(game.characterName)
		who = Join(" ", level and L["Level %d"]:format(level), Readable(game.raceName), Readable(game.className))
		place = Readable(game.areaName) or Readable(game.richPresence)
	elseif Readable(info.isAFK) or Readable(info.isDND) then
		status = Readable(info.isDND) and L["Busy"] or L["Away"]
	end
	local note = Readable(info.note)
	return Join(" · ", character, who, place, status, type(note) == "string" and note ~= "" and ('"' .. note .. '"'))
end

function M:UpdateInfo(window)
	if not window.info then return end
	local text, guildClass = "", nil
	if not (window.group or window.bnetID) then
		-- The guild roster also gives a class for the title color.
		local ok, result, class = pcall(PlayerInfoText, window)
		if ok and type(result) == "string" then text, guildClass = result, class end
	elseif window.bnetID then
		local ok, result = pcall(BNetInfoText, window)
		if ok and type(result) == "string" then text = result end
	end
	ColorTitle(window, guildClass)
	self:UpdateContactButtons(window)
	if not self.db.contactInfo then text = "" end
	window.info:SetText(text)
	window.info:SetShown(text ~= "")
	self:LayoutWindow(window)
end

---------------------------------------------------------------------------
-- Conversation windows
---------------------------------------------------------------------------
local function Timestamp()
	return M.db.timestamps and (E:TextHex("secondary") .. "%s|r "):format(E:FormatTime()) or ""
end

-- A Battle.net contact is saved under its BattleTag: the account name the
-- game gives addons is only valid in this session.
local function StoreLine(key, incoming, text, title)
	if not KeepHistory(key) then return end
	local history = History(key)
	table.insert(history, { time(), incoming and 1 or 0, E.MaskProtectedNames(text) })
	while #history > M.db.history do table.remove(history, 1) end
	local meta = Meta(key)
	meta.last = time()
	if key:find("^BN:") then
		meta.title = key:sub(4)
	elseif title then
		meta.title = E.MaskProtectedNames(title)
	end
end

-- who: the name to show (nil = you), colorHex: rrggbb for the name.
local function AddLine(window, who, text, incoming, colorHex, store)
	local r, g, b = 1, 1, 1
	local secretName = IsSecret(who)
	local name
	if type(who) == "nil" then
		name = E:TextHex("secondary") .. (YOU or L["You"]) .. "|r: "
	elseif not secretName then
		name = ("|cff%s%s|r: "):format(colorHex or "ff80ff", who)
	end
	if IsSecret(text) or secretName then
		-- Secret text or names can be shown but not joined with other strings.
		if name then window.messages:AddMessage(Timestamp() .. name, r, g, b) end
		if secretName then window.messages:AddMessage(who, 1, 0.5, 1) end
		window.messages:AddMessage(text, r, g, b)
		return
	end
	window.messages:AddMessage(Timestamp() .. (name or "") .. text, r, g, b)
	if store then
		-- Group lines keep the speaker; your own lines are marked by incoming = 0.
		local saved = (window.group and who) and (who .. ": " .. text) or text
		StoreLine(window.key, incoming, saved, window.title:GetText())
	end
end

-- The player's typed line. Returns false when the game did not take it
-- (chat restricted, or no way to send), so the line stays in the box.
local function Send(window, text)
	if type(text) ~= "string" or strtrim(text) == "" then return true end
	local ok
	if window.group then
		ok = E:TryChatPost(text, window.group.chatType)
	elseif window.bnetID then
		local send = C_BattleNet and C_BattleNet.SendWhisper or BNSendWhisper
		ok = type(send) == "function" and not E:CommRestricted() and pcall(send, window.bnetID, text)
	elseif window.target then
		ok = E:TryChatPost(text, "WHISPER", nil, window.target)
	else
		return true
	end
	if not ok then
		window.messages:AddMessage(E:ChatRefusedText(), E:TokenColor("warn"))
		return false
	end
	return true
end

function M:LayoutWindow(window)
	window.messages:ClearAllPoints()
	if window.info:IsShown() then
		window.messages:SetPoint("TOPLEFT", window.info, "BOTTOMLEFT", -2, -4)
	else
		window.messages:SetPoint("TOPLEFT", window.titleBar, "BOTTOMLEFT", 4, -4)
	end
	window.messages:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -10, 36)
end

local function SaveWindowPoint(window)
	local point, _, relPoint, x, y = window:GetPoint(1)
	if point then M.db.lastPoint = { point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5) } end
end

-- Earlier messages with this contact, from the saved history.
local function LoadHistory(window, key)
	local messages = window.messages
	local saved = Store().contacts[key]
	if type(saved) == "table" and #saved > 0 then
		for _, line in ipairs(saved) do
			if type(line) == "table" and type(line[3]) == "string" then
				local mine = line[2] ~= 1
				messages:AddMessage((E:TextHex("dim") .. "%s|r %s%s"):format(E:ShortDate(line[1] or 0),
					mine and E:TextHex("secondary") .. "> |r" or "", line[3]), mine and 0.6 or 0.85, mine and 0.6 or 0.6, mine and 0.6 or 0.85)
			end
		end
		messages:AddMessage(E:TextHex("dim") .. "-- " .. L["earlier"] .. " --|r", 0.5, 0.5, 0.5)
	end
end

-- Windows of closed conversations wait here; the next conversation takes
-- one and clears it, so a busy session keeps a few windows, not one per
-- contact.
M.freeWindows = {}
local function ReuseWindow(key, title)
	local window = table.remove(M.freeWindows)
	if not window then return nil end
	window.key = key
	window.unread, window.openAfterCombat = 0, nil
	window.bnetID, window.target, window.guid, window.group, window.color = nil, nil, nil, nil, nil
	window.messages:Clear()
	window.input:SetText("")
	window.info:SetText("")
	window.info:Hide()
	window.title:SetText(not IsSecret(title) and title or "")
	ColorTitle(window)
	StyleFrame(window)
	E:SetHeaderFont(window.title, 15)
	E:SetNameTextFont(window.info, E.tokens.size.small)
	E:SetNameTextFont(window.messages, M.db.fontSize)
	E:SetNameTextFont(window.input, M.db.fontSize)
	M:LayoutWindow(window)
	LoadHistory(window, key)
	window:Hide()
	windows[key] = window
	table.insert(order, 1, key)
	return window
end

-- A closed conversation (right-click on its dock button) leaves the dock
-- and gives its window to the next one. Its saved history stays.
local function ReleaseWindow(key)
	local window = windows[key]
	if not window then return end
	window.openAfterCombat = nil
	window:Hide()
	windows[key] = nil
	for index, k in ipairs(order) do
		if k == key then table.remove(order, index) break end
	end
	window.key = nil
	window.messages:Clear()
	M.freeWindows[#M.freeWindows + 1] = window
end
M.ReleaseWindow = ReleaseWindow

---------------------------------------------------------------------------
-- Contact buttons: invite, add friend, who, ignore and the saved
-- conversation, right of the title of a whisper window. Every button is
-- one click of yours and one call of the game's own function; nothing is
-- sent on its own. A Battle.net window keeps only the history button, a
-- group window none.
---------------------------------------------------------------------------
local CONTACT_BUTTON = 18

local function ContactName(window)
	local name = window.target or window.key
	if IsSecret(name) or type(name) ~= "string" or name == "" or IsGroupKey(name) or name:find("^BN:") then return nil end
	return name
end

local function InGroupWith(name)
	for _, check in ipairs({ UnitInParty, UnitInRaid }) do
		if type(check) == "function" then
			local ok, result = pcall(check, name)
			if ok and not IsSecret(result) and result then return true end
		end
	end
	return false
end

local function Notice(window, text, warn)
	if E.UIKit.Toast then E.UIKit.Toast(window, text, { warn = warn }) end
end

local CONTACT_ACTIONS = {
	{ key = "invite", art = "profile", tipTitle = Key("Invite"), tip = Key("Invites this player to your group."),
		onClick = function(window)
			local name = ContactName(window)
			local party = C_PartyInfo
			if not (name and party and party.InviteUnit) then return end
			local ok = pcall(party.InviteUnit, name)
			Notice(window, ok and L["Group invite sent to %s."]:format(name) or L["The game did not invite %s."]:format(name), not ok)
		end },
	{ key = "friend", art = "Interface\\Buttons\\UI-PlusButton-Up", mono = true, tipTitle = Key("Add friend"),
		tip = Key("Adds this player to your WoW friends list."),
		onClick = function(window)
			local name = ContactName(window)
			if not (name and C_FriendList and C_FriendList.AddFriend) then return end
			if InCombatLockdown() then
				Notice(window, L["Add friends after combat."], true)
				return
			end
			local ok = pcall(C_FriendList.AddFriend, name)
			Notice(window, ok and L["%s is on your friends list now."]:format(name) or L["The game did not add %s."]:format(name), not ok)
			M:UpdateInfo(window)
		end },
	{ key = "who", art = "Interface\\Common\\UI-Searchbox-Icon", mono = true, tipTitle = Key("Who is this?"),
		tip = Key("Asks the game who this player is: level, race, class, guild and zone show in chat."),
		onClick = function(window)
			local name = ContactName(window)
			if not (name and C_FriendList and C_FriendList.SendWho) then return end
			local short = Readable(Ambiguate(name, "none")) or name
			pcall(C_FriendList.SendWho, ('n-"%s"'):format(short))
		end },
	{ key = "ignore", art = "Interface\\Buttons\\UI-GroupLoot-Pass-Up", mono = true, danger = true, tipTitle = Key("Ignore"),
		tip = Key("Puts this player on your ignore list after you confirm. Their whispers and chat stop reaching you."),
		onClick = function(window)
			local name = ContactName(window)
			if not (name and C_FriendList and C_FriendList.AddIgnore) then return end
			E:ShowConfirm({ title = L["Ignore %s?"]:format(name),
				text = L["Their whispers and chat stop reaching you. The game's Ignore list takes them off again."],
				accept = L["Ignore"], danger = true,
				onAccept = function()
					-- The game answers whether the name went on the list (a
					-- full list or an unknown name says no).
					local ok, added = pcall(C_FriendList.AddIgnore, name)
					local done = ok and added == true
					Notice(window, done and L["%s is on your ignore list now."]:format(name) or L["The game did not ignore %s."]:format(name), not done)
				end })
		end },
	{ key = "history", art = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", mono = true, tipTitle = Key("Saved conversation"),
		tip = Key("Opens this conversation in the history browser."),
		onClick = function(window)
			if not window.key then return end
			if not M.browser then M:CreateBrowser() end
			M.browser:Show()
			if Store().contacts[window.key] then M:ShowConversation(window.key) end
		end },
}
M.CONTACT_ACTIONS = CONTACT_ACTIONS

-- Which buttons a window shows now, laid out from the close button
-- leftwards; the title ends before the leftmost one.
function M:UpdateContactButtons(window)
	local buttons = window.contactButtons
	if not buttons then return end
	local player = not (window.group or window.bnetID) and ContactName(window) ~= nil
	local on = self.db.contactButtons
	local show = {
		invite = on and player and not InGroupWith(ContactName(window)),
		friend = on and player and FriendEntry(ContactName(window)) == nil,
		who = on and player,
		ignore = on and player,
		history = on and not window.group and KeepHistory(window.key or ""),
	}
	local anchor, offset = window.titleBar, -28
	local count = 0
	for index = #CONTACT_ACTIONS, 1, -1 do
		local action = CONTACT_ACTIONS[index]
		local button = buttons[action.key]
		button:ClearAllPoints()
		if show[action.key] then
			button:SetPoint("RIGHT", anchor, anchor == window.titleBar and "RIGHT" or "LEFT", offset, 0)
			anchor, offset = button, -2
			count = count + 1
			button:Show()
		else
			button:Hide()
		end
	end
	window.title:SetPoint("RIGHT", window.titleBar, "RIGHT", -28 - count * (CONTACT_BUTTON + 2), 0)
end

local function CreateContactButtons(window)
	window.contactButtons = {}
	for _, action in ipairs(CONTACT_ACTIONS) do
		local button = E.UIKit.IconButton(window, CONTACT_BUTTON, action.art, function() action.onClick(window) end,
			L[action.tipTitle], L[action.tip], nil, { mono = action.mono, danger = action.danger })
		button:Hide()
		window.contactButtons[action.key] = button
	end
end

local function CreateWindow(key, title)
	local reused = ReuseWindow(key, title)
	if reused then return reused end
	local window = CreateFrame("Frame", nil, UIParent)
	window.key = key
	window:SetSize(M.db.width, M.db.height)
	window:SetFrameStrata("MEDIUM")
	window:SetToplevel(true)
	window:SetClampedToScreen(true)
	window:SetMovable(true)
	window:SetResizable(true)
	if window.SetResizeBounds then window:SetResizeBounds(240, 140, 800, 600) end
	window:EnableMouse(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SaveWindowPoint(self)
	end)
	local count = #order % 5
	local last = M.db.lastPoint
	if type(last) == "table" and last[1] then
		window:SetPoint(last[1], UIParent, last[2], last[3] + count * 24, last[4] - count * 24)
	else
		window:SetPoint("CENTER", UIParent, "CENTER", 200 + count * 24, 100 - count * 24)
	end

	window.titleBar = window:CreateTexture(nil, "BORDER")
	window.titleBar:SetPoint("TOPLEFT", 6, -6)
	window.titleBar:SetPoint("TOPRIGHT", -6, -6)
	window.titleBar:SetHeight(22)
	window.title = E.UIKit.Title(window, 15)
	-- The title is the other player's name, the info line their guild:
	-- the name font keeps every alphabet.
	E:UseNameFont(window.title)
	window.title:SetPoint("LEFT", window.titleBar, "LEFT", 6, 0)
	window.title:SetPoint("RIGHT", window.titleBar, "RIGHT", -28, 0)
	window.title:SetText(title)

	window.info = E.UIKit.Text(window, E.tokens.size.small, "LEFT", "secondary")
	E:UseNameFont(window.info)
	window.info:SetPoint("TOPLEFT", window.titleBar, "BOTTOMLEFT", 6, -3)
	window.info:SetPoint("TOPRIGHT", window.titleBar, "BOTTOMRIGHT", -6, -3)
	window.info:Hide()

	local close = CreateFrame("Button", nil, window, "UIPanelCloseButtonNoScripts")
	close:SetSize(22, 22)
	close:SetPoint("RIGHT", window.titleBar, "RIGHT", 2, 0)
	close:SetScript("OnClick", function() window:Hide() end)
	E:SkinCloseButton(close)
	CreateContactButtons(window)

	local messages = CreateFrame("ScrollingMessageFrame", nil, window)
	E:SetNameTextFont(messages, M.db.fontSize)
	messages:SetJustifyH("LEFT")
	messages:SetFading(false)
	messages:SetMaxLines(500)
	messages:SetHyperlinksEnabled(true)
	messages:SetScript("OnHyperlinkClick", function(_, link, text, button)
		SetItemRef(link, text, button)
	end)
	messages:EnableMouseWheel(true)
	messages:SetScript("OnMouseWheel", function(self, delta)
		if IsShiftKeyDown() then
			if delta > 0 then self:ScrollToTop() else self:ScrollToBottom() end
		elseif delta > 0 then
			self:ScrollUp()
		else
			self:ScrollDown()
		end
	end)
	window.messages = messages

	local input = FlatInput(window, M.db.fontSize)
	input:SetPoint("BOTTOMLEFT", 10, 8)
	input:SetPoint("BOTTOMRIGHT", -20, 8)
	input:SetHeight(22)
	input:SetScript("OnEnterPressed", function(self)
		if Send(window, self:GetText()) then self:SetText("") end
	end)
	window.input = input
	window.grip = SizeGrip(window)

	window:SetScript("OnShow", function()
		window.unread = 0
		window.openAfterCombat = nil
		M:UpdateInfo(window)
		M:UpdateDock()
	end)
	window:SetScript("OnHide", function() M:UpdateDock() end)

	StyleFrame(window)
	M:LayoutWindow(window)
	LoadHistory(window, key)
	window:Hide()
	windows[key] = window
	table.insert(order, 1, key)
	return window
end

local function GetWindow(key, title)
	local window = windows[key] or CreateWindow(key, title)
	for i, k in ipairs(order) do
		if k == key then table.remove(order, i) break end
	end
	table.insert(order, 1, key)
	if not IsSecret(title) and title then window.title:SetText(title) end
	return window
end

---------------------------------------------------------------------------
-- Dock: one button per conversation, with an unread count
---------------------------------------------------------------------------
function M:CreateDock()
	local dock = CreateFrame("Frame", "EldoUI_EIM", UIParent)
	dock:SetSize(160, 24)
	self.dock = dock
	dock.buttons = {}
	E:CreateMover(dock, "EldoUI_EIM", L["Instant Messages"], { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 19, 330 })
end

function M:UpdateDock()
	local dock = self.dock
	if not dock then return end
	local r, g, b = unpack(E.media.accentColor)
	-- Buttons only up to the dock size: the rest of the conversations wait
	-- in their order.
	local size = math.min(#order, self.db.dockSize or 0)
	for i = 1, size do
		local key = order[i]
		local button = dock.buttons[i]
		if not button then
			button = CreateFrame("Button", nil, dock)
			button:SetSize(160, 22)
			button:SetPoint("BOTTOMLEFT", 0, (i - 1) * 24)
			E:SetTemplate(button)
			button.text = E:CreateText(button, E.tokens.size.body, "LEFT")
			E:UseNameFont(button.text)
			button.text:SetPoint("LEFT", 6, 0)
			button.text:SetPoint("RIGHT", -6, 0)
			button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			button:SetScript("OnClick", function(dockButton, mouse)
				if E:IsOptionsLinkClick(dockButton, mouse) then return end
				local window = windows[dockButton.key]
				if not window then return end
				if mouse == "RightButton" then
					-- Right-click closes the conversation and drops it from the dock.
					ReleaseWindow(dockButton.key)
					M:UpdateDock()
					return
				end
				window:SetShown(not window:IsShown())
			end)
			button:SetScript("OnEnter", function(dockButton)
				GameTooltip:SetOwner(dockButton, "ANCHOR_RIGHT")
				GameTooltip:AddLine(windows[dockButton.key] and windows[dockButton.key].title:GetText() or "")
				E:TooltipHint(GameTooltip, { L["Left-click"], L["show or hide"] }, { L["Right-click"], L["close"] })
				GameTooltip:Show()
			end)
			button:SetScript("OnLeave", function() GameTooltip:Hide() end)
			E:BindOptionsLink(button, { page = "module:Messages", key = "dockSize" })
			dock.buttons[i] = button
		end
		local window = windows[key]
		button.key = key
		local unread = window.unread or 0
		button.text:SetText((unread > 0 and ("%s(%d)|r "):format(E:TokenHex(E.tokens.text.warn), unread) or "") .. window.title:GetText())
		button:SetBackdropBorderColor(unread > 0 and r or 0, unread > 0 and g or 0, unread > 0 and b or 0, 1)
		button:Show()
	end
	for i = size + 1, #dock.buttons do dock.buttons[i]:Hide() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- One whisper sound, set in Chat (Alerts and filters). Chat plays it while
-- it may change Blizzard's chat; otherwise the messenger plays the same
-- sound itself, so a whisper always sounds once on top of the game's own.
local function WhisperSound()
	local chat = E.modules and E.modules.Chat
	local saved = E.db and E.db.modules and E.db.modules.Chat
	local value = chat and chat.db and chat.db.whisperSound or (type(saved) == "table" and saved.whisperSound)
	if type(value) ~= "string" or value == "" or value:lower() == "none" then return "none" end
	return value:find(":", 1, true) and value or ("kit:" .. value)
end

local function ChatWhisperSound()
	local chat = E.modules and E.modules.Chat
	if not (chat and chat.active and chat.Allowed and chat:Allowed("improve")) then return false end
	return WhisperSound() ~= "none"
end
M.ChatWhisperSound = ChatWhisperSound

local function Notify(window, incoming)
	if incoming then
		local sound = WhisperSound()
		if not window.group and sound ~= "none" and not ChatWhisperSound() then
			E:PlayMedia(sound)
		end
		-- Windows never pop up in combat: the dock shows the unread count,
		-- and the window opens when the fight ends.
		local popUp = M.db.openOnReceive == "window" and not window.group
		if popUp and not InCombatLockdown() then
			window:Show()
		elseif not window:IsShown() then
			window.unread = (window.unread or 0) + 1
			if popUp then
				window.openAfterCombat = true
				M:RegisterEvent("PLAYER_REGEN_ENABLED", function() M:OpenAfterCombat() end)
			end
		end
	elseif M.db.openOnSend and not window.group then
		window:Show()
	end
	M:UpdateDock()
end

-- The fight is over: open each conversation that got a whisper during it
-- and was not opened or closed since.
function M:OpenAfterCombat()
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	if InCombatLockdown() then return end
	for _, window in pairs(windows) do
		if window.openAfterCombat then
			window.openAfterCombat = nil
			if self.db.openOnReceive == "window" and (window.unread or 0) > 0 then window:Show() end
		end
	end
end

local function OnWhisper(_, event, text, sender, _, _, _, _, _, _, _, _, _, guid, bnetID)
	local incoming = event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER"
	local bn = event == "CHAT_MSG_BN_WHISPER" or event == "CHAT_MSG_BN_WHISPER_INFORM"
	local key, title
	if bn then
		bnetID = Readable(bnetID)
		if not bnetID then return end
		local info = C_BattleNet.GetAccountInfoByID(bnetID)
		local tag = info and Readable(info.battleTag)
		key = "BN:" .. (tag or tostring(bnetID))
		title = (info and Readable(info.accountName)) or Readable(sender) or key
	else
		sender = Readable(sender)
		if not sender then return end
		key = Ambiguate(sender, "none")
		title = key
	end
	local window = GetWindow(key, title)
	window.bnetID = bn and bnetID or nil
	window.target = not bn and sender or nil
	local meta = Meta(key)
	if bn then
		local info = C_BattleNet.GetAccountInfoByID(bnetID)
		meta.battleTag = info and Readable(info.battleTag) or meta.battleTag
	else
		-- Sent and received whispers both carry the contact's GUID.
		guid = Readable(guid)
		if type(guid) == "string" and guid ~= "" then
			window.guid = guid
			meta.guid = guid
		end
		ColorTitle(window)
	end
	AddLine(window, incoming and title or nil, text, incoming, window.color, true)
	Notify(window, incoming)
	if window:IsShown() then M:UpdateInfo(window) end
end

local function OnGroupChat(_, event, text, sender, _, _, _, _, _, _, _, _, _, guid)
	local group = EVENT_GROUP[event]
	local def = group and GROUPS[group]
	if not def or not M.db.groups[group] then return end
	local window = GetWindow(def.key, def.title)
	window.group = def
	local name = Readable(sender)
	local mine = false
	if name then
		name = Ambiguate(name, "none")
		mine = E:IsMe(name)
	elseif IsSecret(sender) then
		name = sender -- secret: shown on its own line, never joined
	end
	AddLine(window, (not mine) and name or nil, text, not mine, ClassHex(guid), true)
	Notify(window, not mine)
end

-- Whispers EIM can't show (secret sender) stay in the main chat. Hiding
-- them from Blizzard's chat is a change to Blizzard's chat, so it follows
-- the Blizzard UI switch for chat windows (Improve).
local function ChatAllowed()
	return E:BlizzardAllowed("chat-frames", "improve")
end

-- Whether EIM shows this whisper itself, so the main chat can leave it
-- out: the same readable sender (or Battle.net account) OnWhisper needs.
local function TakesWhisper(event, sender, bnetID)
	if not (M.active and M.db.hideFromChat and ChatAllowed()) then return false end
	if BNET[event] then return Readable(bnetID) ~= nil end
	return Readable(sender) ~= nil
end

-- For other chat code (Chat's line hook): true for a line EIM takes out of
-- the chat windows, so it is not copied, mirrored or alerted on either.
function M:TakesChatLine(event, args)
	if IsSecret(event) or type(event) ~= "string" or type(args) ~= "table" then return false end
	if not (INCOMING[event] or SENT[event]) then return false end
	return TakesWhisper(event, args[2], args[13])
end

-- Whispers you send: hidden by a message filter. Blizzard's handler keeps
-- nothing from them (the last told target comes from the edit box).
local function WhisperFilter(_, event, _, sender, _, _, _, _, _, _, _, _, _, _, bnetID)
	return SENT[event] and TakesWhisper(event, sender, bnetID) or false
end

-- Whispers you receive: Blizzard's handler runs in full (reply target, its
-- sound, taskbar flash), then this post-hook on the chat frame's
-- AddMessage takes that one line out again. RemoveMessagesByPredicate is a
-- secure call on chat frames, so nothing of Blizzard's is tainted.
local function OnChatLine(frame, _, _, _, _, _, _, _, event, eventArgs)
	if IsSecret(event) or type(event) ~= "string" or not INCOMING[event] or type(eventArgs) ~= "table" then return end
	if not TakesWhisper(event, eventArgs[2], eventArgs[13]) then return end
	frame:RemoveMessagesByPredicate(function(_, _, _, _, _, _, _, _, args)
		return args == eventArgs
	end)
end

local hookedFrames = setmetatable({}, { __mode = "k" })
local function HookChatFrames()
	for _, name in ipairs(CHAT_FRAMES or { "ChatFrame1" }) do
		local frame = _G[name]
		if frame and not hookedFrames[frame] and frame.AddMessage then
			hookedFrames[frame] = true
			hooksecurefunc(frame, "AddMessage", OnChatLine)
		end
	end
end
M.HookChatFrames = HookChatFrames
-- Whisper tabs and new chat windows made later get the hook too.
if FCF_OpenTemporaryWindow then hooksecurefunc("FCF_OpenTemporaryWindow", HookChatFrames) end
if FCF_OpenNewWindow then hooksecurefunc("FCF_OpenNewWindow", HookChatFrames) end

local function GroupFilter(_, event, _, sender)
	local group = EVENT_GROUP[event]
	return M.active and M.db.groupHideFromChat and group and M.db.groups[group] and ChatAllowed()
		and not IsSecret(sender) or false
end

M.chatFilters = {} -- event -> filter
local function AddFilter(event, fn)
	M.chatFilters[event] = fn
	local add = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
	if add then add(event, fn) end
end

-- Contact info follows the friends list, guild roster and Battle.net.
local infoQueued = false
local function QueueInfo()
	if infoQueued then return end
	infoQueued = true
	C_Timer.After(1, function()
		infoQueued = false
		for _, window in pairs(windows) do
			if window:IsShown() then M:UpdateInfo(window) end
		end
	end)
end

-- A unit the game shows may be a whisper contact: its level is kept for
-- the session, and an open window shows it. Only the GUIDs of this
-- session's conversations are compared; a secret unit, GUID or level is
-- skipped.
local UNIT_OF_EVENT = { PLAYER_TARGET_CHANGED = "target", PLAYER_FOCUS_CHANGED = "focus", UPDATE_MOUSEOVER_UNIT = "mouseover" }
local function NoteLevel(window, level)
	if not level or seenLevels[window.guid] == level then return end
	seenLevels[window.guid] = level
	if window:IsShown() then M:UpdateInfo(window) end
end

local function OnUnitSeen(_, event, unit)
	if event == "GROUP_ROSTER_UPDATE" then
		for _, window in pairs(windows) do
			if type(window.guid) == "string" then NoteLevel(window, UnitLevelByGUID(window.guid)) end
		end
		-- The invite button hides for a contact who joined your group.
		QueueInfo()
		return
	end
	unit = UNIT_OF_EVENT[event] or unit
	if IsSecret(unit) or type(unit) ~= "string" or not (UnitGUID and UnitLevel) then return end
	local guid = E.PlainCall(UnitGUID, unit)
	if type(guid) ~= "string" then return end
	for _, window in pairs(windows) do
		if window.guid == guid and not (window.group or window.bnetID) then
			NoteLevel(window, PlainLevel(E.PlainCall(UnitLevel, unit)))
			return
		end
	end
end
M.UNIT_LEVEL_EVENTS = { "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED",
	"UNIT_LEVEL", "GROUP_ROSTER_UPDATE" }

function M:RegisterGroupEvents()
	for group, def in pairs(GROUPS) do
		for _, event in ipairs(def.events) do
			if self.db.groups[group] then
				self:RegisterEvent(event, OnGroupChat)
			else
				self:UnregisterEvent(event)
			end
		end
	end
end

-- The messenger's own "Extra whisper sound" became Chat's one whisper
-- sound: a sound picked there moves to Chat once, unless Chat has its own.
-- An on/off value from before media ids meant no extra sound.
function M.MigrateSound(profile)
	local modules = type(profile) == "table" and type(profile.modules) == "table" and profile.modules
	local own = modules and type(modules.Messages) == "table" and modules.Messages
	if not own then return end
	local sound = own.sound
	own.sound = nil
	if type(sound) ~= "string" or sound == "" or sound:lower() == "none" then return end
	if type(modules.Chat) ~= "table" then modules.Chat = {} end
	local chat = modules.Chat
	if type(chat.whisperSound) ~= "string" or chat.whisperSound:lower() == "none" then chat.whisperSound = sound end
end
E:RegisterProfileMigration(M.MigrateSound, "Messages:sound", 1)

-- A new whisper opens its window by default since 0.7.2000 (after the
-- fight when it arrives in combat). A profile on the Messenger style, the
-- default, held "show in the dock" only because that style wrote it, so it
-- moves to the new default once; a profile on another style keeps its choice.
function M.MigratePopUp(profile)
	local modules = type(profile) == "table" and type(profile.modules) == "table" and profile.modules
	local own = modules and type(modules.Messages) == "table" and modules.Messages
	if not own or own.openOnReceive ~= "dock" then return end
	if own.style == nil or own.style == "Messenger" then own.openOnReceive = nil end
end
E:RegisterProfileMigration(M.MigratePopUp, "Messages:popup", 1)

-- A shift-clicked item, spell or quest link goes into the message line of
-- the conversation window that has the keyboard focus, at the cursor, like
-- the game's own chat box. Nothing is sent until Enter is pressed.
local linkHooked = false
local function HookLinks()
	if linkHooked then return end
	linkHooked = true
	E:HookLinkInsert(function(link)
		if not M.active or type(link) ~= "string" or IsSecret(link) or link == "" then return end
		for _, window in pairs(windows) do
			local input = window.input
			if input and window:IsVisible() and input:HasFocus() then
				input:Insert(link)
				return
			end
		end
	end)
end

function M:OnEnable()
	self:ScheduleTrim() -- the limit a later change on the page compares with
	HookChatFrames()
	HookLinks()
	if not self.dock then self:CreateDock() end
	for _, event in ipairs(WHISPER_EVENTS) do self:RegisterEvent(event, OnWhisper) end
	if not self.filtered then
		self.filtered = true
		for event in pairs(SENT) do AddFilter(event, WhisperFilter) end
		for event in pairs(EVENT_GROUP) do AddFilter(event, GroupFilter) end
	end
	self:RegisterGroupEvents()
	for _, event in ipairs({ "FRIENDLIST_UPDATE", "GUILD_ROSTER_UPDATE", "BN_FRIEND_INFO_CHANGED" }) do
		self:RegisterEvent(event, QueueInfo)
	end
	for _, event in ipairs(self.UNIT_LEVEL_EVENTS) do self:RegisterEvent(event, OnUnitSeen) end
	self.dock:Show()
	self:UpdateDock()
end

function M:OnDisable()
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	for _, window in pairs(windows) do
		window.openAfterCombat = nil
		window:Hide()
	end
	if self.dock then self.dock:Hide() end
	if self.browser then self.browser:Hide() end
end

-- Lowering "Lines kept per contact" drops the oldest lines of every saved
-- conversation. At 0 nothing new is saved and what is saved stays (Clear
-- all history deletes it). Only a change on the page trims, a moment after
-- the last one, so a slider dragged down and back up again keeps
-- everything; switching to a profile with a lower limit trims nothing.
function M:TrimHistory()
	local limit = self.db.history or 0
	if limit <= 0 then return 0 end
	local dropped = 0
	for _, history in pairs(Store().contacts or {}) do
		while #history > limit do
			table.remove(history, 1)
			dropped = dropped + 1
		end
	end
	if dropped > 0 and self.browser and self.browser:IsShown() then self:RefreshBrowser() end
	return dropped
end

local trimToken, trimDb, trimBase = 0, nil, 0
function M:ScheduleTrim()
	local limit = self.db.history or 0
	trimToken = trimToken + 1
	if self.db ~= trimDb then
		trimDb, trimBase = self.db, limit
		return
	end
	if limit >= trimBase then
		trimBase = limit
		return
	end
	local token = trimToken
	C_Timer.After(1, function()
		if token ~= trimToken then return end
		M:TrimHistory()
		trimBase = M.db.history or 0
	end)
end

-- Theme, size and font follow the settings and the layout preset.
function M:OnProfileChanged()
	self:ScheduleTrim()
	for _, window in pairs(windows) do
		StyleFrame(window)
		E:SetHeaderFont(window.title, 15)
		E:SetNameTextFont(window.info, E.tokens.size.small)
		E:SetNameTextFont(window.messages, self.db.fontSize)
		E:SetNameTextFont(window.input, self.db.fontSize)
		self:UpdateInfo(window)
	end
	if self.browser then E:SetNameTextFont(self.browser.view, E.tokens.size.body) end
	if self.active then self:RegisterGroupEvents() end
	self:UpdateDock()
end

-- Keep the theme in step when a layout preset is applied.
hooksecurefunc(E, "ApplyLayout", function()
	if M.active then M:OnProfileChanged() end
end)

---------------------------------------------------------------------------
-- Open a conversation from code (history browser, /eui eim <name>)
---------------------------------------------------------------------------
local function FindBNetID(battleTag)
	if not (C_BattleNet and C_BattleNet.GetFriendAccountInfo) then return end
	for index = 1, E:BNetFriendCount() do
		local info = C_BattleNet.GetFriendAccountInfo(index)
		if info and Readable(info.battleTag) == battleTag then return Readable(info.bnetAccountID) end
	end
end

function M:OpenConversation(key)
	if not self.active then return end
	local meta = Store().meta[key] or {}
	local window
	if key:find("^BN:") then
		local id = FindBNetID(meta.battleTag or key:sub(4))
		if not id then
			self:Print(L["That Battle.net friend is not on your friends list right now."])
			return
		end
		-- The live account name while the friend is on the list.
		local info = C_BattleNet and C_BattleNet.GetAccountInfoByID and C_BattleNet.GetAccountInfoByID(id)
		window = GetWindow(key, (info and Readable(info.accountName)) or key:sub(4))
		window.bnetID = id
	elseif IsGroupKey(key) then
		for group, def in pairs(GROUPS) do
			if def.key == key then
				window = GetWindow(key, def.title)
				window.group = GROUPS[group]
			end
		end
	else
		window = GetWindow(key, meta.title or key)
		window.target = window.target or key
		if not window.guid and type(meta.guid) == "string" and meta.guid:find("^Player%-") then window.guid = meta.guid end
	end
	if window then
		window:Show()
		window.input:SetFocus()
	end
end

---------------------------------------------------------------------------
-- History browser: every saved conversation, with search and delete
---------------------------------------------------------------------------
local ROW = 18

local function ContactTitle(key)
	local meta = Store().meta[key]
	if key:find("^BN:") then return key:sub(4) end
	if meta and meta.title then return meta.title end
	for _, def in pairs(GROUPS) do
		if def.key == key then return def.title end
	end
	return key
end

local function Matches(key, query)
	if query == "" then return true end
	if E:FoldText(ContactTitle(key)):find(query, 1, true) or E:FoldText(key):find(query, 1, true) then return true end
	for _, line in ipairs(Store().contacts[key] or {}) do
		if type(line) == "table" and type(line[3]) == "string" and E:FoldText(line[3]):find(query, 1, true) then return true end
	end
	return false
end

local function LastTime(key)
	local meta = Store().meta[key]
	if meta and meta.last then return meta.last end
	local lines = Store().contacts[key]
	local last = type(lines) == "table" and lines[#lines]
	return type(last) == "table" and last[1] or 0
end

-- The kit's tool window: header-font title, accent line, close button,
-- Escape closes it, a footer for the buttons.
function M:CreateBrowser()
	local Kit = E.UIKit
	local browser = Kit.CreateToolWindow("EldoUI_EIMHistory", { title = L["Message history"], width = 640, height = 400,
		strata = "DIALOG", footer = Kit.TOOL_FOOTER })
	self.browser = browser
	local body = browser.content

	local search = Kit.Input(body, { width = 190, hint = L["Search names and text"], onChange = function() M:RefreshBrowser() end })
	-- Searches are names and words of other players: every alphabet shows.
	E:UseNameFont(search)
	search:SetPoint("TOPLEFT", 0, 0)
	browser.search = search

	local list = CreateFrame("Frame", nil, body)
	list:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -4)
	list:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
	list:SetWidth(190)
	E:SetTemplate(list, true)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		browser.offset = math.max(0, (browser.offset or 0) - delta * 3)
		M:RefreshBrowser()
	end)
	browser.list = list
	browser.rows = {}
	browser.offset = 0

	local view = CreateFrame("ScrollingMessageFrame", nil, body)
	view:SetPoint("TOPLEFT", list, "TOPRIGHT", 10, 0)
	view:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
	-- Past conversations: what the other players wrote, in the name font.
	E:SetNameTextFont(view, E.tokens.size.body)
	view:SetJustifyH("LEFT")
	view:SetFading(false)
	view:SetMaxLines(1000)
	view:SetHyperlinksEnabled(true)
	view:SetScript("OnHyperlinkClick", function(_, link, text, button) SetItemRef(link, text, button) end)
	view:EnableMouseWheel(true)
	view:SetScript("OnMouseWheel", function(frame, delta)
		if delta > 0 then frame:ScrollUp() else frame:ScrollDown() end
	end)
	browser.view = view

	-- The conversation count sits in the footer's status line.
	browser.count = browser.footerText

	local delete = Kit.Button(browser.footer, { text = DELETE or L["Delete"], large = true, kind = "danger" })
	delete:SetPoint("RIGHT", -Kit.TOOL_PAD, 0)
	-- Asks first on the shared dialog shell (E:ShowConfirm).
	delete:SetScript("OnClick", function()
		local key = browser.selected
		if not key then return end
		E:ShowConfirm({ title = L["Message history"], text = L["Delete the history with %s? This can't be undone."]:format(key),
			accept = DELETE or L["Delete"], danger = true, data = key,
			onAccept = function(chosen)
				Store().contacts[chosen] = nil
				Store().meta[chosen] = nil
				if browser.selected == chosen then browser.selected = nil end
				M:RefreshBrowser()
			end })
	end)
	browser.delete = delete

	local open = Kit.Button(browser.footer, { text = L["Open chat"], large = true, kind = "primary" })
	open:SetPoint("RIGHT", delete, "LEFT", -8, 0)
	open:SetScript("OnClick", function()
		if browser.selected then M:OpenConversation(browser.selected) end
	end)
	browser.open = open

	browser.footerText:ClearAllPoints()
	browser.footerText:SetPoint("LEFT", 12, 0)
	browser.footerText:SetPoint("RIGHT", open, "LEFT", -8, 0)
	browser:HookScript("OnShow", function() M:RefreshBrowser() end)
end

function M:ShowConversation(key)
	local browser = self.browser
	browser.selected = key
	browser.view:Clear()
	for _, line in ipairs(Store().contacts[key] or {}) do
		if type(line) == "table" and type(line[3]) == "string" then
			local mine = line[2] ~= 1
			browser.view:AddMessage(("%s%s|r %s%s"):format(E:TokenHex(E.tokens.text.dim), E:ShortDate(line[1] or 0),
				mine and E:TokenHex(E.tokens.text.secondary) .. (YOU or "You") .. ":|r " or "", line[3]), mine and 0.75 or 1, mine and 0.75 or 0.8, mine and 0.75 or 1)
		end
	end
	browser.view:ScrollToBottom()
end

function M:RefreshBrowser()
	local browser = self.browser
	if not browser or not browser:IsShown() then return end
	-- Folded (case, accents, Cyrillic) like the names it is compared with.
	local query = E:FoldText(browser.search:GetText() or "")
	local keys = {}
	for key, lines in pairs(Store().contacts) do
		if type(lines) == "table" and #lines > 0 and Matches(key, query) then keys[#keys + 1] = key end
	end
	table.sort(keys, function(a, b) return LastTime(a) > LastTime(b) end)
	local visible = math.max(math.floor((browser.list:GetHeight() - 4) / ROW), 1)
	browser.offset = math.min(browser.offset or 0, math.max(#keys - visible, 0))
	local r, g, b = unpack(E.media.accentColor)
	for index = 1, math.max(visible, #browser.rows) do
		local row = browser.rows[index]
		if not row and index <= visible then
			row = CreateFrame("Button", nil, browser.list)
			row:SetHeight(ROW)
			row:SetPoint("TOPLEFT", 2, -2 - (index - 1) * ROW)
			row:SetPoint("TOPRIGHT", -2, -2 - (index - 1) * ROW)
			row.hover = row:CreateTexture(nil, "HIGHLIGHT")
			row.hover:SetAllPoints()
			row.mark = row:CreateTexture(nil, "BACKGROUND")
			row.mark:SetAllPoints()
			row.text = E:CreateText(row, E.tokens.size.label, "LEFT")
			E:UseNameFont(row.text)
			row.text:SetPoint("LEFT", 4, 0)
			row.text:SetPoint("RIGHT", -40, 0)
			row.count = E:CreateText(row, E.tokens.size.tiny, "RIGHT")
			row.count:SetPoint("RIGHT", -4, 0)
			row.count:SetTextColor(unpack(E.media.text.dim))
			row:SetScript("OnClick", function(button)
				M:ShowConversation(button.key)
				M:RefreshBrowser()
			end)
			browser.rows[index] = row
		end
		if row then
			local key = index <= visible and keys[index + browser.offset]
			row.key = key or nil
			row:SetShown(key and true or false)
			row.hover:SetColorTexture(r, g, b, 0.15)
			row.mark:SetColorTexture(r, g, b, key and key == browser.selected and 0.3 or 0)
			if key then
				row.text:SetText(ContactTitle(key))
				row.count:SetText(#(Store().contacts[key] or {}))
			end
		end
	end
	if browser.selected and not Store().contacts[browser.selected] then browser.selected = nil end
	if not browser.selected then browser.view:Clear() end
	browser.count:SetText((#keys == 1 and L["%d conversation"] or L["%d conversations"]):format(#keys))
	browser.open:SetEnabled(browser.selected ~= nil and self.active)
	browser.delete:SetEnabled(browser.selected ~= nil)
end

function M:ToggleBrowser()
	if not self.browser then self:CreateBrowser() end
	self.browser:Toggle()
end

E:AddCommand("eim", "[name]  the whisper history browser, or open a conversation with name", function(arg)
	arg = strtrim(arg or "")
	if arg ~= "" then
		if not M.active then
			E:Print(E:ModuleOffHint("Messages"))
			return
		end
		local key = Ambiguate(arg, "none")
		if not windows[key] and not Store().contacts[key] then
			-- A new conversation: the first line you type opens it for real.
			local window = GetWindow(key, key)
			window.target = arg
		end
		M:OpenConversation(key)
		return
	end
	M:ToggleBrowser()
end)

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local function NoGroups()
	for _, group in ipairs(GROUP_ORDER) do
		if M.db and M.db.groups[group] then return false end
	end
	return L["Give a group channel a window first."]
end

M.options = {
	{ type = "header", label = "Windows" },
	{ type = "select", key = "theme", label = "Theme",
		desc = "Automatic picks the theme that fits your layout preset, in its accent color. Panel draws the windows like every other EldoUI window, in your art style.",
		values = { auto = "Automatic (follows preset)", Eldo = "Eldo (flat, accent border)", Glass = "Glass (see-through)", Blizzard = "Panel (follows the art style)" } },
	{ type = "range", key = "fontSize", label = "Text size", min = 10, max = 20, step = 1, desc = "Text size in the conversation windows." },
	{ type = "range", key = "width", label = "New window width", min = 240, max = 800, step = 10, desc = "Width of a newly opened window. Drag the corner to resize one." },
	{ type = "range", key = "height", label = "New window height", min = 140, max = 600, step = 10, desc = "Height of a newly opened window." },
	{ type = "toggle", key = "timestamps", label = "Show timestamps", desc = "The time before each line." },
	{ type = "toggle", key = "contactButtons", label = "Contact buttons",
		desc = "Buttons in a whisper window's title bar: invite, add friend, who is this, ignore and the saved conversation. Each one does its task once, on your click." },
	{ type = "toggle", key = "contactInfo", label = "Contact info line", desc = "Under the name: level, race and class, zone, and whether the contact is a friend or in your guild. The level shows once the game has seen the player." },
	{ type = "range", key = "dockSize", label = "Dock buttons", min = 3, max = 12, step = 1, desc = "How many conversations the dock shows. Right-click a dock button to close that conversation." },

	{ type = "header", label = "Whispers" },
	{ type = "toggle", key = "hideFromChat", label = "Show whispers only in the messenger", desc = "Off shows them in the main chat as well. Reply, the whisper sound and the taskbar flash work either way. Needs the Blizzard UI switch Improve for chat." },
	{ type = "select", key = "openOnReceive", label = "New whisper", desc = "Open the window straight away (in a fight it opens when the fight ends) or just count it in the dock.",
		values = { window = "Open the window", dock = "Show in the dock" } },
	{ type = "toggle", key = "openOnSend", label = "Open the window when I whisper someone", desc = "A whisper you send from the main chat opens that conversation's window." },
	{ type = "execute", label = "Whisper sound", keywords = "sound whisper alert",
		desc = "One extra sound on top of the game's own when a whisper arrives, set in Chat (Alerts and filters). It plays for the messenger too.",
		func = function() E:ToggleConfig("module:Chat") end },

	{ type = "header", label = "Group windows" },
	{ type = "description", label = "Give a group channel its own window. The messenger never posts by itself: a line goes out only when you press Enter in the window." },
	{ type = "toggle", key = "groups.guild", label = "Guild", desc = "Guild chat in its own window." },
	{ type = "toggle", key = "groups.officer", label = "Officer", desc = "Officer chat in its own window." },
	{ type = "toggle", key = "groups.party", label = "Party", desc = "Party chat in its own window." },
	{ type = "toggle", key = "groups.raid", label = "Raid", desc = "Raid chat and raid warnings in their own window." },
	{ type = "toggle", key = "groups.instance", label = "Instance", desc = "Instance group chat in its own window." },
	{ type = "toggle", key = "groupHideFromChat", label = "Only in the windows", disabled = NoGroups, desc = "The channels above no longer show in the main chat (needs the Blizzard UI switch Improve for chat windows)." },
	{ type = "toggle", key = "groupHistory", label = "Save group chat", disabled = NoGroups, desc = "Keep group lines in the history too. Off keeps only whispers." },

	{ type = "header", label = "History" },
	{ type = "range", key = "history", label = "Lines kept per contact", min = 0, max = 500, step = 10, zeroText = "Off",
		desc = "Saved per character. Lowering it drops the oldest lines of every saved conversation. Off saves nothing new and what is saved stays until you clear it." },
	{ type = "execute", label = "History browser", desc = "Every saved conversation, with search and delete. Also /eui eim.", func = function() M:ToggleBrowser() end },
	{ type = "execute", confirm = true, label = "Clear all history", desc = "Deletes every saved conversation of this character.", func = function()
		local store = Store()
		wipe(store.contacts)
		wipe(store.meta)
		M:RefreshBrowser()
		M:Print(L["Whisper history cleared."])
	end },
}

E:RegisterStyles("Messages", {
	{ mode = true, key = "Messenger", title = "Messenger", desc = "Theme follows the layout, whispers only in the messenger, a new whisper opens its window (after the fight in combat).",
		settings = { theme = "auto", hideFromChat = true, openOnReceive = "window", openOnSend = true, timestamps = true,
			width = 340, height = 220, fontSize = 14, contactInfo = true, dockSize = 8 } },
	{ mode = true, key = "PopUp", title = "Pop-up", desc = "Bigger windows in the EldoUI theme; a new whisper opens its window (after the fight in combat).",
		settings = { theme = "Eldo", hideFromChat = true, openOnReceive = "window", openOnSend = true, timestamps = true,
			width = 360, height = 240, fontSize = 14, contactInfo = true } },
	{ key = "Glass", title = "Glass", desc = "See-through windows that sit lightly over the world.",
		settings = { theme = "Glass", hideFromChat = true, openOnReceive = "dock", timestamps = true, width = 320, height = 200, fontSize = 13 } },
	{ key = "Classic", title = "Classic", desc = "Panels in your art style; whispers also stay in the main chat.",
		settings = { theme = "Blizzard", hideFromChat = false, openOnReceive = "dock", timestamps = false, width = 340, height = 220, fontSize = 14 } },
	{ key = "Compact", title = "Compact", desc = "Small windows, small text, five dock buttons.",
		settings = { theme = "auto", width = 280, height = 160, fontSize = 12, contactInfo = false, dockSize = 5 } },
	{ mode = true, key = "Social", title = "Social", desc = "Guild and party chat get windows too, and their lines are saved.",
		settings = { theme = "auto", hideFromChat = true, openOnReceive = "dock",
			groups = { guild = true, officer = false, party = true, raid = false, instance = false }, groupHistory = true, history = 200 } },
	{ mode = true, key = "Quiet", title = "Quiet", desc = "No pop-ups and nothing new saved: new whispers wait in the dock.",
		settings = { openOnReceive = "dock", openOnSend = false, history = 0 } },
})
