-- EldoUI Chat: Blizzard's chat windows in the EldoUI look and place.
--
-- Everything here is gated by the Blizzard element "chat-frames" (Blizzard
-- UI page). With its master switch off EldoUI leaves Blizzard's
-- chat exactly as Blizzard made it. The sub-switches:
--   skin     flat tabs, a flat edit box, the chat font, whisper tab flash
--            in EldoUI colors
--   move     ChatFrame1, its tabs and edit box sit in the EldoUI_Chat mover
--   replace  EldoUI's chat panel: a flat box (with an optional image) with
--            the tabs sitting on its edge and a slim side rail with the
--            Copy, Find and Errors buttons (the chat windows stay
--            Blizzard's own)
--   hide     hide the chat buttons (menu, channels, voice, social)
--   improve  message extras (Modules/Chat/Messages.lua): short channel
--            names, clickable links, timestamps, name icons, keyword alerts,
--            spam filter, saved history, search, the right chat panel, link
--            tooltips, typed lines between sessions, back-to-newest
--            scrolling, class-colored name mentions, channel sounds
--            Also Lists.lua (list editor window), Colors.lua
--            (chat colors, Quiet text, preview, font and spacing),
--            Senders.lua (icons, levels, names, whisper markers),
--            Filters.lua (blocked phrases, Cyrillic filter, channel
--            mutes), Alerts.lua (keyword list, Alerts tab) and
--            Layout.lua (edit box and tab strip fades).
--
-- Taint rules kept here: Blizzard chat frames are only changed through
-- widget methods and the ScrollingMessageFrame secure mixin (SetFading,
-- SetTimeVisible, TransformMessages ...). No Blizzard function or field is
-- overwritten; the one exception is ChatTypeInfo[type].sticky for Sticky
-- channels, written only where the player changed a tick and put
-- back when it goes off. CVars go through E:SetCVar so
-- "Blizzard default" can put the player's own values back.
local _, E = ...
local L = E.L

local ELEMENT = "chat-frames"

local M = E:NewModule("Chat", {
	title = "Chat",
	desc = "Chat on an EldoUI panel: clean tabs, clickable links, keyword alerts, saved history, search, a right panel and the error log.",
	conflicts = { "EllesmereUIChat", "Prat-3.0", "Chatter" },
	frames = { "EldoUI_Chat", "EldoUI_ChatRight", "EldoUI_EmojiPicker", "EldoUI_EmojiSuggest" },
	movers = { "EldoUI_Chat", "EldoUI_ChatRight" },
	blizzard = { "chat-frames" },
	savedKeys = { "profile.modules.Chat", "global.ChatGuildCache", "private.chatEmoji", "EldoUIMessagesDB" },
	optionsPage = "module:Chat",
	presets = { "Compact", "Glass", "Large", "Split", "Standard", "Tall", "Wide" },
	defaults = {
		-- Panel
		width = 557,
		height = 282,
		panelAlpha = 0.8,
		panelImage = "none",     -- background media id, "custom" or "none"
		panelImagePath = "",
		panelImageAlpha = 0.3,
		fontSize = 14,
		fontOutline = "NONE",
		fontShadow = true,
		chatFont = "theme",      -- "theme" or a font from the media list
		lineSpacing = 0,         -- extra space between chat lines
		tabHeight = 24,
		tabFontSize = 13,
		tabStyle = "underline",  -- underline, background, text
		tabFlash = true,         -- whisper tabs flash (the game's alert), in EldoUI colors
		tabFlashAccent = true,
		tabFlashColor = { 1, 0.5, 1 },
		editBox = "TABS",        -- TABS, ABOVE, BELOW, TOP
		tabsPosition = "top",    -- top, bottom: where the tab strip sits on the panel
		editBoxHeight = 0,       -- 0 = follow the tab height
		editBoxFontSize = 0,     -- 0 = the chat text size
		editBoxFade = false,     -- fade the edit box while it has no focus and no mouse
		editBoxIdleAlpha = 0.4,
		tabsOnHover = false,     -- tab strip only while the mouse is over the chat
		tabsOnHoverFlash = true, -- ... but a flashing tab still shows it
		arrowKeys = true,        -- arrow keys move the cursor in the edit box
		-- Sticky channels: the edit box stays on the chat type you
		-- last sent in. The defaults are the game's own (ChatTypeInfo).
		sticky = { say = true, yell = false, party = true, raid = true, instance = true,
			guild = true, officer = true, whisper = true, channel = true },
		altInvite = false,       -- Alt-click a player name in chat sends one group invite
		whisperInvite = false,
		whisperInviteWord = "inv", -- no-L: player-typed keyword
		copyButton = true,
		searchButton = true,
		-- Buttons (element switch "hide")
		hideMenu = true,
		hideChannel = true,
		hideVoice = true,
		hideSocial = false,
		hideSideBar = true,
		-- Messages (element switch "improve"; see Messages.lua)
		shortChannels = true,
		channelStyle = "number", -- number ([2]) or name ([Trade])
		urls = true,
		urlAccent = true,
		urlColor = { 0.40, 0.80, 1.00 },
		urlBrackets = true,
		urlAutoClose = true,
		timestamps = "KEEP",     -- KEEP (game setting), none, or a date format
		eldoTimestamps = false,  -- EldoUI's own clickable timestamps
		timestampColor = { 0.55, 0.55, 0.6 },
		colorMode = "game",      -- game, channel, quiet
		colors = {},             -- chat type or channel key -> { r, g, b }
		quietTimestamps = true,  -- Quiet text: the game's timestamp in gray
		classNames = "KEEP",     -- KEEP, ON, OFF (Blizzard's chatClassColorOverride)
		nameIcons = "none",      -- none, class, race, both
		nameIconSize = 100,      -- % of the chat font
		nameIconOffset = 0,      -- fine vertical offset in pixels
		nameIconScope = {        -- false = no icons there
			types = { say = true, yell = true, whisper = true, guild = true, party = true, raid = true, instance = true, channel = true, other = true },
			channels = { true, true, true, true, true, true, true, true, true, true },
			tabs = { true, true, true, true, true, true, true, true, true, true },
		},
		showLevel = false,       -- [42] before names, session only
		whisperMarkers = false,  -- short markers instead of "To X:" / "X whispers:"
		whisperIn = ">",
		whisperOut = "<",
		fade = "KEEP",           -- KEEP, never, fade
		fadeTime = 60,
		fadeDuration = 3,
		maxLines = 0,            -- 0 = game default
		linkTooltips = true,     -- hover a link in chat for its tooltip
		linkIcons = true,        -- icon in front of item and spell link names
		linkItemTypes = false,   -- slot and type inside gear links
		questMarks = true,       -- mark after quest links: in your log or done
		mentions = true,         -- names of group, guild and friends in class color
		mentionGroup = true,
		mentionGuild = true,
		mentionFriends = true,
		mentionExclude = "",
		autoScroll = 60,         -- seconds without scrolling before the newest line comes back (0 = off)
		scrollButton = true,     -- jump-to-bottom button while scrolled up
		-- Alerts and filters
		keywords = "",           -- old comma list, moved into keywordList once
		keywordList = {},        -- { word = "tank", sound = "none" or a sound id }
		keywordsPaused = false,
		alertTab = false,        -- copy keyword lines into an "Alerts" chat tab
		keywordName = true,
		keywordColor = { 1, 0.82, 0 },
		keywordAccent = true,
		keywordSound = "kit:TELL_MESSAGE", -- media id (bare SOUNDKIT names are migrated)
		keywordFlash = true,
		whisperSound = "none",   -- extra sound on a whisper (media id; the game plays its own too)
		whisperFlash = false,
		keywordScope = "public", -- public, all
		spamFilter = false,
		spamWindow = 10,
		spamWords = "",          -- old comma list, moved into filterPhrases once
		tradeBoard = false,
		tradeGeneral = true,
		tradeChannel = true,
		tradeLooking = true,
		tradeMinutes = 30,
		tradeWatchWords = "",
		tradeWatchSound = true,
		contentFilters = true,   -- master switch for phrases, script filter and mutes
		filterPhrases = {},      -- blocked words and phrases
		filterWholeWords = false,
		filterScope = "public",  -- public, whispers, all
		filterDisguised = false,
		filterCyrillic = false,
		hideLearning = false,
		hideOthersCrafts = true, -- other players' "X creates Y." lines stay out of chat
		foldRoster = false,      -- a burst of guild join/leave and online/offline lines as one line
		foldFriends = false,     -- ... friends' online/offline lines too
		channelMutes = {},       -- { channel = "Trade", name = "Name-Realm" }
		quietInCombat = true,    -- no alert sounds or flashes in combat
		channelSounds = { guild = "none", officer = "none", party = "none", raid = "none",
			instance = "none", say = "none", yell = "none", channel = "none" },
		-- History
		history = true,
		historyLines = 200,
		historyWhispers = true,
		editHistoryLines = 20,   -- typed lines kept between sessions (0 = off)
		-- Right panel
		rightPanel = false,
		rightWidth = 420,
		rightHeight = 200,
		rightMove = false,       -- remove the lines from the main chat
		rightTitle = "",
		rightGroups = { loot = true, skills = true, channels = false, guild = false, group = false, whisper = false, system = false, npc = false },
		-- Errors
		scriptErrors = "KEEP",   -- KEEP, 1, 0
		errorTabAlways = false,
	},
})
M.element = ELEMENT

-- The side rail is the kit's icon rail (its width and buttons are
-- tokens.rail). The text starts this far inside the box.
local TEXT_INSET = 6
-- Room right of the text for the game's scroll bar (8 wide) and its
-- "back to the newest line" arrow, which reach about 13 pixels past the text.
local SCROLL_ROOM = 13

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local styled = setmetatable({}, { __mode = "k" })    -- Blizzard tab/frame -> parts
local backdrops = setmetatable({}, { __mode = "k" }) -- Blizzard edit box -> our backdrop
local hidden = setmetatable({}, { __mode = "k" })    -- Blizzard frame -> true while EldoUI hides it
local artHidden = {}                                 -- chat frame name -> true while its art is invisible
local arrowMode = setmetatable({}, { __mode = "k" }) -- Blizzard edit box -> its own alt-arrow mode

-- Read-only: the parts EldoUI draws on a chat tab (line, fill, box, lift).
function M:TabParts(tab) return styled[tab] end

function M:IsSecret(value)
	return issecretvalue and issecretvalue(value) or false
end

local function StripTextures(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:IsObjectType("Texture") then region:SetAlpha(0) end
	end
end

local function RestoreTextures(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:IsObjectType("Texture") then region:SetAlpha(1) end
	end
end

function M:Allowed(action)
	return E:BlizzardAllowed(ELEMENT, action)
end

-- The panel is used (positions chat) when either move or replace is on.
function M:PanelMode()
	return self.active and (self:Allowed("replace") or self:Allowed("move"))
end

function M:Outline()
	local outline = self.db.fontOutline
	return (outline == "NONE" or not outline) and "" or outline
end

-- A flat EldoUI button with a text label.
-- The chat windows' buttons are the shared kit's (E.UIKit.Button): the
-- hover and press look, small label.
function M:FlatButton(parent, text, width, height)
	local button = E.UIKit.Button(parent, text, { width = width, height = height, size = E.tokens.size.small })
	-- Strip buttons are narrow: the label may use the whole box.
	button.text:ClearAllPoints()
	button.text:SetPoint("LEFT", 2, 0)
	button.text:SetPoint("RIGHT", -2, 0)
	return button
end

function M:SelectedFrame()
	local dock = GeneralDockManager
	local frame = dock and FCFDock_GetSelectedWindow and FCFDock_GetSelectedWindow(dock)
	return frame or ChatFrame1
end

-- Every Blizzard chat frame that exists right now.
function M:IterateFrames()
	local list = {}
	for _, name in ipairs(CHAT_FRAMES or {}) do
		local frame = _G[name]
		if frame then list[#list + 1] = frame end
	end
	if #list == 0 and ChatFrame1 then list[1] = ChatFrame1 end
	return ipairs(list)
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
function M:TabsAtBottom()
	return self.db.tabsPosition == "bottom"
end

function M:EditBoxHeight()
	local height = tonumber(self.db.editBoxHeight) or 0
	return height > 0 and height or self.db.tabHeight
end

-- The panel strip's edge: TOP or BOTTOM, and the sign that moves inwards.
function M:StripEdge()
	if self:TabsAtBottom() then return "BOTTOM", 1 end
	return "TOP", -1
end

-- The panel is the tab row plus the box under (or over) it. The box is the
-- part that is drawn; the tabs sit on its edge, outside its art, so no tab
-- text ever runs over the frame line or under the messages.
-- ChatFrame1 is an Edit Mode system: its SetPoint tells Edit Mode the
-- frame snapped to whatever it is anchored to. The plain widget methods
-- (SetPointBase, ClearAllPointsBase) place it without that.
local function Anchor(region)
	local set = type(region.SetPointBase) == "function" and region.SetPointBase or region.SetPoint
	local clear = type(region.ClearAllPointsBase) == "function" and region.ClearAllPointsBase or region.ClearAllPoints
	return set, clear
end

-- The drawn box (panel.bg) fills the panel less the tab row; what sits in
-- the box (the messages, the panes) also leaves room for the Info Bar
-- data panels docked along the box's top edge.
function M:PlaceBody(region, inset, left, right)
	local panel, tabs = self.panel, self.db.tabHeight
	inset, left = inset or 0, left or inset or 0
	right = right or inset
	local infoBar = E.modules.InfoBar
	local docked = region ~= panel.bg and infoBar and infoBar.AttachedHeight and infoBar:AttachedHeight("chat") or 0
	local set, clear = Anchor(region)
	clear(region)
	if self:TabsAtBottom() then
		set(region, "TOPLEFT", panel, "TOPLEFT", left, -(inset + docked))
		set(region, "BOTTOMRIGHT", panel, "BOTTOMRIGHT", -right, tabs + inset)
	else
		set(region, "TOPLEFT", panel, "TOPLEFT", left, -(tabs + inset + docked))
		set(region, "BOTTOMRIGHT", panel, "BOTTOMRIGHT", -right, inset)
	end
end

-- Place the messages and any open pane again (the docked panels changed).
function M:RefreshBody()
	if not self.panel then return end
	self:PlaceMainChat()
	if self.errorPane and self.errorPane:IsShown() then self:LayoutPane(self.errorPane) end
	if self.searchPane and self.searchPane:IsShown() then self:LayoutPane(self.searchPane) end
end

-- The side rail shows while one of its buttons does.
function M:RailShown()
	local panel = self.panel
	if not (panel and self:Allowed("replace")) then return false end
	return panel.copy:IsShown() or panel.search:IsShown() or panel.errors:IsShown()
end

-- Space the rail takes from the messages.
function M:RailWidth()
	return self:RailShown() and self.panel.rail:GetWidth() or 0
end

function M:CreatePanel()
	local panel = CreateFrame("Frame", "EldoUI_Chat", UIParent)
	panel:SetFrameStrata("BACKGROUND")
	panel:SetSize(self.db.width, self.db.height)
	panel.bg = CreateFrame("Frame", nil, panel)
	panel.bg:SetAllPoints()
	panel.bg:SetFrameLevel(math.max(panel:GetFrameLevel() - 1, 0))
	-- The tab row: no band of its own, each tab draws its own box. Kept as
	-- an empty texture for the fades.
	panel.strip = panel.bg:CreateTexture(nil, "BORDER")
	panel.strip:SetColorTexture(0, 0, 0, 0)
	-- An optional image behind the chat (Panel > Background opacity, gear).
	panel.image = panel.bg:CreateTexture(nil, "BACKGROUND", nil, 2)
	panel.image:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	panel.image:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	panel.image:Hide()
	self.panel = panel

	-- The side rail: Copy, Find and Errors (with a red count) as icons on
	-- the left edge of the box, so the tab row holds only tabs.
	local magnifier, isAtlas = E:ClientAtlas("common-search-magnifyingglass")
	panel.rail = E.UIKit.IconRail(panel, { side = "LEFT", buttons = {
		{ key = "copy", art = "copy", onClick = function() self:CopyChat() end,
			tipTitle = L["Copy chat"], tip = L["The selected window as plain text, ready to copy."],
			options = { page = "module:Chat", key = "copyButton" } },
		{ key = "search", art = isAtlas and magnifier or nil, glyph = not isAtlas and "?" or nil,
			onClick = function() if self.ToggleSearch then self:ToggleSearch() end end,
			tipTitle = L["Find"], tip = L["Search the selected window."],
			options = { page = "module:Chat", key = "searchButton" } },
		{ key = "errors", glyph = "!", onClick = function() self:ToggleErrors() end,
			tipTitle = L["Errors"], tip = L["The error log: Lua errors are kept here instead of in chat."],
			options = { page = "module:Chat" } },
	} })
	panel.copy, panel.search, panel.errors = panel.rail.buttons.copy, panel.rail.buttons.search, panel.rail.buttons.errors
	for _, button in ipairs({ panel.copy, panel.search, panel.errors }) do
		-- An open pane keeps its button in the accent after the mouse leaves.
		button:HookScript("OnLeave", function() M:UpdateTabs() end)
	end
	panel.errors.badge = E:CreateText(panel.errors, E.tokens.size.tiny)
	panel.errors.badge:SetPoint("CENTER", panel.errors, "TOPRIGHT", -1, -1)
	panel.errors.badge:SetTextColor(E:TokenColor("bad"))

	E:CreateMover(panel, "EldoUI_Chat", L["Chat"], { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 19, 36 },
		{ sizeKeys = { width = { key = "width", min = 300, max = 1200 }, height = { key = "height", min = 120, max = 800 } } })
end

-- The side rail: its buttons from the top, one under the other.
function M:LayoutStrip()
	local panel, db = self.panel, self.db
	local replace = self:Allowed("replace")
	panel.copy:SetShown(replace and db.copyButton)
	panel.search:SetShown(replace and db.searchButton and self.ToggleSearch ~= nil)
	local rail, bottom = panel.rail, self:TabsAtBottom()
	rail:ClearAllPoints()
	rail:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, bottom and 0 or -db.tabHeight)
	rail:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, bottom and db.tabHeight or 0)
	rail:Layout()
	rail:SetShown(self:RailShown())
end

-- Background and strip only in "replace" mode; "move" alone keeps the
-- panel as an invisible box that chat sits in.
function M:ApplyPanelLook()
	local panel, db = self.panel, self.db
	local replace = self:Allowed("replace")
	if replace then
		-- The chat panel's own opacity, kept through art style changes.
		E:SetPanelTemplate(panel.bg, true, db.panelAlpha)
		panel.bg:Show()
		local path = self:PanelImagePath()
		if path then panel.image:SetTexture(path) end
		panel.image:SetAlpha(db.panelImageAlpha)
		panel.image:SetShown(path ~= nil)
	else
		panel.bg:Hide()
		self:UpdateErrorButton()
	end
	-- The drawn box leaves the tab row free.
	self:PlaceBody(panel.bg)
	local edge = self:StripEdge()
	panel.strip:ClearAllPoints()
	panel.strip:SetPoint(edge .. "LEFT", panel, edge .. "LEFT")
	panel.strip:SetPoint(edge .. "RIGHT", panel, edge .. "RIGHT")
	panel.strip:SetHeight(db.tabHeight)
	if not replace then panel.errors:Hide() end
end

-- The background image: a texture from EldoUI's media list (and any
-- SharedMedia backgrounds), or a file path the player typed.
function M:PanelImagePath()
	local db = self.db
	if db.panelImage == "custom" then
		local path = strtrim(tostring(db.panelImagePath or ""))
		return path ~= "" and path or nil
	end
	if db.panelImage == "none" or not db.panelImage then return nil end
	return E.FetchMedia and E:FetchMedia("background", db.panelImage) or nil
end

---------------------------------------------------------------------------
-- Tabs (skin)
---------------------------------------------------------------------------
local placing = false
local clampSaved    -- the main chat's own clamp to the screen, put back on undo

local function IsSecretValue(value)
	return issecretvalue and issecretvalue(value) or false
end

-- While you type with the edit box over the tabs, the box's backdrop lets
-- a little of the strip through: the tab names, the whisper icon, the
-- new-message flash and EldoUI's tab boxes are made invisible meanwhile and
-- come back when the box loses focus. The flash animates its own alpha, so
-- it is muted through its vertex color's alpha, keeping the game's tint.
local tabsMuted = false

-- The edit box over the tabs covers the main window's strip only: the tabs
-- of the windows docked there. A window dragged out of the dock keeps its
-- tab while you type in the main one.
local function DockedFrames()
	local dock = GeneralDockManager
	if not dock then return nil end
	local list = FCFDock_GetChatFrames and FCFDock_GetChatFrames(dock) or dock.DOCKED_CHAT_FRAMES
	if type(list) == "table" and list[1] then return list end
	return nil
end

local function CoveredTab(tab)
	local name = tab and tab.GetName and tab:GetName()
	local frame = name and _G[(name:gsub("Tab$", ""))]
	if not frame then return false end
	local docked = DockedFrames()
	if docked then
		for _, member in ipairs(docked) do
			if member == frame then return true end
		end
		return false
	end
	-- Before the dock lists its windows, the first window is the main one.
	return frame == ChatFrame1 or frame.isDocked and true or false
end

local function MuteTab(tab, muted)
	local data = styled[tab]
	if not data then return end
	local text = tab.Text or _G[tab:GetName() .. "Text"]
	local alpha = muted and 0 or 1
	for _, region in ipairs({ data.box, data.lift, data.fill, data.line, text, tab.conversationIcon }) do
		if type(region) == "table" and region.SetAlpha then region:SetAlpha(alpha) end
	end
	local glow = tab.glow
	if type(glow) == "table" and glow.SetVertexColor and glow.GetVertexColor then
		local r, g, b = glow:GetVertexColor()
		glow:SetVertexColor(r or 1, g or 1, b or 1, alpha)
	end
end

function M:StyleTab(tab)
	if not tab then return end
	local data = styled[tab]
	if not data then
		local line = tab:CreateTexture(nil, "OVERLAY")
		line:SetHeight(2)
		-- On the panel each tab is a flat box on the panel's edge, one pixel
		-- apart from the next; the open one a shade lighter.
		local box = tab:CreateTexture(nil, "BACKGROUND", nil, 0)
		local lift = tab:CreateTexture(nil, "BACKGROUND", nil, 1)
		lift:SetAllPoints(box)
		local fill = tab:CreateTexture(nil, "BACKGROUND", nil, 2)
		fill:SetAllPoints(box)
		data = { line = line, fill = fill, box = box, lift = lift }
		styled[tab] = data
		-- Clicking any chat tab closes an open pane, also when the tab does
		-- not go through FCF_Tab_OnClick.
		tab:HookScript("OnClick", function()
			if M.active and M.paneShown then M:ShowPane(nil) end
		end)
		-- Blizzard shows the tab art again on some updates; keep it hidden
		-- while the skin switch is on.
		tab:HookScript("OnShow", function(shown)
			if M.active and M:Allowed("skin") then
				StripTextures(shown)
				for _, key in ipairs({ "line", "fill", "box", "lift" }) do data[key]:SetAlpha(1) end
			end
		end)
	end
	StripTextures(tab)
	-- The strip above also caught EldoUI's own marks; UpdateTabs shows them.
	for _, key in ipairs({ "line", "fill", "box", "lift" }) do data[key]:SetAlpha(1) end
	self:PaintTabFlash(tab)
	if self:PanelMode() then
		tab:SetHeight(self.db.tabHeight)
		tab:SetHitRectInsets(0, 0, 0, 0)
	end
	-- The box and the underline sit on the side that touches the panel.
	local bottom = self:TabsAtBottom()
	local edge = bottom and "TOP" or "BOTTOM"
	data.box:ClearAllPoints()
	data.box:SetPoint("TOPLEFT", tab, "TOPLEFT", E.pixel, bottom and 0 or -2)
	data.box:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, bottom and 2 or 0)
	data.line:ClearAllPoints()
	data.line:SetPoint(edge .. "LEFT", data.box, edge .. "LEFT", 0, 0)
	data.line:SetPoint(edge .. "RIGHT", data.box, edge .. "RIGHT", 0, 0)
	local text = tab.Text or _G[tab:GetName() .. "Text"]
	if text then
		E:SetFont(text, self.db.tabFontSize)
		text:ClearAllPoints()
		text:SetPoint("CENTER", tab, "CENTER", 0, 0)
	end
	-- The game dims chat tabs to a fifth while the mouse is away, so the
	-- names looked half faded. On the panel the tab boxes and names stay
	-- solid; "Show tabs only on mouse-over" fades them instead.
	self:SetTabSteady(tab, self:PanelMode() and not self.db.tabsOnHover)
	if tabsMuted then MuteTab(tab, CoveredTab(tab)) end
end

function M:SetTabSteady(tab, steady)
	local data = styled[tab]
	if not data then return end
	local text = tab.Text or _G[tab:GetName() .. "Text"]
	for _, region in ipairs({ data.box, data.lift, data.fill, data.line, text }) do
		if region and region.SetIgnoreParentAlpha then region:SetIgnoreParentAlpha(steady and true or false) end
	end
end

function M:MuteTabs(muted)
	muted = muted and self.active and self.db.editBox == "TABS" and self:PanelMode() and true or false
	if muted == tabsMuted then return end
	tabsMuted = muted
	-- Muting covers the docked tabs; unmuting brings every tab back, also
	-- one that left the dock while you typed.
	for _, frame in self:IterateFrames() do
		local tab = _G[frame:GetName() .. "Tab"]
		if tab then MuteTab(tab, muted and CoveredTab(tab)) end
	end
end

function M:TabsMuted()
	return tabsMuted
end

function M:UnstyleTab(tab)
	local data = tab and styled[tab]
	if not data then return end
	if tabsMuted then MuteTab(tab, false) end
	RestoreTextures(tab)
	self:SetTabSteady(tab, false)
	data.line:Hide()
	data.fill:Hide()
	data.box:Hide()
	data.lift:Hide()
	local glow = tab.glow
	if glow and data.glowTexture then
		glow:SetTexture(data.glowTexture)
		glow:SetVertexColor(1, 1, 1, 1)
		data.glowTexture = nil
	end
end

-- Whisper tabs flash through the game's own alert (the tab's glow texture,
-- FCF_StartAlertFlash). With the skin it is a flat bar in the accent or a
-- chosen color; "Flash whisper tabs" off keeps the glow hidden.
function M:TabFlashColor()
	if self.db.tabFlashAccent then return unpack(E.media.accentColor) end
	return unpack(self.db.tabFlashColor)
