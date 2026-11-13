-- EldoUI Info Bar: the group roll tracker.
--
-- Every /roll the game prints is read from its system line and listed in
-- one round, highest first, with the winner marked. The usual range is the
-- one most rolls of the round used (1-100 when none stands out); a roll
-- outside it, and a second roll by the same player, is marked and not
-- counted. A tie is shown as a tie. A roll two minutes after the round's
-- last roll starts a new round; Clear starts one at once.
--
-- The "Rolls" block shows the round's leader; a click opens the roll
-- window, a right-click clears the round. The window has Roll (your own
-- /roll), Pass (marks you and says "pass" once in group chat) and, for the
-- group leader, Announce the winner. It closes after a set time without
-- rolls, never while the mouse is over it.
--
-- Rules (Forever): the rolls come from the line the game printed, matched
-- against the client's own string (RANDOM_ROLL_RESULT) in every client
-- language; a secret line is never read. In dungeons and raids the game
-- hides those lines, and the window says so instead of staying empty. Nothing rolls or posts without
-- the player's click, and a refused chat line is reported, never retried.
local _, E = ...
local L = E.L
local M = E.modules.InfoBar

local ROUND_GAP = 120 -- seconds without a roll before the next roll starts a new round
local TICK = "InfoBarRolls"
local WIDTH, ROW, SUMMARY, MAX_ROWS = 360, 18, 20, 10

M.defaults.rollClose = 60     -- seconds without a roll before the window closes; 0 keeps it open
M.defaults.rollOpen = false   -- open the window on the first roll of a round in a group
M.defaults.rollWindow = {}    -- the window's position

local Rolls = {}
M.rolls = Rolls

local function Grey(text) return E:TextHex("secondary") .. text .. "|r" end
local function Now() return GetTime() end
local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, value = pcall(fn, ...)
	return ok and value or nil
end

local function InGroup() return Try(IsInGroup) and true or false end

-- In dungeons and raids the game hides its chat lines, /roll results
-- among them, from addons. The window and the block say so.
local function LinesHidden() return E.CommRestricted and E:CommRestricted() or false end
function Rolls.EmptyText()
	if LinesHidden() then return L["The game hides /roll results from addons in dungeons and raids."] end
	return L["No rolls yet. Every /roll you can see shows here, highest first."]
end

-- Forever has no instance groups: raid or party.
local function GroupChannel()
	if Try(IsInRaid) then return "RAID" end
	if InGroup() then return "PARTY" end
end

function Rolls.IsLeader()
	return InGroup() and Try(UnitIsGroupLeader, "player") and true or false
end

---------------------------------------------------------------------------
-- Reading the roll line
---------------------------------------------------------------------------
-- name, roll, low, high from a system line, or nil. The format is the
-- client's own, so translations that reorder it still read right.
function Rolls.Parse(text)
	local format = rawget(_G, "RANDOM_ROLL_RESULT")
	local args = E.ChatParse:MatchFormat(text, format)
	if not args then return nil end
	local name, roll, low, high = args[1], tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
	if type(name) ~= "string" or name == "" or not (roll and low and high) then return nil end
	return name, roll, low, high
end

-- The class of a group member by the name the roll line gave, or nil.
local function ClassOf(name)
	if E:IsMe(name) then return select(2, UnitClass("player")) end
	local short = name:match("^([^%-]+)") or name
	local raid = Try(IsInRaid)
	for index = 1, raid and 40 or 4 do
		local unit = (raid and "raid" or "party") .. index
		if Try(UnitExists, unit) then
			local unitName = E:UnitNameRealm(unit)
			if type(unitName) == "string" and not E.Secret(unitName) and unitName == short then
				local ok, _, class = pcall(UnitClass, unit)
				if ok and type(class) == "string" and not E.Secret(class) then return class end
			end
		end
	end
end

local function Key(name) return name:lower() end

---------------------------------------------------------------------------
-- The round
---------------------------------------------------------------------------
function Rolls:NewRound()
	self.round = { started = Now(), last = Now(), rolls = {}, passes = {}, seen = {} }
	return self.round
end

-- The round while it goes on, or nil.
function Rolls:Active()
	local round = self.round
	if round and Now() - round.last <= ROUND_GAP then return round end
	return nil
