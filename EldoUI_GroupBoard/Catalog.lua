-- EldoUI Group Board: the places a group post can name.
--
-- One entry per dungeon or raid the board knows: its English and German
-- name, the level range and group size, the instance map, and the words
-- players write for it in chat (full names and the usual short forms, in
-- English and German). Wings share a parent (Scarlet Monastery, Dire Maul,
-- Blackrock Spire, Stratholme), so "SM" alone finds the monastery and
-- "SM Lib" its library.
--
--   strong words find the place on their own ("rfc", "todesminen");
--   weak words ("east", "lower", "ud") count only next to their parent
--   ("DM" ... "BRS lower"), so "west" in "LFG west plaguelands" stays a word;
--   solo words ("lib", "arm", "gy") also count alone, but only when no
--   strong word named another place: "arm" in a line about a Deadmines run
--   stays a word.
--
-- At login the client's own dungeon finder list (GetLFDChoiceOrder and
-- GetLFGDungeonInfo) adds what this table can't know: the name in the
-- client's language, the level range WoW: Forever uses, and dungeons this
-- file doesn't list. Levels of the client win over the ones written here.
--
-- Words are written folded (E:FoldText: lower case, no accents or
-- apostrophes, "ü" -> "u"), as the parser folds the chat line.
-- Written from scratch for this fork of EldoUI.
local _, ns = ...
local E = EldoUI
if not (E and E.apiVersion and E.apiVersion >= 1) then return end

local Catalog = {}
ns.Catalog = Catalog

