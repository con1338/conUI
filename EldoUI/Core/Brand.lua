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

-- The folder is still called EldoUI: "next to the EldoUI folder", "im
-- EldoUI-Ordner", "neben den Ordner EldoUI" keep the name, in every language
-- the texts come in.
local FOLDER_AFTER = { " folder", "-Ordner", "-mappe", " 폴더", "文件夹", "資料夾" }
local FOLDER_BEFORE = { "Ordner ", "dossier ", "carpeta ", "pasta ", "папкой ", "폴더를 " }
local function IsFolder(text, from, to)
	for _, word in ipairs(FOLDER_AFTER) do
		if sub(text, to, to + #word - 1) == word then return true end
	end
	for _, word in ipairs(FOLDER_BEFORE) do
		if from > #word and sub(text, from - #word, from - 1) == word then return true end
	end
	return false
end

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
		if IsProse(text, from, to + 2) and not IsFolder(text, from, to + 2) then return E.brand, to + 2 end
		return nil
	end
	-- modules.Eldostar and eldo:EldoChime are keys.
	if sub(text, from - 1, from - 1) == "." then return nil end
	if sub(text, to, to + 3) == "star" then
		if IsProse(text, from, to + 4) then return E.brandGuide, to + 4 end
		return nil
	end
	-- "Eldo-Classic (1440p)" (a layout: a name, then its screen size) and
	-- "Eldo blue", "Eldo (flat, accent border)": the word before a space.
	-- EldoModern, EldoIcon and the author's name Eldodeldo go on in letters
	-- and stay. So do the bare word and "Eldo-Realm": they can be a
	-- character's name, which reaches L through E:Translate.
	local after = sub(text, to, to)
	if after == "-" then
		if not find(text, "^%-%u[%a ]- %(%d+p%)", to) then return nil end
	elseif after ~= " " then
		return nil
	end
	if IsProse(text, from, to) then return E.brandShort, to end
	return nil
end

-- French joins the article to a vowel: "d'EldoUI" is "de conUI", "cet
-- EldoUI" is "ce conUI".
local ELISIONS = { ["d'"] = "de ", ["D'"] = "De ", ["qu'"] = "que ", ["cet "] = "ce " }
local function Elide(lead)
	for joined, apart in pairs(ELISIONS) do
		if sub(lead, -#joined) == joined and not find(sub(lead, -#joined - 1, -#joined - 1), "^%a") then
			return sub(lead, 1, -#joined - 1) .. apart
		end
	end
	return lead
end

local caches = {} -- language -> text -> the text as shown
local origin = {} -- a text as shown -> the text it was made from

-- The text with the product's name as this fork shows it.
local function Brand(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return text end
	if not find(text, "Eldo", 1, true) then return text end
	local language = E.GetLanguage and E:GetLanguage() or "enUS"
	local cache = caches[language]
	if not cache then
		cache = {}
		caches[language] = cache
	end
	local done = cache[text]
	if done then return done end
	local parts, count, pos = {}, 0, 1
	while true do
		local from, to = find(text, "Eldo", pos, true)
		if not from then break end
		local word, resume = Replacement(text, from, to + 1)
		count = count + 1
		if word then
			parts[count] = Elide(sub(text, pos, from - 1)) .. word
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
	if done ~= text and language == "enUS" then
		done = gsub(gsub(done, "^([Aa])n con", "%1 con"), "([^%w])([Aa])n con", "%1%2 con")
	end
	cache[text] = done
	if done ~= text then origin[done] = text end
	return done
end

function E:Brand(text)
	return Brand(text)
end

-- Texts about EldoUI itself keep its name: reports that go to EldoUI's
-- authors, and the thanks to the people who built it. Found by their English
-- key, so the translations are kept too.
local UPSTREAM_KEYS = { "EldoUI's authors", "that went into EldoUI", "standing behind EldoUI" }
local kept = {} -- a text handed out with EldoUI's name
local function IsUpstream(key)
	if type(key) ~= "string" or (issecretvalue and issecretvalue(key)) then return false end
	if kept[key] then return true end
	for _, words in ipairs(UPSTREAM_KEYS) do
		if find(key, words, 1, true) then return true end
	end
	return false
end

-- L and E:Plural hand out branded text. Much of the code looks a text up
-- while its file loads and again where it is shown (in the language saved
-- for the account, which is read later): the second lookup gets the branded
-- text, so it is traced back to the key it came from first.
local meta = getmetatable(E.L)
local lookup = meta.__index
meta.__index = function(strings, key)
	local source = key ~= nil and origin[key]
	if source then key = source end
	local text = lookup(strings, key)
	if IsUpstream(key) then
		if type(text) == "string" then kept[text] = true end
		return text
	end
	return Brand(text)
end

local plural = E.Plural
function E:Plural(n, one, other)
	one, other = origin[one] or one, origin[other] or other
	local text = plural(self, n, one, other)
	if IsUpstream(other) or IsUpstream(one) then
		if type(text) == "string" then kept[text] = true end
		return text
	end
	return Brand(text)
end

-- The text with EldoUI's own names, for a name saved outside EldoUI that
-- must not change with the fork's name (the Details and BigWigs profiles
-- "EldoUI - <layout>").
function E:UpstreamText(key)
	return lookup(self.L, key ~= nil and origin[key] or key)
end
