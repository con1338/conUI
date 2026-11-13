-- EldoUI Dialog: an optional dialog view for quest and gossip
-- NPCs. Big readable text, numbered choices, Space to go on, Esc to leave.
--
-- Pages, each built from the game's own quest and gossip APIs:
--   gossip    C_GossipInfo.GetText, GetAvailableQuests, GetActiveQuests,
--             GetOptions; a pick is C_GossipInfo.SelectAvailableQuest /
--             SelectActiveQuest / SelectOption
--   greeting  GetGreetingText and the NPC's quests (SelectAvailableQuest /
--             SelectActiveQuest)
--   detail    the quest offer; Accept is AcceptQuest, Decline DeclineQuest
--   progress  the turn-in check; Continue is CompleteQuest when the game
--             says the quest can be completed
--   complete  the rewards; Complete is GetQuestReward with the reward the
--             player picked (a click or a number key)
--
-- Every action is one key press or one click of the player. Nothing is
-- accepted, completed, picked or skipped by itself: Space first shows the
-- whole text, and a page with reward choices waits for a pick.
--
-- Blizzard's QuestFrame and GossipFrame stay where they are and keep
-- working: while the view shows they are see-through (alpha 0) and take no
-- clicks (mouse off on the frame and its parts, put back afterwards). They
-- are never hidden, so no protected path changes. Blizzard's window comes
-- back in combat, for a special themed gossip, for quests the game accepts
-- by itself, for PvP quests (they need Blizzard's confirm), and for every
-- frame this view does not draw (books, player choices, merchants).
--
-- The camera: the Camera module's "Talking to an NPC" distance (Camera
-- Situations) reacts to the same NPC events; this module never touches the
-- camera itself.
local _, E = ...
local L = E.L

local D = E:NewModule("Dialogue", {
	title = "NPC Dialog",
	desc = "A dialog view for quest and gossip NPCs: big readable text, numbered choices, Space to go on and Esc to leave.",
	category = "Quality of Life",
	conflicts = { "Immersion", "DialogueUI" },
	frames = { "EldoUI_Dialogue", "EldoUI_DialogueView" },
	movers = { "EldoUI_Dialogue" },
	blizzard = {},
	savedKeys = { "profile.modules.Dialogue" },
	optionsPage = "module:Dialogue",
	presets = { "Book", "Bronze", "Cinematic", "Compact", "Large", "Minimal" },
	reload = false,
	defaults = {
		enabled = false,
		style = "Cinematic",
		look = "cinematic",   -- cinematic, book, compact, large, bronze, minimal
		textSpeed = "fast",   -- instant, fast, slow
		fontSize = 15,
		model = true,         -- the NPC's model next to the text
		numberKeys = true,    -- 1-9 pick a choice
		spaceKey = true,      -- Space shows all, then goes on
		copyKey = true,       -- Ctrl+C: the text in a copy box
		rewardsKey = false,   -- R: rewards only (off: R stays on Reply)
		width = 600,
		dim = 0.35,           -- screen dim behind the view (0 = none)
	},
})
E.Dialogue = D
-- The built-in group list (Core/Config.lua) names this module too, so it
-- keeps its group after the module split.
if E.defaultModuleCategory then E.defaultModuleCategory.Dialogue = D.category end

local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local ACTIVE_ICON = "Interface\\GossipFrame\\ActiveQuestIcon"
local DAILY_ICON = "Interface\\GossipFrame\\DailyQuestIcon"
local GOSSIP_ICON = "Interface\\GossipFrame\\GossipGossipIcon"

local Secret = E.Secret

-- fn(...), or nothing when it fails or any answer is secret.
local Read = E.PlainCallAll
D.Read = Read

local function Text(fn, ...)
	local text = Read(fn, ...)
	if type(text) ~= "string" then return "" end
	return text
end

local function Call(fn, ...)
	if type(fn) ~= "function" then return false end
	local ok, err = pcall(fn, ...)
	if not ok then geterrorhandler()(err) end
	return ok
