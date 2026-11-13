-- EldoUI My Adventure: goal kinds, progress routed through J:Progress, completion.
--
-- A goal is something the player wants to work towards: reach a level,
-- collect an item, run a dungeon, finish an attunement, tick off a to-do.
-- Progress only ever comes from what the game reports: the item count in
-- your bags, your level, your reputation standing, a quest the game marks
-- done, the experience and money the game tells you about, and XP kill
-- lines in chat (only named kills, after a secret test). Nothing is
-- guessed from a target or the combat log, and nothing acts for you.
--
-- Saved in the journal (EldoUIDB.journal[charKey].goals, Store.lua):
--   { id, kind, need, created, target?, name?, itemID?, icon?, count?,
--     base?, src?, visited?, done?, doneAt?, archived? }
-- Counted kinds (kills, creature, xp, gold, quests and, without the
-- Instances module, runs and dungeon) keep `count` from the moment the
-- goal is set; kinds a source answers (runs and dungeon with Instances,
-- attunements, wishes) keep `base`, the source's number when it was set.
--
-- API (E.Adventure.Goals, also E.Journal.Goals):
--   G:Kinds()                      the goal kinds for the picker, in order
--   G:Kind(key)                    one kind definition
--   G:Add(def) -> goal | nil, err  def = { kind, need, target, name, itemID, text }
--   G:Get(id), G:List()            active, reached, archived (newest reached first)
--   G:Progress(goal)               have, need, hint (live)
--   G:Label(goal), G:Icon(goal), G:Describe(goal)  (export and tracker lines)
--   G:Tick(id)                     tick or untick a to-do by hand
--   G:Delete(id) -> trashID        soft delete (Undo through J:Undo)
--   G:Archive(id, on), G:ArchiveReached()
--   G:Check()                      complete what is reached (runs on game events)
--   G:CountActive()                active goals (the hub's tab count)
--   G.Announce(data)               a moment card (Moments.lua) or an alert
--
-- Callbacks (J.RegisterCallback): "GoalSet"(goal), "GoalReached"(goal).
--
-- Portions adapted from Forever Journal by Ugge Zen, MIT License (see
-- THIRD_PARTY_NOTICES.md): the goal kinds, their texts and steps, the
-- count-since-set rule and the completion flow.
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
local L = E.L
local Key = E.Key
local A = E.Adventure
local J = E.Journal
local S = A.Store
local LG = E.LootGuide

local Plain = A.Plain

local G = {}
A.Goals = G
J.Goals = G

G.MAX_COUNT = 99999
G.RUN_GAP = 3600          -- back in the same instance within this: the same run
G.ICON_TODO = "Interface/Icons/INV_Misc_Note_01"

local function Now()
	return time()
end

local function Rec()
	return J:Char()
end

local function Lower(text)
	if type(text) ~= "string" or E:IsSecret(text) then return "" end
	return E:FoldText(strtrim(text))
end

local function Same(a, b)
	local x, y = Lower(a), Lower(b)
	return x ~= "" and x == y
end

local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d, e, f, g = pcall(fn, ...)
	if not ok then return nil end
	return a, b, c, d, e, f, g
end

-- Text without color codes; a link becomes its name.
function G.Plainify(text)
	if type(text) ~= "string" then return "" end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	text = text:gsub("|H.-|h%[?(.-)%]?|h", "%1")
	return text
end

local function Number(value)
	value = Plain(value)
	return type(value) == "number" and value or nil
end

local function Level()
	return Number(UnitLevel("player")) or 1
end

local function MaxLevel()
	local max = Number(Call(rawget(_G, "GetMaxPlayerLevel")))
	return max and max > 1 and max or 60
end

---------------------------------------------------------------------------
-- What the game reports, read once per call
---------------------------------------------------------------------------
-- Item id from a link, an id or a name the item cache knows.
function G.ItemID(value)
	if type(value) == "number" then return value end
	if type(value) ~= "string" or E:IsSecret(value) then return nil end
	local id = value:match("|Hitem:(%d+)")
	if id then return tonumber(id) end
	if value:match("^%s*%d+%s*$") then return tonumber(value) end
	local text = strtrim(value)
	if text == "" then return nil end
	local item = C_Item
	local found = item and Number(Call(item.GetItemInfoInstant, text))
	return found
end

function G.ItemName(itemID, fallback)
	local item = C_Item
	local name = item and Plain(Call(item.GetItemNameByID, itemID))
	if type(name) ~= "string" or name == "" then name = Plain(Call(rawget(_G, "GetItemInfo"), itemID)) end
	if type(name) == "string" and name ~= "" then return name end
	return fallback
end

function G.ItemIcon(itemID)
	local item = C_Item
	local icon = item and Plain(Call(item.GetItemIconByID, itemID))
	if icon then return icon end
	if not item then return nil end
	local _, _, _, _, instant = Call(item.GetItemInfoInstant, itemID)
	return Plain(instant)
end

local function BagCount(itemID)
	local item = C_Item
	return item and Number(Call(item.GetItemCount, itemID, false)) or 0
end

-- Professions you know: { { name, rank, max, icon } }.
function G.Professions()
	local list = {}
	local get, info = rawget(_G, "GetProfessions"), rawget(_G, "GetProfessionInfo")
	if type(get) ~= "function" or type(info) ~= "function" then return list end
	local indexes = { Call(get) }
	for slot = 1, 6 do
		local index = Plain(indexes[slot])
		if type(index) == "number" then
			local name, icon, rank, max = Call(info, index)
			name, rank, max = Plain(name), Number(rank), Number(max)
			if type(name) == "string" and name ~= "" then list[#list + 1] = { name = name, rank = rank or 0, max = max, icon = icon } end
		end
	end
	return list
end

local function Profession(name)
	for _, prof in ipairs(G.Professions()) do
		if Same(prof.name, name) then return prof end
	end
	return nil
end

-- Reputation, read as the game lists it (headers are never expanded).
function G.Factions()
	local list = {}
	local R = C_Reputation
	if not (R and R.GetNumFactions and R.GetFactionDataByIndex) then return list end
	local count = Number(Call(R.GetNumFactions)) or 0
	for index = 1, math.min(count, 300) do
		local data = Call(R.GetFactionDataByIndex, index)
		if type(data) == "table" and not E:IsSecret(data.name) and type(data.name) == "string" and data.name ~= ""
			and not data.isHeader then
			list[#list + 1] = { name = data.name, id = Number(data.factionID), reaction = Number(data.reaction) }
		end
	end
	return list
end

local function Standing(goal)
	local R = C_Reputation
	local id = tonumber(goal.factionID)
	if id and R and R.GetFactionDataByID then
		local data = Call(R.GetFactionDataByID, id)
		if type(data) == "table" then return Number(data.reaction) end
	end
	for _, faction in ipairs(G.Factions()) do
		if Same(faction.name, goal.target) then return faction.reaction end
	end
	return nil
end

-- The game's own word for a standing (1 Hated ... 8 Exalted).
function G.StandingName(reaction)
	local text = Plain(rawget(_G, "FACTION_STANDING_LABEL" .. tostring(reaction)))
	if type(text) == "string" and text ~= "" then return text end
	return tostring(reaction or "")
end

-- Quests in your log, read without selecting one: { { id, title } }.
function G.LogQuests()
	local list = {}
	local Q = C_QuestLog
	if not (Q and Q.GetNumQuestLogEntries and Q.GetInfo) then return list end
	local count = Number(Call(Q.GetNumQuestLogEntries)) or 0
	for index = 1, math.min(count, 60) do
		local info = Call(Q.GetInfo, index)
		if type(info) == "table" and not info.isHeader and not E:IsSecret(info.title) and type(info.title) == "string" then
			list[#list + 1] = { id = Number(info.questID), title = info.title }
		end
	end
	return list
end

function G.QuestTitle(questID, fallback)
	local Q = C_QuestLog
	local title = Q and Plain(Call(Q.GetTitleForQuestID, questID))
	if type(title) == "string" and title ~= "" then return title end
	local entry = LG and LG.Quest and Call(LG.Quest, LG, questID)
	if type(entry) == "table" and type(entry.name) == "string" then return entry.name end
	return fallback
end

local function QuestDone(questID)
	local Q = C_QuestLog
	if not (Q and Q.IsQuestFlaggedCompleted and tonumber(questID)) then return false end
	return Plain(Call(Q.IsQuestFlaggedCompleted, tonumber(questID))) == true
end

-- Where you are now: zone, subzone, minimap zone, and the instance.
local function Here()
	local zone = Plain(Call(rawget(_G, "GetRealZoneText")))
	local sub = Plain(Call(rawget(_G, "GetSubZoneText")))
	local small = Plain(Call(rawget(_G, "GetMinimapZoneText")))
	local shown = Plain(Call(rawget(_G, "GetZoneText")))
	return { zone, sub, small, shown }
end
G.Here = Here

local function InstanceNow()
	local inside, kind = Call(rawget(_G, "IsInInstance"))
	inside, kind = Plain(inside), Plain(kind)
	if not inside or (kind ~= "party" and kind ~= "raid") then return nil end
	local name = Plain(Call(rawget(_G, "GetInstanceInfo")))
	return type(name) == "string" and name ~= "" and name or nil
end
G.InstanceNow = InstanceNow

local function AttuneRunning()
	local At = E.Attunements
	return At and At.Running and Call(At.Running, At) and true or false
end

---------------------------------------------------------------------------
-- Goal kinds. Each kind:
--   key, title, desc, icon     the picker tile
--   input                      "item", "text", "count", "none" (questions in the form)
--   question                   the text question ("Which dungeon?")
--   count                      { question, step, default = fn(), min, max } or nil
--   suggest = fn() -> { { label, value, extra } }   chips under the text box
--   prepare = fn(goal, def) -> ok, err   fill target/name from the form
--   label = fn(goal), hint = fn(goal, have, need), progress = fn(goal) -> have, need
--   hidden = fn()              left out of the picker while true
--   counted                    counted from events (G:Count) while the journal records
---------------------------------------------------------------------------
local KINDS, ORDER = {}, {}

-- A kind's title, line and questions are English keys: reading them gives
-- the text in the current language.
local function Kind(key, def)
	def.key = key
	E:TranslateFields({ def }, "title", "desc", "question")
	if type(def.count) == "table" then E:TranslateFields({ def.count }, "question") end
	KINDS[key] = def
	ORDER[#ORDER + 1] = key
end

local function Count(goal)
	return tonumber(goal.count) or 0
end

local function CountHint(have, need)
	local left = math.max((need or 0) - (have or 0), 0)
	return (L["%s to go"]):format(BreakUpLargeNumbers(left))
end

local function SinceHint(goal)
	return (L["since %s"]):format(G.DateText(goal.created))
end

-- Source-backed counts (runs with the Instances module): the number now
-- minus the number when the goal was set.
local function SourceCount(goal, kind, target)
	local have = J:Progress({ kind = kind, target = target })
	if type(have) ~= "number" then return nil end
	return math.max(have - (tonumber(goal.base) or 0), 0)
end

Kind("item", {
	title = "Collect an item", desc = "Gather ore, herbs, or cloth, or find one special item.",
	icon = "Interface/Icons/INV_Misc_Bag_10", input = "item", question = Key("Which item?"),
	count = { question = Key("How many?"), step = 1, default = function() return 1 end, min = 1 },
	prepare = function(goal, def)
		local id = tonumber(def.itemID) or G.ItemID(def.item) or G.ItemID(def.text)
		if not id then return false, L["Shift-click the item into the box, or type its exact name while you carry one."] end
		goal.itemID = id
		goal.name = G.ItemName(id, type(def.text) == "string" and strtrim(def.text) or nil)
		goal.icon = G.ItemIcon(id)
		return true
	end,
	label = function(goal)
		local name = G.ItemName(goal.itemID, goal.name) or L["an item"]
		if (goal.need or 1) > 1 then return ("%s %s"):format(BreakUpLargeNumbers(goal.need), name) end
		return name
	end,
	progress = function(goal) return math.min(BagCount(goal.itemID), goal.need), goal.need end,
	hint = function() return L["counted in your bags"] end,
})

Kind("kills", {
	title = "Defeat enemies", desc = "Any creature that gives experience.",
	icon = "Interface/Icons/Ability_DualWield", input = "count", counted = true,
	count = { question = Key("How many?"), step = 1, default = function() return 50 end, min = 1 },
	label = function(goal) return (E:Plural(goal.need, "Defeat %s enemy", "Defeat %s enemies")):format(BreakUpLargeNumbers(goal.need)) end,
	progress = function(goal) return Count(goal), goal.need end,
	hint = function(goal) return SinceHint(goal) end,
})

Kind("creature", {
	title = "Hunt a creature", desc = "One kind, like Mottled Worg. Counts each one that gives you experience.",
	icon = "Interface/Icons/Ability_Hunter_MarkedForDeath", input = "text", counted = true,
	question = Key("Which creature?"),
	count = { question = Key("How many?"), step = 1, default = function() return 10 end, min = 1 },
	suggest = function()
		local list, seen = {}, {}
		local exists = Plain(Call(rawget(_G, "UnitExists"), "target"))
		local isPlayer = Plain(Call(rawget(_G, "UnitIsPlayer"), "target"))
		local name = exists and not isPlayer and Plain(Call(rawget(_G, "UnitName"), "target"))
		if type(name) == "string" and name ~= "" then
			list[#list + 1] = { label = name, value = name, tip = L["Your target."] }
			seen[Lower(name)] = true
		end
		for _, mob in ipairs(G.recentKills or {}) do
			if not seen[Lower(mob)] and #list < 6 then
				list[#list + 1] = { label = mob, value = mob, tip = L["You defeated one of these this session."] }
				seen[Lower(mob)] = true
			end
		end
		return list
	end,
	prepare = function(goal, def)
		local name = type(def.text) == "string" and strtrim(def.text) or ""
		if name == "" then return false, L["Type the creature's name, or use your target."] end
		goal.target, goal.name = name, name
		return true
	end,
	label = function(goal)
		if (goal.need or 1) > 1 then return (L["Defeat %s %s"]):format(BreakUpLargeNumbers(goal.need), goal.name or "") end
		return (L["Defeat %s"]):format(goal.name or "")
	end,
	progress = function(goal) return Count(goal), goal.need end,
	hint = function(goal) return SinceHint(goal) end,
})

Kind("xp", {
	title = "Gain experience", desc = "From kills, quests, and exploring.",
	icon = "Interface/Icons/Spell_Holy_SurgeOfLight", input = "count", counted = true,
	count = { question = Key("How much experience?"), step = 100, default = function() return 1000 end, min = 1 },
	hidden = function() return Level() >= MaxLevel() end,
	label = function(goal) return (L["Gain %s experience"]):format(BreakUpLargeNumbers(goal.need)) end,
	progress = function(goal) return Count(goal), goal.need end,
	hint = function(goal) return SinceHint(goal) end,
})

Kind("gold", {
	title = "Earn gold", desc = "From loot, quests, and sales.",
	icon = "Interface/Icons/INV_Misc_Coin_01", input = "count", counted = true,
	count = { question = Key("How much gold?"), step = 1, default = function() return 10 end, min = 1 },
	label = function(goal) return (L["Earn %s gold"]):format(BreakUpLargeNumbers(goal.need)) end,
	progress = function(goal) return math.floor(Count(goal) / 10000), goal.need end,
	hint = function(goal) return SinceHint(goal) end,
})

Kind("quests", {
	title = "Complete quests", desc = "Hand in a number of quests.",
	icon = "Interface/GossipFrame/ActiveQuestIcon", input = "count", counted = true,
	count = { question = Key("How many?"), step = 1, default = function() return 10 end, min = 1 },
	label = function(goal) return (E:Plural(goal.need, "Complete %s quest", "Complete %s quests")):format(BreakUpLargeNumbers(goal.need)) end,
	progress = function(goal) return Count(goal), goal.need end,
	hint = function(goal) return SinceHint(goal) end,
})

local function RunProgress(goal)
	if goal.src == "instances" then
		local have = SourceCount(goal, "run", goal.target)
		if have then return have, goal.need end
	end
	return Count(goal), goal.need
end

Kind("runs", {
	title = "Run dungeons", desc = "Any dungeon counts.",
	icon = "Interface/Icons/INV_Misc_Key_03", input = "count", counted = true,
	count = { question = Key("How many runs?"), step = 1, default = function() return 5 end, min = 1 },
	label = function(goal) return (E:Plural(goal.need, "Run %s dungeon", "Run %s dungeons")):format(BreakUpLargeNumbers(goal.need)) end,
	progress = RunProgress,
	hint = function(goal) return SinceHint(goal) end,
})

local function Dungeons()
	local list, seen = {}, {}
	local now = InstanceNow()
	if now then
		list[#list + 1] = { label = now, value = now, tip = L["You are here."] }
		seen[Lower(now)] = true
	end
	for _, place in ipairs(J:Places()) do
		local name = place.zone
		local fromRuns = place.sources and place.sources.instances
		if fromRuns and type(name) == "string" and not seen[Lower(name)] and #list < 8 then
			list[#list + 1] = { label = name, value = name, tip = L["You have been here."] }
			seen[Lower(name)] = true
		end
	end
	return list
end

Kind("dungeon", {
	title = "Run a dungeon", desc = "One particular dungeon, once or many times.",
	icon = "Interface/Icons/INV_Misc_Key_14", input = "text", counted = true, question = Key("Which dungeon?"),
	count = { question = Key("How many runs?"), step = 1, default = function() return 1 end, min = 1 },
	suggest = Dungeons,
	prepare = function(goal, def)
		local name = type(def.text) == "string" and strtrim(def.text) or ""
		if name == "" then return false, L["Type the dungeon's name, for example The Deadmines."] end
		for _, item in ipairs(Dungeons()) do
			if Same(item.value, name) then name = item.value end
		end
		goal.target, goal.name = name, name
		return true
	end,
	label = function(goal)
		if (goal.need or 1) > 1 then return (L["Run %s %s times"]):format(goal.name or "", BreakUpLargeNumbers(goal.need)) end
		return (L["Run %s"]):format(goal.name or "")
	end,
	progress = RunProgress,
	hint = function(goal) return SinceHint(goal) end,
})

Kind("level", {
	title = "Reach a level", desc = "A milestone to look forward to.",
	icon = "Interface/Icons/Achievement_Level_10", input = "count",
	count = { question = Key("Which level?"), step = 1, default = function() return math.min(Level() + 1, MaxLevel()) end,
		min = 2, max = function() return MaxLevel() end },
	hidden = function() return Level() >= MaxLevel() end,
	prepare = function(goal)
		if (goal.need or 0) <= Level() then return false, L["Pick a level above the one you have."] end
		return true
	end,
	-- A goal from an import or an old save can lack need: read it as the cap.
	label = function(goal) return (L["Reach level %d"]):format(goal.need or MaxLevel()) end,
	progress = function(goal)
		local need = goal.need or MaxLevel()
		return math.min(Level(), need), need
	end,
	hint = function(goal, have, need)
		local left = math.max(need - have, 0)
		return (E:Plural(left, "%d level to go", "%d levels to go")):format(left)
	end,
})

Kind("zone", {
	title = "Visit a place", desc = "A zone, or a spot inside one like Frostmane Hold.",
	icon = "Interface/Icons/INV_Misc_Map_01", input = "text", question = Key("Which place?"),
	suggest = function()
		local list, seen = {}, {}
		for _, name in ipairs(Here()) do
			if type(name) == "string" and name ~= "" and not seen[Lower(name)] then
				list[#list + 1] = { label = name, value = name, tip = L["You are here."] }
				seen[Lower(name)] = true
			end
		end
		return list
	end,
	prepare = function(goal, def)
		local name = type(def.text) == "string" and strtrim(def.text) or ""
		if name == "" then return false, L["Type the place's name, for example Stranglethorn Vale or Frostmane Hold."] end
		goal.target, goal.name = name, name
		return true
	end,
	label = function(goal) return (L["Visit %s"]):format(goal.name or "") end,
	progress = function(goal) return goal.visited and 1 or 0, 1 end,
	hint = function() return L["a place to find"] end,
})

Kind("skill", {
	title = "Raise a profession", desc = "Reach a skill level in First Aid, Mining, Cooking, and more.",
	icon = "Interface/Icons/INV_Misc_Note_01", input = "text", question = Key("Which profession?"),
	count = { question = Key("Which skill level?"), step = 5, default = function() return 75 end, min = 1, max = function() return 450 end },
	suggest = function()
		local list = {}
		for _, prof in ipairs(G.Professions()) do
			list[#list + 1] = { label = ("%s %d"):format(prof.name, prof.rank or 0), value = prof.name,
				tip = L["One of your professions."] }
		end
		return list
	end,
	prepare = function(goal, def)
		local name = type(def.text) == "string" and strtrim(def.text) or ""
		if name == "" then return false, L["Type the profession's name, for example First Aid."] end
		local prof = Profession(name)
		goal.target, goal.name = prof and prof.name or name, prof and prof.name or name
		goal.icon = prof and prof.icon or nil
		return true
	end,
	label = function(goal) return (L["Reach %d in %s"]):format(goal.need, goal.name or "") end,
	progress = function(goal)
		local prof = Profession(goal.target)
		return math.min(prof and prof.rank or 0, goal.need), goal.need
	end,
	hint = function(goal)
		if not Profession(goal.target) then return L["not learned yet"] end
		return L["profession"]
	end,
})

Kind("todo", {
	title = "Something else", desc = "A to-do you check off yourself.",
	icon = G.ICON_TODO, input = "text", question = Key("What do you want to do?"),
	prepare = function(goal, def)
		local text = type(def.text) == "string" and strtrim(def.text) or ""
		if text == "" then return false, L["Write what you want to do."] end
		goal.name = E:Utf8Sub(text, 200)
		return true
	end,
	label = function(goal) return goal.name or "" end,
	progress = function(goal) return goal.done and 1 or 0, 1 end,
	hint = function() return L["check it off yourself"] end,
})

Kind("attune", {
	title = "Finish an attunement", desc = "An attunement or key, step by step as the Attunements tab tracks it.",
	icon = "Interface/Icons/INV_Misc_Key_14", input = "text", question = Key("Which attunement?"),
	hidden = function() return not AttuneRunning() end,
	suggest = function()
		local list = {}
		local At = E.Attunements
		if not AttuneRunning() then return list end
		for _, item in ipairs(Call(At.Summary, At) or {}) do
			if item.state ~= "done" and type(item.name) == "string" and #list < 8 then
				list[#list + 1] = { label = item.name, value = item.name, extra = item.key,
					tip = E:Plural(item.total or 0, "%d of %d step done.", "%d of %d steps done."):format(item.done or 0, item.total or 0) }
			end
		end
		return list
	end,
	prepare = function(goal, def)
		local At = E.Attunements
		if not AttuneRunning() then return false, L["Turn on Attunements to set this goal."] end
		local key = def.target
		local name = type(def.text) == "string" and strtrim(def.text) or ""
		if not key then
			for _, item in ipairs(Call(At.Summary, At) or {}) do
				if Same(item.name, name) or Same(item.key, name) then key, name = item.key, item.name end
			end
		end
		local entry = key and Call(At.Get, At, key)
		if not entry then return false, L["Pick an attunement from the list, or type its name."] end
		goal.target, goal.name = key, entry.name or name
		return true
	end,
	label = function(goal) return (L["Finish %s"]):format(goal.name or "") end,
	progress = function(goal)
		local have, need = J:Progress({ kind = "attune", target = goal.target })
		if type(have) ~= "number" or type(need) ~= "number" or need <= 0 then return 0, 1 end
		return have, need
	end,
	hint = function(goal, have, need)
		if need <= 1 and have == 0 and not AttuneRunning() then return L["Attunements is off"] end
		return E:Plural(need, "%d of %d step", "%d of %d steps"):format(have, need)
	end,
})

local STANDINGS = { 5, 6, 7, 8 }
G.STANDINGS = STANDINGS

Kind("rep", {
	title = "Earn a standing", desc = "Reach Friendly, Honored, Revered, or Exalted with a faction.",
	icon = "Interface/Icons/INV_Misc_Note_02", input = "text", question = Key("Which faction?"), standing = true,
	suggest = function()
		local list = {}
		for _, faction in ipairs(G.Factions()) do
			if (faction.reaction or 0) < 8 and #list < 8 then
				list[#list + 1] = { label = faction.name, value = faction.name, extra = faction.id,
					tip = (L["Now: %s."]):format(G.StandingName(faction.reaction)) }
			end
		end
		return list
	end,
	prepare = function(goal, def)
		local name = type(def.text) == "string" and strtrim(def.text) or ""
		if name == "" then return false, L["Type the faction's name, for example Stormwind."] end
		local found
		for _, faction in ipairs(G.Factions()) do
			if Same(faction.name, name) then found = faction end
		end
		if not found then return false, L["The game does not list that faction for you yet. Check the spelling on your Reputation tab."] end
		local standing = tonumber(def.standing) or 7
		if (found.reaction or 0) >= standing then return false, L["You already have that standing."] end
		goal.target, goal.name, goal.factionID, goal.need = found.name, found.name, found.id, standing
		return true
	end,
	label = function(goal) return (L["%s with %s"]):format(G.StandingName(goal.need), goal.name or "") end,
	progress = function(goal) return math.min(Standing(goal) or 0, goal.need), goal.need end,
	hint = function(goal)
		local now = Standing(goal)
		return now and (L["now %s"]):format(G.StandingName(now)) or L["not met yet"]
	end,
	trackLabel = function(goal, have) return ("%s / %s"):format(G.StandingName(have), G.StandingName(goal.need)) end,
})

Kind("quest", {
	title = "Finish a quest", desc = "One quest, or the last quest of a chain you are working on.",
	icon = "Interface/GossipFrame/AvailableQuestIcon", input = "text", question = Key("Which quest?"),
	suggest = function()
		local list = {}
		for _, quest in ipairs(G.LogQuests()) do
			if quest.id and #list < 8 then
				list[#list + 1] = { label = quest.title, value = quest.title, extra = quest.id, tip = L["In your quest log."] }
			end
		end
		return list
	end,
	prepare = function(goal, def)
		local id = tonumber(def.target)
		local text = type(def.text) == "string" and def.text or ""
		id = id or tonumber(text:match("|Hquest:(%d+)"))
		if not id then
			for _, quest in ipairs(G.LogQuests()) do
				if Same(quest.title, text) then id = quest.id end
			end
		end
		if not id then return false, L["Shift-click the quest into the box, or pick one from your quest log."] end
		if QuestDone(id) then return false, L["You have already done that quest."] end
		goal.target, goal.name = id, G.QuestTitle(id, strtrim(G.Plainify(text)))
		return true
	end,
	label = function(goal) return (L["Finish %s"]):format(G.QuestTitle(goal.target, goal.name) or "") end,
	progress = function(goal) return QuestDone(goal.target) and 1 or 0, 1 end,
	hint = function() return L["the game marks it done"] end,
})

local function WishItems()
	local list = {}
	if not (LG and LG.WishedItems and LG.active) then return list end
	local items = Call(LG.WishedItems, LG) or {}
	local ids = {}
	for itemID in pairs(items) do ids[#ids + 1] = itemID end
	table.sort(ids)
	for _, itemID in ipairs(ids) do
		if not LG:Owns(itemID) and #list < 8 then
			local name = G.ItemName(itemID)
			if name then list[#list + 1] = { label = name, value = name, extra = itemID, tip = L["On your wishlist."] } end
		end
	end
	return list
end

Kind("wish", {
	title = "Get a wishlist item", desc = "An item from your wishlist. Reached once you have it, worn, in your bags, or in the bank.",
	icon = "Interface/Icons/INV_Misc_Bag_10_Blue", input = "text", question = Key("Which item?"),
	hidden = function() return not WishItems()[1] end,
	suggest = WishItems,
	prepare = function(goal, def)
		local id = tonumber(def.target) or G.ItemID(def.text)
		if not id then
			for _, item in ipairs(WishItems()) do
				if Same(item.value, def.text) then id = item.extra end
			end
		end
		if not id then return false, L["Pick an item from your wishlist."] end
		goal.target, goal.itemID = id, id
		goal.name, goal.icon = G.ItemName(id, def.text), G.ItemIcon(id)
		return true
	end,
	label = function(goal) return (L["Get %s"]):format(G.ItemName(goal.itemID, goal.name) or L["an item"]) end,
	progress = function(goal)
		local have = J:Progress({ kind = "wish", target = goal.target })
		return have and have >= 1 and 1 or 0, 1
	end,
	hint = function() return L["worn, in your bags, or in the bank"] end,
})

G.KINDS, G.ORDER = KINDS, ORDER

function G:Kind(key)
	return KINDS[key]
end

-- The kinds the picker shows now.
function G:Kinds()
	local list = {}
	for _, key in ipairs(ORDER) do
		local def = KINDS[key]
		if not (def.hidden and def.hidden()) then list[#list + 1] = def end
	end
	return list
end

---------------------------------------------------------------------------
-- Dates
---------------------------------------------------------------------------
-- Month names come from the game (CALENDAR_FULLDATE_MONTH_NAMES), so they
-- read in the client's language.
local function MonthName(month)
	return E:MonthName(month)
end
G.MonthName = MonthName

-- "October 8" (this year) or "October 8, 2025".
function G.DateText(t)
	t = tonumber(t)
	if not t then return "" end
	return E:LongDay(t)
end

function G.TimeText(t)
	t = tonumber(t)
	if not t then return "" end
	return E:FormatTime(t)
end

---------------------------------------------------------------------------
-- Reading goals
---------------------------------------------------------------------------
local function Goals()
	local rec = Rec()
	return rec and rec.goals or {}
end

function G:Get(id)
	id = tonumber(id)
	for position, goal in ipairs(Goals()) do
		if type(goal) == "table" and goal.id == id then return goal, position end
	end
	return nil
end

-- active (creation order), reached (newest first), archived (newest first).
function G:List()
	local active, reached, archived = {}, {}, {}
	for _, goal in ipairs(Goals()) do
		if type(goal) == "table" and KINDS[goal.kind] then
			if goal.archived then
				archived[#archived + 1] = goal
			elseif goal.done then
				reached[#reached + 1] = goal
			else
				active[#active + 1] = goal
			end
		end
	end
	table.sort(reached, function(a, b) return (a.doneAt or 0) > (b.doneAt or 0) end)
	table.sort(archived, function(a, b) return (a.archived or 0) > (b.archived or 0) end)
	return active, reached, archived
end

function G:CountActive()
	local count = 0
	for _, goal in ipairs(Goals()) do
		if type(goal) == "table" and KINDS[goal.kind] and not goal.done and not goal.archived then count = count + 1 end
	end
	return count
end

function G:Label(goal)
	local def = goal and KINDS[goal.kind]
	if not def then return "" end
	local ok, text = pcall(def.label, goal)
	return ok and text or ""
end

function G:Icon(goal)
	local def = goal and KINDS[goal.kind]
	if goal and goal.icon then return goal.icon end
	if goal and goal.itemID then
		local icon = G.ItemIcon(goal.itemID)
		if icon then return icon end
	end
	return def and def.icon or G.ICON_TODO
end

-- have, need, hint, track label. A reached goal reads full.
function G:Progress(goal)
	local def = goal and KINDS[goal.kind]
	if not def then return 0, 1, "" end
	local ok, have, need = pcall(def.progress, goal)
	if not ok then
		geterrorhandler()(have)
		have, need = 0, 1
	end
	have, need = tonumber(have) or 0, math.max(tonumber(need) or 1, 1)
	if goal.done then have = math.max(have, need) end
	local hint = ""
	if goal.done and goal.doneAt then
		hint = (L["reached %s"]):format(G.DateText(goal.doneAt))
	elseif def.hint then
		local fine, text = pcall(def.hint, goal, have, need)
		hint = fine and text or ""
	elseif goal.kind ~= "todo" then
		hint = CountHint(have, need)
	end
	local track
	if def.trackLabel then track = def.trackLabel(goal, have) end
	return have, need, hint, track
end

-- One line for exports, backups and the tracker: "Reach level 30 (24 / 30)".
function G:Describe(goal)
	local label = self:Label(goal)
	if goal.kind == "todo" then return goal.done and (L["%s (done)"]):format(label) or label end
	local have, need = self:Progress(goal)
	if goal.done then return (L["%s (reached %s)"]):format(label, G.DateText(goal.doneAt)) end
	return ("%s (%s / %s)"):format(label, BreakUpLargeNumbers(have), BreakUpLargeNumbers(need))
end

---------------------------------------------------------------------------
-- Moments: one card per goal reached or reminder. Moments.lua (the moment
-- card, queue and dungeon hold) takes them when it is there; until then
-- EldoUI's own alert card shows them. Display only: a card's buttons only
-- change the journal (Done, Snooze), never anything in the game.
--   data = { kind, title, text, icon, seconds, sound, key, always, actions }
---------------------------------------------------------------------------
function G.Announce(data)
	if type(data) ~= "table" then return nil end
	local db = A.db or {}
	if not data.always and not db.moments then return nil end
	local M = A.Moments
	if type(M) == "table" and type(M.Push) == "function" then
		local ok, result = pcall(M.Push, M, data)
		if ok then return result end
		geterrorhandler()(result)
	end
	local sound = data.sound
	if type(sound) == "string" and sound ~= "" and sound ~= "none" then
		E:PlayMedia(sound, db.soundMaster and "Master" or nil)
	end
	return A:PushAlert({
		title = data.title, text = data.text, icon = data.icon, key = data.key,
		duration = data.seconds, actions = data.actions,
	})
end

---------------------------------------------------------------------------
-- Writing goals
---------------------------------------------------------------------------
local function Changed()
	local rec = Rec()
	if rec then S.Bump(rec) end
	A:MarkDirty("goals")
end
G.Changed = Changed

local function ClampNeed(def, value)
	local spec = def.count
	if not spec then return 1 end
	local need = math.floor(tonumber(value) or (spec.default and spec.default()) or 1)
	local max = type(spec.max) == "function" and spec.max() or spec.max or G.MAX_COUNT
	return math.min(math.max(need, spec.min or 1), max)
end

-- def = { kind, need, text, item, itemID, target, standing }.
function G:Add(def)
	if not A:Running() then return nil, A:OffReason() or L["My Adventure is off."] end
	if type(def) ~= "table" then return nil, L["Unknown goal type."] end
	local kind = KINDS[def.kind]
	local rec = Rec()
	if not kind then return nil, L["Unknown goal type."] end
	if not rec then return nil, L["The journal is not ready yet. Try again in a moment."] end
	local goal = { kind = kind.key, created = Now(), need = ClampNeed(kind, def.need) }
	if kind.prepare then
		local ok, fine, err = pcall(kind.prepare, goal, def)
		if not ok then
			geterrorhandler()(fine)
			return nil, L["Unknown goal type."]
		end
		if not fine then return nil, err end
	end
	if not kind.count and kind.key ~= "rep" then goal.need = 1 end
	-- Runs: the Instances module counts them when it is on.
	if (goal.kind == "runs" or goal.kind == "dungeon") and J:SourceLive("instances") then
		local have = J:Progress({ kind = "run", target = goal.target })
		if type(have) == "number" then goal.src, goal.base = "instances", have end
	end
	if goal.kind == "zone" then
		for _, name in ipairs(Here()) do
			if Same(name, goal.target) then goal.visited = true end
		end
	end
	goal.id = S.NewId(rec)
	rec.goals[#rec.goals + 1] = goal
	S.Write("goalset", { goal = goal.id, name = self:Label(goal), zone = false })
	A:Fire("GoalSet", goal)
	Changed()
	self:Check()
	return goal
end

---------------------------------------------------------------------------
-- "Set as goal" from anywhere (the where-next cards, plugins):
--   J:AddGoal(spec) -> goal | nil, err
-- spec = { kind, target, need, text } in the where-next shape:
--   { kind = "zone", target = uiMapID or a place name }   -> Visit a place
--   { kind = "dungeon", target = instance key or name }    -> Run a dungeon
--   { kind = "attune", target = attunement key }           -> Finish an attunement
--   { kind = "chain", target = root quest id }             -> Finish a quest
--                                                            (the chain's last part)
--   any other goal kind goes to G:Add as it is.
-- Checks: the kind exists, the target names something real, the goal is
-- not one you already work on (same kind and target), a chain is not
-- done already. The error says what to change.
---------------------------------------------------------------------------
local function ZoneName(uiMapID)
	local N = A.Next
	local name = N and N.ZoneName and N.ZoneName(uiMapID)
	if type(name) == "string" and name ~= "" then return name end
	local info = C_Map and C_Map.GetMapInfo and Call(C_Map.GetMapInfo, uiMapID)
	name = type(info) == "table" and Plain(info.name)
	return type(name) == "string" and name ~= "" and name or nil
end

local function SameGoal(goal, def)
	if goal.kind ~= def.kind or goal.done or goal.archived then return false end
	local target = def.target ~= nil and def.target or def.text
	if type(goal.target) == "number" or type(target) == "number" then return tonumber(goal.target) == tonumber(target) end
	return Same(goal.target, target) or Same(goal.name, target)
end

-- spec -> a G:Add definition, or nil and the reason.
function G.FromSpec(spec)
	if type(spec) ~= "table" or type(spec.kind) ~= "string" then return nil, L["Unknown goal type."] end
	local kind, target = spec.kind, spec.target
	if kind == "zone" then
		local name = tonumber(target) and ZoneName(tonumber(target)) or (type(target) == "string" and strtrim(target) ~= "" and strtrim(target))
		if not name then return nil, L["The game has no name for that place yet."] end
		return { kind = "zone", text = name, target = name }
	elseif kind == "dungeon" then
		local info = type(target) == "string" and LG and LG.InstanceInfo and Call(LG.InstanceInfo, LG, target)
		local name = type(info) == "table" and info.name or nil
		if not name and type(target) == "string" and LG and LG.FindInstance then
			local key = Call(LG.FindInstance, LG, target)
			info = key and Call(LG.InstanceInfo, LG, key)
			name = type(info) == "table" and info.name or nil
		end
		if not name then return nil, L["That dungeon is not in the dungeon list."] end
		return { kind = "dungeon", text = name, target = name, need = spec.need or 1 }
	elseif kind == "attune" then
		if not AttuneRunning() then return nil, L["Turn on Attunements to set this goal."] end
		local At = E.Attunements
		if not (type(target) == "string" and Call(At.Get, At, target)) then return nil, L["Pick an attunement from the list, or type its name."] end
		return { kind = "attune", target = target }
	elseif kind == "chain" then
		local root = tonumber(target)
		local chain = root and LG and LG.QuestChain and Call(LG.QuestChain, LG, root)
		local last = type(chain) == "table" and chain[#chain] and tonumber(chain[#chain].id) or root
		if not last then return nil, L["That quest chain is not in the quest data."] end
		if QuestDone(last) then return nil, L["You have already finished that quest chain."] end
		return { kind = "quest", target = last, text = G.QuestTitle(last) }
	end
	if not KINDS[kind] then return nil, L["Unknown goal type."] end
	local def = {}
	for key, value in pairs(spec) do def[key] = value end
	return def
end

function J:AddGoal(spec)
	local def, err = G.FromSpec(spec)
	if not def then return nil, err end
	if not A:Running() then return nil, A:OffReason() or L["My Adventure is off."] end
	for _, goal in ipairs(Goals()) do
		if type(goal) == "table" and SameGoal(goal, def) then return nil, L["That is one of your goals already."], goal end
	end
	return G:Add(def)
end

local function Complete(goal, quiet)
	local db = A.db or {}
	goal.done, goal.doneAt = true, Now()
	if db.archiveGoals then goal.archived = goal.doneAt end
	local label = G:Label(goal)
	S.Write("goal", { goal = goal.id, name = label, keep = true })
	A:Fire("GoalReached", goal)
	Changed()
	if quiet then return end
	local kinds = type(db.momentKinds) == "table" and db.momentKinds or {}
	if kinds.goal ~= false then
		G.Announce({ kind = "goal", title = L["Goal reached"], text = label, icon = G:Icon(goal),
			seconds = db.momentSeconds, sound = type(db.sounds) == "table" and db.sounds.goal or nil,
			key = "journal-goal-" .. tostring(goal.id) })
	end
end
G.Complete = Complete

-- A to-do ticked by hand (window or tracker); a second click unticks it.
function G:Tick(id)
	local goal = self:Get(id)
	if not goal or goal.kind ~= "todo" then return false end
	if goal.done then
		goal.done, goal.doneAt, goal.archived = nil, nil, nil
		Changed()
	else
		Complete(goal)
	end
	return true
end

function G:Archive(id, on)
	return J:SetArchived("goals", tonumber(id), on)
end

function G:ArchiveReached()
	local count = 0
	local now = Now()
	for _, goal in ipairs(Goals()) do
		if type(goal) == "table" and goal.done and not goal.archived then
			goal.archived = now
			count = count + 1
		end
	end
	if count > 0 then Changed() end
	return count
end

function G:Delete(id)
	local rec = Rec()
	local goal, position = self:Get(id)
	if not (rec and goal) then return nil end
	table.remove(rec.goals, position)
	local trashID = S.TrashItem(rec, "goal", goal)
	Changed()
	return trashID
end

A:AddRestorer("goal", function(rec, goal)
	if type(goal) ~= "table" then return end
	local at = #rec.goals + 1
	for position, other in ipairs(rec.goals) do
		if type(other) == "table" and (other.id or 0) > (goal.id or 0) then
			at = position
			break
		end
	end
	table.insert(rec.goals, at, goal)
	A:MarkDirty("goals")
end)

---------------------------------------------------------------------------
-- Progress from game events
---------------------------------------------------------------------------
local checkQueued = false

-- Complete every active goal that is reached. Cheap: a handful of goals.
function G:Check()
	checkQueued = false
	if not A:Running() then return 0 end
	local done = 0
	for _, goal in ipairs(Goals()) do
		if type(goal) == "table" and KINDS[goal.kind] and not goal.done and not goal.archived and goal.kind ~= "todo" then
			local have, need = self:Progress(goal)
			if need > 0 and have >= need then
				Complete(goal)
				done = done + 1
			end
		end
	end
	return done
end

local function QueueCheck()
	if checkQueued then return end
	checkQueued = true
	C_Timer.After(0.2, function() G:Check() end)
end
G.QueueCheck = QueueCheck

-- Add n to every active counted goal of a kind (name: the creature or
-- dungeon it is for). Only while the journal records.
function G:Count(kind, amount, name)
	if not J:Recording() then return 0 end
	amount = tonumber(amount) or 0
	if amount <= 0 then return 0 end
	local touched = 0
	for _, goal in ipairs(Goals()) do
		if type(goal) == "table" and goal.kind == kind and not goal.done and not goal.archived and goal.src == nil then
			if goal.target == nil or Same(goal.target, name) then
				goal.count = math.min(Count(goal) + amount, 1e12)
				touched = touched + 1
			end
		end
	end
	if touched > 0 then
		Changed()
		QueueCheck()
	end
	return touched
end

local function Visit()
	local here = Here()
	local changed = false
	for _, goal in ipairs(Goals()) do
		if type(goal) == "table" and goal.kind == "zone" and not goal.visited and not goal.done then
			for _, name in ipairs(here) do
				if Same(name, goal.target) then
					goal.visited = true
					changed = true
				end
			end
		end
	end
	if changed then Changed() end
end

-- A dungeon run without the Instances module: entering a dungeon counts
-- once; going back in within an hour (a run back after a wipe) does not.
local function EnterInstance()
	local rec = Rec()
	local name = InstanceNow()
	if not (rec and name) then return end
	local last = rec.ui.goalRun
	local now = Now()
	local fresh = not (type(last) == "table" and last.name == name and now - (tonumber(last.seen) or 0) < G.RUN_GAP)
	rec.ui.goalRun = { name = name, seen = now }
	if fresh then
		G:Count("runs", 1)
		G:Count("dungeon", 1, name)
	end
end

-- Inside: keep the run fresh, so a long run is still one run.
local function KeepRun()
	local rec = Rec()
	local name = InstanceNow()
	if rec and name and type(rec.ui.goalRun) == "table" and rec.ui.goalRun.name == name then rec.ui.goalRun.seen = Now() end
end

local xpNow, xpMax, moneyNow

local function ReadXP()
	return Number(Call(rawget(_G, "UnitXP"), "player")), Number(Call(rawget(_G, "UnitXPMax"), "player"))
end

local function OnXP()
	local xp, max = ReadXP()
	if not (xp and max) then return end
	if xpNow and xpMax then
		local gain = xp - xpNow
		if gain < 0 then gain = (xpMax - xpNow) + xp end   -- a level-up between reads
		if gain > 0 then G:Count("xp", gain) end
	end
	xpNow, xpMax = xp, max
end

local function OnMoney()
	local money = Number(Call(rawget(_G, "GetMoney")))
	if not money then return end
	if moneyNow and money > moneyNow then G:Count("gold", money - moneyNow) end
	moneyNow = money
end

local function OnKill(text)
	if E:IsSecret(text) or type(text) ~= "string" then return end
	local fields = E.ChatParse and E.ChatParse:Parse("xpkill", text)
	local mob = fields and Plain(fields.mob)
	if type(mob) ~= "string" or mob == "" then return end
	G.recentKills = G.recentKills or {}
	for position, name in ipairs(G.recentKills) do
		if name == mob then
			table.remove(G.recentKills, position)
			break
		end
	end
	table.insert(G.recentKills, 1, mob)
	while #G.recentKills > 5 do table.remove(G.recentKills) end
	G:Count("kills", 1)
	G:Count("creature", 1, mob)
end

local events = CreateFrame("Frame")
G.events = events
events:SetScript("OnEvent", function(_, event, ...)
	if event == "CHAT_MSG_COMBAT_XP_GAIN" then
		OnKill(...)
	elseif event == "PLAYER_XP_UPDATE" then
		local unit = ...
		if unit == nil or unit == "player" then OnXP() end
	elseif event == "PLAYER_MONEY" then
		OnMoney()
	elseif event == "QUEST_TURNED_IN" then
		G:Count("quests", 1)
		QueueCheck()
	elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
		Visit()
		EnterInstance()
		QueueCheck()
	elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
		Visit()
		KeepRun()
		QueueCheck()
	else
		QueueCheck()
	end
end)

G.EVENTS = { "CHAT_MSG_COMBAT_XP_GAIN", "PLAYER_XP_UPDATE", "PLAYER_MONEY", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP",
	"PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "BAG_UPDATE_DELAYED",
	"SKILL_LINES_CHANGED", "UPDATE_FACTION", "QUEST_LOG_UPDATE" }

A:AddPart("goals", {
	order = 30,
	start = function()
		for _, event in ipairs(G.EVENTS) do events:RegisterEvent(event) end
		xpNow, xpMax = ReadXP()
		moneyNow = Number(Call(rawget(_G, "GetMoney")))
		if J.RegisterCallback then
			J.RegisterCallback(G, "Changed", function(_, ids)
				if type(ids) == "table" and (ids.attunements or ids.lootguide or ids.instances or ids.characters) then QueueCheck() end
			end)
		end
		C_Timer.After(1, function()
			Visit()
			G:Check()
		end)
	end,
	stop = function()
		events:UnregisterAllEvents()
		if J.UnregisterCallback then J.UnregisterCallback(G, "Changed") end
		xpNow, xpMax, moneyNow = nil, nil, nil
	end,
})
