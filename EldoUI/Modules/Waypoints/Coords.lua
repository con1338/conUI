-- EldoUI Waypoints: the coordinate box and the coordinate entry.
--
-- The coordinate box is a small movable box with your own map coordinates
-- (from C_Map.GetPlayerMapPosition, like the arrow). Where the game hides
-- your position it shows a dash, and with "Hide in instances" it hides in
-- dungeons, raids and battlegrounds. A click on it opens the entry: one line
-- where you type "45.2 63.8 Inn" or "Elwynn Forest 41 65" (the same text as
-- /way) and Enter adds the waypoint. Nothing here acts for the player.
local _, E = ...
local L = E.L
local M = E.Waypoints

local WIDTH, HEIGHT = 120, 22
local ENTRY_WIDTH = 260
local UPDATE_STEP = 0.2
local COORDS_TICK = "Waypoints:coords"

---------------------------------------------------------------------------
-- Coordinate box
---------------------------------------------------------------------------
-- The box text for your position now, or a dash where the game hides it.
-- shared: the read the tickers share this frame.
function M:CoordsText(shared)
	local _, x, y
	if shared then _, x, y = M.SharedPlayerPos() else _, x, y = M.PlayerPos() end
	if not x then return "--", false end
	return M.FormatCoords(x, y), true
end

-- fromTick: the shared ticker, which leaves the box alone while the text
-- stays the same.
function M:UpdateCoords(fromTick)
	local frame = self.coordFrame
	if not frame then return end
	local text, known = self:CoordsText(fromTick)
	if fromTick and frame.shownText == text and frame.shownKnown == known then return end
	frame.shownText, frame.shownKnown = text, known
	frame.text:SetText(text)
	if known then
		frame.text:SetTextColor(M.Shade("TEXT"))
	else
		frame.text:SetTextColor(M.Shade("DIM"))
	end
end

function M:CoordsTooltip(owner)
	local r, g, b = M.Shade("SECONDARY")
	GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
	local mapID, x, y = M.PlayerPos()
	E.UIKit.TipTitle(GameTooltip, mapID and M.MapName(mapID) or L["No position here"])
	if x then GameTooltip:AddLine(M.FormatCoords(x, y), r, g, b) end
	GameTooltip:AddLine(" ")
	E.UIKit.TipText(GameTooltip, L["Move it in move mode (Waypoint Coordinates)."])
	E:TooltipHint(GameTooltip, { L["Click"], L["type coordinates to add a waypoint"] }, { L["Right-click"], L["options"] })
	GameTooltip:Show()
end

-- A waypoint where you stand (your own position, from the game).
function M:AddHere()
	local mapID, x, y = M.PlayerPos()
	if not mapID then
		E:Print(L["The game doesn't give your position here."])
		return nil
	end
	return self:Add(mapID, x, y)
end

function M:CoordsMenu(owner)
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(L["Coordinates"])
		root:CreateButton(L["Type coordinates"], function() M:ShowEntry(owner) end)
		root:CreateButton(L["Waypoint where I stand"], function() M:AddHere() end)
		root:CreateButton(L["Waypoint list"], function() M:ShowList() end)
		root:CreateButton(L["Paste waypoints"], function() M:ShowPaste() end)
		-- Opens move mode with this box selected, whatever the view.
		root:CreateButton(L["Move"], function() E:MoveFrame("EldoUI_WaypointCoords") end)
		E:AddHideEntries(root, "EldoUI_WaypointCoords")
	end)
end

function M:BuildCoords()
	if self.coordFrame then return end
	-- The holder carries the mover and is shown while the option is on; the
	-- box inside also hides where the game hides your position.
	local holder = CreateFrame("Frame", "EldoUI_WaypointCoordsHolder", UIParent)
	holder:SetSize(WIDTH, HEIGHT)
	holder:Hide()
	self.coordHolder = holder

	local frame = CreateFrame("Button", "EldoUI_WaypointCoords", holder)
	frame:SetAllPoints(holder)
	frame:SetFrameStrata("MEDIUM")
	frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	E:SetTemplate(frame)
	frame.text = E:CreateText(frame, E.tokens.size.label)
	frame.text:SetPoint("CENTER")
	frame:SetScript("OnClick", function(f, button)
		if E:IsOptionsLinkClick(f, button) then return end
		if button == "RightButton" then M:CoordsMenu(f) else M:ShowEntry(f) end
	end)
	frame:SetScript("OnEnter", function(f) M:CoordsTooltip(f) end)
	frame:SetScript("OnLeave", GameTooltip_Hide)
	E:BindOptionsLink(frame, { page = "module:Waypoints", key = "coordBox" })
	self.coordFrame = frame

	-- combat: the box is part of the main screen (every layout places it),
	-- so move mode shows it in the view it opens in, Combat mode; without it
	-- the box was only in "All frames" and seemed stuck.
	E:CreateMover(holder, "EldoUI_WaypointCoords", L["Waypoint Coordinates"], { "TOP", "UIParent", "TOP", 0, -210 },
		{ enabledPath = { "coordBox" }, followShown = true, combat = true })
	-- Its right-click Hide is the module's own coordinate box switch.
	E:SetHideableSetting("EldoUI_WaypointCoords", function() return not M.db.coordBox end,
		function(hidden) M.db.coordBox = not hidden M:UpdateCoordsShown() end)
