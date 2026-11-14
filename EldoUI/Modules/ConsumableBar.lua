-- EldoUI Consumable Bar: one button each for food, drink, a health potion, a
-- mana potion, a bandage, a healthstone, the Hearthstone, a mount and, for
-- mages, the conjured mana gem, showing the item you carry for it and how
-- many you have. You click; the button uses the item (or, for a mount from
-- the mount collection, casts that mount).
--
-- The buttons are secure action buttons. Which item each one holds is
-- chosen from your bags and set only out of combat (E:RunOutOfCombat); in
-- combat a button keeps its item. Right-click opens the picker, a small
-- window with one two-line row per item you can put on that button. The automatic pick is the highest item your level can use, or the
-- lowest one to use up old stock (conjured items first when that option is
-- on). Food and drink that give a Well Fed buff are left for you to pick
-- yourself unless you turn that off.
--
-- Item IDs are Classic values, checked against cmangos/classic-db (the
-- source of EldoUI_LootData): healthstones by item, mounts by items whose
-- use spell mounts you, buff food by use spells that also give Well Fed or
-- another buff. WoW: Forever's own foods, drinks and rations are known by
-- their use spells from the client tables.
--
-- Nothing is used for you; one click is one use.
local _, E = ...
local L = E.L

local max = math.max

local M = E:NewModule("ConsumableBar", {
	title = "Consumable Bar",
	category = "Combat",
	desc = "A small bar with your food, drink, potions, bandage, healthstone, Hearthstone and mount, with counts and cooldowns. One click uses one.",
	frames = { "EldoUI_ConsumableBar", "EldoUI_ConsumableBarHolder" },
	movers = { "EldoUI_ConsumableBar" },
	blizzard = {},
	savedKeys = { "profile.modules.ConsumableBar" },
	optionsPage = "module:ConsumableBar",
	presets = { "AlwaysAll", "Caster", "Compact", "Melee", "Standard", "Traveller", "Vertical" },
	reload = false,
	defaults = {
		enabled = false, -- a new bar on screen: the player turns it on
		food = true,
		drink = true,
		healthPotion = true,
		manaPotion = true,
		bandage = true,
		healthstone = true,
		hearth = false,
		mount = false,
		manaGem = true,       -- mages only: the conjured mana gem
		hideEmpty = true,     -- hide buttons you have nothing for
		conjuredFirst = true, -- mage food and water before bought food
		skipBuffFood = true,  -- Well Fed food only when picked
		pick = "best",        -- "best" or "lowest"
		order = "rest",       -- button order, see M.ORDERS
		buttonSize = 32,
		spacing = 4,
		vertical = false,
		showCount = true,
		masque = false,       -- Masque skins the buttons (Core/Masque.lua; after a reload)
		overrides = {},       -- category -> itemID the player picked
		mountID = nil,        -- mount collection ID the player picked
		visibility = E:VisibilityDefaults(),
	},
})
E.ConsumableBar = M

local Clean = E.Plain

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d, e, f, g, h, i, j, k, l, m = pcall(fn, ...)
	if ok then return a, b, c, d, e, f, g, h, i, j, k, l, m end
end

---------------------------------------------------------------------------
-- Item data (Classic item and spell IDs from cmangos/classic-db)
---------------------------------------------------------------------------
-- Every healthstone size, plain and from Improved Healthstone (same list as
-- Reminders). Each size has its own use spell name, so they go by item.
local HEALTHSTONES = { 5512, 19004, 19005, 5511, 19006, 19007, 5509, 19008, 19009, 5510, 19010, 19011, 9421, 19012, 19013 }

-- Items whose use spell mounts you (aura "mounted"), without the
-- deprecated, test and GM-only entries of the database.
local MOUNT_ITEMS = {
	1041, 1132, 1133, 1134, 2411, 2413, 2414, 2415, 5655, 5656, 5663, 5665, 5668, 5864, 5872, 5873, 5874, 5875,
	8563, 8583, 8586, 8588, 8589, 8590, 8591, 8592, 8595, 8627, 8628, 8629, 8630, 8631, 8632, 8633,
	12302, 12303, 12325, 12326, 12327, 12330, 12351, 12353, 12354, 13086, 13317, 13321, 13322, 13323, 13324,
	13325, 13326, 13327, 13328, 13329, 13331, 13332, 13333, 13334, 13335, 15277, 15290, 15292, 15293,
	16338, 16339, 16343, 16344, 18241, 18242, 18243, 18244, 18245, 18246, 18247, 18248,
	18766, 18767, 18768, 18772, 18773, 18774, 18776, 18777, 18778, 18785, 18786, 18787, 18788, 18789, 18790,
	18791, 18793, 18794, 18795, 18796, 18797, 18798, 18902, 19029, 19030, 19872, 19902, 20221, 21044,
	21218, 21321, 21323, 21324, 23193, 23720,
}
-- The mage's conjured mana gems, smallest to largest: Mana Agate, Mana
-- Jade, Mana Citrine, Mana Ruby. Their use spell shares the name of the
-- mana potions' (Restore Mana), so they go by item.
local MANA_GEMS = { 5514, 5513, 8007, 8008 }
M.MANA_GEMS = MANA_GEMS

