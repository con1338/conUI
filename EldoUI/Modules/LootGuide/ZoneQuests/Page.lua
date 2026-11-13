-- EldoUI Zone Quests: the Catalog > Zones section.
--
--   +--------------------+-----------------------------------------+
--   | Elwynn Forest      | Elwynn Forest           34 / 81 done   |
--   | [=====-----] 34/81 | [My quests] [Hide done] [Hide gray] ... |
--   | Westfall           | AVAILABLE NOW  12                       |
--   | [==--------]  9/52 |  [10] A quest (2/4) · Marshal Dughan [Map]|
--   | ...                | NEEDS A PREREQUISITE  5                 |
--   +--------------------+-----------------------------------------+
--
-- The zone list on the left (your zone first when it has quests), the
-- quests left and done on the right, grouped Available now / In your
-- quest log / Needs a prerequisite / Too low level / Done, with level,
-- chain step and giver; the Map button sets a waypoint on the giver.
-- Without EldoUI_LootData the section says the data folder is needed and
-- lists only the quests the game showed you.
local _, E = ...
local L = E.L
local Key = E.Key
local LG = E.LootGuide
local Kit = LG.Kit
local P = LG.PageKit
local Z = E:GetModule("ZoneQuests")

local ZONE_WIDTH = 230
local ZONE_ROW = 34

local function State()
	local ui = LG:UI()
	if type(ui.zoneQuests) ~= "table" then ui.zoneQuests = {} end
	return ui.zoneQuests
end

local function Hex(color) return E:TokenHex(color) end
local function Secondary(text) return Hex(E.tokens.text.secondary) .. text .. "|r" end

-- Fill color of a zone's bar: done share, accent.
local function ZoneRow(child)
	local row = CreateFrame("Button", nil, child)
	row.selected = row:CreateTexture(nil, "BACKGROUND")
	row.selected:SetAllPoints()
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	row.name = Kit.Text(row, 12, "LEFT")
	row.name:SetPoint("TOPLEFT", 6, -3)
	row.name:SetPoint("TOPRIGHT", -60, -3)
	row.name:SetWordWrap(false)
	row.count = Kit.Text(row, 11, "RIGHT", "secondary")
	row.count:SetPoint("TOPRIGHT", -6, -4)
	row.bar = E:CreateStatusBar(row)
	row.bar:SetHeight(5)
	row.bar:SetPoint("BOTTOMLEFT", 7, 6)
	row.bar:SetPoint("BOTTOMRIGHT", -7, 6)
	row.bar:SetMinMaxValues(0, 1)
	return row
end

local function PaintZoneRow(row, zone, selected)
	row.name:SetText(zone.name)
	row.count:SetText(("%d / %d"):format(zone.done, zone.total))
	row.bar:SetMinMaxValues(0, math.max(zone.total, 1))
	row.bar:SetValue(zone.done)
	local r, g, b = Kit.Accent()
	if zone.done >= zone.total then r, g, b = unpack(E.tokens.text.good) end
	row.bar:SetStatusBarColor(r, g, b)
	local ar, ag, ab = Kit.Accent()
	row.selected:SetColorTexture(ar, ag, ab, E.tokens.pressed)
	row.selected:SetShown(selected)
	if selected then row.name:SetTextColor(ar, ag, ab) else Kit.Paint(row.name) end
	Kit.Tooltip(row, zone.name, function(tooltip)
		local sr, sg, sb = unpack(E.tokens.text.secondary)
		tooltip:AddDoubleLine(L["Done"], ("%d / %d"):format(zone.done, zone.total), sr, sg, sb, 1, 1, 1)
		tooltip:AddDoubleLine(L["Open for you now"], tostring(zone.open), sr, sg, sb, 1, 1, 1)
		E:TooltipHint(tooltip, { L["Click"], L["see the quests of this zone"] })
	end)
end

