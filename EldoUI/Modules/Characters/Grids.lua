-- EldoUI Characters: the Grids tab.
--
-- Characters side by side: one column per character (a page at a time),
-- one row per thing. Grids: Equipment (each slot's item and item level),
-- Reputation (standing with every faction any character has seen),
-- Currencies, Professions and Lockouts. Hover a cell for details.
local _, E = ...
local L = E.L
local Key = E.Key
local Kit = E.UIKit
local M = E.modules.Characters

local function Store() return E.Characters end

local LABEL_WIDTH, CELL_WIDTH = 190, 82

local function Grey(text) return M.Grey(text) end

local SLOTS = {
	{ 1, "HEADSLOT", Key("Head") }, { 2, "NECKSLOT", Key("Neck") }, { 3, "SHOULDERSLOT", Key("Shoulder") }, { 15, "BACKSLOT", Key("Back") },
	{ 5, "CHESTSLOT", Key("Chest") }, { 4, "SHIRTSLOT", Key("Shirt") }, { 19, "TABARDSLOT", Key("Tabard") }, { 9, "WRISTSLOT", Key("Wrist") },
	{ 10, "HANDSSLOT", Key("Hands") }, { 6, "WAISTSLOT", Key("Waist") }, { 7, "LEGSSLOT", Key("Legs") }, { 8, "FEETSLOT", Key("Feet") },
	{ 11, "FINGER0SLOT", Key("Finger 1") }, { 12, "FINGER1SLOT", Key("Finger 2") }, { 13, "TRINKET0SLOT", Key("Trinket 1") },
	{ 14, "TRINKET1SLOT", Key("Trinket 2") }, { 16, "MAINHANDSLOT", Key("Main hand") }, { 17, "SECONDARYHANDSLOT", Key("Off hand") },
	{ 18, "RANGEDSLOT", Key("Ranged") },
}

local function ItemCell(short)
	if not short then return Grey("-") end
	local level = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(short)
	local _, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(short)
	icon = icon or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(Store().ItemIDOf(short)))
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	local text = level and tostring(level) or ""
	if color and color.hex then text = color.hex .. text .. "|r" end
	return (icon and ("|T%s:14:14:0:0:64:64:5:59:5:59|t "):format(icon) or "") .. text
end

local function StandingText(rep)
	local reaction = rep.reaction or 4
	local label = rawget(_G, "FACTION_STANDING_LABEL" .. reaction) or tostring(reaction)
	local color = E:ReactionColorObject(reaction)
	if color then label = Kit.Hex(color.r, color.g, color.b) .. label .. "|r" end
	return label
end

