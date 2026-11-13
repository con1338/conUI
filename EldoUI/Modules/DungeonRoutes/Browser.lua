-- EldoUI Dungeon Routes: the "Dungeons" window.
--
--   +--------------------------------------------------------------------+
--   | Dungeons   Map  My routes                                      ? x |
--   |--------------------------------------------------------------------|
--   | Ragefire    | The Deadmines [Floor 1][Floor 2] [Schematic] [Route v]|
--   | Wailing ... |+----------------------------------+ Route: Boss to b.|
--   | > Deadmines ||  dungeon map: packs, patrols,    | 1  3 mobs (Miner)|
--   | Shadowfang  ||  bosses, route line, pull tags   | 2  Patrol        |
--   | ...         |+----------------------------------+ [Copy][Export]...|
--   |             | [Edit] opens the editor's tool strip (Editor.lua)    |
--   |--------------------------------------------------------------------|
--   | Packs from the Classic data · no live position inside dungeons     |
--   +--------------------------------------------------------------------+
--
-- Built from E.UIKit (the Loot Guide look) and E.DungeonMaps' canvas; the
-- overlay (Overlay.lua) draws on it. "My routes" lists your own routes of
-- every dungeon. The window remembers its place and scale (no mover: it is
-- a tool window, like the Loot Guide). Inside a dungeon it opens on that
-- dungeon and follows you to the next one ("Open the dungeon you are in").
-- "From your group" lists routes your group sent (Group.lua, opt-in).
-- Planning only: nothing here pulls, targets or marks.
local _, E = ...
local L = E.L
local M = E.DungeonRoutes
local Kit = E.UIKit
local DM = E.DungeonMaps

local WIDTH, HEIGHT = 1040, 640
local LIST_W, SIDE_W = 190, 240
local BAR_H = 26

local win
local state = { key = nil, floor = nil, view = nil, selected = nil }

local function Grey()
	return Kit.SECONDARY[1], Kit.SECONDARY[2], Kit.SECONDARY[3]
end

---------------------------------------------------------------------------
-- Dialogs
---------------------------------------------------------------------------
function M:AskText(question, text, accept)
	E:ShowConfirm({ key = "ELDOUI_ROUTES_TEXT", title = L["Dungeon Routes"], text = question, accept = ACCEPT,
		edit = { text = text or "", maxLetters = 60 },
		onAccept = function(_, typed) if accept then accept(typed or "") end end })
end

function M:Confirm(question, accept)
	E:ShowConfirm({ key = "ELDOUI_ROUTES_CONFIRM", title = L["Dungeon Routes"], text = question, accept = YES, cancel = NO,
		danger = true, onAccept = function() if accept then accept() end end })
end

function M:AskRename(route)
	if not (route and route.id) then return end
	self:AskText(L["Name of the route:"], route.name, function(text) M:RenameRoute(route.id, text) end)
end

function M:AskDelete(route)
	if not (route and route.id) then return end
	self:Confirm((L["Delete the route \"%s\"?"]):format(route.name or "?"), function() M:DeleteRoute(route.id) end)
end

function M:AskPullLabel(route, index)
	local pull = route and route.id and route.pulls[index]
	if not pull then return end
	self:AskText((L["Label of pull %d (empty: none):"]):format(index), pull.l or "", function(text) M:SetPullLabel(route.id, index, text) end)
end

---------------------------------------------------------------------------
-- Menus
---------------------------------------------------------------------------
local function ColorText(key, text)
	return Kit.Hex(M:ColorRGB(key)) .. text .. "|r"
end

function M:RouteMenu(owner)
	if not state.key then return end
	local key = state.key
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(L["Routes"])
		local active = M:ActiveRoute(key)
		for _, route in ipairs(M:Routes(key)) do
			local label = route.name or "?"
			if route == active then label = Kit.AccentHex() .. label .. "|r" end
			root:CreateButton(label, function() M:SetActiveRoute(key, route.shipped and "shipped" or route) end)
		end
		root:CreateDivider()
		root:CreateButton(L["Copy as my route"], function() M:CopyRoute(M:ActiveRoute(key)) end)
		root:CreateButton(L["New empty route"], function() M:NewRoute(key) end)
		if active and active.id then
			root:CreateButton(L["Rename"], function() M:AskRename(active) end)
			root:CreateButton(L["Delete"], function() M:AskDelete(active) end)
		end
		if active and M.SendToGroup then
			root:CreateButton(L["Send to group"], function() M:SendFromWindow(active) end)
		end
		root:CreateButton(L["Import a route"], function() M:ShowImport() end)
	end, { at = "owner" })
