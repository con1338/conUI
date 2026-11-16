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
-- (one line only) is handled the same way; at the level cap, with the
-- switch off, with the Blizzard UI switch off or the module off, every
-- title gets Blizzard's text back, but a title Blizzard wrote again since
-- is left alone; the hook is added once; defaults, Minimal and options.
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
	return fs
end

local function NewRow(questID, title, width, maxLines)
	local row = { questID = questID, Text = NewFontString(width or 40, maxLines) }
	row.Text:SetText(title)
	row.Text.sets = 0
	return row
end

-- Blizzard's update: every title written again, then the post-hooks.
local function BlizzardUpdate()
	for _, row in ipairs(world.rows) do row.Text:SetText(row.blizzard) end
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
QuestScrollFrame = { titleFramePool = { EnumerateActive = function()
	local index = 0
	return function()
		index = index + 1
		return world.rows[index]
	end
end } }

local function Setup()
	world = { xp = {}, rows = {}, hooks = {}, allowed = true, maxLevel = false }
	local L = setmetatable({}, { __index = function(_, key) return key end })
	local test = { parts = {}, options = {} }
	local M = { name = "QoL", active = true, defaults = {}, db = {} }
	function M:AddPart(name, hooks) test.parts[name] = hooks end
	function M:AddOptions(tab, rows) for _, row in ipairs(rows) do table.insert(test.options, { tab = tab, row = row }) end end
	local minimal = { key = "Minimal", settings = { summonPrompt = true } }
	local E = { L = L, styles = { QoL = { { key = "Default", settings = {} }, minimal } } }
	function E.Plain(value) if value == SECRET then return nil end return value end
	function E:GetModule(name) if name == "QoL" then return M end end
	function E:BlizzardAllowed(id, action) return id == "world-map-quest-log" and action == "improve" and world.allowed end
	function E:BlizzardNeeds() return function() return not world.allowed end end
	function E:AtMaxLevel() return world.maxLevel end
	function E:OnBlizzardAddOn(_, fn) fn() end
	chunk(nil, E)
	for key, value in pairs(M.defaults) do M.db[key] = value end
	test.M, test.E, test.minimal = M, E, minimal
	return test
end

local function AddRow(questID, title, xp, width, maxLines)
	local row = NewRow(questID, title, width, maxLines)
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

print(("%d checks passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