end

---------------------------------------------------------------------------
-- Blizzard's windows: see-through and click-through while the view shows
---------------------------------------------------------------------------
local BLIZZARD = { "QuestFrame", "GossipFrame" }
local veiled = {}        -- frame -> { alpha, mouse = { [region] = true } }
local hooked = {}

local function MouseOff(frame, record, depth)
	if depth > 12 then return end
	if E.FrameCheck(frame, "IsProtected") then return end
	if frame.IsMouseEnabled and frame:IsMouseEnabled() then
		record.mouse[frame] = true
		frame:EnableMouse(false)
	end
	if frame.IsMouseWheelEnabled and frame:IsMouseWheelEnabled() then
		record.wheel[frame] = true
		frame:EnableMouseWheel(false)
	end
	if frame.GetChildren then
		for _, child in ipairs({ frame:GetChildren() }) do MouseOff(child, record, depth + 1) end
	end
end

local function Veil(frame)
	if not frame or InCombatLockdown() or E.FrameCheck(frame, "IsProtected") then return false end
	local record = veiled[frame]
	if not record then
		record = { alpha = frame:GetAlpha(), mouse = {}, wheel = {} }
		if Secret(record.alpha) or type(record.alpha) ~= "number" then record.alpha = 1 end
		veiled[frame] = record
	end
	frame:SetAlpha(0)
	-- Parts made since the last pass (gossip rows) are caught on the next.
	MouseOff(frame, record, 0)
	return true
end

local function Unveil(frame)
	local record = veiled[frame]
	if not record then return end
	veiled[frame] = nil
	frame:SetAlpha(record.alpha or 1)
	for region in pairs(record.mouse) do
		if not (E.FrameCheck(region, "IsProtected") and InCombatLockdown()) then region:EnableMouse(true) end
	end
	for region in pairs(record.wheel) do
		if not (E.FrameCheck(region, "IsProtected") and InCombatLockdown()) then region:EnableMouseWheel(true) end
	end
end

function D:IsVeiled(frame)
	return veiled[frame] ~= nil
end

local function BlizzardFrame(kind)
	return rawget(_G, kind == "gossip" and "GossipFrame" or "QuestFrame")
end

function D:VeilBlizzard()
	if not self.page then return end
	local frame = BlizzardFrame(self.page.source)
	if frame then Veil(frame) end
	C_Timer.After(0, function()
		if D.page and frame and D.showing then Veil(frame) end
	end)
end

function D:UnveilAll()
	for _, name in ipairs(BLIZZARD) do
		local frame = rawget(_G, name)
		if frame then Unveil(frame) end
	end
end

local function HookBlizzard()
	for _, name in ipairs(BLIZZARD) do
		local frame = rawget(_G, name)
		if frame and not hooked[frame] then
			-- A window that shows again while the view is up is veiled again.
			local ok = pcall(frame.HookScript, frame, "OnShow", function(self)
				if D.showing and D.page and BlizzardFrame(D.page.source) == self then Veil(self) end
			end)
			hooked[frame] = ok
		end
	end
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
local function NpcName()
	local name = Read(UnitName, "npc")
	if type(name) ~= "string" then name = Read(UnitName, "questnpc") end
	return type(name) == "string" and name or ""
end

local function SortByOrder(a, b)
	return (a.orderIndex or 0) < (b.orderIndex or 0)
end

-- One quest row of a gossip or greeting page. The quest marks (when they
-- run) color the level by difficulty and tint a quest new in Forever.
local function QuestRow(title, level, active, complete, repeatable, action, questID)
	local icon = active and ACTIVE_ICON or (repeatable and DAILY_ICON or QUEST_ICON)
	local label = title or ""
	local tint = E.QuestTint
	if tint and tint.DialogueRow then
		label = tint:DialogueRow(label, level, questID)
	elseif type(level) == "number" and level > 0 then
		label = ("[%d] %s"):format(level, label)
	end
	return { label = label, icon = icon, kind = active and "active" or "available", dim = active and not complete, action = action }