end

function M:PullMenu(owner, index)
	if not state.key then return end
	local route = M:ActiveRoute(state.key)
	if not route then return end
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle((L["Pull %d"]):format(index))
		if not route.id then
			root:CreateButton(L["Copy as my route to change labels and colors"], function() M:CopyRoute(route) end)
			return
		end
		root:CreateButton(L["Label"], function() M:AskPullLabel(route, index) end)
		local colors = root:CreateButton(L["Color"])
		for _, color in ipairs(M.COLORS) do
			colors:CreateButton(ColorText(color.key, color.label), function() M:SetPullColor(route.id, index, color.key) end)
		end
		root:CreateDivider()
		if index > 1 then root:CreateButton(L["Move up"], function() M:DropPull(index, index - 1) end) end
		if index < #route.pulls then root:CreateButton(L["Move down"], function() M:DropPull(index, index + 1) end) end
		if index > 1 then root:CreateButton(L["Join the pull before"], function() M:MergePull(route.id, index) end) end
		root:CreateButton(L["Delete this pull"], function() M:DeletePull(route.id, index) end)
	end)
end

---------------------------------------------------------------------------
-- Map tab
---------------------------------------------------------------------------
local function ViewFor(mapKey, floor)
	local wanted = state.view or M.db.view
	local floors = mapKey and DM:Floors(mapKey) or {}
	local entry = floors[floor or 1]
	local artBounds = entry and entry.tiles and DM:Bounds(mapKey, floor, "art")
	if wanted == "layout" then return "layout" end
	if wanted == "art" then return entry and entry.tiles and "art" or "layout" end
	return artBounds and "art" or "layout"
end

