-- EldoUI Loot Guide: Catalog > Reputation.
--
-- Left: the Classic factions (and the battleground and home-city ones) for
-- your side, each with your live standing bar; "Show factions you have not
-- met" adds the rest, the side toggle shows the other faction's. Right:
-- the faction's quartermasters with Map buttons, then the rewards grouped
-- by standing (Exalted down), each header in its color with "x reputation
-- to go" in red while you are below it, and the quests that need that
-- standing. Costs: gold from the loot data, other currencies from the
-- vendors you visited (read-only), else "visit the vendor once".
local _, E = ...
local LG = E.LootGuide
local Kit = LG.Kit
local P = LG.PageKit
local L = E.L

local Key = E.Key
local LIST_WIDTH = 220

local Secret = E.Secret

local function State()
	local ui = LG:UI()
	if type(ui.reputation) ~= "table" then ui.reputation = {} end
	return ui.reputation
end

---------------------------------------------------------------------------
-- Costs (shared with PvP): "12g 50s", "40 x [Mark]", or the hint.
---------------------------------------------------------------------------
local function CurrencyIcon(entry)
	if entry.currency then
		local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(entry.id)
		local icon = type(info) == "table" and not Secret(info.iconFileID) and info.iconFileID
		return icon
	end
	local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(entry.id)
	if Secret(icon) then return end
	return icon
end

