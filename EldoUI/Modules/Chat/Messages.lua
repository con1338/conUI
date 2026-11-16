-- EldoUI Chat, part 2: everything EldoUI does with chat *messages*. All of
-- it is the "improve" switch of the Blizzard element chat-frames.
--
--   * Short channel names, clickable web links, keyword highlight and
--     EldoUI's own clickable timestamps. Blizzard writes the line first;
--     a post-hook on the chat frame's AddMessage then rewrites that one
--     line through the frame's secure TransformMessages. Nothing of
--     Blizzard's is replaced, so chat and the edit box stay untainted.
--   * Line hooks for the other chat files: colors and Quiet text
--     (Colors.lua), sender icons, levels, names and whisper markers
--     (Senders.lua).
--   * Icons on item and spell links, gear slots and types, quest status marks.
--   * Keyword alert: highlight, a sound and a taskbar flash, outside chat
--     lockdown only. EldoUI never answers for you.
--   * Whisper alert: an extra sound and taskbar flash on whispers.
--   * Spam filter: repeated lines and blocked words in public channels
--     (ChatFrameUtil.AddMessageEventFilter).
--   * Fading and scroll-back length (SetFading, SetTimeVisible, SetMaxLines).
--   * Chat history saved between sessions (EldoUIMessagesDB.chat, capped).
--   * Search in the selected window, and the right chat panel.
--   * Link tooltips on hover, typed lines kept between sessions, back to
--     the newest line after a while and a jump button, names of your
--     group, guild and friends in class color, a sound per channel.
--
-- Midnight rule: during chat lockdown the game hands addons chat text as a
-- secret value. Secret lines are shown exactly as Blizzard wrote them; they
-- are never read, compared, searched or saved.
-- Written from scratch for EldoUI; no code from other addons.
local _, E = ...
local L = E.L

local M = E:GetModule("Chat")

local IsSecret = function(value) return issecretvalue and issecretvalue(value) or false end
local Readable = E.Plain

