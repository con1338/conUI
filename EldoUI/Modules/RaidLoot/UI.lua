-- EldoUI Raid Loot: the roll line, the Loot Guide mark and the
-- Raid Loot window (reserve lists and the GDKP ledger) on its mover
-- EldoUI_GDKPLedger.
--
-- Roll line: our own small box beside each roll (EldoUI's roll bars through
-- the hook on E:UpdateRollVerdict, Blizzard's GroupLootFrame1-4 through an
-- OnShow hook). Their frames and roll buttons are not changed; EldoUI never
-- rolls. The box sits on the side away from the Loot Guide's verdict box.
local _, E = ...
local L = E.L
local M = E.RaidLoot
local Kit = E.UIKit

local MOVER = "EldoUI_GDKPLedger"
local WIDTH, HEIGHT = 560, 420
local LINE_W, LINE_H = 220, 40

local function Hex(color)
	return E:TokenHex(color)
end

local function ItemName(itemID)
	local name = C_Item and C_Item.GetItemNameByID and M.Clean(C_Item.GetItemNameByID(itemID))
	return name or ("#" .. tostring(itemID))
end

local function ItemOfLink(link)
	link = M.Clean(link)
	return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil, link
end

---------------------------------------------------------------------------
-- Roll line
---------------------------------------------------------------------------
-- Roll frame -> our box, never a field on Blizzard's frame.
local lines = setmetatable({}, { __mode = "k" })

local function BuildLine(owner)
	local box = CreateFrame("Frame", nil, owner)
	box:SetSize(LINE_W, LINE_H)
	box:SetFrameLevel(owner:GetFrameLevel() + 5)
	box.bg = CreateFrame("Frame", nil, box)
	box.bg:SetAllPoints()
	box.bg:SetFrameLevel(math.max(box:GetFrameLevel() - 1, 0))
	E:SetTemplate(box.bg, true)
	box.sr = E:CreateText(box, E.tokens.size.small, "LEFT")
	E:UseNameFont(box.sr)
	box.sr:SetPoint("TOPLEFT", 6, -5)
	box.sr:SetPoint("TOPRIGHT", -6, -5)
	box.sr:SetWordWrap(false)
	box.tmb = E:CreateText(box, E.tokens.size.small, "LEFT")
	E:UseNameFont(box.tmb)
	box.tmb:SetPoint("TOPLEFT", box.sr, "BOTTOMLEFT", 0, -3)
	box.tmb:SetPoint("TOPRIGHT", box.sr, "BOTTOMRIGHT", -46, -3)
	box.tmb:SetWordWrap(false)
	box.post = Kit.Button(box, L["Post"], 44, 16, function(button)
		local own = button:GetParent()
		if own.itemID then M:PostItem(own.itemID, own.link) end
	end, L["Post reservations"], L["Sends one line with the reservations for this item to your raid or party."])
	box.post:SetPoint("BOTTOMRIGHT", -4, 4)
	box:EnableMouse(true)
	box:SetScript("OnEnter", function(self)
		if not self.itemID then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(L["Raid Loot"], unpack(E.tokens.text.body))
		local s = E.tokens.text.secondary
		for _, line in ipairs(M:Lines(self.itemID)) do
			GameTooltip:AddLine(line[1] .. ": " .. line[2], s[1], s[2], s[3], true)
		end
		GameTooltip:AddLine(L["Information only: you roll yourself."], s[1], s[2], s[3], true)
		GameTooltip:Show()
	end)
	box:SetScript("OnLeave", GameTooltip_Hide)
	return box
end

local function PlaceLine(box, owner)
	box:ClearAllPoints()
	local right = owner:GetRight()
	local scale = owner:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local width = UIParent:GetWidth()
	-- The Loot Guide's verdict box takes the left side when there is room.
	if right and width and right * scale + LINE_W + 12 < width then
		box:SetPoint("LEFT", owner, "RIGHT", 4, 0)
	else
		box:SetPoint("RIGHT", owner, "LEFT", -4, 0)
	end
end

function M:UpdateRollLine(owner, rollID)
	if not owner then return end
	local box = lines[owner]
	local on = self.active and self.db.rollLine and rollID ~= nil
	local itemID, link
	if on and GetLootRollItemLink then
		local ok, value = pcall(GetLootRollItemLink, rollID)
		if ok then itemID, link = ItemOfLink(value) end
	end
	local rows = itemID and self:Lines(itemID) or {}
	if #rows == 0 then
		if box then box:Hide() end
		return
	end
	box = box or BuildLine(owner)
	lines[owner] = box
	box.itemID, box.link = itemID, link
	local size = self.db.lineSize
	E:SetFont(box.sr, size)
	E:SetFont(box.tmb, size)
	local s = Hex(E.tokens.text.secondary)
	box.sr:SetText(rows[1] and (s .. rows[1][1] .. ":|r " .. rows[1][2]) or "")
	box.tmb:SetText(rows[2] and (s .. rows[2][1] .. ":|r " .. rows[2][2]) or "")
	box.bg:SetShown(self.db.rollBackdrop)
	box.post:SetShown(self.db.allowPosting and self:GroupChannel() ~= nil)
	box.tmb:SetPoint("RIGHT", box.post:IsShown() and -52 or -6, 0)
	PlaceLine(box, owner)
	box:Show()
	return box