function P.CostText(itemID)
	local cost = LG:RewardCost(itemID)
	local parts = {}
	for _, entry in ipairs(cost.cost or {}) do
		local icon = CurrencyIcon(entry)
		parts[#parts + 1] = tostring(entry.amount) .. (icon and (" |T" .. icon .. ":12:12|t") or (" #" .. entry.id))
	end
	local gold = P.MoneyText(cost.gold)
	if gold then parts[#parts + 1] = gold end
	if #parts > 0 then return table.concat(parts, " ") end
	return E:TextHex("secondary") .. L["visit the vendor once"] .. "|r", true
end

---------------------------------------------------------------------------
-- Standing bar
---------------------------------------------------------------------------
local function StandingBar(parent, height)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetHeight(height)
	E:UseBarTexture(bar)
	bar:SetMinMaxValues(0, 1)
	E:SetTemplate(bar, true)
	bar.text = Kit.Text(bar, height >= 14 and 11 or 9, "CENTER")
	bar.text:SetPoint("CENTER")
	function bar:SetStanding(live)
		if not live then
			self:SetValue(0)
			self.text:SetText(L["not met"])
			Kit.Paint(self.text, "secondary")
			return
		end
		local r, g, b = LG:StandingColor(live.standing)
		self:SetStatusBarColor(r, g, b, 0.85)
		local low, high, value = live.min or 0, live.max or 1, live.value or 0
		if high > low then self:SetMinMaxValues(low, high) self:SetValue(value) else self:SetMinMaxValues(0, 1) self:SetValue(1) end
		local name = LG:StandingName(live.standing)
		if height >= 14 and high > low then
			self.text:SetText(("%s  %d / %d"):format(name, value - low, high - low))
		else
			self.text:SetText(name)
		end
		self.text:SetTextColor(1, 1, 1)
	end
	return bar
end

---------------------------------------------------------------------------
-- Faction list
---------------------------------------------------------------------------
local function ListRows()
	local s = State()
	return LG:Factions(LG.db.repShowAll, s.other and "other" or nil)
end

local function RowCreate(row)
	E:SkinRow(row)
	row:RegisterForClicks("LeftButtonUp")
	row.mark = row:CreateTexture(nil, "OVERLAY")
	row.mark:SetPoint("TOPLEFT")
	row.mark:SetPoint("BOTTOMLEFT")
	row.mark:SetWidth(2)
	E:AccentTexture(row.mark, 1)
	row.name = Kit.Text(row, 12, "LEFT")
	row.name:SetPoint("TOPLEFT", 8, -3)
	row.name:SetPoint("TOPRIGHT", -6, -3)
	row.name:SetWordWrap(false)
	row.bar = StandingBar(row, 10)
	row.bar:SetPoint("BOTTOMLEFT", 8, 4)
	row.bar:SetPoint("BOTTOMRIGHT", -6, 4)
	row:SetScript("OnClick", function(self)
		if self.item then
			State().faction = self.item.id
			self.list.section:Draw()
		end
	end)
end

local function RowUpdate(row, faction)
	local selected = State().faction == faction.id
	row.mark:SetShown(selected)
	row.name:SetText(faction.name)
	if selected then row.name:SetTextColor(E:TokenColor("accent")) else Kit.Paint(row.name) end
	row.bar:SetStanding(faction.live)
	Kit.Tooltip(row, faction.name, faction.live and (L["%s with this faction."]):format(LG:StandingName(faction.live.standing))
		or L["You have not met this faction yet."])
end

---------------------------------------------------------------------------
-- Rewards
---------------------------------------------------------------------------
local function VendorOf(itemID)
	local npcs = LG:Vendors(itemID) or {}
	local npc = npcs[1]
	if not npc then
		local seen = LG:SeenVendorCost(itemID)
		return seen and seen.npc, seen and seen.name
	end
	local mob = LG:Mob(npc)
	return npc, mob and mob.name
end

local function ItemMatches(itemID, s, text)
	local record = LG:ItemRecord(itemID)
	if text ~= "" then
		local name = record and record.name or ""
		if not E:FoldText(name):find(text, 1, true) then return false end
	end
	if s.usable and record and not LG:CanUseRecord(record, true) then return false end
	if s.upgrades and LG:BiSOn() and not P.IsUpgrade(itemID) then return false end
	return true
end

local function DrawFaction(section)
	local s = State()
	local flow = section.flow
	flow:Begin()
	local faction
	for _, f in ipairs(section.rows or {}) do if f.id == s.faction then faction = f end end
	if not faction then
		P.FlowText(flow, L["Pick a faction on the left."], 12, "secondary")
		flow:Finish()
		section.header:Hide()
		return
	end
	section.header:Show()
	section.header.name:SetText(faction.name)
	section.header.bar:SetStanding(faction.live)
	local cap, capStanding = LG:FactionCap(faction.id)
	if cap then
		P.FlowText(flow, (L["Reputation with this faction stops at %s."]):format(LG:StandingName(capStanding)), 11, "secondary")
	end
	local text = E:FoldText(s.search or "")
	local rewards = LG:FactionRewards(faction.id)
	local quests = LG:FactionQuests(faction.id)
	-- Quartermasters.
	local vendors, seenVendor = {}, {}
	for _, list in pairs(rewards) do
		for _, itemID in ipairs(list) do
			local npc, name = VendorOf(itemID)
			if npc and not seenVendor[npc] then
				seenVendor[npc] = true
				vendors[#vendors + 1] = { npc = npc, name = name or L["NPC %s"]:format(npc) }
			end
		end
	end
	if #vendors > 0 then
		P.FlowCaption(flow, L["Quartermasters"])
		for _, vendor in ipairs(vendors) do
			local camps = LG:SpawnPoints("npc", vendor.npc)
			local zone = camps[1] and LG:SpawnZone(camps[1])
			P.FlowLine(flow, vendor.name .. (zone and ("  " .. E:TextHex("secondary") .. zone .. "|r") or ""), nil, P.MapButton("npc", vendor.npc, vendor.name),
				vendor.name, L["Sells this faction's rewards."])
		end
	end
	local shown = 0
	for standing = 7, 0, -1 do
		local items = {}
		for _, itemID in ipairs(rewards[standing] or {}) do
			if ItemMatches(itemID, s, text) then items[#items + 1] = itemID end
		end
		local questList = {}
		for _, questID in ipairs(quests[standing] or {}) do
			local title = LG:QuestTitle(questID) or ""
			if text == "" or E:FoldText(title):find(text, 1, true) then questList[#questList + 1] = questID end
		end
		if #items > 0 or #questList > 0 then
			shown = shown + #items + #questList
			local r, g, b = LG:StandingColor(standing)
			local toGo = LG:StandingToGo(faction.id, standing)
			local note
			if toGo and toGo > 0 then
				note = Kit.Hex(unpack(Kit.BAD)) .. (L["%s reputation to go"]):format(BreakUpLargeNumbers and BreakUpLargeNumbers(toGo) or toGo) .. "|r"
			elseif toGo == 0 then
				note = Kit.Hex(unpack(Kit.GOOD)) .. L["reached"] .. "|r"
			end
			flow:Space(6)
			P.FlowText(flow, Kit.Hex(r, g, b) .. E:CaptionText(LG:StandingName(standing)) .. "|r" .. (note and ("   " .. note) or ""), 11)
			table.sort(items, function(a, c)
				local ra, rc = LG:ItemRecord(a), LG:ItemRecord(c)
				return (ra and ra.name or "") < (rc and rc.name or "")
			end)
			for _, itemID in ipairs(items) do
				local cost = P.CostText(itemID)
				local npc, name = VendorOf(itemID)
				local zone
				if npc then
					local camps = LG:SpawnPoints("npc", npc)
					zone = camps[1] and LG:SpawnZone(camps[1])
				end
				P.FlowItem(flow, { itemID = itemID, tag = cost, sub = name and (name .. (zone and (" · " .. zone) or "")) or nil,
					onClick = function() P.OpenItem(itemID) end })
			end
			for _, questID in ipairs(questList) do
				local status = LG:QuestStatus(questID)
				local qr, qg, qb = P.QuestStatusColor(status)
				local quest = LG:Quest(questID)
				local rewardIDs = {}
				for _, reward in ipairs(quest and quest.rewards or {}) do rewardIDs[#rewardIDs + 1] = reward.id end
				for _, reward in ipairs(quest and quest.choice or {}) do rewardIDs[#rewardIDs + 1] = reward.id end
				P.FlowLine(flow, Kit.Hex(qr, qg, qb) .. (P.QUEST_GLYPH[status] or "") .. "|r " .. (L["Quest: %s"]):format(LG:QuestTitle(questID) or ("#" .. questID))
					.. (#rewardIDs > 0 and ("  " .. E:TokenHex(E.media.text.secondary) .. E:Plural(#rewardIDs, "%d reward", "%d rewards"):format(#rewardIDs) .. "|r") or ""), function()
					if LG:IsPageOn("database") then LG:OpenDatabase("quests", questID) end
				end, nil, L["Quest"], function(tip) E.UIKit.TipText(tip, L["A quest that needs this standing."]) Kit.TooltipHint(tip, { L["Click"], L["see it with its rewards"] }) end)
				for _, id in ipairs(rewardIDs) do
					P.FlowItem(flow, { itemID = id, tag = L["Reward"], onClick = function() P.OpenItem(id) end }, 16)
				end
			end
		end
	end
	if shown == 0 then
		P.FlowText(flow, (s.usable or (s.upgrades and LG:BiSOn()) or text ~= "") and L["Nothing matches the filters."]
			or L["The loot data lists no rewards for this faction."], 12, "secondary")
	end
	flow:Space(6)
	P.FlowText(flow, L["Costs other than gold show once you have visited the vendor."], 10, "dim")
	flow:Finish(section.keepScroll)
end

---------------------------------------------------------------------------
-- Section
---------------------------------------------------------------------------
local function Build(parent)
	local section = CreateFrame("Frame", nil, parent)
	section.side = P.Toggle(section, "", function()
		local s = State()
		s.other = not s.other or nil
		s.faction = nil
		section:Draw()
	end, L["Side"], L["Your own side's factions, or the other side's (to see what they get)."])
	section.side:SetPoint("TOPLEFT", 0, 0)
	section.list = Kit.CreateList(section, { rowHeight = 30, create = RowCreate, update = RowUpdate, gap = 2 })
	section.list.section = section
	section.list:SetPoint("TOPLEFT", 0, -26)
	section.list:SetPoint("BOTTOMLEFT")
	section.list:SetWidth(LIST_WIDTH)

	local header = CreateFrame("Frame", nil, section)
	header:SetPoint("TOPLEFT", LIST_WIDTH + 14, 0)
	header:SetPoint("TOPRIGHT")
	header:SetHeight(48)
	header.name = Kit.Text(header, 15, "LEFT")
	header.name:SetPoint("TOPLEFT", 0, -2)
	header.bar = StandingBar(header, 16)
	header.bar:SetPoint("TOPLEFT", header.name, "BOTTOMLEFT", 0, -6)
	header.bar:SetWidth(260)
	header.search = CreateFrame("EditBox", nil, header, "SearchBoxTemplate")
	E:SearchHint(header.search)
	header.search:SetSize(140, 20)
	header.search:SetPoint("TOPRIGHT", 0, 0)
	header.search:SetAutoFocus(false)
	E:SkinEditBox(header.search)
	Kit.Tooltip(header.search, L["Search"], L["Filters the rewards and quests by name."])
	header.search:HookScript("OnTextChanged", function(self, typed)
		if not typed then return end
		State().search = self:GetText() or ""
		section:Draw(true)
	end)
	header.upgrades = P.Toggle(header, L["Upgrades only"], function()
		local s = State()
		s.upgrades = not s.upgrades or nil
		section:Draw()
	end, L["Upgrades only"], L["Shows only rewards that beat what you wear."])
	header.upgrades:SetPoint("TOPRIGHT", header.search, "BOTTOMRIGHT", 0, -6)
	header.usable = P.Toggle(header, L["Usable by me"], function()
		local s = State()
		s.usable = not s.usable or nil
		section:Draw()
	end, L["Usable by me"], L["Hides rewards your class cannot use."])
	header.usable:SetPoint("RIGHT", header.upgrades, "LEFT", -4, 0)
	section.header = header
	section.flow = P.Flow(section)
	section.flow:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
	section.flow:SetPoint("BOTTOMRIGHT")

	function section:Draw(keepScroll)
		local s = State()
		self.keepScroll = keepScroll
		self.side:SetLabel(s.other and L["Other side"] or L["Your side"])
		self.side:SetOn(s.other)
		header.upgrades:SetShown(LG:BiSOn())
		header.upgrades:SetOn(s.upgrades and LG:BiSOn())
		header.usable:SetOn(s.usable)
		if (header.search:GetText() or "") ~= (s.search or "") then header.search:SetText(s.search or "") end
		self.rows = ListRows()
		if LG.db.repShowAll then
			self.list:SetEmpty(L["No faction matches"], s.other and L["The loot data lists no factions of the other side."]
				or L["The loot data lists no factions for your side."])
		else
			self.list:SetEmpty(L["No faction matches"], L["This list shows the factions you have met. Show all factions to see every faction's rewards."], nil, {
				{ L["Show all factions"], function()
					LG.db.repShowAll = true
					LG:Fire("settings")
					section:Draw()
				end, L["Lists the factions you have not met too (Loot Guide options: Reputation: factions you have not met)."] },
			})
		end
		local found = false
		for _, f in ipairs(self.rows) do if f.id == s.faction then found = true end end
		if not found then s.faction = self.rows[1] and self.rows[1].id end
		self.list:SetData(self.rows)
		DrawFaction(self)
	end

	LG:On("section-reputation", function(changed)
		if section:IsShown() and (changed.reputation or changed.data or changed.settings or changed.gear or changed.player
			or changed.wishlist or changed.items or changed.quests) then
			section:Draw(true)
		end
	end)
	return section
end

LG:Listen("UPDATE_FACTION", "reputation", function() LG:Fire("reputation") end)

local function FindFaction(text)
	text = E:FoldText(text or "")
	if text == "" then return end
	for _, faction in ipairs(LG.FACTIONS) do
		local name = E:FoldText(LG:FactionName(faction.id))
		if name == text or (#text >= 3 and (name:find(text, 1, true) or E:FoldText(faction.name):find(text, 1, true))) then return faction.id end
	end
end

local function Show(section, arg)
	local id = tonumber(arg)
	if id then
		local s = State()
		s.faction = id
		local mine = LG:Player().faction
		for _, faction in ipairs(LG.FACTIONS) do
			if faction.id == id then s.other = (faction.side ~= nil and faction.side ~= mine) or nil end
		end
	end
	section:Draw()
	Kit.Tour("reputation", {
		{ target = section.list, text = L["Your factions with your standing. Pick one to see what it sells and gives at each standing."] },
		{ target = section.header.upgrades, text = L["Upgrades only and Usable by me narrow the rewards; the side toggle shows the other faction's."] },
	})
end

LG:RegisterCatalogueSection("reputation", {
	title = "Reputation",
	icon = "Interface\\Icons\\INV_Misc_Note_02",
	desc = "What each faction sells or gives at every standing, how far you are from it and which rewards are upgrades for you.",
	order = 20,
	command = "reputation",
	usage = Key("open Catalog > Reputation; add a faction (/eui reputation argent dawn)"),
	argument = FindFaction,
	build = Build,
	show = Show,
	search = function(text)
		local out = {}
		text = E:FoldText(text)
		for _, faction in ipairs(LG.FACTIONS) do
			for _, list in pairs(LG:FactionRewards(faction.id)) do
				for _, itemID in ipairs(list) do
					local record = LG:ItemRecord(itemID)
					if record and record.name and E:FoldText(record.name):find(text, 1, true) then
						out[#out + 1] = { title = record.name, itemID = itemID, arg = faction.id }
						if #out >= 20 then return out end
					end
				end
			end
		end
		return out
	end,
})