end

function M:PaintTabFlash(tab)
	local data = styled[tab]
	local glow = tab and tab.glow
	if not (data and glow and glow.SetColorTexture) then return end
	if not data.glowTexture then data.glowTexture = glow:GetTexture() or "Interface\\ChatFrame\\ChatFrameTab-NewMessage" end
	local r, g, b = self:TabFlashColor()
	glow:SetColorTexture(r, g, b, 0.35)
end

function M:UpdateTabs()
	if not self.active then return end
	local selected = self:SelectedFrame()
	local r, g, b = unpack(E.media.accentColor)
	local style = self.db.tabStyle
	local skin = self:Allowed("skin")
	local art = E:ArtStyle()
	local own = E:SkinFlag("selectedTabTint", art) and true or false
	for _, frame in self:IterateFrames() do
		local tab = _G[frame:GetName() .. "Tab"]
		local data = tab and styled[tab]
		if data and skin then
			local isSelected = not self.paneShown and frame == selected
			local text = tab.Text or _G[tab:GetName() .. "Text"]
			if text then
				if isSelected and style ~= "background" then text:SetTextColor(r, g, b)
				elseif isSelected then text:SetTextColor(1, 1, 1)
				else text:SetTextColor(unpack(E.media.text.secondary)) end
			end
			data.line:SetColorTexture(r, g, b, 1)
			data.line:SetShown(isSelected and style == "underline")
			-- WoW Forever and the native skins: the skin's selected-tab color
			-- fills the open tab in every tab style.
			if own then data.fill:SetColorTexture(E:SelectedTabColor(0.6)) else data.fill:SetColorTexture(r, g, b, 0.25) end
			data.fill:SetShown(isSelected and (style == "background" or own))
			-- Boxed tabs on the panel: the panel color, muted when closed.
			local boxed = self:Allowed("replace") and self:PanelMode()
			local br, bg, bb = unpack(E.media.backdropColor)
			data.box:SetColorTexture(br, bg, bb, self.db.panelAlpha * (isSelected and 1 or 0.6))
			data.box:SetShown(boxed)
			local white = E.tokens.hover.control
			data.lift:SetColorTexture(1, 1, 1, white)
			data.lift:SetShown(boxed and isSelected)
		end
	end
	if self.panel then
		local panes = { errors = self.panel.errors, search = self.panel.search }
		for kind, button in pairs(panes) do
			if self.paneShown == kind and not button:IsMouseOver() then button.icon:SetVertexColor(r, g, b) end
			if self.paneShown == kind and button.glyph then button.glyph:SetTextColor(r, g, b) end
		end
	end
	-- The game recolors the tabs (and their flash) while you type: keep
	-- them muted.
	if tabsMuted then
		for _, frame in self:IterateFrames() do
			local tab = _G[frame:GetName() .. "Tab"]
			if tab then MuteTab(tab, CoveredTab(tab)) end
		end
	end
