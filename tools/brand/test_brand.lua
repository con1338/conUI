-- The fork's visible name (EldoUI/Core/Brand.lua): prose says "conUI", names
-- a player has to type or find keep "EldoUI". Run from the repository root:
--   lua5.1 tools/brand/test_brand.lua
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/brand/") or "./"

local passed, failed = 0, 0
local function Check(got, want, what)
	if got == want then
		passed = passed + 1
	else
		failed = failed + 1
		print(("FAIL: %s\n  got:  %s\n  want: %s"):format(what, tostring(got), tostring(want)))
	end
end

-- A stand-in for Core/Locale.lua: L gives the German text when there is one,
-- else the key; E:Plural picks by count.
local german = {
	["EldoUI settings"] = "EldoUI-Einstellungen",
	["EldoUI's look"] = "EldoUIs Optik",
}
local E = {
	L = setmetatable({}, { __index = function(_, key) return german[key] or key end }),
}
function E:Plural(n, one, other) return n == 1 and one or other end
assert(loadfile(ROOT .. "EldoUI/Core/Brand.lua"))("EldoUI", E)

local L = E.L
Check(E.brand, "conUI", "the name")

-- Prose: the name changes.
Check(L["Open the EldoUI options."], "Open the conUI options.", "a sentence")
Check(L["EldoUI"], "conUI", "the bare name")
Check(L["EldoUI: name"], "conUI: name", "a colon after the name")
Check(L["Thanks for using EldoUI."], "Thanks for using conUI.", "a full stop after the name")
Check(L["EldoUI's look"], "conUIs Optik", "a German genitive")
Check(L["EldoUI settings"], "conUI-Einstellungen", "a German compound")
Check(L["|cff33aaffEldoUI|r was updated"], "|cff33aaffconUI|r was updated", "inside a color code")
Check(L["%sEldoUI"], "%sconUI", "after a placeholder")
Check(L["EldoUI and EldoUI"], "conUI and conUI", "twice in one text")
Check(E:Plural(2, "EldoUI kept %d value", "EldoUI kept %d values"), "conUI kept %d values", "E:Plural")
Check(E:Plural(1, "EldoUI kept %d value", "EldoUI kept %d values"), "conUI kept %d value", "E:Plural, one")

-- Names: folders, files, saved variables, code, TOC fields and links stay.
for _, text in ipairs({
	"Install the EldoUI_LootData folder.",
	"Interface\\AddOns\\EldoUI\\Media\\Textures\\EldoIcon.tga",
	"WTF/Account/NAME/SavedVariables/EldoUI.lua",
	"Delete EldoUIDB.profiles to start over.",
	"EldoUIMessagesDB",
	"EldoUI:RegisterPlugin(addon, info)",
	"EldoUI.Ticker:Subscribe",
	"## X-EldoUI-Locale: daDK",
	"## X-Min-EldoUI: 0.7.1000",
	"|Haddon:EldoUI:link|h",
	"https://github.com/Eldodeldo/EldoUI/issues/new",
}) do
	Check(L[text], text, "kept as it is")
end
Check(L["EldoUI loads EldoUI_Emoji from Interface\\AddOns\\EldoUI_Emoji."], "conUI loads EldoUI_Emoji from Interface\\AddOns\\EldoUI_Emoji.",
	"prose and names in one text")

-- The short forms: layouts, looks and the guide module.
Check(L["Eldo-Classic (1440p)"], "con-Classic (1440p)", "a layout name")
Check(L["Eldo blue"], "con blue", "a look")
Check(L["Eldo"], "con", "the short name alone")
Check(L["Eldo (flat, accent border)"], "con (flat, accent border)", "the short name before a bracket")
Check(L["Eldostar"], "conStar", "the guide module")
Check(L["Open the Eldostar guide. Eldostars Route"], "Open the conStar guide. conStars Route", "the guide module in a sentence")
Check(L["Eldo-Classic and EldoUI Center"], "con-Classic and conUI Center", "short and full name in one text")
for _, text in ipairs({
	"Copyright 2026 Eldodeldo",
	"EldoModern2000",
	"modules.Eldostar.provider",
	"eldo:EldoChime",
	"Interface\\AddOns\\EldoUI\\Media\\Textures\\EldoChevron.tga",
	"Eldo-udseende",
}) do
	Check(L[text], text, "kept as it is")
end

-- English articles follow the new name; other languages keep their "an".
Check(L["Paste an EldoUI string. An EldoUI profile is made."], "Paste a conUI string. A conUI profile is made.", "English article")
Check(L["An Eldostar guide and an Eldo-Classic layout"], "A conStar guide and a con-Classic layout", "English article, short forms")
Check(L["More than an EldoUI_LootData folder"], "More than an EldoUI_LootData folder", "the article of a kept name")
function E:GetLanguage() return "deDE" end
Check(L["Sendet es an EldoUI zurück."], "Sendet es an conUI zurück.", "German \"an\" stays")
E.GetLanguage = nil

-- A text that was handed out comes back unchanged, and other values pass.
Check(L[L["Open the EldoUI options."]], "Open the conUI options.", "a second lookup")
Check(L["No name here."], "No name here.", "a text without the name")
Check(E:Brand(nil), nil, "nil")
Check(E:Brand(42), 42, "a number")

print(("%d checks passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
