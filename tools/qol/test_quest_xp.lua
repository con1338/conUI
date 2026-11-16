-- Offline test for the XP after each title in the quest log (Quality of
-- Life > Quests > Rewards; review verbesserungen.md, B8).
-- Run from the repository root:
--   lua5.1 tools/qol/test_quest_xp.lua
-- It loads EldoUI/Modules/QoL/QuestXP.lua as it is, with stand-ins for the
-- QoL module, the quest API and the world map's quest list. A title is a
-- font string that wraps after a set number of characters, as Blizzard's
-- row does after it sized itself to the title.
-- Checked: the XP goes after the title once (also when the hook runs again
-- without Blizzard writing the title), in the XP bar's yellow; quests with
-- no XP, a secret or failing answer stay as they are; a title that would
-- take another line gives way to "..." and keeps its color code, one that
-- would end up almost empty keeps no XP; a title that cuts itself off
-- (one line only) is handled the same way; the color follows the XP bar's
-- "Quest XP color"; Quest Marks' difficulty word goes in before the fit is
-- measured, also when its hook runs after this one; a tracked quest's tick
-- follows the title's new end (and back), other anchors stay; at the level
-- cap, while XP gain is locked, with the switch off, with the Blizzard UI
-- switch off or the module off, every title gets Blizzard's text back, but
-- a title Blizzard wrote again since is left alone; the hook is added
-- once; defaults, Minimal and options.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/qol/") or "./"

local function ReadFile(path)
	local file = assert(io.open(ROOT .. path, "rb"), "can't open " .. path)
	local text = file:read("*a")
	file:close()
	return (text:gsub("\r\n", "\n"))
end
local chunk = assert(loadstring(ReadFile("EldoUI/Modules/QoL/QuestXP.lua"), "=QuestXP.lua"))

---------------------------------------------------------------------------
-- The game
---------------------------------------------------------------------------
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
local YELLOW = "|cffffd100"
local world

-- Characters the reader sees: no color codes, UTF-8 counted once.
local function Visible(text)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return #(text:gsub("[\128-\191]", ""))
end

local function NewFontString(width, maxLines)
	local fs = { width = width, maxLines = maxLines, text = "", sets = 0 }
	function fs:SetText(text) self.text = text self.sets = self.sets + 1 end
	function fs:GetText() return self.secret and SECRET or self.text end
	function fs:FullLines() return math.max(1, math.ceil(Visible(self.text) / self.width)) end
	function fs:GetNumLines()
		local lines = self:FullLines()
		if self.maxLines then lines = math.min(lines, self.maxLines) end
		return lines
	end
	function fs:IsTruncated() return self.maxLines ~= nil and self:FullLines() > self.maxLines end
	-- One character is one unit wide; a wrapped string is as wide as a line.
	function fs:GetWrappedWidth() return math.min(Visible(self.text), self.width) end
	return fs
end

-- The tick of a tracked quest: anchored like Blizzard's row code does it,
-- just after the title's text.
local function NewTick()
	local tick = { points = {} }
	function tick:SetPoint(point, relativeTo, relativePoint, x, y)
		self.points = { { point, relativeTo, relativePoint, x, y } }
	end
	function tick:GetNumPoints() return #self.points end
	function tick:GetPoint(index) return unpack(self.points[index]) end
	return tick
end

local function PlaceTick(row)
	if row.Check then row.Check:SetPoint("LEFT", row.Text, "LEFT", row.Text:GetWrappedWidth() + 2, 0) end
end

local function NewRow(questID, title, width, maxLines, tracked)
	local row = { questID = questID, Text = NewFontString(width or 40, maxLines) }
	row.Text:SetText(title)
	row.Text.sets = 0
	if tracked then
		row.Check = NewTick()
		PlaceTick(row)
	end
	return row
end

-- Blizzard's update: every title written again (and its tick placed),
-- then the post-hooks in the order they were added.
local function BlizzardUpdate()
	for _, row in ipairs(world.rows) do
		row.Text:SetText(row.blizzard)
		PlaceTick(row)
	end
	for _, fn in ipairs(world.hooks.QuestLogQuests_Update or {}) do fn() end
end

function GetQuestLogRewardXP(questID)
	local xp = world.xp[questID]
	if xp == "error" then error("no such quest") end
	return xp
end
function BreakUpLargeNumbers(value)
	local text = tostring(value)
	while true do
		local changed
		text, changed = text:gsub("^(%d+)(%d%d%d)", "%1,%2")
		if changed == 0 then return text end
	end
end
function hooksecurefunc(name, fn)
	world.hooks[name] = world.hooks[name] or {}
	table.insert(world.hooks[name], fn)
