-- EldoUI Waypoints: the Waypoints window. Every waypoint of this character
-- by zone (the zone you are in first), with the arrow's waypoint marked.
--
--   +--------------------------------------------+
--   | Waypoints                              [x] |
--   | 5 waypoints in 2 zones                     |
--   |============================================|
--   | 5 waypoints               Sort [Distance v]|
--   | ELWYNN FOREST  3                       [x] |  zone, count, remove all here
--   | > Goldshire          42.10, 65.30   120 yd |  arrow's waypoint, coords, distance
--   |   Fargodeep Mine     38.50, 81.60   410 yd |
--   | WESTFALL  2                            [x] |
--   |--------------------------------------------|
--   | Export     Paste     Remove all            |
--   +--------------------------------------------+
--
-- Click a line to point the arrow there, right-click to remove it. Export
-- shows one /way line per waypoint (two decimals, so pasting them back
-- lands on the same spots) for the player to copy; nothing is sent. Paste
-- opens the paste window.
--
-- Rules: presentation only. The window lists EldoUI's own waypoint store;
-- a distance shows only where the game gives your position (M:Distance),
-- never a guess.
local _, E = ...
local L = E.L
local M = E.Waypoints
local UI = E.UIKit

local ROW = 26
local TICK = 2 -- seconds between distance refreshes while the window is open
local OPTIONS_LINK = { page = "module:Waypoints" } -- Ctrl-click opens the settings
M.LIST_SORTS = { distance = "Distance", added = "Added" }

---------------------------------------------------------------------------
-- Data: zone sections, then their waypoints
---------------------------------------------------------------------------
local function Listed(wp)
	-- Your corpse is a passing point of its own, not part of a route.
	return wp and wp.source ~= "corpse"
end

