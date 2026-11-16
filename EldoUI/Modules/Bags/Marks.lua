-- EldoUI Bags, part five: slot marks. Each is its own switch on the
-- Slots tab, and each only changes how a live slot looks.
--
--   Can't use      a red icon on items this character can't use yet, read
--                  from the red lines of the game's own tooltip data for
--                  the item (level, skill, class, armor or weapon type).
--                  Read once per item and kept until the character levels
--                  up or learns something.
--   Set items      a small mark in the bottom corner on items in one of the
--                  game's equipment sets.
--   Fade           with a vendor, the Send Mail tab, the auction house or
--                  the socket window open, the items it can't take fade
--                  like a search miss.
--   Alt-click      every slot with the same item flashes in the open bag
--                  and bank windows. Alt-click on a bag item does nothing
--                  else in the game; the Mail module's Alt-click attach
--                  keeps the click while Send Mail is open.
--
-- Nothing is used, moved or hidden. Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local M = E:GetModule("Bags")
if not M then return end

local ITEM_CLASS = Enum.ItemClass or {}
local GEAR = { [ITEM_CLASS.Weapon or 2] = true, [ITEM_CLASS.Armor or 4] = true }
-- Kinds of items whose tooltip can say "you can't use this".
local READ = { [ITEM_CLASS.Consumable or 0] = true, [ITEM_CLASS.Weapon or 2] = true, [ITEM_CLASS.Armor or 4] = true,
	[ITEM_CLASS.Projectile or 6] = true, [ITEM_CLASS.Recipe or 9] = true }
local GEM = ITEM_CLASS.Gem or 3
local FADE_ALPHA = 0.2
local FLASH_TIME = 1.5
local UNUSABLE_TINT = { 0.95, 0.3, 0.3 }

local function Visible(frame)
	return frame ~= nil and frame.IsVisible and frame:IsVisible() and true or false
end

local function ClassOf(record)
	if not record.id then return nil end
	return select(6, C_Item.GetItemInfoInstant(record.id))
end

---------------------------------------------------------------------------
-- Loot trade time
---------------------------------------------------------------------------
local TRADE_CLASSES = { [ITEM_CLASS.Armor or 4] = true, [ITEM_CLASS.Weapon or 2] = true, [ITEM_CLASS.Recipe or 9] = true }
local TRADE_TIME = Enum.TooltipDataLineType and Enum.TooltipDataLineType.TradeTimeRemaining
local UNCOMMON = Enum.ItemQuality and Enum.ItemQuality.Uncommon or 2
local TRADE_FORMS = {
	{ 3600, "INT_SPELL_DURATION_HOURS", "D_HOURS", "HOURS_ABBR" },
	{ 60, "INT_SPELL_DURATION_MIN", "D_MINUTES", "MINUTES_ABBR" },
	{ 1, "INT_SPELL_DURATION_SEC", "D_SECONDS", "SECONDS_ABBR" },
}
local TRADE_CACHE_MAX = 2048
local tradeCache, tradeOrder = {}, {}
local tradeMarks = setmetatable({}, { __mode = "k" })
local tradeClocks = setmetatable({}, { __mode = "k" })
local tradeTimer, tradeTickAt
local durationPatterns = {}

local function DurationPatterns(format)
	local existing = durationPatterns[format]
	if existing then return existing end
	local patterns = {}
	local prefix, singular, plural, suffix = format:match("^(.-)|4([^:;]+):([^;]+);(.*)$")
	local versions = prefix and { prefix .. singular .. suffix, prefix .. plural .. suffix } or { format }
	for _, version in ipairs(versions) do
		local spec = E.ChatParse:BuildPattern(version)
		if spec and #spec.order == 1 then patterns[#patterns + 1] = spec.pattern:sub(2, -2) end
	end
	durationPatterns[format] = patterns
	return patterns
end

local function DurationUnit(text, group)
	for index = 2, #group do
		local format = E.Plain(rawget(_G, group[index]))
		if type(format) == "string" then
			for _, pattern in ipairs(DurationPatterns(format)) do
				local amount = tonumber(text:match(pattern))
				if amount and amount >= 0 then return amount * group[1] end
			end
		end
	end
	return 0
end

local function CanReadTable(value)
	return type(value) == "table" and not E.Secret(value) and (not canaccesstable or canaccesstable(value))
