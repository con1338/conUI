-- EldoUI Group Board: reading a chat line.
--
-- Parse.Read(text) turns one line from a public channel into what the
-- board lists, or nil when the line is no group post:
--
--   {
--     kind     = "lfm" | "lfg",     -- a group looking for players, or a
--                                   -- player looking for a group
--     category = "dungeon" | "raid" | "quest" | "pvp" | "other",
--     places   = { "deadmines", ... }, -- Catalog keys, in the line's order
--     roles    = { tank = 1, heal = true, dps = 2 }, -- needed (lfm) or
--                                   -- offered (lfg); a number when written
--     need     = 2,                 -- players needed, when the line says
--     have = 3, size = 5,           -- from "3/5"
--     text     = "LF2M DM ...",     -- the line without link and color codes
--   }
--
-- The line is folded the way EldoUI folds search text (E:FoldText: lower
-- case, no accents, punctuation as spaces), then read word by word:
--   * markers: LFM, LF2M, "need", "suchen noch", "x/5" (a group) against
--     LFG, "LF group", "suche Gruppe" (a player); "LF" and "suche" before a
--     role or a number mean a group, before a place or "group" a player;
--   * places: the longest phrase of the catalog wins ("dm east" over "dm");
--   * roles: tank, healer and damage words in English and German, with a
--     count written before them ("2 dps", "2x dd", "1heal");
--   * trade, guild recruiting and services (summons, portals, enchants,
--     boosts) are no group posts.
-- Only plain text is read: nothing in the line is run, linked or kept with
-- its codes. Written from scratch for this fork of EldoUI.
local _, ns = ...
local E = EldoUI
if not (E and E.apiVersion and E.apiVersion >= 1) then return end

local Parse = {}
ns.Parse = Parse

local Catalog = ns.Catalog
local MAX_TEXT = 255

---------------------------------------------------------------------------
-- Word lists (folded)
---------------------------------------------------------------------------
local function Set(list)
	local set = {}
	for _, word in ipairs(list) do set[word] = true end
	return set
end

local ROLE_WORDS = {
	tank = "tank", tanks = "tank", tankz = "tank", tanky = "tank",
	heal = "heal", heals = "heal", healz = "heal", healer = "heal", healers = "heal", heiler = "heal", heilerin = "heal",
	dps = "dps", dd = "dps", dds = "dps", rdps = "dps", mdps = "dps", damage = "dps", dmg = "dps", schaden = "dps",
}

-- Group words after "lf" / "suche" / "looking for".
local GROUP_WORDS = Set({ "group", "grp", "groups", "party", "gruppe", "grupe", "gruppen" })

-- Player words after them: a group looking for players.
local PLAYER_WORDS = Set({ "more", "mehr", "noch", "all", "alle", "people", "players", "player", "member", "spieler",
	"mitspieler", "leute" })

-- A group looking for players, on their own.
local LFM_WORDS = Set({ "lfm", "lfmore", "need", "needs", "ned", "brauchen", "brauche", "fehlt", "fehlen", "gesucht",
	"suchen", "sucht" })

-- A player looking for a group, on their own.
local LFG_WORDS = Set({ "lfg", "lfgroup", "lfgrp" })

-- Lines that are no group posts.
local NOT_GROUP = Set({
	"wts", "wtb", "wtt", "lfw", "selling", "buying", "verkaufe", "kaufe", "vk",
	"recruit", "recruiting", "recruits", "rekrutiert", "rekrutieren", "rekrutierung",
	"boost", "boosts", "boosting", "carry", "carries",
	"summon", "summons", "port", "ports", "portal", "portals",
	"enchant", "enchanter", "enchants", "ench", "verzauberer", "verzauberung", "verzauberungen",
	"lockpick", "lockpicking", "schlossknacken", "crafter", "craft", "crafting",
})
-- Guild and recruiting words: no group post unless a place is named.
local GUILD_WORDS = Set({ "guild", "gilde", "members", "mitglieder", "raidgilde" })

local QUEST_WORDS = Set({ "quest", "quests", "q", "qs", "elite", "elitequest", "gruppenquest", "questgruppe",
	"questing", "questen" })
