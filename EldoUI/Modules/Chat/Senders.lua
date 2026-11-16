-- EldoUI Chat, part 5: sender details in front of the message.
--
--   * Race and class icons before names, in a size relative to the chat
--     font, with a fine vertical offset, and only where the player wants
--     them (per chat type, numbered channel and chat tab).
--   * The level before the name ("[42]") in the game's difficulty color.
--     Levels come only from what the game hands out: units you can see
--     (target, focus, mouse-over, group), the friends list, the guild
--     roster and /who results. They live for this session only (at most
--     500); an unknown level shows nothing.
--   * The name format (first name, surname, both) on the player
--     link label; the link itself stays complete, so whisper and the right-
--     click menu still work.
--   * Whisper markers: the game's "To X:" / "X whispers:" wording becomes
--     a short marker, matched against the client's own localized strings.
--     The message text is never touched.
--   * Alt-click a name to invite (off by default; a click hook, not
--     a line hook).
-- The rest is a line hook (Messages.lua): it never runs on a secret
-- line, and a secret GUID or level gives no icon and no level.
-- Written from scratch for EldoUI.
local _, E = ...

local M = E:GetModule("Chat")

local IsSecret = function(value) return issecretvalue and issecretvalue(value) or false end
local Readable = E.Plain

local function Improve()
	return M.active and M:Allowed("improve")
end

---------------------------------------------------------------------------
-- Where icons show
---------------------------------------------------------------------------
M.ICON_SCOPE_TYPES = {
	{ "say", "Say and emote" }, { "yell", E.Key("Yell") }, { "whisper", "Whispers" }, { "guild", E.Key("Guild and officer") },
	{ "party", "Party" }, { "raid", "Raid" }, { "instance", "Instance" }, { "channel", E.Key("Numbered channels") },
	{ "other", E.Key("Everything else") },
}
local EVENT_SCOPE = {
	CHAT_MSG_SAY = "say", CHAT_MSG_EMOTE = "say", CHAT_MSG_TEXT_EMOTE = "say", CHAT_MSG_YELL = "yell",
	CHAT_MSG_WHISPER = "whisper", CHAT_MSG_WHISPER_INFORM = "whisper", CHAT_MSG_BN_WHISPER = "whisper",
	CHAT_MSG_BN_WHISPER_INFORM = "whisper", CHAT_MSG_GUILD = "guild", CHAT_MSG_OFFICER = "guild",
	CHAT_MSG_PARTY = "party", CHAT_MSG_PARTY_LEADER = "party", CHAT_MSG_RAID = "raid", CHAT_MSG_RAID_LEADER = "raid",
	CHAT_MSG_RAID_WARNING = "raid", CHAT_MSG_INSTANCE_CHAT = "instance", CHAT_MSG_INSTANCE_CHAT_LEADER = "instance",
	CHAT_MSG_CHANNEL = "channel",
}

-- false only where the player switched icons off.
function M:IconsWanted(event, args, frame)
	local scope = self.db.nameIconScope
	if type(scope) ~= "table" then return true end
	local kind = EVENT_SCOPE[event or ""] or "other"
	if type(scope.types) == "table" and scope.types[kind] == false then return false end
	if kind == "channel" and args and type(scope.channels) == "table" then
		local index = Readable(args[8])
		if type(index) == "number" and scope.channels[index] == false then return false end
	end
	if frame and frame.GetID and type(scope.tabs) == "table" then
		local id = frame:GetID()
		if type(id) == "number" and scope.tabs[id] == false then return false end
	end
	return true
end

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------
local atlasOK = {}
local function AtlasMarkup(atlas, size, offset)
	if type(atlas) ~= "string" then return "" end
	if atlasOK[atlas] == nil then
		atlasOK[atlas] = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)) and true or false
	end
	if not atlasOK[atlas] then return "" end
	return ("|A:%s:%d:%d:0:%d|a"):format(atlas, size, size, offset)
end

