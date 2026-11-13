-- EldoUI Loot Guide: the For You page.
--
-- One page for "where should I go now and what will I get":
--   * hero card: the best instance for you (P.RankInstances: most
--     upgrades, then most open quests, then the lower level, then the
--     name; near your level, else the next three coming up) with Open and
--     Entrance buttons and a level-fit bar
--   * character panel: portrait and level, class, spec and zone, the XP
--     bar with the rested part (or "Max level"), the best-in-slot set as
--     icons (owned bright) with "x of y"
--   * next upgrades: the top three, one per slot, with source, gain and
--     chance; cards for Best in Slot switched off and a simulator that has
--     not run yet
--   * more dungeons: three tiles for your level or coming up
-- Everything is read from the ranking (Rank.lua), the shared item engine
-- and the game (UnitXP, GetXPExhaustion); nothing is computed in combat.
local _, E = ...
local LG = E.LootGuide
local Kit = LG.Kit
local P = LG.PageKit
local L = E.L

local Key = E.Key
local PANEL_WIDTH = 300
local HERO_HEIGHT = 150
local SLOT_KEYS = {
	[1] = "HEADSLOT", [2] = "NECKSLOT", [3] = "SHOULDERSLOT", [4] = "SHIRTSLOT", [5] = "CHESTSLOT", [6] = "WAISTSLOT",
	[7] = "LEGSSLOT", [8] = "FEETSLOT", [9] = "WRISTSLOT", [10] = "HANDSSLOT", [11] = "FINGER0SLOT", [12] = "FINGER1SLOT",
	[13] = "TRINKET0SLOT", [14] = "TRINKET1SLOT", [15] = "BACKSLOT", [16] = "MAINHANDSLOT", [17] = "SECONDARYHANDSLOT",
	[18] = "RANGEDSLOT", [19] = "TABARDSLOT",
}
local BIS_SLOTS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }

function P.SlotName(slot)
	local key = SLOT_KEYS[slot]
	local name = key and rawget(_G, key)
	if type(name) == "string" then return name end
	return ("#%s"):format(tostring(slot))
end