end

function M:RefreshRollLines()
	for owner, box in pairs(lines) do
		if owner:IsShown() and owner.rollID then
			self:UpdateRollLine(owner, owner.rollID)
		else
			box:Hide()
		end
	end
end

local function BlizzardRoll(frame)
	M:UpdateRollLine(frame, frame.rollID)
end

---------------------------------------------------------------------------
-- Loot Guide mark: "SR" / "TMB" beside items you reserved
---------------------------------------------------------------------------
local function MarkCell(cell, data)
	if not (M.active and M.db.lootGuideMark and data and cell.right) then return end
	local itemID = tonumber(data.itemID)
	local which = itemID and M:ReservedByMe(itemID)
	if not which then return end
	local mark = Hex(E.media.accentColor) .. (which == "sr" and L["SR"] or L["TMB"]) .. "|r"
	local right = cell.right:GetText() or ""
	cell.right:SetText(right ~= "" and (mark .. "  " .. right) or mark)
end

---------------------------------------------------------------------------
-- Recent loot (for the ledger's item menu): items in loot windows and rolls
---------------------------------------------------------------------------
local recent = {}

local function Remember(link)
	local itemID, clean = ItemOfLink(link)
	if not itemID then return end
	for index, entry in ipairs(recent) do
		if entry.id == itemID then table.remove(recent, index) break end
	end
	table.insert(recent, 1, { id = itemID, link = clean })
	while #recent > 15 do table.remove(recent) end
end
M.recentLoot = recent

local function OnEvent(_, event, rollID)
	if not M.active then return end
	if event == "START_LOOT_ROLL" then
		if GetLootRollItemLink then
			local ok, link = pcall(GetLootRollItemLink, rollID)
			if ok then Remember(link) end
		end
	elseif event == "LOOT_OPENED" then
		if not (IsInGroup and IsInGroup()) then return end
		for slot = 1, tonumber(M.Clean(GetNumLootItems())) or 0 do
			local ok, link = pcall(GetLootSlotLink, slot)
			if ok then Remember(link) end
		end
	elseif event == "GROUP_ROSTER_UPDATE" then
		if M.db.onlyGroup then M:RefreshRollLines() end
	end
end

---------------------------------------------------------------------------
-- Hooks
---------------------------------------------------------------------------
-- A hook on another function can never be taken back, so each one is put
-- in once and only calls through its gate: the gates hold the handlers
-- while Raid Loot is on and are emptied when it turns off, so a hook left
-- behind does nothing at all.
local hooked = {}
local gates = {} -- hook name -> its handler while the module is on
M.hookGates = gates

local function Gated(name)
	return function(...)
		local handler = gates[name]
		if handler then return handler(...) end
	end
end

-- Shift-click puts an item link into the ledger's item box while it has focus.
local function TakeLink(link)
	local box = M.itemBox
	if box and box:HasFocus() and type(M.Clean(link)) == "string" and link:find("|Hitem:", 1, true) then
		box:SetText(link)
		box.itemID = tonumber(link:match("item:(%d+)"))
	end
end

local HANDLERS = {
	verdict = function(_, owner, rollID) M:UpdateRollLine(owner, rollID) end,
	blizzardRoll = BlizzardRoll,
	lootGuide = MarkCell,
	link = TakeLink,
}

function M:InstallHooks()
	for _, event in ipairs({ "START_LOOT_ROLL", "LOOT_OPENED", "GROUP_ROSTER_UPDATE" }) do
		E:RegisterEvent(event, OnEvent, "RaidLoot")
	end
	for name, handler in pairs(HANDLERS) do gates[name] = handler end
	if not hooked.verdict and type(E.UpdateRollVerdict) == "function" then
		hooked.verdict = true
		hooksecurefunc(E, "UpdateRollVerdict", Gated("verdict"))
	end
	for index = 1, 4 do -- GroupLootFrame1-4
		local frame = rawget(_G, "GroupLootFrame" .. index)
		if frame and not hooked[frame] then
			hooked[frame] = pcall(frame.HookScript, frame, "OnShow", Gated("blizzardRoll"))
		end
	end
	local LG = E.LootGuide
	if not hooked.lootGuide and LG and LG.PageKit and type(LG.PageKit.SetItem) == "function" then
		hooked.lootGuide = true
		hooksecurefunc(LG.PageKit, "SetItem", Gated("lootGuide"))
	end
	if not hooked.link then
		hooked.link = true
		if ChatFrameUtil and type(ChatFrameUtil.InsertLink) == "function" then hooksecurefunc(ChatFrameUtil, "InsertLink", Gated("link")) end
		if type(rawget(_G, "ChatEdit_InsertLink")) == "function" then hooksecurefunc("ChatEdit_InsertLink", Gated("link")) end
	end
end

-- Turning off: the events go and every hook gate closes.
function M:UnregisterEvents()
	for _, event in ipairs({ "START_LOOT_ROLL", "LOOT_OPENED", "GROUP_ROSTER_UPDATE" }) do
		E:UnregisterEvent(event, "RaidLoot")
	end
	wipe(gates)
end

---------------------------------------------------------------------------
-- Import
---------------------------------------------------------------------------
-- The result of a click: a toast in the open Raid Loot window (the warn
-- bar for a problem), a chat line when the window is closed.
function M:Notify(text, warn)
	local win = self.window
	if win and win.frame and win:IsOpen() then
		Kit.Toast(win.frame, text, { warn = warn })
	else
		E:Print(text)
	end
end

function M:ShowImport(which)
	local title = which == "sr" and L["Import soft reserves"] or L["Import TMB"]
	local help = which == "sr"
		and L["Paste the softres.it CSV export (or its JSON) and click Save. It replaces the soft reserves you imported before."]
		or L["Paste the That's My BiS CSV export (or its JSON) and click Save. Prio and wishlist rows are kept, received loot is left out."]
	E:ShowPasteBox(title, help, function(text)
		local count, info
		if which == "sr" then count, info = M:ImportSR(text) else count, info = M:ImportTMB(text) end
		if count then
			local message = E:Plural(count, "Imported %d entry.", "Imported %d entries."):format(count)
			if (info or 0) > 0 then message = message .. " " .. E:Plural(info, "%d line was skipped.", "%d lines were skipped."):format(info) end
			M:Notify(message)
		else
			M:Notify((L["Import failed: %s"]):format(info or "?"), true)
		end
		M.lastImport = { ok = count ~= nil, count = count, info = info }
	end)
end

---------------------------------------------------------------------------
-- Text question (cut, player)
---------------------------------------------------------------------------
function M:AskText(question, accept)
	return E:ShowConfirm({ key = "ELDOUI_RAIDLOOT_TEXT", title = L["Raid Loot"], text = question, accept = ACCEPT,
		edit = { text = "", maxLetters = 60 },
		onAccept = function(_, typed) if accept then accept(typed or "") end end })
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function WindowStore()
	local data = M:Data()
	data.window = type(data.window) == "table" and data.window or {}
	return data.window
end

local function ItemTooltip(widget)
	local item = widget.item
	if not (item and item.id) then return end
	GameTooltip:SetOwner(widget, "ANCHOR_RIGHT")
	if GameTooltip.SetItemByID then GameTooltip:SetItemByID(item.id) end
	GameTooltip:Show()
end

local function HoverRows(widget)
	widget:HookScript("OnEnter", ItemTooltip)
	widget:HookScript("OnLeave", GameTooltip_Hide)
end

-- Reserves tab
local function ReserveRows()
	local rows, seen = {}, {}
	local data = M:Data()
	for _, which in ipairs({ "sr", "tmb" }) do
		for itemID in pairs(data[which].items) do
			if not seen[itemID] then
				seen[itemID] = true
				local sr, srCount = M:Line("sr", itemID)
				local tmb, tmbCount = M:Line("tmb", itemID)
				if sr or tmb then
					rows[#rows + 1] = { id = itemID, name = ItemName(itemID), sr = sr or "", tmb = tmb or "",
						count = (srCount or 0) + (tmbCount or 0) }
				end
			end
		end
	end
	return rows
end

local function RowMenu(widget, row)
	E.UIKit.ContextMenu(widget, function(_, root)
		root:CreateTitle(row.name)
		local post = root:CreateButton(L["Post reservations"], function() M:PostItem(row.id) end)
		if not M.db.allowPosting then
			post:SetEnabled(false)
			post:SetTooltip(function(tooltip) GameTooltip_AddNormalLine(tooltip, L["Turn on \"Allow posting\" under Raid Loot first."]) end)
		end
		root:CreateButton(L["Add to the ledger"], function()
			M:OpenWindow("ledger")
			if M.itemBox then M.itemBox:SetText(ItemName(row.id)) M.itemBox.itemID = row.id end
		end)
	end)
end

local function BuildReserves(content)
	local frame = CreateFrame("Frame", nil, content)
	frame:SetAllPoints()
	frame.importSR = Kit.Button(frame, L["Import soft reserves"], 150, nil, function() M:ShowImport("sr") end,
		L["Import soft reserves"], L["Paste a softres.it CSV or JSON export."])
	frame.importSR:SetPoint("TOPLEFT", 4, -2)
	frame.importTMB = Kit.Button(frame, L["Import TMB"], 110, nil, function() M:ShowImport("tmb") end,
		L["Import TMB"], L["Paste a That's My BiS CSV or JSON export."])
	frame.importTMB:SetPoint("LEFT", frame.importSR, "RIGHT", 6, 0)
	frame.clear = Kit.Button(frame, L["Clear"], 70, nil, function(button)
		M:ConfirmClear(nil, function(text) Kit.Toast(button, text) end)
	end, L["Clear"], L["Removes the imported soft reserves and TMB lists. The ledger stays."])
	frame.clear:SetPoint("TOPRIGHT", -4, -2)
	frame.summary = Kit.Text(frame, 11, "LEFT", "secondary")
	frame.summary:SetPoint("TOPLEFT", frame.importSR, "BOTTOMLEFT", 0, -6)
	frame.summary:SetPoint("TOPRIGHT", -4, -(2 + frame.importSR:GetHeight() + 6)) -- under the button row
	frame.list = Kit.CreateTable(frame, {
		{ key = "name", title = L["Item"], width = 170, value = function(row) return row.name end },
		{ key = "sr", title = L["SR"], value = function(row) return row.sr end },
		{ key = "tmb", title = L["TMB"], width = 170, value = function(row) return row.tmb end },
	}, {
		sortKey = "name", rowHeight = function() return M.db.rowHeight end,
		onClick = function(row, _, widget) RowMenu(widget, row) end,
		createRow = function(row)
			HoverRows(row)
			E:UseNameFont(row.cells[2])
			E:UseNameFont(row.cells[3])
		end,
		empty = { L["No reserve lists"], L["Import a softres.it or That's My BiS export to see who wants which item."] },
	})
	frame.list:SetPoint("TOPLEFT", frame.summary, "BOTTOMLEFT", -4, -6)
	frame.list:SetPoint("BOTTOMRIGHT")
	return frame
end

local function DateText(t)
	return t and E:ShortDate(t) or nil
end

local function RefreshReserves(frame)
	M.window:UpdateFooter()
	local data = M:Data()
	local parts = {}
	if (data.sr.count or 0) > 0 then
		parts[#parts + 1] = E:Plural(data.sr.count, "%d soft reserve", "%d soft reserves"):format(data.sr.count) .. " (" .. DateText(data.sr.importedAt) .. ")"
	end
	if (data.tmb.count or 0) > 0 then
		parts[#parts + 1] = E:Plural(data.tmb.count, "%d TMB entry", "%d TMB entries"):format(data.tmb.count) .. " (" .. DateText(data.tmb.importedAt) .. ")"
	end
	frame.summary:SetText(#parts > 0 and table.concat(parts, "  ·  ") or L["Nothing imported yet."])
	frame.clear:SetEnabled(#parts > 0)
	frame.list:SetData(ReserveRows())
end

-- Ledger tab
local function Field(parent, width, numeric, hint)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetSize(width, 20)
	box:SetAutoFocus(false)
	box:SetTextInsets(6, 6, 0, 0)
	if numeric then box:SetNumeric(true) end
	box:SetScript("OnEscapePressed", box.ClearFocus)
	E:SkinEditBox(box, { left = 0, right = 0, top = 0, bottom = 0, size = 12 })
	local c = E.tokens.text.body
	box:SetTextColor(c[1], c[2], c[3])
	box.hint = Kit.Text(box, 11, "LEFT", "dim")
	box.hint:SetPoint("LEFT", 6, 0)
	box.hint:SetText(hint)
	box:HookScript("OnTextChanged", function(own) own.hint:SetShown((own:GetText() or "") == "") end)
	return box
end

local function SubmitSale(frame)
	local box = frame.item
	local item = box.itemID or box:GetText()
	local sale, why = M:AddSale(item, frame.buyer:GetText(), frame.price:GetText())
	if not sale then
		Kit.Toast(frame.add, why, { warn = true })
		return
	end
	box:SetText("")
	box.itemID = nil
	frame.price:SetText("")
	frame.buyer:SetText("")
	box:ClearFocus()
end

local function RecentMenu(owner, frame)
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(L["Recent loot"])
		if #recent == 0 then
			root:CreateButton(L["No loot seen yet in this session."], function() end):SetEnabled(false)
		end
		for _, entry in ipairs(recent) do
			root:CreateButton(entry.link or ItemName(entry.id), function()
				frame.item:SetText(entry.link or ItemName(entry.id))
				frame.item.itemID = entry.id
			end)
		end
	end, { at = "owner" })
end

local function LedgerMenu(owner)
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(L["Ledgers"])
		local current = M:Ledger()
		for i = #M:Ledgers(), 1, -1 do
			local ledger = M:Ledgers()[i]
			root:CreateRadio(ledger.name, function() return current and current.id == ledger.id end, function() M:SelectLedger(ledger.id) end)
		end
		root:CreateDivider()
		root:CreateButton(L["New ledger..."], function()
			M:AskText(L["Name of the new ledger:"], function(name) M:NewLedger(name) end)
		end)
		if current then
			root:CreateButton(L["Delete this ledger"], function()
				E:ShowConfirm({ key = "ELDOUI_RAIDLOOT_DELETE_LEDGER", title = L["Raid Loot"],
					text = L["Delete the ledger %s with all its sales and cuts? This can't be undone."]:format(E:Highlight(current.name or "")),
					accept = E:GameText(DELETE, L["Delete"]), danger = true,
					onAccept = function() M:DeleteLedger(current.id) end })
			end)
		end
	end, { at = "owner" })
end

local function CutMenu(owner)
	E.UIKit.ContextMenu(owner, function(_, root)
		local ledger = M:Ledger(true)
		root:CreateTitle(L["Organizer cut"])
		for _, percent in ipairs({ 0, 5, 10, 15, 20, 25 }) do
			root:CreateRadio(("%d%%"):format(percent), function() return ledger.cut == percent end, function() M:SetOrganizerCut(percent) end)
		end
		root:CreateDivider()
		root:CreateTitle(L["Other cuts (click to remove)"])
		for index, cut in ipairs(ledger.cuts) do
			root:CreateButton(("%s: %s"):format(cut.label, M.GoldText(cut.gold)), function() M:RemoveCut(index) end)
		end
		root:CreateButton(L["Add a cut..."], function()
			M:AskText(L["The cut and its gold, such as: Tank repairs 300"], function(text)
				local label, gold = strtrim(text or ""):match("^(.-)%s+(%d+)%s*g?$")
				if not M:AddCut(label, gold) then M:Notify(L["Write the name of the cut, then its gold."], true) end
			end)
		end)
	end, { at = "owner" })
end

local function PlayersMenu(owner)
	E.UIKit.ContextMenu(owner, function(_, root)
		local ledger = M:Ledger(true)
		root:CreateButton(L["Fill from your group"], function()
			local added = M:FillFromGroup()
			Kit.Toast(owner, E:Plural(added, "%d player added.", "%d players added."):format(added))
		end)
		root:CreateButton(L["Add a player..."], function()
			M:AskText(L["Name of the player:"], function(name) M:AddPlayer(name) end)
		end)
		if #ledger.players > 0 then
			root:CreateDivider()
			root:CreateTitle(L["Click to remove"])
			for _, name in ipairs(ledger.players) do
				root:CreateButton(name, function() M:RemovePlayer(name) end)
			end
		end
	end, { at = "owner" })
end

local function BuildLedger(content)
	local frame = CreateFrame("Frame", nil, content)
	frame:SetAllPoints()
	-- Top: ledger, cuts, players, export, post
	frame.pick = Kit.Button(frame, "", 130, nil, function(button) LedgerMenu(button) end, L["Ledger"], L["Pick a ledger, start a new one or delete one."])
	frame.pick:SetPoint("TOPLEFT", 4, -2)
	frame.cuts = Kit.Button(frame, L["Cuts"], 70, nil, function(button) CutMenu(button) end, L["Cuts"], L["The organizer's percent and other cuts (a fixed gold amount each)."])
	frame.cuts:SetPoint("LEFT", frame.pick, "RIGHT", 6, 0)
	frame.players = Kit.Button(frame, L["Players"], 80, nil, function(button) PlayersMenu(button) end, L["Players"], L["Who shares the pot. Buyers join by themselves."])
	frame.players:SetPoint("LEFT", frame.cuts, "RIGHT", 6, 0)
	frame.post = Kit.Button(frame, L["Post"], 60, nil, function(button)
		if not M:PostTotals() then Kit.Toast(button, L["Nothing was posted."], { warn = true }) end
	end, L["Post totals"], L["Sends one line with the pot and each player's share to your raid or party (needs \"Allow posting\")."])
	frame.post:SetPoint("TOPRIGHT", -4, -2)
	frame.export = Kit.Button(frame, L["Export"], 70, nil, function()
		E:ShowCopyBox(L["GDKP ledger"], L["Everything is selected. Press Ctrl+C and paste it where you keep your records."], M:ExportText())
	end, L["Export"], L["The ledger as text: sales, pot, cuts and payouts."])
	frame.export:SetPoint("RIGHT", frame.post, "LEFT", -6, 0)
	-- Add a sale
	frame.form = CreateFrame("Frame", nil, frame)
	frame.form:SetPoint("TOPLEFT", frame.pick, "BOTTOMLEFT", 0, -8)
	frame.form:SetPoint("TOPRIGHT", -4, -(2 + frame.pick:GetHeight() + 8)) -- under the button row
	frame.form:SetHeight(22)
	frame.item = Field(frame.form, 170, false, L["Item: drop, shift-click or type"])
	frame.item:SetPoint("LEFT", 2, 0)
	frame.item:SetScript("OnReceiveDrag", function(box)
		local kind, itemID, link = GetCursorInfo()
		if kind == "item" and type(itemID) == "number" then
			box:SetText(link or ItemName(itemID))
			box.itemID = itemID
			ClearCursor()
		end
	end)
	frame.item:HookScript("OnTextChanged", function(box, typed) if typed then box.itemID = nil end end)
	M.itemBox = frame.item
	frame.recent = Kit.Button(frame.form, L["Recent"], 60, 20, function(button) RecentMenu(button, frame) end, L["Recent loot"], L["Items from loot windows and rolls in your group this session."])
	frame.recent:SetPoint("LEFT", frame.item, "RIGHT", 2, 0)
	frame.buyer = Field(frame.form, 100, false, L["Buyer"])
	frame.buyer:SetPoint("LEFT", frame.recent, "RIGHT", 6, 0)
	frame.price = Field(frame.form, 60, true, L["Gold"])
	frame.price:SetPoint("LEFT", frame.buyer, "RIGHT", 6, 0)
	frame.add = Kit.Button(frame.form, L["Add sale"], 80, 20, function() SubmitSale(frame) end, L["Add sale"], L["Adds the item, the buyer and the price to the ledger."])
	frame.add:SetPoint("LEFT", frame.price, "RIGHT", 6, 0)
	for _, box in ipairs({ frame.item, frame.buyer, frame.price }) do
		box:SetScript("OnEnterPressed", function() SubmitSale(frame) end)
	end
	-- Sales (left) and players (right)
	frame.sales = Kit.CreateTable(frame, {
		{ key = "item", title = L["Item"], value = function(row) return row.text end },
		{ key = "buyer", title = L["Buyer"], width = 80, value = function(row) return row.buyer end },
		{ key = "gold", title = L["Gold"], width = 60, align = "RIGHT", value = function(row) return row.gold end },
	}, {
		sortKey = "item", rowHeight = function() return M.db.rowHeight end,
		onClick = function(row, _, widget)
			E.UIKit.ContextMenu(widget, function(_, root)
				root:CreateButton(L["Remove this sale"], function() M:RemoveSale(row.saleID) end)
			end)
		end,
		createRow = function(row)
			HoverRows(row)
			E:UseNameFont(row.cells[2])
		end,
		empty = { L["No sales yet"], L["Add each sale above: the item, who bought it and for how much gold."] },
	})
	frame.sales:SetPoint("TOPLEFT", frame.form, "BOTTOMLEFT", -4, -8)
	frame.sales:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -4, 44)
	frame.payout = Kit.CreateTable(frame, {
		{ key = "name", title = L["Player"], value = function(row) return row.name end },
		{ key = "spent", title = L["Spent"], width = 60, align = "RIGHT", value = function(row) return row.spent end },
		{ key = "net", title = L["Payout"], width = 70, align = "RIGHT", value = function(row) return row.net end,
			text = function(row) return M.GoldText(row.net) end,
			color = function(row) return unpack(row.net < 0 and E.tokens.text.warn or E.tokens.text.body) end },
	}, {
		sortKey = "name", rowHeight = function() return M.db.rowHeight end,
		createRow = function(row) E:UseNameFont(row.cells[1]) end,
		empty = { L["No players"], L["Use Players > Fill from your group, or add players by name."] },
	})
	frame.payout:SetPoint("TOPLEFT", frame.form, "BOTTOM", 4, -8)
	frame.payout:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 44)
	frame.totals = Kit.Text(frame, 12, "LEFT")
	frame.totals:SetPoint("BOTTOMLEFT", 4, 22)
	frame.totals:SetPoint("BOTTOMRIGHT", -4, 22)
	frame.note = Kit.Text(frame, 10, "LEFT", "dim")
	frame.note:SetPoint("BOTTOMLEFT", 4, 4)
	frame.note:SetPoint("BOTTOMRIGHT", -4, 4)
	frame.note:SetText(L["Payout is each player's share minus what they bought: negative means they pay in. You trade the gold yourself."])
	return frame
end

local function RefreshLedger(frame)
	M.window:UpdateFooter()
	local ledger = M:Ledger()
	frame.pick:SetText(ledger and ledger.name or L["New ledger"])
	Kit.FitButton(frame.pick, 100)
	local sales = {}
	for _, sale in ipairs(ledger and ledger.sales or {}) do
		sales[#sales + 1] = { saleID = sale.id, id = sale.item, text = M:SaleItemText(sale), buyer = sale.buyer, gold = sale.gold, t = sale.t }
	end
	frame.sales:SetData(sales)
	local totals = M:Totals(ledger)
	frame.payout:SetData(totals.players)
	local b, s = Hex(E.tokens.text.body), Hex(E.tokens.text.secondary)
	local text = ("%s%s|r %s%s|r   %s%s|r %s%s|r   %s%s|r %s%s|r"):format(
		s, L["Pot"], b, M.GoldText(totals.pot),
		s, (L["Cuts (%d%%)"]):format(ledger and ledger.cut or 0), b, M.GoldText(totals.organizer + totals.other),
		s, L["Each"], b, M.GoldText(totals.per))
	if totals.rest > 0 then text = text .. ("   %s%s|r %s%s|r"):format(s, L["Left over"], b, M.GoldText(totals.rest)) end
	frame.totals:SetText(text)
	frame.post:SetEnabled(M.db.allowPosting and ledger ~= nil)
	frame.export:SetEnabled(ledger ~= nil)
end

---------------------------------------------------------------------------
-- Attendance
---------------------------------------------------------------------------
local RefreshAttendance
local function NightText(night)
	return date("%Y-%m-%d", night.at) .. (night.instance and "  ·  " .. night.instance or "")
end

local function AttendanceNights(owner, frame)
	Kit.ContextMenu(owner, function(_, root)
		local nights = M:AttendanceHistory().nights
		for index = #nights, 1, -1 do
			local night = nights[index]
			root:CreateRadio(NightText(night), function() return frame.night == night end, function()
				frame.night, frame.snapshot = night, nil
				RefreshAttendance(frame)
			end)
		end
	end, { at = "owner" })
end

local function AttendanceBench(owner, frame)
	local night = frame.night
	if not night or night ~= M:CurrentAttendanceNight() then return end
	Kit.ContextMenu(owner, function(_, root)
		root:CreateButton(L["Add to bench"], function()
			M:AskText(L["Enter the full name of the player on the bench."], function(name)
				if not M:SetAttendanceBench(night, name, true) then M:Notify(L["That player could not be added to the bench."], true) end
			end)
		end)
		local names = {}
		for _, name in pairs(night.bench) do names[#names + 1] = name end
		table.sort(names)
		if #names > 0 then
			root:CreateDivider()
			root:CreateTitle(L["Click to remove"])
			for _, name in ipairs(names) do
				root:CreateButton(name, function() M:SetAttendanceBench(night, name, false) end)
			end
		end
	end, { at = "owner" })
end

local function AttendanceSnapshots(owner, frame)
	if not frame.night then return end
	Kit.ContextMenu(owner, function(_, root)
		root:CreateRadio(L["Whole night"], function() return frame.snapshot == nil end, function()
			frame.snapshot = nil
			RefreshAttendance(frame)
		end)
		for _, snapshot in ipairs(frame.night.snapshots) do
			local row = snapshot
			local label = date("%H:%M", row.at) .. "  ·  " .. M:AttendanceSampleName(row)
			root:CreateRadio(label, function() return frame.snapshot == row end, function()
				frame.snapshot = row
				RefreshAttendance(frame)
			end)
		end
	end, { at = "owner" })
end

local function AttendanceActions(owner, frame)
	Kit.ContextMenu(owner, function(_, root)
		root:CreateCheckbox(L["Record raid attendance"], function() return M.db.recordAttendance end, function()
			M.db.recordAttendance = not M.db.recordAttendance
			M:SyncAttendance()
			RefreshAttendance(frame)
			E:RefreshConfig()
		end)
		local night = frame.night
		if night then
			root:CreateDivider()
			local function Copy(csv)
				E:ShowCopyBox(L["Raid attendance"], L["Everything is selected. Press Ctrl+C and paste it where you keep your records."], M:ExportAttendance(night, csv))
			end
			root:CreateButton(L["Copy attendance as text"], function() Copy(false) end)
			root:CreateButton(L["Copy attendance as CSV"], function() Copy(true) end)
			root:CreateButton(L["Delete this raid night"], function()
				E:ShowConfirm({ key = "ELDOUI_DELETE_RAID_NIGHT", title = L["Raid attendance"],
					text = L["Delete this raid night and its snapshots?"], accept = L["Delete"], danger = true,
					onAccept = function() M:DeleteAttendanceNight(night) end })
			end)
		end
		local keep = root:CreateButton(L["Nights to keep"])
		for _, amount in ipairs({ 5, 10, 20, 40, 60 }) do
			keep:CreateRadio(tostring(amount), function() return M:AttendanceHistory().keep == amount end, function()
				if #M:AttendanceHistory().nights <= amount then M:SetAttendanceKeep(amount); return end
				E:ShowConfirm({ key = "ELDOUI_TRIM_RAID_NIGHTS", title = L["Raid attendance"],
					text = L["Remove the oldest nights to keep %d?"]:format(amount), accept = ACCEPT, danger = true,
					onAccept = function() M:SetAttendanceKeep(amount) end })
			end)
		end
	end, { at = "owner" })
end

local function AttendanceTip(widget)
	local data = widget.attendance
	local info = data and data.latest
	if not info then return end
	GameTooltip:SetOwner(widget, "ANCHOR_RIGHT")
	GameTooltip:SetText(data.name)
	if info.class then Kit.TipText(GameTooltip, info.class) end
	if info.group then Kit.TipText(GameTooltip, L["Group %d"]:format(info.group)) end
	if info.zone then Kit.TipText(GameTooltip, info.zone) end
	Kit.TipText(GameTooltip, L[M:AttendanceStatus(info)])
	GameTooltip:Show()
end

local function BuildAttendance(content)
	local frame = CreateFrame("Frame", nil, content)
	frame:SetAllPoints()
	frame.pick = Kit.Button(frame, "", 190, nil, function(owner) AttendanceNights(owner, frame) end)
	frame.pick:SetPoint("TOPLEFT", 4, -2)
	frame.bench = Kit.Button(frame, L["Bench"], 100, nil, function(owner) AttendanceBench(owner, frame) end)
	frame.bench:SetPoint("TOPRIGHT", -4, -2)
	frame.take = Kit.Button(frame, L["Take snapshot"], 150, nil, function(owner)
		if not M:TakeAttendanceSnapshot() then Kit.Toast(owner, L["No raid roster is available after combat."], { warn = true }) end
	end)
	frame.take:SetPoint("RIGHT", frame.bench, "LEFT", -6, 0)
	frame.snapshots = Kit.Button(frame, "", 190, nil, function(owner) AttendanceSnapshots(owner, frame) end)
	frame.snapshots:SetPoint("TOPLEFT", frame.pick, "BOTTOMLEFT", 0, -6)
	frame.actions = Kit.Button(frame, L["Attendance options"], 156, nil, function(owner) AttendanceActions(owner, frame) end)
	frame.actions:SetPoint("TOPRIGHT", frame.bench, "BOTTOMRIGHT", 0, -6)
	frame.summary = Kit.Text(frame, 12, "LEFT")
	frame.summary:SetPoint("TOPLEFT", frame.snapshots, "BOTTOMLEFT", 0, -6)
	frame.summary:SetPoint("TOPRIGHT", frame.actions, "BOTTOMRIGHT", 0, -6)
	frame.summary:SetWordWrap(true)
	frame.list = Kit.CreateTable(frame, {
		{ key = "name", title = L["Player"], value = function(row) return row.name end },
		{ key = "class", title = L["Class"], width = 92, value = function(row) return row.class or "" end },
		{ key = "status", title = L["Status"], width = 108, value = function(row) return row.status or "" end },
		{ key = "bench", title = L["Bench"], width = 62, align = "RIGHT", value = function(row) return row.bench or 0 end },
		{ key = "percent", title = "%", width = 54, align = "RIGHT", value = function(row) return row.percent or 0 end,
			text = function(row) return row.percent and ("%d%%"):format(row.percent) or "" end },
	}, {
		sortKey = "name", rowHeight = function() return math.max(M.db.rowHeight, math.ceil(E:TextScale() * 14 + 4)) end,
		createRow = function(widget)
			E:UseNameFont(widget.cells[1])
			widget:HookScript("OnEnter", AttendanceTip)
			widget:HookScript("OnLeave", function(own) if GameTooltip:IsOwned(own) then GameTooltip:Hide() end end)
		end,
		updateRow = function(widget, row) widget.attendance = row end,
		empty = { L["No attendance recorded"], L["Turn on recording in Attendance options to start keeping raid nights."] },
	})
	frame.list:SetPoint("TOPLEFT", frame.summary, "BOTTOMLEFT", -4, -4)
	frame.list:SetPoint("BOTTOMRIGHT")
	return frame
end

RefreshAttendance = function(frame)
	M.window:UpdateFooter()
	local history = M:AttendanceHistory()
	local nights = history and history.nights or {}
	local found
	for _, night in ipairs(nights) do if night == frame.night then found = true; break end end
	if not found then frame.night, frame.snapshot = nights[#nights], nil end
	local night, snapshot = frame.night, frame.snapshot
	frame.pick:SetText(night and date("%Y-%m-%d", night.at) or L["Raid nights"])
	frame.pick:SetEnabled(#nights > 0)
	frame.snapshots:SetText(snapshot and L["Snapshots"] or L["Whole night"])
	frame.snapshots:SetEnabled(night ~= nil)
	frame.bench:SetEnabled(night ~= nil and night == M:CurrentAttendanceNight())
	frame.take:SetEnabled(M:CanTakeAttendanceSnapshot())
	local rows, bosses, count = M:AttendanceSummary(night)
	if snapshot then
		rows = {}
		for _, entry in ipairs(snapshot.roster) do
			local status = L[M:AttendanceStatus(entry)]
			if entry.online == true then
				if entry.inside == true then status = L["In instance"] elseif entry.inside == false then status = L["Outside"] end
			end
			rows[#rows + 1] = { name = entry.name, class = entry.class, status = status, latest = entry }
		end
		for _, name in ipairs(snapshot.bench) do rows[#rows + 1] = { name = name, status = L["Bench"], bench = 1 } end
	end
	frame.list:SetData(rows)
	local totals = L["Snapshots %d · Bosses %d"]:format(count, bosses)
	if not M.db.recordAttendance then totals = L["Recording off"] .. "  ·  " .. totals end
	if night and night.omitted and night.omitted > 0 then
		totals = totals .. "  ·  " .. L["Earlier snapshots omitted (%d)"]:format(night.omitted)
	end
	local heading = snapshot and M:AttendanceSampleName(snapshot) or night and night.instance
	frame.summary:SetText(heading and (heading .. "\n" .. totals) or totals)
	frame.summary:SetHeight(math.max(22, math.ceil(frame.summary:GetStringHeight())))
end

function M:RefreshAttendanceWindow()
	if self.window and self.window:Current() == "attendance" then self.window:Refresh() end
end

function M:CreateWindow()
	if self.window then return self.window end
	local win = Kit.CreateTabbedWindow({
		name = "EldoUI_RaidLootWindow",
		options = { page = "module:RaidLoot" },
		title = L["Raid Loot"],
		width = WIDTH, height = HEIGHT,
		store = WindowStore,
		-- Nothing in it is blocked in combat: it stays open through a pull.
		hideInCombat = false,
		transparent = function() return M.db.transparent end,
		tabs = {
			{ key = "reserves", title = L["Reserves"], desc = L["Soft reserves and TMB lists you imported."],
				count = function() return M:Count("sr") + M:Count("tmb") end,
				create = BuildReserves, show = RefreshReserves, refresh = RefreshReserves },
			{ key = "ledger", title = L["GDKP ledger"], desc = L["Sales, the pot, cuts and the payout per player."],
				create = BuildLedger, show = RefreshLedger, refresh = RefreshLedger },
			{ key = "attendance", title = E.Key("Attendance"), desc = E.Key("Raid nights, snapshots, bench and attendance exports."),
				create = BuildAttendance, show = RefreshAttendance, refresh = RefreshAttendance },
		},
		help = { text = L["Import reserve lists to see them on tooltips and loot rolls. The ledger only keeps numbers: you roll, trade and pay out yourself."] },
		footer = function()
			if M.window and M.window:Current() == "attendance" then return "" end
			local ledger = M:Ledger()
			if not ledger then return L["No ledger yet."] end
			local totals = M:Totals(ledger)
			return E:Plural(totals.sales, "%d sale", "%d sales"):format(totals.sales) .. "  ·  " .. M.GoldText(totals.pot)
		end,
	})
	self.window = win
	-- The window sits on its mover; dragging the top bar moves the mover.
	function win.ApplyPosition(own)
		local frame = own.frame
		if not frame then return end
		if not own.mover then
			own.mover = E:CreateMover(frame, MOVER, L["GDKP Ledger"], { "TOPLEFT", "UIParent", "TOPLEFT", 552, -44 }, { sample = false })
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
	return win
end

function M:OpenWindow(tab)
	if not self.active then return end
	self:CreateWindow():Open(tab or "reserves")
end

function M:RefreshWindow()
	if self.window and self.window:IsOpen() then self.window:Refresh() end
end
