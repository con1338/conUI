-- EldoUI Loot Guide: Catalog > Crafting.
--
-- Professions across the top (yours first with your skill when "Your
-- professions first" is on), a filter row (search, kind, usable by me,
-- known or not, skill range), the craft rows (result item, skill needed in
-- its color band, a check when you know it, gain and wishlist star like
-- any item) and a detail panel: reagents with how many you own (bags and
-- bank), the recipe item and where it comes from (trainer, vendor with
-- standing, drop, quest), each with a Map button.
--
-- Data: EldoUI_LootData's crafts, trainers and recipe sources; recipes you
-- open in your profession window are cached (read-only), so they show and
-- are marked known even without the loot data. Nothing here crafts, buys
-- or learns anything.
local _, E = ...
local LG = E.LootGuide
local Kit = LG.Kit
local P = LG.PageKit
local L = E.L

local Key = E.Key
local DETAIL_WIDTH = 260
local KIND_LABEL = E:TranslateValues({ armor = E.Key("Armor"), weapon = E.Key("Weapons"), consumable = E.Key("Consumables"), other = E.Key("Other") })
local RANGES = { { 1, 74 }, { 75, 149 }, { 150, 224 }, { 225, 300 } }

local function State()
	local ui = LG:UI()
	if type(ui.crafting) ~= "table" then ui.crafting = {} end
	local s = ui.crafting
	if s.known ~= "known" and s.known ~= "unknown" then s.known = "all" end
	return s
end

local function Kind(record)
	local class = record and record.class
	if class == 4 then return "armor" end
	if class == 2 then return "weapon" end
	if class == 0 then return "consumable" end
	return "other"
end

local function Owned(itemID)
	local count = C_Item.GetItemCount and C_Item.GetItemCount(itemID, true) or 0
	if issecretvalue and issecretvalue(count) then return 0 end
	return tonumber(count) or 0
end

