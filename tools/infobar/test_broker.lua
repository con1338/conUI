-- Offline test for Info Bar blocks offered to other addons through
-- LibDataBroker (review verbesserungen.md, C2).
-- Run from the repository root:
--   lua5.1 tools/infobar/test_broker.lua
-- It loads EldoUI/Modules/InfoBar/Broker.lua as it is, and cuts the parts of
-- EldoUI/Modules/InfoBar.lua it works with out of the file (between fixed
-- markers, so a renamed part makes the test fail instead of testing a stale
-- copy): the tooltip lines, UpdateButton and the LibDataBroker bridge that
-- reads other addons' feeds. Around them: a model of LibDataBroker-1.1 that,
-- like the library, compares each new value with the old one (and here
-- fails on a secret value), frames, the shared ticker and the combat state.
-- Checked: only picked blocks are published, once, with text, label, icon,
-- tooltip and click; they follow their events, polls and the Info Bar's
-- refresh by name; secret or failing texts are not handed on; taken out or
-- switched off they show "Off" and stop; a library that loads later is
-- found; a taken name is left alone; clicks keep the combat rule; the
-- bridge does not read EldoUI's own objects back; the tooltip and
-- UpdateButton keep working for the bars.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/infobar/") or "./"

local function ReadFile(path)
	local file = assert(io.open(ROOT .. path, "rb"), "can't open " .. path)
	local text = file:read("*a")
	file:close()
	return (text:gsub("\r\n", "\n"))
end

