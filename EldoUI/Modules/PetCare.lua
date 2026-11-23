-- EldoUI Pet Care (hunters on WoW: Forever): a Feed Pet button next to the
-- pet frame, plus warnings when the pet gets unhappy or its food runs low.
--
-- The button is a secure macro button the player clicks: one click casts
-- Feed Pet on one piece of food, nothing happens on its own. The food is
-- either the item the player dropped on the button, or (Auto) the lowest
-- level food in the bags that the pet eats and that still pleases it. The
-- choice is made out of combat only; in combat the button keeps its food.
-- Happiness, loyalty and food checks use Blizzard's pet API
-- (C_PetInfo.GetPetHappiness, C_PetInfo.CanPetEatItem).
local _, E = ...
local L = E.L

local FEED_PET = 6991
local LOW_FOOD = 5
local issecret = issecretvalue or function() return false end

local M = E:NewModule("PetCare", {
	title = "Pet Care",
	desc = "Hunters: Feed Pet button next to the pet frame, unhappy pet and low food warnings.",
	conflicts = { "BlackthornesPets" },
	defaults = {
		feedButton = true,
		size = 28,
		auto = true,           -- pick the food from the bags
		foodItem = 0,          -- item dropped on the button (used when auto is off, or as first choice)
		showCount = true,
		warnUnhappy = true,
		warnLowFood = true,
		sound = "kit:RAID_WARNING", -- media id ("none" for no sound) with the unhappy warning
	},
})

local function IsHunter()
	local _, class = UnitClass("player")
	return class == "HUNTER"
end

---------------------------------------------------------------------------
-- Food choice (out of combat)
---------------------------------------------------------------------------
local function CanEat(itemID)
	if not (C_PetInfo and C_PetInfo.CanPetEatItem) then return false end
	local ok, result = pcall(C_PetInfo.CanPetEatItem, itemID)
	return ok and not issecret(result) and result == true
end

local function ItemLevel(itemID)
	local ok, _, _, _, level = pcall(C_Item.GetItemInfo, itemID)
	if ok and type(level) == "number" then return level end
	return nil
end

-- Classic rule: food more than 30 levels below the pet makes it no happier.
local function Useful(itemID)
	local level = ItemLevel(itemID)
	local petLevel = UnitLevel("pet")
	if not level or issecret(petLevel) or type(petLevel) ~= "number" then return true end
	return level >= petLevel - 30
end

