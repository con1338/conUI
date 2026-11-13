-- EldoUI Loot Guide: the Wishlist page.
--
-- Top: the list picker (several lists, one active, others shown), a count,
-- where the items come from, the alert state, "Add my BiS", "Hide
-- obsolete" and Share. Middle: the items of the active list grouped by
-- dungeon or raid (a header opens it in the Journal), open world and
-- "Quests, crafted and other"; each row has its source, chance, gain and
-- your note. Right: "Where to go", the plan by place; "Clear all" asks
-- first. The engine (lists, notes, alerts, sharing) is Wishlist.lua.
local _, E = ...
local LG = E.LootGuide
local Kit = LG.Kit
local P = LG.PageKit
local L = E.L

local Key = E.Key
local SIDEBAR = 230
local HEADER_ROW = 22

local function State()
	local ui = LG:UI()
	if type(ui.wishlist) ~= "table" then ui.wishlist = {} end
	return ui.wishlist
end

local function Confirm(text, fn)
	E:ShowConfirm({ key = "ELDOUI_LOOTGUIDE_CONFIRM", title = L["Wishlist"], text = text, accept = YES, cancel = NO,
		danger = true, onAccept = function() if type(fn) == "function" then fn() end end })
end

---------------------------------------------------------------------------
-- Where an item is best got: one place per item.
-- { kind = "instance", key, boss, npc, chance } | { kind = "world", npc,
-- name, chance, minLevel, maxLevel } | { kind = "worlddrop" } | { kind = "other", entry }
---------------------------------------------------------------------------
function LG:WishPlace(itemID)
	local sources = self:ItemSources(itemID) or {}
	local instance, world, worldDrop, quest
	for _, entry in ipairs(sources) do
		if (entry.kind == "npc" or entry.kind == "object") then
			local chance = type(entry.chance) == "number" and entry.chance or 0
			if entry.instance and self:InstanceInfo(entry.instance) then
				if not instance or chance > instance.chance then
					instance = { kind = "instance", key = entry.instance, boss = entry.name, npc = entry.id, chance = chance }
				end
			elseif entry.kind == "npc" and (not world or chance > world.chance) then
				world = { kind = "world", npc = entry.id, name = entry.name, chance = chance, minLevel = entry.minLevel, maxLevel = entry.maxLevel }
			end
		elseif entry.kind == "world" then
			worldDrop = { kind = "worlddrop", entry = entry }
		elseif (entry.kind == "quest" or entry.kind == "choice") and not quest then
			local key = self:QuestInstance(entry.id)
			if key and self:InstanceInfo(key) then quest = { kind = "instance", key = key, quest = entry.id, chance = 0 } end
		end
	end
	return instance or quest or world or worldDrop or { kind = "other", entry = sources[1] }
end

