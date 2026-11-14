-- Offline test for click-cast keys on hover after a roster change (review F16).
-- Run from the repository root:
--   lua5.1 tools/clickcast/test_hover_unit.lua
-- It cuts the real restricted snippets and CreateHoverParts/WrapHover out of
-- EldoUI/Modules/ClickCast.lua (between fixed markers, so a renamed part
-- makes the test fail instead of testing a stale copy) and runs them with a
-- small model of the game's secure handlers:
--   * the snippets of one header share one environment (globals persist);
--     frames are seen through handles; only a few restricted globals exist;
--   * override bindings: the last SetBindingClick for a key wins,
--     ClearBindings removes the ones the frame set;
--   * a key press clicks the bound button (down, then up); an OnClick
--     pre-snippet that returns false stops the click.
-- Checked: a key acts on the unit the hovered frame shows at the press, also
-- after the group header gave that frame another unit; a frame without a
-- unit gets nothing; the next frame entered before the old one is left;
-- OnHide; a /click without hover. Without the OnClick wrapper the model
-- shows the old fault, and with a new handle per call it still works.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/clickcast/") or "./"

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

local clickcast = ReadFile("EldoUI/Modules/ClickCast.lua")
local section = Between(clickcast, "local ON_ENTER = [[", "function M:ApplyHover()", "ClickCast.lua")
local chunk = assert(loadstring(table.concat({
	"local M, wrapped, handler, hover = ...",
	section,
	"return { ON_ENTER = ON_ENTER, ON_LEAVE = ON_LEAVE, ON_CLICK = ON_CLICK,",
	"\tparts = function() return handler, hover end }",
}, "\n"), "=extracted"))

---------------------------------------------------------------------------
-- Model of the game's frames and secure handlers
---------------------------------------------------------------------------
local world -- fresh for every Setup

local Frame = {}
Frame.__index = Frame
local function NewFrame(name)
	return setmetatable({ name = name, attributes = {}, wraps = {} }, Frame)
end
function Frame:SetAttribute(name, value) self.attributes[name] = value end
function Frame:GetAttribute(name) return self.attributes[name] end
function Frame:SetSize() end
function Frame:SetPoint() end
function Frame:RegisterForClicks(...) self.clicks = { ... } end

-- Handles: what restricted code sees of a frame. The game keeps one handle
-- per frame; `fresh` makes a new one on every call, to show the code does
-- not depend on that.
local Handle
local HandleMethods = {}
local HANDLE_META = { __index = HandleMethods }
local function Real(handle)
	local frame = world.frameOf[handle]
	assert(frame, "not a frame handle")
	return frame
end
Handle = function(frame)
	if frame == nil then return nil end
	local handle = not world.fresh and world.handles[frame]
	if not handle then
		handle = setmetatable({}, HANDLE_META)
		world.frameOf[handle] = frame
		world.handles[frame] = handle
	end
	return handle
