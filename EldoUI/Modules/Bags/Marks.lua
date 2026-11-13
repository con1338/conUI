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
-- Painting
---------------------------------------------------------------------------
local function SetMark(button)
	local mark = button.eldoSetMark
	if mark then return mark end
	mark = button:CreateTexture(nil, "OVERLAY", nil, 2)
	mark:SetSize(11, 11)
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
	local inSet = false
	if live and db.markSets and GEAR[ClassOf(record)] and C_Container.GetContainerItemEquipmentSetInfo then
		inSet = C_Container.GetContainerItemEquipmentSetInfo(record.bag, record.slot) and true or false
	end
	if inSet or button.eldoSetMark then
		local mark = SetMark(button)
		mark:SetVertexColor(E.UIKit.Accent())
		mark:SetShown(inSet)
	end
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
	for _, event in ipairs({ "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_TAB" }) do
		if Valid(event) then self:RegisterEvent(event, Learned) end
	end
	if Valid("EQUIPMENT_SETS_CHANGED") then
		self:RegisterEvent("EQUIPMENT_SETS_CHANGED", function() self:RefreshViews() end)
	end
end)