-- The mage's conjured food and water, by item so every game language
-- reads them (client tables of build 1.60.1.70862): Muffin, Bread, Rye,
-- Pumpernickel, Sourdough, Sweet Roll and Cinnamon Roll, then Water,
-- Fresh, Purified, Spring, Mineral, Sparkling and Crystal Water.
local CONJURED = {}
for _, id in ipairs({ 5349, 1113, 1114, 1487, 8075, 8076, 22895, 5350, 2288, 2136, 3772, 8077, 8078, 8079 }) do
	CONJURED[id] = true
end
M.CONJURED = CONJURED

-- The Qiraji battle tanks work only in Ahn'Qiraj: never the automatic pick
-- over a mount that works everywhere.
local ZONE_MOUNTS = {}
for _, itemID in ipairs({ 21218, 21321, 21323, 21324 }) do ZONE_MOUNTS[itemID] = true end

-- Use spells of food that also gives a buff: Well Fed (5004, 5005, 5006,
-- 5007, 10256, 24800, 24869) or a stat or regeneration buff (18229-18234,
-- 22731, 25660). Plain food uses other "Food" spells (433, 434, 1127 ...).
local BUFF_FOOD_SPELLS = {
	[5004] = true, [5005] = true, [5006] = true, [5007] = true, [10256] = true, [24800] = true, [24869] = true,
	[18229] = true, [18230] = true, [18231] = true, [18232] = true, [18233] = true, [18234] = true,
	[22731] = true, [25660] = true,
	-- WoW: Forever's cooked foods: a "Food" spell that gives a new Well Fed.
	[1225769] = true, [1225771] = true, [1225772] = true, [1225774] = true,
}
M.BUFF_FOOD_SPELLS = BUFF_FOOD_SPELLS

-- Use spells named after the item, not "Food" or "Drink", from the client
-- tables of build 1.60.1.70862. Rations and biscuits restore health and
-- mana (both buttons): manna biscuits, Essence Mango, the battleground and
-- the Darkspear Islands rations.
local RATION_SPELLS = {
	[18071] = true, [23692] = true, [1226814] = true, [24384] = true,
	[23540] = true, [23541] = true, [23542] = true, [24409] = true, [24410] = true, [24411] = true,
	[1290859] = true, [1290860] = true, [1290861] = true,
}
-- WoW: Forever's Nutritious foods and drinks: they also give Well Fed.
local NUTRITIOUS_FOOD_SPELLS = {
	[1248377] = true, [1248378] = true, [1248379] = true, [1248380] = true, [1248381] = true, [1248382] = true,
	[1248383] = true, [1248384] = true, [1248386] = true, [1248387] = true, [1248388] = true, [1248389] = true,
	[1248390] = true, [1248391] = true, [1248392] = true, [1248393] = true, [1248394] = true, [1248395] = true,
	[1248396] = true, [1248397] = true, [1248398] = true, [1248399] = true, [1248400] = true, [1248401] = true,
	[1248687] = true, [1249500] = true, [1249501] = true, [1249502] = true, [1249503] = true, [1249504] = true,
	[1249505] = true, [1249506] = true, [1249507] = true, [1249508] = true, [1249509] = true, [1249510] = true,
	[1249511] = true, [1249512] = true, [1249513] = true, [1249514] = true, [1249515] = true, [1249516] = true,
	[1249522] = true, [1294006] = true, [1302066] = true, [1319311] = true,
}
local NUTRITIOUS_DRINK_SPELLS = {
	[1249906] = true, [1249914] = true, [1249915] = true, [1249916] = true, [1249917] = true, [1249918] = true,
	[1249919] = true, [1249920] = true, [1249921] = true, [1249922] = true, [1249923] = true, [1249924] = true,
	[1249925] = true,
}
local USE_SPELLS = {}
for id in pairs(RATION_SPELLS) do USE_SPELLS[id] = "both" end
for id in pairs(NUTRITIOUS_FOOD_SPELLS) do USE_SPELLS[id], BUFF_FOOD_SPELLS[id] = "food", true end
for id in pairs(NUTRITIOUS_DRINK_SPELLS) do USE_SPELLS[id], BUFF_FOOD_SPELLS[id] = "drink", true end
M.USE_SPELLS = USE_SPELLS

---------------------------------------------------------------------------
-- Categories: an item belongs to one when its use spell has the same name as
-- the category's spell (every rank of Food shares the name "Food"), or when
-- the category lists its item ID (healthstones, the Hearthstone, mounts).
-- alwaysBest: the "lowest first" rule does not apply (mounts, Hearthstone).
-- class: only that class gets the button. keepShown: the button stays on
-- the bar while you carry none (a mage sees when to conjure a gem).
-- New categories go at the end: a button's place in this list is its name
-- and key binding.
---------------------------------------------------------------------------
M.CATEGORIES = {
	{ key = "food", label = "Food", spells = { 433 }, fallback = { "Food" }, icon = 133945 },
	{ key = "drink", label = "Drink", spells = { 430 }, fallback = { "Drink" }, icon = 132794 },
	{ key = "healthPotion", label = "Health potion", spells = { 441 }, fallback = { "Healing Potion" }, icon = 134830 },
	{ key = "manaPotion", label = "Mana potion", spells = { 437 }, fallback = { "Restore Mana" }, icon = 134851 },
	{ key = "bandage", label = "Bandage", spells = { 746 }, fallback = { "First Aid" }, icon = 133685 },
	{ key = "healthstone", label = "Healthstone", spells = { 6262 }, fallback = { "Healthstone" }, icon = 135230, items = HEALTHSTONES },
	{ key = "hearth", label = "Hearthstone", spells = {}, fallback = {}, icon = 134414, items = { 6948 }, alwaysBest = true },
	{ key = "mount", label = "Mount", spells = {}, fallback = {}, icon = "Interface\\Icons\\Ability_Mount_RidingHorse", items = MOUNT_ITEMS, alwaysBest = true },
	{ key = "manaGem", label = "Mana gem", spells = {}, fallback = {}, icon = "Interface\\Icons\\INV_Misc_Gem_Ruby_01", items = MANA_GEMS,
		alwaysBest = true, class = "MAGE", keepShown = true },
}
M.categoryByKey = {}
local categoryByItem = {}
for _, category in ipairs(M.CATEGORIES) do
	M.categoryByKey[category.key] = category
	for _, id in ipairs(category.items or {}) do categoryByItem[id] = category end
