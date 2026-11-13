-- The WoW voice of the journal story.
-- Static English data, our own words, and the rules that bind
-- every flavor word to a fact:
--   * race and class words are bound to the character (me), Bard only, and
--     the reference nouns ("the dwarf", "the priest") to the same;
--   * faction words (the side, gryphon or wind rider, ship or zeppelin) are
--     bound to me.faction and to the continent or port of the cited fact;
--   * zone epithets and scenes (Data/StoryWorld.lua) are bound to a cited
--     fact in that place with enough time there (Story/Honesty.lua H5);
--   * the lexicon (grim, hard-won, prized ...) is bound to a fact flag.
-- No Blizzard quest, lore or item text is used; names are the game's own.
local _, E = ...

E.Story = E.Story or {}
local V = {}
E.Story.Voice = V

-- Race: reference noun, Bard adjective, home capital. Keys are the game's
-- English race names; RaceRow also accepts the client's file names.
V.race = {
	Human = { noun = "human", adj = "steadfast", capital = "Stormwind" },
	Dwarf = { noun = "dwarf", adj = "stout", capital = "Ironforge" },
	Gnome = { noun = "gnome", adj = "clever", capital = "Ironforge" },
	["Night Elf"] = { noun = "night elf", adj = "keen-eyed", capital = "Darnassus" },
	Orc = { noun = "orc", adj = "hardy", capital = "Orgrimmar" },
	Troll = { noun = "troll", adj = "island-born", capital = "Orgrimmar" },
	Tauren = { noun = "tauren", adj = "plains-born", capital = "Thunder Bluff" },
	Undead = { noun = "undead", adj = "grave-risen", capital = "the Undercity", noRef = true },
}
local RACE_ALIAS = { Scourge = "Undead", NightElf = "Night Elf", ["Night elf"] = "Night Elf", Forsaken = "Undead" }

V.class = {
	Warrior = { noun = "warrior" }, Paladin = { noun = "paladin" }, Hunter = { noun = "hunter" },
	Rogue = { noun = "rogue" }, Priest = { noun = "priest" }, Shaman = { noun = "shaman" },
	Mage = { noun = "mage" }, Warlock = { noun = "warlock" }, Druid = { noun = "druid" },
}

V.faction = {
	Alliance = { side = "the Alliance", other = "the Horde", flight = { ["Eastern Kingdoms"] = "gryphon", Kalimdor = "hippogryph" }, sea = "ship" },
	Horde = { side = "the Horde", other = "the Alliance", flight = { ["Eastern Kingdoms"] = "wind rider", Kalimdor = "wind rider" }, sea = "zeppelin",
		batZones = { ["Tirisfal Glades"] = true, ["Undercity"] = true } },
}

-- Words only one faction may use (VO-2).
V.factionWords = {
	Alliance = { "gryphon", "hippogryph", "for the Alliance" },
	Horde = { "wind rider", "zeppelin", "bat", "for the Horde" },
}

-- The bound lexicon. A word may appear in Bard text only
-- when one of the sentence's cited facts carries the flag. Chronicle and
-- Ledger use none of these words (H4).
V.lexicon = {
	{ flag = "slow", words = { "hard-won", "at last" } },
	{ flag = "fast", words = { "swift", "quick" } },
	{ flag = "deathstreak", words = { "grim", "bitter" } },
	{ flag = "deathless", words = { "unbroken", "untouched" } },
	{ flag = "keep", words = { "proud", "prized" } },
	{ flag = "trusted", words = { "old friend", "trusted" } },
	{ flag = "repeat", words = { "again and again" } },
	{ flag = "afterGap", words = { "long-awaited" } },
}
-- Feelings and motives (H4): never in Chronicle or Ledger.
V.feelings = { "felt", "proud", "happy", "glad", "sad", "afraid", "hoped", "wanted", "loved", "feared", "brave", "heroic", "joy" }

local function Find(text, word)
	local lowText = " " .. text:lower() .. " "
	local pattern = "%f[%w]" .. word:gsub("%-", "%%-") .. "%f[^%w%-]"
	return lowText:find(pattern) ~= nil
end
V.HasWord = Find

