-- EldoUI Loot Guide: the Journal page.
--
-- Home: Dungeons / Raids, "My level only", a card for the best instance
-- for you, then tiles for your level, coming up, the rest and the
-- dungeons only WoW: Forever knows.
--
-- Instance: back link, art, name, level, zone and size, Entrance (map pin
-- at the entrance). Left: Bosses / Quests with counts. Bosses: one row per
-- boss (portrait, number, level, rare tag, upgrades), "Trash and zone
-- drops" and "Quest rewards"; right: the loot with filters, the boss model
-- (drag to turn; hidden with compact rows) and designed empty states.
-- Quests: the quest list by status and the quest detail (QuestPane.lua).
--
-- The last instance per kind, the tab, the filters, the loot order (by
-- chance or grouped by kind), the chain view and the faction filter are
-- window state, saved per character without an option.
local _, E = ...
local LG = E.LootGuide
local Kit = LG.Kit
local P = LG.PageKit
local L = E.L

local Key = E.Key
local LEFT_WIDTH = 240
local MODEL_WIDTH = 170
local TOP = 26

-- One extra line in an instance's header from another module (the
-- Attunements tab: "Attunement: 3 of 4 steps"). fn(instanceKey) returns
-- nil or { text, tipTitle, tip, onClick }; the first answer shows.
local headerExtras, headerExtraOrder = {}, {}
function P.AddInstanceHeaderExtra(key, fn)
	if not headerExtras[key] then headerExtraOrder[#headerExtraOrder + 1] = key end
	headerExtras[key] = fn
end

-- More views of an instance beside Bosses and Quests (My Adventure's
-- History tab). def = { label, tip, order, shown = fn(instanceKey) -> bool,
-- count = fn(instanceKey) -> n or nil, build = fn(parent, page) -> frame,
-- draw = fn(frame, instanceKey) }. The view fills the area under the
-- switch (left list and right pane). LG:Open("journal", { key, mode = key })
-- opens it.
local modes, modeOrder = {}, {}
function P.AddInstanceMode(key, def)
	if type(key) ~= "string" or type(def) ~= "table" or key == "bosses" or key == "quests" then return end
	if not modes[key] then modeOrder[#modeOrder + 1] = key end
	def.key = key
	-- label and tip may be English keys: reading them gives the language shown.
	E:TranslateFields({ def }, "label", "tip")
	modes[key] = def
	table.sort(modeOrder, function(a, b)
		local oa, ob = tonumber(modes[a].order) or 50, tonumber(modes[b].order) or 50
		if oa ~= ob then return oa < ob end
		return a < b
	end)
end

local function ModeShown(key, instance)
	local def = modes[key]
	if not def then return false end
	if not def.shown then return true end
	local ok, shown = pcall(def.shown, instance)
	if not ok then geterrorhandler()(shown) end
	return ok and shown and true or false
end

local function HeaderExtra(instance)
	for _, key in ipairs(headerExtraOrder) do
		local ok, extra = pcall(headerExtras[key], instance)
		if ok and type(extra) == "table" and extra.text then return extra end
		if not ok then geterrorhandler()(extra) end
	end
end

local function State()
	local ui = LG:UI()
	if type(ui.journal) ~= "table" then ui.journal = {} end
	local s = ui.journal
	if s.kind ~= "raid" then s.kind = "dungeon" end
	if type(s.last) ~= "table" then s.last = {} end
	if s.mode ~= "quests" and not modes[s.mode] then s.mode = "bosses" end
	if not P.FACTION_TITLE[s.faction or ""] then s.faction = "mine" end
	if s.lootOrder ~= "kind" then s.lootOrder = "chance" end
	if s.chainView ~= "list" then s.chainView = "chart" end
	return s
end
P.JournalState = State

---------------------------------------------------------------------------
-- Instance order (shared with For You): most upgrades, then most open
-- quests, then the lower level, then the name. The pool: instances near
-- your level; when none, the next three coming up.
---------------------------------------------------------------------------
function P.RankInstances(raids, level)
	level = level or LG:Player().level
	local near, upcoming = {}, {}
	for _, info in ipairs(LG:Catalog()) do
		local kindOK = info.kind == "dungeon" or (raids and info.kind == "raid")
		if kindOK and LG:OpenNow(info) then
			local fit = LG:FitsLevel(info, level)
			if fit == "fit" or fit == "near" then
				near[#near + 1] = info
			elseif fit == "up" then
				upcoming[#upcoming + 1] = info
			end
		end
	end
	local pool = near
	if #pool == 0 then
		table.sort(upcoming, function(a, b)
			if (a.min or 0) ~= (b.min or 0) then return (a.min or 0) < (b.min or 0) end
			return a.name < b.name
		end)
		pool = { upcoming[1], upcoming[2], upcoming[3] }
	end
	local stats = {}
	for _, info in ipairs(pool) do stats[info.key] = P.InstanceStats(info.key) end
	table.sort(pool, function(a, b)
		local sa, sb = stats[a.key], stats[b.key]
		if sa.upgrades ~= sb.upgrades then return sa.upgrades > sb.upgrades end
		if sa.open ~= sb.open then return sa.open > sb.open end
		if (a.min or 0) ~= (b.min or 0) then return (a.min or 0) < (b.min or 0) end
		return a.name < b.name
	end)
	return pool, #near > 0
end

---------------------------------------------------------------------------
-- Home
---------------------------------------------------------------------------
local OpenInstance -- forward

local function TileRow(child)
	local row = CreateFrame("Frame", nil, child)
	row.tiles = {}
	for index = 1, 3 do
		row.tiles[index] = P.InstanceTile(row, function(key) OpenInstance(row.page, key) end)
	end
	row:SetScript("OnSizeChanged", function(self)
		local width = math.floor(((self:GetWidth() or 600) - 16) / 3)
		for index, tile in ipairs(self.tiles) do
			tile:ClearAllPoints()
			tile:SetPoint("TOPLEFT", (index - 1) * (width + 8), 0)
			tile:SetWidth(width)
		end
	end)
	return row
end

local function PlaceTiles(page, flow, list)
	for start = 1, #list, 3 do
		local row = flow:Take("tiles", TileRow)
		row.page = page
		flow:Place(row, 64, 0, 8)
		local width = math.floor((flow:Width() - 16) / 3)
		for index, tile in ipairs(row.tiles) do
			tile:ClearAllPoints()
			tile:SetPoint("TOPLEFT", (index - 1) * (width + 8), 0)
			tile:SetWidth(width)
			local info = list[start + index - 1]
			if info then tile:SetInstance(info.key) else tile:Hide() end
		end
	end
end

local function DrawHome(page)
	local s = State()
	local home = page.home
	home.dungeons:SetOn(s.kind == "dungeon")
	home.raids:SetOn(s.kind == "raid")
	home.levelOnly:SetOn(s.levelOnly)
	local flow = home.flow
	flow:Begin()
	local level = LG:Player().level
	local groups = { fit = {}, up = {}, below = {}, forever = {}, later = {} }
	local total = 0
	for _, info in ipairs(LG:Catalog()) do
		if info.kind == s.kind then
			total = total + 1
			local fit = LG:FitsLevel(info, level)
			local mine = fit == "fit" or fit == "near"
			if not s.levelOnly or mine then
				if info.status == "notforever" then
					table.insert(groups.later, info)
				elseif info.status ~= "classic" then
					table.insert(groups.forever, info)
				elseif mine then
					table.insert(groups.fit, info)
				elseif fit == "up" then
					table.insert(groups.up, info)
				else
					table.insert(groups.below, info)
				end
			end
		end
	end
	home.count:SetText(total > 0 and (L["%d known"]):format(total) or "")
	local best = P.RankInstances(s.kind == "raid", level)
	local feature
	for _, info in ipairs(best) do
		if info.kind == s.kind then feature = info break end
	end
	if feature then
		P.FlowCaption(flow, L["Best for you now"], L["most upgrades, then most open quests"])
		local card = flow:Take("feature", function(child) return P.InstanceTile(child, function(key) OpenInstance(page, key) end) end)
		flow:Place(card, 64, 0, 8)
		card:SetInstance(feature.key)
	end
	local sections = {
		{ "fit", L["For your level"] }, { "up", L["Coming up"] }, { "below", L["Below your level"] },
		{ "forever", L["WoW: Forever"] }, { "later", L["Not in WoW: Forever yet"] },
	}
	local any = false
	for _, section in ipairs(sections) do
		local list = groups[section[1]]
		if #list > 0 then
			any = true
			table.sort(list, function(a, b)
				if (a.min or 0) ~= (b.min or 0) then return (a.min or 0) < (b.min or 0) end
				return a.name < b.name
			end)
			P.FlowCaption(flow, section[2], tostring(#list))
			PlaceTiles(page, flow, list)
		end
	end
	if not any and total > 0 then
		P.FlowText(flow, L["Nothing here fits your level."], 12, "secondary")
		P.FlowLine(flow, "", nil, { L["Show all"], function()
			State().levelOnly = false
			DrawHome(page)
		end, L["Show all"], L["Turns off My level only."] })
	end
	flow:Finish()
end

local function BuildHome(page)
	local home = CreateFrame("Frame", nil, page)
	home:SetAllPoints()
	page.home = home
	home.dungeons = P.Toggle(home, L["Dungeons"], function()
		State().kind = "dungeon"
		DrawHome(page)
	end, L["Dungeons"], L["Five-player dungeons and their wings."])
	home.dungeons:SetPoint("TOPLEFT", 0, 0)
	home.raids = P.Toggle(home, L["Raids"], function()
		State().kind = "raid"
		DrawHome(page)
	end, L["Raids"], L["Raids and the world bosses."])
	home.raids:SetPoint("LEFT", home.dungeons, "RIGHT", 4, 0)
	home.count = Kit.Text(home, 11, "LEFT", "secondary")
	home.count:SetPoint("LEFT", home.raids, "RIGHT", 10, 0)
	home.levelOnly = P.Toggle(home, L["My level only"], function()
		local s = State()
		s.levelOnly = not s.levelOnly
		DrawHome(page)
	end, L["My level only"], L["Shows only instances within the level window of yours (Loot Guide settings)."])
	home.levelOnly:SetPoint("TOPRIGHT", 0, 0)
	home.flow = P.Flow(home)
	home.flow:SetPoint("TOPLEFT", 0, -TOP)
	home.flow:SetPoint("BOTTOMRIGHT")
	home.flow.onResize = function()
		if home:IsVisible() then DrawHome(page) end
	end
end

---------------------------------------------------------------------------
-- Instance: left list
---------------------------------------------------------------------------
local function BossRowCreate(row)
	row.select = row:CreateTexture(nil, "BACKGROUND")
	row.select:SetAllPoints()
	E:AccentTexture(row.select, 0.15)
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	row.number = Kit.Text(row, 11, "CENTER", "secondary")
	row.number:SetPoint("LEFT", 2, 0)
	row.number:SetWidth(16)
	row.portrait = row:CreateTexture(nil, "ARTWORK")
	row.portrait:SetSize(26, 26)
	row.portrait:SetPoint("LEFT", row.number, "RIGHT", 2, 0)
	row.right = Kit.Text(row, 11, "RIGHT")
	row.right:SetPoint("RIGHT", -4, 0)
	row.name = Kit.Text(row, 12, "LEFT")
	-- The 26 px portrait and the right text sit on the row's middle.
	row.name:SetPoint("TOPLEFT", row.portrait, "TOPRIGHT", 6, 0)
	row.name:SetPoint("TOPRIGHT", row.right, "LEFT", -4, 13)
	row.name:SetWordWrap(false)
	row.sub = Kit.Text(row, 10, "LEFT", "secondary")
	row.sub:SetPoint("BOTTOMLEFT", row.portrait, "BOTTOMRIGHT", 6, 0)
	row.sub:SetPoint("BOTTOMRIGHT", row.right, "LEFT", -4, -13)
	row.sub:SetWordWrap(false)
	row:SetScript("OnEnter", function(self)
		local item = self.item
		if not item then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		E.UIKit.TipTitle(GameTooltip, item.title)
		if item.sub and item.sub ~= "" then GameTooltip:AddLine(item.sub, unpack(Kit.SECONDARY)) end
		if item.upgrades and item.upgrades > 0 then
			GameTooltip:AddLine(E:Plural(item.upgrades, "%d upgrade for you", "%d upgrades for you"):format(item.upgrades), unpack(Kit.GOOD))
		end
		if item.wished and item.wished > 0 and LG:WishlistOn() then
			GameTooltip:AddLine((L["%d on your wishlist"]):format(item.wished), E:TokenColor("accent"))
		end
		E:TooltipHint(GameTooltip, { L["Click"], L["the loot"] })
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnClick", function(self)
		local page = self.list.page
		State().boss = self.item.select
		page:DrawLoot()
		self.list:Refresh()
	end)
end

local function Counts(items)
	local up, wished = 0, 0
	for _, drop in ipairs(items) do
		if LG:IsWished(drop.itemID) then wished = wished + 1 end
		if P.IsUpgrade(drop.itemID) and (LG:UseLevel(drop.itemID) or 1) <= LG:Player().level + 3 then up = up + 1 end
	end
	return up, wished
end

local function BossRowUpdate(row, item)
	row.select:SetShown(State().boss == item.select)
	row.number:SetText(item.number and tostring(item.number) or "")
	local portrait = false
	if item.boss and item.boss.display and SetPortraitTextureFromCreatureDisplayID then
		local ok = pcall(SetPortraitTextureFromCreatureDisplayID, row.portrait, item.boss.display)
		portrait = ok
	end
	if not portrait then
		row.portrait:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_Head_Dragon_01")
		E:TrimIcon(row.portrait)
	else
		row.portrait:SetTexCoord(0, 1, 0, 1)
	end
	row.name:SetText(item.title)
	row.sub:SetText(item.sub or "")
	local bits = {}
	if item.upgrades and item.upgrades > 0 then bits[#bits + 1] = Kit.Hex(unpack(Kit.GOOD)) .. "+" .. item.upgrades .. "|r" end
	if item.wished and item.wished > 0 and LG:WishlistOn() then bits[#bits + 1] = E:TextHex("accent") .. "*" .. item.wished .. "|r" end
	row.right:SetText(table.concat(bits, " "))
end

local function RewardItems(key, faction)
	local items, seen = {}, {}
	for _, questID in ipairs(LG:InstanceQuestIDs(key)) do
		local quest = LG:Quest(questID)
		if quest and LG:QuestForFaction(questID, faction) then
			for _, list in ipairs({ { quest.rewards, L["Reward"] }, { quest.choice, L["Choice"] } }) do
				for _, reward in ipairs(list[1]) do
					if not seen[reward.id] then
						seen[reward.id] = true
						items[#items + 1] = { itemID = reward.id, tag = list[2], quest = questID, sub = quest.title }
					end
				end
			end
		end
	end
	return items
end

-- Bosses, trash and rewards for the left list.
local function BossItems(key)
	local loot = LG:InstanceLoot(key)
	local items = {}
	for index, boss in ipairs(loot.bosses) do
		local up, wished = Counts(boss.loot)
		local bits = {}
		if boss.level then bits[#bits + 1] = (L["Level %d"]):format(boss.level) end
		if boss.rare then bits[#bits + 1] = Kit.Hex(unpack(Kit.WARN)) .. L["Rare spawn"] .. "|r" end
		items[#items + 1] = { select = index, number = index, boss = boss, title = boss.name, sub = table.concat(bits, "  ·  "),
			upgrades = up, wished = wished }
	end
	if #loot.trash > 0 then
		local up, wished = Counts(loot.trash)
		items[#items + 1] = { select = "trash", title = L["Trash and zone drops"], sub = E:Plural(#loot.trash, "%d item", "%d items"):format(#loot.trash),
			icon = "Interface\\Icons\\INV_Misc_Bag_10", upgrades = up, wished = wished }
	end
	local rewards = RewardItems(key, State().faction)
	if #rewards > 0 then
		local up, wished = Counts(rewards)
		items[#items + 1] = { select = "rewards", title = L["Quest rewards"], sub = E:Plural(#rewards, "%d item", "%d items"):format(#rewards),
			icon = "Interface\\GossipFrame\\AvailableQuestIcon", upgrades = up, wished = wished }
	end
	return items, #loot.bosses
end

---------------------------------------------------------------------------
-- Instance: loot panel
---------------------------------------------------------------------------
-- The data's quality first (no item load needed), else the game's.
local function Quality(itemID)
	local record = LG:ItemRecord(itemID)
	if record and record.quality then return record.quality end
	local _, _, quality = C_Item.GetItemInfo(itemID)
	if P.Secret(quality) then return nil end
	return quality
end
P.Quality = Quality

local function Usable(itemID)
	local record = LG:ItemRecord(itemID)
	if record then return (LG:CanUseRecord(record)) and true or false end
	local _, link = C_Item.GetItemInfo(itemID)
	if not P.Secret(link) and link and E.ItemScore and E.ItemScore.IsUsable then
		local ok, result = pcall(E.ItemScore.IsUsable, E.ItemScore, link)
		if ok and result == false then return false end
	end
	return true
end

-- The loot rows for the selection: { itemID, chance, seen, badge, sub, tag }.
local function LootFor(key, select)
	local loot = LG:InstanceLoot(key)
	local rows = {}
	if select == "trash" then
		for _, drop in ipairs(loot.trash) do
			local data = P.ChanceData(drop.chance, drop.npc, drop.itemID)
			local mob = LG:Mob(drop.npc)
			rows[#rows + 1] = { itemID = drop.itemID, chance = data.chance, seen = data.seen, sub = mob and mob.name,
				questOnly = drop.questOnly }
		end
	elseif select == "rewards" then
		rows = RewardItems(key, State().faction)
	else
		local boss = loot.bosses[tonumber(select) or 1]
		if not boss then return rows, nil end
		local known = {}
		for _, drop in ipairs(boss.loot) do
			known[drop.itemID] = true
			local data = P.ChanceData(drop.chance, boss.npc, drop.itemID)
			rows[#rows + 1] = { itemID = drop.itemID, chance = data.chance, seen = data.seen,
				sub = drop.questOnly and L["Only while on the quest"] or nil, questOnly = drop.questOnly }
		end
		-- Drops you saw that the data does not list.
		local seen, kills = LG:SeenItems(boss.npc)
		for itemID, drops in pairs(seen or {}) do
			itemID = tonumber(itemID)
			if itemID and not known[itemID] then
				rows[#rows + 1] = { itemID = itemID, seen = (L["seen %d/%d"]):format(tonumber(drops) or 0, kills or 0),
					badge = Kit.Hex(unpack(Kit.WARN)) .. L["Forever"] .. "|r" }
			end
		end
		-- A WoW: Forever boss: what you saw it drop for your group.
		for itemID, drops in pairs(boss.seenLoot or {}) do
			itemID = tonumber(itemID)
			if itemID and not known[itemID] then
				known[itemID] = true
				rows[#rows + 1] = { itemID = itemID, seen = (L["seen %d/%d"]):format(tonumber(drops) or 0, tonumber(boss.kills) or 0),
					badge = Kit.Hex(unpack(Kit.WARN)) .. L["Forever"] .. "|r" }
			end
		end
		return rows, boss
	end
	return rows, nil
end

local function SortLoot(rows)
	table.sort(rows, function(a, b)
		local ca, cb = a.chance or -1, b.chance or -1
		if ca ~= cb then return ca > cb end
		return a.itemID < b.itemID
	end)
end

-- By kind: quest items (drops only while on the quest), weapons, armor,
-- accessories (neck, finger, trinket, back), then the rest. The data's
-- item record first, else the game's instant item info.
local KINDS = {
	{ key = "quest", title = Key("Quest items") }, { key = "weapon", title = Key("Weapons") },
	{ key = "armor", title = Key("Armor") }, { key = "accessory", title = Key("Accessories") },
	{ key = "other", title = Key("Other") },
}
local ACCESSORY = { neck = true, finger = true, trinket = true, back = true }

local function LootKind(row)
	if row.questOnly then return "quest" end
	local group = LG:SlotGroup(row.itemID)
	if ACCESSORY[group or ""] then return "accessory" end
	local record = LG:ItemRecord(row.itemID)
	local class = record and record.class
	if not record then
		local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(row.itemID)
		if not P.Secret(classID) then class = tonumber(classID) end
	end
	if class == 2 then return "weapon" end
	if class == 4 and group then return "armor" end
	return "other"
end
P.LootKind = LootKind

-- Sorted rows -> the same rows under a header per kind (empty kinds left
-- out); the order inside a kind stays as it was.
local function GroupByKind(rows)
	local buckets = {}
	for _, row in ipairs(rows) do
		local kind = LootKind(row)
		buckets[kind] = buckets[kind] or {}
		table.insert(buckets[kind], row)
	end
	local out = {}
	for _, kind in ipairs(KINDS) do
		local list = buckets[kind.key]
		if list then
			out[#out + 1] = { header = L[kind.title], kind = kind.key, count = #list }
			for _, row in ipairs(list) do out[#out + 1] = row end
		end
	end
	return out
end

local function Filter(rows)
	local s = State()
	local minQuality = tonumber(LG.db.minQuality) or 0
	local out = {}
	for _, row in ipairs(rows) do
		local quality = Quality(row.itemID)
		local keep = not quality or quality >= minQuality or row.tag ~= nil
		if keep and s.usable and not Usable(row.itemID) then keep = false end
		if keep and s.upgrades and LG:BiSOn() and not P.IsUpgrade(row.itemID) then keep = false end
		if keep then out[#out + 1] = row end
	end
	return out
end

local function BuildModel(parent)
	local model = CreateFrame("PlayerModel", nil, parent)
	model:EnableMouse(true)
	model.facing = 0
	model:SetScript("OnMouseDown", function(self)
		self.dragX = GetCursorPosition()
		self:SetScript("OnUpdate", function(own)
			local x = GetCursorPosition()
			own.facing = own.facing + (x - (own.dragX or x)) / 80
			own.dragX = x
			own:SetFacing(own.facing)
		end)
	end)
	model:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
	model:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
	Kit.Tooltip(model, L["Boss model"], L["Drag to turn it."])
	return model
end

local function BuildLoot(page)
	local pane = CreateFrame("Frame", nil, page.inst)
	page.loot = pane
	pane.title = Kit.Text(pane, 15, "LEFT")
	pane.title:SetPoint("TOPLEFT", 0, 0)
	pane.title:SetPoint("TOPRIGHT", -4, 0)
	pane.title:SetWordWrap(false)
	pane.sub = Kit.Text(pane, 11, "LEFT", "secondary")
	pane.sub:SetPoint("TOPLEFT", pane.title, "BOTTOMLEFT", 0, -3)
	pane.sub:SetPoint("TOPRIGHT", pane.title, "BOTTOMRIGHT", 0, -3)
	pane.sub:SetWordWrap(false)
	pane.usable = P.Toggle(pane, L["Usable by me"], function()
		local s = State()
		s.usable = not s.usable
		page:DrawLoot()
	end, L["Usable by me"], L["Hides items your class cannot use (armor kind, weapon, class)."])
	pane.usable:SetPoint("TOPLEFT", pane.sub, "BOTTOMLEFT", 0, -6)
	pane.upgrades = P.Toggle(pane, L["Upgrades only"], function()
		local s = State()
		s.upgrades = not s.upgrades
		page:DrawLoot()
	end, L["Upgrades only"], L["Shows only items that beat what you wear, rated by the shared item engine."])
	pane.upgrades:SetPoint("LEFT", pane.usable, "RIGHT", 4, 0)
	-- The order: by chance, or grouped by kind (each kind by chance).
	pane.byChance = P.Toggle(pane, L["By chance"], function()
		State().lootOrder = "chance"
		page:DrawLoot()
	end, L["By chance"], L["One list, the most likely drop first."])
	pane.byKind = P.Toggle(pane, L["By kind"], function()
		State().lootOrder = "kind"
		page:DrawLoot()
	end, L["By kind"], L["Quest items, weapons, armor, accessories and the rest, each with the most likely drop first."])
	pane.byKind:SetPoint("LEFT", pane.byChance, "RIGHT", 4, 0)
	pane.model = BuildModel(pane)
	pane.model:SetPoint("TOPRIGHT", 0, -44)
	pane.model:SetSize(MODEL_WIDTH, 240)
	pane.list = Kit.CreateList(pane, {
		create = function(row)
			row.cell = P.ItemCell(row)
			row.cell:SetAllPoints()
			row.head = Kit.Text(row, 11, "LEFT")
			row.head:SetPoint("LEFT", 2, -2)
			row.head:SetPoint("RIGHT", -4, -2)
			row.head:SetWordWrap(false)
		end,
		update = function(row, item)
			if item.header then
				row.cell:Hide()
				row.head:Show()
				row.head:SetText(E:TextHex("accent") .. E:CaptionText(item.header) .. "|r  " .. E:TextHex("secondary") .. item.count .. "|r")
			else
				row.head:Hide()
				row.cell:Show()
				P.SetItem(row.cell, item)
			end
		end,
		gap = 2,
	})
	pane.list:SetPoint("TOPLEFT", pane.usable, "BOTTOMLEFT", 0, -8)
	pane.list:SetPoint("BOTTOMRIGHT")
	pane.empty = Kit.EmptyState(pane)
	pane.empty:ClearAllPoints()
	pane.empty:SetPoint("TOPLEFT", pane.list, "TOPLEFT")
	pane.empty:SetPoint("BOTTOMRIGHT", pane.list, "BOTTOMRIGHT")
	pane.empty:Hide()
end

---------------------------------------------------------------------------
-- Instance view
---------------------------------------------------------------------------
local function BuildInstance(page)
	local inst = CreateFrame("Frame", nil, page)
	inst:SetAllPoints()
	inst:Hide()
	page.inst = inst
	inst.back = P.Back(inst, L["All instances"], function() page:ShowHome() end)
	inst.back:SetPoint("TOPLEFT", 0, 0)
	inst.art = P.Art(inst, 40)
	inst.art:SetPoint("TOPLEFT", 0, -22)
	inst.name = Kit.Text(inst, 16, "LEFT")
	inst.name:SetPoint("TOPLEFT", inst.art, "TOPRIGHT", 10, -2)
	inst.name:SetWordWrap(false)
	inst.sub = Kit.Text(inst, 11, "LEFT", "secondary")
	inst.sub:SetPoint("TOPLEFT", inst.name, "BOTTOMLEFT", 0, -4)
	inst.sub:SetWordWrap(false)
	inst.entrance = Kit.Button(inst, L["Entrance"], 90, 22, function()
		LG:ShowEntrance(page.key)
	end, L["Entrance"], L["Pins the instance entrance on your map, turns on the arrow and opens the map there (out of combat)."])
	inst.entrance:SetPoint("TOPRIGHT", 0, -28)
	inst.map = Kit.Button(inst, L["Dungeon map"], 110, 22, function()
		if LG.OpenDungeonMap then LG:OpenDungeonMap(page.key) end
	end, L["Dungeon map"], L["Opens the map of this instance with its bosses marked."])
	inst.map:SetPoint("RIGHT", inst.entrance, "LEFT", -6, 0)
	inst.name:SetPoint("TOPRIGHT", inst.map, "TOPLEFT", -10, 4) -- the name's top is 4 above the buttons'
	inst.sub:SetPoint("TOPRIGHT", inst.name, "BOTTOMRIGHT", 0, -4)
	inst.rule = Kit.Divider(inst)
	inst.rule:SetPoint("TOPLEFT", 0, -68)
	inst.rule:SetPoint("TOPRIGHT", 0, -68)
	inst.extra = CreateFrame("Button", nil, inst)
	inst.extra:SetSize(200, 14)
	inst.extra:SetPoint("TOPRIGHT", 0, -52)
	inst.extra.text = Kit.Text(inst.extra, 11, "RIGHT", "secondary")
	inst.extra.text:SetAllPoints()
	inst.extra:SetScript("OnEnter", function(self) self.text:SetTextColor(E:TokenColor("accent")) end)
	inst.extra:SetScript("OnLeave", function(self) Kit.Paint(self.text, "secondary") end)
	inst.extra:Hide()

	-- Left: switch and list.
	local left = CreateFrame("Frame", nil, inst)
	left:SetPoint("TOPLEFT", 0, -76)
	left:SetPoint("BOTTOMLEFT")
	left:SetWidth(LEFT_WIDTH)
	inst.left = left
	left.bosses = P.Toggle(left, L["Bosses"], function() page:SetMode("bosses") end, L["Bosses"],
		L["Bosses, trash drops and quest rewards of this instance."])
	left.bosses:SetPoint("TOPLEFT")
	left.quests = P.Toggle(left, L["Quests"], function() page:SetMode("quests") end, L["Quests"],
		L["The quests for this instance with your status: open, done or locked."])
	left.quests:SetPoint("LEFT", left.bosses, "RIGHT", 4, 0)
	left.faction = P.Toggle(left, P.FACTION_TITLE.mine, function(self)
		P.FactionMenu(self, State().faction, function(key)
			State().faction = key
			page:DrawLeft()
			if State().mode == "bosses" then page:DrawLoot() elseif State().mode == "quests" then page.detail:Redraw(true) end
		end)
	end, L["Faction"], L["Whose quests the list shows: yours, Alliance, Horde or both."])
	left.faction:SetPoint("TOPRIGHT")
	left.list = Kit.CreateList(left, { rowHeight = 34, create = BossRowCreate, update = BossRowUpdate, gap = 2 })
	left.list.page = page
	left.list:SetPoint("TOPLEFT", 0, -26)
	left.list:SetPoint("BOTTOMRIGHT")
	left.quest = Kit.CreateList(left, {
		create = function(row)
			P.QuestRowCreate(row)
			row:SetScript("OnClick", function(self)
				if self.item and self.item.row then
					State().quest = self.item.row.id
					page.detail:SetQuest(self.item.row.id)
					self.list:Refresh()
				end
			end)
		end,
		update = function(row, item) P.QuestRowUpdate(row, item, State().quest) end,
		gap = 1,
	})
	left.quest:SetPoint("TOPLEFT", 0, -26)
	left.quest:SetPoint("BOTTOMRIGHT")
	left.none = Kit.Text(left, 12, "LEFT", "secondary")
	left.none:SetPoint("TOPLEFT", 4, -32)
	left.none:SetPoint("TOPRIGHT", -4, -32)
	left.none:SetWordWrap(true)

	BuildLoot(page)
	page.loot:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, 0)
	page.loot:SetPoint("BOTTOMRIGHT")
	page.detail = P.QuestDetail(inst)
	page.detail:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, 0)
	page.detail:SetPoint("BOTTOMRIGHT")
	page.detail.onOpen = function(questID) page:OpenQuest(questID) end
	page.detail.faction = function() return State().faction end
	page.detail:Hide()
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local Page = {}

function Page:ShowHome()
	State().view = "home"
	self.inst:Hide()
	self.home:Show()
	DrawHome(self)
end

function Page:DrawHeader()
	local info = LG:InstanceInfo(self.key)
	local inst = self.inst
	inst.art.icon:SetTexture((LG:InstanceArt(self.key)))
	inst.art.icon:SetDesaturated(not LG:OpenNow(info))
	inst.name:SetText(info.name)
	local bits = { P.LevelText(info), P.SizeText(info) }
	local zone = LG:InstanceZone(self.key)
	if zone then bits[#bits + 1] = zone end
	if info.enterLevel then bits[#bits + 1] = (L["enter from level %d"]):format(info.enterLevel) end
	local _, confidence = LG:Confidence(self.key)
	bits[#bits + 1] = confidence
	inst.sub:SetText(table.concat(bits, "  ·  "))
	local entrance = LG:EntrancePoint(self.key)
	inst.entrance:SetShown(not info.world)
	inst.entrance:SetEnabled(entrance ~= nil)
	Kit.Tooltip(inst.entrance, L["Entrance"], entrance and (L["Pins the entrance in %s on your map and turns on the arrow."]):format(entrance.zone or "?")
		or L["The game does not tell where this entrance is."])
	inst.map:SetShown(LG.OpenDungeonMap ~= nil and not info.world)
	local extra = HeaderExtra(self.key)
	inst.extra:SetShown(extra ~= nil)
	if extra then
		inst.extra.text:SetText(extra.text)
		inst.extra:SetScript("OnClick", extra.onClick)
		Kit.Tooltip(inst.extra, extra.tipTitle, extra.tip)
	end
end

function Page:DrawLeft()
	local s = State()
	local left = self.inst.left
	local bosses, bossCount = BossItems(self.key)
	local quests, questCount = P.QuestItems(self.key, s.faction)
	self.questCount = questCount
	left.bosses:SetLabel(bossCount > 0 and (L["Bosses"] .. " " .. E:TextHex("secondary") .. bossCount .. "|r") or L["Bosses"])
	local _, open = LG:InstanceQuestCounts(self.key)
	left.quests:SetLabel(questCount > 0 and (L["Quests"] .. " " .. E:TextHex("secondary") .. (open > 0 and (open .. "/") or "") .. questCount .. "|r") or L["Quests"])
	left.bosses:SetOn(s.mode == "bosses")
	left.quests:SetOn(s.mode == "quests")
	-- The extra views' switches; with any of them the faction choice sits
	-- on its own line under the switch.
	local anchor, extra = left.quests, false
	left.modes = left.modes or {}
	for _, key in ipairs(modeOrder) do
		local def = modes[key]
		local button = left.modes[key]
		if not button then
			button = P.Toggle(left, def.label or key, function() self:SetMode(key) end, def.label or key, def.tip)
			left.modes[key] = button
		end
		local shown = ModeShown(key, self.key)
		button:SetShown(shown)
		if shown then
			extra = true
			local ok, count = false, nil
			if def.count then ok, count = pcall(def.count, self.key) end
			count = ok and tonumber(count) or nil
			button:SetLabel(count and count > 0 and ((def.label or key) .. " " .. E:TokenHex(E.tokens.text.secondary) .. count .. "|r")
				or (def.label or key))
			button:SetOn(s.mode == key)
			button:ClearAllPoints()
			button:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
			anchor = button
		end
	end
	if modes[s.mode] then
		if not ModeShown(s.mode, self.key) then s.mode = "bosses" end
	end
	left.faction:ClearAllPoints()
	left.quest:ClearAllPoints()
	if extra then
		left.faction:SetPoint("TOPLEFT", 0, -24)
		left.quest:SetPoint("TOPLEFT", 0, -48)
	else
		left.faction:SetPoint("TOPRIGHT")
		left.quest:SetPoint("TOPLEFT", 0, -26)
	end
	left.quest:SetPoint("BOTTOMRIGHT")
	left.none:ClearAllPoints()
	local noneY = (extra and s.mode == "quests") and -54 or -32
	left.none:SetPoint("TOPLEFT", 4, noneY)
	left.none:SetPoint("TOPRIGHT", -4, noneY)
	left.faction:SetLabel(P.FACTION_TITLE[s.faction])
	left.faction:SetShown(s.mode == "quests")
	left.list:SetShown(s.mode == "bosses")
	left.quest:SetShown(s.mode == "quests")
	if modes[s.mode] then
		left.none:Hide()
	elseif s.mode == "bosses" then
		local valid = false
		for _, item in ipairs(bosses) do
			if item.select == s.boss then valid = true end
		end
		if not valid then s.boss = bosses[1] and bosses[1].select or nil end
		left.list:SetData(bosses)
		left.none:SetShown(#bosses == 0)
		left.none:SetText(L["No bosses known for this instance yet."])
	else
		left.quest:SetData(quests)
		left.none:SetShown(#quests == 0)
		left.none:SetText(L["No quests known for this instance."])
	end
end

function Page:DrawLoot()
	local s = State()
	local pane = self.loot
	local info = LG:InstanceInfo(self.key)
	local loot = LG:InstanceLoot(self.key)
	local rows, boss = LootFor(self.key, s.boss)
	SortLoot(rows)
	local shown = Filter(rows)
	local bisOn = LG:BiSOn()
	pane.upgrades:SetShown(bisOn)
	pane.usable:SetOn(s.usable)
	pane.upgrades:SetOn(s.upgrades and bisOn)
	pane.byChance:ClearAllPoints()
	pane.byChance:SetPoint("LEFT", bisOn and pane.upgrades or pane.usable, "RIGHT", 12, 0)
	pane.byChance:SetOn(s.lootOrder == "chance")
	pane.byKind:SetOn(s.lootOrder == "kind")
	-- Title and line.
	local title, bits = info.name, {}
	if boss then
		title = boss.name
		if boss.rare then bits[#bits + 1] = L["Rare spawn"] else bits[#bits + 1] = (L["Boss %d of %d"]):format(s.boss, #loot.bosses) end
		if boss.level then bits[#bits + 1] = (L["Level %d"]):format(boss.level) end
	elseif s.boss == "trash" then
		title = L["Trash and zone drops"]
	elseif s.boss == "rewards" then
		title = L["Quest rewards"]
	end
	if #rows > 0 then
		bits[#bits + 1] = #shown == #rows and E:Plural(#rows, "%d drop", "%d drops"):format(#rows) or E:Plural(#rows, "%d of %d drop", "%d of %d drops"):format(#shown, #rows)
		local up = Counts(rows)
		if up > 0 and bisOn then bits[#bits + 1] = Kit.Hex(unpack(Kit.GOOD)) .. E:Plural(up, "%d upgrade", "%d upgrades"):format(up) .. "|r" end
	end
	pane.title:SetText(title)
	pane.sub:SetText(table.concat(bits, "  ·  "))
	-- Model: the boss, not with compact rows.
	local display = boss and boss.display
	local showModel = display and LG.db.density ~= "compact"
	pane.model:SetShown(showModel and true or false)
	if showModel then
		pane.model:SetDisplayInfo(display)
		pane.model:SetFacing(pane.model.facing or 0)
	end
	pane.list:ClearAllPoints()
	pane.list:SetPoint("TOPLEFT", pane.usable, "BOTTOMLEFT", 0, -8)
	pane.list:SetPoint("BOTTOMRIGHT", showModel and -(MODEL_WIDTH + 10) or 0, 0)
	pane.list:SetData(s.lootOrder == "kind" and GroupByKind(shown) or shown)
	-- Empty states.
	local empty = pane.empty
	if #shown > 0 then
		empty:Hide()
	elseif info.status == "announced" then
		empty:Set(L["Bosses not revealed yet"], L["WoW: Forever has announced this instance. Its loot shows here once it opens and drops are seen."], LG:InstanceArt(self.key))
		empty:Show()
	elseif #rows == 0 and info.forever then
		empty:Set(L["No drops recorded"], boss and L["The items you see this boss drop are added here."]
			or L["Each boss is added here when you defeat it, with the items you see it drop."], LG:InstanceArt(self.key))
		empty:Show()
	elseif #rows == 0 then
		local observed = LG:ObservedAvailable()
		empty:Set(L["No drops recorded"], observed and L["Items you see drop are added as you play."]
			or L["Items you see drop are added as you play when Mob and Loot Info is on."], LG:InstanceArt(self.key))
		empty:Show()
	else
		empty:Set(L["Nothing matches"], E:Plural(#rows, "Your filters hide %d drop.", "Your filters hide all %d drops."):format(#rows), LG.ICON, {
			{ L["Reset"], function()
				local state = State()
				state.usable, state.upgrades = false, false
				self:DrawLoot()
			end, L["Turns the filters off."] },
		})
		empty:Show()
	end
end

function Page:DrawMode()
	local s = State()
	self.modeFrames = self.modeFrames or {}
	for key, frame in pairs(self.modeFrames) do
		if key ~= s.mode then frame:Hide() end
	end
	local def = modes[s.mode]
	if not def then return end
	local frame = self.modeFrames[s.mode]
	if not frame and def.build then
		local ok, built = pcall(def.build, self.inst, self)
		if not ok then geterrorhandler()(built) end
		frame = ok and built or nil
		if frame then
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", self.inst.left, "TOPLEFT", 0, -26)
			frame:SetPoint("BOTTOMRIGHT", self.inst, "BOTTOMRIGHT")
			self.modeFrames[s.mode] = frame
		end
	end
	if not frame then return end
	frame:Show()
	if def.draw then
		local ok, err = pcall(def.draw, frame, self.key)
		if not ok then geterrorhandler()(err) end
	end
end

function Page:SetMode(mode)
	local s = State()
	if modes[mode] and not ModeShown(mode, self.key) then mode = "bosses" end
	s.mode = mode
	self:DrawLeft()
	mode = s.mode
	local custom = modes[mode] ~= nil
	self.inst.left.list:SetShown(mode == "bosses")
	self.loot:SetShown(mode == "bosses")
	self.detail:SetShown(mode == "quests")
	self:DrawMode()
	if custom then
		return
	elseif mode == "bosses" then
		self:DrawLoot()
	else
		local valid = false
		for _, item in ipairs(P.QuestItems(self.key, s.faction)) do
			if item.row and item.row.id == s.quest then valid = true end
		end
		-- A quest asked for by name (search, a chain step) stays even when
		-- the list shows its chain under another step.
		if self.keepQuest and LG:Quest(s.quest) then valid = true end
		self.keepQuest = nil
		if not valid then
			local first = P.QuestItems(self.key, s.faction)[2]
			s.quest = first and first.row and first.row.id or nil
			self.inst.left.quest:Refresh()
		end
		self.detail:SetQuest(s.quest)
	end
end

-- A quest from the chain: its own instance when it has one.
function Page:OpenQuest(questID)
	local quest = LG:Quest(questID)
	local key = quest and quest.instance and LG:InstanceInfo(quest.instance) and quest.instance or self.key
	OpenInstance(self, key, { quest = questID })
end

-- opts: { npc = boss npc, quest = questID, trash = true, rewards = true }
OpenInstance = function(page, key, opts)
	local info = LG:InstanceInfo(key)
	if not info then
		page:ShowHome()
		return
	end
	local s = State()
	opts = opts or {}
	if page.key ~= key then s.boss = nil end
	page.key = key
	s.kind = info.kind
	s.last[info.kind] = key
	s.view = "instance"
	if opts.quest then
		s.mode, s.quest = "quests", opts.quest
		page.keepQuest = true
		if not LG:QuestForFaction(opts.quest, s.faction) then s.faction = "all" end
	elseif opts.mode == "quests" or modes[opts.mode or ""] then
		s.mode = opts.mode
	elseif opts.mode == "bosses" then
		s.mode = "bosses"
	elseif opts.npc or opts.trash or opts.rewards then
		s.mode = "bosses"
		if opts.trash then s.boss = "trash" elseif opts.rewards then s.boss = "rewards" end
		for index, boss in ipairs(LG:InstanceLoot(key).bosses) do
			if boss.npc == opts.npc then s.boss = index end
		end
	end
	page.home:Hide()
	page.inst:Show()
	page:DrawHeader()
	page:SetMode(s.mode)
end

local function Create(parent)
	local page = CreateFrame("Frame", nil, parent)
	page:SetAllPoints()
	for name, fn in pairs(Page) do page[name] = fn end
	BuildHome(page)
	BuildInstance(page)
	return page
end

-- arg: an instance key, or { key, npc | quest | trash | rewards | mode = "quests" | "bosses" | an extra view }.
local function Show(page, arg)
	local s = State()
	if type(arg) == "table" and arg.key then
		OpenInstance(page, arg.key, arg)
	elseif type(arg) == "string" and LG:InstanceInfo(arg) then
		OpenInstance(page, arg)
	elseif s.view == "instance" and s.last[s.kind] and LG:InstanceInfo(s.last[s.kind]) then
		OpenInstance(page, s.last[s.kind])
	else
		page:ShowHome()
	end
end

local function Refresh(page, changed)
	local relevant = changed.data or changed.gear or changed.list or changed.spec or changed.rank or changed.wishlist
		or changed.quests or changed.player or changed.bags or changed.settings or changed.questRewards
		or changed.forever -- a WoW: Forever boss or drop you just saw
	if page.inst:IsShown() and page.key then
		if changed.items and not relevant then
			page.loot.list:Refresh()
			page.inst.left.quest:Refresh()
			if State().mode == "quests" then page.detail:Redraw(true) end
			return
		end
		if changed.attune and not relevant then
			page:DrawHeader()
			if modes[State().mode] then page:DrawMode() end
			return
		end
		if modes[State().mode] and (relevant or changed.adventure) then
			if not LG:InstanceInfo(page.key) then page:ShowHome() return end
			page:DrawHeader()
			page:SetMode(State().mode)
			return
		end
		if not relevant then return end
		if not LG:InstanceInfo(page.key) then page:ShowHome() return end
		page:DrawHeader()
		page:DrawLeft()
		if State().mode == "bosses" then page:DrawLoot() else page.detail:Redraw(true) end
	elseif page.home:IsShown() and (relevant or changed.items) then
		DrawHome(page)
	end
end

-- Only the built-in list of WoW: Forever dungeons: no loot data and no
-- dungeon finder list yet.
local function NothingKnown()
	for _, info in ipairs(LG:Catalog()) do
		if not info.forever or info.lfg then return false end
	end
	return true
end

local function Empty(page)
	if page.home:IsShown() and NothingKnown() then
		return L["No dungeons known yet"],
			L["Install EldoUI_LootData for the Classic loot tables, or open the Dungeon Finder once so the game lists its dungeons."],
			LG.ICON, {
				{ L["Show data status"], function() LG:PrintDataStatus() end, L["Prints where the loot data comes from (same as /lg data)."] },
			}
	end
end

LG:RegisterPage("journal", {
	title = "Journal",
	desc = "Every dungeon and raid: bosses, drops with chances, quests and what is an upgrade for you.",
	order = 20,
	command = "journal",
	usage = Key("open the Journal; add a dungeon name or alias (/eui journal dm)"),
	create = Create,
	show = Show,
	refresh = Refresh,
	empty = Empty,
	alias = function(text) return LG:FindInstance(text) end,
	instanceRoute = function(mapID) return LG:InstanceForPlayer(mapID) end,
})