-- The list as rows: { header = true, mapID, name, count } before each
-- zone's { wp, uid, distance } rows. The zone you are in comes first, the
-- others by name. Sort: "distance" (nearest first; unknown last, in the
-- order added) or "added".
function M:ListRows(sort)
	sort = sort or self.db.listSort
	local zones, byMap, added = {}, {}, {}
	for index, uid in ipairs(self.order) do
		local wp = self.points[uid]
		if Listed(wp) then
			added[uid] = index
			local zone = byMap[wp.mapID]
			if not zone then
				zone = { mapID = wp.mapID, name = M.MapName(wp.mapID), rows = {} }
				byMap[wp.mapID] = zone
				zones[#zones + 1] = zone
			end
			zone.rows[#zone.rows + 1] = { uid = uid, wp = wp, distance = self:Distance(wp) }
		end
	end
	local here = M.PlayerPos()
	table.sort(zones, function(a, b)
		if (a.mapID == here) ~= (b.mapID == here) then return a.mapID == here end
		if a.name ~= b.name then return a.name < b.name end
		return a.mapID < b.mapID
	end)
	local rows = {}
	for _, zone in ipairs(zones) do
		if sort ~= "added" then
			table.sort(zone.rows, function(a, b)
				if a.distance and b.distance then
					if a.distance ~= b.distance then return a.distance < b.distance end
				elseif a.distance or b.distance then
					return a.distance ~= nil
				end
				return added[a.uid] < added[b.uid]
			end)
		end
		rows[#rows + 1] = { header = true, mapID = zone.mapID, name = zone.name, count = #zone.rows }
		for _, row in ipairs(zone.rows) do rows[#rows + 1] = row end
	end
	return rows, #zones
end

-- One /way line per waypoint, in the order added. Two decimals, so a
-- paste merges onto the same spots instead of adding new ones.
function M:ExportText()
	local lines = {}
	for _, wp in self:Iterate() do
		if Listed(wp) then
			lines[#lines + 1] = strtrim(("/way #%d %.2f %.2f %s"):format(wp.mapID, wp.x * 100, wp.y * 100, wp.title or ""))
		end
	end
	return table.concat(lines, "\n"), #lines
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function RowTooltip(row)
	local item = row.item
	if not item then return end
	UI.AnchorTooltip(row)
	if item.header then
		UI.TipTitle(GameTooltip, item.name)
		UI.TipText(GameTooltip, E:Plural(item.count, "%d waypoint in this zone.", "%d waypoints in this zone."):format(item.count))
		GameTooltip:Show()
		return
	end
	local wp = item.wp
	UI.TipTitle(GameTooltip, wp.title or L["waypoint"])
	local r, g, b = M.Shade("SECONDARY")
	GameTooltip:AddLine(("%s %s"):format(M.MapName(wp.mapID), M.FormatCoords(wp.x, wp.y)), r, g, b)
	if item.distance then GameTooltip:AddLine(M.FormatDistance(item.distance), r, g, b) end
	if item.uid == M.arrowUid then GameTooltip:AddLine(L["The arrow points here."], unpack(E.tokens.text.good)) end
	UI.TooltipHint(GameTooltip, { L["Click"], L["point the arrow here"] }, { L["Right-click"], L["remove it"] })
	GameTooltip:Show()
end

local function RowClick(row, button)
	local item = row.item
	if not item or E:IsOptionsLinkClick(row, button) then return end
	if item.header then return end
	if button == "RightButton" then
		M:Remove(item.uid)
	else
		M:SetArrow(item.uid)
	end
end

local function CreateRow(row)
	row:EnableMouse(true)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	row.mark = UI.Text(row, E.tokens.size.body, "LEFT")
	row.mark:SetPoint("LEFT", 6, 0)
	row.mark:SetWidth(12)
	row.name = UI.Text(row, E.tokens.size.body, "LEFT")
	row.name:SetWordWrap(false)
	row.distance = UI.Text(row, E.tokens.size.small, "RIGHT", "secondary")
	row.distance:SetPoint("RIGHT", -8, 0)
	row.distance:SetWidth(64)
	row.coords = UI.Text(row, E.tokens.size.small, "RIGHT", "secondary")
	row.coords:SetPoint("RIGHT", row.distance, "LEFT", -6, 0)
	row.coords:SetWidth(84)
	row.name:SetPoint("LEFT", row.mark, "RIGHT", 2, 0)
	row.name:SetPoint("RIGHT", row.coords, "LEFT", -6, 0)
	row.zone = UI.Text(row, E.tokens.size.small, "LEFT", "header")
	row.zone:SetPoint("LEFT", 6, -2)
	row.zone:SetWordWrap(false)
	row.count = UI.Text(row, E.tokens.size.small, "LEFT", "secondary")
	row.count:SetPoint("LEFT", row.zone, "RIGHT", 6, 0)
	row.clear = UI.IconButton(row, 18, "cross", function(button)
		local item = button:GetParent().item
		if item and item.header then M:AskRemoveAll(item.mapID) end
	end, L["Remove all here"], L["Remove every waypoint in this zone. It asks first."], nil, { danger = true })
	row.clear:SetPoint("RIGHT", -6, -2)
	row.line = UI.Divider(row)
	row.line:SetPoint("BOTTOMLEFT", 4, 0)
	row.line:SetPoint("BOTTOMRIGHT", -4, 0)
	row:SetScript("OnEnter", RowTooltip)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:SetScript("OnClick", RowClick)
	E:BindOptionsLink(row, OPTIONS_LINK)
end

local function UpdateRow(row, item)
	local header = item.header and true or false
	row.zone:SetShown(header)
	row.count:SetShown(header)
	row.clear:SetShown(header)
	row.line:SetShown(header)
	row.mark:SetShown(not header)
	row.name:SetShown(not header)
	row.coords:SetShown(not header)
	row.distance:SetShown(not header)
	if header then
		row.zone:SetText(item.name:upper())
		row.count:SetText(tostring(item.count))
		return
	end
	local wp = item.wp
	local arrow = item.uid == M.arrowUid
	row.mark:SetText(arrow and (M.Accent() .. ">|r") or "")
	row.name:SetText(wp.title or L["waypoint"])
	row.name:SetTextColor(unpack(arrow and E.tokens.text.body or E.tokens.text.secondary))
	row.coords:SetText(("%.2f, %.2f"):format(wp.x * 100, wp.y * 100))
	-- The distance only where the game gives your position.
	local distance = M:Distance(wp)
	item.distance = distance
	row.distance:SetText(distance and M.FormatDistance(distance) or "")
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
function M:BuildList()
	if self.listFrame then return self.listFrame end
	local Kit = E.WindowKit
	local frame = Kit.CreateWindow("EldoUI_WaypointList", { width = 440, height = 460, strata = "DIALOG", footer = 40, headerHeight = 54, resizable = true })
	frame:SetTitle(L["Waypoints"], "")
	local content = frame.content

	-- The bar above the list: the count, and the sort.
	frame.bar = CreateFrame("Frame", nil, content)
	frame.bar:SetPoint("TOPLEFT")
	frame.bar:SetPoint("TOPRIGHT")
	frame.bar:SetHeight(E.tokens.height.button)
	frame.total = UI.Text(frame.bar, E.tokens.size.label, "LEFT", "secondary")
	frame.total:SetPoint("LEFT", 2, 0)
	frame.sort = UI.Dropdown(frame.bar, {
		width = 120,
		values = { { "distance", M.LIST_SORTS.distance }, { "added", M.LIST_SORTS.added } },
		get = function() return M.db.listSort end,
		set = function(value) M.db.listSort = value M:RefreshList() end,
		tipTitle = L["Sort"], tip = L["Nearest first (where the game gives your position), or in the order you added them."],
	})
	frame.sort:SetPoint("RIGHT", 0, 0)
	frame.sortLabel = UI.Text(frame.bar, E.tokens.size.label, "RIGHT", "secondary")
	frame.sortLabel:SetPoint("RIGHT", frame.sort, "LEFT", -6, 0)
	frame.sortLabel:SetText(L["Sort"])

	frame.list = UI.CreateList(content, {
		rowHeight = ROW,
		create = CreateRow,
		update = UpdateRow,
		empty = { L["No waypoints"], L["Add one with /way 45 63 or Ctrl+right-click on the world map."] },
	})
	frame.list:SetPoint("TOPLEFT", frame.bar, "BOTTOMLEFT", 0, -6)
	frame.list:SetPoint("BOTTOMRIGHT")

	-- The export view: the /way lines, selected for Ctrl+C.
	frame.export = CreateFrame("Frame", nil, content)
	frame.export:SetPoint("TOPLEFT", frame.bar, "BOTTOMLEFT", 0, -6)
	frame.export:SetPoint("BOTTOMRIGHT")
	E:SetTemplate(frame.export, true)
	local scroll = CreateFrame("ScrollFrame", nil, frame.export, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -24, 6)
	if scroll.ScrollBar then E:SkinScrollBar(scroll.ScrollBar) end
	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetMaxLetters(0)
	box:SetWidth(360)
	E:SetFont(box, E.tokens.size.label)
	box:SetScript("OnEscapePressed", function() M:ShowListView() end)
	-- The text stays what EldoUI wrote: typing in it changes nothing.
	box:SetScript("OnTextChanged", function(edit, user)
		if user then
			edit:SetText(frame.exportText or "")
			edit:HighlightText()
		end
	end)
	scroll:SetScrollChild(box)
	scroll:SetScript("OnSizeChanged", function(_, width)
		if width and width > 0 then box:SetWidth(width) end
	end)
	frame.export:EnableMouse(true)
	frame.export:SetScript("OnMouseDown", function() box:SetFocus() box:HighlightText() end)
	frame.exportBox = box
	frame.export:Hide()

	-- Footer: Export, Paste, Remove all; in the export view Back.
	frame.exportButton = Kit.Button(frame.footer, L["Export"], 100, function() M:ShowExport() end)
	frame.exportButton:SetPoint("LEFT", frame.footer, "LEFT", 0, 0)
	frame.pasteButton = Kit.Button(frame.footer, L["Paste"], 100, function() M:ShowPaste() end)
	frame.pasteButton:SetPoint("LEFT", frame.exportButton, "RIGHT", 8, 0)
	frame.removeButton = Kit.Button(frame.footer, L["Remove all"], 110, function() M:AskRemoveAll() end)
	frame.removeButton:SetPoint("RIGHT", frame.footer, "RIGHT", 0, 0)
	UI.SetButtonKind(frame.removeButton, "danger")
	frame.backButton = Kit.Button(frame.footer, L["Back to the list"], 130, function() M:ShowListView() end)
	frame.backButton:SetPoint("RIGHT", frame.footer, "RIGHT", 0, 0)
	frame.copyHint = UI.Text(frame.footer, E.tokens.size.small, "LEFT", "secondary")
	frame.copyHint:SetPoint("LEFT", frame.footer, "LEFT", 0, 0)
	frame.copyHint:SetPoint("RIGHT", frame.backButton, "LEFT", -8, 0)
	frame.copyHint:SetWordWrap(true)
	frame.copyHint:SetText(L["Press Ctrl+C to copy. Paste the lines into Paste waypoints to add them again."])

	-- Distances follow you while the window is open.
	frame.elapsed = 0
	frame:SetScript("OnUpdate", function(window, elapsed)
		window.elapsed = window.elapsed + elapsed
		if window.elapsed < TICK then return end
		window.elapsed = 0
		if window.list:IsShown() then window.list:Refresh() end
	end)
	frame:HookScript("OnHide", function() box:ClearFocus() end)
	frame:Hide()
	self.listFrame = frame
	return frame
end

function M:ShowListView()
	local frame = self.listFrame
	if not frame then return end
	frame.exporting = false
	frame.exportBox:ClearFocus()
	frame.export:Hide()
	frame.list:Show()
	frame.bar:Show()
	frame.backButton:Hide()
	frame.copyHint:Hide()
	frame.exportButton:Show()
	frame.pasteButton:Show()
	frame.removeButton:Show()
	self:RefreshList()
end

function M:ShowExport()
	local frame = self:BuildList()
	local text, count = self:ExportText()
	frame.exporting = true
	frame.exportText = text
	frame.list:Hide()
	frame.export:Show()
	frame.exportButton:Hide()
	frame.pasteButton:Hide()
	frame.removeButton:Hide()
	frame.backButton:Show()
	frame.copyHint:Show()
	frame.total:SetText(E:Plural(count, "%d line to copy", "%d lines to copy"):format(count))
	frame.sort:Hide()
	frame.sortLabel:Hide()
	frame.exportBox:SetText(text)
	frame.exportBox:SetFocus()
	frame.exportBox:HighlightText()
end

-- Rebuild the rows (after a change) while the window is open.
function M:RefreshList()
	local frame = self.listFrame
	if not (frame and frame:IsShown()) or frame.exporting then return end
	local rows, zones = self:ListRows()
	local count = #rows - zones
	local subtitle
	if count == 0 then
		subtitle = L["No waypoints yet."]
	elseif zones == 1 then
		subtitle = E:Plural(count, "%d waypoint in one zone. Click one to point the arrow there.", "%d waypoints in one zone. Click one to point the arrow there."):format(count)
	else
		subtitle = E:Plural(count, "%d waypoint in %d zones. Click one to point the arrow there.",
			"%d waypoints in %d zones. Click one to point the arrow there."):format(count, zones)
	end
	frame:SetTitle(L["Waypoints"], subtitle)
	frame.total:SetText("")
	frame.sort:Show()
	frame.sortLabel:Show()
	frame.sort:Refresh()
	frame.sort:SetEnabled(count > 1)
	frame.exportButton:SetEnabled(count > 0)
	frame.removeButton:SetEnabled(count > 0)
	frame.elapsed = 0
	frame.list:SetData(rows)
end

function M:ShowList()
	local frame = self:BuildList()
	frame:Show()
	self:ShowListView()
	return frame
end

function M:ToggleList()
	if self.listFrame and self.listFrame:IsShown() then
		self.listFrame:Hide()
	else
		self:ShowList()
	end
end

-- Every change to the store redraws the pins; the open list follows them.
hooksecurefunc(M, "RefreshPins", function() M:RefreshList() end)
hooksecurefunc(M, "SetArrow", function() M:RefreshList() end)