-- "[12] Title  (2/4)  · Marshal Dughan  · New in Forever"
local function RowText(row)
	local color = row.status == "done" and E.tokens.text.good or row.status == "locked" and E.tokens.text.bad
		or (row.status == "low" or row.status == "notforyou") and E.tokens.text.dim or E.tokens.text.body
	local parts = {}
	if row.level then
		local lr, lg, lb = Kit.LevelColor(row.level)
		parts[#parts + 1] = Kit.Hex(lr, lg, lb) .. ("[%d]"):format(row.level) .. "|r"
	end
	parts[#parts + 1] = Hex(color) .. (row.quest.title or ("#" .. row.id)) .. "|r"
	if (row.chainLength or 1) > 1 then parts[#parts + 1] = Secondary(("(%d/%d)"):format(row.chainPart, row.chainLength)) end
	if row.giver and row.giver.name then parts[#parts + 1] = Secondary("· " .. row.giver.name) end
	if row.new then parts[#parts + 1] = E:Highlight(L["New in Forever"]) end
	if row.repeatable then parts[#parts + 1] = Secondary(L["repeatable"]) end
	return table.concat(parts, " ")
end
Z.RowText = RowText

local STATUS_LINE = E:TranslateValues({
	available = E.Key("You can take this quest now."), turnin = E.Key("Ready to turn in."), active = E.Key("In your quest log."),
	done = E.Key("You have done this quest."), low = E.Key("Needs level %d."), locked = E.Key("Needs %s first."),
	notforyou = E.Key("Not for your side, race, class or profession."),
})

local function RowTooltip(row)
	return function(tooltip)
		local sr, sg, sb = unpack(E.tokens.text.secondary)
		local text = STATUS_LINE[row.status] or ""
		if row.status == "low" then text = text:format(row.detail or 0) end
		if row.status == "locked" then
			local prev = LG:JourneyQuest(row.detail)
			text = text:format(prev and prev.title or LG:QuestTitle(row.detail) or ("#" .. tostring(row.detail)))
		end
		E.UIKit.TipTitle(tooltip, text, true)
		if row.level then tooltip:AddDoubleLine(L["Level"], tostring(row.level), sr, sg, sb, 1, 1, 1) end
		if (row.chainLength or 1) > 1 then
			tooltip:AddDoubleLine(L["Chain"], (L["step %d of %d in the zone"]):format(row.chainPart, row.chainLength), sr, sg, sb, 1, 1, 1)
		end
		if row.giver and row.giver.name then tooltip:AddDoubleLine(L["Given by"], row.giver.name, sr, sg, sb, 1, 1, 1) end
		if row.new then tooltip:AddLine(L["New in Forever: the loot data does not have this quest; it counts since you saw it."], sr, sg, sb, true) end
		if row.quest.provenance == "classic" then tooltip:AddLine(L["Classic values; Forever may differ."], sr, sg, sb, true) end
	end
end

local function MapButton(row)
	if row.status == "done" then return nil end
	local point = LG:ZoneQuestGiverPoint(row)
	if not point then
		return { L["Map"], nil, L["Map"], L["The data has no place on your map for this quest's giver."], true }
	end
	return { L["Map"], function() Z:SetGiverWaypoint(row) end, L["Map"],
		L["Sets a waypoint on the quest giver (through the Waypoints module when it is on)."] }
end

local FILTERS = {
	{ key = "mine", label = "My quests only", tip = Key("Only quests for your side, race, class and professions.") },
	{ key = "hideDone", label = "Hide done", tip = Key("Leave out the quests you have done.") },
	{ key = "hideGray", label = "Hide gray", tip = Key("Leave out quests too low for your level to give experience.") },
	{ key = "chains", label = "Chains as one row", tip = Key("Show a quest chain as one row: the step that needs you now.") },
	{ key = "repeatables", label = "Repeatable quests", tip = Key("Also list and count quests you can do again.") },
}
Z.FILTERS = FILTERS

local function Build(parent)
	local section = CreateFrame("Frame", nil, parent)
	section.zones = P.Flow(section)
	section.zones:SetPoint("TOPLEFT", 0, 0)
	section.zones:SetPoint("BOTTOMLEFT", 0, 0)
	section.zones:SetWidth(ZONE_WIDTH)
	section.rule = section:CreateTexture(nil, "ARTWORK")
	section.rule:SetColorTexture(unpack(E.tokens.edge.divider))
	section.rule:SetWidth(E.pixel)
	section.rule:SetPoint("TOPLEFT", section.zones, "TOPRIGHT", 6, 0)
	section.rule:SetPoint("BOTTOMLEFT", section.zones, "BOTTOMRIGHT", 6, 0)

	section.title = Kit.Text(section, 14, "LEFT", "header")
	section.title:SetPoint("TOPLEFT", section.zones, "TOPRIGHT", 14, -2)
	section.summary = Kit.Text(section, 11, "RIGHT", "secondary")
	section.summary:SetPoint("TOPRIGHT", 0, -4)
	section.chips = CreateFrame("Frame", nil, section)
	section.chips:SetPoint("TOPLEFT", section.zones, "TOPRIGHT", 14, -24)
	section.chips:SetPoint("TOPRIGHT", 0, -24)
	section.chips:SetHeight(20)
	section.filterChips = {}
	for index, filter in ipairs(FILTERS) do
		local chip = P.Toggle(section.chips, filter.label, function()
			Z.db[filter.key] = not Z.db[filter.key]
			Z:Invalidate(false)
			section:Draw(true)
		end, filter.label, filter.tip)
		chip.filterKey = filter.key
		section.filterChips[index] = chip
	end
	section.flow = P.Flow(section)
	section.flow:SetPoint("TOPLEFT", section.chips, "BOTTOMLEFT", 0, -6)
	section.flow:SetPoint("BOTTOMRIGHT")

	function section:LayoutChips()
		local x, y = 0, 0
		local width = math.max((self.chips:GetWidth() or 400), 100)
		for _, chip in ipairs(self.filterChips) do
			chip:SetOn(Z.db[chip.filterKey] and true or false)
			if x > 0 and x + chip:GetWidth() > width then x, y = 0, y + 22 end
			chip:ClearAllPoints()
			chip:SetPoint("TOPLEFT", x, -y)
			x = x + chip:GetWidth() + 4
		end
		self.chips:SetHeight(y + 20)
	end

	function section:DrawZones(zones, selected)
		local flow = self.zones
		flow:Begin()
		local here = Z:CurrentZone()
		local ordered = {}
		for _, zone in ipairs(zones) do
			if zone.uiMapID == here then table.insert(ordered, 1, zone) else ordered[#ordered + 1] = zone end
		end
		for index, zone in ipairs(ordered) do
			local row = flow:Take("zone", ZoneRow)
			flow:Place(row, ZONE_ROW, 0, 2)
			PaintZoneRow(row, zone, zone.uiMapID == selected)
			if index == 1 and zone.uiMapID == here then row.name:SetText(zone.name .. " " .. Secondary(L["(here)"])) end
			row:SetScript("OnClick", function()
				State().zone = zone.uiMapID
				self:Draw(false)
			end)
		end
		flow:Finish(true)
	end

	function section:Draw(keepScroll)
		local s = State()
		self:LayoutChips()
		local flow = self.flow
		flow:Begin()
		if not Z:Ready() then
			Z:BuildLater()
			self.zones:Begin()
			self.zones:Finish()
			self.title:SetText(L["Zones"])
			self.summary:SetText("")
			P.FlowText(flow, L["The zone list is built out of combat. It shows once the fight is over."], 12, "secondary")
			flow:Finish()
			return
		end
		local zones = LG:ZoneQuestZones()
		local selected = s.zone
		local known = false
		for _, zone in ipairs(zones) do if zone.uiMapID == selected then known = true end end
		if not known then
			selected = Z:CurrentZone() or (zones[1] and zones[1].uiMapID)
			s.zone = selected
		end
		self:DrawZones(zones, selected)
		if not LG:HasData() then
			P.FlowText(flow, L["Zone quests come from EldoUI_LootData. Install that folder next to EldoUI to see every zone; until then only the quests the game showed you are listed."], 12, "secondary")
			flow:Space(8)
		end
		if not selected then
			self.title:SetText(L["Zones"])
			self.summary:SetText("")
			P.FlowText(flow, L["No zone with quests yet."], 12, "secondary")
			flow:Finish(keepScroll)
			return
		end
		local total, done = LG:ZoneQuestCounts(selected)
		local N = E.Adventure and E.Adventure.Next
		self.title:SetText(N and N.ZoneName and N.ZoneName(selected) or LG:MapName(selected) or ("#" .. selected))
		self.summary:SetText((L["%d / %d done"]):format(done, total))
		local rows = LG:ZoneQuests(selected)
		local groups = {}
		for _, row in ipairs(rows) do
			groups[row.group] = groups[row.group] or {}
			table.insert(groups[row.group], row)
		end
		local any = false
		for _, key in ipairs(Z.GROUPS) do
			local list = groups[key]
			if list then
				any = true
				P.FlowCaption(flow, Z.GROUP_TITLE[key], tostring(#list))
				for _, row in ipairs(list) do
					local open = LG:Quest(row.id) and LG:IsPageOn("database") and function() LG:OpenDatabase("quests", row.id) end or nil
					P.FlowLine(flow, RowText(row), open, MapButton(row), row.quest.title or ("#" .. row.id), RowTooltip(row), 4)
				end
			end
		end
		if not any then P.FlowText(flow, L["No quest of this zone matches the filters."], 12, "secondary") end
		flow:Finish(keepScroll)
	end

	section:SetScript("OnSizeChanged", function(self) if self:IsShown() then self:LayoutChips() end end)
	LG:On("section-zonequests", function(changed)
		if section:IsShown() and (changed.data or changed.journey or changed.quests or changed.player or changed.settings) then
			section:Draw(true)
		end
	end)
	Z.section = section
	return section
end

-- "/eui zones westfall" -> that zone.
local function FindZone(word)
	word = E:FoldText(strtrim(tostring(word or "")))
	if word == "" then return end
	for _, zone in ipairs(LG:ZoneQuestZones()) do
		local name = E:FoldText(zone.name)
		if name == word or (#word >= 3 and name:find(word, 1, true)) then return zone.uiMapID end
	end
end

local SECTION = {
	title = "Zones",
	icon = "Interface\\Icons\\INV_Misc_Map_01",
	desc = "Every zone's quests: how many you have done, what is left and who gives it, with a Map button for each giver.",
	order = 60,
	command = "zones",
	usage = Key("open Catalog > Zones; add a zone name (/eui zones westfall)"),
	argument = FindZone,
	build = Build,
	show = function(section, arg)
		if tonumber(arg) then State().zone = tonumber(arg) end
		section:Draw()
	end,
	search = function(text)
		local out = {}
		local word = E:FoldText(text)
		for _, zone in ipairs(LG:ZoneQuestZones()) do
			if E:FoldText(zone.name):find(word, 1, true) then out[#out + 1] = { title = zone.name, arg = zone.uiMapID } end
		end
		return out
	end,
}
Z.SECTION = SECTION

function Z:StartPage()
	if LG.RegisterCatalogueSection then LG:RegisterCatalogueSection("zones", SECTION) end
end

function Z:StopPage()
	if LG.UnregisterCatalogueSection then LG:UnregisterCatalogueSection("zones") end
end

-- The quest list or counts changed: redraw an open section.
function Z:Changed()
	if self.section and self.section:IsShown() then self.section:Draw(true) end
	if self.RefreshPins then self:RefreshPins() end
end

-- Open the section on a zone (Zone Info's line, slash command).
function Z:Open(uiMapID)
	if not self:Running() then return end
	LG:OpenSection("zones", uiMapID)
end
