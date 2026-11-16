-- EldoUI Window Skins: Blizzard's game windows in the EldoUI look.
--
-- One module for the windows no other module owns:
--   Spellbook and talents   PlayerSpellsFrame       (Blizzard_PlayerSpells)
--   Professions             ProfessionsFrame        (Blizzard_Professions)
--   Trainer                 ClassTrainerFrame       (Blizzard_TrainerUI)
--   Legacy and achievements LegacySystemFrame, AchievementFrame
--   Collections             CollectionsJournal      (Blizzard_Collections)
--   Item socketing          ItemSocketingFrame, ItemInteractionFrame
--   Dressing room           DressUpFrame, SideDressUpFrame
--   Inspect                 InspectFrame            (Blizzard_InspectUI)
--
-- Every window belongs to one Blizzard element (Core/Blizzard.lua). Nothing
-- here touches a window until the player turns its element on; then the
-- element's switches decide what EldoUI may do:
--   skin     art-style panel, flat tabs, buttons, boxes, bars and rows
--   move     drag and scale it (Core/WindowMover.lua does that for every window)
--   improve  small extras: spell IDs, reagent counts, trainer cost total,
--            item levels in the inspect window, dressing room buttons
-- The window-level helpers (E.WindowKit) are shared with Modules/Character.lua
-- and open to plugins.
--
-- Presentation only. Blizzard art goes to alpha 0 through Core/Skin.lua,
-- Blizzard code is followed with hooksecurefunc / HookScript, and per-frame
-- state lives in local weak tables. Windows are positioned after Blizzard's
-- own panel manager has placed them, never instead of it. Nothing here
-- clicks, buys, trains or equips anything for the player.
-- Written from scratch for EldoUI; no code or media from other addons.
local _, E = ...
local L = E.L

local M = E:NewModule("Skins", {
	title = "Window Skins",
	category = "Interface",
	desc = "Spellbook, talents, professions, trainer, Legacy, collections, socketing, dressing room, and inspect windows in the EldoUI look.",
	conflicts = { "ElvUI", "Aurora", "RealUI" },
	defaults = {
		transparent = false,     -- see-through window panels
		titleSize = 16,          -- window title text size
		windows = {
			spells = { skin = true, pageArt = false, spellIDs = false },
			professions = { skin = true, reagentCounts = true, reagentAlts = true,
				recipeSkill = true, recipePrices = true, recipeCounts = true },
			trainer = { skin = true, costTotal = true, serviceList = true, showKnown = false, hideIgnored = true },
			legacy = { skin = true },
			achievements = { skin = true },
			collections = { skin = true, summary = true },
			socketing = { skin = true },
			interaction = { skin = true },
			dressup = { skin = true, buttons = true, resizable = true, size = false, slotStrip = true, sheathe = true },
			inspect = { skin = true, slots = true, itemLevel = true, avgItemLevel = true,
				ilvlPosition = "BOTTOM", ilvlSize = 12, marks = true, modelBackground = "dark" },
		},
	},
})

---------------------------------------------------------------------------
-- Shared state (weak keys; nothing is written into Blizzard frames)
---------------------------------------------------------------------------
local faded = setmetatable({}, { __mode = "k" })     -- region -> true while we hold it at alpha 0
local walked = setmetatable({}, { __mode = "k" })    -- frame -> last walk time
local sideTabs = setmetatable({}, { __mode = "k" })  -- side tab -> backdrop
local items = setmetatable({}, { __mode = "k" })     -- item button -> { bd, quality fn }
local bars = setmetatable({}, { __mode = "k" })      -- status bar -> backdrop
local tabSystems = setmetatable({}, { __mode = "k" })
local own = setmetatable({}, { __mode = "k" })       -- frames EldoUI made inside Blizzard windows

local function Usable(frame)
	return type(frame) == "table" and type(frame.GetObjectType) == "function"
		and not E.FrameCheck(frame, "IsForbidden")
end

local function Try(fn, ...)
	if type(fn) ~= "function" then return end
	local ok, err = pcall(fn, ...)
	if not ok then geterrorhandler()(err) end
	return ok
end

local function Accent()
	local c = E.media.accentColor
	return c[1], c[2], c[3]
end

local function IsTexture(region)
	return type(region) == "table" and region.IsObjectType and region:IsObjectType("Texture")
end

-- Fade Blizzard art (or bring back what we faded).
local function Fade(on, ...)
	for i = 1, select("#", ...) do
		local region = select(i, ...)
		if type(region) == "table" and region.SetAlpha and not E.FrameCheck(region, "IsForbidden") then
			if on then
				E:SkinCapture(region)
				region:SetAlpha(0)
				faded[region] = true
			elseif faded[region] then
				region:SetAlpha(1)
				faded[region] = nil
			end
		end
	end
end

-- A frame of ours behind `frame` with the flat EldoUI box.
local function Box(frame, transparent, inset)
	E:SkinCapture(frame)
	local bd = CreateFrame("Frame", nil, frame)
	inset = inset or 0
	bd:SetPoint("TOPLEFT", -inset, inset)
	bd:SetPoint("BOTTOMRIGHT", inset, -inset)
	bd:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))
	E:SetTemplate(bd, transparent)
	own[bd] = true
	return bd
end

local function Label(frame)
	local name = frame.GetName and frame:GetName() or ""
	local key = frame.GetParentKey and frame:GetParentKey() or ""
	return name .. "|" .. key
end

local Global = E.SkinGlobal

---------------------------------------------------------------------------
-- E.WindowKit: window-level helpers on top of Core/Skin.lua
---------------------------------------------------------------------------
local Kit = E.WindowKit or {} -- part one (own windows) is in Core/Skin.lua
E.WindowKit = Kit
Kit.Usable = Usable
Kit.Fade = Fade
Kit.Box = Box

-- The whole window: art-style panel, accent line, close button, title.
-- opts: transparent, titleSize, plus anything E:SkinPanel takes.
function Kit.SkinWindow(frame, opts)
	if not Usable(frame) then return end
	opts = opts or {}
	local bd = E:SkinPanel(frame, opts)
	-- ButtonFrameTemplate's bottom strip and the old named corner pieces.
	Fade(true, frame.ButtonBar, Global(frame, "BtnCornerLeft"), Global(frame, "BtnCornerRight"),
		Global(frame, "ButtonBottomBorder"), frame.TopTileStreaks)
	local title = (frame.TitleContainer and frame.TitleContainer.TitleText) or frame.TitleText or Global(frame, "TitleText")
	if title and title.SetFont then
		E:SetFont(title, opts.titleSize or E.tokens.size.dialogTitle)
		title:SetTextColor(1, 1, 1)
	end
	return bd
end

-- Panel buttons (UIPanelButtonTemplate family): three art pieces and a label.
local function IsPanelButton(button)
	if not button:IsObjectType("Button") or button:IsObjectType("CheckButton") then return false end
	local left = button.Left or Global(button, "Left")
	local right = button.Right or Global(button, "Right")
	local middle = button.Middle or Global(button, "Middle")
	return IsTexture(left) and IsTexture(right) and IsTexture(middle)
		and button.GetFontString and button:GetFontString() ~= nil
end

local function IsScrollBar(frame)
	if frame:IsObjectType("Slider") then return Label(frame):find("ScrollBar") ~= nil end
	return (frame.Track ~= nil or frame.GetTrack ~= nil) and (frame.Back ~= nil or frame.Forward ~= nil)
end

local function IsDropdown(frame)
	if frame.IsObjectType and frame:IsObjectType("DropdownButton") then return not IsPanelButton(frame) end
	return (frame.Button or Global(frame, "Button")) ~= nil and (frame.Left or Global(frame, "Left")) ~= nil
		and frame:IsObjectType("Frame") and not frame:IsObjectType("Button")
end

local function IsLabeledCheck(frame)
	if not frame:IsObjectType("CheckButton") or not frame.GetCheckedTexture then return false end
	local width, height = frame:GetSize()
	if (width or 0) > 34 or (height or 0) > 34 then return false end
	if Label(frame):find("Tab") then return false end
	local text = frame.Text or frame.text or Global(frame, "Text")
	return type(text) == "table" and text.IsObjectType ~= nil and text:IsObjectType("FontString")
end

local function IsInset(frame)
	local label = Label(frame)
	return label:find("Inset") ~= nil and (frame.NineSlice ~= nil or frame.Bg ~= nil or Global(frame, "Bg") ~= nil)
end

-- Flat status bar: the fill gets the EldoUI texture (color kept), the
-- frame art goes, a 1 px box sits behind.
function Kit.SkinStatusBar(bar)
	if not Usable(bar) or not bar:IsObjectType("StatusBar") then return end
	if E:SkinRecordIsOff(bar) then return bars[bar] end
	local fill = bar:GetStatusBarTexture()
	local atlas, readable
	if fill then
		atlas, readable = E.FrameAtlas(fill)
		if not readable then return bars[bar] end
	end
	if not bars[bar] then
		E:SkinCapture(bar)
		for _, region in ipairs({ bar:GetRegions() }) do
			if region:IsObjectType("Texture") and region ~= fill and region:GetDrawLayer() ~= "HIGHLIGHT" then
				Fade(true, region)
			elseif region:IsObjectType("FontString") then
				local _, size = region:GetFont()
				E:SetFont(region, size and math.floor(size + 0.5) or 12)
			end
		end
		for _, key in ipairs({ "Left", "Right", "Middle", "Background", "BorderLeft", "BorderRight", "BorderMid", "Border" }) do
			if IsTexture(bar[key]) and bar[key] ~= fill then Fade(true, bar[key]) end
			local named = Global(bar, key)
			if IsTexture(named) and named ~= fill then Fade(true, named) end
		end
		bars[bar] = Box(bar, false, E.pixel)
		bars[bar]:SetBackdropColor(0, 0, 0, 0.5)
		E:SetStyleEdge(bars[bar]) -- thin bronze line under the WoW Forever art style
	end
	fill = bar:GetStatusBarTexture()
	if fill then atlas, readable = E.FrameAtlas(fill) end
	if fill and readable and (not atlas or atlas == "") then
		local r, g, b, a = bar:GetStatusBarColor()
		bar:SetStatusBarTexture(E.media.statusbar)
		if r then bar:SetStatusBarColor(r, g, b, a) end
	end
	return bars[bar]
end

-- Side tabs (LargeSideTabButtonTemplate): the round art goes, the icon
-- sits in a 1 px box whose border turns accent on the open tab.
local function UpdateSideTab(tab)
	local bd = sideTabs[tab]
	if not bd then return end
	local selected = tab.SelectedTexture and tab.SelectedTexture:IsShown()
	if tab.GetChecked then
		local ok, checked = pcall(tab.GetChecked, tab)
		if ok and checked ~= nil and not tab.SelectedTexture then selected = checked end
	end
	if selected then
		local r, g, b = Accent()
		bd:SetBackdropBorderColor(r, g, b, 1)
	else
		bd:SetBackdropBorderColor(unpack(E.media.borderColor))
	end
end

function Kit.SkinSideTabs(list)
	if Usable(list) then list = { list } end
	if type(list) ~= "table" then return end
	for _, tab in ipairs(list) do
		if Usable(tab) and not sideTabs[tab] then
			E:SkinCapture(tab)
			Fade(true, tab.Background, tab.SelectedTexture, tab.TabGlow, tab.HighlightTexture, tab.TabBg, tab.Mask)
			for _, region in ipairs({ tab:GetRegions() }) do
				if region:IsObjectType("Texture") and region ~= tab.Icon and region:GetDrawLayer() ~= "HIGHLIGHT" then Fade(true, region) end
			end
			local icon = tab.Icon
			local bd = CreateFrame("Frame", nil, tab)
			if icon then
				bd:SetPoint("TOPLEFT", icon, "TOPLEFT", -E.pixel, E.pixel)
				bd:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", E.pixel, -E.pixel)
			else
				bd:SetAllPoints()
			end
			bd:SetFrameLevel(math.max(tab:GetFrameLevel() - 1, 0))
			E:SetTemplate(bd)
			own[bd] = true
			local hover = tab:CreateTexture(nil, "HIGHLIGHT")
			hover:SetAllPoints(bd)
			hover:SetColorTexture(1, 1, 1, E.tokens.hover.control)
			sideTabs[tab] = bd
			if type(tab.SetChecked) == "function" then
				hooksecurefunc(tab, "SetChecked", UpdateSideTab)
			end
			tab:HookScript("OnShow", UpdateSideTab)
			UpdateSideTab(tab)
		end
	end
end

function Kit.UpdateSideTabs()
	for tab in pairs(sideTabs) do UpdateSideTab(tab) end
end

-- TabSystemTemplate tabs (spellbook, talents, professions): the shared flat
-- tabs, and tabs the system adds later get the same look.
local function TabFont(tab)
	if E:SkinRecordIsOff(tab) then return end
	local text = tab.Text or (tab.GetFontString and tab:GetFontString())
	if text and text.SetFont then E:SetFont(text, E.tokens.size.body) end
end

