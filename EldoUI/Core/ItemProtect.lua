-- EldoUI item protection: which items one of your open quests, a
-- quest you can still start, or a recipe one of your characters can still
-- learn needs. EldoUI's own sell and move batches (Merchant junk, Bags
-- "Move these") leave those items alone, the bags mark them with a lock,
-- the delete pop-up names their quest and item tooltips say "Needed" or
-- "Safe to sell".
--
-- Only data the game and EldoUI already have:
--   * the game's quest flags on a bag slot (C_Container.GetContainerItemQuestInfo)
--   * Loot Guide quest data: quests that ask for the item (only the ones you
--     are on, C_QuestLog.IsOnQuest) and the quest it starts (until done)
--   * Characters: recipes one of your characters can learn now or later
-- Nothing here sells, moves or deletes anything; it only answers questions.
--
--   E:ItemProtection(itemID, bag, slot) -> reason or nil
--       reason = { kind = "quest" | "starter" | "recipe", questID, title, onQuest, status }
--   E:IsItemProtected(itemID, bag, slot) -> true or false, reason
--   E:ItemQuestContext(itemID, bag, slot) -> { { questID, title, onQuest, starts, completed } }, isQuestItem
--   E:ProtectionReasonText(reason) -> "Quest: The Book of Ur" (one short line)
local _, E = ...
local L = E.L

local IP = {}
E.ItemProtect = IP

-- The lock mark on protected bag slots; Bags already uses it for locked bags.
IP.LOCK_ICON = "Interface\\PetBattles\\PetBattle-LockIcon"

local Plain = E.Plain

