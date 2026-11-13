-- EldoUI Quest Starter Drops: which creatures can drop an item that
-- starts a quest, before you kill them.
--
--   * Tooltip section "lootStarter" (Tooltip page: Always / Shift / Ctrl /
--     Alt / Never): on a creature, "Quest item: Sealed Letter (starts
--     Message to Ag'tor)  4%". The chance follows the Loot Guide's Drop
--     chances setting.
--   * Nameplates: a small icon on that creature's EldoUI nameplate (plate
--     callbacks of Modules/Nameplates.lua), above the name, left or right
--     of the bar.
--   * Hidden once the quest is done, in your quest log, not for your side,
--     race or class, or the item is in your bags (each can be turned off).
--
--   QD:Hints(npcID)        { { item, quest, chance }, ... } that still matter
--   QD:AllHints(npcID)     every hint of the creature, nothing hidden
--   QD:HintsForUnit(unit)  the same from a unit's GUID; nil for a secret GUID
--   QD:BuildIndex()        the reverse index creature -> starter items, built
--                          once from EldoUI_LootData (items with startsQuest,
--                          quest starters "i<item>", their droppers in
--                          Sources.lua), out of combat only
--
-- Static data and your own quest flags and bags only: no scanning, no
-- targeting, nothing read from combat. A secret GUID (inside instances)
-- adds nothing.
local _, E = ...
local L = E.L
local LG = E.LootGuide

local QD = E:NewModule("QuestDrops", {
	title = "Quest Starter Drops",
	desc = "Creatures that can drop an item that starts a quest: a line in their tooltip and a small icon on their nameplate.",
	category = LG and LG.category,
	conflicts = { "QuestionableDrops" },
	frames = {},
	movers = {},
	blizzard = {},
	savedKeys = { "profile.modules.QuestDrops" },
	optionsPage = "module:QuestDrops",
	presets = { "Bronze", "Dot", "Exclamation", "Safe", "Scroll" },
	uiAmount = "moderate",
	reload = false,
	defaults = {
		style = "Scroll",
		hideDone = true,      -- quest done or in your log
		hideOwned = true,     -- the item is in your bags
		hideOther = true,     -- quest not for your side, race or class
		minChance = 0,        -- percent; rarer drops are left out
		plates = true,        -- the nameplate icon
		plateSize = 14,
		platePosition = "top", -- top, left, right
		plateLook = "scroll",  -- scroll, exclamation, dot, bronze, safe
	},
})
E.QuestDrops = QD
-- The built-in group list (Core/Config.lua) names this module too, so it
-- keeps its group after the module split.
if E.defaultModuleCategory then E.defaultModuleCategory.QuestDrops = QD.category end

local Secret = E.Secret

function QD:Running()
	return self.active and LG and LG.active and true or false
end

---------------------------------------------------------------------------
-- The reverse index
---------------------------------------------------------------------------
local index          -- npcID -> { { item, quest, chance }, ... }
local pendingBuild = false

local function Data()
	return select(3, LG:DataStatus())
end

-- "n100:80,n97:3,+2" -> { [100] = 80, [97] = 3 }
local function Droppers(packed)
	local out = {}
	for npc, chance in tostring(packed or ""):gmatch("n(%d+):(%-?[%d%.]+)") do
		out[tonumber(npc)] = math.abs(tonumber(chance) or 0)
	end
	return out
end

local function AddStarter(byNpc, seen, LD, itemID, questID)
	if not (itemID and questID) or seen[itemID .. ":" .. questID] then return end
	seen[itemID .. ":" .. questID] = true
	local sources = LD.sources and LD.sources[itemID]
	for npc, chance in pairs(Droppers(sources)) do
		byNpc[npc] = byNpc[npc] or {}
		table.insert(byNpc[npc], { item = itemID, quest = questID, chance = chance })
	end
end

function QD:BuildIndex()
	if index then return index end
	if InCombatLockdown() then
		pendingBuild = true
		return nil
	end
	local LD = Data()
	if not LD then return nil end
	local byNpc, seen = {}, {}
	for itemID, packed in pairs(LD.items or {}) do
		if type(packed) == "string" then
			local quest = packed:match("^[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|(%d+)")
			if quest then AddStarter(byNpc, seen, LD, itemID, tonumber(quest)) end
		end
	end
	-- Quests whose starter is an item ("i<item>" in the starts field).
	for _, field in ipairs({ "quests", "journey" }) do
		for questID, packed in pairs(LD[field] or {}) do
			if type(packed) == "string" then
				local starts = LG.Split(packed, "|")[field == "quests" and 13 or 7]
				for item in tostring(starts or ""):gmatch("i(%d+)") do AddStarter(byNpc, seen, LD, tonumber(item), questID) end
			end
		end
	end
	for _, list in pairs(byNpc) do
		table.sort(list, function(a, b)
			if a.chance ~= b.chance then return a.chance > b.chance end
			return a.item < b.item
		end)
	end
	index = byNpc
	pendingBuild = false
	return index
end

function QD:ForgetIndex()
	index = nil
end

function QD:IndexBuilt()
	return index ~= nil
end

---------------------------------------------------------------------------
-- What still matters to you
---------------------------------------------------------------------------
local function OwnsItem(itemID)
	if not (C_Item and C_Item.GetItemCount) then return false end
	local ok, count = pcall(C_Item.GetItemCount, itemID)
	if not ok or Secret(count) then return false end
	return (tonumber(count) or 0) > 0
end

