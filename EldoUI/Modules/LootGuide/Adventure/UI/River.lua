-- EldoUI My Adventure: the level river.
--
--     ▲   ⚑ ☠        ✦  ⚑       ⌛         ♞        ⚑  ✦      ★
--  |┈┈┈┈┈|▁▂▃▂▃▄|▄▅▆█▇▆▅▅|▅▆▆▇█▇▆▇▆|  ▆▇▇▆|▆▇██▇▇▆▇▆|▇█▇▆▅▅▆▅▇▇|█┈┈┈┈
--   before   Part 1   Part 2        Part 3        Part 4 ...
--
-- One horizontal ribbon for levels 1 to 60. Each level is one quad, as
-- thick as the time you spent at that level (the slow ones swell, the fast
-- ones narrow), its right edge bent to the next level's thickness so the
-- outline is smooth. Colors follow the eras (the accent's hue turned per
-- era). Levels the journal did not record are drawn as an outline only,
-- with "before the journal" or "not recorded" under them; levels still
-- ahead are a thin line. Thin ticks mark a change of main zone. Markers
-- ride above: dungeons, raids, death streaks, flight paths, quest chains,
-- attunements, keepsakes and long breaks, three high at most ("+n").
--
-- Hover a level for its chapter title and numbers; click opens the
-- Journey, Shift-click the Book at that level. Hover a marker for its row.
-- Everything comes from the story plan (book.river): nothing is guessed.
--
--   A.River.Create(parent, { height, mini })  -> river
--   river:SetBook(book, set[, { motion }])    draws (again on resize)
--   river.quadsShown, river.gapsShown, river.markersShown   (tests)
local _, E = ...
local L = E.L
local A = E.Adventure
local J = E.Journal
local LG = E.LootGuide
local K = E.AdventureKit
local T = E.tokens

local R = {}
A.River = R

local LEVELS = 60
local MARKER = 14
local MARKER_BAND = 3 * MARKER + 4
local LABEL_BAND = 14
local MAX_STACK = 3

local function SV() return A.StoryView end

-- Markers: an atlas the client may have, else the journal's own icon.
local MARKERS = {
	dungeon = { atlas = "Dungeon", icon = "dungeon", label = L["Dungeon"] },
	raid = { atlas = "Raid", icon = "boss", label = L["Raid"] },
	death = { atlas = "poi-graveyard-neutral", icon = "death", label = L["Deaths"] },
	flight = { atlas = "TaxiNode_Neutral", icon = "flight", label = L["Flight path"] },
	quest = { atlas = "QuestTurnin", icon = "quest", label = L["Quest chain"] },
	attuned = { atlas = "QuestLegendary", icon = "goal", label = L["Attunement"] },
	keepsake = { icon = "mount", label = L["Keepsake"] },
	gap = { icon = "gap", label = L["A long break"] },
}
R.MARKERS = MARKERS
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_Book_09"
local GAP_ICON = "Interface\\Icons\\INV_Misc_PocketWatch_01"

local function SetMarkerArt(texture, kind)
	local def = MARKERS[kind] or MARKERS.keepsake
	local icon = (J.ICON and J.ICON[def.icon]) or (kind == "gap" and GAP_ICON) or FALLBACK_ICON
	if def.atlas and E:ClientAtlas(def.atlas) then
		E:SetClientAtlas(texture, def.atlas)
	else
		texture:SetTexture(E:ClientIcon(icon))
		E:TrimIcon(texture)
	end
end

-- The era (book part) a level belongs to: index for its color.
local function EraIndex(book, level)
	for _, part in ipairs(book.parts or {}) do
		if part.a and part.b and level >= part.a and level <= part.b then return part.index or 1, part end
	end
	return nil
end

local function JourneyChapter(book, level)
	for _, chapter in ipairs(book.journey or {}) do
		if chapter.level == level then return chapter end
	end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function Quad(river, index)
	local quad = river.quads[index]
	if not quad then
		quad = river.band:CreateTexture(nil, "ARTWORK")
		quad:SetTexture(E.media.flat)
		river.quads[index] = quad
	end
	return quad
end