end

local function TradeTime(bag, slot)
	local format = E.Plain(_G.BIND_TRADE_TIME_REMAINING)
	if type(format) ~= "string" then return end
	local data = E.PlainCall(C_TooltipInfo and C_TooltipInfo.GetBagItem, bag, slot)
	local lines = CanReadTable(data) and data.lines
	if not CanReadTable(lines) or #lines == 0 then return end
	local complete = true
	for _, line in ipairs(lines) do
		if not CanReadTable(line) then
			complete = false
		else
			local text = E.Plain(line.leftText)
			if type(text) == "string" then text = text:gsub("^|c%x%x%x%x%x%x%x%x(.-)|r$", "%1") end
			local args = E.ChatParse:MatchFormat(text, format)
			local duration = args and args[1]
			if duration then
				local seconds = 0
				for _, group in ipairs(TRADE_FORMS) do seconds = seconds + DurationUnit(duration, group) end
				if seconds > 0 and seconds <= 7200 then return seconds end
				return
			end
			if E.Secret(line.leftText) or E.Secret(line.type) or (TRADE_TIME and line.type == TRADE_TIME) then complete = false end
		end
	end
	if complete then return false end
end

function M:TradeItemGUID(record)
	local bound, quality, bag, slot = record.bound, record.quality, record.bag, record.slot
	local item = E.Plain(record.link) or E.Plain(record.short)
	if E.Secret(bound) or bound ~= true or E.Secret(quality) or type(quality) ~= "number" or quality < UNCOMMON
		or E.Secret(bag) or type(bag) ~= "number" or E.Secret(slot) or type(slot) ~= "number"
		or type(item) ~= "string" or not ItemLocation then return end
	local _, _, _, _, _, class = E.PlainCallAll(C_Item.GetItemInfoInstant, item)
	if not class or not TRADE_CLASSES[class] then return end
	local location = E.PlainCall(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot)
	local guid = location and E.PlainCall(C_Item.GetItemGUID, location)
	if type(guid) == "string" and guid ~= "" then return guid end
end

