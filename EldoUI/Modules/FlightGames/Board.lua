-- EldoUI Flight Games: the drawing kit the games share.
--
--   M.Board.Grid(parent, cols, rows, cell)  a board of square cells
--   M.Board.Sprite(parent, w, h)            a free texture placed by x, y
--   M.Board.Label(parent, size, kind)       a text in the window look
--   M.Board.Model(parent, w, h, display)    a creature model, or nil when
--                                           models are off or it fails
--   M.Board.Tile(tex, color, alpha)         a texture drawn as a rounded,
--                                           softly lit tile in that color
--   M.Board.Art(tex, name, color, alpha)    one of the games' own white
--                                           textures (M.Board.ART), tinted
--   M.Board.Actor(parent, size, display, icon)  a creature model with an
--                                           icon in its place when models
--                                           are off; moved by x, y
--   M.Board.Effects(parent)                 bursts, sparks and rising
--                                           numbers, run by the game's frame
--   M.Board.MapArt(parent, uiMapID, w, h)   a map of the game's world,
--                                           fitted to w x h; nil without it
--
-- Coordinates count from the parent's top left corner, y downward, in
-- window units. Colors are { r, g, b } tables from the host (the palette
-- and the design tokens); nothing here holds a color of its own.
-- Written from scratch for EldoUI.
local _, E = ...
local M = E.FlightGames

local Board = {}
M.Board = Board

-- Every grid and actor made, so a look change restyles them in place.
local grids = setmetatable({}, { __mode = "k" })
local actors = setmetatable({}, { __mode = "k" })

local DOT = "Interface\\AddOns\\EldoUI\\Media\\Textures\\EldoDot.tga"
Board.DOT = DOT

-- The games' own white art (tools/gen_game_art.py): tiles, cards and the
-- card back, the cursor ring, the card suits, the chess pieces, and the
-- tables under the games with their vignette.
local ART_PATH = "Interface\\AddOns\\EldoUI\\Media\\Textures\\Games\\"
Board.ART = {}
for _, name in ipairs({ "Tile", "Card", "CardBack", "Ring", "Heart", "Spade", "Diamond", "Club",
	"TableFelt", "TableWood", "TableStone", "TableNight", "Vignette",
	"ChessKing", "ChessQueen", "ChessRook", "ChessBishop", "ChessKnight", "ChessPawn",
	"ChessKingEdge", "ChessQueenEdge", "ChessRookEdge", "ChessBishopEdge", "ChessKnightEdge", "ChessPawnEdge" }) do
	Board.ART[name] = ART_PATH .. name .. ".tga"
end

-- A deep copy of plain game data (numbers, strings, booleans and tables of
-- them), for saving a game in progress.
local function Copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in pairs(value) do
		local kind = type(v)
		if kind == "table" or kind == "number" or kind == "string" or kind == "boolean" then out[k] = Copy(v) end
	end
	return out
end
Board.Copy = Copy

---------------------------------------------------------------------------
-- Thinking: a computer player's search spread over frames, so no frame
-- waits for it. The search calls Board.Tick() at each position; inside
-- Board.Think it pauses every few hundred positions, and Board.Pump runs
-- it for a few milliseconds a frame.
---------------------------------------------------------------------------
local SLICE_NODES, SLICE_MS = 250, 6
local ticks = 0

local function Now()
	if debugprofilestop then return debugprofilestop() end
	return (GetTime and GetTime() or 0) * 1000
end

function Board.Tick()
	ticks = ticks + 1
	if ticks >= SLICE_NODES then
		ticks = 0
		if coroutine.running() then coroutine.yield() end
	end
end

function Board.Think(fn)
	return coroutine.create(fn)
end

-- Runs a search one frame's worth: true and its result once it is done.
function Board.Pump(thread)
	local stop = Now() + SLICE_MS
	repeat
		local ok, result = coroutine.resume(thread)
		if not ok then error(result, 0) end
		if coroutine.status(thread) == "dead" then return true, result end
	until Now() >= stop
	return false
end

-- A texture drawn as one of the art pieces, tinted (alpha optional).
function Board.Art(tex, name, color, alpha)
	tex:SetTexture(Board.ART[name] or Board.ART.Tile)
	tex:SetTexCoord(0, 1, 0, 1)
	if color then tex:SetVertexColor(color[1], color[2], color[3], alpha or color[4] or 1) end
	return tex
end

-- A rounded, softly lit tile in a color.
function Board.Tile(tex, color, alpha)
	return Board.Art(tex, "Tile", color, alpha)
end

