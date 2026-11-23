-- EldoUI Finder: one search box for game panels, EldoUI and game
-- settings, mounts, toys, bag items, macros, places and EldoUI commands,
-- plus a small calculator ("= 12*35+4").
--
-- Results open things. A result that uses something (a mount, a toy, an
-- item, a macro) sits on a secure action button the player clicks or
-- presses Enter on: one press, one action, set out of combat only. In
-- combat the box shows only results that need no secure button.
--
-- Providers (modules and plugins add their own):
--   E:RegisterFinderProvider(kind, fn, opts)
--     kind  short key ("lootguide"); the result's kind label is opts.label
--     fn    function(query) -> list of entries. Static providers (the
--           default) are called once each time the box opens, with no
--           query, and EldoUI matches the text; opts.dynamic = true calls
--           fn(query) on every search (the entries may carry a score)
--     opts  label (kind label shown on the row), order (sort tie-break),
--           dynamic, option (false: no on/off row on the options page)
--   An entry: { id, text, sub, icon, keywords,
--               open = function() end,          -- a plain action, or
--               secure = { type = "item", item = "item:6948" }, -- attributes
--               second = { label, func },       -- Shift+Enter or right row button
--               combat = true }                 -- usable in combat (plain actions only)
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local M = E:NewModule("Finder", {
	title = "Finder",
	category = "Quality of Life",
	desc = "One search box for game panels, settings, mounts, toys, bag items, macros, places and EldoUI commands, with a small calculator. Using a mount, toy, item or macro is always your own click or key press.",
	frames = {
		"EldoUIFinderBox", "EldoUIFinderToggle", "EldoUIFinderSecure", "EldoUIFinderBindings",
		"EldoUI_FinderAnchor",
	},
	movers = { "EldoUI_Finder" },
	blizzard = {},
	savedKeys = { "profile.modules.Finder" },
	optionsPage = "module:Finder",
	presets = { "Compact", "Forever", "Large", "Minimal", "Spotlight", "TopBar" },
	reload = false,
	defaults = {
		key = "",               -- unbound until the player picks a key
		kinds = { panel = true, setting = true, mount = true, toy = true, item = true, macro = true, place = true, command = true },
		results = 8,
		recent = true,
		calculator = true,
		fuzzy = "normal",       -- off | normal | loose
		-- Look (style presets)
		width = 560,
		rowHeight = 28,
		fontSize = 16,
		icons = true,
		kindLabels = true,
		subtitles = true,
		dim = false,
		transparent = false,
		panelStyle = "theme",   -- theme | an art style key (Modern, Blizzard, Classic, Forever)
		-- Remembered
		recents = {},
		pinned = {},
	},
})
E.Finder = M

local MAX_RECENTS = 12

---------------------------------------------------------------------------
-- Providers
---------------------------------------------------------------------------
M.providers = {}
M.providerOrder = {}

