-- Offline test for the Profiles page's rows (review fehler.md, F18).
-- Run from the repository root:
--   lua5.1 tools/config/test_profile_page.lua
-- Seen in the game: "New profile" did nothing after Enter. A row set the
-- value, then redrew itself (an input row when it loses the focus, a select
-- right after the pick), and only then refreshed the page. Redrawing reads
-- the page's target again, and the Profiles page's target clears its action
-- values there, so the page never saw the typed name or the pick.
-- This cuts the real parts out of the files (between fixed markers, so a
-- renamed part makes the test fail instead of testing a stale copy):
--   * EldoUI/Core/Config.lua: dotted paths, SetOption, the select and the
--     input row builders;
--   * EldoUI/Core/Share.lua: the Profiles page (rows, target, refresh).
-- Around them: an edit box that runs its focus-lost scripts when it loses
-- the focus (as the game does), a select menu, and EldoUI's profile calls.
-- Checked: Enter in "New profile" and "Rename", a pick in "Profile for this
-- character", "Copy parts from", "Copy everything from" and "Delete a
-- profile" reach the page; the old order loses them (the model reproduces
-- the game); every row kind in Config.lua refreshes the page before it
-- redraws itself.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/config/") or "./"

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

local config = ReadFile("EldoUI/Core/Config.lua")
local share = ReadFile("EldoUI/Core/Share.lua")

local configChunk = assert(loadstring(table.concat({
	"local E, L, env = ...",
	"local Tree, builders, Recent = env.Tree, env.builders, env.Recent",
	"local Cell, EditBox, Attach, Changed, SelectValues = env.Cell, env.EditBox, env.Attach, env.Changed, env.SelectValues",
	"local Box, Text, TEXT, CHEVRON, SECONDARY = env.Box, env.Text, env.TEXT, env.CHEVRON, env.SECONDARY",
	"local Speaker, AddTooltip, RowHover, BoxHover, Sounds = env.Speaker, env.AddTooltip, env.RowHover, env.BoxHover, env.Sounds",
	Between(config, "local function GetPath(root, path)", "-- Labels may carry color codes", "Config.lua paths"),
	Between(config, "local function SetOption(page, option, value)", "-- A copy into a whole settings table", "Config.lua SetOption"),
	Between(config, "function builders.select(parent, option, page, tab)", "-- Media picker (sounds, fonts, bar textures)", "Config.lua select"),
	Between(config, "function builders.input(parent, option, page, tab)", "-- An execute row's", "Config.lua input"),
	"return SetOption",
}, "\n"), "=Config.lua parts"))

local shareChunk = assert(loadstring(table.concat({
	"local E, L = ...",
	Between(share, "local profileProxy = ", 'E:RegisterEvent("ADDON_LOADED", function(_, _, addon)', "Share.lua Profiles page"),
	"return profileOptions, ProfileTarget, ProfileRefresh",
}, "\n"), "=Share.lua Profiles page"))

---------------------------------------------------------------------------
-- The game and EldoUI around them
---------------------------------------------------------------------------
local function noop() end
-- A widget: methods (capitalized names) do nothing unless defined; fields
-- stay nil.
local function Widget(object)
	object = object or {}
	object.scripts, object.hooks = object.scripts or {}, object.hooks or {}
	function object:SetScript(name, fn) self.scripts[name] = fn end
	function object:GetScript(name) return self.scripts[name] end
	function object:HookScript(name, fn)
		self.hooks[name] = self.hooks[name] or {}
		table.insert(self.hooks[name], fn)
	end
	function object:CreateTexture() return Widget() end
	function object:SetText(text) self.text_ = text end
	function object:GetText() return self.text_ end
	return setmetatable(object, { __index = function(_, key)
		if type(key) == "string" and key:match("^%u") then return noop end
	end })
end

-- The game's edit box: ClearFocus runs the focus-lost scripts at once.
local function NewEditBox()
	local box = Widget({ focus = false })
	box.text_ = ""
	function box:HasFocus() return self.focus end
	function box:SetFocus() self.focus = true end
	function box:ClearFocus()
		if not self.focus then return end
		self.focus = false
		if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
		for _, fn in ipairs(self.hooks.OnEditFocusLost or {}) do fn(self) end
	end
	return box
end

