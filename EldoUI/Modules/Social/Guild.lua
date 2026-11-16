-- EldoUI Social: the guild and communities window (communities-guild).
--
-- Blizzard_Communities: CommunitiesFrame with the community list, the side
-- tabs (chat, roster, guild benefits, guild info, play style), the member
-- roster, guild news and info, and the small guild dialogs (member detail,
-- guild log, text edit, news filters) plus Blizzard_GuildControlUI.
--   Skin     art-style panels, flat side tabs, rows, buttons and inputs
--   Move     drag by the title bar, scale (Modules/Social.lua window mover)
--   Improve  class colors in the roster, also for offline members (dimmed)
-- Blizzard already colors online names by class; EldoUI only re-colors
-- names after Blizzard has drawn the row, from the member info the game
-- gives the roster. Nothing is sent, invited or changed for the player.
-- Written from scratch for EldoUI; no code or media from other addons.
local _, E = ...

local M = E:GetModule("Social")
local K = M.kit
local Usable, Try = K.Usable, K.Try

local ID = "communities-guild"
local ADDON = "Blizzard_Communities"

local function Skin() return M.active and E:BlizzardAllowed(ID, "skin") end
local function Improve() return M.active and E:BlizzardAllowed(ID, "improve") end

local rowColored = setmetatable({}, { __mode = "k" }) -- member row -> true while we colored its name

---------------------------------------------------------------------------
-- Local guild history and the roster behind its companion view
---------------------------------------------------------------------------
local L = E.L
local Kit = E.UIKit
local Read, Plain = E.PlainCall, E.Plain
local MAX_MEMBERS, MAX_GUILDS, MAX_HINTS = 1000, 12, 80
local DAY = 86400
local historyOwner = {}
local live, historyWindow, historyButton
local restrictionRevision, restrictionChanging = 0, false
local RefreshHistory, RefreshHistoryButton, HistoryShown, CancelRead

E:RegisterGlobal("GuildHistory", { guilds = {}, entries = 1000, days = 90 })
M.defaults.guild.noteLinks = false
M.defaults.guild.noteTemplate = ""
M.defaults.guild.chatMain = false

local function IsTable(value)
	return type(Plain(value)) == "table" and (not canaccesstable or canaccesstable(value))
end

local function Integer(value, low, high)
	return type(value) == "number" and value >= low and value <= high and value % 1 == 0
end

local function Text(value, limit, allowEmpty)
	value = Plain(value)
	if type(value) ~= "string" or #value > limit or value:find("[%c|]") then return end
	value = strtrim(value)
	if value ~= "" or allowEmpty then return value end
end

local function PlayerGUID(value)
	local guid = Text(value, 64)
	return guid and guid:match("^Player%-%d+%-%x+$") and guid or nil
end

local function NativeID(value)
	value = Plain(value)
	if Integer(value, 1, 9007199254740991) then return value, ("%.0f"):format(value) end
	if type(value) == "string" and #value <= 30 and value:match("^%d+$") and value:find("[1-9]") then return value, value end
end

local function Unlocked()
	return not restrictionChanging and Read(C_ChatInfo and C_ChatInfo.InChatMessagingLockdown) == false
end

local function GuildID()
	if Read(IsInGuild) == true then return NativeID(Read(C_Club and C_Club.GetGuildClubId)) end
end

local function Store()
	local store = E:GetGlobal("GuildHistory")
	if not IsTable(store) then return end
	if not IsTable(store.guilds) then store.guilds = {} end
	if not Integer(Plain(store.entries), 100, 5000) then store.entries = 1000 end
	if not Integer(Plain(store.days), 7, 365) then store.days = 90 end
	return store
end

local function GuildRecord(store, key, name)
	local guild = store.guilds[key]
	if not IsTable(guild) then guild = {}; store.guilds[key] = guild end
	if not IsTable(guild.members) then guild.members = {} end
	if not IsTable(guild.log) then guild.log = {} end
	if not IsTable(guild.links) then guild.links = {} end
	guild.name, guild.at = name or guild.name, time()
	return guild
end

