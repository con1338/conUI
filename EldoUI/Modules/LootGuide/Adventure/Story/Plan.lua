-- Story plan: level chapters, story chapters, eras, lead picking and the
-- level river's data.
-- No text here: Render turns the plan into sentences.
--
-- Portions adapted from Forever Journal by Ugge Zen, MIT License (see THIRD_PARTY_NOTICES.md):
-- the level chapter (one chapter per level, titled by its main zone, with the
-- time, kills, quests and deaths line and the deaths-per-zone parenthesis).
local _, E = ...
local ipairs, pairs, type, tostring, setmetatable = ipairs, pairs, type, tostring, setmetatable

E.Story = E.Story or {}
local S = E.Story
local P = {}
S.Plan = P

local ROMAN = { { 1000, "M" }, { 900, "CM" }, { 500, "D" }, { 400, "CD" }, { 100, "C" }, { 90, "XC" }, { 50, "L" },
	{ 40, "XL" }, { 10, "X" }, { 9, "IX" }, { 5, "V" }, { 4, "IV" }, { 1, "I" } }
function P.Roman(n)
	local out = {}
	for _, pair in ipairs(ROMAN) do
		while n >= pair[1] do
			out[#out + 1] = pair[2]
			n = n - pair[1]
		end
	end
	return table.concat(out)
end

-- Kinds that never get a beat of their own (rows, inputs, structure).
local NO_BEAT = { me = true, session = true, ref = true, gametotals = true, totals = true, before = true, level = true,
	lvhome = true, homezone = true, chdeaths = true, chquests = true, chclose = true, eraspan = true }
P.noBeat = NO_BEAT

-- Kinds that show up as markers on the level river.
local MARKERS = { dungeon = "dungeon", run = "dungeon", runs = "dungeon", raid = "raid", raidboss = "raid",
	deathstreak = "death", flight = "flight", questchain = "quest", attuned = "attuned", mount = "keepsake",
	title = "keepsake", gap = "gap" }

local function Weight(fact)
	local w = S.Tuning.weight[fact.kind]
	if type(w) == "function" then w = w(fact) end
	return w or 0
end
P.Weight = Weight

function P.Score(fact)
	local T = S.Tuning
	local score = Weight(fact)
	if fact.flags.first or fact.flags.firstdungeon or fact.flags.firstraid or fact.flags.firstepic or fact.flags.firstmount then
		score = score + T.firstBonus
	end
	if fact.keep or fact.flags.keep then score = score + T.keepBonus end
	local q = fact.v.quality
	if (fact.kind == "loot" or fact.kind == "gear") and q and q >= 3 then score = score + (q - 3) * 10 end
	return score
end

local leadRank = {}
for i, kind in ipairs(S.Tuning.leadOrder) do leadRank[kind] = i end

local function Better(a, b)
	if a.score ~= b.score then return a.score > b.score end
	local ra, rb = leadRank[a.fact.kind] or 99, leadRank[b.fact.kind] or 99
	if ra ~= rb then return ra < rb end
	local ta, tb = a.fact.t or 0, b.fact.t or 0
	if ta ~= tb then return ta > tb end
	return a.fact.id < b.fact.id
end

-- Shown in this detail preset? (the Book follows it too)
function P.Shown(fact, preset)
	local letters = S.Tuning.presets[fact.kind]
	if not letters then return false end
	local letter = S.Tuning.presetLetter[preset or "storyteller"]
	if not letter then return true end      -- "custom" and unknown presets show every kind
	return letters:find(letter, 1, true) ~= nil
end

local function MainZone(set, n)
	return S.Derive.MainZone(set.levels[n])
end

-- A zone's share of a span of levels.
local function ZoneTimes(set, a, b)
	local times, total = {}, 0
	for n = a, b do
		local rec = set.levels[n]
		for zone, t in pairs(rec and rec.zones or {}) do
			times[zone] = (times[zone] or 0) + t
			total = total + t
		end
	end
	local best, bestT
	for _, zone in ipairs(S.Facts.SortedKeys(times)) do
		if not bestT or times[zone] > bestT then best, bestT = zone, times[zone] end
	end
	return best, bestT, total, times
end
P.ZoneTimes = ZoneTimes

local function LevelIds(set, a, b)
	local ids = {}
	for n = a, b do
		if set.byId["lv:" .. n] then ids[#ids + 1] = "lv:" .. n end
	end
	if #ids == 0 then
		local start = set.byId["zone:" .. tostring(set.input.startedZone)]
		if start then ids[1] = start.id end
	end
	return ids
end

-- Every level of a span has its level-log record.
local function Complete(set, a, b)
	for n = a, b do
		if not set.levels[n] or not set:SourceOn("levels", n) then return false end
	end
	return true
end

local function PlayedSum(set, a, b)
	-- Only a whole span has a total: a level without its time (a source was
	-- off) would make "N hours of play" a false claim.
	local sum = 0
	for n = a, b do
		local rec = set.levels[n]
		if not (rec and rec.time) then return nil end
		sum = sum + rec.time
	end
	return b >= a and sum or nil
end

-- Era edges snapped to the nearest main-zone change.
local function EraEdges(set)
	local T = S.Tuning
	local bands = T.eraBands
	local edges = { [1] = 1 }
	for i = 2, #bands - 1 do
		local e = bands[i]
		local best
		for d = 0, T.eraSnap do
			for _, cand in ipairs({ e - d, e + d }) do
				if not best and cand > set.startedLevel and cand <= set.level then
					local now, before = MainZone(set, cand), MainZone(set, cand - 1)
					if now and before and now ~= before then best = cand end
				end
			end
			if best then break end
		end
		edges[i] = best or e
	end
	edges[#bands] = bands[#bands]
	return edges
end

-- Level chapters (the Journey, one per level plus opening and closing).
local function LevelChapters(set, plan, preset)
	local byLevel = {}
	for _, fact in ipairs(set.list) do
		if fact.l then
			local list = byLevel[fact.l]
			if not list then
				list = {}
				byLevel[fact.l] = list
			end
			list[#list + 1] = fact
		end
	end
	set.byLevel = byLevel
	for n = set.startedLevel, set.level do
		local rec = set.levels[n] or {}
		local zone, zoneT = MainZone(set, n)
		if not zone then
			-- No level log here: the zone most rows at this level name, if any.
			local votes, best = {}, nil
			for _, fact in ipairs(byLevel[n] or {}) do
				local z = fact.z
				if z and S.Grammar.PlaceRow(z) and S.Grammar.PlaceRow(z).type ~= "instance" and S.Grammar.PlaceRow(z).type ~= "raid" then
					votes[z] = (votes[z] or 0) + 1
					if not best or votes[z] > votes[best] then best = z end
				end
			end
			zone = best
		end
		local chapter = { key = "lv:" .. n, level = n, zone = zone or rec.zone, rec = rec, rows = {}, now = n == set.level,
			next = set.byId["lv:" .. (n + 1)], pace = set.byId["d:pace:" .. n],
			recorded = set.levels[n] ~= nil and set:SourceOn("levels", n) }
		local candidates = {}
		for _, fact in ipairs(byLevel[n] or {}) do
			local folded = fact.flags.inStreak or (fact.kind == "level" and set.byId["d:max"] and set.byId["d:max"].l == n)
			if not folded and P.Shown(fact, preset) then chapter.rows[#chapter.rows + 1] = fact end
			if not NO_BEAT[fact.kind] and not folded and fact.kind ~= "sourceoff" then
				candidates[#candidates + 1] = { fact = fact, score = P.Score(fact) }
			end
		end
		-- The level's home zone (D): "Duskwood held most of level 24."
		local total = 0
		for _, t in pairs(rec.zones or {}) do total = total + t end
		if zone and zoneT and total > 0 and zoneT >= S.Tuning.zoneMinSeconds and zoneT / total >= 0.5 then
			local home = set:Add({ id = "p:lvhome:" .. n, kind = "lvhome", class = "D", l = n, z = zone, t = rec.at,
				from = LevelIds(set, n, n), v = { zone = zone, share = zoneT / total, level = n } })
			chapter.home = home
		end
		-- The lead: the best candidate (one pass; Better is a strict order).
		local best
		for _, entry in ipairs(candidates) do
			if not best or Better(entry, best) then best = entry end
		end
		chapter.lead = best and best.fact or nil
		local quiet = true
		for _, fact in ipairs(chapter.rows) do
			if fact.kind ~= "level" then quiet = false end
		end
		-- "A quiet chapter" only where the level was recorded at all.
		chapter.quiet = quiet and set.levels[n] ~= nil and set:SourceOn("levels", n)
		plan.levels[#plan.levels + 1] = chapter
		plan.levelByN[n] = chapter
	end
end

-- Story chapters inside one era (zone arcs).
local function SplitEra(set, a, b, breaks)
	local T = S.Tuning
	local chapters = {}
	local cur = { a = a, b = a, zone = MainZone(set, a) }
	for n = a + 1, b do
		local len = cur.b - cur.a + 1
		local brk = false
		if breaks.gap[n] then
			brk = true
		elseif len >= T.chapterMaxLevels then
			brk = true
		elseif len >= T.chapterMinLevels then
			local mz = MainZone(set, n)
			local after = n + 1 <= b and MainZone(set, n + 1) or nil
			if cur.zone and mz and mz ~= cur.zone and (n + 1 > b or after ~= cur.zone) then
				brk = true
			elseif breaks.weight[n] then
				brk = true
			end
		end
		if brk then
			chapters[#chapters + 1] = cur
			cur = { a = n, b = n, zone = MainZone(set, n) }
		else
			cur.b = n
			cur.zone = cur.zone or MainZone(set, n)
		end
	end
	chapters[#chapters + 1] = cur
	return chapters
end

local function KindCapOk(counts, kind)
	local cap = S.Tuning.kindCap[kind]
	return not cap or (counts[kind] or 0) < cap
end

-- Fill one story chapter: lead, setting, body beats, closing.
local function FillChapter(set, chapter, opts, history)
	local T = S.Tuning
	local key = chapter.key
	local a, b = chapter.a, chapter.b
	local zone, zoneT, total = ZoneTimes(set, a, b)
	chapter.zone = zone or chapter.zone
	local facts, forced = {}, {}
	local deaths = {}
	-- The facts at these levels (bucketed once by LevelChapters) and every
	-- off source.
	local pool = {}
	for _, fact in ipairs(set:Kind("sourceoff")) do pool[#pool + 1] = fact end
	for n = a, b do
		for _, fact in ipairs((set.byLevel or {})[n] or {}) do
			if fact.kind ~= "sourceoff" then pool[#pool + 1] = fact end
		end
	end
	for _, fact in ipairs(pool) do
		local l = fact.l
		if fact.kind == "sourceoff" then
			-- G2: stated in every chapter the off range overlaps, clipped to it.
			if fact.v.a <= b and fact.v.b >= a then
				forced[#forced + 1] = fact
				chapter.clips = chapter.clips or {}
				chapter.clips[fact.id] = { a = math.max(a, fact.v.a), b = math.min(b, fact.v.b) }
			end
		elseif l and l >= a and l <= b and not NO_BEAT[fact.kind] then
			if T.forced[fact.kind] then
				forced[#forced + 1] = fact
			elseif fact.kind == "death" then
				if not fact.flags.inStreak then deaths[#deaths + 1] = fact end
			elseif not fact.flags.inSeries and P.Shown(fact, opts.preset) then
				if not (opts.export and fact.kind == "guild") then facts[#facts + 1] = fact end
			elseif fact.kind == "fast" or fact.kind == "slow" or fact.kind == "deathless" or fact.kind == "questburst"
				or fact.kind == "runs" or fact.kind == "topfellow" then
				facts[#facts + 1] = fact
			end
		end
	end
	local levelIds = LevelIds(set, a, b)
	-- Plan facts (D): the chapter's home zone, deaths, quests and totals.
	-- Shares and totals only over a fully recorded span (G2).
	if zone and total > 0 and zoneT >= T.zoneMinSeconds and zoneT / total >= T.zoneShare and Complete(set, a, b) then
		chapter.home = set:Add({ id = "p:home:" .. key, kind = "homezone", class = "D", l = a, z = zone,
			t = set.byId[levelIds[1] or ""] and set.byId[levelIds[1]].t, from = levelIds,
			v = { zone = zone, share = zoneT / total, time = zoneT, a = a, b = b, most = zoneT / total >= 0.5 or nil } })
	end
	if #deaths > 0 then
		local ids, zones = {}, {}
		for _, d in ipairs(deaths) do
			ids[#ids + 1] = d.id
			if d.z then zones[d.z] = true end
		end
		local zoneList = S.Facts.SortedKeys(zones)
		facts[#facts + 1] = set:Add({ id = "p:deaths:" .. key, kind = "chdeaths", class = "D", l = deaths[#deaths].l,
			t = deaths[#deaths].t, z = #zoneList == 1 and zoneList[1] or nil, s = #deaths == 1 and deaths[1].s or nil,
			from = ids, v = { n = #deaths, zone = #zoneList == 1 and zoneList[1] or nil, subzone = #deaths == 1 and deaths[1].s or nil } })
	end
	local quests = 0
	for n = a, b do quests = quests + ((set.levels[n] or {}).quests or 0) end
	if quests >= 5 and #levelIds > 0 and Complete(set, a, b) then
		facts[#facts + 1] = set:Add({ id = "p:quests:" .. key, kind = "chquests", class = "D", l = b,
			t = set.byId[levelIds[#levelIds]].t, z = zone, from = levelIds, v = { n = quests, zone = zone } })
	end
	local played = PlayedSum(set, a, math.min(b, set.level - 1))
	if played and #levelIds > 0 then
		chapter.close = set:Add({ id = "p:close:" .. key, kind = "chclose", class = "D", l = b,
			t = set.byId[levelIds[#levelIds]].t, from = levelIds,
			v = { a = a, b = b, played = played, zone = zone, now = b == set.level or nil, level = b } })
	end

	-- Lead: the top score; a kind that led both previous chapters may not
	-- lead again (V6, REP-5), and one that led either loses weight.
	local scored = {}
	for _, fact in ipairs(facts) do
		local score = P.Score(fact)
		if history[1] == fact.kind or history[2] == fact.kind then score = score - Weight(fact) * (1 - T.leadRepeat) end
		scored[#scored + 1] = { fact = fact, score = score }
	end
	for _, fact in ipairs(forced) do scored[#scored + 1] = { fact = fact, score = P.Score(fact), forced = true } end
	table.sort(scored, Better)
	local lead
	for _, entry in ipairs(scored) do
		local twice = history[1] == entry.fact.kind and history[2] == entry.fact.kind
		if not twice and entry.score >= T.minBeatScore then
			lead = entry
			break
		end
	end
	chapter.lead = lead and lead.fact or (chapter.home or nil)
	-- Where the journal begins is always the first chapter's lead.
	for _, fact in ipairs(facts) do
		if fact.kind == "zone" and fact.v.begin then chapter.lead = fact end
	end
	-- Supporting beats.
	local budget = T.beatsPerChapter[opts.length or "standard"] or T.beatsPerChapter.standard
	local counts, body = {}, {}
	if chapter.lead then counts[chapter.lead.kind] = 1 end
	for _, entry in ipairs(scored) do
		local fact = entry.fact
		if fact ~= chapter.lead then
			if entry.forced then
				body[#body + 1] = fact
			elseif #body < budget and entry.score >= T.minBeatScore and KindCapOk(counts, fact.kind) then
				body[#body + 1] = fact
				counts[fact.kind] = (counts[fact.kind] or 0) + 1
			end
		end
	end
	-- A crossing already says where the road arrived: drop its zone fact (a
	-- zone lead gives way to its crossing).
	if chapter.lead and chapter.lead.kind == "zone" then
		for i, fact in ipairs(body) do
			if fact.kind == "crossed" and fact.from[1] == chapter.lead.id then
				table.remove(body, i)
				chapter.lead = fact
				break
			end
		end
	end
	local covered = {}
	for _, fact in ipairs(body) do
		if fact.kind == "crossed" then for _, id in ipairs(fact.from) do covered[id] = true end end
	end
	if chapter.lead and chapter.lead.kind == "crossed" then for _, id in ipairs(chapter.lead.from) do covered[id] = true end end
	for i = #body, 1, -1 do
		if covered[body[i].id] then table.remove(body, i) end
	end
	table.sort(body, S.Facts.Order)
	chapter.body = body
	chapter.setting = (chapter.home and chapter.home ~= chapter.lead) and chapter.home or nil
	-- The title place: the lead's instance, else the chapter's zone.
	local leadPlace = chapter.lead and (chapter.lead.v.instance or nil)
	if chapter.lead and (chapter.lead.kind == "pvpwin" or chapter.lead.kind == "pvploss") then leadPlace = nil end
	chapter.place = leadPlace or chapter.zone or (set.levels[a] or {}).zone or (chapter.lead and chapter.lead.z) or set.input.startedZone
	chapter.span = { a = a, b = b }
	return chapter.lead and chapter.lead.kind
end

function P.Build(set, opts)
	opts = opts or {}
	local T = S.Tuning
	local plan = { set = set, levels = {}, levelByN = {}, eras = {}, chapters = {}, river = {} }
	LevelChapters(set, plan, opts.preset)

	-- Forced breaks (gaps) and weight breaks (first dungeon, first raid,
	-- attuned, 60) by level.
	local breaks = { gap = {}, weight = {} }
	for _, fact in ipairs(set.list) do
		if fact.l then
			if fact.kind == "gap" then breaks.gap[fact.l] = true end
			if T.chapterBreakKinds[fact.kind] and Weight(fact) >= T.chapterBreakWeight and (fact.kind ~= "dungeon" or fact.flags.first) then
				breaks.weight[fact.l] = true
			end
		end
	end

	local edges = EraEdges(set)
	local numeral = 0
	local history = {}
	-- Before the journal (G1).
	if set.startedLevel > 1 then
		local before = set.byId.before
		numeral = numeral + 1
		local chapter = { key = "ch:gap", kind = "gap", numeral = P.Roman(numeral), a = 1, b = set.startedLevel - 1,
			lead = before, body = {}, span = { a = 1, b = set.startedLevel - 1 }, place = set.input.startedZone }
		local era = { key = "era:0", index = 0, a = 1, b = set.startedLevel - 1, chapters = { chapter }, gap = true }
		plan.eras[#plan.eras + 1] = era
		plan.chapters[#plan.chapters + 1] = chapter
	end
	for i = 1, #T.eraBands do
		local a = edges[i]
		local b = (edges[i + 1] or (T.eraBands[#T.eraBands] + 1)) - 1
		if i == #T.eraBands then b = math.max(a, set.level) end
		a = math.max(a, set.startedLevel)
		b = math.min(b, set.level)
		if a <= b then
			local era = { key = "era:" .. i, index = i, a = a, b = b, chapters = {} }
			for _, span in ipairs(SplitEra(set, a, b, breaks)) do
				numeral = numeral + 1
				local chapter = { key = "ch:" .. span.a, numeral = P.Roman(numeral), a = span.a, b = span.b, zone = span.zone, era = i }
				local kind = FillChapter(set, chapter, opts, history)
				history[2], history[1] = history[1], kind
				era.chapters[#era.chapters + 1] = chapter
				plan.chapters[#plan.chapters + 1] = chapter
			end
			-- The era's span fact (D) and its main zone.
			local zone, zoneT, total = ZoneTimes(set, a, b)
			local played = PlayedSum(set, a, math.min(b, set.level - 1))
			local ids = LevelIds(set, a, b)
			era.zone = zone
			if played and #ids > 0 then
				era.span = set:Add({ id = "p:era:" .. i, kind = "eraspan", class = "D", l = a, z = zone, t = set.byId[ids[1]].t,
					from = ids, v = { a = a, b = b, played = played, zone = zone, share = total > 0 and zoneT / total or nil } })
			end
			local leadBest
			for _, chapter in ipairs(era.chapters) do
				local lead = chapter.lead
				if lead and (not leadBest or P.Score(lead) > P.Score(leadBest)) then leadBest = lead end
			end
			era.lead = leadBest
			plan.eras[#plan.eras + 1] = era
		end
	end

	-- The level river: 60 levels, gaps and markers (UI-2 data).
	for n = 1, 60 do
		local rec = set.levels[n]
		local row = { level = n, time = rec and rec.time, future = n > set.level, markers = {} }
		row.recorded = n >= set.startedLevel and n <= set.level and set:SourceOn("levels", n)
		row.gap = n < set.startedLevel or (n <= set.level and not set:SourceOn("levels", n))
		local zone = MainZone(set, n)
		row.zone = zone
		row.zoneChange = n > 1 and zone ~= nil and plan.river[n - 1] and plan.river[n - 1].zone ~= nil and plan.river[n - 1].zone ~= zone
		plan.river[n] = row
	end
	for _, fact in ipairs(set.list) do
		local marker = MARKERS[fact.kind]
		if fact.kind == "loot" and (fact.v.quality or 0) >= 4 then marker = "keepsake" end
		if fact.kind == "run" and fact.flags.inSeries then marker = nil end
		if marker and fact.l and plan.river[fact.l] then
			local list = plan.river[fact.l].markers
			list[#list + 1] = { kind = marker, id = fact.id }
		end
	end
	for _, fact in ipairs(set:Kind("unrecorded")) do
		if fact.l and plan.river[fact.l] then plan.river[fact.l].unrecorded = true end
	end
	return plan
end
