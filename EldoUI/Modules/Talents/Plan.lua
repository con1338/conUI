-- EldoUI Talent Planner: the rules a talent plan follows.
--
-- Pure logic, no game calls: everything works on the tree the module reads
-- from the client (Modules/Talents/Talents.lua, M:ReadTree):
--
--   tree.nodes[nodeID] = { id, group, maxRanks, required, prereqs = { nodeID, ... },
--                          spellID, row, col, groupIndex }
--   tree.bySpell[spellID] = nodeID
--
-- A plan is an ordered list of node IDs, one entry per rank, in the order
-- the ranks are bought while leveling ({ 101, 101, 103, 101, ... }), plus
-- the spell ID of every node (plan.spells[nodeID]) so a plan survives a
-- hotfix that moves a talent to another node.
--
-- Classic talent rules, as the client's own conditions describe them:
--   * a node holds at most maxRanks ranks;
--   * a node needs `required` points spent in its own tree first
--     (the tier gate: 5 points per row);
--   * a node with an arrow into it needs the node at the arrow's start at
--     its full rank;
--   * the plan holds at most maxPoints points (one per level from 10).
--
--   P.Count(tree, order[, upto])          -> state { ranks, spent, total }
--   P.CanAdd(tree, state, nodeID, max)    -> ok, reason, detail
--   P.Normalize(tree, order, max)         -> order, dropped (deferred steps kept when they fit later)
--   P.Remove(tree, order, nodeID, max)    -> order or nil, reason, detail
--   P.Verify(tree, plan)                  -> remapped, dropped (hotfix check by spell ID)
--   P.FromRanks(tree, ranks, max)         -> order (a legal order for ranks the character has)
--   P.Level(index)                        -> character level of the plan's n-th point
local _, E = ...

local P = {}
E.TalentPlan = P

-- The first talent point comes at level 10, then one per level.
P.FIRST_LEVEL = 10

function P.Level(index)
	return P.FIRST_LEVEL + (index or 1) - 1
end

-- How many plan points a character of `level` can have spent.
function P.PointsAt(level)
	return math.max((level or 0) - P.FIRST_LEVEL + 1, 0)
end

function P.NewState()
	return { ranks = {}, spent = {}, total = 0 }
end

function P.Apply(tree, state, nodeID)
	local node = tree.nodes[nodeID]
	if not node then return end
	state.ranks[nodeID] = (state.ranks[nodeID] or 0) + 1
	state.spent[node.group] = (state.spent[node.group] or 0) + 1
	state.total = state.total + 1
end

