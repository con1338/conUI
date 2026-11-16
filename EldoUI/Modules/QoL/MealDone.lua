-- EldoUI Quality of Life: a signal when eating and drinking are done
-- (Sound and misc tab, on by default). While you eat or drink, a sound
-- plays and the game flashes in the taskbar once everything the meal
-- restores is full: health for food, mana for drinks, both for rations.
-- With food that gives Well Fed it also waits the 10 seconds the buff
-- needs. One signal per meal; standing up is yours.
--
-- Which aura is a meal: the name the game gives Food (433) and Drink (430)
-- in its own language (every rank of plain food and water shares it), or a
-- use spell the Consumable Bar knows (rations, biscuits and WoW: Forever's
-- Nutritious foods, Modules/ConsumableBar.lua USE_SPELLS; buff food from
-- BUFF_FOOD_SPELLS). That module only lends its lists: it may be off.
--
-- Rules (Midnight / Forever): you can't eat in combat, so nothing is read
-- then; auras go through C_UnitAuras in pcall, and a secret aura, health
-- or mana counts as "not readable" (no signal, nothing compared). Your own
-- aura changes wake it (UNIT_AURA for the player only), and the end of
-- combat once (a meal that ended in combat was not read then); during a
-- meal it looks four times a second on the shared ticker and stops when
-- the meal ends. It waits a second after a meal starts or grows, so food
-- and drink from one key press count as one meal. Nothing is cast, used
-- or cancelled.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local M = E:GetModule("QoL")

M.defaults.mealDone = true
M.defaults.mealDoneSound = "eldo:EldoChime" -- media id, "none" for silence
M.defaults.mealDoneFlash = true             -- flash the game in the taskbar

-- Minimal keeps the game as Blizzard made it (Modules/QoL.lua, "Minimal").
for _, style in ipairs(E.styles and E.styles.QoL or {}) do
	if style.key == "Minimal" and type(style.settings) == "table" then style.settings.mealDone = false end
end

local Plain, Secret = E.Plain, E.Secret
local TICK = "QoL:mealDone"
local OWNER = "QoL:MealDone" -- its own event owner: Tweaks already has the module's PLAYER_REGEN_ENABLED
local PERIOD = 0.25
local WELL_FED_DELAY = 10.5 -- Well Fed comes after 10 seconds of eating
local SETTLE = 1            -- one press can start food and drink: wait for both auras
local FOOD_SPELL, DRINK_SPELL = 433, 430

-- While you eat or drink: { food, drink, buff, buffSince, changed, done }.
local meal

local function SpellName(id)
	local spell = C_Spell
	if not (spell and spell.GetSpellName) then return nil end
	local ok, name = pcall(spell.GetSpellName, id)
	name = ok and Plain(name) or nil
	if type(name) ~= "string" or name == "" then return nil end
	return name
end

-- The client's names for Food and Drink, read once. Without them the
-- English names stand in, as on the Consumable Bar, and are asked again
-- next time.
local names
local function Names()
	if names then return names end
	local food, drink = SpellName(FOOD_SPELL), SpellName(DRINK_SPELL)
	if food and drink then
		names = { food = food, drink = drink }
		return names
	end
	return { food = food or "Food", drink = drink or "Drink" } -- no-L: the game's own spell names
end

-- The Consumable Bar's lists of use spells (its file loads before this
-- one, and a module that is off still has them).
local function Lists()
	local bar = E:GetModule("ConsumableBar")
	local uses = bar and type(bar.USE_SPELLS) == "table" and bar.USE_SPELLS or {}
	local buff = bar and type(bar.BUFF_FOOD_SPELLS) == "table" and bar.BUFF_FOOD_SPELLS or {}
	return uses, buff
end

-- What one aura restores: "food", "drink", "both" or nil; and whether it
-- is food that gives Well Fed.
function M.MealKind(aura)
	if type(aura) ~= "table" then return nil end
	local id, name = Plain(aura.spellId), Plain(aura.name)
	local uses, buff = Lists()
	local isBuff = type(id) == "number" and buff[id] and true or false
	if type(id) == "number" and uses[id] then return uses[id], isBuff end
	local known = Names()
	if id == FOOD_SPELL or (type(name) == "string" and name == known.food) then return "food", isBuff end
	if id == DRINK_SPELL or (type(name) == "string" and name == known.drink) then return "drink", false end
	return nil
end