function Kit.SkinTabSystem(system)
	if not Usable(system) then return end
	local function Skin()
		local list = {}
		for _, tab in ipairs(system.tabs or {}) do list[#list + 1] = tab end
		E:SkinTabs(list, { isSelected = function(tab) return tab.isSelected end, size = 13 })
		for _, tab in ipairs(list) do
			if not tabSystems[tab] and type(tab.SetTabSelected) == "function" then
				tabSystems[tab] = true
				-- Blizzard swaps the font object per state; keep ours.
				hooksecurefunc(tab, "SetTabSelected", function(self)
					TabFont(self)
					E:UpdateTabs()
				end)
			end
			TabFont(tab)
		end
	end
	if not tabSystems[system] then
		tabSystems[system] = true
		-- Tabs added later join the record this system was skinned in.
		local key = E:SkinRecordKey()
		if type(system.AddTab) == "function" then
			hooksecurefunc(system, "AddTab", function()
				if key then E:SkinRecord(key, system, Skin) else Skin() end
			end)
		end
	end
	Skin()
end

-- Item buttons: the slot art goes, the icon is trimmed and sits in a box
-- whose border shows the item quality. opts.quality(button) returns the
-- quality (or nil for none); opts.size is the border thickness.
function Kit.SkinItemButton(button, opts)
	if not Usable(button) then return end
	local parts = items[button]
	if parts then return parts end
	opts = opts or {}
	E:SkinCapture(button)
	local icon = button.icon or button.Icon or Global(button, "IconTexture")
	local keep = {}
	if icon then keep[icon] = true end
	for _, key in ipairs({ "IconOverlay", "IconOverlay2", "SearchOverlay", "ItemContextOverlay", "Count", "Stock", "searchOverlay" }) do
		if button[key] then keep[button[key]] = true end
	end
	local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
	local pushed = button.GetPushedTexture and button:GetPushedTexture()
	for _, region in ipairs({ button:GetRegions() }) do
		if region:IsObjectType("Texture") and not keep[region] and region ~= highlight and region ~= pushed then Fade(true, region) end
	end
	Fade(true, button.IconBorder, button.NormalTexture, Global(button, "NormalTexture"), button.BorderFrame)
	if button.GetNormalTexture then Fade(true, button:GetNormalTexture()) end
	if icon then
		E:TrimIcon(icon)
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
		icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	end
	if highlight then
		E:SkinColorTexture(highlight, 1, 1, 1, 0.15)
		highlight:SetAllPoints(icon or button)
	end
	if pushed then
		E:SkinColorTexture(pushed, 1, 1, 1, 0.25)
		pushed:SetAllPoints(icon or button)
	end
	parts = { bd = Box(button), quality = opts.quality }
	parts.bd:SetBackdropColor(0, 0, 0, 0.5)
	items[button] = parts
	Kit.UpdateItemButton(button)
	return parts
end

function Kit.UpdateItemButton(button, quality)
	local parts = items[button]
	if not parts then return end
	if quality == nil and parts.quality then
		local ok, value = pcall(parts.quality, button)
		if ok then quality = value end
	end
	if type(quality) == "number" and quality >= (Enum.ItemQuality and Enum.ItemQuality.Uncommon or 2) then
		local r, g, b = C_Item.GetItemQualityColor(quality)
		parts.bd:SetBackdropBorderColor(r, g, b, 1)
	else
		parts.bd:SetBackdropBorderColor(unpack(E.media.borderColor))
	end
end

-- Quality of an item link, nil while the item is not cached.
function Kit.LinkQuality(link)
	if type(link) ~= "string" then return end
	if C_Item.GetItemQualityByID then
		local ok, quality = pcall(C_Item.GetItemQualityByID, link)
		if ok then return quality end
	end
end

-- Walk a window and give every standard widget the EldoUI look: panel
-- buttons, close buttons, scroll bars, search and input boxes, dropdowns,
-- labeled check boxes, status bars and insets. Item buttons, models and
-- content art are left alone. opts: depth (default 6), skip(frame) -> true
-- to leave a branch out, bars (default true).
function Kit.SkinTree(root, opts)
	if not Usable(root) then return end
	opts = opts or {}
	local now = GetTime()
	if walked[root] and now - walked[root] < 0.5 then return end
	walked[root] = now
	local function Visit(frame, depth)
		if not Usable(frame) or own[frame] then return end
		if opts.skip and opts.skip(frame) then return end
		local kind = frame:GetObjectType()
		if kind == "ModelScene" or kind == "PlayerModel" or kind == "DressUpModel" or kind == "Model" or kind == "Cooldown" then return end
		if frame ~= root then
			local label = Label(frame)
			if kind == "Button" and label:find("CloseButton") then
				E:SkinCloseButton(frame)
			elseif IsScrollBar(frame) then
				E:SkinScrollBar(frame)
				return
			elseif kind == "EditBox" then
				E:SkinEditBox(frame)
			elseif IsDropdown(frame) then
				E:SkinDropdown(frame)
			elseif (kind == "Button" or kind == "DropdownButton") and IsPanelButton(frame) then
				E:SkinButton(frame)
			elseif IsLabeledCheck(frame) then
				E:SkinCheckBox(frame)
			elseif kind == "StatusBar" and opts.bars ~= false then
				Kit.SkinStatusBar(frame)
			elseif IsInset(frame) then
				E:SkinInset(frame)
			end
		end
		if depth <= 0 then return end
		for _, child in ipairs({ frame:GetChildren() }) do Visit(child, depth - 1) end
	end
	Visit(root, opts.depth or 6)
end

---------------------------------------------------------------------------
-- Moving and scaling: Core/WindowMover.lua does it for every Blizzard
-- window (Data/MovableWindows.lua lists these). Kit.MakeMovable stays for
-- plugins as a thin front end onto E:RegisterWindow:
--   Kit.MakeMovable(frame, {
--       key = "MyWindow",                       -- save key (default: the frame name)
--       title = "My window",                    -- name in the Windows options
--       element = "some-element",               -- Blizzard UI switch (optional)
--       allowed = function() return true end,   -- extra check (optional)
--       left = 58, right = 50, height = 22,     -- title strip (optional)
--   })
---------------------------------------------------------------------------
function Kit.MakeMovable(frame, spec)
	if not Usable(frame) or type(spec) ~= "table" then return end
	local name = frame.GetName and frame:GetName()
	local key = spec.key or name
	if not key then return end
	return E:RegisterWindow({
		key = key, frame = frame, title = spec.title or name or key, element = spec.element, allowed = spec.allowed,
		drag = (spec.left or spec.right or spec.height) and { left = spec.left, right = spec.right, height = spec.height } or nil,
	})
end

function Kit.UpdateMovable(frame) E:WindowMoverApply(frame) end
Kit.Reapply = Kit.UpdateMovable
function Kit.ReapplyAll() E:WindowMoverApply() end
-- The window mover gives a window back to Blizzard when its switch goes off.
function Kit.Release(frame) E:WindowMoverApply(frame) end

---------------------------------------------------------------------------
-- Window definitions
---------------------------------------------------------------------------
local WINDOWS = {}

local function Window(def)
	WINDOWS[#WINDOWS + 1] = def
	return def
end

local function WDB(key) return M.db.windows[key] end

local function Text(parent, size, justify)
	local fs = E:CreateText(parent, size, justify)
	own[fs] = true
	return fs
end

---------------------------------------------------------------------------
-- Spellbook and talents
---------------------------------------------------------------------------
local function SpellsPageArt(frame, db)
	local book = frame.SpellBookFrame
	local fade = not db.pageArt
	if Usable(book) then
		Fade(fade, book.TopBar, book.BookBGHalved, book.BookBGLeft, book.BookBGRight, book.Bookmark, book.BookCornerFlipbook)
	end
	local talents = frame.TalentsFrame
	if Usable(talents) then
		Fade(fade, talents.Background, talents.BackgroundBorder, talents.DividerHorizontalLeft, talents.DividerHorizontalRight,
			talents.DividerVerticalLeft, talents.DividerVerticalRight, talents.BottomBar)
	end
end

-- Spell names, ranks and category headers are drawn in Blizzard's dark
-- book ink, made for the parchment pages. With the page art faded they
-- sit on the dark EldoUI panel, so they take the theme's text colors:
-- names body, ranks and "Available at level" secondary, headers the
-- accent. Blizzard's own alpha for unlearned spells stays on top. The ink
-- comes back when the page art is kept or the skin goes off.
local spellInk = setmetatable({}, { __mode = "k" })   -- font string -> Blizzard's color
local spellPagesHooked = setmetatable({}, { __mode = "k" })

local function SpellText(fs, kind, on)
	if type(fs) ~= "table" or type(fs.SetTextColor) ~= "function" then return end
	if on then
		if not spellInk[fs] then spellInk[fs] = { fs:GetTextColor() } end
		fs:SetTextColor(E:TokenColor(kind))
	elseif spellInk[fs] then
		fs:SetTextColor(unpack(spellInk[fs]))
		spellInk[fs] = nil
	end
end

local function SpellPageText(book, on)
	local paged = Usable(book) and book.PagedSpellsFrame
	if not Usable(paged) then return end
	if type(paged.EnumerateFrames) == "function" then
		local ok, iterator, state, start = pcall(paged.EnumerateFrames, paged)
		if ok and iterator then
			for _, frame in iterator, state, start do
				if type(frame) == "table" then
					if frame.SubName or frame.TextContainer then
						SpellText(frame.Name, "body", on)
						SpellText(frame.SubName, "secondary", on)
						SpellText(frame.RequiredLevel, "secondary", on)
					elseif frame.Text then
						SpellText(frame.Text, "accent", on)
					end
				end
			end
		end
	end
	local paging = paged.PagingControls
	if type(paging) == "table" then SpellText(paging.PageText, "secondary", on) end
end

local function SpellTextOn()
	return M.active and E:BlizzardAllowed("player-spells", "skin") and WDB("spells").skin and not WDB("spells").pageArt
end

-- Each page Blizzard fills (paging, category tabs, search) gets the colors.
local function HookSpellPages(book)
	local paged = Usable(book) and book.PagedSpellsFrame
	if not Usable(paged) or spellPagesHooked[paged] or type(paged.DisplayViewsForCurrentPage) ~= "function" then return end
	spellPagesHooked[paged] = true
	hooksecurefunc(paged, "DisplayViewsForCurrentPage", function()
		if SpellTextOn() then Try(SpellPageText, book, true) end
	end)
end

M.SpellPageText, M.HookSpellPages = SpellPageText, HookSpellPages

local function InsideFrame(owner, root)
	local depth = 0
	while owner and depth < 25 do
		if owner == root then return true end
		owner = owner.GetParent and owner:GetParent()
		depth = depth + 1
	end
	return false
end

-- Spell ID line on spell tooltips shown from the spellbook or talents.
-- The Tooltip module's own Spell ID line takes over when it shows one.
local spellTooltipHooked = false
local function HookSpellIDs()
	if spellTooltipHooked then return end
	if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType and Enum.TooltipDataType.Spell) then return end
	spellTooltipHooked = true
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, data)
		if not M.active or not E:BlizzardAllowed("player-spells", "improve") or not WDB("spells").spellIDs then return end
		if not tooltip or E.FrameCheck(tooltip, "IsForbidden") or tooltip ~= GameTooltip then return end
		local frame = _G.PlayerSpellsFrame
		if not Usable(frame) or not frame:IsShown() then return end
		local owner = tooltip:GetOwner()
		if not InsideFrame(owner, frame) then return end
		local id = data and data.id
		if (issecretvalue and issecretvalue(id)) or type(id) ~= "number" then return end
		local tip = E:GetModule("Tooltip")
		if tip and tip.active and tip.db and (tip.db.ids == "always" or (tip.db.ids == "shift" and IsShiftKeyDown())) then return end
		E.UIKit.TipPair(tooltip, L["Spell ID"], tostring(id))
		tooltip:Show()
	end)
end

-- The Talent Planner owns this element: the look joins its hook list, so
-- it goes on after the planner's overlay and comes off before it.
Window({
	key = "spells", element = "player-spells", addon = "Blizzard_PlayerSpells", frame = "PlayerSpellsFrame",
	title = "Spellbook and talents",
	tree = { skip = function(frame)
		local key = frame.GetParentKey and frame:GetParentKey()
		return key == "ButtonsParent" or key == "PagedSpellsFrame" or key == "HeroTalentsContainer"
	end },
	skin = function(frame, db)
		Kit.SkinTabSystem(frame.TabSystem)
		local book = frame.SpellBookFrame
		if Usable(book) then
			Kit.SkinTabSystem(book.CategoryTabSystem)
			E:SkinEditBox(book.SearchBox)
			E:SkinDropdown(book.SettingsDropdown)
		end
		local talents = frame.TalentsFrame
		if Usable(talents) then
			Kit.SkinTabSystem(talents.TabSystem)
			E:SkinEditBox(talents.SearchBox)
			E:SkinButton(talents.ApplyButton)
		end
		SpellsPageArt(frame, db)
		HookSpellPages(book)
	end,
	refresh = function(frame, db, skinned)
		if skinned then SpellsPageArt(frame, db) end
		SpellPageText(frame.SpellBookFrame, skinned and SpellTextOn())
	end,
	improve = function(_, db, on)
		if on and db.spellIDs then HookSpellIDs() end
	end,
})

