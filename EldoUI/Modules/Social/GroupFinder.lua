-- EldoUI Social: the group finder (group-finder).
--
-- Forever uses the "Vanilla style" premade group finder from
-- Blizzard_GroupFinder_VanillaStyle (load on demand): LFGParentFrame with
-- three pages behind side tabs: browse (LFGBrowseFrame), your listing
-- (LFGListingFrame) and the who list (LFGWhoListFrame). Retail's PVEFrame
-- does not load on Forever.
--   Skin     art-style panels, flat side tabs, rows, buttons, inputs and
--            dropdowns; the who list skin has its own toggle
--   Move     drag by the title bar, scale (Modules/Social.lua window mover)
--   Improve  who list names in class color and levels in difficulty
--            color (Blizzard's listings already color leaders by class)
-- With the switch off (the default) the group finder stays exactly
-- Blizzard's. Nothing is listed, applied for, searched or invited for the
-- player: every button keeps Blizzard's own click.
-- Written from scratch for EldoUI; no code or media from other addons.
local _, E = ...

local M = E:GetModule("Social")
local K = M.kit
local Usable, Try = K.Usable, K.Try

local ID = "group-finder"
local ADDON = "Blizzard_GroupFinder_VanillaStyle"

local function Skin() return M.active and E:BlizzardAllowed(ID, "skin") end
local function Improve() return M.active and E:BlizzardAllowed(ID, "improve") end

local origColor = setmetatable({}, { __mode = "k" }) -- FontString -> { r, g, b } before we colored it

---------------------------------------------------------------------------
-- Who list rows
---------------------------------------------------------------------------
local function Color(fs, r, g, b)
	if not (fs and fs.SetTextColor) then return end
	if not origColor[fs] then origColor[fs] = { fs:GetTextColor() } end
	fs:SetTextColor(r, g, b)
end

local function Uncolor(fs)
	local c = fs and origColor[fs]
	if not c then return end
	fs:SetTextColor(c[1], c[2], c[3])
	origColor[fs] = nil
end

local function StyleWhoRow(row, elementData)
	if not Usable(row) or not M.active then return end
	local db = M.db.lfg
	if Skin() and db.whoSkin then
		E:SkinRecord(ID .. ":who", row, function()
			E:SkinRow(row)
			if row.Selected and row.Selected.SetColorTexture then E:AccentTexture(row.Selected, 0.25) end
			E:SkinButton(row.InviteButton)
			K.NameFonts(db.rowSize or 12, row.Name, row.GuildName)
			K.Fonts(db.rowSize or 12, row.Level, row.Race, row.Class, row.Variable)
		end)
	end
	local info = type(elementData) == "table" and elementData.info
	if not Improve() or type(info) ~= "table" then
		Uncolor(row.Name)
		Uncolor(row.Level)
		return
	end
	local r, g, b = K.ClassRGB(info.filename)
	if db.whoClassColors and r then Color(row.Name, r, g, b) else Uncolor(row.Name) end
	local level = info.level
	if db.whoLevelColors and type(level) == "number" and not K.Secret(level) and type(_G.GetQuestDifficultyColor) == "function" then
		local ok, color = pcall(_G.GetQuestDifficultyColor, level)
		if ok and type(color) == "table" and color.r then Color(row.Level, color.r, color.g, color.b) end
	else
		Uncolor(row.Level)
	end
end

local function WhoBox()
	local who = _G.LFGWhoListFrame
	return who and Usable(who.ScrollBox) and who.ScrollBox or nil
end

local function RefreshWho()
	local box = WhoBox()
	if box and box.ForEachFrame then
		pcall(box.ForEachFrame, box, function(row, data) Try(StyleWhoRow, row, data) end)
	end
end

---------------------------------------------------------------------------
-- Skin
---------------------------------------------------------------------------
-- Find a child under one of a few parents (the listing nests its controls).
local function Find(frame, key, ...)
	if not Usable(frame) then return end
	if frame[key] then return frame[key] end
	for i = 1, select("#", ...) do
		local sub = frame[select(i, ...)]
		if type(sub) == "table" and sub[key] then return sub[key] end
	end
end

local function SkinPage(page)
	if not Usable(page) then return end
	Try(E.SkinPanel, E, page, { transparent = M.db.transparent, close = false })
end

local function SkinBrowse()
	local browse = _G.LFGBrowseFrame
	if not Usable(browse) then return end
	SkinPage(browse)
	E:SkinDropdown(browse.CategoryDropdown)
	E:SkinDropdown(browse.ActivityDropdown)
	E:SkinButton(browse.RefreshButton)
	E:SkinScrollBar(browse.ScrollBar)
	if Usable(browse.ScrollBox) then
		E:HookScrollBoxRows(browse.ScrollBox, function(row)
			E:SkinAlphaZero(row.ResultBG)
			E:SkinRow(row)
			if row.Selected and row.Selected.SetColorTexture then E:AccentTexture(row.Selected, 0.25) end
			if row.Highlight and row.Highlight.SetColorTexture then E:SkinColorTexture(row.Highlight, 1, 1, 1, 0.07) end
			local size = M.db.lfg.rowSize or 12
			-- The group's title is what its leader wrote.
			K.NameFonts(size + 1, row.Name)
			K.Fonts(size + 1, row.CategoryLabel)
			K.Fonts(size, row.Level, row.ActivityName)
		end)
	end
end

local function SkinListing()
	local listing = _G.LFGListingFrame
	if not Usable(listing) then return end
	SkinPage(listing)
	if Usable(listing.RolesSection) then E:StripTextures(listing.RolesSection) end
	if Usable(listing.DividerFrame) then E:SkinAlphaZero(listing.DividerFrame.Divider) end
	E:SkinButton(listing.BackButton)
	E:SkinButton(listing.PostButton)
	E:SkinButton(Find(listing, "RolePollButton", "GroupRoleButtons"))
	E:SkinDropdown(Find(listing, "RoleDropdown", "GroupRoleButtons"))
	local view = listing.ActivityView
	if Usable(view) then
		E:StripTextures(view)
		E:SkinDropdown(view.PlayStyleDropdown)
		E:SkinDropdown(view.VoiceChatDropdown)
		local levels = view.LevelRangesCheckbox
		if Usable(levels) then E:SkinCheckBox(levels.Checkbox) end
		E:SkinScrollBar(view.ScrollBar)
		local comment = view.Comment
		if Usable(comment) then
			E:SkinInset(comment)
			E:SkinScrollBar(comment.ScrollBar)
		end
		if Usable(view.ScrollBox) then
			E:HookScrollBoxRows(view.ScrollBox, function(row)
				E:SkinCheckBox(row.CheckButton)
				local name = row.NameButton and row.NameButton.Name or row.Name
				K.Fonts(M.db.lfg.rowSize or 12, name, row.Level)
			end)
		end
	end
end

local function SkinWho()
	local who = _G.LFGWhoListFrame
	if not Usable(who) then return end
	SkinPage(who)
	E:SkinEditBox(who.EditBox)
	E:SkinButton(who.WhoSearch)
	E:SkinDropdown(who.FilterDropdown)
	E:SkinScrollBar(who.ScrollBar)
	if who.WhoFrameTotals and who.WhoFrameTotals.SetFont then
		K.Fonts(11, who.WhoFrameTotals)
		who.WhoFrameTotals:SetTextColor(unpack(E.media.text.secondary))
	end
end

local function SkinWindow()
	local parent = _G.LFGParentFrame
	E:SkinCloseButton(_G.LFGParentFrameCloseButton)
	Try(SkinBrowse)
	Try(SkinListing)
end

---------------------------------------------------------------------------
-- Part
---------------------------------------------------------------------------
local hooked = false
local function Hook()
	if hooked then return end
	hooked = true
	local box = WhoBox()
	if box and ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
		-- After Blizzard's InitButton has filled the row.
		ScrollUtil.AddInitializedFrameCallback(box, function(_, row, data) Try(StyleWhoRow, row, data) end, origColor, false)
	end
end

M:AddPart({
	id = ID,
	addon = ADDON,
	-- The installer leaves the group finder Blizzard's: turn it on in Blizzard UI if wanted.
	setup = function()
		if not Usable(_G.LFGParentFrame) then error("EldoUI Social: LFGParentFrame is missing") end
		Hook()
	end,
	apply = function(part)
		if Skin() then
			local parent = _G.LFGParentFrame
			E:SkinRecord(ID, parent, function()
				if not part.skinned then
					part.skinned = true
					SkinWindow()
				end
				for _, name in ipairs({ "LFGBrowseFrame", "LFGListingFrame", "LFGWhoListFrame" }) do
					local page = _G[name]
					if Usable(page) then E:SetPanelTransparent(page, M.db.transparent) end
				end
			end)
			-- Side tabs and the who page have switches of their own.
			local tabs = {}
			for _, key in ipairs({ "ListingTab", "BrowsingTab", "WhoListingTab" }) do
				if Usable(parent[key]) then tabs[#tabs + 1] = parent[key] end
			end
			K.Want(part, "sideTabs", tabs, M.db.lfg.sideTabs, function()
				for _, tab in ipairs(tabs) do K.SkinSideTab(tab) end
			end)
			K.Want(part, "who", _G.LFGWhoListFrame, M.db.lfg.whoSkin, function()
				if part.who then return end
				part.who = true
				Try(SkinWho)
			end)
		end
		M:ApplyWindow("lfg")
		RefreshWho()
	end,
	undo = function()
		for fs in pairs(origColor) do Uncolor(fs) end
		M:RestoreWindow("lfg")
	end,
})

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
M:AddOptions({ { type = "tab", label = "Group finder" } })
M:AddOptions(M:SwitchOptions(ID, { { "lfg", "Group finder" } }))
M:AddOptions({
	{ type = "header", label = "Window" },
	{ type = "toggle", disabled = E:BlizzardNeeds(ID, "skin"), key = "lfg.sideTabs", label = "Flat side tabs",
		desc = "The browse / listing / who tabs on the right as flat icon boxes with the accent on the open one." },
	{ type = "range", disabled = E:BlizzardNeeds(ID, "skin"), key = "lfg.rowSize", label = "List text size", min = 9, max = 16, step = 1, desc = "Size of the text in the group, activity and who lists." },
	{ type = "header", label = "Who list" },
	{ type = "toggle", disabled = E:BlizzardNeeds(ID, "skin"), key = "lfg.whoSkin", label = "Who list skin", desc = "Flat rows, search box and filter on the who page." },
	{ type = "toggle", disabled = E:BlizzardNeeds(ID, "improve"), key = "lfg.whoClassColors", label = "Class-colored names", desc = "Names in the who list in their class color." },
	{ type = "toggle", disabled = E:BlizzardNeeds(ID, "improve"), key = "lfg.whoLevelColors", label = "Level in difficulty color",
		desc = "Levels colored like quest difficulty: gray far below you, green, yellow, orange, red above you." },
})
