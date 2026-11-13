-- EldoUI Dungeon Routes: the route card ("compact mode").
--
--   +------------------------------+
--   | The Deadmines          3/24  |
--   |  3  Pull with LoS            |
--   |  4  Patrol                   |
--   |  5  Boss: Rhahk'Zor          |
--   | [Back]               [Done]  |
--   +------------------------------+
--
-- A small card with the next pulls of the picked route, on its own mover
-- (EldoUI_RouteCard, /eui move). Off by default ("Route card"). It shows
-- inside a dungeon that has a route, and outside too with "Also outside
-- dungeons" (the dungeon you were in last). Done ticks the next pull off,
-- Back takes one back; the next pull is lit on every dungeon map and the
-- pulls done are dimmed in the window's list. The count is kept per dungeon
-- and starts again when you enter the dungeon after two hours or pick
-- another route. Right-click: start again, open the Dungeons window.
-- The card only shows what you ticked: it never reads where you are or
-- what you killed.
local _, E = ...
local L = E.L
local M = E.DungeonRoutes
local Kit = E.UIKit

local NAME = "EldoUI_RouteCard"
local WIDTH = 230
local ROW_H = 18
local PAD = 8
local HEAD_H = 20
local FOOT_H = 26
local FRESH = 2 * 60 * 60     -- a run older than this starts again on entering
M.CARD_DEFAULT_POINT = { "TOPLEFT", "UIParent", "TOP", 310, -300 }

local card, mover
local sampleShown = false

---------------------------------------------------------------------------
-- Progress (per dungeon, account-wide like the routes)
---------------------------------------------------------------------------
local function Progress()
	local store = M:Store()
	if type(store.progress) ~= "table" then store.progress = {} end
	return store.progress
end

local function RouteTag(route)
	if not route then return nil end
	return route.id or "shipped"
end

