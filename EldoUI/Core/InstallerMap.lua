local _, E = ...
local Installer = E.Installer

---------------------------------------------------------------------------
-- Layout map: a small picture of a preset on its card. The main frames are
-- drawn as boxes where the preset puts them, on a screen of the player's
-- shape; sizes are the frames' own (bars from the preset's bar shapes).
---------------------------------------------------------------------------
local MAP_PARTS = {
	{ name = "EldoUI_InfoBar", kind = "strip", w = 2560, h = 22 },
	{ name = "EldoUI_Minimap", kind = "map", w = 200, h = 200 },
	{ name = "EldoUI_Buffs", kind = "strip", w = 360, h = 36 },
	{ name = "EldoUI_Quests", kind = "panel", w = 260, h = 340 },
	{ name = "EldoUI_Chat", kind = "panel", w = 440, h = 190 },
	{ name = "EldoUI_Details", kind = "panel", w = 300, h = 170 },
	{ name = "EldoUI_Party", kind = "group", w = 150, h = 230 },
	{ name = "EldoUI_ActionBar1", kind = "bar", bar = 1 },
	{ name = "EldoUI_ActionBar2", kind = "bar", bar = 2 },
	{ name = "EldoUI_ActionBar3", kind = "bar", bar = 3 },
	{ name = "EldoUI_ActionBar4", kind = "bar", bar = 4 },
	{ name = "EldoUI_ActionBar5", kind = "bar", bar = 5 },
	{ name = "EldoUI_PlayerCastbar", kind = "hud", w = 240, h = 18 },
	{ name = "EldoUI_Player", kind = "hud", w = 240, h = 48 },
	{ name = "EldoUI_Target", kind = "hud", w = 240, h = 48 },
}
local MAP_ALPHA = { strip = 0.16, map = 0.3, panel = 0.1, group = 0.22, bar = 0.32, hud = 0.75 }

-- The footprints of the styles a map is drawn with ({ Module = style key }),
-- merged: movers[name] = { width, height }, bars[index] = { size, spacing }.
local function MapFootprint(styles)
	local fp = { movers = {}, bars = {} }
	for moduleName, styleKey in pairs(styles or {}) do
		local own = E:StyleFootprint(moduleName, styleKey)
		for name, size in pairs(own and own.movers or {}) do fp.movers[name] = size end
		for index, bar in pairs(own and own.bars or {}) do fp.bars[index] = bar end
	end
	return fp
end

-- Size of an action bar in a preset: the picked style's button size, then
-- the preset's bar shape, on top of the player's current one.
local function MapBarSize(layout, index, fp)
	local bars = E.modules.ActionBars and E.modules.ActionBars.db and E.modules.ActionBars.db.bars
	local own = bars and bars[index] or {}
	local preset = layout.modules and layout.modules.ActionBars and layout.modules.ActionBars.bars
	preset = preset and preset[index] or {}
	local styled = fp and fp.bars[index] or {}
	local function Get(key, default)
		local value = styled[key]
		if value == nil then value = preset[key] end
		if value == nil then value = own[key] end
		return tonumber(value) or default
	end
	local enabled = preset.enabled
	if enabled == nil then enabled = own.enabled end
	if enabled == false then return nil end
	local buttons = math.max(1, Get("buttons", 12))
	local perRow = math.max(1, math.min(buttons, Get("perRow", 12)))
	local size, spacing = Get("size", 40), Get("spacing", 4)
	local rows = math.ceil(buttons / perRow)
	return perRow * size + (perRow - 1) * spacing, rows * size + (rows - 1) * spacing
end

local function MapSize(layout, part, fp)
	if part.bar then return MapBarSize(layout, part.bar, fp) end
	local mover = E.movers and E.movers[part.name]
	local w, h = mover and mover:GetWidth() or 0, mover and mover:GetHeight() or 0
	if not (w and w > 2 and h and h > 2) then w, h = part.w, part.h end
	local styled = fp and fp.movers[part.name]
	if styled then w, h = styled.width or w, styled.height or h end
	return w, h
end