local function Ask(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, result = pcall(fn, ...)
	if ok then return Plain(result) end
end

-- The Loot Guide's quest data, when it is loaded.
local function LootGuide()
	local LG = E.LootGuide
	if LG and LG.HasData and LG.ItemQuests and LG:HasData() then return LG end
end
IP.LootGuide = LootGuide

local function OnQuest(questID)
	return Ask(C_QuestLog and C_QuestLog.IsOnQuest, questID) == true
end

local function Completed(questID)
	return Ask(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, questID) == true
end

function IP.QuestTitle(questID)
	local title = Ask(C_QuestLog and C_QuestLog.GetTitleForQuestID, questID)
	if type(title) == "string" and title ~= "" then return title end
	local LG = LootGuide()
	title = LG and LG.QuestTitle and LG:QuestTitle(questID)
	if type(title) == "string" and title ~= "" then return title end
	return ("#%d"):format(questID)
end

local function SlotQuestInfo(bag, slot)
	if type(bag) ~= "number" or type(slot) ~= "number" then return nil end
	local get = C_Container and C_Container.GetContainerItemQuestInfo
	if not get then return nil end
	local ok, info = pcall(get, bag, slot)
	if ok and type(info) == "table" then return info end
end

local function ItemQuests(itemID)
	local LG = LootGuide()
	if not LG then return nil end
	local ok, quests = pcall(LG.ItemQuests, LG, itemID)
	if ok and type(quests) == "table" then return quests end
end

-- Every quest the item belongs to: the quest it starts (game flag or Loot
-- Guide) and the quests that ask for it. `isQuestItem` is the game's flag.
function E:ItemQuestContext(itemID, bag, slot)
	itemID = Plain(itemID)
	local list, seen = {}, {}
	local function Add(questID, starts, onQuest)
		questID = Plain(questID)
		if type(questID) ~= "number" or seen[questID] then return end
		seen[questID] = true
		if onQuest == nil then onQuest = OnQuest(questID) end
		list[#list + 1] = { questID = questID, title = IP.QuestTitle(questID), onQuest = onQuest and true or false,
			starts = starts and true or false, completed = Completed(questID) }
	end
	local info = SlotQuestInfo(bag, slot)
	if info and Plain(info.questID) then Add(info.questID, true, Plain(info.isActive) == true) end
	local quests = type(itemID) == "number" and ItemQuests(itemID)
	if quests then
		if quests.starts then Add(quests.starts, true) end
		for _, questID in ipairs(quests.needed or {}) do Add(questID, false) end
	end
	return list, info and Plain(info.isQuestItem) == true or false
end

function E:ItemProtection(itemID, bag, slot)
	itemID = Plain(itemID)
	if type(itemID) ~= "number" then return nil end
	local info = SlotQuestInfo(bag, slot)
	if info then
		local questID = Plain(info.questID)
		if type(questID) == "number" and not Completed(questID) then
			return { kind = "starter", questID = questID, title = IP.QuestTitle(questID), onQuest = Plain(info.isActive) == true }
		end
		if Plain(info.isQuestItem) == true then return { kind = "quest" } end
	end
	local quests = ItemQuests(itemID)
	if quests then
		for _, questID in ipairs(quests.needed or {}) do
			if OnQuest(questID) then
				return { kind = "quest", questID = questID, title = IP.QuestTitle(questID), onQuest = true }
			end
		end
		local starts = quests.starts
		if type(starts) == "number" and not Completed(starts) and not OnQuest(starts) then
			return { kind = "starter", questID = starts, title = IP.QuestTitle(starts), onQuest = false }
		end
	end
	local chars = E.modules and E.modules.Characters
	if chars and chars.active and chars.RecipeStatus then
		local ok, status = pcall(chars.RecipeStatus, chars, itemID)
		if ok and (status == "now" or status == "later") then return { kind = "recipe", status = status } end
	end
	return nil
end

function E:IsItemProtected(itemID, bag, slot)
	local reason = self:ItemProtection(itemID, bag, slot)
	return reason ~= nil, reason
end

function E:ProtectionReasonText(reason)
	if not reason then return nil end
	if reason.kind == "recipe" then
		return reason.status == "now" and L["A recipe one of your characters can learn now"]
			or L["A recipe one of your characters can learn later"]
	end
	if reason.kind == "starter" then
		return reason.title and L["Starts the quest %s"]:format(reason.title) or L["Starts a quest"]
	end
	return reason.title and L["Needed for %s"]:format(reason.title) or L["Quest item"]
end

---------------------------------------------------------------------------
-- "Safe to sell": one short row on gray and white items that
-- sell to a vendor. "Needed" (with the reason) when one of your quests or
-- recipes needs the item; "Safe to sell" only when the Loot Guide's quest
-- data is loaded, so the word is never a guess.
---------------------------------------------------------------------------
local function OwnerSlot(tooltip)
	local ok, owner = pcall(tooltip.GetOwner, tooltip)
	if not ok or type(owner) ~= "table" then return nil end
	if owner.GetBagID and owner.GetID then
		local okBag, bag = pcall(owner.GetBagID, owner)
		local okSlot, slot = pcall(owner.GetID, owner)
		if okBag and okSlot then return Plain(bag), Plain(slot) end
	end
end

function IP.SafeToSellRow(tooltip, link, itemID, add)
	itemID = Plain(itemID)
	if type(itemID) ~= "number" then return end
	local name, _, quality, _, _, _, _, _, _, _, price = C_Item.GetItemInfo(Plain(link) or itemID)
	if not name or type(quality) ~= "number" or quality > 1 or type(price) ~= "number" or price <= 0 then return end
	local bag, slot = OwnerSlot(tooltip)
	local reason = E:ItemProtection(itemID, bag, slot)
	if reason then
		local warn = E.tokens.text.warn
		add(L["Needed"], E:ProtectionReasonText(reason), warn[1], warn[2], warn[3])
	elseif LootGuide() then
		local good = E.tokens.text.good
		add(L["Safe to sell"], nil, good[1], good[2], good[3])
	end
end

function IP:RegisterTooltip()
	if self.tooltipRegistered or not E.RegisterTooltipSection then return end
	self.tooltipRegistered = true
	E:RegisterTooltipSection("safeToSell", { order = 33, title = "Safe to sell", default = "always",
		desc = "On gray and white items: \"Needed\" with the quest or recipe that needs it, or \"Safe to sell\" when none of your quests or recipes do (needs the Loot Guide's quest data).",
		item = IP.SafeToSellRow })
end

-- Modules/Tooltip.lua (the section list) loads after the core files.
E:RegisterEvent("PLAYER_LOGIN", function()
	IP:RegisterTooltip()
	E:UnregisterEvent("PLAYER_LOGIN", IP)
end, IP, "modules")