---------------------------------------------------------------------------
-- Professions: skin, and how many of each reagent wait in the bank
-- and on your other characters (from the Bags module's inventory list).
---------------------------------------------------------------------------
local reagentText = setmetatable({}, { __mode = "k" })  -- reagent slot -> font string

local function AltCount(itemID)
	local bags = E:GetModule("Bags")
	local store = bags and bags.store
	if not store or type(store.Characters) ~= "function" then return 0 end
	local ok, keys = pcall(store.Characters, store, "ALL")
	if not ok or type(keys) ~= "table" then return 0 end
	local total = 0
	for _, key in ipairs(keys) do
		if key ~= E.charKey then
			local char = store:Get(key)
			local entry = char and char.counts and char.counts[itemID]
			if type(entry) == "table" then
				for i = 1, 4 do total = total + (tonumber(entry[i]) or 0) end
			end
		end
	end
	return total
end

local function ReagentItemID(slot)
	if type(slot.GetReagentSlotSchematic) ~= "function" then return end
	local ok, schematic = pcall(slot.GetReagentSlotSchematic, slot)
	if not ok or type(schematic) ~= "table" or type(schematic.reagents) ~= "table" then return end
	local reagent = schematic.reagents[1]
	return reagent and reagent.itemID
end

local function UpdateReagentSlot(slot, show)
	local text = reagentText[slot]
	if not show then
		if text then text:Hide() end
		return
	end
	local itemID = ReagentItemID(slot)
	if not itemID then
		if text then text:Hide() end
		return
	end
	local db = WDB("professions")
	local bags = C_Item.GetItemCount(itemID) or 0
	local withBank = C_Item.GetItemCount(itemID, true, false, true, true) or bags
	local bank = math.max(0, withBank - bags)
	local alts = db.reagentAlts and AltCount(itemID) or 0
	local parts = {}
	if bank > 0 then parts[#parts + 1] = (E:TextHex("secondary") .. "%s|r %d"):format(L["Bank"], bank) end
	if alts > 0 then parts[#parts + 1] = (E:TextHex("secondary") .. "%s|r %d"):format(L["Alts"], alts) end
	if #parts == 0 then
		if text then text:Hide() end
		return
	end
	if not text then
		local anchor = slot.Button or slot
		text = Text(slot, 10, "LEFT")
		text:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -1)
		reagentText[slot] = text
	end
	E:SetFont(text, E.tokens.size.tiny)
	text:SetText(table.concat(parts, "  "))
	text:Show()
end

local function UpdateReagents(form)
	if not Usable(form) or type(form.GetSlots) ~= "function" then return end
	local show = M.active and E:BlizzardAllowed("professions", "improve") and WDB("professions").reagentCounts
	local ok, slots = pcall(form.GetSlots, form)
	if not ok or type(slots) ~= "table" then return end
	for _, slot in ipairs(slots) do Try(UpdateReagentSlot, slot, show) end
	if not show then
		for slot, text in pairs(reagentText) do
			if slot then text:Hide() end
		end
	end
end

-- The selected recipe uses public schematic data and saved prices only.
local recipeSummary = { states = setmetatable({}, { __mode = "k" }) }

do
	local Summary = recipeSummary
	local UI = E.UIKit
	local function PlainTable(value)
		value = E.Plain(value)
		return type(value) == "table" and (not canaccesstable or canaccesstable(value)) and value or nil
	end
	local function Number(value)
		value = E.Plain(value)
		return type(value) == "number" and value >= 0 and value < math.huge and value or nil
	end
	local function Read(fn, ...)
		return E.PlainCall(fn, ...)
	end
	local function Enabled()
		return M.active and E:BlizzardAllowed("professions", "improve")
	end
	local function CountOptions()
		return { includeBank = true, countAlts = WDB("professions").reagentAlts, altScope = "realm", strict = true }
	end
	local function Money(value, complete)
		if value == nil then return "?" end
		local sign = value < 0 and "-" or ""
		local amount = math.floor(math.abs(value) + 0.5)
		return sign .. (GetMoneyString and GetMoneyString(amount, true) or tostring(amount)) .. (complete == false and " +?" or "")
	end
	function Summary.Recipe(form)
		local info = PlainTable(Read(form.GetRecipeInfo, form))
		local schematic = PlainTable(form.recipeSchematic)
		local id = info and Number(info.recipeID)
		if not id or id < 1 or not schematic or Number(schematic.recipeID) ~= id then return end
		local slots = PlainTable(schematic.reagentSlotSchematics)
		if not slots then return end
		local recipe = { id = id, result = Number(schematic.outputItemID), reagents = {}, prices = {}, incomplete = false }
		local low, high = Number(schematic.quantityMin), Number(schematic.quantityMax)
		recipe.count = low and high and low > 0 and high >= low and (low + high) / 2 or nil
		recipe.variable = low ~= high
		for _, raw in ipairs(slots) do
			local slot = PlainTable(raw)
			if not slot then return end
			local required = E.Plain(slot.required)
			if type(required) ~= "boolean" then return end
			if required then
				local reagents = PlainTable(slot.reagents)
				local reagent = reagents and #reagents == 1 and PlainTable(reagents[1])
				local itemID = reagent and Number(reagent.itemID)
				local quantity = Number(slot.quantityRequired)
				if not itemID or itemID < 1 or not quantity or quantity <= 0 then
					recipe.incomplete = true
				else
					recipe.prices[itemID] = (recipe.prices[itemID] or 0) + quantity
				end
			end
		end
		for itemID, quantity in pairs(recipe.prices) do
			recipe.reagents[#recipe.reagents + 1] = { id = itemID, count = quantity }
		end
		table.sort(recipe.reagents, function(a, b) return a.id < b.id end)
		return recipe
	end
	function Summary.Counts(recipe)
		local planner = E.ProfessionPlanner
		if recipe.incomplete or not planner or type(planner.Have) ~= "function" or #recipe.reagents == 0 then return end
		local bags, total = math.huge, math.huge
		for _, reagent in ipairs(recipe.reagents) do
			local held = Number(Read(C_Item and C_Item.GetItemCount, reagent.id))
			local all = Number(Read(planner.Have, planner, reagent.id, CountOptions()))
			bags = bags and held and math.min(bags, math.floor(held / reagent.count)) or nil
			total = total and all and math.min(total, math.floor(all / reagent.count)) or nil
		end
		return bags, total
	end
	function Summary.Lines(recipe)
		local db, lines = WDB("professions"), {}
		if db.recipeSkill then
			local guide = E.LootGuide
			local craft = guide and PlainTable(Read(guide.Craft, guide, recipe.id))
			local info = C_TradeSkillUI and PlainTable(Read(C_TradeSkillUI.GetProfessionInfoByRecipeID, recipe.id))
			local skill = info and Number(info.skillLevel)
			local thresholds
			if craft and guide.SkillBand then thresholds = select(3, guide:SkillBand(craft, skill)) end
			if PlainTable(thresholds) and Number(thresholds.yellow) and Number(thresholds.green) and Number(thresholds.grey) then
				lines[#lines + 1] = L["Skill %s. Estimated steps: orange to %d, yellow to %d, green to %d, then gray."]:format(
					skill and tostring(skill) or "?", thresholds.yellow, thresholds.green, thresholds.grey)
			else lines[#lines + 1] = L["Skill-up steps unavailable."] end
		end
		if db.recipePrices then
			local auction = E.modules.Auction
			local cost, complete
			if auction and type(auction.GetCraftingCost) == "function" then
				cost, complete = auction:GetCraftingCost(recipe.result, { n = 1, r = recipe.prices })
			end
			cost = Number(cost)
			complete = complete and not recipe.incomplete
			local sale = recipe.result and auction and Number(Read(auction.GetPrice, auction, recipe.result))
			local vendor = recipe.result and Number(select(11, E.PlainCallAll(C_Item and C_Item.GetItemInfo, recipe.result)))
			if recipe.count then
				sale, vendor = sale and sale * recipe.count, vendor and vendor * recipe.count
			else sale, vendor = nil, nil end
			lines[#lines + 1] = L["Cost per craft: %s"]:format(Money(cost, complete))
			local proceeds = sale and math.floor(sale * (1 - auction.HouseCut()))
			lines[#lines + 1] = L["Auction value: %s. Profit: %s"]:format(Money(sale), Money(proceeds and cost and complete and proceeds - cost or nil))
			lines[#lines + 1] = L["Vendor value: %s. Profit: %s"]:format(Money(vendor), Money(vendor and cost and complete and vendor - cost or nil))
			if recipe.variable then lines[#lines + 1] = L["Sale values use the average output per craft."] end
		end
		if db.recipeCounts then
			local bags, total = Summary.Counts(recipe)
			local text = db.reagentAlts and L["Crafts from bags: %s. With bank and saved alts: %s."]
				or L["Crafts from bags: %s. With bank: %s."]
			lines[#lines + 1] = text:format(bags or "?", total or "?")
		end
		return lines
	end
	function Summary.Quantity(form)
		local panel = Summary.states[form]
		local value = panel and tonumber(E.Plain(panel.quantity:GetText()))
		return value and value >= 1 and value <= 9999 and value % 1 == 0 and value or nil
	end
	function Summary.Build(form)
		local panel = CreateFrame("Frame", nil, form)
		own[panel] = true
		E:SetTemplate(panel)
		panel.area = UI.ScrollArea(panel)
		panel.area:SetPoint("TOPLEFT", 8, -8)
		panel.area:SetPoint("BOTTOMRIGHT", -8, 40)
		panel.text = Text(panel.area.child, E.tokens.size.small, "LEFT")
		panel.text:SetPoint("TOPLEFT")
		panel.text:SetPoint("TOPRIGHT")
		panel.text:SetWordWrap(true)
		panel.send = UI.Button(panel, { text = L["Send missing to Shopping"], minWidth = 100, onClick = function()
			local db = WDB("professions")
			local recipe = Enabled() and (db.recipeSkill or db.recipePrices or db.recipeCounts) and Summary.Recipe(form)
			local planner = E.ProfessionPlanner
			if not recipe or recipe.incomplete or not planner or type(planner.SendRecipeToShopping) ~= "function" then return end
			local ok, text = planner:SendRecipeToShopping(recipe, Summary.Quantity(form), CountOptions())
			UI.Toast(panel, text, { warn = not ok, anchor = panel, point = "BOTTOM", y = 8 })
		end, tipTitle = L["Send missing to Shopping"], tip = L["Adds missing reagents for the selected number of crafts to the Profession Planner shopping list. Nothing is bought or crafted."] })
		panel.quantity = UI.Input(panel, { width = 58, numeric = true, maxLetters = 4,
			tipTitle = L["Crafts"], tip = L["Number of crafts to include in this shopping list. The game's crafting amount stays unchanged."],
			onChange = function() Summary.Update(form) end })
		panel.quantity:SetText("1")
		panel.quantityLabel = Text(panel, E.tokens.size.small, "LEFT")
		panel.quantityLabel:SetText(L["Crafts"])
		panel.quantity:SetPoint("BOTTOMLEFT", 8, 8)
		panel.quantityLabel:SetPoint("BOTTOMLEFT", panel.quantity, "TOPLEFT", 0, 4)
		panel.send:SetPoint("BOTTOMRIGHT", -8, 8)
		E:BindOptionsLink(panel, { page = "module:Skins", key = "windows.professions.recipeSkill" })
		Summary.states[form] = panel
		return panel
	end
	function Summary.Open(form)
		local db = WDB("professions")
		if not Usable(form) or not Enabled() or not form:IsVisible() or E:GamepadUIActive()
			or not (db.recipeSkill or db.recipePrices or db.recipeCounts) or not Summary.Recipe(form) then return end
		local panel = Summary.states[form] or Summary.Build(form)
		if not panel.window then
			panel.window = UI.CreateToolWindow(nil, { title = L["Selected recipe summary"], width = 420, height = 300,
				parent = form, onClose = function() panel.expanded = nil; Summary.Update(form) end })
			panel.window:HookScript("OnSizeChanged", function()
				if panel.expanded then Summary.Layout(form, panel) end
			end)
		end
		panel.expanded = true
		panel.window:SetTitle(L["Selected recipe summary"])
		panel.window:Open()
		Summary.Update(form)
	end
	local function FitText(panel)
		UI.RefitButton(panel.send)
		panel.area:ClearAllPoints()
		panel.area:SetPoint("TOPLEFT", 8, -8)
		local rowHeight = math.max(panel.send:GetHeight(), E:TextScale() * 18 + 4)
		panel.quantity:SetHeight(rowHeight)
		panel.quantity:SetWidth(math.ceil(58 * E:TextScale()))
		E:SetFont(panel.quantity, E.tokens.size.label)
		E:SetFont(panel.quantityLabel, E.tokens.size.small)
		panel.area:SetPoint("BOTTOMRIGHT", -8, rowHeight + panel.quantityLabel:GetStringHeight() + 20)
		panel.area:Update()
		panel.text:SetHeight(0)
		local textHeight = panel.text:GetStringHeight()
		panel.text:SetHeight(textHeight)
		panel.area.child:SetHeight(textHeight)
		panel.area:Update()
		return rowHeight + panel.quantityLabel:GetStringHeight() + E:TextScale() * 24 + 32
	end
	function Summary.Layout(form, panel)
		if panel.expanded then
			panel:SetParent(panel.window.content)
			panel:ClearAllPoints()
			panel:SetAllPoints(panel.window.content)
			if panel.launcher then panel.launcher:Hide() end
			FitText(panel)
			panel:Show()
			return
		end
		panel:SetParent(form)
		local top, bottom, width = Read(form.GetTop, form), Read(form.GetBottom, form), Read(form.GetWidth, form)
		if type(top) ~= "number" or type(bottom) ~= "number" or not width or width < 100 then
			panel:Hide()
			if panel.launcher then panel.launcher:Hide() end
			return
		end
		local ceiling = top
		local found
		for _, key in ipairs({ "Reagents", "OptionalReagents", "FinishingReagents", "Concentrate" }) do
			local part = form[key]
			if part and Read(part.IsShown, part) then
				local edge = Read(part.GetBottom, part)
				if type(edge) ~= "number" then
					panel:Hide()
					if panel.launcher then panel.launcher:Hide() end
					return
				end
				ceiling, found = math.min(ceiling, edge), true
			end
		end
		for _, slot in ipairs(PlainTable(Read(form.GetSlots, form)) or {}) do
			local text = reagentText[slot]
			if text and text:IsVisible() then
				local edge = Read(text.GetBottom, text)
				if type(edge) ~= "number" then
					panel:Hide()
					if panel.launcher then panel.launcher:Hide() end
					return
				end
				ceiling = math.min(ceiling, edge)
			end
		end
		local floor = bottom + 8
		for _, key in ipairs({ "TrackRecipeCheckbox", "AllocateBestQualityCheckbox", "Details" }) do
			local part = form[key]
			if part and Read(part.IsShown, part) then
				local edge = Read(part.GetTop, part)
				if type(edge) ~= "number" then
					panel:Hide()
					if panel.launcher then panel.launcher:Hide() end
					return
				end
				floor = math.max(floor, edge + 8)
			end
		end
		local height = ceiling - floor - 8
		local minimumHeight = FitText(panel)
		if panel.launcher then panel.launcher:Hide() end
		local controlsWidth = panel.quantity:GetWidth() + panel.send:GetWidth() + 24
		if not found or height < minimumHeight or width - 40 < controlsWidth then
			panel:Hide()
			if not panel.launcher then
				panel.launcher = UI.Button(form, { text = L["Recipe summary"], minWidth = 100,
					onClick = function() Summary.Open(form) end })
				own[panel.launcher] = true
			end
			local button = panel.launcher
			button:SetText(L["Recipe summary"])
			UI.RefitButton(button)
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", form, "TOPLEFT", 20, ceiling - top - 8)
			button:SetShown(found and button:GetHeight() <= height and button:GetWidth() <= width - 40)
			return
		end
		panel:ClearAllPoints()
		panel:SetPoint("TOPLEFT", form, "TOPLEFT", 20, ceiling - top - 8)
		panel:SetWidth(width - 40)
		panel:SetHeight(math.min(height, 200 * E:TextScale()))
		FitText(panel)
		panel:Show()
	end
	function Summary.Update(form)
		if not Usable(form) then return end
		local panel, db = Summary.states[form], WDB("professions")
		local on = Enabled() and (db.recipeSkill or db.recipePrices or db.recipeCounts)
		local recipe = on and form:IsVisible() and not E:GamepadUIActive() and Summary.Recipe(form)
		if not recipe or not form:IsVisible() or E:GamepadUIActive() then
			if panel then
				panel:Hide()
				if panel.launcher then panel.launcher:Hide() end
				if panel.window then panel.window:Hide() end
				panel.expanded = nil
			end
			return
		end
		panel = panel or Summary.Build(form)
		if not panel.recipe or panel.recipe.id ~= recipe.id then panel.quantity:SetText("1") end
		panel.recipe = recipe
		E:SetFont(panel.text, E.tokens.size.small)
		panel.text:SetText(table.concat(Summary.Lines(recipe), "\n"))
		panel.send:SetEnabled(not recipe.incomplete and (Summary.Quantity(form) or 0) >= 1 and E.ProfessionPlanner ~= nil)
		Summary.Layout(form, panel)
	end
	function Summary.Refresh(itemID)
		for form, panel in pairs(Summary.states) do
			local recipe = panel.recipe
			if not itemID or (recipe and (recipe.result == itemID or recipe.prices[itemID])) then Summary.Update(form) end
		end
	end
end

M.RecipeSummary = recipeSummary

local reagentHooked = setmetatable({}, { __mode = "k" })
local function HookReagents(frame)
	local form = frame.CraftingPage and frame.CraftingPage.SchematicForm
	if not Usable(form) or reagentHooked[form] then return form end
	reagentHooked[form] = true
	for _, method in ipairs({ "Init", "UpdateAllSlots", "Refresh", "OnAllocationsChanged" }) do
		if type(form[method]) == "function" then
			hooksecurefunc(form, method, function(self) Try(UpdateReagents, self); Try(recipeSummary.Update, self) end)
		end
	end
	form:HookScript("OnShow", function() Try(recipeSummary.Update, form) end)
	form:HookScript("OnHide", function()
		local panel = recipeSummary.states[form]
		if panel then
			panel:Hide()
			if panel.launcher then panel.launcher:Hide() end
			if panel.window then panel.window:Hide() end
			panel.expanded = nil
		end
	end)
	form:HookScript("OnSizeChanged", function()
		local panel = recipeSummary.states[form]
		if panel and M.active and E:BlizzardAllowed("professions", "improve") then Try(recipeSummary.Update, form) end
	end)
	local page = frame.CraftingPage
	if page and type(page.Refresh) == "function" then
		hooksecurefunc(page, "Refresh", function() Try(recipeSummary.Update, form) end)
	end

	return form
end

M.HookProfessionReagents = HookReagents

Window({
	key = "professions", element = "professions", addon = "Blizzard_Professions", frame = "ProfessionsFrame",
	title = "Professions",
	tree = { skip = function(frame)
		local key = frame.GetParentKey and frame:GetParentKey()
		return key == "SpecPage" or key == "OrdersPage"
	end },
	skin = function(frame)
		Kit.SkinSideTabs({ frame.ProfessionsOverviewTab })
		Kit.SkinSideTabs(frame.rightProfessionTabs)
		Kit.SkinTabSystem(frame.TabSystem)
		local page = frame.CraftingPage
		if Usable(page) then
			for _, region in ipairs({ page:GetRegions() }) do
				if region:IsObjectType("Texture") and region:GetDrawLayer() == "BACKGROUND" then Fade(true, region) end
			end
			local list = page.RecipeList
			if Usable(list) then
				Fade(true, list.Background, list.BackgroundNineSlice)
				Box(list, true)
				E:SkinEditBox(list.SearchBox)
				E:SkinDropdown(list.FilterDropdown)
				if Usable(list.ScrollBox) then
					E:HookScrollBoxRows(list.ScrollBox, function(row) E:SkinRow(row) end)
				end
			end
			local form = page.SchematicForm
			if Usable(form) then
				Fade(true, form.Background, form.MinimalBackground, form.NineSlice)
				Box(form, true)
			end
			for _, key in ipairs({ "Prof0ToolSlot", "Prof0Gear0Slot", "Prof0Gear1Slot", "Prof1ToolSlot", "Prof1Gear0Slot",
				"Prof1Gear1Slot", "CookingToolSlot", "CookingGear0Slot", "FishingToolSlot", "FishingGear0Slot", "FishingGear1Slot" }) do
				local slot = page[key]
				if Usable(slot) then
					Kit.SkinItemButton(slot, { quality = function(button)
						local id = button.GetID and button:GetID()
						return id and id > 0 and GetInventoryItemQuality("player", id) or nil
					end })
				end
			end
			Fade(true, page.GearSlotDivider)
		end
	end,
	refresh = function(frame)
		local page = frame.CraftingPage
		if not Usable(page) then return end
		for _, key in ipairs({ "Prof0ToolSlot", "Prof0Gear0Slot", "Prof0Gear1Slot", "Prof1ToolSlot", "Prof1Gear0Slot",
			"Prof1Gear1Slot", "CookingToolSlot", "CookingGear0Slot", "FishingToolSlot", "FishingGear0Slot", "FishingGear1Slot" }) do
			if items[page[key]] then Kit.UpdateItemButton(page[key]) end
		end
	end,
	improve = function(frame, _, on)
		local form = on and HookReagents(frame) or (frame.CraftingPage and frame.CraftingPage.SchematicForm)
		if form then UpdateReagents(form); recipeSummary.Update(form) end
	end,
})

---------------------------------------------------------------------------
-- Class and profession trainer: skin, and the total cost of what you
-- can learn right now. Training stays a click on Blizzard's own button.
---------------------------------------------------------------------------
local trainer = {}

local function TrainerTotal()
	if type(GetNumTrainerServices) ~= "function" then return 0, 0 end
	local count, total = 0, 0
	for index = 1, GetNumTrainerServices() do
		local _, serviceType = GetTrainerServiceInfo(index)
		if serviceType == "available" then
			local cost = GetTrainerServiceCost(index)
			count = count + 1
			if type(cost) == "number" then total = total + cost end
		end
	end
	return count, total
end

local function UpdateTrainerTotal()
	local frame = _G.ClassTrainerFrame
	if not Usable(frame) then return end
	local show = M.active and E:BlizzardAllowed("class-trainer", "improve") and WDB("trainer").costTotal
	if not show then
		if trainer.total then trainer.total:Hide() end
		return
	end
	if not trainer.total then
		trainer.total = Text(frame, 11, "LEFT")
		local anchor = _G.ClassTrainerFrameMoneyBg
		if anchor then
			trainer.total:SetPoint("LEFT", anchor, "RIGHT", 4, 6)
		else
			trainer.total:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 160, 8)
		end
		local train = frame.TrainButton
		if train then trainer.total:SetPoint("RIGHT", train, "LEFT", -6, 0) end
	end
	local count, total = TrainerTotal()
	E:SetFont(trainer.total, E.tokens.size.small)
	if count == 0 then
		trainer.total:SetText(E:TextHex("secondary") .. L["Nothing to learn right now"] .. "|r")
	else
		local money = GetMoneyString and GetMoneyString(total, true) or tostring(total)
		local color = (GetMoney() >= total) and "|cffffffff" or E:TextHex("bad")
		trainer.total:SetFormattedText(E:TextHex("secondary") .. L["%d to learn:"] .. "|r %s%s|r", count, color, money)
	end
	trainer.total:Show()
end

local function SkinTrainerRow(row)
	if not Usable(row) then return end
	if row.LeftPiece or row.CenterPiece then
		-- Category header.
		Fade(true, row.LeftPiece, row.RightPiece, row.CenterPiece)
		if row.Label then
			E:SetFont(row.Label, E.tokens.size.body)
			row.Label:SetTextColor(E:TokenColor("accent"))
		end
		return
	end
	E:SkinRow(row)
	if row.icon then E:TrimIcon(row.icon) end
	if row.selectedTex then
		local r, g, b = Accent()
		row.selectedTex:SetColorTexture(r, g, b, 0.25)
	end
	Fade(true, row.disabledBG)
	if row.name then E:SetFont(row.name, E.tokens.size.body) end
end

---------------------------------------------------------------------------
-- Trainer list: every service this trainer offers in one compact
-- list beside the window, what you can learn now first, then what comes
-- with later levels, each with its rank, required level and cost, straight
-- from the trainer API (GetTrainerServiceInfo / GetTrainerServiceCost).
-- Clicking a row selects it in Blizzard's list; training stays Blizzard's
-- Train button. There is no "Train all" button: buying many services from
-- one click counts as automation (a design decision).
-- Written from scratch for EldoUI; no code from other addons.
---------------------------------------------------------------------------
local LIST_ROWS, LIST_ROW_HEIGHT = 18, 20

-- The spell a trainer service teaches, for the Training module's ignore
-- list (E:IsTrainingIgnored, Modules/Training.lua).
local function ServiceSpellID(index)
	if not (E.IsTrainingIgnored and C_TooltipInfo and C_TooltipInfo.GetTrainerService) then return nil end
	local ok, data = pcall(C_TooltipInfo.GetTrainerService, index)
	local id = ok and type(data) == "table" and data.id or nil
	if (issecretvalue and issecretvalue(id)) or type(id) == "nil" then return nil end
	return id
end

-- True when the player ignored this service in the Training module.
local function IgnoredInTraining(service)
	if not (WDB("trainer").hideIgnored and E.IsTrainingIgnored) or service.kind == "used" then return false end
	if service.spellID and E:IsTrainingIgnored(service.spellID) then return true end
	return E:IsTrainingIgnored(service.name, service.rank) and true or false
end

local function TrainerServices()
	local list = {}
	if type(GetNumTrainerServices) ~= "function" then return list end
	local level = UnitLevel("player")
	for index = 1, GetNumTrainerServices() do
		local name, serviceType, texture, reqLevel, subText = GetTrainerServiceInfo(index)
		if name and serviceType ~= "header" then
			local cost, isProfession = GetTrainerServiceCost(index)
			list[#list + 1] = {
				index = index, name = name, kind = serviceType, icon = texture,
				level = tonumber(reqLevel) or 0, rank = subText, cost = tonumber(cost) or 0,
				profession = isProfession and true or false,
				later = serviceType == "unavailable" and type(level) == "number" and (tonumber(reqLevel) or 0) > level,
				spellID = ServiceSpellID(index),
			}
		end
	end
	local order = { available = 1, unavailable = 2, used = 3 }
	table.sort(list, function(a, b)
		local oa, ob = order[a.kind] or 4, order[b.kind] or 4
		if oa ~= ob then return oa < ob end
		if a.level ~= b.level then return a.level < b.level end
		return a.index < b.index
	end)
	return list
end

local function MoneyText(copper)
	return E:FormatMoney(copper)
end

local function ListRow(panel, index)
	local row = CreateFrame("Frame", nil, panel)
	row:SetHeight(LIST_ROW_HEIGHT)
	row:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -26 - (index - 1) * LIST_ROW_HEIGHT)
	row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -26 - (index - 1) * LIST_ROW_HEIGHT)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(LIST_ROW_HEIGHT - 4, LIST_ROW_HEIGHT - 4)
	row.icon:SetPoint("LEFT", 0, 0)
	E:TrimIcon(row.icon)
	row.cost = Text(row, 11, "RIGHT")
	row.cost:SetPoint("RIGHT", 0, 0)
	row.level = Text(row, 11, "RIGHT")
	row.level:SetPoint("RIGHT", row.cost, "LEFT", -6, 0)
	row.level:SetWidth(42)
	row.name = Text(row, 12, "LEFT")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
	row.name:SetPoint("RIGHT", row.level, "LEFT", -4, 0)
	row.name:SetWordWrap(false)
	row:EnableMouse(true)
	-- Display only: the service's own tooltip. Training stays a click on
	-- Blizzard's Train button (or the confirmed button below).
	row:SetScript("OnEnter", function(self)
		if not self.index or E.FrameCheck(GameTooltip, "IsForbidden") then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if not pcall(GameTooltip.SetTrainerService, GameTooltip, self.index) then GameTooltip:AddLine(self.name:GetText() or "") end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() if not E.FrameCheck(GameTooltip, "IsForbidden") then GameTooltip:Hide() end end)
	own[row] = true
	return row
end

local function TrainerPanel(frame)
	if trainer.panel then return trainer.panel end
	local panel = CreateFrame("Frame", nil, frame)
	panel:SetSize(300, 26 + LIST_ROWS * LIST_ROW_HEIGHT + 34)
	panel:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
	panel:SetFrameLevel(frame:GetFrameLevel() + 2)
	-- The art style's panel (follows style changes) and the shells'
	-- header-font title.
	E:SetPanelTemplate(panel, M.db.transparent)
	own[panel] = true
	panel.title = E.UIKit.Title(panel, 13)
	panel.title:SetPoint("TOPLEFT", 8, -7)
	panel.title:SetText(L["What this trainer teaches"])
	panel.rows = {}
	for index = 1, LIST_ROWS do panel.rows[index] = ListRow(panel, index) end
	panel.offset = 0
	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function(self, delta)
		self.offset = math.max(0, math.min((self.count or 0) - LIST_ROWS, self.offset - delta * 3))
		M:UpdateTrainerList()
	end)
	panel.empty = E.UIKit.Text(panel, E.tokens.size.small, "CENTER", "secondary")
	panel.empty:SetPoint("TOP", 0, -40)
	panel.empty:SetText(L["This trainer has nothing for you."])
	trainer.panel = panel
	return panel
end

function M:UpdateTrainerList()
	local frame = _G.ClassTrainerFrame
	if not Usable(frame) then return end
	local db = WDB("trainer")
	-- The list (or the Training window beside the trainer) steps aside while
	-- the game's gamepad interface is on.
	local show = self.active and E:BlizzardAllowed("class-trainer", "improve") and db.serviceList and not E:GamepadUIActive()
	if not show then
		if trainer.panel then trainer.panel:Hide() end
		local training = E.modules.Training
		if training and training.trainerDocked then training:UndockTrainer() end
		return
	end
	-- A class trainer with Training on: one list, the Training window
	-- beside the trainer. Profession trainers keep this one.
	local training = E.modules.Training
	local profession = type(IsTradeskillTrainer) == "function" and IsTradeskillTrainer()
	if training and training.active and training.DockTrainer and not profession then
		if trainer.panel then trainer.panel:Hide() end
		if not training.trainerDocked then training:DockTrainer(frame) end
		return
	end
	if training and training.trainerDocked then training:UndockTrainer() end
	local panel = TrainerPanel(frame)
	local services = {}
	for _, service in ipairs(TrainerServices()) do
		if (service.kind ~= "used" or db.showKnown) and not IgnoredInTraining(service) then services[#services + 1] = service end
	end
	panel.count = #services
	panel.offset = math.max(0, math.min(panel.offset, #services - LIST_ROWS))
	local money = GetMoney()
	for slot, row in ipairs(panel.rows) do
		local service = services[slot + panel.offset]
		if service then
			row.index = service.index
			row.icon:SetTexture(service.icon)
			row.icon:SetDesaturated(service.kind ~= "available")
			local rank = (service.rank and service.rank ~= "") and (" " .. E:TextHex("secondary") .. "(" .. service.rank .. ")|r") or ""
			if service.kind == "available" then
				row.name:SetText(service.name .. rank)
			else
				row.name:SetText(E:TextHex("secondary") .. service.name .. "|r" .. rank)
			end
			row.level:SetText(service.level > 1 and (service.later and E:TextHex("bad") or E:TextHex("secondary")) .. (E:GameText(_G.LEVEL_ABBR, L["Lvl"])) .. " " .. service.level .. "|r" or "")
			if service.kind == "used" then
				row.cost:SetText(E:TextHex("secondary") .. (E:GameText(ITEM_SPELL_KNOWN, L["Known"])) .. "|r")
			elseif service.cost > 0 then
				row.cost:SetText((service.cost > money and E:TextHex("bad") or "|cffffffff") .. MoneyText(service.cost) .. "|r")
			else
				row.cost:SetText("")
			end
			row:Show()
		else
			row.index = nil
			row:Hide()
		end
	end
	panel.empty:SetShown(#services == 0)
	panel:Show()
end

local function UpdateTrainerExtras()
	UpdateTrainerTotal()
	M:UpdateTrainerList()
end

Window({
	key = "trainer", element = "class-trainer", addon = "Blizzard_TrainerUI", frame = "ClassTrainerFrame",
	title = "Trainer",
	skin = function(frame)
		Kit.SkinStatusBar(_G.ClassTrainerStatusBar)
		E:SkinDropdown(frame.FilterDropdown)
		E:SkinButton(frame.TrainButton)
		E:SkinScrollBar(frame.ScrollBar)
		E:SkinInset(frame.bottomInset)
		Fade(true, frame.BG, _G.ClassTrainerFrameMoneyBg)
		if Usable(frame.ScrollBox) then E:HookScrollBoxRows(frame.ScrollBox, SkinTrainerRow) end
		SkinTrainerRow(frame.skillStepButton)
	end,
	improve = function(frame)
		if not trainer.hooked then
			trainer.hooked = true
			if type(_G.ClassTrainerFrame_Update) == "function" then
				hooksecurefunc("ClassTrainerFrame_Update", function() Try(UpdateTrainerExtras) end)
			end
			frame:HookScript("OnShow", function() Try(UpdateTrainerExtras) end)
		end
		UpdateTrainerExtras()
	end,
})

---------------------------------------------------------------------------
-- Legacy window and achievements
---------------------------------------------------------------------------
Window({
	key = "legacy", element = "legacy-achievements", addon = "Blizzard_LegacySystem", frame = "LegacySystemFrame",
	title = "Legacy window",
	tree = { skip = function(frame)
		local key = frame.GetParentKey and frame:GetParentKey()
		return key == "TreePage"
	end },
	skin = function(frame)
		Kit.SkinSideTabs(frame.Tabs)
	end,
})

Window({
	key = "achievements", element = "legacy-achievements", addon = "Blizzard_AchievementUI", frame = "AchievementFrame",
	title = "Achievements and challenges",
	skin = function(frame)
		local tabs = {}
		for i = 1, 6 do
			if Usable(_G["AchievementFrameTab" .. i]) then tabs[#tabs + 1] = _G["AchievementFrameTab" .. i] end
		end
		E:SkinTabs(tabs, { owner = frame })
		Fade(true, _G.AchievementFrameHeader, _G.AchievementFrameWaterMark, _G.AchievementFrameBackground,
			_G.AchievementFrameMetalBorderTopLeft, _G.AchievementFrameMetalBorderTopRight,
			_G.AchievementFrameMetalBorderBottomLeft, _G.AchievementFrameMetalBorderBottomRight,
			_G.AchievementFrameWoodBorderTopLeft, _G.AchievementFrameWoodBorderTopRight,
			_G.AchievementFrameWoodBorderBottomLeft, _G.AchievementFrameWoodBorderBottomRight)
	end,
})

---------------------------------------------------------------------------
-- Collections: skin, and one line with what you have collected.
---------------------------------------------------------------------------
local collections = {}

local function Count(fn, ...)
	if type(fn) ~= "function" then return end
	local ok, a, b = pcall(fn, ...)
	if ok then return a, b end
end

local function CollectedMounts()
	if not (C_MountJournal and C_MountJournal.GetMountIDs and C_MountJournal.GetMountInfoByID) then return end
	local ok, ids = pcall(C_MountJournal.GetMountIDs)
	if not ok or type(ids) ~= "table" then return end
	local owned = 0
	for _, id in ipairs(ids) do
		local isCollected = select(11, C_MountJournal.GetMountInfoByID(id))
		if isCollected then owned = owned + 1 end
	end
	return owned
end

local function UpdateCollections()
	local frame = _G.CollectionsJournal
	if not Usable(frame) then return end
	local show = M.active and E:BlizzardAllowed("collections", "improve") and WDB("collections").summary
	if not show then
		if collections.line then collections.line:Hide() end
		return
	end
	if not collections.line then
		collections.line = Text(frame, 11, "RIGHT")
		collections.line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -5)
	end
	local parts = {}
	local mounts = CollectedMounts()
	if mounts then parts[#parts + 1] = (E:TextHex("secondary") .. "%s|r %d"):format(L["Mounts"], mounts) end
	local _, pets = Count(C_PetJournal and C_PetJournal.GetNumPets)
	if type(pets) == "number" then parts[#parts + 1] = (E:TextHex("secondary") .. "%s|r %d"):format(L["Pets"], pets) end
	local toys = Count(C_ToyBox and C_ToyBox.GetNumLearnedDisplayedToys)
	if type(toys) == "number" then parts[#parts + 1] = (E:TextHex("secondary") .. "%s|r %d"):format(L["Toys"], toys) end
	local heirlooms = Count(C_Heirloom and C_Heirloom.GetNumKnownHeirlooms)
	if type(heirlooms) == "number" then parts[#parts + 1] = (E:TextHex("secondary") .. "%s|r %d"):format(L["Heirlooms"], heirlooms) end
	E:SetFont(collections.line, E.tokens.size.small)
	collections.line:SetText(table.concat(parts, "   "))
	collections.line:SetShown(#parts > 0)
end

Window({
	key = "collections", element = "collections", addon = "Blizzard_Collections", frame = "CollectionsJournal",
	title = "Collections",
	tree = { skip = function(frame)
		local kind = frame:GetObjectType()
		return kind == "ModelScene"
	end },
	skin = function(frame)
		local container = frame.TabContainer
		if Usable(container) then Kit.SkinSideTabs(container.Tabs) end
		for _, name in ipairs({ "MountJournal", "PetJournal", "ToyBox", "HeirloomsJournal", "WardrobeCollectionFrame" }) do
			local journal = _G[name]
			if Usable(journal) then
				for _, inset in ipairs({ journal.LeftInset, journal.RightInset, journal.BottomLeftInset, journal.MountDisplay, journal.iconsFrame }) do
					if Usable(inset) then E:SkinInset(inset) end
				end
				if Usable(journal.ScrollBox) then
					E:HookScrollBoxRows(journal.ScrollBox, function(row) E:SkinRow(row) end)
				end
			end
		end
	end,
	improve = function(frame)
		if not collections.hooked then
			collections.hooked = true
			frame:HookScript("OnShow", function() Try(UpdateCollections) end)
		end
		UpdateCollections()
	end,
})

---------------------------------------------------------------------------
-- Item socketing and item interaction
---------------------------------------------------------------------------
Window({
	key = "socketing", element = "item-socketing", addon = "Blizzard_ItemSocketingUI", frame = "ItemSocketingFrame",
	title = "Item socketing",
	skin = function(frame)
		for key, value in pairs(frame) do
			if type(key) == "string" and IsTexture(value) and (key:find("^GoldBorder") or key:find("^BorderShadow")
				or key:find("^ParchmentFrame") or key:find("^SocketFrame") or key:find("^ButtonFrame") or key:find("^ButtonBorder")) then
				Fade(true, value)
			end
		end
		local scroll = _G.ItemSocketingScrollFrame
		if Usable(scroll) then Box(scroll, true, 2) end
	end,
})

Window({
	key = "interaction", element = "item-socketing", addon = "Blizzard_ItemInteractionUI", frame = "ItemInteractionFrame",
	title = "Item interaction",
})

---------------------------------------------------------------------------
-- Dressing room: skin, Undress and Target buttons, and a
-- resize grip. Trying things on stays Blizzard's own model scene.
---------------------------------------------------------------------------
local dress = {}

local function DressActor()
	local frame = _G.DressUpFrame
	local scene = frame and frame.ModelScene
	if not scene or type(scene.GetPlayerActor) ~= "function" then return end
	local ok, actor = pcall(scene.GetPlayerActor, scene)
	if ok then return actor end
end

local function DressButton(parent, label, tip, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(62, 20)
	E:SetTemplate(button, true)
	button.text = Text(button, 11, "CENTER")
	button.text:SetPoint("CENTER")
	button.text:SetText(label)
	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	hover:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	hover:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:AccentTexture(hover, 0.18)
	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnter", function(self)
		if E.FrameCheck(GameTooltip, "IsForbidden") then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		E.UIKit.TipTitle(GameTooltip, label)
		E.UIKit.TipText(GameTooltip, tip)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() if not E.FrameCheck(GameTooltip, "IsForbidden") then GameTooltip:Hide() end end)
	own[button] = true
	return button
end

-- Slot strip: one small button per gear slot along the model's
-- right edge, showing what the preview wears there. Click a slot to take
-- just that piece off the preview model (ModelSceneActor:UndressSlot).
-- A Sheathe button puts the preview's weapons away or draws them. Only
-- the preview changes; your own gear is never touched.
local DRESS_SLOTS = { "HeadSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "ShirtSlot", "TabardSlot", "WristSlot",
	"HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "MainHandSlot", "SecondaryHandSlot", "RangedSlot" }
local NO_TRANSMOG = (Constants and Constants.Transmog and Constants.Transmog.NoTransmogID) or 0

local function DressSlotIcon(actor, slot)
	if not actor or type(actor.GetItemTransmogInfo) ~= "function" then return nil end
	local ok, info = pcall(actor.GetItemTransmogInfo, actor, slot)
	local id = ok and type(info) == "table" and info.appearanceID
	if not id or id == NO_TRANSMOG then return nil end
	if C_TransmogCollection and C_TransmogCollection.GetSourceIcon then
		local okIcon, icon = pcall(C_TransmogCollection.GetSourceIcon, id)
		if okIcon then return icon end
	end
end

local function RefreshDressSlots()
	local strip = dress.strip
	if not strip or not strip:IsShown() then return end
	local actor = DressActor()
	for _, button in ipairs(strip.buttons) do
		local icon = DressSlotIcon(actor, button.slot)
		button.icon:SetTexture(icon or button.empty)
		button.icon:SetDesaturated(not icon)
		button.icon:SetAlpha(icon and 1 or 0.45)
		button.filled = icon ~= nil
	end
end

local function DressSlotButton(strip, slotName, slot, empty)
	local button = CreateFrame("Button", nil, strip)
	button:SetSize(24, 24)
	E:SetTemplate(button, true)
	button.slot, button.empty, button.slotName = slot, empty, slotName
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	button.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(button.icon)
	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints(button.icon)
	E:AccentTexture(hover, 0.25)
	button:SetScript("OnClick", function(self)
		local actor = DressActor()
		if actor and actor.UndressSlot and self.filled then pcall(actor.UndressSlot, actor, self.slot) end
		C_Timer.After(0, RefreshDressSlots)
	end)
	button:SetScript("OnEnter", function(self)
		if E.FrameCheck(GameTooltip, "IsForbidden") then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		E.UIKit.TipTitle(GameTooltip, _G[strupper(self.slotName)] or self.slotName)
		if self.filled then
			E:TooltipHint(GameTooltip, { L["Click"], L["take this piece off the preview"] })
		else
			E.UIKit.TipText(GameTooltip, L["Nothing on the preview here."])
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() if not E.FrameCheck(GameTooltip, "IsForbidden") then GameTooltip:Hide() end end)
	own[button] = true
	return button
end

local function DressStrip(frame)
	if dress.strip then return dress.strip end
	local scene = frame.ModelScene or frame
	local strip = CreateFrame("Frame", nil, frame)
	strip:SetSize(24, 24)
	strip:SetPoint("TOPRIGHT", scene, "TOPRIGHT", -6, -6)
	strip:SetFrameLevel((scene:GetFrameLevel() or 1) + 10)
	strip.buttons = {}
	local previous
	for _, slotName in ipairs(DRESS_SLOTS) do
		local ok, slot, empty = pcall(GetInventorySlotInfo, slotName)
		if ok and slot then
			local button = DressSlotButton(strip, slotName, slot, empty)
			if previous then
				button:SetPoint("TOP", previous, "BOTTOM", 0, -3)
			else
				button:SetPoint("TOP", strip, "TOP", 0, 0)
			end
			strip.buttons[#strip.buttons + 1] = button
			previous = button
		end
	end
	-- The preview changes from many places (links, sets, the Reset button):
	-- read it again a few times a second while the strip shows.
	strip:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = (self.elapsed or 0) + elapsed
		if self.elapsed < 0.3 then return end
		self.elapsed = 0
		RefreshDressSlots()
	end)
	own[strip] = true
	dress.strip = strip
	return strip
end

local function UpdateDressSlots(frame, show)
	local db = WDB("dressup")
	if show and db.slotStrip then
		DressStrip(frame):Show()
		RefreshDressSlots()
	elseif dress.strip then
		dress.strip:Hide()
	end
end

local function UpdateDressButtons()
	local frame = _G.DressUpFrame
	if not Usable(frame) then return end
	local db = WDB("dressup")
	local allowed = M.active and E:BlizzardAllowed("dressing-room", "improve")
	local inPlayerMode = type(frame.GetMode) ~= "function" or frame:GetMode() == "player"
	local show = allowed and db.buttons and inPlayerMode
	if show and not dress.buttons then
		local scene = frame.ModelScene or frame
		local undress = DressButton(frame, L["Undress"], L["Takes every item off the preview model. Your own gear is not touched."], function()
			local actor = DressActor()
			if actor and actor.Undress then actor:Undress() end
		end)
		undress:SetPoint("TOPLEFT", scene, "TOPLEFT", 6, -6)
		local target = DressButton(frame, L["Target"], L["Shows your target's appearance on the preview model (players only)."], function()
			local actor = DressActor()
			if not actor or not actor.SetModelByUnit then return end
			local ok, isPlayer = pcall(UnitIsPlayer, "target")
			if not ok or (issecretvalue and issecretvalue(isPlayer)) or not isPlayer then
				UIErrorsFrame:AddMessage(L["Target a player to see their appearance."], unpack(E.tokens.text.warn))
				return
			end
			pcall(actor.SetModelByUnit, actor, "target", false, true)
		end)
		target:SetPoint("TOPLEFT", undress, "BOTTOMLEFT", 0, -4)
		dress.buttons = { undress, target }
		for _, button in ipairs(dress.buttons) do button:SetFrameLevel((scene:GetFrameLevel() or 1) + 10) end
	end
	for _, button in ipairs(dress.buttons or {}) do button:SetShown(show and true or false) end

	local sheathe = allowed and db.sheathe and inPlayerMode
	if sheathe and not dress.sheathe then
		local scene = frame.ModelScene or frame
		local button = DressButton(frame, L["Sheathe"], L["Puts the preview's weapons away, or draws them again."], function()
			local actor = DressActor()
			if not actor or not actor.SetSheathed then return end
			local ok, sheathed = pcall(actor.GetSheathed, actor)
			pcall(actor.SetSheathed, actor, not (ok and sheathed))
		end)
		button:SetPoint("BOTTOMLEFT", scene, "BOTTOMLEFT", 6, 36)
		button:SetFrameLevel((scene:GetFrameLevel() or 1) + 10)
		dress.sheathe = button
	end
	if dress.sheathe then dress.sheathe:SetShown(sheathe and true or false) end
	UpdateDressSlots(frame, allowed and inPlayerMode)
end

local function DressMinimized(frame)
	local toggle = frame.MaximizeMinimizeFrame
	if toggle and type(toggle.IsMinimized) == "function" then
		local ok, minimized = pcall(toggle.IsMinimized, toggle)
		if ok then return minimized end
	end
	return false
end

local function ApplyDressSize()
	local frame = _G.DressUpFrame
	if not Usable(frame) then return end
	local db = WDB("dressup")
	local on = M.active and E:BlizzardAllowed("dressing-room", "improve") and db.resizable
	if dress.grip then dress.grip:SetShown(on and not DressMinimized(frame) and true or false) end
	if not on or DressMinimized(frame) or type(db.size) ~= "table" then return end
	if E.FrameCheck(frame, "IsProtected") and InCombatLockdown() then return end
	frame:SetSize(db.size[1], db.size[2])
end

local function DressGrip(frame)
	if dress.grip then return end
	-- The shared size grip.
	local grip = E.UIKit.SizeGrip(frame, {
		size = 14,
		onStart = function()
			if E.FrameCheck(frame, "IsProtected") and InCombatLockdown() then return end
			frame:SetResizable(true)
			if frame.SetResizeBounds then frame:SetResizeBounds(334, 423, 1100, 1100) end
			frame:StartSizing("BOTTOMRIGHT")
			dress.sizing = true
		end,
		onStop = function()
			if not dress.sizing then return end
			dress.sizing = false
			frame:StopMovingOrSizing()
			if frame.SetUserPlaced then pcall(frame.SetUserPlaced, frame, false) end
			local width, height = frame:GetSize()
			WDB("dressup").size = { math.floor(width + 0.5), math.floor(height + 0.5) }
			Kit.Reapply(frame)
		end,
	})
	own[grip] = true
	dress.grip = grip
end

Window({
	key = "dressup", element = "dressing-room", frame = "DressUpFrame",
	title = "Dressing room",
	tree = { skip = function(frame)
		local key = frame.GetParentKey and frame:GetParentKey()
		return key == "CustomSetDetailsPanel" or key == "SetSelectionPanel"
	end },
	skin = function(frame)
		Fade(true, frame.ModelBackground)
		local panel = frame.CustomSetDetailsPanel
		if Usable(panel) then
			for _, region in ipairs({ panel:GetRegions() }) do
				if region:IsObjectType("Texture") and region ~= panel.ClassBackground then Fade(true, region) end
			end
			Box(panel, true, -6)
		end
		E:SkinButton(frame.ResetButton)
		E:SkinButton(frame.LinkButton)
		E:SkinButton(_G.DressUpFrameCancelButton)
		E:SkinDropdown(frame.CustomSetDropdown)
		local side = _G.SideDressUpFrame
		if Usable(side) then
			E:SkinPanel(side, { accentLine = false })
			E:SkinButton(side.ResetButton)
			E:SkinCloseButton(_G.SideDressUpFrameCloseButton)
		end
	end,
	improve = function(frame)
		if not dress.hooked then
			dress.hooked = true
			if type(frame.SetMode) == "function" then
				hooksecurefunc(frame, "SetMode", function() Try(UpdateDressButtons) end)
			end
			if type(frame.ConfigureSize) == "function" then
				hooksecurefunc(frame, "ConfigureSize", function() Try(ApplyDressSize) end)
			end
			frame:HookScript("OnShow", function()
				Try(UpdateDressButtons)
				Try(ApplyDressSize)
			end)
		end
		DressGrip(frame)
		UpdateDressButtons()
		ApplyDressSize()
	end,
})

---------------------------------------------------------------------------
-- Inspect window: skin, flat slots with quality
-- borders, item level per slot and the average item level the game reports.
---------------------------------------------------------------------------
local INSPECT_SLOTS = {
	"HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "ShirtSlot", "TabardSlot", "WristSlot",
	"HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot",
	"MainHandSlot", "SecondaryHandSlot", "RangedSlot",
}
local NO_LEVEL = { ShirtSlot = true, TabardSlot = true }
local inspect = { levels = setmetatable({}, { __mode = "k" }), marks = setmetatable({}, { __mode = "k" }) }

local function InspectUnit()
	local frame = _G.InspectFrame
	local unit = frame and frame.unit
	if type(unit) == "string" then return unit end
end

local function InspectQuality(button)
	local unit = InspectUnit()
	local id = button.GetID and button:GetID()
	if not unit or not id or id == 0 then return end
	local ok, quality = pcall(GetInventoryItemQuality, unit, id)
	if ok then return quality end
end

local function InspectLevelText(button)
	local text = inspect.levels[button]
	if not text then
		local holder = CreateFrame("Frame", nil, button)
		holder:SetAllPoints()
		holder:SetFrameLevel(button:GetFrameLevel() + 4)
		own[holder] = true
		text = Text(holder, 12, "CENTER")
		inspect.levels[button] = text
	end
	return text
end

-- Gem and enchant marks from the item link (item:id:enchant:gem1:gem2:gem3:gem4),
-- in the slot's top-left corner.
local MAX_MARKS = 4
local ENCHANT_ICON = "Interface\\Icons\\Trade_Engraving"

local function LinkMarks(link)
	local list = {}
	local body = type(link) == "string" and link:match("item:([^|]+)")
	if not body then return list end
	local fields = {}
	for field in (body .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = field end
	local enchant = tonumber(fields[2])
	if enchant and enchant > 0 then list[#list + 1] = ENCHANT_ICON end
	for i = 3, 6 do
		local gem = tonumber(fields[i])
		if gem and gem > 0 and C_Item.GetItemIconByID then list[#list + 1] = C_Item.GetItemIconByID(gem) or 134400 end
	end
	return list
end

local function UpdateInspectMarks(button, link, show)
	local marks = inspect.marks[button]
	if not show or not link then
		if marks then for _, mark in ipairs(marks) do mark:Hide() end end
		return
	end
	if not marks then
		local holder = InspectLevelText(button):GetParent()
		marks = {}
		for i = 1, MAX_MARKS do
			local mark = holder:CreateTexture(nil, "OVERLAY")
			mark:SetSize(9, 9)
			mark:SetPoint("TOPLEFT", button, "TOPLEFT", 2 + (i - 1) * 10, -2)
			E:TrimIcon(mark)
			marks[i] = mark
		end
		inspect.marks[button] = marks
	end
	local list = LinkMarks(link)
	for i, mark in ipairs(marks) do
		if list[i] then
			mark:SetTexture(list[i])
			mark:Show()
		else
			mark:Hide()
		end
	end
end

local function UpdateInspectSlot(button)
	if not Usable(button) then return end
	local db = WDB("inspect")
	if items[button] then Kit.UpdateItemButton(button) end
	local improve = M.active and E:BlizzardAllowed("inspect-frame", "improve")
	local unitForMarks = InspectUnit()
	local linkForMarks = unitForMarks and button.GetID and GetInventoryItemLink(unitForMarks, button:GetID())
	UpdateInspectMarks(button, linkForMarks, improve and db.marks)
	local show = improve and db.itemLevel
	local text = inspect.levels[button]
	if not show then
		if text then text:Hide() end
		return
	end
	local name = button:GetName() or ""
	local slotName = name:gsub("^Inspect", "")
	local unit = InspectUnit()
	if not unit or NO_LEVEL[slotName] then
		if text then text:Hide() end
		return
	end
	local link = GetInventoryItemLink(unit, button:GetID())
	local level = link and C_Item.GetDetailedItemLevelInfo(link)
	text = InspectLevelText(button)
	text:ClearAllPoints()
	if db.ilvlPosition == "TOP" then text:SetPoint("TOP", 0, -2)
	elseif db.ilvlPosition == "CENTER" then text:SetPoint("CENTER")
	else text:SetPoint("BOTTOM", 0, 2) end
	E:SetFont(text, db.ilvlSize or E.tokens.size.label)
	if type(level) == "number" and level > 1 then
		local quality = InspectQuality(button)
		local r, g, b = 1, 1, 1
		if type(quality) == "number" then r, g, b = C_Item.GetItemQualityColor(quality) end
		text:SetTextColor(r, g, b)
		text:SetText(level)
		text:Show()
	else
		text:Hide()
	end
end

local function UpdateInspectAverage()
	local frame = _G.InspectFrame
	local paper = _G.InspectPaperDollFrame
	if not Usable(frame) or not Usable(paper) then return end
	local db = WDB("inspect")
	local show = M.active and E:BlizzardAllowed("inspect-frame", "improve") and db.avgItemLevel
	if not show then
		if inspect.avg then inspect.avg:Hide() end
		return
	end
	if not inspect.avg then
		local holder = CreateFrame("Frame", nil, paper)
		holder:SetAllPoints()
		holder:SetFrameLevel(paper:GetFrameLevel() + 30)
		own[holder] = true
		inspect.avg = Text(holder, 13, "CENTER")
		local level = paper.LevelTextWrapper or _G.InspectLevelText
		if level then
			inspect.avg:SetPoint("TOP", level, "BOTTOM", 0, -3)
		else
			inspect.avg:SetPoint("TOP", frame, "TOP", 0, -50)
		end
	end
	local unit = InspectUnit()
	local average
	if unit and C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
		local ok, value = pcall(C_PaperDollInfo.GetInspectItemLevel, unit)
		if ok and type(value) == "number" and not (issecretvalue and issecretvalue(value)) then average = value end
	end
	if not average or average <= 0 then
		inspect.avg:Hide()
		return
	end
	local r, g, b = Accent()
	E:SetFont(inspect.avg, E.tokens.size.body)
	inspect.avg:SetFormattedText("|cff%02x%02x%02x%s|r %.1f", r * 255, g * 255, b * 255, E:GameText(STAT_AVERAGE_ITEM_LEVEL, L["Item Level"]), average) -- no-L: format only; the label is E:GameText(STAT_AVERAGE_ITEM_LEVEL, L["Item Level"])
	inspect.avg:Show()
end

local function UpdateInspect()
	for _, slot in ipairs(INSPECT_SLOTS) do Try(UpdateInspectSlot, _G["Inspect" .. slot]) end
	Try(UpdateInspectAverage)
end

local function InspectModelBackground(skinned)
	local model = _G.InspectModelFrame
	if not Usable(model) then return end
	local mode = (skinned and M.active) and WDB("inspect").modelBackground or "blizzard"
	local fade = mode ~= "blizzard"
	Fade(fade, model.BackgroundTopLeft, model.BackgroundTopRight, model.BackgroundBotLeft, model.BackgroundBotRight, model.BackgroundOverlay)
	for _, name in ipairs({ "TopLeft", "TopRight", "BottomLeft", "BottomRight", "Left", "Right", "Top", "Bottom", "Bottom2" }) do
		Fade(fade, _G["InspectModelFrameBorder" .. name])
	end
	if mode ~= "blizzard" and not inspect.modelBg then
		inspect.modelBg = model:CreateTexture(nil, "BACKGROUND", nil, -8)
		inspect.modelBg:SetAllPoints(model)
	end
	if inspect.modelBg then
		inspect.modelBg:SetShown(mode ~= "blizzard")
		-- The art style's panel color (warm under WoW Forever), re-applied
		-- through OnProfileChanged when the art style changes.
		local r, g, b = unpack(E.media.backdropColor)
		inspect.modelBg:SetColorTexture(r, g, b, math.max(E.media.backdropColor[4] or 1, E.tokens.panel.alpha))
	end
end

Window({
	key = "inspect", element = "inspect-frame", addon = "Blizzard_InspectUI", frame = "InspectFrame",
	title = "Inspect",
	skin = function(frame, db)
		if frame.ModeTabs then Kit.SkinSideTabs(frame.ModeTabs.Tabs) end
		local tabs = {}
		for i = 1, 3 do
			if Usable(_G["InspectFrameTab" .. i]) then tabs[#tabs + 1] = _G["InspectFrameTab" .. i] end
		end
		E:SkinTabs(tabs, { owner = frame })
		E:SkinButton(_G.InspectPaperDollFrame and _G.InspectPaperDollFrame.ViewButton)
		if _G.InspectLevelText then E:SetFont(_G.InspectLevelText, E.tokens.size.body) end
	end,
	-- Flat item slots have a switch of their own.
	parts = {
		slots = function()
			for _, slot in ipairs(INSPECT_SLOTS) do
				local button = _G["Inspect" .. slot]
				if Usable(button) then Kit.SkinItemButton(button, { quality = InspectQuality }) end
			end
		end,
	},
	refresh = function(_, _, skinned)
		InspectModelBackground(skinned)
	end,
	improve = function(frame)
		if not inspect.hooked then
			inspect.hooked = true
			if type(_G.InspectPaperDollItemSlotButton_Update) == "function" then
				hooksecurefunc("InspectPaperDollItemSlotButton_Update", function(button) Try(UpdateInspectSlot, button) end)
			end
			frame:HookScript("OnShow", function() C_Timer.After(0, UpdateInspect) end)
		end
		UpdateInspect()
	end,
})

---------------------------------------------------------------------------
-- Putting it together
---------------------------------------------------------------------------
local ELEMENTS = {}
for _, win in ipairs(WINDOWS) do
	if not ELEMENTS[win.element] then
		ELEMENTS[win.element] = true
		ELEMENTS[#ELEMENTS + 1] = win.element
	end
end

local function Active(win, action)
	return M.active and E:BlizzardAllowed(win.element, action)
end

-- Each window's skin is recorded (Core/Skin.lua, E:SkinRecord): with its
-- switch off the window goes back to Blizzard's look at once, and comes
-- back painted when the switch goes on again.
local function RecordKey(win, part)
	return "Skins:" .. win.key .. (part and (":" .. part) or "")
end

-- The window shows the EldoUI look right now.
local function Skinned(win)
	return win.built and E:SkinRecordState(RecordKey(win)) == "on"
end
M.WindowSkinned = function(_, key)
	for _, win in ipairs(WINDOWS) do
		if win.key == key then return Skinned(win) end
	end
	return false
end

-- One record switched to what is wanted: built once, then off and on.
local function Want(key, root, want, build, ...)
	if not want then
		E:SkinRecordOff(key)
	elseif E:SkinRecordState(key) == nil then
		E:SkinRecord(key, root, build, ...)
	else
		E:SkinRecordOn(key)
	end
end

function M:ApplyWindow(win)
	local frame = win.loaded
	if not Usable(frame) then return end
	local db = WDB(win.key)
	local want = Active(win, "skin") and db.skin and true or false
	if want then win.built = true end
	Want(RecordKey(win), frame, want, function()
		Kit.SkinWindow(frame, { transparent = self.db.transparent, titleSize = self.db.titleSize })
		Try(win.skin, frame, db)
		Kit.SkinTree(frame, win.tree)
	end)
	-- Parts of a window with a switch of their own (inspect: flat item slots).
	for part, build in pairs(win.parts or {}) do
		Want(RecordKey(win, part), frame, want and db[part] and true or false, build, frame, db)
	end
	local skinned = Skinned(win)
	if skinned then
		E:SkinRecord(RecordKey(win), frame, function()
			E:SetPanelTransparent(frame, self.db.transparent)
			local title = (frame.TitleContainer and frame.TitleContainer.TitleText) or frame.TitleText
			if title and title.SetFont then E:SetFont(title, self.db.titleSize) end
			Try(win.refresh, frame, db, true)
		end)
	else
		Try(win.refresh, frame, db, false)
	end
	if win.improve then Try(win.improve, frame, db, Active(win, "improve")) end
end

function M:SetupWindow(win)
	local frame = _G[win.frame]
	if not Usable(frame) then return end
	win.loaded = frame
	if not win.shownHook then
		win.shownHook = true
		frame:HookScript("OnShow", function()
			if not Skinned(win) or not Active(win, "skin") then return end
			-- Rows and pages created since the last pass get the look too.
			C_Timer.After(0, function() E:SkinRecord(RecordKey(win), frame, Kit.SkinTree, frame, win.tree) end)
		end)
	end
	self:ApplyWindow(win)
end

-- Start watching a window once its element is switched on.
function M:Watch(win)
	if win.watching then return end
	local state = E:BlizzardState(win.element)
	if not (state and state.enabled) then return end
	win.watching = true
	E:OnBlizzardAddOn(win.addon, function()
		if M.active then Try(M.SetupWindow, M, win) end
	end)
end

function M:ApplyElement(id)
	if not self.active then return end
	for _, win in ipairs(WINDOWS) do
		if win.element == id then
			self:Watch(win)
			if win.loaded then self:ApplyWindow(win) end
		end
	end
end

-- Back to Blizzard: the recorded skin comes off, the extras go.
function M:UndoElement(id)
	for _, win in ipairs(WINDOWS) do
		if win.element == id then
			E:SkinRecordOff(RecordKey(win))
			for part in pairs(win.parts or {}) do E:SkinRecordOff(RecordKey(win, part)) end
			if win.loaded then
				if win.improve then Try(win.improve, win.loaded, WDB(win.key), false) end
				Try(win.refresh, win.loaded, WDB(win.key), false)
			end
		end
	end
end

function M:Refresh()
	for _, win in ipairs(WINDOWS) do
		if win.loaded then
			Try(self.ApplyWindow, self, win)
		else
			self:Watch(win)
		end
	end
	Kit.UpdateSideTabs()
	-- The addon and debug tool looks (Modules/SkinsAddons.lua) follow too.
	for _, id in ipairs({ "ace3-config", "debug-tools" }) do
		if E:BlizzardAllowed(id, "skin") then E:SkinRecordOn(id) else E:SkinRecordOff(id) end
	end
end

for _, id in ipairs(ELEMENTS) do
	E:RegisterBlizzardHandler(id, {
		owner = "Skins",
		apply = function() M:ApplyElement(id) end,
		undo = function() M:UndoElement(id) end,
		-- The skin is recorded, so Skin off needs no reload.
		install = { skin = true, improve = true },
		-- v0.5.0 never touched these windows.
		legacy = function() return false end,
	})
end

function M:OnEnable()
	self:Refresh()
	local auction = E.modules.Auction
	if auction and auction.RegisterPriceListener then auction:RegisterPriceListener(recipeSummary, recipeSummary.Refresh) end
	local merchant = E.modules.Merchant
	if not recipeSummary.merchantHook and merchant and type(merchant.RecordPrices) == "function" then
		recipeSummary.merchantHook = true
		hooksecurefunc(merchant, "RecordPrices", function() if M.active then recipeSummary.Refresh() end end)
	end
	if E.Characters and E.Characters.RegisterCallback then
		E.Characters.RegisterCallback(recipeSummary, "Updated", function() recipeSummary.Refresh() end)
	end
	for _, event in ipairs({ "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "GET_ITEM_INFO_RECEIVED", "PLAYERBANKSLOTS_CHANGED" }) do
		pcall(self.RegisterEvent, self, event, function() recipeSummary.Refresh() end)
	end
	self:RegisterEvent("BAG_UPDATE_DELAYED", function()
		local frame = _G.ProfessionsFrame
		if Usable(frame) and frame:IsShown() and frame.CraftingPage then Try(UpdateReagents, frame.CraftingPage.SchematicForm); Try(recipeSummary.Update, frame.CraftingPage.SchematicForm) end
	end)
	pcall(self.RegisterEvent, self, "TRAINER_UPDATE", function() C_Timer.After(0, function() Try(UpdateTrainerExtras) end) end)
	self:RegisterEvent("PLAYER_MONEY", function()
		if Usable(_G.ClassTrainerFrame) and _G.ClassTrainerFrame:IsShown() then Try(UpdateTrainerExtras) end
	end)
	self:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION", function()
		recipeSummary.Refresh()
		if Usable(_G.ClassTrainerFrame) and _G.ClassTrainerFrame:IsShown() then Try(UpdateTrainerExtras) end
	end)
	pcall(self.RegisterEvent, self, "NEW_MOUNT_ADDED", function() Try(UpdateCollections) end)
	pcall(self.RegisterEvent, self, "INSPECT_READY", function()
		if inspect.hooked and Usable(_G.InspectFrame) and _G.InspectFrame:IsShown() then C_Timer.After(0, UpdateInspect) end
	end)
end

function M:OnDisable()
	local auction = E.modules.Auction
	if auction and auction.RegisterPriceListener then auction:RegisterPriceListener(recipeSummary, nil) end
	if E.Characters and E.Characters.UnregisterCallback then
		pcall(E.Characters.UnregisterCallback, recipeSummary, "Updated")
	end
	for form, panel in pairs(recipeSummary.states) do
		panel:Hide()
		if panel.launcher then panel.launcher:Hide() end
		if panel.window then panel.window:Hide() end
		panel.expanded = nil
	end
	for _, event in ipairs({ "BAG_UPDATE_DELAYED", "TRAINER_UPDATE", "PLAYER_MONEY", "INPUT_DEVICE_INTERFACE_TRANSITION", "NEW_MOUNT_ADDED", "INSPECT_READY",
		"TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "GET_ITEM_INFO_RECEIVED", "PLAYERBANKSLOTS_CHANGED" }) do
		pcall(self.UnregisterEvent, self, event)
	end
	for _, id in ipairs(ELEMENTS) do self:UndoElement(id) end
	E:SkinRecordOff("ace3-config")
	E:SkinRecordOff("debug-tools")
end

function M:OnProfileChanged()
	if self.active then self:Refresh() end
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local function ElementOff(id)
	return function()
		local state = E:BlizzardState(id)
		return not (state and state.enabled)
	end
end

local function Note(id)
	return { type = "description", hidden = function() return not ElementOff(id)() end,
		label = "Switched off on the Blizzard UI page, so this window stays Blizzard's own. Type /eui blizz %s on to turn it on.", labelFill = id }
end

M.options = {
	{ type = "tab", label = "General" },
	{ type = "description", label = "Each window here is a Blizzard element: turn it on under Blizzard UI and pick Skin, Move or Improve. These settings fine-tune the result." },
	{ type = "header", label = "Look" },
	{ type = "toggle", key = "transparent", label = "See-through windows", desc = "Skinned windows let the game show through a little. How much: General > Panel opacity." },
	{ type = "range", key = "titleSize", label = "Title text size", min = 12, max = 20, step = 1, desc = "Text size of skinned window titles." },
	{ type = "header", label = "Moving" },
	{ type = "execute", label = "Open Windows", desc = "Dragging, the mouse wheel scale and the resets for every Blizzard window are on the Move windows page.",
		func = function() E:ToggleConfig("windows") end },

	{ type = "tab", label = "Spellbook" },
	Note("player-spells"),
	{ type = "toggle", key = "windows.spells.skin", label = "Skin spellbook and talents", desc = "Panel, flat tabs, search box and buttons." },
	{ type = "toggle", dependsOn = "windows.spells.skin", key = "windows.spells.pageArt", label = "Keep the book and talent art", desc = "Keeps Blizzard's book pages and talent tree background inside the skinned window." },
	{ type = "toggle", disabled = E:BlizzardNeeds("player-spells", "improve"), key = "windows.spells.spellIDs", label = "Show spell IDs", desc = "Adds the spell ID to spell tooltips in the spellbook and talents. The Tooltip module's own Spell ID line takes over when it shows one." },

	{ type = "tab", label = "Professions" },
	Note("professions"),
	{ type = "execute", label = "Selected recipe summary", desc = "Open the current recipe summary in a resizable window when the profession window is crowded.", func = function()
		local frame = _G.ProfessionsFrame
		local form = frame and frame.CraftingPage and frame.CraftingPage.SchematicForm
		recipeSummary.Open(form)
	end, disabled = E:BlizzardNeeds("professions", "improve") },
	{ type = "toggle", disabled = E:BlizzardNeeds("professions", "improve"), key = "windows.professions.recipeSkill", label = "Recipe skill-up steps", desc = "Shows estimated skill-up thresholds for the selected recipe." },
	{ type = "toggle", disabled = E:BlizzardNeeds("professions", "improve"), key = "windows.professions.recipePrices", label = "Recipe cost and profit", desc = "Shows reagent costs and possible auction or vendor profit from your saved prices. Missing prices stay marked." },
	{ type = "toggle", disabled = E:BlizzardNeeds("professions", "improve"), key = "windows.professions.recipeCounts", label = "Crafts from your reagents", desc = "Shows how many crafts fit your bags, bank, and saved character inventories, with a button to list missing reagents." },
	{ type = "toggle", key = "windows.professions.skin", label = "Skin the professions window", desc = "Panel, side tabs, recipe list, search, filter and gear slots." },
	{ type = "toggle", disabled = E:BlizzardNeeds("professions", "improve"), key = "windows.professions.reagentCounts", label = "Reagents in your bank", desc = "Under each reagent: how many more wait in your bank." },
	{ type = "toggle", disabled = E:BlizzardNeeds("professions", "improve"), dependsOn = "windows.professions.reagentCounts", key = "windows.professions.reagentAlts", label = "Reagents on other characters", desc = "Also counts the reagent on your other characters, from the Bags module's inventory list." },

	{ type = "tab", label = "Trainer" },
	Note("class-trainer"),
	{ type = "toggle", key = "windows.trainer.skin", label = "Skin the trainer", desc = "Panel, flat rows, skill bar, filter and Train button." },
	{ type = "toggle", disabled = E:BlizzardNeeds("class-trainer", "improve"), key = "windows.trainer.costTotal", label = "Show the cost total", desc = "How many skills you can learn right now and what they cost together. You still train each one yourself." },
	{ type = "toggle", disabled = E:BlizzardNeeds("class-trainer", "improve"), key = "windows.trainer.serviceList", label = "Trainer list", desc = "A list beside the trainer with everything it teaches, now and at later levels, with rank, level and cost. With Training on, class trainers show that window instead." },
	{ type = "toggle", disabled = E:BlizzardNeeds("class-trainer", "improve"), dependsOn = "windows.trainer.serviceList", key = "windows.trainer.showKnown", label = "Include what you know", desc = "Also list skills you have already learned." },
	{ type = "toggle", disabled = E:BlizzardNeeds("class-trainer", "improve"), dependsOn = "windows.trainer.serviceList", key = "windows.trainer.hideIgnored", label = "Leave out ignored spells", desc = "Spells you ignored in the Training module (right-click a spell there) stay out of the trainer list.",
		requires = function() return E:GetModule("Training") ~= nil end },

	{ type = "tab", label = "Legacy" },
	Note("legacy-achievements"),
	{ type = "toggle", key = "windows.legacy.skin", label = "Skin the Legacy window", desc = "Legacy reward track, challenges and Legacy tree window." },
	{ type = "toggle", key = "windows.achievements.skin", label = "Skin achievement and challenge frames", desc = "Blizzard's achievement window where the game shows it." },

	{ type = "tab", label = "Collections" },
	Note("collections"),
	{ type = "toggle", key = "windows.collections.skin", label = "Skin collections", desc = "Mounts, pets, toys, heirlooms and appearances." },
	{ type = "toggle", disabled = E:BlizzardNeeds("collections", "improve"), key = "windows.collections.summary", label = "Collected summary", desc = "One line in the title bar with how many mounts, pets, toys and heirlooms you have." },

	{ type = "tab", label = "Socketing" },
	Note("item-socketing"),
	{ type = "toggle", key = "windows.socketing.skin", label = "Skin item socketing", desc = "The gem socketing window." },
	{ type = "toggle", key = "windows.interaction.skin", label = "Skin item interaction", desc = "Blizzard's item interaction window, where the game uses it." },

	{ type = "tab", label = "Dressing room" },
	Note("dressing-room"),
	{ type = "toggle", key = "windows.dressup.skin", label = "Skin the dressing room", desc = "Panel, buttons, set list and side preview." },
	{ type = "toggle", disabled = E:BlizzardNeeds("dressing-room", "improve"), key = "windows.dressup.buttons", label = "Undress and Target buttons", desc = "Two buttons on the preview: take everything off the model, or show your target's look. Blizzard's Reset button stays." },
	{ type = "toggle", disabled = E:BlizzardNeeds("dressing-room", "improve"), key = "windows.dressup.slotStrip", label = "Gear slots", desc = "A column of gear slots on the preview showing what it wears; click one to take just that piece off." },
	{ type = "toggle", disabled = E:BlizzardNeeds("dressing-room", "improve"), key = "windows.dressup.sheathe", label = "Sheathe button", desc = "A button that puts the preview's weapons away or draws them." },
	{ type = "toggle", disabled = E:BlizzardNeeds("dressing-room", "improve"), less = true, key = "windows.dressup.resizable", label = "Resizable", desc = "A grip in the bottom-right corner; the size is remembered." },
	{ type = "execute", less = true, label = "Reset dressing room size", desc = "Back to Blizzard's size.", func = function()
		WDB("dressup").size = false
		local frame = _G.DressUpFrame
		if Usable(frame) and type(frame.ConfigureSize) == "function" and not InCombatLockdown() then
			pcall(frame.ConfigureSize, frame, DressMinimized(frame))
		end
	end },

	{ type = "tab", label = "Inspect" },
	Note("inspect-frame"),
	{ type = "toggle", key = "windows.inspect.skin", label = "Skin the inspect window", desc = "Panel, tabs and buttons." },
	{ type = "toggle", key = "windows.inspect.slots", label = "Flat item slots", desc = "Item slots as flat boxes with an item quality border." },
	{ type = "select", dependsOn = "windows.inspect.skin", key = "windows.inspect.modelBackground", label = "Model background", desc = "What shows behind the inspected character: Blizzard's picture, or a plain backdrop in your art style's panel color. Default: plain.",
		values = { blizzard = "Blizzard's", dark = "Plain, in the art style's color" } },
	{ type = "toggle", disabled = E:BlizzardNeeds("inspect-frame", "improve"), key = "windows.inspect.itemLevel", label = "Item levels on slots", desc = "The item level of each item the inspected player wears." },
	{ type = "select", less = true, disabled = E:BlizzardNeeds("inspect-frame", "improve"), dependsOn = "windows.inspect.itemLevel", key = "windows.inspect.ilvlPosition", label = "Item level position", desc = "Where the number sits on the slot.",
		values = { TOP = "Top", CENTER = "Center", BOTTOM = "Bottom" } },
	{ type = "range", less = true, disabled = E:BlizzardNeeds("inspect-frame", "improve"), dependsOn = "windows.inspect.itemLevel", key = "windows.inspect.ilvlSize", label = "Item level text size", min = 8, max = 18, step = 1, desc = "Text size of the slot item levels." },
	{ type = "toggle", disabled = E:BlizzardNeeds("inspect-frame", "improve"), key = "windows.inspect.marks", label = "Gem and enchant marks", desc = "Small icons in the slot's corner: the enchant and each socketed gem, read from the item link." },
	{ type = "toggle", disabled = E:BlizzardNeeds("inspect-frame", "improve"), key = "windows.inspect.avgItemLevel", label = "Average item level", desc = "The inspected player's average item level, under the level line." },
}

---------------------------------------------------------------------------
-- Style presets
---------------------------------------------------------------------------
local function AllWindows(values)
	local windows = {}
	for _, win in ipairs(WINDOWS) do
		windows[win.key] = {}
		for key, value in pairs(values) do
			if M.defaults.windows[win.key][key] ~= nil then windows[win.key][key] = value end
		end
	end
	return windows
end

E:RegisterStyles("Skins", {
	{ key = "Modern", title = "Modern", desc = "Flat dark windows, no book art, every extra on.",
		settings = { transparent = false, titleSize = 16,
			windows = AllWindows({ skin = true, pageArt = false, reagentCounts = true, reagentAlts = true, costTotal = true,
				summary = true, buttons = true, resizable = true, itemLevel = true, avgItemLevel = true, slots = true,
				modelBackground = "dark" }) } },
	{ key = "Glass", title = "Glass", desc = "See-through panels with a larger title.",
		settings = { transparent = true, titleSize = 17,
			windows = AllWindows({ skin = true, pageArt = false, modelBackground = "dark" }) } },
	{ key = "Storybook", title = "Storybook", desc = "Skinned frames that keep Blizzard's book pages, talent art and model backgrounds.",
		settings = { transparent = false, titleSize = 16,
			windows = AllWindows({ skin = true, pageArt = true, modelBackground = "blizzard" }) } },
	{ key = "Minimal", title = "Minimal", desc = "The look only: no extra lines, counts or buttons.",
		settings = { transparent = false, titleSize = 15,
			windows = AllWindows({ skin = true, spellIDs = false, reagentCounts = false, reagentAlts = false, costTotal = false,
				recipeSkill = false, recipePrices = false, recipeCounts = false,
				summary = false, buttons = false, resizable = false, itemLevel = false, avgItemLevel = false, marks = false }) } },
	{ key = "Theorycrafter", title = "Theorycrafter", desc = "Every extra: spell IDs, reagents on alts, item levels and the trainer total.",
		settings = { transparent = false, titleSize = 16,
			windows = AllWindows({ skin = true, spellIDs = true, reagentCounts = true, reagentAlts = true, costTotal = true,
				recipeSkill = true, recipePrices = true, recipeCounts = true,
				summary = true, itemLevel = true, avgItemLevel = true, marks = true, ilvlSize = 13 }) } },
	{ key = "Compact", title = "Compact", desc = "Smaller titles and item level numbers. Window sizes are on the Move windows page.",
		settings = { titleSize = 14, windows = AllWindows({ skin = true, pageArt = false, ilvlSize = 11 }) } },
	{ key = "Blizzard", title = "Blizzard extras only", desc = "Blizzard's own look with EldoUI's extras on top.",
		settings = { transparent = false,
			windows = AllWindows({ skin = false, costTotal = true, reagentCounts = true, itemLevel = true, avgItemLevel = true,
				buttons = true, resizable = true, summary = true }) } },
})
