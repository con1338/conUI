-- EldoUI Character: the character window in the EldoUI look.
--
-- Window chrome, paper doll, stats pane and every side panel (reputation,
-- skills, PvP, currency, statistics) get the art-style panel, flat status
-- bars and accent headers. Item slots become flat EldoUI slots with
-- quality borders, item level, durability and an optional missing-enchant
-- hint, and an average item level line sits in the title bar. Colors
-- follow the active accent and preset, and a few style presets set many
-- options at once. The Modern preset adds a "Name the Title" header with a
-- class-colored level line, item levels beside the slots with gem and
-- enchant marks, a large accent item level with the item score, foldable
-- stat sections, accent-underlined tabs (Core/Skin.lua) and an eye button
-- that shows only the model.
--
-- The window is the Blizzard element "character-frame" (Core/Blizzard.lua).
-- Nothing here touches it until the player turns the element on; then
-- its switches decide: Skin (window, slots, stats, side panels and tabs),
-- Move (drag and scale, done by the window mover in Core/WindowMover.lua)
-- and Improve (item level, durability, gem and enchant
-- marks, average item level, item score, eye button).
--
-- Presentation only: everything shown comes straight from the game
-- (item links, durability, average item level). Blizzard textures are made
-- invisible with SetAlpha(0), never hidden or reparented; Blizzard code is
-- only followed through hooksecurefunc / HookScript, and per-frame state is
-- kept in local tables, never written into Blizzard frames.
-- Written from scratch for EldoUI; no code or media from other addons.
local _, E = ...
local L = E.L

local M = E:NewModule("Character", {
	title = "Character Panel",
	aliases = { "Character" }, -- the page's earlier title, for search and /eui
	category = "Interface",
	desc = "The character window, its slots and side panels in the EldoUI look.",
	conflicts = { "ElvUI", "EllesmereUICharacter", "BetterCharacterPanel", "Narcissus" },
	frames = {},
	movers = {},
	blizzard = { "character-frame" },
	savedKeys = { "profile.modules.Character" },
	optionsPage = "module:Character",
	presets = { "Blizzard", "Classic", "Clean", "EldoUI", "Modern", "Preset", "Raider" },
	defaults = {
		skin = true,             -- window chrome, paper doll and stats pane
		transparent = false,
		header = "blizzard",     -- blizzard, or eldo ("Name the Title" and a class-colored level line)
		eyeButton = true,        -- eye button that shows only the model
		avgItemLevel = true,
		avgPosition = "TITLE",   -- TITLE (left of the title bar), BELOW (under the level line), STATS (large, top of the stats)
		avgSize = 22,            -- text size for the STATS position
		itemScore = true,        -- sum of the equipped items' levels, next to the average
		modelBackground = "dark", -- blizzard, dark, gradient, stone
		gradientColor = "accent", -- accent or class
		slotBorder = "quality",  -- quality, accent, none
		slotBorderSize = 1,      -- border thickness in pixels
		itemLevel = true,
		ilvlSize = 12,
		ilvlPosition = "BOTTOM", -- TOP, BOTTOM, CENTER, SIDE (beside the slot, toward the model)
		ilvlColor = "quality",   -- quality, white, accent
		socketInfo = false,      -- gem and enchant marks, read from the item link
		durability = "text",     -- off, text, tint
		enchantHint = false,
		headerColorMode = "accent", -- accent, gold, class, custom
		headerColor = { 1, 0.82, 0 },
		statsFontSize = 13,
		statsLayout = "classic", -- classic (header bars) or modern (centered titles, thin lines)
		collapsibleStats = true, -- modern layout: click a section title to fold it
		statRowBg = true,        -- Blizzard's alternating stat row shading
		collapsedStats = {},     -- category key -> true while folded
		sideTabs = true,
		tabStyle = "box",        -- box (flat icon boxes) or underline (accent line); change needs /reload
		panelReputation = true,
		panelSkills = true,
		panelPvP = true,
		panelCurrency = true,
		panelStatistics = true,
		panelOther = true,
		gearBar = true,          -- equipment set buttons on the paper doll (Improve switch)
		gearBarPosition = "TOP", -- TOP (left of the level line) or BELOW (under the window)
		gearBarSize = 20,        -- button size
		gearAfterCombat = false, -- a set clicked in combat goes on when combat ends (acts later: the player turns it on)
		slotFlyout = false,      -- hover a trinket or ring slot: pick another one from your bags
	},
})

---------------------------------------------------------------------------
-- State, kept outside Blizzard frames (weak keys so nothing leaks)
---------------------------------------------------------------------------
local ours = setmetatable({}, { __mode = "k" })       -- frames EldoUI created
local stripped = setmetatable({}, { __mode = "k" })   -- frame -> true once its art is gone
local bars = setmetatable({}, { __mode = "k" })       -- status bar -> { bd, tex }
local headers = setmetatable({}, { __mode = "k" })    -- header row -> backdrop
local details = setmetatable({}, { __mode = "k" })    -- detail pane -> backdrop
local tabParts = setmetatable({}, { __mode = "k" })   -- tab -> { border, hover, icon }
local boxes = setmetatable({}, { __mode = "k" })      -- ScrollBoxes we listen to
local hookedPanels = setmetatable({}, { __mode = "k" })
local queuedPanels = setmetatable({}, { __mode = "k" })
local chrome = {}
local slots = {}          -- ordered { name, id, button, border, overlay }
local slotByButton = {}

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local function Usable(frame)
	return frame and type(frame) == "table" and frame.GetObjectType
		and not E.FrameCheck(frame, "IsForbidden")
end

-- The element switches. Every touch of Blizzard's window goes through one.
local ELEMENT = "character-frame"

local function Allowed(action)
	return M.active and E:BlizzardAllowed(ELEMENT, action) and true or false
end

local function SkinOn()
	return Allowed("skin") and M.db.skin and true or false
end

local function ImproveOn()
	return Allowed("improve")
end

-- The game's gamepad interface walks the window's buttons with its
-- controller cursor, so EldoUI's own buttons (the model-only eye, the set
-- buttons, the item flyouts and the stat folds) step aside while it is on
-- and come back with the mouse interface. The look and the texts stay.
local function Additions()
	return not E:GamepadUIActive()
end

local function ElementOn()
	local state = E:BlizzardState(ELEMENT)
	return state and state.enabled and true or false
end

local function Label(frame)
	local name = frame.GetName and frame:GetName() or ""
	local key = frame.GetParentKey and frame:GetParentKey() or ""
	return name .. "|" .. key
end

local function Accent()
	local c = E.media.accentColor
	return c[1], c[2], c[3]
end

local function HeaderColor()
	local mode = M.db.headerColorMode
	if mode == "gold" then return 1, 0.82, 0 end
	if mode == "class" then return E:ClassColor("player") end
	if mode == "custom" and type(M.db.headerColor) == "table" then
		return M.db.headerColor[1] or 1, M.db.headerColor[2] or 1, M.db.headerColor[3] or 1
	end
	return Accent()
end

-- Section and window titles: window text in the header font (no outline,
-- the soft window shadow), like every EldoUI window.
local function SetHeaderFont(fontString, size)
	E:SetWindowFont(fontString, size, true)
end

-- A section title that must fit its row: the header font at `size`, one
-- step smaller at a time when Large text or a long translation makes it
-- wider than the row (the stats list clips everything outside it). A title
-- still too wide at the smallest size wraps onto a second line.
local HEADER_PAD, HEADER_MIN = 6, 8
local wrappedHeaders = setmetatable({}, { __mode = "k" })
local function FitHeaderFont(fontString, row, size)
	SetHeaderFont(fontString, size)
	if wrappedHeaders[fontString] then
		wrappedHeaders[fontString] = nil
		fontString:SetWidth(0)
		fontString:SetWordWrap(false)
	end
	local width = row and row.GetWidth and row:GetWidth()
	if type(width) ~= "number" or width <= HEADER_PAD * 2 then return end
	local room = width - HEADER_PAD * 2
	local text = fontString.GetText and fontString:GetText()
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return end
	local fit = size
	while fit > HEADER_MIN and (fontString:GetStringWidth() or 0) > room do
		fit = fit - 1
		SetHeaderFont(fontString, fit)
	end
	if (fontString:GetStringWidth() or 0) > room then
		wrappedHeaders[fontString] = true
		fontString:SetWidth(room)
		fontString:SetWordWrap(true)
		if fontString.SetMaxLines then fontString:SetMaxLines(2) end
	end
end
M.FitHeaderFont = FitHeaderFont

-- The fill of a section header bar: the art style's panel color, lifted
-- toward white by the hover strength so it stands apart from the panel in
-- every style.
local function HeaderFill()
	local c = E.media.backdropColor
	local lift = E.tokens.hover.control
	return c[1] + (1 - c[1]) * lift, c[2] + (1 - c[2]) * lift, c[3] + (1 - c[3]) * lift, math.max(c[4] or 1, E.tokens.panel.alpha)
end

-- Blizzard's own size of a text, read once before EldoUI sets its font:
-- the size read back later already carries Large text, and restyling a
-- panel again must not grow it on every pass.
local baseSizes = setmetatable({}, { __mode = "k" })
local function FontSize(fontString, fallback)
	local known = baseSizes[fontString]
	if known then return known end
	local _, size = fontString:GetFont()
	known = size and math.floor(size + 0.5) or fallback
	baseSizes[fontString] = known
	return known
end

-- Regions a frame points at with keys like Icon, ExpandIcon or
-- CollapseButton are indicators and stay visible.
local function KeepSet(frame)
	local keep = {}
	for key, value in pairs(frame) do
		if type(key) == "string" and type(value) == "table"
			and (key:find("Icon") or key:find("icon") or key:find("Expand") or key:find("Collapse") or key:find("Toggle") or key:find("Check")) then
			keep[value] = true
		end
	end
	if frame.GetNormalTexture then
		local normal, pushed = frame:GetNormalTexture(), frame.GetPushedTexture and frame:GetPushedTexture()
		if normal then keep[normal] = true end
		if pushed then keep[pushed] = true end
	end
	return keep
end

-- Make a frame's own texture regions invisible. Highlight textures and the
-- regions in `keep` stay.
local function StripRegions(frame, keep)
	if not Usable(frame) then return end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:IsObjectType("Texture") and not (keep and keep[region]) and region:GetDrawLayer() ~= "HIGHLIGHT" then
			region:SetAlpha(0)
		end
	end
	if frame.NineSlice and frame.NineSlice.SetAlpha then frame.NineSlice:SetAlpha(0) end
end

local function AlphaZero(...)
	for i = 1, select("#", ...) do
		local region = select(i, ...)
		if type(region) == "table" and region.SetAlpha then region:SetAlpha(0) end
	end
end

-- A child frame behind `frame` carrying the EldoUI backdrop.
local function Backdrop(frame, panel, transparent, inset)
	local bd = CreateFrame("Frame", nil, frame)
	inset = inset or 0
	bd:SetPoint("TOPLEFT", -inset, inset)
	bd:SetPoint("BOTTOMRIGHT", inset, -inset)
	bd:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))
	if panel then E:SetPanelTemplate(bd, transparent) else E:SetTemplate(bd, transparent) end
	ours[bd] = true
	return bd
end

local function Walk(frame, depth, fn)
	if not Usable(frame) or ours[frame] then return end
	fn(frame)
	if depth <= 0 then return end
	for _, child in ipairs({ frame:GetChildren() }) do
		Walk(child, depth - 1, fn)
	end
end

local function FontStrings(frame)
	local list = {}
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:IsObjectType("FontString") then list[#list + 1] = region end
	end
	return list
end

---------------------------------------------------------------------------
-- Window chrome: art-style panel, accent line, fonts, insets
---------------------------------------------------------------------------
local function TitleText()
	local container = CharacterFrame.TitleContainer
	return (container and container.TitleText) or CharacterFrame.TitleText or _G.CharacterFrameTitleText
end

function M:SkinChrome()
	if chrome.bd then return end
	if CharacterFrame.NineSlice then CharacterFrame.NineSlice:SetAlpha(0) end
	StripRegions(CharacterFrame)
	if CharacterFrame.PortraitContainer then CharacterFrame.PortraitContainer:SetAlpha(0) end
	AlphaZero(_G.CharacterFramePortrait, CharacterFrame.Bg, _G.CharacterFrameBg, CharacterFrame.TopTileStreaks)
	if CharacterFrame.TitleContainer then StripRegions(CharacterFrame.TitleContainer) end

	chrome.bd = Backdrop(CharacterFrame, true, self.db.transparent)
	E:SetWindowEdge(chrome.bd)
	chrome.accent = chrome.bd:CreateTexture(nil, "ARTWORK")
	chrome.accent:SetPoint("TOPLEFT", E.pixel, -24)
	chrome.accent:SetPoint("TOPRIGHT", -E.pixel, -24)
	chrome.accent:SetHeight(E.pixel * 2)

	-- The insets keep their place as subtle outlined areas.
	chrome.insets = {}
	for _, inset in ipairs({ _G.CharacterFrameInset, _G.CharacterFrameInsetRight, CharacterFrame.Inset }) do
		if Usable(inset) and not stripped[inset] then
			stripped[inset] = true
			StripRegions(inset)
			AlphaZero(inset.Bg)
			table.insert(chrome.insets, Backdrop(inset, false, true))
		end
	end

	-- Forever's window: a left pane (model and slots) and a right pane
	-- (stats, sidebar tabs) with their own art, a stone strip and a divider.
	for _, host in ipairs({ CharacterFrame.LeftPaneHost, CharacterFrame.RightPaneHost }) do
		if Usable(host) and not stripped[host] then
			stripped[host] = true
			StripRegions(host)
			for _, child in ipairs({ host:GetChildren() }) do
				if Usable(child) and not ours[child] then StripRegions(child) end
			end
		end
	end
	local right = CharacterFrame.RightPaneHost
	if Usable(right) and not chrome.rightPane then
		-- A thin line where Blizzard's divider was.
		chrome.rightPane = right:CreateTexture(nil, "ARTWORK")
		chrome.rightPane:SetPoint("TOPLEFT", right, "TOPLEFT", 0, -4)
		chrome.rightPane:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 0, 4)
		chrome.rightPane:SetWidth(E.pixel)
	end
end

function M:UpdateChrome()
	self:UpdateHeader()
	self:UpdateEye()
	if not chrome.bd then return end
	E:SetPanelTemplate(chrome.bd, self.db.transparent)
	chrome.accent:SetColorTexture(Accent())
	if chrome.rightPane then chrome.rightPane:SetColorTexture(unpack(E.media.borderColor)) end
	local title = TitleText()
	if title then
		SetHeaderFont(title, 15)
		title:SetTextColor(1, 1, 1)
	end
	local level = _G.CharacterLevelText
	if level then
		E:SetWindowFont(level, E.tokens.size.body)
		level:SetTextColor(E:TokenColor("secondary"))
	end
end

-- Our overlay above the window for the header, eye button and title-bar
-- item level. A child of CharacterFrame, so it shows and hides with it.
local function Overlay()
	if not chrome.overlay then
		local overlay = CreateFrame("Frame", nil, CharacterFrame)
		overlay:SetAllPoints()
		overlay:SetFrameLevel(CharacterFrame:GetFrameLevel() + 20)
		ours[overlay] = true
		chrome.overlay = overlay
	end
	return chrome.overlay