-- key, English name, German name, kind, min, max, size, map, parent,
-- strong words, weak words, solo words.
local PLACES = {
	-- Dungeons
	{ "ragefire", "Ragefire Chasm", "Der Flammenschlund", "dungeon", 13, 18, 5, 389, nil,
		{ "rfc", "ragefire", "ragefire chasm", "flammenschlund" } },
	{ "wailing", "Wailing Caverns", "Die Höhlen des Wehklagens", "dungeon", 17, 24, 5, 43, nil,
		{ "wc", "wailing", "wailing caverns", "hdw", "hohlen des wehklagens", "wehklagen" } },
	{ "deadmines", "The Deadmines", "Die Todesminen", "dungeon", 17, 26, 5, 36, nil,
		{ "dm", "vc", "deadmines", "deadmine", "todesminen", "todesmine" } },
	{ "shadowfang", "Shadowfang Keep", "Burg Schattenfang", "dungeon", 22, 30, 5, 33, nil,
		{ "sfk", "shadowfang", "shadowfang keep", "bsf", "schattenfang", "burg schattenfang" } },
	{ "blackfathom", "Blackfathom Deeps", "Die Tiefschwarze Grotte", "dungeon", 24, 32, 5, 48, nil,
		{ "bfd", "blackfathom", "blackfathom deeps", "tsg", "tiefschwarze grotte" } },
	{ "stockade", "The Stockade", "Das Verlies", "dungeon", 24, 32, 5, 34, nil,
		{ "stocks", "stockade", "stockades", "verlies" } },
	{ "sm", "Scarlet Monastery", "Das Scharlachrote Kloster", "dungeon", 26, 45, 5, 189, nil,
		{ "sm", "scarlet monastery", "scarlet", "kloster", "scharlachrote kloster", "scharlachroten kloster" } },
	{ "sm_gy", "Scarlet Monastery: Graveyard", "Kloster: Friedhof", "dungeon", 26, 36, 5, 189, "sm",
		{ "smgy", "graveyard", "friedhof" }, { "fh" }, { "gy" } },
	{ "sm_lib", "Scarlet Monastery: Library", "Kloster: Bibliothek", "dungeon", 29, 39, 5, 189, "sm",
		{ "smlib", "library", "bibliothek" }, { "bibo" }, { "lib", "bib" } },
	{ "sm_arm", "Scarlet Monastery: Armory", "Kloster: Waffenkammer", "dungeon", 32, 42, 5, 189, "sm",
		{ "smarm", "armory", "armoury", "waffenkammer" }, { "wk" }, { "arm" } },
	{ "sm_cath", "Scarlet Monastery: Cathedral", "Kloster: Kathedrale", "dungeon", 35, 45, 5, 189, "sm",
		{ "smcath", "cathedral", "kathedrale" }, nil, { "cath", "kath" } },
	{ "kraul", "Razorfen Kraul", "Der Kral der Klingenhauer", "dungeon", 29, 38, 5, 47, nil,
		{ "rfk", "kraul", "razorfen kraul", "kral", "kral der klingenhauer", "kdk" } },
	{ "gnomeregan", "Gnomeregan", "Gnomeregan", "dungeon", 29, 38, 5, 90, nil,
		{ "gnomer", "gnomeregan", "gnomeragan" } },
	{ "downs", "Razorfen Downs", "Die Hügel der Klingenhauer", "dungeon", 37, 46, 5, 129, nil,
		{ "rfd", "razorfen downs", "downs", "hdk", "hugel der klingenhauer" } },
	{ "uldaman", "Uldaman", "Uldaman", "dungeon", 41, 51, 5, 70, nil,
		{ "ulda", "uld", "uldaman" } },
	{ "zulfarrak", "Zul'Farrak", "Zul'Farrak", "dungeon", 44, 54, 5, 209, nil,
		{ "zf", "zulfarrak", "zul farrak" } },
	{ "maraudon", "Maraudon", "Maraudon", "dungeon", 46, 55, 5, 349, nil,
		{ "mara", "maraudon" } },
	{ "sunken", "Sunken Temple", "Der Tempel von Atal'Hakkar", "dungeon", 50, 60, 5, 109, nil,
		{ "st", "sunken temple", "sunken", "atalhakkar", "temple of atalhakkar", "tempel von atalhakkar", "tempel" } },
	{ "brd", "Blackrock Depths", "Die Schwarzfelstiefen", "dungeon", 52, 60, 5, 230, nil,
		{ "brd", "brt", "blackrock depths", "schwarzfelstiefen", "schwarzfels tiefen" } },
	{ "brs", "Blackrock Spire", "Die Schwarzfelsspitze", "dungeon", 55, 60, 10, 229, nil,
		{ "brs", "blackrock spire", "schwarzfelsspitze" } },
	{ "lbrs", "Lower Blackrock Spire", "Untere Schwarzfelsspitze", "dungeon", 55, 60, 5, 229, "brs",
		{ "lbrs", "lower blackrock spire", "lower brs", "untere schwarzfelsspitze", "untere brs" }, { "lower", "untere" } },
	{ "ubrs", "Upper Blackrock Spire", "Obere Schwarzfelsspitze", "dungeon", 55, 60, 10, 229, "brs",
		{ "ubrs", "upper blackrock spire", "upper brs", "obere schwarzfelsspitze", "obere brs" }, { "upper", "obere" } },
	{ "diremaul", "Dire Maul", "Düsterbruch", "dungeon", 55, 60, 5, 429, nil,
		{ "dire maul", "diremaul", "dusterbruch", "db" } },
	{ "dm_east", "Dire Maul: East", "Düsterbruch: Ost", "dungeon", 55, 60, 5, 429, "diremaul",
		{ "dme", "dm east", "dm ost", "dire maul east", "dbo", "db ost", "dusterbruch ost" }, { "east", "ost" } },
	{ "dm_west", "Dire Maul: West", "Düsterbruch: West", "dungeon", 55, 60, 5, 429, "diremaul",
		{ "dmw", "dm west", "dire maul west", "dbw", "db west", "dusterbruch west" }, { "west" } },
	{ "dm_north", "Dire Maul: North", "Düsterbruch: Nord", "dungeon", 55, 60, 5, 429, "diremaul",
		{ "dmn", "dm north", "dm nord", "dm tribute", "dm trib", "tribute", "trib", "dire maul north",
			"dbn", "db nord", "dusterbruch nord" }, { "north", "nord" } },
	{ "strat", "Stratholme", "Stratholme", "dungeon", 58, 60, 5, 329, nil,
		{ "strat", "strath", "stratholme" } },
	{ "strat_live", "Stratholme: Main Gate", "Stratholme (lebend)", "dungeon", 58, 60, 5, 329, "strat",
		{ "stratlive", "strat live", "live strat", "living side", "live side", "main gate", "strat lebend" }, { "live", "living", "lebend" } },
	{ "strat_ud", "Stratholme: Service Entrance", "Stratholme (untot)", "dungeon", 58, 60, 5, 329, "strat",
		{ "stratud", "strat ud", "ud strat", "undead strat", "strat undead", "dead side", "service entrance",
			"baron run", "strat untot" }, { "ud", "dead", "baron", "untot" } },
	{ "scholomance", "Scholomance", "Scholomance", "dungeon", 58, 60, 5, 289, nil,
		{ "scholo", "scholomance" } },
	-- Raids
	{ "onyxia", "Onyxia's Lair", "Onyxias Hort", "raid", 60, 60, 40, 249, nil,
		{ "ony", "onyxia", "onyxias lair", "onyxia lair", "onyxias hort" } },
	{ "mc", "Molten Core", "Der Geschmolzene Kern", "raid", 60, 60, 40, 409, nil,
		{ "mc", "molten core", "geschmolzener kern", "geschmolzenen kern" } },
	{ "zg", "Zul'Gurub", "Zul'Gurub", "raid", 60, 60, 20, 309, nil,
		{ "zg", "zulgurub", "zul gurub" } },
	{ "bwl", "Blackwing Lair", "Pechschwingenhort", "raid", 60, 60, 40, 469, nil,
		{ "bwl", "blackwing lair", "blackwing", "pechschwingenhort" } },
	{ "aq20", "Ruins of Ahn'Qiraj", "Ruinen von Ahn'Qiraj", "raid", 60, 60, 20, 509, nil,
		{ "aq20", "aq 20", "raq", "ruins of ahnqiraj", "ruinen von ahnqiraj" } },
	{ "aq40", "Temple of Ahn'Qiraj", "Tempel von Ahn'Qiraj", "raid", 60, 60, 40, 531, nil,
		{ "aq40", "aq 40", "aq", "taq", "temple of ahnqiraj", "tempel von ahnqiraj" } },
	{ "naxx", "Naxxramas", "Naxxramas", "raid", 60, 60, 40, 533, nil,
		{ "naxx", "naxxramas", "naxramas" } },
	-- WoW: Forever's own dungeons (E.ForeverDungeons). No German names
	-- are known here: the client's dungeon finder list brings them at
	-- login. Levels and sizes come from there as well.
	{ "f_dalaran", "City of Dalaran", nil, "dungeon", nil, nil, 5, 2959, nil,
		{ "city of dalaran", "dalaran" } },
	{ "f_drowned", "The Drowned City", nil, "dungeon", nil, nil, 5, 2970, nil,
		{ "drowned city", "drowned" } },
	{ "f_blackmaw", "Blackmaw Hold", nil, "dungeon", nil, nil, 5, 2974, nil,
		{ "blackmaw hold", "blackmaw" } },
	{ "f_alcaz", "Alcaz Prison", nil, "dungeon", nil, nil, 5, 2994, nil,
		{ "alcaz prison", "alcaz" } },
	{ "f_excavation", "Excavation Site: Wetlands", nil, "dungeon", nil, nil, 5, 2998, nil,
		{ "excavation site wetlands", "excavation site", "excavation" } },
	{ "f_lordaeron", "Ruins of Lordaeron", nil, "dungeon", nil, nil, 5, 2999, nil,
		{ "ruins of lordaeron" } },
	{ "f_shaper", "The Shaper's Terrace", nil, "dungeon", nil, nil, 5, 3001, nil,
		{ "shapers terrace", "shaper terrace", "shapers" }, nil, { "shaper" } },
	{ "f_kroldok", "Krol'dok Stronghold", nil, "dungeon", nil, nil, 5, 3039, nil,
		{ "kroldok stronghold", "kroldok" } },
	{ "f_thanes", "The Hall of Thanes", nil, "dungeon", nil, nil, 5, 3065, nil,
		{ "hall of thanes", "thanes" } },
}