-- An outline box for a run of unrecorded levels (four hairlines).
local function Outline(river, index)
	local box = river.outlines[index]
	if not box then
		box = {}
		for _, side in ipairs({ "top", "bottom", "left", "right" }) do
			box[side] = river.band:CreateTexture(nil, "ARTWORK")
			box[side]:SetTexture(E.media.flat)
		end
		E:Hairline(box.top, "h", 1)
		E:Hairline(box.bottom, "h", 1)
		E:Hairline(box.left, "w", 1)
		E:Hairline(box.right, "w", 1)
		box.label = K.Text(river, K.size.caption, "LEFT", "secondary")
		box.label:SetWordWrap(false)
		river.outlines[index] = box
	end
	return box
end

local function Tick(river, index)
	local tick = river.ticks[index]
	if not tick then
		tick = river.band:CreateTexture(nil, "OVERLAY")
		tick:SetTexture(E.media.flat)
		E:Hairline(tick, "w", 1)
		river.ticks[index] = tick
	end
	return tick
end

local function MarkerButton(river, index)
	local button = river.markers[index]
	if not button then
		button = CreateFrame("Button", nil, river)
		button:SetSize(MARKER, MARKER)
		button.art = button:CreateTexture(nil, "ARTWORK")
		button.art:SetAllPoints()
		button.more = K.Text(button, K.size.caption - 1, "CENTER", "secondary")
		button.more:SetPoint("CENTER")
		button:SetScript("OnEnter", function(self)
			local tip = GameTooltip
			tip:SetOwner(self, "ANCHOR_TOP")
			if self.facts then
				for i, fact in ipairs(self.facts) do
					local title, sub = E.Story:Row(fact, river.set)
					local c = i == 1 and T.text.body or T.text.secondary
					tip:AddLine(title or (MARKERS[self.kind] and E:Translate(MARKERS[self.kind].label)) or "", c[1], c[2], c[3], true)
					if sub and i == 1 then
						local s = T.text.secondary
						tip:AddLine(sub, s[1], s[2], s[3], true)
					end
				end
			end
			tip:Show()
		end)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
		button:SetScript("OnClick", function(self)
			if self.facts and self.facts[1] and SV() then SV().Navigate(river.set, self.facts[1]) end
		end)
		river.markers[index] = button
	end
	return button
end

local function Column(river, level)
	local column = river.columns[level]
	if not column then
		column = CreateFrame("Button", nil, river)
		column:RegisterForClicks("LeftButtonUp")
		column.level = level
		column:SetScript("OnEnter", function(self) R.LevelTooltip(river, self, self.level) end)
		column:SetScript("OnLeave", function() GameTooltip:Hide() end)
		column:SetScript("OnClick", function(self) R.OpenLevel(river, self.level, IsShiftKeyDown()) end)
		river.columns[level] = column
	end
	return column
end

function R.LevelTooltip(river, owner, level)
	local book = river.book
	if not book then return end
	local row = book.river and book.river[level]
	local tip = GameTooltip
	tip:SetOwner(owner, "ANCHOR_TOP")
	local chapter = JourneyChapter(book, level)
	E.UIKit.TipTitle(tip, chapter and chapter.title or (L["Level %d"]):format(level))
	local s = T.text.secondary
	-- The part's name, when its label had no room on the river.
	local _, part = EraIndex(book, level)
	if part and part.number and river.droppedParts and river.droppedParts[part] then
		tip:AddLine((L["Part %d"]):format(part.number), s[1], s[2], s[3])
	end
	if row and row.future then
		tip:AddLine(L["Still ahead."], s[1], s[2], s[3])
	elseif row and row.gap then
		tip:AddLine(level < (river.set and river.set.startedLevel or 1) and L["Before the journal: not recorded."]
			or L["Not recorded: the level log was off."], s[1], s[2], s[3], true)
	elseif chapter then
		tip:AddLine(chapter.stats, s[1], s[2], s[3], true)
		local closing = chapter.closing and chapter.closing[1]
		if closing then tip:AddLine(E.Story.Export.Plain(closing.text), s[1], s[2], s[3], true) end
	end
	if row and not row.future then
		local d = T.text.dim
		E:TooltipHint(tip, { L["Click"], L["open this level in the Journey"] }, { L["Shift-click"], L["open the Book"] })
	end
	tip:Show()
