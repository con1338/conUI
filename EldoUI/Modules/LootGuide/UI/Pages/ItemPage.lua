-- EldoUI Loot Guide: the item page and the detail page.
--
--   LG:ItemRoute(itemID)  where opening an item goes: its item page when
--                         it drops in the open world (or is a random world
--                         drop), else the boss in the Journal, else the
--                         quest, else a search for its name
--
-- Item page (hidden page "item"): sidebar with icon, name, slot, required
-- level, wishlist and Try on; a source pill; drops from open-world mobs
-- with a camp-cycling Map button, the random world drop band, dungeon and
-- raid sources (open the Journal), quest rewards (dungeon quests open the
-- Journal; others show the giver, zone and a Map button, dimmed when not
-- for you), vendors and crafts, "no known source" and the Classic footnote.
--
-- Detail page (hidden page "detail"): a quest outside dungeons
-- ({ quest = id }) or a creature with its drops ({ npc = id }).
local _, E = ...
local LG = E.LootGuide
local Kit = LG.Kit
local P = LG.PageKit
local L = E.L

local SIDEBAR = 220

local function Secret(value)
	return P.Secret(value)
end

---------------------------------------------------------------------------
-- Routing
---------------------------------------------------------------------------
local function WorldSource(entry)
	if entry.kind == "world" then return true end
	if (entry.kind == "npc" or entry.kind == "object") and not (entry.instance and LG:InstanceInfo(entry.instance)) then return true end
	return false
end

local function ItemName(itemID)
	local name = C_Item.GetItemInfo(itemID)
	if Secret(name) then name = nil end
	if not name then
		local record = LG:ItemRecord(itemID)
		name = record and record.name
	end
	return name
end

function LG:ItemRoute(itemID)
	itemID = tonumber(itemID)
	local sources = self:ItemSources(itemID) or {}
	for _, entry in ipairs(sources) do
		if WorldSource(entry) then return "item", itemID end
	end
	local bestBoss
	for _, entry in ipairs(sources) do
		if (entry.kind == "npc" or entry.kind == "object") and entry.instance and self:InstanceInfo(entry.instance) then
			if not bestBoss or (entry.chance or 0) > (bestBoss.chance or 0) then bestBoss = entry end
		end
	end
	if bestBoss and self:IsPageOn("journal") then return "journal", { key = bestBoss.instance, npc = bestBoss.id } end
	for _, entry in ipairs(sources) do
		if entry.kind == "quest" or entry.kind == "choice" then
			local quest = self:Quest(entry.id)
			if quest and quest.instance and self:InstanceInfo(quest.instance) and self:IsPageOn("journal") then
				return "journal", { key = quest.instance, quest = entry.id }
			end
			return "item", itemID
		end
	end
	if #sources > 0 then return "item", itemID end
	local name = ItemName(itemID)
	if name and self:IsPageOn("search") then return "search", name end
	return "item", itemID
end

---------------------------------------------------------------------------
-- Shared: back link
---------------------------------------------------------------------------
local function BackTarget()
	local search = LG:GetPage("search")
	local query = search and search.frame and search.frame.query
	if query and query ~= "" then return "search", query, L["Back to search"] end
	return LG:StartPage(), nil, L["Back"]
end

local function Back(parent)
	return P.Back(parent, L["Back"], function()
		local key, arg = BackTarget()
		LG:Open(key, arg)
	end)
end

---------------------------------------------------------------------------
-- Item page
---------------------------------------------------------------------------
local function SourcePill(sources)
	local kinds = {}
	for _, entry in ipairs(sources) do
		if entry.kind == "world" then kinds.world = true
		elseif (entry.kind == "npc" or entry.kind == "object") and entry.instance then kinds.instance = true
		elseif entry.kind == "npc" and (entry.rank == 2 or entry.rank == 4) then kinds.rare = true
		elseif entry.kind == "npc" or entry.kind == "object" then kinds.open = true
		elseif entry.kind == "quest" or entry.kind == "choice" then kinds.quest = true
		elseif entry.kind == "crafted" then kinds.crafted = true
		elseif entry.kind == "vendor" or entry.kind == "repvendor" or entry.kind == "pvpvendor" then kinds.vendor = true
		elseif entry.kind == "token" then kinds.token = true end
	end
	if kinds.rare then return L["Rare drop"], Kit.WARN end
	if kinds.open then return L["Open world"], Kit.GOOD end
	if kinds.instance then return L["Dungeon or raid drop"], { Kit.Accent() } end
	if kinds.world then return L["World drop"], Kit.SECONDARY end
	if kinds.quest then return L["Quest reward"], { 1, 0.82, 0 } end
	if kinds.crafted then return L["Crafted"], Kit.SECONDARY end
	if kinds.vendor then return L["Sold by a vendor"], Kit.SECONDARY end
	if kinds.token then return L["Bought with a token"], Kit.SECONDARY end
	return L["No known source"], Kit.DIM