end
function HandleMethods:GetAttribute(name) return Real(self).attributes[name] end
function HandleMethods:SetAttribute(name, value) Real(self).attributes[name] = value end
function HandleMethods:GetFrameRef(label) return Handle(Real(self).attributes["frameref-" .. label]) end
function HandleMethods:ClearBindings()
	local owner, kept = Real(self), {}
	for _, binding in ipairs(world.bindings) do
		if binding.owner ~= owner then kept[#kept + 1] = binding end
	end
	world.bindings = kept
end
function HandleMethods:SetBindingClick(_, key, target, button)
	table.insert(world.bindings, { owner = Real(self), key = key, target = Real(target), button = button })
end

-- The restricted globals the snippets may read. Anything else is nil, as in
-- the game, so a call to e.g. print or string.find fails here too.
local RESTRICTED = { gmatch = string.gmatch }

local function Environment(header)
	local env = world.envs[header]
	if not env then
		env = setmetatable({}, { __index = RESTRICTED })
		world.envs[header] = env
	end
	return env
end

local compiled = {}
local function Run(body, header, frame, ...)
	local fn = compiled[body]
	if not fn then
		fn = assert(loadstring("local self, owner, button, down = ...\n" .. body, "=snippet"))
		compiled[body] = fn
	end
	setfenv(fn, Environment(header))
	return fn(Handle(frame), Handle(header), ...)
end

-- Runs the pre-snippets of a script; false when one of them stops it.
local function Fire(frame, script, ...)
	for _, wrap in ipairs(frame.wraps[script] or {}) do
		if wrap.pre and Run(wrap.pre, wrap.header, frame, ...) == false then return false end
	end
	return true
end

-- What the extracted code calls.
UIParent = NewFrame("UIParent")
function CreateFrame(_, name) return NewFrame(name) end
function InCombatLockdown() return false end
function SecureHandlerSetFrameRef(frame, label, ref) frame.attributes["frameref-" .. label] = ref end
function SecureHandlerWrapScript(frame, script, header, pre, post)
	if world.failWrap and world.failWrap(frame, script) then error("can't wrap " .. script) end
	frame.wraps[script] = frame.wraps[script] or {}
	table.insert(frame.wraps[script], { header = header, pre = pre, post = post })
end

local HOVER_KEYS = "SHIFT-F\002eldof\001MOUSEWHEELUP\002eldomousewheelup\001"

local function Setup(options)
	options = options or {}
	world = { envs = {}, handles = {}, frameOf = setmetatable({}, { __mode = "k" }), bindings = {},
		fresh = options.fresh, failWrap = options.failWrap }
	local test = { M = {} }
	test.snippets = chunk(test.M, {})
	test.Button = function(name, unit)
		local frame = NewFrame(name)
		frame.attributes.unit = unit
		test.M:WrapHover(frame)
		frame.attributes["eldo-hover"] = true
		return frame
	end
	-- The handler and the hover button exist after the first WrapHover.
	test.Parts = function()
		local handler, hover = test.snippets.parts()
		if handler and not handler.attributes["eldo-hoverkeys"] then handler.attributes["eldo-hoverkeys"] = HOVER_KEYS end
		return handler, hover
	end
	return test
end

local function Enter(frame) Fire(frame, "OnEnter", false) end
local function Leave(frame) Fire(frame, "OnLeave", false) end
local function Hide(frame) Fire(frame, "OnHide") end

-- A key press: the unit the hover button acts on, or nil and why not.
local function Press(key)
	local bound
	for index = #world.bindings, 1, -1 do
		if world.bindings[index].key == key then bound = world.bindings[index] break end
	end
	if not bound then return nil, "no binding" end
	local target = bound.target
	local acts = Fire(target, "OnClick", bound.button, true)
	local unit = acts and target.attributes.unit or nil
	Fire(target, "OnClick", bound.button, false)
	return unit, acts and bound.button or "stopped"
end

-- A /click on the hover button without a hovered frame.
local function ClickDirect(hover)
	if not Fire(hover, "OnClick", "eldof", true) then return nil end
	return hover.attributes.unit
end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
local passed, failed = 0, 0
local function Check(ok, what)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. what) end
end
local function CheckUnit(key, expected, what)
	local unit, how = Press(key)
	Check(unit == expected, ("%s: %s acts on %s (%s), expected %s"):format(what, key, tostring(unit), tostring(how),
		tostring(expected)))
end

