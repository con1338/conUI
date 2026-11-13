-- EldoUI Characters: professions, recipes and recipe owners.
--
-- The Professions tab: one row per character and profession (skill, known
-- recipes, cooldowns), and the recipe list of the selected row with a
-- filter box. Recipe lists come from each character's own profession
-- window (open it once per profession).
--
-- Recipe owners: on a recipe item the tooltip section "Alts: recipes"
-- (altRecipes) says which of your characters already know it, who can
-- learn it now and who later. At vendors a small dot on the item button
-- and at the auction house the icon tint use the same three colors.
-- Everything comes from what the game shows: the item's own "Requires
-- <profession> (<skill>)" line, the saved skill ranks and the saved recipe
-- lists. No C_TradeSkillUI call is needed for this part.
local _, E = ...
local L = E.L
local Kit = E.UIKit
local M = E.modules.Characters

local function Store() return E.Characters end

local function Grey(text) return M.Grey(text) end

---------------------------------------------------------------------------
-- Recipe owners
---------------------------------------------------------------------------
local function IsSecret(value) return issecretvalue and issecretvalue(value) or false end

-- The game's own "Requires %s (%d)" line in the client's language. Some
-- translations number their arguments ("Benötigt %1$s (%2$d)"); the shared
-- parser reads those too.
local function SkillFormat()
	return rawget(_G, "ITEM_MIN_SKILL") or "Requires %s (%d)"
end

local requiredCache = {}

-- The skill the recipe item asks for, from its tooltip line.
local function RequiredSkill(item, itemID)
	if requiredCache[itemID] then return requiredCache[itemID] end
	if not C_TooltipInfo then return end
	local ok, data
	if type(item) == "string" and C_TooltipInfo.GetHyperlink then
		ok, data = pcall(C_TooltipInfo.GetHyperlink, item)
	elseif C_TooltipInfo.GetItemByID then
		ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
	end
	if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return end
	local format = SkillFormat()
	for _, line in ipairs(data.lines) do
		local text = line.leftText
		if type(text) == "string" and not IsSecret(text) then
			local args = E.ChatParse:MatchFormat(text, format)
			local skill = args and tonumber(args[2])
			if skill then
				requiredCache[itemID] = tonumber(skill)
				return requiredCache[itemID]
			end
		end
	end
end

-- Known recipe names per character and profession, from the packed IDs.
local nameCache = {}
local function KnownNames(key, profName, entry)
	if type(entry.recipes) ~= "string" then return nil end
	local slot = key .. "\001" .. profName
	local cached = nameCache[slot]
	if cached and cached.source == entry.recipes then return cached.names end
	local names = {}
	for id in pairs(Store().UnpackIDs(entry.recipes)) do
		local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
		if type(name) == "string" and not IsSecret(name) then names[name:lower()] = true end
	end
	nameCache[slot] = { source = entry.recipes, names = names }
	return names
end

-- What a recipe item teaches: "Pattern: Linen Bag" -> "linen bag".
local function TaughtName(itemName)
	if type(itemName) ~= "string" then return nil end
	return (itemName:match("^[^:]+:%s*(.+)$") or itemName):lower()
end

-- Recipe items whose name the client hasn't loaded yet: asked for once;
-- the vendor squares redraw when GET_ITEM_INFO_RECEIVED brings one.
local waitingItems = {}