-- Lexicon words in a text: list of { word, flag }.
function V.LexiconWords(text)
	local found = {}
	if type(text) ~= "string" then return found end
	for _, row in ipairs(V.lexicon) do
		for _, word in ipairs(row.words) do
			if Find(text, word) then found[#found + 1] = { word = word, flag = row.flag } end
		end
	end
	return found
end

function V.FeelingWords(text)
	local found = {}
	if type(text) ~= "string" then return found end
	for _, word in ipairs(V.feelings) do
		if Find(text, word) then found[#found + 1] = word end
	end
	return found
end

function V.RaceRow(race)
	if type(race) ~= "string" then return nil end
	return V.race[RACE_ALIAS[race] or race]
end

function V.ClassRow(class)
	if type(class) ~= "string" then return nil end
	local key = class:sub(1, 1):upper() .. class:sub(2):lower()
	return V.class[key]
end

-- "a dwarf priest" (prose: race and class in lower case).
function V.Describe(race, class)
	local r, c = V.RaceRow(race), V.ClassRow(class)
	local words = {}
	if r then words[#words + 1] = r.noun end
	if c then words[#words + 1] = c.noun end
	if #words == 0 then return nil end
	local text = table.concat(words, " ")
	return E.Story.Grammar.WithArticle(text)
end

-- "a stout dwarf priest" (Bard: the race word, bound to me.race).
function V.DescribeBard(race, class)
	local r, c = V.RaceRow(race), V.ClassRow(class)
	if not (r and c) then return nil end
	return E.Story.Grammar.WithArticle(r.adj .. " " .. r.noun .. " " .. c.noun)
end

-- Reference nouns for the character (V4): "the priest", then "the dwarf".
function V.References(me)
	local list = {}
	local c = me and V.ClassRow(me.class)
	local r = me and V.RaceRow(me.race)
	if c then list[#list + 1] = "the " .. c.noun end
	if r and not r.noRef then list[#list + 1] = "the " .. r.noun end
	return list
end

-- The flying mount word for a flight path: bound to the faction and the
-- continent of the place (nil when either is unknown).
function V.FlightBeast(faction, zone)
	local row = V.faction[faction or ""]
	if not row or type(zone) ~= "string" then return nil end
	if row.batZones and row.batZones[zone] then return "bat" end
	local place = E.Story.Grammar.PlaceRow(zone)
	local continent = place and place.continent
	return continent and row.flight[continent]
end

-- The vehicle of a sea crossing, only from a recorded port subzone.
function V.Vehicle(faction, port)
	local W = E.StoryWorld or {}
	local row = W.ports and port and W.ports[port]
	if not row then return nil end
	if row.faction and row.faction ~= faction then return nil end
	if row.vehicle == "boat" then return "boat" end
	return row.vehicle
end

function V.Side(faction)
	local row = V.faction[faction or ""]
	return row and row.side
end

-- Zone flavor from the noun table: "epithet" (Chronicle) or "scene" (Bard).
function V.Flavour(name, which)
	local row = E.Story.Grammar.PlaceRow(name)
	if not row then return nil end
	return row[which]
end

function V.Entrance(name)
	local row = E.Story.Grammar.PlaceRow(name)
	return row and row.entrance
end

-- "those halls", "those caves", "the zone" (V4 reference phrases by type).
function V.PlaceReference(name)
	local row = E.Story.Grammar.PlaceRow(name)
	if row and (row.type == "instance" or row.type == "raid") then return "those " .. (row.hall or "halls") end
	if row and row.type == "city" then return "the city" end
	if row and row.type == "subzone" then return "the place" end
	if row and row.type == "battleground" then return "the battlefield" end
	return "the zone"
end

-- Forever context: an instance the Classic data does not
-- know is one WoW: Forever added. Without E.zoneData nothing is flagged.
function V.IsForeverOnly(instance)
	local Z = E.zoneData
	if type(instance) ~= "string" or not (Z and Z.originalInstanceNames and Z.Fold) then return false end
	if Z.originalInstanceNames[Z.Fold(instance)] then return false end
	local core = instance:gsub("^The ", "")
	if Z.originalInstanceNames[Z.Fold(core)] then return false end
	-- The noun table also knows the Classic instances by their own names.
	local row = E.Story.Grammar.PlaceRow(instance)
	if row and (row.type == "instance" or row.type == "raid") then return false end
	return true
end
