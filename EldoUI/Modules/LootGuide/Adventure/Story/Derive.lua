-- Derived story facts. Arithmetic over
-- tracked (T) and game (G) facts only. Every D fact lists the facts it was
-- worked out from (`from`), so its hover can show the sums (H10).
local _, E = ...
local ipairs, pairs, type, tostring, setmetatable = ipairs, pairs, type, tostring, setmetatable

E.Story = E.Story or {}
local S = E.Story
local D = {}
S.Derive = D

local floor = math.floor

local function MainZone(rec)
	local best, bestT
	local keys = S.Facts.SortedKeys(rec and rec.zones)
	for _, zone in ipairs(keys) do
		local t = rec.zones[zone]
		if not bestT or t > bestT then best, bestT = zone, t end
	end
	return best, bestT
end
D.MainZone = MainZone

local function Ids(list)
	local out = {}
	for i, fact in ipairs(list) do out[i] = fact.id end
	return out
end

-- Death streaks: 3 deaths inside 20 minutes, in one zone.
local function Streaks(set, T)
	local deaths = set:Kind("death")
	local n, i = 0, 1
	while i <= #deaths do
		local group = { deaths[i] }
		local j = i + 1
		while j <= #deaths do
			local d = deaths[j]
			local sameZone = not T.deathStreakSameZone or d.z == group[1].z
			if d.t and group[1].t and d.t - group[1].t <= T.deathStreak.window and sameZone then
				group[#group + 1] = d
				j = j + 1
			else
				break
			end
		end
		if #group >= T.deathStreak.count then
			n = n + 1
			local first, last = group[1], group[#group]
			-- The subzone most of the deaths happened in.
			local count, sub = {}, nil
			for _, d in ipairs(group) do
				if d.s then
					count[d.s] = (count[d.s] or 0) + 1
					if not sub or count[d.s] > count[sub] then sub = d.s end
				end
			end
			for _, d in ipairs(group) do d.flags.inStreak = true end
			set:Add({ id = "d:streak:" .. n, kind = "deathstreak", class = "D", t = first.t, l = first.l, z = first.z, s = sub,
				from = Ids(group), flags = { deathstreak = true },
				v = { n = #group, window = (last.t or 0) - (first.t or 0), zone = first.z, subzone = sub, start = first.t, stop = last.t } })
			i = j
		else
			i = i + 1
		end
	end
end

-- Levels in a row without a death.
local function Deathless(set, T)
	local run, startLevel = 0, nil
	local function Close(lastLevel)
		if run >= T.deathlessLevels then
			local from = {}
			for n = startLevel, lastLevel do
				if set.byId["lv:" .. n] then from[#from + 1] = "lv:" .. n end
			end
			if #from == 0 then from[1] = "lv:" .. lastLevel end
			local endFact = set.byId["lv:" .. (lastLevel + 1)] or set.byId["lv:" .. lastLevel]
			set:Add({ id = "d:deathless:" .. startLevel, kind = "deathless", class = "D", t = endFact and endFact.t, l = lastLevel,
				from = from, flags = { deathless = true }, v = { n = run, a = startLevel, b = lastLevel } })
		end
		run, startLevel = 0, nil
	end
	for n = set.startedLevel, set.level - 1 do
		local rec = set.levels[n]
		if rec and rec.time and (rec.deaths or 0) == 0 then
			if not startLevel then startLevel = n end
			run = run + 1
		else
			Close(n - 1)
		end
	end
	Close(set.level - 1)
end

-- Pace: fast and slow levels against the reference curve, blended with the
-- player's own median once enough levels are known.
local function Pace(set, T)
	local ratios = {}
	for n = set.startedLevel, set.level - 1 do
		local rec = set.levels[n]
		local ref = T.pace[n]
		if rec and rec.time and ref then ratios[#ratios + 1] = rec.time / (ref * 60) end
	end
	local own = 1
	if #ratios >= T.paceMinLevels then
		table.sort(ratios)
		local mid = floor((#ratios + 1) / 2)
		own = (#ratios % 2 == 1) and ratios[mid] or (ratios[mid] + ratios[mid + 1]) / 2
	end
	local blend = (#ratios >= T.paceMinLevels) and ((1 - T.paceOwnWeight) + T.paceOwnWeight * own) or 1
	local rested = {}
	for _, fact in ipairs(set:Kind("rested")) do
		if fact.l then rested[fact.l] = rested[fact.l] or fact end
	end
	for n = set.startedLevel, set.level - 1 do
		local rec = set.levels[n]
		local ref = T.pace[n]
		if rec and rec.time and ref then
			local expected = ref * 60 * blend
			local ratio = rec.time / expected
			local kind = (ratio <= T.paceFast and "fast") or (ratio >= T.paceSlow and "slow") or nil
			if kind then
				local refId = "ref:pace:" .. n
				set:Add({ id = refId, kind = "ref", class = "R", l = n, v = { level = n, minutes = ref, expected = expected } })
				local lead = set.byId["lv:" .. (n + 1)] or set.byId["lv:" .. n]
				local from = { lead and lead.id or ("lv:" .. n), refId }
				local co = kind == "fast" and T.paceRested and rested[n]
				set:Add({ id = "d:pace:" .. n, kind = kind, class = "D", t = lead and lead.t, l = n, z = MainZone(rec),
					from = from, flags = { [kind] = true },
					v = { level = n, took = rec.time, expected = expected, ratio = ratio, rested = co and co.id or nil,
						pace = kind == "fast" and "faster than usual" or "slower than usual" } })
			end
		end
	end
end

local function QuestBursts(set, T)
	-- A burst is well above the levels around it (the median of up to five
	-- recorded levels on each side), and never under the set floor.
	local function Around(n)
		local counts = {}
		for m = n - 5, n + 5 do
			local rec = set.levels[m]
			if m ~= n and m < set.level and rec and rec.quests then counts[#counts + 1] = rec.quests end
		end
		table.sort(counts)
		return #counts >= 3 and counts[math.floor((#counts + 1) / 2)] or nil
	end
	for n = set.startedLevel, set.level do
		local rec = set.levels[n]
		local fact = set.byId["lv:" .. n]
		local median = Around(n)
		if rec and fact and median and (rec.quests or 0) >= math.max(T.questBurst, math.ceil(median * T.questBurstRatio)) then
			set:Add({ id = "d:quests:" .. n, kind = "questburst", class = "D", t = fact.t, l = n, z = MainZone(rec),
				from = { fact.id }, v = { n = rec.quests, level = n, usual = median } })
		end
	end
end

-- The first of each kind (only when the journal can know it, H9).
local function Firsts(set)
	local firstEpic, firstMount
	for _, fact in ipairs(set.list) do
		if fact.kind == "loot" and (fact.v.quality or 0) >= 4 and not firstEpic then
			firstEpic = fact
			fact.flags.firstepic = set:FirstKnown("journal", fact.l) or nil
		elseif fact.kind == "mount" and not firstMount then
			firstMount = fact
			fact.flags.firstmount = set:FirstKnown("journal", fact.l) or nil
		end
	end
	local dungeons = set:Kind("dungeon")
	if dungeons[1] and dungeons[1].v.firstKnown then dungeons[1].flags.firstdungeon = true end
	local raids = set:Kind("raid")
	if raids[1] and raids[1].v.firstKnown then raids[1].flags.firstraid = true end
	local raidBosses = set:Kind("raidboss")
	if raidBosses[1] and raidBosses[1].v.firstKnown then raidBosses[1].flags.firstraidboss = true end
end

local function MaxLevel(set)
	local fact = set.byId["lv:60"]
	if not fact then return end
	local rec = set.levels[60] or {}
	set:Add({ id = "d:max", kind = "maxlevel", class = "D", t = fact.t, l = 60, z = fact.z, from = { fact.id },
		v = { level = 60, zone = fact.z, played = rec.played } })
end

-- The same instance three or more times: one "runs" fact that the single
-- runs fold under.
local function RunSeries(set, T)
	local byInstance, order = {}, {}
	for _, fact in ipairs(set.list) do
		if (fact.kind == "run" or fact.kind == "dungeon" or fact.kind == "raid") and fact.v.instance then
			local key = S.Grammar.Fold(fact.v.instance)
			if not byInstance[key] then
				byInstance[key] = {}
				order[#order + 1] = key
			end
			local list = byInstance[key]
			list[#list + 1] = fact
		end
	end
	for _, key in ipairs(order) do
		local list = byInstance[key]
		if #list >= T.runRepeat then
			local a, b = list[1].l, list[#list].l
			-- A companion who came on every run.
			local common
			for _, name in ipairs(list[1].v.with or {}) do
				local all = true
				for i = 2, #list do
					local found = false
					for _, other in ipairs(list[i].v.with or {}) do
						if other == name then found = true end
					end
					if not found then all = false end
				end
				if all then common = name break end
			end
			for _, fact in ipairs(list) do
				if fact.kind == "run" then fact.flags.inSeries = true end
			end
			local last = list[#list]
			set:Add({ id = "d:runs:" .. key:gsub(" ", "_"), kind = "runs", class = "D", t = last.t, l = last.l, z = last.z,
				from = Ids(list), flags = { ["repeat"] = true },
				v = { instance = list[1].v.instance, n = #list, a = a, b = b, fellow = common } })
		end
	end
end

local function TopFellow(set, T)
	local best
	for _, fact in ipairs(set:Kind("met")) do
		if (fact.v.total or 0) >= T.companionNotable and (not best or fact.v.total > best.v.total) then best = fact end
	end
	if best then
		set:Add({ id = "d:topfellow", kind = "topfellow", class = "D", t = set.now, l = set.level, from = { best.id },
			flags = { trusted = best.v.total >= T.companionTrusted or nil },
			v = { fellow = best.v.fellow, duration = best.v.total } })
	end
end

-- Gaps (7+ days away) and play that happened without the journal (G3).
local function Sessions(set, T)
	local sessions = set:Kind("session")
	for i = 2, #sessions do
		local prev, cur = sessions[i - 1], sessions[i]
		local away = (cur.v.login or 0) - (prev.v.logout or prev.v.login or 0)
		if away >= T.gapDays * 86400 then
			local fact = set:Add({ id = "d:gap:" .. i, kind = "gap", class = "D", t = cur.v.login, l = cur.l, from = { prev.id, cur.id },
				v = { days = floor(away / 86400 + 0.5), start = prev.v.logout, stop = cur.v.login, level = cur.l } })
			fact.flags.gap = true
			-- Keepsakes soon after the return may be "long-awaited".
			for _, other in ipairs(set.list) do
				if other.t and other.t >= cur.v.login and other.t <= cur.v.login + T.afterGapWindow
					and (other.kind == "mount" or other.kind == "title" or other.kind == "attuned" or other.keep) then
					other.flags.afterGap = true
				end
			end
		end
		if prev.v.playedOut and cur.v.playedIn and cur.v.playedIn - prev.v.playedOut > T.unrecordedSeconds then
			set:Add({ id = "d:unrec:" .. i, kind = "unrecorded", class = "D", t = cur.v.login, l = cur.l, from = { prev.id, cur.id },
				v = { duration = cur.v.playedIn - prev.v.playedOut, level = cur.l } })
		end
	end
end

-- The last subzone recorded before a time (a port?), by binary search in
-- the time-sorted list.
local function LastSubzoneBefore(set, t)
	if not t then return nil end
	local list = set.list
	local lo, hi = 1, #list
	while lo <= hi do
		local mid = floor((lo + hi) / 2)
		local mt = list[mid].t or -1
		if mt < t then lo = mid + 1 else hi = mid - 1 end
	end
	for i = hi, 1, -1 do
		local other = list[i]
		if not other.t then return nil end
		if other.s then return other.s end
	end
	return nil
end

-- Continent crossings, from the order of first visits.
local function Crossings(set)
	local zones = set:Kind("zone")
	local lastContinent, lastZone
	local n = 0
	for _, fact in ipairs(zones) do
		local row = S.Grammar.PlaceRow(fact.z)
		local continent = row and row.continent
		if continent then
			if lastContinent and continent ~= lastContinent then
				n = n + 1
				-- The last subzone recorded before the crossing (a port?).
				local port = LastSubzoneBefore(set, fact.t)
				local vehicle = S.Voice.Vehicle(set.me.faction, port)
				set:Add({ id = "d:cross:" .. n, kind = "crossed", class = "D", t = fact.t, l = fact.l, z = fact.z, from = { fact.id },
					v = { continent = continent, zone = fact.z, fromZone = lastZone, port = vehicle and port or nil, vehicle = vehicle } })
			end
			lastContinent, lastZone = continent, fact.z
		end
	end
end

function D.Run(set)
	local T = S.Tuning
	-- set.list is time-sorted here (Facts.Compile); Crossings searches it.
	local sorted = #set.list
	Crossings(set)
	Streaks(set, T)
	Deathless(set, T)
	Pace(set, T)
	QuestBursts(set, T)
	Firsts(set)
	MaxLevel(set)
	RunSeries(set, T)
	TopFellow(set, T)
	Sessions(set, T)
	-- Merge the new (derived and reference) facts into the sorted list.
	local Order = S.Facts.Order
	local list, added = set.list, {}
	for i = sorted + 1, #list do added[#added + 1] = list[i] end
	table.sort(added, Order)
	local merged, i, j = {}, 1, 1
	while i <= sorted or j <= #added do
		if j > #added or (i <= sorted and not Order(added[j], list[i])) then
			merged[#merged + 1] = list[i]
			i = i + 1
		else
			merged[#merged + 1] = added[j]
			j = j + 1
		end
	end
	set.list = merged
	S.Facts.Reindex(set)
	return set
end
