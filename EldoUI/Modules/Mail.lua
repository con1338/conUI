-- EldoUI Mail: the Blizzard mailbox (element "mail"), changed only
-- when the player ticks "Let EldoUI change this" under Blizzard UI:
--   skin     EldoUI look for the inbox, Send Mail and the open letter
--            (recorded, so switching it off puts the game's look back at
--            once, even with the mailbox open)
--   move     mover and scale (the shared economy window kit)
--   improve  * Open all: gold and items one mail at a time, skips
--              cash-on-delivery mail (and mail from Blizzard staff), stops
--              before your bags are full and prints the gold collected.
--            * Select letters with a tick box on each row (Shift-click
--              selects a range), then open them or return them to their
--              senders. Returning asks first.
--            * Address book (recent recipients, your alts, friends and
--              guild), the last recipient filled in, Alt-click a bag item
--              to attach it.
--            * Sent log: every letter you send (to, subject, items, gold,
--              cash on delivery), in a searchable list beside the window.
-- Every action is one click of the player; the open and return runs are a
-- chain of single mail actions, the way Blizzard's own "Open All" works.
--
-- How it follows the mailbox:
--   * The tick boxes, the toolbar and the row colors are redrawn when the
--     game updates the inbox (new letters, a page turned, a letter taken)
--     and once when the inbox tab opens. Several updates in one frame are
--     drawn once; a hidden inbox is not drawn at all.
--   * Switching the module or the Blizzard UI switches off puts the
--     mailbox back as the game had it, also while it is open: the skin,
--     the row colors, Blizzard's Open All button, the To: box and the
--     window's place.
-- Saved data:
--   profile.modules.Mail   the settings below, per profile
--   EldoUIDB.mailRecent    [realm or ruleset] = recent recipient names, newest first
--   EldoUIDB.mailSent      [realm or ruleset] = the sent log, newest first
-- Written from scratch for EldoUI; no code or media from other addons.
local _, E = ...
local L = E.L

local M = E:NewModule("Mail", {
	title = "Mail",
	category = "Items & Economy",
	desc = "Open all, select and return letters, address book and a log of the mail you send.",
	conflicts = { "Postal" },
	frames = { "EldoUI_MailToolbar", "EldoUI_MailAddressBook", "EldoUI_MailLog" },
	movers = { "EldoUI_MailWindow" },
	blizzard = { "mail" },
	savedKeys = { "profile.modules.Mail", "EldoUIDB.mailRecent", "EldoUIDB.mailSent" },
	optionsPage = "module:Mail",
	presets = { "Classic", "Compact", "Large", "Standard", "Wide" },
	reload = false,
	defaults = {
		openAll = true,
		delay = 0.15,
		keepFree = 1,
		skipGM = true,
		summary = true,
		multiSelect = true,
		addressBook = true,
		recentMax = 20,
		autofill = true,
		altClick = true,
		sentLog = true,
		sentMax = 200,
		-- Look (style presets set these)
		unreadAccent = true,
		toolbarHeight = 24,
		logRowHeight = 20,
		logFontSize = 12,
		logWidth = 380,
		logZebra = true,
	},
})

local floor, max, min = math.floor, math.max, math.min
local ROWS = INBOXITEMS_TO_DISPLAY or 7

local function Allowed(action)
	return M.active and E:BlizzardAllowed("mail", action)
end

-- The game's gamepad interface walks the window's buttons with its
-- controller cursor, so EldoUI's own buttons (the toolbar, Open all, the
-- tick boxes, the address book and the Sent log) step aside while it is
-- on and come back with the mouse interface. The look stays.
local function Additions()
	return not E:GamepadUIActive()
end

-- An addon with its own open all and send helpers: those parts stand
-- back while it runs (Data/Competitors.lua); the look, the unread
-- accent and the sent log stay.
local PART = { openAll = "openall", multiSelect = "send", addressBook = "send", autofill = "send", altClick = "send" }

local function Mine(setting)
	local part = PART[setting]
	return not (part and E:StandsBack(M, part))
end

local function Improve(setting)
	return Allowed("improve") and (setting == nil or (M.db[setting] and Mine(setting)))
end

local function HandledBy(setting)
	return function()
		local standing, _, title = E:StandsBack(M, PART[setting])
		return standing and L["Handled by %s. Type %s to choose."]:format(title, E:Highlight("/eui addons")) or nil
	end
end

function M:OnStandBack()
	self:UpdateInbox()
	self:UpdateSendMail()
end

local function Accent()
	local c = E.media.accentColor
	return c[1], c[2], c[3]
end

local function HistoryKey()
	local realm = E:ReadableRealmName()
	if realm or not (E.IsForeverClient and E:IsForeverClient()) then return realm end
	local ruleset = E:KnownRulesetName()
	if ruleset then return "Ruleset/" .. ruleset end
end

---------------------------------------------------------------------------
-- Small flat widgets for EldoUI's own frames here
---------------------------------------------------------------------------
-- The shared kit's button (E.UIKit.Button: hover, press and disabled
-- looks) and tooltip.
local function FlatButton(parent, label, width, height)
	local button = E.UIKit.Button(parent, label, { width = width, height = height or E.tokens.height.button })
	button.text:ClearAllPoints()
	button.text:SetPoint("LEFT", 4, 0)
	button.text:SetPoint("RIGHT", -4, 0)
	function button:SetLabel(text) self:SetText(text) end
	return button
end

local function Tip(frame, title, body)
	E.UIKit.Tooltip(frame, title, body)
end

---------------------------------------------------------------------------
-- Selection: mail indices ticked on the inbox rows
---------------------------------------------------------------------------
local selected = {}
local lastClicked