-- Each grid: rows(keys) -> { { label, cell = fn(record) -> text, tip = fn(tooltip, record) } }.
local GRIDS = {
	{ key = "equipment", title = "Equipment", desc = "Each slot's item and item level per character, as of its last login.",
		rows = function()
			local rows = {}
			for _, slot in ipairs(SLOTS) do
				rows[#rows + 1] = {
					label = rawget(_G, slot[2]) or L[slot[3]],
					cell = function(record) return ItemCell(type(record.equip) == "table" and record.equip[slot[1]] or nil) end,
					tip = function(tooltip, record)
						local short = type(record.equip) == "table" and record.equip[slot[1]]
						if short then tooltip:SetHyperlink(short) return true end
					end,
				}
			end
			return rows
		end },
	{ key = "reputation", title = "Reputation", desc = "Standing with every faction any of these characters has seen. Factions under a collapsed header keep their last value.",
		rows = function(keys)
			local seen, rows = {}, {}
			for _, key in ipairs(keys) do
				for id, rep in pairs(type(Store():Get(key).reps) == "table" and Store():Get(key).reps or {}) do
					if not seen[id] then
						seen[id] = true
						rows[#rows + 1] = {
							label = rep.name, group = rep.header or "",
							cell = function(record)
								local own = type(record.reps) == "table" and record.reps[id]
								return own and StandingText(own) or Grey("-")
							end,
							tip = function(tooltip, record)
								local own = type(record.reps) == "table" and record.reps[id]
								if not own then return end
								Kit.TipTitle(tooltip, own.name)
								tooltip:AddDoubleLine(StandingText(own), own.max and own.min and ("%d / %d"):format((own.value or 0) - own.min, own.max - own.min) or "")
								return true
							end,
						}
					end
				end
			end
			table.sort(rows, function(a, b)
				if a.group ~= b.group then return a.group < b.group end
				return a.label < b.label
			end)
			return rows
		end },
	{ key = "currencies", title = "Currencies", desc = "Every currency these characters hold.",
		rows = function(keys)
			local seen, rows = {}, {}
			for _, key in ipairs(keys) do
				for id in pairs(type(Store():Get(key).currency) == "table" and Store():Get(key).currency or {}) do
					if not seen[id] then
						seen[id] = true
						local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
						local name = type(info) == "table" and info.name or ("#" .. id)
						local icon = type(info) == "table" and info.iconFileID
						rows[#rows + 1] = {
							label = (icon and ("|T%s:14:14:0:0:64:64:5:59:5:59|t "):format(icon) or "") .. name, sort = name,
							cell = function(record)
								local amount = type(record.currency) == "table" and record.currency[id]
								return amount and (BreakUpLargeNumbers and BreakUpLargeNumbers(amount) or tostring(amount)) or Grey("-")
							end,
						}
					end
				end
			end
			table.sort(rows, function(a, b) return a.sort < b.sort end)
			return rows
		end },
	{ key = "professions", title = "Professions", desc = "Skill in every profession per character.",
		rows = function(keys)
			local seen, rows = {}, {}
			for _, key in ipairs(keys) do
				for name in pairs(type(Store():Get(key).profs) == "table" and Store():Get(key).profs or {}) do
					if not seen[name] then
						seen[name] = true
						rows[#rows + 1] = {
							label = name,
							cell = function(record)
								local entry = type(record.profs) == "table" and record.profs[name]
								if not entry then return Grey("-") end
								local text = ("%d/%d"):format(entry.rank or 0, entry.max or 0)
								-- At its cap with a next rank to train: no more skill until then.
								if (entry.rank or 0) >= (entry.max or 1) and (entry.max or 0) < 300 then text = M.Warn(text) end
								return text
							end,
						}
					end
				end
			end
			table.sort(rows, function(a, b) return a.label < b.label end)
			return rows
		end },
	{ key = "lockouts", title = "Lockouts", desc = "Bosses killed per instance and character, until the reset.",
		rows = function(keys)
			local seen, rows = {}, {}
			local now = Store().Now()
			for _, key in ipairs(keys) do
				for id, lock in pairs(type(Store():Get(key).lockouts) == "table" and Store():Get(key).lockouts or {}) do
					if not seen[id] and (lock.resetAt or 0) > now then
						seen[id] = true
						rows[#rows + 1] = {
							label = lock.name .. (lock.difficulty and Grey(" " .. lock.difficulty) or ""), sort = lock.name,
							cell = function(record)
								local own = type(record.lockouts) == "table" and record.lockouts[id]
								if not own or (own.resetAt or 0) <= now then return Grey("-") end
								if own.total and own.total > 0 then
									local text = ("%d/%d"):format(own.done or 0, own.total)
									return (own.done or 0) >= own.total and M.Bad(text) or text
								end
								return M.Bad(L["saved"])
							end,
							tip = function(tooltip, record)
								local own = type(record.lockouts) == "table" and record.lockouts[id]
								if not own then return end
								Kit.TipTitle(tooltip, own.name)
								tooltip:AddDoubleLine(L["Resets in"], M.Duration((own.resetAt or now) - now))
								return true
							end,
						}
					end
				end
			end
			table.sort(rows, function(a, b) return a.sort < b.sort end)
			return rows
		end },
}
M.GRIDS = GRIDS
local GRID_BY_KEY = {}
for _, grid in ipairs(GRIDS) do GRID_BY_KEY[grid.key] = grid end

