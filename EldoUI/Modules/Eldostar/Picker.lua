-- EldoUI Eldostar: the guide list, a section of the Journal's My Adventure
-- tab (Today: Guides). It is there only while Eldostar is the guide
-- provider; the guide window's title and /eui eldostar guides open it.
--
--   Guides                                                [Open the window]
--   Elwynn Forest 1-10, step 12 of 80.
--   ---------------------------------------------------------------------
--   [For this character][All guides]                  [ Search guides   ]
--   IN USE ------------------------------------------------------------ v
--   [ic] Elwynn Forest 1-10        Step 12 of 80                    1-10
--   UP NEXT ----------------------------------------------------------- v
--   [ic] Westfall 10-20            Levels 10-20                    10-20
--   LEVELING  14 ------------------------------------------------------ v
--   ...
--
-- "For this character" lists the guides for the character's faction, race
-- and class that are not below its level; "All guides" lists every guide.
-- A click starts a guide (its saved place is kept); a right-click on a
-- guide with progress offers to start it over.
local _, E = ...
local L = E.L
local M = E.Eldostar

local HUB = "adventure"
local KEY = "guides"
local ICON = "Interface\\Icons\\INV_Scroll_03"
local DONE_ICON = "Interface\\Icons\\Achievement_Level_10"

local FILTERS = {
	{ "mine", E.Key("For this character"), E.Key("Guides for your faction, race and class that are not below your level.") },
	{ "all", E.Key("All guides"), E.Key("Every guide in the guide data.") },
}

local filter = "mine"

local function Levels(guide)
	local range = guide.levels
	if not range then return nil end
	return range[1] == range[2] and tostring(range[1]) or ("%d-%d"):format(range[1], range[2])
end

-- "Step 12 of 80", "Finished" or the level range.
local function GuideSub(guide)
	local record = M.Store().progress[guide.id]
	if type(record) == "table" and record.done then return L["Finished"] end
	if type(record) == "table" and type(record.s) == "number" and (record.s > 1 or M.Store().guide == guide.id) then
		return L["Step %d of %d"]:format(record.s, guide.count)
	end
	local levels = Levels(guide)
	return levels and L["Levels %s"]:format(levels) or ""
end

