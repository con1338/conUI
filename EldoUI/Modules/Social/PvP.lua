-- EldoUI Social: battleground scoreboard and results (pvp-match).
--
-- Blizzard_PVPMatch: PVPMatchScoreboard (the in-match score table) and
-- PVPMatchResults (the end-of-match window). Forever has no arena frames
-- and no PvP queue window (Blizzard_PVPUI does not load there).
--   Skin     art-style panels, flat tabs, theme fonts in the score table,
--            flat buttons
--   Move     drag by the top edge, scale (Modules/Social.lua window mover)
--   Improve  player names in the score table in class color
-- The scores are Blizzard's own data, shown as Blizzard gives them: EldoUI
-- only re-colors the name cell from the class Blizzard puts in the row.
-- No enemy tracking of any kind.
-- The battleground "enter battle" popup (PVPReadyDialog) belongs to
-- Notifications (element "ready-check-popups"); this file leaves it alone.
-- Written from scratch for EldoUI; no code or media from other addons.
local _, E = ...

local M = E:GetModule("Social")
local K = M.kit
local Usable, Try = K.Usable, K.Try

local ID = "pvp-match"
local ADDON = "Blizzard_PVPMatch"

local function Skin() return M.active and E:BlizzardAllowed(ID, "skin") end
local function Improve() return M.active and E:BlizzardAllowed(ID, "improve") end

---------------------------------------------------------------------------
-- Score table rows
---------------------------------------------------------------------------
local function IsNameCell(cell)
	local populate = cell.Populate
	if type(populate) ~= "function" then return false end
	for _, mixin in ipairs({ _G.PVPCellNameMixin, _G.PVPSoloShuffleCellNameMixin }) do
		if type(mixin) == "table" and mixin.Populate == populate then return true end
	end
	return false
end

local function PlayerGUID()
	local guid = UnitGUID("player")
	if K.Secret(guid) then return end
	return guid
end

-- What each cell was last styled with, so a refresh only touches cells
-- whose row moved to another player or whose size setting changed.
local styled = setmetatable({}, { __mode = "k" }) -- cell -> { data, size, skin, improve }

local function StyleRow(row)
	if not Usable(row) or not M.active or type(row.cells) ~= "table" then return end
	local db = M.db.pvp
	local skin, improve = Skin(), Improve()
	local size = db.rowSize or 12
	for _, cell in ipairs(row.cells) do
		local text = type(cell) == "table" and cell.text
		if text and text.SetFont then
			local data = cell.rowData
			local last = styled[cell]
			if not (last and last.data == data and last.size == size and last.skin == skin and last.improve == improve) then
				styled[cell] = { data = data, size = size, skin = skin, improve = improve }
				if skin then E:SkinRecord(ID, row, K.Fonts, size, text) end
				if improve and db.classColors and type(data) == "table" and IsNameCell(cell) then
					local token, guid = data.classToken, data.guid
					local isSelf = db.highlightSelf and type(guid) == "string" and not K.Secret(guid) and guid == PlayerGUID()
					local r, g, b = K.ClassRGB(token)
					-- Your own row stays Blizzard's white so you find yourself at a glance.
					if r and not isSelf then text:SetVertexColor(r, g, b) end
				end
			end
		end
	end
end