local function TradeDeadline(record, now)
	local guid = record.tradeGUID
	if not guid then return end
	local cached = tradeCache[guid]
	if cached ~= nil then return cached or nil end
	local seconds = TradeTime(record.bag, record.slot)
	if seconds == nil then return end
	local deadline = seconds and now + seconds or false
	tradeCache[guid] = deadline
	tradeOrder[#tradeOrder + 1] = guid
	if #tradeOrder > TRADE_CACHE_MAX then tradeCache[table.remove(tradeOrder, 1)] = nil end
	return deadline or nil
end

local function PaintTradeTime(text, row, remaining)
	local minutes = math.ceil(remaining / 60)
	row.label = L["Trade %dm"]:format(minutes)
	text:SetText(row.label)
	local width = E.PlainCall(row.owner.GetWidth, row.owner)
	local drawn = E.PlainCall(text.GetStringWidth, text)
	local clock = tradeClocks[text]
	if type(width) == "number" and width > 0 and type(drawn) == "number" and drawn > width - 4 then
		row.label = L["%dm"]:format(minutes)
		text:SetText(row.label)
		if not clock and not InCombatLockdown() then
			local parent = text:GetParent()
			clock = parent:CreateTexture(nil, "OVERLAY")
			clock:SetSize(7, 7)
			clock:SetPoint("BOTTOMLEFT", 1, 1)
			clock:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
			E:TrimIcon(clock)
			tradeClocks[text] = clock
		end
		if clock then clock:Show() end
	elseif clock then
		clock:Hide()
	end
	if not InCombatLockdown() then
		text:ClearAllPoints()
		text:SetPoint("BOTTOMLEFT", clock and clock:IsShown() and 9 or 2, 2)
	end
end

local function ForgetTradeMark(text)
	local clock = tradeClocks[text]
	if clock and clock:IsShown() then
		clock:Hide()
		if not InCombatLockdown() then
			text:ClearAllPoints()
			text:SetPoint("BOTTOMLEFT", 2, 2)
		end
	end
	tradeMarks[text] = nil
end

local function ScheduleTradeMarks(firstDeadline)
	if not (C_Timer and C_Timer.NewTimer) then return end
	local now = E.PlainCall(GetServerTime)
	if type(now) ~= "number" then return end
	local nextTick
	if firstDeadline then
		local remaining = firstDeadline - now
		nextTick = remaining > 0 and ((remaining - 1) % 60 + 1) or 1
	else
		for _, row in pairs(tradeMarks) do
			local remaining = row.deadline - now
			local change = remaining > 0 and ((remaining - 1) % 60 + 1) or 1
			nextTick = math.min(nextTick or 60, change)
		end
	end
	if not nextTick then return end
	if tradeTimer then
		if tradeTickAt <= now + nextTick then return end
		tradeTimer:Cancel()
	end
	tradeTickAt = now + nextTick
	tradeTimer = C_Timer.NewTimer(nextTick, function()
		tradeTimer, tradeTickAt = nil, nil
		local current = E.PlainCall(GetServerTime)
		local locked = InCombatLockdown()
		for text, row in pairs(tradeMarks) do
			local visible = E.PlainCall(text.IsVisible, text) == true
			if not M.active or not M.db.tradeTime or not visible or type(current) ~= "number" or row.deadline <= current then
				text:SetText("")
				ForgetTradeMark(text)
			elseif not locked then
				PaintTradeTime(text, row, row.deadline - current)
			else
				local clock = tradeClocks[text]
				local format = clock and clock:IsShown() and L["%dm"] or L["Trade %dm"]
				row.label = format:format(math.ceil((row.deadline - current) / 60))
				text:SetText(row.label)
			end
		end
		ScheduleTradeMarks()
	end)
end

-- Use the same corner as the BoE and BoU labels. Only live bag slots
-- have access to a specific item's trade deadline.
function M:PaintTradeMark(owner, text, record)
	if not text then return end
	local previous = tradeMarks[text]
	ForgetTradeMark(text)
	if previous and not record then
		local oldText = E.PlainCall(text.GetText, text)
		if oldText == previous.label then text:SetText("") end
	end
	if not (self.db.tradeTime and record) then return end
	local now = E.PlainCall(GetServerTime)
	if type(now) ~= "number" then return end
	local deadline = TradeDeadline(record, now)
	if not deadline or deadline <= now then return end
	local row = { owner = owner, deadline = deadline }
	tradeMarks[text] = row
	PaintTradeTime(text, row, deadline - now)
	ScheduleTradeMarks(deadline)
end

function M:ClearTradeMarks()
	if tradeTimer then tradeTimer:Cancel() tradeTimer, tradeTickAt = nil, nil end
	for text in pairs(tradeMarks) do
		text:SetText("")
		ForgetTradeMark(text)
	end
end

---------------------------------------------------------------------------
-- Can't use
---------------------------------------------------------------------------
local unusable = {} -- item link -> true / false

local function Red(color)
	if type(color) ~= "table" then return false end
	local r, g, b = color.r, color.g, color.b
	if E:IsSecret(r) or E:IsSecret(g) or E:IsSecret(b) then return false end
	return type(r) == "number" and r > 0.95 and type(g) == "number" and g < 0.3 and type(b) == "number" and b < 0.3
end

-- True when the item's tooltip has a red line under its name. Tooltip data
-- the client has not loaded yet is read again on the next repaint.
function M:CannotUse(record)
	local key = record.link or record.short
	if not key or key == "" then return false end
	local known = unusable[key]
	if known ~= nil then return known end
	if not READ[ClassOf(record)] then
		unusable[key] = false
		return false
	end
	if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then return false end
	local ok, data = pcall(C_TooltipInfo.GetBagItem, record.bag, record.slot)
	if not ok or type(data) ~= "table" or type(data.lines) ~= "table" or #data.lines == 0 then return false end
	local red = false
	for index = 2, #data.lines do
		local line = data.lines[index]
		if type(line) == "table" and (Red(line.leftColor) or Red(line.rightColor)) then
			red = true
			break
		end
	end
	unusable[key] = red
	return red
end

function M:ForgetUsable()
	wipe(unusable)
end

---------------------------------------------------------------------------
-- Fade
---------------------------------------------------------------------------
-- The open window that takes items, when it takes only some.
function M:FadeTarget()
	if Visible(rawget(_G, "ItemSocketingFrame")) then return "socket" end
	if Visible(rawget(_G, "AuctionHouseFrame")) then return "auction" end
	local target = self:MoveTarget()
	if target == "vendor" or target == "mail" then return target end
end

function M:CannotTake(target, record)
	if target == "vendor" then
		local price = select(11, C_Item.GetItemInfo(record.link or record.short))
		return price == 0
	elseif target == "mail" then
		return record.bound == true
	elseif target == "auction" then
		if not (C_AuctionHouse and C_AuctionHouse.IsSellItemValid and ItemLocation) then return false end
		local ok, valid = pcall(C_AuctionHouse.IsSellItemValid, ItemLocation:CreateFromBagAndSlot(record.bag, record.slot), false)
		return ok and valid == false
	elseif target == "socket" then
		return ClassOf(record) ~= GEM
	end
	return false
end

---------------------------------------------------------------------------
-- Pet food
---------------------------------------------------------------------------
local petFoods, petIdentity, petFoodCount = {}, nil, 0

local function Hunter()
	local _, class = E.PlainCallAll(UnitClass, "player")
	return class == "HUNTER"
end

function M:ForgetPetFood()
	wipe(petFoods)
	petIdentity, petFoodCount = nil, 0
end

function M:PetCanEat(itemID)
	itemID = E.Plain(itemID)
	if not (self.active and self.db.markPetFood and Hunter() and E.PlainCall(UnitExists, "pet") == true) then return false end
	local guid = E.PlainCall(UnitGUID, "pet")
	if type(guid) ~= "string" or guid == "" or type(itemID) ~= "number" or itemID ~= itemID
		or itemID <= 0 or itemID == math.huge or itemID ~= math.floor(itemID) then return false end
	if petIdentity ~= guid then self:ForgetPetFood(); petIdentity = guid end
	local known = petFoods[itemID]
	if known ~= nil then return known end
	local answer = E.PlainCall(C_PetInfo and C_PetInfo.CanPetEatItem, itemID)
	if type(answer) ~= "boolean" then return false end
	if petFoodCount >= 512 then self:ForgetPetFood(); petIdentity = guid end
	petFoods[itemID], petFoodCount = answer, petFoodCount + 1
	return answer
end

local function FoodMark(button)
	if button.eldoFoodMark then return button.eldoFoodMark end
	local mark = button:CreateTexture(nil, "OVERLAY", nil, 2)
	mark:SetSize(M:MarkSize(), M:MarkSize())
	mark:SetPoint("CENTER", 0, 0)
	-- Feed Pet's native artwork identifies the same food check.
	local texture = E.PlainCall(C_Spell and C_Spell.GetSpellTexture, 6991)
	mark:SetTexture(texture or 132165)
	mark:Hide()
	button.eldoFoodMark = mark
	return mark
end

---------------------------------------------------------------------------
-- Painting
---------------------------------------------------------------------------
local function SetMark(button)
	local mark = button.eldoSetMark
	if mark then return mark end
	mark = button:CreateTexture(nil, "OVERLAY", nil, 2)
	mark:SetSize(M:MarkSize(), M:MarkSize())
	mark:SetPoint("BOTTOMRIGHT", -2, 2)
	E.UIKit.SetGlyph(mark, "profile")
	mark:Hide()
	button.eldoSetMark = mark
	return mark
end

-- After a slot is painted (Core.lua PaintLive and PaintOffline). Offline
-- slots and other characters' items show no marks: they are about what
-- this character can use and what is open now.
-- known: the caller's answer from E:IsItemKnown, when it has one.
function M:PaintMarks(window, button, record, offline, known)
	local db = self.db
	local live = not offline and not record.empty and window.viewChar == E.charKey
	self:PaintTradeMark(button, button.bind, live and window.kind == "bags" and record or nil)
	local inSet = false
	if live and db.markSets and GEAR[ClassOf(record)] and C_Container.GetContainerItemEquipmentSetInfo then
		inSet = C_Container.GetContainerItemEquipmentSetInfo(record.bag, record.slot) and true or false
	end
	if inSet or button.eldoSetMark then
		local mark = SetMark(button)
		mark:SetVertexColor(E.UIKit.Accent())
		mark:SetShown(inSet)
	end
	local food = live and self:PetCanEat(record.id)
	if food or button.eldoFoodMark then FoodMark(button):SetShown(food and true or false) end
	button.eldoUnusable = nil
	if not live then return end
	local icon = button.icon or button.Icon
	if known == nil then known = db.knownTint and E.IsItemKnown and E:IsItemKnown(record.link or record.short) end
	if db.markUnusable and icon and not known and self:CannotUse(record) then
		icon:SetVertexColor(unpack(UNUSABLE_TINT))
		button.eldoUnusable = true
	end
	self:MarkFade(button, record)
end

-- Items the open mail, trade or merchant can't take fade further. Called
-- for this character's live slots only.
function M:MarkFade(button, record)
	if record.empty or not self.db.markFade or button:GetAlpha() <= FADE_ALPHA then return end
	local target = self:FadeTarget()
	if target and self:CannotTake(target, record) then button:SetAlpha(FADE_ALPHA) end
end

---------------------------------------------------------------------------
-- Values of physical stacks and the least valuable eligible carried stack.
---------------------------------------------------------------------------
local poor = Enum.ItemQuality.Poor
local lowest, lowestButton
local lowestEvents = {}
local waitingPrices = {}
local lowestGeneration = 0

local function WholeNumber(value, minimum)
	return type(value) == "number" and value >= minimum and value < math.huge and value % 1 == 0
end

local function ReadableTable(value)
	return not E.Secret(value) and type(value) == "table" and (not canaccesstable or canaccesstable(value))
end

local function Stack(info)
	if not ReadableTable(info) then return end
	local id, link, count, quality = E.Plain(info.itemID), E.Plain(info.hyperlink), E.Plain(info.stackCount), E.Plain(info.quality)
	if not (WholeNumber(id, 1) and type(link) == "string" and link ~= "" and WholeNumber(count, 1)) then return end
	return id, link, count, quality
end

local function ItemValue(link)
	local name, _, quality, _, _, _, _, _, _, _, price, classID = E.PlainCallEach(C_Item.GetItemInfo, link)
	return name, WholeNumber(price, 0) and price or nil, classID, quality
end

local function NotReturnable(bag, slot)
	local read = C_Container.GetContainerItemPurchaseInfo
	if type(read) ~= "function" then return false end
	local ok, info = pcall(read, bag, slot, false)
	if not ok or E.Secret(info) then return false end
	if info == nil then return true end
	if not ReadableTable(info) then return false end
	local seconds = E.Plain(info.refundSeconds)
	return type(seconds) == "number" and seconds > -math.huge and seconds <= 0
end

local function CanSuggest(id, name, classID, bag, slot, merchant)
	if classID == ITEM_CLASS.Questitem then return false end
	local quest = E.PlainCall(C_Container.GetContainerItemQuestInfo, bag, slot)
	if not ReadableTable(quest) or E.Plain(quest.isQuestItem) ~= false or E.Secret(quest.questID)
		or (quest.questID ~= nil and quest.questID ~= 0) then return false end
	if E.PlainCall(C_Container.GetContainerItemEquipmentSetInfo, bag, slot) ~= false or not NotReturnable(bag, slot) then return false end
	if not E.ItemProtection then return false end
	local ok, reason = pcall(E.ItemProtection, E, id, bag, slot)
	if not ok or E.Secret(reason) or reason ~= nil then return false end
	if classID == ITEM_CLASS.Recipe then
		local chars = E.modules.Characters
		if not (chars and chars.active and E.PlainCall(chars.RecipeStatus, chars, id) == "known") then return false end
	end
	if merchant and merchant.db and E.PlainCall(merchant.NeverSell, merchant, id, name) ~= false then return false end
	return true
end

local function StackStillThere(item)
	local info = E.PlainCall(C_Container.GetContainerItemInfo, item.bag, item.slot)
	local id, link, count, quality = Stack(info)
	return id == item.id and link == item.link and count == item.count and quality == item.quality
		and E.Plain(info.isLocked) == false
end

local function ClearLowestMark()
	if lowestButton then
		lowestButton.eldoLowestValue:Hide()
		lowestButton = nil
	end
end

function M:ResetLowestValue()
	lowestGeneration = lowestGeneration + 1
	wipe(waitingPrices)
	lowest = nil
	ClearLowestMark()
end

function M:LowestValueItem()
	local owner, db = E.Plain(E.charKey), self.db
	if type(owner) ~= "string" or not db then return end
	local cache = E.BagCache
	local generation, revision = lowestGeneration, cache:Revision()
	local merchant = E.modules.Merchant
	local merchantDB = merchant and merchant.db
	local keep = merchantDB and E.Plain(merchantDB.keepList)
	if merchantDB and type(keep) ~= "string" then return end
	local function Current()
		return self.db == db and E.Plain(E.charKey) == owner and (merchant and merchant.db) == merchantDB
			and (merchantDB and E.Plain(merchantDB.keepList)) == keep
			and lowestGeneration == generation and cache:Revision() == revision
	end
	local free, _, known, rows = cache:GeneralSlots(cache:BagIDs(), false, true)
	if not known or free > self.LOW_SPACE or not Current() then return end
	local cached = lowest
	if cached and cached.owner == owner and cached.db == db and cached.keep == keep and cached.free == free and cached.revision == revision then
		local item = cached.item
		if not item or StackStillThere(item) then return Current() and item or nil end
		if not Current() then return end
	end
	local snapshot = { owner = owner, db = db, keep = keep, free = free, revision = revision }
	local item
	for _, row in ipairs(rows) do
		local bag = row.bag
		if not row.special and row.free < row.total then
			for slot = 1, row.total do
				local info = cache:Info(bag, slot)
				local id, link, count, quality = Stack(info)
				if id and WholeNumber(quality, 0) and E.Plain(info.isLocked) == false then
					local name, price, classID = ItemValue(link)
					if not (type(name) == "string" and price and WholeNumber(classID, 0)) then waitingPrices[id] = true end
					local value, gray = price and price * count, quality == poor
					if type(name) == "string" and name ~= "" and WholeNumber(classID, 0) and WholeNumber(value, 0)
						and (not item or gray and not item.gray or gray == item.gray and value < item.value)
						and CanSuggest(id, name, classID, bag, slot, merchant) then
						item = { id = id, link = link, name = name, count = count, quality = quality,
							bag = bag, slot = slot, value = value, gray = gray }
					end
				end
			end
		end
	end
	if item and not StackStillThere(item) then return end
	if not Current() then return end
	snapshot.item = item
	lowest = snapshot
	return item
end

function M:RefreshLowestValueMark(window)
	if window.kind ~= "bags" then return end
	ClearLowestMark()
	if not (self.active and self.db.lowestValueMark and self:OwnBags() and window:IsVisible() and self.IsLive(window)) then return end
	local item = self:LowestValueItem()
	local holder = item and window.holders[item.bag]
	local button = holder and holder.buttons[item.slot]
	local record = button and button.eldoRecord
	if not (record and button:IsVisible() and not record.empty and not record.stacks and E.Plain(record.link) == item.link
		and E.Plain(record.id) == item.id and E.Plain(record.count) == item.count) then return end
	local mark = button.eldoLowestValue
	if not mark then
		mark = button:CreateTexture(nil, "OVERLAY", nil, 3)
		E.UIKit.SetGlyph(mark, "chevron-down")
		mark:SetPoint("LEFT", button, "LEFT", 1, 0)
		button.eldoLowestValue = mark
	end
	local size = self:MarkSize()
	mark:SetSize(size, size)
	mark:SetVertexColor(E:TokenColor("warn"))
	mark:Show()
	lowestButton = button
end

function M:LowestValueSlotTip(button)
	if button ~= lowestButton or not GameTooltip:IsOwned(button) then return end
	local item = self:LowestValueItem()
	if item and lowestButton == button then
		E.UIKit.TipText(GameTooltip, L["Lowest value in your bags: %s (%s)"]:format(item.name, self.Money(item.value)))
		GameTooltip:Show()
	end
end

local function InvalidateLowest()
	M:ResetLowestValue()
end

for _, event in ipairs({ "BAG_UPDATE", "BAG_CONTAINER_UPDATE", "PLAYER_ENTERING_WORLD" }) do
	E:RegisterEvent(event, InvalidateLowest, lowestEvents)
end

local function QueueLowestMark()
	local window = M.windows.bags
	if M.active and M.db.lowestValueMark and window and window:IsVisible() then
		E:Debounce("Bags:lowest", 0.08, function() M:RefreshLowestValueMark(window) end)
	end
end

local function ReconsiderLowest()
	M:ResetLowestValue()
	QueueLowestMark()
end

for _, event in ipairs({ "ITEM_LOCK_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED",
	"QUEST_TURNED_IN", "EQUIPMENT_SETS_CHANGED", "SKILL_LINES_CHANGED" }) do
	E:RegisterEvent(event, ReconsiderLowest, lowestEvents)
end
E:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(_, _, itemID)
	itemID = E.Plain(itemID)
	if itemID and waitingPrices[itemID] then ReconsiderLowest() end
end, lowestEvents)
E.BagCache:RegisterCallback(lowestEvents, QueueLowestMark)

