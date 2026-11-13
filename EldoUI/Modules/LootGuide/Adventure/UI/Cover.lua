-- EldoUI My Adventure: the era cover card.
--
--   +------------------------------------------------+
--   |        ═══════  PART III  ═══════              |
--   |            The Duskwood years                   |
--   |       levels 20-29 · Sep 8 - Sep 19             |
--   |                  [ keepsake ]                   |
--   |   "Ten levels and three zones; ..."             |
--   |   [26h 40m] [132 quests] [7 deaths] [2 met]     |
--   |   Main zones: Duskwood · Redridge · Wetlands    |
--   +------------------------------------------------+
--
-- Each part of the Book opens with one. The ribbon carries the era's color,
-- the epigraph is the part's own opening sentence from the story engine
-- (with its facts on hover), the chips and zones are sums of the level log
-- for the era's levels, and the keepsake is the era's lead fact. The very
-- first cover says where the story happened.
--
--   A.Cover.Create(parent) -> cover
--   cover:SetPart(book, set, part[, look])
--   A.Cover.Data(book, set, part) -> { label, title, span, epigraph, chips, zones, icon, lead }
local _, E = ...
local L = E.L
local A = E.Adventure
local J = E.Journal
local K = E.AdventureKit
local T = E.tokens

local C = {}
A.Cover = C

local function SV() return A.StoryView end
local function Story() return E.Story end

local RIBBON_ATLAS = "UI-Frame-Neutral-Ribbon"
local KEEP_ICON = "Interface\\Icons\\INV_Misc_Book_09"

-- The icon of a lead fact: the item, else the journal's icon for its kind.
local function FactIcon(fact)
	if not fact then return nil end
	local v = fact.v or {}
	if fact.kind == "loot" and v.item and C_Item and C_Item.GetItemIconByID then
		local ok, icon = pcall(C_Item.GetItemIconByID, v.item)
		if ok and icon then return icon end
	end
	local icons = J.ICON or {}
	local kind = fact.kind
	if kind == "raidboss" or kind == "bossagain" then kind = "boss" end
	if kind == "raid" or kind == "runs" or kind == "run" then kind = "dungeon" end
	return icons[kind] or KEEP_ICON
end
C.FactIcon = FactIcon

local function DateSpan(set, a, b)
	local Gr = Story().Grammar
	local first = set.levels[a] and set.levels[a].at
	if not first and a == set.startedLevel then first = set.input.started end
	local last = set.levels[b + 1] and set.levels[b + 1].at or (b == set.level and set.now) or (set.levels[b] and set.levels[b].at)
	if not (first and last) then return nil end
	local x, y = Gr.Date(first, "short"), Gr.Date(last, "short")
	if x == y then return x end
	return x .. " - " .. y
end

