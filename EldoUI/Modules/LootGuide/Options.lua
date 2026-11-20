-- EldoUI Loot Guide: settings page, help and style presets.
--
-- A short page: the rows players change, rare settings behind the gear
-- (cog) of the row they belong to. Window state (last page, filters, sort)
-- is saved per character without an option. The tooltip lines have their
-- Always / Shift / Ctrl / Alt / Never switches on the Tooltip page; which
-- kinds of sources they list is in the Drop chances cog here.
--
-- Dependent hides: Best in Slot off hides the rating mode (and the
-- simulator speed), Wishlist off hides the wishlist alerts; rows of pages
-- or Catalog sections that are not built stay hidden.
local _, E = ...
local LG = E.LootGuide
local L = E.L

local Key = E.Key
-- Fork (conUI): the fork's page and issues, like Errors.REPORT_URL.
local REPO_URL = "https://github.com/con1338/conUI"
local ISSUES_URL = "https://github.com/con1338/conUI/issues"

local PAGE_TITLES = {
	foryou = Key("For You"), journal = Key("Journal"), world = Key("Open World"), bis = Key("Best in Slot"),
	wishlist = Key("Wishlist"), catalogue = Key("Catalog"), database = Key("Database"),
}

local function NoPages()
	return #LG:Pages(true) == 0
end

local function NoInstancePage()
	for _, page in ipairs(LG:Pages(true)) do
		if page.instanceRoute then return false end
	end
	return true
end

local function NoSection(key)
	return function() return not (LG.CatalogueSection and LG:CatalogueSection(key)) end
end

local function PhaseChoices()
	return LG:PhaseValues(true)
end

local function NoPhases()
	return LG:MaxPhase() == nil
end

local function StartValues()
	local values = {}
	for _, page in ipairs(LG:Pages(true)) do values[page.key] = page.title or page.key end
	values.last = L["Where you left it"]
	return values
end

-- One switch per page (rows of pages that are not built stay hidden); the
-- last page switched on stays on.
local function PageSwitches()
	local rows = {}
	for _, key in ipairs(LG.PAGE_KEYS) do
		local title = PAGE_TITLES[key] or key
		local desc = key == "bis" and Key("Show the %s page in the Loot Guide window. Hiding it also hides gain marks in lists and plan sets in tooltips.")
			or key == "wishlist" and Key("Show the %s page in the Loot Guide window. Hiding it also hides the wishlist stars and tooltip line.")
			or Key("Show the %s page in the Loot Guide window.")
		rows[#rows + 1] = {
			type = "toggle", key = "pages." .. key, label = title, desc = desc, descFill = title,
			hidden = function() return LG:GetPage(key) == nil end,
			disabled = function()
				if not LG:IsPageOn(key) then return false end
				return #LG:Pages() <= 1 and L["At least one page stays on."] or false
			end,
		}
	end
	return rows
end

---------------------------------------------------------------------------
-- "Rate items by" lives in the scoring engine (per character); the row
-- reaches it through a stand-in table that holds nothing itself and leaves
-- the profile again at logout.
---------------------------------------------------------------------------
local ENGINE_FIELDS = {
	rating = {
		get = function() return E.ItemScore and E.ItemScore:GetRating() or "weights" end,
		set = function(value)
			if E.ItemScore then E.ItemScore:SetRating(value) end
			LG:Fire("settings")
		end,
	},
}

local engineProxy = setmetatable({}, {
	__index = function(_, key)
		local field = ENGINE_FIELDS[key]
		if field then return field.get() end
	end,
	__newindex = function(_, key, value)
		local field = ENGINE_FIELDS[key]
		if field then field.set(value) end
	end,
})

local function EngineKey(path)
	return function()
		local db = LG.db
		if db and rawget(db, "engine") ~= engineProxy then rawset(db, "engine", engineProxy) end
		return path
	end
end

LG:Listen("PLAYER_LOGOUT", "options", function()
	if type(EldoUIDB) ~= "table" or type(EldoUIDB.profiles) ~= "table" then return end
	for _, profile in pairs(EldoUIDB.profiles) do
		local settings = type(profile) == "table" and type(profile.modules) == "table" and profile.modules.LootGuide
		if type(settings) == "table" and rawget(settings, "engine") == engineProxy then settings.engine = nil end
	end
end)

local function RaterValues()
	local values = {}
	for _, rater in ipairs(E.ItemScore and E.ItemScore:Raters() or {}) do values[rater.key] = rater.title end
	return values
end