-- A wide tile (an answer box, a long bar): the tile's two halves as round
-- ends and its middle stretched, so the corners keep their shape.
--   slab = Board.Slab(parent, w, h, layer); slab:Place(x, y);
--   slab:Paint(color, alpha); slab:SetShown(on)
local Slab = {}
Slab.__index = Slab

function Board.Slab(parent, width, height, layer)
	local slab = setmetatable({ parent = parent, w = width, h = height, parts = {} }, Slab)
	local cap = math.min(math.floor(height / 2 + 0.5), math.floor(width / 2))
	local coords = { { 0, 0.5 }, { 0.5, 0.5 }, { 0.5, 1 } }
	local widths = { cap, math.max(1, width - cap * 2), cap }
	for i = 1, 3 do
		local tex = parent:CreateTexture(nil, layer or "BORDER")
		tex:SetTexture(Board.ART.Tile)
		tex:SetTexCoord(coords[i][1], coords[i][2], 0, 1)
		tex:SetSize(widths[i], height)
		slab.parts[i] = tex
	end
	slab.widths = widths
	return slab
end

function Slab:Place(x, y)
	local left = x
	for i, tex in ipairs(self.parts) do
		Board.Place(tex, left, y, self.parent)
		left = left + self.widths[i]
	end
end

function Slab:Paint(color, alpha)
	for _, tex in ipairs(self.parts) do tex:SetVertexColor(color[1], color[2], color[3], alpha or 1) end
end

function Slab:SetShown(on)
	for _, tex in ipairs(self.parts) do tex:SetShown(on) end
end

---------------------------------------------------------------------------
-- Grid
---------------------------------------------------------------------------
local Grid = {}
Grid.__index = Grid

function Board.Grid(parent, cols, rows, cell, opts)
	opts = opts or {}
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(cols * cell, rows * cell)
	local grid = setmetatable({ frame = frame, cols = cols, rows = rows, cell = cell, cells = {}, icons = {},
		gap = opts.gap or (M.db and M.db.gridLines and 1 or 0), fixedGap = opts.gap ~= nil, flat = opts.flat }, Grid)
	grids[grid] = true
	frame.bg = frame:CreateTexture(nil, "BACKGROUND")
	frame.bg:SetAllPoints()
	frame.bg:SetColorTexture(unpack(E.tokens.inset))
	for y = 1, rows do
		for x = 1, cols do
			local index = (y - 1) * cols + x
			local tex = frame:CreateTexture(nil, "ARTWORK")
			tex:Hide()
			grid.cells[index] = tex
		end
	end
	grid:Layout()
	return grid
end

-- Places every cell again (after a cell size or grid line change).
function Grid:Layout()
	local cell, gap = self.cell, self.gap
	self.frame:SetSize(self.cols * cell, self.rows * cell)
	for y = 1, self.rows do
		for x = 1, self.cols do
			local tex = self.cells[(y - 1) * self.cols + x]
			tex:ClearAllPoints()
			tex:SetSize(math.max(1, cell - gap), math.max(1, cell - gap))
			tex:SetPoint("TOPLEFT", self.frame, "TOPLEFT", (x - 1) * cell + gap / 2, -((y - 1) * cell + gap / 2))
			local icon = self.icons[(y - 1) * self.cols + x]
			if icon then self:PlaceIcon(icon, tex) end
		end
	end
end

function Grid:Inside(x, y)
	return x >= 1 and y >= 1 and x <= self.cols and y <= self.rows
end

-- The icon sits inside its tile, so the tile's edge frames it.
function Grid:PlaceIcon(icon, tex)
	local inset = (self.flat or not icon.framed) and 0 or math.max(1, math.floor(self.cell * 0.09 + 0.5))
	icon:ClearAllPoints()
	icon:SetPoint("TOPLEFT", tex, "TOPLEFT", inset, -inset)
	icon:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", -inset, inset)
end

-- Fills a cell's texture: a flat color on a flat grid, else a tile.
function Grid:Fill(tex, color, alpha)
	if self.flat then
		tex:SetColorTexture(color[1], color[2], color[3], alpha or color[4] or 1)
	else
		Board.Tile(tex, color, alpha or color[4] or 1)
	end
end

-- A cell filled with a color (alpha optional).
function Grid:Paint(x, y, color, alpha)
	if not self:Inside(x, y) then return end
	local index = (y - 1) * self.cols + x
	local tex = self.cells[index]
	self:Fill(tex, color, alpha)
	tex:Show()
	local icon = self.icons[index]
	if icon then icon:Hide() end
end

