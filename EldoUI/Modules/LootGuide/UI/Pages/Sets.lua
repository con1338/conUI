-- EldoUI Loot Guide: Catalog > Sets and tokens and Collections.
--
-- Sets: tier, dungeon, Zul'Gurub, Ahn'Qiraj, PvP and other sets. A set
-- opens to a card: the pieces (owned mark, where each drops, gain), the
-- bonuses with the pieces each needs (yours lit when you have enough),
-- "Try on set" (dressing room) and "Wish all missing" (only the wishlist).
-- "Sets for my class only" shows your class first; the class chip picks
-- another. Tokens: what each raid token or turn-in item buys for a class.
--
-- Collections: mounts, companions, tabards, legendary items and world
-- epics, with a learned check and a learned count per group ("Hide learned
-- mounts and pets" lists only what you still lack).
--
-- The Journal's item menu opens a piece's set or a token's list here.
local _, E = ...
local LG = E.LootGuide
local Kit = LG.Kit
local P = LG.PageKit
local L = E.L

local Key = E.Key
local CLASS_IDS = { 1, 2, 3, 4, 5, 7, 8, 9, 11 }

local Secret = E.Secret

local function State()
	local ui = LG:UI()
	if type(ui.sets) ~= "table" then ui.sets = {} end
	local s = ui.sets
	if s.view ~= "tokens" then s.view = "sets" end
	if type(s.open) ~= "table" then s.open = {} end
	return s
end

local function ClassName(classID)
	if classID == 0 then return L["All classes"] end
	if C_CreatureInfo and C_CreatureInfo.GetClassInfo then
		local info = C_CreatureInfo.GetClassInfo(classID)
		if type(info) == "table" and type(info.className) == "string" and not Secret(info.className) then return info.className end
	end
	return "#" .. tostring(classID)
end

-- The class to show: picked, else yours (Sets for my class only), else all.
local function ShowClass()
	local s = State()
	if s.class ~= nil then return s.class end
	if LG.db.setsMyClass then return LG:Player().classID or 0 end
	return 0
end

local function ClassMask(classID)
	if not classID or classID == 0 then return 0 end
	return bit.lshift(1, classID - 1)
end

local function ItemLink(itemID)
	local _, link = C_Item.GetItemInfo(itemID)
	if type(link) == "string" and not Secret(link) then return link end
	return ("item:%d"):format(itemID)
end

---------------------------------------------------------------------------
-- Set card
---------------------------------------------------------------------------
local function ButtonsBlock(child)
	local block = CreateFrame("Frame", nil, child)
	block.tryOn = Kit.Button(block, L["Try on set"], 100, 20)
	block.tryOn:SetPoint("LEFT", 0, 0)
	block.wish = Kit.Button(block, L["Wish all missing"], 130, 20)
	block.wish:SetPoint("LEFT", block.tryOn, "RIGHT", 6, 0)
	return block
end

function LG:TryOnSet(set)
	local dress = rawget(_G, "DressUpItemLink")
	if not (set and dress) then return end
	for _, itemID in ipairs(set.pieces) do pcall(dress, ItemLink(itemID)) end
end

-- Puts every piece you do not own on the wishlist; returns how many.
function LG:WishMissingPieces(set)
	local added = 0
	for _, itemID in ipairs(set and set.pieces or {}) do
		if not self:Owns(itemID) and not self:IsWished(itemID) then
			self:SetWished(itemID, true)
			added = added + 1
		end
	end
	return added
end

local function DrawCard(flow, set)
	local owned = LG:SetOwned(set)
	for _, itemID in ipairs(set.pieces) do
		local sources = LG:ItemSources(itemID) or {}
		P.FlowItem(flow, { itemID = itemID, sub = sources[1] and P.SourceLine(sources[1]) or nil, onClick = function() P.OpenItem(itemID) end }, 12)
	end
	local bonuses = LG:SetBonuses(set.id)
	if #bonuses > 0 then
		for _, bonus in ipairs(bonuses) do
			local on = owned >= bonus.count
			local color = on and Kit.GOOD or Kit.SECONDARY
			P.FlowText(flow, Kit.Hex(unpack(color)) .. ("(%d) %s"):format(bonus.count, bonus.text) .. "|r", 11, nil, 12, 2)
		end
	else
		P.FlowText(flow, L["The set bonuses show once the game has the pieces' details (hover a piece once)."], 10, "dim", 12)
	end
	local buttons = flow:Take("setbuttons", ButtonsBlock)
	flow:Place(buttons, 22, 12, 8)
	buttons.tryOn:SetScript("OnClick", function() LG:TryOnSet(set) end)
	Kit.Tooltip(buttons.tryOn, L["Try on set"], L["Shows every piece on your character in the dressing room."])
	local missing = #set.pieces - owned
	buttons.wish:SetEnabled(missing > 0 and LG:WishlistOn())
	buttons.wish:SetScript("OnClick", function()
		local added = LG:WishMissingPieces(set)
		LG:Notify(E:Plural(added, "Added %d piece of %s to your wishlist.", "Added %d pieces of %s to your wishlist."):format(added, set.name))
	end)
	Kit.Tooltip(buttons.wish, L["Wish all missing"], L["Puts every piece you do not have on your active wishlist."])
end

local function SetMatches(set, s, mask, text)
	if s.group and set.group ~= s.group then return false end
	if mask ~= 0 and set.classMask ~= 0 and bit.band(set.classMask, mask) == 0 then return false end
	if text ~= "" and not LG:Fold(set.name):find(text, 1, true) then
		local any = false
		for _, itemID in ipairs(set.pieces) do
			local record = LG:ItemRecord(itemID)
			if record and record.name and LG:Fold(record.name):find(text, 1, true) then any = true end
		end
		if not any then return false end
	end
	return true
end

-- Text other modules add after a set's piece count (the Appearances
-- module's "3/8 looks"): fn(set) -> text or nil.
local function SetLineExtras(set)
	local out = ""
	for _, extra in ipairs(LG.setLineExtras or {}) do
		local ok, text = pcall(extra, set)
		if not ok then
			geterrorhandler()(text)
		elseif type(text) == "string" and text ~= "" then
			out = out .. "  " .. text
		end
	end
	return out
end

local function DrawSets(section)
	local s = State()
	local flow = section.flow
	local mask = ClassMask(ShowClass())
	local text = LG:Fold(s.search or "")
	local shown = 0
	section.setsShown = {}
	for _, group in ipairs(LG.SET_GROUPS) do
		local sets = {}
		for _, set in ipairs(LG:ItemSets()) do
			if set.group == group.key and SetMatches(set, s, mask, text) then sets[#sets + 1] = set end
		end
		if #sets > 0 then
			P.FlowCaption(flow, group.title, tostring(#sets))
			for _, set in ipairs(sets) do
				shown = shown + 1
				section.setsShown[#section.setsShown + 1] = set.id
				local owned = LG:SetOwned(set)
				local open = s.open[set.id]
				local badge = LG.PhaseBadge and LG:PhaseBadge(set.pieces[1])
				P.FlowLine(flow, (open and "- " or "+ ") .. set.name .. "  " .. Kit.Hex(unpack(owned > 0 and Kit.GOOD or Kit.SECONDARY))
					.. ("%d/%d"):format(owned, #set.pieces) .. "|r" .. SetLineExtras(set) .. (badge and ("  " .. badge) or ""), function()
					s.open[set.id] = not s.open[set.id] or nil
					section:Draw(true)
				end, nil, set.name, function(tip) Kit.TooltipHint(tip, { L["Click"], L["show or hide the pieces and bonuses"] }) end)
				if open then DrawCard(flow, set) end
			end
		end
	end
	if shown == 0 then
		P.FlowText(flow, LG:HasData() and L["No set matches the filters."] or L["Item sets come from EldoUI_LootData. Install it next to EldoUI to list them."], 12, "secondary")
	end
end

local function DrawTokens(section)
	local s = State()
	local flow = section.flow
	local classID = ShowClass()
	local text = LG:Fold(s.search or "")
	local shown = 0
	section.tokensShown = {}
	for _, tokenID in ipairs(LG:TokenList()) do
		local record = LG:ItemRecord(tokenID)
		local name = record and record.name or ("item:" .. tokenID)
		local items = LG:TokenFor(tokenID, classID)
		local match = text == "" or LG:Fold(name):find(text, 1, true)
		if not match then
			for _, id in ipairs(items) do
				local r = LG:ItemRecord(id)
				if r and r.name and LG:Fold(r.name):find(text, 1, true) then match = true end
			end
		end
		if match and #items > 0 then
			shown = shown + 1
			section.tokensShown[#section.tokensShown + 1] = tokenID
			local open = s.open["t" .. tokenID]
			local cell = P.FlowItem(flow, { itemID = tokenID, tag = (open and "- " or "+ ") .. E:Plural(#items, "%d item", "%d items"):format(#items),
				onClick = function()
					s.open["t" .. tokenID] = not s.open["t" .. tokenID] or nil
					section:Draw(true)
				end })
			cell.tokenID = tokenID
			if open then
				for _, id in ipairs(items) do
					P.FlowItem(flow, { itemID = id, onClick = function() P.OpenItem(id) end }, 16)
				end
			end
		end
	end
	if shown == 0 then
		P.FlowText(flow, LG:HasData() and (L["No token buys anything for %s."]):format(ClassName(classID))
			or L["Tokens come from EldoUI_LootData. Install it next to EldoUI to list them."], 12, "secondary")
	end
end

local function GroupMenu(owner, section)
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(L["Sets"])
		root:CreateRadio(L["All sets"], function() return State().group == nil end, function() State().group = nil section:Draw() end)
		for _, group in ipairs(LG.SET_GROUPS) do
			root:CreateRadio(group.title, function() return State().group == group.key end, function()
				State().group = group.key
				section:Draw()
			end)
		end
	end, { at = "owner" })
end

local function ClassMenu(owner, section)
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(L["Class"])
		root:CreateRadio(L["My class"], function() return State().class == nil end, function() State().class = nil section:Draw() end)
		root:CreateRadio(L["All classes"], function() return State().class == 0 end, function() State().class = 0 section:Draw() end)
		for _, classID in ipairs(CLASS_IDS) do
			root:CreateRadio(ClassName(classID), function() return State().class == classID end, function()
				State().class = classID
				section:Draw()
			end)
		end
	end, { at = "owner" })
end

local function BuildSets(parent)
	local section = CreateFrame("Frame", nil, parent)
	section.tabSets = P.Toggle(section, L["Sets"], function() State().view = "sets" section:Draw() end, L["Sets"],
		L["Item sets with their pieces and bonuses."])
	section.tabSets:SetPoint("TOPLEFT")
	section.tabTokens = P.Toggle(section, L["Tokens"], function() State().view = "tokens" section:Draw() end, L["Tokens"],
		L["What each raid token or turn-in item buys for a class."])
	section.tabTokens:SetPoint("LEFT", section.tabSets, "RIGHT", 4, 0)
	section.group = P.Toggle(section, "", function(self) GroupMenu(self, section) end, L["Sets"], L["One kind of set, or all."])
	section.group:SetPoint("LEFT", section.tabTokens, "RIGHT", 12, 0)
	section.class = P.Toggle(section, "", function(self) ClassMenu(self, section) end, L["Class"],
		L["Your class (Sets for my class only), all classes or one other class."])
	section.class:SetPoint("LEFT", section.group, "RIGHT", 4, 0)
	section.search = CreateFrame("EditBox", nil, section, "SearchBoxTemplate")
	E:SearchHint(section.search)
	section.search:SetSize(150, 20)
	section.search:SetPoint("TOPRIGHT")
	section.search:SetAutoFocus(false)
	E:SkinEditBox(section.search)
	Kit.Tooltip(section.search, L["Search"], L["Finds sets and tokens by their name or a piece's name."])
	section.search:HookScript("OnTextChanged", function(self, typed)
		if not typed then return end
		State().search = self:GetText() or ""
		section:Draw()
	end)
	section.flow = P.Flow(section)
	section.flow:SetPoint("TOPLEFT", 0, -26)
	section.flow:SetPoint("BOTTOMRIGHT")

	function section:Draw(keepScroll)
		local s = State()
		self.tabSets:SetOn(s.view == "sets")
		self.tabTokens:SetOn(s.view == "tokens")
		local groupTitle = L["All sets"]
		for _, group in ipairs(LG.SET_GROUPS) do if group.key == s.group then groupTitle = group.title end end
		self.group:SetLabel(groupTitle, true)
		self.group:SetShown(s.view == "sets")
		self.group:SetOn(s.group ~= nil)
		self.class:SetLabel(ClassName(ShowClass()), true)
		if (self.search:GetText() or "") ~= (s.search or "") then self.search:SetText(s.search or "") end
		self.flow:Begin()
		if s.view == "tokens" then DrawTokens(self) else DrawSets(self) end
		self.flow:Finish(keepScroll)
	end

	LG:On("section-sets", function(changed)
		if section:IsShown() and (changed.data or changed.bags or changed.gear or changed.wishlist or changed.settings or changed.items) then
			section:Draw(true)
		end
	end)
	return section
end

-- arg: a set id, { set = id }, { token = id } or a search word.
local function ShowSets(section, arg)
	local s = State()
	if type(arg) == "table" and arg.token then
		s.view, s.search = "tokens", ""
		s.open["t" .. arg.token] = true
		s.class = nil
	elseif tonumber(type(arg) == "table" and arg.set or arg) then
		local setID = tonumber(type(arg) == "table" and arg.set or arg)
		local set = LG:SetInfo(setID)
		if set then
			s.view, s.group, s.search = "sets", nil, ""
			s.open[setID] = true
			if set.classMask ~= 0 and bit.band(set.classMask, ClassMask(ShowClass())) == 0 then s.class = 0 end
		end
	elseif type(arg) == "string" and arg ~= "" then
		s.view, s.search = "sets", arg
	end
	section:Draw()
	Kit.Tour("sets", {
		{ target = section.class, text = L["Sets for your class come first; pick another class here."] },
		{ target = section.tabTokens, text = L["Tokens shows what each raid token buys for a class."] },
	})
end

LG:RegisterCatalogueSection("sets", {
	title = "Sets and tokens",
	icon = "Interface\\Icons\\INV_Chest_Plate03",
	desc = "Item sets with pieces and bonuses, try on and wish all missing; what each token buys for your class.",
	order = 40,
	command = "sets",
	usage = Key("open Catalog > Sets; add a set name (/eui sets bloodfang)"),
	argument = function(word) return strtrim(word) end,
	build = BuildSets,
	show = ShowSets,
	search = function(text)
		local out = {}
		text = LG:Fold(text)
		for _, set in ipairs(LG:ItemSets()) do
			if LG:Fold(set.name):find(text, 1, true) then
				out[#out + 1] = { title = set.name, arg = set.id }
				if #out >= 20 then break end
			end
		end
		return out
	end,
})

---------------------------------------------------------------------------
-- Collections
---------------------------------------------------------------------------
local function CState()
	local ui = LG:UI()
	if type(ui.collections) ~= "table" then ui.collections = { group = "mounts" } end
	return ui.collections
end

local function HideLearned()
	local s = CState()
	if s.hideLearned ~= nil then return s.hideLearned end
	return LG.db.collectHideLearned and true or false
end

function LG:CollectionCounts(group)
	local list = self:Collections()[group] or {}
	local learned = 0
	for _, itemID in ipairs(list) do
		if self:IsLearned(itemID) then learned = learned + 1 end
	end
	return learned, #list
end

local function BuildCollections(parent)
	local section = CreateFrame("Frame", nil, parent)
	section.chips = {}
	local anchor
	for _, group in ipairs(LG.COLLECTION_GROUPS) do
		local chip = P.Toggle(section, group.title, function()
			CState().group = group.key
			section:Draw()
		end, group.title, L["Learned or owned out of all the loot data knows."])
		if anchor then chip:SetPoint("LEFT", anchor, "RIGHT", 4, 0) else chip:SetPoint("TOPLEFT") end
		anchor = chip
		section.chips[group.key] = chip
	end
	section.hide = P.Toggle(section, L["Not learned only"], function()
		local s = CState()
		s.hideLearned = not HideLearned()
		section:Draw()
	end, L["Not learned only"], L["Lists only what you have not learned or do not own yet."])
	section.hide:SetPoint("TOPRIGHT")
	section.flow = P.Flow(section)
	section.flow:SetPoint("TOPLEFT", 0, -26)
	section.flow:SetPoint("BOTTOMRIGHT")

	function section:Draw(keepScroll)
		local s = CState()
		for _, group in ipairs(LG.COLLECTION_GROUPS) do
			local learned, total = LG:CollectionCounts(group.key)
			local chip = self.chips[group.key]
			chip:SetLabel(("%s %d/%d"):format(group.title, learned, total))
			chip:SetOn(s.group == group.key)
		end
		local hide = HideLearned()
		self.hide:SetOn(hide)
		local flow = self.flow
		flow:Begin()
		local items = {}
		for _, itemID in ipairs(LG:Collections()[s.group] or {}) do
			if not (hide and LG:IsLearned(itemID)) then items[#items + 1] = itemID end
		end
		table.sort(items, function(a, b)
			local ra, rb = LG:ItemRecord(a), LG:ItemRecord(b)
			return (ra and ra.name or "") < (rb and rb.name or "")
		end)
		self.shown = items
		for _, itemID in ipairs(items) do
			local learned = LG:IsLearned(itemID)
			local sources = LG:ItemSources(itemID) or {}
			P.FlowItem(flow, { itemID = itemID, tag = learned and (Kit.Hex(unpack(Kit.GOOD)) .. L["learned"] .. "|r") or nil,
				sub = sources[1] and P.SourceLine(sources[1]) or nil, onClick = function() P.OpenItem(itemID) end })
		end
		if #items == 0 then
			P.FlowText(flow, LG:HasData() and (hide and L["You have them all."] or L["Nothing in this group."])
				or L["Collections come from EldoUI_LootData. Install it next to EldoUI to list them."], 12, "secondary")
		end
		flow:Finish(keepScroll)
	end

	LG:On("section-collections", function(changed)
		if section:IsShown() and (changed.learned or changed.bags or changed.data or changed.settings or changed.items) then section:Draw(true) end
	end)
	return section
end

LG:RegisterCatalogueSection("collections", {
	title = "Collections",
	icon = "Interface\\Icons\\Ability_Mount_RidingHorse",
	desc = "Mounts, companions, tabards, legendary items and world epics, with what you have learned or own.",
	order = 45,
	command = "collections",
	usage = Key("open Catalog > Collections; add mounts, pets, tabards, legendary or epics"),
	argument = function(word)
		word = strtrim(word:lower())
		if word == "companions" then word = "pets" end
		for _, group in ipairs(LG.COLLECTION_GROUPS) do if group.key == word then return word end end
	end,
	build = BuildCollections,
	show = function(section, arg)
		if type(arg) == "string" then CState().group = arg end
		section:Draw()
	end,
})

-- Bag changes may mean a tabard or an epic arrived.
LG:Listen("BAG_UPDATE_DELAYED", "collections", function() LG:Fire("learned") end)

---------------------------------------------------------------------------
-- Item menu: open a piece's set or a token's list
---------------------------------------------------------------------------
LG:RegisterItemMenu("sets", function(root, itemID)
	local setID, set = LG:SetsOf(itemID)
	if setID and set then
		root:CreateButton((L["Show set: %s (%d/%d)"]):format(set.name, LG:SetOwned(set), #set.pieces), function()
			LG:OpenSection("sets", { set = setID })
		end)
	end
	if LG:TokenRewards(itemID) then
		root:CreateButton(L["Show what this token buys"], function() LG:OpenSection("sets", { token = itemID }) end)
	end
end)
