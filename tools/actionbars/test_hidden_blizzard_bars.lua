-- Offline test for Blizzard's action bars that EldoUI hides (review
-- fehler.md, F19).
-- Run from the repository root:
--   lua5.1 tools/actionbars/test_hidden_blizzard_bars.lua
-- Seen in the game (15.11.2026): a spell put on bar 1 in combat, and the
-- game blocked its own bar update, ActionButton<n>:SetShown() and
-- MainActionBarButtonContainer<n>:SetShown(), booked on EldoUI. EldoUI set
-- the "statehidden" attribute on the buttons of the bars it hides, and the
-- game's bar reads that attribute when it decides which buttons show
-- (ActionBarMixin:UpdateShownButtons). An attribute an addon set counts as
-- the addon's: the game's update ran as EldoUI's, and in combat the game
-- blocks every SetShown on a protected button in it.
-- This cuts the real parts out of EldoUI/Modules/ActionBars.lua (between
-- fixed markers, so a renamed part makes the test fail instead of testing
-- a stale copy): the BARS table and the block that hides and brings back
-- Blizzard's bars. Around them: Blizzard's bars and buttons with the
-- game's taint rule for attributes, and the game's update on a slot change
-- (the same loop as UpdateShownButtons).
-- Checked: hiding writes no attribute on the game's buttons, the game's own
-- update in combat runs clean, the buttons stay out of sight under the
-- hidden parent, the grid events come back with the bar, and the old code
-- (with the attribute) is blocked in the model as it was in the game.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/actionbars/") or "./"

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

local source = ReadFile("EldoUI/Modules/ActionBars.lua")
local barsTable = Between(source, "local BARS = {", "M.BARS = BARS", "ActionBars.lua BARS")
local hideBlock = Between(source, "local hiddenBars = {}", "function M:UpdateBlizzardBars()", "ActionBars.lua hidden bars")

local function Load(block)
	return assert(loadstring(table.concat({
		"local E, M, UIParent = ...",
		barsTable,
		block,
		"return HideBlizzardBar, ShowBlizzardBar, BARS",
	}, "\n"), "=ActionBars.lua hidden bars"))
end

---------------------------------------------------------------------------
-- The game: who runs now, and the taint rule for attributes
---------------------------------------------------------------------------
local world

-- Run fn as the game's own code (an event handler): it starts clean and
-- becomes the addon's when it reads a value the addon wrote.
local function AsGame(fn)
	local before = world.addon
	world.addon, world.tainted = false, false
	fn()
	world.addon, world.tainted = before, false
end