-- For a recipe item (link or ID): { profession, required, known = {keys},
-- now = {keys}, later = {keys}, unscanned = {keys} }, or nil when the
-- item is no recipe, nobody saved has the profession, or the item's name
-- (what it teaches) isn't loaded yet: unknown, never a guess.
function M:RecipeOwners(item)
	if IsSecret(item) or type(item) == "nil" then return nil end
	local itemID, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(item)
	if not itemID or classID ~= (Enum.ItemClass and Enum.ItemClass.Recipe or 9) then return nil end
	if subclassID == (Enum.ItemRecipeSubclass and Enum.ItemRecipeSubclass.Book or 0) then return nil end
	local profName = C_Item.GetItemSubClassInfo and C_Item.GetItemSubClassInfo(classID, subclassID)
	if type(profName) ~= "string" or profName == "" then return nil end
	local itemName = C_Item.GetItemInfo(item)
	if IsSecret(itemName) then return nil end
	local taught = TaughtName(itemName)
	if not taught then
		if not waitingItems[itemID] then
			waitingItems[itemID] = true
			if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
		end
		return nil
	end
	local required = RequiredSkill(item, itemID) or 1
	local result = { profession = profName, required = required, known = {}, now = {}, later = {}, unscanned = {} }
	local any = false
	for _, key in ipairs(Store():Keys("realm")) do
		local record = Store():Get(key)
		local entry = type(record.profs) == "table" and record.profs[profName]
		if entry then
			any = true
			local names = KnownNames(key, profName, entry)
			local known
			if key == E.charKey and E.IsItemKnown and E:IsItemKnown(item) then
				known = true
			elseif names and taught then
				known = names[taught] == true
			end
			if known then
				result.known[#result.known + 1] = key
			elseif names == nil and key ~= E.charKey then
				result.unscanned[#result.unscanned + 1] = key
			elseif (entry.rank or 0) >= required then
				result.now[#result.now + 1] = key
			else
				result.later[#result.later + 1] = key
			end
		end
	end
	return any and result or nil
end

-- "now" (green), "later" (yellow), "known" (red: everyone with the
-- profession knows it) or nil.
function M:RecipeStatus(item)
	local owners = self:RecipeOwners(item)
	if not owners then return nil end
	if #owners.now > 0 then return "now", owners end
	if #owners.later > 0 then return "later", owners end
	if #owners.known > 0 and #owners.unscanned == 0 then return "known", owners end
	return nil, owners
end

local STATUS_COLOR = { now = Kit.GOOD, later = Kit.WARN, known = Kit.BAD }
M.RECIPE_COLOR = STATUS_COLOR

-- Used by the auction house results (Modules/Auction.lua).
function E:AltRecipeTint(item)
	if not (M.active and M.db.recipeColours) then return nil end
	local status = M:RecipeStatus(item)
	local color = status and STATUS_COLOR[status]
	if color then return color[1], color[2], color[3] end
end

local function Names(keys, withRank, profName)
	local parts = {}
	for _, key in ipairs(keys) do
		local record = Store():Get(key)
		local text = M.ClassName(record)
		if withRank then
			local entry = record.profs and record.profs[profName]
			text = text .. Grey((" (%d)"):format(entry and entry.rank or 0))
		end
		parts[#parts + 1] = text
	end
	return table.concat(parts, ", ")
end

function M:RecipeLines(item)
	local owners = self:RecipeOwners(item)
	if not owners then return nil end
	local lines = {}
	if #owners.known > 0 then lines[#lines + 1] = { L["Known by"], Names(owners.known) } end
	if #owners.now > 0 then lines[#lines + 1] = { L["Can learn now"], Names(owners.now, true, owners.profession), Kit.GOOD } end
	if #owners.later > 0 then
		lines[#lines + 1] = { L["Can learn at %d"]:format(owners.required), Names(owners.later, true, owners.profession), Kit.WARN }
	end
	if #owners.unscanned > 0 then
		lines[#lines + 1] = { L["Recipes not saved yet"], Names(owners.unscanned) }
	end
	return lines
end

local function AddRecipeLines(add, item)
	for _, line in ipairs(M:RecipeLines(item) or {}) do
		local color = line[3]
		if color then add(line[1], line[2], color[1], color[2], color[3]) else add(line[1], line[2]) end
	end
end

local function HookTooltip()
	if M.recipeTooltipHooked then return end
	M.recipeTooltipHooked = true
	-- A section of the shared info area: it shows with the Tooltip module
	-- on or off.
	E:RegisterTooltipSection("altRecipes", { order = 41, title = "Alts: recipes", default = "always",
		desc = "On recipes: which of your characters already know it, who can learn it now and who later (Alts module).",
		item = function(_, link, itemID, add)
			if not M.active then return end
			AddRecipeLines(add, link or itemID)
		end })
end
M.HookRecipeTooltip = HookTooltip

---------------------------------------------------------------------------
-- Vendor dots: a small square on Blizzard's merchant item buttons, drawn
-- after Blizzard has drawn the page (post-hook, nothing replaced).
---------------------------------------------------------------------------
-- The squares, keyed by Blizzard's button (weak keys): nothing is written
-- onto Blizzard's frames.
local dots = setmetatable({}, { __mode = "k" })
M.vendorDots = dots

local function Dot(button)
	if dots[button] then return dots[button] end
	local dot = CreateFrame("Frame", nil, button, "BackdropTemplate")
	-- The square in the item's top-left corner: the color says whether one
	-- of your characters can learn the recipe (see the item tooltip).
	dot:SetSize(9, 9)
	dot:SetPoint("TOPLEFT", 1, -1)
	dot:SetFrameLevel(button:GetFrameLevel() + 3)
	E:SetTemplate(dot)
	dots[button] = dot
	return dot
end

function M:UpdateVendorDots()
	local perPage = MERCHANT_ITEMS_PER_PAGE or 10
	local page = MerchantFrame and MerchantFrame.page or 1
	local on = self.active and self.db.recipeColours and MerchantFrame and MerchantFrame:IsShown()
		and (MerchantFrame.selectedTab or 1) == 1
	local shown = 0
	for index = 1, perPage do
		local button = _G["MerchantItem" .. index .. "ItemButton"]
		if button then
			local item = on and (page - 1) * perPage + index
			local link = item and item <= (GetMerchantNumItems() or 0) and GetMerchantItemLink(item)
			local status = link and self:RecipeStatus(link)
			local color = status and STATUS_COLOR[status]
			if color then
				local dot = Dot(button)
				dot:SetBackdropColor(color[1], color[2], color[3], 1)
				dot:Show()
				shown = shown + 1
			elseif dots[button] then
				dots[button]:Hide()
			end
		end
	end
	return shown
end

-- The merchant page draws through MerchantFrame_UpdateMerchantInfo, the
-- buyback page through MerchantFrame_UpdateBuybackInfo (the same buttons):
-- both redraw the squares, which stay hidden off the merchant page.
local itemWatcher = {}

local function HookVendor()
	if M.vendorHooked then return end
	local names = {}
	for _, name in ipairs({ "MerchantFrame_UpdateMerchantInfo", "MerchantFrame_UpdateBuybackInfo" }) do
		if type(rawget(_G, name)) == "function" then names[#names + 1] = name end
	end
	if #names == 0 and type(rawget(_G, "MerchantFrame_Update")) == "function" then names[1] = "MerchantFrame_Update" end
	if #names == 0 then return end
	M.vendorHooked = true
	for _, name in ipairs(names) do
		hooksecurefunc(name, function() M:UpdateVendorDots() end)
	end
	E:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(_, _, itemID)
		if IsSecret(itemID) or not waitingItems[itemID] then return end
		waitingItems[itemID] = nil
		if M.vendorRedraw or not (MerchantFrame and MerchantFrame:IsShown()) then return end
		M.vendorRedraw = true
		C_Timer.After(0.2, function()
			M.vendorRedraw = nil
			M:UpdateVendorDots()
		end)
	end, itemWatcher)
end
M.HookVendor = HookVendor


---------------------------------------------------------------------------
-- Professions tab
---------------------------------------------------------------------------
local function ProfRows()
	local rows = {}
	local now = Store().Now()
	for _, key in ipairs(M:Keys()) do
		local record = Store():Get(key)
		for name, entry in pairs(type(record.profs) == "table" and record.profs or {}) do
			local ready, waiting, soonest = 0, 0
			for _, cd in pairs(type(record.cooldowns) == "table" and record.cooldowns or {}) do
				if cd.prof == nil or cd.prof == name then
					if (cd.readyAt or 0) <= now then
						ready = ready + 1
					else
						waiting = waiting + 1
						soonest = math.min(soonest or cd.readyAt, cd.readyAt)
					end
				end
			end
			rows[#rows + 1] = { key = key, record = record, name = name, entry = entry, ready = ready, waiting = waiting, soonest = soonest }
		end
	end
	return rows
end
M.ProfRows = ProfRows

local function RecipeRows(row, filter)
	local list = {}
	if not row then return list end
	filter = (filter or ""):lower()
	for id in pairs(Store().UnpackIDs(row.entry.recipes)) do
		local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) or ("#" .. id)
		if filter == "" or name:lower():find(filter, 1, true) then
			local cd = type(row.record.cooldowns) == "table" and row.record.cooldowns[id]
			list[#list + 1] = { id = id, name = name, cooldown = cd and cd.readyAt }
		end
	end
	return list
end
M.RecipeRows = RecipeRows

local function ShowRecipes(frame)
	local row = frame.selected
	frame.recipes:SetData(RecipeRows(row, frame.filter:GetText()))
	if row then
		frame.recipeTitle:SetText(L["%s: %s recipes"]:format(M.ClassName(row.record), row.name))
	else
		frame.recipeTitle:SetText(L["Click a profession to see its recipes."])
	end
end

local function Update(frame)
	local rows = ProfRows()
	frame.profs:SetData(rows)
	local keep
	for _, row in ipairs(rows) do
		if frame.selected and row.key == frame.selected.key and row.name == frame.selected.name then keep = row end
	end
	frame.selected = keep or rows[1]
	ShowRecipes(frame)
end
M.UpdateProfessions = Update

-- Recipe row hooks: other modules (the Profession Planner's Pin)
-- add to the recipe rows of the Professions tab without reading tooltip
-- owners. hook = { tooltip = fn(tooltip, spellID, row), click =
-- fn(row, spellID, button, widget) -> true when it handled the click }.
-- Each runs in a pcall; an error goes to the error log.
M.recipeRowHooks = {}
function M:RegisterRecipeRowHook(key, hook)
	self.recipeRowHooks[key] = type(hook) == "table" and hook or nil
end

function M.RunRecipeRowHooks(kind, ...)
	local handled = false
	for key, hook in pairs(M.recipeRowHooks) do
		local fn = hook[kind]
		if type(fn) == "function" then
			local ok, result = pcall(fn, ...)
			if not ok then
				geterrorhandler()(("EldoUI Characters recipe row hook %s: %s"):format(tostring(key), tostring(result)))
			elseif result then
				handled = true
			end
		end
	end
	return handled
end

M:AddTab({
	key = "professions", order = 30, title = "Professions",
	desc = "Every character's professions with skill, recipes and cooldowns, and the recipe list of each.",
	create = function(content)
		local frame = CreateFrame("Frame", nil, content)
		frame:SetAllPoints()
		frame.profs = Kit.CreateTable(frame, {
			{ key = "char", title = L["Character"], width = 170, value = function(row) return row.record.name or "" end,
				text = function(row) return M.ClassIcon(row.record.class, 14) .. M.ClassName(row.record) end },
			{ key = "name", title = L["Profession"], value = function(row) return row.name end,
				text = function(row) return (row.entry.icon and ("|T%s:14:14:0:0:64:64:5:59:5:59|t "):format(row.entry.icon) or "") .. row.name end },
			{ key = "rank", title = L["Skill"], width = 90, align = "RIGHT", value = function(row) return row.entry.rank or 0 end,
				text = function(row) return ("%d/%d"):format(row.entry.rank or 0, row.entry.max or 0) end },
			{ key = "count", title = L["Recipes"], width = 80, align = "RIGHT", value = function(row) return row.entry.count or -1 end,
				text = function(row) return row.entry.count and tostring(row.entry.count) or Grey(L["open once"]) end },
			{ key = "cd", title = L["Cooldowns"], width = 130, align = "RIGHT", value = function(row) return row.soonest or (row.ready > 0 and 0) or math.huge end,
				text = function(row)
					local parts = {}
					if row.ready > 0 then parts[#parts + 1] = M.Good(L["%d ready"]:format(row.ready)) end
					if row.soonest then parts[#parts + 1] = M.Duration(row.soonest - Store().Now()) end
					return table.concat(parts, " · ")
				end },
		}, {
			sortKey = "char", rowHeight = 18,
			onClick = function(row, button, widget)
				if button == "RightButton" then
					M:ShowCharacterMenu(widget, row.key)
				else
					frame.selected = row
					ShowRecipes(frame)
				end
			end,
			empty = { L["No professions"], L["Professions show here after each character logs in. Recipe lists fill in when a character opens its profession window."] },
		})
		frame.profs:SetPoint("TOPLEFT")
		frame.profs:SetPoint("TOPRIGHT")
		frame.profs:SetHeight(190)
		frame.bar = CreateFrame("Frame", nil, frame)
		frame.bar:SetPoint("TOPLEFT", frame.profs, "BOTTOMLEFT", 0, -8)
		frame.bar:SetPoint("TOPRIGHT", frame.profs, "BOTTOMRIGHT", 0, -8)
		frame.bar:SetHeight(22)
		frame.recipeTitle = Kit.Text(frame.bar, 12, "LEFT", "header")
		frame.recipeTitle:SetPoint("LEFT", 4, 0)
		local filter = CreateFrame("EditBox", nil, frame.bar, "SearchBoxTemplate")
		E:SearchHint(filter)
		filter:SetSize(200, 20)
		filter:SetAutoFocus(false)
		filter:SetPoint("RIGHT", -2, 0)
		E:SkinEditBox(filter)
		filter:HookScript("OnTextChanged", function() ShowRecipes(frame) end)
		Kit.Tooltip(filter, L["Filter recipes"], L["Shows only the recipes whose name contains this text."])
		frame.filter = filter
		frame.recipeTitle:SetPoint("RIGHT", filter, "LEFT", -8, 0)
		frame.recipes = Kit.CreateTable(frame, {
			{ key = "name", title = L["Recipe"], value = function(row) return row.name end },
			{ key = "cooldown", title = L["Cooldown"], width = 120, align = "RIGHT", value = function(row) return row.cooldown or 0 end,
				text = function(row)
					if not row.cooldown then return "" end
					local left = row.cooldown - Store().Now()
					return left > 0 and M.Duration(left) or M.Good(L["ready"])
				end },
		}, {
			sortKey = "name", rowHeight = 16,
			onClick = function(row, button, widget)
				if M.RunRecipeRowHooks("click", row, row.id, button, widget) then return end
				if IsModifiedClick("CHATLINK") and C_Spell and C_Spell.GetSpellLink then
					E:InsertLink(C_Spell.GetSpellLink(row.id))
				end
			end,
			createRow = function(widget)
				widget:HookScript("OnEnter", function(own)
					if not own.item then return end
					GameTooltip:SetOwner(own, "ANCHOR_RIGHT")
					GameTooltip:SetSpellByID(own.item.id)
					M.RunRecipeRowHooks("tooltip", GameTooltip, own.item.id, own.item)
					GameTooltip:Show()
				end)
				widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
			end,
			empty = { L["No recipes saved"], L["Log in on this character and open the profession window once; its recipes are saved then."] },
		})
		frame.recipes:SetPoint("TOPLEFT", frame.bar, "BOTTOMLEFT", 0, -4)
		frame.recipes:SetPoint("BOTTOMRIGHT")
		return frame
	end,
	show = function(frame) Update(frame) end,
	refresh = function(frame) Update(frame) end,
	enable = function()
		HookTooltip()
		HookVendor()
	end,
})
