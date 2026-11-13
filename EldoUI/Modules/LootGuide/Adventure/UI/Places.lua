-- EldoUI My Adventure: the Places section, the places gallery and place
-- pages in the Journal window's look.
--
--   Places                                              [Open the Journey]
--   14 places so far, and the road goes on.
--   -----------------------------------------------------------------------
--   [All][Zones][Dungeons]  [Most time][Latest][First]  [ Search places  ]
--   +-----------------------------+ +-----------------------------+
--   | Westfall                    | | Elwynn Forest               |
--   | First came here Sep 14, l 9 | | Where it began              |
--   | [=========-----]     7 / 12 | | [==============]    3h 20m  |
--   | 3h 20m · 140 kills · 21 q.  | | 1h 05m · 40 kills · 9 q.    |
--   +-----------------------------+ +-----------------------------+
--   DUNGEONS  4 --------------------------------------------------- v
--   [ic] The Deadmines   3 runs, 2h 05m inside. First Oct 3.
--
-- A place page (a zone): the tally (foes bested, quests handed in, falls,
-- time, corners), what Zone Info knows of it (levels, territory, the
-- dungeons there), its corners (the Explore achievement's list where the
-- game has one, else the subzones you found), the quests you handed in
-- there, your notes written there, what you gathered there and everything
-- that happened there. A dungeon card opens the dungeon's history (the
-- same view as the History tab on the Dungeons page, UI/History.lua).
--
-- Every number is a fact the journal or another EldoUI module wrote down:
-- time from the journal's ticker, kills from the game's statistic or the
-- XP lines that name a creature, runs from Instances. Nothing is guessed.
--
-- Routes: show(frame, arg) with nil (the gallery), { place = zone },
-- { dungeon = name }, { search = text }, { show = "zones"|"dungeons" };
-- the address "journal:place:<zone>" opens a place page.
--
-- Shared page parts for Places, Quests, Fellowship and History
-- (A.LogPages, this file loads first of them):
--   LP.Page(parent, opts)       header, back link, controls, journal list
--   LP.Words(text), LP.Hits(folded, words), LP.Text(value)
--   LP.ClassColor(class), LP.ClassIcon(class), LP.ClassName(class)
--   LP.Money(copper), LP.Count(n, one, other)
--   LP.SPLIT, LP.SplitParts(split), LP.SplitTip(tooltip, split, total)
--   list row kinds added to E.AdventureKit.ROWS:
--     akCards    two cards side by side   { cards = { data, data }, height }
--     akStats    a tally across the page  { stats = { { value, label, onClick, tip } } }
--     akText     a wrapped line           { text, role, size, indent }
--     akSplit    a split bar with legend  { parts = { { value, color, label } } }
--     akCorners  two corners per row      { cells = { { name, done, time } } }
--
-- Portions adapted from Forever Journal by Ugge Zen, MIT License (see
-- THIRD_PARTY_NOTICES.md): the places gallery, the place page with its
-- tally, corners, quests, notes and events, and their texts.
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

local KEY = "places"
local ICON = "Interface\\Icons\\INV_Misc_Map_01"
local DUNGEON_ICON = "Interface\\Icons\\INV_Misc_Key_03"
local CONTROLS_Y = -(K.HEADER_HEIGHT + 8)
local CARD_GAP = 12
local ZONE_CARD, DUNGEON_CARD = 92, 60
local EVENT_CAP = 120

---------------------------------------------------------------------------
-- Shared page parts (A.LogPages)
---------------------------------------------------------------------------
local LP = {}
A.LogPages = LP

local function Text(value)
	if E:IsSecret(value) or type(value) ~= "string" or value == "" then return nil end
	return value
end
LP.Text = Text

