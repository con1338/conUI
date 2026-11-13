-- EldoUI Bags, part three: extras of the Categories view.
--
--   Own categories as many as the player likes, each with a name, a
--                  color, a search, items filed by hand (dropped on its
--                  title), items left out, a priority and a bags / bank
--                  switch, in an order the player sets for every section.
--                  The three search slots of older versions become the
--                  first three, once. Shared as a string (!EUBC1!).
--   Group stacks   stacks of one item show as one slot with the total
--                  count. The slot is the game's own button of the first
--                  stack in bag order, so a click, a drag, a split, using
--                  or selling the item acts on that one real stack, as on
--                  any other slot. Full stacks only, when chosen, and every
--                  stack apart again while a vendor, the Send Mail tab, the
--                  bank or a trade is open, where single stacks matter.
--
-- Only the view changes: nothing moves an item, and "Move these" still
-- reads the real bag slots. Filing an item only reads which item is on
-- the cursor and gives it back to its slot. Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local M = E:GetModule("Bags")
if not M then return end

-- True when `window` shows grouped stacks now.
function M:GroupsStacks(window)
	local db = self.db
	if not (db and db.groupItems and window) then return false end
	local view = window.kind == "bank" and db.bankView or db.view
	if view ~= "categories" then return false end
	if db.groupApart and self:MoveTarget() then return false end
	return true
end

local function MaxStack(id)
	local size = id and C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(id)
	return tonumber(size) or 1
end