-- A cell showing a game icon (trimmed), over an optional fill.
function Grid:Icon(x, y, file, fill)
	if not self:Inside(x, y) then return end
	local index = (y - 1) * self.cols + x
	local icon = self.icons[index]
	if not icon then
		icon = self.frame:CreateTexture(nil, "OVERLAY")
		self.icons[index] = icon
	end
	E:SetClientFile(icon, file, "Interface\\Icons\\INV_Misc_QuestionMark")
	E:TrimIcon(icon)
	icon:SetAlpha(1)
	icon:Show()
	local tex = self.cells[index]
	icon.framed = fill and true or false
	self:PlaceIcon(icon, tex)
	if fill then
		self:Fill(tex, fill, fill[4] or 1)
		tex:Show()
	else
		tex:Hide()
	end
	return icon
end

function Grid:IconAt(x, y)
	if not self:Inside(x, y) then return nil end
	return self.icons[(y - 1) * self.cols + x]
end

function Grid:Clear(x, y)
	if not self:Inside(x, y) then return end
	local index = (y - 1) * self.cols + x
	self.cells[index]:Hide()
	local icon = self.icons[index]
	if icon then icon:Hide() end
end

function Grid:ClearAll()
	for index, tex in ipairs(self.cells) do
		tex:Hide()
		local icon = self.icons[index]
		if icon then icon:Hide() end
	end
end

-- The cell under a point in the grid's parent units (the grid placed at
-- its parent's top left plus `left`, `top`); nil outside.
function Grid:CellAt(px, py, left, top)
	local x = math.floor((px - (left or 0)) / self.cell) + 1
	local y = math.floor((py - (top or 0)) / self.cell) + 1
	if self:Inside(x, y) then return x, y end
end

---------------------------------------------------------------------------
-- Sprites, labels and models
---------------------------------------------------------------------------
function Board.Sprite(parent, width, height, layer)
	local tex = parent:CreateTexture(nil, layer or "ARTWORK")
	tex:SetSize(width, height)
	tex.parentFrame = parent
	return tex
end

-- Puts a region with its top left corner at x, y of its parent.
function Board.Place(region, x, y, parent)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", parent or region.parentFrame or region:GetParent(), "TOPLEFT", x, -y)
end

