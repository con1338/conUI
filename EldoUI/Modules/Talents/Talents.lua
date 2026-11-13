-- EldoUI Talent Planner: plan your own class's talents level by
-- level, see the next point, and learn it with one click.
--
-- What it reads (all from the client, nothing computed or guessed):
--   * The tree: C_ClassTalents.InitializeViewLoadout(specID, maxLevel) gives
--     an empty copy of the class tree (Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID)
--     whose conditions still hold the full tier requirements; the tree is
--     C_ClassTalents.GetTraitTreeForSpec(specID). The three talent trees are
--     the tree's node groups (C_Traits.GetGroupDisplayInfoByTreeID).
--   * Your ranks: the active combat config (C_ClassTalents.GetActiveConfigID),
--     or the other dual-talent group's config
--     (C_SpecializationInfo.GetCombatConfigIDForSpecGroup).
--
-- Learning happens only when you click (Learn next, Learn to level, the
-- toast's Learn button, the chat link or the key binding): EldoUI refuses
-- while you can't change talents or while Blizzard's talent window has
-- changes of its own, stages one PurchaseRank per rank in tier order, rolls
-- everything back if the game refuses one, and commits once. It never
-- learns on level-up by itself and never refunds.
--
-- Plans are saved per character and per talent group (E:GetPrivate("talents")),
-- by node ID with the spell ID kept as a hotfix check (Plan.lua).
--
-- Other classes: plans for a class you are not playing are saved for the
-- whole account (E:GetGlobal("talentPlans")). Their tree is read through the
-- same view loadout, for that class's spec, when the game hands it out; when
-- it doesn't, the plans are still kept and open on a character of that
-- class. Everywhere below, a talent group is either a number (your own
-- groups) or a class token such as "MAGE" (the account's plans for it).
local _, E = ...
local L = E.L
local P = E.TalentPlan

local M = E:NewModule("Talents", {
	title = "Talent Planner",
	desc = L["Plan your talents level by level, see which point comes next and learn it with one click. EldoUI never spends a point unless you click."],
	category = "Quality of Life",
	frames = { "EldoUI_TalentPlannerFrame" },
	movers = { "EldoUI_TalentPlanner" },
	-- Owns "Spellbook and talents"; Training and Skins join its hook list.
	blizzard = { "player-spells" },
	savedKeys = { "profile.modules.Talents", "private.talents", "global.talentPlans" },
	optionsPage = "module:Talents",
	presets = { "Clean", "Compact", "Glass", "Large", "Minimal", "Modern" },
	reload = false,
	defaults = {
		enabled = false,
		style = "Modern",
		levelUpToast = true,
		loginToast = true,
		confirmNewTree = true,
		learnSound = "kit:IG_QUEST_LIST_COMPLETE",
		showGuide = true,
		guideMarkers = true,
		showArrows = true,
		showOrder = true,     -- pick order numbers on the trees and on Blizzard's window
		tileSize = 36,
		transparent = false,
		blizzOverlay = true,
		blizzButton = true,
		window = {},          -- planner window: scale, last tab
	},
})
E.Talents = M

-- Other talent planners (folder names): EldoUI's reminders stand back.
E:RegisterFeatureConflicts("talents", { "TalentedForever", "TalentsForeverBook" })

E:RegisterPrivate("talents", {
	groups = {},          -- [talent group] = { plans = { plan, ... }, active = planID }
	offered = {},         -- [account plan ID] = true once the login offer was shown
})

-- Plans for other classes, for every character on the account.
E:RegisterGlobal("talentPlans", {
	classes = {},         -- [class token] = { plans = { plan, ... }, active = planID }
}, { title = "Talent plans for other classes" })

local MAX_PLANS = 10
local COMMIT_TIMEOUT = 30
local UNDO_STEPS = 30

-- One spec per class on Forever (Camelot ClassTalentUtil).
local CLASS_SPECS = {
	MAGE = 1482, DRUID = 1484, HUNTER = 1485, PALADIN = 1486, PRIEST = 1487,
	ROGUE = 1488, SHAMAN = 1489, WARLOCK = 1490, WARRIOR = 1491,
}
M.CLASS_SPECS = CLASS_SPECS

-- The classes in the class picker, in the game's own order.
M.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local IsSecret = E.Secret

local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if not ok then return nil end
	return a, b, c
end

local function Number(value)
	if type(value) ~= "number" or IsSecret(value) then return nil end
	return value
end

local function ViewConfigID()
	local consts = Constants and Constants.TraitConsts
	return consts and consts.VIEW_TRAIT_CONFIG_ID or -3
end

local function EdgeTypes()
	local edge = Enum and Enum.TraitEdgeType or {}
	return edge.VisualOnly or 0, edge.MutuallyExclusive or 4
end

function M:ClassToken()
	local _, class = UnitClass("player")
	return class
end

-- The class name in the player's language.
function M:ClassName(token)
	local names = LOCALIZED_CLASS_NAMES_MALE
	return (type(names) == "table" and token and names[token]) or token or "?"
end

-- A talent group key that stands for another class's account plans.
function M:IsOtherClass(group)
	return type(group) == "string" and group ~= self:ClassToken()
end

function M:SpecID()
	local util = PlayerUtil
	local id = util and Number(Call(util.GetCurrentSpecID))
	if id and id > 0 then return id end
	return CLASS_SPECS[self:ClassToken() or ""]
end

function M:MaxLevel()
	local level = Number(Call(GetMaxPlayerLevel))
	if not level or level < P.FIRST_LEVEL then level = 60 end
	return level
end

function M:PlayerLevel()
	local level = Number(UnitLevel("player")) or 1
	if self.levelHint and self.levelHint > level then level = self.levelHint end
	return level
end

---------------------------------------------------------------------------
-- The tree (structure only; read once, again after a hotfix is noticed)
---------------------------------------------------------------------------
-- The config of a talent group: the active one for the group in use, the
-- dual-talent config for the other.
function M:ConfigID(group)
	group = group or E:TalentGroup()
	local id
	if group == E:TalentGroup() and C_ClassTalents then id = Number(Call(C_ClassTalents.GetActiveConfigID)) end
	if not id and C_SpecializationInfo then id = Number(Call(C_SpecializationInfo.GetCombatConfigIDForSpecGroup, group)) end
	return id
end

function M:NumGroups()
	local count = Number(Call(GetNumSpecGroups)) or Number(Call(C_SpecializationInfo and C_SpecializationInfo.GetNumSpecGroups))
	return math.max(math.min(count or 1, 2), 1)
end

local function NodeSpell(configID, info)
	local entryID = info.entryIDs and info.entryIDs[1]
	local entry = entryID and Call(C_Traits.GetEntryInfo, configID, entryID)
	local def = entry and entry.definitionID and Call(C_Traits.GetDefinitionInfo, entry.definitionID)
	if type(def) ~= "table" then return nil end
	return Number(def.spellID) or Number(def.overriddenSpellID), def.overrideName, def.overrideIcon, entryID
end

local function SpellName(spellID)
	local name = spellID and C_Spell and Call(C_Spell.GetSpellName, spellID)
	if type(name) == "string" and not IsSecret(name) and name ~= "" then return name end
	return spellID and L["Talent %d"]:format(spellID) or L["Unknown talent"]
end

local function SpellIcon(spellID)
	local icon = spellID and C_Spell and Call(C_Spell.GetSpellTexture, spellID)
	return icon or 134400
end

local function Required(configID, info)
	local required = 0
	for _, condID in ipairs(info.conditionIDs or {}) do
		local cond = Call(C_Traits.GetConditionInfo, configID, condID)
		local amount = type(cond) == "table" and Number(cond.spentAmountRequired)
		if amount and amount > required then required = amount end
	end
	return required
end

-- Rows and columns per tree from the node positions.
local function Grid(nodes, list)
	local byGroup = {}
	for _, node in ipairs(list) do
		local data = byGroup[node.group] or { xs = {}, ys = {} }
		byGroup[node.group] = data
		data.xs[node.posX] = true
		data.ys[node.posY] = true
	end
	local rows, cols = 1, 1
	for group, data in pairs(byGroup) do
		local xs, ys = {}, {}
		for x in pairs(data.xs) do xs[#xs + 1] = x end
		for y in pairs(data.ys) do ys[#ys + 1] = y end
		table.sort(xs)
		table.sort(ys)
		local xIndex, yIndex = {}, {}
		for i, x in ipairs(xs) do xIndex[x] = i end
		for i, y in ipairs(ys) do yIndex[y] = i end
		for _, node in pairs(nodes) do
			if node.group == group then
				node.col, node.row = xIndex[node.posX], yIndex[node.posY]
			end
		end
		rows, cols = math.max(rows, #ys), math.max(cols, #xs)
	end
	return rows, cols
end

-- The view loadout for a spec. It is shared with Blizzard's talent window,
-- which uses it to show a linked build: it is made once per spec and
-- level, and never while that window is open (a re-read then uses the view
-- as it is). True when the view holds that spec's tree.
function M:PrepareView(specID, maxLevel, probeNode)
	if not (specID and C_ClassTalents and C_ClassTalents.InitializeViewLoadout) then return false end
	local viewKey = specID .. ":" .. tostring(maxLevel)
	local blizzard = rawget(_G, "PlayerSpellsFrame")
	local blizzardOpen = type(blizzard) == "table" and blizzard.IsShown and blizzard:IsShown()
	local function ViewReady()
		local probe = Call(C_Traits.GetNodeInfo, ViewConfigID(), probeNode)
		return type(probe) == "table" and Number(probe.ID) and probe.ID ~= 0
	end
	local ready = self.viewLoadoutKey == viewKey and ViewReady()
	-- Made again when it is missing or was replaced (another spec's
	-- view), but only while Blizzard's window is closed.
	if not ready and not blizzardOpen and pcall(C_ClassTalents.InitializeViewLoadout, specID, maxLevel) then
		self.viewLoadoutKey = viewKey
		ready = ViewReady()
	end
	return ready and true or false
end

local BuildTree

function M:ReadTree(force)
	if self.tree and not force then return self.tree end
	if not (C_Traits and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo) then return nil end
	local specID = self:SpecID()
	local maxLevel = self:MaxLevel()
	local active = self:ConfigID(E:TalentGroup())
	local treeID = specID and C_ClassTalents and Number(Call(C_ClassTalents.GetTraitTreeForSpec, specID))
	if not treeID and active then
		local info = Call(C_Traits.GetConfigInfo, active)
		treeID = type(info) == "table" and info.treeIDs and Number(info.treeIDs[1])
	end
	if not treeID then return nil end
	local nodeIDs = Call(C_Traits.GetTreeNodes, treeID)
	if type(nodeIDs) ~= "table" or #nodeIDs == 0 then return nil end

	-- The view loadout holds the full tier requirements; the live config
	-- only reports what is still missing. Fall back to it when the view
	-- can't be made.
	local readConfig = active
	if self:PrepareView(specID, maxLevel, nodeIDs[1]) then readConfig = ViewConfigID() end
	if not readConfig then return nil end
	self.tree = BuildTree(specID, treeID, nodeIDs, readConfig, maxLevel)
	return self.tree
end

-- Another class's tree, read through the view loadout for its spec (never
-- the live config: that is your own class). Returns the tree, or nil and
-- why: "blizzard" while Blizzard's talent window is open, "none" when the
-- game doesn't give that tree to this character.
function M:ClassTree(class, force)
	if not self:IsOtherClass(class) then return self:Tree() end
	self.classTrees = self.classTrees or {}
	if self.classTrees[class] and not force then return self.classTrees[class] end
	local specID = CLASS_SPECS[class]
	if not (specID and C_Traits and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo and C_ClassTalents) then return nil, "none" end
	local treeID = Number(Call(C_ClassTalents.GetTraitTreeForSpec, specID))
	local own = self:Tree()
	if not treeID or treeID == 0 or (own and own.treeID == treeID) then return nil, "none" end
	local nodeIDs = Call(C_Traits.GetTreeNodes, treeID)
	if type(nodeIDs) ~= "table" or #nodeIDs == 0 then return nil, "none" end
	local maxLevel = self:MaxLevel()
	if not self:PrepareView(specID, maxLevel, nodeIDs[1]) then
		local blizzard = rawget(_G, "PlayerSpellsFrame")
		if type(blizzard) == "table" and blizzard.IsShown and blizzard:IsShown() then return nil, "blizzard" end
		return nil, "none"
	end
	local tree = BuildTree(specID, treeID, nodeIDs, ViewConfigID(), maxLevel)
	if not tree then return nil, "none" end
	tree.class = class
	self.classTrees[class] = tree
	return tree
end

-- The tree a talent group's plans are made on.
function M:TreeOf(group)
	if self:IsOtherClass(group) then return (self:ClassTree(group)) end
	return self:Tree()
end

-- The nodes of one tree, read through a config, as the tree table the
-- planner and Plan.lua work on (nil when the config shows none).
function BuildTree(specID, treeID, nodeIDs, readConfig, maxLevel)
	local groups, groupIndex = {}, {}
	local display = Call(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
	if type(display) == "table" then
		for _, info in ipairs(display) do
			if type(info) == "table" and Number(info.groupID) then
				groups[#groups + 1] = { groupID = info.groupID, name = info.displayName or "", icon = info.icon, orderIndex = Number(info.orderIndex) or #groups + 1 }
			end
		end
		table.sort(groups, function(a, b) return a.orderIndex < b.orderIndex end)
	end

	-- A node lists several node groups (Forever puts others before its
	-- talent tree's group), so its tree is the group the tree's display
	-- list names; the first group only when the list names none.
	local displayed = {}
	for _, group in ipairs(groups) do displayed[group.groupID] = true end
	local function TreeGroup(info)
		local first
		for _, id in ipairs(info.groupIDs or {}) do
			local groupID = Number(id)
			if groupID then
				if displayed[groupID] then return groupID end
				first = first or groupID
			end
		end
		if next(displayed) == nil then return first or 0 end
		return groups[1].groupID
	end

	local visualOnly, exclusive = EdgeTypes()
	local nodes, list, bySpell, edges = {}, {}, {}, {}
	for _, nodeID in ipairs(nodeIDs) do
		local info = Call(C_Traits.GetNodeInfo, readConfig, nodeID)
		if type(info) == "table" and Number(info.ID) and info.ID ~= 0 and info.isVisible ~= false and (Number(info.maxRanks) or 0) > 0 then
			local spellID, overrideName, overrideIcon, entryID = NodeSpell(readConfig, info)
			local group = TreeGroup(info)
			local node = {
				id = nodeID, group = group, entryID = entryID, spellID = spellID,
				maxRanks = math.max(Number(info.maxRanks) or 1, Number(info.totalMaxRanks) or 0),
				required = Required(readConfig, info), prereqs = {}, unlocks = {},
				posX = Number(info.posX) or 0, posY = Number(info.posY) or 0,
				name = overrideName or SpellName(spellID), icon = overrideIcon or SpellIcon(spellID),
			}
			nodes[nodeID] = node
			list[#list + 1] = node
			if spellID then bySpell[spellID] = nodeID end
			for _, edge in ipairs(info.visibleEdges or {}) do
				local target = type(edge) == "table" and Number(edge.targetNode)
				if target and edge.type ~= visualOnly and edge.type ~= exclusive then edges[#edges + 1] = { nodeID, target } end
			end
		end
	end
	if #list == 0 then return nil end
	for _, edge in ipairs(edges) do
		local from, to = nodes[edge[1]], nodes[edge[2]]
		if from and to then
			to.prereqs[#to.prereqs + 1] = from.id
			from.unlocks[#from.unlocks + 1] = to.id
		end
	end
	-- Trees the display list doesn't name still get a column.
	for _, group in ipairs(groups) do groupIndex[group.groupID] = true end
	for _, node in ipairs(list) do
		if not groupIndex[node.group] then
			groupIndex[node.group] = true
			groups[#groups + 1] = { groupID = node.group, name = L["Tree %d"]:format(#groups + 1), orderIndex = #groups + 1 }
		end
	end
	wipe(groupIndex)
	for index, group in ipairs(groups) do groupIndex[group.groupID] = index end
	for _, node in ipairs(list) do node.groupIndex = groupIndex[node.group] end
	local rows, cols = Grid(nodes, list)
	for _, node in ipairs(list) do node.tier = math.floor((node.required or 0) / 5) + 1 end
	local order = {}
	for _, node in ipairs(list) do order[#order + 1] = node.id end
	table.sort(order, function(a, b)
		local na, nb = nodes[a], nodes[b]
		if na.groupIndex ~= nb.groupIndex then return na.groupIndex < nb.groupIndex end
		if na.row ~= nb.row then return na.row < nb.row end
		return na.col < nb.col
	end)
	return {
		specID = specID, treeID = treeID, maxLevel = maxLevel, maxPoints = P.PointsAt(maxLevel),
		groups = groups, groupIndex = groupIndex, nodes = nodes, order = order, bySpell = bySpell,
		rows = rows, cols = cols, fromView = readConfig == ViewConfigID(),
	}
end

function M:Tree()
	return self:ReadTree()
end

-- The spell a node teaches right now (hotfix check before learning).
function M:CurrentNodeSpell(configID, nodeID)
	local info = Call(C_Traits.GetNodeInfo, configID, nodeID)
	if type(info) ~= "table" then return nil end
	return (NodeSpell(configID, info))
end

---------------------------------------------------------------------------
-- Live ranks
---------------------------------------------------------------------------
function M:LiveState(group)
	group = group or E:TalentGroup()
	-- Another class: nothing learned on this character.
	if self:IsOtherClass(group) then return P.NewState() end
	if type(group) == "string" then group = E:TalentGroup() end
	self.liveCache = self.liveCache or {}
	if self.liveCache[group] then return self.liveCache[group] end
	local state = P.NewState()
	local tree = self:Tree()
	local config = self:ConfigID(group)
	state.config = config
	if tree and config then
		for nodeID, node in pairs(tree.nodes) do
			local info = Call(C_Traits.GetNodeInfo, config, nodeID)
			local rank = type(info) == "table" and Number(info.ranksPurchased) or 0
			if rank > 0 then
				state.ranks[nodeID] = math.min(rank, node.maxRanks)
				state.spent[node.group] = (state.spent[node.group] or 0) + state.ranks[nodeID]
				state.total = state.total + state.ranks[nodeID]
			end
		end
		state.staged = Call(C_Traits.ConfigHasStagedChanges, config) and true or false
	end
	self.liveCache[group] = state
	return state
end

-- Unspent points: the client's own number for the group in use.
function M:Unspent(group)
	group = group or E:TalentGroup()
	if type(group) == "string" then return 0 end
	local tree = self:Tree()
	local live = self:LiveState(group)
	if tree and live.config then
		local list = Call(C_Traits.GetTreeCurrencyInfo, live.config, tree.treeID, true)
		local info = type(list) == "table" and list[1]
		local quantity = type(info) == "table" and Number(info.quantity)
		if quantity then return math.max(quantity, 0) end
	end
	return math.max(P.PointsAt(self:PlayerLevel()) - live.total, 0)
end

function M:Invalidate()
	self.liveCache = nil
end

---------------------------------------------------------------------------
-- Plans
---------------------------------------------------------------------------
local undo = {}   -- planID -> { order copies, or the marker of a copy made with Undo }

local function Store()
	local store = E:GetPrivate("talents") or {}
	store.groups = type(store.groups) == "table" and store.groups or {}
	return store
end

-- The account's plans for other classes (kept for this session when the
-- saved settings aren't loaded).
local accountFallback = { classes = {} }
local function AccountStore()
	local store = E:GetGlobal("talentPlans") or accountFallback
	store.classes = type(store.classes) == "table" and store.classes or {}
	return store
end
M.AccountStore = AccountStore

function M:GroupStore(group)
	group = group or E:TalentGroup()
	local parent
	if type(group) == "string" then
		-- Your own class picked in the class picker: your talent group.
		if not self:IsOtherClass(group) then return self:GroupStore(E:TalentGroup()) end
		parent = AccountStore().classes
	else
		parent = Store().groups
	end
	local data = parent[group]
	if type(data) ~= "table" then
		data = { plans = {} }
		parent[group] = data
	end
	data.plans = type(data.plans) == "table" and data.plans or {}
	return data
end

function M:Plans(group)
	return self:GroupStore(group).plans
end

function M:FindPlan(id, group)
	for _, plan in ipairs(self:Plans(group)) do
		if plan.id == id then return plan end
	end
end

function M:ActivePlan(group)
	local data = self:GroupStore(group)
	local plan = data.active and self:FindPlan(data.active, group)
	if not plan and data.plans[1] then
		plan = data.plans[1]
		data.active = plan.id
	end
	if plan and plan.unchecked then self:CheckPlan(plan, self:TreeOf(group)) end
	return plan
end

-- A plan saved without its tree (another class the game didn't show) is
-- checked against the tree once it can be read: talents that moved follow
-- their spell, ranks that don't fit are left out.
function M:CheckPlan(plan, tree)
	if not (plan and plan.unchecked and tree) then return end
	plan.unchecked = nil
	plan.tree = tree.treeID
	P.Verify(tree, plan, tree.maxPoints)
end

function M:SetActivePlan(id, group)
	if not self:FindPlan(id, group) then return false end
	self:GroupStore(group).active = id
	self:Changed()
	return true
end

local planCounter = 0
local function NewID()
	planCounter = planCounter + 1
	return ("%d-%d"):format(time(), planCounter)
end

function M:UniqueName(base, group)
	local taken = {}
	for _, plan in ipairs(self:Plans(group)) do taken[plan.name] = true end
	if not taken[base] then return base end
	for n = 2, 99 do
		local name = ("%s %d"):format(base, n)
		if not taken[name] then return name end
	end
	return base
end

-- A new plan (order: ranks in buying order). Returns the plan, or nil and why.
-- The text when a group's tree can't be read.
function M:NoTreeText(group)
	if self:IsOtherClass(group) then
		local _, why = self:ClassTree(group)
		if why == "blizzard" then return L["Close Blizzard's talent window, then pick the class again."] end
		return L["The game doesn't show the %s tree to this character. Your %s plans are kept and open on a %s."]:format(
			self:ClassName(group), self:ClassName(group), self:ClassName(group))
	end
	return L["Your talents aren't loaded yet. Try again in a moment."]
end

-- A new plan (order: ranks in buying order). Returns the plan, or nil and
-- why. opts.spells keeps the spell of each node for a plan saved without
-- its tree (another class the game doesn't show): it is checked against
-- the tree when a character of that class opens it. opts.undoable: Undo on
-- the new plan takes it back and puts the plan in use before it back.
function M:CreatePlan(name, order, group, opts)
	local tree = self:TreeOf(group)
	local unchecked = not tree and self:IsOtherClass(group) and opts and opts.spells
	if not tree and not unchecked then return nil, self:NoTreeText(group) end
	local plans = self:Plans(group)
	if #plans >= MAX_PLANS then return nil, L["You have %d plans for this talent group. Delete one first."]:format(MAX_PLANS) end
	name = strtrim(tostring(name or ""))
	if name == "" then name = L["My plan"] end
	local plan = {
		id = NewID(), name = self:UniqueName(E:Utf8Sub(name, 40), group),
		class = self:IsOtherClass(group) and group or self:ClassToken(), created = time(),
	}
	if tree then
		plan.tree = tree.treeID
		plan.order = (P.Normalize(tree, order or {}, tree.maxPoints))
		P.RecordSpells(tree, plan)
	else
		plan.order, plan.spells, plan.unchecked = {}, {}, true
		for index = 1, math.min(#(order or {}), 120) do plan.order[index] = order[index] end
		for nodeID, spellID in pairs(opts.spells) do plan.spells[nodeID] = spellID end
	end
	plans[#plans + 1] = plan
	local data = self:GroupStore(group)
	if opts and opts.undoable then undo[plan.id] = { { created = true, group = group, back = data.active } } end
	data.active = plan.id
	self:Changed()
	return plan
end

-- A plan that starts as the character's talents in this group.
function M:CreatePlanFromLive(name, group)
	if self:IsOtherClass(group) then return nil, L["You can only start from the talents of the class you play."] end
	local tree = self:Tree()
	if not tree then return nil, L["Your talents aren't loaded yet. Try again in a moment."] end
	local live = self:LiveState(group)
	return self:CreatePlan(name or L["My talents"], P.FromRanks(tree, live.ranks, tree.maxPoints), group)
end

function M:DeletePlan(id, group)
	local data = self:GroupStore(group)
	for index, plan in ipairs(data.plans) do
		if plan.id == id then
			table.remove(data.plans, index)
			undo[id] = nil
			if data.active == id then data.active = data.plans[1] and data.plans[1].id or nil end
			self:Changed()
			return true
		end
	end
	return false
end

function M:RenamePlan(id, name, group)
	local plan = self:FindPlan(id, group)
	name = strtrim(tostring(name or ""))
	if not plan or name == "" then return false end
	if name ~= plan.name then plan.name = self:UniqueName(E:Utf8Sub(name, 40), group) end
	self:Changed()
	return true
end

function M:CopyPlan(id, group)
	local plan = self:FindPlan(id, group)
	if not plan then return nil end
	return self:CreatePlan(L["%s (copy)"]:format(plan.name), CopyTable(plan.order), group)
end

local function PushUndo(plan)
	local stack = undo[plan.id] or {}
	undo[plan.id] = stack
	stack[#stack + 1] = CopyTable(plan.order)
	if #stack > UNDO_STEPS then table.remove(stack, 1) end
end

function M:CanUndo(plan)
	return plan ~= nil and undo[plan.id] ~= nil and #undo[plan.id] > 0
end

function M:Undo(plan)
	local stack = plan and undo[plan.id]
	if not stack or #stack == 0 then return false end
	local entry = table.remove(stack)
	if entry.created then
		-- The plan was a copy made with Undo (a suggested path): it goes,
		-- and the plan in use before it is back.
		self:DeletePlan(plan.id, entry.group)
		if entry.back and self:FindPlan(entry.back, entry.group) then self:GroupStore(entry.group).active = entry.back end
		self:Changed()
		return true
	end
	plan.order = entry
	local tree = self:TreeOf(plan.class)
	if tree then P.RecordSpells(tree, plan) end
	self:Changed()
	return true
end

-- Messages for the reasons P.CanAdd and P.Remove give.
function M:ReasonText(reason, detail, group)
	local tree = self:TreeOf(group)
	local node = tree and detail and tree.nodes[detail]
	if reason == "max" then return L["That talent is already at its full rank in your plan."] end
	if reason == "points" then return L["Your plan already uses all %d points."]:format(tree and tree.maxPoints or 0) end
	if reason == "tier" then return L["Needs %d points in this tree first."]:format(detail or 0) end
	if reason == "prereq" then return L["Needs %s at full rank first."]:format(node and node.name or "?") end
	if reason == "needed" then return L["%s in your plan needs this rank. Remove that first."]:format(node and node.name or "?") end
	if reason == "none" then return L["Your plan has no rank of this talent."] end
	return L["That talent isn't in your class's tree."]
end

-- Left click on a talent: one more rank in the plan (at the end).
function M:PlanAdd(nodeID, group)
	local tree = self:TreeOf(group)
	local plan = self:ActivePlan(group)
	if not tree then return false, self:NoTreeText(group) end
	if not plan then
		local made, err = self:CreatePlan(L["My plan"], nil, group)
		if not made then return false, err end
		plan = made
	end
	local ok, reason, detail = P.CanAdd(tree, P.Count(tree, plan.order), nodeID, tree.maxPoints)
	if not ok then return false, self:ReasonText(reason, detail, group) end
	PushUndo(plan)
	plan.order[#plan.order + 1] = nodeID
	P.RecordSpells(tree, plan)
	self:Changed()
	return true
end

-- Right click: the plan's last rank of that talent goes.
function M:PlanRemove(nodeID, group)
	local tree = self:TreeOf(group)
	local plan = self:ActivePlan(group)
	if not (tree and plan) then return false, L["Your plan has no rank of this talent."] end
	local order, reason, detail = P.Remove(tree, plan.order, nodeID)
	if not order then return false, self:ReasonText(reason, detail, group) end
	PushUndo(plan)
	plan.order = order
	P.RecordSpells(tree, plan)
	self:Changed()
	return true
end

function M:ClearPlan(group)
	local plan = self:ActivePlan(group)
	if not plan or #plan.order == 0 then return false end
	PushUndo(plan)
	plan.order = {}
	plan.spells = {}
	self:Changed()
	return true
end

-- Every entry of a plan with what the character has: { index, nodeID,
-- rank (the n-th rank of that talent), level, learned }.
function M:PlanSteps(plan, group)
	local steps = {}
	if not plan then return steps end
	local live = self:LiveState(group)
	local seen = {}
	for index, nodeID in ipairs(plan.order) do
		seen[nodeID] = (seen[nodeID] or 0) + 1
		steps[index] = {
			index = index, nodeID = nodeID, rank = seen[nodeID], level = P.Level(index),
			learned = (live.ranks[nodeID] or 0) >= seen[nodeID],
		}
	end
	return steps
end

-- The plan's ranks the character hasn't learned yet, in plan order.
function M:OpenSteps(plan, group)
	local open = {}
	for _, step in ipairs(self:PlanSteps(plan, group)) do
		if not step.learned then open[#open + 1] = step end
	end
	return open
end

function M:NextStep(group)
	return self:OpenSteps(self:ActivePlan(group), group)[1]
end

function M:StepText(step, group)
	local tree = self:TreeOf(group)
	local node = tree and step and tree.nodes[step.nodeID]
	if not node then return "" end
	return L["%s %d/%d"]:format(node.name, step.rank, node.maxRanks)
end

-- The pick order mark on a talent: a small box with the number of the
-- plan's point that first takes the talent. Used by the planner's trees and
-- the overlay on Blizzard's talent window. The box fits its number, also
-- with Large text. badge:SetOrder(number) shows it, SetOrder(nil) hides it.
local function FitOrder(badge)
	local text = badge.text
	local width = math.ceil(text:GetStringWidth() or 0)
	local height = math.ceil(text:GetStringHeight() or 0)
	height = math.max(height + 3, 13)
	badge:SetSize(math.max(width + 6, height), height)
end

function M:CreateOrderBadge(parent)
	local Kit = E.UIKit
	local badge = CreateFrame("Frame", nil, parent)
	E:SetTemplate(badge)
	badge:EnableMouse(false)
	badge.text = Kit.Text(badge, 10, "CENTER")
	badge.text:SetPoint("CENTER", 0, 0)
	badge.SetOrder = function(own, number)
		if not number then
			own.order = nil
			own:Hide()
			return
		end
		own.order = number
		own.text:SetText(tostring(number))
		own.text:SetTextColor(Kit.Accent())
		FitOrder(own)
		own:Show()
	end
	E:RegisterThemed(badge, function(own)
		if own.order then
			own.text:SetTextColor(Kit.Accent())
			FitOrder(own)
		end
	end)
	badge:Hide()
	return badge
end

-- Whether the trees show the pick order (planner option, on by default).
function M:ShowsOrder()
	return self.db.showOrder ~= false
end

-- Plans, plan view and overlay redraw after any change.
function M:Changed()
	self:Invalidate()
	if self.changeQueued then return end
	self.changeQueued = true
	C_Timer.After(0, function()
		M.changeQueued = false
		M:RefreshViews()
	end)
end

function M:RefreshViews()
	if self.RefreshWindow then self:RefreshWindow() end
	if self.RefreshOverlay then self:RefreshOverlay() end
	if self.UpdateBlizzardButton then self:UpdateBlizzardButton() end
end

---------------------------------------------------------------------------
-- Learning (only from a click)
---------------------------------------------------------------------------
local function Accent(text)
	return E.UIKit.AccentHex() .. text .. "|r"
end

function M:Busy()
	return self.pending ~= nil
end

-- Whether a Learn click can go ahead now; returns ok or false and why.
function M:CanLearn(group)
	group = group or E:TalentGroup()
	if not self.active then return false, E:ModuleOffNote("Talents") end
	if InCombatLockdown() then return false, L["Talents can't change in combat."] end
	if self.pending then return false, L["Still learning the last talent. One moment."] end
	if self:IsOtherClass(group) then return false, L["This plan is for another class. Open it on a character of that class to learn it."] end
	if group ~= E:TalentGroup() then return false, L["This is your other talent group. Switch to it in Blizzard's talent window first."] end
	local tree = self:Tree()
	if not tree then return false, L["Your talents aren't loaded yet. Try again in a moment."] end
	local live = self:LiveState(group)
	if not live.config then return false, L["Your talents aren't loaded yet. Try again in a moment."] end
	if C_ClassTalents and C_ClassTalents.CanChangeTalents then
		local ok, canChange, canAdd, why = pcall(C_ClassTalents.CanChangeTalents)
		if ok and not canChange and not canAdd then
			return false, (type(why) == "string" and not IsSecret(why) and why ~= "") and why or L["The game doesn't let you change talents right now."]
		end
	end
	if Call(C_Traits.ConfigHasStagedChanges, live.config) then
		return false, L["Blizzard's talent window has changes that aren't applied. Apply or undo them there first."]
	end
	if self:Unspent(group) <= 0 then return false, L["You have no unspent talent points."] end
	if not self:ActivePlan(group) then return false, L["Make a plan first: click talents in the planner."] end
	if not self:NextStep(group) then return false, L["Everything in your plan is learned."] end
	return true
end

-- The steps a Learn click would take. mode: "next" (one rank) or "level"
-- (every open rank the plan has up to your level, as far as your points go).
function M:LearnSteps(mode, group)
	group = group or E:TalentGroup()
	local open = self:OpenSteps(self:ActivePlan(group), group)
	local unspent = self:Unspent(group)
	local steps = {}
	if mode == "level" then
		local level = self:PlayerLevel()
		for _, step in ipairs(open) do
			if #steps >= unspent then break end
			if step.level <= level then steps[#steps + 1] = step end
		end
		if #steps == 0 and open[1] and unspent > 0 then steps[1] = open[1] end
	elseif open[1] and unspent > 0 then
		steps[1] = open[1]
	end
	return steps
end

function M:Report(message, failed)
	local link = E:ChatLink("talents", "open", L["Open planner"])
	E:Print(("%s %s"):format(message, link))
	if failed then E:Debug("Talents:", message) end
	if self.SetWindowStatus then self:SetWindowStatus(message, failed) end
end

-- Learn from a click. Returns true when the commit went out.
function M:Learn(mode, confirmed)
	local ok, why = self:CanLearn()
	if not self.active then
		-- The shared off line, with the enable command as a link.
		E:Print(E:ModuleOffHint("Talents"))
		return false, why
	end
	if not ok then
		self:Report(why, true)
		return false, why
	end
	local tree = self:Tree()
	local live = self:LiveState()
	local steps = self:LearnSteps(mode)
	if #steps == 0 then
		self:Report(L["Nothing to learn right now."], true)
		return false
	end
	-- First point into an empty tree: ask once more.
	if self.db.confirmNewTree and not confirmed then
		for _, step in ipairs(steps) do
			local node = tree.nodes[step.nodeID]
			if node and (live.spent[node.group] or 0) == 0 then
				local group = tree.groups[node.groupIndex]
				E:ShowConfirm({ key = "ELDOUI_TALENTS_NEWTREE", title = L["Talents"], accept = ACCEPT,
					text = L["This puts your first point into %s: %s. Learn it?"]:format(group and group.name or "?", self:StepText(step)),
					data = { mode = mode }, onAccept = function(data) M:Learn(data.mode, true) end })
				return false, "confirm"
			end
		end
	end
	local config = live.config
	table.sort(steps, P.StageSort(tree))
	for _, step in ipairs(steps) do
		local node = tree.nodes[step.nodeID]
		local spell = self:CurrentNodeSpell(config, step.nodeID)
		if node.spellID and spell and spell ~= node.spellID then
			self.tree = nil
			self:Report(L["Blizzard changed the talent tree since the planner read it. Open the planner to check your plan, then try again."], true)
			return false
		end
	end
	local staged = 0
	for _, step in ipairs(steps) do
		local done = Call(C_Traits.PurchaseRank, config, step.nodeID)
		if not done then
			Call(C_Traits.RollbackConfig, config)
			self:Invalidate()
			self:Report(L["The game refused %s. Nothing was learned."]:format(self:StepText(step)), true)
			return false
		end
		staged = staged + 1
	end
	if staged == 0 then return false end
	local committed = Call(C_ClassTalents.CommitConfig, nil)
	if not committed then
		Call(C_Traits.RollbackConfig, config)
		self:Invalidate()
		self:Report(L["The game didn't accept the change. Nothing was learned."], true)
		return false
	end
	local token = {}
	self.pending = { config = config, steps = steps, token = token }
	C_Timer.After(COMMIT_TIMEOUT, function()
		if M.pending and M.pending.token == token then M:FinishLearn(false, true) end
	end)
	self:Changed()
	return true
end

function M:FinishLearn(success, timedOut)
	local pending = self.pending
	if not pending then return end
	self.pending = nil
	self:Invalidate()
	if success then
		local names = {}
		for _, step in ipairs(pending.steps) do names[#names + 1] = self:StepText(step) end
		self:Report(L["Learned: %s."]:format(Accent(table.concat(names, ", "))))
		if self.db.learnSound and self.db.learnSound ~= "none" then E:PlayMedia(self.db.learnSound) end
	elseif timedOut then
		self:Report(L["No answer from the game. Check your talents in Blizzard's talent window."], true)
	else
		Call(C_Traits.RollbackConfig, pending.config)
		self:Report(L["The game didn't accept the change. Nothing was learned."], true)
	end
	self:Changed()
end

---------------------------------------------------------------------------
-- Reminders: a toast with a Learn button, never a purchase on its own.
---------------------------------------------------------------------------
function M:Remind(level)
	-- On level-up: the one checklist reminder for the new level (LevelUp.lua).
	if level and self.LevelUpToast then return self.active and self:LevelUpToast(level) or false end
	if not self.active or E:FeatureConflict("talents") then return false end
	local step = self:NextStep()
	if not step or self:Unspent() <= 0 then return false end
	local tree = self:Tree()
	local node = tree and tree.nodes[step.nodeID]
	if not node then return false end
	local text
	if level then
		text = L["Level %d: next in your plan is %s."]:format(level, self:StepText(step))
	else
		text = L["You have %d unspent talent points. Next in your plan: %s."]:format(self:Unspent(), self:StepText(step))
	end
	M:PushAlert({
		key = "eldoui-talents", title = L["Talent point"], text = text, icon = node.icon, duration = 30,
		actions = {
			{ label = L["Learn"], func = function() M:Learn("next") end, tip = L["Learns this one rank now. Nothing else is spent."] },
			{ label = L["Planner"], func = function() M:OpenPlanner() end, tip = L["Opens the Talent Planner."] },
		},
	})
	self:OfferToastHelp()
	return true
end

-- Tour help: the first toast with a Learn button says what Learn does.
local TOAST_KEYS = { ["eldoui-talents"] = true, ["eldoui-levelup"] = true }

local function ToastFrame()
	local queue = E.NoticeQueue and E:NoticeQueue()
	for _, shown in ipairs(queue and queue.shown or {}) do
		local data, frame = shown.data, shown.frame
		if not shown.closing and data and TOAST_KEYS[data.key] and frame and frame:IsVisible() then return frame end
	end
end

E.Tour:Register("talents:toast", {
	form = "spot", word = "talents",
	offer = function(_, force)
		return E.Tour:Spot("talents:toast", {
			force = force, target = ToastFrame,
			title = L["Talent point"],
			text = L["Learn spends one point on the next rank in your talent plan. EldoUI never spends a point unless you click, also not when you level up."],
		})
	end,
	replay = function(def) def.offer(def, true) end,
})

function M:OfferToastHelp()
	E.Tour:Offer("talents:toast")
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function OnTraitEvent(_, event, configID)
	if event == "TRAIT_CONFIG_UPDATED" and M.pending and (configID == nil or configID == M.pending.config) then
		M:FinishLearn(true)
		return
	elseif event == "CONFIG_COMMIT_FAILED" and M.pending and (configID == nil or configID == M.pending.config) then
		M:FinishLearn(false)
		return
	end
	M:Changed()
end

-- Published tree changes can keep the same spell IDs while moving ranks,
-- requirements or edges. Re-read only cached trees named by the event.
local function OnTreeChanged(_, _, treeID)
	treeID = Number(treeID)
	if not treeID or treeID <= 0 or treeID == math.huge or treeID % 1 ~= 0 then return end
	local changed = false
	if M.tree and M.tree.treeID == treeID then
		M.tree = nil
		changed = true
	end
	for class, tree in pairs(M.classTrees or {}) do
		if tree.treeID == treeID then
			M.classTrees[class] = nil
			changed = true
		end
	end
	if changed then
		M.viewLoadoutKey = nil
		M:Changed()
	end
end

local function OnGroupChanged()
	M.tree = nil
	M.viewGroup = nil
	M:Changed()
end

local function OnLevelUp(owner, event, level, ...)
	-- What the level gave, for the level-up card (LevelUp.lua).
	if M.RecordLevelGains then M.RecordLevelGains(owner, event, level, ...) end
	level = Number(level)
	if level then M.levelHint = level end
	M:Invalidate()
	if not M.db.levelUpToast then return M:Changed() end
	C_Timer.After(1.5, function()
		M:Remind(level)
		M:Changed()
	end)
end

local function OnEnteringWorld(_, _, isLogin)
	M:Changed()
	if isLogin and M.db.loginToast then
		C_Timer.After(5, function() M:Remind() end)
	end
	if isLogin then C_Timer.After(8, function() M:OfferAccountPlans() end) end
end

---------------------------------------------------------------------------
-- Plans saved on another character for this class
---------------------------------------------------------------------------
-- At login: one offer per saved plan and character, with a Use it button.
-- Nothing is learned; the plan is copied into this character's plans.
function M:OfferAccountPlans()
	if not self.active then return false end
	local class = self:ClassToken()
	local data = class and AccountStore().classes[class]
	if type(data) ~= "table" or type(data.plans) ~= "table" then return false end
	local store = Store()
	store.offered = type(store.offered) == "table" and store.offered or {}
	for _, plan in ipairs(data.plans) do
		if type(plan) == "table" and plan.id and not store.offered[plan.id] then
			store.offered[plan.id] = true
			local id = plan.id
			M:PushAlert({
				key = "eldoui-talents-saved", title = L["Saved talent plan"], icon = 134400, duration = 30,
				text = L["You saved the plan %s for your %s characters. Use it on this character?"]:format(Accent(plan.name), self:ClassName(class)),
				actions = {
					{ label = L["Use it"], func = function() M:AdoptPlan(id) end, tip = L["Copies the plan into this character's plans. Nothing is learned."] },
					{ label = L["Not now"], tip = L["The plan stays saved. Pick your class in the planner to find it."] },
				},
			})
			return true
		end
	end
	return false
end

-- Copy an account plan for this class into the character's plans.
function M:AdoptPlan(id)
	local class = self:ClassToken()
	local data = class and AccountStore().classes[class]
	local source
	for _, plan in ipairs(type(data) == "table" and data.plans or {}) do
		if plan.id == id then source = plan break end
	end
	local tree = self:Tree()
	if not (source and tree) then return nil end
	local copy = { order = CopyTable(source.order or {}), spells = CopyTable(source.spells or {}) }
	P.Verify(tree, copy, tree.maxPoints)
	local plan, why = self:CreatePlan(source.name, copy.order)
	if not plan then
		self:Report(why, true)
		return nil
	end
	self:Report(L["Saved the talent plan %s for this character. Nothing was learned."]:format(Accent(plan.name)))
	return plan
end

local TRAIT_EVENTS = { "TRAIT_CONFIG_UPDATED", "CONFIG_COMMIT_FAILED", "TRAIT_NODE_CHANGED", "TRAIT_TREE_CURRENCY_INFO_UPDATED" }

function M:OnEnable()
	for _, event in ipairs(TRAIT_EVENTS) do self:RegisterEvent(event, OnTraitEvent) end
	self:RegisterEvent("TRAIT_TREE_CHANGED", OnTreeChanged)
	self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", OnGroupChanged)
	self:RegisterEvent("ACTIVE_COMBAT_CONFIG_CHANGED", OnGroupChanged)
	self:RegisterEvent("PLAYER_LEVEL_UP", OnLevelUp)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", OnEnteringWorld)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() M:Changed() end)
	-- The gamepad and mouse interfaces swap: the talent window's additions
	-- step aside or come back.
	self:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION", function()
		E:RunOutOfCombat(function() if M.active and M.ApplyBlizzard then M:ApplyBlizzard() end end)
	end)
	local conflict, title = E:FeatureConflict("talents")
	if conflict then
		self:Print(L["%s is loaded too. EldoUI's planner still works; its level-up reminders stay quiet so you don't get two."]:format(title))
	end
	if self.BuildWindow then self:BuildWindow() end
	if self.ApplyBlizzard then self:ApplyBlizzard() end
	self:Changed()
end

function M:OnDisable()
	self.pending = nil
	if self.ForgetLevelGains then self:ForgetLevelGains() end
	if self.ClosePlanner then self:ClosePlanner() end
	if self.RestoreBlizzard then self:RestoreBlizzard() end
end

function M:OnProfileChanged()
	if not self.active then return end
	if self.RestyleWindow then self:RestyleWindow() end
	if self.ApplyBlizzard then self:ApplyBlizzard() end
	self:Changed()
end

---------------------------------------------------------------------------
-- Entry points: chat link, key binding, slash command
---------------------------------------------------------------------------
local function NeedsModule()
	if M.active then return true end
	E:Print(E:ModuleOffHint("Talents"))
	return false
end

E:RegisterChatLink("talents", function(data)
	if not NeedsModule() then return end
	if data == "learn" then M:Learn("next") else M:OpenPlanner() end
end)

-- Bindings.xml: "Open or close the talent planner".
function E:ToggleTalentPlanner()
	if NeedsModule() then M:TogglePlanner() end
end
E:NameBinding("BINDING_NAME_ELDOUI_TALENTS", E.Key("Open or close the Talent Planner"))

local function Command(arg)
	local word, rest = (arg or ""):match("^(%S*)%s*(.-)$")
	word = (word or ""):lower()
	if word == "on" or word == "off" then
		E:SetModuleFromCommand("Talents", word == "on")
		return
	elseif word == "config" or word == "options" then
		E:ToggleConfig("module:Talents")
		return
	end
	if not NeedsModule() then return end
	if word == "" then
		M:TogglePlanner()
	elseif word == "next" then
		M:Learn("next")
	elseif word == "level" then
		M:Learn("level")
	elseif word == "export" then
		local plan = M:ActivePlan()
		if plan then E:ShowExport("share:talents:" .. plan.id) else E:Print(L["Make a plan first: click talents in the planner."]) end
	elseif word == "import" then
		if rest ~= "" then M:ImportText(rest) else M:ShowImportBox() end
	elseif word == "send" then
		local plan = M:ActivePlan()
		if plan then E:SendShare("share:talents:" .. plan.id, rest) else E:Print(L["Make a plan first: click talents in the planner."]) end
	elseif word == "reset" then
		if M:ClearPlan() then E:Print(L["Your plan is empty again. Your talents didn't change."]) end
	else
		E:Print(L["Unknown option. Try /eui help talents."])
	end
end

E:AddCommand("talents", "[next | level | export | import [link] | send <party | raid | guild | name> | reset | config | on | off]  the Talent Planner: open it, import a plan or a talent calculator link, or learn your plan's next point", Command, "Tools")
