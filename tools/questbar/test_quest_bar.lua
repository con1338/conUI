-- Offline test for the Quest Item Bar (Modules/QuestBar.lua; review
-- verbesserungen.md, B5).
-- Run from the repository root:
--   lua5.1 tools/questbar/test_quest_bar.lua
-- It loads EldoUI/Modules/QuestBar.lua as it is, together with EldoUI's own
-- Core/Safe.lua (secret values) and Core/BagCache.lua (the bags), with
-- stand-ins for the bags, the quest log, the item API, frames, the combat
-- lockdown, key bindings, the shared ticker and the cooldown source. A
-- secure button changed in combat counts as blocked, as in the game.
-- Checked: which items get a button (the quest log's items while carried,
-- not for a quest ready to turn in unless the game keeps the item or the
-- setting asks; flagged or Quest-class items with a use or loot inside;
-- quest starters until done or switched off; no potions, no plain quest
-- loot), bag order, one button per item, at most 12; secret and failing
-- answers count as not there; hidden items and "Show hidden items again";
-- the secure attributes, layout and size out of combat only, a change in
-- combat waits for its end, the same items are not applied again; counts,
-- charges, starter mark, key text, cooldowns; the range color only for the
-- quest log's items and only while switched on; the glow for new items only;
-- Shift-right-click; Bind keys; the tooltip; turning the module off; one
-- read per burst of events; key binding names; defaults and options.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/questbar/") or "./"

local function ReadFile(path)
	local file = assert(io.open(ROOT .. path, "rb"), "can't open " .. path)
	local text = file:read("*a")
	file:close()
	return (text:gsub("\r\n", "\n"))
end
local function Load(path) return assert(loadstring(ReadFile(path), "=" .. path:match("[^/]+$"))) end
local SAFE, BAGCACHE, CHUNK = Load("EldoUI/Core/Safe.lua"), Load("EldoUI/Core/BagCache.lua"), Load("EldoUI/Modules/QuestBar.lua")

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

-- Frames. A frame made from a secure template is protected: showing,
-- hiding, moving, sizing it or setting an attribute in combat is blocked.
local Region = {}
Region.__index = Region
function Region:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Region:ClearAllPoints() self.points = {} end
function Region:SetAllPoints() self.points = { { "all" } } end
function Region:SetTexture(texture) self.texture = texture end
function Region:SetDesaturated(desaturated) self.desaturated = desaturated and true or false end
function Region:SetAlpha(alpha) self.alpha = alpha end
function Region:SetVertexColor(r, g, b) self.vertex = { r, g, b } end
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:SetShown(shown) self.shown = shown and true or false end
function Region:IsShown() return self.shown end
function Region:SetText(text) self.text = text ~= nil and tostring(text) or "" end
function Region:GetText() return self.text end
function Region:SetTextColor() end
local function NewRegion() return setmetatable({ points = {}, shown = true, text = "" }, Region) end

local Frame = setmetatable({}, { __index = Region })
Frame.__index = Frame
local function Guard(frame, what)
	if frame.protected and world.combat then table.insert(world.blocked, (frame.name or "?") .. ":" .. what) end
end
function Frame:CreateTexture() return NewRegion() end
function Frame:SetAttribute(name, value)
	Guard(self, "SetAttribute")
	world.attributeSets = world.attributeSets + 1
	self.attributes[name] = value
end
function Frame:GetAttribute(name) return self.attributes[name] end
function Frame:RegisterForClicks(...) self.clicks = { ... } end
function Frame:SetSize(width, height) Guard(self, "SetSize") self.width, self.height = width, height end
function Frame:GetSize() return self.width, self.height end
function Frame:SetPoint(...) Guard(self, "SetPoint") Region.SetPoint(self, ...) end
function Frame:ClearAllPoints() Guard(self, "ClearAllPoints") Region.ClearAllPoints(self) end
function Frame:Show() Guard(self, "Show") self.shown = true end
function Frame:Hide() Guard(self, "Hide") self.shown = false end
function Frame:SetShown(shown) Guard(self, "SetShown") self.shown = shown and true or false end
function Frame:SetFrameStrata() end
function Frame:HookScript(name, fn) self.hooks[name] = fn end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:Clear() self.cleared = (self.cleared or 0) + 1 end
function CreateFrame(kind, name, parent, template)
	local frame = setmetatable({ kind = kind, name = name, parent = parent, attributes = {}, hooks = {}, scripts = {},
		points = {}, shown = true, width = 0, height = 0,
		protected = type(template) == "string" and template:find("Secure", 1, true) ~= nil }, Frame)
	if name then _G[name] = frame end
	return frame
end
UIParent = CreateFrame("Frame", "UIParent")

GameTooltip = { lines = {} }
function GameTooltip:SetOwner() self.lines, self.set = {}, nil end
function GameTooltip:SetQuestLogSpecialItem(index) self.set = "log:" .. index end
function GameTooltip:SetBagItem(bag, slot) self.set = ("bag:%d:%d"):format(bag, slot) end
function GameTooltip:SetItemByID(id) self.set = "id:" .. id end
function GameTooltip:AddLine(text) table.insert(self.lines, text) end
function GameTooltip:Show() end
function GameTooltip:Hide() end
function GameTooltip:IsForbidden() return false end
local function TipHas(text)
	for _, line in ipairs(GameTooltip.lines) do
		if line == text then return true end
	end
	return false