end

---------------------------------------------------------------------------
-- Positions (move)
---------------------------------------------------------------------------
function M:PlaceDock()
	local dock = GeneralDockManager
	if not dock or placing or not self:PanelMode() then return end
	placing = true
	local edge, inward = self:StripEdge()
	dock:ClearAllPoints()
	dock:SetPoint(edge .. "LEFT", self.panel, edge .. "LEFT", 0, 0)
	dock:SetPoint(edge .. "RIGHT", self.panel, edge .. "RIGHT", 0, 0)
	dock:SetHeight(self.db.tabHeight)
	placing = false
	self:AlignDockTabs()
end

-- The game puts the fixed tabs (General, Combat Log) on the dock's bottom
-- edge and the others in a scroll area 31 pixels high that starts at the
-- dock's bottom, so with EldoUI's tab height the other tabs (Whispers,
-- Loot, ...) sat higher than the fixed ones. The scroll area gets the
-- strip's exact height and every tab is centered on the strip; the game's
-- order, widths and overflow width stay.
local SCROLL_EDGE = { LEFT = "TOPLEFT", RIGHT = "TOPRIGHT", TOPLEFT = "TOPLEFT", TOPRIGHT = "TOPRIGHT",
	BOTTOMLEFT = "TOPLEFT", BOTTOMRIGHT = "TOPRIGHT" }

function M:FitDockScroll(scroll, dock)
	local left, right
	for index = 1, scroll:GetNumPoints() do
		local point, relative, relativePoint, x = scroll:GetPoint(index)
		-- The game's own LEFT anchor wins over the TOPLEFT set here before.
		if point == "LEFT" or (point == "TOPLEFT" and not left) then
			left = { relative or dock, SCROLL_EDGE[relativePoint] or "TOPLEFT", x or 0 }
		elseif point == "BOTTOMRIGHT" then
			right = { relative or dock, relativePoint or "BOTTOMRIGHT", x or 0 }
		end
	end
	left = left or { dock, "TOPLEFT", 0 }
	right = right or { dock, "BOTTOMRIGHT", 0 }
	-- The right edge keeps the game's spot (the overflow width) on the
	-- strip's bottom; the left edge starts at the strip's top.
	scroll:ClearAllPoints()
	scroll:SetPoint("TOPLEFT", left[1], left[2], left[3], 0)
	scroll:SetPoint("BOTTOMRIGHT", right[1], right[2], right[3], 0)
end

function M:AlignDockTabs()
	local dock = GeneralDockManager
	if not (dock and self.active and self:PanelMode()) then return end
	local scroll = dock.scrollFrame
	local child = scroll and scroll.GetScrollChild and scroll:GetScrollChild()
	if scroll then self:FitDockScroll(scroll, dock) end
	if child then child:SetHeight(self.db.tabHeight) end
	for _, frame in ipairs(dock.DOCKED_CHAT_FRAMES or {}) do
		local tab = frame.GetName and _G[frame:GetName() .. "Tab"]
		self:FitTabText(tab)
		if tab and tab:GetNumPoints() == 1 then
			local point, relative, _, x = tab:GetPoint(1)
			if point == "BOTTOMLEFT" and relative == dock then
				tab:ClearAllPoints()
				tab:SetPoint("LEFT", dock, "LEFT", x or 0, 0)
			elseif point == "LEFT" and child and relative == child then
				tab:SetPoint("LEFT", child, "LEFT", x or 0, 0)
			end
		end
	end
end

-- The game sizes a tab's name for its own font and padding, so with the
-- EldoUI tab font a name like "Whispers" was cut to "Whis...". The name
-- gets the tab's whole width, less a small margin.
function M:FitTabText(tab)
	if not (tab and styled[tab] and self:Allowed("skin")) then return end
	local text = tab.Text or _G[tab:GetName() .. "Text"]
	local width = tab:GetWidth()
	if not text or IsSecretValue(width) or type(width) ~= "number" or width <= 8 then return end
	text:SetWidth(width - 8)
end

function M:PlaceMainChat()
	if placing or not self:PanelMode() then return end
	placing = true
	local chat = ChatFrame1
	chat:SetMovable(true)
	chat:SetUserPlaced(true)
	-- The game keeps the chat window clamped to the screen with Edit Mode's
	-- wide selection box around it, which pushed the text up into the tab
	-- row near a screen edge. The panel itself stays on screen instead.
	if clampSaved == nil then clampSaved = chat:IsClampedToScreen() and true or false end
	chat:SetClampedToScreen(false)
	-- Inside the box, right of the side rail, with a small inset. The game
	-- draws the window's scroll bar and its "back to the newest line" arrow
	-- right of the text, so the text leaves room for them inside the box.
	local rail = self:RailWidth()
	local right = TEXT_INSET + (chat.ScrollBar and SCROLL_ROOM or 0)
	self:PlaceBody(chat, TEXT_INSET, rail > 0 and rail + TEXT_INSET + 2 or TEXT_INSET, right)
	placing = false
end

-- In the game's "IM" chat style (the default) the edit box stays on screen
-- as a dim bar after you send or press Escape, and a click on a chat tab
-- brings it up again (Deactivate). Over the tab strip that bar covered the
-- tabs and the Errors, Find and Copy buttons and took their clicks. With
-- "Over the tabs" it is hidden whenever it has no focus; Enter, /, R and a
-- link click still open it as usual.
local idleHooked = setmetatable({}, { __mode = "k" })

function M:HidesIdleEditBox()
	return self.active and self:PanelMode() and self.db.editBox == "TABS"
end

function M:HideIdleEditBox(editBox)
	if not (editBox and self:HidesIdleEditBox()) or editBox.isGM then return end
	if editBox:IsShown() and not editBox:HasFocus() then editBox:Hide() end
end

function M:HookIdleEditBox(editBox)
	if idleHooked[editBox] then return end
	idleHooked[editBox] = true
	local function Idle(box)
		M:MuteTabs(false)
		M:HideIdleEditBox(box)
	end
	if type(editBox.Deactivate) == "function" then hooksecurefunc(editBox, "Deactivate", Idle) end
	editBox:HookScript("OnEditFocusLost", Idle)
	editBox:HookScript("OnEditFocusGained", function(box)
		if M:HidesIdleEditBox() and box:HasFocus() then M:MuteTabs(true) end
	end)
end

function M:PlaceEditBox(editBox)
	if not editBox or not self:PanelMode() then
		self:MuteTabs(false)
		return
	end
	local panel, mode = self.panel, self.db.editBox
	if mode ~= "TABS" then self:MuteTabs(false) end
	local height = self:EditBoxHeight()
	editBox:ClearAllPoints()
	if mode == "TABS" then
		-- Over the tab strip while you type, so it never sticks out. With
		-- the tabs at the bottom it covers the bottom strip.
		local edge, inward = self:StripEdge()
		editBox:SetPoint(edge .. "LEFT", panel, edge .. "LEFT", E.pixel, inward * E.pixel)
		editBox:SetPoint(edge .. "RIGHT", panel, edge .. "RIGHT", -E.pixel, inward * E.pixel)
		editBox:SetFrameLevel(panel:GetFrameLevel() + 20)
		self:HookIdleEditBox(editBox)
		self:HideIdleEditBox(editBox)
	elseif mode == "ABOVE" then
		editBox:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 0, 2)
		editBox:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", 0, 2)
	elseif mode == "TOP" then
		editBox:SetPoint("TOP", UIParent, "TOP", 0, -200)
		editBox:SetWidth(self.db.width)
	else
		editBox:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -2)
		editBox:SetPoint("TOPRIGHT", panel, "BOTTOMRIGHT", 0, -2)
	end
	editBox:SetHeight(height)
end

---------------------------------------------------------------------------
-- Edit box and chat frames (skin)
---------------------------------------------------------------------------
function M:StyleEditBox(editBox)
	if not editBox then return end
	local skin = self:Allowed("skin")
	local backdrop = backdrops[editBox]
	if skin then
		if not backdrop then
			backdrop = CreateFrame("Frame", nil, editBox)
			backdrop:SetAllPoints()
			backdrop:SetFrameLevel(math.max(editBox:GetFrameLevel() - 1, 0))
			backdrops[editBox] = backdrop
			editBox:HookScript("OnEditFocusGained", function(box)
				if M.active and M:Allowed("skin") then
					StripTextures(box)
					local bd = backdrops[box]
					if bd then bd:SetBackdropBorderColor(unpack(E.media.accentColor)) end
				end
			end)
			editBox:HookScript("OnEditFocusLost", function(box)
				local bd = backdrops[box]
				if bd and bd.SetBackdropBorderColor then bd:SetBackdropBorderColor(unpack(E.media.borderColor)) end
			end)
		end
		StripTextures(editBox)
		E:SetTemplate(backdrop)
		backdrop:Show()
		local path = self.ChatFontPath and self:ChatFontPath() or E.media.font
		local size = tonumber(self.db.editBoxFontSize) or 0
		if size <= 0 then size = self.db.fontSize end
		-- What the player types and the "Say:" label in front (a whisper names
		-- the other player there) take the name font of the chat font, so
		-- every alphabet keeps its letters.
		local font, _, flags = editBox:GetFont()
		if font then E:SetMessageFont(editBox, path, size, flags or "") end
		for _, label in ipairs({ editBox.header, editBox.headerSuffix }) do
			if type(label) == "table" and label.GetFont then
				local _, _, labelFlags = label:GetFont()
				E:SetMessageFont(label, path, size, labelFlags or "")
			end
		end
	elseif backdrop then
		backdrop:Hide()
		RestoreTextures(editBox)
	end
	if self.db.arrowKeys and self:Allowed("improve") then
		if arrowMode[editBox] == nil then arrowMode[editBox] = editBox:GetAltArrowKeyMode() and true or false end
		editBox:SetAltArrowKeyMode(false)
	elseif arrowMode[editBox] ~= nil then
		editBox:SetAltArrowKeyMode(arrowMode[editBox])
		arrowMode[editBox] = nil
	end
	self:PlaceEditBox(editBox)
	if self.HookEditHistory then self:HookEditHistory(editBox) end
	if self.UpdateEditFade then self:UpdateEditFade(editBox) end
end

-- Blizzard's window background and border (CHAT_FRAME_TEXTURES), shown or
-- made invisible through the vertex color's alpha. The names below are the
-- same suffixes, for a client that doesn't publish the list.
local WINDOW_ART = { "Background", "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
	"LeftTexture", "RightTexture", "BottomTexture", "TopTexture", "ButtonFrameBackground", "ButtonFrameTopLeftTexture",
	"ButtonFrameBottomLeftTexture", "ButtonFrameTopRightTexture", "ButtonFrameBottomRightTexture", "ButtonFrameLeftTexture",
	"ButtonFrameRightTexture", "ButtonFrameBottomTexture", "ButtonFrameTopTexture" }

function M:SetWindowArt(frame, shown)
	local name = frame:GetName()
	if shown and not artHidden[name] then return end
	local list = rawget(_G, "CHAT_FRAME_TEXTURES")
	if type(list) ~= "table" then list = WINDOW_ART end
	for _, suffix in ipairs(list) do
		local region = _G[name .. suffix]
		if region and region.GetVertexColor and region:IsObjectType("Texture") then
			local r, g, b = region:GetVertexColor()
			region:SetVertexColor(r, g, b, shown and 1 or 0)
		end
	end
	artHidden[name] = not shown or nil
