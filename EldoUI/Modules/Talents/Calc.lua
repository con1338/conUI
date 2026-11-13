-- EldoUI Talent Planner: talent calculator links as plans.
--
-- Paste a talent calculator link (or its talent string) into the
-- planner's import box or /eui talents import, see what it holds, and save
-- it as a plan. Nothing is learned.
--
-- Each site is one small reader in a registry, one file per site in
-- Modules\Talents\Calc, so a new site or a new link version is one more
-- file (listed in the TOC after this one):
--
--   C.Register({ key, site, version, find = function(text) -> found or nil })
--     found = { class = "MAGE" or nil, trees = { "2305", "", "05" },
--               game = "classic" | "forever" | nil, ordered = true|nil }
--     found.error = text for a link the reader knows but can't use
--     found.read = function(tree) -> ranks ([nodeID] = rank), total, for a
--       string that names the talents by node instead of by digit (trees
--       is then left empty), or nil and why
--   Optional reader fields: heading (the preview's title instead of
--   "<site> talent link") and note (instead of the line on the order).
--   A reader with the key of one already listed takes its place, so a site
--   that only has a "can't read yet" entry gets a real reader the same way.
--   C.Pending(key, site, pattern) lists a site whose links can't be read
--   yet: its links get a message naming the site.
--
-- How the digits map to talents: one digit per talent of a tree (its rank),
-- in the tree's own reading order, row by row from the top and left to
-- right in a row, as the planner reads the tree from the game. Trailing
-- zeros may be left out, and so may trailing trees. C.ORDER can hold a
-- different talent order per site and class, once a site's order for the
-- WoW: Forever trees is known; it holds only that order, never a build.
--
-- Most calculators keep only the final ranks, not the order they were
-- bought in, so the plan gets a legal leveling order (lower rows first)
-- that you can change in the planner.
local _, E = ...
local L = E.L
local P = E.TalentPlan
local M = E.Talents

local C = {}
M.Calc = C

C.readers = {}

-- [site key][class token][tree index] = { talent position in the planner's
-- reading order, ... } for each digit of the link, when a site orders the
-- talents differently. A reader can carry the same table as its own
-- "order" field. Empty: the reading order is used.
C.ORDER = {}

-- Class names in links, in English as the sites write them.
local SLUGS = {
	warrior = "WARRIOR", paladin = "PALADIN", hunter = "HUNTER", rogue = "ROGUE", priest = "PRIEST",
	shaman = "SHAMAN", mage = "MAGE", warlock = "WARLOCK", druid = "DRUID",
}
C.SLUGS = SLUGS