local function TrimGuilds(store, own)
	local ordered = {}
	for key, guild in pairs(store.guilds) do
		if key ~= own then
			local stamp = IsTable(guild) and Plain(guild.at)
			if type(stamp) == "number" then ordered[#ordered + 1] = { key = key, at = stamp }
			else store.guilds[key] = nil end
		end
	end
	table.sort(ordered, function(a, b) return a.at > b.at end)
	for index = MAX_GUILDS, #ordered do store.guilds[ordered[index].key] = nil end
end

local function Lease(state)
	if not (state and state == live and Improve() and M.db == state.db and Plain(E.charKey) == state.character and Unlocked()) then return false end
	local id = GuildID()
	return state == live and id == state.id and M.db == state.db and Plain(E.charKey) == state.character
		and E:GetGlobal("GuildHistory") == state.store
end

local function GuildClub(club, id)
	local kinds = Enum and Enum.ClubType
	return kinds and kinds.Guild ~= nil and IsTable(club) and Plain(club.clubType) == kinds.Guild and Plain(club.clubId) == id
end

local function CurrentClub(state)
	if not Lease(state) or Read(C_Club.AreMembersReady, state.id) ~= true then return end
	local club = Read(C_Club.GetClubInfo, state.id)
	if not GuildClub(club, state.id) then return end
	local raw = club.memberCount
	local count = Plain(raw)
	if E.Secret(raw) or (count ~= nil and not Integer(count, 1, MAX_MEMBERS)) then return end
	return club, count
end

local function ReadIDs(state, count)
	local ids = Read(C_Club.GetClubMembers, state.id)
	if not IsTable(ids) then return end
	local list, idsSeen, size = {}, {}, 0
	for index, raw in pairs(ids) do
		local id = NativeID(raw)
		if not Integer(Plain(index), 1, MAX_MEMBERS) or not id or idsSeen[id] then return end
		idsSeen[id], list[index], size = true, id, size + 1
		E.SliceYield()
	end
	if size == 0 or (count and count ~= size) or #list ~= size then return end
	for index = 1, size do if not list[index] then return end end
	return list, idsSeen
end

local function NumberField(value, low, high)
	value = Plain(value)
	return Integer(value, low, high) and value or nil
end

local function ReadMember(state, opaque)
	if not Unlocked() then return end
	local info = Read(C_Club.GetMemberInfo, state.id, opaque)
	if not IsTable(info) or Plain(info.memberId) ~= opaque then return end
	local guid, name = PlayerGUID(info.guid), Text(info.name, 160)
	if not guid or not name then return end
	return { guid = guid, name = name, class = NumberField(info.classID, 1, 64), level = NumberField(info.level, 1, 200),
		rank = Text(info.guildRank, 160), order = NumberField(info.guildRankOrder, 1, 100), note = Text(info.memberNote, 512, true),
		presence = NumberField(info.presence, 0, 5), year = NumberField(info.lastOnlineYear, 0, 99),
		month = NumberField(info.lastOnlineMonth, 0, 12), day = NumberField(info.lastOnlineDay, 0, 366),
		hour = NumberField(info.lastOnlineHour, 0, 24) }
end

local function NameKey(name)
	return type(name) == "string" and name:lower() or nil
end

local function NameIndex(state, row, add)
	local key = NameKey(row.name)
	local names = state.names[key]
	if add then
		if not names then names = {}; state.names[key] = names end
		names[row.guid] = true
	elseif names then
		names[row.guid] = nil
		if not next(names) then state.names[key] = nil end
	end
end

local function ResolveName(state, name)
	local key = NameKey(name)
	local names = key and state.names[key]
	if not names then return end
	local guid = next(names)
	if guid and next(names, guid) == nil then return guid end
end

local eventLabels = { join = E.Key("Joined the guild"), rejoin = E.Key("Rejoined the guild"), left = E.Key("Left the guild"),
	removed = E.Key("Removed from the guild"), gone = E.Key("No longer in the guild"), promote = E.Key("Promoted"),
	demote = E.Key("Demoted"), rank = E.Key("Rank changed"), level = E.Key("Reached level %d"), note = E.Key("Public note changed") }
local originLabels = { live = E.Key("Live"), login = E.Key("Seen on login"), roster = E.Key("Seen in roster") }

local function Prune(state)
	local log, store = state.guild.log, state.store
	local oldest, keep = time() - store.days * DAY, {}
	local first = math.max(1, #log - store.entries + 1)
	for index = first, #log do
		local entry = log[index]
		if IsTable(entry) and PlayerGUID(entry.guid) and Text(entry.name, 160) and eventLabels[Plain(entry.kind)]
			and NumberField(entry.at, oldest, 4102444800) then keep[#keep + 1] = entry end
		E.SliceYield()
	end
	state.guild.log = keep
	local departures, recent = {}, {}
	for _, entry in ipairs(keep) do
		if entry.kind == "left" or entry.kind == "removed" or entry.kind == "gone" then
			departures[entry.guid] = entry.at
			if time() - entry.at <= 5 then recent[NameKey(entry.name)] = entry end
		elseif entry.kind == "rank" and time() - entry.at <= 5 then
			recent[NameKey(entry.name)] = entry
		elseif entry.kind == "join" or entry.kind == "rejoin" then
			recent[NameKey(entry.name)] = nil
		end
		E.SliceYield()
	end
	state.departed, state.recent = departures, recent
end

local function Append(state, row, kind, origin, detail)
	local entry = { at = time(), guid = row.guid, name = row.name, kind = kind, origin = origin, detail = detail }
	local log = state.guild.log
	log[#log + 1] = entry
	return entry
end

local function RecentDeparture(state, guid)
	local stamp = state.departed[guid]
	return stamp and stamp >= time() - state.store.days * DAY
end

local function Departure(state, row, origin)
	local key = NameKey(row.name)
	local hint = state.hints[key]
	local kind = hint and time() - hint.at <= 5 and (hint.kind == "left" or hint.kind == "removed") and hint.kind
	local entry = Append(state, row, kind or "gone", kind and "live" or origin)
	state.recent[key] = entry
	state.departed[row.guid] = entry.at
	state.hints[key] = nil
end

local function SavedMember(row)
	return { guid = row.guid, name = row.name, class = row.class, level = row.level,
		rank = row.rank, order = row.order, note = row.note }
end

local function ChangeMember(state, guid, row, origin, log)
	local members = state.guild.members
	local old = members[guid]
	if old and (not IsTable(old) or not Text(old.name, 160) or PlayerGUID(old.guid) ~= guid) then old, log = nil, false end
	if not row then
		if old and log then Departure(state, old, origin) end
		members[guid] = nil
		if state.rows[guid] then NameIndex(state, state.rows[guid], false) end
		state.rows[guid] = nil
		return
	end
	if log and not old then
		local key = NameKey(row.name)
		local hint = state.hints[key]
		local observed = hint and hint.kind == "join" and time() - hint.at <= 5 and "live" or origin
		Append(state, row, RecentDeparture(state, guid) and "rejoin" or "join", observed)
		state.recent[key], state.hints[key] = nil, nil
	elseif log and old then
		if row.rank and Text(old.rank, 160) and row.rank ~= old.rank then
			local hint = state.hints[NameKey(row.name)]
			local kind = hint and time() - hint.at <= 5 and hint.detail == row.rank
				and (hint.kind == "promote" or hint.kind == "demote") and hint.kind
			local entry = Append(state, row, kind or "rank", kind and "live" or origin, row.rank)
			state.recent[NameKey(row.name)] = entry
			state.hints[NameKey(row.name)] = nil
		end
		if row.level and NumberField(old.level, 1, 200) and row.level > old.level then Append(state, row, "level", origin, row.level) end
		if row.note ~= nil and Text(old.note, 512, true) ~= nil and row.note ~= old.note then Append(state, row, "note", origin) end
	end
	local data = SavedMember(row)
	if old then
		for _, key in ipairs({ "class", "level", "rank", "order", "note" }) do
			if data[key] == nil then data[key] = Plain(old[key]) end
		end
	end
	members[guid] = data
	if state.rows[guid] then NameIndex(state, state.rows[guid], false) end
	state.rows[guid] = row
	NameIndex(state, row, true)
end

local function TemplateParts()
	if not M.db.guild.noteLinks then return end
	local template = Text(M.db.guild.noteTemplate, 160)
	if not template then return end
	local offset = template:find("{main}", 1, true)
	if not offset or template:find("{main}", offset + 6, true) then return end
	local before, after = template:sub(1, offset - 1), template:sub(offset + 6)
	if before ~= "" or after ~= "" then return before, after end
end

local function MainGUID(state, guid, before, after)
	local row = state.rows[guid]
	if not row then return end
	local main = PlayerGUID(state.guild.links[guid])
	if not main and before and row.note and #row.note > #before + #after
		and row.note:sub(1, #before) == before and (after == "" or row.note:sub(-#after) == after) then
		main = ResolveName(state, Text(row.note:sub(#before + 1, #row.note - #after), 160))
	end
	if main and main ~= guid and state.rows[main] and not state.guild.links[main] then return main end
end

local function BuildLinks(state)
	local before, after = TemplateParts()
	local links = {}
	for guid in pairs(state.rows) do
		links[guid] = MainGUID(state, guid, before, after)
		E.SliceYield()
	end
	for guid, main in pairs(links) do if links[main] then links[guid] = nil end end
	state.main = links
end

local function Changed(state)
	if not Lease(state) then return end
	if RefreshHistory then RefreshHistory() end
end

local function CopyRows(source)
	local copy = {}
	for key, value in pairs(source) do
		copy[key] = value
		E.SliceYield()
	end
	return copy
end

local function CanPublish(state, scan)
	return Lease(state) and state.scan == scan and state.revision == scan.revision and (state.login or HistoryShown())
end

local function Complete(state, scan, rows, idMap, count, ids)
	if not CanPublish(state, scan) then return end
	local guild = state.guild
	local origin = state.login and "login" or "roster"
	local first, missing = guild.baseline ~= true, {}
	for guid in pairs(guild.members) do
		if not rows[guid] then missing[#missing + 1] = guid end
		E.SliceYield()
	end
	local canRemove, absence = count ~= nil
	if not canRemove and #missing > 0 then
		local earlier = state.absence
		canRemove = earlier and earlier.settled > 0 and earlier.settled + 1 == state.settled and #earlier.missing == #missing
		if canRemove then
			for _, guid in ipairs(missing) do if not earlier.ids[guid] then canRemove = false; break end end
		end
		if not canRemove then
			local missingIDs = {}
			for _, guid in ipairs(missing) do missingIDs[guid] = true end
			absence = { settled = state.settled, missing = missing, ids = missingIDs }
		end
	end
	-- An uncertain partial list must not grow persistent membership past
	-- the same limit as an admitted complete roster.
	if not canRemove and #missing + #ids > MAX_MEMBERS then return end
	-- All calculations use a private working copy. Publish no state until
	-- the final complete membership and lease still match.
	local stage = { store = state.store, hints = CopyRows(state.hints), recent = {}, departed = CopyRows(state.departed),
		rows = {}, names = {}, guild = { members = CopyRows(guild.members), log = CopyRows(guild.log), links = guild.links } }
	if canRemove then
		for _, guid in ipairs(missing) do
			ChangeMember(stage, guid, nil, origin, not first)
			E.SliceYield()
		end
	end
	for guid, row in pairs(rows) do
		ChangeMember(stage, guid, row, origin, not first)
		E.SliceYield()
	end
	Prune(stage)
	BuildLinks(stage)
	if not CanPublish(state, scan) then return end
	local final, finalCount = CurrentClub(state)
	if not final or count ~= finalCount then return end
	local finalList, finalIDs = ReadIDs(state, finalCount)
	if not finalList or #finalList ~= #ids then return end
	for _, id in ipairs(ids) do if not finalIDs[id] then return end end
	local current, currentCount = CurrentClub(state)
	if not current or currentCount ~= count or not CanPublish(state, scan) then return end
	guild.members, guild.log, guild.baseline = stage.guild.members, stage.guild.log, true
	state.rows, state.names, state.opaque, state.loaded = stage.rows, stage.names, idMap, true
	state.hints, state.recent, state.departed = stage.hints, stage.recent, stage.departed
	state.main, state.absence = stage.main, absence
	state.login = false
	scan.accepted = true
	Changed(state)
end

local function Collect(state, scan)
	local club, count = CurrentClub(state)
	if not club then return end
	local list = ReadIDs(state, count)
	if not list then return end
	local me = PlayerGUID(Read(UnitGUID, "player"))
	if not me then return end
	local rows, idMap = {}, {}
	for _, id in ipairs(list) do
		if live ~= state or state.revision ~= scan.revision then return end
		local row = ReadMember(state, id)
		if not row or rows[row.guid] then return end
		rows[row.guid], idMap[id] = row, row.guid
		E.SliceYield()
	end
	if not rows[me] then return end
	Complete(state, scan, rows, idMap, count, list)
end

CancelRead = function(state)
	if state.timer then state.timer:Cancel(); state.timer = nil end
	local scan = state.scan
	state.scan = nil
	if scan and scan.handle then scan.handle:Cancel() end
end

HistoryShown = function()
	return historyWindow and historyWindow:IsOpen() or false
end

local function QueueRoster(state)
	if not Lease(state) or not (state.login or HistoryShown()) then return end
	CancelRead(state)
	state.timer = C_Timer.NewTimer(0.15, function()
		state.timer = nil
		if not Lease(state) or not (state.login or HistoryShown()) then return end
		local scan = { revision = state.revision }
		state.scan = scan
		scan.handle = E:RunSliced(function() Collect(state, scan) end, 3, function()
			if state.scan == scan then
				if not scan.accepted then state.absence = nil end
				state.scan = nil
				if RefreshHistory then RefreshHistory() end
			end
		end)
	end)
end

local function LiveGuild(state)
	if not Lease(state) or Read(C_Club.AreMembersReady, state.id) ~= true then return false end
	local info = Read(C_Club.GetClubInfo, state.id)
	return GuildClub(info, state.id)
end

local function NewGuild()
	local id, key = GuildID()
	local character, store = Plain(E.charKey), Store()
	if not (id and store and type(character) == "string") then return end
	local info = Read(C_Club.GetClubInfo, id)
	if not GuildClub(info, id) then return end
	local guild = GuildRecord(store, key, Text(info.name, 160))
	local state = { id = id, key = key, db = M.db, store = store, guild = guild, character = character,
		revision = 0, settled = 0, login = true, rows = {}, opaque = {}, names = {}, main = {}, hints = {}, recent = {}, departed = {} }
	TrimGuilds(store, key)
	Prune(state)
	return state
end

local systemKeys = {
	{ "ERR_GUILD_JOIN_S", "join", 1 }, { "ERR_GUILD_LEAVE_S", "left", 1 }, { "ERR_GUILD_REMOVE_SS", "removed", 1 },
	{ "ERR_GUILD_PROMOTE_SSS", "promote", 2 }, { "ERR_GUILD_DEMOTE_SSS", "demote", 2 },
}
local function RecordSystem(state, line)
	line = Plain(line)
	if type(line) ~= "string" or not LiveGuild(state) or not E.ChatParse then return end
	for _, spec in ipairs(systemKeys) do
		local args = E.ChatParse:MatchFormat(line, rawget(_G, spec[1]))
		local name = args and Text(args[spec[3]], 160)
		if name then
			local kind, key = spec[2], NameKey(name)
			local recent, detail = state.recent[key], Text(args[3], 160)
			local departure = recent and (kind == "left" or kind == "removed") and recent.kind == "gone"
				and not state.guild.members[recent.guid]
			local rank = recent and (kind == "promote" or kind == "demote") and recent.kind == "rank"
				and detail and detail == recent.detail and ResolveName(state, name) == recent.guid
			if not Lease(state) then return end
			CancelRead(state)
			state.revision = state.revision + 1
			if (departure or rank) and time() - recent.at <= 5 then
				recent.kind, recent.origin = kind, "live"
				Changed(state)
			else
				local count = 0
				for _ in pairs(state.hints) do count = count + 1 end
				if count >= MAX_HINTS then wipe(state.hints) end
				state.hints[key] = { kind = kind, detail = detail, at = time() }
			end
			QueueRoster(state)
			return
		end
	end
end

local function MemberEvent(state, event, memberID)
	if not Lease(state) then return end
	local logCount = #state.guild.log
	local opaque = NativeID(memberID)
	if not opaque then return end
	local guid = state.opaque[opaque]
	if event == "CLUB_MEMBER_REMOVED" then
		if guid then
			ChangeMember(state, guid, nil, "live", state.guild.baseline == true)
			state.opaque[opaque], state.main[guid] = nil, nil
		end
	elseif LiveGuild(state) and (event ~= "CLUB_MEMBER_PRESENCE_UPDATED" or HistoryShown()) then
		local row = ReadMember(state, opaque)
		if row and Lease(state) and (not guid or guid == row.guid) then
			state.opaque[opaque] = row.guid
			ChangeMember(state, row.guid, row, "live", state.guild.baseline == true)
			local before, after = TemplateParts()
			state.main[row.guid] = MainGUID(state, row.guid, before, after)
		end
	end
	if #state.guild.log ~= logCount then Prune(state) end
	Changed(state)
end

local events = { "INITIAL_CLUBS_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE",
	"CLUB_MEMBER_ADDED", "CLUB_MEMBER_REMOVED", "CLUB_MEMBER_UPDATED", "CLUB_MEMBER_PRESENCE_UPDATED",
	"CLUB_MEMBERS_UPDATED", "CHAT_MSG_SYSTEM", "ADDON_RESTRICTION_STATE_CHANGED" }
local listening

local function GuildHistoryEvent(_, event, first, second)
	if not Improve() then return end
	if event == "ADDON_RESTRICTION_STATE_CHANGED" then
		local kind = Enum and Enum.AddOnRestrictionType
		if kind and Plain(first) ~= kind.Chat then return end
		restrictionRevision = restrictionRevision + 1
		restrictionChanging = true
		local revision = restrictionRevision
		if live then
			CancelRead(live)
			live.absence = nil
		end
		if RefreshHistory then RefreshHistory() end
		-- The native lockdown value changes after this dispatch returns.
		C_Timer.After(0, function()
			if revision ~= restrictionRevision then return end
			restrictionChanging = false
			if Improve() then M:SyncGuildHistory() end
		end)
		return
	end
	M:SyncGuildHistory(true)
	local state = live
	if not Lease(state) then return end
	if event == "CHAT_MSG_SYSTEM" then
		RecordSystem(state, first)
		return
	end
	if event:find("^CLUB_MEMBER") and Plain(first) ~= state.id then return end
	CancelRead(state)
	state.revision = state.revision + 1
	if event == "CLUB_MEMBERS_UPDATED" then state.settled = state.settled + 1 end
	if event:find("^CLUB_MEMBER_") then MemberEvent(state, event, second) end
	QueueRoster(state)
end

function M:SyncGuildHistory(quiet)
	if not Improve() then
		if listening then
			for _, event in ipairs(events) do E:UnregisterEvent(event, historyOwner) end
			listening = nil
		end
		if live then CancelRead(live); live = nil end
		if historyWindow then historyWindow:Close() end
		E:CancelConfirm("ELDOUI_GUILD_LINK_MAIN")
		E:CancelConfirm("ELDOUI_GUILD_CLEAR_HISTORY")
		if RefreshHistoryButton then RefreshHistoryButton() end
		return
	end
	if not listening then
		listening = true
		for _, event in ipairs(events) do E:RegisterEvent(event, GuildHistoryEvent, historyOwner) end
	end
	if not Unlocked() then
		if live then CancelRead(live) end
		if RefreshHistory then RefreshHistory() end
		return
	end
	local id = GuildID()
	if not live or live.id ~= id or live.character ~= Plain(E.charKey) or live.store ~= E:GetGlobal("GuildHistory") then
		if live then CancelRead(live) end
		live = NewGuild()
	elseif live.db ~= M.db then
		CancelRead(live)
		live.db = M.db
	end
	if live and not quiet then
		local noteLinks, template = self.db.guild.noteLinks, self.db.guild.noteTemplate
		if live.noteLinks ~= noteLinks or live.template ~= template then
			live.noteLinks, live.template = noteLinks, template
			BuildLinks(live)
		end
		QueueRoster(live)
	end
	if RefreshHistoryButton then RefreshHistoryButton() end
	if HistoryShown() and RefreshHistory then RefreshHistory() end
end

function M:GuildMainForChat(guid)
	if not (Improve() and M.db.guild.chatMain and Lease(live)) then return end
	guid = PlayerGUID(guid)
	local main = guid and live.rows[guid] and live.rows[live.main[guid]]
	if not main then return end
	local streamer = E.modules.Streamer
	if streamer and streamer.Streaming() and streamer.db.chat then return end
	return main.name
end


---------------------------------------------------------------------------
-- Guild history window, opened from the native guild or its slash command
---------------------------------------------------------------------------
local function ClassName(class)
	local info = class and Read(C_CreatureInfo and C_CreatureInfo.GetClassInfo, class)
	return IsTable(info) and Text(info.className, 100) or nil
end

local function DisplayName(row, setting)
	local streamer = E.modules.Streamer
	if streamer and streamer.Streaming() and streamer.db[setting or "frames"] then
		local alias = streamer:OtherAlias(streamer.Key(row.name), ClassName(row.class))
		if alias then return alias, true end
	end
	return E:FormatNameString(row.name, "GuildHistory"), false
end

local function OfflineAge(row)
	local offline = Enum and Enum.ClubMemberPresence and Enum.ClubMemberPresence.Offline
	if not offline or row.presence ~= offline or not (row.year or row.month or row.day or row.hour) then return end
	local years, months, days, hours = row.year or 0, row.month or 0, row.day or 0, row.hour or 0
	return years * 365 + months * 28 + days + hours / 24
end

local function LastOnline(row)
	local kinds = Enum and Enum.ClubMemberPresence
	if kinds and OfflineAge(row) then
		local since = TimeUtil and Read(TimeUtil.GetRecentTimeDate, row.year, row.month, row.day, row.hour)
		return since or L["Offline"]
	end
	if kinds and row.presence == kinds.Offline then return L["Offline"] end
	if kinds and row.presence and row.presence ~= kinds.Unknown then return L["Online"] end
	return L["Unknown"]
end

local function FilterChanged(frame)
	if frame.filterTimer then frame.filterTimer:Cancel() end
	frame.filterTimer = C_Timer.NewTimer(0.1, function()
		frame.filterTimer = nil
		if frame:IsVisible() and RefreshHistory then RefreshHistory() end
	end)
end

local function MainLine(tooltip, guid, setting)
	if not Lease(live) then return end
	local main = live.rows[live.main[guid]]
	if main then Kit.TipText(tooltip, L["Main: %s"]:format(DisplayName(main, setting))) end
end

local function LinkMenu(parent, row)
	local state = live
	if not Lease(state) or not state.rows[row.guid] then return end
	Kit.ContextMenu(parent, function(_, root)
		root:CreateButton(L["Link to a main"], function()
			E:ShowConfirm({ key = "ELDOUI_GUILD_LINK_MAIN", title = L["Link to a main"],
				text = L["Enter the full guild name of this member's main."], accept = ACCEPT,
				edit = { text = "", maxLetters = 80 }, onAccept = function(_, text)
					if not Lease(state) or not state.rows[row.guid] then return end
					local guid = ResolveName(state, Text(text, 160))
					if not guid or guid == row.guid or state.main[guid] then
						Kit.Toast(parent, L["The main must be one distinct guild member with no main link."], { warn = true })
						return
					end
					CancelRead(state)
					state.guild.links[row.guid] = guid
					state.revision = state.revision + 1
					BuildLinks(state)
					Changed(state)
				end })
		end)
		if state.guild.links[row.guid] then
			root:CreateButton(L["Remove main link"], function()
				if Lease(state) then
					CancelRead(state)
					state.guild.links[row.guid] = nil
					state.revision = state.revision + 1
					BuildLinks(state)
					Changed(state)
				end
			end)
		end
	end, { at = "owner" })
end

local function RosterColumns()
	return {
		{ key = "name", title = E.Key("Name"), value = function(row) return row.display end },
		{ key = "level", title = E.Key("Level"), width = 66, align = "RIGHT", value = function(row) return row.level end },
		{ key = "class", title = E.Key("Class"), width = 112, value = function(row) return row.className end },
		{ key = "rank", title = E.Key("Rank"), width = 142, value = function(row) return row.rank end },
		{ key = "online", title = E.Key("Last online"), width = 160, value = function(row) return row.age end,
			text = function(row) return row.lastOnline end },
	}
end

local function RosterTip(widget)
	local row = widget.guildMember
	if not row or not Lease(live) or live.rows[row.guid] ~= row.member then return end
	GameTooltip:SetOwner(widget, "ANCHOR_RIGHT")
	GameTooltip:SetText(row.display)
	if row.note and row.note ~= "" then Kit.TipText(GameTooltip, row.note) end
	Kit.TipText(GameTooltip, row.lastOnline)
	MainLine(GameTooltip, row.guid)
	Kit.TipText(GameTooltip, L["Click to manage main links"])
	GameTooltip:Show()
end

local function BuildRoster(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetAllPoints()
	frame.classValues, frame.rankValues = {}, {}
	local function Change() FilterChanged(frame) end
	frame.search = Kit.Input(frame, { hint = L["Search names and public notes"], width = 292, maxLetters = 80, onChange = Change })
	frame.search:SetPoint("TOPLEFT", 4, -4)
	frame.class = Kit.Dropdown(frame, { width = 150, values = function() return frame.classValues end,
		get = function() return frame.classFilter or 0 end, set = function(value) frame.classFilter = value; Change() end })
	frame.class:SetPoint("LEFT", frame.search, "RIGHT", 8, 0)
	frame.rank = Kit.Dropdown(frame, { width = 180, values = function() return frame.rankValues end,
		get = function() return frame.rankFilter or "" end, set = function(value) frame.rankFilter = value; Change() end })
	frame.rank:SetPoint("LEFT", frame.class, "RIGHT", 8, 0)
	local function Range(label, width)
		return Kit.Input(frame, { hint = label, width = width, numeric = true, maxLetters = 3, onChange = Change, tipTitle = label })
	end
	frame.min = Range(L["Min. level"], 124)
	frame.min:SetPoint("TOPLEFT", frame.search, "BOTTOMLEFT", 0, -8)
	frame.max = Range(L["Max. level"], 124)
	frame.max:SetPoint("LEFT", frame.min, "RIGHT", 8, 0)
	frame.days = Range(L["Offline days"], 142)
	frame.days:SetPoint("LEFT", frame.max, "RIGHT", 8, 0)
	Kit.TabOrder(frame.search, frame.min, frame.max, frame.days)
	frame.list = Kit.CreateTable(frame, RosterColumns(), {
		rowHeight = function() return math.ceil(math.max(21, E:TextScale() * 14 + 4)) end,
		createRow = function(row)
			E:UseNameFont(row.cells[1])
			row:HookScript("OnEnter", RosterTip)
			row:HookScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
		end,
		updateRow = function(widget, row) widget.guildMember = row end,
		onClick = function(row, _, widget) LinkMenu(widget, row) end,
		empty = { L["No guild members to show"], L["Wait for the full roster or clear the filters."] },
	})
	frame.list:SetPoint("TOPLEFT", frame.min, "BOTTOMLEFT", -4, -8)
	frame.list:SetPoint("BOTTOMRIGHT")
	return frame
end

local function RefreshRoster(frame)
	local state = frame.viewState
	local source = state and state.rows or {}
	local classes, ranks, rows = {}, {}, {}
	local search = E:FoldText(Text(frame.search:GetText(), 240, true) or "")
	local low, high = tonumber(Plain(frame.min:GetText())), tonumber(Plain(frame.max:GetText()))
	local days = tonumber(Plain(frame.days:GetText()))
	local classFilter, rankFilter = frame.classFilter or 0, frame.rankFilter or ""
	for guid, row in pairs(source) do
		local class = row.class and (classes[row.class] or ClassName(row.class))
		if class then classes[row.class] = class end
		if row.rank then ranks[row.rank] = true end
		local age = OfflineAge(row)
		local display, masked = DisplayName(row)
		local note = not masked and row.note or nil
		local name = masked and display or row.name
		if (not low or row.level and row.level >= low) and (not high or row.level and row.level <= high)
			and (not days or age and age > days) and (classFilter == 0 or classFilter == row.class)
			and (rankFilter == "" or rankFilter == row.rank)
			and (search == "" or E:FoldText(name .. " " .. (note or "")):find(search, 1, true)) then
			rows[#rows + 1] = { guid = guid, member = row, display = display, level = row.level, className = class,
				rank = row.rank, note = note, lastOnline = LastOnline(row), age = age }
		end
		E.SliceYield()
	end
	local cv, rv = {}, {}
	for id, name in pairs(classes) do cv[#cv + 1] = { id, name } end
	for name in pairs(ranks) do rv[#rv + 1] = { name, name } end
	local function ByName(a, b) return a[2] < b[2] end
	table.sort(cv, ByName)
	table.sort(rv, ByName)
	table.insert(cv, 1, { 0, L["All classes"] })
	table.insert(rv, 1, { "", L["All guild ranks"] })
	if state and (not Lease(state) or frame.viewState ~= state) then return end
	frame.classValues, frame.rankValues = cv, rv
	frame.class:Refresh()
	frame.rank:Refresh()
	frame.list:SetData(rows)
end

local function RetentionMenu(owner)
	local state = live
	if not Lease(state) then return end
	Kit.ContextMenu(owner, function(_, root)
		local entries = root:CreateButton(L["History entries to keep"])
		local days = root:CreateButton(L["History days to keep"])
		local function Choices(menu, key, values)
			for _, value in ipairs(values) do
				menu:CreateRadio(tostring(value), function() return state.store[key] == value end, function()
					if not Lease(state) then return end
					CancelRead(state)
					state.store[key] = value
					state.revision = state.revision + 1
					Prune(state)
					Changed(state)
				end)
			end
		end
		Choices(entries, "entries", { 100, 250, 500, 1000, 2000, 5000 })
		Choices(days, "days", { 7, 30, 90, 180, 365 })
		root:CreateDivider()
		root:CreateButton(L["Clear this guild's history"], function()
			E:ShowConfirm({ key = "ELDOUI_GUILD_CLEAR_HISTORY", title = L["Guild history"],
				text = L["Clear the recorded changes for this guild?"], accept = L["Clear"], danger = true,
				onAccept = function()
					if not Lease(state) then return end
					CancelRead(state)
					state.guild.log, state.departed, state.recent = {}, {}, {}
					state.revision = state.revision + 1
					Changed(state)
				end })
		end)
	end, { at = "owner" })
end

local function BuildHistory(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetAllPoints()
	frame.search = Kit.Input(frame, { width = 310, hint = L["Search guild history"], maxLetters = 80,
		onChange = function() FilterChanged(frame) end })
	frame.search:SetPoint("TOPLEFT", 4, -4)
	frame.keep = Kit.Button(frame, L["History options"], 162, nil, RetentionMenu)
	frame.keep:SetPoint("TOPRIGHT", -4, -4)
	frame.list = Kit.CreateTable(frame, {
		{ key = "when", title = E.Key("Date and time"), width = 156, value = function(row) return row.at end,
			text = function(row) return date("%Y-%m-%d %H:%M", row.at) end },
		{ key = "name", title = E.Key("Name"), width = 154, value = function(row) return row.display end },
		{ key = "change", title = E.Key("Change"), value = function(row) return row.change end },
		{ key = "origin", title = E.Key("Observed"), width = 148, value = function(row) return row.origin end },
	}, { sortKey = "when", sortDown = true, rowHeight = function() return math.ceil(math.max(21, E:TextScale() * 14 + 4)) end,
		empty = { L["No guild changes to show"], L["The first complete roster is the starting point for history."] },
	})
	frame.list:SetPoint("TOPLEFT", frame.search, "BOTTOMLEFT", -4, -8)
	frame.list:SetPoint("BOTTOMRIGHT")
	return frame
end

local function RefreshLog(frame)
	local rows = {}
	local state = frame.viewState
	local search = E:FoldText(Text(frame.search:GetText(), 240, true) or "")
	for _, entry in ipairs(state and state.guild.log or {}) do
		local label = eventLabels[entry.kind]
		if label then
			local display, masked = DisplayName(entry)
			local name = masked and display or entry.name
			local change = L[label]
			local detail = Text(entry.detail, 160)
			if entry.kind == "level" and NumberField(entry.detail, 1, 200) then change = change:format(entry.detail)
			elseif detail then change = change .. "  ·  " .. detail end
			local origin = L[originLabels[Plain(entry.origin)] or originLabels.roster]
			if search == "" or E:FoldText(name .. " " .. change .. " " .. origin):find(search, 1, true) then
				rows[#rows + 1] = { at = entry.at, display = display, change = change, origin = origin }
			end
		end
		E.SliceYield()
	end
	if state and (not Lease(state) or frame.viewState ~= state) then return end
	frame.keep:SetEnabled(state ~= nil)
	frame.list:SetData(rows)
end

local function UpdateView(frame, draw)
	if frame.viewJob then frame.viewJob:Cancel() end
	frame.viewState = Lease(live) and live or nil
	if not frame.viewState then
		frame.list:SetData({})
		if frame.keep then frame.keep:SetEnabled(false) end
		return
	end
	frame.viewJob = E:RunSliced(function() draw(frame) end, 3)
end

local function View(update)
	return function(frame) UpdateView(frame, update) end
end

RefreshHistory = function()
	if HistoryShown() then historyWindow:Refresh() end
end

function M:OpenGuildHistory(tab)
	if not Improve() then return false end
	self:SyncGuildHistory(true)
	if not historyWindow then
		historyWindow = Kit.CreateTabbedWindow({ name = "EldoUI_GuildHistory", title = L["Guild history"],
			width = 824, height = 480, options = { page = "module:Social" },
			store = function()
				local store = Store()
				if not store then return {} end
				if not IsTable(store.window) then store.window = {} end
				return store.window
			end,
			tabs = {
				{ key = "roster", title = E.Key("Roster"), create = BuildRoster, show = View(RefreshRoster), refresh = View(RefreshRoster) },
				{ key = "history", title = E.Key("History"), create = BuildHistory, show = View(RefreshLog), refresh = View(RefreshLog) },
			}, footer = function()
				if not Lease(live) then return L["Guild roster unavailable"] end
				if not live.loaded then return L["Waiting for the full guild roster"] end
				return live.guild.name or L["Guild"]
			end })
		self.guildHistoryWindow = historyWindow
	end
	local opened = historyWindow:Open(tab or "history")
	if opened and not historyWindow.guildHideHook then
		historyWindow.guildHideHook = true
		historyWindow.frame:HookScript("OnHide", function()
			if live and not live.login then CancelRead(live) end
			for _, key in ipairs({ "history", "roster" }) do
				local frame = historyWindow:GetTab(key).frame
				if frame and frame.viewJob then frame.viewJob:Cancel() end
				if frame and frame.filterTimer then frame.filterTimer:Cancel(); frame.filterTimer = nil end
			end
		end)
	end
	if live then QueueRoster(live) end
	return opened
end

RefreshHistoryButton = function()
	local frame = _G.CommunitiesFrame
	if InCombatLockdown() then return end
	if not Usable(frame) or not Improve() then if historyButton then historyButton:Hide() end; return end
	local id = GuildID()
	local selected = Read(frame.GetSelectedClubId, frame)
	if not id or id ~= selected or not frame:IsShown() then if historyButton then historyButton:Hide() end; return end
	local anchor = frame.GuildPreferredPlaySettingsTab or frame.GuildInfoTab
	if not Usable(anchor) then return end
	if not historyButton then
		historyButton = Kit.IconButton(frame, 30, "profile", function() M:OpenGuildHistory("roster") end, L["Guild history"])
	end
	historyButton:ClearAllPoints()
	historyButton:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 3, -20)
	historyButton:Show()
end

E:AddCommand("guildlog", "open the guild history", function() M:OpenGuildHistory("history") end)
E:RegisterNameFormatUser("GuildHistory", { title = "Guild history", order = 64, refresh = RefreshHistory })


---------------------------------------------------------------------------
-- Roster rows
---------------------------------------------------------------------------
local function MemberInfo(row)
	if type(row.GetMemberInfo) ~= "function" then return end
	local info = Read(row.GetMemberInfo, row)
	if IsTable(info) then return info end
end

-- A roster row: the name, rank, note and info columns are what players
-- named or wrote, so they take the name font; level and zone stay plain.
local function RowFonts(size, name, level, zone, rank, note, guildInfo)
	K.NameFonts(size, name, rank, note, guildInfo)
	K.Fonts(size, level, zone)
end

local tipHooked = setmetatable({}, { __mode = "k" })
local function GuildMemberTip(row)
	if not Lease(live) or not GameTooltip:IsOwned(row) then return end
	local frame = _G.CommunitiesFrame
	if not Usable(frame) or Read(frame.GetSelectedClubId, frame) ~= live.id then return end
	local info = MemberInfo(row)
	local guid = info and PlayerGUID(info.guid)
	if guid then MainLine(GameTooltip, guid, "tooltips"); GameTooltip:Show() end
end

local function StyleMemberRow(row)
	if not Usable(row) or not M.active then return end
	local db = M.db.guild
	local nameFrame = row.NameFrame
	local name = nameFrame and nameFrame.Name
	if Skin() then
		E:SkinRecord(ID, row, RowFonts, db.rowSize or 12, name, row.Level, row.Zone, row.Rank, row.Note, row.GuildInfo)
		if db.flatRows then E:SkinRecord(ID .. ":rows", row, E.SkinRow, E, row) end
	end
	if not (name and name.SetTextColor) then return end
	if not Improve() then
		rowColored[row] = nil
		return
	end
	if not tipHooked[row] and row.HookScript then
		tipHooked[row] = true
		row:HookScript("OnEnter", GuildMemberTip)
	end
	local info = MemberInfo(row)
	if not info then return end
	local token = K.ClassToken(nil, nil, Plain(info.classID))
	local r, g, b = K.ClassRGB(token)
	if not r then return end
	local offline = Enum and Enum.ClubMemberPresence and Plain(info.presence) == Enum.ClubMemberPresence.Offline
	if offline then
		if db.offlineClassColors then
			-- Dimmed class color: still readable as offline.
			name:SetTextColor(r * 0.6, g * 0.6, b * 0.6)
			rowColored[row] = true
		end
	elseif db.classColors then
		name:SetTextColor(r, g, b)
		rowColored[row] = true
	end
end

local function MemberList()
	local frame = _G.CommunitiesFrame
	local list = frame and frame.MemberList
	return Usable(list) and list or nil
end

local function RefreshRows()
	local list = MemberList()
	local box = list and list.ScrollBox
	if Usable(box) and box.ForEachFrame then
		pcall(box.ForEachFrame, box, function(row) Try(StyleMemberRow, row) end)
	end
end

local function QueueRows()
	E:Debounce("social:guild", 0, function()
		if M.active then RefreshRows() end
	end)
end

-- Rows Blizzard re-colored since we last touched them come back with
-- Blizzard's colors when Improve goes off: ask the list to redraw.
local function ResetRows()
	wipe(rowColored)
	local list = MemberList()
	if list and type(list.RefreshListDisplay) == "function" and not InCombatLockdown() then
		Try(list.RefreshListDisplay, list)
	end
end

---------------------------------------------------------------------------
-- Skin
---------------------------------------------------------------------------
local function SkinColumnHeaders(display)
	if not Usable(display) then return end
	E:SkinAlphaZero(display.Background, display.TopTileStreaks)
	E:StripTextures(display)
	local pool = display.columnHeaders
	if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
		for header in pool:EnumerateActive() do
			if Usable(header) then
				E:SkinAlphaZero(header.Left, header.Right, header.Middle)
				local text = header.Text or (header.GetFontString and header:GetFontString())
				if text and text.SetFont then
					E:SetFont(text, E.tokens.size.small)
					text:SetTextColor(unpack(E.media.text.secondary))
				end
			end
		end
	end
end

local function SkinCommunityList(list)
	if not Usable(list) then return end
	E:SkinAlphaZero(list.Bg, list.TopFiligree, list.BottomFiligree, list.FilligreeOverlay)
	E:SkinInset(list.InsetFrame)
	E:SkinScrollBar(list.ScrollBar)
	if Usable(list.ScrollBox) then
		E:HookScrollBoxRows(list.ScrollBox, function(row)
			E:SkinAlphaZero(row.Background)
			E:SkinRow(row)
			if row.Selection and row.Selection.SetColorTexture then
				E:AccentTexture(row.Selection, 0.25)
			end
			K.NameFonts(13, row.Name)
		end)
	end
end

local function SkinWindow()
	local frame = _G.CommunitiesFrame
	Try(E.SkinPanel, E, frame, { transparent = M.db.transparent })

	SkinCommunityList(frame.CommunitiesList)
	for _, key in ipairs({ "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab", "GuildPreferredPlaySettingsTab" }) do
		K.SkinSideTab(frame[key])
	end
	for _, key in ipairs({ "StreamDropdown", "GuildMemberListDropdown", "CommunityMemberListDropdown", "CommunitiesListDropdown" }) do
		E:SkinDropdown(frame[key])
	end
	E:SkinButton(frame.InviteButton)
	E:SkinButton(frame.GuildLogButton)
	local control = frame.CommunitiesControlFrame
	if Usable(control) then
		E:SkinButton(control.GuildControlButton)
		E:SkinButton(control.GuildRecruitmentButton)
		E:SkinButton(control.CommunitiesSettingsButton)
	end

	-- Roster.
	local list = frame.MemberList
	if Usable(list) then
		E:StripTextures(list)
		E:SkinInset(list.InsetFrame)
		E:SkinScrollBar(list.ScrollBar)
		E:SkinCheckBox(list.ShowOfflineButton)
		local display = list.ColumnDisplay
		if Usable(display) then
			SkinColumnHeaders(display)
			if type(display.LayoutColumns) == "function" then
				hooksecurefunc(display, "LayoutColumns", function(self)
					if Skin() then E:SkinRecord(ID, self, SkinColumnHeaders, self) end
				end)
			end
		end
	end

	-- Chat.
	local chat = frame.Chat
	if Usable(chat) then
		E:SkinInset(chat.InsetFrame)
		E:SkinScrollBar(chat.ScrollBar)
	end
	E:SkinEditBox(frame.ChatEditBox, { left = 4, right = 2 })

	-- Guild info, news and benefits.
	local details = frame.GuildDetailsFrame
	if Usable(details) then
		E:StripTextures(details)
		for _, key in ipairs({ "Info", "News" }) do
			local sub = details[key]
			if Usable(sub) then
				E:StripTextures(sub)
				if sub.TitleText and sub.TitleText.SetFont then
					E:SetFont(sub.TitleText, E.tokens.size.cardTitle)
					sub.TitleText:SetTextColor(1, 1, 1)
				end
				E:SkinScrollBar(sub.ScrollBar)
			end
		end
	end
	local benefits = frame.GuildBenefitsFrame
	if Usable(benefits) then
		E:StripTextures(benefits)
		for _, key in ipairs({ "Perks", "Rewards" }) do
			local sub = benefits[key]
			if Usable(sub) then
				E:StripTextures(sub)
				E:SkinScrollBar(sub.ScrollBar)
			end
		end
	end

	-- Member detail and the community dialogs.
	local detail = frame.GuildMemberDetailFrame
	if Usable(detail) then
		K.SkinDialog(detail, { close = true })
		E:SkinButton(detail.RemoveButton)
		E:SkinButton(detail.GroupInviteButton)
	end
	for _, key in ipairs({ "EditStreamDialog", "NotificationSettingsDialog", "RecruitmentDialog" }) do
		local dialog = frame[key]
		if Usable(dialog) then K.SkinDialog(dialog) end
	end

	-- Guild windows built on the translucent dialog template.
	for _, name in ipairs({ "CommunitiesGuildLogFrame", "CommunitiesGuildTextEditFrame", "CommunitiesGuildNewsFiltersFrame", "GuildControlUI" }) do
		local window = _G[name]
		if Usable(window) then
			K.SkinDialog(window, { strip = true, close = true })
			E:SkinCloseButton(window.CloseButton or _G[name .. "CloseButton"])
		end
	end
end

---------------------------------------------------------------------------
-- Part
---------------------------------------------------------------------------
local hooked = false
local function Hook()
	if hooked then return end
	hooked = true
	local list = MemberList()
	if list and Usable(list.ScrollBox) and ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
		-- After Blizzard's initializer has drawn the row.
		ScrollUtil.AddInitializedFrameCallback(list.ScrollBox, function(_, row) Try(StyleMemberRow, row) end, M, false)
	end
	for _, event in ipairs({ "CLUB_MEMBER_PRESENCE_UPDATED", "CLUB_MEMBER_UPDATED", "CLUB_MEMBERS_UPDATED", "GUILD_ROSTER_UPDATE" }) do
		E:RegisterEvent(event, function() if M.active then QueueRows() end end, rowColored)
	end
	local frame = _G.CommunitiesFrame
	frame:HookScript("OnShow", function() if M.active then QueueRows(); RefreshHistoryButton() end end)
	if type(frame.SelectClub) == "function" then hooksecurefunc(frame, "SelectClub", RefreshHistoryButton) end
end

M:AddPart({
	id = ID,
	addon = ADDON,
	install = { skin = true, improve = true },
	setup = function()
		if not Usable(_G.CommunitiesFrame) then error("EldoUI Social: CommunitiesFrame is missing") end
		Hook()
	end,
	apply = function(part)
		if Skin() then
			E:SkinRecord(ID, _G.CommunitiesFrame, function()
				if not part.skinned then
					part.skinned = true
					SkinWindow()
				end
				E:SetPanelTransparent(_G.CommunitiesFrame, M.db.transparent)
				local chat = _G.CommunitiesFrame.Chat
				local messages = chat and chat.MessageFrame
				if messages and messages.SetFont then
					E:SkinCapture(messages)
					local _, _, flags = messages:GetFont()
					-- What guild members write, in the name font of the theme font.
					pcall(E.SetMessageFont, E, messages, E.media.font, M.db.guild.chatSize or 13, flags or "")
				end
			end)
			-- Flat roster rows have a switch of their own.
			K.Want(part, "rows", nil, M.db.guild.flatRows, function() end)
		end
		if not Improve() and next(rowColored) then ResetRows() end
		M:ApplyWindow("guild")
		RefreshRows()
		RefreshHistoryButton()
	end,
	undo = function()
		if historyButton then historyButton:Hide() end
		ResetRows()
		M:RestoreWindow("guild")
	end,
})

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
M:AddOptions({ { type = "tab", label = "Guild" } })
M:AddOptions(M:SwitchOptions(ID, { { "guild", "Guild window" } }))
M:AddOptions({
	{ type = "header", label = "Roster" },
	{ type = "toggle", disabled = E:BlizzardNeeds(ID, "improve"), key = "guild.classColors", label = "Class colors in roster",
		desc = "Member names in their class color, also for community members Blizzard leaves uncolored." },
	{ type = "toggle", disabled = E:BlizzardNeeds(ID, "improve"), key = "guild.offlineClassColors", label = "Class colors for offline members",
		desc = "Offline members keep a dimmed class color instead of plain gray." },
	{ type = "toggle", disabled = E:BlizzardNeeds(ID, "skin"), key = "guild.flatRows", label = "Flat roster rows", desc = "Flat stripes and dividers behind the roster rows." },
	{ type = "range", disabled = E:BlizzardNeeds(ID, "skin"), key = "guild.rowSize", label = "Roster text size", min = 9, max = 16, step = 1, desc = "Size of names, levels, zones, ranks and notes." },
	{ type = "header", label = "Guild history" },
	{ type = "execute", label = "Open guild history", testSafe = true, disabled = E:BlizzardNeeds(ID, "improve"),
		desc = "Open the local record of guild member changes and the filterable roster.",
		func = function() M:OpenGuildHistory("history") end },
	{ type = "toggle", key = "guild.noteLinks", disabled = E:BlizzardNeeds(ID, "improve"), label = "Suggest main links from public notes",
		desc = "Reads only the public member note. Your own links take priority." },
	{ type = "input", key = "guild.noteTemplate", dependsOn = "guild.noteLinks", disabled = E:BlizzardNeeds(ID, "improve"),
		label = "Main name note template", desc = "Use one {main} placeholder. For example, alt of {main} matches a full note containing that main name." },
	{ type = "toggle", key = "guild.chatMain", disabled = E:BlizzardNeeds(ID, "improve"), label = "Main names in guild chat",
		desc = "Shows the linked main beside an alt's name in guild chat. Off by default." },
	{ type = "header", label = "Chat" },
	{ type = "range", disabled = E:BlizzardNeeds(ID, "skin"), key = "guild.chatSize", label = "Chat text size", min = 10, max = 20, step = 1,
		desc = "Size of the messages in the communities chat, in the EldoUI font." },
})