-- More grids from other modules (the Attunements tab): def = { key, title,
-- desc, rows = fn(keys) } like the ones above; the chips follow.
local gridFrame
local BuildChips -- below

function M:AddGrid(def)
	if type(def) ~= "table" or type(def.key) ~= "string" or type(def.rows) ~= "function" then return end
	if GRID_BY_KEY[def.key] then self:RemoveGrid(def.key) end
	GRIDS[#GRIDS + 1] = def
	GRID_BY_KEY[def.key] = def
	if gridFrame and BuildChips then BuildChips(gridFrame) end
end

function M:RemoveGrid(key)
	local grid = GRID_BY_KEY[key]
	if not grid then return end
	GRID_BY_KEY[key] = nil
	for index, other in ipairs(GRIDS) do
		if other == grid then table.remove(GRIDS, index) break end
	end
	if gridFrame and BuildChips then BuildChips(gridFrame) end
end

function M:GridRows(gridKey, keys)
	local grid = GRID_BY_KEY[gridKey] or GRIDS[1]
	return grid.rows(keys or self:Keys())
end

local function PageSize(frame)
	local width = frame:GetWidth()
	if not width or width < 300 then width = 804 end
	return math.max(math.floor((width - LABEL_WIDTH - 12) / CELL_WIDTH), 1)
end

local function CellEnter(cell)
	local row = cell:GetParent()
	local item, key = row.item, cell.key
	if not (item and key) then return end
	local record = Store():Get(key)
	GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
	local shown = item.tip and item.tip(GameTooltip, record)
	if not shown then
		GameTooltip:AddLine(M.ClassName(record, true))
		GameTooltip:AddDoubleLine(item.label, item.cell(record), Kit.SECONDARY[1], Kit.SECONDARY[2], Kit.SECONDARY[3], 1, 1, 1)
	end
	GameTooltip:Show()
end

-- The grid chips (built again when a grid comes or goes).
BuildChips = function(frame)
	local selected = frame.which and next(frame.which:GetSelected()) or "equipment"
	if not GRID_BY_KEY[selected] then selected = "equipment" end
	if frame.which then frame.which:Hide() end
	frame.which = Kit.ChipBar(frame.toolbar, {
		selected = selected,
		chips = (function()
			local list = {}
			for _, grid in ipairs(GRIDS) do list[#list + 1] = { grid.key, L[grid.title], L[grid.desc] } end
			return list
		end)(),
		onChange = function(chosen, key)
			if not next(chosen) then frame.which:SetSelected(key) end
			M.UpdateGrids(frame)
		end,
	})
	frame.which:SetPoint("LEFT", 2, 0)
	if frame.list and frame:IsVisible() and M.UpdateGrids then M.UpdateGrids(frame) end
end

local function Update(frame)
	local keys = M:Keys()
	local size = PageSize(frame)
	local pages = math.max(math.ceil(#keys / size), 1)
	frame.page = math.min(math.max(frame.page or 1, 1), pages)
	local first = (frame.page - 1) * size + 1
	local shown = {}
	for index = first, math.min(first + size - 1, #keys) do shown[#shown + 1] = keys[index] end
	frame.columns = shown
	for index = 1, math.max(#frame.heads, size) do
		local head = frame.heads[index]
		if not head then
			head = Kit.Text(frame.header, 11, "CENTER")
			head:SetWidth(CELL_WIDTH - 4)
			head:SetWordWrap(false)
			head:SetPoint("LEFT", frame.header, "LEFT", LABEL_WIDTH + (index - 1) * CELL_WIDTH + 2, 0)
			frame.heads[index] = head
		end
		local key = shown[index]
		head:SetText(key and M.ClassName(Store():Get(key)) or "")
	end
	frame.pageText:SetText(L["%d-%d of %d"]:format(#shown > 0 and first or 0, first + #shown - 1, #keys))
	frame.prev:SetEnabled(frame.page > 1)
	frame.next:SetEnabled(frame.page < pages)
	local grid = next(frame.which:GetSelected()) or "equipment"
	frame.grid = grid
	frame.rows = M:GridRows(grid, keys)
	frame.list:SetData(frame.rows)
end
M.UpdateGrids = Update

M:AddTab({
	key = "grids", order = 65, title = "Grids",
	desc = "Your characters side by side: equipment, reputation, currencies, professions and lockouts.",
	create = function(content)
		local frame = CreateFrame("Frame", nil, content)
		frame:SetAllPoints()
		frame.heads = {}
		frame.toolbar = CreateFrame("Frame", nil, frame)
		frame.toolbar:SetPoint("TOPLEFT")
		frame.toolbar:SetPoint("TOPRIGHT")
		frame.toolbar:SetHeight(20)
		gridFrame = frame
		BuildChips(frame)
		frame.next = E.UIKit.IconButton(frame.toolbar, 20, "chevron-right", function() frame.page = frame.page + 1 Update(frame) end,
			L["Next characters"], L["Shows the next page of characters."])
		frame.next:SetPoint("RIGHT", -2, 0)
		frame.pageText = Kit.Text(frame.toolbar, 11, "CENTER", "secondary")
		frame.pageText:SetWidth(80)
		frame.pageText:SetPoint("RIGHT", frame.next, "LEFT", -4, 0)
		frame.prev = E.UIKit.IconButton(frame.toolbar, 20, "chevron-left", function() frame.page = frame.page - 1 Update(frame) end,
			L["Previous characters"], L["Shows the previous page of characters."])
		frame.prev:SetPoint("RIGHT", frame.pageText, "LEFT", -4, 0)
		frame.header = CreateFrame("Frame", nil, frame)
		frame.header:SetPoint("TOPLEFT", frame.toolbar, "BOTTOMLEFT", 0, -6)
		frame.header:SetPoint("TOPRIGHT", frame.toolbar, "BOTTOMRIGHT", 0, -6)
		frame.header:SetHeight(20)
		local line = Kit.Divider(frame.header)
		line:SetPoint("BOTTOMLEFT")
		line:SetPoint("BOTTOMRIGHT")
		frame.list = Kit.CreateList(frame, {
			rowHeight = 18,
			empty = { L["Nothing to show"], L["None of these characters has saved anything for this grid yet."] },
			create = function(row)
				E:SkinRow(row)
				row.label = Kit.Text(row, 12, "LEFT")
				row.label:SetPoint("LEFT", 4, 0)
				row.label:SetWidth(LABEL_WIDTH - 8)
				row.label:SetWordWrap(false)
				row.cells = {}
			end,
			update = function(row, item)
				row.label:SetText(item.label)
				for index = 1, math.max(#row.cells, #frame.columns) do
					local cell = row.cells[index]
					if not cell then
						cell = CreateFrame("Button", nil, row)
						cell:SetSize(CELL_WIDTH - 4, 18)
						cell:SetPoint("LEFT", row, "LEFT", LABEL_WIDTH + (index - 1) * CELL_WIDTH + 2, 0)
						cell.text = Kit.Text(cell, 12, "CENTER")
						cell.text:SetAllPoints()
						cell:SetScript("OnEnter", CellEnter)
						cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
						row.cells[index] = cell
					end
					local key = frame.columns[index]
					cell.key = key
					cell.text:SetText(key and item.cell(Store():Get(key)) or "")
					cell:SetShown(key ~= nil)
				end
			end,
		})
		frame.list:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 0, -2)
		frame.list:SetPoint("BOTTOMRIGHT")
		return frame
	end,
	show = function(frame, arg)
		if GRID_BY_KEY[arg] then frame.which:SetSelected(arg) end
		Update(frame)
	end,
	refresh = function(frame) Update(frame) end,
})