end
function QuestLogQuests_Update() end
function IsXPUserDisabled() return world.xpLocked end
function geterrorhandler() return function(err) table.insert(world.errors, err) end end
QuestScrollFrame = { titleFramePool = { EnumerateActive = function()
	local index = 0
	return function()
		index = index + 1
		return world.rows[index]
	end
end } }

local function Setup()
	world = { xp = {}, rows = {}, hooks = {}, allowed = true, maxLevel = false, xpLocked = false, errors = {} }
	local L = setmetatable({}, { __index = function(_, key) return key end })
	local test = { parts = {}, options = {} }
	local M = { name = "QoL", active = true, defaults = {}, db = {} }
	function M:AddPart(name, hooks) test.parts[name] = hooks end
	function M:AddOptions(tab, rows) for _, row in ipairs(rows) do table.insert(test.options, { tab = tab, row = row }) end end
	local minimal = { key = "Minimal", settings = { summonPrompt = true } }
	local E = { L = L, styles = { QoL = { { key = "Default", settings = {} }, minimal } } }
	function E.Plain(value) if value == SECRET then return nil end return value end
	function E.PlainCall(fn, ...)
		if type(fn) ~= "function" then return nil end
		local ok, value = pcall(fn, ...)
		if not ok or value == SECRET then return nil end
		return value
	end
	function E:GetModule(name)
		if name == "QoL" then return M end
		if name == "StatusBars" then return world.bars end
		if name == "QuestTint" then return world.tint end
	end
	function E:BlizzardAllowed(id, action) return id == "world-map-quest-log" and action == "improve" and world.allowed end
	function E:BlizzardNeeds() return function() return not world.allowed end end
	function E:AtMaxLevel() return world.maxLevel end
	function E:OnBlizzardAddOn(_, fn) fn() end
	chunk(nil, E)
	for key, value in pairs(M.defaults) do M.db[key] = value end
	test.M, test.E, test.minimal = M, E, minimal
	return test
end

local function AddRow(questID, title, xp, width, maxLines, tracked)
	local row = NewRow(questID, title, width, maxLines, tracked)
	row.blizzard = title
	world.xp[questID] = xp
	table.insert(world.rows, row)
	return row
end

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

