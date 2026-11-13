-- EldoUI Dungeon Routes: the route editor in the Dungeons window.
--
--   [Edit] in the window's top bar turns it on for the route shown (a
--   suggested route is copied as yours first). A tool strip lies over the
--   top of the map:
--
--   | Pulls  Note  Arrow  Draw  Erase | Color v | Undo  Clear floor | Done |
--
--   Pulls   click a pack: it becomes the next pull, or comes out of the
--           route when it is in it; Shift-click: it joins the pull picked
--           in the list
--   Note    click the map: a note with your text there; click a note to
--           change its text (an empty text deletes it)
--   Arrow   press, drag and let go: an arrow from where you pressed
--   Draw    press and drag: a free-hand line
--   Erase   click a note, arrow or line to delete it
-- Every change has an undo step. In the pull list a pull can be dragged to
-- another place; its right-click menu also moves, joins and deletes pulls.
-- Notes, arrows and lines are kept in world yards per floor, so they stay
-- in place in the map art and the schematic view and travel in the share
-- string.
--
-- Combat closes the editor (the map stays, read-only). Nothing here touches
-- the game: it only changes your saved route.
local _, E = ...
local L = E.L
local M = E.DungeonRoutes
local Kit = E.UIKit

local STRIP_H = 28
local DRAG_STEP = 4          -- pixels between two points of a free-hand line
local ERASE_PX = 12          -- the eraser's reach on screen
local MIN_ARROW_PX = 8

local editor = { on = false, tool = "pulls", color = "accent" }
M.editor = editor

M.TOOLS = {
	{ key = "pulls", label = L["Pulls"], desc = L["Click a pack: it becomes the next pull, or comes out of the route when it is in it. Shift-click: it joins the pull picked in the list."] },
	{ key = "note", label = L["Note"], desc = L["Click the map to write a note there. Click a note to change its text; an empty text deletes it."] },
	{ key = "arrow", label = L["Arrow"], desc = L["Press, drag and let go: an arrow from where you pressed to where you let go."] },
	{ key = "draw", label = L["Draw"], desc = L["Press and drag to draw a free-hand line."] },
	{ key = "erase", label = L["Erase"], desc = L["Click a note, arrow or line to delete it."] },
}
local toolByKey = {}
for _, tool in ipairs(M.TOOLS) do toolByKey[tool.key] = tool end

local function MapFrame()
	local win = M:Browser()
	return win and win.mapFrame
end

-- The route being edited: the window's route when it is one of yours.
function M:EditedRoute()
	local state = self:BrowserState()
	local route = state and state.key and self:ActiveRoute(state.key)
	return route and route.id and route or nil
end

function M:IsEditing()
	return editor.on and self:EditedRoute() ~= nil
end

---------------------------------------------------------------------------
-- Map positions: cursor -> map fraction -> world yards
---------------------------------------------------------------------------
local function CursorFraction(canvas)
	local area = canvas and canvas.area
	if not area then return nil end
	local left, top = area:GetLeft(), area:GetTop()
	local width, height = area:GetWidth() or 0, area:GetHeight() or 0
	if not (left and top) or width <= 0 or height <= 0 then return nil end
	local x, y = GetCursorPosition()
	local scale = area:GetEffectiveScale() or 1
	return (x / scale - left) / width, (top - y / scale) / height
end
M.CursorFraction = CursorFraction

local function ToWorld(ctx, fx, fy)
	local b = ctx and ctx.bounds
	if not (b and fx and fy) then return nil end
	return b.top - fy * (b.top - b.bottom), b.left - fx * (b.left - b.right)
end