-- The snippets as the game gets them.
do
	local test = Setup()
	for _, name in ipairs({ "ON_ENTER", "ON_LEAVE", "ON_CLICK" }) do
		local body = test.snippets[name]
		Check(type(body) == "string", name .. " exists")
		if type(body) == "string" then
			Check(not body:find("function", 1, true), name .. ": no function definitions (not allowed in restricted code)")
			Check(loadstring(body) ~= nil, name .. " compiles")
		end
	end
	local frame = test.Button("A", "raid1")
	local handler, hover = test.Parts()
	Check(handler and hover, "WrapHover creates the handler and the hover button")
	local enter = frame.wraps.OnEnter and frame.wraps.OnEnter[1]
	local click = hover and hover.wraps.OnClick
	Check(enter and enter.header == handler and enter.pre == test.snippets.ON_ENTER, "OnEnter wrapped with ON_ENTER")
	Check(frame.wraps.OnLeave and frame.wraps.OnLeave[1].pre == test.snippets.ON_LEAVE, "OnLeave wrapped with ON_LEAVE")
	Check(frame.wraps.OnHide and frame.wraps.OnHide[1].pre == test.snippets.ON_LEAVE, "OnHide wrapped with ON_LEAVE")
	Check(click and #click == 1, "the hover button's OnClick is wrapped once")
	Check(click and click[1].header == handler and click[1].pre == test.snippets.ON_CLICK,
		"OnClick wrapped with ON_CLICK, same handler (shared environment) as OnEnter")
	test.Button("B", "raid2")
	Check(click and #click == 1, "a second frame does not wrap the hover button again")
end

-- The roster changes while the mouse rests on a frame.
local function RosterScenario(test, what)
	local a = test.Button("A", "raid3")
	local b = test.Button("B", "party1")
	test.Parts()
	Enter(a)
	CheckUnit("SHIFT-F", "raid3", what .. ", hovered")
	CheckUnit("MOUSEWHEELUP", "raid3", what .. ", second key")
	a.attributes.unit = "raid2"  -- someone above left the raid; the header moved A up
	CheckUnit("SHIFT-F", "raid2", what .. ", header gave the frame another unit")
	a.attributes.unitsuffix = "pet"
	CheckUnit("SHIFT-F", "raid2pet", what .. ", unit with suffix")
	a.attributes.unitsuffix = nil
	a.attributes.unit = nil  -- the frame stays on screen without a unit
	CheckUnit("SHIFT-F", nil, what .. ", frame without a unit")
	a.attributes.unit = "raid2"
	-- The next frame is entered before the old one is left.
	Enter(b)
	Leave(a)
	CheckUnit("SHIFT-F", "party1", what .. ", next frame entered first")
	b.attributes.unit = "party2"
	CheckUnit("SHIFT-F", "party2", what .. ", next frame changes its unit")
	Leave(b)
	CheckUnit("SHIFT-F", nil, what .. ", mouse left")
	-- The hovered frame hides (the group shrinks).
	Enter(a)
	Hide(a)
	CheckUnit("SHIFT-F", nil, what .. ", hovered frame hidden")
	-- A frame with hover keys switched off.
	local c = test.Button("C", "raid5")
	c.attributes["eldo-hover"] = nil
	Enter(c)
	CheckUnit("SHIFT-F", nil, what .. ", frame without hover keys")
	Leave(c)
end

do
	local test = Setup()
	RosterScenario(test, "one handle per frame")
	local _, hover = test.Parts()
	local env = world.envs[test.Parts()]
	Check(env and env.eldoHovered == nil, "nothing hovered after the mouse left")
	-- /click EldoUI_ClickCastHover without a hovered frame: unit unchanged.
	hover.attributes.unit = "raid2"
	Check(ClickDirect(hover) == "raid2", "/click without a hovered frame keeps the button's unit")
end

do
	local test = Setup({ fresh = true })
	RosterScenario(test, "new handle per call")
end

-- Without the OnClick wrapper (the wrap fails): the unit copied on enter, as
-- before the fix. Shows that the model reproduces F16, and that nothing gets
-- worse on a game build that can't wrap the button.
do
	local test = Setup({ failWrap = function(frame, script) return script == "OnClick" and frame.name == "EldoUI_ClickCastHover" end })
	local a = test.Button("A", "raid3")
	test.Parts()
	Check(a.wraps.OnEnter ~= nil, "failed OnClick wrap: frames still get the hover wrapper")
	Enter(a)
	CheckUnit("SHIFT-F", "raid3", "without wrapper, hovered")
	a.attributes.unit = "raid2"
	CheckUnit("SHIFT-F", "raid3", "without wrapper, old unit after the change (the F16 fault)")
	Leave(a)
	CheckUnit("SHIFT-F", nil, "without wrapper, mouse left")
end

print(("%d checks passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