local function Hex(r, g, b)
	return ("ff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

local function Improve()
	return M.active and M:Allowed("improve")
end

-- "No alert sounds in combat": keyword, whisper and channel sounds (and the
-- taskbar flash) are skipped while you are in combat; nothing is replayed
-- afterwards.
function M:QuietNow()
	return self.db.quietInCombat and InCombatLockdown() or false
end

local function InLockdown()
	return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() or false
end
M.InLockdown = InLockdown

-- One Yes/Cancel question for everything in chat that deletes saved data.
function M:Confirm(text, accept, cancel)
	-- Each answer runs once, however the popup closes.
	local data = {}
	local function Once(fn)
		return function()
			if data.answered then return end
			data.answered = true
			if fn then fn() end
		end
	end
	data.accept, data.cancel = Once(accept), Once(cancel)
	return E:ShowConfirm({ key = "ELDOUI_CHAT_CONFIRM", title = L["Chat"], text = text, accept = E:GameText(YES, L["Yes"]), danger = true,
		data = data, onAccept = function(own) own.accept() end, onCancel = function(own) own.cancel() end })
end

---------------------------------------------------------------------------
-- Saved data: EldoUIMessagesDB (per character) holds EIM's contacts and the
-- chat history and the acquired Alerts window identity. Older versions
-- kept contacts at the top level; version 2
-- moves each one into `contacts` (a contact already there keeps its place
-- and the older entry is set aside, never dropped). A registered saved
-- store (Core/Database.lua): a copy is kept before the move.
---------------------------------------------------------------------------
local OWN_KEYS = { contacts = true, chat = true, _alertWindow = true, _releasedAlertWindows = true, _quarantine = true }

E:RegisterStoreStep("EldoUIMessagesDB", 2, function(db)
	if type(db.contacts) ~= "table" then db.contacts = E:KeepInNewTable(db.contacts, "contacts") end
	local moving = {}
	for key, value in pairs(db) do
		if type(value) == "table" and not OWN_KEYS[key] then moving[#moving + 1] = key end
	end
	for _, key in ipairs(moving) do
		local value = db[key]
		db[key] = nil
		if db.contacts[key] == nil then
			db.contacts[key] = value
		else
			E:SavedDataChecker(db).Keep(tostring(key), value, "An older copy of this contact.")
		end
	end
end)

E:RegisterStore("EldoUIMessagesDB", { validate = function(db, C)
	C.Table(db, "contacts")
	C.Table(db, "chat")
	local alert = C.Table(db, "_alertWindow")
	for key, value in pairs(alert) do
		local valid = key == "index" and type(value) == "number" and value >= 1 and value % 1 == 0
			or key == "name" and type(value) == "string" and value ~= ""
			or key == "released" and type(value) == "boolean"
		if not valid then
			C.Keep("_alertWindow." .. tostring(key), value, "Expected a chat window index, name or release state.")
			alert[key] = nil
		end
	end
	local released = C.Table(db, "_releasedAlertWindows")
	for index, name in pairs(released) do
		if type(index) ~= "number" or index < 1 or index % 1 ~= 0 or type(name) ~= "string" or name == "" then
			C.Keep("_releasedAlertWindows." .. tostring(index), name, "Expected a chat window index and name.")
			released[index] = nil
		end
	end
end })

local messagesChecked = setmetatable({}, { __mode = "k" })

function E:GetMessagesDB()
	local db = EldoUIMessagesDB
	if type(db) ~= "table" then
		db = E:KeepInNewTable(db, "EldoUIMessagesDB")
		EldoUIMessagesDB = db
	end
	if not messagesChecked[db] then
		messagesChecked[db] = true
		E:MigrateStore("EldoUIMessagesDB", db)
	end
	if type(db.contacts) ~= "table" then db.contacts = {} end
	if type(db.chat) ~= "table" then db.chat = {} end
	return db
end

---------------------------------------------------------------------------
-- Links: find web addresses in a message and make them clickable
---------------------------------------------------------------------------
local TLDS = {}
for tld in ("com net org io gg dk de se no fi uk eu co tv me info app dev wtf gl ly to us ca fr nl be pl ru es it cz at ch"):gmatch("%a+") do TLDS[tld] = true end
-- Endings that are also everyday English words.
local WORD_TLDS = { no = true, it = true, me = true, us = true, to = true, be = true, at = true }

-- Stamped lines live in a small ring buffer.
local function Ring(size)
	local ring = { size = size, next = 0, items = {} }
	function ring:Add(value)
		self.next = self.next + 1
		self.items[self.next] = value
		self.items[self.next - self.size] = nil
		return self.next
	end
	function ring:Get(id) return self.items[id] end
	return ring
end
local stamped = Ring(300)

local function IsLink(word)
	if word:match("^%a[%w+.-]*://[^%s]+$") then return true end
	if word:match("^www%.[%w-]+%.[%w.-]+") then return true end
	if word:match("^discord%.gg/%w+") then return true end
	if word:match("^[%w._%%+-]+@[%w-]+%.[%w.-]*%a%a+$") then return true end
	if word:match("^%d+%.%d+%.%d+%.%d+:%d+") then return true end
	-- A bare address: no empty label ("wait...no") and no label that starts
	-- or ends with "-"; the ending is matched as typed (lowercase), so a
	-- sentence missing a space ("done.Be") stays plain.
	local host, rest = word:match("^([%w-]+%.[%w.-]+)(.*)$")
	if not host or host:find("..", 1, true) or host:find("%.$") or host:find("%-%.") or host:find("%.%-")
		or host:find("^%-") or host:find("%-$") then return false end
	local tld = host:match("%.(%a+)$")
	if not (tld and TLDS[tld]) then return false end
	-- Endings that are also common words ("nice.to", "ok.me") need a path.
	if WORD_TLDS[tld] then return rest:match("^[/:]%S") ~= nil end
	return rest == "" or rest:match("^[/:]") ~= nil
end

local function LinkWord(word)
	if word:find("|", 1, true) then return word end
	local lead, core, tail = word:match("^([%(%[\"']*)(.-)([%.,;:!%?%)%]\"']*)$")
	if not core or core == "" or not IsLink(core) then return word end
	local color
	if M.db.urlAccent then color = Hex(unpack(E.media.accentText)) else color = Hex(unpack(M.db.urlColor)) end
	local shown = M.db.urlBrackets and ("[" .. core .. "]") or core
	-- The address itself is the link payload, so links in saved history
	-- still work after a reload.
	return ("%s|c%s|Haddon:EldoUIURL:%s|h%s|h|r%s"):format(lead, color, core:sub(1, 1000), shown, tail)
end

local function LinkPlain(text)
	return (text:gsub("%S+", LinkWord))
end

-- Run fn on the plain parts of a line; item, spell, player and other
-- hyperlinks stay untouched.
local function EachPlain(text, fn)
	local out, pos = {}, 1
	while true do
		local first, last = text:find("|H.-|h.-|h", pos)
		if not first then
			out[#out + 1] = fn(text:sub(pos))
			break
		end
		out[#out + 1] = fn(text:sub(pos, first - 1))
		out[#out + 1] = text:sub(first, last)
		pos = last + 1
	end
	return table.concat(out)
end

---------------------------------------------------------------------------
-- Short channel names: [2. Trade - City] becomes [2] or [Trade], [Guild] [G]
---------------------------------------------------------------------------
local SHORT = {
	GUILD = "G", OFFICER = "O", PARTY = "P", PARTY_LEADER = "PL", RAID = "R", RAID_LEADER = "RL",
	RAID_WARNING = "RW", INSTANCE_CHAT = "I", INSTANCE_CHAT_LEADER = "IL", BATTLEGROUND = "BG",
	BATTLEGROUND_LEADER = "BL", GUILD_DISCORD = "GD",
}

local function ShortChannel(payload, label)
	local number, rest = label:match("^(%d+)%.%s*(.*)$")
	if number then
		if M.db.channelStyle == "name" and rest and rest ~= "" then
			rest = rest:gsub("%s+%-%s+.*$", "")
			return ("|Hchannel:%s|h[%s]|h"):format(payload, rest)
		end
		return ("|Hchannel:%s|h[%s]|h"):format(payload, number)
	end
	local short = SHORT[(payload:match("([%w_]+)$") or ""):upper()]
	if short then return ("|Hchannel:%s|h[%s]|h"):format(payload, short) end
	return nil
end

---------------------------------------------------------------------------
-- Keywords
---------------------------------------------------------------------------
local keywordList = {}   -- lower-case words
local keywordEntries = {} -- the same order: the db entry (word, sound) or the name entry
local keywordSource      -- the settings the list was built from

local function SplitList(text)
	local list = {}
	for word in tostring(text or ""):gmatch("[^,]+") do
		word = strtrim(word):lower()
		if word ~= "" then list[#list + 1] = word end
	end
	return list
end
M.SplitList = SplitList

-- The keyword list lives in Alerts.lua (word and sound per entry);
-- this is the matching side. Built again after any change to the list.
local function BuildKeywords()
	local name = E:PlayerName()
	if type(name) ~= "string" or IsSecret(name) then name = "" end
	local source = tostring(M.db.keywordName) .. "|" .. name .. "|" .. tostring(M.db.keywordList)
	if source == keywordSource then return keywordList end
	keywordSource = source
	keywordList, keywordEntries = {}, {}
	for _, entry in ipairs(M.db.keywordList or {}) do
		if type(entry) == "table" and type(entry.word) == "string" and entry.word ~= "" then
			keywordList[#keywordList + 1] = entry.word:lower()
			keywordEntries[#keywordEntries + 1] = entry
		end
	end
	if M.db.keywordName and name ~= "" then
		keywordList[#keywordList + 1] = name:lower()
		keywordEntries[#keywordEntries + 1] = { word = name, isName = true }
	end
	return keywordList
end
M.InvalidateKeywords = function() keywordSource = nil end

local function IsWordChar(char)
	return char ~= "" and char:match("[%w\128-\255]") ~= nil
end

-- Positions of whole-word matches in `text` (case-insensitive), or nil.
local function FindWord(lower, word, start)
	local from = start or 1
	while true do
		local first, last = lower:find(word, from, true)
		if not first then return nil end
		if not IsWordChar(lower:sub(first - 1, first - 1)) and not IsWordChar(lower:sub(last + 1, last + 1)) then
			return first, last
		end
		from = last + 1
	end
end
M.FindWord = FindWord

-- The first keyword entry the message mentions, or nil.
local function Mentions(message)
	if type(message) ~= "string" or message == "" then return nil end
	local lower = message:lower()
	for index, word in ipairs(BuildKeywords()) do
		if FindWord(lower, word) then return keywordEntries[index] end
	end
	return nil
end

local function HighlightPlain(text)
	local words = keywordList
	if #words == 0 or text == "" then return text end
	local color = M.db.keywordAccent and Hex(unpack(E.media.accentText)) or Hex(unpack(M.db.keywordColor))
	for _, word in ipairs(words) do
		local lower = text:lower()
		local out, pos = {}, 1
		local first, last = FindWord(lower, word, 1)
		if first then
			while first do
				out[#out + 1] = text:sub(pos, first - 1)
				out[#out + 1] = ("|c%s%s|r"):format(color, text:sub(first, last))
				pos = last + 1
				first, last = FindWord(lower, word, pos)
			end
			out[#out + 1] = text:sub(pos)
			text = table.concat(out)
		end
	end
	return text
end

local PLAYER_EVENTS = {
	CHAT_MSG_CHANNEL = "public", CHAT_MSG_SAY = "public", CHAT_MSG_YELL = "public",
	CHAT_MSG_GUILD = "all", CHAT_MSG_OFFICER = "all", CHAT_MSG_PARTY = "all", CHAT_MSG_PARTY_LEADER = "all",
	CHAT_MSG_RAID = "all", CHAT_MSG_RAID_LEADER = "all", CHAT_MSG_RAID_WARNING = "all",
	CHAT_MSG_INSTANCE_CHAT = "all", CHAT_MSG_INSTANCE_CHAT_LEADER = "all", CHAT_MSG_WHISPER = "all",
	CHAT_MSG_BN_WHISPER = "all", CHAT_MSG_EMOTE = "all", CHAT_MSG_COMMUNITIES_CHANNEL = "all",
}

local function IsMe(sender)
	sender = Readable(sender)
	if type(sender) ~= "string" then return false end
	local name = E:PlayerName()
	return type(name) == "string" and Ambiguate(sender, "none") == name
end
M.IsMe = IsMe

-- The keyword entry a line matches (in scope, readable, not your own
-- line, keywords not paused), or nil. Secret lines never match.
local function MatchKeyword(event, eventArgs)
	local scope = event and PLAYER_EVENTS[event]
	if not scope or type(eventArgs) ~= "table" or M.db.keywordsPaused then return nil end
	if IsSecret(eventArgs) or (canaccesstable and not canaccesstable(eventArgs)) then return nil end
	if M.db.keywordScope == "public" and scope ~= "public" then return nil end
	if InLockdown() then return nil end
	local message = Readable(eventArgs[1])
	if type(message) ~= "string" or IsMe(eventArgs[2]) then return nil end
	return Mentions(message)
end
M.MatchKeyword = MatchKeyword
M.KEYWORD_EVENTS = PLAYER_EVENTS

-- Returns true when this line should be highlighted; the sound and flash
-- (Alerts.lua) come once per line, however many windows show it.
local function CheckKeywords(event, eventArgs)
	local entry = MatchKeyword(event, eventArgs)
	if not entry then return false end
	if M.OnKeywordMatch then M:OnKeywordMatch(Readable(eventArgs[11]), entry) end
	return true
end

---------------------------------------------------------------------------
-- Name mentions in class color: names of your group, guild and
-- friends inside other players' lines. The class comes from the game's
-- roster data; the list is rebuilt (lazily) when a roster changes.
---------------------------------------------------------------------------
local nameClass = {}      -- lower-case name -> class file
local namesDirty = true
local excluded, excludedSource = {}, nil

local function ShortName(name)
	name = Readable(name)
	if type(name) ~= "string" or name == "" then return nil end
	return (name:match("^[^%-]+"))
end

local function AddName(name, class)
	name, class = ShortName(name), Readable(class)
	if name and type(class) == "string" and #name >= 3 then nameClass[name:lower()] = class end
end

local function BuildNames()
	if not namesDirty then return end
	namesDirty = false
	wipe(nameClass)
	local db = M.db
	local me = E:PlayerName()
	if db.mentionGroup and IsInGroup and IsInGroup() then
		local raid = IsInRaid and IsInRaid()
		for index = 1, raid and 40 or 4 do
			local unit = (raid and "raid" or "party") .. index
			if UnitExists(unit) and not UnitIsUnit(unit, "player") then
				AddName(UnitName(unit), select(2, UnitClass(unit)))
			end
		end
	end
	if db.mentionGuild and IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
		for index = 1, math.min(GetNumGuildMembers() or 0, 2000) do
			local name, _, _, _, _, _, _, _, _, _, class = GetGuildRosterInfo(index)
			AddName(name, class)
		end
	end
	if db.mentionFriends and C_FriendList and C_FriendList.GetNumFriends and GetPlayerInfoByGUID then
		for index = 1, C_FriendList.GetNumFriends() or 0 do
			local info = C_FriendList.GetFriendInfoByIndex(index)
			local guid = info and Readable(info.guid)
			if type(guid) == "string" and guid ~= "" then
				local _, class = GetPlayerInfoByGUID(guid)
				AddName(info.name, class)
			end
		end
	end
	if type(me) == "string" then nameClass[me:lower()] = nil end
end

local function IsExcluded(lower)
	if excludedSource ~= M.db.mentionExclude then
		excludedSource = M.db.mentionExclude
		excluded = {}
		for _, word in ipairs(SplitList(M.db.mentionExclude)) do excluded[word] = true end
	end
	return excluded[lower]
end

local function MentionPlain(text)
	if text == "" or not next(nameClass) then return text end
	return (text:gsub("[%w\128-\255]+", function(word)
		local lower = word:lower()
		local class = nameClass[lower]
		if not class or IsExcluded(lower) then return nil end
		local r, g, b = E:GetClassColor(class)
		if not r then return nil end
		return ("|c%s%s|r"):format(Hex(r, g, b), word)
	end))
end

-- Mentions are colored in players' lines only, and never during boss fights.
local function WantsMentions(event)
	if not (M.db.mentions and event and PLAYER_EVENTS[event]) then return false end
	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return false end
	BuildNames()
	return next(nameClass) ~= nil
end

---------------------------------------------------------------------------
-- EldoUI timestamps: gray and clickable (copies the line)
---------------------------------------------------------------------------
-- time (optional): the time the line was first seen, for a copy made later.
local function Stamp(text, time)
	-- The raw line; it becomes plain text only when its stamp is clicked.
	local id = stamped:Add(text)
	local color = Hex(unpack(M.db.timestampColor))
	return ("|c%s|Haddon:EldoUITime:%d|h[%s]|h|r %s"):format(color, id, time or E:FormatTime(), text)
end

---------------------------------------------------------------------------
-- Link extras: icons, gear slots and types, and a mark after quest links.
-- The icon and gear information change only the displayed label.
-- The link data stays intact, so clicks and tooltips work
-- as before. Items the client hasn't loaded yet are requested (at most 100
-- waiting at once; one the game never answers makes room after 10 seconds)
-- and their lines updated when the data arrives.
---------------------------------------------------------------------------
local QUEST_DONE_ATLAS = "common-icon-checkmark"
local QUEST_DONE_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local QUEST_ACTIVE_TEXTURE = "Interface\\GossipFrame\\ActiveQuestIcon"
local itemWaiting, itemRequests = {}, 0   -- itemID -> request time while waiting
local itemReady = {}                     -- answered requests held through chat lockdown
local ITEM_MAX, ITEM_WAIT = 100, 10

local function AtlasExists(atlas)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) and true or false
end

local function QuestMark(questID)
	if not (C_QuestLog and questID) then return nil end
	local done = C_QuestLog.IsQuestFlaggedCompleted and Readable(C_QuestLog.IsQuestFlaggedCompleted(questID))
	if done == true then
		if AtlasExists(QUEST_DONE_ATLAS) then return ("|A:%s:0:0|a"):format(QUEST_DONE_ATLAS) end
		return ("|T%s:0|t"):format(QUEST_DONE_TEXTURE)
	end
	local active = C_QuestLog.IsOnQuest and Readable(C_QuestLog.IsOnQuest(questID))
	if active == true then return ("|T%s:0|t"):format(QUEST_ACTIVE_TEXTURE) end
	return nil
end

local QUEST_MARK_STARTS = { "|A:" .. QUEST_DONE_ATLAS, "|T" .. QUEST_DONE_TEXTURE, "|T" .. QUEST_ACTIVE_TEXTURE }

local function HasQuestMark(text, pos)
	for _, start in ipairs(QUEST_MARK_STARTS) do
		if text:sub(pos, pos + #start - 1) == start then return true end
	end
	return false
end

local function LinkIconOf(kind, id)
	local icon
	if kind == "item" and C_Item and C_Item.GetItemIconByID then
		icon = Readable(C_Item.GetItemIconByID(id))
	elseif kind == "spell" and C_Spell and C_Spell.GetSpellTexture then
		icon = Readable(C_Spell.GetSpellTexture(id))
	end
	if type(icon) == "number" or (type(icon) == "string" and icon ~= "") then return icon end
	return nil
end

local function Unwait(id)
	if itemWaiting[id] then
		itemWaiting[id], itemReady[id] = nil, nil
		itemRequests = math.max(itemRequests - 1, 0)
	end
end

local function RequestItem(id)
	if not (C_Item and C_Item.RequestLoadItemDataByID) then return end
	local now = GetTime()
	local since = itemWaiting[id]
	if itemReady[id] or (since and now - since < ITEM_WAIT) then return true end
	Unwait(id)
	if itemRequests >= ITEM_MAX then
		for waiting, at in pairs(itemWaiting) do
			if not itemReady[waiting] and now - at >= ITEM_WAIT then Unwait(waiting) end
		end
		if itemRequests >= ITEM_MAX then return end
	end
	itemWaiting[id] = now
	itemRequests = itemRequests + 1
	C_Item.RequestLoadItemDataByID(id)
	return true
end
M.ItemRequestsWaiting = function() return itemRequests end

-- A colored suffix inside the brackets. A color/reset without visible text
-- marks only readable links whose item data is still loading.
local ITEM_TYPE_COLOR = E:TextHex("secondary")
local ITEM_TYPE_MARK = ITEM_TYPE_COLOR .. " · "
local ITEM_TYPE_PENDING = ITEM_TYPE_COLOR .. "|r"
local ITEM_LINK = "|H(%a+):(%d+)([^|]*)|h(.-)|h"
local ITEM_TYPE_PATTERN = ITEM_TYPE_MARK:gsub("%p", "%%%0") .. "[^|]+|r|c%x%x%x%x%x%x%x%x%]$"
local ITEM_TYPE_NO_COLOR = ITEM_TYPE_MARK:gsub("%p", "%%%0") .. "[^|]+|r%]$"
local PENDING_PATTERN = ITEM_TYPE_PENDING .. "|c%x%x%x%x%x%x%x%x%]$"
local PENDING_NO_COLOR = ITEM_TYPE_PENDING .. "%]$"
local itemTypesInChat, clearItemTypes
local itemRestrictionOwner = {}

local function StripTypeLabel(label)
	local clean, count = label:gsub(ITEM_TYPE_PATTERN, "]", 1)
	if count == 0 then clean, count = label:gsub(ITEM_TYPE_NO_COLOR, "]", 1) end
	return clean, count > 0
end

local function StripPendingLabel(label)
	local clean, count = label:gsub(PENDING_PATTERN, "]", 1)
	if count == 0 then clean, count = label:gsub(PENDING_NO_COLOR, "]", 1) end
	return clean, count > 0
end

local function StripItemTypes(text)
	if not text:find(ITEM_TYPE_COLOR, 1, true) then return text end
	return (text:gsub(ITEM_LINK, function(kind, id, rest, label)
		if kind ~= "item" then return nil end
		local clean, marked = StripTypeLabel(label)
		local plain, pending = StripPendingLabel(clean)
		if marked or pending then return ("|Hitem:%s%s|h%s|h"):format(id, rest, plain) end
	end))
end

local function ItemType(id)
	local getter = C_Item and C_Item.GetItemInfoInstant
	if type(getter) ~= "function" then return end
	local ok, resolved, _, subtype, equip, _, class = pcall(getter, id)
	if not ok or IsSecret(resolved) or IsSecret(subtype) or IsSecret(equip) or IsSecret(class) then return end
	if resolved == nil then return nil, true end
	if resolved ~= id or type(equip) ~= "string" or not equip:match("^INVTYPE_[A-Z0-9_]+$")
		or equip == "INVTYPE_NON_EQUIP" or equip == "INVTYPE_NON_EQUIP_IGNORE" then return end
	local slot = Readable(rawget(_G, equip))
	if type(slot) ~= "string" or slot == "" or slot:find("|", 1, true) then return end
	local classes = Enum and Enum.ItemClass
	if classes and (class == classes.Weapon or class == classes.Armor) and type(subtype) == "string"
		and subtype ~= "" and subtype ~= slot and not subtype:find("|", 1, true) then
		return slot .. ", " .. subtype
	end
	return slot
end

local function LinkExtras(text, itemOnly, failed)
	local db = M.db
	local icons, marks, itemTypes = db.linkIcons, db.questMarks, db.linkItemTypes
	if not (icons or marks or itemTypes or itemOnly) or IsSecret(text) or not text:find("|H", 1, true) then return text end
	local out, pos = {}, 1
	while true do
		local first, last, kind, id, rest, label = text:find(ITEM_LINK, pos)
		if not first then break end
		out[#out + 1] = text:sub(pos, first - 1)
		pos = last + 1
		local number, added = tonumber(id), label
		if number and number > 0 and number < math.huge and (not itemOnly or (kind == "item" and number == itemOnly)) then
			if kind == "item" then
				local clean, pending = StripPendingLabel(label)
				added = clean
				if not failed and itemTypes and (pending or not itemOnly) and clean:sub(-1) == "]" then
					local _, marked = StripTypeLabel(clean)
					if not marked then
						local details, uncached = ItemType(number)
						if details or (uncached and not itemOnly and RequestItem(number)) then
							local color = text:sub(math.max(1, first - 10), first - 1)
							if not color:match("^|c%x%x%x%x%x%x%x%x$") then color = "" end
							local suffix = details and (ITEM_TYPE_MARK .. details .. "|r") or ITEM_TYPE_PENDING
							added = clean:sub(1, -2) .. suffix .. color .. "]"
							itemTypesInChat = true
						end
					end
				end
			end
			if not failed and icons and (kind == "item" or kind == "spell") and not label:find("^|T") then
				local icon = LinkIconOf(kind, number)
				if icon then
					added = ("|T%s:0|t%s"):format(tostring(icon), added)
				elseif kind == "item" and not itemOnly then
					RequestItem(number)
				end
			end
		end
		out[#out + 1] = added == label and text:sub(first, last) or ("|H%s:%s%s|h%s|h"):format(kind, id, rest, added)
		if not itemOnly and marks and kind == "quest" then
			-- After the link's color end, so the mark keeps its own colors.
			if text:sub(pos, pos + 1) == "|r" then
				out[#out + 1] = "|r"
				pos = pos + 2
			end
			if not HasQuestMark(text, pos) then
				local mark = QuestMark(number)
				if mark then out[#out + 1] = mark end
			end
		end
	end
	out[#out + 1] = text:sub(pos)
	return table.concat(out)
end
M.LinkExtras = LinkExtras

local function TransformLinkMessages(needle, transform, bareLink)
	local function Match(message)
		return type(message) == "string" and not IsSecret(message)
			and (message:find(needle, 1, true) ~= nil or (bareLink and message:find(bareLink, 1, true) ~= nil))
	end
	local function RewriteLink(message, ...)
		return transform(message), ...
	end
	for _, frame in M:IterateFrames() do frame:TransformMessages(Match, RewriteLink) end
	local panel = M.rightPanel
	if panel and panel.messages then panel.messages:TransformMessages(Match, RewriteLink) end
end

local function ApplyItemTypes()
	if not itemTypesInChat or InLockdown() then return end
	if clearItemTypes or not Improve() or not M.db.linkItemTypes then
		TransformLinkMessages(ITEM_TYPE_COLOR, StripItemTypes)
		itemTypesInChat, clearItemTypes = nil, nil
	end
end

local function FinishItem(itemID, success)
	Unwait(itemID)
	if not Improve() then return end
	local needle = "|Hitem:" .. tostring(itemID)
	TransformLinkMessages(needle .. ":", function(message) return LinkExtras(message, itemID, not success) end, needle .. "|h")
end

local function RefreshUnlockedLinks()
	if InLockdown() then return end
	ApplyItemTypes()
	for itemID, result in pairs(itemReady) do FinishItem(itemID, result == "ready") end
	if not M.active then E:UnregisterEvent("ADDON_RESTRICTION_STATE_CHANGED", itemRestrictionOwner) end
end

-- An item arrived: finish only that item's extras in its chat lines.
function M:OnItemData(itemID, success)
	if IsSecret(itemID) or type(itemID) ~= "number" or not itemWaiting[itemID] then return end
	local loaded = not IsSecret(success) and success == true
	if InLockdown() then
		itemReady[itemID] = loaded and "ready" or "failed"
	else
		FinishItem(itemID, loaded)
	end
end

---------------------------------------------------------------------------
-- The rewrite of one line
---------------------------------------------------------------------------
local function Rewrite(text, highlight, mentions, time)
	local db = M.db
	if db.shortChannels then
		text = text:gsub("|Hchannel:([^|]-)|h%[([^%]]-)%]|h", ShortChannel)
	end
	if (db.linkIcons or db.questMarks or db.linkItemTypes) and not InLockdown() then
		if clearItemTypes then ApplyItemTypes() end
		text = LinkExtras(text)
	end
	if db.urls or highlight or mentions then
		text = EachPlain(text, function(plain)
			if db.urls then plain = LinkPlain(plain) end
			if highlight or mentions then
				-- Links made above are hyperlinks now; color the rest.
				plain = EachPlain(plain, function(rest)
					if mentions then rest = MentionPlain(rest) end
					if highlight then rest = HighlightPlain(rest) end
					return rest
				end)
			end
			return plain
		end)
	end
	if db.eldoTimestamps then text = Stamp(text, time) end
	return text
end
M.RewriteLine = Rewrite

---------------------------------------------------------------------------
-- Right panel groups
---------------------------------------------------------------------------
local GROUP_EVENTS = {
	loot = { "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CHAT_MSG_CURRENCY" },
	skills = { "CHAT_MSG_SKILL", "CHAT_MSG_TRADESKILLS", "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_COMBAT_HONOR_GAIN",
		"CHAT_MSG_COMBAT_FACTION_CHANGE" },
	channels = { "CHAT_MSG_CHANNEL" },
	guild = { "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_GUILD_ACHIEVEMENT", "CHAT_MSG_GUILD_ITEM_LOOTED" },
	group = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
		"CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" },
	whisper = { "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM" },
	system = { "CHAT_MSG_SYSTEM" },
	npc = { "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_EMOTE", "CHAT_MSG_MONSTER_WHISPER",
		"CHAT_MSG_MONSTER_PARTY", "CHAT_MSG_RAID_BOSS_EMOTE", "CHAT_MSG_RAID_BOSS_WHISPER" },
}
local EVENT_GROUP = {}
for group, events in pairs(GROUP_EVENTS) do
	for _, event in ipairs(events) do EVENT_GROUP[event] = group end
end

local function RightGroup(event)
	if not event or not M.db.rightPanel or not M.rightPanel then return nil end
	local group = EVENT_GROUP[event]
	return group and M.db.rightGroups[group] and group or nil
end

local mirrored = {}      -- lineID -> true
local mirroredCount = 0

-- Copy a line into the right panel once, however many windows show it.
-- Returns true when the line is in the right panel (now or already).
local function Mirror(frame, text, r, g, b, eventArgs, event)
	local lineID = type(eventArgs) == "table" and Readable(eventArgs[11])
	if lineID then
		if mirrored[lineID] then return true end
		mirrored[lineID] = true
		mirroredCount = mirroredCount + 1
		if mirroredCount > 400 then wipe(mirrored); mirroredCount = 0 end
	elseif frame ~= DEFAULT_CHAT_FRAME then
		-- The game keeps the line ID secret: copy from the main window only.
		return false
	end
	-- The event goes with the copy, so the saved history knows a whisper.
	M.rightPanel.messages:AddMessage(text, r, g, b, nil, nil, nil, event)
	return true
end

---------------------------------------------------------------------------
-- The post-hook: Blizzard has added a line; adjust that one line
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Line hooks: the other chat files add their part of the rewrite here
-- (colors, sender details). fn(text, r, g, b, event, eventArgs, frame)
-- returns the new text and color (or nil to leave the line alone).
---------------------------------------------------------------------------
local lineHooks = {}

function M:AddLineHook(order, fn)
	lineHooks[#lineHooks + 1] = { order = order, fn = fn }
	table.sort(lineHooks, function(a, b) return a.order < b.order end)
end

-- Event arguments the client lets addons read, or nil.
local function ReadableArgs(eventArgs)
	if type(eventArgs) ~= "table" then return nil end
	if canaccesstable and not canaccesstable(eventArgs) then return nil end
	return eventArgs
end
M.ReadableArgs = ReadableArgs

-- The whole rewrite of one (readable) line, without side effects: the
-- chat windows, the Alert tab copies and the options preview use it.
-- time (optional): the stamp a copy keeps (the Alerts tab).
local function Format(frame, text, r, g, b, event, eventArgs, highlight, time)
	local args = ReadableArgs(eventArgs)
	local ok, result = pcall(Rewrite, text, highlight, WantsMentions(event), time)
	if ok and type(result) == "string" then text = result end
	for _, hook in ipairs(lineHooks) do
		local done, newText, nr, ng, nb = pcall(hook.fn, text, r, g, b, event, args, frame)
		if not done then
			geterrorhandler()(newText)
		elseif type(newText) == "string" then
			text, r, g, b = newText, nr or r, ng or g, nb or b
		end
	end
	return text, r, g, b
end
M.FormatLine = Format


-- The line being rewritten, read by the two callbacks below: one pair of
-- functions for every line, not two new ones per line.
local rewriting = {}
local function SameArgs(_, _, _, _, _, _, _, _, args)
	return args == rewriting.args
end
local function IsThisLine(message, _, _, _, _, _, _, _, args)
	if rewriting.done then return false end
	if rewriting.byArgs then
		if args ~= rewriting.args then return false end
	elseif IsSecret(message) or message ~= rewriting.text then
		return false
	end
	rewriting.done = true
	return true
end
local function RewriteLine(_, _, _, _, ...)
	return rewriting.rewritten, rewriting.r, rewriting.g, rewriting.b, ...
end

local function OnAddMessage(frame, text, r, g, b, _, _, _, event, eventArgs, formatter)
	if not Improve() then return end
	-- A whisper Instant Messages shows in its own window and takes out of
	-- this one: no rewrite, right-panel copy, keyword alert or
	-- Alerts tab copy.
	local eim = E.modules and E.modules.Messages
	if eim and eim.TakesChatLine and eim:TakesChatLine(event, eventArgs) then return end
	-- The Alerts tab only holds copies that are already rewritten.
	if M.IsAlertFrame and M:IsAlertFrame(frame) then
		if M.MarkNewBelow then M:MarkNewBelow(frame) end
		return
	end
	local secret = IsSecret(text)
	if type(text) ~= "string" and not secret then return end

	local group = RightGroup(event)
	local rewritten, nr, ng, nb = text, r, g, b
	if not secret then
		local highlight = CheckKeywords(event, eventArgs)
		if event == "CHAT_MSG_CHANNEL" and M.ReadTradeLine then M:ReadTradeLine(text, eventArgs, formatter) end
		rewritten, nr, ng, nb = Format(frame, text, r, g, b, event, eventArgs, highlight)
	end
	-- A line arrived while this window is scrolled up: mark the jump button.
	if M.MarkNewBelow then M:MarkNewBelow(frame) end

	if group then
		local copied = Mirror(frame, rewritten, nr, ng, nb, eventArgs, event)
		if copied and M.db.rightMove and type(eventArgs) == "table" then
			rewriting.args = eventArgs
			frame:RemoveMessagesByPredicate(SameArgs)
			rewriting.args = nil
			return
		end
	end

	if secret or (rewritten == text and nr == r and ng == g and nb == b) then return end
	-- Find the new entry: Blizzard's lines carry their own eventArgs table,
	-- so the identity picks exactly this line. Lines added by other code
	-- have none; then the first entry still holding the raw text is used
	-- (any such entry gets the same rewrite).
	rewriting.done, rewriting.byArgs, rewriting.args, rewriting.text = false, type(eventArgs) == "table", eventArgs, text
	rewriting.rewritten, rewriting.r, rewriting.g, rewriting.b = rewritten, nr, ng, nb
	frame:TransformMessages(IsThisLine, RewriteLine)
	rewriting.args, rewriting.text, rewriting.rewritten = nil, nil, nil
end

local hookedFrames = setmetatable({}, { __mode = "k" })
local original = setmetatable({}, { __mode = "k" }) -- frame -> { fading, time, duration, lines }

function M:StyleMessages(frame)
	if not hookedFrames[frame] then
		hookedFrames[frame] = true
		hooksecurefunc(frame, "AddMessage", OnAddMessage)
		-- Shift + mouse wheel jumps to the top or bottom; any wheel turn
		-- restarts the "back to the bottom" timer.
		frame:HookScript("OnMouseWheel", function(scrolled, delta)
			if not Improve() then return end
			M:NoteScroll(scrolled)
			if IsShiftKeyDown() then
				if delta > 0 then scrolled:ScrollToTop() else scrolled:ScrollToBottom() end
			end
		end)
	end
	local db = self.db
	local improve = self.active and self:Allowed("improve")
	local changeFade = improve and db.fade ~= "KEEP"
	local changeLines = improve and (db.maxLines or 0) > 0
	if (changeFade or changeLines) and not original[frame] then
		original[frame] = {
			fading = frame.GetFading and frame:GetFading(),
			time = frame.GetTimeVisible and frame:GetTimeVisible(),
			duration = frame.GetFadeDuration and frame:GetFadeDuration(),
			lines = frame.GetMaxLines and frame:GetMaxLines(),
		}
	end
	local saved = original[frame]
	if changeFade then
		if db.fade == "never" then
			frame:SetFading(false)
		else
			frame:SetFading(true)
			frame:SetTimeVisible(db.fadeTime)
			frame:SetFadeDuration(db.fadeDuration)
		end
	elseif saved and saved.fading ~= nil then
		frame:SetFading(saved.fading)
		if saved.time then frame:SetTimeVisible(saved.time) end
		if saved.duration then frame:SetFadeDuration(saved.duration) end
	end
	if changeLines then
		if frame:GetMaxLines() ~= db.maxLines then frame:SetMaxLines(db.maxLines) end
	elseif saved and saved.lines and frame:GetMaxLines() ~= saved.lines then
		frame:SetMaxLines(saved.lines)
	end
	if not changeFade and not changeLines then original[frame] = nil end
end

---------------------------------------------------------------------------
-- Message event filters: repeated lines, blocked phrases, the script
-- filter and channel mutes all decide in Filters.lua (M.FilterLine).
-- A hidden line never reaches a chat window, the Alert tab or history.
---------------------------------------------------------------------------
local function MessageFilter(frame, event, ...)
	if not (Improve() and M.FilterLine) then return false end
	local ok, hide = pcall(M.FilterLine, M, event, ...)
	if ok and not hide and event == "CHAT_MSG_SYSTEM" then
		ok, hide = pcall(M.FoldRoster, M, frame, ...)
	end
	if not ok then
		geterrorhandler()(hide)
		return false
	end
	return hide and true or false
end
M.MessageFilter = MessageFilter

local filtersAdded = false
local function AddFilters()
	if filtersAdded then return end
	filtersAdded = true
	local addFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
	if addFilter then
		for _, event in ipairs(M.FILTER_EVENTS or {}) do addFilter(event, MessageFilter) end
	end
end

---------------------------------------------------------------------------
-- Link popup: link selected, Ctrl+C copies, closes itself
---------------------------------------------------------------------------
local popup

-- The kit's dialog shell with one edit line (header-font title, accent
-- line, an X, Escape closes it).
local function CreatePopup()
	local Kit = E.UIKit
	popup = Kit.CreateDialog("EldoUI_LinkCopy", { width = 360, strata = "DIALOG", edit = {}, closeButton = true })
	local box = popup.edit
	popup.box = box

	box:HookScript("OnTextChanged", function(self, user)
		if user and popup.url then self:SetText(popup.url); self:HighlightText() end
	end)
	box:SetScript("OnEscapePressed", function() popup:Hide() end)
	box:SetScript("OnEnterPressed", function() popup:Hide() end)
	box:HookScript("OnEditFocusLost", function()
		-- The X takes the focus away on its way to closing the pop-up.
		if not (popup.close and popup.close:IsMouseOver()) then popup:Hide() end
	end)
	box:SetScript("OnKeyDown", function(_, key)
		if key == "C" and IsControlKeyDown() then
			popup:SetText(L["Copied!"])
			Kit.Paint(popup.text, "good")
			if M.db.urlAutoClose then C_Timer.After(0.6, function() popup:Hide() end) end
		end
	end)
	popup:HookScript("OnHide", function() box:ClearFocus() end)
end

function M:ShowLinkPopup(url, title)
	if not popup then CreatePopup() end
	local Kit = E.UIKit
	popup.url = url
	popup:SetTitle(title or L["Copy link"])
	popup:SetText(L["Press Ctrl+C to copy, then Escape."])
	Kit.Paint(popup.text, "secondary")
	local width = math.min(math.max(360, #url * 7 + 30), 700)
	popup:SetWidth(width)
	popup.box:SetWidth(width - 2 * Kit.DIALOG_PAD)
	local scale = UIParent:GetEffectiveScale()
	local x, y = GetCursorPosition()
	popup:ClearAllPoints()
	popup:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale - 20, y / scale + 8)
	popup:Show()
	popup.box:SetText(url)
	popup.box:SetFocus()
	popup.box:SetCursorPosition(0)
	popup.box:HighlightText()
end

local lastLink, lastTime = nil, 0
local function OnLink(link)
	if type(link) ~= "string" or IsSecret(link) then return end
	local kind, id = link:match("^addon:(EldoUI%a+):(.+)$")
	if not kind then return end
	-- The click can arrive through both routes below; act once.
	if link == lastLink and GetTime() - lastTime < 0.2 then return end
	lastLink, lastTime = link, GetTime()
	if kind == "EldoUITime" then
		local line = stamped:Get(tonumber(id))
		if type(line) == "string" and not IsSecret(line) then M:ShowLinkPopup(M:PlainText(line), L["Copy line"]) end
		return
	end
	if kind ~= "EldoUIURL" then return end
	local url = id
	-- Shift+click puts the address into an edit box that is already open
	-- (the game's own insert, as for item links). EldoUI never opens the
	-- chat edit box itself: an edit box opened from addon code can block
	-- secure slash commands typed into it afterwards.
	if IsShiftKeyDown() then
		local insert = ChatFrameUtil and ChatFrameUtil.InsertLink or ChatEdit_InsertLink
		if insert and insert(url) then return end
		M:ShowLinkPopup(url, L["Copy link (to insert it, open the chat first)"])
		return
	end
	M:ShowLinkPopup(url)
end

if EventRegistry and EventRegistry.RegisterCallback then
	EventRegistry:RegisterCallback("SetItemRef", function(_, link) OnLink(link) end, M)
end
hooksecurefunc("SetItemRef", function(link) OnLink(link) end)

---------------------------------------------------------------------------
-- Chat history between sessions
---------------------------------------------------------------------------
local HISTORY_MARK = "|Haddon:EldoUIHistory:0|h"
local WHISPER_EVENTS = { CHAT_MSG_WHISPER = true, CHAT_MSG_WHISPER_INFORM = true, CHAT_MSG_BN_WHISPER = true, CHAT_MSG_BN_WHISPER_INFORM = true }
local MAX_LINE = 1500

local function Round(value)
	return type(value) == "number" and math.floor(value * 100 + 0.5) / 100 or 1
end

-- A whisper line: the event of the line, also for right-panel and Alerts
-- copies and for lines restored from history (they carry their event).
local function IsWhisperEvent(event)
	return type(event) == "string" and not IsSecret(event) and WHISPER_EVENTS[event] or false
end

local function CollectLines(frame, limit)
	local lines = {}
	local count = frame:GetNumMessages() or 0
	local keepWhispers = M.db.historyWhispers
	for index = math.max(1, count - limit + 1), count do
		local text, r, g, b, _, _, _, event = frame:GetMessageInfo(index)
		local whisper = IsWhisperEvent(event)
		if type(text) == "string" and not IsSecret(text) and #text <= MAX_LINE and not text:find(HISTORY_MARK, 1, true)
			and (keepWhispers or not whisper) then
			-- Timestamp links point into this session's memory: keep their text only.
			text = text:gsub("|Haddon:EldoUITime:%d+|h(.-)|h", "%1")
			-- Saved lines stay plain: icons and marks are drawn again live.
			text = StripItemTypes(text):gsub("|T.-|t", ""):gsub("|A.-|a", "")
			text = E.MaskProtectedNames(text)
			lines[#lines + 1] = { text, Round(r), Round(g), Round(b), w = whisper and 1 or nil }
		end
	end
	return lines
end

-- "Save whispers" off: whispers already in the saved history go too.
function M:DropSavedWhispers()
	if self.db.historyWhispers then return 0 end
	local dropped = 0
	for _, entry in pairs(E:GetMessagesDB().chat) do
		if type(entry) == "table" and type(entry.lines) == "table" then
			for index = #entry.lines, 1, -1 do
				local line = entry.lines[index]
				if type(line) == "table" and line.w then
					table.remove(entry.lines, index)
					dropped = dropped + 1
				end
			end
		end
	end
	return dropped
end

-- The tab name of a chat window ("General", "Trade"...). Saved lines go
-- back only into the tab with the same name, so a renamed or reordered
-- tab never gets another tab's lines.
function M:TabName(frame)
	local id = frame and frame.GetID and frame:GetID()
	local name = id and id > 0 and GetChatWindowInfo and GetChatWindowInfo(id)
	if type(name) ~= "string" or IsSecret(name) or name == "" then
		local tab = frame and frame.GetName and _G[frame:GetName() .. "Tab"]
		local text = tab and tab.GetText and tab:GetText()
		name = type(text) == "string" and not IsSecret(text) and text ~= "" and text or nil
	end
	return name
end

function M:HistoryLimit()
	return math.min(math.max(self.db.historyLines or 200, 20), 500)
end

function M:SaveHistory()
	if not self.db then return end
	local store = E:GetMessagesDB()
	if not self.db.history then
		wipe(store.chat)
		return
	end
	if not (self.active and self:Allowed("improve")) then return end
	local limit = self:HistoryLimit()
	local saved = {}
	-- Every tab, the Alerts tab too: its lines are rewritten copies that
	-- come back like any other tab's.
	for _, frame in self:IterateFrames() do
		local lines = CollectLines(frame, limit)
		if #lines > 0 then saved[frame:GetName()] = { t = time(), lines = lines, name = self:TabName(frame) } end
	end
	if self.rightPanel then
		local lines = CollectLines(self.rightPanel.messages, limit)
		if #lines > 0 then saved.EldoUI_ChatRight = { t = time(), lines = lines } end
	end
	store.chat = saved
end

-- How many saved lines a limit of `limit` per window would delete.
function M:SavedBeyond(limit)
	local lost = 0
	for _, entry in pairs(E:GetMessagesDB().chat) do
		if type(entry) == "table" and type(entry.lines) == "table" then
			lost = lost + math.max(#entry.lines - limit, 0)
		end
	end
	return lost
end

function M:TrimHistory(limit)
	for _, entry in pairs(E:GetMessagesDB().chat) do
		if type(entry) == "table" and type(entry.lines) == "table" then
			while #entry.lines > limit do table.remove(entry.lines, 1) end
		end
	end
end

function M:ClearHistory()
	wipe(E:GetMessagesDB().chat)
	self:Print(L["Saved chat history cleared."])
end

function M:ConfirmClearHistory()
	local count = self:SavedBeyond(0)
	if count == 0 then
		self:Print(L["There is no saved chat history to clear."])
		return
	end
	self:Confirm(L["Delete the %d saved chat lines of this character?\n\nThe chat you see now stays until you reload."]:format(count),
		function() M:ClearHistory() end)
end

-- Lowering "Lines saved per window" or turning history off deletes saved
-- lines, so EldoUI asks first. Cancel puts the old value back. A
-- profile switch is not a change by the player and doesn't ask.
local guard = { lines = nil, history = nil, profile = nil, asking = false }

function M:GuardHistory()
	local db = self.db
	if guard.lines == nil or guard.profile ~= E.profileName then
		guard.lines, guard.history, guard.profile = db.historyLines, db.history, E.profileName
		return
	end
	if guard.asking then return end
	local turningOff = guard.history and not db.history
	local lowering = db.history and (db.historyLines or 0) < (guard.lines or 0)
	local lost = 0
	if turningOff then lost = self:SavedBeyond(0)
	elseif lowering then lost = self:SavedBeyond(self:HistoryLimit()) end
	if lost == 0 then
		guard.lines, guard.history = db.historyLines, db.history
		return
	end
	guard.asking = true
	local text
	if turningOff then
		text = L["Turn saved chat history off?\n\nThe %d saved chat lines of this character are deleted."]:format(lost)
	else
		text = L["Keep only %d lines per window?\n\n%d saved chat lines are deleted."]:format(self:HistoryLimit(), lost)
	end
	self:Confirm(text, function()
		guard.asking = false
		guard.lines, guard.history = M.db.historyLines, M.db.history
		if not M.db.history then wipe(E:GetMessagesDB().chat) else M:TrimHistory(M:HistoryLimit()) end
	end, function()
		guard.asking = false
		M.db.historyLines, M.db.history = guard.lines, guard.history
		if E.RefreshConfig then E:RefreshConfig() end
	end)
end

-- Older lines go behind what this session already shows, under a gray divider.
local function Restore(target, entry)
	if type(entry) ~= "table" or type(entry.lines) ~= "table" or #entry.lines == 0 then return end
	local divider = (E:TextHex("dim") .. "%s-- %s --|h|r"):format(HISTORY_MARK, L["History from %s"]:format(E:ShortDate(entry.t or time())))
	target:BackFillMessage(divider, 0.5, 0.5, 0.5)
	for index = #entry.lines, 1, -1 do
		local line = entry.lines[index]
		if type(line) == "table" and type(line[1]) == "string" then
			-- A saved whisper keeps its whisper event, so turning Save
			-- whispers off later leaves it out of the next save.
			target:BackFillMessage(line[1], line[2] or 1, line[3] or 1, line[4] or 1, nil, nil, nil, line.w and "CHAT_MSG_WHISPER" or nil)
		end
	end
end

function M:RestoreHistory()
	if self.historyRestored or not self.db.history or not self:Allowed("improve") then return end
	self.historyRestored = true
	local chat = E:GetMessagesDB().chat
	local byTab = {}
	for _, frame in self:IterateFrames() do
		local tabName = self:TabName(frame)
		if tabName and not byTab[tabName] then byTab[tabName] = frame end
	end
	for key, entry in pairs(chat) do
		if key == "EldoUI_ChatRight" then
			if self.rightPanel then Restore(self.rightPanel.messages, entry) end
		elseif type(entry) == "table" then
			-- Saved with a tab name: only that tab. Older saves without one:
			-- the same window, as before.
			local target
			if type(entry.name) == "string" then target = byTab[entry.name] else target = _G[key] end
			if target and target.BackFillMessage then Restore(target, entry) end
		end
	end
end

---------------------------------------------------------------------------
-- Search the selected window
---------------------------------------------------------------------------
local SEARCH_ROW = 16

function M:CreateSearchPane()
	local pane = self:CreatePane()
	self.searchPane = pane
	pane.offset = 0
	pane.results = {}

	local box = CreateFrame("EditBox", nil, pane)
	-- Its middle on the buttons' middle, so both of its points are middles.
	box:SetPoint("LEFT", pane, "TOPLEFT", 0, -9)
	box:SetHeight(18)
	box:SetAutoFocus(false)
	E:SetFont(box, E.tokens.size.label)
	box:SetTextInsets(6, 6, 0, 0)
	E:SetTemplate(box)
	box:SetScript("OnEscapePressed", function() self:ShowPane(nil) end)
	box:SetScript("OnEnterPressed", function(b) b:ClearFocus() end)
	box:SetScript("OnTextChanged", function(b) self:RunSearch(b:GetText()) end)
	box:SetScript("OnEditFocusGained", function(b) b:SetBackdropBorderColor(unpack(E.media.accentColor)) end)
	box:SetScript("OnEditFocusLost", function(b) b:SetBackdropBorderColor(unpack(E.media.borderColor)) end)
	pane.box = box

	pane.status = E:CreateText(pane, E.tokens.size.tiny, "RIGHT")
	pane.status:SetTextColor(unpack(E.media.text.secondary))
	local close = self:FlatButton(pane, L["Close"], 44, 18)
	close:SetPoint("TOPRIGHT", 0, 0)
	close:SetScript("OnClick", function() self:ShowPane(nil) end)
	-- Every result as plain text, oldest first, ready for Ctrl+C.
	local copy = self:FlatButton(pane, L["Copy results"], 80, 18)
	copy:SetPoint("RIGHT", close, "LEFT", -4, 0)
	copy:SetScript("OnClick", function() self:CopySearchResults() end)
	pane.copy = copy
	pane.status:SetPoint("RIGHT", copy, "LEFT", -8, 0)
	box:SetPoint("RIGHT", pane.status, "LEFT", -8, 0)

	local list = CreateFrame("Frame", nil, pane)
	list:SetPoint("TOPLEFT", 0, -22)
	list:SetPoint("BOTTOMRIGHT", 0, 0)
	E:SetTemplate(list, true)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		pane.offset = math.max(0, pane.offset - delta * 3)
		self:RefreshSearch()
	end)
	pane.list = list
	pane.rows = {}

	function pane.Layout()
		pane.status:SetWidth(120)
		self:RefreshSearch()
	end
end

function M:RunSearch(text)
	local pane = self.searchPane
	if not pane then return end
	wipe(pane.results)
	pane.offset = 0
	text = strtrim(tostring(text or "")):lower()
	pane.query = text
	if text ~= "" then
		local frame = self:SelectedFrame()
		pane.frame = frame
		for index = frame:GetNumMessages(), 1, -1 do
			local line = frame:GetMessageInfo(index)
			if type(line) == "string" and not IsSecret(line) then
				local plain = self:PlainText(line)
				if plain:lower():find(text, 1, true) then
					pane.results[#pane.results + 1] = { index = index, text = plain }
				end
			end
		end
	end
	self:RefreshSearch()
end

local function MarkMatch(text, query)
	if query == "" then return text end
	local r, g, b = unpack(E.media.accentColor)
	local first, last = text:lower():find(query, 1, true)
	if not first then return text end
	return text:sub(1, first - 1) .. ("|c%s"):format(Hex(r, g, b)) .. text:sub(first, last) .. "|r" .. text:sub(last + 1)
end

function M:RefreshSearch()
	local pane = self.searchPane
	if not pane then return end
	local listHeight = math.max(self.db.height - self.db.tabHeight - 34, SEARCH_ROW)
	local visible = math.floor((listHeight - 4) / SEARCH_ROW)
	pane.offset = math.min(pane.offset, math.max(#pane.results - visible, 0))
	local r, g, b = unpack(E.media.accentColor)
	for index = 1, math.max(visible, #pane.rows) do
		local row = pane.rows[index]
		if not row and index <= visible then
			row = CreateFrame("Button", nil, pane.list)
			row:SetHeight(SEARCH_ROW)
			row:SetPoint("TOPLEFT", 2, -2 - (index - 1) * SEARCH_ROW)
			row:SetPoint("TOPRIGHT", -2, -2 - (index - 1) * SEARCH_ROW)
			row.hover = row:CreateTexture(nil, "HIGHLIGHT")
			row.hover:SetAllPoints()
			row.text = E:CreateText(row, E.tokens.size.small, "LEFT")
			row.text:SetPoint("LEFT", 3, 0)
			row.text:SetPoint("RIGHT", -3, 0)
			row:SetScript("OnClick", function(button) self:JumpTo(button.result) end)
			pane.rows[index] = row
		end
		if row then
			local result = index <= visible and pane.results[index + pane.offset]
			row.result = result or nil
			row:SetShown(result and true or false)
			row.hover:SetColorTexture(r, g, b, 0.18)
			if result then row.text:SetText(MarkMatch(result.text, pane.query or "")) end
		end
	end
	if (pane.query or "") == "" then
		pane.status:SetText(L["Type to search"])
	else
		pane.status:SetText(L["%d found"]:format(#pane.results))
	end
end

function M:CopySearchResults()
	local pane = self.searchPane
	if not pane or #pane.results == 0 then
		E:Print(L["Nothing to copy: search for something first."])
		return
	end
	local lines = {}
	for index = #pane.results, 1, -1 do lines[#lines + 1] = pane.results[index].text end
	E:ShowCopyBox(L["Copy search results"], L["%d lines matching \"%s\". Press Ctrl+C."]:format(#lines, pane.query or ""), table.concat(lines, "\n"))
end

-- Scroll the window so the line sits at the bottom of the view.
function M:JumpTo(result)
	local pane = self.searchPane
	local frame = pane and pane.frame
	if not result or not frame then return end
	local offset = math.max(frame:GetNumMessages() - result.index, 0)
	self:ShowPane(nil)
	frame:SetScrollOffset(offset)
end

function M:ToggleSearch(text)
	if not (self.panel and self.panel:IsShown() and self:Allowed("replace")) then
		E:Print(L["Search needs EldoUI's chat panel (Blizzard UI page: Chat windows, Replace)."])
		return
	end
	if not self.searchPane then
		self:CreateSearchPane()
		self:LayoutPane(self.searchPane)
	end
	if text == nil and self.paneShown == "search" then
		self:ShowPane(nil)
		return
	end
	self:ShowPane("search")
	self:LayoutPane(self.searchPane)
	self.searchPane.box:SetText(text or self.searchPane.box:GetText() or "")
	self.searchPane.box:SetFocus()
	self:RunSearch(self.searchPane.box:GetText())
end

E:AddCommand("chatsearch", "<text>  search the selected chat window", function(arg)
	M:ToggleSearch(arg or "")
end)

---------------------------------------------------------------------------
-- Right chat panel: EldoUI's own message frame
---------------------------------------------------------------------------
-- Above the damage meter (Eldo-Modern); tools/data/layout-points/chat.json
-- has the spot for every layout.
local RIGHT_POINT = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -26, 270 }

function M:RightTitle()
	if (self.db.rightTitle or "") ~= "" then return self.db.rightTitle end
	local names = {}
	local short = { loot = "Loot", skills = "Progress", channels = "Channels", guild = "Guild", group = "Group",
		whisper = "Whispers", system = "System", npc = "NPCs" }
	for _, group in ipairs(self.rightGroupList) do
		if self.db.rightGroups[group[1]] then names[#names + 1] = L[short[group[1]]] end
	end
	return #names > 0 and table.concat(names, " · ") or L["Right panel"]
end

function M:CreateRightPanel()
	local panel = CreateFrame("Frame", "EldoUI_ChatRight", UIParent)
	panel:SetFrameStrata("BACKGROUND")
	panel:SetSize(self.db.rightWidth, self.db.rightHeight)
	panel.bg = CreateFrame("Frame", nil, panel)
	panel.bg:SetAllPoints()
	panel.bg:SetFrameLevel(math.max(panel:GetFrameLevel() - 1, 0))
	panel.strip = panel.bg:CreateTexture(nil, "BORDER")
	panel.strip:SetColorTexture(0, 0, 0, 0.35)
	panel.title = E:CreateText(panel, E.tokens.size.section, "LEFT")
	panel.line = panel:CreateTexture(nil, "OVERLAY")
	panel.line:SetHeight(2)
	panel.line:SetPoint("BOTTOMLEFT", panel.title, "BOTTOMLEFT", 0, 1)
	panel.line:SetPoint("BOTTOMRIGHT", panel.title, "BOTTOMRIGHT", 0, 1)

	panel.copy = self:FlatButton(panel, L["Copy"], 34, 18)
	panel.copy:SetScript("OnClick", function()
		local lines = {}
		for index = 1, panel.messages:GetNumMessages() do
			local text = panel.messages:GetMessageInfo(index)
			if type(text) == "string" and not IsSecret(text) then lines[#lines + 1] = self:PlainText(text) end
		end
		E:ShowCopyBox(L["Copy right panel"], L["Select what you need and press Ctrl+C."], table.concat(lines, "\n"))
	end)
	panel.clear = self:FlatButton(panel, L["Clear"], 36, 18)
	panel.clear:SetPoint("RIGHT", panel.copy, "LEFT", -4, 0)
	panel.clear:SetScript("OnClick", function() panel.messages:Clear() end)

	local messages = CreateFrame("ScrollingMessageFrame", nil, panel)
	messages:SetJustifyH("LEFT")
	messages:SetMaxLines(500)
	messages:SetHyperlinksEnabled(true)
	messages:SetScript("OnHyperlinkClick", function(_, link, text, button)
		SetItemRef(link, text, button, DEFAULT_CHAT_FRAME)
	end)
	messages:SetScript("OnHyperlinkEnter", function(frame, link) M.OnLinkEnter(frame, link) end)
	messages:SetScript("OnHyperlinkLeave", function(frame) M.OnLinkLeave(frame) end)
	messages:EnableMouseWheel(true)
	messages:SetScript("OnMouseWheel", function(frame, delta)
		if IsShiftKeyDown() then
			if delta > 0 then frame:ScrollToTop() else frame:ScrollToBottom() end
		elseif delta > 0 then
			frame:ScrollUp()
		else
			frame:ScrollDown()
		end
	end)
	panel.messages = messages
	self.rightPanel = panel
	E:CreateMover(panel, "EldoUI_ChatRight", L["Chat (Right)"], RIGHT_POINT,
		{ sizeKeys = { width = { key = "rightWidth", min = 200, max = 900 }, height = { key = "rightHeight", min = 100, max = 600 } } })
end

function M:ApplyRightPanel()
	local db = self.db
	local want = db.rightPanel and self:Allowed("improve")
	if want and not self.rightPanel then self:CreateRightPanel() end
	local panel = self.rightPanel
	if not panel then return end
	panel:SetShown(want)
	if not want then return end
	panel:SetSize(db.rightWidth, db.rightHeight)
	E:SetPanelTemplate(panel.bg, true)
	local r, g, b = unpack(E.media.backdropColor)
	if E:ArtStyle() == "Classic" then r, g, b = 1, 1, 1 end
	panel.bg:SetBackdropColor(r, g, b, db.panelAlpha)
	-- The title strip sits where the main chat has its tabs (top or bottom).
	local edge, inward = self:StripEdge()
	panel.strip:ClearAllPoints()
	panel.strip:SetPoint(edge .. "LEFT", E.pixel, inward * E.pixel)
	panel.strip:SetPoint(edge .. "RIGHT", -E.pixel, inward * E.pixel)
	panel.strip:SetHeight(db.tabHeight)
	panel.title:ClearAllPoints()
	panel.title:SetPoint(edge .. "LEFT", 10, 0)
	panel.title:SetHeight(db.tabHeight)
	E:SetFont(panel.title, db.tabFontSize)
	panel.title:SetText(self:RightTitle())
	panel.title:SetTextColor(E:TokenColor("accent"))
	local ar, ag, ab = unpack(E.media.accentColor)
	panel.line:SetColorTexture(ar, ag, ab, 1)
	panel.copy:ClearAllPoints()
	panel.copy:SetPoint(edge .. "RIGHT", panel, edge .. "RIGHT", -4, inward * (db.tabHeight - 18) / 2)
	local messages = panel.messages
	messages:ClearAllPoints()
	if edge == "BOTTOM" then
		messages:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
		messages:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, db.tabHeight + 6)
	else
		messages:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -(db.tabHeight + 6))
		messages:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)
	end
	E:SetMessageFont(messages, self.ChatFontPath and self:ChatFontPath() or E.media.font, db.fontSize, self:Outline())
	if db.fontShadow then
		messages:SetShadowOffset(1, -1)
		messages:SetShadowColor(0, 0, 0, 1)
	else
		messages:SetShadowOffset(0, 0)
	end
	if db.fade == "fade" then
		messages:SetFading(true)
		messages:SetTimeVisible(db.fadeTime)
		messages:SetFadeDuration(db.fadeDuration)
	elseif db.fade == "never" then
		messages:SetFading(false)
	else
		messages:SetFading(true)
		messages:SetTimeVisible(120)
		messages:SetFadeDuration(3)
	end
end

---------------------------------------------------------------------------
-- Link tooltips on hover: the link the client hands to the chat
-- frame's OnHyperlinkEnter, shown where the game (or EldoUI's Tooltip
-- module) puts tooltips. A secret link shows nothing.
---------------------------------------------------------------------------
local TOOLTIP_LINKS = {
	item = true, spell = true, enchant = true, quest = true, talent = true, achievement = true,
	currency = true, unit = true, instancelock = true, keystone = true, glyph = true, mount = true,
}
local linkOwner = {}     -- EventRegistry owner key
local hoverFrame         -- the frame whose link tooltip is showing

-- The [all] link of a folded guild or friend notice lists every name.
local function ShowRosterNames(frame, link)
	local kind, data = E:ParseChatLink(link)
	local names = kind == "roster" and M.RosterSummaryNames and M:RosterSummaryNames(data)
	if not names then return false end
	GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
	GameTooltip:SetText(E:Plural(#names, "%d player", "%d players"):format(#names))
	for _, name in ipairs(names) do GameTooltip:AddLine(name, unpack(E.media.text.body)) end
	GameTooltip:Show()
	hoverFrame = frame
	return true
end

local function OnLinkEnter(frame, link)
	if not Improve() or type(link) ~= "string" or IsSecret(link) then return end
	if ShowRosterNames(frame, link) or not M.db.linkTooltips then return end
	local kind = link:match("^(%a+):")
	if not (kind and TOOLTIP_LINKS[kind]) then return end
	if GameTooltip_SetDefaultAnchor then
		GameTooltip_SetDefaultAnchor(GameTooltip, frame)
	else
		GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
	end
	if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then
		hoverFrame = frame
		GameTooltip:Show()
	else
		GameTooltip:Hide()
	end
end

local function OnLinkLeave(frame)
	if hoverFrame and (frame == nil or frame == hoverFrame) then
		hoverFrame = nil
		GameTooltip:Hide()
	end
end
M.OnLinkEnter, M.OnLinkLeave = OnLinkEnter, OnLinkLeave

if EventRegistry and EventRegistry.RegisterCallback then
	EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkEnter", function(_, frame, link) OnLinkEnter(frame, link) end, linkOwner)
	EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkLeave", function(_, frame) OnLinkLeave(frame) end, linkOwner)
end

---------------------------------------------------------------------------
-- Edit box history between sessions: what you typed (chat lines and
-- slash commands) is kept per character, the last N lines, and handed back
-- to the edit boxes at login. Up and Down (Alt+Up/Down with "Arrow keys
-- move the cursor" off) walk through it as usual.
---------------------------------------------------------------------------
local historyHooked = setmetatable({}, { __mode = "k" })
local historyFilled = setmetatable({}, { __mode = "k" })
local restoringHistory = false

local function EditHistory()
	local store = E:GetMessagesDB()
	if type(store.editHistory) ~= "table" then store.editHistory = {} end
	return store.editHistory
end

-- Secure slash commands (/cast, /target, /use ...) are never saved: the
-- file stays free of combat macros. Uses the game's own list.
local function IsSecureLine(text)
	local command = text:match("^(/[^%s]+)")
	if not command then return false end
	command = command:lower()
	if IsSecureCmd then
		local ok, secure = pcall(IsSecureCmd, command)
		if ok and secure then return true end
	end
	return false
end
M.IsSecureLine = IsSecureLine

local function KeepLine(text)
	if type(text) ~= "string" or IsSecret(text) then return false end
	text = strtrim(text)
	return text ~= "" and #text <= 255 and not IsSecureLine(text), text
end

local function RememberLine(_, text)
	if restoringHistory or not Improve() then return end
	local limit = M.db.editHistoryLines or 0
	if limit <= 0 then return end
	-- Nothing typed during chat lockdown is kept.
	if InLockdown() then return end
	local keep
	keep, text = KeepLine(text)
	if not keep then return end
	local list = EditHistory()
	-- Lines saved by older versions may hold secure commands: drop them.
	for index = #list, 1, -1 do
		if not KeepLine(list[index]) then table.remove(list, index) end
	end
	if list[#list] == text then return end
	list[#list + 1] = text
	while #list > limit do table.remove(list, 1) end
end

function M:HookEditHistory(editBox)
	if not editBox or not editBox.AddHistoryLine then return end
	if not historyHooked[editBox] then
		historyHooked[editBox] = true
		hooksecurefunc(editBox, "AddHistoryLine", RememberLine)
	end
	if historyFilled[editBox] or not Improve() or (self.db.editHistoryLines or 0) <= 0 then return end
	historyFilled[editBox] = true
	local list = EditHistory()
	-- Lines saved by older versions may hold secure commands: drop them.
	for index = #list, 1, -1 do
		if not KeepLine(list[index]) then table.remove(list, index) end
	end
	restoringHistory = true
	for index = math.max(1, #list - self.db.editHistoryLines + 1), #list do
		if type(list[index]) == "string" then editBox:AddHistoryLine(list[index]) end
	end
	restoringHistory = false
end

function M:ClearEditHistory()
	wipe(EditHistory())
	self:Print(L["Saved typed lines cleared."])
end

function M:ConfirmClearEditHistory()
	local count = #EditHistory()
	if count == 0 then
		self:Print(L["There are no saved typed lines to clear."])
		return
	end
	self:Confirm(L["Delete the %d saved typed lines of this character?"]:format(count), function() M:ClearEditHistory() end)
end

---------------------------------------------------------------------------
-- Scrolling: back to the newest line after N seconds without
-- scrolling, and a small button while a window is scrolled up (accent when
-- new lines arrived below). Checked twice a second, only while one of the
-- two is on.
---------------------------------------------------------------------------
local scrollButtons = setmetatable({}, { __mode = "k" }) -- chat frame -> button
local scrollState = setmetatable({}, { __mode = "k" })   -- chat frame -> { offset, moved, newBelow }
local scrollTicker

local function ScrollStateOf(frame)
	local state = scrollState[frame]
	if not state then
		state = { offset = 0, moved = GetTime() }
		scrollState[frame] = state
	end
	return state
end

function M:NoteScroll(frame)
	ScrollStateOf(frame).moved = GetTime()
end

local function PaintScrollButton(button, state)
	local color = state and state.newBelow and E.media.accentColor or E.media.borderColor
	button:SetBackdropBorderColor(unpack(color))
	button.icon:SetVertexColor(unpack(state and state.newBelow and E.media.accentColor or { 0.85, 0.85, 0.88 }))
end

local function ScrollButton(frame)
	local button = scrollButtons[frame]
	if button then return button end
	button = CreateFrame("Button", nil, frame)
	button:SetSize(24, 18)
	button:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	button:SetFrameLevel(frame:GetFrameLevel() + 6)
	E:SetTemplate(button)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetSize(14, 14)
	button.icon:SetPoint("CENTER")
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("minimal-scrollbar-arrow-returntobottom") then
		button.icon:SetAtlas("minimal-scrollbar-arrow-returntobottom")
	else
		button.icon:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollEnd-Up")
	end
	button:SetScript("OnClick", function(self, mouse)
		if E:IsOptionsLinkClick(self, mouse) then return end
		frame:ScrollToBottom()
		local state = ScrollStateOf(frame)
		state.newBelow = nil
		button:Hide()
	end)
	button:SetScript("OnEnter", function(self)
		self:SetBackdropBorderColor(unpack(E.media.accentColor))
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L["Jump to the newest line"])
		if scrollState[frame] and scrollState[frame].newBelow then
			E.UIKit.TipText(GameTooltip, L["New lines arrived while you were scrolled up."])
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function(self)
		GameTooltip_Hide()
		PaintScrollButton(self, scrollState[frame])
	end)
	E:BindOptionsLink(button, { page = "module:Chat", key = "scrollButton" })
	button:Hide()
	scrollButtons[frame] = button
	return button
end

function M:MarkNewBelow(frame)
	if not (frame and frame.AtBottom and scrollButtons[frame]) or frame:AtBottom() then return end
	local state = ScrollStateOf(frame)
	if not state.newBelow then
		state.newBelow = true
		PaintScrollButton(scrollButtons[frame], state)
	end
end

local function CheckScroll()
	if not Improve() then return end
	local db = M.db
	local now = GetTime()
	for frame in pairs(hookedFrames) do
		local visible = frame:IsVisible() and frame.AtBottom
		local atBottom = not visible or frame:AtBottom()
		if visible then
			local state = ScrollStateOf(frame)
			local offset = frame:GetScrollOffset()
			if offset ~= state.offset then
				state.offset = offset
				state.moved = now
			end
			if not atBottom and db.autoScroll > 0 and now - state.moved >= db.autoScroll and not frame:IsMouseOver() then
				frame:ScrollToBottom()
				atBottom = true
			end
			if atBottom then state.newBelow = nil end
		end
		local show = db.scrollButton and visible and not atBottom
		if show then
			local button = ScrollButton(frame)
			if not button:IsShown() then
				PaintScrollButton(button, scrollState[frame])
				button:Show()
			end
		elseif scrollButtons[frame] then
			scrollButtons[frame]:Hide()
		end
	end
end

function M:ApplyScrolling()
	local want = Improve() and ((self.db.autoScroll or 0) > 0 or self.db.scrollButton)
	if want and not scrollTicker then
		scrollTicker = C_Timer.NewTicker(0.5, CheckScroll)
	elseif not want and scrollTicker then
		scrollTicker:Cancel()
		scrollTicker = nil
	end
	if not (want and self.db.scrollButton) then
		for _, button in pairs(scrollButtons) do button:Hide() end
	end
end

---------------------------------------------------------------------------
-- A sound per channel (plan 3.21): played when someone else writes
-- in that channel, at most every 2 seconds per channel. The message is
-- never read. During chat lockdown the sender can be secret; then EldoUI
-- can't tell your own lines apart and stays quiet.
---------------------------------------------------------------------------
local CHANNEL_SOUND_EVENTS = {
	CHAT_MSG_GUILD = "guild", CHAT_MSG_OFFICER = "officer",
	CHAT_MSG_PARTY = "party", CHAT_MSG_PARTY_LEADER = "party",
	CHAT_MSG_RAID = "raid", CHAT_MSG_RAID_LEADER = "raid", CHAT_MSG_RAID_WARNING = "raid",
	CHAT_MSG_INSTANCE_CHAT = "instance", CHAT_MSG_INSTANCE_CHAT_LEADER = "instance",
	CHAT_MSG_SAY = "say", CHAT_MSG_YELL = "yell", CHAT_MSG_CHANNEL = "channel",
}
local lastChannelSound = {}

-- Would the chat hide this line (blocked phrases, channel mutes, repeated
-- lines, a muted guild)? A hidden line makes no sound, flash or Alerts tab
-- copy. Both filters keep their answer per line, so asking again here costs
-- nothing and the hidden-lines log counts the line once.
function M:LineHidden(event, ...)
	for _, filter in ipairs({ self.FilterLine, self.GuildMuteFilter }) do
		local ok, hide = pcall(filter, self, event, ...)
		if ok and hide then return true end
	end
	return false
end

-- A channel line that no chat tab shows (a joined channel left out of
-- every window) makes no sound either.
local function ChannelShown(channelBase, channel)
	local name = M.ChannelName and M.ChannelName(Readable(channelBase) or Readable(channel))
	if not name then return true end
	for _, frame in M:IterateFrames() do
		if not (M.IsAlertFrame and M:IsAlertFrame(frame)) then
			if not frame.ContainsChannel or frame:ContainsChannel(name) then return true end
			for _, listed in pairs(frame.channelList or {}) do
				if type(listed) == "string" and listed:lower() == name then return true end
			end
		end
	end
	return false
end

local function OnChannelMessage(_, event, message, sender, ...)
	if not Improve() or M:QuietNow() then return end
	local group = CHANNEL_SOUND_EVENTS[event]
	local sound = group and M.db.channelSounds[group]
	if not sound or sound == "none" then return end
	local rawSender = sender
	sender = Readable(sender)
	if type(sender) ~= "string" or IsMe(sender) then return end
	if M:LineHidden(event, message, rawSender, ...) then return end
	if event == "CHAT_MSG_CHANNEL" then
		local _, channel, _, _, _, _, channelBase = ...
		if not ChannelShown(channelBase, channel) then return end
	end
	local now = GetTime()
	if lastChannelSound[group] and now - lastChannelSound[group] < 2 then return end
	lastChannelSound[group] = now
	E:PlayMedia(sound)
end

---------------------------------------------------------------------------
-- Wiring (called from Core.lua)
---------------------------------------------------------------------------
function M:ApplyMessages()
	if self.MigrateSounds then self:MigrateSounds() end
	if self.MigrateFilters then self:MigrateFilters() end
	if self.ResetFilterDecisions then self:ResetFilterDecisions() end
	if self.AddMuteMenu then self:AddMuteMenu() end
	AddFilters()
	if self.ApplyAlerts then self:ApplyAlerts() end
	keywordSource = nil
	BuildKeywords()
	namesDirty = true
	self:ApplyRightPanel()
	if self.ApplyChatColors then self:ApplyChatColors() end
	if self.ApplyLevels then self:ApplyLevels() end
	if self.RefreshPreview then self:RefreshPreview() end
	if self.RestyleListEditors then self:RestyleListEditors() end
	self:GuardHistory()
	self:DropSavedWhispers()
	self:RestoreHistory()
	RefreshUnlockedLinks()
	self:ApplyScrolling()
end

function M:RestoreMessages()
	ApplyItemTypes()
	for frame in pairs(hookedFrames) do self:StyleMessages(frame) end
	if self.RestoreChatColors then self:RestoreChatColors() end
	if self.ApplyLevels then self:ApplyLevels() end
	if self.rightPanel then self.rightPanel:Hide() end
	self:ApplyScrolling()
	OnLinkLeave(nil)
end

-- Whisper alert: tied to the whisper events only. The message itself is
-- never read, so it works the same during chat lockdown.
local lastWhisper = 0
local function OnWhisper(_, event, ...)
	if not Improve() or M:QuietNow() then return end
	if M:LineHidden(event, ...) then return end
	local now = GetTime()
	if now - lastWhisper < 2 then return end
	lastWhisper = now
	local sound = M.MediaSound and M.MediaSound(M.db.whisperSound) or "none"
	if sound ~= "none" then E:PlayMedia(sound) end
	if M.db.whisperFlash and FlashClientIcon then FlashClientIcon() end
end

local ROSTER_EVENTS = { "GROUP_ROSTER_UPDATE", "GUILD_ROSTER_UPDATE", "FRIENDLIST_UPDATE" }

function M:EnableMessages()
	self:RegisterEvent("PLAYER_LOGOUT", function() M:SaveHistory() end)
	self:RegisterEvent("CHAT_MSG_WHISPER", OnWhisper)
	self:RegisterEvent("CHAT_MSG_BN_WHISPER", OnWhisper)
	self:RegisterEvent("ITEM_DATA_LOAD_RESULT", function(_, _, itemID, success) M:OnItemData(itemID, success) end)
	E:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", function(_, _, _, state)
		E:AfterRestrictionEnds(state, RefreshUnlockedLinks)
	end, itemRestrictionOwner)
	for event in pairs(CHANNEL_SOUND_EVENTS) do self:RegisterEvent(event, OnChannelMessage) end
	for _, event in ipairs(ROSTER_EVENTS) do self:RegisterEvent(event, function() namesDirty = true end) end
	if self.EnableColors then self:EnableColors() end
end

function M:DisableMessages()
	self:UnregisterEvent("PLAYER_LOGOUT")
	self:UnregisterEvent("CHAT_MSG_WHISPER")
	self:UnregisterEvent("CHAT_MSG_BN_WHISPER")
	self:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
	wipe(itemWaiting)
	wipe(itemReady)
	itemRequests = 0
	-- Drop the old annotations once chat is writable, even if this module
	-- stays off or is switched on again before the restriction ends.
	clearItemTypes = itemTypesInChat
	if clearItemTypes then
		RefreshUnlockedLinks()
	else
		E:UnregisterEvent("ADDON_RESTRICTION_STATE_CHANGED", itemRestrictionOwner)
	end
	for event in pairs(CHANNEL_SOUND_EVENTS) do self:UnregisterEvent(event) end
	for _, event in ipairs(ROSTER_EVENTS) do self:UnregisterEvent(event) end
	if self.DisableColors then self:DisableColors() end
	if self.DisableAlerts then self:DisableAlerts() end
	if self.ApplyLevels then self:ApplyLevels() end
	if self.rightPanel then self.rightPanel:Hide() end
	if scrollTicker then
		scrollTicker:Cancel()
		scrollTicker = nil
	end
	for _, button in pairs(scrollButtons) do button:Hide() end
	OnLinkLeave(nil)
	if self.FlushRosterBursts then self:FlushRosterBursts() end
end
