-- EldoUI Characters: the Alts window.
--
-- Everything about every character on the account, recorded by each
-- character itself (Core/CharacterStore.lua, E.Characters) and shown in one
-- window in the EldoUI look (E.UIKit): an Overview list with column sets,
-- search across all characters, professions and recipes, mail and
-- auctions, a level log, quests, grids, one character in detail, an agenda
-- and the guild. Plus owner lines in tooltips, recipe colors at vendors
-- and the auction house, an "Alts" datatext and /eui alts.
--
-- Files: Characters.lua (module, helpers, window), Overview.lua, Search.lua,
-- Professions.lua, LevelLog.lua, Quests.lua, Grids.lua, Character.lua,
-- Agenda.lua, Guild.lua, Options.lua. Each tab file adds itself with
-- M:AddTab(def); a tab that is not built has no tab.
--
-- Presentation only: every value is what the game showed that character.
-- The offline rested XP is an estimate from the game's published rate and
-- is marked with "~". Nothing is sent to other players unless the player
-- turns on the guild exchange and clicks.
local _, E = ...
local L = E.L
local Key = E.Key
local Kit = E.UIKit

local M = E:NewModule("Characters", {
	title = "Alts",
	aliases = { "Characters" }, -- the page's earlier title, for search and /eui
	category = "Items & Economy",
	desc = "An Alts window with every character you play: level, gold, gear, professions, mail, quests, reputation and lockouts, with search across all of them. Off while another alts addon is loaded.",
	conflicts = { "Altoholic", "DataStore" },
	frames = {},
	movers = { "EldoUI_Alts" },
	blizzard = {},
	savedKeys = { "profile.modules.Characters", "global.characters" },
	optionsPage = "module:Characters",
	presets = { "Banker", "Compact", "Crafter", "Full", "Leveling", "MaxLevel", "Overview" },
	uiAmount = "full",
	reload = false,
	defaults = {
		enabled = false,
		-- Overview
		style = "Overview",
		columns = { "name", "level", "rested", "gold", "played", "ilvl", "seen" },
		rowHeight = 18,
		chips = true,
		openTab = "overview",
		scope = "realm",          -- char / realm / faction / account
		group = "",               -- "" = every character, else a group name
		restedEstimate = true,
		-- Recording (Core/CharacterStore.lua reads these)
		requestPlayed = true,
		quietPlayed = true,
		playedOnLevelUp = false,
		skip = {},                -- view of E.global.characters.skip (M:SkipView)
		-- Groups and bank marks
		groups = {},              -- [group] = { [charKey] = true }
		bankMarks = {},           -- [charKey] = "prof:<name>" / "general"
		-- Mail and auctions
		warnMail = true,
		warnMailDays = 5,
		warnAuction = true,
		warnAuctionDays = 15,
		-- Recipes
		recipeColours = true,
		-- Quests
		questTooltip = true,
		-- Agenda
		weekStartsMonday = true,
		agendaWarn = true,
		agendaLead = 15,
		agendaWarnLockouts = true,
		agendaWarnCooldowns = true,
		agendaWarnCalendar = true,
		-- Guild
		guildShare = false,
		-- Tooltips
		countsWithBagAddons = false,
		reagentsExtra = "",
		-- Forget
		forgetSettings = false,
		forgetPick = "",
		forgetLevel = 10,
		-- Datatext
		datatext = "count",       -- count / gold
	},
})

M.tabs = {}

---------------------------------------------------------------------------
-- Helpers shared by the tab files
---------------------------------------------------------------------------
local function Store() return E.Characters end
M.Store = Store

-- Text colors by meaning (DESIGN.md §2, E.UIKit tokens): secondary gray,
-- good green, warning yellow, bad red. Read when drawing.
local function Paint(color, text)
	return Kit.Hex(color[1], color[2], color[3]) .. tostring(text) .. "|r"
end
function M.Grey(text) return Paint(Kit.SECONDARY, text) end
function M.Good(text) return Paint(Kit.GOOD, text) end
function M.Warn(text) return Paint(Kit.WARN, text) end
function M.Bad(text) return Paint(Kit.BAD, text) end
function M.Accent(text) return Kit.AccentHex() .. tostring(text) .. "|r" end
-- A guild name in the game's guild chat color.
function M.GuildText(text)
	local chatTypes = rawget(_G, "ChatTypeInfo")
	local info = type(chatTypes) == "table" and chatTypes.GUILD
	if type(info) == "table" and type(info.r) == "number" then return Paint({ info.r, info.g, info.b }, text) end
	return Paint(Kit.GOOD, text)
