-- EldoUI Loot Guide: Catalog > PvP.
--
-- Wallet line (honor, battleground marks, your rank on the season track),
-- group chips (Alterac Valley, Warsong Gulch, Arathi Basin, PvP class sets,
-- armor, weapons, Emboldened seals, mounts, insignia and tabards), the
-- rewards with their cost (honor and marks seen at the vendor, gold from
-- the data, else "visit the vendor once"), the rank or standing they need
-- (red when you are not there yet) and the vendor with a Map button.
-- Right: the planner. Pick
-- pieces with "Plan" (or from your wishlist); it shows the running total,
-- what you can buy now and the weeks until you can afford each piece at
-- your recent weekly honor (or the number you typed): green this week,
-- then yellow, orange, red, and "never" with no income. Nothing estimates
-- a server formula; nothing is bought or queued.
local _, E = ...
local LG = E.LootGuide
local Kit = LG.Kit
local P = LG.PageKit
local L = E.L

local Key = E.Key
local PLAN_WIDTH = 270
local ROW = 22

local Secret = E.Secret

local function State()
	local ui = LG:UI()
	if type(ui.pvp) ~= "table" then ui.pvp = {} end
	return ui.pvp
end

local function Number(n)
	n = tonumber(n) or 0
	local text = BreakUpLargeNumbers and BreakUpLargeNumbers(n)
	if type(text) ~= "string" or text == "" then text = tostring(n) end
	return text
end

---------------------------------------------------------------------------
-- Cost and requirement text
---------------------------------------------------------------------------
local function MarkIcon(itemID)
	local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
	if Secret(icon) then return end
	return icon
end

