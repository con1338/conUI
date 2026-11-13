-- EldoUI My Adventure: the smaller moments: spells and recipes,
-- professions and skills, reputation, bosses, finds, mounts and pets,
-- talent re-specs, flight paths, titles, the hearthstone, the guild,
-- cinematics, wished items and where each quest came from.
--
-- Rows it writes (kinds and fields in Kinds.lua):
--   spell, recipe, profession, skill (rank, max, mastered), rep (standing
--   1-8), boss (first kill) / raidboss / bossagain, loot (uncommon and up,
--   never crafting materials), wish (an item on your wishlist), mount, pet,
--   respec, flight, title, hearth, guild, cinematic.
-- Tables it keeps: bosses[encounterID] = { name, first, kills, instance },
-- runExtras[runID].bosses = { encounterID, ... }, quests (hand-ins, cap
-- 2000), questStart[questID] = { t, giver, z, s, l, map, x, y, objective,
-- with }, taxi = { [nodeID] = true }, titles = { [id] = true },
-- abandoned = { { t, id, title, z, s, l, started, giver } } (cap 200).
--
-- Rules:
--   * bosses only from ENCOUNTER_END (success) and BOSS_KILL by encounter
--     id, one count per kill; no unit, model or nameplate probes;
--   * a find hangs on a boss only through ENCOUNTER_LOOT_RECEIVED's
--     encounter id, never a time guess;
--   * reputation from FACTION_STANDING_CHANGED and C_Reputation, not chat;
--   * spells from LEARNED_SPELL_IN_SKILL_LINE; recipe, spell and new
--     skill system lines are read only when not secret (chat lockdown);
--   * skills from GetProfessions and C_SkillInfo (the old skill list is
--     not on Forever); re-specs from the talent tree (TRAIT_CONFIG_UPDATED);
--   * flight paths from the taxi map's known nodes (C_TaxiMap), with the
--     system line as a fallback;
--   * quest objectives from the quest window or C_QuestLog's objectives;
--     the quest log selection is never changed.
--
-- API (E.Journal):
--   J:OpenQuests()      the quests in your log now, with what the journal
--                       saw when you took them { questID, title, level,
--                       have, need, ready, start }
--   J:Abandoned([charKey])  quests that left the log without a hand-in,
--                       newest first (callback "QuestAbandoned"(id, entry))
--
-- Portions adapted from Forever Journal by Ugge Zen, MIT License (see
-- THIRD_PARTY_NOTICES.md): the event kinds and when each is written, the
-- login replay pause, a spell turning into a recipe, the profession caps
-- and the Mastered keepsake, first boss kills as keepsakes with later
-- kills counted, the loot quality and armor reading, materials skipped,
-- quest givers and takers joined to the hand-in, and the open quest list.
--
-- MIT License
--
-- Copyright (c) 2026 Ugge Zen
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
local _, E = ...
local A = E.Adventure
local J = E.Journal
local S = A.Store
local R = A.Record

local Call, Text, Number = R.Call, R.Text, R.Number
local floor = math.floor

local CH = {}
A.Chronicle = CH

-- The game replays spells and skills in the first seconds after a login.
CH.REPLAY_SECONDS = 10
CH.SPELL_WAIT = 1.5         -- a spell row waits this long for its recipe line
CH.LOOT_WAIT = 1            -- a find waits this long for ENCOUNTER_LOOT_RECEIVED
CH.BOSS_SAME = 60           -- ENCOUNTER_END and BOSS_KILL of one kill
CH.FLIGHT_SAME = 30         -- the system line and the taxi map of one discovery
CH.MATERIAL = { [3] = true, [5] = true, [7] = true }   -- Gem, Reagent, Tradegoods
CH.PRO_CAPS = { [75] = true, [150] = true, [225] = true }
CH.MASTER = 300

local ready = false
local function Ready() return ready end
CH.Ready = Ready

-- A game format string ("You have learned a new spell: %s.") as a pattern.
local function Pattern(name)
	local fmt = rawget(_G, name)
	if type(fmt) ~= "string" or E:IsSecret(fmt) then return nil end
	fmt = fmt:gsub("%%%d%$", "%%"):gsub("%%s", "\1"):gsub("%%d", "\2")
	fmt = fmt:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("\1", "(.+)"):gsub("\2", "(%%d+)")
	return "^" .. fmt .. "$"
