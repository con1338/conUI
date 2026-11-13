-- Story grammar: articles, places, possessives, plurals, counts, numbers,
-- durations, lists, capitals, dates and pronouns for the journal story.
--
-- English only. Plain Lua 5.1: no frames and no game calls except `date`
-- (Grammar.Date) and GetLocale at load. Every function accepts nil and returns nil or "" without
-- erroring. Names arrive as plain strings (the recorder checks secrets).
--
-- Style (the tone) decides how numbers are written:
--   ledger     digits always, "2h 05m" durations, "742g 12s" money
--   chronicle  words for zero to twelve, digits from 13
--   bard       words up to 999, digits above
-- Levels after the word "level" are always digits (the bank writes them so).
local _, E = ...

E.Story = E.Story or {}
local G = {}
E.Story.Grammar = G

G.style = "chronicle"
-- English phrasing ("the Barrens") only while EldoUI shows English on an
-- English client. Otherwise names pass through untouched, with the place
-- phrase of the language EldoUI shows around them (G.Place). G.english
-- pins it either way; nil follows the language.
local clientLocale = type(GetLocale) == "function" and GetLocale() or "enUS"
local clientEnglish = type(clientLocale) ~= "string" or clientLocale:sub(1, 2) == "en"
G.english = nil
local function English()
	if G.english ~= nil then return G.english end
	return clientEnglish and (not E.GetLanguage or E:GetLanguage() == "enUS")
end
G.English = English

-- "in <place>" outside the English grammar. The place phrase has its own
-- key, since a translation of "in %s" may be a time ("in 5 minutes").
function G.InPlace(name)
	if not E.GetLanguage or E:GetLanguage() == "enUS" then return ("in %s"):format(name) end
	return (E.L["in %s (place)"]):format(name)
end
G.utc = false           -- true: dates in UTC, the same on every machine
G.refYear = nil         -- a year is printed only when it differs from this one
G.unknown = {}          -- place names that fell through to the head-noun rule (GR-9)

local floor, abs = math.floor, math.abs
local format, upper, lower = string.format, string.upper, string.lower

local function World() return E.StoryWorld or {} end
local function Fold(text)
	text = lower(tostring(text or "")):gsub("'", ""):gsub("[%p%s]+", " ")
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end
G.Fold = Fold

local function Trim(text) return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
G.Trim = Trim

-- Markup ----------------------------------------------------------------------
function G.IsLink(text)
	if type(text) ~= "string" then return false end
	if text:find("|H", 1, true) then return true end
	return text:match("^%[.*%]$") ~= nil
end

function G.StripMarkup(text)
	if type(text) ~= "string" then return "" end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
	text = text:gsub("|H.-|h(.-)|h", "%1")
	return text
end

-- Splits "|cff112233Name|r" into prefix, visible text, suffix.
local function Wrap(text)
	local pre, body, post = text:match("^(|c%x%x%x%x%x%x%x%x)(.-)(|r)$")
	if pre then return pre, body, post end
	return "", text, ""
end

-- a / an by sound ----------------------------------------------------------------
local LETTER_AN = { a = true, e = true, f = true, h = true, i = true, l = true, m = true, n = true, o = true, r = true, s = true, x = true }
local YOU_STARTS = { "uni", "use", "usa", "usu", "uti", "ure", "uro", "eu", "ewe", "ubi" }

local function NumberAn(digits)
	local n = tonumber(digits)
	if not n then return false end
	if digits:sub(1, 1) == "8" then return true end
	-- 11 and 18, 11,000 and 18,000 ("eleven", "eighteen")
	local len = #digits
	if len == 2 or len == 5 or len == 8 then
		local two = digits:sub(1, 2)
		return two == "11" or two == "18"
	end
	return false
end

