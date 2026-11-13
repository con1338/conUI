-- EldoUI addon messages (E:RegisterComm / E:SendComm).
--
--   E:RegisterComm("EUI_IR", function(payload, sender, channel) ... end, { trusted = "group" })
--   E:SendComm("EUI_IR", payload, "GROUP")            -- party, raid or instance group
--   E:SendComm("EUI_TAL", payload, "WHISPER", "Player")
--   E:SendComm(prefix, payload, "CHANNEL", channelNumber, { raw = true })
--
-- A prefix is the game's addon message prefix (at most 16 characters); it
-- is registered with C_ChatInfo.RegisterAddonMessagePrefix on first use.
-- Payloads are plain strings of any length (no "\0"): longer ones are cut
-- into parts of at most 255 bytes and joined again on the other side.
--
-- Sending: each prefix has its own queue and its own allowance, the same
-- one the game gives every registered prefix (a burst of 10 messages, then
-- one a second), so EldoUI never runs into the game's throttle and one
-- busy prefix never holds up another: the pump takes turns between the
-- prefixes that have something to send and allowance left. While the game
-- holds addon messages back (chat messaging lockdown during boss fights,
-- and PvP matches) every queue waits and goes on when the
-- restriction ends; if the game still answers "throttled" (another addon
-- on the same prefix, a server hiccup) only that prefix waits a little.
-- Nothing is ever sent from a combat event by itself: modules call
-- SendComm from a player's click or a state change.
--
-- Receiving: lines whose text or sender is a secret value are dropped
-- unread, as are your own messages (unless the handler asks for them) and,
-- with `trusted`, messages from people you don't know:
--   trusted = "group"   party or raid members
--   trusted = "guild"   guild members
--   trusted = "friends" your friends list
--   trusted = true      any of those three
-- The handler gets (payload, sender, channel, prefix).
local _, E = ...
local L = E.L

local MAX_MESSAGE = 255
local SEND_INTERVAL = 0.1     -- between messages (all prefixes together)
local BURST = 10              -- the game's allowance per prefix ...
local REFILL = 1              -- ... and how many come back each second
local THROTTLE_WAIT = 1.5     -- after the game says "throttled" anyway
local RESTRICTED_POLL = 2     -- while addon messages are held back
local PART_TIMEOUT = 60       -- seconds without a part before a message is dropped
local MAX_PARTS = 400         -- about 95 KB per message
local MAX_QUEUE = 1000        -- messages waiting to go out
local INSTANCE_GROUP = _G.LE_PARTY_CATEGORY_INSTANCE -- battleground and instance groups, where the client has them

local handlers = {}           -- prefix -> { fn, opts }
local registered = {}         -- prefix -> true once the game knows it
local queues = {}             -- prefix -> { { prefix, text, channel, target, id }, ... }
local order = {}              -- prefixes with a queue, in turn order
local cursor = 0              -- the prefix that sent last (index into order)
local budget = {}             -- prefix -> { tokens, at, waitUntil }
local queued = 0              -- messages waiting, all prefixes
local incoming = {}           -- "prefix\1sender\1id" -> { parts, total, got, last }
local nextId = 0
local waitUntil = 0
local pump = CreateFrame("Frame")
pump:Hide()

local IsSecret = E.Secret

local function ShortName(name)
	if type(name) ~= "string" then return name end
	if Ambiguate then return Ambiguate(name, "none") end
	return (name:gsub("%-.*$", ""))
end

local function RegisterPrefix(prefix)
	if registered[prefix] then return true end
	if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) then return false end
	local ok, result = pcall(C_ChatInfo.RegisterAddonMessagePrefix, prefix)
	if not ok then return false end
	local results = Enum.RegisterAddonMessagePrefixResult
	if results and type(result) == "number" and result ~= results.Success and result ~= results.DuplicatePrefix then
		return false
	end
	registered[prefix] = true
	return true
end

-- ADDON_RESTRICTION_STATE_CHANGED (kind, state) fires as a restriction
-- starts (Activating) and after one ends (Inactive), and while it is being
-- dispatched the game answers "not active" for every restriction. A handler
-- that waits for the end passes the event's state here: `fn` runs one frame
-- later and only for an end, so the checks it makes get a true answer.
function E:AfterRestrictionEnds(state, fn)
	local states = Enum and Enum.AddOnRestrictionState
	local inactive = states and states.Inactive or 0
	if type(state) == "number" and not E:IsSecret(state) and state ~= inactive then return end
	C_Timer.After(0, fn)
end