local function WorthKind(classID, quality)
	if quality == poor then return "Junk" end
	if not WholeNumber(classID, 0) then return "Other" end
	if classID == ITEM_CLASS.Tradegoods or classID == ITEM_CLASS.Reagent or classID == ITEM_CLASS.Gem
		or classID == ITEM_CLASS.ItemEnhancement then return "Trade goods" end
	if classID == ITEM_CLASS.Weapon or classID == ITEM_CLASS.Armor then return "Gear" end
	return "Other"
end

function M:BagWorth(window)
	local live = M.IsLive(window)
	local capacity = window.slotCapacity
	local groups = { Junk = {}, ["Trade goods"] = {}, Gear = {}, Other = {} }
	local market = live and E.modules.Auction
	local names, totals = {}, { vendor = 0, auction = 0, vendorCount = 0, auctionCount = 0, stacks = 0 }
	local function Add(link, count, id, quality)
		totals.stacks = totals.stacks + 1
		if type(link) ~= "string" or link == "" or not WholeNumber(count, 1) then return end
		local values = names[link]
		if not values then
			local _, price, classID, itemQuality = ItemValue(link)
			local auction = market and E.PlainCall(market.GetUsualPrice, market, link, id)
			values = { vendor = price, auction = WholeNumber(auction, 0) and auction or nil,
				kind = WorthKind(classID, quality or itemQuality) }
			names[link] = values
		end
		local group = groups[values.kind]
		for _, key in ipairs({ "vendor", "auction" }) do
			local amount = values[key] and values[key] * count
			if WholeNumber(amount, 0) then
				group[key] = (group[key] or 0) + amount
				totals[key] = totals[key] + amount
				totals[key .. "Count"] = totals[key .. "Count"] + 1
			end
		end
	end
	if live then
		local cache = E.BagCache
		local rows = capacity and capacity.rows
		totals.incomplete = not rows
		for _, row in ipairs(rows or {}) do
			local occupied = 0
			for slot = 1, row.total or 0 do
				local info = cache:Info(row.bag, slot)
				local id, link, count, quality = Stack(info)
				if info then
					occupied = occupied + 1
					Add(link, count, id, quality)
				end
			end
			if not row.total or not row.free or occupied ~= row.total - row.free then totals.incomplete = true end
		end
	else
		for _, packed in ipairs(self.store:View(window.viewChar, window.kind)) do
			if type(packed) == "string" then
				local link, count = packed:match("^(.-);(%d+)$")
				link = link or packed
				Add(link, tonumber(count) or 1)
			end
		end
	end
	return groups, totals, live