end

local function PaperDollShown()
	return _G.PaperDollFrame and _G.PaperDollFrame:IsShown()
end

---------------------------------------------------------------------------
-- Header: "Name the Title" and "Level 60 Spec Class" in class color.
-- Everything comes from the game (UnitPVPName, UnitLevel, the active
-- specialization); Blizzard's own lines are made invisible while ours show.
---------------------------------------------------------------------------
local function SpecName()
	local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or _G.GetSpecialization
	local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or _G.GetSpecializationInfo
	if type(getSpec) ~= "function" or type(getInfo) ~= "function" then return end
	local ok, index = pcall(getSpec)
	if not ok or type(index) ~= "number" or index < 1 then return end
	local ok2, _, name = pcall(getInfo, index)
	if ok2 and type(name) == "string" and name ~= "" then return name end
end

function M:UpdateHeader()
	if not CharacterFrame then return end
	local blizzTitle, blizzLevel = TitleText(), _G.CharacterLevelText
	local own = SkinOn() and self.db.header == "eldo" and PaperDollShown()
	if not own then
		if chrome.title then chrome.title:Hide(); chrome.levelLine:Hide() end
		if chrome.headerHidden then
			chrome.headerHidden = false
			if blizzTitle then blizzTitle:SetAlpha(1) end
			if blizzLevel then blizzLevel:SetAlpha(1) end
		end
		return
	end
	local overlay = Overlay()
	if not chrome.title then
		chrome.title = overlay:CreateFontString(nil, "OVERLAY")
		chrome.title:SetWordWrap(false)
		chrome.levelLine = E:CreateText(overlay, E.tokens.size.body, "CENTER")
	end
	M.chrome = chrome
	chrome.headerHidden = true
	if blizzTitle then blizzTitle:SetAlpha(0) end
	if blizzLevel then blizzLevel:SetAlpha(0) end

	local title = chrome.title
	SetHeaderFont(title, 15)
	title:SetTextColor(1, 1, 1)
	title:ClearAllPoints()
	if blizzTitle then title:SetPoint("CENTER", blizzTitle, "CENTER") else title:SetPoint("TOP", CharacterFrame, "TOP", 0, -5) end
	title:SetText(UnitPVPName("player") or UnitName("player") or "")
	title:Show()

	-- The one colored line under the title: level, specialization and
	-- class, all in the class color (the secondary gray without one).
	local line = chrome.levelLine
	E:SetWindowFont(line, E.tokens.size.body)
	line:ClearAllPoints()
	if blizzLevel then line:SetPoint("CENTER", blizzLevel, "CENTER") else line:SetPoint("TOP", CharacterFrame, "TOP", 0, -30) end
	local className, classFile = UnitClass("player")
	local who = SpecName() and (SpecName() .. " " .. (className or "")) or (className or "")
	line:SetFormattedText("%s %d %s", LEVEL or L["Level"], UnitLevel("player") or 0, who)
	local r, g, b = E:GetClassColor(classFile)
	if type(r) == "number" then
		line:SetTextColor(r, g, b)
	else
		line:SetTextColor(E:TokenColor("secondary"))
	end
	line:Show()
end

---------------------------------------------------------------------------
-- Eye button: a local toggle that fades the slots, stats and side panes so
-- only the model shows. Nothing is hidden or moved: the frames go to alpha
-- 0 and stop taking the mouse, and come back when the toggle is off or the
-- window closes. Not saved.
---------------------------------------------------------------------------
local eye = { on = false, faded = {}, mouse = setmetatable({}, { __mode = "k" }) }

