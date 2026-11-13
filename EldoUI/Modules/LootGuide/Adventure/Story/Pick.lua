-- Deterministic wording choice and the no-repeat rules.
--   seed  hash(charKey | chapterKey | beatId | tone | salt), a 31-bit string
--         hash with no bit library: h = (h * 33 + byte) % 2147483647
--   V1    a variant is not reused within the last T.variantWindow uses of its
--         beat (book-wide); when every variant is blocked the least recently
--         used one wins
--   V2    two sentences in a row never start with the same T.stemWords words
--   V3    no rendered sentence appears twice in a book
-- V4 (name rhythm) and V5 (paragraph shapes) live in Render, V6 (lead
-- rotation) in Plan. The same journal therefore always reads the same,
-- until the player asks for new wording (salt) or a new fact arrives.
local _, E = ...

E.Story = E.Story or {}
local S = E.Story
local P = {}
S.Pick = P

function P.Hash(text)
	local h = 5381
	for i = 1, #text do
		h = (h * 33 + text:byte(i)) % 2147483647
	end
	return h
end

function P.Seed(charKey, chapterKey, beatId, tone, salt)
	return P.Hash(table.concat({ tostring(charKey), tostring(chapterKey), tostring(beatId), tostring(tone), tostring(salt or 0) }, "|"))
end

-- One state per rendered book.
function P.New()
	return { uses = {}, clock = 0, seen = {} }
end

-- Candidate order for a beat: start at the seed, walk round. Variants used
-- inside the window go to the back, least recently used first.
function P.Order(state, key, count, seed)
	local window = S.Tuning.variantWindow
	local uses = state.uses[key] or {}
	local recent = {}
	for i = #uses, math.max(1, #uses - window + 1), -1 do recent[uses[i]] = true end
	local fresh, blocked = {}, {}
	local start = seed % count
	for step = 0, count - 1 do
		local index = (start + step) % count + 1
		if recent[index] then blocked[#blocked + 1] = index else fresh[#fresh + 1] = index end
	end
	local last = {}
	for i, index in ipairs(uses) do last[index] = i end
	table.sort(blocked, function(a, b) return (last[a] or 0) < (last[b] or 0) end)
	for _, index in ipairs(blocked) do fresh[#fresh + 1] = index end
	return fresh
end

function P.Use(state, key, index)
	local uses = state.uses[key]
	if not uses then
		uses = {}
		state.uses[key] = uses
	end
	uses[#uses + 1] = index
end

function P.Seen(state, text) return state.seen[text] == true end
function P.Remember(state, text) state.seen[text] = true end

function P.Stem(text)
	return S.Grammar.FirstWords(text, S.Tuning.stemWords)
end