end

-- Gold in the Money style (Fonts and text page), like Bags and the Gold
-- datatext: gold and silver, or silver and copper under one gold. short =
-- whole gold only, abbreviated above 10k.
local function Coins(copper)
	return E:FormatMoney(copper)
end

function M.Money(copper, short)
	copper = math.max(math.floor(tonumber(copper) or 0), 0)
	local gold = math.floor(copper / 10000)
	if short then
		if gold >= 10000 then
			-- The gold mark of one gold (icon or letter), behind the abbreviated number.
			local one = Coins(10000)
			local icon = one:gsub("^[%d%s,%.]+", "")
			if icon == one then
				return E:TokenHex(E.tokens.money.gold) .. E:FormatNumber(gold) .. "g|r"
			end
			return E:FormatNumber(gold) .. (icon ~= "" and " " .. icon or "")
		end
		return Coins(gold * 10000)
	end
	if gold > 0 then return Coins(copper - copper % 100) end
	return Coins(copper)
end


-- "3d 4h", "5h 12m", "42m".
function M.Duration(seconds)
	if type(seconds) ~= "number" then return "" end
	seconds = math.max(math.floor(seconds), 0)
	local days, hours, minutes = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600), math.floor(seconds % 3600 / 60)
	if days > 0 then return L["%dd %dh"]:format(days, hours) end
	if hours > 0 then return L["%dh %dm"]:format(hours, minutes) end
	return L["%dm"]:format(minutes)
end

-- How long ago: "online", "now", "5h", "3d".
function M.Ago(record)
	if not record then return "" end
	if record == Store():Get(E.charKey) then return L["online"] end
	local at = record.loggedOut or record.seen or record.updated
	if not at then return "" end
	local seconds = Store().Now() - at
	if seconds < 3600 then return L["now"] end
	if seconds < 86400 then return L["%dh"]:format(seconds / 3600) end
	return L["%dd"]:format(seconds / 86400)
end

function M.ClassColor(class)
	local color = E:ClassColorObject(class)
	if color then return color.r, color.g, color.b end
	return 1, 1, 1
end

function M.ClassName(record, withRealm)
	if not record then return "?" end
	local name = record.name or "?"
	if withRealm and record.realmKey and record.realmKey ~= E:RealmKey() then name = name .. " - " .. record.realmKey end
	local r, g, b = M.ClassColor(record.class)
	return Kit.Hex(r, g, b) .. name .. "|r"
end

function M.ClassIcon(class, size)
	local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
	if not coords then return "" end
	return ("|TInterface\\TargetingFrame\\UI-Classes-Circles:%d:%d:0:0:256:256:%d:%d:%d:%d|t "):format(
		size or 14, size or 14, coords[1] * 256, coords[2] * 256, coords[3] * 256, coords[4] * 256)
end

-- Rested XP as a share of a level (0 to 150), and whether it is estimated.
function M.RestedPercent(record)
	local rested, xpMax, estimated = Store():RestedEstimate(record)
	if not M.db.restedEstimate then estimated = false rested = record.rested or 0 end
	if not xpMax or xpMax <= 0 then return nil end
	return math.floor(rested / xpMax * 100 + 0.5), estimated
end

-- The rested bar is at its cap (150 %, or what Well Rested lets it hold).
function M.FullyRested(record)
	local pct = M.RestedPercent(record)
	return pct ~= nil and pct >= math.floor(Store():RestCap(record) * 100 + 0.5)
end

-- Number of lockouts that have not reset yet.
function M.LockoutCount(record)
	local now, count = Store().Now(), 0
	for _, lock in pairs(type(record.lockouts) == "table" and record.lockouts or {}) do
		if (lock.resetAt or 0) > now then count = count + 1 end
	end
	return count
end

-- Mail: items waiting, and how many mails expire within `days`.
function M.MailInfo(record, days)
	local now, items, soon = Store().Now(), 0, 0
	for _, mail in ipairs(type(record.mailMeta) == "table" and record.mailMeta or {}) do
		items = items + (mail.items or 0)
		if mail.expires and mail.expires - now < (days or 5) * 86400 then soon = soon + 1 end
	end
	if not record.mailMeta then items = #(record.mail or {}) end
	return items, soon