-- A round sprite (the kit's dot).
function Board.Dot(parent, size, color, layer)
	local tex = Board.Sprite(parent, size, size, layer)
	tex:SetTexture(DOT)
	if color then tex:SetVertexColor(color[1], color[2], color[3]) end
	return tex
end

function Board.Fill(tex, color, alpha)
	tex:SetColorTexture(color[1], color[2], color[3], alpha or 1)
end

function Board.Label(parent, size, kind, justify)
	return E.UIKit.Text(parent, size or E.tokens.size.body, justify or "CENTER", kind)
end

-- A creature model from the game's own creature data. Returns the model
-- frame, or nil when models are off or the client does not draw it; the
-- caller then shows an icon instead.
function Board.Model(parent, width, height, display, opts)
	if not (M.db and M.db.models) then return nil end
	local ok, model = pcall(CreateFrame, "PlayerModel", nil, parent)
	if not ok or not model then return nil end
	model:SetSize(width, height)
	local shown = false
	if display == "player" then
		shown = pcall(model.SetUnit, model, "player")
	elseif type(display) == "number" then
		shown = pcall(model.SetDisplayInfo, model, display)
	end
	if not shown then
		model:Hide()
		return nil
	end
	opts = opts or {}
	if opts.facing then pcall(model.SetFacing, model, opts.facing) end
	if opts.animation then pcall(model.SetAnimation, model, opts.animation) end
	if opts.zoom then pcall(model.SetPortraitZoom, model, opts.zoom) end
	model:EnableMouse(false)
	return model
end

-- Creature display ids from the game's own creature data.
Board.DISPLAY = {
	gryphon = 1149,  -- a wild gryphon
	murloc = 441,    -- a murloc forager
	boar = 503,      -- a stonetusk boar
	kodo = 1453,     -- a Barrens kodo
	bat = 4732,      -- a duskbat
}

-- Animation ids of the game's model animations.
Board.ANIM = { stand = 0, run = 5, fly = 135, dance = 69, cheer = 68 }

---------------------------------------------------------------------------
-- Actors: a model, or its icon when models are off
---------------------------------------------------------------------------
local Actor = {}
Actor.__index = Actor

-- size is the box the actor stands in; the model draws `scale` times as
-- big round the same center (models have room around them), or
-- opts.modelW by opts.modelH when the model needs another shape.
function Board.Actor(parent, size, display, icon, opts)
	opts = opts or {}
	local actor = setmetatable({ parent = parent, size = size, scale = opts.scale or 2, display = display,
		iconFile = icon, opts = opts, visible = true }, Actor)
	actor:Refresh()
	actors[actor] = true
	return actor
end

-- Shows the model or the icon, as the Creature models option says. Each
-- is made once, the first time it is needed, and kept.
function Actor:Refresh()
	local want = self.display and M.db and M.db.models
	if want and not self.modelFrame and not self.noModel then
		local w, h = self:ModelSize()
		self.modelFrame = Board.Model(self.parent, w, h, self.display, self.opts)
		if not self.modelFrame then self.noModel = true end
	end
	self.model = want and self.modelFrame or nil
	if not self.model and not self.icon then
		self.icon = Board.Sprite(self.parent, self.size, self.size, self.opts.layer or "OVERLAY")
		E:SetClientFile(self.icon, self.iconFile or "Interface\\Icons\\INV_Misc_QuestionMark", "Interface\\Icons\\INV_Misc_QuestionMark")
		E:TrimIcon(self.icon)
	end
	if self.model then
		if self.icon then self.icon:Hide() end
		if self.facing then pcall(self.model.SetFacing, self.model, self.facing) end
		if self.animation then pcall(self.model.SetAnimation, self.model, self.animation) end
	elseif self.modelFrame then
		self.modelFrame:Hide()
	end
	if self.x then self:Place(self.x, self.y) end
	self:SetShown(self.visible)
	if self.tint then self:Tint(self.tint[1], self.tint[2]) end
end

function Actor:ModelSize()
	local size = self.size * self.scale
	return self.opts.modelW or size, self.opts.modelH or size
end

-- x, y: the top left corner of the actor's box.
function Actor:Place(x, y)
	self.x, self.y = x, y
	if self.model then
		local w, h = self:ModelSize()
		Board.Place(self.model, x + self.size / 2 - w / 2, y + self.size / 2 - h / 2, self.parent)
	else
		Board.Place(self.icon, x, y, self.parent)
	end
end

function Actor:SetShown(on)
	self.visible = on and true or false
	if self.model then self.model:SetShown(on) else self.icon:SetShown(on) end
end

function Actor:SetAlpha(alpha)
	if self.model then self.model:SetAlpha(alpha) else self.icon:SetAlpha(alpha) end
end

function Actor:Face(facing)
	if self.facing ~= facing then
		self.facing = facing
		if self.model then pcall(self.model.SetFacing, self.model, facing) end
	end
end

function Actor:Animate(animation)
	if self.animation ~= animation then
		self.animation = animation
		if self.model then pcall(self.model.SetAnimation, self.model, animation) end
	end
end

-- Tints the icon (a model keeps its own colors).
function Actor:Tint(color, alpha)
	self.tint = { color, alpha }
	if self.icon then self.icon:SetVertexColor(color[1], color[2], color[3], alpha or 1) end
end

-- After a look change: grid lines and models as the options now say,
-- on the boards already made (nothing new is built for them).
function Board.Restyle()
	local gap = M.db and M.db.gridLines and 1 or 0
	for grid in pairs(grids) do
		if not grid.fixedGap and grid.gap ~= gap then
			grid.gap = gap
			grid:Layout()
		end
	end
	for actor in pairs(actors) do actor:Refresh() end
end

---------------------------------------------------------------------------
-- Effects: bursts, sparks and rising numbers
---------------------------------------------------------------------------
local Effects = {}
Effects.__index = Effects

function Board.Effects(parent)
	return setmetatable({ parent = parent, live = {}, rings = {}, dots = {}, texts = {} }, Effects)
end

local function Take(pool, make)
	local item = table.remove(pool)
	if not item then item = make() end
	item:Show()
	return item
end

-- A ring that opens and fades where something happened.
function Effects:Burst(x, y, color, size, life)
	local ring = Take(self.rings, function()
		local tex = self.parent:CreateTexture(nil, "OVERLAY")
		tex:SetDrawLayer("OVERLAY", 6)
		return tex
	end)
	Board.Art(ring, "Ring", color, 1)
	self.live[#self.live + 1] = { kind = "ring", tex = ring, x = x, y = y, size = size or 40, t = 0, life = life or 0.45, color = color }
end

-- A handful of sparks flying out and falling.
function Effects:Sparks(x, y, color, count, speed)
	for i = 1, count or 8 do
		local dot = Take(self.dots, function()
			local tex = self.parent:CreateTexture(nil, "OVERLAY")
			tex:SetTexture(DOT)
			tex:SetDrawLayer("OVERLAY", 7)
			return tex
		end)
		dot:SetVertexColor(color[1], color[2], color[3], 1)
		local angle = (i / (count or 8)) * math.pi * 2 + (i % 3) * 0.4
		local v = (speed or 120) * (0.6 + (i % 4) * 0.15)
		self.live[#self.live + 1] = { kind = "dot", tex = dot, x = x, y = y, vx = math.cos(angle) * v, vy = math.sin(angle) * v - 60,
			t = 0, life = 0.6, size = 5 }
	end
end

-- A number or word rising from a point ("+10", "Miss").
function Effects:Float(x, y, text, color, size)
	local label = Take(self.texts, function()
		local fs = Board.Label(self.parent, size or E.tokens.size.cardTitle, "title")
		fs:SetDrawLayer("OVERLAY", 7)
		return fs
	end)
	size = size or E.tokens.size.cardTitle
	if label.kitSize ~= size then
		label.kitSize = size
		E:SetWindowFont(label, size)
	end
	label:SetText(text)
	label:SetTextColor(color[1], color[2], color[3], 1)
	self.live[#self.live + 1] = { kind = "text", tex = label, x = x, y = y, t = 0, life = 0.9 }
end

function Effects:Update(dt)
	if #self.live == 0 then return end
	local keep = {}
	for _, fx in ipairs(self.live) do
		fx.t = fx.t + dt
		local f = fx.t / fx.life
		if f >= 1 then
			fx.tex:Hide()
			if fx.kind == "ring" then table.insert(self.rings, fx.tex)
			elseif fx.kind == "dot" then table.insert(self.dots, fx.tex)
			else table.insert(self.texts, fx.tex) end
		else
			keep[#keep + 1] = fx
			if fx.kind == "ring" then
				local size = fx.size * (0.4 + f * 0.9)
				fx.tex:SetSize(size, size)
				Board.Place(fx.tex, fx.x - size / 2, fx.y - size / 2, self.parent)
				fx.tex:SetAlpha(1 - f)
			elseif fx.kind == "dot" then
				fx.vy = fx.vy + 260 * dt
				fx.x, fx.y = fx.x + fx.vx * dt, fx.y + fx.vy * dt
				fx.tex:SetSize(fx.size, fx.size)
				Board.Place(fx.tex, fx.x - fx.size / 2, fx.y - fx.size / 2, self.parent)
				fx.tex:SetAlpha(1 - f)
			else
				fx.tex:ClearAllPoints()
				fx.tex:SetPoint("CENTER", self.parent, "TOPLEFT", fx.x, -(fx.y - f * 26))
				fx.tex:SetAlpha(f < 0.6 and 1 or (1 - f) / 0.4)
			end
		end
	end
	self.live = keep
end

-- Puts every live effect away, back in its pool for the next one.
function Effects:Clear()
	for _, fx in ipairs(self.live) do
		fx.tex:Hide()
		if fx.kind == "ring" then table.insert(self.rings, fx.tex)
		elseif fx.kind == "dot" then table.insert(self.dots, fx.tex)
		else table.insert(self.texts, fx.tex) end
	end
	self.live = {}
end

---------------------------------------------------------------------------
-- Map art: a map of the game's world, drawn from the client's own map
-- tiles and fitted to a box. Returns nil when the client gives no art.
---------------------------------------------------------------------------
function Board.MapArt(parent, uiMapID, width, height, layer)
	local map = C_Map
	if not (map and map.GetMapArtLayers and map.GetMapArtLayerTextures) then return nil end
	local ok, layers = pcall(map.GetMapArtLayers, uiMapID)
	local info = ok and type(layers) == "table" and layers[1]
	if type(info) ~= "table" then return nil end
	local ok2, files = pcall(map.GetMapArtLayerTextures, uiMapID, 1)
	if not (ok2 and type(files) == "table" and #files > 0) then return nil end
	local lw, lh = tonumber(info.layerWidth), tonumber(info.layerHeight)
	local tw, th = tonumber(info.tileWidth) or 256, tonumber(info.tileHeight) or 256
	if not (lw and lh and lw > 0 and lh > 0) then return nil end
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(width, height)
	if frame.SetClipsChildren then frame:SetClipsChildren(true) end
	local sx, sy = width / lw, height / lh
	local cols = math.ceil(lw / tw)
	for i, file in ipairs(files) do
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		local tex = frame:CreateTexture(nil, layer or "ARTWORK")
		tex:SetTexture(file, nil, nil, "TRILINEAR")
		tex:SetSize(tw * sx, th * sy)
		tex:SetPoint("TOPLEFT", frame, "TOPLEFT", col * tw * sx, -row * th * sy)
	end
	return frame
end