-- The stats lists on Forever (scroll boxes in the right pane).
local function StatScrollBoxes()
	local list = {}
	for _, frame in ipairs({ _G.CharacterStatsPaneScrollBox, _G.CharacterStatsPanePetScrollBox }) do
		if Usable(frame) then list[#list + 1] = frame end
	end
	return list
end

local function EyeFrames()
	local list = {}
	local paperDoll = _G.PaperDollFrame
	for _, frame in ipairs({ _G.PaperDollItemsFrame, _G.CharacterStatsPane, _G.PaperDollSidebarTabs,
		_G.CharacterFrameInsetRight, _G.CharacterAttributesFrame, _G.CharacterResistanceFrame,
		_G.PaperDollTitlesPane, _G.PaperDollEquipmentManagerPane,
		_G.CharacterStatsPaneScrollBox, _G.CharacterStatsPanePetScrollBox, CharacterFrame.RightPaneHost,
		paperDoll and paperDoll.TitleManagerPane, paperDoll and paperDoll.EquipmentManagerPane }) do
		if Usable(frame) then list[#list + 1] = frame end
	end
	-- The slot buttons themselves on Forever (no items frame around them).
	if not Usable(_G.PaperDollItemsFrame) then
		for _, info in ipairs(slots) do list[#list + 1] = info.button end
	end
	return list
end

local function MouseFrames()
	local list = {}
	for _, info in ipairs(slots) do list[#list + 1] = info.button end
	for i = 1, 5 do
		local tab = _G["PaperDollSidebarTab" .. i]
		if Usable(tab) then list[#list + 1] = tab end
	end
	local pane = _G.CharacterStatsPane
	if Usable(pane) then
		for _, child in ipairs({ pane:GetChildren() }) do
			if Usable(child) and not ours[child] then list[#list + 1] = child end
		end
	end
	-- Rows of the stats lists, so invisible rows show no tooltips.
	for _, box in ipairs(StatScrollBoxes()) do
		local scroll = box.ScrollBox
		if Usable(scroll) and type(scroll.ForEachFrame) == "function" then
			pcall(scroll.ForEachFrame, scroll, function(row) list[#list + 1] = row end)
		end
	end
	return list
end

function M:SetModelOnly(on)
	on = on and ImproveOn() and true or false
	if on == eye.on then return end
	eye.on = on
	if on then
		for _, frame in ipairs(EyeFrames()) do
			eye.faded[#eye.faded + 1] = { frame, frame:GetAlpha() }
			frame:SetAlpha(0)
		end
		for _, frame in ipairs(MouseFrames()) do
			if frame.IsMouseEnabled and eye.mouse[frame] == nil then
				eye.mouse[frame] = frame:IsMouseEnabled()
				pcall(frame.EnableMouse, frame, false)
			end
		end
	else
		for _, entry in ipairs(eye.faded) do entry[1]:SetAlpha(entry[2] or 1) end
		wipe(eye.faded)
		for frame, enabled in pairs(eye.mouse) do pcall(frame.EnableMouse, frame, enabled) end
		wipe(eye.mouse)
	end
	if chrome.avg then chrome.avg:SetAlpha(on and 0 or 1) end
	if chrome.avgScore then chrome.avgScore:SetAlpha(on and 0 or 1) end
	self:UpdateEye()
	if not on then self:SafeCollapse() end
end

function M:UpdateEye()
	local show = ImproveOn() and Additions() and self.db.eyeButton and PaperDollShown()
	if not show then
		if eye.on then self:SetModelOnly(false) end
		if chrome.eye then chrome.eye:Hide() end
		return
	end
	if not chrome.eye then
		local button = CreateFrame("Button", nil, Overlay())
		button:SetSize(18, 18)
		button:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 6, -3)
		button.icon = button:CreateTexture(nil, "ARTWORK")
		button.icon:SetAllPoints()
		button.icon:SetTexture(E.media.eye)
		button:SetScript("OnClick", function(b, mouse)
			if E:IsOptionsLinkClick(b, mouse) then return end
			M:SetModelOnly(not eye.on)
		end)
		button:SetScript("OnEnter", function(b)
			b.icon:SetVertexColor(1, 1, 1)
			GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
			GameTooltip:AddLine(eye.on and L["Show the panels"] or L["Show only the model"])
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function()
			GameTooltip_Hide()
			M:UpdateEye()
		end)
		E:BindOptionsLink(button, { page = "module:Character", key = "eyeButton" })
		ours[button] = true
		chrome.eye = button
	end
	chrome.eye:Show()
	if eye.on then chrome.eye.icon:SetVertexColor(Accent()) else chrome.eye.icon:SetVertexColor(E:TokenColor("secondary")) end
end

---------------------------------------------------------------------------
-- Model background
---------------------------------------------------------------------------
local function ModelFrame()
	return _G.CharacterModelScene or _G.CharacterModelFrame
end

local function BlizzardModelBackgrounds()
	local model = ModelFrame()
	local list = {}
	local function Add(texture)
		if type(texture) == "table" and texture.SetAlpha then list[#list + 1] = texture end
	end
	if model then
		Add(model.BackgroundTopLeft); Add(model.BackgroundTopRight)
		Add(model.BackgroundBotLeft); Add(model.BackgroundBotRight)
		Add(model.BackgroundBottomLeft); Add(model.BackgroundBottomRight)
		Add(model.BackgroundOverlay)
	end
	for _, name in ipairs({ "TopLeft", "TopRight", "BotLeft", "BotRight", "BottomLeft", "BottomRight", "Overlay" }) do
		Add(_G["CharacterModelFrameBackground" .. name])
		Add(_G["PaperDollFrameBackground" .. name])
	end
	return list
end

function M:UpdateModelBackground()
	local model = ModelFrame()
	if not Usable(model) then return end
	local blizzard = BlizzardModelBackgrounds()
	local mode = SkinOn() and self.db.modelBackground or "blizzard"
	for _, texture in ipairs(blizzard) do texture:SetAlpha(mode == "blizzard" and 1 or 0) end
	if not chrome.modelBg then
		if mode == "blizzard" then return end
		local bg = model:CreateTexture(nil, "BACKGROUND", nil, -8)
		local topLeft = model.BackgroundTopLeft or _G.CharacterModelFrameBackgroundTopLeft
		local bottomRight = model.BackgroundBotRight or model.BackgroundBottomRight or _G.CharacterModelFrameBackgroundBotRight
		if topLeft and bottomRight then
			bg:SetPoint("TOPLEFT", topLeft, "TOPLEFT")
			bg:SetPoint("BOTTOMRIGHT", bottomRight, "BOTTOMRIGHT")
		else
			bg:SetAllPoints(model)
		end
		chrome.modelBg = bg
	end
	local bg = chrome.modelBg
	bg:SetShown(mode ~= "blizzard")
	bg:SetGradient("VERTICAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1))
	bg:SetHorizTile(false)
	bg:SetVertTile(false)
	if mode == "gradient" then
		local r, g, b
		if self.db.gradientColor == "class" then r, g, b = E:ClassColor("player") else r, g, b = Accent() end
		bg:SetColorTexture(1, 1, 1, 1)
		-- Bottom dark, top tinted.
		bg:SetGradient("VERTICAL", CreateColor(0.04, 0.04, 0.05, 0.95), CreateColor(r * 0.45, g * 0.45, b * 0.45, 0.95))
	elseif mode == "stone" then
		bg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background-Dark", "REPEAT", "REPEAT")
		bg:SetHorizTile(true)
		bg:SetVertTile(true)
		bg:SetVertexColor(unpack(E.tokens.paper.tint))
	else
		-- The art style's panel color, as the inspect window's plain backdrop.
		local c = E.media.backdropColor
		bg:SetColorTexture(c[1], c[2], c[3], math.max(c[4] or 1, E.tokens.panel.alpha))
	end
end

---------------------------------------------------------------------------
-- Item slots
---------------------------------------------------------------------------
local SLOT_NAMES = {
	"HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "ShirtSlot", "TabardSlot", "WristSlot",
	"HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot",
	"MainHandSlot", "SecondaryHandSlot", "RangedSlot", "AmmoSlot",
}
-- Slots that take an enchant in Classic content.
local ENCHANTABLE = {
	HeadSlot = true, ShoulderSlot = true, BackSlot = true, ChestSlot = true, WristSlot = true, HandsSlot = true,
	LegsSlot = true, FeetSlot = true, MainHandSlot = true, SecondaryHandSlot = true, RangedSlot = true,
}
local OFFHAND_ENCHANTABLE = { INVTYPE_SHIELD = true, INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true }
local NO_ITEM_LEVEL = { ShirtSlot = true, TabardSlot = true, AmmoSlot = true }
-- Which way the item level goes in the SIDE position: toward the model.
local SLOT_SIDE = {
	HeadSlot = "RIGHT", NeckSlot = "RIGHT", ShoulderSlot = "RIGHT", BackSlot = "RIGHT", ChestSlot = "RIGHT",
	ShirtSlot = "RIGHT", TabardSlot = "RIGHT", WristSlot = "RIGHT",
	HandsSlot = "LEFT", WaistSlot = "LEFT", LegsSlot = "LEFT", FeetSlot = "LEFT", Finger0Slot = "LEFT",
	Finger1Slot = "LEFT", Trinket0Slot = "LEFT", Trinket1Slot = "LEFT",
	MainHandSlot = "LEFT", SecondaryHandSlot = "RIGHT", RangedSlot = "RIGHT", AmmoSlot = "RIGHT",
}
local MAX_MARKERS = 4
local ENCHANT_ICON = "Interface\\Icons\\Trade_Engraving"

local function SlotIcon(button)
	local name = button:GetName()
	return button.icon or button.Icon or (name and _G[name .. "IconTexture"])
end

local function CollectSlots()
	if #slots > 0 then return end
	for _, name in ipairs(SLOT_NAMES) do
		local button = _G["Character" .. name]
		local ok, id = pcall(GetInventorySlotInfo, name)
		if button and ok and id then
			local info = { name = name, id = id, button = button }
			slots[#slots + 1] = info
			slotByButton[button] = info
		end
	end
end

local function MissingEnchant(info, link)
	if not ENCHANTABLE[info.name] or not link then return false end
	local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
	if info.name == "SecondaryHandSlot" and not OFFHAND_ENCHANTABLE[equipLoc] then return false end
	-- Wands take no enchant.
	if classID == Enum.ItemClass.Weapon and Enum.ItemWeaponSubclass and subclassID == Enum.ItemWeaponSubclass.Wand then return false end
	local enchant = link:match("item:%-?%d+:(%-?%d*)")
	return enchant == nil or enchant == "" or enchant == "0"
end

-- Flat EldoUI slot: Blizzard's slot art invisible, cropped icon, 1-pixel
-- border behind it. Only when the window skin is on.
local function SkinSlot(info)
	if info.border then return end
	local button = info.button
	local icon = SlotIcon(button)
	local keep = {}
	if icon then keep[icon] = true end
	for _, key in ipairs({ "IconOverlay", "IconOverlay2", "ignoreTexture", "SearchOverlay", "ItemContextOverlay" }) do
		if button[key] then keep[button[key]] = true end
	end
	local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
	local pushed = button.GetPushedTexture and button:GetPushedTexture()
	if highlight then keep[highlight] = true end
	if pushed then keep[pushed] = true end
	for _, region in ipairs({ button:GetRegions() }) do
		if region:IsObjectType("Texture") and not keep[region] then region:SetAlpha(0) end
	end
	AlphaZero(button.IconBorder, _G[button:GetName() .. "Frame"])
	if icon then
		E:TrimIcon(icon)
	end
	info.icon = icon
	if highlight then
		highlight:SetColorTexture(1, 1, 1, E.tokens.hover.hud)
		if icon then highlight:SetAllPoints(icon) end
	end
	if pushed then
		pushed:SetColorTexture(1, 1, 1, E.tokens.pressed)
		if icon then pushed:SetAllPoints(icon) end
	end
	info.border = Backdrop(button, false)
	info.border:SetBackdropColor(0, 0, 0, 0.5)
end

-- Border thickness: the backdrop edge and the icon inset follow it.
local function ApplyBorderSize(info)
	if not info.border then return end
	local size = math.max(1, math.min(4, math.floor(M.db.slotBorderSize or 1)))
	if info.borderSize == size then return end
	info.borderSize = size
	local edge = E.pixel * size
	info.border:SetBackdrop({ bgFile = E.media.flat, edgeFile = E.media.flat, edgeSize = edge })
	info.border:SetBackdropColor(0, 0, 0, 0.5)
	if info.icon then
		info.icon:ClearAllPoints()
		info.icon:SetPoint("TOPLEFT", info.button, "TOPLEFT", edge, -edge)
		info.icon:SetPoint("BOTTOMRIGHT", info.button, "BOTTOMRIGHT", -edge, edge)
	end
end

-- Gems and enchant from the item link only: item:id:enchant:gem1:gem2:gem3:gem4.
-- Empty sockets come from the item's own stats (EMPTY_SOCKET_* counts).
local function SplitLink(link)
	local body = link and link:match("item:([^|]+)")
	if not body then return end
	local fields = {}
	for field in (body .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = field end
	return fields
end

local function ItemMarkers(link)
	local list = {}
	local fields = SplitLink(link)
	if not fields then return list end
	local enchant = tonumber(fields[2])
	if enchant and enchant > 0 then list[#list + 1] = { kind = "enchant" } end
	local gems = 0
	for i = 3, 6 do
		local gem = tonumber(fields[i])
		if gem and gem > 0 then
			gems = gems + 1
			local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(gem)
			list[#list + 1] = { kind = "gem", icon = icon }
		end
	end
	local getStats = (C_Item and C_Item.GetItemStats) or _G.GetItemStats
	if type(getStats) == "function" then
		local ok, stats = pcall(getStats, link)
		if ok and type(stats) == "table" then
			local sockets = 0
			for key, value in pairs(stats) do
				if type(key) == "string" and key:find("^EMPTY_SOCKET_") and type(value) == "number" then sockets = sockets + value end
			end
			for _ = 1, math.max(0, sockets - gems) do list[#list + 1] = { kind = "empty" } end
		end
	end
	return list
end

local function SlotOverlay(info)
	if info.overlay then return info.overlay end
	local button = info.button
	local overlay = CreateFrame("Frame", nil, button)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(button:GetFrameLevel() + 3)
	ours[overlay] = true
	local icon = SlotIcon(button)
	overlay.tint = overlay:CreateTexture(nil, "ARTWORK")
	if icon then overlay.tint:SetAllPoints(icon) else overlay.tint:SetAllPoints() end
	overlay.tint:SetColorTexture(E:TokenColor("bad", 0.35))
	overlay.tint:Hide()
	overlay.ilvl = E:CreateText(overlay, E.tokens.size.label, "CENTER")
	overlay.durability = E:CreateText(overlay, E.tokens.size.tiny, "CENTER")
	overlay.enchant = overlay:CreateTexture(nil, "OVERLAY")
	overlay.enchant:SetSize(6, 6)
	overlay.enchant:SetPoint("TOPRIGHT", -2, -2)
	overlay.enchant:SetColorTexture(E:TokenColor("bad", 1))
	overlay.enchant:Hide()
	overlay.markers = {}
	for i = 1, MAX_MARKERS do
		local marker = overlay:CreateTexture(nil, "OVERLAY")
		marker:SetSize(11, 11)
		marker:Hide()
		overlay.markers[i] = marker
	end
	info.overlay = overlay
	-- Missing-enchant line in the item tooltip.
	button:HookScript("OnEnter", function(self)
		if not M.active or not M.db.enchantHint or not info.missingEnchant then return end
		if E.FrameCheck(GameTooltip, "IsForbidden") or not GameTooltip:IsOwned(self) then return end
		GameTooltip:AddLine(L["No enchant"], E:TokenColor("bad"))
		GameTooltip:Show()
	end)
	return overlay
end

local function UpdateSlot(info)
	local db = M.db
	local id = info.id
	local link = GetInventoryItemLink("player", id)
	local quality = link and GetInventoryItemQuality("player", id)
	local qr, qg, qb = 1, 1, 1
	if quality then qr, qg, qb = C_Item.GetItemQualityColor(quality) end

	-- The flat slot's border (Skin switch).
	if info.border then
		local r, g, b = unpack(E.media.borderColor)
		if link and db.slotBorder == "quality" and quality and quality >= Enum.ItemQuality.Uncommon then
			r, g, b = qr, qg, qb
		elseif link and db.slotBorder == "accent" then
			r, g, b = Accent()
		end
		info.border:SetBackdropBorderColor(r, g, b, 1)
	end

	-- Everything below is extra information (Improve switch).
	if not ImproveOn() then
		if info.overlay then info.overlay:Hide() end
		info.missingEnchant = false
		return
	end
	local overlay = SlotOverlay(info)
	overlay:Show()

	-- Item level.
	local position = db.ilvlPosition
	local level = ""
	if db.itemLevel and link and not NO_ITEM_LEVEL[info.name] then
		local itemLevel = C_Item.GetDetailedItemLevelInfo(link)
		if itemLevel and itemLevel > 1 then level = itemLevel else M.missingInfo = true end
	end
	E:SetFont(overlay.ilvl, db.ilvlSize)
	overlay.ilvl:ClearAllPoints()
	local side = position == "SIDE" and SLOT_SIDE[info.name]
	-- An off hand between the main hand and a ranged slot has no free side.
	if side and info.name == "SecondaryHandSlot" and _G.CharacterRangedSlot and _G.CharacterRangedSlot:IsShown() then side = "TOP" end
	if side == "RIGHT" then
		overlay.ilvl:SetPoint("TOPLEFT", info.button, "TOPRIGHT", 6, -2)
		overlay.ilvl:SetJustifyH("LEFT")
	elseif side == "LEFT" then
		overlay.ilvl:SetPoint("TOPRIGHT", info.button, "TOPLEFT", -6, -2)
		overlay.ilvl:SetJustifyH("RIGHT")
	elseif side == "TOP" then
		overlay.ilvl:SetPoint("BOTTOM", info.button, "TOP", 0, 2)
		overlay.ilvl:SetJustifyH("CENTER")
	elseif position == "TOP" then
		overlay.ilvl:SetPoint("TOP", 0, -2)
	elseif position == "CENTER" then
		overlay.ilvl:SetPoint("CENTER")
	else
		overlay.ilvl:SetPoint("BOTTOM", 0, 2)
	end
	overlay.ilvl:SetText(level)
	if db.ilvlColor == "white" then
		overlay.ilvl:SetTextColor(1, 1, 1)
	elseif db.ilvlColor == "accent" then
		overlay.ilvl:SetTextColor(E:TokenColor("accent"))
	else
		overlay.ilvl:SetTextColor(qr, qg, qb)
	end

	-- Durability: percent text or a red tint below the threshold.
	local percent
	if db.durability ~= "off" and link then
		local current, maximum = GetInventoryItemDurability(id)
		if current and maximum and maximum > 0 then percent = current / maximum * 100 end
	end
	-- "Low" is the shared threshold (General > Clock and durability).
	local low = percent and (E:DurabilityLevel(percent) == "low" or percent == 0)
	E:SetFont(overlay.durability, math.max(9, db.ilvlSize - 2))
	overlay.durability:ClearAllPoints()
	if side then
		overlay.durability:SetPoint("BOTTOM", 0, 2)
	else
		overlay.durability:SetPoint(position == "TOP" and "BOTTOM" or "TOP", 0, position == "TOP" and 2 or -2)
	end
	-- Low durability carries the shape mark too, so the red never stands
	-- alone: before the percent, or on its own over the tint.
	local mark = low and E:StatusMark("bad") or ""
	if db.durability == "text" and percent and percent < 100 then
		overlay.durability:SetFormattedText(mark ~= "" and "%s %d%%" or "%s%d%%", mark, percent)
		if low then overlay.durability:SetTextColor(E:TokenColor("bad")) else overlay.durability:SetTextColor(E:TokenColor("body")) end
	elseif db.durability == "tint" and mark ~= "" then
		overlay.durability:SetText(mark)
		overlay.durability:SetTextColor(E:TokenColor("bad"))
	else
		overlay.durability:SetText("")
	end
	overlay.tint:SetShown(db.durability == "tint" and low or false)

	info.missingEnchant = db.enchantHint and MissingEnchant(info, link) or false
	overlay.enchant:SetShown(info.missingEnchant)

	-- Gem and enchant marks: under the item level beside the slot, or a
	-- small row in the slot's top-left corner for the other positions.
	local markers = (db.socketInfo and link and not NO_ITEM_LEVEL[info.name]) and ItemMarkers(link) or {}
	local previous
	for i, marker in ipairs(overlay.markers) do
		local data = markers[i]
		marker:ClearAllPoints()
		if data then
			if data.kind == "gem" and data.icon then
				marker:SetTexture(data.icon)
				E:TrimIcon(marker)
			elseif data.kind == "enchant" then
				marker:SetTexture(ENCHANT_ICON)
				E:TrimIcon(marker)
			else
				marker:SetColorTexture(E:TokenColor("dim", 1))
			end
			local size = side and 11 or 9
			marker:SetSize(size, size)
			if previous then
				if side == "LEFT" then marker:SetPoint("RIGHT", previous, "LEFT", -2, 0)
				else marker:SetPoint("LEFT", previous, "RIGHT", 2, 0) end
			elseif side == "TOP" then
				marker:SetPoint("LEFT", overlay.ilvl, "RIGHT", 3, 0)
			elseif side == "RIGHT" then
				marker:SetPoint("TOPLEFT", overlay.ilvl, "BOTTOMLEFT", 0, -2)
			elseif side == "LEFT" then
				marker:SetPoint("TOPRIGHT", overlay.ilvl, "BOTTOMRIGHT", 0, -2)
			else
				marker:SetPoint("TOPLEFT", info.button, "TOPLEFT", 2, -2)
			end
			marker:Show()
			previous = marker
		else
			marker:Hide()
		end
	end
end

function M:UpdateSlots()
	CollectSlots()
	self.missingInfo = false
	for _, info in ipairs(slots) do
		if SkinOn() then
			SkinSlot(info)
			ApplyBorderSize(info)
		end
		UpdateSlot(info)
	end
	self:UpdateAverage()
end

---------------------------------------------------------------------------
-- Average item level
---------------------------------------------------------------------------
local function AverageItemLevel()
	if GetAverageItemLevel then
		local overall, equipped = GetAverageItemLevel()
		if equipped and equipped > 0 then return equipped, overall end
		if overall and overall > 0 then return overall, overall end
	end
	-- Fallback: the plain mean over the gear slots; a two-hander with an
	-- empty off hand counts twice, as the game does.
	CollectSlots()
	local total, count, mainHand, offHandLink = 0, 0, nil, nil
	for _, info in ipairs(slots) do
		if not NO_ITEM_LEVEL[info.name] then
			count = count + 1
			local link = GetInventoryItemLink("player", info.id)
			if info.name == "SecondaryHandSlot" then offHandLink = link end
			if link then
				local itemLevel = C_Item.GetDetailedItemLevelInfo(link) or 0
				total = total + itemLevel
				if info.name == "MainHandSlot" then
					local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
					if equipLoc == "INVTYPE_2HWEAPON" then mainHand = itemLevel end
				end
			end
		end
	end
	if mainHand and not offHandLink then total = total + mainHand end
	if count == 0 then return 0 end
	return total / count
end

-- Item score: the sum of the item levels the game reports for each
-- equipped item (shirt, tabard and ammo left out).
local function ItemScore()
	CollectSlots()
	local total = 0
	for _, info in ipairs(slots) do
		if not NO_ITEM_LEVEL[info.name] then
			local link = GetInventoryItemLink("player", info.id)
			if link then
				local level = C_Item.GetDetailedItemLevelInfo(link)
				if type(level) == "number" then total = total + level end
			end
		end
	end
	return total
end

local function ScoreText()
	if not M.db.itemScore then return "" end
	return ("  " .. E:TextHex("secondary") .. "%s|r |cffffffff%d|r"):format(L["Score"], ItemScore())
end

-- The large accent number at the top of the stats pane. It sits on its
-- own frame inside the pane, over Blizzard's item level line (made
-- invisible, its tooltip still works), so it follows the pane's tab.
-- On Forever the old pane stays hidden (the stats are a scrolling list
-- without an item level line), so the large number goes under the level
-- line instead; see M:UpdateAverage.
local function StatsAverage(show)
	local pane = _G.CharacterStatsPane
	local blizzard = Usable(pane) and pane.ItemLevelFrame
	if not show or not Usable(pane) or not pane:IsShown() then
		if chrome.avgBig then chrome.avgBig:Hide() end
		if chrome.scoreLine then chrome.scoreLine:Hide() end
		if chrome.ilvlHidden and blizzard then blizzard:SetAlpha(1) end
		chrome.ilvlHidden = false
		return false
	end
	if not chrome.avgBig then
		local holder = CreateFrame("Frame", nil, pane)
		holder:SetAllPoints()
		holder:SetFrameLevel(pane:GetFrameLevel() + 6)
		ours[holder] = true
		chrome.avgBig = holder:CreateFontString(nil, "OVERLAY")
		chrome.avgBig:SetWordWrap(false)
		chrome.avgBigHolder = holder
	end
	local text = chrome.avgBig
	text:ClearAllPoints()
	if blizzard then
		text:SetPoint("CENTER", blizzard, "CENTER", 0, 0)
		blizzard:SetAlpha(0)
		chrome.ilvlHidden = true
	else
		text:SetPoint("TOP", pane, "TOP", 0, -6)
	end
	SetHeaderFont(text, M.db.avgSize or 22)
	text:SetTextColor(E:TokenColor("accent"))
	local equipped, overall = AverageItemLevel()
	if overall and overall > 0 and math.abs(overall - equipped) >= 0.005 then
		text:SetFormattedText("%.2f / %.2f", equipped, overall)
	else
		text:SetFormattedText("%.2f", equipped)
	end
	text:Show()
	-- Item score on a smaller line under the big number.
	if not chrome.scoreLine then chrome.scoreLine = E:CreateText(chrome.avgBigHolder, E.tokens.size.label, "CENTER") end
	local score = chrome.scoreLine
	E:SetFont(score, E.tokens.size.label)
	score:ClearAllPoints()
	score:SetPoint("TOP", text, "BOTTOM", 0, -2)
	score:SetText(M.db.itemScore and ScoreText():gsub("^%s+", "") or "")
	score:SetShown(M.db.itemScore and true or false)
	return true
end

function M:UpdateAverage()
	if not chrome.avg and not ImproveOn() then
		StatsAverage(false)
		return
	end
	if not chrome.avg then
		chrome.avg = E:CreateText(Overlay(), 13, "LEFT")
	end
	local text = chrome.avg
	if not chrome.avgScore then chrome.avgScore = E:CreateText(Overlay(), 12, "CENTER") end
	chrome.avgScore:Hide()
	local wanted = ImproveOn() and self.db.avgItemLevel and true or false
	if StatsAverage(wanted and self.db.avgPosition == "STATS") then
		text:Hide()
		return
	end
	text:SetShown(wanted)
	if not text:IsShown() then return end
	text:ClearAllPoints()
	local level = (chrome.levelLine and chrome.levelLine:IsShown() and chrome.levelLine) or _G.CharacterLevelText
	if self.db.avgPosition == "STATS" then
		-- Forever: the large accent number under the level line, on the
		-- paper doll only.
		if not PaperDollShown() then
			text:Hide()
			return
		end
		if level then text:SetPoint("TOP", level, "BOTTOM", 0, -4) else text:SetPoint("TOP", CharacterFrame, "TOP", 0, -56) end
		text:SetJustifyH("CENTER")
		SetHeaderFont(text, self.db.avgSize or 22)
		text:SetTextColor(E:TokenColor("accent"))
		local equipped, overall = AverageItemLevel()
		if overall and overall > 0 and math.abs(overall - equipped) >= 0.005 then
			text:SetFormattedText("%.2f / %.2f", equipped, overall)
		else
			text:SetFormattedText("%.2f", equipped)
		end
		if self.db.itemScore then
			local score = chrome.avgScore
			E:SetFont(score, E.tokens.size.label)
			score:ClearAllPoints()
			score:SetPoint("TOP", text, "BOTTOM", 0, -2)
			score:SetText((ScoreText():gsub("^%s+", "")))
			score:SetAlpha(eye.on and 0 or 1)
			score:Show()
		end
		return
	end
	E:SetFont(text, E.tokens.size.body)
	text:SetTextColor(1, 1, 1)
	if self.db.avgPosition == "BELOW" and level then
		text:SetPoint("TOP", level, "BOTTOM", 0, -3)
		text:SetJustifyH("CENTER")
	else
		-- Clear of the eye button when it shows.
		local x = (chrome.eye and chrome.eye:IsShown()) and 28 or 10
		text:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", x, -6)
		text:SetJustifyH("LEFT")
	end
	local r, g, b = Accent()
	local color = ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
	local average = AverageItemLevel()
	text:SetFormattedText("%s%s|r %.1f%s", color, STAT_AVERAGE_ITEM_LEVEL or L["Item Level"], average, ScoreText())
end

---------------------------------------------------------------------------
-- Paper doll: frame borders, side tabs inside the doll, stats pane
---------------------------------------------------------------------------
-- A side tab icon fills its tab inside the border, so every tab is the same
-- size. The portrait is a whole texture and gets the usual icon crop. The
-- Titles and Equipment Manager icons are regions of a shared art sheet (an
-- atlas or set texture coordinates): their region stays as the game set it,
-- because the usual crop would show the wrong part of the sheet.
local function SidebarTabIcon(tab, icon)
	icon:ClearAllPoints()
	icon:SetPoint("TOPLEFT", tab, "TOPLEFT", 1, -1)
	icon:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -1, 1)
	if type(icon.GetAtlas) == "function" and icon:GetAtlas() then return end
	if type(icon.GetTexCoord) == "function" then
		local left, top, _, _, _, _, right, bottom = icon:GetTexCoord()
		if type(left) == "number" and type(top) == "number" and type(right) == "number" and type(bottom) == "number"
			and (left > 0.001 or top > 0.001 or right < 0.999 or bottom < 0.999) then return end
	end
	E:TrimIcon(icon)
end

function M:SkinPaperDoll()
	if chrome.paperDoll then return end
	chrome.paperDoll = true
	local paperDollFrame = _G.PaperDollFrame
	for _, name in ipairs({ "TopLeft", "TopRight", "BottomLeft", "BottomRight", "Left", "Right", "Top", "Bottom", "Bottom2" }) do
		AlphaZero(_G["PaperDollInnerBorder" .. name])
	end
	if _G.PaperDollItemsFrame then StripRegions(_G.PaperDollItemsFrame) end
	-- Stats / titles / equipment manager tabs inside the paper doll.
	if _G.PaperDollSidebarTabs then
		AlphaZero(_G.PaperDollSidebarTabs.DecorLeft, _G.PaperDollSidebarTabs.DecorRight)
	end
	for i = 1, 5 do
		local tab = _G["PaperDollSidebarTab" .. i]
		if Usable(tab) and not tabParts[tab] then
			AlphaZero(tab.TabBg)
			local icon = tab.Icon
			-- Forever's tabs: an atlas frame and a checked glow; the icon stays.
			if not tab.TabBg then
				StripRegions(tab, icon and { [icon] = true } or nil)
				AlphaZero(tab.GetCheckedTexture and tab:GetCheckedTexture())
			end
			if icon then SidebarTabIcon(tab, icon) end
			tabParts[tab] = { border = Backdrop(tab, false, true), sidebar = true }
			if type(tab.SetChecked) == "function" then
				hooksecurefunc(tab, "SetChecked", function() M:UpdateTabs() end)
			end
		end
	end
	if Usable(paperDollFrame) and Usable(paperDollFrame.TopBackgroundStripHost) then
		StripRegions(paperDollFrame.TopBackgroundStripHost)
	end
	self:SkinStatLists()
	self:SkinSetPanes()
	-- Stats pane: class art and brown category bars go, flat bars come in.
	local pane = _G.CharacterStatsPane
	if Usable(pane) then
		AlphaZero(pane.ClassBackground)
		for key, value in pairs(pane) do
			if type(key) == "string" and key:find("Category$") and Usable(value) then
				AlphaZero(value.Background)
				chrome.statBars = chrome.statBars or {}
				chrome.statBars[value] = Backdrop(value, false, true)
			end
		end
		if pane.ItemLevelFrame then AlphaZero(pane.ItemLevelFrame.Background) end
	end
end

-- Forever's stats are scroll boxes (yours and your pet's): the border and
-- class art go, the scroll bar turns flat and every row that scrolls in is
-- restyled. The values stay Blizzard's own.
local catBars = setmetatable({}, { __mode = "k" })    -- stats list header row -> flat bar

local HookStatList -- the list folding below hooks each stats list

local function StyleStatRowLater()
	M:QueueStats()
end

function M:SkinStatLists()
	for _, box in ipairs(StatScrollBoxes()) do
		if not stripped[box] then
			stripped[box] = true
			AlphaZero(box.Border, box.ClassBackground)
			E:SkinScrollBar(box.ScrollBar)
			if Usable(box.ScrollBox) then E:HookScrollBoxRows(box.ScrollBox, StyleStatRowLater) end
		end
		HookStatList(box)
	end
end

-- Titles and equipment sets on the paper doll's sidebar, and the popup that
-- names a new set.
local function SkinSetRow(row)
	if not SkinOn() then return end
	E:SkinRow(row)
	AlphaZero(row.HighlightBar)
	if row.SelectedBar then
		local r, g, b = Accent()
		row.SelectedBar:SetColorTexture(r, g, b, 0.25)
	end
	local text = row.text or row.Text
	if text and text.SetFont then E:SetFont(text, E.tokens.size.label) end
end

function M:SkinSetPanes()
	local paperDoll = _G.PaperDollFrame
	if not Usable(paperDoll) then return end
	for _, pane in ipairs({ paperDoll.TitleManagerPane, paperDoll.EquipmentManagerPane }) do
		if Usable(pane) and not stripped[pane] then
			stripped[pane] = true
			AlphaZero(pane.Border)
			for _, child in ipairs({ pane:GetChildren() }) do
				if Usable(child) and child ~= pane.ScrollBox and child ~= pane.ScrollBar and not child:IsObjectType("Button") then
					-- The frame around the list and the divider line.
					for _, region in ipairs({ child:GetRegions() }) do
						if region:IsObjectType("Texture") then region:SetAlpha(0) end
					end
				end
			end
			E:SkinScrollBar(pane.ScrollBar)
			if Usable(pane.ScrollBox) then E:HookScrollBoxRows(pane.ScrollBox, SkinSetRow) end
			E:SkinButton(pane.EquipSet)
			E:SkinButton(pane.SaveSet)
		end
	end
	local popup = _G.GearManagerPopupFrame
	if Usable(popup) and not stripped[popup] and E.WindowKit then
		stripped[popup] = true
		E:SkinPanel(popup, { accentLine = false })
		E.WindowKit.SkinTree(popup, { depth = 4 })
	end
end

local function StatsContainer()
	local stats = _G.CharacterStatsPane
	if Usable(stats) and stats:IsShown() then return stats end
	if CharacterFrame and type(CharacterFrame.GetStatsPane) == "function" then
		local ok, pane = pcall(CharacterFrame.GetStatsPane, CharacterFrame)
		if ok and Usable(pane) then
			-- The pet list when the pet page is open.
			local paperDoll = _G.PaperDollFrame
			local current = paperDoll and paperDoll.currentSideBar
			if Usable(current) and current == _G.CharacterStatsPanePetScrollBox then return current end
			return pane
		end
	end
	return stats or (_G.PaperDollFrame and _G.PaperDollFrame.StatsPane) or _G.CharacterAttributesFrame
end

local function CategoryKeys(pane)
	local map = {}
	for key, value in pairs(pane) do
		if type(key) == "string" and key:find("Category$") and Usable(value) then map[value] = key end
	end
	return map
end

local function Modern(db)
	return db.skin and db.statsLayout == "modern"
end

-- A section folds in the modern layout with "Fold stat sections" on; the
-- item level at the top of the fixed pane never does.
local function CanCollapse(db, key)
	return Modern(db) and db.collapsibleStats and key ~= nil and key ~= "ItemLevelCategory"
end

local function Plain(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return nil end
	return text
end

-- The fold key of a header of Forever's stats list: its section name.
local function ListKey(name)
	name = Plain(name)
	if not name or name == "" then return nil end
	return "list:" .. name
end

-- Modern section headers are the kit's fold divider (E.UIKit.FoldDivider):
-- the name centered between two thin accent lines and, when the section
-- folds, a chevron on the right; the whole header is the click area. Two
-- dividers sit over Blizzard's header (one that folds, one that doesn't),
-- and Blizzard's own title goes to alpha 0 while ours shows.
local catParts = setmetatable({}, { __mode = "k" })   -- header frame -> { fold, plain, key }
local titleFaded = setmetatable({}, { __mode = "k" }) -- Blizzard title -> true while ours shows
local labelFitted = setmetatable({}, { __mode = "k" }) -- stat label -> true while we gave it a width

local function OnFold(folded, divider)
	local key = divider.kitStatKey
	if not CanCollapse(M.db, key) then return end
	M.db.collapsedStats[key] = folded or nil
	M:SafeCollapse()
	M:FoldStatLists()
	M:StyleStats()
end

local function StatDividers(cat)
	local parts = catParts[cat]
	if parts then return parts end
	local Kit = E.UIKit
	parts = { fold = Kit.FoldDivider(cat, { onToggle = OnFold }), plain = Kit.FoldDivider(cat) }
	for _, divider in ipairs({ parts.fold, parts.plain }) do
		divider:SetAllPoints()
		divider:SetFrameLevel(cat:GetFrameLevel() + 2)
		divider:Hide()
		ours[divider] = true
	end
	catParts[cat] = parts
	return parts
end
M.StatDividers = function(_, cat) return catParts[cat] end

-- The section name at `size`, one step smaller at a time while it is wider
-- than the room between the lines (Large text, long translations), down to
-- HEADER_MIN pixels on screen; a name still too wide is cut short.
local function FitDividerLabel(divider, size)
	local label = divider.label
	local room = (divider:GetWidth() or 0) - (divider.chevron and 56 or 32)
	local scale = E:TextScale()
	local fit = size
	E:SetWindowFont(label, fit)
	label:SetWidth(0)
	if room > 0 and Plain(label:GetText()) then
		while (fit - 1) * scale >= HEADER_MIN and (label:GetStringWidth() or 0) > room do
			fit = fit - 1
			E:SetWindowFont(label, fit)
		end
		if (label:GetStringWidth() or 0) > room then label:SetWidth(room) end
	end
	label.kitSize = fit
end

local function ShowTitle(title)
	if title and titleFaded[title] then
		title:SetAlpha(1)
		titleFaded[title] = nil
	end
end

-- One header: our divider over Blizzard's header frame (modern), or
-- Blizzard's own title back (classic).
local function StyleHeader(cat, key, modern)
	local title = cat.Title or cat.TitleText
	local parts = (modern or catParts[cat]) and StatDividers(cat)
	if not parts then return end
	if not modern then
		parts.fold:Hide()
		parts.plain:Hide()
		ShowTitle(title)
		return
	end
	local db = M.db
	local foldable = CanCollapse(db, key) and Additions() and true or false
	local divider, other = parts.plain, parts.fold
	if foldable then divider, other = parts.fold, parts.plain end
	other:Hide()
	parts.key, divider.kitStatKey = key, key
	divider:SetLabel(title and Plain(title:GetText()) or "")
	FitDividerLabel(divider, db.statsFontSize + 2)
	divider.label:SetTextColor(HeaderColor())
	divider:SetFolded(foldable and db.collapsedStats[key] and true or false, true)
	divider:Show()
	if title then
		title:SetAlpha(0)
		titleFaded[title] = true
	end
end

function M:StyleCategories(pane)
	local modern = Modern(self.db)
	for cat, key in pairs(CategoryKeys(pane)) do
		local bar = chrome.statBars and chrome.statBars[cat]
		if bar then bar:SetShown(not modern) end
		if modern then AlphaZero(cat.Background) end
		StyleHeader(cat, key, modern)
	end
end

-- A header row of Forever's stats list: a flat bar (classic) or the fold
-- divider (modern).
local function StyleListHeader(row, modern)
	if not (row.Title and row.Background and not row.Label) then return end
	AlphaZero(row.Background)
	local bar = catBars[row]
	if not bar and not modern then
		bar = Backdrop(row, false, true)
		catBars[row] = bar
	end
	if bar then
		bar:SetShown(not modern)
		bar:SetBackdropColor(HeaderFill())
	end
	if row.Title.SetJustifyH then row.Title:SetJustifyH("CENTER") end
	StyleHeader(row, ListKey(row.Title:GetText()), modern)
end

-- A stat row in the modern layout reads like the kit's value row: label
-- left, value right on Blizzard's one value edge. A label too long for the
-- room left of the value (Large text, long translations) is cut short
-- instead of running under the value.
local function FitStatRow(frame, modern)
	local label, value = frame.Label, frame.Value
	if not (label and value and label.SetWidth) then return end
	if not modern then
		if labelFitted[label] then
			labelFitted[label] = nil
			label:SetWidth(0)
		end
		return
	end
	local width = frame:GetWidth()
	local text = Plain(value:GetText())
	if type(width) ~= "number" or width <= 0 or not text then return end
	local left = select(4, label:GetPoint(1))
	local room = width - (type(left) == "number" and left or 0) - 16 - (text ~= "" and value:GetStringWidth() or 0)
	label:SetWordWrap(false)
	label:SetWidth(math.max(math.floor(room), 1))
	labelFitted[label] = true
end

function M:StyleStats()
	if not SkinOn() then return end
	local pane = StatsContainer()
	if not Usable(pane) then return end
	local size = self.db.statsFontSize
	local hr, hg, hb = HeaderColor()
	local modern = Modern(self.db)
	local list = pane ~= _G.CharacterStatsPane
	Walk(pane, list and 5 or 4, function(frame)
		local label = Label(frame)
		local isCategory = label:find("Category") or label:find("Header")
		if list then StyleListHeader(frame, modern) end
		if frame.Label and frame.Value and frame.Background and frame.Background.SetAlpha then
			frame.Background:SetAlpha(self.db.statRowBg and 1 or 0)
		end
		-- Window text (no outline); the modern labels are white like the
		-- kit's value rows, the classic ones keep the muted gray.
		for _, fs in ipairs(FontStrings(frame)) do
			local fsLabel = fs:GetName() or ""
			if fs == frame.Title or fs == frame.Header or (isCategory and fs ~= frame.Value) or fsLabel:find("Header") then
				FitHeaderFont(fs, frame, size + 2)
				fs:SetTextColor(hr, hg, hb)
			elseif frame == pane.ItemLevelFrame then
				E:SetWindowFont(fs, size + 6)
			elseif fs == frame.Label or fsLabel:find("Label$") then
				E:SetWindowFont(fs, size)
				fs:SetTextColor(E:TokenColor(modern and "body" or "secondary"))
				if modern then fs:SetJustifyH("LEFT") end
			else
				-- Values: our font; Blizzard's inline color codes for
				-- buffed or debuffed stats still show.
				E:SetWindowFont(fs, size)
				fs:SetTextColor(1, 1, 1)
				if modern and fs == frame.Value then fs:SetJustifyH("RIGHT") end
			end
		end
		if frame.Label and frame.Value then FitStatRow(frame, modern) end
	end)
	if pane == _G.CharacterStatsPane then self:StyleCategories(pane) end
end

---------------------------------------------------------------------------
-- Folding Forever's scrolling stats list. Blizzard keeps its own list of
-- rows (box.elementData) and builds it again on every stats update. While
-- a section is folded, the scroll box shows a copy of that list without
-- the section's stats; Blizzard's list itself is never written to, the
-- values stay Blizzard's own, and Blizzard's full list comes back as soon
-- as nothing is folded.
---------------------------------------------------------------------------
local listFold = setmetatable({}, { __mode = "k" }) -- stats list -> the data provider we gave its scroll box
local foldDepth = 0

local function Retain()
	local constants = rawget(_G, "ScrollBoxConstants")
	return type(constants) == "table" and constants.RetainScrollPosition or nil
end

function M:FoldStatList(box, off)
	local scroll = box and box.ScrollBox
	local data = box and box.elementData
	local create = rawget(_G, "CreateDataProvider")
	if foldDepth > 2 or not (Usable(scroll) and type(scroll.SetDataProvider) == "function" and type(data) == "table"
		and type(create) == "function") then return end
	local db = self.db
	local on = not off and self.active and SkinOn() and db.collapsibleStats and Modern(db)
	local shown, hidden, folded = {}, 0, false
	for _, entry in ipairs(data) do
		if type(entry) == "table" and entry.isHeader then
			local key = ListKey(entry.name)
			folded = (on and CanCollapse(db, key) and db.collapsedStats[key]) and true or false
			shown[#shown + 1] = entry
		elseif folded then
			hidden = hidden + 1
		else
			shown[#shown + 1] = entry
		end
	end
	local mine = listFold[box]
	local current = type(scroll.GetDataProvider) == "function" and scroll:GetDataProvider() or nil
	foldDepth = foldDepth + 1
	local ok, err = pcall(function()
		if hidden == 0 then
			-- Nothing folded: Blizzard's own list again, if ours is still up.
			listFold[box] = nil
			if mine and current == mine then scroll:SetDataProvider(create(data), Retain()) end
			return
		end
		local provider = create(shown)
		listFold[box] = provider
		scroll:SetDataProvider(provider, Retain())
	end)
	foldDepth = foldDepth - 1
	if not ok then geterrorhandler()(err) end
end

function M:FoldStatLists(off)
	for _, box in ipairs(StatScrollBoxes()) do self:FoldStatList(box, off) end
end

-- Blizzard rebuilds the list on every stats update, and drops rows it
-- hides into a fresh list of its own: fold again right after both.
local foldHooked = setmetatable({}, { __mode = "k" })
function HookStatList(box)
	if foldHooked[box] then return end
	foldHooked[box] = true
	if type(box.UpdateStats) == "function" then
		hooksecurefunc(box, "UpdateStats", function(self) if M.active and ElementOn() then M:FoldStatList(self) end end)
	end
	if type(box.HideElements) == "function" then
		hooksecurefunc(box, "HideElements", function(self)
			local provider, scroll = listFold[self], self.ScrollBox
			if provider and M.active and ElementOn() and scroll and type(scroll.GetDataProvider) == "function"
				and scroll:GetDataProvider() ~= provider then
				M:FoldStatList(self)
			end
		end)
	end
end

---------------------------------------------------------------------------
-- Folding stat sections. Blizzard lays the pane out in
-- PaperDollFrame_UpdateStats; right after it, the stats of a folded
-- section go to alpha 0 (mouse off) and the next section header is
-- anchored under the folded one. The points we change are remembered and
-- put back before every pass, so nothing drifts. Stats are never
-- recomputed: the values stay Blizzard's own.
---------------------------------------------------------------------------
local collapse = {
	points = setmetatable({}, { __mode = "k" }),  -- frame -> its points before we moved it
	hidden = setmetatable({}, { __mode = "k" }),  -- frame -> mouse state before we faded it
	fresh = false,                                -- Blizzard re-laid the pane since our last pass
}

function M:ApplyCollapse()
	local pane = _G.CharacterStatsPane
	if not Usable(pane) or eye.on then return end
	if collapse.fresh then
		wipe(collapse.points)
	else
		for frame, points in pairs(collapse.points) do
			frame:ClearAllPoints()
			for _, point in ipairs(points) do frame:SetPoint(unpack(point, 1, 5)) end
		end
		wipe(collapse.points)
	end
	collapse.fresh = false
	for frame, mouse in pairs(collapse.hidden) do
		frame:SetAlpha(1)
		frame:EnableMouse(mouse)
	end
	wipe(collapse.hidden)
	-- Forever's scrolling list folds through its data (M:FoldStatList).
	if not SkinOn() or not Modern(self.db) or not self.db.collapsibleStats or not pane:IsShown() then return end

	local cats = CategoryKeys(pane)
	local list = {}
	for _, child in ipairs({ pane:GetChildren() }) do
		if Usable(child) and not ours[child] and child:IsShown()
			and (cats[child] or child == pane.ItemLevelFrame or (child.Label and child.Value)) then
			local top = child:GetTop()
			if not top then return end -- not laid out yet; the next update tries again
			list[#list + 1] = { frame = child, top = top }
		end
	end
	table.sort(list, function(a, b) return a.top > b.top end)

	local folded
	for _, entry in ipairs(list) do
		local frame = entry.frame
		local key = cats[frame]
		if key then
			if folded then
				local points = {}
				for i = 1, frame:GetNumPoints() do points[i] = { frame:GetPoint(i) } end
				if #points > 0 then
					collapse.points[frame] = points
					frame:ClearAllPoints()
					for _, point in ipairs(points) do
						frame:SetPoint(point[1], folded, point[3], point[4], point[5])
					end
				end
			end
			folded = (CanCollapse(self.db, key) and self.db.collapsedStats[key]) and frame or nil
		elseif folded then
			collapse.hidden[frame] = frame:IsMouseEnabled()
			frame:SetAlpha(0)
			frame:EnableMouse(false)
		end
	end
end

function M:SafeCollapse()
	local ok, err = pcall(self.ApplyCollapse, self)
	if not ok then geterrorhandler()(err) end
end

---------------------------------------------------------------------------
-- Character window tabs (the icon strip) and paper doll sidebar tabs
---------------------------------------------------------------------------
local function TabIcon(tab)
	local name = tab:GetName()
	local icon = tab.Icon or tab.icon or tab.TabIcon or (name and (_G[name .. "Icon"] or _G[name .. "IconTexture"]))
	if type(icon) == "table" and icon.IsObjectType and icon:IsObjectType("Texture") then return icon end
end

local function FindTabs()
	local list, seen = {}, {}
	local function Add(tab)
		if Usable(tab) and not seen[tab] and not ours[tab] and tab:IsObjectType("Button") then
			seen[tab] = true
			list[#list + 1] = tab
		end
	end
	for i = 1, 12 do
		Add(_G["CharacterFrameTab" .. i])
		Add(_G["CharacterFrameSideTab" .. i])
	end
	for _, key in ipairs({ "Tabs", "SideTabs", "TabButtons" }) do
		if type(CharacterFrame[key]) == "table" then
			for _, tab in ipairs(CharacterFrame[key]) do Add(tab) end
		end
	end
	-- Anything else on the window that calls itself a tab.
	Walk(CharacterFrame, 2, function(frame)
		if frame ~= CharacterFrame and frame:IsObjectType("Button") then
			local label = Label(frame)
			if label:find("Tab") and not label:find("PaperDollSidebar") then Add(frame) end
		end
	end)
	return list
end

local function IsSelectedTab(tab, index)
	if tab.GetChecked and tab:GetChecked() then return true end
	if tab.isSelected then return true end
	local selected = CharacterFrame.selectedTab
	if selected then
		local id = tab:GetID()
		return (id ~= 0 and id or index) == selected
	end
	return false
end

function M:SkinTabs()
	-- Forever's mode tabs along the right edge (Character, Reputation,
	-- Skills, PvP, Currency, Statistics): flat icon boxes, accent when open.
	if CharacterFrame.ModeTabs and E.WindowKit then E.WindowKit.SkinSideTabs(CharacterFrame.ModeTabs.Tabs) end
	-- Accent-underline style: the shared kit does the work.
	if self.db.tabStyle == "underline" then
		local list = {}
		for _, tab in ipairs(FindTabs()) do
			if not tabParts[tab] then list[#list + 1] = tab end
		end
		E:SkinTabs(list, { size = 13 })
		return
	end
	for index, tab in ipairs(FindTabs()) do
		if not tabParts[tab] and not E:GetSkin(tab, "tab") then
			local icon = TabIcon(tab)
			StripRegions(tab, icon and { [icon] = true } or nil)
			local highlight = tab.GetHighlightTexture and tab:GetHighlightTexture()
			AlphaZero(highlight)
			if icon then
				E:TrimIcon(icon)
				icon:ClearAllPoints()
				icon:SetPoint("TOPLEFT", E.pixel * 2, -E.pixel * 2)
				icon:SetPoint("BOTTOMRIGHT", -E.pixel * 2, E.pixel * 2)
			end
			local parts = { border = Backdrop(tab, false), icon = icon, index = index }
			-- Our own highlight; the HIGHLIGHT layer shows it on mouse-over.
			parts.hover = tab:CreateTexture(nil, "HIGHLIGHT")
			parts.hover:SetPoint("TOPLEFT", E.pixel, -E.pixel)
			parts.hover:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
			parts.hover:SetColorTexture(1, 1, 1, E.tokens.hover.control)
			tab:HookScript("OnClick", function() C_Timer.After(0, function() M:UpdateTabs() end) end)
			local text = tab.Text or (tab.GetFontString and tab:GetFontString())
			if text then E:SetFont(text, E.tokens.size.body) end
			tabParts[tab] = parts
		elseif tabParts[tab] then
			-- Already a box tab (a tab the underline style took keeps that look until /reload).
			tabParts[tab].index = index
		end
	end
end

function M:UpdateTabs()
	if not Allowed("skin") then return end
	if E.WindowKit then E.WindowKit.UpdateSideTabs() end
	local r, g, b = Accent()
	for tab, parts in pairs(tabParts) do
		if parts.sidebar then
			local selected
			if tab.Hider then
				selected = not tab.Hider:IsShown()
			elseif tab.GetChecked then
				selected = tab:GetChecked()
			end
			if selected then parts.border:SetBackdropBorderColor(r, g, b, 1)
			else parts.border:SetBackdropBorderColor(unpack(E.media.borderColor)) end
		elseif self.db.sideTabs then
			local selected = IsSelectedTab(tab, parts.index)
			if selected then
				parts.border:SetBackdropBorderColor(r, g, b, 1)
				parts.border:SetBackdropColor(r * 0.25, g * 0.25, b * 0.25, 0.9)
			else
				parts.border:SetBackdropBorderColor(unpack(E.media.borderColor))
				parts.border:SetBackdropColor(unpack(E.media.backdropColor))
			end
			local text = tab.Text or (tab.GetFontString and tab:GetFontString())
			if text then
				if selected then text:SetTextColor(r, g, b) else text:SetTextColor(E:TokenColor("secondary")) end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Side panels: reputation, skills, PvP, currency, statistics and any other
-- panel the window shows. Frame names differ between clients, so each
-- group lists every name it might have; missing ones are skipped.
---------------------------------------------------------------------------
local PANEL_GROUPS = {
	{ key = "panelReputation", names = { "ReputationFrame", "CharacterReputationFrame" },
		details = { "ReputationDetailFrame" }, funcs = { "ReputationFrame_Update" } },
	{ key = "panelSkills", names = { "SkillFrame", "CharacterSkillsFrame", "SkillsFrame", "CharacterSkillFrame" },
		details = { "SkillDetailScrollFrame", "SkillDetailScrollChildFrame" }, funcs = { "SkillFrame_UpdateSkills", "SkillFrame_Update" } },
	{ key = "panelPvP", names = { "PVPRankFrame", "PVPFrame", "HonorFrame", "CharacterHonorFrame", "CharacterPVPFrame", "PVPFrameHonor" },
		details = {}, funcs = { "PVPFrame_Update", "HonorFrame_Update", "PVPHonor_Update" } },
	{ key = "panelCurrency", names = { "TokenFrame", "CurrencyFrame", "CharacterCurrencyFrame" },
		details = { "TokenFramePopup", "TokenDetailFrame" }, funcs = { "TokenFrame_Update" } },
	{ key = "panelStatistics", names = { "CharacterStatisticsFrame", "StatisticsFrame", "CharacterStatsFrame", "PlayerStatisticsFrame" },
		details = {}, funcs = { "StatisticsFrame_Update" } },
}

local DECORATION = { "Inset", "Bg", "Background", "Parchment", "Border", "Stone", "Corner", "Divider" }
local NOT_DECORATION = { Button = true, CheckButton = true, StatusBar = true, EditBox = true, Slider = true, ItemButton = true, Cooldown = true, Model = true, PlayerModel = true, ModelScene = true }

local function IsDecoration(frame)
	local kind = frame:GetObjectType()
	if NOT_DECORATION[kind] then return false end
	if kind == "ScrollFrame" then return true end
	local label = Label(frame)
	for _, word in ipairs(DECORATION) do
		if label:find(word) then return true end
	end
	return false
end

local function IsHeader(frame)
	if not frame:IsObjectType("Button") and not frame:IsObjectType("Frame") then return false end
	if frame:IsObjectType("StatusBar") then return false end
	if frame.isHeader == true then return true end
	if frame.GetElementData then
		local ok, data = pcall(frame.GetElementData, frame)
		if ok and type(data) == "table" and (data.isHeader == true or data.isCategory == true) then return true end
	end
	if frame.ExpandOrCollapseButton or frame.CollapseButton or frame.ExpandCollapseButton or frame.ToggleCollapseButton then return true end
	local name = frame:GetName() or ""
	return name:find("Header%d*$") ~= nil or name:find("TypeLabel%d+$") ~= nil or name:find("CategoryHeader") ~= nil
end

local function IsDetail(frame)
	if not frame:IsObjectType("Frame") or frame:IsObjectType("Button") or frame:IsObjectType("StatusBar") then return false end
	local label = Label(frame)
	return label:find("Detail") ~= nil or label:find("Popup") ~= nil
end

-- Status bar: flat EldoUI texture with a 1-pixel border; Blizzard's
-- colors (reputation standing, skill blue) are kept.
local function SkinBar(bar)
	local parts = bars[bar]
	if not parts then
		parts = {}
		bars[bar] = parts
		local fill = bar:GetStatusBarTexture()
		for _, region in ipairs({ bar:GetRegions() }) do
			if region:IsObjectType("Texture") and region ~= fill and region:GetDrawLayer() ~= "HIGHLIGHT" then
				region:SetAlpha(0)
			elseif region:IsObjectType("FontString") then
				E:SetFont(region, FontSize(region, 12))
			end
		end
		-- Border/background art that lives on child frames of the bar.
		for _, child in ipairs({ bar:GetChildren() }) do
			if Usable(child) and not ours[child] and not child:IsObjectType("StatusBar") then
				local label = Label(child)
				if label:find("Border") or label:find("Background") or label:find("Bg") then
					StripRegions(child)
					if child.GetNormalTexture and child:GetNormalTexture() then child:GetNormalTexture():SetAlpha(0) end
				end
				for _, fs in ipairs(FontStrings(child)) do E:SetFont(fs, FontSize(fs, 12)) end
			end
		end
		parts.bd = Backdrop(bar, false, false, E.pixel)
		parts.bd:SetBackdropColor(0, 0, 0, 0.5)
	end
	local fill = bar:GetStatusBarTexture()
	-- Atlas fills carry their color in the art; those stay as they are.
	if fill and not (fill.GetAtlas and fill:GetAtlas()) and (parts.fill ~= fill or parts.tex ~= fill:GetTexture() or parts.file ~= E.media.statusbar) then
		local r, g, b, a = bar:GetStatusBarColor()
		bar:SetStatusBarTexture(E.media.statusbar)
		if r then bar:SetStatusBarColor(r, g, b, a) end
		fill = bar:GetStatusBarTexture()
		parts.fill, parts.tex, parts.file = fill, fill and fill:GetTexture(), E.media.statusbar
	end
end

-- Category header: flat dark bar with accent text; the expand/collapse
-- indicator stays.
local function SkinHeader(frame, isHeader)
	local bd = headers[frame]
	if not isHeader then
		if bd then bd:Hide() end
		return
	end
	if not bd then
		StripRegions(frame, KeepSet(frame))
		bd = Backdrop(frame, false)
		headers[frame] = bd
	end
	bd:SetBackdropColor(HeaderFill())
	bd:Show()
	local r, g, b = HeaderColor()
	local fontStrings = FontStrings(frame)
	if frame.GetFontString and frame:GetFontString() then fontStrings[#fontStrings + 1] = frame:GetFontString() end
	for _, fs in ipairs(fontStrings) do
		FitHeaderFont(fs, frame, FontSize(fs, 13))
		fs:SetTextColor(r, g, b)
	end
end

local function SkinDetail(frame)
	if details[frame] then return end
	StripRegions(frame, KeepSet(frame))
	for _, child in ipairs({ frame:GetChildren() }) do
		if Usable(child) and not ours[child] and IsDecoration(child) then StripRegions(child) end
	end
	details[frame] = Backdrop(frame, true)
	for _, fs in ipairs(FontStrings(frame)) do
		local label = Label(fs)
		if label:find("Title") or label:find("Name") then
			SetHeaderFont(fs, FontSize(fs, 15))
		else
			E:SetFont(fs, FontSize(fs, 12))
		end
	end
end

local QueueRestyle

local function WatchScrollBox(box, panel)
	if boxes[box] then return end
	boxes[box] = true
	local function Again() QueueRestyle(panel) end
	if ScrollUtil and ScrollUtil.AddAcquiredFrameCallback then
		pcall(ScrollUtil.AddAcquiredFrameCallback, box, Again, M, false)
	end
	pcall(box.RegisterCallback, box, "OnDataRangeChanged", Again, M)
end

function M:RestylePanel(panel)
	if not self.active or not Usable(panel) then return end
	Walk(panel, 8, function(frame)
		if frame == panel or frame == _G.PaperDollFrame then return end
		if frame:IsObjectType("StatusBar") then
			SkinBar(frame)
			return
		end
		if Label(frame):find("ScrollBar") and (frame.GetThumb or frame.Track or frame:IsObjectType("Slider")) then
			E:SkinScrollBar(frame)
			return
		end
		if type(frame.ForEachFrame) == "function" and type(frame.RegisterCallback) == "function" then
			WatchScrollBox(frame, panel)
		end
		if IsDetail(frame) then
			SkinDetail(frame)
		elseif IsHeader(frame) then
			SkinHeader(frame, true)
		elseif headers[frame] then
			SkinHeader(frame, false)
		elseif not stripped[frame] and IsDecoration(frame) then
			stripped[frame] = true
			StripRegions(frame)
		end
	end)
end

QueueRestyle = function(panel)
	if queuedPanels[panel] then return end
	queuedPanels[panel] = true
	C_Timer.After(0, function()
		queuedPanels[panel] = nil
		M:RestylePanel(panel)
	end)
end

local function SkinPanel(panel)
	if not Usable(panel) then return end
	if not stripped[panel] then
		stripped[panel] = true
		StripRegions(panel, KeepSet(panel))
		for _, fs in ipairs(FontStrings(panel)) do
			if Label(fs):find("Title") then
				SetHeaderFont(fs, 15)
				fs:SetTextColor(1, 1, 1)
			end
		end
	end
	if not hookedPanels[panel] then
		hookedPanels[panel] = true
		panel:HookScript("OnShow", function()
			QueueRestyle(panel)
			C_Timer.After(0, function() M:UpdateTabs() end)
		end)
		for _, method in ipairs({ "Update", "Refresh", "UpdateList" }) do
			if type(panel[method]) == "function" then
				hooksecurefunc(panel, method, function() QueueRestyle(panel) end)
			end
		end
	end
	M:RestylePanel(panel)
end

function M:SkinPanels()
	local known = {}
	if _G.PaperDollFrame then known[_G.PaperDollFrame] = true end
	for _, group in ipairs(PANEL_GROUPS) do
		for _, name in ipairs(group.names) do
			local panel = _G[name]
			if Usable(panel) then
				known[panel] = true
				if self.db[group.key] then SkinPanel(panel) end
			end
		end
		if self.db[group.key] then
			for _, name in ipairs(group.details) do
				local frame = _G[name]
				if Usable(frame) and not frame:IsObjectType("ScrollFrame") then SkinDetail(frame)
				elseif Usable(frame) and not stripped[frame] then stripped[frame] = true; StripRegions(frame) end
			end
			for _, name in ipairs(group.funcs) do
				if type(_G[name]) == "function" and not hookedPanels[name] then
					hookedPanels[name] = true
					hooksecurefunc(name, function()
						for _, panelName in ipairs(group.names) do
							if Usable(_G[panelName]) then QueueRestyle(_G[panelName]) end
						end
					end)
				end
			end
		end
	end
	-- Any other named panel the window carries.
	if not self.db.panelOther then return end
	for _, frame in ipairs({ _G.CharacterFrameInset, _G.CharacterFrameInsetRight, CharacterFrame.NineSlice,
		CharacterFrame.PortraitContainer, CharacterFrame.TitleContainer, CharacterFrame.CloseButton,
		CharacterFrame.LeftPaneHost, CharacterFrame.RightPaneHost, CharacterFrame.ModeTabs, CharacterFrame.TabIndicators,
		_G.CharacterStatsPane, _G.CharacterStatsPaneScrollBox, _G.CharacterStatsPanePetScrollBox, _G.PaperDollSidebarTabs }) do
		if frame then known[frame] = true end
	end
	for _, child in ipairs({ CharacterFrame:GetChildren() }) do
		if Usable(child) and not known[child] and not ours[child] and not tabParts[child]
			and child:GetObjectType() == "Frame" then
			local name = child:GetName()
			if name and not name:find("Tab") and not name:find("Inset") then SkinPanel(child) end
		end
	end
end

---------------------------------------------------------------------------
-- Gear sets. Blizzard's own equipment sets (C_EquipmentSet): a row of
-- set buttons on the paper doll and an info bar "Gear" block. Every swap is
-- a click and happens out of combat; nothing picks "best" gear. Saving and
-- editing sets stays in Blizzard's equipment manager tab.
-- "Equip after combat" (off by default; review verbesserungen.md, B12): a
-- set clicked in combat is kept and goes on once combat ends (or, when you
-- are dead then, once you are alive again). Only the last click counts; a
-- second click on that set, or a click on the set you wear, takes it back.
-- Nothing is kept past a reload. Written from scratch; no addon code reused.
---------------------------------------------------------------------------
local gear = { buttons = {} } -- pending: the set ID that goes on after combat
local GEAR_OWNER = "Character:gearAfterCombat" -- its own event owner (the module's events stay as they are)

local function SetsAvailable()
	return C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs and true or false
end

-- Every set as { id, name, icon, equipped, numItems, numEquipped, numLost }.
local function GearSets()
	local list = {}
	if not SetsAvailable() then return list end
	local ok, ids = pcall(C_EquipmentSet.GetEquipmentSetIDs)
	if not ok or type(ids) ~= "table" then return list end
	for _, id in ipairs(ids) do
		local name, icon, setID, isEquipped, numItems, numEquipped, _, numLost = C_EquipmentSet.GetEquipmentSetInfo(id)
		if name then
			list[#list + 1] = { id = setID or id, name = name, icon = icon, equipped = isEquipped,
				numItems = numItems or 0, numEquipped = numEquipped or 0, numLost = numLost or 0 }
		end
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end

local function EquippedSetName()
	for _, set in ipairs(GearSets()) do
		if set.equipped then return set.name end
	end
end

-- The name of a set and whether you wear it, read in pcall (nil, false
-- for a set that is gone).
local function SetState(id)
	local ok, name, _, _, isEquipped = pcall(C_EquipmentSet.GetEquipmentSetInfo, id)
	if not ok or type(name) ~= "string" or E:IsSecret(name) then return nil, false end
	return name, (not E:IsSecret(isEquipped) and isEquipped) and true or false
end

local TryPendingSet -- below: puts the kept set on

local function WatchPending(on)
	for _, event in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
		if on then
			E:RegisterEvent(event, function() TryPendingSet() end, GEAR_OWNER)
		else
			E:UnregisterEvent(event, GEAR_OWNER)
		end
	end
end

local function SetPending(id)
	gear.pending = id
	WatchPending(id ~= nil)
	if M.active then M:UpdateGear() end
end

-- A click in combat with "Equip after combat" on: keep the set, or take
-- the kept one back (its second click, or a click on the set you wear).
local function KeepSet(id)
	local name, isEquipped = SetState(id)
	if not name then return end
	if gear.pending and (gear.pending == id or isEquipped) then
		SetPending(nil)
		UIErrorsFrame:AddMessage(L["EldoUI: no set change after combat."], unpack(E.tokens.text.warn))
	elseif not isEquipped then
		SetPending(id)
		UIErrorsFrame:AddMessage(L["EldoUI: %s goes on when combat ends. Click it again to keep your gear."]:format(name), unpack(E.tokens.text.good))
	end
end

-- Equip a set. `why` names the trigger for the chat line.
local function EquipSet(id, why)
	if not SetsAvailable() or not id then return false end
	if InCombatLockdown() then
		if M.db.gearAfterCombat then
			KeepSet(id)
		else
			UIErrorsFrame:AddMessage(L["EldoUI: gear sets change only out of combat."], unpack(E.tokens.text.warn))
		end
		return false
	end
	-- A click out of combat wins over a set kept from the fight.
	if gear.pending then SetPending(nil) end
	local name, isEquipped = SetState(id)
	if not name or isEquipped then return false end
	local ok = pcall(C_EquipmentSet.UseEquipmentSet, id)
	if ok and why then M:Print(L["%s: equipped %s."]:format(why, name)) end
	return ok
end
M.EquipSet = function(_, id) return EquipSet(id) end

-- After combat (or once you are alive again): the kept set goes on. The
-- switch turned off in the meantime drops it.
TryPendingSet = function()
	local id = gear.pending
	if not id then
		WatchPending(false)
		return
	end
	if InCombatLockdown() then return end
	if not M.db.gearAfterCombat then
		SetPending(nil)
		return
	end
	local ok, dead = pcall(UnitIsDeadOrGhost, "player")
	if ok and not E:IsSecret(dead) and dead then return end
	SetPending(nil)
	EquipSet(id, L["After combat"])
end
M.TryPendingSet = TryPendingSet
M.PendingSet = function() return gear.pending end -- tools/character/test_gear_after_combat.lua

-- The menu of the info bar block: equip a set with a click. EldoUI never
-- swaps gear on its own (no spec or stance swaps); "Equip after combat"
-- only finishes a click from the fight.
local function GearMenu(owner)
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(L["Gear sets"])
		local sets = GearSets()
		if #sets == 0 then
			-- Only says what to do: a row that cannot be clicked.
			root:CreateButton(L["No sets yet: save one in the equipment manager"], function() end):SetEnabled(false)
		end
		for _, set in ipairs(sets) do
			local label = set.equipped and (E:TextHex("good") .. "%s|r"):format(set.name) or set.name
			local sub = root:CreateButton(label, function() EquipSet(set.id) end)
			sub:CreateButton(L["Equip"], function() EquipSet(set.id) end)
		end
	end)
end

if E.RegisterDataText then
	E:RegisterDataText("Gear", {
		events = { "EQUIPMENT_SETS_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "EQUIPMENT_SWAP_FINISHED" },
		text = function()
			local r, g, b = unpack(E.media.accentColor)
			local name = EquippedSetName()
			return ("|cff%02x%02x%02x%s|r %s"):format(r * 255, g * 255, b * 255, L["Gear"],
				name and ("|cffffffff%s|r"):format(name) or (E:TextHex("secondary") .. L["no set"] .. "|r"))
		end,
		tooltip = function(tooltip)
			E.UIKit.TipTitle(tooltip, L["Gear sets"])
			local sets = GearSets()
			if #sets == 0 then E.UIKit.TipText(tooltip, L["Save a set in the character window's equipment manager."]) end
			local pending = gear.pending and SetState(gear.pending)
			if pending then tooltip:AddLine(L["After combat: %s"]:format(pending), E:TokenColor("warn")) end
			for _, set in ipairs(sets) do
				local right = ("%d/%d"):format(set.numEquipped, set.numItems)
				if set.numLost > 0 then right = right .. " " .. E:TextHex("bad") .. L["%d missing"]:format(set.numLost) .. "|r" end
				if set.equipped then
					tooltip:AddDoubleLine(set.name, right, 0.27, 0.87, 0.27, 1, 1, 1)
				else
					E.UIKit.TipPair(tooltip, set.name, right, unpack(E.UIKit.SECONDARY))
				end
			end
			E:TooltipHint(tooltip, { L["Click"], M.db.gearAfterCombat and L["equip a set (in combat: when it ends)"] or L["equip a set (out of combat)"] })
		end,
		onClick = function(button) GearMenu(button) end,
	})
end

-- Set buttons on the paper doll.
local function GearButton(index)
	local button = gear.buttons[index]
	if button then return button end
	button = CreateFrame("Button", nil, gear.bar)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	button.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(button.icon)
	button.bd = Backdrop(button, false)
	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints(button.icon)
	hover:SetColorTexture(1, 1, 1, E.tokens.hover.hud)
	button:SetScript("OnClick", function(self, mouse)
		if E:IsOptionsLinkClick(self, mouse) then return end
		EquipSet(self.setID)
	end)
	button:SetScript("OnEnter", function(self)
		if E.FrameCheck(GameTooltip, "IsForbidden") then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		E.UIKit.TipTitle(GameTooltip, self.setName or "")
		if self.info then
			E.UIKit.TipText(GameTooltip, L["%d of %d items worn"]:format(self.info.numEquipped, self.info.numItems))
			if self.info.numLost > 0 then GameTooltip:AddLine(E:Plural(self.info.numLost, "%d item missing", "%d items missing"):format(self.info.numLost), E:TokenColor("bad")) end
		end
		if gear.pending == self.setID then GameTooltip:AddLine(L["Goes on when combat ends."], E:TokenColor("warn")) end
		E:TooltipHint(GameTooltip, { L["Click"], M.db.gearAfterCombat and L["equip (in combat: when it ends)"] or L["equip (out of combat)"] })
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() if not E.FrameCheck(GameTooltip, "IsForbidden") then GameTooltip:Hide() end end)
	E:BindOptionsLink(button, { page = "module:Character", key = "gearBar" })
	ours[button] = true
	gear.buttons[index] = button
	return button
end

function M:UpdateGear()
	local show = ImproveOn() and Additions() and self.db.gearBar and SetsAvailable() and PaperDollShown()
	if not show then
		if gear.bar then gear.bar:Hide() end
		return
	end
	if not gear.bar then
		gear.bar = CreateFrame("Frame", nil, Overlay())
		gear.bar:SetSize(1, 1)
		ours[gear.bar] = true
	end
	local bar = gear.bar
	local size = self.db.gearBarSize or 20
	bar:ClearAllPoints()
	if self.db.gearBarPosition == "BELOW" then
		bar:SetPoint("TOPLEFT", CharacterFrame, "BOTTOMLEFT", 0, -4)
	else
		local strip = _G.PaperDollFrame and _G.PaperDollFrame.TopBackgroundStripHost
		if Usable(strip) then
			bar:SetPoint("LEFT", strip, "LEFT", 8, 0)
		else
			bar:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 8, -30)
		end
	end
	local sets = GearSets()
	local r, g, b = Accent()
	for index, set in ipairs(sets) do
		local button = GearButton(index)
		button:SetSize(size, size)
		button:ClearAllPoints()
		button:SetPoint("LEFT", bar, "LEFT", (index - 1) * (size + 3), 0)
		button.setID, button.setName, button.info = set.id, set.name, set
		button.icon:SetTexture(set.icon or 134400)
		if set.equipped then
			button.bd:SetBackdropBorderColor(r, g, b, 1)
		elseif gear.pending == set.id then
			button.bd:SetBackdropBorderColor(E:TokenColor("warn", 1))
		elseif set.numLost > 0 then
			button.bd:SetBackdropBorderColor(E:TokenColor("bad", 1))
		else
			button.bd:SetBackdropBorderColor(unpack(E.media.borderColor))
		end
		button:Show()
	end
	for index = #sets + 1, #gear.buttons do gear.buttons[index]:Hide() end
	bar:SetShown(#sets > 0)
end

---------------------------------------------------------------------------
-- Slot flyout: hover a trinket or ring slot with the window open to
-- see the matching items in your bags; click one to wear it in that slot.
-- Out of combat only, and only on that click.
---------------------------------------------------------------------------
local FLYOUT_SLOTS = {
	Trinket0Slot = { INVTYPE_TRINKET = true }, Trinket1Slot = { INVTYPE_TRINKET = true },
	Finger0Slot = { INVTYPE_FINGER = true }, Finger1Slot = { INVTYPE_FINGER = true },
}
local flyout = { buttons = {} }

local function BagItemsFor(kinds)
	local list = {}
	local bags = E.BagCache
	for _, bag in ipairs(bags:BagIDs()) do
		for slot = 1, bags:NumSlots(bag) do
			local link = bags:Link(bag, slot)
			if link then
				local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
				if equipLoc and kinds[equipLoc] then
					local info = bags:Info(bag, slot)
					list[#list + 1] = { link = link, icon = info and info.iconFileID, quality = info and info.quality }
				end
			end
		end
	end
	return list
end

local function HideFlyout()
	if flyout.frame then flyout.frame:Hide() end
end

local function ShowFlyout(info)
	local kinds = FLYOUT_SLOTS[info.name]
	if not kinds or not ImproveOn() or not Additions() or not M.db.slotFlyout or InCombatLockdown() then return end
	local items = BagItemsFor(kinds)
	if #items == 0 then HideFlyout() return end
	if not flyout.frame then
		local frame = CreateFrame("Frame", nil, Overlay())
		frame:SetFrameStrata("DIALOG")
		E:SetTemplate(frame, true)
		frame:EnableMouse(true)
		frame:SetScript("OnLeave", function(self)
			C_Timer.After(0.2, function()
				if not self:IsMouseOver() and not (flyout.owner and flyout.owner:IsMouseOver()) then self:Hide() end
			end)
		end)
		ours[frame] = true
		flyout.frame = frame
	end
	local frame, size = flyout.frame, 30
	frame:ClearAllPoints()
	local side = SLOT_SIDE[info.name] == "LEFT" and "RIGHT" or "LEFT"
	if side == "RIGHT" then
		frame:SetPoint("TOPLEFT", info.button, "TOPRIGHT", 4, 0)
	else
		frame:SetPoint("TOPRIGHT", info.button, "TOPLEFT", -4, 0)
	end
	for index, item in ipairs(items) do
		local button = flyout.buttons[index]
		if not button then
			button = CreateFrame("Button", nil, frame)
			button.icon = button:CreateTexture(nil, "ARTWORK")
			button.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
			button.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
			E:TrimIcon(button.icon)
			button.bd = Backdrop(button, false)
			local hover = button:CreateTexture(nil, "HIGHLIGHT")
			hover:SetAllPoints(button.icon)
			hover:SetColorTexture(1, 1, 1, E.tokens.hover.hud)
			button:SetScript("OnClick", function(self)
				if InCombatLockdown() or not self.link then return end
				pcall(C_Item.EquipItemByName, self.link, self.slotID)
				HideFlyout()
			end)
			button:SetScript("OnEnter", function(self)
				if E.FrameCheck(GameTooltip, "IsForbidden") then return end
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetHyperlink(self.link)
				GameTooltip:Show()
			end)
			button:SetScript("OnLeave", function(self)
				if not E.FrameCheck(GameTooltip, "IsForbidden") then GameTooltip:Hide() end
				local parent = self:GetParent()
				if parent:GetScript("OnLeave") then parent:GetScript("OnLeave")(parent) end
			end)
			ours[button] = true
			flyout.buttons[index] = button
		end
		button:SetSize(size, size)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3 - (index - 1) * (size + 2))
		button.link, button.slotID = item.link, info.id
		button.icon:SetTexture(item.icon or 134400)
		if type(item.quality) == "number" and item.quality >= Enum.ItemQuality.Uncommon then
			button.bd:SetBackdropBorderColor(C_Item.GetItemQualityColor(item.quality))
		else
			button.bd:SetBackdropBorderColor(unpack(E.media.borderColor))
		end
		button:Show()
	end
	for index = #items + 1, #flyout.buttons do flyout.buttons[index]:Hide() end
	frame:SetSize(size + 6, #items * (size + 2) + 4)
	flyout.owner = info.button
	frame:Show()
end

local function HookFlyouts()
	if flyout.hooked then return end
	flyout.hooked = true
	CollectSlots()
	for _, info in ipairs(slots) do
		if FLYOUT_SLOTS[info.name] then
			info.button:HookScript("OnEnter", function() if M.active and ElementOn() then ShowFlyout(info) end end)
			info.button:HookScript("OnLeave", function()
				C_Timer.After(0.2, function()
					if flyout.frame and flyout.frame:IsShown() and not flyout.frame:IsMouseOver() and not info.button:IsMouseOver() then HideFlyout() end
				end)
			end)
		end
	end
end

---------------------------------------------------------------------------
-- Putting it together
---------------------------------------------------------------------------
local function AnyPanelGroup(db)
	return db.panelReputation or db.panelSkills or db.panelPvP or db.panelCurrency or db.panelStatistics or db.panelOther or db.sideTabs
end

-- What a hook may still do once it is installed: nothing unless the
-- element is on (hooks stay installed after the switch goes off).
local function Live()
	return M.active and ElementOn()
end

local function Hooks()
	if M.hooked then return end
	M.hooked = true
	CharacterFrame:HookScript("OnShow", function()
		if not Live() then return end
		M:UpdateSlots()
		M:StyleStats()
		M:UpdateTabs()
	end)
	if type(_G.PaperDollItemSlotButton_Update) == "function" then
		hooksecurefunc("PaperDollItemSlotButton_Update", function(button)
			local info = slotByButton[button]
			if Live() and info then UpdateSlot(info) end
		end)
	end
	if type(_G.PaperDollFrame_UpdateStats) == "function" then
		hooksecurefunc("PaperDollFrame_UpdateStats", function()
			if not Live() then return end
			collapse.fresh = true
			M:SafeCollapse()
			M:QueueStats()
		end)
	end
	CharacterFrame:HookScript("OnHide", function() M:SetModelOnly(false) end)
	if _G.PaperDollFrame then
		local function Follow()
			if not Live() then return end
			M:UpdateHeader()
			M:UpdateEye()
			M:UpdateAverage()
			M:UpdateGear()
			HideFlyout()
		end
		_G.PaperDollFrame:HookScript("OnShow", Follow)
		_G.PaperDollFrame:HookScript("OnHide", Follow)
	end
	if type(_G.PaperDollFrame_UpdateSidebarTabs) == "function" then
		hooksecurefunc("PaperDollFrame_UpdateSidebarTabs", function() if Live() then M:UpdateTabs() end end)
	end
	for _, name in ipairs({ "PanelTemplates_SetTab", "PanelTemplates_UpdateTabs" }) do
		if type(_G[name]) == "function" then
			hooksecurefunc(name, function(frame)
				if frame == CharacterFrame and Live() then M:UpdateTabs() end
			end)
		end
	end
	if type(_G.ToggleCharacter) == "function" then
		hooksecurefunc("ToggleCharacter", function()
			if Live() then C_Timer.After(0, function() M:UpdateTabs() end) end
		end)
	end
end

function M:QueueStats()
	if self.statsQueued or not self.active then return end
	self.statsQueued = true
	C_Timer.After(0, function()
		self.statsQueued = false
		self:StyleStats()
	end)
end

function M:QueueSlots()
	if self.slotsQueued or not Live() then return end
	self.slotsQueued = true
	C_Timer.After(0.1, function()
		self.slotsQueued = false
		if self.active then self:UpdateSlots() end
	end)
end

function M:QueueApply()
	if self.applyQueued or not self.active then return end
	self.applyQueued = true
	C_Timer.After(0.2, function()
		self.applyQueued = false
		self:Apply()
	end)
end

-- Structural skinning runs out of combat; color passes run any time.
-- With the element off this does nothing at all: no hooks, no skin.
function M:Apply()
	if not CharacterFrame or not self.active or not ElementOn() then return end
	E:RunOutOfCombat(function()
		if not self.active or not ElementOn() then return end
		self.applied = true
		Hooks()
		local db = self.db
		if Allowed("skin") then
			if db.skin or AnyPanelGroup(db) then self:SkinChrome() end
			if db.skin then
				self:SkinPaperDoll()
				E:SkinCloseButton(CharacterFrame.CloseButton or _G.CharacterFrameCloseButton)
			end
			if db.sideTabs then self:SkinTabs() end
			self:SkinPanels()
		end
		if ImproveOn() then HookFlyouts() end
		self:Refresh()
	end)
end

function M:Refresh()
	if not CharacterFrame then return end
	self:UpdateChrome()
	self:UpdateModelBackground()
	self:UpdateSlots()
	self:StyleStats()
	self:SafeCollapse()
	self:FoldStatLists()
	self:UpdateTabs()
	self:UpdateGear()
	if Allowed("skin") then
		E:UpdateTabs()
		for panel in pairs(hookedPanels) do
			if type(panel) == "table" then self:RestylePanel(panel) end
		end
	end
end

-- Back to Blizzard's window as far as it goes without a /reload: our
-- header, extras, overlays and model background go (the window mover gives
-- the scale and place back). Art made invisible by the skin needs /reload.
function M:Restore()
	if not CharacterFrame or not self.applied then return end
	self:SetModelOnly(false)
	self:UpdateHeader()
	self:UpdateEye()
	self:SafeCollapse()
	self:FoldStatLists(true)
	for cat, parts in pairs(catParts) do
		parts.fold:Hide()
		parts.plain:Hide()
		ShowTitle(cat.Title or cat.TitleText)
	end
	for _, bar in pairs(chrome.statBars or {}) do bar:Show() end
	self:UpdateAverage()
	for _, info in ipairs(slots) do
		if info.overlay then info.overlay:Hide() end
		info.missingEnchant = false
	end
	if chrome.avg then chrome.avg:Hide() end
	if chrome.avgScore then chrome.avgScore:Hide() end
	if gear.bar then gear.bar:Hide() end
	HideFlyout()
	self:UpdateModelBackground()
end

E:RegisterBlizzardHandler(ELEMENT, {
	owner = "Character",
	apply = function() M:Apply() end,
	undo = function() M:Restore() end,
	reload = { skin = true },
	install = { skin = true, move = true, improve = true },
	-- v0.5.0 skinned the window whenever its skin option was on.
	legacy = function() return M.db and M.db.enabled ~= false and M.db.skin end,
})

function M:OnEnable()
	-- Gear swaps on spec or stance were removed; forget their saved keys.
	self.db.swapOnSpec, self.db.swapOnStance, self.db.stanceSets = nil, nil, nil
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() M:QueueSlots() end)
	self:RegisterEvent("UPDATE_INVENTORY_DURABILITY", function() M:QueueSlots() end)
	self:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
		if M.missingInfo and CharacterFrame and CharacterFrame:IsShown() then M:QueueSlots() end
	end)
	-- Panels that load on demand (currency, PvP) are picked up when they arrive.
	self:RegisterEvent("ADDON_LOADED", function() M:QueueApply() end)
	-- Header line: name, title, level and specialization.
	local function Header()
		if CharacterFrame and CharacterFrame:IsShown() then M:UpdateHeader() end
	end
	self:RegisterEvent("PLAYER_LEVEL_UP", function() C_Timer.After(0, Header) end)
	-- Gamepad and mouse interface swap: EldoUI's buttons follow.
	self:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION", function()
		HideFlyout()
		M:UpdateEye()
		M:UpdateGear()
		M:QueueApply()
	end)
	self:RegisterUnitEvent("UNIT_NAME_UPDATE", "player", Header)
	self:RegisterEvent("KNOWN_TITLES_UPDATE", Header)
	-- Gear sets: the buttons follow the sets.
	pcall(self.RegisterEvent, self, "EQUIPMENT_SETS_CHANGED", function() if Live() then M:UpdateGear() end end)
	pcall(self.RegisterEvent, self, "EQUIPMENT_SWAP_FINISHED", function() if Live() then M:UpdateGear() end end)
	pcall(self.RegisterEvent, self, "PLAYER_SPECIALIZATION_CHANGED", function(_, _, unit) if unit == nil or unit == "player" then Header() end end)
	pcall(self.RegisterEvent, self, "ACTIVE_TALENT_GROUP_CHANGED", Header)
	self:Apply()
end

function M:OnDisable()
	self:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
	self:UnregisterEvent("UPDATE_INVENTORY_DURABILITY")
	self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
	self:UnregisterEvent("ADDON_LOADED")
	self:UnregisterUnitEvent("UNIT_NAME_UPDATE", "player")
	for _, event in ipairs({ "PLAYER_LEVEL_UP", "KNOWN_TITLES_UPDATE",
		"PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "EQUIPMENT_SETS_CHANGED",
		"EQUIPMENT_SWAP_FINISHED", "UPDATE_SHAPESHIFT_FORM" }) do
		pcall(self.UnregisterEvent, self, event)
	end
	-- Blizzard's own title, level line, item level and stat layout come
	-- back; the skin itself after /reload.
	self:Restore()
end

function M:OnProfileChanged()
	if self.active then self:Apply() end
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local function ElementOff()
	return not ElementOn()
end

M.options = {
	{ type = "description", hidden = function() return not ElementOff() end,
		label = "The character window is switched off on the Blizzard UI page, so it stays Blizzard's own. Type /eui blizz character-frame on to turn it on." },
	{ type = "description", label = "Skin, Move and Improve are the character window's switches on the Blizzard UI page; the settings here fine-tune each one." },
	{ type = "header", label = "Window" },
	{ type = "toggle", disabled = E:BlizzardNeeds(ELEMENT, "skin"), reload = "off", key = "skin", label = "EldoUI look for the character window", desc = "Panel, flat item slots, stats and tabs." },
	{ type = "toggle", key = "transparent", label = "See-through window", desc = "The character window lets the game show through a little. How much: General > Panel opacity." },
	{ type = "execute", label = "Open Windows", desc = "Dragging, the mouse wheel scale and the reset of the character window are on the Move windows page, with every other Blizzard window.",
		func = function() E:ToggleConfig("windows") end },
	{ type = "select", key = "header", label = "Title and level line",
		desc = "EldoUI shows \"Name the Title\" and the level, specialization and class in class color, all as the game reports them.",
		values = { blizzard = "Blizzard's", eldo = "EldoUI: name, title, class color" } },
	{ type = "toggle", disabled = E:BlizzardNeeds(ELEMENT, "improve"), key = "eyeButton", label = "Eye button (show only the model)",
		desc = "A small eye in the top-left corner fades the slots and stats so only the model shows. Click again, or close the window, to bring them back." },
	{ type = "select", key = "tabStyle", label = "Window tab style", reload = true,
		desc = "Flat boxes, or flat tabs with an accent underline on the open one.",
		values = { box = "Flat boxes", underline = "Accent underline" } },
	{ type = "toggle", disabled = E:BlizzardNeeds(ELEMENT, "improve"), key = "avgItemLevel", label = "Average item level", desc = "Shows the average item level the game reports for your gear." },
	{ type = "select", key = "avgPosition", label = "Average item level position", dependsOn = "avgItemLevel",
		desc = "Large: a big accent number, equipped / best when they differ; above the stats where the window has a fixed stats pane, under the level line otherwise.",
		values = { TITLE = "Title bar, left", BELOW = "Under the level line", STATS = "Large, above the stats" } },
	{ type = "range", key = "avgSize", label = "Large item level text size", desc = "Size of the large average item level number.", min = 14, max = 32, step = 1,
		dependsOn = "avgItemLevel", hidden = function() return M.db.avgPosition ~= "STATS" end },
	{ type = "toggle", key = "itemScore", label = "Item score", dependsOn = "avgItemLevel",
		desc = "The sum of the item levels of your equipped gear (shirt and tabard left out), shown next to the average item level." },
	{ type = "header", label = "Model background" },
	{ type = "select", key = "modelBackground", label = "Background behind the model", desc = "What shows behind your character model.",
		values = { blizzard = "Blizzard class background", dark = "Plain dark", gradient = "Gradient", stone = "Dark stone (classic)" } },
	{ type = "select", key = "gradientColor", label = "Gradient color", desc = "Tint of the gradient background.", hidden = function() return M.db.modelBackground ~= "gradient" end,
		values = { accent = "Accent color", class = "Class color" } },
	{ type = "header", label = "Item slots" },
	{ type = "select", key = "slotBorder", label = "Slot border", desc = "Color of the border around each equipped item.",
		values = { quality = "Item quality", accent = "Accent color", none = "Plain black" } },
	{ type = "range", key = "slotBorderSize", label = "Slot border thickness", desc = "Border width in pixels.", min = 1, max = 3, step = 1 },
	{ type = "toggle", disabled = E:BlizzardNeeds(ELEMENT, "improve"), key = "itemLevel", label = "Item level on each slot", desc = "The item level of each equipped item." },
	{ type = "range", key = "ilvlSize", label = "Item level text size", dependsOn = "itemLevel", desc = "Text size of the slot item levels.", min = 8, max = 20, step = 1 },
	{ type = "select", key = "ilvlPosition", label = "Item level position", dependsOn = "itemLevel",
		desc = "Beside the slot puts the number next to the icon, on the side facing the model.",
		values = { TOP = "Top", BOTTOM = "Bottom", CENTER = "Center", SIDE = "Beside the slot" } },
	{ type = "select", key = "ilvlColor", label = "Item level color", dependsOn = "itemLevel", desc = "Color of the slot item levels.",
		values = { quality = "Item quality", white = "White", accent = "Accent color" } },
	{ type = "toggle", disabled = E:BlizzardNeeds(ELEMENT, "improve"), key = "socketInfo", label = "Gem and enchant marks",
		desc = "Small icons under the item level: the enchant, each socketed gem, and a gray square per empty socket. Read from the item link." },
	{ type = "select", disabled = E:BlizzardNeeds(ELEMENT, "improve"), key = "durability", label = "Durability", desc = "Shows worn gear as a percentage or a red tint.",
		values = { off = "Off", text = "Percent text", tint = "Red tint when low" } }, -- no-L: select values are translated by Core/Config.lua
	{ type = "execute", label = "Durability colors", keywords = "durability low threshold",
		desc = "When durability turns red is set once for every module, on the General page (Clock and durability).",
		func = function() E:ToggleConfig("general") end },
	{ type = "toggle", disabled = E:BlizzardNeeds(ELEMENT, "improve"), key = "enchantHint", label = "Mark gear without an enchant",
		desc = "A small red mark on enchantable slots whose item carries no enchant, and a line in the tooltip. Read from the item link." },
	{ type = "header", label = "Stats and headers" },
	{ type = "select", key = "statsLayout", label = "Stats layout",
		desc = "Modern: centered section titles between thin lines, labels left and values right. The values are Blizzard's own.",
		values = { classic = "Header bars", modern = "Centered titles, thin lines" } },
	{ type = "toggle", key = "collapsibleStats", label = "Fold stat sections",
		disabled = function() if M.db.statsLayout ~= "modern" then return L["Pick the centered titles stats layout first."] end end,
		desc = "Modern layout: click a section title to fold or unfold it. Remembered per profile." },
	{ type = "toggle", key = "statRowBg", label = "Shaded stat rows", desc = "Keeps Blizzard's alternating row shading in the stats." },
	{ less = true, type = "select", key = "headerColorMode", label = "Header color", desc = "Color of section titles in the stats and side panels.",
		values = { accent = "Accent color", gold = "Blizzard gold", class = "Class color", custom = "Custom color" } },
	{ less = true, type = "color", key = "headerColor", label = "Custom header color", desc = "Color of the section titles.", hidden = function() return M.db.headerColorMode ~= "custom" end },
	{ type = "range", key = "statsFontSize", label = "Stats text size", desc = "Text size in the stats pane.", min = 9, max = 18, step = 1 },
	{ type = "header", label = "Gear sets" },
	{ type = "description", label = "Uses the game's equipment sets from the character window. Every swap happens out of combat." },
	{ type = "toggle", disabled = E:BlizzardNeeds(ELEMENT, "improve"), key = "gearBar", label = "Set buttons on the character window", desc = "One button per set; click to equip it. The open set has an accent border, a set with missing items a red one." },
	{ type = "select", key = "gearBarPosition", label = "Set buttons position", dependsOn = "gearBar", desc = "Where the set buttons sit.",
		values = { TOP = "Left of the level line", BELOW = "Under the window" } },
	{ type = "range", key = "gearBarSize", label = "Set button size", dependsOn = "gearBar", desc = "Size of each set button.", min = 14, max = 32, step = 1 },
	{ type = "toggle", acts = true, key = "gearAfterCombat", label = "Equip after combat",
		desc = "Acts for you when turned on: a set you click in combat (set buttons or the Gear block) goes on once combat ends, or once you are alive again. Only your last click counts; click that set again, or the set you wear, to keep your gear. Off by default." },
	{ type = "toggle", disabled = E:BlizzardNeeds(ELEMENT, "improve"), key = "slotFlyout", label = "Trinket and ring flyout",
		desc = "Hover a trinket or ring slot to see the matching items in your bags, and click one to wear it there. Out of combat only. Blizzard's own Alt flyout keeps working." },
	{ type = "header", label = "Side panels" },
	{ type = "description", label = "Each panel group gets the EldoUI panel, flat bars and accent headers." },
	{ type = "toggle", reload = "off", key = "sideTabs", label = "Skin the window tabs", desc = "The tabs along the window in the chosen tab style." },
	{ type = "toggle", reload = "off", key = "panelReputation", label = "Reputation", desc = "Skin the reputation panel." },
	{ type = "toggle", reload = "off", key = "panelSkills", label = "Skills", desc = "Skin the skills panel." },
	{ type = "toggle", reload = "off", key = "panelPvP", label = "Player vs. Player", desc = "Skin the PvP panel." },
	{ type = "toggle", reload = "off", key = "panelCurrency", label = "Currency", desc = "Skin the currency panel." },
	{ type = "toggle", reload = "off", key = "panelStatistics", label = "Statistics", desc = "Skin the statistics panel." },
	{ type = "toggle", reload = "off", key = "panelOther", label = "Other panels in the window", desc = "Skin any other panel the window shows." },
}

---------------------------------------------------------------------------
-- Style presets
---------------------------------------------------------------------------
-- Keys the newer looks added; the older presets set them back to the
-- original look so switching between presets is clean.
local CLASSIC_EXTRAS = { header = "blizzard", statsLayout = "classic", slotBorderSize = 1, socketInfo = false, statRowBg = true }

local function Preset(settings)
	for key, value in pairs(CLASSIC_EXTRAS) do
		if settings[key] == nil then settings[key] = value end
	end
	return settings
end

E:RegisterStyles("Character", {
	{ key = "Modern", title = "Modern", desc = "Flat dark window: name and title header, item level beside each slot with gem and enchant marks, a large accent item level, foldable stat sections and underlined tabs (tabs after a reload).",
		settings = { skin = true, transparent = false, modelBackground = "dark", slotBorder = "quality", slotBorderSize = 2,
			itemLevel = true, ilvlSize = 12, ilvlPosition = "SIDE", ilvlColor = "quality", socketInfo = true,
			durability = "off", enchantHint = false, header = "eldo", headerColorMode = "accent",
			statsLayout = "modern", collapsibleStats = true, statRowBg = false, statsFontSize = 13,
			avgItemLevel = true, avgPosition = "STATS", avgSize = 22, sideTabs = true, tabStyle = "underline", eyeButton = true } },
	{ key = "EldoUI", title = "EldoUI", desc = "Quality borders, item level at the bottom, dark model background.",
		settings = Preset({ skin = true, transparent = false, modelBackground = "dark", slotBorder = "quality",
			itemLevel = true, ilvlSize = 12, ilvlPosition = "BOTTOM", ilvlColor = "quality",
			durability = "text", enchantHint = false, headerColorMode = "accent",
			statsFontSize = 13, avgItemLevel = true, avgPosition = "TITLE", sideTabs = true }) },
	{ key = "Preset", title = "Preset colors", desc = "Accent borders and headers with an accent gradient behind the model.",
		settings = Preset({ skin = true, transparent = false, modelBackground = "gradient", gradientColor = "accent",
			slotBorder = "accent", itemLevel = true, ilvlSize = 12, ilvlPosition = "BOTTOM", ilvlColor = "accent",
			durability = "tint", enchantHint = false, headerColorMode = "accent",
			statsFontSize = 13, avgItemLevel = true, avgPosition = "TITLE", sideTabs = true }) },
	{ key = "Clean", title = "Clean", desc = "Minimal: no item level, no durability, see-through dark panel.",
		settings = Preset({ skin = true, transparent = true, modelBackground = "dark", slotBorder = "none",
			itemLevel = false, durability = "off", enchantHint = false, headerColorMode = "accent",
			statsFontSize = 12, avgItemLevel = false, sideTabs = true }) },
	{ key = "Raider", title = "Raider", desc = "Big item levels, red tint on worn gear, missing-enchant marks.",
		settings = Preset({ skin = true, transparent = false, modelBackground = "gradient", gradientColor = "class",
			slotBorder = "quality", itemLevel = true, ilvlSize = 16, ilvlPosition = "CENTER", ilvlColor = "quality",
			durability = "tint", enchantHint = true, headerColorMode = "class",
			statsFontSize = 14, avgItemLevel = true, avgPosition = "BELOW", sideTabs = true }) },
	{ key = "Blizzard", title = "Blizzard", desc = "Blizzard's class background with quality borders only.",
		settings = Preset({ skin = true, transparent = false, modelBackground = "blizzard", slotBorder = "quality",
			itemLevel = false, durability = "off", enchantHint = false, headerColorMode = "gold",
			statsFontSize = 13, avgItemLevel = true, avgPosition = "TITLE", sideTabs = true }) },
	{ key = "Classic", title = "Classic", desc = "Gold headers on dark stone, item level at the top.",
		settings = Preset({ skin = true, transparent = false, modelBackground = "stone", slotBorder = "quality",
			itemLevel = true, ilvlSize = 11, ilvlPosition = "TOP", ilvlColor = "white",
			durability = "text", enchantHint = false, headerColorMode = "gold",
			statsFontSize = 13, avgItemLevel = true, avgPosition = "BELOW", sideTabs = true }) },
})