end

-- Items: world.items[id] = { class, spell, count, charges, name, spellError }.
C_Item = {
	GetItemInfoInstant = function(id)
		local item = world.items[id]
		if not item then return nil end
		return id, "type", "subtype", "", 1, item.class, 0
	end,
	GetItemSpell = function(id)
		local item = world.items[id]
		if item and item.spellError then error("item API failed") end
		if item and item.spell then return item.spell, item.spell == SECRET and SECRET or 4000 + id end
	end,
	GetItemCount = function(id)
		local item = world.items[id]
		return item and item.count or 0
	end,
	GetItemIconByID = function(id) return world.items[id] and (9000 + id) or nil end,
	GetItemNameByID = function(id) return world.items[id] and world.items[id].name or nil end,
}

-- Bags: world.bags[bag] = { size = n, [slot] = { id, hasLoot, quest = { isQuestItem, questID, isActive } } }.
NUM_BAG_SLOTS = 4
local function Slot(bag, slot)
	local list = world.bags[bag]
	return list and list[slot] or nil
end
C_Container = {
	GetContainerNumSlots = function(bag) return world.bags[bag] and world.bags[bag].size or 0 end,
	GetContainerItemInfo = function(bag, slot)
		local entry = Slot(bag, slot)
		if not entry then return nil end
		return { itemID = entry.id, hasLoot = entry.hasLoot or false, iconFileID = 1, stackCount = 1 }
	end,
	GetContainerItemID = function(bag, slot)
		local entry = Slot(bag, slot)
		return entry and entry.id or nil
	end,
	GetContainerItemLink = function(bag, slot)
		local entry = Slot(bag, slot)
		return entry and ("|Hitem:%s::|h[x]|h"):format(tostring(entry.id)) or nil
	end,
	GetContainerItemQuestInfo = function(bag, slot)
		local entry = Slot(bag, slot)
		if entry and entry.questInfo == SECRET then return SECRET end
		local quest = entry and entry.quest or {}
		return { isQuestItem = quest.isQuestItem or false, questID = quest.questID, isActive = quest.isActive or false }
	end,
}

-- Quest log: world.log[index] = { questID, header, complete, special = { id, charges, showWhenComplete } }.
local function Link(id) return ("|cffffffff|Hitem:%d::::::::|h[Item]|h|r"):format(id) end
C_QuestLog = {
	GetNumQuestLogEntries = function() return #world.log, #world.log end,
	GetInfo = function(index)
		local quest = world.log[index]
		if not quest then return nil end
		return { questID = quest.questID, isHeader = quest.header or false, title = "Quest" }
	end,
	IsComplete = function(questID)
		for _, quest in ipairs(world.log) do
			if quest.questID == questID then return quest.complete or false end
		end
		return false
	end,
	IsQuestFlaggedCompleted = function(questID) return world.completed[questID] or false end,
	GetLogIndexForQuestID = function(questID)
		for index, quest in ipairs(world.log) do
			if quest.questID == questID then return index end
		end
		return nil
	end,
}
local LOG_INDEX_FOR_QUEST = C_QuestLog.GetLogIndexForQuestID
function GetQuestLogSpecialItemInfo(index)
	local quest = world.log[index]
	local special = quest and quest.special
	if not special then return nil end
	if special.link == SECRET then return SECRET, 1, 1, false end
	return Link(special.id), 1, special.charges or 1, special.showWhenComplete or false
end
function IsQuestLogSpecialItemInRange(index) return world.range[index] end

function InCombatLockdown() return world.combat end
function IsShiftKeyDown() return world.shift end
function GetTime() return world.now end
function GetBindingKey(command) return world.bindings[command] end
function GetBindingText(key) return "K:" .. key end
C_Timer = { After = function(_, fn) table.insert(world.timers, fn) end }
function wipe(t)
	for key in pairs(t) do t[key] = nil end
	return t
end
function geterrorhandler() return function(err) error(err, 2) end end

local function Copy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, item in pairs(value) do copy[key] = Copy(item) end
	return copy
end

---------------------------------------------------------------------------
-- EldoUI around the module
---------------------------------------------------------------------------
local test

