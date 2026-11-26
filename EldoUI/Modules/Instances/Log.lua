-- EldoUI Instances: the run log window.
--
--   +------------------------------------------------------------+
--   | Instance log  All 12  Dungeons 9  Raids 1  PvP 2   ? gear x |
--   |------------------------------------------------------------|
--   | [Alts] [24 h]                     green: counts this hour    |
--   | [i] The Deadmines  + this hour                    [c] [x] |
--   |     #n · 14:05 · Mira · 23m left                           |
--   | [i] The Stockade  ! 24 h                          [c] [x] |
--   |     #n · 13:31 · Mira · 2 hrs ago · merged 2               |
--   |------------------------------------------------------------|
--   | 3/5 this hour (estimate) · 7 in 24 h                         |
--   +------------------------------------------------------------+
--
-- Built from E.UIKit.CreateTabbedWindow on the mover EldoUI_InstanceLog
-- (600 x 460, layout points in tools/data/layout-points/instances.json).
-- Rows are the kit's two-line rows (DESIGN.md §0a rule 5): an icon for the
-- kind of run, the instance in its row color with a status mark (green
-- counts toward the hourly limit, yellow is within 24 hours, gray is older
-- or another character), the number, time, character and age on a muted
-- second line. A battleground or a raid that doesn't count is dimmed and
-- says "not counted". Hover: the run's details. Click selects, right-click
-- opens a menu (print, copy, same run as last, post when allowed, remove);
-- the small boxed buttons copy a run or remove it after a confirmation.
local _, E = ...
local L = E.L
local Key = E.Key
local M = E.Instances
local Kit = E.UIKit

local floor = math.floor
local C = M.COLORS
local MOVER = "EldoUI_InstanceLog"
local WIDTH, HEIGHT = 600, 460
local HOUR, DAY = 3600, 86400

local win, anchor
local selected -- id of the selected run

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local TABS = {
	{ key = "all", title = "All", desc = "Every run, newest first." },
	{ key = "party", title = "Dungeons", desc = "Dungeon runs. These count toward the hourly limit." },
	{ key = "raid", title = "Raids", desc = "Raid runs. Raids for up to 20 players count; 40-player raids count only with \"Count raids\" on." },
	{ key = "pvp", title = "PvP", desc = "Battlegrounds with the result and honor. They never count." },
}

