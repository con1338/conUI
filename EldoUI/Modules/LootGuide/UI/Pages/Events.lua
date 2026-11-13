-- EldoUI Loot Guide: Catalog > World events.
--
-- Darkmoon Faire, the holidays, the fishing contest and
-- the elemental invasions WoW: Forever runs: each event with an "active
-- now" chip when the game's calendar says it is on today, or the day it
-- next starts when the calendar lists it this month or the next, its
-- vendors (Map button) and their goods, its quests with their rewards and
-- its creatures' drops.
local _, E = ...
local LG = E.LootGuide
local Kit = LG.Kit
local P = LG.PageKit
local L = E.L

local Key = E.Key
local ITEMS_SHOWN = 12

local function State()
	local ui = LG:UI()
	if type(ui.events) ~= "table" then ui.events = {} end
	local s = ui.events
	if type(s.open) ~= "table" then s.open = {} end
	return s
end

local function ItemsBlock(flow, items, indent)
	for index, itemID in ipairs(items) do
		if index > ITEMS_SHOWN then
			P.FlowText(flow, (L["and %d more"]):format(#items - ITEMS_SHOWN), 11, "secondary", indent)
			break
		end
		P.FlowItem(flow, { itemID = itemID, onClick = function() P.OpenItem(itemID) end }, indent)
	end
end

local function DrawEvent(flow, event)
	local content = LG:EventItems(event)
	local any = false
	for _, vendor in ipairs(content.vendors) do
		any = true
		local mob = LG:Mob(vendor.npc)
		local name = mob and mob.name or L["NPC %s"]:format(vendor.npc)
		P.FlowLine(flow, (L["Sold by %s"]):format(name), nil, P.MapButton("npc", vendor.npc, name), name, L["A vendor during this event."], 12)
		ItemsBlock(flow, vendor.items, 24)
	end
	for _, quest in ipairs(content.quests) do
		if #quest.items > 0 then
			any = true
			local status = LG:QuestStatus(quest.questID)
			local r, g, b = P.QuestStatusColor(status)
			P.FlowLine(flow, Kit.Hex(r, g, b) .. (P.QUEST_GLYPH[status] or "") .. "|r " .. (L["Quest: %s"]):format(LG:QuestTitle(quest.questID) or ("#" .. quest.questID)),
				function() if LG:IsPageOn("database") then LG:OpenDatabase("quests", quest.questID) end end, nil, L["Quest"],
				function(tip) E.UIKit.TipText(tip, L["A quest of this event."]) Kit.TooltipHint(tip, { L["Click"], L["see it in the Database"] }) end, 12)
			ItemsBlock(flow, quest.items, 24)
		end
	end
	for _, mob in ipairs(content.mobs) do
		any = true
		local record = LG:Mob(mob.npc)
		local name = record and record.name or L["NPC %s"]:format(mob.npc)
		P.FlowLine(flow, (L["Drops from %s"]):format(name), nil, P.MapButton("npc", mob.npc, name), name, L["A creature of this event."], 12)
		ItemsBlock(flow, mob.items, 24)
	end
	if not any then P.FlowText(flow, L["The loot data lists no vendors, quest rewards or drops for this event."], 11, "secondary", 12) end
end

local function Build(parent)
	local section = CreateFrame("Frame", nil, parent)
	section.note = Kit.Text(section, 11, "LEFT", "secondary")
	section.note:SetPoint("TOPLEFT", 0, -2)
	section.note:SetPoint("TOPRIGHT", -160, -2)
	section.search = CreateFrame("EditBox", nil, section, "SearchBoxTemplate")
	E:SearchHint(section.search)
	section.search:SetSize(150, 20)
	section.search:SetPoint("TOPRIGHT")
	section.search:SetAutoFocus(false)
	E:SkinEditBox(section.search)
	Kit.Tooltip(section.search, L["Search"], L["Finds events by name."])
	section.search:HookScript("OnTextChanged", function(self, typed)
		if not typed then return end
		State().search = self:GetText() or ""
		section:Draw()
	end)
	section.flow = P.Flow(section)
	section.flow:SetPoint("TOPLEFT", 0, -26)
	section.flow:SetPoint("BOTTOMRIGHT")

	function section:Draw(keepScroll)
		local s = State()
		local flow = self.flow
		flow:Begin()
		local events = LG:Events()
		local text = E:FoldText(s.search or "")
		local calendar = false
		self.active = {}
		local active, rest = {}, {}
		for _, event in ipairs(events) do
			if text == "" or E:FoldText(event.name or ""):find(text, 1, true) then
				local on = LG:EventActive(event)
				if on ~= nil then calendar = true end
				if on then
					self.active[event.id] = true
					active[#active + 1] = event
				else
					rest[#rest + 1] = event
				end
			end
		end
		self.note:SetText(calendar and L["Active now and start dates: from the game's calendar."] or L["The game's calendar is not available here, so no event shows as active."])
		local function Line(event)
			local open = s.open[event.id]
			local chip = ""
			if self.active[event.id] then
				chip = "  " .. Kit.Hex(unpack(Kit.GOOD)) .. L["active now"] .. "|r"
			elseif calendar then
				local at = LG:EventNext(event)
				if at then chip = "  " .. Kit.Hex(unpack(Kit.SECONDARY)) .. L["starts %s"]:format(E:ShortDay(at)) .. "|r" end
			end
			P.FlowLine(flow, (open and "- " or "+ ") .. (event.name or ("#" .. event.id)) .. chip, function()
				s.open[event.id] = not s.open[event.id] or nil
				self:Draw(true)
			end, nil, event.name, function(tip) Kit.TooltipHint(tip, { L["Click"], L["show or hide its vendors, quests and drops"] }) end)
			if open then DrawEvent(flow, event) end
		end
		if #active > 0 then
			P.FlowCaption(flow, L["Active now"], tostring(#active))
			for _, event in ipairs(active) do Line(event) end
		end
		if #rest > 0 then
			P.FlowCaption(flow, #active > 0 and L["Other events"] or L["World events"], tostring(#rest))
			for _, event in ipairs(rest) do Line(event) end
		end
		if #events == 0 then
			P.FlowText(flow, L["World events come from EldoUI_LootData. Install it next to EldoUI to list them."], 12, "secondary")
		elseif #active + #rest == 0 then
			P.FlowText(flow, L["No event matches the search."], 12, "secondary")
		end
		flow:Finish(keepScroll)
	end

	LG:On("section-events", function(changed)
		if section:IsShown() and (changed.data or changed.settings or changed.quests or changed.events or changed.items) then section:Draw(true) end
	end)
	return section
end

LG:Listen("CALENDAR_UPDATE_EVENT_LIST", "events", function() LG:Fire("events") end)

LG:RegisterCatalogueSection("events", {
	title = "World events",
	icon = "Interface\\Icons\\INV_Misc_Ticket_Darkmoon_01",
	desc = "Darkmoon Faire, the holidays and other world events: their vendors, quest rewards and drops, and which are on now.",
	order = 50,
	command = "events",
	usage = Key("open Catalog > World events; add an event name"),
	argument = function(word)
		word = E:FoldText(word)
		for _, event in ipairs(LG:Events()) do
			if E:FoldText(event.name or ""):find(word, 1, true) then return event.id end
		end
	end,
	build = Build,
	show = function(section, arg)
		if tonumber(arg) then State().open[tonumber(arg)] = true end
		section:Draw()
	end,
	search = function(text)
		local out = {}
		text = E:FoldText(text)
		for _, event in ipairs(LG:Events()) do
			if E:FoldText(event.name or ""):find(text, 1, true) then out[#out + 1] = { title = event.name, arg = event.id } end
		end
		return out
	end,
})