function G.Article(word)
	if type(word) ~= "string" or word == "" or G.IsLink(word) then return "" end
	local plain = Trim(G.StripMarkup(word))
	if plain == "" then return "" end
	local digits = plain:match("^(%d[%d,]*)")
	if digits then return NumberAn((digits:gsub(",", ""))) and "an" or "a" end
	local first = plain:match("^([%a']+)") or ""
	-- Acronyms of 2-5 capitals are said as letters ("an MC run", "a BRD run").
	if #first >= 2 and #first <= 5 and first:match("^%u+$") then
		local letter = lower(first:sub(1, 1))
		if letter == "u" then return "a" end
		return LETTER_AN[letter] and "an" or "a"
	end
	local low = lower(first)
	if low == "" then return "a" end
	for _, start in ipairs(YOU_STARTS) do
		if low:sub(1, #start) == start then
			-- "unique", "usable", "European"; but "un-" words ("undead",
			-- "Un'Goro", "Uldaman") keep "an".
			if not (start == "uni" and low:find("^unin")) then return "a" end
		end
	end
	if low == "one" or low:find("^once") or low:find("^one%-") then return "a" end
	local silent = World().silentHSet or {}
	if silent[low] then return "an" end
	if low:find("^[aeiou]") then return "an" end
	return "a"
end

function G.WithArticle(word)
	local article = G.Article(word)
	if article == "" then return word end
	return article .. " " .. word
end

-- Places and their articles -----------------------------------------
local function LastWord(text) return text:match("([%a']+)%s*$") or "" end

-- Returns "the" or "none", and the core (the name without a leading "The ").
local function ArticleOf(plain, log)
	local W = World()
	if plain:find("^The ") then return "the", plain:sub(5) end
	local key = Fold(plain)
	if (W.the and W.the[key]) or (W.factionThe and W.factionThe[key]) then return "the", plain end
	if W.bare and W.bare[key] then return "none", plain end
	if W.known and W.known[key] then return "none", plain end
	-- Unknown name (Forever-only content, new NPCs): the head-noun rule.
	if log then G.unknown[plain] = true end
	local last = LastWord(plain)
	for _, head in ipairs(W.pluralHeads or {}) do
		if last == head then return "the", plain end
	end
	local headOf = plain:match("^(%a+) of ")
	if headOf then
		for _, head in ipairs(W.ofHeads or {}) do
			if headOf == head then return "the", plain end
		end
	end
	return "none", plain
end
G.ArticleOf = function(name) return ArticleOf(Trim(G.StripMarkup(name)), false) end

local function IsAt(plain)
	local W = World()
	if W.at and W.at[Fold(plain)] then return true end
	local core = plain:gsub("^The ", "")
	if W.at and W.at[Fold(core)] then return true end
	local last = LastWord(plain)
	for _, head in ipairs(W.atHeads or {}) do
		if last == head then return true end
	end
	return false
end

local function IsPlural(plain)
	local W = World()
	local key = Fold(plain)
	if W.plural and W.plural[key] then return true end
	local core = plain:gsub("^The ", "")
	if W.plural and W.plural[Fold(core)] then return true end
	local last = LastWord(core)
	for _, head in ipairs(W.pluralHeads or {}) do
		if last == head then return true end
	end
	return false
end
G.IsPlural = function(name) return name and IsPlural(Trim(G.StripMarkup(name))) or false end

local PREPS = { ["in"] = true, to = true, from = true, at = true, into = true, of = true, on = true, near = true, toward = true, beyond = true }

function G.PlaceRow(name)
	if type(name) ~= "string" then return nil end
	local W = World()
	return W.byFold and W.byFold[Fold(G.StripMarkup(name))]
end

function G.Place(name, mode, quiet)
	if type(name) ~= "string" or name == "" then return nil end
	mode = mode or "bare"
	if G.IsLink(name) then return name end
	local plain = Trim(G.StripMarkup(name))
	if plain == "" then return nil end
	if not English() then
		-- The place phrase around the name; the other prepositions have no
		-- place text in the translations, so the name stays bare.
		if mode == "in" or mode == "auto" then return G.InPlace(name) end
		return name
	end
	local art, core = ArticleOf(plain, not quiet)
	local mid = art == "the" and ("the " .. core) or core
	local start = art == "the" and ("The " .. core) or core
	if mode == "bare" then return mid end
	if mode == "start" or mode == "head" then return start end
	if mode == "core" then return core end
	if mode == "short" then
		local W = World()
		return (W.short and W.short[Fold(plain)]) or mid
	end
	if mode == "auto" then return (IsAt(plain) and "at " or "in ") .. mid end
	if mode == "poss" then return G.Possessive(name) end
	if PREPS[mode] then return mode .. " " .. mid end
	return nil
end

-- "in the Crossroads, the Barrens", "in Duskwood", "in an unknown place"
-- (the death place, with the article fixed).
function G.Where(subzone, zone)
	if subzone == "" then subzone = nil end
	if zone == "" then zone = nil end
	if subzone and zone and subzone ~= zone then
		return G.Place(subzone, "auto") .. ", " .. G.Place(zone, "bare")
	end
	local one = zone or subzone
	if one then return "in " .. G.Place(one, "bare") end
	return "in an unknown place"
end

-- Possessives ---------------------------------------------
function G.Possessive(name)
	if type(name) ~= "string" or name == "" or G.IsLink(name) then return nil end
	local pre, body, post = Wrap(name)
	local plain = Trim(G.StripMarkup(body))
	if plain:find("'s$") or plain:find("'s ") then return nil end
	local W = World()
	local key = Fold(plain)
	local form = body
	local isPlace = W.known and W.known[key] or plain:find("^The ")
	if isPlace and English() then
		local art, core = ArticleOf(plain, false)
		form = art == "the" and ("the " .. core) or core
	end
	if IsPlural(plain) and form:find("s$") then return pre .. form .. "'" .. post end
	return pre .. form .. "'s" .. post
end

-- Plurals ----------------------------------------------------------------------------
local IRREGULAR = {
	dwarf = "dwarves", elf = "elves", wolf = "wolves", thief = "thieves", man = "men", woman = "women",
	foot = "feet", tooth = "teeth", mouse = "mice", person = "people", child = "children", life = "lives",
	knife = "knives", leaf = "leaves", staff = "staves",
}
local INVARIANT = {
	tauren = true, forsaken = true, undead = true, defias = true, sheep = true, deer = true, fish = true,
	gold = true, silver = true, copper = true, cloth = true, xp = true, ore = true,
}

local function KeepCase(source, target)
	if source:match("^%u%u+$") then return upper(target) end
	if source:match("^%u") then return upper(target:sub(1, 1)) .. target:sub(2) end
	return target
end

local function PluralWord(word)
	local low = lower(word)
	if INVARIANT[low] then return word end
	if IRREGULAR[low] then return KeepCase(word, IRREGULAR[low]) end
	if low:find("[sxz]$") or low:find("ch$") or low:find("sh$") then return word .. "es" end
	if low:find("[^aeiou]y$") then return word:sub(1, -2) .. "ies" end
	return word .. "s"
end

function G.Pluralize(noun)
	if type(noun) ~= "string" or noun == "" then return noun end
	if G.IsLink(noun) then return noun end
	local head, rest = noun:match("^(.-)( of .+)$")
	if head and head ~= "" then return G.Pluralize(head) .. rest end
	local before, last = noun:match("^(.-)([%a']+)$")
	if not last then return noun end
	return before .. PluralWord(last)
end

function G.Plural(n, one, many)
	if type(one) == "table" then one, many = one[1], one[2] end
	if n and abs(n) == 1 then return one end
	return many or G.Pluralize(one)
end

-- Numbers ---------------------------------------------------------------------------
local ONES = { [0] = "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven",
	"twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen" }
local TENS = { [2] = "twenty", [3] = "thirty", [4] = "forty", [5] = "fifty", [6] = "sixty", [7] = "seventy", [8] = "eighty", [9] = "ninety" }

local function Words(n)
	if n < 20 then return ONES[n] end
	if n < 100 then
		local t, o = floor(n / 10), n % 10
		return TENS[t] .. (o > 0 and ("-" .. ONES[o]) or "")
	end
	local h, rest = floor(n / 100), n % 100
	-- US style: "seven hundred forty-two", no "and".
	return ONES[h] .. " hundred" .. (rest > 0 and (" " .. Words(rest)) or "")
end
G.Words = function(n) return (n and n >= 0 and n < 1000 and n == floor(n)) and Words(n) or nil end
G.numberWords = {}
for i = 0, 999 do G.numberWords[Words(i)] = i end

function G.Digits(n)
	if type(n) ~= "number" then return nil end
	local negative = n < 0
	local text = tostring(floor(abs(n) + 0.5))
	local out = text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return (negative and "-" or "") .. out
end

local WORD_LIMIT = { chronicle = 12, diary = 12, bard = 999, saga = 999, ledger = -1 }

function G.Number(n, style)
	if type(n) ~= "number" then return nil end
	style = style or G.style
	local limit = WORD_LIMIT[style] or 12
	if n >= 0 and n == floor(n) and n <= limit then return Words(n) end
	return G.Digits(n)
end

function G.Count(n, noun, style)
	if type(n) ~= "number" or not noun then return nil end
	style = style or G.style
	local plural = G.Plural(n, noun)
	if n == 0 and style ~= "ledger" then
		return "no " .. G.Plural(2, noun)
	end
	return G.Number(n, style) .. " " .. plural
end

-- "once", "twice", "three times"; Ledger "1 time", "6 times".
function G.Times(n, style)
	if type(n) ~= "number" then return nil end
	style = style or G.style
	if style == "ledger" then return G.Digits(n) .. (n == 1 and " time" or " times") end
	if n == 1 then return "once" end
	if n == 2 then return "twice" end
	return G.Number(n, style) .. " times"
end

local ORDINAL_WORDS = { "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth",
	"eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth", "sixteenth", "seventeenth", "eighteenth", "nineteenth" }
local TENS_ORDINAL = { [2] = "twentieth", [3] = "thirtieth", [4] = "fortieth", [5] = "fiftieth", [6] = "sixtieth" }

function G.Ordinal(n, style)
	if type(n) ~= "number" then return nil end
	style = style or G.style
	if (style == "bard" or style == "saga") and n >= 1 and n <= 60 and n == floor(n) then
		if n < 20 then return ORDINAL_WORDS[n] end
		local t, o = floor(n / 10), n % 10
		if o == 0 then return TENS_ORDINAL[t] end
		return TENS[t] .. "-" .. ORDINAL_WORDS[o]
	end
	local last2, last = n % 100, n % 10
	local suffix = "th"
	if last2 < 11 or last2 > 13 then
		if last == 1 then suffix = "st" elseif last == 2 then suffix = "nd" elseif last == 3 then suffix = "rd" end
	end
	return G.Digits(n) .. suffix
end

function G.Levels(a, b)
	if type(a) ~= "number" then return nil end
	if not b or b == a then return "level " .. a end
	return ("levels %d-%d"):format(a, b)
end

-- Lists (serial comma) -----------------------------------------------
function G.List(items, opts)
	opts = opts or {}
	local conj = opts.conj or "and"
	local extra = opts.extra or 0
	local max = opts.max or 3
	local list = {}
	for _, item in ipairs(items or {}) do
		if item and item ~= "" then list[#list + 1] = item end
	end
	local n = #list
	if n == 0 then return extra > 0 and G.Count(extra, "other") or "" end
	if n > max or (extra > 0 and n >= 1) then
		local keep = n > max and (max - 1) or n
		local others = (n - keep) + extra
		local head = {}
		for i = 1, keep do head[i] = list[i] end
		local tail = G.Count(others, "other", opts.style)
		if keep == 1 then return head[1] .. " " .. conj .. " " .. tail end
		return table.concat(head, ", ") .. ", " .. conj .. " " .. tail
	end
	if n == 1 then return list[1] end
	if n == 2 then return list[1] .. " " .. conj .. " " .. list[2] end
	return table.concat(list, ", ", 1, n - 1) .. ", " .. conj .. " " .. list[n]
end

-- Capitals ---------------------------------------------------------------------
local SKIP_CHARS = { ['"'] = true, ["'"] = true, ["("] = true, ["["] = true, [" "] = true }

function G.Capitalize(text)
	if type(text) ~= "string" or text == "" then return text end
	text = text:gsub("^%s+", "")
	local i, len = 1, #text
	while i <= len do
		local two = text:sub(i, i + 1)
		if two == "|c" then
			i = i + 10
		elseif two == "|r" then
			i = i + 2
		elseif two == "|T" then
			local close = text:find("|t", i + 2, true)
			if not close then return text end
			i = close + 2
		elseif two == "|H" then
			return text
		else
			local ch = text:sub(i, i)
			if SKIP_CHARS[ch] then
				i = i + 1
			elseif ch:match("%l") then
				return text:sub(1, i - 1) .. upper(ch) .. text:sub(i + 1)
			else
				return text
			end
		end
	end
	return text
end

-- First letter lower case (for a sentence fragment used mid-sentence).
function G.Decapitalize(text)
	if type(text) ~= "string" then return text end
	return (text:gsub("^(%u)(%l)", function(a, b) return lower(a) .. b end))
end

function G.Lower(word)
	if type(word) ~= "string" then return nil end
	return lower(word)
end

-- Durations ------------------------------------------------------------
local function HoursText(half, style)
	-- half = number of half hours, >= 2
	local hours, extra = floor(half / 2), half % 2
	if hours == 1 then return extra == 1 and "an hour and a half" or "an hour" end
	local n = G.Number(hours, style)
	if extra == 1 then return n .. " and a half hours" end
	return n .. " hours"
end

function G.Duration(seconds, style)
	if type(seconds) ~= "number" or seconds < 0 then return nil end
	style = style or G.style
	local s = floor(seconds)
	if style == "ledger" then
		if s < 60 then return "<1m" end
		if s < 3600 then return ("%dm"):format(floor(s / 60)) end
		if s < 86400 then return ("%dh %02dm"):format(floor(s / 3600), floor(s % 3600 / 60)) end
		local d, h = floor(s / 86400), floor((s % 86400) / 3600 + 0.5)
		if h == 24 then d, h = d + 1, 0 end
		return h > 0 and ("%dd %dh"):format(d, h) or ("%dd"):format(d)
	end
	if s < 60 then return "less than a minute" end
	if s < 3600 then
		local m = floor(s / 60)
		if m == 1 then return "a minute" end
		return G.Count(m, "minute", style)
	end
	if s < 129600 then
		local u = 1800
		local base = floor(s / u) * u
		local rem = s - base
		local hedge = ""
		if rem >= u / 2 then
			base = base + u
			if base - s >= 120 then hedge = "almost " end
		elseif rem >= 120 then
			hedge = "a little over "
		end
		return hedge .. HoursText(base / u, style)
	end
	local d = floor(s / 86400)
	local h = floor((s % 86400) / 3600 + 0.5)
	if h == 24 then d, h = d + 1, 0 end
	local function Days(n) return n == 1 and "a day" or (G.Number(n, style) .. " days") end
	if h == 0 then return Days(d) end
	if h <= 2 then return "a little over " .. Days(d) end
	if h >= 22 then return "almost " .. Days(d + 1) end
	-- One number style inside one phrase: digits for both when either needs them.
	if G.Number(h, style) ~= G.Words(h) or G.Number(d, style) ~= G.Words(d) then
		return G.Count(d, "day", "ledger") .. " and " .. G.Count(h, "hour", "ledger")
	end
	return Days(d) .. " and " .. G.Count(h, "hour", style)
end

-- Money --------------------------------------------------------------------
function G.Money(copper, style)
	if type(copper) ~= "number" or copper < 0 then return nil end
	style = style or G.style
	copper = floor(copper)
	local g, s, c = floor(copper / 10000), floor(copper % 10000 / 100), copper % 100
	if style == "ledger" then
		local parts = {}
		if g > 0 then parts[#parts + 1] = G.Digits(g) .. "g" end
		if s > 0 then parts[#parts + 1] = s .. "s" end
		if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
		return table.concat(parts, " ")
	end
	if g >= 1 then return (s >= 50 and "a little over " or "") .. G.Number(g, style) .. " gold" end
	if s >= 1 then return G.Number(s, style) .. " silver" end
	return nil
end

-- Dates and times of day --------------------------------------------------------
local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }
local SHORT_MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

local function DateParts(t)
	local fn = date or (os and os.date)
	if not fn or type(t) ~= "number" then return nil end
	return fn(G.utc and "!*t" or "*t", t)
end
G.DateParts = DateParts

function G.Date(t, form)
	local d = DateParts(t)
	if not d then return nil end
	local year = (G.refYear and d.year ~= G.refYear) and (", " .. d.year) or ""
	if form == "short" or form == "ledger" then return SHORT_MONTHS[d.month] .. " " .. d.day .. year end
	return MONTHS[d.month] .. " " .. d.day .. year
end

function G.Year(t)
	local d = DateParts(t)
	return d and d.year
end

function G.TimeOfDay(t)
	local d = DateParts(t)
	if not d then return nil end
	local h = d.hour
	if h >= 5 and h <= 11 then return "morning" end
	if h >= 12 and h <= 16 then return "afternoon" end
	if h >= 17 and h <= 21 then return "evening" end
	return "night"
end

-- Shares of time in words ("two of every three hours").
function G.Share(x)
	if type(x) ~= "number" or x <= 0 then return nil end
	if x >= 0.9 then return "nearly all" end
	if x >= 0.72 then return "three of every four hours" end
	if x >= 0.6 then return "two of every three hours" end
	if x >= 0.45 then return "about half" end
	if x >= 0.3 then return "about a third" end
	return nil
end

-- Pronouns -----------------------------------------------------------------------
local PRONOUNS = {
	they = { they = "they", them = "them", their = "their", theirs = "theirs", themself = "themself", were = "they were", have = "they have", are = "they are" },
	she = { they = "she", them = "her", their = "her", theirs = "hers", themself = "herself", were = "she was", have = "she has", are = "she is" },
	he = { they = "he", them = "him", their = "his", theirs = "his", themself = "himself", were = "he was", have = "he has", are = "he is" },
}

-- setting "name" (Name only) returns nil: the caller uses the name instead.
function G.Pronoun(slot, setting)
	local row = PRONOUNS[setting or "they"]
	return row and row[slot]
end

-- Clean-up after slot filling -------------------------------------------------------------------
local DOUBLE_WORDS = { "a", "an", "the", "of", "in", "to", "and", "at", "on", "with", "for" }

function G.Clean(text, prose)
	if type(text) ~= "string" then return text end
	text = text:gsub("  +", " ")
	text = text:gsub(" ([,%.;:!%?])", "%1")
	-- A doubled article across a slot boundary ("in the The Barrens").
	text = text:gsub("(%f[%a][Tt]he) [Tt]he%f[%A]", "%1")
	text = text:gsub("%f[%a]([Aa]n?) an?%f[%A]", "%1")
	for _, word in ipairs(DOUBLE_WORDS) do
		text = text:gsub("%f[%a](" .. word .. ") " .. word .. "%f[%A]", "%1")
	end
	text = text:gsub(",,", ","):gsub("%.%.", ".")
	if prose then
		-- US punctuation: a period or comma right after a closing quote goes inside it.
		text = text:gsub('"([%.,])', '%1"')
	end
	return Trim(text)
end

-- Words of a sentence for the opening-words rule (V2).
function G.FirstWords(text, n)
	local plain = lower(G.StripMarkup(text or ""))
	local words = {}
	for word in plain:gmatch("[%a%d']+") do
		words[#words + 1] = word
		if #words >= n then break end
	end
	return table.concat(words, " ")
end
