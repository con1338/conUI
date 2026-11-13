-- EldoUI My Adventure: the stats spread of a chapter.
--
--   ┌ III · Duskwood · levels 22-27 ─────────────────────────────────┐
--   │ TIME        14h 05m played    ▁▃▅█▃▂   level 25 was the longest │
--   │ KILLS       212               counted by the journal            │
--   │ QUESTS      61 handed in      most in Duskwood                  │
--   │ GOLD        38g earned        money in, never spending          │
--   │ DEATHS      4                 3 in Duskwood, 1 in Redridge      │
--   │ COMPANIONS  2 met             Tom Ashford, Kara Flint           │
--   │ DUNGEONS    the Deadmines     first time                        │
--   │ KEEPSAKES   Honored with Stormwind                              │
--   └────────────────────────────────────────────────────────────────┘
--
-- The closing page of each chapter in the Book. Every value is a sum of the
-- level log or a count of the chapter's facts; a level the log did not
-- record makes its rows say so (G2). The sparkline has one bar per level
-- (time played), the longest in the accent; hover a bar for its numbers.
--
--   A.StatsSpread.Data(set, a, b[, opts]) -> rows, levels
--   A.StatsSpread.Create(parent) -> spread
--   spread:SetChapter(set, chapter[, look, opts]); spread:Height()
local _, E = ...
local L = E.L
local A = E.Adventure
local K = E.AdventureKit
local T = E.tokens

local SS = {}
A.StatsSpread = SS

local function SV() return A.StoryView end
local function Story() return E.Story end

local ROW_H, PAD, GAP = 20, 8, 4
local LABEL_W, VALUE_W = 92, 128
local SPARK_W, SPARK_H = 72, 14

-- Complete: every level of the span has its level-log record.
local function Recorded(set, a, b)
	for n = a, b do
		if not set.levels[n] or not set:SourceOn("levels", n) then return false end
	end
	return true
end

