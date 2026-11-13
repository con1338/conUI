-- EldoUI My Adventure: a dungeon's history, on the Dungeons tab of
-- the Journal window (a History tab beside Bosses and Quests on every
-- instance page) and as the dungeon page of Places.
--
--   Bosses 7   Quests 3/9   History 3
--   First came here October 3. 3 runs, 2h 05m inside.
--   +------------------------------------------------------------------+
--   |  3        2h 05m      38m       41m       4 / 6       2          |
--   |  runs     inside      fastest   median    bosses      companions |
--   +------------------------------------------------------------------+
--   BOSSES  4 ------------------------------------------------------- v
--   | [skull] Edwin VanCleef   First beaten Oct 3 · 3 kills           |
--   RUNS  3 --------------------------------------------------------- v
--   | [key] Run 3 · 42m inside · 4 bosses          With Aria, Tom  Oct 9 |
--   NOT YET  5 ------------------------------------------------------ v
--   | Cookie, Captain Greenskin (never beaten here)                    |
--   | The Defias Brotherhood (a quest for this dungeon)                |
--
-- Runs come from the journal's own runs (Runs.lua, copied from what the
-- Instances recorder saw: enter and leave, the same-run merge, XP, kills,
-- gold, the group and the loot rolls), a page of 100 at a time with the
-- tally from its index, so a long history opens as fast as a short one;
-- bosses from the journal's own
-- first kills (ENCOUNTER_END and BOSS_KILL by encounter id), companions
-- from the fellowship and the run's group, "Not yet" from the Loot Guide's
-- boss list, the dungeon's quests (your status from the game) and the
-- attunements inside (EldoUI.Attunements). Nothing is guessed: a dungeon
-- you entered before the journal or Instances kept runs says so.
--
-- API (A.History):
--   H.Dungeons([charKey])   every dungeon and raid you entered:
--                           { name, key, kind, first, last, runs, inside,
--                             bossesBeaten, icon }
--   H.IsDungeon(name)       the name is one of them
--   H.Key(name[, instanceID])  the Loot Guide's instance key, or nil
--   H.Runs(name[, charKey[, count]]) the newest runs (one page unless
--                           count): { id, jid, place, enter, leave, duration,
--                           level, bosses, xp, money, kills, with, record }
--   H.RunsWith(key[, charKey[, count]]) a companion's newest runs
--   H.RunPlaces(name[, count]), H.RunPlacesWith(key[, count])  places in
--                           the journal's list, newest first, and the total
--   H.Run(place)            one run, read from the list
--   H.RunRows(listKey, places, total, make, redraw)  ledger rows of runs:
--                           the first built now, the rest as they scroll
--                           into view, "Show earlier runs" for the next page
--   H.Drops(run), H.LootTip(tooltip, run), H.RollsLine(drop)  loot rolls
--   H.Bosses(name, key)     beaten { name, first, kills }, total, notYet names
--   H.View(name, opts)      title, sentence, list items, header actions
--
-- Portions adapted from Forever Journal by Ugge Zen, MIT License (see
-- THIRD_PARTY_NOTICES.md): the dungeon page with its tally, bosses and
-- runs, and their texts.
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
local LG = E.LootGuide
local K = E.AdventureKit
local T = E.tokens
local Fmt = A.Fmt
local LP = A.LogPages

local H = {}
A.History = H

local DUNGEON_ICON = "Interface\\Icons\\INV_Misc_Key_03"
local BOSS_ICON = J.ICON and J.ICON.boss or "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local NOT_YET_QUESTS = 10

local Text = LP.Text

local function Fold(text)
	return (E:FoldText(tostring(text or "")):gsub("^the ", ""):gsub(" ", ""))
end

---------------------------------------------------------------------------
-- Instance keys
---------------------------------------------------------------------------
local keyCache = {}

function H.Key(name, instanceID)
	if not (LG and LG.Catalog) then return nil end
	local cacheKey = tostring(name) .. "|" .. tostring(instanceID)
	if keyCache[cacheKey] ~= nil then return keyCache[cacheKey] or nil end
	local found
	local folded = Fold(name)
	for _, info in ipairs(LG:Catalog()) do
		if (instanceID and info.map == instanceID) or (folded ~= "" and Fold(info.name) == folded) then
			found = info.key
			break
		end
	end
	if not found and type(name) == "string" and LG.FindInstance then found = LG:FindInstance(name) end
	keyCache[cacheKey] = found or false
	return found
