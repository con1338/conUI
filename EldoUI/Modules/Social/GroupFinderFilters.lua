-- EldoUI Social: filters and Player Notes marks on the group
-- finder's browse page. Part of the "Improve" action of the
-- group-finder element (Modules/Social/GroupFinder.lua).
--
--   Filters  Role needed (tank, healer, damage), Level fits me, Not full,
--            Friends or guild, a text filter on the leader and activity
--            names, and listings you dismissed (until /reload or for 30
--            minutes). Listings that don't match are dimmed.
--   Marks    your Player Notes mark (Good / Avoid) on the leader and the
--            members of a listing.
--
-- Everything reads the search result info Blizzard's page already has
-- (C_LFGList.GetSearchResultInfo and friends). Nothing is searched,
-- requested, applied for or invited for the player; a refresh is always
-- Blizzard's own button. The listing comment is a protected string the game
-- does not let addons read, so the text filter matches the leader and the
-- activity names only.
--
-- Hooks are post-hooks only: LFGBrowseSearchEntry_Update (a row was drawn)
-- and LFGBrowseUtil_SortSearchResults (the list was sorted, only counted).
-- Listings that don't match are dimmed, never taken out: the group finder
-- is a secure Blizzard addon, and writing into its result list would taint it.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local M = E:GetModule("Social")
local K = M.kit
local Usable, Try, Secret = K.Usable, K.Try, K.Secret
local Kit = E.UIKit

local ID = "group-finder"
local DISMISS_SECONDS = 30 * 60
local SOLO_LEVEL_RANGE = 5

