-- EldoUI Party Quests: the quests you share with your party and
-- how far each of you is.
--
--   * Cards: "Shared" (you and at least one member are on it), "Only mine"
--     and "Only theirs". Who is on a quest of your log comes from
--     C_QuestLog.IsUnitOnQuest; what the others carry and how far they are
--     comes from "Sync with group".
--   * The module and Sync with group are on by default (design decision):
--     your quest IDs and objective counts go to
--     the group as an EldoUI addon message (prefix EUI_PQ), never a chat
--     line, when your quest log changes or the group does. Members who run
--     EldoUI with sync on see your progress and you see theirs. Never in
--     battlegrounds or arenas, and not in raids while hideInRaid is on.
--     While it is off nothing is sent and nothing is read. The Comm queue
--     waits while the game holds addon messages back.
--   * Share: your quest to the party through the game's own share, one
--     click. Ask: one message to a member who has a quest you lack; they see
--     "Mira asks you to share ..." with a Share button. Nothing is shared,
--     accepted or answered by itself.
--   * Popups (optional): when a member with sync finishes an objective or
--     the whole of a quest you share.
--   * Summary (optional): when the group ends, how long you grouped and the
--     quests you turned in together.
--
--   PQ:Cards()        { shared = { card }, mine = { card }, theirs = { card } }
--                     card: { id, title, level, members = { { name, unit,
--                     have, done, total, complete, synced } }, mine = { done,
--                     total, complete } | nil, pushable }
--   PQ:Share(questID) the game's share for one quest (a click)
--   PQ:Ask(questID, name) one ask message (a click)
--   PQ:SendState(force) your state to the group (sync on only)
--
-- Only your own quest log and what members send: nothing comes from combat,
-- nothing is guessed.
local _, E = ...
local L = E.L

local PQ = E:NewModule("PartyQuests", {
	title = "Party Quests",
	desc = "The quests you share with your party, each member's progress, and one-click Share and Ask buttons. Shares your quest progress with group members who run EldoUI, as addon messages only, never in chat.",
	category = "Group",
	conflicts = { "QuestAsOne" },
	frames = { "EldoUI_PartyQuests" },
	movers = { "EldoUI_PartyQuests" },
	savedKeys = { "profile.modules.PartyQuests" },
	optionsPage = "module:PartyQuests",
	presets = { "Bronze", "Cards", "Compact", "Minimal", "Tracker" },
	reload = false,
	defaults = {
		enabled = true,
		style = "Cards",
		panel = true,          -- the panel while you are in a group
		sync = true,           -- send and read quest progress (addon messages only)
		popups = true,         -- member finished an objective of a shared quest
		summary = true,        -- the card when the group ends
		showShared = true,
		showMine = true,
		showTheirs = true,
		hideInRaid = true,
		look = "cards",        -- cards, list, tracker, bronze, minimal
		fontSize = 12,
		bars = true,           -- progress bars on cards
		visibility = E:VisibilityDefaults(), -- the shared visibility rules (the panel)
	},
})
E.PartyQuests = PQ
E:RegisterVisibilityFacet("EldoUI_PartyQuests", "rules", { module = "PartyQuests", setting = "visibility" })
-- The built-in group list (Core/Config.lua) names this module too, so it
-- keeps its group after the module split.
if E.defaultModuleCategory then E.defaultModuleCategory.PartyQuests = PQ.category end

local PREFIX = "EUI_PQ"
local SEND_DELAY = 1.5     -- seconds a burst of quest log changes takes
local ASK_REPEAT = 30      -- the same ask from the same member shows once in this
local MAX_QUESTS = 35      -- quests in one state message
local MIN_SUMMARY = 120    -- seconds grouped before a summary is worth a card
local PARTY = { "party1", "party2", "party3", "party4" }

local Secret = E.Secret

-- fn(...), or nothing when it fails or any answer is secret.
local Read = E.PlainCallAll
PQ.Read = Read

function PQ:Now()
	return GetTime()