end

function M:StyleChatFrame(frame)
	if not frame then return end
	local name = frame:GetName()
	local skin = self:Allowed("skin")
	if skin then
		-- The chat font's name font: messages in every alphabet keep their letters.
		if not E:SetMessageFont(frame, self.ChatFontPath and self:ChatFontPath() or E.media.font, self.db.fontSize, self:Outline()) then
			E:SetMessageFont(frame, E.media.font, self.db.fontSize, self:Outline())
		end
		if self.db.fontShadow then
			frame:SetShadowOffset(1, -1)
			frame:SetShadowColor(0, 0, 0, 1)
		else
			frame:SetShadowOffset(0, 0)
		end
		local tab = _G[name .. "Tab"]
		if tab then self:StyleTab(tab) end
	else
		local tab = _G[name .. "Tab"]
		if tab then self:UnstyleTab(tab) end
	end
	if self.ApplyFrameText then self:ApplyFrameText(frame, skin) end
	-- EldoUI's panel is the background in replace mode. The window art
	-- gets vertex alpha 0 (no Blizzard function or field is used, so the
	-- player's chat window settings and Blizzard's fades stay untouched).
	self:SetWindowArt(frame, not self:Allowed("replace"))
	if self.HookHover then
		self:HookHover(frame)
		self:HookHover(_G[name .. "Tab"])
	end
	self:StyleEditBox(frame.editBox or _G[name .. "EditBox"])
	if self.StyleMessages then self:StyleMessages(frame) end
end

---------------------------------------------------------------------------
-- Chat buttons (hide)
---------------------------------------------------------------------------
local BUTTON_GROUPS = {
	hideMenu = { "ChatFrameMenuButton" },
	hideChannel = { "ChatFrameChannelButton" },
	hideVoice = { "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton", "TextToSpeechButtonFrame" },
	hideSocial = { "QuickJoinToastButton" },
}

local function WantsHidden(frame)
	local key = hidden[frame]
	return key and M.active and M:Allowed("hide") and M.db[key] and true or false
end

local function HideNow(frame)
	if E.FrameCheck(frame, "IsProtected") and InCombatLockdown() then return end
	frame:Hide()
end

-- Hide a Blizzard frame while its setting is on; Blizzard shows some of
-- these again on updates, so the OnShow hook keeps them hidden.
local hooked = setmetatable({}, { __mode = "k" })
local function HideButton(frame, key)
	if not frame then return end
	hidden[frame] = key
	if not hooked[frame] then
		hooked[frame] = { wasShown = frame:IsShown() }
		frame:HookScript("OnShow", function(self)
			if WantsHidden(self) then HideNow(self) end
		end)
	end
	if WantsHidden(frame) then
		HideNow(frame)
	elseif hooked[frame].hiddenByUs then
		frame:Show()
	end
	hooked[frame].hiddenByUs = WantsHidden(frame)
end

function M:ApplyButtons()
	for key, names in pairs(BUTTON_GROUPS) do
		for _, name in ipairs(names) do HideButton(_G[name], key) end
	end
	for _, frame in self:IterateFrames() do
		HideButton(frame.buttonFrame or _G[frame:GetName() .. "ButtonFrame"], "hideSideBar")
	end
end

function M:RestoreButtons()
	for frame, data in pairs(hooked) do
		hidden[frame] = nil
		if data.hiddenByUs then
			data.hiddenByUs = false
			if data.wasShown then frame:Show() end
		end
	end
end

---------------------------------------------------------------------------
-- CVars: only while the element is on, through E:SetCVar
---------------------------------------------------------------------------
function M:ApplyCVars()
	if not E:BlizzardAllowed(ELEMENT) then return end
	local db = self.db
	local improve = self:Allowed("improve")
	-- A setting back on "Keep game setting" (or Improve off) gives the
	-- player's own game value back; the other values set it.
	if improve and db.eldoTimestamps then
		E:SetCVar("showTimestamps", "none", ELEMENT)
	elseif improve and db.timestamps ~= "KEEP" then
		E:SetCVar("showTimestamps", db.timestamps, ELEMENT)
	else
		E:RestoreCVar("showTimestamps", ELEMENT)
	end
	if improve and db.classNames == "ON" then
		E:SetCVar("chatClassColorOverride", "0", ELEMENT)
	elseif improve and db.classNames == "OFF" then
		E:SetCVar("chatClassColorOverride", "1", ELEMENT)
	else
		E:RestoreCVar("chatClassColorOverride", ELEMENT)
	end
end

---------------------------------------------------------------------------
-- Sticky channels: after you send a line, the edit box stays on that
-- chat type when its tick is on. Blizzard reads ChatTypeInfo[type].sticky
-- (1 or 0) when a line is sent; EldoUI writes only that one field, only
-- where the tick differs from the game's value, and puts the game's value
-- back when the tick, the Improve switch or the module goes off.
---------------------------------------------------------------------------
M.STICKY_TYPES = {
	{ "say", E.Key("Say"), { "SAY" } },
	{ "yell", E.Key("Yell"), { "YELL" } },
	{ "party", E.Key("Party"), { "PARTY" } },
	{ "raid", E.Key("Raid"), { "RAID" } },
	{ "instance", E.Key("Instance"), { "INSTANCE_CHAT" } },
	{ "guild", E.Key("Guild"), { "GUILD" } },
	{ "officer", E.Key("Officer"), { "OFFICER" } },
	{ "whisper", E.Key("Whispers"), { "WHISPER", "BN_WHISPER" } },
	{ "channel", E.Key("Numbered channels"), { "CHANNEL" }, true },
}
local stickyOriginal = {} -- chat type -> the game's sticky value, while EldoUI changed it

local function StickyKeys(entry)
	local keys = {}
	for _, key in ipairs(entry[3]) do keys[#keys + 1] = key end
	if entry[4] then
		for index = 1, 20 do keys[#keys + 1] = "CHANNEL" .. index end
	end
	return keys
end

function M:ApplySticky(off)
	local info = rawget(_G, "ChatTypeInfo")
	if type(info) ~= "table" then return end
	local want = not off and self.active and self:Allowed("improve")
	local ticks = type(self.db.sticky) == "table" and self.db.sticky or {}
	for _, entry in ipairs(self.STICKY_TYPES) do
		for _, key in ipairs(StickyKeys(entry)) do
			local row = info[key]
			if type(row) == "table" then
				local game = stickyOriginal[key]
				if game == nil then game = row.sticky end
				local value = game
				if want and ticks[entry[1]] ~= nil then value = ticks[entry[1]] and 1 or 0 end
				if value ~= row.sticky then row.sticky = value end
				if value ~= game then
					stickyOriginal[key] = game
				else
					stickyOriginal[key] = nil
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Whisper your target: /eui tt opens the edit box as a whisper
-- to the target. Only for a player whose name the game shows (never a
-- secret name). The edit box is opened by the game's own ChatFrameUtil.
---------------------------------------------------------------------------
function M:WhisperTarget()
	local exists = UnitExists and UnitExists("target")
	local player = not self:IsSecret(exists) and exists and UnitIsPlayer and UnitIsPlayer("target")
	if self:IsSecret(player) or not player then
		E:Print(L["Target a player first."])
		return
	end
	-- On Forever the second value of UnitName is the surname, not a realm:
	-- the name comes from E:UnitWhisperName, as the game's own
	-- Whisper button builds it.
	local name = E:UnitWhisperName("target")
	if type(name) ~= "string" or name == "" then
		E:Print(L["The game does not show this name right now."])
		return
	end
	local util = rawget(_G, "ChatFrameUtil")
	-- A name with a surname has a space, which a typed "/w" line would cut:
	-- the game's own SendTell sets the whisper target as one name.
	local tell = util and util.SendTell or rawget(_G, "ChatFrame_SendTell")
	if type(tell) == "function" then
		tell(name)
		return
	end
	local open = util and util.OpenChat or rawget(_G, "ChatFrame_OpenChat")
	if type(open) ~= "function" then return end
	open(("%s %s "):format(rawget(_G, "SLASH_WHISPER1") or "/w", name))
end
E:NameBinding("BINDING_NAME_ELDOUI_WHISPER_TARGET", E.Key("Whisper your target"))

E:AddCommand("tt", "whisper your target: opens the chat box as /w <name>", function() M:WhisperTarget() end, "Tools")

---------------------------------------------------------------------------
-- Apply / undo
---------------------------------------------------------------------------
function M:Apply()
	if not self.active then return end
	local panel, db = self.panel, self.db
	local panelMode = self:PanelMode()
	panel:SetShown(panelMode)
	panel:SetSize(db.width, db.height)
	if panelMode then
		self:ApplyPanelLook()
		-- The Errors button decides whether the side rail shows.
		self.applying = true
		self:UpdateErrorButton()
		self.applying = nil
		self:LayoutStrip()
		self:PlaceMainChat()
		self:PlaceDock()
	end
	for _, frame in self:IterateFrames() do self:StyleChatFrame(frame) end
	self:ApplyButtons()
	self:UpdateTabs()
	self:UpdateErrorButton()
	self:ApplyCVars()
	self:ApplySticky()
	self:RefreshWhisperInvites()
	if self.ApplyMessages then self:ApplyMessages() end
	if self.errorPane and panelMode then self:LayoutPane(self.errorPane) end
	if self.searchPane and panelMode then self:LayoutPane(self.searchPane) end
	if not panelMode then self:ClosePanes() end
	if self.ApplyFades then self:ApplyFades() end
end

-- Back to Blizzard as far as possible without a reload. Positions come
-- back with Edit Mode after /reload (the handler asks for it).
function M:RestoreBlizzard()
	self:RefreshWhisperInvites()
	if self.panel then self.panel:Hide() end
	self:ClosePanes()
	for _, frame in self:IterateFrames() do
		local name = frame:GetName()
		local tab = _G[name .. "Tab"]
		if tab then self:UnstyleTab(tab) end
		local editBox = frame.editBox or _G[name .. "EditBox"]
		if editBox and backdrops[editBox] then
			backdrops[editBox]:Hide()
			RestoreTextures(editBox)
		end
		if editBox and arrowMode[editBox] ~= nil then
			editBox:SetAltArrowKeyMode(arrowMode[editBox])
			arrowMode[editBox] = nil
		end
		self:SetWindowArt(frame, true)
	end
	if clampSaved ~= nil and ChatFrame1 then
		ChatFrame1:SetClampedToScreen(clampSaved)
		clampSaved = nil
	end
	self:RestoreButtons()
	self:ApplySticky(true)
	if self.RestoreFades then self:RestoreFades() end
	if self.RestoreMessages then self:RestoreMessages() end
end

E:RegisterBlizzardHandler(ELEMENT, {
	owner = "Chat",
	apply = function() if M.active then M:Apply() end end,
	undo = function() M:RestoreBlizzard() end,
	reload = { skin = true, move = true, replace = true },
	install = { skin = true, move = true, replace = true, hide = true, improve = true },
	legacy = function() return M.db and M.db.enabled end,
})

---------------------------------------------------------------------------
-- Copy chat: the selected window's lines as plain text
---------------------------------------------------------------------------
function M:PlainText(text)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	text = text:gsub("|H.-|h(.-)|h", "%1")
	text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
	return E.MaskProtectedNames(text)
end

function M:CopyChat()
	local frame = self:SelectedFrame()
	local lines = {}
	for index = 1, frame:GetNumMessages() do
		local text = frame:GetMessageInfo(index)
		if type(text) == "string" and not self:IsSecret(text) then table.insert(lines, self:PlainText(text)) end
	end
	E:ShowCopyBox(L["Copy chat"], L["Select what you need and press Ctrl+C. Lines the game keeps secret are left out."], table.concat(lines, "\n"))
end

---------------------------------------------------------------------------
-- Panes over the chat area (Errors, Search)
---------------------------------------------------------------------------
local paneCount = 0

function M:CreatePane()
	-- Named so Escape closes it (UISpecialFrames); the Errors and Find
	-- buttons, a close button and a click on any chat tab close it too.
	paneCount = paneCount + 1
	local pane = CreateFrame("Frame", "EldoUI_ChatPane" .. paneCount, self.panel)
	pane:SetFrameStrata("MEDIUM")
	pane:EnableMouse(true)
	pane.bg = pane:CreateTexture(nil, "BACKGROUND")
	pane.bg:SetAllPoints()
	pane:SetScript("OnHide", function(closed)
		if (self.paneShown == "errors" and closed == self.errorPane) or (self.paneShown == "search" and closed == self.searchPane) then
			self.paneShown = nil
			self:UpdateTabs()
		end
	end)
	tinsert(UISpecialFrames, pane:GetName())
	pane:Hide()
	return pane
end

function M:LayoutPane(pane)
	-- Over the messages, right of the side rail.
	self:PlaceBody(pane, 2, self:RailWidth() + 2)
	local r, g, b = unpack(E.media.backdropColor)
	pane.bg:SetColorTexture(r, g, b, 1)
	if pane.Layout then pane:Layout() end
end

function M:ClosePanes()
	if self.errorPane then self.errorPane:Hide() end
	if self.searchPane then self.searchPane:Hide() end
	self.paneShown = nil
end

-- Show one pane (or none). Returns false when there is no panel to show it on.
function M:ShowPane(kind)
	if not (self.panel and self.panel:IsShown() and self:Allowed("replace")) then return false end
	if self.errorPane then self.errorPane:SetShown(kind == "errors") end
	if self.searchPane then self.searchPane:SetShown(kind == "search") end
	self.paneShown = kind
	self:UpdateTabs()
	if self.UpdateTabFade then self:UpdateTabFade() end
	return true
end

---------------------------------------------------------------------------
-- Errors tab: the log from Core\Errors.lua in its own pane
---------------------------------------------------------------------------
local Errors = E.errors
local ROW_HEIGHT = 16

function M:UpdateErrorButton()
	if not self.panel then return end
	local button = self.panel.errors
	local count = #Errors.entries
	local shown = self:Allowed("replace") and (self.db.errorTabAlways or count > 0)
	local railBefore = self:RailShown()
	button:SetShown(shown)
	-- The first error can bring the rail in: the messages make room for it.
	if not self.applying and railBefore ~= self:RailShown() and self.active and self:PanelMode() then self:Reapply() end
	button.badge:SetText(Errors.unseen > 0 and (Errors.unseen > 99 and "99+" or Errors.unseen) or "")
	if self.errorPane and self.errorPane:IsShown() then self:RefreshErrors() end
end

function M:FilteredErrors()
	local list = {}
	for _, entry in ipairs(Errors.entries) do
		if self.errorFilter ~= "session" or entry.session == Errors.session then table.insert(list, entry) end
	end
	table.sort(list, function(a, b) return (a.last or 0) > (b.last or 0) end)
	return list
end

function M:CreateErrorPane()
	local pane = self:CreatePane()
	self.errorPane = pane
	self.errorFilter = "all"
	self.errorOffset = 0

	-- Toolbar
	local all = self:FlatButton(pane, L["All"], 40, 18)
	all:SetPoint("TOPLEFT", 0, 0)
	all:SetScript("OnClick", function() self.errorFilter = "all"; self.errorOffset = 0; self:RefreshErrors() end)
	local session = self:FlatButton(pane, L["This session"], 80, 18)
	session:SetPoint("LEFT", all, "RIGHT", 4, 0)
	session:SetScript("OnClick", function() self.errorFilter = "session"; self.errorOffset = 0; self:RefreshErrors() end)
	pane.filters = { all = all, session = session }

	local close = E.UIKit.IconButton(pane, 18, "cross", nil, L["Close"])
	close:SetPoint("TOPRIGHT", 0, 0)
	close:SetScript("OnClick", function() self:ToggleErrors(false) end)
	pane.close = close
	local clear = self:FlatButton(pane, L["Clear"], 44, 18)
	clear:SetPoint("RIGHT", close, "LEFT", -4, 0)
	clear:SetScript("OnClick", function() E:AskClearErrorLog(function() self.selectedError = nil end) end)
	pane.clear = clear
	local copyAll = self:FlatButton(pane, L["Copy all"], 56, 18)
	copyAll:SetPoint("RIGHT", clear, "LEFT", -4, 0)
	copyAll:SetScript("OnClick", function()
		local parts = {}
		for _, entry in ipairs(self:FilteredErrors()) do table.insert(parts, Errors:Format(entry)) end
		E:ShowCopyBox(L["EldoUI error log"], L["Everything is selected. Press Ctrl+C."], table.concat(parts, "\n\n"))
	end)
	local issue = self:FlatButton(pane, L["As issue"], 56, 18)
	issue:SetPoint("RIGHT", copyAll, "LEFT", -4, 0)
	issue:SetScript("OnClick", function()
		if self.selectedError then
			E:ShowCopyBox(L["Error as GitHub issue"], L["Markdown with the context. Press Ctrl+C and paste it into a new issue."], Errors:ReportText(self.selectedError))
		end
	end)
	local copy = self:FlatButton(pane, L["Copy"], 40, 18)
	copy:SetPoint("RIGHT", issue, "LEFT", -4, 0)
	copy:SetScript("OnClick", function()
		if self.selectedError then
			E:ShowCopyBox(L["Error"], L["Everything is selected. Press Ctrl+C."], Errors:Format(self.selectedError))
		end
	end)
	-- The same log in its own window, with more room and filters.
	local open = self:FlatButton(pane, L["Open window"], 80, 18)
	open:SetPoint("RIGHT", copy, "LEFT", -4, 0)
	open:SetScript("OnClick", function()
		self:ToggleErrors(false)
		E:ToggleErrorWindow(true)
	end)
	E.UIKit.Tooltip(open, L["Open window"], L["Open the error log in its own window, with filters and room for long errors."])

	pane.status = E:CreateText(pane, E.tokens.size.tiny, "LEFT")
	pane.status:SetPoint("LEFT", session, "RIGHT", 8, 0)
	pane.status:SetTextColor(unpack(E.media.text.secondary))

	-- List on the left, newest first; the wheel scrolls it.
	local list = CreateFrame("Frame", nil, pane)
	list:SetPoint("TOPLEFT", 0, -22)
	list:SetPoint("BOTTOMLEFT", 0, 0)
	E:SetTemplate(list, true)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		self.errorOffset = math.max(0, self.errorOffset - delta * 3)
		self:RefreshErrors()
	end)
	pane.list = list
	pane.rows = {}

	-- Details on the right, scrollable.
	local scroll = CreateFrame("ScrollFrame", nil, pane)
	scroll:SetPoint("TOPLEFT", list, "TOPRIGHT", 6, -4)
	scroll:SetPoint("BOTTOMRIGHT", -4, 4)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(1, 1)
	scroll:SetScrollChild(child)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(frame, delta)
		local maximum = math.max(child:GetHeight() - frame:GetHeight(), 0)
		frame:SetVerticalScroll(math.min(math.max(frame:GetVerticalScroll() - delta * 30, 0), maximum))
	end)
	pane.detail = child:CreateFontString(nil, "OVERLAY")
	E:SetFont(pane.detail, E.tokens.size.small)
	pane.detail:SetPoint("TOPLEFT")
	pane.detail:SetJustifyH("LEFT")
	pane.detail:SetJustifyV("TOP")
	pane.detail:SetWordWrap(true)
	pane.scroll, pane.child = scroll, child

	function pane.Layout()
		pane.list:SetWidth(math.floor((self.db.width - 12) * 0.45))
		pane.child:SetWidth(math.max(self.db.width * 0.55 - 30, 50))
		pane.detail:SetWidth(pane.child:GetWidth())
		self:RefreshErrors()
	end
