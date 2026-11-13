-- Rare Alerts: the Rare History window. A small panel beside the alert
-- cards that lists this session's sightings, newest first.
--
--   +--------------------------------------+
--   | Rare History  3            [^]  [x]  |  title, count, collapse, clear
--   |--------------------------------------|
--   | Lord Kazzak                   2 min  |  name, how long ago
--   | Rare elite · Blasted Lands           |  rank or kind, zone
--   | Glinting Chest        Already done   |
--   | Treasure · Elwynn Forest             |
--   +--------------------------------------+
--
-- Click a line to set a waypoint, Shift-click to share it (the chat box
-- opens on the share channel; the player presses Enter), right-click to
-- remove it. Clear empties the list (it asks first when more than three
-- lines would go).
--
-- Rules: the list is the session list Core.lua already keeps; nothing about
-- rares is saved. The window is a plain frame (nothing secure), so it may
-- show, hide and fade in combat; the shared visibility rules drive its
-- alpha (out of combat by default). Nothing here targets.
local _, E = ...
local L = E.L
local M = E.RareScanner
local UI = E.UIKit

local WIDTH = 210
local HEADER = 24
local ROW = 30
local ROWS = 5
local PAD = 6
local TICK = 15 -- seconds between "how long ago" refreshes while shown
local OPTIONS_LINK = { page = "module:RareScanner" } -- Ctrl-click opens the settings
M.HISTORY_MOVER = "EldoUI_RareHistory"
-- Beside the alert cards: its top left corner at their top right, so it
-- follows the alert spot of every layout.
M.HISTORY_POINT = { "TOPLEFT", "EldoUI_RareAlertMover", "TOPRIGHT", 6, 0 }
-- The window follows its own visibility block (General > Visibility lists it).
E:RegisterVisibilityFacet(M.HISTORY_MOVER, "rules", { module = "RareScanner", setting = "historyVisibility" })

local function Ago(seconds)
	if seconds < 60 then return L["now"] end
	if seconds < 3600 then return L["%d min"]:format(math.floor(seconds / 60)) end
	return L["%d h"]:format(math.floor(seconds / 3600))
end
M.HistoryAgo = Ago

