-- EldoUI My Adventure: the EldoUIDB.journalSeen recorder and the "Report new content" export.
--
-- What the game shows you that the quest data does not know yet: a quest
-- WoW: Forever added or changed, a dungeon the instance list lacks, a zone
-- whose level range differs. It is written to EldoUIDB.journalSeen (the
-- shape is at the top of Modules/LootGuide/Quests.lua), the Journal's
-- quest pages read it at once (LG:JourneyChanged()), and "Report new
-- content" (LG:ShowJourneyReport) puts it in a copy box for a
-- journal-data issue. Nothing is sent from the game.
--
-- Only what a dialog or the map shows you is read: the quest window
-- (QUEST_DETAIL, QUEST_COMPLETE), the gossip list (GOSSIP_SHOW), your
-- quest log (QUEST_ACCEPTED), the hand-in (QUEST_TURNED_IN), the instance
-- and the map you are in. No combat data, nothing automated. A secret
-- value is skipped. Titles and names are kept on English clients only
-- (the data is English; another language would look like a change).
-- Settings: A.db.observe (on by default).
--
-- API (E.Adventure.Observe):
--   O:Quest(questID, fields)   note a quest's fields when they are new
--   O:Instance()               note the instance you are in, when new
--   O:Zone()                   note the map you are on, when new
--   O:Report()                 the copy box (LG:ShowJourneyReport)
--   O.NpcID(unit)              the npc id of a unit, or nil
local _, E = ...
local A = E.Adventure
local J = E.Journal
local R = A.Record
local LG = E.LootGuide

local type, tonumber, pairs = type, tonumber, pairs
local Text, Number, Call = R.Text, R.Number, R.Call

local O = {}
A.Observe = O

O.CHANGED_DELAY = 0.5
O.ENGLISH = { enUS = true, enGB = true }

function O.On()
	return A.db and A.db.observe ~= false and A:Running() and type(J.AddSeen) == "function" or false
end

local function English()
	local locale = Text(Call(GetLocale))
	return locale and O.ENGLISH[locale] or false
end
O.English = English

-- "Creature-0-1-2-3-<npcID>-<spawn>" -> npcID
function O.NpcID(unit)
	local guid = Text(Call(UnitGUID, unit or "npc"))
	if not guid then return nil end
	local kind, npc = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
	return tonumber(npc)
end

local function NpcName(unit)
	if not English() then return nil end
	return Text(Call(UnitName, unit or "npc"))
end

local function Where()
	local map, x, y = R.Position()
	if x and y then x, y = x / 100, y / 100 end
	return map, x, y
end

---------------------------------------------------------------------------
-- One coalesced change call for the quest pages
---------------------------------------------------------------------------
local function Changed()
	E:Debounce("adventure:changed", O.CHANGED_DELAY, function()
		if LG and LG.JourneyChanged then LG:JourneyChanged() end
	end)
end
O.Changed = Changed

local function Add(list, id, fields)
	local ok, changed = pcall(J.AddSeen, J, list, id, fields)
	if not ok then
		geterrorhandler()(changed)
		return false
	end
	if changed then Changed() end
	return changed and true or false
end

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------
-- A field the merged record already has with the same value adds nothing.
local function Differs(record, key, value)
	if key == "giver" then return not (record.giver and record.giver.npc == value) end
	if key == "ender" then return not (record.ender and record.ender.npc == value) end
	if key == "giverName" or key == "enderName" or key == "map" or key == "x" or key == "y" or key == "plevel"
		or key == "faction" then
		return false
	end
	if key == "xp" then return record.seenXP ~= value end
	if key == "money" then return record.seenMoney ~= value end
	return record[key] ~= value
end

-- fields: title, level, minLevel, giver, giverName, map, x, y, header,
-- plevel, faction, ender, enderName, xp, money (any may be missing).
function O:Quest(questID, fields)
	questID = Number(questID)
	if not (questID and questID > 0 and type(fields) == "table" and O.On()) then return false end
	local clean = {}
	for key, value in pairs(fields) do
		if not E:IsSecret(value) and (type(value) == "number" or (type(value) == "string" and value ~= "")) then clean[key] = value end
	end
	if not English() then clean.title, clean.giverName, clean.enderName, clean.header = nil, nil, nil, nil end
	local record = LG and LG.JourneyQuest and LG:JourneyQuest(questID)
	-- A quest the data knows and you have not noted: only a difference counts.
	if record and not record.seen then
		local new = false
		for key, value in pairs(clean) do
			if Differs(record, key, value) then new = true break end
		end
		if not new then return false end
	end
	clean.plevel = clean.plevel or R.Level()
	clean.faction = clean.faction or Text(Call(UnitFactionGroup, "player"))
	return Add("quests", questID, clean)
end

local function DialogQuest()
	return Number(Call(GetQuestID))
end

function O.OnDetail()
	local questID = DialogQuest()
	if not questID then return end
	local map, x, y = Where()
	O:Quest(questID, {
		title = Text(Call(GetTitleText)),
		level = C_QuestLog and Number(Call(C_QuestLog.GetQuestDifficultyLevel, questID)) or nil,
		giver = O.NpcID("npc"), giverName = NpcName("npc"), map = map, x = x, y = y,
	})
end