local RAID_WORDS = Set({ "raid", "raids", "schlachtzug", "sz" })
local PVP_WORDS = Set({ "bg", "bgs", "pvp", "wsg", "av", "warsong", "arathi", "alterac", "premade",
	"schlachtfeld", "kriegshymnenschlucht", "arathibecken", "alteractal" })

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
-- The line without color, texture, atlas and link codes. A link keeps its
-- shown text ("[The Deadmines]"); raid marks ({skull}, {rt1}) go.
function Parse.Clean(text)
	if type(text) ~= "string" then return "" end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	text = text:gsub("|H.-|h(.-)|h", "%1")
	text = text:gsub("|T.-|t", " "):gsub("|A.-|a", " "):gsub("|K.-|k", " ")
	text = text:gsub("|n", " ")
	text = text:gsub("{[^}]*}", " ")
	-- Any code left is shown as text, never read as one.
	text = text:gsub("|", "/")
	text = text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	if #text > MAX_TEXT then text = text:sub(1, MAX_TEXT) end
	return text
end

-- Folded words; a count glued to a word is split off ("2dps" -> "2", "dps",
-- "2x" -> "2", "x") and so is "lf" before a role ("lftank" -> "lf", "tank",
-- "lf2dps" -> "lf", "2", "dps").
function Parse.Words(text)
	local words = {}
	for word in Catalog.Fold(text):gmatch("%S+") do
		local count, rest = word:match("^(%d+)(%a+)$")
		local role = word:match("^lf(%a+)$")
		local lfCount, lfRole = word:match("^lf(%d+)(%a+)$")
		if lfCount and ROLE_WORDS[lfRole] then
			words[#words + 1] = "lf"
			words[#words + 1] = lfCount
			words[#words + 1] = lfRole
		elseif count and (rest == "x" or ROLE_WORDS[rest]) then
			words[#words + 1] = count
			words[#words + 1] = rest
		elseif role and ROLE_WORDS[role] then
			words[#words + 1] = "lf"
			words[#words + 1] = role
		else
			words[#words + 1] = word
		end
	end
	return words
end

---------------------------------------------------------------------------
-- Places
---------------------------------------------------------------------------
local byFirst, byFirstVersion -- first word -> list of catalog words, longest first

local function Index()
	local list = Catalog:Words()
	if byFirst and byFirstVersion == Catalog.version then return byFirst end
	byFirst = {}
	for _, item in ipairs(list) do
		local first = item.parts[1]
		if first then
			byFirst[first] = byFirst[first] or {}
			table.insert(byFirst[first], item)
		end
	end
	byFirstVersion = Catalog.version
	return byFirst
end

local function MatchAt(words, index, parts)
	for offset = 1, #parts do
		if words[index + offset - 1] ~= parts[offset] then return false end
	end
	return true
end

-- Leftmost, longest: { { key, at, len, weak, solo }, ... }; used[i] is the
-- last word of the place that took word i.
local function FindPlaces(words, used)
	local index = Index()
	local found = {}
	local at = 1
	while at <= #words do
		local hit
		for _, item in ipairs(index[words[at]] or {}) do
			if MatchAt(words, at, item.parts) then
				hit = item
				break
			end
		end
		if hit then
			found[#found + 1] = { key = hit.key, at = at, len = #hit.parts, weak = hit.weak, solo = hit.solo }
			for offset = 0, #hit.parts - 1 do used[at + offset] = at + #hit.parts - 1 end
			at = at + #hit.parts
		else
			at = at + 1
		end
	end
	return found
end

local function InFamily(key, set)
	local entry = Catalog:Get(key)
	while entry and entry.parent do
		if set[entry.parent] then return true end
		entry = Catalog:Get(entry.parent)
	end
	return false
end

-- The places the line names, in its order; a wing replaces its parent.
local function ResolvePlaces(found)
	local strong, any = {}, false
	for _, hit in ipairs(found) do
		if not hit.weak and not hit.solo then
			strong[hit.key] = true
			any = true
		end
	end
	local chosen, order = {}, {}
	for _, hit in ipairs(found) do
		local take
		if hit.weak then
			take = InFamily(hit.key, strong)
		elseif hit.solo then
			take = InFamily(hit.key, strong) or not any
		else
			take = true
		end
		if take and not chosen[hit.key] then
			chosen[hit.key] = hit.at
			order[#order + 1] = hit.key
		end
	end
	local places = {}
	for _, key in ipairs(order) do
		local wing = false
		for _, child in ipairs(Catalog:Get(key).children) do
			if chosen[child] then wing = true end
		end
		if not wing then places[#places + 1] = key end
	end
	return places
end

---------------------------------------------------------------------------
-- Markers and roles
---------------------------------------------------------------------------
local function Number(word)
	local n = tonumber(word)
	if n and n >= 1 and n <= 39 and n == math.floor(n) then return n end
end

-- What follows "lf", "suche" or "looking for": "lfm" (a role, a count,
-- "more", players), "lfg" (a group word, a place) or nil. A place with a
-- role after it is a group looking for that role ("LF DM tank").
local function After(words, at, used)
	local next = words[at]
	if not next then return nil end
	if ROLE_WORDS[next] or Number(next) or PLAYER_WORDS[next] then return "lfm" end
	if used[at] then
		local after = words[used[at] + 1]
		if after and ROLE_WORDS[after] then return "lfm" end
		return "lfg"
	end
	if GROUP_WORDS[next] then return "lfg" end
	if next == "a" or next == "an" or next == "eine" or next == "ne" then
		local after = words[at + 1]
		if after and (GROUP_WORDS[after] or used[at + 1]) then return "lfg" end
		return "lfm"
	end
	return nil
end

-- "3/5" in the clean text: have, size.
local function Fraction(text)
	for have, size in text:gmatch("(%d+)%s*/%s*(%d+)") do
		have, size = tonumber(have), tonumber(size)
		if size and have and (size == 5 or size == 10 or size == 15 or size == 20 or size == 40) and have >= 1 and have < size then
			return have, size
		end
	end
end

local function Roles(words)
	local roles, any = {}, false
	for at, word in ipairs(words) do
		local role = ROLE_WORDS[word]
		if role then
			local count = Number(words[at - 1])
			if not count and words[at - 1] == "x" then count = Number(words[at - 2]) end
			if count then
				roles[role] = (type(roles[role]) == "number" and roles[role] or 0) + count
			elseif roles[role] == nil then
				roles[role] = true
			end
			any = true
		end
	end
	return any and roles or nil
end

---------------------------------------------------------------------------
-- The line
---------------------------------------------------------------------------
function Parse.Read(raw)
	if type(raw) ~= "string" or raw == "" then return nil end
	local text = Parse.Clean(raw)
	if text == "" then return nil end
	local words = Parse.Words(text)
	if #words == 0 then return nil end

	local guild = false
	for _, word in ipairs(words) do
		if NOT_GROUP[word] then return nil end
		if GUILD_WORDS[word] then guild = true end
	end

	local used = {}
	local places = ResolvePlaces(FindPlaces(words, used))

	local lfm, lfg, need = false, false, nil
	for at, word in ipairs(words) do
		local count = word:match("^lf(%d+)m?$")
		if count and Number(count) then
			lfm = true
			need = need or Number(count)
		elseif LFM_WORDS[word] then
			-- "Tank sucht Gruppe" is a player; "Gruppe sucht Tank" a group.
			if word == "sucht" and GROUP_WORDS[words[at + 1] or ""] then lfg = true else lfm = true end
		elseif LFG_WORDS[word] then
			lfg = true
		elseif word == "lf" or word == "suche" then
			local kind = After(words, at + 1, used)
			if kind == "lfm" then lfm = true elseif kind == "lfg" then lfg = true end
		elseif word == "looking" and words[at + 1] == "for" then
			local kind = After(words, at + 2, used)
			if kind == "lfm" then lfm = true elseif kind == "lfg" then lfg = true end
		elseif (word == "more" or word == "mehr") and Number(words[at - 1]) then
			need = need or Number(words[at - 1])
		end
	end
	local have, size = Fraction(text)
	if have then
		lfm = true
		need = need or (size - have)
	end
	if not (lfm or lfg) then return nil end
	if guild and #places == 0 then return nil end

	-- Without a count, each role named counts one ("LFM tank heal": 2).
	local roles = Roles(words)
	if lfm and not need and roles then
		local total = 0
		for _, count in pairs(roles) do total = total + (type(count) == "number" and count or 1) end
		need = total
	end

	local category
	if #places > 0 then
		category = Catalog:Get(places[1]).kind == "raid" and "raid" or "dungeon"
	else
		category = "other"
		for _, word in ipairs(words) do
			if PVP_WORDS[word] then category = "pvp" break end
			if RAID_WORDS[word] then category = "raid" end
			if (QUEST_WORDS[word] or word:find("quest", 1, true)) and category == "other" then category = "quest" end
		end
	end

	return {
		kind = lfm and "lfm" or "lfg",
		category = category,
		places = places,
		roles = roles,
		need = need,
		have = have,
		size = size,
		text = text,
	}
end