end

function M:AddWorthLines(tooltip, window)
	local groups, totals, live = self:BagWorth(window)
	if totals.stacks == 0 and not totals.incomplete then return end
	local function Price(value)
		return value and self.Money(value) or L["No known price"]
	end
	tooltip:AddLine(" ")
	E.UIKit.TipTitle(tooltip, live and L["Inventory value"] or L["Saved inventory vendor value"])
	local columns = live and (L["Vendor value"] .. "  /  " .. L["Usual auction prices"]) or L["Vendor value"]
	E.UIKit.TipText(tooltip, columns)
	for _, key in ipairs({ "Junk", "Trade goods", "Gear", "Other" }) do
		local group = groups[key]
		if group.vendor ~= nil or group.auction ~= nil then
			local value = Price(group.vendor)
			if live then value = value .. "  /  " .. Price(group.auction) end
			tooltip:AddDoubleLine(L[key], value)
		end
	end
	local vendor = Price(totals.vendorCount > 0 and totals.vendor or nil)
	if live then vendor = vendor .. "  /  " .. Price(totals.auctionCount > 0 and totals.auction or nil) end
	tooltip:AddDoubleLine(L["Total"], vendor)
	if totals.incomplete or totals.vendorCount < totals.stacks or live and totals.auctionCount < totals.stacks then
		E.UIKit.TipText(tooltip, L["Totals include known prices only."])
	end
	local item = live and window.kind == "bags" and self:LowestValueItem()
	if item then
		E.UIKit.TipText(tooltip, L["Lowest value in your bags: %s (%s)"]:format(item.name, self.Money(item.value)))
	end