local function BagFoods()
	local foods, seen = {}, {}
	local bags = E.BagCache
	for _, bag in ipairs(bags:BagIDs()) do
		for slot = 1, bags:NumSlots(bag) do
			local itemID = bags:ItemID(bag, slot)
			if itemID and not seen[itemID] then
				seen[itemID] = true
				if CanEat(itemID) and Useful(itemID) then foods[#foods + 1] = itemID end
			end
		end
	end
	return foods
end

function M:ChooseFood()
	local db = self.db
	local picked = db.foodItem
	if picked and picked > 0 and C_Item.GetItemCount(picked) > 0 and (not UnitExists("pet") or CanEat(picked)) then
		return picked
	end
	if not db.auto then return (picked and picked > 0) and picked or nil end
	local best, bestLevel
	for _, itemID in ipairs(BagFoods()) do
		local level = ItemLevel(itemID) or 0
		if not best or level < bestLevel then best, bestLevel = itemID, level end
	end
	return best
end

---------------------------------------------------------------------------
-- Button
---------------------------------------------------------------------------
function M:UpdateButton()
	local button = self.button
	if not button or InCombatLockdown() then return end
	local food = self:ChooseFood()
	self.food = food
	local spell = C_Spell.GetSpellName and C_Spell.GetSpellName(FEED_PET)
	-- Left button only ("type1"): a right-click clears the choice in
	-- PostClick and must never feed. A plain "type" would answer
	-- every mouse button.
	button:SetAttribute("type", nil)
	if food and spell then
		button:SetAttribute("type1", "macro")
		button:SetAttribute("macrotext1", ("/cast %s\n/use item:%d"):format(spell, food))
	else
		button:SetAttribute("type1", nil)
		button:SetAttribute("macrotext1", nil)
	end
	button:SetAttribute("macrotext", nil)
	self:UpdateLook()
end

function M:UpdateLook()
	local button = self.button
	if not button then return end
	local food = self.food
	button.icon:SetTexture(food and C_Item.GetItemIconByID(food) or 132165)
	button.icon:SetDesaturated(not food)
	local count = food and C_Item.GetItemCount(food) or 0
	button.count:SetText((self.db.showCount and food) and count or "")
	-- Warn once each time the food runs low: a restock arms it again.
	if food and count >= LOW_FOOD and self.warnedFood == food then self.warnedFood = nil end
	if food and self.db.warnLowFood and count < LOW_FOOD and self.warnedFood ~= food then
		self.warnedFood = food
		M:PushAlert({ key = "eldoui-petfood", title = L["Pet Care"], icon = C_Item.GetItemIconByID(food) or 132165,
			text = L["Pet food is running low: %d left."]:format(count) })
	end
end

local function OnReceiveDrag(button)
	if InCombatLockdown() then return end
	local kind, itemID = GetCursorInfo()
	if kind ~= "item" or not itemID then return end
	ClearCursor()
	M.db.foodItem = itemID
	M.warnedFood = nil
	M:UpdateButton()
	if UnitExists("pet") and not CanEat(itemID) then
		M:PushAlert({ key = "eldoui-petfood", title = L["Pet Care"], icon = C_Item.GetItemIconByID(itemID) or 132165,
			text = L["Your pet does not eat that."] })
	end
end

local function OnEnter(button)
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	if M.food then
		GameTooltip:SetItemByID(M.food)
		GameTooltip:AddLine(" ")
	end
	E.UIKit.TipText(GameTooltip, L["Drop food on the button to choose it."])
	E:TooltipHint(GameTooltip, { L["Click"], L["feed your pet one piece of this food"] }, { L["Right-click"], L["clear your choice"] })
	GameTooltip:Show()
end

local function PostClick(_, mouse)
	if mouse == "RightButton" and not InCombatLockdown() then
		M.db.foodItem = 0
		M:UpdateButton()
	end
end

function M:Build()
	if self.button then return end
	local holder = CreateFrame("Frame", "EldoUI_PetFeedHolder", UIParent)
	holder:SetSize(self.db.size, self.db.size)
	self.holder = holder
	-- Next to EldoUI's pet frame when it exists, else near Blizzard's.
	local point = _G.EldoUI_PetMover and { "LEFT", "EldoUI_PetMover", "RIGHT", 34, 0 }
		or { "CENTER", "UIParent", "CENTER", -300, -330 }
	E:CreateMover(holder, "EldoUI_PetFeed", L["Feed Pet"], point)

	local button = CreateFrame("Button", "EldoUI_PetFeedButton", holder, "SecureActionButtonTemplate")
	button:SetAllPoints()
	-- Act on the release: with the game's "cast on key press" setting a
	-- secure button otherwise waits for a press it never receives.
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetAttribute("useOnKeyDown", false)
	E:SetTemplate(button)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	button.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(button.icon)
	button.count = E:CreateText(button, E.tokens.size.small, "RIGHT")
	button.count:SetPoint("BOTTOMRIGHT", -1, 2)
	E:SkinHudButton(button, button.icon)
	button:SetScript("OnReceiveDrag", OnReceiveDrag)
	button:SetScript("OnEnter", OnEnter)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetScript("PostClick", PostClick)
	self.button = button
end

-- The button shows while you have a living pet: the visibility engine
-- registers its state driver (Core/Visibility.lua).
local PET_RULE = E:VisibilityDefaults()
E:RegisterVisibilityFacet("EldoUI_PetFeed", "event", { module = "PetCare" })

function M:Layout()
	local db = self.db
	self.holder:SetSize(db.size, db.size)
	E:SetFont(self.button.count, math.max(math.floor(db.size * 0.4), 9))
	local show = db.feedButton and IsHunter()
	if show then
		E:AttachVisibility(self.button, PET_RULE, { secure = true, exempt = true, watch = false, module = "PetCare",
			condition = "[@pet,noexists][@pet,dead] hide" })
	else
		E:DetachVisibility(self.button)
		self.button:Hide()
	end
	self.holder:SetShown(show)
	self:UpdateButton()
end

---------------------------------------------------------------------------
-- Warnings
---------------------------------------------------------------------------
function M:CheckHappiness()
	if not self.db.warnUnhappy or not UnitExists("pet") then
		self.lastHappiness = nil
		return
	end
	local happiness = C_PetInfo and C_PetInfo.GetPetHappiness and C_PetInfo.GetPetHappiness()
	if issecret(happiness) or type(happiness) ~= "number" then return end
	local last = self.lastHappiness
	self.lastHappiness = happiness
	if last and happiness < last and happiness <= 2 then
		local text = L["Your pet is %s."]:format(string.lower(_G["PET_HAPPINESS" .. happiness] or L["unhappy"]))
		M:PushAlert({ key = "eldoui-pethappy", title = L["Pet Care"], text = text, icon = 132165 })
		E:PlayMedia(self.db.sound)
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, unit)
	if not M.active then return end
	if event == "UNIT_HAPPINESS" or (event == "UNIT_PET" and unit == "player") then
		M:CheckHappiness()
		if event == "UNIT_PET" then E:RunOutOfCombat(function() M:UpdateButton() end) end
	elseif event == "PLAYER_REGEN_ENABLED" then
		M:UpdateButton()
	elseif not InCombatLockdown() then
		M:UpdateButton()
	else
		M:UpdateLook()
	end