-- How many pulls of the dungeon's picked route are ticked off.
function M:DoneCount(key)
	local entry = key and Progress()[key]
	local route = key and self:ActiveRoute(key)
	if type(entry) ~= "table" or not route or entry.route ~= RouteTag(route) then return 0 end
	return math.max(0, math.min(tonumber(entry.done) or 0, #route.pulls))
end

function M:SetDoneCount(key, count)
	local route = key and self:ActiveRoute(key)
	if not route then return false end
	count = math.max(0, math.min(tonumber(count) or 0, #route.pulls))
	Progress()[key] = { route = RouteTag(route), done = count, at = time and time() or 0 }
	self:Changed("progress")
	return true
end

function M:PullDone(key, index)
	return self.db.card and index <= self:DoneCount(key)
end

-- The next pull to take (the overlay lights it), or nil.
function M:NextPullIndex(key)
	if not (self.active and self.db.card) then return nil end
	local route = key and self:ActiveRoute(key)
	local done = self:DoneCount(key)
	if not route or done <= 0 or done >= #route.pulls then return nil end
	return done + 1
end

function M:TickPull(key, step)
	key = key or self:CardKey()
	if not key then return false end
	local before = self:DoneCount(key)
	return self:SetDoneCount(key, before + (step or 1)) and self:DoneCount(key) ~= before
end

---------------------------------------------------------------------------
-- The card
---------------------------------------------------------------------------
-- The dungeon the card shows: the one you are in, else (with "Also
-- outside dungeons") the last one, else nil.
function M:CardKey()
	if not (self.active and self.db.card) then return nil end
	local here = self:CurrentDungeon()
	if here then return here end
	if self.db.cardOutside then
		local last = self:Store().cardLast
		if type(last) == "string" and self:DungeonInfo(last) then return last end
	end
end

local function Rows()
	return math.max(1, math.min(4, tonumber(M.db.cardPulls) or 3))
end

local function CardMenu(owner)
	local key = M:CardKey()
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(L["Route Card"])
		if key then
			root:CreateButton(L["Start the route again"], function() M:SetDoneCount(key, 0) end)
			root:CreateButton(L["Open the Dungeons window"], function()
				if not InCombatLockdown() then M:OpenBrowser(key) end
			end)
		end
		E:AddHideEntries(root, NAME)
	end)
end

local function Build()
	if card then return card end
	card = CreateFrame("Frame", NAME, UIParent)
	card:SetSize(WIDTH, 100)
	card:SetFrameStrata("MEDIUM")
	card:SetClampedToScreen(true)
	card:EnableMouse(true)
	card:Hide()
	E:SetPanelTemplate(card, true)
	card.title = Kit.Text(card, 12, "LEFT", "header")
	card.title:SetPoint("TOPLEFT", PAD, -PAD)
	card.title:SetPoint("TOPRIGHT", -52, -PAD)
	card.title:SetWordWrap(false)
	card.count = Kit.Text(card, 11, "RIGHT", "secondary")
	card.count:SetPoint("TOPRIGHT", -PAD, -PAD - 1)
	card.rows = {}
	for index = 1, 4 do
		local row = CreateFrame("Button", nil, card)
		row:SetHeight(ROW_H)
		row:SetPoint("TOPLEFT", PAD - 2, -(PAD + HEAD_H + (index - 1) * ROW_H))
		row:SetPoint("TOPRIGHT", -PAD, -(PAD + HEAD_H + (index - 1) * ROW_H))
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		E:SkinRow(row)
		row.number = Kit.Text(row, 12, "RIGHT")
		row.number:SetPoint("LEFT", 0, 0)
		row.number:SetWidth(22)
		row.text = Kit.Text(row, 12, "LEFT")
		row.text:SetPoint("LEFT", row.number, "RIGHT", 6, 0)
		row.text:SetPoint("RIGHT", 0, 0)
		row.text:SetWordWrap(false)
		row:SetScript("OnClick", function(self, button)
			if E:IsOptionsLinkClick(self, button) then return end
			if button == "RightButton" then CardMenu(self) return end
			local key = M:CardKey()
			if key and self.pullIndex and not InCombatLockdown() and M:OpenBrowser(key) then M:SelectPull(self.pullIndex, true) end
		end)
		Kit.Tooltip(row, nil, function(tooltip)
			local key = M:CardKey()
			local route = key and M:ActiveRoute(key)
			local pull = route and row.pullIndex and route.pulls[row.pullIndex]
			if not pull then return end
			Kit.TipTitle(tooltip, (L["Pull %d"]):format(row.pullIndex))
			for _, pack in ipairs(M:PullInfo(key, pull).packs) do
				for _, member in ipairs(pack.members) do
					tooltip:AddLine(("%dx %s"):format(member.count, member.name or "?"), unpack(Kit.TEXT))
				end
			end
			E:TooltipHint(tooltip, { L["Click"], L["show it in the Dungeons window (out of combat)"] })
		end)
		E:BindOptionsLink(row, { page = "module:DungeonRoutes" })
		card.rows[index] = row
	end
	card.empty = Kit.Text(card, 11, "LEFT", "secondary")
	card.empty:SetPoint("TOPLEFT", PAD, -(PAD + HEAD_H))
	card.empty:SetPoint("TOPRIGHT", -PAD, -(PAD + HEAD_H))
	card.back = Kit.Button(card, L["Back"], 70, 20, function() M:TickPull(nil, -1) end,
		L["Back"], L["Uncheck the last pull: it is next again."])
	card.back:SetPoint("BOTTOMLEFT", PAD, PAD - 2)
	card.done = Kit.Button(card, L["Done"], 70, 20, function() M:TickPull(nil, 1) end,
		L["Done"], L["Check the next pull off. Only your click counts: the card never reads what you killed."])
	card.done:SetPoint("BOTTOMRIGHT", -PAD, PAD - 2)
	card:SetScript("OnMouseUp", function(self, button) if button == "RightButton" then CardMenu(self) end end)
	return card
end

local function Fill()
	if not card then return end
	local key = M:CardKey()
	local rows = Rows()
	local route = key and M:ActiveRoute(key)
	local sample = not key and sampleShown
	card.title:SetText(key and M:DungeonName(key) or L["Route Card"])
	local done = key and M:DoneCount(key) or 0
	local total = route and #route.pulls or 0
	card.count:SetText(route and ("%d/%d"):format(done, total) or "")
	card.empty:Hide()
	for index, row in ipairs(card.rows) do
		local pullIndex = done + index
		local pull = route and route.pulls[pullIndex]
		row.pullIndex = pull and pullIndex or nil
		if index <= rows and pull then
			row.number:SetText(pullIndex)
			row.number:SetTextColor(M:ColorRGB(pull.c))
			row.text:SetText(M:PullText(key, pull))
			row.text:SetTextColor(unpack(index == 1 and Kit.TEXT or Kit.SECONDARY))
			row:Show()
		elseif index <= rows and sample then
			row.number:SetText(index)
			row.number:SetTextColor(M:ColorRGB(nil))
			row.text:SetText(L["Next pull of your route"])
			row.text:SetTextColor(unpack(Kit.SECONDARY))
			row:Show()
		else
			row:Hide()
		end
	end
	if route and done >= total then
		card.empty:SetText(total > 0 and L["Route done. Right-click to start again."] or L["This route has no pulls yet."])
		card.empty:Show()
	elseif not route and key then
		card.empty:SetText(L["No route for this dungeon."])
		card.empty:Show()
	end
	card.back:SetEnabled(done > 0)
	card.done:SetEnabled(route ~= nil and done < total)
	local shownRows = (route and done < total) and math.min(rows, total - done) or ((sample and rows) or 1)
	card:SetHeight(PAD + HEAD_H + shownRows * ROW_H + FOOT_H + PAD)
end

function M:RefreshCard()
	if not card then return end
	local key = self:CardKey()
	local show = key ~= nil or (sampleShown and self.active and self.db.card)
	if show then
		Fill()
		card:Show()
	else
		card:Hide()
	end
	return show
end

function M:CreateCard()
	if mover then return card end
	Build()
	mover = E:CreateMover(card, NAME, L["Route Card"], M.CARD_DEFAULT_POINT, { enabledPath = { "card" }, followShown = true })
	self.cardMover = mover
	return card
end

function M:Card()
	return card, mover
end

-- Entering a dungeon: remember it for "Also outside dungeons", and start a
-- run that is old again.
local function OnZone()
	local here = M:CurrentDungeon()
	if here then
		local store = M:Store()
		if store.cardLast ~= here then store.cardLast = here end
		local entry = Progress()[here]
		local now = time and time() or 0
		if type(entry) == "table" and now - (tonumber(entry.at) or 0) > FRESH then Progress()[here] = nil end
	end
	M:RefreshCard()
end

M:Hook("enable", function()
	M:CreateCard()
	OnZone()
end)
M:Hook("disable", function()
	if card then card:Hide() end
end)
M:Hook("zone", OnZone)
M:Hook("profile", function() M:RefreshCard() end)
M:Hook("changed", function() M:RefreshCard() end)

-- Move mode shows a sample, so the card has a place and a size.
hooksecurefunc(E, "ToggleMoveMode", function()
	sampleShown = E:IsMoveMode() and true or false
	if M.active then M:RefreshCard() end
end)
