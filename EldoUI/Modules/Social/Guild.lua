-- EldoUI Social: the guild and communities window (communities-guild).
--
-- Blizzard_Communities: CommunitiesFrame with the community list, the side
-- tabs (chat, roster, guild benefits, guild info, play style), the member
-- roster, guild news and info, and the small guild dialogs (member detail,
-- guild log, text edit, news filters) plus Blizzard_GuildControlUI.
--   Skin     art-style panels, flat side tabs, rows, buttons and inputs
--   Move     drag by the title bar, scale (Modules/Social.lua window mover)
--   Improve  class colors in the roster, also for offline members (dimmed)
-- Blizzard already colors online names by class; EldoUI only re-colors
-- names after Blizzard has drawn the row, from the member info the game
-- gives the roster. Nothing is sent, invited or changed for the player.
-- Written from scratch for EldoUI; no code or media from other addons.
local _, E = ...

local M = E:GetModule("Social")
local K = M.kit
local Usable, Try = K.Usable, K.Try

local ID = "communities-guild"
local ADDON = "Blizzard_Communities"

local function Skin() return M.active and E:BlizzardAllowed(ID, "skin") end
local function Improve() return M.active and E:BlizzardAllowed(ID, "improve") end

local rowColored = setmetatable({}, { __mode = "k" }) -- member row -> true while we colored its name

---------------------------------------------------------------------------
-- Roster rows
---------------------------------------------------------------------------
local function MemberInfo(row)
	if type(row.GetMemberInfo) ~= "function" then return end
	local ok, info = pcall(row.GetMemberInfo, row)
	if ok and type(info) == "table" then return info end
end

-- A roster row: the name, rank, note and info columns are what players
-- named or wrote, so they take the name font; level and zone stay plain.
local function RowFonts(size, name, level, zone, rank, note, guildInfo)
	K.NameFonts(size, name, rank, note, guildInfo)
	K.Fonts(size, level, zone)
end

local function StyleMemberRow(row)
	if not Usable(row) or not M.active then return end
	local db = M.db.guild
	local nameFrame = row.NameFrame
	local name = nameFrame and nameFrame.Name
	if Skin() then
		E:SkinRecord(ID, row, RowFonts, db.rowSize or 12, name, row.Level, row.Zone, row.Rank, row.Note, row.GuildInfo)
		if db.flatRows then E:SkinRecord(ID .. ":rows", row, E.SkinRow, E, row) end
	end
	if not (name and name.SetTextColor) then return end
	if not Improve() then
		rowColored[row] = nil
		return
	end
	local info = MemberInfo(row)
	if not info then return end
	local token = K.ClassToken(nil, nil, info.classID)
	local r, g, b = K.ClassRGB(token)
	if not r then return end
	local offline = Enum and Enum.ClubMemberPresence and info.presence == Enum.ClubMemberPresence.Offline
	if offline then
		if db.offlineClassColors then
			-- Dimmed class color: still readable as offline.
			name:SetTextColor(r * 0.6, g * 0.6, b * 0.6)
			rowColored[row] = true
		end
	elseif db.classColors then
		name:SetTextColor(r, g, b)
		rowColored[row] = true
	end
end

local function MemberList()
	local frame = _G.CommunitiesFrame
	local list = frame and frame.MemberList
	return Usable(list) and list or nil
end

local function RefreshRows()
	local list = MemberList()
	local box = list and list.ScrollBox
	if Usable(box) and box.ForEachFrame then
		pcall(box.ForEachFrame, box, function(row) Try(StyleMemberRow, row) end)
	end
end

local function QueueRows()
	E:Debounce("social:guild", 0, function()
		if M.active then RefreshRows() end
	end)
end

-- Rows Blizzard re-colored since we last touched them come back with
-- Blizzard's colors when Improve goes off: ask the list to redraw.
local function ResetRows()
	wipe(rowColored)
	local list = MemberList()
	if list and type(list.RefreshListDisplay) == "function" and not InCombatLockdown() then
		Try(list.RefreshListDisplay, list)
	end
end

