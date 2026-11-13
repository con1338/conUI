-- EldoUI My Adventure: the Journey section, the timeline in the Journal
-- window's look.
--
--   Mira                                                    [Jump to date]
--   Gnome Mage, level 23. A journal kept since September 14.
--   -----------------------------------------------------------------------
--   [Level][Day][Zone]  [ Search the journal            ] [Filter] [Zone: All]
--   [23] Chapter 23 · Westfall  (Now)                                    v
--    |   2h 10m so far · 41 kills · 9 quests · 1 death
--    |   +----------------------------------------------------------+
--    |   | [ic] Reached level 23                 Westfall    14:02  |
--    |   | [ic] Learned Frost Nova (Rank 2)      Stormwind   13:40  |
--    |   +----------------------------------------------------------+
--    |   +== The Deadmines ================================ Oct 3 ==+
--    |   | [boss] Edwin VanCleef   First kill                       |
--   [22] Elwynn Forest   12 kills · 6 moments           1h 05m      >
--
-- Views: by level (chapters on the timeline; the current chapter and the
-- one before start open, older ones fold while "Fold older chapters" is
-- on), by day and by zone (folds, the newest three open). Search, the
-- group filter (Growth, Gear, Deeds, Places, People, Notes), a zone
-- filter and "Jump to date". Keepsakes break the ledger cards: standing
-- cards, victory cards (first kills of one run, with the epic finds that
-- dropped from them), find rows and pinned notes. Long chapters show
-- their newest 120 moments, then "Show all n".
--
-- Every row is a fact the journal or another EldoUI module wrote down
-- (E.Journal:Timeline). A click opens what it is about (navigation only);
-- right-click keeps it as a keepsake, writes a note on it, opens the map
-- or removes it. Removing a moment and taking it off the keepsakes both
-- show a notice with Undo. Imported rows say so after their place. The
-- level view starts with the level river (UI/River.lua, "riverStrip")
-- while no search or filter is on.
--
-- Routes (A:OpenSection("journey", arg)): nil, or a table with any of
--   search = text, zone = name, view = "level" | "day" | "zone",
--   seq = n (one moment), level = n (one chapter), day = "2026-10-08",
--   address = "journal:..." (the newest moment that links to it).
--
-- Shared with the other hub pages:
--   A:LineText(row) -> title, sub, icon   one row in words (UI labels)
--   A:JourneyItems(rows, opts) -> items   rows as journal list items
--                                         (Keepsakes.lua uses it too)
--
-- Portions adapted from Forever Journal by Ugge Zen, MIT License (see
-- THIRD_PARTY_NOTICES.md): the Journey's views, chapters, folding,
-- keepsake cards inside the ledger, the line texts and the "Show all"
-- cut-off.
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
local LG = E.LootGuide
local K = E.AdventureKit
local T = E.tokens
local Fmt = A.Fmt
local Plain = A.Plain

local KEY = "journey"
local GROUP_CAP = 120          -- rows per group before "Show all n"
local RUN_WINDOW = 4 * 3600    -- first kills this close share one victory card
local LOOT_WINDOW = 180        -- an epic this soon after a first kill hangs on its card
local CONTROLS_Y = -(K.HEADER_HEIGHT + 8)
local FILTER_Y = CONTROLS_Y - 26
local RIVER_HEIGHT = 104       -- the level river over the chapters (markers, band, labels)

---------------------------------------------------------------------------
-- Line texts
---------------------------------------------------------------------------
local function Text(value)
	if E:IsSecret(value) or type(value) ~= "string" or value == "" then return nil end
	return value
end

local function Place(row)
	local zone, sub = Text(row.zone), Text(row.subzone)
	if zone and sub and sub ~= zone then return ("%s, %s"):format(sub, zone) end
	return zone or sub
end

local function QuestName(id)
	id = tonumber(id)
	if not id then return L["a quest"] end
	local name = LG.DataName and LG:DataName("quest", id)
	if type(name) == "string" and name ~= "" then return name end
	local quest = LG.Quest and LG:Quest(id)
	return quest and Text(quest.name) or (L["Quest %d"]):format(id)
end

local function ItemName(id)
	id = tonumber(id)
	if not id then return L["an item"] end
	local name = C_Item.GetItemInfo(id)
	if Text(name) then return name end
	local record = LG.ItemRecord and LG:ItemRecord(id)
	return record and Text(record.name) or ("item:" .. id)
end

local function Standing(n)
	n = tonumber(n)
	local label = n and rawget(_G, "FACTION_STANDING_LABEL" .. n)
	return Text(label) or (n and tostring(n)) or "?"
end

local function AttuneName(key)
	local At = E.Attunements
	if At and At.Get and At:Get(key) then return At:Name(key) end
	return tostring(key or "?")
end

local function NoteEntry(id)
	local rec = J:Char()
	for _, note in ipairs(rec and rec.notes or {}) do
		if type(note) == "table" and note.id == id then return note end
	end
end

-- Pinned notes from the Notes files (A.Notes:Pinned()), when they are
-- there: a list of note entries, and the set of their ids.
function A:PinnedNotes()
	local notes = self.Notes
	if type(notes) ~= "table" or type(notes.Pinned) ~= "function" then return nil, {} end
	local ok, list = pcall(notes.Pinned, notes)
	if not ok or type(list) ~= "table" then return nil, {} end
	local ids = {}
	for _, note in ipairs(list) do
		if type(note) == "table" and note.id ~= nil then ids[note.id] = true end
	end
	return list, ids
end

-- Kinds rolled into a chapter summary, in words ("6 spells").
local ROLLUP_WORDS = {
	spell = function(n) return E:Plural(n, "%d spell", "%d spells") end,
	recipe = function(n) return E:Plural(n, "%d recipe", "%d recipes") end,
	loot = function(n) return E:Plural(n, "%d find", "%d finds") end,
	flight = function(n) return E:Plural(n, "%d flight path", "%d flight paths") end,
	quest = function(n) return E:Plural(n, "%d quest", "%d quests") end,
	bossagain = function(n) return E:Plural(n, "%d boss kill", "%d boss kills") end,
	subzone = function(n) return E:Plural(n, "%d new place", "%d new places") end,
	gear = function(n) return E:Plural(n, "%d gear change", "%d gear changes") end,
	rested = function(n) return E:Plural(n, "%d rest", "%d rests") end,
	gather = function(n) return E:Plural(n, "%d gathering", "%d gatherings") end,
	farm = function(n) return E:Plural(n, "%d farming trip", "%d farming trips") end,
	rare = function(n) return E:Plural(n, "%d rare seen", "%d rares seen") end,
	cinematic = function(n) return E:Plural(n, "%d cinematic", "%d cinematics") end,
	session = function(n) return E:Plural(n, "%d session", "%d sessions") end,
}