-- "7,650 [honor] 30 [mark] 1g" or the hint; second value true for the hint.
function LG:PvPCostText(itemID)
	local honor, marks, gold = self:PvPCost(itemID)
	local parts = {}
	if honor then
		local _, _, name, icon = self:HonorCurrency()
		parts[#parts + 1] = Number(honor) .. (icon and (" |T" .. icon .. ":12:12|t") or (" " .. (name or L["honor"])))
	end
	for markID, amount in pairs(marks or {}) do
		local icon = MarkIcon(markID)
		parts[#parts + 1] = tostring(amount) .. (icon and (" |T" .. icon .. ":12:12|t") or (" #" .. markID))
	end
	local money = P.MoneyText(gold)
	if money then parts[#parts + 1] = money end
	if #parts == 0 then
		local price = P.MoneyText((self:Price(itemID)))
		if price then return price end
		return E:TextHex("secondary") .. L["visit the vendor once"] .. "|r", true
	end
	return table.concat(parts, " ")
end

-- "Rank 8" / "Revered" in red when not reached; reached, the text in gray.
function LG:PvPNeedText(itemID)
	local record = self:ItemRecord(itemID)
	if not record then return end
	local rank = self:PvPItemRank(itemID)
	if rank then
		local wallet = self:PvPWallet()
		local ok = wallet.rank and wallet.rank >= rank
		local color = ok and Kit.SECONDARY or Kit.BAD
		return Kit.Hex(unpack(color)) .. (L["Rank %d"]):format(rank) .. "|r", ok
	end
	if record.repFaction and record.repStanding then
		local live = self:FactionStanding(record.repFaction)
		local ok = live and live.standing >= record.repStanding
		local color = ok and Kit.SECONDARY or Kit.BAD
		return Kit.Hex(unpack(color)) .. self:StandingName(record.repStanding) .. "|r", ok
	end
end

---------------------------------------------------------------------------
-- Reward rows: an item cell and a Plan button
---------------------------------------------------------------------------
local function RewardRow(child)
	local row = CreateFrame("Frame", nil, child)
	row.cell = P.ItemCell(row)
	row.cell:SetPoint("TOPLEFT")
	row.cell:SetPoint("BOTTOMRIGHT", -64, 0)
	row.plan = Kit.Button(row, L["Plan"], 58, 18)
	row.plan:SetPoint("RIGHT", 0, 0)
	return row
end

local function VendorFor(itemID)
	local npcs = LG:Vendors(itemID) or {}
	if npcs[1] then
		local mob = LG:Mob(npcs[1])
		return npcs[1], mob and mob.name
	end
	local seen = LG:SeenVendorCost(itemID)
	return seen and seen.npc, seen and seen.name
end

-- Search, group and both ticks back to their defaults.
local function ClearFilters(section)
	local s = State()
	s.search, s.group, s.usable, s.allSides = nil, nil, nil, nil
	section:Draw()
end

local function DrawRewards(section)
	local s = State()
	local flow = section.flow
	flow:Begin()
	local groups = LG:PvPGroups(s.allSides and "all" or nil)
	local text = E:FoldText(s.search or "")
	local shown = 0
	for _, group in ipairs(LG.PVP_GROUPS) do
		if not s.group or s.group == group.key then
			local items = {}
			for _, itemID in ipairs(groups[group.key] or {}) do
				local record = LG:ItemRecord(itemID)
				local ok = true
				if text ~= "" and not E:FoldText(record and record.name or ""):find(text, 1, true) then ok = false end
				if ok and s.usable and record and not LG:CanUseRecord(record, true) then ok = false end
				if ok then items[#items + 1] = itemID end
			end
			if #items > 0 then
				shown = shown + #items
				-- Built as they scroll into view: a screen of rows per draw,
				-- not every reward of both sides.
				flow:Defer(20 + 2 * 22, function(f)
					P.FlowCaption(f, LG:PvPGroupTitle(group), tostring(#items))
					-- The group's vendors with Map buttons.
					local vendors, seen = {}, {}
					for _, itemID in ipairs(items) do
						local npc, name = VendorFor(itemID)
						if npc and not seen[npc] and #vendors < 2 then
							seen[npc] = true
							vendors[#vendors + 1] = { npc = npc, name = name or L["NPC %s"]:format(npc) }
						end
					end
					for _, vendor in ipairs(vendors) do
						local camps = LG:SpawnPoints("npc", vendor.npc)
						local zone = camps[1] and LG:SpawnZone(camps[1])
						P.FlowLine(f, (L["Sold by %s"]):format(vendor.name) .. (zone and ("  " .. E:TextHex("secondary") .. zone .. "|r") or ""), nil,
							P.MapButton("npc", vendor.npc, vendor.name), vendor.name, L["A vendor for these rewards."])
					end
				end)
				local height = math.max(Kit.RowHeight(), ROW)
				for _, itemID in ipairs(items) do
					flow:Defer(height + 2, function(f)
						local row = f:Take("pvpreward", RewardRow)
						f:Place(row, height, 0, 2)
						local cost = LG:PvPCostText(itemID)
						local need = LG:PvPNeedText(itemID)
						P.SetItem(row.cell, { itemID = itemID, tag = cost, sub = need, onClick = function() P.OpenItem(itemID) end })
						local picked = LG:IsPvPPick(itemID)
						row.plan:SetText(picked and L["Planned"] or L["Plan"])
						row.plan:SetScript("OnClick", function() LG:SetPvPPick(itemID, not picked) end)
						Kit.Tooltip(row.plan, picked and L["Planned"] or L["Plan"], nil,
							{ { L["Click"], picked and L["take it out of the planner"] or L["add it to the planner on the right"] } })
					end)
				end
			end
		end
	end
	-- An empty list says why: the filters (with the way back) or the data.
	section.empty:SetShown(shown == 0)
	if shown == 0 then
		if LG:HasData() then
			section.empty:Set(L["Nothing matches"], L["No rewards match these filters."], nil,
				{ { L["Clear the filters"], function() ClearFilters(section) end } })
		elseif LG:DataStatus() == "missing" then
			section.empty:Set(L["PvP"], L["PvP rewards come from EldoUI_LootData. Install it next to EldoUI to list them."])
		else
			section.empty:Set(L["PvP"], LG:DataStatusText())
		end
		flow:Finish(section.keepScroll)
		return
	end
	flow:Defer(30, function(f)
		f:Space(6)
		P.FlowText(f, L["Honor and mark costs show once you have visited the vendor; nothing is estimated."], 10, "dim")
	end)
	flow:Finish(section.keepScroll)
end

-- A rewards draw that stopped half way: the column says so with a way to
-- try again instead of staying blank, and the error is reported once.
local reported = false
local function RewardsFailed(section, err)
	section.flow:Begin()
	section.flow:Finish()
	section.empty:Set(L["PvP"], L["The rewards list couldn't load."], nil,
		{ { L["Try again"], function() section:Draw() end } })
	section.empty:Show()
	if not reported then
		reported = true
		geterrorhandler()(err)
	end
end

---------------------------------------------------------------------------
-- Planner
---------------------------------------------------------------------------
local function DrawPlanner(section)
	local plan = section.planner
	local flow = plan.flow
	flow:Begin()
	local rows, summary = LG:PlanRows()
	local _, _, honorName = LG:HonorCurrency()
	honorName = honorName or L["honor"]
	if summary.source == "typed" then
		plan.income:SetText((L["At %s %s a week (typed in the settings)."]):format(Number(summary.income), honorName))
	elseif summary.source == "recent" then
		plan.income:SetText((L["At your recent weekly %s: %s."]):format(honorName, Number(summary.income)))
	else
		plan.income:SetText(L["No weekly income yet: play a battleground, or type one in the settings."])
	end
	if #rows == 0 then
		P.FlowText(flow, L["Click Plan on a reward, or add the PvP items from your wishlist."], 11, "secondary")
	end
	for _, row in ipairs(rows) do
		local weeks
		if not row.known then
			weeks = E:TextHex("secondary") .. L["cost unknown"] .. "|r"
		elseif row.now then
			weeks = Kit.Hex(LG:WeeksColor(0)) .. L["buy now"] .. "|r"
		elseif row.weeks == nil then
			weeks = Kit.Hex(LG:WeeksColor(nil)) .. L["never"] .. "|r"
		else
			weeks = Kit.Hex(LG:WeeksColor(row.weeks)) .. E:Plural(row.weeks, "%d week", "%d weeks"):format(row.weeks) .. "|r"
		end
		local cell = P.FlowItem(flow, { itemID = row.itemID, tag = weeks,
			sub = row.known and ((L["total %s"]):format(Number(row.total))) or nil,
			onClick = function() P.OpenItem(row.itemID) end })
		cell.planItem = row.itemID
	end
	plan.total:SetText((L["Total: %s %s"]):format(Number(summary.total), honorName)
		.. (summary.unknown > 0 and ("  " .. E:TextHex("secondary") .. (L["+%d unknown"]):format(summary.unknown) .. "|r") or "")
		.. "\n" .. (L["You have %s."]):format(Number(summary.have)))
	plan.rows = rows
	plan.summary = summary
	flow:Finish(true)
end

local function AddWishlistPicks()
	local added = 0
	local ids = {}
	for id in pairs(LG:WishedItems() or {}) do ids[#ids + 1] = id end
	table.sort(ids)
	for _, id in ipairs(ids) do
		if LG:PvPGroup(id) and not LG:IsPvPPick(id) then
			LG:SetPvPPick(id, true)
			added = added + 1
		end
	end
	return added
end
LG.AddPvPWishlistPicks = AddWishlistPicks

---------------------------------------------------------------------------
-- Section
---------------------------------------------------------------------------
local function GroupMenu(owner, section)
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(L["Show"])
		root:CreateRadio(L["All groups"], function() return State().group == nil end, function() State().group = nil section:Draw() end)
		for _, group in ipairs(LG.PVP_GROUPS) do
			root:CreateRadio(LG:PvPGroupTitle(group), function() return State().group == group.key end, function()
				State().group = group.key
				section:Draw()
			end)
		end
	end, { at = "owner" })
end

local function Build(parent)
	local section = CreateFrame("Frame", nil, parent)
	section.wallet = Kit.Text(section, 12, "LEFT")
	section.wallet:SetPoint("TOPLEFT", 0, -2)
	section.wallet:SetPoint("TOPRIGHT", -PLAN_WIDTH - 10, -2)
	section.wallet:SetWordWrap(false)

	local bar = CreateFrame("Frame", nil, section)
	bar:SetPoint("TOPLEFT", 0, -24)
	bar:SetPoint("TOPRIGHT", -PLAN_WIDTH - 10, -24)
	bar:SetHeight(20)
	bar.group = P.Toggle(bar, "", function(self) GroupMenu(self, section) end, L["Show"], L["One group of rewards, or all of them."])
	bar.group:SetPoint("LEFT")
	bar.usable = P.Toggle(bar, L["Usable by me"], function()
		local s = State()
		s.usable = not s.usable or nil
		section:Draw()
	end, L["Usable by me"], L["Hides rewards your class cannot use."])
	bar.usable:SetPoint("LEFT", bar.group, "RIGHT", 4, 0)
	bar.sides = P.Toggle(bar, L["Both sides"], function()
		local s = State()
		s.allSides = not s.allSides or nil
		section:Draw()
	end, L["Both sides"], L["Also lists the other faction's rewards."])
	bar.sides:SetPoint("LEFT", bar.usable, "RIGHT", 4, 0)
	bar.search = CreateFrame("EditBox", nil, bar, "SearchBoxTemplate")
	E:SearchHint(bar.search)
	bar.search:SetSize(140, 20)
	bar.search:SetPoint("RIGHT")
	bar.search:SetAutoFocus(false)
	E:SkinEditBox(bar.search)
	Kit.Tooltip(bar.search, L["Search"], L["Filters the rewards by name."])
	bar.search:HookScript("OnTextChanged", function(self, typed)
		if not typed then return end
		State().search = self:GetText() or ""
		section:Draw(true)
	end)
	section.bar = bar

	section.flow = P.Flow(section, { virtual = true })
	section.flow:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
	section.flow:SetPoint("BOTTOMRIGHT", -PLAN_WIDTH - 10, 0)
	section.empty = Kit.EmptyState(section)
	section.empty:ClearAllPoints()
	section.empty:SetAllPoints(section.flow)
	section.empty:SetFrameLevel(section.flow:GetFrameLevel() + 20)
	section.empty:Hide()

	local plan = CreateFrame("Frame", nil, section)
	plan:SetPoint("TOPRIGHT")
	plan:SetPoint("BOTTOMRIGHT")
	plan:SetWidth(PLAN_WIDTH)
	E:SetTemplate(plan, true)
	plan.title = Kit.Text(plan, 13, "LEFT")
	plan.title:SetPoint("TOPLEFT", 8, -8)
	plan.title:SetPoint("TOPRIGHT", -8, -8)
	plan.title:SetText(L["Planner"])
	plan.income = Kit.Text(plan, 10, "LEFT", "secondary")
	plan.income:SetPoint("TOPLEFT", plan.title, "BOTTOMLEFT", 0, -4)
	plan.income:SetPoint("TOPRIGHT", plan.title, "BOTTOMRIGHT", 0, -4)
	plan.income:SetWordWrap(true)
	plan.income:SetSpacing(2)
	plan.wish = Kit.Button(plan, L["From wishlist"], 110, 20, function()
		local added = AddWishlistPicks()
		LG:Notify(added > 0 and (L["Added %d PvP items from your wishlist to the planner."]):format(added) or L["No PvP item on your wishlist is missing from the planner."])
	end, L["From wishlist"], L["Adds the PvP rewards on your active wishlist to the planner."])
	plan.wish:SetPoint("BOTTOMLEFT", 8, 8)
	plan.clear = Kit.Button(plan, L["Clear"], 60, 20, function()
		local count = #LG:PvPPlan()
		if count == 0 then
			LG:Notify(L["The planner is already empty."])
			return
		end
		E:ShowConfirm({ title = L["Clear the planner"], accept = L["Clear"], danger = true,
			text = E:Plural(count, "Remove %d item from the PvP planner?", "Remove all %d items from the PvP planner?"):format(count)
				.. " " .. L["This can't be undone."],
			onAccept = function()
				wipe(LG:PvPPlan())
				LG:Fire("pvpplan")
				LG:Notify(L["The planner is empty."])
			end })
	end, L["Clear"], L["Empty the planner. Asks first."])
	E.UIKit.SetButtonKind(plan.clear, "danger")
	plan.clear:SetPoint("BOTTOMRIGHT", -8, 8)
	plan.total = Kit.Text(plan, 11, "LEFT")
	plan.total:SetPoint("BOTTOMLEFT", plan.wish, "TOPLEFT", 0, 8)
	plan.total:SetPoint("BOTTOMRIGHT", -8, 8 + 20 + 8) -- above the 20 px buttons
	plan.total:SetSpacing(2)
	plan.flow = P.Flow(plan)
	plan.flow:SetPoint("TOPLEFT", plan.income, "BOTTOMLEFT", 0, -8)
	plan.flow:SetPoint("BOTTOMRIGHT", -4, 70)
	section.planner = plan

	function section:DrawWallet()
		local wallet = LG:PvPWallet()
		local parts = {}
		local honorText = Number(wallet.honor or 0)
		parts[#parts + 1] = (wallet.honorIcon and ("|T" .. wallet.honorIcon .. ":14:14|t ") or "") .. honorText .. " "
			.. E:TextHex("secondary") .. (wallet.honorName or L["honor"]) .. "|r"
		for _, mark in ipairs(wallet.marks) do
			local icon = MarkIcon(mark.id)
			parts[#parts + 1] = (icon and ("|T" .. icon .. ":14:14|t ") or "") .. mark.count
		end
		if wallet.rank and wallet.rank > 0 then
			parts[#parts + 1] = (L["Rank %d"]):format(wallet.rank) .. (wallet.rankName and (" " .. E:TextHex("secondary") .. wallet.rankName .. "|r") or "")
		elseif wallet.rank == 0 then
			parts[#parts + 1] = E:TextHex("secondary") .. L["No PvP rank yet this season"] .. "|r"
		end
		self.wallet:SetText(table.concat(parts, "   "))
		self.walletData = wallet
	end

	function section:Draw(keepScroll)
		local s = State()
		self.keepScroll = keepScroll
		local title = L["All groups"]
		for _, group in ipairs(LG.PVP_GROUPS) do if group.key == s.group then title = LG:PvPGroupTitle(group) end end
		bar.group:SetLabel(title, true)
		bar.group:SetOn(s.group ~= nil)
		bar.usable:SetOn(s.usable)
		bar.sides:SetOn(s.allSides)
		if (bar.search:GetText() or "") ~= (s.search or "") then bar.search:SetText(s.search or "") end
		self:DrawWallet()
		local ok, err = pcall(DrawRewards, self)
		if not ok then RewardsFailed(self, err) end
		DrawPlanner(self)
	end

	LG:On("section-pvp", function(changed)
		if not section:IsShown() then return end
		if changed.data or changed.pvpplan or changed.settings or changed.gear or changed.wishlist or changed.reputation or changed.player then
			section:Draw(true)
		elseif changed.wallet then
			section:DrawWallet()
			DrawPlanner(section)
		end
	end)
	return section
end

local function Show(section, arg)
	if type(arg) == "string" then
		for _, group in ipairs(LG.PVP_GROUPS) do if group.key == arg then State().group = arg end end
	end
	section:Draw()
	Kit.Tour("pvp", {
		{ target = section.wallet, text = L["Your honor, marks and rank. Costs show once you have visited the vendor."] },
		{ target = section.planner, text = L["Plan pieces to see the total and how many weeks of your recent honor each one takes."] },
	})
end

-- The Honor datatext's tooltip: the planner in one line (InfoBar).
function LG:PvPTooltipLine(tooltip)
	if not self.active then return end
	local rows = self:PlanRows()
	local r, g, b = unpack(Kit.SECONDARY)
	tooltip:AddLine(" ")
	if #rows > 0 then
		local last = rows[#rows]
		local weeks = last.now and L["buy now"] or (last.weeks and (E:Plural(last.weeks, "%d week", "%d weeks"):format(last.weeks))) or L["never"]
		tooltip:AddDoubleLine(L["Loot Guide PvP plan"], E:Plural(#rows, "%d piece, %s", "%d pieces, %s"):format(#rows, weeks), r, g, b, 1, 1, 1)
	end
	E:TooltipHint(tooltip, { L["Shift-click"], L["Loot Guide PvP"] })
end

LG:RegisterCatalogueSection("pvp", {
	title = "PvP",
	icon = "Interface\\Icons\\INV_BannerPVP_02",
	desc = "Every PvP reward with its cost and the rank or standing it needs, plus a planner for the weeks to afford them.",
	order = 30,
	command = "pvp",
	usage = Key("open Catalog > PvP; add av, wsg, ab, sets, armor, weapons, mounts or insignia"),
	argument = function(word) return strtrim(word:lower()) end,
	build = Build,
	show = Show,
	search = function(text)
		local out = {}
		text = E:FoldText(text)
		for group, list in pairs(LG:PvPGroups("all")) do
			for _, itemID in ipairs(list) do
				local record = LG:ItemRecord(itemID)
				if record and record.name and E:FoldText(record.name):find(text, 1, true) then
					out[#out + 1] = { title = record.name, itemID = itemID, arg = group }
					if #out >= 20 then return out end
				end
			end
		end
		return out
	end,
})
