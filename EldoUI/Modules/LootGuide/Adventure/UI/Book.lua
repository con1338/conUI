-- EldoUI My Adventure: the Book.
--
--   Book                                  [Contents] [Copy as text] [New wording]
--   Hedda Stonebrew's story: 4 parts, 14 chapters. Chronicle tone.
--   ---------------------------------------------------------------------------
--   [Ledger][Chronicle][Bard]  [Parchment][EldoUI][Night ledger]   <  3-4 of 28  >
--   +--------------------------------------+-----------------------------------+
--   |  IV                                  |  ...three of every four hours of   |
--   |  Duskwood                            |  the chapter's play.               |
--   |  levels 22-27 · Mar 4 - Mar 8        |                                    |
--   |  ───                                 |  ┌ IV · Duskwood · levels 22-27 ─┐ |
--   |  ┌─┐n the evening of March 5, Hedda  |  │ TIME   14h 05m played  ▁▃▅█▃▂ │ |
--   |  │O│ Stonebrew died three times in   |  │ ...                           │ |
--   |  └─┘ 14 minutes at Raven Hill ...    |  └───────────────────────────────┘ |
--   |                                  21  |                                22 |
--   +--------------------------------------+-----------------------------------+
--
-- The story engine's book (E.Story:Build) laid out as spreads: each part
-- opens with its cover card (UI/Cover.lua), each chapter with its numeral,
-- title and level span, a drop cap on its first paragraph, and closes with
-- its stats spread (UI/StatsSpread.lua). Pages break between sentences,
-- never inside one unless a single sentence is taller than a page, and a
-- chapter head never sits alone at the bottom of a page.
--
-- Tone and look switch live (the facts stay the same). The pages turn with
-- the arrows, the mouse wheel or the Contents list; the level river and
-- the eras on Story so far open the Book at their chapter. Under 600 px of
-- width the Book shows one page at a time. Every sentence is a link: hover
-- shows the facts behind it and the tone ("Wording: Chronicle tone"), a
-- click opens what it is about, Shift-click puts it in the chat box.
--
--   A.Book.Flow(book, set, look) -> blocks
--   A.Book.Paginate(blocks, width, height, size, look) -> pages
--   A.Book.Atoms(text) -> atoms (words and links), A.Book.AtomText(atoms, i, j, id)
local _, E = ...
local L = E.L
local Key = E.Key
local A = E.Adventure
local J = E.Journal
local LG = E.LootGuide
local K = E.AdventureKit
local T = E.tokens

local KEY = "book"
local ICON = "Interface\\Icons\\INV_Misc_Book_09"
local CONTROLS_Y = -(K.HEADER_HEIGHT + 8)
local SPREAD_Y = CONTROLS_Y - 28

-- Page geometry (DESIGN.md steps of 4; the book tokens in Core/Media.lua).
local MARGIN = 24
local GUTTER = 32
local FOOT = 18
local ONE_COLUMN = 600
local LINE_GAP = 3
local PARA_GAP = 6
local CAP_LINES = 3
local CAP_GAP = 6
local HEAD_TITLE = 22

local B = {}
A.Book = B

local function SV() return A.StoryView end
local function Story() return E.Story end