function C.Data(book, set, part)
	local Gr = Story().Grammar
	local data = { part = part }
	data.label = part.number and (L["Part %s"]):format(Story().Plan.Roman(part.number)) or L["Before the journal"]
	data.title = part.title or ""
	local span = { Gr.Levels(part.a, part.b) }
	local dates = DateSpan(set, part.a, part.b)
	if dates then span[#span + 1] = dates end
	data.span = table.concat(span, " · ")
	data.epigraph = part.opening and part.opening[1]
	-- Chips: sums of the level log for these levels, and the people met.
	local chips = {}
	local era = set.byId["p:era:" .. tostring(part.index)]
	if era and era.v.played then chips[#chips + 1] = { Gr.Duration(era.v.played, "ledger"), L["played"] } end
	local quests = SV().Sum(set, "quests", part.a, part.b)
	if quests and quests > 0 then chips[#chips + 1] = { quests, quests == 1 and L["quest"] or L["quests"] } end
	local deaths = SV().Sum(set, "deaths", part.a, part.b)
	if deaths then chips[#chips + 1] = { deaths, deaths == 1 and L["death"] or L["deaths"] } end
	local met = 0
	for _, fact in ipairs(set:Kind("met")) do
		if fact.l and fact.l >= part.a and fact.l <= part.b then met = met + 1 end
	end
	if met > 0 then chips[#chips + 1] = { met, met == 1 and L["companion met"] or L["companions met"] } end
	data.chips = chips
	-- The main zones by time.
	local _, _, _, times = Story().Plan.ZoneTimes(set, part.a, part.b)
	local zones = {}
	for zone, t in pairs(times or {}) do
		local row = Gr.PlaceRow(zone)
		if t >= Story().Tuning.zoneMinSeconds and not (row and (row.type == "instance" or row.type == "raid")) then
			zones[#zones + 1] = { zone, t }
		end
	end
	table.sort(zones, function(x, y) if x[2] ~= y[2] then return x[2] > y[2] end return x[1] < y[1] end)
	local names = {}
	for i = 1, math.min(3, #zones) do names[i] = Gr.Place(zones[i][1], "head", true) end
	data.zones = names
	-- The era's lead fact (from the plan).
	local plan = book.plan
	for _, planEra in ipairs(plan and plan.eras or {}) do
		if planEra.key == part.key then data.lead = planEra.lead end
	end
	if not data.lead then
		local chapter = part.chapters and part.chapters[1]
		data.lead = chapter and chapter.opening and chapter.opening[1] and set.byId[chapter.opening[1].lead]
	end
	data.icon = FactIcon(data.lead)
	data.first = book.parts[1] == part
	return data
end

function C.Create(parent)
	local cover = CreateFrame("Frame", nil, parent)
	cover:EnableMouse(true)
	cover.ribbon = cover:CreateTexture(nil, "ARTWORK")
	cover.ribbon:SetSize(240, 56)
	cover.ribbon:SetPoint("TOP", 0, -18)
	cover.ruleL = cover:CreateTexture(nil, "ARTWORK")
	cover.ruleR = cover:CreateTexture(nil, "ARTWORK")
	cover.ruleL:SetTexture(E.media.flat)
	cover.ruleR:SetTexture(E.media.flat)
	E:Hairline(cover.ruleL, "h", 1)
	E:Hairline(cover.ruleR, "h", 1)
	cover.label = K.Text(cover, T.size.small, "CENTER", "head", true)
	cover.label:SetPoint("CENTER", cover.ribbon, "CENTER", 0, 2)
	-- The rules run on the label's line: the ribbon's middle, 2 higher.
	local labelY = -(18 + 56 / 2) + 2
	cover.ruleL:SetPoint("RIGHT", cover.label, "LEFT", -12, 0)
	cover.ruleL:SetPoint("LEFT", cover, "TOPLEFT", 24, labelY)
	cover.ruleR:SetPoint("LEFT", cover.label, "RIGHT", 12, 0)
	cover.ruleR:SetPoint("RIGHT", cover, "TOPRIGHT", -24, labelY)
	-- The column of centered lines spans the cover with top corners only,
	-- each under the one above, so every box keeps its own height.
	cover.title = K.Text(cover, 22, "CENTER", "head", true)
	cover.title:SetPoint("TOPLEFT", 24, -(18 + 56 + 6)) -- under the ribbon
	cover.title:SetPoint("TOPRIGHT", -24, -(18 + 56 + 6))
	cover.span = K.Text(cover, T.size.small, "CENTER", "secondary")
	cover.span:SetPoint("TOPLEFT", cover.title, "BOTTOMLEFT", 0, -6)
	cover.span:SetPoint("TOPRIGHT", cover.title, "BOTTOMRIGHT", 0, -6)
	cover.subtitle = K.Text(cover, T.size.small, "CENTER", "dim")
	cover.subtitle:SetPoint("TOPLEFT", cover.span, "BOTTOMLEFT", 0, -4)
	cover.subtitle:SetPoint("TOPRIGHT", cover.span, "BOTTOMRIGHT", 0, -4)
	cover.art = K.Art(cover, 64)
	cover.art:SetPoint("TOP", cover.subtitle, "BOTTOM", 0, -18)
	cover.epigraph = K.Text(cover, T.size.body, "CENTER", "body")
	cover.epigraph:SetPoint("TOPLEFT", cover.subtitle, "BOTTOMLEFT", 8, -(18 + 64 + 18)) -- under the 64 px art
	cover.epigraph:SetPoint("TOPRIGHT", cover.subtitle, "BOTTOMRIGHT", -8, -(18 + 64 + 18))
	cover.epigraph:SetWordWrap(true)
	cover.epigraph:SetSpacing(3)
	cover.chips = {}
	cover.zones = K.Text(cover, T.size.small, "CENTER", "secondary")
	cover.zones:SetWordWrap(true)
	cover.storyMap = {}
	if SV() then SV().HookLinks(cover) end

	function cover:SetPart(book, set, part, look)
		look = look or SV().Look()
		local data = C.Data(book, set, part)
		self.data = data
		self.storySet = set
		wipe(self.storyMap)
		local era = SV().EraColor(part.index or 1, look)
		local isRibbon = E:SetClientAtlas(self.ribbon, RIBBON_ATLAS, nil)
		self.ribbon:SetShown(isRibbon)
		if isRibbon then self.ribbon:SetVertexColor(era[1], era[2], era[3], 1) end
		self.ruleL:SetShown(not isRibbon)
		self.ruleR:SetShown(not isRibbon)
		self.ruleL:SetVertexColor(era[1], era[2], era[3], 1)
		self.ruleR:SetVertexColor(era[1], era[2], era[3], 1)
		self.label:SetText(E:CaptionText(data.label))
		SV().Paint(self.label, isRibbon and "body" or "head", look)
		self.title:SetText(data.title)
		SV().Paint(self.title, "head", look)
		self.span:SetText(data.span)
		SV().Paint(self.span, "secondary", look)
		self.subtitle:SetText(data.first and Story().Export.subtitle or "")
		SV().Paint(self.subtitle, "dim", look)
		K.SetIcon(self.art.icon, data.icon)
		self.art:SetShown(data.icon ~= nil)
		if data.epigraph then
			self.epigraph:SetText(SV().Linked(data.epigraph, "cover:" .. tostring(part.key), 1, self.storyMap, look))
		else
			self.epigraph:SetText("")
		end
		SV().Paint(self.epigraph, "body", look)
		-- Chips centered in one row.
		local total, widths = 0, {}
		for index = 1, math.max(#self.chips, #data.chips) do
			local chip = self.chips[index]
			local entry = data.chips[index]
			if entry and not chip then
				chip = K.StatPill(self)
				self.chips[index] = chip
			end
			if chip then
				chip:SetShown(entry ~= nil)
				if entry then
					chip:Set(entry[1], entry[2])
					widths[index] = chip:GetWidth()
					total = total + widths[index] + 8
				end
			end
		end
		local x = -(total - 8) / 2
		for index, entry in ipairs(data.chips) do
			local chip = self.chips[index]
			if entry and chip then
				chip:ClearAllPoints()
				chip:SetPoint("TOPLEFT", self.epigraph, "BOTTOM", x, -18)
				x = x + widths[index] + 8
			end
		end
		self.zones:ClearAllPoints()
		self.zones:SetPoint("TOPLEFT", self.epigraph, "BOTTOMLEFT", -8, -(18 + 18 + 12))
		self.zones:SetPoint("TOPRIGHT", self.epigraph, "BOTTOMRIGHT", 8, -(18 + 18 + 12))
		self.zones:SetText(#data.zones > 0 and (L["Main zones: %s"]):format(table.concat(data.zones, " · ")) or "")
		SV().Paint(self.zones, "secondary", look)
		if SV().Motion() and self.animate then E:PopIn(self, 0.98) end
	end
	return cover
end
