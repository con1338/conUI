-- EldoUI Flight Games: the rules of chess and a small computer player.
--
-- The board is a 10 x 12 mailbox: square = 21 + file + rank * 10 (file and
-- rank 0 to 7, rank 0 is White's first rank), with a border of OFF squares
-- so a step off the board is one lookup. White pieces are 1 to 6 (pawn,
-- knight, bishop, rook, queen, king), Black's are the same numbers
-- negative, an empty square is 0.
--
-- A move is one number: from + to * 128 + promotion * 16384 (promotion is
-- the piece kind a pawn becomes, 0 for none). Make() and Unmake() play and
-- take back a move; Legal() lists the legal moves, with castling, en
-- passant and promotion. Search() is an alpha-beta search with a quiet
-- search for captures, written as a coroutine body that yields every few
-- hundred positions, so the game never stalls a frame.
--
-- Written from scratch for EldoUI.
local _, E = ...
local M = E.FlightGames

local C = {}
M.ChessEngine = C

local OFF = 99
C.OFF = OFF
local PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING = 1, 2, 3, 4, 5, 6
C.PAWN, C.KNIGHT, C.BISHOP, C.ROOK, C.QUEEN, C.KING = PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING
local KNIGHT_STEPS = { 21, 19, 12, 8, -21, -19, -12, -8 }
local DIAGONALS = { 11, 9, -11, -9 }
local LINES = { 10, -10, 1, -1 }
local KING_STEPS = { 11, 9, -11, -9, 10, -10, 1, -1 }
local floor, abs = math.floor, math.abs

function C.Square(file, rank) return 21 + file + rank * 10 end
function C.FileRank(sq) local x = sq - 21 return x % 10, floor(x / 10) end
function C.Encode(from, to, promo) return from + to * 128 + (promo or 0) * 16384 end
function C.Decode(m) return m % 128, floor(m / 128) % 128, floor(m / 16384) end

local LETTERS = { p = PAWN, n = KNIGHT, b = BISHOP, r = ROOK, q = QUEEN, k = KING }
local FILES = "abcdefgh"

-- "e4" for a square.
function C.Name(sq)
	local file, rank = C.FileRank(sq)
	return FILES:sub(file + 1, file + 1) .. (rank + 1)
end

-- A position from a FEN line.
function C.FromFEN(fen)
	local board, placement, side, castle, ep, half, full = {}, fen:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s*(%d*)%s*(%d*)")
	for i = 0, 119 do board[i] = OFF end
	local rank, file = 7, 0
	for ch in placement:gmatch(".") do
		if ch == "/" then
			rank, file = rank - 1, 0
		elseif ch:match("%d") then
			for _ = 1, tonumber(ch) do
				board[C.Square(file, rank)] = 0
				file = file + 1
			end
		else
			local kind = LETTERS[ch:lower()]
			board[C.Square(file, rank)] = ch == ch:upper() and kind or -kind
			file = file + 1
		end
	end
	local pos = { b = board, side = side == "b" and -1 or 1,
		wk = castle:find("K", 1, true) ~= nil, wq = castle:find("Q", 1, true) ~= nil,
		bk = castle:find("k", 1, true) ~= nil, bq = castle:find("q", 1, true) ~= nil,
		ep = 0, half = tonumber(half) or 0, full = tonumber(full) or 1 }
	if ep ~= "-" then
		local f, r = ep:byte(1) - 97, tonumber(ep:sub(2)) - 1
		pos.ep = C.Square(f, r)
	end
	C.FindKings(pos)
	return pos
end

C.START = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
function C.New() return C.FromFEN(C.START) end

function C.FindKings(pos)
	pos.kw, pos.kb = nil, nil
	for sq = 21, 98 do
		if pos.b[sq] == KING then pos.kw = sq elseif pos.b[sq] == -KING then pos.kb = sq end
	end
end

-- True when `sq` is attacked by `by` (1 White, -1 Black).
function C.Attacked(pos, sq, by)
	local b = pos.b
	if by == 1 then
		if b[sq - 9] == PAWN or b[sq - 11] == PAWN then return true end
	else
		if b[sq + 9] == -PAWN or b[sq + 11] == -PAWN then return true end
	end
	local knight, king = KNIGHT * by, KING * by
	for i = 1, 8 do
		if b[sq + KNIGHT_STEPS[i]] == knight then return true end
		if b[sq + KING_STEPS[i]] == king then return true end
	end
	local bishop, rook, queen = BISHOP * by, ROOK * by, QUEEN * by
	for i = 1, 4 do
		local d = DIAGONALS[i]
		local t = sq + d
		while b[t] == 0 do t = t + d end
		if b[t] == bishop or b[t] == queen then return true end
		d = LINES[i]
		t = sq + d
		while b[t] == 0 do t = t + d end
		if b[t] == rook or b[t] == queen then return true end
	end
	return false
end

function C.InCheck(pos, side)
	local king = side == 1 and pos.kw or pos.kb
	return king ~= nil and C.Attacked(pos, king, -side)
end

local function Enemy(v, side) return v ~= OFF and v * side < 0 end

-- Every move by the rules of the pieces, before the check test.
function C.Pseudo(pos, list, capturesOnly)
	list = list or {}
	local n = #list
	local b, side = pos.b, pos.side
	local lastRank = side == 1 and 7 or 0
	for sq = 21, 98 do
		local p = b[sq]
		if p ~= OFF and p * side > 0 then
			local kind = p * side
			if kind == PAWN then
				local dir = 10 * side
				local one = sq + dir
				local _, rank = C.FileRank(sq)
				local _, toRank = C.FileRank(one)
				if b[one] == 0 and (not capturesOnly or toRank == lastRank) then
					if toRank == lastRank then
						for promo = QUEEN, KNIGHT, -1 do n = n + 1 list[n] = sq + one * 128 + promo * 16384 end
					else
						n = n + 1 list[n] = sq + one * 128
						local startRank = side == 1 and 1 or 6
						if rank == startRank and b[one + dir] == 0 and not capturesOnly then n = n + 1 list[n] = sq + (one + dir) * 128 end
					end
				end
				for _, d in ipairs({ dir + 1, dir - 1 }) do
					local t = sq + d
					if Enemy(b[t], side) or (t == pos.ep and pos.ep ~= 0) then
						if toRank == lastRank then
							for promo = QUEEN, KNIGHT, -1 do n = n + 1 list[n] = sq + t * 128 + promo * 16384 end
						else
							n = n + 1 list[n] = sq + t * 128
						end
					end
				end
			elseif kind == KNIGHT or kind == KING then
				local steps = kind == KNIGHT and KNIGHT_STEPS or KING_STEPS
				for i = 1, 8 do
					local t = sq + steps[i]
					local v = b[t]
					if (v == 0 and not capturesOnly) or Enemy(v, side) then n = n + 1 list[n] = sq + t * 128 end
				end
			else
				local dirs = kind == BISHOP and DIAGONALS or kind == ROOK and LINES or KING_STEPS
				for i = 1, #dirs do
					local d = dirs[i]
					local t = sq + d
					while b[t] == 0 do
						if not capturesOnly then n = n + 1 list[n] = sq + t * 128 end
						t = t + d
					end
					if Enemy(b[t], side) then n = n + 1 list[n] = sq + t * 128 end
				end
			end
		end
	end
	-- Castling: the king and rook unmoved, the squares between empty, and
	-- the king never in, through or into check.
	if not capturesOnly then
		if side == 1 and pos.kw == 25 then
			if pos.wk and b[26] == 0 and b[27] == 0 and b[28] == ROOK
				and not C.Attacked(pos, 25, -1) and not C.Attacked(pos, 26, -1) and not C.Attacked(pos, 27, -1) then
				n = n + 1 list[n] = 25 + 27 * 128
			end
			if pos.wq and b[24] == 0 and b[23] == 0 and b[22] == 0 and b[21] == ROOK
				and not C.Attacked(pos, 25, -1) and not C.Attacked(pos, 24, -1) and not C.Attacked(pos, 23, -1) then
				n = n + 1 list[n] = 25 + 23 * 128
			end
		elseif side == -1 and pos.kb == 95 then
			if pos.bk and b[96] == 0 and b[97] == 0 and b[98] == -ROOK
				and not C.Attacked(pos, 95, 1) and not C.Attacked(pos, 96, 1) and not C.Attacked(pos, 97, 1) then
				n = n + 1 list[n] = 95 + 97 * 128
			end
			if pos.bq and b[94] == 0 and b[93] == 0 and b[92] == 0 and b[91] == -ROOK
				and not C.Attacked(pos, 95, 1) and not C.Attacked(pos, 94, 1) and not C.Attacked(pos, 93, 1) then
				n = n + 1 list[n] = 95 + 93 * 128
			end
		end
	end
	return list
end

local CASTLE_ROOK = { [27] = { 28, 26 }, [23] = { 21, 24 }, [97] = { 98, 96 }, [93] = { 91, 94 } }

-- Plays a move; returns what Unmake needs.
function C.Make(pos, m)
	local b, side = pos.b, pos.side
	local from, to, promo = m % 128, floor(m / 128) % 128, floor(m / 16384)
	local p = b[from]
	local cap, capSq = b[to], to
	local undo = { m = m, wk = pos.wk, wq = pos.wq, bk = pos.bk, bq = pos.bq, ep = pos.ep, half = pos.half, full = pos.full,
		kw = pos.kw, kb = pos.kb }
	local kind = p * side
	if kind == PAWN and to == pos.ep and cap == 0 then
		capSq = to - 10 * side
		cap = b[capSq]
		b[capSq] = 0
	end
	undo.cap, undo.capSq = cap, capSq
	b[to] = promo > 0 and promo * side or p
	b[from] = 0
	if kind == KING then
		if side == 1 then pos.kw = to else pos.kb = to end
		if abs(to - from) == 2 then
			local rook = CASTLE_ROOK[to]
			b[rook[2]] = b[rook[1]]
			b[rook[1]] = 0
		end
		if side == 1 then pos.wk, pos.wq = false, false else pos.bk, pos.bq = false, false end
	end
	if from == 28 or to == 28 then pos.wk = false end
	if from == 21 or to == 21 then pos.wq = false end
	if from == 98 or to == 98 then pos.bk = false end
	if from == 91 or to == 91 then pos.bq = false end
	pos.ep = (kind == PAWN and abs(to - from) == 20) and (from + 10 * side) or 0
	pos.half = (kind == PAWN or cap ~= 0) and 0 or pos.half + 1
	if side == -1 then pos.full = pos.full + 1 end
	pos.side = -side
	return undo
end

function C.Unmake(pos, undo)
	local b = pos.b
	local side = -pos.side
	pos.side = side
	local m = undo.m
	local from, to, promo = m % 128, floor(m / 128) % 128, floor(m / 16384)
	local p = promo > 0 and PAWN * side or b[to]
	b[from] = p
	b[to] = 0
	b[undo.capSq] = undo.cap
	if p * side == KING and abs(to - from) == 2 then
		local rook = CASTLE_ROOK[to]
		b[rook[1]] = b[rook[2]]
		b[rook[2]] = 0
	end
	pos.wk, pos.wq, pos.bk, pos.bq = undo.wk, undo.wq, undo.bk, undo.bq
	pos.ep, pos.half, pos.full, pos.kw, pos.kb = undo.ep, undo.half, undo.full, undo.kw, undo.kb
end

-- The legal moves of the side to move.
function C.Legal(pos, capturesOnly)
	local out = {}
	local side = pos.side
	for _, m in ipairs(C.Pseudo(pos, nil, capturesOnly)) do
		local undo = C.Make(pos, m)
		if not C.InCheck(pos, side) then out[#out + 1] = m end
		C.Unmake(pos, undo)
	end
	return out
end

-- The number of positions `depth` moves deep (the standard rules test).
function C.Perft(pos, depth)
	if depth == 0 then return 1 end
	local total = 0
	local side = pos.side
	for _, m in ipairs(C.Pseudo(pos)) do
		local undo = C.Make(pos, m)
		if not C.InCheck(pos, side) then total = total + (depth == 1 and 1 or C.Perft(pos, depth - 1)) end
		C.Unmake(pos, undo)
	end
	return total
end

-- A key for the same position (repetition): the pieces, the side, the
-- castling rights and the en passant square.
function C.Key(pos)
	local parts = {}
	local b = pos.b
	for rank = 0, 7 do
		for file = 0, 7 do parts[#parts + 1] = string.char(b[21 + file + rank * 10] + 70) end
	end
	parts[#parts + 1] = pos.side == 1 and "w" or "b"
	parts[#parts + 1] = (pos.wk and "K" or "") .. (pos.wq and "Q" or "") .. (pos.bk and "k" or "") .. (pos.bq and "q" or "")
	-- The en passant square counts only when a pawn can take there, so
	-- the position after a double step matches its later repeats.
	local ep = pos.ep or 0
	if ep ~= 0 then
		local behind, pawn = ep - 10 * pos.side, PAWN * pos.side
		if b[behind - 1] ~= pawn and b[behind + 1] ~= pawn then ep = 0 end
	end
	parts[#parts + 1] = tostring(ep)
	return table.concat(parts)
end

-- Neither side can mate: king against king, or with one bishop or knight.
function C.DeadPosition(pos)
	local minors, other = 0, 0
	for sq = 21, 98 do
		local v = pos.b[sq]
		if v ~= OFF and v ~= 0 then
			local kind = abs(v)
			if kind == BISHOP or kind == KNIGHT then minors = minors + 1 elseif kind ~= KING then other = other + 1 end
		end
	end
	return other == 0 and minors <= 1
end

-- A plain copy of a position (for saving and the search).
function C.Copy(pos)
	local b = {}
	for i = 0, 119 do b[i] = pos.b[i] end
	return { b = b, side = pos.side, wk = pos.wk, wq = pos.wq, bk = pos.bk, bq = pos.bq, ep = pos.ep,
		half = pos.half, full = pos.full, kw = pos.kw, kb = pos.kb }
end

-- Saved data has a board as a list of 64 squares (rank 1 first).
function C.Pack(pos)
	local squares = {}
	for rank = 0, 7 do
		for file = 0, 7 do squares[#squares + 1] = pos.b[C.Square(file, rank)] end
	end
	return { squares = squares, side = pos.side, wk = pos.wk, wq = pos.wq, bk = pos.bk, bq = pos.bq, ep = pos.ep, half = pos.half, full = pos.full }
end

function C.Unpack(data)
	if type(data) ~= "table" or type(data.squares) ~= "table" or #data.squares ~= 64 then return nil end
	local b = {}
	for i = 0, 119 do b[i] = OFF end
	local at = 0
	for rank = 0, 7 do
		for file = 0, 7 do
			at = at + 1
			local v = tonumber(data.squares[at])
			if not v or v < -6 or v > 6 then return nil end
			b[C.Square(file, rank)] = v
		end
	end
	local pos = { b = b, side = data.side == -1 and -1 or 1, wk = data.wk and true or false, wq = data.wq and true or false,
		bk = data.bk and true or false, bq = data.bq and true or false, ep = tonumber(data.ep) or 0,
		half = tonumber(data.half) or 0, full = tonumber(data.full) or 1 }
	C.FindKings(pos)
	if not (pos.kw and pos.kb) then return nil end
	return pos
end

---------------------------------------------------------------------------
-- The computer player
---------------------------------------------------------------------------
local VALUE = { [PAWN] = 100, [KNIGHT] = 320, [BISHOP] = 330, [ROOK] = 500, [QUEEN] = 900, [KING] = 0 }
C.VALUE = VALUE
-- Square bonuses from White's side, rank 8 first (a common teaching set:
-- pawns forward, knights and bishops to the middle, the king safe).
local PST = {
	[PAWN] = {
		0, 0, 0, 0, 0, 0, 0, 0,  50, 50, 50, 50, 50, 50, 50, 50,  10, 10, 20, 30, 30, 20, 10, 10,  5, 5, 10, 25, 25, 10, 5, 5,
		0, 0, 0, 20, 20, 0, 0, 0,  5, -5, -10, 0, 0, -10, -5, 5,  5, 10, 10, -20, -20, 10, 10, 5,  0, 0, 0, 0, 0, 0, 0, 0 },
	[KNIGHT] = {
		-50, -40, -30, -30, -30, -30, -40, -50,  -40, -20, 0, 0, 0, 0, -20, -40,  -30, 0, 10, 15, 15, 10, 0, -30,  -30, 5, 15, 20, 20, 15, 5, -30,
		-30, 0, 15, 20, 20, 15, 0, -30,  -30, 5, 10, 15, 15, 10, 5, -30,  -40, -20, 0, 5, 5, 0, -20, -40,  -50, -40, -30, -30, -30, -30, -40, -50 },
	[BISHOP] = {
		-20, -10, -10, -10, -10, -10, -10, -20,  -10, 0, 0, 0, 0, 0, 0, -10,  -10, 0, 5, 10, 10, 5, 0, -10,  -10, 5, 5, 10, 10, 5, 5, -10,
		-10, 0, 10, 10, 10, 10, 0, -10,  -10, 10, 10, 10, 10, 10, 10, -10,  -10, 5, 0, 0, 0, 0, 5, -10,  -20, -10, -10, -10, -10, -10, -10, -20 },
	[ROOK] = {
		0, 0, 0, 0, 0, 0, 0, 0,  5, 10, 10, 10, 10, 10, 10, 5,  -5, 0, 0, 0, 0, 0, 0, -5,  -5, 0, 0, 0, 0, 0, 0, -5,
		-5, 0, 0, 0, 0, 0, 0, -5,  -5, 0, 0, 0, 0, 0, 0, -5,  -5, 0, 0, 0, 0, 0, 0, -5,  0, 0, 0, 5, 5, 0, 0, 0 },
	[QUEEN] = {
		-20, -10, -10, -5, -5, -10, -10, -20,  -10, 0, 0, 0, 0, 0, 0, -10,  -10, 0, 5, 5, 5, 5, 0, -10,  -5, 0, 5, 5, 5, 5, 0, -5,
		0, 0, 5, 5, 5, 5, 0, -5,  -10, 5, 5, 5, 5, 5, 0, -10,  -10, 0, 5, 0, 0, 0, 0, -10,  -20, -10, -10, -5, -5, -10, -10, -20 },
	[KING] = {
		-30, -40, -40, -50, -50, -40, -40, -30,  -30, -40, -40, -50, -50, -40, -40, -30,  -30, -40, -40, -50, -50, -40, -40, -30,  -30, -40, -40, -50, -50, -40, -40, -30,
		-20, -30, -30, -40, -40, -30, -30, -20,  -10, -20, -20, -20, -20, -20, -20, -10,  20, 20, 0, 0, 0, 0, 20, 20,  20, 30, 10, 0, 0, 10, 30, 20 },
}

-- The position's worth for the side to move.
function C.Evaluate(pos)
	local b = pos.b
	local score = 0
	for rank = 0, 7 do
		for file = 0, 7 do
			local v = b[21 + file + rank * 10]
			if v ~= 0 then
				local kind = abs(v)
				if v > 0 then
					score = score + VALUE[kind] + PST[kind][(7 - rank) * 8 + file + 1]
				else
					score = score - VALUE[kind] - PST[kind][rank * 8 + file + 1]
				end
			end
		end
	end
	return score * pos.side
end

local MATE = 100000
C.MATE = MATE

-- Captures first, the biggest catch by the smallest piece first.
local function Order(pos, moves)
	local b = pos.b
	local keyed = {}
	for i, m in ipairs(moves) do
		local from, to, promo = m % 128, floor(m / 128) % 128, floor(m / 16384)
		local victim = b[to]
		local score = 0
		if victim ~= 0 and victim ~= OFF then score = VALUE[abs(victim)] * 10 - VALUE[abs(b[from])] / 10 + 10000 end
		if promo > 0 then score = score + VALUE[promo] + 9000 end
		keyed[i] = { m = m, s = score }
	end
	table.sort(keyed, function(x, y) return x.s > y.s end)
	for i, k in ipairs(keyed) do moves[i] = k.m end
	return moves
end

-- Search state: nodes counted and a yield every `slice` nodes.
local search = { nodes = 0, slice = 400 }

local function Tick()
	search.nodes = search.nodes + 1
	if search.nodes % search.slice == 0 and coroutine.running() then coroutine.yield() end
end

local function Quiet(pos, alpha, beta, depth)
	Tick()
	local stand = C.Evaluate(pos)
	if stand >= beta then return beta end
	if stand > alpha then alpha = stand end
	if depth <= 0 then return alpha end
	local side = pos.side
	for _, m in ipairs(Order(pos, C.Pseudo(pos, nil, true))) do
		local undo = C.Make(pos, m)
		if not C.InCheck(pos, side) then
			local score = -Quiet(pos, -beta, -alpha, depth - 1)
			C.Unmake(pos, undo)
			if score >= beta then return beta end
			if score > alpha then alpha = score end
		else
			C.Unmake(pos, undo)
		end
	end
	return alpha
end

local function Negamax(pos, depth, alpha, beta, ply)
	Tick()
	if depth <= 0 then return Quiet(pos, alpha, beta, 4) end
	local side = pos.side
	local any = false
	for _, m in ipairs(Order(pos, C.Pseudo(pos))) do
		local undo = C.Make(pos, m)
		if not C.InCheck(pos, side) then
			any = true
			local score = -Negamax(pos, depth - 1, -beta, -alpha, ply + 1)
			C.Unmake(pos, undo)
			if score >= beta then return beta end
			if score > alpha then alpha = score end
		else
			C.Unmake(pos, undo)
		end
	end
	if not any then return C.InCheck(pos, side) and (-MATE + ply) or 0 end
	return alpha
end

-- The best move for the side to move, `depth` moves deep, with up to
-- `noise` points of chance per move (the lower levels play looser).
-- Call it inside a coroutine to spread it over frames; random(n) gives
-- 1 to n.
function C.Search(pos, depth, noise, random)
	search.nodes = 0
	local moves = Order(pos, C.Legal(pos))
	if #moves == 0 then return nil end
	local best, bestScore = moves[1], -MATE * 2
	for _, m in ipairs(moves) do
		local undo = C.Make(pos, m)
		local score = -Negamax(pos, depth - 1, -MATE * 2, -bestScore + (noise or 0), 1)
		C.Unmake(pos, undo)
		if noise and noise > 0 and random then score = score + random(noise * 2 + 1) - noise - 1 end
		if score > bestScore then best, bestScore = m, score end
	end
	return best, bestScore, search.nodes
end
