-- Story engine set values.
--
-- The story engine is plain Lua with no game calls, so it runs without
-- any frames. Its parts share E.Story:
--   Tuning   this file: every set value, the line-kind weights and presets
--   Grammar  numbers, durations, plurals, lists, places, articles
--   Voice    the WoW voice: faction, race, class words and the bound lexicon
--   Facts    compiles typed facts (T tracked, G game, D derived, R reference)
--   Derive   derived facts (streaks, pace, gaps, firsts, crossings)
--   Plan     level chapters, story chapters, eras, lead picking, river data
--   Pick     the deterministic seed and the no-repeat rules V1-V3
--   Honesty  the checker every sentence passes (H1-H10)
--   Render   facts to sentences with citations; the only part that writes text
--   Banks    the phrase banks (Banks/Ledger.lua defines every beat)
--
-- These values are constants, not options: changing one is a code change.
-- The player's knobs are the Story settings (tone, length, pronoun,
-- companions, salt).
local _, E = ...

E.Story = E.Story or {}
local S = E.Story

local T = {}
S.Tuning = T
E.StoryTuning = T

-- What counts as notable ---------------------------------------------------
T.zoneShare = 0.35            -- a zone "holds" a chapter with >= 35 % of its played time
T.zoneMinSeconds = 900        -- a zone with less than 15 min in a chapter gets no mood words
T.zoneHold = 2                -- the main zone must change for 2 levels before a new story chapter
T.deathStreak = { count = 3, window = 1200 }   -- 3 deaths inside 20 min = one streak fact
T.deathStreakSameZone = true
T.deathlessLevels = 8         -- 8 levels in a row without a death is worth a sentence
T.lootNotable = 3             -- rare (blue) finds can get a sentence; epics lead
T.lootLead = 4
T.gapDays = 7                 -- a break of 7+ days between sessions is a "gap" fact
T.unrecordedSeconds = 600     -- /played that grew by more than 10 min between sessions
T.questBurst = 12             -- a burst is at least 12 quests at one level
T.questBurstRatio = 1.6       -- and at least 1.6 times the character's median level
T.companionNotable = 3600     -- 1 h together before a companion counts as notable
T.companionSteps = { 3600, 3 * 3600, 10 * 3600 }   -- "together" rows at 1 h, 3 h, 10 h
T.companionTrusted = 3 * 3600 -- "trusted", "old friend" need 3 h together
T.runRepeat = 3               -- the same instance 3+ times is a "runs" fact
T.restedNotable = 0.5         -- rested pool grew by half a level or more
T.repLead = 6                 -- standing 6 (Honored) and up can lead
T.afterGapWindow = 2 * 86400  -- "long-awaited" may only touch facts this soon after a gap

-- Pace: typical played minutes per level (EldoUI reference, our own estimate
-- for a steady quester). Only used to say "faster" or "slower than usual";
-- the hover always shows the minutes.
T.pace = { [1] = 10, [2] = 12, [3] = 14, [4] = 16, [5] = 18, [6] = 20, [7] = 22, [8] = 25, [9] = 28 }
T.paceFill = { { 10, 19, 35, 80 }, { 20, 29, 85, 125 }, { 30, 39, 130, 165 }, { 40, 49, 170, 215 }, { 50, 59, 220, 290 } }
for _, band in ipairs(T.paceFill) do
	local a, b, lo, hi = band[1], band[2], band[3], band[4]
	for level = a, b do
		T.pace[level] = math.floor(lo + (hi - lo) * (level - a) / (b - a) + 0.5)
	end
end
T.paceFast = 0.6
T.paceSlow = 1.7
T.paceOwnWeight = 0.5
T.paceMinLevels = 8
T.paceRested = true          -- a fast level that started well rested may cite it (co-occurrence, never a cause)

-- Shape ----------------------------------------------------------------------
T.eraBands = { 1, 10, 20, 30, 40, 50, 60 }
T.eraSnap = 2
T.chapterMinLevels = 2
T.chapterMaxLevels = 6
T.chapterBreakWeight = 80
T.chapterBreakKinds = { dungeon = true, raid = true, attuned = true, maxlevel = true }
T.beatsPerChapter = { short = 3, standard = 5, long = 8 }
T.minBeatScore = 12
T.paraBeats = 3
T.paraShapes = { { 3, 2 }, { 2, 3 }, { 3, 3 }, { 2, 2 } }
T.firstBonus, T.keepBonus, T.leadRepeat = 20, 15, 0.6
T.leadOrder = { "maxlevel", "attuned", "raidboss", "boss", "dungeon", "raid", "loot", "mount", "title",
	"deathstreak", "gap", "topfellow", "slow", "fast", "zone", "rep", "questburst" }