end
CH.Pattern = Pattern

-- "|cff..|Hspell:..|h[Name]|h|r" -> "Name".
local function Unlink(text)
	if type(text) ~= "string" then return nil end
	return (text:gsub("|c%x+|H.-|h%[?(.-)%]?|h|r", "%1"):gsub("|H.-|h%[?(.-)%]?|h", "%1"))
end

---------------------------------------------------------------------------
-- Spells and recipes
---------------------------------------------------------------------------
local pendingSpells = {}   -- name -> true while a spell row waits

local function SpellInfo(spellID)
	local name = C_Spell and Text(Call(C_Spell.GetSpellName, spellID))
	local rank = C_Spell and Text(Call(C_Spell.GetSpellSubtext, spellID))
	return name, rank
end

function CH.LearnSpell(spellID, name, rank)
	if not ready then return end
	if spellID and not name then name, rank = SpellInfo(spellID) end
	if not name or pendingSpells[name] then return end
	pendingSpells[name] = { spell = spellID, name = name, rank = rank }
	C_Timer.After(CH.SPELL_WAIT, function()
		local item = pendingSpells[name]
		pendingSpells[name] = nil
		if item and not item.recipe then J:Log("spell", { spell = item.spell, name = item.name, rank = item.rank }) end
	end)
end

function CH.LearnRecipe(name)
	if not (ready and name) then return end
	local item = pendingSpells[name]
	if item then item.recipe = true end
	J:Log("recipe", { recipe = item and item.spell or nil, name = name })
end

---------------------------------------------------------------------------
-- Professions and skills: a new profession, a profession at a trainer cap,
-- a skill mastered at 300, a new weapon skill.
---------------------------------------------------------------------------
local skills   -- [lower name] = { name, rank, max, pro }

function CH.Skills()
	local out = {}
	if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
		local indexes = { Call(GetProfessions) }
		for slot = 1, 6 do
			local index = Number(indexes[slot])
			if index then
				local name, _, rank, max = Call(GetProfessionInfo, index)
				name = Text(name)
				if name then out[name:lower()] = { name = name, rank = Number(rank) or 0, max = Number(max), pro = true } end
			end
		end
	end
	local info = C_SkillInfo
	if info and info.GetNumSkillLines and info.GetSkillLineInfo then
		for index = 1, Number(Call(info.GetNumSkillLines)) or 0 do
			local line = Call(info.GetSkillLineInfo, index)
			if type(line) == "table" and not line.isHeader then
				local name = Text(line.name)
				if name and not out[name:lower()] then
					out[name:lower()] = { name = name, rank = Number(line.rank) or 0, max = Number(line.maxRank) }
				end
			end
		end
	end
	return out
end

function CH.CheckSkills()
	local now = CH.Skills()
	local before = skills
	skills = now
	if not (ready and before) then return end
	for key, skill in pairs(now) do
		local was = before[key]
		if not was then
			if skill.pro then
				J:Log("profession", { profession = skill.name })
			else
				J:Log("skill", { profession = skill.name, rank = skill.rank, max = skill.max })
			end
		elseif skill.pro and was.rank < skill.rank and skill.max and skill.rank == skill.max then
			if skill.max >= CH.MASTER then
				J:Log("skill", { profession = skill.name, rank = skill.rank, max = skill.max, mastered = true, keep = true })
			elseif CH.PRO_CAPS[skill.max] then
				J:Log("skill", { profession = skill.name, rank = skill.rank, max = skill.max })
			end
		end
	end
end

---------------------------------------------------------------------------
-- Reputation: every new standing; Honored and up is a keepsake (Kinds).
---------------------------------------------------------------------------
local standings = {}   -- factionID -> the standing written this session

function CH.OnStanding(factionID, standing)
	factionID = Number(factionID)
	if not (ready and factionID) then return end
	local data = C_Reputation and Call(C_Reputation.GetFactionDataByID, factionID)
	if type(data) ~= "table" then return end
	local name = Text(data.name)
	local reaction = Number(data.reaction) or Number(standing)
	if not (name and reaction) or standings[factionID] == reaction then return end
	standings[factionID] = reaction
	J:Log("rep", { faction = name, factionID = factionID, standing = reaction })
end

