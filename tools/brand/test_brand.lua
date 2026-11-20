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
Check(L["Eldo (flat, accent border)"], "con (flat, accent border)", "the short name before a bracket")
Check(L["Eldostar"], "conStar", "the guide module")
Check(L["Open the Eldostar guide. Eldostars Route"], "Open the conStar guide. conStars Route", "the guide module in a sentence")
Check(L["Eldo-Classic (1440p) and EldoUI Center"], "con-Classic (1440p) and conUI Center", "short and full name in one text")
for _, text in ipairs({
	"Copyright 2026 Eldodeldo",
	"EldoModern2000",
	"modules.Eldostar.provider",
	"eldo:EldoChime",
	"Interface\\AddOns\\EldoUI\\Media\\Textures\\EldoChevron.tga",
	"Eldo-udseende",
	-- These can be a character's name (E:Translate takes names too).
	"Eldo",
	"Eldo-Stormrage",
	-- The folder is still called EldoUI.
	"Put it next to the EldoUI folder in Interface\\AddOns.",
	"Delete the old EldoUI folders.",
	"THIRD_PARTY_NOTICES.md im EldoUI-Ordner.",
	"neben den Ordner EldoUI in Interface\\AddOns",
	"ved siden af EldoUI-mappen i Interface\\AddOns",
}) do
	Check(L[text], text, "kept as it is")
end

-- English articles follow the new name; other languages keep their "an".
Check(L["Paste an EldoUI string. An EldoUI profile is made."], "Paste a conUI string. A conUI profile is made.", "English article")
Check(L["An Eldostar guide and an Eldo-Vanilla Focus (1440p) layout"], "A conStar guide and a con-Vanilla Focus (1440p) layout", "English article, short forms")
Check(L["More than an EldoUI_LootData folder"], "More than an EldoUI_LootData folder", "the article of a kept name")
function E:GetLanguage() return "deDE" end
Check(L["Sendet es an EldoUI zurück."], "Sendet es an conUI zurück.", "German \"an\" stays")
E.GetLanguage = nil

Check(L["It comes with EldoUI: put it next to the EldoUI folder."], "It comes with conUI: put it next to the EldoUI folder.",
	"the product and its folder in one text")

-- French joins the article to the name.
function E:GetLanguage() return "frFR" end
Check(L["la mise à jour d'EldoUI"], "la mise à jour de conUI", "French d'")
Check(L["pour cet EldoUI"], "pour ce conUI", "French cet")
Check(L["viennent d'EldoUI_LootData."], "viennent d'EldoUI_LootData.", "French d' before a kept name")
E.GetLanguage = nil

-- Texts about EldoUI itself keep its name, in every language.
german["Copy it (Ctrl+C) and send it to EldoUI's authors."] = "Kopiert es und sendet es an EldoUIs Autoren."
Check(L["Copy it (Ctrl+C) and send it to EldoUI's authors."], "Kopiert es und sendet es an EldoUIs Autoren.", "a report to EldoUI's authors")
Check(L[L["Copy it (Ctrl+C) and send it to EldoUI's authors."]], "Kopiert es und sendet es an EldoUIs Autoren.", "the same, looked up twice")
Check(L["Thank you for standing behind EldoUI."], "Thank you for standing behind EldoUI.", "the thanks to EldoUI's supporters")
Check(E:Plural(2, "Send it to EldoUI's authors.", "Send them to EldoUI's authors."), "Send them to EldoUI's authors.", "E:Plural, about EldoUI")

-- A text looked up while a file loads (English) and again where it is shown,
-- once the saved language is read: the second lookup finds the translation.
german["Show EldoUI's party frames."] = nil
local early = L["Show EldoUI's party frames."]
Check(early, "Show conUI's party frames.", "at load, before the language is known")
german["Show EldoUI's party frames."] = "Zeigt EldoUIs Gruppenrahmen."
Check(L[early], "Zeigt conUIs Gruppenrahmen.", "shown later in the saved language")
Check(E:Plural(2, L["EldoUI kept %d value"], L["EldoUI kept %d values"]), "conUI kept %d values", "E:Plural with texts looked up before")

-- Names saved outside EldoUI keep EldoUI's wording.
Check(E:UpstreamText("Eldo-Classic (1440p)"), "Eldo-Classic (1440p)", "E:UpstreamText")
Check(E:UpstreamText(L["Eldo-Classic (1440p)"]), "Eldo-Classic (1440p)", "E:UpstreamText of a text as shown")

-- A text that was handed out comes back unchanged, and other values pass.
Check(L[L["Open the EldoUI options."]], "Open the conUI options.", "a second lookup")
Check(L["No name here."], "No name here.", "a text without the name")
Check(E:Brand(nil), nil, "nil")
Check(E:Brand(42), 42, "a number")

print(("%d checks passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