-- The meal on you now: { food, drink, buff }, or nil (none, or not
-- readable).
function M.ReadMeal()
	local auras = C_UnitAuras
	if not (auras and auras.GetAuraDataByIndex) then return nil end
	local found
	for index = 1, 80 do
		local ok, aura = pcall(auras.GetAuraDataByIndex, "player", index, "HELPFUL")
		if not ok or Secret(aura) then return nil end
		if type(aura) ~= "table" then break end
		local kind, isBuff = M.MealKind(aura)
		if kind then
			found = found or {}
			if kind == "food" or kind == "both" then found.food = true end
			if kind == "drink" or kind == "both" then found.drink = true end
			if isBuff then found.buff = true end
		end
	end
	return found
end

-- Is this part full? nil when the game keeps a number secret.
local function Full(current, maximum)
	current, maximum = Plain(current), Plain(maximum)
	if type(current) ~= "number" or type(maximum) ~= "number" then return nil end
	return maximum <= 0 or current >= maximum
end

local function ManaUser()
	local mana = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
	local ok, maximum = pcall(UnitPowerMax, "player", mana)
	maximum = ok and Plain(maximum)
	return type(maximum) == "number" and maximum > 0, mana
end

-- True once everything the meal restores is full. Well Fed counts from
-- when the buff food started, not from the drink before it.
function M.MealIsDone(state, now)
	if not state then return false end
	if now - (state.changed or now) < SETTLE then return false end
	if state.buff and now - (state.buffSince or now) < WELL_FED_DELAY then return false end
	if state.food then
		local full = Full(UnitHealth("player"), UnitHealthMax("player"))
		if not full then return false end
	end
	if state.drink then
		local user, mana = ManaUser()
		if user then
			local full = Full(UnitPower("player", mana), UnitPowerMax("player", mana))
			if not full then return false end
		end
	end
	return true
end

function M:MealSignal()
	E:PlayMedia(self.db.mealDoneSound, "Master")
	if self.db.mealDoneFlash and FlashClientIcon then FlashClientIcon() end
end

local function CheckMeal()
	if not (meal and not meal.done) then return end
	if InCombatLockdown() then return end
	if M.MealIsDone(meal, GetTime()) then
		meal.done = true
		E.Ticker:Unsubscribe(TICK)
		M:MealSignal()
	end
end

function M:StopMeal()
	meal = nil
	E.Ticker:Unsubscribe(TICK)
end

-- From your own aura changes, and once more when combat ends (an aura that
-- went in combat was not read then): a meal starts, grows (a drink after
-- the food, buff food after a drink) or ends.
function M:UpdateMeal()
	if not (self.active and self.db.mealDone) then
		self:StopMeal()
		return
	end
	if InCombatLockdown() then return end
	local found = M.ReadMeal()
	if not found then
		self:StopMeal()
		return
	end
	local now = GetTime()
	if not meal then meal = { changed = now } end
	local grows = (found.food and not meal.food) or (found.drink and not meal.drink) or (found.buff and not meal.buff)
	if grows then
		-- Something new to fill: the next signal is for it.
		meal.done, meal.changed = nil, now
	end
	if found.buff and not meal.buff then meal.buffSince = now end
	if not found.buff then meal.buffSince = nil end
	meal.food, meal.drink, meal.buff = found.food, found.drink, found.buff
	if not meal.done and not E.Ticker:IsSubscribed(TICK) then E.Ticker:Subscribe(TICK, PERIOD, CheckMeal, self) end
	CheckMeal()
end

M.MealState = function() return meal end -- tools/qol/test_meal_done.lua

-- This part's place in the module's life cycle (Modules/QoL.lua, AddPart).
M:AddPart("MealDone", {
	enable = function(self)
		self:RegisterUnitEvent("UNIT_AURA", "player", function() M:UpdateMeal() end)
		E:RegisterEvent("PLAYER_REGEN_ENABLED", function() M:UpdateMeal() end, OWNER)
		self:UpdateMeal()
	end,
	disable = function(self)
		E:UnregisterEvent("PLAYER_REGEN_ENABLED", OWNER)
		self:StopMeal()
	end,
	profile = function(self) self:UpdateMeal() end,
})

M:AddOptions(E.Key("Sound and misc"), {
	{ type = "header", label = "Eating and drinking" },
	{ type = "toggle", key = "mealDone", label = "Signal when the meal is done",
		desc = "While you eat or drink: a sound and a flash of the game in the taskbar once your health and mana are full, so you know when to get up. Food that gives Well Fed waits for the buff. Once per meal, out of combat only." },
	{ type = "media", key = "mealDoneSound", label = "Sound", mediaKind = "sound", none = true, dependsOn = "mealDone",
		desc = "The sound when your meal is done. None for silence." },
	{ type = "toggle", key = "mealDoneFlash", label = "Taskbar flash", dependsOn = "mealDone",
		desc = "The game's button in the taskbar flashes while the game is in the background." },
	{ type = "execute", label = "Test", dependsOn = "mealDone", desc = "Plays the signal now.",
		func = function() M:MealSignal() end },
})
