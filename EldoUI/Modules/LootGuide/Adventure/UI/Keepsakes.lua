-- EldoUI My Adventure: keepsakes. The Keepsakes section of the hub,
-- keeping a moment by hand, and a note on a keepsake.
--
--   Keepsakes                                                [Open the Journey]
--   23 keepsakes. 7 of 11 firsts so far.
--   -----------------------------------------------------------------------
--   [All][Victories][Finds][Standings][Pinned][Other]  [ Search keepsakes  ]
--   FIRSTS  7 of 11 ---------------------------------------------------- v
--   [ic]      [ic]      [ic]      [ic]      [..]      [..]
--   Dungeon   Boss      Mount     Epic      Raid      Rare
--   Oct 3     Oct 3     Oct 9     Oct 9     Not yet   Not yet
--   VICTORIES  4 ------------------------------------------------------- v
--   +== The Deadmines ================================== Oct 3 ==+
--   | [boss] Edwin VanCleef   First kill                          |
--   FINDS  6 ----------------------------------------------------------- v
--
-- The section is the gallery of what the journal already marks as a
-- keepsake (E.Journal:IsKeepsake: first kills, epic finds, Honored and up,
-- mounts, titles, attunements, ...) and the moments you kept by hand,
-- grouped by kind, newest first. The Firsts strip shows the first time
-- each of eleven things happened, with its date; the ones still waiting
-- are dim and lead to Next trips when that page is there. Every medal and
-- card is a recorded fact; nothing is guessed.
--
-- Shared (the Journey's row menu, the item menu, plugins):
--   A:CanKeep(row)            the row can be kept or unkept by hand (a
--                             journal row the rules do not already keep)
--   J:SetKeep(seq, on)        keep or unkeep one of this character's rows
--   A:KeepNote(row)           your note on a keepsake (or nil)
--   J:SetKeepNote(key, text)  set or clear it (key = A.KeepKey(row));
--                             stored in EldoUIDB.journal[char].keepNotes
--   A:EditKeepNote(row)       asks for the note (one line)
--   A:Firsts()                { { key, label, row = first row or nil }, ... }
--
-- Portions adapted from Forever Journal by Ugge Zen, MIT License (see
-- THIRD_PARTY_NOTICES.md): the keepsake objects and their award rules,
-- grouped as cards (pinned notes, standings, victories and finds).
--
-- MIT License
--
-- Copyright (c) 2026 Ugge Zen
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
local _, E = ...
local L = E.L
local Key = E.Key
local A = E.Adventure
local J = E.Journal
local S = A.Store
local LG = E.LootGuide
local K = E.AdventureKit
local T = E.tokens
local Fmt = A.Fmt

local KEY = "keepsakes"
local NOTE_MAX = 140
local CONTROLS_Y = -(K.HEADER_HEIGHT + 8)
local MEDAL_WIDTH, MEDAL_HEIGHT, MEDAL_GAP = 84, 72, 8
local MEDAL_ART = 36

---------------------------------------------------------------------------
-- Keeping by hand
---------------------------------------------------------------------------
-- The kind's own rule says it is a keepsake (first kill, epic, ...).
local function RuleKeepsake(row)
	local def = J:Kind(row.kind)
	if not (def and type(def.keepsake) == "function") then return false end
	local ok, yes = pcall(def.keepsake, row)
	return ok and yes and true or false
end

function A:CanKeep(row)
	if type(row) ~= "table" or row.src ~= "journal" or not tonumber(row.seq) then return false end
	if self.db and self.db.keepsakes == false then return false end
	if row.kind == "note" or row.kind == "goalset" or row.kind == "rollup" then return false end
	return not RuleKeepsake(row)
end

function J:SetKeep(seq, on)
	local rec = S.Own()
	seq = tonumber(seq)
	if not (rec and seq) then return false end
	local row, position = self:Row(nil, seq)
	if not row then return false end
	on = on and true or nil
	if row.keep == on then return true end
	row.keep = on
	rec.events[position] = S.Pack(rec, row)
	-- What the journal keeps first when it is full changes with it.
	rec.trimSkip = nil
	S.Bump(rec)
	A:MarkDirty("journal")
	return true
end

---------------------------------------------------------------------------
-- Notes on keepsakes
---------------------------------------------------------------------------
local function Notes(create)
	local rec = create and S.Own() or J:Char()
	if not rec then return nil end
	if type(rec.keepNotes) ~= "table" then
		if not create then return nil end
		rec.keepNotes = {}
	end
	return rec.keepNotes, rec
end

function A:KeepNote(row)
	local key = type(row) == "table" and A.KeepKey and A.KeepKey(row)
	local notes = key and Notes(false)
	local text = notes and notes[key]
	if type(text) == "string" and text ~= "" then return text end
	return nil
end

function J:SetKeepNote(key, text)
	if type(key) ~= "string" or key == "" then return false end
	if E:IsSecret(text) then return false end
	text = type(text) == "string" and strtrim(text) or ""
	local notes, rec = Notes(text ~= "")
	if not notes then return text == "" end
	if text == "" then
		notes[key] = nil
	else
		notes[key] = E:Utf8Sub(text, NOTE_MAX)
	end
	S.Bump(rec)
	A:MarkDirty("journal")
	return true
end

function A:EditKeepNote(row)
	local key = type(row) == "table" and A.KeepKey and A.KeepKey(row)
	if not key or not LG.AskText then return nil end
	local title = A:LineText(row)
	return LG:AskText((L["Your note on \"%s\" (up to %d letters; empty removes it):"]):format(title, NOTE_MAX), -- no-plural: a fixed count
		self:KeepNote(row) or "", NOTE_MAX, function(text) J:SetKeepNote(key, text) end)
end

---------------------------------------------------------------------------
-- Kinds of keepsake
---------------------------------------------------------------------------
local VICTORY = { boss = true, raidboss = true }
local FIND = { loot = true, gear = true, wish = true }

local function PinnedNote(row)
	if row.kind ~= "note" then return false end
	local _, pinnedIDs = A:PinnedNotes()
	if pinnedIDs[row.note] then return true end
	local rec = J:Char()
	for _, note in ipairs(rec and rec.notes or {}) do
		if type(note) == "table" and note.id == row.note then return note.pinned and true or false end
	end
	return false
end

-- "pinned", "victory", "find", "standing", "other" or nil (no keepsake).
local function Category(row)
	if PinnedNote(row) then return "pinned" end
	if not J:IsKeepsake(row) then return nil end
	if row.keep and not RuleKeepsake(row) then return "pinned" end
	if VICTORY[row.kind] then return "victory" end
	if FIND[row.kind] then return "find" end
	if row.kind == "rep" then return "standing" end
	return "other"
end
A.KeepsakeCategory = Category

local CATEGORIES = {
	{ "pinned", Key("Pinned"), Key("Moments you kept by hand and your pinned notes.") },
	{ "victory", Key("Victories"), Key("First kills, one card per run.") },
	{ "find", Key("Finds"), Key("Epic finds and the wishlist items you got.") },
	{ "standing", Key("Standings"), Key("Factions that count you as Honored or better.") },
	{ "other", Key("Other"), Key("Mounts, titles, attunements, mastered professions, and first raids.") },
}
local CATEGORY_TITLE = {}
for _, entry in ipairs(CATEGORIES) do CATEGORY_TITLE[entry[1]] = entry[2] end

local SWITCH = { { "all", Key("All"), Key("Every keepsake, grouped by kind.") } }
for _, entry in ipairs(CATEGORIES) do SWITCH[#SWITCH + 1] = entry end

-- Every keepsake, newest first, with its category: cached per timeline.
local cache = { rows = nil, list = nil, counts = nil, setting = nil }

local function All()
	local rows = J:Timeline()
	local setting = not (A.db and A.db.keepsakes == false)
	local rec = J:Char()
	local notesRev = rec and rec.rev
	if cache.rows == rows and cache.setting == setting and cache.rev == notesRev then return cache.list, cache.counts end
	local list, counts = {}, { all = 0 }
	for index = #rows, 1, -1 do
		local row = rows[index]
		local category = Category(row)
		if category then
			list[#list + 1] = { row = row, category = category }
			counts[category] = (counts[category] or 0) + 1
			counts.all = counts.all + 1
		end
	end
	cache.rows, cache.list, cache.counts, cache.setting, cache.rev = rows, list, counts, setting, notesRev
	return list, counts
end

function A:KeepsakeCount()
	local _, counts = All()
	return counts.all
end

---------------------------------------------------------------------------
-- Firsts: the first time each of these happened (recorded rows only)
---------------------------------------------------------------------------
local FIRSTS = {
	{ "dungeon", Key("Dungeon"), J.ICON and J.ICON.dungeon, Key("The first time you entered a dungeon."),
		function(row) return row.kind == "dungeon" end },
	{ "boss", Key("Boss"), J.ICON and J.ICON.boss, Key("Your first boss kill."),
		function(row) return (row.kind == "boss" and row.first) or row.kind == "raidboss" end },
	{ "mount", Key("Mount"), J.ICON and J.ICON.mount, Key("Your first mount."),
		function(row) return row.kind == "mount" end },
	{ "epic", Key("Epic"), J.ICON and J.ICON.loot, Key("Your first epic find."),
		function(row) return row.kind == "loot" and (tonumber(row.quality) or 0) >= 4 end },
	{ "flight", Key("Flight path"), J.ICON and J.ICON.flight, Key("The first flight path you learned."),
		function(row) return row.kind == "flight" end },
	{ "death", Key("Death"), J.ICON and J.ICON.death, Key("The first time you died. It happens to everyone."),
		function(row) return row.kind == "death" end },
	{ "honored", Key("Honored"), J.ICON and J.ICON.rep, Key("The first faction that counts you as Honored."),
		function(row) return row.kind == "rep" and (tonumber(row.standing) or 0) >= 6 end },
	{ "raid", Key("Raid"), J.ICON and J.ICON.dungeon, Key("The first time you entered a raid."),
		function(row) return row.kind == "raid" end },
	{ "attune", Key("Attunement"), J.ICON and J.ICON.attune, Key("Your first attunement step."),
		function(row) return row.kind == "attunestep" or row.kind == "attuned" end },
	{ "groupquest", Key("Group quest"), J.ICON and J.ICON.quest, Key("The first quest you handed in with a group."),
		function(row) return row.kind == "groupquest" end },
	{ "rare", Key("Rare"), J.ICON and J.ICON.rare, Key("The first rare you saw."),
		function(row) return row.kind == "rare" end },
}

function A:Firsts()
	local out, left = {}, #FIRSTS
	for index, def in ipairs(FIRSTS) do out[index] = { key = def[1], label = L[def[2]], icon = def[3], tip = L[def[4]] } end
	for _, row in ipairs(J:Timeline()) do
		if left == 0 then break end
		for index, def in ipairs(FIRSTS) do
			if not out[index].row then
				local ok, yes = pcall(def[5], row)
				if ok and yes then
					out[index].row = row
					left = left - 1
				end
			end
		end
	end
	return out
end

-- Where a medal or card leads: the moment in the Journey, else its link.
local function OpenRow(row)
	if row.src == "journal" and row.seq and A:SectionShown("journey") then
		return A:OpenSection("journey", { seq = row.seq })
	end
	local address = J:LinkFor(row)
	return address and J:Open(address) or false
end

local function NextShown()
	return A:SectionShown("next")
end

---------------------------------------------------------------------------
-- The Firsts strip
---------------------------------------------------------------------------
local function CreateMedal(strip)
	local medal = CreateFrame("Button", nil, strip)
	medal:SetSize(MEDAL_WIDTH, MEDAL_HEIGHT)
	medal.art = K.Art(medal, MEDAL_ART)
	medal.art:SetPoint("TOP", 0, -2)
	medal.label = K.Text(medal, K.size.small, "CENTER", "body")
	medal.label:SetPoint("TOP", medal.art, "BOTTOM", 0, -4)
	medal.label:SetWidth(MEDAL_WIDTH)
	medal.label:SetWordWrap(false)
	medal.date = K.Text(medal, K.size.caption, "CENTER", "secondary")
	medal.date:SetPoint("TOP", medal.label, "BOTTOM", 0, -2)
	medal.date:SetWidth(MEDAL_WIDTH)
	medal.date:SetWordWrap(false)
	E:SkinHoverPress(medal)
	return medal
end

local function SetMedal(medal, first)
	medal.first = first
	local row = first.row
	medal.art.icon:SetTexture(first.icon or A.HUB_ICON)
	medal.art.icon:SetDesaturated(row == nil)
	medal.art:SetAlpha(row and 1 or 0.5)
	local border = row and K.Ink("good") or E.media.borderColor
	if medal.art.SetBackdropBorderColor then medal.art:SetBackdropBorderColor(border[1], border[2], border[3]) end
	medal.label:SetText(first.label)
	K.Paint(medal.label, row and "body" or "dim")
	medal.date:SetText(row and Fmt.Short(row.t) or L["Not yet"])
	K.Paint(medal.date, row and "secondary" or "dim")
	local tip, hint
	if row then
		local title = A:LineText(row)
		tip = ("%s\n%s, %s"):format(title, Fmt.Day(row.t), Fmt.Clock(row.t))
		if row.src == "journal" or J:LinkFor(row) then hint = { L["Click"], L["open it"] } end
	else
		tip = first.tip .. "\n" .. L["Not yet."]
		if NextShown() then hint = { L["Click"], L["ideas in Next trips"] } end
	end
	LG.Kit.Tooltip(medal, (L["First: %s"]):format(first.label), tip, hint and { hint } or nil)
	medal:SetScript("OnClick", function(self)
		local data = self.first
		if data.row then
			OpenRow(data.row)
		elseif NextShown() then
			A:OpenSection("next", { first = data.key })
		end
	end)
end

local function LayoutStrip(frame)
	local strip = frame.strip
	local width = math.max(frame:GetWidth() or 0, MEDAL_WIDTH)
	local columns = math.max(1, math.floor((width + MEDAL_GAP) / (MEDAL_WIDTH + MEDAL_GAP)))
	for index, medal in ipairs(strip.medals) do
		local column = (index - 1) % columns
		local line = math.floor((index - 1) / columns)
		medal:ClearAllPoints()
		medal:SetPoint("TOPLEFT", column * (MEDAL_WIDTH + MEDAL_GAP), -line * (MEDAL_HEIGHT + MEDAL_GAP))
	end
	local lines = math.ceil(#strip.medals / columns)
	strip:SetHeight(math.max(1, lines * MEDAL_HEIGHT + (lines - 1) * MEDAL_GAP))
	strip.columns = columns
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local function UIState()
	local rec = J:Char()
	local ui = rec and rec.ui or {}
	if type(ui.keepsakes) ~= "table" then ui.keepsakes = {} end
	return ui.keepsakes
end

local function Showing()
	local show = UIState().show
	return CATEGORY_TITLE[show or ""] and show or "all"
end

local function Matches(row, words)
	if #words == 0 then return true end
	local title, sub = A:LineText(row)
	local text = E:FoldText((title or "") .. " " .. (sub or "") .. " " .. (A:KeepNote(row) or ""))
	for _, word in ipairs(words) do
		if not text:find(word, 1, true) then return false end
	end
	return true
end

local function Words(query)
	local words = {}
	for word in E:FoldText(query or ""):gmatch("%S+") do words[#words + 1] = word end
	return words
end

local function OnRowClick(frame)
	return function(row, button, owner)
		if button == "RightButton" and A.JourneyRowMenu then
			A.JourneyRowMenu(frame, row, owner)
		else
			OpenRow(row)
		end
	end
end

local function Links(row)
	if not (A:CanKeep(row) and row.keep) then return nil end
	return { { L["Unkeep"], function() J:SetKeep(row.seq, false) end, L["Takes it off your keepsakes."] } }
end

local function UpdateHeader(frame, counts, firsts)
	frame.header:SetTitle(L["Keepsakes"])
	local earned = 0
	for _, first in ipairs(firsts) do if first.row then earned = earned + 1 end end
	local total = counts.all
	local sentence
	if total > 0 then
		sentence = E:Plural(total, "%s keepsake.", "%s keepsakes."):format(K.Num(total))
	else
		sentence = L["No keepsakes yet."]
	end
	sentence = sentence .. " " .. (L["%s of %s firsts so far."]):format(K.Num(earned), K.Num(#firsts))
	frame.header:SetSentence(sentence)
	frame.firstsEarned = earned
	return earned
end

local function EmptyText(frame, counts)
	if counts.all > 0 then
		return L["Nothing matches"], L["No keepsake matches that search or kind."], {
			{ L["Clear the filters"], function() frame:ClearFilters() end } }
	end
	local buttons
	if A:SectionShown("journey") then
		buttons = { { L["Open the Journey"], function() A:OpenSection("journey") end } }
	end
	return L["No keepsakes yet"],
		L["First kills, epic finds, Honored standings, mounts, and attunements become keepsakes. Right-click any moment in the Journey to keep it."],
		buttons
end

local function Build(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetAllPoints()
	frame.header = K.Header(frame)
	frame.header:SetPoint("TOPLEFT")
	frame.header:SetPoint("TOPRIGHT")
	frame.header:SetActions({ { L["Open the Journey"], function() A:OpenSection("journey") end,
		L["Your whole story, with the keepsakes in their place."] } })

	frame.switch = K.Switch(frame, SWITCH, Showing(), function(show)
		UIState().show = show
		frame:Draw()
	end)
	frame.switch:SetPoint("TOPLEFT", 0, CONTROLS_Y)
	frame.search = K.Search(frame, KEY, L["Search keepsakes"], function() frame:Draw() end)
	frame.search:SetPoint("TOPLEFT", frame.switch, "TOPRIGHT", 12, 1)
	frame.search:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, CONTROLS_Y + 1)

	frame.firstsFold = K.Fold(frame, function(_, open)
		K.SetFoldOpen("keepsakes:firsts", open)
		frame:Draw(true)
	end)
	-- TOPRIGHT, not RIGHT, on the fold and the strip: a bare RIGHT also pins
	-- the vertical center, so the anchors would set their height and push
	-- the strip down to the middle of the page, past what SetHeight asks.
	frame.firstsFold:SetPoint("TOPLEFT", 0, CONTROLS_Y - 28)
	frame.firstsFold:SetPoint("TOPRIGHT", 0, CONTROLS_Y - 28)
	frame.strip = CreateFrame("Frame", nil, frame)
	frame.strip:SetPoint("TOPLEFT", frame.firstsFold, "BOTTOMLEFT", 0, -6)
	frame.strip:SetPoint("TOPRIGHT", frame.firstsFold, "BOTTOMRIGHT", 0, -6)
	frame.strip.medals = {}
	for index = 1, #FIRSTS do frame.strip.medals[index] = CreateMedal(frame.strip) end

	frame.list = K.CreateJournalList(frame, { empty = { L["No keepsakes yet"], "", A.HUB_ICON } })

	local function Anchor(self)
		local open = K.FoldOpen("keepsakes:firsts", true)
		self.strip:SetShown(open)
		self.list:ClearAllPoints()
		if open then
			LayoutStrip(self)
			self.list:SetPoint("TOPLEFT", self.strip, "BOTTOMLEFT", 0, -10)
		else
			self.list:SetPoint("TOPLEFT", self.firstsFold, "BOTTOMLEFT", 0, -6)
		end
		self.list:SetPoint("BOTTOMRIGHT")
	end

	function frame:Draw(keepScroll)
		if not self:IsShown() then
			self.dirty = true
			return
		end
		self.dirty = false
		local started = debugprofilestop()
		local list, counts = All()
		local firsts = A:Firsts()
		self.firsts = firsts
		local earned = UpdateHeader(self, counts, firsts)
		local show = Showing()
		self.switch:SetActive(show)
		for _, entry in ipairs(SWITCH) do
			local count = counts[entry[1]] or 0
			local label = L[entry[2]]
			self.switch:SetLabel(entry[1], count > 0 and (label .. " " .. K.InkHex("secondary") .. count .. "|r") or label)
		end
		local open = K.FoldOpen("keepsakes:firsts", true)
		self.firstsFold:Set(L["Firsts"], (L["%d of %d"]):format(earned, #firsts), open)
		for index, medal in ipairs(self.strip.medals) do SetMedal(medal, firsts[index]) end
		Anchor(self)

		local words = Words(K.Query(KEY))
		local byCategory = {}
		local shown = 0
		for _, entry in ipairs(list) do
			if (show == "all" or entry.category == show) and Matches(entry.row, words) then
				local bucket = byCategory[entry.category]
				if not bucket then
					bucket = {}
					byCategory[entry.category] = bucket
				end
				bucket[#bucket + 1] = entry.row
				shown = shown + 1
			end
		end
		self.shownCount = shown
		local items = {}
		local opts = { onClick = OnRowClick(self), links = Links, time = "date", keepsakes = true }
		for _, category in ipairs(CATEGORIES) do
			local rows = byCategory[category[1]]
			if rows then
				local foldKey = "keepsakes:" .. category[1]
				local foldOpen = show ~= "all" or #words > 0 or K.FoldOpen(foldKey, true)
				items[#items + 1] = { kind = "fold", key = foldKey, label = category[2], open = foldOpen,
					note = tostring(#rows), onToggle = function() self:Draw(true) end }
				if foldOpen then
					items[#items + 1] = { kind = "space", height = 4 }
					for _, item in ipairs(A:JourneyItems(rows, opts)) do items[#items + 1] = item end
				end
				items[#items + 1] = { kind = "space", height = 6 }
			end
		end
		self.items = items
		local title, text, buttons = EmptyText(self, counts)
		self.list:SetEmpty(title, text, A.HUB_ICON, buttons)
		self.list:SetData(items, keepScroll)
		self.buildMs = debugprofilestop() - started
	end

	function frame:SetShow(show)
		UIState().show = CATEGORY_TITLE[show or ""] and show or "all"
		self:Draw()
	end

	function frame:SetSearch(text)
		self.search:SetText(text or "")
		self.search:GetScript("OnTextChanged")(self.search, true)
	end

	function frame:ClearFilters()
		UIState().show = "all"
		self:SetSearch("")
		self:Draw()
	end

	frame:SetScript("OnSizeChanged", function(self)
		if self.strip:IsShown() then
			local columns = self.strip.columns
			LayoutStrip(self)
			if columns ~= self.strip.columns then self.list:SetData(self.items or {}, true) end
		end
	end)
	frame:SetScript("OnShow", function(self) if self.dirty then self:Draw(true) end end)
	return frame
end

local function Show(frame, arg)
	if type(arg) == "table" then
		if arg.show then UIState().show = arg.show end
		if arg.search then frame:SetSearch(arg.search) end
	elseif type(arg) == "string" and CATEGORY_TITLE[arg] then
		UIState().show = arg
	end
	frame:Draw(true)
end

local function Refresh(frame, changed)
	if changed.adventure or changed.settings or changed.items or changed.data then frame:Draw(true) end
end

A:RegisterSection(KEY, {
	title = "Keepsakes",
	icon = "Interface\\Icons\\INV_Misc_Gem_Pearl_04",
	desc = "Your big moments as cards: first kills, epic finds, standings, mounts, and the moments you kept, with your firsts.",
	words = { "keepsakes", "keepsake", "firsts", "trophies" },
	hidden = function() return A.db and A.db.keepsakes == false end,
	count = function()
		local count = A:KeepsakeCount()
		return count > 0 and count or nil
	end,
	build = Build,
	show = Show,
	refresh = Refresh,
	search = function(text)
		local words = Words(text)
		if #words == 0 then return {} end
		local out = {}
		for _, entry in ipairs((All())) do
			if A:KeepNote(entry.row) and Matches(entry.row, words) then
				local title = A:LineText(entry.row)
				out[#out + 1] = { title = title, sub = (L["Your note: %s"]):format(A:KeepNote(entry.row)),
					icon = J.ICON and J.ICON.note, arg = { search = text } }
				if #out >= 20 then break end
			end
		end
		return out
	end,
})

---------------------------------------------------------------------------
-- The item menu: keep the newest find of this item, or show it
---------------------------------------------------------------------------
local function NewestFind(itemID)
	local rec = J:Char()
	if not rec then return nil end
	local rows = J:Rows()
	for index = #rows, 1, -1 do
		local row = rows[index]
		if FIND[row.kind] and tonumber(row.item) == itemID then
			local copy = {}
			for key, value in pairs(row) do copy[key] = value end
			copy.src = "journal"
			return copy
		end
	end
end
A.NewestFind = NewestFind

LG:RegisterItemMenu("keepsake", function(root, itemID)
	if not (A:Running() and A:SectionShown("journey")) then return end
	itemID = tonumber(itemID)
	local row = itemID and NewestFind(itemID)
	if not row then return end
	if A:CanKeep(row) then
		if row.keep then
			root:CreateButton(L["Remove from keepsakes"], function() J:SetKeep(row.seq, false) end)
		else
			root:CreateButton(L["Keep in your journal"], function() J:SetKeep(row.seq, true) end)
		end
	end
	root:CreateButton(L["Show in your journal"], function() A:OpenSection("journey", { seq = row.seq }) end)
end)