function O.OnComplete()
	local questID = DialogQuest()
	if not questID then return end
	O:Quest(questID, {
		title = Text(Call(GetTitleText)),
		ender = O.NpcID("npc"), enderName = NpcName("npc"),
		xp = Number(Call(GetRewardXP)), money = Number(Call(GetRewardMoney)),
	})
end

-- The header the quest sits under in your log (its zone or kind).
local function LogHeader(questID)
	if not (C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetInfo) then return nil end
	local index = Number(Call(C_QuestLog.GetLogIndexForQuestID, questID))
	if not index then return nil end
	local info = Call(C_QuestLog.GetInfo, index)
	local level = type(info) == "table" and Number(info.level) or nil
	for i = index - 1, 1, -1 do
		local row = Call(C_QuestLog.GetInfo, i)
		if type(row) == "table" and not E:IsSecret(row.isHeader) and row.isHeader then return Text(row.title), level end
	end
	return nil, level
end

function O.OnAccepted(a1, a2)
	local questID = Number(a2) or Number(a1)
	if not questID then return end
	local header, level = LogHeader(questID)
	local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and Text(Call(C_QuestLog.GetTitleForQuestID, questID)) or nil
	O:Quest(questID, { header = header, level = level, title = title })
end

function O.OnTurnedIn(questID, xp, money)
	questID = Number(questID)
	if not questID then return end
	local fields = { xp = Number(xp), money = Number(money) }
	if fields.xp or fields.money then O:Quest(questID, fields) end
end

function O.OnGossip()
	if not (C_GossipInfo and C_GossipInfo.GetAvailableQuests) then return end
	local list = Call(C_GossipInfo.GetAvailableQuests)
	if type(list) ~= "table" then return end
	local giver, giverName = O.NpcID("npc"), NpcName("npc")
	local map, x, y = Where()
	for _, info in ipairs(list) do
		if type(info) == "table" then
			O:Quest(info.questID, {
				title = Text(info.title), level = Number(info.questLevel), giver = giver, giverName = giverName,
				map = map, x = x, y = y,
			})
		end
	end
end

---------------------------------------------------------------------------
-- Instances and zones
---------------------------------------------------------------------------
function O:Instance()
	if not O.On() then return false end
	local name, kind, _, _, maxPlayers, _, _, instanceID = Call(GetInstanceInfo)
	if E:IsSecret(kind) or (kind ~= "party" and kind ~= "raid") then return false end
	instanceID = Number(instanceID)
	if not instanceID then return false end
	local known = LG and LG.InstanceForPlayer and LG:InstanceForPlayer(instanceID)
	if known then return false end
	return Add("instances", instanceID, { name = English() and Text(name) or nil, size = Number(maxPlayers) })
end

function O:Zone()
	if not O.On() or not C_Map then return false end
	local map = Number(Call(C_Map.GetBestMapForUnit, "player"))
	if not map then return false end
	local info = Call(C_Map.GetMapInfo, map)
	local mapType = type(info) == "table" and Number(info.mapType) or nil
	-- Zones only (3); continents, dungeons and micro maps are not zones.
	if mapType and mapType ~= 3 then return false end
	local min, max = Call(C_Map.GetMapLevels, map)
	min, max = Number(min), Number(max)
	if not (min and max and min > 0 and max > 0) then return false end
	local data = E.zoneData and E.zoneData[map]
	if type(data) == "table" and data.min == min and data.max == max then return false end
	local name = English() and type(info) == "table" and Text(info.name) or nil
	return Add("zones", map, { name = name, min = min, max = max })
end

function O:Report()
	if LG and LG.ShowJourneyReport then return LG:ShowJourneyReport() end
	return false
end

---------------------------------------------------------------------------
-- Part
---------------------------------------------------------------------------
local function Place()
	O:Instance()
	O:Zone()
end

local events = R.Events({
	QUEST_DETAIL = function() O.OnDetail() end,
	QUEST_ACCEPTED = function(a1, a2) O.OnAccepted(a1, a2) end,
	QUEST_COMPLETE = function() O.OnComplete() end,
	QUEST_TURNED_IN = function(questID, xp, money) O.OnTurnedIn(questID, xp, money) end,
	GOSSIP_SHOW = function() O.OnGossip() end,
	PLAYER_ENTERING_WORLD = function() C_Timer.After(2, Place) end,
	ZONE_CHANGED_NEW_AREA = function() C_Timer.After(1, Place) end,
})
O.events = events

-- Option rows on "Data" (Options.lua places them).
A.ObserveOptions = {
	{ type = "header", label = "New Forever content" },
	{ type = "toggle", key = "observe", label = "Remember new Forever content",
		desc = "Notes the quests, dungeons and zone level ranges the game shows you that the quest data does not know yet, so the quest pages can show them. Only what dialogs and the map show is read." },
	{ type = "execute", label = "Report new content",
		desc = "Shows what was noted as one block to copy into a journal-data issue. Nothing is sent from the game.",
		func = function() O:Report() end },
}

A:AddPart("observe", {
	order = 40,
	init = function()
		if A.AddOptionRows then A:AddOptionRows("data", A.ObserveOptions) end
	end,
	start = function()
		events.Start()
		C_Timer.After(2, Place)
	end,
	stop = function()
		events.Stop()
	end,
})