end

---------------------------------------------------------------------------
-- Alt-click flash
---------------------------------------------------------------------------
local function Flash(button)
	local glow = button.eldoFlash
	if not glow then
		glow = button:CreateTexture(nil, "OVERLAY", nil, 3)
		glow:SetAllPoints()
		glow:SetColorTexture(1, 1, 1, 1)
		glow:SetBlendMode("ADD")
		glow:SetAlpha(0)
		local anim = glow:CreateAnimationGroup()
		local fade = anim:CreateAnimation("Alpha")
		fade:SetFromAlpha(0.55)
		fade:SetToAlpha(0)
		fade:SetDuration(FLASH_TIME / 3)
		anim:SetLooping("REPEAT")
		glow.anim = anim
		button.eldoFlash = glow
	end
	glow:SetVertexColor(E.UIKit.Accent())
	glow.anim:Stop()
	-- With motion reduced the slot holds a steady highlight instead.
	if E:MotionOn() then glow.anim:Play() else glow:SetAlpha(0.4) end
	button.eldoFlashedAt = GetTime() -- when it last flashed
	local at = button.eldoFlashedAt
	C_Timer.After(FLASH_TIME, function()
		if button.eldoFlashedAt ~= at then return end
		glow.anim:Stop()
		glow:SetAlpha(0)
	end)
