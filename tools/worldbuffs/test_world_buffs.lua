-- Offline test for the World Buffs module (review verbesserungen.md, B4).
-- Run from the repository root:
--   lua5.1 tools/worldbuffs/test_world_buffs.lua
-- It loads EldoUI/Modules/WorldBuffs.lua as it is, with stand-ins for the
-- aura and spell API, the group, the Info Bar and the Ready Check Report.
-- Checked: which auras count (by ID, by the client's name for a listed ID,
-- secret ones never), the time left and the order; other members only out
-- of combat; the Info Bar text and tooltip; the warning before a buff runs
-- out (once per buff, not in combat, not when off); the Ready Check Report
-- column; the module's events.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/worldbuffs/") or "./"

local function ReadFile(path)
	local file = assert(io.open(ROOT .. path, "rb"), "can't open " .. path)
	local text = file:read("*a")
	file:close()
	return (text:gsub("\r\n", "\n"))
end
local chunk = assert(loadstring(ReadFile("EldoUI/Modules/WorldBuffs.lua"), "=WorldBuffs.lua"))

---------------------------------------------------------------------------
-- The game
---------------------------------------------------------------------------
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
local world

local NAMES = { [22888] = "Rallying Cry of the Dragonslayer", [15366] = "Songflower Serenade", [16609] = "Warchief's Blessing",
	[24425] = "Spirit of Zandalar" }