local world
local frames
CreateFrame = function() local frame = Widget(); frames[#frames + 1] = frame; return frame end
ACCEPT = "Accept"
IsInRaid = function() return false end
strtrim = function(text) return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function Setup()
	world = { switched = {}, renamed = {}, copied = {}, copiedParts = {}, deleted = {}, printed = {}, confirms = 0 }
	frames = {}
	EldoUIDB = { profiles = { Main = {}, Alt = {} } }
	local L = setmetatable({}, { __index = function(_, key) return key end })
	local E = { profileName = "Main", charKey = "Me - Realm", tokens = { size = { label = 12, body = 12 }, height = { row = 20 } },
		UIKit = { RegisterKeyControl = noop } }
	function E.DeepEqual(a, b) return a == b end
	function E:TextScale() return 1 end
	function E:ModuleStatesPerCharacter() return false end
	function E:GetProfileList() local list = {} for name in pairs(EldoUIDB.profiles) do list[#list + 1] = name end table.sort(list) return list end
	function E:RawValues(values) return values end
	function E:IsRawValues() return true end
	function E:Highlight(text) return text end
	function E:Print(text) world.printed[#world.printed + 1] = text end
	function E:RunOutOfCombat(fn) fn() return true end
	function E:CheckProfileName(name)
		name = strtrim(name)
		if name == "" then return nil, "Type a name first." end
		return name
	end
	function E:SetProfile(name)
		world.switched[#world.switched + 1] = name
		EldoUIDB.profiles[name] = EldoUIDB.profiles[name] or {}
		E.profileName = name
		return true
	end
	function E:RenameProfile(old, new)
		world.renamed[#world.renamed + 1] = old .. ">" .. new
		EldoUIDB.profiles[new], EldoUIDB.profiles[old] = EldoUIDB.profiles[old], nil
		E.profileName = new
		return true
	end
	function E:CopyProfile(from) world.copied[#world.copied + 1] = from return true end
	function E:ShowCopyParts(from) world.copiedParts[#world.copiedParts + 1] = from end
	function E:DeleteProfile(name) world.deleted[#world.deleted + 1] = name EldoUIDB.profiles[name] = nil return true end
	-- Since EldoUI 0.7.3000: the questions name the other users, and a copy
	-- is kept before a reset, copy or delete (here: the change runs at once).
	function E:ProfileUsers() return { E.charKey } end
	function E:ChangeProfileWithUndo(_, _, change) return change() end
	-- The shared question: answered with Accept at once.
	function E:ShowConfirm(info) world.confirms = world.confirms + 1 if info.onAccept then info.onAccept() end end
	-- The options window redraws every row it shows.
	local cells = {}
	function E:RefreshConfig() for _, cell in ipairs(cells) do cell.refresh() end end

	-- The select menu: the picks it offers, by name.
	local menu
	E.UIKit.ContextMenu = function(_, build)
		menu = {}
		local root = Widget()
		function root:CreateRadio(name, _, pick) menu[name] = pick return Widget() end
		build(nil, root)
	end

	local env = {
		Tree = { ControlWidth = function() return 200 end, NoChoices = function() return false end,
			RootOf = function(page, option)
				if type(option.root) == "function" then return option.root() end
				return page.target()
			end },
		builders = {},
		Recent = { log = {}, MAX = 20, Copy = function(value) return value end },
		Cell = function() local cell = Widget({ controls = {}, label = Widget() }); cells[#cells + 1] = cell; return cell end,
		EditBox = function() local box = NewEditBox(); world.box = box; return box end,
		Attach = noop,
		-- The renderer's Changed: the page's refresh first (Config.lua).
		Changed = function(page) page.refresh() end,
		SelectValues = function(option)
			local values = option.values
			if type(values) == "function" then values = values() end
			return type(values) == "table" and values or {}
		end,
		Box = noop, Text = function() return Widget() end, TEXT = {}, CHEVRON = "chevron", SECONDARY = { 0.6, 0.6, 0.6 },
		Speaker = function() return Widget() end, AddTooltip = noop, RowHover = noop, BoxHover = noop, Sounds = {},
	}
	local SetOption = configChunk(E, L, env)
	local options, target, refresh = shareChunk(E, L)
	local page = { id = "profiles", target = target, refresh = refresh, options = options }
	local function Option(key)
		for _, option in ipairs(options) do if option.key == key then return option end end
		error("no row " .. key)
	end
	local test = { E = E, page = page, Option = Option, SetOption = SetOption }
	-- Type into an input row and press Enter.
	function test.Type(key, text)
		local cell = env.builders.input(Widget(), Option(key), page, {})
		cell.refresh()
		local box = world.box
		box:SetFocus()
		box:SetText(text)
		box.scripts.OnEnterPressed(box)
		return box
	end
	-- Open a select row and pick a value.
	function test.Pick(key, value)
		local cell = env.builders.select(Widget(), Option(key), page, {})
		cell.refresh()
		local button = frames[#frames]
		button.scripts.OnClick(button)
		assert(menu and menu[value], "no choice " .. tostring(value) .. " in " .. key)
		menu[value]()
		return cell
	end
	return test
end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
local passed, failed = 0, 0
local function Check(ok, what)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. what) end
end

-- Input rows.
do
	local test = Setup()
	local box = test.Type("new", "Test")
	Check(world.switched[1] == "Test" and #world.switched == 1, "New profile: Enter makes and uses the profile (got " .. tostring(world.switched[1]) .. ")")
	Check(test.E.profileName == "Test", "New profile: this character uses it")
	Check(box:GetText() == "" and not box:HasFocus(), "New profile: the box is empty again afterwards")

	test = Setup()
	test.Type("new", "Alt")
	Check(#world.switched == 0 and world.printed[1] == "A profile with that name already exists.", "New profile: a name in use says so")

	test = Setup()
	test.Type("new", "   ")
	Check(#world.switched == 0 and world.printed[1] == "Type a name first.", "New profile: an empty name says so")

	test = Setup()
	test.Type("rename", "Raid")
	Check(world.renamed[1] == "Main>Raid", "Rename: Enter renames this profile (got " .. tostring(world.renamed[1]) .. ")")
end

-- Select rows.
do
	local test = Setup()
	test.Pick("current", "Alt")
	Check(world.switched[1] == "Alt" and test.E.profileName == "Alt", "Profile for this character: the pick switches (got " .. tostring(world.switched[1]) .. ")")

	test = Setup()
	test.Pick("copyParts", "Alt")
	Check(world.copiedParts[1] == "Alt", "Copy parts from: opens the parts for the picked profile")
	test = Setup()
	test.Pick("copyFrom", "Alt")
	Check(world.confirms == 1 and world.copied[1] == "Alt", "Copy everything from: asks, then copies")
	test = Setup()
	test.Pick("delete", "Alt")
	Check(world.confirms == 1 and world.deleted[1] == "Alt" and EldoUIDB.profiles.Alt == nil, "Delete a profile: asks, then deletes")
	Check(#world.switched == 0, "Delete a profile: no switch on the way")
end

-- The model reproduces the game: in the old order (redraw, then the page)
-- the typed name is gone before the page looks.
do
	local test = Setup()
	local option = test.Option("new")
	test.SetOption(test.page, option, "Test")
	test.page.target() -- the row's redraw when the box loses the focus
	test.page.refresh()
	Check(#world.switched == 0, "old order: the name is lost (as seen in the game)")
end

-- Every row kind in Config.lua: after SetOption the page's refresh comes
-- before the row's own redraw (cell.refresh or ClearFocus, whichever is
-- first). Five rows redraw themselves after a change: the number box of a
-- slider, select, media, color, input.
do
	local found = 0
	for at in config:gmatch("()SetOption%(page, option, ") do
		local tail = config:sub(at, at + 400)
		local refresh, focus = tail:find("cell.refresh()", 1, true), tail:find(":ClearFocus()", 1, true)
		local redraw = refresh and focus and math.min(refresh, focus) or refresh or focus
		local changed = tail:find("Changed(page, tab, option)", 1, true)
		local nextSet = tail:find("SetOption(page, option, ", 2, true)
		if redraw and (not nextSet or redraw < nextSet) and changed and (not nextSet or changed < nextSet) then
			found = found + 1
			local line = select(2, config:sub(1, at):gsub("\n", "\n")) + 1
			Check(changed < redraw, ("Config.lua:%d: the page refreshes before the row redraws"):format(line))
		end
	end
	Check(found == 5, ("five rows redraw themselves after a change (found %d)"):format(found))
end

print(("%d checks passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
