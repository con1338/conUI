-- EldoUI Group Board: the window.
--
--   +--------------------------------------------------------------+
--   | Group board                                              [x] |
--   | [Groups] [Players] [My level] [Tank] [Healer] [Damage]       |
--   | [Dungeons] [Raids] [Quests] [Other]          [Search.......] |
--   | (icon) Kalio   The Deadmines                  [w] [i] [x]    |
--   |        2 min ago · Group, needs 2: Tank, Healer · LF2M DM... |
--   | ...                                                          |
--   |--------------------------------------------------------------|
--   | 12 of 20 posts                            [Options] [Clear]  |
--   +--------------------------------------------------------------+
--
-- Chips are the board's filters (saved with the profile); none on in a
-- row means all of that row. A row click opens a whisper to the sender;
-- the buttons whisper, invite (players looking for a group) and hide the
-- post until its sender posts something else. The tooltip shows the whole
-- line. Built the first time it opens, in the EldoUI tool window look.
-- Written from scratch for this fork of EldoUI.
local _, ns = ...
local E = EldoUI
if not (E and E.apiVersion and E.apiVersion >= 1) then return end
local L = E.L
local Key = E.Key

local M, Board, Catalog = ns.M, ns.Board, ns.Catalog

local Window = {}
ns.Window = Window

local WIDTH, HEIGHT = 580, 460
local CHIP_ROW = 22
local GROUP_ICON = "Interface\\Icons\\INV_Misc_GroupNeedMore"
local PLAYER_ICON = "Interface\\Icons\\INV_Misc_GroupLooking"

local KIND_CHIPS = {
	{ "lfm", Key("Groups"), Key("Groups looking for players (LFM).") },
	{ "lfg", Key("Players"), Key("Players looking for a group (LFG).") },
	{ "fit", Key("My level"), Key("Only places that fit your level: from three levels under the range to five over it.") },
	{ "tank", Key("Tank"), Key("Groups that need a tank, players who tank. Posts that name no role stay.") },
	{ "heal", Key("Healer"), Key("Groups that need a healer, players who heal. Posts that name no role stay.") },
	{ "dps", Key("Damage"), Key("Groups that need damage, players who deal damage. Posts that name no role stay.") },
}
local CATEGORY_CHIPS = {
	{ "dungeon", Key("Dungeons"), Key("Posts that name a dungeon.") },
	{ "raid", Key("Raids"), Key("Posts that name a raid, or raid groups.") },
	{ "quest", Key("Quests"), Key("Groups for quests, without a dungeon.") },
	{ "other", Key("Other"), Key("Battlegrounds and group posts that name no place.") },
}

local function Selected(chips)
	local filter, selected = M.db.filter, {}
	for _, chip in ipairs(chips) do
		if filter[chip[1]] then selected[chip[1]] = true end
	end
	return selected
end

local function Store(chips, chosen)
	for _, chip in ipairs(chips) do M.db.filter[chip[1]] = chosen[chip[1]] and true or false end
	Window:Refresh()
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function SetIconFor(row, post)
	local texture = row.icon and row.icon.icon
	if post.kind == "lfg" and post.class and texture then
		local ok = pcall(texture.SetAtlas, texture, "classicon-" .. post.class:lower())
		if ok and texture:GetAtlas() then
			texture:SetTexCoord(0, 1, 0, 1)
			return
		end
		local coords = rawget(_G, "CLASS_ICON_TCOORDS") and _G.CLASS_ICON_TCOORDS[post.class]
		if coords then
			texture:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
			texture:SetTexCoord(coords[1] + 0.015, coords[2] - 0.015, coords[3] + 0.015, coords[4] - 0.015)
			return
		end
	end
	row.icon:SetIcon(post.kind == "lfg" and PLAYER_ICON or GROUP_ICON)
	if texture and E.TrimIcon then E:TrimIcon(texture) end
end

local function Tooltip(row)
	local post = row.item
	if not post then return end
	local Kit = E.UIKit
	local tip = GameTooltip
	Kit.AnchorTooltip(row, tip)
	Kit.TipTitle(tip, Board.NameText(post))
	tip:AddLine(post.text or "", 1, 1, 1, true)
	tip:AddLine(" ")
	Kit.TipPair(tip, L["Looking for"], Board.WhatText(post))
	if #post.places > 0 then
		Kit.TipPair(tip, L["Place"], Board.PlacesText(post, 4))
		local min, max = Catalog:Levels(post.places[1])
		if min and not post.maybe then
			Kit.TipPair(tip, L["Levels"], min == max and tostring(min) or ("%d-%d"):format(min, max or min))
		end
	end
	if post.channel then Kit.TipPair(tip, L["Channel"], post.channel) end
	Kit.TipPair(tip, L["Last posted"], Board.AgeText(post))
	if post.count > 1 then Kit.TipPair(tip, L["Times posted"], tostring(post.count)) end
	Kit.TooltipHint(tip, { L["Click"], L["whisper"] }, { L["Right-click"], L["hide this post"] })
	tip:Show()
end

