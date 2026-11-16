-- EldoUI Legacy Planner window: an E.WindowKit window on the shared
-- window mover (E:RegisterWindow, key "legacyPlanner").
--
--   Build       your Legacy trees node by node: your ranks now, the draft's
--               ranks, added nodes green, removed red, changed yellow; the
--               draft's cost against the points you own and the season cap.
--               Clicks change the draft only.
--   Profiles    named builds shared by all your characters: load one into
--               the draft, overwrite it with the draft, rename, delete,
--               export and import ("!EUL1!" strings).
--   Challenges  Legacy Challenges with progress bars, a status filter,
--               a category filter and search.
--
-- Next to Blizzard's Legacy window: when the player lets EldoUI improve
-- "Legacy window and achievements" (Blizzard UI page), the planner docks
-- beside LegacySystemFrame while that window is open, a Planner button sits
-- on it, and (an option, off by default) the planner opens with it. The
-- planner only reads Blizzard's window: it never clicks, stages or applies
-- anything there.
local _, E = ...
local L = E.L
local Key = E.Key
local M = E.Legacy
local Kit = E.UIKit
local WK = E.WindowKit

local NAME = "EldoUI_LegacyPlanner"
local WINDOW_KEY = "legacyPlanner"
local ELEMENT = "legacy-achievements"
local WIDTH, HEIGHT = 540, 620
local TAB_HEIGHT = 24

local win
local docked = false
local openedWithBlizzard = false
local selectedProfile
local filters = { tree = "all", category = nil, search = "" }

local PAGES = {
	{ key = "build", title = "Build", desc = "Your Legacy trees: ranks now and in your draft, with the changes marked." },
	{ key = "profiles", title = "Profiles", desc = "Named Legacy builds shared by all your characters." },
	{ key = "challenges", title = "Challenges", desc = "Legacy Challenges with progress, filters and search." },
}

local function Color(status)
	if status == M.STATUS.added then return Kit.GOOD end
	if status == M.STATUS.removed then return Kit.BAD end
	if status == M.STATUS.changed then return Kit.WARN end
end

local function Hex(color) return Kit.Hex(color[1], color[2], color[3]) end

local function Ranks(build, nodeID)
	local item = build and build[nodeID]
	return type(item) == "table" and (tonumber(item.r) or 0) or 0
end

---------------------------------------------------------------------------
-- Blizzard's Legacy window
---------------------------------------------------------------------------
local function BlizzardAllowed()
	return M.active and E:BlizzardAllowed(ELEMENT, "improve")
end

local function BlizzardFrame()
	local frame = rawget(_G, "LegacySystemFrame")
	if type(frame) ~= "table" or not frame.IsShown then return nil end
	if E.FrameCheck(frame, "IsForbidden") then return nil end
	return frame
end

function M:IsDocked()
	return docked
end

-- Beside Blizzard's window while it is open (and the switch allows it),
-- else where the window mover keeps it.
function M:UpdateDock()
	if not win then return end
	local blizz = BlizzardFrame()
	if BlizzardAllowed() and blizz and blizz:IsShown() and win:IsShown() then
		docked = true
		-- allowed() is false while docked: the mover lets go of the window.
		E:WindowMoverApply(win)
		win:ClearAllPoints()
		local scale = win:GetEffectiveScale() / UIParent:GetEffectiveScale()
		local right, left = blizz:GetRight(), blizz:GetLeft()
		local screen = UIParent:GetRight()
		if right and left and screen and right + WIDTH * scale + 4 > screen and left - WIDTH * scale - 4 > 0 then
			win:SetPoint("TOPRIGHT", blizz, "TOPLEFT", -4, 0)
		else
			win:SetPoint("TOPLEFT", blizz, "TOPRIGHT", 4, 0)
		end
	elseif docked then
		docked = false
		win:ClearAllPoints()
		win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
		E:WindowMoverApply(win)
	end
end

local plannerButton
local hooked

local function UpdateBlizzardButton()
	local blizz = BlizzardFrame()
	if not blizz then return end
	if not (BlizzardAllowed() and M.db.blizzButton) then
		if plannerButton then plannerButton:Hide() end
		return
	end
	if plannerButton and plannerButton:GetParent() ~= blizz then
		plannerButton:Hide()
		plannerButton = nil
	end
	if not plannerButton then
		plannerButton = Kit.Button(blizz, L["Planner"], 80, 20, function() M:TogglePlanner() end, L["Legacy Planner"],
			L["Opens EldoUI's Legacy Planner beside this window: a draft build, profiles and the challenge browser. It never spends points."])
		plannerButton:SetPoint("TOPRIGHT", blizz, "TOPRIGHT", -30, -2)
		plannerButton:SetFrameLevel(blizz:GetFrameLevel() + 20)
	end
	plannerButton:Show()
end

-- Hooks the frame that has the name now (once per frame object).
local function HookBlizzard()
	local blizz = BlizzardFrame()
	if not blizz or hooked == blizz then return end
	hooked = blizz
	blizz:HookScript("OnShow", function()
		if not BlizzardAllowed() then return end
		UpdateBlizzardButton()
		if M.db.openWithBlizzard and not (win and win:IsShown()) then
			if M:OpenPlanner() then openedWithBlizzard = true end
		end
		M:UpdateDock()
	end)
	blizz:HookScript("OnHide", function()
		if not M.active then return end
		if openedWithBlizzard and win and win:IsShown() then
			openedWithBlizzard = false
			win:Hide()
			return
		end
		M:UpdateDock()
	end)
