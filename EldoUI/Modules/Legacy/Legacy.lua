-- EldoUI Legacy Planner: plan Forever's Legacy points without
-- spending them.
--
-- What Forever has (Blizzard_LegacySystem, wow-ui-source branch forever):
--   * Legacy is three trait trees in C_Traits: Constants.LegacyConsts
--     LEGACY_TREE_PROFESSIONS_ID, _ADVENTURE_ID and _PROGRESSION_ID, each
--     with its own config (C_Traits.GetConfigIDByTreeID). The points are
--     one trait currency (LEGACY_POINTS_TRAIT_CURRENCY_ID) shared by the
--     three trees: C_Traits.GetTreeCurrencyInfo gives quantity (unspent),
--     spent, spentInTree and maxQuantity (Blizzard's tooltip calls it the
--     season cap).
--   * The Legacy level is the renown of the faction
--     LEGACY_REWARD_TRACK_FACTION_ID (C_MajorFactions.GetCurrentRenownLevel);
--     0 means Legacy is still locked.
--   * Legacy Challenges are the achievement API: on Forever every
--     achievement category is a challenge category, and
--     C_Traits.GetTraitCurrencyForAchievement says how many Legacy points
--     one awards.
-- There is no C_Legacy namespace, and nothing here guesses a name: a client
-- without these answers gets an honest "not on this client" page.
--
-- Read-only: EldoUI never calls PurchaseRank, RefundRank, CommitConfig or
-- ResetTree on a Legacy tree. A draft and the profiles are EldoUI's own
-- saved data; the player spends points in Blizzard's Legacy window.
local _, E = ...
local L = E.L

local Key = E.Key
local M = E:NewModule("Legacy", {
	title = "Legacy Planner",
	desc = L["Plan your Legacy points: a draft build next to your current one, named profiles for all your characters, a cost check against the season cap and a challenge browser. It never spends a point."],
	category = "Quality of Life",
	frames = {},
	movers = {},
	blizzard = { "legacy-achievements" },
	savedKeys = { "profile.modules.Legacy", "global.legacy", "private.legacy" },
	optionsPage = "module:Legacy",
	presets = { "Clean", "Compact", "Glass", "Large", "Minimal", "Modern" },
	uiAmount = "full",
	reload = false,
	themed = "RestyleWindow",
	defaults = {
		enabled = false,
		style = "Modern",
		openWithBlizzard = false,  -- open the planner when Blizzard's Legacy window opens
		blizzButton = true,        -- "Planner" button on Blizzard's Legacy window
		recordAlts = true,         -- Legacy points into the Characters store
		rowHeight = 22,
		showIcons = true,
		transparent = false,
		changesOnly = false,       -- Build page: only nodes the draft changes
		challengeStatus = "all",   -- Challenges page: all | progress | new | done
		window = {},               -- last page
	},
})
E.Legacy = M

E:RegisterGlobal("legacy", { profiles = {}, nextID = 1 }, {
	title = "Legacy profiles", desc = "Named Legacy builds shared by all your characters.",
})
E:RegisterPrivate("legacy", { draft = {} })

local MAX_PROFILES = 40
local MAX_NAME = 40
local STATUS = { added = "added", removed = "removed", changed = "changed" }
M.STATUS = STATUS

local IsSecret = E.Secret

local function Pass(ok, ...)
	if not ok then return nil end
	return ...
end

-- A protected call: every return value, or nil when it fails.
local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	return Pass(pcall(fn, ...))
end
M.Call = Call

local function Number(value)
	if type(value) ~= "number" or IsSecret(value) then return nil end
	return value
end
M.Number = Number

local function Text(value)
	if type(value) ~= "string" or IsSecret(value) then return nil end
	return value
end

---------------------------------------------------------------------------
-- What the client has
---------------------------------------------------------------------------
function M:Consts()
	local consts = Constants and Constants.LegacyConsts
	return type(consts) == "table" and consts or nil
end

-- The Legacy trees exist on this client and C_Traits can read them.
function M:Supported()
	local consts = self:Consts()
	return consts ~= nil and type(consts.LEGACY_TREE_PROFESSIONS_ID) == "number"
		and C_Traits ~= nil and type(C_Traits.GetConfigIDByTreeID) == "function"
		and type(C_Traits.GetTreeNodes) == "function" and type(C_Traits.GetNodeInfo) == "function"