local function ScoreBoxes()
	local list = {}
	local board, results = _G.PVPMatchScoreboard, _G.PVPMatchResults
	if board and Usable(board.ScrollBox) then list[#list + 1] = board.ScrollBox end
	local content = results and results.content
	if content and Usable(content.scrollBox) then list[#list + 1] = content.scrollBox end
	return list
end

local function RefreshRows()
	for _, box in ipairs(ScoreBoxes()) do
		if box.ForEachFrame then pcall(box.ForEachFrame, box, function(row) Try(StyleRow, row) end) end
	end
end

-- Blizzard fills the cells while it builds the table; EldoUI styles them
-- afterwards, from its own timer. Nothing of EldoUI's runs inside the
-- game's table build, which in a full battleground already takes long.
local function QueueRows()
	E:Debounce("social:pvp", 0.1, function()
		if M.active then RefreshRows() end
	end)
end

-- Rows scrolled into view: checked a few times a second while a window is
-- open (a cheap look at each visible row; only changed cells are styled).
local watcher
local function ShownWindow()
	for _, name in ipairs({ "PVPMatchScoreboard", "PVPMatchResults" }) do
		local frame = _G[name]
		if Usable(frame) and frame:IsShown() then return true end
	end
	return false
end
local function Watch()
	if not watcher then
		watcher = CreateFrame("Frame")
		watcher.elapsed = 0
		watcher:SetScript("OnUpdate", function(self, elapsed)
			self.elapsed = self.elapsed + elapsed
			if self.elapsed < 0.25 then return end
			self.elapsed = 0
			if not (M.active and ShownWindow()) then
				self:Hide()
				return
			end
			RefreshRows()
		end)
	end
	watcher:Show()
end

---------------------------------------------------------------------------
-- Skin
---------------------------------------------------------------------------
local function SkinTable(content, scrollBar, tabContainer, tabs, owner, matchmaking)
	if Usable(content) then
		E:StripTextures(content)
		if Usable(content.ScrollBox or content.scrollBox) then
			E:SkinAlphaZero((content.ScrollBox or content.scrollBox).Background)
		end
	end
	E:SkinScrollBar(scrollBar)
	if Usable(tabContainer) then E:StripTextures(tabContainer) end
	if matchmaking and matchmaking.SetFont then
		E:SetFont(matchmaking, E.tokens.size.label)
		matchmaking:SetTextColor(unpack(E.media.text.secondary))
	end
	E:SkinTabs(tabs, { owner = owner })
end

local function SkinScoreboard()
	local board = _G.PVPMatchScoreboard
	if not Usable(board) then return end
	Try(E.SkinPanel, E, board, { transparent = M.db.transparent, accentOffset = 30 })
	local content = board.Content
	local tabs = board.TabContainer
	local group = tabs and tabs.TabGroup
	SkinTable(content, board.ScrollBar or (content and content.ScrollBar), tabs,
		{ board.Tab1 or (group and group.Tab1), board.Tab2 or (group and group.Tab2), board.Tab3 or (group and group.Tab3) },
		board, tabs and tabs.MatchmakingText)
end

local function SkinResults()
	local results = _G.PVPMatchResults
	if not Usable(results) then return end
	Try(E.SkinPanel, E, results, { transparent = M.db.transparent, accentOffset = 30 })
	local overlay = results.overlay
	if Usable(overlay) then E:SkinAlphaZero(overlay.decorator) end
	local content = results.content
	local tabs = content and content.tabContainer
	local group = tabs and tabs.tabGroup
	SkinTable(content, content and content.scrollBar, tabs,
		{ group and group.tab1, group and group.tab2, group and group.tab3 }, results, tabs and tabs.matchmakingText)
	local buttons = results.buttonContainer
	if Usable(buttons) then
		E:SkinButton(buttons.requeueButton)
		E:SkinButton(buttons.leaveButton)
	end
end

---------------------------------------------------------------------------
-- Part: the match windows (Blizzard_PVPMatch)
---------------------------------------------------------------------------
local hooked = false
local function Hook()
	if hooked then return end
	hooked = true
	E:RegisterEvent("UPDATE_BATTLEFIELD_SCORE", function()
		if M.active and ShownWindow() then QueueRows() end
	end, QueueRows)
	for _, name in ipairs({ "PVPMatchScoreboard", "PVPMatchResults" }) do
		local frame = _G[name]
		if Usable(frame) then frame:HookScript("OnShow", function() if M.active then QueueRows() Watch() end end) end
	end
end

M:AddPart({
	id = ID,
	addon = ADDON,
	install = { skin = true, improve = true },
	setup = function()
		if not Usable(_G.PVPMatchScoreboard) then error("EldoUI Social: PVPMatchScoreboard is missing") end
		Hook()
	end,
	apply = function(part)
		if Skin() then
			E:SkinRecord(ID, { _G.PVPMatchScoreboard, _G.PVPMatchResults }, function()
				if not part.skinned then
					part.skinned = true
					Try(SkinScoreboard)
					Try(SkinResults)
				end
				for _, name in ipairs({ "PVPMatchScoreboard", "PVPMatchResults" }) do
					local frame = _G[name]
					if Usable(frame) then E:SetPanelTransparent(frame, M.db.transparent) end
				end
			end)
		end
		M:ApplyWindow("scoreboard")
		M:ApplyWindow("results")
		RefreshRows()
		if ShownWindow() then Watch() end
	end,
	undo = function()
		M:RestoreWindow("scoreboard")
		M:RestoreWindow("results")
	end,
})

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
M:AddOptions({ { type = "tab", label = "PvP" } })
M:AddOptions(M:SwitchOptions(ID, { { "scoreboard", "Scoreboard" }, { "results", "Results window" } }))
M:AddOptions({
	{ type = "header", label = "Score table" },
	{ type = "toggle", disabled = E:BlizzardNeeds(ID, "improve"), key = "pvp.classColors", label = "Class colors",
		desc = "Player names in the scoreboard and results in their class color instead of the team color." },
	{ type = "toggle", disabled = E:BlizzardNeeds(ID, "improve"), key = "pvp.highlightSelf", label = "Keep your own name white", desc = "Your own row keeps Blizzard's white name, so you find yourself at a glance." },
	{ type = "range", disabled = E:BlizzardNeeds(ID, "skin"), key = "pvp.rowSize", label = "Table text size", min = 9, max = 16, step = 1, desc = "Size of the names and scores in the table." },
	{ type = "header", label = "Battleground popup" },
	{ type = "description", label = "The Enter Battle popup's skin and countdown bar are set under Messages > Ready check." },
})
