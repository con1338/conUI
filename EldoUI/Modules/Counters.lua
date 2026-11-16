-- EldoUI Counters: small icon + count blocks for items, currencies and
-- gold you want to watch, in one movable strip or each on its own mover.
-- A goal (for example 20/40) turns the count green once reached, and the
-- gain since login can show next to it. Display only.
local _, E = ...
local L = E.L

local M = E:NewModule("Counters", {
	title = "Counters",
	desc = "Watch items, currencies and gold as small movable counters, with goals and the session gain.",
	category = "Interface",
	frames = { "EldoUI_Counters" },
	movers = { "EldoUI_Counters" }, -- and one per counter shown on its own
	blizzard = {},
	savedKeys = { "profile.modules.Counters" },
	optionsPage = "module:Counters",
	presets = { "Column", "Large", "Minimal", "Row", "Separate" },
	uiAmount = "moderate",
	reload = false,
	defaults = {
		enabled = true,
		layout = "row",       -- "row" or "column"
		separate = false,     -- every counter on its own mover
		iconSize = 22,
		spacing = 4,
		fontSize = 12,
		showSession = true,
		showGoal = true,
		background = true,
		gold = false,
		goldGoal = 0,         -- in whole gold; 0 = no goal
		entries = {},         -- list of { kind = "item"|"currency", id = number, goal = number }
	},
})

local GREEN, GREY = { 0.27, 0.87, 0.27 }, { 0.65, 0.65, 0.65 }
local GOLD_ICON = 133784

local session = {} -- [counterKey] = amount at login

local IsSecret = E.Secret

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
local function CurrencyInfo(id)
	if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end
	local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
	return ok and info or nil
end