end

-- The order of Blizzard's tree selection panel (LegacyTreeData).
local TREES = {
	{ const = "LEGACY_TREE_PROFESSIONS_ID", label = "LEGACY_TREE_PROFESSIONS", fallback = Key("Professions") },
	{ const = "LEGACY_TREE_ADVENTURE_ID", label = "LEGACY_TREE_ADVENTURE", fallback = Key("Adventure") },
	{ const = "LEGACY_TREE_PROGRESSION_ID", label = "LEGACY_TREE_PROGRESSION", fallback = Key("Progression") },
}

function M:Trees()
	local consts = self:Consts()
	local list = {}
	if not consts then return list end
	for index, def in ipairs(TREES) do
		local treeID = Number(consts[def.const])
		if treeID then
			local name = Text(rawget(_G, def.label)) or L[def.fallback]
			list[#list + 1] = { index = index, treeID = treeID, name = name }
		end
	end
	return list
end

function M:ConfigID(treeID)
	if not (C_Traits and treeID) then return nil end
	local id = Number(Call(C_Traits.GetConfigIDByTreeID, treeID))
	if id and id > 0 then return id end
end

function M:CurrencyID()
	local consts = self:Consts()
	return consts and Number(consts.LEGACY_POINTS_TRAIT_CURRENCY_ID)
end

-- The Legacy level: renown with the Legacy reward track faction.
function M:Level()
	local consts = self:Consts()
	local faction = consts and Number(consts.LEGACY_REWARD_TRACK_FACTION_ID)
	if not (faction and C_MajorFactions) then return nil end
	return Number(Call(C_MajorFactions.GetCurrentRenownLevel, faction))
end

function M:Unlocked()
	local level = self:Level()
	return level ~= nil and level > 0
end

---------------------------------------------------------------------------
-- Reading the trees (structure and your committed ranks)
---------------------------------------------------------------------------
local entryCache = {}

-- Name, icon and description of a node entry, from its definition.
function M:EntryInfo(configID, entryID)
	if not entryID then return nil end
	local cached = entryCache[entryID]
	if cached then return cached end
	local entry = Call(C_Traits.GetEntryInfo, configID, entryID)
	local definitionID = type(entry) == "table" and Number(entry.definitionID) or nil
	local definition = definitionID and Call(C_Traits.GetDefinitionInfo, definitionID)
	if type(definition) ~= "table" then return nil end
	local spellID = Number(definition.spellID)
	local name = Text(definition.overrideName)
	if (not name or name == "") and spellID and C_Spell then name = Text(Call(C_Spell.GetSpellName, spellID)) end
	local icon = Number(definition.overrideIcon)
	if not icon and spellID and C_Spell then icon = Call(C_Spell.GetSpellTexture, spellID) end
	local description = Text(definition.overrideDescription)
	if (not description or description == "") and spellID and C_Spell then description = Text(Call(C_Spell.GetSpellDescription, spellID)) end
	cached = { name = name or "", icon = icon, spellID = spellID, description = description }
	entryCache[entryID] = cached
	return cached
end

-- Points one rank of a node costs, from C_Traits.GetNodeCost (a node with
-- no cost entry is free).
function M:RankCost(configID, nodeID, currencyID)
	local costs = Call(C_Traits.GetNodeCost, configID, nodeID)
	local total = 0
	if type(costs) ~= "table" then return total end
	for _, cost in ipairs(costs) do
		local amount = type(cost) == "table" and Number(cost.amount) or nil
		local id = type(cost) == "table" and Number(cost.ID) or nil
		if amount and (not currencyID or not id or id == currencyID) then total = total + amount end
	end
	return total
end

local function ReadTree(tree, currencyID)
	local configID = M:ConfigID(tree.treeID)
	if not configID then return nil end
	local nodeIDs = Call(C_Traits.GetTreeNodes, tree.treeID)
	local nodes = {}
	for _, nodeID in ipairs(type(nodeIDs) == "table" and nodeIDs or {}) do
		local info = Call(C_Traits.GetNodeInfo, configID, nodeID)
		local maxRanks = type(info) == "table" and Number(info.maxRanks) or nil
		if maxRanks and maxRanks > 0 and Number(info.ID) and info.ID ~= 0 and info.isVisible ~= false then
			local entries = {}
			for _, entryID in ipairs(type(info.entryIDs) == "table" and info.entryIDs or {}) do
				if Number(entryID) then entries[#entries + 1] = entryID end
			end
			local choice = #entries > 1
			local rank = Number(info.ranksPurchased) or 0
			local active = type(info.activeEntry) == "table" and Number(info.activeEntry.entryID) or nil
			local node = {
				nodeID = nodeID, tree = tree.index, treeID = tree.treeID, configID = configID,
				posX = Number(info.posX) or 0, posY = Number(info.posY) or 0,
				maxRanks = maxRanks, rank = rank, entries = entries, choice = choice,
				entryID = active or (rank > 0 and entries[1]) or nil,
				cost = M:RankCost(configID, nodeID, currencyID),
			}
			local shown = M:EntryInfo(configID, node.entryID or entries[1])
			node.name = shown and shown.name ~= "" and shown.name or L["Node %d"]:format(nodeID)
			node.icon = shown and shown.icon
			nodes[#nodes + 1] = node
		end
	end
	table.sort(nodes, function(a, b)
		if a.posY ~= b.posY then return a.posY < b.posY end
		if a.posX ~= b.posX then return a.posX < b.posX end
		return a.nodeID < b.nodeID
	end)
	return { tree = tree, configID = configID, nodes = nodes }
end

-- The points: unspent, spent, owned (both), the season cap and per tree.
local function ReadCurrency(trees)
	local currency = { trees = {} }
	for _, read in ipairs(trees) do
		local list = Call(C_Traits.GetTreeCurrencyInfo, read.configID, read.tree.treeID, true)
		local info = type(list) == "table" and list[1] or nil
		if type(info) == "table" then
			currency.quantity = currency.quantity or Number(info.quantity)
			currency.spent = currency.spent or Number(info.spent)
			currency.max = currency.max or Number(info.maxQuantity)
			currency.currencyID = currency.currencyID or Number(info.traitCurrencyID)
			currency.trees[read.tree.index] = Number(info.spentInTree)
		end
	end
	if currency.quantity and currency.spent then currency.owned = currency.quantity + currency.spent end
	local id = currency.currencyID or M:CurrencyID()
	if id and C_Traits then currency.sourcedMax = Number(Call(C_Traits.GetMaxAvailableTraitCurrency, id, false)) end
	return currency
end

-- Everything the planner shows about the trees, cached until a trait event.
function M:Snapshot(force)
	if self.snapshot and not force then return self.snapshot end
	if not self:Supported() then return nil end
	local currencyID = self:CurrencyID()
	local trees, byID, list = {}, {}, {}
	for _, tree in ipairs(self:Trees()) do
		local read = ReadTree(tree, currencyID)
		if read then
			trees[#trees + 1] = read
			for _, node in ipairs(read.nodes) do
				byID[node.nodeID] = node
				list[#list + 1] = node
			end
		end
	end
	if #trees == 0 then return nil end
	self.snapshot = {
		trees = trees, nodes = byID, list = list, currency = ReadCurrency(trees),
		level = self:Level(), currencyID = currencyID,
	}
	return self.snapshot
end

function M:Invalidate()
	self.snapshot = nil
end

-- Your committed build as { [nodeID] = { r = ranks, e = entryID } }.
function M:CurrentBuild(snapshot)
	snapshot = snapshot or self:Snapshot()
	local build = {}
	if not snapshot then return build end
	for nodeID, node in pairs(snapshot.nodes) do
		if node.rank > 0 then build[nodeID] = { r = node.rank, e = node.choice and node.entryID or nil } end
	end
	return build
end

---------------------------------------------------------------------------
-- Pure helpers (builds are { [nodeID] = { r, e } })
---------------------------------------------------------------------------
local function Ranks(build, nodeID)
	local item = build and build[nodeID]
	return type(item) == "table" and (tonumber(item.r) or 0) or 0
end

-- Added, removed and changed nodes between two builds.
function M.Diff(current, draft)
	local status, counts = {}, { added = 0, removed = 0, changed = 0, same = 0 }
	local seen = {}
	local function Look(nodeID)
		if seen[nodeID] then return end
		seen[nodeID] = true
		local have, want = Ranks(current, nodeID), Ranks(draft, nodeID)
		local kind
		if have == 0 and want > 0 then
			kind = STATUS.added
		elseif have > 0 and want == 0 then
			kind = STATUS.removed
		elseif have > 0 and want > 0 then
			local e1, e2 = current[nodeID].e, draft[nodeID].e
			if have ~= want or (e1 and e2 and e1 ~= e2) then kind = STATUS.changed else counts.same = counts.same + 1 end
		end
		if kind then
			status[nodeID] = kind
			counts[kind] = counts[kind] + 1
		end
	end
	for nodeID in pairs(current or {}) do Look(nodeID) end
	for nodeID in pairs(draft or {}) do Look(nodeID) end
	return status, counts
end

-- What a build costs: total, per tree, and nodes this client doesn't have.
function M.Cost(build, nodes)
	local total, perTree, unknown = 0, {}, 0
	for nodeID, item in pairs(build or {}) do
		local node = nodes and nodes[nodeID]
		local ranks = type(item) == "table" and (tonumber(item.r) or 0) or 0
		if ranks > 0 then
			if node then
				local cost = ranks * (node.cost or 0)
				total = total + cost
				perTree[node.tree] = (perTree[node.tree] or 0) + cost
			else
				unknown = unknown + 1
			end
		end
	end
	return total, perTree, unknown
end

-- A build cleaned against the trees: unknown nodes dropped, ranks clamped,
-- a choice kept only when the node offers it.
function M.Clean(build, nodes)
	local clean, dropped = {}, 0
	for nodeID, item in pairs(type(build) == "table" and build or {}) do
		nodeID = tonumber(nodeID)
		local node = nodeID and nodes and nodes[nodeID]
		local ranks = type(item) == "table" and math.floor(tonumber(item.r) or 0) or 0
		if node and ranks > 0 then
			ranks = math.min(ranks, node.maxRanks)
			local entryID = type(item) == "table" and tonumber(item.e) or nil
			if node.choice then
				local offered = false
				for _, id in ipairs(node.entries) do if id == entryID then offered = true end end
				if not offered then entryID = node.entries[1] end
			else
				entryID = nil
			end
			clean[nodeID] = { r = ranks, e = entryID }
		elseif ranks > 0 then
			dropped = dropped + 1
		end
	end
	return clean, dropped
end

local function CopyBuild(build)
	local copy = {}
	for nodeID, item in pairs(build or {}) do
		if type(item) == "table" and (tonumber(item.r) or 0) > 0 then copy[tonumber(nodeID) or nodeID] = { r = item.r, e = item.e } end
	end
	return copy
end
M.CopyBuild = CopyBuild

function M.CountRanks(build)
	local ranks = 0
	for _, item in pairs(build or {}) do ranks = ranks + (type(item) == "table" and (tonumber(item.r) or 0) or 0) end
	return ranks
end

-- The cost check: "ok", "short" (more than the points you own) or "cap"
-- (over the season cap, so it can't be made this season).
function M.Check(cost, currency)
	currency = currency or {}
	if currency.max and cost > currency.max then return "cap", cost - currency.max end
	if currency.owned and cost > currency.owned then return "short", cost - currency.owned end
	return "ok", currency.owned and (currency.owned - cost) or nil
end

---------------------------------------------------------------------------
-- The draft (per character) and profiles (account-wide)
---------------------------------------------------------------------------
function M:Draft()
	local store = E:GetPrivate("legacy")
	if type(store.draft) ~= "table" then store.draft = {} end
	return store.draft
end

function M:SetDraft(build)
	E:GetPrivate("legacy").draft = CopyBuild(build)
	self:Changed()
end

function M:CopyCurrent()
	self:SetDraft(self:CurrentBuild())
end

function M:ClearDraft()
	self:SetDraft({})
end

-- Add (delta 1) or take away (-1) a rank in the draft.
function M:DraftRank(nodeID, delta)
	local snapshot = self:Snapshot()
	local node = snapshot and snapshot.nodes[nodeID]
	if not node then return false end
	local draft = self:Draft()
	local item = draft[nodeID]
	local ranks = math.max(0, math.min(node.maxRanks, Ranks(draft, nodeID) + delta))
	if ranks == Ranks(draft, nodeID) then return false end
	if ranks == 0 then
		draft[nodeID] = nil
	else
		local entryID = item and item.e
		if node.choice and not entryID then entryID = node.entryID or node.entries[1] end
		draft[nodeID] = { r = ranks, e = node.choice and entryID or nil }
	end
	self:Changed()
	return true
end

-- A choice node: the next option in the draft.
function M:DraftSwap(nodeID)
	local snapshot = self:Snapshot()
	local node = snapshot and snapshot.nodes[nodeID]
	if not (node and node.choice) then return false end
	local draft = self:Draft()
	local item = draft[nodeID]
	if not item then
		draft[nodeID] = { r = 1, e = node.entries[1] }
	else
		local index = 1
		for i, entryID in ipairs(node.entries) do if entryID == item.e then index = i end end
		item.e = node.entries[index % #node.entries + 1]
	end
	self:Changed()
	return true
end

function M:Profiles()
	local store = E:GetGlobal("legacy")
	if type(store.profiles) ~= "table" then store.profiles = {} end
	return store.profiles
end

function M:FindProfile(id)
	for _, profile in ipairs(self:Profiles()) do
		if profile.id == id then return profile end
	end
end

local function CleanName(name)
	name = type(name) == "string" and strtrim((name:gsub("|", ""))) or ""
	return E:Utf8Clip(name, MAX_NAME)
end
M.CleanName = CleanName

function M:UniqueName(base, except)
	base = CleanName(base)
	if base == "" then base = L["Legacy build"] end
	local taken = {}
	for _, profile in ipairs(self:Profiles()) do
		if profile.id ~= except then taken[profile.name:lower()] = true end
	end
	if not taken[base:lower()] then return base end
	for n = 2, 99 do
		local name = ("%s %d"):format(base, n)
		if not taken[name:lower()] then return name end
	end
	return base
end

function M:SaveProfile(name, build)
	local list = self:Profiles()
	if #list >= MAX_PROFILES then return nil, L["You have %d profiles, the most there can be. Delete one first."]:format(MAX_PROFILES) end
	local store = E:GetGlobal("legacy")
	local id = tonumber(store.nextID) or 1
	store.nextID = id + 1
	local profile = { id = id, name = self:UniqueName(name), build = CopyBuild(build or self:Draft()), created = time(), updated = time() }
	list[#list + 1] = profile
	self:Changed()
	return profile
end

function M:OverwriteProfile(id, build)
	local profile = self:FindProfile(id)
	if not profile then return false end
	profile.build = CopyBuild(build or self:Draft())
	profile.updated = time()
	self:Changed()
	return true
end

function M:RenameProfile(id, name)
	local profile = self:FindProfile(id)
	name = CleanName(name)
	if not profile or name == "" then return false end
	profile.name = self:UniqueName(name, id)
	self:Changed()
	return true
end

function M:DeleteProfile(id)
	local list = self:Profiles()
	for index, profile in ipairs(list) do
		if profile.id == id then
			table.remove(list, index)
			self:Changed()
			return true
		end
	end
	return false
end

-- Loads a profile into the draft (your Legacy points don't change).
function M:LoadProfile(id)
	local profile = self:FindProfile(id)
	if not profile then return false end
	local snapshot = self:Snapshot()
	local build, dropped = profile.build, 0
	if snapshot then build, dropped = M.Clean(profile.build, snapshot.nodes) end
	self:SetDraft(build)
	return true, dropped
end

---------------------------------------------------------------------------
-- Legacy Challenges (the achievement API)
---------------------------------------------------------------------------
local function TopCategory(categoryID)
	local id, name = categoryID, nil
	for _ = 1, 10 do
		local catName, parentID = Call(GetCategoryInfo, id)
		name = Text(catName) or name
		parentID = Number(parentID)
		if not parentID or parentID == -1 or parentID == id then break end
		id = parentID
	end
	return id, name
end

local function Progress(achievementID)
	local count = Number(Call(GetAchievementNumCriteria, achievementID)) or 0
	if count == 0 then return nil end
	local done, quantity, required = 0, nil, nil
	for index = 1, count do
		local _, _, completed, have, need = Call(GetAchievementCriteriaInfo, achievementID, index)
		if completed then done = done + 1 end
		if count == 1 then quantity, required = Number(have), Number(need) end
	end
	if count == 1 and quantity and required and required > 1 then
		return math.min(quantity, required) / required, quantity, required
	end
	return done / count, done, count
end

-- Every challenge: id, name, description, icon, category, the top category,
-- Legacy points, done, progress (0..1) and its numbers, and a state
-- (done, progress or new).
function M:Challenges(force)
	if self.challenges and not force then return self.challenges end
	local list, seen, categories = {}, {}, {}
	if type(GetCategoryList) ~= "function" or type(GetCategoryNumAchievements) ~= "function" then
		self.challenges = list
		return list, categories
	end
	local currencyID = self:CurrencyID()
	for _, categoryID in ipairs(Call(GetCategoryList) or {}) do
		local count = Number(Call(GetCategoryNumAchievements, categoryID)) or 0
		local categoryName = Text(Call(GetCategoryInfo, categoryID)) or ""
		local topID, topName = TopCategory(categoryID)
		for index = 1, count do
			local id, name, _, completed, month, day, year, description, _, icon, _, _, earnedByMe = Call(GetAchievementInfo, categoryID, index)
			id = Number(id)
			if id and not seen[id] then
				seen[id] = true
				local points = currencyID and C_Traits and Number(Call(C_Traits.GetTraitCurrencyForAchievement, currencyID, id)) or nil
				local done = completed == true and earnedByMe ~= false
				local progress, have, need = Progress(id)
				if done then progress = 1 end
				local item = {
					id = id, name = Text(name) or "", description = Text(description) or "", icon = icon,
					category = categoryID, categoryName = categoryName, top = topID, topName = topName or categoryName,
					points = points, done = done, progress = progress, have = have, need = need,
					date = done and day and month and year and ("%02d-%02d-%02d"):format(year % 100, month, day) or nil,
				}
				item.state = done and "done" or ((progress or 0) > 0 and "progress" or "new")
				list[#list + 1] = item
				categories[topID] = topName or categoryName
			end
		end
	end
	self.challenges = list
	self.challengeCategories = categories
	return list, categories
end

function M:ChallengeCategories()
	if not self.challenges then self:Challenges() end
	local sorted = {}
	for id, name in pairs(self.challengeCategories or {}) do sorted[#sorted + 1] = { id = id, name = name } end
	table.sort(sorted, function(a, b) return a.name < b.name end)
	return sorted
end

-- Filter: status (all | done | progress | new), top category id or nil,
-- search text (name or description, any case).
function M.FilterChallenges(list, status, category, search)
	local out = {}
	search = E:FoldText(search)
	for _, item in ipairs(list or {}) do
		local keep = status == nil or status == "all" or item.state == status
		if keep and category then keep = item.top == category end
		if keep and search ~= "" then
			keep = E:FoldText(item.name):find(search, 1, true) ~= nil or E:FoldText(item.description):find(search, 1, true) ~= nil
		end
		if keep then out[#out + 1] = item end
	end
	table.sort(out, function(a, b)
		if a.done ~= b.done then return not a.done end
		if (a.progress or 0) ~= (b.progress or 0) then return (a.progress or 0) > (b.progress or 0) end
		return a.name < b.name
	end)
	return out
end

---------------------------------------------------------------------------
-- Alts: a small Legacy summary in the Characters store
---------------------------------------------------------------------------
function M:RecordAlts()
	if not self.db.recordAlts then return false end
	local C = E.Characters
	if not (C and C.Recording and C:Recording()) then return false end
	local snapshot = self:Snapshot()
	if not (snapshot and snapshot.currency.owned) then return false end
	local me = C:Me()
	local currency = snapshot.currency
	me.legacy = {
		spent = currency.spent, owned = currency.owned, cap = currency.max, level = snapshot.level,
		trees = { currency.trees[1], currency.trees[2], currency.trees[3] }, at = time(),
	}
	if C.FireUpdated then C:FireUpdated("legacy") end
	return true
end

-- The Characters window's Overview gets a Legacy column (its Columns menu).
local function AddCharactersColumn()
	local characters = E.modules and E.modules.Characters
	if not (characters and type(characters.COLUMNS) == "table" and type(characters.COLUMN_BY_KEY) == "table") then return end
	if characters.COLUMN_BY_KEY.legacy then return end
	local column = {
		key = "legacy", title = L["Legacy"], width = 58, align = "RIGHT",
		desc = L["Legacy points spent of the points the character had, as of its last login (Legacy Planner)."],
		value = function(r) return type(r.legacy) == "table" and r.legacy.spent or -1 end,
		text = function(r)
			local legacy = type(r.legacy) == "table" and r.legacy or nil
			if not (legacy and legacy.spent) then return "" end
			return ("%d/%d"):format(legacy.spent, legacy.owned or legacy.spent)
		end,
	}
	characters.COLUMNS[#characters.COLUMNS + 1] = column
	characters.COLUMN_BY_KEY.legacy = column
end
AddCharactersColumn()

---------------------------------------------------------------------------
-- The in-game probe: what the live client answers (/eui legacy probe)
---------------------------------------------------------------------------
local function YesNo(value) return value and L["yes"] or L["no"] end

local function Has(path)
	local tbl, name = path:match("^(.-)%.(.+)$")
	local holder = tbl and rawget(_G, tbl)
	return type(holder) == "table" and type(holder[name]) == "function"
end

function M:ProbeLines()
	local lines = {}
	local function Add(text) lines[#lines + 1] = text end
	local consts = self:Consts()
	if not consts then
		Add(L["Constants.LegacyConsts: missing. This client has no Legacy system."])
		return lines
	end
	Add(L["Constants.LegacyConsts: faction %s, currency %s, trees %s / %s / %s"]:format(tostring(consts.LEGACY_REWARD_TRACK_FACTION_ID),
		tostring(consts.LEGACY_POINTS_TRAIT_CURRENCY_ID), tostring(consts.LEGACY_TREE_PROFESSIONS_ID),
		tostring(consts.LEGACY_TREE_ADVENTURE_ID), tostring(consts.LEGACY_TREE_PROGRESSION_ID)))
	local apis = {}
	for _, path in ipairs({ "C_Traits.GetConfigIDByTreeID", "C_Traits.GetTreeNodes", "C_Traits.GetNodeInfo", "C_Traits.GetNodeCost",
		"C_Traits.GetTreeCurrencyInfo", "C_Traits.GetMaxAvailableTraitCurrency", "C_Traits.GetTraitCurrencyForAchievement",
		"C_Traits.GenerateImportString", "C_MajorFactions.GetCurrentRenownLevel" }) do
		apis[#apis + 1] = path:gsub("^C_%a+%.", "") .. " " .. YesNo(Has(path))
	end
	Add(L["API: %s"]:format(table.concat(apis, ", ")))
	local level = self:Level()
	Add(L["Legacy level (renown): %s, unlocked: %s"]:format(tostring(level), YesNo(level and level > 0)))
	local snapshot = self:Snapshot(true)
	for _, tree in ipairs(self:Trees()) do
		local configID = self:ConfigID(tree.treeID)
		local all = configID and Call(C_Traits.GetTreeNodes, tree.treeID)
		local read
		for _, r in ipairs(snapshot and snapshot.trees or {}) do if r.tree.treeID == tree.treeID then read = r end end
		local spentHere = snapshot and snapshot.currency.trees[tree.index]
		Add(L["Tree %s (%d): config %s, %d of %d nodes shown, %s spent here"]:format(tree.name, tree.treeID, tostring(configID),
			read and #read.nodes or 0, type(all) == "table" and #all or 0, tostring(spentHere)))
	end
	local currency = snapshot and snapshot.currency or {}
	Add(L["Points: %s unspent, %s spent, %s owned, cap (maxQuantity) %s, most available %s"]:format(tostring(currency.quantity),
		tostring(currency.spent), tostring(currency.owned), tostring(currency.max), tostring(currency.sourcedMax)))
	local costs = {}
	for _, node in ipairs(snapshot and snapshot.list or {}) do costs[node.cost] = (costs[node.cost] or 0) + 1 end
	local parts = {}
	for cost, count in pairs(costs) do parts[#parts + 1] = L["%d pt x%d"]:format(cost, count) end
	table.sort(parts)
	Add(L["Rank costs seen: %s"]:format(#parts > 0 and table.concat(parts, ", ") or L["none"]))
	local configID = snapshot and snapshot.trees[1] and snapshot.trees[1].configID
	if configID and Has("C_Traits.GenerateImportString") then
		local text = Call(C_Traits.GenerateImportString, configID)
		Add(L["Blizzard import string for the first Legacy tree: %s"]:format(type(text) == "string" and text ~= "" and L["%d characters"]:format(#text) or L["none"]))
	end
	local list = self:Challenges(true)
	local done, points = 0, 0
	for _, item in ipairs(list) do
		if item.done then done = done + 1 end
		points = points + (item.points or 0)
	end
	Add(L["Challenges: %d in %d categories, %d done, %d Legacy points in all"]:format(#list, #self:ChallengeCategories(), done, points))
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_LegacySystem")
	Add(L["Blizzard_LegacySystem loaded: %s, LegacySystemFrame: %s"]:format(YesNo(loaded), YesNo(rawget(_G, "LegacySystemFrame") ~= nil)))
	return lines
end

function M:Probe()
	E:Print(L["Legacy probe (what this client answers):"])
	for _, line in ipairs(self:ProbeLines()) do E:Print("  " .. line) end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function M:Changed()
	if self.RefreshWindow then self:RefreshWindow() end
end

local TRAIT_EVENTS = { "TRAIT_CONFIG_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED", "TRAIT_NODE_CHANGED" }
local ACHIEVEMENT_EVENTS = { "ACHIEVEMENT_EARNED", "CRITERIA_UPDATE" }

local function OnTraitEvent()
	M:Invalidate()
	if M.recordTimer then return end
	M.recordTimer = true
	C_Timer.After(1, function()
		M.recordTimer = nil
		if not M.active then return end
		M:RecordAlts()
		M:Changed()
	end)
end

local function OnAchievementEvent()
	M.challenges = nil
	if M.challengeTimer then return end
	M.challengeTimer = true
	C_Timer.After(1, function()
		M.challengeTimer = nil
		if M.active then M:Changed() end
	end)
end

local function OnRenown(_, _, factionID)
	local consts = M:Consts()
	if consts and factionID == consts.LEGACY_REWARD_TRACK_FACTION_ID then OnTraitEvent() end
end

function M:OnEnable()
	for _, event in ipairs(TRAIT_EVENTS) do self:RegisterEvent(event, OnTraitEvent) end
	for _, event in ipairs(ACHIEVEMENT_EVENTS) do self:RegisterEvent(event, OnAchievementEvent) end
	self:RegisterEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", OnRenown)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", OnTraitEvent)
	if self.ApplyBlizzard then self:ApplyBlizzard() end
	OnTraitEvent()
end

function M:OnDisable()
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
-- Slash command: /eui legacy [probe | export | import | on | off | config]
---------------------------------------------------------------------------
local function NeedsModule()
	if M.active then return true end
	E:Print(E:ModuleOffHint("Legacy"))
	return false
end

local function Command(arg)
	local word = ((arg or ""):match("^(%S*)") or ""):lower()
	if word == "on" or word == "off" then
		E:SetModuleFromCommand("Legacy", word == "on")
		return
	elseif word == "config" or word == "options" then
		E:ToggleConfig("module:Legacy")
		return
	elseif word == "probe" then
		-- Works with the module off too: it only reads.
		M:Probe()
		return
	end
	if not NeedsModule() then return end
	if word == "" then
		M:TogglePlanner()
	elseif word == "export" then
		M:ExportDraft()
	elseif word == "import" then
		M:ShowImportBox()
	elseif word == "challenges" then
		M:OpenPlanner("challenges")
	else
		E:Print(L["Unknown option. Try /eui help legacy."])
	end
end

E:AddCommand("legacy", "[challenges | probe | export | import | config | on | off]  the Legacy Planner: plan Legacy points (never spends them), browse challenges, or print what the client answers", Command, "Tools")