local function Setup(options)
	options = options or {}
	world = { now = 100, combat = false, shift = false, items = {}, bags = { [0] = { size = 20 } }, log = {}, completed = {},
		range = {}, bindings = {}, timers = {}, printed = {}, events = {}, coreEvents = {}, ticker = {}, glows = {},
		draws = {}, cooldownSubs = {}, keybind = {}, masqued = {}, combatQueue = {}, blocked = {}, attributeSets = 0,
		moverApplies = 0, reskins = 0, visibilityUpdates = 0, keybindMode = false, moveMode = false, masque = options.masque }
	test = { bindings = {} }
	local L = setmetatable({}, { __index = function(_, key) return key end })
	local E = { L = L, pixel = 1, tokens = { size = { small = 10, label = 12 } }, movers = {}, MASQUE_OPTION_DESC = "Masque." }
	E.UIKit = {
		TipText = function(tooltip, text) tooltip:AddLine(text) end,
		TipTitle = function(tooltip, text) tooltip:AddLine(text) end,
	}
	E.Ticker = {
		Subscribe = function(_, key, period, fn, owner) world.ticker[key] = { period = period, fn = fn, owner = owner } end,
		Unsubscribe = function(_, key) world.ticker[key] = nil end,
		IsSubscribed = function(_, key) return world.ticker[key] ~= nil end,
		UnsubscribeOwner = function(_, owner)
			for key, entry in pairs(world.ticker) do
				if entry.owner == owner then world.ticker[key] = nil end
			end
		end,
	}
	E.CombatKit = { Cooldowns = {
		DrawItem = function(cooldown, itemID, opts)
			table.insert(world.draws, { cooldown = cooldown, id = itemID, hideGCD = opts and opts.hideGCD })
		end,
		Subscribe = function(key, fn) world.cooldownSubs[key] = fn end,
		Unsubscribe = function(key) world.cooldownSubs[key] = nil end,
	} }
	function E:RegisterEvent(event, fn) world.coreEvents[event] = fn end
	function E:NewModule(name, def)
		local M = { name = name, title = def.title, category = def.category, def = def, defaults = def.defaults, active = false }
		M.db = Copy(def.defaults)
		function M:RegisterEvent(event, fn) world.events[event] = fn end
		function M:UnregisterEvent(event) world.events[event] = nil end
		test.M = M
		return M
	end
	function E:VisibilityDefaults() return { preset = "always" } end
	function E:VisibilityOptions(prefix)
		return { { type = "select", key = prefix .. ".show", label = "Show", desc = "When it shows.", values = {} } }
	end
	function E:AttachVisibility(frame, block, opts) world.visibility = { frame = frame, block = block, opts = opts } end
	function E:IsVisibilityAttached(frame) return world.visibility ~= nil and world.visibility.frame == frame end
	function E:UpdateVisibility() world.visibilityUpdates = world.visibilityUpdates + 1 end
	function E:DetachVisibility() world.visibility = nil end
	function E:RegisterGlowUser(key, info) test.glowUser = { key = key, info = info } end
	function E:ShowUserGlow(frame, key) table.insert(world.glows, { frame = frame, key = key }) end
	function E:HideGlow(frame) frame.glowHidden = true end
	function E:NameBinding(name, text, ...) test.bindings[name] = text:format(...) end
	E.Key = function(text) return text end
	function E:CreateMover(frame, name, title, point, opts)
		world.mover = { frame = frame, name = name, title = title, point = point, opts = opts }
		E.movers[name] = world.mover
	end
	function E:ApplyMover() world.moverApplies = world.moverApplies + 1 end
	function E:IsMoveMode() return world.moveMode end
	function E:SetTemplate() end
	function E:TrimIcon() end
	function E:CreateText() return NewRegion() end
	function E:AccentTexture() end
	function E:ApplyCooldownFont() end
	function E:TokenColor(kind)
		if kind == "bad" then return 1, 0.47, 0.42 end
		return 0.65, 0.65, 0.7
	end
	function E:Masque() return world.masque end
	function E:MasqueButton(group, button, parts, kind)
		table.insert(world.masqued, { group = group, button = button, parts = parts, kind = kind })
		return true
	end
	function E:MasqueReSkin() world.reskins = world.reskins + 1 end
	function E:RegisterKeybindButton(button, command) world.keybind[button] = command end
	function E:UnregisterKeybindButton(button) world.keybind[button] = nil end
	function E:ToggleKeybindMode(on) world.keybindMode = on and true or false end
	function E:IsKeybindMode() return world.keybindMode end
	function E:KeybindStatus(text) world.keybindStatus = text end
	function E:RunOutOfCombat(fn, key)
		if not world.combat then
			fn()
			return true
		end
		for _, job in ipairs(world.combatQueue) do
			if key ~= nil and job.key == key then
				job.fn = fn
				return false
			end
		end
		table.insert(world.combatQueue, { fn = fn, key = key })
		return false
	end
	function E:Print(text) table.insert(world.printed, text) end
	function E:TooltipHint(tooltip, ...)
		for index = 1, select("#", ...) do
			local hint = select(index, ...)
			tooltip:AddLine(hint[1] .. ": " .. hint[2])
		end
	end
	SAFE(nil, E)
	BAGCACHE(nil, E)
	CHUNK(nil, E)
	test.E = E
	return test.M
end

local function RunTimers()
	while #world.timers > 0 do
		local timers = world.timers
		world.timers = {}
		for _, fn in ipairs(timers) do fn() end
	end
end

-- A game event: the bags read again on the next frame, then the timers.
local function Fire(event)
	world.now = world.now + 1
	local handler = world.events[event]
	if handler then handler() end
	RunTimers()
end

local function Enable(M)
	M.active = true
	M:OnEnable()
	RunTimers()
end

local function StartCombat()
	world.combat = true
end

local function EndCombat()
	world.combat = false
	world.now = world.now + 1
	local queue = world.combatQueue
	world.combatQueue = {}
	for _, job in ipairs(queue) do job.fn() end
	local handler = world.events.PLAYER_REGEN_ENABLED
	if handler then handler() end
	RunTimers()
end