---------------------------------------------------------------------------
-- Skin
---------------------------------------------------------------------------
local function SkinColumnHeaders(display)
	if not Usable(display) then return end
	E:SkinAlphaZero(display.Background, display.TopTileStreaks)
	E:StripTextures(display)
	local pool = display.columnHeaders
	if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
		for header in pool:EnumerateActive() do
			if Usable(header) then
				E:SkinAlphaZero(header.Left, header.Right, header.Middle)
				local text = header.Text or (header.GetFontString and header:GetFontString())
				if text and text.SetFont then
					E:SetFont(text, E.tokens.size.small)
					text:SetTextColor(unpack(E.media.text.secondary))
				end
			end
		end
	end
end

local function SkinCommunityList(list)
	if not Usable(list) then return end
	E:SkinAlphaZero(list.Bg, list.TopFiligree, list.BottomFiligree, list.FilligreeOverlay)
	E:SkinInset(list.InsetFrame)
	E:SkinScrollBar(list.ScrollBar)
	if Usable(list.ScrollBox) then
		E:HookScrollBoxRows(list.ScrollBox, function(row)
			E:SkinAlphaZero(row.Background)
			E:SkinRow(row)
			if row.Selection and row.Selection.SetColorTexture then
				E:AccentTexture(row.Selection, 0.25)
			end
			K.NameFonts(13, row.Name)
		end)
	end
end

local function SkinWindow()
	local frame = _G.CommunitiesFrame
	Try(E.SkinPanel, E, frame, { transparent = M.db.transparent })

	SkinCommunityList(frame.CommunitiesList)
	for _, key in ipairs({ "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab", "GuildPreferredPlaySettingsTab" }) do
		K.SkinSideTab(frame[key])
	end
	for _, key in ipairs({ "StreamDropdown", "GuildMemberListDropdown", "CommunityMemberListDropdown", "CommunitiesListDropdown" }) do
		E:SkinDropdown(frame[key])
	end
	E:SkinButton(frame.InviteButton)
	E:SkinButton(frame.GuildLogButton)
	local control = frame.CommunitiesControlFrame
	if Usable(control) then
		E:SkinButton(control.GuildControlButton)
		E:SkinButton(control.GuildRecruitmentButton)
		E:SkinButton(control.CommunitiesSettingsButton)
	end

	-- Roster.
	local list = frame.MemberList
	if Usable(list) then
		E:StripTextures(list)
		E:SkinInset(list.InsetFrame)
		E:SkinScrollBar(list.ScrollBar)
		E:SkinCheckBox(list.ShowOfflineButton)
		local display = list.ColumnDisplay
		if Usable(display) then
			SkinColumnHeaders(display)
			if type(display.LayoutColumns) == "function" then
				hooksecurefunc(display, "LayoutColumns", function(self)
					if Skin() then E:SkinRecord(ID, self, SkinColumnHeaders, self) end
				end)
			end
		end
	end

	-- Chat.
	local chat = frame.Chat
	if Usable(chat) then
		E:SkinInset(chat.InsetFrame)
		E:SkinScrollBar(chat.ScrollBar)
	end
	E:SkinEditBox(frame.ChatEditBox, { left = 4, right = 2 })

	-- Guild info, news and benefits.
	local details = frame.GuildDetailsFrame
	if Usable(details) then
		E:StripTextures(details)
		for _, key in ipairs({ "Info", "News" }) do
			local sub = details[key]
			if Usable(sub) then
				E:StripTextures(sub)
				if sub.TitleText and sub.TitleText.SetFont then
					E:SetFont(sub.TitleText, E.tokens.size.cardTitle)
					sub.TitleText:SetTextColor(1, 1, 1)
				end
				E:SkinScrollBar(sub.ScrollBar)
			end
		end
	end
	local benefits = frame.GuildBenefitsFrame
	if Usable(benefits) then
		E:StripTextures(benefits)
		for _, key in ipairs({ "Perks", "Rewards" }) do
			local sub = benefits[key]
			if Usable(sub) then
				E:StripTextures(sub)
				E:SkinScrollBar(sub.ScrollBar)
			end
		end
	end

	-- Member detail and the community dialogs.
	local detail = frame.GuildMemberDetailFrame
	if Usable(detail) then
		K.SkinDialog(detail, { close = true })
		E:SkinButton(detail.RemoveButton)
		E:SkinButton(detail.GroupInviteButton)
	end
	for _, key in ipairs({ "EditStreamDialog", "NotificationSettingsDialog", "RecruitmentDialog" }) do
		local dialog = frame[key]
		if Usable(dialog) then K.SkinDialog(dialog) end
	end

	-- Guild windows built on the translucent dialog template.
	for _, name in ipairs({ "CommunitiesGuildLogFrame", "CommunitiesGuildTextEditFrame", "CommunitiesGuildNewsFiltersFrame", "GuildControlUI" }) do
		local window = _G[name]
		if Usable(window) then
			K.SkinDialog(window, { strip = true, close = true })
			E:SkinCloseButton(window.CloseButton or _G[name .. "CloseButton"])
		end
	end