end

-- Hooks go in only once the switch is on; off leaves Blizzard's window as
-- Blizzard made it (our button hidden, the planner undocked).
function M:ApplyBlizzard()
	if not BlizzardAllowed() then return self:RestoreBlizzard() end
	if C_AddOns.IsAddOnLoaded("Blizzard_LegacySystem") then
		HookBlizzard()
		UpdateBlizzardButton()
		self:UpdateDock()
		return
	end
	if self.waitingBlizzard then return end
	self.waitingBlizzard = true
	E:OnBlizzardAddOn("Blizzard_LegacySystem", function()
		M.waitingBlizzard = false
		if not BlizzardAllowed() then return end
		HookBlizzard()
		UpdateBlizzardButton()
		M:UpdateDock()
	end)
end

function M:RestoreBlizzard()
	if plannerButton then plannerButton:Hide() end
	self:UpdateDock()
end

E:RegisterBlizzardHandler(ELEMENT, {
	owner = "Legacy",
	apply = function() if M.active then M:ApplyBlizzard() end end,
	undo = function() M:RestoreBlizzard() end,
	install = { improve = true },
	-- New: nothing put a planner on the Legacy window before.
	legacy = function() return false end,
})

function M:BlizzardPlannerButton()
	return plannerButton
end

---------------------------------------------------------------------------
-- Dialogs
---------------------------------------------------------------------------
function M:AskText(question, text, accept)
	E:ShowConfirm({ key = "ELDOUI_LEGACY_TEXT", title = L["Legacy Planner"], text = question, accept = ACCEPT,
		edit = { text = text or "", maxLetters = 40 },
		onAccept = function(_, typed) if accept then accept(typed or "") end end })
end

-- The draft is the only copy of a plan until it is saved, so a button that
-- replaces it asks first, unless the draft is empty.
function M:AskReplaceDraft(question, accept, replace)
	if next(self:Draft()) == nil then return replace() end
	E:ShowConfirm({ key = "ELDOUI_LEGACY_CONFIRM", title = L["Legacy Planner"], text = question, accept = accept,
		danger = true, onAccept = function() replace() end })
end

-- A saved profile is shared by every character: overwriting it asks first.
function M:AskOverwriteProfile(id)
	local profile = id and self:FindProfile(id)
	if not profile then return end
	E:ShowConfirm({ key = "ELDOUI_LEGACY_CONFIRM", title = L["Legacy Planner"],
		text = L["Save the draft over the Legacy profile %s for all your characters?"]:format(profile.name),
		accept = L["Overwrite"], danger = true, onAccept = function() M:OverwriteProfile(profile.id) end })
end

