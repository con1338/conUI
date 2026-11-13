-- Story export: the story as text for the Story so far page, the character
-- card, the copy box and the chat box.
--
--   X.SoFar(set, book, opts) -> sentences    the Story so far prose, in the
--                                           book's tone, every sentence
--                                           with its cites (hover, H1-H10)
--   X.Card(set, book, opts) -> card          the character card: facts only
--   X.CardText(card), X.CardMarkdown(card)   the card for the copy box
--   X.ChatLine(card) -> text                 one line for the chat box (the
--                                           player presses Enter)
--   X.BookText(book, set, opts)              the whole book as plain text
--   X.BookMarkdown(book, set, opts)          the whole book as Markdown
--   X.Plain(text)                            links and colors stripped
--
-- Rules: every sentence here cites a tracked, game or derived fact and goes
-- through the honesty checker like the book's own. Exports use the name
-- (no pronoun) and leave companion names and the guild out unless the
-- caller turns them on (opts.companions). Nothing is sent anywhere: the
-- texts go to E:ShowCopyBox or the chat edit box, and the player decides.
--
-- The story is English only: its lines skip L[] like the banks.
local _, E = ...
local ipairs, pairs, type, tostring = ipairs, pairs, type, tostring

E.Story = E.Story or {}
local S = E.Story
local X = {}
S.Export = X

X.footer = "EldoUI Journal · WoW: Forever" -- no-L
X.subtitle = "A journal of the road in WoW: Forever" -- no-L
X.toneName = { ledger = "Ledger", chronicle = "Chronicle", bard = "Bard" } -- no-L

local function G() return S.Grammar end

function X.Plain(text)
	if type(text) ~= "string" then return "" end
	return (G().StripMarkup(text):gsub("|n", "\n"))
end

---------------------------------------------------------------------------
-- Sentences
---------------------------------------------------------------------------
-- One sentence from a template whose slots are already words. A slot with
-- no value drops the variant (H1: nothing is guessed).
local function Make(tone, template, slots, cites, extra)
	local failed
	local used = {}
	local text = template:gsub("{([%w_]+)}", function(key)
		used[key] = true
		local value = slots[key]
		if value == nil or value == false then
			failed = key
			return ""
		end
		return tostring(value)
	end)
	if failed then return nil end
	local Gr = G()
	local prose = tone ~= "ledger"
	text = Gr.Clean(text, prose)
	text = Gr.Capitalize(text)
	if prose and not (text:find("[%.!%?]$") or text:find('[%.!%?]"$')) then text = text .. "." end
	return {
		text = text, skeleton = template:gsub("{[^}]+}", "§"), cites = cites, tone = tone, beat = "sofar",
		flavour = extra and extra.flavour or {}, people = extra and extra.people or {}, lead = cites[1], nouns = {},
		usesRef = (used.who or used.whom or used.whose or used.name) and true or false,
	}
end
X.Make = Make

-- The first variant that passes the honesty checker, starting at a seeded
-- place so the same journal always reads the same (until "Reshuffle").
local function Pick(ctx, key, variants, slots, cites, extra)
	if not variants or #variants == 0 then return nil end
	local n = #variants
	local seed = S.Pick.Seed(ctx.set.charKey, "sofar", key, ctx.tone, ctx.opts.salt) % n
	for step = 0, n - 1 do
		local sentence = Make(ctx.tone, variants[(seed + step) % n + 1], slots, cites, extra)
		if sentence and S.Honesty.Check(sentence, ctx.set, ctx.opts) then return sentence end
	end
	return nil
end

-- Words for the character, one set per sentence: the full name first, then
-- the pronoun (or the first name with "Name only") and the first name in
-- turn. Peek() gives the next set, Next() moves on once a sentence is used.
local function References(ctx)
	local me = ctx.set.me
	local Gr = G()
	local used = 0
	local refs = {}
	function refs.Peek()
		local k = used + 1
		local first = me.first or me.name
		if k == 1 then return { subj = me.name, poss = Gr.Possessive(me.name), obj = me.name } end
		local pronoun = Gr.Pronoun("they", ctx.opts.pronoun)
		if pronoun and k % 2 == 0 then
			return { subj = pronoun, poss = Gr.Pronoun("their", ctx.opts.pronoun), obj = Gr.Pronoun("them", ctx.opts.pronoun) }
		end
		return { subj = first, poss = Gr.Possessive(first), obj = first }
	end
	function refs.Next() used = used + 1 end
	return refs
