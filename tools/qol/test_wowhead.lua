-- Offline test for the language of Wowhead links (Quality of Life >
-- Interface > Wowhead; review verbesserungen.md, B10).
-- Run from the repository root:
--   lua5.1 tools/qol/test_wowhead.lua
-- This cuts the address part out of EldoUI/Modules/QoL.lua (between fixed
-- markers, so a renamed part makes the test fail instead of testing a stale
-- copy) and runs it with a stand-in for the game's language and the page's
-- settings.
-- Checked: "Game language" (the default) gives the client's Wowhead
-- language and English where Wowhead has none; a picked language wins over
-- the client's; Classic and Retail keep their path; a profile from before
-- this setting behaves like "Game language"; the options row offers every
-- language once and only languages Wowhead has; the copy box and the Loot
-- Guide menu use the same address.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/qol/") or "./"

local function ReadFile(path)
	local file = assert(io.open(ROOT .. path, "rb"), "can't open " .. path)
	local text = file:read("*a")
	file:close()
	return (text:gsub("\r\n", "\n"))
end

-- The text from `first` up to (not including) `last`.
local function Between(text, first, last, where)
	local from = text:find(first, 1, true)
	assert(from, where .. ": marker not found: " .. first)
	local to = text:find(last, from + #first, true)
	assert(to, where .. ": end marker not found after " .. first .. ": " .. last)
	return text:sub(from, to - 1)
end

local qol = ReadFile("EldoUI/Modules/QoL.lua")
local block = Between(qol, "local WOWHEAD_SITES = {", "local LINK_KINDS = {", "QoL.lua Wowhead")

local client = "enUS"
function GetLocale() return client end

local M = { db = {} }
assert(loadstring("local M = ...\n" .. block, "=QoL.lua Wowhead"))(M)

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
local passed, failed = 0, 0
local function Check(ok, what)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. what) end
end
local function Is(got, want, what)
	Check(got == want, what .. " (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
end

local function URL(site, language, locale, kind, id)
	M.db.wowheadSite, M.db.wowheadLanguage, client = site, language, locale
	return M.WowheadURL(kind or "item", id or 19019)
end

-- Game language (the default).
Is(URL("classic", "auto", "deDE"), "https://www.wowhead.com/classic/de/item=19019", "German client: German Classic page")
Is(URL("classic", "auto", "enUS"), "https://www.wowhead.com/classic/item=19019", "English client: no language path")
Is(URL("classic", "auto", "enGB"), "https://www.wowhead.com/classic/item=19019", "British client: English")
Is(URL("classic", "auto", "frFR"), "https://www.wowhead.com/classic/fr/item=19019", "French client")
Is(URL("classic", "auto", "esMX"), "https://www.wowhead.com/classic/es/item=19019", "Latin American Spanish: Wowhead's Spanish")
Is(URL("classic", "auto", "ptBR"), "https://www.wowhead.com/classic/pt/item=19019", "Brazilian Portuguese")
Is(URL("classic", "auto", "zhCN"), "https://www.wowhead.com/classic/cn/item=19019", "Simplified Chinese")
Is(URL("classic", "auto", "zhTW"), "https://www.wowhead.com/classic/item=19019", "Traditional Chinese: no Wowhead page, English")
Is(URL("classic", nil, "deDE"), "https://www.wowhead.com/classic/de/item=19019", "a profile from before the setting: game language")

-- A picked language.
Is(URL("classic", "de", "enUS"), "https://www.wowhead.com/classic/de/item=19019", "German picked on an English client")
Is(URL("classic", "en", "deDE"), "https://www.wowhead.com/classic/item=19019", "English picked on a German client")
Is(URL("classic", "ko", "deDE"), "https://www.wowhead.com/classic/ko/item=19019", "Korean picked")
Is(URL("classic", "xx", "deDE"), "https://www.wowhead.com/classic/item=19019", "an unknown value: English, never a broken path")

-- The site and the kinds.
Is(URL("retail", "auto", "deDE", "quest", 123), "https://www.wowhead.com/de/quest=123", "Retail keeps its path")
Is(URL(nil, "auto", "deDE", "npc", 448), "https://www.wowhead.com/classic/de/npc=448", "no site saved: Classic")
Is(URL("classic", "auto", "deDE", "spell", 1459), "https://www.wowhead.com/classic/de/spell=1459", "spells")

-- The options row: every language once, each one Wowhead has.
do
	local row = qol:match('{ type = "select", key = "wowheadLanguage",(.-)order = {[^}]*}')
	Check(row ~= nil, "options row for the Wowhead language")
	local order = qol:match('key = "wowheadLanguage".-order = {([^}]*)}')
	local values = row and row:match("values = {(.-)}") or ""
	local valueKeys, count = {}, 0
	for key in values:gmatch("(%w+) = \"") do valueKeys[key] = true count = count + 1 end
	local seen, orderCount = {}, 0
	for key in (order or ""):gmatch('"(%w+)"') do
		Check(valueKeys[key], "order entry " .. key .. " has a label")
		Check(not seen[key], "order entry " .. key .. " only once")
		seen[key] = true
		orderCount = orderCount + 1
		if key ~= "auto" and key ~= "en" then
			-- A picked language must come back as its own path.
			Is(URL("classic", key, "enUS"), "https://www.wowhead.com/classic/" .. key .. "/item=19019", "picked " .. key)
		end
	end
	Is(orderCount, count, "every label in the order")
	Check(qol:find('wowheadLanguage = "auto",', 1, true) ~= nil, "default: game language")
end

-- The copy box uses the same address (and with it the Loot Guide's menu).
Check(qol:find("local url = WowheadURL(kind, id)", 1, true) ~= nil, "the copy box builds its address with WowheadURL")

print(("%d checks passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
