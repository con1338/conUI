-- EldoUI Ready Check Report: the panel. A UIKit window on its own
-- mover (EldoUI_ReadyReport, under the ready check box): a toolbar with
-- Refresh and Post to group, the summary line, and one row per member in
-- the chosen layout (grid: buff icons; list: buff names; summary: only the
-- summary lines). Rows show a tooltip with the details; a click does
-- nothing else.
local _, E = ...
local L = E.L
local Kit = E.UIKit
local M = E.ReadyReport

local MOVER = "EldoUI_ReadyReport"
local SIZES = { grid = { 560, 320 }, list = { 520, 300 }, summary = { 420, 150 } }
local POINT = { "TOP", "UIParent", "TOP", 0, -444 }

local function Size()
	return SIZES[M.db.layout] or SIZES.grid
end

local function Hex(color)
	return E:TokenHex(color)
end

local function Good(text) return Hex(Kit.GOOD) .. text .. "|r" end
-- Warnings and problems carry their shape mark too (E:StatusText).
local function Warn(text) return E:StatusText("warn", text) end
local function Bad(text) return E:StatusText("bad", text) end
local function Grey(text) return Hex(Kit.SECONDARY) .. text .. "|r" end

local function Icon(texture, size)
	return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(tostring(texture), size, size)
end

local STATE_TEXT = {
	offline = "offline", dead = "dead", combat = "in combat", restricted = "not readable",
}

local function NameText(row)
	local name = row.name or "?"
	if M.db.classColors and row.class then return E:WrapClassColor(row.class, name) end
	return name
end

local function ReadyText(row)
	if row.ready == "ready" then return Good(L["Ready"]) end
	if row.ready == "notready" then return Bad(L["Not ready"]) end
	if row.ready == "waiting" then return Grey(L["Waiting"]) end
	return ""
end