function E:RegisterFinderProvider(kind, fn, opts)
	if type(kind) ~= "string" or kind == "" or type(fn) ~= "function" then return false end
	opts = opts or {}
	if not M.providers[kind] then M.providerOrder[#M.providerOrder + 1] = kind end
	M.providers[kind] = { kind = kind, fn = fn, label = opts.label or kind, order = opts.order or 50,
		dynamic = opts.dynamic and true or false, option = opts.option ~= false }
	if M.defaults.kinds[kind] == nil then M.defaults.kinds[kind] = true end
	if M.db and M.db.kinds[kind] == nil then M.db.kinds[kind] = true end
	M.index = nil
	return true
end

function M:KindOn(kind)
	local kinds = self.db and self.db.kinds
	return not kinds or kinds[kind] ~= false
end

function M:KindLabel(kind)
	local provider = self.providers[kind]
	return provider and L[provider.label] or kind
end

---------------------------------------------------------------------------
-- Matching and ranking
---------------------------------------------------------------------------
local function Fold(text)
	return E:FoldText(text)
end

-- A score for text against the query (both folded), or nil.
function M:Score(text, query, fuzzy)
	if text == "" or query == "" then return nil end
	if text == query then return 1000 end
	local at = text:find(query, 1, true)
	if at == 1 then return 800 - math.min(#text - #query, 100) end
	if at and text:sub(at - 1, at - 1) == " " then return 600 - math.min(at, 100) end
	if at then return 400 - math.min(at, 100) end
	if fuzzy == "off" then return nil end
	-- Letters in order with gaps; "normal" allows a gap of a few letters.
	local pos, gaps, last = 1, 0, 0
	for i = 1, #query do
		local char = query:sub(i, i)
		if char ~= " " then
			local found = text:find(char, pos, true)
			if not found then return nil end
			if last > 0 then gaps = gaps + (found - last - 1) end
			last, pos = found, found + 1
		end
	end
	if fuzzy ~= "loose" and gaps > #query * 2 then return nil end
	return math.max(1, 200 - gaps * 4)
end

local function RecentRank(db, id)
	for index, recent in ipairs(db.recents or {}) do
		if recent == id then return index end
	end
end

-- Static entries of every provider that is on, built once per opening.
function M:BuildIndex()
	local index = {}
	for _, kind in ipairs(self.providerOrder) do
		local provider = self.providers[kind]
		if not provider.dynamic and self:KindOn(kind) then
			local ok, list = pcall(provider.fn)
			if not ok then
				if E.errors and E.errors.Add then E.errors:Add("warning", ("EldoUI Finder: provider %s failed: %s"):format(kind, tostring(list))) end
			elseif type(list) == "table" then
				for _, entry in ipairs(list) do
					if type(entry) == "table" and type(entry.text) == "string" then
						entry.kind = kind
						entry.id = entry.id or (kind .. ":" .. entry.text)
						entry.folded = Fold(entry.text)
						entry.foldedKeys = entry.keywords and Fold(type(entry.keywords) == "table" and table.concat(entry.keywords, " ") or entry.keywords) or nil
						index[#index + 1] = entry
					end
				end
			end
		end
	end
	self.index = index
	return index
end

-- Can this entry be used right now? Secure ones never in combat.
function M:Usable(entry)
	if not InCombatLockdown() then return true end
	if entry.secure then return false end
	return entry.combat ~= false
end

-- Ranked results for a query (an empty query: pinned and recent ones).
function M:Search(text)
	local db = self.db
	local query = Fold(text or "")
	local index = self.index or self:BuildIndex()
	local results = {}
	local limit = math.max(3, math.min(20, tonumber(db.results) or 8))
	local function Add(entry, score)
		if not self:Usable(entry) then return end
		local pinned = db.pinned[entry.id] and 300 or 0
		local rank = db.recent and RecentRank(db, entry.id)
		local recent = rank and (150 - rank * 10) or 0
		entry.score = score + pinned + recent
		results[#results + 1] = entry
	end
	if query == "" then
		for _, entry in ipairs(index) do
			if db.pinned[entry.id] or (db.recent and RecentRank(db, entry.id)) then Add(entry, 0) end
		end
	else
		for _, entry in ipairs(index) do
			local score = self:Score(entry.folded, query, db.fuzzy)
			if not score and entry.foldedKeys then
				score = self:Score(entry.foldedKeys, query, db.fuzzy)
				score = score and math.floor(score * 0.8)
			end
			if score then Add(entry, score) end
		end
	end
	-- Dynamic providers (the calculator, slash commands, plugins).
	for _, kind in ipairs(self.providerOrder) do
		local provider = self.providers[kind]
		if provider.dynamic and self:KindOn(kind) then
			local ok, list = pcall(provider.fn, text or "")
			if ok and type(list) == "table" then
				for _, entry in ipairs(list) do
					if type(entry) == "table" and type(entry.text) == "string" then
						entry.kind = kind
						entry.id = entry.id or (kind .. ":" .. entry.text)
						local score = tonumber(entry.score)
						if not score then score = self:Score(Fold(entry.text), query, db.fuzzy) end
						if score then Add(entry, score) end
					end
				end
			end
		end
	end
	table.sort(results, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		local oa, ob = self.providers[a.kind].order, self.providers[b.kind].order
		if oa ~= ob then return oa < ob end
		return a.text < b.text
	end)
	-- One kind fills at most half the list while other kinds match too, so
	-- a word shared by many settings never hides the item or mount itself.
	local cap, kept, spare, perKind = math.ceil(limit / 2), {}, {}, {}
	for _, entry in ipairs(results) do
		local count = perKind[entry.kind] or 0
		if count < cap then
			kept[#kept + 1], perKind[entry.kind] = entry, count + 1
		else
			spare[#spare + 1] = entry
		end
	end
	for _, entry in ipairs(spare) do
		if #kept >= limit then break end
		kept[#kept + 1] = entry
	end
	for i = limit + 1, #kept do kept[i] = nil end
	return kept
end

function M:Remember(entry)
	local db = self.db
	if not (entry and entry.id) or entry.noRecent then return end
	local list = db.recents
	for i = #list, 1, -1 do
		if list[i] == entry.id then table.remove(list, i) end
	end
	table.insert(list, 1, entry.id)
	for i = MAX_RECENTS + 1, #list do list[i] = nil end
end

function M:TogglePin(entry)
	if not (entry and entry.id) then return end
	self.db.pinned[entry.id] = not self.db.pinned[entry.id] or nil
	return self.db.pinned[entry.id] == true
end

-- A plain (non-secure) action of an entry.
function M:Run(entry, second)
	if not entry then return false end
	local fn = second and entry.second and (entry.second.func or entry.second[2]) or (not second and entry.open)
	if type(fn) ~= "function" then return false end
	if not second then self:Remember(entry) end
	local ok, err = pcall(fn, entry)
	if not ok then geterrorhandler()(err) end
	return ok
end

---------------------------------------------------------------------------
-- Calculator: numbers, + - * / ^ ( ), unary minus. Its own parser; text
-- is never run as Lua.
---------------------------------------------------------------------------
local function Tokens(text)
	local list, pos = {}, 1
	text = text:gsub(",", ".")
	while pos <= #text do
		local char = text:sub(pos, pos)
		if char:match("%s") then
			pos = pos + 1
		elseif char:match("[%d%.]") then
			local number = text:match("^%d*%.?%d+", pos) or text:match("^%d+%.?", pos)
			if not number or not tonumber(number) then return nil end
			list[#list + 1] = { "n", tonumber(number) }
			pos = pos + #number
		elseif text:sub(pos, pos + 1) == "\195\151" then -- × (two bytes: before the one-byte signs)
			list[#list + 1] = { "*" }
			pos = pos + 2
		elseif char:match("[%+%-%*/%^%(%)x]") then
			if char == "x" then char = "*" end
			list[#list + 1] = { char }
			pos = pos + 1
		else
			return nil
		end
	end
	return list
end

function M:Calculate(text)
	if type(text) ~= "string" then return nil end
	local tokens = Tokens(text)
	if not tokens or #tokens == 0 then return nil end
	local pos = 1
	local Expr
	local function Peek() return tokens[pos] and tokens[pos][1] end
	local function Primary()
		local token = tokens[pos]
		if not token then return nil end
		if token[1] == "n" then
			pos = pos + 1
			return token[2]
		elseif token[1] == "(" then
			pos = pos + 1
			local value = Expr()
			if value == nil or Peek() ~= ")" then return nil end
			pos = pos + 1
			return value
		elseif token[1] == "-" then
			pos = pos + 1
			local value = Primary()
			return value and -value
		elseif token[1] == "+" then
			pos = pos + 1
			return Primary()
		end
	end
	local function Power()
		local base = Primary()
		if base == nil then return nil end
		if Peek() == "^" then
			pos = pos + 1
			local exponent = Power()
			if exponent == nil then return nil end
			return base ^ exponent
		end
		return base
	end
	local function Term()
		local value = Power()
		while value ~= nil and (Peek() == "*" or Peek() == "/") do
			local op = Peek()
			pos = pos + 1
			local right = Power()
			if right == nil then return nil end
			if op == "*" then value = value * right else value = value / right end
		end
		return value
	end
	function Expr()
		local value = Term()
		while value ~= nil and (Peek() == "+" or Peek() == "-") do
			local op = Peek()
			pos = pos + 1
			local right = Term()
			if right == nil then return nil end
			if op == "+" then value = value + right else value = value - right end
		end
		return value
	end
	local value = Expr()
	if value == nil or pos <= #tokens then return nil end
	if value ~= value or value == math.huge or value == -math.huge then return nil end
	return value
end

function M:FormatNumber(value)
	if math.floor(value) == value and math.abs(value) < 1e15 then return ("%d"):format(value) end
	return (("%.10g"):format(value))
end

---------------------------------------------------------------------------
-- Built-in providers
---------------------------------------------------------------------------
local function Global(name)
	return rawget(_G, name)
end

-- Game panels: the same calls as the game's own key bindings
-- (Bindings_Camelot.xml). `fn` names a global; `util` a PlayerSpellsUtil
-- function; `map` the world map; `bags` the bags. combat = false: the panel
-- is protected in combat.
local PANELS = {
	{ text = "Character", fn = "ToggleCharacter", arg = "PaperDollFrame", icon = "Interface\\Icons\\INV_Chest_Chain" }, -- no-L (translated where shown)
	{ text = "Reputation", fn = "ToggleCharacter", arg = "ReputationFrame", icon = "Interface\\Icons\\INV_BannerPVP_02" }, -- no-L (translated where shown)
	{ text = "Spellbook", util = "ToggleSpellBookFrame", icon = "Interface\\Icons\\INV_Misc_Book_09", combat = false }, -- no-L (translated where shown)
	{ text = "Talents", util = "ToggleClassTalentOrSpecFrame", icon = "Interface\\Icons\\INV_Misc_Book_11", combat = false }, -- no-L (translated where shown)
	{ text = "Professions", fn = "ToggleProfessionsBook", icon = "Interface\\Icons\\Trade_BlackSmithing" }, -- no-L (translated where shown)
	{ text = "Quest log", fn = "ToggleQuestLog", icon = "Interface\\Icons\\INV_Misc_Note_01" }, -- no-L (translated where shown)
	{ text = "World map", map = true, icon = "Interface\\Icons\\INV_Misc_Map_01", combat = false }, -- no-L (translated where shown)
	{ text = "Bags", bags = true, icon = "Interface\\Icons\\INV_Box_02" }, -- no-L (translated where shown)
	{ text = "Friends", fn = "ToggleFriendsFrame", icon = "Interface\\Icons\\INV_Letter_15" }, -- no-L (translated where shown)
	{ text = "Guild", fn = "ToggleGuildFrame", icon = "Interface\\Icons\\INV_BannerPVP_01" }, -- no-L (translated where shown)
	{ text = "Who", fn = "LFGVanilla_ToggleFrame", argGlobal = "LFG_TAB_WHO", icon = "Interface\\Icons\\INV_Misc_Note_02" }, -- no-L (translated where shown)
	{ text = "Group finder", fn = "LFGVanilla_ToggleFrame", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", keywords = "lfg looking for group" }, -- no-L (translated where shown)
	{ text = "Raid", fn = "ToggleRaidFrame", icon = "Interface\\Icons\\Ability_Warrior_Cleave" }, -- no-L (translated where shown)
	{ text = "Chat channels", fn = "ToggleChannelFrame", icon = "Interface\\Icons\\INV_Letter_15" }, -- no-L (translated where shown)
	{ text = "Collections", fn = "ToggleCollectionsJournal", icon = "Interface\\Icons\\Ability_Mount_RidingHorse" }, -- no-L (translated where shown)
	{ text = "Mounts", fn = "ToggleCollectionsJournal", argGlobal = "COLLECTIONS_JOURNAL_TAB_INDEX_MOUNTS", icon = "Interface\\Icons\\Ability_Mount_Gryphon_01" }, -- no-L (translated where shown)
	{ text = "Toy box", fn = "ToggleCollectionsJournal", argGlobal = "COLLECTIONS_JOURNAL_TAB_INDEX_TOYS", icon = "Interface\\Icons\\INV_Misc_Key_03" }, -- no-L (translated where shown)
	{ text = "Achievements", fn = "ToggleAchievementFrame", icon = "Interface\\Icons\\INV_Misc_Coin_01" }, -- no-L (translated where shown)
	{ text = "Calendar", fn = "ToggleCalendar", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01" }, -- no-L (translated where shown)
	{ text = "Clock and stopwatch", fn = "ToggleTimeManager", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01" }, -- no-L (translated where shown)
	{ text = "Macros", fn = "ShowMacroFrame", icon = "Interface\\Icons\\INV_Misc_Note_02", combat = false }, -- no-L (translated where shown)
	{ text = "Battleground map", fn = "ToggleBattlefieldMap", icon = "Interface\\Icons\\INV_Misc_Map_01" }, -- no-L (translated where shown)
	{ text = "Help", fn = "ToggleHelpFrame", icon = "Interface\\Icons\\INV_Misc_QuestionMark" }, -- no-L (translated where shown)
}
M.PANELS = PANELS

local function PanelCall(panel)
	-- The world map opens through the game's own request (E:OpenWorldMapAt).
	if panel.map then
		return C_Map and type(C_Map.OpenWorldMap) == "function" and function() E:OpenWorldMapAt() end or nil
	end
	-- The bags through the Bags module, which keeps the game's bag code out
	-- of EldoUI's code while its bag window replaces the game's and uses
	-- the game's toggle otherwise (review/fehler.md F24).
	if panel.bags then
		local bags = E.modules.Bags
		return bags and type(bags.ToggleBags) == "function" and function() bags:ToggleBags() end or nil
	end
	if panel.util then
		local util = Global("PlayerSpellsUtil")
		return util and type(util[panel.util]) == "function" and function() util[panel.util]() end or nil
	end
	local fn = Global(panel.fn)
	if type(fn) ~= "function" then return nil end
	local arg = panel.arg
	if panel.argGlobal then
		arg = Global(panel.argGlobal)
		if arg == nil then return nil end
	end
	return function() fn(arg) end
end

-- The config window opens only from /eui (design decision): a settings
-- result puts the /eui command in the chat box, and the player's Enter opens it.
local function SlashInChat(text)
	local util = rawget(_G, "ChatFrameUtil")
	local open = util and util.OpenChat or rawget(_G, "ChatFrame_OpenChat")
	if type(open) == "function" then open(text) end
end

E:RegisterFinderProvider("panel", function()
	local list = {}
	for _, panel in ipairs(PANELS) do
		local call = PanelCall(panel)
		if call then
			list[#list + 1] = { id = "panel:" .. panel.text, text = L[panel.text], icon = panel.icon, keywords = panel.keywords,
				combat = panel.combat ~= false, open = call }
		end
	end
	list[#list + 1] = { id = "panel:EldoUI", text = L["EldoUI options"], icon = "Interface\\Icons\\Trade_Engineering", keywords = "eui config settings",
		open = function() SlashInChat("/eui") end }
	return list
end, { label = "Panel", order = 10 })

-- Settings: EldoUI's own option rows (each opens the options search on it)
-- and module pages, plus the game settings browser.
local SETTING_TYPES = { toggle = true, range = true, select = true, color = true, input = true, media = true, execute = true }

E:RegisterFinderProvider("setting", function()
	local list = {}
	for name, module in E:IterateModules() do
		local title = L[module.title]
		-- Earlier page names (aliases) find the page too.
		local keywords = module.desc
		for _, alias in ipairs(module.aliases or {}) do keywords = keywords .. " " .. alias .. " " .. L[alias] end
		list[#list + 1] = { id = "page:" .. name, text = title, sub = L["EldoUI settings page"], icon = "Interface\\Icons\\Trade_Engineering",
			keywords = keywords, open = function() SlashInChat("/eui " .. name:lower()) end }
		local options = type(module.options) == "table" and module.options or nil
		if options then
			for _, option in ipairs(options) do
				if type(option) == "table" and SETTING_TYPES[option.type] and type(option.label) == "string" then
					local label = L[option.label]
					list[#list + 1] = { id = "setting:" .. name .. ":" .. option.label, text = label, sub = title, icon = "Interface\\Icons\\Trade_Engineering",
						open = function() SlashInChat("/eui search " .. label) end }
				end
			end
		end
	end
	local tweaks = E.modules.QoL
	if tweaks and tweaks.ShowCVarBrowser then
		list[#list + 1] = { id = "setting:cvars", text = L["Game settings browser"], sub = L["Every setting the game keeps"], icon = "Interface\\Icons\\Trade_Engineering",
			keywords = "cvar console", combat = false, open = function() tweaks:ShowCVarBrowser() end }
	end
	return list
end, { label = "Setting", order = 20 })

-- Mounts the player has collected: the secure button casts the mount.
E:RegisterFinderProvider("mount", function()
	local journal = C_MountJournal
	if not (journal and journal.GetMountIDs and journal.GetMountInfoByID) then return {} end
	local list = {}
	for _, mountID in ipairs(journal.GetMountIDs() or {}) do
		local name, spellID, icon, _, _, _, _, _, _, hideOnChar, collected = journal.GetMountInfoByID(mountID)
		if collected and not hideOnChar and type(name) == "string" and spellID then
			list[#list + 1] = { id = "mount:" .. mountID, text = name, icon = icon, secure = { type = "spell", spell = spellID } }
		end
	end
	return list
end, { label = "Mount", order = 30 })

-- Toys the toy box lists (its own filters apply).
E:RegisterFinderProvider("toy", function()
	local box = C_ToyBox
	if not (box and box.GetNumFilteredToys and box.GetToyFromIndex and box.GetToyInfo) then return {} end
	local list = {}
	for index = 1, box.GetNumFilteredToys() or 0 do
		local itemID = box.GetToyFromIndex(index)
		if itemID and itemID > 0 and (not PlayerHasToy or PlayerHasToy(itemID)) then
			local _, name, icon = box.GetToyInfo(itemID)
			if type(name) == "string" and name ~= "" then
				list[#list + 1] = { id = "toy:" .. itemID, text = name, icon = icon, secure = { type = "toy", toy = itemID } }
			end
		end
	end
	return list
end, { label = "Toy", order = 31 })

-- Bag items with a use effect.
E:RegisterFinderProvider("item", function()
	local list, seen = {}, {}
	local bags = E.BagCache
	for _, bag in ipairs(bags:BagIDs({ equipped = true })) do
		for slot = 1, bags:NumSlots(bag) do
			local info = bags:Info(bag, slot)
			local itemID = type(info) == "table" and info.itemID
			if itemID and not seen[itemID] and C_Item and C_Item.GetItemSpell and C_Item.GetItemSpell(itemID) then
				seen[itemID] = true
				local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
				if type(name) ~= "string" and type(info.hyperlink) == "string" then name = info.hyperlink:match("%[(.-)%]") end
				if type(name) == "string" and name ~= "" then
					local count = info.stackCount and info.stackCount > 1 and ("x" .. info.stackCount) or nil
					list[#list + 1] = { id = "item:" .. itemID, text = name, sub = count, icon = info.iconFileID,
						secure = { type = "item", item = "item:" .. itemID } }
				end
			end
		end
	end
	return list
end, { label = "Item", order = 32 })

-- Macros: account and character ones.
E:RegisterFinderProvider("macro", function()
	if not (GetNumMacros and GetMacroInfo) then return {} end
	local list = {}
	local account, character = GetNumMacros()
	local first = Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_ACCOUNT_MACROS or Global("MAX_ACCOUNT_MACROS") or 120
	local function Add(index)
		local name, icon = GetMacroInfo(index)
		if type(name) == "string" and name ~= "" then
			list[#list + 1] = { id = "macro:" .. name, text = name, sub = index > first and L["Character macro"] or L["Account macro"],
				icon = icon, secure = { type = "macro", macro = index } }
		end
	end
	for index = 1, account or 0 do Add(index) end
	for index = first + 1, first + (character or 0) do Add(index) end
	return list
end, { label = "Macro", order = 33 })

-- Places: the zones EldoUI knows (names from the game) and your waypoints.
function M:OpenMap(mapID)
	return E:OpenWorldMapAt(mapID)
end

E:RegisterFinderProvider("place", function()
	local list = {}
	local zones = E.zoneData and E.zoneData.zones
	if zones and C_Map and C_Map.GetMapInfo then
		for mapID in pairs(zones) do
			local info = C_Map.GetMapInfo(mapID)
			local name = type(info) == "table" and info.name
			if type(name) == "string" and not E:IsSecret(name) and name ~= "" then
				list[#list + 1] = { id = "place:" .. mapID, text = name, sub = L["Zone"], icon = "Interface\\Icons\\INV_Misc_Map_01", combat = false,
					open = function() M:OpenMap(mapID) end }
			end
		end
	end
	local waypoints = E.Waypoints
	if waypoints and waypoints.Iterate and waypoints.SetArrow then
		for uid, point in waypoints:Iterate() do
			if type(point) == "table" and type(point.title) == "string" and point.mapID then
				list[#list + 1] = { id = "waypoint:" .. tostring(uid), text = point.title, sub = L["Waypoint"], icon = "Interface\\Icons\\INV_Misc_Map02", combat = false,
					open = function() M:OpenMap(point.mapID) end,
					second = { label = L["Set waypoint"], func = function() waypoints:SetArrow(uid) end } }
			end
		end
	end
	return list
end, { label = "Place", order = 40 })

-- EldoUI commands: module pages switch and a typed "/eui ..." line.
E:RegisterFinderProvider("command", function(text)
	local list = {}
	local line = strtrim(text or "")
	local rest = line:match("^/eui%s+(.+)$") or line:match("^/eldoui%s+(.+)$")
	if rest and SlashCmdList and SlashCmdList.ELDOUI then
		list[#list + 1] = { id = "command:typed", text = "/eui " .. rest, sub = L["Run this EldoUI command"], icon = "Interface\\Icons\\Trade_Engineering", score = 2000, -- no-L (slash command)
			noRecent = true, open = function() SlashCmdList.ELDOUI(rest) end }
	end
	local query = Fold(line)
	if query ~= "" then
		for name, module in E:IterateModules() do
			local match = E.SetModuleEnabled and M:Score(Fold(L[module.title]), query, "off")
			if match then
				local on = module.db and module.db.enabled
				list[#list + 1] = { id = "toggle:" .. name, text = (on and L["Turn off %s"] or L["Turn on %s"]):format(L[module.title]),
					sub = L["EldoUI module"], icon = "Interface\\Icons\\Trade_Engineering", score = match - 100, noRecent = true, combat = false,
					open = function() E:SetModuleEnabled(name, not module.db.enabled) end }
			end
		end
	end
	return list
end, { label = "EldoUI command", order = 50, dynamic = true })

E:RegisterFinderProvider("calc", function(text)
	if not M.db.calculator then return {} end
	local expr = strtrim(text or ""):match("^=%s*(.+)$")
	if not expr then
		-- Plain sums too: "12*35+4" (at least one operator, only math characters).
		local plain = strtrim(text or "")
		if plain:match("^[%d%.%s%+%-%*/%^%(%),x]+$") and plain:match("%d%s*[%+%-%*/%^x]") then expr = plain end
	end
	local value = expr and M:Calculate(expr)
	if not value then return {} end
	local shown = M:FormatNumber(value)
	return { { id = "calc", text = "= " .. shown, sub = L["Click to copy"], icon = "Interface\\Icons\\INV_Misc_Coin_01", score = 3000, noRecent = true,
		open = function() E:ShowCopyBox(L["Calculator"], L["Press Ctrl+C to copy."], shown) end } }
end, { label = "Calculator", order = 0, dynamic = true, option = false })