-- Runs for a tab with the filters: newest first.
function M:LogRuns(kind)
	local now = self:Now()
	local mine = self:CharKey()
	local list = {}
	for _, run in ipairs(self:Runs()) do
		local keep = kind == "all" or run.kind == kind
		if keep and not self.db.logAlts and run.char ~= mine then keep = false end
		if keep and self.db.log24h and now - (run.leave or now) >= DAY then keep = false end
		if keep then list[#list + 1] = run end
	end
	return list
end

-- The row color of a run.
function M:RunColor(run, now)
	now = now or self:Now()
	if run.kind == "pvp" or not self:Counts(run) then return C.UNCOUNTED end
	if run.char ~= self:CharKey() then return C.GREY end
	local age = now - self:CountTime(run, now)
	if age < HOUR then return C.GREEN end
	if age < DAY then return C.YELLOW end
	return C.GREY
end

-- The same as a text kind: "good", "warn", "secondary" or "dim".
function M:RunKind(run, now)
	local color = self:RunColor(run, now)
	if color == C.GREEN then return "good" end
	if color == C.YELLOW then return "warn" end
	if color == C.UNCOUNTED then return "dim" end
	return "secondary"
end

-- "(23m left)", "(inside)" or "(2 hrs ago)".
function M:RunWhen(run, now)
	now = now or self:Now()
	if not run.leave then return L["inside"] end
	local age = now - run.leave
	if self.db.logLockoutTime and self:Counts(run) and age < HOUR then
		return (L["%s left"]):format(self:Duration(HOUR - age))
	end
	return (L["%s ago"]):format(self:Duration(age))
end

-- What a run's row shows: the title, its status word, the muted line
-- ("#n · 14:05 · Mira · 23m left · merged 2") and whether it is dimmed.
local STATUS_WORDS = E:TranslateValues({ good = E.Key("this hour"), warn = E.Key("24 h") })
function M:RowParts(run, number, now)
	now = now or self:Now()
	local kind = self:RunKind(run, now)
	local uncounted = run.kind == "pvp" or not self:Counts(run)
	local sub = { ("#%d"):format(number), self:Clock(run.leave or run.enter), self:ShortName(run), self:RunWhen(run, now) }
	if (run.merged or 0) > 0 then sub[#sub + 1] = (L["merged %d"]):format(run.merged) end
	if self.RowResult then
		local result = self:RowResult(run)
		if result then sub[#sub + 1] = result end
	end
	return {
		title = self:RunTitle(run),
		kind = kind,
		status = (kind == "good" or kind == "warn") and kind or nil,
		statusText = uncounted and L["not counted"] or STATUS_WORDS[kind],
		sub = table.concat(sub, " · "),
		dimmed = uncounted,
	}
end

-- The same as one line (chat, copy): "12) 14:05  Mira  The Deadmines (23m left)".
function M:RowText(run, number, now)
	now = now or self:Now()
	local parts = { ("%d) %s"):format(number, self:Clock(run.leave or run.enter)) }
	parts[#parts + 1] = self:ShortName(run)
	parts[#parts + 1] = self:RunColor(run, now) .. self:RunTitle(run) .. "|r"
	local extra = { self:RunWhen(run, now) }
	-- A run that doesn't count says so, not only by its color.
	if run.kind == "pvp" or not self:Counts(run) then table.insert(extra, 1, L["not counted"]) end
	if (run.merged or 0) > 0 then extra[#extra + 1] = (L["merged %d"]):format(run.merged) end
	if self.RowResult then
		local result = self:RowResult(run)
		if result then extra[#extra + 1] = result end
	end
	parts[#parts + 1] = C.GREY .. "(" .. table.concat(extra, ", ") .. ")|r"
	return table.concat(parts, "  ")
end

---------------------------------------------------------------------------
-- Row tooltip: the run's details.
---------------------------------------------------------------------------
local function LevelText(level, xp, xpMax)
	if not level then return "?" end
	if xp and xpMax and xpMax > 0 then return ("%d (%d%%)"):format(level, floor(xp / xpMax * 100)) end
	return tostring(level)
end

-- Gold trades this character made inside the run (from the Trade log, if it is loaded).
function M:RunTrades(run)
	local trades = E.GetTradeLog and E:GetTradeLog(run.enter or 0, run.leave or self:Now()) or {}
	local list = {}
	for _, trade in ipairs(trades) do
		local char = type(trade.char) == "string" and trade.char:match("^(.-) %- ")
		if tonumber(trade.time) and (not char or char == run.name) then list[#list + 1] = trade end
	end
	return list
end

-- A trade can move gold both ways; show each side that moved.
function M:TradeAmountText(trade)
	local parts = {}
	if (trade.received or 0) > 0 then parts[#parts + 1] = "+" .. self:Money(trade.received) end
	if (trade.given or 0) > 0 then parts[#parts + 1] = "-" .. self:Money(trade.given) end
	return #parts > 0 and table.concat(parts, " ") or self:Money(0)
end

function M:FillRunTooltip(tooltip, run)
	local function Line(label, value)
		E.UIKit.TipPair(tooltip, label, value)
	end
	Kit.TipTitle(tooltip, self:RunTitle(run))
	tooltip:AddLine(self:ShortName(run) .. C.GREY .. "  " .. (run.realm or "") .. "|r")
	Line(L["Entered"], self:Clock(run.enter))
	Line(L["Left"], run.leave and self:Clock(run.leave) or L["still inside"])
	Line(L["Time inside"], self:Duration(self:RunDuration(run)))
	if run.kind ~= "pvp" and run.enterLevel then
		local left = run.leave and LevelText(run.leaveLevel, run.leaveXP, run.leaveXPMax) or "-"
		Line(L["Level"], ("%s → %s"):format(LevelText(run.enterLevel, run.enterXP, run.enterXPMax), left))
	end
	if (run.merged or 0) > 0 then Line(L["Entries merged"], tostring(run.merged)) end
	self:AddRunStats(tooltip, run, true)
	local average, count = self:GroupLevel(run)
	if count and count > 0 then
		tooltip:AddLine(" ")
		E.UIKit.TipPair(tooltip, L["Group"], average and L["avg level %.1f"]:format(average) or "", unpack(E.UIKit.SECONDARY))
		local names = {}
		for name in pairs(run.group or {}) do names[#names + 1] = name end
		table.sort(names)
		for _, name in ipairs(names) do
			local info = run.group[name]
			local shown = Ambiguate and Ambiguate(name, "short") or name
			local color = E:ClassColorObject(info.class)
			if color then shown = color:WrapTextInColorCode(shown) end
			local right = (info.level and tostring(info.level) or "") .. (info.guild and (C.GREY .. "  <" .. info.guild .. ">|r") or "")
			tooltip:AddDoubleLine(shown, right, 1, 1, 1, 1, 1, 1)
		end
	end
	local trades = self:RunTrades(run)
	if #trades > 0 then
		tooltip:AddLine(" ")
		E.UIKit.TipText(tooltip, L["Trades inside"])
		for _, trade in ipairs(trades) do
			tooltip:AddDoubleLine(trade.who or "?", self:TradeAmountText(trade), 1, 1, 1, 1, 1, 1)
		end
	end
	if run.kind == "pvp" then
		tooltip:AddLine(" ")
		tooltip:AddLine(L["Battlegrounds never count toward the hourly limit."], E:TokenColor("secondary", true))
	elseif not self:Counts(run) then
		tooltip:AddLine(" ")
		tooltip:AddLine(run.kind == "raid" and not run.uncounted and L["40-player raids don't count toward the hourly limit."]
			or L["This run doesn't count toward the hourly limit."], E:TokenColor("secondary", true))
	else
		local age = self:Now() - self:CountTime(run)
		tooltip:AddLine(" ")
		if not run.leave then
			tooltip:AddLine(L["Counts toward the hourly limit while you are inside."], E:TokenColor("good", true))
		elseif age < HOUR then
			tooltip:AddLine((L["Counts toward the hourly limit for %s more."]):format(self:Duration(HOUR - age)), E:TokenColor("good", true))
		end
	end
	tooltip:AddLine(" ")
	E:TooltipHint(tooltip, { L["Right-click"], L["menu"] })
end

---------------------------------------------------------------------------
-- Row menu
---------------------------------------------------------------------------
function M:CopyRun(id)
	local run = self:FindRun(id)
	if not run then return end
	local text = ("%s, %s, %s: %s"):format(self:RunTitle(run), run.name or "?", self:Clock(run.enter), self:StatLine(run, { all = true }))
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
	E:ShowCopyBox(L["Instance run"], L["Press Ctrl+C to copy."], text)
end

function M:RowMenu(owner, run)
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(self:RunTitle(run))
		root:CreateButton(L["Print to my chat"], function() M:PrintRun(run.id) end)
		root:CreateButton(L["Copy"], function() M:CopyRun(run.id) end)
		if self:ManualMergeTarget(run) then
			root:CreateButton(L["Same run as last"], function() M:ManualMerge(run.id) end)
		end
		if self.db.allowPosting then
			root:CreateDivider()
			root:CreateButton(L["Post to group"], function() M:PostRun(run.id, "GROUP") end)
			root:CreateButton(L["Post to guild"], function() M:PostRun(run.id, "GUILD") end)
		end
		root:CreateDivider()
		root:CreateButton(L["Remove"], function() M:AskDelete(run.id) end)
	end)
end

---------------------------------------------------------------------------
-- A tab: filter chips and a list.
---------------------------------------------------------------------------
-- An icon per kind of run (classic game icons).
local KIND_ICONS = {
	party = "Interface\\Icons\\INV_Misc_Key_03",
	raid = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
	pvp = "Interface\\Icons\\INV_BannerPVP_02",
}

local function UpdateRow(row, run, index)
	local parts = M:RowParts(run, #row.list.data - index + 1, M:Now())
	local color = parts.kind ~= "dim" and E.tokens.text[parts.kind] or nil
	row:SetRow({
		icon = KIND_ICONS[run.kind] or KIND_ICONS.party,
		name = parts.title, color = color,
		status = parts.status, statusText = parts.statusText,
		sub = parts.sub, dimmed = parts.dimmed,
	})
	-- The kit's selection tint fades in and out.
	row:SetSelected(run.id == selected, run.id)
end

local ROW_ACTIONS = {
	{ key = "copy", art = "copy", tipTitle = Key("Copy"), tip = Key("Copy this run as one line of text."),
		onClick = function(run) if run then M:CopyRun(run.id) end end },
	{ key = "remove", art = "cross", danger = true, tipTitle = Key("Remove"), tip = Key("Removes this run after a confirmation."),
		onClick = function(run) if run then M:AskDelete(run.id) end end },
}

local function CreateRow(row)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.remove = row.actionByKey.remove
	row:SetScript("OnClick", function(self, button)
		if not self.item then return end
		if button == "RightButton" then
			M:RowMenu(self, self.item)
		else
			selected = self.item.id
			self.list:Refresh()
		end
	end)
	row:SetScript("OnEnter", function(self)
		if not self.item then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		M:FillRunTooltip(GameTooltip, self.item)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Built on each draw, so it follows the current status colors.
local function Legend()
	return ("%s%s|r  %s%s|r  %s%s|r  %s%s|r"):format(C.GREEN, L["this hour"], C.YELLOW, L["24 h"], C.GREY, L["older or alt"], C.UNCOUNTED, L["not counted"])
end

local function CreateTab(kind)
	return function(content)
		local frame = CreateFrame("Frame", nil, content)
		frame:SetAllPoints()
		frame.chips = Kit.ChipBar(frame, {
			multi = true,
			chips = {
				{ "alts", L["Alts"], L["Show the runs of your other characters too (in gray)."] },
				{ "day", L["24 h"], L["Show only runs from the last 24 hours."] },
			},
			selected = { alts = M.db.logAlts, day = M.db.log24h },
			onChange = function(chosen)
				M.db.logAlts = chosen.alts and true or false
				M.db.log24h = chosen.day and true or false
				if win then win:Refresh("filters") end
			end,
		})
		frame.chips:SetPoint("TOPLEFT", 0, 0)
		frame.legend = Kit.Text(frame, 10, "RIGHT", "secondary")
		frame.legend:SetPoint("RIGHT", frame, "TOPRIGHT", 0, -9)
		frame.legend:SetText(Legend())
		frame.list = Kit.CreateList(frame, Kit.ListRow2Template({ gap = 1, create = CreateRow, update = UpdateRow,
			row = { actions = ROW_ACTIONS } }))
		frame.list:SetPoint("TOPLEFT", 0, -26)
		frame.list:SetPoint("BOTTOMRIGHT")
		frame.kind = kind
		return frame
	end
end

local function ShowTab(frame)
	frame.chips:SetSelected({ alts = M.db.logAlts, day = M.db.log24h })
	frame.list:SetData(M:LogRuns(frame.kind))
end

local EMPTY = E:TranslateValues({
	all = E.Key("Runs show up here when you enter a dungeon, raid or battleground."),
	party = E.Key("No dungeon runs yet. Enter a dungeon and it shows up here."),
	raid = E.Key("No raid runs yet."),
	pvp = E.Key("No battlegrounds yet."),
})

local function EmptyFor(kind)
	return function(frame)
		if #frame.list.data > 0 then return nil end
		local filtered = (not M.db.logAlts or M.db.log24h) and #M:Runs() > 0
		local text = EMPTY[kind]
		if filtered then text = L["Nothing matches the filters. Turn on Alts or turn off 24 h to see more."] end
		return L["No runs"], text, 133735
	end
end

local function Tabs()
	local tabs = {}
	for _, tab in ipairs(TABS) do
		tabs[#tabs + 1] = {
			key = tab.key, title = tab.title, desc = tab.desc,
			count = function() return #M:LogRuns(tab.key) end,
			create = CreateTab(tab.key),
			show = ShowTab,
			refresh = ShowTab,
			empty = EmptyFor(tab.key),
		}
	end
	return tabs
end

---------------------------------------------------------------------------
-- Window and mover
---------------------------------------------------------------------------
local function Scale()
	return win and win:Scale() or 1
end

local function SizeAnchor()
	if anchor then anchor:SetSize(WIDTH * Scale(), HEIGHT * Scale()) end
end

function M:EnsureLogMover()
	if anchor then return anchor end
	anchor = CreateFrame("Frame", "EldoUI_InstanceLogAnchor", UIParent)
	anchor:SetSize(WIDTH, HEIGHT)
	-- Hidden while the window is closed, so it never counts as covering
	-- anything; the mover still shows it in move mode.
	anchor:Hide()
	self.logMover = E:CreateMover(anchor, MOVER, L["Instance Log"], { "TOP", "UIParent", "TOP", 0, -120 }, {
		sample = false,
		onMoved = function() if win then win:ApplyPosition() end end,
	})
	return anchor
end

local function CreateWindow()
	if win then return win end
	win = Kit.CreateTabbedWindow({
		name = "EldoUIInstanceLog",
		options = { page = "module:Instances" },
		title = L["Instance Log"],
		width = WIDTH, height = HEIGHT,
		store = function() return M.db.window end,
		tabs = Tabs(),
		help = { text = function(tooltip)
			E.UIKit.TipText(tooltip, L["Every dungeon, raid and battleground you entered, newest first."])
			tooltip:AddLine(" ")
			tooltip:AddLine(Legend(), Kit.TEXT[1], Kit.TEXT[2], Kit.TEXT[3], true)
			E.UIKit.TipText(tooltip, L["The hourly count is an estimate from your own entries on this ruleset."])
		end },
		footer = function() return M:CountLine() end,
		transparent = function() return M.db.transparent end,
	})
	-- The window sits on its mover: dragging the title bar moves the mover.
	function win:ApplyPosition()
		local frame = self.frame
		if not frame then return end
		frame:SetScale(self:Scale())
		SizeAnchor()
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", M:EnsureLogMover(), "TOPLEFT", 0, 0)
	end
	function win:SavePosition()
		local frame = self.frame
		if not frame then return end
		local scale = frame:GetScale()
		local left, bottom = frame:GetLeft(), frame:GetBottom()
		SizeAnchor()
		if left and bottom and M.logMover then E:SaveMoverFromRect(M.logMover, left * scale, bottom * scale) end
	end
	function win:ResetPosition()
		E.db.movers[MOVER] = nil
		E:ApplyMover(MOVER)
		self:ResetSize()
		self:ApplyPosition()
	end
	return win
end

function M:ShowLog(tab)
	self:EnsureLogMover()
	local window = CreateWindow()
	local first = not window.frame
	window:Build()
	if first then
		window.frame:HookScript("OnShow", function() if anchor then anchor:Show() end end)
		window.frame:HookScript("OnHide", function() if anchor then anchor:Hide() end end)
		window:ApplyPosition()
	end
	if window:IsOpen() and (tab == nil or tab == window:Current()) then
		window:Close()
		return
	end
	window:Open(tab)
end

function M:LogWindow()
	return win
end

function M:ApplyLook()
	if win and win.frame then
		win:Restyle()
		win:ApplyPosition()
	end
end

M:OnChange("log", function(what)
	if win and win:IsOpen() then win:Refresh(what) end
end)

local previousEnable = M.OnEnableParts
function M:OnEnableParts()
	if previousEnable then previousEnable(self) end
	self:EnsureLogMover()
end

local previousDisable = M.OnDisableParts
function M:OnDisableParts()
	if previousDisable then previousDisable(self) end
	if win then win:Close() end
end

---------------------------------------------------------------------------
-- Options and style presets
---------------------------------------------------------------------------
M.optionParts = M.optionParts or {}
table.insert(M.optionParts, function(options)
	local rows = {
		{ type = "tab", label = L["Log"] },
		{ type = "header", label = L["Rows"] },
		{ type = "toggle", key = "logAlts", label = L["Show alts"], desc = L["List the runs of your other characters too, in gray."] },
		{ type = "toggle", key = "log24h", label = L["Last 24 hours only"], desc = L["Hide runs older than a day."] },
		{ type = "toggle", key = "logLockoutTime", label = L["Time left on the limit"], desc = L["Runs that still count show how long until they stop counting. Off: how long ago you left."] },
		{ type = "select", key = "durationStyle", label = L["Durations"], desc = L["How times are written in the log, tooltips and chat lines."],
			values = { long = L["1 hour 5 minutes"], medium = L["1 hr 5 mins"], short = L["1h 5m"] },
			cog = {
				{ type = "select", key = "clock", label = L["Clock"], desc = L["How clock times are written in the log. Like every EldoUI clock: the clock format on the General page."],
					values = { infobar = L["Like every EldoUI clock"], ["24"] = L["24 hour"], ["12"] = L["12 hour"] } },
			} },
		{ type = "header", label = L["Look"] },
		{ type = "toggle", key = "transparent", label = L["See-through window"], desc = L["The log window lets the game show through a little. How much: General > Panel opacity."] },
		{ type = "header", label = L["Sharing (acts for you)"] },
		{ type = "description", label = L["Off by default. Nothing is ever sent without your click, and gold is never posted."] },
		{ type = "toggle", key = "allowPosting", label = L["Allow posting stats"], desc = L["Adds \"Post to group\" and \"Post to guild\" to the log's right-click menu and lets /eui instances stats party send the newest run. Each post is one click."] },
	}
	for _, row in ipairs(rows) do options[#options + 1] = row end
end)

local QUIET_SHOW = { time = true, kills = true, xp = true, xpPercent = true, xpHour = true, xpKill = false, gold = true, rep = true,
	currency = true, groupLevel = false, runsLevel = true, runsNext = false, honor = true }

local function Show(overrides)
	local show = {}
	for key, value in pairs(QUIET_SHOW) do show[key] = value end
	for key, value in pairs(overrides or {}) do show[key] = value end
	return show
end

-- Content only: positions belong to the layouts, and sharing stays off.
E:RegisterStyles("Instances", {
	{ key = "Compact", title = L["Compact"], desc = L["The datatext and the log; only the slot-free line in chat."],
		settings = { noticeEnter = false, noticeRaid = false, noticePvP = false, noticeFree = true,
			summary = false, allowPosting = false, durationStyle = "short" } },
	{ key = "Leveling", title = L["Leveling"], desc = L["Experience, XP per hour, kills and runs to the next level after each run."],
		settings = { noticeEnter = true, noticeFree = true, summary = true, summaryOnlyActivity = true, allowPosting = false,
			show = Show({ xpKill = true, runsNext = true, gold = false, currency = false }) } },
	{ key = "MaxLevel", title = L["Max level"], desc = L["Gold, reputation and currencies after each run; no experience."],
		settings = { noticeEnter = true, noticeFree = true, summary = true, summaryOnlyActivity = true, allowPosting = false,
			show = Show({ kills = false, xp = false, xpPercent = false, xpHour = false, runsLevel = false }) } },
	{ key = "Booster", title = L["Booster"], desc = L["Kills, gold and group level."],
		settings = { noticeEnter = true, noticeFree = true, summary = true, summaryOnlyActivity = false, allowPosting = false,
			show = Show({ groupLevel = true, xpPercent = false, runsLevel = false }) } },
	{ key = "Quiet", title = L["Quiet"], desc = L["No chat lines at all; everything is in the datatext and the log."],
		settings = { noticeEnter = false, noticeRaid = false, noticePvP = false, noticeFree = false,
			summary = false, allowPosting = false } },
	{ key = "Full", title = L["Full"], desc = L["Every notice and every stat in the summary. Sharing stays off."],
		settings = { noticeEnter = true, noticeRaid = true, noticePvP = true, noticeFree = true,
			summary = true, summaryOnlyActivity = false, allowPosting = false, durationStyle = "long",
			show = Show({ xpKill = true, groupLevel = true, runsNext = true }) } },
})
