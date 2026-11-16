-- EldoUI Quest Marks: marks quests the original game did not have, so
-- WoW: Forever's new content is easy to spot.
--
--   * Quest window: a "New in Forever" tag and a tinted quest title.
--   * Quest log: new quests' titles in the tint color.
--   * Quest givers: new quests in the gossip list in the tint color.
--   * Quest tracker: new quests' titles in the tint color.
--   * Tooltips: the tag under a new quest's link, and new quests' titles
--     tinted where a unit tooltip lists them (quest mobs).
--   * World map: the "!" of new quest offers in the tint color.
--
-- Quest levels: WoW: Forever already writes "[24] " in front of
-- quest titles in the quest log and tracker. EldoUI adds the level to the
-- quest giver lists (gossip and quest greeting), where the game shows
-- none, in the game's difficulty color. With the game's color-blind mode
-- on, a difficulty word follows the level in all three places
-- ("[24 hard]"). Right-click on a quest in the log or tracker adds
-- "Wowhead link" and "Remind me when done" (one alert when the quest's
-- objectives are complete). "Show in your journal" comes from My
-- Adventure (LootGuide/Adventure/Entry.lua) when it runs.
--
-- Which quests are new: the original game's quest IDs nearly all sit below
-- 10000, and WoW: Forever's new quests use new, higher IDs. EldoUI_LootData
-- (the original quest lists, from CMaNGOS classic-db: the Loot Guide's
-- quests and the Journal's journey quests) also lists the original quests
-- above 10000. When that folder is installed it is loaded
-- the first time a quest above 10000 shows up (through the Loot Guide's
-- loader, never in combat), and a quest it lists is never marked.
--
-- Only colors and a tag on text Blizzard already shows; nothing is clicked
-- or accepted for the player. Each place follows its Blizzard UI element
-- setting ("improve").
--
-- Taint: every hook is a hooksecurefunc post-hook that only sets text
-- colors, a tracker title's color code (the same title, the tint's code in
-- place of Blizzard's) and a map pin texture's color. No Blizzard table
-- gets a new field and no Blizzard method that writes one is called; what
-- EldoUI tinted is kept in this file's own weak tables.
-- luacheck: read globals EldoUI_LootData
local _, E = ...
local L = E.L


local M = E:NewModule("QuestTint", {
	title = "Quest Marks",
	aliases = { "New in Forever" }, -- earlier title, for search and /eui
	category = "Quality of Life",
	desc = "Marks quests new in WoW: Forever with a tag in the quest window and a tint in the quest log, tracker, tooltips and world map, and shows quest levels in quest giver lists.",
	defaults = {
		questFrame = true,
		titleTint = true,     -- tint the title in the quest window (off: tag only)
		questLog = true,
		gossip = true,
		tracker = true,
		tooltip = true,
		mapPins = true,
		tag = true,
		tagText = "New in Forever",
		color = { 0.25, 0.85, 0.8 },
		-- Quest levels and menu
		levelGossip = true,   -- [24] in quest giver lists
		levelWord = true,     -- "[24 hard]" while the game's color-blind mode is on
		questMenu = true,     -- Wowhead link and Remind me in the quest menus
		chainLine = true,     -- "Part 2 of 5" in the quest window and log (QuestChains.lua)
	},
})
E.QuestTint = M
-- Reminded quests: account-wide, one list per character.
E:RegisterGlobal("QuestTint", { reminders = {} })

M.FIRST_NEW_ID = 10000

local Clean = E.Plain

local function Weak()
	return setmetatable({}, { __mode = "k" })
end

-- The original quest lists from EldoUI_LootData, once it is loaded: the
-- Loot Guide's quests and every other quest a player can pick up (journey).
local function OriginalQuests()
	local data = rawget(_G, "EldoUI_LootData")
	if type(data) ~= "table" or type(data.quests) ~= "table" then return nil end
	return data.quests, type(data.journey) == "table" and data.journey or nil
end

-- Load EldoUI_LootData once, the first time a quest above FIRST_NEW_ID shows
-- up, so the original quests above it are not marked. Through the Loot
-- Guide's loader: it never loads in combat (it waits for the end of combat)
-- and knows when the folder is missing or switched off. Marked places
-- refresh once the list is in.
function M:LoadOriginalList()
	if self.originalAsked then return end
	self.originalAsked = true
	local LG = E.LootGuide
	if not (LG and type(LG.LoadData) == "function") then return end
	C_Timer.After(0, function()
		if not M.active then return end
		local ok, loaded = pcall(LG.LoadData, LG)
		if ok and loaded and OriginalQuests() then M:RefreshAll() end
	end)
end

-- Is this quest new in WoW: Forever?
function M:IsNew(questID)
	questID = tonumber(Clean(questID))
	if not questID or questID < self.FIRST_NEW_ID then return false end
	local original, journey = OriginalQuests()
	if original then return not (original[questID] or (journey and journey[questID])) end
	if self.active then self:LoadOriginalList() end
	return true
end

function E:IsForeverQuest(questID)
	return M.active and M:IsNew(questID) or false
end

local function Color()
	local c = M.db.color or {}
	return c[1] or c.r or 0.25, c[2] or c.g or 0.85, c[3] or c.b or 0.8
end

function M:Hex()
	local r, g, b = Color()
	return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

local function TagText()
	local text = M.db.tagText
	if type(text) ~= "string" or text == "" then return L["New in Forever"] end
	return text
end

local function Allowed(element)
	return M.active and E:BlizzardAllowed(element, "improve")
end

---------------------------------------------------------------------------
-- Quest window (detail, progress, reward)
---------------------------------------------------------------------------
local function CurrentQuestID()
	return GetQuestID and Clean(GetQuestID()) or nil
end

function M:UpdateQuestFrame()
	local frame = _G.QuestFrame
	if not frame then return end
	local show = Allowed("quest-gossip-npc") and self.db.questFrame and frame:IsShown() and self:IsNew(CurrentQuestID())
	if show and self.db.tag and not self.questTag then
		local tag = E:CreateText(frame, E.tokens.size.small, "RIGHT")
		tag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -32)
		self.questTag = tag
	end
	if self.questTag then
		self.questTag:SetText(self:Hex() .. TagText() .. "|r")
		self.questTag:SetShown(show and self.db.tag and true or false)
	end
	if show and self.db.titleTint ~= false then
		local r, g, b = Color()
		for _, name in ipairs({ "QuestInfoTitleHeader", "QuestProgressTitleText" }) do
			local text = _G[name]
			if text and text.SetTextColor then text:SetTextColor(r, g, b) end
		end
	end
	if self.db.chainLine == false then
		if self.HideChainLines then self:HideChainLines() end
	elseif self.UpdateChainLine then
		self:UpdateChainLine()
	end