-- The items in bag 0, one per slot from slot 1.
local function Bag(list)
	world.bags[0] = { size = 20 }
	for slot, entry in ipairs(list) do world.bags[0][slot] = entry end
	world.now = world.now + 1
end

-- The item IDs on the shown buttons, in order ("-" for an empty button).
local function Bar(M)
	local ids = {}
	for _, button in ipairs(M.buttons) do
		if button.shown then ids[#ids + 1] = button.attributes.item and button.attributes.item:match("item:(%d+)") or "-" end
	end
	return table.concat(ids, " ")
end

local function Item(id, fields)
	local item = fields or {}
	item.count = item.count or 1
	item.name = item.name or ("Item " .. id)
	world.items[id] = item
	return item
end

-- The standard bag: every kind of item once.
local function StandardWorld()
	Item(5005, { class = 0, spell = "Healing Potion" })       -- a potion: not a quest item
	Item(5000, { class = 12, spell = "Use" })                 -- the quest log's item for quest 100
	Item(5001, { class = 12, spell = "Use" })                 -- a Quest item with a use
	Item(5002, { class = 12 })                                -- plain quest loot: nothing to use
	Item(5003, { class = 12 })                                -- a quest item with something inside
	Item(5004, { class = 15, spell = "Use" })                 -- flagged by the game as a quest item
	Item(5006, { class = 12 })                                -- starts quest 200
	Item(5007, { class = 12 })                                -- starts quest 201, done already
	Item(5008, { class = 12 })                                -- started quest 202, which you have
	world.log = { { questID = 100, special = { id = 5000 } }, { questID = 300, header = true } }
	world.completed[201] = true
	Bag({
		{ id = 5005 }, { id = 5000 }, { id = 5001 }, { id = 5002 }, { id = 5003, hasLoot = true },
		{ id = 5004, quest = { isQuestItem = true } }, { id = 5006, quest = { questID = 200 } },
		{ id = 5007, quest = { questID = 201 } }, { id = 5008, quest = { questID = 202, isActive = true } },
	})
end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
-- Which items get a button, and in which order.
do
	local M = Setup()
	StandardWorld()
	Enable(M)
	Check(Bar(M) == "5000 5001 5003 5004 5006", "the quest items you can use, in bag order: " .. Bar(M))
	Check(#world.blocked == 0, "nothing blocked out of combat")
	Check(M.list[1].kind == "quest" and M.list[1].quest and M.list[1].quest.logIndex == 1, "the quest log's item knows its quest")
	Check(M.list[5].kind == "starter", "the item that starts a quest is a starter")
	Check(M.list[2].quest == nil, "a bag quest item has no quest log entry")
	Check(M.bar.shown == true, "the bar shows with items")
	Check(M.bar.width == 5 * 36 - 4 and M.bar.height == 32, "the bar's size follows five buttons")
	Check(world.moverApplies > 0, "the mover takes the new size")

	-- A quest ready to turn in.
	world.log[1].complete = true
	Fire("QUEST_LOG_UPDATE")
	Check(Bar(M) == "5001 5003 5004 5006", "a finished quest's log item leaves the bar: " .. Bar(M))
	world.log[1].special.showWhenComplete = true
	Fire("QUEST_LOG_UPDATE")
	Check(Bar(M) == "5000 5001 5003 5004 5006", "unless the game keeps the item for the finished quest")
	world.log[1].special.showWhenComplete = false
	M.db.complete = true
	M:OnProfileChanged()
	Check(Bar(M) == "5000 5001 5003 5004 5006", "or Finished quests too is on")
	M.db.complete = false
	world.bags[0][2].quest = { isQuestItem = true }
	Fire("QUEST_LOG_UPDATE")
	Check(Bar(M) == "5001 5003 5004 5006", "a finished quest's item the game flags as a quest item stays off too: " .. Bar(M))
	world.bags[0][2].quest = nil
	world.log[2] = { questID = 101, special = { id = 5000 } }
	Fire("QUEST_LOG_UPDATE")
	Check(Bar(M) == "5000 5001 5003 5004 5006" and M.list[1].quest.questID == 101, "another open quest with the same item keeps it")
	world.log[2] = { questID = 300, header = true }
	world.log[1].complete = false

	-- Starters.
	M.db.starters = false
	M:OnProfileChanged()
	Check(Bar(M) == "5000 5001 5003 5004", "starters switched off: " .. Bar(M))
	M.db.starters = true
	M:OnProfileChanged()

	-- A quest log item you don't carry: from the bags only.
	world.items[5000].count = 0
	world.bags[0][2] = nil
	Fire("BAG_UPDATE_DELAYED")
	Check(Bar(M) == "5001 5003 5004 5006", "a quest log item not in the bags gets no button: " .. Bar(M))
end

-- Secret and failing answers count as not there.
do
	local M = Setup()
	Item(6000, { class = 12, spell = SECRET })
	Item(6001, { class = 12, spellError = true })
	Item(6002, { class = SECRET, spell = "Use" })
	Item(6003, { class = 15, spell = "Use" })
	Item(6004, { class = 12, spell = "Use" })
	Item(6005, { class = 0, spell = "Use" })
	world.log = { { questID = 100, special = { link = SECRET } } }
	Bag({ { id = 6000 }, { id = 6001 }, { id = 6002 }, { id = 6003, questInfo = SECRET }, { id = SECRET }, { id = 6004 },
		{ id = 6005, quest = { isQuestItem = SECRET, questID = SECRET } } })
	Enable(M)
	Check(Bar(M) == "6004", "secret spells, failing calls, secret classes, quest info, item IDs and links are left out: " .. Bar(M))
end

-- One button per item, at most 12, empty bags.
do
	local M = Setup()
	local list = {}
	for id = 7001, 7015 do
		Item(id, { class = 12, spell = "Use" })
		list[#list + 1] = { id = id }
	end
	table.insert(list, 2, { id = 7001 })
	Bag(list)
	Enable(M)
	local ids = {}
	for id = 7001, 7012 do ids[#ids + 1] = tostring(id) end
	Check(Bar(M) == table.concat(ids, " "), "one button per item, the first 12: " .. Bar(M))
	Bag({})
	Fire("BAG_UPDATE_DELAYED")
	Check(Bar(M) == "" and M.bar.shown == false, "no items: the bar hides")
	Check(M.buttons[1].attributes.item == nil, "and the buttons hold no item")
	world.moveMode = true
	M:OnProfileChanged()
	Check(M.bar.shown == true, "applied again in move mode, the empty bar shows")
end

-- Combat: the bar keeps its items until combat ends. In the game the
-- options window queues a settings change in combat (E:RefreshModule) and
-- the module switch waits for the end of combat; the module's own guards
-- are checked here anyway.
do
	local M = Setup()
	StandardWorld()
	Enable(M)
	local sets = world.attributeSets
	StartCombat()
	world.bags[0][10] = { id = 5009 }
	Item(5009, { class = 12, spell = "Use" })
	world.items[5001].count = 0
	Fire("BAG_UPDATE_DELAYED")
	Fire("QUEST_LOG_UPDATE")
	Check(#world.blocked == 0, "nothing secure changes in combat: " .. table.concat(world.blocked, ", "))
	Check(Bar(M) == "5000 5001 5003 5004 5006" and world.attributeSets == sets, "in combat the buttons keep their items")
	Check(M.buttons[2].icon.desaturated == true, "a used-up item turns gray in combat")
	Check(M.dirty == true, "the change waits for the end of combat")
	M.db.buttonSize = 40
	M:OnProfileChanged()
	Check(#world.blocked == 0, "a settings change in combat waits too")
	EndCombat()
	Check(#world.blocked == 0, "nothing blocked after combat")
	Check(Bar(M) == "5000 5001 5003 5004 5006 5009", "after combat the new item has its button: " .. Bar(M))
	Check(M.buttons[1].width == 40, "and the size from combat is applied")
	Check(M.dirty == false, "nothing waits any more")
end

-- The same items are not applied again.
do
	local M = Setup()
	StandardWorld()
	Enable(M)
	local sets, applies = world.attributeSets, world.moverApplies
	Fire("BAG_UPDATE_DELAYED")
	Fire("QUEST_LOG_UPDATE")
	Check(world.attributeSets == sets and world.moverApplies == applies, "an event with the same items sets no attribute")
	M:OnProfileChanged()
	Check(world.attributeSets > sets, "a settings change applies again")
end

-- One read per burst of events.
do
	local M = Setup()
	StandardWorld()
	Enable(M)
	for _, event in ipairs({ "BAG_UPDATE_DELAYED", "QUEST_LOG_UPDATE", "PLAYER_ENTERING_WORLD", "GET_ITEM_INFO_RECEIVED" }) do
		Check(world.events[event] ~= nil, "listens to " .. event)
	end
	world.events.BAG_UPDATE_DELAYED()
	world.events.QUEST_LOG_UPDATE()
	world.events.GET_ITEM_INFO_RECEIVED()
	Check(#world.timers == 1, "a burst of three events: one read")
	RunTimers()
end

-- Layout.
do
	local M = Setup()
	StandardWorld()
	M.db.vertical, M.db.buttonSize, M.db.spacing = true, 30, 2
	Enable(M)
	Check(M.bar.width == 30 and M.bar.height == 5 * 32 - 2, "vertical: a column of five buttons")
	local point = M.buttons[2].points[1]
	Check(point and point[1] == "TOP" and point[5] == -32, "the second button sits under the first")
	Check(M.buttons[6].shown == false and M.buttons[6].attributes.item == nil, "unused buttons hide and hold nothing")
	Check(world.mover.name == "EldoUI_QuestBar" and world.mover.opts.group == "Action bars" and world.mover.opts.combat == true,
		"the mover is in Action bars and in combat mode")
	Check(world.mover.point[1] == "BOTTOMRIGHT", "the mover starts at the bottom right")
end

-- Counts, charges, starter mark, key text, cooldowns.
do
	local M = Setup()
	StandardWorld()
	world.items[5001].count = 3
	world.log[1].special.charges = 5
	world.bindings["CLICK EldoUI_QuestBarButton2:LeftButton"] = "F"
	Enable(M)
	Check(M.buttons[2].count.text == "3", "a stack shows its count")
	Check(M.buttons[1].count.text == "5", "a quest log item shows its charges")
	Check(M.buttons[3].count.text == "", "a single item shows no count")
	Check(M.buttons[5].starter.shown == true and M.buttons[1].starter.shown == false, "the starter mark only on the starter")
	Check(M.buttons[2].hotkey.text == "K:F" and M.buttons[1].hotkey.text == "", "the bound key shows")
	Check(M.buttons[2].icon.texture == 9000 + 5001, "the item's icon")
	M.db.showCount, M.db.hotkey = false, false
	M:OnProfileChanged()
	Check(M.buttons[2].count.text == "" and M.buttons[2].hotkey.text == "", "counts and key text switched off")
	world.draws = {}
	world.cooldownSubs.QuestBar({ items = true })
	Check(#world.draws == 5 and world.draws[1].id == 5000 and world.draws[1].hideGCD == true, "an item cooldown change draws the buttons' cooldowns")
	world.draws = {}
	world.cooldownSubs.QuestBar({ spells = true })
	Check(#world.draws == 0, "a spell cooldown change draws nothing")
	world.bindings["CLICK EldoUI_QuestBarButton2:LeftButton"] = nil
	M.db.hotkey = true
	Fire("UPDATE_BINDINGS")
	Check(M.buttons[2].hotkey.text == "", "a removed key leaves the button")
end

-- Range color.
do
	local M = Setup()
	StandardWorld()
	world.range[1] = 0
	Enable(M)
	local tick = world.ticker["QuestBar:range"]
	Check(tick ~= nil and tick.period == 0.2, "the range check runs while a quest log item shows")
	Check(M.buttons[1].icon.vertex[1] == 1 and M.buttons[1].icon.vertex[2] == 0.47, "out of range: red")
	Check(M.buttons[2].icon.vertex[2] == 1, "a bag quest item keeps its color")
	world.range[1] = 1
	tick.fn()
	Check(M.buttons[1].icon.vertex[2] == 1, "in range: its color")
	world.range[1] = SECRET
	tick.fn()
	Check(M.buttons[1].icon.vertex[2] == 1, "a secret answer: its color")
	world.range[1] = 0
	tick.fn()
	M.db.range = false
	M:OnProfileChanged()
	Check(world.ticker["QuestBar:range"] == nil and M.buttons[1].icon.vertex[2] == 1, "switched off: no check, the color back")
	M.db.range = true
	M:OnProfileChanged()
	-- In combat a quest comes in above ours: the bar keeps its items, the
	-- range and the tooltip follow our quest to its new place.
	StartCombat()
	Item(5500, { class = 12, spell = "Use" })
	table.insert(world.log, 1, { questID = 150, special = { id = 5500 } })
	world.range[1], world.range[2] = 0, 1
	Fire("QUEST_LOG_UPDATE")
	world.ticker["QuestBar:range"].fn()
	Check(M.buttons[1].item.id == 5000 and M.buttons[1].icon.vertex[2] == 1, "in combat the range is read at the quest's new place")
	M.buttons[1].scripts.OnEnter(M.buttons[1])
	Check(GameTooltip.set == "log:2", "and the tooltip shows our quest's item")
	table.remove(world.log, 2)
	world.range[1] = 0
	world.ticker["QuestBar:range"].fn()
	M.buttons[1].scripts.OnEnter(M.buttons[1])
	Check(M.buttons[1].icon.vertex[2] == 1 and GameTooltip.set == "bag:0:2", "a quest gone from the log: no range, the bag's tooltip")
	EndCombat()
	Check(#world.blocked == 0, "nothing blocked")
	-- A client without GetLogIndexForQuestID: the place from the last read.
	world.log = { { questID = 100, special = { id = 5000 } } }
	world.range = { [1] = 0 }
	Fire("QUEST_LOG_UPDATE")
	C_QuestLog.GetLogIndexForQuestID = nil
	world.ticker["QuestBar:range"].fn()
	Check(M.buttons[1].icon.vertex[2] == 0.47, "without the lookup: the place from the last read")
	C_QuestLog.GetLogIndexForQuestID = LOG_INDEX_FOR_QUEST
	world.log = {}
	Fire("QUEST_LOG_UPDATE")
	Check(world.ticker["QuestBar:range"] == nil, "no quest log item: no check")
end

-- Glow for new items.
do
	local M = Setup()
	StandardWorld()
	Enable(M)
	Check(#world.glows == 0, "the items at login don't glow")
	Item(5009, { class = 12, spell = "Use" })
	world.bags[0][10] = { id = 5009 }
	Fire("BAG_UPDATE_DELAYED")
	Check(#world.glows == 1 and world.glows[1].frame == M.buttons[6] and world.glows[1].key == "questBar", "a new item glows")
	RunTimers()
	Check(M.buttons[6].glowHidden == true, "and the glow ends")
	M.db.glow = false
	Item(5010, { class = 12, spell = "Use" })
	world.bags[0][11] = { id = 5010 }
	Fire("BAG_UPDATE_DELAYED")
	Check(#world.glows == 1, "glow off: no glow")
	M.db.glow = true
	M.active = false
	M:OnDisable()
	Enable(M)
	Check(#world.glows == 1, "turned on again, its items don't glow")
	M:HideItem(5001)
	M:ShowHidden()
	Check(#world.glows == 1, "Show hidden items again: no glow")
	M.db.starters = false
	M:OnProfileChanged()
	M.db.starters = true
	M:OnProfileChanged()
	Check(#world.glows == 1, "starters off and on again: no glow")
	Item(5011, { class = 12 })
	world.bags[0][12] = { id = 5011 }
	Fire("BAG_UPDATE_DELAYED")
	world.items[5011].spell = "Use"
	Fire("GET_ITEM_INFO_RECEIVED")
	Check(M.buttons[8].item and M.buttons[8].item.id == 5011 and #world.glows == 1,
		"an item whose data came late joins the bar without a glow")
	StartCombat()
	Item(5012, { class = 12, spell = "Use" })
	world.bags[0][13] = { id = 5012 }
	Fire("BAG_UPDATE_DELAYED")
	EndCombat()
	Check(#world.glows == 2 and world.glows[2].frame == M.buttons[9] and M.buttons[9].item.id == 5012,
		"an item looted in combat glows after combat")
	Check(test.glowUser.key == "questBar" and test.glowUser.info.button == true, "the glow is on the Glows page")
end

-- Hidden items.
do
	local M = Setup()
	StandardWorld()
	Enable(M)
	local post = M.buttons[2].hooks.PostClick
	post(M.buttons[2], "RightButton", false)
	Check(Bar(M) == "5000 5001 5003 5004 5006", "right-click without Shift hides nothing")
	post(M.buttons[2], "LeftButton", false)
	world.shift = true
	post(M.buttons[2], "LeftButton", false)
	Check(Bar(M) == "5000 5001 5003 5004 5006", "a left click with Shift hides nothing")
	post(M.buttons[2], "RightButton", true)
	Check(Bar(M) == "5000 5001 5003 5004 5006", "the press of the right button hides nothing")
	post(M.buttons[2], "RightButton", false)
	Check(Bar(M) == "5000 5003 5004 5006" and M.db.hidden[5001] == true, "Shift-right-click leaves the item off the bar")
	Check(world.printed[1]:find("Item 5001", 1, true) ~= nil, "a chat line names the item")
	Check(M:HiddenCount() == 1, "one hidden item")
	StartCombat()
	Check(M.buttons[2].item.id == 5003, "the next item moved up to the second button")
	post(M.buttons[2], "RightButton", false)
	Check(#world.blocked == 0 and Bar(M) == "5000 5003 5004 5006", "in combat the bar keeps the item until combat ends")
	Check(world.printed[#world.printed] == "The bar changes when combat ends.", "and says so")
	EndCombat()
	Check(Bar(M) == "5000 5004 5006", "after combat it is gone")
	world.shift = false
	M:ShowHidden()
	Check(Bar(M) == "5000 5001 5003 5004 5006" and M:HiddenCount() == 0, "Show hidden items again brings them back")
	M.db.hidden = nil
	Check(M:HiddenCount() == 0, "a profile without the list has none hidden")
	M:ShowHidden()
	Check(type(M.db.hidden) == "table", "and Show hidden items again makes a new list")
	Check(M.buttons[1].clicks[1] == "LeftButtonUp" and M.buttons[1].clicks[2] == "LeftButtonDown" and M.buttons[1].clicks[3] == "RightButtonUp",
		"the left button acts on press and release, the right button on release")
	Check(M.buttons[1].attributes.type == nil and M.buttons[1].attributes["*type1"] == "item", "only the left button uses the item")
	-- The game looks a secure attribute up as modifier-name-button, *name-button, modifier-name*, *name*, name
	-- (Blizzard_FrameXML/SecureTemplates.lua): with Shift, Ctrl or Alt held, as for a key bound with a modifier, the
	-- left button must still find its action, the right button none.
	local function Action(button, prefix, suffix)
		local a = button.attributes
		for _, key in ipairs({ prefix .. "type" .. suffix, "*type" .. suffix, prefix .. "type*", "*type*", "type" }) do
			if a[key] ~= nil and a[key] ~= "" then return a[key] end
		end
	end
	for _, prefix in ipairs({ "", "shift-", "ctrl-", "alt-", "alt-ctrl-shift-" }) do
		Check(Action(M.buttons[1], prefix, "1") == "item", "the left button uses the item with modifier '" .. prefix .. "' (keys bound with Shift, Ctrl or Alt)")
		Check(Action(M.buttons[1], prefix, "2") == nil, "the right button uses nothing with modifier '" .. prefix .. "'")
	end
end

-- Bind keys.
do
	local M = Setup()
	StandardWorld()
	M:BindKeys()
	Check(world.printed[1] == "Turn on the Quest Item Bar first.", "module off: a hint")
	Enable(M)
	StartCombat()
	M:BindKeys()
	Check(world.printed[2] == "Keys can't be bound in combat." and not world.keybindMode, "in combat: a hint, no keybind mode")
	EndCombat()
	M:BindKeys()
	Check(world.keybindMode and #Bar(M):gsub("[^ ]", "") == 11, "keybind mode with all 12 buttons")
	Check(Bar(M) == "5000 5001 5003 5004 5006 - - - - - - -", "the empty ones hold nothing: " .. Bar(M))
	Check(world.keybind[M.buttons[12]] == "CLICK EldoUI_QuestBarButton12:LeftButton", "every button can take its key")
	Check(world.keybindStatus ~= nil, "the banner says what to do")
	local vis = world.visibility.opts
	Check(vis.condition() == "show" and vis.forceShow() == true and vis.forceShowFirst == true,
		"while binding, the bar shows whatever the visibility rule says")
	Check(world.visibilityUpdates > 0, "and the visibility rule is read again")
	world.ticker["QuestBar:bind"].fn()
	Check(Bar(M):find("-", 1, true) ~= nil, "while keybind mode is open the buttons stay")
	world.keybindMode = false
	world.ticker["QuestBar:bind"].fn()
	Check(Bar(M) == "5000 5001 5003 5004 5006" and world.ticker["QuestBar:bind"] == nil, "keybind mode closed: the items again")
	Check(vis.condition() == nil and vis.forceShow() == false, "and the visibility rule decides again")
	world.moveMode = true
	Check(vis.forceShow() == true, "move mode shows the bar too")
end

-- Tooltip.
do
	local M = Setup()
	StandardWorld()
	world.bindings["CLICK EldoUI_QuestBarButton1:LeftButton"] = "G"
	Enable(M)
	local enter = M.buttons[1].scripts.OnEnter
	enter(M.buttons[1])
	Check(GameTooltip.set == "log:1" and TipHas("Key: %s") == false and TipHas("Key: K:G"), "a quest log item: the quest log's tooltip and the key")
	Check(TipHas("Shift-right-click: leave this item off the bar"), "the hint for hiding")
	enter(M.buttons[2])
	Check(GameTooltip.set == "bag:0:3", "a bag item: the bag slot's tooltip")
	Check(TipHas("No key bound (Quest Item Bar > Bind keys)"), "no key: where to bind one")
	enter(M.buttons[5])
	Check(TipHas("Starts a quest: a click shows it."), "a starter says what a click does")
	world.bags[0][3] = nil
	world.now = world.now + 1
	enter(M.buttons[2])
	Check(GameTooltip.set == "id:5001", "the slot changed in combat: the item's own tooltip")
	M.binding = true
	M.list = {}
	M:UpdateButtons()
	enter(M.buttons[7])
	Check(TipHas("Empty for now: the next quest item you can use comes here."), "an empty button says what comes")
end

-- Turning the module off.
do
	local M = Setup()
	StandardWorld()
	world.range[1] = 0
	Enable(M)
	Check(world.cooldownSubs.QuestBar ~= nil and world.visibility ~= nil, "on: cooldowns and visibility")
	StartCombat()
	M.active = false
	M:OnDisable()
	Check(#world.blocked == 0 and Bar(M) ~= "", "off in combat: the bar waits for the end of combat")
	EndCombat()
	Check(Bar(M) == "" and M.bar.shown == false and M.buttons[1].attributes.item == nil, "then it hides and holds nothing")
	Check(next(world.keybind) == nil, "no button stays in keybind mode")
	Check(world.ticker["QuestBar:range"] == nil and world.cooldownSubs.QuestBar == nil and world.visibility == nil,
		"no ticker, no cooldown source, no visibility rule")
	Fire("BAG_UPDATE_DELAYED")
	Check(Bar(M) == "", "events after it is off change nothing")
	Enable(M)
	Check(Bar(M) == "5000 5001 5003 5004 5006", "on again: the items again")
end

-- Masque.
do
	local M = Setup({ masque = {} })
	M.db.masque = true
	StandardWorld()
	Enable(M)
	Check(#world.masqued == 12 and world.masqued[1].group == "Quest Item Bar" and world.masqued[1].kind == "Item", "Masque gets the 12 buttons")
	Check(world.masqued[1].parts.Icon == M.buttons[1].icon and world.masqued[1].parts.HotKey == M.buttons[1].hotkey, "with their parts")
	Check(world.reskins > 0, "and skins them after they have their size")
end

-- Key binding names, defaults and options.
do
	local M = Setup()
	Check(test.bindings.BINDING_HEADER_ELDOUIQUESTBAR == "EldoUI Quest Item Bar", "the key bindings have a header")
	for index = 1, 12 do
		local name = ("BINDING_NAME_CLICK EldoUI_QuestBarButton%d:LeftButton"):format(index)
		Check(test.bindings[name] == ("Quest item %d (Quest Item Bar)"):format(index), "binding name " .. index)
	end
	Check(M.MAX == 12, "at most 12 buttons")
	Check(M.defaults.enabled == true and M.defaults.starters == true and M.defaults.complete == false and M.defaults.masque == false,
		"on by default with starters, without finished quests and Masque")
	Check(M.category == "Quality of Life" and M.def.optionsPage == "module:QuestBar", "a Quality of Life module with its own page")
	for _, row in ipairs(M.options) do
		if row.type ~= "header" and row.type ~= "description" then
			Check(type(row.desc) == "string" and row.desc ~= "", "the option has a description: " .. tostring(row.label))
		end
		if row.key and not row.key:find("^visibility%.") then
			Check(M.defaults[row.key] ~= nil, "the option has a default: " .. row.key)
		end
	end
	local Signature = M.Signature
	Check(Signature({ { id = 1 }, { id = 2 } }) == "1,2" and Signature({}) == "" and Signature(nil) == "", "the signature of a list")
end

print(("%d checks passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
