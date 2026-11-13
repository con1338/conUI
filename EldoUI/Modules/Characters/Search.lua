-- EldoUI Characters: the Search tab.
--
-- One search across the bags, bank, equipped gear, mailbox and auctions of
-- every character in the scope, and the guild banks they saw. The query
-- uses the bag search words (q:rare, t:cloth, ilvl>20, boe, -junk, a|b),
-- so the Bags help applies here too. Results: one row per item, owner and
-- place, with the count. Shift-click links the item, Ctrl-click tries it
-- on (the game's own modified-click handler).
local _, E = ...
local L = E.L
local Key = E.Key
local Kit = E.UIKit
local M = E.modules.Characters

local function Store() return E.Characters end

local WHERE = {
	{ "bags", Key("Bags"), Key("Items in the bags.") },
	{ "bank", Key("Bank"), Key("Items in the bank, as of the last visit.") },
	{ "equip", Key("Equipped"), Key("Gear the character wears.") },
	{ "mail", Key("Mail"), Key("Items attached to mail in the mailbox, as of the last visit.") },
	{ "auctions", Key("Auctions"), Key("Items the character has on the auction house, as of the last visit.") },
	{ "guild", Key("Guild bank"), Key("Items in the guild bank tabs a character of yours opened.") },
}
local WHERE_TITLE = {}
for _, entry in ipairs(WHERE) do WHERE_TITLE[entry[1]] = entry[2] end
M.SEARCH_WHERE = WHERE

local function Bags() return E.modules.Bags end

-- Item name, link, quality and icon from the client cache. A missing item
-- asks the server; GET_ITEM_INFO_RECEIVED redraws the tab.
local waiting = false
local function ItemInfo(short, id)
	local name, link, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(short)
	if not name then
		if id and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
		waiting = true
	end
	return name, link, quality, icon
end

-- query: a Bags.ParseQuery result (nil matches nothing). A query that is
-- only a number matches that item ID.
local function Matcher(text)
	text = strtrim(text or "")
	if text == "" then return nil end
	local id = tonumber(text)
	if id then return function(record) return record.id == id end end
	local bags = Bags()
	local query = bags and bags.ParseQuery and bags.ParseQuery(text)
	if not (query and bags.Matches) then return nil end
	local cache = {}
	return function(record)
		local hit = cache[record.short]
		if hit == nil then
			hit = bags.Matches(query, { short = record.short, id = record.id }) and true or false
			cache[record.short] = hit
		end
		return hit
	end
end

-- Every matching item: { id, short, count, key (character or guild key),
-- record (character) or guild, where }.
function M:SearchItems(text, where)
	local match = Matcher(text)
	if not match then return {} end
	where = where or {}
	local store = Store()
	local rows, index = {}, {}
	local function Add(owner, place, short, count, extra)
		local id = store.ItemIDOf(short)
		if not id then return end
		local probe = { short = short, id = id }
		if not match(probe) then return end
		local slot = owner .. "\001" .. place .. "\001" .. short
		local row = index[slot]
		if not row then
			row = { id = id, short = short, count = 0, key = owner, where = place }
			for k, v in pairs(extra) do row[k] = v end
			index[slot] = row
			rows[#rows + 1] = row
		end
		row.count = row.count + (count or 1)
	end
	for _, key in ipairs(self:Keys()) do
		local record = store:Get(key)
		for _, location in ipairs(store.LOCATIONS) do
			if where[location] then
				for _, value in ipairs(type(record[location]) == "table" and record[location] or {}) do
					local short, count = store.Decode(value)
					if short then Add(key, location, short, count, { record = record }) end
				end
			end
		end
		local auctions = type(record.auctions) == "table" and record.auctions.list
		if where.auctions and type(auctions) == "table" then
			for _, auction in ipairs(auctions) do
				local short = store.ShortItem(auction.link) or (auction.id and "item:" .. auction.id)
				if short then Add(key, "auctions", short, auction.count, { record = record }) end
			end
		end
	end
	if where.guild then
		local guilds = store:Guilds()
		for _, key in ipairs(store:GuildKeys(self.db.scope)) do
			for _, tab in pairs(type(guilds[key].tabs) == "table" and guilds[key].tabs or {}) do
				for _, value in ipairs(tab.items or {}) do
					local short, count = store.Decode(value)
					if short then Add(key, "guild", short, count, { guild = guilds[key] }) end
				end
			end
		end
	end
	return rows
end

local function OwnerText(row)
	if row.record then return M.ClassIcon(row.record.class, 14) .. M.ClassName(row.record) end
	return M.GuildText("<" .. (row.guild and row.guild.name or row.key) .. ">")
end

local function ItemText(row)
	local name, _, quality, icon = ItemInfo(row.short, row.id)
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	local text = name or ("item:" .. row.id)
	if color and color.hex then text = color.hex .. text .. "|r" end
	icon = icon or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(row.id))
	return (icon and ("|T%s:14:14:0:0:64:64:5:59:5:59|t "):format(icon) or "") .. text
end

local function Update(frame)
	waiting = false
	local text = strtrim(frame.box:GetText() or "")
	frame.query = text
	local rows = M:SearchItems(text, frame.where:GetSelected())
	frame.rows = rows
	frame.tbl:SetData(rows)
	local total, owners = 0, {}
	for _, row in ipairs(rows) do
		total = total + row.count
		owners[row.key] = true
	end
	local people = 0
	for _ in pairs(owners) do people = people + 1 end
	if text == "" then
		frame.count:SetText(L["Type a name, an item ID or bag search words."])
	else
		frame.count:SetText(L["%d items on %d characters and banks"]:format(total, people))
	end
	frame.pending = waiting
end
M.UpdateSearch = Update

local function OnItemInfo(frame)
	if not frame.pending or frame.redraw then return end
	frame.redraw = true
	C_Timer.After(0.3, function()
		frame.redraw = nil
		if frame:IsVisible() then Update(frame) end
	end)
end

M:AddTab({
	key = "search", order = 20, title = "Search",
	desc = "Find an item on any of your characters: bags, bank, gear, mail, auctions and guild banks.",
	create = function(content)
		local frame = CreateFrame("Frame", nil, content)
		frame:SetAllPoints()
		frame.toolbar = CreateFrame("Frame", nil, frame)
		frame.toolbar:SetPoint("TOPLEFT")
		frame.toolbar:SetPoint("TOPRIGHT")
		frame.toolbar:SetHeight(22)
		local box = CreateFrame("EditBox", nil, frame.toolbar, "SearchBoxTemplate")
		E:SearchHint(box)
		box:SetSize(240, 20)
		box:SetAutoFocus(false)
		box:SetPoint("LEFT", 4, 0)
		E:SkinEditBox(box)
		box:HookScript("OnTextChanged", function(own, user)
			if not user then return end
			if frame.typing then frame.typing:Cancel() end
			frame.typing = C_Timer.NewTimer(0.25, function()
				frame.typing = nil
				Update(frame)
			end)
		end)
		box:SetScript("OnEnterPressed", function(own)
			own:ClearFocus()
			Update(frame)
		end)
		Kit.Tooltip(box, L["Search"], L["An item name, an item ID, or the bag search words: q:rare, t:cloth, ilvl>20, boe, bop, quest, junk. Put - before a word to exclude it and | between alternatives."])
		frame.box = box
		frame.count = Kit.Text(frame.toolbar, 12, "LEFT", "secondary")
		frame.count:SetPoint("LEFT", box, "RIGHT", 10, 0)
		frame.count:SetPoint("RIGHT", -4, 0)
		frame.where = Kit.ChipBar(frame, {
			multi = true,
			selected = { bags = true, bank = true, equip = true, mail = true, auctions = true, guild = true },
			chips = (function()
				local list = {}
				for _, entry in ipairs(WHERE) do list[#list + 1] = { entry[1], L[entry[2]], L[entry[3]] } end
				return list
			end)(),
			onChange = function() Update(frame) end,
		})
		frame.where:SetPoint("TOPLEFT", frame.toolbar, "BOTTOMLEFT", 0, -4)
		frame.tbl = Kit.CreateTable(frame, {
			{ key = "item", title = L["Item"], value = function(row) return (ItemInfo(row.short, row.id)) or "" end, text = ItemText },
			{ key = "count", title = L["Count"], width = 70, align = "RIGHT", value = function(row) return row.count end },
			{ key = "owner", title = L["Character"], width = 200, value = function(row) return row.record and row.record.name or row.key end, text = OwnerText },
			{ key = "where", title = L["Where"], width = 120, value = function(row) return L[WHERE_TITLE[row.where] or row.where] end },
		}, {
			sortKey = "item", rowHeight = 18,
			onClick = function(row, button, widget)
				if button == "RightButton" then
					if row.record then M:ShowCharacterMenu(widget, row.key) end
					return
				end
				local _, link = ItemInfo(row.short, row.id)
				if IsModifiedClick() and HandleModifiedItemClick then HandleModifiedItemClick(link or row.short) end
			end,
			createRow = function(widget)
				widget:HookScript("OnEnter", function(own)
					if not own.item then return end
					GameTooltip:SetOwner(own, "ANCHOR_RIGHT")
					GameTooltip:SetHyperlink(own.item.short)
					GameTooltip:Show()
				end)
				widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
			end,
			empty = { L["Nothing found"], L["None of your characters has a matching item in the places picked above. Banks, mail and auctions show what each character saw on its last visit."] },
		})
		frame.tbl:SetPoint("TOPLEFT", frame.where, "BOTTOMLEFT", 0, -6)
		frame.tbl:SetPoint("BOTTOMRIGHT")
		frame:SetScript("OnEvent", OnItemInfo)
		return frame
	end,
	show = function(frame, arg)
		if type(arg) == "string" and arg ~= "" then frame.box:SetText(arg) end
		frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		Update(frame)
	end,
	hide = function(frame)
		frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
		if frame.typing then frame.typing:Cancel() frame.typing = nil end
	end,
	refresh = function(frame) Update(frame) end,
})