-- Defaults (merged into the Social module's lfg table before it loads).
local DEFAULTS = {
	filters = true,        -- the filter bar on the browse page
	filterMode = "dim",    -- only "dim": hiding would write into Blizzard's list
	notes = true,          -- Player Notes marks on listings
	remember = true,       -- keep the filter state across sessions
	dismissFor = "30",     -- "30" minutes | "reload"
	filter = { tank = false, healer = false, dps = false, level = false, notFull = false, friends = false, text = "" },
}
M.defaults.lfg = M.defaults.lfg or {}
for key, value in pairs(DEFAULTS) do
	if M.defaults.lfg[key] == nil then M.defaults.lfg[key] = type(value) == "table" and CopyTable(value) or value end
end

local GF = {}
M.groupFinderFilters = GF

local session = CopyTable(DEFAULTS.filter) -- the filter state when "remember" is off
local dismissed = {}                       -- leader name -> expiry time (math.huge until /reload)
local rowParts = setmetatable({}, { __mode = "k" }) -- row -> { tag, dismiss, anchors }
local last = { total = 0, matched = 0, hidden = 0 } -- the last sorted list

local function DB() return M.db.lfg end

local function On()
	return M.active and E:BlizzardAllowed(ID, "improve") and DB().filters and true or false
end

local function NotesOn()
	local notes = E.PlayerNotes
	return M.active and E:BlizzardAllowed(ID, "improve") and DB().notes and notes and notes.active and true or false
end

function GF:State()
	if DB().remember then
		local saved = DB().filter
		if type(saved) ~= "table" then
			saved = CopyTable(DEFAULTS.filter)
			DB().filter = saved
		end
		return saved
	end
	return session
end

function GF:Active()
	local state = self:State()
	return state.tank or state.healer or state.dps or state.level or state.notFull or state.friends
		or (type(state.text) == "string" and strtrim(state.text) ~= "")
end

---------------------------------------------------------------------------
-- Reading a listing (all from what the page shows; secret values count as
-- "can't tell", which never hides a listing)
---------------------------------------------------------------------------
local Clean = E.Plain

local function Info(resultID)
	if not (resultID and C_LFGList and C_LFGList.GetSearchResultInfo) then return nil end
	local ok, info = pcall(C_LFGList.GetSearchResultInfo, resultID)
	if ok and type(info) == "table" then return info end
end

local function Activities(info)
	local list = {}
	local ids = Clean(info.activityIDs)
	if type(ids) ~= "table" or not (C_LFGList and C_LFGList.GetActivityInfoTable) then return list end
	for _, id in ipairs(ids) do
		local ok, activity = pcall(C_LFGList.GetActivityInfoTable, id)
		if ok and type(activity) == "table" then list[#list + 1] = activity end
	end
	return list
end

local function Member(resultID, index)
	if not (C_LFGList and C_LFGList.GetSearchResultPlayerInfo) then return nil end
	local ok, member = pcall(C_LFGList.GetSearchResultPlayerInfo, resultID, index)
	if ok and type(member) == "table" then return member end
end

local function Number(value)
	value = Clean(value)
	return type(value) == "number" and value or nil
end

local function Counts(resultID)
	if not (C_LFGList and C_LFGList.GetSearchResultMemberCounts) then return nil end
	local ok, counts = pcall(C_LFGList.GetSearchResultMemberCounts, resultID)
	if ok and type(counts) == "table" then return counts end
end

local function LeaderKey(info)
	local name = Clean(info.leaderName)
	if type(name) == "string" and name ~= "" then return name end
end

-- Does a listing pass a filter? true / false, or nil when it can't tell.
local CHECKS = {}

CHECKS.roles = function(resultID, info, state)
	if not (state.tank or state.healer or state.dps) then return true end
	local members = Number(info.numMembers) or 0
	if members <= 1 then
		-- A player on their own: the roles they offer.
		local member = Member(resultID, 1)
		local roles = member and Clean(member.lfgRoles)
		if type(roles) ~= "table" then return nil end
		return (state.tank and roles.tank) or (state.healer and roles.healer) or (state.dps and roles.dps) or false
	end
	-- A group: the roles it still needs.
	local counts = Counts(resultID)
	if not counts then return nil end
	local tank, healer, dps = Number(counts.TANK_REMAINING), Number(counts.HEALER_REMAINING), Number(counts.DAMAGER_REMAINING)
	if not (tank or healer or dps) then return nil end
	return (state.tank and (tank or 0) > 0) or (state.healer and (healer or 0) > 0) or (state.dps and (dps or 0) > 0) or false
end

CHECKS.level = function(resultID, info, state)
	if not state.level then return true end
	local mine = UnitLevel and Number(UnitLevel("player"))
	if not mine then return nil end
	local members = Number(info.numMembers) or 0
	if members <= 1 then
		local member = Member(resultID, 1)
		local level = member and Number(member.level)
		if not level then return nil end
		return math.abs(level - mine) <= SOLO_LEVEL_RANGE
	end
	local activities = Activities(info)
	if #activities == 0 then return nil end
	for _, activity in ipairs(activities) do
		local low = Number(activity.minLevelSuggestion) or Number(activity.minLevel) or 0
		local high = Number(activity.maxLevelSuggestion) or 0
		if mine >= low and (high <= 0 or mine <= high) then return true end
	end
	return false
end

CHECKS.notFull = function(resultID, info, state)
	if not state.notFull then return true end
	local members = Number(info.numMembers)
	if not members then return nil end
	if members <= 1 then return true end
	local most = 0
	for _, activity in ipairs(Activities(info)) do most = math.max(most, Number(activity.maxNumPlayers) or 0) end
	if most > 0 then return members < most end
	local counts = Counts(resultID)
	if not counts then return nil end
	local open = (Number(counts.TANK_REMAINING) or 0) + (Number(counts.HEALER_REMAINING) or 0) + (Number(counts.DAMAGER_REMAINING) or 0)
	return open > 0
end

CHECKS.friends = function(_, info, state)
	if not state.friends then return true end
	local bnet, char, guild = Number(info.numBNetFriends), Number(info.numCharFriends), Number(info.numGuildMates)
	if not (bnet or char or guild) then return nil end
	return (bnet or 0) + (char or 0) + (guild or 0) > 0
end

CHECKS.text = function(_, info, state)
	local query = E:FoldText(type(state.text) == "string" and state.text or "")
	if query == "" then return true end
	local leader = LeaderKey(info)
	if leader and E:FoldText(leader):find(query, 1, true) then return true end
	for _, activity in ipairs(Activities(info)) do
		for _, key in ipairs({ "fullName", "shortName" }) do
			local name = Clean(activity[key])
			if type(name) == "string" and E:FoldText(name):find(query, 1, true) then return true end
		end
	end
	return false
end

local CHECK_ORDER = { "roles", "level", "notFull", "friends", "text" }

function GF:IsDismissed(info)
	local key = info and LeaderKey(info)
	local expiry = key and dismissed[key]
	if not expiry then return false end
	if expiry ~= math.huge and GetTime() >= expiry then
		dismissed[key] = nil
		return false
	end
	return true
end

-- Does a listing pass every filter? Your own listing always does.
function GF:Matches(resultID, info)
	info = info or Info(resultID)
	if not info then return true end
	if Clean(info.hasSelf) then return true end
	if self:IsDismissed(info) then return false end
	local state = self:State()
	for _, key in ipairs(CHECK_ORDER) do
		local ok, pass = pcall(CHECKS[key], resultID, info, state)
		if ok and pass == false then return false end
	end
	return true
end

function GF:Dismiss(resultID)
	local key = LeaderKey(Info(resultID) or {})
	if not key then return false end
	dismissed[key] = DB().dismissFor == "reload" and math.huge or (GetTime() + DISMISS_SECONDS)
	self:Refresh(true)
	return true
end

function GF:DismissedCount()
	local count, now = 0, GetTime()
	for key, expiry in pairs(dismissed) do
		if expiry ~= math.huge and now >= expiry then dismissed[key] = nil else count = count + 1 end
	end
	return count
end

function GF:BringBack()
	wipe(dismissed)
	self:Refresh(true)
end

---------------------------------------------------------------------------
-- Player Notes marks: the leader's and any marked member's
---------------------------------------------------------------------------
function GF:Marks(resultID, info)
	local notes = E.PlayerNotes
	if not (notes and notes.Get and notes.CharacterKey) then return {} end
	info = info or Info(resultID)
	if not info then return {} end
	local out, seen = {}, {}
	local function Add(name, isLeader)
		if type(name) ~= "string" or Secret(name) or name == "" then return end
		local key = notes.CharacterKey(name)
		if not key or seen[key] then return end
		seen[key] = true
		local record = notes:Get(key)
		local mark = record and record.mark
		if mark == "good" or mark == "avoid" then
			out[#out + 1] = { name = name:match("^[^%-]+") or name, mark = mark, leader = isLeader }
		end
	end
	Add(LeaderKey(info), true)
	local members = Number(info.numMembers) or 0
	for index = 1, math.min(members, 40) do
		local member = Member(resultID, index)
		if member then Add(Clean(member.name), Clean(member.isLeader)) end
	end
	return out
end

local function MarkText(marks)
	if #marks == 0 then return "" end
	local parts = {}
	for index, mark in ipairs(marks) do
		if index > 2 then
			parts[#parts + 1] = L["+%d"]:format(#marks - 2)
			break
		end
		local color = E:TokenHex(mark.mark == "good" and E.tokens.text.good or E.tokens.text.bad)
		parts[#parts + 1] = color .. (mark.mark == "good" and L["Good"] or L["Avoid"]) .. ": " .. mark.name .. "|r"
	end
	return table.concat(parts, "  ")
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function Parts(row)
	local parts = rowParts[row]
	if parts then return parts end
	parts = {}
	parts.tag = Kit.Text(row, E.tokens.size.small, "RIGHT")
	parts.tag:SetPoint("TOPRIGHT", row, "TOPRIGHT", -22, -4)
	parts.tag:SetWordWrap(false)
	-- The kit's cross glyph (never a letter), secondary gray, hover and
	-- pressed states and a padded hit rect.
	parts.dismiss = Kit.IconButton(row, 14, "cross", function() if row.resultID then GF:Dismiss(row.resultID) end end,
		L["Dismiss"], L["Dims this listing (by its leader) until you bring it back on the filter bar."])
	parts.dismiss:SetPoint("TOPRIGHT", row, "TOPRIGHT", -5, -3)
	rowParts[row] = parts
	return parts
end

function GF:StyleRow(row)
	if not Usable(row) then return end
	local parts = rowParts[row]
	local filters, notes = On(), NotesOn()
	if not (filters or notes) then
		if parts then
			row:SetAlpha(1)
			parts.tag:Hide()
			parts.dismiss:Hide()
		end
		return
	end
	parts = Parts(row)
	local resultID = row.resultID
	local info = Info(resultID)
	local own = info and Clean(info.hasSelf)
	-- Filters: dim.
	if filters and info and not own then
		row:SetAlpha(self:Matches(resultID, info) and 1 or E.tokens.disabledAlpha)
		parts.dismiss:Show()
	else
		row:SetAlpha(1)
		parts.dismiss:Hide()
	end
	local text = notes and info and MarkText(self:Marks(resultID, info)) or ""
	parts.tag:SetText(text)
	parts.tag:SetShown(text ~= "")
end

local function ForEachRow(fn)
	local browse = _G.LFGBrowseFrame
	local box = Usable(browse) and browse.ScrollBox
	if box and box.ForEachFrame then
		pcall(box.ForEachFrame, box, function(row) if row and row.resultID ~= nil then Try(fn, row) end end)
	end
end

---------------------------------------------------------------------------
-- The list: hide filtered listings after Blizzard sorted them
---------------------------------------------------------------------------
function GF:AfterSort(results, countOnly)
	if type(results) ~= "table" then return end
	local total, matched = #results, 0
	for _, resultID in ipairs(results) do
		if not On() or self:Matches(resultID) then matched = matched + 1 end
	end
	last.total, last.matched, last.hidden = total, matched, 0
	self:UpdateBar()
end

function GF:Counts()
	return last.total, last.matched, last.hidden
end

---------------------------------------------------------------------------
-- The filter bar (under the browse page, or over it near the screen's
-- bottom edge)
---------------------------------------------------------------------------
local bar

local CHIPS = {
	{ "tank", "Tank", "Groups that still need a tank, and players on their own who play one." },
	{ "healer", "Healer", "Groups that still need a healer, and players on their own who play one." },
	{ "dps", "Damage", "Groups that still need damage, and players on their own who deal it." },
	{ "level", "Level fits", "Groups whose activity suits your level, and players on their own within 5 levels of you." },
	{ "notFull", "Not full", "Groups with a free place." },
	{ "friends", "Friends", "Listings with a friend or a guild member in them." },
}

local function Place()
	local browse = _G.LFGBrowseFrame
	if not (bar and Usable(browse)) then return end
	bar:ClearAllPoints()
	local bottom = browse:GetBottom()
	if bottom and bottom < bar:GetHeight() + 8 then
		bar:SetPoint("BOTTOMLEFT", browse, "TOPLEFT", 0, 2)
		bar:SetPoint("BOTTOMRIGHT", browse, "TOPRIGHT", 0, 2)
	else
		bar:SetPoint("TOPLEFT", browse, "BOTTOMLEFT", 0, -2)
		bar:SetPoint("TOPRIGHT", browse, "BOTTOMRIGHT", 0, -2)
	end
end

local function CreateBar()
	local browse = _G.LFGBrowseFrame
	if bar or not Usable(browse) then return bar end
	bar = CreateFrame("Frame", "EldoUIGroupFinderFilters", browse)
	bar:SetHeight(58)
	bar:SetFrameLevel((browse:GetFrameLevel() or 1) + 5)
	E:SetTemplate(bar, M.db.transparent)
	bar.chips = Kit.ChipBar(bar, {
		multi = true,
		chips = CHIPS,
		selected = {},
		onChange = function(selected)
			local state = GF:State()
			for _, chip in ipairs(CHIPS) do state[chip[1]] = selected[chip[1]] == true end
			GF:Refresh(true)
		end,
	})
	bar.chips:SetPoint("TOPLEFT", 8, -7)
	bar.search = CreateFrame("EditBox", nil, bar, "SearchBoxTemplate")
	E:SearchHint(bar.search)
	bar.search:SetSize(150, 20)
	bar.search:SetAutoFocus(false)
	bar.search:SetPoint("BOTTOMLEFT", 12, 7)
	E:SkinEditBox(bar.search)
	bar.search:SetScript("OnTextChanged", function(box, user)
		if SearchBoxTemplate_OnTextChanged then pcall(SearchBoxTemplate_OnTextChanged, box) end
		if not user then return end
		GF:State().text = box:GetText() or ""
		GF:Refresh(true)
	end)
	Kit.Tooltip(bar.search, L["Leader or activity"], L["Shows listings whose leader or activity name has this text. The game keeps listing comments from addons, so they can't be searched."])
	bar.clear = Kit.Button(bar, L["Clear"], 60, 20, function(self, button)
		if E:IsOptionsLinkClick(self, button) then return end
		GF:ClearFilters()
	end, L["Clear"], L["Turns every filter off."])
	E:BindOptionsLink(bar.clear, { page = "module:Social" })
	Kit.FitButton(bar.clear, 50)
	bar.clear:SetPoint("LEFT", bar.search, "RIGHT", 6, 0)
	bar.back = Kit.Button(bar, L["Bring back"], 80, 20, function() GF:BringBack() end,
		L["Bring back"], L["Shows the listings you dismissed again."])
	Kit.FitButton(bar.back, 70)
	bar.back:SetPoint("LEFT", bar.clear, "RIGHT", 4, 0)
	bar.status = Kit.Text(bar, E.tokens.size.small, "RIGHT", "secondary")
	bar.status:SetPoint("BOTTOMRIGHT", -8, 11)
	bar.status:SetPoint("BOTTOMLEFT", bar.back, "BOTTOMRIGHT", 6, 4) -- the buttons stand 7 up, the text 11
	bar.status:SetWordWrap(false)
	bar:SetScript("OnShow", Place)
	return bar
end

function GF:Bar() return bar end

function GF:UpdateBar()
	if not bar then return end
	local state = self:State()
	local selected = {}
	for _, chip in ipairs(CHIPS) do if state[chip[1]] then selected[chip[1]] = true end end
	bar.chips:SetSelected(selected)
	if not bar.search:HasFocus() and (bar.search:GetText() or "") ~= (state.text or "") then bar.search:SetText(state.text or "") end
	local count = self:DismissedCount()
	bar.back:SetText(count > 0 and L["Bring back (%d)"]:format(count) or L["Bring back"])
	Kit.FitButton(bar.back, 70)
	bar.back:SetEnabled(count > 0)
	bar.clear:SetEnabled(self:Active() and true or false)
	local total, matched, hidden = self:Counts()
	local text
	if total == 0 then
		text = ""
	elseif hidden > 0 then
		text = E:Plural(hidden, "%d of %d hidden", "%d of %d hidden"):format(hidden, total)
	elseif matched < total then
		text = E:Plural(total - matched, "%d of %d dimmed", "%d of %d dimmed"):format(total - matched, total)
	else
		text = E:Plural(total, "%d listing", "%d listings"):format(total)
	end
	bar.status:SetText(text)
end

function GF:ClearFilters()
	if bar then bar.search:ClearFocus() end
	local state = self:State()
	for key, value in pairs(DEFAULTS.filter) do state[key] = value end
	self:Refresh(true)
end

---------------------------------------------------------------------------
-- Applying
---------------------------------------------------------------------------
-- After a filter change: recount from the page's list without changing it.
function GF:Refresh(filtersChanged)
	local browse = _G.LFGBrowseFrame
	if filtersChanged and Usable(browse) and browse.results then
		self:AfterSort(browse.results, true)
	end
	ForEachRow(function(row) GF:StyleRow(row) end)
	self:UpdateBar()
end

-- Post-hooks, installed again if the page's functions were replaced.
local hookedSort, hookedRow
local function Hook()
	local sort = rawget(_G, "LFGBrowseUtil_SortSearchResults")
	if type(sort) == "function" and sort ~= hookedSort then
		hooksecurefunc("LFGBrowseUtil_SortSearchResults", function(results)
			if M.active then Try(GF.AfterSort, GF, results) end
		end)
		hookedSort = rawget(_G, "LFGBrowseUtil_SortSearchResults")
	end
	local update = rawget(_G, "LFGBrowseSearchEntry_Update")
	if type(update) == "function" and update ~= hookedRow then
		hooksecurefunc("LFGBrowseSearchEntry_Update", function(row)
			if M.active then Try(GF.StyleRow, GF, row) end
		end)
		hookedRow = rawget(_G, "LFGBrowseSearchEntry_Update")
	end
end

function GF:Apply()
	Hook()
	local browse = _G.LFGBrowseFrame
	if On() then
		CreateBar()
		if bar then
			E:SetTemplate(bar, M.db.transparent)
			bar:Show()
			Place()
		end
	elseif bar then
		bar:Hide()
	end
	if Usable(browse) then self:Refresh(true) end
end

function GF:Undo()
	if bar then bar:Hide() end
	ForEachRow(function(row) GF:StyleRow(row) end)
	-- Hidden listings come back with the page's next update.
	local browse = _G.LFGBrowseFrame
	if last.hidden > 0 and Usable(browse) and browse.UpdateResultList and browse:IsShown() then
		pcall(browse.UpdateResultList, browse)
	end
	last.total, last.matched, last.hidden = 0, 0, 0
end

-- Wrap the group finder part (Modules/Social/GroupFinder.lua).
for _, part in ipairs(M.parts) do
	if part.id == ID then
		local apply, undo = part.apply, part.undo
		part.apply = function(self)
			if apply then apply(self) end
			Try(GF.Apply, GF)
		end
		part.undo = function(self)
			if undo then undo(self) end
			Try(GF.Undo, GF)
		end
	end
end

---------------------------------------------------------------------------
-- Options: after the group finder's own rows
---------------------------------------------------------------------------
local OPTIONS = {
	{ type = "header", label = "Browse filters" },
	{ type = "toggle", disabled = E:BlizzardNeeds(ID, "improve"), key = "lfg.filters", label = "Filter bar",
		desc = "A bar under the browse page: role needed, level fits, not full, friends or guild, a name filter and dismissed listings." },
	{ type = "select", key = "lfg.dismissFor", label = "Dismissed listings stay away", order = { "30", "reload" },
		values = { ["30"] = "For 30 minutes", reload = "Until /reload" },
		desc = "The x on a listing dismisses it (by its leader). Bring back on the filter bar shows them again at any time.",
		hidden = function() return not M.db.lfg.filters end },
	{ type = "toggle", key = "lfg.remember", label = "Remember the filters",
		desc = "The filters you chose are still on next time you log in. Off: they start cleared every session.",
		hidden = function() return not M.db.lfg.filters end },
	{ type = "toggle", key = "lfg.notes", label = "Player Notes marks", disabled = E:BlizzardNeeds(ID, "improve"),
		desc = "Your Good or Avoid mark from Player Notes on the leader and members of a listing. Needs the Player Notes module." },
}

local insertAt
for index, option in ipairs(M.options) do
	if option.key == "lfg.whoLevelColors" then insertAt = index + 1 end
end
for offset, option in ipairs(OPTIONS) do
	if insertAt then table.insert(M.options, insertAt + offset - 1, option) else table.insert(M.options, option) end
end

-- A look preset for the finder (merged into the Social presets).
if E.styles and E.styles.Social then
	table.insert(E.styles.Social, { key = "CompactFinder", title = "Compact finder",
		desc = "The EldoUI look with smaller group finder list text and Player Notes marks on listings.",
		settings = { lfg = { rowSize = 11, notes = true, sideTabs = true, whoSkin = true, whoClassColors = true, whoLevelColors = true } } })
end