-- rows = { { label, value, note, tip } }, levels = { { n, time } }
-- opts.companions: name companions (off in exports).
function SS.Data(set, a, b, opts)
	opts = opts or {}
	local Gr = Story().Grammar
	local rows, levels = {}, {}
	local whole = Recorded(set, a, math.min(b, set.level))
	local missing = L["Some of these levels were not recorded, so this is only part of it."]
	local function Add(label, value, note, tip)
		rows[#rows + 1] = { label = label, value = value, note = note or "", tip = tip }
	end
	-- Time.
	local played, longest, longestN = 0, 0, nil
	for n = a, b do
		local rec = set.levels[n]
		local t = rec and tonumber(rec.time)
		levels[#levels + 1] = { n = n, time = t, rec = rec }
		if t then
			played = played + t
			if t > longest then longest, longestN = t, n end
		end
	end
	if played > 0 then
		local note = longestN and b > a and (L["Longest: level %d (%s)"]):format(longestN, Gr.Duration(longest, "ledger")) or ""
		Add(L["Time"], (L["%s played"]):format(Gr.Duration(played, "ledger")), note,
			whole and L["Time played at each level, from the level log."] or missing)
	else
		Add(L["Time"], L["Not recorded"], "", L["The level log was off for these levels."])
	end
	-- Kills, quests, gold, deaths (sums of the level log).
	local kills = SV().Sum(set, "kills", a, b)
	if kills then
		Add(L["Kills"], BreakUpLargeNumbers(kills), L["counted by the journal"],
			whole and L["From the game's kill statistic and its experience lines, at each level."] or missing)
	end
	local quests = SV().Sum(set, "quests", a, b)
	if quests then
		local zone = Story().Plan.ZoneTimes(set, a, b)
		Add(L["Quests"], (L["%s handed in"]):format(BreakUpLargeNumbers(quests)),
			zone and quests > 0 and (L["most time in %s"]):format(Gr.Place(zone, "head", true)) or "",
			whole and L["Quests you handed in at these levels."] or missing)
	end
	local earned = SV().Sum(set, "earned", a, b)
	if earned and earned > 0 then
		Add(L["Gold"], (L["%s earned"]):format(Gr.Money(earned, "ledger")), L["money in, never spending"],
			whole and L["Money you looted, earned from quests and sold for. Spending is not counted."] or missing)
	end
	local deaths = SV().Sum(set, "deaths", a, b)
	if deaths then
		local where = {}
		for n = a, b do
			for zone, count in pairs((set.levels[n] or {}).deathZones or {}) do where[zone] = (where[zone] or 0) + count end
		end
		local list = {}
		for zone, count in pairs(where) do list[#list + 1] = { zone, count } end
		table.sort(list, function(x, y) if x[2] ~= y[2] then return x[2] > y[2] end return x[1] < y[1] end)
		local bits = {}
		for i = 1, math.min(3, #list) do bits[i] = ("%d %s"):format(list[i][2], Gr.Place(list[i][1], "in", true)) end
		Add(L["Deaths"], deaths == 0 and L["none"] or tostring(deaths), table.concat(bits, ", "),
			whole and L["Deaths at these levels, from the level log."] or missing)
	end
	-- Companions met, dungeons entered, keepsakes (facts of these levels).
	local met, names = 0, {}
	local dungeons, keep = {}, {}
	for _, fact in ipairs(set.list) do
		local l = fact.l
		if l and l >= a and l <= b then
			if fact.kind == "met" then
				met = met + 1
				if opts.companions and fact.v.fellow then names[#names + 1] = fact.v.fellow end
			elseif fact.kind == "dungeon" or fact.kind == "raid" or fact.kind == "run" then
				if fact.v.instance then
					local key = fact.v.instance
					if not dungeons[key] then
						dungeons[key] = { name = fact.v.instance, n = 0, first = fact.kind ~= "run" }
						dungeons[#dungeons + 1] = dungeons[key]
					end
					dungeons[key].n = dungeons[key].n + 1
				end
			end
			if fact.keep or fact.flags.first and (fact.kind == "boss" or fact.kind == "raidboss") then
				local title = E.Story:Row(fact, set)
				if title then keep[#keep + 1] = title end
			end
		end
	end
	if met > 0 then
		Add(L["Companions"], (L["%d met"]):format(met), Gr.List(names, { max = 3 }), -- no-plural
			L["People you grouped with long enough for the journal to remember. Names show while Name companions is on."])
	end
	if #dungeons > 0 then
		local bits = {}
		for _, d in ipairs(dungeons) do
			bits[#bits + 1] = Gr.Place(d.name, "head", true) .. (d.n > 1 and (" ×" .. d.n) or "")
		end
		Add(L["Dungeons"], tostring(#dungeons), table.concat(bits, " · "), L["Dungeons and raids the Instances module recorded."])
	end
	if #keep > 0 then
		Add(L["Keepsakes"], tostring(#keep), table.concat(keep, " · "), L["Your big moments at these levels."])
	end
	return rows, levels
end

local function PaintBar(bar, color)
	bar:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
end

local measureFrame, measures
local ROLES = { label = { "caption", "accent" }, value = { "body", "body" }, note = { "small", "secondary" }, head = { "section", "head", true } }
local function Finite(value)
	return not E:IsSecret(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end

-- Measurement and painting use the same kit font and look, including Large
-- text. No independent character-width estimate or fixed row height is used.
local function Measurer(look)
	if not measureFrame then
		measureFrame = CreateFrame("Frame", nil, UIParent)
		measureFrame:Hide();measures = {}
	end
	local function Font(role)
		local spec = ROLES[role]
		local fs = measures[role]
		if not fs then fs = K.Text(measureFrame, K.size[spec[1]], "LEFT", spec[2], spec[3]);measures[role] = fs end
		K.InkFont(fs, K.size[spec[1]], spec[3] and true or false)
		SV().Paint(fs, spec[2], look)
		fs:SetSpacing(0);fs:SetMaxLines(0)
		return fs
	end
	local function Measure(role, text, width)
		assert(not E:IsSecret(text) and type(text) == "string", "Invalid Book statistics text")
		local fs = Font(role)
		fs:SetWordWrap(width ~= nil);fs:SetWidth(width or 0);fs:SetText(text)
		local w, h = fs:GetUnboundedStringWidth(), fs:GetStringHeight()
		assert(Finite(w) and w >= 0 and Finite(h) and h >= 0 and (text == "" or h > 0), "Book statistics font could not be measured")
		return { width = w, height = math.ceil(h) }
	end
	local signature, scales = {}, {}
	for _, role in ipairs({ "label", "value", "note", "head" }) do
		local fs = Font(role)
		local file, size, flags = fs:GetFont()
		assert(type(file) == "string" and not E:IsSecret(file) and Finite(size) and size > 0
			and type(flags) == "string" and not E:IsSecret(flags), "Book statistics font is unavailable")
		signature[#signature + 1] = table.concat({ file, size, flags }, ":")
		scales[role] = size / K.size[ROLES[role][1]]
	end
	return Measure, table.concat(signature, "|"), scales
end

function SS.FontKey(look)
	local _, key = Measurer(look)
	return key
end

function SS.Measure(set, chapter, width, look, opts)
	assert(Finite(width) and width > 2 * PAD + 2, "Book statistics need a positive reading width")
	local data, levels = SS.Data(set, chapter.a, chapter.b, opts)
	local measure, key, scales = Measurer(look)
	local inner, labelW, valueW, noteW = width - 2 * PAD - 2, LABEL_W * scales.label, VALUE_W * scales.value, 0
	local source = {}
	for index, row in ipairs(data) do
		local fields = { label = E:CaptionText(row.label), value = tostring(row.value or ""), note = row.note or "" }
		source[index] = fields
		labelW = math.max(labelW, measure("label", fields.label).width)
		valueW = math.max(valueW, measure("value", fields.value).width)
		noteW = math.max(noteW, measure("note", fields.note).width)
	end
	local columns = labelW + valueW + noteW + 2 * PAD <= inner
	labelW = math.min(labelW, inner * .45)
	if not columns then valueW = inner - labelW - PAD end
	local function Wrapped(role, text, w)
		local function Text(value, available) return measure(role, value, available) end
		local wrapped = A.Book.WrapText(text, w, Text)
		return wrapped, measure(role, wrapped, w).height
	end
	local header = ("%s · %s · %s"):format(chapter.numeral or "", chapter.title or "", chapter.span or "")
	local head, headH = Wrapped("head", header, inner)
	local plan = { width = width, inner = inner, header = head, headHeight = 7 + headH + 5,
		data = data, levels = levels, rows = {}, look = look, fontKey = key, measure = measure }
	local height = plan.headHeight + GAP + PAD
	for index, fields in ipairs(source) do
		local noteWidth = columns and inner - labelW - valueW - 2 * PAD or inner
		local label, labelH = Wrapped("label", fields.label, labelW)
		local value, valueH = Wrapped("value", fields.value, valueW)
		local note, noteH = Wrapped("note", fields.note, math.max(noteWidth, 1))
		local mainH = math.max(ROW_H, labelH, valueH)
		local noteY = not columns and note ~= "" and mainH + GAP or 0
		local bodyH = columns and math.max(mainH, noteH) or note ~= "" and noteY + noteH or mainH
		local row = { index = index, source = fields, fields = {
			{ key = "label", text = label, x = 0, y = 0, width = labelW, height = labelH },
			{ key = "value", text = value, x = labelW + PAD, y = 0, width = valueW, height = valueH },
			{ key = "note", text = note, x = columns and labelW + valueW + 2 * PAD or 0, y = noteY, width = math.max(noteWidth, 1), height = noteH },
		} }
		if index == 1 and #levels > 1 then row.sparkY = bodyH + GAP;bodyH = row.sparkY + SPARK_H end
		row.height = bodyH + GAP;plan.rows[index] = row;height = height + row.height
	end
	plan.height = height
	return plan
end

-- A large spread continues by rows; an individual large field continues by
-- the Book's balanced rich-text units. Every field is retained at its font.
function SS.Pages(plan, limit)
	if plan.height <= limit then return { plan } end
	local pages, measure = {}, plan.measure
	local header, headHeight = plan.header, plan.headHeight
	local function Text(role)
		return function(value, width) return measure(role, value, width) end
	end
	local function NewPage()
		local page = { width = plan.width, inner = plan.inner, header = header, headHeight = headHeight,
			data = plan.data, levels = plan.levels, rows = {}, look = plan.look, fontKey = plan.fontKey, measure = measure,
			height = headHeight + GAP + PAD }
		pages[#pages + 1] = page;return page
	end
	local minimum = 0
	for _, role in ipairs({ "label", "value", "note" }) do minimum = math.max(minimum, measure(role, "W", plan.inner).height) end
	if headHeight + GAP + PAD + minimum + GAP > limit then
		local rest = header
		while rest ~= "" do
			local piece;piece, rest = A.Book.SplitText(rest, plan.inner, limit - 7 - 5 - PAD - GAP, Text("head"))
			local h = measure("head", piece, plan.inner).height
			pages[#pages + 1] = { width = plan.width, inner = plan.inner, header = piece, headHeight = 7 + h + 5,
				data = plan.data, levels = plan.levels, rows = {}, look = plan.look, height = 7 + h + 5 + GAP + PAD }
		end
		header, headHeight = "", 0
	end
	local page = NewPage()
	local function Add(row)
		if page.height + row.height > limit then page = NewPage() end
		page.rows[#page.rows + 1] = row;page.height = page.height + row.height
	end
	for _, row in ipairs(plan.rows) do
		local capacity = limit - headHeight - GAP - PAD
		if row.height <= capacity then Add(row)
		else
			-- Full-width field continuations preserve even a long value or
			-- translated label; they are not only a special case for notes.
			local fragment, y = { index = row.index, source = row.source, fields = {} }, 0
			local function Flush()
				if #fragment.fields > 0 or fragment.sparkY then fragment.height = y;Add(fragment) end
				fragment, y = { index = row.index, source = row.source, fields = {} }, 0
			end
			for _, role in ipairs({ "label", "value", "note" }) do
				local rest = A.Book.WrapText(row.source[role], plan.inner, Text(role))
				while rest ~= "" do
					local room = capacity - y - GAP
					if room < measure(role, "W", plan.inner).height then Flush();room = capacity - GAP end
					local piece;piece, rest = A.Book.SplitText(rest, plan.inner, room, Text(role))
					local h = measure(role, piece, plan.inner).height
					fragment.fields[#fragment.fields + 1] = { key = role, text = piece, x = 0, y = y, width = plan.inner, height = h }
					y = y + h + GAP
					if rest ~= "" then Flush() end
				end
			end
			if row.sparkY then
				if y + SPARK_H + GAP > capacity then Flush() end
				fragment.sparkY = y;y = y + SPARK_H + GAP
			end
			Flush()
		end
	end
	return pages
end

function SS.Create(parent)
	local spread = K.Card(parent, { solid = true })
	spread:EnableMouse(false)
	spread.headText = K.Text(spread, K.size.section, "LEFT", "head", true)
	spread.rule = K.Rule(spread)
	spread.rows, spread.bars = {}, {}

	function spread:Height()
		return self.layout and self.layout.height or 0
	end

	function spread:SetChapter(set, chapter, look, opts, layout)
		look = look or SV().Look()
		layout = layout or SS.Measure(set, chapter, self:GetWidth(), look, opts)
		self.layout, self.data, self.levels, self.set = layout, layout.data, layout.levels, set
		local head = self.headText
		K.InkFont(head, K.size.section, true);SV().Paint(head, "head", look)
		head:ClearAllPoints();head:SetPoint("TOPLEFT", PAD + 2, -7)
		head:SetWidth(layout.inner);head:SetWordWrap(false);head:SetMaxLines(0);head:SetJustifyV("TOP")
		head:SetText(layout.header);head:SetShown(layout.header ~= "")
		self.rule:ClearAllPoints();self.rule:SetPoint("TOPLEFT", PAD, -layout.headHeight)
		self.rule:SetPoint("TOPRIGHT", -PAD, -layout.headHeight)
		self.rule:SetShown(layout.header ~= "")
		local rule = SV().Ink("rule", look)
		self.rule:SetColorTexture(rule[1], rule[2], rule[3], rule[4] or 1)
		local fill = look == "Parchment" and T.paper and (T.paper.card or T.paper.fill)
		if fill then
			self:SetBackdropColor(fill[1], fill[2], fill[3], fill[4] or 1)
			self:SetBackdropBorderColor(rule[1], rule[2], rule[3], rule[4] or 1)
		end
		local y, sparkRow, sparkY = layout.headHeight + GAP, nil, nil
		for index = 1, math.max(#self.rows, #layout.rows) do
			local data, row = layout.rows[index], self.rows[index]
			if data and not row then
				row = CreateFrame("Frame", nil, self)
				for _, role in ipairs({ "label", "value", "note" }) do
					local spec = ROLES[role]
					row[role] = K.Text(row, K.size[spec[1]], "LEFT", spec[2])
				end
				self.rows[index] = row
			end
			if row then
				row:SetShown(data ~= nil)
				if data then
					row:ClearAllPoints();row:SetPoint("TOPLEFT", PAD + 2, -y)
					row:SetPoint("TOPRIGHT", -PAD, -y);row:SetHeight(data.height)
					for _, role in ipairs({ "label", "value", "note" }) do row[role]:Hide();row[role]:SetText("") end
					for _, field in ipairs(data.fields) do
						local text, spec = row[field.key], ROLES[field.key]
						K.InkFont(text, K.size[spec[1]], false);SV().Paint(text, spec[2], look)
						text:ClearAllPoints();text:SetPoint("TOPLEFT", field.x, -field.y)
						text:SetSize(field.width, field.height);text:SetWordWrap(false);text:SetMaxLines(0)
						text:SetJustifyV("TOP");text:SetSpacing(0);text:SetText(field.text);text:SetShown(field.text ~= "")
					end
					local original = layout.data[data.index]
					row:EnableMouse(original and original.tip ~= nil or false)
					E.LootGuide.Kit.Tooltip(row, original and original.tip and original.label, original and original.tip)
					if data.sparkY then sparkRow, sparkY = row, data.sparkY end
					y = y + data.height
				end
			end
		end
		local levels, maxT = layout.levels, 0
		for _, level in ipairs(levels) do maxT = math.max(maxT, level.time or 0) end
		local count = #levels
		local plotW = math.min(SPARK_W, layout.inner)
		local gap = count > 0 and math.min(1, plotW / (2 * count)) or 1
		local barW = count > 0 and (plotW - (count - 1) * gap) / count or 1
		for index = 1, math.max(#self.bars, count) do
			local level, bar = levels[index], self.bars[index]
			if level and not bar then
				bar = CreateFrame("Frame", nil, self)
				bar.fill = bar:CreateTexture(nil, "ARTWORK")
				bar.fill:SetTexture(E.media.flat)
				bar.fill:SetPoint("BOTTOMLEFT");bar.fill:SetPoint("BOTTOMRIGHT")
				bar:SetScript("OnEnter", function(own)
					local tip = GameTooltip
					tip:SetOwner(own, "ANCHOR_TOP")
					E.UIKit.TipTitle(tip, (L["Level %d"]):format(own.level))
					local color = T.text.secondary
					tip:AddLine(own.time and (L["%s played"]):format(Story().Grammar.Duration(own.time, "ledger")) or L["Not recorded"],
						color[1], color[2], color[3])
					tip:Show()
				end)
				bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
				self.bars[index] = bar
			end
			if bar then
				local show = level ~= nil and sparkRow ~= nil and count > 1
				bar:SetShown(show);bar:EnableMouse(show)
				if show then
					bar.level, bar.time = level.n, level.time
					bar:ClearAllPoints();bar:SetSize(barW, SPARK_H)
					bar:SetPoint("TOPLEFT", sparkRow, "TOPLEFT", layout.inner - plotW + (index - 1) * (barW + gap), -sparkY)
					local h = maxT > 0 and level.time and math.max(2, SPARK_H * level.time / maxT) or 1
					bar.fill:SetHeight(h)
					local longest = level.time and maxT > 0 and level.time == maxT
					PaintBar(bar.fill, longest and E.media.accentColor or SV().Ink(level.time and "secondary" or "dim", look))
				end
			end
		end
		self:SetHeight(self:Height())
	end
	return spread
end
