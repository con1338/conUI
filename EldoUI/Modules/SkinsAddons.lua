-- EldoUI Window Skins: other addons' Ace3 option windows and Blizzard's
-- debug tools in the EldoUI look. Part of the Window Skins module;
-- each has its own Blizzard UI element, so nothing changes until the
-- player turns it on:
--   ace3-config   every AceGUI-3.0 window and widget another addon opens
--                 (AceConfigDialog option windows): panels, tree and tab groups,
--                 buttons, check boxes, sliders, dropdowns, edit boxes,
--                 color swatches, headings and scroll bars.
--   debug-tools   the frame stack tooltip (/fstack), the table inspector
--                 (/tinspect) and the event trace window (/etrace).
--
-- Rules: other addons' widgets are only post-hooked (hooksecurefunc on
-- AceGUI's RegisterAsWidget / RegisterAsContainer and on single widget
-- methods); no function of theirs is ever replaced. AceGUI versions EldoUI
-- does not know are left alone (version guard), so a library update can't
-- break another addon. Each widget is styled through Core/Skin.lua and
-- E.WindowKit and only once (weak tables). What the look changes is
-- recorded (E:SkinRecord), so switching it off puts every widget back at
-- once, without a reload.
-- Written from scratch for EldoUI; no code or media from other addons.
local _, E = ...

local M = E:GetModule("Skins")
local Kit = E.WindowKit

local ACE = "ace3-config"
local DEBUG = "debug-tools"

-- AceGUI-3.0 minor versions whose widgets were checked (Ace3 releases up
-- to r1349). Anything newer is skipped until it is checked.
local ACE_MIN, ACE_MAX = 30, 41

local done = setmetatable({}, { __mode = "k" })   -- widget or frame -> true once styled

local function Usable(frame)
	return Kit and Kit.Usable(frame)
end