-- True while the game holds addon messages back.
function E:CommRestricted()
	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
		local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
		if ok and locked then return true end
	end
	local restricted, types = C_RestrictedActions, Enum.AddOnRestrictionType
	if restricted and restricted.IsAddOnRestrictionActive and types then
		for _, key in ipairs({ "Chat", "Encounter", "ChallengeMode", "PvPMatch" }) do
			if types[key] then
				local ok, active = pcall(restricted.IsAddOnRestrictionActive, types[key])
				if ok and active then return true end
			end
		end
	end
	return false
end

-- One chat line the player asked for (a click or their own typing). The
-- game's chat restriction is checked first, so a refused line is never
-- reported as posted and never marks a post as done. Returns true and
-- "attempted" when the line went to the game (the game does not confirm
-- delivery), or false and why: "restricted", "unavailable" or "error".
-- Nothing is retried, queued or posted later.
function E:TryChatPost(text, chatType, languageID, target)
	if type(text) ~= "string" or text == "" then return false, "error" end
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or rawget(_G, "SendChatMessage")
	if type(send) ~= "function" then return false, "unavailable" end
	if self:CommRestricted() then return false, "restricted" end
	if not pcall(send, text, chatType, languageID, target) then return false, "error" end
	return true, "attempted"
end

-- The line a refused post shows the player.
function E:ChatRefusedText()
	return L["The game doesn't allow chat messages right now."]
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
-- "GROUP" picks the instance group, raid or party you are in.
local function ResolveChannel(channel)
	channel = type(channel) == "string" and channel:upper() or "GROUP"
	if channel == "GROUP" then
		if INSTANCE_GROUP and IsInGroup(INSTANCE_GROUP) then return "INSTANCE_CHAT" end
		if IsInRaid() then return "RAID" end
		if IsInGroup() then return "PARTY" end
		return nil
	end
	if channel == "PARTY" and not IsInGroup() then return nil end
	if channel == "RAID" and not IsInRaid() then return nil end
	if channel == "GUILD" and not IsInGuild() then return nil end
	return channel
end

-- The wire format: a whole message is "1" .. payload; a cut one is sent
-- as "P<id>\t<index>\t<total>\t" .. part. Parts end on a whole UTF-8
-- character, so every message the game sees is valid text.
local HEADER_ROOM = 14 -- "P" + 4 hex + tab + 3 digits + tab + 3 digits + tab

