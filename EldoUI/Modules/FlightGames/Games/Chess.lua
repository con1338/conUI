-- EldoUI Flight Games: Chess against the computer. You play White, first
-- to move, against the other faction at four levels. Every rule of
-- chess holds: castling, en passant, promotion, check, checkmate,
-- stalemate, the threefold repetition, the fifty-move rule and a draw when
-- neither side can mate. Click a piece to see where it can go, then click
-- the square; U takes back your last move. A win counts its moves: the
-- fewer, the better.
-- Written from scratch for EldoUI; the pieces are EldoUI's own art
-- (tools/gen_game_art.py), the rules and the computer are in
-- ChessEngine.lua.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board
local C = M.ChessEngine

local CELL, LEFT, TOP = 48, 10, 10
local BOARD = CELL * 8
local PANEL_X = LEFT + BOARD + 14
local WIDTH, HEIGHT = PANEL_X + 180, BOARD + 20
local SLICE_MS = 6            -- the computer thinks this long per frame
local LIST_ROWS = 9
local MODES = {
	{ key = "novice", title = "Novice", depth = 1, noise = 70 },
	{ key = "adept", title = "Adept", depth = 2, noise = 25 },
	{ key = "expert", title = "Expert", depth = 3, noise = 8 },
	{ key = "master", title = "Champion", depth = 4, noise = 0 },
}
local ART = { [C.PAWN] = "ChessPawn", [C.KNIGHT] = "ChessKnight", [C.BISHOP] = "ChessBishop",
	[C.ROOK] = "ChessRook", [C.QUEEN] = "ChessQueen", [C.KING] = "ChessKing" }
local PROMOTE = { C.QUEEN, C.ROOK, C.BISHOP, C.KNIGHT }
local PROMOTE_KEYS = { Q = C.QUEEN, R = C.ROOK, B = C.BISHOP, N = C.KNIGHT }

local Chess = {}
Chess.__index = Chess
Chess.saveKeys = { "moves" }

local function ModeOf(mode)
	return mode and mode.depth and mode or MODES[1]
end

local function Now()
	if debugprofilestop then return debugprofilestop() end
	return (GetTime and GetTime() or 0) * 1000
end

-- Square index of the mailbox from a board cell (1-8, 1-8 from the top).
local function SquareAt(col, row) return C.Square(col - 1, 8 - row) end
local function CellOf(sq)
	local file, rank = C.FileRank(sq)
	return file + 1, 8 - rank
end

