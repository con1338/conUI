-- EldoUI Loot Guide: the Best in Slot page.
--
--   +---------------------------------------------------------------------+
--   | Best in Slot · Phase 2   Holy Paladin, level 58 [Filter: ...] [P2 v]|
--   | [What I wear] [Best in Slot +12%] [Set 1] [Set 2] [Wishlist]  ...   |
--   | +--------+                                          +--------+      |
--   | | head   |              3D model                    | hands  |      |
--   | | neck   |          (wears the shown set)           | waist  |      |
--   | | ...    |                                          | ...    |      |
--   | +--------+      [main hand] [off hand] [ranged]     +--------+      |
--   +---------------------------------------------------------------------+
--
-- Views: what you wear, Best in Slot (the resolver over your list, for the
-- phase on the Phase chip), plan sets 1 and 2 (renamable), and the active
-- wishlist sorted into slots (main pick per slot, saved with the list).
-- A slot card opens the flyout (search, armor chips, None, Higher levels,
-- mouse-wheel paging); the Filter button opens the filter panel (spec,
-- armor, sources, lowest drop chance, Back to realistic) with the Stat
-- priority tab (drag to reorder; only the moved stat changes).
--
-- The list and the stat priority are the player's own and count
-- everywhere (For You, tooltips, roll advice), because they are the same
-- per-character list (Rank.lua) and the same E.ItemScore scale.
--
-- /eui bis [1 | 2 | wish | export]. Presentation only: plan sets are plans,
-- not equipment sets; nothing is equipped.
local _, E = ...
local LG = E.LootGuide
local Kit = LG.Kit
local P = LG.PageKit
local L = E.L

local Key = E.Key
local CARD_W, CARD_H = 228, 38
local CARD_GAP = 5
local FLYOUT_W, FLYOUT_H = 330, 380
local FILTER_W = 300
local CLOSE_PERCENT = 2

local LEFT_SLOTS = { 1, 2, 3, 15, 5, 9 }
local RIGHT_SLOTS = { 10, 6, 7, 8, 11, 12, 13, 14 }
local WEAPON_SLOTS = { 16, 17, 18 }
local ALL_SLOTS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }

local ARMOR_NAMES = E:TranslateValues({ [1] = E.Key("Cloth"), [2] = E.Key("Leather"), [3] = E.Key("Mail"), [4] = E.Key("Plate") })

local Secret = E.Secret

local function State()
	local ui = LG:UI()
	if type(ui.bis) ~= "table" then ui.bis = { view = "bis" } end
	return ui.bis
end

local function SpecName(spec)
	local engine = E.ItemScore
	local info = engine and spec and engine:SpecInfo(spec)
	return info and info.name or L["your spec"], info
end

local function PlayerSpec()
	local engine = E.ItemScore
	return engine and engine.PlayerSpec and engine:PlayerSpec()
end

---------------------------------------------------------------------------
-- Best in Slot for the plan phase (cached per ranking)
---------------------------------------------------------------------------
local resolved = {}  -- rank key -> { set, total }

LG:On("bis-resolved", function(changed)
	if changed.rank or changed.list or changed.spec or changed.gear or changed.data or changed.settings then wipe(resolved) end
end)

-- set { [slot] = itemID }, total score, rank (nil while the ranking runs;
-- it starts it).
function LG:BiSSet(phase)
	local rank = self:RankAll(nil, { phase = phase or self:PlanPhase() })
	if not rank then return end
	local entry = resolved[rank.key]
	if not entry then
		local set, total = self:ResolveBiS(rank)
		entry = { set = set, total = total, rank = rank }
		resolved[rank.key] = entry
	end
	return entry.set, entry.total, entry.rank
end

-- "Protection · Phase 2" when the item is best in slot for your spec at
-- the plan phase (our engine; no curated lists), else nil. Second value:
-- the slot.
function LG:IsBiS(itemID)
	itemID = tonumber(itemID)
	if not itemID or not self:BiSOn() then return end
	local phase = self:PlanPhase()
	local set = self:BiSSet(phase)
	if not set then return end
	for slot, id in pairs(set) do
		if id == itemID then
			local text = SpecName(PlayerSpec())
			if phase and phase ~= self:CurrentPhase() then text = text .. " · " .. self:PhaseName(phase) end
			return text, slot
		end
	end
end