end

---------------------------------------------------------------------------
-- Group
---------------------------------------------------------------------------
local function InPvP()
	local _, kind = Read(IsInInstance)
	return kind == "pvp" or kind == "arena"
end

-- The panel and sync work in a party, and in a raid unless hidden there.
function PQ:InScope()
	if not Read(IsInGroup) then return false end
	if Read(IsInRaid) and self.db.hideInRaid then return false end
	return true
end

-- "Name" on your realm, "Name-Realm" from another: what Ambiguate(sender,
-- "none") gives for an addon message from that member.
local function UnitKey(unit)
	local name, realm = Read(UnitName, unit)
	if type(name) ~= "string" or name == "" then return nil end
	local own = Read(GetNormalizedRealmName)
	if type(realm) == "string" and realm ~= "" and realm:gsub("[%s%-]", "") ~= own then return name .. "-" .. realm, name end
	return name, name
end
PQ.UnitKey = UnitKey

local function SenderKey(sender)
	if type(sender) ~= "string" or Secret(sender) then return nil end
	local key = Read(Ambiguate, sender, "none")
	if type(key) ~= "string" or key == "" then key = sender end
	return key
end
PQ.SenderKey = SenderKey

-- { { unit, key, name }, ... } of the party members you can see.
function PQ:Members()
	local list = {}
	for _, unit in ipairs(PARTY) do
		if Read(UnitExists, unit) then
			local key, name = UnitKey(unit)
			if key then list[#list + 1] = { unit = unit, key = key, name = name } end
		end
	end
	return list
end

---------------------------------------------------------------------------
-- Your quest log
---------------------------------------------------------------------------
-- { [questID] = { id, title, level, done, total, complete, counts = {
-- { have, need } } } } of the quests in your log (no headers, no hidden).
function PQ:MyQuests()
	local list = {}
	local log = C_QuestLog
	if not log then return list end
	local count = Read(log.GetNumQuestLogEntries) or 0
	for index = 1, count do
		local info = Read(log.GetInfo, index)
		if type(info) == "table" and not info.isHeader and not info.isHidden and type(info.questID) == "number" and info.questID > 0 then
			local id = info.questID
			local entry = { id = id, title = info.title, level = info.level, counts = {}, done = 0, total = 0 }
			local objectives = Read(log.GetQuestObjectives, id)
			if type(objectives) == "table" then
				for _, objective in ipairs(objectives) do
					local need = tonumber(objective.numRequired) or 0
					local have = tonumber(objective.numFulfilled) or 0
					if need <= 0 then need, have = 1, objective.finished and 1 or 0 end
					have = math.min(have, need)
					entry.counts[#entry.counts + 1] = { have, need }
					entry.done, entry.total = entry.done + have, entry.total + need
				end
			end
			local complete = Read(log.IsComplete, id)
			entry.complete = complete == true or (entry.total > 0 and entry.done >= entry.total)
			list[id] = entry
		end
	end
	return list
end

-- Cards and outbound state share one read of the player's log.
local ownQuests
local ownRevision, builtRevision = 0, nil

local function InvalidateOwnQuests()
	ownRevision = ownRevision + 1
end

local function OwnQuests()
	local revision = ownRevision
	if builtRevision ~= revision then
		local quests = PQ:MyQuests()
		if ownRevision ~= revision then return nil, revision end
		ownQuests, builtRevision = quests, revision
	end
	return ownQuests, revision
end

---------------------------------------------------------------------------
-- Sync: the state message
--   "S" then one entry per quest, ";" between: "<id>,<have>/<need>.<have>/<need>,<1 when complete>"
---------------------------------------------------------------------------
function PQ.EncodeState(quests)
	local ids = {}
	for id in pairs(quests) do ids[#ids + 1] = id end
	table.sort(ids)
	local parts = {}
	for index = 1, math.min(#ids, MAX_QUESTS) do
		local entry = quests[ids[index]]
		local counts = {}
		for _, pair in ipairs(entry.counts) do counts[#counts + 1] = ("%d/%d"):format(pair[1], pair[2]) end
		parts[#parts + 1] = ("%d,%s,%d"):format(entry.id, table.concat(counts, "."), entry.complete and 1 or 0)
	end
	return "S" .. table.concat(parts, ";")
end

function PQ.DecodeState(payload)
	if type(payload) ~= "string" or payload:sub(1, 1) ~= "S" then return nil end
	local quests, count = {}, 0
	for entry in payload:sub(2):gmatch("[^;]+") do
		local id, countText, complete = entry:match("^(%d+),([%d/%.]*),([01])$")
		id = tonumber(id)
		if id and count < MAX_QUESTS then
			count = count + 1
			local quest = { id = id, counts = {}, done = 0, total = 0, complete = complete == "1" }
			for have, need in countText:gmatch("(%d+)/(%d+)") do
				have, need = tonumber(have), tonumber(need)
				if need > 0 and #quest.counts < 20 then
					have = math.min(have, need)
					quest.counts[#quest.counts + 1] = { have, need }
					quest.done, quest.total = quest.done + have, quest.total + need
				end
			end
			quests[id] = quest
		end
	end
	return quests
end

local synced = {}      -- member key -> { quests = { [id] = quest }, at }
PQ.synced = synced
local lastSent
local sendPending

function PQ:CanSend()
	return self.active and self.db.sync and self:InScope() and not InPvP()
end

function PQ:SendState(force)
	if not self:CanSend() then return false end
	local quests, revision = OwnQuests()
	if not quests or not self:CanSend() or revision ~= ownRevision then return false end
	local payload = PQ.EncodeState(quests)
	if payload == lastSent and not force then return false end
	local ok = E:SendComm(PREFIX, payload, "GROUP")
	if ok and ownRevision == revision then lastSent = payload end
	return ok and true or false
end

-- A quest log or group change: send once the burst is over.
function PQ:QueueSend()
	if sendPending or not self:CanSend() then return end
	local pending = {}
	sendPending = pending
	C_Timer.After(SEND_DELAY, function()
		if sendPending ~= pending then return end
		sendPending = nil
		PQ:SendState()
	end)
end

function PQ:ForgetSync()
	for key in pairs(synced) do synced[key] = nil end
	lastSent = nil
end

-- The objectives a member finished since their last message, for popups.
local function Finished(old, new)
	local out = {}
	if not old then return out end
	for id, quest in pairs(new) do
		local before = old[id]
		if before then
			if quest.complete and not before.complete then
				out[#out + 1] = { id = id, whole = true }
			else
				for index, pair in ipairs(quest.counts) do
					local was = before.counts[index]
					if was and pair[1] >= pair[2] and was[1] < was[2] then
						out[#out + 1] = { id = id, index = index, of = #quest.counts }
					end
				end
			end
		end
	end
	return out
end

function PQ:OnState(payload, sender)
	if not (self.active and self.db.sync and self:InScope()) or InPvP() then return end
	local key = SenderKey(sender)
	if not key then return end
	local member
	for _, entry in ipairs(self:Members()) do
		if entry.key == key then member = entry end
	end
	if not member then return end
	local quests = PQ.DecodeState(payload)
	if not quests then return end
	local before = synced[key]
	synced[key] = { quests = quests, at = self:Now() }
	if self.db.popups and before then
		for _, done in ipairs(Finished(before.quests, quests)) do
			local log = C_QuestLog
			local index = log and Read(log.GetLogIndexForQuestID, done.id)
			local info = index and Read(log.GetInfo, index)
			if type(info) == "table" and not Secret(info.questID) and info.questID == done.id
				and not info.isHeader and not info.isHidden then
				self:Popup(member.name, { id = done.id, title = info.title }, done)
			end
		end
	end
	self:Changed()
end

function PQ:Popup(name, quest, done)
	local title = quest.title or self.QuestTitle(quest.id)
	local text
	if done.whole then
		text = L["%s has finished %s."]:format(name, title)
	else
		text = L["%s finished objective %d of %d in %s."]:format(name, done.index, done.of, title)
	end
	PQ:PushAlert({ title = L["Party Quests"], text = text, icon = "Interface\\GossipFrame\\ActiveQuestIcon",
		key = "partyquests:" .. name .. ":" .. quest.id, duration = 6 })
end

---------------------------------------------------------------------------
-- Ask and Share
--   "A<questID>" whispered to the member who has the quest
---------------------------------------------------------------------------
local asksSeen = {}    -- "sender:quest" -> time shown

function PQ.QuestTitle(questID)
	local title = C_QuestLog and Read(C_QuestLog.GetTitleForQuestID, questID)
	if type(title) == "string" and title ~= "" then return title end
	local LG = E.LootGuide
	local record = LG and LG.JourneyQuest and LG:JourneyQuest(questID)
	if record and type(record.title) == "string" then return record.title end
	return L["Quest %d"]:format(questID)
end

function PQ:CanShare(questID)
	if not (self.active and Read(IsInGroup) and C_QuestLog) then return false end
	if not Read(C_QuestLog.GetLogIndexForQuestID, questID) then return false end
	return Read(C_QuestLog.IsPushableQuest, questID) == true
end

-- The game's own share of one quest. A click only.
function PQ:Share(questID)
	questID = tonumber(questID)
	if not (questID and self:CanShare(questID)) then return false end
	local before = Read(C_QuestLog.GetSelectedQuest)
	Read(C_QuestLog.SetSelectedQuest, questID)
	local ok = pcall(QuestLogPushQuest)
	if before and before ~= questID then Read(C_QuestLog.SetSelectedQuest, before) end
	return ok
end

-- One ask message to one member. A click only.
function PQ:Ask(questID, key)
	questID = tonumber(questID)
	if not (self.active and questID and type(key) == "string" and self:InScope()) or InPvP() then return false end
	local ok = E:SendComm(PREFIX, "A" .. questID, "WHISPER", key)
	return ok and true or false
end

function PQ:OnAsk(payload, sender)
	if not (self.active and self:InScope()) then return end
	local questID = tonumber(payload:match("^A(%d+)$"))
	local key = SenderKey(sender)
	if not (questID and key) then return end
	local member
	for _, entry in ipairs(self:Members()) do
		if entry.key == key then member = entry end
	end
	if not member then return end
	if not Read(C_QuestLog.GetLogIndexForQuestID, questID) then return end
	local seenKey = key .. ":" .. questID
	local now = self:Now()
	if asksSeen[seenKey] and now - asksSeen[seenKey] < ASK_REPEAT then return end
	asksSeen[seenKey] = now
	local title = self.QuestTitle(questID)
	PQ:PushAlert({
		title = L["Party Quests"],
		text = L["%s asks you to share %s."]:format(member.name, title),
		icon = "Interface\\GossipFrame\\AvailableQuestIcon",
		key = "partyquests:ask:" .. seenKey,
		actions = {
			{ label = L["Share"], func = function() PQ:Share(questID) end, tip = L["Shares the quest with your party through the game's own share."] },
			{ label = L["Not now"] },
		},
	})
	self.lastAsk = { from = member.name, quest = questID }
end

local function OnComm(payload, sender)
	if Secret(payload) or type(payload) ~= "string" then return end
	local kind = payload:sub(1, 1)
	if kind == "S" then
		PQ:OnState(payload, sender)
	elseif kind == "A" then
		PQ:OnAsk(payload, sender)
	end
end
PQ.OnComm = OnComm

---------------------------------------------------------------------------
-- Cards
---------------------------------------------------------------------------
local function ByTitle(a, b)
	if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
	return (a.title or "") < (b.title or "")
end

local function MemberQuest(member, questID)
	local data = synced[member.key] and synced[member.key].quests[questID]
	return data, data ~= nil or (C_QuestLog and Read(C_QuestLog.IsUnitOnQuest, member.unit, questID) == true)
end

function PQ:Cards(mine)
	local out = { shared = {}, mine = {}, theirs = {} }
	if not self.active then return out end
	mine = mine or self:MyQuests()
	local members = self:Members()
	local theirs = {}
	for id, quest in pairs(mine) do
		local card = { id = id, title = quest.title or self.QuestTitle(id), level = quest.level, members = {},
			mine = { done = quest.done, total = quest.total, complete = quest.complete } }
		for _, member in ipairs(members) do
			local data, on = MemberQuest(member, id)
			if on then
				card.members[#card.members + 1] = { name = member.name, key = member.key, unit = member.unit, synced = data ~= nil,
					done = data and data.done, total = data and data.total, complete = data and data.complete }
			end
		end
		card.pushable = self:CanShare(id)
		if #card.members > 0 then out.shared[#out.shared + 1] = card else out.mine[#out.mine + 1] = card end
	end
	for _, member in ipairs(members) do
		local data = synced[member.key]
		if data then
			for id, quest in pairs(data.quests) do
				if not mine[id] then
					local card = theirs[id]
					if not card then
						card = { id = id, title = self.QuestTitle(id), members = {} }
						local LG = E.LootGuide
						local record = LG and LG.JourneyQuest and LG:JourneyQuest(id)
						card.level = record and tonumber(record.level)
						theirs[id] = card
						out.theirs[#out.theirs + 1] = card
					end
					card.members[#card.members + 1] = { name = member.name, key = member.key, unit = member.unit, synced = true,
						done = quest.done, total = quest.total, complete = quest.complete }
				end
			end
		end
	end
	for _, list in pairs(out) do
		table.sort(list, ByTitle)
		for _, card in ipairs(list) do
			table.sort(card.members, function(a, b) return a.name < b.name end)
		end
	end
	return out
end

---------------------------------------------------------------------------
-- The group session and its summary
---------------------------------------------------------------------------
local session -- { start, together = { [questID] = title } }

function PQ:Session()
	return session
end

function PQ:OnTurnedIn(questID)
	if not (session and self:InScope()) or Secret(questID) or type(questID) ~= "number" then return end
	for _, card in ipairs(self.cache and self.cache.shared or {}) do
		if card.id == questID then
			session.together[questID] = card.title
			return
		end
	end
	-- Without projected cards, a turn-in can still be shared. The game
	-- may already have removed the quest from our own log at this point.
	for _, member in ipairs(self:Members()) do
		local _, on = MemberQuest(member, questID)
		if on then
			local quest = ownQuests and ownQuests[questID]
			session.together[questID] = quest and quest.title or self.QuestTitle(questID)
			return
		end
	end
end

function PQ:StartSession()
	if session then return end
	session = { start = self:Now(), together = {} }
end

function PQ:EndSession()
	local current = session
	session = nil
	self:ForgetSync()
	if not (current and self.active and self.db.summary) then return end
	local seconds = self:Now() - current.start
	if seconds < MIN_SUMMARY then return end
	local titles = {}
	for _, title in pairs(current.together) do titles[#titles + 1] = title end
	table.sort(titles)
	local minutes = math.max(1, math.floor(seconds / 60 + 0.5))
	local text = L["Grouped for %d min."]:format(minutes)
	if #titles > 0 then
		text = text .. " " .. L["Quests done together: %d (%s)."]:format(#titles, table.concat(titles, ", "))
	else
		text = text .. " " .. L["No quests done together."]
	end
	self.lastSummary = { minutes = minutes, titles = titles, text = text }
	PQ:PushAlert({ title = L["Group summary"], text = text, icon = "Interface\\GossipFrame\\ActiveQuestIcon",
		key = "partyquests:summary", duration = 15, closable = true })
end

local changePending
local wasInScope = false

local function ResetWork()
	changePending, sendPending = nil, nil
	ownQuests = nil
	InvalidateOwnQuests()
end

function PQ:OnRoster()
	if Read(IsInGroup) then
		self:StartSession()
		-- Drop members who left; send again so a new member gets your state.
		local here = {}
		for _, member in ipairs(self:Members()) do here[member.key] = true end
		for key in pairs(synced) do
			if not here[key] then synced[key] = nil end
		end
		lastSent = nil
	elseif session then
		self:EndSession()
	end
	if self:InScope() and wasInScope then
		self:Changed()
	else
		self:Refresh()
	end
	self:QueueSend()
end

---------------------------------------------------------------------------
-- Changes
---------------------------------------------------------------------------
function PQ:Changed()
	if changePending or not (self.active and self:InScope() and self.db.panel) then return end
	local pending = {}
	changePending = pending
	C_Timer.After(0.2, function()
		if changePending ~= pending then return end
		changePending = nil
		if PQ.active then PQ:Refresh() end
	end)
end

function PQ:Refresh()
	local inScope = self.active and self:InScope()
	if not inScope or not wasInScope then ResetWork() end
	wasInScope = inScope and true or false
	if inScope and self.db.panel then
		local quests, revision = OwnQuests()
		if not quests or not (self.active and self.db.panel and self:InScope()) or revision ~= ownRevision then return end
		local cards = self:Cards(quests)
		if not (self.active and self.db.panel and self:InScope()) or revision ~= ownRevision then return end
		self.cache = cards
	else
		self.cache = nil
	end
	if self.UpdatePanel then self:UpdatePanel() end
end

function PQ:OnQuestProgress()
	InvalidateOwnQuests()
	self:QueueSend()
	self:Changed()
end

function PQ:OnEnable()
	if not self.commOn then
		self.commOn = E:RegisterComm(PREFIX, OnComm, { trusted = "group" }) and true or false
	end
	self:RegisterEvent("QUEST_LOG_UPDATE", function()
		if not PQ:InScope() or not (PQ.db.panel or PQ:CanSend()) then InvalidateOwnQuests() end
	end)
	self:RegisterUnitEvent("UNIT_QUEST_LOG_CHANGED", "player", function() PQ:OnQuestProgress() end)
	self:RegisterEvent("QUEST_ACCEPTED", function() PQ:OnQuestProgress() end)
	self:RegisterEvent("QUEST_REMOVED", function() PQ:OnQuestProgress() end)
	self:RegisterEvent("QUEST_TURNED_IN", function(_, _, questID)
		PQ:OnTurnedIn(questID)
		PQ:OnQuestProgress()
	end)
	self:RegisterEvent("GROUP_ROSTER_UPDATE", function() PQ:OnRoster() end)
	self:RegisterEvent("GROUP_LEFT", function() PQ:OnRoster() end)
	if self.CreatePanel then self:CreatePanel() end
	if self.ApplyVisibility then self:ApplyVisibility() end
	if Read(IsInGroup) then self:StartSession() end
	self:Refresh()
	self:QueueSend()
end

function PQ:OnDisable()
	if self.frame then E:DetachVisibility(self.frame) end
	self.visibilityBlock = nil
	self:UnregisterUnitEvent("UNIT_QUEST_LOG_CHANGED", "player")
	for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "GROUP_ROSTER_UPDATE", "GROUP_LEFT" }) do
		self:UnregisterEvent(event)
	end
	if self.commOn then
		E:UnregisterComm(PREFIX)
		self.commOn = false
	end
	session = nil
	wasInScope, self.cache = false, nil
	ResetWork()
	self:ForgetSync()
	if self.UpdatePanel then self:UpdatePanel() end
end

-- A profile or an option changed (Config calls this after every change).
function PQ:OnProfileChanged()
	if not self.db.sync then
		sendPending = nil
		self:ForgetSync()
	end
	if self.ApplyLook then self:ApplyLook() end
	if self.active then
		if self.ApplyVisibility then self:ApplyVisibility() end
		self:Refresh()
		self:QueueSend()
	end
end
