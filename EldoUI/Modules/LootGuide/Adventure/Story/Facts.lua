-- Story facts: typed records compiled from the journal. Text is never
-- stored: tone, wording and grammar fixes rewrite the whole book without
-- touching saved data.
--
-- A fact (never saved; rebuilt from the input):
--   { id = "ev:1832", kind = "boss", class = "T"|"G"|"D"|"R", t = time or nil,
--     l = level, z = zone, s = subzone, v = { slot values }, src = source id,
--     link = { page, key, tab }, from = { ids } (D facts), keep = bool,
--     flags = { first, keep, slow, fast, deathstreak, ... } }
--
-- The input ("story input") is a plain table in the journal store's shape,
-- unpacked. The Adventure store builds it (E.Journal:StoryInput(charKey))
-- in this shape:
--   charKey, salt, now, level (current), rev
--   me        = { name = "Hedda Stonebrew", first = "Hedda", race, class, faction }
--   started   = time, startedLevel = 14, startedZone = "Loch Modan"
--   levels[n] = { at = time reached, zone = zone reached in, time = seconds played
--                 at level n, kills, quests, deaths, deathZones = { [zone] = n },
--                 zones = { [zone] = seconds }, earned = copper, played = /played at ding }
--   events    = { { seq, t, kind, l, z, s, keep, v = { ... } } }  -- journal rows
--   runs      = { { id, instance, kind = "dungeon"|"raid"|"pvp", enter, leave, level,
--                   with = { names }, extra = n unnamed, bosses, result = "win"|"loss", z, s } }
--   quests    = { { id, t, title, z, s, l, xp, money, giver, with = { names },
--                   instance = name, chain = name (set on the quest that finished it) } }
--   zones[z]  = { first, firstLevel, t = seconds, deaths, quests }
--   fellows[k]= { name, race, class, met, metLevel, metZone, metSub, time,
--                 steps = { { t, l, secs } } }
--   sessions  = { { login, logout, level, playedIn, playedOut } }
--   game      = { questsDone, questsBefore, played, playedBefore, deaths,
--                 challenges = { { name, t } } }
--   totals    = { earned = copper since the journal began }
--   sources   = { [sourceId] = { off = { { a, b } } } }   -- levels a source was off
--   rolled    = { { a, b, spells, finds } }               -- rolled-up rows (G4)
local _, E = ...
local ipairs, pairs, type, tostring, setmetatable = ipairs, pairs, type, tostring, setmetatable

E.Story = E.Story or {}
local S = E.Story
local F = {}
S.Facts = F

local SOURCE_LABEL = {
	instances = "Dungeon runs", levels = "Level times", journal = "Journal rows", quests = "Quest hand-ins",
	fellowship = "Companions", gathering = "Gathering finds", farming = "Farming sessions",
}
F.sourceLabel = SOURCE_LABEL

-- Row kinds the journal stores as events (everything else comes from the
-- structured tables: levels, runs, quests, zones, fellows, sessions, game).
local FROM_TABLES = { level = true, dungeon = false, zone = true, quest = true, run = true, met = true }

local LINKS = {
	level = { page = "journey" }, zone = { page = "places" }, dungeon = { page = "journal", tab = "history" },
	raid = { page = "journal" }, death = { page = "places" }, boss = { page = "journal", tab = "bosses" },
	raidboss = { page = "journal", tab = "bosses" }, bossagain = { page = "journal", tab = "bosses" },
	loot = { page = "item" }, gear = { page = "item" }, wish = { page = "wishlist" }, rep = { page = "reputation" },
	recipe = { page = "crafting" }, profession = { page = "crafting" }, skill = { page = "crafting" },
	mount = { page = "keepsakes" }, pet = { page = "keepsakes" }, title = { page = "keepsakes" }, respec = { page = "talents" },
	flight = { page = "map" }, hearth = { page = "map" }, goal = { page = "goals" }, note = { page = "notes" },
	run = { page = "journal", tab = "history" }, pvpwin = { page = "pvp" }, pvploss = { page = "pvp" },
	quest = { page = "quest" }, questchain = { page = "quest" }, dungeonquest = { page = "quest" }, groupquest = { page = "fellowship" },
	attunestep = { page = "attunements" }, attuned = { page = "attunements" }, challenge = { page = "legacy" },
	legacylevel = { page = "legacy" }, explored = { page = "places" }, subzone = { page = "places" },
	met = { page = "fellowship" }, together = { page = "fellowship" }, gather = { page = "places" }, farm = { page = "places" },
	rare = { page = "world" },
}