-- "Rare elite · Blasted Lands", "Treasure · Elwynn Forest".
function M:HistoryKindText(entry)
	local label
	if entry.kind == "treasure" or entry.kind == "event" then
		label = M.KIND_LABEL[entry.kind]
	else
		label = M.CLASS_LABEL[entry.classification] or "Rare"
	end
	local parts = { L[label] }
	if type(entry.zone) == "string" and entry.zone ~= "" then parts[#parts + 1] = entry.zone end
	return table.concat(parts, " · ")
end

---------------------------------------------------------------------------
-- Session list edits
---------------------------------------------------------------------------
function M:RemoveFromSession(key)
	local entry = key and self.session[key]
	if not entry then return false end
	self.session[key] = nil
	for index, item in ipairs(self.sessionList) do
		if item == entry then table.remove(self.sessionList, index) break end
	end
	if self.RefreshDataText then self:RefreshDataText() end
	self:RefreshHistory()
	return true
end

function M:ClearHistory()
	local count = #self.sessionList
	if count == 0 then return end
	if count <= 3 then
		self:ClearSession()
		return
	end
	E:ShowConfirm({ title = L["Clear Rare History"], text = E:Plural(count, "Remove the %d line from the Rare History?", "Remove all %d lines from the Rare History?"):format(count),
		accept = L["Clear"], danger = true, onAccept = function() M:ClearSession() end })
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function RowTooltip(row)
	local entry = row.item
	if not entry then return end
	UI.AnchorTooltip(row)
	UI.TipTitle(GameTooltip, entry.name)
	local secondary = E.tokens.text.secondary
	GameTooltip:AddLine(M:HistoryKindText(entry), secondary[1], secondary[2], secondary[3], true)
	local coords = M.Coords and M.Coords(entry.x, entry.y)
	if coords then GameTooltip:AddLine(coords, secondary[1], secondary[2], secondary[3]) end
	GameTooltip:AddLine(L["Seen %s ago"]:format(Ago(GetTime() - (entry.t or GetTime()))), secondary[1], secondary[2], secondary[3])
	if entry.dead then GameTooltip:AddLine(L["Dead"], unpack(E.tokens.text.bad)) end
	if entry.done then GameTooltip:AddLine(L["Already done"], unpack(E.tokens.text.good)) end
	local where = type(entry.x) == "number" and type(entry.uiMapID) == "number"
	UI.TooltipHint(GameTooltip,
		(where or entry.npc) and { L["Click"], where and L["set a waypoint"] or L["show its camps on your map"] } or nil,
		{ L["Shift-click"], L["share in chat"] },
		{ L["Right-click"], L["remove it from the list"] })
	GameTooltip:Show()
end

local function RowClick(row, button)
	local entry = row.item
	if not entry or E:IsOptionsLinkClick(row, button) then return end
	if button == "RightButton" then
		M:RemoveFromSession(entry.key)
	elseif IsShiftKeyDown() then
		M:Share(entry)
	else
		M:ShowOnMap(entry)
	end
end

local function CreateRow(row)
	row:EnableMouse(true)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	row.name = UI.Text(row, E.tokens.size.body, "LEFT")
	row.name:SetWordWrap(false)
	row.ago = UI.Text(row, E.tokens.size.small, "RIGHT", "secondary")
	row.sub = UI.Text(row, E.tokens.size.small, "LEFT", "secondary")
	row.sub:SetWordWrap(false)
	row.ago:SetPoint("TOPRIGHT", row, "TOPRIGHT", -PAD, -3)
	row.name:SetPoint("TOPLEFT", row, "TOPLEFT", PAD, -3)
	row.name:SetPoint("TOPRIGHT", row.ago, "TOPLEFT", -4, 0)
	row.sub:SetPoint("TOPLEFT", row, "TOPLEFT", PAD, -17)
	row.sub:SetPoint("TOPRIGHT", row, "TOPRIGHT", -PAD, -17)
	row:SetScript("OnEnter", RowTooltip)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:SetScript("OnClick", RowClick)
	E:BindOptionsLink(row, OPTIONS_LINK)
end

local function UpdateRow(row, entry)
	row.name:SetText(entry.name or "")
	local faded = entry.dead or entry.done
	row.name:SetTextColor(unpack(faded and E.tokens.text.secondary or E.tokens.text.body))
	local now = GetTime()
	local ago, color = Ago(now - (entry.t or now)), E.tokens.text.secondary
	if entry.dead then
		ago = L["Dead"]
	elseif entry.done then
		ago, color = L["Already done"], E.tokens.text.good
	end
	row.ago:SetText(ago)
	row.ago:SetTextColor(unpack(color))
	row.sub:SetText(M:HistoryKindText(entry))
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function InMoveMode() return E.IsMoveMode and E:IsMoveMode() end

function M:HistoryHeight()
	if self.db.historyCollapsed then return HEADER end
	return HEADER + ROWS * ROW + PAD
end

function M:BuildHistory()
	if self.history then return self.history end
	local frame = CreateFrame("Frame", M.HISTORY_MOVER, UIParent)
	frame:SetSize(WIDTH, self:HistoryHeight())
	frame:SetFrameStrata("LOW")
	frame:SetClampedToScreen(true)
	E:SetPanelTemplate(frame, true)

	frame.header = CreateFrame("Button", nil, frame)
	frame.header:SetPoint("TOPLEFT")
	frame.header:SetPoint("TOPRIGHT")
	frame.header:SetHeight(HEADER)
	frame.header:SetScript("OnClick", function(header, button)
		if not E:IsOptionsLinkClick(header, button) then M:ToggleHistoryCollapsed() end
	end)
	E:BindOptionsLink(frame.header, OPTIONS_LINK)
	frame.title = UI.Text(frame.header, E.tokens.size.section, "LEFT", "header")
	frame.title:SetPoint("LEFT", PAD + 2, 0)
	frame.title:SetText(L["Rare History"])
	frame.count = UI.Text(frame.header, E.tokens.size.small, "LEFT", "secondary")
	frame.count:SetPoint("LEFT", frame.title, "RIGHT", 6, 0)
	frame.clear = UI.IconButton(frame.header, 18, "cross", function() M:ClearHistory() end,
		L["Clear"], L["Remove every line. Nothing is kept after you log out anyway."], nil, { danger = true })
	frame.clear:SetPoint("RIGHT", -PAD, 0)
	frame.fold = UI.IconButton(frame.header, 18, "chevron-up", function() M:ToggleHistoryCollapsed() end,
		L["Collapse"], L["Show only the title, or the list again."])
	frame.fold:SetPoint("RIGHT", frame.clear, "LEFT", -2, 0)

	frame.line = UI.Divider(frame)
	frame.line:SetPoint("TOPLEFT", 1, -HEADER)
	frame.line:SetPoint("TOPRIGHT", -1, -HEADER)

	frame.list = UI.CreateList(frame, {
		rowHeight = ROW,
		create = CreateRow,
		update = UpdateRow,
		empty = { L["No sightings yet"], L["Rares, treasures and events you see show up here until you log out."] },
	})
	frame.list:SetPoint("TOPLEFT", 0, -HEADER - 1)
	frame.list:SetPoint("BOTTOMRIGHT", 0, PAD / 2)

	-- "How long ago" ticks while the window is up.
	frame.elapsed = 0
	frame:SetScript("OnUpdate", function(window, elapsed)
		window.elapsed = window.elapsed + elapsed
		if window.elapsed < TICK then return end
		window.elapsed = 0
		if window.list:IsShown() then window.list:Refresh() end
	end)

	frame:Hide()
	self.history = frame
	E:CreateMover(frame, M.HISTORY_MOVER, "Rare History", M.HISTORY_POINT, { followShown = true })
	E:RegisterHideable(frame.header, M.HISTORY_MOVER, { mouse = true })
	return frame
end

function M:HistoryWanted()
	return self.active and self.db.historyWindow and true or false
end

function M:ToggleHistoryCollapsed()
	self.db.historyCollapsed = not self.db.historyCollapsed
	self:ApplyHistory()
end

function M:ApplyHistory()
	if not self:HistoryWanted() then
		local frame = self.history
		if frame then
			if E:IsVisibilityAttached(frame) then E:DetachVisibility(frame) end
			frame:Hide()
		end
		return
	end
	local frame = self:BuildHistory()
	local collapsed = self.db.historyCollapsed and true or false
	frame:SetHeight(self:HistoryHeight())
	frame.line:SetShown(not collapsed)
	frame.list:SetShown(not collapsed)
	UI.SetGlyph(frame.fold.icon, collapsed and "chevron-down" or "chevron-up")
	if type(self.db.historyVisibility) ~= "table" then
		self.db.historyVisibility = E:VisibilityDefaults({ show = "nocombat" })
	end
	frame:Show()
	E:AttachVisibility(frame, self.db.historyVisibility, { forceShow = InMoveMode, exempt = true })
	self:RefreshHistory()
end

function M:RefreshHistory()
	local frame = self.history
	if not (frame and frame:IsShown()) then return end
	local count = #self.sessionList
	frame.count:SetText(count > 0 and tostring(count) or "")
	frame.clear:SetEnabled(count > 0)
	frame.elapsed = 0
	if frame.list:IsShown() then frame.list:SetData(self.sessionList) end
end