local function New(host, mode)
	mode = ModeOf(mode)
	local game = setmetatable({ host = host, mode = mode, squares = {} }, Chess)
	local area = host.area
	for row = 1, 8 do
		for col = 1, 8 do
			local x, y = LEFT + (col - 1) * CELL, TOP + (row - 1) * CELL
			local cell = {}
			cell.tex = B.Sprite(area, CELL, CELL, "BACKGROUND")
			B.Place(cell.tex, x, y, area)
			cell.tint = B.Sprite(area, CELL, CELL, "BORDER")
			B.Place(cell.tint, x, y, area)
			cell.edge = B.Sprite(area, CELL - 4, CELL - 4, "ARTWORK")
			B.Place(cell.edge, x + 2, y + 2, area)
			cell.edge:SetDrawLayer("ARTWORK", 1)
			cell.piece = B.Sprite(area, CELL - 4, CELL - 4, "ARTWORK")
			B.Place(cell.piece, x + 2, y + 2, area)
			cell.piece:SetDrawLayer("ARTWORK", 2)
			cell.dot = B.Dot(area, 14, nil, "OVERLAY")
			B.Place(cell.dot, x + (CELL - 14) / 2, y + (CELL - 14) / 2, area)
			cell.ring = B.Sprite(area, CELL, CELL, "OVERLAY")
			B.Place(cell.ring, x, y, area)
			game.squares[(row - 1) * 8 + col] = cell
		end
	end
	-- The file letters and rank numbers in the board's corners.
	for i = 1, 8 do
		local letter = B.Label(area, E.tokens.size.tiny, "dim", "LEFT")
		letter:SetPoint("BOTTOMLEFT", area, "TOPLEFT", LEFT + (i - 1) * CELL + 3, -(TOP + BOARD - 2))
		letter:SetText(("abcdefgh"):sub(i, i))
		local number = B.Label(area, E.tokens.size.tiny, "dim", "RIGHT")
		number:SetPoint("TOPRIGHT", area, "TOPLEFT", LEFT + BOARD - 3, -(TOP + (i - 1) * CELL + 2))
		number:SetText(9 - i)
	end
	-- The side panel: the two sides, the state, the captures and the moves.
	local function Player(y, icon, name)
		local row = {}
		row.plate = B.Slab(area, 176, 34, "BORDER")
		row.plate:Place(PANEL_X, y)
		row.icon = B.Sprite(area, 24, 24, "ARTWORK")
		B.Place(row.icon, PANEL_X + 6, y + 5, area)
		E:SetClientFile(row.icon, icon, "Interface\\Icons\\INV_Misc_QuestionMark")
		E:TrimIcon(row.icon)
		row.name = B.Label(area, E.tokens.size.body, "body", "LEFT")
		row.name:SetPoint("LEFT", area, "TOPLEFT", PANEL_X + 38, -(y + 17))
		row.name:SetText(name)
		row.taken = {}
		for i = 1, 15 do
			local tex = B.Sprite(area, 13, 13, "ARTWORK")
			B.Place(tex, PANEL_X + 2 + (i - 1) * 11.5, y + 38, area)
			tex:Hide()
			row.taken[i] = tex
		end
		return row
	end
	game.opponent = Player(TOP, host.FactionIcon(-1), host.FactionName(-1))
	game.player = Player(TOP + BOARD - 54, host.FactionIcon(1), L["%s (you)"]:format(host.FactionName(1)))
	game.state = B.Label(area, E.tokens.size.cardTitle, "title", "LEFT")
	game.state:SetPoint("TOPLEFT", area, "TOPLEFT", PANEL_X, -(TOP + 64))
	game.state:SetWidth(176)
	game.hint = B.Label(area, E.tokens.size.small, "secondary", "LEFT")
	game.hint:SetPoint("TOPLEFT", game.state, "BOTTOMLEFT", 0, -4)
	game.hint:SetWidth(176)
	game.lines = {}
	for i = 1, LIST_ROWS do
		local line = B.Label(area, E.tokens.size.small, "secondary", "LEFT")
		line:SetPoint("TOPLEFT", area, "TOPLEFT", PANEL_X, -(TOP + 120 + (i - 1) * 16))
		line:SetWidth(176)
		game.lines[i] = line
	end
	-- The promotion choice: four pieces over the board.
	local choose = CreateFrame("Frame", nil, area)
	choose:SetSize(CELL * 4 + 24, CELL + 24)
	choose:SetPoint("CENTER", area, "TOPLEFT", LEFT + BOARD / 2, -(TOP + BOARD / 2))
	choose:SetFrameLevel(area:GetFrameLevel() + 10)
	choose.bg = choose:CreateTexture(nil, "BACKGROUND")
	choose.bg:SetAllPoints()
	choose.pieces = {}
	for i, kind in ipairs(PROMOTE) do
		local tex = choose:CreateTexture(nil, "ARTWORK")
		tex:SetSize(CELL - 4, CELL - 4)
		tex:SetPoint("TOPLEFT", 12 + (i - 1) * CELL + 2, -14)
		B.Art(tex, ART[kind])
		choose.pieces[i] = tex
	end
	choose:Hide()
	game.choose = choose
	return game
end