end

-- "Dwarf Priest" (card and Ledger: each word capitalized).
local function TitleWords(text)
	return (tostring(text or ""):gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

function X.RaceClass(me)
	local V = S.Voice
	local r, c = V.RaceRow(me.race), V.ClassRow(me.class)
	local words = {}
	if r then words[#words + 1] = TitleWords(r.noun) end
	if c then words[#words + 1] = TitleWords(c.noun) end
	if #words == 0 then return nil end
	return table.concat(words, " ")
end

-- A game fact for where the character stands now (level, /played).
local function NowFact(set)
	local id = "x:now"
	if set.byId[id] then return set.byId[id] end
	local game = set.input.game or {}
	return set:Add({ id = id, kind = "now", class = "G", t = set.now, l = set.level, src = "game",
		v = { level = set.level, played = game.played } })
end

-- Zones by time, most first (zone facts with enough time there).
local function TopZones(set)
	local list = {}
	for _, fact in ipairs(set:Kind("zone")) do
		local zone = set.input.zones and set.input.zones[fact.v.zone]
		local seconds = zone and zone.t or fact.v.time
		if type(seconds) == "number" and seconds >= S.Tuning.zoneMinSeconds then
			local row = G().PlaceRow(fact.v.zone)
			if not (row and (row.type == "instance" or row.type == "raid" or row.type == "battleground")) then
				list[#list + 1] = { fact = fact, t = seconds }
			end
		end
	end
	table.sort(list, function(a, b)
		if a.t ~= b.t then return a.t > b.t end
		return a.fact.id < b.fact.id
	end)
	return list
end
X.TopZones = TopZones

local function Earliest(list)
	local best
	for _, fact in ipairs(list) do
		if not best or S.Facts.Order(fact, best) then best = fact end
	end
	return best
end

-- The finest find: kept first, then quality, then the newest.
local function BestFind(set)
	local best
	for _, fact in ipairs(set:Kind("loot")) do
		local q = fact.v.quality or 0
		if q >= S.Tuning.lootNotable and type(fact.v.item) == "string" then
			if not best then
				best = fact
			else
				local bk, fk = best.keep and 1 or 0, fact.keep and 1 or 0
				local bq = best.v.quality or 0
				if fk > bk or (fk == bk and (q > bq or (q == bq and (fact.t or 0) > (best.t or 0)))) then best = fact end
			end
		end
	end
	return best
end
X.BestFind = BestFind

local function MostRun(set)
	local best
	for _, fact in ipairs(set:Kind("runs")) do
		if not best or (fact.v.n or 0) > (best.v.n or 0) then best = fact end
	end
	return best
end
X.MostRun = MostRun

local function CurrentZone(set)
	local rec = set.levels[set.level]
	local zone = rec and S.Derive.MainZone(rec)
	if zone then return zone end
	local latest
	for _, fact in ipairs(set:Kind("zone")) do
		if not latest or (fact.t or 0) > (latest.t or 0) then latest = fact end
	end
	return latest and latest.v.zone
end

---------------------------------------------------------------------------
-- Story so far: a paragraph of facts set as prose
---------------------------------------------------------------------------
-- Variant lists per tone. Slots: {who} the subject (name, pronoun or first
-- name), {whose} its possessive, {whom} its object form. Verbs stay in the
-- past tense, so "they" and "she" read the same.
local V_OPEN = {
	chronicle = {
		begin1 = { "{name}, {desc}, set out from {zone} on {date}.", "The road of {name}, {desc}, began {zonein} on {date}." },
		beginN = { "{name}, {desc}, began this journal at level {level} {zonein}, on {date}.",
			"The journal begins on {date}, {zonein}, with {name}, {desc}, at level {level}." },
		plain = { "This is the story of {name}, {desc}.", "These pages follow {name}, {desc}." },
	},
	bard = {
		begin1 = { "{name}, {bdesc}, first took the road {zonein} on {date}.", "On {date}, {name}, {bdesc}, set out from {zone}." },
		beginN = { "The journal found {name}, {bdesc}, {zonein} at level {levelword}, on {date}.",
			"On {date}, at level {levelword}, {name}, {bdesc}, opened this journal {zonein}." },
		plain = { "Hear now of {name}, {bdesc}.", "This is the song of {name}, {bdesc}." },
	},
	ledger = {
		begin1 = { "{name} · {rc} · set out {zonein} · {short}" },
		beginN = { "{name} · {rc} · journal from level {level} {zonein} · {short}" },
		plain = { "{name} · {rc}" },
	},
}

-- "over" variants read badly with a hedged time ("Over almost three days"):
-- they carry hedge = false and are skipped then.
local V_LEVEL = {
	chronicle = {
		max = { { "Over {played} of play, {who} reached level 60, the end of the road.", hedge = false },
			"{who} reached level 60, the end of the road, after {played} of play." },
		played = { { "Over {played} of play, {who} reached level {level}.", hedge = false },
			"{who} reached level {level} in {played} of play." },
		start = { "The journal holds {played} of play so far, all at level {level}.",
			"So far the road has taken {played} of play, at level {level}." },
		level = { "{who} reached level {level}.", "The road has reached level {level} so far." },
	},
	bard = {
		max = { "{played} of play carried {whom} to sixty, the end of the road.", "At sixty, after {played} of play, the road ended for {whom}." },
		played = { "{played} of play carried {whom} to level {levelword}.", "Level {levelword} came after {played} of play." },
		start = { "The road has only begun: {played} of play, at level {levelword}." },
		level = { "The road has carried {whom} to level {levelword}.", "Level {levelword} is where the song stands." },
	},
	ledger = {
		max = { "Level 60 · {playedL} played" },
		played = { "Level {level} · {playedL} played" },
		start = { "Level {level} · {playedL} played" },
		level = { "Level {level}" },
	},
}

local V_PLACES = {
	chronicle = {
		two = { "{who} spent the most time {z1in}, then {z2in}.", "{z1start} and {z2} took the most time on the road." },
		one = { "{who} spent the most time {z1in}.", "{z1start} took the most time on the road." },
	},
	bard = {
		two = { "Of all the lands, {z1} and {z2} kept {whom} longest.", "The longest days were spent {z1in}, and then {z2in}." },
		one = { "Of all the lands, {z1} kept {whom} longest.", "The longest days were spent {z1in}." },
	},
	ledger = {
		two = { "Most time: {z1start} {t1} · {z2start} {t2}" },
		one = { "Most time: {z1start} {t1}" },
	},
}

local V_DUNGEONS = {
	chronicle = {
		known = { "{who} entered {count}, the first of them {first} at level {level}.",
			"{who} entered {count}; {first} came first, at level {level}." },
		journal = { "{who} entered {count} in the journal, the first of them {first} at level {level}.",
			"Of the {countword} in the journal, {first} came first, at level {level}." },
		one = { "{who} entered {first} at level {level}, the one dungeon in the journal so far." },
	},
	bard = {
		known = { "{countstart} opened their doors to {whom}, and {first} was the first, at level {levelword}.",
			"Through {count} the road went, {first} the first of them, at level {levelword}." },
		journal = { "{countstart} in the journal opened their doors to {whom}; {first} came first, at level {levelword}." },
		one = { "Of dungeons, the journal holds one so far: {first}, at level {levelword}." },
	},
	ledger = {
		known = { "Dungeons: {n} · first {firsthead} at level {level}" },
		journal = { "Dungeons in the journal: {n} · first {firsthead} at level {level}" },
		one = { "Dungeons in the journal: 1 · {firsthead} at level {level}" },
	},
}

-- Item names keep their own number ("Glowing Magical Bracelets"), so the
-- verb never agrees with the item.
local V_FIND = {
	chronicle = { any = { "Of all the finds in the journal, the finest is {item}.", "The finest find in the journal is {item}." } },
	bard = {
		kept = { "Of all the treasure, the most prized is {item}.", "No find is prized above {item}." },
		any = { "Of all the treasure in the journal, the brightest is {item}." },
	},
	ledger = { any = { "Best find: {item}" } },
}

local V_FELLOW = {
	chronicle = { any = { "{who} traveled most with {fellow}, {duration} together.",
		"{fellow} shared more of the road with {whom} than anyone else: {duration}." } },
	bard = {
		trusted = { "{fellow}, an old friend of the road, shared {duration} of it.", "The trusted {fellow} walked beside {whom} for {duration}." },
		any = { "{fellow} shared {duration} of the road." },
	},
	ledger = { any = { "Most time together: {fellow} {durationL}" } },
}

-- Variants as plain strings (a { text, hedge = false } entry is dropped
-- while the time is hedged).
local function Variants(list, hedged)
	local out = {}
	for _, entry in ipairs(list or {}) do
		if type(entry) == "string" then
			out[#out + 1] = entry
		elseif not (hedged and entry.hedge == false) then
			out[#out + 1] = entry[1]
		end
	end
	return out
end

local function Hedged(text)
	return type(text) == "string" and (text:find("^almost ") or text:find("^a little ")) and true or false
end

-- opts as E.Story:Build (tone, pronoun, companions, salt).
function X.SoFar(set, book, opts)
	opts = opts or {}
	local tone = opts.tone or (book and book.tone) or "chronicle"
	local Gr = G()
	local savedStyle = Gr.style
	Gr.style = tone
	local ctx = { set = set, opts = opts, tone = tone }
	local out = {}
	local me = set.me
	if not me.name then
		Gr.style = savedStyle
		return out
	end
	local refs = References(ctx)
	-- A sentence that named the character moves the name rhythm on.
	local function Add(sentence)
		if not sentence then return end
		out[#out + 1] = sentence
		if sentence.usesRef then refs.Next() end
	end
	local function Who(slots)
		local ref = refs.Peek()
		slots.who, slots.whose, slots.whom = ref.subj, ref.poss, ref.obj
		return slots
	end
	local function Lvl(n) return tone == "bard" and Gr.Number(n, "bard") or Gr.Digits(n) end

	-- 1. Who, and where the road began.
	local begin = set.byId["zone:" .. tostring(set.input.startedZone)]
	if begin and not begin.v.begin then begin = nil end
	local meFact = set.byId.me
	local slots = { name = me.name, desc = S.Voice.Describe(me.race, me.class), rc = X.RaceClass(me) }
	local extra
	if tone == "bard" then
		slots.bdesc = S.Voice.DescribeBard(me.race, me.class)
		extra = { flavour = { { kind = "race", word = me.race } } }
	end
	local bank = V_OPEN[tone] or V_OPEN.chronicle
	local opened
	if begin then
		slots.zone = Gr.Place(begin.v.zone, "bare")
		slots.zonein = Gr.Place(begin.v.zone, "auto")
		slots.date = Gr.Date(begin.t)
		slots.short = Gr.Date(begin.t, "short")
		slots.level = Gr.Digits(begin.l or set.startedLevel)
		slots.levelword = Gr.Number(begin.l or set.startedLevel, "bard")
		opened = Pick(ctx, "open", set.startedLevel > 1 and bank.beginN or bank.begin1, slots, { begin.id, meFact.id }, extra)
	end
	opened = opened or Pick(ctx, "open", bank.plain, slots, { meFact.id }, extra)
	Add(opened)

	-- 2. The level and the time it took.
	local now = NowFact(set)
	local played = now.v.played
	bank = V_LEVEL[tone] or V_LEVEL.chronicle
	local max = set.byId["d:max"]
	if set.level > set.startedLevel or played then
		local cites = { now.id }
		local list = bank.level
		if played and max then
			list = bank.max
			cites[#cites + 1] = max.id
		elseif played and set.level == set.startedLevel then
			list = bank.start
		elseif played then
			list = bank.played
		end
		local playedText = Gr.Duration(played, tone)
		Add(Pick(ctx, "level", Variants(list, Hedged(playedText)), Who({
			level = Gr.Digits(set.level), levelword = Lvl(set.level),
			played = playedText, playedL = Gr.Duration(played, "ledger"),
		}), cites))
	end

	-- 3. Where the time went.
	local zones = TopZones(set)
	if #zones > 0 then
		bank = V_PLACES[tone] or V_PLACES.chronicle
		local z1, z2 = zones[1], zones[2]
		local s = Who({
			z1 = Gr.Place(z1.fact.v.zone, "bare"), z1in = Gr.Place(z1.fact.v.zone, "auto"), z1start = Gr.Place(z1.fact.v.zone, "start"),
			t1 = Gr.Duration(z1.t, "ledger"),
		})
		local cites = { z1.fact.id }
		if z2 then
			s.z2, s.z2in, s.z2start = Gr.Place(z2.fact.v.zone, "bare"), Gr.Place(z2.fact.v.zone, "auto"), Gr.Place(z2.fact.v.zone, "start")
			s.t2 = Gr.Duration(z2.t, "ledger")
			cites[2] = z2.fact.id
		end
		Add(Pick(ctx, "places", z2 and bank.two or bank.one, s, cites))
	end

	-- 4. Dungeons: how many, and the first.
	local dungeons = set:Kind("dungeon")
	if #dungeons > 0 then
		bank = V_DUNGEONS[tone] or V_DUNGEONS.chronicle
		local first = Earliest(dungeons)
		local cites = { first.id }
		for _, fact in ipairs(dungeons) do
			if fact ~= first then cites[#cites + 1] = fact.id end
		end
		local count = Gr.Count(#dungeons, "dungeon", tone)
		local list = #dungeons == 1 and bank.one or (first.v.firstKnown and bank.known or bank.journal)
		Add(Pick(ctx, "dungeons", list, Who({
			count = count, countstart = Gr.Capitalize(count or ""), countword = Gr.Count(#dungeons, "dungeon", "chronicle"),
			n = Gr.Digits(#dungeons),
			first = Gr.Place(first.v.instance, "bare"), firsthead = Gr.Place(first.v.instance, "head"),
			level = Gr.Digits(first.l or 0), levelword = Lvl(first.l or 0),
		}), cites))
	end

	-- 5. The finest find.
	local find = BestFind(set)
	if find then
		bank = V_FIND[tone] or V_FIND.chronicle
		local list = (find.keep and bank.kept) or bank.any
		Add(Pick(ctx, "find", list, { item = find.v.item }, { find.id }))
	end

	-- 6. The companion of the road (names only while companions are on).
	local fellow = set.byId["d:topfellow"]
	if fellow and opts.companions and fellow.v.fellow then
		bank = V_FELLOW[tone] or V_FELLOW.chronicle
		local list = (fellow.flags.trusted and bank.trusted) or bank.any
		Add(Pick(ctx, "fellow", list, Who({
			fellow = fellow.v.fellow,
			duration = Gr.Duration(fellow.v.duration, tone), durationL = Gr.Duration(fellow.v.duration, "ledger"),
		}), { fellow.id }, { people = { fellow.v.fellow } }))
	end

	-- 7. The book's own closing summary (gold earned, what the game counts).
	for _, sentence in ipairs(book and book.summary or {}) do out[#out + 1] = sentence end
	Gr.style = savedStyle
	return out
end

---------------------------------------------------------------------------
-- The character card: facts only
---------------------------------------------------------------------------
local function Chip(value, label, cites)
	return { value = value, label = label, cites = cites }
end

local KEEP_KINDS = { raidboss = 1, boss = 2, attuned = 3, loot = 4, mount = 5, title = 6, rep = 7 }

-- opts: tone, companions (off by default on the card), salt.
function X.Card(set, book, opts)
	opts = opts or {}
	local Gr = G()
	local savedStyle = Gr.style
	Gr.style = "ledger"
	local me = set.me
	local game = set.input.game or {}
	local card = { name = me.name, firstName = me.first, faction = me.faction, race = me.race, class = me.class,
		level = set.level, charKey = set.charKey, footer = X.footer, river = book and book.river, stats = {}, firsts = {},
		keepsakes = {} }
	local parts = {}
	local rc = X.RaceClass(me)
	if rc then parts[#parts + 1] = rc end
	parts[#parts + 1] = "level " .. set.level
	if game.played then parts[#parts + 1] = Gr.Duration(game.played, "ledger") .. " played" end
	card.line = table.concat(parts, " · ")
	if set.input.started then card.since = "Journal kept since " .. Gr.Date(set.input.started, "short") end -- no-L

	-- Six stat chips.
	local stats = card.stats
	local quests = game.questsDone
	if quests then stats[#stats + 1] = Chip(Gr.Digits(quests), quests == 1 and "quest" or "quests", { "game" }) end
	if game.deaths then stats[#stats + 1] = Chip(Gr.Digits(game.deaths), game.deaths == 1 and "death" or "deaths", { "game" }) end
	local dungeons = #set:Kind("dungeon")
	local runs = dungeons + #set:Kind("run")
	if dungeons > 0 then stats[#stats + 1] = Chip(Gr.Digits(dungeons), dungeons == 1 and "dungeon" or "dungeons") end
	if runs > dungeons then stats[#stats + 1] = Chip(Gr.Digits(runs), "runs") end
	local raids = #set:Kind("raid")
	if raids > 0 then stats[#stats + 1] = Chip(Gr.Digits(raids), raids == 1 and "raid" or "raids") end
	local totals = set.byId.totals
	if totals and (totals.v.earned or 0) >= 10000 then
		stats[#stats + 1] = Chip(Gr.Digits(math.floor(totals.v.earned / 10000)) .. "g", "earned", { "totals" })
	end
	local together = 0
	for _, fact in ipairs(set:Kind("met")) do together = together + (fact.v.total or 0) end
	if together >= 3600 then stats[#stats + 1] = Chip(Gr.Duration(together, "ledger"), "with companions") end
	while #stats > 6 do table.remove(stats) end

	-- Three firsts and mosts.
	local firsts = card.firsts
	local firstDungeon = Earliest(set:Kind("dungeon"))
	if firstDungeon then
		firsts[#firsts + 1] = { label = firstDungeon.v.firstKnown and "First dungeon" or "First dungeon in the journal",
			value = ("%s (%d)"):format(Gr.Place(firstDungeon.v.instance, "head"), firstDungeon.l or 0), cites = { firstDungeon.id } }
	end
	local zones = TopZones(set)
	if zones[1] then
		firsts[#firsts + 1] = { label = "Most time", value = ("%s (%s)"):format(Gr.Place(zones[1].fact.v.zone, "head"),
			Gr.Duration(zones[1].t, "ledger")), cites = { zones[1].fact.id } }
	end
	local most = MostRun(set)
	if most then
		firsts[#firsts + 1] = { label = "Most run", value = ("%s ×%d"):format(Gr.Place(most.v.instance, "head"), most.v.n or 0),
			cites = { most.id } }
	end

	-- Up to four keepsakes: first kills, attunements, the finest finds, mounts.
	local pool = {}
	for _, fact in ipairs(set.list) do
		local rank = KEEP_KINDS[fact.kind]
		if rank and (fact.keep or fact.flags.first or (fact.kind == "loot" and (fact.v.quality or 0) >= 4)) then
			if fact.kind ~= "boss" or fact.flags.first then pool[#pool + 1] = { fact = fact, rank = rank } end
		end
	end
	table.sort(pool, function(a, b)
		local ka, kb = a.fact.keep and 0 or 1, b.fact.keep and 0 or 1
		if ka ~= kb then return ka < kb end
		if a.rank ~= b.rank then return a.rank < b.rank end
		return S.Facts.Order(a.fact, b.fact)
	end)
	local used = {}
	for _, entry in ipairs(pool) do
		if #card.keepsakes >= 4 then break end
		local fact = entry.fact
		local text
		local v = fact.v
		if fact.kind == "raidboss" or fact.kind == "boss" then text = v.boss
		elseif fact.kind == "attuned" then text = v.instance and ("Attuned: " .. Gr.Place(v.instance, "head"))
		elseif fact.kind == "loot" then text = v.item and X.Plain(v.item)
		elseif fact.kind == "mount" then text = v.mount
		elseif fact.kind == "title" then text = v.title and Gr.Trim(v.title)
		elseif fact.kind == "rep" then text = v.faction and v.standing and (v.standing .. " with " .. v.faction) end
		if text and not used[text] then
			used[text] = true
			card.keepsakes[#card.keepsakes + 1] = { text = text, kind = fact.kind, id = fact.id, item = fact.kind == "loot" and v.item or nil,
				quality = v.quality }
		end
	end

	-- One closing line: from where the journal began to where it is now.
	local begin = set.byId["zone:" .. tostring(set.input.startedZone)]
	local nowZone = CurrentZone(set)
	local now = NowFact(set)
	if begin and nowZone then
		local tone = opts.tone or "chronicle"
		local from, to = Gr.Place(begin.v.zone, "bare"), Gr.Place(nowZone, "bare")
		local played = now.v.played and Gr.Duration(now.v.played, tone == "ledger" and "ledger" or "chronicle")
		local template
		if from ~= to then
			template = played and "From {from} to {to}, in {played} of play." or "From {from} to {to}."
			if tone == "ledger" then template = played and "{fromhead} to {to} · {played} played" or "{fromhead} to {to}" end
		elseif played then
			template = tone == "ledger" and "{fromhead} · {played} played" or "All of it {fromin}, in {played} of play so far."
		end
		if template then
			local sentence = Make(tone, template, { from = from, to = to, played = played, fromhead = Gr.Place(begin.v.zone, "head"),
				fromin = Gr.Place(begin.v.zone, "auto") }, { begin.id, now.id })
			if sentence and S.Honesty.Check(sentence, set, { companions = false }) then card.closing = sentence.text end
		end
	end
	Gr.style = savedStyle
	return card
end

local function StatLine(card)
	local bits = {}
	for _, chip in ipairs(card.stats) do bits[#bits + 1] = chip.value .. " " .. chip.label end
	return table.concat(bits, " · ")
end
X.StatLine = StatLine

local function FirstsLine(card)
	local bits = {}
	for _, entry in ipairs(card.firsts) do bits[#bits + 1] = entry.label .. ": " .. entry.value end
	return table.concat(bits, " · ")
end
X.FirstsLine = FirstsLine

local function KeepsakeLine(card)
	local bits = {}
	for _, entry in ipairs(card.keepsakes) do bits[#bits + 1] = entry.text end
	return table.concat(bits, " · ")
end
X.KeepsakeLine = KeepsakeLine

function X.CardText(card)
	local lines = { card.name or "" }
	if card.line then lines[#lines + 1] = card.line end
	if card.since then lines[#lines + 1] = card.since end
	if #card.stats > 0 then lines[#lines + 1] = StatLine(card) end
	if #card.firsts > 0 then lines[#lines + 1] = FirstsLine(card) end
	if #card.keepsakes > 0 then lines[#lines + 1] = "Keepsakes: " .. KeepsakeLine(card) end -- no-L
	if card.closing then lines[#lines + 1] = card.closing end
	lines[#lines + 1] = card.footer
	return table.concat(lines, "\n") .. "\n"
end

-- Markdown: a heading, the line in italics, a list, the footer.
local function MdEscape(text)
	return (tostring(text or ""):gsub("([%*_`#|%[%]])", "\\%1"))
end
X.MdEscape = MdEscape

function X.CardMarkdown(card)
	local lines = { "## " .. MdEscape(card.name or "") }
	if card.line then lines[#lines + 1] = "*" .. MdEscape(card.line) .. "*" end
	lines[#lines + 1] = ""
	for _, chip in ipairs(card.stats) do lines[#lines + 1] = ("- **%s** %s"):format(MdEscape(chip.value), MdEscape(chip.label)) end
	for _, entry in ipairs(card.firsts) do lines[#lines + 1] = ("- %s: **%s**"):format(MdEscape(entry.label), MdEscape(entry.value)) end
	if #card.keepsakes > 0 then lines[#lines + 1] = "- Keepsakes: " .. MdEscape(KeepsakeLine(card)) end -- no-L
	if card.closing then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "> " .. MdEscape(card.closing)
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "*" .. MdEscape(card.footer) .. (card.since and (" · " .. MdEscape(card.since)) or "") .. "*"
	return table.concat(lines, "\n") .. "\n"
end

-- One chat line (the edit box holds 255 characters): name, class, level,
-- then as many stats and firsts as fit.
function X.ChatLine(card)
	local parts = { card.name or "" }
	if card.line then parts[1] = parts[1] .. ", " .. card.line end
	for _, chip in ipairs(card.stats) do parts[#parts + 1] = chip.value .. " " .. chip.label end
	for _, entry in ipairs(card.firsts) do parts[#parts + 1] = entry.label:lower() .. ": " .. entry.value end
	local text = parts[1]
	for i = 2, #parts do
		local nextText = text .. " · " .. parts[i]
		if #nextText > 240 then break end
		text = nextText
	end
	return text
end

---------------------------------------------------------------------------
-- The whole book
---------------------------------------------------------------------------
local function Join(list, lineEach)
	local out = {}
	for _, sentence in ipairs(list or {}) do out[#out + 1] = X.Plain(sentence.text) end
	return table.concat(out, lineEach and "\n" or " ")
end

-- opts: soFar (sentences), title.
function X.BookText(book, set, opts)
	opts = opts or {}
	local rows = book.tone == "ledger"
	local lines = {}
	local function Add(text) lines[#lines + 1] = text end
	Add((set and set.me.name or "") .. " · " .. (X.toneName[book.tone] or ""))
	Add(X.subtitle)
	if opts.soFar and #opts.soFar > 0 then
		Add("")
		Add("STORY SO FAR") -- no-L
		Add(Join(opts.soFar, rows))
	end
	if book.empty then
		Add("")
		Add(book.emptyText)
	end
	for _, part in ipairs(book.parts) do
		Add("")
		Add(part.number and ("PART %d · %s"):format(part.number, E:CaptionText(part.title or "")) or E:CaptionText(part.title or ""))
		if #part.opening > 0 then Add(Join(part.opening, rows)) end
		for _, chapter in ipairs(part.chapters) do
			Add("")
			Add(("%s. %s (%s)"):format(chapter.numeral, chapter.title or "", chapter.span or ""))
			if #chapter.opening > 0 then Add(Join(chapter.opening, rows)) end
			for _, para in ipairs(chapter.paragraphs) do Add(Join(para, rows)) end
			if #chapter.closing > 0 then Add(Join(chapter.closing, rows)) end
		end
	end
	Add("")
	Add(X.footer)
	return table.concat(lines, "\n") .. "\n"
end

function X.BookMarkdown(book, set, opts)
	opts = opts or {}
	local rows = book.tone == "ledger"
	local lines = {}
	local function Add(text) lines[#lines + 1] = text end
	local function Block(list)
		if not list or #list == 0 then return end
		if rows then
			for _, sentence in ipairs(list) do Add("- " .. MdEscape(X.Plain(sentence.text))) end
		else
			Add(MdEscape(Join(list)))
		end
		Add("")
	end
	Add("# " .. MdEscape(set and set.me.name or ""))
	Add("*" .. MdEscape(X.subtitle) .. " · " .. (X.toneName[book.tone] or "") .. " tone*") -- no-L
	Add("")
	if opts.soFar and #opts.soFar > 0 then
		Add("## Story so far") -- no-L
		Add("")
		Block(opts.soFar)
	end
	if book.empty then
		Add(MdEscape(book.emptyText))
		Add("")
	end
	for _, part in ipairs(book.parts) do
		Add(part.number and ("## Part %d · %s"):format(part.number, MdEscape(part.title or "")) or ("## " .. MdEscape(part.title or "")))
		Add("")
		Block(part.opening)
		for _, chapter in ipairs(part.chapters) do
			Add(("### %s. %s"):format(chapter.numeral, MdEscape(chapter.title or "")))
			Add("*" .. MdEscape(chapter.span or "") .. "*")
			Add("")
			Block(chapter.opening)
			for _, para in ipairs(chapter.paragraphs) do Block(para) end
			Block(chapter.closing)
		end
	end
	Add("---")
	Add("*" .. MdEscape(X.footer) .. "*")
	return table.concat(lines, "\n") .. "\n"
end
