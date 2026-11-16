-- Offline test for the signal when eating and drinking are done (Quality
-- of Life > Sound and misc; review verbesserungen.md, B6).
-- Run from the repository root:
--   lua5.1 tools/qol/test_meal_done.lua
-- It loads EldoUI/Modules/QoL/MealDone.lua as it is, with stand-ins for the
-- QoL module, the Consumable Bar's spell lists, the aura and spell API,
-- your health and mana, the clock, the shared ticker and the sound.
-- Checked: which auras are a meal (the client's own names for Food and
-- Drink, in German here, and the Consumable Bar's use spells; the English
-- names without the spell API, the client's names read once), secret ones
-- never; food waits for full health, drinks for full mana (a class without
-- mana after a second), rations for both, buff food also for Well Fed's 10
-- seconds counted from the buff food, also after a drink; food and drink
-- from one key press are one meal; one signal per meal, a new one when a
-- drink or buff food joins a finished meal; nothing in combat, a meal that
-- ended in combat is gone when combat ends (no late signal, no stale
-- meal), nothing with a secret number, nothing after the meal ends early;
-- the ticker runs only during a meal; switch, sound, taskbar flash and the
-- Test button; its own owner for the end of combat; defaults, Minimal and
-- options.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/qol/") or "./"

local function ReadFile(path)
	local file = assert(io.open(ROOT .. path, "rb"), "can't open " .. path)
	local text = file:read("*a")
	file:close()
	return (text:gsub("\r\n", "\n"))
end
local chunk = assert(loadstring(ReadFile("EldoUI/Modules/QoL/MealDone.lua"), "=MealDone.lua"))

---------------------------------------------------------------------------
-- The game (a German client: Food is "Essen", Drink is "Trinken")
---------------------------------------------------------------------------
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
local world

local NAMES = { [433] = "Essen", [430] = "Trinken" }
local nameCalls = 0
C_Spell = { GetSpellName = function(id) nameCalls = nameCalls + 1 return NAMES[id] end }
local SPELL_API = C_Spell
C_UnitAuras = { GetAuraDataByIndex = function(unit, index, filter)
	assert(unit == "player" and filter == "HELPFUL")
	if world.auras == SECRET then return SECRET end
	return world.auras[index]
end }
Enum = { PowerType = { Mana = 0 } }
function GetTime() return world.now end
function InCombatLockdown() return world.combat end
function UnitHealth() return world.health end
function UnitHealthMax() return world.healthMax end
function UnitPower(_, kind) assert(kind == 0) return world.mana end
function UnitPowerMax(_, kind) assert(kind == 0) return world.manaMax end
function FlashClientIcon() world.flashes = world.flashes + 1 end

-- The Consumable Bar's lists (Modules/ConsumableBar.lua): a ration, a
-- Nutritious drink and food, and a buff food named "Essen".
local BAR = {
	USE_SPELLS = { [18071] = "both", [1249906] = "drink", [1248377] = "food" },
	BUFF_FOOD_SPELLS = { [5004] = true, [1248377] = true },
}

local function Setup(options)
	options = options or {}
	world = { now = 100, combat = false, auras = {}, health = 50, healthMax = 100, mana = 40, manaMax = 100,
		ticker = {}, sounds = {}, flashes = 0, unitEvents = {}, events = {} }
	local L = setmetatable({}, { __index = function(_, key) return key end })
	local test = { parts = {}, options = {} }
	local M = { name = "QoL", active = true, defaults = {}, db = {} }
	function M:AddPart(name, hooks) test.parts[name] = hooks end
	function M:AddOptions(tab, rows) for _, row in ipairs(rows) do table.insert(test.options, { tab = tab, row = row }) end end
	function M:RegisterUnitEvent(event, unit, fn) world.unitEvents[event] = { unit = unit, fn = fn } end
	local minimal = { key = "Minimal", settings = {} }
	local E = { L = L, styles = { QoL = { minimal } }, Ticker = {
		Subscribe = function(_, key, period, fn, owner) world.ticker[key] = { period = period, fn = fn, owner = owner } end,
		Unsubscribe = function(_, key) world.ticker[key] = nil end,
		IsSubscribed = function(_, key) return world.ticker[key] ~= nil end,
	} }
	function E.Plain(value) if value == SECRET then return nil end return value end
	function E.Secret(value) return value == SECRET end
	function E.Key(text) return text end
	function E:GetModule(name)
		if name == "QoL" then return M end
		if name == "ConsumableBar" and not options.noBar then return BAR end
	end
	function E:PlayMedia(id, channel) table.insert(world.sounds, { id = id, channel = channel }) end
	function E:RegisterEvent(event, fn, owner) world.events[event] = { fn = fn, owner = owner } end
	function E:UnregisterEvent(event, owner)
		if world.events[event] and world.events[event].owner == owner then world.events[event] = nil end
	end
	chunk(nil, E)
	for key, value in pairs(M.defaults) do M.db[key] = value end
	test.M, test.minimal = M, minimal
	test.parts.MealDone.enable(M)
	return test
end

local function Aura(id, name) return { spellId = id, name = name } end
local function AuraEvent() world.unitEvents.UNIT_AURA.fn() end
local function CombatEnds()
	world.combat = false
	if world.events.PLAYER_REGEN_ENABLED then world.events.PLAYER_REGEN_ENABLED.fn() end
end
-- Time passes on the ticker, a quarter second at a time.
local function Wait(seconds)
	local stop = world.now + seconds
	while world.now < stop do
		world.now = world.now + 0.25
		local sub = world.ticker["QoL:mealDone"]
		if sub then sub.fn(0.25) end
	end
end
local function Signals() return #world.sounds end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
local passed, failed = 0, 0
local function Check(ok, what)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. what) end
end
local function Is(got, want, what)
	Check(got == want, what .. " (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
end

-- Defaults, presets, options, events.
do
	local test = Setup()
	local M = test.M
	Check(M.defaults.mealDone == true and M.defaults.mealDoneFlash == true and M.defaults.mealDoneSound == "eldo:EldoChime", "defaults")
	Check(test.minimal.settings.mealDone == false, "Minimal turns it off")
	local keys = {}
	for _, entry in ipairs(test.options) do
		Check(entry.tab == "Sound and misc", "every row on the Sound and misc tab")
		if entry.row.key then keys[entry.row.key] = entry.row end
	end
	Check(keys.mealDone and keys.mealDone.type == "toggle", "the switch")
	Check(keys.mealDoneSound and keys.mealDoneSound.type == "media" and keys.mealDoneSound.none == true, "a sound choice with None")
	Check(keys.mealDoneFlash and keys.mealDoneFlash.type == "toggle", "the taskbar flash switch")
	Is(world.unitEvents.UNIT_AURA and world.unitEvents.UNIT_AURA.unit, "player", "your own auras only")
	local regen = world.events.PLAYER_REGEN_ENABLED
	Check(regen and regen.owner ~= M and type(regen.owner) == "string", "the end of combat under its own owner, not the module's")
	Check(next(world.ticker) == nil, "no meal: no ticker")
end

-- Which auras are a meal.
do
	local M = Setup().M
	Is(M.MealKind(Aura(1127, "Essen")), "food", "plain food by the client's name, any rank")
	Is(M.MealKind(Aura(1137, "Trinken")), "drink", "plain water by the client's name")
	Is(M.MealKind(Aura(18071, "Enriched Manna Biscuit")), "both", "a ration by its use spell")
	Is(M.MealKind(Aura(1249906, "Nutritious Drink")), "drink", "a Nutritious drink")
	local kind, buff = M.MealKind(Aura(5004, "Essen"))
	Check(kind == "food" and buff == true, "buff food: food, and it gives Well Fed")
	kind, buff = M.MealKind(Aura(1248377, "Nutritious Meal"))
	Check(kind == "food" and buff == true, "Nutritious food: food with Well Fed")
	Is(M.MealKind(Aura(1243, "Machtwort: Seelenstärke")), nil, "a class buff is no meal")
	Is(M.MealKind(Aura(SECRET, SECRET)), nil, "secret ID and name: no meal")
	Is(M.MealKind(Aura(433, "Food")), "food", "the base Food spell by ID")
	local noBar = Setup({ noBar = true }).M
	Is(noBar.MealKind(Aura(1127, "Essen")), "food", "without the Consumable Bar's lists: names still work")
	Is(noBar.MealKind(Aura(18071, "Enriched Manna Biscuit")), nil, "without its lists: rations unknown, no error")
	-- The client's names are read once.
	local cached = Setup().M
	cached.MealKind(Aura(1127, "Essen"))
	local calls = nameCalls
	for _ = 1, 5 do cached.MealKind(Aura(1137, "Trinken")) cached.MealKind(Aura(1243, "x")) end
	Is(nameCalls, calls, "the names are read once, not on every aura")
end

-- Without the spell API: the English names stand in.
do
	C_Spell = nil
	local M = Setup().M
	Is(M.MealKind(Aura(1127, "Food")), "food", "no spell API: plain food by its English name")
	Is(M.MealKind(Aura(1137, "Drink")), "drink", "no spell API: water by its English name")
	C_Spell = SPELL_API
end

-- Food: waits for full health, one signal.
do
	local test = Setup()
	world.auras = { Aura(1127, "Essen") }
	AuraEvent()
	Check(world.ticker["QoL:mealDone"] ~= nil and world.ticker["QoL:mealDone"].period == 0.25, "eating: the ticker runs")
	Wait(3)
	Is(Signals(), 0, "health not full: no signal")
	world.health = 100
	Wait(0.25)
	Is(Signals(), 1, "full health: one signal")
	Is(world.sounds[1].id, "eldo:EldoChime", "the chosen sound")
	Is(world.sounds[1].channel, "Master", "on the master channel")
	Is(world.flashes, 1, "the taskbar flashes")
	Check(world.ticker["QoL:mealDone"] == nil, "done: the ticker stops")
	AuraEvent()
	Wait(2)
	Is(Signals(), 1, "still eating: no second signal")
	world.auras = {}
	AuraEvent()
	Check(test.M.MealState() == nil, "the meal ends with the aura")
	world.health = 60
	world.auras = { Aura(1127, "Essen") }
	AuraEvent()
	world.health = 100
	Wait(1)
	Is(Signals(), 2, "the next meal has its own signal")
end

-- Drinks: mana; a class without mana at once.
do
	Setup()
	world.health = 30
	world.auras = { Aura(1137, "Trinken") }
	AuraEvent()
	Wait(1)
	Is(Signals(), 0, "drinking, mana not full: no signal (health does not matter)")
	world.mana = 100
	Wait(0.25)
	Is(Signals(), 1, "full mana: signal")

	Setup()
	world.manaMax = 0
	world.auras = { Aura(1137, "Trinken") }
	AuraEvent()
	Is(Signals(), 0, "no mana to fill: not at the very start (food may follow)")
	Wait(1)
	Is(Signals(), 1, "no mana to fill: signal after a second")
end

-- Rations need both; a drink that joins a finished meal gets its own.
do
	Setup()
	world.auras = { Aura(18071, "Enriched Manna Biscuit") }
	AuraEvent()
	world.health = 100
	Wait(1)
	Is(Signals(), 0, "ration: full health alone is not enough")
	world.mana = 100
	Wait(0.25)
	Is(Signals(), 1, "ration: both full, signal")

	Setup()
	world.auras = { Aura(1127, "Essen") }
	AuraEvent()
	world.health = 100
	Wait(1)
	Is(Signals(), 1, "food done")
	world.auras = { Aura(1127, "Essen"), Aura(1137, "Trinken") }
	AuraEvent()
	Wait(1)
	Is(Signals(), 1, "a drink joins: waits for mana")
	world.mana = 100
	Wait(0.25)
	Is(Signals(), 2, "mana full: the drink's signal")
end

-- Buff food waits for Well Fed.
do
	Setup()
	world.health = 100
	world.auras = { Aura(5004, "Essen") }
	AuraEvent()
	Wait(10)
	Is(Signals(), 0, "buff food at full health: waits for Well Fed")
	Wait(0.75)
	Is(Signals(), 1, "after 10 seconds: signal")
end

-- Food and drink from one key press are one meal.
do
	Setup()
	world.health = 100
	world.auras = { Aura(1127, "Essen") }
	AuraEvent()
	world.auras = { Aura(1127, "Essen"), Aura(1137, "Trinken") }
	AuraEvent()
	Wait(1)
	Is(Signals(), 0, "full health, the drink's aura a moment later: no signal for the food alone")
	world.mana = 100
	Wait(0.25)
	Is(Signals(), 1, "mana full: one signal for the whole meal")
end

-- Well Fed counts from the buff food, also when a drink came first.
do
	Setup()
	world.health = 100
	world.auras = { Aura(1137, "Trinken") }
	AuraEvent()
	Wait(15)
	Is(Signals(), 0, "drinking, mana not full")
	world.auras = { Aura(1137, "Trinken"), Aura(5004, "Essen") }
	AuraEvent()
	Wait(2)
	world.mana = 100
	Wait(5)
	Is(Signals(), 0, "mana full 2 s after the buff food: still waits for Well Fed")
	Wait(3.75)
	Is(Signals(), 1, "10.5 s after the buff food: signal")

	Setup()
	world.health = 100
	world.auras = { Aura(1137, "Trinken") }
	AuraEvent()
	world.mana = 100
	Wait(1)
	Is(Signals(), 1, "the drink's signal")
	Wait(20)
	world.auras = { Aura(1137, "Trinken"), Aura(5004, "Essen") }
	AuraEvent()
	Wait(5)
	Is(Signals(), 1, "buff food after a finished drink: waits for Well Fed")
	Wait(5.75)
	Is(Signals(), 2, "then its own signal")
end

-- A meal that ends in combat.
do
	Setup()
	world.auras = { Aura(1127, "Essen") }
	AuraEvent()
	world.combat = true
	world.auras = {}
	AuraEvent()
	CombatEnds()
	Check(world.ticker["QoL:mealDone"] == nil, "combat ends: the meal that ended in it is gone, the ticker too")
	world.health = 100
	Wait(2)
	Is(Signals(), 0, "health fills by itself afterwards: no signal")

	Setup()
	world.auras = { Aura(1127, "Essen") }
	AuraEvent()
	world.health = 100
	Wait(1)
	Is(Signals(), 1, "the first meal's signal")
	world.combat = true
	world.auras = {}
	AuraEvent()
	CombatEnds()
	world.health = 50
	world.auras = { Aura(1127, "Essen") }
	AuraEvent()
	world.health = 100
	Wait(1)
	Is(Signals(), 2, "a done meal that ended in combat does not swallow the next one")
end

-- Combat, secrets, a meal that ends early.
do
	Setup()
	world.auras = { Aura(1127, "Essen") }
	AuraEvent()
	world.combat = true
	world.health = 100
	Wait(1)
	Is(Signals(), 0, "in combat: nothing checked")
	CombatEnds()
	Wait(0.25)
	Is(Signals(), 1, "after combat, still eating: the signal")

	Setup()
	world.auras = { Aura(1127, "Essen") }
	AuraEvent()
	world.health = SECRET
	Wait(1)
	Is(Signals(), 0, "secret health: no signal, nothing compared")
	world.health = 100
	Wait(0.25)
	Is(Signals(), 1, "readable again: signal")

	Setup()
	world.auras = SECRET
	AuraEvent()
	Check(world.ticker["QoL:mealDone"] == nil, "secret auras: no meal")

	Setup()
	world.combat = true
	world.auras = { Aura(1127, "Essen") }
	AuraEvent()
	Check(world.ticker["QoL:mealDone"] == nil, "an aura change in combat: not read")

	Setup()
	world.auras = { Aura(1127, "Essen") }
	AuraEvent()
	Wait(1)
	world.auras = {}
	AuraEvent()
	world.health = 100
	Wait(1)
	Is(Signals(), 0, "stood up early: no signal")
	Check(world.ticker["QoL:mealDone"] == nil, "stood up early: the ticker stops")
end

-- Switch, sound, flash, Test, module off.
do
	local test = Setup()
	local M = test.M
	M.db.mealDone = false
	world.auras = { Aura(1127, "Essen") }
	AuraEvent()
	world.health = 100
	Wait(1)
	Is(Signals(), 0, "switched off: no signal")
	Check(world.ticker["QoL:mealDone"] == nil, "switched off: no ticker")

	test = Setup()
	M = test.M
	world.auras = { Aura(1127, "Essen") }
	AuraEvent()
	M.db.mealDone = false
	test.parts.MealDone.profile(M)
	Check(world.ticker["QoL:mealDone"] == nil and M.MealState() == nil, "switched off during a meal: it stops")

	test = Setup()
	M = test.M
	M.db.mealDoneSound, M.db.mealDoneFlash = "none", false
	world.auras = { Aura(1127, "Essen") }
	AuraEvent()
	world.health = 100
	Wait(1)
	Check(world.sounds[1] and world.sounds[1].id == "none" and world.flashes == 0, "sound None and no flash: silent (the media player skips None)")

	test = Setup()
	M = test.M
	local testRow
	for _, entry in ipairs(test.options) do if entry.row.type == "execute" then testRow = entry.row end end
	testRow.func()
	Is(Signals(), 1, "Test plays the signal")
	Is(world.flashes, 1, "Test flashes the taskbar")

	test = Setup()
	M = test.M
	world.auras = { Aura(1127, "Essen") }
	AuraEvent()
	M.active = false
	test.parts.MealDone.disable(M)
	Check(world.ticker["QoL:mealDone"] == nil and M.MealState() == nil, "module off: the meal and ticker end")
	Check(world.events.PLAYER_REGEN_ENABLED == nil, "module off: the end-of-combat handler goes too")
end

print(("%d checks passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
