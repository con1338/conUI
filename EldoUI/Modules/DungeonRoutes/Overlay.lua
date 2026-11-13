-- EldoUI Dungeon Routes: the map overlay.
--
-- One pin provider on E.DungeonMaps (Core/DungeonMaps.lua). It draws on any
-- dungeon canvas that names a dungeon:
--   canvas.routesKey  the Dungeons window (Browser.lua), and the dungeon
--                     view on the world map with "Packs and route" on
--   canvas.routesBossKey  the dungeon view on the world map with "Packs and
--                     route" off: the bosses only, as the game's skulls
--   canvas.lgKey      the Loot Guide's dungeon map, when "Packs on the Loot
--                     Guide's dungeon map" is on (its own boss markers stay,
--                     so ours are left out there)
-- What it draws, each part with its own setting:
--   pins   a marker per pack (mob count, gold ring for elites, dark ring for
--          packs the route skips) and a red, numbered marker per boss
--   lines  patrol paths, and the route line from pull to pull in each pull's
--          color, with a numbered tag on every pull
--   notes  the route's notes (a tag with the text), arrows and free-hand
--          lines on the floor shown ("Notes and drawings"), and the line
--          the editor is drawing right now (canvas.routesDraft)
-- The pull the route card points at (the next one) is lit when no pull is
-- picked in the window.
-- Positions are the packs' world yards turned into map positions with the
-- floor's edges (the canvas context's bounds). Nothing is read from the
-- game's units or the player's position; read-only in and out of combat.
local _, E = ...
local L = E.L
local M = E.DungeonRoutes
local Kit = E.UIKit

local PROVIDER = "dungeonroutes"
local ELITE = { 1, 0.78, 0.2 }
local BOSS = { 0.92, 0.25, 0.22 }
local PATROL = { 1, 0.85, 0.25 }

local function Neutral()
	local c = Kit and Kit.SECONDARY or E.media.borderColor
	return { c[1], c[2], c[3] }
end

-- The dungeon a canvas shows, or nil.
local function KeyFor(ctx)
	if not (M.active and ctx and ctx.kind == "dungeon" and ctx.bounds) then return nil end
	local canvas = ctx.canvas
	if not canvas then return nil end
	if canvas.routesBossKey then return canvas.routesBossKey, "bosses" end
	if canvas.routesKey then return canvas.routesKey, "browser" end
	if canvas.lgKey and M.db.lootGuideMap then
		local data = M:Data(true)
		if data and type(data.routePacks[canvas.lgKey]) == "table" then return canvas.lgKey, "lootguide" end
	end
end
M.OverlayKey = KeyFor

-- pack id -> pull index of the route (first pull that has it).
local function PullIndex(key, route)
	local index = {}
	for i, pull in ipairs(route and route.pulls or {}) do
		for _, id in ipairs(pull.p or {}) do
			if not index[id] then index[id] = i end
		end
	end
	return index
end

