-- Story render: facts to sentences with citations, paragraphs and chapters.
-- The only part of the engine that writes text.
--
--   E.Story:Build(input, opts) -> book (cached per input revision and options)
--   E.Story:Row(fact, set)     -> title, sub (the Journey's Ledger row)
--   E.Story.Render.Text(book)  -> plain text (exports)
--   E.Story.Render.Linked(sentence, chapterKey, n) -> "|Heldostory:...|h" text
--   E.Story.Render.Hover(book, sentence) -> the facts behind a sentence
--
-- opts: tone ("chronicle" default, "bard", "ledger"), length ("short",
-- "standard", "long"), pronoun ("they" default, "name", "she", "he"),
-- companions (true), salt (0), preset ("storyteller"), export (false: true
-- drops guild beats and companion names).
--
-- A bank variant is a whole sentence with {slots}: {slot}, {slot:mode},
-- {n:count:noun}, and optional {slot?} parts that render "" when they do not
-- apply. A slot that does not resolve drops the variant (H1); the next one
-- is tried, then the beat's Ledger line, then the beat is dropped.
local _, E = ...
local ipairs, pairs, type, tostring, setmetatable = ipairs, pairs, type, tostring, setmetatable

E.Story = E.Story or {}
local S = E.Story
local R = {}
S.Render = R

local function Grammar() return S.Grammar end

-- Slot types ------------------------------------------------------------------
local PLACE_SLOTS = { zone = "zone", subzone = "subzone", instance = "instance", place = "place", battleground = "battleground",
	continent = "continent", fromzone = "zone", inn = "place" }
local NAME_SLOTS = { boss = true, faction = true }
local TEXT_SLOTS = { item = true, spell = true, recipe = true, challenge = true, attunement = true, node = true, standing = true,
	profession = true, rank = true, mount = true, pet = true, rare = true, guild = true, title = true, quest = true, chain = true,
	goal = true, note = true }
local QUOTED = { quest = true, chain = true, goal = true, title = true, note = true }
local NUMBER_SLOTS = { n = true, total = true, skill = true, kills = true, gain = true, a = true, b = true, days = true,
	spells = true, finds = true, quests = true, deaths = true, next = true, level = true, xp = true, step = true, since = true }
local DURATION_SLOTS = { took = true, duration = true, played = true, window = true, nexttook = true }
R.slotTypes = { place = PLACE_SLOTS, name = NAME_SLOTS, text = TEXT_SLOTS, number = NUMBER_SLOTS, duration = DURATION_SLOTS }

-- Values ----------------------------------------------------------------------------
local function Val(fact, key)
	local v = fact.v
	if v[key] ~= nil then return v[key] end
	if key == "level" then return fact.l end
	if key == "zone" then return fact.z end
	if key == "subzone" then return fact.s end
	return nil
end

-- Book context helpers --------------------------------------------------------
local function NewPara(ctx)
	if ctx.para and ctx.para.first then ctx.chapter.prevParaFirst = ctx.para.first end
	ctx.para = { names = 0, nouns = {}, first = nil, count = 0 }
end

local function NewChapter(ctx, key)
	ctx.chapter = { key = key, mentioned = false, epithets = {}, last = nil }
	ctx.para = nil
	NewPara(ctx)
end

-- Reference phrase for the character after T.nameRepeat mentions (V4).
local function CharacterRef(ctx, refIndex)
	local refs = S.Voice.References(ctx.set.me)
	if #refs == 0 then return nil end
	return refs[(refIndex % #refs) + 1]
end

-- Fill one template. Returns sentence or nil, reason.
local function Fill(ctx, template, fact, extra, beat)
	local G = Grammar()
	local T = S.Tuning
	local tone = ctx.tone
	local set = ctx.set
	local me = set.me
	local opts = ctx.opts
	G.style = tone
	local cites, citeSeen = {}, {}
	local function Cite(f)
		if f and not citeSeen[f.id] then
			citeSeen[f.id] = true
			cites[#cites + 1] = f.id
		end
	end
	Cite(fact)
	for _, id in ipairs(extra.cites or {}) do Cite(set.byId[id]) end
	local flavour, people, nouns = {}, {}, {}
	local nameUses, mentioned = 0, ctx.chapter.mentioned
	local paraNames = ctx.para.names
	local failed

	local function Number(n, mode)
		if type(n) ~= "number" then return nil end
		if mode == "digits" then return G.Digits(n) end
		if mode == "word" then return G.Number(n, tone) end
		if mode == "ordinal" then return G.Ordinal(n, tone) end
		if mode == "times" then return G.Times(n, tone) end
		return G.Digits(n)
	end

	local function PlaceText(name, mode, slotType)
		if type(name) ~= "string" or name == "" then return nil end
		mode = mode or "bare"
		if mode == "epithet" or mode == "scene" then
			if tone == "ledger" then return nil end
			if mode == "epithet" and tone ~= "chronicle" then return nil end
			if ctx.chapter.epithets[name] then return nil end
			local text = S.Voice.Flavour(name, mode)
			if not text then return nil end
			flavour[#flavour + 1] = { kind = mode, place = name, word = text }
			nouns[name] = (nouns[name] or 0) + 1
			return text
		end
		if mode == "entrance" then
			local word = S.Voice.Entrance(name)
			if not word or tone ~= "bard" then return nil end
			flavour[#flavour + 1] = { kind = "entrance", place = name, word = word }
			return word
		end
		-- V4: a name used T.nameRepeat times in this paragraph becomes a reference.
		local count = (ctx.para.nouns[name] or 0) + (nouns[name] or 0)
		if count >= T.nameRepeat and tone ~= "ledger" then
			if mode == "in" or mode == "at" or mode == "auto" or mode == "to" or mode == "into" then return "there" end
			if mode == "bare" or mode == "start" then return S.Voice.PlaceReference(name) end
			return nil
		end
		nouns[name] = (nouns[name] or 0) + 1
		if mode == "poss" then return G.Possessive(name) end
		local quiet = slotType == "boss" or slotType == "faction"
		return G.Place(name, mode, quiet)
	end

	local function CharacterName(mode)
		if not me.name then return nil end
		local text
		if paraNames + nameUses >= T.nameRepeat and tone ~= "ledger" then
			text = CharacterRef(ctx, paraNames + nameUses)
			if not text then return nil end
		else
			text = mentioned and (me.first or me.name) or me.name
			mentioned = true
		end
		nameUses = nameUses + 1
		if mode == "poss" then return G.Possessive(text) end
		return text
	end

	local function Optional(name, mode)
		if name == "since" then
			if fact.v.firstKnown or fact.flags.firstdungeon or fact.flags.firstraid then return "" end
			return " since the journal began"
		elseif name == "rank" then
			local rank = fact.v.rank
			return rank and (" (Rank " .. rank .. ")") or ""
		elseif name == "forever" then
			if not fact.v.forever then return "" end
			flavour[#flavour + 1] = { kind = "forever", place = fact.v.instance }
			return tone == "bard" and ", a hall new to the old world" or ", one of the dungeons WoW: Forever added"
		elseif name == "with" then
			local fellow = fact.v.fellow
			if not (fellow and opts.companions) then return "" end
			people[#people + 1] = fellow
			return ", with " .. fellow
		elseif name == "pace" then
			local pace = extra.pace
			if not pace then return "" end
			Cite(pace)
			return ", " .. pace.v.pace
		elseif name == "rested" then
			local id = fact.v.rested
			if not id or not set.byId[id] then return "" end
			Cite(set.byId[id])
			return tone == "ledger" and " · well rested" or ", on a day that began well rested"
		elseif name == "where" then
			local sub = fact.s
			if not sub or sub == fact.z then return "" end
			return " " .. G.Place(sub, "auto")
		end
		return nil
	end

	local function Slot(body)
		local name, rest = body:match("^([%a_]+)(.*)$")
		if not name then return nil end
		local optional = rest:sub(-1) == "?"
		if optional then
			rest = rest:sub(1, -2)
			return Optional(name, rest ~= "" and rest:sub(2) or nil)
		end
		local mode, arg = rest:match("^:([%a_]+):?(.*)$")
		if arg == "" then arg = nil end

		-- Guards: "{if:flag}" renders nothing, and only when the fact has the flag.
		-- "{if:samelevel}": the last sentence of the paragraph was about this
		-- level, so the variant may leave the level out.
		if name == "if" and mode == "samelevel" then return (fact.l and fact.l == ctx.para.level) and "" or nil end
		if name == "if" and mode == "many" then return ((fact.v.n or 0) > 1) and "" or nil end
		if name == "if" then return (mode and (fact.flags[mode] or fact.v[mode])) and "" or nil end

		-- The character.
		if name == "name" then return CharacterName(mode) end
		if name == "their" or name == "they" or name == "them" then
			local word = G.Pronoun(name, opts.pronoun)
			if word then return word end
			if name == "their" then return CharacterName("poss") end
			return CharacterName()
		end
		if name == "me" then
			if mode == "desc" then return S.Voice.Describe(me.race, me.class) end
			if mode == "bard" then
				if tone ~= "bard" then return nil end
				flavour[#flavour + 1] = { kind = "race", word = me.race }
				return S.Voice.DescribeBard(me.race, me.class)
			end
			if mode == "race" then local r = S.Voice.RaceRow(me.race) return r and r.noun end
			if mode == "class" then local c = S.Voice.ClassRow(me.class) return c and c.noun end
			return nil
		end
		if name == "side" then
			local side = S.Voice.Side(me.faction)
			if side then flavour[#flavour + 1] = { kind = "faction", faction = me.faction, word = side } end
			return side
		end
		if name == "beast" then
			local beast = S.Voice.FlightBeast(me.faction, fact.z)
			if not beast or tone ~= "bard" then return nil end
			flavour[#flavour + 1] = { kind = "faction", faction = me.faction, word = beast }
			return beast
		end
		if name == "vehicle" then
			local vehicle = fact.v.vehicle
			if vehicle and vehicle ~= "boat" then flavour[#flavour + 1] = { kind = "faction", faction = me.faction, word = vehicle } end
			return vehicle
		end
		if name == "home" then
			local r = S.Voice.RaceRow(me.race)
			return r and r.capital
		end

		-- First-time wording (H9).
		if name == "firsttime" then
			return (fact.v.firstKnown or fact.flags.firstdungeon or fact.flags.firstraid) and "for the first time"
				or "for the first time since the journal began"
		end
		if name == "afirst" then
			return (fact.v.firstKnown or fact.flags.firstdungeon or fact.flags.firstraid) and "a first for the journey"
				or "a first since the journal began"
		end
		if name == "firstkill" then
			return fact.v.firstKnown and "a first kill for the journey" or "a first kill since the journal began"
		end

		-- Companions and other players (H6).
		if name == "companions" then
			if not opts.companions then return nil end
			local list = fact.v.with or {}
			if #list == 0 then return nil end
			for _, person in ipairs(list) do people[#people + 1] = person end
			return G.List(list, { extra = fact.v.extra or 0, style = tone })
		end
		if name == "fellow" then
			local fellow = Val(fact, "fellow")
			if not fellow or not opts.companions then return nil end
			if mode == "desc" then return S.Voice.Describe(fact.v.race, fact.v.class) end
			people[#people + 1] = fellow
			return fellow
		end
		if name == "fclass" then
			local row = S.Voice.ClassRow(fact.v.class)
			if not row then return nil end
			return tone == "ledger" and (row.noun:sub(1, 1):upper() .. row.noun:sub(2)) or row.noun
		end

		-- Places and named things.
		local placeType = PLACE_SLOTS[name]
		if placeType or NAME_SLOTS[name] then
			local value = Val(fact, name)
			if name == "fromzone" then value = fact.v.fromZone end
			if name == "place" and not value then value = fact.v.instance or fact.s or fact.z end
			return PlaceText(value, mode, name)
		end
		if name == "where" then return G.Where(fact.s, fact.z) end
		if name == "counts" then
			local faction = fact.v.faction
			return (faction and G.IsPlural(faction)) and "count" or "counts"
		end
		if TEXT_SLOTS[name] then
			local value = Val(fact, name)
			if type(value) ~= "string" or value == "" then return nil end
			if name == "title" then value = G.Trim(value) end
			if (name == "guild") and opts.export then return nil end
			if mode == "a" then
				if G.IsLink(value) then return value end
				return G.WithArticle(value)
			end
			if mode == "lower" then return G.Lower(value) end
			if mode == "q" or (QUOTED[name] and tone ~= "ledger" and mode ~= "bare") then return '"' .. value .. '"' end
			return value
		end

		-- Numbers, durations, money, dates.
		if name == "next" then
			local nextFact = extra.next
			if not nextFact then return nil end
			Cite(nextFact)
			return Number(nextFact.l, mode)
		end
		if name == "nexttook" then
			return G.Duration(extra.took, mode == "ledger" and "ledger" or tone)
		end
		if mode == "count" and arg then
			local value = Val(fact, name)
			if type(value) ~= "number" then return nil end
			return G.Count(value, arg, tone)
		end
		if NUMBER_SLOTS[name] then
			return Number(Val(fact, name), mode)
		end
		if DURATION_SLOTS[name] then
			local value = Val(fact, name)
			if name == "duration" and not value then value = fact.v.time end
			return G.Duration(value, mode == "ledger" and "ledger" or tone)
		end
		if name == "gold" then
			return G.Money(fact.v.earned or fact.v.gold, mode == "ledger" and "ledger" or tone)
		end
		if name == "levels" then
			local clip = extra.clip
			return G.Levels(clip and clip.a or fact.v.a, clip and clip.b or fact.v.b)
		end
		if name == "range" then
			local a, b = fact.v.a, fact.v.b
			if not a then return nil end
			if not b or a == b then return "at level " .. a end
			return ("between levels %d and %d"):format(a, b)
		end
		if name == "date" or name == "startdate" or name == "stopdate" then
			local t = (name == "date" and (fact.t or fact.v.date)) or (name == "startdate" and fact.v.start) or fact.v.stop
			return G.Date(t, (mode == "short" or tone == "ledger") and "short" or nil)
		end
		if name == "daypart" then return G.TimeOfDay(fact.t or fact.v.start) end
		if name == "share" then
			if tone == "ledger" then return fact.v.share and (G.Digits(fact.v.share * 100) .. "%") or nil end
			return G.Share(fact.v.share)
		end
		if name == "source" then
			local source = fact.v.source
			if not source then return nil end
			if mode == "lower" then return G.Decapitalize(source) end
			return source
		end
		if name == "pct" then
			local pct = fact.v.pct
			return pct and (G.Digits(pct * 100) .. "%") or nil
		end
		return nil
	end

	local text = template:gsub("{([^}]+)}", function(body)
		if failed then return "" end
		local value = Slot(body)
		if value == nil then
			failed = body
			return ""
		end
		return value
	end)
	if failed then return nil, "slot " .. failed end
	local skeleton = template:gsub("{[^}]+}", "§")
	local prose = tone ~= "ledger"
	text = G.Clean(text, prose)
	-- "since the journal began at level 19" reads as when the journal began.
	text = text:gsub("since the journal began (at) ", "since the journal began, %1 ")
	text = text:gsub("since the journal began (on) ", "since the journal began, %1 ")
	text = text:gsub("since the journal began (in) ", "since the journal began, %1 ")
	if ctx.chapter.single then
		-- A one-level chapter: "these levels" is "this level".
		text = text:gsub("([Tt])hese levels'", "%1his level's"):gsub("([Tt])hese levels have", "%1his level has")
		text = text:gsub("([Tt])hese levels", "%1his level")
	end
	text = G.Capitalize(text)
	if prose and not (text:find("[%.!%?]$") or text:find('[%.!%?]"$')) then text = text .. "." end
	return {
		text = text, skeleton = skeleton, cites = cites, tone = tone, flavour = flavour, people = people,
		beat = beat, nouns = nouns, nameUses = nameUses, mentioned = mentioned, lead = fact.id,
		saysLevel = template:find("{level", 1, true) ~= nil, level = fact.l,
	}
end
R.Fill = Fill

-- Beat choice for a fact ----------------------------------------------------------------
local BEAT_FOR = {
	zone = function(f) return f.v.begin and "zone_begin" or "zone" end,
	skill = function(f) return f.v.mastered and "skill_master" or "skill" end,
	loot = function(f) return f.flags.firstepic and "loot_epic" or "loot" end,
	mount = function(f) return f.flags.firstmount and "mount_first" or "mount" end,
	fast = function(f) return f.v.rested and "fast_rested" or "fast" end,
	pvpwin = function() return "pvpwin" end,
}
function R.BeatFor(fact)
	local fn = BEAT_FOR[fact.kind]
	if fn then return fn(fact) end
	return fact.kind
end

-- Render one beat in the current tone with V1-V3 and Honesty.
local function RenderBeat(ctx, beatId, fact, extra, required)
	local B = S.Banks
	local def = B.beats[beatId]
	if not def or not fact then return nil end
	extra = extra or {}
	local tone = ctx.tone
	local bank = B.tones[tone] or {}
	local lists = {}
	if def.with and ctx.opts.companions then
		local withList = bank[beatId .. "_with"]
		if withList then lists[#lists + 1] = { key = beatId .. "_with", list = withList } end
	end
	if bank[beatId] then lists[#lists + 1] = { key = beatId, list = bank[beatId] } end
	local ledger = B.tones.ledger and B.tones.ledger[beatId]
	local prose = tone ~= "ledger"
	local function Accept(sentence, strict)
		if not sentence then return false end
		local ok = S.Honesty.Check(sentence, ctx.set, ctx.opts)
		if not ok then return false end
		if S.Pick.Seen(ctx.pick, sentence.text) then return false end
		if prose then
			local stem = S.Pick.Stem(sentence.text)
			if stem == ctx.chapter.last then return false end
			if (ctx.para.count or 0) == 0 and stem == ctx.chapter.prevParaFirst then return false end
			if strict then
				-- V7 (soft): the level the last sentence was about is not said again
				-- in the same paragraph, and "since the journal began" once a chapter.
				if sentence.saysLevel and sentence.level and sentence.level == ctx.para.level then return false end
				if ctx.chapter.since and sentence.text:find("since the journal began", 1, true) then return false end
			end
		end
		return true
	end
	for pass = 1, prose and 2 or 1 do
		for _, entry in ipairs(lists) do
			local seed = S.Pick.Seed(ctx.set.charKey, ctx.chapter.key, entry.key, tone, ctx.opts.salt)
			local useKey = entry.key .. "|" .. tone
			-- Ledger lines are fallbacks, most complete first; prose variants rotate.
			local order = S.Pick.Order(ctx.pick, useKey, #entry.list, seed)
			if not prose then
				order = {}
				for i = 1, #entry.list do order[i] = i end
			end
			for _, index in ipairs(order) do
				local sentence = Fill(ctx, entry.list[index], fact, extra, beatId)
				if Accept(sentence, prose and pass == 1) then
					S.Pick.Use(ctx.pick, useKey, index)
					sentence.variant = index
					sentence.list = entry.key
					return sentence
				end
			end
		end
	end
	-- V3 fallback: the Ledger line (prose tones end it with a period).
	if prose and ledger and (required or #lists == 0) then
		local saved = ctx.tone
		ctx.tone = "ledger"
		local sentence = Fill(ctx, ledger[1], fact, extra, beatId)
		ctx.tone = saved
		if sentence then
			sentence.tone = tone
			sentence.ledger = true
			if not sentence.text:find("[%.!%?]$") then sentence.text = sentence.text .. "." end
			if Accept(sentence) then return sentence end
		end
	end
	return nil
end
R.RenderBeat = RenderBeat

-- Facts about a range of levels: a sentence about one never sets the
-- paragraph's "same level".
local SPAN_KINDS = { deathless = true, runs = true, topfellow = true, sourceoff = true, rolled = true, gap = true }

-- Commit a sentence to the book state (name rhythm, stems, duplicates).
local function Commit(ctx, sentence, block)
	if not sentence then return end
	ctx.para.names = ctx.para.names + sentence.nameUses
	ctx.chapter.mentioned = sentence.mentioned or ctx.chapter.mentioned
	for name, n in pairs(sentence.nouns) do ctx.para.nouns[name] = (ctx.para.nouns[name] or 0) + n end
	for _, word in ipairs(sentence.flavour) do
		if word.kind == "epithet" or word.kind == "scene" then ctx.chapter.epithets[word.place] = true end
	end
	local stem = S.Pick.Stem(sentence.text)
	ctx.chapter.last = stem
	-- Chapter-wide plan facts (p:...) span levels: they set no "same level".
	local leadFact = ctx.set.byId[sentence.lead]
	local span = not leadFact or leadFact.id:find("^p:") or SPAN_KINDS[leadFact.kind]
	ctx.para.level = (not span) and sentence.level or nil
	if sentence.text:find("since the journal began", 1, true) then ctx.chapter.since = true end
	if not ctx.para.first then ctx.para.first = stem end
	ctx.para.count = (ctx.para.count or 0) + 1
	S.Pick.Remember(ctx.pick, sentence.text)
	block[#block + 1] = sentence
end

local function Say(ctx, block, beatId, fact, extra, required)
	local sentence = RenderBeat(ctx, beatId, fact, extra, required)
	Commit(ctx, sentence, block)
	return sentence
end

-- Story chapters ----------------------------------------------------------------------------
local function RenderChapter(ctx, chapter, plan)
	local set = ctx.set
	NewChapter(ctx, chapter.key)
	ctx.chapter.single = chapter.a == chapter.b
	local out = { key = chapter.key, numeral = chapter.numeral, a = chapter.a, b = chapter.b, opening = {}, paragraphs = {},
		closing = {}, era = chapter.era, kind = chapter.kind }
	out.span = Grammar().Levels(chapter.a, chapter.b)
	-- Title.
	if chapter.kind == "gap" then
		out.title = "Before the journal"
	else
		local G = Grammar()
		local list = (S.Banks.tones[ctx.tone] or {}).chtitle or S.Banks.tones.ledger.chtitle
		local seed = S.Pick.Seed(set.charKey, chapter.key, "title", ctx.tone, ctx.opts.salt)
		local index = seed % #list + 1
		local place = chapter.place
		local text = list[index]:gsub("{place:(%a+)}", function(mode) return G.Place(place, mode, true) or "" end)
		out.title = G.Capitalize(text)
		-- Two chapters in a row in one place: the second says so.
		if out.title == ctx.lastTitle then
			local again = (S.Banks.tones[ctx.tone] or {}).chtitle_again or S.Banks.tones.ledger.chtitle_again
			out.title = G.Capitalize((again[1]:gsub("{place:(%a+)}", function(mode) return G.Place(place, mode, true) or "" end)))
		end
	end
	ctx.lastTitle = out.title
	-- Opening: the lead, then the setting.
	local leadSentence
	if chapter.kind == "gap" then
		leadSentence = Say(ctx, out.opening, "before", chapter.lead, nil, true)
	elseif chapter.lead then
		leadSentence = Say(ctx, out.opening, R.BeatFor(chapter.lead), chapter.lead, { pace = nil }, true)
	end
	local named = leadSentence and chapter.setting and leadSentence.nouns[chapter.setting.v.zone]
	if chapter.setting and not named then Say(ctx, out.opening, "homezone", chapter.setting) end
	-- Body: paragraphs by shape (V5).
	local shapes = S.Tuning.paraShapes
	local shape = shapes[S.Pick.Seed(set.charKey, chapter.key, "shape", ctx.tone, ctx.opts.salt) % #shapes + 1]
	local para, sizeIndex = {}, 1
	NewPara(ctx)
	for _, fact in ipairs(chapter.body or {}) do
		local extra = {}
		if fact.kind == "sourceoff" and chapter.clips then extra.clip = chapter.clips[fact.id] end
		local before = #para
		Say(ctx, para, R.BeatFor(fact), fact, extra, S.Tuning.forced[fact.kind])
		if #para > before and #para >= shape[(sizeIndex - 1) % #shape + 1] then
			out.paragraphs[#out.paragraphs + 1] = para
			para = {}
			sizeIndex = sizeIndex + 1
			NewPara(ctx)
		end
	end
	if #para > 0 then out.paragraphs[#out.paragraphs + 1] = para end
	-- Closing.
	NewPara(ctx)
	if chapter.close then Say(ctx, out.closing, chapter.close.v.now and "chclose_now" or "chclose", chapter.close) end
	return out
end

-- Level chapters (the Journey) ---------------------------------------------------------------
local LEVEL_OPEN = { deathstreak = true, boss = true, raidboss = true, dungeon = true, raid = true, loot = true, mount = true,
	zone = true, rep = true, attuned = true, gap = true, title = true, maxlevel = true, crossed = true, runs = true, slow = true, fast = true }

local function StatsLine(chapter)
	local G = Grammar()
	local rec = chapter.rec or {}
	if not chapter.recorded then return "Level times not recorded" end
	local parts = {}
	if rec.time then parts[#parts + 1] = G.Duration(rec.time, "ledger") .. (chapter.now and " so far" or "") end
	parts[#parts + 1] = G.Count(rec.kills or 0, "kill", "ledger")
	parts[#parts + 1] = G.Count(rec.quests or 0, "quest", "ledger")
	local deaths = rec.deaths or 0
	if deaths > 0 then
		local where = {}
		for zone, n in pairs(rec.deathZones or {}) do where[#where + 1] = { zone, n } end
		local text = G.Count(deaths, "death", "ledger")
		if #where >= 2 then
			table.sort(where, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
			for i, w in ipairs(where) do where[i] = ("%d %s"):format(w[2], G.Place(w[1], "in", true)) end
			text = text .. " (" .. table.concat(where, ", ") .. ")"
		end
		parts[#parts + 1] = text
	end
	return table.concat(parts, " · ")
end
R.StatsLine = StatsLine

local ROW_META = {
	__index = function(row, key)
		if key ~= "title" and key ~= "sub" then return nil end
		local title, sub = R.Row(rawget(row, "fact"), rawget(row, "set"))
		rawset(row, "title", title or false)
		rawset(row, "sub", sub or false)
		return rawget(row, key) or nil
	end,
}

local function RenderLevel(ctx, chapter)
	local G = Grammar()
	NewChapter(ctx, chapter.key)
	local zone = chapter.zone
	local out = { key = chapter.key, level = chapter.level, now = chapter.now, opening = {}, closing = {}, rows = {} }
	out.title = ("Chapter %d · %s"):format(chapter.level, zone and G.Place(zone, "head", true) or "The road")
	out.stats = StatsLine(chapter)
	local lead = chapter.lead
	if lead and LEVEL_OPEN[lead.kind] and not (lead.kind == "zone" and (lead.v.begin or lead.z == zone)) then
		Say(ctx, out.opening, "lvopen_" .. lead.kind, lead)
	end
	if #out.opening == 0 and chapter.home then Say(ctx, out.opening, "lvopen_home", chapter.home) end
	-- Rows render on first read (row.title, row.sub): a long journal has
	-- thousands, and a page shows a few dozen.
	for _, fact in ipairs(chapter.rows) do
		if S.Banks.tones.ledger[R.BeatFor(fact)] then
			out.rows[#out.rows + 1] = setmetatable({ id = fact.id, kind = fact.kind, t = fact.t, fact = fact, set = ctx.set }, ROW_META)
		end
	end
	if chapter.quiet then Say(ctx, out.closing, "quiet", chapter.home or ctx.set.byId["lv:" .. chapter.level] or lead or chapter.home) end
	NewPara(ctx)
	local rec = chapter.rec or {}
	if chapter.next and rec.time then
		local moved = chapter.next.z and zone and chapter.next.z ~= zone
		local closeFact = chapter.next
		Say(ctx, out.closing, moved and "lvclose_moved" or "lvclose", closeFact,
			{ took = rec.time, pace = chapter.pace, next = chapter.next, cites = { chapter.home and chapter.home.id } })
	elseif chapter.now and rec.time then
		local fact = ctx.set.byId["lv:" .. chapter.level] or chapter.home
		if fact then Say(ctx, out.closing, "lvclose_now", fact, { took = rec.time }) end
	end
	return out
end

-- The whole book ------------------------------------------------------------------------------
local function EraTitle(ctx, era)
	local G = Grammar()
	if era.gap then return "Where it began" end
	local list = (S.Banks.tones[ctx.tone] or {})["era" .. era.index] or S.Banks.tones.ledger["era" .. era.index]
	if not list then return nil end
	local zone = era.zone
	local starts = (E.StoryWorld or {}).starts or {}
	local seed = S.Pick.Seed(ctx.set.charKey, era.key, "era", ctx.tone, ctx.opts.salt)
	for step = 0, #list - 1 do
		local template = list[(seed + step) % #list + 1]
		local ok = true
		if template:find("{place", 1, true) and not zone then ok = false end
		-- "The road to Loch Modan" is wrong where the journal began.
		if template:find("{place:to}", 1, true) and zone == ctx.set.input.startedZone then ok = false end
		if template:find("Where it began", 1, true) and zone ~= ctx.set.input.startedZone then ok = false end
		-- "The forties" only for an era inside levels 40-49 (eras snap to zone changes).
		for word, decade in pairs({ thirties = 30, forties = 40, fifties = 50 }) do
			if template:find(word, 1, true) and (era.a < decade or era.b > decade + 9) then ok = false end
		end
		if template:find("last ten levels", 1, true) and (era.a < 50 or era.b > 59) then ok = false end
		if template:find("Home ground", 1, true) and not (zone and starts[ctx.set.me.race or ""] == zone) then ok = false end
		if ok then
			local text = template:gsub("{place:(%a+)}", function(mode) return G.Place(zone, mode, true) or "" end)
			return G.Capitalize(text)
		end
	end
	return G.Capitalize(G.Levels(era.a, era.b))
end

local function Summary(ctx, block)
	local set = ctx.set
	NewChapter(ctx, "summary")
	local totals, game = set.byId.totals, set.byId.game
	if totals and (totals.v.earned or 0) > 0 then Say(ctx, block, "summary", totals, { cites = { game and game.id } }) end
	if game then Say(ctx, block, "gamecount", game) end
end

-- The story is English only: its own lines skip L[], like the banks.
R.emptyText = "The first page is still blank. Go and explore." -- no-L

function R.Book(set, plan, opts)
	local ctx = { set = set, plan = plan, opts = opts, tone = opts.tone, pick = S.Pick.New() }
	local G = Grammar()
	G.refYear = set.now and G.Year(set.now) or nil
	local book = { tone = opts.tone, parts = {}, chapters = {}, journey = {}, river = plan.river, summary = {}, charKey = set.charKey }
	local number = 0
	for _, era in ipairs(plan.eras) do
		if not era.gap then number = number + 1 end
		local part = { key = era.key, index = era.index, number = not era.gap and number or nil, a = era.a, b = era.b,
			chapters = {}, opening = {}, gap = era.gap }
		part.title = EraTitle(ctx, era)
		NewChapter(ctx, era.key)
		if era.span then Say(ctx, part.opening, "eraopen", era.span) end
		for _, chapter in ipairs(era.chapters) do
			local out = RenderChapter(ctx, chapter, plan)
			-- A chapter with nothing to say is left out (no placeholder pages).
			if #out.opening > 0 or #out.paragraphs > 0 then
				out.numeral = S.Plan.Roman(#book.chapters + 1)
				part.chapters[#part.chapters + 1] = out
				book.chapters[#book.chapters + 1] = out
			end
		end
		if #part.chapters > 0 then
			book.parts[#book.parts + 1] = part
		else
			number = number - (era.gap and 0 or 1)
		end
	end
	-- Nothing recorded yet: the book says so in one line.
	if #book.chapters == 0 then
		book.empty = true
		book.emptyText = R.emptyText
	end
	-- The journey has its own wording state: its openings never block the Book's.
	local jctx = { set = set, plan = plan, opts = opts, tone = opts.tone, pick = S.Pick.New() }
	for _, chapter in ipairs(plan.levels) do
		book.journey[#book.journey + 1] = RenderLevel(jctx, chapter)
	end
	Summary(ctx, book.summary)
	G.style = "chronicle"
	return book
end

-- Rows: the Journey's Ledger line for a fact (title, sub-line).
local NO_PLACE = { death = true, deathstreak = true, zone = true, level = true, gap = true, maxlevel = true, crossed = true,
	sourceoff = true, unrecorded = true, rolled = true, met = true, explored = true, gather = true, farm = true }
function R.Row(fact, set)
	local beatId = R.BeatFor(fact)
	local def = S.Banks.beats[beatId]
	local ledger = S.Banks.tones.ledger and S.Banks.tones.ledger[beatId]
	if not def or not ledger then return nil end
	local ctx = { set = set, opts = { companions = true, pronoun = "name" }, tone = "ledger", pick = S.Pick.New() }
	NewChapter(ctx, "row")
	local sentence
	for _, template in ipairs(ledger) do
		sentence = Fill(ctx, template, fact, {}, beatId)
		if sentence then break end
	end
	if not sentence then return nil end
	local G = Grammar()
	local sub = {}
	if def.sub then
		local subText = def.sub(fact, G)
		if subText then sub[#sub + 1] = subText end
	end
	if not NO_PLACE[fact.kind] and (fact.s or fact.z) then
		local place = (fact.s and fact.z and fact.s ~= fact.z) and (fact.s .. ", " .. G.Place(fact.z, "head", true)) or G.Place(fact.s or fact.z, "head", true)
		sub[#sub + 1] = place
	end
	return sentence.text, (#sub > 0) and table.concat(sub, " · ") or nil
end

-- Plain text of a book (for exports).
function R.Text(book, withJourney)
	local lines = {}
	local function Add(text) lines[#lines + 1] = text end
	local rows = book.tone == "ledger"
	if book.empty then
		Add("")
		Add(book.emptyText)
	end
	local function Block(list, lineEach)
		local parts = {}
		for _, sentence in ipairs(list) do
			if rows or lineEach then Add(sentence.text) else parts[#parts + 1] = sentence.text end
		end
		if #parts > 0 then Add(table.concat(parts, " ")) end
	end
	for _, part in ipairs(book.parts) do
		Add("")
		if part.number then
			Add(("== Part %d%s =="):format(part.number, part.title and (" · " .. part.title) or ""))
		else
			Add(("== %s =="):format(part.title or ""))
		end
		Block(part.opening)
		for _, chapter in ipairs(part.chapters) do
			Add("")
			Add(("%s. %s (%s)"):format(chapter.numeral, chapter.title or "", chapter.span or ""))
			Block(chapter.opening)
			for _, para in ipairs(chapter.paragraphs) do Block(para) end
			Block(chapter.closing)
		end
	end
	if #book.summary > 0 then
		Add("")
		Add("== Story so far ==")
		Block(book.summary)
	end
	if withJourney then
		Add("")
		Add("== Journey ==")
		for _, chapter in ipairs(book.journey) do
			Add("")
			Add(chapter.title .. (chapter.now and " (Now)" or ""))
			Block(chapter.opening, true)
			Add(chapter.stats)
			for _, row in ipairs(chapter.rows) do
				if row.title then Add("  " .. row.title .. (row.sub and ("  [" .. row.sub .. "]") or "")) end
			end
			Block(chapter.closing, true)
		end
	end
	return table.concat(lines, "\n") .. "\n"
end

-- Every sentence of a book, in reading order, with where it sits.
function R.Sentences(book, withJourney)
	local out = {}
	local function Add(list, where, para)
		for _, sentence in ipairs(list) do out[#out + 1] = { s = sentence, where = where, para = para } end
	end
	local paraN = 0
	for _, part in ipairs(book.parts) do
		paraN = paraN + 1
		Add(part.opening, part.key, paraN)
		for _, chapter in ipairs(part.chapters) do
			paraN = paraN + 1
			Add(chapter.opening, chapter.key, paraN)
			for _, para in ipairs(chapter.paragraphs) do
				paraN = paraN + 1
				Add(para, chapter.key, paraN)
			end
			paraN = paraN + 1
			Add(chapter.closing, chapter.key, paraN)
		end
	end
	paraN = paraN + 1
	Add(book.summary, "summary", paraN)
	if withJourney then
		for _, chapter in ipairs(book.journey) do
			paraN = paraN + 1
			Add(chapter.opening, chapter.key, paraN)
			paraN = paraN + 1
			Add(chapter.closing, chapter.key, paraN)
		end
	end
	return out
end

-- Sentence hyperlinks: |Heldostory:<chapter>:<n>|h ... |h, split around item
-- links (hyperlinks cannot nest).
function R.Linked(sentence, chapterKey, n)
	local id = ("eldostory:%s:%d"):format(tostring(chapterKey), n)
	local text = sentence.text or ""
	local out, pos = {}, 1
	while true do
		local s, e = text:find("|c%x%x%x%x%x%x%x%x|H.-|h.-|h|r", pos)
		if not s then s, e = text:find("|H.-|h.-|h", pos) end
		if not s then break end
		if s > pos then out[#out + 1] = "|H" .. id .. "|h" .. text:sub(pos, s - 1) .. "|h" end
		out[#out + 1] = text:sub(s, e)
		pos = e + 1
	end
	if pos <= #text then out[#out + 1] = "|H" .. id .. "|h" .. text:sub(pos) .. "|h" end
	return table.concat(out)
end

local CLASS_LABEL = { T = "Recorded by the journal", G = "From the game", D = "Worked out from", R = "EldoUI reference" }
R.classLabel = CLASS_LABEL

-- The facts behind a sentence: { { text, source } }, then the tone line.
function R.Hover(set, sentence)
	local G = Grammar()
	local lines = {}
	for _, id in ipairs(sentence.cites or {}) do
		local fact = set.byId[id]
		if fact then
			local title = R.Row(fact, set) or (fact.kind == "ref" and ("Typical for level %d: %s"):format(fact.v.level, G.Duration(fact.v.minutes * 60, "ledger")))
				or fact.kind
			local bits = { title }
			if fact.t then bits[#bits + 1] = G.Date(fact.t, "short") end
			if fact.z then bits[#bits + 1] = G.Place(fact.z, "head", true) end
			local source = CLASS_LABEL[fact.class] or ""
			if fact.class == "G" and fact.v.undated then source = "From the game (undated)" end
			lines[#lines + 1] = { text = table.concat(bits, " · "), source = source }
			if fact.class == "D" then
				for _, input in ipairs(fact.from or {}) do
					local inputFact = set.byId[input]
					local inputTitle = inputFact and (R.Row(inputFact, set) or inputFact.kind) or input
					lines[#lines + 1] = { text = "  " .. inputTitle, source = inputFact and CLASS_LABEL[inputFact.class] or "" }
				end
			end
		end
	end
	local toneName = { ledger = "Ledger", chronicle = "Chronicle", bard = "Bard" }
	lines[#lines + 1] = { text = "Wording: " .. (toneName[sentence.tone] or tostring(sentence.tone)) .. " tone" } -- no-L
	return lines
end

-- Public entry points ------------------------------------------------------------------------
local cache = setmetatable({}, { __mode = "k" })
S.cache = cache

local DEFAULTS = { tone = "chronicle", length = "standard", pronoun = "they", companions = true, salt = 0, preset = "storyteller", export = false }

function S.Options(opts)
	local out = {}
	for k, v in pairs(DEFAULTS) do out[k] = v end
	for k, v in pairs(opts or {}) do out[k] = v end
	if out.export then out.companions = opts and opts.exportCompanions or false end
	if out.salt == 0 and opts and opts.salt == nil then out.salt = 0 end
	return out
end

-- The compiled facts for an input (cached per revision).
function S:Compile(input)
	local entry = cache[input]
	if entry and entry.rev == input.rev then return entry.set end
	local set = S.Facts.Compile(input)
	S.Derive.Run(set)
	cache[input] = { rev = input.rev, set = set, books = {} }
	return set
end

function S:Build(input, opts)
	opts = S.Options(opts)
	if opts.salt == 0 and input.salt then opts.salt = input.salt end
	local set = self:Compile(input)
	local entry = cache[input]
	local key = table.concat({ opts.tone, opts.length, opts.pronoun, tostring(opts.companions), opts.salt, opts.preset, tostring(opts.export) }, "|")
	if entry.books[key] then return entry.books[key], set end
	local plan = S.Plan.Build(set, opts)
	local book = R.Book(set, plan, opts)
	book.plan = plan
	entry.books[key] = book
	return book, set
end

function S:Row(fact, set) return R.Row(fact, set) end