-- Ranks, points per tree and the total after the first `upto` entries.
function P.Count(tree, order, upto)
	local state = P.NewState()
	if type(order) ~= "table" then return state end
	upto = math.min(upto or #order, #order)
	for index = 1, upto do P.Apply(tree, state, order[index]) end
	return state
end

-- The pick order: for each talent, the places in the plan where it takes a
-- point (1 = the plan's first point), counting only the first `upto`
-- entries. { [nodeID] = { 3, 7 } }
function P.Picks(order, upto)
	local picks = {}
	if type(order) ~= "table" then return picks end
	upto = math.min(upto or #order, #order)
	for index = 1, upto do
		local nodeID = order[index]
		local list = picks[nodeID]
		if not list then
			list = {}
			picks[nodeID] = list
		end
		list[#list + 1] = index
	end
	return picks
end

-- Whether one more rank of nodeID fits on top of `state`.
-- reason: "unknown", "max", "points", "tier" (detail = points needed in the
-- tree) or "prereq" (detail = the node that must be full first).
function P.CanAdd(tree, state, nodeID, maxPoints)
	local node = tree and tree.nodes[nodeID]
	if not node then return false, "unknown" end
	if (state.ranks[nodeID] or 0) >= node.maxRanks then return false, "max" end
	if maxPoints and state.total >= maxPoints then return false, "points" end
	if (state.spent[node.group] or 0) < (node.required or 0) then return false, "tier", node.required end
	for _, prereq in ipairs(node.prereqs or {}) do
		local other = tree.nodes[prereq]
		if other and (state.ranks[prereq] or 0) < other.maxRanks then return false, "prereq", prereq end
	end
	return true
end

-- A legal version of `order`: entries that can't go where they stand wait
-- and go in as soon as they fit (so removing an early rank only moves
-- later ones down the list); entries that never fit are dropped.
function P.Normalize(tree, order, maxPoints)
	local state = P.NewState()
	local out, waiting, dropped = {}, {}, {}
	local function TryWaiting()
		local placed = true
		while placed do
			placed = false
			for index = 1, #waiting do
				local nodeID = waiting[index]
				if P.CanAdd(tree, state, nodeID, maxPoints) then
					P.Apply(tree, state, nodeID)
					out[#out + 1] = nodeID
					table.remove(waiting, index)
					placed = true
					break
				end
			end
		end
	end
	for _, nodeID in ipairs(type(order) == "table" and order or {}) do
		if P.CanAdd(tree, state, nodeID, maxPoints) then
			P.Apply(tree, state, nodeID)
			out[#out + 1] = nodeID
			TryWaiting()
		elseif tree.nodes[nodeID] then
			waiting[#waiting + 1] = nodeID
		else
			dropped[#dropped + 1] = nodeID
		end
	end
	TryWaiting()
	for _, nodeID in ipairs(waiting) do dropped[#dropped + 1] = nodeID end
	return out, dropped
end

-- The plan without its last rank of nodeID. Refused (nil, reason, detail)
-- when a later rank needs it: "none" (no rank planned) or "needed" (detail =
-- the node that would lose its requirement).
function P.Remove(tree, order, nodeID)
	local last
	for index = #order, 1, -1 do
		if order[index] == nodeID then last = index break end
	end
	if not last then return nil, "none" end
	local copy = {}
	for index, id in ipairs(order) do
		if index ~= last then copy[#copy + 1] = id end
	end
	local fixed, dropped = P.Normalize(tree, copy)
	if #dropped > 0 then return nil, "needed", dropped[1] end
	return fixed
end

local function NodeSort(tree)
	return function(a, b)
		local na, nb = tree.nodes[a], tree.nodes[b]
		if (na.required or 0) ~= (nb.required or 0) then return (na.required or 0) < (nb.required or 0) end
		if na.groupIndex ~= nb.groupIndex then return (na.groupIndex or 0) < (nb.groupIndex or 0) end
		if na.row ~= nb.row then return (na.row or 0) < (nb.row or 0) end
		if na.col ~= nb.col then return (na.col or 0) < (nb.col or 0) end
		return a < b
	end
end

-- A legal order for a set of ranks (the character's own talents, where the
-- order they were learned in is unknown): lower rows first.
function P.FromRanks(tree, ranks, maxPoints)
	local ids = {}
	for nodeID, rank in pairs(ranks or {}) do
		if tree.nodes[nodeID] and rank > 0 then ids[#ids + 1] = nodeID end
	end
	table.sort(ids, NodeSort(tree))
	local order = {}
	for _, nodeID in ipairs(ids) do
		for _ = 1, math.min(ranks[nodeID], tree.nodes[nodeID].maxRanks) do order[#order + 1] = nodeID end
	end
	return (P.Normalize(tree, order, maxPoints))
end

-- Sort helper for staging: lower tier gates first, plan order inside.
function P.StageSort(tree)
	return function(a, b)
		local ra = tree.nodes[a.nodeID] and tree.nodes[a.nodeID].required or 0
		local rb = tree.nodes[b.nodeID] and tree.nodes[b.nodeID].required or 0
		if ra ~= rb then return ra < rb end
		return a.index < b.index
	end
end

-- Hotfix check: every planned node must still teach the spell it taught
-- when the plan was made. A talent that moved to another node follows its
-- spell; one that is gone is dropped. Updates plan.order and plan.spells.
-- Returns how many entries moved and how many were dropped.
function P.Verify(tree, plan, maxPoints)
	if type(plan) ~= "table" or type(plan.order) ~= "table" then return 0, 0 end
	plan.spells = type(plan.spells) == "table" and plan.spells or {}
	local moved, dropped = 0, 0
	local order = {}
	for _, nodeID in ipairs(plan.order) do
		local wanted = plan.spells[nodeID]
		local node = tree.nodes[nodeID]
		if node and (not wanted or node.spellID == nil or node.spellID == wanted) then
			order[#order + 1] = nodeID
		elseif wanted and tree.bySpell[wanted] then
			order[#order + 1] = tree.bySpell[wanted]
			moved = moved + 1
		else
			dropped = dropped + 1
		end
	end
	local fixed, lost = P.Normalize(tree, order, maxPoints)
	dropped = dropped + #lost
	plan.order = fixed
	P.RecordSpells(tree, plan)
	return moved, dropped
end

-- plan.spells for every node the plan holds.
function P.RecordSpells(tree, plan)
	local spells = {}
	for _, nodeID in ipairs(plan.order or {}) do
		local node = tree.nodes[nodeID]
		if node and node.spellID then spells[nodeID] = node.spellID end
	end
	plan.spells = spells
end