-- records: one section's filled slots in bag order. Returns the list with
-- the stacks of each item folded into its first stack, which carries
-- `total` (the count it shows) and `stacks`. The same item string groups,
-- so items with another suffix or enchant stay apart.
function M:GroupStacks(window, records)
	local on = self:GroupsStacks(window)
	window.grouped = on
	if not on then return records end
	local partial = self.db.groupPartial
	local list, first = {}, {}
	for _, record in ipairs(records) do
		local key = record.short ~= "" and record.short or record.id
		local full = not partial or (record.count or 1) >= MaxStack(record.id)
		local lead = key and full and first[key]
		if lead then
			lead.total = (lead.total or lead.count or 1) + (record.count or 1)
			lead.stacks = (lead.stacks or 1) + 1
		else
			if key and full then first[key] = record end
			list[#list + 1] = record
		end
	end
	return list
end

-- The tooltip of a grouped slot says how the total is made up.
function M:StackTip(button)
	local record = button.eldoRecord
	if not (record and record.stacks and record.stacks > 1) then return end
	if not (GameTooltip:IsShown() and GameTooltip:GetOwner() == button) then return end
	local color = E.tokens.text.secondary
	local line = E:Plural(record.stacks, "%d in %d stack", "%d in %d stacks"):format(record.total, record.stacks)
	GameTooltip:AddLine(line, color[1], color[2], color[3])
	GameTooltip:Show()
end

-- A vendor, the mailbox, a trade or the bank opened or closed: the bag
-- window shows its stacks apart or grouped again. The Send Mail tab
-- opens without an event, so its frame tells.
local mailHooked = false
hooksecurefunc(M, "UpdateMoveButton", function(self, window)
	if not mailHooked then
		local send = rawget(_G, "SendMailFrame")
		if send and send.HookScript then
			mailHooked = true
			local function Changed() M:UpdateMoveButton(M.windows.bags) end
			send:HookScript("OnShow", Changed)
			send:HookScript("OnHide", Changed)
		end
	end
	if not (window and window:IsShown() and self.db.groupItems) then return end
	local now = self:GroupsStacks(window)
	if now ~= (window.grouped or false) then
		window.grouped = now
		self:UpdateWindow(window)
	end
end)

---------------------------------------------------------------------------
-- Own categories
---------------------------------------------------------------------------
local MAX_CATEGORIES = 60
local MAX_NAME = 40
M.MAX_CATEGORIES = MAX_CATEGORIES
-- New categories take these colors in turn; the editor can change them.
local PALETTE = {
	{ 0.95, 0.75, 0.30 }, { 0.45, 0.75, 0.95 }, { 0.55, 0.85, 0.45 }, { 0.90, 0.50, 0.85 },
	{ 0.95, 0.55, 0.40 }, { 0.65, 0.65, 0.95 }, { 0.40, 0.85, 0.80 }, { 0.85, 0.85, 0.50 },
}
local own = { sorted = {}, byID = {}, queries = {} }

function M:CategoryList()
	local db = self.db
	if type(db.categoryList) ~= "table" then db.categoryList = {} end
	return db.categoryList
end

local function Color(value, fallback)
	if type(value) == "table" and tonumber(value[1]) and tonumber(value[2]) and tonumber(value[3]) then
		return { math.min(math.max(value[1], 0), 1), math.min(math.max(value[2], 0), 1), math.min(math.max(value[3], 0), 1) }
	end
	return { fallback[1], fallback[2], fallback[3] }
end

-- Every field in place and of the right kind (a profile edited by hand or
-- an older import may lack some).
local function Normalize(cat, index)
	cat.id = tonumber(cat.id) or index
	cat.name = type(cat.name) == "string" and cat.name:sub(1, MAX_NAME) or ""
	cat.query = type(cat.query) == "string" and cat.query or ""
	cat.color = Color(cat.color, PALETTE[(cat.id - 1) % #PALETTE + 1])
	if type(cat.items) ~= "table" then cat.items = {} end
	if type(cat.ignore) ~= "table" then cat.ignore = {} end
	cat.priority = math.floor(math.min(math.max(tonumber(cat.priority) or 0, 0), 10))
	if cat.bags == nil then cat.bags = true end
	if cat.bank == nil then cat.bank = true end
end

local function NextID(list)
	local high = 0
	for _, cat in ipairs(list) do high = math.max(high, tonumber(cat.id) or 0) end
	return high + 1
end

-- Reads the list again after any change: the search of each category is
-- parsed here once, not for every slot.
function M:RebuildCategories()
	local db = self.db
	if not db then return end
	local list = self:CategoryList()
	if not db.customMoved then
		db.customMoved = true
		for index, custom in ipairs(db.custom or {}) do
			if type(custom) == "table" and type(custom.query) == "string" and strtrim(custom.query) ~= "" and #list < MAX_CATEGORIES then
				local name = type(custom.name) == "string" and custom.name ~= "" and custom.name or L["Custom %s"]:format(index)
				list[#list + 1] = { id = NextID(list), name = name, query = custom.query }
			end
		end
	end
	wipe(own.sorted)
	wipe(own.byID)
	wipe(own.queries)
	local seen = {}
	for index, cat in ipairs(list) do
		Normalize(cat, index)
		if seen[cat.id] then cat.id = NextID(list) end
		seen[cat.id] = true
		cat.order = index
		own.byID[cat.id] = cat
		own.sorted[#own.sorted + 1] = cat
		if strtrim(cat.query) ~= "" then own.queries[cat.id] = M.ParseQuery(cat.query) end
	end
	table.sort(own.sorted, function(a, b)
		if a.priority ~= b.priority then return a.priority > b.priority end
		return a.order < b.order
	end)
end

function M:OwnKey(cat)
	return "own:" .. cat.id
end

function M:OwnCategory(key)
	local id = type(key) == "string" and tonumber(key:match("^own:(%d+)$"))
	return id and own.byID[id] or nil
end

local function ShownIn(cat, window)
	if window and window.kind == "bank" then return cat.bank ~= false end
	return cat.bags ~= false
end

-- The own category an item belongs to in `window`: an item filed by hand
-- first, then each category's search by priority, skipping the items it
-- leaves out. nil: the built-in sections decide.
function M:OwnCategoryOf(record, window)
	if #own.sorted == 0 then return nil end
	local id = record.id
	if id then
		for _, cat in ipairs(own.sorted) do
			if cat.items[id] then
				if ShownIn(cat, window) then return "own:" .. cat.id end
				break
			end
		end
	end
	for _, cat in ipairs(own.sorted) do
		local query = own.queries[cat.id]
		if query and ShownIn(cat, window) and not (id and cat.ignore[id]) and M.Matches(query, record) then
			return "own:" .. cat.id
		end
	end
end

function M:CategoryName(cat)
	return cat.name ~= "" and cat.name or L["Category %d"]:format(cat.id)
end

-- The section title of an own category, in its color.
function M:OwnSectionTitle(key)
	local cat = self:OwnCategory(key)
	if not cat then return nil end
	local c = cat.color
	local name = self:CategoryName(cat):gsub("|", "||")
	return ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, name)
end

-- The built-in sections in their default order (the three old search
-- slots only until they became own categories).
local function BuiltIn()
	local list = {}
	for _, key in ipairs(M.CATEGORY_ORDER) do
		if not (M.db.customMoved and key:find("^custom%d$")) then list[#list + 1] = key end
	end
	return list
end

function M:IsSectionKey(key)
	if key == "free" then return false end
	if self:OwnCategory(key) then return true end
	for _, builtin in ipairs(BuiltIn()) do
		if builtin == key then return true end
	end
	return false
end

-- Every section key of the Categories view in its order, Free last. A
-- category the order doesn't name yet goes on top; a built-in section
-- the order lacks goes before Free.
function M:SectionOrder()
	local saved = type(self.db.categoryOrder) == "table" and self.db.categoryOrder or {}
	local order, seen = {}, { free = true }
	for _, cat in ipairs(self:CategoryList()) do
		local key = "own:" .. cat.id
		local named = false
		for _, value in ipairs(saved) do
			if value == key then named = true break end
		end
		if not named then
			order[#order + 1] = key
			seen[key] = true
		end
	end
	for _, key in ipairs(saved) do
		if not seen[key] and self:IsSectionKey(key) then
			order[#order + 1] = key
			seen[key] = true
		end
	end
	for _, key in ipairs(BuiltIn()) do
		if not seen[key] then
			order[#order + 1] = key
			seen[key] = true
		end
	end
	order[#order + 1] = "free"
	return order
end

-- Saves an order (without Free) and redraws.
function M:SetSectionOrder(order)
	local saved = {}
	for _, key in ipairs(order) do
		if key ~= "free" then saved[#saved + 1] = key end
	end
	self.db.categoryOrder = saved
	self:RefreshViews()
end

-- Moves `key` by `delta` places, or to the top with delta "top".
function M:MoveSection(key, delta)
	local order = self:SectionOrder()
	table.remove(order) -- Free
	local at
	for index, value in ipairs(order) do
		if value == key then at = index end
	end
	if not at then return false end
	local to = delta == "top" and 1 or math.min(math.max(at + delta, 1), #order)
	if to == at then return false end
	table.remove(order, at)
	table.insert(order, to, key)
	self:SetSectionOrder(order)
	return true
end

function M:NewCategory(name)
	local list = self:CategoryList()
	if #list >= MAX_CATEGORIES then return nil end
	local id = NextID(list)
	local cat = { id = id, name = (name or ""):sub(1, MAX_NAME), query = "", items = {}, ignore = {}, priority = 0, bags = true, bank = true,
		color = Color(nil, PALETTE[(id - 1) % #PALETTE + 1]) }
	list[#list + 1] = cat
	self:CategoriesChanged()
	return cat
end

function M:DeleteCategory(cat)
	local list = self:CategoryList()
	for index, value in ipairs(list) do
		if value == cat or value.id == cat.id then
			table.remove(list, index)
			break
		end
	end
	local key = "own:" .. cat.id
	local saved = self.db.categoryOrder or {}
	for index = #saved, 1, -1 do
		if saved[index] == key then table.remove(saved, index) end
	end
	self:CategoriesChanged()
end

function M:CategoriesChanged()
	self:RebuildCategories()
	self:RefreshViews()
	if self.RefreshCategoryEditor then self:RefreshCategoryEditor() end
end

-- Files an item into the category of `key` (off every other one's list),
-- or with a built-in key takes it off every own category's list.
function M:FileItem(itemID, key)
	if type(itemID) ~= "number" then return false end
	for _, cat in ipairs(self:CategoryList()) do
		if type(cat.items) == "table" then cat.items[itemID] = nil end
	end
	local cat = self:OwnCategory(key)
	if cat then
		cat.items[itemID] = true
		cat.ignore[itemID] = nil
	end
	self:CategoriesChanged()
	return true
end

-- Leaves an item out of a category's search.
function M:IgnoreItem(cat, itemID)
	if not (cat and type(itemID) == "number") then return end
	cat.ignore[itemID] = true
	cat.items[itemID] = nil
	self:CategoriesChanged()
end

local function CursorItem()
	local kind, id = GetCursorInfo()
	if kind == "item" and type(id) == "number" then return id end
end

-- An item held on the cursor dropped on a section title of the
-- Categories view: filed there, and given back to its slot.
function M:DropOnTitle(window, title)
	local section = title and title.section
	if not (section and window) then return false end
	local view = window.kind == "bank" and self.db.bankView or self.db.view
	if view ~= "categories" or not self:IsSectionKey(section.key) then return false end
	local id = CursorItem()
	if not id then return false end
	self:FileItem(id, section.key)
	ClearCursor()
	return true
end

-- The section menu's own entries (Core.lua ShowSectionMenu).
function M:AddCategoryEntries(root, window, section)
	local view = window.kind == "bank" and self.db.bankView or self.db.view
	if view ~= "categories" or not self:IsSectionKey(section.key) then return end
	local cat = self:OwnCategory(section.key)
	local id = CursorItem()
	root:CreateDivider()
	if cat and id then
		root:CreateButton(L["Leave this item out"], function()
			M:IgnoreItem(cat, id)
			ClearCursor()
		end)
	end
	if cat then
		root:CreateButton(L["Edit category"], function() M:ShowCategoryEditor(section.key) end)
	end
	root:CreateButton(L["Bag categories"], function() M:ShowCategoryEditor(section.key) end)
end

---------------------------------------------------------------------------
-- Share string
---------------------------------------------------------------------------
local function IDList(set)
	local list = {}
	for id, on in pairs(set or {}) do
		if on and type(id) == "number" then list[#list + 1] = id end
	end
	table.sort(list)
	return list
end

function M:CategoryShareData()
	local data = { list = {}, order = {} }
	for _, cat in ipairs(self:CategoryList()) do
		data.list[#data.list + 1] = { id = cat.id, name = cat.name, query = cat.query, color = { cat.color[1], cat.color[2], cat.color[3] },
			items = IDList(cat.items), ignore = IDList(cat.ignore), priority = cat.priority, bags = cat.bags ~= false, bank = cat.bank ~= false }
	end
	for _, key in ipairs(self.db.categoryOrder or {}) do data.order[#data.order + 1] = key end
	return data
end

-- Replaces the own categories and the order with an imported set. Returns
-- how many categories it holds.
function M:ImportCategories(data)
	if type(data) ~= "table" or type(data.list) ~= "table" then return nil end
	local list, remap = {}, {}
	for _, entry in ipairs(data.list) do
		if type(entry) == "table" and #list < MAX_CATEGORIES then
			local cat = { id = #list + 1, name = entry.name, query = entry.query, color = entry.color, priority = entry.priority,
				bags = entry.bags ~= false, bank = entry.bank ~= false, items = {}, ignore = {} }
			for _, id in ipairs(type(entry.items) == "table" and entry.items or {}) do
				if type(id) == "number" then cat.items[id] = true end
			end
			for _, id in ipairs(type(entry.ignore) == "table" and entry.ignore or {}) do
				if type(id) == "number" then cat.ignore[id] = true end
			end
			remap["own:" .. tostring(entry.id)] = "own:" .. cat.id
			list[#list + 1] = cat
		end
	end
	local order = {}
	for _, key in ipairs(type(data.order) == "table" and data.order or {}) do
		if type(key) == "string" then
			local mapped = key:find("^own:") and remap[key] or (not key:find("^own:") and key) or nil
			if mapped then order[#order + 1] = mapped end
		end
	end
	self.db.categoryList = list
	self.db.categoryOrder = order
	self.db.customMoved = true
	self:CategoriesChanged()
	return #list
end

function M:ExportCategories()
	return E.ExportShareKind and E:ExportShareKind("bagcategories")
end

if E.RegisterShareKind then
	E:RegisterShareKind("bagcategories", {
		prefix = "!EUBC1!",
		version = 1,
		title = "Bag categories",
		build = function() return M:CategoryShareData() end,
		describe = function(data)
			local count = type(data) == "table" and type(data.list) == "table" and #data.list or 0
			return { E:Plural(count, "%d bag category and the order of the sections. Importing replaces your own categories.",
				"%d bag categories and the order of the sections. Importing replaces your own categories."):format(count) }
		end,
		apply = function(data)
			if not M.active then return end
			local count = M:ImportCategories(data)
			if count then E:Print(E:Plural(count, "Imported %d bag category.", "Imported %d bag categories."):format(count)) end
		end,
	})
end
