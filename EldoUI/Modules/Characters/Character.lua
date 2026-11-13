-- EldoUI Characters: the Character tab.
--
-- One character in detail. Left: the characters in the scope. Right:
-- Summary (everything the character tooltip shows, plus base stats and
-- lifetime honorable kills), Items (bags, bank, mail with counts, or
-- the Bags module's own windows), Gear, Quests and Reputation.
local _, E = ...
local L = E.L
local Key = E.Key
local Kit = E.UIKit
local M = E.modules.Characters

local function Store() return E.Characters end

local LIST_WIDTH = 190

local function Grey(text) return M.Grey(text) end

-- The side list: one two-line row per character (the class icon, the
-- name in its class color, level, zone and last login under it), the
-- character you play marked, the open one selected.
local CLASS_ART = "Interface\\TargetingFrame\\UI-Classes-Circles"

local function ListRowData(record, current)
	local name = record.name or "?"
	if record.realmKey and record.realmKey ~= E:RealmKey() then name = name .. " - " .. record.realmKey end
	local parts = { L["Level %d"]:format(record.level or 0) }
	if type(record.zone) == "string" and record.zone ~= "" then parts[#parts + 1] = record.zone end
	local ago = not current and M.Ago(record) or ""
	if ago ~= "" then parts[#parts + 1] = ago end
	return {
		name = name,
		class = record.class,
		status = current and "good" or nil,
		statusText = current and L["Online"] or nil,
		sub = table.concat(parts, " - "),
	}
end

local function SetClassArt(row, class)
	local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
	local texture = row.icon.icon
	if coords then
		row.icon:SetIcon(CLASS_ART)
		texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
	else
		row.icon:SetIcon(134400)
		E:TrimIcon(texture)
	end
end

-- A stand-in tooltip that collects the character tooltip's lines.
local function Collector()
	local rows = {}
	local collector = { rows = rows }
	function collector:AddLine(text, r, g, b)
		rows[#rows + 1] = { left = text or "", color = r and { r, g, b }, line = true }
	end
	function collector:AddDoubleLine(left, right, r, g, b)
		rows[#rows + 1] = { left = left or "", right = right or "", color = r and { r, g, b } }
	end
	function collector:NumLines() return #rows end
	return collector
end

local STATS = {
	{ "str", Key("Strength") }, { "agi", Key("Agility") }, { "sta", Key("Stamina") }, { "int", Key("Intellect") }, { "spi", Key("Spirit") },
	{ "armor", Key("Armor") }, { "hp", Key("Health") }, { "power", Key("Power") }, { "hk", Key("Honorable kills") },
}

function M:SummaryRows(key)
	local collector = Collector()
	self:CharacterTooltip(collector, key)
	local record = Store():Get(key)
	local stats = record and type(record.stats) == "table" and record.stats
	if stats then
		collector:AddLine(" ")
		collector:AddLine(L["Stats"], Kit.Accent())
		for _, stat in ipairs(STATS) do
			local value = stats[stat[1]]
			if value then collector:AddDoubleLine(L[stat[2]], BreakUpLargeNumbers and BreakUpLargeNumbers(value) or tostring(value), unpack(Kit.SECONDARY)) end
		end
	end
	local rows = {}
	for _, row in ipairs(collector.rows) do
		if not (row.line and row.left == " ") then rows[#rows + 1] = row end
	end
	return rows
end

local WHERE_TITLE = { bags = Key("Bags"), bank = Key("Bank"), mail = Key("Mail"), equip = Key("Equipped") }

function M:ItemRows(key)
	local record = Store():Get(key)
	local rows, index = {}, {}
	if not record then return rows end
	for _, location in ipairs({ "bags", "bank", "mail" }) do
		for _, value in ipairs(type(record[location]) == "table" and record[location] or {}) do
			local short, count = Store().Decode(value)
			if short then
				local slot = location .. short
				local row = index[slot]
				if not row then
					row = { short = short, id = Store().ItemIDOf(short), count = 0, where = location }
					index[slot] = row
					rows[#rows + 1] = row
				end
				row.count = row.count + count
			end
		end
	end
	return rows
end

local SLOT_NAMES = {
	"HEADSLOT", "NECKSLOT", "SHOULDERSLOT", "SHIRTSLOT", "CHESTSLOT", "WAISTSLOT", "LEGSSLOT", "FEETSLOT", "WRISTSLOT",
	"HANDSSLOT", "FINGER0SLOT", "FINGER1SLOT", "TRINKET0SLOT", "TRINKET1SLOT", "BACKSLOT", "MAINHANDSLOT",
	"SECONDARYHANDSLOT", "RANGEDSLOT", "TABARDSLOT",
}

function M:GearRows(key)
	local record = Store():Get(key)
	local rows = {}
	for slot = 1, 19 do
		local short = record and type(record.equip) == "table" and record.equip[slot]
		if short then
			rows[#rows + 1] = { slot = slot, label = rawget(_G, SLOT_NAMES[slot]) or SLOT_NAMES[slot], short = short, id = Store().ItemIDOf(short),
				level = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(short) }
		end
	end
	return rows
end

function M:QuestLogRows(key)
	local record = Store():Get(key)
	local rows = {}
	local quests = record and type(record.quests) == "table" and record.quests or {}
	for _, entry in ipairs(type(quests.log) == "table" and quests.log or {}) do rows[#rows + 1] = entry end
	return rows
end

function M:RepRows(key)
	local record = Store():Get(key)
	local rows = {}
	for id, rep in pairs(record and type(record.reps) == "table" and record.reps or {}) do
		rows[#rows + 1] = { id = id, rep = rep }
	end
	return rows
end

local function ItemName(row)
	local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(row.short)
	if not name and row.id and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(row.id) end
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	local text = name or ("item:" .. tostring(row.id))
	if color and color.hex then text = color.hex .. text .. "|r" end
	icon = icon or (row.id and C_Item.GetItemIconByID and C_Item.GetItemIconByID(row.id))
	return (icon and ("|T%s:14:14:0:0:64:64:5:59:5:59|t "):format(icon) or "") .. text, name or ""
end

local function Standing(rep)
	local reaction = rep.reaction or 4
	local label = rawget(_G, "FACTION_STANDING_LABEL" .. reaction) or tostring(reaction)
	local color = E:ReactionColorObject(reaction)
	if color then label = Kit.Hex(color.r, color.g, color.b) .. label .. "|r" end
	return label
end

local VIEWS = {
	{ key = "summary", title = "Summary", desc = "Everything saved about the character: level, gold, played, rested, professions, lockouts, mail and stats.",
		rows = function(key) return M:SummaryRows(key) end,
		columns = {
			{ key = "left", title = "What", width = 230, value = function(row) return row.left end,
				color = function(row) if row.color then return row.color[1], row.color[2], row.color[3] end return Kit.TEXT[1], Kit.TEXT[2], Kit.TEXT[3] end },
			{ key = "right", title = "Value", value = function(row) return row.right or "" end },
		}, sortKey = "none" },
	{ key = "items", title = "Items", desc = "Items in the bags, bank and mailbox. The Bags button opens the Bags module's own windows on this character.",
		rows = function(key) return M:ItemRows(key) end,
		columns = {
			{ key = "item", title = "Item", value = function(row) return select(2, ItemName(row)) end, text = function(row) return (ItemName(row)) end },
			{ key = "count", title = "Count", width = 70, align = "RIGHT", value = function(row) return row.count end },
			{ key = "where", title = "Where", width = 110, value = function(row) return L[WHERE_TITLE[row.where]] end },
		}, sortKey = "item" },
	{ key = "gear", title = "Gear", desc = "The equipped items with their item levels.",
		rows = function(key) return M:GearRows(key) end,
		columns = {
			{ key = "slot", title = "Slot", width = 130, value = function(row) return row.slot end, text = function(row) return row.label end },
			{ key = "item", title = "Item", value = function(row) return select(2, ItemName(row)) end, text = function(row) return (ItemName(row)) end },
			{ key = "level", title = "Item level", width = 90, align = "RIGHT", value = function(row) return row.level or 0 end },
		}, sortKey = "slot" },
	{ key = "quests", title = "Quests", desc = "The quest log at the last logout.",
		rows = function(key) return M:QuestLogRows(key) end,
		columns = {
			{ key = "title", title = "Quest", value = function(row) return row.title or "" end,
				text = function(row) return (row.title or ("#" .. row.id)) .. (row.daily and Grey(" (" .. L["daily"] .. ")") or "") end },
			{ key = "level", title = "Level", width = 60, align = "RIGHT", value = function(row) return row.level or 0 end },
			{ key = "done", title = "Ready", width = 70, align = "RIGHT", value = function(row) return row.done and 1 or 0 end,
				text = function(row) return row.done and M.Good(L["ready"]) or "" end },
		}, sortKey = "level" },
	{ key = "reputation", title = "Reputation", desc = "Standing with each faction, in the game's groups.",
		rows = function(key) return M:RepRows(key) end,
		columns = {
			{ key = "group", title = "Group", width = 150, value = function(row) return row.rep.header or "" end },
			{ key = "name", title = "Faction", value = function(row) return row.rep.name or "" end },
			{ key = "standing", title = "Standing", width = 110, value = function(row) return (row.rep.reaction or 0) * 1e6 + (row.rep.value or 0) end,
				text = function(row) return Standing(row.rep) end },
			{ key = "progress", title = "Progress", width = 110, align = "RIGHT", value = function(row) return (row.rep.value or 0) - (row.rep.min or 0) end,
				text = function(row)
					local rep = row.rep
					if not (rep.min and rep.max and rep.max > rep.min) then return "" end
					return ("%d / %d"):format((rep.value or 0) - rep.min, rep.max - rep.min)
				end },
		}, sortKey = "group" },
}
M.CHARACTER_VIEWS = VIEWS
local VIEW_BY_KEY = {}
for _, view in ipairs(VIEWS) do VIEW_BY_KEY[view.key] = view end

local function Table(frame, viewKey)
	for _, tbl in pairs(frame.tables) do tbl:Hide() end
	local view = VIEW_BY_KEY[viewKey]
	local tbl = frame.tables[viewKey]
	if not tbl then
		tbl = Kit.CreateTable(frame.right, view.columns, {
			sortKey = view.sortKey, rowHeight = 18,
			onClick = function(row)
				if row.short and IsModifiedClick() and HandleModifiedItemClick then
					local _, link = C_Item.GetItemInfo(row.short)
					HandleModifiedItemClick(link or row.short)
				end
			end,
			createRow = function(widget)
				widget:HookScript("OnEnter", function(own)
					local row = own.item
					if not (row and row.short) then return end
					GameTooltip:SetOwner(own, "ANCHOR_RIGHT")
					GameTooltip:SetHyperlink(row.short)
					GameTooltip:Show()
				end)
				widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
			end,
			empty = { L["Nothing saved"], L["This character has not saved this part yet. It does at its next login (bank and mail at the next visit)."] },
		})
		tbl:SetPoint("TOPLEFT", frame.views, "BOTTOMLEFT", 0, -6)
		tbl:SetPoint("BOTTOMRIGHT")
		frame.tables[viewKey] = tbl
	end
	tbl:Show()
	return tbl, view
end

local function Update(frame)
	local keys = M:Keys()
	local found = false
	for _, key in ipairs(keys) do if key == frame.key then found = true end end
	if not found then frame.key = Store():Get(frame.key or "") and frame.key or keys[1] or E.charKey end
	local items = {}
	for _, key in ipairs(keys) do items[#items + 1] = { key = key, record = Store():Get(key) } end
	frame.list:SetData(items)
	local viewKey = next(frame.views:GetSelected()) or "summary"
	local tbl, view = Table(frame, viewKey)
	frame.rows = view.rows(frame.key)
	tbl:SetData(frame.rows)
	local record = Store():Get(frame.key)
	frame.name:SetText(record and (M.ClassIcon(record.class, 16) .. M.ClassName(record, true) .. Grey("  " .. L["level %d"]:format(record.level or 0))) or "")
	local bags = E.modules.Bags
	frame.bagsButton:SetShown(viewKey == "items" and bags and bags.ShowCharacterBags and bags.active and true or false)
end
M.UpdateCharacter = Update

M:AddTab({
	key = "character", order = 15, title = "Character",
	desc = "One character in detail: summary with stats, items, gear, quests and reputation.",
	create = function(content)
		local frame = CreateFrame("Frame", nil, content)
		frame:SetAllPoints()
		frame.tables = {}
		frame.list = Kit.CreateList(frame, Kit.ListRow2Template({
			gap = 1,
			create = function(row)
				row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
				row:SetScript("OnClick", function(own, button)
					if not own.item then return end
					if button == "RightButton" then
						M:ShowCharacterMenu(own, own.item.key)
					else
						frame.key = own.item.key
						Update(frame)
					end
				end)
			end,
			update = function(row, item)
				local record = item.record or {}
				row:SetRow(ListRowData(record, item.key == E.charKey))
				SetClassArt(row, record.class)
				row:SetSelected(item.key == frame.key, item.key)
			end,
		}))
		frame.list:SetPoint("TOPLEFT")
		frame.list:SetPoint("BOTTOMLEFT")
		frame.list:SetWidth(LIST_WIDTH)
		local line = Kit.Divider(frame)
		line:SetPoint("TOPLEFT", frame.list, "TOPRIGHT", 4, 0)
		line:SetPoint("BOTTOMLEFT", frame.list, "BOTTOMRIGHT", 4, 0)
		line:SetWidth(E.pixel or 1)
		frame.right = CreateFrame("Frame", nil, frame)
		frame.right:SetPoint("TOPLEFT", frame.list, "TOPRIGHT", 10, 0)
		frame.right:SetPoint("BOTTOMRIGHT")
		frame.header = CreateFrame("Frame", nil, frame.right)
		frame.header:SetPoint("TOPLEFT")
		frame.header:SetPoint("TOPRIGHT")
		frame.header:SetHeight(22)
		frame.name = Kit.Text(frame.header, 14, "LEFT", "header")
		frame.name:SetPoint("LEFT", 2, 0)
		frame.bagsButton = Kit.Button(frame.header, L["Open in Bags"], 110, 20, function()
			local bags = E.modules.Bags
			if bags and bags.ShowCharacterBags then bags:ShowCharacterBags(frame.key, "bags") end
		end, L["Open in Bags"], L["Shows this character's bags in the Bags module's own window."])
		frame.bagsButton:SetPoint("RIGHT", -2, 0)
		frame.views = Kit.ChipBar(frame.right, {
			selected = "summary",
			chips = (function()
				local list = {}
				for _, view in ipairs(VIEWS) do list[#list + 1] = { view.key, L[view.title], L[view.desc] } end
				return list
			end)(),
			onChange = function(selected, key)
				if not next(selected) then frame.views:SetSelected(key) end
				Update(frame)
			end,
		})
		frame.views:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 0, -4)
		return frame
	end,
	show = function(frame, arg)
		if type(arg) == "string" and Store():Get(arg) then frame.key = arg end
		Update(frame)
	end,
	refresh = function(frame) Update(frame) end,
})
