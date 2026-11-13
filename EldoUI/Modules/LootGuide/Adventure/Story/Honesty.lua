-- The honesty checker every story sentence passes before it is shown.
--
--   H1  every sentence cites at least one T, G or D fact, and every cite resolves
--   H2  R (reference) facts only qualify: a sentence citing only R facts is out
--   H3  no causes and no combat performance ("killed by", "because", "damage" ...)
--   H4  no inner life in Chronicle or Ledger; in Bard every lexicon word needs its fact
--   H5  setting words (epithets, scenes, race, class and faction words) are bound:
--       a place word needs a cited fact in that place with time there
--   H6  other players' names only from what the player saw while grouped, and
--       only while "Name companions" is on (off in exports)
--   H7  undated game history says "the game remembers" (or "recalls")
--   H8  gaps are stated: a chapter that overlaps a gap or an off source says so
--   H9  "first" means first known, else "since the journal began"
--   H10 derived claims list their inputs (from) and every input resolves
-- Check() works on the skeleton (the template with slot values masked) for
-- the word rules, so a spell named "Healing Touch" is never flagged.
local _, E = ...

E.Story = E.Story or {}
local S = E.Story
local H = {}
S.Honesty = H

H.forbidden = { "killed by", "slain by", "because", "due to", "thanks to", "on the back of", "so that", "in order to",
	"to avenge", "damage", "healing", "dps", "hps", "crit", "parse" }

local function Has(text, phrase)
	return S.Voice.HasWord(text, phrase)
end

local function Fail(rule, why) return false, rule, why end

-- Is a place word bound to one of the cited facts (H5)?
function H.PlaceBound(set, place, cites)
	local T = S.Tuning
	local row = S.Grammar.PlaceRow(place)
	local zone = set.input.zones and set.input.zones[place]
	for _, id in ipairs(cites) do
		local fact = set.byId[id]
		if fact then
			local v = fact.v
			local here = fact.z == place or fact.s == place or v.zone == place or v.instance == place or v.place == place
				or v.battleground == place
			if here then
				if row and (row.type == "instance" or row.type == "raid" or row.type == "battleground") then return true end
				if fact.s == place and row and row.type == "subzone" then return true end
				if zone and (zone.t or 0) >= T.zoneMinSeconds then return true end
				if fact.kind == "homezone" or fact.kind == "lvhome" or fact.kind == "eraspan" then
					if (v.time or 0) >= T.zoneMinSeconds or (v.share or 0) > 0 then return true end
				end
			end
		end
	end
	return false
end

-- sentence = { text, skeleton, cites = { ids }, tone, flavour = { { kind, place, word } }, people = { names } }
-- opts = { companions = bool }
function H.Check(sentence, set, opts)
	opts = opts or {}
	local cites = sentence.cites or {}
	local skeleton = sentence.skeleton or sentence.text or ""
	local tone = sentence.tone
	-- H1, H2
	if #cites == 0 then return Fail("H1", "no cites") end
	local strong = false
	for _, id in ipairs(cites) do
		local fact = set.byId[id]
		if not fact then return Fail("H1", "cite does not resolve: " .. tostring(id)) end
		if fact.class == "T" or fact.class == "G" or fact.class == "D" then strong = true end
	end
	if not strong then return Fail("H2", "only reference facts") end
	-- H3
	for _, phrase in ipairs(H.forbidden) do
		if Has(skeleton, phrase) then return Fail("H3", "cause or combat word: " .. phrase) end
	end
	-- H4
	local lexicon = S.Voice.LexiconWords(skeleton)
	if tone ~= "bard" then
		if #lexicon > 0 then return Fail("H4", "color word outside Bard: " .. lexicon[1].word) end
		local feelings = S.Voice.FeelingWords(skeleton)
		if #feelings > 0 then return Fail("H4", "feeling word outside Bard: " .. feelings[1]) end
	else
		for _, entry in ipairs(lexicon) do
			local ok = false
			for _, id in ipairs(cites) do
				local fact = set.byId[id]
				if fact.flags[entry.flag] or (entry.flag == "keep" and fact.keep) then ok = true end
			end
			if not ok then return Fail("H4", ("'%s' needs a %s fact"):format(entry.word, entry.flag)) end
		end
	end
	-- H5
	for _, word in ipairs(sentence.flavour or {}) do
		if word.kind == "epithet" or word.kind == "scene" or word.kind == "entrance" then
			if not H.PlaceBound(set, word.place, cites) then return Fail("H5", "unbound place word for " .. tostring(word.place)) end
		elseif word.kind == "race" or word.kind == "class" then
			if tone ~= "bard" and word.kind == "race" then return Fail("H5", "race word outside Bard") end
			if not set.me[word.kind] then return Fail("H5", "no " .. word.kind .. " fact") end
		elseif word.kind == "faction" then
			if word.faction ~= set.me.faction then return Fail("H5", "faction word for the other side") end
		end
	end
	-- H6
	for _, name in ipairs(sentence.people or {}) do
		if not opts.companions then return Fail("H6", "companion names are off") end
		if not S.Facts.IsPerson(set, name) then return Fail("H6", "not a person the player grouped with: " .. name) end
	end
	-- H7
	for _, id in ipairs(cites) do
		local fact = set.byId[id]
		if fact.class == "G" and fact.v.undated then
			if not (Has(skeleton, "remembers") or Has(skeleton, "recalls") or Has(skeleton, "remember") or Has(skeleton, "recall")) then
				return Fail("H7", "undated history without 'remembers'")
			end
		end
	end
	-- H9
	if Has(skeleton, "first") then
		local known = false
		for _, id in ipairs(cites) do
			local fact = set.byId[id]
			if fact.v.firstKnown or fact.flags.firstdungeon or fact.flags.firstraid or fact.flags.firstepic or fact.flags.firstmount then known = true end
		end
		local text = sentence.text or ""
		if not known and not (text:find("since the journal began", 1, true) or text:find("in the journal", 1, true)) then
			return Fail("H9", "'first' without a known first")
		end
	end
	-- H10
	for _, id in ipairs(cites) do
		local fact = set.byId[id]
		if fact.class == "D" then
			if not fact.from or #fact.from == 0 then return Fail("H10", "derived fact without inputs: " .. id) end
			for _, input in ipairs(fact.from) do
				if not set.byId[input] then return Fail("H10", "derived input does not resolve: " .. input) end
			end
		end
	end
	return true
end

-- H8 for a whole chapter: every gap or off source that overlaps its levels
-- has a sentence citing it.
function H.CheckChapter(chapter, set)
	local cited = {}
	for _, block in ipairs({ chapter.opening or {}, chapter.closing or {} }) do
		for _, sentence in ipairs(block) do
			for _, id in ipairs(sentence.cites) do cited[id] = true end
		end
	end
	for _, para in ipairs(chapter.paragraphs or {}) do
		for _, sentence in ipairs(para) do
			for _, id in ipairs(sentence.cites) do cited[id] = true end
		end
	end
	for _, fact in ipairs(set.list) do
		local inside = fact.l and fact.l >= chapter.a and fact.l <= chapter.b
		if fact.kind == "sourceoff" then inside = fact.v.a <= chapter.b and fact.v.b >= chapter.a end
		if (fact.kind == "gap" or fact.kind == "unrecorded" or fact.kind == "sourceoff" or fact.kind == "rolled") and inside
			and not cited[fact.id] then
			return false, "H8", "gap not stated: " .. fact.id
		end
	end
	if chapter.kind == "gap" and not cited.before and set.byId.before then return false, "H8", "before-journal gap not stated" end
	return true
end