local function Copy(t)
	local out = {}
	for k, v in pairs(t or {}) do out[k] = v end
	return out
end

local function SortedKeys(t)
	local keys = {}
	for k in pairs(t or {}) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	return keys
end
F.SortedKeys = SortedKeys

-- Order facts by time (undated first), then id: the one stable order.
local function FactOrder(a, b)
	local ta, tb = a.t or -1, b.t or -1
	if ta ~= tb then return ta < tb end
	return a.id < b.id
end
F.Order = FactOrder

-- The same order for a whole list, fast: each fact gets a string key (the
-- zero-padded time, then the id) and the keys sort without a Lua compare
-- function. Gives exactly FactOrder's order for whole-second times.
function F.SortList(list)
	local keys, byKey = {}, {}
	local format, floor = string.format, math.floor
	for i = 1, #list do
		local fact = list[i]
		local key = format("%013d%s", floor(fact.t or -1) + 1, fact.id)
		keys[i] = key
		byKey[key] = fact
	end
	table.sort(keys)
	for i = 1, #keys do list[i] = byKey[keys[i]] end
	return list
end

local Set = {}
Set.__index = Set
F.SetMeta = Set

function Set:Add(fact)
	if self.byId[fact.id] then return self.byId[fact.id] end
	fact.flags = fact.flags or {}
	fact.v = fact.v or {}
	fact.link = fact.link or LINKS[fact.kind]
	self.list[#self.list + 1] = fact
	self.byId[fact.id] = fact
	local list = self.byKind[fact.kind]
	if not list then
		list = {}
		self.byKind[fact.kind] = list
	end
	list[#list + 1] = fact
	return fact
end

function Set:Get(id) return self.byId[id] end
function Set:Kind(kind) return self.byKind[kind] or {} end

-- Was a source recording at this level? off ranges come from the provider
-- hub's "since" (G2).
function Set:SourceOn(source, level)
	local row = self.input.sources and self.input.sources[source]
	for _, range in ipairs(row and row.off or {}) do
		if level and level >= range[1] and level <= range[2] then return false end
	end
	return true
end

-- "First" means first known (H9): the journal must have recorded since level
-- 1, and the source must not have been off at any level before this one.
function Set:FirstKnown(source, level)
	if (self.startedLevel or 1) > 1 then return false end
	local row = self.input.sources and self.input.sources[source]
	for _, range in ipairs(row and row.off or {}) do
		if not level or range[1] <= level then return false end
	end
	return true
end

-- The level a time falls in (for rows that carry no level).
function Set:LevelAt(t)
	if not t then return nil end
	local best = self.startedLevel
	for n = self.startedLevel, self.level do
		local rec = self.levels[n]
		if rec and rec.at and rec.at <= t then best = n end
	end
	return best
end

local function Names(list)
	local out = {}
	for _, name in ipairs(list or {}) do
		if type(name) == "string" and name ~= "" then out[#out + 1] = name end
	end
	return out
end

function F.Compile(input)
	input = input or {}
	local set = setmetatable({
		input = input, list = {}, byId = {}, byKind = {},
		me = input.me or {}, charKey = input.charKey or "?",
		startedLevel = input.startedLevel or 1, level = input.level or input.startedLevel or 1,
		levels = input.levels or {}, now = input.now, people = {},
	}, Set)
	local me = set.me
	if not me.first and me.name then me.first = me.name:match("^(%S+)") end

	set:Add({ id = "me", kind = "me", class = "G", v = { name = me.name, race = me.race, class = me.class, faction = me.faction } })

	-- Before the journal (G1): the game's own memory, undated (H7).
	local game = input.game or {}
	if set.startedLevel > 1 then
		set:Add({ id = "before", kind = "before", class = "G", l = set.startedLevel, z = input.startedZone,
			v = { level = set.startedLevel, zone = input.startedZone, quests = game.questsBefore, played = game.playedBefore,
				undated = true, date = input.started } })
	end

	-- Levels (CS-1 level log).
	for n = set.startedLevel + 1, set.level do
		local rec = set.levels[n]
		if rec and rec.at then
			set:Add({ id = "lv:" .. n, kind = "level", class = "T", t = rec.at, l = n, z = rec.zone, src = "levels",
				v = { level = n, zone = rec.zone, played = rec.played } })
		end
	end

	-- Places (PL-1): the first sight of every zone.
	for _, name in ipairs(SortedKeys(input.zones)) do
		local zone = input.zones[name]
		if zone.first then
			local begin = name == input.startedZone and zone.firstLevel == set.startedLevel
			set:Add({ id = "zone:" .. name, kind = "zone", class = "T", t = zone.first, l = zone.firstLevel or set:LevelAt(zone.first),
				z = name, src = "journal",
				v = { zone = name, time = zone.t, begin = begin or nil, firstKnown = set:FirstKnown("journal", zone.firstLevel) } })
		end
	end

	-- Journal rows. A "dungeon" row is skipped when the run store has that
	-- instance (the run is the better fact: duration and roster).
	local runInstances = {}
	for _, run in ipairs(input.runs or {}) do
		if run.instance then runInstances[S.Grammar.Fold(run.instance)] = true end
	end
	for i, row in ipairs(input.events or {}) do
		local kind = row.kind
		local dup = kind == "dungeon" and row.v and runInstances[S.Grammar.Fold(row.v.instance)]
		if kind and not FROM_TABLES[kind] and not dup then
			-- Rows are read, never written: only the kinds changed below get a copy.
			local v = (kind == "boss" or kind == "skill") and Copy(row.v) or row.v or {}
			local fact = { id = "ev:" .. (row.seq or i), kind = kind, class = "T", t = row.t, l = row.l or set:LevelAt(row.t),
				z = row.z, s = row.s, keep = row.keep, src = row.src or "journal", v = v }
			if kind == "boss" then
				local raid = v.raid or (S.Grammar.PlaceRow(v.instance or "") or {}).type == "raid"
				v.raid = raid or nil
				if v.first then
					fact.flags = { first = true }
					v.firstKnown = set:FirstKnown("journal", fact.l)
					if raid then fact.kind = "raidboss" end
				else
					fact.kind = "bossagain"
				end
			elseif kind == "skill" then
				v.mastered = v.mastered or nil
			elseif kind == "challenge" then
				fact.class = "G"
			end
			if fact.keep then fact.flags = fact.flags or {}; fact.flags.keep = true end
			set:Add(fact)
		end
	end

	-- Instance runs (IN-1, IN-2): the first run of an instance is its
	-- "dungeon" or "raid" fact, the rest are "run" facts.
	local runs = {}
	for _, run in ipairs(input.runs or {}) do runs[#runs + 1] = run end
	table.sort(runs, function(a, b)
		if (a.enter or 0) ~= (b.enter or 0) then return (a.enter or 0) < (b.enter or 0) end
		return tostring(a.id) < tostring(b.id)
	end)
	local seen, pvpFirst = {}, {}
	for i, run in ipairs(runs) do
		local id = "run:" .. tostring(run.id or i)
		local with = Names(run.with)
		for _, name in ipairs(with) do set.people[name] = true end
		local level = run.level or set:LevelAt(run.enter)
		local v = { instance = run.instance, duration = (run.leave and run.enter) and (run.leave - run.enter) or nil,
			with = with, extra = run.extra or 0, bosses = run.bosses, run = id }
		if run.kind == "pvp" then
			local win = run.result == "win"
			local fact = set:Add({ id = id, kind = win and "pvpwin" or "pvploss", class = "T", t = run.enter, l = level,
				z = run.instance, src = "instances", v = { battleground = run.instance, with = with, extra = run.extra or 0, honor = run.honor } })
			if win and not pvpFirst.done then pvpFirst.done = true; fact.flags.first = true end
		else
			local key = S.Grammar.Fold(run.instance)
			local kind = "run"
			if not seen[key] then
				seen[key] = true
				kind = run.kind == "raid" and "raid" or "dungeon"
				v.firstKnown = set:FirstKnown("instances", level)
				v.forever = S.Voice.IsForeverOnly(run.instance) or nil
			end
			set:Add({ id = id, kind = kind, class = "T", t = run.enter, l = level, z = run.z or run.instance, s = run.s,
				src = "instances", v = v, flags = { first = kind ~= "run" or nil } })
		end
	end

	-- Quest hand-ins (QH-1).
	local firstGroup = true
	for i, q in ipairs(input.quests or {}) do
		local id = "q:" .. tostring(q.id or i)
		local with = Names(q.with)
		for _, name in ipairs(with) do set.people[name] = true end
		local kind = (q.instance and "dungeonquest") or (#with > 0 and "groupquest") or "quest"
		local fact = set:Add({ id = id, kind = kind, class = "T", t = q.t, l = q.l or set:LevelAt(q.t), z = q.z, s = q.s,
			src = "quests", v = { quest = q.title, instance = q.instance, with = with, xp = q.xp, giver = q.giver } })
		if kind == "groupquest" and firstGroup then firstGroup = false; fact.flags.first = true end
		if q.chain then
			set:Add({ id = id .. ":chain", kind = "questchain", class = "T", t = q.t, l = fact.l, z = q.z, s = q.s,
				src = "quests", v = { chain = q.chain, quest = q.title ~= q.chain and q.title or nil } })
		end
	end

	-- Companions (FE-1).
	for _, key in ipairs(SortedKeys(input.fellows)) do
		local fe = input.fellows[key]
		if fe.name then
			set.people[fe.name] = true
			set:Add({ id = "fe:" .. key, kind = "met", class = "T", t = fe.met, l = fe.metLevel or set:LevelAt(fe.met),
				z = fe.metZone, s = fe.metSub, src = "fellowship",
				v = { fellow = fe.name, race = fe.race, class = fe.class, total = fe.time } })
			local stepIndex = 1
			for _, step in ipairs(fe.steps or {}) do
				local target = S.Tuning.companionSteps[stepIndex]
				while target and step.secs >= target do
					set:Add({ id = "fe:" .. key .. ":" .. target, kind = "together", class = "T", t = step.t, l = step.l or set:LevelAt(step.t),
						src = "fellowship", v = { fellow = fe.name, duration = target },
						flags = { trusted = target >= S.Tuning.companionTrusted or nil } })
					stepIndex = stepIndex + 1
					target = S.Tuning.companionSteps[stepIndex]
				end
			end
		end
	end

	-- Sessions (NEW recorder piece): used by Derive for gaps.
	for i, sess in ipairs(input.sessions or {}) do
		set:Add({ id = "sess:" .. i, kind = "session", class = "T", t = sess.login, l = sess.level, src = "journal",
			v = { login = sess.login, logout = sess.logout, playedIn = sess.playedIn, playedOut = sess.playedOut } })
	end

	-- Legacy challenges carry the game's own date (G).
	for i, ch in ipairs(game.challenges or {}) do
		set:Add({ id = "ch:" .. i, kind = "challenge", class = "G", t = ch.t, l = set:LevelAt(ch.t), src = "game",
			v = { challenge = ch.name } })
	end

	-- What the game counts now (G) and what the journal counted (T).
	if game.questsDone or game.deaths or game.played then
		set:Add({ id = "game", kind = "gametotals", class = "G", t = input.now, l = set.level, src = "game",
			v = { quests = game.questsDone, deaths = game.deaths, played = game.played } })
	end
	if input.totals and input.totals.earned then
		set:Add({ id = "totals", kind = "totals", class = "T", t = input.now, l = set.level, src = "journal",
			v = { earned = input.totals.earned, since = set.startedLevel } })
	end

	-- G2: a source that was off.
	for _, source in ipairs(SortedKeys(input.sources)) do
		for _, range in ipairs(input.sources[source].off or {}) do
			set:Add({ id = ("off:%s:%d"):format(source, range[1]), kind = "sourceoff", class = "T", l = range[1], src = "journal",
				v = { source = SOURCE_LABEL[source] or source, a = range[1], b = range[2] } })
		end
	end

	-- G4: rolled-up rows.
	for i, row in ipairs(input.rolled or {}) do
		set:Add({ id = "roll:" .. i, kind = "rolled", class = "T", l = row.a, src = "journal",
			v = { a = row.a, b = row.b, spells = row.spells or 0, finds = row.finds or 0 } })
	end

	F.SortList(set.list)
	F.Reindex(set)
	return set
end

-- Rebuild the per-kind lists from the sorted list (one pass, same order).
function F.Reindex(set)
	local byKind = {}
	for _, fact in ipairs(set.list) do
		local list = byKind[fact.kind]
		if not list then
			list = {}
			byKind[fact.kind] = list
		end
		list[#list + 1] = fact
	end
	set.byKind = byKind
end

-- Is this name a person the player saw while grouped (H6)?
function F.IsPerson(set, name)
	return set.people[name] == true
end