---------------------------------------------------------------------------
-- Atoms: the words and game links of a sentence, so a sentence can split
-- (beside a drop cap, or across a page) without breaking a link.
---------------------------------------------------------------------------
function B.Atoms(text)
	local atoms = {}
	local pos = 1
	text = text or ""
	local function Words(chunk)
		for word in chunk:gmatch("%S+") do atoms[#atoms + 1] = { t = word } end
	end
	while pos <= #text do
		local s, e = text:find("|c%x%x%x%x%x%x%x%x|H.-|h.-|h|r", pos)
		local s2, e2 = text:find("|H.-|h.-|h", pos)
		if s2 and (not s or s2 < s) then s, e = s2, e2 end
		if not s then
			Words(text:sub(pos))
			break
		end
		Words(text:sub(pos, s - 1))
		local glued = s > 1 and not text:sub(s - 1, s - 1):find("%s")
		atoms[#atoms + 1] = { t = text:sub(s, e), link = true, glued = glued }
		pos = e + 1
		-- Punctuation right after a link stays with it ("[Ringblade].").
		local tail = text:match("^[^%s|]+", pos)
		if tail then
			atoms[#atoms].tail = tail
			pos = pos + #tail
		end
	end
	return atoms
end

-- Plain text of atoms i..j (for measuring).
local function AtomPlain(atoms, i, j)
	local out = {}
	for k = i, j do
		local atom = atoms[k]
		local text = atom.link and Story().Grammar.StripMarkup(atom.t) .. (atom.tail or "") or atom.t
		out[#out + 1] = text
	end
	return table.concat(out, " ")
end

-- Hyperlink text of atoms i..j: plain words inside one story link, game
-- links as they are (links cannot nest).
function B.AtomText(atoms, i, j, id)
	local out, run = {}, {}
	local function Flush()
		if #run > 0 then
			out[#out + 1] = "|H" .. id .. "|h" .. table.concat(run, " ") .. "|h"
			run = {}
		end
	end
	for k = i, j do
		local atom = atoms[k]
		if atom.link then
			Flush()
			if #out > 0 then out[#out + 1] = " " end
			out[#out + 1] = atom.t
			if atom.tail then out[#out + 1] = "|H" .. id .. "|h" .. atom.tail .. "|h" end
		else
			if #run == 0 and #out > 0 then out[#out + 1] = " " end
			run[#run + 1] = atom.t
		end
	end
	Flush()
	return table.concat(out)
end
local AtomText = B.AtomText

-- Public rich text stays balanced when a very long field crosses a line or
-- page. Each unit is one UTF-8 character (or an indivisible inline image),
-- with its current color and hyperlink retained around that character.
local function TextUnits(text)
	local units, color, pos = {}, "", 1
	local function Add(raw, visible)
		units[#units + 1] = { text = color .. raw .. (color ~= "" and "|r" or ""),
			space = visible:match("^%s+$") ~= nil, newline = visible == "\n" }
	end
	while pos <= #text do
		local tail, pair = text:sub(pos), text:sub(pos, pos + 1)
		local tint = tail:match("^|c%x%x%x%x%x%x%x%x")
		if tint then color = tint;pos = pos + 10
		elseif pair == "|r" then color = "";pos = pos + 2
		elseif pair == "|H" then
			local first = text:find("|h", pos + 2, true)
			local last = first and text:find("|h", first + 2, true)
			if last then
				local open = text:sub(pos, first + 1)
				for _, unit in ipairs(TextUnits(text:sub(first + 2, last - 1))) do
					Add(open .. unit.text .. "|h", unit.newline and "\n" or unit.space and " " or "x")
				end
				pos = last + 2
			else Add("||", "|");pos = pos + 1 end
		elseif pair == "|T" or pair == "|A" then
			local ending = pair == "|T" and "|t" or "|a"
			local last = text:find(ending, pos + 2, true)
			if last then Add(text:sub(pos, last + 1), "x");pos = last + 2 else Add("||", "|");pos = pos + 1 end
		elseif pair == "||" then Add("||", "|");pos = pos + 2
		else
			local byte = text:byte(pos)
			local count = byte >= 240 and 4 or byte >= 224 and 3 or byte >= 192 and 2 or 1
			local char = text:sub(pos, pos + count - 1)
			Add(char, char);pos = pos + count
		end
	end
	return units
end

local function UnitText(units, first, last)
	local out = {}
	for index = first, last do out[#out + 1] = units[index].text end
	return table.concat(out)
end

-- The caller supplies its own native font measurer; statistics and prose do
-- not substitute guessed character widths for the font they actually paint.
function B.WrapText(text, width, measure)
	if measure(text, nil).width <= width then return text end
	local units, lines, first = TextUnits(text), {}, 1
	while first <= #units do
		local last, fit, space = first, first - 1
		while last <= #units and not units[last].newline do
			if measure(UnitText(units, first, last), nil).width > width then break end
			fit = last;if units[last].space then space = last end;last = last + 1
		end
		if last <= #units and units[last].newline then
			lines[#lines + 1] = UnitText(units, first, last - 1);first = last + 1
		else
			local stop = fit == #units and fit or space or math.max(fit, first)
			lines[#lines + 1] = UnitText(units, first, stop);first = stop + 1
		end
	end
	if #units > 0 and units[#units].newline then lines[#lines + 1] = "" end
	return table.concat(lines, "\n")
end

function B.SplitText(text, width, height, measure)
	if text == "" or measure(text, width).height <= height then return text, "" end
	local units = TextUnits(text)
	local low, high, fit = 1, #units, 0
	while low <= high do
		local mid = math.floor((low + high) / 2)
		if measure(UnitText(units, 1, mid), width).height <= height then fit = mid;low = mid + 1 else high = mid - 1 end
	end
	assert(fit > 0, "Book text needs a page tall enough for its native font")
	local head, tail = UnitText(units, 1, fit), UnitText(units, fit + 1, #units)
	-- A page boundary already supplies this line break.
	if units[fit + 1] and units[fit + 1].newline then tail = UnitText(units, fit + 2, #units) end
	return head, tail
end

---------------------------------------------------------------------------
-- The flow: the book as blocks in reading order
--   cover   { part }
--   head    { chapter }            numeral, title, levels
--   para    { pieces, chapter, cap = true for the first paragraph }
--           a piece is { s = sentence, i, j } (atoms i..j; nil = all)
--   stats   { chapter }
--   coda    { title }              the closing "Story so far" heading
---------------------------------------------------------------------------
local function Pieces(list)
	local pieces = {}
	for _, sentence in ipairs(list or {}) do pieces[#pieces + 1] = { s = sentence } end
	return pieces
end

function B.Flow(book, set, look)
	local blocks = {}
	local rows = book.tone == "ledger"
	local cap = not rows and look ~= "Night"
	for _, part in ipairs(book.parts or {}) do
		blocks[#blocks + 1] = { kind = "cover", part = part }
		for _, chapter in ipairs(part.chapters) do
			blocks[#blocks + 1] = { kind = "head", chapter = chapter, part = part }
			local paras = {}
			if #chapter.opening > 0 then paras[#paras + 1] = chapter.opening end
			for _, para in ipairs(chapter.paragraphs) do paras[#paras + 1] = para end
			if #chapter.closing > 0 then paras[#paras + 1] = chapter.closing end
			for index, para in ipairs(paras) do
				if rows then
					for _, sentence in ipairs(para) do
						blocks[#blocks + 1] = { kind = "para", pieces = { { s = sentence } }, chapter = chapter, row = true }
					end
				else
					blocks[#blocks + 1] = { kind = "para", pieces = Pieces(para), chapter = chapter, cap = cap and index == 1 }
				end
			end
			if chapter.kind ~= "gap" then blocks[#blocks + 1] = { kind = "stats", chapter = chapter } end
		end
	end
	if book.summary and #book.summary > 0 then
		blocks[#blocks + 1] = { kind = "coda", title = L["Story so far"] }
		blocks[#blocks + 1] = { kind = "para", pieces = Pieces(book.summary), chapter = { key = "summary" }, row = rows }
	end
	return blocks
end

---------------------------------------------------------------------------
-- Measuring
---------------------------------------------------------------------------
local function TextH(text, width, size)
	return E.UIKit.TextHeight(text, width, size, { spacing = LINE_GAP })
end

local function LineH(size)
	return size + LINE_GAP
end

local function PiecePlain(piece)
	if not piece.atoms then piece.atoms = B.Atoms(piece.s.text) end
	local atoms = piece.atoms
	return AtomPlain(atoms, piece.i or 1, piece.j or #atoms)
end

local function PiecesPlain(pieces, from, to)
	local out = {}
	for k = from or 1, to or #pieces do out[#out + 1] = PiecePlain(pieces[k]) end
	return table.concat(out, " ")
end

local function HeadHeight(block, width)
	if block.kind == "coda" then return 14 + TextH(block.title, width, T.size.section) + 12 end
	local title = block.chapter.title or ""
	local titleH = E.UIKit.TextHeight(title, width, HEAD_TITLE, { header = true })
	return 12 + 4 + titleH + 6 + 12 + 10 + 1 + 12
end

-- The drop cap: the first letter big, the words beside it filled to three
-- lines at the narrow width, the rest full width under it.
local function CapSplit(block, width, size, capW)
	local first = block.pieces[1]
	if not first then return nil end
	first.atoms = first.atoms or B.Atoms(first.s.text)
	local atoms = first.atoms
	local word = atoms[1]
	if not word or word.link then return nil end
	local letter = word.t:match("^(%u)")
	if not letter then return nil end
	local narrow = width - capW - CAP_GAP
	local capH = CAP_LINES * LineH(size)
	-- How many atoms fit beside the cap (the first word without its letter).
	local function Beside(n)
		local rest = word.t:sub(2)
		local text = (n > 1) and (rest .. " " .. AtomPlain(atoms, 2, n)) or rest
		return text
	end
	local lo, hi = 1, #atoms
	if TextH(Beside(hi), narrow, size) <= capH then
		lo = hi
	else
		while lo < hi do
			local mid = math.floor((lo + hi + 1) / 2)
			if TextH(Beside(mid), narrow, size) <= capH then lo = mid else hi = mid - 1 end
		end
	end
	return { letter = letter, n = lo, narrow = narrow, capH = capH }
end

---------------------------------------------------------------------------
-- Pagination
---------------------------------------------------------------------------
-- pages[i] = { items = { { block, y, h, pieces, cap, cont } }, chapter = key of the first head }
function B.Paginate(blocks, set, width, height, size, look)
	local pages = {}
	local page, y
	local function NewPage()
		page = { items = {}, index = #pages + 1 }
		pages[#pages + 1] = page
		y = 0
	end
	NewPage()
	local lineH = LineH(size)
	local capW = math.ceil(size * CAP_LINES * 0.75)
	local function Place(item, h)
		item.y, item.h = y, h
		page.items[#page.items + 1] = item
		y = y + h
	end
	local index = 1
	while index <= #blocks do
		local block = blocks[index]
		local kind = block.kind
		if kind == "cover" then
			if #page.items > 0 then NewPage() end
			Place({ block = block }, height)
			page.cover = block.part.key
			NewPage()
			index = index + 1
		elseif kind == "head" or kind == "coda" then
			local h = HeadHeight(block, width)
			-- Keep the head with at least two lines of its text.
			if #page.items > 0 and y + h + 2 * lineH > height then NewPage() end
			Place({ block = block }, h)
			if kind == "head" then
				page.chapters = page.chapters or {}
				page.chapters[#page.chapters + 1] = block.chapter.key
			end
			index = index + 1
		elseif kind == "stats" then
			local plan = A.StatsSpread.Measure(set, block.chapter, width, look, { companions = SV().Options().companions })
			if #page.items > 0 and y + plan.height + PARA_GAP > height then NewPage() end
			local fragments = A.StatsSpread.Pages(plan, height - PARA_GAP)
			for part, fragment in ipairs(fragments) do
				if part > 1 then NewPage() end
				Place({ block = block, stats = fragment }, fragment.height + PARA_GAP)
			end
			index = index + 1
		else
			-- A paragraph (or the rest of one).
			local pieces = block.pieces
			local cap = block.cap and not block.cont and CapSplit(block, width, size, capW)
			local function Height(to)
				local text = PiecesPlain(pieces, 1, to)
				if cap then
					-- The cap block, then the rest of the first sentence and the others at full width.
					local first = pieces[1]
					local rest = first.atoms and #first.atoms > cap.n and AtomPlain(first.atoms, cap.n + 1, #first.atoms) or ""
					local others = to > 1 and PiecesPlain(pieces, 2, to) or ""
					local below = (rest .. " " .. others):gsub("^%s+", ""):gsub("%s+$", "")
					return cap.capH + (below ~= "" and (2 + TextH(below, width, size)) or 0)
				end
				return TextH(text, width, size)
			end
			local room = height - y
			local whole = Height(#pieces)
			if whole <= room then
				Place({ block = block, pieces = pieces, cap = cap }, math.min(whole + PARA_GAP, room))
				index = index + 1
			else
				-- Whole sentences that fit, at least two lines' worth.
				local fit = 0
				for k = 1, #pieces - 1 do
					if Height(k) <= room then fit = k else break end
				end
				if fit > 0 and Height(fit) >= 2 * lineH then
					local head, tail = {}, {}
					for k = 1, fit do head[k] = pieces[k] end
					for k = fit + 1, #pieces do tail[#tail + 1] = pieces[k] end
					Place({ block = block, pieces = head, cap = cap }, math.min(Height(fit) + PARA_GAP, room))
					blocks[index] = { kind = "para", pieces = tail, chapter = block.chapter, cont = true, row = block.row }
					NewPage()
				elseif #page.items > 0 then
					NewPage()
				else
					-- One sentence taller than a page: split it by words.
					local piece = pieces[1]
					piece.atoms = piece.atoms or B.Atoms(piece.s.text)
					local from = piece.i or 1
					local to = piece.j or #piece.atoms
					local n = from
					while n < to and TextH(AtomPlain(piece.atoms, from, n + 1), width, size) <= room do n = n + 1 end
					local headPiece = { s = piece.s, atoms = piece.atoms, i = from, j = n }
					local restPiece = { s = piece.s, atoms = piece.atoms, i = n + 1, j = to }
					local tail = { restPiece }
					for k = 2, #pieces do tail[#tail + 1] = pieces[k] end
					Place({ block = block, pieces = { headPiece } }, room)
					if n >= to then table.remove(tail, 1) end
					if #tail > 0 then
						blocks[index] = { kind = "para", pieces = tail, chapter = block.chapter, cont = true, row = block.row }
					else
						index = index + 1
					end
					NewPage()
				end
			end
		end
	end
	if #pages > 1 and #pages[#pages].items == 0 then table.remove(pages) end
	return pages
end

---------------------------------------------------------------------------
-- Drawing one page
---------------------------------------------------------------------------
local function Pool(page, key, make)
	page.pools[key] = page.pools[key] or { list = {}, used = 0 }
	local pool = page.pools[key]
	pool.used = pool.used + 1
	local object = pool.list[pool.used]
	if not object then
		object = make()
		pool.list[pool.used] = object
	end
	object:Show()
	return object
end

local function ResetPools(page)
	for _, pool in pairs(page.pools) do
		for index = 1, #pool.list do pool.list[index]:Hide() end
		pool.used = 0
	end
end

local function NewText(page, size, header)
	local fs = K.Text(page, size, "LEFT", "body", header)
	fs:SetWordWrap(true)
	return fs
end

-- The font of a pooled text for this size and look: the ink font on
-- Parchment, the profile font on the other looks. The text keeps both, so
-- a look switch at the same size still changes the font.
local function SetSize(fs, size, header, look)
	fs.akLook = look
	if fs.akSize ~= size or fs.akPaper ~= K.OnPaperText(fs) then K.InkFont(fs, size, header) end
end

local function PieceText(page, piece, look)
	page.count = page.count + 1
	local key = piece.s.chapterKey or "b"
	local id = ("eldostory:%s:%d"):format(key, page.count)
	page.storyMap[id] = piece.s
	piece.atoms = piece.atoms or B.Atoms(piece.s.text)
	local text = AtomText(piece.atoms, piece.i or 1, piece.j or #piece.atoms, id)
	if A.db and A.db.showSources and (piece.j == nil or piece.j >= #piece.atoms) then
		text = text .. " " .. SV().Hex("dim", look) .. "°|r"
	end
	return text
end

local function DrawPage(page, data, frame)
	ResetPools(page)
	wipe(page.storyMap)
	page.count = 0
	page.storySet = frame.set
	page.number:SetText("")
	if not data then return end
	local look, size, width = frame.look, frame.size, page.textWidth
	local set = frame.set
	for _, item in ipairs(data.items) do
		local block = item.block
		local kind = block.kind
		local top = -item.y
		if kind == "cover" then
			local cover = Pool(page, "cover", function() return A.Cover.Create(page) end)
			cover:ClearAllPoints()
			cover:SetPoint("TOPLEFT", page.text, "TOPLEFT", 0, 0)
			cover:SetPoint("BOTTOMRIGHT", page.text, "BOTTOMRIGHT", 0, 0)
			cover.animate = frame.turning
			cover:SetPart(frame.book, set, block.part, look)
		elseif kind == "head" or kind == "coda" then
			local head = Pool(page, "head", function()
				local h = CreateFrame("Frame", nil, page)
				h.numeral = K.Text(h, T.size.small, "LEFT", "secondary")
				-- Both lines span the head with top anchors only: a bare RIGHT
				-- would pin the title's vertical center to the head's.
				h.numeral:SetPoint("TOPLEFT", 0, -12)
				h.numeral:SetPoint("TOPRIGHT", 0, -12)
				h.title = K.Text(h, HEAD_TITLE, "LEFT", "head", true)
				h.title:SetPoint("TOPLEFT", h.numeral, "BOTTOMLEFT", 0, -4)
				h.title:SetPoint("TOPRIGHT", h.numeral, "BOTTOMRIGHT", 0, -4)
				h.title:SetWordWrap(true)
				h.span = K.Text(h, T.size.small, "LEFT", "secondary")
				h.span:SetPoint("TOPLEFT", h.title, "BOTTOMLEFT", 0, -6)
				h.rule = h:CreateTexture(nil, "ARTWORK")
				h.rule:SetTexture(E.media.flat)
				E:Hairline(h.rule, "h", 1)
				h.rule:SetWidth(64)
				h.rule:SetPoint("TOPLEFT", h.span, "BOTTOMLEFT", 0, -10)
				return h
			end)
			head:ClearAllPoints()
			head:SetPoint("TOPLEFT", page.text, "TOPLEFT", 0, top)
			head:SetPoint("TOPRIGHT", page.text, "TOPRIGHT", 0, top)
			head:SetHeight(item.h)
			if kind == "coda" then
				head.numeral:SetText("")
				head.title:SetText(block.title)
				head.span:SetText("")
			else
				local chapter = block.chapter
				head.numeral:SetText(chapter.numeral and E:CaptionText((L["Chapter %s"]):format(chapter.numeral)) or "")
				head.title:SetText(chapter.title or "")
				head.span:SetText(chapter.span or "")
			end
			SV().Paint(head.numeral, "secondary", look)
			SV().Paint(head.title, "head", look)
			SV().Paint(head.span, "secondary", look)
			local accent = E.media.accentColor
			head.rule:SetVertexColor(accent[1], accent[2], accent[3], 1)
		elseif kind == "stats" then
			local spread = Pool(page, "stats", function() return A.StatsSpread.Create(page) end)
			spread:ClearAllPoints()
			spread:SetPoint("TOPLEFT", page.text, "TOPLEFT", 0, top - 4)
			spread:SetPoint("TOPRIGHT", page.text, "TOPRIGHT", 0, top - 4)
			spread:SetChapter(set, block.chapter, look, { companions = SV().Options().companions }, item.stats)
		else
			local pieces = item.pieces or block.pieces
			for _, piece in ipairs(pieces) do piece.s.chapterKey = block.chapter.key end
			local cap = item.cap
			if cap then
				local letter = Pool(page, "cap", function() return NewText(page, size * CAP_LINES, true) end)
				local capSize = math.floor(LineH(size) * CAP_LINES * 0.9)
				SetSize(letter, capSize, true, look)
				letter:SetWordWrap(false)
				letter:ClearAllPoints()
				letter:SetPoint("TOPLEFT", page.text, "TOPLEFT", 0, top + 2)
				letter:SetText(cap.letter)
				-- A wide letter (M, W) never runs into the words beside it.
				local room = width - cap.narrow - CAP_GAP
				local capW = letter:GetStringWidth() or 0
				if capW > room and room > 0 then
					SetSize(letter, math.max(math.floor(capSize * room / capW), size), true, look)
				end
				SV().Paint(letter, look == "Parchment" and T.paper and "head" or "accent", look)
				-- Beside the cap: the first word without its letter, and on.
				local first = pieces[1]
				first.atoms = first.atoms or B.Atoms(first.s.text)
				page.count = page.count + 1
				local id = ("eldostory:%s:%d"):format(block.chapter.key, page.count)
				page.storyMap[id] = first.s
				local atoms = first.atoms
				local besideAtoms = { { t = atoms[1].t:sub(2) } }
				for k = 2, cap.n do besideAtoms[#besideAtoms + 1] = atoms[k] end
				local beside = Pool(page, "para", function() return NewText(page, size) end)
				SetSize(beside, size, false, look)
				beside:SetSpacing(LINE_GAP)
				beside:ClearAllPoints()
				beside:SetPoint("TOPLEFT", page.text, "TOPLEFT", width - cap.narrow, top)
				beside:SetWidth(cap.narrow)
				beside:SetText(AtomText(besideAtoms, 1, #besideAtoms, id))
				SV().Paint(beside, "body", look)
				-- Under it: the rest of the first sentence, then the others.
				local parts = {}
				if #atoms > cap.n then parts[#parts + 1] = AtomText(atoms, cap.n + 1, #atoms, id) end
				for k = 2, #pieces do parts[#parts + 1] = PieceText(page, pieces[k], look) end
				if #parts > 0 then
					local below = Pool(page, "para", function() return NewText(page, size) end)
					SetSize(below, size, false, look)
					below:SetSpacing(LINE_GAP)
					below:ClearAllPoints()
					below:SetPoint("TOPLEFT", page.text, "TOPLEFT", 0, top - cap.capH - 2)
					below:SetWidth(width)
					below:SetText(table.concat(parts, " "))
					SV().Paint(below, "body", look)
				end
			else
				local fs = Pool(page, "para", function() return NewText(page, size) end)
				SetSize(fs, size, false, look)
				fs:SetSpacing(LINE_GAP)
				fs:ClearAllPoints()
				fs:SetPoint("TOPLEFT", page.text, "TOPLEFT", 0, top)
				fs:SetWidth(width)
				local parts = {}
				for _, piece in ipairs(pieces) do parts[#parts + 1] = PieceText(page, piece, look) end
				fs:SetText(table.concat(parts, " "))
				SV().Paint(fs, "body", look)
			end
		end
	end
	page.number:SetText(tostring(data.index))
	SV().Paint(page.number, "secondary", look)
end

---------------------------------------------------------------------------
-- The section
---------------------------------------------------------------------------
local function UIState()
	local rec = J.Char and J:Char()
	local ui = rec and rec.ui
	if type(ui) ~= "table" then
		B.session = B.session or {}
		return B.session
	end
	if type(ui.book) ~= "table" then ui.book = {} end
	return ui.book
end

local function PaintSpread(frame)
	local look = frame.look
	local spread = frame.spread
	if look == "Parchment" and T.paper then
		local fill, rule = T.paper.fill or T.paper.card, SV().Ink("rule", look)
		spread:SetBackdropColor(fill[1], fill[2], fill[3], 1)
		spread:SetBackdropBorderColor(rule[1], rule[2], rule[3], 1)
		K.ShowPaper(spread.paper, true)
	else
		E:SetTemplate(spread, look ~= "Night")
		K.ShowPaper(spread.paper, false)
	end
	local rule = SV().Ink("rule", look)
	spread.gutter:SetVertexColor(rule[1], rule[2], rule[3], rule[4] or 1)
end

local function CreatePage(spread, frame)
	local page = CreateFrame("Frame", nil, spread)
	page.pools = {}
	page.storyMap = {}
	page.count = 0
	page.text = CreateFrame("Frame", nil, page)
	page.text:EnableMouse(false)
	page.number = K.Text(page, T.size.small, "CENTER", "secondary")
	SV().HookLinks(page)
	page:EnableMouse(true)
	page:EnableMouseWheel(true)
	page:SetScript("OnMouseWheel", function(_, delta) frame:Turn(delta > 0 and -1 or 1) end)
	return page
end

local function Build(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetAllPoints()
	frame.header = K.Header(frame)
	frame.header:SetPoint("TOPLEFT")
	frame.header:SetPoint("TOPRIGHT")

	frame.tone = K.Switch(frame, SV().TONES, SV().Tone(), function(tone) SV().SetTone(tone) end)
	frame.tone:SetPoint("TOPLEFT", 0, CONTROLS_Y)
	local looks = {}
	for _, look in ipairs(SV().LOOKS) do looks[#looks + 1] = { look.key, look.label, look.tip } end
	frame.looks = K.Switch(frame, looks, SV().Look(), function(look) SV().SetLook(look) end)
	frame.looks:SetPoint("LEFT", frame.tone, "RIGHT", 16, 0)

	frame.next = LG.Kit.Button(frame, ">", 26, T.height.button, function() frame:Turn(1) end, L["Next pages"], L["The mouse wheel turns the pages too."])
	frame.next:SetPoint("TOPRIGHT", 0, CONTROLS_Y + 2)
	frame.pageText = K.Text(frame, T.size.small, "RIGHT", "secondary")
	frame.pageText:SetPoint("RIGHT", frame.next, "LEFT", -8, 0)
	frame.prev = LG.Kit.Button(frame, "<", 26, T.height.button, function() frame:Turn(-1) end, L["Previous pages"], L["The mouse wheel turns the pages too."])
	frame.prev:SetPoint("RIGHT", frame.pageText, "LEFT", -8, 0)

	frame.spread = K.Card(frame, { solid = true })
	frame.spread:SetPoint("TOPLEFT", 0, SPREAD_Y)
	frame.spread:SetPoint("BOTTOMRIGHT")
	frame.spread.paper = frame.spread:CreateTexture(nil, "BACKGROUND", nil, 1)
	frame.spread.paper:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	frame.spread.paper:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	if not E:SetClientAtlas(frame.spread.paper, "AdventureMap_TileBg_Parchment", E.media.flat) then
		local fill = T.paper and T.paper.fill
		if fill then frame.spread.paper:SetVertexColor(fill[1], fill[2], fill[3], 1) end
	end
	frame.spread.paper:SetHorizTile(true)
	frame.spread.paper:SetVertTile(true)
	frame.spread.paper:Hide()
	K.PaperWash(frame.spread, frame.spread.paper, 2)
	frame.spread.gutter = frame.spread:CreateTexture(nil, "ARTWORK")
	frame.spread.gutter:SetTexture(E.media.flat)
	E:Hairline(frame.spread.gutter, "w", 1)
	frame.spread:EnableMouseWheel(true)
	frame.spread:SetScript("OnMouseWheel", function(_, delta) frame:Turn(delta > 0 and -1 or 1) end)
	frame.pages = { CreatePage(frame.spread, frame), CreatePage(frame.spread, frame) }
	frame.empty = K.Empty(frame.spread)
	frame.empty:SetAllPoints()

	-- Two pages side by side, or one under ONE_COLUMN px.
	function frame:Geometry()
		local w = self.spread:GetWidth() or 0
		local h = self.spread:GetHeight() or 0
		local columns = w >= ONE_COLUMN and 2 or 1
		local pageW = columns == 2 and math.floor((w - 2 * MARGIN - GUTTER) / 2) or math.floor(w - 2 * MARGIN)
		local textH = math.floor(h - 2 * MARGIN - FOOT)
		return columns, math.max(pageW, 120), math.max(textH, 120), w, h
	end

	function frame:LayoutPages()
		local columns, pageW, textH = self:Geometry()
		self.columns = columns
		for index, page in ipairs(self.pages) do
			page:ClearAllPoints()
			local left = MARGIN + (index - 1) * (pageW + GUTTER)
			page:SetPoint("TOPLEFT", self.spread, "TOPLEFT", left, -MARGIN)
			page:SetSize(pageW, textH + FOOT)
			page.text:ClearAllPoints()
			page.text:SetPoint("TOPLEFT")
			page.text:SetSize(pageW, textH)
			page.textWidth = pageW
			page.number:ClearAllPoints()
			if index == 1 then page.number:SetPoint("BOTTOMLEFT", 0, 0) else page.number:SetPoint("BOTTOMRIGHT", 0, 0) end
			page:SetShown(index <= columns)
		end
		self.spread.gutter:ClearAllPoints()
		self.spread.gutter:SetPoint("TOP", self.spread, "TOPLEFT", MARGIN + pageW + GUTTER / 2, -MARGIN)
		self.spread.gutter:SetPoint("BOTTOM", self.spread, "BOTTOMLEFT", MARGIN + pageW + GUTTER / 2, MARGIN)
		self.spread.gutter:SetShown(columns == 2)
		return columns, pageW, textH
	end

	-- The book in the current tone and look, paginated for this size.
	function frame:Compose()
		local book, set = SV().Build()
		self.book, self.set = book, set
		self.look = SV().Look()
		self.size = SV().BodySize()
		if not (book and set) or book.empty then
			self.layout = nil
			return nil
		end
		local columns, pageW, textH = self:LayoutPages()
		local key = table.concat({ tostring(book), self.look, self.size, pageW, textH, tostring(A.db and A.db.showSources),
			tostring(SV().Options().companions), A.StatsSpread.FontKey(self.look) }, "|")
		if self.layout and self.layout.key == key then return self.layout end
		local started = debugprofilestop()
		local blocks = B.Flow(book, set, self.look)
		local pages = B.Paginate(blocks, set, pageW, textH, self.size, self.look)
		local chapterPage, partPage = {}, {}
		for index, page in ipairs(pages) do
			for _, ckey in ipairs(page.chapters or {}) do chapterPage[ckey] = chapterPage[ckey] or index end
			for _, item in ipairs(page.items) do
				local chapter = item.block.chapter
				if chapter and chapter.key then chapterPage[chapter.key] = chapterPage[chapter.key] or index end
			end
			if page.cover then partPage[page.cover] = partPage[page.cover] or index end
		end
		self.layout = { key = key, pages = pages, chapterPage = chapterPage, partPage = partPage, columns = columns,
			ms = debugprofilestop() - started }
		self.paginateMs = self.layout.ms
		return self.layout
	end

	-- The chapter you are reading (kept across tone, look and size): the one
	-- you jumped to while it is on the spread, else the chapter at the top of
	-- the spread (the chapter after a part's cover, in two columns).
	local function ItemKey(item)
		local block = item and item.block
		if not block then return nil end
		if block.kind == "cover" then return "part:" .. tostring(block.part.key) end
		return block.chapter and block.chapter.key
	end

	function frame:Anchor()
		local layout = self.layout
		if not layout then return nil end
		local first = self.first or 1
		local columns = self.columns or 2
		if self.wantAnchor then
			for index = first, first + columns - 1 do
				local page = layout.pages[index]
				for _, item in ipairs(page and page.items or {}) do
					if ItemKey(item) == self.wantAnchor then return self.wantAnchor end
				end
			end
		end
		local page = layout.pages[first]
		if not page then return nil end
		local key = ItemKey(page.items[1])
		if page.cover and columns == 2 and layout.pages[first + 1] then
			key = ItemKey(layout.pages[first + 1].items[1]) or key
		end
		return key
	end

	function frame:FirstFor(pageIndex)
		local columns = self.columns or 2
		if columns == 1 then return pageIndex end
		return pageIndex - ((pageIndex - 1) % 2)
	end

	function frame:Spread()
		local layout = self.layout
		if not layout then return end
		local count = #layout.pages
		local first = math.min(math.max(self.first or 1, 1), count)
		first = self:FirstFor(first)
		self.first = first
		for index, page in ipairs(self.pages) do
			if index <= (self.columns or 2) then DrawPage(page, layout.pages[first + index - 1], self) end
		end
		local last = math.min(first + (self.columns or 2) - 1, count)
		self.pageText:SetText(first == last and (L["%d of %d"]):format(first, count) or (L["%d-%d of %d"]):format(first, last, count))
		self.prev:SetEnabled(first > 1)
		self.next:SetEnabled(last < count)
		local anchor = self:Anchor()
		if anchor then UIState().at = anchor end
	end

	function frame:GoToPage(index, anchor)
		if not self.layout then return false end
		self.wantAnchor = anchor
		self.first = self:FirstFor(math.min(math.max(index, 1), #self.layout.pages))
		self:Spread()
		return true
	end

	function frame:GoToChapter(key)
		local layout = self.layout
		if not (layout and key) then return false end
		local index = layout.chapterPage[key]
		if not index and key:find("^part:") then index = layout.partPage[key:sub(6)] end
		if not index then return false end
		return self:GoToPage(index, key)
	end

	function frame:GoToPart(key)
		local layout = self.layout
		local index = layout and layout.partPage[key]
		if not index then return false end
		return self:GoToPage(index, "part:" .. tostring(key))
	end

	function frame:GoToLevel(level)
		if not self.book then return false end
		for _, chapter in ipairs(self.book.chapters) do
			if chapter.a and chapter.b and level >= chapter.a and level <= chapter.b then return self:GoToChapter(chapter.key) end
		end
		return false
	end

	function frame:Turn(step)
		local layout = self.layout
		if not layout then return false end
		local columns = self.columns or 2
		local target = (self.first or 1) + step * columns
		if target < 1 or target > #layout.pages then return false end
		self.turning = SV().Motion()
		self:GoToPage(target)
		if self.turning then
			for index = 1, columns do E:FadeIn(self.pages[index], 0.14) end
		end
		self.turning = false
		return true
	end

	-- The Contents list (the chapter list), from the header button.
	function frame:FillContents(root)
		root:CreateTitle(L["Contents"])
		if not self.book then return end
		for _, part in ipairs(self.book.parts) do
			local title = part.number and (L["Part %d · %s"]):format(part.number, part.title or "") or (part.title or "")
			root:CreateButton(title, function() self:GoToPart(part.key) end)
			for _, chapter in ipairs(part.chapters) do
				root:CreateButton(("    %s. %s (%s)"):format(chapter.numeral or "", chapter.title or "", chapter.span or ""),
					function() self:GoToChapter(chapter.key) end)
			end
		end
	end

	function frame:Contents(owner)
		E.UIKit.ContextMenu(owner or self, function(_, root) self:FillContents(root) end, { at = "owner" })
	end

	function frame:Draw()
		if not self:IsShown() then
			self.dirty = true
			return
		end
		self.dirty = false
		local started = debugprofilestop()
		local layout = self:Compose()
		local book, set = self.book, self.set
		self.tone:SetActive(SV().Tone())
		local available = SV().Looks()
		self.looks:SetShown(#available > 1)
		for _, button in ipairs(self.looks.buttons) do
			local ok = false
			for _, look in ipairs(available) do if look.key == button.key then ok = true end end
			button:SetShown(ok)
		end
		self.looks:Layout()
		self.looks:SetActive(self.look)
		PaintSpread(self)
		local actions = {}
		if layout then
			actions[#actions + 1] = { L["Contents"], function(button) self:Contents(button) end, L["Every part and chapter of the Book. Click one to turn to it."] }
		end
		if layout then
			actions[#actions + 1] = { L["Copy as text"], function() SV().CopyText(book, set) end, L["The whole Book in this tone as plain text, in a copy box."] }
			actions[#actions + 1] = { L["New wording"], function() SV().Reshuffle() end, L["Picks new wording for the whole Book. The facts don't change."] }
		end
		self.header:SetActions(actions)
		self.header:SetTitle(L["Book"])
		if not layout then
			self.header:SetSentence(L["Your story in chapters, written from what the journal recorded."])
			for _, page in ipairs(self.pages) do
				ResetPools(page)
				page.number:SetText("")
				page:Hide()
			end
			self.spread.gutter:Hide()
			self.empty:Set(L["The first page is still blank"], Story() and Story().Render.emptyText or "", ICON,
				A:SectionShown("journey") and { { L["Open the Journey"], function() A:OpenSection("journey") end } } or nil)
			self.empty:Show()
			-- An empty book has no pages to turn: no arrows.
			self.prev:Hide()
			self.next:Hide()
			self.pageText:SetText("")
			self.drawMs = debugprofilestop() - started
			return
		end
		self.empty:Hide()
		self.prev:Show()
		self.next:Show()
		local tone = SV().TONES
		local toneName
		for _, entry in ipairs(tone) do if entry[1] == book.tone then toneName = L[entry[2]] end end
		self.header:SetSentence((L["%s's story: %s, %s. %s tone."]):format(set.me.first or set.me.name or "",
			E:Plural(#book.parts, "%d part", "%d parts"):format(#book.parts),
			E:Plural(#book.chapters, "%d chapter", "%d chapters"):format(#book.chapters), toneName or ""))
		-- Stay on the chapter you were reading.
		if not self.first then
			local at = UIState().at
			if not (at and self:GoToChapter(at)) then self.first = 1 end
		elseif self.keepAnchor then
			if not self:GoToChapter(self.keepAnchor) then self.first = 1 end
		end
		self.keepAnchor = nil
		self:Spread()
		self.drawMs = debugprofilestop() - started
	end

	function frame:Redraw()
		self.keepAnchor = self:Anchor()
		self:Draw()
	end

	frame:SetScript("OnShow", function(self) if self.dirty then self:Redraw() end end)
	frame.spread:SetScript("OnSizeChanged", function()
		if frame:IsShown() and frame.layout then frame:Redraw() end
	end)
	return frame
end

local function Show(frame, arg)
	frame:Redraw()
	if type(arg) == "table" then
		if arg.chapter then frame:GoToChapter(arg.chapter) end
		if arg.part then frame:GoToPart(arg.part) end
		if arg.level then frame:GoToLevel(arg.level) end
		if arg.page then frame:GoToPage(arg.page) end
	end
end

local function Refresh(frame, changed)
	if changed.adventure or changed.settings or changed.data then frame:Redraw() end
end

A:RegisterSection(KEY, {
	title = "Book",
	icon = ICON,
	desc = "Your story from level 1 to 60 as a book in chapters, in the tone you choose, with a cover for every part.",
	words = { "book", "chapters", "chronicle" },
	build = Build,
	show = Show,
	refresh = Refresh,
})