local function NotForYou(questID)
	local quest = LG:JourneyQuest(questID)
	if not quest then return false end
	local player = LG:Player()
	local rMask, cMask = quest.raceMask, quest.classMask
	if rMask and rMask > 0 and (player.raceMask or 0) > 0 and bit.band(rMask, player.raceMask) == 0 then return true end
	if cMask and cMask > 0 and (player.classMask or 0) > 0 and bit.band(cMask, player.classMask) == 0 then return true end
	return false
end

function QD:AllHints(npcID)
	npcID = tonumber(npcID)
	if not npcID then return {} end
	local built = self:BuildIndex()
	return built and built[npcID] or {}
end

function QD:Hints(npcID)
	local db = self.db or self.defaults
	local out = {}
	for _, hint in ipairs(self:AllHints(npcID)) do
		local keep = hint.chance >= (tonumber(db.minChance) or 0)
		if keep and db.hideDone and (LG:QuestDone(hint.quest) or LG:OnQuest(hint.quest)) then keep = false end
		if keep and db.hideOwned and OwnsItem(hint.item) then keep = false end
		if keep and db.hideOther and NotForYou(hint.quest) then keep = false end
		if keep then out[#out + 1] = hint end
	end
	return out
end

-- npcID from a unit, or nil (players, secret GUIDs).
function QD:UnitNpc(unit)
	if type(unit) ~= "string" then return nil end
	local guid = UnitGUID and UnitGUID(unit)
	if Secret(guid) or type(guid) ~= "string" then return nil end
	return LG.NpcFromGUID and LG.NpcFromGUID(guid) or nil
end

function QD:HintsForUnit(unit)
	local npc = self:UnitNpc(unit)
	if not npc then return nil end
	return self:Hints(npc)
end

---------------------------------------------------------------------------
-- Tooltip section
---------------------------------------------------------------------------
local function ChanceText(chance)
	local mode = LG.db and LG.db.dropRates or "both"
	if mode == "off" or mode == "seen" then return nil end
	local Kit = LG.Kit
	return Kit and Kit.ChanceText(chance) or ("%d%%"):format(chance)
end

function QD:HintLine(hint)
	local record = LG:ItemRecord(hint.item)
	local itemName = record and record.name or ("#" .. hint.item)
	local quest = LG:JourneyQuest(hint.quest)
	local title = quest and quest.title or LG:QuestTitle(hint.quest) or ("#" .. hint.quest)
	return (L["%s (starts %s)"]):format(itemName, title), ChanceText(hint.chance)
end

local MAX_LINES = 3

local function UnitSection(_, unit, add)
	if not QD:Running() or type(unit) ~= "string" then return end
	if UnitIsPlayer and UnitIsPlayer(unit) then return end
	local hints = QD:HintsForUnit(unit)
	if not hints then return end
	local sr, sg, sb = unpack(E.tokens.text.secondary)
	for i, hint in ipairs(hints) do
		if i > MAX_LINES then
			add((L["and %d more"]):format(#hints - MAX_LINES), nil, sr, sg, sb)
			break
		end
		local text, chance = QD:HintLine(hint)
		local ar, ag, ab = unpack(E.media.accentColor)
		add(L["Quest item"] .. ": " .. text, chance, ar, ag, ab, 1, 1, 1)
	end
end
QD.TooltipUnit = UnitSection

local sectionDone
function QD:RegisterSection()
	if sectionDone or not E.RegisterTooltipSection then return end
	sectionDone = true
	E:RegisterTooltipSection("lootStarter", { order = 50, title = L["Loot Guide: quest starters"], default = "always",
		desc = L["On a creature that can drop an item that starts a quest: the item, the quest and the drop chance, until you have the item or did the quest."],
		unit = UnitSection })
end

---------------------------------------------------------------------------
-- Upkeep
---------------------------------------------------------------------------
LG:On("questdrops", function(changed)
	if changed.data then QD:ForgetIndex() end
	if QD.active and (changed.data or changed.quests or changed.bags or changed.player) and QD.RefreshPlates then QD:RefreshPlates() end
end)

local PLATE_LOOKS = { scroll = true, exclamation = true, dot = true, bronze = true, safe = true }
local POSITIONS = { top = true, left = true, right = true }
local function Sanitize(db)
	if not PLATE_LOOKS[db.plateLook] then db.plateLook = "scroll" end
	if not POSITIONS[db.platePosition] then db.platePosition = "top" end
	db.plateSize = math.max(8, math.min(32, tonumber(db.plateSize) or 14))
	db.minChance = math.max(0, math.min(100, tonumber(db.minChance) or 0))
end
QD.Sanitize = Sanitize

function QD:OnEnable()
	Sanitize(self.db)
	self:RegisterSection()
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if pendingBuild and QD:BuildIndex() and QD.RefreshPlates then QD:RefreshPlates() end
	end)
	self:RegisterEvent("BAG_UPDATE_DELAYED", function() if QD.RefreshPlates then QD:RefreshPlates() end end)
	if self.StartPlates then self:StartPlates() end
	-- Build the index a moment after login, out of combat, so the first
	-- tooltip costs nothing.
	C_Timer.After(5, function()
		if QD.active and LG:HasData() and not InCombatLockdown() then QD:BuildIndex() end
	end)
end

function QD:OnDisable()
	if self.StopPlates then self:StopPlates() end
end

function QD:OnProfileChanged()
	Sanitize(self.db)
	if self.active and self.RefreshPlates then self:RefreshPlates(true) end
end