local function SelectedList()
	local list = {}
	for index in pairs(selected) do list[#list + 1] = index end
	table.sort(list, function(a, b) return a > b end) -- high to low: lower indices never shift
	return list
end

local function SelectedCount()
	local n = 0
	for _ in pairs(selected) do n = n + 1 end
	return n
end

local function ClearSelection()
	wipe(selected)
	lastClicked = nil
end

local function Header(index)
	local _, _, sender, subject, money, cod, daysLeft, itemCount, wasRead, wasReturned, _, canReply, isGM = GetInboxHeaderInfo(index)
	return { sender = sender, subject = subject, money = money or 0, cod = cod or 0, daysLeft = daysLeft,
		items = itemCount or 0, read = wasRead, returned = wasReturned, canReply = canReply, gm = isGM }
end

-- A letter goes back to a player who sent it, once. Auction house and
-- system mail would be deleted instead, so it is never "returned".
local function CanReturn(index)
	local h = Header(index)
	if not h.sender or h.gm or h.returned or not h.canReply then return false end
	if InboxItemCanDelete and InboxItemCanDelete(index) then return false end
	return true
end

---------------------------------------------------------------------------
-- Open run: gold and items, one action per tick
---------------------------------------------------------------------------
local run -- { kind = "open" | "return", queue = { index, ... }, gold, count }

local function FreeSlots()
	local free = 0
	for bag = 0, NUM_BAG_SLOTS do
		local slots, family = C_Container.GetContainerNumFreeSlots(bag)
		if family == 0 then free = free + slots end
	end
	return free
end

local function OpeningAll(on)
	if C_Mail and C_Mail.SetOpeningAll then pcall(C_Mail.SetOpeningAll, on) end
end

function M:StopRun(reason)
	if not run then return end
	local finished = run
	run = nil
	OpeningAll(false)
	if finished.kind == "open" and self.db.summary and finished.gold > 0 then
		self:Print(L["Collected %s."]:format(E:EconomyMoney(finished.gold)))
	elseif finished.kind == "return" and finished.count > 0 then
		self:Print((finished.count == 1 and L["Returned %d letter."] or L["Returned %d letters."]):format(finished.count))
	end
	if reason then self:Print(reason) end
	ClearSelection()
	self:UpdateInbox()
end

local function OpenStep()
	if not run or run.kind ~= "open" then return end
	if not InboxFrame or not InboxFrame:IsVisible() then return M:StopRun() end
	while run.queue[1] do
		local index = run.queue[1]
		if index > GetInboxNumItems() then
			table.remove(run.queue, 1)
		else
			local h = Header(index)
			local skip = h.cod > 0 or (h.gm and M.db.skipGM)
			if not skip and h.money > 0 then
				run.gold = run.gold + h.money
				TakeInboxMoney(index)
				return C_Timer.After(M.db.delay, OpenStep)
			end
			if not skip and h.items > 0 then
				if FreeSlots() <= M.db.keepFree then
					return M:StopRun(L["Stopped: bags are full."])
				end
				for attachment = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
					if GetInboxItemLink(index, attachment) then
						TakeInboxItem(index, attachment)
						return C_Timer.After(M.db.delay, OpenStep)
					end
				end
			end
			table.remove(run.queue, 1)
		end
	end
	M:StopRun()
end

local function ReturnStep()
	if not run or run.kind ~= "return" then return end
	if not InboxFrame or not InboxFrame:IsVisible() then return M:StopRun() end
	local index = table.remove(run.queue, 1)
	if not index then return M:StopRun() end
	if index <= GetInboxNumItems() and CanReturn(index) then
		ReturnInboxItem(index)
		run.count = run.count + 1
	end
	C_Timer.After(M.db.delay, ReturnStep)
end

-- indices: nil = every letter. Started by the player's click.
function M:Open(indices)
	if run then return self:StopRun() end
	local queue = indices
	if not queue then
		queue = {}
		for index = GetInboxNumItems(), 1, -1 do queue[#queue + 1] = index end
	end
	if #queue == 0 then return end
	run = { kind = "open", queue = queue, gold = 0, count = 0 }
	OpeningAll(true)
	self:UpdateInbox()
	OpenStep()
end

function M:Return(indices)
	if run then return self:StopRun() end
	local queue = {}
	for _, index in ipairs(indices) do
		if CanReturn(index) then queue[#queue + 1] = index end
	end
	if #queue == 0 then
		self:Print(L["None of the selected letters can be returned (auction house and system mail can't, and nothing goes back twice)."])
		return
	end
	run = { kind = "return", queue = queue, gold = 0, count = 0 }
	self:UpdateInbox()
	ReturnStep()
end


function M:AskReturn()
	local list = SelectedList()
	local returnable = {}
	for _, index in ipairs(list) do
		if CanReturn(index) then returnable[#returnable + 1] = index end
	end
	if #returnable == 0 then
		self:Print(L["None of the selected letters can be returned (auction house and system mail can't, and nothing goes back twice)."])
		return
	end
	self.pendingReturn = returnable
	-- The question on the shared dialog shell (E:ShowConfirm).
	E:ShowConfirm({ title = L["Return selected"],
		text = E:Plural(#returnable, "Return %d letter to its sender? Its gold and items go back with it.", "Return %d letters to their senders? Their gold and items go back with them."):format(#returnable),
		accept = YES, cancel = NO,
		onAccept = function()
			local pending = M.pendingReturn
			M.pendingReturn = nil
			if pending then M:Return(pending) end
		end,
		onCancel = function() M.pendingReturn = nil end })
end

---------------------------------------------------------------------------
-- Inbox: Open all, tick boxes and the toolbar under the window
---------------------------------------------------------------------------
function M:CreateInbox()
	if self.toolbar or not InboxFrame or not MailFrame then return end
	-- Open all takes the place of Blizzard's button, which is made
	-- invisible and click-through while it is on (Blizzard re-shows it on
	-- every inbox update, so it is never hidden).
	local open = FlatButton(InboxFrame, L["Open all"], 120, 24)
	open:SetFrameLevel(InboxFrame:GetFrameLevel() + 20)
	if OpenAllMail then
		open:SetPoint("CENTER", OpenAllMail, "CENTER")
	else
		open:SetPoint("BOTTOM", InboxFrame, "BOTTOM", 0, 102)
	end
	open:SetScript("OnClick", function() M:Open() end)
	Tip(open, L["Open all"], L["Takes gold and items from every letter, one after the other. Cash-on-delivery mail is skipped. Click again to stop."])
	open:Hide()
	self.openButton = open

	-- Toolbar on its own row under the window's Inbox and Send Mail tabs.
	local bar = CreateFrame("Frame", "EldoUI_MailToolbar", MailFrame)
	bar:SetHeight(self.db.toolbarHeight + 8)
	bar:SetClampedToScreen(true)
	E:SetPanelTemplate(bar)
	bar:Hide()
	local all = FlatButton(bar, L["Select all"], 80, self.db.toolbarHeight)
	all:SetPoint("LEFT", 4, 0)
	all:SetScript("OnClick", function()
		if SelectedCount() > 0 then
			ClearSelection()
		else
			for index = 1, GetInboxNumItems() do selected[index] = true end
		end
		M:UpdateInbox()
	end)
	Tip(all, L["Select all"], L["Checks every letter in the inbox, or clears the ticks."])
	local openSel = FlatButton(bar, L["Open"], 90, self.db.toolbarHeight)
	openSel:SetPoint("LEFT", all, "RIGHT", 4, 0)
	openSel:SetScript("OnClick", function() M:Open(SelectedList()) end)
	Tip(openSel, L["Open selected"], L["Takes gold and items from the checked letters."])
	local ret = FlatButton(bar, L["Return"], 90, self.db.toolbarHeight)
	ret:SetPoint("LEFT", openSel, "RIGHT", 4, 0)
	ret:SetScript("OnClick", function() M:AskReturn() end)
	Tip(ret, L["Return selected"], L["Sends the checked letters back to the players who sent them. Asks first."])
	local log = FlatButton(bar, L["Sent log"], 70, self.db.toolbarHeight)
	log:SetPoint("RIGHT", -4, 0)
	log:SetScript("OnClick", function() M:ToggleLog() end)
	Tip(log, L["Sent log"], L["Every letter you sent: recipient, subject, items and gold."])
	bar.all, bar.open, bar.ret, bar.log = all, openSel, ret, log
	self.toolbar = bar
	self:LayoutToolbar()
	-- The tabs change size with the font and the skin: the row follows.
	for i = 1, 2 do
		local tab = _G["MailFrameTab" .. i]
		if tab and tab.HookScript then
			tab:HookScript("OnSizeChanged", function() M:LayoutToolbar() end)
			tab:HookScript("OnShow", function() M:LayoutToolbar() end)
		end
	end

	-- One tick box per inbox row.
	self.checks = {}
	for i = 1, ROWS do
		local row = _G["MailItem" .. i]
		if row then
			local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
			check:SetSize(20, 20)
			check:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 2)
			check:SetFrameLevel(row:GetFrameLevel() + 5)
			if E.SkinCheckBox then E:SkinCheckBox(check, { inset = 3 }) end
			check:SetScript("OnClick", function(box)
				local index = box.index
				if not index then return end
				if IsShiftKeyDown() and lastClicked then
					local on = box:GetChecked() and true or nil
					for j = min(lastClicked, index), max(lastClicked, index) do selected[j] = on end
				else
					selected[index] = box:GetChecked() and true or nil
				end
				lastClicked = index
				M:UpdateInbox()
			end)
			Tip(check, L["Select"], L["Check letters to open or return them together. Shift-click checks a range."])
			check:Hide()
			self.checks[i] = check
		end
	end
	hooksecurefunc(InboxFrame, "Update", function() if M.active then M:UpdateInbox() end end)
end

-- The toolbar's row starts under the lowest of the game's mail tabs,
-- measured, so the tabs keep their strip and every button keeps its own
-- hit area. Without measurable tabs it sits one tab height down.
local TOOLBAR_GAP = 2
function M:LayoutToolbar()
	local bar = self.toolbar
	if not bar or not MailFrame then return end
	local frameBottom = MailFrame:GetBottom()
	local lowest
	for i = 1, 2 do
		local tab = _G["MailFrameTab" .. i]
		if tab and tab.IsShown and tab:IsShown() then
			local bottom = tab:GetBottom()
			if bottom and (not lowest or bottom < lowest) then lowest = bottom end
		end
	end
	local offset = -(E.tokens.height.tab + TOOLBAR_GAP * 3)
	if lowest and frameBottom then offset = min(lowest - frameBottom, 0) - TOOLBAR_GAP end
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", MailFrame, "BOTTOMLEFT", 0, offset)
	bar:SetPoint("TOPRIGHT", MailFrame, "BOTTOMRIGHT", 0, offset)
end

-- One redraw for every inbox update in the same frame: the game's own
-- inbox update draws at once, a mail event asks for one draw on the next
-- frame, which is skipped when the inbox was drawn since.
local requestedAt
function M:RequestInbox()
	if requestedAt then return end
	requestedAt = GetTime()
	C_Timer.After(0, function()
		local at = requestedAt
		requestedAt = nil
		if M.active and (M.drawnAt or -1) < at then M:UpdateInbox() end
	end)
end

function M:UpdateInbox()
	if not self.toolbar then return end
	local improve = Allowed("improve") and Additions()
	local inbox = InboxFrame and InboxFrame:IsShown()
	-- The rows are read only while the inbox can be seen.
	local rows = inbox and InboxFrame:IsVisible() and true or false
	if rows then self.drawnAt = GetTime() end
	-- Open all
	local useOpen = improve and self.db.openAll and Mine("openAll")
	self.openButton:SetShown(useOpen and inbox)
	self.openButton:SetLabel(run and run.kind == "open" and L["Stop"] or L["Open all"])
	if useOpen and inbox then self:OfferOpenAllHelp() end
	if OpenAllMail then
		OpenAllMail:SetAlpha(useOpen and 0 or 1)
		OpenAllMail:EnableMouse(not useOpen)
	end
	-- Tick boxes and toolbar
	local multi = improve and self.db.multiSelect and Mine("multiSelect")
	if multi and rows then
		local page = InboxFrame.pageNum or 1
		local count = GetInboxNumItems and GetInboxNumItems() or 0
		for i, check in ipairs(self.checks) do
			local index = (page - 1) * ROWS + i
			check.index = index
			check:SetShown(index <= count)
			check:SetChecked(selected[index] and true or false)
		end
	elseif not multi then
		for _, check in ipairs(self.checks) do check:Hide() end
	end
	local n = SelectedCount()
	local bar = self.toolbar
	-- Select all, Open and Return act on the inbox: the Send Mail tab
	-- shows only the Sent log button, the one way into the log.
	local inboxTools = (multi and inbox) and true or false
	local log = Improve("sentLog") and true or false
	local barShown = (improve and MailFrame:IsShown() and (inboxTools or log)) and true or false
	bar:SetShown(barShown)
	if barShown then self:LayoutToolbar() end
	bar.all:SetShown(inboxTools)
	bar.open:SetShown(inboxTools)
	bar.ret:SetShown(inboxTools)
	bar.log:SetShown(log)
	bar.all:SetLabel(n > 0 and L["Clear"] or L["Select all"])
	bar.open:SetLabel(run and run.kind == "open" and L["Stop"] or L["Open (%d)"]:format(n))
	bar.ret:SetLabel(run and run.kind == "return" and L["Stop"] or L["Return (%d)"]:format(n))
	bar.open:SetEnabled(n > 0 or (run and run.kind == "open") or false)
	bar.ret:SetEnabled(n > 0 or (run and run.kind == "return") or false)
	if run and run.kind == "return" then bar.ret:SetScript("OnClick", function() M:StopRun() end)
	else bar.ret:SetScript("OnClick", function() M:AskReturn() end) end
	if run and run.kind == "open" then bar.open:SetScript("OnClick", function() M:StopRun() end)
	else bar.open:SetScript("OnClick", function() M:Open(SelectedList()) end) end
	if rows then self:UpdateRowColors() end
end

---------------------------------------------------------------------------
-- Address book, autofill and Alt-click attach
-- Recent recipients saved by realm or confirmed ruleset, newest first.
---------------------------------------------------------------------------
E:RegisterStore("mailRecent", { owner = "Mail", key = "realm", shape = "recent recipient names per realm or ruleset, newest first" })

local function RecentHistory(key)
	if not key or type(EldoUIDB) ~= "table" then return {} end
	EldoUIDB.mailRecent = EldoUIDB.mailRecent or {}
	EldoUIDB.mailRecent[key] = EldoUIDB.mailRecent[key] or {}
	return EldoUIDB.mailRecent[key]
end

local function Recent() return RecentHistory(HistoryKey()) end
M.RecentRecipients = Recent

local function Remember(name)
	name = E.Plain(name)
	local key = HistoryKey()
	if not key or type(name) ~= "string" or name == "" then return end
	local list = RecentHistory(key)
	for i = #list, 1, -1 do
		if list[i]:lower() == name:lower() then table.remove(list, i) end
	end
	table.insert(list, 1, name)
	while #list > M.db.recentMax do table.remove(list) end
end

-- Your other characters on this realm and faction (the character store,
-- Core/CharacterStore.lua): { name, class, level }, by name.
local function Alts()
	local alts = {}
	local store = E.Characters
	if not store then return alts end
	for _, key in ipairs(store:Keys("faction")) do
		local record = store:Get(key)
		if key ~= E.charKey and record and type(record.name) == "string" then
			alts[#alts + 1] = { name = record.name, class = record.class, level = record.level }
		end
	end
	table.sort(alts, function(a, b) return a.name < b.name end)
	return alts
end

local function Friends()
	local list = {}
	for i = 1, C_FriendList.GetNumFriends() do
		local info = C_FriendList.GetFriendInfoByIndex(i)
		if info and info.name then list[#list + 1] = Ambiguate(info.name, "mail") end
	end
	table.sort(list)
	return list
end

local function Guild()
	local list = {}
	if not IsInGuild() then return list end
	for i = 1, GetNumGuildMembers() do
		local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
		if name and online then list[#list + 1] = Ambiguate(name, "mail") end
	end
	table.sort(list)
	return list
end

local function SetRecipient(name)
	SendMailNameEditBox:SetText(name)
	SendMailSubjectEditBox:SetFocus()
end

function M:CreateAddressBook()
	if self.addressBook or not SendMailNameEditBox then return end
	local button = CreateFrame("Button", "EldoUI_MailAddressBook", SendMailFrame)
	-- Sits inside the right end of the To: box.
	button:SetSize(20, 20)
	button:SetPoint("RIGHT", SendMailNameEditBox, "RIGHT", -2, 0)
	button:SetFrameLevel(SendMailNameEditBox:GetFrameLevel() + 5)
	-- The kit chevron: secondary at rest, the accent on hover.
	button.arrow = E.UIKit.Chevron(button, "down", 10)
	button.arrow:SetPoint("CENTER")
	button:HookScript("OnEnter", function(b) b.arrow:SetVertexColor(Accent()) end)
	button:HookScript("OnLeave", function(b) b.arrow:SetVertexColor(unpack(E.tokens.text.secondary)) end)
	Tip(button, L["Address book"], L["Recent recipients, your alts, friends and guild."])
	button:SetScript("OnClick", function(b)
		if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
		local scope = HistoryKey()
		self.addressBookScope = scope
		E.UIKit.ContextMenu(b, function(_, root)
			local function Section(title, names, historyScope)
				if #names == 0 then return end
				local sub = root:CreateButton(title)
				for _, name in ipairs(names) do
					sub:CreateButton(name, function()
						if not historyScope or HistoryKey() == historyScope then SetRecipient(name) end
					end)
				end
			end
			Section(L["Recent"], RecentHistory(scope), scope)
			-- Alts in class color with their level.
			local alts = Alts()
			if #alts > 0 then
				local sub = root:CreateButton(L["Alts"])
				for _, alt in ipairs(alts) do
					local color = E:ClassColorObject(alt.class)
					local label = (color and color:WrapTextInColorCode(alt.name) or alt.name) .. (" " .. E:TextHex("secondary") .. "%d|r"):format(alt.level or 0)
					sub:CreateButton(label, function() SetRecipient(alt.name) end)
				end
			end
			Section(L["Friends"], Friends())
			Section(L["Guild (online)"], Guild())
			if scope then
				root:CreateDivider()
				root:CreateButton(L["Clear recent"], function()
					if HistoryKey() ~= scope then return end
					E:ShowConfirm({ title = L["Clear recent"], text = L["Clear the current list of recent recipients?"],
						accept = L["Clear recent"], danger = true, onAccept = function()
							if HistoryKey() == scope then wipe(RecentHistory(scope)) end
						end })
				end)
			end
		end, { at = "owner" })
	end)
	button:Hide()
	self.addressBook = button
end

-- Alt-click a bag item while Send Mail is open to attach it.
-- Alt+Shift-click attaches every stack of that item, as far as slots allow.
local function FreeAttachment()
	for i = 1, ATTACHMENTS_MAX_SEND or 12 do
		if not GetSendMailItem(i) then return i end
	end
end

function M:AttachFromBag(bag, slot)
	if not Improve("altClick") or not SendMailFrame or not SendMailFrame:IsVisible() then return end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if not info or info.isLocked then return end
	local function Attach(b, s)
		local index = FreeAttachment()
		if not index then return false end
		C_Container.PickupContainerItem(b, s)
		ClickSendMailItemButton(index)
		return true
	end
	if not Attach(bag, slot) then return end
	if IsShiftKeyDown() then
		for b = 0, NUM_BAG_SLOTS do
			for s = 1, C_Container.GetContainerNumSlots(b) do
				local other = C_Container.GetContainerItemInfo(b, s)
				if other and other.itemID == info.itemID and not other.isLocked and not (b == bag and s == slot) then
					if not Attach(b, s) then return true end
				end
			end
		end
	end
	return true
end

function M:UpdateSendMail()
	if not self.addressBook then return end
	local book = Improve("addressBook") and Additions()
	self.addressBook:SetShown(book and true or false)
	-- The To: text stops before the arrow while the address book shows.
	local left, _, top, bottom = SendMailNameEditBox:GetTextInsets()
	SendMailNameEditBox:SetTextInsets(left or 0, book and 22 or 0, top or 0, bottom or 0)
end

---------------------------------------------------------------------------
-- Sent log: EldoUIDB.mailSent[realm] = { { t, to, s, items = { { id, n, link } }, m, cod } }
---------------------------------------------------------------------------
local pendingSend

E:RegisterStore("mailSent", { owner = "Mail", key = "realm", shape = "letters you sent per realm or ruleset, newest first, at most the \"Letters to keep\" setting" })

local function SentHistory(key)
	if not key or type(EldoUIDB) ~= "table" then return {} end
	EldoUIDB.mailSent = EldoUIDB.mailSent or {}
	EldoUIDB.mailSent[key] = EldoUIDB.mailSent[key] or {}
	return EldoUIDB.mailSent[key]
end

local function SentLog() return SentHistory(HistoryKey()) end
M.SentLog = SentLog

local function AskClearSentLog(scope, immediate, announce)
	if not scope or HistoryKey() ~= scope then return end
	local function Clear()
		if HistoryKey() ~= scope then return end
		wipe(SentHistory(scope))
		M:UpdateLog()
		if announce then M:Print(L["Sent log cleared."]) end
	end
	if immediate then return Clear() end
	local accept = Clear
	if announce then accept = function() E:RunConfigRow(Clear) end end
	E:ShowConfirm({ title = L["Clear log"], text = L["Clear the current sent log? This can't be undone."],
		accept = L["Clear log"], danger = true, onAccept = accept })
end

local function CaptureSend(recipient, subject)
	pendingSend = nil
	local scope = HistoryKey()
	if not scope or not M.active or not M.db.sentLog then return end
	local items = {}
	for i = 1, ATTACHMENTS_MAX_SEND or 12 do
		local name, itemID, texture, count = GetSendMailItem(i)
		if name then
			local link = GetSendMailItemLink and GetSendMailItemLink(i) or nil
			items[#items + 1] = { id = itemID, n = count or 1, link = link, tex = texture, name = name }
		end
	end
	pendingSend = {
		scope = scope,
		letter = {
			t = time(), to = recipient, s = subject,
			items = items,
			m = GetSendMailMoney and GetSendMailMoney() or 0,
			cod = GetSendMailCOD and GetSendMailCOD() or 0,
		},
	}
end

local function CommitSend()
	local pending = pendingSend
	pendingSend = nil
	if not pending or pending.scope ~= HistoryKey() then return end
	local log = SentHistory(pending.scope)
	table.insert(log, 1, pending.letter)
	while #log > (M.db.sentMax or 200) do table.remove(log) end
	if M.logFrame and M.logFrame:IsShown() then M:UpdateLog() end
end

local function MatchesLog(entry, filter)
	if filter == "" then return true end
	if E:FoldText(entry.to):find(filter, 1, true) or E:FoldText(entry.s):find(filter, 1, true) then return true end
	for _, item in ipairs(entry.items or {}) do
		if E:FoldText(item.name):find(filter, 1, true) then return true end
	end
	return false
end

function M:CreateLog()
	local frame = CreateFrame("Frame", "EldoUI_MailLog", MailFrame)
	frame:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, 0)
	frame:SetPoint("BOTTOMLEFT", MailFrame, "BOTTOMRIGHT", 4, 0)
	frame:SetWidth(self.db.logWidth)
	frame:EnableMouse(true)
	frame:EnableMouseWheel(true)
	E:SetPanelTemplate(frame)
	frame:Hide()
	frame.title = E.UIKit.Title(frame, E.tokens.size.dialogTitle)
	frame.title:SetPoint("TOPLEFT", 10, -6)
	frame.title:SetText(L["Sent mail"])
	frame.count = E.UIKit.Text(frame, E.tokens.size.small, "RIGHT", "secondary")
	frame.count:SetPoint("TOPRIGHT", -30, -10)
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButtonNoScripts")
	close:SetSize(20, 20)
	close:SetPoint("TOPRIGHT", -3, -3)
	close:SetScript("OnClick", function() frame:Hide() end)
	if E.SkinCloseButton then E:SkinCloseButton(close) end
	frame.line = frame:CreateTexture(nil, "ARTWORK")
	frame.line:SetPoint("TOPLEFT", E.pixel, -26)
	frame.line:SetPoint("TOPRIGHT", -E.pixel, -26)
	frame.line:SetHeight(E.pixel * 2)
	E:AccentTexture(frame.line)

	local search = E.UIKit.Input(frame, { height = 20, hint = L["Search recipient, subject or item"] })
	search:SetPoint("TOPLEFT", 8, -32)
	search:SetPoint("TOPRIGHT", -8, -32)
	search:HookScript("OnTextChanged", function()
		frame.offset = 0
		M:UpdateLog()
	end)
	frame.search = search

	frame.body = CreateFrame("Frame", nil, frame)
	frame.body:SetPoint("TOPLEFT", 6, -58)
	frame.body:SetPoint("BOTTOMRIGHT", -6, 34)
	frame.rows = {}
	frame.offset = 0
	frame:SetScript("OnMouseWheel", function(_, delta)
		frame.offset = max(0, frame.offset - delta)
		M:UpdateLog()
	end)
	frame.empty = E.UIKit.Text(frame.body, E.tokens.size.label, "CENTER", "secondary")
	frame.empty:SetPoint("CENTER")

	local clear = FlatButton(frame, L["Clear log"], 90, 20)
	frame.clear = clear
	clear:SetPoint("BOTTOMRIGHT", -8, 8)
	-- Asks first on the shared dialog shell; Shift-click clears at once.
	clear:SetScript("OnClick", function()
		local scope = frame.historyScope
		if HistoryKey() ~= scope then M:UpdateLog(); return end
		AskClearSentLog(scope, IsShiftKeyDown())
	end)
	frame.hint = E.UIKit.Text(frame, E.tokens.size.small, "LEFT", "secondary")
	frame.hint:SetPoint("BOTTOMLEFT", 10, 12)
	frame.hint:SetText(L["Click a row to write to that player again."])
	frame:SetScript("OnShow", function() M:LayoutLog(); M:UpdateLog() end)
	self.logFrame = frame
end

local function LogRow(frame, i)
	local row = frame.rows[i]
	if row then return row end
	row = CreateFrame("Button", nil, frame.body)
	row.stripe = row:CreateTexture(nil, "BACKGROUND")
	row.stripe:SetAllPoints()
	local hover = row:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	row.date = E.UIKit.Text(row, E.tokens.size.small, "LEFT", "secondary")
	row.date:SetPoint("LEFT", 4, 0)
	row.date:SetWidth(70)
	row.to = E:CreateText(row, E.tokens.size.label, "LEFT")
	row.to:SetPoint("LEFT", row.date, "RIGHT", 4, 0)
	row.to:SetWidth(90)
	row.what = E:CreateText(row, E.tokens.size.label, "LEFT")
	row.what:SetPoint("LEFT", row.to, "RIGHT", 4, 0)
	row.what:SetPoint("RIGHT", -4, 0)
	row:SetScript("OnClick", function(self)
		local entry = self.entry
		if not entry or not entry.to then return end
		if not self.historyScope or HistoryKey() ~= self.historyScope then M:UpdateLog(); return end
		if SendMailFrame and SendMailFrame:IsShown() then
			SetRecipient(entry.to)
		elseif MailFrameTab2 and MailFrameTab_OnClick then
			MailFrameTab_OnClick(nil, 2)
			SetRecipient(entry.to)
		end
	end)
	row:SetScript("OnEnter", function(self)
		local entry = self.entry
		if not entry or not self.historyScope or HistoryKey() ~= self.historyScope then return end
		local sr, sg, sb = unpack(E.tokens.text.secondary)
		E.UIKit.AnchorTooltip(self)
		GameTooltip:AddLine(L["To %s"]:format(entry.to or "?"))
		GameTooltip:AddLine(E:ShortDate(entry.t), sr, sg, sb)
		if entry.s and entry.s ~= "" then E.UIKit.TipTitle(GameTooltip, entry.s, true) end
		for _, item in ipairs(entry.items or {}) do
			local name = item.link or item.name or L["Item %s"]:format(tostring(item.id))
			E.UIKit.TipTitle(GameTooltip, ("%s%s"):format(item.tex and ("|T%s:0|t "):format(item.tex) or "", name) .. (item.n > 1 and (" x%d"):format(item.n) or ""))
		end
		if (entry.m or 0) > 0 then GameTooltip:AddDoubleLine(L["Gold sent"], E:EconomyMoney(entry.m), sr, sg, sb, 1, 1, 1) end
		local wr, wg, wb = unpack(E.tokens.text.warn)
		if (entry.cod or 0) > 0 then GameTooltip:AddDoubleLine(L["Cash on delivery"], E:EconomyMoney(entry.cod), wr, wg, wb, 1, 1, 1) end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	frame.rows[i] = row
	return row
end

function M:LayoutLog()
	local frame = self.logFrame
	if not frame then return end
	frame:SetWidth(self.db.logWidth)
	local height = frame.body:GetHeight()
	local rowHeight = self.db.logRowHeight
	local count = max(1, floor((height > 10 and height or 360) / rowHeight))
	for i = 1, max(count, #frame.rows) do
		local row = LogRow(frame, i)
		if i <= count then
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
			row:SetPoint("TOPRIGHT", 0, -(i - 1) * rowHeight)
			row:SetHeight(rowHeight)
			E:SetFont(row.to, self.db.logFontSize)
			E:SetFont(row.what, self.db.logFontSize)
			E:SetFont(row.date, max(9, self.db.logFontSize - 1))
		else
			row:Hide()
		end
	end
	frame.visible = count
end

function M:UpdateLog()
	local frame = self.logFrame
	if not frame or not frame:IsShown() then return end
	local scope = HistoryKey()
	if scope ~= frame.historyScope then
		frame.offset = 0
		-- A reused row keeps its hover state until the pointer leaves it.
		if GameTooltip:IsShown() then
			local owner = E.PlainCall(GameTooltip.GetOwner, GameTooltip)
			for _, row in ipairs(frame.rows) do
				if owner == row then
					GameTooltip:Hide()
					break
				end
			end
		end
	end
	frame.historyScope = scope
	frame.clear:SetEnabled(scope ~= nil)
	-- Folded (case, accents, Cyrillic) like the names it is compared with.
	local filter = E:FoldText(frame.search:GetText() or "")
	local items = {}
	for _, entry in ipairs(SentHistory(scope)) do
		if MatchesLog(entry, filter) then items[#items + 1] = entry end
	end
	frame.offset = max(0, min(frame.offset, max(0, #items - (frame.visible or 1))))
	frame.count:SetText(scope and L["%d letters"]:format(#items) or "")
	for i = 1, frame.visible or 0 do
		local row = frame.rows[i]
		local entry = items[frame.offset + i]
		row.entry, row.historyScope = entry, scope
		if entry then
			row.date:SetText(E:When(entry.t))
			row.to:SetText(entry.to or "?")
			local parts = {}
			for n, item in ipairs(entry.items or {}) do
				if n > 6 then
					parts[#parts + 1] = "+" .. (#entry.items - 6)
					break
				end
				parts[#parts + 1] = item.tex and ("|T%s:0|t%s"):format(item.tex, item.n > 1 and item.n or "") or (item.name or "?")
			end
			if (entry.m or 0) > 0 then parts[#parts + 1] = E:EconomyMoney(entry.m) end
			if (entry.cod or 0) > 0 then parts[#parts + 1] = E:TokenHex(E.tokens.text.warn) .. L["COD"] .. "|r " .. E:EconomyMoney(entry.cod) end
			local text = #parts > 0 and table.concat(parts, " ") or (entry.s or "")
			row.what:SetText(text)
			row.stripe:SetColorTexture(1, 1, 1, (self.db.logZebra and i % 2 == 0) and E.tokens.hover.row / 2 or 0)
			row:Show()
		else
			row:Hide()
		end
	end
	frame.empty:SetShown(#items == 0)
	frame.empty:SetText(not scope and L["Mail history is unavailable."]
		or (filter == "" and L["No mail sent yet."] or L["Nothing matches."]))
end

function M:ToggleLog()
	if not MailFrame or not Additions() then return end
	if not self.logFrame then self:CreateLog() end
	self.logFrame:SetShown(not self.logFrame:IsShown())
end

---------------------------------------------------------------------------
-- Skin: the mail windows in the EldoUI look ("Skin" switch). The skin is
-- recorded (E:SkinRecord), so switching it off puts back what the game
-- drew, without a reload.
---------------------------------------------------------------------------
local SKIN = "mail"

local function Skinned()
	return E:SkinRecordState(SKIN) == "on"
end

-- Row colors: the game sets them on every inbox update and the skin
-- paints over them right after. Each painted text keeps the game's color,
-- so switching the skin off gives it back.
local painted = setmetatable({}, { __mode = "k" })

local function SameColor(color, r, g, b)
	return color ~= nil and type(r) == "number" and math.abs(color[1] - r) < 0.002
		and math.abs(color[2] - g) < 0.002 and math.abs(color[3] - b) < 0.002
end

local function Paint(text, r, g, b)
	local entry = painted[text]
	local nr, ng, nb, na = text:GetTextColor()
	if not (entry and SameColor(entry.ours, nr, ng, nb)) then
		entry = { game = { nr, ng, nb, na } }
		painted[text] = entry
	end
	text:SetTextColor(r, g, b)
	entry.ours = { text:GetTextColor() }
end

local function UnpaintRows()
	for text, entry in pairs(painted) do
		if SameColor(entry.ours, text:GetTextColor()) then
			text:SetTextColor(entry.game[1], entry.game[2], entry.game[3], entry.game[4])
		end
		painted[text] = nil
	end
end

-- Read letters gray, unread ones white with the sender in the accent
-- color (or the game's gold). Blizzard sets these colors on each update;
-- this runs right after.
function M:UpdateRowColors()
	if not Skinned() then return end
	local page = InboxFrame and InboxFrame.pageNum or 1
	local count = GetInboxNumItems()
	for i = 1, ROWS do
		local index = (page - 1) * ROWS + i
		local sender, subject = _G["MailItem" .. i .. "Sender"], _G["MailItem" .. i .. "Subject"]
		if sender and subject and index <= count then
			local read = select(9, GetInboxHeaderInfo(index))
			if read then
				Paint(sender, unpack(E.media.text.secondary))
				Paint(subject, unpack(E.media.text.secondary))
			else
				Paint(sender, E:TokenColor(self.db.unreadAccent and "accent" or "gold"))
				Paint(subject, 1, 1, 1)
			end
		end
	end
end

local function SkinRoots()
	local roots = {}
	for _, frame in ipairs({ MailFrame, InboxFrame, SendMailFrame, OpenMailFrame }) do
		if frame then roots[#roots + 1] = frame end
	end
	return roots
end

-- The skin on or off as the switches say: built the first time, then
-- the record goes off and on.
function M:SkinMail()
	if not MailFrame then return end
	if not Allowed("skin") then return self:SkinOff() end
	local state = E:SkinRecordState(SKIN)
	if state == nil then
		E:SkinRecord(SKIN, SkinRoots(), function() M:BuildSkin() end)
	elseif state == "off" then
		E:SkinRecordOn(SKIN)
	end
end

function M:SkinOff()
	E:SkinRecordOff(SKIN)
	UnpaintRows()
end

function M:BuildSkin()
	E:SkinPanel(MailFrame)
	local tabs = {}
	for i = 1, 2 do tabs[#tabs + 1] = _G["MailFrameTab" .. i] end
	E:SkinTabs(tabs, { owner = MailFrame })

	-- Inbox: no parchment, flat rows and item buttons.
	E:EconomyStrip(InboxFrame)
	if InboxFrameBg then InboxFrameBg:SetAlpha(0) end
	for i = 1, ROWS do
		local row = _G["MailItem" .. i]
		if row then
			E:EconomyStrip(row)
			E:SkinRow(row, { divider = true, stripe = 0.02 })
			local button = _G["MailItem" .. i .. "Button"]
			if button then E:EconomySlot(button, _G["MailItem" .. i .. "ButtonIcon"] or button.Icon) end
			local sender, subject = _G["MailItem" .. i .. "Sender"], _G["MailItem" .. i .. "Subject"]
			if sender then E:SetNameTextFont(sender, E.tokens.size.body) end
			if subject then E:SetFont(subject, E.tokens.size.label) end
		end
	end
	if OpenAllMail then E:SkinButton(OpenAllMail) end
	for _, button in ipairs({ InboxFrame.PrevPageButton, InboxFrame.NextPageButton }) do
		if button then button:SetAlpha(0.85) end
	end

	-- Send Mail: no stationery, flat attachment slots, white body text.
	E:EconomyStrip(SendMailFrame)
	for _, region in ipairs({ SendStationeryBackgroundLeft, SendStationeryBackgroundRight,
		SendMailHorizontalBarLeft, SendMailHorizontalBarLeft2 }) do
		if region then region:SetAlpha(0) end
	end
	if SendMailScrollFrame then
		E:EconomyStrip(SendMailScrollFrame)
		local body = CreateFrame("Frame", nil, SendMailFrame)
		body:SetPoint("TOPLEFT", SendMailScrollFrame, "TOPLEFT", -4, 4)
		body:SetPoint("BOTTOMRIGHT", SendMailScrollFrame, "BOTTOMRIGHT", 4, -4)
		body:SetFrameLevel(max(SendMailScrollFrame:GetFrameLevel() - 1, 0))
		E:SetTemplate(body, true)
		if SendMailScrollFrame.ScrollBar then E:SkinScrollBar(SendMailScrollFrame.ScrollBar) end
	end
	if SendMailBodyEditBox then
		SendMailBodyEditBox:SetTextColor(1, 1, 1)
		if SendMailBodyEditBox.SetFont then E:SetFont(SendMailBodyEditBox, E.tokens.size.cardTitle) end
	end
	for _, box in ipairs({ SendMailNameEditBox, SendMailSubjectEditBox }) do E:SkinEditBox(box) end
	for _, button in ipairs({ SendMailMailButton, SendMailCancelButton }) do E:SkinButton(button) end
	if SendMailMoneyInset then E:SkinInset(SendMailMoneyInset) end
	if SendMailMoneyBg then E:EconomyStrip(SendMailMoneyBg) end
	for i = 1, ATTACHMENTS_MAX_SEND or 12 do
		local button = _G["SendMailAttachment" .. i]
		if button then E:EconomySlot(button, button.icon or button.Icon) end
	end

	-- Reading a letter: same treatment.
	if OpenMailFrame then
		E:SkinPanel(OpenMailFrame)
		for _, region in ipairs({ OpenStationeryBackgroundLeft, OpenStationeryBackgroundRight, OpenMailHorizontalBarLeft, OpenMailArithmeticLine }) do
			if region then region:SetAlpha(0) end
		end
		if OpenMailScrollFrame then
			E:EconomyStrip(OpenMailScrollFrame)
			if OpenMailScrollFrame.ScrollBar then E:SkinScrollBar(OpenMailScrollFrame.ScrollBar) end
		end
		-- OpenMailBodyText is a SimpleHTML: its SetTextColor takes the text type first.
		if OpenMailBodyText and OpenMailBodyText.SetTextColor then
			if OpenMailBodyText.GetObjectType and OpenMailBodyText:GetObjectType() == "SimpleHTML" then
				for _, textType in ipairs({ "P", "H1", "H2", "H3" }) do OpenMailBodyText:SetTextColor(textType, 1, 1, 1) end
			else
				OpenMailBodyText:SetTextColor(1, 1, 1)
			end
		end
		for _, button in ipairs({ OpenMailReplyButton, OpenMailDeleteButton, OpenMailCancelButton }) do E:SkinButton(button) end
		for i = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
			local button = _G["OpenMailAttachmentButton" .. i]
			if button then E:EconomySlot(button, button.icon or button.Icon) end
		end
		for _, button in ipairs({ OpenMailLetterButton, OpenMailMoneyButton }) do
			if button then E:EconomySlot(button, button.icon or button.Icon or _G[(button:GetName() or "") .. "IconTexture"]) end
		end
	end
end

---------------------------------------------------------------------------
-- Blizzard element "mail"
---------------------------------------------------------------------------
M.window = E:EconomyWindow({
	id = "mail",
	key = "mail",
	frame = function() return MailFrame end,
	mover = "EldoUI_MailWindow",
	title = "Mailbox",
	point = { "TOPLEFT", "UIParent", "TOPLEFT", 20, -150 },
	active = function() return M.active end,
})

function M:SetupHooks()
	if self.hooked or not MailFrame then return end
	self.hooked = true
	hooksecurefunc("SendMail", function(recipient, subject)
		if not M.active then return end
		if Improve() then Remember(recipient) end
		CaptureSend(recipient, subject)
	end)
	if SendMailFrame then
		SendMailFrame:HookScript("OnShow", function()
			if not M.active then return end
			M:UpdateInbox()
			M:UpdateSendMail()
			if Improve("autofill") and SendMailNameEditBox:GetText() == "" then
				local recipient = Recent()[1]
				if recipient then
					SendMailNameEditBox:SetText(recipient)
					SendMailNameEditBox:HighlightText()
				end
			end
		end)
	end
	-- The inbox tab opening (also when the mailbox opens) draws it once;
	-- the Send Mail tab only switches the toolbar to its Sent log button.
	InboxFrame:HookScript("OnShow", function() if M.active then M:RequestInbox() end end)
	-- Blizzard's own bag buttons: Alt-click attaches too.
	if ContainerFrameItemButtonMixin and ContainerFrameItemButtonMixin.OnModifiedClick then
		hooksecurefunc(ContainerFrameItemButtonMixin, "OnModifiedClick", function(button)
			if IsAltKeyDown() and button.GetBagID then M:AttachFromBag(button:GetBagID(), button:GetID()) end
		end)
	end
end

function M:ApplyBlizzard()
	if not self.active or not MailFrame then return end
	self:SkinMail()
	self.window:Apply()
	self:SetupHooks()
	self:CreateInbox()
	self:CreateAddressBook()
	self:UpdateInbox()
	self:UpdateSendMail()
	if self.logFrame then
		E:SetPanelTemplate(self.logFrame)
		if not (Improve("sentLog") and Additions()) then self.logFrame:Hide() end
		if self.logFrame:IsShown() then self:LayoutLog(); self:UpdateLog() end
	end
	if self.toolbar then E:SetPanelTemplate(self.toolbar) end
end

-- Everything back the way the game had it, also with the mailbox open:
-- the recorded skin and the row colors, Blizzard's Open All, the To: box,
-- EldoUI's own buttons hidden and the window on Blizzard's spot.
function M:RestoreBlizzard()
	self:StopRun()
	self:SkinOff()
	self.window:Restore()
	self:UpdateInbox()
	self:UpdateSendMail()
	if self.logFrame then self.logFrame:Hide() end
end

E:RegisterBlizzardHandler("mail", {
	owner = "Mail",
	apply = function() M:ApplyBlizzard() end,
	undo = function() M:RestoreBlizzard() end,
	-- The skin is recorded and comes off without a reload.
	install = { skin = true, improve = true },
	-- v0.5.0 skinned the mailbox and replaced Open all when the module was on.
	legacy = function() return M.db and M.db.enabled end,
})

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:OnEnable()
	self:ScheduleTrim() -- the limits a later change on the page compares with
	self:RegisterEvent("MAIL_CLOSED", function()
		self:StopRun()
		ClearSelection()
		if self.logFrame then self.logFrame:Hide() end
	end)
	self:RegisterEvent("MAIL_INBOX_UPDATE", function()
		-- Letters came or went: ticks on other letters would be wrong.
		local count = GetInboxNumItems()
		if not run and self.lastCount and self.lastCount ~= count then ClearSelection() end
		self.lastCount = count
		self:RequestInbox()
	end)
	self:RegisterEvent("MAIL_SEND_SUCCESS", CommitSend)
	self:RegisterEvent("GAME_RULES_CHANGED", function()
		local menu = E.UIKit.GetMenu()
		if self.addressBook and menu and menu.owner == self.addressBook and self.addressBookScope ~= HistoryKey() then
			E.UIKit.CloseMenu()
		end
		self:UpdateLog()
	end)
	-- Gamepad and mouse interface swap: EldoUI's buttons follow.
	self:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION", function()
		if not self.toolbar then return end
		self:UpdateInbox()
		self:UpdateSendMail()
		if self.logFrame and not Additions() then self.logFrame:Hide() end
	end)
	self:RegisterEvent("MAIL_FAILED", function()
		pendingSend = nil
		-- A run stops on the first error.
		if run then M:StopRun(L["Stopped: the game reported a mail error."]) end
	end)
	E:OnBlizzardAddOn("Blizzard_MailFrame", function() M:ApplyBlizzard() end)
end

function M:OnDisable()
	self:RestoreBlizzard()
end

-- Lowering "Letters to keep" or "Recent recipients to remember" on the
-- page drops the oldest entries, not only when the next letter goes out.
-- It runs a moment after the last change, so a slider dragged down and back
-- up again keeps everything; switching to a profile with lower limits
-- trims nothing.
function M:TrimLists()
	local scope = HistoryKey()
	if not scope or type(EldoUIDB) ~= "table" then return end
	local recent, log = RecentHistory(scope), SentHistory(scope)
	while #recent > (self.db.recentMax or 20) do table.remove(recent) end
	while #log > (self.db.sentMax or 200) do table.remove(log) end
	self:UpdateLog()
end

local trimToken, trimDb, trimRecent, trimSent = 0, nil, 0, 0
function M:ScheduleTrim()
	local recent, sent = self.db.recentMax or 20, self.db.sentMax or 200
	trimToken = trimToken + 1
	if self.db ~= trimDb then
		trimDb, trimRecent, trimSent = self.db, recent, sent
		return
	end
	if recent >= trimRecent and sent >= trimSent then
		trimRecent, trimSent = recent, sent
		return
	end
	local token, scope = trimToken, HistoryKey()
	C_Timer.After(1, function()
		if token ~= trimToken then return end
		if scope and HistoryKey() == scope then M:TrimLists() end
		trimRecent, trimSent = M.db.recentMax or 20, M.db.sentMax or 200
	end)
end

function M:OnProfileChanged()
	self:ScheduleTrim()
	if not self.active then return end
	if self.toolbar then
		self.toolbar:SetHeight(self.db.toolbarHeight + 8)
		for _, key in ipairs({ "all", "open", "ret", "log" }) do self.toolbar[key]:SetHeight(self.db.toolbarHeight) end
	end
	self:ApplyBlizzard()
end

E:AddCommand("sentmail", "show the log of mail you sent (at a mailbox)", function()
	if not M.active then return E:Print(E:ModuleOffHint("Mail")) end
	if not (MailFrame and MailFrame:IsShown()) then return M:Print(L["Open a mailbox first."]) end
	M:ToggleLog()
end, "Tools")

---------------------------------------------------------------------------
-- Options and styles
---------------------------------------------------------------------------
M.options = {
	{ type = "tab", label = "Inbox" },
	{ type = "description", label = "Everything here changes Blizzard's mailbox, so it needs \"Let EldoUI change this\" and \"Improve\" on for the Mailbox under Blizzard UI." },
	{ type = "execute", label = "Open Blizzard UI switches", desc = "Opens the Blizzard UI page, where you choose what EldoUI may change on the mailbox.",
		func = function() E:ToggleConfig("blizzard") end },
	{ type = "header", label = "Open all" },
	{ type = "toggle", key = "openAll", disabled = HandledBy("openAll"), label = "Open all button", desc = "EldoUI's Open all takes gold and items from every letter, skips cash-on-delivery mail and stops before your bags are full." },
	{ type = "range", key = "delay", label = "Delay between letters", unit = "s", desc = "Pause between two mail actions. Raise it if the server refuses some.", min = 0.05, max = 1, step = 0.05 },
	{ type = "range", key = "keepFree", label = "Keep bag slots free", desc = "Opening stops when only this many free bag slots are left.", min = 0, max = 10, step = 1 },
	{ type = "toggle", key = "skipGM", label = "Skip mail from Blizzard staff", desc = "Letters from Game Masters stay in the inbox, so you read them yourself." },
	{ type = "toggle", key = "summary", label = "Print the gold collected", desc = "One chat line with the gold an open run collected, and how many letters were returned." },
	{ type = "header", label = "Select letters" },
	{ type = "toggle", key = "multiSelect", disabled = HandledBy("multiSelect"), label = "Check boxes on letters", desc = "A check box on every letter and a bar under the mailbox: open the checked letters, or return them to their senders (asks first)." },

	{ type = "tab", label = "Send mail" },
	{ type = "toggle", key = "addressBook", disabled = HandledBy("addressBook"), label = "Address book button", desc = "Recent recipients, your alts, friends and online guild members." },
	{ type = "range", key = "recentMax", label = "Recent recipients to remember", desc = "How many recipients the address book keeps under Recent.", min = 5, max = 40, step = 5 },
	{ type = "toggle", key = "autofill", disabled = HandledBy("autofill"), label = "Fill in the last recipient", desc = "Send Mail starts with the last player you wrote to, selected so typing replaces it." },
	{ type = "toggle", key = "altClick", disabled = HandledBy("altClick"), label = "Alt-click a bag item to attach it", desc = "Alt+Shift-click attaches every stack of that item." },

	{ type = "tab", label = "Sent log" },
	{ type = "toggle", key = "sentLog", label = "Keep a log of sent mail", desc = "Remembers each letter in the current sent log, including its recipient, subject, items, gold, and cash on delivery. Open it beside the mailbox or with /eui sentmail." },
	{ type = "range", key = "sentMax", label = "Letters to keep", desc = "The oldest entries drop off after this many.", min = 50, max = 500, step = 50, dependsOn = "sentLog" },
	{ type = "execute", label = "Clear the sent log", desc = "Clears every letter in the current sent log.",
		func = function() AskClearSentLog(HistoryKey(), false, true) end },

	{ type = "tab", label = "Look" },
	{ less = true, type = "toggle", key = "unreadAccent", label = "Unread senders in the accent color", desc = "With the EldoUI skin on: unread letters show the sender in the accent color, read ones in gray." },
	{ type = "range", unit = "px", key = "toolbarHeight", label = "Toolbar height", desc = "Height of the buttons under the mailbox.", min = 18, max = 30, step = 1 },
	{ type = "range", unit = "px", key = "logWidth", label = "Sent log width", desc = "Width of the sent log beside the mailbox.", min = 300, max = 520, step = 10, dependsOn = "sentLog" },
	{ type = "range", unit = "px", key = "logRowHeight", label = "Sent log row height", desc = "Height of every row in the sent log.", min = 16, max = 30, step = 1, dependsOn = "sentLog" },
	{ type = "range", key = "logFontSize", label = "Sent log text size", desc = "Text size in the sent log.", min = 9, max = 16, step = 1, dependsOn = "sentLog" },
	{ type = "toggle", key = "logZebra", label = "Striped rows", desc = "A faint tint on every other row of the sent log.", dependsOn = "sentLog" },
	{ type = "execute", label = "Open Windows", testSafe = true,
		desc = "Blizzard's mailbox. Its size (mouse wheel on the title bar), dragging and resets are on the Move windows page with the other Blizzard windows; where it opens is its mover in move mode (/eui move).",
		func = function() E:ToggleConfig("windows") end },
}

E:RegisterStyles("Mail", {
	{ key = "Standard", title = "Standard", desc = "Accent senders, 24 px toolbar, roomy log.",
		settings = { unreadAccent = true, toolbarHeight = 24, logWidth = 380, logRowHeight = 20, logFontSize = 12, logZebra = true } },
	{ key = "Compact", title = "Compact", desc = "Small toolbar and a tight log.",
		settings = { unreadAccent = true, toolbarHeight = 20, logWidth = 330, logRowHeight = 17, logFontSize = 11, logZebra = true } },
	{ key = "Large", title = "Large", desc = "Big buttons and rows, larger window.",
		settings = { unreadAccent = true, toolbarHeight = 28, logWidth = 440, logRowHeight = 24, logFontSize = 14, logZebra = true } },
	{ key = "Classic", title = "Classic gold", desc = "Unread senders in the game's gold, no stripes.",
		settings = { unreadAccent = false, toolbarHeight = 24, logWidth = 380, logRowHeight = 20, logFontSize = 12, logZebra = false } },
	{ key = "Wide", title = "Wide log", desc = "A wide sent log for long subjects and many items.",
		settings = { unreadAccent = true, toolbarHeight = 24, logWidth = 500, logRowHeight = 20, logFontSize = 12, logZebra = true } },
})

---------------------------------------------------------------------------
-- Tour help: Open all, once the mailbox has stayed open a moment
---------------------------------------------------------------------------
local function OpenAllButton()
	local button = M.openButton
	if button and button:IsVisible() then return button end
end

E.Tour:Register("mail:openall", {
	form = "spot", word = "mail",
	offer = function(_, force)
		return E.Tour:Spot("mail:openall", {
			force = force, target = OpenAllButton,
			title = L["Open all"],
			text = L["Open all takes the gold and items from every letter, one letter at a time. It skips cash-on-delivery mail and stops before your bags are full. Click it again to stop."],
		})
	end,
	replay = function(def) def.offer(def, true) end,
})

local openAllHelpPending = false
function M:OfferOpenAllHelp()
	if openAllHelpPending or E.Tour:Seen("mail:openall") then return end
	openAllHelpPending = true
	C_Timer.After(1, function()
		openAllHelpPending = false
		if OpenAllButton() then E.Tour:Offer("mail:openall") end
	end)
end