function LP.Words(query)
	local words = {}
	for word in E:FoldText(query or ""):gmatch("%S+") do words[#words + 1] = word end
	return words
end

function LP.Hits(folded, words)
	for _, word in ipairs(words) do
		if not folded:find(word, 1, true) then return false end
	end
	return true
end

function LP.Count(n, one, other)
	n = tonumber(n) or 0
	return E:Plural(n, one, other):format(K.Num(BreakUpLargeNumbers(n)))
end

function LP.Money(copper)
	copper = tonumber(copper)
	if not copper or copper <= 0 then return nil end
	local P = LG.PageKit
	return P and P.MoneyText and P.MoneyText(copper) or nil
end

-- The class color, icon and name of a class file token ("MAGE").
function LP.ClassColor(class)
	if type(class) ~= "string" or E:IsSecret(class) or class == "" then return nil end
	-- E:ClassColorObject: custom class colors, the game's otherwise.
	local color = E:ClassColorObject(class)
	if color then return { color.r, color.g, color.b } end
	return nil
end

function LP.ClassIcon(class)
	if type(class) ~= "string" or E:IsSecret(class) or class == "" then return "Interface\\Icons\\INV_Misc_QuestionMark" end
	local atlas = rawget(_G, "GetClassAtlas") and GetClassAtlas(class:lower())
	if type(atlas) == "string" and LG.Kit.HasAtlas(atlas) then return atlas end
	return "Interface\\Icons\\ClassIcon_" .. class
end

function LP.ClassName(class)
	if type(class) ~= "string" or E:IsSecret(class) then return nil end
	local names = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
	return type(names) == "table" and names[class] or (class:sub(1, 1) .. class:sub(2):lower())
end

-- The time split of a companion: parts in the kit's inks, each with a word
-- (the color is never the only cue).
LP.SPLIT = {
	{ "dungeon", Key("Dungeons"), "accent" },
	{ "fight", Key("Fighting"), "bad" },
	{ "travel", Key("Traveling"), "warn" },
	{ "town", Key("In town"), "good" },
}

function LP.SplitParts(split)
	local parts = {}
	split = type(split) == "table" and split or {}
	for _, def in ipairs(LP.SPLIT) do
		parts[#parts + 1] = { tonumber(split[def[1]]) or 0, color = K.Ink(def[3]), label = L[def[2]] }
	end
	return parts
end

function LP.SplitTip(tooltip, split, total)
	split = type(split) == "table" and split or {}
	for _, def in ipairs(LP.SPLIT) do
		local seconds = tonumber(split[def[1]]) or 0
		if seconds > 0 then
			local c = K.Ink(def[3])
			tooltip:AddDoubleLine(L[def[2]], Fmt.Span(seconds), c[1], c[2], c[3], unpack(T.text.body))
		end
	end
	if tonumber(total) and total > 0 then
		tooltip:AddDoubleLine(L["Together"], Fmt.Span(total), unpack(T.text.body))
	end
end

---------------------------------------------------------------------------
-- List rows of the log pages
---------------------------------------------------------------------------
local ROWS = K.ROWS

-- Two cards per row. make(parent) builds one card, set(card, data) fills it.
local function CardRow(make, set)
	return {
		height = function(item) return (item.height or ZONE_CARD) + CARD_GAP end,
		create = function(row)
			row:EnableMouse(false)
			row.cards = { make(row), make(row) }
		end,
		update = function(row, item, width)
			width = width or row:GetWidth() or 0
			local x = item.indent or 0
			local cardWidth = math.floor((width - x - CARD_GAP) / 2)
			for index, card in ipairs(row.cards) do
				local data = item.cards and item.cards[index]
				card:SetShown(data ~= nil)
				if data then
					card:ClearAllPoints()
					card:SetPoint("TOPLEFT", row, "TOPLEFT", x + (index - 1) * (cardWidth + CARD_GAP), 0)
					card:SetSize(math.max(cardWidth, 1), item.height or ZONE_CARD)
					set(card, data)
				end
			end
		end,
	}
end
LP.CardRow = CardRow

ROWS.akCards = CardRow(function(row) return K.InfoCard(row) end, function(card, data) card:Set(data) end)

-- A tally across the page: big numbers with their labels, in one card.
ROWS.akStats = {
	height = function() return 58 + 8 end,
	create = function(row)
		row:EnableMouse(false)
		row.card = K.Card(row, { solid = true })
		row.cells = {}
	end,
	update = function(row, item, width)
		width = width or row:GetWidth() or 0
		local x = item.indent or 0
		row.card:ClearAllPoints()
		row.card:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
		row.card:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 8)
		local stats = item.stats or {}
		local count = math.max(#stats, 1)
		local cellWidth = math.floor((width - x - 2 * K.CARD_INSET) / count)
		for index = 1, math.max(#row.cells, #stats) do
			local data = stats[index]
			local cell = row.cells[index]
			if data and not cell then
				cell = CreateFrame("Button", nil, row.card)
				cell:RegisterForClicks("LeftButtonUp")
				cell.hover = cell:CreateTexture(nil, "HIGHLIGHT")
				cell.hover:SetAllPoints()
				cell.hover:SetColorTexture(1, 1, 1, T.hover.row)
				cell.value = K.Text(cell, 18, "LEFT", "body", true)
				cell.value:SetPoint("TOPLEFT", 8, -8)
				cell.value:SetPoint("TOPRIGHT", -4, -8)
				cell.value:SetWordWrap(false)
				cell.label = K.Text(cell, K.size.small, "LEFT", "secondary")
				cell.label:SetPoint("TOPLEFT", cell.value, "BOTTOMLEFT", 0, -4)
				cell.label:SetPoint("TOPRIGHT", cell.value, "BOTTOMRIGHT", 0, -4)
				cell.label:SetWordWrap(false)
				row.cells[index] = cell
			end
			if cell then
				cell:SetShown(data ~= nil)
				if data then
					cell:ClearAllPoints()
					cell:SetPoint("TOPLEFT", row.card, "TOPLEFT", K.CARD_INSET + (index - 1) * cellWidth, -2)
					cell:SetSize(math.max(cellWidth, 1), 54)
					cell.value:SetText(data[1] ~= nil and tostring(data[1]) or "")
					K.Paint(cell.value, data[1] == nil and "dim" or "body")
					cell.label:SetText(data[2] or "")
					cell:SetScript("OnClick", data[3])
					cell.hover:SetShown(data[3] ~= nil)
					cell:EnableMouse(data[3] ~= nil or data[4] ~= nil)
					LG.Kit.Tooltip(cell, data[4] and data[2], data[4])
				end
			end
		end
	end,
}

-- A wrapped line of text (facts, an empty fold's note).
ROWS.akText = {
	height = function(item, width)
		local x = (item.indent or 0) + 4
		return E.UIKit.TextHeight(item.text or "", math.max(width - x - 4, 1), item.size or K.size.small) + 8
	end,
	create = function(row)
		row:RegisterForClicks("LeftButtonUp")
		row.text = K.Text(row, K.size.small, "LEFT", "secondary")
		row.text:SetWordWrap(true)
	end,
	update = function(row, item)
		row.text:ClearAllPoints()
		row.text:SetPoint("TOPLEFT", (item.indent or 0) + 4, -4)
		row.text:SetPoint("TOPRIGHT", -4, -4)
		K.InkFont(row.text, item.size or K.size.small)
		row.text:SetText(item.text or "")
		K.Paint(row.text, item.role or "secondary")
		row:SetScript("OnClick", item.onClick and function() item.onClick(item) end or nil)
		row:EnableMouse(item.onClick ~= nil or item.tip ~= nil)
		LG.Kit.Tooltip(row, item.tip and (item.tipTitle or item.text), item.tip)
	end,
}

-- A split bar (12 px) with its legend under it.
ROWS.akSplit = {
	height = function() return 12 + 6 + 16 + 8 end,
	create = function(row)
		row:EnableMouse(true)
		row.bar = K.SplitBar(row, 12)
		row.legend = {}
	end,
	update = function(row, item)
		local x = item.indent or 0
		row.bar:ClearAllPoints()
		row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", x, -2)
		row.bar:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -2)
		row.bar:SetParts(item.parts or {})
		local anchor
		local parts = item.parts or {}
		for index = 1, math.max(#row.legend, #parts) do
			local part = parts[index]
			local key = row.legend[index]
			if part and not key then
				key = CreateFrame("Frame", nil, row)
				key:SetSize(10, 14)
				key.swatch = key:CreateTexture(nil, "ARTWORK")
				key.swatch:SetSize(8, 8)
				key.swatch:SetPoint("LEFT", 0, 0)
				key.text = K.Text(key, K.size.small, "LEFT", "secondary")
				key.text:SetPoint("LEFT", key.swatch, "RIGHT", 4, 0)
				row.legend[index] = key
			end
			if key then
				key:SetShown(part ~= nil)
				if part then
					local c = part.color or K.Ink("secondary")
					key.swatch:SetColorTexture(c[1], c[2], c[3], 1)
					local seconds = tonumber(part[1] or part.value) or 0
					key.text:SetText(("%s %s"):format(part.label or "", seconds > 0 and Fmt.Span(seconds) or "-"))
					key:SetWidth(12 + math.ceil(key.text:GetStringWidth()))
					key:ClearAllPoints()
					if anchor then
						key:SetPoint("LEFT", anchor, "RIGHT", 16, 0)
					else
						key:SetPoint("TOPLEFT", row, "TOPLEFT", x, -20)
					end
					anchor = key
				end
			end
		end
		LG.Kit.Tooltip(row, item.tipTitle, item.tip)
	end,
}

-- Corners: two per row, a square (filled when explored), the name and the
-- time you spent there.
local function Corner(parent)
	local cell = CreateFrame("Frame", nil, parent)
	cell.mark = cell:CreateTexture(nil, "ARTWORK")
	cell.mark:SetSize(8, 8)
	cell.mark:SetPoint("LEFT", 2, 0)
	cell.name = K.Text(cell, K.size.body, "LEFT", "body")
	cell.name:SetPoint("LEFT", cell.mark, "RIGHT", 8, 0)
	cell.name:SetWordWrap(false)
	cell.time = K.Text(cell, K.size.small, "RIGHT", "secondary")
	cell.time:SetPoint("RIGHT", -4, 0)
	cell.name:SetPoint("RIGHT", cell.time, "LEFT", -8, 0)
	return cell
end

ROWS.akCorners = {
	height = function() return 22 end,
	create = function(row)
		row:EnableMouse(false)
		row.cells = { Corner(row), Corner(row) }
	end,
	update = function(row, item, width)
		width = width or row:GetWidth() or 0
		local x = (item.indent or 0) + K.CARD_INSET
		local cellWidth = math.floor((width - x - K.CARD_INSET) / 2)
		for index, cell in ipairs(row.cells) do
			local data = item.cells and item.cells[index]
			cell:SetShown(data ~= nil)
			if data then
				cell:ClearAllPoints()
				cell:SetPoint("LEFT", row, "LEFT", x + (index - 1) * (cellWidth + 8), 0)
				cell:SetSize(math.max(cellWidth - 8, 1), 20)
				local c = data.done and K.Ink("good") or K.Ink("dim")
				cell.mark:SetColorTexture(c[1], c[2], c[3], data.done and 1 or 0.6)
				cell.name:SetText(data.name or "")
				K.Paint(cell.name, data.done and "body" or "dim")
				cell.time:SetText(data.time or (data.done and "" or L["Not yet explored"]))
				K.Paint(cell.time, data.done and "secondary" or "dim")
			end
		end
	end,
}

---------------------------------------------------------------------------
-- A log page: header, back link or controls, the list
--   LP.Page(parent, { key, controls = fn(frame, bar), controlsHeight,
--     empty = { title, text, icon } })
--   frame:SetDetail(label, onBack)   the back link instead of the controls
--   frame:SetDetail(nil)             the controls again
---------------------------------------------------------------------------
function LP.Page(parent, opts)
	opts = opts or {}
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetAllPoints()
	frame.header = K.Header(frame)
	frame.header:SetPoint("TOPLEFT")
	frame.header:SetPoint("TOPRIGHT")
	frame.controls = CreateFrame("Frame", nil, frame)
	frame.controls:SetPoint("TOPLEFT", 0, CONTROLS_Y)
	frame.controls:SetPoint("TOPRIGHT", 0, CONTROLS_Y)
	frame.controls:SetHeight(opts.controlsHeight or 20)
	frame.back = LG.PageKit.Back(frame, L["Back"], function()
		if frame.onBack then frame.onBack() end
	end)
	frame.back:SetPoint("TOPLEFT", 0, CONTROLS_Y)
	frame.back:Hide()
	frame.list = K.CreateJournalList(frame, { empty = opts.empty or { L["Nothing to show yet"], "", ICON } })
	if opts.controls then opts.controls(frame, frame.controls) end

	function frame:SetDetail(label, onBack)
		self.detail = label ~= nil
		self.onBack = onBack
		self.controls:SetShown(not self.detail)
		self.back:SetShown(self.detail)
		if self.detail then self.back:SetLabel(label) end
		self.list:ClearAllPoints()
		if self.detail then
			self.list:SetPoint("TOPLEFT", self.back, "BOTTOMLEFT", 0, -8)
		else
			self.list:SetPoint("TOPLEFT", self.controls, "BOTTOMLEFT", 0, -10)
		end
		self.list:SetPoint("BOTTOMRIGHT")
	end
	frame:SetDetail(nil)
	return frame
end

-- A fold item and its rows: fold, rows (when open), a small gap.
function LP.AddFold(items, key, label, note, rows, defaultOpen, onToggle, forceOpen)
	local open = forceOpen or K.FoldOpen(key, defaultOpen ~= false)
	items[#items + 1] = { kind = "fold", key = key, label = label, note = note, open = open, onToggle = onToggle }
	if open then
		items[#items + 1] = { kind = "space", height = 4 }
		for _, row in ipairs(rows) do items[#items + 1] = row end
	end
	items[#items + 1] = { kind = "space", height = 8 }
end

-- Ledger items in one card (position first ... last).
function LP.Card(items, rows)
	local count = #rows
	for index, row in ipairs(rows) do
		row.kind = row.kind or "ledger"
		row.position = count == 1 and "only" or index == 1 and "first" or index == count and "last" or "middle"
		items[#items + 1] = row
	end
	return items
end

-- The rows of a fold as one ledger card, cut at `cap` with "Show all n".
function LP.Ledger(rows, cap, onMore)
	local out = {}
	local shown = rows
	if cap and #rows > cap then
		shown = {}
		for index = 1, cap do shown[index] = rows[index] end
	end
	LP.Card(out, shown)
	if shown ~= rows then
		out[#out + 1] = { kind = "more", text = (L["Show all %d"]):format(#rows), onClick = onMore }
	end
	return out
end

---------------------------------------------------------------------------
-- Places: the journal's zones (open world) and the dungeons (History.lua)
---------------------------------------------------------------------------
local function H()
	return A.History
end

local function Rec()
	return J:Char()
end

-- Names that are dungeons or raids (never a zone card).
local function InstanceNames(rec)
	local set = {}
	for name in pairs(type(rec and rec.instancesSeen) == "table" and rec.instancesSeen or {}) do set[name] = true end
	local history = H()
	for _, dungeon in ipairs(history and history.Dungeons() or {}) do set[dungeon.name] = true end
	return set
end

-- Corners of a zone: { { name, done, time, seconds } }, explored count, total
-- (total nil when the game lists no corners for it).
local function Corners(zone, place)
	local subs = type(place) == "table" and type(place.subs) == "table" and place.subs or {}
	local criteria = J.Explore and J:Explore(zone)
	local out, done, seen = {}, 0, {}
	for _, corner in ipairs(criteria or {}) do
		local sub = subs[corner.name]
		local seconds = type(sub) == "table" and tonumber(sub.t) or nil
		local explored = corner.done or sub ~= nil
		seen[corner.name] = true
		out[#out + 1] = { name = corner.name, done = explored, seconds = seconds or 0,
			time = explored and seconds and seconds > 0 and Fmt.Span(seconds) or nil }
		if explored then done = done + 1 end
	end
	for name, sub in pairs(subs) do
		if not seen[name] and type(sub) == "table" then
			local seconds = tonumber(sub.t) or 0
			out[#out + 1] = { name = name, done = true, seconds = seconds, time = seconds > 0 and Fmt.Span(seconds) or nil,
				first = tonumber(sub.first), level = tonumber(sub.level) }
			if not criteria then done = done + 1 end
		end
	end
	table.sort(out, function(a, b)
		if a.done ~= b.done then return a.done end
		if a.seconds ~= b.seconds then return a.seconds > b.seconds end
		return a.name < b.name
	end)
	return out, done, criteria and #criteria or nil
end
LP.Corners = Corners

-- Every open-world zone of the journal: { zone, place, first, time, ... }.
local function Zones()
	local rec = Rec()
	local list = {}
	if not rec then return list end
	local instances = InstanceNames(rec)
	local earliest
	for zone, place in pairs(rec.zones or {}) do
		if type(zone) == "string" and type(place) == "table" and not instances[zone] then
			local entry = { zone = zone, place = place, first = tonumber(place.first), level = tonumber(place.firstLevel),
				time = tonumber(place.t) or 0, kills = tonumber(place.kills) or 0, quests = tonumber(place.quests) or 0,
				deaths = tonumber(place.deaths) or 0, map = tonumber(place.map) }
			list[#list + 1] = entry
			if entry.first and (not earliest or entry.first < earliest.first) then earliest = entry end
		end
	end
	if rec.startedZone and rec.zones[rec.startedZone] then
		for _, entry in ipairs(list) do
			if entry.zone == rec.startedZone then earliest = entry end
		end
	end
	if earliest then earliest.began = true end
	return list
end
LP.Zones = Zones

local function Find(zone)
	for _, entry in ipairs(Zones()) do
		if entry.zone == zone then return entry end
	end
end

-- The stats line of a zone: "3h 20m · 140 kills · 21 quests · 2 deaths".
local function StatsLine(entry)
	local bits = {}
	if entry.time > 0 then bits[#bits + 1] = Fmt.Span(entry.time) end
	if entry.kills > 0 then bits[#bits + 1] = E:Plural(entry.kills, "%s kill", "%s kills"):format(BreakUpLargeNumbers(entry.kills)) end
	if entry.quests > 0 then bits[#bits + 1] = E:Plural(entry.quests, "%d quest", "%d quests"):format(entry.quests) end
	if entry.deaths > 0 then bits[#bits + 1] = E:Plural(entry.deaths, "%d death", "%d deaths"):format(entry.deaths) end
	return table.concat(bits, " · ")
end

local function FirstLine(entry)
	if entry.began then return L["Where it began"] end
	if entry.first and entry.level then return (L["First came here %s, level %d"]):format(Fmt.Short(entry.first), entry.level) end
	if entry.first then return (L["First came here %s"]):format(Fmt.Short(entry.first)) end
	return L["Visited before the journal kept dates"]
end

-- What Zone Info knows of a zone: levels, territory, dungeons there.
local function ZoneFacts(map)
	local Z = E.ZoneInfo
	if not (Z and map and Z.Levels) then return nil end
	local bits = {}
	local ok, low, high = pcall(Z.Levels, Z, map)
	if ok and low then bits[#bits + 1] = low == high and (L["Level %d"]):format(low) or (L["Levels %d-%d"]):format(low, high) end
	local okTerritory, territory = pcall(Z.Territory, Z, map)
	if okTerritory and territory and Z.TerritoryText then
		local text = Z:TerritoryText(territory)
		if text then bits[#bits + 1] = text end
	end
	local okInstances, instances = pcall(Z.Instances, Z, map)
	if okInstances and type(instances) == "table" and instances[1] then
		local names = {}
		for _, inst in ipairs(instances) do names[#names + 1] = inst.name end
		bits[#bits + 1] = (L["Dungeons here: %s"]):format(table.concat(names, ", "))
	end
	if #bits == 0 then return nil end
	return table.concat(bits, " · ")
end

---------------------------------------------------------------------------
-- Gallery
---------------------------------------------------------------------------
local SHOW = {
	{ "all", Key("All"), Key("Zones and dungeons.") },
	{ "zones", Key("Zones"), Key("Only the zones of the open world.") },
	{ "dungeons", Key("Dungeons"), Key("Only dungeons and raids.") },
}
local SORT = {
	{ "time", Key("Most time"), Key("The places you spent the most time in first.") },
	{ "recent", Key("Latest"), Key("The places you came to last first.") },
	{ "first", Key("First visit"), Key("In the order you first came there.") },
}
local SHOW_KEYS, SORT_KEYS = {}, {}
for _, entry in ipairs(SHOW) do SHOW_KEYS[entry[1]] = true end
for _, entry in ipairs(SORT) do SORT_KEYS[entry[1]] = true end

local function UIState()
	local rec = Rec()
	local ui = rec and rec.ui
	if type(ui) ~= "table" then
		LP.session = LP.session or {}
		ui = LP.session
	end
	if type(ui.places) ~= "table" then ui.places = {} end
	local s = ui.places
	if not SHOW_KEYS[s.show or ""] then s.show = "all" end
	if not SORT_KEYS[s.sort or ""] then s.sort = "time" end
	return s
end

local function Sorted(list, sort, timeOf, firstOf, lastOf)
	table.sort(list, function(a, b)
		local ka, kb
		if sort == "first" then
			ka, kb = -(firstOf(a) or math.huge), -(firstOf(b) or math.huge)
		elseif sort == "recent" then
			ka, kb = lastOf(a) or 0, lastOf(b) or 0
		else
			ka, kb = timeOf(a) or 0, timeOf(b) or 0
		end
		if ka ~= kb then return ka > kb end
		return tostring(a.zone or a.name) < tostring(b.zone or b.name)
	end)
	return list
end

-- The last time you were somewhere: the newest moment there, else the first visit.
local function LastSeen()
	local last = {}
	for _, row in ipairs(J:Timeline()) do
		local zone = Text(row.zone)
		if zone and type(row.t) == "number" then last[zone] = math.max(last[zone] or 0, row.t) end
	end
	return last
end

local function ZoneCard(frame, entry, top)
	local corners, done, total = Corners(entry.zone, entry.place)
	local progress, right
	if total and total > 0 then
		progress = { done, total }
		right = ("%d / %d"):format(done, total)
	else
		progress = { entry.time, math.max(top, 1) }
		right = entry.time > 0 and Fmt.Span(entry.time) or "-"
	end
	local tip = function(tooltip)
		tooltip:AddLine(FirstLine(entry), unpack(T.text.secondary))
		local stats = StatsLine(entry)
		if stats ~= "" then tooltip:AddLine(stats, unpack(T.text.body)) end
		if total then
			tooltip:AddLine(E:Plural(total, "%d of %d corner explored", "%d of %d corners explored"):format(done, total), unpack(T.text.secondary))
		elseif #corners > 0 then
			tooltip:AddLine(E:Plural(#corners, "%d corner found", "%d corners found"):format(#corners), unpack(T.text.secondary))
		end
		E:TooltipHint(tooltip, { L["Click"], L["open %s"]:format(entry.zone) })
	end
	return { title = entry.zone, lines = { FirstLine(entry), StatsLine(entry) }, progress = progress, right = right,
		onClick = function() frame:OpenPlace(entry.zone) end, tip = tip, zone = entry.zone }
end

local function DungeonCard(frame, dungeon)
	local bits = {}
	if dungeon.runs > 0 then bits[#bits + 1] = E:Plural(dungeon.runs, "%d run", "%d runs"):format(dungeon.runs) end
	if dungeon.inside > 0 then bits[#bits + 1] = (L["%s inside"]):format(Fmt.Span(dungeon.inside)) end
	local line = table.concat(bits, ", ")
	if dungeon.first then
		line = (line ~= "" and (line .. ". ") or "") .. (L["First %s."]):format(Fmt.Short(dungeon.first))
	end
	if line == "" then line = L["Entered before the journal kept runs."] end
	local beaten = dungeon.bossesBeaten or 0
	local tip = function(tooltip)
		tooltip:AddLine(line, unpack(T.text.secondary))
		if beaten > 0 then
			tooltip:AddLine(E:Plural(beaten, "%d boss beaten", "%d bosses beaten"):format(beaten), unpack(T.text.body))
		end
		E:TooltipHint(tooltip, { L["Click"], L["open %s"]:format(dungeon.name) })
	end
	return { icon = dungeon.icon or DUNGEON_ICON, title = dungeon.name, lines = { line, nil },
		right = dungeon.kind == "raid" and L["Raid"] or nil,
		onClick = function() frame:OpenDungeon(dungeon.name) end, tip = tip, dungeon = dungeon.name }
end

local function Pairs(items, cards, height)
	for index = 1, #cards, 2 do
		items[#items + 1] = { kind = "akCards", cards = { cards[index], cards[index + 1] }, height = height }
	end
end

local function GalleryMatches(entry, words, extra)
	if #words == 0 then return true end
	local text = entry.zone or entry.name or ""
	for name in pairs(extra or {}) do text = text .. " " .. name end
	return LP.Hits(E:FoldText(text), words)
end

local function DrawGallery(frame)
	local s = UIState()
	frame:SetDetail(nil)
	frame.place, frame.dungeon = nil, nil
	frame.show:SetActive(s.show)
	frame.sort:SetActive(s.sort)
	local zones = Zones()
	local history = H()
	local dungeons = history and history.Dungeons() or {}
	local words = LP.Words(K.Query(KEY))
	local last = (s.sort == "recent") and LastSeen() or {}

	local top = 0
	for _, entry in ipairs(zones) do top = math.max(top, entry.time) end
	local count = #zones + #dungeons
	frame.header:SetTitle(L["Places"])
	if count > 0 then
		frame.header:SetSentence(E:Plural(count, "%s place so far, and the road goes on.", "%s places so far, and the road goes on.")
			:format(K.Num(count)))
	else
		frame.header:SetSentence(L["Nowhere yet. The road is waiting."])
	end
	frame.header:SetActions(A:SectionShown("journey") and {
		{ L["Open the Journey"], function() A:OpenSection("journey") end, L["Your whole story, place by place."] } } or nil)
	frame.show:SetLabel("zones", #zones > 0 and (L["Zones"] .. " " .. K.InkHex("secondary") .. #zones .. "|r") or L["Zones"])
	frame.show:SetLabel("dungeons", #dungeons > 0 and (L["Dungeons"] .. " " .. K.InkHex("secondary") .. #dungeons .. "|r") or L["Dungeons"])

	local items = {}
	local shownZones, shownDungeons = {}, {}
	if s.show ~= "dungeons" then
		for _, entry in ipairs(zones) do
			if GalleryMatches(entry, words, entry.place.subs) then shownZones[#shownZones + 1] = entry end
		end
		Sorted(shownZones, s.sort, function(e) return e.time end, function(e) return e.first end,
			function(e) return last[e.zone] or e.first end)
		local cards = {}
		for _, entry in ipairs(shownZones) do cards[#cards + 1] = ZoneCard(frame, entry, top) end
		Pairs(items, cards, ZONE_CARD)
	end
	if s.show ~= "zones" then
		for _, dungeon in ipairs(dungeons) do
			if GalleryMatches(dungeon, words) then shownDungeons[#shownDungeons + 1] = dungeon end
		end
		Sorted(shownDungeons, s.sort, function(d) return d.inside end, function(d) return d.first end,
			function(d) return d.last or d.first end)
		local cards = {}
		for _, dungeon in ipairs(shownDungeons) do cards[#cards + 1] = DungeonCard(frame, dungeon) end
		if s.show == "all" then
			local open = #words > 0 or K.FoldOpen("places:dungeons", true)
			items[#items + 1] = { kind = "space", height = 4 }
			items[#items + 1] = { kind = "fold", key = "places:dungeons", label = L["Dungeons"], note = tostring(#shownDungeons),
				open = open, onToggle = function() frame:Draw(true) end }
			if open then
				items[#items + 1] = { kind = "space", height = 6 }
				if #cards == 0 then
					items[#items + 1] = { kind = "akText", text = #words > 0 and L["No dungeon matches that search."]
						or L["None braved yet. Each dungeon gets a card of its own, with runs and time inside."] }
				end
				Pairs(items, cards, DUNGEON_CARD)
			end
		else
			Pairs(items, cards, DUNGEON_CARD)
		end
	end
	frame.shownZones, frame.shownDungeons = shownZones, shownDungeons
	if #shownZones == 0 and #shownDungeons == 0 then items = {} end
	local emptyTitle, emptyText, buttons
	if count == 0 then
		emptyTitle, emptyText = L["Nowhere yet"], L["The road is waiting. Every zone you visit gets a card."]
	else
		emptyTitle, emptyText = L["Nothing matches"], L["No place matches that search or filter."]
		buttons = { { L["Clear the filters"], function() frame:ClearFilters() end } }
	end
	frame.list:SetEmpty(emptyTitle, emptyText, ICON, buttons)
	return items
end

---------------------------------------------------------------------------
-- A place page
---------------------------------------------------------------------------
local function QuestRows(zone)
	local rec = Rec()
	local rows = {}
	for index = #(rec and rec.quests or {}), 1, -1 do
		local quest = rec.quests[index]
		if type(quest) == "table" and quest.z == zone and not quest.archived then
			local title = Text(quest.title) or (L["Quest %d"]):format(tonumber(quest.id) or 0)
			local bits = {}
			if Text(quest.s) then bits[#bits + 1] = quest.s end
			if tonumber(quest.l) then bits[#bits + 1] = (L["level %d"]):format(quest.l) end
			rows[#rows + 1] = { icon = J.ICON.quest, title = title, sub = table.concat(bits, " · "), time = Fmt.Short(quest.t),
				tip = function(tooltip)
					if tonumber(quest.xp) and quest.xp > 0 then tooltip:AddLine((L["%s XP"]):format(BreakUpLargeNumbers(quest.xp)), unpack(T.text.body)) end
					E:TooltipHint(tooltip, { L["Click"], L["open it in Quests"] })
				end,
				onClick = function() A:OpenSection("quests", { quest = quest.id, t = quest.t }) end }
		end
	end
	return rows
end

local function NoteRows(zone)
	local rec = Rec()
	local out = {}
	for index = #(rec and rec.notes or {}), 1, -1 do
		local note = rec.notes[index]
		if type(note) == "table" and note.zone == zone and not note.archived and Text(note.text) then
			local where = Text(note.subzone) and (("%s · %s"):format(note.subzone, Fmt.Short(note.t))) or Fmt.Short(note.t)
			out[#out + 1] = { kind = "note", text = note.text, sub = where, pinned = note.pinned and true or false }
			out[#out + 1] = { kind = "space", height = 4 }
		end
	end
	return out
end

-- Gathering rows of a zone summed per node: "Peacebloom  x12".
local function GatherRows(rows)
	local counts, order = {}, {}
	for _, row in ipairs(rows) do
		if row.kind == "gather" then
			local node = Text(row.node) or L["Something"]
			if not counts[node] then
				counts[node] = 0
				order[#order + 1] = node
			end
			counts[node] = counts[node] + (tonumber(row.count) or 1)
		end
	end
	table.sort(order, function(a, b)
		if counts[a] ~= counts[b] then return counts[a] > counts[b] end
		return a < b
	end)
	local out = {}
	for _, node in ipairs(order) do
		out[#out + 1] = { kind = "line", icon = J.ICON.gather, text = node, time = ("x%d"):format(counts[node]) }
	end
	return out
end

local function DrawPlace(frame, zone)
	local entry = Find(zone)
	frame.place, frame.dungeon = zone, nil
	frame:SetDetail(L["Places"], function() frame:ShowGallery() end)
	frame.header:SetTitle(zone)
	local items = {}
	if not entry then
		frame.header:SetSentence(L["The journal has not been here yet."])
		frame.header:SetActions(nil)
		frame.list:SetEmpty(L["Not visited yet"], L["Once you come here, this page fills with what happened."], ICON)
		return items
	end
	local sentence
	if entry.first and entry.level then
		sentence = (L["First came here %s at level %s."]):format(Fmt.Long(entry.first), K.Num(entry.level))
	elseif entry.first then
		sentence = (L["First came here %s."]):format(Fmt.Long(entry.first))
	else
		sentence = L["You came here before the journal kept dates."]
	end
	if entry.time > 0 then sentence = sentence .. " " .. (L["%s here in all."]):format(K.Num(Fmt.Span(entry.time))) end
	frame.header:SetSentence(sentence)

	local moments = {}
	for _, row in ipairs(J:Timeline()) do
		if Text(row.zone) == zone and row.kind ~= "goalset" then moments[#moments + 1] = row end
	end
	local actions = {}
	if A:SectionShown("journey") and #moments > 0 then
		actions[#actions + 1] = { (L["In your journal: %d"]):format(#moments), function() A:OpenSection("journey", { zone = zone }) end,
			L["Opens the Journey with only the moments of this place."] }
	end
	if entry.map and LG.OpenWorldMapAt then
		actions[#actions + 1] = { L["Map"], function() LG:OpenWorldMapAt(entry.map) end, L["Opens the world map on this zone (out of combat)."] }
	end
	frame.header:SetActions(actions)

	local corners, done, total = Corners(zone, entry.place)
	local questRows = QuestRows(zone)
	items[#items + 1] = { kind = "akStats", stats = {
		{ BreakUpLargeNumbers(entry.kills), L["foes bested"], nil,
			L["Creatures you killed here, from the game's statistic or the XP lines that name them."] },
		{ BreakUpLargeNumbers(entry.quests), L["quests handed in"],
			A:SectionShown("quests") and function() A:OpenSection("quests", { group = "zone", open = zone }) end or nil,
			A:SectionShown("quests") and function(tip) LG.Kit.TooltipHint(tip, { L["Click"], L["see them in Quests, grouped by zone"] }) end or nil },
		{ BreakUpLargeNumbers(entry.deaths), L["falls"] },
		{ entry.time > 0 and Fmt.Span(entry.time) or "-", L["time here"], nil, L["Time you spent here, away from keyboard not counted."] },
		{ total and ("%d / %d"):format(done, total) or tostring(#corners), L["corners"] },
	} }
	local facts = ZoneFacts(entry.map)
	if facts then items[#items + 1] = { kind = "akText", text = facts, tip = L["From Zone Info."], tipTitle = L["About this zone"] } end
	items[#items + 1] = { kind = "space", height = 8 }

	local cornerRows = {}
	for index = 1, #corners, 2 do cornerRows[#cornerRows + 1] = { kind = "akCorners", cells = { corners[index], corners[index + 1] } } end
	if #cornerRows == 0 then cornerRows[1] = { kind = "akText", text = L["No corners named yet. Wander a little and they appear here."] } end
	LP.AddFold(items, "places:corners", (L["Corners of %s"]):format(zone),
		total and (L["%d of %d explored"]):format(done, total) or tostring(#corners), cornerRows, true, function() frame:Draw(true) end)

	if #questRows > 0 then
		LP.AddFold(items, "places:quests", L["Quests handed in here"], tostring(#questRows),
			LP.Ledger(questRows, EVENT_CAP, function() A:OpenSection("quests", { group = "zone", open = zone }) end), true,
			function() frame:Draw(true) end)
	end
	local notes = NoteRows(zone)
	if #notes > 0 then
		LP.AddFold(items, "places:notes", L["Notes written here"], tostring(math.floor(#notes / 2)), notes, true, function() frame:Draw(true) end)
	end
	local gathered = GatherRows(moments)
	if #gathered > 0 then
		LP.AddFold(items, "places:gathered", L["Gathered here"], tostring(#gathered), gathered, false, function() frame:Draw(true) end)
	end
	-- What happened here: every moment, newest first (the detail setting
	-- does not hide any here).
	local lines = {}
	for index = #moments, 1, -1 do
		local row = moments[index]
		if row.kind ~= "gather" then
			local title, _, icon = A:LineText(row)
			local link = J:LinkFor(row)
			lines[#lines + 1] = { kind = "line", icon = icon, text = title, time = Fmt.When(row.t), row = row,
				onClick = (row.src == "journal" and row.seq and A:SectionShown("journey")) and function()
					A:OpenSection("journey", { seq = row.seq })
				end or (link and function() J:Open(link) end) or nil,
				tip = function(tooltip)
					tooltip:AddLine(("%s, %s"):format(Fmt.Day(row.t), Fmt.Clock(row.t)), unpack(T.text.secondary))
				end, tipTitle = title }
			if #lines >= EVENT_CAP then break end
		end
	end
	if #lines > 0 then
		if #moments > EVENT_CAP and A:SectionShown("journey") then
			lines[#lines + 1] = { kind = "more", text = K.MoreText(#moments), onClick = function() A:OpenSection("journey", { zone = zone }) end }
		end
		LP.AddFold(items, "places:events", L["What happened here"], tostring(#moments), lines, true, function() frame:Draw(true) end)
	end
	return items
end

---------------------------------------------------------------------------
-- A dungeon page (the history view, UI/History.lua)
---------------------------------------------------------------------------
local function DrawDungeon(frame, name)
	frame.place, frame.dungeon = nil, name
	frame:SetDetail(L["Places"], function() frame:ShowGallery() end)
	local history = H()
	if not history then return {} end
	local title, sentence, items, actions = history.View(name, { from = "places", redraw = function() frame:Draw(true) end })
	frame.header:SetTitle(title)
	frame.header:SetSentence(sentence)
	frame.header:SetActions(actions)
	frame.list:SetEmpty(L["No runs here yet"], L["Each run you make here is written down with its time, bosses, and company."], DUNGEON_ICON)
	return items
end

---------------------------------------------------------------------------
-- The section
---------------------------------------------------------------------------
local function Build(parent)
	local frame
	frame = LP.Page(parent, {
		empty = { L["Nowhere yet"], L["The road is waiting. Every zone you visit gets a card."], ICON },
		controls = function(page, bar)
			page.show = K.Switch(bar, SHOW, UIState().show, function(show)
				UIState().show = show
				page:Draw()
			end)
			page.show:SetPoint("LEFT", 0, 0)
			page.sort = K.Switch(bar, SORT, UIState().sort, function(sort)
				UIState().sort = sort
				page:Draw()
			end)
			page.sort:SetPoint("LEFT", page.show, "RIGHT", 12, 0)
			page.search = K.Search(bar, KEY, L["Search places and their corners"], function() page:Draw() end)
			page.search:SetPoint("LEFT", page.sort, "RIGHT", 12, 0)
			page.search:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
		end,
	})

	function frame:Draw(keepScroll)
		if not self:IsShown() then
			self.dirty = true
			return
		end
		self.dirty = false
		local started = debugprofilestop()
		local items
		if self.dungeon then
			items = DrawDungeon(self, self.dungeon)
		elseif self.place then
			items = DrawPlace(self, self.place)
		else
			items = DrawGallery(self)
		end
		self.items = items
		self.list:SetData(items, keepScroll)
		self.buildMs = debugprofilestop() - started
	end

	function frame:ShowGallery()
		self.place, self.dungeon = nil, nil
		self:Draw()
	end

	function frame:OpenPlace(zone)
		self.place, self.dungeon = zone, nil
		self:Draw()
	end

	function frame:OpenDungeon(name)
		self.place, self.dungeon = nil, name
		self:Draw()
	end

	function frame:SetSearch(text)
		self.search:SetText(text or "")
		self.search:GetScript("OnTextChanged")(self.search, true)
	end

	function frame:ClearFilters()
		local s = UIState()
		s.show = "all"
		self:SetSearch("")
		self:Draw()
	end

	frame:SetScript("OnShow", function(self) if self.dirty then self:Draw(true) end end)
	return frame
end

local function Show(frame, arg)
	if type(arg) == "string" then
		local kind, id = J:ParseAddress(arg)
		if kind == "place" then arg = { place = tostring(id) } else arg = { search = arg } end
	end
	if type(arg) == "table" then
		if arg.show and SHOW_KEYS[arg.show] then UIState().show = arg.show end
		if arg.search then frame:SetSearch(arg.search) end
		if arg.place then
			frame.place, frame.dungeon = tostring(arg.place), nil
		elseif arg.dungeon then
			frame.place, frame.dungeon = nil, tostring(arg.dungeon)
		else
			frame.place, frame.dungeon = nil, nil
		end
	elseif arg == nil and not frame.drawnOnce then
		frame.place, frame.dungeon = nil, nil
	end
	frame.drawnOnce = true
	frame:Draw(type(arg) ~= "table")
end

local function Refresh(frame, changed)
	if changed.adventure or changed.settings or changed.data then frame:Draw(true) end
end

A:RegisterSection(KEY, {
	title = "Places",
	icon = ICON,
	desc = "Every zone you visited, with its corners, time, kills, and quests, and every dungeon with its runs.",
	words = { "places", "place", "zones", "zone", "corners" },
	build = Build,
	show = Show,
	refresh = Refresh,
	search = function(text)
		local words = LP.Words(text)
		if #words == 0 then return {} end
		local out = {}
		for _, entry in ipairs(Zones()) do
			for sub in pairs(entry.place.subs or {}) do
				if type(sub) == "string" and LP.Hits(E:FoldText(sub), words) then
					out[#out + 1] = { title = sub, sub = (L["A corner of %s"]):format(entry.zone), icon = ICON, arg = { place = entry.zone } }
					if #out >= 20 then return out end
				end
			end
		end
		local history = H()
		for _, dungeon in ipairs(history and history.Dungeons() or {}) do
			if LP.Hits(E:FoldText(dungeon.name), words) then
				out[#out + 1] = { title = dungeon.name, sub = L["Your runs there"], icon = dungeon.icon or DUNGEON_ICON, arg = { dungeon = dungeon.name } }
				if #out >= 20 then return out end
			end
		end
		return out
	end,
})

-- "journal:place:<zone>" opens the place page (a dungeon name opens its history).
J:RegisterAddress("place", function(id)
	if not A:SectionShown(KEY) then return false end
	id = tostring(id)
	local history = H()
	if history and history.IsDungeon(id) and not Find(id) then return A:OpenSection(KEY, { dungeon = id }) end
	return A:OpenSection(KEY, { place = id })
end)