---------------------------------------------------------------------------
-- The game
---------------------------------------------------------------------------
-- Plays the move list from the start: the position, the repetitions, the
-- captured pieces and the last move.
function Chess:Replay()
	local pos = C.New()
	self.keys = { [C.Key(pos)] = 1 }
	self.taken = { [1] = {}, [-1] = {} }
	self.last = nil
	for _, m in ipairs(self.moves) do
		local mover = pos.side
		local undo = C.Make(pos, m)
		if undo.cap ~= 0 then table.insert(self.taken[mover], math.abs(undo.cap)) end
		local key = C.Key(pos)
		self.keys[key] = (self.keys[key] or 0) + 1
		self.last = m
	end
	self.pos = pos
	self.legal = C.Legal(pos)
	self.result = nil
	self:Judge()
end

-- Mate, stalemate and the draws.
function Chess:Judge()
	local pos = self.pos
	if #self.legal == 0 then
		if C.InCheck(pos, pos.side) then
			self.result = pos.side == 1 and "lost" or "won"
		else
			self.result = "stalemate"
		end
	elseif pos.half >= 100 then
		self.result = "fifty"
	elseif (self.keys[C.Key(pos)] or 0) >= 3 then
		self.result = "repeat"
	elseif C.DeadPosition(pos) then
		self.result = "dead"
	end
end

function Chess:Start()
	self.moves = {}
	self.picked, self.promo, self.thread = nil, nil, nil
	self.choose:Hide()
	self:Replay()
	self.host.Score(0)
	self:Draw()
end

function Chess:Loaded()
	if type(self.moves) ~= "table" then self.moves = {} end
	self.picked, self.promo, self.thread = nil, nil, nil
	self.choose:Hide()
	local ok = pcall(self.Replay, self)
	if not ok then
		self.moves = {}
		self:Replay()
	end
	self.host.Score(self.pos.full)
end

function Chess:Play(m)
	local captured = self.pos.b[math.floor(m / 128) % 128] ~= 0
	table.insert(self.moves, m)
	self:Replay()
	self.picked = nil
	self.host.Sound(captured and "point" or "turn")
	self.host.Score(self.pos.full)
	self:Draw()
	if self.result then
		self:Finish()
	end
end

function Chess:Finish()
	if self.result == "won" then
		self.host.Score(self.pos.full)
		self.host.Over(true)
	else
		self.host.Over(false)
	end
end