end

---------------------------------------------------------------------------
-- Part
---------------------------------------------------------------------------
local hooked = false
local function Hook()
	if hooked then return end
	hooked = true
	local list = MemberList()
	if list and Usable(list.ScrollBox) and ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
		-- After Blizzard's initializer has drawn the row.
		ScrollUtil.AddInitializedFrameCallback(list.ScrollBox, function(_, row) Try(StyleMemberRow, row) end, M, false)
	end
	for _, event in ipairs({ "CLUB_MEMBER_PRESENCE_UPDATED", "CLUB_MEMBER_UPDATED", "CLUB_MEMBERS_UPDATED", "GUILD_ROSTER_UPDATE" }) do
		E:RegisterEvent(event, function() if M.active then QueueRows() end end, rowColored)
	end
	_G.CommunitiesFrame:HookScript("OnShow", function() if M.active then QueueRows() end end)
end

M:AddPart({
	id = ID,
	addon = ADDON,
	install = { skin = true, improve = true },
	setup = function()
		if not Usable(_G.CommunitiesFrame) then error("EldoUI Social: CommunitiesFrame is missing") end
		Hook()
	end,
	apply = function(part)
		if Skin() then
			E:SkinRecord(ID, _G.CommunitiesFrame, function()
				if not part.skinned then
					part.skinned = true
					SkinWindow()
				end
				E:SetPanelTransparent(_G.CommunitiesFrame, M.db.transparent)
				local chat = _G.CommunitiesFrame.Chat
				local messages = chat and chat.MessageFrame
				if messages and messages.SetFont then
					E:SkinCapture(messages)
					local _, _, flags = messages:GetFont()
					-- What guild members write, in the name font of the theme font.
					pcall(E.SetMessageFont, E, messages, E.media.font, M.db.guild.chatSize or 13, flags or "")
				end
			end)
			-- Flat roster rows have a switch of their own.
			K.Want(part, "rows", nil, M.db.guild.flatRows, function() end)
		end
		if not Improve() and next(rowColored) then ResetRows() end
		M:ApplyWindow("guild")
		RefreshRows()
	end,
	undo = function()
		ResetRows()
		M:RestoreWindow("guild")
	end,
})

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
M:AddOptions({ { type = "tab", label = "Guild" } })
M:AddOptions(M:SwitchOptions(ID, { { "guild", "Guild window" } }))
M:AddOptions({
	{ type = "header", label = "Roster" },
	{ type = "toggle", disabled = E:BlizzardNeeds(ID, "improve"), key = "guild.classColors", label = "Class colors in roster",
		desc = "Member names in their class color, also for community members Blizzard leaves uncolored." },
	{ type = "toggle", disabled = E:BlizzardNeeds(ID, "improve"), key = "guild.offlineClassColors", label = "Class colors for offline members",
		desc = "Offline members keep a dimmed class color instead of plain gray." },
	{ type = "toggle", disabled = E:BlizzardNeeds(ID, "skin"), key = "guild.flatRows", label = "Flat roster rows", desc = "Flat stripes and dividers behind the roster rows." },
	{ type = "range", disabled = E:BlizzardNeeds(ID, "skin"), key = "guild.rowSize", label = "Roster text size", min = 9, max = 16, step = 1, desc = "Size of names, levels, zones, ranks and notes." },
	{ type = "header", label = "Chat" },
	{ type = "range", disabled = E:BlizzardNeeds(ID, "skin"), key = "guild.chatSize", label = "Chat text size", min = 10, max = 20, step = 1,
		desc = "Size of the messages in the communities chat, in the EldoUI font." },
})
