-- Offline test of the Group Board parser (EldoUI_GroupBoard/Parse.lua).
-- Run from the repository root:  lua5.1 tools/groupboard/test_parse.lua
-- It loads EldoUI's own Core/Locale.lua for E:FoldText, so lines fold
-- exactly as in the game, then the plugin's Catalog.lua and Parse.lua.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/groupboard/") or "./"

-- WoW globals the loaded files touch.
function strtrim(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end
function GetLocale() return "enUS" end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end

local E = { apiVersion = 1 }
function E.RegisterEvent() end
function E.UnregisterEvent() end
EldoUI = E
assert(loadfile(ROOT .. "EldoUI/Core/Locale.lua"))("EldoUI", E)
E.Secret = function() return false end

local ns = {}
assert(loadfile(ROOT .. "EldoUI_GroupBoard/Catalog.lua"))("EldoUI_GroupBoard", ns)
assert(loadfile(ROOT .. "EldoUI_GroupBoard/Parse.lua"))("EldoUI_GroupBoard", ns)
local Parse, Catalog = ns.Parse, ns.Catalog

local failures, count = 0, 0

local function Show(value)
	if type(value) ~= "table" then return tostring(value) end
	local parts = {}
	for key, v in pairs(value) do
		if type(key) == "number" then parts[#parts + 1] = tostring(v) else parts[#parts + 1] = key .. "=" .. tostring(v) end
	end
	table.sort(parts)
	return "{" .. table.concat(parts, ",") .. "}"
end

local function Same(a, b)
	return Show(a) == Show(b)
end

-- want: nil for "no group post", else fields to compare (kind, places,
-- category, need, roles).
local function Check(line, want)
	count = count + 1
	local got = Parse.Read(line)
	local problems = {}
	if want == nil then
		if got ~= nil then problems[#problems + 1] = "expected no post, got " .. got.kind .. " " .. Show(got.places) end
	elseif got == nil then
		problems[#problems + 1] = "expected a post, got nil"
	else
		for field, value in pairs(want) do
			if not Same(got[field], value) then
				problems[#problems + 1] = ("%s: want %s, got %s"):format(field, Show(value), Show(got[field]))
			end
		end
	end
	if #problems > 0 then
		failures = failures + 1
		print("FAIL  " .. line)
		for _, problem in ipairs(problems) do print("      " .. problem) end
	end
end

-- English
Check("LF2M DM need tank and heal", { kind = "lfm", places = { "deadmines" }, need = 2, roles = { tank = true, heal = true } })
Check("LFM SM Lib, need 2 dps", { kind = "lfm", places = { "sm_lib" }, need = 2, roles = { dps = 2 } })
Check("LFM SM Cath/Arm farm", { kind = "lfm", places = { "sm_cath", "sm_arm" } })
Check("Tank LFG BRD", { kind = "lfg", places = { "brd" }, roles = { tank = true } })
Check("LF DM East group, mage 58", { kind = "lfg", places = { "dm_east" } })
Check("LFM Dire Maul East, need heal", { kind = "lfm", places = { "dm_east" }, roles = { heal = true }, need = 1 })
Check("LF1M heal UBRS 9/10", { kind = "lfm", places = { "ubrs" }, need = 1 })
Check("UBRS 7/10 LF healers", { kind = "lfm", places = { "ubrs" }, need = 3 })
Check("LFM strat UD baron run", { kind = "lfm", places = { "strat_ud" } })
Check("LFM strat live", { kind = "lfm", places = { "strat_live" } })
Check("LF tank for |cffffff00|Hquest:123:25|h[The Deadmines]|h|r", { kind = "lfm", places = { "deadmines" } })
Check("LFG west plaguelands quests", { kind = "lfg", places = {}, category = "quest" })
Check("LFM MC 30/40 need 2 heals", { kind = "lfm", places = { "mc" }, need = 10, roles = { heal = 2 }, category = "raid" })
Check("LF more for ZF", { kind = "lfm", places = { "zulfarrak" } })
Check("LF DM tank", { kind = "lfm", places = { "deadmines" }, roles = { tank = true } })
Check("LFM WSG premade", { kind = "lfm", category = "pvp" })
Check("LFM arm need heal", { kind = "lfm", places = { "sm_arm" } })
Check("LF tank DM, my arm hurts", { kind = "lfm", places = { "deadmines" } })
Check("{skull} LFM RFC {skull}", { kind = "lfm", places = { "ragefire" } })
Check("LFM Temple of Ahn'Qiraj", { kind = "lfm", places = { "aq40" } })
Check("LFG Zul'Farrak", { kind = "lfg", places = { "zulfarrak" } })
Check("LFM Blackmaw Hold need tank", { kind = "lfm", places = { "f_blackmaw" } })
Check("LF2dps BFD", { kind = "lfm", places = { "blackfathom" }, need = 2, roles = { dps = 2 } })
Check("looking for more for SFK", { kind = "lfm", places = { "shadowfang" } })
Check("looking for group WC", { kind = "lfg", places = { "wailing" } })
Check("LFM SM need 2 more", { kind = "lfm", places = { "sm" }, need = 2 })
-- German
Check("Suchen noch Tank und Heiler für die Todesminen", { kind = "lfm", places = { "deadmines" }, roles = { tank = true, heal = true } })
Check("Heiler sucht Gruppe für BRT", { kind = "lfg", places = { "brd" }, roles = { heal = true } })
Check("Gruppe sucht noch 2 DDs für Kloster Bibliothek", { kind = "lfm", places = { "sm_lib" }, need = 2, roles = { dps = 2 } })
Check("suche Gruppe für Düsterbruch Nord", { kind = "lfg", places = { "dm_north" } })
Check("LFM Hügel der Klingenhauer, brauchen Tank", { kind = "lfm", places = { "downs" } })
Check("Suche Mitspieler für den Tempel von Atal'Hakkar", { kind = "lfm", places = { "sunken" } })
Check("Tank sucht Gruppe Tempel von Ahn'Qiraj", { kind = "lfg", places = { "aq40" } })
Check("LF Heiler Höhlen des Wehklagens 3/5", { kind = "lfm", places = { "wailing" }, need = 2 })
Check("Suche Gruppe für Elitequests im Schlingendorntal", { kind = "lfg", places = {}, category = "quest" })
Check("DB Ost sucht noch einen Tank", { kind = "lfm", places = { "dm_east" } })
-- No group posts
Check("WTS [Lionheart Helm] 300g")
Check("LF enchanter for crusader")
Check("LF summon to ZF")
Check("WTB DM key")
Check("<Eisenwacht> sucht noch aktive Mitglieder, Gilde ist nett")
Check("Recruiting for our guild, LFM raiders")
Check("Anyone know where the Deadmines are?")
Check("selling SM boost")
Check("anyone up for some fun")

-- The catalog's level fit.
count = count + 1
if not (Catalog:Fits("deadmines", 20) and not Catalog:Fits("deadmines", 40) and Catalog:Fits("sm", 30) and Catalog:Fits("f_blackmaw", 10)) then
	failures = failures + 1
	print("FAIL  Catalog:Fits")
end

print(("%d of %d checks passed"):format(count - failures, count))
os.exit(failures == 0 and 0 or 1)