local function Hint(ctx)
	local tool = M.editor and M.editor.on and M.TOOLS
	if tool then
		for _, entry in ipairs(M.TOOLS) do
			if entry.key == M.editor.tool then return entry.desc end
		end
	end
	local parts = {}
	if not ctx or not ctx.bounds then
		parts[#parts + 1] = L["No floor edges for this map: try Schematic, or pick the floor while you are inside."]
	elseif ctx.view == "layout" then
		parts[#parts + 1] = L["Schematic: packs placed by where they stand (Classic data, approximate)."]
	else
		parts[#parts + 1] = L["Packs from the Classic data; WoW: Forever may differ."]
	end
	parts[#parts + 1] = L["No live position inside dungeons."]
	return table.concat(parts, "  ·  ")
end

local function DungeonRows(frame)
	local items = {}
	local here = M:CurrentDungeon()
	for _, entry in ipairs(M:Dungeons()) do
		items[#items + 1] = { key = entry.key, name = entry.name, min = entry.min, max = entry.max, here = entry.key == here }
	end
	frame.list:SetData(items)
end

local function UpdateFloorButtons(frame, floors, floor)
	local anchor = frame.title
	for index = 1, math.max(#floors, #frame.floorButtons) do
		local entry = floors[index]
		local button = frame.floorButtons[index]
		if entry and #floors > 1 then
			if not button then
				button = Kit.Button(frame.bar, "", 70, 20, function(self) M:ShowFloor(self.floor) end,
					L["Floor"], L["Shows this floor. Your pick is remembered for this dungeon."])
				frame.floorButtons[index] = button
			end
			button.floor = index
			button:SetText(entry.name or (L["Floor %d"]):format(index))
			Kit.FitButton(button, 60)
			local text = button:GetFontString()
			if text then
				if index == floor then text:SetTextColor(E:TokenColor("accent")) else text:SetTextColor(1, 1, 1) end
			end
			button:ClearAllPoints()
			button:SetPoint("LEFT", anchor, "RIGHT", anchor == frame.title and 12 or 4, 0)
			anchor = button
			button:Show()
		elseif button then
			button:Hide()
		end
	end
end

local function UpdateSide(frame)
	local key = state.key
	local route = key and M:ActiveRoute(key)
	frame.routeButton:SetText(route and route.name or L["No route"])
	Kit.FitButton(frame.routeButton, 120)
	frame.sideTitle:SetText(route and route.name or L["No route"])
	if route then
		local mobs = 0
		for _, pull in ipairs(route.pulls) do mobs = mobs + M:PullInfo(key, pull).count end
		frame.sideInfo:SetText((L["%d pulls, %d mobs"]):format(#route.pulls, mobs) .. (route.shipped and ("  ·  " .. L["suggested"]) or ""))
	else
		frame.sideInfo:SetText("")
	end
	-- Another route may have fewer pulls than the one a pull was picked on.
	if state.selected and not (route and route.pulls[state.selected]) then
		state.selected = nil
		frame.canvas.routesSelected = nil
	end
	local items = {}
	for index, pull in ipairs(route and route.pulls or {}) do items[#items + 1] = { index = index, pull = pull } end
	frame.pulls:SetData(items)
	frame.renameButton:SetEnabled(route ~= nil and route.id ~= nil)
	frame.deleteButton:SetEnabled(route ~= nil and route.id ~= nil)
	frame.exportButton:SetEnabled(route ~= nil)
	frame.copyButton:SetEnabled(route ~= nil)
	if frame.sendButton then frame.sendButton:SetEnabled(route ~= nil and #route.pulls > 0) end
end

function M:ShowFloor(floor)
	if not (win and win.mapFrame) or not state.key then return end
	local frame = win.mapFrame
	local mapKey = self:MapKey(state.key)
	if not mapKey then
		frame.canvas.routesKey = nil
		frame.canvas:Hide()
		frame.noMap:Show()
		frame.hint:SetText(L["This dungeon has no map in EldoUI's list."])
		UpdateFloorButtons(frame, {}, 1)
		return
	end
	frame.noMap:Hide()
	frame.canvas:Show()
	local floors = DM:Floors(mapKey)
	floor = floors[floor or 0] and floor or DM:CurrentFloor(mapKey) or 1
	state.floor = floor
	DM:SetLastFloor(mapKey, floor)
	frame.canvas.routesKey = state.key
	frame.canvas.routesSelected = state.selected
	local view = ViewFor(mapKey, floor)
	local ctx = frame.canvas:SetMap(mapKey, floor, view)
	UpdateFloorButtons(frame, floors, floor)
	local layout = DM:Bounds(mapKey, floor, "layout")
	frame.viewButton:SetShown(layout ~= nil and DM:HasArt(mapKey))
	frame.viewButton:SetText(ctx and ctx.view == "layout" and L["Map art"] or L["Schematic"])
	Kit.FitButton(frame.viewButton, 80)
	frame.hint:SetText(Hint(ctx))
end

function M:RefreshHint()
	if win and win.mapFrame then win.mapFrame.hint:SetText(Hint(win.mapFrame.canvas.ctx)) end
end

function M:ShowDungeon(key)
	if not (win and win.mapFrame) then return end
	local frame = win.mapFrame
	if key and not self:DungeonInfo(key) then key = nil end
	key = key or state.key or (self.db.trackZone and self:CurrentDungeon()) or (self:Dungeons()[1] and self:Dungeons()[1].key)
	if not key then return end
	if key ~= state.key then
		state.selected = nil
		state.floor = nil
		if self.StopEditing then self:StopEditing() end
	end
	state.key = key
	self:RememberWing(key)
	frame.title:SetText(self:DungeonName(key))
	local mapKey = self:MapKey(key)
	if mapKey then DM:LearnFloorMap(mapKey) end
	DungeonRows(frame)
	for index, item in ipairs(frame.list.data) do
		if item.key == key then frame.list:ScrollTo(index) end
	end
	UpdateSide(frame)
	self:ShowFloor(state.floor)
end

-- Picks a pull in the list and on the map; the same pull again clears it
-- (unless `keep`).
function M:SelectPull(index, keep)
	if state.selected == index and not keep then index = nil end
	state.selected = index
	if win and win.mapFrame then
		local frame = win.mapFrame
		frame.canvas.routesSelected = index
		frame.pulls:Refresh()
		if frame.canvas:IsShown() and frame.canvas.ctx then frame.canvas:RefreshPins() end
	end
end

-- A click on a pack marker in the window: select the pull that has it.
function M:OnPackClick(pin, button)
	if self.IsEditing and self:IsEditing() then
		self:EditorPackClick(pin, button)
		return
	end
	if button ~= "LeftButton" or not (pin and pin.pull) then return end
	if win and win.mapFrame and win.mapFrame.canvas.routesKey == pin.routeKey then
		self:SelectPull(pin.pull)
		win.mapFrame.pulls:ScrollTo(pin.pull)
	end
end

local function CreateMapTab(content)
	local frame = CreateFrame("Frame", nil, content)
	frame:SetAllPoints()

	-- Dungeon list.
	frame.list = Kit.CreateList(frame, {
		rowHeight = 20,
		create = function(row)
			row:RegisterForClicks("LeftButtonUp")
			E:SkinRow(row)
			row.sel = row:CreateTexture(nil, "BACKGROUND", nil, -5)
			row.sel:SetAllPoints()
			row.name = Kit.Text(row, 12, "LEFT")
			row.name:SetPoint("LEFT", 6, 0)
			row.name:SetPoint("RIGHT", -44, 0)
			row.name:SetWordWrap(false)
			row.levels = Kit.Text(row, 10, "RIGHT", "secondary")
			row.levels:SetPoint("RIGHT", -4, 0)
			row:SetScript("OnClick", function(self) if self.item then M:ShowDungeon(self.item.key) end end)
		end,
		update = function(row, item)
			row.name:SetText(item.here and (Kit.AccentHex() .. "> |r" .. item.name) or item.name)
			row.levels:SetText(item.min and item.max and ("%d-%d"):format(item.min, item.max) or "")
			local r, g, b = Kit.Accent()
			row.sel:SetColorTexture(r, g, b, 0.25)
			row.sel:SetShown(item.key == state.key)
			Kit.Tooltip(row, item.name, item.here and L["You are in this dungeon."] or nil, not item.here and { { L["Click"], L["show its map, packs and routes"] } } or nil)
		end,
	})
	frame.list:SetPoint("TOPLEFT", 0, 0)
	frame.list:SetPoint("BOTTOMLEFT", 0, 0)
	frame.list:SetWidth(LIST_W)

	-- Top bar: title, floors, view, route picker.
	local bar = CreateFrame("Frame", nil, frame)
	bar:SetPoint("TOPLEFT", frame.list, "TOPRIGHT", 8, 0)
	bar:SetPoint("TOPRIGHT", 0, 0)
	bar:SetHeight(BAR_H)
	frame.bar = bar
	frame.title = Kit.Text(bar, 14, "LEFT", "header")
	frame.title:SetPoint("LEFT", 4, 0)
	frame.floorButtons = {}
	frame.routeButton = Kit.Button(bar, L["Route"], 140, 20, function(self) M:RouteMenu(self) end,
		L["Route"], L["Pick the route to show: the suggested one or one of yours. Also copy, rename, delete or import routes."])
	frame.routeButton:SetPoint("RIGHT", -2, 0)
	frame.viewButton = Kit.Button(bar, L["Schematic"], 90, 20, function()
		local mapKey = M:MapKey(state.key)
		local current = win.mapFrame.canvas.ctx and win.mapFrame.canvas.ctx.view
		state.view = current == "layout" and "art" or "layout"
		if mapKey then M:ShowFloor(state.floor) end
	end, L["View"], L["Switch between the game's dungeon map and the schematic, where packs are placed by where they stand (approximate)."])
	frame.viewButton:SetPoint("RIGHT", frame.routeButton, "LEFT", -6, 0)

	-- Side: the picked route's pulls.
	local side = CreateFrame("Frame", nil, frame)
	side:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -6)
	side:SetPoint("BOTTOMRIGHT", 0, 0)
	side:SetWidth(SIDE_W)
	E:SetTemplate(side, true)
	frame.side = side
	frame.sideTitle = Kit.Text(side, 13, "LEFT", "header")
	frame.sideTitle:SetPoint("TOPLEFT", 8, -8)
	frame.sideTitle:SetPoint("TOPRIGHT", -8, -8)
	frame.sideTitle:SetWordWrap(false)
	frame.sideInfo = Kit.Text(side, 11, "LEFT", "secondary")
	frame.sideInfo:SetPoint("TOPLEFT", frame.sideTitle, "BOTTOMLEFT", 0, -4)
	frame.sideInfo:SetPoint("TOPRIGHT", frame.sideTitle, "BOTTOMRIGHT", 0, -4)
	local buttons = CreateFrame("Frame", nil, side)
	buttons:SetPoint("BOTTOMLEFT", 6, 6)
	buttons:SetPoint("BOTTOMRIGHT", -6, 6)
	buttons:SetHeight(70)
	local function SideButton(text, tip, onClick)
		return Kit.Button(buttons, text, (SIDE_W - 18) / 2, 20, onClick, text, tip)
	end
	frame.copyButton = SideButton(L["Copy"], L["Keep this route as one of yours, to name it, label and color its pulls, and share it."],
		function() M:CopyRoute(M:ActiveRoute(state.key)) end)
	frame.copyButton:SetPoint("TOPLEFT")
	frame.exportButton = SideButton(L["Export"], L["A !EUR1! string of this route to copy and paste to others."], function()
		local route = M:ActiveRoute(state.key)
		if route then M:Export(route.id or ("shipped:" .. route.key)) end
	end)
	frame.exportButton:SetPoint("TOPRIGHT")
	frame.sendButton = SideButton(L["Send to group"], L["Send this route to your party or raid with one click. Only players who turned on \"Get routes your group sends\" see it, in their From your group list."], function()
		local route = M:ActiveRoute(state.key)
		if route then M:SendFromWindow(route) end
	end)
	frame.sendButton:SetPoint("LEFT", buttons, "LEFT", 0, 0)
	frame.newButton = SideButton(L["New route"], L["Start an empty route of yours for this dungeon and open the editor."], function()
		if M:NewRoute(state.key) and M.StartEditing then M:StartEditing() end
	end)
	frame.newButton:SetPoint("RIGHT", buttons, "RIGHT", 0, 0)
	frame.renameButton = SideButton(L["Rename"], L["Give your route another name."], function() M:AskRename(M:ActiveRoute(state.key)) end)
	frame.renameButton:SetPoint("BOTTOMLEFT")
	frame.deleteButton = SideButton(L["Delete"], L["Delete this route of yours (after a question)."], function() M:AskDelete(M:ActiveRoute(state.key)) end)
	frame.deleteButton:SetPoint("BOTTOMRIGHT")
	frame.pulls = Kit.CreateList(side, {
		rowHeight = 20,
		create = function(row)
			row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			E:SkinRow(row)
			row.sel = row:CreateTexture(nil, "BACKGROUND", nil, -5)
			row.sel:SetAllPoints()
			row.number = Kit.Text(row, 12, "RIGHT")
			row.number:SetPoint("LEFT", 2, 0)
			row.number:SetWidth(26)
			row.text = Kit.Text(row, 12, "LEFT")
			row.text:SetPoint("LEFT", row.number, "RIGHT", 6, 0)
			row.text:SetPoint("RIGHT", -4, 0)
			row.text:SetWordWrap(false)
			row:SetScript("OnClick", function(self, button)
				if not self.item then return end
				if button == "RightButton" then M:PullMenu(self, self.item.index) else M:SelectPull(self.item.index) end
			end)
			if M.HookPullRow then M:HookPullRow(row) end
		end,
		update = function(row, item)
			row.number:SetText(item.index)
			row.number:SetTextColor(M:ColorRGB(item.pull.c))
			local info = M:PullInfo(state.key, item.pull)
			local text = M:PullText(state.key, item.pull)
			local done = M.PullDone and M:PullDone(state.key, item.index)
			row:SetAlpha(done and E.tokens.disabledAlpha or 1)
			if not info.found then
				row.text:SetTextColor(Grey())
			-- Bosses in the danger color, elites as a warning (design tokens).
			elseif info.boss then
				row.text:SetTextColor(unpack(Kit.BAD))
			elseif info.elite then
				row.text:SetTextColor(unpack(Kit.WARN))
			else
				row.text:SetTextColor(unpack(Kit.TEXT))
			end
			row.text:SetText(text)
			local r, g, b = Kit.Accent()
			row.sel:SetColorTexture(r, g, b, 0.25)
			row.sel:SetShown(item.index == state.selected)
			Kit.Tooltip(row, (L["Pull %d"]):format(item.index), function(tooltip)
				for _, pack in ipairs(info.packs) do
					for _, member in ipairs(pack.members) do
						tooltip:AddLine(("%dx %s"):format(member.count, member.name or "?"), unpack(Kit.TEXT))
					end
				end
				if not info.found then tooltip:AddLine(L["Its packs are not in your dungeon data."], Grey()) end
				if done then tooltip:AddLine(L["Done on the route card."], Grey()) end
				E:TooltipHint(tooltip, { L["Click"], L["show it on the map"] }, { L["Right-click"], L["label, color, move or delete"] }, { L["Drag"], L["move it in your route"] })
			end)
		end,
	})
	frame.pulls:SetPoint("TOPLEFT", frame.sideInfo, "BOTTOMLEFT", -6, -8)
	frame.pulls:SetPoint("BOTTOMRIGHT", buttons, "TOPRIGHT", 0, 6)

	-- Map.
	frame.canvas = DM:CreateCanvas(frame)
	frame.canvas:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
	frame.canvas:SetPoint("BOTTOMRIGHT", side, "BOTTOMLEFT", -8, 18)
	frame.noMap = Kit.EmptyState(frame)
	frame.noMap:ClearAllPoints()
	frame.noMap:SetAllPoints(frame.canvas)
	frame.noMap:Set(L["No map for this dungeon"], L["EldoUI has no map for this place yet. The pulls of its route are listed on the right."], nil)
	frame.noMap:Hide()
	frame.hint = Kit.Text(frame, 11, "LEFT", "secondary")
	frame.hint:SetPoint("BOTTOMLEFT", frame.canvas, "BOTTOMLEFT", 2, -16)
	frame.hint:SetPoint("BOTTOMRIGHT", frame.canvas, "BOTTOMRIGHT", 0, -16)
	frame.hint:SetWordWrap(false)
	win.mapFrame = frame
	if M.BuildEditor then M:BuildEditor(frame) end
	return frame
end

local function ShowMapTab(_, key)
	M:Data()
	if key then state.key = nil end
	M:ShowDungeon(key)
end

local function RefreshMapTab(_, changed)
	if not (win and win.mapFrame) then return end
	if changed == "data" then
		M:ShowDungeon(state.key)
		return
	end
	UpdateSide(win.mapFrame)
	DungeonRows(win.mapFrame)
	if win.mapFrame.canvas:IsShown() and win.mapFrame.canvas.ctx then win.mapFrame.canvas:RefreshPins() end
end

local function NoData()
	if M:Data() and #M:Dungeons() > 0 then return nil end
	local title, text = M:DataProblem()
	if not title then return L["No dungeons in the data"], L["Your EldoUI_LootData lists no dungeon packs."] end
	return title, text
end

---------------------------------------------------------------------------
-- My routes tab
---------------------------------------------------------------------------
local function CreateRoutesTab(content)
	local frame = CreateFrame("Frame", nil, content)
	frame:SetAllPoints()
	frame.importButton = Kit.Button(frame, L["Import a route"], 140, 22, function() M:ShowImport() end,
		L["Import a route"], L["Paste a route string someone shared (!EUR1!). You see what it holds before it is added."])
	frame.importButton:SetPoint("TOPRIGHT", 0, 0)
	frame.help = Kit.Text(frame, 11, "LEFT", "secondary")
	frame.help:SetPoint("TOPLEFT", 2, -4)
	frame.help:SetPoint("TOPRIGHT", frame.importButton, "TOPLEFT", -12, -4)
	frame.help:SetText(L["Click a route to open it on the map. Right-click for rename, export and delete."])
	frame.table = Kit.CreateTable(frame, {
		{ key = "dungeon", title = L["Dungeon"], width = 220, value = function(item) return M:DungeonName(item.key) end },
		{ key = "name", title = L["Route"], value = function(item) return tostring(item.name or "") end },
		{ key = "pulls", title = L["Pulls"], width = 70, align = "RIGHT", value = function(item) return #item.pulls end },
		{ key = "created", title = L["Made"], width = 110, align = "RIGHT", value = function(item) return item.created or 0 end,
			text = function(item) return (item.created and item.created > 0) and E:ShortDay(item.created) or "" end },
	}, {
		sortKey = "dungeon",
		empty = { L["No routes of your own yet"], L["Copy a suggested route on the Map tab, or import a route string someone shared."] },
		onClick = function(item, button, row)
			if button == "RightButton" then
				E.UIKit.ContextMenu(row, function(_, root)
					root:CreateTitle(item.name or "?")
					root:CreateButton(L["Open on the map"], function() M:OpenRoute(item) end)
					root:CreateButton(L["Rename"], function() M:AskRename(item) end)
					root:CreateButton(L["Export"], function() M:Export(item.id) end)
					root:CreateButton(L["Delete"], function() M:AskDelete(item) end)
				end)
			else
				M:OpenRoute(item)
			end
		end,
	})
	frame.table:SetPoint("TOPLEFT", 0, -30)
	frame.table:SetPoint("BOTTOMRIGHT")
	win.routesFrame = frame
	return frame
end

local function RefreshRoutesTab(frame)
	frame.table:SetData(M:AllUserRoutes())
end

function M:OpenRoute(route)
	if not (route and route.key) then return end
	self:SetActiveRoute(route.key, route)
	self:OpenBrowser(route.key)
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function HelpText(tooltip)
	local r, g, b = Grey()
	tooltip:AddLine(L["Every Classic dungeon with its packs (count on the marker, gold ring: elite), patrol paths, bosses (red, in kill order) and a route of numbered pulls."], r, g, b, true)
	tooltip:AddLine(" ")
	tooltip:AddLine(L["The suggested route clears the dungeon from boss to boss. Copy it to keep your own: name it, label and color pulls, and share it as a string. Planning only: nothing is pulled, targeted or marked for you."], r, g, b, true)
	tooltip:AddLine(" ")
	tooltip:AddLine(L["Edit opens the editor: click packs to add or take out pulls, drag pulls in the list, write notes and draw arrows or lines on the map. Send to group shares a route with your party with one click."], r, g, b, true)
end

function M:BuildBrowser()
	if win then return win end
	win = Kit.CreateTabbedWindow({
		name = "EldoUI_DungeonRoutesFrame",
		options = { page = "module:DungeonRoutes" },
		title = L["Dungeons"],
		width = WIDTH, height = HEIGHT,
		store = function()
			if type(M.db.window) ~= "table" then M.db.window = {} end
			return M.db.window
		end,
		-- Nothing in it is blocked in combat: it stays open through a pull.
		hideInCombat = false,
		tabs = {
			{ key = "map", title = L["Map"], desc = L["The dungeon list, the map with packs and the picked route."],
				create = CreateMapTab, show = ShowMapTab, refresh = RefreshMapTab, empty = NoData },
			{ key = "routes", title = L["My routes"], desc = L["Your own routes of every dungeon: open, rename, export and delete them."],
				create = CreateRoutesTab, show = RefreshRoutesTab, refresh = RefreshRoutesTab,
				count = function() return M:UserRouteCount() end },
			M.GroupTab and M:GroupTab() or nil,
		},
		help = { text = HelpText },
		footer = function() return L["Packs, patrols and bosses from the Classic data (EldoUI_LootData). Planning only."] end,
		transparent = function() return M.db.transparent end,
	})
	return win
end

function M:Browser()
	return win
end

function M:BrowserState()
	return state
end

function M:OpenBrowser(key)
	if not self.active then return false end
	-- The window stays open through combat, but the data loads only out of
	-- combat: asked for before it is loaded, it opens when combat ends.
	if InCombatLockdown() and not self:Data(true) then
		self.openAfterCombat = key or true
		self.loadAfterCombat = true
		E:Print(L["%s opens when combat ends."]:format(L["Dungeons"]))
		return false
	end
	self.openAfterCombat = nil
	self:Data()
	self:BuildBrowser()
	if key then state.key = nil end
	if not key and self.db.trackZone then key = self:CurrentDungeon() end
	local opened = win:Open("map", key)
	return opened
end

function M:CloseBrowser()
	if win then win:Close() end
end

function M:ToggleBrowser()
	if win and win:IsOpen() then self:CloseBrowser() else self:OpenBrowser() end
end

function M:RefreshBrowser(changed)
	if win and win:IsOpen() then win:Refresh(changed) end
end

function M:RestyleBrowser()
	if win then
		win:Restyle()
		self:RefreshBrowser()
	end
end

-- Zoning while the window is open: follow into the next dungeon.
function M:OnZoneChanged()
	if not (win and win:IsOpen() and self.db.trackZone and win:Current() == "map") then return end
	local key = self:CurrentDungeon()
	if key and key ~= state.key then self:ShowDungeon(key) end
end