function M:NameIconMarkup(guid)
	local mode = self.db.nameIcons
	if mode == "none" or type(guid) ~= "string" or not guid:find("^Player") or not GetPlayerInfoByGUID then return "" end
	local _, class, _, race, sex = GetPlayerInfoByGUID(guid)
	class, race, sex = Readable(class), Readable(race), Readable(sex)
	local size = math.max(6, math.floor((self.db.fontSize or 14) * (self.db.nameIconSize or 100) / 100 + 0.5))
	local offset = math.floor(self.db.nameIconOffset or 0)
	local icons = ""
	if (mode == "race" or mode == "both") and type(race) == "string" and GetRaceAtlas then
		icons = icons .. AtlasMarkup(GetRaceAtlas(race:lower(), sex == 3 and "female" or "male"), size, offset)
	end
	if (mode == "class" or mode == "both") and type(class) == "string" and GetClassAtlas then
		icons = icons .. AtlasMarkup(GetClassAtlas(class:lower()), size, offset)
	end
	return icons
end

---------------------------------------------------------------------------
-- Levels: a session cache filled from what the game hands out
---------------------------------------------------------------------------
local byGUID, byName, count = {}, {}, 0

local function NameKey(name)
	name = Readable(name)
	if type(name) ~= "string" or name == "" then return nil end
	local short = Ambiguate and Readable(Ambiguate(name, "none"))
	if type(short) == "string" and short ~= "" then name = short end
	return name:lower()
end

local function Remember(guid, name, level)
	level = Readable(level)
	if type(level) ~= "number" or level <= 0 then return end
	if count >= 500 then
		wipe(byGUID)
		wipe(byName)
		count = 0
	end
	guid = Readable(guid)
	if type(guid) == "string" and guid ~= "" then byGUID[guid] = level end
	local key = NameKey(name)
	if key then byName[key] = level end
	count = count + 1
end

local function RememberUnit(unit)
	if not (UnitExists and Readable(UnitExists(unit))) then return end
	if not Readable(UnitIsPlayer(unit)) then return end
	-- "Name-Realm" the way chat senders are keyed, never with the surname.
	Remember(UnitGUID(unit), E:UnitNameKey(unit, true), UnitLevel(unit))
end

function M:LevelOf(guid, sender)
	guid = Readable(guid)
	if type(guid) == "string" and byGUID[guid] then return byGUID[guid] end
	local key = NameKey(sender)
	return key and byName[key] or nil
end

local function ScanGroup()
	if not (IsInGroup and IsInGroup()) then return end
	local raid = IsInRaid and IsInRaid()
	for index = 1, raid and 40 or 4 do RememberUnit((raid and "raid" or "party") .. index) end
end

local function ScanFriends()
	if not (C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex) then return end
	for index = 1, math.min(C_FriendList.GetNumFriends() or 0, 200) do
		local info = C_FriendList.GetFriendInfoByIndex(index)
		if type(info) == "table" and Readable(info.connected) then Remember(info.guid, info.name, info.level) end
	end
end

local function ScanGuild()
	if not (IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo) then return end
	for index = 1, math.min(GetNumGuildMembers() or 0, 1000) do
		local name, _, _, level = GetGuildRosterInfo(index)
		Remember(nil, name, level)
	end
end

local function ScanWho()
	if not (C_FriendList and C_FriendList.GetNumWhoResults and C_FriendList.GetWhoInfo) then return end
	for index = 1, math.min(C_FriendList.GetNumWhoResults() or 0, 50) do
		local info = C_FriendList.GetWhoInfo(index)
		if type(info) == "table" then Remember(nil, info.fullName, info.level) end
	end
end

local LEVEL_EVENTS = {
	PLAYER_TARGET_CHANGED = function() RememberUnit("target") end,
	PLAYER_FOCUS_CHANGED = function() RememberUnit("focus") end,
	UPDATE_MOUSEOVER_UNIT = function() RememberUnit("mouseover") end,
	UNIT_LEVEL = function(unit) if type(unit) == "string" then RememberUnit(unit) end end,
	GROUP_ROSTER_UPDATE = ScanGroup,
	FRIENDLIST_UPDATE = ScanFriends,
	GUILD_ROSTER_UPDATE = ScanGuild,
	WHO_LIST_UPDATE = ScanWho,
}
M.LEVEL_EVENTS = LEVEL_EVENTS
local levelOwner = {}       -- its own event owner: the roster events are shared with name mentions
local levelEventsOn = false