-- Tank role note: when the best pick and the next one are within 2 %,
-- say which way the pick leans (our words; from the items' own stats).
local function Lean(itemID)
	local record = LG:ItemRecord(itemID)
	local s = record and record.stats or {}
	local avoid = (s.def or 0) + (s.dodge or 0) * 10 + (s.parry or 0) * 10 + (s.block or 0) * 5 + (s.blk or 0) * 0.3
		+ (s.sta or 0) * 0.5 + (s.arm or 0) / 50
	local threat = (s.str or 0) + (s.agi or 0) + (s.ap or 0) / 2 + (s.hit or 0) * 10 + (s.crit or 0) * 10
	return avoid, threat
end

function LG:TankNote(itemID, slot)
	local engine = E.ItemScore
	local _, info = SpecName(PlayerSpec())
	if not (engine and info and info.role == "TANK") then return end
	local _, _, rank = self:BiSSet(self:PlanPhase())
	local group = rank and self:SlotGroup(itemID)
	local list = group and rank.groups[group]
	if not list then return end
	local pick, other
	for _, entry in ipairs(list) do
		if entry.itemID == itemID then pick = entry elseif not other and pick then other = entry end
	end
	if not (pick and other) or pick.score <= 0 then return end
	if (pick.score - other.score) / pick.score * 100 > CLOSE_PERCENT then return end
	local avoidA, threatA = Lean(pick.itemID)
	local avoidB, threatB = Lean(other.itemID)
	local record = self:ItemRecord(other.itemID)
	local name = record and record.name or ("item:" .. other.itemID)
	if avoidA > avoidB and threatA <= threatB then
		return (L["Tank: avoidance pick (%s holds more threat)"]):format(name)
	elseif threatA > threatB and avoidA <= avoidB then
		return (L["Tank: threat pick (%s holds more avoidance)"]):format(name)
	end
	return (L["Tank: close call with %s"]):format(name)
end

---------------------------------------------------------------------------
-- Wishlist view picks (saved with the list)
---------------------------------------------------------------------------
function LG:WishPicks(listID)
	listID = listID or self:ActiveListID()
	local data = self:Char()
	if not data then return {} end
	if listID == "main" then
		if type(data.mainListPicks) ~= "table" then data.mainListPicks = {} end
		return data.mainListPicks
	end
	local list = self:WishListRecord(listID)
	if not list then return {} end
	if type(list.picks) ~= "table" then list.picks = {} end
	return list.picks
end

local function SlotsFor(itemID)
	local group = LG:SlotGroup(itemID)
	local slots = group and LG.GROUP_SLOTS[group]
	if group == "onehand" then slots = { 16, 17 } end
	return slots
end

-- Items with "BiS" or "best in slot" in their note become the slot's main
-- pick (rings, trinkets and one-hand weapons fill both slots).
function LG:PromoteBiSNotes(listID, items)
	local picks = self:WishPicks(listID)
	local promoted = 0
	for _, item in ipairs(items or {}) do
		local note = type(item) == "table" and type(item.note) == "string" and item.note:lower() or ""
		local itemID = type(item) == "table" and tonumber(item.id)
		if itemID and (note:find("%f[%a]bis%f[%A]") or note:find("best in slot", 1, true)) then
			for _, slot in ipairs(SlotsFor(itemID) or {}) do
				if not picks[slot] or picks[slot] == itemID then
					picks[slot] = itemID
					promoted = promoted + 1
					break
				end
			end
		end
	end
	return promoted
end

-- { [slot] = { itemID, ... } } of the active list, and the picks.
local function WishBySlot()
	local list = LG:WishListRecord(LG:ActiveListID())
	local bySlot = {}
	for itemID in pairs(list and list.items or {}) do
		itemID = tonumber(itemID)
		for _, slot in ipairs(itemID and SlotsFor(itemID) or {}) do
			bySlot[slot] = bySlot[slot] or {}
			table.insert(bySlot[slot], itemID)
		end
	end
	for _, ids in pairs(bySlot) do table.sort(ids) end
	local picks = LG:WishPicks()
	local shown = {}
	for _, slot in ipairs(ALL_SLOTS) do
		local ids = bySlot[slot]
		local pick = picks[slot]
		local valid = false
		for _, id in ipairs(ids or {}) do if id == pick then valid = true end end
		if valid then shown[slot] = pick elseif ids then
			-- The best scoring wished item, without using one ring twice.
			local best, bestScore
			for _, id in ipairs(ids) do
				local taken = (slot == 12 and shown[11] == id) or (slot == 14 and shown[13] == id) or (slot == 17 and shown[16] == id)
				local score = LG:ScoreItem(id) or 0
				if not taken and (not bestScore or score > bestScore) then best, bestScore = id, score end
			end
			shown[slot] = best
		end
	end
	return shown, bySlot
end

---------------------------------------------------------------------------
-- Views
---------------------------------------------------------------------------
local VIEW_TITLES = E:TranslateValues({ worn = E.Key("What I wear"), bis = E.Key("Best in Slot"), wish = E.Key("Wishlist") })

local function SetIndex(view)
	return view == "set1" and 1 or view == "set2" and 2 or nil
end

-- { [slot] = itemID }, extra (bis: nil while ranking; wish: bySlot).
local function ViewItems(view)
	if view == "worn" then return LG:Player().equipped end
	if view == "bis" then return LG:BiSSet(LG:PlanPhase()) end
	if view == "wish" then
		local shown, bySlot = WishBySlot()
		return shown, bySlot
	end
	local data = LG:Char()
	local index = SetIndex(view)
	return data and index and data.sets[index].slots or {}
end

local function Total(items)
	local total = 0
	for _, slot in ipairs(ALL_SLOTS) do
		local id = items and items[slot]
		if id then total = total + (LG:ScoreItem(id) or 0) end
	end
	return total
end

-- Gain of the BiS set over what you wear, in percent.
local function SetGain(items)
	local worn = Total(LG:Player().equipped)
	local total = Total(items)
	if worn <= 0 then return end
	return (total - worn) / worn * 100
end

---------------------------------------------------------------------------
-- Slot cards
---------------------------------------------------------------------------
local function TwoHander(items)
	local main = items and items[16]
	local equipLoc = main and select(4, C_Item.GetItemInfoInstant(main))
	if Secret(equipLoc) then return false end
	return equipLoc == "INVTYPE_2HWEAPON"
end

local function GainFor(itemID, slot)
	if not itemID then return end
	local worn = LG:WornScore(slot)
	local score = LG:ScoreItem(itemID)
	if not (score and worn and worn > 0) then return end
	return (score - worn) / worn * 100
end

local function CreateCard(parent, slot, onClick)
	local card = CreateFrame("Button", nil, parent)
	card:SetSize(CARD_W, CARD_H)
	card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	E:SkinRow(card)
	card.slot = slot
	card.iconBox = CreateFrame("Frame", nil, card)
	card.iconBox:SetSize(CARD_H - 4, CARD_H - 4)
	card.iconBox:SetPoint("LEFT", 2, 0)
	E:SetTemplate(card.iconBox)
	card.icon = card.iconBox:CreateTexture(nil, "ARTWORK")
	card.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	card.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(card.icon)
	card.name = Kit.Text(card, 12, "LEFT")
	-- The icon sits on the card's middle: the two lines take their top and
	-- bottom from its edges.
	card.name:SetPoint("TOPLEFT", card.iconBox, "TOPRIGHT", 6, -2)
	card.name:SetPoint("TOPRIGHT", card, "RIGHT", -4, (CARD_H - 4) / 2 - 2)
	card.name:SetWordWrap(false)
	card.sub = Kit.Text(card, 10, "LEFT", "secondary")
	card.sub:SetPoint("BOTTOMLEFT", card.iconBox, "BOTTOMRIGHT", 6, 2)
	card.sub:SetPoint("BOTTOMRIGHT", card, "RIGHT", -4, -(CARD_H - 4) / 2 + 2)
	card.sub:SetWordWrap(false)
	card:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			if self.itemID then Kit.ItemMenu(self, self.itemID) end
			return
		end
		if self.itemID and IsModifiedClick() then
			local _, link = C_Item.GetItemInfo(self.itemID)
			if LG:IsCheckClick() then LG:OpenCheck(link or ("item:" .. self.itemID)) return end
			if not Secret(link) and link and HandleModifiedItemClick(link) then return end
		end
		onClick(self)
	end)
	card:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.itemID then
			GameTooltip:SetItemByID(self.itemID)
		else
			E.UIKit.TipTitle(GameTooltip, LG:SlotLabel(self.slot))
			if self.why then E.UIKit.TipText(GameTooltip, self.why) end
		end
		GameTooltip:AddLine(" ")
		E:TooltipHint(GameTooltip, { L["Click"], L["the items that fit this slot"] }, { L["Right-click an item"], L["more"] })
		GameTooltip:Show()
	end)
	card:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return card
end