local function BuffsText(row)
	if row.state ~= "ok" then return Grey(L[STATE_TEXT[row.state] or "not readable"]) end
	if #row.missing == 0 then return Good(L["all"]) end
	local parts = {}
	for _, key in ipairs(row.missing) do
		local buff = M.BuffByKey(key)
		if M.db.layout == "grid" then
			parts[#parts + 1] = Icon(M.BuffIcon(buff), math.max(12, M.db.rowHeight - 4))
		else
			parts[#parts + 1] = L[buff.label]
		end
	end
	return table.concat(parts, M.db.layout == "grid" and " " or ", ")
end

local function FlaskText(row)
	if row.state ~= "ok" then return "" end
	if row.flask then return Good(L["Flask"]) end
	if (row.elixirs or 0) > 0 then return Good(L["%d elixir"]:format(row.elixirs)) end
	return Bad(L["none"])
end

local function FoodText(row)
	if row.state ~= "ok" then return "" end
	if row.food then return Good(L["yes"]) end
	if row.eating then return Grey(L["eating"]) end
	return Bad(L["no"])
end

local function DurabilityText(row)
	if not row.durability then return Grey(L["not shared"]) end
	local text = ("%d%%"):format(row.durability)
	local level = E:DurabilityLevel(row.durability)
	if level == "low" then return Bad(text) end
	if level == "warn" then return Warn(text) end
	return text
end

local function VersionText(row)
	if not row.version then return Grey(row.shared and "" or L["not shared"]) end
	local mine = E.version
	if type(mine) == "string" and E.CompareVersions and E:CompareVersions(row.version, mine) == -1 then
		return Warn(row.version)
	end
	return row.version
end

function M:Columns()
	local checks = self.db.checks
	local columns = {
		{ key = "name", title = L["Name"], value = function(row) return row.name or "" end, text = NameText },
	}
	if checks.ready then
		columns[#columns + 1] = { key = "ready", title = L["Ready"], width = 74,
			value = function(row) return row.ready or "" end, text = ReadyText }
	end
	if checks.buffs then
		columns[#columns + 1] = { key = "buffs", title = L["Missing buffs"], width = self.db.layout == "grid" and 120 or 160,
			value = function(row) return row.state == "ok" and #row.missing or 99 end, text = BuffsText,
			desc = L["Class buffs the member doesn't have. Only buffs a class in your group can give count, unless you changed that in the options."] }
	end
	if checks.flask then
		columns[#columns + 1] = { key = "flask", title = L["Flask"], width = 70,
			value = function(row) return row.flask and 2 or ((row.elixirs or 0) > 0 and 1 or 0) end, text = FlaskText }
	end
	if checks.food then
		columns[#columns + 1] = { key = "food", title = L["Food"], width = 50,
			value = function(row) return row.food and 2 or (row.eating and 1 or 0) end, text = FoodText }
	end
	if checks.durability then
		columns[#columns + 1] = { key = "durability", title = L["Durability"], width = 80, align = "RIGHT",
			value = function(row) return row.durability or 101 end, text = DurabilityText }
	end
	if checks.version then
		columns[#columns + 1] = { key = "version", title = L["Version"], width = 80, align = "RIGHT",
			value = function(row) return row.version or "" end, text = VersionText }
	end
	-- Columns other parts of EldoUI add (M:AddColumn).
	for _, column in ipairs(M.extraColumns) do
		if not column.shown or column.shown() then columns[#columns + 1] = column end
	end
	return columns
end

local function RowTooltip(row)
	GameTooltip:AddLine(NameText(row))
	if row.state ~= "ok" then
		local why = {
			offline = L["Offline."],
			dead = L["Dead or a ghost."],
			combat = L["Buffs are read out of combat only."],
			restricted = L["The game does not let addons read this member's buffs right now."],
		}
		GameTooltip:AddLine(why[row.state] or why.restricted, Kit.SECONDARY[1], Kit.SECONDARY[2], Kit.SECONDARY[3], true)
	else
		for _, key in ipairs(row.missing) do
			local buff = M.BuffByKey(key)
			GameTooltip:AddLine(L["Missing: %s"]:format(L[buff.label]), unpack(Kit.WARN))
		end
		if #row.missing == 0 then GameTooltip:AddLine(L["Every checked buff is up."], unpack(Kit.GOOD)) end
	end
	if not row.shared then
		GameTooltip:AddLine(L["Durability and version show for members who turn on sharing in their own EldoUI."], Kit.SECONDARY[1], Kit.SECONDARY[2], Kit.SECONDARY[3], true)
	end
end

local function BuildTable(frame)
	if frame.tbl then
		frame.tbl:Hide()
		frame.tbl:SetParent(nil)
		frame.tbl = nil
	end
	local tbl = Kit.CreateTable(frame, M:Columns(), {
		sortKey = "name", rowHeight = M.db.rowHeight,
		empty = { L["Nobody to check"], L["Join a group, or start a ready check, to see who is missing what."] },
		createRow = function(row)
			row:HookScript("OnEnter", function(own)
				if not own.item then return end
				GameTooltip:SetOwner(own, "ANCHOR_RIGHT")
				RowTooltip(own.item)
				GameTooltip:Show()
			end)
			row:HookScript("OnLeave", GameTooltip_Hide)
		end,
	})
	tbl:SetPoint("TOPLEFT", frame.summaryArea, "BOTTOMLEFT", 0, -6)
	tbl:SetPoint("BOTTOMRIGHT")
	frame.tbl = tbl
	frame.tableKey = M:LookKey()
end

function M:LookKey()
	local checks = self.db.checks
	local key = { self.db.layout, self.db.rowHeight }
	for _, name in ipairs({ "ready", "buffs", "flask", "food", "durability", "version" }) do
		key[#key + 1] = checks[name] and "1" or "0"
	end
	return table.concat(key, ":")
end

local function FitSummary(frame)
	if not frame.summary or frame.fittingSummary then return end
	frame.fittingSummary = true
	local area = frame.summaryArea
	-- Update the child width before measuring wrapped text. The report's
	-- summary remains scrollable inside the content, including when its table
	-- is hidden, so a long report never paints across the footer.
	area:Update()
	E:SetWindowFont(frame.summary, E.tokens.size.body)
	local height = math.max(math.ceil(frame.summary:GetStringHeight() or 14), 14)
	frame.summary:SetHeight(height)
	area.child:SetHeight(height)
	local available = math.max(1, (frame:GetHeight() or 0) - (frame.toolbar:GetHeight() or 0) - 8)
	local view = available
	if M.db.layout ~= "summary" then
		-- Leave at least half the small window for the table, and up to two
		-- ordinary rows on larger windows. Overflow stays in the summary scroll.
		local rows = math.min(available * 0.5, math.max(42, M.db.rowHeight * 2))
		view = math.min(height, math.max(1, available - rows - 6))
	end
	area:SetHeight(view)
	area:Update()
	frame.fittingSummary = nil
end

-- The share of the ready check still left, 0 to 1, or nil when no check
-- runs or the game gives no time.
function M.TimerValue()
	if not M.checking or not M.checkLength then return nil end
	local left = type(GetReadyCheckTimeLeft) == "function" and E.PlainCallAll(GetReadyCheckTimeLeft) or nil
	if type(left) ~= "number" then return nil end
	return math.max(0, math.min(1, left / M.checkLength))
end

function M.UpdateTimer(bar)
	local value = M.TimerValue()
	if not value then bar:Hide() return end
	bar:SetValue(value)
end

local function CreateTab(content)
	local frame = CreateFrame("Frame", nil, content)
	frame:SetAllPoints()
	frame.toolbar = CreateFrame("Frame", nil, frame)
	frame.toolbar:SetPoint("TOPLEFT")
	frame.toolbar:SetPoint("TOPRIGHT")
	frame.toolbar:SetHeight(E.tokens.height.button)
	frame.refresh = Kit.Button(frame.toolbar, L["Refresh"], 80, nil, function() M:Refresh() end,
		L["Refresh"], L["Read the group's buffs again (out of combat only)."])
	frame.refresh:SetPoint("LEFT", 0, 0)
	frame.post = Kit.Button(frame.toolbar, L["Post to group"], 110, nil, function() M:Post() end,
		L["Post to group"], L["Send the summary line to your party or raid chat. One click, one message."])
	frame.post:SetPoint("LEFT", frame.refresh, "RIGHT", 6, 0)
	frame.share = Kit.Button(frame.toolbar, L["Share mine"], 96, nil, function() M:SendShare() end,
		L["Share mine"], L["Send your lowest durability and your EldoUI version to the group, once per ready check, so their report can show it."])
	frame.share:SetPoint("LEFT", frame.post, "RIGHT", 6, 0)
	frame.status = Kit.Text(frame.toolbar, E.tokens.size.small, "RIGHT", "secondary")
	frame.status:SetPoint("LEFT", frame.share, "RIGHT", 8, 0)
	frame.status:SetPoint("RIGHT", -4, 0)
	-- A thin bar in the gap under the toolbar: the time left to answer the
	-- ready check. It shows only while a check runs.
	frame.timer = CreateFrame("StatusBar", nil, frame)
	frame.timer:SetPoint("TOPLEFT", frame.toolbar, "BOTTOMLEFT", 2, -3)
	frame.timer:SetPoint("TOPRIGHT", frame.toolbar, "BOTTOMRIGHT", -2, -3)
	frame.timer:SetHeight(3)
	E:UseBarTexture(frame.timer)
	frame.timer:SetStatusBarColor(E:TokenColor("accent", 0.85))
	frame.timer:SetMinMaxValues(0, 1)
	frame.timer:Hide()
	frame.timer:SetScript("OnUpdate", function(bar) M.UpdateTimer(bar) end)
	frame.summaryArea = Kit.ScrollArea(frame)
	frame.summaryArea:SetPoint("TOPLEFT", frame.toolbar, "BOTTOMLEFT", 2, -8)
	frame.summaryArea:SetPoint("TOPRIGHT", frame.toolbar, "BOTTOMRIGHT", -2, -8)
	frame.summaryArea:SetHeight(14)
	frame.summary = Kit.Text(frame.summaryArea.child, E.tokens.size.body, "LEFT")
	frame.summary:SetPoint("TOPLEFT")
	frame.summary:SetPoint("TOPRIGHT")
	frame.summary:SetWordWrap(true)
	frame.summary:SetJustifyV("TOP")
	-- The summary is the only copy of the line (the footer stays free), so it
	-- wraps; measure it again once the window has its width.
	frame:SetScript("OnSizeChanged", function(own) FitSummary(own) end)
	frame.summaryArea.child:HookScript("OnSizeChanged", function() FitSummary(frame) end)
	return frame
end

local function UpdateTab(frame)
	local rows, order, line, unknown = M.rows or {}, M.summaryOrder or {}, M.summaryLine or "", M.unknown or 0
	local previous = frame.summary:GetText()
	local timeLeft = M.TimerValue()
	if timeLeft then frame.timer:SetValue(timeLeft) end
	frame.timer:SetShown(timeLeft ~= nil)
	frame.post:SetShown(M.db.postButton)
	frame.post:SetEnabled(#rows > 1 and not InCombatLockdown())
	frame.share:SetShown(M.db.share)
	frame.share:ClearAllPoints()
	frame.share:SetPoint("LEFT", M.db.postButton and frame.post or frame.refresh, "RIGHT", 6, 0)
	frame.share:SetEnabled(IsInGroup() and not M.sharedThisCheck and not InCombatLockdown())
	if M.db.layout == "summary" then
		local lines = {}
		for _, item in ipairs(order) do lines[#lines + 1] = "· " .. item.line end
		if #lines == 0 then lines[1] = line end
		if unknown > 0 then lines[#lines + 1] = Grey(E:Plural(unknown, "%d member could not be read.", "%d members could not be read."):format(unknown)) end
		frame.summary:SetText(table.concat(lines, "\n"))
		if frame.tbl then frame.tbl:Hide() end
	else
		frame.summary:SetText(line)
		if not frame.tbl or frame.tableKey ~= M:LookKey() then BuildTable(frame) end
		frame.tbl:Show()
		frame.tbl:SetData(rows)
	end
	FitSummary(frame)
	if previous ~= frame.summary:GetText() then frame.summaryArea:ScrollToTop() end
	local ready, total = 0, #rows
	for _, row in ipairs(rows) do if row.ready == "ready" then ready = ready + 1 end end
	frame.status:SetText(M.checking and L["Ready check: %d of %d ready"]:format(ready, total) or E:Plural(total, "%d member", "%d members"):format(total))
end

function M:BuildWindow()
	if self.window then return self.window end
	local size = Size()
	local win = Kit.CreateTabbedWindow({
		name = "EldoUI_ReadyReportWindow",
		options = { page = "module:ReadyReport" },
		title = L["Ready Check Report"],
		width = size[1], height = size[2],
		transparent = function() return M.db.transparent end,
		-- A report belongs to its ready check: after the pull it is stale.
		backAfterCombat = false,
		tabs = {
			{ key = "report", title = L["Group"], desc = L["What each member is missing."],
				create = CreateTab, show = UpdateTab, refresh = UpdateTab },
		},
		help = { text = L["Opens when a ready check starts (see the options). Buffs are read from the game out of combat; durability and version show for members who share them in their own EldoUI. Clicking a row does nothing; Post to group sends one summary line, and Share mine sends your own durability and version once."] },
	})
	self.window = win
	-- The window sits on its mover; dragging the top bar moves the mover.
	function win.ApplyPosition(own)
		local frame = own.frame
		if not frame then return end
		if not own.mover then own.mover = E:CreateMover(frame, MOVER, L["Ready Check Report"], POINT, { sample = false }) end
		frame:SetScale(own:Scale())
		frame:ClearAllPoints()
		frame:SetPoint("TOP", own.mover, "TOP")
	end
	function win.SavePosition(own)
		local frame, mover = own.frame, own.mover
		if not (frame and mover) then return end
		local left, top = frame:GetLeft(), frame:GetTop()
		if not (left and top) then return end
		local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
		E:SaveMoverFromRect(mover, left * scale, top * scale - mover:GetHeight())
	end
	function win.ResetPosition(own)
		E.db.movers[MOVER] = nil
		E:ApplyMover(MOVER)
		own:ResetSize()
		own:ApplyPosition()
	end
	win:Build()
	self:ApplyLook()
	return win
end

function M:ApplyLook()
	local win = self.window
	if not (win and win.frame) then return end
	local size = Size()
	win.opts.width, win.opts.height = size[1], size[2]
	win.frame:SetSize(size[1], size[2])
	if win.mover then win.mover:SetSize(size[1], size[2]) end
	win:Restyle()
	if win:IsOpen() then self:Refresh() end
end

function M:IsOpen()
	return self.window ~= nil and self.window:IsOpen()
end

-- Read the group again and redraw (out of combat only).
function M:Refresh()
	if InCombatLockdown() then return false end
	local rows, order, line, unknown = self:Collect()
	self.rows, self.summaryOrder, self.summaryLine, self.unknown = rows, order, line, unknown
	if self.window then self.window:Refresh() end
	return true
end

function M:Open()
	if not self.active or InCombatLockdown() then return false end
	local win = self:BuildWindow()
	self:Refresh()
	local opened = win:Open("report")
	-- Aura changes are heard only while the report shows them.
	if win.frame and not win.auraHooked then
		win.auraHooked = true
		win.frame:HookScript("OnHide", function() M:SyncAuraUnits() end)
	end
	self:SyncAuraUnits()
	return opened
end

function M:Close()
	if self.window then self.window:Close() end
end

function M:Toggle()
	if self:IsOpen() then self:Close() else self:Open() end
end

function M:Toast(text, warn)
	local win = self.window
	if win and win.frame and win.frame:IsShown() then
		Kit.Toast(win.frame, text, { anchor = win.frame.footer, warn = warn })
	elseif warn then
		M:PushAlert({ title = L["Ready Check Report"], text = text, key = "readyreport" })
	end
end
