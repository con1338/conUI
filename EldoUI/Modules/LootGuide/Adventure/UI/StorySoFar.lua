-- EldoUI My Adventure: the Story so far section and the shared
-- helpers of every story view (A.StoryView).
--
--   Hedda Stonebrew                               [Open the Book] [Show card]
--   Dwarf Priest, level 60. A journal kept since March 2.
--   -----------------------------------------------------------------------
--   [Ledger][Chronicle][Bard]
--   |▁▂▃▄▅▆▇█▇▆▅▆▇██▇▆▇▆▅▆▇▇▆▇██▇▇▆▇▆▇█▇▆▅▅▆▅▇▇█|   the level river
--   Hedda Stonebrew, a dwarf priest, began this journal at level 14 in Loch
--   Modan, on March 2. Over 5 days and 18 hours of play, she reached ...
--   [5d 18h played] [612 quests] [23 deaths] [4 dungeons] ...
--   ERAS ............................................................ 7
--   Part 1 · The road out              levels 14-17 · 4h 33m          >
--   LAST SESSION .................................................
--   TAKING IT WITH YOU ...........................................
--   [Copy as text] [Copy as Markdown] [Show card] [Put in chat]
--
-- Every sentence comes from the story engine (E.Story) with the facts
-- behind it: hover shows them ("Wording:" names the tone), a click opens
-- what the sentence is about, Shift-click puts it in the chat box. Nothing
-- here computes new numbers beyond sums of what the journal recorded.
--
-- A.StoryView (shared by Book, River, Cover, StatsSpread and Card):
--   SV.Build([over]) -> book, set        the story in the current settings,
--                                        cached per journal revision
--   SV.SoFar(book, set), SV.CardData(book, set)
--   SV.Tone(), SV.SetTone(key), SV.TONES
--   SV.Look(), SV.SetLook(key), SV.Looks()   only the looks this client can draw
--   SV.Ink(role[, look]), SV.Paint(fs, role[, look]), SV.EraColor(index[, look])
--   SV.Motion()                          story motion allowed now
--   SV.HookLinks(frame)                  sentence hover, click and Shift-click
--   SV.Linked(sentence, key, n, map)     a sentence as hyperlink text
--   SV.Navigate(set, fact)               open what a fact is about
--   SV.CanChat(), SV.ChatInsert(text)    the chat box (the player sends it)
--   SV.Copy(title, text)                 the copy box
--   SV.Reshuffle()                       new wording, same facts
--   A:SessionRecap([which]) -> recap     "last" (default) or "current"
--   A:OpenStory(key[, arg])              the Book or Story so far
local _, E = ...
local L = E.L
local Key = E.Key
local A = E.Adventure
local J = E.Journal
local LG = E.LootGuide
local K = E.AdventureKit
local T = E.tokens
local Fmt = A.Fmt

local KEY = "story"
local ICON = "Interface\\Icons\\INV_Misc_Book_11"
local CONTROLS_Y = -(K.HEADER_HEIGHT + 8)

local SV = A.StoryView or {}
A.StoryView = SV

local function Story() return E.Story end

---------------------------------------------------------------------------
-- Settings: tone, look, options for the engine
---------------------------------------------------------------------------
SV.TONES = {
	{ "ledger", Key("Ledger"), Key("The journal's own rows: short, exact, with digits.") },
	{ "chronicle", Key("Chronicle"), Key("The adventurer's log: plain past tense, places and levels first.") },
	{ "bard", Key("Bard"), Key("The tavern song: warm and vivid, never false.") },
}
local TONE_OK = { ledger = true, chronicle = true, bard = true }

SV.LOOKS = {
	{ key = "Parchment", label = "Parchment", tip = Key("Parchment pages with dark ink, like an old book."),
		ok = function() return T.paper ~= nil end },
	{ key = "EldoUI", label = "EldoUI", tip = Key("The Journal window's own dark page with the accent color.") },
	{ key = "Night", label = "Night ledger", tip = Key("A solid dark page with no ornaments, numbers first.") },
}

function SV.Tone()
	local tone = A.db and A.db.tone
	return TONE_OK[tone or ""] and tone or "chronicle"
end