-- The text from `first` up to (not including) `last`.
local function Between(text, first, last, where)
	local from = text:find(first, 1, true)
	assert(from, where .. ": marker not found: " .. first)
	local to = text:find(last, from + #first, true)
	assert(to, where .. ": end marker not found after " .. first .. ": " .. last)
	return text:sub(from, to - 1)
end

local infobar = ReadFile("EldoUI/Modules/InfoBar.lua")
local function Cut(first, last) return Between(infobar, first, last, "InfoBar.lua") end
local infobarChunk = assert(loadstring(table.concat({
	"local E, L, M = ...",
	-- Parts of InfoBar.lua the cut code reaches but this test does not need.
	"local Label = function(text) return text end",
	"local DB = function() return M.db end",
	"local BarDB = function() return nil end",
	"local SIDES, SLOTS, MAX_PANEL_SLOTS = {}, 6, 6",
	"local AllHolders = function() return M.testHolders or {} end",
	"local BarOf = function() return nil end",
	"local IsSecret = E.Secret",
	"local LabelPart = function() return nil end",
	Cut("-- The lines of a block's tooltip:", "-- Tooltips open away from the screen edge"),
	Cut("local function UpdateButton(button)", "M.UpdateButton = UpdateButton"),
	"M.UpdateButton = UpdateButton",
	Cut("local LDB_PREFIX = ", "-- Other addons can load the library after EldoUI"),
}, "\n"), "=InfoBar.lua parts"))
local brokerChunk = assert(loadstring(ReadFile("EldoUI/Modules/InfoBar/Broker.lua"), "=Broker.lua"))

---------------------------------------------------------------------------
-- Model of the game, LibDataBroker-1.1 and EldoUI's core
---------------------------------------------------------------------------
local world

local function Secret(value) return type(value) == "table" and value.secret == true end
local SECRET = { secret = true }

local function NewTooltip()
	local tooltip = { lines = {}, calls = {} }
	function tooltip:AddLine(text) table.insert(self.lines, text) end
	function tooltip:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
	function tooltip:ClearLines() self.lines = {}; table.insert(self.calls, "ClearLines") end
	function tooltip:Show() table.insert(self.calls, "Show") end
	return tooltip
end

local function NewFrame()
	local frame = { registered = {} }
	function frame:RegisterEvent(event) self.registered[event] = true end
	function frame:RegisterUnitEvent(event, unit) self.registered[event] = unit end
	function frame:UnregisterAllEvents() self.registered = {} end
	function frame:SetScript(_, fn) self.onEvent = fn end
	return frame
end

-- LibDataBroker-1.1 as far as it matters here.
local function NewLibrary()
	local lib = { objects = {}, storage = {}, names = {}, callbacks = {}, changes = 0 }
	local function Fire(event, ...)
		for _, entry in ipairs(lib.callbacks[event] or {}) do entry.fn(event, ...) end
	end
	local meta = {
		__index = function(self, key) return lib.storage[self][key] end,
		__newindex = function(self, key, value)
			-- The library compares the new value with the old one; the game
			-- does not allow that on a secret value.
			assert(not Secret(value), "a secret value reached LibDataBroker")
			local store = lib.storage[self]
			if store[key] == value then return end
			store[key] = value
			lib.changes = lib.changes + 1
			Fire("LibDataBroker_AttributeChanged", lib.names[self], key, value, self)
		end,
	}
	function lib:NewDataObject(name, dataobj)
		if self.objects[name] then return nil end
		dataobj = dataobj or {}
		local store = {}
		for key, value in pairs(dataobj) do store[key] = value end
		for key in pairs(store) do dataobj[key] = nil end
		self.storage[dataobj], self.names[dataobj] = store, name
		setmetatable(dataobj, meta)
		self.objects[name] = dataobj
		Fire("LibDataBroker_DataObjectCreated", name, dataobj)
		return dataobj
	end
	function lib:GetDataObjectByName(name) return self.objects[name] end
	function lib:DataObjectIterator() return pairs(self.objects) end
	function lib.RegisterCallback(target, event, fn)
		lib.callbacks[event] = lib.callbacks[event] or {}
		table.insert(lib.callbacks[event], { target = target, fn = fn })
	end
	return lib
end

function hooksecurefunc(target, name, fn)
	local original = target[name]
	assert(type(original) == "function", "hooking a missing function: " .. tostring(name))
	target[name] = function(...)
		local results = { original(...) }
		fn(...)
		return unpack(results)
	end
end
function CreateFrame()
	local frame = NewFrame()
	table.insert(world.frames, frame)
	return frame
end
function InCombatLockdown() return world.combat end
C_Timer = { After = function() end }
GameTooltip = NewTooltip()

local state -- what the test blocks show

local function Blocks()
	return {
		Durability = {
			title = "Durability", icon = 132281, events = { "UPDATE_INVENTORY_DURABILITY" },
			text = function() return state.durability .. "%" end,
			tooltip = function(tooltip) tooltip:AddLine("Durability lines") end,
			hint = { "Click", "character window" },
			onClick = function(frame, mouseButton)
				state.clicks[#state.clicks + 1] = { "Durability", frame, mouseButton }
				state.durability = state.durability + 1
			end,
		},
		Clock = { title = "Time", poll = true, text = function() return state.clock end, tooltip = function() end },
		Slow = { title = "Slow", poll = true, interval = 5, pollWhen = function() return state.slowOn end,
			text = function() return "slow " .. state.slow end },
		Health = { title = "Health", events = { "UNIT_HEALTH" }, text = function() return state.health end },
		Mail = { title = "Mail", text = function() return state.mail end, tooltip = function(tooltip) tooltip:AddLine("mail") end },
		Broken = { title = "Broken", events = { "BAG_UPDATE" }, text = function()
			if state.broken then error("boom") end
			return "fine"
		end },
		Bags = { title = "Bags", combatClick = true, text = function() return "bags" end,
			onClick = function(frame) state.clicks[#state.clicks + 1] = { "Bags", frame } end },
		Gold = { title = "Gold", text = function() return "gold" end },
		["LDB: Foo"] = { title = "LDB: Foo", broker = true, text = function() return "foo" end },
	}
end

-- A fresh Info Bar with these slots picked; `library`: loaded from the start.
local function Setup(picked, library)
	world = { combat = false, frames = {}, ticker = {}, toasts = {}, tooltipLines = {}, refreshed = {} }
	state = { durability = 80, clock = "12:00", slow = 1, slowOn = true, health = "100", mail = "No mail",
		broken = false, clicks = {} }
	world.lib = library and NewLibrary() or nil
	_G.LibStub = function(name, silent)
		assert(name == "LibDataBroker-1.1" and silent == true)
		return world.lib
	end
	local slots = { "", "", "", "", "", "", "", "" }
	for index, name in ipairs(picked or {}) do slots[index] = name end
	local E = {
		dataTexts = Blocks(),
		Secret = Secret,
		media = { accentColor = { 0.1, 0.2, 0.3 } },
		tokens = { text = { warn = { 1, 0.8, 0 } } },
		UIKit = {
			Toast = function(owner, text) table.insert(world.toasts, { owner, text }) end,
			TipText = function(tooltip, text) tooltip:AddLine(text) end,
		},
		Ticker = {
			Subscribe = function(_, key, period, fn, owner) world.ticker[key] = { period = period, fn = fn, owner = owner } end,
			Unsubscribe = function(_, key) world.ticker[key] = nil end,
		},
	}
	function E:TextHex() return "|cff999999" end
	function E:TooltipHint(tooltip, ...)
		for _, hint in ipairs({ ... }) do tooltip:AddLine(hint[1] .. ": " .. hint[2]) end
	end
	local L = setmetatable({}, { __index = function(_, key) return key end })
	local M = { active = true, extras = {}, overlays = {},
		defaults = { ldbBlocks = { "", "", "", "", "", "", "", "" } },
		db = { ldbBlocks = slots, ldb = true } }
	function M:AddExtra(extra) table.insert(self.extras, extra) end
	function M:Rebuild() end
	function M:TooltipAnchor() return "ANCHOR_TOP" end
	E.L, E.modules = L, { InfoBar = M }
	infobarChunk(E, L, M)
	brokerChunk(nil, E)
	-- Record what the Info Bar refreshes by name (after Broker's hook).
	local refresh = M.RefreshDataText
	M.RefreshDataText = function(self, key)
		table.insert(world.refreshed, key)
		return refresh(self, key)
	end
	return { E = E, M = M, Broker = M.broker }
end

local function Object(name) return world.lib and world.lib.objects["EldoUI: " .. name] end
local function Text(name) local object = Object(name) return object and object.text end
local function BrokerFrame(test) return test.Broker.frame end
local function FireEvent(test, event) local frame = BrokerFrame(test) frame.onEvent(frame, event) end
local function Tick(elapsed) world.ticker["InfoBar:broker"].fn(elapsed) end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
local passed, failed = 0, 0
local function Check(ok, what)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. what) end
end
local OFF = "|cff999999Off|r"

-- Nothing picked: nothing published, nothing running.
do
	local test = Setup({}, true)
	test.M:Rebuild()
	Check(next(world.lib.objects) == nil, "nothing picked: no data objects")
	Check(world.ticker["InfoBar:broker"] == nil, "nothing picked: no ticker")
end

-- Picked blocks: published once each, with their fields.
do
	local test = Setup({ "Durability", "Clock", "Durability", "LDB: Foo", "NoSuchBlock", "Mail" }, true)
	test.M:Rebuild()
	local names = {}
	for name in pairs(world.lib.objects) do names[#names + 1] = name end
	table.sort(names)
	Check(table.concat(names, ",") == "EldoUI: Clock,EldoUI: Durability,EldoUI: Mail",
		"only the picked EldoUI blocks are published, each once (got " .. table.concat(names, ",") .. ")")
	local durability = Object("Durability")
	Check(durability.type == "data source", "type is data source")
	Check(durability.label == "Durability" and durability.text == "80%", "label and text")
	Check(durability.icon == 132281 and durability.tocname == "EldoUI", "icon and tocname")
	Check(type(durability.OnTooltipShow) == "function" and type(durability.OnClick) == "function", "tooltip and click handlers")
	Check(Object("Clock").OnClick == nil, "a block without a click gets no OnClick")
	test.M:Rebuild()
	Check(world.lib.changes == 0, "a second rebuild changes nothing")
	Check(test.Broker.Owns("EldoUI: Durability") and not test.Broker.Owns("Foo"), "Owns knows its objects")
end

-- Events, polls and the refresh by name.
do
	local test = Setup({ "Durability", "Clock", "Slow", "Health", "Mail", "Broken" }, true)
	test.M:Rebuild()
	local frame = BrokerFrame(test)
	Check(frame.registered.UPDATE_INVENTORY_DURABILITY == true, "block event registered")
	Check(frame.registered.UNIT_HEALTH == "player", "UNIT_ event for the player only")
	state.durability = 55
	FireEvent(test, "UPDATE_INVENTORY_DURABILITY")
	Check(Text("Durability") == "55%", "event updates the block")
	state.clock = "12:01"
	FireEvent(test, "UPDATE_INVENTORY_DURABILITY")
	Check(Text("Clock") == "12:00", "another block's event leaves a block alone")
	Check(world.ticker["InfoBar:broker"] ~= nil, "polling blocks start the ticker")
	Tick(0.5)
	Check(Text("Clock") == "12:00", "poll waits for its interval")
	Tick(0.6)
	Check(Text("Clock") == "12:01", "poll after 1 s")
	-- Slow has 1.1 s so far.
	state.slow = 2
	Tick(1)
	Tick(1)
	Tick(1)
	Check(Text("Slow") == "slow 1", "a 5 s poll waits (4.1 s)")
	Tick(1)
	Check(Text("Slow") == "slow 2", "a 5 s poll runs after 5 s (5.1 s)")
	state.slow, state.slowOn = 3, false
	for _ = 1, 6 do Tick(1) end
	Check(Text("Slow") == "slow 2", "pollWhen false: no poll")
	state.mail = "Mail: 2"
	test.M:RefreshDataText("Mail")
	Check(Text("Mail") == "Mail: 2", "the Info Bar's refresh by name reaches the object")
	-- Secret and failing texts.
	state.health = SECRET
	FireEvent(test, "UNIT_HEALTH")
	Check(Text("Health") == "100", "a secret text is not handed on; the last readable one stays")
	state.health = "90"
	FireEvent(test, "UNIT_HEALTH")
	Check(Text("Health") == "90", "readable again: handed on")
	state.broken = true
	FireEvent(test, "BAG_UPDATE")
	Check(Text("Broken") == "fine", "a failing text keeps the last one")
end

-- Taken out, put back, module off.
do
	local test = Setup({ "Durability", "Clock" }, true)
	test.M:Rebuild()
	test.M.db.ldbBlocks[1] = ""
	test.M:Rebuild()
	Check(Text("Durability") == OFF, "taken out: shows Off")
	Check(BrokerFrame(test).registered.UPDATE_INVENTORY_DURABILITY == nil, "taken out: its event is dropped")
	state.durability = 10
	test.M:RefreshDataText("Durability")
	Check(Text("Durability") == OFF, "taken out: no more updates")
	Object("Durability").OnClick({}, "LeftButton")
	Check(#state.clicks == 0, "taken out: a click does nothing")
	local tooltip = NewTooltip()
	Object("Durability").OnTooltipShow(tooltip)
	Check(tooltip.lines[2] == OFF, "taken out: the tooltip says Off")
	test.M.db.ldbBlocks[3] = "Durability"
	test.M:Rebuild()
	Check(Text("Durability") == "10%", "put back: current again")
	test.M.active = false
	for _, extra in ipairs(test.M.extras) do if extra.Disable then extra.Disable(extra) end end
	Check(Text("Durability") == OFF and Text("Clock") == OFF, "module off: every block shows Off")
	Check(world.ticker["InfoBar:broker"] == nil, "module off: ticker stopped")
	Check(next(BrokerFrame(test).registered) == nil, "module off: no events")
	test.M:Rebuild()
	Check(Text("Durability") == OFF, "module off: a rebuild publishes nothing")
end

-- The library loads after EldoUI; a name another addon already has.
do
	local test = Setup({ "Durability", "Gold" }, false)
	test.M:Rebuild()
	local watcher = test.Broker.watcher
	Check(watcher and watcher.registered.ADDON_LOADED, "no library: watches ADDON_LOADED")
	world.lib = NewLibrary()
	world.lib:NewDataObject("EldoUI: Gold", { type = "data source", text = "someone else's" })
	watcher.onEvent(watcher, "ADDON_LOADED")
	Check(Text("Durability") == "80%", "library loaded later: published")
	Check(next(watcher.registered) == nil, "library found: watching stops")
	Check(Text("Gold") == "someone else's" and not test.Broker.live.Gold, "a taken name is left alone")
end

-- Clicks: the combat rule, the display's frame, a refresh afterwards.
do
	local test = Setup({ "Durability", "Bags" }, true)
	test.M:Rebuild()
	local display = { name = "display button" }
	Object("Durability").OnClick(display, "RightButton")
	Check(#state.clicks == 1 and state.clicks[1][2] == display and state.clicks[1][3] == "RightButton",
		"click passes the display's frame and the mouse button")
	Check(Text("Durability") == "81%", "the block refreshes after its click")
	world.combat = true
	Object("Durability").OnClick(display, "LeftButton")
	Check(#state.clicks == 1 and #world.toasts == 1 and world.toasts[1][1] == display, "in combat: click waits, note at the display")
	Object("Bags").OnClick(display, "LeftButton")
	Check(#state.clicks == 2 and state.clicks[2][1] == "Bags", "in combat: a combatClick block still clicks")
	-- The tooltip: the bar's lines, with the combat note.
	local tooltip = NewTooltip()
	Object("Durability").OnTooltipShow(tooltip)
	Check(tooltip.lines[1] == "Durability" and tooltip.lines[2] == "Durability lines" and tooltip.lines[3] == "Click: character window",
		"tooltip: title, lines, hint")
	Check(tooltip.lines[4] == "Clicks work again after combat.", "tooltip: combat note")
	world.combat = false
end

-- The bridge that reads other addons' feeds does not read ours back.
do
	local test = Setup({ "Durability" }, true)
	world.lib:NewDataObject("Foo", { type = "data source", text = "foo" })
	test.M:HookBrokers()
	Check(test.E.dataTexts["LDB: Foo"] ~= nil, "bridge: a foreign feed becomes a block")
	test.M:Rebuild()
	Check(Object("Durability") ~= nil, "published while the bridge listens")
	Check(test.E.dataTexts["LDB: EldoUI: Durability"] == nil, "bridge: our own object is not read back")
	world.refreshed = {}
	state.durability = 70
	FireEvent(test, "UPDATE_INVENTORY_DURABILITY")
	local own = false
	for _, key in ipairs(world.refreshed) do if key == "LDB: EldoUI: Durability" then own = true end end
	Check(not own, "bridge: a change of our object refreshes nothing")
	world.lib.objects.Foo.text = "bar"
	Check(world.refreshed[#world.refreshed] == "LDB: Foo", "bridge: a foreign change still refreshes its block")
end

-- The bars keep their tooltip and UpdateButton.
do
	local test = Setup({}, true)
	local button = { dataName = "Durability" }
	test.M.ShowTooltip(button)
	Check(GameTooltip.owner == button and GameTooltip.anchor == "ANCHOR_TOP", "bar tooltip: owner and anchor")
	Check(GameTooltip.lines[1] == "Durability" and GameTooltip.lines[3] == "Click: character window", "bar tooltip: lines")
	Check(GameTooltip.calls[#GameTooltip.calls] == "Show", "bar tooltip: shown")
	world.combat = true
	test.M.overlays.Durability = { target = button }
	test.M.ShowTooltip(button)
	Check(GameTooltip.lines[4] == nil, "bar tooltip: no combat note under a secure overlay")
	test.M.overlays.Durability = nil
	test.M.ShowTooltip(button)
	Check(GameTooltip.lines[4] == "Clicks work again after combat.", "bar tooltip: combat note otherwise")
	world.combat = false
	-- UpdateButton with another addon's frame (no dataName): nothing happens.
	local ok = pcall(test.M.UpdateButton, { name = "display button" })
	Check(ok, "UpdateButton ignores a frame that is no block")
	local text = {}
	function text:SetText(value) self.value = value end
	local gone = { dataName = "Removed", text = text }
	test.M.UpdateButton(gone)
	Check(text.value == "" and gone.shownText == "", "UpdateButton still clears a block that no longer exists")
	Check(pcall(test.M.ShowTooltip, { name = "display button" }), "ShowTooltip ignores a frame that is no block")
end

print(("%d checks passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