---------------------------------------------------------------------------
-- Bosses: ENCOUNTER_END (success) and BOSS_KILL, by encounter id. The first
-- kill of each boss is a keepsake row; later kills are "bossagain" rows.
---------------------------------------------------------------------------
local lastKill = {}        -- encounterID -> GetTime() of the counted kill
local encounterLoot = {}   -- itemID -> { encounter, boss, at }

function CH.Boss(encounterID, name)
	encounterID, name = Number(encounterID), Text(name)
	if not encounterID then return end
	local now = GetTime()
	if lastKill[encounterID] and now - lastKill[encounterID] < CH.BOSS_SAME then return end
	lastKill[encounterID] = now
	local rec = R.Rec()
	if not rec then return end
	local instance, _, kind = R.Instance()
	local entry = rec.bosses[encounterID]
	-- A boss an imported journal counted (Import.lua keeps those by name) is
	-- the same boss: its kills go on, and this is no first kill.
	local imported = name and rec.bosses["name:" .. name]
	if type(entry) ~= "table" and type(imported) == "table" then
		entry = imported
		rec.bosses["name:" .. name] = nil
		rec.bosses[encounterID] = entry
	end
	local first = type(entry) ~= "table"
	if first then
		entry = { name = name, first = R.Now(), kills = 0, instance = instance }
		rec.bosses[encounterID] = entry
	end
	entry.kills = (tonumber(entry.kills) or 0) + 1
	entry.name = entry.name or name
	local M = E.Instances
	local run = M and M.current
	if run and run.id then
		local extras = rec.runExtras[run.id]
		if type(extras) ~= "table" then
			extras = {}
			rec.runExtras[run.id] = extras
		end
		extras.bosses = type(extras.bosses) == "table" and extras.bosses or {}
		extras.bosses[#extras.bosses + 1] = encounterID
	end
	local fields = { boss = entry.name, encounter = encounterID, instance = instance or entry.instance, kills = entry.kills }
	if first then
		fields.first = true
		fields.keep = true
		J:Log(kind == "raid" and "raidboss" or "boss", fields)
	else
		J:Log("bossagain", fields)
	end
	S.Bump(rec)
end

-- The game says which encounter dropped an item you received.
function CH.OnEncounterLoot(encounterID, itemID)
	encounterID, itemID = Number(encounterID), Number(itemID)
	if not (encounterID and itemID) then return end
	local rec = S.Own()
	local boss = rec and type(rec.bosses[encounterID]) == "table" and rec.bosses[encounterID].name or nil
	encounterLoot[itemID] = { encounter = encounterID, boss = boss, at = GetTime() }
end

---------------------------------------------------------------------------
-- Finds: your own loot lines (E.ChatParse "item"; secret lines skipped),
-- uncommon and up, never crafting materials.
---------------------------------------------------------------------------
local QUALITY_BY_COLOR = { ff1eff00 = 2, ff0070dd = 3, ffa335ee = 4, ffff8000 = 5, ffe6cc80 = 6, ff00ccff = 7 }

function CH.LinkQuality(link)
	local color = link:match("|c(%x%x%x%x%x%x%x%x)|Hitem:")
	if color then return QUALITY_BY_COLOR[color:lower()] end
	return tonumber(link:match("|cnIQ(%d):|Hitem:"))
end

local function IsWished(itemID)
	local LG = E.LootGuide
	local data = LG and LG.Char and Call(LG.Char, LG)
	local wishes = type(data) == "table" and data.wishlist
	return type(wishes) == "table" and wishes[itemID] ~= nil
end

function CH.OnLoot(text)
	local fields = E.ChatParse and E.ChatParse:Parse("item", text)
	local link = fields and Text(fields.link)
	if not link then return end
	local itemID = tonumber(link:match("|Hitem:(%d+)"))
	if not itemID then return end
	local quality = CH.LinkQuality(link) or (C_Item and Number(Call(C_Item.GetItemQualityByID, itemID)))
	if not quality or quality < 2 then return end
	local armor
	if C_Item and C_Item.GetItemInfoInstant then
		local _, _, _, _, _, classID, subclassID = Call(C_Item.GetItemInfoInstant, itemID)
		classID, subclassID = Number(classID), Number(subclassID)
		if classID and CH.MATERIAL[classID] then return end
		if classID == 4 and subclassID and subclassID >= 1 and subclassID <= 4 then armor = subclassID end
	end
	if not J:Recording() then return end
	local zone, sub = R.Zone()
	local level = R.Level()
	C_Timer.After(CH.LOOT_WAIT, function()
		local drop = encounterLoot[itemID]
		if drop and GetTime() - drop.at > 120 then drop = nil end
		encounterLoot[itemID] = nil
		J:Log("loot", { item = itemID, quality = quality, armor = armor, from = drop and drop.boss or nil,
			level = level, zone = zone, subzone = sub })
		if IsWished(itemID) then J:Log("wish", { item = itemID, ref = "wish:" .. itemID, level = level, zone = zone, subzone = sub }) end
	end)
end

---------------------------------------------------------------------------
-- Mounts, pets, re-specs, titles, hearth, guild, cinematics
---------------------------------------------------------------------------
function CH.Mount(mountID)
	mountID = Number(mountID)
	local name = mountID and C_MountJournal and Text(Call(C_MountJournal.GetMountInfoByID, mountID))
	if name then J:Log("mount", { mount = mountID, name = name }) end
end

function CH.Pet(guid)
	if E:IsSecret(guid) or not (C_PetJournal and C_PetJournal.GetPetInfoByPetID) then return end
	local _, custom, _, _, _, _, _, name = Call(C_PetJournal.GetPetInfoByPetID, guid)
	name = Text(custom) or Text(name)
	if name then J:Log("pet", { name = name }) end
end

-- All points coming back at once (two or more, not right after a level-up)
-- is a re-spec. The spent total is the talent tree's own (Talents module).
local spent

local function SpentPoints()
	local T = E.Talents
	if not (T and T.LiveState) then return nil end
	if T.Invalidate then Call(T.Invalidate, T) end
	local state = Call(T.LiveState, T)
	return type(state) == "table" and Number(state.total) or nil
end

function CH.CheckTalents()
	local now = SpentPoints()
	if not now then return end
	local before = spent
	spent = now
	if not (ready and before) then return end
	local leveled = R.state.lastLevelUp and GetTime() - R.state.lastLevelUp < 3
	if before - now >= 2 and not leveled then J:Log("respec", { points = before - now }) end
end

local function SeedTitles(rec)
	local titles = R.Map(rec, "titles")
	local count = Number(Call(GetNumTitles)) or 0
	local fresh = next(titles) == nil
	for id = 1, count do
		local known = Call(IsTitleKnown, id)
		if not E:IsSecret(known) and known and not titles[id] then
			titles[id] = true
			if not fresh then
				local name = Text(Call(GetTitleName, id))
				if name then J:Log("title", { title = id, name = strtrim(name), keep = true }) end
			end
		end
	end
	if fresh then titles[0] = true end   -- seeded: later titles are new
end

function CH.OnTitles(unit)
	if unit ~= nil and unit ~= "player" then return end
	local rec = R.Rec()
	if rec and type(IsTitleKnown) == "function" then SeedTitles(rec) end
end

function CH.OnHearth()
	local place = Text(Call(GetBindLocation))
	if place then J:Log("hearth", { place = place }) end
end

function CH.OnGuild()
	local rec = R.Rec()
	if not rec then return end
	local guild = Text((Call(GetGuildInfo, "player")))
	if guild and rec.lastGuild ~= guild then
		if rec.lastGuild ~= nil or ready then J:Log("guild", { guild = guild }) end
		rec.lastGuild = guild
	elseif not guild and ready then
		rec.lastGuild = false
	end
end

function CH.OnCinematic()
	if ready then J:Log("cinematic", {}) end
end

---------------------------------------------------------------------------
-- Flight paths: new known nodes on the taxi map; the system line covers a
-- flight master whose map never opened.
---------------------------------------------------------------------------
local lastFlightRow = 0
local UNREACHABLE = Enum and Enum.FlightPathState and Enum.FlightPathState.Unreachable or 2

function CH.OnTaxiMap()
	local rec = R.Rec()
	if not (rec and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then return end
	local mapID = C_Map and Number(Call(C_Map.GetBestMapForUnit, "player"))
	local nodes = mapID and Call(C_TaxiMap.GetAllTaxiNodes, mapID)
	if type(nodes) ~= "table" then return end
	local taxi = R.Map(rec, "taxi")
	local seeded = taxi[0] == true
	for _, node in ipairs(nodes) do
		local id, state = Number(node.nodeID), Number(node.state)
		if id and state and state ~= UNREACHABLE and not taxi[id] then
			taxi[id] = true
			local name = Text(node.name)
			if seeded and name then
				J:Log("flight", { place = (name:match("^(.-),") or name), node = id })
				lastFlightRow = GetTime()
			end
		end
	end
	taxi[0] = true
end

function CH.NewFlightLine()
	local at = GetTime()
	C_Timer.After(3, function()
		if math.abs(lastFlightRow - at) < CH.FLIGHT_SAME then return end
		local zone, sub = R.Zone()
		local place = sub or zone
		if place then
			J:Log("flight", { place = place })
			lastFlightRow = GetTime()
		end
	end)
end

---------------------------------------------------------------------------
-- System lines (only when not secret)
---------------------------------------------------------------------------
local LINES

local function Lines()
	if LINES then return LINES end
	LINES = {
		recipe = Pattern("ERR_LEARN_RECIPE_S"),
		spell = Pattern("ERR_LEARN_SPELL_S"),
		ability = Pattern("ERR_LEARN_ABILITY_S"),
		skill = Pattern("ERR_SKILL_GAINED_S"),
		flight = rawget(_G, "ERR_NEWTAXIPATH"),
	}
	return LINES
end
CH.ResetLines = function() LINES = nil end

function CH.OnSystem(text)
	text = Text(text)
	if not (text and ready) then return end
	local lines = Lines()
	if lines.flight and text == lines.flight then return CH.NewFlightLine() end
	local recipe = lines.recipe and text:match(lines.recipe)
	if recipe then return CH.LearnRecipe(Unlink(recipe)) end
	local skill = lines.skill and text:match(lines.skill)
	if skill then
		-- Professions are written by the skill check; weapon skills here.
		local known = CH.Skills()[skill:lower()]
		if not (known and known.pro) then
			if skills then skills[skill:lower()] = known or { name = skill, rank = 1 } end
			J:Log("skill", { profession = skill, rank = known and known.rank or 1, max = known and known.max })
		end
		return
	end
	for _, key in ipairs({ "spell", "ability" }) do
		local name = lines[key] and text:match(lines[key])
		if name then return CH.LearnSpell(nil, Unlink(name)) end
	end
end

---------------------------------------------------------------------------
-- Quests: who gave it, where and when, what it asked; joined to the
-- hand-in. Titles load through QUEST_DATA_LOAD_RESULT when the game does
-- not have them yet.
---------------------------------------------------------------------------
local offered = {}         -- the NPC that showed a quest's text
local turnInNPC
local turnedIn = {}        -- questID -> true for this session
local waitingTitle = {}    -- questID -> hand-in entry without a title

local function NPC()
	local exists = Call(UnitExists, "npc")
	if E:IsSecret(exists) or not exists then return nil end
	return Text((Call(UnitName, "npc")))
end

local function FirstSentence(text)
	text = Text(text)
	if not text then return nil end
	return text:match("^(.-[%.!?])%s") or text
end

local function Objectives(questID)
	local list = C_QuestLog and Call(C_QuestLog.GetQuestObjectives, questID)
	if type(list) ~= "table" then return nil end
	local parts = {}
	for _, objective in ipairs(list) do
		local text = type(objective) == "table" and Text(objective.text)
		if text then parts[#parts + 1] = text end
	end
	return parts[1] and table.concat(parts, "; ") or nil
end
CH.Objectives = Objectives

local function Title(questID)
	return C_QuestLog and Text(Call(C_QuestLog.GetTitleForQuestID, questID))
end

local function Tag(questID)
	local info = C_QuestLog and Call(C_QuestLog.GetQuestTagInfo, questID)
	return type(info) == "table" and Text(info.tagName) or nil
end

function CH.OnDetail()
	local objective = type(rawget(_G, "GetObjectiveText")) == "function" and FirstSentence(Call(rawget(_G, "GetObjectiveText"))) or nil
	offered.name, offered.t, offered.objective = NPC(), GetTime(), objective
end

function CH.OnAccepted(a1, a2)
	local questID = Number(a2) or Number(a1)
	local rec = R.Rec()
	if not (rec and questID) then return end
	local recent = offered.t and GetTime() - offered.t < 120
	local giver = NPC() or (recent and offered.name) or nil
	local zone, sub = R.Zone()
	local map, x, y = R.Position()
	local start = rec.questStart[questID]
	local with = type(start) == "table" and start.with or nil
	rec.questStart[questID] = { t = R.Now(), giver = giver, z = zone, s = sub, l = R.Level(), map = map, x = x, y = y,
		objective = recent and offered.objective or nil, with = with }
	C_Timer.After(0.5, function()
		local entry = rec.questStart[questID]
		if type(entry) == "table" and not entry.objective then entry.objective = Objectives(questID) end
	end)
end

function CH.OnComplete()
	turnInNPC = NPC()
end

function CH.OnTurnedIn(questID, xp, money)
	questID = Number(questID)
	local rec = R.Rec()
	if not (rec and questID) then return end
	turnedIn[questID] = true
	local zone, sub = R.Zone()
	local map, x, y = R.Position()
	local level = R.Level()
	local instance = R.Instance()
	local start = rec.questStart[questID]
	start = type(start) == "table" and start or {}
	local with = {}
	for key in pairs(type(start.with) == "table" and start.with or {}) do with[key] = true end
	local F = A.Fellowship
	for _, key in ipairs(F and F.QuestPartners and F.QuestPartners(questID) or {}) do with[key] = true end
	local entry = {
		t = R.Now(), id = questID, z = zone, s = sub, l = level, xp = Number(xp), m = Number(money), map = map, x = x, y = y,
		title = Title(questID), tag = Tag(questID), instance = instance, giver = start.giver, taker = turnInNPC,
		objective = start.objective, started = start.t, fromZone = start.z, with = next(with) and with or nil,
	}
	rec.questStart[questID] = nil
	turnInNPC = nil
	S.AddQuest(rec, entry)
	local row = R.LevelRec(rec, level)
	if row then row.quests = row.quests + 1 end
	local place = R.ZoneRec(rec, zone)
	if place then place.quests = (tonumber(place.quests) or 0) + 1 end
	if not entry.title and C_QuestLog and C_QuestLog.RequestLoadQuestByID then
		waitingTitle[questID] = entry
		Call(C_QuestLog.RequestLoadQuestByID, questID)
	end
	A:Fire("QuestTurnedIn", questID, entry)
	A:MarkDirty("quests")
end

function CH.OnQuestData(questID, success)
	questID = Number(questID)
	local entry = questID and waitingTitle[questID]
	if not entry then return end
	waitingTitle[questID] = nil
	if E:IsSecret(success) or not success then return end
	entry.title = Title(questID)
	if entry.title then A:MarkDirty("quests") end
end

-- A quest that leaves the log without a hand-in (abandoned, failed or
-- dropped by the game) goes on the abandoned list for the Quests page,
-- with where and when you took it. QUEST_REMOVED fires on a hand-in too,
-- so wait for QUEST_TURNED_IN first; a replay quest is not a drop.
CH.CAP_ABANDONED = 200

function CH.OnRemoved(questID, replay)
	questID = Number(questID)
	if not questID or (not E:IsSecret(replay) and replay) then return end
	local title = Title(questID)
	local level = R.Level()
	C_Timer.After(1, function()
		if turnedIn[questID] then return end
		local rec = R.Rec()
		if not rec then
			local own = S.Own()
			if own then own.questStart[questID] = nil end
			return
		end
		local start = rec.questStart[questID]
		start = type(start) == "table" and start or {}
		rec.questStart[questID] = nil
		local list = R.Map(rec, "abandoned")
		list[#list + 1] = { t = R.Now(), id = questID, title = title or Title(questID), l = level, z = start.z, s = start.s,
			started = start.t, giver = start.giver }
		while #list > CH.CAP_ABANDONED do table.remove(list, 1) end
		S.Bump(rec)
		A:Fire("QuestAbandoned", questID, list[#list])
		A:MarkDirty("quests")
	end)
end

-- Quests that left the log without a hand-in, newest first:
-- { { t, id, title, z, s, l, started, giver } }.
function J:Abandoned(charKey)
	local rec = self:Char(charKey)
	local out = {}
	local list = rec and type(rec.abandoned) == "table" and rec.abandoned or {}
	for index = #list, 1, -1 do
		if type(list[index]) == "table" then out[#out + 1] = list[index] end
	end
	return out
end

function J:OpenQuests()
	local out = {}
	local log = C_QuestLog
	if not (log and log.GetNumQuestLogEntries and log.GetInfo) then return out end
	local rec = S.Own()
	for index = 1, Number(Call(log.GetNumQuestLogEntries)) or 0 do
		local info = Call(log.GetInfo, index)
		if type(info) == "table" and not info.isHeader then
			local questID = Number(info.questID)
			local title = Text(info.title)
			if questID and title then
				local have, need = 0, 0
				local list = Call(log.GetQuestObjectives, questID)
				for _, objective in ipairs(type(list) == "table" and list or {}) do
					have = have + (Number(objective.numFulfilled) or 0)
					need = need + (Number(objective.numRequired) or 0)
				end
				local complete = Call(log.IsComplete, questID)
				local start = rec and rec.questStart[questID]
				out[#out + 1] = { questID = questID, title = title, level = Number(info.level), have = have, need = need,
					ready = (not E:IsSecret(complete) and complete) and true or false, start = type(start) == "table" and start or nil }
			end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Part
---------------------------------------------------------------------------
local events = R.Events({
	LEARNED_SPELL_IN_SKILL_LINE = function(spellID) CH.LearnSpell(Number(spellID)) end,
	CHAT_MSG_SYSTEM = function(text) CH.OnSystem(text) end,
	CHAT_MSG_SKILL = function(text) CH.OnSystem(text) CH.CheckSkills() end,
	SKILL_LINES_CHANGED = function() CH.CheckSkills() end,
	FACTION_STANDING_CHANGED = function(factionID, standing) CH.OnStanding(factionID, standing) end,
	ENCOUNTER_END = function(encounterID, name, _, _, success)
		if not E:IsSecret(success) and (success == 1 or success == true) then CH.Boss(encounterID, name) end
	end,
	BOSS_KILL = function(encounterID, name) CH.Boss(encounterID, name) end,
	ENCOUNTER_LOOT_RECEIVED = function(encounterID, itemID) CH.OnEncounterLoot(encounterID, itemID) end,
	CHAT_MSG_LOOT = function(text) CH.OnLoot(text) end,
	NEW_MOUNT_ADDED = function(mountID) CH.Mount(mountID) end,
	NEW_PET_ADDED = function(guid) CH.Pet(guid) end,
	TRAIT_CONFIG_UPDATED = function() CH.CheckTalents() end,
	TAXIMAP_OPENED = function() CH.OnTaxiMap() end,
	KNOWN_TITLES_UPDATE = function(unit) CH.OnTitles(unit) end,
	HEARTHSTONE_BOUND = function() CH.OnHearth() end,
	PLAYER_GUILD_UPDATE = function() CH.OnGuild() end,
	CINEMATIC_START = function() CH.OnCinematic() end,
	PLAY_MOVIE = function() CH.OnCinematic() end,
	QUEST_DETAIL = function() CH.OnDetail() end,
	QUEST_ACCEPTED = function(a1, a2) CH.OnAccepted(a1, a2) end,
	QUEST_COMPLETE = function() CH.OnComplete() end,
	QUEST_TURNED_IN = function(questID, xp, money) CH.OnTurnedIn(questID, xp, money) end,
	QUEST_DATA_LOAD_RESULT = function(questID, success) CH.OnQuestData(questID, success) end,
	QUEST_REMOVED = function(questID, replay) CH.OnRemoved(questID, replay) end,
})
CH.events = events

local replayTimer

-- After the login replay: take the snapshots later changes are read against.
function CH.Arm()
	ready = true
	skills = CH.Skills()
	spent = SpentPoints()
	local rec = R.Rec()
	if rec and type(IsTitleKnown) == "function" then SeedTitles(rec) end
	CH.OnGuild()
end

A:AddPart("chronicle", {
	order = 11,
	start = function()
		events.Start()
		ready = false
		if replayTimer then replayTimer:Cancel() end
		replayTimer = C_Timer.NewTimer(CH.REPLAY_SECONDS, function()
			replayTimer = nil
			CH.Arm()
		end)
	end,
	stop = function()
		events.Stop()
		ready = false
		if replayTimer then
			replayTimer:Cancel()
			replayTimer = nil
		end
		wipe(pendingSpells)
		wipe(encounterLoot)
		wipe(waitingTitle)
	end,
})
