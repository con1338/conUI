-- EldoUI Quest Marks: where a quest sits in its chain, in one short line
-- where the player decides to take it.
--
--   * Quest window (detail, progress and reward pages): "Part 2 of 5,
--     next: The Defias Brotherhood (level 18)", "Last of 5 parts" on the
--     last step, "Leads to: <quest>" on a breadcrumb. It sits in the
--     window's top row, so it never moves the quest text or the rewards.
--   * The quest log's detail pane beside the world map: the same line in
--     its top bar.
--   * The dialog view (NPC Windows) shows it under the quest title.
--   * Hover: the whole chain, done steps grayed, the current one marked.
--     Click: the quest in your journal, or in the Journal's instance page.
--
-- The chain comes from the Loot Guide's quest data, or for a WoW: Forever
-- chain the data does not know, from the quest line the game lists. A quest
-- in neither shows no line: nothing is guessed. Only text EldoUI draws on
-- its own frames; nothing is clicked or accepted for the player.
local _, E = ...
local L = E.L
local M = E.QuestTint

local Clean = E.Plain
local Kit = E.UIKit

local function LG()
	local guide = E.LootGuide
	if guide and type(guide.QuestChain) == "function" then return guide end
end

local function DataLoaded(guide)
	return select(3, guide:DataStatus()) ~= nil
end

local function Title(guide, questID)
	local title = guide:QuestTitle(questID)
	if type(title) == "string" and title ~= "" then return title end
end

