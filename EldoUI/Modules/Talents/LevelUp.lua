-- EldoUI Talent Planner: the level-up checklist.
--
-- One reminder when you level up, with what the new level brings:
--   * the talent point and where your plan puts it;
--   * new spells and ranks at your class trainer, with their cost, and
--     ranks that need a talent your plan doesn't take marked as such
--     (Training module);
--   * class quests that open at this level (Attunements, Class quests);
--   * gear for your spec that beats what you wear and that you can now
--     put on (the Journal's item rankings);
--   * dungeons that come in reach (My Adventure).
-- Above them, one line with what the level gave: the health, mana and
-- stat gains the game reports with the level-up (plain event values).
-- Each part shows only when its module is on and has something. Every line
-- is a link: the trainer and class quest lines put a map pin, the others
-- open the planner or the Journal. The one button, Learn, learns the
-- plan's next rank. Nothing is trained, accepted or equipped on its own.
--
-- This is EldoUI's only level-up card: while it is on, the alert lane's
-- "Level up" toast and My Adventure's level moment stand back
-- (M:OwnsLevelUp). Fanfare's celebration stays: it is a sound and a
-- splash, not a card.
--
--   M:LevelUpChecklist(level) -> { level, items = { { kind, text, icon,
--                                  action = { label, func, tip } } } }
--   M:LevelUpToast(level)     -> true when the reminder was shown
--   M:LevelUpGains(level)     -> "Health +32, Mana +45, Stamina +2" or nil
--   M:OwnsLevelUp()           -> true while this reminder shows on level-up
local _, E = ...
local L = E.L
local M = E.Talents

local MAX_NAMES = 3

local function Accent(text)
	return E.UIKit.AccentHex() .. text .. "|r"
end

local function Names(list, field)
	local names = {}
	for index = 1, math.min(#list, MAX_NAMES) do names[index] = list[index][field] end
	local text = table.concat(names, ", ")
	if #list > MAX_NAMES then text = L["%s and %d more"]:format(text, #list - MAX_NAMES) end
	return text
end

-- Opens an item or a dungeon in the Journal.
local function OpenJournal(kind, id)
	local J, A = E.Journal, E.Adventure
	if J and A and A:Running() and J:Open(J:Address(kind, id)) then return true end
	local LG = E.LootGuide
	if not (LG and LG.active) then return false end
	if kind == "item" and LG.OpenDatabase then
		LG:OpenDatabase("items", id)
	elseif kind == "instance" and LG.Open then
		LG:Open("journal", id)
	end
	return true
end

-- Spells of the planned talents (to mark ranks the plan doesn't need).
local function PlannedSpells(self)
	local plan = self:ActivePlan()
	local spells = {}
	for _, spellID in pairs(plan and plan.spells or {}) do spells[spellID] = true end
	return spells, plan ~= nil
end

local function TalentItem(self)
	if E:FeatureConflict("talents") then return nil end
	local step = self:NextStep()
	if not step or self:Unspent() <= 0 then return nil end
	local tree = self:Tree()
	local node = tree and tree.nodes[step.nodeID]
	if not node then return nil end
	return {
		kind = "talent", icon = node.icon,
		text = L["Talent point: %s"]:format(Accent(self:StepText(step))),
		action = { label = L["Planner"], func = function() M:OpenPlanner() end, tip = L["Opens the Talent Planner."] },
		primary = { label = L["Learn"], func = function() M:Learn("next") end, tip = L["Learns this one rank now. Nothing else is spent."] },
	}
end

local function SpellsItem(self, level)
	local T = E.Training
	if not (T and T.active and type(T.SpellsAt) == "function") then return nil end
	local ok, spells = pcall(T.SpellsAt, T, level)
	if not ok or type(spells) ~= "table" or #spells == 0 then return nil end
	local planned, hasPlan = PlannedSpells(self)
	local cost, skipped, shown = 0, 0, {}
	for _, spell in ipairs(spells) do
		if spell.talent and hasPlan and not planned[spell.talent] then
			skipped = skipped + 1
		else
			cost = cost + (spell.cost or 0)
			shown[#shown + 1] = { name = spell.rank and ("%s (%s)"):format(spell.name, spell.rank) or spell.name }
		end
	end
	local lines = {}
	if #shown > 0 then
		lines[1] = E:Plural(#shown, "New at your trainer: %s, %s.", "New at your trainer: %s, %s in all."):format(Names(shown, "name"), E:FormatMoney(cost))
	end
	if skipped > 0 then
		lines[#lines + 1] = E:Plural(skipped, "%d rank needs a talent your plan doesn't take.", "%d ranks need a talent your plan doesn't take."):format(skipped)
	end
	local item = { kind = "spells", icon = spells[1].icon, text = table.concat(lines, " ") }
	-- Mage portals are taught by the portal trainers, not the class trainer.
	local portals = E.mageTravel and E.mageTravel.spells or {}
	local isPortal = {}
	for _, spell in ipairs(portals) do
		if spell.kind == "portal" then isPortal[spell.id] = true end
	end
	local portal = true
	for _, spell in ipairs(spells) do
		if not (spell.entry and isPortal[spell.entry.id]) then portal = false break end
	end
	if type(T.SetTrainerWaypoint) == "function" and #T:ClassTrainers(portal) > 0 then
		item.action = { label = L["Trainer"], func = function() T:SetTrainerWaypoint(portal) end,
			tip = portal and L["Puts a map pin on your nearest portal trainer."] or L["Puts a map pin on your nearest class trainer."] }
	elseif type(T.Show) == "function" then
		item.action = { label = L["Training"], func = function() T:Show("spells") end, tip = L["Opens the list of spells to train."] }
	end
	return item
end

local function QuestsItem(level)
	local A = E.Attunements
	if not (A and A.Running and A:Running() and type(A.ClassQuestsAt) == "function") then return nil end
	local ok, keys = pcall(A.ClassQuestsAt, A, level)
	if not ok or type(keys) ~= "table" or #keys == 0 then return nil end
	local list = {}
	for index, key in ipairs(keys) do list[index] = { name = A:Name(key) } end
	local key, place
	if type(A.NearestClassQuest) == "function" then
		key, place = A:NearestClassQuest(keys)
	else
		key = keys[1]
		place = select(2, A:NextClassStep(key))
	end
	local item = {
		kind = "quests", icon = 136243,
		text = E:Plural(#keys, "Class quest opens: %s.", "Class quests open: %s."):format(Names(list, "name")),
	}
	if place and place.uiMapID then
		item.action = { label = L["Class quest"], func = function() A:ClassWaypoint(key) end, tip = L["Puts a map pin where the class quest starts."] }
	else
		item.action = { label = L["Class quest"], func = function() A:Open(key) end, tip = L["Opens the class quest in the Journal."] }
	end
	return item
end

local function GearItem(level)
	local LG = E.LootGuide
	if not (LG and LG.active and type(LG.NextUpgrades) == "function") then return nil end
	local ok, upgrades = pcall(LG.NextUpgrades, LG, 30)
	if not ok or type(upgrades) ~= "table" then return nil end
	local list = {}
	for _, upgrade in ipairs(upgrades) do
		if upgrade.useLevel == level then
			local record = LG.ItemRecord and LG:ItemRecord(upgrade.itemID)
			list[#list + 1] = { name = record and record.name or ("item:" .. upgrade.itemID), itemID = upgrade.itemID }
		end
	end
	if #list == 0 then return nil end
	local itemID = list[1].itemID
	return {
		kind = "gear", icon = 132644,
		text = L["Gear you can wear now: %s."]:format(Names(list, "name")),
		action = { label = L["Journal"], func = function() OpenJournal("item", itemID) end, tip = L["Opens the item in the Journal: where it drops and what it gives."] },
	}
end

-- Dungeons that come in reach at this level (My Adventure's level page).
local function DungeonsItem(level)
	local J, A = E.Journal, E.Adventure
	if not (J and A and type(J.LevelUpPage) == "function" and type(A.Running) == "function" and A:Running()) then return nil end
	local LG = E.LootGuide
	local ok, page = pcall(J.LevelUpPage, J, level, true)
	if not ok or type(page) ~= "table" or type(page.dungeons) ~= "table" or #page.dungeons == 0 then return nil end
	local list = {}
	for index, key in ipairs(page.dungeons) do
		local info = LG and LG.InstanceInfo and LG:InstanceInfo(key)
		list[index] = { name = info and info.name or key }
	end
	local key = page.dungeons[1]
	return {
		kind = "dungeons", icon = 136327,
		text = E:Plural(#list, "Dungeon in reach: %s.", "Dungeons in reach: %s."):format(Names(list, "name")),
		action = { label = L["Journal"], func = function() OpenJournal("instance", key) end, tip = L["Opens the dungeon in the Journal."] },
	}
end

---------------------------------------------------------------------------
-- What the level gave, from the game's level-up event: level, healthDelta,
-- powerDelta, numNewTalents, numNewPvpTalentSlots, then the five stat
-- deltas (spirit since Forever 1.60.1). Values only shown, never used.
---------------------------------------------------------------------------
local gains -- { level = n, health = n, power = n, stats = { n, n, n, n, n } }

local function Plain(value)
	return not E:IsSecret(value) and type(value) == "number"
end

local function RecordGains(_, _, level, health, power, _, _, ...)
	if not Plain(level) then gains = nil return end
	gains = { level = level, health = Plain(health) and health or 0, power = Plain(power) and power or 0, stats = {} }
	for index = 1, 5 do
		local value = select(index, ...)
		gains.stats[index] = Plain(value) and value or 0
	end
end
-- Recorded by the planner's own level-up handler, which the module drops
-- when it is turned off; nothing listens while the planner is off.
M.RecordLevelGains = RecordGains

function M:ForgetLevelGains()
	gains = nil
end

local STAT_NAMES = E:TranslateValues({ E.Key("Strength"), E.Key("Agility"), E.Key("Stamina"), E.Key("Intellect"), E.Key("Spirit") })

function M:LevelUpGains(level)
	if not (gains and gains.level == level) then return nil end
	local parts = {}
	if gains.health > 0 then parts[#parts + 1] = L["Health +%d"]:format(gains.health) end
	-- The game reports the power gain as mana (classes without mana get 0).
	if gains.power > 0 then parts[#parts + 1] = L["Mana +%d"]:format(gains.power) end
	for index, value in ipairs(gains.stats) do
		if value > 0 then
			local name = _G["SPELL_STAT" .. index .. "_NAME"]
			if type(name) ~= "string" or name == "" then name = STAT_NAMES[index] end
			parts[#parts + 1] = ("%s +%d"):format(name, value)
		end
	end
	if #parts == 0 then return nil end
	return table.concat(parts, ", ")
end

function M:LevelUpChecklist(level)
	local list = { level = level, items = {} }
	if not self.active then return list end
	local items = list.items
	for _, make in ipairs({
		function() return TalentItem(self) end,
		function() return SpellsItem(self, level) end,
		function() return QuestsItem(level) end,
		function() return GearItem(level) end,
		function() return DungeonsItem(level) end,
	}) do
		local ok, item = pcall(make)
		if ok and item then items[#items + 1] = item end
	end
	return list
end

-- While this is on, it is EldoUI's one card on a level-up.
function M:OwnsLevelUp()
	return self.active and type(self.db) == "table" and self.db.levelUpToast and true or false
end

-- One reminder for the whole level: a line per part, each a link, and one
-- button (Learn) while the plan has a rank to learn.
function M:LevelUpToast(level)
	if not self.active then return false end
	local list = self:LevelUpChecklist(level)
	local lines, actions = {}, {}
	for _, item in ipairs(list.items) do
		local action = item.action
		lines[#lines + 1] = { text = item.text, icon = item.icon, label = action and action.label,
			func = action and action.func, tip = action and action.tip }
		if item.primary then actions[#actions + 1] = item.primary end
	end
	local texts = {}
	local gained = self:LevelUpGains(level)
	if gained then texts[#texts + 1] = gained end
	if #lines == 0 then texts[#texts + 1] = L["Nothing new to learn, train or wear at this level."] end
	M:PushAlert({
		key = "eldoui-levelup", title = level and L["Level %d"]:format(level) or L["Level up"],
		text = #texts > 0 and table.concat(texts, "\n") or nil,
		lines = lines, icon = list.items[1] and list.items[1].icon or nil, duration = 30, actions = actions,
	})
	-- Learn is on the card: the first time it says what Learn does.
	if #actions > 0 and self.OfferToastHelp then self:OfferToastHelp() end
	return true
end