end

LG:On("adventure-history", function(changed)
	if changed.data then wipe(keyCache) end
end)

---------------------------------------------------------------------------
-- Runs (the journal's own runs, Runs.lua) and first visits (the journal)
---------------------------------------------------------------------------
local function Store()
	return A.Runs
end

-- Runs the Instances log closed since the journal last looked come in
-- first (one look at the log's newest run; nothing when there is none).
local function Sync(charKey)
	local R = Store()
	local M = E.Instances
	if not (R and R.CatchUp and M and M.Store) or (charKey and charKey ~= E.charKey) or not J:Recording() then return end
	local unit = R:Store()
	local ok, store = pcall(M.Store, M)
	local newest = ok and type(store) == "table" and type(store.runs) == "table" and store.runs[1]
	if unit and type(newest) == "table" and type(newest.id) == "number" and newest.id > (tonumber(unit.lastSrc) or 0)
		and type(newest.leave) == "number" then
		R:CatchUp()
	end
end
H.Sync = Sync

-- A journal run in the shape the pages use: { id (the Instances run it
-- came from, else the journal's), jid, place, instance, enter, leave,
-- duration, level, leaveLevel, bosses, xp, money, kills, with = { keys },
-- kind, instanceID, record }.
local function Shape(unit, run, place)
	local R = Store()
	local enter, leave = tonumber(run.t), tonumber(run.leave)
	local with = R.MemberKeys(unit, run)
	table.sort(with)
	local facts = R.Facts(unit, run)
	return { id = run.src or run.id, jid = run.id, place = place, instance = R.Str(unit, run.inst), enter = enter or 0, leave = leave,
		duration = enter and leave and leave > enter and leave - enter or nil, level = facts.level, leaveLevel = facts.levelOut,
		bosses = facts.bosses or 0, xp = facts.xp, money = facts.money, kills = facts.kills,
		with = with, kind = facts.kind, instanceID = facts.instanceID, record = run }
end

-- The run at a place of the journal's list, shaped (nil when gone).
function H.Run(place, charKey)
	local R = Store()
	local unit = R and R:Store(charKey)
	local run = unit and R:Get(place, charKey)
	return run and Shape(unit, run, place) or nil
end

-- The newest `count` places of a list of places (an index entry).
local function Newest(places, count)
	local R = Store()
	return R and R:Newest(places, count) or {}
end

-- An instance's runs, newest first: the places of the newest `count`
-- (default one page) and how many there are. Nothing is read yet.
function H.RunPlaces(name, count, charKey)
	local R = Store()
	if not R then return {}, 0 end
	Sync(charKey)
	local places = R:PlacesOf(name, charKey)
	return Newest(places, count or R.PAGE), #places
end

-- A companion's runs, newest first, the same way.
function H.RunPlacesWith(key, count, charKey)
	local R = Store()
	if not (R and type(key) == "string") then return {}, 0 end
	Sync(charKey)
	local places = R:RunsWith(key, charKey)
	return Newest(places, count or R.PAGE), #places
end

-- The runs themselves (newest first, up to `count`).
function H.Runs(name, charKey, count)
	local out = {}
	for _, place in ipairs((H.RunPlaces(name, count, charKey))) do out[#out + 1] = H.Run(place, charKey) end
	return out
end

function H.RunsWith(key, charKey, count)
	local out = {}
	for _, place in ipairs((H.RunPlacesWith(key, count, charKey))) do out[#out + 1] = H.Run(place, charKey) end
	return out
end

-- Runs per companion key (every run, every instance), from the index.
function H.RunCounts(charKey)
	local R = Store()
	local counts = {}
	if not R then return counts end
	Sync(charKey)
	local idx = R:Index(charKey)
	for key, places in pairs(idx and idx.with or {}) do counts[key] = #places end
	return counts
end

-- Every dungeon and raid you entered, from the index's tally of each
-- instance, the journal's first visits and first kills (cached per
-- revision; no run is read beyond the first and last of each instance).
local dungeonCache = {}

function H.Dungeons(charKey)
	charKey = charKey or E.charKey
	local rec = J:Char(charKey)
	local R = Store()
	Sync(charKey)
	local unit = R and R:Store(charKey)
	local idx = unit and R:Index(charKey)
	local sig = ("%s|%s|%s|%s|%s"):format(tostring(rec and rec.rev), tostring(J:Rev(charKey)), tostring(unit),
		tostring(unit and unit.rev), tostring(idx ~= nil))
	local cached = dungeonCache[charKey]
	if cached and cached.sig == sig then return cached.list end
	local byName, list = {}, {}
	local function Entry(name)
		name = Text(name)
		if not name then return nil end
		local entry = byName[name]
		if not entry then
			entry = { name = name, runs = 0, inside = 0, bossesBeaten = 0 }
			byName[name] = entry
			list[#list + 1] = entry
		end
		return entry
	end
	for inst, places in pairs(idx and idx.inst or {}) do
		local entry = Entry(unit.strings[inst])
		local agg = idx.agg and idx.agg[inst]
		local first, last = places[1] and R:Get(places[1], charKey), places[#places] and R:Get(places[#places], charKey)
		if entry and first then
			entry.runs = agg and agg.n or #places
			entry.inside = agg and agg.inside or 0
			if tonumber(first.t) then entry.first = math.min(entry.first or first.t, first.t) end
			entry.last = math.max(entry.last or 0, tonumber(last.t) or 0)
			local lastFacts = R.Facts(unit, last)
			entry.instanceID = lastFacts.instanceID or R.Facts(unit, first).instanceID
			entry.kind = entry.kind or (lastFacts.kind == "raid" and "raid" or "dungeon")
		end
	end
	for name, first in pairs(rec and type(rec.instancesSeen) == "table" and rec.instancesSeen or {}) do
		local entry = Entry(name)
		if entry and tonumber(first) then entry.first = math.min(entry.first or first, first) end
	end
	for _, boss in pairs(rec and type(rec.bosses) == "table" and rec.bosses or {}) do
		local entry = type(boss) == "table" and Entry(boss.instance)
		if entry then
			entry.bossesBeaten = entry.bossesBeaten + 1
			if tonumber(boss.first) then entry.first = math.min(entry.first or boss.first, boss.first) end
		end
	end
	for _, row in ipairs(J:RowsOfKind(charKey, { dungeon = true, raid = true })) do
		local entry = Entry(row.instance or row.zone)
		if entry and row.t then
			entry.first = math.min(entry.first or row.t, row.t)
			entry.kind = entry.kind or row.kind
		end
	end
	for _, entry in ipairs(list) do
		entry.key = H.Key(entry.name, entry.instanceID)
		local info = entry.key and LG:InstanceInfo(entry.key)
		if info then entry.kind = info.kind end
		entry.kind = entry.kind or "dungeon"
		entry.icon = entry.key and LG:InstanceArt(entry.key) or DUNGEON_ICON
	end
	table.sort(list, function(a, b)
		if (a.first or 0) ~= (b.first or 0) then return (a.first or 0) < (b.first or 0) end
		return a.name < b.name
	end)
	-- A list made while the index was rebuilt is not kept.
	if idx or not (R and R:Updating(charKey)) then dungeonCache[charKey] = { sig = sig, list = list } end
	return list
end

function H.IsDungeon(name)
	for _, entry in ipairs(H.Dungeons()) do
		if entry.name == name then return true end
	end
	return false
end

local function DungeonEntry(name)
	for _, entry in ipairs(H.Dungeons()) do
		if entry.name == name then return entry end
	end
end

---------------------------------------------------------------------------
-- Bosses
---------------------------------------------------------------------------
function H.Bosses(name, key)
	local rec = J:Char()
	local beaten, seen = {}, {}
	for encounter, boss in pairs(rec and type(rec.bosses) == "table" and rec.bosses or {}) do
		if type(boss) == "table" and boss.instance == name and Text(boss.name) then
			beaten[#beaten + 1] = { name = boss.name, first = tonumber(boss.first), kills = tonumber(boss.kills) or 1, encounter = encounter }
			seen[Fold(boss.name)] = true
		end
	end
	table.sort(beaten, function(a, b)
		if (a.first or 0) ~= (b.first or 0) then return (a.first or 0) < (b.first or 0) end
		return a.name < b.name
	end)
	local total, notYet = nil, {}
	if key and LG.InstanceLoot then
		local ok, loot = pcall(LG.InstanceLoot, LG, key)
		local list = ok and type(loot) == "table" and loot.bosses or {}
		local count = 0
		for _, boss in ipairs(list) do
			if not boss.rare then
				count = count + 1
				if not seen[Fold(boss.name)] then notYet[#notYet + 1] = boss.name end
			end
		end
		if count > 0 then total = math.max(count, #beaten) end
	end
	return beaten, total, notYet
end

---------------------------------------------------------------------------
-- Names of companions, in their class colors
---------------------------------------------------------------------------
local function Colored(key)
	local rec = J:Char()
	local fellow = rec and type(rec.fellows) == "table" and rec.fellows[key]
	local name = type(fellow) == "table" and Text(fellow.name) or key
	local color = type(fellow) == "table" and LP.ClassColor(fellow.class)
	if color then return E:TokenHex(color) .. name .. "|r" end
	return name
end
H.Colored = Colored

local function Names(keys, max)
	max = max or 4
	local parts = {}
	for index, key in ipairs(keys) do
		if index > max then
			parts[#parts + 1] = (L["%d more"]):format(#keys - max)
			break
		end
		parts[#parts + 1] = Colored(key)
	end
	return table.concat(parts, ", ")
end
H.Names = Names

---------------------------------------------------------------------------
-- Loot rolls of a run (Runs.lua: what the game showed once a roll ended)
---------------------------------------------------------------------------
-- The game's roll types, in its own order.
local ROLL_TYPES = E:TranslateValues({
	[0] = E.Key("Need"), [1] = E.Key("Need (off spec)"), [2] = E.Key("Transmog"), [3] = E.Key("Greed"), [4] = E.Key("No roll"), [5] = E.Key("Pass"),
})
H.ROLL_TYPES = ROLL_TYPES
local LOOT_TIP = 12   -- drops listed in a run's tooltip

local function Who(key, me)
	if me then return L["You"] end
	if key then return Colored(key) end
	return L["Someone"]
end

-- "Need 87", "Pass", or the number alone when the game gave no type.
local function RollText(roll)
	local kind = roll.state and ROLL_TYPES[roll.state]
	if kind and roll.roll then return ("%s %d"):format(kind, roll.roll) end
	if kind then return kind end
	if roll.roll then return tostring(roll.roll) end
	return L["No roll"]
end
H.RollText = RollText

-- The winner of a drop, or "Everyone passed".
local function WinnerText(drop)
	if drop.pass then return L["Everyone passed"] end
	return Who(drop.key, drop.me)
end
H.WinnerText = WinnerText

-- Every roll of a drop on one line; the winner's in the accent color.
local function RollsLine(drop)
	local parts = {}
	for _, roll in ipairs(drop.rolls or {}) do
		local text = ("%s: %s"):format(Who(roll.key, roll.me), RollText(roll))
		if roll.won then text = E:TextHex("accent") .. text .. "|r" end
		parts[#parts + 1] = text
	end
	return table.concat(parts, " · ")
end
H.RollsLine = RollsLine

-- The drops of a run, readable (see Runs.lua R:Loot), and how many more
-- it had than it could keep.
local function Drops(run)
	local R = Store()
	if not (R and run and run.record) then return {}, 0 end
	return R:Loot(run.record)
end
H.Drops = Drops

-- "3 drops" for a run's line, nil when it has none.
local function DropsNote(run)
	local record = run and run.record
	local count = record and type(record.loot) == "table" and #record.loot or 0
	if count == 0 then return nil end
	return E:Plural(count, "%d drop", "%d drops"):format(count)
end
H.DropsNote = DropsNote

local function LootTip(tooltip, run)
	local drops, more = Drops(run)
	if #drops == 0 then return end
	tooltip:AddLine(" ")
	tooltip:AddLine(L["Loot"], unpack(T.text.secondary))
	for index, drop in ipairs(drops) do
		if index > LOOT_TIP then
			tooltip:AddLine((L["%d more"]):format(#drops - LOOT_TIP + more), unpack(T.text.dim))
			return
		end
		local winner = WinnerText(drop)
		if not drop.pass then winner = E:TextHex("accent") .. winner .. "|r" end
		tooltip:AddDoubleLine(drop.item or L["An item"], winner, unpack(T.text.body))
		local rolls = RollsLine(drop)
		if rolls ~= "" then tooltip:AddLine(rolls, T.text.secondary[1], T.text.secondary[2], T.text.secondary[3], true) end
	end
	if more > 0 then
		tooltip:AddLine(E:Plural(more, "%d more drop was not kept.", "%d more drops were not kept."):format(more), unpack(T.text.dim))
	end
end
H.LootTip = LootTip

---------------------------------------------------------------------------
-- The view: title, sentence, list items, header actions
--   opts: from = "places" | "dungeons", redraw = fn
---------------------------------------------------------------------------
local function RunTip(run)
	return function(tooltip)
		tooltip:AddLine(("%s, %s"):format(Fmt.Day(run.enter), Fmt.Clock(run.enter)), unpack(T.text.secondary))
		if run.duration then tooltip:AddDoubleLine(L["Inside"], Fmt.Span(run.duration), unpack(T.text.body)) end
		if run.level then
			local levels = run.leaveLevel and run.leaveLevel ~= run.level and ("%d-%d"):format(run.level, run.leaveLevel) or tostring(run.level)
			tooltip:AddDoubleLine(L["Your level"], levels, unpack(T.text.body))
		end
		if run.kills and run.kills > 0 then tooltip:AddDoubleLine(L["Kills"], BreakUpLargeNumbers(run.kills), unpack(T.text.body)) end
		if run.xp and run.xp > 0 then tooltip:AddDoubleLine(L["Experience"], BreakUpLargeNumbers(run.xp), unpack(T.text.body)) end
		local money = LP.Money(run.money)
		if money then tooltip:AddDoubleLine(L["Gold"], money, unpack(T.text.body)) end
		if #run.with > 0 then tooltip:AddLine((L["With %s"]):format(Names(run.with, 10)), unpack(T.text.body)) end
		LootTip(tooltip, run)
		local source = J:Source("instances")
		if source then tooltip:AddLine((L["from %s"]):format(source.title), unpack(T.text.dim)) end
		if A:SectionShown("journey") then E:TooltipHint(tooltip, { L["Click"], L["see that day in the Journey"] }) end
	end
end

H.RunTip = RunTip

-- How many runs a list shows, per list ("dungeon:<name>", "fellow:<key>"):
-- a page more with each "Show earlier runs".
local shownRuns = {}
local EAGER = 20   -- rows built at once; the rest of a page when it scrolls into view

function H.Shown(listKey)
	local R = Store()
	return shownRuns[listKey] or (R and R.PAGE or 100)
end

function H.SetShown(listKey, count)
	shownRuns[listKey] = tonumber(count)
end

-- The ledger rows of a list of run places (newest first): the first rows
-- built now, the others only when they come on screen. make(run, position)
-- returns the row of one run. A "Show earlier runs" line follows when the
-- list has more than it shows.
function H.RunRows(listKey, places, total, make, redraw)
	local rows = {}
	for position, place in ipairs(places) do
		if position <= EAGER then
			local run = H.Run(place)
			rows[#rows + 1] = run and make(run, position) or { kind = "space", height = 1 }
		else
			rows[#rows + 1] = { kind = "ledger", lazy = function()
				local run = H.Run(place)
				return run and make(run, position) or { kind = "space", height = 1 }
			end }
		end
	end
	local out = LP.Ledger(rows)
	if total > #places then
		local R = Store()
		local step = math.min(R and R.PAGE or 100, total - #places)
		out[#out + 1] = { kind = "more", text = E:Plural(step, "Show %d earlier run", "Show %d earlier runs"):format(step),
			onClick = function()
				shownRuns[listKey] = #places + (R and R.PAGE or 100)
				if redraw then redraw() else A:MarkDirty("runs") end
			end }
	end
	local R = Store()
	if R and R:Updating() then
		out[#out + 1] = { kind = "akText", text = L["Updating the list of runs. It fills in by itself in a moment."] }
	end
	return out
end

function H.View(name, opts)
	opts = opts or {}
	local entry = DungeonEntry(name)
	local key = (entry and entry.key) or H.Key(name)
	local info = key and LG:InstanceInfo(key)
	-- The name the game showed inside (the card's title), else the catalog's.
	local title = Text(name) or (info and info.name) or tostring(name)
	local listKey = "dungeon:" .. tostring(name)
	local places, total = H.RunPlaces(name, H.Shown(listKey))
	local R = Store()
	local totals = R and R:Totals(name) or nil
	local beaten, totalBosses, notYet = H.Bosses(name, key)

	-- The sentence
	local first = entry and entry.first
	local inside = totals and totals.inside or 0
	local sentence
	if first then
		sentence = (L["First came here %s."]):format(Fmt.Long(first))
		if total > 0 then
			sentence = sentence .. " " .. LP.Count(total, "%s run", "%s runs")
			if inside > 0 then sentence = sentence .. ", " .. (L["%s inside"]):format(K.Num(Fmt.Span(inside))) end
			sentence = sentence .. "."
		end
	else
		sentence = L["You have not been inside yet."]
	end

	local items = {}
	local actions = {}
	local moments = J:ZoneCount(nil, name)
	if opts.from == "places" and key and LG:IsPageOn("journal") then
		actions[#actions + 1] = { L["Open in Dungeons"], function() LG:Open("journal", key) end,
			L["Opens this dungeon on the Dungeons tab: bosses, loot, and quests."] }
	end
	if opts.from ~= "places" and first and A:SectionShown("places") then
		actions[#actions + 1] = { L["Open in Places"], function() A:OpenSection("places", { dungeon = name }) end,
			L["Opens this dungeon among your places in My Adventure."] }
	end
	if moments > 0 and A:SectionShown("journey") then
		actions[#actions + 1] = { (L["In your journal: %d"]):format(moments), function() A:OpenSection("journey", { zone = name }) end,
			L["Opens the Journey with only the moments of this dungeon."] }
	end

	-- The tally (from the index: no run is read for it)
	if first or total > 0 or #beaten > 0 then
		local companions = totals and totals.ppl or 0
		items[#items + 1] = { kind = "akStats", stats = {
			{ total, L["runs"], nil, L["Runs recorded by the Instances module (leaving and reentering counts as the same run)."] },
			{ inside > 0 and Fmt.Span(inside) or nil, L["inside"] },
			{ totals and totals.fast and Fmt.Span(totals.fast) or nil, L["fastest"] },
			{ totals and totals.median and Fmt.Span(totals.median) or nil, L["median"] },
			{ totalBosses and ("%d / %d"):format(#beaten, totalBosses) or #beaten, L["bosses beaten"] },
			{ companions, L["companions"], nil, companions > 0 and function(tooltip)
				-- Read on hover: the companions of the newest runs.
				local set, list = {}, {}
				for _, place in ipairs(R:Newest(R:PlacesOf(name), 20)) do
					local run = H.Run(place)
					for _, who in ipairs(run and run.with or {}) do
						if not set[who] then
							set[who] = true
							list[#list + 1] = who
						end
					end
				end
				E.UIKit.TipText(tooltip, Names(list, 12))
			end or nil },
		} }
		items[#items + 1] = { kind = "space", height = 8 }
	end

	-- Bosses beaten
	local bossRows = {}
	for _, boss in ipairs(beaten) do
		local sub
		if boss.first and boss.kills > 1 then
			sub = E:Plural(boss.kills, "First beaten %s · %d kill", "First beaten %s · %d kills"):format(Fmt.Short(boss.first), boss.kills)
		elseif boss.first then
			sub = (L["Beaten %s"]):format(Fmt.Short(boss.first))
		end
		bossRows[#bossRows + 1] = { icon = BOSS_ICON, title = boss.name, sub = sub, titleRole = "head",
			time = boss.first and Fmt.Short(boss.first) or nil }
	end
	if #bossRows > 0 or first then
		local rows = #bossRows > 0 and LP.Ledger(bossRows) or { { kind = "akText", text = L["None beaten here yet."] } }
		LP.AddFold(items, "history:bosses", L["Bosses"], totalBosses and (L["%d of %d"]):format(#beaten, totalBosses) or tostring(#beaten),
			rows, true, opts.redraw)
	end

	-- Runs, newest first (a page at a time)
	if total > 0 then
		-- While the index fills in, the count is not final: the runs go by day.
		local updating = R and R:Updating()
		local rows = H.RunRows(listKey, places, total, function(run, position)
			local bits = { updating and Fmt.Day(run.enter) or (L["Run %d"]):format(total - position + 1) }
			if run.duration then bits[#bits + 1] = (L["%s inside"]):format(Fmt.Span(run.duration)) end
			if run.bosses > 0 then bits[#bits + 1] = E:Plural(run.bosses, "%d boss", "%d bosses"):format(run.bosses) end
			local sub
			if #run.with > 0 then
				sub = (L["With %s"]):format(Names(run.with))
			elseif run.level then
				sub = (L["At level %d"]):format(run.level)
			end
			local drops = DropsNote(run)
			if drops then sub = sub and (sub .. " · " .. drops) or drops end
			return { icon = entry and entry.icon or DUNGEON_ICON, title = table.concat(bits, " · "), sub = sub,
				time = Fmt.Short(run.enter), tip = RunTip(run), tipTitle = title, run = run,
				onClick = A:SectionShown("journey") and function() A:OpenSection("journey", { day = Fmt.DayKey(run.enter) }) end or nil }
		end, opts.redraw)
		LP.AddFold(items, "history:runs", L["Runs"], tostring(total), rows, true, opts.redraw)
	elseif R and R:Updating() then
		LP.AddFold(items, "history:runs", L["Runs"], "", { { kind = "akText",
			text = L["Updating the list of runs. It fills in by itself in a moment."] } }, true, opts.redraw)
	elseif first then
		LP.AddFold(items, "history:runs", L["Runs"], "0", { { kind = "akText",
			text = J:SourceLive("instances") and L["No run recorded yet. Your next one is written down with its time, bosses, and company."]
				or L["Runs are recorded by Instances. Turn on Instances, or \"Use the Characters and Instances records\" in My Adventure."] } },
			true, opts.redraw)
	end

	-- Not yet: bosses, quests, attunement steps
	local notRows = {}
	for _, boss in ipairs(notYet) do
		notRows[#notRows + 1] = { kind = "line", icon = BOSS_ICON, text = boss, time = L["never beaten"],
			onClick = key and LG:IsPageOn("journal") and function() LG:Open("journal", { key = key, mode = "bosses" }) end or nil }
	end
	if key and LG.InstanceQuests then
		local ok, quests = pcall(LG.InstanceQuests, LG, key)
		local shown = 0
		for _, quest in ipairs(ok and quests or {}) do
			if quest.status ~= "done" and quest.status ~= "notforyou" and shown < NOT_YET_QUESTS then
				local data = LG:Quest(quest.id)
				local questTitle = data and Text(data.title) or (L["Quest %d"]):format(quest.id)
				local status = quest.status == "turnin" and L["ready to hand in"] or quest.status == "active" and L["in your log"]
					or quest.status == "locked" and L["needs an earlier step"] or quest.status == "low" and L["too low for it"]
					or L["not done"]
				notRows[#notRows + 1] = { kind = "line", icon = J.ICON.quest, text = questTitle, time = status,
					onClick = LG:IsPageOn("journal") and function() LG:Open("journal", { key = key, quest = quest.id }) end or nil }
				shown = shown + 1
			end
		end
	end
	local At = E.Attunements
	if key and At and At.ForInstance and At.Running and At:Running() then
		local ok, entries = pcall(At.ForInstance, At, key)
		for _, entryKey in ipairs(ok and entries or {}) do
			local done, steps = At:Progress(entryKey)
			if steps and steps > 0 and done < steps then
				notRows[#notRows + 1] = { kind = "line", icon = J.ICON.attune, text = At:Name(entryKey),
					time = E:Plural(steps, "%d of %d step", "%d of %d steps"):format(done, steps),
					onClick = function() LG:Open("attune", { key = entryKey }) end }
			end
		end
	end
	if #notRows > 0 then
		LP.AddFold(items, "history:notyet", L["Not yet"], tostring(#notRows), notRows, true, opts.redraw)
	end
	return title, sentence, items, actions
end

---------------------------------------------------------------------------
-- The History tab on the Dungeons tab's instance pages
---------------------------------------------------------------------------
local function BuildTab(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame.sentence = K.Text(frame, K.size.label, "LEFT", "body")
	frame.sentence:SetPoint("TOPLEFT", 0, -2)
	frame.sentence:SetWordWrap(true)
	frame.links = {}
	frame.list = K.CreateJournalList(frame, { empty = { L["No runs here yet"], "", DUNGEON_ICON } })
	frame.list:SetPoint("TOPLEFT", 0, -28)
	frame.list:SetPoint("BOTTOMRIGHT")
	return frame
end

local function LinkButton(frame, index)
	local link = frame.links[index]
	if link then return link end
	link = CreateFrame("Button", nil, frame)
	link:SetHeight(16)
	link.text = K.Text(link, K.size.small, "RIGHT", "secondary")
	link.text:SetPoint("RIGHT")
	link:SetScript("OnEnter", function(self) K.Paint(self.text, "accent") end)
	link:SetScript("OnLeave", function(self) K.Paint(self.text, "secondary") end)
	frame.links[index] = link
	return link
end

local function DrawTab(frame, instanceKey)
	if not A:Running() then return end
	local info = LG:InstanceInfo(instanceKey)
	local name = info and info.name or instanceKey
	-- The journal knows the dungeon by the name the game gave it inside.
	for _, entry in ipairs(H.Dungeons()) do
		if entry.key == instanceKey then name = entry.name end
	end
	frame.key, frame.name = instanceKey, name
	local _, sentence, items, actions = H.View(name, { from = "dungeons", redraw = function() DrawTab(frame, instanceKey) end })
	frame.sentence:SetText(sentence)
	local anchor
	local reserve = 0 -- the room the links take at the right, with their gaps
	for index = 1, math.max(#frame.links, #actions) do
		local data = actions[index]
		local link = LinkButton(frame, index)
		link:SetShown(data ~= nil)
		if data then
			link.text:SetText(data[1])
			link:SetWidth(math.ceil(link.text:GetStringWidth()) + 2)
			E:PadHitRect(link, 4)
			link:SetScript("OnClick", data[2])
			LG.Kit.Tooltip(link, data[1], data[3])
			link:ClearAllPoints()
			if anchor then link:SetPoint("RIGHT", anchor, "LEFT", -12, 0) else link:SetPoint("TOPRIGHT", 0, -2) end
			anchor = link
			reserve = reserve + link:GetWidth() + 12
		end
	end
	frame.sentence:ClearAllPoints()
	frame.sentence:SetPoint("TOPLEFT", 0, -2)
	frame.sentence:SetPoint("TOPRIGHT", -(anchor and reserve or 12), -2)
	frame.items = items
	frame.list:SetEmpty(L["No runs here yet"], L["Each run you make here is written down with its time, bosses, and company."], DUNGEON_ICON)
	frame.list:SetData(items, frame.drawnKey == instanceKey)
	frame.drawnKey = instanceKey
end
H.DrawTab = DrawTab

local P = LG.PageKit
if P and P.AddInstanceMode then
	P.AddInstanceMode("history", {
		label = "History",
		tip = Key("Your runs here: first visit, time inside, bosses beaten, who came along, and what is still to do."),
		order = 30,
		shown = function() return A:Running() end,
		count = function(instanceKey)
			if not A:Running() then return nil end
			for _, entry in ipairs(H.Dungeons()) do
				if entry.key == instanceKey then return entry.runs > 0 and entry.runs or nil end
			end
			return nil
		end,
		build = BuildTab,
		draw = DrawTab,
	})
end

-- A dungeon row of the journal opens its History tab (or its place page
-- when the Dungeons tab is off).
J:RegisterAddress("instance", function(id)
	id = tostring(id)
	local key = H.Key(id) or (LG.FindInstance and LG:FindInstance(id))
	if key and LG:IsPageOn("journal") and LG:InstanceInfo(key) then
		LG:Open("journal", { key = key, mode = "history" })
		return true
	end
	if A:SectionShown("places") and H.IsDungeon(id) then return A:OpenSection("places", { dungeon = id }) end
	return false
end)