-- Rectangles { left, bottom, right, top } of the map parts in a preset, on
-- a screen `width` x `height` (UIParent units), with the frame sizes of
-- `styles` ({ Module = style key }, optional). Points chained to another
-- mover follow it; a chain that can't be followed falls back to the center.
function Installer.LayoutMap(key, width, height, styles)
	local layout = E.layouts[key]
	if not layout then return {} end
	-- Points follow the screen height while layout fit is on (Core/Layout.lua).
	local ratio = E:GetLayoutRatio(layout, height)
	local screen = { 0, 0, width, height }
	local hidden = {}
	for _, name in ipairs(layout.hidden or {}) do hidden[name] = true end
	local sizes = {}
	local fp = MapFootprint(styles)
	for _, part in ipairs(MAP_PARTS) do
		local w, h = MapSize(layout, part, fp)
		if w and not hidden[part.name] then sizes[part.name] = { w, h } end
	end
	local Resolve, rects = E:LayoutRectangles(function(name)
		local point = layout.points and layout.points[name]
		local size = sizes[name]
		if not point then return end
		size = size or { 1, 1 }
		local target = type(point[2]) == "string" and point[2]:match("^(EldoUI_.+)Mover$")
		local scaled = { point[1], point[2], point[3], tonumber(point[4]) or 0, tonumber(point[5]) or 0 }
		return scaled, size[1], size[2], target, screen, ratio
	end, { depth = 6, fallback = screen })
	local function Rect(name)
		local rect = Resolve(name)
		if rect then rects[name] = rect end
		return rect
	end
	local list = {}
	for _, part in ipairs(MAP_PARTS) do
		if sizes[part.name] then
			local rect = Rect(part.name)
			if rect then list[#list + 1] = { part = part, rect = rect } end
		end
	end
	-- Parts a module draws itself (the second info bar docks in the chat
	-- box): module:LayoutMapParts(map) returns { part = { name, kind },
	-- rect } entries. map.Rect(name) is a drawn part's rectangle;
	-- map.Place(name, w, h) puts a frame of that size on the layout's point.
	local map = { layout = layout, width = width, height = height, styles = styles or {}, hidden = hidden,
		Rect = function(name) return rects[name] end,
		Place = function(name, w, h)
			if hidden[name] then return nil end
			sizes[name] = { w, h }
			return Rect(name)
		end }
	for _, module in E:IterateModules() do
		if type(module.LayoutMapParts) == "function" then
			local ok, parts = pcall(module.LayoutMapParts, module, map)
			if not ok then
				geterrorhandler()(parts)
			elseif type(parts) == "table" then
				for _, entry in ipairs(parts) do
					if type(entry.part) == "table" and type(entry.rect) == "table" then list[#list + 1] = entry end
				end
			end
		end
	end
	return list
end

-- Draw the map of preset `key` into `frame` (a box of the screen's shape),
-- its frames as large as `styles` makes them.
function Installer.DrawLayoutMap(frame, key, accent, styles)
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	if not (width and width > 0 and height and height > 0) then return end
	local scaleX, scaleY = frame:GetWidth() / width, frame:GetHeight() / height
	frame.boxes = frame.boxes or {}
	for _, box in ipairs(frame.boxes) do box:Hide() end
	local c = E.media.accentColor
	local r, g, b = c[1], c[2], c[3]
	if accent then r, g, b = accent[1], accent[2], accent[3] end
	for index, entry in ipairs(Installer.LayoutMap(key, width, height, styles)) do
		local box = frame.boxes[index]
		if not box then
			box = frame:CreateTexture(nil, "ARTWORK")
			frame.boxes[index] = box
		end
		local rect = entry.rect
		local left = math.max(0, math.min(rect[1], width)) * scaleX
		local right = math.max(0, math.min(rect[3], width)) * scaleX
		local bottom = math.max(0, math.min(rect[2], height)) * scaleY
		local top = math.max(0, math.min(rect[4], height)) * scaleY
		if right - left >= 1 and top - bottom >= 1 then
			box:ClearAllPoints()
			box:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", left, bottom)
			box:SetSize(math.max(1, right - left), math.max(1, top - bottom))
			local alpha = MAP_ALPHA[entry.part.kind] or 0.2
			if entry.part.kind == "hud" then
				box:SetColorTexture(r, g, b, alpha)
			else
				box:SetColorTexture(1, 1, 1, alpha)
			end
			box:Show()
		end
	end
end