-- Yards per pixel of the map area (for the eraser's reach).
local function YardsPerPixel(canvas)
	local b = canvas.ctx and canvas.ctx.bounds
	local height = canvas.area:GetHeight() or 0
	if not b or height <= 0 then return 1 end
	return math.abs(b.top - b.bottom) / height
end

local function Inside(fx, fy)
	return fx and fy and fx >= 0 and fx <= 1 and fy >= 0 and fy <= 1
end

---------------------------------------------------------------------------
-- Input (the strip's tools on the map); testable without a mouse:
-- M:EditorInput("down" | "move" | "up", fx, fy[, shift])
---------------------------------------------------------------------------
local function Toast(text, warn)
	local win = M:Browser()
	if win and win.frame and Kit.Toast then Kit.Toast(win.frame, text, { warn = warn }) end
end
M.EditorToast = Toast

function M:EditorInput(phase, fx, fy)
	local frame = MapFrame()
	local route = self:EditedRoute()
	if not (editor.on and frame and route) then return false end
	local canvas = frame.canvas
	local ctx = canvas.ctx
	if not (ctx and ctx.bounds) then return false end
	local tool = editor.tool
	local floor = ctx.floor or 1
	if phase == "down" then
		if not Inside(fx, fy) then return false end
		if tool == "arrow" or tool == "draw" then
			canvas.routesDraft = { kind = tool, color = editor.color, points = { fx, fy } }
			canvas:RefreshPins()
		end
		editor.down = { fx, fy }
		return true
	elseif phase == "move" then
		local draft = canvas.routesDraft
		if not draft or not (fx and fy) then return false end
		fx, fy = math.max(0, math.min(1, fx)), math.max(0, math.min(1, fy))
		local p = draft.points
		local width, height = canvas.area:GetWidth() or 1, canvas.area:GetHeight() or 1
		if draft.kind == "arrow" then
			p[3], p[4] = fx, fy
		else
			local dx, dy = (fx - p[#p - 1]) * width, (fy - p[#p]) * height
			if dx * dx + dy * dy < DRAG_STEP * DRAG_STEP then return false end
			p[#p + 1], p[#p + 2] = fx, fy
		end
		canvas:RefreshPins()
		return true
	elseif phase ~= "up" then
		return false
	end
	-- Let go: finish what was started.
	local down = editor.down
	editor.down = nil
	local draft = canvas.routesDraft
	canvas.routesDraft = nil
	if tool == "arrow" and draft then
		local p = draft.points
		if fx and fy then p[3], p[4] = math.max(0, math.min(1, fx)), math.max(0, math.min(1, fy)) end
		local width, height = canvas.area:GetWidth() or 1, canvas.area:GetHeight() or 1
		if not p[3] or ((p[3] - p[1]) * width) ^ 2 + ((p[4] - p[2]) * height) ^ 2 < MIN_ARROW_PX * MIN_ARROW_PX then
			canvas:RefreshPins()
			return false
		end
		local x1, y1 = ToWorld(ctx, p[1], p[2])
		local x2, y2 = ToWorld(ctx, p[3], p[4])
		local ok = self:AddArrow(route.id, floor, x1, y1, x2, y2, editor.color)
		if not ok then Toast((L["A route keeps at most %d arrows."]):format(self.MAX_ARROWS), true) end
		canvas:RefreshPins()
		return ok
	elseif tool == "draw" and draft then
		local p = draft.points
		if fx and fy and Inside(fx, fy) then p[#p + 1], p[#p + 2] = fx, fy end
		local world = {}
		for i = 1, #p - 1, 2 do
			local x, y = ToWorld(ctx, p[i], p[i + 1])
			world[#world + 1], world[#world + 2] = x, y
		end
		local ok = #world >= 4 and self:AddStroke(route.id, floor, world, editor.color)
		if #world >= 4 and not ok then Toast((L["A route keeps at most %d lines."]):format(self.MAX_STROKES), true) end
		canvas:RefreshPins()
		return ok and true or false
	elseif tool == "note" and down then
		local x, y = ToWorld(ctx, down[1], down[2])
		local radius = ERASE_PX * YardsPerPixel(canvas)
		local field, index = self:DrawingNear(route, floor, x, y, radius)
		if field == "n" then
			local note = route.n[index]
			self:AskText(L["Text of the note (empty: delete it):"], note.t, function(text) M:SetNoteText(route.id, index, text) end)
		else
			if #(route.n or {}) >= self.MAX_NOTES then
				Toast((L["A route keeps at most %d notes."]):format(self.MAX_NOTES), true)
				return false
			end
			local color = editor.color
			self:AskText(L["Text of the note:"], "", function(text) M:AddNote(route.id, floor, x, y, text, color) end)
		end
		return true
	elseif tool == "erase" and down then
		local x, y = ToWorld(ctx, down[1], down[2])
		return self:EraseNear(route.id, floor, x, y, ERASE_PX * YardsPerPixel(canvas)) and true or false
	end
	return false
end

-- A click on a pack marker while the Pulls tool is on.
function M:EditorPackClick(pin, button)
	local route = self:EditedRoute()
	if not (editor.on and editor.tool == "pulls" and route and pin and pin.pack) or button ~= "LeftButton" then return false end
	local state = self:BrowserState()
	local into = IsShiftKeyDown() and state.selected or nil
	local action = self:TogglePack(route.id, pin.pack.id, into)
	if action == "added" then
		self:SelectPull(nil)
	elseif not action then
		Toast(L["That pull is full, or the route has as many pulls as it can keep."], true)
	end
	return action
end

---------------------------------------------------------------------------
-- The tool strip
---------------------------------------------------------------------------
local function PaintStrip(frame)
	local strip = frame.editStrip
	if not strip then return end
	for key, button in pairs(strip.tools) do
		local text = button:GetFontString()
		if text then
			if key == editor.tool then text:SetTextColor(E:TokenColor("accent")) else text:SetTextColor(unpack(Kit.TEXT)) end
		end
	end
	local swatch = strip.swatch
	swatch:SetColorTexture(M:ColorRGB(editor.color))
	local route = M:EditedRoute()
	strip.undo:SetEnabled(route ~= nil and M:CanUndo(route.id))
	strip.clear:SetEnabled(route ~= nil and M:DrawingCount(route) > 0)
	local input = frame.editInput
	input:EnableMouse(editor.on and editor.tool ~= "pulls")
	input:SetShown(editor.on)
	frame.canvas.routesEditing = editor.on or nil
	local tool = toolByKey[editor.tool]
	if editor.on and tool and frame.hint then frame.hint:SetText(tool.desc) end
end

local function ColorMenu(owner)
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(L["Color of new notes, arrows and lines"])
		for _, color in ipairs(M.COLORS) do
			root:CreateButton(Kit.Hex(M:ColorRGB(color.key)) .. color.label .. "|r", function()
				editor.color = color.key
				local frame = MapFrame()
				if frame then PaintStrip(frame) end
			end)
		end
	end, { at = "owner" })
end

function M:BuildEditor(frame)
	if frame.editStrip then return end
	local strip = CreateFrame("Frame", nil, frame)
	strip:SetHeight(STRIP_H)
	strip:SetPoint("TOPLEFT", frame.canvas, "TOPLEFT", 0, 0)
	strip:SetPoint("TOPRIGHT", frame.canvas, "TOPRIGHT", 0, 0)
	strip:SetFrameLevel(frame.canvas:GetFrameLevel() + 60)
	E:SetTemplate(strip, true)
	strip:Hide()
	strip.tools = {}
	local anchor
	for _, tool in ipairs(M.TOOLS) do
		local button = Kit.Button(strip, tool.label, 60, 20, function()
			M:SetEditorTool(tool.key)
		end, tool.label, tool.desc)
		Kit.FitButton(button, 52)
		if anchor then button:SetPoint("LEFT", anchor, "RIGHT", 4, 0) else button:SetPoint("LEFT", 4, 0) end
		strip.tools[tool.key] = button
		anchor = button
	end
	strip.color = Kit.Button(strip, L["Color"], 70, 20, function(owner) ColorMenu(owner) end,
		L["Color"], L["The color of the next note, arrow or line you add."])
	strip.color:SetPoint("LEFT", anchor, "RIGHT", 12, 0)
	strip.swatch = strip.color:CreateTexture(nil, "OVERLAY")
	strip.swatch:SetSize(8, 8)
	strip.swatch:SetPoint("RIGHT", -6, 0)
	strip.done = Kit.Button(strip, L["Done"], 60, 20, function() M:StopEditing() end,
		L["Done"], L["Close the editor. Your route is saved as you go."])
	strip.done:SetPoint("RIGHT", -4, 0)
	strip.clear = Kit.Button(strip, L["Clear floor"], 90, 20, function()
		local route = M:EditedRoute()
		local ctx = frame.canvas.ctx
		if route and ctx then
			M:Confirm(L["Delete every note, arrow and line on this floor?"], function() M:ClearDrawings(route.id, ctx.floor or 1) end)
		end
	end, L["Clear floor"], L["Delete every note, arrow and line on the floor shown (after a question). Pulls stay."])
	Kit.FitButton(strip.clear, 80)
	strip.clear:SetPoint("RIGHT", strip.done, "LEFT", -12, 0)
	strip.undo = Kit.Button(strip, L["Undo"], 60, 20, function()
		local route = M:EditedRoute()
		if route then M:Undo(route.id) end
	end, L["Undo"], L["Take back the last change to this route."])
	strip.undo:SetPoint("RIGHT", strip.clear, "LEFT", -4, 0)
	frame.editStrip = strip

	-- Mouse input over the map for the drawing tools (the pins take the
	-- clicks of the Pulls tool, so this layer lets them through then).
	local input = frame.canvas:Layer("dungeonroutes-input", 45)
	input:EnableMouse(false)
	input:Hide()
	input:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" then return end
		M:EditorInput("down", CursorFraction(frame.canvas))
		input.tracking = true
	end)
	input:SetScript("OnMouseUp", function(_, button)
		if button ~= "LeftButton" then return end
		input.tracking = nil
		M:EditorInput("up", CursorFraction(frame.canvas))
	end)
	input:SetScript("OnUpdate", function()
		if input.tracking then M:EditorInput("move", CursorFraction(frame.canvas)) end
	end)
	frame.editInput = input

	frame.editButton = Kit.Button(frame.bar, L["Edit"], 60, 20, function()
		if editor.on then M:StopEditing() else M:StartEditing() end
	end, L["Edit"], L["Change this route on the map: add and take out pulls, write notes, draw arrows and lines. A suggested route is copied as yours first."])
	frame.editButton:SetPoint("RIGHT", frame.viewButton, "LEFT", -6, 0)
end

function M:SetEditorTool(key)
	if not toolByKey[key] then return false end
	editor.tool = key
	local frame = MapFrame()
	if frame and frame.canvas then
		frame.canvas.routesDraft = nil
		PaintStrip(frame)
	end
	return true
end

function M:SetEditorColor(key)
	if not self:IsColor(key) then return false end
	editor.color = key
	local frame = MapFrame()
	if frame then PaintStrip(frame) end
	return true
end

function M:StartEditing()
	local frame = MapFrame()
	local state = self:BrowserState()
	if not (frame and state.key) then return false end
	if InCombatLockdown() then
		Toast(L["The editor opens out of combat."], true)
		return false
	end
	local route = self:ActiveRoute(state.key)
	if route and not route.id then route = self:CopyRoute(route) end
	if not route then route = self:NewRoute(state.key) end
	if not route then
		Toast(L["You have too many routes; delete some first."], true)
		return false
	end
	editor.on = true
	frame.editStrip:Show()
	frame.editButton:SetText(L["Done"])
	PaintStrip(frame)
	return true
end

function M:StopEditing()
	local was = editor.on
	editor.on = false
	editor.down = nil
	local frame = MapFrame()
	if frame and frame.editStrip then
		frame.canvas.routesDraft = nil
		frame.canvas.routesEditing = nil
		frame.editStrip:Hide()
		frame.editInput.tracking = nil
		frame.editButton:SetText(L["Edit"])
		PaintStrip(frame)
		if frame.canvas.ctx then frame.canvas:RefreshPins() end
		if was and M.RefreshHint then M:RefreshHint() end
	end
	return was
end

-- Redraw the strip after a change (undo state, another route picked).
function M:RefreshEditor()
	local frame = MapFrame()
	if not (frame and frame.editStrip) then return end
	if editor.on and not self:EditedRoute() then
		self:StopEditing()
		return
	end
	PaintStrip(frame)
end

M:Hook("changed", function() M:RefreshEditor() end)
-- Combat closes the editor; the map stays, read-only.
M:Hook("combat", function()
	if M:StopEditing() then Toast(L["The editor closed for combat. Your route is saved."]) end
end)
M:Hook("disable", function() M:StopEditing() end)

---------------------------------------------------------------------------
-- Pull list: drag a pull to another place
---------------------------------------------------------------------------
-- The pull row under the cursor, or nil.
local function RowUnderCursor(list)
	for _, row in ipairs(list:ShownRows()) do
		if row:IsMouseOver() then return row end
	end
end

function M:HookPullRow(row)
	row:RegisterForDrag("LeftButton")
	row:SetScript("OnDragStart", function(dragged)
		local route = M:EditedRoute() or (M:BrowserState().key and M:ActiveRoute(M:BrowserState().key))
		if not (dragged.item and route and route.id) then return end
		M.dragPull = dragged.item.index
		dragged:SetAlpha(0.5)
	end)
	row:SetScript("OnDragStop", function(dragged)
		dragged:SetAlpha(1)
		local from = M.dragPull
		M.dragPull = nil
		if not from then return end
		local target = RowUnderCursor(dragged.list)
		if target and target.item then M:DropPull(from, target.item.index) end
	end)
end

-- Drag and drop in the pull list (also used by Move up / Move down).
function M:DropPull(from, to)
	local state = self:BrowserState()
	local route = state.key and self:ActiveRoute(state.key)
	if not (route and route.id) then return false end
	local ok = self:MovePull(route.id, from, to)
	if ok then self:SelectPull(math.max(1, math.min(#route.pulls, to))) end
	return ok
end