C_Spell = { GetSpellName = function(id) return NAMES[id] end }
C_UnitAuras = { GetAuraDataByIndex = function(unit, index, filter)
	assert(filter == "HELPFUL")
	local list = world.auras[unit]
	if list == SECRET then return SECRET end
	return list and list[index] or nil
end }
function GetTime() return world.now end
function InCombatLockdown() return world.combat end
function IsInRaid() return world.raid end
function IsInGroup() return world.group ~= nil end
function GetNumGroupMembers() return world.group and #world.group + 1 or 0 end
function GetNumSubgroupMembers() return world.group and #world.group or 0 end
function UnitIsUnit(a, b) return a == b or (world.raid and a == "raid" .. (#world.group + 1) and b == "player") end
function UnitName(unit)
	local index = tonumber(unit:match("(%d+)$"))
	return index and world.group and world.group[index] or (unit == "player" and "Me" or nil)
end

local function Aura(id, name, left)
	return { spellId = id, name = name, expirationTime = left and (world.now + left) or 0 }
end

local function Setup(options)
	options = options or {}
	world = { now = 1000, combat = false, auras = {}, printed = {}, events = {}, unitEvents = {}, ticker = {},
		group = options.group, raid = options.raid }
	local L = setmetatable({}, { __index = function(_, key) return key end })
	local report = { columns = {} }
	function report:AddColumn(column) table.insert(self.columns, column) end
	local test = { report = report }
	local E = { L = L, UIKit = { TipPair = function(tooltip, left, right) tooltip:AddLine(left .. ": " .. right) end },
		Ticker = {
			Subscribe = function(_, key, period, fn, owner) world.ticker[key] = { period = period, fn = fn, owner = owner } end,
			Unsubscribe = function(_, key) world.ticker[key] = nil end,
		} }
	function E.Secret(value) return value == SECRET end
	function E:TextHex() return "|cff999999" end
	function E:Print(text) table.insert(world.printed, text) end
	function E:GetModule(name) if name == "ReadyReport" then return report end end
	function E:RegisterDataText(name, definition) test.block = definition test.blockName = name end
	function E:RegisterUnitEvent(event, unit, fn, owner) world.unitEvents[event] = { unit = unit, fn = fn, owner = owner } end
	function E:NewModule(name, def)
		local M = { name = name, title = def.title, category = def.category, defaults = def.defaults, active = true, db = {} }
		for key, value in pairs(def.defaults) do M.db[key] = value end
		function M:RegisterEvent(event, fn) world.events[event] = fn end
		test.M = M
		return M
	end
	chunk(nil, E)
	return test
end

local function NewTooltip()
	local tooltip = { lines = {} }
	function tooltip:AddLine(text) table.insert(self.lines, text) end
	return tooltip
end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
local passed, failed = 0, 0
local function Check(ok, what)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. what) end
end

-- Which auras count.
do
	local test = Setup()
	local M = test.M
	Check(M.title == "World Buffs" and M.category == "Group", "module title and category")
	Check(M.db.warn == true and M.db.warnMinutes == 5 and M.db.readyColumn == false, "defaults")
	Check(M.Kind({ spellId = 22888, name = "x" }) == "DRAGONSLAYER", "by spell ID")
	Check(M.Kind({ spellId = 1300001, name = "Songflower Serenade" }) == "SONGFLOWER", "another ID, the client's name: still counts")
	Check(M.Kind({ spellId = 23768, name = "Sayge's Dark Fortune of Damage" }) == "DARKMOON", "every Darkmoon fortune by ID")
	Check(M.Kind({ spellId = 1243, name = "Power Word: Fortitude" }) == nil, "a class buff is no world buff")
	Check(M.Kind({ spellId = SECRET, name = SECRET }) == nil, "secret ID and name: not counted")
	Check(M.Kind({ spellId = SECRET, name = "Warchief's Blessing" }) == "WARCHIEF", "secret ID, readable name: counts by name")
end

-- Reading a unit.
do
	local test = Setup({ group = { "Ann", "Bob" } })
	local M = test.M
	world.auras.player = { Aura(1243, "Power Word: Fortitude", 1800), Aura(22888, "Rallying Cry of the Dragonslayer", 5400),
		Aura(15366, "Songflower Serenade", 840), Aura(24425, "Spirit of Zandalar", nil) }
	local list = M.Read("player")
	Check(list and #list == 3, "three world buffs, the class buff left out")
	Check(list[1].key == "SONGFLOWER" and list[1].left == 840 and list[2].key == "DRAGONSLAYER", "shortest time first")
	Check(list[3].key == "ZANDALAR" and list[3].left == nil, "a buff without an end time: no time, last")
	world.combat = true
	local mine = M.Read("player")
	local other, why = M.Read("party1")
	Check(mine and #mine == 3, "in combat: your own still read")
	Check(other == nil and why == "combat", "in combat: other members not read")
	world.combat = false
	world.auras.party1 = SECRET
	local secret, reason = M.Read("party1")
	Check(secret == nil and reason == "restricted", "a secret aura: unreadable, not compared")
	Check(M.Duration(5400) == "1h 30m" and M.Duration(840) == "14m" and M.Duration(45) == "45s", "durations")
end

-- The Info Bar block.
do
	local test = Setup({ group = { "Ann", "Bob" } })
	local M, block = test.M, test.block
	Check(test.blockName == "WorldBuffs" and block.title == "World buffs", "the Info Bar block is registered")
	Check(block.text() == "|cff999999" .. "0|r", "no world buffs: a gray 0")
	world.auras.player = { Aura(22888, "Rallying Cry of the Dragonslayer", 5400), Aura(15366, "Songflower Serenade", 840) }
	Check(block.text() == "2  14m", "count and the shortest time (got " .. tostring(block.text()) .. ")")
	world.auras.party1 = { Aura(22888, "Rallying Cry of the Dragonslayer", 5000) }
	world.auras.party2 = { Aura(22888, "Rallying Cry of the Dragonslayer", 5000), Aura(16609, "Warchief's Blessing", 3000) }
	local tooltip = NewTooltip()
	block.tooltip(tooltip)
	local text = table.concat(tooltip.lines, "\n")
	Check(text:find("Songflower Serenade: 14m", 1, true) and text:find("Rallying Cry of the Dragonslayer: 1h 30m", 1, true),
		"tooltip: each of yours with its time")
	Check(text:find("Group", 1, true) and text:find("Bob: 2\nAnn: 1", 1, true), "tooltip: the group, most first")
	world.combat = true
	tooltip = NewTooltip()
	block.tooltip(tooltip)
	Check(table.concat(tooltip.lines, "\n"):find("Buffs are read out of combat only.", 1, true), "in combat: the group waits")
	world.combat = false
	world.auras.player = {}
	tooltip = NewTooltip()
	block.tooltip(tooltip)
	Check(tooltip.lines[1] == "You have no world buffs.", "none: says so")
	M.active = false
	Check(block.text() == "|cff999999Off|r", "module off: the block says Off")
end

-- The warning.
do
	local test = Setup()
	local M = test.M
	M:OnEnable()
	Check(world.unitEvents.UNIT_AURA and world.unitEvents.UNIT_AURA.unit == "player", "UNIT_AURA for you only")
	Check(world.events.PLAYER_REGEN_ENABLED and world.ticker["WorldBuffs:warn"] and world.ticker["WorldBuffs:warn"].period == 30,
		"after combat and every 30 s")
	world.auras.player = { Aura(15366, "Songflower Serenade", 240), Aura(22888, "Rallying Cry of the Dragonslayer", 900) }
	world.unitEvents.UNIT_AURA.fn()
	Check(#world.printed == 1 and world.printed[1] == "Songflower Serenade runs out in 4m.", "a buff with 4 min left: one line (got "
		.. tostring(world.printed[1]) .. ")")
	world.ticker["WorldBuffs:warn"].fn()
	Check(#world.printed == 1, "the same buff: no second line")
	world.auras.player[1] = Aura(15366, "Songflower Serenade", 200) -- taken again: a new end time
	world.auras.player[1].expirationTime = world.now + 120
	world.ticker["WorldBuffs:warn"].fn()
	Check(#world.printed == 2, "a buff taken again warns again")
	world.auras.player = { Aura(16609, "Warchief's Blessing", 100) }
	world.combat = true
	M:CheckWarnings()
	Check(#world.printed == 2, "in combat: no warning")
	world.combat = false
	world.events.PLAYER_REGEN_ENABLED()
	Check(#world.printed == 3, "after combat: the warning comes")
	world.auras.player = { Aura(24425, "Spirit of Zandalar", 60) }
	M.db.warn = false
	M:CheckWarnings()
	Check(#world.printed == 3, "warning off: nothing")
	M:OnDisable()
	Check(world.ticker["WorldBuffs:warn"] == nil, "module off: the ticker stops")
end

-- The Ready Check Report column.
do
	local test = Setup({ group = { "Ann" } })
	local M, column = test.M, test.report.columns[1]
	Check(column and column.key == "worldbuffs" and column.title == "World buffs", "the column is added")
	Check(column.shown() == false, "off by default")
	M.db.readyColumn = true
	Check(column.shown() == true, "on with the setting")
	world.auras.party1 = { Aura(22888, "Rallying Cry of the Dragonslayer", 5000), Aura(15366, "Songflower Serenade", 3000) }
	Check(column.value({ unit = "party1" }) == 2 and column.text({ unit = "party1" }) == "2", "a member with two world buffs")
	world.auras.party1 = {}
	Check(column.text({ unit = "party1" }) == "|cff999999" .. "0|r", "none: a gray 0")
	world.combat = true
	Check(column.value({ unit = "party1" }) == -1 and column.text({ unit = "party1" }) == "|cff999999?|r", "unreadable: ?")
	M.active = false
	Check(column.shown() == false, "module off: no column")
end

print(("%d checks passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