local function NoRating()
	return not LG:BiSOn() or not E.ItemScore or #E.ItemScore:Raters() < 2
end

-- The kinds of sources the item tooltip lists (Drop chances cog).
local SOURCE_KINDS = {
	{ "drops", Key("Drops"), Key("Creatures and containers that drop the item, with the chance.") },
	{ "quests", Key("Quests"), Key("Quests that reward the item, need it or start from it.") },
	{ "vendors", Key("Vendors"), Key("Vendors that sell the item, where they stand and what it costs.") },
	{ "reputation", Key("Reputation"), Key("The reputation the item needs, red while you are below it.") },
	{ "pvp", Key("PvP"), Key("The honor cost and PvP rank the item needs.") },
	{ "crafting", Key("Crafting"), Key("Crafted items and recipes: the profession, skill and whether you know it.") },
	{ "sets", Key("Sets and tokens"), Key("The set an item is part of (owned of total) and what a token buys.") },
}

local function SourceToggles()
	local rows = {}
	for _, kind in ipairs(SOURCE_KINDS) do
		rows[#rows + 1] = { type = "toggle", key = "tipSources." .. kind[1], label = "Tooltip: %s", labelFill = kind[2], desc = kind[3] }
	end
	return rows
end

local function DropCog()
	local rows = {
		{ type = "select", key = "minQuality", label = L["Lowest item quality"], hidden = NoPages,
			values = { [0] = L["Poor (gray)"], [1] = L["Common (white)"], [2] = L["Uncommon (green)"], [3] = L["Rare (blue)"], [4] = L["Epic (purple)"] },
			desc = L["Loot lists in the Journal and on creature pages hide items below this quality. Quest rewards always show."] },
		{ type = "toggle", key = "phaseBadges", label = L["Opening day badges"], hidden = NoPhases,
			desc = L["Marks loot and instances WoW: Forever has announced but not opened yet with the day they open."] },
		{ type = "select", key = "phaseOverride", label = L["Content open now"], values = PhaseChoices, hidden = NoPhases,
			desc = L["What counts as open on WoW: Forever. Auto follows the announced days; pick a step if the game opens it earlier or later."] },
	}
	for _, row in ipairs(SourceToggles()) do rows[#rows + 1] = row end
	rows[#rows + 1] = { type = "execute", label = L["Show sample tooltip"], testSafe = true, func = function() LG:ShowSampleTooltip() end,
		desc = L["Shows an item tooltip with the Loot Guide lines, so you can see your settings."] }
	rows[#rows + 1] = { type = "execute", label = L["Tooltip line settings"], func = function() E:ToggleConfig("module:Tooltip") end,
		desc = L["Choose when each Loot Guide line shows: Always, with Shift, Ctrl or Alt, or Never (Tooltip page)."] }
	rows[#rows + 1] = { type = "execute", label = L["Show data status"], testSafe = true, func = function() LG:PrintDataStatus() end,
		desc = L["Prints where the loot data comes from, its version and size (same as /lg data)."] }
	return rows
end

-- Open on: page switches, then the Catalog sections' rare settings.
local function StartCog()
	local rows = PageSwitches()
	local catalogue = {
		{ type = "toggle", key = "craftOwnFirst", label = L["Crafting: your professions first"], hidden = NoSection("crafting"),
			desc = L["Crafting lists the professions you have before the others."] },
		{ type = "toggle", key = "craftShowGrey", label = L["Crafting: show gray recipes"], hidden = NoSection("crafting"),
			desc = L["Also lists recipes that no longer give you skill points."] },
		{ type = "toggle", key = "repShowAll", label = L["Reputation: factions you have not met"], hidden = NoSection("reputation"),
			desc = L["Reputation also lists factions your character has not met yet."] },
		{ type = "input", key = "pvpIncome", label = L["PvP: honor per week"], hidden = NoSection("pvp"),
			desc = L["The PvP planner works out weeks from this. Leave 0 to use what you earned in recent weeks."] },
		{ type = "toggle", key = "setsMyClass", label = L["Sets: your class first"], hidden = NoSection("sets"),
			desc = L["Sets and tokens starts on your own class. The class menu there still shows the others."] },
		{ type = "toggle", key = "collectHideLearned", label = L["Collections: hide what you have learned"], hidden = NoSection("collections"),
			desc = L["Collections starts with only the mounts, pets and other items you have not learned or got yet."] },
	}
	for _, row in ipairs(catalogue) do rows[#rows + 1] = row end
	return rows
end

local function WishlistOff()
	return LG:GetPage("wishlist") == nil or not LG:WishlistOn()
end

local function CopyLinks()
	E:ShowCopyBox(L["Loot Guide help"], L["The EldoUI page and the place to report problems. Copy (Ctrl+C) and open them in your browser."],
		REPO_URL .. "\n" .. ISSUES_URL)
end

-- A plain table (not a function): other config pages (Fonts, search) walk
-- every module's options while the game starts.
LG.options = {
	{ type = "header", label = L["Window"] },
	{ type = "select", key = "startPage", label = L["Open on"], values = StartValues, hidden = NoPages,
		desc = L["The page the window shows when you open it outside a dungeon. The gear holds a switch for each page and the Catalog's settings."],
		cog = StartCog() },
	{ type = "toggle", key = "autoOpen", label = L["Open the dungeon you are in"], hidden = NoInstancePage,
		desc = L["Inside a dungeon or raid, the window opens on that instance."] },
	{ type = "select", key = "density", label = L["Row size"], hidden = NoPages,
		values = { comfortable = L["Comfortable (20 px)"], compact = L["Compact (16 px)"] },
		desc = L["How tall each row in the Loot Guide lists is. Compact fits more on a page."] },
	-- The window's size comes from its corner grip, so there is no size row.
	{ type = "toggle", key = "transparent", label = L["See-through window"],
		desc = L["The window lets the game show through a little. How much: General > Panel opacity. Drag the window's corner grip to change its size."],
		cog = {
			{ type = "toggle", key = "sounds", label = L["Window sounds"],
				desc = L["Book sounds when the window opens, closes and turns a page."] },
			{ type = "execute", label = L["Open the Loot Guide"], func = function() LG:Open() end,
				desc = L["Same as /lg. Opens out of combat."] },
			{ type = "execute", label = L["Reset window position"], testSafe = true, func = function() LG:ResetWindow() end,
				desc = L["Puts the window back at the top of the screen at normal size."] },
		} },

	{ type = "header", label = L["Upgrades"] },
	{ type = "select", key = EngineKey("engine.rating"), label = L["Rate items by"], values = RaterValues, hidden = NoRating,
		desc = L["For this character: your stat weights (fast, the same as the Upgrades arrows), or the simulator (DPS against a target dummy, run when you press Sim)."],
		cog = {
			{ type = "select", key = "simSpeed", label = L["Simulator speed"],
				values = { smooth = L["Smooth (4 ms a frame)"], fast = L["Fast (8 ms a frame)"], turbo = L["Turbo (16 ms a frame)"] },
				desc = L["How much of each frame the simulator may use. Turbo finishes sooner but can lower your frame rate while it runs."] },
			{ type = "execute", label = L["Open the simulator"], func = function() LG:OpenSim() end,
				disabled = function() return LG:SimUnavailable() or false end,
				desc = L["Same as /eui sim. Loads the simulator (EldoUI_LootSim) out of combat."] },
		} },
	{ type = "toggle", key = "includeRaids", label = L["Suggest raids too"], hidden = function() return LG:GetPage("foryou") == nil end,
		desc = L["For You also counts raids when it picks the best instance and the next upgrades."],
		cog = {
			{ type = "range", key = "levelWindow", label = L["Level window"], min = 0, max = 10, step = 1,
				desc = L["Dungeons within this many levels of yours count as right for you now (tiles, the level bar and My level only)."] },
		} },

	{ type = "header", label = L["Tooltips"] },
	{ type = "select", key = "dropRates", label = L["Drop chances"],
		values = { both = L["Classic and seen"], classic = L["Classic data"], seen = L["Seen by you"], off = L["Off"] },
		desc = L["Classic: chances from Classic data; Forever may differ. Seen: what you looted yourself, with the number of kills (needs Mob and Loot Info)."],
		cog = DropCog() },

	{ type = "header", label = L["Loot rolls and item check"] },
	{ type = "toggle", key = "rollBox", label = L["Gain beside loot rolls"],
		desc = L["Shows how much the item would gain you beside each loot roll. Advice only: you always roll yourself."],
		cog = {
			{ type = "toggle", key = "suggest", label = L["Need, Greed or Pass label"],
				desc = L["Adds a Need, Greed or Pass word to that box. It is a label only and never rolls for you."] },
		} },
	{ type = "select", key = "check", label = L["Item check"],
		values = { ALT = L["Alt-click an item"], CTRLALT = L["Ctrl+Alt-click an item"], OFF = L["Off"] },
		desc = L["Opens a card that compares the item with what you wear, its source and your plans."] },
	{ type = "toggle", key = "wishAlert", label = L["Wishlist alerts"], hidden = WishlistOff,
		desc = L["Tells you when a wishlist item is in a loot window or a roll, or drops in the dungeon you enter. It never loots or rolls for you."],
		cog = {
			{ type = "media", mediaKind = "sound", none = true, key = "wishSound", label = L["Alert sound"],
				desc = L["The sound that plays with a wishlist alert."] },
			{ type = "select", key = "wishRoute", label = L["Show alerts as"],
				values = { auto = L["Toast, else loot toast, else chat"], lane = L["Toast (Alerts and Banners)"], banner = L["Alert card with a button"], chat = L["Chat line only"] },
				desc = L["Where the alert shows. Every alert also writes one chat line so you can read it later."] },
			{ type = "execute", label = L["Test alert"], testSafe = true, func = function() LG:TestWishAlert() end,
				desc = L["Shows a sample alert with your settings."] },
		} },

	{ type = "header", label = L["Maps"] },
	{ type = "toggle", key = "mapEntrances", label = L["Dungeon entrances on the world map"],
		desc = L["Pins at dungeon and raid entrances on the world and zone maps, with the level range and your upgrades inside. Where the game draws its own entrance pin, ours steps aside, so no entrance shows twice."],
		cog = {
			{ type = "toggle", key = "mapBosses", label = L["Boss markers on dungeon maps"],
				desc = L["Numbered boss markers from the loot data on the dungeon map window. They never show where you are."] },
		} },

	{ type = "header", label = L["Help"] },
	{ type = "description", label = "Loot Guide in EldoUI %s. %s opens the window, %s the simulator, %s lists every command.",
		labelFill = { tostring(E.version), "/lg", "/eui sim", "/lg help" } },
	{ type = "execute", label = L["Start tour"], func = function() LG:ResetTours() LG:StartTour() end,
		desc = L["Walks through every page of the Loot Guide again, and shows the small tours of the filter, dungeon map and simulator again too."] },
	{ type = "execute", label = L["Copy help links"], testSafe = true, func = CopyLinks,
		desc = L["The EldoUI project page and the address to report a wrong drop or a problem, ready to copy."] },
}

E:RegisterStyles("LootGuide", {
	{ key = "EldoUI", title = "EldoUI", desc = L["Comfortable rows, For You first, both kinds of drop chance, window sounds on."],
		settings = { density = "comfortable", startPage = "foryou", autoOpen = true, scale = 1, transparent = false,
			sounds = true, dropRates = "both", includeRaids = false, levelWindow = 3, minQuality = 2, wishAlert = true, wishRoute = "auto",
			rollBox = true, suggest = true, check = "ALT", mapEntrances = true, mapBosses = true, phaseBadges = true, simSpeed = "fast" } },
	{ key = "Compact", title = L["Compact"], desc = L["Dense rows and a smaller window that opens where you left it."],
		settings = { density = "compact", startPage = "last", scale = 0.9, transparent = false } },
	{ key = "Leveller", title = L["Leveler"], desc = L["For You first, dungeons and quests near your level, no raids; Classic drop chances only."],
		settings = { startPage = "foryou", autoOpen = true, density = "comfortable", dropRates = "classic", includeRaids = false, levelWindow = 4 } },
	{ key = "Raider", title = L["Raider"], desc = L["Journal first and the raid you are in, raids suggested too, epic loot and better."],
		settings = { startPage = "journal", autoOpen = true, dropRates = "both", includeRaids = true, minQuality = 4, rollBox = true, suggest = true,
			phaseBadges = true } },
	{ key = "Collector", title = L["Collector"], desc = L["Wishlist first, compact rows, every quality, wishlist alerts as alert cards."],
		settings = { startPage = "wishlist", density = "compact", dropRates = "both", minQuality = 0, wishAlert = true, wishRoute = "banner",
			collectHideLearned = true } },
	{ key = "Quiet", title = L["Quiet"], desc = L["No sounds, no wishlist alerts, no jumping to the dungeon you are in, a see-through window."],
		settings = { sounds = false, autoOpen = false, transparent = true, startPage = "last", wishAlert = false, suggest = false, simSpeed = "smooth" } },
	{ key = "Atlas", title = L["Atlas"], desc = L["Journal first and the dungeon you are in, at a larger size."],
		settings = { startPage = "journal", autoOpen = true, density = "comfortable", scale = 1.1, transparent = false } },
})