end

local function ChanceText(entry, itemID)
	local data = P.ChanceData(entry.chance, entry.kind == "npc" and entry.id or nil, itemID)
	local bits = {}
	if data.chance then bits[#bits + 1] = Kit.Hex(Kit.ChanceColor(data.chance)) .. Kit.ChanceText(data.chance) .. "|r" end
	if data.seen then bits[#bits + 1] = E:TextHex("secondary") .. data.seen .. "|r" end
	if entry.questOnly then bits[#bits + 1] = E:TextHex("secondary") .. L["on the quest"] .. "|r" end
	return #bits > 0 and ("  " .. table.concat(bits, "  ")) or ""
end

local function DrawItem(page)
	local itemID = page.itemID
	local side = page.side
	local name, link, quality, itemLevel, reqLevel, _, _, _, equipLoc, icon = C_Item.GetItemInfo(itemID)
	if Secret(name) then name, link, quality, itemLevel, reqLevel, equipLoc, icon = nil, nil, nil, nil, nil, nil, nil end
	local record = LG:ItemRecord(itemID)
	if not name then LG:RequestItem(itemID) end
	name = name or (record and record.name) or ("item:" .. itemID)
	quality = quality or (record and record.quality)
	reqLevel = reqLevel or (record and record.reqLevel)
	itemLevel = itemLevel or (record and record.itemLevel)
	icon = icon or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)) or 134400
	side.icon.icon:SetTexture(icon)
	side.name:SetText(name)
	side.name:SetTextColor(Kit.QualityColor(quality))
	local bits = {}
	local slotName = type(equipLoc) == "string" and equipLoc ~= "" and rawget(_G, equipLoc)
	if type(slotName) == "string" then bits[#bits + 1] = slotName end
	if reqLevel and reqLevel > 1 then bits[#bits + 1] = (L["Requires level %d"]):format(reqLevel) end
	if itemLevel and itemLevel > 0 then bits[#bits + 1] = (L["Item level %d"]):format(itemLevel) end
	side.info:SetText(table.concat(bits, "\n"))
	local wished = LG:IsWished(itemID)
	side.wish:SetShown(LG:WishlistOn())
	side.wish:SetText(wished and L["Remove from wishlist"] or L["Add to wishlist"])
	side.tryOn:SetEnabled(link ~= nil and DressUpItemLink ~= nil and LG:ItemSlots(itemID) ~= nil)
	local _, _, backLabel = BackTarget()
	side.back:SetLabel(backLabel)
	page.link = link

	local flow = page.flow
	flow:Begin()
	local sources, more = LG:ItemSources(itemID)
	sources = sources or {}
	local pill, color = SourcePill(sources)
	page.pill:SetLabel(pill, unpack(color))

	-- Drops from open-world mobs and objects.
	local open, inside, quests, other, worldDrop = {}, {}, {}, {}, nil
	for _, entry in ipairs(sources) do
		if entry.kind == "world" then worldDrop = entry
		elseif entry.kind == "npc" or entry.kind == "object" then
			if entry.instance and LG:InstanceInfo(entry.instance) then inside[#inside + 1] = entry else open[#open + 1] = entry end
		elseif entry.kind == "quest" or entry.kind == "choice" then quests[#quests + 1] = entry
		else other[#other + 1] = entry end
	end
	if #open > 0 then
		P.FlowCaption(flow, L["Drops from"], tostring(#open))
		for _, entry in ipairs(open) do
			local camps = LG:SpawnPoints(entry.kind, entry.id)
			local zone = camps[1] and LG:SpawnZone(camps[1])
			local meta = {}
			if P.RANK[entry.rank or 0] then meta[#meta + 1] = P.RANK[entry.rank] end
			if entry.minLevel then
				meta[#meta + 1] = entry.minLevel == entry.maxLevel and (L["level %d"]):format(entry.minLevel)
					or (L["level %d-%d"]):format(entry.minLevel, entry.maxLevel or entry.minLevel)
			end
			if zone then meta[#meta + 1] = zone end
			if #camps > 1 then meta[#meta + 1] = E:Plural(#camps, "%d camp", "%d camps"):format(#camps) end
			local label = entry.name or (entry.kind == "npc" and L["NPC %s"]:format(entry.id) or L["Container"])
			local text = label .. (#meta > 0 and ("  " .. E:TextHex("secondary") .. table.concat(meta, " · ") .. "|r") or "") .. ChanceText(entry, itemID)
			local npc = entry.kind == "npc" and entry.id or nil
			P.FlowLine(flow, text, npc and function() LG:Open("detail", { npc = npc }) end or nil, P.MapButton(entry.kind, entry.id, label),
				label, npc and function(tip) Kit.TooltipHint(tip, { L["Click"], L["see everything it drops"] }) end or nil)
		end
	end
	if worldDrop then
		P.FlowCaption(flow, L["Random world drop"])
		local text = worldDrop.minLevel and (L["Any mob of level %d to %d can drop it."]):format(worldDrop.minLevel, worldDrop.maxLevel or worldDrop.minLevel)
			or L["Any mob of the right level can drop it."]
		if type(worldDrop.chance) == "number" then text = text .. "  " .. (L["About %s per kill."]):format(Kit.ChanceText(worldDrop.chance)) end
		P.FlowText(flow, text, 12, "secondary")
	end
	if #inside > 0 then
		P.FlowCaption(flow, L["In dungeons and raids"], tostring(#inside))
		for _, entry in ipairs(inside) do
			local info = LG:InstanceInfo(entry.instance)
			local text = (entry.name or L["NPC %s"]:format(tostring(entry.id))) .. "  " .. E:TextHex("secondary") .. info.name .. "|r" .. ChanceText(entry, itemID)
			P.FlowLine(flow, text, function() LG:Open("journal", { key = entry.instance, npc = entry.id }) end, nil,
				info.name, function(tip) Kit.TooltipHint(tip, { L["Click"], L["open it in the Journal"] }) end)
		end
	end
	if #quests > 0 then
		P.FlowCaption(flow, L["Quest rewards"], tostring(#quests))
		for _, entry in ipairs(quests) do
			local quest = LG:Quest(entry.id)
			local status = LG:QuestStatus(entry.id)
			local title = LG:QuestTitle(entry.id) or ("#" .. entry.id)
			local tag = entry.kind == "choice" and L["choice"] or L["reward"]
			if quest and quest.instance and LG:InstanceInfo(quest.instance) then
				local text = ("%s  " .. E:TextHex("secondary") .. "%s · %s|r"):format(title, tag, LG:InstanceInfo(quest.instance).name)
				P.FlowLine(flow, text, function() LG:Open("journal", { key = quest.instance, quest = entry.id }) end, nil,
					title, function(tip) Kit.TooltipHint(tip, { L["Click"], L["open it in the Journal"] }) end)
			else
				local giver = quest and quest.starts[1]
				local meta = { tag }
				if quest and quest.level and quest.level > 0 then meta[#meta + 1] = (L["level %d"]):format(quest.level) end
				local faction = LG:QuestSide(entry.id)
				if faction then meta[#meta + 1] = faction end
				local giverName
				if giver and giver.kind == "npc" then
					local mob = LG:Mob(giver.id)
					giverName = mob and mob.name
					local camps = LG:SpawnPoints("npc", giver.id)
					local zone = camps[1] and LG:SpawnZone(camps[1])
					if giverName then meta[#meta + 1] = giverName end
					if zone then meta[#meta + 1] = zone end
				end
				local dim = status == "notforyou"
				local text = (dim and E:TextHex("dim") or "") .. title .. (dim and "|r" or "") .. "  " .. E:TextHex("secondary") .. table.concat(meta, " · ") .. "|r"
				local button = giver and giver.kind ~= "item" and P.MapButton(giver.kind, giver.id, giverName or title) or nil
				local id = entry.id
				P.FlowLine(flow, text, function() LG:Open("detail", { quest = id }) end, button, title,
					function(tip) E.UIKit.TipText(tip, LG.QUEST_STATUS_TITLE[status] .. ".") Kit.TooltipHint(tip, { L["Click"], L["see the quest"] }) end)
			end
		end
	end
	if #other > 0 then
		P.FlowCaption(flow, L["Other sources"], tostring(#other))
		for _, entry in ipairs(other) do
			local text = P.SourceLine(entry)
			if entry.price and P.MoneyText(entry.price) then text = text .. "  " .. P.MoneyText(entry.price) end
			P.FlowLine(flow, text, nil)
		end
	end
	if #sources == 0 then
		P.FlowCaption(flow, L["Sources"])
		P.FlowText(flow, LG:HasData() and L["No known source. It may be new in WoW: Forever or come from something the data does not cover."]
			or L["No known source. Install EldoUI_LootData for Classic drop tables and quest rewards."], 12, "secondary")
	end
	if (more or 0) > 0 then
		P.FlowText(flow, E:Plural(more, "%d more source with a small chance is not listed.", "%d more sources with small chances are not listed."):format(more), 11, "secondary")
	end
	local note = LG:ItemNote(itemID)
	if note then
		P.FlowCaption(flow, L["Note"])
		P.FlowText(flow, note, 12, "secondary")
	end
	flow:Space(8)
	P.FlowText(flow, L["Drop chances are Classic values from EldoUI_LootData; WoW: Forever may differ. \"seen\" counts are your own kills."], 10, "dim")
	flow:Finish()
end

local function CreateItem(parent)
	local page = CreateFrame("Frame", nil, parent)
	page:SetAllPoints()
	local side = CreateFrame("Frame", nil, page)
	side:SetPoint("TOPLEFT")
	side:SetPoint("BOTTOMLEFT")
	side:SetWidth(SIDEBAR)
	E:SetTemplate(side, true)
	page.side = side
	side.back = Back(side)
	side.back:SetPoint("TOPLEFT", 10, -8)
	side.icon = P.Art(side, 48)
	side.icon:SetPoint("TOPLEFT", 10, -32)
	side.icon:EnableMouse(true)
	side.icon:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(page.itemID)
		GameTooltip:Show()
	end)
	side.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
	side.name = Kit.Text(side, 14, "LEFT")
	side.name:SetPoint("TOPLEFT", side.icon, "BOTTOMLEFT", 0, -8)
	side.name:SetPoint("TOPRIGHT", -10, -(32 + 48 + 8)) -- under the 48 px icon
	side.info = Kit.Text(side, 11, "LEFT", "secondary")
	side.info:SetPoint("TOPLEFT", side.name, "BOTTOMLEFT", 0, -6)
	side.info:SetPoint("TOPRIGHT", side.name, "BOTTOMRIGHT", 0, -6)
	side.info:SetSpacing(3)
	side.wish = Kit.Button(side, L["Add to wishlist"], SIDEBAR - 20, 22, function()
		LG:ToggleWished(page.itemID)
	end, L["Wishlist"], L["Adds the item to your active wishlist, or takes it off every list on show."])
	side.wish:SetPoint("TOPLEFT", side.info, "BOTTOMLEFT", 0, -14)
	side.tryOn = Kit.Button(side, L["Try on"], SIDEBAR - 20, 22, function()
		if page.link and DressUpItemLink then DressUpItemLink(page.link) end
	end, L["Try on"], L["Shows the item on your character in the dressing room."])
	side.tryOn:SetPoint("TOPLEFT", side.wish, "BOTTOMLEFT", 0, -6)
	page.pill = P.Pill(page)
	page.pill:SetPoint("TOPLEFT", side, "TOPRIGHT", 12, 0)
	page.flow = P.Flow(page)
	page.flow:SetPoint("TOPLEFT", side, "TOPRIGHT", 12, -24)
	page.flow:SetPoint("BOTTOMRIGHT")
	return page
end

LG:RegisterPage("item", {
	title = "Item",
	desc = "Every way to get one item.",
	order = 91,
	hidden = true,
	create = CreateItem,
	show = function(page, arg)
		page.itemID = tonumber(arg) or page.itemID
		if page.itemID then DrawItem(page) end
	end,
	refresh = function(page, changed)
		if page.itemID and (changed.items or changed.wishlist or changed.data or changed.quests or changed.settings) then DrawItem(page) end
	end,
	empty = function(page)
		if not page.itemID then
			return L["No item picked"], L["Open an item from Search, the Journal or your wishlist."], LG.ICON
		end
	end,
})

---------------------------------------------------------------------------
-- Detail page: a quest outside dungeons, or a creature and its drops.
---------------------------------------------------------------------------
local function MobLoot(npc)
	local LD = select(3, LG:DataStatus())
	local rows = {}
	local packed = LD and LD.loot and LD.loot[npc]
	for item, chance in tostring(packed or ""):gmatch("(%d+):(%-?[%d%.]+)") do
		local value, questOnly = LG.ParseChance(chance)
		local data = P.ChanceData(value, npc, tonumber(item))
		rows[#rows + 1] = { itemID = tonumber(item), chance = data.chance, seen = data.seen,
			sub = questOnly and L["Only while on the quest"] or nil }
	end
	table.sort(rows, function(a, b) return (a.chance or -1) > (b.chance or -1) end)
	return rows
end

local function DrawMob(page, npc)
	local flow = page.flow
	flow:Begin()
	local mob = LG:Mob(npc)
	local name = mob and mob.name or L["NPC %s"]:format(npc)
	P.FlowText(flow, name, 16, nil, 0, 2)
	local bits = {}
	if mob and mob.minLevel then
		bits[#bits + 1] = mob.minLevel == mob.maxLevel and (L["Level %d"]):format(mob.minLevel)
			or (L["Level %d-%d"]):format(mob.minLevel, mob.maxLevel or mob.minLevel)
	end
	if mob and P.RANK[mob.rank or 0] then bits[#bits + 1] = P.RANK[mob.rank] end
	if mob and mob.instance and LG:InstanceInfo(mob.instance) then bits[#bits + 1] = LG:InstanceInfo(mob.instance).name end
	local camps = LG:SpawnPoints("npc", npc)
	local zone = camps[1] and LG:SpawnZone(camps[1])
	if zone then bits[#bits + 1] = zone end
	P.FlowLine(flow, E:TextHex("secondary") .. table.concat(bits, "  ·  ") .. "|r", nil, P.MapButton("npc", npc, name))
	local rows = MobLoot(npc)
	P.FlowCaption(flow, L["Drops"], tostring(#rows))
	if #rows == 0 then P.FlowText(flow, L["No drops known for this creature."], 12, "secondary") end
	for _, row in ipairs(rows) do
		local quality = P.Quality(row.itemID) or 1
		if quality >= (tonumber(LG.db.minQuality) or 0) then
			local itemID = row.itemID
			row.onClick = function() LG:Open("item", itemID) end
			P.FlowItem(flow, row)
		end
	end
	flow:Finish()
end

local function CreateDetail(parent)
	local page = CreateFrame("Frame", nil, parent)
	page:SetAllPoints()
	page.back = Back(page)
	page.back:SetPoint("TOPLEFT")
	page.flow = P.Flow(page)
	page.flow:SetPoint("TOPLEFT", 0, -24)
	page.flow:SetPoint("BOTTOMRIGHT")
	page.quest = P.QuestDetail(page)
	page.quest:SetPoint("TOPLEFT", 0, -24)
	page.quest:SetPoint("BOTTOMRIGHT")
	page.quest.onOpen = function(questID)
		local quest = LG:Quest(questID)
		if quest and quest.instance and LG:InstanceInfo(quest.instance) then
			LG:Open("journal", { key = quest.instance, quest = questID })
		else
			LG:Open("detail", { quest = questID })
		end
	end
	return page
end

local function DrawDetail(page)
	local arg = page.arg or {}
	local _, _, backLabel = BackTarget()
	page.back:SetLabel(backLabel)
	page.quest:SetShown(arg.quest ~= nil)
	page.flow:SetShown(arg.quest == nil)
	if arg.quest then
		page.quest:SetQuest(arg.quest)
	elseif arg.npc then
		DrawMob(page, arg.npc)
	end
end

LG:RegisterPage("detail", {
	title = "Details",
	desc = "A quest outside dungeons, or a creature and what it drops.",
	order = 92,
	hidden = true,
	create = CreateDetail,
	show = function(page, arg)
		if type(arg) == "table" then page.arg = arg end
		DrawDetail(page)
	end,
	refresh = function(page, changed)
		if changed.items or changed.data or changed.quests or changed.wishlist or changed.questRewards then DrawDetail(page) end
	end,
	empty = function(page)
		if not (page.arg and (page.arg.quest or page.arg.npc)) then
			return L["Nothing picked"], L["Open a quest or a creature from Search or an item page."], LG.ICON
		end
	end,
})