end

-- Flashes every shown slot with the item of `record`. Returns how many.
function M:FlashSame(record)
	if not (record and not record.empty and record.id) then return 0 end
	local count = 0
	for _, window in pairs(self.windows or {}) do
		if window:IsShown() and window.viewChar == E.charKey then
			for _, holder in pairs(window.holders or {}) do
				for _, button in pairs(holder.buttons or {}) do
					local other = button.eldoRecord
					if button:IsShown() and other and not other.empty and other.id == record.id then
						Flash(button)
						count = count + 1
					end
				end
			end
		end
	end
	return count
end

-- The slot's own OnClick ran first; Alt + left click is otherwise unused.
function M:AltFlash(button, mouse)
	if mouse ~= "LeftButton" or not IsAltKeyDown() or not self.db.flashSame then return end
	local mail = E.modules.Mail
	if mail and mail.active and mail.db and mail.db.altClick and mail.AttachFromBag and Visible(rawget(_G, "SendMailFrame")) then return end
	self:FlashSame(button.eldoRecord)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- A window that takes items opened or closed: repaint when the fade changes.
hooksecurefunc(M, "UpdateMoveButton", function(self, window)
	if not (window and window:IsShown() and self.db.markFade) then return end
	local target = self:FadeTarget() or false
	if window.fadeTarget == nil then window.fadeTarget = target end
	if target ~= window.fadeTarget then
		window.fadeTarget = target
		self:UpdateWindow(window)
	end
end)

local function Valid(event)
	return not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event)
end

hooksecurefunc(M, "OnEnable", function(self)
	self:ForgetPetFood()
	if Hunter() then
		local function PetChanged()
			self:ForgetPetFood()
			self:RefreshViews()
		end
		self:RegisterUnitEvent("UNIT_PET", "player", PetChanged)
		self:RegisterEvent("PLAYER_ENTERING_WORLD", PetChanged)
	end
	local function Repaint()
		C_Timer.After(0, function()
			if self.active and self.windows then self:UpdateMoveButton(self.windows.bags) end
		end)
	end
	for _, event in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "SOCKET_INFO_UPDATE", "SOCKET_INFO_CLOSE" }) do
		if Valid(event) then self:RegisterEvent(event, Repaint) end
	end
	local function Learned()
		self:ForgetUsable()
		self:RefreshViews()
	end
	for _, event in ipairs({ "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE" }) do
		if Valid(event) then self:RegisterEvent(event, Learned) end
	end
	if Valid("EQUIPMENT_SETS_CHANGED") then
		self:RegisterEvent("EQUIPMENT_SETS_CHANGED", function() self:RefreshViews() end)
	end
end)

hooksecurefunc(M, "OnDisable", function(self) self:ForgetPetFood() end)
