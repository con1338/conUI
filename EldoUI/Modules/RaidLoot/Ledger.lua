-- EldoUI Raid Loot: the GDKP ledger. Sales are added by hand (item,
-- buyer, gold); the ledger keeps the pot, the organizer's cut, other cuts
-- (a fixed gold amount each) and the payout per player, and exports them as
-- text. It never trades gold or handles bids.
local _, E = ...
local L = E.L
local M = E.RaidLoot

local floor = math.floor

local function Gold(value)
	value = tonumber(value)
	if not value or value ~= value or value < 0 then return nil end
	return floor(value + 0.5)
end
M.Gold = Gold

function M:Ledgers()
	return self:Data().ledgers
end

-- The ledger shown (the newest unless another was picked).
function M:Ledger(create)
	local data = self:Data()
	local list = data.ledgers
	for _, ledger in ipairs(list) do
		if ledger.id == data.current then return ledger end
	end
	if list[#list] then
		data.current = list[#list].id
		return list[#list]
	end
	if create then return self:NewLedger() end
end

function M:NewLedger(name)
	local data = self:Data()
	data.nextID = (data.nextID or 0) + 1
	local ledger = {
		id = data.nextID,
		name = (type(name) == "string" and strtrim(name) ~= "") and strtrim(name) or date("%Y-%m-%d"),
		created = time(),
		cut = self.db.organizerCut,
		organizer = self.Clean(UnitName("player")),
		cuts = {}, players = {}, sales = {},
	}
	table.insert(data.ledgers, ledger)
	data.current = ledger.id
	-- Old ledgers beyond 20 go.
	while #data.ledgers > 20 do table.remove(data.ledgers, 1) end
	self:Changed()
	return ledger
end

function M:SelectLedger(id)
	self:Data().current = id
	self:Changed()
end

function M:DeleteLedger(id)
	local data = self:Data()
	for index, ledger in ipairs(data.ledgers) do
		if ledger.id == id then table.remove(data.ledgers, index) break end
	end
	if data.current == id then data.current = nil end
	self:Changed()
end

local function Name(text)
	text = strtrim(tostring(text or ""))
	if text == "" then return nil end
	return text
end

-- A sale: item (ID, link or text), buyer, gold. Returns the sale or nil, why.
function M:AddSale(item, buyer, gold)
	local ledger = self:Ledger(true)
	buyer, gold = Name(buyer), Gold(gold)
	if not buyer then return nil, L["Enter the buyer."] end
	if not gold or gold <= 0 then return nil, L["Enter the price in gold."] end
	local itemID = self.ItemID(item)
	local link = type(item) == "string" and item:find("|H") and item or nil
	local label = not itemID and Name(item) or nil
	if not itemID and not label then return nil, L["Enter the item: drop it on the slot, shift-click it or type its name."] end
	ledger.nextSale = (ledger.nextSale or 0) + 1
	local sale = { id = ledger.nextSale, item = itemID, link = link, label = label, buyer = buyer, gold = gold, t = time() }
	table.insert(ledger.sales, sale)
	self:AddPlayer(buyer, true)
	self:Changed()
	return sale
end

function M:RemoveSale(id)
	local ledger = self:Ledger()
	if not ledger then return end
	for index, sale in ipairs(ledger.sales) do
		if sale.id == id then table.remove(ledger.sales, index) break end
	end
	self:Changed()
end

function M:SetOrganizerCut(percent)
	local ledger = self:Ledger(true)
	percent = tonumber(percent)
	if not percent then return end
	ledger.cut = math.max(0, math.min(100, percent))
	self:Changed()
end

function M:AddCut(label, gold)
	local ledger = self:Ledger(true)
	label, gold = Name(label), Gold(gold)
	if not (label and gold and gold > 0) then return nil end
	table.insert(ledger.cuts, { label = label, gold = gold })
	self:Changed()
	return true
end

function M:RemoveCut(index)
	local ledger = self:Ledger()
	if ledger and ledger.cuts[index] then table.remove(ledger.cuts, index) end
	self:Changed()
end

function M:HasPlayer(name)
	local ledger = self:Ledger()
	if not (ledger and name) then return false end
	for _, player in ipairs(ledger.players) do
		if player:lower() == name:lower() then return true end
	end
	return false
end

function M:AddPlayer(name, quiet)
	local ledger = self:Ledger(true)
	name = Name(name)
	if not name or self:HasPlayer(name) then return false end
	table.insert(ledger.players, name)
	if not quiet then self:Changed() end
	return true
end

function M:RemovePlayer(name)
	local ledger = self:Ledger()
	if not ledger then return end
	for index, player in ipairs(ledger.players) do
		if player == name then table.remove(ledger.players, index) break end
	end
	self:Changed()
end

-- Everyone in your group now joins the split.
function M:FillFromGroup()
	local added = 0
	local names = {}
	for _, shown in pairs(self:GroupNames()) do names[#names + 1] = shown end
	table.sort(names)
	for _, shown in ipairs(names) do
		if self:AddPlayer(shown, true) then added = added + 1 end
	end
	self:Changed()
	return added
end

-- The sums: pot, cuts, what is shared and each player's part.
function M:Totals(ledger)
	ledger = ledger or self:Ledger()
	local out = { pot = 0, organizer = 0, other = 0, shared = 0, per = 0, rest = 0, players = {}, sales = 0 }
	if not ledger then return out end
	local spent = {}
	for _, sale in ipairs(ledger.sales) do
		out.pot = out.pot + sale.gold
		out.sales = out.sales + 1
		local key = sale.buyer:lower()
		spent[key] = (spent[key] or 0) + sale.gold
	end
	out.organizer = floor(out.pot * (ledger.cut or 0) / 100)
	for _, cut in ipairs(ledger.cuts) do out.other = out.other + cut.gold end
	out.shared = math.max(0, out.pot - out.organizer - out.other)
	local count = #ledger.players
	if count > 0 then
		out.per = out.shared / count
		if self.db.roundGold then out.per = floor(out.per) end
		out.rest = out.shared - out.per * count
	end
	for _, name in ipairs(ledger.players) do
		local paid = spent[name:lower()] or 0
		out.players[#out.players + 1] = { name = name, spent = paid, share = out.per, net = out.per - paid }
	end
	return out
end

local function GoldText(value)
	if value == floor(value) then return ("%dg"):format(value) end
	return ("%.2fg"):format(value)
end
M.GoldText = GoldText

function M:SaleItemText(sale)
	if sale.link then return sale.link end
	if sale.item then
		local name = C_Item and C_Item.GetItemNameByID and self.Clean(C_Item.GetItemNameByID(sale.item))
		return name or ("#" .. sale.item)
	end
	return sale.label or "?"
end

-- The ledger as plain text (for the copy box).
function M:ExportText(ledger)
	ledger = ledger or self:Ledger()
	if not ledger then return "" end
	local totals = self:Totals(ledger)
	local lines = {}
	lines[#lines + 1] = (L["GDKP ledger: %s"]):format(ledger.name)
	lines[#lines + 1] = ""
	lines[#lines + 1] = L["Sales"]
	for _, sale in ipairs(ledger.sales) do
		local item = self:SaleItemText(sale):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
		lines[#lines + 1] = ("%s - %s - %s"):format(item, sale.buyer, GoldText(sale.gold))
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = (L["Pot: %s"]):format(GoldText(totals.pot))
	lines[#lines + 1] = (L["Organizer cut (%d%%): %s"]):format(ledger.cut or 0, GoldText(totals.organizer))
	for _, cut in ipairs(ledger.cuts) do
		lines[#lines + 1] = ("%s: %s"):format(cut.label, GoldText(cut.gold))
	end
	lines[#lines + 1] = (L["Shared: %s"]):format(GoldText(totals.shared))
	lines[#lines + 1] = (L["Players: %d, each %s"]):format(#ledger.players, GoldText(totals.per))
	if totals.rest > 0 then lines[#lines + 1] = (L["Left over: %s"]):format(GoldText(totals.rest)) end
	lines[#lines + 1] = ""
	lines[#lines + 1] = L["Payout (share minus purchases)"]
	for _, row in ipairs(totals.players) do
		lines[#lines + 1] = ("%s: %s"):format(row.name, GoldText(row.net))
	end
	return table.concat(lines, "\n")
end

-- One chat line with the totals (one click).
function M:PostTotals()
	local ledger = self:Ledger()
	if not ledger then return false end
	local totals = self:Totals(ledger)
	return self:Say((L["GDKP %s: pot %s, %d players, %s each"]):format(ledger.name, GoldText(totals.pot), #ledger.players, GoldText(totals.per)))
end