function SV.Looks()
	local out = {}
	for _, look in ipairs(SV.LOOKS) do
		if not look.ok or look.ok() then out[#out + 1] = look end
	end
	return out
end

local function LookOk(key)
	for _, look in ipairs(SV.Looks()) do
		if look.key == key then return true end
	end
	return false
end

function SV.Look()
	local look = A.db and A.db.bookLook
	if look and LookOk(look) then return look end
	if LookOk("Parchment") then return "Parchment" end
	return "EldoUI"
end

local function Changed()
	SV.cache = nil
	A:MarkDirty("story")
	if LG.Fire then LG:Fire("adventure") end
end

function SV.SetTone(tone)
	if not TONE_OK[tone or ""] or not A.db then return end
	A.db.tone = tone
	Changed()
end

function SV.SetLook(look)
	if not LookOk(look) or not A.db then return end
	A.db.bookLook = look
	Changed()
end

local PRONOUN = { nameThey = "they", they = "they", name = "name", she = "she", he = "he" }

function SV.Options(over)
	local db = A.db or {}
	local opts = {
		tone = SV.Tone(), length = db.storyLength or "standard", pronoun = PRONOUN[db.pronoun or ""] or "they",
		companions = db.nameCompanions ~= false, preset = db.detail == "essentials" and "essentials"
			or db.detail == "chronicler" and "chronicler" or db.detail == "custom" and "custom" or "storyteller",
	}
	for k, v in pairs(over or {}) do opts[k] = v end
	return opts
end

-- The story input for this character, kept while the journal's revision and
-- the wording salt stay the same (E.Story caches its books on that table).
-- SV.inputOverride (tests, option previews) replaces it.
function SV.Input()
	if SV.inputOverride then return SV.inputOverride end
	local rec = J.Char and J:Char()
	if not rec then return nil end
	local rev, salt = J:Rev(), rec.salt or 0
	local cache = SV.cache
	if cache and cache.charKey == E.charKey and cache.rev == rev and cache.salt == salt then return cache.input end
	local input = J:StoryInput(E.charKey)
	SV.cache = { charKey = E.charKey, rev = rev, salt = salt, input = input, soFar = {} }
	return input
end

-- book, set (nil when the journal has nothing yet).
function SV.Build(over)
	local S = Story()
	local input = SV.Input()
	if not (S and S.Build and input) then return nil end
	local ok, book, set = pcall(S.Build, S, input, SV.Options(over))
	if not ok then
		geterrorhandler()(book)
		return nil
	end
	return book, set
end

function SV.SoFar(book, set)
	if not (book and set and Story().Export) then return {} end
	local opts = SV.Options({ tone = book.tone })
	local key = table.concat({ book.tone, opts.pronoun, tostring(opts.companions), tostring(opts.salt) }, "|")
	local store = (SV.cache and SV.cache.input == set.input and SV.cache.soFar) or {}
	if store[key] then return store[key] end
	local ok, list = pcall(Story().Export.SoFar, set, book, opts)
	if not ok then
		geterrorhandler()(list)
		list = {}
	end
	store[key] = list
	return list
end

-- The card never names companions (H6).
function SV.CardData(book, set)
	if not (book and set and Story().Export) then return nil end
	local ok, card = pcall(Story().Export.Card, set, book, { tone = book.tone, companions = false })
	if not ok then
		geterrorhandler()(card)
		return nil
	end
	return card
end

-- "Reshuffle wording": the same facts, new wording (the seed's salt).
function SV.Reshuffle()
	local rec = J.Char and J:Char()
	if not rec then return end
	rec.salt = (tonumber(rec.salt) or 0) + 1
	Changed()
end

---------------------------------------------------------------------------
-- Ink per look
---------------------------------------------------------------------------
local PANEL_INK = { head = "body", link = "secondary" }

function SV.Ink(role, look)
	look = look or SV.Look()
	role = role or "body"
	if role == "accent" then return E.media.accentColor end
	if look == "Parchment" and T.paper then
		local ink = T.paper[role]
		if ink then return ink end
		if role == "good" or role == "warn" then return T.paper.head or T.text[role] end
	end
	if role == "rule" then return T.edge.divider end
	return T.text[PANEL_INK[role] or role] or T.text.body
end

-- Paint a text in a look's ink. A kit text (K.Text) also keeps the look,
-- so it takes the ink font on Parchment (no outline, no shadow) and the
-- profile font on the other looks, and keeps it through a theme change.
function SV.Paint(fs, role, look)
	if not fs then return end
	look = look or SV.Look()
	if fs.akSize then
		fs.akLook = look
		K.Paint(fs, role or "body")
		return
	end
	local c = SV.Ink(role, look)
	fs:SetTextColor(c[1], c[2], c[3])
	if look == "Parchment" and T.paper then fs:SetShadowOffset(0, 0) end
end

function SV.Hex(role, look)
	return E:TokenHex(SV.Ink(role, look))
end

-- The seven era colors: the accent's hue turned in 50 degree steps, muted
-- (the book's eraStep and eraSaturation). Read when drawing, so they follow the
-- accent. Night ledger draws the river in one color.
local function RGBtoHSV(r, g, b)
	local max, min = math.max(r, g, b), math.min(r, g, b)
	local d = max - min
	local h = 0
	if d > 0 then
		if max == r then h = ((g - b) / d) % 6
		elseif max == g then h = (b - r) / d + 2
		else h = (r - g) / d + 4 end
		h = h / 6
	end
	return h, max > 0 and d / max or 0, max
end

local function HSVtoRGB(h, s, v)
	local i = math.floor(h * 6) % 6
	local f = h * 6 - math.floor(h * 6)
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	if i == 0 then return v, t, p end
	if i == 1 then return q, v, p end
	if i == 2 then return p, v, t end
	if i == 3 then return p, q, v end
	if i == 4 then return t, p, v end
	return v, p, q
end

SV.ERA_SATURATION = 0.55
SV.ERA_STEP = 50 / 360

function SV.EraColor(index, look)
	look = look or SV.Look()
	if look == "Night" then return T.text.secondary end
	local accent = E.media.accentColor
	local h, _, v = RGBtoHSV(accent[1], accent[2], accent[3])
	local value = math.max(v, 0.55)
	if look == "Parchment" and T.paper then value = 0.5 end
	local r, g, b = HSVtoRGB((h + ((index or 1) - 1) * SV.ERA_STEP) % 1, SV.ERA_SATURATION, value)
	return { r, g, b }
end

function SV.Motion()
	if A.db and A.db.storyMotion == "off" then return false end
	if InCombatLockdown() then return false end
	return E.db and E.db.general and E.db.general.animations and true or false
end

-- Body text size of the story (the hub's reading size).
function SV.BodySize()
	local scale = (A.db and tonumber(A.db.readingSize) or 100) / 100
	return math.floor(K.size.body * math.min(math.max(scale, 0.8), 1.4) + 0.5)
end

---------------------------------------------------------------------------
-- Sentence links: hover, click, Shift-click
---------------------------------------------------------------------------
-- "Show sources": a small dim mark after each sentence (its facts are in
-- the hover).
function SV.Linked(sentence, key, n, map, look)
	local link = Story().Render.Linked(sentence, key, n)
	map[("eldostory:%s:%d"):format(tostring(key), n)] = sentence
	if A.db and A.db.showSources then
		link = link .. " " .. SV.Hex("dim", look) .. "°|r"
	end
	return link
end

-- The facts behind one sentence, in the game tooltip.
function SV.Tooltip(owner, set, sentence)
	local tip = GameTooltip
	tip:SetOwner(owner, "ANCHOR_CURSOR")
	E.UIKit.TipTitle(tip, L["Where this comes from"])
	local lines = Story().Render.Hover(set, sentence)
	for _, line in ipairs(lines) do
		local c = T.text.body
		if line.source and line.source ~= "" then
			local s = T.text.secondary
			tip:AddDoubleLine(line.text, line.source, c[1], c[2], c[3], s[1], s[2], s[3])
		else
			local s = T.text.secondary
			tip:AddLine(line.text, s[1], s[2], s[3], true)
		end
	end
	local hint = T.text.dim
	E:TooltipHint(tip, { L["Click"], L["open what this is about"] }, { L["Shift-click"], L["put it in the chat box"] })
	tip:Show()
end

-- An item or spell link inside a sentence shows the game's own tooltip.
local function GameLinkTooltip(owner, link)
	local tip = GameTooltip
	tip:SetOwner(owner, "ANCHOR_CURSOR")
	local ok = pcall(tip.SetHyperlink, tip, link)
	if ok then tip:Show() else tip:Hide() end
end

-- Opens what a fact is about (navigation only). Derived facts open their
-- first input that can show something.
function SV.Navigate(set, fact, depth)
	if not fact then return false end
	depth = depth or 0
	local id = fact.id or ""
	local v = fact.v or {}
	local seq = id:match("^ev:(%d+)$")
	if seq and J:Open(J:Address("moment", tonumber(seq))) then return true end
	if v.instance and (fact.kind == "dungeon" or fact.kind == "raid" or fact.kind == "run" or fact.kind == "runs"
		or fact.kind == "boss" or fact.kind == "raidboss" or fact.kind == "bossagain") then
		if J:Open(J:Address("instance", v.instance)) then return true end
	end
	local quest = id:match("^q:(%d+)")
	if quest and J:Open(J:Address("quest", tonumber(quest))) then return true end
	local zone = id:match("^zone:(.+)$")
	if zone and A:SectionShown("places") and J:Open(J:Address("place", zone)) then return true end
	local fellow = id:match("^fe:([^:]+)")
	if fellow and A:SectionShown("fellowship") and J:Open(J:Address("fellow", fellow)) then return true end
	if depth < 3 then
		for _, input in ipairs(fact.from or {}) do
			if SV.Navigate(set, set.byId[input], depth + 1) then return true end
		end
	end
	if depth == 0 and A:SectionShown("journey") then return A:OpenSection("journey") end
	return false
end

function SV.CanChat()
	local util = rawget(_G, "ChatFrameUtil")
	return type(util) == "table" and type(util.OpenChat) == "function"
end

-- Into the chat box: added to an open edit box, or a new one opens with it.
-- The player reads it and presses Enter; nothing is sent from here.
function SV.ChatInsert(text)
	if type(text) ~= "string" or text == "" or not SV.CanChat() then return false end
	local util = ChatFrameUtil
	if type(util.InsertLink) == "function" then
		local ok, done = pcall(util.InsertLink, text)
		if ok and done then return true end
	end
	local ok = pcall(util.OpenChat, text)
	return ok
end

function SV.Copy(title, text)
	E:ShowCopyBox(title, L["Press Ctrl+C to copy. Nothing is sent anywhere: paste it where you like."], text)
end

-- frame.storyMap[linkID] = sentence, frame.storySet = set (filled when drawing).
function SV.HookLinks(frame)
	if frame.storyLinks then return end
	frame.storyLinks = true
	local function Enable()
		frame:SetHyperlinksEnabled(true)
	end
	if InCombatLockdown() then E:RunOutOfCombat(Enable) else Enable() end
	frame:SetScript("OnHyperlinkEnter", function(self, link)
		local sentence = self.storyMap and self.storyMap[link]
		if sentence and self.storySet then
			SV.Tooltip(self, self.storySet, sentence)
		elseif type(link) == "string" and not link:find("^eldostory:") then
			GameLinkTooltip(self, link)
		end
	end)
	frame:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
	frame:SetScript("OnHyperlinkClick", function(self, link, text, button)
		local sentence = self.storyMap and self.storyMap[link]
		if not sentence then
			-- An item link: the game's own handling (Shift-click links it).
			-- E:FollowLink: SetItemRef, but map links open the map the clean way (Core/ChatLinks.lua).
			if type(link) == "string" and not link:find("^eldostory:") and SetItemRef then
				pcall(E.FollowLink, E, link, text, button, self)
			end
			return
		end
		if IsShiftKeyDown() then
			SV.ChatInsert(Story().Export.Plain(sentence.text))
		elseif self.storySet then
			SV.Navigate(self.storySet, self.storySet.byId[sentence.lead])
		end
	end)
end

---------------------------------------------------------------------------
-- Opening the views
---------------------------------------------------------------------------
function A:OpenStory(key, arg)
	if not self:SectionShown(key) then return false end
	return self:OpenSection(key, arg)
end

---------------------------------------------------------------------------
-- Session recap: what the last session (or this one) holds.
-- recap = { title, line, best, seconds, rows, level = { a, b } } or nil
---------------------------------------------------------------------------
local function CountBy(rows)
	local counts, keep, best = {}, 0, nil
	for _, row in ipairs(rows) do
		counts[row.kind] = (counts[row.kind] or 0) + 1
		if J:IsKeepsake(row) then
			keep = keep + 1
			if not best or (J:Worth(row) or 0) >= (J:Worth(best) or 0) then best = row end
		end
	end
	return counts, keep, best
end

function A:SessionRecap(which)
	local rec = J.Char and J:Char()
	if not rec then return nil end
	local from, to
	local sessions = rec.sessions or {}
	if which == "current" then
		local last = sessions[#sessions]
		from, to = last and tonumber(last.logout) or tonumber(rec.started) or 0, time()
	else
		local last = sessions[#sessions]
		if not last then return nil end
		from, to = tonumber(last.login), tonumber(last.logout)
	end
	if not (from and to) or to <= from then return nil end
	local seconds = to - from
	local rows = J:Rows(nil, from, to)
	local quests = 0
	for _, q in ipairs(rec.quests or {}) do
		if type(q) == "table" and type(q.t) == "number" and q.t >= from and q.t <= to then quests = quests + 1 end
	end
	local counts, keep, best = CountBy(rows)
	local levels = {}
	for _, row in ipairs(rows) do
		if row.kind == "level" and type(row.level) == "number" then levels[#levels + 1] = row.level end
	end
	if #rows == 0 and quests == 0 then return nil end
	local bits = { Fmt.Span(seconds) }
	if #levels > 0 then
		local a, b = levels[1] - 1, levels[#levels]
		bits[#bits + 1] = (L["level %d to %d"]):format(a, b)
	end
	if quests > 0 then bits[#bits + 1] = E:Plural(quests, "%d quest", "%d quests"):format(quests) end
	if (counts.dungeon or 0) + (counts.run or 0) > 0 then
		local n = (counts.dungeon or 0) + (counts.run or 0)
		bits[#bits + 1] = E:Plural(n, "%d dungeon run", "%d dungeon runs"):format(n)
	end
	if keep > 0 then bits[#bits + 1] = E:Plural(keep, "%d keepsake", "%d keepsakes"):format(keep) end
	if (counts.death or 0) > 0 then bits[#bits + 1] = E:Plural(counts.death, "%d death", "%d deaths"):format(counts.death) end
	local recap = { which = which or "last", from = from, to = to, seconds = seconds, line = table.concat(bits, " · "),
		rows = rows, quests = quests, keepsakes = keep }
	if best then recap.best = (A:LineText(best)) end
	recap.title = which == "current" and L["This session"] or L["Last session"]
	return recap
end

-- Once per session, a little after login: the last session in one card
-- (option "Session recap"). Only when that session had something in it.
local recapShown = false

local function ShowRecap()
	if recapShown or not (A.db and A.db.sessionRecap) or not A:Running() then return end
	if InCombatLockdown() then
		E:RunOutOfCombat(ShowRecap)
		return
	end
	local recap = A:SessionRecap("last")
	if not recap then return end
	recapShown = true
	local text = recap.line .. (recap.best and ("\n" .. (L["Best moment: %s"]):format(recap.best)) or "")
	local actions = {}
	if A:SectionShown(KEY) then
		actions[1] = { label = L["Story so far"], func = function() A:OpenStory(KEY) end }
	end
	local data = { kind = "recap", key = "recap:" .. tostring(recap.to), title = L["Last time on your journey"], text = text,
		icon = ICON, actions = actions }
	if A.Moments and type(A.Moments.Push) == "function" then
		A.Moments:Push(data)
	else
		A:PushAlert(data)
	end
end
SV.ShowRecap = ShowRecap

function SV.ResetRecap() recapShown = false end

A:AddPart("storyrecap", {
	order = 95,
	start = function()
		if not recapShown then C_Timer.After(12, ShowRecap) end
	end,
})

---------------------------------------------------------------------------
-- Story so far: rows of the journal list
---------------------------------------------------------------------------
local INSET = K.CARD_INSET

-- Prose with linked sentences.
K.ROWS.story_prose = {
	height = function(item, width)
		local size = SV.BodySize()
		return 8 + E.UIKit.TextHeight(item.plain or item.text, math.max(width - 2 * INSET, 40), size, { spacing = 3 }) + 10
	end,
	create = function(row)
		row:EnableMouse(true)
		row.text = K.Text(row, SV.BodySize(), "LEFT", "body")
		row.text:SetWordWrap(true)
		row.text:SetSpacing(3)
		SV.HookLinks(row)
	end,
	update = function(row, item)
		local size = SV.BodySize()
		if row.text.akSize ~= size or row.text.akPaper ~= K.OnPaperText(row.text) then
			K.InkFont(row.text, size)
		end
		row.text:ClearAllPoints()
		row.text:SetPoint("TOPLEFT", INSET, -8)
		row.text:SetPoint("TOPRIGHT", -INSET, -8)
		row.text:SetText(item.text or "")
		K.Paint(row.text, item.role or "body")
		row.storyMap, row.storySet = item.map, item.set
	end,
}

-- The level river.
K.ROWS.story_river = {
	height = function(item) return item.height or 140 end,
	create = function(row)
		row:EnableMouse(false)
	end,
	update = function(row, item)
		if not row.river and A.River then
			row.river = A.River.Create(row, { height = (item.height or 140) - 8 })
			row.river:SetPoint("TOPLEFT", 0, -4)
			row.river:SetPoint("TOPRIGHT", 0, -4)
		end
		if row.river then row.river:SetBook(item.book, item.set, { motion = item.motion }) end
	end,
}

-- Stat tiles: a value in the header font and a label, a tooltip with the source.
local TILE_W, TILE_H, TILE_GAP = 128, 46, 8

local function TileColumns(width)
	return math.max(1, math.floor((width + TILE_GAP) / (TILE_W + TILE_GAP)))
end

K.ROWS.story_tiles = {
	height = function(item, width)
		local columns = TileColumns(width)
		local rows = math.ceil(#(item.tiles or {}) / columns)
		return rows * (TILE_H + TILE_GAP) + 4
	end,
	create = function(row)
		row:EnableMouse(false)
		row.tiles = {}
	end,
	update = function(row, item, width)
		width = width or row:GetWidth() or 600
		local columns = TileColumns(width)
		local tileW = math.floor((width - (columns - 1) * TILE_GAP) / columns)
		local data = item.tiles or {}
		for index = 1, math.max(#row.tiles, #data) do
			local tile = row.tiles[index]
			local entry = data[index]
			if entry and not tile then
				tile = K.Card(row, { solid = true })
				tile.value = K.Text(tile, 16, "LEFT", "head", true)
				tile.value:SetPoint("TOPLEFT", 10, -7)
				tile.value:SetPoint("TOPRIGHT", -8, -7)
				tile.value:SetWordWrap(false)
				tile.label = K.Text(tile, K.size.small, "LEFT", "secondary")
				tile.label:SetPoint("TOPLEFT", tile.value, "BOTTOMLEFT", 0, -3)
				tile.label:SetPoint("TOPRIGHT", tile.value, "BOTTOMRIGHT", 0, -3)
				tile.label:SetWordWrap(false)
				row.tiles[index] = tile
			end
			if tile then
				tile:SetShown(entry ~= nil)
				if entry then
					local col = (index - 1) % columns
					local line = math.floor((index - 1) / columns)
					tile:ClearAllPoints()
					tile:SetPoint("TOPLEFT", row, "TOPLEFT", col * (tileW + TILE_GAP), -(line * (TILE_H + TILE_GAP)))
					tile:SetSize(tileW, TILE_H)
					tile.value:SetText(entry.value or "")
					tile.label:SetText(entry.label or "")
					tile:EnableMouse(entry.tip ~= nil)
					LG.Kit.Tooltip(tile, entry.tip and entry.label, entry.tip)
				end
			end
		end
	end,
}

-- A row of buttons ("Taking it with you").
K.ROWS.story_actions = {
	height = function() return T.height.button + 8 end,
	create = function(row)
		row:EnableMouse(false)
		row.buttons = {}
	end,
	update = function(row, item)
		local x = 0
		local list = item.actions or {}
		for index = 1, math.max(#row.buttons, #list) do
			local data = list[index]
			local button = row.buttons[index]
			if data and not button then
				button = LG.Kit.Button(row, "", 100, T.height.button)
				row.buttons[index] = button
			end
			if button then
				button:SetShown(data ~= nil)
				if data then
					button:SetText(data[1])
					E.UIKit.FitButton(button, 90)
					button:SetScript("OnClick", data[2])
					LG.Kit.Tooltip(button, data[1], data[3])
					button:ClearAllPoints()
					button:SetPoint("LEFT", row, "LEFT", x, 0)
					x = x + button:GetWidth() + 8
				end
			end
		end
	end,
}

---------------------------------------------------------------------------
-- Story so far: data
---------------------------------------------------------------------------
local function Sum(set, field, a, b)
	local total, any = 0, false
	for n = a or 1, b or 60 do
		local rec = set.levels[n]
		local value = rec and tonumber(rec[field])
		if value then
			total = total + value
			any = true
		end
	end
	return any and total or nil
end
SV.Sum = Sum

local function Count(set, kinds)
	local n = 0
	for _, kind in ipairs(kinds) do n = n + #set:Kind(kind) end
	return n
end

local function Tiles(set)
	local game = set.input.game or {}
	local Gr = Story().Grammar
	local tiles = {}
	local function Add(value, label, tip)
		if value ~= nil then tiles[#tiles + 1] = { value = value, label = label, tip = tip } end
	end
	if game.played then Add(Gr.Duration(game.played, "ledger"), L["played"], L["Your /played time, from the game."]) end
	if game.questsDone then
		Add(BreakUpLargeNumbers(game.questsDone), L["quests completed"], L["The game's own count of quests you completed."])
	end
	local kills = Sum(set, "kills", set.startedLevel, set.level)
	if kills then Add(BreakUpLargeNumbers(kills), L["kills recorded"], L["Kills the journal counted from the game's statistic and its experience lines."]) end
	if game.deaths then Add(BreakUpLargeNumbers(game.deaths), L["deaths"], L["The game's own count of your deaths."]) end
	local dungeons = Count(set, { "dungeon" })
	if dungeons > 0 then Add(dungeons, L["dungeons"], L["Different dungeons you entered while the journal was kept."]) end
	local runs = Count(set, { "dungeon", "run", "raid" })
	if runs > dungeons then Add(runs, L["dungeon runs"], L["Every run the Instances module recorded."]) end
	local bosses = 0
	for _, fact in ipairs(set:Kind("raidboss")) do if fact.flags.first then bosses = bosses + 1 end end
	for _, fact in ipairs(set:Kind("boss")) do if fact.flags.first then bosses = bosses + 1 end end
	if bosses > 0 then Add(bosses, L["first boss kills"], L["Bosses you beat for the first time while the journal was kept."]) end
	local met = #set:Kind("met")
	if met > 0 then Add(met, L["companions"], L["People you grouped with long enough for the journal to remember."]) end
	local totals = set.byId.totals
	if totals and (totals.v.earned or 0) > 0 then
		Add(Gr.Money(totals.v.earned, "ledger"):match("^(%S+)") or "", L["gold earned"], L["Money you looted, earned from quests, and sold for since the journal began. Spending is not counted."])
	end
	local flights = #set:Kind("flight")
	if flights > 0 then Add(flights, L["flight paths"], L["Flight paths you learned while the journal was kept."]) end
	return tiles
end
SV.Tiles = Tiles

local function EraRows(book, set)
	local rows = {}
	local Gr = Story().Grammar
	for _, part in ipairs(book.parts) do
		local played = set.byId["p:era:" .. tostring(part.index)]
		local title = part.number and (L["Part %d · %s"]):format(part.number, part.title or "") or (part.title or "")
		local sub = Gr.Levels(part.a, part.b)
		if played and played.v.played then sub = sub .. " · " .. Gr.Duration(played.v.played, "ledger") end
		rows[#rows + 1] = { part = part, title = title, sub = sub, chapters = #part.chapters }
	end
	return rows
end
SV.EraRows = EraRows

---------------------------------------------------------------------------
-- Story so far: the section
---------------------------------------------------------------------------
local function CopyText(book, set)
	local soFar = SV.SoFar(book, set)
	SV.Copy(L["Your story as text"], Story().Export.BookText(book, set, { soFar = soFar }))
end

local function CopyMarkdown(book, set)
	local soFar = SV.SoFar(book, set)
	SV.Copy(L["Your story as Markdown"], Story().Export.BookMarkdown(book, set, { soFar = soFar }))
end
SV.CopyText, SV.CopyMarkdown = CopyText, CopyMarkdown

local function HeaderSentence(set)
	local Ex = Story().Export
	local bits = {}
	local rc = Ex.RaceClass(set.me)
	local first = rc and (L["%s, level %d."]):format(rc, set.level) or (L["Level %d."]):format(set.level)
	bits[#bits + 1] = first
	if set.input.started then bits[#bits + 1] = (L["A journal kept since %s."]):format(Fmt.Long(set.input.started)) end
	return table.concat(bits, " ")
end

local function Build(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetAllPoints()
	frame.header = K.Header(frame)
	frame.header:SetPoint("TOPLEFT")
	frame.header:SetPoint("TOPRIGHT")

	frame.tone = K.Switch(frame, SV.TONES, SV.Tone(), function(tone) SV.SetTone(tone) end)
	frame.tone:SetPoint("TOPLEFT", 0, CONTROLS_Y)

	frame.list = K.CreateJournalList(frame, { empty = { L["The first page is still blank"], "", ICON } })
	frame.list:SetPoint("TOPLEFT", 0, CONTROLS_Y - 28)
	frame.list:SetPoint("BOTTOMRIGHT")

	function frame:Draw(keepScroll)
		if not self:IsShown() then
			self.dirty = true
			return
		end
		self.dirty = false
		local started = debugprofilestop()
		local book, set = SV.Build()
		self.book, self.set = book, set
		self.tone:SetActive(SV.Tone())
		local actions = {}
		if A:SectionShown("book") then
			actions[#actions + 1] = { L["Open the Book"], function() A:OpenStory("book") end, L["Your story in chapters, page by page."] }
		end
		if book and A.Card then
			actions[#actions + 1] = { L["Show card"], function() A.Card:Show() end,
				L["Your character card on a dimmed screen, ready for your own screenshot key."] }
		end
		self.header:SetActions(actions)
		if not (book and set) or book.empty then
			self.header:SetTitle(L["Story so far"])
			self.header:SetSentence(L["Your story starts with the first thing the journal writes down."])
			self.list:SetEmpty(L["The first page is still blank"], Story() and Story().Render.emptyText or "", ICON,
				A:SectionShown("journey") and { { L["Open the Journey"], function() A:OpenSection("journey") end } } or nil)
			self.items = {}
			self.list:SetData({}, keepScroll)
			self.buildMs = debugprofilestop() - started
			return
		end
		self.header:SetTitle(set.me.name or L["Story so far"])
		self.header:SetSentence(HeaderSentence(set))
		local items = {}
		local map = {}
		self.map = map
		-- The river.
		if A.River then
			items[#items + 1] = { kind = "story_river", book = book, set = set, height = 140, motion = not self.riverShown }
			self.riverShown = true
		end
		-- The prose.
		local soFar = SV.SoFar(book, set)
		local parts, plain = {}, {}
		local lineEach = book.tone == "ledger"
		for n, sentence in ipairs(soFar) do
			parts[#parts + 1] = SV.Linked(sentence, "sofar", n, map, "EldoUI")
			plain[#plain + 1] = sentence.text
		end
		self.soFar = soFar
		if #parts > 0 then
			local sep = lineEach and "\n" or " "
			items[#items + 1] = { kind = "story_prose", text = table.concat(parts, sep), plain = table.concat(plain, sep), map = map, set = set }
		end
		-- Tiles.
		local tiles = Tiles(set)
		self.tiles = tiles
		if #tiles > 0 then
			items[#items + 1] = { kind = "space", height = 6 }
			items[#items + 1] = { kind = "story_tiles", tiles = tiles }
		end
		-- Eras.
		local eras = EraRows(book, set)
		self.eras = eras
		if #eras > 0 then
			local open = K.FoldOpen("story:eras", true)
			items[#items + 1] = { kind = "space", height = 6 }
			items[#items + 1] = { kind = "fold", key = "story:eras", label = L["Eras"], note = tostring(#eras), open = open,
				onToggle = function() self:Draw(true) end }
			if open then
				for index, era in ipairs(eras) do
					items[#items + 1] = { kind = "ledger", icon = ICON, title = era.title, sub = era.sub,
						time = E:Plural(era.chapters, "%d chapter", "%d chapters"):format(era.chapters),
						position = (#eras == 1 and "only") or (index == 1 and "first") or (index == #eras and "last") or "middle",
						tip = L["Opens this part in the Book."],
						onClick = A:SectionShown("book") and function() A:OpenStory("book", { part = era.part.key }) end or nil }
				end
			end
		end
		-- The last session.
		local recap = A:SessionRecap("last")
		self.recap = recap
		if recap then
			items[#items + 1] = { kind = "space", height = 6 }
			items[#items + 1] = { kind = "fold", key = "story:session", label = recap.title, note = Fmt.When(recap.to),
				open = K.FoldOpen("story:session", true), onToggle = function() self:Draw(true) end }
			if K.FoldOpen("story:session", true) then
				items[#items + 1] = { kind = "ledger", icon = ICON, title = recap.line,
					sub = recap.best and (L["Best moment: %s"]):format(recap.best) or nil, time = Fmt.Clock(recap.from), position = "only" }
			end
		end
		-- Taking it with you.
		items[#items + 1] = { kind = "space", height = 6 }
		items[#items + 1] = { kind = "fold", key = "story:share", label = L["Taking it with you"], open = K.FoldOpen("story:share", true),
			onToggle = function() self:Draw(true) end }
		if K.FoldOpen("story:share", true) then
			local share = {
				{ L["Copy as text"], function() CopyText(self.book, self.set) end, L["The whole story in this tone as plain text, in a copy box."] },
				{ L["Copy as Markdown"], function() CopyMarkdown(self.book, self.set) end,
					L["The whole story with headings, for a website, a forum, or Discord."] },
			}
			if A.Card then
				share[#share + 1] = { L["Copy the card"], function() A.Card:CopyText() end,
					L["Your character card as a few lines of text. Companion names are left out."] }
			end
			if SV.CanChat() and A.Card then
				share[#share + 1] = { L["Put in chat"], function() A.Card:ToChat() end,
					L["Puts one line about your character in the chat box. You read it and press Enter to send it."] }
			end
			items[#items + 1] = { kind = "story_actions", actions = share }
		end
		self.items = items
		self.list:SetData(items, keepScroll)
		self.buildMs = debugprofilestop() - started
	end

	frame:SetScript("OnShow", function(self) if self.dirty then self:Draw(true) end end)
	return frame
end

local function Show(frame)
	frame:Draw(true)
end

local function Refresh(frame, changed)
	if changed.adventure or changed.settings or changed.data then frame:Draw(true) end
end

A:RegisterSection(KEY, {
	title = "Story so far",
	icon = ICON,
	desc = "Your character's story in a few lines, with the level river, your numbers, the eras, and ways to share it.",
	words = { "story", "summary", "so far", "card" },
	build = Build,
	show = Show,
	refresh = Refresh,
})