end

-- When a character's data moves to its full-name key, it stays hidden if
-- you hid it, and keeps its groups and bank mark in every profile.
E:RegisterCharacterKeyMove(function(db, oldKey, newKey)
	local data = type(db.global) == "table" and db.global.characters
	E.MoveCharacterEntry(type(data) == "table" and data.skip, oldKey, newKey)
	for _, settings in ipairs(E.EachProfileModule(db, "Characters")) do
		E.MoveCharacterEntry(settings.bankMarks, oldKey, newKey)
		E.MoveCharacterEntry(settings.skip, oldKey, newKey)
		if type(settings.groups) == "table" then
			for _, members in pairs(settings.groups) do
				E.MoveCharacterEntry(members, oldKey, newKey)
				if type(members) == "table" then members[oldKey] = nil end
			end
		end
	end
end)

-- "Don't record this character" is kept account-wide per character
-- (E.Characters:SkipList), not in the profile. The options page edits
-- `skip.<charKey>` of this table, which reads and writes that list.
function M:SkipView()
	local db = self.db
	if not db then return nil end
	local skip = rawget(db, "skip")
	if type(skip) ~= "table" then
		skip = {}
		db.skip = skip
	end
	if getmetatable(skip) then return skip end
	local store = Store()
	if not store then return skip end
	store:SkipList()
	setmetatable(skip, {
		__index = function(_, key)
			local list = store:SkipList()
			return list and list[key] or nil
		end,
		__newindex = function(_, key, value) store:SetSkipped(key, value) end,
	})
	return skip
end