local ACTIONS = {
	{ key = "whisper", art = "Interface\\ChatFrame\\UI-ChatWhisperIcon", mono = true, tipTitle = Key("Whisper"),
		tip = Key("Opens a whisper to this player in the chat box."),
		onClick = function(post) Board:Whisper(post) end },
	{ key = "invite", art = "profile", tipTitle = Key("Invite"), tip = Key("Invites this player to your group."),
		onClick = function(post) Window:Invite(post) end },
	{ key = "hide", art = "cross", tipTitle = Key("Hide"), tip = Key("Hides this post until its sender posts something else."),
		onClick = function(post) Board:Hide(post) end },
}

local function CreateRow(row)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("OnClick", function(self, button)
		if not self.item then return end
		if button == "RightButton" then Board:Hide(self.item) else Board:Whisper(self.item) end
	end)
	row:HookScript("OnEnter", Tooltip)
	row:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function UpdateRow(row, post)
	local sub = Board.AgeText(post) .. "  ·  " .. Board.WhatText(post) .. "  ·  " .. E:TokenHex(E.tokens.text.body) .. (post.text or "") .. "|r"
	row:SetRow({
		name = post.name or post.sender,
		class = post.class,
		statusText = Board.PlacesText(post),
		sub = sub,
		hide = { invite = post.kind ~= "lfg" },
	})
	SetIconFor(row, post)
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
function Window:Build()
	if self.frame then return self.frame end
	local Kit = E.UIKit
	local win = Kit.CreateToolWindow("EldoUI_GroupBoardWindow", { title = L["Group board"], width = WIDTH, height = HEIGHT,
		footer = Kit.TOOL_FOOTER, resizable = { minWidth = 500, minHeight = 260 },
		store = function() return M.db and M.db.window end })
	self.frame = win
	local content = win.content

	win.kinds = Kit.ChipBar(content, { multi = true, chips = KIND_CHIPS, selected = Selected(KIND_CHIPS),
		onChange = function(chosen) Store(KIND_CHIPS, chosen) end })
	win.kinds:SetPoint("TOPLEFT", 0, 0)
	win.categories = Kit.ChipBar(content, { multi = true, chips = CATEGORY_CHIPS, selected = Selected(CATEGORY_CHIPS),
		onChange = function(chosen) Store(CATEGORY_CHIPS, chosen) end })
	win.categories:SetPoint("TOPLEFT", 0, -CHIP_ROW)
	win.search = Kit.Input(content, { width = 170, height = 20, hint = L["Search"],
		tipTitle = L["Search"], tip = L["Matches names, places and the text of the posts."],
		onChange = function(text)
			Window.searchText = text
			Window:Refresh()
		end })
	win.search:SetPoint("TOPRIGHT", 0, -CHIP_ROW + 1)

	win.list = Kit.CreateList(content, Kit.ListRow2Template({ gap = 1, create = CreateRow, update = UpdateRow,
		row = { actions = ACTIONS } }))
	win.list:SetPoint("TOPLEFT", 0, -(2 * CHIP_ROW + 6))
	win.list:SetPoint("BOTTOMRIGHT")

	win.clear = Kit.Button(win.footer, { text = L["Clear"], onClick = function() Board:Clear() end,
		tip = { L["Clear"], L["Removes every post from the board. New posts show up again as they come."] } })
	win.clear:SetPoint("RIGHT", -Kit.TOOL_PAD, 0)
	win.options = Kit.Button(win.footer, { text = L["Options"], onClick = function() E:OpenConfigFromLink("module:GroupBoard") end,
		tip = { L["Options"], L["Channels, how long posts stay, and the notice for new groups."] } })
	win.options:SetPoint("RIGHT", win.clear, "LEFT", -6, 0)
	win.footerText:ClearAllPoints()
	win.footerText:SetPoint("LEFT", 12, 0)
	win.footerText:SetPoint("RIGHT", win.options, "LEFT", -8, 0)

	win:HookScript("OnShow", function() Window:Refresh() end)
	return win
end

function Window:Open()
	if not M.active then return end
	self:Build():Open()
	self:Refresh()
end

function Window:Close()
	if self.frame and self.frame:IsShown() then self.frame:Close() end
end

function Window:Toggle()
	if self.frame and self.frame:IsShown() then self:Close() else self:Open() end
end

function Window:Invite(post)
	local ok, why = Board:Invite(post)
	if ok or not self.frame then return end
	E.UIKit.Toast(self.frame, why == "combat" and L["Invite after combat."] or L["The game did not send the invite."], { warn = true })
end

local function EmptyState(total)
	if Board.Hidden() then
		return L["Chat is held back"], L["The game holds chat back from addons right now, in boss fights or PvP matches for example. The board fills again afterwards."]
	end
	if total > 0 then
		return L["Nothing matches"], L["No post passes the filters. Turn off a chip or clear the search to see more."]
	end
	return L["No group posts yet"],
		L["Group posts from the channels you read show up here, newest first. Options picks the channels."]
end

function Window:Refresh()
	local win = self.frame
	if not (win and win:IsShown()) then return end
	win.kinds:SetSelected(Selected(KIND_CHIPS))
	win.categories:SetSelected(Selected(CATEGORY_CHIPS))
	local list = Board:Matching(self.searchText)
	local total = Board:Count()
	local title, text = EmptyState(total)
	win.list.opts.empty = { title, text, GROUP_ICON }
	win.list:SetData(list)
	win.footerText:SetText(L["%d of %d posts"]:format(#list, total))
end
