-- Talent Planner: /eui probe talents, a record of the talent trees the
-- game hands out, for testers who compare game builds.
--
-- For every class it asks the client for that class's tree through the
-- same reader the planner uses (the view loadout for the class's spec) and
-- keeps, per talent: node ID, spell ID, entry ID, maximum ranks, position
-- (row, column and the raw posX and posY), its tree and the points that
-- tree needs before the talent opens, plus the talents it follows.
--
-- The record is kept in the account's saved data under
-- EldoUIDB.talentProbe and is written to the SavedVariables file on
-- /reload or logout. "/eui probe talents clear" removes it.
--
-- Read-only: it never learns, refunds or stages a talent, and it works
-- with the Talent Planner on or off. Nothing runs unless the player types
-- the command.
local _, E = ...
local L = E.L
local Key = E.Key
local M = E:GetModule("Talents")

local PROBE_VERSION = 1

local function Line(text) E:Print(text) end

-- The record sits in the saved file under "talentProbe"; SaveRecord is the
-- only place that writes it (nil removes it, for "clear").
E:RegisterStore("talentProbe", { owner = "Talents", accessor = "SaveRecord" })

local function SaveRecord(record)
	if type(EldoUIDB) == "table" then EldoUIDB.talentProbe = record end
end

local function BuildText()
	local version, build, _, interface = GetBuildInfo()
	return tostring(version or "?"), tostring(build or "?"), tonumber(interface)
end

-- One tree as plain saved data: groups and nodes in reading order.
local function Record(tree)
	local groups = {}
	for index, group in ipairs(tree.groups or {}) do
		groups[index] = { groupID = group.groupID, name = group.name, orderIndex = group.orderIndex }
	end
	local nodes = {}
	for _, nodeID in ipairs(tree.order or {}) do
		local node = tree.nodes[nodeID]
		if node then
			local prereqs = {}
			for index, id in ipairs(node.prereqs or {}) do prereqs[index] = id end
			table.sort(prereqs)
			nodes[#nodes + 1] = {
				id = node.id, spellID = node.spellID, entryID = node.entryID, maxRanks = node.maxRanks,
				group = node.group, tree = node.groupIndex, required = node.required or 0,
				row = node.row, col = node.col, posX = node.posX, posY = node.posY,
				prereqs = (#prereqs > 0) and prereqs or nil,
			}
		end
	end
	return {
		status = "ok", specID = tree.specID, treeID = tree.treeID, maxLevel = tree.maxLevel,
		maxPoints = tree.maxPoints, rows = tree.rows, cols = tree.cols, fromView = tree.fromView and true or false,
		groups = groups, nodes = nodes,
	}
end

-- Ranks per tree and the gates of one-rank talents, for the chat summary.
local function Summary(record)
	local ranks, gates = {}, {}
	for _, node in ipairs(record.nodes) do
		ranks[node.tree or 1] = (ranks[node.tree or 1] or 0) + (node.maxRanks or 0)
		if node.maxRanks == 1 then gates[node.required] = (gates[node.required] or 0) + 1 end
	end
	local rankText = {}
	for index = 1, #record.groups do rankText[index] = tostring(ranks[index] or 0) end
	local gateList = {}
	for required in pairs(gates) do gateList[#gateList + 1] = required end
	table.sort(gateList)
	for index, required in ipairs(gateList) do gateList[index] = ("%d:%d"):format(required, gates[required]) end
	return table.concat(rankText, "/"), table.concat(gateList, " ")
end

-- The tree of one class, or nil and why ("none": not handed out to this
-- character, "blizzard": Blizzard's talent window is open).
local function ReadClass(class)
	if class == M:ClassToken() then
		local tree = M:Tree()
		if tree then return tree end
		return nil, "none"
	end
	return M:ClassTree(class)
end

function M:ProbeTrees()
	local version, build, interface = BuildText()
	local store = {
		version = PROBE_VERSION, gameVersion = version, build = build, interface = interface,
		locale = GetLocale and GetLocale() or nil, playerClass = self:ClassToken(),
		time = time and time() or nil, classes = {},
	}
	Line(L["Talent tree probe: game %s (build %s)"]:format(version, build))
	local found = 0
	for _, class in ipairs(self.CLASSES) do
		local tree, why = ReadClass(class)
		local name = self:ClassName(class)
		if tree then
			local record = Record(tree)
			store.classes[class] = record
			found = found + 1
			local ranks, gates = Summary(record)
			Line(L["  %s: spec %s, tree %s, talents: %d, rows: %d, ranks per tree: %s, one-rank gates: %s"]:format(
				name, tostring(record.specID), tostring(record.treeID), #record.nodes, record.rows or 0, ranks,
				gates ~= "" and gates or "-"))
		else
			store.classes[class] = { status = why or "none", specID = self.CLASS_SPECS[class] }
			if why == "blizzard" then
				Line(L["  %s: close the game's talent window and run the probe again"]:format(name))
			else
				Line(L["  %s: the game doesn't hand out this tree here"]:format(name))
			end
		end
	end
	SaveRecord(store)
	Line(E:Plural(found, "Kept %d tree. /reload or log out to write it to the SavedVariables file.",
		"Kept %d trees. /reload or log out to write them to the SavedVariables file."):format(found))
	return store
end

E:RegisterProbe("talents", Key("[clear]  record every talent tree the game hands out (kept until /reload writes it)"), function(rest)
	if tostring(rest or ""):lower() == "clear" then
		SaveRecord(nil)
		Line(L["Talent tree probe record removed."])
		return
	end
	if InCombatLockdown() then
		Line(L["Talent tree probe: leave combat first."])
		return
	end
	M:ProbeTrees()
end)
