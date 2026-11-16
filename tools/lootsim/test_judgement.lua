-- Offline test: the Loot Sim rolls Judgement as a ranged attack.
-- Run from the repository root:
--   lua5.1 tools/lootsim/test_judgement.lua
-- WoW: Forever hotfix of 11 November 2026: Judgement is "now considered a Ranged Attack" and "uses the Paladin's
-- Ranged Hit chance". The sim rolled it with spell hit before. Since EldoUI 0.7.3000 the sim does this itself
-- (Data.lua: hitType = "ranged", Engine.lua: Fight:SpellHits); the fork's own rule (C8) is gone and this test
-- checks EldoUI's. It loads the real sim files (they need nothing of the game) and checks that Judgement misses at
-- the ranged miss chance from hit, does not care about spell hit, and that a spell without hitType "ranged"
-- still rolls spell hit. A full fight with the "Seal of Righteousness, judged and renewed" variant runs and judges.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/lootsim/") or "./"

local passed, failed = 0, 0
local function Check(ok, what)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL: " .. what)
	end
end

local S = {}
for _, path in ipairs({ "Rng.lua", "Combat.lua", "Data.lua", "Engine.lua", "Classes/Melee.lua" }) do
	local chunk = assert(loadfile(ROOT .. "EldoUI_LootSim/" .. path))
	chunk("EldoUI_LootSim", S)
end
local C, D, Engine = S.Combat, S.Data, S.Engine

local function Sheet(hit, spellHit)
	return {
		class = "PALADIN", level = 60, hit = hit, spellHit = spellHit, crit = 5, spellCrit = 5, spellPower = 0,
		ap = 1000, str = 200,
		mh = { min = 200, max = 300, speed = 3.5, skill = 300, twoHand = true, kind = "twohand" },
		power = 5000, maxPower = 5000, regen = { idle = 10, casting = 5 },
		spells = { judgement = {}, sealOfRighteousness = {} },
	}
end

-- Misses out of `rolls` landing checks of `spell` (seeded, so always the same count).
local function Misses(sheet, spell, rolls)
	local fight = Engine.New(sheet, nil, { seed = 7, targetLevel = 63 })
	local misses = 0
	for _ = 1, rolls do
		if not fight:SpellHits(spell) then misses = misses + 1 end
	end
	return misses / rolls * 100
end

local judgement = D.SPELLS.PALADIN.judgement
Check(judgement.hitType == "ranged", "Data: Judgement rolls ranged hit (hitType)")

-- Ranged miss against a level 63 dummy with weapon skill 300 (diff 15): 5 + 15 * 0.2 = 8 %, hit counts one point less.
local expected = C.MissChance(C.SkillDiff(63, 300), 0, false)
Check(math.abs(expected - 8) < 1e-9, "Combat: ranged miss at diff 15 is 8 %")

local ROLLS = 20000
local rate = Misses(Sheet(0, 99), judgement, ROLLS)
Check(math.abs(rate - 8) < 1, ("Judgement with no hit and much spell hit misses about 8 %% (got %.2f %%)"):format(rate))

rate = Misses(Sheet(9, 0), judgement, ROLLS)
Check(rate == 0, ("Judgement with 9 %% hit and no spell hit never misses (got %.2f %%)"):format(rate))

rate = Misses(Sheet(4, 0), judgement, ROLLS)
Check(math.abs(rate - 5) < 1, ("Judgement with 4 %% hit misses about 5 %% (got %.2f %%)"):format(rate))

-- The same spell without the ranged hit type: spell hit decides (level 63 dummy: 83 % to hit with no spell hit).
local spellOnly = setmetatable({ hitType = false }, { __index = judgement })
rate = Misses(Sheet(9, 0), spellOnly, ROLLS)
Check(math.abs(rate - 17) < 1, ("a spell without the ranged hit type misses at spell hit, about 17 %% (got %.2f %%)"):format(rate))
rate = Misses(Sheet(0, 17), spellOnly, ROLLS)
Check(rate == 0, ("a spell without the ranged hit type and 17 %% spell hit never misses (got %.2f %%)"):format(rate))

-- A whole fight: the judged Seal of Righteousness variant still runs and judges.
local sheet = Sheet(0, 99)
sheet.variant = "righteousness"
local model, key = Engine.ModelFor(sheet)
Check(model ~= nil and key == "righteousness", "Engine: the righteousness variant is found")
if model then
	local fight = Engine.New(sheet, model, { seed = 3, targetLevel = 63, length = 300 })
	local ok, err = pcall(fight.Run, fight)
	Check(ok, "a 300 s fight runs: " .. tostring(err))
	local source = fight.sources.judgement
	Check(source and source.count > 0, "the fight judges")
	Check(source and source.misses > 0 and source.misses < source.count, "some Judgements miss with no hit")
end

print(("%d checks passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
