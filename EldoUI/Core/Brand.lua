-- Fork (conUI): the name players read.
--
-- This fork is shown as "conUI". Only the visible name changes: folders,
-- globals (EldoUI, EldoUIDB), frame names, saved variables, share strings and
-- the plugin API keep EldoUI's names, so EldoUI releases still merge and a
-- player's saved settings carry over.
--
-- Every text a player reads comes out of E.L (Core/Locale.lua), so the name
-- is swapped there, on the way out, in whichever language is shown. The
-- English keys and the language packs keep saying "EldoUI" and stay the same
-- as upstream's. The few texts that skip L (the chat prefix, the addon list
-- title, the key binding header) read E.brand.
--
-- A name that is no prose keeps its spelling: folder and file names
-- (EldoUI_LootData, Interface\AddOns\EldoUI\...), saved variables (EldoUIDB),
-- frame names, code (EldoUI:RegisterPlugin, EldoUI.Ticker), TOC fields
-- (X-EldoUI-Locale), links (addon:EldoUI:...) and web addresses, because a
-- player has to type or find exactly that.
local _, E = ...

local UPSTREAM = "EldoUI"
E.brand = "conUI"
E.upstreamBrand = UPSTREAM

local find, sub, gsub = string.find, string.sub, string.gsub

-- Is the "EldoUI" at text[from, to - 1] the product's name in a sentence?
local function IsProse(text, from, to)
	local before = sub(text, from - 1, from - 1)
	-- A path, a link, an identifier: ...\EldoUI, github.com/x/EldoUI,
	-- addon:EldoUI:..., E.movers.EldoUI_...
	if before == "\\" or before == "/" or before == "_" or before == ":" then return false end
	-- TOC fields: X-EldoUI-Locale, X-Min-EldoUI.
	if before == "-" and (sub(text, from - 2, from - 2) == "X" or sub(text, from - 4, from - 2) == "Min") then return false end

	local after = sub(text, to, to)
	if after == "" then return true end
	if after == "_" or after == "\\" or after == "/" then return false end
	local nextChar = sub(text, to + 1, to + 1)
	-- EldoUI.lua, EldoUI.Ticker and EldoUI:RegisterPlugin are names; a full
	-- stop or a colon before a space (or the end) is punctuation.
	if after == "." or after == ":" then return not find(nextChar, "^[%w_]") end
	if find(after, "^[%w]") then
		-- "EldoUIs Optik" (German genitive) is the name; EldoUIDB is not.
		return after == "s" and not find(nextChar, "^[%w_]")
	end
	return true
end

local cache = {}

-- The text with the product's name as this fork shows it.
local function Brand(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return text end
	if not find(text, UPSTREAM, 1, true) then return text end
	local done = cache[text]
	if done then return done end
	local brand = E.brand
	done = gsub(text, "()" .. UPSTREAM .. "()", function(from, to)
		if IsProse(text, from, to) then return brand end
	end)
	cache[text] = done
	return done
end

function E:Brand(text)
	return Brand(text)
end

-- L and E:Plural hand out branded text. A text looked up a second time (by
-- the code that shows it) no longer holds the upstream name and comes back
-- as it is.
local meta = getmetatable(E.L)
local lookup = meta.__index
meta.__index = function(strings, key)
	return Brand(lookup(strings, key))
end

local plural = E.Plural
function E:Plural(n, one, other)
	return Brand(plural(self, n, one, other))
end