function M:ApplyLevels()
	local want = Improve() and self.db.showLevel and true or false
	if want == levelEventsOn then return end
	levelEventsOn = want
	if want then
		for event, fn in pairs(LEVEL_EVENTS) do
			E:RegisterEvent(event, function(_, _, unit) fn(unit) end, levelOwner)
		end
		RememberUnit("player")
		ScanGroup()
		ScanFriends()
		ScanGuild()
	else
		for event in pairs(LEVEL_EVENTS) do E:UnregisterEvent(event, levelOwner) end
		wipe(byGUID)
		wipe(byName)
		count = 0
	end
end

function M:LevelMarkup(level)
	local r, g, b = 1, 0.82, 0
	local colorOf = GetCreatureDifficultyColor or GetQuestDifficultyColor
	if colorOf then
		local ok, color, cg, cb = pcall(colorOf, level)
		if ok and type(color) == "table" and type(color.r) == "number" then
			r, g, b = color.r, color.g, color.b
		elseif ok and type(color) == "number" and type(cg) == "number" and type(cb) == "number" then
			r, g, b = color, cg, cb
		end
	end
	return ("|cff%02x%02x%02x[%d]|r "):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), level)
end

---------------------------------------------------------------------------
-- Name format on the link label
---------------------------------------------------------------------------
E:RegisterNameFormatUser("Chat", { title = "Chat", order = 60,
	desc = "Name format of player names in chat lines. Only the shown name changes; whispering and the right-click menu still use the full name. On realms with regional names the realm part is left out too.",
	refresh = function() end })

local function Separator()
	local consts = Constants and Constants.CharacterNameSeparatorConsts
	return consts and consts.CHARACTERNAME_SURNAME_SEPARATOR or " "
end

function M:FormatSenderName(name)
	local mode = E.NameFormat and E:NameFormat("Chat") or "blizzard"
	if mode == "blizzard" or type(name) ~= "string" or name == "" then return name end
	if RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then name = name:gsub("%-[^%s]+$", "") end
	local sep = Separator():gsub("%p", "%%%0")
	local first, last = name:match("^(.-)" .. sep .. "(.+)$")
	if not (first and first ~= "" and last and last ~= "") then return name end
	return E:FormatName(first, last, mode)
end

---------------------------------------------------------------------------
-- Whisper markers
---------------------------------------------------------------------------
local WHISPER_TEMPLATES = {
	CHAT_MSG_WHISPER = { "CHAT_WHISPER_GET", "%s whispers: ", "in" },
	CHAT_MSG_WHISPER_INFORM = { "CHAT_WHISPER_INFORM_GET", "To %s: ", "out" },
	CHAT_MSG_BN_WHISPER = { "CHAT_BN_WHISPER_GET", "%s whispers: ", "in" },
	CHAT_MSG_BN_WHISPER_INFORM = { "CHAT_BN_WHISPER_INFORM_GET", "To %s: ", "out" },
}

-- The marker text: plain, at most 16 characters, no markup.
function M:MarkerText(which)
	local text = which == "in" and self.db.whisperIn or self.db.whisperOut
	text = tostring(text or ""):gsub("|", ""):sub(1, 16)
	if text == "" then text = which == "in" and ">" or "<" end
	return text
end

local function MarkerColor(which)
	if which == "in" then return unpack(E.media.accentColor) end
	return 0.65, 0.65, 0.7
end

-- The header around the sender link, from the client's own string.
local function WhisperHeader(event)
	local spec = WHISPER_TEMPLATES[event or ""]
	if not spec then return nil end
	local template = rawget(_G, spec[1])
	if type(template) ~= "string" or not template:find("%s", 1, true) then template = spec[2] end
	local before, after = template:match("^(.-)%%s(.*)$")
	return before, after, spec[3]
end
M.WhisperHeader = WhisperHeader

---------------------------------------------------------------------------
-- The line hook
---------------------------------------------------------------------------
local SENDER_LINK = "|H[BN]*player:.-|h.-|h"