local function RollupText(counts)
	local parts = {}
	for kind, count in tostring(counts or ""):gmatch("([%w_]+):(%d+)") do
		count = tonumber(count)
		local words = ROLLUP_WORDS[kind]
		if words then
			parts[#parts + 1] = words(count):format(count)
		else
			parts[#parts + 1] = E:Plural(count, "%d other moment", "%d other moments"):format(count)
		end
	end
	return table.concat(parts, ", ")
end

local LINES = {
	level = function(row)
		local zone = Text(row.zone)
		if zone then return (L["Reached level %d in %s"]):format(row.level or 0, zone) end
		return (L["Reached level %d"]):format(row.level or 0)
	end,
	zone = function(row)
		if row.begin then return (L["The journal begins in %s"]):format(Text(row.zone) or L["an unknown place"]) end
		return (L["First visit to %s"]):format(Text(row.zone) or L["an unknown place"])
	end,
	dungeon = function(row) return (L["First time in %s"]):format(Text(row.instance) or Text(row.zone) or L["a dungeon"]) end,
	raid = function(row) return (L["First time in %s"]):format(Text(row.instance) or Text(row.zone) or L["a raid"]) end,
	death = function(row)
		local place = Place(row)
		return place and (L["Died in %s"]):format(place) or L["Died in an unknown place"]
	end,
	spell = function(row)
		local name = Text(row.name) or L["a spell"]
		local rank = Text(row.rank)
		return rank and (L["Learned %s (%s)"]):format(name, rank) or (L["Learned %s"]):format(name)
	end,
	recipe = function(row) return (L["Recipe: %s"]):format(Text(row.name) or "?") end,
	profession = function(row) return (L["Became a student of %s"]):format(Text(row.profession) or "?") end,
	skill = function(row)
		local name = Text(row.profession) or "?"
		if row.mastered then return (L["Mastered %s"]):format(name) end
		return (L["%s reached %d"]):format(name, tonumber(row.rank) or 0)
	end,
	rep = function(row) return (L["%s now counts you as %s"]):format(Text(row.faction) or "?", Standing(row.standing)) end,
	boss = function(row) return (L["Defeated %s"]):format(Text(row.boss) or "?") end,
	raidboss = function(row) return (L["Defeated %s"]):format(Text(row.boss) or "?") end,
	bossagain = function(row) return (L["Defeated %s again"]):format(Text(row.boss) or "?") end,
	loot = function(row) return (L["Found %s"]):format(ItemName(row.item)) end,
	gear = function(row) return (L["Equipped %s"]):format(ItemName(row.item)) end,
	wish = function(row) return (L["Wishlist item found: %s"]):format(ItemName(row.item)) end,
	mount = function(row) return (L["New mount: %s"]):format(Text(row.name) or "?") end,
	pet = function(row) return (L["New companion: %s"]):format(Text(row.name) or "?") end,
	respec = function(row)
		local points = tonumber(row.points) or 0
		return E:Plural(points, "Re-specced %d talent point", "Re-specced %d talent points"):format(points)
	end,
	flight = function(row) return (L["Flight path: %s"]):format(Text(row.place) or Text(row.zone) or "?") end,
	goal = function(row) return (L["Goal reached: %s"]):format(Text(row.name) or "?") end,
	goalset = function(row) return (L["New goal: %s"]):format(Text(row.name) or "?") end,
	note = function(row)
		local note = NoteEntry(row.note)
		return note and Text(note.text) or L["A note"]
	end,
	run = function(row) return (L["Ran %s again"]):format(Text(row.instance) or Text(row.zone) or "?") end,
	pvpwin = function(row) return (L["Won %s"]):format(Text(row.battleground) or "?") end,
	pvploss = function(row) return (L["Lost %s"]):format(Text(row.battleground) or "?") end,
	quest = function(row) return (L["Handed in %s"]):format(QuestName(row.quest)) end,
	questchain = function(row) return (L["Finished the chain with %s"]):format(QuestName(row.quest)) end,
	dungeonquest = function(row) return (L["Handed in %s"]):format(QuestName(row.quest)) end,
	groupquest = function(row)
		local names = Text(row.names)
		if names then return (L["Handed in %s with %s"]):format(QuestName(row.quest), names) end
		return (L["Handed in %s"]):format(QuestName(row.quest))
	end,
	attunestep = function(row)
		return (L["%s: step %d of %d"]):format(AttuneName(row.attune), tonumber(row.step) or 0, tonumber(row.total) or 0)
	end,
	attuned = function(row) return (L["Attuned: %s"]):format(AttuneName(row.attune)) end,
	challenge = function(row) return (L["Legacy challenge done: %s"]):format(Text(row.name) or "?") end,
	legacylevel = function(row) return (L["Legacy rank %d"]):format(tonumber(row.rank) or 0) end,
	title = function(row) return (L["New title: %s"]):format(Text(row.name) or "?") end,
	explored = function(row) return (L["Explored %s"]):format(Text(row.zone) or "?") end,
	subzone = function(row) return (L["Discovered %s"]):format(Text(row.subzone) or Text(row.zone) or "?") end,
	hearth = function(row) return (L["Hearthstone set to %s"]):format(Text(row.place) or Text(row.subzone) or "?") end,
	met = function(row) return (L["Met %s"]):format(Text(row.name) or "?") end,
	together = function(row)
		return (L["%s with %s"]):format(Fmt.Span(row.seconds), Text(row.name) or "?")
	end,
	rested = function(row) return (L["Rested: %d%% of a level"]):format(tonumber(row.pct) or 0) end,
	gap = function(row)
		local days = tonumber(row.days) or 0
		return E:Plural(days, "Back after %d day away", "Back after %d days away"):format(days)
	end,
	gather = function(row)
		local count = tonumber(row.count)
		if count and count > 1 then return (L["Gathered %s (%d)"]):format(Text(row.node) or "?", count) end
		return (L["Gathered %s"]):format(Text(row.node) or "?")
	end,
	farm = function(row) return (L["Farmed for %s"]):format(Fmt.Span(row.seconds)) end,
	rare = function(row) return (L["Saw %s"]):format(Text(row.rare) or "?") end,
	cinematic = function() return L["Watched a cinematic"] end,
	guild = function(row) return (L["Joined %s"]):format(Text(row.guild) or "?") end,
	session = function(row) return (L["Played for %s"]):format(Fmt.Span(row.played)) end,
	rollup = function(row)
		local text = RollupText(row.counts)
		if text == "" then return L["Earlier moments"] end
		return (L["Also this level: %s"]):format(text)
	end,
}
A.LINES = LINES

-- title, sub, icon of one row. The sub line says where and at which level.
function A:LineText(row)
	if type(row) ~= "table" then return "", nil, nil end
	local fn = LINES[row.kind]
	local ok, title = false, nil
	if fn then ok, title = pcall(fn, row) end
	if not ok or type(title) ~= "string" then
		local def = J:Kind(row.kind)
		title = Text(row.name) or (def and def.plugin and Text(row.title)) or tostring(row.kind or "?")
	end
	local bits = {}
	local place = row.kind ~= "zone" and row.kind ~= "death" and Place(row) or nil
	if place then bits[#bits + 1] = place end
	if type(row.level) == "number" then bits[#bits + 1] = (L["level %d"]):format(row.level) end
	if (row.kind == "run" or row.kind == "dungeon" or row.kind == "raid") and tonumber(row.duration) then
		bits[#bits + 1] = (L["%s inside"]):format(Fmt.Span(row.duration))
	end
	if row.kind == "quest" and tonumber(row.xp) and row.xp > 0 then bits[#bits + 1] = (L["%s XP"]):format(BreakUpLargeNumbers(row.xp)) end
	if row.kind == "boss" and row.first then bits[#bits + 1] = L["First kill"] end
	local def = J:Kind(row.kind)
	return title, table.concat(bits, " · "), def and def.icon or nil
end

---------------------------------------------------------------------------
-- Rows to list items
---------------------------------------------------------------------------
local function KeepKey(row)
	if row.src and row.src ~= "journal" then return row.ref end
	return row.seq and ("seq:" .. row.seq) or nil
end
A.KeepKey = KeepKey

local function IsFind(row)
	return row.kind == "loot" or row.kind == "gear" or row.kind == "wish"
end

-- The tooltip of a row: what it says, when and where, and what a click does.
local function RowTip(row)
	return function(tooltip)
		local _, sub = A:LineText(row)
		if sub and sub ~= "" then tooltip:AddLine(sub, unpack(T.text.secondary)) end
		if type(row.t) == "number" then tooltip:AddLine(("%s, %s"):format(Fmt.Day(row.t), Fmt.Clock(row.t)), unpack(T.text.secondary)) end
		local source = row.src and row.src ~= "journal" and J:Source(row.src)
		if source then tooltip:AddLine((L["from %s"]):format(source.title), unpack(T.text.dim)) end
		local note = A.KeepNote and A:KeepNote(row)
		if note then tooltip:AddLine(note, unpack(T.text.body)) end
		if J:LinkFor(row) then E:TooltipHint(tooltip, { L["Click"], L["open it"] }) end
		E:TooltipHint(tooltip, { L["Right-click"], L["more"] })
	end
end

local function TimeText(row, how)
	if how == "clock" then return Fmt.Clock(row.t) end
	if how == "date" then return Fmt.Short(row.t) end
	return Fmt.When(row.t)
end

-- Imported rows (Import.lua): everything up to
-- the newest moment of the last import (rec.imported.lastT) came from
-- there. -> the high-water time, 0 without an import.
local function ImportMark()
	local rec = J:Char()
	local imported = type(rec) == "table" and type(rec.imported) == "table" and rec.imported or nil
	if not (imported and imported.from == "ForeverJournal") then return 0 end
	return tonumber(imported.lastT) or 0
end

local function Imported(row, mark)
	mark = mark or ImportMark()
	local t = type(row) == "table" and tonumber(row.t) or nil
	return mark > 0 and t ~= nil and t <= mark or false
end
A.JourneyImported = Imported

local function FromLabel(sub)
	local label = L["from Forever Journal"]
	if type(sub) == "string" and sub ~= "" then return sub .. " · " .. label end
	return label
end

-- opts: indent, spine, time ("clock", "date" or nil = clock today, else
-- the date), onClick(row, button, frame), keepsakes (cards on; default
-- the setting), notes (show keepsake notes under their card).
function A:JourneyItems(rows, opts)
	opts = opts or {}
	local items = {}
	local mark = ImportMark()
	local indent, spine = opts.indent or 0, opts.spine
	local cards = opts.keepsakes
	if cards == nil then cards = not (A.db and A.db.keepsakes == false) end
	local run = {}

	local function Click(row)
		if not opts.onClick then return nil end
		return function(_, button, frame) opts.onClick(row, button, frame) end
	end

	local function Flush()
		local count = #run
		for index, entry in ipairs(run) do
			local position = count == 1 and "only" or index == 1 and "first" or index == count and "last" or "middle"
			entry.position = position
			items[#items + 1] = entry
		end
		if count > 0 then items[#items + 1] = { kind = "space", height = 8, spine = spine } end
		wipe(run)
	end

	local function NoteUnder(row)
		local note = opts.notes ~= false and A.KeepNote and A:KeepNote(row)
		if note then
			items[#items + 1] = { kind = "note", text = note, sub = L["Your note"], pinned = true, indent = indent + 24, spine = spine }
			items[#items + 1] = { kind = "space", height = 4, spine = spine }
		end
	end

	local function Ledger(row)
		local title, sub, icon = A:LineText(row)
		if Imported(row, mark) then sub = FromLabel(sub) end
		if IsFind(row) and tonumber(row.item) then
			return { kind = "find", row = row, indent = indent, spine = spine,
				item = { itemID = tonumber(row.item), sub = sub, tag = TimeText(row, opts.time) } }
		end
		return { kind = "ledger", row = row, icon = icon, title = title, sub = sub, time = TimeText(row, opts.time),
			indent = indent, spine = spine, onClick = Click(row), tip = RowTip(row), tipTitle = title,
			titleRole = J:IsKeepsake(row) and "head" or nil, links = opts.links and opts.links(row) or nil }
	end

	-- First kills of one run share a card; epic finds from them hang on it.
	local used = {}
	local function Victory(start)
		local first = rows[start]
		local instance = Text(first.instance) or Text(first.zone)
		local card = { kind = "victory", row = first, instance = instance or L["A dungeon"], time = Fmt.Short(first.t),
			bosses = {}, loot = {}, rows = {}, indent = indent, spine = spine }
		local names = {}
		for index = start, #rows do
			local row = rows[index]
			if not used[index] and (row.kind == "boss" or row.kind == "raidboss") and J:IsKeepsake(row)
				and (Text(row.instance) or Text(row.zone)) == instance and math.abs((row.t or 0) - (first.t or 0)) <= RUN_WINDOW then
				used[index] = true
				local kills = tonumber(row.kills)
				local sub = L["First kill"]
				if kills and kills > 1 then sub = E:Plural(kills - 1, "First kill · killed %d time since", "First kill · killed %d times since"):format(kills - 1) end
				card.bosses[#card.bosses + 1] = { name = Text(row.boss) or "?", sub = sub, icon = J.ICON.boss }
				card.rows[#card.rows + 1] = row
				names[Text(row.boss) or ""] = row.t or 0
			end
		end
		for index = 1, #rows do
			local row = rows[index]
			local from = row.kind == "loot" and Text(row.from)
			if not used[index] and from and names[from] and (row.t or 0) >= names[from] and (row.t or 0) - names[from] <= LOOT_WINDOW
				and J:IsKeepsake(row) and tonumber(row.item) then
				used[index] = true
				card.loot[#card.loot + 1] = { itemID = tonumber(row.item), sub = (L["from %s"]):format(from) }
				card.rows[#card.rows + 1] = row
			end
		end
		local count = #card.bosses
		card.footer = E:Plural(count, "%d boss down this run", "%d bosses down this run"):format(count)
		return card
	end

	for index, row in ipairs(rows) do
		if not used[index] then
			local keep = cards and J:IsKeepsake(row)
			if keep and (row.kind == "boss" or row.kind == "raidboss") then
				Flush()
				items[#items + 1] = Victory(index)
				NoteUnder(row)
			elseif keep and row.kind == "rep" then
				Flush()
				items[#items + 1] = { kind = "standing", row = row, faction = Text(row.faction) or "?", standing = Standing(row.standing),
					standingID = tonumber(row.standing), time = Fmt.Short(row.t), indent = indent, spine = spine }
				NoteUnder(row)
			elseif row.kind == "note" then
				local note = NoteEntry(row.note)
				if note and Text(note.text) then
					Flush()
					local where = Place(row)
					local sub = where and ("%s · %s"):format(where, Fmt.Short(row.t)) or Fmt.Short(row.t)
					local _, pinnedIDs = A:PinnedNotes()
					items[#items + 1] = { kind = "note", row = row, text = note.text, sub = sub,
						pinned = (row.keep or note.pinned or pinnedIDs[note.id]) and true or false,
						indent = indent, spine = spine }
					items[#items + 1] = { kind = "space", height = 4, spine = spine }
				end
			elseif keep then
				-- Finds and the other keepsakes: a card of their own.
				Flush()
				run[1] = Ledger(row)
				Flush()
				NoteUnder(row)
			else
				run[#run + 1] = Ledger(row)
			end
		end
	end
	Flush()
	return items
end

-- The level river above the chapters (UI/River.lua): a click on a level
-- opens its chapter here, Shift-click the Book.
K.ROWS.journey_river = {
	height = function(item) return item.height or RIVER_HEIGHT end,
	create = function(row)
		row:EnableMouse(false)
	end,
	update = function(row, item)
		if not row.river and A.River then
			row.river = A.River.Create(row, { height = (item.height or RIVER_HEIGHT) - 8 })
			row.river:SetPoint("TOPLEFT", 0, -4)
			row.river:SetPoint("TOPRIGHT", 0, -4)
		end
		if row.river then row.river:SetBook(item.book, item.set) end
	end,
}

-- A chapter's story line ("Story lines in chapters"): the Storyteller's
-- opening under the chapter title and its closing after the moments, in
-- the secondary ink on the timeline.
local STORY_GAP = 4

local function StoryWidth(item, width)
	return math.max((width or 400) - (item.indent or 0) - 16, 40)
end

K.ROWS.journey_story = {
	height = function(item, width)
		return STORY_GAP + E.UIKit.TextHeight(item.text or "", StoryWidth(item, width), K.size.small, { spacing = 2 }) + STORY_GAP
	end,
	create = function(row)
		row:EnableMouse(false)
		row.text = K.Text(row, K.size.small, "LEFT", "secondary")
		row.text:SetWordWrap(true)
		row.text:SetSpacing(2)
		row.line = row:CreateTexture(nil, "BACKGROUND", nil, 1)
		row.line:SetWidth(K.SPINE_WIDTH)
	end,
	update = function(row, item)
		row.text:ClearAllPoints()
		row.text:SetPoint("TOPLEFT", item.indent or 0, -STORY_GAP)
		row.text:SetPoint("TOPRIGHT", -16, -STORY_GAP)
		row.text:SetText(item.text or "")
		K.Paint(row.text, "secondary")
		row.line:ClearAllPoints()
		row.line:SetPoint("TOPLEFT", row, "TOPLEFT", K.SPINE_X, 0)
		row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", K.SPINE_X, 0)
		local c = K.OnPaper() and K.Ink("rule") or T.edge.window
		row.line:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
		row.line:SetShown(item.spine and true or false)
	end,
}

-- Sentences -> one line of text (nil when there is none).
local function StoryText(list)
	local parts = {}
	for _, sentence in ipairs(type(list) == "table" and list or {}) do
		local text = type(sentence) == "table" and sentence.text or nil
		if type(text) == "string" and text ~= "" then parts[#parts + 1] = text end
	end
	return #parts > 0 and table.concat(parts, " ") or nil
end
A.JourneyStoryText = StoryText

---------------------------------------------------------------------------
-- Grouping
---------------------------------------------------------------------------
local function CurrentLevel()
	local level = Plain(UnitLevel("player"))
	return type(level) == "number" and level or nil
end

-- The zone a chapter is named after: most time there (the level record),
-- else most moments.
local function ChapterZone(level, rows)
	local rec = J:Char()
	local record = rec and rec.levels and rec.levels[level]
	local best, most
	for zone, seconds in pairs(type(record) == "table" and type(record.zones) == "table" and record.zones or {}) do
		seconds = tonumber(seconds) or 0
		if type(zone) == "string" and (not most or seconds > most) then best, most = zone, seconds end
	end
	if best then return best end
	local counts = {}
	for _, row in ipairs(rows) do
		local zone = Text(row.zone)
		if zone then counts[zone] = (counts[zone] or 0) + 1 end
	end
	for zone, count in pairs(counts) do
		if not most or count > most or (count == most and zone < best) then best, most = zone, count end
	end
	return best
end

-- "2h 10m so far · 41 kills · 9 quests · 1 death": facts of the level record.
local function ChapterFacts(level, rows, current)
	local rec = J:Char()
	local record = rec and rec.levels and rec.levels[level]
	local parts = {}
	local seconds
	for _, row in ipairs(rows) do
		if row.kind == "level" and tonumber(row.took) then seconds = tonumber(row.took) end
	end
	if not seconds and type(record) == "table" and type(record.zones) == "table" then
		for _, value in pairs(record.zones) do seconds = (seconds or 0) + (tonumber(value) or 0) end
	end
	if seconds and seconds > 0 then
		parts[#parts + 1] = current and (L["%s so far"]):format(Fmt.Span(seconds)) or Fmt.Span(seconds)
	end
	local stat = type(record) == "table" and type(record.stat) == "table" and record.stat or {}
	local kills, quests = tonumber(stat.kills), tonumber(stat.quests)
	local deaths = type(record) == "table" and tonumber(record.deaths) or tonumber(stat.deaths)
	if kills and kills > 0 then parts[#parts + 1] = E:Plural(kills, "%d kill", "%d kills"):format(kills) end
	if quests and quests > 0 then parts[#parts + 1] = E:Plural(quests, "%d quest", "%d quests"):format(quests) end
	if deaths and deaths > 0 then parts[#parts + 1] = E:Plural(deaths, "%d death", "%d deaths"):format(deaths) end
	return parts, seconds
end

local PinnedFirst

local function Newest(rows)
	local out = {}
	for index = #rows, 1, -1 do out[#out + 1] = rows[index] end
	return out
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local VIEWS = { { "level", Key("Level"), Key("Chapters by level on a timeline.") },
	{ "day", Key("Day"), Key("One group per day you played.") },
	{ "zone", Key("Zone"), Key("One group per zone.") } }

local FILTERS = {
	{ "all", Key("All"), Key("Every moment.") },
	{ "growth", Key("Growth"), Key("Levels, spells, recipes, and professions.") },
	{ "gear", Key("Gear"), Key("Finds, mounts, and companions.") },
	{ "deeds", Key("Deeds"), Key("Bosses, quests, reputation, goals, and deaths.") },
	{ "places", Key("Places"), Key("New zones, dungeons, runs, and flight paths.") },
	{ "people", Key("People"), Key("The people you met and grouped with.") },
	{ "notes", Key("Notes"), Key("Your notes.") },
}

local function UIState()
	local rec = J:Char()
	local ui = rec and rec.ui or {}
	if type(ui.journey) ~= "table" then ui.journey = {} end
	return ui.journey
end

local function View()
	local by = A.db and A.db.journeyBy
	return (by == "day" or by == "zone") and by or "level"
end

-- Every row the page may show for the filters (oldest first).
local function Rows(frame)
	local state = UIState()
	local ctx = { group = state.group or "all", search = K.Query(KEY) }
	local rows, partial = J:Timeline(nil, nil, nil, ctx)
	frame.partial = partial
	local zone = frame.zone
	local out = {}
	for _, row in ipairs(rows) do
		if row.kind ~= "goalset" and (not zone or Text(row.zone) == zone) then out[#out + 1] = row end
	end
	return out
end

local function Filtered(frame)
	local state = UIState()
	return (state.group and state.group ~= "all") or K.Query(KEY) ~= "" or frame.zone ~= nil
end

function A:OpenRow(row)
	local address = J:LinkFor(row)
	if address and J:Open(address) then return true end
	return false
end

-- Takes a moment off the keepsakes, with Undo (DESIGN.md 5).
local function Unkeep(frame, row)
	if not J:SetKeep(row.seq, false) then return false end
	local seq = row.seq
	E.UIKit.Toast(frame, L["Taken off your keepsakes."], { action = { L["Undo"], function() J:SetKeep(seq, true) end } })
	return true
end
A.JourneyUnkeep = Unkeep

-- Right-click menu of a row: keep, note, map, open, remove.
local function RowMenu(frame, row, owner)
	E.UIKit.ContextMenu(owner or frame, function(_, root)
		local title = A:LineText(row)
		root:CreateTitle(title)
		local address = J:LinkFor(row)
		if address then root:CreateButton(L["Open"], function() J:Open(address) end) end
		if A.CanKeep and A:CanKeep(row) then
			if row.keep then
				root:CreateButton(L["Remove from keepsakes"], function() Unkeep(frame, row) end)
			else
				root:CreateButton(L["Keep as a keepsake"], function() J:SetKeep(row.seq, true) end)
			end
		end
		if A.EditKeepNote and J:IsKeepsake(row) and KeepKey(row) then
			root:CreateButton(A:KeepNote(row) and L["Edit the note"] or L["Write a note on it"], function() A:EditKeepNote(row) end)
		end
		local map = A.RowMap and A:RowMap(row)
		if map then root:CreateButton(L["Open the map there"], function() A:OpenRowMap(row) end) end
		if row.src == "journal" and row.seq then
			root:CreateButton(L["Remove from the journal"], function()
				local trash = J:DeleteRow(row.seq)
				if trash then K.UndoToast(frame, L["Removed from your journal."], trash) end
			end)
		end
	end)
end
A.JourneyRowMenu = RowMenu

-- The map of a row's zone, when the journal knows it (navigation only).
function A:RowMap(row)
	local rec = J:Char()
	local zone = Text(row and row.zone)
	local info = zone and rec and rec.zones and rec.zones[zone]
	local map = type(info) == "table" and tonumber(info.map) or nil
	return map
end

function A:OpenRowMap(row)
	local map = self:RowMap(row)
	if not map then return false end
	return E:OpenWorldMapAt(map)
end

local function OnRowClick(frame)
	return function(row, button, owner)
		if button == "RightButton" then
			RowMenu(frame, row, owner)
		else
			A:OpenRow(row)
		end
	end
end

-- Hover links on a ledger row: Keep / Unkeep for the journal's own rows.
local function Links(frame)
	return function(row)
		if not (A.CanKeep and A:CanKeep(row)) then return nil end
		if row.keep then
			return { { L["Unkeep"], function() Unkeep(frame, row) end, L["Takes it off your keepsakes."] } }
		end
		return { { L["Keep"], function() J:SetKeep(row.seq, true) end, L["Keeps this moment on your Keepsakes page."] } }
	end
end

local function More(frame, key, total, items, indent, spine)
	items[#items + 1] = { kind = "more", text = K.MoreText(total), indent = indent, spine = spine,
		onClick = function()
			frame.expanded[key] = true
			frame:Draw(true)
		end }
end

local function Cut(frame, key, rows)
	if frame.expanded[key] or #rows <= GROUP_CAP or K.Query(KEY) ~= "" then return rows, nil end
	local out = {}
	for index = 1, GROUP_CAP do out[index] = rows[index] end
	return out, #rows
end

local function ItemOpts(frame, extra)
	local opts = { onClick = OnRowClick(frame), links = Links(frame) }
	for key, value in pairs(extra or {}) do opts[key] = value end
	return opts
end

local function ByLevel(frame, rows)
	local byLevel, levels, other = {}, {}, {}
	for _, row in ipairs(rows) do
		local level = tonumber(row.level)
		if level then
			if not byLevel[level] then
				byLevel[level] = {}
				levels[#levels + 1] = level
			end
			table.insert(byLevel[level], row)
		else
			other[#other + 1] = row
		end
	end
	table.sort(levels, function(a, b) return a > b end)
	local current = CurrentLevel()
	local filtered = Filtered(frame)
	local fold = not (A.db and A.db.foldChapters == false)
	local items = {}
	frame.groups = {}
	-- The Storyteller's book, for the river and the story lines.
	local wantRiver = not filtered and A.db and A.db.riverStrip and A.River and #levels > 0
	local wantLines = A.db and A.db.storyLines and #levels > 0
	local book, set
	if wantRiver or wantLines then
		local SV = A.StoryView
		if SV and SV.Build then
			local ok, built, builtSet = pcall(SV.Build)
			if ok then book, set = built, builtSet else geterrorhandler()(built) end
		end
	end
	local stories = {}
	frame.storyShown = 0
	if wantLines and book and type(book.journey) == "table" then
		for _, chapter in ipairs(book.journey) do
			if type(chapter) == "table" and type(chapter.level) == "number" then
				stories[chapter.level] = { opening = StoryText(chapter.opening), closing = StoryText(chapter.closing) }
			end
		end
	end
	-- The level river over the chapters ("Level river on the Journey").
	frame.riverShown = false
	if wantRiver then
		if book and set and book.river then
			items[#items + 1] = { kind = "journey_river", book = book, set = set, height = RIVER_HEIGHT }
			items[#items + 1] = { kind = "space", height = 4 }
			frame.riverShown = true
		end
	end
	local chapters = #levels + (#other > 0 and 1 or 0)
	local function Chapter(position, level, list)
		local key = "journey:level:" .. tostring(level)
		local isCurrent = level == current
		local recent = current == nil or (type(level) == "number" and level >= current - 1)
		local open = filtered or K.FoldOpen(key, recent or not fold)
		local zone = type(level) == "number" and ChapterZone(level, list) or nil
		local facts, seconds = {}, nil
		if type(level) == "number" then facts, seconds = ChapterFacts(level, list, isCurrent) end
		local title
		if type(level) == "number" then
			title = zone and (L["Chapter %d · %s"]):format(level, zone) or (L["Chapter %d"]):format(level)
		else
			title = L["Before the journal knew your level"]
		end
		local spineInfo = { up = position > 1, down = position < chapters }
		local count = #list
		local moments = E:Plural(count, "%d moment", "%d moments"):format(count)
		frame.groups[#frame.groups + 1] = { key = key, index = #items + 1, t = list[#list] and list[#list].t }
		if open then
			local sentence = #facts > 0 and table.concat(facts, " · ") or moments
			items[#items + 1] = { kind = "chapter", key = key, level = type(level) == "number" and level or "?", title = title,
				sentence = sentence, current = isCurrent, now = isCurrent, open = true, spine = spineInfo,
				onToggle = function() frame:Draw(true) end }
			local story = type(level) == "number" and stories[level] or nil
			if story and story.opening then
				items[#items + 1] = { kind = "journey_story", text = story.opening, indent = K.CHAPTER_INDENT, spine = true, story = "opening" }
				frame.storyShown = frame.storyShown + 1
			end
			local newest, total = Cut(frame, key, Newest(list))
			local moment = A:JourneyItems(newest, ItemOpts(frame, { indent = K.CHAPTER_INDENT, spine = position < chapters }))
			for _, item in ipairs(moment) do items[#items + 1] = item end
			if total then More(frame, key, total, items, K.CHAPTER_INDENT, position < chapters) end
			if story and story.closing then
				items[#items + 1] = { kind = "journey_story", text = story.closing, indent = K.CHAPTER_INDENT,
					spine = position < chapters, story = "closing" }
				frame.storyShown = frame.storyShown + 1
			end
		else
			local meta = { moments }
			items[#items + 1] = { kind = "chapterClosed", key = key, level = type(level) == "number" and level or "?",
				title = zone or title, meta = table.concat(meta, " · "), time = seconds and Fmt.Span(seconds) or "",
				current = isCurrent, open = false, spine = spineInfo, onToggle = function() frame:Draw(true) end }
		end
	end
	for position, level in ipairs(levels) do Chapter(position, level, byLevel[level]) end
	if #other > 0 then Chapter(chapters, "other", other) end
	return items
end

-- Day and zone views: one fold per group, the newest three open.
local function ByGroup(frame, rows, view)
	local groups, order = {}, {}
	local otherKey = view .. ":other"
	for _, row in ipairs(rows) do
		local key
		if view == "day" then
			key = type(row.t) == "number" and ("day:" .. Fmt.DayKey(row.t)) or otherKey
		else
			local zone = Text(row.zone)
			key = zone and ("zone:" .. zone) or otherKey
		end
		local group = groups[key]
		if not group then
			group = { key = key, rows = {}, last = 0 }
			groups[key] = group
			order[#order + 1] = group
		end
		group.rows[#group.rows + 1] = row
		group.last = math.max(group.last, tonumber(row.t) or 0)
		group.zone = group.zone or Text(row.zone)
		group.t = group.t or row.t
	end
	table.sort(order, function(a, b)
		if (a.key == otherKey) ~= (b.key == otherKey) then return b.key == otherKey end
		return a.last > b.last
	end)
	local filtered = Filtered(frame)
	local items = {}
	frame.groups = {}
	for position, group in ipairs(order) do
		local stateKey = "journey:" .. group.key
		local open = filtered or K.FoldOpen(stateKey, position <= 3)
		local label
		if group.key == otherKey then
			label = L["Other"]
		elseif view == "day" then
			label = Fmt.Day(group.t)
		else
			label = group.zone
		end
		local count = #group.rows
		frame.groups[#frame.groups + 1] = { key = stateKey, index = #items + 1, t = group.last, day = view == "day" and Fmt.DayKey(group.t) or nil }
		items[#items + 1] = { kind = "fold", key = stateKey, label = label, open = open,
			note = E:Plural(count, "%d moment", "%d moments"):format(count),
			onToggle = function() frame:Draw(true) end }
		if open then
			items[#items + 1] = { kind = "space", height = 4 }
			local newest, total = Cut(frame, stateKey, Newest(group.rows))
			local list = A:JourneyItems(newest, ItemOpts(frame, { time = view == "day" and "clock" or "date" }))
			for _, item in ipairs(list) do items[#items + 1] = item end
			if total then More(frame, stateKey, total, items, 0) end
		end
		items[#items + 1] = { kind = "space", height = 6 }
	end
	return items
end

-- Pinned notes (A.Notes:Pinned()) in a fold above the story, while no
-- search or filter is on.
PinnedFirst = function(frame, items)
	frame.pinnedCount = 0
	if Filtered(frame) then return items end
	local list = A:PinnedNotes()
	local notes = {}
	for _, note in ipairs(list or {}) do
		-- Archived ones too: a pinned note stays until it is deleted (Notes.lua).
		if type(note) == "table" and Text(note.text) then notes[#notes + 1] = note end
	end
	if #notes == 0 then return items end
	frame.pinnedCount = #notes
	local key = "journey:pinned"
	local open = K.FoldOpen(key, true)
	local out = { { kind = "fold", key = key, label = L["Pinned notes"], open = open, note = tostring(#notes),
		onToggle = function() frame:Draw(true) end } }
	if open then
		out[#out + 1] = { kind = "space", height = 4 }
		for _, note in ipairs(notes) do
			local when = tonumber(note.t or note.created)
			local where = Text(note.zone)
			local sub = when and Fmt.Short(when) or ""
			if where then sub = sub ~= "" and ("%s · %s"):format(where, sub) or where end
			out[#out + 1] = { kind = "note", text = note.text, sub = sub, pinned = true }
			out[#out + 1] = { kind = "space", height = 4 }
		end
	end
	out[#out + 1] = { kind = "space", height = 8 }
	-- The groups (Jump to date, a chapter) move down by the fold.
	for _, group in ipairs(frame.groups or {}) do group.index = group.index + #out end
	for _, item in ipairs(items) do out[#out + 1] = item end
	return out
end

local function HeaderText(frame)
	local name = Plain(UnitName("player"))
	frame.header:SetTitle(Text(name) or L["Journey"])
	local race = Plain(UnitRace("player"))
	local class = Plain(UnitClass("player"))
	local level = CurrentLevel()
	local who = {}
	if Text(race) then who[#who + 1] = race end
	if Text(class) then who[#who + 1] = class end
	local sentence = ""
	if #who > 0 and level then
		sentence = (L["%s, level %s."]):format(table.concat(who, " "), K.Num(level))
	elseif level then
		sentence = (L["Level %s."]):format(K.Num(level))
	end
	local rec = J:Char()
	if rec and type(rec.started) == "number" then
		sentence = (sentence ~= "" and (sentence .. " ") or "") .. (L["A journal kept since %s."]):format(Fmt.Long(rec.started))
	end
	frame.header:SetSentence(sentence)
end

local function UpdateControls(frame)
	local state = UIState()
	frame.switch:SetActive(View())
	local group = state.group or "all"
	frame.filters:SetSelected(group)
	local open = frame.filterOpen or group ~= "all"
	frame.filterToggle:SetOn(open)
	frame.filters:SetShown(open)
	frame.zoneToggle:SetLabel(frame.zone and (L["Zone: %s"]):format(frame.zone) or L["Zone: All"])
	frame.zoneToggle:SetOn(frame.zone ~= nil)
	frame.list:ClearAllPoints()
	frame.list:SetPoint("TOPLEFT", 0, open and (FILTER_Y - 26) or (CONTROLS_Y - 28))
	frame.list:SetPoint("BOTTOMRIGHT")
end

local function EmptyText(frame)
	if Filtered(frame) then
		return L["Nothing matches"], L["No moment in the journal matches that search or filter."], {
			{ L["Clear the filters"], function() frame:ClearFilters() end } }
	end
	if frame.partial then
		return L["The journal waits for the end of combat"], L["Some of your records are read out of combat. They show in a moment."]
	end
	local level = CurrentLevel()
	local cap = tonumber(Plain(GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion())) or 60
	if level and level >= cap then
		return L["The first page is still blank"], L["Runs, first kills, finds, and standings are written here as they happen."]
	end
	return L["The first page is still blank"], L["Go and explore. Levels, places, first kills, and finds are written here as they happen."]
end

local function Build(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetAllPoints()
	frame.expanded = {}
	frame.header = K.Header(frame)
	frame.header:SetPoint("TOPLEFT")
	frame.header:SetPoint("TOPRIGHT")
	frame.header:SetActions({ { L["Jump to date"], function(button) frame:JumpMenu(button) end,
		L["Opens the day you pick in the day view."] } })

	frame.switch = K.Switch(frame, VIEWS, View(), function(view)
		if A.db then A.db.journeyBy = view end
		frame:Draw()
	end)
	frame.switch:SetPoint("TOPLEFT", 0, CONTROLS_Y)
	frame.zoneToggle = LG.PageKit.Toggle(frame, L["Zone: All"], function(button) frame:ZoneMenu(button) end,
		L["Zone"], L["Only the moments of one zone. Right-click shows every zone again."])
	frame.zoneToggle:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	frame.zoneToggle:SetScript("OnClick", function(button, mouse)
		if mouse == "RightButton" then frame:SetZone(nil) else frame:ZoneMenu(button) end
	end)
	frame.zoneToggle:SetPoint("TOPRIGHT", 0, CONTROLS_Y)
	frame.filterToggle = LG.PageKit.Toggle(frame, L["Filter"], function()
		frame.filterOpen = not frame.filterOpen
		if not frame.filterOpen then UIState().group = "all" end
		frame:Draw()
	end, L["Filter"], L["Show one kind of moment: growth, gear, deeds, places, people, or notes."])
	frame.filterToggle:SetPoint("RIGHT", frame.zoneToggle, "LEFT", -8, 0)
	frame.search = K.Search(frame, KEY, L["Search the journal"], function() frame:Draw() end)
	frame.search:SetPoint("LEFT", frame.switch, "RIGHT", 12, 0)
	frame.search:SetPoint("RIGHT", frame.filterToggle, "LEFT", -8, 0)
	frame.filters = E.UIKit.ChipBar(frame, { chips = FILTERS, selected = "all", onChange = function(selected)
		local key = next(selected) or "all"
		UIState().group = key
		frame:Draw()
	end })
	frame.filters:SetPoint("TOPLEFT", 0, FILTER_Y)
	frame.list = K.CreateJournalList(frame, { empty = { L["The first page is still blank"], "", A.HUB_ICON } })

	function frame:Draw(keepScroll)
		if not self:IsShown() then
			self.dirty = true
			return
		end
		self.dirty = false
		local started = debugprofilestop()
		HeaderText(self)
		UpdateControls(self)
		local rows = Rows(self)
		self.rowCount = #rows
		local view = View()
		local items
		if view == "level" then items = ByLevel(self, rows) else items = ByGroup(self, rows, view) end
		items = PinnedFirst(self, items)
		self.items = items
		local title, text, buttons = EmptyText(self)
		self.list:SetEmpty(title, text, A.HUB_ICON, buttons)
		self.list:SetData(items, keepScroll)
		self.buildMs = debugprofilestop() - started
	end

	function frame:ClearFilters()
		UIState().group = "all"
		self.filterOpen = false
		self.zone = nil
		self.search:SetText("")
		self.search:GetScript("OnTextChanged")(self.search, true)
		self:Draw()
	end

	function frame:SetView(view)
		if A.db then A.db.journeyBy = (view == "day" or view == "zone") and view or "level" end
		self:Draw()
	end

	function frame:SetGroup(group)
		UIState().group = group or "all"
		self.filterOpen = group ~= nil and group ~= "all"
		self:Draw()
	end

	function frame:SetZone(zone)
		self.zone = Text(zone)
		self:Draw()
	end

	function frame:SetSearch(text)
		self.search:SetText(text or "")
		self.search:GetScript("OnTextChanged")(self.search, true)
	end

	-- Zones with moments, most first.
	function frame:Zones()
		local counts, list = {}, {}
		for _, row in ipairs(J:Timeline()) do
			local zone = Text(row.zone)
			if zone then
				if not counts[zone] then list[#list + 1] = zone end
				counts[zone] = (counts[zone] or 0) + 1
			end
		end
		table.sort(list, function(a, b)
			if counts[a] ~= counts[b] then return counts[a] > counts[b] end
			return a < b
		end)
		return list, counts
	end

	function frame:ZoneMenu(owner)
		E.UIKit.ContextMenu(owner or self, function(_, root) self:FillZoneMenu(root) end, { at = "owner" })
	end

	function frame:FillZoneMenu(root)
		root:CreateTitle(L["Zone"])
		root:CreateButton(L["Every zone"], function() self:SetZone(nil) end)
		local list, counts = self:Zones()
		for index, zone in ipairs(list) do
			if index > 30 then break end
			root:CreateButton(("%s  (%d)"):format(zone, counts[zone]), function() self:SetZone(zone) end)
		end
	end

	-- Days with moments, newest first: { key, t, count }.
	function frame:Days()
		local byDay, list = {}, {}
		for _, row in ipairs(J:Timeline()) do
			if type(row.t) == "number" then
				local key = Fmt.DayKey(row.t)
				local day = byDay[key]
				if not day then
					day = { key = key, t = row.t, count = 0 }
					byDay[key] = day
					list[#list + 1] = day
				end
				day.count = day.count + 1
			end
		end
		table.sort(list, function(a, b) return a.key > b.key end)
		return list
	end

	function frame:JumpMenu(owner)
		E.UIKit.ContextMenu(owner or self, function(_, root) self:FillJumpMenu(root) end, { at = "owner" })
	end

	-- The last 20 days you played, then one entry per older month.
	function frame:FillJumpMenu(root)
		root:CreateTitle(L["Jump to date"])
		local days = self:Days()
		if #days == 0 then
			root:CreateTitle(L["No days yet"])
			return
		end
		local months, monthOrder = {}, {}
		for index, day in ipairs(days) do
			if index <= 20 then
				root:CreateButton(("%s  (%d)"):format(Fmt.Day(day.t), day.count), function() self:JumpTo(day.key) end)
			else
				local month = day.key:sub(1, 7)
				if not months[month] then
					months[month] = day
					monthOrder[#monthOrder + 1] = month
				end
			end
		end
		for _, month in ipairs(monthOrder) do
			local day = months[month]
			root:CreateButton(Fmt.Long(day.t):gsub(" %d+,", ","):gsub(" %d+$", ""), function() self:JumpTo(day.key) end)
		end
	end

	-- Opens the day view on a day ("2026-10-08"), or the newest day before it.
	function frame:JumpTo(dayKey)
		if type(dayKey) ~= "string" then return false end
		if A.db then A.db.journeyBy = "day" end
		local target
		for _, day in ipairs(self:Days()) do
			if day.key <= dayKey then
				target = day.key
				break
			end
		end
		if not target then return false end
		K.SetFoldOpen("journey:day:" .. target, true)
		self:Draw()
		for _, group in ipairs(self.groups or {}) do
			if group.day == target then
				self.list:ScrollTo(group.index, "top")
				self.jumped = target
				return true
			end
		end
		return false
	end

	-- Scroll to one moment (an address "journal:moment:<seq>").
	function frame:ShowMoment(seq)
		seq = tonumber(seq)
		if not seq then return false end
		local row
		for _, each in ipairs(J:Timeline()) do
			if each.src == "journal" and each.seq == seq then row = each end
		end
		if not row then return false end
		local key
		if View() == "level" then
			key = "journey:level:" .. tostring(row.level or "other")
		elseif View() == "day" then
			key = "journey:day:" .. (type(row.t) == "number" and Fmt.DayKey(row.t) or "other")
		else
			key = "journey:zone:" .. (Text(row.zone) or "other")
		end
		K.SetFoldOpen(key, true)
		self.expanded[key] = true
		local function Find()
			for index, item in ipairs(self.items or {}) do
				local shown = item.row
				if shown == row or (shown and shown.src == "journal" and shown.seq == seq) then return index end
				for _, boss in ipairs(item.kind == "victory" and item.rows or {}) do
					if boss.seq == seq then return index end
				end
			end
		end
		self:Draw()
		local index = Find()
		-- Hidden by a search or filter: show everything and look again.
		if not index and Filtered(self) then
			self:ClearFilters()
			index = Find()
		end
		if not index then return false end
		self.list:ScrollTo(index, "center")
		self.shownMoment = seq
		return true
	end

	-- The level view on one chapter, open and at the top (the river, the
	-- Book and Today link here with { level = n }).
	function frame:ShowLevel(level)
		level = tonumber(level)
		if not level then return false end
		if A.db then A.db.journeyBy = "level" end
		local key = "journey:level:" .. tostring(level)
		K.SetFoldOpen(key, true)
		self:Draw()
		local function Find()
			for _, group in ipairs(self.groups or {}) do
				if group.key == key then return group.index end
			end
		end
		local index = Find()
		-- Hidden by a search or filter: show everything and look again.
		if not index and Filtered(self) then
			self:ClearFilters()
			index = Find()
		end
		if not index then return false end
		self.list:ScrollTo(index, "top")
		self.shownLevel = level
		return true
	end

	-- An address no page opens (a goal or note before its page exists):
	-- the newest moment that links to it.
	function frame:ShowAddress(address)
		local rows = J:Timeline()
		for index = #rows, 1, -1 do
			local row = rows[index]
			if row.src == "journal" and row.seq and J:LinkFor(row) == address then return self:ShowMoment(row.seq) end
		end
		return false
	end

	frame:SetScript("OnShow", function(self) if self.dirty then self:Draw(true) end end)
	return frame
end

local function Show(frame, arg)
	if type(arg) == "table" then
		if arg.search then frame:SetSearch(arg.search) end
		if arg.zone then frame.zone = Text(arg.zone) end
		if arg.view then frame:SetView(arg.view) end
	end
	frame:Draw(true)
	if type(arg) == "table" then
		if arg.seq then frame:ShowMoment(arg.seq) end
		if arg.level then frame:ShowLevel(arg.level) end
		if arg.day then frame:JumpTo(arg.day) end
		if arg.address then frame:ShowAddress(arg.address) end
	end
end

local function Refresh(frame, changed)
	if changed.adventure or changed.settings or changed.items or changed.data then frame:Draw(true) end
end

A:RegisterSection(KEY, {
	title = "Journey",
	icon = "Interface\\Icons\\INV_Misc_Book_09",
	desc = "Your story as it happened: chapters by level, day, or zone, with keepsakes, finds, and pinned notes.",
	words = { "journey", "timeline", "diary" },
	build = Build,
	show = Show,
	refresh = Refresh,
})

-- The Journey's own rows on the options page (Journal tab). Options.lua
-- loads after this file, so the rows join at init.
local optionsAdded = false
A:AddPart("journeyOptions", { order = 90, init = function()
	if optionsAdded or type(A.AddOptionRows) ~= "function" then return end
	optionsAdded = true
	A:AddOptionRows("journal", {
		{ type = "header", label = L["Journey page"] },
		{ type = "toggle", key = "riverStrip", label = L["Level river on the Journey"],
			desc = L["A strip over the chapters with a mark for each level and its big moments. Click a level to open its chapter. Shown in the level view while no search or filter is on."] },
		{ type = "toggle", key = "storyLines", label = L["Story lines in chapters"],
			desc = L["A line from your story under each chapter title and another after its moments, told in the tone you picked on the Story tab. Level view only."] },
	})
end })