end

function D:BuildGossip()
	local G = C_GossipInfo
	if not G then return nil end
	local page = { kind = "gossip", source = "gossip", name = NpcName(), text = Text(G.GetText), rows = {} }
	for _, quest in ipairs(Read(G.GetAvailableQuests) or {}) do
		local id = quest.questID
		page.rows[#page.rows + 1] = QuestRow(quest.title, quest.questLevel, false, false, quest.repeatable or (quest.frequency or 0) > 0,
			function() Call(G.SelectAvailableQuest, id) end, id)
	end
	for _, quest in ipairs(Read(G.GetActiveQuests) or {}) do
		local id = quest.questID
		page.rows[#page.rows + 1] = QuestRow(quest.title, quest.questLevel, true, quest.isComplete, false,
			function() Call(G.SelectActiveQuest, id) end, id)
	end
	local options = {}
	for _, option in ipairs(Read(G.GetOptions) or {}) do options[#options + 1] = option end
	table.sort(options, SortByOrder)
	for _, option in ipairs(options) do
		local id = option.gossipOptionID
		if id then
			page.rows[#page.rows + 1] = { label = option.name or "", icon = option.overrideIconID or option.icon or GOSSIP_ICON, kind = "option",
				action = function() Call(G.SelectOption, id) end }
		end
	end
	page.secondary = { label = L["Goodbye"], key = "Esc", action = function() Call(G.CloseGossip) end }
	return page
end

function D:BuildGreeting()
	local page = { kind = "greeting", source = "quest", name = NpcName(), text = Text(GetGreetingText), rows = {} }
	for index = 1, Read(GetNumAvailableQuests) or 0 do
		page.rows[#page.rows + 1] = QuestRow(Text(GetAvailableTitle, index), Read(GetAvailableLevel, index), false, false, false,
			function() Call(SelectAvailableQuest, index) end, select(5, Read(GetAvailableQuestInfo, index)))
	end
	for index = 1, Read(GetNumActiveQuests) or 0 do
		page.rows[#page.rows + 1] = QuestRow(Text(GetActiveTitle, index), Read(GetActiveLevel, index), true, true, false,
			function() Call(SelectActiveQuest, index) end, Read(GetActiveQuestID, index))
	end
	page.secondary = { label = L["Goodbye"], key = "Esc", action = function() Call(CloseQuest) end }
	return page
end

-- Items of a quest page: "choice", "reward" or "required".
local function Items(kind, count)
	local list = {}
	for index = 1, count or 0 do
		local name, texture, amount, quality, usable = Read(GetQuestItemInfo, kind, index)
		local link = Read(GetQuestItemLink, kind, index)
		list[#list + 1] = { kind = kind, index = index, name = name or "", icon = texture, count = amount, quality = quality,
			usable = usable ~= false, link = link }
	end
	return list
end

local function Money(amount)
	if type(amount) ~= "number" or amount <= 0 then return nil end
	return E:FormatMoney(amount)
end

local function RewardLine()
	local parts = {}
	local xp = Read(GetRewardXP)
	if type(xp) == "number" and xp > 0 then parts[#parts + 1] = L["%d experience"]:format(xp) end
	local money = Money(Read(GetRewardMoney))
	if money then parts[#parts + 1] = money end
	return #parts > 0 and table.concat(parts, "   ") or nil
end

-- Where the quest sits in its chain (Quest Marks), or nil.
function D.ChainInfo()
	local marks = E.QuestTint
	if not (marks and marks.ChainInfo and GetQuestID) then return nil end
	local ok, info = pcall(marks.ChainInfo, marks, GetQuestID())
	return ok and info or nil
end

function D:BuildDetail()
	local page = { kind = "detail", source = "quest", name = NpcName(), title = Text(GetTitleText), rows = {} }
	local objectives = Text(GetObjectiveText)
	page.text = Text(GetQuestText)
	if objectives ~= "" then page.extra = { heading = L["Objectives"], text = objectives } end
	page.choices = Items("choice", Read(GetNumQuestChoices))
	page.rewards = Items("reward", Read(GetNumQuestRewards))
	page.rewardLine = RewardLine()
	page.primary = { label = L["Accept"], key = "Space", action = function() Call(AcceptQuest) end, enabled = true }
	page.secondary = { label = L["Decline"], key = "Esc", action = function() Call(DeclineQuest) end }
	page.chain = D.ChainInfo()
	return page
end

function D:BuildProgress()
	local page = { kind = "progress", source = "quest", name = NpcName(), title = Text(GetTitleText), text = Text(GetProgressText), rows = {} }
	page.required = Items("required", Read(GetNumQuestItems))
	local money = Money(Read(GetQuestMoneyToGet))
	if money then page.rewardLine = L["Needs %s"]:format(money) end
	local completable = Read(IsQuestCompletable) and true or false
	page.primary = { label = L["Continue"], key = "Space", action = function() Call(CompleteQuest) end, enabled = completable,
		why = not completable and L["The quest is not done yet."] or nil }
	page.secondary = { label = L["Goodbye"], key = "Esc", action = function() Call(CloseQuest) end }
	page.chain = D.ChainInfo()
	return page
end

function D:BuildComplete()
	local page = { kind = "complete", source = "quest", name = NpcName(), title = Text(GetTitleText), text = Text(GetRewardText), rows = {} }
	page.choices = Items("choice", Read(GetNumQuestChoices))
	page.rewards = Items("reward", Read(GetNumQuestRewards))
	page.rewardLine = RewardLine()
	-- One choice is the only reward there is; more wait for the player's pick.
	page.choice = #page.choices == 1 and 1 or nil
	page.primary = { label = L["Complete quest"], key = "Space", enabled = true, action = function()
		local choice = D.page and D.page.choice
		if #page.choices > 1 and not choice then return end
		Call(GetQuestReward, choice or 0)
	end }
	page.secondary = { label = L["Goodbye"], key = "Esc", action = function() Call(CloseQuest) end }
	page.chain = D.ChainInfo()
	return page
end

-- Is the primary action ready (text shown, a reward picked)?
function D:PrimaryReady()
	local page = self.page
	local primary = page and page.primary
	if not (primary and primary.enabled) then return false end
	if page.kind == "complete" and #page.choices > 1 and not page.choice then return false end
	return true
end

function D:PickChoice(index)
	local page = self.page
	if not (page and page.kind == "complete" and page.choices[index]) then return false end
	page.choice = index
	if self.Render then self:Render(true) end
	return true
end

-- Number key or click on row `index` of a gossip or greeting page; on a
-- reward page it picks the reward.
function D:Pick(index)
	local page = self.page
	if not page then return false end
	if page.kind == "complete" then return self:PickChoice(index) end
	local row = page.rows[index]
	if not (row and row.action) then return false end
	row.action()
	return true
end

-- Space (or the primary button): first the whole text, then the action.
function D:Continue(fromButton)
	local page = self.page
	if not page then return false end
	if not fromButton and self.IsRevealing and self:IsRevealing() then
		self:RevealAll()
		return "reveal"
	end
	if not self:PrimaryReady() then return false end
	page.primary.action()
	return true
end

function D:Leave()
	local page = self.page
	if page and page.secondary then page.secondary.action() end
	return page ~= nil
end

-- All text of the page, for the copy box.
function D:PlainText()
	local page = self.page
	if not page then return "" end
	local parts = {}
	if page.title and page.title ~= "" then parts[#parts + 1] = page.title end
	if page.text and page.text ~= "" then parts[#parts + 1] = page.text end
	if page.extra then parts[#parts + 1] = page.extra.heading .. "\n" .. page.extra.text end
	for index, row in ipairs(page.rows) do parts[#parts + 1] = ("%d. %s"):format(index, row.label) end
	return table.concat(parts, "\n\n")
end

---------------------------------------------------------------------------
-- When the view takes over, and when Blizzard's window stays
---------------------------------------------------------------------------
-- nil when the view may show this page, else why not.
function D:FallbackReason(event, arg)
	if InCombatLockdown() then return "combat" end
	if event == "GOSSIP_SHOW" and arg ~= nil and arg ~= "" then return "themed" end
	if event == "QUEST_DETAIL" then
		if Read(QuestGetAutoAccept) then return "autoaccept" end
		if Read(QuestFlagsPVP) then return "pvp" end
	end
	return nil
end

local BUILD = {
	GOSSIP_SHOW = "BuildGossip",
	QUEST_GREETING = "BuildGreeting",
	QUEST_DETAIL = "BuildDetail",
	QUEST_PROGRESS = "BuildProgress",
	QUEST_COMPLETE = "BuildComplete",
}
D.BUILD = BUILD

function D:Fallback(reason)
	self.fallback = reason or "other"
	self.page = nil
	self:UnveilAll()
	if self.HideView then self:HideView() end
end

function D:OnShowEvent(event, arg)
	if not self.active then return end
	local reason = self:FallbackReason(event, arg)
	if reason then
		self:Fallback(reason)
		return
	end
	local build = self[BUILD[event]]
	local page = build and build(self)
	if not page then
		self:Fallback("other")
		return
	end
	-- Moving from gossip to a quest: the other window is not veiled any more.
	if self.page and self.page.source ~= page.source then self:UnveilAll() end
	self.fallback = nil
	self.page = page
	HookBlizzard()
	if self.ShowView then self:ShowView() end
	self:VeilBlizzard()
end

function D:OnCloseEvent(event, continuing)
	if not self.active then return end
	local page = self.page
	if event == "GOSSIP_CLOSED" and page and page.source ~= "gossip" then return end
	if event == "QUEST_FINISHED" and page and page.source ~= "quest" then return end
	self.page = nil
	self.fallback = nil
	self:UnveilAll()
	if self.HideView then self:HideView() end
	self.continuing = continuing and true or false
end

function D:OnCombat()
	if self.page then self:Fallback("combat") end
end

-- QUEST_ITEM_UPDATE: item names and icons came in. A page with several
-- new items gets one event per item; they are folded into one rebuild.
function D:OnItemUpdate()
	E:Debounce("Dialogue:items", 0.2, function() D:RefreshItems() end)
end

function D:RefreshItems()
	if not self.active then return end
	local page = self.page
	if not page or (page.kind ~= "detail" and page.kind ~= "progress" and page.kind ~= "complete") then return end
	local choice = page.choice
	local fresh = self[BUILD[page.kind == "detail" and "QUEST_DETAIL" or page.kind == "progress" and "QUEST_PROGRESS" or "QUEST_COMPLETE"]](self)
	fresh.choice = choice or fresh.choice
	self.page = fresh
	if self.Render then self:Render(true) end
end

local SHOW_EVENTS = { "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE" }
local CLOSE_EVENTS = { "GOSSIP_CLOSED", "QUEST_FINISHED" }

-- The module list sets `active` before OnEnable and clears it before
-- OnDisable; the module never writes it.
function D:OnEnable()
	for _, event in ipairs(SHOW_EVENTS) do
		self:RegisterEvent(event, function(_, name, arg) D:OnShowEvent(name, arg) end)
	end
	for _, event in ipairs(CLOSE_EVENTS) do
		self:RegisterEvent(event, function(_, name, arg) D:OnCloseEvent(name, arg) end)
	end
	self:RegisterEvent("QUEST_ITEM_UPDATE", function() D:OnItemUpdate() end)
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function() D:OnCombat() end)
	if self.CreateView then self:CreateView() end
end

function D:OnDisable()
	self.page = nil
	self:UnveilAll()
	if self.HideView then self:HideView() end
end

function D:OnProfileChanged()
	if self.ApplyLook then self:ApplyLook() end
	if self.page and self.Render then self:Render(true) end
end