---------------------------------------------------------------------------
-- Next upgrades: one per slot group, biggest gain first.
---------------------------------------------------------------------------
function LG:TopUpgrades(n, rank)
	local out, groups = {}, {}
	for _, upgrade in ipairs(self:NextUpgrades(30, rank)) do
		local group = self:SlotGroup(upgrade.itemID) or upgrade.slot
		if not groups[group] then
			groups[group] = true
			out[#out + 1] = upgrade
			if #out >= (n or 3) then break end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Parts
---------------------------------------------------------------------------
local function BuildHero(page)
	local hero = CreateFrame("Frame", nil, page)
	hero:SetPoint("TOPLEFT")
	hero:SetPoint("TOPRIGHT", -(PANEL_WIDTH + 10), 0)
	hero:SetHeight(HERO_HEIGHT)
	E:SetTemplate(hero, true)
	hero.bg = hero:CreateTexture(nil, "BACKGROUND", nil, 1)
	hero.bg:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	hero.bg:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	hero.bg:SetAlpha(0.35)
	hero.caption = P.Caption(hero)
	hero.caption:SetPoint("TOPLEFT", 12, -10)
	hero.art = P.Art(hero, 56)
	hero.art:SetPoint("TOPLEFT", 12, -28)
	hero.name = Kit.Text(hero, 18, "LEFT")
	hero.name:SetPoint("TOPLEFT", hero.art, "TOPRIGHT", 12, 0)
	hero.name:SetPoint("TOPRIGHT", -12, -28)
	hero.name:SetWordWrap(false)
	hero.sub = Kit.Text(hero, 11, "LEFT", "secondary")
	hero.sub:SetPoint("TOPLEFT", hero.name, "BOTTOMLEFT", 0, -4)
	hero.sub:SetPoint("TOPRIGHT", hero.name, "BOTTOMRIGHT", 0, -4)
	hero.sub:SetWordWrap(false)
	hero.pills = {}
	hero.fit = Kit.LevelFit(hero, 200)
	hero.fit:SetPoint("TOPLEFT", hero.sub, "BOTTOMLEFT", 0, -26)
	hero.open = Kit.Button(hero, L["Open"], 90, 22, function()
		if hero.key then LG:Open("journal", hero.key) end
	end, L["Open"], L["Opens this instance in the Journal."])
	hero.open:SetPoint("BOTTOMRIGHT", -12, 10)
	hero.entrance = Kit.Button(hero, L["Entrance"], 90, 22, function()
		local point = hero.key and LG:EntrancePoint(hero.key)
		if point then LG:SetWaypoint(point, hero.name:GetText()) end
	end, L["Entrance"], L["Pins the instance entrance on your map and turns on the arrow."])
	hero.entrance:SetPoint("RIGHT", hero.open, "LEFT", -6, 0)
	hero:SetScript("OnEnter", function(self)
		if not self.key then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		P.InstanceTooltip(GameTooltip, self.key)
		GameTooltip:Show()
	end)
	hero:SetScript("OnLeave", function() GameTooltip:Hide() end)
	page.hero = hero
end

local function DrawHero(page, info, upcoming)
	local hero = page.hero
	hero.key = info and info.key
	hero:SetShown(info ~= nil)
	if not info then return end
	hero.caption:SetText(E:CaptionText(upcoming and L["Coming up for you"] or L["Best for you now"]))
	hero.caption:SetTextColor(E:TokenColor("accent"))
	local icon, background = LG:InstanceArt(info.key)
	hero.art.icon:SetTexture(icon)
	hero.bg:SetShown(background ~= nil)
	if background then
		hero.bg:SetTexture(background)
		hero.bg:SetTexCoord(0, 1, 0.1, 0.7)
	end
	hero.name:SetText(info.name)
	local bits = { P.LevelText(info), P.SizeText(info) }
	local zone = LG:InstanceZone(info.key)
	if zone then bits[#bits + 1] = zone end
	if info.bosses and info.bosses > 0 then bits[#bits + 1] = E:Plural(info.bosses, "%d boss", "%d bosses"):format(info.bosses) end
	hero.sub:SetText(table.concat(bits, "  ·  "))
	local stats = P.InstanceStats(info.key)
	local pills = {}
	if stats.upgrades > 0 then pills[#pills + 1] = { E:Plural(stats.upgrades, "%d upgrade", "%d upgrades"):format(stats.upgrades), Kit.GOOD } end
	if stats.open > 0 then pills[#pills + 1] = { E:Plural(stats.open, "%d quest", "%d quests"):format(stats.open), Kit.WARN } end
	if stats.wished > 0 and LG:WishlistOn() then pills[#pills + 1] = { (L["%d wished"]):format(stats.wished), { 1, 0.82, 0 } } end
	local anchor
	for index = 1, math.max(#pills, #hero.pills) do
		local data = pills[index]
		local pill = hero.pills[index]
		if data and not pill then
			pill = P.Pill(hero)
			hero.pills[index] = pill
		end
		if pill then
			pill:SetShown(data ~= nil)
			if data then
				pill:SetLabel(data[1], unpack(data[2]))
				pill:ClearAllPoints()
				if anchor then pill:SetPoint("LEFT", anchor, "RIGHT", 4, 0) else pill:SetPoint("TOPLEFT", hero.sub, "BOTTOMLEFT", 0, -6) end
				anchor = pill
			end
		end
	end
	hero.fit:SetRange(info.min, info.max, nil, tonumber(LG.db.levelWindow) or 3)
	local entrance = LG:EntrancePoint(info.key)
	hero.entrance:SetShown(not info.world)
	hero.entrance:SetEnabled(entrance ~= nil)
	hero.open:SetEnabled(LG:IsPageOn("journal"))
end

---------------------------------------------------------------------------
-- Character panel
---------------------------------------------------------------------------
local function Plain(value)
	if P.Secret(value) then return nil end
	return value
end

local function BuildPanel(page)
	local panel = CreateFrame("Frame", nil, page)
	panel:SetPoint("TOPRIGHT")
	panel:SetSize(PANEL_WIDTH, HERO_HEIGHT)
	E:SetTemplate(panel, true)
	panel.portrait = panel:CreateTexture(nil, "ARTWORK")
	panel.portrait:SetSize(48, 48)
	panel.portrait:SetPoint("TOPLEFT", 10, -10)
	panel.level = Kit.Text(panel, 11, "CENTER")
	panel.level:SetPoint("BOTTOM", panel.portrait, "BOTTOM", 0, -6)
	panel.name = Kit.Text(panel, 14, "LEFT")
	panel.name:SetPoint("TOPLEFT", panel.portrait, "TOPRIGHT", 10, -2)
	panel.name:SetPoint("TOPRIGHT", -10, -12)
	panel.name:SetWordWrap(false)
	panel.sub = Kit.Text(panel, 11, "LEFT", "secondary")
	panel.sub:SetPoint("TOPLEFT", panel.name, "BOTTOMLEFT", 0, -3)
	panel.sub:SetPoint("TOPRIGHT", panel.name, "BOTTOMRIGHT", 0, -3)
	panel.sub:SetWordWrap(false)
	panel.xp = E:CreateStatusBar(panel)
	panel.xp:SetHeight(6)
	panel.xp:SetPoint("TOPLEFT", panel.portrait, "BOTTOMLEFT", 0, -14)
	panel.xp:SetPoint("TOPRIGHT", -10, -(10 + 48 + 14)) -- under the 48 px portrait
	panel.rested = panel.xp:CreateTexture(nil, "BORDER")
	E:UseBarTexture(panel.rested)
	panel.rested:SetVertexColor(E.tokens.bar.rested[1], E.tokens.bar.rested[2], E.tokens.bar.rested[3], 0.5)
	panel.rested:SetPoint("TOPLEFT")
	panel.rested:SetPoint("BOTTOMLEFT")
	panel.xpText = Kit.Text(panel, 10, "LEFT", "secondary")
	panel.xpText:SetPoint("TOPLEFT", panel.xp, "BOTTOMLEFT", 0, -4)
	panel.xpText:SetPoint("TOPRIGHT", panel.xp, "BOTTOMRIGHT", 0, -4)
	panel.xpText:SetWordWrap(false)
	local xpHit = CreateFrame("Frame", nil, panel)
	xpHit:SetPoint("TOPLEFT", panel.xp, "TOPLEFT", 0, 4)
	xpHit:SetPoint("BOTTOMRIGHT", panel.xpText, "BOTTOMRIGHT", 0, -2)
	Kit.Tooltip(xpHit, L["Experience"], L["The light part is rested experience: kills give double experience until it is used up."])
	panel.bisCaption = P.Caption(panel)
	panel.bisCaption:SetPoint("TOPLEFT", panel.xpText, "BOTTOMLEFT", 0, -8)
	panel.icons = {}
	page.panel = panel
end

function P.XPState()
	local level = Plain(UnitLevel("player")) or 1
	local maxLevel = Plain(GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
	if level >= maxLevel then return { max = true, level = level } end
	local xp, xpMax = Plain(UnitXP("player")) or 0, Plain(UnitXPMax("player")) or 0
	local rested = Plain(GetXPExhaustion and GetXPExhaustion()) or 0
	return { level = level, xp = xp, xpMax = xpMax, rested = rested,
		percent = xpMax > 0 and math.floor(xp / xpMax * 1000 + 0.5) / 10 or 0 }
end

local function DrawXP(page)
	local panel = page.panel
	local state = P.XPState()
	local r, g, b = Kit.Accent()
	panel.xp:SetStatusBarColor(r, g, b)
	panel.level:SetText(tostring(state.level))
	if state.max then
		panel.xp:SetMinMaxValues(0, 1)
		panel.xp:SetValue(1)
		panel.rested:Hide()
		panel.xpText:SetText(L["Max level"])
		return
	end
	panel.xp:SetMinMaxValues(0, math.max(state.xpMax, 1))
	panel.xp:SetValue(state.xp)
	local width = panel.xp:GetWidth() or 0
	local restedEnd = math.min(state.xp + state.rested, state.xpMax)
	if state.rested > 0 and state.xpMax > 0 and width > 0 then
		panel.rested:SetWidth(math.max(width * restedEnd / state.xpMax, 1))
		panel.rested:Show()
	else
		panel.rested:Hide()
	end
	local text = (L["%s%% to level %d"]):format(tostring(math.floor((100 - state.percent) * 10 + 0.5) / 10), state.level + 1)
	if state.rested > 0 then text = text .. "  " .. E:TokenHex(E.tokens.bar.rested) .. (L["rested %s"]):format(BreakUpLargeNumbers and BreakUpLargeNumbers(state.rested) or state.rested) .. "|r" end
	panel.xpText:SetText(text)
end
P.DrawXP = DrawXP

local function BisIcon(panel, index)
	local button = panel.icons[index]
	if button then return button end
	button = CreateFrame("Button", nil, panel)
	button:SetSize(15, 15)
	E:SetTemplate(button)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	button.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(button.icon)
	button:SetScript("OnEnter", function(self)
		if not self.itemID then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(self.itemID)
		GameTooltip:AddLine(" ")
		E.UIKit.TipText(GameTooltip, (self.owned and L["%s: you have it."] or L["%s: still to get."]):format(P.SlotName(self.slot)))
		if not self.owned then E:TooltipHint(GameTooltip, { L["Click"], L["where it drops"] }) end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnClick", function(self) if self.itemID then P.OpenItem(self.itemID) end end)
	panel.icons[index] = button
	return button
end

local function DrawPanel(page, rank)
	local panel = page.panel
	SetPortraitTexture(panel.portrait, "player")
	panel.name:SetText(Plain(UnitName("player")) or "")
	local bits = {}
	local className = Plain((UnitClass("player")))
	if className then bits[#bits + 1] = className end
	local engine = E.ItemScore
	local spec = engine and engine.PlayerSpec and engine:PlayerSpec()
	local info = spec and engine:SpecInfo(spec)
	if info and (info.title or info.name) then bits[#bits + 1] = info.title or info.name end
	local zone = Plain(GetRealZoneText and GetRealZoneText())
	if zone and zone ~= "" then bits[#bits + 1] = zone end
	panel.sub:SetText(table.concat(bits, " · "))
	DrawXP(page)
	-- Best-in-slot icons.
	local bisOn = LG:BiSOn()
	panel.bisCaption:SetShown(bisOn and rank ~= nil)
	for _, button in ipairs(panel.icons) do button:Hide() end
	if not (bisOn and rank) then return end
	local set = LG:ResolveBiS(rank)
	local count, owned, x = 0, 0, 0
	for _, slot in ipairs(BIS_SLOTS) do
		local itemID = set[slot]
		if itemID then
			count = count + 1
			local button = BisIcon(panel, count)
			button.itemID, button.slot = itemID, slot
			button.owned = LG:Owns(itemID) ~= nil
			if button.owned then owned = owned + 1 end
			button.icon:SetTexture(C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID) or 134400)
			button.icon:SetDesaturated(not button.owned)
			button.icon:SetAlpha(button.owned and 1 or 0.55)
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", panel.bisCaption, "BOTTOMLEFT", x, -4)
			x = x + 16
			button:Show()
		end
	end
	panel.bisCaption:SetText(E:CaptionText((L["Best in slot: %d of %d"]):format(owned, count)))
	panel.bisCaption:SetShown(count > 0)
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local function UpgradeData(upgrade)
	local sources = LG:ItemSources(upgrade.itemID) or {}
	local best = sources[1]
	for _, entry in ipairs(sources) do
		if (entry.kind == "npc" or entry.kind == "object") and type(entry.chance) == "number"
			and (not (best and best.chance) or entry.chance > best.chance) then best = entry end
	end
	local sub = P.SlotName(upgrade.slot) .. (best and ("  ·  " .. P.SourceLine(best)) or "")
	local data = P.ChanceData(best and best.chance, best and best.kind == "npc" and best.id or nil, upgrade.itemID)
	return { itemID = upgrade.itemID, sub = sub, chance = data.chance, seen = data.seen,
		onClick = function() P.OpenItem(upgrade.itemID) end }
end

local function Draw(page)
	local flow = page.flow
	flow:Begin()
	local rank = LG:RankStatus() == "ready" and LG:RankAll() or nil
	if not rank then
		-- RankAll answers at once from the cache even while a ranking for
		-- another key runs: take that answer here, and redraw only when the
		-- callback comes later, or Draw calls itself without end.
		local waiting = false
		rank = LG:RankAll(function() if waiting and page:IsVisible() then Draw(page) end end)
		waiting = true
	end
	local raids = LG.db.includeRaids
	local pool, near = P.RankInstances(raids)
	page.best = pool[1]
	DrawHero(page, pool[1], not near)
	DrawPanel(page, rank)

	-- Next upgrades.
	local bisOn = LG:BiSOn()
	if not bisOn then
		P.FlowCaption(flow, L["Next upgrades"])
		P.FlowText(flow, L["Best in Slot is switched off, so the Loot Guide does not rate gear for you."], 12, "secondary")
		P.FlowLine(flow, "", nil, { L["Turn it on"], function()
			if type(LG.db.pages) == "table" then LG.db.pages.bis = nil end
			LG:Fire("settings")
			if E.RefreshConfig then E:RefreshConfig() end
		end, L["Turn it on"], L["Shows gain marks, plan sets and upgrades again."] })
	else
		local rating = E.ItemScore and E.ItemScore:GetRating()
		local simWaiting = rating == "sim" and LG.SimStatus and LG:SimStatus() == "none"
		P.FlowCaption(flow, L["Next upgrades"], L["one per slot, biggest gain first"])
		if not simWaiting and LG.SimAvailable and LG:SimAvailable() then
			-- The Best in Slot simulation: progress, outdated, or the set gain.
			local status = LG:SimStatus()
			local progress = LG:SimProgress()
			local text, label
			if progress then
				text = (L["Simulating: %d %%"]):format(math.floor(progress * 100)) .. (status == "paused" and ("  " .. E:TextHex("secondary") .. L["(paused for combat)"] .. "|r") or "")
				label = L["Open"]
			elseif status == "ready" then
				text = (L["Simulated Best in Slot set: %s"]):format(LG:SimSetGainText() or "") .. "  " .. E:TextHex("secondary") .. L["estimate"] .. "|r"
				label = L["Sim again"]
			elseif status == "outdated" then
				text = Kit.Hex(unpack(Kit.WARN)) .. L["Your Best in Slot run is outdated."] .. "|r"
				label = L["Sim again"]
			else
				text = E:TextHex("secondary") .. L["Simulate your Best in Slot set for DPS numbers."] .. "|r"
				label = L["Sim Best in Slot"]
			end
			page.simRow = P.FlowLine(flow, text, nil, { label, function()
				if LG:SimJob() then LG:OpenSim() else LG:RunSim("bis") end
			end, L["Sim Best in Slot"], L["Fights against a target dummy with the best items of your list (one-minute fights, out of combat). Progress shows here, in the datatext and as a toast when done."] })
		else
			page.simRow = nil
		end
		if simWaiting then
			P.FlowText(flow, L["Simulation mode rates items once the simulator has run for your character."], 12, "secondary")
			P.FlowLine(flow, "", nil, { L["Run the simulator"], function() LG:RunSim() end, L["Run the simulator"],
				L["Rates every item you can get with the simulator. It runs in small steps out of combat."] })
		elseif not rank then
			P.FlowText(flow, L["Rating the gear you can get..."], 12, "secondary")
		else
			local top = LG:TopUpgrades(3, rank)
			if #top == 0 then
				P.FlowText(flow, L["Everything you can get at your level is already as good as what you wear."], 12, "secondary")
				if not raids then
					P.FlowLine(flow, "", nil, { L["Show raids too"], function()
						LG.db.includeRaids = true
						LG:Fire("settings")
						if E.RefreshConfig then E:RefreshConfig() end
					end, L["Show raids too"], L["Counts raids for the best instance and upgrades (Loot Guide settings)."] })
				end
			end
			for _, upgrade in ipairs(top) do P.FlowItem(flow, UpgradeData(upgrade)) end
			if LG:GetPage("bis") and LG:IsPageOn("bis") and #top > 0 then
				P.FlowLine(flow, "", nil, { L["All upgrades"], function() LG:Open("bis") end, L["All upgrades"],
					L["Opens the Best in Slot page with every slot."] })
			end
		end
	end

	-- More dungeons: the next three after the hero.
	local more = {}
	for index = 2, #pool do
		more[#more + 1] = pool[index]
		if #more >= 3 then break end
	end
	if #more > 0 then
		P.FlowCaption(flow, near and L["More for your level"] or L["Coming up"])
		local row = flow:Take("tiles", function(child)
			local frame = CreateFrame("Frame", nil, child)
			frame.tiles = {}
			for index = 1, 3 do frame.tiles[index] = P.InstanceTile(frame, function(key) LG:Open("journal", key) end) end
			return frame
		end)
		flow:Place(row, 64, 0, 8)
		local width = math.floor((flow:Width() - 16) / 3)
		for index, tile in ipairs(row.tiles) do
			tile:ClearAllPoints()
			tile:SetPoint("TOPLEFT", (index - 1) * (width + 8), 0)
			tile:SetWidth(width)
			if more[index] then tile:SetInstance(more[index].key) else tile:Hide() end
		end
	end
	flow:Finish(true)
end
P.DrawForYou = Draw

local function Create(parent)
	local page = CreateFrame("Frame", nil, parent)
	page:SetAllPoints()
	BuildHero(page)
	BuildPanel(page)
	page.flow = P.Flow(page)
	page.flow:SetPoint("TOPLEFT", 0, -(HERO_HEIGHT + 8))
	page.flow:SetPoint("BOTTOMRIGHT")
	-- Sim progress redraws the upgrades header (Sim.lua loads after this file).
	if LG.SimWatch then
		LG:SimWatch("foryou", function()
			if page:IsVisible() and page.simRow then Draw(page) end
		end)
	end
	return page
end

LG:Listen("PLAYER_XP_UPDATE", "foryou", function()
	local page = LG:GetPage("foryou")
	if page and page.frame and page.frame:IsVisible() then DrawXP(page.frame) end
end)
LG:Listen("UPDATE_EXHAUSTION", "foryou", function()
	local page = LG:GetPage("foryou")
	if page and page.frame and page.frame:IsVisible() then DrawXP(page.frame) end
end)

LG:RegisterPage("foryou", {
	title = "For You",
	desc = "Where to go now and what you get there: the best dungeon for your level, your next upgrades and your best-in-slot progress.",
	order = 10,
	command = "foryou",
	usage = Key("open the For You page"),
	create = Create,
	show = function(page) Draw(page) end,
	refresh = function(page, changed)
		if changed.data or changed.gear or changed.list or changed.spec or changed.rank or changed.wishlist or changed.quests
			or changed.player or changed.bags or changed.settings or changed.items or changed.sim then
			Draw(page)
		end
	end,
	empty = function(page)
		if not page.best and #LG:Catalog() == 0 then
			return L["Nothing to suggest yet"],
				L["Install EldoUI_LootData for the Classic loot tables, or open the Dungeon Finder once so the game lists its dungeons."],
				LG.ICON, {
					{ L["Show data status"], function() LG:PrintDataStatus() end, L["Prints where the loot data comes from (same as /lg data)."] },
				}
		end
	end,
})