-- Defaults, presets, options, life cycle.
do
	local test = Setup()
	Check(test.M.defaults.questXP == true, "on by default")
	Check(test.minimal.settings.questXP == false and test.minimal.settings.summonPrompt == true, "Minimal turns it off and keeps the rest")
	local option = test.options[1]
	Check(#test.options == 1 and option.tab == "Quests" and option.row.key == "questXP" and option.row.type == "toggle", "one switch on the Quests tab")
	Check(type(option.row.disabled) == "function", "the switch follows the Blizzard UI switch of the quest log")
	local part = test.parts.QuestXP
	Check(part and part.enable and part.disable and part.profile, "a part with enable, disable and profile")
	Check(test.M.QuestXPSuffix(1250) == "  " .. YELLOW .. "+1,250 XP|r", "the suffix: game number in yellow")
end

-- The XP after the title, once.
do
	local test = Setup()
	local M = test.M
	local plain = AddRow(101, "[24] The Collector", 1250)
	local none = AddRow(102, "[24] A Letter", 0)
	local missing = AddRow(103, "[24] No Reward", nil)
	local secret = AddRow(104, "[24] Hidden", SECRET)
	local broken = AddRow(105, "[24] Broken", "error")
	test.parts.QuestXP.enable(M)
	Is(#world.hooks.QuestLogQuests_Update, 1, "the quest list update is hooked")
	Is(plain.Text.text, "[24] The Collector  " .. YELLOW .. "+1,250 XP|r", "XP after the title, at enable")
	Is(none.Text.text, "[24] A Letter", "no XP: title as it is")
	Is(missing.Text.text, "[24] No Reward", "no answer: title as it is")
	Is(secret.Text.text, "[24] Hidden", "secret XP: title as it is")
	Is(broken.Text.text, "[24] Broken", "an error from the game: title as it is")
	local sets = plain.Text.sets
	M:UpdateQuestXP()
	Is(plain.Text.sets, sets, "the hook again without Blizzard: nothing written again")
	Is(plain.Text.text, "[24] The Collector  " .. YELLOW .. "+1,250 XP|r", "still once")
	BlizzardUpdate()
	Is(plain.Text.text, "[24] The Collector  " .. YELLOW .. "+1,250 XP|r", "Blizzard writes the title again: XP once")
	test.parts.QuestXP.enable(M)
	Is(#world.hooks.QuestLogQuests_Update, 1, "enabled again: still one hook")
	-- Another part of EldoUI rewrote the title after this one (Quest
	-- Marks' difficulty word): the XP at the end is still seen as there.
	plain.Text:SetText("[24 hard] The Collector  " .. YELLOW .. "+1,250 XP|r")
	M:UpdateQuestXP()
	Is(plain.Text.text, "[24 hard] The Collector  " .. YELLOW .. "+1,250 XP|r", "a rewritten title with the XP: not added twice")
	world.rows[1].Text.secret = true
	M:UpdateQuestXP()
	world.rows[1].Text.secret = nil
	Check(true, "a secret title is skipped without an error")
end

-- Titles that would take another line.
do
	local test = Setup()
	local M = test.M
	-- 30 characters per line. 24 characters: one line; with the XP, two.
	local long = AddRow(201, "[24] The Missing Diplomat", 1550, 30)
	-- A color code and two lines already: the XP fits on the second.
	local colored = AddRow(202, "|cffff0000[30] The Shadowy Figure of Lake|r", 2100, 30)
	-- Too narrow: the XP would leave only a few letters of the title.
	local narrow = AddRow(203, "[24] Bloodsail", 900, 15)
	-- One line only, cut off by the game.
	local single = AddRow(204, "[24] Down the Coast", 700, 26, 1)
	test.parts.QuestXP.enable(M)
	Is(long.Text:GetNumLines(), 1, "long title: still one line")
	local suffix = "  " .. YELLOW .. "+1,550 XP|r"
	Is(long.Text.text:sub(-#suffix), suffix, "long title: XP kept at the end")
	Check(long.Text.text:find("^%[24%] The Missing") ~= nil and long.Text.text:find("...", 1, true) ~= nil,
		"long title: its end gives way to ... (" .. long.Text.text .. ")")
	Is(colored.Text:GetNumLines(), 2, "two-line title: still two lines")
	Is(colored.Text.text, "|cffff0000[30] The Shadowy Figure of Lake|r  " .. YELLOW .. "+2,100 XP|r", "two-line title: XP fits, color code kept")
	Is(narrow.Text.text, "[24] Bloodsail", "almost nothing left of the title: no XP, Blizzard's title")
	Check(not single.Text:IsTruncated(), "single-line title: not cut off by the game")
	Check(single.Text.text:find("+700 XP|r$") ~= nil and single.Text.text:find("...", 1, true) ~= nil,
		"single-line title: shortened, XP kept (" .. single.Text.text .. ")")
	-- A title the game already cut off: shortened until the XP shows.
	local test2 = Setup()
	local cut = AddRow(205, "[24] An Already Very Long Quest Title Here", 300, 30, 1)
	test2.parts.QuestXP.enable(test2.M)
	Check(not cut.Text:IsTruncated() and cut.Text.text:find("+300 XP|r", 1, true) ~= nil,
		"a title cut off before: shortened, the XP readable (" .. cut.Text.text .. ")")
end

-- Back to Blizzard's text.
do
	local test = Setup()
	local M = test.M
	local row = AddRow(301, "[24] The Collector", 1250)
	local other = AddRow(302, "[25] Elmore's Task", 600)
	test.parts.QuestXP.enable(M)
	M.db.questXP = false
	test.parts.QuestXP.profile(M)
	Is(row.Text.text, "[24] The Collector", "switch off: Blizzard's title back")
	Is(other.Text.text, "[25] Elmore's Task", "switch off: every title")
	BlizzardUpdate()
	Is(row.Text.text, "[24] The Collector", "switch off: no XP after Blizzard's next update")
	M.db.questXP = true
	test.parts.QuestXP.profile(M)
	Check(row.Text.text:find("+1,250 XP", 1, true) ~= nil, "switch on: XP again")

	world.maxLevel = true
	BlizzardUpdate()
	Is(row.Text.text, "[24] The Collector", "level cap: no XP")
	world.maxLevel = false
	BlizzardUpdate()
	Check(row.Text.text:find("+1,250 XP", 1, true) ~= nil, "below the cap again: XP")

	world.allowed = false
	test.parts.QuestXP.profile(M)
	Is(row.Text.text, "[24] The Collector", "Blizzard UI switch off: Blizzard's title")
	world.allowed = true
	test.parts.QuestXP.profile(M)

	-- Blizzard wrote another quest's title into the row since: left alone.
	row.Text:SetText("[26] Another Quest")
	M.active = false
	test.parts.QuestXP.disable(M)
	Is(row.Text.text, "[26] Another Quest", "a title Blizzard wrote since: not touched")
	Is(other.Text.text, "[25] Elmore's Task", "module off: the other title back")
	BlizzardUpdate()
	Is(other.Text.text, "[25] Elmore's Task", "module off: the hook adds nothing")
end

-- The color follows the XP bar's "Quest XP color".
do
	local test = Setup()
	world.bars = { db = { xp = { questColor = { 0.2, 0.4, 1.0 } } } }
	Is(test.M.QuestXPSuffix(80), "  |cff3366ff+80 XP|r", "the XP bar's own quest color")
	world.bars = { db = { xp = { questColor = { 2, -1, "x" } } } }
	Is(test.M.QuestXPSuffix(80), "  |cffff0000+80 XP|r", "a broken color: clamped, the default for a missing part")
	world.bars = { db = {} }
	Is(test.M.QuestXPSuffix(80), "  " .. YELLOW .. "+80 XP|r", "no color saved: the default yellow")
	-- A color change while Quest Marks rewrote the title: no second XP.
	world.bars = nil
	local row = AddRow(401, "[24] The Collector", 1250)
	test.parts.QuestXP.enable(test.M)
	row.Text:SetText("[24 hard] The Collector  " .. YELLOW .. "+1,250 XP|r")
	world.bars = { db = { xp = { questColor = { 0.2, 0.4, 1.0 } } } }
	test.M:UpdateQuestXP()
	local _, count = row.Text.text:gsub("XP|r", "")
	Is(count, 1, "new color, rewritten title: the XP stays once")
end

-- Quest Marks' difficulty word (color-blind mode), whichever hook runs first.
do
	local function Tint()
		local tint = { active = true, db = { levelWord = true }, calls = 0 }
		function tint:AddDifficultyWord(fontString)
			self.calls = self.calls + 1
			local text = fontString:GetText()
			local level, rest = text:match("^%[(%d+)%] (.*)$")
			if not level then return false end
			fontString:SetText("[" .. level .. " hard] " .. rest)
			return true
		end
		return tint
	end
	-- This part's hook first, Quest Marks' after it (Quest Marks switched
	-- on later). 30 per line: "[24] The Missing Diplomat" is 25, with the
	-- word 30, with the XP it needs to be shortened.
	local test = Setup()
	world.tint = Tint()
	local row = AddRow(501, "[24] The Missing Diplomat", 1550, 30)
	test.parts.QuestXP.enable(test.M)
	hooksecurefunc("QuestLogQuests_Update", function() world.tint:AddDifficultyWord(row.Text) end)
	BlizzardUpdate()
	Check(row.Text.text:find("^%[24 hard%] ") ~= nil, "the word is in (" .. row.Text.text .. ")")
	Is(row.Text:GetNumLines(), 1, "measured with the word: still one line")
	Check(row.Text.text:find("+1,550 XP|r", 1, true) ~= nil, "and the XP is there")
	-- Quest Marks off: no word.
	world.tint.active = false
	world.rows[1].blizzard = "[24] The Collector"
	local before = world.tint.calls
	test.M:UpdateQuestXP()
	Is(world.tint.calls, before, "Quest Marks off: its word is not asked for")
	-- An error in Quest Marks: reported, the XP still goes in.
	local test2 = Setup()
	world.tint = { active = true, db = {}, AddDifficultyWord = function() error("boom") end }
	local plain = AddRow(502, "[24] The Collector", 1250)
	test2.parts.QuestXP.enable(test2.M)
	Is(#world.errors, 1, "an error in Quest Marks is reported")
	Check(plain.Text.text:find("+1,250 XP|r", 1, true) ~= nil, "and the XP still goes in")
end

-- The tick of a tracked quest follows the end of the title.
do
	local test = Setup()
	local tracked = AddRow(601, "[24] The Collector", 1250, 40, nil, true)
	local far = AddRow(602, "[24] Elmore's Task", 600, 40, nil, true)
	far.Check:SetPoint("LEFT", far.Text, "LEFT", 32, 0) -- not at the title's end (18 + 14)
	test.parts.QuestXP.enable(test.M)
	local _, relativeTo, _, x = tracked.Check:GetPoint(1)
	Check(relativeTo == tracked.Text, "the tick stays on the title")
	Is(x, tracked.Text:GetWrappedWidth() + 2, "the tick sits after the XP")
	local _, _, _, farX = far.Check:GetPoint(1)
	Is(farX, 32, "a tick that was not at the title's end: left alone")
	local two = AddRow(603, "[24] A Letter", 300, 40, nil, true)
	two.Check.points[2] = { "RIGHT", two.Text, "RIGHT", 0, 0 }
	test.M:UpdateQuestXP()
	Is(two.Check.points[1][4], 13 + 2, "a tick with two anchors: left alone")
	test.M.db.questXP = false
	test.parts.QuestXP.profile(test.M)
	_, _, _, x = tracked.Check:GetPoint(1)
	Is(x, 18 + 2, "switched off: the tick back after Blizzard's title")
end

-- XP gain locked.
do
	local test = Setup()
	local row = AddRow(701, "[24] The Collector", 1250)
	test.parts.QuestXP.enable(test.M)
	world.xpLocked = true
	BlizzardUpdate()
	Is(row.Text.text, "[24] The Collector", "XP gain locked: no XP")
	world.xpLocked = false
	BlizzardUpdate()
	Check(row.Text.text:find("+1,250 XP", 1, true) ~= nil, "unlocked: XP again")
end

print(("%d checks passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