function M:SenderDetails(text, event, args, frame)
	if type(Readable(text)) ~= "string" then return end
	if E.Secret(args) or (args ~= nil and (type(args) ~= "table" or (canaccesstable and not canaccesstable(args)))) then return end
	local db = self.db
	local markers = db.whisperMarkers and WHISPER_TEMPLATES[event or ""]
	local icons = db.nameIcons ~= "none"
	local levels = db.showLevel
	local names = E.NameFormat and E:NameFormat("Chat") ~= "blizzard"
	local social = event == "CHAT_MSG_GUILD" and E.modules.Social
	local guid = args and Readable(args[12])
	local main = social and social.GuildMainForChat and social:GuildMainForChat(guid)
	if not (markers or icons or levels or names or main) then return nil end
	local first, last = text:find(SENDER_LINK)
	if not first then return nil end
	local link = text:sub(first, last)
	local kind, payload, label = link:match("^|H(%a+):(.-)|h(.*)|h$")
	if not label then return nil end
	local sender = args and Readable(args[2])

	-- Inside the label: icons, then the formatted name.
	local inner = label:match("^%[(.*)%]$")
	if inner and kind == "player" then
		local color, name, reset = inner:match("^(|c%x%x%x%x%x%x%x%x)(.-)(|r)$")
		if not color then color, name, reset = "", inner, "" end
		if not name:find("|", 1, true) then
			if names then name = self:FormatSenderName(name) end
			local markup = ""
			if icons and not inner:find("|A", 1, true) and self:IconsWanted(event, args, frame) then markup = self:NameIconMarkup(guid) end
			label = "[" .. markup .. color .. name .. reset .. "]"
		end
	end
	local newLink = ("|H%s:%s|h%s|h"):format(kind, payload, label)

	-- In front of the link: the level.
	local level = levels and kind == "player" and self:LevelOf(guid, sender)
	local lead = level and self:LevelMarkup(level) or ""

	local before, after = text:sub(1, first - 1), text:sub(last + 1)
	if markers then
		local head, tail, which = WhisperHeader(event)
		if head and before:sub(-#head) == head and after:sub(1, #tail) == tail then
			local r, g, b = MarkerColor(which)
			before = before:sub(1, #before - #head) .. ("|cff%02x%02x%02x%s|r "):format(r * 255, g * 255, b * 255, self:MarkerText(which))
			after = ": " .. after:sub(#tail + 1)
		end
	end
	local tag = main and kind == "player" and (" (" .. main .. ")") or ""
	local result = before .. lead .. newLink .. tag .. after
	if result == text then return nil end
	return result
end

M:AddLineHook(50, function(text, r, g, b, event, args, frame)
	if not args then return nil end
	local result = M:SenderDetails(text, event, args, frame)
	if result then return result, r, g, b end
	return nil
end)

---------------------------------------------------------------------------
-- Alt-click a name to invite. Off by default. One Alt + left click
-- on a player link in chat sends exactly one group invite through the
-- game's own C_PartyInfo.InviteUnit; nothing is sent on its own, in combat,
-- or for a name the game keeps secret. Plain click (whisper), Shift-click
-- (insert the name) and right-click (menu) stay the game's own: this is a
-- hook after the game handled the click, and the whisper line the game
-- opens on any left click stays open.
---------------------------------------------------------------------------
function M:InviteName(link)
	if IsSecret(link) or type(link) ~= "string" then return nil end
	local name = link:match("^player:([^:]+)")
	if type(name) ~= "string" or IsSecret(name) or name == "" then return nil end
	local short = Ambiguate and Readable(Ambiguate(name, "none")) or name
	if E:IsMe(name) or E:IsMe(short) then return nil end
	return name
end

local lastInvite, lastInviteTime = nil, -1
function M:OnNameClick(link, button)
	if not (Improve() and self.db.altInvite) then return end
	if button ~= "LeftButton" or not (IsAltKeyDown and IsAltKeyDown()) then return end
	if (IsShiftKeyDown and IsShiftKeyDown()) or (IsControlKeyDown and IsControlKeyDown()) then return end
	if InCombatLockdown and InCombatLockdown() then return end
	local name = self:InviteName(link)
	if not name then return end
	local party = C_PartyInfo
	if not (party and party.InviteUnit) then return end
	-- One click, one invite: the same click can't reach here twice.
	local now = GetTime()
	if name == lastInvite and now - lastInviteTime < 0.2 then return end
	lastInvite, lastInviteTime = name, now
	party.InviteUnit(name)
end

if type(SetItemRef) == "function" then
	hooksecurefunc("SetItemRef", function(link, _, button) M:OnNameClick(link, button) end)
end

---------------------------------------------------------------------------
-- Keep keyword invites separate from the sound listener on the same event.
---------------------------------------------------------------------------
local whisperInviteOwner = {}
local listeningForInvite = false

local function WhisperInvitesOn()
	return Improve() and M.db.whisperInvite == true
end

local function QueueAllowsInvite()
	local inside, kind = E.PlainCallAll(IsInInstance)
	if type(inside) ~= "boolean" or type(kind) ~= "string" or kind == "pvp" or kind == "arena" then return false end
	local slots = E.PlainCall(GetMaxBattlefieldID)
	if type(slots) ~= "number" or slots < 0 or slots % 1 ~= 0 then return false end
	for index = 1, slots do
		if E.PlainCall(GetBattlefieldStatus, index) ~= "none" then return false end
	end
	local categories = rawget(_G, "NUM_LE_LFG_CATEGORYS")
	if E.Secret(categories) then return false end
	if categories ~= nil then
		if type(categories) ~= "number" or categories < 0 or categories % 1 ~= 0 or type(GetLFGMode) ~= "function" then return false end
		for category = 1, categories do
			local ok, mode = pcall(GetLFGMode, category)
			if not ok or E.Secret(mode) or (mode and mode ~= "lfgparty") then return false end
		end
	end
	return true
end

local function OnWhisperInvite(_, event, text, name, ...)
	if not WhisperInvitesOn() then return end
	if E.PlainCall(InCombatLockdown) ~= false or E.PlainCall(UnitAffectingCombat, "player") ~= false then return end
	if E.PlainCall(C_ChatInfo and C_ChatInfo.InChatMessagingLockdown) ~= false then return end
	local keyword = M.db.whisperInviteWord
	if E.Secret(keyword) or type(keyword) ~= "string" or not keyword:find("%S") then return end
	if E.Secret(text) or type(text) ~= "string" or text ~= keyword then return end
	if E.Secret(name) or type(name) ~= "string" or name == "" or name:find("[|%c]") then return end
	local guid, account = select(10, ...)
	if E.Secret(guid) or type(guid) ~= "string" or not guid:match("^Player%-%d+%-%x+$") or E.Secret(account) then return end
	local flags = select(4, ...)
	if E.Secret(flags) or flags == "GM" or flags == "DEV" then return end
	local myGUID = E.PlainCall(UnitGUID, "player")
	if type(myGUID) ~= "string" or guid == myGUID then return end
	local grouped = E.PlainCall(IsInGroup)
	if grouped ~= false and (grouped ~= true or (E.PlainCall(UnitIsGroupLeader, "player") ~= true
		and E.PlainCall(UnitIsGroupAssistant, "player") ~= true)) then return end
	local party = C_PartyInfo
	if not (party and E.PlainCall(party.CanInvite) == true and E.PlainCall(party.IsGUIDInGroup, guid) == false) then return end
	if E.PlainCall(C_FriendList and C_FriendList.IsIgnoredByGuid, guid) == true then return end
	if not QueueAllowsInvite() or (M.LineHidden and M:LineHidden(event, text, name, ...)) then return end
	-- Use the unmodified name from the event, including a surname or realm.
	-- The game's own invite confirmation still applies when it is needed.
	E.PlainCall(party.InviteUnit, name)
end

function M:RefreshWhisperInvites()
	local on = WhisperInvitesOn() and C_PartyInfo and type(C_PartyInfo.InviteUnit) == "function" or false
	if on == listeningForInvite then return end
	listeningForInvite = on
	if on then E:RegisterEvent("CHAT_MSG_WHISPER", OnWhisperInvite, whisperInviteOwner)
	else E:UnregisterEvent("CHAT_MSG_WHISPER", whisperInviteOwner) end
end

-- The keyword invite acts for the player: listed for the setup's Convenience
-- step and the Conveniences page (Core/Conveniences.lua), off until ticked
-- and never recommended.
E:RegisterConvenience({ id = "whisperInvite", module = "Chat", setting = "whisperInvite", order = 145,
	label = "Invite by whisper keyword",
	desc = "Acts for you: sends a group invite when a regular whisper matches your keyword exactly, out of combat. Set the keyword in Chat settings.",
	blocked = function() return E:BlizzardNeedsReason(M.element, "improve") end })
