-- EldoUI Bags: every bag (profession bags and the keyring included) in one
-- window in the EldoUI look, a bank window in the same style, and an
-- account-wide inventory cache.
--
--   * Windows: flat slots with game-colored quality borders, item level on
--     gear, bind text, junk marks, new-item glow, search with filters,
--     Blizzard's own sort, free slots, ammo, gold and tracked currencies.
--     Three views: one grid, categories (sections by item type, plus your
--     own search-based categories) or bag by bag. A bag bar inside the
--     window shows, hides and swaps single bags and bank tabs.
--   * Window extras: bags open and close with the bank, vendor,
--     mailbox, auction house, trade, guild bank and profession windows (one
--     setting each), item cooldown swipes on the slots, stack count / item
--     level / bind text sizes, outlines and corners, the window layer, a
--     search box that empties on close, and windows that grow away from the
--     screen edge their mover is on.
--   * Cache: bags, bank, equipped gear, mailbox, gold and currencies of every
--     character on the account, plus the guild bank tabs you open, in
--     EldoUIDB.inventory[charKey] and EldoUIDB.guildBanks[guildKey].
--     Rebuilt (throttled) on the game's own update events.
--   * Offline view: a character dropdown in both windows shows any cached
--     character's bags or bank (or a cached guild bank), read-only.
--   * Tooltips: an "Inventory" block listing every character's count per
--     location (Bags / Bank / Mail / Equipped / Auctions / Guild bank), and a
--     account-wide vendor value. Both go through E:RegisterTooltipSection
--     and E:RegisterTooltipValue, which show with the Tooltip module on or off.
--   * Protection: items one of your quests or recipes needs get a
--     small lock in the corner (E:IsItemProtected, Core/ItemProtect.lua).
--   * "Move these" (Transfers tab, off by default): with the bank,
--     mail, trade or a vendor open, a button beside the search box moves
--     one batch (at most 12) of the items your search shows there. One
--     click, one batch, out of combat; protected items always stay, and a
--     vendor never gets your "never sell" items.
--   * Search: plain words match the name; q:rare, q>=3, t:cloth, ilvl>50,
--     bop, boe, bound, junk, quest, new, gear, -word or !word (not), a|b
--     (or), & (and), all in SEARCH_WORDS. "All" searches every character.
--     /eui find <text>. Saved searches and the Search help window are in
--     Modules/Bags/Searches.lua.
--
-- What EldoUI may do with Blizzard's bags and bank is decided per element on
-- the Blizzard UI page (Core/Blizzard.lua): "bags-containers" and "bank".
--   replace  EldoUI's windows; Blizzard's frames keep running on a hidden
--            parent, so the game's own open/close logic (B, bag buttons,
--            vendor, mail) still decides when bags are open.
--   hide     Blizzard's frames stay hidden (without replace: no window).
--   skin / move / improve
--            Blizzard's own windows in the EldoUI look, on EldoUI's movers,
--            with item levels and junk marks (Modules/Bags/Blizzard.lua).
-- With an element's master switch off, nothing here touches Blizzard's frame.
--
-- Live item buttons use Blizzard's ContainerFrameItemButtonTemplate, so
-- clicking, using and dragging items works exactly like in the default bags.
-- Offline slots only show a tooltip and accept modified clicks.
--
-- Presentation only: everything shown is data the game gives the player.
-- Nothing is used, sold, sorted or moved without the player's click; sorting
-- is only the game's own sort, on a click of the broom (a design rule).
-- Written from scratch for EldoUI; no code or media from other addons.
local _, E = ...
local L = E.L