end)

-- The sound used to be a tick: on is the raid warning, off is none.
function M:Migrate()
	local db = self.db
	if db.sound == true then db.sound = "kit:RAID_WARNING" elseif db.sound == false then db.sound = "none" end
end

function M:OnInitialize()
	self:Migrate()
end

local EVENTS = { "UNIT_HAPPINESS", "UNIT_PET", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "UNIT_LEVEL" }

function M:OnEnable()
	if not IsHunter() then return end
	E:RunOutOfCombat(function()
		self:Build()
		for _, event in ipairs(EVENTS) do pcall(eventFrame.RegisterEvent, eventFrame, event) end
		self:Layout()
		self:CheckHappiness()
	end)
end

function M:OnDisable()
	eventFrame:UnregisterAllEvents()
	E:RunOutOfCombat(function()
		if self.button then
			E:DetachVisibility(self.button)
			self.button:Hide()
		end
		if self.holder then self.holder:Hide() end
	end)
end

function M:OnProfileChanged()
	self:Migrate()
	if self.active and self.button then
		E:RunOutOfCombat(function() self:Layout() end)
	end
end

M.options = {
	{ type = "description", label = "For hunters: a Feed Pet button by the pet frame; one click feeds one piece of food. The [pet:happiness] tag shows happiness." },
	{ type = "description", label = "A happy pet deals more damage and gains loyalty; an unhappy pet deals less and loses loyalty." },
	{ type = "header", label = "Feed button" },
	{ type = "toggle", key = "feedButton", label = "Feed Pet button", desc = "A button that casts Feed Pet on the chosen food." },
	{ type = "toggle", key = "auto", label = "Pick food from the bags", desc = "Without a food dropped on the button, use the lowest level food in your bags that your pet eats and still enjoys.", dependsOn = "feedButton" },
	{ type = "range", key = "size", label = "Size", min = 16, max = 48, step = 1, desc = "Size of the button.", dependsOn = "feedButton" },
	{ type = "toggle", key = "showCount", label = "Show food count", desc = "How many of the chosen food you carry.", dependsOn = "feedButton" },
	{ type = "execute", label = "Forget dropped food", desc = "Clear the food you dropped on the button (right-click on the button does the same).",
		func = function() M.db.foodItem = 0; if M.active then E:RunOutOfCombat(function() M:UpdateButton() end) end end, dependsOn = "feedButton" },
	{ type = "header", label = "Warnings" },
	{ type = "toggle", key = "warnUnhappy", label = "Unhappy pet warning", desc = "A message when your pet's happiness drops to content or unhappy." },
	{ type = "toggle", key = "warnLowFood", label = "Low food warning", desc = "A note when fewer than %d of the chosen food are left. It comes again after you restock.", descFill = LOW_FOOD },
	{ type = "media", key = "sound", label = "Warning sound", mediaKind = "sound", none = true, desc = "The sound that plays with the unhappy pet warning. None for silence.", dependsOn = "warnUnhappy" },
}

E:RegisterStyles("PetCare", {
	{ key = "Standard", title = "Standard", desc = "28 px button with food count, both warnings.",
		settings = { feedButton = true, size = 28, showCount = true, warnUnhappy = true, warnLowFood = true } },
	{ key = "Small", title = "Small", desc = "20 px button, no count.",
		settings = { feedButton = true, size = 20, showCount = false } },
	{ key = "Large", title = "Large", desc = "40 px button with food count.",
		settings = { feedButton = true, size = 40, showCount = true } },
	{ key = "WarningsOnly", title = "Warnings only", desc = "No button, just the unhappy and low food warnings.",
		settings = { feedButton = false, warnUnhappy = true, warnLowFood = true } },
	{ key = "Quiet", title = "Quiet", desc = "Button only, no warnings or sound.",
		settings = { feedButton = true, warnUnhappy = false, warnLowFood = false, sound = "none" } },
})