Catalog.entries = {}  -- key -> entry
Catalog.order = {}    -- keys in table order (the order lists and menus show)

local function Fold(text)
	if E.FoldText then return E:FoldText(text) end
	return (tostring(text or ""):lower():gsub("['`]", ""):gsub("[%p%s]+", " "):gsub("^ +", ""):gsub(" +$", ""))
end
Catalog.Fold = Fold

local function AddEntry(entry)
	if Catalog.entries[entry.key] then return Catalog.entries[entry.key] end
	Catalog.entries[entry.key] = entry
	Catalog.order[#Catalog.order + 1] = entry.key
	entry.index = #Catalog.order
	return entry
end

for _, place in ipairs(PLACES) do
	local entry = {
		key = place[1], en = place[2], de = place[3], kind = place[4],
		min = place[5], max = place[6], size = place[7], map = place[8], parent = place[9],
		strong = {}, weak = {}, solo = {}, children = {},
		guess = place[5] == nil, -- no levels known here: size and kind come from the client
	}
	for _, word in ipairs(place[10] or {}) do entry.strong[#entry.strong + 1] = word end
	for _, word in ipairs(place[11] or {}) do entry.weak[#entry.weak + 1] = word end
	for _, word in ipairs(place[12] or {}) do entry.solo[#entry.solo + 1] = word end
	AddEntry(entry)
end
for _, key in ipairs(Catalog.order) do
	local entry = Catalog.entries[key]
	local parent = entry.parent and Catalog.entries[entry.parent]
	if parent then parent.children[#parent.children + 1] = key end
end

---------------------------------------------------------------------------
-- The client's dungeon finder list
---------------------------------------------------------------------------
local Secret = E.Secret or function() return false end

local function Number(value)
	if Secret(value) then return nil end
	return tonumber(value)
end

local function HasWord(folded, word)
	return (" " .. folded .. " "):find(" " .. word .. " ", 1, true) ~= nil
end

-- The catalog entry a dungeon finder entry stands for, and whether its map
-- is one this table knows. A map with wings (Scarlet Monastery, Dire Maul,
-- Blackrock Spire, Stratholme) goes to the wing whose name or words the
-- client's name has ("Scarlet Monastery - Library" -> the library, the
-- longest word wins); a wing the name doesn't tell gets nothing, never a
-- second place for the same dungeon.
local function EntryForClient(map, folded)
	local family = {}
	for _, key in ipairs(Catalog.order) do
		local entry = Catalog.entries[key]
		if entry.map == map and not entry.lfgOnly then family[#family + 1] = entry end
	end
	if #family == 0 then return nil, false end
	if #family == 1 then return family[1], true end
	local best, bestLength
	for _, entry in ipairs(family) do
		if entry.parent then
			if Fold(entry.en) == folded or (entry.de and Fold(entry.de) == folded) then return entry, true end
			for _, list in ipairs({ entry.strong, entry.weak, entry.solo }) do
				for _, word in ipairs(list) do
					if HasWord(folded, word) and (not bestLength or #word > bestLength) then best, bestLength = entry, #word end
				end
			end
		end
	end
	return best, true
end

local function AddWord(entry, word)
	if type(word) ~= "string" or word == "" then return end
	for _, known in ipairs(entry.strong) do
		if known == word then return end
	end
	entry.strong[#entry.strong + 1] = word
end

-- Reads the dungeon finder list once (again after LFG_UPDATE_RANDOM_INFO).
-- Returns true when the client gave a list.
function Catalog:ReadClient()
	local order = rawget(_G, "GetLFDChoiceOrder")
	local info = rawget(_G, "GetLFGDungeonInfo")
	if type(order) ~= "function" or type(info) ~= "function" then return false end
	local ok, ids = pcall(order)
	if not ok or type(ids) ~= "table" then return false end
	local any, seen = false, {}
	for _, id in ipairs(ids) do
		-- name, typeID, subtypeID, minLevel, maxLevel, ..., maxPlayers (13th
		-- value), ..., mapID (22nd value); pcall adds one in front.
		local r = { pcall(info, id) }
		local name = r[2]
		if r[1] and type(name) == "string" and not Secret(name) and name ~= "" then
			any = true
			local min, max, size, map = Number(r[5]), Number(r[6]), Number(r[14]), Number(r[23])
			local folded = Fold(name)
			local entry, known = nil, false
			if map then entry, known = EntryForClient(map, folded) end
			if not entry and not known then
				entry = AddEntry({ key = "lfg:" .. tostring(id), en = name, kind = (size and size > 5) and "raid" or "dungeon",
					size = size, map = map, strong = {}, weak = {}, solo = {}, children = {}, lfgOnly = true })
			end
			if entry then
				entry.client = entry.client or name
				-- The first finder entry of a place sets its levels; more
				-- entries (another level band) widen them.
				if not seen[entry] then
					seen[entry] = true
					if min and min > 0 then entry.min = min end
					if max and max > 0 then entry.max = max end
				else
					if min and min > 0 and (not entry.min or min < entry.min) then entry.min = min end
					if max and max > 0 and (not entry.max or max > entry.max) then entry.max = max end
				end
				-- Group size and kind only where this table had to guess
				-- them (Forever's own dungeons, entries from the list):
				-- UBRS stays a dungeon of ten.
				if size and size > 0 and (entry.lfgOnly or entry.guess) then
					entry.size = size
					entry.kind = size > 5 and "raid" or "dungeon"
				end
				AddWord(entry, folded)
				-- "The Drowned City" is also written without the article.
				local bare = folded:gsub("^the ", ""):gsub("^die ", ""):gsub("^der ", ""):gsub("^das ", "")
				if bare ~= folded and #bare >= 5 then AddWord(entry, bare) end
			end
		end
	end
	self.version = (self.version or 0) + 1
	return any
end

---------------------------------------------------------------------------
-- Reading entries
---------------------------------------------------------------------------
function Catalog:Get(key)
	return self.entries[key]
end

-- The name in the language EldoUI shows: German where this table has it,
-- else the client's own name (in the client's language), else English.
function Catalog:Name(key)
	local entry = self.entries[key]
	if not entry then return tostring(key) end
	local language = E.GetLanguage and E:GetLanguage() or "enUS"
	if language == "deDE" and entry.de then return entry.de end
	if language == "enUS" or language == "enGB" then return entry.en end
	return entry.client or entry.en
end

-- The top of an entry's family: the monastery for its library.
function Catalog:Root(key)
	local entry = self.entries[key]
	while entry and entry.parent and self.entries[entry.parent] do entry = self.entries[entry.parent] end
	return entry
end

-- Level range of an entry (a parent spans its wings), or nil.
function Catalog:Levels(key)
	local entry = self.entries[key]
	if not entry then return nil end
	local min, max = entry.min, entry.max
	for _, child in ipairs(entry.children) do
		local c = self.entries[child]
		if c and c.min and (not min or c.min < min) then min = c.min end
		if c and c.max and (not max or c.max > max) then max = c.max end
	end
	return min, max
end

-- True when a character of `level` can go: from three levels under the
-- range to five over it, as players usually take groups.
function Catalog:Fits(key, level)
	level = tonumber(level)
	local min, max = self:Levels(key)
	if not (level and min) then return true end
	return level >= min - 3 and level <= (max or min) + 5
end

-- Every word of every entry as a list of { word, key, parts, weak, solo },
-- longest phrases first (the parser takes the longest match).
function Catalog:Words()
	if self.words and self.wordsVersion == self.version then return self.words end
	local list = {}
	for _, key in ipairs(self.order) do
		local entry = self.entries[key]
		for _, word in ipairs(entry.strong) do list[#list + 1] = { word = word, key = key } end
		for _, word in ipairs(entry.weak) do list[#list + 1] = { word = word, key = key, weak = true } end
		for _, word in ipairs(entry.solo) do list[#list + 1] = { word = word, key = key, solo = true } end
	end
	for _, item in ipairs(list) do
		local parts = {}
		for part in item.word:gmatch("%S+") do parts[#parts + 1] = part end
		item.parts = parts
	end
	-- Equal words: the entry this table lists first (before entries from
	-- the client's list) wins.
	table.sort(list, function(a, b)
		if #a.parts ~= #b.parts then return #a.parts > #b.parts end
		if #a.word ~= #b.word then return #a.word > #b.word end
		if a.word ~= b.word then return a.word < b.word end
		return self.entries[a.key].index < self.entries[b.key].index
	end)
	self.words, self.wordsVersion = list, self.version
	return list
end
