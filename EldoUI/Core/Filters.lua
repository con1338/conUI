-- EldoUI aura filters: account-wide spell lists and per-widget
-- filter groups, handed to the client's aura containers (12.x candidate
-- filters). The client decides which auras pass; EldoUI never reads an
-- aura in Lua to decide anything (aura data is secret in combat).
--
-- Spell lists (account-wide, EldoUIDB.auraFilters):
--   E:GetAuraFilterLists()                 sorted list names
--   E:GetAuraFilterList(name)              { kind = "allow"|"block", spells = { [id] = true }, builtin }
--   E:CreateAuraFilterList(name, kind)     E:RenameAuraFilterList(old, new)
--   E:DeleteAuraFilterList(name)           E:ResetAuraFilterLists()
--   E:AddAuraFilterSpell(name, input)      input: spell ID, name or chat link
--   E:RemoveAuraFilterSpell(name, id)
--   E:ExportAuraFilterList(name)           E:ImportAuraFilterList(text)
--
-- Per widget (a block in the module's settings, see E:AuraFilterDefaults):
--   E:AuraFilterGroups(block, kind, total, opts) the groups for AddAuraGroup
--   E:ApplyAuraFilters(container, block, kind, total, opts)  update in place
--   E:TrackAuraContainer(container, block, kind, total, opts) keep it updated
--     opts.suffix: kept on every filter string ("|INCLUDE_NAME_PLATE_ONLY")
--   E:AuraFilterSignature(block, kind)     changes only when a rebuild is needed
--   E:AuraFilterOptions(prefix, opts)      the editor rows for a module page
--   E:AuraSlotSpec(listName, kind)         filter + options for AddAuraSlot
--   E:AuraSpellSlotSpec(id, kind, mine)    filter + candidate filters for one spell's slot
--   E:AuraHighlightSpec(which)             filter + candidate filters for a highlight
--
-- How a group reaches the client:
--   filter string    "HELPFUL" / "HARMFUL" plus PLAYER, RAID, CANCELABLE and
--                    one client flag (IMPORTANT, CROWD_CONTROL ...)
--   candidateFilters includeSpellIDs (allow list), excludeSpellIDs (block
--                    list and "Never show"), maxDuration, and the client's
--                    yes/no flags (from you, boss aura, stealable ...)
-- The client only applies spell lists where Blizzard allows it (helpful
-- auras on friends, harmful auras on enemies, never-secret spells); that
-- is the rule, and EldoUI doesn't try to get round it.
--
-- Dropped by rule: Lua-side priority filters (personal, CC, minimum
-- duration computed in Lua) and C_UnitAuras.AddBlockedAura: it blocks one
-- aura instance, so a spell list would need EldoUI to read live auras'
-- spell IDs, which is not allowed in combat. Exclude sets do the same job
-- inside the client.
-- Written from scratch for EldoUI. The starter lists are our own and
-- start empty; no spell tables are copied from anywhere.
local _, E = ...
local L = E.L

local issecret = issecretvalue or function() return false end

local MAX_GROUPS = 4
local NEVER_SHOW = "Never show"
local WATCH_LIST = "Watch list"

---------------------------------------------------------------------------
-- What the client offers (Blizzard_AuraContainer on Forever 1.60.1)
---------------------------------------------------------------------------
-- Extra filter-string flags, one per group.
E.AURA_FILTER_FLAGS = {
	[""] = "None",
	IMPORTANT = "Important",
	CROWD_CONTROL = "Crowd control",
	BIG_DEFENSIVE = "Big defensives",
	EXTERNAL_DEFENSIVE = "External defensives",
	RAID_IN_COMBAT = "Raid frame auras (in combat)",
	RAID_PLAYER_DISPELLABLE = "Dispellable by your group",
	DISPELLABLE = "Dispellable by anyone",
}

-- The client's yes / no / don't care candidate flags.
E.AURA_CANDIDATE_FLAGS = {
	{ key = "isFromPlayerOrPlayerPet", label = "Cast by you or your pet", desc = "Yes: only auras you or your pet applied. No: only other people's." },
	{ key = "isBossAura", label = "Boss aura", desc = "Auras the game marks as boss auras." },
	{ key = "isBossOrRoleAura", label = "Boss or role aura", desc = "Boss auras and auras the game marks as important for your role." },
	{ key = "isStealable", label = "Stealable", desc = "Buffs that can be stolen or purged." },
	{ key = "canApplyAura", label = "You can apply it", desc = "Buffs you could cast yourself." },
	{ key = "isPriorityAura", label = "Priority aura", desc = "Auras the game shows with priority on raid frames." },
	{ key = "nameplateShowAll", label = "Shown on every nameplate", desc = "Auras the game shows on all nameplates." },
	{ key = "nameplateShowPersonal", label = "Shown on the personal nameplate", desc = "Auras the game shows on your personal resource display." },
}
local TRISTATE = { any = "Don't care", yes = "Yes", no = "No" }

local SORT = { TIME = "Expiration", NAME = "Name", INDEX = "Default", IMPORTANT = "ImportantOnly" }

-- One probe, out of combat at login: can this client's containers take
-- candidate filters at all? Without them only filter strings are used,
-- and the options that need them are hidden.
local supported
function E:AuraFiltersSupported()
	if supported ~= nil then return supported end
	if InCombatLockdown() then return false end
	supported = false
	local ok, probe = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
	if ok and probe then
		supported = type(probe.SetAuraGroupCandidateFilters) == "function"
		probe:Hide()
	end
	return supported
end

---------------------------------------------------------------------------
-- Account-wide lists
---------------------------------------------------------------------------
local function Store()
	EldoUIDB = EldoUIDB or {}
	local store = EldoUIDB.auraFilters
	if type(store) ~= "table" then
		store = {}
		EldoUIDB.auraFilters = store
	end
	store.lists = type(store.lists) == "table" and store.lists or {}
	for name, kind in pairs({ [NEVER_SHOW] = "block", [WATCH_LIST] = "allow" }) do
		local list = store.lists[name]
		if type(list) ~= "table" then
			list = {}
			store.lists[name] = list
		end
		list.kind = kind
		list.builtin = true
		list.spells = type(list.spells) == "table" and list.spells or {}
	end
	return store
end

local listeners = {}
local tracked = setmetatable({}, { __mode = "k" })   -- container -> { block, kind, total }

local function Changed()
	for container, info in pairs(tracked) do
		E:RunOutOfCombat(function()
			if tracked[container] == info then E:ApplyAuraFilters(container, info.block, info.kind, info.total, info.opts) end
		end)
	end
	for _, fn in pairs(listeners) do
		local ok, err = pcall(fn)
		if not ok then geterrorhandler()(err) end
	end
end

-- fn() runs after any list changes (modules that rebuild their own way).
function E:OnAuraFiltersChanged(owner, fn)
	listeners[owner] = fn
end

function E:GetAuraFilterLists(kind)
	local names = {}
	for name, list in pairs(Store().lists) do
		if not kind or list.kind == kind then names[#names + 1] = name end
	end
	table.sort(names)
	return names
end

function E:GetAuraFilterList(name)
	return name and Store().lists[name] or nil
end

local function CleanName(name)
	if type(name) ~= "string" then return nil end
	name = strtrim((name:gsub("[|:\n]", "")))
	if name == "" or #name > 40 then return nil end
	return name
end

function E:CreateAuraFilterList(name, kind)
	name = CleanName(name)
	local store = Store()
	if not name or store.lists[name] then return false end
	store.lists[name] = { kind = kind == "allow" and "allow" or "block", spells = {} }
	Changed()
	return name
end

function E:RenameAuraFilterList(old, new)
	new = CleanName(new)
	local store = Store()
	local list = store.lists[old]
	if not list or list.builtin or not new or store.lists[new] then return false end
	store.lists[new], store.lists[old] = list, nil
	Changed()
	return new
end

function E:DeleteAuraFilterList(name)
	local store = Store()
	local list = store.lists[name]
	if not list or list.builtin then return false end
	store.lists[name] = nil
	Changed()
	return true
end

-- Built-in lists back to empty; your own lists stay.
function E:ResetAuraFilterLists()
	local store = Store()
	for _, list in pairs(store.lists) do
		if list.builtin then wipe(list.spells) end
	end
	Changed()
end

-- A spell from an ID, a name the client knows, or a chat link.
function E:ResolveSpell(input)
	if type(input) == "number" then input = tostring(input) end
	if type(input) ~= "string" then return nil end
	input = strtrim(input)
	if input == "" then return nil end
	local id = tonumber(input) or tonumber(input:match("|Hspell:(%d+)"))
	if not id and C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, input)
		if ok and type(info) == "table" and not issecret(info.spellID) then id = info.spellID end
	end
	if not id or id <= 0 or id ~= math.floor(id) then return nil end
	if C_Spell and C_Spell.GetSpellName then
		local ok, name = pcall(C_Spell.GetSpellName, id)
		if not ok or type(name) == "nil" then return nil end
	end
	return id
end

function E:SpellLabel(id)
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
	if type(name) == "string" and not issecret(name) then return ("%s (%d)"):format(name, id) end
	return tostring(id)
end

function E:AddAuraFilterSpell(listName, input)
	local list = self:GetAuraFilterList(listName)
	local id = self:ResolveSpell(input)
	if not (list and id) then return false end
	list.spells[id] = true
	Changed()
	return id
end

function E:RemoveAuraFilterSpell(listName, id)
	local list = self:GetAuraFilterList(listName)
	id = tonumber(id)
	if not (list and id and list.spells[id]) then return false end
	list.spells[id] = nil
	Changed()
	return true
end

-- Share string: "!EUIF1!<kind>:<name>:<id>,<id>,..." (plain text, read
-- by our own parser; nothing is ever run as code).
local PREFIX = "!EUIF1!"

function E:ExportAuraFilterList(name)
	local list = self:GetAuraFilterList(name)
	if not list then return nil end
	local ids = {}
	for id in pairs(list.spells) do ids[#ids + 1] = id end
	table.sort(ids)
	return ("%s%s:%s:%s"):format(PREFIX, list.kind, name, table.concat(ids, ","))
end

-- Returns the list name it went into, or nil and a reason.
function E:ImportAuraFilterList(text)
	if type(text) ~= "string" then return nil, L["That is not a filter list string."] end
	text = strtrim(text)
	local kind, name, ids = text:match("^" .. PREFIX:gsub("%p", "%%%0") .. "(%a+):([^:]*):([%d,]*)$")
	if not kind or (kind ~= "allow" and kind ~= "block") then return nil, L["That is not an EldoUI filter list string."] end
	name = CleanName(name)
	if not name then return nil, L["The list in that string has no usable name."] end
	local store = Store()
	-- Never overwrite: "Name (2)" when the name is taken.
	local final, n = name, 1
	while store.lists[final] do
		n = n + 1
		final = ("%s (%d)"):format(name, n)
	end
	local spells = {}
	for id in ids:gmatch("%d+") do
		id = tonumber(id)
		if id and id > 0 then spells[id] = true end
	end
	store.lists[final] = { kind = kind, spells = spells }
	Changed()
	return final
end

-- A copy of a list's spells as the set the client wants, or nil.
local function SpellSet(name, into)
	local list = name and name ~= "" and E:GetAuraFilterList(name)
	if not list or not next(list.spells) then return into end
	into = into or {}
	for id in pairs(list.spells) do into[id] = true end
	return into
end

---------------------------------------------------------------------------
-- Per-widget filter blocks
---------------------------------------------------------------------------
local function GroupDefaults(kind)
	local flags = {}
	for _, flag in ipairs(E.AURA_CANDIDATE_FLAGS) do flags[flag.key] = "any" end
	return {
		enabled = false, kind = kind or "HELPFUL", player = false, notPlayer = false, raid = false,
		cancelable = false, extra = "", allow = "", block = "", maxDuration = 0, max = 0, sort = "TIME",
		flags = flags,
	}
end

-- defaults for a module: E:AuraFilterDefaults("HARMFUL", "mine")
function E:AuraFilterDefaults(kind, preset)
	local block = { preset = preset or "all", useNeverShow = true, edit = 1, groups = {} }
	for index = 1, MAX_GROUPS do block.groups[index] = GroupDefaults(kind) end
	block.groups[1].enabled = true
	return block
end

-- Presets: groups written by the client's own flags, per aura kind.
local PRESETS = {
	HELPFUL = {
		all = { title = "All", groups = { {} } },
		mine = { title = "Mine", groups = { { player = true } } },
		important = { title = "Important", groups = { { extra = "IMPORTANT" } } },
		dispellable = { title = "Purgeable", groups = { { extra = "RAID_PLAYER_DISPELLABLE" } } },
		hots = { title = "My heals over time", groups = { { player = true, extra = "RAID_IN_COMBAT" } } },
		defensives = { title = "Defensives", groups = { { extra = "BIG_DEFENSIVE" }, { extra = "EXTERNAL_DEFENSIVE" } } },
	},
	HARMFUL = {
		all = { title = "All", groups = { {} } },
		mine = { title = "Mine", groups = { { player = true } } },
		important = { title = "Important", groups = { { flags = { isBossOrRoleAura = "yes" } } } },
		dispellable = { title = "Dispellable by you", groups = { { raid = true } } },
		cc = { title = "Crowd control", groups = { { extra = "CROWD_CONTROL" } } },
	},
}
E.AURA_FILTER_PRESETS = PRESETS

local function Tri(value)
	if value == "yes" then return true end
	if value == "no" then return false end
	return nil
end

local function FilterString(group, kind)
	local parts = { (group.kind == "HARMFUL" or group.kind == "HELPFUL") and group.kind or kind }
	if group.player then parts[#parts + 1] = "PLAYER" elseif group.notPlayer then parts[#parts + 1] = "!PLAYER" end
	if group.raid then parts[#parts + 1] = "RAID" end
	if group.cancelable then parts[#parts + 1] = "CANCELABLE" end
	if group.extra and E.AURA_FILTER_FLAGS[group.extra] and group.extra ~= "" then parts[#parts + 1] = group.extra end
	return table.concat(parts, "|")
end

local function CandidateFilters(group, block)
	if not E:AuraFiltersSupported() then return nil end
	local cf = {}
	cf.includeSpellIDs = SpellSet(group.allow)
	local exclude = SpellSet(group.block)
	if block.useNeverShow ~= false then exclude = SpellSet(NEVER_SHOW, exclude) end
	cf.excludeSpellIDs = exclude
	local maxDuration = tonumber(group.maxDuration) or 0
	if maxDuration > 0 then cf.maxDuration = maxDuration end
	for _, flag in ipairs(E.AURA_CANDIDATE_FLAGS) do
		local value = Tri(group.flags and group.flags[flag.key])
		if value ~= nil then cf[flag.key] = value end
	end
	if next(cf) == nil then return nil end
	return cf
end

local function SortOf(group)
	local method = _G.AuraContainerSortMethod
	local direction = _G.AuraContainerSortDirection
	return method and method[SORT[group.sort] or "Default"], direction and direction.Normal
end

-- The groups a block stands for, ready for container:AddAuraGroup:
--   { key, filter, candidateFilters, maxFrameCount, sortMethod, sortDirection }
-- total: the widget's icon limit, shared by groups without their own.
function E:AuraFilterGroups(block, kind, total, opts)
	kind = kind == "HARMFUL" and "HARMFUL" or "HELPFUL"
	block = type(block) == "table" and block or self:AuraFilterDefaults(kind)
	local source = {}
	local preset = PRESETS[kind][block.preset]
	if preset then
		for _, overrides in ipairs(preset.groups) do
			local group = GroupDefaults(kind)
			for key, value in pairs(overrides) do
				if key == "flags" then
					for flag, state in pairs(value) do group.flags[flag] = state end
				else
					group[key] = value
				end
			end
			group.enabled = true
			source[#source + 1] = group
		end
	else
		for index = 1, MAX_GROUPS do
			local group = block.groups and block.groups[index]
			if type(group) == "table" and group.enabled then source[#source + 1] = group end
		end
		if #source == 0 then
			local group = GroupDefaults(kind)
			group.enabled = true
			source[1] = group
		end
	end
	total = math.max(tonumber(total) or 16, 1)
	local share = math.max(math.floor(total / #source), 1)
	local suffix = opts and type(opts.suffix) == "string" and opts.suffix or ""
	local out = {}
	for index, group in ipairs(source) do
		local method, direction = SortOf(group)
		local own = tonumber(group.max) or 0
		out[index] = {
			key = "group" .. index,
			filter = FilterString(group, kind) .. suffix,
			candidateFilters = CandidateFilters(group, block),
			maxFrameCount = own > 0 and math.min(own, total) or share,
			sortMethod = method,
			sortDirection = direction,
		}
	end
	return out
end

-- Changes only when the number of groups changes (the container must be
-- rebuilt then); everything else is updated in place.
function E:AuraFilterSignature(block, kind)
	return ("filters:%d"):format(#self:AuraFilterGroups(block, kind, 1))
end

-- Update a container's groups in place (out of combat). Returns false when
-- the container must be rebuilt (other group count, or no setters).
function E:ApplyAuraFilters(container, block, kind, total, opts)
	if not container or InCombatLockdown() then return false end
	local groups = self:AuraFilterGroups(block, kind, total, opts)
	if type(container.HasAuraGroup) ~= "function" or type(container.SetAuraGroupFilterString) ~= "function" then return false end
	for _, group in ipairs(groups) do
		local ok, has = pcall(container.HasAuraGroup, container, group.key)
		if not ok or not has then return false end
	end
	local nextKey = "group" .. (#groups + 1)
	local okNext, hasNext = pcall(container.HasAuraGroup, container, nextKey)
	if okNext and hasNext then return false end
	for _, group in ipairs(groups) do
		pcall(container.SetAuraGroupFilterString, container, group.key, group.filter)
		if container.SetAuraGroupCandidateFilters then
			pcall(container.SetAuraGroupCandidateFilters, container, group.key, group.candidateFilters)
		end
		if container.SetAuraGroupMaxFrameCount then
			pcall(container.SetAuraGroupMaxFrameCount, container, group.key, group.maxFrameCount)
		end
		if container.SetAuraGroupSortMethod and group.sortMethod then
			pcall(container.SetAuraGroupSortMethod, container, group.key, group.sortMethod, group.sortDirection)
		end
	end
	return true
end

function E:TrackAuraContainer(container, block, kind, total, opts)
	if container then tracked[container] = { block = block, kind = kind, total = total, opts = opts } end
end

function E:UntrackAuraContainer(container)
	if container then tracked[container] = nil end
end

-- One fixed slot (AddAuraSlot) for the spells of a list: "my Renew always
-- top-left". Returns filter, options or nil when the list is empty.
function E:AuraSlotSpec(listName, kind)
	local include = SpellSet(listName)
	if not include or not self:AuraFiltersSupported() then return nil end
	local method, direction = SortOf({ sort = "TIME" })
	return (kind == "HARMFUL" and "HARMFUL" or "HELPFUL"),
		{ candidateFilters = { includeSpellIDs = include }, sortMethod = method, sortDirection = direction }
end

-- One slot for one spell (aura groups, the cooldown rows' aura glow):
-- filter string and candidate filters, or nil when this client has no
-- candidate filters. kind "HELPFUL"/"HARMFUL"; mine adds the PLAYER flag.
function E:AuraSpellSlotSpec(spellID, kind, mine)
	spellID = tonumber(spellID)
	if not spellID or not self:AuraFiltersSupported() then return nil end
	local filter = kind == "HARMFUL" and "HARMFUL" or "HELPFUL"
	if mine then filter = filter .. "|PLAYER" end
	return filter, { includeSpellIDs = { [spellID] = true } }
end

-- The Never show list as a candidate filter for the client's own checks
-- (a highlight or glow that must not light for those debuffs). nil when the
-- list is empty, the block does not use it, or the client has no candidate
-- filters; the client applies it only to auras it allows filtering on.
function E:NeverShowFilter(block)
	if not self:AuraFiltersSupported() then return nil end
	if type(block) == "table" and block.useNeverShow == false then return nil end
	local set = SpellSet(NEVER_SHOW)
	return set and { excludeSpellIDs = set } or nil
end

-- A highlight is a slot whose frame shows only while a matching aura is on
-- the unit; the client decides. which = "dispel" | "boss" | "stealable".
local HIGHLIGHTS = {
	dispel = { filter = "HARMFUL|RAID" },
	boss = { filter = "HARMFUL", candidateFilters = { isBossAura = true } },
	stealable = { filter = "HELPFUL", candidateFilters = { isStealable = true } },
}
function E:AuraHighlightSpec(which)
	local spec = HIGHLIGHTS[which]
	if not spec then return nil end
	if spec.candidateFilters and not self:AuraFiltersSupported() then return nil end
	return spec.filter, { candidateFilters = spec.candidateFilters and CopyTable(spec.candidateFilters) or nil }
end

---------------------------------------------------------------------------
-- Editor rows for a module page.
--   prefix: dotted path of the filter block in the module's settings
--   opts.kind ("HELPFUL"/"HARMFUL"), opts.db (function: module settings),
--   opts.label, opts.hidden, opts.presets (list of preset keys to offer)
-- Custom groups are rare, so their rows carry `cog = true`.
---------------------------------------------------------------------------
local function ListValues(kind)
	local values = { [""] = L["None"] }
	for _, name in ipairs(E:GetAuraFilterLists(kind)) do values[name] = name end
	return values
end

function E:AuraFilterOptions(prefix, opts)
	opts = opts or {}
	local kind = opts.kind == "HARMFUL" and "HARMFUL" or "HELPFUL"
	local p = prefix .. "."
	local function Block()
		local db = opts.db and opts.db()
		local block = db and E.GetPath and E.GetPath(db, prefix)
		return type(block) == "table" and block or nil
	end
	local function ParentHidden() return opts.hidden and opts.hidden() or false end
	local function NotCustom()
		if ParentHidden() then return true end
		local block = Block()
		return block ~= nil and block.preset ~= "custom"
	end
	local function Editing()
		local block = Block()
		local index = block and tonumber(block.edit) or 1
		return math.max(1, math.min(MAX_GROUPS, index))
	end
	local function G(field)
		return function() return ("%sgroups.%d.%s"):format(p, Editing(), field) end
	end
	local function GroupOff()
		if NotCustom() then return true end
		local block = Block()
		local group = block and block.groups and block.groups[Editing()]
		return group ~= nil and not group.enabled
	end
	local function NoCandidates() return GroupOff() or not E:AuraFiltersSupported() end

	local presetValues = { custom = "Custom groups" }
	for key, preset in pairs(PRESETS[kind]) do
		if not opts.presets or tContains(opts.presets, key) then presetValues[key] = preset.title end
	end
	local rows = {}
	if opts.label ~= false then rows[#rows + 1] = { type = "header", label = opts.label or "Aura filter", hidden = opts.hidden } end
	rows[#rows + 1] = { type = "select", key = p .. "preset", label = "Show", values = presetValues, hidden = opts.hidden,
		desc = "Which auras appear. The game does the filtering. Custom groups lets you combine up to four groups with your own spell lists and conditions." }
	rows[#rows + 1] = { type = "toggle", key = p .. "useNeverShow", label = "Use the Never show list", cog = true, hidden = opts.hidden,
		desc = "Spells on the account-wide Never show list (Aura filters page) are left out here too." }
	local groupValues = {}
	for index = 1, MAX_GROUPS do groupValues[index] = L["Group %d"]:format(index) end
	rows[#rows + 1] = { type = "select", key = p .. "edit", label = "Edit group", values = groupValues, cog = true, hidden = NotCustom,
		desc = "Pick which of the four groups the rows below change. Each enabled group adds its auras after the ones before it." }
	rows[#rows + 1] = { type = "toggle", key = G("enabled"), label = "Group on", cog = true, hidden = NotCustom,
		desc = "Use this group. With no group on, every aura of the widget's kind shows." }
	rows[#rows + 1] = { type = "select", key = G("kind"), label = "Shows", cog = true, hidden = GroupOff,
		values = { HELPFUL = "Buffs", HARMFUL = "Debuffs" }, desc = "Buffs or debuffs." }
	rows[#rows + 1] = { type = "toggle", key = G("player"), label = "Only yours", cog = true, hidden = GroupOff,
		desc = "Only auras you, your pet or your vehicle applied." }
	rows[#rows + 1] = { type = "toggle", key = G("notPlayer"), label = "Only other people's", cog = true,
		hidden = function()
			if GroupOff() then return true end
			local block = Block()
			local group = block and block.groups and block.groups[Editing()]
			return group ~= nil and group.player
		end,
		desc = "Only auras that someone else applied." }
	rows[#rows + 1] = { type = "toggle", key = G("raid"), label = "Castable or dispellable by you", cog = true, hidden = GroupOff,
		desc = "Buffs: only ones you can cast. Debuffs: only ones you can dispel." }
	rows[#rows + 1] = { type = "toggle", key = G("cancelable"), label = "Only cancelable", cog = true, hidden = GroupOff,
		desc = "Only buffs you could right-click off." }
	rows[#rows + 1] = { type = "select", key = G("extra"), label = "Game flag", values = E.AURA_FILTER_FLAGS, cog = true, hidden = GroupOff,
		desc = "One of the game's own aura groups, e.g. crowd control or big defensives." }
	rows[#rows + 1] = { type = "select", key = G("allow"), label = "Only spells on", cog = true, hidden = NoCandidates,
		values = function() return ListValues("allow") end,
		desc = "Only auras whose spell is on this allow list. The game applies spell lists to buffs on friends and debuffs on enemies only." }
	rows[#rows + 1] = { type = "select", key = G("block"), label = "Never spells on", cog = true, hidden = NoCandidates,
		values = function() return ListValues("block") end,
		desc = "Leave out auras whose spell is on this block list (same game limits as above)." }
	rows[#rows + 1] = { type = "range", key = G("maxDuration"), label = "Max duration", unit = "s", min = 0, max = 600, step = 5, cog = true, zeroText = "No limit",
		hidden = NoCandidates, desc = "Hide auras that last longer than this in total. Also hides auras without a duration." }
	for _, flag in ipairs(E.AURA_CANDIDATE_FLAGS) do
		rows[#rows + 1] = { type = "select", key = G("flags." .. flag.key), label = flag.label, values = TRISTATE, cog = true,
			hidden = NoCandidates, desc = "%s Don't care: no check.", descFill = flag.desc }
	end
	rows[#rows + 1] = { type = "range", key = G("max"), label = "Icons in this group", min = 0, max = 40, step = 1, cog = true, zeroText = "Share",
		hidden = GroupOff, desc = "At most this many icons from this group. Share: an equal share of the widget's icon limit." }
	rows[#rows + 1] = { type = "select", key = G("sort"), label = "Sort", cog = true, hidden = GroupOff,
		values = { TIME = "Time left", NAME = "Name", INDEX = "Order applied", IMPORTANT = "Important first" },
		desc = "Order of the icons in this group." }
	return rows
end

---------------------------------------------------------------------------
-- General > Aura filters: the account-wide lists.
---------------------------------------------------------------------------
local selected = NEVER_SHOW
local proxy = {}

local function Selected()
	if not E:GetAuraFilterList(selected) then selected = NEVER_SHOW end
	return E:GetAuraFilterList(selected), selected
end

local function SpellIDs(list)
	local ids = {}
	for id in pairs(list.spells) do ids[#ids + 1] = id end
	table.sort(ids)
	return ids
end

local function Notify(message)
	E:Print(message)
end

setmetatable(proxy, {
	__index = function(_, key)
		local list, name = Selected()
		if key == "list" then return name end
		if key == "kind" then return list.kind end
		if key == "spells" then return table.concat(SpellIDs(list), ", ") end
		if key == "add" or key == "rename" or key == "new" or key == "remove" then return "" end
	end,
	__newindex = function(_, key, value)
		local list, name = Selected()
		if key == "list" then
			if E:GetAuraFilterList(value) then selected = value end
		elseif key == "kind" then
			if not list.builtin and (value == "allow" or value == "block") and list.kind ~= value then
				list.kind = value
				Changed()
			end
		elseif key == "spells" then
			-- The whole list as typed: IDs separated by commas or spaces.
			local spells = {}
			for id in tostring(value or ""):gmatch("%d+") do
				id = tonumber(id)
				if id and id > 0 then spells[id] = true end
			end
			list.spells = spells
			Changed()
		elseif key == "add" then
			if value and strtrim(tostring(value)) ~= "" then
				local id = E:AddAuraFilterSpell(name, value)
				if not id then Notify(L["No spell found for %q. Use a spell ID, the exact name or a chat link."]:format(tostring(value))) end
			end
		elseif key == "remove" then
			E:RemoveAuraFilterSpell(name, value)
		elseif key == "rename" then
			if value and strtrim(tostring(value)) ~= "" then
				local new = E:RenameAuraFilterList(name, value)
				if new then selected = new end
			end
		elseif key == "new" then
			if value and strtrim(tostring(value)) ~= "" then
				local new = E:CreateAuraFilterList(value, "block")
				if new then selected = new end
			end
		end
	end,
})

local function ListsPage()
	local function Builtin()
		local list = Selected()
		return list.builtin
	end
	return {
		{ type = "description", label = "Spell lists for EldoUI's aura displays, for all your characters. A block list leaves spells out; an allow list shows only its spells." },
		{ type = "header", label = "List" },
		-- Rows marked noUndo run an action and keep no value of their own:
		-- they stay out of Recent changes.
		{ type = "select", key = "list", label = "Edit list", noUndo = true, values = function()
			local values = {}
			for _, name in ipairs(E:GetAuraFilterLists()) do values[name] = name end
			return values
		end, desc = "The list the rows below edit." },
		{ type = "select", key = "kind", label = "Type", values = { allow = "Allow list (only these)", block = "Block list (never these)" },
			desc = "Allow lists show only their spells; block lists hide them. Built-in lists keep their type.",
			hidden = Builtin },
		{ type = "input", key = "add", label = "Add a spell", noUndo = true, desc = "A spell ID, the exact spell name, or Shift-click a spell link into the box. Press Enter." },
		{ type = "select", key = "remove", label = "Remove a spell", noUndo = true, desc = "Pick a spell to take it off the list.",
			values = function()
				local list = Selected()
				local values = {}
				for _, id in ipairs(SpellIDs(list)) do values[id] = E:SpellLabel(id) end
				return values
			end, hidden = function() return next((Selected()).spells) == nil end },
		{ type = "input", key = "spells", label = "Spell IDs", desc = "Every spell ID on the list. Edit and press Enter to replace the list in one go." },
		{ type = "header", label = "Manage" },
		{ type = "input", key = "new", label = "New list", noUndo = true, desc = "Type a name and press Enter. New lists start as block lists." },
		{ type = "input", key = "rename", label = "Rename this list", noUndo = true, desc = "Type a new name and press Enter. Built-in lists keep their name.", hidden = Builtin },
		{ type = "execute", label = "Delete this list", desc = "Removes the selected list. Displays that used it show without it.", confirm = true,
			hidden = Builtin, func = function()
				local _, name = Selected()
				if E:DeleteAuraFilterList(name) then selected = NEVER_SHOW end
				E:RefreshConfig()
			end },
		{ type = "execute", label = "Export this list", desc = "A text string with the list, to share or keep.", testSafe = true,
			func = function()
				local _, name = Selected()
				E:ShowCopyBox(L["Export aura filter list"], L["Copy this string (Ctrl+C)."], E:ExportAuraFilterList(name) or "")
			end },
		{ type = "execute", label = "Import a list", desc = "Paste a list string. It becomes a new list; nothing is overwritten.",
			func = function()
				E:ShowPasteBox(L["Import aura filter list"], L["Paste a list string (Ctrl+V) and click Save."], function(text)
					local name, err = E:ImportAuraFilterList(text)
					if name then
						selected = name
						Notify(L["Imported aura filter list %s."]:format(name))
					else
						Notify(err)
					end
					E:RefreshConfig()
				end)
			end },
		{ type = "execute", label = "Empty the built-in lists", desc = "Takes every spell off Never show and Watch list. Your own lists stay.", confirm = true,
			func = function() E:ResetAuraFilterLists(); E:RefreshConfig() end },
	}
end

E:RegisterEvent("PLAYER_LOGIN", function()
	Store()
	E:AuraFiltersSupported()
	local page = E:RegisterConfigPage("aurafilters", "Aura filters", ListsPage(), function() return proxy end,
		function() end, 1.4)
	page.desc = L["Spell lists that decide which auras EldoUI shows, for all your characters."]
end, proxy, "pages")
