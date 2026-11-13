-- EldoUI Profession Planner: pinned recipes and one shopping list,
-- recipe cooldowns across your characters, and a leveling plan.
--
-- Pin a recipe (profession window, Loot Guide > Crafting, Alts >
-- Professions, or /eui plan pin <recipeID>) with a number of crafts. The
-- Shopping List tracker then shows every reagent as "have/need" from your
-- bags, bank and (optionally) your other characters, the smelt and craft
-- steps of reagents you can make yourself, and which recipe cooldowns are
-- ready. At the auction house "Send to Shopping" turns what is missing into
-- an EldoUI Auction shopping list: it only fills the list, the player still
-- searches and buys.
--
-- The leveling plan picks, for each skill point, the cheapest recipe that
-- is still orange or yellow, using EldoUI's saved auction and vendor
-- prices. Colors come from the game's profession window where you opened
-- it, else from Classic's usual steps (an estimate, said so on the page).
-- Expected crafts per point follow the public Classic rule (orange: every
-- craft, yellow: (gray - skill) / (gray - yellow)), also shown as an
-- estimate.
--
-- Nothing here crafts, buys, searches or posts for the player.
--
-- Saved data:
--   E:GetPrivate("ProfessionPlanner").pins = { { id = recipeID, qty = crafts, at = time } }
--   E:GetGlobal("ProfessionRecipes")[recipeID] = { name, result, count, skill, rank, icon,
--       reagents = { { id, count } } }   (what the profession window showed)
--
-- Public: E.ProfessionPlanner (this module): Pin, Unpin, SetQuantity, IsPinned,
-- Pins, Recipe, Have, Needs, Missing, Cooldowns, Plan, SendToShopping.
local _, E = ...
local L = E.L

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local M = E:NewModule("ProfessionPlanner", {
	title = "Profession Planner",
	category = "Items & Economy",
	desc = "Pin recipes for one shopping list with what you have on every character, recipe cooldowns across alts and a cheapest leveling plan from your saved prices.",
	conflicts = { "ProfessionShoppingList" },
	frames = { "EldoUI_ShoppingList" },
	movers = { "EldoUI_ShoppingList" },
	savedKeys = { "profile.modules.ProfessionPlanner", "EldoUIDB.private.ProfessionPlanner", "EldoUIDB.global.ProfessionRecipes" },
	optionsPage = "module:ProfessionPlanner",
	presets = { "Compact", "Detailed", "Checklist", "MinimalText", "ForeverBronze", "Large" },
	defaults = {
		tracker = true,        -- the Shopping List tracker (shows once something is pinned)
		countAlts = true,      -- count reagents your other characters hold
		altScope = "realm",    -- realm | faction | account
		includeBank = true,    -- count bank (and your alts' bank) as had
		subReagents = true,    -- expand reagents you can craft into their own reagents
		hideDone = false,      -- hide reagents you already have enough of
		cooldowns = true,      -- recipe cooldown lines across your characters
		priceSource = "lowest", -- auction | vendor | lowest
		blizzardPin = true,    -- the Pin button on the profession window
		otherPins = true,      -- pin from the Loot Guide and the Alts window
		planKnownOnly = false, -- the leveling plan uses only recipes you know
		fontSize = 12,
		width = 250,
		icons = true,
		checks = false,        -- a check mark instead of the count when a reagent is done
		backdrop = "transparent", -- panel | transparent | none
		edge = true,           -- the art style's frame line on the tracker
		maxLines = 14,
		-- The tracker steps aside in combat (its spot is shared with the
		-- target's combat text, which shows only then).
		visibility = E:VisibilityDefaults({ show = "nocombat" }),
	},
})
E.ProfessionPlanner = M


local Clean = E.Plain

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d = pcall(fn, ...)
	if ok then return a, b, c, d end
end

M.QUANTITIES = { 1, 5, 10, 20 }

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
function M:Store()
	local store = E:GetPrivate("ProfessionPlanner") or {}
	if type(store.pins) ~= "table" then store.pins = {} end
	return store
end

function M:RecipeCache()
	local cache = E:GetGlobal("ProfessionRecipes")
	return type(cache) == "table" and cache or {}
end

function M:Pins()
	return self:Store().pins
end

function M:IsPinned(recipeID)
	recipeID = tonumber(recipeID)
	for index, pin in ipairs(self:Pins()) do
		if pin.id == recipeID then return pin, index end
	end
end

local function Changed()
	M.version = (M.version or 0) + 1
	if M.Redraw then M:Redraw() end
end
M.Changed = Changed

function M:Pin(recipeID, qty, info)
	recipeID = tonumber(recipeID)
	if not recipeID then return false end
	qty = max(1, floor(tonumber(qty) or 1))
	if type(info) == "table" then self:Remember(recipeID, info) end
	local pin = self:IsPinned(recipeID)
	if pin then
		pin.qty = qty
	else
		table.insert(self:Pins(), { id = recipeID, qty = qty, at = time() })
	end
	Changed()
	return true
end

function M:Unpin(recipeID)
	local _, index = self:IsPinned(recipeID)
	if not index then return false end
	table.remove(self:Pins(), index)
	Changed()
	return true
end

function M:SetQuantity(recipeID, qty)
	local pin = self:IsPinned(recipeID)
	if not pin then return false end
	pin.qty = max(1, floor(tonumber(qty) or 1))
	Changed()
	return true
end

function M:ClearPins()
	wipe(self:Pins())
	Changed()
end

-- Unpin all, after a question: the list can't be brought back.
function M:ConfirmClearPins()
	local count = #self:Pins()
	if count == 0 then
		E:Print(L["The shopping list is already empty."])
		return
	end
	E:ShowConfirm({ title = L["Unpin all"], danger = true, accept = L["Unpin all"],
		text = E:Plural(count, "Take %d recipe off the shopping list?", "Take all %d recipes off the shopping list?"):format(count),
		onAccept = function()
			M:ClearPins()
			E:Print(L["Shopping list cleared."])
		end })
end

---------------------------------------------------------------------------
-- Recipes: the profession window's own data first, then EldoUI_LootData
---------------------------------------------------------------------------
function M:Remember(recipeID, info)
	local cache = self:RecipeCache()
	local entry = cache[recipeID] or {}
	for key, value in pairs(info) do entry[key] = value end
	cache[recipeID] = entry
	return entry
end

-- What the open profession window says about a recipe (read-only).
function M:ReadSchematic(recipeID)
	local T = C_TradeSkillUI
	if not (T and T.GetRecipeSchematic) then return nil end
	local schematic = Try(T.GetRecipeSchematic, recipeID, false)
	if type(schematic) ~= "table" then return nil end
	local entry = { name = Clean(schematic.name), result = tonumber(Clean(schematic.outputItemID)),
		count = tonumber(Clean(schematic.quantityMin)) or 1, icon = Clean(schematic.icon), reagents = {} }
	for _, slot in ipairs(type(schematic.reagentSlotSchematics) == "table" and schematic.reagentSlotSchematics or {}) do
		local reagent = type(slot.reagents) == "table" and slot.reagents[1]
		local itemID = reagent and tonumber(Clean(reagent.itemID))
		if itemID and Clean(slot.required) ~= false then
			entry.reagents[#entry.reagents + 1] = { id = itemID, count = tonumber(Clean(slot.quantityRequired)) or 1 }
		end
	end
	if T.GetProfessionInfoByRecipeID then
		local info = Try(T.GetProfessionInfoByRecipeID, recipeID)
		if type(info) == "table" then entry.skill = tonumber(Clean(info.parentProfessionID)) or tonumber(Clean(info.professionID)) end
	end
	return entry
end

local function LootGuide()
	local LG = E.LootGuide
	return type(LG) == "table" and LG or nil
end

function M:Recipe(recipeID)
	recipeID = tonumber(recipeID)
	if not recipeID then return nil end
	local cached = self:RecipeCache()[recipeID]
	local recipe
	if type(cached) == "table" and type(cached.reagents) == "table" and #cached.reagents > 0 then
		recipe = cached
	else
		local LG = LootGuide()
		local craft = LG and LG.Craft and Try(LG.Craft, LG, recipeID)
		if type(craft) == "table" then
			recipe = { result = craft.result, count = craft.count or 1, reagents = craft.reagents or {}, skill = craft.skill, rank = craft.rank }
		elseif type(cached) == "table" then
			recipe = cached
		end
	end
	if not recipe then return nil end
	local name = recipe.name or (C_Spell and C_Spell.GetSpellName and Clean(Try(C_Spell.GetSpellName, recipeID)))
	if not name and recipe.result and recipe.result > 0 then name = self:ItemName(recipe.result) end
	return { id = recipeID, name = name or ("#" .. recipeID), result = recipe.result, count = max(1, recipe.count or 1),
		reagents = recipe.reagents or {}, skill = recipe.skill, rank = recipe.rank, icon = recipe.icon }
end

-- The recipe that makes an item, for sub-reagents (smelting, leather).
function M:RecipeFor(itemID)
	for recipeID, entry in pairs(self:RecipeCache()) do
		if type(entry) == "table" and entry.result == itemID then return self:Recipe(recipeID) end
	end
	local LG = LootGuide()
	local craft = LG and LG.CraftOf and Try(LG.CraftOf, LG, itemID)
	if type(craft) == "table" and craft.id then return self:Recipe(craft.id) end
end

function M:ItemName(itemID)
	local name = C_Item and C_Item.GetItemNameByID and Clean(Try(C_Item.GetItemNameByID, itemID))
	if not name and C_Item and C_Item.RequestLoadItemDataByID then Try(C_Item.RequestLoadItemDataByID, itemID) end
	return name
end

function M:ItemIcon(itemID)
	return C_Item and C_Item.GetItemIconByID and Clean(Try(C_Item.GetItemIconByID, itemID)) or 134400
end

---------------------------------------------------------------------------
-- What you have: this character (bags, bank), your other characters
---------------------------------------------------------------------------
local function Characters()
	local C = E.Characters
	return type(C) == "table" and C.Keys and C or nil
end

-- total, mine, { { key, name, count } } for the other characters.
function M:Have(itemID)
	local mine = C_Item and C_Item.GetItemCount and tonumber(Clean(Try(C_Item.GetItemCount, itemID, self.db.includeBank))) or 0
	local total, alts = mine, {}
	local C = Characters()
	if self.db.countAlts and C then
		for _, key in ipairs(Try(C.Keys, C, self.db.altScope) or {}) do
			if key ~= E.charKey then
				local record = C:Get(key)
				local counts = record and type(record.counts) == "table" and record.counts[itemID]
				if type(counts) == "table" then
					local n = (counts[1] or 0) + (counts[3] or 0) + (self.db.includeBank and (counts[2] or 0) or 0)
					if n > 0 then
						total = total + n
						alts[#alts + 1] = { key = key, name = record.name or key, count = n }
					end
				end
			end
		end
	end
	return total, mine, alts
end

---------------------------------------------------------------------------
-- The shopping list
---------------------------------------------------------------------------
-- Lines of one pin: { id, need, have, depth, made (sub-reagent lines) }.
-- Have counts are shared: what one pin takes is not counted again for the
-- next, so two pins that need Copper Bar ask for both.
local function AddLines(lines, recipe, crafts, used, depth, seen)
	for _, reagent in ipairs(recipe.reagents) do
		local need = reagent.count * crafts
		local total = M:Have(reagent.id)
		local free = max(0, total - (used[reagent.id] or 0))
		local have = min(free, need)
		used[reagent.id] = (used[reagent.id] or 0) + have
		local line = { id = reagent.id, need = need, have = have, depth = depth }
		lines[#lines + 1] = line
		local missing = need - have
		if missing > 0 and M.db.subReagents and depth < 2 and not seen[reagent.id] then
			local sub = M:RecipeFor(reagent.id)
			if sub and #sub.reagents > 0 then
				seen[reagent.id] = true
				line.made = sub
				line.crafts = ceil(missing / sub.count)
				AddLines(lines, sub, line.crafts, used, depth + 1, seen)
				seen[reagent.id] = nil
			end
		end
	end
end

-- { { pin, recipe, lines = { ... } } } in pin order.
function M:Needs()
	local out, used = {}, {}
	for _, pin in ipairs(self:Pins()) do
		local recipe = self:Recipe(pin.id)
		local entry = { pin = pin, recipe = recipe, lines = {} }
		if recipe then AddLines(entry.lines, recipe, pin.qty, used, 0, {}) end
		out[#out + 1] = entry
	end
	return out
end

-- Totals per item over every pin: need, have, missing (top-level and
-- sub-reagents alike; a reagent you will craft counts its own reagents).
function M:Totals()
	local totals = {}
	for _, entry in ipairs(self:Needs()) do
		for _, line in ipairs(entry.lines) do
			local t = totals[line.id] or { need = 0, have = 0 }
			totals[line.id] = t
			t.need, t.have = t.need + line.need, t.have + line.have
		end
	end
	for _, t in pairs(totals) do t.missing = max(0, t.need - t.have) end
	return totals
end

-- Items to buy: what is missing that you don't make from a pinned sub-step.
function M:Missing()
	local list = {}
	for _, entry in ipairs(self:Needs()) do
		for _, line in ipairs(entry.lines) do
			if not line.made and line.need > line.have then
				list[#list + 1] = { id = line.id, count = line.need - line.have }
			end
		end
	end
	local merged, order = {}, {}
	for _, item in ipairs(list) do
		if not merged[item.id] then
			merged[item.id] = { id = item.id, count = 0 }
			order[#order + 1] = merged[item.id]
		end
		merged[item.id].count = merged[item.id].count + item.count
	end
	return order
end

---------------------------------------------------------------------------
-- Recipe cooldowns across your characters (saved by each character's own
-- profession window)
---------------------------------------------------------------------------
function M:Cooldowns()
	local C = Characters()
	local out = {}
	if not C then return out end
	local now = C.Now and C.Now() or time()
	for _, key in ipairs(Try(C.Keys, C, self.db.altScope) or {}) do
		local record = C:Get(key)
		for recipeID, cd in pairs(record and type(record.cooldowns) == "table" and record.cooldowns or {}) do
			if type(cd) == "table" and tonumber(cd.readyAt) then
				out[#out + 1] = { key = key, who = record.name or key, class = record.class, id = recipeID,
					name = cd.name or (C_Spell and C_Spell.GetSpellName and Clean(Try(C_Spell.GetSpellName, recipeID))) or ("#" .. recipeID),
					left = max(0, cd.readyAt - now) }
			end
		end
	end
	table.sort(out, function(a, b)
		if a.left ~= b.left then return a.left < b.left end
		return a.name < b.name
	end)
	return out
end

---------------------------------------------------------------------------
-- Prices (EldoUI's own saved auction and vendor prices)
---------------------------------------------------------------------------
-- What a vendor asked for an item, as the Merchant module saved it. Read
-- through the Merchant module when it offers the call, else from its
-- saved table ("vendorBuy", item ID -> copper), read only.
function M:VendorPrice(itemID)
	local merchant = E.modules and E.modules.Merchant
	if merchant and type(merchant.VendorPrice) == "function" then
		return Clean(Try(merchant.VendorPrice, merchant, itemID))
	end
	local saved = type(EldoUIDB) == "table" and EldoUIDB.vendorBuy
	return type(saved) == "table" and saved[itemID] or nil
end

function M:Price(itemID)
	local auction = E.modules and E.modules.Auction
	local ah = auction and auction.GetPrice and tonumber(Clean(Try(auction.GetPrice, auction, itemID)))
	local vendor = tonumber(self:VendorPrice(itemID))
	if ah and ah <= 0 then ah = nil end
	if vendor and vendor <= 0 then vendor = nil end
	local source = self.db.priceSource
	if source == "auction" then return ah end
	if source == "vendor" then return vendor end
	if ah and vendor then return min(ah, vendor) end
	return ah or vendor
end

-- Cost of one craft, or nil when a reagent has no price.
function M:CraftCost(recipe)
	if not recipe then return nil end
	local cost = 0
	for _, reagent in ipairs(recipe.reagents or {}) do
		local price = self:Price(reagent.id)
		if not price then return nil end
		cost = cost + price * reagent.count
	end
	return cost
end

function M.Money(copper)
	if not copper then return L["no price"] end
	return E:FormatMoney(floor(copper + 0.5))
end

---------------------------------------------------------------------------
-- Leveling plan
---------------------------------------------------------------------------
-- Expected crafts for one skill point at `skill` (public Classic rule).
function M.ExpectedCrafts(thresholds, skill)
	if skill < thresholds.yellow then return 1 end
	if skill >= thresholds.grey then return nil end
	local span = thresholds.grey - thresholds.yellow
	if span <= 0 then return nil end
	local chance = (thresholds.grey - skill) / span
	if chance <= 0 then return nil end
	return 1 / chance
end

-- steps = { { recipe, from, to, crafts, cost (nil = no price), band, known, estimated } },
-- total = known cost, unpriced = steps without a price, gaps = { { from, to } }
-- (skill points no recipe covers).
function M:Plan(skillLine, from, to)
	local plan = { steps = {}, total = 0, unpriced = 0, gaps = {}, skill = skillLine, from = from, to = to }
	local LG = LootGuide()
	if not (LG and LG.ProfessionCrafts and LG.SkillBand) or not from or not to or to <= from then return plan end
	local crafts = Try(LG.ProfessionCrafts, LG, skillLine) or {}
	local candidates = {}
	for _, craft in ipairs(crafts) do
		local known = LG.CraftKnown and LG:CraftKnown(craft.id)
		if craft.rank and (known or not self.db.planKnownOnly) and #(craft.reagents or {}) > 0 then
			local _, estimated, thresholds = LG:SkillBand(craft, from)
			local recipe = { id = craft.id, result = craft.result, count = craft.count or 1, reagents = craft.reagents, rank = craft.rank }
			candidates[#candidates + 1] = { craft = craft, recipe = recipe, thresholds = thresholds, estimated = estimated,
				known = known, cost = self:CraftCost(recipe) }
		end
	end
	local current
	for skill = from, to - 1 do
		local best, bestScore, bestPriced
		for _, c in ipairs(candidates) do
			if skill >= c.thresholds.orange then
				local expected = M.ExpectedCrafts(c.thresholds, skill)
				if expected then
					local priced = c.cost ~= nil
					local score = priced and c.cost * expected or expected
					if not best or (priced and not bestPriced) or (priced == bestPriced and score < bestScore) then
						best, bestScore, bestPriced = c, score, priced
						best.expected = expected
					end
				end
			end
		end
		if not best then
			local gap = plan.gaps[#plan.gaps]
			if gap and gap.to == skill then gap.to = skill + 1 else plan.gaps[#plan.gaps + 1] = { from = skill, to = skill + 1 } end
			current = nil
		else
			if not current or current.candidate ~= best then
				current = { candidate = best, recipe = best.recipe, from = skill, to = skill, crafts = 0, cost = best.cost and 0 or nil,
					band = skill < best.thresholds.yellow and "orange" or "yellow", known = best.known, estimated = best.estimated }
				plan.steps[#plan.steps + 1] = current
			end
			current.to = skill + 1
			current.crafts = current.crafts + best.expected
			if current.cost then current.cost = current.cost + best.cost * best.expected end
		end
	end
	for _, step in ipairs(plan.steps) do
		step.crafts = ceil(step.crafts - 0.001)
		if step.cost then
			step.cost = step.cost and (self:CraftCost(step.recipe) or 0) * step.crafts
			plan.total = plan.total + step.cost
		else
			plan.unpriced = plan.unpriced + 1
		end
		step.candidate = nil
	end
	return plan
end

-- Pin every step of a plan with its number of crafts.
function M:PinPlan(plan)
	local count = 0
	for _, step in ipairs(plan and plan.steps or {}) do
		local recipe = step.recipe
		self:Remember(recipe.id, { result = recipe.result, count = recipe.count, reagents = recipe.reagents, rank = recipe.rank, skill = plan.skill })
		local pin = self:IsPinned(recipe.id)
		self:Pin(recipe.id, (pin and pin.qty or 0) + step.crafts)
		count = count + 1
	end
	return count
end

---------------------------------------------------------------------------
-- Send to Shopping: fill an EldoUI Auction shopping list (nothing more)
---------------------------------------------------------------------------
M.LIST_NAME = "Profession Planner"

-- The Auction module keeps the shopping lists. The list goes in through
-- its own call (SetShoppingList: one list per name, replaced) when it
-- offers one; otherwise into its saved lists the same way.
local function SetAuctionList(name, terms)
	local auction = E.modules.Auction
	if type(auction.SetShoppingList) == "function" then return auction:SetShoppingList(name, terms) end
	EldoUIDB.auction = type(EldoUIDB.auction) == "table" and EldoUIDB.auction or {}
	local saved = EldoUIDB.auction
	saved.lists = type(saved.lists) == "table" and saved.lists or {}
	for _, entry in ipairs(saved.lists) do
		if entry.name == name then
			entry.terms = terms
			return
		end
	end
	saved.lists[#saved.lists + 1] = { name = name, terms = terms }
end

function M:SendToShopping()
	if not (E.modules and E.modules.Auction) then return false, L["The Auction module is not loaded."] end
	local missing = self:Missing()
	if #missing == 0 then return false, L["Nothing is missing."] end
	local terms, waiting = {}, 0
	for _, item in ipairs(missing) do
		local name = self:ItemName(item.id)
		if name then terms[#terms + 1] = '"' .. name .. '"' else waiting = waiting + 1 end
	end
	if #terms == 0 then return false, L["Item names are still loading. Try again in a moment."] end
	SetAuctionList(self.LIST_NAME, terms)
	local text = E:Plural(#terms, "%d item is on the shopping list \"Profession Planner\".", "%d items are on the shopping list \"Profession Planner\"."):format(#terms)
	if waiting > 0 then text = text .. " " .. E:Plural(waiting, "%d name is still loading.", "%d names are still loading."):format(waiting) end
	return true, text
end

---------------------------------------------------------------------------
-- Profession window: remember pinned recipes while it is open
---------------------------------------------------------------------------
function M:ScanOpenWindow()
	local T = C_TradeSkillUI
	if not T then return end
	if (T.IsTradeSkillLinked and Try(T.IsTradeSkillLinked)) or (T.IsNPCCrafting and Try(T.IsNPCCrafting)) then return end
	local changed = false
	for _, pin in ipairs(self:Pins()) do
		local entry = self:ReadSchematic(pin.id)
		if entry and #entry.reagents > 0 then
			self:Remember(pin.id, entry)
			changed = true
		end
	end
	if changed then Changed() end
end

---------------------------------------------------------------------------
-- Tooltip: "Shopping list: 7/12" on a reagent
---------------------------------------------------------------------------
local function TooltipLine(_, _, itemID, add)
	if not (M.active and itemID) or #M:Pins() == 0 then return end
	local t = M:Totals()[itemID]
	if not t then return end
	local color = t.missing == 0 and E.tokens.text.good or E.tokens.text.warn
	add(L["Shopping list"], ("%d/%d"):format(t.have, t.need), nil, nil, nil, color[1], color[2], color[3])
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	if not M.active then return end
	if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then
		M:ScanOpenWindow()
	elseif event == "AUCTION_HOUSE_SHOW" then
		M.atAuction = true
		Changed()
	elseif event == "AUCTION_HOUSE_CLOSED" then
		M.atAuction = false
		Changed()
	else
		-- Bags, bank and the character store: counts changed.
		if not M.redrawQueued then
			M.redrawQueued = true
			C_Timer.After(0.3, function()
				M.redrawQueued = false
				if M.active then Changed() end
			end)
		end
	end
end)

-- The reagent line on item tooltips: one section of the Tooltip page,
-- switched there under its key.
M.TOOLTIP_SECTION = { key = "shoppingList", order = 46, title = "Shopping list", default = "always", module = "ProfessionPlanner",
	desc = "How many of a reagent you have and need for the recipes you pinned in the Profession Planner.",
	item = TooltipLine }

local EVENTS = { "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
	"BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED" }

function M:OnInitialize()
	E:RegisterPrivate("ProfessionPlanner", { pins = {} })
	E:RegisterGlobal("ProfessionRecipes", {})
	if E.RegisterTooltipSection then E:RegisterTooltipSection(M.TOOLTIP_SECTION.key, M.TOOLTIP_SECTION) end
end

function M:OnEnable()
	for _, event in ipairs(EVENTS) do pcall(events.RegisterEvent, events, event) end
	if E.Characters and E.Characters.RegisterCallback then
		E.Characters.RegisterCallback(M, "Updated", function() if M.active then Changed() end end)
	end
	if self.BuildTracker then self:BuildTracker() end
	if self.UpdateTrackerVisibility then self:UpdateTrackerVisibility() end
	if self.InstallHooks then self:InstallHooks() end
	Changed()
	if E.RefreshTooltipSections then E:RefreshTooltipSections() end
end

function M:OnDisable()
	events:UnregisterAllEvents()
	if E.Characters and E.Characters.UnregisterCallback then pcall(E.Characters.UnregisterCallback, M, "Updated") end
	if self.tracker then self.tracker:Hide() end
	if self.UpdateTrackerVisibility then self:UpdateTrackerVisibility() end
	if self.window and self.window:IsOpen() then self.window:Close() end
	if self.UpdateHooks then self:UpdateHooks() end
	if E.RefreshTooltipSections then E:RefreshTooltipSections() end
end

function M:OnProfileChanged()
	if not self.active then return end
	if self.StyleTracker then self:StyleTracker() end
	if self.UpdateTrackerVisibility then self:UpdateTrackerVisibility() end
	Changed()
end

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
function M:Command(arg)
	local word, rest = (arg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	word = (word or ""):lower()
	if word == "" or word == "open" then
		if self.OpenWindow then self:OpenWindow("list") end
	elseif word == "level" or word == "plan" then
		if self.OpenWindow then self:OpenWindow("plan") end
	elseif word == "pin" then
		local id, qty = rest:match("^(%d+)%s*(%d*)$")
		if id and self:Pin(tonumber(id), tonumber(qty) or 1) then
			E:Print(L["Pinned."])
		else
			E:Print(L["/eui plan pin <recipe ID> [crafts]"])
		end
	elseif word == "unpin" then
		local id = tonumber(rest:match("^(%d+)$") or "")
		if not id then
			E:Print(L["/eui plan unpin <recipe ID>"])
		elseif self:Unpin(id) then
			E:Print(L["Unpinned."])
		else
			E:Print(L["No pinned recipe with that ID."])
		end
	elseif word == "clear" then
		self:ConfirmClearPins()
	else
		E:Print(L["/eui plan [open | level | pin <recipe ID> [crafts] | unpin <recipe ID> | clear]"])
	end
end

E:AddCommand("plan", "[open | level | pin <id> [n] | unpin <id> | clear]  the Profession Planner", function(arg)
	if M.active then M:Command(arg) else E:Print(E:ModuleOffHint("ProfessionPlanner")) end
end)

---------------------------------------------------------------------------
-- Options and styles
---------------------------------------------------------------------------
M.options = {
	{ type = "description", label = "Pin recipes from the profession window, Loot Guide or Alts window; the Shopping List shows what they need. /eui plan has a leveling plan." },
	{ type = "execute", label = "Open the planner", desc = "Opens the Profession Planner window with the shopping list and the leveling plan.", testSafe = true,
		func = function() if M.active and M.OpenWindow then M:OpenWindow("list") end end },
	{ type = "header", label = "Shopping list" },
	{ type = "toggle", key = "tracker", label = "Show the tracker", desc = "The Shopping List tracker on screen while something is pinned. Move it in move mode (Shopping List)." },
	{ type = "toggle", key = "includeBank", label = "Count your bank", desc = "Reagents in your bank (and your other characters' banks) count as had." },
	{ type = "toggle", key = "countAlts", label = "Count your other characters", desc = "Reagents your other characters carry count as had; their names show in the tracker's tooltip." },
	{ type = "select", key = "altScope", label = "Which characters", dependsOn = "countAlts", order = { "realm", "faction", "account" },
		values = { realm = "This realm", faction = "This faction", account = "All characters" },
		desc = "The characters whose reagents and recipe cooldowns count. On Forever, this realm means everyone on the same ruleset." },
	{ type = "toggle", key = "subReagents", label = "Reagents you can make", desc = "A reagent you can craft (a bar, a leather, a thread) shows its own reagents under it, two steps deep." },
	{ type = "toggle", key = "hideDone", label = "Hide finished reagents", desc = "Reagents you already have enough of leave the tracker." },
	{ type = "toggle", key = "cooldowns", label = "Recipe cooldowns", desc = "Lines for recipe cooldowns (Transmute, Mooncloth, Salt Shaker) on all counted characters, with the time left or Ready." },
	{ type = "description", label = "The reagent line in item tooltips is the Shopping list section on the Tooltip page." },
	{ type = "header", label = "Prices" },
	{ type = "select", key = "priceSource", label = "Price source", order = { "lowest", "auction", "vendor" },
		values = { lowest = "Lowest of both", auction = "Auction price", vendor = "Vendor price" },
		desc = "Which saved price the leveling plan uses for a reagent: EldoUI's auction prices (from your searches), what a vendor charges (seen at vendors), or the lower of the two." },
	{ type = "toggle", key = "planKnownOnly", label = "Plan with known recipes only", desc = "The leveling plan uses only recipes you already know. Off: it also lists recipes you can still learn, marked Learn." },
	{ type = "header", label = "Pin buttons" },
	{ type = "toggle", key = "blizzardPin", label = "On the profession window", desc = "A Pin button on the game's profession window, next to the selected recipe.", disabled = E:BlizzardNeeds("professions", "improve") },
	{ type = "toggle", key = "otherPins", label = "In the Loot Guide and Alts", desc = "A Pin button in the Loot Guide's Crafting details, and Alt-click on a recipe in the Alts window's Professions tab." },
}
for _, row in ipairs(E:VisibilityOptions("visibility", { db = function() return M.db end, label = "Tracker visibility",
	hidden = function() return not (M.db and M.db.tracker) end })) do
	table.insert(M.options, row)
end
for _, row in ipairs({
	{ type = "tab", label = "Look" },
	{ type = "header", label = "Tracker" },
	{ type = "range", key = "width", label = "Width", min = 180, max = 400, step = 10, desc = "Width of the Shopping List tracker." },
	{ type = "range", key = "fontSize", label = "Text size", min = 10, max = 16, step = 1, desc = "Size of the tracker's text." },
	{ type = "range", key = "maxLines", label = "Most lines", min = 6, max = 30, step = 1, desc = "The tracker shows at most this many lines; the planner window shows them all." },
	{ type = "toggle", key = "icons", label = "Item icons", desc = "A small icon before each reagent." },
	{ type = "toggle", key = "checks", label = "Check marks", desc = "A check mark instead of the count once you have enough of a reagent." },
	{ type = "select", key = "backdrop", label = "Background", order = { "panel", "transparent", "none" },
		values = { panel = "Panel", transparent = "See-through", none = "None" },
		desc = "The tracker's background: a full panel in your art style, a see-through one, or text only." },
	{ type = "toggle", key = "edge", label = "Frame line", desc = "The art style's thin frame line around the tracker (bronze under WoW Forever)." },
}) do
	table.insert(M.options, row)
end

E:RegisterStyles("ProfessionPlanner", {
	{ key = "Compact", title = "Compact", desc = "Small text, icons, finished reagents hidden.",
		settings = { fontSize = 11, width = 220, icons = true, checks = false, hideDone = true, subReagents = true, backdrop = "transparent", edge = true, maxLines = 14 } },
	{ key = "Detailed", title = "Detailed", desc = "Every reagent with the steps you can make and the recipe cooldowns.",
		settings = { fontSize = 12, width = 280, icons = true, checks = false, hideDone = false, subReagents = true, cooldowns = true, backdrop = "transparent", edge = true, maxLines = 18 } },
	{ key = "Checklist", title = "Checklist", desc = "A check mark on what is done; nothing is hidden.",
		settings = { fontSize = 12, width = 250, icons = false, checks = true, hideDone = false, backdrop = "transparent", edge = true, maxLines = 14 } },
	{ key = "MinimalText", title = "Minimal text", desc = "Text only, no background or icons, finished reagents hidden.",
		settings = { fontSize = 12, width = 230, icons = false, checks = false, hideDone = true, backdrop = "none", edge = false, maxLines = 14 } },
	{ key = "ForeverBronze", title = "Forever bronze", desc = "A full panel with the art style's frame line, bronze under WoW Forever.",
		settings = { fontSize = 12, width = 260, icons = true, checks = true, backdrop = "panel", edge = true, maxLines = 14 } },
	{ key = "Large", title = "Large", desc = "Bigger text and a wider tracker.",
		settings = { fontSize = 15, width = 320, icons = true, checks = false, hideDone = false, backdrop = "transparent", edge = true, maxLines = 12 } },
})