local function Split(text)
	if #text + 1 <= MAX_MESSAGE then return { "1" .. text } end
	nextId = nextId % 0xFFFF + 1
	local id = ("%x"):format(nextId)
	local size = MAX_MESSAGE - HEADER_ROOM
	local bodies, pos = {}, 1
	while pos <= #text do
		local last = math.min(pos + size - 1, #text)
		-- Step back off a continuation byte (0x80-0xBF) so no character is cut.
		while last < #text and last > pos do
			local byte = text:byte(last + 1)
			if byte < 0x80 or byte > 0xBF then break end
			last = last - 1
		end
		bodies[#bodies + 1] = text:sub(pos, last)
		pos = last + 1
	end
	local parts = {}
	for index, body in ipairs(bodies) do
		parts[index] = ("P%s\t%d\t%d\t"):format(id, index, #bodies) .. body
	end
	return parts, id
end

-- Queue a payload. Returns true when it is queued, false and a reason
-- ("prefix", "payload", "channel", "target", "full") when not.
-- opts (optional):
--   raw = true    send the payload as it is, in one message of at most 255
--                 bytes, for a wire format of its own (settings sharing and
--                 the version check, which older EldoUI versions also read)
--   done = fn     fn(status, reason) once the message left ("ok") or the
--                 game refused it ("fail", e.g. the player is offline)
function E:SendComm(prefix, payload, channel, target, opts)
	if type(prefix) ~= "string" or prefix == "" or #prefix > 16 then return false, "prefix" end
	local raw = type(opts) == "table" and opts.raw
	if type(payload) ~= "string" or IsSecret(payload) or payload:find("\0", 1, true)
		or #payload > (raw and MAX_MESSAGE or MAX_PARTS * (MAX_MESSAGE - HEADER_ROOM)) then
		return false, "payload"
	end
	local resolved = ResolveChannel(channel)
	if not resolved then return false, "channel" end
	if resolved == "WHISPER" and (type(target) ~= "string" or IsSecret(target) or target == "") then return false, "target" end
	if resolved == "CHANNEL" and (type(target) ~= "number" or IsSecret(target) or target <= 0) then return false, "target" end
	if not RegisterPrefix(prefix) then return false, "prefix" end
	local parts, id
	if raw then parts = { payload } else parts, id = Split(payload) end
	if #parts > MAX_PARTS then return false, "payload" end
	if queued + #parts > MAX_QUEUE then return false, "full" end
	local queue = queues[prefix]
	if not queue then
		queue = {}
		queues[prefix] = queue
		order[#order + 1] = prefix
	end
	local done = type(opts) == "table" and type(opts.done) == "function" and opts.done or nil
	for index, text in ipairs(parts) do
		queue[#queue + 1] = { prefix = prefix, text = text, channel = resolved, target = (resolved == "WHISPER" or resolved == "CHANNEL") and target or nil, id = id,
			done = index == #parts and done or nil }
	end
	queued = queued + #parts
	pump:Show()
	return true
end

-- Messages waiting to go out (for /eui diag and tests); with a prefix,
-- only that prefix's.
function E:CommQueueSize(prefix)
	if prefix ~= nil then return queues[prefix] and #queues[prefix] or 0 end
	return queued
end

-- A prefix's allowance right now (refilled for the time that passed).
local function Budget(prefix, now)
	local entry = budget[prefix]
	if not entry then
		entry = { tokens = BURST, at = now, waitUntil = 0 }
		budget[prefix] = entry
	end
	if now > entry.at then
		entry.tokens = math.min(BURST, entry.tokens + (now - entry.at) * REFILL)
		entry.at = now
	end
	return entry
end

-- Take a sent (or failed) message off its prefix's queue.
local function Remove(queue, index)
	table.remove(queue, index)
	queued = queued - 1
end

-- Tell the sender how its message went (opts.done of E:SendComm).
local function Report(done, status, reason)
	if not done then return end
	local ok, err = pcall(done, status, reason)
	if not ok then geterrorhandler()(err) end
end

-- Drop the rest of a cut message after one of its parts failed.
local function DropMessage(message, reason)
	local queue = queues[message.prefix]
	if not (message.id and queue) then return end
	for index = #queue, 1, -1 do
		if queue[index].id == message.id then
			local done = queue[index].done
			Remove(queue, index)
			Report(done, "fail", reason)
		end
	end
end

-- The next prefix (after the one that sent last) with a message waiting,
-- allowance left and no throttle wait; nil when none may send now.
local function NextPrefix(now)
	local count = #order
	for step = 1, count do
		local index = (cursor + step - 1) % count + 1
		local prefix = order[index]
		local queue = queues[prefix]
		if queue and queue[1] then
			local entry = Budget(prefix, now)
			if entry.tokens >= 1 and now >= entry.waitUntil then return prefix, index end
		end
	end
end

-- Forget empty queues (the turn order keeps only prefixes with work).
local function Tidy()
	for index = #order, 1, -1 do
		local prefix = order[index]
		if not (queues[prefix] and queues[prefix][1]) then
			queues[prefix] = nil
			table.remove(order, index)
			if cursor >= index then cursor = cursor - 1 end
		end
	end
	if cursor < 0 then cursor = 0 end
end

local THROTTLED = { AddonMessageThrottle = true, ChannelThrottle = true }

-- "ok", "throttled" (this prefix tries again later), "locked" (every
-- prefix waits) or "fail".
local function SendOne(message)
	if E:CommRestricted() then return "locked", RESTRICTED_POLL end
	local ok, result = pcall(C_ChatInfo.SendAddonMessage, message.prefix, message.text, message.channel, message.target)
	if not ok then return "fail" end
	if result == nil or result == true then return "ok" end
	local results = Enum.SendAddonMessageResult
	if results and type(result) == "number" then
		if result == results.Success then return "ok" end
		for name, value in pairs(results) do
			if value == result then
				if THROTTLED[name] then return "throttled", THROTTLE_WAIT end
				if name == "AddOnMessageLockdown" then return "locked", RESTRICTED_POLL end
				return "fail", name
			end
		end
	end
	return "ok"
end

local elapsedSince = 0
pump:SetScript("OnUpdate", function(self, elapsed)
	elapsedSince = elapsedSince + elapsed
	if elapsedSince < SEND_INTERVAL then return end
	elapsedSince = 0
	if queued <= 0 then
		Tidy()
		self:Hide()
		return
	end
	local now = GetTime()
	if now < waitUntil then return end
	local prefix, index = NextPrefix(now)
	if not prefix then return end -- every prefix with work is out of allowance
	local queue = queues[prefix]
	local message = queue[1]
	local status, wait = SendOne(message)
	if status == "locked" then
		waitUntil = now + (wait or RESTRICTED_POLL)
		return
	end
	cursor = index
	local entry = Budget(prefix, now)
	if status == "throttled" then
		-- The game's own count says no: this prefix rests, the others go on.
		entry.tokens = 0
		entry.waitUntil = now + (wait or THROTTLE_WAIT)
		return
	end
	entry.tokens = entry.tokens - 1
	Remove(queue, 1)
	if status ~= "ok" then
		Report(message.done, "fail", wait)
		DropMessage(message, wait)
		E:Debug(("Addon message on %s to %s not sent (%s)."):format(message.prefix, tostring(message.target or message.channel), tostring(wait)))
	else
		Report(message.done, "ok")
	end
	if not queue[1] then Tidy() end
	if queued <= 0 then self:Hide() end
end)

-- A restriction that ends lets the queues go on at once.
E:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", function(_, _, _, state)
	if queued <= 0 then return end
	E:AfterRestrictionEnds(state, function()
		if queued > 0 and not E:CommRestricted() then waitUntil = 0 end
	end)
end, pump)

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
-- Is `sender` someone the player knows (scope: "group", "guild",
-- "friends" or true for any)?
function E:CommTrusted(sender, scope)
	if type(sender) ~= "string" or IsSecret(sender) or sender == "" then return false end
	local short = ShortName(sender)
	local any = scope == true
	if any or scope == "group" then
		if UnitInParty(short) or UnitInRaid(short) then return true end
	end
	if (any or scope == "guild") and IsInGuild() and C_GuildInfo and C_GuildInfo.MemberExistsByName then
		local ok, member = pcall(C_GuildInfo.MemberExistsByName, sender)
		if ok and member then return true end
		ok, member = pcall(C_GuildInfo.MemberExistsByName, short)
		if ok and member then return true end
	end
	if (any or scope == "friends") and C_FriendList and C_FriendList.GetFriendInfo then
		local ok, info = pcall(C_FriendList.GetFriendInfo, short)
		if ok and info then return true end
	end
	return false
end

-- handler(payload, sender, channel, prefix); opts: trusted (see above),
-- self (also get your own messages).
function E:RegisterComm(prefix, handler, opts)
	if type(prefix) ~= "string" or prefix == "" or #prefix > 16 or type(handler) ~= "function" then return false end
	handlers[prefix] = { fn = handler, opts = opts or {} }
	return RegisterPrefix(prefix)
end

function E:UnregisterComm(prefix)
	handlers[prefix] = nil
end

local function Deliver(entry, prefix, payload, sender, channel)
	local ok, err = pcall(entry.fn, payload, sender, channel, prefix)
	if not ok then geterrorhandler()(err) end
end

local function Forget(now)
	for key, partial in pairs(incoming) do
		if now - partial.last > PART_TIMEOUT then incoming[key] = nil end
	end
end

local function OnAddonMessage(_, _, prefix, text, channel, sender)
	if IsSecret(prefix) or IsSecret(text) or IsSecret(sender) or IsSecret(channel) then return end
	local entry = type(prefix) == "string" and handlers[prefix]
	if not entry or type(text) ~= "string" or type(sender) ~= "string" then return end
	local opts = entry.opts
	-- Your own messages come back on group and guild channels (never
	-- the display name, which may carry the surname).
	local mine = E:IsMe(ShortName(sender))
	if not opts.self and mine then return end
	if opts.trusted and not mine and not E:CommTrusted(sender, opts.trusted) then return end
	local mark = text:sub(1, 1)
	if mark == "1" then
		Deliver(entry, prefix, text:sub(2), sender, channel)
		return
	end
	if mark ~= "P" then return end
	local id, index, total, part = text:match("^P(%x+)\t(%d+)\t(%d+)\t(.*)$")
	index, total = tonumber(index), tonumber(total)
	if not (id and index and total) or total < 1 or total > MAX_PARTS or index < 1 or index > total then return end
	local now = GetTime()
	Forget(now)
	local key = prefix .. "\1" .. sender .. "\1" .. id
	local partial = incoming[key]
	if not partial or partial.total ~= total then
		partial = { parts = {}, total = total, got = 0 }
		incoming[key] = partial
	end
	partial.last = now
	if partial.parts[index] then return end
	partial.parts[index] = part
	partial.got = partial.got + 1
	if partial.got < total then return end
	incoming[key] = nil
	Deliver(entry, prefix, table.concat(partial.parts), sender, channel)
end

E:RegisterEvent("CHAT_MSG_ADDON", OnAddonMessage, handlers)
