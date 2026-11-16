-- EldoUI Quality of Life: the XP each quest gives, after its title in the
-- quest log (Quests tab > Rewards, on by default).
--
--   [24] The Collector  +1,250 XP
--
-- The number is the game's own (GetQuestLogRewardXP), the same one the XP
-- bar adds up for finished quests, and it shows in that part's yellow. It
-- helps to choose which quest goes when the log is full. Nothing shows at
-- the level cap, or for a quest that gives no XP.
--
-- The world map's quest list (QuestScrollFrame), the one WoW: Forever uses
-- (Modules/QuestTint.lua). Blizzard writes every title again on each update
-- and sizes the row to the title first, so the XP only goes in when the
-- title keeps its number of lines: otherwise the end of the title gives way
-- to "..." (a title that would end up almost empty keeps no XP). What
-- EldoUI changed lives in this file's weak table; switched off, each
-- title gets Blizzard's text back. Text only: no Blizzard table gets a
-- field, and the hook is a post-hook.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local M = E:GetModule("QoL")

M.defaults.questXP = true

-- Minimal keeps Blizzard's own quest log (Modules/QoL.lua, "Minimal").
for _, style in ipairs(E.styles and E.styles.QoL or {}) do
	if style.key == "Minimal" and type(style.settings) == "table" then style.settings.questXP = false end
end

local Plain = E.Plain
local COLOR = "|cffffd100"     -- the XP bar's finished-quest yellow (Modules/StatusBars.lua)
local MIN_TITLE = 10           -- bytes of title (with its "[24] ") worth keeping

-- fontString -> { set = the text EldoUI wrote, original = Blizzard's text }
local changed = setmetatable({}, { __mode = "k" })

local function QuestXP(questID)
	questID = tonumber(Plain(questID))
	if not questID or type(GetQuestLogRewardXP) ~= "function" then return nil end
	local ok, xp = pcall(GetQuestLogRewardXP, questID)
	xp = ok and tonumber(Plain(xp)) or nil
	if not xp or xp <= 0 then return nil end
	return xp
end

local function Amount(xp)
	if type(BreakUpLargeNumbers) == "function" then
		local ok, text = pcall(BreakUpLargeNumbers, xp)
		if ok and type(Plain(text)) == "string" then return text end
	end
	return tostring(math.floor(xp + 0.5))
end

-- "  +1,250 XP" in the yellow; the title before it may end with its own "|r".
local function Suffix(xp)
	return "  " .. COLOR .. L["+%s XP"]:format(Amount(xp)) .. "|r"
end
M.QuestXPSuffix = Suffix -- tools/qol/test_quest_xp.lua

local function Lines(fontString)
	if not fontString.GetNumLines then return nil end
	local ok, lines = pcall(fontString.GetNumLines, fontString)
	lines = ok and Plain(lines)
	return type(lines) == "number" and lines or nil
end

local function Truncated(fontString)
	if not fontString.IsTruncated then return false end
	local ok, truncated = pcall(fontString.IsTruncated, fontString)
	return ok and Plain(truncated) == true
end

local function DropLastChar(text)
	return (text:gsub("[%z\1-\127\194-\244][\128-\191]*$", ""))
end

-- Did the title outgrow the row Blizzard sized for it?
local function Outgrown(fontString, before)
	local now = Lines(fontString)
	if before and now and now > before then return true end
	return Truncated(fontString)
end

-- Puts the XP after one title. True when it is there now.
function M:AddQuestXP(fontString, questID)
	if not (fontString and fontString.GetText and fontString.SetText) then return false end
	local text = Plain(fontString:GetText())
	if type(text) ~= "string" or text == "" then return false end
	local xp = QuestXP(questID)
	if not xp then return false end
	local suffix = Suffix(xp)
	local entry = changed[fontString]
	if (entry and entry.set == text) or text:sub(-#suffix) == suffix then return true end
	local before = Lines(fontString)
	fontString:SetText(text .. suffix)
	-- Also a title the game already cut off: the XP must stay readable.
	if Outgrown(fontString, before) then
		-- The title's color code ends with "|r": keep it at the end.
		local tail = text:match("|r$") and "|r" or ""
		local title = tail ~= "" and text:sub(1, -3) or text
		local guard, fits = 0, false
		while #title > MIN_TITLE and guard < 200 do
			guard = guard + 1
			title = DropLastChar(title):gsub("%s+$", "")
			fontString:SetText(title .. "..." .. tail .. suffix)
			if not Outgrown(fontString, before) then fits = true break end
		end
		if not fits then
			fontString:SetText(text)
			changed[fontString] = nil
			return false
		end
	end
	changed[fontString] = { set = fontString:GetText(), original = text }
	return true
end

-- Blizzard's text back on every title EldoUI changed (and still shows so).
function M:RemoveQuestXP()
	for fontString, entry in pairs(changed) do
		if Plain(fontString:GetText()) == entry.set then fontString:SetText(entry.original) end
		changed[fontString] = nil
	end
end

local function Wanted()
	return M.active and M.db.questXP and E:BlizzardAllowed("world-map-quest-log", "improve") and not E:AtMaxLevel()
end

function M:UpdateQuestXP()
	if not Wanted() then
		self:RemoveQuestXP()
		return
	end
	local scroll = rawget(_G, "QuestScrollFrame")
	local pool = scroll and scroll.titleFramePool
	if not (pool and pool.EnumerateActive) then return end
	for button in pool:EnumerateActive() do
		local text = button.Text or (button.GetFontString and button:GetFontString())
		if text then self:AddQuestXP(text, button.questID) end
	end
end

local function Hook()
	if M.questXPHooked or type(rawget(_G, "QuestLogQuests_Update")) ~= "function" then return end
	hooksecurefunc("QuestLogQuests_Update", function() M:UpdateQuestXP() end)
	M.questXPHooked = true
end

-- This part's place in the module's life cycle (Modules/QoL.lua, AddPart).
M:AddPart("QuestXP", {
	enable = function(self)
		Hook()
		-- The quest list comes with the world map, which may load later.
		E:OnBlizzardAddOn("Blizzard_WorldMap", Hook)
		self:UpdateQuestXP()
	end,
	disable = function(self) self:RemoveQuestXP() end,
	profile = function(self) self:UpdateQuestXP() end,
})

-- After the Quests tab's "Rewards" section (Modules/QoL/Tweaks.lua).
M:AddOptions("Quests", {
	{ type = "toggle", key = "questXP", label = "XP in the quest log", disabled = E:BlizzardNeeds("world-map-quest-log", "improve"),
		desc = "The XP each quest gives when you hand it in, after its title in the quest log, in the yellow of the finished quests on the XP bar. Hidden at the level cap." },
})