local function BandText(craft, skill)
	local band, estimated, thresholds = LG:SkillBand(craft, skill)
	local color = LG.BAND_COLORS[band or ""] or Kit.SECONDARY
	return Kit.Hex(unpack(color)) .. tostring(craft.rank or "?") .. "|r", band, estimated, thresholds
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function Rows(skill)
	local s = State()
	local mySkill = LG:Player().professions[skill]
	local text = E:FoldText(s.search or "")
	local out = {}
	for _, craft in ipairs(LG:ProfessionCrafts(skill)) do
		local record = LG:ItemRecord(craft.result)
		local name = record and record.name or C_Item.GetItemInfo(craft.result) or ""
		if issecretvalue and issecretvalue(name) then name = "" end
		local band = LG:SkillBand(craft, mySkill)
		local ok = true
		if text ~= "" and not E:FoldText(tostring(name)):find(text, 1, true) then ok = false end
		if ok and s.kind and Kind(record) ~= s.kind then ok = false end
		if ok and s.usable and record and not LG:CanUseRecord(record, true) then ok = false end
		if ok and s.known ~= "all" then
			local known = LG:CraftKnown(craft.id)
			if (s.known == "known") ~= known then ok = false end
		end
		if ok and s.range then
			local range = RANGES[s.range]
			if range and ((craft.rank or 0) < range[1] or (craft.rank or 0) > range[2]) then ok = false end
		end
		if ok and not LG.db.craftShowGrey and band == "grey" then ok = false end
		if ok then out[#out + 1] = craft end
	end
	return out
end

local function RowCreate(row)
	row.cell = P.ItemCell(row)
	row.cell:SetAllPoints()
	row.select = row:CreateTexture(nil, "BACKGROUND", nil, 2)
	row.select:SetAllPoints()
end

local function RowUpdate(row, craft)
	local section = row.list.section
	local mySkill = LG:Player().professions[section.skill]
	local rank = BandText(craft, mySkill)
	local known = LG:CraftKnown(craft.id)
	local tag = rank .. (known and ("  " .. Kit.Hex(unpack(Kit.GOOD)) .. L["known"] .. "|r") or "")
	local count = (craft.count or 1) > 1 and (" x" .. craft.count) or ""
	P.SetItem(row.cell, { itemID = craft.result, tag = tag, sub = count ~= "" and (L["makes"] .. count) or nil,
		onClick = function() section:Select(craft.id) end })
	local r, g, b = Kit.Accent()
	row.select:SetColorTexture(r, g, b, 0.15)
	row.select:SetShown(State().selected == craft.id)
end

---------------------------------------------------------------------------
-- Detail
---------------------------------------------------------------------------
local function SourceButton(kind, id, title)
	return P.MapButton(kind, id, title)
end

local function DrawDetail(section, craft)
	local flow = section.flow
	flow:Begin()
	if not craft then
		P.FlowText(flow, L["Pick a craft to see its reagents and where the recipe comes from."], 12, "secondary")
		flow:Finish()
		return
	end
	local mySkill = LG:Player().professions[section.skill]
	P.FlowItem(flow, { itemID = craft.result, onClick = function() P.OpenItem(craft.result) end })
	local _, band, estimated, thresholds = BandText(craft, mySkill)
	if craft.rank then
		local parts = {}
		for _, key in ipairs({ "orange", "yellow", "green", "grey" }) do
			parts[#parts + 1] = Kit.Hex(unpack(LG.BAND_COLORS[key])) .. tostring(thresholds[key]) .. "|r"
		end
		P.FlowText(flow, (L["%s %d"]):format(LG:ProfessionName(section.skill), craft.rank) .. "   " .. table.concat(parts, " "), 12)
		if estimated then
			P.FlowText(flow, L["Colors are estimated from the usual steps until you open your profession window."], 10, "dim")
		end
		if band == "red" then P.FlowText(flow, (L["You need %d skill to learn it."]):format(craft.rank), 11, "secondary") end
	end
	P.FlowText(flow, LG:CraftKnown(craft.id) and (Kit.Hex(unpack(Kit.GOOD)) .. L["You know this recipe."] .. "|r")
		or L["You do not know this recipe yet."], 11, "secondary")
	-- Guild crafters (Modules/Characters/GuildCrafters.lua).
	local guildLine = E.GuildCraftersLine and E:GuildCraftersLine(craft.id)
	if guildLine then P.FlowText(flow, guildLine, 11, "secondary") end
	-- Lines other modules add (the Profession Planner's Pin): fn(flow, craft, P).
	for _, extra in ipairs(LG.craftDetailExtras or {}) do
		local ok, err = pcall(extra, flow, craft, P)
		if not ok then geterrorhandler()(err) end
	end
	-- Reagents with what you own.
	P.FlowCaption(flow, L["Reagents"])
	for _, reagent in ipairs(craft.reagents or {}) do
		local have = Owned(reagent.id)
		local color = have >= reagent.count and Kit.GOOD or Kit.SECONDARY
		P.FlowItem(flow, { itemID = reagent.id, tag = Kit.Hex(unpack(color)) .. ("%d/%d"):format(have, reagent.count) .. "|r",
			onClick = function() P.OpenItem(reagent.id) end })
	end
	if #(craft.reagents or {}) == 0 then P.FlowText(flow, L["No reagents known."], 11, "secondary") end
	-- Recipe sources.
	P.FlowCaption(flow, L["Recipe"])
	if not LG:HasData() then
		P.FlowText(flow, L["Where recipes come from needs EldoUI_LootData. Install it next to EldoUI to see trainers, vendors, drops and quests."], 11, "secondary")
		flow:Finish()
		return
	end
	local sources = LG:RecipeSources(craft)
	local any = false
	if sources.trainer then
		any = true
		local cost = P.MoneyText(sources.trainer.cost)
		P.FlowText(flow, (L["Trainer: %s %d"]):format(LG:ProfessionName(section.skill), sources.trainer.value or 0)
			.. (cost and ("  ·  " .. cost) or ""), 12)
		for index, npc in ipairs(sources.trainer.npcs or {}) do
			if index > 4 then
				P.FlowText(flow, E:Plural(#sources.trainer.npcs - 4, "and %d more trainer", "and %d more trainers"):format(#sources.trainer.npcs - 4), 11, "secondary", 12)
				break
			end
			local mob = LG:Mob(npc)
			local name = mob and mob.name or L["NPC %s"]:format(npc)
			local camps = LG:SpawnPoints("npc", npc)
			local zone = camps[1] and LG:SpawnZone(camps[1])
			P.FlowLine(flow, name .. (zone and ("  " .. E:TextHex("secondary") .. zone .. "|r") or ""), nil, SourceButton("npc", npc, name), name,
				L["A trainer who teaches this recipe."], 12)
		end
	end
	for _, recipe in ipairs(sources.recipes) do
		any = true
		P.FlowItem(flow, { itemID = recipe.itemID, onClick = function() P.OpenItem(recipe.itemID) end })
		for _, vendor in ipairs(recipe.vendors) do
			local camps = LG:SpawnPoints("npc", vendor.id)
			local zone = camps[1] and LG:SpawnZone(camps[1])
			local extra = {}
			if zone then extra[#extra + 1] = zone end
			if vendor.standing then
				extra[#extra + 1] = Kit.Hex(LG:StandingColor(vendor.standing)) .. LG:StandingName(vendor.standing) .. "|r " .. (LG:FactionName(vendor.faction) or "")
			end
			if vendor.limited then extra[#extra + 1] = L["limited stock"] end
			local price = P.MoneyText(vendor.price)
			if price then extra[#extra + 1] = price end
			P.FlowLine(flow, (L["Sold by %s"]):format(vendor.name or L["NPC %s"]:format(vendor.id)) .. "  " .. E:TextHex("secondary") .. table.concat(extra, "  ·  ") .. "|r",
				nil, SourceButton("npc", vendor.id, vendor.name), vendor.name, L["A vendor who sells the recipe."], 12)
		end
		for index, drop in ipairs(recipe.drops) do
			if index > 4 then
				P.FlowText(flow, (L["and %d more"]):format(#recipe.drops - 4), 11, "secondary", 12)
				break
			end
			local chance = type(drop.chance) == "number" and ("  " .. Kit.Hex(Kit.ChanceColor(drop.chance)) .. Kit.ChanceText(drop.chance) .. "|r") or ""
			local button = (drop.kind == "npc" or drop.kind == "object") and SourceButton(drop.kind, drop.id, drop.name) or nil
			if drop.instance and LG:InstanceInfo(drop.instance) then
				button = { L["Journal"], function() LG:Open("journal", { key = drop.instance, npc = drop.id }) end, L["Journal"], L["Opens the boss in the Journal."] }
			end
			P.FlowLine(flow, (L["Drop: %s"]):format(P.SourceLine(drop)) .. chance, nil, button, L["Drop"], L["A creature or chest that drops the recipe."], 12)
		end
		for _, questID in ipairs(recipe.quests) do
			P.FlowLine(flow, (L["Quest: %s"]):format(LG:QuestTitle(questID) or ("#" .. questID)), function()
				if LG.OpenDatabase and LG:IsPageOn("database") then LG:OpenDatabase("quests", questID) end
			end, nil, L["Quest"], function(tip) E.UIKit.TipText(tip, L["A quest that rewards the recipe."]) Kit.TooltipHint(tip, { L["Click"], L["see the quest"] }) end, 12)
		end
	end
	if not any then
		P.FlowText(flow, craft.seen and L["Seen in your profession window; the loot data does not list where it comes from."]
			or L["The loot data does not list where this recipe comes from."], 11, "secondary")
	end
	flow:Finish()
end

---------------------------------------------------------------------------
-- Menus
---------------------------------------------------------------------------
local function Menu(owner, title, entries, get, set)
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(title)
		for _, entry in ipairs(entries) do
			root:CreateRadio(entry[2], function() return get() == entry[1] end, function() set(entry[1]) end)
		end
	end, { at = "owner" })
end

---------------------------------------------------------------------------
-- Section
---------------------------------------------------------------------------
local function Build(parent)
	local section = CreateFrame("Frame", nil, parent)
	section.profs = {}
	section.strip = CreateFrame("Frame", nil, section)
	section.strip:SetPoint("TOPLEFT")
	section.strip:SetPoint("TOPRIGHT")
	section.strip:SetHeight(22)

	local bar = CreateFrame("Frame", nil, section)
	bar:SetPoint("TOPLEFT", section.strip, "BOTTOMLEFT", 0, -6)
	bar:SetPoint("TOPRIGHT", section.strip, "BOTTOMRIGHT", 0, -6)
	bar:SetHeight(20)
	section.bar = bar
	bar.search = CreateFrame("EditBox", nil, bar, "SearchBoxTemplate")
	E:SearchHint(bar.search)
	bar.search:SetSize(150, 20)
	bar.search:SetPoint("LEFT", 4, 0)
	bar.search:SetAutoFocus(false)
	E:SkinEditBox(bar.search)
	Kit.Tooltip(bar.search, L["Search"], L["Filters the crafts by the name of what they make."])
	bar.search:HookScript("OnTextChanged", function(self, typed)
		if not typed then return end
		State().search = self:GetText() or ""
		section:Draw()
	end)
	bar.kind = P.Toggle(bar, "", function(self)
		Menu(self, L["Kind"], { { false, L["All kinds"] }, { "armor", KIND_LABEL.armor }, { "weapon", KIND_LABEL.weapon },
			{ "consumable", KIND_LABEL.consumable }, { "other", KIND_LABEL.other } },
			function() return State().kind or false end, function(v) State().kind = v or nil section:Draw() end)
	end, L["Kind"], L["Armor, weapons, consumables or the rest."])
	bar.kind:SetPoint("LEFT", bar.search, "RIGHT", 8, 0)
	bar.usable = P.Toggle(bar, L["Usable by me"], function()
		local s = State()
		s.usable = not s.usable
		section:Draw()
	end, L["Usable by me"], L["Hides results your class cannot use."])
	bar.usable:SetPoint("LEFT", bar.kind, "RIGHT", 4, 0)
	bar.known = P.Toggle(bar, "", function(self)
		Menu(self, L["Recipes"], { { "all", L["Known and unknown"] }, { "known", L["Known"] }, { "unknown", L["Not known"] } },
			function() return State().known end, function(v) State().known = v section:Draw() end)
	end, L["Recipes"], L["Recipes you know (seen in your profession window) or not."])
	bar.known:SetPoint("LEFT", bar.usable, "RIGHT", 4, 0)
	bar.range = P.Toggle(bar, "", function(self)
		local entries = { { false, L["Any skill"] } }
		for index, range in ipairs(RANGES) do entries[#entries + 1] = { index, ("%d-%d"):format(range[1], range[2]) } end
		Menu(self, L["Skill"], entries, function() return State().range or false end, function(v) State().range = v or nil section:Draw() end)
	end, L["Skill"], L["Only crafts learned in this skill range."])
	bar.range:SetPoint("LEFT", bar.known, "RIGHT", 4, 0)
	bar.count = Kit.Text(bar, 11, "RIGHT", "secondary")
	bar.count:SetPoint("RIGHT", -4, 0)

	section.detail = CreateFrame("Frame", nil, section)
	section.detail:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -6)
	section.detail:SetPoint("BOTTOMRIGHT")
	section.detail:SetWidth(DETAIL_WIDTH)
	E:SetTemplate(section.detail, true)
	section.flow = P.Flow(section.detail)
	section.flow:SetPoint("TOPLEFT", 8, -8)
	section.flow:SetPoint("BOTTOMRIGHT", -4, 8)

	section.list = Kit.CreateList(section, { create = RowCreate, update = RowUpdate, gap = 2 })
	section.list.section = section
	section.list:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
	section.list:SetPoint("BOTTOMRIGHT", section.detail, "BOTTOMLEFT", -8, 0)
	section.empty = Kit.Text(section, 12, "CENTER", "secondary")
	section.empty:SetPoint("TOP", section.list, "TOP", 0, -40)
	section.empty:SetWidth(360)
	section.empty:SetWordWrap(true)
	section.empty:SetSpacing(3)

	function section:Select(spellID)
		State().selected = spellID
		self.list:Refresh()
		local craft
		for _, c in ipairs(self.rows or {}) do if c.id == spellID then craft = c end end
		DrawDetail(self, craft)
	end

	function section:DrawStrip()
		local x, y = 0, 0
		local width = self:GetWidth() or 600
		local list = LG:Professions()
		for index, prof in ipairs(list) do
			local chip = self.profs[index]
			if not chip then
				chip = P.Toggle(self.strip, "", nil, nil, nil)
				chip.icon = chip:CreateTexture(nil, "ARTWORK")
				chip.icon:SetSize(14, 14)
				chip.icon:SetPoint("LEFT", 4, 0)
				E:TrimIcon(chip.icon)
				self.profs[index] = chip
			end
			chip.icon:SetTexture(prof.icon)
			chip:SetLabel(prof.rank and ("%s %d"):format(prof.name, prof.rank) or prof.name)
			chip.text:ClearAllPoints()
			chip.text:SetPoint("LEFT", chip.icon, "RIGHT", 4, 0)
			chip:SetWidth(chip:GetWidth() + 16)
			chip:SetOn(prof.id == self.skill)
			chip:SetScript("OnClick", function()
				State().skill = prof.id
				State().selected = nil
				self:Draw()
			end)
			Kit.Tooltip(chip, prof.name, prof.rank and (L["Your skill: %d"]):format(prof.rank) or L["You do not have this profession."])
			if x > 0 and x + chip:GetWidth() > width then x, y = 0, y + 22 end
			chip:ClearAllPoints()
			chip:SetPoint("TOPLEFT", x, -y)
			chip:Show()
			x = x + chip:GetWidth() + 4
		end
		self.strip:SetHeight(y + 20)
	end

	function section:Draw()
		local s = State()
		if not s.skill or not LG:ProfessionInfo(s.skill) then
			local list = LG:Professions()
			s.skill = list[1] and list[1].id
		end
		self.skill = s.skill
		self:DrawStrip()
		local kindLabel = s.kind and KIND_LABEL[s.kind] or L["All kinds"]
		bar.kind:SetLabel(kindLabel, true)
		bar.kind:SetOn(s.kind ~= nil)
		bar.usable:SetOn(s.usable)
		bar.known:SetLabel((s.known == "known" and L["Known"] or s.known == "unknown" and L["Not known"] or L["Known and unknown"]), true)
		bar.known:SetOn(s.known ~= "all")
		local range = s.range and RANGES[s.range]
		bar.range:SetLabel((range and ("%d-%d"):format(range[1], range[2]) or L["Any skill"]), true)
		bar.range:SetOn(range ~= nil)
		if (bar.search:GetText() or "") ~= (s.search or "") then bar.search:SetText(s.search or "") end
		self.rows = Rows(s.skill)
		self.list:SetData(self.rows)
		bar.count:SetText(E:Plural(#self.rows, "%d craft", "%d crafts"):format(#self.rows))
		local all = LG:ProfessionCrafts(s.skill)
		if #all == 0 then
			self.empty:SetText(LG:HasData() and L["The loot data lists no crafts for this profession."]
				or L["Crafts come from EldoUI_LootData. Without it, recipes appear here once you open your profession window."])
			self.empty:Show()
		elseif #self.rows == 0 then
			self.empty:SetText(L["No craft matches the filters."])
			self.empty:Show()
		else
			self.empty:Hide()
		end
		local selected
		for _, craft in ipairs(self.rows) do if craft.id == s.selected then selected = craft end end
		DrawDetail(self, selected)
	end
	section:SetScript("OnSizeChanged", function(self) if self:IsShown() then self:DrawStrip() end end)

	LG:On("section-crafting", function(changed)
		if section:IsShown() and (changed.crafts or changed.data or changed.player or changed.bags or changed.settings
			or changed.gear or changed.wishlist or changed.items) then
			section:Draw()
		end
	end)
	return section
end

local function Show(section, arg)
	if tonumber(arg) and LG:ProfessionInfo(tonumber(arg)) then State().skill = tonumber(arg) end
	section:Draw()
	Kit.Tour("crafting", {
		{ target = section.strip, text = L["Your professions come first with your skill. Open your profession window once so known recipes and their colors show."] },
		{ target = section.detail, text = L["Pick a craft: its reagents with what you own and where the recipe comes from, with Map buttons."] },
	})
end

-- "/eui crafting tailoring" -> that profession.
local function FindProfession(text)
	text = E:FoldText(text or "")
	if text == "" then return end
	for _, prof in ipairs(LG.PROFESSIONS) do
		local name = E:FoldText(LG:ProfessionName(prof.id))
		if name == text or E:FoldText(prof.name) == text or (#text >= 3 and (name:find(text, 1, true) or E:FoldText(prof.name):find(text, 1, true))) then
			return prof.id
		end
	end
end

LG:RegisterCatalogueSection("crafting", {
	title = "Crafting",
	icon = "Interface\\Icons\\Trade_BlackSmithing",
	desc = "Every craft per profession: what it makes, the skill it needs, the reagents you own and where the recipe comes from.",
	order = 10,
	command = "crafting",
	usage = Key("open Catalog > Crafting; add a profession (/eui crafting tailoring)"),
	argument = FindProfession,
	build = Build,
	show = Show,
	search = function(text)
		local out = {}
		text = E:FoldText(text)
		for _, prof in ipairs(LG.PROFESSIONS) do
			for _, craft in ipairs(LG:ProfessionCrafts(prof.id)) do
				local record = LG:ItemRecord(craft.result)
				if record and record.name and E:FoldText(record.name):find(text, 1, true) then
					out[#out + 1] = { title = record.name, itemID = craft.result, arg = prof.id }
					if #out >= 20 then return out end
				end
			end
		end
		return out
	end,
})