end

function Rolls:Add(name, roll, low, high)
	local round = self:Active()
	local fresh = round == nil
	if fresh then round = self:NewRound() end
	round.last = Now()
	local key = Key(name)
	local entry = { name = name, roll = roll, low = low, high = high, order = #round.rolls + 1,
		again = round.seen[key] ~= nil, me = E:IsMe(name), class = ClassOf(name) }
	round.seen[key] = round.seen[key] or entry
	round.passes[key] = nil
	if entry.me then round.mine = round.mine or entry end
	round.rolls[#round.rolls + 1] = entry
	self.activity = Now()
	if fresh and M.db and M.db.rollOpen and InGroup() then self:Open() end
	self:Refresh()
	return entry
end

function Rolls:Clear()
	self.round = nil
	self:Refresh()
end

-- The usual range: the one most first rolls used, 1-100 when none stands out.
function Rolls.Range(round)
	local counts = {}
	for _, entry in ipairs(round and round.rolls or {}) do
		if not entry.again then
			local key = entry.low .. ":" .. entry.high
			counts[key] = (counts[key] or 0) + 1
		end
	end
	local best, bestCount, tie = nil, 0, false
	for key, count in pairs(counts) do
		if count > bestCount then
			best, bestCount, tie = key, count, false
		elseif count == bestCount then
			tie = true
		end
	end
	if not best or tie then return 1, 100 end
	local low, high = best:match("^(%-?%d+):(%-?%d+)$")
	return tonumber(low), tonumber(high)
end

-- The round's rolls, counted ones first and highest first; the winners
-- (more than one on a tie); the usual range.
function Rolls:Standings()
	local round = self.round
	if not round then return {}, {}, 1, 100 end
	local low, high = Rolls.Range(round)
	local list = {}
	for _, entry in ipairs(round.rolls) do
		entry.odd = entry.low ~= low or entry.high ~= high
		entry.counted = not entry.again and not entry.odd
		list[#list + 1] = entry
	end
	table.sort(list, function(a, b)
		if a.counted ~= b.counted then return a.counted end
		if a.roll ~= b.roll then return a.roll > b.roll end
		return a.order < b.order
	end)
	local winners, top = {}, nil
	for _, entry in ipairs(list) do
		if entry.counted then
			top = top or entry.roll
			entry.winner = entry.roll == top
			if entry.winner then winners[#winners + 1] = entry end
		else
			entry.winner = false
		end
	end
	return list, winners, low, high
end

-- The names that passed, in the order they did.
function Rolls:Passes()
	local names = {}
	for _, pass in pairs(self.round and self.round.passes or {}) do names[#names + 1] = pass end
	table.sort(names, function(a, b) return a.at < b.at end)
	return names
end

---------------------------------------------------------------------------
-- The buttons (each runs only on the player's click)
---------------------------------------------------------------------------
local function Say(text) E:Print(text) end

function Rolls:Roll()
	if type(RandomRoll) ~= "function" then return false end
	return pcall(RandomRoll, 1, 100)
end

-- Marks you as passing and says "pass" once in group chat.
function Rolls:Pass()
	local round = self:Active() or self:NewRound()
	if round.mine then return false end
	local name = E:PlayerName() or "?"
	local key = Key(name)
	if round.passes[key] then return false end
	round.passes[key] = { name = name, class = select(2, UnitClass("player")), at = Now(), me = true }
	round.last = Now()
	self.activity = Now()
	local channel = GroupChannel()
	local posted = false
	if channel then
		posted = E:TryChatPost(L["pass"], channel)
		if not posted then Say(E:ChatRefusedText()) end
	end
	self:Refresh()
	return true, posted
end

-- The line Announce posts, or nil while nothing counted.
function Rolls:AnnounceText()
	local _, winners, low, high = self:Standings()
	if #winners == 0 then return nil end
	if #winners == 1 then
		return L["Roll won by %s with %d (%d-%d)."]:format(winners[1].name, winners[1].roll, low, high)
	end
	local names = {}
	for _, entry in ipairs(winners) do names[#names + 1] = entry.name end
	return L["Roll tie at %d (%d-%d): %s."]:format(winners[1].roll, low, high, table.concat(names, ", "))
end

function Rolls:Announce()
	if not Rolls.IsLeader() then return false end
	local text = self:AnnounceText()
	local channel = GroupChannel()
	if not (text and channel) then return false end
	if not E:TryChatPost(text, channel) then
		Say(E:ChatRefusedText())
		return false
	end
	return true
end

---------------------------------------------------------------------------
-- Texts shared by the block and the window
---------------------------------------------------------------------------
local function NameText(entry, grey)
	local name = entry.me and L["%s (you)"]:format(entry.name) or entry.name
	if grey then return Grey(name) end
	return entry.class and E:WrapClassColor(entry.class, name) or name
end

local function NoteText(entry, single, low, high)
	if entry.winner then return E:StatusText(single and "good" or "warn", single and L["Winner"] or L["Tie"]) end
	if entry.again then return Grey(L["second roll"]) end
	if entry.odd then return Grey(L["range %d-%d"]:format(entry.low, entry.high)) end
	return ""
end

local function RollCount(count) return E:Plural(count, "%d roll", "%d rolls"):format(count) end

local function SummaryText(list, low, high)
	return L["Range %d-%d"]:format(low, high) .. Grey(" · ") .. RollCount(#list)
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function CreateRow(content, index)
	local Kit = E.UIKit
	local row = CreateFrame("Frame", nil, content)
	row:SetHeight(ROW)
	row:SetPoint("TOPLEFT", 0, -(SUMMARY + (index - 1) * ROW))
	row:SetPoint("TOPRIGHT", 0, -(SUMMARY + (index - 1) * ROW))
	row.rank = Kit.Text(row, E.tokens.size.small, "RIGHT", "secondary")
	row.rank:SetPoint("LEFT", 0, 0)
	row.rank:SetWidth(18)
	row.value = Kit.Text(row, E.tokens.size.label, "RIGHT")
	row.value:SetPoint("RIGHT", -2, 0)
	row.value:SetWidth(32)
	row.note = Kit.Text(row, E.tokens.size.small, "RIGHT", "secondary")
	row.note:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
	row.note:SetWordWrap(false)
	row.name = Kit.Text(row, E.tokens.size.label, "LEFT")
	row.name:SetPoint("LEFT", 24, 0)
	row.name:SetPoint("RIGHT", row.note, "LEFT", -6, 0)
	row.name:SetWordWrap(false)
	return row
end

function Rolls:BuildWindow()
	if self.window then return self.window end
	local Kit = E.UIKit
	local win = Kit.CreateToolWindow("EldoUI_RollTracker", { title = L["Rolls"], width = WIDTH, height = 200,
		footer = Kit.TOOL_FOOTER, resizable = false,
		store = function() return M.db and M.db.rollWindow end,
		onClose = function() E.Ticker:Unsubscribe(TICK) end })
	self.window = win
	local content = win.content
	win.summary = Kit.Text(content, E.tokens.size.small, "LEFT", "secondary")
	win.summary:SetPoint("TOPLEFT", 2, -2)
	win.summary:SetPoint("TOPRIGHT", -2, -2)
	win.summary:SetWordWrap(false)
	win.rows = {}
	for index = 1, MAX_ROWS do win.rows[index] = CreateRow(content, index) end
	win.more = Kit.Text(content, E.tokens.size.small, "LEFT", "secondary")
	win.more:SetWordWrap(false)
	win.passes = Kit.Text(content, E.tokens.size.small, "LEFT", "secondary")
	win.passes:SetWordWrap(true)
	win.empty = Kit.Text(content, E.tokens.size.label, "LEFT", "secondary")
	win.empty:SetPoint("TOPLEFT", 2, -(SUMMARY + 2))
	win.empty:SetPoint("TOPRIGHT", -2, -(SUMMARY + 2))
	win.empty:SetWordWrap(true)
	win.empty:SetText(Rolls.EmptyText())

	win.announce = Kit.Button(win.footer, { text = L["Announce the winner"], kind = "primary", onClick = function() Rolls:Announce() end,
		tip = { L["Announce the winner"], L["One line with the winner in party or raid chat. Only the group leader has this button."] } })
	win.announce:SetPoint("RIGHT", -Kit.TOOL_PAD, 0)
	win.pass = Kit.Button(win.footer, { text = L["Pass"], onClick = function() Rolls:Pass() end,
		tip = { L["Pass"], L["Marks you as passing and says \"pass\" once in party or raid chat."] } })
	win.roll = Kit.Button(win.footer, { text = L["Roll"], onClick = function() Rolls:Roll() end,
		tip = { L["Roll"], L["Rolls 1-100, as /roll does."] } })
	win.pass:SetPoint("RIGHT", win.announce, "LEFT", -6, 0)
	win.roll:SetPoint("RIGHT", win.pass, "LEFT", -6, 0)
	win.footerText:SetText("")
	win:HookScript("OnShow", function()
		Rolls.activity = Now()
		E.Ticker:Subscribe(TICK, 1, function() Rolls:Tick() end, M)
		Rolls:Refresh()
	end)
	return win
end

function Rolls:Open()
	self:BuildWindow():Open()
	self:Refresh()
end

function Rolls:Toggle()
	local win = self:BuildWindow()
	if win:IsShown() then win:Close() else self:Open() end
end

-- Closes the window after the set time without rolls; the mouse over it
-- keeps it open and starts the wait again.
function Rolls:CheckClose()
	local win = self.window
	if not (win and win:IsShown()) then return end
	local after = tonumber(M.db and M.db.rollClose) or 60
	if after <= 0 then return end
	if win:IsMouseOver() then
		self.activity = Now()
		return
	end
	if Now() - (self.activity or 0) >= after then win:Close() end
end

-- Once a second while the window is open: the empty line follows the
-- game's chat restriction (entering or leaving a dungeon).
function Rolls:Tick()
	local win = self.window
	if win and win:IsShown() and win.empty:IsShown() then win.empty:SetText(Rolls.EmptyText()) end
	self:CheckClose()
end

function Rolls:Refresh()
	if M.active then M:RefreshDataText("Rolls") end
	local win = self.window
	if not (win and win:IsShown()) then return end
	local Kit = E.UIKit
	local list, winners, low, high = self:Standings()
	local single = #winners == 1
	win.summary:SetText(self.round and SummaryText(list, low, high) or "")
	local shown = math.min(#list, MAX_ROWS)
	for index, row in ipairs(win.rows) do
		local entry = list[index]
		row:SetShown(entry ~= nil)
		if entry then
			local grey = not entry.counted
			row.rank:SetText(entry.counted and tostring(index) or "")
			row.name:SetText(NameText(entry, grey))
			row.note:SetText(NoteText(entry, single, low, high))
			local value = tostring(entry.roll)
			if entry.winner then
				value = E:TextHex(single and "good" or "warn") .. value .. "|r"
			elseif grey then
				value = Grey(value)
			end
			row.value:SetText(value)
		end
	end
	local y = SUMMARY + shown * ROW
	win.more:SetShown(#list > MAX_ROWS)
	if #list > MAX_ROWS then
		win.more:ClearAllPoints()
		win.more:SetPoint("TOPLEFT", 2, -(y + 2))
		win.more:SetPoint("TOPRIGHT", -2, -(y + 2))
		win.more:SetText(L["and %d more"]:format(#list - MAX_ROWS))
		y = y + 16
	end
	local passes = self:Passes()
	win.passes:SetShown(#passes > 0)
	if #passes > 0 then
		local names = {}
		for _, pass in ipairs(passes) do names[#names + 1] = NameText(pass) end
		win.passes:ClearAllPoints()
		win.passes:SetPoint("TOPLEFT", 2, -(y + 4))
		win.passes:SetPoint("TOPRIGHT", -2, -(y + 4))
		win.passes:SetText(L["Passed: %s"]:format(table.concat(names, ", ")))
		y = y + 4 + math.max(math.ceil(win.passes:GetStringHeight() or 14), 14)
	end
	win.empty:SetText(Rolls.EmptyText())
	win.empty:SetShown(#list == 0 and #passes == 0)
	if #list == 0 and #passes == 0 then y = y + 36 end
	win:SetHeight(Kit.TOOL_HEADER + 2 * Kit.TOOL_PAD + y + 4 + Kit.TOOL_FOOTER)

	local round = self:Active()
	local rolled = round and round.mine ~= nil
	local passed = false
	if round then
		for _, pass in pairs(round.passes) do
			if pass.me then passed = true end
		end
	end
	win.roll:SetEnabled(not rolled)
	win.pass:SetEnabled(not (rolled or passed))
	local leader = Rolls.IsLeader()
	win.announce:SetShown(leader)
	win.announce:SetEnabled(leader and #winners > 0)
	win.pass:ClearAllPoints()
	if leader then
		win.pass:SetPoint("RIGHT", win.announce, "LEFT", -6, 0)
	else
		win.pass:SetPoint("RIGHT", -Kit.TOOL_PAD, 0)
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
function Rolls:OnSystemLine(text)
	local name, roll, low, high = Rolls.Parse(text)
	if name then self:Add(name, roll, low, high) end
end

function Rolls:Enable()
	if not self.events then
		self.events = CreateFrame("Frame")
		self.events:SetScript("OnEvent", function(_, _, text) Rolls:OnSystemLine(text) end)
	end
	self.events:RegisterEvent("CHAT_MSG_SYSTEM")
end

function Rolls:Disable()
	if self.events then self.events:UnregisterAllEvents() end
	E.Ticker:Unsubscribe(TICK)
	if self.window and self.window:IsShown() then self.window:Hide() end
end

M:AddExtra(Rolls)

---------------------------------------------------------------------------
-- The block
---------------------------------------------------------------------------
E:RegisterDataText("Rolls", {
	title = "Rolls",
	label = "Rolls",
	icon = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
	poll = true,
	interval = 10, -- a round ends two minutes after its last roll
	text = function()
		if not Rolls.round then return Grey(L["No rolls"]) end
		local list, winners = Rolls:Standings()
		local text
		if #winners == 1 then
			text = NameText(winners[1]) .. " " .. M.Value(tostring(winners[1].roll))
		elseif #winners > 1 then
			text = E:StatusText("warn", L["Tie at %d"]:format(winners[1].roll))
		else
			text = RollCount(#list)
		end
		if not Rolls:Active() then return Grey((text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))) end
		return text
	end,
	tooltip = function(tooltip)
		local Kit = E.UIKit
		if not Rolls.round then
			Kit.TipText(tooltip, Rolls.EmptyText())
			return
		end
		local list, winners, low, high = Rolls:Standings()
		local single = #winners == 1
		Kit.TipText(tooltip, SummaryText(list, low, high))
		for index = 1, math.min(#list, 5) do
			local entry = list[index]
			local note = NoteText(entry, single, low, high)
			local right = (note ~= "" and (note .. "  ") or "") .. (entry.counted and tostring(entry.roll) or Grey(tostring(entry.roll)))
			tooltip:AddDoubleLine(NameText(entry, not entry.counted), right, 1, 1, 1, 1, 1, 1)
		end
		if #list > 5 then Kit.TipText(tooltip, L["and %d more"]:format(#list - 5)) end
		local passes = Rolls:Passes()
		if #passes > 0 then
			local names = {}
			for _, pass in ipairs(passes) do names[#names + 1] = NameText(pass) end
			Kit.TipText(tooltip, L["Passed: %s"]:format(table.concat(names, ", ")))
		end
		if not Rolls:Active() then Kit.TipText(tooltip, L["The round is over: the next roll starts a new one."]) end
	end,
	hint = function() return { { L["Click"], L["open the roll window"] }, { L["Right-click"], L["clear the rolls"] } } end,
	combatClick = true,
	onClick = function(_, mouseButton)
		if mouseButton == "RightButton" then Rolls:Clear() else Rolls:Toggle() end
	end,
})

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
M.InsertOptions({
	{ type = "header", label = "Roll tracker" },
	{ type = "range", key = "rollClose", label = "Close the roll window after", unit = "s", min = 0, max = 300, step = 10,
		desc = "How long the roll window stays open without a new roll. It never closes while the mouse is over it. 0 keeps it open." },
	{ type = "toggle", key = "rollOpen", label = "Open on the first group roll",
		desc = "Opens the roll window when someone in your group starts a round of rolls. The Rolls block opens it with a click." },
})