---------------------------------------------------------------------------
-- Summary (header subtitle) and the cost line
---------------------------------------------------------------------------
function M:SummaryText()
	local snapshot = self:Snapshot()
	if not snapshot then return L["Your Legacy trees aren't loaded yet."] end
	local currency = snapshot.currency
	local parts = {}
	if snapshot.level then parts[#parts + 1] = L["Legacy level %d"]:format(snapshot.level) end
	if currency.quantity then parts[#parts + 1] = L["%d unspent"]:format(currency.quantity) end
	if currency.spent then parts[#parts + 1] = L["%d spent"]:format(currency.spent) end
	if currency.max then parts[#parts + 1] = L["season cap %d"]:format(currency.max) end
	return table.concat(parts, "  |  ")
end

-- The draft's cost check as one line and a state (ok, short, cap).
function M:CostText()
	local snapshot = self:Snapshot()
	if not snapshot then return "", "ok", 0 end
	local draft = self:Draft()
	local cost, _, unknown = M.Cost(draft, snapshot.nodes)
	local currency = snapshot.currency
	local state, amount = M.Check(cost, currency)
	local text
	if state == "cap" then
		text = Hex(Kit.BAD) .. L["The draft costs %d points: %d over the season cap of %d. It can't be made this season."]:format(cost, amount, currency.max) .. "|r"
	elseif state == "short" then
		text = Hex(Kit.WARN) .. L["The draft costs %d points: %d more than the %d you have now."]:format(cost, amount, currency.owned) .. "|r"
	elseif currency.owned then
		text = L["The draft costs %d of your %d points (%d left)."]:format(cost, currency.owned, amount or 0)
	else
		text = L["The draft costs %d points."]:format(cost)
	end
	if unknown > 0 then text = text .. "  " .. Hex(Kit.WARN) .. L["%d draft nodes aren't on your trees."]:format(unknown) .. "|r" end
	return text, state, cost
end

local function DiffLine(counts)
	return ("%s+%d|r  %s-%d|r  %s~%d|r"):format(Hex(Kit.GOOD), counts.added, Hex(Kit.BAD), counts.removed, Hex(Kit.WARN), counts.changed)
end

---------------------------------------------------------------------------
-- Build page
---------------------------------------------------------------------------
local function BuildItems()
	local snapshot = M:Snapshot()
	if not snapshot then return {}, {} end
	local current, draft = M:CurrentBuild(snapshot), M:Draft()
	local status, counts = M.Diff(current, draft)
	local items = {}
	for _, read in ipairs(snapshot.trees) do
		if filters.tree == "all" or filters.tree == read.tree.index then
			local nodes = {}
			for _, node in ipairs(read.nodes) do
				if not M.db.changesOnly or status[node.nodeID] then nodes[#nodes + 1] = node end
			end
			if #nodes > 0 then
				local now, want = 0, 0
				for _, node in ipairs(read.nodes) do
					now = now + Ranks(current, node.nodeID) * node.cost
					want = want + Ranks(draft, node.nodeID) * node.cost
				end
				items[#items + 1] = { header = true, tree = read.tree, now = now, want = want }
				for _, node in ipairs(nodes) do
					items[#items + 1] = { node = node, status = status[node.nodeID], now = Ranks(current, node.nodeID),
						want = Ranks(draft, node.nodeID), choice = draft[node.nodeID] and draft[node.nodeID].e or node.entryID }
				end
			end
		end
	end
	return items, counts
end
M.BuildItems = BuildItems

local function NodeTooltip(tooltip, item)
	local node = item.node
	local info = M:EntryInfo(node.configID, item.choice or node.entryID or node.entries[1])
	tooltip:AddLine(L["Now %d of %d ranks, draft %d."]:format(item.now, node.maxRanks, item.want), Kit.SECONDARY[1], Kit.SECONDARY[2], Kit.SECONDARY[3], true)
	if node.cost > 0 then tooltip:AddLine(L["%d Legacy points a rank."]:format(node.cost), Kit.SECONDARY[1], Kit.SECONDARY[2], Kit.SECONDARY[3], true) end
	if info and info.description and info.description ~= "" then Kit.TipTitle(tooltip, info.description, true) end
	if node.choice then
		local names = {}
		for _, entryID in ipairs(node.entries) do
			local option = M:EntryInfo(node.configID, entryID)
			local name = option and option.name ~= "" and option.name or tostring(entryID)
			if entryID == item.choice then name = Kit.AccentHex() .. name .. "|r" end
			names[#names + 1] = name
		end
		tooltip:AddLine(L["Choice: %s"]:format(table.concat(names, " / ")), Kit.SECONDARY[1], Kit.SECONDARY[2], Kit.SECONDARY[3], true)
	end
	local color = Color(item.status)
	if color then
		local labels = { added = L["Added in the draft"], removed = L["Removed in the draft"], changed = L["Changed in the draft"] }
		tooltip:AddLine(labels[item.status], color[1], color[2], color[3])
	end
	E.UIKit.TipText(tooltip, L["Nothing is spent."])
	E:TooltipHint(tooltip, { L["Click"], L["add a rank to the draft"] }, { L["Right-click"], L["take one away"] })
end

local function CreateBuildRow(row)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	E:SkinRow(row)
	row.stripe = row:CreateTexture(nil, "ARTWORK")
	row.stripe:SetWidth(3)
	row.stripe:SetPoint("TOPLEFT")
	row.stripe:SetPoint("BOTTOMLEFT")
	row.icon = row:CreateTexture(nil, "ARTWORK")
	E:TrimIcon(row.icon)
	row.name = Kit.Text(row, 12, "LEFT")
	row.name:SetWordWrap(false)
	row.now = Kit.Text(row, 12, "RIGHT", "secondary")
	row.want = Kit.Text(row, 12, "RIGHT")
	row.minus = Kit.IconButton(row, 18, nil, function(own) M:DraftRank(own:GetParent().item.node.nodeID, -1) end,
		L["Take away a rank"], L["One rank less in the draft. Nothing is refunded."], "-")
	row.plus = Kit.IconButton(row, 18, nil, function(own) M:DraftRank(own:GetParent().item.node.nodeID, 1) end,
		L["Add a rank"], L["One rank more in the draft. Nothing is spent."], "+")
	row.swap = Kit.Button(row, L["Swap"], 48, 18, function(own) M:DraftSwap(own:GetParent().item.node.nodeID) end,
		L["Swap the choice"], L["Picks the next option of this choice node in the draft."])
	row.plus:SetPoint("RIGHT", -2, 0)
	row.minus:SetPoint("RIGHT", row.plus, "LEFT", -2, 0)
	row.want:SetPoint("RIGHT", row.minus, "LEFT", -6, 0)
	row.want:SetWidth(44)
	row.now:SetPoint("RIGHT", row.want, "LEFT", -4, 0)
	row.now:SetWidth(44)
	row.swap:SetPoint("RIGHT", row.now, "LEFT", -6, 0)
	row:SetScript("OnClick", function(self, button)
		local item = self.item
		if not (item and item.node) then return end
		M:DraftRank(item.node.nodeID, button == "RightButton" and -1 or 1)
	end)
	Kit.Tooltip(row, nil, function(tooltip)
		local item = row.item
		if not item then return end
		if item.header then
			Kit.TipTitle(tooltip, item.tree.name)
			tooltip:AddLine(L["Points in this tree now %d, in the draft %d."]:format(item.now, item.want), Kit.SECONDARY[1], Kit.SECONDARY[2], Kit.SECONDARY[3], true)
			return
		end
		Kit.TipTitle(tooltip, item.node.name)
		NodeTooltip(tooltip, item)
	end)
end

local function UpdateBuildRow(row, item)
	local height = row:GetHeight()
	if item.header then
		row.stripe:Hide()
		row.icon:Hide()
		row.minus:Hide()
		row.plus:Hide()
		row.swap:Hide()
		row.name:ClearAllPoints()
		row.name:SetPoint("LEFT", 6, 0)
		row.name:SetPoint("RIGHT", row.now, "LEFT", -6, 0)
		row.name:SetText(item.tree.name)
		Kit.Paint(row.name, "header")
		row.now:SetText(L["now %d"]:format(item.now))
		row.want:SetText(L["draft %d"]:format(item.want))
		row.want:SetWidth(64)
		row.now:SetWidth(64)
		return
	end
	local node = item.node
	row.want:SetWidth(44)
	row.now:SetWidth(44)
	row.minus:Show()
	row.plus:Show()
	row.minus:SetEnabled(item.want > 0)
	row.plus:SetEnabled(item.want < node.maxRanks)
	row.swap:SetShown(node.choice)
	local color = Color(item.status)
	row.stripe:SetShown(color ~= nil)
	if color then row.stripe:SetColorTexture(color[1], color[2], color[3], 1) end
	local left = 8
	if M.db.showIcons then
		local size = math.max(height - 4, 12)
		row.icon:SetSize(size, size)
		row.icon:ClearAllPoints()
		row.icon:SetPoint("LEFT", 8, 0)
		row.icon:SetTexture(node.icon or 134400)
		row.icon:Show()
		left = 8 + size + 6
	else
		row.icon:Hide()
	end
	local name = node.name
	if node.choice and item.choice then
		local option = M:EntryInfo(node.configID, item.choice)
		if option and option.name ~= "" then name = option.name end
	end
	row.name:ClearAllPoints()
	row.name:SetPoint("LEFT", left, 0)
	row.name:SetPoint("RIGHT", node.choice and row.swap or row.now, "LEFT", -6, 0)
	row.name:SetText(name)
	if color then row.name:SetTextColor(color[1], color[2], color[3]) else Kit.Paint(row.name) end
	row.now:SetText(("%d/%d"):format(item.now, node.maxRanks))
	row.want:SetText(("%d/%d"):format(item.want, node.maxRanks))
	if color then row.want:SetTextColor(color[1], color[2], color[3]) else Kit.Paint(row.want) end
end

-- A page takes its place below the tabs before its rows are built, so
-- every row measures against the page's real size.
local function NewPage(parent)
	local page = CreateFrame("Frame", nil, parent)
	page:SetPoint("TOPLEFT", 0, -(TAB_HEIGHT + 10))
	page:SetPoint("BOTTOMRIGHT")
	return page
end

local function CreateBuildPage(parent)
	local page = NewPage(parent)
	page.cost = Kit.Text(page, 12, "LEFT")
	page.cost:SetPoint("TOPLEFT", 2, 0)
	page.cost:SetPoint("TOPRIGHT", -2, 0)
	page.cost:SetWordWrap(true)
	page.bar = E:CreateStatusBar(page)
	page.bar:SetHeight(8)
	page.bar:SetPoint("TOPLEFT", page.cost, "BOTTOMLEFT", 0, -6)
	page.bar:SetPoint("TOPRIGHT", page.cost, "BOTTOMRIGHT", 0, -6)
	page.bar:SetMinMaxValues(0, 1)
	E:SetTemplate(page.bar, true)
	page.diff = Kit.Text(page, 12, "RIGHT")
	page.diff:SetPoint("TOPRIGHT", page.bar, "BOTTOMRIGHT", 0, -8)
	local treeChips = { { "all", L["All trees"], L["Every Legacy tree."] } }
	for _, tree in ipairs(M:Trees()) do
		treeChips[#treeChips + 1] = { tree.index, tree.name, L["Only the %s tree."]:format(tree.name) }
	end
	page.trees = Kit.ChipBar(page, { chips = treeChips, selected = filters.tree, onChange = function(selected, key)
		filters.tree = selected[key] and key or "all"
		page.trees:SetSelected(filters.tree)
		M:RefreshWindow()
	end })
	page.trees:SetPoint("TOPLEFT", page.bar, "BOTTOMLEFT", 0, -8)
	page.changes = Kit.ChipBar(page, { multi = true, selected = M.db.changesOnly and { changes = true } or nil,
		chips = { { "changes", L["Changes only"], L["Shows only the nodes your draft adds, removes or changes."] } },
		onChange = function(selected)
			M.db.changesOnly = selected.changes and true or false
			M:RefreshWindow()
		end })
	page.changes:SetPoint("TOPLEFT", page.trees, "BOTTOMLEFT", 0, -6)
	page.list = Kit.CreateList(page, {
		rowHeight = M.db.rowHeight, gap = 1,
		create = CreateBuildRow, update = UpdateBuildRow,
		empty = { L["Nothing to show"], L["Your draft matches your build. Click a node to add a rank, or load a profile."], 134400 },
	})
	page.list:SetPoint("TOPLEFT", page.changes, "BOTTOMLEFT", 0, -8)
	page.list:SetPoint("BOTTOMRIGHT")
	function page:Update()
		local text, state, cost = M:CostText()
		self.cost:SetText(text)
		local snapshot = M:Snapshot()
		local limit = snapshot and (snapshot.currency.max or snapshot.currency.owned) or 0
		self.bar:SetValue(limit > 0 and math.min(cost / limit, 1) or 0)
		local color = state == "cap" and Kit.BAD or state == "short" and Kit.WARN or { Kit.Accent() }
		self.bar:SetStatusBarColor(color[1], color[2], color[3])
		local items, counts = BuildItems()
		self.diff:SetText(DiffLine(counts))
		self.list.opts.rowHeight = M.db.rowHeight
		self.list:SetData(items)
	end
	return page
end

---------------------------------------------------------------------------
-- Profiles page
---------------------------------------------------------------------------
local function ProfileInfo(profile)
	local snapshot = M:Snapshot()
	local cost = M.Cost(profile.build, snapshot and snapshot.nodes)
	local _, counts = M.Diff(M:CurrentBuild(snapshot), profile.build)
	local same = counts.added + counts.removed + counts.changed == 0
	return cost, counts, same
end

local function CreateProfileRow(row)
	row:RegisterForClicks("LeftButtonUp")
	E:SkinRow(row)
	row.fill = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.fill:SetAllPoints()
	row.name = Kit.Text(row, 12, "LEFT")
	row.name:SetPoint("LEFT", 8, 0)
	row.name:SetWordWrap(false)
	row.date = Kit.Text(row, 11, "RIGHT", "secondary")
	row.date:SetPoint("RIGHT", -6, 0)
	row.date:SetWidth(70)
	row.diff = Kit.Text(row, 11, "RIGHT")
	row.diff:SetPoint("RIGHT", row.date, "LEFT", -6, 0)
	row.diff:SetWidth(110)
	row.info = Kit.Text(row, 11, "RIGHT", "secondary")
	row.info:SetPoint("RIGHT", row.diff, "LEFT", -6, 0)
	row.info:SetWidth(110)
	row.name:SetPoint("RIGHT", row.info, "LEFT", -6, 0)
	row:SetScript("OnClick", function(self)
		selectedProfile = self.item and self.item.id
		M:RefreshWindow()
	end)
	row:SetScript("OnDoubleClick", function(self)
		if self.item then M:LoadProfileAndShow(self.item.id) end
	end)
	Kit.Tooltip(row, nil, function(tooltip)
		local profile = row.item
		if not profile then return end
		Kit.TipTitle(tooltip, profile.name)
		local cost, counts, same = ProfileInfo(profile)
		tooltip:AddLine(L["%d ranks, %d Legacy points"]:format(M.CountRanks(profile.build), cost), Kit.SECONDARY[1], Kit.SECONDARY[2], Kit.SECONDARY[3])
		Kit.TipTitle(tooltip, same and L["Matches your build."] or L["Against your build: %s"]:format(DiffLine(counts)))
		E.UIKit.TipText(tooltip, L["Your Legacy points don't change."])
		E:TooltipHint(tooltip, { L["Double-click"], L["load into the draft"] })
	end)
end

local function UpdateProfileRow(row, profile)
	local selected = profile.id == selectedProfile
	local r, g, b = Kit.Accent()
	row.fill:SetColorTexture(r, g, b, selected and 0.25 or 0)
	row.name:SetText(profile.name)
	local cost, counts, same = ProfileInfo(profile)
	row.info:SetText(L["%d ranks, %d pts"]:format(M.CountRanks(profile.build), cost))
	row.diff:SetText(same and (Hex(Kit.GOOD) .. L["your build"] .. "|r") or DiffLine(counts))
	row.date:SetText(profile.updated and E:ShortDay(profile.updated) or "")
end

local function CreateProfilesPage(parent)
	local page = NewPage(parent)
	page.help = Kit.Text(page, 12, "LEFT", "secondary")
	page.help:SetPoint("TOPLEFT", 2, 0)
	page.help:SetPoint("TOPRIGHT", -2, 0)
	page.help:SetWordWrap(true)
	page.help:SetText(L["Profiles are saved for all your characters. Loading one only changes the draft; you spend points in Blizzard's Legacy window."])
	page.list = Kit.CreateList(page, {
		rowHeight = M.db.rowHeight, gap = 1,
		create = CreateProfileRow, update = UpdateProfileRow,
		empty = { L["No profiles yet"], L["Build a draft on the Build page and click Save as profile, or import a Legacy build string."], 134400 },
	})
	page.list:SetPoint("TOPLEFT", page.help, "BOTTOMLEFT", 0, -10)
	page.list:SetPoint("BOTTOMRIGHT")
	function page:Update()
		if selectedProfile and not M:FindProfile(selectedProfile) then selectedProfile = nil end
		self.list.opts.rowHeight = M.db.rowHeight
		self.list:SetData(M:Profiles())
	end
	return page
end

function M:LoadProfileAndShow(id)
	local ok, dropped = self:LoadProfile(id)
	if not ok then return false end
	if dropped and dropped > 0 then E:Print(L["%d nodes of that profile aren't on your Legacy trees and were left out."]:format(dropped)) end
	if win then self:ShowPage("build") end
	return true
end

---------------------------------------------------------------------------
-- Challenges page
---------------------------------------------------------------------------
local STATUS_CHIPS = {
	{ "all", Key("All"), Key("Every Legacy Challenge.") },
	{ "progress", Key("In progress"), Key("Challenges you have started but not finished.") },
	{ "new", Key("Not started"), Key("Challenges with no progress yet.") },
	{ "done", Key("Done"), Key("Challenges you have finished.") },
}

local function InsertLink(link)
	if not link then return end
	local util = rawget(_G, "ChatFrameUtil")
	if type(util) == "table" and util.InsertLink and util.InsertLink(link) then return end
	local insert = rawget(_G, "ChatEdit_InsertLink")
	if type(insert) == "function" then insert(link) end
end

local function CreateChallengeRow(row)
	E:SkinRow(row)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	E:TrimIcon(row.icon)
	row.icon:SetPoint("LEFT", 6, 0)
	row.name = Kit.Text(row, 12, "LEFT")
	row.name:SetWordWrap(false)
	row.points = Kit.Text(row, 12, "RIGHT")
	row.points:SetPoint("TOPRIGHT", -6, -4)
	row.points:SetWidth(54)
	-- The icon is the row's height less 8, so its top and the points' top
	-- are both 4 under the row's.
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
	row.name:SetPoint("TOPRIGHT", row.points, "TOPLEFT", -6, 0)
	row.category = Kit.Text(row, 10, "LEFT", "secondary")
	row.category:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 0)
	row.category:SetWidth(150)
	row.category:SetWordWrap(false)
	row.bar = E:CreateStatusBar(row)
	row.bar:SetHeight(10)
	row.bar:SetMinMaxValues(0, 1)
	row.bar:SetPoint("LEFT", row.category, "RIGHT", 8, 0)
	row.bar:SetPoint("RIGHT", -6, 0)
	E:SetTemplate(row.bar, true)
	row.barText = Kit.Text(row.bar, 10, "CENTER")
	row.barText:SetPoint("CENTER")
	row:SetScript("OnClick", function(self)
		if self.item and IsModifiedClick and IsModifiedClick("CHATLINK") then
			InsertLink(M.Call(GetAchievementLink, self.item.id))
		end
	end)
	Kit.Tooltip(row, nil, function(tooltip)
		local item = row.item
		if not item then return end
		Kit.TipTitle(tooltip, item.name)
		if item.description ~= "" then tooltip:AddLine(item.description, Kit.SECONDARY[1], Kit.SECONDARY[2], Kit.SECONDARY[3], true) end
		local count = M.Number(M.Call(GetAchievementNumCriteria, item.id)) or 0
		for index = 1, math.min(count, 12) do
			local text, _, completed, have, need = M.Call(GetAchievementCriteriaInfo, item.id, index)
			if type(text) == "string" and text ~= "" then
				local line = text
				if M.Number(need) and need > 1 and M.Number(have) then line = ("%s (%d/%d)"):format(text, have, need) end
				local color = completed and Kit.GOOD or Kit.SECONDARY
				tooltip:AddLine(line, color[1], color[2], color[3], true)
			end
		end
		if item.points then tooltip:AddLine(L["Awards %d Legacy points."]:format(item.points), Kit.Accent()) end
		if item.date then tooltip:AddLine(L["Done %s"]:format(item.date), Kit.GOOD[1], Kit.GOOD[2], Kit.GOOD[3]) end
		E:TooltipHint(tooltip, { L["Shift-click"], L["link it in chat"] })
	end)
end

local function UpdateChallengeRow(row, item)
	local size = row:GetHeight() - 8
	row.icon:SetSize(size, size)
	row.icon:SetTexture(item.icon or 134400)
	row.icon:SetDesaturated(not item.done)
	row.name:SetText(item.name)
	if item.done then row.name:SetTextColor(unpack(Kit.GOOD)) else Kit.Paint(row.name) end
	row.category:SetText(item.topName or item.categoryName)
	row.points:SetText(item.points and item.points > 0 and ("+%d"):format(item.points) or "")
	if item.points and item.points > 0 then row.points:SetTextColor(E:TokenColor("accent")) end
	local progress = item.progress or 0
	row.bar:SetValue(progress)
	local color = item.done and Kit.GOOD or { Kit.Accent() }
	row.bar:SetStatusBarColor(color[1], color[2], color[3])
	if item.done then
		row.barText:SetText(item.date and L["Done %s"]:format(item.date) or L["Done"])
	elseif item.have and item.need then
		row.barText:SetText(("%d / %d"):format(item.have, item.need))
	else
		row.barText:SetText(L["Not started"])
	end
end

local function CategoryLabel()
	if not filters.category then return L["All categories"] end
	for _, category in ipairs(M:ChallengeCategories()) do
		if category.id == filters.category then return category.name end
	end
	filters.category = nil
	return L["All categories"]
end

function M:ShowCategoryMenu(anchor)
	E.UIKit.ContextMenu(anchor, function(_, root)
		root:CreateTitle(L["Category"])
		root:CreateRadio(L["All categories"], function() return filters.category == nil end, function()
			filters.category = nil
			M:RefreshWindow()
		end)
		for _, category in ipairs(M:ChallengeCategories()) do
			root:CreateRadio(category.name, function() return filters.category == category.id end, function()
				filters.category = category.id
				M:RefreshWindow()
			end)
		end
	end, { at = "owner" })
end

local function CreateChallengesPage(parent)
	local page = NewPage(parent)
	local box = CreateFrame("EditBox", nil, page, "SearchBoxTemplate")
	E:SearchHint(box)
	box:SetSize(180, 20)
	box:SetAutoFocus(false)
	box:SetPoint("TOPLEFT", 6, 0)
	E:SkinEditBox(box)
	Kit.SearchEscape(box)
	box:HookScript("OnTextChanged", function(own)
		filters.search = own:GetText() or ""
		M:RefreshWindow()
	end)
	Kit.Tooltip(box, L["Search"], L["Finds challenges by name or description as you type."])
	page.search = box
	page.category = Kit.Button(page, L["All categories"], 160, 20, function(own) M:ShowCategoryMenu(own) end,
		L["Category"], L["Shows the challenges of one category."])
	page.category:SetPoint("LEFT", box, "RIGHT", 8, 0)
	page.status = Kit.ChipBar(page, { chips = STATUS_CHIPS, selected = M.db.challengeStatus, onChange = function(selected, key)
		M.db.challengeStatus = selected[key] and key or "all"
		page.status:SetSelected(M.db.challengeStatus)
		M:RefreshWindow()
	end })
	page.status:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, -8)
	page.summary = Kit.Text(page, 11, "RIGHT", "secondary")
	page.summary:SetPoint("TOPRIGHT", page, "TOPRIGHT", -2, -(20 + 8 + 2)) -- the chips' line, under the 20 px search box
	page.list = Kit.CreateList(page, {
		rowHeight = math.max(M.db.rowHeight + 14, 32), gap = 2,
		create = CreateChallengeRow, update = UpdateChallengeRow,
		empty = { L["No challenges match"], L["Try another filter or search word."], 134400 },
	})
	page.list:SetPoint("TOPLEFT", page.status, "BOTTOMLEFT", 0, -8)
	page.list:SetPoint("BOTTOMRIGHT")
	function page:Update()
		local list = M:Challenges()
		local done, earned = 0, 0
		for _, item in ipairs(list) do
			if item.done then
				done = done + 1
				earned = earned + (item.points or 0)
			end
		end
		self.summary:SetText(L["%d of %d done, %d points earned"]:format(done, #list, earned))
		self.category:SetText(CategoryLabel())
		Kit.FitButton(self.category, 120)
		self.status:SetSelected(M.db.challengeStatus)
		self.list.opts.rowHeight = math.max(M.db.rowHeight + 14, 32)
		self.list:SetData(M.FilterChallenges(list, M.db.challengeStatus, filters.category, filters.search))
		if #list == 0 then
			self.list:SetEmpty(L["No Legacy Challenges"], L["The game lists no challenges for this character yet."], 134400)
		else
			self.list:SetEmpty(L["No challenges match"], L["Try another filter or search word."], 134400)
		end
	end
	return page
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local CREATORS = { build = CreateBuildPage, profiles = CreateProfilesPage, challenges = CreateChallengesPage }

-- Pages the client can answer: Build and Profiles need the Legacy trees,
-- Challenges the achievement API.
function M:PageAvailable(key)
	if key == "challenges" then return type(GetCategoryList) == "function" and type(GetAchievementInfo) == "function" end
	return self:Supported()
end

local function FooterButtons()
	local buttons = {}
	local function Add(key, label, tip, onClick)
		local button = Kit.Button(win.footer, label, 100, 22, onClick, label, tip)
		Kit.FitButton(button, 90)
		buttons[key] = button
	end
	Add("copy", L["Copy my build"], L["Starts the draft from the ranks you have now."], function()
		M:AskReplaceDraft(L["Replace the draft with the ranks you have now?"], L["Copy my build"], function() M:CopyCurrent() end)
	end)
	Add("clear", L["Clear draft"], L["Empties the draft. Your Legacy points don't change."], function()
		M:AskReplaceDraft(L["Empty the draft? Your Legacy points don't change."], L["Clear draft"], function() M:ClearDraft() end)
	end)
	Add("save", L["Save as profile"], L["Saves the draft as a named profile for all your characters."], function()
		M:AskText(L["Name for the profile:"], "", function(text)
			local profile, why = M:SaveProfile(text, M:Draft())
			if profile then
				selectedProfile = profile.id
				M:ShowPage("profiles")
			else
				E:Print(why)
			end
		end)
	end)
	Add("export", L["Export"], L["A string of the draft (or the selected profile) to share."], function()
		M:ExportDraft(win.page == "profiles" and selectedProfile or nil)
	end)
	Add("load", L["Load into draft"], L["Copies the selected profile into the draft. Your Legacy points don't change."], function()
		local profile = selectedProfile and M:FindProfile(selectedProfile)
		if not profile then return end
		M:AskReplaceDraft(L["Replace the draft with the profile %s?"]:format(profile.name), L["Load into draft"],
			function() M:LoadProfileAndShow(profile.id) end)
	end)
	Add("overwrite", L["Overwrite"], L["Saves the draft over the selected profile."], function()
		M:AskOverwriteProfile(selectedProfile)
	end)
	Add("rename", L["Rename"], L["Gives the selected profile another name."], function()
		local profile = selectedProfile and M:FindProfile(selectedProfile)
		if profile then M:AskText(L["New name for the profile:"], profile.name, function(text) M:RenameProfile(profile.id, text) end) end
	end)
	Add("delete", L["Delete"], L["Deletes the selected profile for all your characters."], function()
		local profile = selectedProfile and M:FindProfile(selectedProfile)
		if not profile then return end
		E:ShowConfirm({ title = L["Delete profile"], text = L["Delete the Legacy profile %s for all your characters?"]:format(profile.name),
			accept = L["Delete"], danger = true, onAccept = function() M:DeleteProfile(profile.id) end })
	end)
	Add("import", L["Import"], L["Paste a Legacy build string. It is saved as a profile; nothing is spent."], function() M:ShowImportBox() end)
	return buttons
end

local FOOTERS = {
	build = { "copy", "clear", "save", "export" },
	profiles = { "load", "overwrite", "rename", "delete", "export", "import" },
	challenges = {},
}

local function LayoutFooter()
	for _, button in pairs(win.buttons) do button:Hide() end
	local x = 4
	for _, key in ipairs(FOOTERS[win.page] or {}) do
		local button = win.buttons[key]
		button:ClearAllPoints()
		button:SetPoint("LEFT", win.footer, "LEFT", x, -2)
		button:Show()
		x = x + button:GetWidth() + 6
		if win.page == "profiles" and key ~= "import" then
			button:SetEnabled(selectedProfile ~= nil)
		else
			button:SetEnabled(true)
		end
	end
	if win.page == "build" then win.buttons.export:SetEnabled(next(M:Draft()) ~= nil) end
	win.footerText:SetShown(win.page == "challenges")
end

function M:BuildWindow()
	if win then return win end
	win = WK.CreateWindow(NAME, { width = WIDTH, height = HEIGHT, footer = 34, headerHeight = 56, options = { page = "module:Legacy" } })
	win:SetTitle(L["Legacy Planner"], "")
	-- Ctrl+F and Esc work on the Challenges search while that page shows.
	if win.SetKeys then
		win:SetKeys({ search = function()
			local page = win.page == "challenges" and win.pages and win.pages.challenges
			return page and page.search
		end })
	end
	E:SetPanelTransparent(win, self.db.transparent)
	-- Dragging: the window mover's title strip, or the window when the mover
	-- is off; never while docked to Blizzard's window.
	for _, part in ipairs({ win, win.header }) do
		part:SetScript("OnDragStart", function() if not docked then win:StartMoving() end end)
		part:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)
	end
	win.tabs = {}
	for index, def in ipairs(PAGES) do
		local tab = CreateFrame("Button", nil, win.content)
		tab:SetHeight(TAB_HEIGHT)
		tab.pageKey = def.key
		tab:SetScript("OnClick", function(own) M:ShowPage(own.pageKey) end)
		-- The skin gives the tab the theme font (and Large text) before its first text.
		E:SkinTabs({ tab }, { isSelected = function(own) return own.pageKey == win.page end, size = E.tokens.size.body })
		tab:SetText(L[def.title])
		Kit.Tooltip(tab, def.title, def.desc)
		win.tabs[index] = tab
		local text = tab:GetFontString()
		tab:SetWidth(math.max(80, math.ceil((text and text:GetStringWidth() or 60) + 28)))
	end
	win.pages = {}
	win.empty = Kit.EmptyState(win.content)
	win.empty:ClearAllPoints()
	win.empty:SetPoint("TOPLEFT", 0, -(TAB_HEIGHT + 10))
	win.empty:SetPoint("BOTTOMRIGHT")
	win.empty:Hide()
	win.buttons = FooterButtons()
	win.footerText = Kit.Text(win.footer, 11, "LEFT", "secondary")
	win.footerText:SetPoint("LEFT", 6, -2)
	win.footerText:SetPoint("RIGHT", -24, -2)
	win.footerText:SetText(L["Progress comes from the game's achievement data. Spend Legacy points in Blizzard's Legacy window."])
	win:HookScript("OnShow", function() M:UpdateDock() end)
	win:HookScript("OnHide", function()
		openedWithBlizzard = false
		if docked then M:UpdateDock() end
	end)
	E:RegisterWindow({
		key = WINDOW_KEY, frame = win, title = L["Legacy Planner"],
		allowed = function() return not docked end,
		drag = { left = 8, right = 40, top = -1, height = 30 },
	})
	return win
end

-- The empty state when the client can't answer a page.
local function PageEmpty(key)
	if not M:PageAvailable(key) then
		if key == "challenges" then
			return L["No challenge data"], L["This version of the game can't list achievements, so EldoUI can't show Legacy Challenges."]
		end
		return L["Legacy isn't on this client"], L["The game has no Legacy trees here (Constants.LegacyConsts or C_Traits is missing). Type /eui legacy probe to see what it answers."]
	end
	if key ~= "challenges" and not M:Snapshot() then
		return L["Your Legacy trees aren't loaded yet"], L["Legacy unlocks with your first Legacy level. Open Blizzard's Legacy window once, then open the planner again."]
	end
end

-- Tabs only for pages this client can answer (no placeholder pages).
local function LayoutTabs()
	local x, first = 0, nil
	for _, tab in ipairs(win.tabs) do
		local shown = M:PageAvailable(tab.pageKey)
		tab:SetShown(shown)
		if shown then
			tab:ClearAllPoints()
			tab:SetPoint("TOPLEFT", win.content, "TOPLEFT", x, 0)
			x = x + tab:GetWidth() + 2
			first = first or tab.pageKey
		end
	end
	return first
end

function M:ShowPage(key)
	if not win then return end
	local first = LayoutTabs()
	if not CREATORS[key] or (first and not self:PageAvailable(key)) then key = first or "build" end
	win.page = key
	self.db.window = type(self.db.window) == "table" and self.db.window or {}
	self.db.window.page = key
	for pageKey, page in pairs(win.pages) do page:SetShown(pageKey == key) end
	E:UpdateTabs()
	local title, text = PageEmpty(key)
	if title then
		if win.pages[key] then win.pages[key]:Hide() end
		win.empty:Set(title, text, 134400)
		win.empty:Show()
	else
		win.empty:Hide()
		local page = win.pages[key]
		if not page then
			page = CREATORS[key](win.content)
			win.pages[key] = page
		end
		page:Show()
		page:Update()
	end
	win.subtitle:SetText(self:SummaryText())
	LayoutFooter()
end

function M:OpenPlanner(page)
	if not self.active then return false end
	self:BuildWindow()
	if not win:IsShown() then E:SlideIn(win, "DOWN") end
	self:ShowPage(page or (type(self.db.window) == "table" and self.db.window.page) or "build")
	self:UpdateDock()
	return true
end

function M:ClosePlanner()
	if win and win:IsShown() then win:Hide() end
end

function M:TogglePlanner(page)
	if win and win:IsShown() and (page == nil or page == win.page) then
		self:ClosePlanner()
	else
		self:OpenPlanner(page)
	end
end

function M:PlannerWindow()
	return win
end

function M:RefreshWindow()
	if not (win and win:IsShown()) then return end
	self:ShowPage(win.page)
end

function M:RestyleWindow()
	if not win then return end
	E:SetPanelTransparent(win, self.db.transparent)
	self:RefreshWindow()
end
