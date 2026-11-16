-- EldoUI Talent Planner: talent loadout strings.
--
-- A talent loadout string, as calculator sites and other tools make it,
-- read here as a plan. Written from scratch from the loadout string format
-- Blizzard documents for third-party sites:
--
--   Base64 (A-Z a-z 0-9 + /), six bits per letter, lowest bit first; each
--   value is read lowest bit first too.
--   Header: serialization version (8 bits), specialization ID (16 bits),
--   tree hash (128 bits, not read: the nodes are checked against the tree
--   instead).
--   Then one entry per node of the class tree, in the order
--   C_Traits.GetTreeNodes lists them:
--     selected (1 bit); when selected: purchased (1 bit); when purchased:
--     partly ranked (1 bit) and then its ranks (6 bits), choice node (1 bit)
--     and then the chosen entry (2 bits).
--   A purchased node that isn't partly ranked has all its ranks. A node the
--   game grants (selected, not purchased) costs no point and isn't planned.
--
-- The string names the class through its specialization, so it is read for
-- that class whatever the planner shows. It keeps only the final ranks: the
-- plan gets a legal leveling order (lower rows first).
local _, E = ...
local L = E.L
local Key = E.Key
local C = E.Talents.Calc
local M = E.Talents

local LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local VALUE = {}
for index = 1, #LETTERS do VALUE[LETTERS:sub(index, index)] = index - 1 end

local HEADER_BITS = 8 + 16 + 128
local MIN_LETTERS = math.ceil(HEADER_BITS / 6)
local MAX_LETTERS = 4000
-- Versions a loadout string has carried so far start at 1; a higher first
-- byte is some other base64 text, not a loadout.
local MAX_VERSION = 15

-- A reader over the string's bits, lowest bit of each letter first.
local function BitReader(text)
	local values = {}
	for index = 1, #text do
		local value = VALUE[text:sub(index, index)]
		if not value then return nil end
		values[index] = value
	end
	local reader = { total = #values * 6, pos = 0 }
	-- The next width bits as a number, or nil past the end.
	function reader.Read(width)
		if reader.pos + width > reader.total then return nil end
		local value, factor = 0, 1
		for _ = 1, width do
			local letter = values[math.floor(reader.pos / 6) + 1]
			local set = math.floor(letter / 2 ^ (reader.pos % 6)) % 2
			value = value + set * factor
			factor = factor * 2
			reader.pos = reader.pos + 1
		end
		return value
	end
	-- Whether any bit from here to the end is set.
	function reader.AnyLeft()
		while reader.pos < reader.total do
			if reader.Read(1) == 1 then return true end
		end
		return false
	end
	return reader
end

local function ClassOfSpec(specID)
	for class, id in pairs(M.CLASS_SPECS) do
		if id == specID then return class end
	end
	return nil
end

local function CurrentVersion()
	local traits = C_Traits
	if not (traits and type(traits.GetLoadoutSerializationVersion) == "function") then return nil end
	local ok, version = pcall(traits.GetLoadoutSerializationVersion)
	if ok and type(version) == "number" and not E:IsSecret(version) and version > 0 then return version end
	return nil
end

local function TreeNodeIDs(tree)
	local traits = C_Traits
	if not (traits and type(traits.GetTreeNodes) == "function") then return nil end
	local ok, list = pcall(traits.GetTreeNodes, tree.treeID)
	if not ok or type(list) ~= "table" or #list == 0 then return nil end
	return list
end

local function Broken() return L["This talent loadout string is cut short or damaged. Copy it again."] end
local function Outside() return L["This talent loadout names talents WoW: Forever's tree doesn't have. Make the string again on the calculator site."] end

-- The ranks the content part holds, read against the class tree.
local function ReadContent(stream, tree)
	local nodeIDs = TreeNodeIDs(tree)
	if not nodeIDs then return nil, L["The game doesn't list this class's talent tree right now. Try again in a moment."] end
	local ranks, total = {}, 0
	for _, nodeID in ipairs(nodeIDs) do
		local selected = stream.Read(1)
		-- A string that ends between two nodes leaves the rest unselected.
		if selected == nil then break end
		if selected == 1 then
			local purchased = stream.Read(1)
			if purchased == nil then return nil, Broken() end
			if purchased == 1 then
				local partial = stream.Read(1)
				if partial == nil then return nil, Broken() end
				local rank
				if partial == 1 then
					rank = stream.Read(6)
					if rank == nil then return nil, Broken() end
				end
				-- The chosen entry of a choice node: the planner keeps the node.
				local choice = stream.Read(1)
				if choice == nil or (choice == 1 and stream.Read(2) == nil) then return nil, Broken() end
				local node = tree.nodes[nodeID]
				if not node then return nil, Outside() end
				rank = partial == 1 and rank or node.maxRanks
				if rank > node.maxRanks then
					return nil, E:Plural(rank, "The talent loadout asks for %d rank of %s, more than it has. Make the string again on the calculator site.",
						"The talent loadout asks for %d ranks of %s, more than it has. Make the string again on the calculator site."):format(rank, node.name or "?")
				end
				if rank > 0 then
					ranks[nodeID] = rank
					total = total + rank
				end
			end
		end
	end
	if stream.AnyLeft() then return nil, Outside() end
	return ranks, total
end

C.Register({
	key = "loadout", site = Key("Talent loadout string"), version = 1,
	heading = Key("Talent loadout string"),
	note = Key("A talent loadout keeps only the final ranks: the plan takes lower rows first. Reorder it in the planner."),
	find = function(text)
		if #text < MIN_LETTERS or #text > MAX_LETTERS or not text:match("^[%w%+/]+$") then return nil end
		local stream = BitReader(text)
		if not stream then return nil end
		local version, specID = stream.Read(8), stream.Read(16)
		if not version or version < 1 or version > MAX_VERSION or not specID or specID == 0 then return nil end
		stream.Read(128)
		local current = CurrentVersion()
		if current and version ~= current then
			return { error = L["This talent loadout string was made for another version of the game. Make it again on the calculator site, then paste the new string."] }
		end
		local class = ClassOfSpec(specID)
		if not class then
			return { error = L["This talent loadout is for a class or specialization WoW: Forever doesn't have."] }
		end
		return {
			class = class, trees = {},
			read = function(tree) return ReadContent(stream, tree) end,
		}
	end,
})