local function Started(guide)
	local record = M.Store().progress[guide.id]
	return type(record) == "table" and ((type(record.s) == "number" and record.s > 1) or record.done
		or (type(record.hist) == "table" and #record.hist > 0)) and true or false
end

local function ConfirmReset(guide)
	E:ShowConfirm({
		title = L["Start over?"],
		text = L["Start %s over from its first step? Your place in it is cleared."]:format(guide.title),
		accept = L["Start over"],
		danger = true,
		onAccept = function()
			M:ResetGuide(guide.id)
			M:StartGuide(guide.id)
		end,
	})
end

local function GuideRow(guide, current)
	local tip = current and L["The guide in use. Right-click to start it over."]
		or (Started(guide) and L["Click to go on with this guide where you left it. Right-click to start it over."]
		or L["Click to start this guide."])
	local lines = {}
	if guide.pitch or guide.why then lines[#lines + 1] = guide.pitch or guide.why end
	if guide.author then lines[#lines + 1] = L["By %s."]:format(guide.author) end
	local rewards = M.RewardNames(guide.rewards)
	if rewards then lines[#lines + 1] = L["Rewards: %s"]:format(rewards) end
	lines[#lines + 1] = tip
	local record = M.Store().progress[guide.id]
	return {
		icon = (type(record) == "table" and record.done) and DONE_ICON or ICON,
		title = guide.title,
		sub = GuideSub(guide),
		time = Levels(guide),
		tipTitle = guide.title,
		tip = table.concat(lines, "\n"),
		guide = guide.id,
		onClick = function(_, button)
			if button == "RightButton" then
				if Started(guide) then ConfirmReset(guide) end
				return
			end
			M:StartGuide(guide.id)
		end,
	}
end

local function Shown(guide, facts, words, mode)
	if mode == "mine" then
		if not M:GuideFits(guide, facts) or M.LevelFit(guide, facts.level) == "past" then return false end
	end
	if #words == 0 then return true end
	local LP = E.Adventure.LogPages
	return LP.Hits(E:FoldText(guide.search), words)
end

-- Categories in a steady order: Leveling first, then by name.
local function CategoryOrder(a, b)
	if a == "Leveling" then return b ~= "Leveling" end
	if b == "Leveling" then return false end
	return a < b
end

local function GuideOrder(a, b)
	local la, lb = a.levels and a.levels[1] or 100, b.levels and b.levels[1] or 100
	if la ~= lb then return la < lb end
	return a.title < b.title
end

local function Draw(frame)
	local A = E.Adventure
	local LP, K = A.LogPages, E.AdventureKit
	local items = {}
	frame.header:SetTitle(L["Guides"])
	frame.filter:SetActive(filter)
	if not M.data then
		frame.header:SetSentence(M:DataStateText())
		frame.header:SetActions(nil)
		frame.list:SetEmpty(L["No guides yet"], M:DataStateText(), ICON)
		return items
	end
	local guide, record, steps = M:Current()
	if guide then
		frame.header:SetSentence(record.done and L["You finished %s."]:format(guide.title)
			or L["%s, step %d of %d."]:format(guide.title, record.s, #steps))
	else
		frame.header:SetSentence(L["Community leveling guides, step by step in the Eldostar window."])
	end
	frame.header:SetActions({ { L["Open the window"], function() M:ShowNow() end, L["Shows the Eldostar guide window."] } })

	local facts = M.PlayerFacts()
	local words = LP.Words(K.Query("eldostar"))
	if #words == 0 then
		if guide then
			LP.AddFold(items, "eldostar:current", L["In use"], nil, LP.Ledger({ GuideRow(guide, true) }),
				true, function() frame:Draw(true) end)
		end
		local suggest = M:Suggest()
		if suggest and suggest ~= guide then
			LP.AddFold(items, "eldostar:next", L["Up next"], nil, LP.Ledger({ GuideRow(suggest) }),
				true, function() frame:Draw(true) end)
		end
	end
	local byCategory, categories = {}, {}
	for _, entry in ipairs(M:Guides()) do
		if Shown(entry, facts, words, filter) then
			local list = byCategory[entry.category]
			if not list then
				list = {}
				byCategory[entry.category] = list
				categories[#categories + 1] = entry.category
			end
			list[#list + 1] = entry
		end
	end
	table.sort(categories, CategoryOrder)
	for _, category in ipairs(categories) do
		local list = byCategory[category]
		table.sort(list, GuideOrder)
		local rows = {}
		for _, entry in ipairs(list) do rows[#rows + 1] = GuideRow(entry, entry == guide) end
		LP.AddFold(items, "eldostar:" .. category, category, tostring(#list), LP.Ledger(rows),
			#words > 0 or #categories <= 3, function() frame:Draw(true) end, #words > 0)
	end
	local count = 0
	for _, category in ipairs(categories) do count = count + #byCategory[category] end
	frame.shownCategories, frame.shownCount = categories, count
	if #categories == 0 then
		items = {}
		frame.list:SetEmpty(L["Nothing matches"], filter == "mine"
			and L["No guide for this character matches. All guides lists every guide."]
			or L["No guide matches that search."], ICON)
	end
	return items
end

local function Build(parent)
	local A = E.Adventure
	local LP, K = A.LogPages, E.AdventureKit
	local frame
	frame = LP.Page(parent, {
		empty = { L["No guides yet"], "", ICON },
		controls = function(page, bar)
			page.filter = K.Switch(bar, FILTERS, filter, function(key)
				filter = key
				page:Draw()
			end)
			page.filter:SetPoint("LEFT", 0, 0)
			page.search = K.Search(bar, "eldostar", L["Search guides"], function() page:Draw() end)
			page.search:SetPoint("LEFT", page.filter, "RIGHT", 12, 0)
			page.search:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
		end,
	})
	function frame:Draw(keepScroll)
		if not self:IsShown() then
			self.dirty = true
			return
		end
		self.dirty = false
		self.items = Draw(self)
		self.list:SetData(self.items, keepScroll)
	end
	function frame:SetSearch(text)
		self.search:SetText(text or "")
		self.search:GetScript("OnTextChanged")(self.search, true)
	end
	frame:SetScript("OnShow", function(self) if self.dirty then self:Draw(true) end end)
	M.pickerFrame = frame
	return frame
end

local SECTION = {
	title = "Guides",
	icon = ICON,
	desc = "Community leveling guides for Eldostar: the one in use, the next one and every guide for your character.",
	group = "today",
	order = 45,
	words = { "guides", "guide", "eldostar", "leveling" },
	build = Build,
	show = function(frame, arg)
		-- At the level cap the data waits for this page.
		if not M.data then M:LoadData() end
		if type(arg) == "table" and arg.search then frame:SetSearch(arg.search) end
		frame:Draw(type(arg) ~= "table")
	end,
	refresh = function(frame, changed)
		if changed.settings or changed.data then frame:Draw(true) end
	end,
	hidden = function() return not M:IsLive() end,
	search = function(text)
		local A = E.Adventure
		local words = A and A.LogPages and A.LogPages.Words(text) or {}
		if #words == 0 or not M.data then return {} end
		local out = {}
		for _, guide in ipairs(M:Guides()) do
			if A.LogPages.Hits(E:FoldText(guide.search), words) then
				out[#out + 1] = { title = guide.title, sub = L["Eldostar guide"], icon = ICON, arg = { search = guide.title } }
				if #out >= 20 then break end
			end
		end
		return out
	end,
}
M.PICKER = SECTION

local function Hub()
	local LG = E.LootGuide
	if LG and type(LG.RegisterHubSection) == "function" then return LG end
end

function M:RegisterPicker()
	local LG = Hub()
	if not LG or self.pickerRegistered then return end
	self.pickerRegistered = true
	LG:RegisterHubSection(HUB, KEY, SECTION)
end

function M:UnregisterPicker()
	if not self.pickerRegistered then return end
	self.pickerRegistered = nil
	local LG = Hub()
	if LG and LG.UnregisterHubSection then LG:UnregisterHubSection(HUB, KEY) end
end

-- Opens the list in the Journal; false when My Adventure is not running.
function M:OpenPicker(search)
	local A = E.Adventure
	if not (self.pickerRegistered and A and A.Running and A:Running() and A.OpenSection) then return false end
	return A:OpenSection(KEY, search and { search = search } or nil) and true or false
end

function M:RefreshPicker()
	local frame = self.pickerFrame
	if frame and self.pickerRegistered then frame:Draw(true) end
end
