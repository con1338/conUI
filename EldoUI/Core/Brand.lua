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

-- The short forms follow the name: the layouts "Eldo-Classic (1440p)" and
-- the look "Eldo blue" show as "con-Classic (1440p)" and "con blue", the
-- guide module "Eldostar" as "conStar". Their keys (EldoClassic, the module
-- name Eldostar, the theme "Eldo") stay.
E.brandShort = "con"
E.brandGuide = "conStar"

-- Is the name at text[from, to - 1] the product's name in a sentence?
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

-- What stands for the "Eldo" at text[from, to - 1], with the text it takes
-- along ("UI", "star"); nil when it stays.
local function Replacement(text, from, to)
	if sub(text, to, to + 1) == "UI" then
		if IsProse(text, from, to + 2) then return E.brand, to + 2 end
		return nil
	end
	-- modules.Eldostar and eldo:EldoChime are keys.
	if sub(text, from - 1, from - 1) == "." then return nil end
	if sub(text, to, to + 3) == "star" then
		if IsProse(text, from, to + 4) then return E.brandGuide, to + 4 end
		return nil
	end
	-- "Eldo-Classic", "Eldo blue", "Eldo": the word alone. EldoModern,
	-- EldoIcon and the author's name Eldodeldo go on in letters and stay.
	local after = sub(text, to, to)
	if find(after, "^[%w_]") then return nil end
	if after == "-" and not find(sub(text, to + 1, to + 1), "^%u") then return nil end
	if IsProse(text, from, to) then return E.brandShort, to end
	return nil
end

local cache = {}

-- The text with the product's name as this fork shows it.
local function Brand(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return text end
	if not find(text, "Eldo", 1, true) then return text end
	local done = cache[text]
	if done then return done end
	local parts, count, pos = {}, 0, 1
	while true do
		local from, to = find(text, "Eldo", pos, true)
		if not from then break end
		local word, resume = Replacement(text, from, to + 1)
		count = count + 1
		if word then
			parts[count] = sub(text, pos, from - 1) .. word
			pos = resume
		else
			parts[count] = sub(text, pos, to)
			pos = to + 1
		end
	end
	parts[count + 1] = sub(text, pos)
	done = table.concat(parts)
	-- English: "an EldoUI profile" is "a conUI profile". Other languages have
	-- their own "an" (German: "an conUI senden").
	if done ~= text and (not E.GetLanguage or E:GetLanguage() == "enUS") then
		done = gsub(gsub(done, "^([Aa])n con", "%1 con"), "([^%w])([Aa])n con", "%1%2 con")
	end
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