end

-- Button orders (keys of M.CATEGORIES). The buttons keep their names (and
-- key bindings); only their place on the bar changes.
M.ORDERS = {
	rest = { "food", "drink", "healthPotion", "manaPotion", "manaGem", "bandage", "healthstone", "hearth", "mount" },
	combat = { "healthPotion", "manaPotion", "manaGem", "healthstone", "bandage", "food", "drink", "hearth", "mount" },
	travel = { "mount", "hearth", "food", "drink", "healthPotion", "manaPotion", "manaGem", "bandage", "healthstone" },
}

-- Is the category's button for this character's class?
function M.ForClass(category)
	if not (category and category.class) then return true end
	local _, class = UnitClass("player")
	return Clean(class) == category.class
end

local spellNames -- use spell name -> category
local function CategoryOfSpell(name)
	if not spellNames then
		spellNames = {}
		for _, category in ipairs(M.CATEGORIES) do
			for _, id in ipairs(category.spells) do
				local spell = C_Spell and C_Spell.GetSpellName and Clean(Try(C_Spell.GetSpellName, id))
				if type(spell) == "string" and spell ~= "" then spellNames[spell] = category end
			end
			for _, fallback in ipairs(category.fallback) do spellNames[fallback] = spellNames[fallback] or category end
		end
	end
	return spellNames[name]
end
-- Spell names are read once.
function M.ResetSpellNames() spellNames = nil end

-- The item's use spell: name, spell ID (either may be nil).
local function ItemSpell(itemID)
	local getSpell = (C_Item and C_Item.GetItemSpell) or rawget(_G, "GetItemSpell")
	local name, spellID = Try(getSpell, itemID)
	return Clean(name), Clean(spellID)
end

function M.CategoryOfItem(itemID)
	if categoryByItem[itemID] then return categoryByItem[itemID] end
	local spell, spellID = ItemSpell(itemID)
	local listed = spellID and USE_SPELLS[spellID]
	if listed then return M.categoryByKey[listed == "drink" and "drink" or "food"] end
	if type(spell) ~= "string" then return nil end
	-- "Food & Drink" items (both) count as food.
	return CategoryOfSpell(spell)
end

-- Every button an item belongs on: rations on both Food and Drink.
local FOOD_AND_DRINK = {}
function M.CategoriesOfItem(itemID)
	local category = M.CategoryOfItem(itemID)
	if not category then return {} end
	local _, spellID = ItemSpell(itemID)
	if spellID and USE_SPELLS[spellID] == "both" then
		FOOD_AND_DRINK[1], FOOD_AND_DRINK[2] = M.categoryByKey.food, M.categoryByKey.drink
		return FOOD_AND_DRINK
	end
	return { category }
end

-- Food or drink whose use spell also gives a buff (Well Fed and the like).
function M.IsBuffFood(itemID)
	local _, spellID = ItemSpell(itemID)
	return spellID ~= nil and BUFF_FOOD_SPELLS[spellID] == true
end

local function Eats(category) return category.key == "food" or category.key == "drink" end

-- Items in the bags: itemID -> count.
local function BagItems()
	local items = {}
	local bags = E.BagCache
	for _, bag in ipairs(bags:BagIDs()) do
		for slot = 1, bags:NumSlots(bag) do
			local id = bags:ItemID(bag, slot)
			if id and not items[id] then
				local count = C_Item and C_Item.GetItemCount and Clean(Try(C_Item.GetItemCount, id)) or 1
				items[id] = count or 1
			end
		end
	end
	return items
end

local function ItemLevelReq(itemID)
	local getInfo = (C_Item and C_Item.GetItemInfo) or rawget(_G, "GetItemInfo")
	local _, _, _, itemLevel, minLevel = Try(getInfo, itemID)
	return Clean(minLevel) or 0, Clean(itemLevel) or 0
end

local function IsConjured(itemID)
	return CONJURED[itemID] == true
end

-- false only when the game says plainly that you can't use the item (a
-- mount without the riding skill); nil and secret answers count as usable.
local function Unusable(itemID)
	local isUsable = (C_Item and C_Item.IsUsableItem) or rawget(_G, "IsUsableItem")
	local usable = Clean(Try(isUsable, itemID))
	return usable == false
end

-- Score of one item for its category: higher is picked.
local function Score(db, category, itemID, minLevel, itemLevel)
	local score = minLevel * 1000 + itemLevel
	if db.pick == "lowest" and not category.alwaysBest then score = -score end
	if db.conjuredFirst and IsConjured(itemID) then score = score + 1e6 end
	if category.key == "mount" then
		if ZONE_MOUNTS[itemID] then score = score - 1e6 end
		if Unusable(itemID) then score = score - 2e6 end
	end
	return score
end