end

function M:UpdateCoordsShown()
	local holder, frame = self.coordHolder, self.coordFrame
	if not holder then return end
	local on = self.active and self.db.coordBox and true or false
	holder:SetShown(on)
	local shown = on and not self:HiddenHere()
	frame:SetShown(shown)
	if on then self:UpdateCoords() end
	-- The coordinates update on the shared ticker while the box shows.
	if shown then
		if not E.Ticker:IsSubscribed(COORDS_TICK) then
			E.Ticker:Subscribe(COORDS_TICK, UPDATE_STEP, function()
				if frame:IsVisible() then M:UpdateCoords(true) end
			end, M)
		end
	else
		E.Ticker:Unsubscribe(COORDS_TICK)
	end
end

---------------------------------------------------------------------------
-- Coordinate entry: type a /way line, Enter adds it
---------------------------------------------------------------------------
-- Adds the waypoint a typed line names. Returns its uid, or nil and the
-- reason to show under the box.
function M:SubmitEntry(text)
	text = strtrim((tostring(text or ""):gsub("^%s*/%a*way%s*", "")))
	if text == "" then return nil, L["Type coordinates, like 45.2 63.8 or Elwynn Forest 41 65 Inn."] end
	local mapID, x, y, title = self:Parse(text)
	if not mapID then return nil, x end
	local uid = self:Add(mapID, x, y, { title = title })
	if not uid then return nil, L["Coordinates go from 0 to 100."] end
	return uid
end

-- The kit's dialog shell with one edit line: header-font title, accent
-- line, Escape closes it. The line under the title says what to type, or
-- why a typed line didn't work.
local function BuildEntry()
	local Kit = E.UIKit
	local frame = Kit.CreateDialog("EldoUI_WaypointEntry", { width = ENTRY_WIDTH + 2 * Kit.DIALOG_PAD, strata = "DIALOG",
		title = L["Add a waypoint"], edit = {} })
	local box = frame.edit
	frame.box = box
	frame.hint = frame.text

	function frame:ShowHint(text, bad)
		self:SetText(text)
		Kit.Paint(self.hint, bad and "bad" or "secondary")
	end

	local function Submit()
		local uid, err = M:SubmitEntry(box:GetText())
		if uid then
			box:SetText("")
			frame:Hide()
		else
			frame:ShowHint(err, true)
			box:SetFocus()
		end
	end
	box:SetScript("OnEnterPressed", Submit)
	box:SetScript("OnEscapePressed", function() frame:Hide() end)
	box:HookScript("OnTextChanged", function(_, userInput)
		if userInput then frame:ShowHint(L["x y [title], or zone x y [title]. Enter adds, Esc closes."]) end
	end)
	frame:SetButtons({
		{ L["Add"], keepOpen = true, kind = "primary", onClick = Submit },
		{ E:GameText(CANCEL, L["Cancel"]) },
	})
	frame:HookScript("OnHide", function() box:ClearFocus() end)
	return frame
end

-- Opens the entry under `owner` (the coordinate box or the arrow), or at the
-- top of the screen.
function M:ShowEntry(owner)
	if not self.active then return end
	local frame = self.entryFrame
	if not frame then
		frame = BuildEntry()
		self.entryFrame = frame
	end
	if not (owner and owner.IsShown and owner:IsShown()) then
		owner = self.coordFrame and self.coordFrame:IsShown() and self.coordFrame or nil
	end
	frame:ClearAllPoints()
	if owner then
		frame:SetPoint("TOP", owner, "BOTTOM", 0, -4)
	else
		frame:SetPoint("TOP", UIParent, "TOP", 0, -160)
	end
	frame:ShowHint(L["x y [title], or zone x y [title]. Enter adds, Esc closes."])
	frame:Show()
	frame.box:SetFocus()
end