local function ItemName(id)
	return (C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (C_Item.GetItemInfo and C_Item.GetItemInfo(id))
end

-- Returns amount, name, icon for one entry (amount nil when unreadable).
local function Read(entry)
	if entry.kind == "gold" then
		return GetMoney(), L["Gold"], GOLD_ICON
	elseif entry.kind == "currency" then
		local info = CurrencyInfo(entry.id)
		if not info then return nil, "currency:" .. entry.id, 134400 end
		return info.quantity, info.name, info.iconFileID
	end
	local count = C_Item.GetItemCount(entry.id, true) -- bags and bank
	local name = ItemName(entry.id)
	if not name and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(entry.id) end
	local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(entry.id)
	return count, name or ("item:" .. entry.id), icon or 134400
end

local function Key(entry)
	return entry.kind .. ":" .. (entry.id or 0)
end

local function FormatAmount(entry, amount)
	if entry.kind == "gold" then
		-- Whole gold from 1g up; below that silver and copper, so a small gain isn't "+0".
		if amount >= 10000 then amount = amount - amount % 10000 end
		return E:FormatMoney(amount)
	end
	return BreakUpLargeNumbers(amount)
end

-- The entries shown, gold first when switched on.
function M:Entries()
	local list = {}
	if self.db.gold then table.insert(list, { kind = "gold", id = 0, goal = math.max(tonumber(self.db.goldGoal) or 0, 0) * 10000 }) end
	for _, entry in ipairs(self.db.entries) do table.insert(list, entry) end
	return list
end

---------------------------------------------------------------------------
-- Counter blocks
---------------------------------------------------------------------------
local function CounterTooltip(block)
	local entry = block.entry
	if not entry then return end
	GameTooltip:SetOwner(block, "ANCHOR_TOP", 0, 4)
	if entry.kind == "item" then
		GameTooltip:SetItemByID(entry.id)
	elseif entry.kind == "currency" and GameTooltip.SetCurrencyByID then
		GameTooltip:SetCurrencyByID(entry.id)
	else
		E.UIKit.TipTitle(GameTooltip, block.name or "")
	end
	GameTooltip:AddLine(" ")
	local amount = block.amount
	if amount then
		GameTooltip:AddDoubleLine(L["Have"], FormatAmount(entry, amount), GREY[1], GREY[2], GREY[3], 1, 1, 1)
		if (entry.goal or 0) > 0 then
			local done = amount >= entry.goal
			GameTooltip:AddDoubleLine(L["Goal"], FormatAmount(entry, entry.goal), GREY[1], GREY[2], GREY[3],
				done and GREEN[1] or 1, done and GREEN[2] or 1, done and GREEN[3] or 1)
		end
		local start = session[Key(entry)]
		if start then
			local gain = amount - start
			GameTooltip:AddDoubleLine(L["This session"], (gain < 0 and "-" or "+") .. FormatAmount(entry, math.abs(gain)),
				GREY[1], GREY[2], GREY[3], gain < 0 and 1 or GREEN[1], gain < 0 and 0.27 or GREEN[2], gain < 0 and 0.27 or GREEN[3])
		end
	end
	GameTooltip:Show()
end

function M:CreateBlock(parent)
	local block = CreateFrame("Frame", nil, parent)
	block.icon = block:CreateTexture(nil, "ARTWORK")
	E:TrimIcon(block.icon)
	block.iconBorder = CreateFrame("Frame", nil, block)
	block.iconBorder:SetFrameLevel(block:GetFrameLevel())
	E:SetTemplate(block.iconBorder)
	block.text = E:CreateText(block, self.db.fontSize, "LEFT")
	block.gain = E:CreateText(block, math.max(self.db.fontSize - 2, 9), "LEFT")
	block:EnableMouse(true)
	block:SetScript("OnEnter", CounterTooltip)
	block:SetScript("OnLeave", GameTooltip_Hide)
	E:RegisterHideable(block, parent:GetName())
	E:BindOptionsLink(block, { page = "module:Counters" })
	return block
end

-- Fill one block and size it; returns its width.
function M:FillBlock(block, entry)
	local db = self.db
	local amount, name, icon = Read(entry)
	if IsSecret(amount) then amount = nil end
	local key = Key(entry)
	if amount and not session[key] then session[key] = amount end
	block.entry, block.amount, block.name = entry, amount, name

	local size = db.iconSize
	block.iconBorder:ClearAllPoints()
	block.iconBorder:SetPoint("LEFT", 0, 0)
	block.iconBorder:SetSize(size, size)
	block.icon:ClearAllPoints()
	block.icon:SetPoint("TOPLEFT", block.iconBorder, "TOPLEFT", E.pixel, -E.pixel)
	block.icon:SetPoint("BOTTOMRIGHT", block.iconBorder, "BOTTOMRIGHT", -E.pixel, E.pixel)
	block.icon:SetTexture(icon or 134400)
	E:SetTemplate(block.iconBorder)

	E:SetFont(block.text, db.fontSize)
	E:SetFont(block.gain, math.max(db.fontSize - 2, 9))
	block.text:ClearAllPoints()
	block.text:SetPoint("LEFT", block.iconBorder, "RIGHT", 4, 0)
	local text = amount and FormatAmount(entry, amount) or "?"
	local goal = entry.goal or 0
	if db.showGoal and goal > 0 and amount then
		text = text .. E:TextHex("secondary") .. "/" .. FormatAmount(entry, goal) .. "|r"
	end
	block.text:SetText(text)
	if amount and goal > 0 and amount >= goal then
		block.text:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
	else
		block.text:SetTextColor(1, 1, 1)
	end

	local width = size + 4 + block.text:GetStringWidth()
	local gain = amount and session[key] and amount - session[key] or 0
	if db.showSession and gain ~= 0 then
		block.gain:ClearAllPoints()
		block.gain:SetPoint("LEFT", block.text, "RIGHT", 4, 0)
		block.gain:SetText((gain > 0 and "+" or "-") .. FormatAmount(entry, math.abs(gain)))
		if gain > 0 then block.gain:SetTextColor(GREEN[1], GREEN[2], GREEN[3]) else block.gain:SetTextColor(E:TokenColor("bad")) end
		block.gain:Show()
		width = width + 4 + block.gain:GetStringWidth()
	else
		block.gain:Hide()
	end
	width = math.ceil(width + 4)
	block:SetSize(width, size)
	block:Show()
	return width
end

---------------------------------------------------------------------------
-- Strip (all counters together) or separate movers
---------------------------------------------------------------------------
function M:CreateStrip()
	local strip = CreateFrame("Frame", "EldoUI_Counters", UIParent)
	strip:SetFrameStrata("LOW")
	strip:SetSize(120, 26)
	strip.blocks = {}
	self.strip = strip
	-- followShown: no move-mode box while the strip is hidden (separate mode, nothing watched).
	E:CreateMover(strip, "EldoUI_Counters", L["Counters"], { "TOPLEFT", "UIParent", "TOPLEFT", 8, -40 }, { followShown = true })
end

local separateFrames = {} -- [counterKey] = frame (frames and movers can't be deleted, so reuse them)

function M:SeparateFrame(entry, index)
	local key = Key(entry)
	local frame = separateFrames[key]
	if not frame then
		local name = "EldoUI_Counter_" .. key:gsub("[^%w]", "_")
		frame = CreateFrame("Frame", name, UIParent)
		frame:SetFrameStrata("LOW")
		frame:SetSize(80, 26)
		frame.block = self:CreateBlock(frame)
		frame.block:SetPoint("LEFT", 4, 0)
		separateFrames[key] = frame
		-- Placed under the strip's spot, so every layout's Counters point
		-- places the separate counters too.
		E:CreateMover(frame, name, L["Counter: %s"]:format(select(2, Read(entry)) or key),
			{ "TOPLEFT", "EldoUI_CountersMover", "TOPLEFT", 0, -(index - 1) * 30 }, { followShown = true })
	end
	return frame
end

function M:Update()
	if not self.strip then return end
	local db = self.db
	local entries = self:Entries()
	local strip = self.strip
	for _, frame in pairs(separateFrames) do frame.used = false end

	if db.separate then
		for _, block in ipairs(strip.blocks) do block:Hide() end
		strip:Hide()
		for index, entry in ipairs(entries) do
			local frame = self:SeparateFrame(entry, index)
			frame.used = true
			local width = self:FillBlock(frame.block, entry)
			frame:SetSize(width + 8, db.iconSize + 6)
			if db.background then E:SetTemplate(frame, true) elseif frame.SetBackdrop then frame:SetBackdrop(nil) end
			E:SetStyleEdge(frame, db.background) -- WoW Forever art style frame line
			frame:Show()
		end
	else
		local x, y, maxWidth = 4, -3, 0
		for index, entry in ipairs(entries) do
			local block = strip.blocks[index] or self:CreateBlock(strip)
			strip.blocks[index] = block
			local width = self:FillBlock(block, entry)
			block:ClearAllPoints()
			block:SetPoint("TOPLEFT", strip, "TOPLEFT", x, y)
			if db.layout == "column" then
				y = y - db.iconSize - db.spacing
				maxWidth = math.max(maxWidth, width)
			else
				x = x + width + db.spacing * 2
			end
		end
		for index = #entries + 1, #strip.blocks do strip.blocks[index]:Hide() end
		if db.layout == "column" then
			strip:SetSize(math.max(maxWidth + 8, 40), math.max(-y - db.spacing + 3, db.iconSize + 6))
		else
			strip:SetSize(math.max(x - db.spacing * 2 + 4, 40), db.iconSize + 6)
		end
		if db.background then E:SetTemplate(strip, true) elseif strip.SetBackdrop then strip:SetBackdrop(nil) end
		E:SetStyleEdge(strip, db.background) -- WoW Forever art style frame line
		strip:SetShown(#entries > 0)
	end
	for _, frame in pairs(separateFrames) do
		if not frame.used then frame:Hide() end
	end
end

---------------------------------------------------------------------------
-- Adding and removing: an item link, an item ID, "c" + currency ID, a
-- currency link, or a currency / cached item name.
---------------------------------------------------------------------------
local function FindCurrencyByName(text)
	if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize) then return nil end
	local wanted = text:lower()
	for index = 1, C_CurrencyInfo.GetCurrencyListSize() do
		local info = C_CurrencyInfo.GetCurrencyListInfo(index)
		if info and not info.isHeader and info.name and info.name:lower() == wanted then
			local link = C_CurrencyInfo.GetCurrencyListLink and C_CurrencyInfo.GetCurrencyListLink(index)
			local id = link and tonumber(link:match("currency:(%d+)"))
			if id then return id end
		end
	end
end

function M:AddFromText(text)
	text = strtrim(text or "")
	if text == "" then return false end
	local kind, id
	local currency = text:match("currency:(%d+)") or text:match("^[cC](%d+)$")
	if currency then
		kind, id = "currency", tonumber(currency)
	else
		id = tonumber(text:match("item:(%d+)") or text:match("^(%d+)$"))
		if id then kind = "item" end
	end
	if not id then
		local currencyID = FindCurrencyByName(text)
		if currencyID then
			kind, id = "currency", currencyID
		elseif C_Item.GetItemInfo then
			local _, link = C_Item.GetItemInfo(text)
			id = link and tonumber(link:match("item:(%d+)"))
			if id then kind = "item" end
		end
	end
	if not id then return false end
	if kind == "item" and not C_Item.GetItemInfoInstant(id) then return false end
	if kind == "currency" and not CurrencyInfo(id) then return false end
	for _, entry in ipairs(self.db.entries) do
		if entry.kind == kind and entry.id == id then return true end
	end
	table.insert(self.db.entries, { kind = kind, id = id, goal = 0 })
	self:Update()
	return true
end

local ROW_HEIGHT = 24

function M:RefreshManager()
	local manager = self.manager
	if not manager or not manager:IsShown() then return end
	manager.title:SetTextColor(E:TokenColor("accent")) -- accent at draw time
	local entries = self.db.entries
	for index, entry in ipairs(entries) do
		local row = manager.rows[index]
		if not row then
			row = CreateFrame("Frame", nil, manager.content)
			row:SetHeight(ROW_HEIGHT)
			row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
			row:SetPoint("TOPRIGHT", manager.content, "TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)
			row.bg = row:CreateTexture(nil, "BACKGROUND")
			row.bg:SetAllPoints()
			row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and E.tokens.hover.row / 2 or 0)
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(18, 18)
			row.icon:SetPoint("LEFT", 4, 0)
			E:TrimIcon(row.icon)
			row.name = E.UIKit.Text(row, E.tokens.size.label, "LEFT")
			row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
			row.name:SetPoint("RIGHT", row, "RIGHT", -120, 0)
			-- The kit's remove cross (danger hover, "Remove" tooltip).
			row.remove = E.UIKit.RemoveButton(row)
			row.remove:SetPoint("RIGHT", -4, 0)
			row.remove:SetScript("OnClick", function()
				table.remove(M.db.entries, row.index)
				M:Update()
				M:RefreshManager()
			end)
			row.goal = E.UIKit.Input(row, { width = 50, height = 20, numeric = true })
			row.goal:SetPoint("RIGHT", row.remove, "LEFT", -10, 0)
			row.goal:SetScript("OnEnterPressed", function(box)
				local data = M.db.entries[row.index]
				if data then data.goal = tonumber(box:GetText()) or 0 end
				box:ClearFocus()
				M:Update()
			end)
			row.goal:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
			row.goal:SetScript("OnEditFocusLost", function(box)
				local data = M.db.entries[row.index]
				if data then data.goal = tonumber(box:GetText()) or 0 end
				M:Update()
			end)
			row.goalLabel = E.UIKit.Text(row, E.tokens.size.small, "RIGHT", "secondary")
			row.goalLabel:SetPoint("RIGHT", row.goal, "LEFT", -6, 0)
			row.goalLabel:SetText(L["Goal"])
			manager.rows[index] = row
		end
		row.index = index
		local _, name, icon = Read(entry)
		row.icon:SetTexture(icon or 134400)
		row.name:SetText(name)
		row.goal:SetText(tostring(entry.goal or 0))
		row:Show()
	end
	for index = #entries + 1, #manager.rows do manager.rows[index]:Hide() end
	manager.content:SetHeight(math.max(#entries * ROW_HEIGHT, 1))
	manager.empty:SetShown(#entries == 0)
	if manager.area then manager.area:Update() end
end

function M:ShowManager()
	local manager = self.manager
	if not manager then
		-- The shared tool window shell and kit parts (E.UIKit).
		manager = E.UIKit.CreateToolWindow("EldoUI_CountersManager", { title = L["Counters"], width = 400, height = 380,
			strata = "DIALOG" })

		local box = E.UIKit.Input(manager, { width = 290, height = 22 })
		box:SetPoint("TOPLEFT", 8, -36)
		local function Add()
			if M:AddFromText(box:GetText()) then
				box:SetText("")
			else
				M:Print(L["Not found. Use an item link or ID, a currency link, c<currency ID>, or a currency name."])
			end
			M:RefreshManager()
		end
		box:SetScript("OnEnterPressed", function(b) Add(); b:ClearFocus() end)
		box:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
		manager.box = box
		local add = E.UIKit.Button(manager, E:GameText(ADD, L["Add"]), { width = 86, onClick = Add })
		add:SetPoint("LEFT", box, "RIGHT", 8, 0)
		manager.add = add

		local area = E.UIKit.ScrollArea(manager)
		area:SetPoint("TOPLEFT", 8, -66)
		area:SetPoint("BOTTOMRIGHT", -8, 40)
		manager.area = area
		manager.content = area.child
		manager.rows = {}

		manager.empty = E.UIKit.Text(manager, E.tokens.size.label, "CENTER", "secondary")
		manager.empty:SetPoint("CENTER", area, "CENTER")
		manager.empty:SetText(L["Nothing watched yet."])

		local footer = E.UIKit.Text(manager, E.tokens.size.small, "LEFT", "secondary")
		footer:SetPoint("BOTTOMLEFT", 8, 8)
		footer:SetPoint("BOTTOMRIGHT", -8, 8)
		footer:SetWordWrap(true)
		footer:SetText(L["Shift-click an item or currency into the box, or type an item ID, c<currency ID> or a currency name. Goal 0 means no goal."])

		-- Shift-clicked links go into our box while it has focus.
		E:HookLinkInsert(function(link)
			if link and box:IsVisible() and box:HasFocus() then box:SetText(link) end
		end)
		manager:HookScript("OnShow", function() M:RefreshManager() end)
		self.manager = manager
	end
	manager:Show()
	self:RefreshManager()
end

---------------------------------------------------------------------------
-- Enable / disable
---------------------------------------------------------------------------
local EVENTS = { "BAG_UPDATE_DELAYED", "CURRENCY_DISPLAY_UPDATE", "PLAYER_MONEY", "GET_ITEM_INFO_RECEIVED", "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED" }

function M:OnEnable()
	if not self.strip then self:CreateStrip() end
	if not self.events then
		local events = CreateFrame("Frame")
		events:SetScript("OnEvent", function()
			E:Debounce(events, 0.3, function()
				if M.active then M:Update() end
			end)
		end)
		self.events = events
	end
	for _, event in ipairs(EVENTS) do pcall(self.events.RegisterEvent, self.events, event) end
	self:Update()
	-- Item names and currency data can arrive a bit after login.
	C_Timer.After(3, function() if M.active then M:Update() end end)
end

function M:OnDisable()
	if self.events then self.events:UnregisterAllEvents() end
	if self.strip then self.strip:Hide() end
	for _, frame in pairs(separateFrames) do frame:Hide() end
	if self.manager then self.manager:Hide() end
end

-- Re-apply sizes, fonts and theme colors.
function M:OnProfileChanged()
	if self.manager then E:SetPanelTemplate(self.manager); self:RefreshManager() end
	if self.active then self:Update() end
end

---------------------------------------------------------------------------
-- Style presets
---------------------------------------------------------------------------
E:RegisterStyles("Counters", {
	{ key = "Row", title = "Row", desc = "One strip, counters side by side, with goals and session gain.",
		settings = { layout = "row", separate = false, iconSize = 22, spacing = 4, fontSize = 12, showSession = true, showGoal = true, background = true } },
	{ key = "Column", title = "Column", desc = "One strip, counters stacked.",
		settings = { layout = "column", separate = false, iconSize = 22, spacing = 4, fontSize = 12, showSession = true, showGoal = true, background = true } },
	{ key = "Minimal", title = "Minimal", desc = "Small row without background or session gain.",
		settings = { layout = "row", separate = false, iconSize = 16, spacing = 4, fontSize = 11, showSession = false, showGoal = true, background = false } },
	{ key = "Large", title = "Large", desc = "Bigger 30 px icons and 14 pt text in a column.",
		settings = { layout = "column", separate = false, iconSize = 30, spacing = 6, fontSize = 14, showSession = true, showGoal = true, background = true } },
	{ key = "Separate", title = "Separate", desc = "Every counter on its own mover, to place anywhere.",
		settings = { separate = true, iconSize = 22, spacing = 4, fontSize = 12, showSession = true, showGoal = true, background = true } },
})

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
M.options = {
	{ type = "header", label = "Watched" },
	{ type = "execute", label = "Add or remove counters", desc = "Open the list of watched items and currencies, set goals and remove entries.", func = function() M:ShowManager() end },
	{ type = "toggle", key = "gold", label = "Gold counter", desc = "Also show your gold as a counter." },
	{ type = "range", key = "goldGoal", label = "Gold goal", unit = "g", zeroText = "No goal", min = 0, max = 100000, softMax = 5000, step = 1,
		dependsOn = "gold",
		desc = "Gold to reach; the gold counter turns green once you have it. The slider goes to 5000; type a bigger goal in the box." },
	{ type = "header", label = "Layout" },
	{ type = "select", key = "layout", label = "Direction", values = { row = "Row", column = "Column" }, desc = "Side by side or stacked, for the shared strip.", disabled = function() return M.db.separate and L["Only for the shared strip, and Separate movers is on."] end },
	{ type = "toggle", key = "separate", label = "Separate movers", desc = "Every counter on its own mover instead of one strip. Place them in move mode." },
	{ type = "range", unit = "px", key = "iconSize", label = "Icon size", min = 12, max = 40, step = 1, desc = "Size of each counter's icon." },
	{ type = "range", key = "fontSize", label = "Text size", min = 9, max = 18, step = 1, desc = "Size of the count text." },
	{ type = "range", unit = "px", key = "spacing", label = "Spacing", min = 0, max = 16, step = 1, desc = "Gap between counters in the strip.", disabled = function() return M.db.separate and L["Only for the shared strip, and Separate movers is on."] end },
	{ type = "toggle", key = "background", label = "Background", desc = "A see-through panel behind the counters." },
	{ type = "header", label = "Text" },
	{ type = "toggle", key = "showGoal", label = "Show goal", desc = "Show have/goal; the count turns green once the goal is reached." },
	{ type = "toggle", key = "showSession", label = "Show session gain", desc = "Show what you gained or lost since login next to the count." },
	{ type = "execute", label = "Move", desc = "Unlock EldoUI frames to drag the counters.", func = function() E:MoveFrame("EldoUI_Counters") end },
}