---------------------------------------------------------------------------
-- Mount collection: when the game keeps mounts in a collection instead of
-- the bags, the mount button casts a collected mount: the one you picked,
-- else a favorite, else the first by name.
---------------------------------------------------------------------------
function M:CollectedMounts()
	local list = {}
	local journal = C_MountJournal
	if not (journal and journal.GetMountIDs and journal.GetMountInfoByID) then return list end
	for _, mountID in ipairs(Try(journal.GetMountIDs) or {}) do
		local name, spellID, icon, _, _, _, isFavorite, _, _, hideOnChar, isCollected = Try(journal.GetMountInfoByID, mountID)
		name, spellID = Clean(name), Clean(spellID)
		if type(name) == "string" and spellID and Clean(isCollected) and not Clean(hideOnChar) then
			list[#list + 1] = { mountID = mountID, name = name, spell = spellID, icon = Clean(icon), favorite = Clean(isFavorite) and true or false }
		end
	end
	table.sort(list, function(a, b)
		if a.favorite ~= b.favorite then return a.favorite end
		return a.name < b.name
	end)
	return list
end

local function JournalPick(self)
	local mounts = self:CollectedMounts()
	if #mounts == 0 then return nil end
	local pick = mounts[1]
	for _, mount in ipairs(mounts) do
		if mount.mountID == self.db.mountID then pick = mount break end
	end
	return { spell = pick.spell, mountID = pick.mountID, icon = pick.icon, name = pick.name, count = 1, score = 0 }
end

-- The pick for each category: { key = { id, count, score } }, or for a
-- collection mount { spell, mountID, icon, name, count }.
function M:Choose()
	local db = self.db
	local playerLevel = UnitLevel and Clean(UnitLevel("player")) or 60
	local best = {}
	for id, count in pairs(BagItems()) do
		for _, category in ipairs(M.CategoriesOfItem(id)) do
			if not (Eats(category) and db.skipBuffFood and M.IsBuffFood(id)) then
				local minLevel, itemLevel = ItemLevelReq(id)
				if minLevel <= playerLevel then
					local score = Score(db, category, id, minLevel, itemLevel)
					local current = best[category.key]
					if not current or score > current.score or (score == current.score and count > current.count) then
						best[category.key] = { id = id, count = count, score = score }
					end
				end
			end
		end
	end
	for key, itemID in pairs(db.overrides or {}) do
		local count = C_Item and C_Item.GetItemCount and Clean(Try(C_Item.GetItemCount, itemID)) or 0
		if count and count > 0 then best[key] = { id = itemID, count = count, score = math.huge } end
	end
	-- A picked collection mount wins over a mount item; with no mount item
	-- in the bags the collection fills the button.
	if db.mount and (db.mountID or not best.mount) and not (db.overrides or {}).mount then
		best.mount = JournalPick(self) or best.mount
	end
	return best
end

-- Every item you carry for one category (for the right-click list).
function M:Candidates(key)
	local list = {}
	for id, count in pairs(BagItems()) do
		for _, category in ipairs(M.CategoriesOfItem(id)) do
			if category.key == key then
				list[#list + 1] = { id = id, count = count, buff = Eats(category) and M.IsBuffFood(id) or nil }
			end
		end
	end
	table.sort(list, function(a, b) return a.id < b.id end)
	return list
end

---------------------------------------------------------------------------
-- The bar
---------------------------------------------------------------------------
local function ItemIcon(itemID)
	local icon = C_Item and C_Item.GetItemIconByID and Clean(Try(C_Item.GetItemIconByID, itemID))
	return icon or 134400
end

local function ItemName(itemID)
	return C_Item and C_Item.GetItemNameByID and Clean(Try(C_Item.GetItemNameByID, itemID)) or L["Item %s"]:format(itemID)
end

---------------------------------------------------------------------------
-- The picker (right-click a button): a small window with one two-line row
-- per choice (DESIGN.md §0a rule 5). The item's icon in its quality edge,
-- the name in its quality color, a "Picked" mark on the one the button
-- holds, a muted line with how many you carry. Items you carry none of (a
-- picked item that ran out, a mana gem you have not conjured) are dimmed.
-- A click on a row or its check picks it; nothing is used.
---------------------------------------------------------------------------
local PICKER_ROWS = 8 -- rows shown before the list scrolls
local PICKER_WIDTH = 300

local function ItemQuality(itemID)
	return C_Item and C_Item.GetItemQualityByID and Clean(Try(C_Item.GetItemQualityByID, itemID)) or nil
end

local function ItemRow(itemID, sub, picked, dimmed)
	return { kind = "item", id = itemID, icon = ItemIcon(itemID), quality = ItemQuality(itemID), name = ItemName(itemID),
		sub = sub, picked = picked, dimmed = dimmed }
end

-- The choices for one button, in the picker's order: the automatic pick,
-- the items you carry, the ones you carry none of, collected mounts.
function M:PickerItems(key)
	local db = self.db
	local category = self.categoryByKey[key]
	local override = db.overrides[key]
	local manual = override ~= nil or (key == "mount" and db.mountID ~= nil)
	local how = (category.alwaysBest or db.pick ~= "lowest") and L["The best one your level can use"] or L["The lowest one first"]
	local list = { { kind = "auto", icon = category.icon, name = L["Automatic pick"], sub = how, picked = not manual } }
	local carried = {}
	for _, item in ipairs(self:Candidates(key)) do
		carried[item.id] = true
		local sub = item.buff and L["%d in your bags, buff food"]:format(item.count) or L["%d in your bags"]:format(item.count)
		list[#list + 1] = ItemRow(item.id, sub, override == item.id)
	end
	local missing = {}
	if override and not carried[override] then missing[#missing + 1] = override end
	if key == "manaGem" then
		local level = UnitLevel and Clean(UnitLevel("player")) or 60
		for _, id in ipairs(MANA_GEMS) do
			if not carried[id] and id ~= override and ItemLevelReq(id) <= level then missing[#missing + 1] = id end
		end
	end
	for _, id in ipairs(missing) do
		list[#list + 1] = ItemRow(id, L["None in your bags"], override == id, true)
	end
	if key == "mount" then
		for _, mount in ipairs(self:CollectedMounts()) do
			list[#list + 1] = { kind = "mount", mountID = mount.mountID, icon = mount.icon, name = mount.name,
				sub = L["From your collection"], picked = override == nil and db.mountID == mount.mountID }
		end
	end
	return list
end

-- Put one choice of the picker on its button.
function M:PickChoice(key, item)
	local db = self.db
	if item.kind == "auto" then
		db.overrides[key] = nil
		if key == "mount" then db.mountID = nil end
	elseif item.kind == "mount" then
		db.overrides.mount = nil
		db.mountID = item.mountID
	else
		db.overrides[key] = item.id
		if key == "mount" then db.mountID = nil end
	end
	self:Update()
end

local function PickerRow(row, item)
	row:SetRow({ icon = item.icon, quality = item.quality, name = item.name, sub = item.sub, dimmed = item.dimmed,
		status = item.picked and "good" or nil, statusText = item.picked and L["Picked"] or nil, hide = { pick = item.picked } })
end

function M:Picker()
	if self.picker then return self.picker end
	local Kit = E.UIKit
	local win = Kit.CreateToolWindow("EldoUI_ConsumablePicker", { width = PICKER_WIDTH, height = 200, strata = "DIALOG",
		resizable = false, movable = false, dialog = false })
	local function Pick(item)
		if not (item and win.key) then return end
		M:PickChoice(win.key, item)
		win:Close()
	end
	win.list = Kit.CreateList(win.content, Kit.ListRow2Template({
		row = { actions = { { key = "pick", art = "check", tipTitle = L["Pick"], tip = L["The button holds this one from now on."],
			onClick = function(item) Pick(item) end } } },
		create = function(row) row:SetScript("OnClick", function(clicked) Pick(clicked.item) end) end,
		update = PickerRow,
	}))
	win.list:SetAllPoints(win.content)
	self.picker = win
	return win
end

-- Fill the picker for a button; the height follows the rows.
function M:FillPicker()
	local win = self.picker
	if not (win and win.key) then return end
	local items = self:PickerItems(win.key)
	local Kit = E.UIKit
	local rows = math.min(#items, PICKER_ROWS)
	win:SetHeight(Kit.TOOL_HEADER + 2 * Kit.TOOL_PAD + rows * Kit.TwoLineRowHeight())
	win.list:SetData(items)
end

function M:TogglePicker(button)
	local win = self:Picker()
	if win:IsShown() and win.key == button.key and win.owner == button then
		win:Close()
		return
	end
	win.key, win.owner = button.key, button
	win:SetTitle(L[self.categoryByKey[button.key].label])
	self:FillPicker()
	-- Above the bar, or below it when the bar sits in the top half.
	win:ClearAllPoints()
	local _, y = button:GetCenter()
	local _, height = UIParent:GetSize()
	if y and height and y > height / 2 then
		win:SetPoint("TOP", button, "BOTTOM", 0, -6)
	else
		win:SetPoint("BOTTOM", button, "TOP", 0, 6)
	end
	win:Open()
end

local function ShowTooltip(btn)
	local category = M.categoryByKey[btn.key]
	GameTooltip:SetOwner(btn, "ANCHOR_TOP")
	if btn.itemID and GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(btn.itemID)
	elseif btn.spellID and GameTooltip.SetSpellByID then
		GameTooltip:SetSpellByID(btn.spellID)
	else
		E.UIKit.TipTitle(GameTooltip, L[category.label])
		E.UIKit.TipText(GameTooltip, L["You carry none."])
		if btn.key == "manaGem" then E.UIKit.TipText(GameTooltip, L["Conjure a mana gem to fill this button."]) end
	end
	if (btn.key == "food" or btn.key == "drink") and M.db.skipBuffFood then
		E.UIKit.TipText(GameTooltip, L["Buff food and drink are used only when you pick them."])
	end
	E:TooltipHint(GameTooltip, { L["Right-click"], L["pick an item"] })
	GameTooltip:Show()
end

-- The Masque group of the buttons (a fixed English name: Masque keeps its
-- skin settings under it).
local MASQUE_GROUP = "Consumable Bar"

function M:CreateButton(category, index)
	local button = CreateFrame("Button", "EldoUI_ConsumableButton" .. index, self.bar, "SecureActionButtonTemplate")
	button.key = category.key
	-- Left button only ("type1"); right-click opens the picker in PostClick
	-- and never uses an item. The left button takes the press and the
	-- release, so the item is used on whichever one the game's "cast on key
	-- press" setting asks for, by click and by key. The right button takes
	-- the release only, so the picker opens once per click.
	button:RegisterForClicks("LeftButtonUp", "LeftButtonDown", "RightButtonUp")
	button:SetAttribute("type", nil)
	button:SetAttribute("type1", "item")
	E:SetTemplate(button)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	button.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(button.icon)
	button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.cooldown:SetAllPoints(button.icon)
	button.count = E:CreateText(button, E.tokens.size.small, "RIGHT")
	button.count:SetPoint("BOTTOMRIGHT", -2, 2)
	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints(button.icon)
	local r, g, b = unpack(E.media.accentColor)
	highlight:SetColorTexture(r, g, b, 0.2)
	button:HookScript("PostClick", function(btn, mouse, down) if mouse == "RightButton" and not down then M:TogglePicker(btn) end end)
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	if self.db.masque then
		E:MasqueButton(MASQUE_GROUP, button, { Icon = button.icon, Cooldown = button.cooldown, Count = button.count, Highlight = highlight }, "Item")
	end
	return button
end

function M:BuildBar()
	if self.bar then return end
	-- The holder carries the visibility rule: a secure state driver
	-- for the hard rules (mounted, vehicle, instance ...) and the fade. The
	-- bar inside shows and hides itself by how many buttons it has.
	local holder = CreateFrame("Frame", "EldoUI_ConsumableBarHolder", UIParent, "SecureHandlerStateTemplate")
	holder:SetAllPoints(UIParent)
	holder:SetFrameStrata("LOW")
	self.holder = holder
	local bar = CreateFrame("Frame", "EldoUI_ConsumableBar", holder, "SecureHandlerStateTemplate")
	bar:SetSize(200, 36)
	bar:SetFrameStrata("LOW")
	self.bar = bar
	self.buttons = {}
	for index, category in ipairs(self.CATEGORIES) do
		self.buttons[index] = self:CreateButton(category, index)
	end
	E:CreateMover(bar, "EldoUI_ConsumableBar", "Consumable Bar", { "BOTTOM", "UIParent", "BOTTOM", 330, 240 })
end

-- True while hidden buttons are kept invisible (/eui keys hidden invisible):
-- then the Show rule only fades the bar and never hides it, so the key set's
-- keys on these buttons work whatever the rule says.
local function KeptInvisible()
	return E.HiddenButtonsMode and E:HiddenButtonsMode() == "invisible" or false
end

function M:UpdateVisibility()
	if not self.holder then return end
	local secure = not KeptInvisible()
	-- A new profile brings a new block: attach that one instead.
	if self.visibilityBlock ~= self.db.visibility or self.visibilitySecure ~= secure then E:DetachVisibility(self.holder) end
	if E:IsVisibilityAttached(self.holder) then
		E:UpdateVisibility(self.holder)
	else
		self.visibilityBlock = self.db.visibility
		self.visibilitySecure = secure
		E:AttachVisibility(self.holder, self.db.visibility, {
			watch = self.bar,
			secure = secure,
			forceShow = function() return E.IsMoveMode and E:IsMoveMode() end,
		})
	end
end

-- Kept invisible, a faded-out bar takes no clicks in a fight: its buttons
-- stop taking the mouse as the fight starts (still allowed then) and take
-- it again after.
function M:FightMouse(fight)
	if not (self.holder and self.buttons and KeptInvisible()) then return end
	local on = not fight or self.holder:GetAlpha() > 0.01
	for _, button in ipairs(self.buttons) do button:EnableMouse(on) end
end

-- What the secure attributes depend on: the chosen item or spell per button.
local function Signature(chosen)
	local parts = {}
	for _, button in ipairs(M.buttons or {}) do
		local pick = chosen[button.key]
		parts[#parts + 1] = pick and (pick.spell and ("s" .. tostring(pick.spell)) or ("i" .. tostring(pick.id))) or "-"
	end
	return table.concat(parts, ",")
end

-- Item, count and cooldown on every button; attributes and layout out of combat.
-- fromEvent: a bag or item event, which queues the secure update only when the
-- chosen items changed (settings changes always re-apply the layout).
function M:Update(fromEvent)
	if not (self.active and self.bar) then return end
	local chosen = self:Choose()
	self.chosen = chosen
	for _, button in ipairs(self.buttons) do
		local pick = chosen[button.key]
		button.itemID = pick and pick.id or nil
		button.spellID = pick and pick.spell or nil
		local category = self.categoryByKey[button.key]
		local icon = pick and (pick.id and ItemIcon(pick.id) or pick.icon) or category.icon
		button.icon:SetTexture(icon or category.icon)
		button.icon:SetDesaturated(not pick)
		button.icon:SetAlpha(pick and 1 or 0.4)
		button.count:SetText((self.db.showCount and pick and pick.count > 1) and pick.count or "")
		self:UpdateCooldown(button)
	end
	if self.picker and self.picker:IsShown() then self:FillPicker() end
	if not (fromEvent and Signature(chosen) == self.appliedSignature) then
		E:RunOutOfCombat(function() M:ApplySecure() end, "ConsumableBar:ApplySecure")
	end
	self:UpdateVisibility()
end

-- The cooldown swipe as the game describes it, read through the combat
-- kit's one cooldown source (K.Cooldowns in Modules/CombatHUD/Kit.lua),
-- which also says when the game reports a change. The global cooldown
-- alone draws no swipe: the game's own flag says when only it runs.
local function Cooldowns()
	return E.CombatKit and E.CombatKit.Cooldowns
end

function M:UpdateCooldown(button)
	local source = Cooldowns()
	if not source then
		button.cooldown:Clear()
	elseif button.itemID then
		source.DrawItem(button.cooldown, button.itemID, { hideGCD = true })
	elseif button.spellID then
		source.DrawSpell(button.cooldown, button.spellID, { hideGCD = true })
	else
		button.cooldown:Clear()
	end
end

function M:UpdateCooldowns()
	for _, button in ipairs(self.buttons or {}) do self:UpdateCooldown(button) end
end

-- The buttons in the chosen order.
function M:OrderedButtons()
	local byKey = {}
	for _, button in ipairs(self.buttons) do byKey[button.key] = button end
	local list = {}
	for _, key in ipairs(self.ORDERS[self.db.order] or self.ORDERS.rest) do
		if byKey[key] then list[#list + 1] = byKey[key] byKey[key] = nil end
	end
	for _, button in ipairs(self.buttons) do
		if byKey[button.key] then list[#list + 1] = button end
	end
	return list
end

local shapeRequest = 0
local function ShapeSame(a, b) return not E:IsSecret(a) and not E:IsSecret(b) and rawequal(a, b) end
function M:ApplySecure()
	shapeRequest = shapeRequest + 1
	local request, bar, root, profile = shapeRequest, self.bar, E.db, E.profileName
	local db, chosen = self.db, self.chosen or {}
	local size, spacing = db.buttonSize, db.spacing
	local shown = 0
	for _, button in ipairs(self:OrderedButtons()) do
		local pick = chosen[button.key]
		if pick and pick.spell then
			button:SetAttribute("type1", "spell")
			button:SetAttribute("spell", pick.spell)
			button:SetAttribute("item", nil)
		else
			button:SetAttribute("type1", "item")
			button:SetAttribute("spell", nil)
			button:SetAttribute("item", pick and ("item:" .. pick.id) or nil)
		end
		local category = self.categoryByKey[button.key]
		local visible = db[button.key] and M.ForClass(category) and (pick or not db.hideEmpty or category.keepShown)
		button:ClearAllPoints()
		if visible then
			button:SetSize(size, size)
			if db.vertical then
				button:SetPoint("TOP", self.bar, "TOP", 0, -shown * (size + spacing))
			else
				button:SetPoint("LEFT", self.bar, "LEFT", shown * (size + spacing), 0)
			end
			button:Show()
			shown = shown + 1
		else
			button:Hide()
		end
	end
	-- Masque fits its skin to the button size it finds when it skins.
	if db.masque then E:MasqueReSkin(MASQUE_GROUP) end
	local length = max(1, shown) * (size + spacing) - spacing
	if db.vertical then self.bar:SetSize(size, length) else self.bar:SetSize(length, size) end
	self.bar:SetShown(shown > 0 or (E.IsMoveMode and E:IsMoveMode()))
	self.shownButtons = shown
	self.appliedSignature = Signature(chosen)
	if not E:IsSecret(self.active) and self.active and E.movers.EldoUI_ConsumableBar then E:ApplyMover("EldoUI_ConsumableBar") end
	if request == shapeRequest and ShapeSame(self, M) and ShapeSame(self.bar, bar) and ShapeSame(self.db, db) and ShapeSame(E.db, root)
		and ShapeSame(E.profileName, profile) and not E:IsSecret(self.active) and self.active and E.RefreshWideConsumableLayout then E:RefreshWideConsumableLayout(self) end
end

---------------------------------------------------------------------------
-- Events and lifecycle
---------------------------------------------------------------------------
-- GET_ITEM_INFO_RECEIVED fires once per item the client loads (hundreds at
-- login or while browsing item lists): one bag scan per burst, not per item.
local ITEM_INFO_DELAY = 0.25
local itemInfoPending = false
local function ItemInfoUpdate()
	itemInfoPending = false
	if M.active then M:Update(true) end
end

local COOLDOWN_KEY = "ConsumableBar"
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	if not M.active then return end
	if event == "PLAYER_REGEN_DISABLED" then
		M:FightMouse(true)
		return
	elseif event == "PLAYER_REGEN_ENABLED" then
		M:FightMouse(false)
	end
	if event == "GET_ITEM_INFO_RECEIVED" then
		if itemInfoPending then return end
		itemInfoPending = true
		C_Timer.After(ITEM_INFO_DELAY, ItemInfoUpdate)
	else
		M:Update(true)
	end
end)

function M:OnEnable()
	self:BuildBar()
	for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD",
		"GET_ITEM_INFO_RECEIVED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "NEW_MOUNT_ADDED", "SKILL_LINES_CHANGED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	local source = Cooldowns()
	if source then
		source.Subscribe(COOLDOWN_KEY, function(changes)
			if M.active and (changes.items or changes.spells) then M:UpdateCooldowns() end
		end)
	end
	self:Update()
end

function M:OnDisable()
	shapeRequest = shapeRequest + 1
	local request, bar, db, root, profile = shapeRequest, self.bar, self.db, E.db, E.profileName
	events:UnregisterAllEvents()
	local source = Cooldowns()
	if source then source.Unsubscribe(COOLDOWN_KEY) end
	if self.holder then E:DetachVisibility(self.holder) end
	self.visibilityBlock = nil
	E:RunOutOfCombat(function()
		if M.bar then M.bar:Hide() end
		if request == shapeRequest and ShapeSame(M.bar, bar) and ShapeSame(M.db, db) and ShapeSame(E.db, root) and ShapeSame(E.profileName, profile)
			and not E:IsSecret(M.active) and not M.active and E.RefreshWideConsumableLayout then E:RefreshWideConsumableLayout(M) end
	end)
end

function M:OnProfileChanged()
	if self.active then self:Update() end
end

---------------------------------------------------------------------------
-- Options and styles
---------------------------------------------------------------------------
local function Off(key) return function() return not M.db[key] end end

M.options = {
	{ type = "description", label = "Each button holds an item of its kind from your bags; click to use, right-click to pick one. Buttons change only out of combat." },
	{ type = "header", label = "Buttons", fold = true },
	{ type = "toggle", key = "food", label = "Food", desc = "A button for food." },
	{ type = "toggle", key = "drink", label = "Drink", desc = "A button for drinks." },
	{ type = "toggle", key = "healthPotion", label = "Health potion", desc = "A button for healing potions." },
	{ type = "toggle", key = "manaPotion", label = "Mana potion", desc = "A button for mana potions." },
	{ type = "toggle", key = "bandage", label = "Bandage", desc = "A button for bandages." },
	{ type = "toggle", key = "healthstone", label = "Healthstone", desc = "A button for healthstones." },
	{ type = "toggle", key = "hearth", label = "Hearthstone", desc = "A button for your Hearthstone, with its cooldown." },
	{ type = "toggle", key = "mount", label = "Mount", desc = "A button for a mount: the best mount item in your bags, or a mount from your collection (right-click picks which)." },
	{ type = "toggle", key = "manaGem", label = "Mana gem", desc = "A button for your conjured mana gem, with its cooldown. It stays on the bar while you carry none, so you see when to conjure one.",
		requires = function() return M.ForClass(M.categoryByKey.manaGem) end },
	{ type = "toggle", key = "hideEmpty", label = "Hide empty buttons", desc = "Hide a button while you carry nothing for it (the mana gem stays)." },
	{ type = "select", key = "order", label = "Button order", values = {
		rest = "Food and drink first",
		combat = "Potions and healthstone first",
		travel = "Mount and Hearthstone first",
	}, desc = "Where each button sits on the bar. Key bindings stay with their button." },
	{ type = "header", label = "Which item", fold = true },
	{ type = "select", key = "pick", label = "Pick", values = {
		best = "Best for your level",
		lowest = "Lowest first (use up old stock)",
	}, desc = "Which item a button holds when you have several: the highest one your level can use, or the lowest one so old food and potions get used up. Mounts and the Hearthstone always take the best." },
	{ type = "toggle", key = "conjuredFirst", label = "Conjured first", desc = "Pick conjured food and water before bought food." },
	{ type = "toggle", key = "skipBuffFood", label = "Keep buff food", desc = "Food and drink that give Well Fed or another buff are left out of the automatic pick, so they are not used up as plain food or drink. Right-click the button to pick one.", hidden = function() return not (M.db.food or M.db.drink) end },
	{ type = "execute", label = "Forget picked items", confirm = true, desc = "Every button goes back to the automatic pick, the mount button too.", func = function()
		wipe(M.db.overrides)
		M.db.mountID = nil
		M:Update()
	end },
	{ type = "header", label = "Look", fold = true },
	{ type = "range", key = "buttonSize", label = "Button size", min = 20, max = 48, step = 1, desc = "Size of each button." },
	{ type = "range", key = "spacing", label = "Spacing", min = 0, max = 12, step = 1, desc = "Space between buttons." },
	{ type = "toggle", key = "vertical", label = "Vertical", desc = "Stack the buttons top to bottom." },
	{ type = "toggle", key = "showCount", label = "Counts", desc = "Show how many you carry." },
	{ type = "toggle", key = "masque", label = "Use Masque", reload = true, desc = E.MASQUE_OPTION_DESC,
		requires = function() return E:Masque() ~= nil end },
}
for _, row in ipairs(E:VisibilityOptions("visibility", { db = function() return M.db end, secure = true })) do
	table.insert(M.options, row)
end

E:RegisterStyles("ConsumableBar", {
	{ key = "Standard", title = "Standard", desc = "Food, drink, potions, bandage and healthstone, empty ones hidden, 32 px.",
		settings = { food = true, drink = true, healthPotion = true, manaPotion = true, bandage = true, healthstone = true, hearth = false, mount = false, hideEmpty = true, buttonSize = 32, vertical = false, order = "rest" } },
	{ key = "Caster", title = "Caster", desc = "Drink, mana potion, health potion and healthstone, potions first.",
		settings = { food = false, drink = true, manaPotion = true, healthPotion = true, bandage = false, healthstone = true, hearth = false, mount = false, order = "combat" } },
	{ key = "Melee", title = "Melee", desc = "Food, health potion, bandage and healthstone, potions first.",
		settings = { food = true, drink = false, manaPotion = false, healthPotion = true, bandage = true, healthstone = true, hearth = false, mount = false, order = "combat" } },
	{ key = "Traveller", title = "Traveler", desc = "Mount and Hearthstone first, then food, drink and bandage.",
		settings = { food = true, drink = true, manaPotion = false, healthPotion = false, bandage = true, healthstone = false, hearth = true, mount = true, order = "travel" } },
	{ key = "Compact", title = "Compact", desc = "Small 24 px buttons close together.",
		settings = { buttonSize = 24, spacing = 2 } },
	{ key = "Vertical", title = "Vertical", desc = "A column at the side of the screen.",
		settings = { vertical = true, buttonSize = 30 } },
	{ key = "AlwaysAll", title = "Always all", desc = "Every button stays on screen, grayed out when empty, the Hearthstone and mount too.",
		settings = { hideEmpty = false, hearth = true, mount = true } },
})