end

function M:RefreshErrors()
	local pane = self.errorPane
	if not pane then return end
	local entries = self:FilteredErrors()
	local listHeight = math.max(self.db.height - self.db.tabHeight - 34, ROW_HEIGHT)
	local visible = math.floor((listHeight - 4) / ROW_HEIGHT)
	self.errorOffset = math.min(self.errorOffset, math.max(#entries - visible, 0))
	local r, g, b = unpack(E.media.accentColor)

	for index = 1, math.max(visible, #pane.rows) do
		local row = pane.rows[index]
		if not row and index <= visible then
			row = CreateFrame("Button", nil, pane.list)
			row:SetHeight(ROW_HEIGHT)
			row:SetPoint("TOPLEFT", 2, -2 - (index - 1) * ROW_HEIGHT)
			row:SetPoint("TOPRIGHT", -2, -2 - (index - 1) * ROW_HEIGHT)
			row.highlight = row:CreateTexture(nil, "BACKGROUND")
			row.highlight:SetAllPoints()
			row.text = E:CreateText(row, E.tokens.size.small, "LEFT")
			row.text:SetPoint("LEFT", 3, 0)
			row.text:SetPoint("RIGHT", -3, 0)
			row:SetScript("OnClick", function(button)
				self.selectedError = button.entry
				self:RefreshErrors()
			end)
			pane.rows[index] = row
		end
		if row then
			local entry = index <= visible and entries[index + self.errorOffset]
			row.entry = entry or nil
			row:SetShown(entry and true or false)
			if entry then
				-- An entry with no type is an error, as in the error window.
				local first = (entry.message or ""):match("^[^\n]*")
				local kind = (entry.kind or "error") == "error" and "" or (E:TextHex("warn") .. entry.kind .. "|r ")
				row.text:SetText((E:TextHex("secondary") .. "%s|r " .. E:TextHex("bad") .. "x%d|r %s%s"):format(E:FormatTime(entry.last or 0), entry.count or 1, kind, first))
				row.highlight:SetColorTexture(r, g, b, entry == self.selectedError and 0.25 or 0)
			end
		end
	end

	for key, button in pairs(pane.filters) do
		if key == self.errorFilter then button.text:SetTextColor(r, g, b) else button.text:SetTextColor(unpack(E.media.text.secondary)) end
	end
	local status = L["%d logged"]:format(#Errors.entries)
	if Errors.dropped > 0 then status = L["%d logged, %d skipped (too many at once)"]:format(#Errors.entries, Errors.dropped) end
	pane.status:SetText(status)

	local entry = self.selectedError or entries[1]
	if entry then
		-- Month name and the clock style from General, readable in every region.
		local stamp = "%b %d " .. (E:Clock24() and "%H:%M:%S" or "%I:%M:%S %p")
		local head = (E:TextHex("secondary") .. E:Plural(entry.count, "First %s, last %s, %d time", "First %s, last %s, %d times") .. "|r\n" .. E:TextHex("accent") .. "%s|r\n\n"):format(
			date(stamp, entry.first or entry.last), date(stamp, entry.last or entry.first), entry.count or 1, entry.addon or L["Unknown addon"])
		-- A Lua stack indents its lines with tabs, which a text line cannot
		-- draw: they show as four spaces.
		local stack = (entry.stack or ""):gsub("\t", "    ")
		local message = (entry.message or ""):gsub("\t", "    ")
		pane.detail:SetText(head .. message .. (stack ~= "" and ("\n\n" .. E:TextHex("secondary") .. stack .. "|r") or ""))
	else
		pane.detail:SetText(E:TextHex("secondary") .. L["No errors logged. Nice."] .. "|r")
	end
	pane.child:SetHeight(pane.detail:GetStringHeight() + 8)
end

function M:ToggleErrors(show)
	if not (self.panel and self.panel:IsShown() and self:Allowed("replace")) then
		-- No EldoUI chat panel: the log window does the same job.
		if show ~= false then E:ToggleErrorWindow(true) end
		return
	end
	if not self.errorPane then
		self:CreateErrorPane()
		self:LayoutPane(self.errorPane)
	end
	if show == nil then show = not self.errorPane:IsShown() end
	if show then
		self:ShowPane("errors")
		self.panel.errors:Show()
		self:LayoutPane(self.errorPane)
		Errors:MarkSeen()
	elseif self.paneShown == "errors" then
		self:ShowPane(nil)
	end
	self:UpdateTabs()
end

---------------------------------------------------------------------------
-- Debug view: outline each frame and print where it sits
---------------------------------------------------------------------------
local outlines = {}

local function Describe(label, frame)
	if not frame then return ("%s: missing"):format(label) end
	local point, relative, relPoint, x, y = frame:GetPoint(1)
	local left, right, top, bottom = 0, 0, 0, 0
	if frame.GetHitRectInsets then left, right, top, bottom = frame:GetHitRectInsets() end
	return ("%s: %dx%d at %s %s %s %.0f,%.0f  hit %d/%d/%d/%d  %s %d %s"):format(label,
		frame:GetWidth(), frame:GetHeight(), tostring(point), relative and (relative.GetName and relative:GetName() or "?") or "nil",
		tostring(relPoint), x or 0, y or 0, left, right, top, bottom,
		E.FrameStrata(frame, "?"), E.FrameLevel(frame, -1), frame:IsShown() and "shown" or "hidden")
end

-- One color per part, shared by the outlines and the chat legend: the
-- color-blind safe set (E.tokens.palette.safe).
local DEBUG_COLORS = { panel = "sky", chat = "green", dock = "yellow", tabs = "vermilion", edit = "orange" }

local function DebugColor(part)
	return E.tokens.palette.safe[DEBUG_COLORS[part]]
end

local function DebugWord(part, word)
	return E:TokenHex(DebugColor(part)) .. word .. "|r"
end

local function Outline(frame, part)
	if not frame then return end
	local r, g, b = unpack(DebugColor(part))
	local box = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	box:SetFrameStrata("TOOLTIP")
	box:SetPoint("TOPLEFT", frame, "TOPLEFT")
	box:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
	box:SetBackdrop({ edgeFile = E.media.flat, edgeSize = E:PixelFor(box) }) -- one screen pixel
	box:SetBackdropBorderColor(r, g, b, 1)
	box:EnableMouse(false)
	table.insert(outlines, box)
end

function M:ToggleDebug()
	if #outlines > 0 then
		for _, box in ipairs(outlines) do box:Hide() end
		wipe(outlines)
		E:PrintSwitch(L["Chat debug"], false)
		return
	end
	E:PrintSwitch(L["Chat debug"], true)
	E:Print(L["Outlines: %s, %s, %s, %s, %s. Run it again to turn off."]:format(DebugWord("panel", L["panel"]),
		DebugWord("chat", L["chat"]), DebugWord("dock", L["dock"]), DebugWord("tabs", L["tabs"]), DebugWord("edit", L["edit box"])))
	Outline(self.panel, "panel")
	Outline(ChatFrame1, "chat")
	Outline(GeneralDockManager, "dock")
	Outline(ChatFrame1EditBox, "edit")
	print(Describe("  panel", self.panel))
	print(Describe("  ChatFrame1", ChatFrame1))
	print(Describe("  dock", GeneralDockManager))
	print(Describe("  edit box", ChatFrame1EditBox))
	for _, frame in self:IterateFrames() do
		local tab = _G[frame:GetName() .. "Tab"]
		if tab and tab:IsShown() then
			Outline(tab, "tabs")
			print(Describe("  " .. tab:GetName(), tab))
		end
	end
	local element = E:BlizzardState(ELEMENT) or {}
	print(("  element %s: skin %s, move %s, replace %s, hide %s, improve %s"):format(tostring(element.enabled),
		tostring(self:Allowed("skin")), tostring(self:Allowed("move")), tostring(self:Allowed("replace")),
		tostring(self:Allowed("hide")), tostring(self:Allowed("improve"))))
end

---------------------------------------------------------------------------
-- Enable / disable
---------------------------------------------------------------------------
function M:Reapply()
	if not self.active then return end
	-- Keyed: calls in combat (whisper tabs, dock changes) run once after it.
	E:Debounce("chat:reapply", 0, function()
		E:RunOutOfCombat(function() M:Apply() end, "chat:apply")
	end)
end

function M:InstallHooks()
	-- Edit Mode and chat setup move these back; put them where we want them.
	hooksecurefunc(ChatFrame1, "SetPoint", function()
		if self.active and not placing and self:PanelMode() then
			C_Timer.After(0, function() E:RunOutOfCombat(function() self:PlaceMainChat() end, "chat:placeMain") end)
		end
	end)
	if GeneralDockManager then
		hooksecurefunc(GeneralDockManager, "SetPoint", function()
			if self.active and not placing and self:PanelMode() then C_Timer.After(0, function() self:PlaceDock() end) end
		end)
	end
	if FCF_DockUpdate then hooksecurefunc("FCF_DockUpdate", function() self:Reapply() end) end
	if FCFDock_UpdateTabs then hooksecurefunc("FCFDock_UpdateTabs", function() self:AlignDockTabs() end) end
	-- ChatFrame1 is an Edit Mode system on Forever: a layout update and the
	-- game saving a window position (chat setup, drags) can leave it at the
	-- game's spot. The main chat goes back into the panel afterwards.
	local editMode = _G.EditModeManagerFrame
	if editMode and type(editMode.UpdateLayoutInfo) == "function" then
		hooksecurefunc(editMode, "UpdateLayoutInfo", function() self:Reapply() end)
	end
	if FCF_SavePositionAndDimensions then hooksecurefunc("FCF_SavePositionAndDimensions", function() self:Reapply() end) end
	if FCF_OpenTemporaryWindow then hooksecurefunc("FCF_OpenTemporaryWindow", function() self:Reapply() end) end
	if FCF_OpenNewWindow then hooksecurefunc("FCF_OpenNewWindow", function() self:Reapply() end) end
	if FCFDock_SelectWindow then
		hooksecurefunc("FCFDock_SelectWindow", function()
			if self.active then
				if self.paneShown then self:ShowPane(nil) end
				self:UpdateTabs()
			end
		end)
	end
	if FCF_Tab_OnClick then
		hooksecurefunc("FCF_Tab_OnClick", function(_, button)
			if self.active and button == "LeftButton" and self.paneShown then self:ShowPane(nil) end
		end)
	end
	-- A color change from Blizzard's chat settings resets the vertex alpha.
	if FCF_SetWindowColor then
		hooksecurefunc("FCF_SetWindowColor", function(frame)
			if self.active and self:Allowed("replace") and frame then self:SetWindowArt(frame, false) end
		end)
	end
	if FCFTab_UpdateColors then
		hooksecurefunc("FCFTab_UpdateColors", function() if self.active then self:UpdateTabs() end end)
	end
	-- Whisper tab alert: EldoUI colors, or no glow at all.
	if FCF_StartAlertFlash then
		hooksecurefunc("FCF_StartAlertFlash", function(frame)
			if self.NoteTabFlash then self:NoteTabFlash(frame, true) end
			if not (self.active and self:Allowed("skin") and frame and frame.GetName) then return end
			local tab = _G[frame:GetName() .. "Tab"]
			if not (tab and tab.glow and styled[tab]) then return end
			if self.db.tabFlash then
				self:PaintTabFlash(tab)
			else
				tab.glow:Hide()
			end
		end)
	end
	if FCF_StopAlertFlash then
		hooksecurefunc("FCF_StopAlertFlash", function(frame)
			if self.NoteTabFlash then self:NoteTabFlash(frame, false) end
		end)
	end
	-- Shift + mouse wheel (Messages.lua) is a hook on each window's own
	-- OnMouseWheel script.
	Errors:OnChange(self, function() self:UpdateErrorButton() end)
end

function M:OnEnable()
	self:RefreshWhisperInvites()
	-- The error window setting moved to General > Lua errors: carry over a
	-- choice made here once (the key stays for old profiles).
	if self.db.scriptErrors == "1" or self.db.scriptErrors == "0" then
		E.db.general.errorPopup = self.db.scriptErrors == "1" and "SHOW" or "HIDE"
		self.db.scriptErrors = "KEEP"
		E.errors:ApplyPopup()
	end
	E:RunOutOfCombat(function()
		if not self.panel then
			self:CreatePanel()
			self:InstallHooks()
		end
		if self.EnableMessages then self:EnableMessages() end
		self:Apply()
	end)
	self:RegisterEvent("UPDATE_CHAT_WINDOWS", function() M:Reapply() end)
	self:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS", function() M:Reapply() end)
end

-- Blizzard's chat look comes back fully with a reload.
function M:OnDisable()
	if self.SyncTradeBoard then self:SyncTradeBoard() end
	self:RefreshWhisperInvites()
	self:MuteTabs(false)
	self:UnregisterEvent("UPDATE_CHAT_WINDOWS")
	self:UnregisterEvent("UPDATE_FLOATING_CHAT_WINDOWS")
	E:RunOutOfCombat(function() self:RestoreBlizzard() end)
	-- The game settings EldoUI changed for chat go back to the player's own.
	E:RestoreCVars(ELEMENT)
	if self.DisableMessages then self:DisableMessages() end
	E:ShowReloadPrompt(L["Chat switched off. Blizzard's chat look comes fully back after a reload."])
end

function M:OnProfileChanged()
	if self.SyncTradeBoard then self:SyncTradeBoard() end
	self:RefreshWhisperInvites()
	if self.active then E:RunOutOfCombat(function() self:Apply() end, "chat:apply") end
	-- Held guild and friend notices are written out when folding goes off.
	if self.FlushRosterBursts and not (self.active and self.db.foldRoster) then self:FlushRosterBursts() end
	-- Chat bubbles use the chat font too.
	local bubbles = E.modules and E.modules.ChatBubbles
	if bubbles and bubbles.active and bubbles.ApplyFont then bubbles:ApplyFont() end
end

E:AddCommand("chatdebug", "outline the chat frames and print their positions", function()
	if M.active and M.panel then M:ToggleDebug() elseif not M.active then E:Print(E:ModuleOffHint("Chat")) end
end, "Troubleshooting")

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local function NotReplace() return not M:Allowed("replace") end
local function NotEldoStamp() return not M.db.eldoTimestamps end
local function NotFade() return M.db.fade ~= "fade" end
local function NotRight() return not M.db.rightPanel end

local RIGHT_GROUPS = {
	{ "loot", E.Key("Loot, money and currency") },
	{ "skills", E.Key("Skill-ups, XP, honor and reputation") },
	{ "channels", E.Key("Public channels (Trade, General, LFG)") },
	{ "guild", E.Key("Guild and officer") },
	{ "group", E.Key("Party, raid and instance") },
	{ "whisper", E.Key("Whispers") },
	{ "system", E.Key("System messages") },
	{ "npc", E.Key("NPC and boss speech") },
}
M.rightGroupList = RIGHT_GROUPS

-- Size, offset and where the name icons show.
-- Grayed rows say why: the reason shows in their tooltip.
local function NoIcons()
	if M.db.nameIcons == "none" then return L["Pick an icon under \"%s\" first."]:format(L["Icons before names"]) end
end
local IconCog = {
	{ type = "range", key = "nameIconSize", label = "Icon size", unit = "%", min = 50, max = 150, step = 5, disabled = NoIcons,
		desc = "Size of the name icons compared with the chat text." },
	{ type = "range", unit = "px", key = "nameIconOffset", label = "Y offset", min = -6, max = 6, step = 1, disabled = NoIcons,
		desc = "Moves the icons up (positive) or down (negative) by a few pixels, for fonts that sit higher or lower." },
}
for _, entry in ipairs({ { "say", "Say and emote" }, { "yell", E.Key("Yell") }, { "whisper", "Whispers" }, { "guild", E.Key("Guild and officer") },
	{ "party", "Party" }, { "raid", "Raid" }, { "instance", "Instance" }, { "channel", E.Key("Numbered channels") }, { "other", E.Key("Everything else") } }) do
	local function What() return E:Translate(entry[2]):lower() end
	IconCog[#IconCog + 1] = { type = "toggle", key = "nameIconScope.types." .. entry[1], label = "Icons in %s", labelFill = What, disabled = NoIcons,
		desc = "Show the name icons in %s lines.", descFill = What }
end
local function ScopeRow(kind, index, label, what)
	return { type = "toggle", key = ("nameIconScope.%s.%d"):format(kind, index), label = label, labelFill = index, disabled = NoIcons,
		desc = what, descFill = index }
end
local IconChannelCog, IconTabCog = {}, {}
for index = 1, 10 do
	IconChannelCog[#IconChannelCog + 1] = ScopeRow("channels", index, E.Key("Channel %d"), E.Key("Show the name icons in channel %d."))
	IconTabCog[#IconTabCog + 1] = ScopeRow("tabs", index, E.Key("Chat tab %d"), E.Key("Show the name icons in chat tab %d (counted from the left in the chat settings)."))
end

-- One tick per chat type for Sticky channels.
local StickyCog = {}
for _, entry in ipairs(M.STICKY_TYPES) do
	StickyCog[#StickyCog + 1] = { type = "toggle", key = "sticky." .. entry[1], label = entry[2],
		desc = "After you send a line in %s, the edit box stays there for the next line. Off: it goes back to the last sticky chat type.",
		descFill = function() return L[entry[2]]:lower() end }
end

local function PanelImages()
	local values = E.MediaValues and E:MediaValues("background") or {}
	values.none = "None"
	values.custom = "Your own file"
	return values
end

-- One sound picker per channel (the events are in Messages.lua).
local ChannelSoundOptions = {}
for _, entry in ipairs({ { "guild", E.Key("Guild") }, { "officer", E.Key("Officer") }, { "party", E.Key("Party") }, { "raid", E.Key("Raid and raid warning") },
	{ "instance", E.Key("Instance") }, { "say", E.Key("Say") }, { "yell", E.Key("Yell") }, { "channel", E.Key("Public channels") } }) do
	ChannelSoundOptions[#ChannelSoundOptions + 1] = { type = "media", mediaKind = "sound", none = true, key = "channelSounds." .. entry[1],
		label = entry[2], desc = "Played when someone else writes in %s chat.", descFill = function() return L[entry[2]]:lower() end }
end

M.options = {
	{ type = "tab", label = "Panel" },
	{ type = "description", label = "What EldoUI may do with Blizzard's chat is set on the Blizzard UI page. These settings shape what each switch does." },
	{ type = "header", label = "Size and look" },
	{ type = "range", unit = "px", key = "width", label = "Width", min = 300, max = 1200, step = 1, desc = "Width of the chat panel." },
	{ type = "range", unit = "px", key = "height", label = "Height", min = 120, max = 800, step = 1, desc = "Height of the chat panel." },
	{ type = "range", key = "panelAlpha", label = "Background opacity", percent = true, min = 0, max = 1, step = 0.05, desc = "How dark the panel behind the chat is (panel mode only).",
		cog = {
			{ type = "select", key = "panelImage", label = "Background image", values = PanelImages,
				desc = "A picture behind the chat text: a background from EldoUI's media list (SharedMedia packs add more), or your own file." },
			{ type = "input", key = "panelImagePath", label = "Image file", hidden = function() return M.db.panelImage ~= "custom" end,
				desc = "Path of your own image, for example Interface\\AddOns\\MyMedia\\chat.tga (a .tga or .blp in an addon folder)." },
			{ type = "range", percent = true, key = "panelImageAlpha", label = "Image opacity", min = 0.05, max = 1, step = 0.05, hidden = function() return M.db.panelImage == "none" end,
				desc = "How strongly the image shows through." },
		} },
	{ type = "range", key = "fontSize", label = "Text size", min = 8, max = 24, step = 1, desc = "Size of the chat text (skin switch)." },
	{ type = "select", key = "fontOutline", label = "Outline", values = { NONE = "None", OUTLINE = "Outline", THICKOUTLINE = "Thick outline" },
		desc = "Outline around the chat text (skin switch)." },
	{ type = "toggle", key = "fontShadow", label = "Text shadow", desc = "A soft shadow under the chat text, so it reads on bright ground." },
	{ type = "media", mediaKind = "font", key = "chatFont", label = "Chat font", default = "theme", defaultLabel = "Theme font",
		desc = "The font of the chat windows and the edit box (skin switch). Theme font follows EldoUI's font; any EldoUI or SharedMedia font can be picked." },
	{ type = "range", unit = "px", key = "lineSpacing", label = "Line spacing", min = 0, max = 8, step = 1,
		zeroText = "Game", desc = "Extra space between chat lines, in pixels (skin switch). Game keeps the game's spacing." },
	{ type = "header", label = "Tabs and edit box" },
	{ type = "range", unit = "px", key = "tabHeight", label = "Tab height", min = 18, max = 40, step = 1, desc = "Height of the tab strip and the tabs in it." },
	{ type = "range", key = "tabFontSize", label = "Tab text size", min = 8, max = 18, step = 1, desc = "Text size on the tabs." },
	{ type = "toggle", key = "tabFlash", label = "Flash whisper tabs", desc = "A tab that gets a whisper while you look at another tab flashes (the game's alert, in the EldoUI look). Off: it stays still. Skin switch.",
		cog = {
			{ type = "toggle", key = "tabFlashAccent", label = "Flash in accent color", desc = "Off uses the color below." },
			{ type = "color", key = "tabFlashColor", label = "Flash color", desc = "Color of the flashing whisper tab.", hidden = function() return M.db.tabFlashAccent end },
		} },
	{ type = "select", key = "tabStyle", label = "Active tab", values = { underline = "Accent underline", background = "Accent background", text = "Accent text only" }, -- no-L: select value, translated by Core/Config.lua
		desc = "How the selected tab is marked." },
	{ type = "select", key = "tabsPosition", label = "Tab strip", values = { top = "Top of the panel", bottom = "Bottom of the panel" },
		desc = "Where the tabs and the Errors, Find and Copy buttons sit: above or under the messages (move switch). The right panel's title follows." },
	{ type = "toggle", key = "tabsOnHover", label = "Show tabs only on mouse-over",
		desc = "The tabs and the side rail fade out while the mouse is not over the chat and come back when you point at it. Off by default.",
		cog = {
			{ type = "toggle", key = "tabsOnHoverFlash", label = "Show the tabs while one flashes",
				desc = "A tab that flashes (a whisper in another tab) brings the strip back, so you never miss it." },
		} },
	{ type = "select", key = "editBox", label = "Edit box position",
		desc = "Over the tabs: the box covers the tab strip while you type. Top of screen: centered near the top.",
		values = { TABS = "Over the tabs", ABOVE = "Above the chat", BELOW = "Below the chat", TOP = "Top of screen" } },
	{ type = "range", unit = "px", key = "editBoxHeight", label = "Edit box height", min = 0, max = 40, step = 1,
		zeroText = "Auto", desc = "Height of the box you type in. Auto follows the tab height. The width is always the panel width." },
	{ type = "range", key = "editBoxFontSize", label = "Edit box text size", min = 0, max = 24, step = 1,
		zeroText = "Auto", desc = "Text size in the box you type in (skin switch). Auto uses the chat text size." },
	{ type = "toggle", key = "editBoxFade", label = "Fade the edit box when idle",
		desc = "While the box is shown but you are not typing and the mouse is not over it, it fades to the opacity in the gear. Typing or pointing at it brings it back at once.",
		cog = {
			{ type = "range", percent = true, key = "editBoxIdleAlpha", label = "Idle opacity", min = 0, max = 1, step = 0.05,
				desc = "How visible the idle edit box stays. 0 is invisible until you point at it or type." },
		} },
	{ type = "toggle", key = "arrowKeys", label = "Arrow keys move the cursor", desc = "Left and right move the cursor in the edit box without holding Alt. Up and down still browse what you typed." },
	{ type = "cog", label = "Sticky channels", options = StickyCog,
		desc = "Which chat types the edit box stays on after you send a line, one tick each. The ticks start as the game has them: everything but yell. Needs the Blizzard UI switch Improve." },
	{ type = "header", label = "Strip buttons" },
	{ type = "toggle", key = "copyButton", label = "Copy button", desc = "A Copy button on the chat's side rail: the selected window as plain text.", hidden = NotReplace },
	{ type = "toggle", key = "searchButton", label = "Search button", desc = "A Find button on the chat's side rail that searches the selected window.", hidden = NotReplace },
	{ type = "header", label = "Chat buttons" },
	{ type = "description", label = "Hidden while the Blizzard UI switch Hide is on for chat windows." },
	{ type = "toggle", key = "hideMenu", label = "Hide the chat menu button", desc = "The speech-bubble button with the emote and language menus. /s, /p and right-clicking a tab still work." },
	{ type = "toggle", key = "hideChannel", label = "Hide the channels button", desc = "Opens the channel list; /chatlist and the social panel still work." },
	{ type = "toggle", key = "hideVoice", label = "Hide voice and speech buttons", desc = "Voice mute, deafen and text-to-speech buttons." },
	{ type = "toggle", key = "hideSocial", label = "Hide the Quick Join toast", desc = "The social button with Quick Join toasts above the chat." },
	{ type = "toggle", key = "hideSideBar", label = "Hide the side bar", desc = "The thin button bar beside every chat window (scroll and minimize buttons)." },

	{ type = "tab", label = "Messages" },
	{ type = "preview", label = "Preview", height = 132, desc = "Sample lines drawn with your current chat settings.",
		create = function(canvas) if M.DrawPreview then M:DrawPreview(canvas) end end,
		update = function(canvas) if M.DrawPreview then M:DrawPreview(canvas) end end },
	{ type = "description", label = "Message extras need the Blizzard UI switch Improve. During boss fights chat text shows untouched." },
	{ type = "header", label = "Colors" },
	{ type = "select", key = "colorMode", label = "Chat colors",
		values = { game = "Game colors", channel = "My colors", quiet = "My colors, quiet text" },
		desc = "Game colors keeps the game's chat colors. My colors uses the colors from Edit chat colors. Quiet text draws the message in a calm gray; channel and sender keep their color." },
	{ type = "execute", label = "Edit chat colors", desc = "A color per chat type (say, guild, party ...) and per joined channel. Channels keep their color when their number changes.",
		func = function() if M.OpenColorEditor then M:OpenColorEditor() end end },
	{ type = "toggle", key = "quietTimestamps", label = "Gray timestamps", hidden = function() return M.db.colorMode ~= "quiet" end,
		desc = "With quiet text, the game's timestamp in front of a line is gray too." },
	{ type = "header", label = "Channels and names" },
	{ type = "toggle", key = "linkTooltips", label = "Link tooltips on hover", desc = "Point at an item, spell, quest, achievement, currency or talent link in chat to see its tooltip, where your tooltips usually show." },
	{ type = "toggle", key = "mentions", label = "Known names in class color", desc = "Names of your group, guild and friends inside other players' lines get their class color. Not during boss fights.",
		cog = {
			{ type = "toggle", key = "mentionGroup", label = "Group", desc = "Party and raid members." },
			{ type = "toggle", key = "mentionGuild", label = "Guild", desc = "Guild members (as the guild list knows them)." },
			{ type = "toggle", key = "mentionFriends", label = "Friends", desc = "Characters on your friends list." },
			{ type = "input", key = "mentionExclude", label = "Never color", desc = "Comma-separated names that stay plain, for example names that are also common words." },
		} },
	{ type = "toggle", key = "shortChannels", label = "Short channel names", desc = "[2. Trade - City] becomes [2] or [Trade], [Guild] becomes [G]." },
	{ type = "select", key = "channelStyle", label = "Short channel style", values = { number = "Number: [2]", name = "Name: [Trade]" }, dependsOn = "shortChannels",
		desc = "How numbered channels are shortened." },
	{ type = "select", key = "classNames", label = "Class-colored names",
		values = { KEEP = "Game setting", ON = "Always", OFF = "Never" },
		desc = "Blizzard's own option for coloring names by class in every channel." },
	{ type = "select", key = "nameIcons", label = "Icons before names",
		values = { none = "None", class = "Class icon", race = "Race icon", both = "Race and class" },
		desc = "A small class or race icon (the game's own art) in front of player names. The gear sets their size, offset and where they show.",
		cog = IconCog },
	{ type = "cog", label = "Name icons per channel", options = IconChannelCog,
		desc = "Turn the name icons off in single numbered channels, for example a busy trade channel." },
	{ type = "cog", label = "Name icons per chat tab", options = IconTabCog,
		desc = "Turn the name icons off in single chat tabs." },
	{ type = "toggle", key = "showLevel", label = "Level before names",
		desc = "The sender's level as [42] before the name, in the game's difficulty color, for levels the game has shown you this session. Off by default." },
	{ type = "toggle", key = "whisperMarkers", label = "Whisper markers",
		desc = "\"To Name:\" and \"Name whispers:\" become short markers, for example > Name: (received, accent color) and < Name: (sent, gray). Battle.net whispers too. Only the wording around the name changes.",
		cog = {
			{ type = "input", key = "whisperIn", label = "Received marker", desc = "Up to 16 characters in front of whispers you receive. Empty uses >." },
			{ type = "input", key = "whisperOut", label = "Sent marker", desc = "Up to 16 characters in front of whispers you send. Empty uses <." },
		} },
	{ type = "toggle", key = "altInvite", label = "Alt-click a name to invite", acts = true,
		desc = "Alt-click a player's name in chat to send one group invite. Not in combat. Other clicks on names work as before. Off by default." },
	{ type = "toggle", key = "whisperInvite", label = "Invite by whisper keyword", acts = true,
		desc = "Acts for you when turned on: sends a group invite when a player's regular whisper exactly matches your keyword. Out of combat only. Off by default.",
		disabled = E:BlizzardNeeds(ELEMENT, "improve") },
	{ type = "input", key = "whisperInviteWord", label = "Invite keyword", dependsOn = "whisperInvite",
		desc = "A regular whisper must match this text exactly, including case and spaces. Leave empty to pause invites." },
	{ type = "header", label = "Timestamps" },
	{ type = "select", key = "timestamps", label = "Game timestamps",
		values = { KEEP = "Keep game setting", none = "None", ["%H:%M "] = "15:04", ["%H:%M:%S "] = "15:04:05", ["%I:%M "] = "03:04", ["%I:%M %p "] = "03:04 PM",
			["%d/%m %H:%M "] = "31/12 15:04", ["%d/%m %H:%M:%S "] = "31/12 15:04:05" },
		desc = "Blizzard's own timestamp setting (Social options)." },
	{ type = "toggle", key = "eldoTimestamps", label = "EldoUI timestamps",
		desc = "Gray [15:04] in front of every line. Click one to copy that line. Replaces the game's timestamps while on." },
	{ type = "color", key = "timestampColor", label = "Timestamp color", desc = "Color of EldoUI's timestamps.", hidden = NotEldoStamp },
	{ type = "header", label = "Links" },
	{ type = "toggle", key = "urls", label = "Clickable links", desc = "Web addresses in chat become links. Click one, then press Ctrl+C to copy it. Shift+click puts it into an open chat edit box." },
	{ less = true, type = "toggle", key = "urlAccent", label = "Links in accent color", desc = "Off uses the link color below.", dependsOn = "urls" },
	{ less = true, type = "color", key = "urlColor", label = "Link color", desc = "Color of clickable links.", dependsOn = "urls", hidden = function() return M.db.urlAccent end },
	{ type = "toggle", key = "urlBrackets", label = "Brackets around links", desc = "Shows links as [example.com].", dependsOn = "urls" },
	{ type = "toggle", key = "urlAutoClose", label = "Close the copy box after Ctrl+C", desc = "The link box closes itself once you copied.", dependsOn = "urls" },
	{ type = "toggle", key = "linkIcons", label = "Icons on item and spell links", desc = "Item and spell links in chat show their icon in front of the name, at the height of the chat text. The link works as before." },
	{ type = "toggle", key = "linkItemTypes", label = "Slot and type on item links",
		desc = "Gear links in chat show their equipment slot and armor or weapon type. Off by default." },
	{ type = "toggle", key = "questMarks", label = "Quest status marks", desc = "A small mark after a quest link: a tick when you have done the quest, the quest icon when it is in your quest log. Nothing when neither or unknown." },
	{ type = "header", label = "Fading" },
	{ type = "select", key = "fade", label = "Fade old lines", values = { KEEP = "Game default", never = "Never", fade = "After a set time" },
		desc = "When chat lines fade out. Scrolling or hovering shows them again." },
	{ type = "range", key = "fadeTime", label = "Visible for", unit = "s", min = 5, max = 600, step = 5, hidden = NotFade, desc = "How long a line stays before it fades." },
	{ type = "range", key = "fadeDuration", label = "Fade duration", unit = "s", min = 0.5, max = 10, step = 0.5, hidden = NotFade, desc = "How long the fade itself takes." },
	{ type = "range", key = "maxLines", label = "Lines kept per window", min = 0, max = 2000, step = 50,
		zeroText = "Game", desc = "How far you can scroll back. Game keeps the game's default." },
	{ type = "header", label = "Scrolling" },
	{ type = "range", key = "autoScroll", label = "Back to the newest line after", unit = "s", min = 0, max = 300, step = 5,
		zeroText = "Never", desc = "When you scrolled up and leave the chat alone this long, it jumps back to the newest line (not while the mouse is over it)." },
	{ type = "toggle", key = "scrollButton", label = "Jump to newest button", desc = "A small arrow in the corner of a chat window while it is scrolled up; it turns accent when new lines arrive. Shift + mouse wheel jumps to the top or bottom." },

	{ type = "tab", label = "Alerts and filters" },
	{ type = "header", label = "Keyword alert" },
	{ type = "description", label = "Lines that mention one of your keywords are highlighted and can play a sound. Paused during boss fights." },
	{ type = "execute", label = "Edit keywords", desc = "The keyword list (up to 50), with a sound per keyword and Pause. Also /eui chat alerts, and /eui chat alert <word> adds or removes one.",
		func = function() if M.OpenKeywordEditor then M:OpenKeywordEditor() end end },
	{ type = "toggle", key = "keywordsPaused", label = "Pause keyword alerts", desc = "Stops highlights, sounds and Alerts tab copies for all keywords. The list stays saved." },
	{ type = "toggle", key = "keywordName", label = "Alert on your name", desc = "Your character's name counts as a keyword." },
	{ type = "media", mediaKind = "sound", none = true, key = "keywordSound", label = "Name alert sound", dependsOn = "keywordName",
		desc = "Played when a line mentions your name. Every other keyword has its own sound in Edit keywords. At most one sound every 2 seconds." },
	{ less = true, type = "toggle", key = "keywordAccent", label = "Highlight in accent color", desc = "Off uses the color below." },
	{ less = true, type = "color", key = "keywordColor", label = "Highlight color", desc = "Color of a matched keyword.", hidden = function() return M.db.keywordAccent end },
	{ type = "toggle", key = "keywordFlash", label = "Flash the game icon", desc = "Flashes the WoW icon in the taskbar when the game is in the background." },
	{ type = "select", key = "keywordScope", label = "Listen in", values = { public = "Public channels, say and yell", all = "All chat except your own lines" },
		desc = "Where keywords are looked for." },
	{ type = "header", label = "Alerts tab" },
	{ type = "toggle", key = "alertTab", label = "Copy matches to an Alerts tab",
		desc = "Every line with a keyword is also copied into an Alerts chat tab, with time, source and a clickable name, also from channels no tab shows. The tab flashes on new lines. Off by default." },
	{ type = "preview", label = "Alerts tab status", height = 22, hidden = function() return not M.db.alertTab end,
		desc = "Whether the Alerts tab is ready, or why matches are waiting.",
		create = function(canvas)
			if not canvas then return end
			canvas.status = E:CreateText(canvas, E.tokens.size.label, "LEFT")
			canvas.status:SetPoint("LEFT", 4, 0)
			canvas.status:SetPoint("RIGHT", -4, 0)
			canvas.status:SetText(M.AlertStatus and M:AlertStatus() or "")
		end,
		update = function(canvas) if canvas and canvas.status and M.AlertStatus then canvas.status:SetText(M:AlertStatus()) end end },
	{ type = "execute", label = "Open Alerts tab", hidden = function() return not M.db.alertTab end,
		desc = "Makes the Alerts tab now (outside combat) and shows it. Close it like any chat tab; the next match makes it again while this option is on.",
		func = function() if M.OpenAlertTab then M:OpenAlertTab() end end },
	{ type = "header", label = "Whisper alert" },
	{ type = "media", mediaKind = "sound", none = true, key = "whisperSound", label = "Whisper sound",
		desc = "An extra sound when someone whispers you (also Battle.net whispers). The game's own whisper sound still plays. Instant Messages plays this same sound, so a whisper sounds once." },
	{ type = "toggle", key = "whisperFlash", label = "Flash the game icon on whispers", desc = "Flashes the WoW icon in the taskbar when a whisper arrives." },
	{ type = "header", label = "Alert sounds" },
	{ type = "toggle", key = "quietInCombat", label = "No alert sounds in combat", desc = "Skips keyword, whisper and channel sounds, the taskbar flash and the Instant Messages whisper sound in combat. The game's own whisper sound still plays." },
	{ type = "header", label = "Channel sounds" },
	{ type = "cog", label = "Sound per channel", options = ChannelSoundOptions,
		desc = "A sound when someone else writes in guild, party, raid or another channel. None by default." },
	{ type = "header", label = "Content filters" },
	{ type = "description", label = "Filters only change what you see: nothing is sent and your /ignore list is untouched. Hidden lines stay out of the Alerts tab and history." },
	{ type = "toggle", key = "contentFilters", label = "Enable", desc = "Master switch for blocked phrases, the Cyrillic filter and channel mutes. Off pauses them; the lists stay saved. The editors show whether they are on." },
	{ type = "execute", label = "Blocked phrases", desc = "Edit the list of words and phrases that hide a line (up to 50), and test a line against it. Also /eui chat filters.",
		func = function() if M.OpenPhraseEditor then M:OpenPhraseEditor() end end },
	{ type = "execute", label = "Channel mutes", desc = "Players hidden in one public channel only (up to 50). Also /eui chat mute <channel>; <name>, or right-click a sender in a channel line.",
		func = function() if M.OpenMuteEditor then M:OpenMuteEditor() end end },
	{ type = "toggle", key = "filterWholeWords", label = "Whole words only", dependsOn = "contentFilters",
		desc = "A phrase matches only as a whole word: \"gold\" hides \"buy gold\" but not \"goldfish\"." },
	{ type = "select", key = "filterScope", label = "Blocked phrases apply to", dependsOn = "contentFilters", wide = true,
		values = { public = "Channels, say, yell, emote", whispers = "Public channels and whispers from strangers", all = "All chat except your own lines" },
		desc = "Where blocked phrases and the Cyrillic filter look. Friends, guild members, and group members are always shown." },
	{ type = "toggle", key = "filterDisguised", label = "Also catch disguised spellings", dependsOn = "contentFilters",
		desc = "Match your blocked phrases across punctuation, spacing, and common look-alike letters. Off by default." },
	{ type = "toggle", key = "filterCyrillic", label = "Hide Cyrillic lines", dependsOn = "contentFilters",
		desc = "Hides lines that contain Cyrillic letters. It looks at the letters, not the language. Off by default." },
	{ type = "header", label = "Crafting" },
	{ type = "toggle", key = "hideOthersCrafts", label = "Hide other players' crafting", desc = "Lines like \"Name creates Item.\" from players near you stay out of chat, so the Loot tab shows only what you craft yourself. Your own crafts always show." },
	{ type = "toggle", key = "hideLearning", label = "Hide learn/unlearn lines", desc = "Hides system messages about learning or unlearning spells, abilities, and passive effects." },
	{ type = "header", label = "Guild and friend notices" },
	{ type = "toggle", key = "foldRoster", label = "Fold join and online notices",
		desc = "A burst of guild join, leave, online and offline lines shows as one line per kind, such as \"5 more came online: Name, Name ...\". Point at [all] for every name. Off by default." },
	{ type = "toggle", key = "foldFriends", label = "Fold friends too", dependsOn = "foldRoster",
		desc = "Off: friends coming online or going offline keep their own lines. On: they are folded with the guild." },
	{ type = "header", label = "Repeated lines" },
	{ type = "toggle", key = "spamFilter", label = "Hide repeated lines", desc = "In public channels, say and yell: the same text from the same player within the time below shows only once. Off by default." },
	{ type = "range", key = "spamWindow", label = "Repeat window", unit = "s", min = 2, max = 120, step = 1, dependsOn = "spamFilter", desc = "How long a repeated line stays hidden." },

	{ type = "tab", label = "Trade board" },
	{ type = "toggle", key = "tradeBoard", label = "Keep recent trade offers",
		desc = "Reads offers from visible public chat in the chosen channels. Kept for this session only. Off by default.",
		disabled = E:BlizzardNeeds(ELEMENT, "improve") },
	{ type = "execute", label = "Open the Trade board", dependsOn = "tradeBoard",
		desc = "Search recent sales, requests and services. A row opens an unsent whisper draft.",
		func = function() if M.ToggleTradeBoard then M:ToggleTradeBoard() end end },
	{ type = "header", label = "Trade board channels" },
	{ type = "toggle", key = "tradeChannel", label = "Trade channel", dependsOn = "tradeBoard", desc = "Collect offers from the game's Trade channel." },
	{ type = "toggle", key = "tradeGeneral", label = "General channel", dependsOn = "tradeBoard", desc = "Collect offers from the game's General channel." },
	{ type = "toggle", key = "tradeLooking", label = "LookingForGroup channel", dependsOn = "tradeBoard", desc = "Collect trade and service offers from the game's LookingForGroup channel." },
	{ type = "range", unit = "min", key = "tradeMinutes", label = "Keep offers for", min = 5, max = 60, step = 5,
		dependsOn = "tradeBoard", desc = "Offers this old disappear. The board keeps up to 300 offers." },
	{ type = "input", key = "tradeWatchWords", label = "Trade watch words", dependsOn = "tradeBoard",
		desc = "Comma-separated words or phrases. Matching offers stand out in the list." },
	{ type = "toggle", key = "tradeWatchSound", label = "Sound for watched offers", dependsOn = "tradeBoard",
		desc = "Uses the Chat keyword sound and its quiet-in-combat setting." },

	{ type = "tab", label = "History and search" },
	{ type = "header", label = "Saved history" },
	{ type = "toggle", key = "history", label = "Keep chat between sessions", desc = "The last lines of every chat tab come back after a reload or the next login, under a gray divider. Per character. Turning it off asks first, because it deletes the saved lines." },
	{ type = "range", key = "historyLines", label = "Lines saved per window", min = 20, max = 500, step = 10, desc = "Capped so the saved file stays small. Lowering it asks first when saved lines would be deleted." },
	{ type = "toggle", key = "historyWhispers", label = "Save whispers", desc = "Off leaves whispers out of the saved history, also their copies in the right panel and the Alerts tab, and deletes the whispers saved so far." },
	{ type = "execute", label = "Clear saved history", desc = "Deletes the saved chat lines of this character (asks first).", func = function() if M.ConfirmClearHistory then M:ConfirmClearHistory() end end },
	{ type = "header", label = "Typed lines" },
	{ type = "range", key = "editHistoryLines", label = "Typed lines kept", min = 0, max = 50, step = 1,
		zeroText = "Off", desc = "What you typed in the edit box comes back after a reload or the next login: Up and Down walk through it. Per character; secure commands are never saved. Off keeps them for this session only." },
	{ type = "execute", label = "Clear typed lines", desc = "Deletes the saved typed lines of this character (asks first).", func = function() if M.ConfirmClearEditHistory then M:ConfirmClearEditHistory() end end },
	{ type = "header", label = "Search" },
	{ type = "description", label = "Find on the chat's side rail (or /eui chatsearch) lists matching lines. Click a result to scroll to it; Copy results gives them as text." },

	{ type = "tab", label = "Right panel" },
	{ type = "description", label = "A second panel on the right for chosen kinds of messages, such as loot, so the main chat stays readable." },
	{ type = "toggle", key = "rightPanel", label = "Show the right panel", desc = "Turns the right chat panel on. Move it with /eui move (EldoUI_ChatRight)." },
	{ type = "range", unit = "px", key = "rightWidth", label = "Width", min = 200, max = 900, step = 1, hidden = NotRight, desc = "Width of the right panel." },
	{ type = "range", unit = "px", key = "rightHeight", label = "Height", min = 100, max = 600, step = 1, hidden = NotRight, desc = "Height of the right panel." },
	{ type = "input", key = "rightTitle", label = "Title", hidden = NotRight, desc = "Name shown on the panel. Empty uses the message kinds." },
	{ type = "toggle", key = "rightMove", label = "Only in the right panel", hidden = NotRight, desc = "Removes these lines from the main chat. Off shows them in both." },
}
for _, group in ipairs(RIGHT_GROUPS) do
	table.insert(M.options, { type = "toggle", key = "rightGroups." .. group[1], label = group[2], hidden = NotRight,
		desc = "Show %s in the right panel.", descFill = function() return L[group[2]]:lower() end })
end
for _, option in ipairs({
	{ type = "tab", label = "Errors and help" },
	{ type = "description", label = "Lua errors never go to chat but into a log of 100 entries, with repeats counted. Open it from the chat's side rail or with /eui errors." },
	{ type = "toggle", key = "errorTabAlways", label = "Always show the Errors button", desc = "Off: it appears when the first error is logged." },
	{ type = "description", label = "The game's own error window is set on General > Lua errors." },
	{ type = "header", label = "Tools" },
	{ type = "execute", label = "Open error log", desc = "Shows the Errors tab, or the log as text without the chat panel.", func = function() M:ToggleErrors(true) end },
	{ type = "execute", label = "Copy chat", desc = "The selected chat window as plain text.", func = function() M:CopyChat() end },
}) do table.insert(M.options, option) end

---------------------------------------------------------------------------
-- Style presets (the layout places the chat)
---------------------------------------------------------------------------
E:RegisterStyles("Chat", {
	{ key = "Standard", title = "Standard", desc = "557 x 282, accent underline on the active tab, edit box over the tabs.",
		settings = { width = 557, height = 282, fontSize = 14, panelAlpha = 0.8, tabStyle = "underline", editBox = "TABS",
			fontOutline = "NONE", fontShadow = true, shortChannels = true, channelStyle = "number",
			tabFlashAccent = true, urlAccent = true, keywordAccent = true } },
	{ key = "Wide", title = "Wide", desc = "700 x 260 for long lines.",
		settings = { width = 700, height = 260, fontSize = 14, panelAlpha = 0.8, tabStyle = "underline" } },
	{ key = "Compact", title = "Compact", desc = "440 x 200 with 13 pt text and the edit box below.",
		settings = { width = 440, height = 200, fontSize = 13, tabHeight = 22, tabFontSize = 12, editBox = "BELOW" } },
	{ key = "Tall", title = "Tall", desc = "480 x 380 for busy guilds, with saved history.",
		settings = { width = 480, height = 380, fontSize = 14, history = true, historyLines = 300 } },
	{ key = "Large", title = "Large text", desc = "557 x 300 with 16 pt outlined text.",
		settings = { width = 557, height = 300, fontSize = 16, fontOutline = "OUTLINE", fontShadow = false, tabFontSize = 14 } },
	{ key = "Glass", title = "Glass", desc = "See-through panel, text fades after 30 seconds.",
		settings = { panelAlpha = 0.25, fade = "fade", fadeTime = 30, fadeDuration = 3, tabStyle = "text", fontShadow = true } },
	{ key = "Split", title = "Split with right panel", desc = "Main chat left, loot and skill-ups in a right panel.",
		settings = { width = 500, height = 260, rightPanel = true, rightWidth = 420, rightHeight = 200, rightMove = true,
			rightGroups = { loot = true, skills = true, channels = false, guild = false, group = false, whisper = false, system = false, npc = false } } },
}, { restores = { "rightPanel", "rightMove", "panelAlpha", "fade", "fadeTime" } })