function C.Register(reader)
	assert(type(reader) == "table" and type(reader.key) == "string" and type(reader.find) == "function", "Calc.Register: key and find")
	-- EldoUI's own texts are given in English and read in the language shown.
	E:TranslateFields({ reader }, "site", "heading", "note")
	for index, entry in ipairs(C.readers) do
		if entry.key == reader.key then
			C.readers[index] = reader
			return reader
		end
	end
	C.readers[#C.readers + 1] = reader
	return reader
end

-- A site whose share links keep the build in a form that isn't published:
-- its links are recognized and get a message naming the site.
function C.Pending(key, site, pattern)
	return C.Register({
		key = key, site = site, pending = true,
		find = function(text)
			if not text:lower():find(pattern) then return nil end
			return { error = L["EldoUI can't read %s talent links yet. If the site offers a talent string or a talent loadout string of the build, paste that instead."]:format(site) }
		end,
	})
end

local function SplitTrees(text)
	local trees = {}
	for part in (text .. "-"):gmatch("([^%-]*)%-") do trees[#trees + 1] = part end
	-- "a-b-" ends with an empty tree; drop trailing empties.
	while #trees > 0 and trees[#trees] == "" do trees[#trees] = nil end
	return trees
end
C.SplitTrees = SplitTrees

-- The sites EldoUI reads, for the message on a link it doesn't know.
function C.SiteNames()
	local names = {}
	for _, reader in ipairs(C.readers) do
		if not reader.pending and reader.key ~= "digits" and reader.key ~= "loadout" then names[#names + 1] = reader.site end
	end
	return names
end

-- What a text that no reader knows gets as an answer.
function C.UnknownText()
	return L["EldoUI doesn't recognize this talent link. It reads talent calculator links from %s, talent strings like 0505-3200-5 and talent loadout strings."]:format(table.concat(C.SiteNames(), ", "))
end

-- Whether a pasted text is a talent calculator link or string.
function C.Recognize(text)
	text = strtrim(tostring(text or ""))
	if text == "" or text:sub(1, 1) == "!" then return false end
	local lower = text:lower()
	if lower:find("talent") and lower:find("^https?://") then return true end
	for _, reader in ipairs(C.readers) do
		local ok, found = pcall(reader.find, text)
		if ok and found then return true end
	end
	return false
end

-- Read a link against a class's tree. Returns a result or nil and why:
--   { site, class, order, ranks, total, dropped, spent = { [groupID] = n },
--     notes = { text, ... } }
-- class: the class the link is read for when it names none.
function C.Read(text, class)
	text = strtrim(tostring(text or ""))
	local found, reader
	for _, entry in ipairs(C.readers) do
		local ok, result = pcall(entry.find, text)
		if ok and result then found, reader = result, entry break end
	end
	if not found then return nil, C.UnknownText() end
	if found.error then return nil, found.error end
	if found.slug and not found.class then
		return nil, L["This link is for a class WoW: Forever doesn't have."]
	end
	class = found.class or class or M:ClassToken()
	local tree, why = M:ClassTree(class)
	if not tree then
		if why == "blizzard" then return nil, L["Close Blizzard's talent window, then paste the link again."] end
		return nil, L["The game doesn't show the %s tree to this character, so the link can't be read here. Paste it on a %s."]:format(M:ClassName(class), M:ClassName(class))
	end
	if #found.trees > #tree.groups then
		return nil, E:Plural(#found.trees, "The link has %d talent tree, more than WoW: Forever's %s has.", "The link has %d talent trees, more than WoW: Forever's %s has."):format(#found.trees, M:ClassName(class))
	end
	local ranks, total
	if found.read then
		ranks, total = found.read(tree)
		if not ranks then return nil, total end
	else
		ranks, total = {}, 0
		local custom = (reader.order or C.ORDER[reader.key] or {})[class]
		for index, digits in ipairs(found.trees) do
			local group = tree.groups[index]
			local nodes = {}
			for _, nodeID in ipairs(tree.order) do
				if tree.nodes[nodeID].group == group.groupID then nodes[#nodes + 1] = nodeID end
			end
			local map = custom and custom[index]
			if #digits > #nodes then
				return nil, E:Plural(#digits, "The link lists %d talent in %s, more than WoW: Forever's tree has. It was made for other trees.",
					"The link lists %d talents in %s, more than WoW: Forever's tree has. It was made for other trees."):format(#digits, group.name)
			end
			for position = 1, #digits do
				local rank = tonumber(digits:sub(position, position)) or 0
				if rank > 0 then
					local nodeID = nodes[map and map[position] or position]
					local node = nodeID and tree.nodes[nodeID]
					if not node then
						return nil, L["The link names a talent %s doesn't have. It was made for other trees."]:format(group.name)
					end
					if rank > node.maxRanks then
						return nil, E:Plural(rank, "The link asks for %d rank of %s, more than it has. It was made for other trees.",
							"The link asks for %d ranks of %s, more than it has. It was made for other trees."):format(rank, node.name)
					end
					ranks[nodeID] = rank
					total = total + rank
				end
			end
		end
	end
	if total == 0 then return nil, L["The link has no talent points in it."] end
	local order = P.FromRanks(tree, ranks, tree.maxPoints)
	local state = P.Count(tree, order)
	local result = {
		site = reader.site, heading = reader.heading, class = class, other = M:IsOtherClass(class), order = order, ranks = ranks,
		total = total, dropped = total - #order, spent = state.spent, tree = tree, notes = {},
	}
	if total > tree.maxPoints then
		result.notes[#result.notes + 1] = E:Plural(total, "The link has %d point, more than a plan holds. The rest are left out.",
			"The link has %d points, more than a plan holds. The rest are left out."):format(total)
	elseif result.dropped > 0 then
		result.notes[#result.notes + 1] = E:Plural(result.dropped, "%d rank doesn't fit the tree's rules and is left out. The link may have been made for other trees.",
			"%d ranks don't fit the tree's rules and are left out. The link may have been made for other trees."):format(result.dropped)
	end
	if found.game == "classic" then
		result.notes[#result.notes + 1] = L["Made for the Classic trees. WoW: Forever's trees have more talents, so check every tree before you follow it."]
	end
	result.notes[#result.notes + 1] = reader.note or found.ordered and L["The link's buying order isn't read: the plan takes lower rows first. Reorder it in the planner."]
		or L["The link keeps only the final ranks: the plan takes lower rows first. Reorder it in the planner."]
	return result
end

local function TreeLine(result)
	local parts = {}
	for _, group in ipairs(result.tree.groups) do
		parts[#parts + 1] = ("%s %d"):format(group.name, result.spent[group.groupID] or 0)
	end
	return table.concat(parts, " / ")
end

-- The lines the preview shows.
function C.Describe(result)
	local lines = {
		E:Highlight(result.heading or L["%s talent link"]:format(result.site)),
		L["Class: %s"]:format(M:ClassName(result.class)),
		E:Plural(#result.order, "%d point: %s", "%d points: %s"):format(#result.order, TreeLine(result)),
	}
	for _, note in ipairs(result.notes) do lines[#lines + 1] = note end
	if result.other then
		lines[#lines + 1] = L["Not your class: it is saved for later with your %s plans, read-only on this character."]:format(M:ClassName(result.class))
	end
	lines[#lines + 1] = L["It is saved as a plan. Nothing is learned."]
	return lines
end

-- Save a read link as a new plan (own class: the talent group you plan;
-- another class: the account's plans for it). notify(text, warn): where
-- the answer goes (a window's notice; nil: chat).
function C.Save(result, name, notify)
	notify = notify or M.ChatNotice
	local group = result.other and result.class or M:ViewGroup()
	if M:IsOtherClass(group) and group ~= result.class then group = nil end
	name = name or L["%s %s build"]:format(result.site, M:ClassName(result.class))
	local plan, why = M:CreatePlan(name, result.order, group)
	if not plan then
		notify(L["Import failed: %s"]:format(why), true)
		return nil
	end
	M:SavedNotice(plan, result.other and result.class or nil, "", notify)
	return plan
end

-- Read, preview, and save on the player's click.
function C.Import(text, class, notify)
	local result, err = C.Read(text, class)
	if not result then
		if notify then
			notify(L["Import failed: %s"]:format(err), true)
		else
			E:Print(L["Import failed: %s"]:format(err))
			if M.SetWindowStatus then M:SetWindowStatus(err, true) end
		end
		return nil, err
	end
	E:ShowConfirm({ key = "ELDOUI_TALENTS_CALC", title = L["Import"], text = table.concat(C.Describe(result), "\n"),
		accept = result.other and L["Save for later"] or L["Save plan"], data = result,
		onAccept = function(data) C.Save(data, nil, notify) end })
	return result
end

-- The class a bare string is read for: the class shown in the planner.
local function PlannedClass()
	local group = M:ViewGroup()
	return M:IsOtherClass(group) and group or M:ClassToken()
end

-- One paste box for both: talent links here, EldoUI strings to the share
-- kit. notify(text, warn): a click in a window (Import build, the Plans
-- tab) answers in that window; without it (the slash command) in chat.
function M:ImportText(text, notify)
	if C.Recognize(text) then return C.Import(text, PlannedClass(), notify) end
	if not notify then return E:ImportString(text) end
	text = strtrim(tostring(text or ""))
	local kind = E:ShareKindFor(text)
	if kind == "talents" then return M:PreviewPlanString(text, notify) end
	-- Another EldoUI string (a profile, a layout): the import it belongs to.
	if kind or E:IsShareString(text) then return E:ImportString(text) end
	notify(L["Import failed: %s"]:format(C.UnknownText()), true)
	return nil
end
