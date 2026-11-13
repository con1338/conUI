-- EldoUI Loot Sim: the jobs.
--
--   Character  your DPS with what you wear, the damage of each ability and
--              the value of one more point of each stat
--   Item       one item against what you wear in its slot (item check,
--              tooltips, the context menu's Simulate)
--   BiS        a quick pass over the best items of your loot list per slot
--              (by stat weights), exact runs of the top picks, then the best
--              set and its gain over what you wear (one-minute fights)
--   Sets       what you wear, Best in Slot and your two plan sets as DPS
--
-- Comparisons use paired dice: the same seeds for both gear sets, so the
-- error of a difference is small. Errors are 95 % ranges (1.96 standard
-- errors). Results go to EldoUIDB.lootGuide[character].sim (LootGuide's
-- Sim.lua) with the setup they were made for; a change of level, gear,
-- talents, fight settings or loot list makes them outdated.
local _, S = ...
local Engine, Gear, Reader, D = S.Engine, S.Gear, S.Reader, S.Data
local Scheduler = S.Scheduler

local Jobs = {}
S.Jobs = Jobs

local BIS_LENGTH = 60
local SEED = 4242

-- Fights per run.
Jobs.COUNTS = { char = 120, item = 160, sets = 120, quick = 30, exact = 120, final = 160, perGroup = 5, top = 3 }
local COUNTS = Jobs.COUNTS

local function LG()
	return S.E and S.E.LootGuide
end

---------------------------------------------------------------------------
-- Statistics
---------------------------------------------------------------------------
local function MeanErr(values)
	local n = #values
	if n == 0 then return 0, 0 end
	local sum = 0
	for _, value in ipairs(values) do sum = sum + value end
	local mean = sum / n
	if n < 2 then return mean, 0 end
	local squares = 0
	for _, value in ipairs(values) do squares = squares + (value - mean) ^ 2 end
	local sd = math.sqrt(squares / (n - 1))
	return mean, 1.96 * sd / math.sqrt(n)
end
Jobs.MeanErr = MeanErr

-- Fight settings: target level and length (from the window's choices).
function Jobs.Settings(length)
	local lg = LG()
	if lg and lg.SimSettings then return lg:SimSettings(length) end
	local ui = lg and lg.UI and lg:UI() or {}
	local level = UnitLevel and UnitLevel("player") or 60
	if issecretvalue and issecretvalue(level) then level = 60 end
	local plus = 0
	for _, target in ipairs(D.TARGETS) do
		if target.key == (ui.simTarget or "boss") then plus = target.plus end
	end
	return { targetLevel = math.min(63, (tonumber(level) or 60) + plus), length = length or tonumber(ui.simLength) or 180 }
end

-- n fights of one sheet: mean DPS, error, per-source damage per second.
local function Runs(sheet, model, settings, n, step)
	local values, sources = {}, {}
	for index = 1, n do
		local result = Engine.Simulate(sheet, model, { seed = SEED + index, length = settings.length,
			targetLevel = settings.targetLevel, hook = Scheduler.Check })
		values[index] = result.dps
		for key, source in pairs(result.sources) do
			local entry = sources[key] or { damage = 0, count = 0, crits = 0, misses = 0 }
			entry.damage = entry.damage + source.damage
			entry.count = entry.count + source.count
			entry.crits = entry.crits + source.crits
			entry.misses = entry.misses + source.misses
			sources[key] = entry
		end
		if step then step() end
		Scheduler.Check()
	end
	local mean, err = MeanErr(values)
	for _, entry in pairs(sources) do
		entry.dps = entry.damage / n / settings.length
		entry.share = mean > 0 and entry.dps / mean or 0
		entry.count = entry.count / n
		entry.crits = entry.crits / n
		entry.misses = entry.misses / n
	end
	return mean, err, sources
end
Jobs.Runs = Runs

-- Paired: sheet b against sheet a on the same seeds. Returns the mean
-- difference, its error and b's mean.
local function Paired(a, b, model, settings, n, step)
	local diffs, totals = {}, {}
	for index = 1, n do
		local opts = { seed = SEED + index, length = settings.length, targetLevel = settings.targetLevel, hook = Scheduler.Check }
		local one = Engine.Simulate(a, model, opts)
		local two = Engine.Simulate(b, model, opts)
		diffs[index] = two.dps - one.dps
		totals[index] = two.dps
		if step then step() end
		Scheduler.Check()
	end
	local diff, err = MeanErr(diffs)
	return diff, err, (MeanErr(totals))
end
Jobs.Paired = Paired

---------------------------------------------------------------------------
-- Preparing: read the character and pick the model
---------------------------------------------------------------------------
function Jobs.Prepare()
	local sheet, report = Reader.Read()
	if not sheet then return nil, report end
	local model, variant = Engine.ModelFor(sheet)
	if not model then return nil, variant end
	report.variant, report.variantTitle = variant, model.title
	return { sheet = sheet, report = report, model = model, variant = variant }
end

local function Store()
	local lg = LG()
	return lg and lg.SimStore and lg:SimStore() or {}
end

local function SetupKey(settings)
	local lg = LG()
	return lg and lg.SimSetupKey and lg:SimSetupKey(settings) or "setup"
end

local function Done(kind, result)
	local lg = LG()
	if lg and lg.OnSimDone then lg:OnSimDone(kind, result) end
end

---------------------------------------------------------------------------
-- Character
---------------------------------------------------------------------------
-- Stats worth one more point, per kind of character.
Jobs.STATS = {
	physical = { { "str", 20 }, { "agi", 20 }, { "ap", 40 }, { "crit", 1 }, { "hit", 1 } },
	caster = { { "sp", 25 }, { "spellCrit", 1 }, { "spellHit", 1 }, { "int", 20 } },
}

function Jobs.StatKinds(prepared)
	local model, sheet = prepared.model, prepared.sheet
	local list = {}
	if model.melee or model.autoShot then
		for _, entry in ipairs(Jobs.STATS.physical) do list[#list + 1] = entry end
		if sheet.class == "PALADIN" or sheet.class == "SHAMAN" then list[#list + 1] = { "sp", 25 } end
	else
		for _, entry in ipairs(Jobs.STATS.caster) do list[#list + 1] = entry end
	end
	return list
end

function Jobs.Character(prepared, n)
	n = n or COUNTS.char
	local settings = Jobs.Settings()
	local stats = Jobs.StatKinds(prepared)
	local total = n + #stats * math.floor(n / 2)
	local done = 0
	local job = { name = "character", kind = "char", settings = settings }
	local function Step()
		done = done + 1
		job.progress = done / total
	end
	job.run = function()
		local sheet, model = prepared.sheet, prepared.model
		local mean, err, sources = Runs(sheet, model, settings, n, Step)
		local values = {}
		for _, entry in ipairs(stats) do
			local more = Gear.AddStats(sheet, { [entry[1]] = entry[2] })
			local diff, diffErr = Paired(sheet, more, model, settings, math.floor(n / 2), Step)
			values[#values + 1] = { stat = entry[1], amount = entry[2], perPoint = diff / entry[2], err = diffErr / entry[2] }
		end
		local record = { dps = mean, err = err, sources = sources, values = values, report = prepared.report,
			key = SetupKey(settings), at = time(), length = settings.length, targetLevel = settings.targetLevel, fights = n }
		Store().char = record
		job.result = record
		Done("char", record)
	end
	return job
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
local function SlotsFor(itemID, sheet)
	local lg = LG()
	local slots = lg and lg.ItemSlots and lg:ItemSlots(itemID)
	if not slots then return {} end
	local out = {}
	for _, slot in ipairs(slots) do
		if slot ~= 17 or sheet.oh or not (sheet.mh and sheet.mh.twoHand) then out[#out + 1] = slot end
	end
	-- A one-hander for someone who cannot dual wield goes in the main hand.
	if #out > 1 and out[1] == 16 and not sheet.oh then out = { 16 } end
	return out
end

-- Best slot for an item: diff, err, slot (or nil when it has no numbers).
local function RateItem(prepared, itemID, settings, n, step)
	local best
	for _, slot in ipairs(SlotsFor(itemID, prepared.sheet)) do
		local changed, missing = Gear.Apply(prepared.sheet, { [slot] = itemID })
		if #missing == 0 then
			local diff, err = Paired(prepared.sheet, changed, prepared.model, settings, n, step)
			if not best or diff > best.dps then best = { dps = diff, err = err, slot = slot } end
		end
	end
	return best
end

function Jobs.Item(prepared, itemID, n)
	n = n or COUNTS.item
	local settings = Jobs.Settings(BIS_LENGTH)
	local slots = #SlotsFor(itemID, prepared.sheet)
	local total, done = math.max(1, slots * n), 0
	local job = { name = "item", kind = "item", itemID = itemID, settings = settings }
	job.run = function()
		local best = RateItem(prepared, itemID, settings, n, function()
			done = done + 1
			job.progress = done / total
		end)
		local store = Store()
		store.items = store.items or {}
		if best then
			best.key, best.at = SetupKey(settings), time()
			store.items[itemID] = best
			if store.noNumbers then store.noNumbers[itemID] = nil end
		else
			store.noNumbers = store.noNumbers or {}
			store.noNumbers[itemID] = true
		end
		job.result = best and { itemID = itemID, dps = best.dps, err = best.err, slot = best.slot }
		Done("item", job.result)
	end
	return job
end

---------------------------------------------------------------------------
-- Best in Slot
---------------------------------------------------------------------------

local function WaitForRanking()
	local lg = LG()
	if not (lg and lg.RankAll) then return end
	local rank = lg:RankAll()
	local tries = 0
	while not rank and tries < 3000 do
		coroutine.yield()
		tries = tries + 1
		rank = lg:RankAll()
	end
	return rank
end

function Jobs.BiS(prepared)
	local settings = Jobs.Settings(BIS_LENGTH)
	local job = { name = "bis", kind = "bis", settings = settings }
	job.run = function()
		local lg = LG()
		local QUICK, EXACT, FINAL, PER_GROUP, TOP = COUNTS.quick, COUNTS.exact, COUNTS.final, COUNTS.perGroup, COUNTS.top
		local rank = WaitForRanking()
		local sheet, model = prepared.sheet, prepared.model
		local worn = sheet.gear or {}
		-- Candidates per slot.
		local candidates, noNumbers = {}, {}
		for group, list in pairs(rank and rank.groups or {}) do
			local count = 0
			for _, entry in ipairs(list) do
				if count >= PER_GROUP then break end
				local itemID = entry.itemID
				local owned = false
				for _, id in pairs(worn) do if id == itemID then owned = true end end
				if not owned then
					if Gear.Stats(itemID) then
						count = count + 1
						for _, slot in ipairs(SlotsFor(itemID, sheet)) do
							candidates[#candidates + 1] = { itemID = itemID, slot = slot, group = group }
						end
					else
						noNumbers[#noNumbers + 1] = itemID
					end
				end
			end
		end
		local total = #candidates * QUICK + TOP * 17 * EXACT + FINAL
		local done = 0
		local function Step()
			done = done + 1
			job.progress = math.min(0.99, done / math.max(total, 1))
		end
		-- Quick pass.
		for _, candidate in ipairs(candidates) do
			local changed, missing = Gear.Apply(sheet, { [candidate.slot] = candidate.itemID })
			if #missing == 0 then
				candidate.dps, candidate.err = Paired(sheet, changed, model, settings, QUICK, Step)
			else
				done = done + QUICK
			end
		end
		-- Exact runs of the top picks per slot.
		local bySlot = {}
		for _, candidate in ipairs(candidates) do
			if candidate.dps then
				bySlot[candidate.slot] = bySlot[candidate.slot] or {}
				table.insert(bySlot[candidate.slot], candidate)
			end
		end
		local store = Store()
		store.items = store.items or {}
		local key = SetupKey(settings)
		for slot, list in pairs(bySlot) do
			table.sort(list, function(a, b) return a.dps > b.dps end)
			for index = 1, math.min(TOP, #list) do
				local candidate = list[index]
				local changed = Gear.Apply(sheet, { [slot] = candidate.itemID })
				candidate.dps, candidate.err = Paired(sheet, changed, model, settings, EXACT, Step)
				candidate.exact = true
			end
			table.sort(list, function(a, b) return a.dps > b.dps end)
			for _, candidate in ipairs(list) do
				local old = store.items[candidate.itemID]
				if not old or old.key ~= key or candidate.exact or (old.dps or 0) < candidate.dps then
					store.items[candidate.itemID] = { dps = candidate.dps, err = candidate.err, slot = slot, key = key, at = time() }
				end
			end
		end
		-- The best set: the best pick per slot (an item only once).
		local set, gains, used = {}, {}, {}
		local slots = {}
		for slot in pairs(bySlot) do slots[#slots + 1] = slot end
		table.sort(slots)
		for _, slot in ipairs(slots) do
			for _, candidate in ipairs(bySlot[slot]) do
				if candidate.dps > 0 and not used[candidate.itemID] then
					set[slot], gains[slot] = candidate.itemID, { itemID = candidate.itemID, dps = candidate.dps, err = candidate.err }
					used[candidate.itemID] = true
					break
				end
			end
		end
		-- A two-hander against a main hand plus off hand.
		if set[16] then
			local stats = Gear.Stats(set[16])
			if stats and stats.weapon and stats.weapon.twoHand and set[17] then
				local pair = (gains[17] and gains[17].dps or 0)
				local oneHand
				for _, candidate in ipairs(bySlot[16]) do
					local s = Gear.Stats(candidate.itemID)
					if s and s.weapon and not s.weapon.twoHand then oneHand = candidate break end
				end
				if oneHand and oneHand.dps + pair > gains[16].dps then
					set[16], gains[16] = oneHand.itemID, { itemID = oneHand.itemID, dps = oneHand.dps, err = oneHand.err }
				else
					set[17], gains[17] = nil, nil
				end
			end
		end
		local final, missing = Gear.Apply(sheet, set)
		local setGain, setErr, setDps = 0, 0, nil
		if next(set) and #missing == 0 then
			setGain, setErr, setDps = Paired(sheet, final, model, settings, FINAL, Step)
		end
		local full = {}
		for slot, itemID in pairs(worn) do full[slot] = itemID end
		for slot, itemID in pairs(set) do full[slot] = itemID end
		if set[17] == nil and Gear.IsTwoHand(set[16]) then full[17] = nil end
		local spec = sheet.spec or "none"
		store.bis = store.bis or {}
		store.bis[spec] = { level = sheet.level, key = key, listKey = lg and lg.ListKey and lg:ListKey() or "", set = full,
			changes = set, gains = gains, setGain = setGain, setErr = setErr, setDps = setDps, at = time(), noNumbers = noNumbers,
			variant = prepared.variant }
		job.result = store.bis[spec]
		job.progress = 1
		Done("bis", job.result)
	end
	return job
end

---------------------------------------------------------------------------
-- Sets
---------------------------------------------------------------------------
-- sets: { { key, title, changes = { slot -> itemID } } }
function Jobs.Sets(prepared, sets, n)
	n = n or COUNTS.sets
	local settings = Jobs.Settings()
	local job = { name = "sets", kind = "sets", settings = settings }
	job.run = function()
		local sheet, model = prepared.sheet, prepared.model
		local total, done = math.max(1, #sets * n), 0
		local function Step()
			done = done + 1
			job.progress = done / total
		end
		local results = {}
		for _, entry in ipairs(sets) do
			local changed, missing = Gear.Apply(sheet, entry.changes or {})
			local result = { key = entry.key, title = entry.title, missing = missing }
			if #missing == 0 then
				local mean, err, sources = Runs(changed, model, settings, n, Step)
				result.dps, result.err, result.sources = mean, err, sources
			else
				done = done + n
			end
			results[#results + 1] = result
		end
		local store = Store()
		store.sets = { results = results, key = SetupKey(settings), at = time(), length = settings.length, targetLevel = settings.targetLevel }
		job.result = store.sets
		Done("sets", store.sets)
	end
	return job
end