-- The chain line for a quest: { text, questID, chain, breadcrumb } or nil.
function M:ChainInfo(questID)
	questID = tonumber(Clean(questID))
	local guide = LG()
	if not (questID and guide and self.active and self.db.chainLine ~= false) then return nil end
	if not DataLoaded(guide) then self:LoadOriginalList() end
	local chain = guide:QuestChain(questID)
	if type(chain) == "table" and #chain > 1 then
		local part
		for index, step in ipairs(chain) do
			if step.step == "current" then part = index break end
		end
		if not part then return nil end
		local text
		if part == #chain then
			text = E:Plural(#chain, "Last of %d part", "Last of %d parts"):format(#chain)
		else
			local nextID = chain[part + 1].id
			local nextTitle = Title(guide, nextID)
			local level = guide:QuestLevel(nextID)
			if nextTitle and level then
				text = L["Part %d of %d, next: %s (level %d)"]:format(part, #chain, nextTitle, level)
			elseif nextTitle then
				text = L["Part %d of %d, next: %s"]:format(part, #chain, nextTitle)
			else
				text = L["Part %d of %d"]:format(part, #chain)
			end
		end
		return { text = text, questID = questID, chain = chain }
	end
	local quest = guide:Quest(questID)
	local target = quest and quest.breadcrumbFor
	local targetTitle = target and Title(guide, target)
	if targetTitle then
		return { text = L["Leads to: %s"]:format(targetTitle), questID = questID, breadcrumb = target }
	end
	return nil
end

-- The whole chain in a tooltip, done steps grayed and the current one
-- marked, then what a click does.
function M:ChainTooltip(tooltip, info)
	if not (tooltip and info) then return end
	local guide = LG()
	if not guide then return end
	Kit.TipTitle(tooltip, L["Quest chain"])
	local steps = info.chain or { { id = info.questID, step = "current" }, { id = info.breadcrumb, step = "after" } }
	for index, step in ipairs(steps) do
		local title = Title(guide, step.id) or ("#" .. tostring(step.id))
		local level = guide:QuestLevel(step.id)
		local label = level and ("%d. [%d] %s"):format(index, level, title) or ("%d. %s"):format(index, title)
		if step.step == "current" then
			tooltip:AddLine(E:TextHex("accent") .. "> " .. label .. "|r")
		elseif guide:QuestStatus(step.id) == "done" then
			tooltip:AddLine(E:TextHex("secondary") .. label .. "  " .. L["(done)"] .. "|r")
		else
			Kit.TipText(tooltip, label)
		end
	end
	E:TooltipHint(tooltip, { L["Click"], L["open in your journal"] })
end

-- Opens the quest: in your journal when My Adventure runs, else on its
-- instance's Journal page when it has one.
function M:OpenChainQuest(questID)
	local journal = E.Journal
	if journal and type(journal.Open) == "function" and type(journal.Address) == "function" then
		local ok, opened = pcall(journal.Open, journal, journal:Address("quest", questID))
		if ok and opened then return true end
	end
	local guide = LG()
	local quest = guide and guide:Quest(questID)
	if quest and quest.instance and type(guide.Open) == "function" then
		guide:Open("journal", { key = quest.instance, quest = questID })
		return true
	end
	return false
end

-- A one-line button with the chain text, its tooltip and its click.
function M:ChainButton(parent)
	local button = CreateFrame("Button", nil, parent)
	button:SetHeight(16)
	button.text = E:CreateText(button, E.tokens.size.small, "LEFT")
	button.text:SetPoint("LEFT")
	button.text:SetPoint("RIGHT")
	button.text:SetWordWrap(false)
	button:SetScript("OnEnter", function(hovered)
		if not hovered.info then return end
		GameTooltip:SetOwner(hovered, "ANCHOR_BOTTOMLEFT")
		M:ChainTooltip(GameTooltip, hovered.info)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnClick", function(clicked)
		if clicked.info then M:OpenChainQuest(clicked.info.questID) end
	end)
	E:BindOptionsLink(button, { page = "module:QuestTint", key = "chainLine" })
	return button
end

function M:ShowChain(button, info)
	button.info = info
	if info then
		button.text:SetText(E:TextHex("secondary") .. info.text .. "|r")
		button:Show()
	else
		button:Hide()
	end
end

---------------------------------------------------------------------------
-- Quest window and the quest log's detail pane
---------------------------------------------------------------------------
function M:UpdateChainLine()
	local frame = _G.QuestFrame
	if frame then
		local info = frame:IsShown() and E:BlizzardAllowed("quest-gossip-npc", "improve") and self:ChainInfo(GetQuestID and GetQuestID())
		if info and not self.chainLine then
			local line = self:ChainButton(frame)
			line:SetPoint("TOPLEFT", frame, "TOPLEFT", 64, -30)
			self.chainLine = line
		end
		if self.chainLine then
			-- Beside the "New in Forever" tag when it shows.
			self.chainLine:SetPoint("RIGHT", frame, "TOPRIGHT", (self.questTag and self.questTag:IsShown()) and -110 or -12, -38)
			self:ShowChain(self.chainLine, info or nil)
		end
	end
	local details = _G.QuestMapFrame and _G.QuestMapFrame.DetailsFrame
	if details then
		local questID = C_QuestLog and C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
		local info = details:IsShown() and E:BlizzardAllowed("world-map-quest-log", "improve") and self:ChainInfo(questID)
		if info and not self.logChainLine then
			local line = self:ChainButton(details)
			line:SetPoint("TOPLEFT", details, "TOPLEFT", 90, -6)
			line:SetPoint("TOPRIGHT", details, "TOPRIGHT", -24, -6)
			self.logChainLine = line
		end
		if self.logChainLine then self:ShowChain(self.logChainLine, info or nil) end
	end
end

function M:HideChainLines()
	if self.chainLine then self.chainLine:Hide() end
	if self.logChainLine then self.logChainLine:Hide() end
end

function M:HookChainLines()
	if self.chainHooked then return end
	self.chainHooked = true
	for _, name in ipairs({ "QuestInfo_Display", "QuestFrameProgressItems_Update", "QuestMapFrame_ShowQuestDetails" }) do
		if type(_G[name]) == "function" then
			hooksecurefunc(name, function() if M.active then M:UpdateChainLine() end end)
		end
	end
end