end

function R.OpenLevel(river, level, book)
	local row = river.book and river.book.river and river.book.river[level]
	if not row or row.future then return false end
	if book and A:SectionShown("book") then return A:OpenSection("book", { level = level }) end
	if A:SectionShown("journey") then return A:OpenSection("journey", { view = "level", level = level }) end
	return false
end

local function Draw(river)
	local book = river.book
	if not (book and book.river) then return end
	local width = river:GetWidth() or 0
	if width <= 0 then return end
	local mini = river.mini
	local look = SV() and SV().Look() or "EldoUI"
	local top = mini and 0 or MARKER_BAND
	local bandH = math.max((river:GetHeight() or 0) - top - (mini and 0 or LABEL_BAND), 8)
	river.band:ClearAllPoints()
	river.band:SetPoint("TOPLEFT", river, "TOPLEFT", 0, -top)
	river.band:SetPoint("TOPRIGHT", river, "TOPRIGHT", 0, -top)
	river.band:SetHeight(bandH)
	local cw = width / LEVELS
	local mid = bandH / 2
	local minH, maxH = math.max(2, bandH * 0.05), math.max(bandH - 4, 4)
	local maxTime = 0
	for n = 1, LEVELS do
		local row = book.river[n]
		if row and row.recorded and not row.future and (row.time or 0) > maxTime then maxTime = row.time end
	end
	local function Thick(row)
		if not row or row.future or row.gap or not row.recorded then return nil end
		if not row.time or maxTime <= 0 then return minH end
		return math.min(math.max(minH, maxH * row.time / maxTime), maxH)
	end
	local quads, gaps = 0, 0
	local ticks, markers
	local now = river.set and river.set.level
	-- Quads.
	for n = 1, LEVELS do
		local row = book.river[n]
		local h = Thick(row)
		local quad = Quad(river, n)
		if h then
			quads = quads + 1
			local era = EraIndex(book, n) or 1
			local c = SV() and SV().EraColor(era, look) or T.text.secondary
			quad:SetVertexColor(c[1], c[2], c[3], 0.9)
			quad:ClearAllPoints()
			quad:SetPoint("TOPLEFT", river.band, "TOPLEFT", (n - 1) * cw, -(mid - h / 2))
			quad:SetSize(math.max(cw, 1), h)
			-- Bend the right edge toward the next level's thickness.
			local nextH = Thick(book.river[n + 1]) or h
			local d = (nextH - h) / 2
			if quad.SetVertexOffset then
				quad:SetVertexOffset(1, 0, 0)
				quad:SetVertexOffset(2, 0, 0)
				quad:SetVertexOffset(3, 0, d)
				quad:SetVertexOffset(4, 0, -d)
			end
			quad:Show()
		else
			quad:Hide()
		end
	end
	-- Unrecorded runs (outline only) and the line of levels still ahead.
	local runs = {}
	local cur
	for n = 1, LEVELS do
		local row = book.river[n]
		if row and row.gap and not row.future then
			if cur and cur.b == n - 1 then cur.b = n else
				cur = { a = n, b = n, before = now and river.set.startedLevel and n < river.set.startedLevel }
				runs[#runs + 1] = cur
			end
		end
	end
	local rule = SV() and SV().Ink("rule", look) or T.edge.divider
	local dim = SV() and SV().Ink("dim", look) or T.text.dim
	for index = 1, math.max(#river.outlines, #runs) do
		local run = runs[index]
		local box = Outline(river, index)
		local shown = run ~= nil
		for _, side in ipairs({ "top", "bottom", "left", "right" }) do box[side]:SetShown(shown) end
		box.label:SetShown(shown and not mini)
		if run then
			gaps = gaps + 1
			local x0, x1 = (run.a - 1) * cw, run.b * cw
			local h = math.max(minH * 3, bandH * 0.3)
			local y0 = -(mid - h / 2)
			for _, side in ipairs({ "top", "bottom", "left", "right" }) do
				box[side]:SetVertexColor(dim[1], dim[2], dim[3], 0.8)
				box[side]:ClearAllPoints()
			end
			box.top:SetPoint("TOPLEFT", river.band, "TOPLEFT", x0, y0)
			box.top:SetWidth(math.max(x1 - x0, 1))
			box.bottom:SetPoint("TOPLEFT", river.band, "TOPLEFT", x0, y0 - h)
			box.bottom:SetWidth(math.max(x1 - x0, 1))
			box.left:SetPoint("TOPLEFT", river.band, "TOPLEFT", x0, y0)
			box.left:SetHeight(h)
			box.right:SetPoint("TOPLEFT", river.band, "TOPLEFT", x1 - 1, y0)
			box.right:SetHeight(h)
			box.label:ClearAllPoints()
			box.label:SetPoint("TOPLEFT", river.band, "BOTTOMLEFT", x0, -2)
			box.label:SetWidth(math.max(x1 - x0, 40))
			box.label:SetText(run.before and L["before the journal"] or L["not recorded"])
		end
	end
	local futureFrom
	for n = 1, LEVELS do
		local row = book.river[n]
		if row and row.future then
			futureFrom = n
			break
		end
	end
	river.ahead:SetShown(futureFrom ~= nil)
	if futureFrom then
		river.ahead:ClearAllPoints()
		river.ahead:SetPoint("LEFT", river.band, "TOPLEFT", (futureFrom - 1) * cw, -mid)
		river.ahead:SetPoint("RIGHT", river.band, "TOPRIGHT", 0, -mid)
		river.ahead:SetVertexColor(dim[1], dim[2], dim[3], 0.8)
	end
	-- Zone ticks.
	local tickIndex = 0
	if not mini then
		for n = 2, LEVELS do
			local row = book.river[n]
			if row and row.zoneChange and row.recorded and not row.future then
				tickIndex = tickIndex + 1
				local tick = Tick(river, tickIndex)
				tick:ClearAllPoints()
				tick:SetPoint("TOPLEFT", river.band, "TOPLEFT", (n - 1) * cw, -2)
				tick:SetHeight(bandH - 4)
				tick:SetVertexColor(rule[1], rule[2], rule[3], rule[4] or 1)
				tick:Show()
			end
		end
	end
	ticks = tickIndex
	for index = tickIndex + 1, #river.ticks do river.ticks[index]:Hide() end
	-- Now: an accent line through the current level.
	river.now:SetShown(now ~= nil and now >= 1 and now <= LEVELS)
	if now and now >= 1 and now <= LEVELS then
		local accent = E.media.accentColor
		river.now:SetVertexColor(accent[1], accent[2], accent[3], 1)
		river.now:ClearAllPoints()
		river.now:SetPoint("TOP", river.band, "TOPLEFT", (now - 0.5) * cw, 0)
		river.now:SetHeight(bandH)
	end
	-- Markers (stacked up to three, then "+n").
	local used = 0
	if not mini then
		for n = 1, LEVELS do
			local row = book.river[n]
			local list = row and row.markers or {}
			if #list > 0 then
				local byKind, order = {}, {}
				for _, marker in ipairs(list) do
					local fact = river.set and river.set.byId[marker.id]
					if fact then
						if not byKind[marker.kind] then
							byKind[marker.kind] = {}
							order[#order + 1] = marker.kind
						end
						local facts = byKind[marker.kind]
						facts[#facts + 1] = fact
					end
				end
				local stack = 0
				for index, kind in ipairs(order) do
					if stack >= MAX_STACK then break end
					used = used + 1
					local button = MarkerButton(river, used)
					button:ClearAllPoints()
					button:SetPoint("BOTTOM", river.band, "TOPLEFT", (n - 0.5) * cw, 2 + stack * MARKER)
					local hidden = #order - index
					if stack == MAX_STACK - 1 and hidden > 0 then
						button.art:Hide()
						button.more:SetText("+" .. (hidden + 1))
						button.more:Show()
						button.kind, button.facts = kind, {}
						for k = index, #order do
							for _, fact in ipairs(byKind[order[k]]) do button.facts[#button.facts + 1] = fact end
						end
					else
						SetMarkerArt(button.art, kind)
						button.art:Show()
						button.more:Hide()
						button.kind, button.facts = kind, byKind[kind]
					end
					button:Show()
					stack = stack + 1
				end
			end
		end
	end
	markers = used
	for index = used + 1, #river.markers do river.markers[index]:Hide() end
	-- Era labels.
	-- A part narrower than its label gets the label's own width; one that
	-- would run past the band's right end is set flush right (the last part
	-- at level 60 is one level wide). When two labels would touch, the
	-- narrower part loses its label and its name stays in the tooltip.
	local labelIndex = 0
	river.droppedParts = {}
	if not mini then
		local last
		for _, part in ipairs(book.parts or {}) do
			if part.number and part.a then
				labelIndex = labelIndex + 1
				local label = river.labels[labelIndex]
				if not label then
					label = K.Text(river, K.size.caption, "LEFT", "secondary")
					label:SetWordWrap(false)
					river.labels[labelIndex] = label
				end
				label:SetText((L["Part %d"]):format(part.number))
				local need = math.ceil(label.GetUnboundedStringWidth and label:GetUnboundedStringWidth() or label:GetStringWidth() or 0) + 2
				local room = math.max(((part.b or part.a) - part.a + 1) * cw - 4, 0)
				local left = (part.a - 1) * cw + 2
				label:ClearAllPoints()
				label:SetWidth(math.max(room, need, 12))
				if left + need > width - 2 then
					left = width - 2 - need
					label:SetPoint("TOPRIGHT", river.band, "BOTTOMRIGHT", -2, -2)
					label:SetJustifyH("RIGHT")
				else
					label:SetPoint("TOPLEFT", river.band, "BOTTOMLEFT", (part.a - 1) * cw + 2, -2)
					label:SetJustifyH("LEFT")
				end
				local c = SV() and SV().EraColor(part.index or 1, look) or T.text.secondary
				label:SetTextColor(c[1], c[2], c[3])
				label:Show()
				local placed = { label = label, part = part, left = left, right = left + need, room = room }
				if last and placed.left < last.right + 4 then
					local drop = room < last.room and placed or last
					drop.label:Hide()
					river.droppedParts[drop.part] = true
					if drop == last then last = placed end
				else
					last = placed
				end
			end
		end
	end
	for index = labelIndex + 1, #river.labels do river.labels[index]:Hide() end
	-- Hover columns (one per level that has something to say).
	for n = 1, LEVELS do
		local column = Column(river, n)
		local row = book.river[n]
		column:ClearAllPoints()
		column:SetPoint("TOPLEFT", river.band, "TOPLEFT", (n - 1) * cw, 0)
		column:SetSize(math.max(cw, 1), bandH)
		column:SetShown(row ~= nil and not mini)
		column:EnableMouse(row ~= nil and not mini)
	end
	river.quadsShown, river.gapsShown, river.ticksShown, river.markersShown = quads, gaps, ticks, markers
end
R.Draw = Draw

function R.Create(parent, opts)
	opts = opts or {}
	local river = CreateFrame("Frame", nil, parent)
	river:SetHeight(opts.height or 120)
	river.mini = opts.mini and true or false
	river.band = CreateFrame("Frame", nil, river)
	river.band:EnableMouse(false)
	river.quads, river.outlines, river.ticks, river.markers, river.columns, river.labels = {}, {}, {}, {}, {}, {}
	river.ahead = river.band:CreateTexture(nil, "BORDER")
	river.ahead:SetTexture(E.media.flat)
	E:Hairline(river.ahead, "h", 1)
	river.now = river.band:CreateTexture(nil, "OVERLAY")
	river.now:SetTexture(E.media.flat)
	E:Hairline(river.now, "w", 2)
	river:EnableMouse(false)

	function river:SetBook(book, set, how)
		self.book, self.set = book, set
		Draw(self)
		if how and how.motion and SV() and SV().Motion() then E:FadeIn(self, 0.6) end
	end
	river:SetScript("OnSizeChanged", function(self) Draw(self) end)
	return river
end