local function Protected(object, method, fn)
	object[method] = function(self, ...)
		if world.combat and (world.addon or world.tainted) then
			world.blocked[#world.blocked + 1] = (self.name or "?") .. ":" .. method .. "()"
			return
		end
		return fn(self, ...)
	end
end

local function Frame(name, parent)
	local frame = { name = name, parent = parent, shown = true, attributes = {}, attributeOwner = {}, events = {} }
	function frame:GetParent() return self.parent end
	function frame:SetParent(p) self.parent = p end
	function frame:IsShown() return self.shown end
	function frame:IsVisible()
		local f = self
		while f do
			if not f.shown then return false end
			f = f.parent
		end
		return true
	end
	function frame:RegisterEvent(event) self.events[event] = true end
	function frame:UnregisterEvent(event) self.events[event] = nil end
	function frame:IsEventRegistered(event) return self.events[event] == true end
	function frame:UnregisterAllEvents() self.events = {} end
	-- An attribute keeps who set it; the game reading one the addon set
	-- runs on as the addon's.
	function frame:SetAttribute(key, value)
		self.attributes[key] = value
		self.attributeOwner[key] = world.addon and "addon" or "game"
		if world.addon then world.addonAttributes[#world.addonAttributes + 1] = (self.name or "?") .. "." .. key end
	end
	function frame:GetAttribute(key)
		if self.attributeOwner[key] == "addon" then world.tainted = true end
		return self.attributes[key]
	end
	Protected(frame, "Show", function(self) self.shown = true end)
	Protected(frame, "Hide", function(self) self.shown = false end)
	Protected(frame, "SetShown", function(self, show) self.shown = show and true or false end)
	return frame
end

local UIParent

-- A bar of 12 buttons, each in its container, as the game builds them.
local function Bar(name, buttonPrefix)
	local bar = Frame(name, UIParent)
	bar.numButtonsShowable = 12
	bar.actionButtons = {}
	bar:RegisterEvent("ACTIONBAR_SHOWGRID")
	bar:RegisterEvent("ACTIONBAR_HIDEGRID")
	for i = 1, 12 do
		local container = Frame((name == "MainActionBar" and "MainActionBarButtonContainer" or buttonPrefix .. "Container") .. i, bar)
		local button = Frame(buttonPrefix .. i, container)
		button.index, button.container, button.bar = i, container, bar
		button.hasAction = i <= 8
		button:RegisterEvent("ACTIONBAR_UPDATE_STATE")
		function button:HasAction() return self.hasAction end
		function button:GetShowGrid() return false end
		bar.actionButtons[i] = button
		_G[buttonPrefix .. i] = button
	end
	-- The game's loop (Blizzard_ActionBar/Shared/ActionBar.lua).
	function bar:UpdateShownButtons()
		for _, actionButton in ipairs(self.actionButtons) do
			local showButton = actionButton.index <= self.numButtonsShowable
				and not actionButton:GetAttribute("statehidden")
				and (actionButton:GetShowGrid() or actionButton:HasAction())
			actionButton:SetShown(showButton)
			actionButton.container:SetShown(showButton or actionButton.index <= self.numButtonsShowable)
		end
	end
	_G[name] = bar
	return bar
end

-- A slot of the bar changed: the game's button event frame calls every
-- button, and each one updates its bar (ActionButton.lua, UpdateAction).
local function SlotChanged(bar)
	AsGame(function()
		for _, button in ipairs(bar.actionButtons) do button.bar:UpdateShownButtons() end
	end)
end

local hider

local function NewWorld()
	world = { addon = true, tainted = false, combat = false, blocked = {}, addonAttributes = {} }
	UIParent = Frame("UIParent", nil)
	hider = Frame("EldoUIHider", nil)
	hider.shown = false
	local E = {}
	function E:HideBlizzardFrame(frame, opts)
		assert(opts and type(opts.check) == "function", "HideBlizzardFrame gets a check")
		frame:SetParent(hider)
		return true
	end
	function E:UnhideBlizzardFrame(frame, parent)
		if frame.parent == hider then frame:SetParent(parent or UIParent) end
	end
	local bars = {
		Bar("MainActionBar", "ActionButton"),
		Bar("MultiBarBottomLeft", "MultiBarBottomLeftButton"),
		Bar("MultiBarBottomRight", "MultiBarBottomRightButton"),
	}
	return E, { db = { bars = {} } }, bars
end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
local failures, passed = 0, 0
local function Check(ok, message)
	if ok then
		passed = passed + 1
	else
		failures = failures + 1
		print("FAIL: " .. message)
	end
end

local function AnyVisible(bar)
	for _, button in ipairs(bar.actionButtons) do
		if button:IsVisible() then return true end
	end
	return false
end

-- The fixed code.
do
	local E, M, bars = NewWorld()
	local HideBlizzardBar, ShowBlizzardBar, BARS = Load(hideBlock)(E, M, UIParent)
	Check(BARS[2].buttons == "MultiBarBottomLeftButton", "BARS gives bar 2 its button names")
	for index = 1, 3 do HideBlizzardBar(index) end
	Check(#world.addonAttributes == 0, "hiding sets no attribute on the game's buttons (set: " .. table.concat(world.addonAttributes, ", ") .. ")")
	Check(bars[1].parent == hider and bars[2].parent == hider and bars[3].parent == hider, "the hidden bars sit on the hidden parent")
	Check(not bars[1]:IsEventRegistered("ACTIONBAR_SHOWGRID") and not bars[1]:IsEventRegistered("ACTIONBAR_HIDEGRID"),
		"a hidden bar stops listening to the grid events")
	Check(not ActionButton1:IsShown() and not ActionButton1:IsEventRegistered("ACTIONBAR_UPDATE_STATE"),
		"a hidden bar's buttons are hidden and have no events")

	-- In combat a slot of bar 1 changes (a spell put on the bar).
	world.combat = true
	SlotChanged(bars[1])
	Check(#world.blocked == 0, "the game's own update in combat is not blocked (blocked: " .. table.concat(world.blocked, ", ") .. ")")
	Check(ActionButton1:IsShown(), "the game's update may show a button with an action")
	Check(not AnyVisible(bars[1]), "no button of a hidden bar is visible (the hidden parent keeps them away)")
	SlotChanged(bars[2])
	SlotChanged(bars[3])
	Check(#world.blocked == 0, "bars 2 and 3 update in combat without a block")
	world.combat = false

	-- A bar comes back this session (a profile without EldoUI's bar).
	Check(ShowBlizzardBar(2) == true, "a bar hidden this session comes back and asks for a reload")
	Check(bars[2].parent == UIParent, "the bar is back on its parent")
	Check(bars[2]:IsEventRegistered("ACTIONBAR_SHOWGRID") and bars[2]:IsEventRegistered("ACTIONBAR_HIDEGRID"),
		"the bar listens to the grid events again")
	Check(#world.addonAttributes == 0, "bringing a bar back sets no attribute either")
	Check(MultiBarBottomLeftButton1:IsShown() and MultiBarBottomLeftButton1:IsVisible(), "its buttons with an action show again")
	Check(ShowBlizzardBar(2) == false, "a bar that is not hidden does not come back twice")
	world.combat = true
	SlotChanged(bars[2])
	Check(#world.blocked == 0, "the bar that came back updates in combat without a block")
	world.combat = false
	HideBlizzardBar(2)
	Check(bars[2].parent == hider and #world.addonAttributes == 0, "hiding it again still sets no attribute")
end

-- The old code set the attribute: the model blocks the game's update in
-- combat, as the game did.
do
	local old, count = hideBlock:gsub("(\t\t\tbutton:UnregisterAllEvents%(%)\n)", "%1\t\t\tbutton:SetAttribute(\"statehidden\", true)\n")
	Check(count == 1, "the old code can be rebuilt from the hiding loop")
	local E, M, bars = NewWorld()
	local HideBlizzardBar = Load(old)(E, M, UIParent)
	HideBlizzardBar(1)
	Check(#world.addonAttributes == 12, "the old code set the attribute on all 12 buttons")
	world.combat = true
	SlotChanged(bars[1])
	local buttons, containers = 0, 0
	for _, entry in ipairs(world.blocked) do
		if entry:match("^ActionButton%d+:SetShown") then buttons = buttons + 1 end
		if entry:match("^MainActionBarButtonContainer%d+:SetShown") then containers = containers + 1 end
	end
	Check(buttons > 0 and containers > 0, "the old code: the game blocks ActionButton<n>:SetShown and the containers (as seen in the game)")
end

-- Nowhere in the block does EldoUI set an attribute on the game's buttons.
Check(not hideBlock:find("SetAttribute", 1, true), "the hide/show block of ActionBars.lua calls no SetAttribute")

print(("%d checks passed, %d failed"):format(passed, failures))
os.exit(failures == 0 and 0 or 1)
