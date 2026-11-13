-- EldoUI Upgrades: shows when an item beats what you wear. A green arrow
-- with "+X%" in the tooltip's info area and on bag, merchant, loot-roll and
-- quest-reward icons; the best quest reward gets a green outline (or a coin
-- on the best-selling one when nothing is an upgrade); gear the game marks
-- in red (wrong armor type, level too high) gets a faint red tint in the
-- bags.
--
-- The numbers come from EldoUI's scoring engine (Core/ItemScore.lua,
-- E.ItemScore), which keeps the scales, gems and enchants settings and works
-- even while this module is off, so the Loot Guide and every other place
-- that rates items agree with these arrows. This module draws the arrows and
-- the tooltip line, and is where scales are edited, shared and pasted
-- (EldoUI's own text format and Pawn scale strings).
--
-- Arrows on Blizzard's own windows follow the Blizzard UI switches:
-- bags (bags-containers), merchant, roll frames (group-loot-rolls) and quest
-- rewards (quest-gossip-npc / world-map-quest-log) each need the element's
-- master switch and its Improve switch. EldoUI's own frames always get them.
--
-- Public API (other modules, e.g. Bags and Loot, call these on their own buttons):
--   E:GetItemUpgrade(itemLink) -> result or nil (nil while this module is off)
--       result = { score, base, delta, percent (nil when the slot is empty),
--                  upgrade = true/false, usable = true/false, scale = name,
--                  slot, rater, dps and bis when a rater gives them }
--       Same as E.ItemScore:Rate(itemLink).
--   E:SetUpgradeArrow(button, itemLink[, opts]) -> result or nil
--       draws or clears the arrow on `button` (its .icon/.Icon if present).
--       opts = { noTint = true, best = true, coin = true, kind = "bags" }
--   E:RegisterUpgradeRefresh(fn) (in Core/ItemScore.lua)
--       fn() runs whenever arrows should be redrawn (scale, gear or item
--       data changed), e.g. for EldoUI's roll bars.
local _, E = ...
local L = E.L

local IS = E.ItemScore

local M = E:NewModule("Upgrades", {
	title = "Upgrades",
	desc = "Upgrade arrows from a stat-weight scale: tooltips, bags, merchants, loot rolls and quest rewards.",
	conflicts = { "Pawn" },
	defaults = {
		tooltip = true,          -- the Upgrade row in the tooltip info area
		onlyUpgrades = true,     -- no row for items that are not upgrades (Shift shows the score anyway)
		border = true,           -- green tooltip border on upgrades
		display = "percent",     -- percent or score
		minPercent = 0,          -- smaller gains are not called upgrades
		icons = true,            -- arrows on bag, merchant and loot-roll icons
		tintUnusable = true,     -- red tint on bag items the game marks red
		questRewards = true,     -- arrows and best-choice outline on quest rewards
		questVendor = true,      -- coin on the best-selling reward when none is an upgrade
		showAllStats = false,    -- editor shows every stat, not only weighted ones
		renameTo = "",
		-- Scales, gems and enchants live in the engine (E.db.itemScore). The
		-- options reach them through two stand-in tables, `engine` and
		-- `current` (the active scale's weights), set up by EnsureProxies.
	},
})

-- The engine decides what counts as an upgrade with this module's threshold.
IS:SetThreshold(function() return M.db and M.db.minPercent or 0 end)

-- Ratings without a tooltip are kept per link until the engine's version
-- changes (gear, scales, talents, level, item data) or the engine asks
-- for a full redraw, so repainting a bag slot whose item did not change rates nothing
-- again. At most RATED_MAX links are kept.
local RATED_MAX = 2000
local rated, ratedCount, ratedVersion = {}, 0, nil
local function ForgetRatings()
	wipe(rated)
	ratedCount, ratedVersion = 0, IS.version
end
local function Evaluate(link, tooltip)
	if not link then return end
	if tooltip then return IS:Rate(link, nil, tooltip) end
	if ratedVersion ~= IS.version or ratedCount >= RATED_MAX then ForgetRatings() end
	local result = rated[link]
	if result == nil then
		result = IS:Rate(link) or false
		rated[link] = result
		ratedCount = ratedCount + 1
	end
	return result or nil
end

function E:GetItemUpgrade(link)
	if not M.active then return end
	local ok, result = pcall(Evaluate, link)
	if ok then return result end
end

---------------------------------------------------------------------------
-- Stand-in tables: the options page reads and writes plain paths in this
-- module's settings ("engine.gems", "current.Strength"); these tables pass
-- them on to the engine. They hold nothing themselves, so nothing is saved
-- twice, and they are taken out again at logout.
---------------------------------------------------------------------------
local ENGINE_FIELDS = {
	gems = { get = function() return IS:GetSetting("gems") end, set = function(value) IS:SetSetting("gems", value and true or false) end },
	enchants = { get = function() return IS:GetSetting("enchants") end, set = function(value) IS:SetSetting("enchants", value and true or false) end },
	activeScale = { get = function() return IS:ActiveScaleKey() end, set = function(value) IS:SelectScale(value) end },
	rating = { get = function() return IS:GetRating() end, set = function(value) IS:SetRating(value) end },
}

local engineProxy = setmetatable({}, {
	__index = function(_, key)
		local field = ENGINE_FIELDS[key]
		if field then return field.get() end
	end,
	__newindex = function(_, key, value)
		local field = ENGINE_FIELDS[key]
		if field then field.set(value) end
	end,
})

local weightsProxy = setmetatable({}, {
	__index = function(_, stat)
		return IS:ActiveScale().weights[stat]
	end,
	__newindex = function(_, stat, value)
		IS:SetWeight(IS:ActiveScaleKey(), stat, value)
	end,
})

-- Every settings table the stand-ins were put in this session (a profile
-- switch puts them in the new profile's table too).
local holders = setmetatable({}, { __mode = "k" })

local function EnsureProxies()
	local db = M.db
	if not db then return end
	holders[db] = true
	local raw = rawget(db, "engine")
	if raw ~= engineProxy then
		db.engine = engineProxy
		-- Plain values a share string or an older style wrote: pass them on.
		if type(raw) == "table" then
			for key, value in pairs(raw) do
				if ENGINE_FIELDS[key] then engineProxy[key] = value end
			end
		end
	end
	if rawget(db, "current") ~= weightsProxy then db.current = weightsProxy end
end

-- Option keys that go through the stand-ins (made sure they exist first).
local function EngineKey(path)
	return function()
		EnsureProxies()
		return path
	end
end

-- Logout: the stand-ins leave every profile they were put in, so only real
-- settings are saved.
local function DropProxies()
	for settings in pairs(holders) do
		if rawget(settings, "engine") == engineProxy then settings.engine = nil end
		if rawget(settings, "current") == weightsProxy then settings.current = nil end
	end
end

---------------------------------------------------------------------------
-- Look
---------------------------------------------------------------------------
local ARROW_ATLAS = "bags-greenarrow"
local function HasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function Green()
	local color = _G.GREEN_FONT_COLOR
	if color then return color.r, color.g, color.b end
	return 0.1, 1, 0.1
end

local function Hex(r, g, b)
	return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

-- The gain: "+12.4 DPS" from a rater that simulates, else percent or score.
local function GainText(result)
	local text
	if type(result.dps) == "number" then
		text = L["+%.1f DPS"]:format(result.dps)
	elseif M.db.display == "percent" and result.percent then
		text = ("+%.1f%%"):format(result.percent)
	else
		text = ("+%.1f"):format(result.delta or result.score or 0)
	end
	if result.bis then text = text .. " · " .. L["BiS"] end
	return text
end

local function ArrowMarkup()
	if HasAtlas(ARROW_ATLAS) and CreateAtlasMarkup then return CreateAtlasMarkup(ARROW_ATLAS, 12, 12) .. " " end
	return ""
end

---------------------------------------------------------------------------
-- Tooltip row (through the Tooltip module's info area)
---------------------------------------------------------------------------
local GREY = { 0.65, 0.65, 0.65 }

local function RaterTitle(key)
	for _, rater in ipairs(IS:Raters()) do
		if rater.key == key then return rater.title end
	end
	return key
end

local function UpgradeSection(tooltip, link, id, add, info)
	if not M.active or not M.db.tooltip then return end
	if not link and id then link = select(2, C_Item.GetItemInfo(id)) end
	local result = Evaluate(link, tooltip)
	if not result then return end
	local shift = info and info.shift or IsShiftKeyDown()
	local name = result.rater ~= "weights" and RaterTitle(result.rater) or result.scale or ""
	local scoreText = type(result.score) == "number" and ("%s %.1f"):format(name, result.score) or name
	-- On Shift: how much of the score comes from gems and the enchant.
	local parts = shift and link and IS:Parts(link, result.scaleKey)
	if parts and (parts.gems or parts.enchant) then
		local bits = {}
		if parts.gems then bits[#bits + 1] = L["gems %+.1f"]:format(parts.gems) end
		if parts.enchant then bits[#bits + 1] = L["enchant %+.1f"]:format(parts.enchant) end
		scoreText = scoreText .. Hex(GREY[1], GREY[2], GREY[3]) .. " (" .. table.concat(bits, ", ") .. ")|r"
	end
	if result.upgrade then
		local r, g, b = Green()
		add(ArrowMarkup() .. GainText(result), scoreText, r, g, b, GREY[1], GREY[2], GREY[3])
		if M.db.border and E.SetTooltipBorder then E:SetTooltipBorder(tooltip, r, g, b) end
	elseif result.bis then
		-- In a Best in Slot set but not better than what you wear (or worn).
		local r, g, b = Green()
		add(result.worn and L["Worn · BiS"] or L["BiS"], scoreText, r, g, b, GREY[1], GREY[2], GREY[3])
	elseif not M.db.onlyUpgrades or shift then
		local right = scoreText
		if result.base and not result.worn then
			right = right .. Hex(GREY[1], GREY[2], GREY[3]) .. " " .. L["(worn %.1f)"]:format(result.base) .. "|r"
		end
		local label = result.usable and (result.worn and L["Worn"] or L["Not an upgrade"]) or L["Not usable"]
		add(label, right, GREY[1], GREY[2], GREY[3], 1, 1, 1)
	end
end

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------
local overlays = setmetatable({}, { __mode = "k" }) -- button -> overlay frame
local overlayKind = setmetatable({}, { __mode = "k" }) -- button -> kind (which window it sits on)

-- Blizzard UI element each kind of Blizzard window belongs to. Arrows on
-- these need the element's Improve switch (Core/Blizzard.lua).
local KIND_ELEMENT = {
	bags = "bags-containers",
	merchant = "merchant",
	rolls = "group-loot-rolls",
	quest = "quest-gossip-npc",
	questlog = "world-map-quest-log",
}

local function KindAllowed(kind)
	local id = KIND_ELEMENT[kind]
	return not id or E:BlizzardAllowed(id, "improve")
end

local function IconRegion(button)
	local name = button.GetName and button:GetName()
	return button.icon or button.Icon or (name and (_G[name .. "IconTexture"] or _G[name .. "Icon"])) or button
end

local function Overlay(button)
	local overlay = overlays[button]
	if overlay then return overlay end
	overlay = CreateFrame("Frame", nil, button)
	overlay:SetAllPoints(IconRegion(button))
	overlay:SetFrameLevel(button:GetFrameLevel() + 3)

	overlay.tint = overlay:CreateTexture(nil, "ARTWORK")
	overlay.tint:SetAllPoints()
	overlay.tint:SetColorTexture(E:TokenColor("bad", 0.35))

	if HasAtlas(ARROW_ATLAS) then
		overlay.arrow = overlay:CreateTexture(nil, "OVERLAY")
		overlay.arrow:SetAtlas(ARROW_ATLAS)
		overlay.arrow:SetSize(14, 14)
		overlay.arrow:SetPoint("TOPLEFT", -1, 1)
	else
		overlay.arrow = E:CreateText(overlay, E.tokens.size.display, "LEFT")
		overlay.arrow:SetPoint("TOPLEFT", 1, -1)
		overlay.arrow:SetText("+")
	end

	overlay.coin = overlay:CreateTexture(nil, "OVERLAY")
	overlay.coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
	overlay.coin:SetSize(12, 12)
	overlay.coin:SetPoint("TOPLEFT", 1, -1)

	-- Best quest reward: a thin green outline around the whole button.
	overlay.best = CreateFrame("Frame", nil, button, "BackdropTemplate")
	overlay.best:SetPoint("TOPLEFT", -E.pixel, E.pixel)
	overlay.best:SetPoint("BOTTOMRIGHT", E.pixel, -E.pixel)
	overlay.best:SetFrameLevel(button:GetFrameLevel() + 2)
	overlay.best:SetBackdrop({ edgeFile = E.media.flat, edgeSize = E.pixel * 2 })

	overlays[button] = overlay
	return overlay
end

local function ClearOverlay(button)
	local overlay = overlays[button]
	if not overlay then return end
	overlay:Hide()
	overlay.best:Hide()
end

-- Clears every arrow of one kind (an element's Improve switch went off).
local function ClearKind(kind)
	for button, buttonKind in pairs(overlayKind) do
		if buttonKind == kind then ClearOverlay(button) end
	end
end

function E:SetUpgradeArrow(button, link, opts)
	if not button then return end
	opts = opts or {}
	if opts.kind then overlayKind[button] = opts.kind end
	if not M.active or not link or not KindAllowed(opts.kind) then
		ClearOverlay(button)
		return
	end
	local ok, result = pcall(Evaluate, link)
	if not ok then result = nil end
	local upgrade = result and result.upgrade and (M.db.icons or opts.quest)
	local tint = result and not result.usable and M.db.tintUnusable and not opts.noTint
	local coin = opts.coin and true or false
	if not upgrade and not tint and not coin and not opts.best then
		ClearOverlay(button)
		return result
	end
	local overlay = Overlay(button)
	local r, g, b = Green()
	overlay.arrow:SetShown(upgrade and true or false)
	if overlay.arrow.SetTextColor then overlay.arrow:SetTextColor(r, g, b) end
	overlay.tint:SetShown(tint and true or false)
	overlay.coin:SetShown(coin and not upgrade)
	overlay.best:SetBackdropBorderColor(r, g, b, 1)
	overlay.best:SetShown(opts.best and true or false)
	overlay:Show()
	if upgrade then M.OfferArrowHelp(button) end
	return result
end

-- Blizzard bag windows (when EldoUI's bags are off) -----------------------
local function UpdateContainerFrame(frame)
	if not M.active or not frame or not frame.IsShown or not frame:IsShown() then return end
	local function Update(button)
		local ok, bag = pcall(button.GetBagID, button)
		local link = ok and bag and C_Container.GetContainerItemLink(bag, button:GetID())
		E:SetUpgradeArrow(button, link, { kind = "bags" })
	end
	if frame.EnumerateValidItems then
		for _, button in frame:EnumerateValidItems() do Update(button) end
	elseif frame.Items then
		for _, button in ipairs(frame.Items) do Update(button) end
	end
end

local function BlizzardBagFrames()
	local frames = {}
	if ContainerFrameCombinedBags then frames[#frames + 1] = ContainerFrameCombinedBags end
	for index = 1, (NUM_TOTAL_BAG_FRAMES or NUM_CONTAINER_FRAMES or 13) do
		local frame = _G["ContainerFrame" .. index]
		if frame then frames[#frames + 1] = frame end
	end
	return frames
end

-- EldoUI's own bag slots (named EldoUI_Bag<bag>_Slot<slot> by the Bags module).
local function UpdateEldoBags()
	local frame = _G.EldoUI_Bags
	if not frame or not frame:IsShown() then return end
	local cache, bagHolders = E.BagCache, frame.holders or {}
	for _, bag in ipairs(cache:BagIDs({ reagent = true })) do
		local buttons = bagHolders[bag] and bagHolders[bag].buttons
		if buttons then
			for slot = 1, cache:NumSlots(bag) do
				local button = buttons[slot]
				if button then E:SetUpgradeArrow(button, cache:Link(bag, slot)) end
			end
		end
	end
end

-- Merchant ------------------------------------------------------------------
local function UpdateMerchant()
	if not M.active or not MerchantFrame or not MerchantFrame:IsShown() then return end
	local perPage = MERCHANT_ITEMS_PER_PAGE or 10
	local buyback = MerchantFrame.selectedTab == 2
	for index = 1, perPage do
		local button = _G["MerchantItem" .. index .. "ItemButton"]
		if button then
			local item = ((MerchantFrame.page or 1) - 1) * perPage + index
			local link = not buyback and item <= (GetMerchantNumItems() or 0) and GetMerchantItemLink(item) or nil
			-- The merchant already tints what you can't use.
			E:SetUpgradeArrow(button, link, { noTint = true, kind = "merchant" })
		end
	end
end

-- Loot rolls (Blizzard's roll frames) -----------------------------------------
local function UpdateRollFrame(frame)
	if not M.active then return end
	local rollID = frame and frame.rollID
	local link = rollID and GetLootRollItemLink and GetLootRollItemLink(rollID)
	local target = frame.IconFrame or frame.Icon or frame
	E:SetUpgradeArrow(target, link, { noTint = true, kind = "rolls" })
end

local function UpdateRollFrames()
	for index = 1, 4 do -- GroupLootFrame1-4 (Forever has no NUM_GROUP_LOOT_FRAMES)
		local frame = _G["GroupLootFrame" .. index]
		if frame and frame:IsShown() then UpdateRollFrame(frame) end
	end
end

-- Quest rewards -------------------------------------------------------------
local function QuestChoices()
	local frame = QuestInfoFrame
	if not frame or not frame.rewardsFrame or not QuestInfo_GetRewardButton then return end
	local log = frame.questLog
	local count
	if log then
		local questID = C_QuestLog and C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
		local ok, value = pcall(GetNumQuestLogChoices, questID)
		count = ok and value or 0
	else
		count = GetNumQuestChoices and GetNumQuestChoices() or 0
	end
	local list = {}
	for index = 1, count or 0 do
		local button = QuestInfo_GetRewardButton(frame.rewardsFrame, index)
		if button then
			local link
			if log then link = GetQuestLogItemLink and GetQuestLogItemLink("choice", index)
			else link = GetQuestItemLink and GetQuestItemLink("choice", index) end
			list[#list + 1] = { button = button, link = link }
		end
	end
	-- Clear arrows left on fixed rewards from an earlier quest.
	for index = #list + 1, #list + 10 do
		local button = QuestInfo_GetRewardButton(frame.rewardsFrame, index)
		if not button then break end
		ClearOverlay(button)
	end
	return list, log and "questlog" or "quest"
end

-- Mark a list of reward choices ({ button, link } each): the best upgrade
-- outlined, or else the best-selling one's coin. Also for the dialog view's
-- reward cards (Modules/Dialogue). False when quest rewards are not marked.
function E:MarkQuestRewards(list, kind)
	if not (M.active and type(list) == "table") then return false end
	if not M.db.questRewards or not KindAllowed(kind) then
		for _, entry in ipairs(list) do ClearOverlay(entry.button) end
		return false
	end
	local best, bestDelta, richest, richestPrice
	for _, entry in ipairs(list) do
		local ok, result = pcall(Evaluate, entry.link)
		entry.result = ok and result or nil
		local gain = entry.result and (entry.result.dps or entry.result.delta)
		if entry.result and entry.result.upgrade and gain and (not bestDelta or gain > bestDelta) then
			best, bestDelta = entry, gain
		end
		local price = entry.link and select(11, C_Item.GetItemInfo(entry.link))
		if type(price) == "number" and price > 0 and (not richestPrice or price > richestPrice) then
			richest, richestPrice = entry, price
		end
	end
	for _, entry in ipairs(list) do
		E:SetUpgradeArrow(entry.button, entry.link, {
			quest = true, noTint = true, kind = kind, best = entry == best and #list > 1,
			coin = not best and M.db.questVendor and entry == richest and #list > 1,
		})
	end
	return true
end

local function UpdateQuestRewards()
	if not M.active then return end
	local list, kind = QuestChoices()
	if not list then return end
	E:MarkQuestRewards(list, kind)
end

---------------------------------------------------------------------------
-- Refresh: the engine runs every refresher (these arrows first) a moment
-- after scores may have changed.
---------------------------------------------------------------------------
local function PaintAll()
	if not M.active then return end
	ForgetRatings()
	UpdateEldoBags()
	for _, frame in ipairs(BlizzardBagFrames()) do UpdateContainerFrame(frame) end
	UpdateMerchant()
	UpdateRollFrames()
	if QuestInfoFrame and QuestInfoFrame:IsVisible() then UpdateQuestRewards() end
end
E:RegisterUpgradeRefresh(PaintAll)

function M:RefreshIcons()
	IS:Redraw()
end

-- Hooks stay installed; each one checks the module and the element switch
-- every time it runs, so nothing changes while a switch is off.
local function HookFrames()
	for _, frame in ipairs(BlizzardBagFrames()) do
		if frame.UpdateItems then hooksecurefunc(frame, "UpdateItems", UpdateContainerFrame) end
	end
	if MerchantFrame_UpdateMerchantInfo then hooksecurefunc("MerchantFrame_UpdateMerchantInfo", UpdateMerchant) end
	if MerchantFrame_UpdateBuybackInfo then hooksecurefunc("MerchantFrame_UpdateBuybackInfo", UpdateMerchant) end
	if QuestInfo_Display then
		hooksecurefunc("QuestInfo_Display", function() C_Timer.After(0, UpdateQuestRewards) end)
	end
	for index = 1, 4 do -- GroupLootFrame1-4 (Forever has no NUM_GROUP_LOOT_FRAMES)
		local frame = _G["GroupLootFrame" .. index]
		if frame then frame:HookScript("OnShow", UpdateRollFrame) end
	end
	if _G.EldoUI_Bags then _G.EldoUI_Bags:HookScript("OnShow", function() M:RefreshIcons() end) end
end

local function ClearAll()
	for button in pairs(overlays) do ClearOverlay(button) end
end

---------------------------------------------------------------------------
-- Scales: create, rename, delete, share (stored by the engine)
---------------------------------------------------------------------------
local function AfterScaleChange()
	M:RefreshIcons()
	if E.RefreshConfig then E:RefreshConfig() end
end

function M:SelectScale(key)
	if IS:SelectScale(key) then AfterScaleChange() end
end

function M:NewScale(name, weights, model)
	local key = IS:NewScale(name, weights, model)
	AfterScaleChange()
	return key
end

function M:RenameScale(name)
	if IS:RenameScale(IS:ActiveScaleKey(), name) then
		self.db.renameTo = ""
		AfterScaleChange()
	end
end

function M:DeleteScale()
	if IS:DeleteScale(IS:ActiveScaleKey()) then AfterScaleChange() end
end

function M:ResetScale()
	if IS:ResetScale(IS:ActiveScaleKey()) then AfterScaleChange() end
end

function M:ScaleString() return IS:ScaleString() end
function M:PawnString() return IS:PawnString() end

function M:ImportPawnString(text)
	local parsed = IS:ParsePawnString(text)
	if not parsed then return false end
	if parsed.count == 0 then
		self:Print(L["That Pawn scale has no stats EldoUI can use."])
		return true
	end
	self:NewScale(parsed.name, parsed.weights)
	local note = parsed.factor < 1 and (" " .. L["Weights scaled by %.2f to fit; their order is the same."]:format(parsed.factor)) or ""
	if parsed.skipped > 0 then note = note .. " " .. L["%d Pawn values EldoUI doesn't use were skipped."]:format(parsed.skipped) end
	self:Print(L["Imported a Pawn scale with %d stats."]:format(parsed.count) .. note)
	return true
end

function M:ImportScaleString(text)
	if type(text) ~= "string" then return false end
	if text:find("Pawn:") and self:ImportPawnString(text) then return true end
	local parsed = IS:ParseScaleString(text)
	if not parsed or parsed.count == 0 then
		self:Print(L["No stats found. The format is Strength=1, Agility=0.5 ... or a Pawn scale string."])
		return false
	end
	self:NewScale(parsed.name, parsed.weights, parsed.model)
	self:Print(L["Imported a scale with %d stats."]:format(parsed.count))
	return true
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
local lastActive, lastDb

function M:OnInitialize()
	IS:MigrateLegacy()
	EnsureProxies()
	lastActive, lastDb = IS:ActiveScaleKey(), self.db
	self:RegisterEvent("PLAYER_LOGOUT", DropProxies)
	-- One section of the Tooltip page; it shows only while this module is on.
	if E.RegisterTooltipSection then
		E:RegisterTooltipSection("upgrade", { order = 10, title = "Upgrade", module = "Upgrades",
			desc = "A green arrow with the gain when an item beats what you wear, by your active scale.",
			item = UpgradeSection })
	end
end

function M:OnEnable()
	if not self.hooked then
		self.hooked = true
		HookFrames()
	end
	EnsureProxies()
	IS:Bump()
	if E.RefreshTooltipSections then E:RefreshTooltipSections() end
	-- Gear, item data, level and talents are watched by the engine.
	-- EldoUI's bag window marks the slots it repaints itself; after a bag
	-- change only the game's own bag windows need a pass.
	self:RegisterEvent("BAG_UPDATE_DELAYED", function()
		if not M.active then return end
		for _, frame in ipairs(BlizzardBagFrames()) do
			if frame:IsShown() then UpdateContainerFrame(frame) end
		end
	end)
	self:RegisterEvent("MERCHANT_SHOW", function() M:RefreshIcons() end)
end

function M:OnDisable()
	ClearAll()
	if E.RefreshTooltipSections then E:RefreshTooltipSections() end
end

-- Every option change lands here: re-link and redraw.
function M:OnProfileChanged()
	-- "Reset Upgrades" empties this same table: the engine's switches go
	-- back to their defaults too (the scales are kept; they are your work).
	if self.db == lastDb and rawget(self.db, "engine") == nil then IS:ResetSettings() end
	lastDb = self.db
	IS:MigrateLegacy()
	EnsureProxies()
	local active = IS:ActiveScaleKey()
	local changed = active ~= lastActive
	lastActive = active
	IS:Bump()
	if self.active then ClearAll() end
	if E.RefreshTooltipSections then E:RefreshTooltipSections() end
	-- A new scale needs its sliders on the options page.
	if changed and E.RefreshConfig then C_Timer.After(0, function() E:RefreshConfig() end) end
end

---------------------------------------------------------------------------
-- Blizzard element handlers: arrows on Blizzard's own windows need the
-- element's Improve switch. The windows' owners (Bags, Merchant, Loot and
-- NPC windows) decide about installing and migrating those switches; these
-- handlers only redraw or clear the arrows when a switch changes.
---------------------------------------------------------------------------
for kind, id in pairs(KIND_ELEMENT) do
	E:RegisterBlizzardHandler(id, {
		owner = "Upgrades",
		refreshModule = false,
		apply = function()
			if not M.active then return end
			if not KindAllowed(kind) then ClearKind(kind) end
			M:RefreshIcons()
		end,
		undo = function() ClearKind(kind) end,
	})
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local function ActiveScale() return IS:ActiveScale() end
local function IsSpecModel() return ActiveScale().model == "spec" end

local function RaterValues()
	local list = {}
	for _, rater in ipairs(IS:Raters()) do list[rater.key] = rater.title end
	return list
end

M.options = {
	{ type = "header", label = "Upgrade arrows" },
	{ type = "toggle", key = "tooltip", label = "Upgrade row in tooltips", desc = "A green arrow with the gain in the tooltip's info area. Its visibility (Always / Shift ...) is set on the Tooltip page." },
	{ type = "toggle", key = "onlyUpgrades", label = "Show only upgrades", desc = "No row for items that are not upgrades. Hold Shift to see the score anyway." },
	{ type = "toggle", key = "border", label = "Green border on upgrades", desc = "The tooltip border turns green when the item is an upgrade." },
	{ type = "select", key = "display", label = "Show the gain as", values = { percent = "Percent (+7.5%)", score = "Score (+12.3)" },
		desc = "Percent of what you wear now, or the plain score difference. Empty slots always show the score. A simulated rating shows DPS instead." },
	{ type = "range", key = "minPercent", label = "Smallest upgrade", unit = "%", min = 0, max = 20, step = 0.5, desc = "Gains below this are not marked." },
	{ type = "toggle", key = "icons", label = "Arrows on icons", desc = "On bag, merchant and loot-roll icons. On Blizzard's own bag, merchant and roll windows this also needs that element's Improve switch (Blizzard UI page)." },
	{ type = "toggle", key = "tintUnusable", label = "Red tint on unusable gear", desc = "Bag items the game marks in red (wrong armor type, level too high) get a faint red tint." },
	{ type = "toggle", key = "questRewards", label = "Quest rewards", disabled = E:BlizzardNeeds("quest-gossip-npc", "improve"),
		desc = "Arrows on upgrade rewards and a green outline on the best choice in the quest dialogs, and in the quest log while World map and quest log has Improve on." },
	{ type = "toggle", key = "questVendor", label = "Best vendor reward", desc = "When no reward is an upgrade, a coin marks the one that sells for most." },
	{ type = "select", key = EngineKey("engine.rating"), label = "Rate items by", values = RaterValues,
		desc = "How every gain in EldoUI is worked out for this character: your stat weights, or another rating mode an add-on provides (such as the Loot Guide's simulator).",
		hidden = function() return #IS:Raters() < 2 end },
	{ type = "description", label = "The item ID shows on Shift through the Tooltip page (Items and spells > Item ID)." },

	{ type = "header", label = "Gems and enchants" },
	{ type = "toggle", key = EngineKey("engine.gems"), label = "Count socketed gems", desc = "Gems in an item add their stats to its score; their sockets no longer count as empty. Off: every socket counts as empty, valued by the socket weights below." },
	{ type = "toggle", key = EngineKey("engine.enchants"), label = "Count enchants", desc = "An item's enchant adds its plain stats (+7 Agility) to its score. Off compares items bare, as a new item would be before you enchant it. Procs are never counted." },

	{ type = "header", label = "Scale" },
	{ type = "description", label = "A scale gives each stat a value; an item's score is the sum. Starter scales are rough; tune one for your spec or paste a friend's." },
	{ type = "select", key = EngineKey("engine.activeScale"), label = "Active scale (this class)", values = function() return IS:ScaleList() end,
		desc = "The scale used for this class. Each class remembers its own." },
	{ type = "execute", label = "New custom scale", desc = "A copy of the active scale that you can rename and tune.", func = function() M:NewScale() end },
	{ type = "execute", label = "Copy as text", desc = "The scale as plain text (Strength=1, Agility=0.5 ...) to share.",
		func = function() E:ShowCopyBox(L["Upgrade scale"], L["Everything is selected. Press Ctrl+C and share it."], M:ScaleString()) end },
	{ type = "execute", label = "Copy as Pawn string", desc = "The scale in Pawn's format, ( Pawn: v1: \"Name\": ... ), for Pawn users and scale websites.",
		func = function() E:ShowCopyBox(L["Pawn scale"], L["Everything is selected. Press Ctrl+C and share it."], M:PawnString()) end },
	{ type = "execute", label = "Paste a scale", desc = "Paste an EldoUI or a Pawn scale string. It becomes a new custom scale.",
		func = function() E:ShowPasteBox(L["Paste an upgrade scale"], L["Paste a scale (Ctrl+V): EldoUI scale \"Name\": Strength=1, Agility=0.5 ... or a Pawn string ( Pawn: v1: \"Name\": ... ), and click Save."], function(text) M:ImportScaleString(text) end) end },
	{ type = "execute", label = "Reset to starter values", desc = "Puts this starter scale back to EldoUI's values (for a spec scale: back to EldoUI's stat priority).", confirm = true,
		hidden = function() return IS:IsCustom(IS:ActiveScaleKey()) end, func = function() M:ResetScale() end },
	{ type = "execute", label = "Delete this scale", desc = "Removes this custom scale.",
		hidden = function() return not IS:IsCustom(IS:ActiveScaleKey()) end,
		func = function()
			local scale = ActiveScale()
			if scale then
				E:ShowConfirm({ key = "ELDOUI_UPGRADES_DELETE", title = L["Upgrades"], text = L["Delete the scale %s?"]:format(E:Highlight(scale.name)),
					accept = DELETE or L["Delete"], danger = true, onAccept = function() M:DeleteScale() end })
			end
		end },
	{ type = "input", key = "renameTo", label = "New name", desc = "Type a name, press Enter, then click Rename." },
	{ type = "execute", label = "Rename", desc = "Gives the active scale the name above.", func = function() M:RenameScale(M.db.renameTo) end },
	{ type = "toggle", key = "showAllStats", label = "Show every stat", desc = "Off lists only the stats this scale values. On lists all of them so you can add more." },
	{ type = "header", label = "Stat values" },
}

-- One slider per stat. Ratings and weapon DPS get a second row with a wider
-- range for spec scales, whose rating weights are per 1 %.
local function StatHidden(stat, specRow)
	return function()
		local spec = IsSpecModel()
		if specRow ~= nil and specRow ~= spec then return true end
		if stat.specOnly and not spec then return true end
		if M.db.showAllStats then return false end
		local value = tonumber(ActiveScale().weights[stat.key])
		return not value or value == 0
	end
end

for _, stat in ipairs(IS.STATS) do
	local label, gameName = IS.StatLabel(stat)
	local plainDesc = stat.socket and E.Key("Points for each empty %s on an item.") or E.Key("Points per 1 %s on an item.")
	local wide = stat.rating or stat.key == "Dps" or stat.key == "RangedDps"
	table.insert(M.options, {
		type = "range", key = EngineKey("current." .. stat.key), label = label, gameName = gameName, min = 0, max = stat.max or 3, step = stat.step or 0.05,
		desc = plainDesc, descFill = label, hidden = StatHidden(stat, wide and false or nil),
	})
	if wide then
		local specDesc, specFill
		if stat.key == "Defense" then
			specDesc = E.Key("Points per defense skill point the item's rating gives at your level.")
		elseif stat.key == "Expertise" then
			specDesc = E.Key("Points per expertise point the item's rating gives at your level.")
		elseif stat.key == "Dps" then
			specDesc = E.Key("Points per 1 weapon DPS in the main hand; the off hand counts half.")
		elseif stat.key == "RangedDps" then
			specDesc = E.Key("Points per 1 DPS of a bow, gun, crossbow, thrown weapon or wand.")
		else
			specDesc, specFill = E.Key("Points per 1%% %s the item's rating gives at your level."), label
		end
		table.insert(M.options, {
			type = "range", key = EngineKey("current." .. stat.key),
			label = stat.rating and E.Key("%s (per 1%%)") or label, labelFill = stat.rating and label or nil,
			gameName = not stat.rating and gameName or nil,
			min = 0, max = stat.rating and 40 or 15, step = stat.rating and 0.5 or 0.1,
			desc = specDesc, descFill = specFill, hidden = StatHidden(stat, true),
		})
	end
end

---------------------------------------------------------------------------
-- Style presets
---------------------------------------------------------------------------
E:RegisterStyles("Upgrades", {
	{ key = "EldoUI", title = "EldoUI", desc = "Upgrade row and green border in tooltips, arrows on icons and quest rewards.",
		settings = { tooltip = true, onlyUpgrades = true, border = true, display = "percent", minPercent = 0, icons = true,
			tintUnusable = true, questRewards = true, questVendor = true, engine = { gems = true, enchants = false } } },
	{ key = "Quiet", title = "Quiet", desc = "Only the tooltip row, no border change, no icon tint, gains of 2% or more.",
		settings = { tooltip = true, onlyUpgrades = true, border = false, display = "percent", minPercent = 2, icons = true,
			tintUnusable = false, questRewards = true, questVendor = false } },
	{ key = "IconsOnly", title = "Icons only", desc = "Arrows on icons and quest rewards, nothing in tooltips.",
		settings = { tooltip = false, border = false, icons = true, tintUnusable = true, questRewards = true, questVendor = true } },
	{ key = "Detailed", title = "Detailed", desc = "The score on every gear tooltip, upgrade or not.",
		settings = { tooltip = true, onlyUpgrades = false, border = true, display = "percent", minPercent = 0, icons = true,
			tintUnusable = true, questRewards = true, questVendor = true } },
	{ key = "Score", title = "Score", desc = "Gains as score points instead of percent, for tuning scales.",
		settings = { tooltip = true, onlyUpgrades = false, border = true, display = "score", minPercent = 0, icons = true } },
	{ key = "AsWorn", title = "As worn", desc = "Gems and enchants count, so the score is what each item gives you right now.",
		settings = { tooltip = true, onlyUpgrades = true, border = true, display = "percent", minPercent = 0, icons = true,
			engine = { gems = true, enchants = true } } },
})

---------------------------------------------------------------------------
-- Tour help: the first upgrade mark that stays on screen a moment
---------------------------------------------------------------------------
local arrowHelp = { button = nil, pending = false }

local function MarkedButton()
	local button = arrowHelp.button
	local overlay = button and overlays[button]
	if overlay and overlay:IsVisible() and overlay.arrow:IsShown() then return button end
end

E.Tour:Register("upgrades:arrows", {
	form = "spot", word = "upgrades",
	offer = function(_, force)
		return E.Tour:Spot("upgrades:arrows", {
			-- Offered again at the next redraw, so it never waits in the queue.
			force = force, now = true, target = MarkedButton,
			title = L["Upgrades"],
			text = L["The green mark means this item beats what you wear, rated by the stat weights of your scale. The Upgrades page picks the scale and how big a gain counts."],
		})
	end,
	replay = function(def) def.offer(def, true) end,
})

function M.OfferArrowHelp(button)
	if arrowHelp.pending or E.Tour:Seen("upgrades:arrows") then return end
	arrowHelp.button, arrowHelp.pending = button, true
	C_Timer.After(1, function()
		arrowHelp.pending = false
		if MarkedButton() then E.Tour:Offer("upgrades:arrows") end
	end)
end