---------------------------------------------------------------------------
-- Rows of the main list
---------------------------------------------------------------------------
local function Rows(hideObsolete)
	local list = LG:WishListRecord(LG:ActiveListID())
	local groups, order = {}, {}
	local summary = { total = 0, instances = 0, world = 0, other = 0, obsolete = 0 }
	local function Group(key, title, sort, open)
		local group = groups[key]
		if not group then
			group = { key = key, title = title, sort = sort, open = open, rows = {} }
			groups[key] = group
			order[#order + 1] = group
		end
		return group
	end
	for itemID, entry in pairs(list and list.items or {}) do
		itemID = tonumber(itemID)
		local obsolete = itemID and LG:WishObsolete(itemID)
		if obsolete then summary.obsolete = summary.obsolete + 1 end
		if itemID and not (hideObsolete and obsolete) then
			summary.total = summary.total + 1
			local place = LG:WishPlace(itemID)
			local group
			if place.kind == "instance" then
				local info = LG:InstanceInfo(place.key)
				group = Group(place.key, info.name, info.min or 0, place.key)
			elseif place.kind == "world" or place.kind == "worlddrop" then
				group = Group("world", L["Open world"], 1000)
			else
				group = Group("other", L["Quests, crafted and other"], 1001)
			end
			local sources = LG:ItemSources(itemID) or {}
			local line
			if place.kind == "instance" and place.boss then
				line = place.boss
			elseif place.kind == "instance" and place.quest then
				line = (L["Quest reward: %s"]):format(LG:QuestTitle(place.quest) or ("#" .. place.quest))
			else
				line = P.SourceLine(place.entry or sources[1]) or ""
				if place.kind == "world" then line = place.name or line end
				if line == "" then line = L["No known source"] end
			end
			local note = type(entry) == "table" and entry.note
			if note and note ~= "" then line = line .. "  " .. E:TextHex("accent") .. note .. "|r" end
			if obsolete then line = Kit.Hex(unpack(Kit.DIM)) .. L["You own something better"] .. "|r  " .. line end
			local data = P.ChanceData(place.chance and place.chance > 0 and place.chance or nil, place.npc, itemID)
			group.rows[#group.rows + 1] = { itemID = itemID, sub = line, chance = data.chance, seen = data.seen, dim = obsolete,
				onClick = function() P.OpenItem(itemID) end, place = place }
		end
	end
	table.sort(order, function(a, b)
		if a.sort ~= b.sort then return a.sort < b.sort end
		return a.title < b.title
	end)
	local items = {}
	for _, group in ipairs(order) do
		if group.open then summary.instances = summary.instances + 1
		elseif group.key == "world" then summary.world = summary.world + #group.rows
		else summary.other = summary.other + #group.rows end
		table.sort(group.rows, function(a, b) return a.itemID < b.itemID end)
		items[#items + 1] = { header = group.title, open = group.open, count = #group.rows }
		for _, row in ipairs(group.rows) do items[#items + 1] = row end
	end
	return items, summary, order
end

local function RowCreate(row)
	row.cell = P.ItemCell(row)
	row.cell:SetAllPoints()
	row.head = CreateFrame("Button", nil, row)
	row.head:SetAllPoints()
	row.head.text = Kit.Text(row.head, 11, "LEFT")
	row.head.text:SetPoint("LEFT", 2, -2)
	row.head.text:SetPoint("RIGHT", -4, -2)
	row.head.text:SetWordWrap(false)
	row.head.hover = row.head:CreateTexture(nil, "HIGHLIGHT")
	row.head.hover:SetAllPoints()
	row.head.hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	row.head:SetScript("OnClick", function(self)
		local item = self:GetParent().item
		if item and item.open then LG:Open("journal", item.open) end
	end)
end

local function RowUpdate(row, item)
	if item.header then
		row.cell:Hide()
		row.head:Show()
		row.head.text:SetText(E:TextHex("accent") .. E:CaptionText(item.header) .. "|r  " .. E:TextHex("secondary") .. item.count .. "|r")
		row.head.hover:SetShown(item.open ~= nil)
		Kit.Tooltip(row.head, item.open and item.header or nil, nil, item.open and { { L["Click"], L["open it in the Journal"] } } or nil)
	else
		row.head:Hide()
		P.SetItem(row.cell, item)
	end
end

---------------------------------------------------------------------------
-- Where to go
---------------------------------------------------------------------------
local function DrawSidebar(page, groups)
	local flow = page.side
	flow:Begin()
	P.FlowCaption(flow, L["Where to go"])
	if #groups == 0 then
		P.FlowText(flow, L["Star items in the Journal, Search or any list and the places to get them show here."], 11, "secondary")
	end
	for _, group in ipairs(groups) do
		if group.open then
			local bosses, seen = {}, {}
			for _, row in ipairs(group.rows) do
				local boss = row.place and row.place.boss
				if boss and not seen[boss] then
					seen[boss] = true
					bosses[#bosses + 1] = boss
				end
			end
			P.FlowLine(flow, ("%s  " .. E:TextHex("secondary") .. "%d|r"):format(group.title, #group.rows), function() LG:Open("journal", group.open) end,
				nil, group.title, function(tip) Kit.TooltipHint(tip, { L["Click"], L["open it in the Journal"] }) end)
			if #bosses > 0 then P.FlowText(flow, table.concat(bosses, ", "), 10, "secondary", 8, 4) end
		elseif group.key == "world" then
			P.FlowLine(flow, ("%s  " .. E:TextHex("secondary") .. "%d|r"):format(L["Open world"], #group.rows), nil)
			local mobs = {}
			for _, row in ipairs(group.rows) do
				local place = row.place
				if place.kind == "world" and place.npc and not mobs[place.npc] then
					mobs[place.npc] = true
					local camps = LG:SpawnPoints("npc", place.npc)
					local zone = camps[1] and LG:SpawnZone(camps[1])
					local level = place.minLevel and (place.minLevel == place.maxLevel and tostring(place.minLevel)
						or ("%d-%d"):format(place.minLevel, place.maxLevel or place.minLevel))
					local text = (place.name or L["NPC %s"]:format(place.npc)) .. "  " .. E:TextHex("secondary") .. table.concat({ zone or "", level or "" }, " ") .. "|r"
					P.FlowLine(flow, text, function() P.OpenItem(row.itemID) end, P.MapButton("npc", place.npc, place.name), place.name,
						function(tip) Kit.TooltipHint(tip, { L["Click"], L["open the item"] }) end, 8)
				end
			end
			for _, row in ipairs(group.rows) do
				if row.place.kind == "worlddrop" then
					P.FlowText(flow, L["Random world drops: any mob of the right level."], 10, "secondary", 8, 4)
					break
				end
			end
		else
			P.FlowLine(flow, ("%s  " .. E:TextHex("secondary") .. "%d|r"):format(group.title, #group.rows), nil)
		end
	end
	flow:Finish(true)
end

---------------------------------------------------------------------------
-- List picker menu
---------------------------------------------------------------------------
local function ListMenu(owner)
	E.UIKit.ContextMenu(owner, function(_, root)
		local lists = LG:WishLists()
		local active = LG:ActiveListID()
		local current = LG:WishListRecord(active)
		root:CreateTitle(L["Wishlists"])
		for _, list in ipairs(lists) do
			local label = ("|T%s:14|t %s " .. E:TextHex("secondary") .. "%d|r%s"):format(list.icon, list.name, list.count, list.account and ("  " .. E:TextHex("secondary") .. L["account"] .. "|r") or "")
			root:CreateRadio(label, function() return list.id == active end, function() LG:SetActiveList(list.id) end)
		end
		if #lists > 1 then
			local shown = root:CreateButton(L["Also star items from"])
			for _, list in ipairs(lists) do
				if list.id ~= active then
					shown:CreateCheckbox(list.name, function() return LG:IsListShown(list.id) end,
						function() LG:SetListShown(list.id, not LG:IsListShown(list.id)) end)
				end
			end
		end
		root:CreateDivider()
		root:CreateButton(L["New list..."], function()
			LG:AskText(L["Name of the new list (this character):"], "", 40, function(name)
				local id = LG:NewWishList(name, false)
				if id then LG:SetActiveList(id) end
			end)
		end)
		root:CreateButton(L["New account list..."], function()
			LG:AskText(L["Name of the new list (every character on this account):"], "", 40, function(name)
				local id = LG:NewWishList(name, true)
				if id then LG:SetActiveList(id) end
			end)
		end)
		root:CreateButton(L["Rename..."], function()
			LG:AskText(L["New name:"], current and current.name or "", 40, function(name) LG:RenameWishList(active, name) end)
		end)
		local icons = root:CreateButton(L["Icon"])
		for _, icon in ipairs(LG.WISH_ICONS) do
			icons:CreateButton(("|T%s:16|t"):format(icon), function() LG:SetWishListIcon(active, icon) end)
		end
		if active ~= "main" then
			root:CreateButton(L["Delete this list"], function()
				Confirm((L["Delete the wishlist %s?"]):format(current and current.name or "?"), function() LG:DeleteWishList(active) end)
			end)
		end
		root:CreateDivider()
		root:CreateButton(L["Export (share string)"], function() LG:ShowWishListExport(active) end)
		root:CreateButton(L["Import as a new list"], function() LG:ShowWishListImport(nil) end)
		root:CreateButton(L["Import into this list"], function() LG:ShowWishListImport(active) end)
		local send = root:CreateButton(L["Send to"])
		if IsInRaid and IsInRaid() then send:CreateButton(L["Raid"], function() LG:SendWishList(active, "RAID") end)
		elseif IsInGroup and IsInGroup() then send:CreateButton(L["Party"], function() LG:SendWishList(active, "PARTY") end) end
		if IsInGuild and IsInGuild() then send:CreateButton(L["Guild"], function() LG:SendWishList(active, "GUILD") end) end
		send:CreateButton(L["A friend or group member..."], function()
			LG:AskText(L["Send the list to (name):"], "", 60, function(name) LG:SendWishList(active, name) end)
		end)
	end, { at = "owner" })
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local function AlertText()
	if not LG.db.wishAlert then return L["Alerts off"] end
	local route = { auto = L["toast"], lane = L["toast"], banner = L["banner"], chat = L["chat"] }
	return (L["Alerts on (%s)"]):format(route[LG.db.wishRoute] or L["toast"])
end

local function Draw(page)
	local s = State()
	local list = LG:WishListRecord(LG:ActiveListID())
	local items, summary, groups = Rows(s.hideObsolete)
	page.items, page.summary = items, summary
	page.picker:SetLabel(("|T%s:14|t %s"):format(list and list.icon or LG.ICON, list and list.name or L["Wishlist"]))
	page.count:SetLabel(tostring(summary.total), 1, 0.82, 0)
	local parts = {}
	if summary.instances > 0 then parts[#parts + 1] = E:Plural(summary.instances, "%d dungeon or raid", "%d dungeons and raids"):format(summary.instances) end
	if summary.world > 0 then parts[#parts + 1] = (L["%d open world"]):format(summary.world) end
	if summary.other > 0 then parts[#parts + 1] = (L["%d other"]):format(summary.other) end
	parts[#parts + 1] = AlertText()
	page.summaryText:SetText(table.concat(parts, "  ·  "))
	page.bis:SetShown(LG:BiSOn())
	page.obsolete:SetOn(s.hideObsolete)
	page.obsolete:SetLabel(summary.obsolete > 0 and (L["Hide obsolete"] .. " " .. E:TextHex("secondary") .. summary.obsolete .. "|r") or L["Hide obsolete"])
	page.list:SetData(items)
	DrawSidebar(page, groups)
end

local function AddBiS(page)
	page.bis:Disable()
	page.bis:SetText(L["Ranking..."])
	LG:AddMyBiS(function(added)
		page.bis:Enable()
		page.bis:SetText(L["Add my BiS"])
		if added > 0 then
			LG:Notify((L["Added %d best-in-slot items to your wishlist."]):format(added))
		else
			LG:Notify(L["Every best-in-slot item is already yours or on your wishlist."])
		end
	end)
end

local function Create(parent)
	local page = CreateFrame("Frame", nil, parent)
	page:SetAllPoints()
	page.picker = P.Toggle(page, L["Wishlist"], function(self) ListMenu(self) end, L["Wishlists"],
		L["Pick the list the stars add to, show other lists, make, rename, share or delete lists."])
	page.picker:SetPoint("TOPLEFT")
	page.count = P.Pill(page)
	page.count:SetPoint("LEFT", page.picker, "RIGHT", 6, 0)
	Kit.Tooltip(page.count, L["Items"], L["Items on this list (without the hidden obsolete ones)."])
	page.summaryText = Kit.Text(page, 11, "LEFT", "secondary")
	page.summaryText:SetPoint("LEFT", page.count, "RIGHT", 8, 0)
	page.summaryText:SetWordWrap(false)
	local alertHit = CreateFrame("Button", nil, page)
	alertHit:SetAllPoints(page.summaryText)
	Kit.Tooltip(alertHit, L["Wishlist alerts"], L["A toast or banner, a sound and a chat line when a wished item is in a loot window or a roll, or drops in the dungeon you enter. Set them in /eui > Loot Guide."])
	page.bis = Kit.Button(page, L["Add my BiS"], 110, 20, function() AddBiS(page) end, L["Add my BiS"],
		L["Adds the best-in-slot items for your spec that you do not own and have not wished for yet."])
	page.bis:SetPoint("TOPRIGHT", -(SIDEBAR + 12), 0)
	page.obsolete = P.Toggle(page, L["Hide obsolete"], function()
		local s = State()
		s.hideObsolete = not s.hideObsolete
		Draw(page)
	end, L["Hide obsolete"], L["Hides wished items you already beat with gear you own."])
	page.obsolete:SetPoint("RIGHT", page.bis, "LEFT", -6, 0)
	page.summaryText:SetPoint("RIGHT", page.obsolete, "LEFT", -8, 0)

	page.list = Kit.CreateList(page, { create = RowCreate, update = RowUpdate, gap = 2,
		rowHeight = math.max(Kit.RowHeight(), HEADER_ROW) })
	page.list:SetPoint("TOPLEFT", 0, -28)
	page.list:SetPoint("BOTTOMRIGHT", -(SIDEBAR + 12), 0)

	local side = CreateFrame("Frame", nil, page)
	side:SetPoint("TOPRIGHT")
	side:SetPoint("BOTTOMRIGHT")
	side:SetWidth(SIDEBAR)
	E:SetTemplate(side, true)
	page.side = P.Flow(side)
	page.side:SetPoint("TOPLEFT", 8, -4)
	page.side:SetPoint("BOTTOMRIGHT", -4, 32)
	page.clear = Kit.Button(side, L["Clear all"], 100, 20, function()
		local id = LG:ActiveListID()
		local list = LG:WishListRecord(id)
		local count = 0
		for _ in pairs(list and list.items or {}) do count = count + 1 end
		if count == 0 then
			LG:Notify(L["This list is already empty."])
			return
		end
		E:ShowConfirm({ title = L["Clear all"], accept = L["Clear"], danger = true,
			text = E:Plural(count, "Remove %d item from the list %s?", "Remove all %d items from the list %s?"):format(count, list.name)
				.. " " .. L["This can't be undone."],
			onAccept = function()
				LG:ClearWishList(id)
				LG:Notify(L["Emptied the list %s."]:format(list.name))
			end })
	end, L["Clear all"], L["Empty the list on show. The other lists stay. Asks first."])
	E.UIKit.SetButtonKind(page.clear, "danger")
	page.clear:SetPoint("BOTTOM", 0, 6)
	return page
end

local function Empty(page)
	local summary = page.summary
	if summary and summary.total == 0 and summary.obsolete == 0 then
		local buttons = {}
		if LG:BiSOn() then
			buttons[#buttons + 1] = { L["Add my BiS"], function() AddBiS(page) end,
				L["Adds the best-in-slot items for your spec that you do not own and have not wished for yet."] }
		end
		if LG:IsPageOn("journal") then
			buttons[#buttons + 1] = { L["Open the Journal"], function() LG:Open("journal") end, L["Browse dungeon and raid loot and star what you want."] }
		end
		return L["Your wishlist is empty"],
			L["Click the star on any item (or right-click it) to add it. You get an alert when it drops or is rolled on."],
			"Interface\\Icons\\INV_Misc_Note_01", buttons
	end
end

-- /eui wishlist add <link> | export | import
local function Run(arg)
	local word, rest = arg:match("^(%S+)%s*(.*)$")
	word = (word or ""):lower()
	if word == "add" then
		local itemID = tonumber(rest:match("item:(%d+)") or rest:match("^(%d+)$"))
		if not itemID then
			E:Print(L["Usage: /eui wishlist add <item link>"])
			return true
		end
		LG:SetWished(itemID, true)
		local list = LG:WishListRecord(LG:ActiveListID())
		E:Print((L["Added %s to %s."]):format(rest ~= "" and rest or ("item:" .. itemID), list and list.name or L["Wishlist"]))
		return true
	elseif word == "export" then
		LG:ShowWishListExport()
		return true
	elseif word == "import" then
		LG:ShowWishListImport(nil)
		return true
	end
	return false
end

LG:RegisterPage("wishlist", {
	title = "Wishlist",
	desc = "Items you starred, grouped by where they drop, with a plan of where to go.",
	order = 50,
	command = "wishlist",
	usage = Key("open the Wishlist; add <item link> | export | import"),
	create = Create,
	show = function(page) Draw(page) end,
	refresh = function(page, changed)
		if changed.items and not (changed.wishlist or changed.data) then
			page.list:Refresh()
			return
		end
		if changed.wishlist or changed.data or changed.gear or changed.settings or changed.bags or changed.rank or changed.spec then Draw(page) end
	end,
	empty = Empty,
	count = function() return LG:WishlistCount() end,
	run = Run,
})

LG:RegisterItemMenu("wishnote", function(root, itemID)
	if LG:WishlistOn() and LG:IsWished(itemID) then
		root:CreateButton(LG:WishNote(itemID) and L["Edit wishlist note"] or L["Add wishlist note"], function() LG:EditWishNote(itemID) end)
	end
end)