local M = E:NewModule("Bags", {
	title = "Bags",
	category = "Items & Economy",
	desc = "All bags and the bank in EldoUI windows with categories and a bag bar, item counts across your characters, search with filters, offline viewing and a Blizzard skin mode.",
	conflicts = { "Bagnon", "AdiBags", "BetterBags", "ArkInventory", "Baganator", "Combuctor", "ElvUI" },
	frames = {
		"EldoUI_Bags", "EldoUI_Bank", "EldoUI_BagsAnchor", "EldoUI_BankAnchor", "EldoUI_GuildBankAnchor",
	},
	movers = { "EldoUI_BagsAnchor", "EldoUI_BankAnchor", "EldoUI_GuildBank" },
	blizzard = { "bags-containers", "bank" },
	savedKeys = { "profile.modules.Bags", "private.bagSections" },
	optionsPage = "module:Bags",
	presets = { "Classic", "Clean", "Collector", "Compact", "Roomy", "Sorted", "Standard" },
	defaults = {
		replaceBlizzard = true, -- v0.5.0 setting; the Blizzard UI switches decide now
		-- Mirrors of the Blizzard UI switches, so the mode can be picked here too.
		bagMode = "blizzard",
		bagModeSynced = "blizzard",
		bankMode = "blizzard",
		bankModeSynced = "blizzard",
		guildBank = "skin",       -- blizzard / skin (needs the bank element's Skin switch) / eldoui (GuildBank.lua)
		-- Window layout
		view = "single",          -- single / categories / bags
		bankView = "single",
		columns = 12,
		bankColumns = 14,
		size = 38,
		spacing = 4,
		scale = 1,
		packSections = true,      -- small sections share a row
		compactEmpty = true,      -- categories view: one slot per bag type for free space
		groupItems = false,       -- categories view: stacks of one item as one slot (Modules/Bags/Categories.lua)
		groupPartial = false,     -- only full stacks group
		groupApart = true,        -- every stack apart at a vendor, the Send Mail tab, the bank or a trade
		savedSearches = {},       -- { { name, text } }, the Searches button (Modules/Bags/Searches.lua)
		reverse = false,          -- one-grid view fills from the bottom right
		bagBar = false,
		currencies = true,
		gold = true,
		footerSlots = "free",
		lowestValueMark = true,
		keyring = true,
		reagentSection = true,
		accountBank = true,
		hiddenBags = {},          -- [bagID] = true: left out of the windows
		strata = "HIGH",          -- frame strata of both windows
		clearSearch = true,       -- empty the search box when a window closes
		growFromMover = false,    -- windows grow away from the screen edge their mover is on
		-- Open and close the bags together with other windows. The
		-- defaults match the game: it opens bags at the bank, a vendor, the
		-- mailbox and the auction house, and closes what it opened.
		autoOpen = { bank = true, merchant = true, mail = true, auction = true, trade = false, guildbank = false, professions = false },
		autoClose = { bank = true, merchant = true, mail = true, auction = true, trade = true, guildbank = true, professions = true, combat = false },
		-- Item cooldowns on the slots (the game's own swipe and countdown)
		cooldowns = true,
		cooldownText = "eldoui",  -- eldoui / blizzard / off
		-- Text on the slots
		text = {
			countSize = 13, countOutline = "DEFAULT", countPoint = "BOTTOMRIGHT", countX = -2, countY = 2,
			levelSize = 12, levelOutline = "DEFAULT", levelPoint = "TOPLEFT", levelX = 2, levelY = -2,
			levelColor = "quality",  -- quality / custom
			levelCustom = { 1, 1, 1 },
			bindSize = 10,
		},
		-- Slots
		itemLevel = true,
		itemLevelMin = 1,
		boundText = true,
		tradeTime = true,
		junkStyle = "both",       -- coin / dim / both / off
		bagTint = true,           -- tint slots of profession bags
		qualityBorder = true,
		minQuality = 2,           -- lowest quality that colors the border
		questBorder = true,
		newGlow = true,
		knownTint = true,         -- green icon on recipes, mounts, pets and toys you already have
		markUnusable = true,      -- red icon on items this character can't use (Modules/Bags/Marks.lua)
		markPetFood = true,       -- food the current Hunter pet can eat
		markSets = true,          -- a mark on items in an equipment set
		markFade = true,          -- fade what an open vendor, mailbox, auction house or socket window can't take
		flashSame = true,         -- Alt-click flashes every slot with the same item
		protectItems = true,      -- lock mark on items a quest or recipe of yours needs
		moveThese = false,        -- "Move these" acts for you on a click, so off until chosen
		-- Sorting
		sortButton = true,
		sortDirection = "game",   -- game / ltr / rtl
		insertDirection = "game",
		-- Bag bar buttons of the action bar
		bagButtonFree = true,     -- free slots written on profession bag buttons
		ammoWarn = true,
		ammoWarnAll = false,    -- also warriors and rogues with a bow, gun or crossbow
		ammoSound = "kit:RAID_WARNING", -- media id with the low ammo warning, "none" for silence
		ammoThreshold = 200,
		-- Data
		altChars = true,
		moneyFormat = "general",  -- general (Fonts and text > Money) / icons / letters / short
		categories = {
			new = true, equipment = true, consumable = true, quest = true, tradegoods = true,
			recipe = true, ammo = true, container = true, keys = true, junk = true,
		},
		custom = {                -- the three search slots of older versions, kept for them
			{ name = "", query = "" },
			{ name = "", query = "" },
			{ name = "", query = "" },
		},
		categoryList = {},        -- your own categories (Modules/Bags/Categories.lua)
		categoryOrder = {},       -- the order of every section in the Categories view
		customMoved = false,      -- the three old slots became own categories
		-- Blizzard's own windows (skin / move / improve switches)
		blizzard = {
			scale = 1,
			bankScale = 1,        -- bank and guild bank with Move on
			combined = "game",    -- game / combined / separate (CVar combinedBags)
		},
		tooltip = {
			enabled = true,
			modifier = "ALWAYS",    -- ALWAYS or SHIFT
			includeCurrent = true,
			scope = "FACTION",      -- FACTION (same realm and faction), REALM, ALL
			onlyWithItem = true,
			minCount = 1,           -- hide the block below this account total
			maxChars = 8,
			icons = true,
			breakdown = true,       -- per location, or totals only
			vendor = true,
			currency = true,
			guild = true,
		},
		forget = "",
	},
})

local BAGS_ID, BANK_ID = "bags-containers", "bank"

local hider = CreateFrame("Frame")
hider:Hide()

local bankOpen = false
local windows = {}          -- kind ("bags" / "bank") -> window frame
M.windows = windows

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local LOCATIONS = { "bags", "bank", "mail", "equip" }
local LOCATION_LABEL = E:TranslateValues({ bags = E.Key("Bags"), bank = E.Key("Bank"), mail = E.Key("Mail"), equip = E.Key("Equipped"), auction = E.Key("Auctions"), guild = E.Key("Guild bank") })

local KEYRING = Enum.BagIndex and Enum.BagIndex.Keyring          -- -1 on Forever
local REAGENT = Enum.BagIndex and Enum.BagIndex.ReagentBag       -- 5
local CHAR_TABS = Enum.BagIndex and Enum.BagIndex.Characterbanktab  -- bags put into bank slots
local BANK_CHARACTER = Enum.BankType and Enum.BankType.Character
local BANK_ACCOUNT = Enum.BankType and Enum.BankType.Account
local ITEM_CLASS = Enum.ItemClass or {}
local QUALITY = Enum.ItemQuality or { Poor = 0, Common = 1, Uncommon = 2 }

-- Money in the Money style (Fonts and text page), or the bags' own choice.
local function Money(copper)
	return E:FormatMoney(copper, M.db and M.db.moneyFormat)
end
M.Money = Money
M.LOW_SPACE = 5

local Secret = E.Secret

local function Grey(text)
	return E:TextHex("secondary") .. text .. "|r"
end

local function AccentHex()
	local r, g, b = unpack(E.media.accentText)
	return ("ff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

-- "item:1234:..." without trailing colons, from a full hyperlink.
local function ShortItem(link)
	if type(link) ~= "string" then return end
	local short = link:match("|H(item:[^|]+)|h") or link:match("^(item:[%-%d:]+)")
	if not short then return end
	return (short:gsub(":+$", ""))
end

local function ItemIDOf(short)
	return short and tonumber(short:match("^item:(%d+)"))
end

local function Encode(short, count)
	if count and count > 1 then return short .. ";" .. count end
	return short
end

local function Decode(value)
	if type(value) ~= "string" then return end
	local short, count = value:match("^(.-);(%d+)$")
	if short then return short, tonumber(count) end
	return value, 1
end

local function ClassIcon(class, size)
	local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
	if not coords then return "" end
	return ("|TInterface\\TargetingFrame\\UI-Classes-Circles:%d:%d:0:0:256:256:%d:%d:%d:%d|t "):format(
		size or 14, size or 14, coords[1] * 256, coords[2] * 256, coords[3] * 256, coords[4] * 256)
end

local function ClassName(char)
	local color = E:ClassColorObject(char.class)
	local name = char.name or "?"
	if color then return color:WrapTextInColorCode(name) end
	return name
end

local function Age(timestamp)
	if not timestamp then return "" end
	local seconds = time() - timestamp
	if seconds < 3600 then return L["now"] end
	if seconds < 86400 then return L["%dh"]:format(seconds / 3600) end
	return L["%dd"]:format(seconds / 86400)
end

local function ClassOf(record)
	if record.classID == nil then
		local key = record.id or record.short
		record.classID = key and select(6, C_Item.GetItemInfoInstant(key)) or false
	end
	return record.classID or nil
end

-- Toolbar buttons from the shared kit (E.UIKit). A text button is a kit
-- button; an icon button shows the game icon as a toolbar glyph
-- (desaturated, gray, the accent on hover). tipTitle and tipText make the
-- tooltip; tipText may be a function(tooltip) that fills it.
local function ToolButton(parent, width, height, label, icon, tipTitle, tipText)
	local Kit = E.UIKit
	local button
	if icon then
		button = Kit.IconButton(parent, height, icon, nil, tipTitle, tipText, nil, { mono = true })
	else
		button = Kit.Button(parent, label or "", { width = width, height = height, tipTitle = tipTitle, tip = tipText })
	end
	return button
end

-- A rail button that is on (All characters) shows its accent mark.
function M.SetRailActive(button, active)
	if not button then return end
	button.active = active and true or false
	if button.activeMark then button.activeMark:SetShown(button.active) end
end

---------------------------------------------------------------------------
-- Bag lists
---------------------------------------------------------------------------
local function NumSlots(bag)
	if bag == nil then return 0 end
	local slots = E.PlainCall(C_Container.GetContainerNumSlots, bag)
	return type(slots) == "number" and slots >= 0 and slots < math.huge and slots % 1 == 0 and slots or 0
end

-- Player bags in display order. `all` adds the keyring even when the
-- window hides it (the cache always keeps keys).
local function BagIDs(all)
	local ids = {}
	for bag = 0, NUM_BAG_SLOTS do ids[#ids + 1] = bag end
	if REAGENT and NumSlots(REAGENT) > 0 then ids[#ids + 1] = REAGENT end
	if KEYRING and (all or (M.db and M.db.keyring)) and NumSlots(KEYRING) > 0 then ids[#ids + 1] = KEYRING end
	return ids
end
M.BagIDs = BagIDs

local function TabIDs(bankType)
	local ids = {}
	if not (C_Bank and C_Bank.FetchPurchasedBankTabData and bankType) then return ids end
	if C_Bank.CanViewBank and not C_Bank.CanViewBank(bankType) then return ids end
	local ok, tabs = pcall(C_Bank.FetchPurchasedBankTabData, bankType)
	if ok and type(tabs) == "table" then
		for _, tab in ipairs(tabs) do ids[#ids + 1] = tab.ID end
	end
	return ids
end

local function AccountTabsShown()
	return BANK_ACCOUNT and M.db and M.db.accountBank and #TabIDs(BANK_ACCOUNT) > 0
end
M.AccountTabsShown = AccountTabsShown

-- True while the game offers no account bank (WoW: Forever has none in play
-- yet): its option stays out of the page and comes back by itself once the
-- game lists one. The saved choice is kept.
local function NoAccountBank()
	if not (BANK_ACCOUNT and C_Bank and C_Bank.FetchViewableBankTypes) then return true end
	local ok, types = pcall(C_Bank.FetchViewableBankTypes)
	if not ok or type(types) ~= "table" then return true end
	for _, bankType in ipairs(types) do
		if bankType == BANK_ACCOUNT then return false end
	end
	return true
end
M.NoAccountBank = NoAccountBank

-- True when the game says it has no guild bank (C_GuildBank.IsGuildBankEnabled
-- false). A client without the call, or a secret answer, counts as having
-- one, so nothing is hidden on a guess.
function E:NoGuildBank()
	local api = C_GuildBank
	if not (api and api.IsGuildBankEnabled) then return false end
	local ok, enabled = pcall(api.IsGuildBankEnabled)
	if not ok or E.Secret(enabled) then return false end
	return enabled == false
end
local function NoGuildBank() return E:NoGuildBank() end

-- True while the character stands at the bank (BankActions.lua).
function M:BankIsOpen()
	return bankOpen
end

-- Bank containers: the character bank tabs (the modern bank Forever uses),
-- the warband tabs when that bank can be viewed, or the old bank container
-- plus bank bags while the character tabs cannot be read (the bank is
-- closed, or no tab is bought).
local function BankBagIDs(characterOnly)
	local ids = TabIDs(BANK_CHARACTER)
	if #ids > 0 then
		if not characterOnly and AccountTabsShown() then
			for _, id in ipairs(TabIDs(BANK_ACCOUNT)) do ids[#ids + 1] = id end
		end
		return ids
	end
	local bank = (Enum.BagIndex and Enum.BagIndex.Bank) or rawget(_G, "BANK_CONTAINER")
	if bank then
		ids[1] = bank
		local first = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS) + 1
		for bag = first, first + (NUM_BANKBAGSLOTS or 0) - 1 do ids[#ids + 1] = bag end
	end
	return ids
end

local accountTab = {}
local function IsAccountTab(bag)
	if not BANK_ACCOUNT then return false end
	if accountTab[bag] == nil then
		local first = Enum.BagIndex.AccountBankTab_1
		accountTab[bag] = first and bag >= first and bag < first + 9 or false
	end
	return accountTab[bag]
end

-- A character bank tab or a warband bank page.
local function IsBankTab(bag)
	if IsAccountTab(bag) then return true end
	local first = Enum.BagIndex and Enum.BagIndex.CharacterBankTab_1
	return first ~= nil and bag >= first and bag < first + 9
end

-- Only the old bank container keeps its items in inventory slots.
local function IsBankContainer(bag)
	local bank = (Enum.BagIndex and Enum.BagIndex.Bank) or rawget(_G, "BANK_CONTAINER")
	return bank ~= nil and bag == bank
end

-- Profession bags get a soft tint so their slots stand out.
local function BagFamily(bag)
	if bag == nil or bag <= 0 or bag == KEYRING then return 0 end
	local _, family = E.BagCache:Free(bag)
	return type(family) == "number" and family or 0
end

local function BagTint(bag)
	if BagFamily(bag) ~= 0 then return 0.25, 0.55, 0.25 end
end

local function BagName(bag)
	if bag == 0 then return E:GameText(BAG_NAME_BACKPACK, L["Backpack"]) end
	if bag == KEYRING then return E:GameText(_G.KEYRING, L["Keyring"]) end
	if IsAccountTab(bag) or (CHAR_TABS and bag >= (Enum.BagIndex.CharacterBankTab_1 or 99)) then
		for _, bankType in ipairs({ BANK_CHARACTER, BANK_ACCOUNT }) do
			local tabs = E.PlainCall(C_Bank and C_Bank.FetchPurchasedBankTabData, bankType)
			if type(tabs) == "table" and (not canaccesstable or canaccesstable(tabs)) then
				for index, tab in ipairs(tabs) do
					if not E.Secret(tab) and type(tab) == "table" and (not canaccesstable or canaccesstable(tab))
						and E.Plain(tab.ID) == bag then
						local name = E.Plain(tab.name)
						if type(name) == "string" and name ~= "" then return name end
						return (bankType == BANK_ACCOUNT and L["Account bank page %d"] or L["Bank tab %d"]):format(index)
					end
				end
			end
		end
	end
	local name = E.PlainCall(C_Container.GetBagName, bag)
	if type(name) == "string" and name ~= "" then return name end
	return L["Bag %d"]:format(bag)
end

---------------------------------------------------------------------------
-- Inventory cache: the core character store (Core/CharacterStore.lua,
-- E.Characters) records every character's bags, bank, gear, mail, gold,
-- currencies and guild bank tabs, also while this module is off. Store is
-- the thin view this module (and older plugin code) uses on top of it:
--   EldoUIDB.inventory[charKey] = { name, realm, realmKey, class, faction,
--     level, money, updated, bankUpdated, mailUpdated, bags, bank, mail,
--     equip, bagsLayout, bankLayout, counts = { [itemID] = { bags, bank,
--     mail, equip } }, currency, watched, ... }
--   EldoUIDB.guildBanks[guildKey] = { name, realm, faction, money, updated,
--     tabs = { [tab] = { name, icon, items, updated } }, counts }
---------------------------------------------------------------------------
local Store = {}
M.store = Store

local function Chars() return E.Characters end

function Store:All() return Chars():All() end
function Store:Get(key) return Chars():Get(key) end
function Store:Me() return Chars():Me() end
function Store:Recount(char) return Chars():Recount(char) end
function Store:ScanBags() Chars():ScanNow("bags") end
function Store:ScanBank() Chars():ScanNow("bank") end
function Store:ScanEquip() Chars():ScanNow("equip") end
function Store:ScanMail() Chars():ScanNow("mail") end
function Store:ScanMoney() Chars():ScanNow("money") end
function Store:ScanCurrency() Chars():ScanNow("currency") end
function Store:FindCharacter(name, realm) return Chars():FindCharacter(name, realm) end
function Store:CaptureSendMail(recipient) return Chars():CaptureSendMail(recipient) end
function Store:MailSent() return Chars():MailSent() end
function Store:Guilds() return Chars():Guilds() end
function Store:ScanGuildTab(tab) Chars():ScanNow("guildTab", tab) end

-- Nothing to scan; used to redraw once item info arrives from the server.
function Store:Refresh() end

function Store:Forget(key, settings)
	return Chars():Forget(key, settings)
end

-- Items each character has listed at the auction house (the character's
-- own auction list, or the Auction module's older per-character counts).
function Store:AuctionCount(key, itemID)
	local char = self:Get(key)
	local auctions = char and char.auctions
	if type(auctions) == "table" and type(auctions.list) == "table" and auctions.at then
		local total = 0
		for _, entry in ipairs(auctions.list) do
			if entry.id == itemID then total = total + (entry.count or 1) end
		end
		return total
	end
	local auction = EldoUIDB.auction
	local chars = type(auction) == "table" and auction.chars
	local entry = type(chars) == "table" and chars[key]
	local counts = type(entry) == "table" and entry.counts
	return type(counts) == "table" and counts[itemID] or 0
end

-- The Bags scopes (FACTION, REALM, ALL) as store scopes. "Realm" is the
-- ruleset on Forever (E:RealmKey).
local SCOPES = { FACTION = "faction", REALM = "realm", ALL = "account" }

-- Characters in display order: the current one first, then by realm and name.
-- With "Other characters" off only the current one is listed.
function Store:Characters(scope)
	Chars():Me()
	if M.db and not M.db.altChars then return { E.charKey } end
	return Chars():Keys(SCOPES[scope] or "account")
end

-- Guild banks on the realms the scope covers.
function Store:GuildList(scope)
	if M.db and not M.db.altChars then
		local key = Chars().CurrentGuildKey()
		if key and self:Guilds()[key] then return { key } end
		return {}
	end
	return Chars():GuildKeys(SCOPES[scope] or "account")
end

-- What an offline view shows: the list, the bag layout and a label record.
function Store:View(key, kind)
	if type(key) == "string" and key:find("^guild:") then
		local guild = self:Guilds()[key:sub(7)]
		if not guild then return {}, {}, { name = "?" } end
		local list, layout = {}, {}
		local tabs = {}
		for index in pairs(guild.tabs or {}) do tabs[#tabs + 1] = index end
		table.sort(tabs)
		for _, index in ipairs(tabs) do
			local data = guild.tabs[index]
			for _, value in ipairs(data.items or {}) do list[#list + 1] = value end
			layout[#layout + 1] = { "guild" .. index, #(data.items or {}), data.name ~= "" and data.name or L["Tab %d"]:format(index) }
		end
		return list, layout, { name = guild.name, money = guild.money, updated = guild.updated, guild = true }
	end
	local char = self:Get(key)
	if not char then return {}, {}, { name = "?" } end
	return char[kind] or {}, char[kind .. "Layout"] or {}, char
end

-- Views redraw (throttled) after the store records something.
local pending = {}
local function Schedule(what, delay)
	if pending[what] then return end
	pending[what] = true
	C_Timer.After(delay or 0.5, function()
		pending[what] = nil
		M:RefreshViews()
	end)
end

---------------------------------------------------------------------------
-- Search
---------------------------------------------------------------------------
local waitingForInfo = false
local TooltipPrefix, CanReadSearchTable
do
	local QUALITY_NAMES = { poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5, artifact = 6, heirloom = 7 }
	for index = 0, 8 do
		local name = _G["ITEM_QUALITY" .. index .. "_DESC"]
		if type(name) == "string" then QUALITY_NAMES[name:lower()] = index end
	end

	local function Compare(a, op, b)
		if not a or not b then return false end
		if op == ">" then return a > b end
		if op == ">=" then return a >= b end
		if op == "<" then return a < b end
		if op == "<=" then return a <= b end
		return a == b
	end

	local function QualityValue(text)
		local number = tonumber(text)
		if number then return number end
		for name, value in pairs(QUALITY_NAMES) do
			if name:sub(1, #text) == text then return value end
		end
	end

	local TOOLTIP_FORMS = { ["tt:"] = true, ["tip:"] = true, ["tooltip:"] = true }
	function TooltipPrefix(word)
		local prefix = word:match("^([!%-]?%a+:)")
		if prefix and TOOLTIP_FORMS[(prefix:gsub("^[!%-]", ""))] then return prefix end
	end

	-- "a b|c" -> { { "a", "b" }, { "c" } }: words AND, bars OR. A tooltip
	-- phrase continues to the next explicit separator, or ends at its closing quote.
	local function ParseQuery(text)
		text = strtrim((text or ""):lower())
		if text == "" then return nil end
		local alternatives, words = {}, {}
		local position = 1
		while position <= #text do
			local first = text:sub(position, position)
			if first == "|" then
				if #words > 0 then alternatives[#alternatives + 1] = words end
				words = {}
				position = position + 1
			elseif first == "&" or first:match("%s") then
				position = position + 1
			else
				local word = text:match("^[^%s&|]+", position)
				local prefix = TooltipPrefix(word)
				if prefix and text:sub(position + #prefix, position + #prefix) == '"' then
					local start = position + #prefix + 1
					local close = text:find('"', start, true)
					if close then
						word = prefix .. text:sub(start, close - 1)
						position = close + 1
					else
						position = position + #word
					end
				elseif prefix then
					local stop = text:find("[&|]", position + #prefix) or (#text + 1)
					word = strtrim(text:sub(position, stop - 1))
					position = stop
				else
					position = position + #word
				end
				words[#words + 1] = word
			end
		end
		if #words > 0 then alternatives[#alternatives + 1] = words end
		return #alternatives > 0 and alternatives or nil
	end
	M.ParseQuery = ParseQuery

	-- record: { short, id, quality, bound, quest, new }. Item info comes from
	-- the client cache; missing info asks the server and matches later.
	-- An item whose details are still loading is asked again on every look,
	-- so a search typed before they arrive still redraws once they do.
	local function Info(record)
		if not record.info then
			local info = { E.PlainCallEach(C_Item.GetItemInfo, record.short) }
			if info[1] then
				record.info = info
			else
				if record.info == nil and record.id and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(record.id) end
				record.info = false
				waitingForInfo = true
			end
		end
		return record.info or nil
	end

	-- Name and type words compare folded (E:FoldText: case, accents and
	-- Cyrillic), so "льняная" finds "Льняная ткань" and "epee" finds "Épée".
	local function Has(text, folded)
		return type(text) == "string" and E:FoldText(text):find(folded, 1, true) ~= nil
	end

	local TOOLTIP_TEXT_MAX = 256
	local savedTooltipText, savedTooltipCount = {}, 0
	local TOOLTIP_TEXT_FIELDS = { "leftText", "rightText" }

	function CanReadSearchTable(value)
		return type(value) == "table" and not E.Secret(value) and (not canaccesstable or canaccesstable(value))
	end

	local function SearchTooltipText(data)
		local lines = CanReadSearchTable(data) and data.lines
		if not CanReadSearchTable(lines) or #lines == 0 then return end
		local fields, complete = {}, true
		for _, line in ipairs(lines) do
			if CanReadSearchTable(line) then
				for _, key in ipairs(TOOLTIP_TEXT_FIELDS) do
					local text = line[key]
					if E.Secret(text) then
						complete = false
					elseif type(text) == "string" then
						fields[#fields + 1] = E:FoldText(text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
					end
				end
			else
				complete = false
			end
		end
		if #fields > 0 then return table.concat(fields, "\n"), complete end
	end

	local function TooltipTest(record, _, _, _, value)
		local native = C_TooltipInfo
		local wanted = E:FoldText(value)
		if not native or wanted == "" then return false end
		local text, complete
		if record.live then
			if not native.GetBagItem then return false end
			text = record.tooltipSearch
			if not text then
				text, complete = SearchTooltipText(E.PlainCall(native.GetBagItem, record.bag, record.slot))
				if complete then record.tooltipSearch = text end
			else
				complete = true
			end
		elseif native.GetHyperlink then
			local link = record.short
			text = savedTooltipText[link]
			if not text then
				text, complete = SearchTooltipText(E.PlainCall(native.GetHyperlink, link))
				if complete then
					if savedTooltipCount >= TOOLTIP_TEXT_MAX then wipe(savedTooltipText) savedTooltipCount = 0 end
					savedTooltipText[link] = text
					savedTooltipCount = savedTooltipCount + 1
				end
			else
				complete = true
			end
		else
			return false
		end
		if text and text:find(wanted, 1, true) then return true end
		if not complete then waitingForInfo = true end
		return false
	end

	-- The search words: one table for the search and the Search help window,
	-- so every word the search knows has its help line. An entry matches a
	-- whole `word` (or one of `also`), or one of its `forms` (patterns whose
	-- captures go to `test`); an entry without a test is a rule of the search
	-- itself (not, or, and) and is only shown. `syntax` is the help line's
	-- left side, `example` what a click on the line puts in the search box.
	-- test(record, info, quality, classID, ...) -> true when the item matches.
	local function NameTest(record, info, _, _, value)
		local name = info and info[1] or (C_Item.GetItemNameByID and record.id and C_Item.GetItemNameByID(record.id))
		return Has(name, E:FoldText(value))
	end
	local SEARCH_WORDS = {
		{ syntax = "silk", example = "silk", help = L["Items whose name has the word"], plain = true },
		{ forms = { "^n:(.+)$" }, syntax = "n:silk", example = "n:silk", help = L["The name only, also for words below"], test = NameTest },
		{ forms = { "^q([:=<>]+)(.+)$" }, syntax = "q:rare  q>=3", example = "q>=rare", help = L["Quality by name or number (0 poor to 7 heirloom)"],
			test = function(_, _, quality, _, op, value) return Compare(quality, op == ":" and "=" or op, QualityValue(value)) end },
		{ forms = { "^i?lvl([:=<>]+)(%d+)$" }, syntax = "ilvl>50  lvl:20", example = "ilvl>=60", help = L["Item level; \"lvl:20\" means 20 or more"],
			test = function(record, info, _, _, op, value)
				local level = C_Item.GetDetailedItemLevelInfo(record.short) or (info and info[4])
				return Compare(level, op == ":" and ">=" or op, tonumber(value))
			end },
		{ forms = { "^tt:(.+)$", "^tip:(.+)$", "^tooltip:(.+)$" }, syntax = 'tt:cloth  tt:"fire resistance"', example = 'tt:"fire resistance"',
			help = L["Tooltip text. Use quotes around a phrase to add more search words after it."], test = TooltipTest },
		{ forms = { "^r([:=<>]+)(%d+)$", "^req([:=<>]+)(%d+)$", "^rl([:=<>]+)(%d+)$" }, syntax = "r<=32  r>=20  r=30", example = "r<=32",
			help = L['Required level. "r:32" means level 32 or lower.'],
			test = function(_, info, _, _, op, value)
				local required = info and E.Plain(info[5])
				return type(required) == "number" and Compare(required, op == ":" and "<=" or op, tonumber(value))
			end },
		{ word = "known", example = "known", help = L["Recipes, mounts, pets or toys you already know or own"],
			test = function(record) return E.IsItemKnown and E.PlainCall(E.IsItemKnown, E, record.link or record.short) == true end },
		{ word = "upgrade", example = "upgrade", help = L["Gear that Upgrades rates above your equipped gear"],
			test = function(record)
				local upgrades = E.modules.Upgrades
				if not (upgrades and upgrades.active) then return false end
				local result = E.PlainCall(E.GetItemUpgrade, E, record.link or record.short)
				return CanReadSearchTable(result) and E.Plain(result.upgrade) == true
			end },
		{ forms = { "^t:(.+)$", "^type:(.+)$" }, syntax = "t:cloth  type:sword", example = "t:cloth", help = L["Item type, subtype or slot"],
			test = function(_, info, _, _, value)
				if not info then return false end
				local slot = info[9] and _G[info[9]]
				value = E:FoldText(value)
				return (Has(info[6], value) or Has(info[7], value) or Has(slot, value)) and true or false
			end },
		{ word = "junk", example = "junk", help = L["Poor quality (gray) items"],
			test = function(_, _, quality) return quality == QUALITY.Poor end },
		{ word = "quest", example = "quest", help = L["Quest items"],
			test = function(record, _, _, classID) return record.quest or classID == ITEM_CLASS.Questitem end },
		{ word = "new", example = "new", help = L["Items new in your bags"],
			test = function(record) return record.new == true end },
		{ word = "gear", example = "gear", help = L["Weapons and armor"],
			test = function(_, _, _, classID) return classID == ITEM_CLASS.Weapon or classID == ITEM_CLASS.Armor end },
		{ word = "bound", also = { "soulbound" }, example = "bound", help = L["Items bound to you"],
			test = function(record) return record.bound == true end },
		{ word = "bop", example = "bop", help = L["Items that bind when picked up"],
			test = function(_, info) return info and info[14] == 1 end },
		{ word = "boe", example = "boe", help = L["Items that bind when equipped and are not bound yet"],
			test = function(record, info) return info and info[14] == 2 and record.bound ~= true end },
		{ syntax = "-word  !word", example = "gear -bound", help = L["Not: leaves out what the word finds"] },
		{ syntax = "a b  a&b", example = "gear boe", help = L["And: items both words find"] },
		{ syntax = "a|b", example = "junk|q:0", help = L["Or: items either side finds"] },
	}
	M.SEARCH_WORDS = SEARCH_WORDS
	local WORD_TESTS, FORM_TESTS = {}, {}
	for _, entry in ipairs(SEARCH_WORDS) do
		if entry.word then
			entry.syntax = entry.syntax or table.concat({ entry.word, unpack(entry.also or {}) }, "  ")
			WORD_TESTS[entry.word] = entry.test
			for _, word in ipairs(entry.also or {}) do WORD_TESTS[word] = entry.test end
		elseif entry.forms then
			for _, form in ipairs(entry.forms) do FORM_TESTS[#FORM_TESTS + 1] = { form, entry.test } end
		end
	end

	local function MatchWord(word, record)
		local first = word:sub(1, 1)
		if (first == "-" or first == "!") and #word > 1 then return not MatchWord(word:sub(2), record) end
		local info = Info(record)
		local quality = record.quality or (info and info[3])
		local classID = info and info[12] or ClassOf(record)
		local test = WORD_TESTS[word]
		if test then return test(record, info, quality, classID) end
		for _, pair in ipairs(FORM_TESTS) do
			local a, b = word:match(pair[1])
			if a then return pair[2](record, info, quality, classID, a, b) end
		end
		return NameTest(record, info, quality, classID, word)
	end

	local function Matches(query, record)
		if not query then return true end
		if not record.short or record.short == "" then return false end
		for _, words in ipairs(query) do
			local all = true
			for _, word in ipairs(words) do
				if not MatchWord(word, record) then
					all = false
					break
				end
			end
			if all then return true end
		end
		return false
	end
	M.Matches = Matches
end
local ParseQuery, Matches = M.ParseQuery, M.Matches

local function ByFoundName(a, b)
	if a.sortName ~= b.sortName then return a.sortName < b.sortName end
	return a.id < b.id
end

-- Search every cached character and guild bank. Returns
-- { { id, short, total, chars = { key = { b, k, m, e } }, guilds = { key = n } } }.
function M:FindAll(text)
	local query = ParseQuery(text)
	if not query then return {} end
	local found, matches = {}, {}
	local tooltipQuery
	for _, words in ipairs(query) do
		for _, word in ipairs(words) do
			if TooltipPrefix(word) then tooltipQuery = true break end
		end
		if tooltipQuery then break end
	end
	local function Add(short, id)
		if not found[id] then found[id] = { id = id, short = short, total = 0, chars = {}, guilds = {} } end
		return found[id]
	end
	local function Entry(short)
		local id = ItemIDOf(short)
		if not id then return end
		if matches[short] == nil then
			local record = { short = short, id = id }
			matches[short] = Matches(query, record) == true
		end
		if not matches[short] then return end
		return Add(short, id)
	end
	if tooltipQuery then
		for _, bag in ipairs(BagIDs(true)) do
			for slot = 1, NumSlots(bag) do
				local info = E.BagCache:Info(bag, slot)
				if CanReadSearchTable(info) then
					local link = E.Plain(info.hyperlink)
					local short = ShortItem(link)
					local id = short and ItemIDOf(short)
					if id then
						local record = { short = short, id = id, link = link, quality = E.Plain(info.quality),
							bound = E.Plain(info.isBound), bag = bag, slot = slot, live = true }
						if Matches(query, record) then
							local count = E.Plain(info.stackCount)
							if type(count) ~= "number" or not (count > 0 and count < math.huge) then count = 1 end
							local entry = Add(short, id)
							entry.chars[E.charKey] = entry.chars[E.charKey] or { 0, 0, 0, 0 }
							entry.chars[E.charKey][1] = entry.chars[E.charKey][1] + count
							entry.total = entry.total + count
						end
					end
				end
			end
		end
	end
	for _, key in ipairs(Store:Characters("ALL")) do
		local char = Store:Get(key)
		for index, location in ipairs(LOCATIONS) do
			if not (tooltipQuery and key == E.charKey and location == "bags") then
				for _, value in ipairs(char[location] or {}) do
					local short, count = Decode(value)
					local entry = short and Entry(short)
					if entry then
						entry.chars[key] = entry.chars[key] or { 0, 0, 0, 0 }
						entry.chars[key][index] = entry.chars[key][index] + count
						entry.total = entry.total + count
					end
				end
			end
		end
	end
	for _, key in ipairs(Store:GuildList("ALL")) do
		for _, data in pairs(Store:Guilds()[key].tabs or {}) do
			for _, value in ipairs(data.items or {}) do
				local short, count = Decode(value)
				local entry = short and Entry(short)
				if entry then
					entry.guilds[key] = (entry.guilds[key] or 0) + count
					entry.total = entry.total + count
				end
			end
		end
	end
	local list = {}
	for _, entry in pairs(found) do
		if entry then
			entry.sortName = C_Item.GetItemNameByID and C_Item.GetItemNameByID(entry.id) or ""
			list[#list + 1] = entry
		end
	end
	table.sort(list, ByFoundName)
	return list
end

local function Breakdown(counts, auctions)
	local parts = {}
	for index, location in ipairs(LOCATIONS) do
		if counts[index] > 0 then parts[#parts + 1] = Grey(LOCATION_LABEL[location]) .. " " .. counts[index] end
	end
	if auctions and auctions > 0 then parts[#parts + 1] = Grey(LOCATION_LABEL.auction) .. " " .. auctions end
	return table.concat(parts, "  ")
end

---------------------------------------------------------------------------
-- Slot decorations, shared with the Blizzard skin (Modules/Bags/Blizzard.lua)
---------------------------------------------------------------------------
-- Border color from the game's quality colors; quest items in yellow.
local function BorderColor(quality, quest)
	local db = M.db
	if quest and db.questBorder then return 1, 0.82, 0 end
	if db.qualityBorder and quality and quality >= db.minQuality then
		local r, g, b = C_Item.GetItemQualityColor(quality)
		if r then return r, g, b end
	end
	return unpack(E.media.borderColor)
end
M.BorderColor = BorderColor

-- The new-item glow has its own color, whatever the border settings: the
-- quality color from Uncommon up, quest yellow, white below. A glow in the
-- border color would be black, and draws nothing in additive blend.
local function NewGlowColor(quality, quest)
	if quest then return 1, 0.82, 0 end
	if quality and quality >= 2 then
		local r, g, b = C_Item.GetItemQualityColor(quality)
		if r then return r, g, b end
	end
	return 1, 1, 1
end
M.NewGlowColor = NewGlowColor

-- Item level for weapons and armor at or above the chosen minimum.
local function ItemLevelText(short, quality)
	local db = M.db
	if not (db.itemLevel and short and quality and quality >= QUALITY.Common) then return "" end
	local classID = select(6, C_Item.GetItemInfoInstant(short))
	if classID ~= ITEM_CLASS.Weapon and classID ~= ITEM_CLASS.Armor then return "" end
	local itemLevel = C_Item.GetDetailedItemLevelInfo(short)
	if itemLevel and itemLevel > 1 and itemLevel >= (db.itemLevelMin or 1) then return itemLevel end
	return ""
end
M.ItemLevelText = ItemLevelText

-- "BoE" / "BoU" on items that are not bound yet.
local function BindText(short, bound)
	if not (M.db.boundText and short) or bound ~= false then return "" end
	local bindType = select(14, C_Item.GetItemInfo(short))
	if bindType == 2 then return L["BoE"] end
	if bindType == 3 then return L["BoU"] end
	return ""
end
M.BindText = BindText

local function JunkMarks(quality, eligible)
	local style = M.db.junkStyle
	if eligible == nil then eligible = quality == QUALITY.Poor end
	local junk = eligible and style ~= "off"
	return junk and (style == "coin" or style == "both"), junk and (style == "dim" or style == "both")
end
M.JunkMarks = JunkMarks

-- Text on the slots: stack count, item level and bind text use the
-- sizes, outlines and corners from the Slots tab. Every styled font string
-- is remembered, so a change restyles the slots that already exist.
local styledTexts = setmetatable({}, { __mode = "k" })  -- font string -> { kind, parent }
local JUSTIFY = { LEFT = "LEFT", RIGHT = "RIGHT" }

local function Outline(value)
	if value == "NONE" then return "" end
	if value == nil or value == "DEFAULT" then return nil end
	return value
end

local function PaintText(fontString, kind, parent)
	local text = M.db.text
	if kind == "count" then
		E:SetFont(fontString, text.countSize, Outline(text.countOutline))
		fontString:ClearAllPoints()
		fontString:SetPoint(text.countPoint, parent, text.countPoint, text.countX, text.countY)
		fontString:SetJustifyH(JUSTIFY[text.countPoint:match("LEFT") or text.countPoint:match("RIGHT") or ""] or "CENTER")
	elseif kind == "level" then
		E:SetFont(fontString, text.levelSize, Outline(text.levelOutline))
		fontString:ClearAllPoints()
		fontString:SetPoint(text.levelPoint, parent, text.levelPoint, text.levelX, text.levelY)
		fontString:SetJustifyH(JUSTIFY[text.levelPoint:match("LEFT") or text.levelPoint:match("RIGHT") or ""] or "CENTER")
	elseif kind == "bind" then
		E:SetFont(fontString, text.bindSize, Outline(text.levelOutline))
	end
end

-- Style one font string of a slot and keep it in the restyle list.
function M:StyleSlotText(fontString, kind, parent)
	if not fontString then return end
	styledTexts[fontString] = { kind = kind, parent = parent }
	PaintText(fontString, kind, parent)
end

-- Countdown numbers on a slot's cooldown swipe: EldoUI's
-- shared cooldown text, the game's own numbers, or none. The swipe itself
-- is the client's Cooldown widget; EldoUI never reads the remaining time.
local styledCooldowns = setmetatable({}, { __mode = "k" })

function M:StyleSlotCooldown(cooldown)
	if not cooldown then return end
	styledCooldowns[cooldown] = true
	if E.StyleCooldownText then
		E:StyleCooldownText(cooldown, { mode = self.db.cooldownText, size = math.max(10, math.floor((self.db.size or 38) * 0.4)) })
	elseif cooldown.SetHideCountdownNumbers then
		cooldown:SetHideCountdownNumbers(self.db.cooldownText == "off")
	end
end

-- The junk coin, lock and set marks: about a third of the slot, at
-- least 10 px.
function M:MarkSize()
	return math.max(10, math.floor((self.db and self.db.size or 37) * 0.3 + 0.5))
end

local styledSlots = setmetatable({}, { __mode = "k" })

function M:RestyleSlotTexts()
	for fontString, info in pairs(styledTexts) do PaintText(fontString, info.kind, info.parent) end
	for cooldown in pairs(styledCooldowns) do self:StyleSlotCooldown(cooldown) end
	local size = self:MarkSize()
	for button in pairs(styledSlots) do
		for _, key in ipairs({ "junkCoin", "lockMark", "eldoSetMark", "eldoFoodMark" }) do
			if button[key] then button[key]:SetSize(size, size) end
		end
	end
end

-- Item level color: the game's quality color (Uncommon and up) or a custom one.
function M:ItemLevelColor(quality)
	local text = self.db.text
	if text.levelColor == "custom" then return unpack(text.levelCustom) end
	if quality and quality >= QUALITY.Uncommon then
		local r, g, b = C_Item.GetItemQualityColor(quality)
		if r then return r, g, b end
	end
	return 1, 1, 1
end

---------------------------------------------------------------------------
-- Item slots
---------------------------------------------------------------------------
-- Every empty slot has one look: EldoUI's dark slot, the same in every bag.
-- The game's item button brings empty-slot art of its own (its normal
-- texture, a slot background, the empty-slot picture as the icon). Which
-- of them shows depends on which of the game's own updates touched the
-- button last, so the grid would mix two looks. They never show; a slot
-- shows its icon only while it holds an item.
local TEMPLATE_ART = { "ItemSlotBackground", "SlotBackground", "EmptyBackground", "BagIndicator" }

local function HideTemplateArt(button)
	local normal = button.GetNormalTexture and button:GetNormalTexture()
	if normal then normal:SetAlpha(0) end
	for _, key in ipairs(TEMPLATE_ART) do
		local region = button[key]
		if type(region) == "table" and region.SetAlpha then region:SetAlpha(0) end
	end
end

local function SlotLook(button)
	HideTemplateArt(button)
	local icon = button.icon or button.Icon
	if icon then icon:SetAlpha(button.eldoEmpty and 0 or 1) end
end

-- The game's own updates set the icon or the normal texture again; the
-- slot keeps its look.
hooksecurefunc("SetItemButtonTexture", function(button)
	if styledSlots[button] then SlotLook(button) end
end)

local function StyleSlot(button)
	styledSlots[button] = true
	HideTemplateArt(button)
	if button.SetNormalTexture then hooksecurefunc(button, "SetNormalTexture", HideTemplateArt) end
	if button.IconBorder then button.IconBorder:SetAlpha(0) end
	if button.NewItemTexture then button.NewItemTexture:SetAlpha(0) end
	if button.BattlepayItemTexture then button.BattlepayItemTexture:SetAlpha(0) end
	if button.IconQuestTexture then button.IconQuestTexture:SetAlpha(0) end
	local icon = button.icon or button.Icon
	if not icon then
		icon = button:CreateTexture(nil, "ARTWORK")
		button.icon = icon
	end
	E:TrimIcon(icon)
	icon:ClearAllPoints()
	icon:SetPoint("TOPLEFT", E:PixelFor(button), -E:PixelFor(button))
	icon:SetPoint("BOTTOMRIGHT", -E:PixelFor(button), E:PixelFor(button))
	button.eldoBorder = CreateFrame("Frame", nil, button)
	button.eldoBorder:SetAllPoints()
	E:SetTemplate(button.eldoBorder)
	button.eldoBorder:SetBackdropColor(0, 0, 0, 0.35)
	button.eldoBorder:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
	local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
	if not highlight and button.SetHighlightTexture then
		button:SetHighlightTexture(E.media.flat)
		highlight = button:GetHighlightTexture()
	end
	if highlight then
		highlight:SetColorTexture(1, 1, 1, E.tokens.hover.hud)
		highlight:SetAllPoints(icon)
	end
	local pushed = button.GetPushedTexture and button:GetPushedTexture()
	if pushed then
		pushed:SetColorTexture(1, 1, 1, E.tokens.pressed)
		pushed:SetAllPoints(icon)
	end
	button.level = E:CreateText(button, E.tokens.size.label, "LEFT")
	M:StyleSlotText(button.level, "level", button)
	button.bind = E:CreateText(button, E.tokens.size.tiny, "LEFT")
	button.bind:SetPoint("BOTTOMLEFT", 2, 2)
	M:StyleSlotText(button.bind, "bind", button)
	button.bind:SetTextColor(E:TokenColor("secondary"))
	button.junkCoin = button:CreateTexture(nil, "OVERLAY")
	button.junkCoin:SetSize(M:MarkSize(), M:MarkSize())
	button.junkCoin:SetPoint("TOPLEFT", 2, -2)
	button.junkCoin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
	-- Lock mark: one of your quests or recipes needs this item.
	button.lockMark = button:CreateTexture(nil, "OVERLAY")
	button.lockMark:SetSize(M:MarkSize(), M:MarkSize())
	button.lockMark:SetPoint("TOPRIGHT", -2, -2)
	button.lockMark:SetTexture(E.ItemProtect and E.ItemProtect.LOCK_ICON)
	local warn = E.tokens.text.warn
	button.lockMark:SetVertexColor(warn[1], warn[2], warn[3])
	button.lockMark:Hide()
	button.newGlow = button:CreateTexture(nil, "OVERLAY")
	button.newGlow:SetAllPoints()
	button.newGlow:SetTexture(E.media.glow)
	button.newGlow:SetBlendMode("ADD")
	local count = button.Count or (button:GetName() and _G[button:GetName() .. "Count"])
	if not count then count = button:CreateFontString(nil, "OVERLAY") end
	M:StyleSlotText(count, "count", button)
	button.eldoCount = count
	-- The template's cooldown swipe: countdown numbers as set on the Slots tab.
	if button.Cooldown then M:StyleSlotCooldown(button.Cooldown) end
end

-- Shared look for one filled slot, live or offline.
local function PaintItem(button, record, alpha)
	button.eldoEmpty = nil
	SlotLook(button)
	local r, g, b = BorderColor(record.quality, record.quest)
	button.eldoBorder:SetBackdropBorderColor(r, g, b, 1)
	button.level:SetText(ItemLevelText(record.short, record.quality))
	button.level:SetTextColor(M:ItemLevelColor(record.quality))
	button.bind:SetText(BindText(record.short, record.bound))
	local coin, dim = JunkMarks(record.quality, record.junk)
	button.junkCoin:SetShown(coin and true or false)
	button.lockMark:SetShown(M.db.protectItems and record.protected or false)
	local icon = button.icon or button.Icon
	local shade = dim and 0.6 or 1
	-- Already known: the shared check and tint from
	-- Core/EconomyWindows.lua, also used by the merchant and auction house.
	local known = M.db.knownTint and E.IsItemKnown and E.knownTint and E:IsItemKnown(record.link or record.short)
	if icon then
		if known then
			icon:SetVertexColor(unpack(E.knownTint))
		else
			icon:SetVertexColor(shade, shade, shade)
		end
	end
	button.newGlow:SetShown(M.db.newGlow and record.new or false)
	if record.new then
		local gr, gg, gb = NewGlowColor(record.quality, record.quest)
		button.newGlow:SetVertexColor(gr, gg, gb, 0.6)
	end
	local count = record.total or record.count
	button.eldoCount:SetText(count and count > 1 and tostring(count) or "")
	button:SetAlpha(alpha)
	return known
end

local function PaintEmpty(button, bag, freeCount, alpha)
	button.eldoEmpty = true
	SlotLook(button)
	button.level:SetText("")
	button.bind:SetText("")
	button.junkCoin:Hide()
	button.lockMark:Hide()
	button.newGlow:Hide()
	button.eldoCount:SetText(freeCount and freeCount > 0 and freeCount or "")
	button:SetAlpha(alpha or 1)
	local tr, tg, tb
	if type(bag) == "number" then tr, tg, tb = BagTint(bag) end
	if tr and M.db.bagTint then
		button.eldoBorder:SetBackdropBorderColor(tr, tg, tb, 1)
	else
		button.eldoBorder:SetBackdropBorderColor(unpack(E.media.borderColor))
	end
end

-- The bag window's slot look, also used by the guild bank window
-- (GuildBank.lua).
M.StyleSlot, M.PaintSlotItem, M.PaintSlotEmpty, M.ShortItem = StyleSlot, PaintItem, PaintEmpty, ShortItem

-- Live slots: Blizzard's container item button inside a holder whose ID is the bag.
local function GetLiveSlot(window, bag, slot)
	local holder = window.holders[bag]
	if not holder then
		holder = CreateFrame("Frame", nil, window)
		holder:SetID(bag)
		holder:SetAllPoints(window)
		holder.buttons = {}
		window.holders[bag] = holder
	end
	local button = holder.buttons[slot]
	if not button then
		local name = ("EldoUI_Bag%d_Slot%d"):format(bag < 0 and 100 - bag or bag, slot)
		button = CreateFrame("ItemButton", name, holder, "ContainerFrameItemButtonTemplate")
		button:SetID(slot)
		if button.SetBagID then button:SetBagID(bag) end
		-- A right-click on an item in a bank tab takes it out to the bags,
		-- as on the game's own bank window. The bag button's right-click
		-- puts an item into the open bank, which does nothing for an item
		-- that is already there. Modified clicks and the left button keep
		-- the button's own handling.
		if IsBankTab(bag) then
			local click = button:GetScript("OnClick")
			button:SetScript("OnClick", function(self, mouse, down)
				if mouse == "RightButton" and not IsModifiedClick() then
					if bankOpen then C_Container.UseContainerItem(bag, self:GetID()) end
					return
				end
				if click then return click(self, mouse, down) end
			end)
		end
		if E.modules.Merchant then E.modules.Merchant:WatchJunkSlot(button, bag) end
		StyleSlot(button)
		-- Alt-click attaches to mail when the Mail module is on.
		button:HookScript("OnClick", function(self, mouse)
			local merchant = E.modules.Merchant
			if IsAltKeyDown() and not (merchant and merchant:IsJunkMarkClick(mouse))
				and E.modules.Mail and E.modules.Mail.AttachFromBag then
				E.modules.Mail:AttachFromBag(bag, self:GetID())
			end
		end)
		-- The old bank container keeps its items in inventory slots.
		if IsBankContainer(bag) and BankButtonIDToInvSlotID then
			button:HookScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetInventoryItem("player", BankButtonIDToInvSlotID(self:GetID()))
				GameTooltip:Show()
			end)
		end
		button:HookScript("OnEnter", function() M:HighlightBag(window, bag) end)
		button:HookScript("OnLeave", function() M:HighlightBag(window, nil) end)
		-- A grouped slot names its stacks (Modules/Bags/Categories.lua).
		button:HookScript("OnEnter", function(self)
			if M.StackTip then M:StackTip(self) end
			if M.LowestValueSlotTip then M:LowestValueSlotTip(self) end
		end)
		-- Alt-click flashes the same item (Modules/Bags/Marks.lua).
		button:HookScript("OnClick", function(self, mouse) if M.AltFlash then M:AltFlash(self, mouse) end end)
		-- Modifier-click disenchant / pick lock (Modules/BagActions).
		if E.BagActions then E.BagActions:WatchSlot(button, "eldoui") end
		holder.buttons[slot] = button
	end
	return button
end

local function LiveRecord(bag, slot)
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if not info then return { bag = bag, slot = slot, empty = true } end
	local questInfo = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
	local bound = E.Plain(info.isBound)
	if type(bound) ~= "boolean" then bound = nil end
	local record = {
		bag = bag, slot = slot, live = true,
		short = ShortItem(info.hyperlink) or "", id = info.itemID, link = info.hyperlink,
		quality = info.quality, count = info.stackCount, locked = info.isLocked, icon = info.iconFileID,
		bound = bound,
		quest = questInfo and (questInfo.isQuestItem or questInfo.questID) and true or false,
		new = C_NewItems and C_NewItems.IsNewItem(bag, slot) or false,
		protected = M.db.protectItems and E.IsItemProtected and E:IsItemProtected(info.itemID, bag, slot) or false,
		junk = E.WillSellAsJunk and E:WillSellAsJunk(bag, slot, info),
	}
	if M.db.tradeTime and M.TradeItemGUID then record.tradeGUID = M:TradeItemGUID(record) end
	return record
end
M.LiveRecord = LiveRecord

-- Faded while searching for something else or hovering another bag.
local function SlotAlpha(window, record)
	if window.highlightBag ~= nil and record.bag ~= window.highlightBag then return 0.25 end
	if record.empty then return window.query and 0.4 or 1 end
	if window.query and not Matches(window.query, record) then return 0.2 end
	return 1
end

-- The item's cooldown on the template's Cooldown widget. The times
-- come from the client; when they are secret they go to the widget as
-- they are, without being compared.
local function PaintCooldown(button, record)
	if button.SetHasItem then button:SetHasItem(not record.empty and record.icon or nil) end
	local cooldown = button.Cooldown
	if not cooldown then return end
	if record.empty or not M.db.cooldowns or not C_Container.GetContainerItemCooldown then
		cooldown:Hide()
		return
	end
	local start, duration, enable = C_Container.GetContainerItemCooldown(record.bag, record.slot)
	if Secret(start) or Secret(duration) or Secret(enable) then
		pcall(cooldown.SetCooldown, cooldown, start, duration)
	elseif enable and enable ~= 0 and start and start > 0 and duration and duration > 0 then
		cooldown:SetDrawEdge(false)
		cooldown:SetCooldown(start, duration)
	else
		cooldown:Clear()
	end
end

-- The upgrade arrow takes a corner the item level doesn't use. The red mark
-- on gear this character can't use belongs to the Slots tab switch alone.
local ARROW_CORNER = { TOPLEFT = "BOTTOMLEFT", TOP = "BOTTOMLEFT", LEFT = "TOPRIGHT" }
local upgradeOptions = { noTint = true }

function M:UpgradeOptions()
	local text = self.db and self.db.text
	upgradeOptions.arrowPoint = ARROW_CORNER[text and text.levelPoint or "TOPLEFT"] or "TOPLEFT"
	return upgradeOptions
end

local function PaintLive(window, button, record)
	local icon = button.icon or button.Icon
	M.livePaints = (M.livePaints or 0) + 1
	button.eldoRecord = record -- the lock and cooldown updates repaint from it
	PaintCooldown(button, record)
	if not record.empty then
		SetItemButtonTexture(button, record.icon)
		SetItemButtonCount(button, record.total or record.count)
		SetItemButtonDesaturated(button, record.locked)
		local known = PaintItem(button, record, SlotAlpha(window, record))
		if E.SetUpgradeArrow then E:SetUpgradeArrow(button, record.link, M:UpgradeOptions()) end
		if M.PaintMarks then M:PaintMarks(window, button, record, nil, known or false) end
		return
	end
	SetItemButtonTexture(button, nil)
	SetItemButtonCount(button, 0)
	if E.SetUpgradeArrow then E:SetUpgradeArrow(button, nil) end
	if icon then icon:SetVertexColor(1, 1, 1) end
	PaintEmpty(button, record.bag, record.freeCount, SlotAlpha(window, record))
	if M.PaintMarks then M:PaintMarks(window, button, record) end
end

-- Offline slots: plain buttons with a tooltip and modified clicks.
local function GetOfflineSlot(window, index)
	local button = window.pool[index]
	if button then return button end
	button = CreateFrame("Button", nil, window)
	StyleSlot(button)
	button:SetScript("OnEnter", function(self)
		if not self.short then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(self.short)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnClick", function(self)
		if not self.short then return end
		local link = select(2, C_Item.GetItemInfo(self.short))
		if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
	end)
	window.pool[index] = button
	return button
end

local function PaintOffline(window, button, record)
	button.short = record.short
	button.eldoOffline = record -- a new search fades it again from this
	if record.empty then
		button.icon:SetTexture(nil)
		button.icon:SetVertexColor(1, 1, 1)
		PaintEmpty(button, record.bag, record.freeCount, SlotAlpha(window, record))
		if M.PaintMarks then M:PaintMarks(window, button, record, true) end
		return
	end
	local id = record.id
	local icon = id and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) or (id and select(5, C_Item.GetItemInfoInstant(id)))
	button.icon:SetTexture(icon)
	PaintItem(button, record, SlotAlpha(window, record))
	if M.PaintMarks then M:PaintMarks(window, button, record, true) end
end

---------------------------------------------------------------------------
-- Categories and sections
---------------------------------------------------------------------------
local CATEGORY_ORDER = { "custom1", "custom2", "custom3", "new", "equipment", "consumable", "quest", "tradegoods",
	"recipe", "ammo", "container", "keys", "other", "junk", "free" }
local CATEGORY_TITLE = E:TranslateValues({
	new = E.Key("New"), equipment = E.Key("Equipment"), consumable = E.Key("Consumables"), quest = E.Key("Quest items"),
	tradegoods = E.Key("Trade goods"), recipe = E.Key("Recipes"), ammo = E.Key("Ammo"), container = E.Key("Bags"),
	keys = E.Key("Keys"), other = E.Key("Other"), junk = E.Key("Junk"), free = E.Key("Free"),
})
M.CATEGORY_TITLE = CATEGORY_TITLE
M.CATEGORY_ORDER = CATEGORY_ORDER
local customQueries = {}

function M:ParseCustomCategories()
	wipe(customQueries)
	for index, custom in ipairs(self.db.custom or {}) do
		if type(custom) == "table" and type(custom.query) == "string" and custom.query ~= "" then
			customQueries[index] = ParseQuery(custom.query)
		end
	end
	if self.RebuildCategories then self:RebuildCategories() end
end

-- window: the bag or bank window the item shows in (own categories can be
-- off in one of them).
local function CategoryOf(record, window)
	local db = M.db
	if record.bag == KEYRING and KEYRING then return "keys" end
	local own = M.OwnCategoryOf and M:OwnCategoryOf(record, window)
	if own then return own end
	for index = 1, db.customMoved and 0 or 3 do
		local query = customQueries[index]
		if query and Matches(query, record) then return "custom" .. index end
	end
	local enabled = db.categories
	if enabled.new and record.new then return "new" end
	if enabled.junk and (record.junk == true or (record.junk == nil and record.quality == QUALITY.Poor)) then return "junk" end
	local classID = ClassOf(record)
	if enabled.quest and (record.quest or classID == ITEM_CLASS.Questitem) then return "quest" end
	if enabled.equipment and (classID == ITEM_CLASS.Weapon or classID == ITEM_CLASS.Armor) then return "equipment" end
	if enabled.ammo and classID == ITEM_CLASS.Projectile then return "ammo" end
	if enabled.consumable and classID == ITEM_CLASS.Consumable then return "consumable" end
	if enabled.tradegoods and (classID == ITEM_CLASS.Tradegoods or classID == ITEM_CLASS.Reagent
		or classID == ITEM_CLASS.Gem or classID == ITEM_CLASS.ItemEnhancement) then return "tradegoods" end
	if enabled.recipe and classID == ITEM_CLASS.Recipe then return "recipe" end
	if enabled.container and (classID == ITEM_CLASS.Container or classID == ITEM_CLASS.Quiver) then return "container" end
	if enabled.keys and classID == ITEM_CLASS.Key then return "keys" end
	return "other"
end
M.CategoryOf = CategoryOf

local function SortItems(a, b)
	local qa, qb = a.quality or -1, b.quality or -1
	if qa ~= qb then return qa > qb end
	local ia, ib = a.id or 0, b.id or 0
	if ia ~= ib then return ia < ib end
	local ca, cb = a.count or 1, b.count or 1
	if ca ~= cb then return ca > cb end
	if a.bag ~= b.bag then return tostring(a.bag) < tostring(b.bag) end
	return (a.slot or 0) < (b.slot or 0)
end

local function SectionTitle(bag, records)
	local free = 0
	for _, record in ipairs(records) do
		if record.empty then free = free + 1 end
	end
	return BagName(bag), free > 0 and L["%d free"]:format(free) or nil
end

-- groups: ordered list of { bag, records } (one per bag). Builds the
-- sections of the chosen view: { { key, title, note, records, reverse } }.
local function BuildSections(window, groups, live)
	local db = M.db
	local view = window.kind == "bank" and db.bankView or db.view
	local sections = {}
	if view == "bags" then
		for _, group in ipairs(groups) do
			if #group.records > 0 then
				local title, note = SectionTitle(group.bag, group.records)
				sections[#sections + 1] = { key = tostring(group.bag), title = group.title or title, note = note, records = group.records }
			end
		end
		return sections
	end
	if view == "categories" then
		local byKey = {}
		local empties = {}
		for _, group in ipairs(groups) do
			for _, record in ipairs(group.records) do
				if record.empty then
					if group.bag ~= KEYRING or not KEYRING then
						-- Free space goes together per bag type (normal, each profession family, reagent bag).
						local family = live and type(group.bag) == "number" and (group.bag == REAGENT and "reagent" or BagFamily(group.bag)) or 0
						empties[family] = empties[family] or {}
						table.insert(empties[family], record)
					end
				else
					local key = CategoryOf(record, window)
					byKey[key] = byKey[key] or {}
					table.insert(byKey[key], record)
				end
			end
		end
		local free = {}
		local families = {}
		for family in pairs(empties) do families[#families + 1] = family end
		table.sort(families, function(a, b) return tostring(a) < tostring(b) end)
		for _, family in ipairs(families) do
			local list = empties[family]
			if db.compactEmpty then
				list[1].freeCount = #list
				free[#free + 1] = list[1]
			else
				for _, record in ipairs(list) do free[#free + 1] = record end
			end
		end
		byKey.free = #free > 0 and free or nil
		for _, key in ipairs(M.SectionOrder and M:SectionOrder() or CATEGORY_ORDER) do
			local records = byKey[key]
			if records then
				if key ~= "free" then
					if M.GroupStacks then records = M:GroupStacks(window, records) end
					table.sort(records, SortItems)
				end
				local title = CATEGORY_TITLE[key]
				local index = key:match("^custom(%d)$")
				if index then
					local custom = db.custom[tonumber(index)]
					title = custom and custom.name ~= "" and custom.name or L["Custom %s"]:format(index)
				end
				if M.OwnSectionTitle then title = M:OwnSectionTitle(key) or title end
				local note = key == "free" and db.compactEmpty and ("%d"):format(#(byKey.free or {})) or tostring(#records)
				if key == "free" then
					local total = 0
					for _, list in pairs(empties) do total = total + #list end
					note = tostring(total)
				end
				sections[#sections + 1] = { key = key, title = title, note = note, records = records }
			end
		end
		return sections
	end
	-- One grid: the normal bags, with the reagent bag, keyring and warband
	-- tabs in their own sections.
	local main = { key = "main", records = {}, reverse = db.reverse }
	sections[1] = main
	for _, group in ipairs(groups) do
		local own = (group.bag == REAGENT and REAGENT and db.reagentSection and live)
			or (group.bag == KEYRING and KEYRING and live) or (type(group.bag) == "number" and IsAccountTab(group.bag))
		if own and #group.records > 0 then
			local title = group.bag == REAGENT and L["Reagents"] or group.bag == KEYRING and (E:GameText(KEYRING_LABEL, L["Keyring"])) or L["Account bank"]
			local last = sections[#sections]
			if last.key == "warband" and IsAccountTab(group.bag) then
				for _, record in ipairs(group.records) do table.insert(last.records, record) end
			else
				sections[#sections + 1] = { key = IsAccountTab(group.bag) and "warband" or tostring(group.bag), title = title, records = group.records }
			end
		else
			for _, record in ipairs(group.records) do table.insert(main.records, record) end
		end
	end
	if #main.records == 0 then table.remove(sections, 1) end
	return sections
end

---------------------------------------------------------------------------
-- Hidden sections (per character): a section folds to its header and its
-- slots are left out. Its items still count, still sell and still search:
-- a search that finds something in a hidden section opens it, with a hint.
-- Keys are "<window>:<view>:<section>", so each view keeps its own choice.
---------------------------------------------------------------------------
E:RegisterPrivate("bagSections", { hidden = {} })

local function HiddenSections()
	local store = E:GetPrivate("bagSections")
	if type(store) ~= "table" then return nil end
	if type(store.hidden) ~= "table" then store.hidden = {} end
	return store.hidden
end

local function SectionID(window, section)
	local view = window.kind == "bank" and M.db.bankView or M.db.view
	return ("%s:%s:%s"):format(tostring(window.kind), tostring(view), tostring(section.key))
end

-- Only sections with a header can fold (the one-grid view's main grid has none).
function M:SetSectionHidden(window, section, hidden)
	local store = HiddenSections()
	if not (store and window and section and section.title) then return false end
	store[SectionID(window, section)] = hidden and true or nil
	self:UpdateWindow(window)
	return true
end

function M:HasHiddenSections()
	local store = HiddenSections()
	return store ~= nil and next(store) ~= nil
end

function M:ShowAllSections()
	local store = HiddenSections()
	if store then wipe(store) end
	self:RefreshViews()
end

local function MarkHidden(window, sections)
	local store = HiddenSections()
	for _, section in ipairs(sections) do
		section.collapsed = nil
		section.hidden = section.title and store and store[SectionID(window, section)] or nil
		if section.hidden then
			local found = 0
			if window.query then
				for _, record in ipairs(section.records) do
					if not record.empty and Matches(window.query, record) then found = found + 1 end
				end
			end
			if found > 0 then
				section.note = L["hidden, %d found"]:format(found)
			else
				section.collapsed = true
				section.note = L["hidden"]
			end
		end
	end
	window.sections = sections
	return sections
end

---------------------------------------------------------------------------
-- Windows
---------------------------------------------------------------------------
local HEADER, FOOTER, PAD, TITLE_H, BAR_H, CURRENCY_H = 60, 26, 8, 16, 30, 20
local SECTION_GAP = 12
local RAIL = E.tokens.rail.width + 4 -- the side icon rail and its gap to the slots

local function IsGuildView(window)
	return type(window.viewChar) == "string" and window.viewChar:find("^guild:") ~= nil
end

local function IsLive(window)
	return window.viewChar == E.charKey and (window.kind == "bags" or bankOpen)
end
M.IsLive = IsLive

function M:ShowCharacterMenu(window, anchor)
	E.UIKit.ContextMenu(anchor, function(_, root)
		root:CreateTitle(L["Characters"])
		local total = 0
		for _, key in ipairs(Store:Characters("ALL")) do
			local char = Store:Get(key)
			total = total + (char.money or 0)
			local updated = window.kind == "bank" and char.bankUpdated or char.updated
			local label = ("%s%s  %s"):format(ClassIcon(char.class), ClassName(char), Grey(Money(char.money or 0)))
			if key ~= E.charKey then label = label .. "  " .. Grey(Age(updated)) end
			if char.realm ~= GetRealmName() then label = label .. " " .. Grey("(" .. (char.realm or "?") .. ")") end
			local entry = root:CreateRadio(label,
				function() return window.viewChar == key end,
				function()
					window.viewChar = key
					M:UpdateWindow(window)
				end)
			if key ~= E.charKey then
				entry:CreateButton(L["Forget %s"]:format(char.name or key), function()
					M:ConfirmForget(char.name or key, key)
				end)
			end
		end
		if window.kind == "bank" then
			local guilds = Store:GuildList("ALL")
			if #guilds > 0 then
				root:CreateDivider()
				root:CreateTitle(L["Guild banks"])
				for _, gkey in ipairs(guilds) do
					local guild = Store:Guilds()[gkey]
					local key = "guild:" .. gkey
					local label = (E:TextHex("good") .. "%s|r  %s  %s"):format(guild.name or gkey, Grey(Money(guild.money or 0)), Grey(Age(guild.updated)))
					local entry = root:CreateRadio(label,
						function() return window.viewChar == key end,
						function()
							window.viewChar = key
							M:UpdateWindow(window)
						end)
					entry:CreateButton(L["Forget %s"]:format(guild.name or gkey), function()
						M:ConfirmForget(guild.name or gkey, key)
					end)
				end
			end
		end
		root:CreateDivider()
		root:CreateTitle(L["Account: %s"]:format(Money(total)))
	end, { at = "owner" })
end

local VIEW_LABEL = E:TranslateValues({ single = E.Key("Grid"), categories = E.Key("Sorted"), bags = E.Key("Bags") })

function M:ShowViewMenu(window, anchor)
	local key = window.kind == "bank" and "bankView" or "view"
	E.UIKit.ContextMenu(anchor, function(_, root)
		root:CreateTitle(L["View"])
		for _, view in ipairs({ "single", "categories", "bags" }) do
			local label = view == "single" and L["One grid"] or view == "categories" and L["Categories"] or L["Bag by bag"]
			root:CreateRadio(label, function() return M.db[key] == view end, function()
				M.db[key] = view
				M:RefreshViews()
			end)
		end
		root:CreateDivider()
		root:CreateCheckbox(L["Bag bar"], function() return M.db.bagBar end, function()
			M.db.bagBar = not M.db.bagBar
			M:RefreshViews()
		end)
		if window.kind == "bags" then
			root:CreateCheckbox(L["Tracked currencies"], function() return M.db.currencies end, function()
				M.db.currencies = not M.db.currencies
				M:RefreshViews()
			end)
		end
		-- Free space folds only in the Categories view.
		if M.db[window.kind == "bank" and "bankView" or "view"] == "categories" then
			root:CreateCheckbox(L["One slot per bag type for free space"], function() return M.db.compactEmpty end, function()
				M.db.compactEmpty = not M.db.compactEmpty
				M:RefreshViews()
			end)
		end
		if next(M.db.hiddenBags) then
			root:CreateButton(L["Show every bag again"], function()
				wipe(M.db.hiddenBags)
				M:RefreshViews()
			end)
		end
	end, { at = "owner" })
end

-- The side rail's buttons, top to bottom: sort, bank (the bank window:
-- Blizzard's bank), view, search all characters, settings. A function
-- tooltip is read each time it opens, so it names the current view.
function M.RailButtons(window, isBank)
	local page = "module:Bags"
	local viewKey = isBank and "bankView" or "view"
	local list = {
		{ key = "sort", art = E:ClientIcon("Interface\\Icons\\INV_Pet_Broom"), mono = true,
			tipTitle = isBank and (E:GameText(BAG_CLEANUP_BANK, L["Clean up bank"])) or (E:GameText(BAG_CLEANUP_BAGS, L["Clean up bags"])),
			tip = function(tooltip)
				E.UIKit.TipText(tooltip, L["Runs the game's own sort."])
				if InCombatLockdown() then
					local warn = E.tokens.text.warn
					tooltip:AddLine(L["Not in combat."], warn[1], warn[2], warn[3])
				end
				if isBank then E.UIKit.TooltipHint(tooltip, { L["Right-click"], L["clean up the account bank"] }) end
			end,
			onClick = function(_, mouse) M:Sort(window, mouse) end, options = { page = page, key = "sortButton" } },
	}
	if isBank then
		list[#list + 1] = { key = "blizzard", art = E:ClientIcon("Interface\\Icons\\INV_Misc_Note_01"), mono = true,
			tipTitle = L["Blizzard bank"], tip = L["Open the game's own bank window, e.g. to buy bank space."],
			onClick = function() M:ShowBlizzardBank() end, options = { page = page, key = "bankMode" } }
	else
		list[#list + 1] = { key = "bank", art = E:ClientIcon("Interface\\Icons\\INV_Box_02"), mono = true,
			tipTitle = L["Bank"], tip = L["Show the saved bank of the selected character."],
			onClick = function() M:ToggleBank(window.viewChar) end, options = { page = page, key = "bankMode" } }
	end
	list[#list + 1] = { key = "view", art = E:ClientIcon("Interface\\Icons\\INV_Misc_Bag_08"), mono = true,
		tipTitle = L["View"], tip = function(tooltip)
			local view = M.db and M.db[viewKey]
			E.UIKit.TipText(tooltip, L["Now: %s"]:format(VIEW_LABEL[view] or VIEW_LABEL.single))
			E.UIKit.TipText(tooltip, L["One grid, categories or bag by bag, the bag bar and more."])
		end,
		onClick = function(button) M:ShowViewMenu(window, button) end, options = { page = page, key = viewKey } }
	list[#list + 1] = { key = "all", art = "profile",
		tipTitle = L["All characters"], tip = L["Search every cached character and guild bank and list where the items are."],
		onClick = function(button)
			window.allChars = not window.allChars
			M.SetRailActive(button, window.allChars)
			M:UpdateWindow(window)
		end, options = { page = page } }
	return list
end

function M:Sort(window, button)
	if InCombatLockdown() then return end
	if window.kind == "bank" then
		if button == "RightButton" and AccountTabsShown() and C_Container.SortBank then
			C_Container.SortBank(BANK_ACCOUNT)
		elseif C_Container.SortBank and BANK_CHARACTER and #TabIDs(BANK_CHARACTER) > 0 then
			C_Container.SortBank(BANK_CHARACTER)
		elseif C_Container.SortBankBags then
			C_Container.SortBankBags()
		end
	elseif C_Container.SortBags then
		C_Container.SortBags()
	end
end

-- The corner of the mover a window hangs from. By default the bag window
-- grows up and left from its mover and the bank down and right. With "Grow
-- away from the screen edge" the corner follows the mover's half of the
-- screen, so a bag mover a layout puts on the left opens towards the middle.
function M:WindowCorner(window)
	if not self.db.growFromMover then return window.kind == "bank" and "TOPLEFT" or "BOTTOMRIGHT" end
	local x, y = window.anchor:GetCenter()
	local width, height = UIParent:GetSize()
	if not (x and y and width and height) then return window.kind == "bank" and "TOPLEFT" or "BOTTOMRIGHT" end
	return (y > height / 2 and "TOP" or "BOTTOM") .. (x < width / 2 and "LEFT" or "RIGHT")
end

-- The side a window slides in from and out to.
function M:WindowSide(window)
	if not window.anchor then return window.kind == "bank" and "LEFT" or "RIGHT" end
	return self:WindowCorner(window):match("LEFT") and "LEFT" or "RIGHT"
end

function M:PlaceWindow(window)
	local corner = self:WindowCorner(window)
	if window.corner == corner then return end
	window.corner = corner
	window:ClearAllPoints()
	window:SetPoint(corner, window.anchor, corner)
end

function M:CreateWindow(kind)
	local isBank = kind == "bank"
	local name = isBank and "EldoUI_Bank" or "EldoUI_Bags"
	local window = CreateFrame("Frame", name, UIParent)
	window.kind = kind
	window.holders = {}
	window.pool = {}
	window.titles = {}
	window.barButtons = {}
	window.currencyButtons = {}
	window.viewChar = E.charKey
	window:SetFrameStrata("HIGH")
	window:SetToplevel(true)
	window:EnableMouse(true)
	window:SetClampedToScreen(true)
	window:Hide()
	E:SetPanelTemplate(window)
	-- The window edge, title, text and accent line of every EldoUI window.
	E:SetWindowEdge(window)
	table.insert(UISpecialFrames, name)

	window.title = E.UIKit.Title(window, E.tokens.size.dialogTitle)
	-- The title sits on the close button's middle line (TOPRIGHT -5, 22
	-- tall), so the character button between them has one vertical line.
	window.title:SetPoint("LEFT", window, "TOPLEFT", 12, -16)
	window.title:SetText(isBank and (E:GameText(BANK, L["Bank"])) or (E:GameText(INVENTORY_TOOLTIP, L["Bags"])))
	window.accent = window:CreateTexture(nil, "ARTWORK")
	window.accent:SetPoint("TOPLEFT", E.pixel, -30)
	window.accent:SetPoint("TOPRIGHT", -E.pixel, -30)
	E:Hairline(window.accent, "h", 2)
	E:AccentTexture(window.accent, 1)

	local close = CreateFrame("Button", nil, window, "UIPanelCloseButtonNoScripts")
	close:SetSize(22, 22)
	close:SetPoint("TOPRIGHT", -3, -5)
	close:SetScript("OnClick", function() M:CloseWindow(window) end)
	if E.SkinCloseButton then E:SkinCloseButton(close) end
	window.close = close

	-- The side icon rail (DESIGN.md §0a rule 6): every toolbar action in a
	-- fixed order on the window's right edge, under the title line. Each
	-- tooltip names its button; Ctrl-click opens its setting.
	local rail = E.UIKit.IconRail(window, { side = "RIGHT", buttons = M.RailButtons(window, isBank) })
	rail:SetPoint("TOPRIGHT", window, "TOPRIGHT", -E.pixel, -(30 + E.pixel * 2))
	rail:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -E.pixel, FOOTER)
	local buttons = rail.buttons
	buttons.sort:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	window.rail = rail
	window.sort = buttons.sort
	window.bankButton = buttons.bank
	window.blizzard = buttons.blizzard
	window.viewButton = buttons.view
	window.allButton = buttons.all
	-- The active "All characters" search shows a short accent bar on the
	-- button's inner edge (the accent means on, DESIGN.md §0a rule 2).
	local mark = buttons.all:CreateTexture(nil, "OVERLAY")
	mark:SetPoint("TOPLEFT", buttons.all, "TOPLEFT", -3, -2)
	mark:SetPoint("BOTTOMLEFT", buttons.all, "BOTTOMLEFT", -3, 2)
	mark:SetWidth(2)
	E:AccentTexture(mark)
	mark:Hide()
	buttons.all.activeMark = mark

	local character = ToolButton(window, 120, 20, "", nil, L["Characters"], L["View another character's items, or forget one."])
	character:SetPoint("LEFT", window.title, "RIGHT", 8, 0)
	character:SetPoint("RIGHT", close, "LEFT", -6, 0)
	character.text:SetJustifyH("LEFT")
	character:SetScript("OnClick", function(button) M:ShowCharacterMenu(window, button) end)
	window.character = character

	local search = CreateFrame("EditBox", name .. "Search", window, "SearchBoxTemplate")
	E:SearchHint(search)
	search:SetHeight(20)
	search:SetPoint("TOPLEFT", PAD + 6, -36)
	search:SetPoint("TOPRIGHT", window, "TOPRIGHT", -(PAD + RAIL), -36)
	search:SetAutoFocus(false)
	if E.SkinEditBox then E:SkinEditBox(search) end
	search:HookScript("OnTextChanged", function(box)
		window.searchText = box:GetText()
		window.query = ParseQuery(window.searchText)
		M:Refilter(window, true)
	end)
	window.search = search

	-- "No matches": a short muted line at the right end of the search box,
	-- beside the clear control, shown only when a search finds nothing in
	-- this window. Items keep their places (dimmed); nothing is covered.
	local noMatch = E.UIKit.Text(search, E.tokens.size.small, "RIGHT", "secondary")
	local clear = search.clearButton
	if clear then
		noMatch:SetPoint("RIGHT", clear, "LEFT", -4, 0)
	else
		noMatch:SetPoint("RIGHT", search, "RIGHT", -20, 0)
	end
	noMatch:SetText(L["No matches"])
	noMatch:Hide()
	window.noMatch = noMatch
	search.eldoInsets = { search:GetTextInsets() }

	-- "Move these": only in the bag window, only while a target is
	-- open and the search shows something. It sits between the search box
	-- and "All".
	if not isBank then
		local move = ToolButton(window, 84, 20, L["Move these"], nil, L["Move these"], function(tooltip)
			E.UIKit.TipText(tooltip, M:MoveTip())
		end)
		move:SetPoint("TOPRIGHT", window, "TOPRIGHT", -(PAD + RAIL), -36)
		move.text:SetJustifyH("CENTER")
		move:SetScript("OnClick", function() M:MoveSearched(window) end)
		move:Hide()
		window.moveButton = move
	end

	-- Bag bar (under the search box when shown).
	window.bar = CreateFrame("Frame", nil, window)
	window.bar:SetPoint("TOPLEFT", PAD, -HEADER)
	window.bar:SetPoint("TOPRIGHT", -(PAD + RAIL), -HEADER)
	window.bar:SetHeight(BAR_H - 6)

	-- Tracked currencies (over the footer).
	window.currencyRow = CreateFrame("Frame", nil, window)
	window.currencyRow:SetPoint("BOTTOMLEFT", PAD, FOOTER)
	window.currencyRow:SetPoint("BOTTOMRIGHT", -(PAD + RAIL), FOOTER)
	window.currencyRow:SetHeight(CURRENCY_H - 2)

	window.slotsText = E.UIKit.Text(window, E.tokens.size.label, "LEFT", "secondary")
	window.slotsText:SetPoint("BOTTOMLEFT", PAD, 8)
	window.slotsText:SetWordWrap(false)
	local slots = CreateFrame("Frame", nil, window)
	slots:SetAllPoints(window.slotsText)
	slots:EnableMouse(true)
	slots:SetScript("OnEnter", function() M:ShowSlotFooter(window) end)
	local function CloseSlotTip(anchor)
		if GameTooltip:IsOwned(anchor) then GameTooltip:Hide() end
	end
	slots:SetScript("OnLeave", CloseSlotTip)
	slots:SetScript("OnHide", CloseSlotTip)
	window.slots = slots
	window.extraText = E.UIKit.Text(window, E.tokens.size.label, "LEFT", "secondary")
	window.extraText:SetPoint("LEFT", window.slotsText, "RIGHT", 10, 0)
	window.extraText:SetWordWrap(false)
	if window.kind == "bags" then
		-- The backpack's locked slots on an account without an authenticator.
		local locked = CreateFrame("Frame", nil, window)
		locked:SetSize(64, 16)
		locked:SetPoint("LEFT", window.extraText, "RIGHT", 8, 0)
		locked.text = E.UIKit.Text(locked, E.tokens.size.label, "LEFT", "secondary")
		locked.text:SetPoint("LEFT")
		locked.text:SetText(L["+4 locked"])
		locked.text:SetWordWrap(false)
		locked:EnableMouse(true)
		locked:SetScript("OnEnter", function(anchor)
			GameTooltip:SetOwner(anchor, "ANCHOR_TOP")
			E.UIKit.TipTitle(GameTooltip, L["Locked backpack slots"])
			E.UIKit.TipText(GameTooltip, L["Secure your account with an authenticator and the game adds 4 slots to your backpack."])
			GameTooltip:Show()
		end)
		locked:SetScript("OnLeave", GameTooltip_Hide)
		locked:Hide()
		window.lockedSlots = locked
	end

	local gold = CreateFrame("Frame", nil, window)
	gold:SetSize(140, 18)
	gold:SetPoint("BOTTOMRIGHT", -PAD, 5)
	gold.text = E.UIKit.Text(gold, E.tokens.size.body, "RIGHT")
	gold.text:SetPoint("RIGHT")
	gold.text:SetWordWrap(false)
	gold:SetScript("OnEnter", function(anchor)
		GameTooltip:SetOwner(anchor, "ANCHOR_TOP")
		M:AddGoldLines(GameTooltip)
		if M.AddWorthLines then M:AddWorthLines(GameTooltip, window) end
		GameTooltip:Show()
	end)
	gold:SetScript("OnLeave", GameTooltip_Hide)
	-- Ctrl-click opens the setting (item slots keep the game's Ctrl-click,
	-- the dressing room preview).
	E:BindOptionsLink(gold, { page = "module:Bags", key = "gold" })
	window.gold = gold

	-- "All characters" results.
	local results = CreateFrame("Frame", nil, window)
	results:SetPoint("TOPLEFT", window, "BOTTOMLEFT", 0, -4)
	results:SetPoint("TOPRIGHT", window, "BOTTOMRIGHT", 0, -4)
	results:SetHeight(40)
	E:SetPanelTemplate(results)
	-- Long results scroll inside the room the screen has.
	results.area = E.UIKit.ScrollArea(results)
	results.area:SetPoint("TOPLEFT", PAD, -PAD)
	results.area:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	results.rows = {}
	results:Hide()
	window.results = results

	window:SetScript("OnShow", function() M:WatchCooldowns() end)
	window:SetScript("OnHide", function()
		M:WatchCooldowns()
		window.tourOpening = nil
		search:ClearFocus()
		window.highlightBag = nil
		if M.db.clearSearch and search:GetText() ~= "" then search:SetText("") end
		if not isBank then
			if M.db.newGlow and C_NewItems and C_NewItems.ClearAll then C_NewItems.ClearAll() end
			window.eldoOnly = nil
			-- Never the game's CloseAllBags() from here (F24, M:CloseGameBags).
			if M:AnyBagOpen() then M:CloseGameBags() end
		elseif bankOpen and not M.showingBlizzardBank then
			local closeBank = (C_Bank and C_Bank.CloseBankFrame) or CloseBankFrame
			if closeBank then closeBank() end
		end
	end)

	local anchorName = isBank and "EldoUI_BankAnchor" or "EldoUI_BagsAnchor"
	local anchor = _G[anchorName] or CreateFrame("Frame", anchorName, UIParent)
	anchor:SetSize(520, 300)
	if not E.movers[anchorName] then
		if isBank then
			E:CreateMover(anchor, anchorName, L["Bank"], { "TOPLEFT", "UIParent", "TOPLEFT", 20, -120 }, { sample = false })
		else
			E:CreateMover(anchor, anchorName, L["Bags"], { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -19, 330 }, { sample = false })
		end
	end
	window.anchor = anchor
	self:PlaceWindow(window)
	windows[kind] = window
	return window
end

-- Section titles are fold dividers (DESIGN.md §0a rule 4): the name and
-- a muted note centered between two thin accent lines, the fold chevron
-- on the right. A click folds the section or shows it again (saved per
-- character); a right-click opens its menu (hide, "Move these"). Folding
-- only changes what the window shows.
local function GetTitle(window, index)
	local title = window.titles[index]
	if not title then
		title = E.UIKit.FoldDivider(window, { label = "", onToggle = function(_, divider)
			local section = divider.section
			if not section then return end
			-- A hidden section a search opened folds back only by showing it.
			M:SetSectionHidden(window, section, not section.hidden)
		end })
		title:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		local fold = title:GetScript("OnClick")
		title:SetScript("OnClick", function(self, mouseButton)
			-- An item held on the cursor is filed into this category instead.
			if mouseButton ~= "RightButton" and M.DropOnTitle and M:DropOnTitle(window, self) then return end
			if mouseButton == "RightButton" then
				if self.section then M:ShowSectionMenu(window, self.section, self) end
			else
				fold(self, mouseButton)
			end
		end)
		title:SetScript("OnReceiveDrag", function(self) if M.DropOnTitle then M:DropOnTitle(window, self) end end)
		E.UIKit.Tooltip(title, nil, nil, { { L["Click"], L["fold or unfold"] }, { L["Right-click"], L["more"] } })
		title:Hide()
		-- Older callers reach the click frame as title.hit.
		title.hit = title
		window.titles[index] = title
	end
	return title
end

-- The width a section's title needs. The name and note sit in the middle,
-- so each half holds half the name, the 8 px gap, a short 8 px line and
-- the 20 px the chevron takes on the right (kept on the left too, so the
-- name stays centered).
local function TitleWidth(window, section)
	local probe = window.titleProbe
	if not probe then
		probe = E.UIKit.Text(window, E.tokens.size.label, "LEFT")
		probe:Hide()
		window.titleProbe = probe
	end
	probe:SetText(section.title .. (section.note and ("  " .. section.note) or ""))
	return math.ceil(probe:GetStringWidth()) + 2 * (8 + 8 + 20)
end

-- Place every section; returns the content height. Small sections share a
-- row when "Pack sections" is on.
function M:PlaceSections(window, sections, columns, top, placeButton)
	local db = self.db
	local cell = db.size + db.spacing
	local contentWidth = columns * cell - db.spacing
	local x, y, bandHeight = 0, 0, 0
	local titleIndex = 0
	for _, section in ipairs(sections) do
		local count = section.collapsed and 0 or #section.records
		local width = math.max(1, math.min(count, columns))
		local rows = math.ceil(count / width)
		local titled = section.title ~= nil
		local height = (titled and TITLE_H or 0) + rows * cell - db.spacing
		local widthPx = width * cell - db.spacing
		if section.collapsed then
			width = math.min(columns, 4)
			widthPx = width * cell - db.spacing
			height = TITLE_H
		end
		-- A narrow section gets the room its title needs (up to the window).
		if titled then widthPx = math.min(math.max(widthPx, TitleWidth(window, section)), contentWidth) end
		if x > 0 and not (db.packSections and x + SECTION_GAP + widthPx <= contentWidth) then
			y = y + bandHeight + SECTION_GAP / 2
			x, bandHeight = 0, 0
		elseif x > 0 then
			x = x + SECTION_GAP
		end
		if titled then
			titleIndex = titleIndex + 1
			local title = GetTitle(window, titleIndex)
			title:ClearAllPoints()
			title:SetPoint("TOPLEFT", window, "TOPLEFT", PAD + x, -top - y)
			title:SetWidth(widthPx)
			title:SetHeight(TITLE_H)
			title.section = section
			title.kitTipTitle = section.title
			title.label:SetWidth(0)
			title:SetLabel(section.title .. (section.note and ("  " .. Grey(section.note)) or ""))
			title:SetFolded(section.collapsed, true)
			-- A long name stops before the chevron.
			title.label:SetWidth(math.min(math.ceil(title.label:GetStringWidth()) + 1, math.max(widthPx - 40, 1)))
			title:Show()
		end
		local slotTop = y + (titled and TITLE_H or 0)
		for index, record in ipairs(section.collapsed and {} or section.records) do
			local position = section.reverse and (count - index + 1) or index
			local column = (position - 1) % width
			local row = math.floor((position - 1) / width)
			placeButton(record, PAD + x + column * cell, -top - slotTop - row * cell)
		end
		x = x + widthPx
		bandHeight = math.max(bandHeight, height)
	end
	for index = titleIndex + 1, #window.titles do
		window.titles[index]:Hide()
		window.titles[index].section = nil
	end
	return y + bandHeight
end

local function HideAll(window)
	for _, holder in pairs(window.holders) do
		-- pairs: a slot that was never drawn (free space shown as one
		-- slot, a grouped stack) leaves a gap in the list.
		for _, button in pairs(holder.buttons) do button:Hide() end
	end
	for _, button in ipairs(window.pool) do button:Hide() end
end

-- Bags shown in a live window, with hidden ones left out.
local function VisibleIDs(window)
	local ids = window.kind == "bank" and BankBagIDs() or BagIDs()
	local list = {}
	for _, bag in ipairs(ids) do
		if not M.db.hiddenBags[bag] then list[#list + 1] = bag end
	end
	return list, ids
end

-- General-purpose slots, including those in bags hidden from this view.
local function FixedBankTabs()
	return C_Bank and E.PlainCall(C_Bank.ShouldUsePlayerBagsInBank) == false
end

local function SlotCounts(allIDs, bank)
	local free, total, known, rows = E.BagCache:GeneralSlots(allIDs, bank and FixedBankTabs(), true)
	return total, total - free, known, rows
end

-- What a live window's slot grid depends on besides the items: the view
-- and every bag's size and hidden state. While it stays the same, a bag
-- change can repaint its slots in place (M:RepaintBags).
local function LiveShape(window)
	local db = M.db
	local _, allIDs = VisibleIDs(window)
	local parts = { window.kind == "bank" and db.bankView or db.view, tostring(db.reagentSection) }
	for _, bag in ipairs(allIDs) do
		parts[#parts + 1] = ("%s=%d%s"):format(tostring(bag), NumSlots(bag), db.hiddenBags[bag] and "h" or "")
	end
	return table.concat(parts, ",")
end

-- The bag window's slot buttons, made ahead out of combat: the game allows
-- no new item buttons in combat, so the first open of a session (or of a
-- bigger bag) in combat would wait for the fight to end. A few buttons a
-- frame, so logging in stays smooth; sliced work waits out a fight. The
-- bank window stays as it is: it opens at an NPC.
local prebuilding
M.prebuildEvents = {}
function M:PrebuildLiveSlots()
	local window = windows.bags
	if (prebuilding and not prebuilding.done) or not (window and self.active) then return end
	prebuilding = E:RunSliced(function()
		for _, bag in ipairs(BagIDs(true)) do
			for slot = 1, NumSlots(bag) do
				local holder = window.holders[bag]
				if not (holder and holder.buttons[slot]) then
					local button = GetLiveSlot(window, bag, slot)
					if not window:IsShown() then button:Hide() end
					E.SliceYield()
				end
			end
		end
	end, 3)
end

function M:LayoutLive(window, columns, top)
	local ids, allIDs = VisibleIDs(window)
	-- Buttons can't be made in combat; finish after combat.
	if InCombatLockdown() then
		for _, bag in ipairs(ids) do
			local holder = window.holders[bag]
			for slot = 1, NumSlots(bag) do
				if not (holder and holder.buttons[slot]) then
					if not window.waiting then
						window.waiting = true
						E:RunOutOfCombat(function() window.waiting = nil; M:UpdateWindow(window) end)
					end
					return nil
				end
			end
		end
	end
	local groups = {}
	for _, bag in ipairs(ids) do
		local records = {}
		for slot = 1, NumSlots(bag) do records[#records + 1] = LiveRecord(bag, slot) end
		groups[#groups + 1] = { bag = bag, records = records }
	end
	local total, used, known, rows = SlotCounts(allIDs, window.kind == "bank")
	HideAll(window)
	local sections = MarkHidden(window, BuildSections(window, groups, true))
	local height = self:PlaceSections(window, sections, columns, top, function(record, x, y)
		local button = GetLiveSlot(window, record.bag, record.slot)
		button:SetSize(self.db.size, self.db.size)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", window, "TOPLEFT", x, y)
		button:Show()
		PaintLive(window, button, record)
	end)
	window.liveShape = LiveShape(window)
	return height, total, used, known, rows
end

function M:LayoutOffline(window, columns, top)
	local list, layout = Store:View(window.viewChar, window.kind)
	local groups = {}
	local index = 0
	if #layout > 0 then
		for _, entry in ipairs(layout) do
			local bag, size, title = entry[1], entry[2], entry[3]
			local records = {}
			for _ = 1, size do
				index = index + 1
				local short, count = Decode(list[index])
				if short then
					local id = ItemIDOf(short)
					local quality = id and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
					records[#records + 1] = { bag = bag, index = index, short = short, id = id, quality = quality, count = count }
				else
					records[#records + 1] = { bag = bag, index = index, empty = true }
				end
			end
			if not self.db.hiddenBags[bag] or IsGuildView(window) then
				groups[#groups + 1] = { bag = bag, title = title, records = records }
			end
		end
	end
	-- Data saved before bag layouts were kept: one group.
	if index < #list then
		local records = {}
		for rest = index + 1, #list do
			local short, count = Decode(list[rest])
			local id = ItemIDOf(short)
			records[#records + 1] = short and { bag = 0, index = rest, short = short, id = id, count = count,
				quality = id and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id) } or { bag = 0, index = rest, empty = true }
		end
		groups[#groups + 1] = { bag = 0, records = records }
	end
	local used, total = 0, 0
	for _, group in ipairs(groups) do
		for _, record in ipairs(group.records) do
			if group.bag ~= KEYRING or not KEYRING then
				total = total + 1
				if not record.empty then used = used + 1 end
			end
		end
	end
	HideAll(window)
	local sections = MarkHidden(window, BuildSections(window, groups, false))
	local slot = 0
	local height = self:PlaceSections(window, sections, columns, top, function(record, x, y)
		slot = slot + 1
		local button = GetOfflineSlot(window, slot)
		button:SetSize(self.db.size, self.db.size)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", window, "TOPLEFT", x, y)
		button:Show()
		PaintOffline(window, button, record)
	end)
	return height, total, used
end

-- Hovering a bag button or a slot fades every other bag's slots.
function M:HighlightBag(window, bag)
	if window.highlightBag == bag then return end
	if bag ~= nil and not window.barHover then return end
	window.highlightBag = bag
	self:Refilter(window)
end

-- A new search or a bag hover only changes which slots are faded: the
-- shown slots fade again where they are. A search in a window with hidden
-- sections redraws it, since the search opens the sections it finds in.
function M:Refilter(window, searched)
	if not (window and window:IsShown()) then return end
	if searched then
		for _, section in ipairs(window.sections or {}) do
			if section.hidden then return self:UpdateWindow(window) end
		end
	end
	self.refilters = (self.refilters or 0) + 1
	waitingForInfo = false
	if IsLive(window) then
		local own = window.viewChar == E.charKey
		for _, holder in pairs(window.holders or {}) do
			for _, button in pairs(holder.buttons or {}) do
				local record = button.eldoRecord
				if record and button:IsShown() then
					button:SetAlpha(SlotAlpha(window, record))
					if own and M.MarkFade then M:MarkFade(button, record) end
				end
			end
		end
	else
		for _, button in pairs(window.pool or {}) do
			local record = button.eldoOffline
			if record and button:IsShown() then button:SetAlpha(SlotAlpha(window, record)) end
		end
	end
	self:UpdateMoveButton(window)
	self:UpdateNoMatch(window)
	if searched then
		E:Debounce("Bags:results:" .. tostring(window.kind), 0.15, function() M:UpdateResults(window) end)
	end
end

-- At most this many lines: an item line counts, and so does each line
-- under it for a character or a guild bank.
local RESULT_LINES, RESULT_ROW = 120, 18

-- The results panel opens on the side of the bag window with more room,
-- and is never taller than that room; the rest scrolls.
local function PlaceResults(window, results, wanted)
	local scale, parentScale = window:GetEffectiveScale() or 1, UIParent:GetEffectiveScale() or 1
	local screen = (UIParent:GetHeight() or 768) * parentScale / scale
	local bottom, top = window:GetBottom() or 0, window:GetTop() or screen
	local below, above = bottom - 8, screen - top - 8
	local up = wanted > below and above > below
	local height = math.max(math.min(wanted, up and above or below), RESULT_ROW + PAD * 2)
	results:ClearAllPoints()
	if up then
		results:SetPoint("BOTTOMLEFT", window, "TOPLEFT", 0, 4)
		results:SetPoint("BOTTOMRIGHT", window, "TOPRIGHT", 0, 4)
	else
		results:SetPoint("TOPLEFT", window, "BOTTOMLEFT", 0, -4)
		results:SetPoint("TOPRIGHT", window, "BOTTOMRIGHT", 0, -4)
	end
	results:SetHeight(height)
	results.up = up
end

local function ResultRow(results, index)
	local rows = results.rows
	local row = rows[index]
	if row then return row end
	row = CreateFrame("Button", nil, results.area.child)
	row:SetHeight(RESULT_ROW)
	row.left = E.UIKit.Text(row, E.tokens.size.label, "LEFT")
	row.left:SetPoint("LEFT", 4, 0)
	row.right = E.UIKit.Text(row, E.tokens.size.label, "RIGHT")
	row.right:SetPoint("RIGHT", -4, 0)
	if E.SkinRow then E:SkinRow(row) end
	row:SetScript("OnEnter", function(entryRow)
		if not entryRow.short then return end
		GameTooltip:SetOwner(entryRow, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(entryRow.short)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	-- Shift-click links the item in the chat, like a bag slot.
	row:SetScript("OnClick", function(entryRow)
		if not entryRow.short then return end
		local link = select(2, C_Item.GetItemInfo(entryRow.short))
		if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
	end)
	rows[index] = row
	return row
end

function M:UpdateResults(window)
	local results = window.results
	if not (window.allChars and window.query) then
		results:Hide()
		return
	end
	local rows = results.rows
	local lines = {}
	local function Add(line)
		if #lines >= RESULT_LINES then return false end
		lines[#lines + 1] = line
		return true
	end
	for _, entry in ipairs(self:FindAll(window.searchText)) do
		local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(entry.id) or entry.short
		local quality = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(entry.id)
		local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
		local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(entry.id)
		local label = (icon and ("|T%s:14:14:0:0:64:64:5:59:5:59|t "):format(icon) or "")
			.. (color and color.hex or "|cffffffff") .. (name or "?") .. "|r"
		if not Add({ left = label, right = tostring(entry.total), short = entry.short }) then break end
		for key, counts in pairs(entry.chars) do
			local char = Store:Get(key)
			if char then
				Add({ left = "    " .. ClassIcon(char.class, 12) .. ClassName(char), right = Breakdown(counts), short = entry.short })
			end
		end
		for key, count in pairs(entry.guilds) do
			local guild = Store:Guilds()[key]
			Add({ left = "    " .. E:TextHex("good") .. (guild and guild.name or key) .. "|r",
				right = Grey(LOCATION_LABEL.guild) .. " " .. count, short = entry.short })
		end
	end
	if #lines == 0 then lines[1] = { left = Grey(L["Nothing found on any character."]) } end
	for index, line in ipairs(lines) do
		local row = ResultRow(results, index)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -(index - 1) * RESULT_ROW)
		row:SetPoint("TOPRIGHT", 0, -(index - 1) * RESULT_ROW)
		row.left:SetText(line.left)
		row.right:SetText(line.right or "")
		row.short = line.short
		row:Show()
	end
	for index = #lines + 1, #rows do rows[index]:Hide() end
	local area = results.area
	area.child:SetHeight(#lines * RESULT_ROW)
	PlaceResults(window, results, PAD * 2 + #lines * RESULT_ROW)
	results:Show()
	area:ScrollToTop()
	area:Update()
end

-- The backpack slots the game holds back until the account has an
-- authenticator (IsAccountSecured false).
local function BackpackLocked()
	if not IsAccountSecured then return false end
	local ok, secured = pcall(IsAccountSecured)
	return ok and not E.Secret(secured) and secured == false
end

local function ShowLockedSlots(window, live)
	if window.lockedSlots then window.lockedSlots:SetShown(live and BackpackLocked() or false) end
end

-- Keep the compact special-bag and ammunition summary beside the main count.
function M:SpecialBagText(rows)
	local parts = {}
	for _, row in ipairs(rows) do
		if row.special and row.bag > 0 and row.free then
			local short = BagName(row.bag):match("(%S+)$") or L["Bag"]
			parts[#parts + 1] = ("%s %d"):format(short, row.free)
		end
	end
	local ammo = self:AmmoCount()
	if not ammo then return table.concat(parts, "  ") end
	local low = ammo < self.db.ammoThreshold
	local ammoText = (low and E:TextHex("bad") or "") .. L["Ammo %d"]:format(ammo) .. (low and "|r" or "")
	parts[#parts + 1] = ammoText
	return table.concat(parts, "  "), ammoText
end

function M:AddSlotFooterLines(tooltip, window)
	local capacity = window.slotCapacity
	E.UIKit.TipTitle(tooltip, capacity.rows and L["General bag slots"] or L["Saved bag slots"])
	E.UIKit.TipText(tooltip, capacity.known and L["%d / %d free"]:format(capacity.total - capacity.used, capacity.total)
		or L["Slot count unavailable"])
	if capacity.extraClipped and capacity.ammo then E.UIKit.TipText(tooltip, capacity.ammo) end
	local specialHeading = false
	for _, special in ipairs({ false, true }) do
		for _, row in ipairs(capacity.rows or {}) do
			if (row.special == true) == special then
				if special and not specialHeading then
					E.UIKit.TipText(tooltip, L["Special bags"])
					specialHeading = true
				end
				tooltip:AddDoubleLine(BagName(row.bag), row.free and L["%d / %d free"]:format(row.free, row.total)
					or L["Slot count unavailable"])
			end
		end
	end
end

function M:ShowSlotFooter(window)
	if not window.slotCapacity then return end
	GameTooltip:SetOwner(window.slots, "ANCHOR_TOP")
	self:AddSlotFooterLines(GameTooltip, window)
	if self.AddWorthLines then self:AddWorthLines(GameTooltip, window) end
	GameTooltip:Show()
end

function M:UpdateCapacityFooter(window, total, used, known, rows)
	local capacity = { total = total, used = used, known = known, rows = rows }
	window.slotCapacity = capacity
	local free = known and total - used
	local slots = window.slotsText
	local text = L["? free"]
	if known then
		text = self.db.footerSlots == "used" and ("%d / %d"):format(used, total) or L["%d free"]:format(free)
	end
	slots:SetText(text)
	E.UIKit.Paint(slots, rows and free == 0 and "bad" or rows and free and free <= self.LOW_SPACE and "warn" or "secondary")
	local extra, locked, gold = window.extraText, window.lockedSlots, window.gold
	local summary
	if rows and window.kind == "bags" then summary, capacity.ammo = self:SpecialBagText(rows) end
	extra:SetText(summary or "")
	ShowLockedSlots(window, rows ~= nil)

	local function TextWidth(label)
		return math.ceil(label.GetUnboundedStringWidth and label:GetUnboundedStringWidth() or label:GetStringWidth()) + 1
	end
	local available = math.max(1, window:GetWidth() - PAD * 2)
	local slotWidth = math.min(TextWidth(slots), available)
	slots:SetWidth(slotWidth)
	available = available - slotWidth
	if gold:IsShown() then
		local width = math.min(TextWidth(gold.text) + 1, math.max(0, available - 8))
		gold:SetWidth(width)
		gold.text:SetWidth(math.max(1, width))
		available = math.max(0, available - width - 8)
	end
	local lockWidth = 0
	if locked and locked:IsShown() then
		lockWidth = math.min(TextWidth(locked.text) + 1, math.max(0, available - 8))
		locked:SetWidth(lockWidth)
		locked.text:SetWidth(math.max(1, lockWidth))
		available = math.max(0, available - lockWidth - 8)
	end
	local wantExtra = summary and summary ~= "" and TextWidth(extra) or 0
	local extraWidth = math.min(wantExtra, math.max(0, available - 10))
	capacity.extraClipped = extraWidth < wantExtra
	extra:SetWidth(math.max(1, extraWidth))
	extra:SetShown(extraWidth > 0)
	if lockWidth > 0 then
		locked:ClearAllPoints()
		locked:SetPoint("LEFT", extraWidth > 0 and extra or slots, "RIGHT", 8, 0)
	end
	if self.RefreshLowestValueMark then self:RefreshLowestValueMark(window) end
	if GameTooltip:IsOwned(window.slots) and GameTooltip:IsShown() then
		GameTooltip:ClearLines()
		self:AddSlotFooterLines(GameTooltip, window)
		if self.AddWorthLines then self:AddWorthLines(GameTooltip, window) end
		GameTooltip:Show()
	end
end

---------------------------------------------------------------------------
-- Bag bar inside the windows: show, hide and swap single bags / bank tabs
---------------------------------------------------------------------------
local BAR_SIZE = 22

local function InventorySlotOf(bag)
	if bag == nil or bag <= 0 or bag == KEYRING then return end
	local ok, slot = pcall(C_Container.ContainerIDToInventoryID, bag)
	return ok and slot or nil
end

-- Entries for the bar: { bag, icon, kind, bankSlot, bought, tab }. At the
-- bank, the first tab the game sells next carries `buy` (its bank type):
-- BankActions.lua puts the game's own purchase button over it.
local function CanBuyTab(bankType)
	if not (bankOpen and bankType and C_Bank and C_Bank.CanPurchaseBankTab) then return false end
	local ok, can = pcall(C_Bank.CanPurchaseBankTab, bankType)
	return ok and can == true
end

local function BarEntries(window)
	local entries = {}
	if window.kind == "bags" then
		for bag = 0, NUM_BAG_SLOTS do
			local invSlot = InventorySlotOf(bag)
			local icon = bag == 0 and "Interface\\Buttons\\Button-Backpack-Up" or (invSlot and GetInventoryItemTexture("player", invSlot))
			entries[#entries + 1] = { bag = bag, icon = icon, kind = "bag", invSlot = invSlot }
		end
		if REAGENT and InventorySlotOf(REAGENT) then
			local invSlot = InventorySlotOf(REAGENT)
			entries[#entries + 1] = { bag = REAGENT, icon = GetInventoryItemTexture("player", invSlot), kind = "bag", invSlot = invSlot }
		end
		if KEYRING and M.db.keyring and NumSlots(KEYRING) > 0 then
			entries[#entries + 1] = { bag = KEYRING, icon = E:ClientIcon("Interface\\Icons\\INV_Misc_Key_03"), kind = "keyring" }
		end
		return entries
	end
	if not (C_Bank and BANK_CHARACTER and C_Bank.FetchMaxNumBankTabs) then return entries end
	local first = Enum.BagIndex.CharacterBankTab_1
	local okTabs, tabs = pcall(C_Bank.FetchPurchasedBankTabData, BANK_CHARACTER)
	local bought = {}
	if okTabs and type(tabs) == "table" then
		for _, tab in ipairs(tabs) do bought[tab.ID] = tab end
	end
	local okMax, max = pcall(C_Bank.FetchMaxNumBankTabs, BANK_CHARACTER)
	for index = 1, okMax and max or 0 do
		local bag = first and first + index - 1
		local tab = bag and bought[bag]
		local icon = tab and tab.icon
		-- Bank tabs past the first hold a bag put into a bank bag slot.
		if index > 1 and tab and CHAR_TABS and ItemLocation and C_Item.GetItemIcon then
			local location = ItemLocation:CreateFromBagAndSlot(CHAR_TABS, index)
			local ok, itemIcon = pcall(C_Item.GetItemIcon, location)
			if ok and itemIcon then icon = itemIcon end
		end
		entries[#entries + 1] = { bag = bag, icon = E:ClientIcon(icon, E:ClientIcon("Interface\\Icons\\INV_Box_02")), kind = "bank",
			bought = tab ~= nil, bankSlot = index, tab = tab }
	end
	if CanBuyTab(BANK_CHARACTER) then
		for _, entry in ipairs(entries) do
			if not entry.bought then
				entry.buy = BANK_CHARACTER
				break
			end
		end
	end
	if AccountTabsShown() then
		local okAccount, accountTabs = pcall(C_Bank.FetchPurchasedBankTabData, BANK_ACCOUNT)
		if okAccount and type(accountTabs) == "table" then
			for _, tab in ipairs(accountTabs) do
				entries[#entries + 1] = { bag = tab.ID, icon = tab.icon, kind = "account", bought = true, tab = tab }
			end
			if CanBuyTab(BANK_ACCOUNT) then
				entries[#entries + 1] = { kind = "account", bought = false, buy = BANK_ACCOUNT }
			end
		end
	end
	return entries
end

local function BarTooltip(button)
	local entry = button.entry
	if not entry then return end
	GameTooltip:SetOwner(button, "ANCHOR_TOP")
	local shown = false
	if entry.invSlot then
		shown = GameTooltip:SetInventoryItem("player", entry.invSlot)
	elseif entry.kind == "bank" and entry.bought and entry.bankSlot > 1 and CHAR_TABS then
		shown = GameTooltip:SetBagItem(CHAR_TABS, entry.bankSlot)
	end
	if not shown then
		if entry.kind == "bank" and not entry.bought then
			GameTooltip:SetText(E:GameText(BANK_BAG_PURCHASE, L["Buy bank space"]))
			E.UIKit.TipText(GameTooltip, L["Bank tabs are bought in order at the bank: the next one shows a plus."])
		else
			GameTooltip:SetText(entry.tab and entry.tab.name ~= "" and entry.tab.name or BagName(entry.bag))
		end
	end
	if entry.bought ~= false then
		local hidden = M.db.hiddenBags[entry.bag]
		if hidden then E.UIKit.TipText(GameTooltip, L["Hidden in the window."]) end
		E:TooltipHint(GameTooltip, { L["Click"], hidden and L["show in the window"] or L["hide in the window"] })
		if entry.kind == "bag" and entry.bag > 0 then
			E:TooltipHint(GameTooltip, { L["Drag"], L["take the bag out, drop a bag here to swap"] }, { L["Right-click"], L["options"] })
		elseif entry.kind == "bag" or bankOpen then
			E:TooltipHint(GameTooltip, { L["Right-click"], L["options"] })
		end
	end
	GameTooltip:Show()
end

-- Put the item on the cursor into this bag slot (a player click or drop).
local function DropOnBar(entry)
	if not (CursorHasItem and CursorHasItem()) then return false end
	if entry.kind == "bag" then
		if entry.bag == 0 then
			if PutItemInBackpack then PutItemInBackpack() end
		elseif entry.invSlot and PutItemInBag then
			PutItemInBag(entry.invSlot)
		end
		return true
	end
	if entry.kind == "bank" and bankOpen and entry.bankSlot > 1 and CHAR_TABS then
		C_Container.PickupContainerItem(CHAR_TABS, entry.bankSlot)
		return true
	end
	return false
end

local SORT_FLAGS = {
	{ "ClassEquipment", BAG_FILTER_EQUIPMENT or E.Key("Equipment") },
	{ "ClassConsumables", BAG_FILTER_CONSUMABLES or E.Key("Consumables") },
	{ "ClassProfessionGoods", BAG_FILTER_PROFESSION_GOODS or E.Key("Trade goods") },
	{ "ClassJunk", BAG_FILTER_JUNK or E.Key("Junk") },
	{ "ClassQuestItems", BAG_FILTER_QUEST_ITEMS or E.Key("Quest items") },
}

-- Bank tabs keep "ignore when sorting" in their deposit settings, the
-- same flag Blizzard's tab settings window sets. It can only change while
-- the bank is open; the name, icon and other settings stay as they are.
local function TabFlags(value, flag, on)
	if FlagsUtil and FlagsUtil.Combine then return FlagsUtil.Combine(value or 0, flag, on) end
	if on then return bit.bor(value or 0, flag) end
	return bit.band(value or 0, bit.bnot(flag))
end

local function TabHasFlag(value, flag)
	if FlagsUtil and FlagsUtil.IsSet then return FlagsUtil.IsSet(value or 0, flag) end
	return bit.band(value or 0, flag) ~= 0
end

local function FreshTab(bankType, id)
	local ok, tabs = pcall(C_Bank.FetchPurchasedBankTabData, bankType)
	if not ok or type(tabs) ~= "table" then return nil end
	for _, tab in ipairs(tabs) do
		if tab.ID == id then return tab end
	end
end

function M:AddBankTabSortToggle(root, entry)
	local flag = Enum.BagSlotFlags and Enum.BagSlotFlags.DisableAutoSort
	if not (flag and bankOpen and C_Bank and C_Bank.UpdateBankTabSettings and C_Bank.FetchPurchasedBankTabData) then return end
	local bankType = entry.kind == "account" and BANK_ACCOUNT or BANK_CHARACTER
	if not bankType then return end
	root:CreateCheckbox(E:GameText(BAG_FILTER_IGNORE, L["Ignore when sorting"]), function()
		local tab = FreshTab(bankType, entry.bag)
		return tab and TabHasFlag(tab.depositFlags, flag) or false
	end, function()
		local tab = FreshTab(bankType, entry.bag)
		if not tab or InCombatLockdown() or not bankOpen then return end
		local flags = TabFlags(tab.depositFlags, flag, not TabHasFlag(tab.depositFlags, flag))
		C_Bank.UpdateBankTabSettings(bankType, tab.ID, tab.name or "", tab.icon or 134400, flags) -- 134400: the question mark icon
	end)
end

-- For the tab settings in BankActions.lua.
M.BankTab = { Flags = TabFlags, HasFlag = TabHasFlag, Fresh = FreshTab, SORT_FLAGS = SORT_FLAGS }

function M:ShowBagMenu(entry, anchor)
	local flags = Enum.BagSlotFlags
	E.UIKit.ContextMenu(anchor, function(_, root)
		root:CreateTitle(BagName(entry.bag))
		root:CreateCheckbox(L["Show in the window"], function() return not M.db.hiddenBags[entry.bag] end, function()
			M.db.hiddenBags[entry.bag] = not M.db.hiddenBags[entry.bag] or nil
			M:RefreshViews()
		end)
		if (entry.kind == "bank" or entry.kind == "account") and entry.bought then
			M:AddBankTabSortToggle(root, entry)
			if M.AddBankTabSettings then M:AddBankTabSettings(root, entry) end
			return
		end
		if entry.kind ~= "bag" or not flags then return end
		-- The game's own per-bag settings, as in Blizzard's bag menu.
		if entry.bag == 0 then
			if C_Container.GetBackpackAutosortDisabled then
				root:CreateCheckbox(E:GameText(BAG_FILTER_IGNORE, L["Ignore when sorting"]), function() return C_Container.GetBackpackAutosortDisabled() end,
					function() C_Container.SetBackpackAutosortDisabled(not C_Container.GetBackpackAutosortDisabled()) end)
			end
			return
		end
		if not (C_Container.GetBagSlotFlag and flags.DisableAutoSort) then return end
		root:CreateCheckbox(E:GameText(BAG_FILTER_IGNORE, L["Ignore when sorting"]), function() return C_Container.GetBagSlotFlag(entry.bag, flags.DisableAutoSort) end,
			function() C_Container.SetBagSlotFlag(entry.bag, flags.DisableAutoSort, not C_Container.GetBagSlotFlag(entry.bag, flags.DisableAutoSort)) end)
		if entry.bag == REAGENT then return end
		root:CreateDivider()
		root:CreateTitle(E:GameText(BAG_FILTER_ASSIGN_TO, L["Assign to"]))
		for _, pair in ipairs(SORT_FLAGS) do
			local flag = flags[pair[1]]
			if flag then
				root:CreateRadio(E:Translate(pair[2]), function() return C_Container.GetBagSlotFlag(entry.bag, flag) end, function()
					local on = C_Container.GetBagSlotFlag(entry.bag, flag)
					for _, other in ipairs(SORT_FLAGS) do
						if flags[other[1]] then C_Container.SetBagSlotFlag(entry.bag, flags[other[1]], false) end
					end
					C_Container.SetBagSlotFlag(entry.bag, flag, not on)
				end)
			end
		end
	end)
end

local function GetBarButton(window, index)
	local button = window.barButtons[index]
	if button then return button end
	button = CreateFrame("Button", nil, window.bar)
	button:SetSize(BAR_SIZE, BAR_SIZE)
	E:SetTemplate(button)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	button.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(button.icon)
	button.free = E:CreateText(button, E.tokens.size.tiny, "RIGHT")
	button.free:SetPoint("BOTTOMRIGHT", -1, 1)
	button.lock = button:CreateTexture(nil, "OVERLAY")
	button.lock:SetSize(12, 12)
	button.lock:SetPoint("CENTER")
	button.lock:SetTexture("Interface\\PetBattles\\PetBattle-LockIcon")
	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints(button.icon)
	hover:SetColorTexture(1, 1, 1, E.tokens.hover.hud)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetScript("OnEnter", function(self)
		self:SetBackdropBorderColor(unpack(E.media.accentColor))
		BarTooltip(self)
		window.barHover = true
		if self.entry then M:HighlightBag(window, self.entry.bag) end
	end)
	button:SetScript("OnLeave", function(self)
		GameTooltip_Hide()
		window.barHover = nil
		M:HighlightBag(window, nil)
		M:PaintBarButton(self)
	end)
	button:SetScript("OnClick", function(self, mouse)
		local entry = self.entry
		if not entry then return end
		if mouse == "RightButton" then
			M:ShowBagMenu(entry, self)
			return
		end
		if DropOnBar(entry) then return end
		if entry.bought == false then
			-- The game's purchase button covers the next tab; without it,
			-- Blizzard's bank window sells it.
			if entry.buy and bankOpen then M:ShowBlizzardBank() end
			return
		end
		M.db.hiddenBags[entry.bag] = not M.db.hiddenBags[entry.bag] or nil
		M:RefreshViews()
	end)
	button:SetScript("OnDragStart", function(self)
		local entry = self.entry
		if not entry or InCombatLockdown() then return end
		if entry.kind == "bag" and entry.invSlot and PickupBagFromSlot then
			PickupBagFromSlot(entry.invSlot)
		elseif entry.kind == "bank" and bankOpen and entry.bought and entry.bankSlot > 1 and CHAR_TABS then
			C_Container.PickupContainerItem(CHAR_TABS, entry.bankSlot)
		end
	end)
	button:SetScript("OnReceiveDrag", function(self)
		if self.entry then DropOnBar(self.entry) end
	end)
	window.barButtons[index] = button
	return button
end

function M:PaintBarButton(button)
	local entry = button.entry
	if not entry then return end
	local hidden = self.db.hiddenBags[entry.bag]
	button.icon:SetTexture(entry.icon or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
	button.icon:SetDesaturated(hidden or entry.bought == false)
	button.icon:SetAlpha(hidden and 0.45 or 1)
	button.lock:SetShown(entry.bought == false and not entry.buy)
	local free = ""
	if entry.bought ~= false and entry.bag and NumSlots(entry.bag) > 0 and entry.kind ~= "keyring" then
		local count, _, known = E.BagCache:Free(entry.bag)
		if known then free = count end
	end
	button.free:SetText(free)
	local r, g, b = unpack(hidden and E.media.borderColor or E.media.accentColor)
	if not hidden and entry.bought == false then r, g, b = unpack(E.media.borderColor) end
	button:SetBackdropBorderColor(r, g, b)
end

-- Returns the height the bar uses (0 when hidden).
function M:UpdateBar(window, live)
	if not (self.db.bagBar and live) then
		window.bar:Hide()
		return 0
	end
	local entries = BarEntries(window)
	for index, entry in ipairs(entries) do
		local button = GetBarButton(window, index)
		button.entry = entry
		button:ClearAllPoints()
		button:SetPoint("LEFT", window.bar, "LEFT", (index - 1) * (BAR_SIZE + 4), 0)
		self:PaintBarButton(button)
		button:Show()
	end
	for index = #entries + 1, #window.barButtons do
		window.barButtons[index].entry = nil
		window.barButtons[index]:Hide()
	end
	window.bar:Show()
	return BAR_H
end

---------------------------------------------------------------------------
-- Tracked currencies in the bag window
---------------------------------------------------------------------------
local function WatchedCurrencies(live, char)
	if live then
		local list = {}
		if C_CurrencyInfo and C_CurrencyInfo.GetBackpackCurrencyInfo then
			for index = 1, 10 do
				local info = C_CurrencyInfo.GetBackpackCurrencyInfo(index)
				if not info then break end
				list[#list + 1] = { id = info.currencyTypesID, quantity = info.quantity, icon = info.iconFileID }
			end
		end
		return list
	end
	return char and char.watched or {}
end

local function GetCurrencyButton(window, index)
	local button = window.currencyButtons[index]
	if button then return button end
	button = CreateFrame("Button", nil, window.currencyRow)
	button:SetHeight(CURRENCY_H - 2)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetSize(14, 14)
	button.icon:SetPoint("LEFT", 0, 0)
	E:TrimIcon(button.icon)
	button.text = E.UIKit.Text(button, E.tokens.size.label, "LEFT")
	button.text:SetPoint("LEFT", button.icon, "RIGHT", 4, 0)
	button:SetScript("OnEnter", function(self)
		if not self.currencyID then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		if GameTooltip.SetCurrencyByID then GameTooltip:SetCurrencyByID(self.currencyID) end
		E:TooltipHint(GameTooltip, { L["Click"], L["open the currency list"] })
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnClick", function(self, mouse)
		if InCombatLockdown() or E:IsOptionsLinkClick(self, mouse) then return end
		if ToggleCharacter then ToggleCharacter("TokenFrame") end
	end)
	E:BindOptionsLink(button, { page = "module:Bags", key = "currencies" })
	window.currencyButtons[index] = button
	return button
end

-- Returns the height the row uses (0 when hidden or empty).
function M:UpdateCurrencies(window, live, char)
	if window.kind ~= "bags" or not self.db.currencies or IsGuildView(window) then
		window.currencyRow:Hide()
		return 0
	end
	local list = WatchedCurrencies(live, char)
	local x = 0
	for index, entry in ipairs(list) do
		local button = GetCurrencyButton(window, index)
		button.currencyID = entry.id
		local icon = entry.icon
		if not icon and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
			local info = C_CurrencyInfo.GetCurrencyInfo(entry.id)
			icon = info and info.iconFileID
		end
		button.icon:SetTexture(icon)
		local amount = entry.quantity or 0
		local text = BreakUpLargeNumbers and BreakUpLargeNumbers(amount) or tostring(amount)
		if #text > 7 and AbbreviateNumbers then text = AbbreviateNumbers(amount) end
		button.text:SetText(text)
		button:SetWidth(18 + button.text:GetStringWidth() + 4)
		button:ClearAllPoints()
		button:SetPoint("LEFT", window.currencyRow, "LEFT", x, 0)
		button:Show()
		x = x + button:GetWidth() + 10
	end
	for index = #list + 1, #window.currencyButtons do window.currencyButtons[index]:Hide() end
	window.currencyRow:SetShown(#list > 0)
	return #list > 0 and CURRENCY_H or 0
end

---------------------------------------------------------------------------
-- Window update
---------------------------------------------------------------------------
function M:UpdateWindow(window)
	if not window or not window:IsShown() then return end
	self:WatchCooldowns()
	local db = self.db
	waitingForInfo = false
	-- A window drawn at its own scale snaps its edges to whole screen
	-- pixels again, so slot borders stay crisp at every size.
	if window.drawnScale ~= (db.scale or 1) then
		window:SetScale(db.scale or 1)
		window.drawnScale = db.scale or 1
		E:SnapBorders(window)
	end
	window:SetFrameStrata(db.strata or "HIGH")
	local columns = window.kind == "bank" and db.bankColumns or db.columns
	local live = IsLive(window)
	local _, _, char = Store:View(window.viewChar, window.kind)
	if not live and window.viewChar == E.charKey then char = Store:Me() end
	local top = HEADER + self:UpdateBar(window, live)
	local currencyHeight = self:UpdateCurrencies(window, live, char)
	window.currencyHeight = currencyHeight
	local height, slots, used, known, rows
	if live then
		height, slots, used, known, rows = self:LayoutLive(window, columns, top)
		if not height then return end
	else
		height, slots, used = self:LayoutOffline(window, columns, top)
		known = slots > 0
	end
	height = math.max(height, db.size)
	local width = PAD * 2 + RAIL + columns * db.size + (columns - 1) * db.spacing
	window:SetSize(width, top + height + 6 + currencyHeight + FOOTER)
	window.anchor:SetSize(width * (db.scale or 1), (top + height + 6 + currencyHeight + FOOTER) * (db.scale or 1))
	self:PlaceWindow(window)

	local text
	if IsGuildView(window) then
		text = E:TextHex("good") .. (char.name or "?") .. "|r " .. Grey(Age(char.updated))
	else
		text = ClassIcon(char.class) .. ClassName(char)
		if not live then
			local updated = window.kind == "bank" and char.bankUpdated or char.updated
			text = text .. " " .. Grey(updated and Age(updated) or L["no data"])
		end
	end
	window.character.text:SetText(text)
	window.sort:SetShown(live and db.sortButton)
	if window.blizzard then window.blizzard:SetShown(bankOpen) end
	M.SetRailActive(window.allButton, window.allChars)
	window.rail:Layout()
	window.gold:SetShown(db.gold)
	window.gold.text:SetText(Money(live and GetMoney() or char.money or 0))
	self:UpdateCapacityFooter(window, slots, used, known, rows)
	self:UpdateMoveButton(window)
	self:UpdateNoMatch(window)
	self:UpdateResults(window)
end

-- How many items in this window's sections match the search (hidden
-- sections too: a search opens them).
function M:SearchMatchCount(window)
	if not window.query then return nil end
	local found = 0
	for _, section in ipairs(window.sections or {}) do
		for _, record in ipairs(section.records or {}) do
			if not record.empty and Matches(window.query, record) then found = found + 1 end
		end
	end
	return found
end

-- The "No matches" line: only for a real zero. While item details are
-- still on their way it waits; the refresh that follows decides.
function M:UpdateNoMatch(window)
	local line, search = window.noMatch, window.search
	if not (line and search) then return end
	local show = window.query ~= nil and not waitingForInfo and self:SearchMatchCount(window) == 0
	local base = search.eldoInsets or {}
	local left, right, top, bottom = base[1] or 0, base[2] or 0, base[3] or 0, base[4] or 0
	if show then
		line:SetText(L["No matches"])
		-- At most half the box, so the typed text keeps its room.
		local room = math.floor((search:GetWidth() or 0) * 0.5)
		local width = line.GetUnboundedStringWidth and line:GetUnboundedStringWidth() or line:GetStringWidth() or 0
		if room > 0 then width = math.min(width, room) end
		line:SetWidth(width)
		line:Show()
		-- Typed text stops before the line.
		search:SetTextInsets(left, math.max(right, width + 24), top, bottom)
	else
		line:Hide()
		search:SetTextInsets(left, right, top, bottom)
	end
end

function M:RefreshViews()
	for _, window in pairs(windows) do self:UpdateWindow(window) end
end

---------------------------------------------------------------------------
-- Bag changes: BAG_UPDATE names the bags that changed, and the
-- BAG_UPDATE_DELAYED that follows repaints only their slots while nothing
-- else moved (the same view, bags and sizes, no search running). Selling,
-- buying or looting then repaints one bag instead of the whole window.
---------------------------------------------------------------------------
local changedBags = {}

function M:NoteBagChanged(bag)
	if type(bag) == "number" then changedBags[bag] = true end
end

-- A slot whose look did not change keeps its paint.
local SLOT_FIELDS = { "empty", "link", "count", "locked", "bound", "quality", "new", "quest", "protected", "junk", "icon", "freeCount", "total", "tradeGUID" }
local function SameSlot(old, new)
	for _, field in ipairs(SLOT_FIELDS) do
		if old[field] ~= new[field] then return false end
	end
	return true
end

-- Repaint the slots of `bags` in an open live window. False when the
-- window needs a full redraw instead.
function M:RepaintBags(window, bags)
	if not (window:IsShown() and IsLive(window)) or window.query or window.waiting then return false end
	local view = window.kind == "bank" and self.db.bankView or self.db.view
	if view == "categories" or window.liveShape == nil or window.liveShape ~= LiveShape(window) then return false end
	-- Grouped stacks (one slot for several) always redraw whole.
	if self.GroupsStacks and self:GroupsStacks(window) then return false end
	local _, allIDs = VisibleIDs(window)
	local mine = {}
	for _, bag in ipairs(allIDs) do mine[bag] = true end
	local paints, swaps = {}, {}
	for bag in pairs(bags) do
		if mine[bag] and not self.db.hiddenBags[bag] then
			local holder = window.holders[bag]
			local records = {}
			for slot = 1, NumSlots(bag) do
				local button = holder and holder.buttons[slot]
				local old = button and button.eldoRecord
				-- A slot that is not on screen (a folded section): redraw all.
				if not (old and old.bag == bag and old.slot == slot and button:IsShown()) then return false end
				local record = LiveRecord(bag, slot)
				records[slot] = record
				if SameSlot(old, record) then
					button.eldoRecord = record
				else
					paints[#paints + 1] = { button, record }
				end
				swaps[old] = record
			end
			-- The bags view names each bag's free slots in its title.
			if view == "bags" then
				for _, section in ipairs(window.sections or {}) do
					if section.key == tostring(bag) then
						local _, note = SectionTitle(bag, records)
						if note ~= section.note then return false end
					end
				end
			end
		end
	end
	for _, section in ipairs(window.sections or {}) do
		local list = section.records
		for index = 1, #(list or {}) do
			local record = swaps[list[index]]
			if record then list[index] = record end
		end
	end
	for _, paint in ipairs(paints) do PaintLive(window, paint[1], paint[2]) end
	local total, used, known, rows = SlotCounts(allIDs, window.kind == "bank")
	self:UpdateCapacityFooter(window, total, used, known, rows)
	self:UpdateMoveButton(window)
	return true
end

-- Bank slot and quest events: one repaint a moment after the last one
-- (BAG_UPDATE_DELAYED does not always follow them).
local function FlushChanged() M:RefreshChangedBags() end
function M:RefreshChangedSoon()
	E:Debounce("Bags:changed", 0.08, FlushChanged)
end

-- After a bag change: repaint what changed, or redraw the windows.
function M:RefreshChangedBags()
	local bags = changedBags
	changedBags = {}
	for _, window in pairs(windows) do
		if not (next(bags) and self:RepaintBags(window, bags)) then self:UpdateWindow(window) end
	end
end

---------------------------------------------------------------------------
-- Small updates: events that change one slot, the gold or the currency
-- row redraw only that part of an open window, not the whole window.
---------------------------------------------------------------------------
local function LiveWindows()
	local list = {}
	for _, window in pairs(windows) do
		if window:IsShown() and IsLive(window) then list[#list + 1] = window end
	end
	return list
end

-- A slot was locked or unlocked (picked up, being sold, posted or traded).
function M:UpdateLock(bag, slot)
	if bag == nil or slot == nil then return end
	for _, window in ipairs(LiveWindows()) do
		local holder = window.holders[bag]
		local button = holder and holder.buttons[slot]
		local record = button and button.eldoRecord
		if record and not record.empty and record.bag == bag and record.slot == slot then
			local info = C_Container.GetContainerItemInfo(bag, slot)
			record.locked = info and info.isLocked or false
			record.junk = E.WillSellAsJunk and E:WillSellAsJunk(bag, slot, info)
			PaintLive(window, button, record)
		end
	end
end

-- The gold line of the open windows that show this character.
function M:UpdateMoney()
	for _, window in pairs(windows) do
		if window:IsShown() and window.viewChar == E.charKey then
			local money = IsLive(window) and GetMoney() or Store:Me().money
			window.gold.text:SetText(Money(money or 0))
			local capacity = window.slotCapacity
			if capacity then self:UpdateCapacityFooter(window, capacity.total, capacity.used, capacity.known, capacity.rows) end
		end
	end
end

local cooldownOwner, cooldownTimer, watchingCooldowns = {}, nil, false

local function HasLiveWindow()
	for _, window in pairs(windows) do
		if window:IsVisible() and IsLive(window) then return true end
	end
	return false
end

local function QueueCooldowns()
	if cooldownTimer then return end
	cooldownTimer = C_Timer.NewTimer(0, function()
		cooldownTimer = nil
		if M.active and HasLiveWindow() then M:UpdateCooldowns() end
	end)
end

function M:WatchCooldowns()
	if self.active and HasLiveWindow() then
		if not watchingCooldowns then
			E:RegisterEvent("BAG_UPDATE_COOLDOWN", QueueCooldowns, cooldownOwner)
			watchingCooldowns = true
		end
	else
		if watchingCooldowns then E:UnregisterEvent("BAG_UPDATE_COOLDOWN", cooldownOwner) end
		watchingCooldowns = false
		if cooldownTimer then cooldownTimer:Cancel() cooldownTimer = nil end
	end
end

-- The cooldown swipes of the slots on screen.
function M:UpdateCooldowns()
	for _, window in ipairs(LiveWindows()) do
		for _, holder in pairs(window.holders) do
			for _, button in pairs(holder.buttons) do
				if button.eldoRecord and button:IsShown() then PaintCooldown(button, button.eldoRecord) end
			end
		end
	end
end

-- The tracked currencies; the whole window only when the row appears or goes.
function M:UpdateCurrencyRow()
	for _, window in ipairs(LiveWindows()) do
		if window.kind == "bags" then
			local height = self:UpdateCurrencies(window, true)
			if height ~= window.currencyHeight then self:UpdateWindow(window) end
		end
	end
end

---------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------
local function BlizzardBagFrames()
	local frames = {}
	if ContainerFrameCombinedBags then frames[#frames + 1] = ContainerFrameCombinedBags end
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do
		local frame = _G["ContainerFrame" .. i]
		if frame then frames[#frames + 1] = frame end
	end
	return frames
end
M.BlizzardBagFrames = BlizzardBagFrames

function M:AnyBagOpen()
	for _, frame in ipairs(BlizzardBagFrames()) do
		-- Bank bags open their own window; the bag window follows the player's bags.
		local id = frame.GetBagID and frame:GetBagID() or frame:GetID()
		if frame:IsShown() and (frame == ContainerFrameCombinedBags or (id and ((id >= 0 and id <= NUM_BAG_SLOTS + 1) or id == KEYRING))) then
			return true
		end
	end
	return false
end

function M:OwnBags()
	return self.active and E:BlizzardAllowed(BAGS_ID, "replace")
end

function M:OwnBank()
	return self.active and E:BlizzardAllowed(BANK_ID, "replace")
end

---------------------------------------------------------------------------
-- The game's bag code stays the game's (review/fehler.md F24)
--
-- Blizzard's bank and vendor windows call OpenAllBags(self) when they open,
-- before they choose their tab. If anything that bag code reads was written
-- by EldoUI, the rest of their OnShow runs tainted, and so does the bank tab
-- it stores (BankFrame.BankPanel.bankType). Every right-click on an item in
-- the bags hands that tab to C_Container.UseContainerItem
-- (ContainerFrameItemButton_OnClick), so the hearthstone, keys and recipes
-- were blocked ("Forbidden") until a reload. EldoUI wrote it two ways:
-- CloseAllBags() writes FRAME_THAT_OPENED_BAGS, and an open from EldoUI's
-- code builds the game's bag frames (ContainerFrame_GenerateFrame and its
-- settings manager).
-- So while the game's bag frames sit on EldoUI's hidden parent, EldoUI's
-- own code never runs that code: it closes the frames by hiding them (on
-- the hidden parent they run no scripts, the same as the game's close
-- there), and it opens only its own window. That window (window.eldoOnly)
-- stays open until the player closes it: its close button, Escape, the
-- game's bag toggle (B) or a bag block. With the game's frames shown, the
-- game's functions are used as before.
---------------------------------------------------------------------------
function M:GameBagsParked()
	local frames = BlizzardBagFrames()
	if #frames == 0 then return false end
	for _, frame in ipairs(frames) do
		if frame:GetParent() ~= hider then return false end
	end
	return true
end

-- Closes the game's bag frames for EldoUI. `frame` is the window that
-- closes them (CloseAllBags(frame)) when the game's frames are shown.
function M:CloseGameBags(frame)
	if not self:GameBagsParked() then
		CloseAllBags(frame)
		return
	end
	-- What the CloseAllBags hook does for a close without a window.
	if not frame and self.ForgetAutoOpen then self:ForgetAutoOpen() end
	for _, bagFrame in ipairs(BlizzardBagFrames()) do
		if bagFrame:IsShown() then
			-- What the game's close does besides hiding: the items lose their
			-- "new" mark (C_NewItems only, nothing of the game's is written).
			if type(UpdateNewItemList) == "function" and bagFrame.EnumerateValidItems then
				pcall(UpdateNewItemList, bagFrame)
			end
			bagFrame:Hide()
		end
	end
end

-- Opens the bags from EldoUI's code (a slash command, the tour, a window's
-- event, a bag block): the game's own open while its frames are shown,
-- else only EldoUI's window.
function M:OpenBags()
	local window = windows.bags
	if not (window and self:OwnBags() and self:GameBagsParked()) then
		OpenAllBags()
		return
	end
	if not self:AnyBagOpen() then window.eldoOnly = true end
	if not window:IsShown() then window.viewChar = E.charKey end
	self:OpenWindow(window, self:WindowSide(window))
end

-- Closes them again: EldoUI's window when it opened alone, and the game's
-- frames.
function M:CloseBags()
	local window = windows.bags
	if window and window.eldoOnly and window:IsShown() then
		self:CloseWindow(window)
	else
		self:CloseGameBags()
	end
end

-- The bag blocks of the info bar and the flight view's Bags button.
function M:ToggleBags()
	local window = windows.bags
	if not (window and self:OwnBags() and self:GameBagsParked()) then
		ToggleAllBags()
	elseif window:IsShown() then
		self:CloseWindow(window)
	else
		self:OpenBags()
	end
end

---------------------------------------------------------------------------
-- Tour help: the bag window explains itself once, after it has stayed
-- open a moment (bags are often opened in a hurry).
---------------------------------------------------------------------------
local function LockedSlot(window)
	for _, holder in pairs(window.holders or {}) do
		for _, button in ipairs(holder.buttons or {}) do
			if button:IsVisible() and button.lockMark and button.lockMark:IsShown() then return button end
		end
	end
end

E.Tour:Register("bags:first", {
	form = "tour", word = "bags",
	offer = function(_, force)
		local window = windows.bags
		if not (M:OwnBags() and window and window:IsShown()) then return false end
		return E.Tour:Run("bags:first", {
			{ target = window.search, title = L["Search"],
				text = L["Type a name, or a filter: q:rare for rare items, ilvl>50 for item level above 50, t:cloth for a type, or junk, quest and new. Put - before a word to leave it out."] },
			{ target = window.viewButton, title = L["View"],
				text = L["One grid, categories or bag by bag, and the bag bar that shows, hides and swaps single bags."] },
			{ target = window.character, title = L["Characters"],
				text = L["Pick another character on this account to see their bags as they were when you last played them."] },
			{ target = function() return LockedSlot(window) end, title = L["A lock on an item"],
				text = L["A quest or recipe of yours needs this item, so EldoUI's junk selling and Move these leave it alone."] },
		}, { force = force, title = L["Bags"] })
	end,
	replay = function(def)
		if not M.active then
			E:Print(E:ModuleOffHint("Bags"))
			return
		elseif not M:OwnBags() then
			E:Print(L["The bags tour runs in EldoUI's bag window: Blizzard UI > Bags (container windows) > Replace with EldoUI's frame."])
			return
		end
		if not (windows.bags and windows.bags:IsShown()) then M:OpenBags() end
		C_Timer.After(1, function() def.offer(def, true) end)
	end,
})

function M:OpenWindow(window, side)
	if not window:IsShown() then
		local opening
		if window.kind == "bags" then
			opening = {}
			window.tourOpening = opening
		end
		E:SlideIn(window, side)
		if window.kind == "bags" and not E.Tour:Seen("bags:first") then
			C_Timer.After(1, function()
				if window.tourOpening == opening and window:IsShown() then
					window.tourOpening = nil
					E.Tour:Offer("bags:first")
				end
			end)
		end
	end
	self:UpdateWindow(window)
end

function M:CloseWindow(window)
	if window.kind == "bags" then
		window.eldoOnly = nil
		self:CloseGameBags()
	end
	if window:IsShown() then E:SlideOut(window, self:WindowSide(window)) end
end

function M:SyncOpen()
	local window = windows.bags
	if not window then return end
	if not self:OwnBags() then
		if window:IsShown() then window:Hide() end
		return
	end
	if self:AnyBagOpen() then
		if not window:IsShown() then
			window.viewChar = E.charKey
			self:OpenWindow(window, self:WindowSide(window))
		end
	elseif window:IsShown() and not window.eldoOnly then
		-- A window EldoUI opened alone (M:OpenBags) stays until the player
		-- closes it, like bags that were open before a bank or vendor
		-- opened and closed them.
		window.search:ClearFocus()
		E:SlideOut(window, self:WindowSide(window))
	end
end

-- Bank window anywhere: the selected character's saved bank.
function M:ToggleBank(charKey)
	local window = windows.bank
	if not window then return end
	if window:IsShown() and not bankOpen then
		E:SlideOut(window, self:WindowSide(window))
		return
	end
	window.viewChar = charKey or E.charKey
	self:OpenWindow(window, self:WindowSide(window))
end

-- Shows a saved character's bags or bank in EldoUI's own windows (the
-- Alts window's Character tab uses it). Returns false when Bags is off.
function M:ShowCharacterBags(charKey, kind)
	if kind == "bank" then
		if not self:OwnBank() then return false end
	elseif not self:OwnBags() then
		return false
	end
	local window = windows[kind == "bank" and "bank" or "bags"]
	if not window then return false end
	window.viewChar = charKey or E.charKey
	self:OpenWindow(window, self:WindowSide(window))
	self:UpdateWindow(window)
	return true
end

-- Blizzard's bank sits in a tiny frame while EldoUI shows its own; this
-- brings it back for the rest of the visit (to buy slots or tabs).
local tiny = CreateFrame("Frame", nil, UIParent)
tiny:SetScale(0.001)
tiny:SetAlpha(0)
tiny:SetPoint("TOPLEFT")
tiny:SetSize(1, 1)

local originalParent = {}   -- Blizzard frame -> parent before EldoUI moved it

local function Reparent(frame, parent)
	if not frame or frame:GetParent() == parent then return end
	if originalParent[frame] == nil then originalParent[frame] = frame:GetParent() or UIParent end
	frame:SetParent(parent)
end

local function RestoreParent(frame)
	local parent = frame and originalParent[frame]
	if not parent then return end
	originalParent[frame] = nil
	frame:SetParent(parent)
end

function M:ShowBlizzardBank()
	if not BankFrame then return end
	E:RunOutOfCombat(function()
		self.showingBlizzardBank = true
		RestoreParent(BankFrame)
		if windows.bank then windows.bank:Hide() end
		self.showingBlizzardBank = nil
		self.blizzardBankVisible = true
		if self.PlaceBlizzardBank then self.PlaceBlizzardBank() end
	end)
end

function M:OnBankOpened()
	bankOpen = true
	local window = windows.bank
	if window and self:OwnBank() then
		window.viewChar = E.charKey
		self:OpenWindow(window, self:WindowSide(window))
	end
end

function M:OnBankClosed()
	bankOpen = false
	self:WatchCooldowns()
	if self.blizzardBankVisible and BankFrame then
		E:RunOutOfCombat(function()
			if E:BlizzardHidden(BANK_ID) then Reparent(BankFrame, tiny) end
		end)
		self.blizzardBankVisible = nil
	end
	local window = windows.bank
	if window and window:IsShown() then
		if window.viewChar == E.charKey then
			E:SlideOut(window, self:WindowSide(window))
		else
			self:UpdateWindow(window)
		end
	end
end

---------------------------------------------------------------------------
-- Open and close the bags with other windows
--
-- The game itself opens the bags with the bank, a vendor, the mailbox and
-- the auction house (their OnShow calls OpenAllBags(frame)) and closes them
-- again when that window closes, if it was the one that opened them. The
-- post-hooks below only undo or keep that: a window whose "open" setting
-- is off closes the bags it just opened, one whose "close" setting is off
-- opens them again. Trade, the guild bank and the profession window don't
-- open bags in the game; for them EldoUI opens the bags on the window's
-- event and closes them again only if it opened them. EldoUI opens and
-- closes through M:OpenBags / M:CloseGameBags, never the game's bag code
-- while its own window replaces the game's (F24).
-- Only the bags are opened or closed, never the other window, and nothing
-- happens without the player opening that window.
---------------------------------------------------------------------------
local FRAME_KIND = { BankFrame = "bank", MerchantFrame = "merchant", MailFrame = "mail", AuctionHouseFrame = "auction" }
local EVENT_KIND = {
	TRADE_SHOW = { "trade", true }, TRADE_CLOSED = { "trade", false },
	GUILDBANKFRAME_OPENED = { "guildbank", true }, GUILDBANKFRAME_CLOSED = { "guildbank", false },
	TRADE_SKILL_SHOW = { "professions", true }, TRADE_SKILL_CLOSE = { "professions", false },
}
M.autoWindows = {
	{ "bank", "Bank", E.Key("the game opens them"), E.Key("bank") },
	{ "merchant", "Vendor", E.Key("the game opens them"), E.Key("vendor") },
	{ "mail", "Mailbox", E.Key("the game opens them"), E.Key("mailbox") },
	{ "auction", "Auction house", E.Key("the game opens them"), E.Key("auction house") },
	{ "trade", "Trade", E.Key("the game leaves them closed"), E.Key("trade") },
	{ "guildbank", "Guild bank", E.Key("the game leaves them closed"), E.Key("guild bank") },
	{ "professions", "Profession", E.Key("the game leaves them closed"), E.Key("profession") },
}

local openedBy      -- kind of the game window that opened the bags this visit
local eventOpened   -- kind EldoUI opened the bags for
local autoOwner = {} -- event owner key, separate from the module's own handlers

-- Opening the bags with other windows follows EldoUI's bag window or the
-- bags element's Improve switch; with neither, the game decides alone.
function M:AutoBagsAllowed()
	return self.active and (self:OwnBags() or E:BlizzardAllowed(BAGS_ID, "improve")) and true or false
end

local function AnyOpen()
	if IsAnyBagOpen then return IsAnyBagOpen() end
	return M:AnyBagOpen()
end

local autoHooked = false
function M:HookAutoBags()
	if autoHooked then return end
	autoHooked = true
	hooksecurefunc("OpenAllBags", function(frame)
		if not (M:AutoBagsAllowed() and frame and frame.GetName) then return end
		local name = frame:GetName()
		local kind = name and FRAME_KIND[name]
		-- Only when this call opened them (bags that were open stay open).
		if not kind or rawget(_G, "FRAME_THAT_OPENED_BAGS") ~= name then return end
		if M.db.autoOpen[kind] then
			openedBy = kind
		else
			openedBy = nil
			M:CloseGameBags(frame)
		end
	end)
	hooksecurefunc("CloseAllBags", function(frame)
		if not frame then
			-- Closed by the player (close button, Escape, B): nothing to keep.
			openedBy, eventOpened = nil, nil
			return
		end
		if not (M:AutoBagsAllowed() and frame.GetName) then return end
		local kind = FRAME_KIND[frame:GetName() or ""]
		if not kind or openedBy ~= kind then return end
		openedBy = nil
		if not M.db.autoClose[kind] then M:OpenBags() end
	end)
	-- The player closing the bags by hand ends "opened by" as well.
	local function Toggled()
		if not AnyOpen() then openedBy, eventOpened = nil, nil end
	end
	if ToggleAllBags then hooksecurefunc("ToggleAllBags", Toggled) end
	if ToggleBackpack then hooksecurefunc("ToggleBackpack", Toggled) end
end

-- EldoUI closed the bags (its window, combat): like the game's
-- CloseAllBags() above, nothing is kept (M:CloseGameBags).
function M:ForgetAutoOpen()
	openedBy, eventOpened = nil, nil
end

function M:OnAutoBagEvent(event)
	local entry = EVENT_KIND[event]
	if not (entry and self:AutoBagsAllowed()) then return end
	local kind, shown = entry[1], entry[2]
	if shown then
		local window = windows.bags
		if self.db.autoOpen[kind] and not AnyOpen() and not (window and window:IsShown()) then
			self:OpenBags()
			eventOpened = kind
		end
	elseif eventOpened == kind then
		eventOpened = nil
		if self.db.autoClose[kind] then self:CloseBags() end
	end
end

-- Combat-start is the last chance to close a protected bag window.
function M:CloseForCombat()
	if not self.db.autoClose.combat or not self:AutoBagsAllowed() or InCombatLockdown() then return end
	local window = windows.bags
	if not AnyOpen() and not (self:OwnBags() and window and window:IsShown()) then return end
	if self:OwnBags() and window and window:IsShown() then
		-- OnHide closes the native bags too. A slide would finish in combat.
		for _, animation in pairs(window.eldoAnim or {}) do animation:Stop() end
		window:Hide()
	end
	if AnyOpen() then self:CloseGameBags() end
end

function M:EnableAutoBags()
	self:HookAutoBags()
	for event in pairs(EVENT_KIND) do
		E:RegisterEvent(event, function(_, name) M:OnAutoBagEvent(name) end, autoOwner)
	end
end

function M:DisableAutoBags()
	for event in pairs(EVENT_KIND) do E:UnregisterEvent(event, autoOwner) end
	openedBy, eventOpened = nil, nil
end

---------------------------------------------------------------------------
-- The Blizzard UI switches: hide / replace here, skin / move / improve in
-- Modules/Bags/Blizzard.lua.
---------------------------------------------------------------------------
local bagHooks = false

local function HookBagFrames()
	if bagHooks then return end
	bagHooks = true
	-- The Blizzard frames sit on a hidden parent, so OnShow never fires;
	-- their Show/Hide calls are what say "bags opened/closed". The hook
	-- checks the switch every time it runs.
	-- Closing all bags hides a dozen of them at once: one check on the
	-- next frame covers the whole burst.
	local queued = false
	local function Sync()
		if queued or not M:OwnBags() then return end
		queued = true
		C_Timer.After(0, function()
			queued = false
			M:SyncOpen()
		end)
	end
	for _, frame in ipairs(BlizzardBagFrames()) do
		hooksecurefunc(frame, "Show", Sync)
		hooksecurefunc(frame, "Hide", Sync)
		hooksecurefunc(frame, "SetShown", Sync)
	end
	-- A window EldoUI opened alone (M:OpenBags): the game's bag toggle (B)
	-- either opened the game's frames or closed the ones a bank or vendor
	-- opened, but the player meant to close the window. Whatever is open
	-- closes, and the window follows (SyncOpen). Only ToggleAllBags: the
	-- game's own opens call ToggleBackpack too (OpenBackpack).
	if ToggleAllBags then
		hooksecurefunc("ToggleAllBags", function()
			local window = windows.bags
			if not (window and window.eldoOnly) then return end
			window.eldoOnly = nil
			if window:IsShown() and M:OwnBags() then M:CloseGameBags() end
		end)
	end
end
M.HookBagFrames = HookBagFrames

function M:ApplyBagElement()
	if not self.active then return end
	if E:BlizzardHidden(BAGS_ID) then
		HookBagFrames()
		E:RunOutOfCombat(function()
			if not E:BlizzardHidden(BAGS_ID) then return end
			for _, frame in ipairs(BlizzardBagFrames()) do Reparent(frame, hider) end
		end)
	else
		self:RestoreBagFrames()
	end
	if not self:OwnBags() and windows.bags and windows.bags:IsShown() then windows.bags:Hide() end
	if self.ApplyBlizzardBags then self:ApplyBlizzardBags() end
	self:ApplySortDirection()
	self:ApplyInsertDirection()
end

function M:RestoreBagFrames()
	local moved = false
	for _, frame in ipairs(BlizzardBagFrames()) do
		if originalParent[frame] then moved = true end
	end
	if not moved then return end
	E:RunOutOfCombat(function()
		if E:BlizzardHidden(BAGS_ID) then return end
		for _, frame in ipairs(BlizzardBagFrames()) do RestoreParent(frame) end
		if UpdateContainerFrameAnchors then UpdateContainerFrameAnchors() end
	end)
end

function M:RestoreBagElement()
	if windows.bags then windows.bags:Hide() end
	self:RestoreBagFrames()
	if self.RestoreBlizzardBags then self:RestoreBlizzardBags() end
end

function M:ApplyBankElement()
	if not self.active then return end
	if BankFrame then
		E:RunOutOfCombat(function()
			if E:BlizzardHidden(BANK_ID) then
				if not self.blizzardBankVisible then Reparent(BankFrame, tiny) end
			else
				RestoreParent(BankFrame)
			end
		end)
	end
	if not self:OwnBank() and windows.bank and windows.bank:IsShown() and bankOpen then windows.bank:Hide() end
	if self.ApplyBlizzardBank then self:ApplyBlizzardBank() end
end

function M:RestoreBankElement()
	if windows.bank and bankOpen then windows.bank:Hide() end
	if BankFrame then E:RunOutOfCombat(function() RestoreParent(BankFrame) end) end
	if self.RestoreBlizzardBank then self:RestoreBlizzardBank() end
end

-- "Sort direction" is the game's own setting, changed only when picked here.
function M:ApplySortDirection()
	local direction = self.db.sortDirection
	if direction == "game" or not self:OwnBags() then return end
	if not (C_Container.SetSortBagsRightToLeft and C_Container.GetSortBagsRightToLeft) then return end
	local rtl = direction == "rtl"
	if C_Container.GetSortBagsRightToLeft() ~= rtl then C_Container.SetSortBagsRightToLeft(rtl) end
end

function M:ApplyInsertDirection()
	local direction = self.db.insertDirection
	if (direction ~= "first" and direction ~= "last") or not self:OwnBags() then return end
	if not (C_Container.SetInsertItemsLeftToRight and C_Container.GetInsertItemsLeftToRight) then return end
	local current = E.PlainCall(C_Container.GetInsertItemsLeftToRight)
	local leftToRight = direction == "last"
	if type(current) == "boolean" and current ~= leftToRight then
		E.PlainCall(C_Container.SetInsertItemsLeftToRight, leftToRight)
	end
end

E:RegisterBlizzardHandler(BAGS_ID, {
	owner = "Bags",
	apply = function() M:ApplyBagElement() end,
	undo = function() M:RestoreBagElement() end,
	reload = { skin = true },
	install = { replace = true, skin = true, improve = true },
	-- v0.5.0 replaced Blizzard's bags unless "Use EldoUI bag and bank windows" was off.
	legacy = function() return M.db and M.db.enabled ~= false and M.db.replaceBlizzard ~= false end,
})

E:RegisterBlizzardHandler(BANK_ID, {
	owner = "Bags",
	apply = function() M:ApplyBankElement() end,
	undo = function() M:RestoreBankElement() end,
	reload = { skin = true },
	install = { replace = true, skin = true },
	legacy = function() return M.db and M.db.enabled ~= false and M.db.replaceBlizzard ~= false end,
})

-- The "Mode" selects on this page mirror the switches: picking one here
-- flips the switches; flipping switches on the Blizzard UI page updates them.
local MODE_ELEMENTS = { { "bagMode", BAGS_ID }, { "bankMode", BANK_ID } }

local function ModeOf(id)
	if not E:BlizzardAllowed(id) then return "blizzard" end
	if E:BlizzardAllowed(id, "replace") then return "eldoui" end
	if E:BlizzardAllowed(id, "skin") and not E:BlizzardAllowed(id, "hide") then return "skin" end
	return "custom"
end

local function SetMode(id, mode)
	if mode == "blizzard" then
		E:SetBlizzardElement(id, "enabled", false)
	elseif mode == "skin" then
		E:SetBlizzardElement(id, "replace", false)
		E:SetBlizzardElement(id, "hide", false)
		E:SetBlizzardElement(id, "skin", true)
		E:SetBlizzardElement(id, "enabled", true)
	elseif mode == "eldoui" then
		E:SetBlizzardElement(id, "replace", true)
		E:SetBlizzardElement(id, "enabled", true)
	end
end

function M:SyncModes()
	if self.syncingModes or not (E.db and E.db.blizzard) then return end
	self.syncingModes = true
	local changed = false
	for _, pair in ipairs(MODE_ELEMENTS) do
		local key, id = pair[1], pair[2]
		local db = self.db
		if db[key] ~= db[key .. "Synced"] then
			SetMode(id, db[key])
			changed = true
		end
		local current = ModeOf(id)
		if db[key] ~= current then changed = true end
		db[key], db[key .. "Synced"] = current, current
	end
	self.syncingModes = nil
	if changed and E.RefreshConfig then C_Timer.After(0, function() E:RefreshConfig() end) end
end

---------------------------------------------------------------------------
-- Bag bar buttons of the action bar: free slots on profession bags, ammo on the quiver
---------------------------------------------------------------------------
local bagButtonTexts = {}   -- Blizzard bag button -> our font string (kept out of Blizzard's frame)

local function BagBarButton(bag)
	if bag == 0 then return MainMenuBarBackpackButton end
	return _G["CharacterBag" .. (bag - 1) .. "Slot"]
end

-- Bows and crossbows shoot arrows, guns shoot bullets (item class 2
-- weapon: 2 bow, 3 gun, 18 crossbow; class 6 projectile: 2 arrow, 3 bullet).
local AMMO_FOR_WEAPON = { [2] = 2, [3] = 3, [18] = 2 }

local function ItemClass(itemID)
	if not (itemID and C_Item and C_Item.GetItemInfoInstant) then return end
	local ok, _, _, _, _, _, classID, subclassID = pcall(C_Item.GetItemInfoInstant, itemID)
	if not ok or E:IsSecret(classID) or E:IsSecret(subclassID) then return end
	return classID, subclassID
end

-- The ammo the equipped ranged weapon shoots (2 arrows, 3 bullets), or nil
-- without a bow, gun or crossbow.
function M:RangedAmmoType()
	local slot = INVSLOT_RANGED or 18
	local weapon = GetInventoryItemID("player", slot)
	if E:IsSecret(weapon) then return end
	local classID, subclassID = ItemClass(weapon)
	if classID ~= 2 then return end
	return AMMO_FOR_WEAPON[subclassID]
end

-- Ammo left in the ammo slot, for every class whose ranged weapon shoots
-- ammo (hunters always), or nil. The second value is true when the
-- equipped ammo does not fit the weapon (arrows with a gun).
function M:AmmoCount()
	if not INVSLOT_AMMO then return end
	local _, class = UnitClass("player")
	local wants = self:RangedAmmoType()
	if class ~= "HUNTER" and not wants then return end
	local ammo = GetInventoryItemID("player", INVSLOT_AMMO)
	if E:IsSecret(ammo) or not ammo then return 0 end
	local classID, subclassID = ItemClass(ammo)
	local mismatch = wants ~= nil and classID == 6 and subclassID ~= wants
	return GetInventoryItemCount("player", INVSLOT_AMMO) or 0, mismatch
end

-- Writes on Blizzard's bag buttons, so it follows the bags element's
-- "Improve" switch.
function M:UpdateBagButtons()
	local db = self.db
	local allowed = E:BlizzardAllowed(BAGS_ID, "improve")
	local ammo = self:AmmoCount()
	for bag = 1, NUM_BAG_SLOTS do
		local button = BagBarButton(bag)
		if button then
			local text = bagButtonTexts[button]
			if not text and db.bagButtonFree and allowed then
				text = E:CreateText(button, E.tokens.size.small, "CENTER")
				text:SetPoint("BOTTOM", 0, 2)
				bagButtonTexts[button] = text
			end
			if text then
				local free, family = C_Container.GetContainerNumFreeSlots(bag)
				local special = family and family ~= 0
				local value = ""
				if allowed and db.bagButtonFree and special then
					-- Quivers and ammo pouches (families 1 and 2) show the ammo left.
					if ammo and bit.band(family, 3) ~= 0 then
						value = (ammo < db.ammoThreshold and E:TextHex("bad") .. "%d|r" or "%d"):format(ammo)
					else
						value = free
					end
				end
				text:SetText(value)
			end
		end
	end
end

-- One warning when ammo runs low, again only after restocking.
function M:CheckAmmo()
	local ammo = self:AmmoCount()
	if not ammo or not self.db.ammoWarn then return end
	-- Warriors and rogues get the warning only when they ask for it.
	local _, class = UnitClass("player")
	if class ~= "HUNTER" and not self.db.ammoWarnAll then return end
	if ammo >= self.db.ammoThreshold then
		self.ammoWarned = nil
	elseif not self.ammoWarned then
		self.ammoWarned = true
		M:PushAlert({ key = "eldoui-ammo", title = L["Bags"], text = L["Low on ammo: %d left."]:format(ammo) })
		E:PlayMedia(self.db.ammoSound)
	end
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------
-- Lines of the Inventory block for one item: { { left, right }, ... }.
-- The lines are kept per item while the records and the settings that
-- shape them stay the same (a store change, a forgotten character or
-- other settings start over), at most `cap` items.
M.LINES_KEEP = { money = true, currency = true, itemCooldowns = true, durability = true, lockouts = true,
	professions = true, recipes = true, quests = true, questHistory = true, reps = true, calendar = true, stats = true,
	played = true, levels = true }
M.linesCache = { items = {}, totals = {}, count = 0, cap = 1500 }
function M:ForgetInventoryLines()
	local cache = self.linesCache
	wipe(cache.items)
	wipe(cache.totals)
	cache.count = 0
end

do
	local function LinesSettings(db)
		return table.concat({ tostring(db.scope), tostring(db.includeCurrent), tostring(db.onlyWithItem), tostring(db.guild),
			tostring(db.breakdown), tostring(db.minCount), tostring(db.maxChars), tostring(db.icons),
			tostring(M.db.altChars), AccentHex(), E:TextHex("good"), E:TextHex("secondary"), tostring(E.colorsVersion),
			tostring(GetRealmName()), tostring(E.charKey) }, "\1")
	end

	-- Other settings, colors or character: the kept lines start over.
	function M:CheckInventorySettings()
		local cache = self.linesCache
		local settings = LinesSettings(self.db.tooltip)
		if cache.settings ~= settings then
			self:ForgetInventoryLines()
			cache.settings = settings
		end
	end

	local NO_LINES = {}
	function M:InventoryLines(itemID)
		local cache = self.linesCache
		self:CheckInventorySettings()
		local kept = cache.items[itemID]
		if kept then
			if kept.lines == NO_LINES then return nil, 0 end
			return kept.lines, kept.total
		end
		if cache.count >= cache.cap then self:ForgetInventoryLines() end
		local lines, total = self:BuildInventoryLines(itemID)
		cache.items[itemID] = { lines = lines or NO_LINES, total = total }
		cache.count = cache.count + 1
		cache.builds = (cache.builds or 0) + 1
		return lines, total
	end
end

function M:BuildInventoryLines(itemID)
	local db = self.db.tooltip
	local entries, total = {}, 0
	for _, key in ipairs(Store:Characters(db.scope)) do
		if key ~= E.charKey or db.includeCurrent then
			local char = Store:Get(key)
			local counts = char.counts and char.counts[itemID] or { 0, 0, 0, 0 }
			local auctions = Store:AuctionCount(key, itemID)
			local sum = counts[1] + counts[2] + counts[3] + counts[4] + auctions
			total = total + sum
			if sum > 0 or not db.onlyWithItem then
				entries[#entries + 1] = { key = key, char = char, counts = counts, auctions = auctions, sum = sum }
			end
		end
	end
	local guildLines = {}
	if db.guild then
		for _, key in ipairs(Store:GuildList(db.scope)) do
			local guild = Store:Guilds()[key]
			local count = guild.counts and guild.counts[itemID] or 0
			if count > 0 then
				total = total + count
				guildLines[#guildLines + 1] = { E:TextHex("good") .. (guild.name or key) .. "|r",
					db.breakdown and (Grey(LOCATION_LABEL.guild) .. " " .. count) or tostring(count) }
			end
		end
	end
	if total < math.max(db.minCount, 1) and db.onlyWithItem then return nil, 0 end
	table.sort(entries, function(a, b)
		if a.key == E.charKey then return true end
		if b.key == E.charKey then return false end
		if a.sum ~= b.sum then return a.sum > b.sum end
		return a.key < b.key
	end)
	local lines = {}
	for index, entry in ipairs(entries) do
		if index > db.maxChars then
			local more, count = #entries - db.maxChars, 0
			for rest = index, #entries do count = count + entries[rest].sum end
			lines[#lines + 1] = { Grey(L["+%d more"]:format(more)), Grey(tostring(count)) }
			break
		end
		local left = (db.icons and ClassIcon(entry.char.class) or "") .. ClassName(entry.char)
		if entry.char.realm ~= GetRealmName() then left = left .. Grey("-" .. (entry.char.realm or "?")) end
		local right = db.breakdown and Breakdown(entry.counts, entry.auctions) or tostring(entry.sum)
		if right == "" then right = Grey("0") end
		lines[#lines + 1] = { left, right }
	end
	for _, line in ipairs(guildLines) do lines[#lines + 1] = line end
	if #lines > 0 then
		lines[#lines + 1] = { " ", "|c" .. AccentHex() .. L["Total: %d"]:format(total) .. "|r" }
	end
	return lines, total
end

-- Item counts show while this module is on, or (with Bags off, e.g. next
-- to another bag addon) while the Characters module is on. Bag addons
-- that show their own counts (Data/Competitors.lua) make EldoUI's step
-- back unless the Characters page says to show both.
function M:CountsActive()
	if self.active then return true end
	local chars = E.modules.Characters
	if not (chars and chars.active) then return false end
	return not E:StandsBack("Characters", "bagcounts")
end

---------------------------------------------------------------------------
-- "Move these": what the bag search shows goes to the open bank,
-- mail, trade window or vendor. Off by default (Transfers tab). One click
-- moves one batch of at most 12 items with the game's own right-click
-- (C_Container.UseContainerItem); there is no timer and no second batch
-- without a second click. Nothing moves in combat, nothing moves to a
-- full target, protected items (Core/ItemProtect.lua) always stay, and a
-- vendor never gets an item on Merchant's "never sell" list.
---------------------------------------------------------------------------
local MOVE_BATCH = 12
local MOVE_TARGET_LABEL = E:TranslateValues({ trade = E.Key("the trade window"), mail = E.Key("the mail"), bank = E.Key("the bank"), vendor = E.Key("the vendor") })

local function Visible(frame)
	return frame and frame.IsShown and frame:IsShown() and true or false
end

-- The open target, in this order: trade, mail (Send Mail tab), bank, vendor.
function M:MoveTarget()
	if Visible(rawget(_G, "TradeFrame")) then return "trade" end
	if Visible(rawget(_G, "SendMailFrame")) then return "mail" end
	if bankOpen then return "bank" end
	if Visible(rawget(_G, "MerchantFrame")) then return "vendor" end
end

-- How many more items the target takes.
function M:MoveRoom(target)
	local free = 0
	if target == "trade" then
		for index = 1, (rawget(_G, "MAX_TRADABLE_ITEMS") or 6) do
			if not GetTradePlayerItemLink(index) then free = free + 1 end
		end
	elseif target == "mail" then
		for index = 1, (ATTACHMENTS_MAX_SEND or 12) do
			if not HasSendMailItem(index) then free = free + 1 end
		end
	elseif target == "bank" then
		free = E.BagCache:GeneralSlots(BankBagIDs(true), FixedBankTabs())
	elseif target == "vendor" then
		free = MOVE_BATCH
	end
	return math.min(free, MOVE_BATCH)
end

-- The bag slots the search shows that may go to `target`. With `category`
-- (a Categories view section key) it is that section's items; an
-- active search narrows them to what the search shows.
function M:MoveCandidates(window, target, category)
	local list = {}
	if not (window and (window.query or category)) then return list end
	local merchant = E.modules.Merchant
	for _, bag in ipairs(BagIDs()) do
		if bag ~= KEYRING then
			for slot = 1, C_Container.GetContainerNumSlots(bag) do
				local record = LiveRecord(bag, slot)
				if not record.empty and not record.locked and (not window.query or Matches(window.query, record))
					and (not category or CategoryOf(record, window) == category) then
					local keep = E.IsItemProtected and E:IsItemProtected(record.id, bag, slot)
					if not keep and target == "vendor" then
						local info = C_Container.GetContainerItemInfo(bag, slot)
						local name = C_Item.GetItemInfo(record.link or record.id)
						keep = (info and info.hasNoValue) or (merchant and merchant.NeverSell and merchant:NeverSell(record.id, name))
					end
					if not keep then list[#list + 1] = { bag = bag, slot = slot } end
				end
			end
		end
	end
	return list
end

-- Shown with the option on, a live bag window, a search (or a category
-- header's menu) and an open target.
function M:MoveReady(window, category)
	if not (self.db.moveThese and window and window.kind == "bags" and IsLive(window) and (window.query or category)) then return nil end
	return self:MoveTarget()
end

-- The line under "Move these" in its tooltip: what a click does now.
function M:MoveTip()
	local target = self:MoveTarget()
	if InCombatLockdown() then return L["Not in combat."] end
	if not target then return L["Open the bank, mail, trade or a vendor first."] end
	return L["Moves up to %d of the items your search shows to %s. One batch per click; quest and recipe items stay."]:format(MOVE_BATCH, MOVE_TARGET_LABEL[target])
end

-- The sort button dims while the game refuses a sort (in combat).
function M:UpdateSortButtons()
	local fight = InCombatLockdown()
	for _, window in pairs(windows) do
		if window.sort then window.sort:SetAlpha(fight and E.tokens.disabledAlpha or 1) end
	end
end

function M:UpdateMoveButton(window)
	local button = window and window.moveButton
	if not button then return end
	local target = self:MoveReady(window)
	local shown = target ~= nil
	button:SetShown(shown)
	if shown then
		window.search:SetPoint("TOPRIGHT", button, "TOPLEFT", -4, 0)
	else
		window.search:SetPoint("TOPRIGHT", window, "TOPRIGHT", -(PAD + RAIL), -36)
	end
	if not shown then return end
	local usable = not InCombatLockdown() and self:MoveRoom(target) > 0
	button:SetEnabled(usable)
	button:SetAlpha(usable and 1 or E.tokens.disabledAlpha)
end

-- One click: one batch. Returns how many items were handed to the game.
-- `category`: only that Categories view section (its header menu).
function M:MoveSearched(window, category)
	if InCombatLockdown() then return 0 end
	local target = self:MoveReady(window, category)
	if not target then return 0 end
	local room = self:MoveRoom(target)
	local list = self:MoveCandidates(window, target, category)
	local bankType = target == "bank" and #TabIDs(BANK_CHARACTER) > 0 and BANK_CHARACTER or nil
	local moved = 0
	for index = 1, math.min(room, #list) do
		local item = list[index]
		C_Container.UseContainerItem(item.bag, item.slot, nil, bankType)
		moved = moved + 1
	end
	return moved
end

-- Category header menu: which sections get one. Item categories of
-- the live bag window in the Categories view, with "Move these" on.
function M:CategoryMenuFor(window, section)
	if not (self.db.moveThese and section and window and window.kind == "bags" and IsLive(window)) then return false end
	if self.db.view ~= "categories" or section.key == "free" or not CATEGORY_TITLE[section.key] and not section.key:find("^custom%d$")
		and not section.key:find("^own:") then
		return false
	end
	return true
end

-- Every section header's right-click menu: hide or show the section and,
-- for the categories that have it, "Move these".
function M:ShowSectionMenu(window, section, anchor)
	if not (section and section.title) then return end
	E.UIKit.ContextMenu(anchor, function(_, root)
		root:CreateTitle(section.title)
		root:CreateButton(section.hidden and L["Show this section"] or L["Hide this section"], function()
			M:SetSectionHidden(window, section, not section.hidden)
		end)
		if self:CategoryMenuFor(window, section) then self:AddMoveEntries(root, window, section) end
		-- Own categories: edit, leave the held item out (Modules/Bags/Categories.lua).
		if M.AddCategoryEntries then M:AddCategoryEntries(root, window, section) end
	end)
end

-- The "Move these" entry: one batch per click, or the reason there is
-- nothing to do yet.
function M:AddMoveEntries(root, window, section)
	local target = self:MoveTarget()
	if InCombatLockdown() then
		root:CreateTitle(L["Not in combat."])
	elseif not target then
		root:CreateTitle(L["Open the bank, mail, trade or a vendor first."])
	elseif self:MoveRoom(target) <= 0 then
		root:CreateTitle(L["No room left there."])
	elseif #self:MoveCandidates(window, target, section.key) == 0 then
		root:CreateTitle(L["Nothing here can go there."])
	else
		root:CreateButton(L["Move these to %s (up to %d)"]:format(MOVE_TARGET_LABEL[target], MOVE_BATCH), function()
			M:MoveSearched(window, section.key)
		end)
	end
end

-- Older name of the header menu.
function M:ShowCategoryMenu(window, section, anchor)
	self:ShowSectionMenu(window, section, anchor)
end

local function TotalOnAccount(itemID)
	M:CheckInventorySettings()
	local totals = M.linesCache.totals
	if totals[itemID] then return totals[itemID] end
	local total = 0
	for _, key in ipairs(Store:Characters("ALL")) do
		local counts = Store:Get(key).counts
		local entry = counts and counts[itemID]
		if entry then total = total + entry[1] + entry[2] + entry[3] + entry[4] end
	end
	if M.linesCache.count < M.linesCache.cap then
		totals[itemID] = total
		M.linesCache.count = M.linesCache.count + 1
	end
	return total
end

-- The current character's fresh carried count and the total in the
-- character inventory snapshots, with the saved carried count replaced.
function E:GatheringItemCounts(itemID)
	if not (M:CountsActive() and M.db.tooltip.enabled and C_Item) then return end
	local count = E.PlainCall(C_Item.GetItemCount, itemID, false, false, false, false)
	if type(count) ~= "number" or count < 0 or count >= math.huge or count % 1 ~= 0 then return end
	if not M.db.altChars then return count end
	local total = TotalOnAccount(itemID)
	local own = Store:Get(E.charKey)
	local saved = own and own.counts and own.counts[itemID]
	local savedBags = saved and saved[1] or 0
	return count, total - savedBags + count
end

function M:HookTooltips()
	if self.tooltipsHooked then return end
	self.tooltipsHooked = true
	-- Kept tooltip lines start over when a record changes or leaves (not
	-- for the parts of a record the lines never read).
	if E.Characters and E.Characters.RegisterCallback then
		local owner = M.linesCache
		E.Characters.RegisterCallback(owner, "Updated", function(_, _, section)
			if not M.LINES_KEEP[section] then M:ForgetInventoryLines() end
		end)
		E.Characters.RegisterCallback(owner, "Forgotten", function() M:ForgetInventoryLines() end)
	end
	-- The shared info area (Modules/Tooltip.lua) renders these whether the
	-- Tooltip module is on or off, so toggling it never loses the lines:
	-- our block is its "Alts and bank" section (it also handles
	-- Always/Shift), and the account-wide vendor value joins its Value row.
	if self.db.tooltip.syncedModifier == nil then self.db.tooltip.syncedModifier = self.db.tooltip.modifier end
	E:RegisterTooltipSection("inventory", { order = 40, title = "Alts and bank",
		desc = "How many of the item each of your characters has, per location (Bags module).",
		default = self.db.tooltip.modifier == "SHIFT" and "shift" or "always",
		item = function(_, _, itemID, add)
			if not itemID or not (M:CountsActive() and M.db.tooltip.enabled) then return end
			local lines = M:InventoryLines(itemID)
			for _, line in ipairs(lines or {}) do add(line[1], line[2], 1, 1, 1) end
		end })
	E:RegisterTooltipValue("bagsTotal", { order = 30, item = function(_, _, itemID)
		if not itemID or not (M:CountsActive() and M.db.tooltip.vendor) then return end
		local price = select(11, C_Item.GetItemInfo(itemID))
		local total = TotalOnAccount(itemID)
		if not price or price <= 0 or total <= 1 then return end
		return Grey(L["all %d: "]:format(total)) .. Money(price * total)
	end })
	-- Currencies across characters: the "Alts: currencies" section, with
	-- the Bags switch below as its on/off.
	E:RegisterTooltipSection("bagsCurrency", { order = 41, title = "Alts: currencies",
		desc = "On a currency: how much of it each of your other characters has (Bags module).",
		currency = function(_, id, add)
			if not (M:CountsActive() and M.db.tooltip.currency) then return end
			if Secret(id) or type(id) ~= "number" then return end
			for _, key in ipairs(Store:Characters(M.db.tooltip.scope)) do
				local char = Store:Get(key)
				local amount = char.currency and char.currency[id]
				if type(amount) == "number" and amount > 0 and key ~= E.charKey then
					add(ClassIcon(char.class) .. ClassName(char), BreakUpLargeNumbers and BreakUpLargeNumbers(amount) or amount, 1, 1, 1, 1, 1, 1)
				end
			end
		end })
end

-- Gold of every character (bag window footer).
function M:AddGoldLines(tooltip)
	local r, g, b = unpack(E.media.accentColor)
	tooltip:AddLine(L["Gold"], r, g, b)
	local total = 0
	local list = Store:Characters("ALL")
	table.sort(list, function(a, b2) return (Store:Get(a).money or 0) > (Store:Get(b2).money or 0) end)
	for _, key in ipairs(list) do
		local char = Store:Get(key)
		total = total + (char.money or 0)
		tooltip:AddDoubleLine(ClassIcon(char.class) .. ClassName(char), Money(char.money or 0), 1, 1, 1, 1, 1, 1)
	end
	tooltip:AddLine(" ")
	tooltip:AddDoubleLine(L["Account"], Money(total), r, g, b, 1, 1, 1)
end

---------------------------------------------------------------------------
-- /eui find and /eui bank
---------------------------------------------------------------------------
function M:Find(text)
	text = strtrim(text or "")
	if text == "" then
		E:Print(L["Usage: /eui find <name or filter>, e.g. /eui find linen or /eui find q:rare t:cloth"])
		return
	end
	local window = windows.bags
	if self:OwnBags() and window then
		window.viewChar = E.charKey
		window.allChars = true
		M.SetRailActive(window.allButton, true)
		if not window:IsShown() then self:OpenBags() end
		window.search:SetText(text)
		self:OpenWindow(window, self:WindowSide(window))
		return
	end
	local lines = {}
	local found = self:FindAll(text)
	for _, entry in ipairs(found) do
		local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(entry.id) or entry.short
		lines[#lines + 1] = ("%s: %d"):format(name or entry.short, entry.total)
		for key, counts in pairs(entry.chars) do
			local parts = {}
			for index, location in ipairs(LOCATIONS) do
				if counts[index] > 0 then parts[#parts + 1] = LOCATION_LABEL[location] .. " " .. counts[index] end
			end
			lines[#lines + 1] = ("    %s: %s"):format(key, table.concat(parts, ", "))
		end
		for key, count in pairs(entry.guilds) do
			lines[#lines + 1] = ("    %s: %s %d"):format(key, LOCATION_LABEL.guild, count)
		end
	end
	E:ShowCopyBox(L["Find: %s"]:format(text), E:Plural(#found, "%d item found on your characters.", "%d items found on your characters."):format(#found),
		#lines > 0 and table.concat(lines, "\n") or L["Nothing found."])
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
-- The question on the shared dialog shell (E:ShowConfirm).
function M:ConfirmForget(name, key)
	E:ShowConfirm({ title = L["Forget %s"]:format(name),
		text = L["Forget %s? Their saved items, gold, mail and auctions leave EldoUI. Log in on them again to record them anew."]:format(name),
		accept = YES, cancel = NO, danger = true, data = key, onAccept = function(chosen) Store:Forget(chosen) end })
end

function M:OnInitialize()
	-- v0.5.0 had one "junk" switch; it is a style now.
	if self.db.junk == false then self.db.junkStyle = "off" end
	self.db.junk = nil
	self:ParseCustomCategories()
	E:AddCommand("find", "<text>  search the items of all your characters", function(arg) M:Find(arg) end)
	E:AddCommand("bank", "show your saved bank anywhere", function()
		if M.active then M:ToggleBank(E.charKey) end
	end)
end

-- Views follow the character store: a forgotten character leaves every
-- window, and new scans redraw the windows that show that record.
-- Record parts no bag view reads (profession item cooldowns, level,
-- quests, reputations, stats and the like):
M.STORE_UNSHOWN = {
	itemCooldowns = true, basics = true, durability = true, lockouts = true, professions = true, recipes = true,
	quests = true, questHistory = true, reps = true, bids = true, calendar = true, stats = true, played = true, levels = true,
}
M.storeDirty = {}
local function WatchStore()
	if M.storeWatched or not (E.Characters and E.Characters.RegisterCallback) then return end
	M.storeWatched = true
	E.Characters.RegisterCallback(M, "Updated", function(_, key, section)
		if not M.active then return end
		-- This character's money or currencies alone change only their line.
		if key == E.charKey and section == "money" then
			M:UpdateMoney()
			return
		elseif key == E.charKey and section == "currency" then
			M:UpdateCurrencyRow()
			return
		elseif M.STORE_UNSHOWN[section] then
			-- Parts of a record the bag window never shows.
			return
		end
		-- Only the windows that show this record redraw: a live window
		-- reads the game and was repainted per bag already. Whether a
		-- window is live is asked when the redraw runs (the bank closing
		-- turns its window into the saved view).
		local any = false
		for _, window in pairs(windows) do
			if window:IsShown() and (window.allChars or window.viewChar == key
				or (IsGuildView(window) and section == "guild")) then
				M.storeDirty[window] = true
				any = true
			end
		end
		if any and not M.storeQueued then
			M.storeQueued = true
			C_Timer.After(0.1, function()
				M.storeQueued = false
				for window in pairs(M.storeDirty) do
					M.storeDirty[window] = nil
					if M.active and (window.allChars or not IsLive(window) or IsGuildView(window)) then M:UpdateWindow(window) end
				end
			end)
		end
	end)
	E.Characters.RegisterCallback(M, "Forgotten", function(_, key)
		for _, window in pairs(windows) do
			if window.viewChar == key then window.viewChar = E.charKey end
		end
		if M.active then M:RefreshViews() end
	end)
end

function M:OnEnable()
	Store:Me()
	if not windows.bags then
		self:CreateWindow("bags")
		self:CreateWindow("bank")
		self.frame = windows.bags
	end
	WatchStore()

	-- The character store (Core/CharacterStore.lua) records the items;
	-- these events only redraw the windows.
	self:RegisterEvent("BAG_UPDATE", function(_, _, bag) M:NoteBagChanged(bag) end)
	self:RegisterEvent("BAG_UPDATE_DELAYED", function()
		M:UpdateBagButtons()
		M:CheckAmmo()
		M:RefreshChangedBags()
	end)
	-- A deposit, a sort or "Move these" changes one bank slot per event:
	-- they are repainted together, a moment after the last one. A bank bag
	-- slot and the other structural events redraw once per burst.
	local function RefreshSoon() Schedule("Refresh", 0.1) end
	self:RegisterEvent("PLAYERBANKSLOTS_CHANGED", function(_, _, slot)
		if type(slot) == "number" and slot <= (rawget(_G, "NUM_BANKGENERIC_SLOTS") or 28) then
			M:NoteBagChanged((Enum.BagIndex and Enum.BagIndex.Bank) or rawget(_G, "BANK_CONTAINER") or -1)
			M:RefreshChangedSoon()
		else
			RefreshSoon()
		end
	end)
	self:RegisterEvent("PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", RefreshSoon)
	self:RegisterEvent("BANK_TABS_CHANGED", RefreshSoon)
	self:RegisterEvent("BAG_CONTAINER_UPDATE", RefreshSoon)
	self:RegisterEvent("BAG_SLOT_FLAGS_UPDATED", RefreshSoon)
	self:RegisterEvent("BANKFRAME_OPENED", function() M:OnBankOpened() end)
	self:RegisterEvent("BANKFRAME_CLOSED", function() M:OnBankClosed() end)
	-- These change one part of a window: only that part redraws.
	self:RegisterEvent("PLAYER_MONEY", function() M:UpdateMoney() end)
	self:RegisterEvent("CURRENCY_DISPLAY_UPDATE", function() M:UpdateCurrencyRow() end)
	self:RegisterEvent("ITEM_LOCK_CHANGED", function(_, _, bag, slot) M:UpdateLock(bag, slot) end)
	-- Quests change the lock marks, on Blizzard's bag windows too.
	-- Quest items: the shown bags repaint (the categories view, where an
	-- item changes section, redraws whole).
	local function QuestsChanged()
		for _, window in pairs(windows) do
			if window:IsShown() and IsLive(window) then
				local _, ids = VisibleIDs(window)
				for _, bag in ipairs(ids) do M:NoteBagChanged(bag) end
			end
		end
		M:RefreshChangedSoon()
		if M.RepaintBlizzardBags then M:RepaintBlizzardBags() end
	end
	self:RegisterEvent("QUEST_ACCEPTED", QuestsChanged)
	self:RegisterEvent("QUEST_REMOVED", QuestsChanged)
	local function MoveTargetChanged() M:UpdateMoveButton(windows.bags) end
	for _, event in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_INFO_UPDATE", "TRADE_SHOW", "TRADE_CLOSED",
		"TRADE_PLAYER_ITEM_CHANGED", "MERCHANT_SHOW", "MERCHANT_CLOSED" }) do
		self:RegisterEvent(event, MoveTargetChanged)
	end
	-- In combat the game refuses a sort and a move: both buttons dim.
	local function CombatChanged(_, event)
		if event == "PLAYER_REGEN_DISABLED" then M:CloseForCombat() end
		MoveTargetChanged()
		M:UpdateSortButtons()
	end
	self:RegisterEvent("PLAYER_REGEN_DISABLED", CombatChanged)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", CombatChanged)
	self:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player", function() M:UpdateBagButtons(); M:CheckAmmo() end)
	self:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
		if waitingForInfo then Schedule("Refresh", 0.3) end
	end)
	self:HookTooltips()
	self:EnableAutoBags()

	self:SyncModes()
	self:ApplyBagElement()
	self:ApplyBankElement()
	self:UpdateBagButtons()
	-- Slot buttons for the bags, ready for a first open in combat.
	E:RegisterEvent("PLAYER_REGEN_ENABLED", function() M:PrebuildLiveSlots() end, M.prebuildEvents)
	E:RegisterEvent("BAG_CONTAINER_UPDATE", function() M:PrebuildLiveSlots() end, M.prebuildEvents)
	self:PrebuildLiveSlots()
end

function M:OnDisable()
	if self.ResetLowestValue then self:ResetLowestValue() end
	if self.ClearTradeMarks then self:ClearTradeMarks() end
	E:UnregisterEvent("PLAYER_REGEN_ENABLED", M.prebuildEvents)
	E:UnregisterEvent("BAG_CONTAINER_UPDATE", M.prebuildEvents)
	self:DisableAutoBags()
	self:WatchCooldowns()
	for _, window in pairs(windows) do window:Hide() end
	self:RestoreBagFrames()
	if BankFrame then E:RunOutOfCombat(function() RestoreParent(BankFrame) end) end
	if self.DisableBlizzard then self:DisableBlizzard() end
	E:ShowReloadPrompt(L["Bags switched off. Blizzard's bags come fully back after a reload."])
end

-- Bags > "Show the block" and Tooltip > "Alts and bank" pick the same thing;
-- a change here is written to the tooltip section (the last one changed
-- applies). The first look only remembers the value, so it never
-- overwrites a choice made on the Tooltip page.
function M:SyncTooltipMode()
	local db = self.db.tooltip
	if db.syncedModifier ~= nil and db.syncedModifier ~= db.modifier then
		E:SetTooltipSectionMode("inventory", db.modifier == "SHIFT" and "shift" or "always")
	end
	db.syncedModifier = db.modifier
end

function M:OnProfileChanged()
	if self.ResetLowestValue then self:ResetLowestValue() end
	self:SyncTooltipMode()
	if not self.active then return end
	self:ParseCustomCategories()
	self:SyncModes()
	E:RunOutOfCombat(function()
		self:ApplyBagElement()
		self:ApplyBankElement()
		self:UpdateBagButtons()
		for _, window in pairs(windows) do
			for _, button in ipairs(window.barButtons) do E:SetTemplate(button) end
			self:PlaceWindow(window)
		end
		self:RestyleSlotTexts()
		self:RefreshViews()
	end)
end

---------------------------------------------------------------------------
-- Options and styles
---------------------------------------------------------------------------
local function ForgetValues()
	local values = { [""] = "Choose a character" }
	-- Also characters that asked not to be recorded: they can be forgotten.
	for _, key in ipairs(Chars():Keys("account", true)) do
		if key ~= E.charKey then values[key] = key end
	end
	for _, key in ipairs(Store:GuildList("ALL")) do values["guild:" .. key] = L["Guild bank: %s"]:format(key) end
	return values
end

-- "Custom" is a state, not a choice: it shows only while the Blizzard UI page
-- has a mix of switches that none of the three modes covers.
local function ModeValues(key)
	return function()
		local values = { blizzard = "Blizzard", skin = "Blizzard, EldoUI skin", eldoui = "EldoUI window" }
		if M.db and M.db[key] == "custom" then values.custom = "Custom (Blizzard UI page)" end
		return values
	end
end
local VIEW_VALUES = { single = "One grid", categories = "Categories", bags = "Bag by bag" }

local function NotCategories() return M.db and M.db.view ~= "categories" and M.db.bankView ~= "categories" end
-- Rows that only act in the Categories view are grayed with the reason in
-- the other views.
local function OnlyCategories()
	if NotCategories() then return L["Pick Categories as the bag or bank view first."] end
end
local function NotOneGrid()
	if M.db and M.db.view ~= "single" and M.db.bankView ~= "single" then return L["Pick One grid as the bag or bank view first."] end
end
local OUTLINE_VALUES = { DEFAULT = "Theme (General)", NONE = "None", OUTLINE = "Outline", THICKOUTLINE = "Thick outline" }
local POINT_VALUES = { TOPLEFT = "Top left", TOP = "Top", TOPRIGHT = "Top right", LEFT = "Left", CENTER = "Center",
	RIGHT = "Right", BOTTOMLEFT = "Bottom left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom right" }

-- Preview: two rows of sample slots in the bag window's columns (up to
-- twelve), slot size, spacing and quality borders (E:ConfigSample,
-- Core/MoverSamples.lua).
local function UpdatePreview(canvas)
	local db = M.db
	if not (canvas and db) then return end
	E:ConfigSample(canvas, "grid", {
		columns = math.min(db.columns or 12, 12), rows = 2, size = db.size, spacing = db.spacing,
		qualities = db.qualityBorder,
	})
end

M.options = {
	{ type = "tab", label = "Windows" },
	{ type = "preview", label = "Preview", height = 96, create = UpdatePreview, update = UpdatePreview,
		desc = "Sample bag slots in your slot size, spacing and quality borders." },
	{ type = "header", label = "Mode" },
	{ type = "description", label = "Pick which bag windows you use: the same as the Bags and Bank switches on the Blizzard UI page." },
	{ type = "select", key = "bagMode", label = "Bags", values = ModeValues("bagMode"),
		desc = "Blizzard: the game's bags, untouched. Skin: the game's bags in the EldoUI look. EldoUI window: one window with categories, offline view and more." },
	{ type = "select", key = "bankMode", label = "Bank", values = ModeValues("bankMode"),
		desc = "Blizzard: the game's bank, untouched. Skin: the game's bank in the EldoUI look. EldoUI window: the bank in the bag window's style, with offline view." },
	{ type = "select", key = "guildBank", label = "Guild bank", hidden = NoGuildBank, values = { blizzard = "Blizzard", skin = "EldoUI skin", eldoui = "EldoUI window" },
		desc = "EldoUI skin dresses the game's guild bank window (Bank switch with Skin on). EldoUI window shows the guild bank in EldoUI's own window, on the Guild bank mover." },
	{ type = "header", label = "Layout" },
	{ type = "select", key = "view", label = "Bag view", values = VIEW_VALUES,
		desc = "One grid of every slot, sections by item type (Categories), or one section per bag." },
	{ type = "select", key = "bankView", label = "Bank view", values = VIEW_VALUES,
		desc = "The same choice for the bank window." },
	{ type = "range", key = "columns", label = "Bag columns", desc = "Slots per row in the bag window.", min = 6, max = 24, step = 1 },
	{ type = "range", key = "bankColumns", label = "Bank columns", desc = "Slots per row in the bank window.", min = 6, max = 30, step = 1 },
	{ type = "range", key = "size", label = "Slot size", desc = "Size of each slot in pixels.", min = 24, max = 52, step = 1 },
	{ type = "range", unit = "px", key = "spacing", label = "Spacing", desc = "Gap between slots in pixels.", min = 0, max = 10, step = 1 },
	{ type = "range", percent = true, key = "scale", label = "Window scale", desc = "Size of the bag, bank and guild bank windows, from 50 to 150 percent.", min = 0.5, max = 1.5, step = 0.05 },
	{ type = "toggle", key = "reverse", label = "Fill from the bottom", desc = "One-grid view: the first bag slot sits at the bottom right instead of the top left.", disabled = NotOneGrid },
	{ type = "toggle", key = "packSections", label = "Pack sections", desc = "Small sections (categories or bags) share a row instead of starting a new one." },
	{ type = "execute", label = "Show hidden sections", testSafe = true, func = function() M:ShowAllSections() end,
		disabled = function() return not M:HasHiddenSections() and L["No section is hidden."] or false end,
		desc = "Shows every section you hid on this character. Right-click a section's title in the bag or bank window to hide it; click a hidden title to show it again." },
	{ type = "toggle", key = "bagBar", label = "Bag bar in the window", desc = "A row of your bags (or bank tabs) under the search box: click one to hide or show its slots, drag bags in and out, right-click for the game's bag options." },
	{ type = "toggle", key = "currencies", label = "Tracked currencies", desc = "Currencies you track in the game's currency list (Show on backpack) appear over the footer of the bag window." },
	{ type = "toggle", key = "gold", label = "Gold", desc = "Your gold in the footer; hover it for every character's gold." },
	{ type = "select", key = "footerSlots", label = "Slot counter", values = { free = "Free slots", used = "Used of total" }, order = { "free", "used" },
		desc = "How the bag and bank footers display space. Hover the count to see the bags separately." },
	{ type = "toggle", key = "keyring", label = "Keyring", desc = "Shows the keyring's slots in the bag window, in their own section." },
	{ type = "toggle", key = "reagentSection", label = "Reagent bag in its own section", desc = "One-grid view: the reagent bag gets its own section. Off puts its slots into the main grid.", disabled = NotOneGrid },
	{ type = "toggle", key = "accountBank", label = "Account bank", desc = "Shows the account bank pages in the bank window when the game lets you view them.", hidden = NoAccountBank },
	{ type = "select", key = "moneyFormat", label = "Money style", desc = "How gold is written in the bag windows and their tooltips. \"Use general setting\" follows Fonts and text > Money.",
		values = function() return E:MoneyStyleValues(true) end },
	{ type = "toggle", key = "clearSearch", label = "Clear the search when a window closes", desc = "Empties the search box each time the bag or bank window closes, so the next open shows every item." },
	{ type = "toggle", key = "growFromMover", label = "Grow away from the screen edge",
		desc = "The windows open from the corner of their mover that faces the middle of the screen, so a bag mover on the left side grows to the right. Off: bags grow up and left, the bank down and right." },
	{ type = "select", key = "strata", label = "Window layer", desc = "Which layer of the screen the windows sit on. Higher layers cover more of the other windows.",
		values = { MEDIUM = "Medium", HIGH = "High (default)", DIALOG = "Dialog (over most windows)" }, cog = true },
	{ type = "header", label = "Open and close with" },
	{ type = "description", label = "Which windows open your bags with them. A window only closes the bags it opened; bags you opened yourself stay open." },
	{ type = "cog", label = "Close bags", desc = "Choose when open bags close.", options = {
		{ type = "toggle", key = "autoClose.combat", label = "In combat",
			desc = "Closes open bags as combat starts. Bags opened during combat stay open." },
	} },
	{ type = "header", label = "Sorting" },
	{ type = "toggle", key = "sortButton", label = "Sort button", desc = "Shows the broom that runs the game's own bag and bank sort. Right-click it at the bank to sort the account bank." },
	{ type = "select", key = "sortDirection", label = "Sort direction", desc = "The game's own sort setting. Game setting leaves it as it is.",
		values = { game = "Game setting", ltr = "Top-down", rtl = "Bottom-up" } },
	{ type = "select", key = "insertDirection", label = "New items go to", desc = "Choose which bag receives new items first. Game setting leaves the current choice unchanged.",
		values = { game = "Game setting", first = "First bag", last = "Last bag" }, order = { "game", "first", "last" } },
	{ type = "description", label = "Right-click a bag in the bag bar, or a bank tab, to keep it out of sorting or give it a kind of item. Sorting is always the game's own." },

	{ type = "tab", label = "Slots" },
	{ type = "header", label = "Borders and marks" },
	{ type = "toggle", key = "qualityBorder", label = "Quality borders", desc = "Colors the slot border with the game's item quality color." },
	{ type = "select", key = "minQuality", label = "Lowest quality with a border", desc = "Items below this quality keep the plain border.", dependsOn = "qualityBorder",
		values = { [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic" } },
	{ type = "toggle", key = "questBorder", label = "Yellow border on quest items", desc = "Quest items and items that start a quest." },
	{ type = "toggle", key = "itemLevel", label = "Item level on gear", desc = "Weapons and armor show their item level in the corner, in the quality color.",
		cog = {
			{ type = "range", key = "text.levelSize", label = "Text size", desc = "Size of the item level number.", min = 8, max = 20, step = 1 },
			{ type = "select", key = "text.levelOutline", label = "Outline", desc = "Outline around the item level (and the bind text).", values = OUTLINE_VALUES },
			{ type = "select", key = "text.levelPoint", label = "Position", desc = "Corner or edge of the slot the item level sits in.", values = POINT_VALUES },
			{ type = "range", unit = "px", key = "text.levelX", label = "X offset", desc = "Moves the item level left or right, in pixels.", min = -12, max = 12, step = 1 },
			{ type = "range", unit = "px", key = "text.levelY", label = "Y offset", desc = "Moves the item level up or down, in pixels.", min = -12, max = 12, step = 1 },
			{ type = "select", key = "text.levelColor", label = "Color", desc = "The game's quality color of the item, or one color for every item level.",
				values = { quality = "Item quality", custom = "Custom color" } },
			{ type = "color", key = "text.levelCustom", label = "Custom color", desc = "Color of every item level number.", hidden = function() return M.db.text.levelColor ~= "custom" end },
		} },
	{ type = "range", key = "itemLevelMin", label = "Item level from", desc = "Gear below this item level shows no number.", min = 1, max = 100, step = 1, dependsOn = "itemLevel" },
	{ type = "toggle", key = "boundText", label = "BoE and BoU text", desc = "Gear that binds when equipped or used and is not bound yet says so in the bottom corner.",
		cog = { { type = "range", key = "text.bindSize", label = "Text size", desc = "Size of the BoE and BoU text.", min = 7, max = 16, step = 1 } } },
	{ type = "toggle", key = "tradeTime", label = "Tradeable loot", desc = "Show how many minutes remain to trade bound loot with eligible group members. On by default." },
	{ type = "range", key = "text.countSize", label = "Stack count size", desc = "Size of the number of items in a stack.", min = 8, max = 22, step = 1,
		cog = {
			{ type = "select", key = "text.countOutline", label = "Outline", desc = "Outline around the stack count.", values = OUTLINE_VALUES },
			{ type = "select", key = "text.countPoint", label = "Position", desc = "Corner or edge of the slot the stack count sits in.", values = POINT_VALUES },
			{ type = "range", unit = "px", key = "text.countX", label = "X offset", desc = "Moves the stack count left or right, in pixels.", min = -12, max = 12, step = 1 },
			{ type = "range", unit = "px", key = "text.countY", label = "Y offset", desc = "Moves the stack count up or down, in pixels.", min = -12, max = 12, step = 1 },
		} },
	{ type = "toggle", key = "cooldowns", label = "Item cooldowns", desc = "Potions, hearthstones and other items on cooldown show the game's cooldown swipe on their slot.",
		cog = { { type = "select", key = "cooldownText", label = "Countdown numbers", desc = "Numbers on the swipe: EldoUI's cooldown text (Fonts and text page), the game's own (its Action Bars setting), or none.",
			values = { eldoui = "EldoUI cooldown text", blizzard = "Game setting", off = "None" } } } },
	{ type = "select", key = "junkStyle", label = "Mark junk", desc = "A coin, a darker icon, both, or nothing. Live bag marks follow Merchant's junk rules while that module is on, and mark gray items while it is off.",
		values = { coin = "Coin icon", dim = "Darken", both = "Coin and darken", off = "Off" } },
	{ type = "toggle", key = "knownTint", label = "Tint items you already know",
		desc = "Recipes, mounts, pets and toys you already know or own get a green icon, like at the merchant and the auction house." },
	{ type = "toggle", key = "newGlow", label = "Glow on new items", desc = "Items you just got glow until you close your bags." },
	{ type = "toggle", key = "lowestValueMark", label = "Mark the lowest value stack",
		desc = "When five or fewer ordinary slots are free, marks the lowest value eligible stack. Protected stacks stay unmarked." },
	{ type = "toggle", key = "bagTint", label = "Tint the slots of profession bags", desc = "Empty slots of herb, enchanting and other special bags get a green border." },
	{ type = "toggle", key = "markUnusable", label = "Red icon on items you can't use",
		desc = "Gear, recipes and other items this character can't use yet (level, skill, class or armor type) get a red icon, as the game's tooltip shows in red." },
	{ type = "toggle", key = "markPetFood", label = "Pet food",
		desc = "Hunters with a pet see a food mark on bag items their current pet can eat." },
	{ type = "toggle", key = "markSets", label = "Mark equipment set items", desc = "Items in one of your equipment sets get a small mark in the bottom corner." },
	{ type = "toggle", key = "markFade", label = "Fade what the open window can't take",
		desc = "With a vendor, the Send Mail tab, the auction house or the socket window open, items it can't take fade, like a search miss: no sell price, soulbound, not for sale, not a gem." },
	{ type = "toggle", key = "flashSame", label = "Alt-click shows the same item",
		desc = "Alt-click a slot: every slot with the same item flashes in the bag and bank windows. Nothing else happens with the item." },
	{ type = "header", label = "Action bar bag buttons" },
	{ type = "toggle", key = "bagButtonFree", label = "Free slots on special bag buttons", desc = "Writes the free slots (or ammo left, on a quiver) on Blizzard's bag bar buttons of special bags.", disabled = E:BlizzardNeeds("bags-containers", "improve") },
	{ type = "toggle", key = "ammoWarn", label = "Warn when ammo runs low", desc = "Hunters: one message and sound when ammo drops below the amount below, again only after restocking." },
	{ type = "toggle", key = "ammoWarnAll", label = "Also for warriors and rogues", desc = "The low ammo warning also for a warrior or rogue with a bow, gun or crossbow.", hidden = function() return not M.db.ammoWarn end },
	{ type = "media", key = "ammoSound", label = "Low ammo sound", mediaKind = "sound", none = true,
		desc = "The sound with the low ammo warning. None for only the message.", hidden = function() return not M.db.ammoWarn end },
	{ type = "range", key = "ammoThreshold", label = "Low ammo below", desc = "Ammo count that turns red and triggers the warning.", min = 50, max = 2000, step = 50 },
	{ type = "header", label = "Blizzard's windows (skin and move)" },
	{ type = "range", percent = true, key = "blizzard.scale", label = "Scale of Blizzard's bags", desc = "With Move on for Bags: the size of the game's bag windows on the EldoUI mover.", min = 0.5, max = 1.5, step = 0.05 },
	{ type = "range", percent = true, key = "blizzard.bankScale", label = "Scale of Blizzard's bank", desc = "With Move on for the Bank: the size of the game's bank and guild bank windows on their EldoUI movers.", min = 0.5, max = 1.5, step = 0.05 },
	{ type = "select", key = "blizzard.combined", label = "Blizzard's bag windows", desc = "The game's own setting: one combined bag or one window per bag. Game setting leaves it as it is. Needs the Bags switch on.",
		values = { game = "Game setting", combined = "One combined bag", separate = "One window per bag" } },

	{ type = "tab", label = "Categories" },
	{ type = "description", label = "The Categories view sorts items into sections; one that is off goes to Other. Your own categories come first and use the search syntax." },
	{ type = "toggle", key = "compactEmpty", label = "One slot per bag type for free space", desc = "Free space shows as one slot per bag type with the number free; drop items on it. Off shows every free slot.", disabled = OnlyCategories },
	{ type = "toggle", key = "groupItems", label = "Group stacks", disabled = OnlyCategories,
		desc = "Stacks of the same item show as one slot with the total count. A click, drag or split acts on one of the stacks, as on any slot, and the tooltip says how many stacks there are." },
	{ type = "toggle", key = "groupPartial", label = "Keep partial stacks apart", dependsOn = "groupItems", disabled = OnlyCategories,
		desc = "Only full stacks are grouped; a stack that is not full keeps its own slot." },
	{ type = "toggle", key = "groupApart", label = "Stacks apart at a vendor, mail, bank or trade", dependsOn = "groupItems", disabled = OnlyCategories,
		desc = "While a vendor, the Send Mail tab, the bank or a trade is open, every stack shows on its own slot, so you can pick the one you want." },
	{ type = "toggle", key = "categories.new", label = "New", desc = "Items you just got, until you close your bags.", hidden = NotCategories },
	{ type = "toggle", key = "categories.equipment", label = "Equipment", desc = "Weapons and armor.", disabled = OnlyCategories },
	{ type = "toggle", key = "categories.consumable", label = "Consumables", desc = "Food, potions, scrolls, bandages and the like.", disabled = OnlyCategories },
	{ type = "toggle", key = "categories.quest", label = "Quest items", desc = "Items for quests and items that start one.", disabled = OnlyCategories },
	{ type = "toggle", key = "categories.tradegoods", label = "Trade goods", desc = "Trade goods, reagents, gems and enhancements.", disabled = OnlyCategories },
	{ type = "toggle", key = "categories.recipe", label = "Recipes", desc = "Recipes, patterns, plans and formulas.", disabled = OnlyCategories },
	{ type = "toggle", key = "categories.ammo", label = "Ammo", desc = "Arrows and bullets.", disabled = OnlyCategories },
	{ type = "toggle", key = "categories.container", label = "Bags", desc = "Bags and quivers you carry.", disabled = OnlyCategories },
	{ type = "toggle", key = "categories.keys", label = "Keys", desc = "Keys outside the keyring.", disabled = OnlyCategories },
	{ type = "toggle", key = "categories.junk", label = "Junk", desc = "Gray items, at the end.", disabled = OnlyCategories },
	{ type = "header", label = "Your categories" },
	{ type = "description", label = "Make your own categories with a name, color, search and place. Drop an item on a section title in the bag window to file it there." },
	{ type = "execute", label = "Edit categories", testSafe = true, func = function() if M.ShowCategoryEditor then M:ShowCategoryEditor() end end,
		desc = "Opens the category editor: add, rename, color, order and share your categories, and turn the built-in sections on or off." },

	{ type = "tab", label = "Transfers" },
	{ type = "header", label = "Move what you searched" },
	{ type = "toggle", key = "moveThese", label = "\"Move these\" button",
		desc = "Off by default. At the bank, mail, trade or a vendor, a button by the search box moves up to 12 searched items per click. Quest, recipe and never-sell items stay." },
	{ type = "header", label = "Protection" },
	{ type = "toggle", key = "protectItems", label = "Protect quest and recipe items",
		desc = "A small lock on items an open quest needs, items that start a quest you haven't done, and recipes one of your characters can still learn. On by default." },

	{ type = "tab", label = "Characters" },
	{ type = "header", label = "Item counts in tooltips" },
	{ type = "description", label = "Each character's bags, bank, gear, mail and gold are kept. Search with words or filters (q:rare, ilvl>50); /eui find searches them all." },
	{ type = "toggle", key = "altChars", label = "Other characters", desc = "Off: the windows, search and tooltips use only this character. Saved data stays until you forget it." },
	{ type = "toggle", key = "tooltip.enabled", label = "Inventory block in item tooltips", desc = "Lists how many of the item each character has, per location." },
	{ type = "select", key = "tooltip.modifier", label = "Show the block", dependsOn = "tooltip.enabled", desc = "Always, or only while you hold Shift. Tooltip > Info area > Alts and bank sets the same thing (also Ctrl, Alt or Never); the one you changed last applies.",
		values = { ALWAYS = "Always", SHIFT = "While holding Shift" } },
	{ type = "toggle", key = "tooltip.includeCurrent", label = "Include this character", dependsOn = "tooltip.enabled", desc = "Off lists only your other characters." },
	{ type = "select", key = "tooltip.scope", label = "Characters to include", desc = "Which of your other characters the block and currency tooltips list.",
		values = { FACTION = "Same realm and faction", REALM = "Same realm", ALL = "All realms" } },
	{ type = "toggle", key = "tooltip.onlyWithItem", label = "Only characters that have the item", dependsOn = "tooltip.enabled", desc = "Off lists every character, with 0 where they have none." },
	{ type = "range", key = "tooltip.minCount", label = "Hide below this total", dependsOn = "tooltip.enabled", desc = "The block only shows when your characters have at least this many together.", min = 1, max = 50, step = 1 },
	{ type = "range", key = "tooltip.maxChars", label = "Most characters listed", dependsOn = "tooltip.enabled", desc = "The rest are summed up in a \"+N more\" line.", min = 1, max = 20, step = 1 },
	{ type = "toggle", key = "tooltip.icons", label = "Class icons", dependsOn = "tooltip.enabled", desc = "A class icon before each name." },
	{ type = "toggle", key = "tooltip.breakdown", label = "Count per location", dependsOn = "tooltip.enabled", desc = "Bags, Bank, Mail, Equipped and Auctions separately. Off shows one number per character." },
	{ type = "toggle", key = "tooltip.guild", label = "Guild banks", dependsOn = "tooltip.enabled", hidden = NoGuildBank, desc = "Adds the count in the guild banks you have opened (cached per guild)." },
	{ type = "toggle", key = "tooltip.vendor", label = "Vendor value of all copies", desc = "Adds what all copies on your characters sell for to the tooltip's value line." },
	{ type = "toggle", key = "tooltip.currency", label = "Currency counts of other characters", desc = "Adds your other characters' amounts to currency tooltips.", disabled = E:BlizzardNeeds("tooltips", "improve") },
	{ type = "header", label = "Saved characters" },
	{ type = "select", key = "forget", label = "Character to forget", desc = "Pick a character or guild bank whose saved items and gold you want removed.", values = ForgetValues },
	{ type = "execute", label = "Forget this character", desc = "Removes the saved data picked above. Log in on it (or open the guild bank) to save it again.", func = function()
		local key = M.db.forget
		if key and key ~= "" then
			M:ConfirmForget(key, key)
			M.db.forget = ""
			if E.RefreshConfig then E:RefreshConfig() end
		end
	end },
}

-- One row per window: "open with" and, in its gear, "close with".
do
	local at
	for index, option in ipairs(M.options) do
		if option.type == "header" and option.label == "Open and close with" then at = index + 2 end
	end
	for offset, info in ipairs(M.autoWindows) do
		local kind, label, game, noun = info[1], info[2], info[3], info[4]
		table.insert(M.options, at + offset - 1, { type = "toggle", key = "autoOpen." .. kind, label = label,
			hidden = kind == "guildbank" and NoGuildBank or nil,
			desc = "Opens your bags when the %s window opens (by default %s).", descFill = { noun, game },
			cog = { { type = "toggle", key = "autoClose." .. kind, label = "Close bags with it",
				desc = "Closes the bags again when the %s window closes, if it opened them.", descFill = noun } } })
	end
end

E:RegisterStyles("Bags", {
	{ key = "Standard", title = "Standard", desc = "One grid, 12 columns, 38 px slots, every marker on.",
		settings = { view = "single", bankView = "single", columns = 12, bankColumns = 14, size = 38, spacing = 4, itemLevel = true,
			qualityBorder = true, minQuality = 2, newGlow = true, junkStyle = "both", bagTint = true, bagBar = false } },
	{ key = "Sorted", title = "Sorted", desc = "Categories view: equipment, consumables, trade goods and more in their own sections, with the bag bar.",
		settings = { view = "categories", bankView = "categories", columns = 12, bankColumns = 16, size = 36, spacing = 4,
			packSections = true, compactEmpty = true, bagBar = true } },
	{ key = "Compact", title = "Compact", desc = "Small slots in wide rows, for big bags.",
		settings = { view = "single", columns = 16, bankColumns = 18, size = 32, spacing = 2, scale = 1 } },
	{ key = "Roomy", title = "Roomy", desc = "Large slots with more space between them.",
		settings = { columns = 10, bankColumns = 12, size = 44, spacing = 6 } },
	{ key = "Clean", title = "Clean", desc = "Only quality borders: no item level, coins, tints, bind text or glow.",
		settings = { itemLevel = false, junkStyle = "off", bagTint = false, newGlow = false, boundText = false, qualityBorder = true, minQuality = 3 } },
	{ key = "Collector", title = "Collector", desc = "Bag by bag with the bag bar, borders from common quality up and every marker.",
		settings = { view = "bags", bankView = "bags", bagBar = true, itemLevel = true, junkStyle = "both", bagTint = true, newGlow = true,
			questBorder = true, qualityBorder = true, minQuality = 1, boundText = true } },
	{ key = "Classic", title = "Classic order", desc = "One grid that fills from the bottom right, like the old bag windows.",
		settings = { view = "single", reverse = true, columns = 8, bankColumns = 14, size = 38, spacing = 4 } },
})