-- The keys the window lists: scope, group, and characters not skipped.
function M:Keys(scope, group)
	local keys = Store():Keys(scope or self.db.scope)
	group = group or self.db.group
	local members = group ~= "" and self.db.groups[group]
	if type(members) == "table" then
		local list = {}
		for _, key in ipairs(keys) do
			if members[key] then list[#list + 1] = key end
		end
		return list
	end
	return keys
end

local SCOPE_TITLE = { char = Key("This character"), realm = Key("This realm"), faction = Key("This faction"), account = Key("All characters") }
M.SCOPE_TITLE = SCOPE_TITLE

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------
-- def: { key, title, desc, order, create(content) -> frame, show, hide,
--   refresh, empty, hidden, count } (E.UIKit tab fields).
function M:AddTab(def)
	for index, tab in ipairs(self.tabs) do
		if tab.key == def.key then table.remove(self.tabs, index) break end
	end
	self.tabs[#self.tabs + 1] = def
	table.sort(self.tabs, function(a, b) return (a.order or 50) < (b.order or 50) end)
	if self.window then self.window:SetTabs(self.tabs) end
end

---------------------------------------------------------------------------
-- Window (mover EldoUI_Alts, 820 x 520)
---------------------------------------------------------------------------
local WIDTH, HEIGHT = 820, 520
local MOVER = "EldoUI_Alts"

local function WindowStore()
	local data = E:GetGlobal("characters")
	if type(data) ~= "table" then return nil end
	data.window = type(data.window) == "table" and data.window or {}
	return data.window
end

function M:Footer()
	local keys = self:Keys()
	local gold, played, levels = 0, 0, 0
	for _, key in ipairs(keys) do
		local record = Store():Get(key)
		gold = gold + (record.money or 0)
		played = played + (Store():Played(record) or 0)
		levels = levels + (record.level or 0)
	end
	local scope = L[SCOPE_TITLE[self.db.scope] or "All characters"]
	if self.db.group ~= "" then scope = scope .. " · " .. self.db.group end
	return E:Plural(#keys, "%s: %d character · %d levels · %s · played %s", "%s: %d characters · %d levels · %s · played %s"):format(scope, #keys, levels, M.Money(gold, true), M.Duration(played))
end

-- The scope and group menu in the top bar.
function M:ShowScopeMenu(anchor)
	E.UIKit.ContextMenu(anchor, function(_, root)
		root:CreateTitle(L["Show"])
		for _, scope in ipairs({ "char", "realm", "faction", "account" }) do
			root:CreateRadio(L[SCOPE_TITLE[scope]], function() return M.db.scope == scope end, function()
				M.db.scope = scope
				M:Refresh()
			end)
		end
		local names = {}
		for name in pairs(M.db.groups) do names[#names + 1] = name end
		table.sort(names)
		if #names > 0 then
			root:CreateDivider()
			root:CreateTitle(L["Group"])
			root:CreateRadio(L["Every character"], function() return M.db.group == "" end, function()
				M.db.group = ""
				M:Refresh()
			end)
			for _, name in ipairs(names) do
				root:CreateRadio(name, function() return M.db.group == name end, function()
					M.db.group = name
					M:Refresh()
				end)
			end
		end
	end, { at = "owner" })
end

function M:UpdateScopeButton()
	local button = self.window and self.window.frame and self.window.frame.scopeButton
	if not button then return end
	local label = L[SCOPE_TITLE[self.db.scope] or "All characters"]
	if self.db.group ~= "" then label = self.db.group end
	button:SetText(label)
	Kit.FitButton(button, 90)
end

function M:CreateWindow()
	if self.window then return self.window end
	local win = Kit.CreateTabbedWindow({
		name = "EldoUI_AltsWindow",
		options = { page = "module:Characters" },
		title = L["Alts"],
		width = WIDTH, height = HEIGHT,
		store = WindowStore,
		tabs = self.tabs,
		help = { text = L["Each character records itself when you log in on it. Right-click a character for groups, bank marks and Forget. Values with ~ are estimates for characters that are offline."] },
		footer = function() return M:Footer() end,
	})
	self.window = win
	-- The window sits on its mover; dragging the top bar moves the mover.
	function win.ApplyPosition(own)
		local frame = own.frame
		if not frame then return end
		if not own.mover then
			own.mover = E:CreateMover(frame, MOVER, L["Alts"], { "TOPLEFT", "UIParent", "TOPLEFT", 20, -120 }, { sample = false })
		end
		frame:SetScale(own:Scale())
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", own.mover, "TOPLEFT")
	end
	function win.SavePosition(own)
		local frame, mover = own.frame, own.mover
		if not (frame and mover) then return end
		local left, top = frame:GetLeft(), frame:GetTop()
		if not (left and top) then return end
		local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
		E:SaveMoverFromRect(mover, left * scale, top * scale - mover:GetHeight())
	end
	function win.ResetPosition(own)
		E.db.movers[MOVER] = nil
		local store = own:Store()
		store.scale = nil
		E:ApplyMover(MOVER)
		own:ResetSize()
		own:ApplyPosition()
	end
	-- Tabs that don't fit the bar move into a "More" tab with a menu.
	local layoutTabs = win.LayoutTabs
	function win.LayoutTabs(own)
		layoutTabs(own)
		M:FitTabs(own)
	end
	local frame = win:Build()
	frame.scopeButton = Kit.Button(frame.topBar, "", 110, 20, function(button) M:ShowScopeMenu(button) end,
		L["Characters shown"], L["Which characters the window lists: this character, this realm (on Forever: everyone on the same ruleset), this faction, or all. Groups you made show here too."])
	frame.scopeButton:SetPoint("RIGHT", frame.help or frame.close, "LEFT", -8, 0)
	frame.tabBar:SetPoint("RIGHT", frame.scopeButton, "LEFT", -8, 0)
	self:UpdateScopeButton()
	return win
end

-- Hide the tab buttons past the bar's width and list them under "More".
function M:FitTabs(win)
	local frame = win.frame
	if not (frame and frame.tabBar) then return end
	local more = frame.moreTab
	if not more then
		more = CreateFrame("Button", nil, frame.tabBar)
		more:SetText(L["More"])
		more:SetHeight(24)
		more:SetScript("OnClick", function(own) M:ShowMoreMenu(own) end)
		E:SkinTabs({ more }, { isSelected = function() return win.overflow and win.overflow[win.current] ~= nil end, size = 13 })
		Kit.Tooltip(more, L["More"], L["The tabs that don't fit the bar."])
		-- A kit chevron instead of a letter v (it opens a menu).
		more.arrow = E.UIKit.Chevron(more, "down", 9)
		more.arrow:SetPoint("RIGHT", -8, 0)
		frame.moreTab = more
	end
	local text = more:GetFontString()
	more:SetWidth(math.max(64, math.ceil((text and text:GetStringWidth() or 40) + 36)))
	-- The bar's width from its anchors; before the frame has a layout, an
	-- estimate from the parts around it.
	local left, right = frame.tabBar:GetLeft(), frame.scopeButton and frame.scopeButton:GetLeft()
	local room
	if left and right and right > left then
		room = right - left - 8
	else
		local title = frame.title and frame.title:GetStringWidth() or 40
		local scope = frame.scopeButton and frame.scopeButton:GetWidth() or 110
		room = WIDTH - 12 - title - 16 - 8 - scope - 8 - 3 * 24 - 12
	end
	local shown = {}
	for _, button in ipairs(win.tabButtons or {}) do
		if button:IsShown() then shown[#shown + 1] = button end
	end
	local total = 0
	for _, button in ipairs(shown) do total = total + button:GetWidth() + 2 end
	win.overflow = {}
	if total <= room then
		more:Hide()
		return
	end
	local x = 0
	local limit = room - more:GetWidth() - 2
	local last
	for _, button in ipairs(shown) do
		if x + button:GetWidth() <= limit then
			x = x + button:GetWidth() + 2
			last = button
		else
			button:Hide()
			win.overflow[button.tabKey] = #win.overflow + 1
			win.overflow[#win.overflow + 1] = button.tabKey
		end
	end
	more:ClearAllPoints()
	if last then more:SetPoint("LEFT", last, "RIGHT", 2, 0) else more:SetPoint("LEFT", frame.tabBar, "LEFT", 0, 0) end
	more:Show()
	E:UpdateTabs()
end

function M:ShowMoreMenu(anchor)
	local win = self.window
	if not (win and win.overflow) then return end
	E.UIKit.ContextMenu(anchor, function(_, root)
		for _, key in ipairs(win.overflow) do
			local tab = win:GetTab(key)
			if tab then
				root:CreateRadio(tab.title or key, function() return win.current == key end, function() M:Open(key) end)
			end
		end
	end, { at = "owner" })
end

function M:Open(tab, arg)
	if not self.active then
		E:Print(E:ModuleOffHint("Characters"))
		return false
	end
	local win = self:CreateWindow()
	local ok = win:Open(tab or (not win:IsOpen() and self.db.openTab) or nil, arg)
	self:UpdateScopeButton()
	return ok
end

-- What a window button did: a toast in the open Alts window (the warn bar
-- for a problem), a chat line when the window is closed.
function M:Say(text, warn)
	local win = self.window
	if win and win.frame and win:IsOpen() then
		Kit.Toast(win.frame, text, { warn = warn })
	else
		E:Print(text)
	end
end

function M:Toggle(tab, arg)
	if self.window and self.window:IsOpen() and (tab == nil or self.window:Current() == tab) then
		self.window:Close()
	else
		self:Open(tab, arg)
	end
end

-- Redraw the open tab, the footer and the scope label.
function M:Refresh(changed)
	self:UpdateScopeButton()
	if self.window then self.window:Refresh(changed) end
end

---------------------------------------------------------------------------
-- Forget: a confirm box naming the character, with a tick for its
-- EldoUI settings.
---------------------------------------------------------------------------
function M:ConfirmForget(key)
	local record = Store():Get(key)
	if not record then return end
	if key == E.charKey then
		E:Print(L["You can't forget the character you are logged in on."])
		return
	end
	local box = self.forgetBox
	if not box then
		-- The shared dialog shell (E.UIKit.CreateDialog), with the tick.
		box = E.UIKit.CreateDialog("EldoUI_AltsForget", { width = 380,
			check = { label = L["Also forget its EldoUI settings"],
				desc = L["Removes the character's profile choice, its own settings, installer state, profile rules and key binding backup too. Leave it off when you may play the character again."] } })
		box:SetButtons({
			{ L["Forget"], function(own)
				M.db.forgetSettings = own.tick:GetChecked() and true or false
				M:Forget(own.key, M.db.forgetSettings)
			end, kind = "danger" },
			{ CANCEL or L["Cancel"] },
		})
		box.tick = box.check
		box.ok, box.cancel = box.buttons[1], box.buttons[2]
		self.forgetBox = box
	end
	box.key = key
	box.title:SetText(L["Forget %s?"]:format(M.ClassName(record, true)))
	box.text:SetText(L["Its saved bags, bank, gold, mail, auctions, professions, quests, lockouts, level log, wishlist and journal leave EldoUI. Its journal is backed up first, and the Saved data page can put it back or remove it. Log in on it again to record it anew."])
	box.tick:SetChecked(self.db.forgetSettings)
	box:Show()
	box:Raise()
	box:Layout()
end

function M:Forget(key, settings)
	if Store():Forget(key, settings) then
		E:Print(L["Forgot %s."]:format(key))
		return true
	end
	return false
end

-- Forget every character below a level, with one confirm.
function M:ForgetBelow(level)
	local list = {}
	for _, key in ipairs(Store():Keys("account", true)) do
		local record = Store():Get(key)
		if key ~= E.charKey and (record.level or 0) < level then list[#list + 1] = key end
	end
	for _, key in ipairs(list) do Store():Forget(key, self.db.forgetSettings) end
	E:Print(E:Plural(#list, "Forgot %d character below level %d.", "Forgot %d characters below level %d."):format(#list, level))
	return #list
end

---------------------------------------------------------------------------
-- The row menu: groups, bank marks, forget. Tabs add their own entries.
---------------------------------------------------------------------------
M.menuEntries = {}

function M:AddMenuEntry(fn)
	self.menuEntries[#self.menuEntries + 1] = fn
end

function M:ShowCharacterMenu(anchor, key)
	local record = Store():Get(key)
	if not record then return end
	E.UIKit.ContextMenu(anchor, function(_, root)
		root:CreateTitle(M.ClassName(record, true))
		for _, fn in ipairs(M.menuEntries) do
			local ok, err = pcall(fn, root, key, record)
			if not ok then geterrorhandler()(err) end
		end
		root:CreateDivider()
		local forget = root:CreateButton(L["Forget character"], function() M:ConfirmForget(key) end)
		if key == E.charKey and forget.SetEnabled then forget:SetEnabled(false) end
	end)
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:OnInitialize()
	E:RegisterGlobal("characters", { window = {} })
	E:AddCommand("alts", "[on | off | search <text> | agenda | log | size]  the Alts window with all your characters", function(arg)
		M:Command(arg)
	end)
end

function M:Command(arg)
	arg = strtrim(arg or "")
	local word, rest = arg:match("^(%S+)%s*(.*)$")
	word = word and word:lower()
	if word == "on" or word == "off" then
		E:SetModuleFromCommand("Characters", word == "on")
		return
	end
	if not self.active then
		E:Print(E:ModuleOffHint("Characters"))
		return
	end
	if word == "search" or word == "find" then
		self:Open("search", rest)
	elseif word == "agenda" then
		self:Open("agenda")
	elseif word == "log" or word == "levels" then
		self:Open("levels")
	elseif word == "size" then
		local total = 0
		for _, key in ipairs(Store():Keys("account", true)) do
			local size = Store():Size(Store():Get(key))
			total = total + size
			E:Print(L["%s: %.1f KB"]:format(key, size / 1024))
		end
		E:Print(L["Saved character data: about %.1f KB."]:format(total / 1024))
	elseif not word or word == "toggle" then
		self:Toggle()
	else
		E:Print(L["Usage: /eui alts [on | off | search <text> | agenda | log | size]"])
	end
end

function M:OnEnable()
	local store = Store()
	self:SkipView()
	if store and store.OnCharactersEnabled then store:OnCharactersEnabled() end

	if store and store.RegisterCallback and not self.watching then
		self.watching = true
		store.RegisterCallback(self, "Updated", function(_, key, section)
			if M.active then M:Refresh({ key = key, section = section }) end
		end)
		store.RegisterCallback(self, "Forgotten", function(_, key)
			if M.active then M:Refresh({ key = key, forgotten = true }) end
		end)
	end
	if E.modules.Bags and E.modules.Bags.HookTooltips then E.modules.Bags:HookTooltips() end
	for _, tab in ipairs(self.tabs) do
		if tab.enable then
			local ok, err = pcall(tab.enable)
			if not ok then geterrorhandler()(err) end
		end
	end
end

function M:OnDisable()
	if self.window then self.window:Close() end
	for _, tab in ipairs(self.tabs) do
		if tab.disable then
			local ok, err = pcall(tab.disable)
			if not ok then geterrorhandler()(err) end
		end
	end
end

function M:OnProfileChanged()
	if not self.active then return end
	if self.window then
		for _, tab in ipairs(self.tabs) do
			if tab.frame and tab.restyle then
				local ok, err = pcall(tab.restyle, tab.frame)
				if not ok then geterrorhandler()(err) end
			end
		end
		self:Refresh({ settings = true })
	end
end