end

---------------------------------------------------------------------------
-- Quest log (the world map's quest list)
---------------------------------------------------------------------------
local tinted = Weak()

function M:UpdateQuestLog()
	local scroll = _G.QuestScrollFrame
	local pool = scroll and scroll.titleFramePool
	if not (pool and pool.EnumerateActive) then return end
	local on = Allowed("world-map-quest-log") and self.db.questLog
	local r, g, b = Color()
	for button in pool:EnumerateActive() do
		local text = button.Text or (button.GetFontString and button:GetFontString())
		if text and text.SetTextColor then
			if on and self:IsNew(button.questID) then
				text:SetTextColor(r, g, b)
				tinted[button] = true
				self:OfferTintHelp(button)
			elseif tinted[button] then
				-- Blizzard colors the title again on its next update.
				tinted[button] = nil
			end
			if Allowed("world-map-quest-log") then self:AddDifficultyWord(text, button.questID) end
		end
	end
end

---------------------------------------------------------------------------
-- Quest givers (gossip list)
---------------------------------------------------------------------------
local function GossipQuestID(frame, data)
	local info = type(data) == "table" and data.info
	return type(info) == "table" and info.questID or (type(data) == "table" and data.questID) or frame.questID
end

function M:UpdateGossip()
	local frame = _G.GossipFrame
	local box = frame and frame.GreetingPanel and frame.GreetingPanel.ScrollBox
	if not (box and box.ForEachFrame) then return end
	if not (Allowed("quest-gossip-npc") and self.db.gossip) then return end
	local r, g, b = Color()
	box:ForEachFrame(function(button, data)
		data = data or (button.GetElementData and button:GetElementData())
		if self:IsNew(GossipQuestID(button, data)) then
			local text = button.GetFontString and button:GetFontString()
			if text and text.SetTextColor then text:SetTextColor(r, g, b) end
		end
	end)
end

---------------------------------------------------------------------------
-- Quest levels. Levels, difficulty and colors are what the game
-- gives (C_GossipInfo's questLevel, GetActiveLevel / GetAvailableLevel,
-- C_PlayerInfo.GetContentDifficultyQuestForPlayer, GetDifficultyColor);
-- titles are only rewritten when they are plain strings.
---------------------------------------------------------------------------
local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d, e = pcall(fn, ...)
	if not ok then return nil end
	return a, b, c, d, e
end

-- The game's color-blind mode (Options > Accessibility > Colors).
function M:ColorBlind()
	local getter = C_CVar and C_CVar.GetCVarBool or rawget(_G, "GetCVarBool")
	return Clean(Call(getter, "colorblindMode")) == true
end

function M:Difficulty(questID)
	questID = tonumber(Clean(questID))
	if not (questID and C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer) then return nil end
	local difficulty = Clean(Call(C_PlayerInfo.GetContentDifficultyQuestForPlayer, questID))
	return type(difficulty) == "number" and difficulty or nil
end

-- The word for a difficulty (Enum.RelativeContentDifficulty), in the
-- order of the game's colors: gray, green, yellow, orange, red.
function M.DifficultyWord(difficulty)
	local enum = Enum and Enum.RelativeContentDifficulty
	if not enum or type(difficulty) ~= "number" then return nil end
	if difficulty == enum.Trivial then return L["trivial"] end
	if difficulty == enum.Easy then return L["easy"] end
	if difficulty == enum.Fair then return L["fair"] end
	if difficulty == enum.Difficult then return L["hard"] end
	if difficulty == enum.Impossible then return L["very hard"] end
	return nil
end

-- The color code for a quest: its difficulty color, or the level's.
local function DifficultyHex(questID, level, difficulty)
	local color
	if difficulty and type(rawget(_G, "GetDifficultyColor")) == "function" then
		color = Call(GetDifficultyColor, difficulty)
	elseif type(rawget(_G, "GetQuestDifficultyColor")) == "function" then
		color = Call(GetQuestDifficultyColor, level, false, questID)
	end
	if type(color) ~= "table" or type(color.r) ~= "number" then return nil end
	color = E:DifficultyColor(color)
	return ("|cff%02x%02x%02x"):format(color.r * 255 + 0.5, color.g * 255 + 0.5, color.b * 255 + 0.5)
end

-- "[24]", "[24+]" (elite) or "[24 hard]" (color-blind mode), and the
-- difficulty color code; nil without a level.
function M:LevelLabel(level, questID)
	level = tonumber(Clean(level))
	if not level or level <= 0 then return nil end
	questID = tonumber(Clean(questID))
	local elite = questID and C_QuestLog and Clean(Call(C_QuestLog.IsEliteQuest, questID)) == true
	local difficulty = self:Difficulty(questID)
	local word = self.db.levelWord and self:ColorBlind() and M.DifficultyWord(difficulty)
	local label = "[" .. level .. (elite and "+" or "") .. (word and (" " .. word) or "") .. "]"
	return label, DifficultyHex(questID, level, difficulty)
end

-- A quest row of the dialog view (Modules/Dialogue): the level in its
-- difficulty color and a new quest's title in the tint, as the game's
-- quest giver lists get them here. Plain "[24] Title" while this is off.
function M:DialogueRow(title, level, questID)
	title = Clean(title)
	if type(title) ~= "string" then title = "" end
	local on = self.active and type(self.db) == "table"
	if on and self.db.gossip and title ~= "" and self:IsNew(questID) then title = self:Hex() .. title .. "|r" end
	local label, hex
	if on and self.db.levelGossip then label, hex = self:LevelLabel(level, questID) end
	if not label then
		level = tonumber(Clean(level))
		if level and level > 0 then label = "[" .. level .. "]" end
	end
	if not label then return title end
	return (hex and (hex .. label .. "|r") or label) .. " " .. title
end

-- Put the level in front of `title` in a list button's text, once. The
-- color code that wraps the title (NORMAL_QUEST_DISPLAY) is opened again
-- after the level's own color.
function M:PrefixLevel(button, title, level, questID)
	title = Clean(title)
	if type(title) ~= "string" or title == "" or not (button and button.SetText) then return false end
	local fontString = button.GetFontString and button:GetFontString()
	local text = Clean(fontString and fontString:GetText())
	if type(text) ~= "string" then return false end
	local label, hex = self:LevelLabel(level, questID)
	if not label then return false end
	local start = text:find(title, 1, true)
	if not start then return false end
	local before = text:sub(1, start - 1)
	if before:find("[", 1, true) then return false end -- the level is there already
	local code = before:match("(|c%x%x%x%x%x%x%x%x)$")
	local shown = hex and (hex .. label .. "|r" .. (code or "")) or label
	button:SetText(before .. shown .. " " .. text:sub(start))
	return true
end

-- Gossip (C_GossipInfo lists): the level from the element's quest info.
function M:UpdateGossipLevels()
	if not (Allowed("quest-gossip-npc") and self.db.levelGossip) then return end
	local frame = _G.GossipFrame
	local box = frame and frame.GreetingPanel and frame.GreetingPanel.ScrollBox
	if not (box and box.ForEachFrame) then return end
	box:ForEachFrame(function(button, data)
		data = data or (button.GetElementData and button:GetElementData())
		local info = type(data) == "table" and data.info
		if type(info) == "table" and info.questID and info.title then
			if self:PrefixLevel(button, info.title, info.questLevel, info.questID) and button.Resize then pcall(button.Resize, button) end
		end
	end)
end

-- Quest greeting (an NPC with several quests and no gossip).
function M:UpdateGreetingLevels()
	if not (Allowed("quest-gossip-npc") and self.db.levelGossip) then return end
	local panel = _G.QuestFrameGreetingPanel
	local pool = panel and panel.titleButtonPool
	if not (pool and pool.EnumerateActive) then return end
	for button in pool:EnumerateActive() do
		local index = button.GetID and button:GetID()
		if index and index > 0 then
			local title, level, questID
			if button.isActive == 1 then
				title, level, questID = Call(GetActiveTitle, index), Call(GetActiveLevel, index), Call(GetActiveQuestID, index)
			else
				title, level = Call(GetAvailableTitle, index), Call(GetAvailableLevel, index)
				questID = select(5, Call(GetAvailableQuestInfo, index))
			end
			if self:PrefixLevel(button, title, level, questID) then
				-- The height the game gives a title button, for the new text.
				local textHeight = button.GetTextHeight and Clean(button:GetTextHeight())
				local iconHeight = button.Icon and Clean(button.Icon:GetHeight())
				if type(textHeight) == "number" then
					button:SetHeight(math.max(textHeight + 2, type(iconHeight) == "number" and iconHeight or 0))
				end
			end
		end
	end
end

-- Short words for a title line that has no room (the tracker).
function M.DifficultyShort(difficulty)
	local enum = Enum and Enum.RelativeContentDifficulty
	if not enum or type(difficulty) ~= "number" then return nil end
	if difficulty == enum.Trivial then return L["triv."] end
	if difficulty == enum.Impossible then return L["v. hard"] end
	return M.DifficultyWord(difficulty)
end

-- Lines the string shows now; nil when the game keeps it secret.
local function Lines(fontString)
	if not fontString.GetNumLines then return nil end
	local ok, lines = pcall(fontString.GetNumLines, fontString)
	lines = ok and Clean(lines)
	return type(lines) == "number" and lines or nil
end

-- The quest log and tracker already start titles with "[24] " (or
-- "[24+] "); in color-blind mode the difficulty word goes inside. Returns
-- the new title and its parts (code, level, elite, word, title), or nil when
-- there is no level prefix or no word for the quest. short: the short word.
function M:DifficultyTitle(text, questID, short)
	if type(text) ~= "string" or not (self.db.levelWord and self:ColorBlind()) then return nil end
	local code, rest = text:match("^(|c%x%x%x%x%x%x%x%x)(.*)$")
	if not code then code, rest = "", text end
	local level, elite, after = rest:match("^%[(%d+)(%+?)%] (.*)$")
	if not level then return nil end
	local difficulty = self:Difficulty(questID)
	local word = short and M.DifficultyShort(difficulty) or M.DifficultyWord(difficulty)
	if not word then return nil end
	return code .. "[" .. level .. elite .. " " .. word .. "] " .. after, code, level, elite, word, after
end

-- The quest log's own title strings (not the tracker, see below).
function M:AddDifficultyWord(fontString, questID)
	if not (fontString and fontString.GetText) then return false end
	local text = self:DifficultyTitle(Clean(fontString:GetText()), questID)
	if not text then return false end
	fontString:SetText(text)
	return true
end

---------------------------------------------------------------------------
-- Quest menu entries: right-click on a quest in the log or tracker.
---------------------------------------------------------------------------
-- The quest the menu is for: the owner's questID, else the frame under
-- the mouse (a tracker block keeps its quest in id).
function M.QuestFromMenu(owner)
	local id = type(owner) == "table" and tonumber(Clean(owner.questID))
	if id then return id end
	local foci = Call(rawget(_G, "GetMouseFoci"))
	for _, region in ipairs(type(foci) == "table" and foci or {}) do
		local frame, depth = region, 0
		while type(frame) == "table" and depth < 5 do
			local questID = tonumber(Clean(frame.questID)) or tonumber(Clean(frame.poiQuestID))
			if questID then return questID end
			if frame.parentModule and tonumber(Clean(frame.id)) then return tonumber(frame.id) end
			frame = frame.GetParent and frame:GetParent() or nil
			depth = depth + 1
		end
	end
	return nil
end

-- Reminded quests, per character (E.global.QuestTint.reminders[charKey]).
E:RegisterCharacterKeyMove(function(db, oldKey, newKey)
	local all = type(db.global) == "table" and db.global.QuestTint
	E.MoveCharacterEntry(type(all) == "table" and all.reminders, oldKey, newKey)
end)

E:RegisterCharacterForget(function(db, key)
	local all = type(db.global) == "table" and db.global.QuestTint
	if type(all) == "table" and type(all.reminders) == "table" then all.reminders[key] = nil end
end)

local function Reminders()
	local global = E.global
	if type(global) ~= "table" or not E.charKey then return {} end
	local all = E:GetGlobal("QuestTint")
	if type(all) ~= "table" then return {} end
	all.reminders = all.reminders or {}
	all.reminders[E.charKey] = all.reminders[E.charKey] or {}
	return all.reminders[E.charKey]
end
M.Reminders = Reminders

local function InLog(questID)
	local index = C_QuestLog and Clean(Call(C_QuestLog.GetLogIndexForQuestID, questID))
	return type(index) == "number" and index > 0
end

local function IsComplete(questID)
	return C_QuestLog and Clean(Call(C_QuestLog.IsComplete, questID)) == true
end

local function QuestTitle(questID)
	local title = C_QuestLog and Clean(Call(C_QuestLog.GetTitleForQuestID, questID))
	return type(title) == "string" and title ~= "" and title or nil
end

function M:SetReminder(questID, on)
	questID = tonumber(questID)
	if not questID then return end
	Reminders()[questID] = on and true or nil
	if on then self:CheckReminders() end
end

function M:HasReminder(questID)
	return Reminders()[tonumber(questID) or 0] == true
end

-- One alert per reminded quest when its objectives are complete; a quest
-- that left the log (turned in, abandoned) drops its reminder.
function M:CheckReminders()
	if not self.active then return end
	local list = Reminders()
	for questID in pairs(list) do
		if IsComplete(questID) then
			list[questID] = nil
			M:PushAlert({
				key = "questdone:" .. questID, icon = "Interface\\Icons\\INV_Misc_Note_02",
				title = L["Quest ready to turn in"],
				text = QuestTitle(questID) or L["Quest %d"]:format(questID),
			})
		elseif not InLog(questID) then
			list[questID] = nil
		end
	end
end

function M:AddQuestMenu(root, questID)
	if not (self.active and self.db.questMenu and root and questID) then return end
	local qol = E:GetModule("QoL")
	local wowhead = qol and type(qol.ShowWowhead) == "function" and qol.ShowWowhead
	local reminded = self:HasReminder(questID)
	local remind = not reminded and InLog(questID) and not IsComplete(questID)
	if not (wowhead or remind or reminded) then return end
	root:CreateDivider()
	root:CreateTitle(L["EldoUI"])
	if wowhead then
		root:CreateButton(L["Wowhead link"], function() wowhead("quest", questID, QuestTitle(questID)) end)
	end
	if reminded then
		root:CreateButton(L["Don't remind me"], function() M:SetReminder(questID, false) end)
	elseif remind then
		root:CreateButton(L["Remind me when done"], function() M:SetReminder(questID, true) end)
	end
end

function M:HookQuestMenus()
	if self.menusHooked or not (Menu and Menu.ModifyMenu) then return end
	self.menusHooked = true
	for _, tag in ipairs({ "MENU_QUEST_MAP_LOG_TITLE", "MENU_QUEST_OBJECTIVE_TRACKER" }) do
		Menu.ModifyMenu(tag, function(owner, root)
			if M.active then M:AddQuestMenu(root, M.QuestFromMenu(owner)) end
		end)
	end
end

---------------------------------------------------------------------------
-- Quest tracker (Blizzard's objective tracker)
--
-- Blizzard writes a quest's title into block.HeaderText during
-- UpdateSingle and lays the tracker out from that string, so EldoUI never
-- writes into it. A new quest's tint and the difficulty word are drawn on
-- EldoUI's own string over the title, with the same font and width; the
-- game's string stays as it is and is only faded out while the overlay
-- shows. Hovering a title runs the block's UpdateHighlight, which recolors
-- it; a hook on it dresses the block again.
---------------------------------------------------------------------------
local overlays, faded, hookedBlocks, hookedModules = Weak(), Weak(), Weak(), Weak()
local fitCache, fitCount = {}, 0
local FIT_CACHE_MAX = 200
M.trackerMeasures = 0 -- text measures made for tracker titles so far

-- The overlay a tracker block shows, or nil.
function M.TrackerOverlay(block)
	local own = overlays[block]
	return own and own:IsShown() and own or nil
end

local function HideOverlay(block)
	local own = overlays[block]
	if own then own:Hide() end
	if faded[block] then
		faded[block] = nil
		if block.HeaderText and block.HeaderText.SetAlpha then block.HeaderText:SetAlpha(1) end
	end
end

local function Overlay(block, text)
	local own = overlays[block]
	if not own then
		own = block:CreateFontString(nil, "OVERLAY") -- EldoUI's own string
		overlays[block] = own
	end
	local font, size, flags = E.PlainCallAll(text.GetFont, text)
	if type(font) == "string" and type(size) == "number" then own:SetFont(font, size, flags) end
	local justify = E.PlainCall(text.GetJustifyH, text)
	if type(justify) == "string" then own:SetJustifyH(justify) end
	-- A string without a set width is as wide as its text and never wraps.
	local width = E.PlainCall(text.GetWidth, text)
	local natural = E.PlainCall(text.GetUnboundedStringWidth, text)
	if type(width) ~= "number" or width <= 0
		or (type(natural) == "number" and natural >= width - 0.5 and Lines(text) == 1) then
		width = nil
	end
	own:ClearAllPoints()
	own:SetPoint("TOPLEFT", text, "TOPLEFT", 0, 0)
	own:SetWidth(width or 0)
	return own, width
end

local function Measure(own, text)
	own:SetText(text)
	M.trackerMeasures = M.trackerMeasures + 1
	return Lines(own)
end

-- The title with the difficulty word, on no more lines than the game's own
-- title: the short word first, then the end of the title gives way to
-- "...". Reuse the fit only when the title, width and overlay font still
-- match, so a font change cannot reuse an old line measurement.
function M:FitTrackerTitle(own, title, questID, lines, width)
	local full, code, level, elite, _, after = self:DifficultyTitle(title, questID)
	if not full then return title end
	if not lines then return full end
	local font, size, flags = E.PlainCallAll(own.GetFont, own)
	local key
	if type(font) == "string" and type(size) == "number" and (flags == nil or type(flags) == "string") then
		key = table.concat({ font, tostring(size), flags or "", tostring(lines), tostring(width), full }, "\1")
		if fitCache[key] then return fitCache[key] end
	end
	local result = full
	local now = Measure(own, full)
	if now and now > lines then
		local shortTitle, _, _, _, short = self:DifficultyTitle(title, questID, true)
		result = shortTitle
		now = Measure(own, shortTitle)
		if now and now > lines then
			-- The title's color code ends with "|r": keep it at the end.
			local tail = after:match("|r$") and "|r" or ""
			local body = tail ~= "" and after:sub(1, -3) or after
			local chars = {}
			for char in body:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = char end
			local prefix = code .. "[" .. level .. elite .. " " .. short .. "] "
			local function Cut(n)
				return prefix .. (table.concat(chars, "", 1, n):gsub("%s+$", "")) .. "..." .. tail
			end
			-- The longest start of the title that still fits.
			local lo, hi = 0, #chars - 1
			while lo < hi do
				local mid = math.floor((lo + hi + 1) / 2)
				local got = Measure(own, Cut(mid))
				if got and got <= lines then lo = mid else hi = mid - 1 end
			end
			result = Cut(lo)
		end
	end
	if key then
		if fitCount >= FIT_CACHE_MAX then fitCache, fitCount = {}, 0 end
		fitCache[key], fitCount = result, fitCount + 1
	end
	return result
end

function M:DressTrackerBlock(block, questID)
	local text = type(block) == "table" and block.HeaderText
	if not (text and text.GetText) then return end
	if not hookedBlocks[block] and type(block.UpdateHighlight) == "function" then
		hookedBlocks[block] = true
		hooksecurefunc(block, "UpdateHighlight", function(b)
			if M.active then M:DressTrackerBlock(b, b.poiQuestID) end
		end)
	end
	local allowed = M.active and Allowed("objective-tracker")
	local tint = allowed and self.db.tracker and self:IsNew(questID)
	local word = allowed and self.db.levelWord and self:ColorBlind()
	local title = Clean(text:GetText())
	if type(title) ~= "string" or title == "" or not (tint or word) then return HideOverlay(block) end
	local shown = title
	if tint then shown = title:gsub("^|c%x%x%x%x%x%x%x%x", self:Hex()) end
	local own, width = Overlay(block, text)
	if word then
		-- Without a set width the string does not wrap: nothing to fit.
		local lines = width and Lines(text) or nil
		shown = self:FitTrackerTitle(own, shown, Clean(questID), lines, width)
	end
	if shown == title and not tint then return HideOverlay(block) end
	local r, g, b
	if tint then
		r, g, b = Color()
	else
		r, g, b = E.PlainCallAll(text.GetTextColor, text)
		if type(r) ~= "number" then r, g, b = 1, 0.82, 0 end
	end
	own:SetTextColor(r, g, b)
	own:SetText(shown)
	own:Show()
	if not faded[block] then
		faded[block] = true
		text:SetAlpha(0)
	end
end

-- Every block with an overlay goes back to the game's own title.
function M:UndressTracker()
	for block in pairs(overlays) do HideOverlay(block) end
end

local function TrackerQuestID(quest)
	if type(quest) ~= "table" then return nil end
	local id = Clean(quest.questID)
	if id == nil and type(quest.GetID) == "function" then id = Clean(quest:GetID()) end
	return id
end

function M:HookTrackerModule(module)
	if type(module) ~= "table" or hookedModules[module] or type(module.UpdateSingle) ~= "function" then return end
	hookedModules[module] = true
	hooksecurefunc(module, "UpdateSingle", function(mod, quest)
		if not M.active then return end
		local questID = TrackerQuestID(quest)
		local block = questID and type(mod.GetExistingBlock) == "function" and mod:GetExistingBlock(questID)
		if block then M:DressTrackerBlock(block, questID) end
	end)
end

-- Blocks already on screen: re-tint (or untint) after an option change.
function M:UpdateTracker()
	for _, name in ipairs({ "QuestObjectiveTracker", "CampaignQuestObjectiveTracker" }) do
		local module = _G[name]
		local used = type(module) == "table" and module.usedBlocks
		if type(used) == "table" then
			for _, blocks in pairs(used) do
				if type(blocks) == "table" then
					for id, block in pairs(blocks) do
						if type(block) == "table" then self:DressTrackerBlock(block, block.poiQuestID or id) end
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------
-- Quest titles in the quest log, for a tooltip line that has no quest ID.
local titleIDs

local function QuestIDForTitle(title)
	title = Clean(title)
	if type(title) ~= "string" or title == "" then return nil end
	if not titleIDs then
		titleIDs = {}
		local log = C_QuestLog
		local count = log and log.GetNumQuestLogEntries and log.GetNumQuestLogEntries() or 0
		for index = 1, tonumber(Clean(count)) or 0 do
			local info = log.GetInfo and log.GetInfo(index)
			if type(info) == "table" and not info.isHeader then
				local name, id = Clean(info.title), Clean(info.questID)
				if type(name) == "string" and id then titleIDs[name] = id end
			end
		end
	end
	return titleIDs[title]
end

local function LeftLine(tooltip, index)
	if not index then return nil end
	if type(tooltip.GetLeftLine) == "function" then return tooltip:GetLeftLine(index) end
	local name = tooltip.GetName and tooltip:GetName()
	return name and _G[name .. "TextLeft" .. index] or nil
end

-- A quest link's tooltip: the tag on a line of its own.
function M:OnQuestTooltip(tooltip, data)
	if not (Allowed("tooltips") and self.db.tooltip) then return end
	if type(data) ~= "table" or not self:IsNew(data.id) then return end
	local r, g, b = Color()
	tooltip:AddLine(TagText(), r, g, b)
end

-- A quest title line in a unit tooltip (a mob for an active quest).
function M:OnQuestTitleLine(tooltip, lineData)
	if not (Allowed("tooltips") and self.db.tooltip) then return end
	if type(lineData) ~= "table" then return end
	local questID = Clean(lineData.id) or Clean(lineData.questID) or QuestIDForTitle(lineData.leftText)
	if not self:IsNew(questID) then return end
	local line = LeftLine(tooltip, Clean(lineData.lineIndex))
	if line and line.SetTextColor then line:SetTextColor(Color()) end
end

function M:HookTooltips()
	if self.tooltipsHooked then return end
	local processor, enum = rawget(_G, "TooltipDataProcessor"), rawget(_G, "Enum")
	if not (processor and enum) then return end
	self.tooltipsHooked = true
	local types, lines = enum.TooltipDataType, enum.TooltipDataLineType
	if types and types.Quest and processor.AddTooltipPostCall then
		processor.AddTooltipPostCall(types.Quest, function(tooltip, data)
			if M.active then M:OnQuestTooltip(tooltip, data) end
		end)
	end
	if lines and lines.QuestTitle and processor.AddLinePostCall then
		processor.AddLinePostCall(lines.QuestTitle, function(tooltip, lineData)
			if M.active then M:OnQuestTitleLine(tooltip, lineData) end
		end)
	end
end

---------------------------------------------------------------------------
-- World map: quest offers (the "!" of quests a quest giver has for you)
---------------------------------------------------------------------------
local pinTinted, hookedPins = Weak(), Weak()
local OFFER_PIN = "QuestOfferPinTemplate" -- no-L: Blizzard template name

function M:TintMapPin(pin)
	local texture = type(pin) == "table" and pin.Texture
	if not (texture and texture.SetVertexColor) then return end
	if Allowed("world-map-quest-log") and self.db.mapPins and self:IsNew(pin.questID) then
		-- Desaturate first: the yellow "!" would otherwise mix with the tint.
		if texture.SetDesaturated then texture:SetDesaturated(true) end
		texture:SetVertexColor(Color())
		pinTinted[pin] = true
	elseif pinTinted[pin] then
		pinTinted[pin] = nil
		if texture.SetDesaturated then texture:SetDesaturated(false) end
		texture:SetVertexColor(1, 1, 1)
	end
end

local function HookPin(pin)
	if hookedPins[pin] or type(pin) ~= "table" or type(pin.OnAcquired) ~= "function" then return end
	hookedPins[pin] = true
	hooksecurefunc(pin, "OnAcquired", function(p) if M.active then M:TintMapPin(p) end end)
end

function M:HookMapPins()
	if self.mapPinsHooked then return end
	local mixin = rawget(_G, "QuestOfferPinMixin")
	if type(mixin) ~= "table" or type(mixin.OnAcquired) ~= "function" then return end
	self.mapPinsHooked = true
	-- Pins made from now on copy the hooked function from the mixin.
	hooksecurefunc(mixin, "OnAcquired", function(pin) if M.active then M:TintMapPin(pin) end end)
end

function M:UpdateMapPins()
	local map = _G.WorldMapFrame
	if not (map and type(map.EnumeratePinsByTemplate) == "function") then return end
	local mixin = rawget(_G, "QuestOfferPinMixin")
	for pin in map:EnumeratePinsByTemplate(OFFER_PIN) do
		-- A pin made before the mixin was hooked still has the old function.
		if not (self.mapPinsHooked and type(mixin) == "table" and pin.OnAcquired == mixin.OnAcquired) then HookPin(pin) end
		self:TintMapPin(pin)
	end
end

---------------------------------------------------------------------------
-- Hooks and events
---------------------------------------------------------------------------
function M:RefreshAll()
	if not self.active then return end
	self:UpdateQuestFrame()
	self:UpdateQuestLog()
	self:UpdateTracker()
	self:UpdateMapPins()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	if not M.active then return end
	if event == "GOSSIP_SHOW" then
		-- The list is filled in the same frame; color it right after.
		C_Timer.After(0, function()
			if not M.active then return end
			M:UpdateGossip()
			M:UpdateGossipLevels()
		end)
	elseif event == "QUEST_GREETING" then
		C_Timer.After(0, function() if M.active then M:UpdateGreetingLevels() end end)
	elseif event == "QUEST_LOG_UPDATE" then
		titleIDs = nil
		M:CheckReminders()
	else
		M:UpdateQuestFrame()
	end
end)

function M:Hook()
	if self.hooked then return end
	self.hooked = true
	for _, name in ipairs({ "QuestInfo_Display", "QuestFrameProgressItems_Update" }) do
		if type(_G[name]) == "function" then
			hooksecurefunc(name, function() if M.active then M:UpdateQuestFrame() end end)
		end
	end
	for _, name in ipairs({ "QuestLogQuests_Update" }) do
		if type(_G[name]) == "function" then
			hooksecurefunc(name, function() if M.active then M:UpdateQuestLog() end end)
		end
	end
	if type(_G.QuestFrameGreetingPanel_OnShow) == "function" then
		hooksecurefunc("QuestFrameGreetingPanel_OnShow", function() if M.active then M:UpdateGreetingLevels() end end)
	end
	self:HookTooltips()
	self:HookQuestMenus()
	if self.HookChainLines then self:HookChainLines() end
	E:OnBlizzardAddOn("Blizzard_ObjectiveTracker", function()
		for _, name in ipairs({ "QuestObjectiveTracker", "CampaignQuestObjectiveTracker" }) do
			M:HookTrackerModule(_G[name])
		end
	end)
	E:OnBlizzardAddOn("Blizzard_SharedMapDataProviders", function() M:HookMapPins() end)
end

function M:OnEnable()
	self:Hook()
	for _, event in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_LOG_UPDATE" }) do
		pcall(events.RegisterEvent, events, event)
	end
end

function M:OnDisable()
	events:UnregisterAllEvents()
	if self.questTag then self.questTag:Hide() end
	if self.HideChainLines then self:HideChainLines() end
	self:UndressTracker()
end

function M:OnProfileChanged()
	self:RefreshAll()
end

E:AddCommand("newquest", "[questID]  is a quest new in WoW: Forever? Without an ID: the quest window's quest", function(arg)
	local id = tonumber(arg) or CurrentQuestID()
	if not id then E:Print(L["Give a quest ID, or open a quest first."]) return end
	E:Print((L["Quest %d is %s."]):format(id, M:IsNew(id) and (M:Hex() .. L["new in WoW: Forever"] .. "|r") or L["from the original game"]))
end)

---------------------------------------------------------------------------
-- Options and styles
---------------------------------------------------------------------------
M.options = {
	{ type = "description", label = "Quests new in WoW: Forever get a tag in the quest window and a tint in the quest log, tracker, tooltips and world map. Also: /eui newquest." },
	{ type = "header", label = "Where" },
	{ type = "toggle", key = "questFrame", label = "Quest window", desc = "Mark new quests in the quest window, with the tag and the title tint below." },
	{ type = "toggle", key = "titleTint", label = "Tint the title", desc = "Show a new quest's title in the tint color in the quest window. Off: only the tag marks it.", dependsOn = "questFrame" },
	{ type = "toggle", key = "tag", label = "Tag in the quest window", desc = "Show a small tag in the corner of the quest window for new quests.", dependsOn = "questFrame" },
	{ type = "input", key = "tagText", label = "Tag text", desc = "The text of the tag in the quest window and in quest tooltips, e.g. New or New in Forever." },
	{ type = "toggle", key = "questLog", label = "Quest log", desc = "Tint new quests in the quest log beside the world map." },
	{ type = "toggle", key = "tracker", label = "Quest tracker", desc = "Tint new quests' titles in the quest tracker. Follows the Objective tracker Blizzard UI setting." },
	{ type = "toggle", key = "tooltip", label = "Tooltips", desc = "Add the tag under a new quest's link, and tint new quests' titles where a tooltip lists them (quest mobs). Follows the Tooltips Blizzard UI setting." },
	{ type = "toggle", key = "gossip", label = "Quest givers", desc = "Tint new quests in a quest giver's list." },
	{ type = "toggle", key = "mapPins", label = "World map", desc = "Tint the \"!\" of new quests a quest giver offers on the world map." },
	{ type = "header", label = "Look" },
	{ type = "color", key = "color", label = "Tint color", desc = "The color of new quests and the tag." },
	{ type = "header", label = "Quest levels" },
	{ type = "description", label = "WoW: Forever already shows quest levels in the quest log and quest tracker." },
	{ type = "toggle", key = "levelGossip", label = "Levels in quest giver lists", desc = "Show each quest's level in front of its title when a quest giver lists quests, like [24] The Defias Brotherhood, in the difficulty color. On by default." },
	{ type = "toggle", key = "levelWord", label = "Difficulty word in color-blind mode", desc = "While the game's color-blind mode is on, add a word after the level in the quest log, quest tracker and quest giver lists, like [24 hard]. On by default." },
	{ type = "header", label = "Quest chains" },
	{ type = "toggle", key = "chainLine", label = "Show quest chains", desc = "A line in the quest window, the quest log and the dialog view that says where a quest sits in its chain, like Part 2 of 5 and the next step. On by default." },
	{ type = "header", label = "Quest menu" },
	{ type = "toggle", key = "questMenu", label = "Quest menu entries", desc = "Right-click a quest in the quest log or tracker for \"Wowhead link\" (the address in a copy box) and \"Remind me when done\" (one alert when its objectives are complete). On by default." },
}

local ALL_ON = { questFrame = true, questLog = true, tracker = true, tooltip = true, gossip = true, mapPins = true }
local function With(base, extra)
	local out = {}
	for key, value in pairs(base) do out[key] = value end
	for key, value in pairs(extra) do out[key] = value end
	return out
end

E:RegisterStyles("QuestTint", {
	{ key = "Teal", title = "Teal tint", desc = "Teal titles and a \"New in Forever\" tag everywhere.",
		settings = With(ALL_ON, { titleTint = true, tag = true, tagText = "New in Forever", color = { 0.25, 0.85, 0.8 } }) },
	{ key = "Gold", title = "Gold \"New\"", desc = "Gold titles and a short \"New\" tag everywhere.",
		settings = With(ALL_ON, { titleTint = true, tag = true, tagText = "New", color = { 1, 0.75, 0.2 } }) },
	{ key = "TagOnly", title = "Tag only", desc = "Only the tag in the quest window; everything else keeps Blizzard's look.",
		settings = { questFrame = true, titleTint = false, tag = true, questLog = false, tracker = false, tooltip = false, gossip = false, mapPins = false } },
	{ key = "ListsOnly", title = "Lists only", desc = "Teal titles in the quest log, tracker, quest giver lists and on the map; the quest window and tooltips keep Blizzard's look.",
		settings = With(ALL_ON, { questFrame = false, tooltip = false, color = { 0.25, 0.85, 0.8 } }) },
	{ key = "Subtle", title = "Subtle", desc = "A soft blue tint everywhere and no tag in the quest window.",
		settings = With(ALL_ON, { titleTint = true, tag = false, color = { 0.55, 0.75, 1 } }) },
})

---------------------------------------------------------------------------
-- Tour help: the first quest tinted in the quest log, once the log has
-- stayed open a moment
---------------------------------------------------------------------------
local tintHelp = { button = nil, pending = false }

local function TintedQuest()
	local button = tintHelp.button
	if button and tinted[button] and button:IsVisible() and M:IsNew(button.questID) then return button end
end

E.Tour:Register("quests:tint", {
	form = "spot", word = "quests",
	offer = function(_, force)
		return E.Tour:Spot("quests:tint", {
			-- Offered again at the next redraw, so it never waits in the queue.
			force = force, now = true, target = TintedQuest,
			title = L["New in Forever"],
			text = L["Quests in this color are new in WoW: Forever; the original game did not have them. The Quest Marks page changes the color or turns the marks off."],
		})
	end,
	replay = function(def) def.offer(def, true) end,
})

function M:OfferTintHelp(button)
	if tintHelp.pending or E.Tour:Seen("quests:tint") then return end
	tintHelp.button, tintHelp.pending = button, true
	C_Timer.After(1, function()
		tintHelp.pending = false
		if TintedQuest() then E.Tour:Offer("quests:tint") end
	end)
end