-- At most this many beats of one kind per story chapter.
T.kindCap = { death = 1, quest = 1, run = 2, rep = 2, loot = 2, boss = 2, spell = 1, recipe = 1, subzone = 1,
	gear = 1, flight = 1, together = 1, met = 2, gather = 1, rare = 1, bossagain = 1, skill = 1 }

-- Variation --------------------------------------------------------------------
T.variantWindow = 4
T.stemWords = 2
T.nameRepeat = 2

-- Line-kind weights. A function gets the fact.
T.weight = {
	level = 8, maxlevel = 100, zone = 45, dungeon = 80, raid = 95, raidboss = 95,
	death = 10, deathstreak = 60, deathless = 45,
	boss = function(f) return f.v.first and 90 or 5 end,
	bossagain = 5,
	loot = function(f) local q = f.v.quality or 0 return q >= 4 and 75 or (q >= 3 and 35 or 0) end,
	rep = function(f) return (f.v.standingID or 0) >= T.repLead and 45 or 10 end,
	spell = 5, recipe = 5, profession = 25,
	skill = function(f) return f.v.mastered and 55 or 20 end,
	mount = 70, pet = 20, respec = 15, flight = 12, goal = 40,
	run = 20, runs = 50, pvpwin = function(f) return f.flags.first and 30 or 8 end, pvploss = 8,
	quest = 3, questchain = 50, dungeonquest = 35, groupquest = function(f) return f.flags.first and 40 or 25 end,
	questburst = 25, attunestep = 40, attuned = 85, challenge = 35, legacylevel = 40, title = 60,
	explored = 30, subzone = 2, hearth = 8,
	gear = function(f) return (f.v.quality or 0) >= 4 and 60 or 12 end,
	wish = 55,
	met = function(f) return (f.v.total or 0) >= T.companionNotable and 50 or 15 end,
	together = 35, topfellow = 45, rested = 10, gap = 50, gather = 15, farm = 10, rare = 12, cinematic = 8,
	guild = 30, note = 20, fast = 40, slow = 40, homezone = 30, crossed = 30,
	chdeaths = 20, chquests = 14,
}

-- Detail presets: which preset shows a kind's row.
-- E Essentials, S Storyteller (default), C Chronicler. "all" = always.
local ALL, ESC, SC, C = "ESC", "ESC", "SC", "C"
T.presets = {
	level = ALL, zone = SC, dungeon = SC, death = ESC, deathstreak = ESC, boss = ESC, loot = SC, rep = SC,
	spell = SC, recipe = SC, profession = SC, skill = SC, mount = ESC, pet = SC, respec = SC, flight = SC,
	goal = ESC, run = SC, bossagain = C, raid = ALL, raidboss = ALL, pvpwin = SC, pvploss = SC, quest = C,
	questchain = SC, dungeonquest = SC, groupquest = SC, attunestep = SC, attuned = ALL, challenge = SC,
	legacylevel = SC, title = ESC, explored = SC, subzone = C, hearth = C, gear = SC, wish = ESC, met = SC,
	together = SC, rested = C, gap = ALL, gather = C, farm = C, rare = C, cinematic = C, guild = SC, note = ALL,
	maxlevel = ALL, crossed = SC, unrecorded = ALL, sourceoff = ALL,
}
T.presetLetter = { essentials = "E", storyteller = "S", chronicler = "C" }

-- Kinds that never get a beat in the Book (their row is enough) and kinds
-- that are always stated when they fall in a chapter (H8 gaps).
T.forced = { gap = true, unrecorded = true, sourceoff = true, rolled = true }

-- The phrase-bank registry. Banks/Ledger.lua defines every beat; the tone
-- files add their variants by beat id.
S.Banks = S.Banks or { beats = {}, order = {}, tones = {} }
local B = S.Banks
B.toneList = { "ledger", "chronicle", "bard" }
B.prose = { chronicle = true, bard = true }

function B:Define(id, def)
	if not self.beats[id] then self.order[#self.order + 1] = id end
	def.id = id
	self.beats[id] = def
	if def.ledger then self:Tone("ledger", { [id] = def.ledger }) end
end

function B:Tone(tone, entries)
	local bank = self.tones[tone]
	if not bank then
		bank = {}
		self.tones[tone] = bank
	end
	for id, list in pairs(entries) do bank[id] = list end
end