-- Takes back your last move and the answer to it.
function Chess:TakeBack()
	if self.thread or #self.moves == 0 then return end
	local remove = self.pos.side == 1 and 2 or 1
	for _ = 1, math.min(remove, #self.moves) do table.remove(self.moves) end
	self:Replay()
	self.picked = nil
	self.host.Sound("turn")
	self:Draw()
end

-- The computer's move, spread over frames.
function Chess:Think()
	local pos, mode, random = C.Copy(self.pos), self.mode, self.host.Random
	self.thread = coroutine.create(function()
		return C.Search(pos, mode.depth, mode.noise, random)
	end)
	self:Draw()
end

function Chess:Update()
	if self.result then return end
	if not self.thread then
		if self.pos.side == -1 then self:Think() end
		return
	end
	local stop = Now() + SLICE_MS
	repeat
		local ok, m = coroutine.resume(self.thread)
		if not ok then
			self.thread = nil
			error(m)
		end
		if coroutine.status(self.thread) == "dead" then
			self.thread = nil
			if m then self:Play(m) end
			return
		end
	until Now() >= stop
end

function Chess:MovesFrom(sq)
	local out = {}
	for _, m in ipairs(self.legal) do
		if m % 128 == sq then out[#out + 1] = m end
	end
	return out
end

function Chess:Click(col, row)
	if self.result or self.thread or self.pos.side ~= 1 then return end
	local sq = SquareAt(col, row)
	if self.picked then
		local options = {}
		for _, m in ipairs(self:MovesFrom(self.picked)) do
			if math.floor(m / 128) % 128 == sq then options[#options + 1] = m end
		end
		if #options == 1 then
			self:Play(options[1])
			return
		elseif #options > 1 then
			-- A pawn on the last rank: pick what it becomes.
			self.promo = options
			self.choose:Show()
			self:Draw()
			return
		end
	end
	local v = self.pos.b[sq]
	if v ~= C.OFF and v > 0 and #self:MovesFrom(sq) > 0 then
		self.picked = sq ~= self.picked and sq or nil
	else
		self.picked = nil
	end
	self:Draw()
end

function Chess:Promote(kind)
	local options = self.promo
	if not options then return end
	self.promo = nil
	self.choose:Hide()
	for _, m in ipairs(options) do
		if math.floor(m / 16384) == kind then
			self:Play(m)
			return
		end
	end
	self:Draw()
end

function Chess:Press(button, x, y)
	if not (x and y) then return end
	if button == "RightButton" then
		self.picked = nil
		if self.promo then self:Promote(C.QUEEN) end
		self:Draw()
		return
	end
	if button ~= "LeftButton" then return end
	if self.promo then
		local cx = x - (LEFT + BOARD / 2 - (CELL * 4 + 24) / 2) - 12
		local index = math.floor(cx / CELL) + 1
		if PROMOTE[index] then self:Promote(PROMOTE[index]) end
		return
	end
	local col, row = math.floor((x - LEFT) / CELL) + 1, math.floor((y - TOP) / CELL) + 1
	if col >= 1 and col <= 8 and row >= 1 and row <= 8 then self:Click(col, row) end
end

function Chess:Key(key)
	if self.promo and PROMOTE_KEYS[key] then
		self:Promote(PROMOTE_KEYS[key])
		return true
	end
	if key == "U" or key == "BACKSPACE" then
		self:TakeBack()
		return true
	end
	return false
end

local RESULTS = {
	won = Key("Checkmate: you win!"),
	lost = Key("Checkmate: the %s wins."),
	stalemate = Key("Stalemate: a draw."),
	fifty = Key("Fifty moves without a capture or a pawn move: a draw."),
	["repeat"] = Key("The same position three times: a draw."),
	dead = Key("Neither side can mate: a draw."),
}

-- "Checkmate in 24 moves", for the end of the game.
function Chess:Summary()
	if not self.result then return nil end
	if self.result == "won" then
		return E:Plural(self.pos.full, "Checkmate in %d move", "Checkmate in %d moves"):format(self.pos.full)
	end
	return L[RESULTS[self.result]]:format(self.host.FactionName(-1))
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
function Chess:Draw()
	local pos = self.pos
	if not pos then return end
	local paper = E.tokens.paper
	local light, dark = paper.fill, E.tokens.palette.bronze
	local accent = self.host.Color("accent")
	local lastFrom, lastTo
	if self.last then lastFrom, lastTo = C.Decode(self.last) end
	local targets = {}
	if self.picked then
		for _, m in ipairs(self:MovesFrom(self.picked)) do targets[math.floor(m / 128) % 128] = true end
	end
	local checked = C.InCheck(pos, pos.side) and (pos.side == 1 and pos.kw or pos.kb) or nil
	for row = 1, 8 do
		for col = 1, 8 do
			local cell = self.squares[(row - 1) * 8 + col]
			local sq = SquareAt(col, row)
			local isLight = (col + row) % 2 == 0
			B.Fill(cell.tex, isLight and light or { dark[1] * 0.75, dark[2] * 0.75, dark[3] * 0.75 }, 1)
			if sq == checked then
				B.Fill(cell.tint, self.host.Color("bad"), 0.55)
				cell.tint:Show()
			elseif sq == lastFrom or sq == lastTo then
				B.Fill(cell.tint, accent, 0.28)
				cell.tint:Show()
			else
				cell.tint:Hide()
			end
			local v = pos.b[sq]
			if v ~= 0 and v ~= C.OFF then
				local kind = math.abs(v)
				local white = v > 0
				local fill = white and E.tokens.text.body or paper.body
				local edge = white and paper.body or paper.fill
				B.Art(cell.edge, ART[kind] .. "Edge", edge, white and 0.9 or 0.75)
				B.Art(cell.piece, ART[kind], fill, 1)
				cell.edge:Show()
				cell.piece:Show()
			else
				cell.edge:Hide()
				cell.piece:Hide()
			end
			if targets[sq] then
				local filled = v ~= 0
				cell.dot:SetSize(filled and CELL - 6 or 14, filled and CELL - 6 or 14)
				B.Place(cell.dot, LEFT + (col - 1) * CELL + (filled and 3 or (CELL - 14) / 2), TOP + (row - 1) * CELL + (filled and 3 or (CELL - 14) / 2), self.host.area)
				if filled then
					B.Art(cell.dot, "Ring", accent, 0.8)
				else
					cell.dot:SetTexture(B.DOT)
					cell.dot:SetTexCoord(0, 1, 0, 1)
					cell.dot:SetVertexColor(accent[1], accent[2], accent[3], 0.7)
				end
				cell.dot:Show()
			else
				cell.dot:Hide()
			end
			if sq == self.picked then
				B.Art(cell.ring, "Ring", accent, 1)
				cell.ring:Show()
			else
				cell.ring:Hide()
			end
		end
	end
	-- The panel.
	local secondary = self.host.Color("secondary")
	local palette = self.host.Palette()
	local yourTurn = pos.side == 1 and not self.result
	self.player.plate:Paint(yourTurn and self.host.FactionColor(1, palette) or secondary, yourTurn and 0.4 or 0.15)
	self.opponent.plate:Paint((not yourTurn and not self.result) and self.host.FactionColor(-1, palette) or secondary, (not yourTurn and not self.result) and 0.4 or 0.15)
	for side, row in pairs({ [1] = self.player, [-1] = self.opponent }) do
		local list = self.taken[side]
		table.sort(list, function(a, b) return a > b end)
		for i, tex in ipairs(row.taken) do
			local kind = list[i]
			if kind then
				B.Art(tex, ART[kind], side == 1 and paper.fill or E.tokens.text.body, 0.9)
				tex:Show()
			else
				tex:Hide()
			end
		end
	end
	local state, hint
	if self.result then
		state = L[RESULTS[self.result]]:format(self.host.FactionName(-1))
		hint = ""
	elseif self.promo then
		state, hint = L["Pick what the pawn becomes."], L["Q, R, B or N, or a click."]
	elseif self.thread or pos.side == -1 then
		state, hint = L["The %s is thinking..."]:format(self.host.FactionName(-1)), ""
	else
		state = checked and L["Check! Your move."] or L["Your move."]
		hint = L["U takes back your last move."]
	end
	self.state:SetText(state)
	self.hint:SetText(hint)
	if self.promo then
		B.Fill(self.choose.bg, E.tokens.inset, 1)
		self.choose.bg:SetColorTexture(0, 0, 0, 0.85)
		for _, tex in ipairs(self.choose.pieces) do tex:SetVertexColor(unpack(E.tokens.text.body)) end
	end
	-- The last moves, two to a line.
	local total = #self.moves
	local lines = math.ceil(total / 2)
	local first = math.max(1, lines - LIST_ROWS + 1)
	for i, line in ipairs(self.lines) do
		local n = first + i - 1
		if n <= lines then
			local function Name(m)
				if not m then return "" end
				local from, to, promo = C.Decode(m)
				return C.Name(from) .. "-" .. C.Name(to) .. (promo > 0 and ("=" .. (" NBRQ"):sub(promo, promo)) or "")
			end
			line:SetText(("%d.  %s   %s"):format(n, Name(self.moves[n * 2 - 1]), Name(self.moves[n * 2])))
		else
			line:SetText("")
		end
	end
end

M:RegisterGame({
	key = "chess", order = 120, group = "board",
	title = "Chess", desc = "Every rule of chess against the computer, at four levels.",
	controls = Key("Click a piece, then where it goes. U: take back. P: pause."),
	actions = { { key = "U", label = "Take back" } },
	icon = "Interface\\Icons\\INV_Misc_Ticket_Tarot_Furies",
	lower = true, unit = "moves",
	modes = MODES,
	Size = function() return WIDTH, HEIGHT end,
	New = New,
})
