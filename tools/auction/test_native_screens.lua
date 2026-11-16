-- Offline test for the Auction House module: Blizzard's screens under
-- EldoUI's pages (F22).
-- Run from the repository root:
--   lua5.1 tools/auction/test_native_screens.lua
-- Seen in the game (16.11.2026, WoW: Forever 1.60.1): an item right-clicked
-- into Blizzard's Sell screen, then EldoUI's Quick Sell tab, then
-- Blizzard's Sell tab again: the window stayed empty (only its title), and
-- the item could not be sold. Blizzard's SetDisplayMode returns at once
-- when asked for the mode it already shows (Blizzard_AuctionHouseFrame.lua,
-- 12.1.7): it then shows no screen, while EldoUI's hook took for granted
-- that it had and left its put-away screens hidden.
-- This cuts the real code out of EldoUI/Modules/Auction.lua between fixed
-- markers (a renamed part makes the test fail instead of testing a stale
-- copy): the screen bookkeeping (PutAway, HideNative, RestoreNative,
-- OnBlizzardDisplayMode) and ShowPage / HidePanel. Blizzard's window is a
-- model written after its SetDisplayMode, SetPostItem and tabs (not
-- Blizzard's code).
-- Checked: Blizzard's Sell tab after Quick Sell with an item in its slot
-- (the case from the game) and its Buy tab after the Shopping List bring
-- the screens back; a tab with a new mode leaves the screens to Blizzard
-- and only brings back the title and close button; a bag item clicked on
-- Quick Sell restores and puts away again, so a later Sell tab still works;
-- closing the window brings everything back; a protected screen waits for
-- the end of a fight.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/auction/") or "./"

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

local AUCTION = ReadFile("EldoUI/Modules/Auction.lua")
local SCREENS = Between(AUCTION, "local NATIVE_SCREENS", "function M:CreatePanel()", "Auction.lua screens")
local PAGES = Between(AUCTION, "function M:ShowPage(name)", "local function Allowed(action)", "Auction.lua pages")
assert(SCREENS:find("function M:OnBlizzardDisplayMode", 1, true), "Auction.lua: OnBlizzardDisplayMode is gone")
assert(AUCTION:find('hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", function() M:OnBlizzardDisplayMode() end)', 1, true),
	"Auction.lua: SetDisplayMode is no longer hooked to OnBlizzardDisplayMode")

---------------------------------------------------------------------------
-- Model of Blizzard's auction window
---------------------------------------------------------------------------
local world

local function NewFrame(name, shown)
	local frame = { name = name, shown = shown or false, protected = false, shows = 0 }
	function frame.Show(self) self.shown = true; self.shows = self.shows + 1 end
	function frame.Hide(self) self.shown = false end
	function frame.SetShown(self, on) if on then self:Show() else self:Hide() end end
	function frame.IsShown(self) return self.shown end
	return frame
end

-- Display modes as Blizzard_AuctionHouseFrame.lua lists them (12.1.7).
local MODES = {
	Buy = { "CategoriesList", "SearchBar", "BrowseResultsFrame" },
	ItemBuy = { "CategoriesList", "SearchBar", "ItemBuyFrame" },
	CommoditiesBuy = { "CategoriesList", "SearchBar", "CommoditiesBuyFrame" },
	ItemSell = { "ItemSellFrame", "ItemSellList" },
	CommoditiesSell = { "CommoditiesSellFrame", "CommoditiesSellList" },
	Auctions = { "AuctionsFrame" },
}

local function NewAuctionHouse()
	local ahf = NewFrame("AuctionHouseFrame", true)
	for _, mode in pairs(MODES) do
		for _, name in ipairs(mode) do ahf[name] = ahf[name] or NewFrame(name) end
	end
	for _, name in ipairs({ "WoWTokenResults", "WoWTokenSellFrame" }) do ahf[name] = NewFrame(name) end
	for _, name in ipairs({ "TitleContainer", "TitleText", "CloseButton" }) do ahf[name] = NewFrame(name, true) end
	ahf.sellItem = nil
	function ahf.GetDisplayMode(self) return self.displayMode end
	-- SetDisplayMode: a sell mode with an item in the slot becomes that item's
	-- mode; the mode it already shows returns at once; else every screen of
	-- another mode hides and the mode's own show. EldoUI's hook runs after.
	function ahf.SetDisplayMode(self, mode)
		if mode == MODES.ItemSell or mode == MODES.CommoditiesSell then
			if self.sellItem then mode = MODES[self.sellItem] end
		end
		if self.displayMode ~= mode then
			self.displayMode = mode
			local show = {}
			for _, other in pairs(MODES) do
				for _, name in ipairs(other) do show[name] = show[name] or other == mode end
			end
			for name, on in pairs(show) do if not on then self[name]:Hide() end end
			for _, name in ipairs(mode) do self[name]:Show() end
		end
		world.M:OnBlizzardDisplayMode()
	end
	-- SetPostItem: clears the slot, then the item's sell mode.
	function ahf.SetPostItem(self, kind)
		self.sellItem = nil
		self:SetDisplayMode(MODES[kind])
		self.sellItem = kind
	end
	-- A Blizzard tab: its own handler, then EldoUI's HookScript.
	function ahf.ClickTab(self, mode)
		self:SetDisplayMode(MODES[mode])
		world.M:HidePanel()
		world.M.lastPage = nil
	end
	return ahf
end

local function NewWorld()
	world = { combat = false, now = 1000, queued = {} }
	local ahf = NewAuctionHouse()
	_G.AuctionHouseFrame = ahf
	local M = { panel = NewFrame("EldoUI_AuctionPanel") }
	M.panel.title = { SetText = function() end }
	function M.ClearStatus() end
	function M.UpdateMoney() end
	function M.UpdateTabStates() end
	world.M = M
	local pages = {}
	for _, name in ipairs({ "Shopping", "Selling", "Cancelling" }) do pages[name] = { frame = NewFrame(name .. "Page") } end
	local E = {
		color = "|cffffffff",
		FrameCheck = function(frame, method) return frame[method] and frame[method](frame) or frame.protected end,
		RunOutOfCombat = function(_, fn) world.queued[#world.queued + 1] = fn end,
	}
	local env = setmetatable({
		M = M, E = E, pages = pages,
		TAB_TITLES = { Shopping = "Shopping List", Selling = "Quick Sell", Cancelling = "Cancel Undercut" },
		InCombatLockdown = function() return world.combat end,
		GetTime = function() return world.now end,
		-- Since EldoUI 0.7.3000 HidePanel also refreshes the deal hint on
		-- Blizzard's sell page; not part of this test.
		Deals = { UpdateNativeSell = function() end },
	}, { __index = _G })
	for _, part in ipairs({ { SCREENS, "screens" }, { PAGES, "pages" } }) do
		local chunk = assert(loadstring(part[1], "@EldoUI/Modules/Auction.lua (" .. part[2] .. ")"))
		setfenv(chunk, env)
		chunk()
	end
	return M, ahf
end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
local passed, failed = 0, 0
local function Check(name, ok, detail)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL " .. name .. (detail and (": " .. tostring(detail)) or ""))
	end
end

local function Shown(ahf, names)
	local missing = {}
	for _, name in ipairs(names) do if not ahf[name]:IsShown() then missing[#missing + 1] = name end end
	return #missing == 0, table.concat(missing, ", ")
end
local function Hidden(ahf, names)
	local visible = {}
	for _, name in ipairs(names) do if ahf[name]:IsShown() then visible[#visible + 1] = name end end
	return #visible == 0, table.concat(visible, ", ")
end
local CHROME = { "TitleContainer", "TitleText", "CloseButton" }

do -- the case from the game: Sell, Quick Sell, Sell again
	local M, ahf = NewWorld()
	ahf:ClickTab("Buy")
	ahf:ClickTab("ItemSell")
	ahf:SetPostItem("ItemSell")
	Check("game: the item is in Blizzard's sell slot", ahf.sellItem == "ItemSell" and ahf:GetDisplayMode() == MODES.ItemSell)
	M:ShowPage("Selling")
	Check("game: Quick Sell puts Blizzard's sell screens away", Hidden(ahf, { "ItemSellFrame", "ItemSellList" }))
	Check("game: and the title", Hidden(ahf, CHROME))
	Check("game: EldoUI's panel is open", M.panel:IsShown() and M.current == "Selling")
	ahf:ClickTab("ItemSell")
	Check("game: Blizzard's Sell tab shows its screens again", Shown(ahf, { "ItemSellFrame", "ItemSellList" }))
	Check("game: and the title", Shown(ahf, CHROME))
	Check("game: EldoUI's panel is closed", not M.panel:IsShown() and M.current == nil)
	Check("game: nothing stays noted", next(M:NativeHidden()) == nil)
end

do -- Shopping List, then Blizzard's Buy tab (the same mode)
	local M, ahf = NewWorld()
	ahf:ClickTab("Buy")
	M:ShowPage("Shopping")
	Check("buy: Shopping puts the buy screens away", Hidden(ahf, MODES.Buy))
	ahf:ClickTab("Buy")
	Check("buy: Blizzard's Buy tab shows them again", Shown(ahf, MODES.Buy))
end

do -- a tab with a new mode: Blizzard sets the screens, EldoUI leaves them
	local M, ahf = NewWorld()
	ahf:ClickTab("Buy")
	M:ShowPage("Shopping")
	local browse = ahf.BrowseResultsFrame.shows
	ahf:ClickTab("Auctions")
	Check("new mode: Blizzard's own screen shows", Shown(ahf, MODES.Auctions))
	Check("new mode: the buy screens stay hidden", Hidden(ahf, MODES.Buy))
	Check("new mode: EldoUI shows none of them", ahf.BrowseResultsFrame.shows == browse)
	Check("new mode: the title comes back", Shown(ahf, CHROME))
	Check("new mode: EldoUI's panel is closed", not M.panel:IsShown())
	Check("new mode: nothing stays noted", next(M:NativeHidden()) == nil)
end

do -- a bag item clicked on Quick Sell (Blizzard was on its Sell screen)
	local M, ahf = NewWorld()
	ahf:ClickTab("ItemSell")
	M:ShowPage("Selling")
	ahf:SetPostItem("ItemSell") -- SetDisplayMode with the mode it shows
	Check("post: Blizzard's sell screens are back for a moment", Shown(ahf, MODES.ItemSell))
	-- EldoUI's SetPostItem hook then opens Quick Sell again (the same click).
	M:ShowPage("Selling")
	Check("post: Quick Sell put them away again", Hidden(ahf, MODES.ItemSell))
	ahf:ClickTab("ItemSell")
	Check("post: a later Sell tab still shows them", Shown(ahf, MODES.ItemSell))
end

do -- a bag item clicked on Quick Sell while Blizzard was on Buy
	local M, ahf = NewWorld()
	ahf:ClickTab("Buy")
	M:ShowPage("Selling")
	ahf:SetPostItem("ItemSell")
	Check("post from buy: Blizzard's sell screens show", Shown(ahf, MODES.ItemSell))
	Check("post from buy: the buy screens stay hidden", Hidden(ahf, MODES.Buy))
	M:ShowPage("Selling")
	ahf:ClickTab("Buy")
	Check("post from buy: Buy tab later shows the buy screens", Shown(ahf, MODES.Buy))
	Check("post from buy: and not the sell screens", Hidden(ahf, MODES.ItemSell))
end

do -- closing the window and switching pages
	local M, ahf = NewWorld()
	ahf:ClickTab("ItemSell")
	ahf:SetPostItem("ItemSell")
	M:ShowPage("Selling")
	M:ShowPage("Shopping")
	Check("pages: a second page notes nothing twice", Hidden(ahf, MODES.ItemSell))
	M:HidePanel()
	Check("close: every noted screen comes back", Shown(ahf, MODES.ItemSell))
	Check("close: and the title", Shown(ahf, CHROME))
end

do -- a protected screen during a fight
	local M, ahf = NewWorld()
	ahf:ClickTab("ItemSell")
	M:ShowPage("Selling")
	ahf.ItemSellFrame.protected = true
	world.combat = true
	ahf:ClickTab("ItemSell")
	Check("combat: the protected screen waits", not ahf.ItemSellFrame:IsShown() and #world.queued == 1)
	Check("combat: the others come back", ahf.ItemSellList:IsShown())
	world.combat = false
	world.queued[1]()
	Check("combat: after the fight it shows", ahf.ItemSellFrame:IsShown())
end

print(("Auction screens: %d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
