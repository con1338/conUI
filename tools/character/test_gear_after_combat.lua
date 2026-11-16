-- Offline test for "Equip after combat" (Character > Gear sets; review
-- verbesserungen.md, B12).
-- Run from the repository root:
--   lua5.1 tools/character/test_gear_after_combat.lua
-- It cuts the gear set section out of EldoUI/Modules/Character.lua (from
-- "local gear" to the slot flyout) and runs it as it is, with stand-ins for
-- the helpers before it, the equipment set API, the combat lockdown, death,
-- events, the error frame, the info bar block, its menu and tooltips.
-- Checked: with the switch off a click in combat only says no; with it on
-- the set is kept and goes on when combat ends, the last click counts, a
-- second click or a click on the worn set takes it back, a click out of
-- combat wins; dead at the end of combat it waits until you are alive;
-- turned off, gone or already worn in the meantime nothing happens; a
-- failing or secret answer changes nothing; the events are only listened
-- to while a set is kept; the set button's border, the tooltips and the
-- hints; the default and the option.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/character/") or "./"

local function ReadFile(path)
	local file = assert(io.open(ROOT .. path, "rb"), "can't open " .. path)
	local text = file:read("*a")
	file:close()
	return (text:gsub("\r\n", "\n"))
end

local function Between(text, first, last, where)
	local from = text:find(first, 1, true)
	assert(from, where .. ": marker not found: " .. first)
	local to = text:find(last, from + #first, true)
	assert(to, where .. ": end marker not found after " .. first .. ": " .. last)
	return text:sub(from, to - 1)
end

local character = ReadFile("EldoUI/Modules/Character.lua")
local CHUNK = assert(loadstring(table.concat({
	"local E, M, ours, Backdrop, Overlay, ImproveOn, Additions, PaperDollShown, Accent, Usable = ...",
	"local L = E.L",
	Between(character, "local gear = { buttons = {} }", "-- Slot flyout: hover a trinket", "Character.lua"),
	"return EquipSet, GearMenu, gear",
}, "\n"), "=Character.lua gear sets"))

local passed, failed = 0, 0
local function Check(ok, what)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL: " .. what)
	end
end

---------------------------------------------------------------------------
-- The game
---------------------------------------------------------------------------
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
function issecretvalue(value) return value == SECRET end
local world

-- Sets: world.sets[id] = { name, equipped }.
C_EquipmentSet = {
	GetEquipmentSetIDs = function()
		local ids = {}
		for id in pairs(world.sets) do ids[#ids + 1] = id end
		table.sort(ids)
		return ids
	end,
	GetEquipmentSetInfo = function(id)
		local set = world.sets[id]
		if not set then return nil end
		return set.name, 100 + id, id, set.equipped, 10, set.equipped and 10 or 5, 0, 0
	end,
	UseEquipmentSet = function(id)
		if world.useFails then error("can't equip now") end
		table.insert(world.used, id)
		for setID, set in pairs(world.sets) do set.equipped = setID == id end
	end,
}
function InCombatLockdown() return world.combat end
function UnitIsDeadOrGhost(unit) assert(unit == "player") return world.dead end
UIErrorsFrame = { AddMessage = function(_, text, r, g, b) table.insert(world.errors, { text = text, color = { r, g, b } }) end }

local Frame = {}
Frame.__index = Frame
function Frame:SetSize(w, h) self.width, self.height = w, h end
function Frame:SetPoint() end
function Frame:ClearAllPoints() end
function Frame:SetAllPoints() end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:SetShown(on) self.shown = on and true or false end
function Frame:SetTexture(texture) self.texture = texture end
function Frame:SetColorTexture() end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:CreateTexture() return setmetatable({ scripts = {} }, Frame) end
function CreateFrame() return setmetatable({ scripts = {} }, Frame) end
GameTooltip = { lines = {} }
function GameTooltip:SetOwner() self.lines = {} end
function GameTooltip:AddLine(text) table.insert(self.lines, text) end
function GameTooltip:AddDoubleLine(left) table.insert(self.lines, left) end
function GameTooltip:Show() end
function GameTooltip:IsForbidden() return false end
local function Has(lines, text)
	for _, line in ipairs(lines) do
		if line == text then return true end
	end
	return false
end

---------------------------------------------------------------------------
-- EldoUI around the section
---------------------------------------------------------------------------
local test

local function Setup()
	world = { combat = false, dead = false, sets = { [1] = { name = "Tank", equipped = true }, [2] = { name = "Damage" }, [3] = { name = "Fire" } },
		used = {}, errors = {}, printed = {}, events = {}, borders = {} }
	test = {}
	local L = setmetatable({}, { __index = function(_, key) return key end })
	local E = { L = L, pixel = 1, media = { accentColor = { 0, 0.6, 1 }, borderColor = { 0, 0, 0, 1 } },
		tokens = { text = { warn = { 1, 0.8, 0 }, good = { 0.3, 0.9, 0.5 } }, hover = { hud = 0.2 } } }
	function E:IsSecret(value) return value == SECRET end
	function E.FrameCheck() return false end
	function E:RegisterEvent(event, fn, owner) world.events[event .. "|" .. owner] = fn end
	function E:UnregisterEvent(event, owner) world.events[event .. "|" .. owner] = nil end
	function E:RegisterDataText(name, def) test.block = def test.blockName = name end
	function E:TokenColor(kind, alpha)
		if kind == "warn" then return 1, 0.8, 0, alpha end
		if kind == "bad" then return 1, 0.4, 0.4, alpha end
		return 0.6, 0.6, 0.6, alpha
	end
	function E:TextHex() return "|cff999999" end
	function E:TooltipHint(tooltip, hint) tooltip:AddLine(hint[1] .. ": " .. hint[2]) end
	function E:TrimIcon() end
	function E:BindOptionsLink() end
	function E:IsOptionsLinkClick() return false end
	function E:Plural(n, one, other) return n == 1 and one or other end
	E.UIKit = {
		SECONDARY = { 0.6, 0.6, 0.6 },
		TipTitle = function(tooltip, text) tooltip:AddLine(text) end,
		TipText = function(tooltip, text) tooltip:AddLine(text) end,
		TipPair = function(tooltip, left) tooltip:AddLine(left) end,
		ContextMenu = function(owner, fn) test.menu = { owner = owner, fn = fn } end,
	}
	local M = { active = true, db = { gearAfterCombat = false, gearBar = true, gearBarSize = 20 } }
	function M:Print(text) table.insert(world.printed, text) end
	local function Backdrop()
		local bd = {}
		function bd:SetBackdropBorderColor(r, g, b) bd.border = { r, g, b } end
		return bd
	end
	local overlay = CreateFrame()
	local EquipSet, GearMenu, gear = CHUNK(E, M, {}, Backdrop, function() return overlay end,
		function() return true end, function() return true end, function() return true end,
		function() return 0, 0.6, 1 end, function() return true end)
	test.E, test.M, test.EquipSet, test.GearMenu, test.gear = E, M, EquipSet, GearMenu, gear
	CharacterFrame = CreateFrame()
	return M
end

local function Listening()
	local count = 0
	for key in pairs(world.events) do
		if key:find("|Character:gearAfterCombat", 1, true) then count = count + 1 end
	end
	return count
end

local function Fire(event)
	local fn = world.events[event .. "|Character:gearAfterCombat"]
	if fn then fn() end
end

local function EndCombat()
	world.combat = false
	Fire("PLAYER_REGEN_ENABLED")
end

local function LastError() return world.errors[#world.errors] and world.errors[#world.errors].text end

-- The border of a set's button on the character window.
local function Border(M, setID)
	M:UpdateGear()
	for _, button in ipairs(test.gear.buttons) do
		if button.setID == setID then return button.bd.border end
	end
end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
-- Switch off: a click in combat only says no.
do
	local M = Setup()
	local EquipSet = test.EquipSet
	world.combat = true
	Check(EquipSet(2) == false and LastError() == "EldoUI: gear sets change only out of combat.", "off: a click in combat says no")
	Check(M.PendingSet() == nil and Listening() == 0, "off: nothing is kept, nothing listened to")
	EndCombat()
	Check(#world.used == 0, "off: nothing goes on after combat")
	world.combat = false
	Check(EquipSet(2) == true and world.used[1] == 2, "out of combat a click equips at once")
end

-- Switch on: kept, last click counts, taken back.
do
	local M = Setup()
	M.db.gearAfterCombat = true
	local EquipSet = test.EquipSet
	world.combat = true
	EquipSet(2)
	Check(M.PendingSet() == 2 and LastError() == "EldoUI: Damage goes on when combat ends. Click it again to keep your gear.",
		"a click in combat keeps the set and says so")
	Check(world.errors[1].color[2] == 0.9, "in the good color")
	Check(Listening() == 3, "while a set is kept: the end of combat and coming back to life are listened to")
	Check(#world.used == 0, "nothing is equipped in combat")
	local r, g = unpack(Border(M, 2))
	Check(r == 1 and g == 0.8, "the kept set's button has the warning border")
	EquipSet(3)
	Check(M.PendingSet() == 3, "a click on another set: that one is kept")
	EquipSet(3)
	Check(M.PendingSet() == nil and LastError() == "EldoUI: no set change after combat." and Listening() == 0,
		"a second click on it takes it back")
	EquipSet(2)
	EquipSet(1)
	Check(M.PendingSet() == nil and LastError() == "EldoUI: no set change after combat.", "a click on the worn set takes it back")
	local count = #world.errors
	EquipSet(1)
	Check(#world.errors == count and M.PendingSet() == nil, "a click on the worn set with nothing kept: nothing")
	EquipSet(2)
	EndCombat()
	Check(world.used[1] == 2 and #world.used == 1, "combat over: the kept set goes on")
	Check(world.printed[1] == "After combat: equipped Damage.", "with the chat line")
	Check(M.PendingSet() == nil and Listening() == 0, "and nothing is listened to any more")
	EndCombat()
	Check(#world.used == 1, "only once")
end

-- Dead when combat ends.
do
	local M = Setup()
	M.db.gearAfterCombat = true
	world.combat = true
	test.EquipSet(2)
	world.dead = true
	EndCombat()
	Check(#world.used == 0 and M.PendingSet() == 2, "dead when combat ends: the set waits")
	Fire("PLAYER_ALIVE") -- released, now a ghost
	Check(#world.used == 0, "as a ghost: still waiting")
	world.dead = false
	world.combat = true
	Fire("PLAYER_UNGHOST")
	Check(#world.used == 0, "alive but in combat: waiting for its end")
	EndCombat()
	Check(world.used[1] == 2, "alive and out of combat: it goes on")
	world.combat = true
	test.EquipSet(3)
	world.dead = true
	EndCombat()
	world.dead = false
	Fire("PLAYER_ALIVE")
	Check(world.used[2] == 3, "resurrected: it goes on")
	world.combat = true
	test.EquipSet(2)
	world.dead = SECRET
	EndCombat()
	Check(#world.used == 3, "a secret answer about death does not hold it back")
end

-- Changed in the meantime.
do
	local M = Setup()
	M.db.gearAfterCombat = true
	world.combat = true
	test.EquipSet(2)
	M.db.gearAfterCombat = false
	EndCombat()
	Check(#world.used == 0 and M.PendingSet() == nil and Listening() == 0, "switched off in the meantime: dropped")
	M.db.gearAfterCombat = true
	world.combat = true
	test.EquipSet(2)
	world.sets[2] = nil
	EndCombat()
	Check(#world.used == 0 and M.PendingSet() == nil, "the set was deleted: nothing")
	world.combat = true
	test.EquipSet(3)
	world.sets[3].equipped, world.sets[1].equipped = true, false
	EndCombat()
	Check(#world.used == 0, "already worn when combat ends: nothing")
	world.combat = true
	test.EquipSet(1)
	world.useFails = true
	EndCombat()
	Check(#world.used == 0 and M.PendingSet() == nil and #world.printed == 0, "the game refuses: no error, no chat line")
	world.useFails = false
	world.combat = true
	test.EquipSet(1)
	world.combat = false
	test.EquipSet(3)
	Check(M.PendingSet() == nil and Listening() == 0, "a click out of combat wins over the kept set")
	world.sets[2] = { name = SECRET }
	world.combat = true
	test.EquipSet(2)
	Check(M.PendingSet() == nil, "a secret set name: nothing kept")
end

-- Tooltips and hints.
do
	local M = Setup()
	local block = test.block
	Check(test.blockName == "Gear", "the Gear block")
	block.tooltip(GameTooltip)
	Check(Has(GameTooltip.lines, "Click: equip a set (out of combat)"), "switch off: the old hint")
	M.db.gearAfterCombat = true
	world.combat = true
	test.EquipSet(2)
	GameTooltip.lines = {}
	block.tooltip(GameTooltip)
	Check(Has(GameTooltip.lines, "After combat: Damage") and Has(GameTooltip.lines, "Click: equip a set (in combat: when it ends)"),
		"the block names the kept set and the new hint")
	Border(M, 2)
	local button
	for _, candidate in ipairs(test.gear.buttons) do if candidate.setID == 2 then button = candidate end end
	button.scripts.OnEnter(button)
	Check(Has(GameTooltip.lines, "Goes on when combat ends.") and Has(GameTooltip.lines, "Click: equip (in combat: when it ends)"),
		"the set button says it goes on after combat")
	button.scripts.OnClick(button, "LeftButton")
	Check(M.PendingSet() == nil, "a click on its button takes it back")
	test.GearMenu(CharacterFrame)
	Check(test.menu ~= nil, "the block's menu opens")
end

-- The default and the option.
do
	Check(character:find("gearAfterCombat = false,", 1, true) ~= nil, "off by default")
	Check(character:find('{ type = "toggle", acts = true, key = "gearAfterCombat"', 1, true) ~= nil, "an option that says it acts for you")
end

print(("%d checks passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