local function PackTooltip(tooltip, pin)
	local pack, key = pin.pack, pin.routeKey
	if not pack then return end
	if pack.boss then
		tooltip:AddLine(("%d. %s"):format(pack.boss, M:BossName(key, pack.boss)), BOSS[1], BOSS[2], BOSS[3])
	else
		Kit.TipTitle(tooltip, pack.count > 1 and (L["Pack of %d"]):format(pack.count) or L["Single mob"])
	end
	local grey = Kit.SECONDARY
	for _, member in ipairs(pack.members) do
		local tags = {}
		if member.rank == 1 or member.rank == 2 then tags[#tags + 1] = L["elite"] end
		if member.rank == 2 or member.rank == 4 then tags[#tags + 1] = L["rare"] end
		if member.rank == 3 then tags[#tags + 1] = L["boss"] end
		local text = ("%dx %s"):format(member.count, member.name or "?")
		if #tags > 0 then text = text .. " (" .. table.concat(tags, ", ") .. ")" end
		local right = member.level and (L["Level %d"]):format(member.level) or ""
		if member.rank == 1 or member.rank == 2 then
			tooltip:AddDoubleLine(text, right, ELITE[1], ELITE[2], ELITE[3], grey[1], grey[2], grey[3])
		else
			tooltip:AddDoubleLine(text, right, 1, 1, 1, grey[1], grey[2], grey[3])
		end
	end
	if pack.path then tooltip:AddLine(L["Patrols: the line shows its path."], PATROL[1], PATROL[2], PATROL[3], true) end
	if pin.pull then
		tooltip:AddLine((L["Pull %d of the route"]):format(pin.pull), grey[1], grey[2], grey[3])
	elseif pin.hasRoute then
		tooltip:AddLine(L["Not in the route"], grey[1], grey[2], grey[3])
	end
	tooltip:AddLine(L["Classic data; WoW: Forever may place mobs differently."], grey[1], grey[2], grey[3], true)
end

local provider = { order = 45, group = PROVIDER }

function provider.pins(_, ctx)
	local key, where = KeyFor(ctx)
	if not key then return nil end
	local db = M.db
	local route = M:ActiveRoute(key)
	local inRoute = PullIndex(key, route)
	local hasRoute = route ~= nil and db.showRoute
	local canvas = ctx.canvas
	local pick = canvas.routesSelected or (M.NextPullIndex and M:NextPullIndex(key))
	local selected = pick and route and route.pulls[pick]
	local lit = {}
	for _, id in ipairs(selected and selected.p or {}) do lit[id] = true end
	local scale = tonumber(db.markerScale) or 1
	local neutral = Neutral()
	local pins = {}
	if where == "bosses" then
		for _, pack in ipairs(M:Packs(key)) do
			if pack.boss then
				pins[#pins + 1] = { world = { pack.x, pack.y }, id = "rpack:" .. pack.id, pack = pack, routeKey = key,
					size = 26 * scale, atlas = "DungeonSkull", label = pack.boss, color = BOSS, tooltip = PackTooltip }
			end
		end
		return pins
	end
	for _, pack in ipairs(M:Packs(key)) do
		local boss = pack.boss and db.showBosses and where ~= "lootguide"
		if boss or (db.showPacks and not (pack.boss and where == "lootguide")) then
			local pin = { world = { pack.x, pack.y }, id = "rpack:" .. pack.id, pack = pack, routeKey = key,
				pull = inRoute[pack.id], hasRoute = hasRoute, highlight = lit[pack.id] or nil, tooltip = PackTooltip,
				onClick = function(data, button) if M.OnPackClick then M:OnPackClick(data, button) end end }
			if boss then
				pin.size = 24 * scale
				pin.label = pack.boss
				pin.color = BOSS
			else
				pin.size = (12 + math.min(pack.count, 6) * 1.5) * scale
				pin.label = (db.showCounts and pack.count > 1) and pack.count or nil
				pin.color = (db.showElite and pack.elite) and ELITE or neutral
				if db.dimOffRoute and hasRoute and not pin.pull then pin.ring = false end
			end
			pins[#pins + 1] = pin
		end
	end
	return pins
end

---------------------------------------------------------------------------
-- Lines and pull tags (pooled on the provider's layer)
---------------------------------------------------------------------------
local function Pool(layer, field)
	layer[field] = layer[field] or {}
	return layer[field]
end

local function Hide(layer)
	for _, line in ipairs(layer.routeLines or {}) do line:Hide() end
	for _, tag in ipairs(layer.routeTags or {}) do tag:Hide() end
	for _, note in ipairs(layer.routeNotes or {}) do note:Hide() end
	layer.lineCount, layer.tagCount, layer.noteCount = 0, 0, 0
end

local function Line(layer, x1, y1, x2, y2, width, r, g, b, a)
	local pool = Pool(layer, "routeLines")
	layer.lineCount = (layer.lineCount or 0) + 1
	local line = pool[layer.lineCount]
	if not line then
		line = layer:CreateLine(nil, "ARTWORK")
		pool[layer.lineCount] = line
	end
	line:SetThickness(width)
	line:SetColorTexture(r, g, b, a)
	line:SetStartPoint("TOPLEFT", layer, x1, -y1)
	line:SetEndPoint("TOPLEFT", layer, x2, -y2)
	line:Show()
	return line
end

local function Tag(layer, x, y, text, r, g, b)
	local pool = Pool(layer, "routeTags")
	layer.tagCount = (layer.tagCount or 0) + 1
	local tag = pool[layer.tagCount]
	if not tag then
		tag = CreateFrame("Frame", nil, layer)
		tag:SetSize(18, 14)
		E:SetTemplate(tag)
		tag.text = E:CreateText(tag, E.tokens.size.tiny, "CENTER")
		tag.text:SetPoint("CENTER", 0, 0)
		pool[layer.tagCount] = tag
	end
	tag:SetFrameLevel(layer:GetFrameLevel() + 2)
	tag:ClearAllPoints()
	tag:SetPoint("BOTTOMLEFT", layer, "TOPLEFT", x + 6, -y + 6)
	tag.text:SetText(text)
	tag.text:SetTextColor(r, g, b)
	tag:SetWidth(math.max(18, (tag.text:GetStringWidth() or 10) + 8))
	tag:Show()
	return tag
end

local function Near(x, y)
	return x and y and x > -0.5 and x < 1.5 and y > -0.5 and y < 1.5
end

-- A note: its text in a small box, the box centered on the spot.
local NOTE_WIDTH = 160
local function Note(layer, x, y, text, r, g, b)
	local pool = Pool(layer, "routeNotes")
	layer.noteCount = (layer.noteCount or 0) + 1
	local note = pool[layer.noteCount]
	if not note then
		note = CreateFrame("Frame", nil, layer)
		E:SetTemplate(note)
		note.bar = note:CreateTexture(nil, "OVERLAY")
		note.bar:SetPoint("TOPLEFT", E.pixel or 1, -(E.pixel or 1))
		note.bar:SetPoint("BOTTOMLEFT", E.pixel or 1, E.pixel or 1)
		note.bar:SetWidth(2)
		note.text = E:CreateText(note, E.tokens.size.small, "LEFT")
		note.text:SetPoint("TOPLEFT", 7, -4)
		note.text:SetWordWrap(true)
		pool[layer.noteCount] = note
	end
	note:SetFrameLevel(layer:GetFrameLevel() + 3)
	note.text:SetWidth(NOTE_WIDTH)
	note.text:SetText(text)
	note.text:SetTextColor(unpack(Kit.TEXT))
	note.bar:SetColorTexture(r, g, b, 1)
	local width = math.min(NOTE_WIDTH, math.ceil(note.text:GetStringWidth() or 40)) + 1
	note.text:SetWidth(width)
	note:SetSize(width + 12, math.ceil(note.text:GetStringHeight() or 12) + 8)
	note:ClearAllPoints()
	note:SetPoint("CENTER", layer, "TOPLEFT", x, -y)
	note:Show()
	return note
end
M.NOTE_WIDTH = NOTE_WIDTH

-- An arrow from (x1, y1) to (x2, y2) in layer pixels: the shaft and a head
-- of two short lines.
local HEAD = 10
local function Arrow(layer, x1, y1, x2, y2, width, r, g, b, a)
	Line(layer, x1, y1, x2, y2, width, r, g, b, a)
	local angle = math.atan2(y2 - y1, x2 - x1)
	for _, turn in ipairs({ 2.6, -2.6 }) do
		local hx, hy = x2 + HEAD * math.cos(angle + turn), y2 + HEAD * math.sin(angle + turn)
		Line(layer, x2, y2, hx, hy, width, r, g, b, a)
	end
end

-- Notes, arrows and lines of a route on this floor (and the draft).
local function DrawNotes(layer, ctx, route, width, height, alpha)
	local ToMap = E.DungeonMaps.ToMap
	local floor = ctx.floor or 1
	local thickness = math.max(2, (tonumber(M.db.lineWidth) or 3) - 0.5)
	for _, stroke in ipairs(route and route.d or {}) do
		if stroke.f == floor then
			local r, g, b = M:ColorRGB(stroke.c)
			local p, lastX, lastY = stroke.p, nil, nil
			for i = 1, #p - 1, 2 do
				local x, y = ToMap(ctx.bounds, p[i], p[i + 1])
				if lastX and Near(x, y) and Near(lastX, lastY) then
					Line(layer, lastX * width, lastY * height, x * width, y * height, thickness, r, g, b, alpha)
				end
				lastX, lastY = x, y
			end
		end
	end
	for _, arrow in ipairs(route and route.a or {}) do
		if arrow.f == floor then
			local x1, y1 = ToMap(ctx.bounds, arrow.x1, arrow.y1)
			local x2, y2 = ToMap(ctx.bounds, arrow.x2, arrow.y2)
			if Near(x1, y1) and Near(x2, y2) then
				local r, g, b = M:ColorRGB(arrow.c)
				Arrow(layer, x1 * width, y1 * height, x2 * width, y2 * height, thickness, r, g, b, alpha)
			end
		end
	end
	for _, note in ipairs(route and route.n or {}) do
		if note.f == floor then
			local x, y = ToMap(ctx.bounds, note.x, note.y)
			if Near(x, y) then
				local r, g, b = M:ColorRGB(note.c)
				Note(layer, x * width, y * height, note.t, r, g, b)
			end
		end
	end
	-- What the editor draws right now (map fractions).
	local draft = ctx.canvas and ctx.canvas.routesDraft
	if draft and draft.points and #draft.points >= 4 then
		local r, g, b = M:ColorRGB(draft.color)
		local p = draft.points
		if draft.kind == "arrow" then
			Arrow(layer, p[1] * width, p[2] * height, p[#p - 1] * width, p[#p] * height, thickness, r, g, b, alpha)
		else
			for i = 1, #p - 3, 2 do
				Line(layer, p[i] * width, p[i + 1] * height, p[i + 2] * width, p[i + 3] * height, thickness, r, g, b, alpha)
			end
		end
	end
end

function provider.draw(_, layer, ctx)
	Hide(layer)
	local key, where = KeyFor(ctx)
	if not key or where == "bosses" then return end
	local db = M.db
	local width, height = layer:GetWidth() or 0, layer:GetHeight() or 0
	if width <= 0 or height <= 0 then return end
	local ToMap = E.DungeonMaps.ToMap
	local alpha = tonumber(db.lineAlpha) or 0.85
	if db.showPatrols then
		for _, pack in ipairs(M:Packs(key)) do
			local last
			for _, point in ipairs(pack.path or {}) do
				local x, y = ToMap(ctx.bounds, point.x, point.y)
				if last and Near(x, y) and Near(last[1], last[2]) then
					Line(layer, last[1] * width, last[2] * height, x * width, y * height, 1.5, PATROL[1], PATROL[2], PATROL[3], alpha * 0.7)
				end
				last = { x, y }
			end
		end
	end
	local route = M:ActiveRoute(key)
	if db.showNotes or (ctx.canvas and ctx.canvas.routesEditing) then DrawNotes(layer, ctx, route, width, height, math.max(alpha, 0.9)) end
	if not (route and (db.showRoute or db.showNumbers)) then return end
	local lineWidth = tonumber(db.lineWidth) or 3
	local previous
	for index, pull in ipairs(route.pulls) do
		local info = M:PullInfo(key, pull)
		if info.found then
			local x, y = ToMap(ctx.bounds, info.x, info.y)
			if Near(x, y) then
				local r, g, b = M:ColorRGB(pull.c)
				if db.showRoute and previous then
					Line(layer, previous[1] * width, previous[2] * height, x * width, y * height, lineWidth, r, g, b, alpha)
				end
				if db.showNumbers then Tag(layer, x * width, y * height, tostring(index), r, g, b) end
				previous = { x, y }
			end
		end
	end
end

function provider.clear(_, layer)
	Hide(layer)
end

M.overlayProvider = provider

function M:EnableOverlay()
	if E.AddMapPinProvider then E:AddMapPinProvider(PROVIDER, provider) end
	if E.DungeonMaps and not self.layoutRegistered then
		self.layoutRegistered = true
		-- The schematic view's box: where the packs of every wing on the map stand.
		E.DungeonMaps:RegisterLayoutSource(PROVIDER, function(mapKey)
			if not M.active then return nil end
			local points = {}
			for _, entry in ipairs(M:Dungeons()) do
				if M:MapKey(entry.key) == mapKey then
					for _, pack in ipairs(M:Packs(entry.key)) do points[#points + 1] = { x = pack.x, y = pack.y } end
				end
			end
			return points
		end)
	end
end

function M:DisableOverlay()
	if E.RemoveMapPinProvider then E:RemoveMapPinProvider(PROVIDER) end
end

function M:RefreshOverlay()
	if self.active and E.RefreshMapPins then E:RefreshMapPins() end
end