local function Try(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then geterrorhandler()(err) end
end

---------------------------------------------------------------------------
-- Small helpers on frames that belong to other addons
---------------------------------------------------------------------------
-- A frame with its own BackdropTemplate backdrop: the EldoUI flat box.
local function Flat(frame, transparent)
	if not Usable(frame) or done[frame] then return end
	done[frame] = true
	E:SkinCapture(frame)
	if frame.SetBackdrop then
		E:SetTemplate(frame, transparent)
	else
		Kit.Box(frame, transparent)
	end
end

local function AccentHighlight(texture, alpha)
	if texture and texture.SetColorTexture then
		texture:SetTexture(E.media.flat)
		E:AccentTexture(texture, alpha or 0.25)
	end
end

-- Children of a frame that are plain panel buttons or close buttons.
local function SkinChildButtons(frame)
	for _, child in ipairs({ frame:GetChildren() }) do
		if Usable(child) and child:IsObjectType("Button") then
			local text = child.GetFontString and child:GetFontString()
			local width = child:GetWidth() or 0
			if text and (child.Left or child.Middle) then
				E:SkinButton(child)
			elseif not text and width > 0 and width <= 34 and child.GetNormalTexture and child:GetNormalTexture() then
				E:SkinCloseButton(child)
			end
		end
	end
end

---------------------------------------------------------------------------
-- AceGUI widgets, by type
---------------------------------------------------------------------------
local Ace = {}

function Ace.Frame(widget)
	local frame = widget.frame
	E:SkinPanel(frame, { accentOffset = 30, close = false, title = false })
	if widget.titletext then
		E:SetFont(widget.titletext, E.tokens.size.cardTitle)
		widget.titletext:SetTextColor(1, 1, 1)
	end
	if widget.statustext then E:SetFont(widget.statustext, E.tokens.size.label) end
	for _, child in ipairs({ frame:GetChildren() }) do
		-- The status line under the content has its own backdrop.
		if Usable(child) and child.SetBackdrop and child ~= widget.content then Flat(child, true) end
	end
	SkinChildButtons(frame)
end
Ace.Window = Ace.Frame

function Ace.TreeGroup(widget)
	Flat(widget.treeframe, true)
	Flat(widget.border, true)
	if widget.scrollbar then E:SkinScrollBar(widget.scrollbar) end
	if type(widget.RefreshTree) == "function" then
		local function SkinTreeButton(button)
			done[button] = true
			local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
			AccentHighlight(highlight, 0.2)
			if button.text then E:SetFont(button.text, E.tokens.size.label) end
		end
		hooksecurefunc(widget, "RefreshTree", function(self)
			for _, button in ipairs(self.buttons or {}) do
				if Usable(button) and not done[button] then E:SkinRecord(ACE, button, SkinTreeButton, button) end
			end
		end)
	end
end

function Ace.TabGroup(widget)
	Flat(widget.border, true)
	local function SkinTabs(self)
		local list = {}
		for _, tab in ipairs(self.tabs or {}) do list[#list + 1] = tab end
		if #list > 0 then E:SkinTabs(list, { isSelected = function(tab) return tab.selected end, size = 12 }) end
	end
	if type(widget.BuildTabs) == "function" then
		hooksecurefunc(widget, "BuildTabs", function(self) E:SkinRecord(ACE, self.frame, SkinTabs, self) end)
	end
	if type(widget.SelectTab) == "function" then hooksecurefunc(widget, "SelectTab", function() E:UpdateTabs() end) end
	SkinTabs(widget)
end

local function GroupBorder(widget)
	local content = widget.content
	local border = content and content.GetParent and content:GetParent()
	if border and border ~= widget.frame then Flat(border, true) end
	if widget.titletext then E:SetFont(widget.titletext, E.tokens.size.section) end
end
Ace.InlineGroup = GroupBorder

function Ace.DropdownGroup(widget)
	GroupBorder(widget)
	Flat(widget.border, true)
end

function Ace.ScrollFrame(widget)
	if widget.scrollbar then E:SkinScrollBar(widget.scrollbar) end
end

function Ace.Button(widget)
	E:SkinButton(widget.frame)
end

function Ace.CheckBox(widget)
	local bg, check = widget.checkbg, widget.check
	if not (bg and check) then return end
	local box = CreateFrame("Frame", nil, widget.frame)
	box:SetPoint("TOPLEFT", bg, "TOPLEFT", 4, -4)
	box:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -4, 4)
	box:SetFrameLevel(math.max(widget.frame:GetFrameLevel(), 1))
	E:SetTemplate(box)
	local function Restyle(self)
		self.checkbg:SetAlpha(0)
		self.check:SetTexture(E.media.flat)
		self.check:ClearAllPoints()
		self.check:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
		self.check:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
		E:AccentTexture(self.check, 1)
		if self.highlight then
			self.highlight:SetTexture(E.media.flat)
			self.highlight:SetVertexColor(1, 1, 1, 0.12)
			self.highlight:ClearAllPoints()
			self.highlight:SetAllPoints(box)
		end
	end
	Restyle(widget)
	-- Ace sets its textures again for radio buttons and on every reuse.
	if type(widget.SetType) == "function" then
		hooksecurefunc(widget, "SetType", function(self) E:SkinRecord(ACE, self.frame, Restyle, self) end)
	end
end

function Ace.Slider(widget)
	local slider = widget.slider
	if Usable(slider) then
		Flat(slider, true)
		local thumb = slider.GetThumbTexture and slider:GetThumbTexture()
		if thumb then
			thumb:SetTexture(E.media.flat)
			thumb:SetSize(8, 14)
			E:AccentTexture(thumb, 1)
		end
	end
	if widget.editbox then Flat(widget.editbox, true) end
end

function Ace.Dropdown(widget)
	if widget.dropdown then E:SkinDropdown(widget.dropdown) end
	local pullout = widget.pullout
	if type(pullout) == "table" and pullout.frame then Flat(pullout.frame) end
end

function Ace.EditBox(widget)
	if widget.editbox then E:SkinEditBox(widget.editbox) end
	if widget.button then E:SkinButton(widget.button) end
end

function Ace.MultiLineEditBox(widget)
	Flat(widget.scrollBG, true)
	if widget.button then E:SkinButton(widget.button) end
	local bar = widget.scrollBar or widget.scrollbar
	if bar then E:SkinScrollBar(bar) end
end

function Ace.Keybinding(widget)
	if widget.button then E:SkinButton(widget.button) end
	Flat(widget.msgframe)
end

function Ace.ColorPicker(widget)
	local swatch = widget.colorSwatch
	if not swatch then return end
	local box = CreateFrame("Frame", nil, widget.frame)
	box:SetPoint("TOPLEFT", swatch, "TOPLEFT", -E.pixel, E.pixel)
	box:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", E.pixel, -E.pixel)
	box:SetFrameLevel(math.max(widget.frame:GetFrameLevel() - 1, 0))
	E:SetTemplate(box)
	box:SetBackdropColor(0, 0, 0, 0)
	swatch:SetTexture(E.media.flat)
end

function Ace.Heading(widget)
	for _, line in ipairs({ widget.left, widget.right }) do
		if line and line.SetTexture then
			line:SetTexture(E.media.flat)
			line:SetHeight(E.pixel)
			E:AccentTexture(line, 0.5)
		end
	end
	if widget.label then E:SetFont(widget.label, E.tokens.size.body) end
end

---------------------------------------------------------------------------
-- AceGUI hooks
---------------------------------------------------------------------------
local ace = { lib = nil, minor = nil, hooked = {}, skinned = 0, skipped = nil }

local function SkinWidget(widget)
	if type(widget) ~= "table" or done[widget] then return end
	if not (M.active and E:BlizzardAllowed(ACE, "skin")) then return end
	local fn = Ace[widget.type]
	if not fn or not Usable(widget.frame) then return end
	done[widget] = true
	ace.skinned = ace.skinned + 1
	E:SkinRecord(ACE, widget.frame, fn, widget)
end

local function HookAce()
	if not (M.active and E:BlizzardAllowed(ACE, "skin")) then return end
	if not LibStub then return end
	local lib, minor = LibStub("AceGUI-3.0", true)
	if not lib then return end
	ace.lib, ace.minor = lib, minor
	if type(minor) ~= "number" or minor < ACE_MIN or minor > ACE_MAX then
		ace.skipped = minor
		return
	end
	ace.skipped = nil
	-- A newer copy of the library replaces these functions; hook each copy once.
	for _, method in ipairs({ "RegisterAsWidget", "RegisterAsContainer" }) do
		local current = lib[method]
		if type(current) == "function" and ace.hooked[method] ~= current then
			hooksecurefunc(lib, method, function(_, widget) SkinWidget(widget) end)
			ace.hooked[method] = lib[method]
		end
	end
end

-- Another addon may bring AceGUI (or a newer copy) at any time.
local aceWatch = {}
local function WatchAce()
	if aceWatch.on then return end
	aceWatch.on = true
	E:RegisterEvent("ADDON_LOADED", function() HookAce() end, aceWatch)
end

E:RegisterBlizzardHandler(ACE, {
	owner = "Skins",
	apply = function(state)
		if not state.skin then
			E:SkinRecordOff(ACE)
			return
		end
		E:SkinRecordOn(ACE)
		WatchAce()
		HookAce()
	end,
	undo = function() E:SkinRecordOff(ACE) end,
	legacy = function() return false end,
})

function M:AceSkinLines()
	local line
	if not ace.lib then
		line = "AceGUI-3.0: not loaded by any addon"
	elseif ace.skipped then
		line = ("AceGUI-3.0 minor %s: not skinned (EldoUI knows %d-%d)"):format(tostring(ace.skipped), ACE_MIN, ACE_MAX)
	else
		line = ("AceGUI-3.0 minor %s: %d widgets skinned"):format(tostring(ace.minor), ace.skinned)
	end
	return { "   " .. line }
end

E:RegisterDiagnostics("Ace3 skin", function() return M:AceSkinLines() end)

-- For plugins: skin a widget table as AceGUI would hand it over.
M.SkinAceWidget = SkinWidget

---------------------------------------------------------------------------
-- Debug tools
---------------------------------------------------------------------------
local function DebugOn()
	return M.active and E:BlizzardAllowed(DEBUG, "skin")
end

-- The frame stack tooltip: a flat panel behind, Blizzard's border hidden
-- each time it shows (Blizzard picks a tooltip style on show).
local stackBox
local function SkinFrameStack()
	local tip = _G.FrameStackTooltip
	if not Usable(tip) or done[tip] then return end
	done[tip] = true
	stackBox = CreateFrame("Frame", nil, tip)
	stackBox:SetAllPoints()
	stackBox:SetFrameLevel(math.max(tip:GetFrameLevel() - 1, 0))
	E:SetPanelTemplate(stackBox)
	local function Hide9()
		if tip.NineSlice then tip.NineSlice:SetAlpha(0) end
	end
	Hide9()
	tip:HookScript("OnShow", function()
		if DebugOn() then E:SkinRecord(DEBUG, tip, Hide9) end
	end)
end

local function SkinInspector(frame)
	if not Usable(frame) or done[frame] then return end
	done[frame] = true
	E:SkinPanel(frame, { accentOffset = 26 })
	if frame.TitleButton and frame.TitleButton.Text then E:SetFont(frame.TitleButton.Text, E.tokens.size.body) end
	for _, key in ipairs({ "VisibilityButton", "HighlightButton", "DynamicUpdateButton" }) do
		local check = frame[key]
		if Usable(check) then
			E:SkinCheckBox(check)
			if check.Label then E:SetFont(check.Label, E.tokens.size.label) end
		end
	end
	if frame.FilterBox then E:SkinEditBox(frame.FilterBox) end
	local scroll = frame.LinesScrollFrame
	if scroll and scroll.ScrollBar then E:SkinScrollBar(scroll.ScrollBar) end
	local art = frame.ScrollFrameArt
	if Usable(art) then
		E:StripTextures(art)
		Kit.Box(art, true)
	end
end

local inspectorHooked = false
local function SkinDebugTools()
	if not DebugOn() then return end
	E:SkinRecord(DEBUG, _G.FrameStackTooltip, SkinFrameStack)
	E:SkinRecord(DEBUG, _G.TableAttributeDisplay, SkinInspector, _G.TableAttributeDisplay)
	-- Inspectors opened later come from a pool built on this mixin.
	local mixin = _G.TableInspectorMixin
	if not inspectorHooked and type(mixin) == "table" and type(mixin.InspectTable) == "function" then
		inspectorHooked = true
		hooksecurefunc(mixin, "InspectTable", function(self)
			if DebugOn() then E:SkinRecord(DEBUG, self, SkinInspector, self) end
		end)
	end
end

local function SkinEventTrace()
	local frame = _G.EventTrace
	if not (DebugOn() and Usable(frame)) or done[frame] then return end
	done[frame] = true
	E:SkinRecord(DEBUG, frame, function()
		Kit.SkinWindow(frame)
		Kit.SkinTree(frame, { depth = 8 })
	end)
end

E:RegisterBlizzardHandler(DEBUG, {
	owner = "Skins",
	apply = function(state)
		if not state.skin then
			E:SkinRecordOff(DEBUG)
			return
		end
		E:SkinRecordOn(DEBUG)
		E:OnBlizzardAddOn("Blizzard_DebugTools", SkinDebugTools)
		E:OnBlizzardAddOn("Blizzard_EventTrace", SkinEventTrace)
	end,
	undo = function() E:SkinRecordOff(DEBUG) end,
	legacy = function() return false end,
})