local function FillCard(card, itemID, view, items, extra)
	card.itemID = itemID
	card.why = nil
	if itemID then
		local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
		if Secret(name) then name, quality, icon = nil, nil, nil end
		if not name then
			local record = LG:ItemRecord(itemID)
			name, quality = record and record.name, record and record.quality
			LG:RequestItem(itemID)
		end
		card.icon:SetTexture(icon or C_Item.GetItemIconByID(itemID) or 134400)
		card.icon:SetDesaturated(false)
		card.name:SetText(name or ("item:" .. itemID))
		local r, g, b = Kit.QualityColor(quality)
		card.name:SetTextColor(r, g, b)
		if type(quality) == "number" and quality >= 2 then card.iconBox:SetBackdropBorderColor(r, g, b, 1)
		else card.iconBox:SetBackdropBorderColor(unpack(E.media.borderColor)) end
		local bits = {}
		if view == "worn" then
			local bis = LG:BiSSet(LG:PlanPhase())
			local best = bis and bis[card.slot]
			if best and best ~= itemID then
				local gain = GainFor(best, card.slot)
				if gain and gain > 0 then bits[#bits + 1] = Kit.Hex(unpack(Kit.GOOD)) .. L["BiS +%.1f%%"]:format(gain) .. "|r" end
			elseif best == itemID then
				bits[#bits + 1] = E:TextHex("accent") .. L["Best in Slot"] .. "|r"
			end
		else
			local worn = LG:Player().equipped[card.slot]
			if worn == itemID then
				bits[#bits + 1] = L["Worn"]
			else
				local gain = GainFor(itemID, card.slot)
				if gain then
					local color = gain > 0 and Kit.GOOD or Kit.SECONDARY
					bits[#bits + 1] = Kit.Hex(unpack(color)) .. ("%+.1f%%"):format(gain) .. "|r"
				elseif not worn then
					bits[#bits + 1] = Kit.Hex(unpack(Kit.GOOD)) .. L["Fills an empty slot"] .. "|r"
				end
			end
		end
		if view == "wish" and extra and extra[card.slot] and #extra[card.slot] > 1 then
			bits[#bits + 1] = (L["%d wished"]):format(#extra[card.slot])
		end
		local badge = LG:PhaseBadge(itemID)
		if badge then bits[#bits + 1] = badge end
		card.sub:SetText(table.concat(bits, "  "))
		card:SetAlpha(1)
	else
		card.icon:SetTexture(134400)
		card.icon:SetDesaturated(true)
		card.iconBox:SetBackdropBorderColor(unpack(E.media.borderColor))
		card.name:SetText(LG:SlotLabel(card.slot))
		Kit.Paint(card.name, "dim")
		local why
		if card.slot == 17 and TwoHander(items) then
			why = L["Two-hander in the main hand"]
		elseif view == "worn" then
			why = L["Nothing worn"]
		elseif view == "bis" then
			why = items and L["Nothing on your list: widen the filter"] or L["Ranking your items..."]
		elseif view == "wish" then
			why = L["No wished item for this slot"]
		else
			why = L["Empty slot: click to pick"]
		end
		card.why = why
		card.sub:SetText(why)
		card:SetAlpha(0.85)
	end
end

---------------------------------------------------------------------------
-- Model
---------------------------------------------------------------------------
local function UpdateModel(page, items)
	local model = page.model
	if not model:IsShown() then return end
	if model.SetUnit then pcall(model.SetUnit, model, "player") end
	if model.Undress then pcall(model.Undress, model) end
	for _, slot in ipairs(ALL_SLOTS) do
		local id = items and items[slot]
		if id and model.TryOn then
			local _, link = C_Item.GetItemInfo(id)
			pcall(model.TryOn, model, (not Secret(link) and link) and link or ("item:" .. id))
		end
	end
end

local function CreateModel(page)
	local holder = CreateFrame("Frame", nil, page)
	holder.glow = holder:CreateTexture(nil, "BACKGROUND")
	holder.glow:SetPoint("BOTTOMLEFT", 20, 10)
	holder.glow:SetPoint("BOTTOMRIGHT", -20, 10)
	holder.glow:SetHeight(140)
	holder.glow:SetTexture("Interface\\Buttons\\WHITE8X8")
	local model = CreateFrame("DressUpModel", nil, holder)
	model:SetAllPoints()
	model:EnableMouse(true)
	model:EnableMouseWheel(true)
	model.facing, model.zoom = 0, 0
	model:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then
			self.dragX = GetCursorPosition()
			self:SetScript("OnUpdate", function(own)
				local x = GetCursorPosition()
				own.facing = (own.facing or 0) + (x - (own.dragX or x)) / 80
				own.dragX = x
				if own.SetFacing then own:SetFacing(own.facing) end
			end)
		end
	end)
	model:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
	model:SetScript("OnMouseWheel", function(self, delta)
		self.zoom = math.max(0, math.min(0.9, (self.zoom or 0) + delta * 0.1))
		if self.SetPortraitZoom then self:SetPortraitZoom(self.zoom) end
	end)
	Kit.Tooltip(model, L["Model"], L["Wears the set on show. Drag to turn it, mouse wheel to zoom."])
	holder.model = model
	return holder
end

local function PaintGlow(page)
	local _, class = UnitClass("player")
	local color = E:ClassColorObject(class)
	local r, g, b = 0.5, 0.5, 0.5
	if color then r, g, b = color.r, color.g, color.b end
	page.modelHolder.glow:SetGradient("VERTICAL", CreateColor(r, g, b, 0.25), CreateColor(r, g, b, 0))
end

---------------------------------------------------------------------------
-- Flyout: the items that fit a slot
---------------------------------------------------------------------------
local slotIndex   -- group -> { itemID, ... } (every LootData item)

LG:On("bis-slotindex", function(changed)
	if changed.data then slotIndex = nil end
end)

local function SlotIndex()
	if slotIndex then return slotIndex end
	slotIndex = {}
	local data = select(3, LG:DataStatus())
	for itemID in pairs(data and data.items or {}) do
		local group = LG:SlotGroup(itemID)
		if group then
			slotIndex[group] = slotIndex[group] or {}
			table.insert(slotIndex[group], itemID)
		end
	end
	return slotIndex
end

local function GroupsForSlot(slot)
	local groups = {}
	for group, slots in pairs(LG.GROUP_SLOTS) do
		for _, s in ipairs(slots) do
			if s == slot then groups[#groups + 1] = group end
		end
	end
	if slot == 17 and not LG:Player().dualWield then
		for index = #groups, 1, -1 do
			if groups[index] == "onehand" then table.remove(groups, index) end
		end
	end
	return groups
end

local REASON = E:TranslateValues({
	quests = Key("quest you have done or can't take"), dungeons = Key("dungeons are off in your filter"),
	rares = Key("rares are off in your filter"), crafted = Key("needs a profession"), world = Key("world drops are off in your filter"),
	vendor = Key("vendors are off in your filter"), reputation = Key("reputation is off in your filter"), pvp = Key("PvP is off in your filter"),
})

-- Rows for a slot: { itemID, score, armor, source, onList, why } best first.
local function FlyoutRows(slot, higher)
	local rows, seen = {}, {}
	local player = LG:Player()
	local phase = LG:PlanPhase()
	local cap = higher and 60 or player.level
	for _, group in ipairs(GroupsForSlot(slot)) do
		for _, itemID in ipairs(SlotIndex()[group] or {}) do
			if not seen[itemID] then
				seen[itemID] = true
				local record = LG:ItemRecord(itemID)
				local ok = LG:CanUseRecord(record, true)
				local useLevel = LG:UseLevel(itemID) or 1
				if ok and useLevel <= cap and not LG:IsFuturePhase(itemID, phase) then
					local score = LG:ScoreItem(itemID)
					if score and score > 0 then
						local onList, _, chips = LG:Obtainable(itemID)
						local why
						if not onList then
							local chip = type(chips) == "table" and chips[1]
							why = chip and REASON[chip] or L["not on your list"]
						end
						local sources = LG:ItemSources(itemID)
						rows[#rows + 1] = { itemID = itemID, score = score, armor = record and record.class == 4 and record.subclass or nil,
							source = sources and sources[1] and P.SourceLine(sources[1]) or "", onList = onList, why = why,
							useLevel = useLevel, name = record and record.name or "" }
					end
				end
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.onList ~= b.onList then return a.onList and true or false end
		if a.score ~= b.score then return a.score > b.score end
		return a.itemID < b.itemID
	end)
	return rows
end
-- The simulator's planner picks from the same rows.
LG.BiSFlyoutRows = function(_, slot, higher) return FlyoutRows(slot, higher) end

local function FlyoutRowCreate(row)
	row.cell = P.ItemCell(row)
	row.cell:SetAllPoints()
end

local function FlyoutRowUpdate(row, item)
	if item.none then
		P.SetItem(row.cell, { itemID = 0, sub = L["Leaves the slot empty"] })
		row.cell.name:SetText(L["None"])
		Kit.Paint(row.cell.name, "secondary")
		row.cell.icon:SetTexture(134400)
		row.cell.right:SetText("")
		row.cell.starButton:Hide()
		return
	end
	local bits = {}
	if item.armor and ARMOR_NAMES[item.armor] then bits[#bits + 1] = ARMOR_NAMES[item.armor] end
	if item.source ~= "" then bits[#bits + 1] = item.source end
	if item.why then bits[#bits + 1] = Kit.Hex(unpack(Kit.WARN)) .. item.why .. "|r" end
	if item.useLevel > LG:Player().level then bits[#bits + 1] = (L["from level %d"]):format(item.useLevel) end
	local gain = GainFor(item.itemID, item.slot)
	P.SetItem(row.cell, { itemID = item.itemID, sub = table.concat(bits, " · "), dim = not item.onList,
		tag = gain and (("%+.1f%%"):format(gain)) or nil, badge = LG:PhaseBadge(item.itemID),
		onClick = function() item.pick(item.itemID) end })
end

local function BuildFlyout(page)
	local fly = CreateFrame("Frame", nil, page)
	fly:SetSize(FLYOUT_W, FLYOUT_H)
	fly:SetFrameLevel(page:GetFrameLevel() + 40)
	fly:EnableMouse(true)
	E:SetTemplate(fly)
	fly:Hide()
	fly.title = Kit.Text(fly, 13, "LEFT", "header")
	fly.title:SetPoint("TOPLEFT", 10, -8)
	fly.close = CreateFrame("Button", nil, fly, "UIPanelCloseButton")
	fly.close:SetPoint("TOPRIGHT", -2, -2)
	E:SkinCloseButton(fly.close)
	fly.close:SetScript("OnClick", function() fly:Hide() end)
	fly.search = CreateFrame("EditBox", nil, fly, "SearchBoxTemplate")
	E:SearchHint(fly.search)
	fly.search:SetSize(FLYOUT_W - 20, 20)
	fly.search:SetPoint("TOPLEFT", 12, -30)
	fly.search:SetAutoFocus(false)
	E:SkinEditBox(fly.search)
	Kit.Tooltip(fly.search, L["Search"], L["Filters the rows by item name and source."])
	fly.search:HookScript("OnTextChanged", function() if fly.Draw then fly:Draw() end end)
	fly.chips = {}
	fly.higher = P.Toggle(fly, L["Higher levels"], function()
		State().higher = not State().higher
		fly:Draw(true)
	end, L["Higher levels"], L["Also lists items above your level, to plan ahead. Saved for this character."])
	fly.notice = Kit.Text(fly, 11, "LEFT")
	fly.notice:SetPoint("BOTTOMLEFT", 10, 8)
	fly.notice:SetPoint("BOTTOMRIGHT", -10, 8)
	fly.notice:SetTextColor(unpack(Kit.WARN))
	fly.list = Kit.CreateList(fly, { create = FlyoutRowCreate, update = FlyoutRowUpdate, gap = 2 })
	fly.list:SetPoint("TOPLEFT", 8, -82)
	fly.list:SetPoint("BOTTOMRIGHT", -8, 26)
	return fly
end

---------------------------------------------------------------------------
-- Filter panel (Filter and Stat priority tabs)
---------------------------------------------------------------------------
local function FilterSummary()
	local spec = SpecName(PlayerSpec())
	local list = LG:IsRealisticList() and L["realistic list"] or L["your own list"]
	return (L["Filter: %s · %s"]):format(spec, list)
end

local function ChanceLabel(value)
	value = tonumber(value) or 0
	if value <= 0 then return L["All"] end
	return ("%d%%"):format(value)
end

local function DrawFilterTab(panel)
	local flow = panel.flow
	local engine = E.ItemScore
	local player = LG:Player()
	flow:Begin()
	P.FlowCaption(flow, L["Spec"])
	local current = PlayerSpec()
	local detected = engine and engine.DetectedSpec and engine:DetectedSpec()
	for _, spec in ipairs(engine and engine:Specs(player.class) or {}) do
		local roles = { TANK = L["Tank"], HEALER = L["Healer"], DAMAGER = L["Damage"] }
		local text = spec.name .. "  " .. E:TextHex("secondary") .. (roles[spec.role] or "") .. "|r"
		if spec.key == detected then text = text .. "  " .. Kit.Hex(unpack(Kit.GOOD)) .. L["your talents"] .. "|r" end
		if spec.key == current then text = E:TextHex("accent") .. "> |r" .. text end
		P.FlowLine(flow, text, function()
			engine:SetPlayerSpec(spec.key == detected and nil or spec.key)
			LG:Fire("spec")
			panel:Draw()
		end, nil, spec.name, spec.note)
	end
	P.FlowCaption(flow, L["Armor"])
	local list = LG:List()
	for subclass = 1, 4 do
		local from = LG:ArmorLevel(player.class, subclass)
		if from then
			local off = type(list.armor) == "table" and list.armor[subclass] == false
			local label = ARMOR_NAMES[subclass] .. (from > player.level and ("  " .. E:TextHex("secondary") .. (L["from level %d"]):format(from) .. "|r") or "")
			P.FlowLine(flow, (off and E:TextHex("dim") or "") .. label .. (off and ("  " .. L["(left out)"] .. "|r") or ""), function()
				LG:SetListArmor(subclass, off)
				panel:Draw()
			end, nil, ARMOR_NAMES[subclass], function(tip) Kit.TooltipHint(tip, { L["Click"], L["leave this armor kind out of your list, or take it back in"] }) end)
		end
	end
	P.FlowCaption(flow, L["Sources"])
	local chipNames = { quests = L["Quests"], dungeons = L["Dungeons"], rares = L["Rare"], crafted = L["Crafted"], world = L["World"],
		vendor = L["Vendors"], reputation = L["Reputation"], pvp = L["PvP"] }
	for _, chip in ipairs(LG.SOURCE_CHIPS) do
		local on = list.sources[chip] and true or false
		local accent = { Kit.Accent() }
		local text = (on and E.UIKit.InlineGlyph("check", 12, accent) or E.UIKit.InlineGlyph("dot", 12, E.tokens.text.dim)) .. " "
			.. (chipNames[chip] or chip)
		P.FlowLine(flow, text, function()
			LG:SetListSource(chip, not on)
			panel:Draw()
		end, nil, chipNames[chip], L["Counts items from this source as gear you can get."])
	end
	P.FlowCaption(flow, L["Lowest drop chance"], ChanceLabel(list.minChance))
	panel.slider:ClearAllPoints()
	flow:Place(panel.sliderHolder, 26, 4, 4)
	panel.slider:SetPoint("LEFT", panel.sliderHolder, "LEFT", 4, 0)
	panel.slider:SetPoint("RIGHT", panel.sliderHolder, "RIGHT", -8, 0)
	panel.slider.setting = true
	panel.slider:SetValue(tonumber(list.minChance) or 0)
	panel.slider.setting = false
	flow:Space(6)
	P.FlowLine(flow, LG:IsRealisticList() and (E:TextHex("dim") .. L["Back to realistic"] .. "|r") or (E:TextHex("accent") .. L["Back to realistic"] .. "|r"),
		function()
			LG:ResetList()
			panel:Draw()
		end, nil, L["Back to realistic"], L["Quests, dungeons, crafted, vendors and reputation; no rares, world drops or PvP; every drop chance; every armor kind you wear."])
	flow:Finish(true)
end

-- Stat priority: bars in order; drag one to move it (only its weight changes).
local function DrawPriorityTab(panel)
	local flow = panel.flow
	local engine = E.ItemScore
	local spec = PlayerSpec()
	flow:Begin()
	P.FlowCaption(flow, L["Stat priority"], SpecName(spec))
	P.FlowText(flow, L["Drag a stat up or down. Only the stat you move changes weight; the rest keep theirs."], 11, "secondary")
	local order = engine and spec and engine:Priority(spec) or {}
	local default = engine and spec and engine:DefaultPriority(spec) or {}
	local defaultPos = {}
	for index, key in ipairs(default) do defaultPos[key] = index end
	local weights = engine and spec and engine:SpecWeights(spec) or {}
	local typical = E.StatWeights and E.StatWeights.typical or {}
	local top
	for _, key in ipairs(order) do
		local value = (tonumber(weights[key]) or 0) * (typical[key] or 1)
		top = top or value
	end
	panel.order = order
	for index, key in ipairs(order) do
		local bar = flow:Take("statbar", function(child)
			local b = CreateFrame("Button", nil, child)
			b:RegisterForDrag("LeftButton")
			b.fill = b:CreateTexture(nil, "ARTWORK")
			b.fill:SetPoint("TOPLEFT", 0, -2)
			b.fill:SetPoint("BOTTOMLEFT", 0, 2)
			E:UseBarTexture(b.fill)
			b.label = Kit.Text(b, 11, "LEFT")
			b.label:SetPoint("LEFT", 6, 0)
			b:SetScript("OnDragStart", function(self) self.dragging = true end)
			b:SetScript("OnDragStop", function(self)
				self.dragging = nil
				local holder = self:GetParent()
				local _, y = GetCursorPosition()
				y = y / holder:GetEffectiveScale()
				local target
				for _, other in ipairs(holder.statBars or {}) do
					if other:IsShown() and other:GetTop() and y <= other:GetTop() and y >= other:GetBottom() then target = other.index end
				end
				if target and target ~= self.index then self.panel.Move(self.index, target) end
			end)
			return b
		end)
		flow:Place(bar, 20, 0, 2)
		bar.index, bar.panel = index, panel
		flow.child.statBars = flow.child.statBars or {}
		flow.child.statBars[index] = bar
		local value = (tonumber(weights[key]) or 0) * (typical[key] or 1)
		local width = math.max(4, (flow:Width() - 10) * (top and top > 0 and value / top or 0))
		bar.fill:SetWidth(width)
		local moved = defaultPos[key] ~= index
		local r, g, b = Kit.Accent()
		if moved then bar.fill:SetVertexColor(r, g, b, 0.55) else bar.fill:SetVertexColor(E:TokenColor("dim", 0.45)) end
		bar.label:SetText(("%d. %s"):format(index, engine.StatLabel and engine.StatLabel(key) or key))
		if moved then bar.label:SetTextColor(r, g, b) else Kit.Paint(bar.label) end
		Kit.Tooltip(bar, engine.StatLabel and engine.StatLabel(key) or key, moved and L["Moved by you. Default order puts it back."] or L["Drag to move."])
	end
	for index = #order + 1, #(flow.child.statBars or {}) do flow.child.statBars[index] = nil end
	flow:Space(8)
	P.FlowLine(flow, E:TextHex("accent") .. L["Default order"] .. "|r", function()
		engine:SetPriority(spec, nil)
		LG:Fire("spec")
		panel:Draw()
	end, nil, L["Default order"], L["Removes your own order: EldoUI's weights for this spec again."])
	flow:Finish(true)
end

local function BuildFilter(page)
	local panel = CreateFrame("Frame", nil, page)
	panel:SetWidth(FILTER_W)
	panel:SetPoint("TOPRIGHT", 0, -28)
	panel:SetPoint("BOTTOMRIGHT")
	panel:SetFrameLevel(page:GetFrameLevel() + 35)
	panel:EnableMouse(true)
	E:SetTemplate(panel)
	panel:Hide()
	panel.tabFilter = P.Toggle(panel, L["Filter"], function() panel.tab = "filter" panel:Draw() end, L["Filter"],
		L["Spec, armor, sources and the lowest drop chance your list counts."])
	panel.tabFilter:SetPoint("TOPLEFT", 8, -8)
	panel.tabPriority = P.Toggle(panel, L["Stat priority"], function() panel.tab = "priority" panel:Draw() end, L["Stat priority"],
		L["The order your spec values stats in. Drag to change it."])
	panel.tabPriority:SetPoint("LEFT", panel.tabFilter, "RIGHT", 4, 0)
	panel.done = Kit.Button(panel, L["Done"], 70, 20, function() panel:Hide() end, L["Done"], L["Closes the filter. Changes are already saved."])
	panel.done:SetPoint("TOPRIGHT", -8, -6)
	panel.flow = P.Flow(panel)
	panel.flow:SetPoint("TOPLEFT", 10, -34)
	panel.flow:SetPoint("BOTTOMRIGHT", -4, 8)
	panel.sliderHolder = CreateFrame("Frame", nil, panel.flow.child)
	panel.slider = CreateFrame("Slider", nil, panel.sliderHolder)
	panel.slider:SetOrientation("HORIZONTAL")
	panel.slider:SetHeight(14)
	panel.slider:SetMinMaxValues(0, 50)
	panel.slider:SetValueStep(1)
	panel.slider:SetObeyStepOnDrag(true)
	E:SetTemplate(panel.slider, true)
	local thumb = panel.slider:CreateTexture(nil, "OVERLAY")
	thumb:SetSize(8, 14)
	thumb:SetColorTexture(Kit.Accent())
	panel.slider:SetThumbTexture(thumb)
	panel.slider:EnableMouseWheel(true)
	-- Applies when the knob is let go (E.UIKit.SliderCommit): the list is
	-- rebuilt once, not on every step of a drag.
	local FeedChance = E.UIKit.SliderCommit(panel.slider, { commit = function(value)
		LG:SetListMinChance(math.floor((value or 0) + 0.5))
		panel:Draw()
	end })
	panel.slider:SetScript("OnValueChanged", function(self, value)
		if not self.setting then FeedChance(value) end
	end)
	panel.slider:SetScript("OnMouseWheel", function(self, delta)
		self:SetValue(math.max(0, math.min(50, math.floor((self:GetValue() or 0) + 0.5) + delta)))
	end)
	Kit.Tooltip(panel.slider, L["Lowest drop chance"], L["Drops rarer than this leave your list. Drag and let go, or use the mouse wheel for 1 % steps."])
	panel.Move = function(from, to)
		local order = {}
		for index, key in ipairs(panel.order or {}) do order[index] = key end
		local key = table.remove(order, from)
		table.insert(order, to, key)
		E.ItemScore:SetPriority(PlayerSpec(), order, key)
		LG:Fire("spec")
		panel:Draw()
	end
	function panel:Draw()
		self.tab = self.tab or "filter"
		self.tabFilter:SetOn(self.tab == "filter")
		self.tabPriority:SetOn(self.tab == "priority")
		self.sliderHolder:Hide()
		if self.tab == "priority" then DrawPriorityTab(self) else
			self.sliderHolder:Show()
			DrawFilterTab(self)
		end
		page.filterButton:SetText(FilterSummary())
	end
	return panel
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local Draw

-- Write a pick: into a set view, or copy the view on show into the first
-- free set and put it there (notice when both sets are in use).
local function Pick(page, slot, itemID)
	local s = State()
	local data = LG:Char()
	if not data then return end
	local index = SetIndex(s.view)
	if s.view == "wish" then
		LG:WishPicks()[slot] = itemID ~= 0 and itemID or nil
		page.flyout:Hide()
		LG:Fire("wishlist")
		return
	end
	if not index then
		for i = 1, 2 do
			if not index and not next(data.sets[i].slots) then index = i end
		end
		if not index then
			page.flyout.notice:SetText(L["Both plan sets are in use. Open Set 1 or Set 2 to change one, or clear a set first."])
			return
		end
		local items = ViewItems(s.view) or {}
		for _, sl in ipairs(ALL_SLOTS) do data.sets[index].slots[sl] = items[sl] end
		LG:Notify((L["Copied %s into %s."]):format(VIEW_TITLES[s.view] or "", LG:SetName(index)))
		s.view = "set" .. index
	end
	local slots = data.sets[index].slots
	if itemID == 0 then
		slots[slot] = nil
	else
		slots[slot] = itemID
		local equipLoc = select(4, C_Item.GetItemInfoInstant(itemID))
		if slot == 16 and equipLoc == "INVTYPE_2HWEAPON" then slots[17] = nil end
		if slot == 17 and TwoHander(slots) then slots[16] = nil end
	end
	page.flyout:Hide()
	LG:Fire("sets")
	Draw(page)
end

local function OpenFlyout(page, card)
	local fly = page.flyout
	local s = State()
	local slot = card.slot
	fly.slot = slot
	fly.notice:SetText("")
	fly.search:SetText("")
	fly:ClearAllPoints()
	if card:GetLeft() and page:GetLeft() and (card:GetLeft() - page:GetLeft()) < page:GetWidth() / 2 then
		fly:SetPoint("TOPLEFT", card, "TOPRIGHT", 6, 0)
	else
		fly:SetPoint("TOPRIGHT", card, "TOPLEFT", -6, 0)
	end
	fly.armorShown = nil
	function fly.Draw(self, rebuild)
		local state = State()
		if rebuild or not self.rows or self.rowsSlot ~= slot or self.rowsHigher ~= (state.higher and true or false) or self.rowsView ~= state.view then
			if state.view == "wish" then
				local _, bySlot = WishBySlot()
				self.rows = {}
				for _, id in ipairs(bySlot[slot] or {}) do
					local record = LG:ItemRecord(id)
					local sources = LG:ItemSources(id)
					self.rows[#self.rows + 1] = { itemID = id, score = LG:ScoreItem(id) or 0, onList = true, useLevel = LG:UseLevel(id) or 1,
						armor = record and record.class == 4 and record.subclass or nil, name = record and record.name or "",
						source = sources and sources[1] and P.SourceLine(sources[1]) or "" }
				end
			else
				self.rows = FlyoutRows(slot, state.higher)
			end
			self.rowsSlot, self.rowsHigher, self.rowsView = slot, state.higher and true or false, state.view
		end
		local text = E:FoldText(self.search:GetText() or "")
		local counts = {}
		local shown = {}
		if SetIndex(state.view) then shown[1] = { none = true } end
		for _, row in ipairs(self.rows) do
			row.slot = slot
			row.pick = function(id) Pick(page, slot, id) end
			if row.armor then counts[row.armor] = (counts[row.armor] or 0) + 1 end
			local match = text == "" or E:FoldText(row.name):find(text, 1, true) or E:FoldText(row.source):find(text, 1, true)
			if match and (not self.armorShown or not row.armor or self.armorShown == row.armor) then shown[#shown + 1] = row end
		end
		self.title:SetText(("%s  " .. E:TextHex("secondary") .. "%d|r"):format(LG:SlotLabel(slot), #self.rows))
		-- Armor chips with counts.
		local anchor
		local chipIndex = 0
		for subclass = 1, 4 do
			if counts[subclass] then
				chipIndex = chipIndex + 1
				local chip = self.chips[chipIndex]
				if not chip then
					chip = P.Toggle(self, "", function(own)
						self.armorShown = self.armorShown ~= own.subclass and own.subclass or nil
						self:Draw()
					end, L["Armor"], L["Shows only this armor kind. Click again for all."])
					self.chips[chipIndex] = chip
				end
				chip.subclass = subclass
				chip:SetLabel(("%s %d"):format(ARMOR_NAMES[subclass], counts[subclass]))
				chip:SetOn(self.armorShown == subclass)
				chip:ClearAllPoints()
				if anchor then chip:SetPoint("LEFT", anchor, "RIGHT", 4, 0) else chip:SetPoint("TOPLEFT", 10, -56) end
				chip:Show()
				anchor = chip
			end
		end
		for index = chipIndex + 1, #self.chips do self.chips[index]:Hide() end
		self.higher:ClearAllPoints()
		self.higher:SetPoint("TOPRIGHT", -10, -56)
		self.higher:SetOn(state.higher)
		self.higher:SetShown(state.view ~= "wish")
		self.list:SetData(shown)
		if #shown == 0 then self.notice:SetText(state.view == "wish" and L["No wished item fits this slot."] or L["Nothing fits: widen the filter or turn on Higher levels."]) end
	end
	fly:Draw(true)
	fly:Show()
end

local function DrawCards(page, items, extra)
	local s = State()
	for _, card in pairs(page.cards) do
		FillCard(card, items and items[card.slot], s.view, items, extra)
	end
end

Draw = function(page)
	local s = State()
	local view = s.view or "bis"
	if view ~= "worn" and view ~= "bis" and view ~= "set1" and view ~= "set2" and view ~= "wish" then view = "bis" end
	if view == "wish" and not LG:WishlistOn() then view = "bis" end
	s.view = view
	local phase, follows = LG:PlanPhase()
	local spec = PlayerSpec()
	local specName = SpecName(spec)
	local player = LG:Player()
	local title = L["Best in Slot"]
	if phase and not follows then title = title .. " · " .. LG:PhaseName(phase) end
	page.title:SetText(title)
	local className = UnitClass("player")
	if Secret(className) then className = nil end
	page.sub:SetText(("%s %s, %s"):format(specName, className or "", (L["level %d"]):format(player.level))
		.. (player.dualWield and ("  ·  " .. L["two weapons"]) or ""))
	page.filterButton:SetText(FilterSummary())
	if LG:MaxPhase() then
		page.phase:SetLabel(follows and L["Plan: now"] or (L["Plan: %s"]):format(LG:PhaseName(phase)))
		page.phase:Show()
	else
		page.phase:Hide()
	end
	-- View chips.
	local bisItems, bisTotal = LG:BiSSet(phase)
	local gain = bisItems and SetGain(bisItems)
	for _, key in ipairs({ "worn", "bis", "set1", "set2", "wish" }) do
		local chip = page.views[key]
		local label = VIEW_TITLES[key] or LG:SetName(SetIndex(key))
		local simGain = key == "bis" and LG.SimMode and LG:SimMode() and LG:SimSetGainText()
		if simGain then
			label = label .. " " .. Kit.Hex(unpack(Kit.GOOD)) .. simGain .. "|r"
		elseif key == "bis" and gain and gain > 0 then
			label = label .. " " .. Kit.Hex(unpack(Kit.GOOD)) .. ("+%.1f%%"):format(gain) .. "|r"
		end
		chip:SetLabel(label)
		chip:SetOn(key == view)
		chip:SetShown(key ~= "wish" or LG:WishlistOn())
	end
	page.rename:SetShown(SetIndex(view) ~= nil)
	page.copy1:SetShown(view == "wish")
	page.copy2:SetShown(view == "wish")
	local items, extra = ViewItems(view)
	page.items = items
	DrawCards(page, items, extra)
	-- Empty-set help.
	local empty = SetIndex(view) and not next(items or {})
	page.help:SetShown(empty or (view == "wish" and not next(items or {})))
	if empty then
		page.help:SetText((L["%s is empty. Click a slot to pick an item for it, or right-click any item in the Loot Guide and choose Put in %s."]):format(
			LG:SetName(SetIndex(view)), LG:SetName(SetIndex(view))))
	elseif view == "wish" and not next(items or {}) then
		page.help:SetText(L["Your active wishlist has no gear. Star items in the Journal or Search; they show here by slot."])
	end
	page.status:SetText((view == "bis" and not bisItems) and L["Ranking your items..."] or "")
	if page.UpdateSim then page.UpdateSim() end
	if not bisItems then LG:RankAll(nil, { phase = phase }) end
	page.bisTotal = bisTotal
	-- Model (hidden in compact rows).
	local compact = LG.db.density == "compact"
	page.modelHolder:SetShown(not compact)
	if not compact then
		PaintGlow(page)
		UpdateModel(page, items)
	end
	if page.flyout:IsShown() and page.flyout.Draw then page.flyout:Draw(true) end
	if page.filter:IsShown() then page.filter:Draw() end
end

local function PhaseMenu(owner)
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(L["Plan for"])
		root:CreateRadio(L["Now"] .. " (" .. LG:PhaseName(LG:CurrentPhase()) .. ")", function() return LG:UI().bisPhase == nil end,
			function() LG:SetPlanPhase(nil) end)
		for phase = 1, LG:MaxPhase() or 1 do
			root:CreateRadio(LG:PhaseName(phase), function() return LG:UI().bisPhase == phase end, function() LG:SetPlanPhase(phase) end)
		end
	end, { at = "owner" })
end

local function Create(parent)
	local page = CreateFrame("Frame", nil, parent)
	page:SetAllPoints()
	page.title = Kit.Text(page, 15, "LEFT")
	page.title:SetPoint("TOPLEFT", 0, -2)
	page.sub = Kit.Text(page, 11, "LEFT", "secondary")
	page.sub:SetPoint("LEFT", page.title, "RIGHT", 10, -1)
	page.phase = P.Toggle(page, L["Plan: now"], function(self) PhaseMenu(self) end, L["Plan for"],
		L["Plan with what WoW: Forever has open now, or with an announced step such as the December raids: loot up to that step counts. Now follows the announced days."])
	page.phase:SetPoint("TOPRIGHT", 0, -2)
	page.export = Kit.Button(page, L["Export"], 70, 20, function() LG:ShowBiSExport() end, L["Export"],
		L["A string with this character's Best in Slot, plan sets, spec and talents (no name or realm) to share."])
	page.export:SetPoint("RIGHT", page.phase, "LEFT", -6, 0)
	page.addBis = Kit.Button(page, L["Add my BiS"], 100, 20, function()
		LG:AddMyBiS(function(added)
			LG:Notify(added > 0 and (L["Added %d best-in-slot items to your wishlist."]):format(added) or L["Every best-in-slot item is already yours or on your wishlist."])
		end)
	end, L["Add my BiS"], L["Adds the best-in-slot items for your spec that you do not own and have not wished for yet."])
	page.addBis:SetPoint("RIGHT", page.export, "LEFT", -6, 0)
	page.filterButton = Kit.Button(page, "", 260, 20, function()
		if page.filter:IsShown() then page.filter:Hide() return end
		page.flyout:Hide()
		page.filter:Draw()
		page.filter:Show()
		Kit.Tour("bisfilter", {
			{ target = page.filter.tabFilter, text = L["Filter: pick your spec, the armor you wear and where your gear may come from. Every page and tooltip uses the same list."] },
			{ target = page.filter.tabPriority, text = L["Stat priority: drag a stat to change the order. Default order takes your change back."] },
		})
	end, L["Filter"], L["Spec, armor, sources, lowest drop chance and stat priority: what counts as your gear everywhere in EldoUI."])
	page.filterButton:SetPoint("RIGHT", page.addBis, "LEFT", -8, 0)

	page.views = {}
	local anchor
	for _, key in ipairs({ "worn", "bis", "set1", "set2", "wish" }) do
		local chip = P.Toggle(page, "", function()
			State().view = key
			page.flyout:Hide()
			Draw(page)
		end, nil, nil)
		chip:SetHeight(24)
		local tips = {
			worn = L["The gear you wear; each slot shows how much its Best in Slot item adds."],
			bis = L["The best items on your list for your spec and the plan phase, one per slot. The number is the gain over what you wear."],
			set1 = L["Your own plan. Click a slot to pick items; right-click the chip to rename it."],
			set2 = L["Your own plan. Click a slot to pick items; right-click the chip to rename it."],
			wish = L["Your active wishlist by slot. Click a slot to choose its main pick; the model wears the picks."],
		}
		Kit.Tooltip(chip, VIEW_TITLES[key] or L["Plan set"], tips[key])
		chip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		chip:SetScript("OnClick", function(_, button)
			local index = SetIndex(key)
			if button == "RightButton" and index then
				LG:AskText(L["New name:"], LG:SetName(index), 24, function(name)
					local data = LG:Char()
					if data and name and strtrim(name) ~= "" then data.sets[index].name = strtrim(name):gsub("|", "") end
					LG:Fire("sets")
				end)
				return
			end
			State().view = key
			page.flyout:Hide()
			Draw(page)
		end)
		if anchor then chip:SetPoint("LEFT", anchor, "RIGHT", 4, 0) else chip:SetPoint("TOPLEFT", 0, -28) end
		anchor = chip
		page.views[key] = chip
	end
	page.rename = Kit.Button(page, L["Rename"], 70, 20, function()
		local index = SetIndex(State().view)
		if not index then return end
		LG:AskText(L["New name:"], LG:SetName(index), 24, function(name)
			local data = LG:Char()
			if data and name and strtrim(name) ~= "" then data.sets[index].name = strtrim(name):gsub("|", "") end
			LG:Fire("sets")
		end)
	end, L["Rename"], L["Gives this plan set a name of your own."])
	page.rename:SetPoint("LEFT", anchor, "RIGHT", 10, 0)
	local function CopyPicks(index)
		local data = LG:Char()
		if not data then return end
		local items = ViewItems("wish") or {}
		wipe(data.sets[index].slots)
		for _, slot in ipairs(ALL_SLOTS) do data.sets[index].slots[slot] = items[slot] end
		LG:Notify((L["Copied your wishlist picks into %s."]):format(LG:SetName(index)))
		LG:Fire("sets")
	end
	page.copy1 = Kit.Button(page, L["Copy to set 1"], 100, 20, function() CopyPicks(1) end, L["Copy to set 1"],
		L["Replaces plan set 1 with your wishlist picks."])
	page.copy1:SetPoint("LEFT", anchor, "RIGHT", 10, 0)
	page.copy2 = Kit.Button(page, L["Copy to set 2"], 100, 20, function() CopyPicks(2) end, L["Copy to set 2"],
		L["Replaces plan set 2 with your wishlist picks."])
	page.copy2:SetPoint("LEFT", page.copy1, "RIGHT", 6, 0)
	page.status = Kit.Text(page, 11, "RIGHT", "secondary")
	page.status:SetPoint("TOPRIGHT", 0, -32)
	-- The Best in Slot simulation (EldoUI_LootSim; only when installed).
	page.sim = Kit.Button(page, L["Sim Best in Slot"], 130, 20, function()
		if LG:SimJob() then LG:OpenSim() return end
		LG:RunSim("bis")
	end, L["Sim Best in Slot"], function(tooltip)
		local r, g, b = unpack(Kit.SECONDARY)
		tooltip:AddLine(L["Fights against a target dummy with the best items of your list per slot: a quick pass, exact runs of the top picks, then the best set (one-minute fights, out of combat)."], r, g, b, true)
		tooltip:AddLine(L["Shown here and used for upgrades when Rate items by is Simulator. Estimates: set bonuses and item procs are not counted."], r, g, b, true)
		local status = LG:SimStatus()
		if status == "outdated" then tooltip:AddLine(L["The last run is outdated: your level, gear, talents or list changed."], Kit.WARN[1], Kit.WARN[2], Kit.WARN[3], true) end
	end)
	page.sim:SetPoint("TOPRIGHT", 0, -28)
	page.status:ClearAllPoints()
	page.status:SetPoint("RIGHT", page.sim, "LEFT", -8, 0)
	page.UpdateSim = function()
		local available = LG.SimAvailable and LG:SimAvailable()
		page.sim:SetShown(available and true or false)
		if not available then return end
		local status = LG:SimStatus()
		local progress = LG:SimProgress()
		if progress then
			page.sim:SetText((L["Sim %d %%"]):format(math.floor(progress * 100)) .. (status == "paused" and (" " .. L["(paused)"]) or ""))
		elseif status == "outdated" then
			page.sim:SetText(L["Sim again"])
		else
			page.sim:SetText(L["Sim Best in Slot"])
		end
	end
	if LG.SimWatch then LG:SimWatch("bispage", function() if page:IsVisible() then page.UpdateSim() end end) end

	-- Slot cards.
	page.cards = {}
	local function OnCard(card) OpenFlyout(page, card) end
	for index, slot in ipairs(LEFT_SLOTS) do
		local card = CreateCard(page, slot, OnCard)
		card:SetPoint("TOPLEFT", 0, -60 - (index - 1) * (CARD_H + CARD_GAP))
		page.cards[slot] = card
	end
	for index, slot in ipairs(RIGHT_SLOTS) do
		local card = CreateCard(page, slot, OnCard)
		card:SetPoint("TOPRIGHT", 0, -60 - (index - 1) * (CARD_H + CARD_GAP))
		page.cards[slot] = card
	end
	page.weaponRow = CreateFrame("Frame", nil, page)
	page.weaponRow:SetSize(#WEAPON_SLOTS * (CARD_W + CARD_GAP) - CARD_GAP, CARD_H)
	page.weaponRow:SetPoint("BOTTOM", 0, 2)
	for index, slot in ipairs(WEAPON_SLOTS) do
		local card = CreateCard(page.weaponRow, slot, OnCard)
		card:SetPoint("LEFT", (index - 1) * (CARD_W + CARD_GAP), 0)
		page.cards[slot] = card
	end
	page.modelHolder = CreateModel(page)
	page.modelHolder:SetPoint("TOPLEFT", CARD_W + 16, -60)
	page.modelHolder:SetPoint("BOTTOMRIGHT", -(CARD_W + 16), CARD_H + 10)
	page.model = page.modelHolder.model
	page.help = Kit.Text(page, 12, "CENTER", "secondary")
	page.help:SetPoint("CENTER", page.modelHolder, "CENTER", 0, 0)
	page.help:SetWidth(320)
	page.help:SetWordWrap(true)
	page.help:SetSpacing(3)
	page.help:Hide()
	page.flyout = BuildFlyout(page)
	page.filter = BuildFilter(page)
	return page
end

---------------------------------------------------------------------------
-- Export (/eui bis export): spec, level, phase, BiS, plan sets, talents
---------------------------------------------------------------------------
local function TalentText()
	local talents = LG:TalentRanks()
	if not talents then return end
	local parts = {}
	for tree = 1, talents.trees do parts[#parts + 1] = tostring(talents.points[tree] or 0) end
	return #parts > 0 and table.concat(parts, "/") or nil
end

function LG:BiSShareData()
	local data = self:Char()
	local player = self:Player()
	local out = { v = 1, class = player.class, spec = PlayerSpec(), level = player.level, phase = self:PlanPhase(),
		talents = TalentText(), bis = {}, sets = {} }
	local set = self:BiSSet(self:PlanPhase())
	for slot, id in pairs(set or {}) do out.bis[#out.bis + 1] = { slot, id } end
	table.sort(out.bis, function(a, b) return a[1] < b[1] end)
	for index = 1, 2 do
		local plan = { name = data and data.sets[index].name or nil, slots = {} }
		for slot, id in pairs(data and data.sets[index].slots or {}) do plan.slots[#plan.slots + 1] = { slot, id } end
		table.sort(plan.slots, function(a, b) return a[1] < b[1] end)
		out.sets[index] = plan
	end
	return out
end

-- Put an imported Best in Slot into the first empty plan set.
function LG:ImportBiS(share)
	if type(share) ~= "table" or type(share.bis) ~= "table" then return false, L["this is not a Best in Slot string"] end
	local data = self:Char()
	if not data then return false end
	local index
	for i = 1, 2 do
		if not index and not next(data.sets[i].slots) then index = i end
	end
	if not index then return false, L["both plan sets are in use; clear one first"] end
	for _, pair in ipairs(share.bis) do
		local slot, id = tonumber(pair[1]), tonumber(pair[2])
		if slot and id and slot >= 1 and slot <= 19 then data.sets[index].slots[slot] = id end
	end
	self:Fire("sets")
	return index
end

function LG:ExportBiS()
	return E:ExportShareKind("lootbis")
end

function LG:ShowBiSExport()
	local text = self:ExportBiS()
	if not text then
		LG:Notify(L["Best in Slot is still ranking your items; try again in a moment."], true)
		return
	end
	E:ShowCopyBox(L["Best in Slot export"], L["Everything is selected. Press Ctrl+C and share it. It holds your gear plans, spec and talents, not your name or realm."], text)
end

if E.RegisterShareKind then
	E:RegisterShareKind("lootbis", {
		prefix = "!EUB1!",
		version = 1,
		title = "Loot Guide Best in Slot",
		build = function() return LG:BiSShareData() end,
		describe = function(data)
			local count = type(data.bis) == "table" and #data.bis or 0
			return { E:Plural(count, "%d item for %s, level %s. Importing puts it in your first empty plan set.", "%d items for %s, level %s. Importing puts them in your first empty plan set."):format(count,
				tostring(data.spec or "?"), tostring(data.level or "?")) }
		end,
		apply = function(data)
			if not LG.active then return end
			local index, err = LG:ImportBiS(data)
			if index then LG:Notify((L["Imported into %s."]):format(LG:SetName(index))) else LG:Notify((L["Import failed: %s"]):format(err or "?"), true) end
		end,
	})
end

---------------------------------------------------------------------------
-- Character window: a small "BiS" button (only with the Character window
-- element's Improve switch; our own button, Blizzard's window unchanged)
---------------------------------------------------------------------------
local charButton
function LG:AttachCharacterButton()
	if charButton or not E:BlizzardAllowed("character-frame", "improve") then return end
	local frame = rawget(_G, "CharacterFrame")
	if not frame then return end
	charButton = Kit.Button(frame, L["BiS"], 44, 18, function()
		if InCombatLockdown() then return end
		LG:Open("bis")
	end, L["Best in Slot"], L["Opens the Loot Guide's Best in Slot page."])
	charButton:SetFrameLevel(frame:GetFrameLevel() + 10)
	charButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, -4)
end

LG:Listen("PLAYER_ENTERING_WORLD", "bis-charbutton", function()
	if LG:IsPageOn("bis") then LG:AttachCharacterButton() end
end)

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------
local function Run(arg)
	local word = (arg or ""):lower():match("^(%S+)")
	if word == "1" or word == "2" then
		State().view = "set" .. word
		LG:Open("bis")
		return true
	elseif word == "wish" or word == "wishlist" then
		State().view = "wish"
		LG:Open("bis")
		return true
	elseif word == "export" then
		LG:ShowBiSExport()
		return true
	end
	return false
end

LG:RegisterPage("bis", {
	title = "Best in Slot",
	desc = "The best gear you can get for your spec and level, your filter and stat order, and two plan sets of your own.",
	order = 40,
	command = "bis",
	usage = Key("open Best in Slot; 1 | 2 (a plan set) | wish | export"),
	create = Create,
	show = function(page)
		Draw(page)
	end,
	hide = function(page)
		page.flyout:Hide()
		page.filter:Hide()
	end,
	refresh = function(page, changed)
		if changed.rank or changed.list or changed.spec or changed.gear or changed.sets or changed.wishlist or changed.settings
			or changed.data or changed.items or changed.player or changed.sim then
			Draw(page)
		end
	end,
	run = Run,
})
