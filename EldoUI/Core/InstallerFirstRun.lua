local _, E = ...

---------------------------------------------------------------------------
-- The first load on a fresh profile: EldoUI's chat and action bars
-- (design decision). A character that never ran the setup gets EldoUI's
-- chat windows and action bars at once, with the switches the Blizzard UI
-- step recommends for them, so the screen shows EldoUI from the first
-- login while the setup is still open. Every other Blizzard element stays
-- as Blizzard made it until the setup's Blizzard UI step.
--
--   * only a fresh profile (needsSetup), once: a profile set up before
--     (its mark cleared by Finish or Skip) is never changed (alt safety)
--   * an element that is on already keeps the switches the player set
--   * the switches change through E:SetBlizzardElement, so the modules
--     re-apply out of combat (E:RunOutOfCombat) and nothing asks for a
--     reload (taking a Blizzard frame over needs none)
--   * the Blizzard UI step can still pick "Blizzard's own UI", which puts
--     Blizzard's chat and bars back
---------------------------------------------------------------------------
local FirstRun = {}
E.InstallerFirstRun = FirstRun

-- The modules whose Blizzard elements are taken over at the first load.
FirstRun.OWNERS = { ActionBars = true, Chat = true }

-- The element ids those modules ask to change, in catalog order.
function FirstRun.Elements()
	local list = {}
	for _, id in ipairs(E.blizzardElementOrder or {}) do
		local data = E.blizzardElements[id]
		for _, handler in ipairs(data and data.handlers or {}) do
			if handler.owner and FirstRun.OWNERS[handler.owner] and handler.install then
				list[#list + 1] = id
				break
			end
		end
	end
	return list
end

-- Turn the elements on with the recommended switches. Returns how many
-- elements were turned on (0 when the profile is not fresh or was done).
function FirstRun.TakeOver()
	local db = E.db
	if not (db and db.needsSetup) or db.blizzardTakeover then
		if db then db.blizzardTakeoverPending = nil end
		return 0
	end
	local Recommended = E.Installer and E.Installer.RecommendedTarget
	if not Recommended then return 0 end
	-- Keep only the writes not yet acknowledged by their owner. A setter
	-- can fail after changing the saved state; retry it even when that
	-- state already says enabled. Completed elements and their choices stay.
	local pending = type(db.blizzardTakeoverPending) == "table" and db.blizzardTakeoverPending or {}
	db.blizzardTakeoverPending = pending
	local ids, eligible = FirstRun.Elements(), {}
	for _, id in ipairs(ids) do eligible[id] = true end
	for id, target in pairs(pending) do
		local data = eligible[id] and E.blizzardElements[id]
		local valid = data and type(target) == "table" and target.enabled == true
		if valid then
			for key, value in pairs(target) do
				if type(value) ~= "boolean" or (key ~= "enabled" and not data.allowed[key]) then valid = false; break end
			end
		end
		if not valid then pending[id] = nil end
	end
	local count, complete = 0, true
	for _, id in ipairs(ids) do
		if E.db ~= db or not db.needsSetup then return count end
		local state = E:BlizzardState(id)
		local target = pending[id]
		if not target and state and not state.enabled then
			local recommended = Recommended(id)
			if type(recommended) == "table" then
				target = { enabled = true }
				for key, value in pairs(recommended) do
					if key ~= "enabled" and (state[key] and true or false) ~= (value and true or false) then target[key] = value and true or false end
				end
				pending[id] = target
			else complete = false end
		end
		if not state then complete = false end
		if target then
			-- Switches first, while the element is still off: nothing
			-- applies until it is turned on below.
			local ready = true
			for key, value in pairs(target) do
				if key ~= "enabled" then
					local written = E:SetBlizzardElement(id, key, value, true)
					local observed = E.db == db and E:BlizzardState(id)
					if written ~= true or not observed or (observed[key] and true or false) ~= value then
						ready, complete = false, false
						break
					end
					target[key] = nil
				end
			end
			if ready then
				local written = E:SetBlizzardElement(id, "enabled", true, true)
				local observed = E.db == db and E:BlizzardState(id)
				if written == true and observed and observed.enabled then
					pending[id], count = nil, count + 1
				else complete = false end
			end
		end
	end
	if complete and next(pending) == nil then
		db.blizzardTakeover, db.blizzardTakeoverPending = true, nil
	end
	return count
end
