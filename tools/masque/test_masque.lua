-- Offline test for Masque on the Consumable Bar, the shaman totem and
-- cooldown bars and Quickdraw (review verbesserungen.md, C1).
-- Run from the repository root:
--   lua5.1 tools/masque/test_masque.lua
-- It loads EldoUI/Core/Masque.lua as it is and cuts the real code out of the
-- other files (between fixed markers, so a renamed part makes the test fail
-- instead of testing a stale copy): the box code of Core/Media.lua
-- (E:SetTemplate, E:DropTemplate, the theme and UI scale refreshes), the
-- Consumable Bar's CreateButton, the totem button (NewButton, PaintButton)
-- and Quickdraw's entry look. Around them: frames with backdrops and a model
-- of Masque's public API.
-- Checked: without Masque or with the switch off nothing changes; with both,
-- each button goes to its group with its parts, once, and loses EldoUI's box
-- for good (a repaint, the theme and a new UI scale don't bring it back);
-- other boxes are left alone; a failing Masque call keeps EldoUI's look; the
-- modules re-skin after sizing their buttons and offer the switch.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/masque/") or "./"

local function ReadFile(path)
	local file = assert(io.open(ROOT .. path, "rb"), "can't open " .. path)
	local text = file:read("*a")
	file:close()
	return (text:gsub("\r\n", "\n"))
end

-- The text from `first` up to (not including) `last`.
local function Between(text, first, last, where)
	local from = text:find(first, 1, true)
	assert(from, where .. ": marker not found: " .. first)
	local to = text:find(last, from + #first, true)
	assert(to, where .. ": end marker not found after " .. first .. ": " .. last)
	return text:sub(from, to - 1)
end

local media = ReadFile("EldoUI/Core/Media.lua")
local consumable = ReadFile("EldoUI/Modules/ConsumableBar.lua")
local totemBar = ReadFile("EldoUI/Modules/Totems/Bar.lua")
local totemCooldowns = ReadFile("EldoUI/Modules/Totems/Cooldowns.lua")
local quickdraw = ReadFile("EldoUI/Modules/Quickdraw.lua")
local totemOptions = ReadFile("EldoUI/Modules/Totems/Options.lua")

local mediaChunk = assert(loadstring(table.concat({
	"local E = ...",
	Between(media, "local themedBoxes = setmetatable", "-- Is the frame's size secret right now?", "Media.lua"),
	Between(media, "local waitingBoxes = setmetatable", "local function SamePath(a, b)", "Media.lua"),
	Between(media, "function E:SetTemplate(frame, transparent)", "-- A panel's background opacity", "Media.lua"),
	Between(media, "function E:RefreshTemplates()", "-- The edge size E:RefreshPixelEdges keeps", "Media.lua"),
}, "\n"), "=Media.lua parts"))
local masqueChunk = assert(loadstring(ReadFile("EldoUI/Core/Masque.lua"), "=Masque.lua"))
local consumableChunk = assert(loadstring(table.concat({
	"local E, M = ...",
	"local ShowTooltip = function() end",
	Between(consumable, "-- The Masque group of the buttons", "function M:BuildBar()", "ConsumableBar.lua"),
}, "\n"), "=ConsumableBar.lua parts"))
local totemChunk = assert(loadstring(table.concat({
	"local E, M = ...",
	Between(totemBar, "M.MASQUE_TOTEMS, M.MASQUE_COOLDOWNS", "local function KeyText(command)", "Totems/Bar.lua"),
}, "\n"), "=Totems/Bar.lua parts"))
local quickdrawChunk = assert(loadstring(table.concat({
	"local E, M = ...",
	Between(quickdraw, "-- The Masque group of the entries", "local function CreatePalette(menu)", "Quickdraw.lua"),
	"return SkinEntry",
}, "\n"), "=Quickdraw.lua parts"))

---------------------------------------------------------------------------
-- Frames, textures and backdrops
---------------------------------------------------------------------------
local Region = {}
Region.__index = Region
function Region:SetPoint(...) self.points = (self.points or 0) + 1 end
function Region:ClearAllPoints() self.points = 0 end
function Region:SetAllPoints() self.points = 1 end
function Region:SetTexCoord(...) self.coords = { ... } end
function Region:SetColorTexture(...) self.color = { ... } end
function Region:SetTexture(texture) self.texture = texture end
function Region:SetVertexColor(...) self.vertex = { ... } end
function Region:SetHeight() end
function Region:SetDrawLayer() end
function Region:SetAlpha() end
function Region:Hide() self.shown = false end
function Region:Show() self.shown = true end
function Region:SetDrawEdge() end
function Region:SetText() end
local function NewRegion(kind) return setmetatable({ kind = kind }, Region) end

local Frame = setmetatable({}, { __index = Region })
Frame.__index = Frame
function Frame:CreateTexture() return NewRegion("Texture") end
function Frame:SetPushedTexture(texture) self.pushedTexture = texture end
function Frame:RegisterForClicks() end
function Frame:SetAttribute(name, value) self.attributes[name] = value end
function Frame:HookScript() end
function Frame:SetScript() end
function Frame:GetFrameLevel() return 1 end
function Frame:GetWidth() return self.width end
function Frame:GetHeight() return self.height end
function Frame:SetSize(width, height) self.width, self.height = width, height end

local function NewFrame(kind, name)
	return setmetatable({ kind = kind, name = name, attributes = {}, width = 32, height = 32 }, Frame)
end

-- BackdropTemplateMixin as far as E:SetTemplate uses it.
BackdropTemplateMixin = {
	SetBackdrop = function(self, info)
		self.backdrop = info
		self.backdropInfo = info
		self.backdropSets = (self.backdropSets or 0) + 1
	end,
	GetBackdrop = function(self) return self.backdrop end,
	SetBackdropColor = function(self, r, g, b, a) self.bg = { r, g, b, a } end,
	GetBackdropColor = function(self) local c = self.bg or {} return c[1], c[2], c[3], c[4] end,
	SetBackdropBorderColor = function(self, r, g, b, a) self.border = { r, g, b, a } end,
	GetBackdropBorderColor = function(self) local c = self.border or {} return c[1], c[2], c[3], c[4] end,
}
function Mixin(target, source)
	for key, value in pairs(source) do target[key] = value end
	return target
end
function CopyTable(source)
	local copy = {}
	for key, value in pairs(source) do copy[key] = type(value) == "table" and CopyTable(value) or value end
	return copy
end
function CreateFrame(kind, name) return NewFrame(kind, name) end
function GameTooltip_Hide() end

---------------------------------------------------------------------------
-- Masque's public API: LibStub("Masque", true):Group(addon, group) and the
-- group's AddButton, RemoveButton and ReSkin.
---------------------------------------------------------------------------
local world

local function NewMasque(options)
	local masque = { groups = {}, groupCalls = 0 }
	function masque:Group(addon, name)
		self.groupCalls = self.groupCalls + 1
		if options.groupFails then error("no group") end
		local key = addon .. " > " .. name
		if not self.groups[key] then
			local group = { buttons = {}, adds = 0, reskins = 0 }
			function group:AddButton(button, parts, kind)
				if options.addFails then error("bad button") end
				self.adds = self.adds + 1
				self.buttons[button] = { parts = parts, kind = kind }
			end
			function group:ReSkin() self.reskins = self.reskins + 1 end
			self.groups[key] = group
		end
		return self.groups[key]
	end
	return masque
end

local function Setup(options)
	options = options or {}
	world = { masque = options.masque ~= false and NewMasque(options) or nil }
	LibStub = function(name, silent)
		assert(name == "Masque" and silent == true, "LibStub(\"Masque\", true)")
		return world.masque
	end
	local E = {
		pixel = 1,
		media = { flat = "flat", backdropColor = { 0.1, 0.1, 0.1, 0.8 }, borderColor = { 0, 0, 0, 1 },
			accentColor = { 1, 0.5, 0 } },
		tokens = { iconCoords = { 0.08, 0.92, 0.08, 0.92 }, size = { tiny = 8, small = 10 },
			hover = { hud = 0.2 }, pressed = 0.3, edge = { window = { 0.5, 0.5, 0.5, 1 } }, text = { body = { 1, 1, 1 } } },
		UIKit = { Chevron = function() return NewRegion("Chevron") end },
	}
	function E:EdgeSize() return self.pixel end
	function E:IsSecret() return false end
	function E:SizeIsSecret() return false end
	function E:SeeThroughAlpha(a) return a end
	function E:SeeThroughColor() return 0.1, 0.1, 0.1 end
	function E:PanelAlpha() return 0.8 end
	function E:RegisterEvent() end
	function E:TrimIcon(texture) texture:SetTexCoord(0.08, 0.92, 0.08, 0.92) return texture end
	function E:CreateText() return NewRegion("FontString") end
	function E:SetFont() end
	-- EldoUI's shared HUD button hover and pressed look (Core/Skin.lua,
	-- since 0.7.3000), as far as the buttons here use it.
	function E:SkinHudButton(button, area)
		area = area or button.icon or button
		local hover = button:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints(area)
		hover:SetColorTexture(1, 1, 1, self.tokens.hover.hud)
		local pressed = button:CreateTexture(nil, "OVERLAY")
		pressed:SetAllPoints(area)
		pressed:SetColorTexture(1, 0.5, 0, self.tokens.pressed)
		button:SetPushedTexture(pressed)
		button.hover, button.pushed = hover, pressed
		return hover, pressed
	end
	mediaChunk(E)
	masqueChunk(nil, E)
	return E
end

local function Group(name) return world.masque and world.masque.groups["EldoUI > " .. name] end
local function HasBox(frame) return frame.backdrop ~= nil end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
local passed, failed = 0, 0
local function Check(ok, what)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. what) end
end

-- Core: no Masque.
do
	local E = Setup({ masque = false })
	local button = NewFrame("Button")
	E:SetTemplate(button)
	Check(E:Masque() == nil, "no Masque: E:Masque() is nil")
	Check(E:MasqueButton("Consumable Bar", button, { Icon = {} }, "Item") == false, "no Masque: the button is not taken")
	Check(HasBox(button) and not E:Masqued(button) and not E:TemplateDropped(button), "no Masque: the box stays")
	Check(pcall(E.MasqueReSkin, E, "Consumable Bar"), "no Masque: a re-skin does nothing")
end

-- Core: Masque takes a button; the box goes for good.
do
	local E = Setup()
	local button, other = NewFrame("Button"), NewFrame("Frame")
	E:SetTemplate(button)
	E:SetTemplate(other)
	local parts = { Icon = NewRegion("Texture") }
	Check(E:MasqueButton("Totem Bar", button, parts, "Action") == true, "Masque takes the button")
	local group = Group("Totem Bar")
	Check(group and group.buttons[button] and group.buttons[button].parts == parts and group.buttons[button].kind == "Action",
		"the button is in group EldoUI > Totem Bar with its parts and type")
	Check(not HasBox(button) and E:Masqued(button) and E:TemplateDropped(button), "its box is gone")
	Check(E:MasqueButton("Totem Bar", button, parts, "Action") == true and group.adds == 1, "a second hand-over adds nothing")
	local second = NewFrame("Button")
	E:MasqueButton("Totem Bar", second, {}, "Action")
	Check(world.masque.groupCalls == 1 and group.adds == 2, "one group per name, made once")
	-- Repaint, theme, UI scale.
	E:SetTemplate(button)
	Check(not HasBox(button), "a module's repaint (E:SetTemplate) doesn't bring the box back")
	E.media.backdropColor = { 0.2, 0.2, 0.2, 0.9 }
	E:RefreshTemplates()
	Check(not HasBox(button), "a theme change doesn't bring the box back")
	Check(other.bg[1] == 0.2, "a theme change still repaints other boxes")
	local sets = other.backdropSets
	E.pixel = 2
	E:RefreshPixelEdges()
	Check(not HasBox(button), "a new UI scale doesn't bring the box back")
	Check(other.backdropSets == sets + 1 and other.backdrop.edgeSize == 2, "a new UI scale still re-edges other boxes")
	E:MasqueReSkin("Totem Bar")
	Check(group.reskins == 1, "E:MasqueReSkin re-skins the group")
	Check(pcall(E.MasqueReSkin, E, "Nothing"), "re-skinning an unknown group does nothing")
end

-- Core: Masque calls that fail keep EldoUI's look.
do
	local E = Setup({ addFails = true })
	local button = NewFrame("Button")
	E:SetTemplate(button)
	Check(E:MasqueButton("Quickdraw", button, {}, "Action") == false, "failing AddButton: not taken")
	Check(HasBox(button) and not E:Masqued(button), "failing AddButton: the box stays")
	E = Setup({ groupFails = true })
	button = NewFrame("Button")
	E:SetTemplate(button)
	Check(E:MasqueButton("Quickdraw", button, {}, "Action") == false and HasBox(button), "failing Group: not taken, box stays")
end

-- Consumable Bar.
for _, on in ipairs({ false, true }) do
	local E = Setup()
	local M = { db = { masque = on }, bar = NewFrame("Frame") }
	function M:TogglePicker() end
	consumableChunk(E, M)
	local button = M:CreateButton({ key = "food" }, 1)
	local group = Group("Consumable Bar")
	if on then
		local entry = group and group.buttons[button]
		Check(entry and entry.kind == "Item", "Consumable Bar: in its group as an item button")
		Check(entry and entry.parts.Icon == button.icon and entry.parts.Cooldown == button.cooldown and entry.parts.Count == button.count
			and entry.parts.Highlight == button.hover and button.hover ~= nil, "Consumable Bar: icon, cooldown, count and hover go to Masque")
		Check(not HasBox(button), "Consumable Bar: no EldoUI box")
	else
		Check(group == nil and HasBox(button), "Consumable Bar, switch off: no Masque, box stays")
	end
end

-- Totem and cooldown bars: the shared button and its repaint.
for _, on in ipairs({ false, true }) do
	local E = Setup()
	local M = { db = { masque = on } }
	totemChunk(E, M)
	Check(M.MASQUE_TOTEMS == "Totem Bar" and M.MASQUE_COOLDOWNS == "Shaman Cooldowns", "Totems: group names")
	local totem = M.NewButton(NewFrame("Frame"), "EldoUI_TotemButton1", "SecureActionButtonTemplate", M.MASQUE_TOTEMS)
	local cooldown = M.NewButton(NewFrame("Frame"), "EldoUI_ShamanCooldown1", "SecureActionButtonTemplate", M.MASQUE_COOLDOWNS)
	local plain = M.NewButton(NewFrame("Frame"), "Plain", "SecureActionButtonTemplate")
	if on then
		local entry = Group("Totem Bar") and Group("Totem Bar").buttons[totem]
		Check(entry and entry.kind == "Action" and entry.parts.Icon == totem.icon and entry.parts.HotKey == totem.hotkey
			and entry.parts.Count == totem.count and entry.parts.Cooldown == totem.cooldown, "Totems: the totem button with its parts")
		Check(entry and entry.parts.Pushed == nil and totem.pushedTexture == totem.pushed, "Totems: the pressed look stays EldoUI's")
		Check(entry and entry.parts.Highlight == totem.hover and totem.hover ~= nil, "Totems: the hover goes to Masque")
		Check(Group("Shaman Cooldowns") and Group("Shaman Cooldowns").buttons[cooldown], "Totems: the cooldown bar has its own group")
		Check(not E:Masqued(plain) and HasBox(plain), "Totems: a button without a group stays EldoUI's")
		M.PaintButton(totem)
		Check(not HasBox(totem), "Totems: PaintButton keeps the box off")
	else
		Check(Group("Totem Bar") == nil and HasBox(totem) and HasBox(cooldown), "Totems, switch off: no Masque, boxes stay")
	end
end

-- Quickdraw entries.
for _, on in ipairs({ false, true }) do
	local E = Setup()
	local M = { db = { masque = on } }
	local SkinEntry = quickdrawChunk(E, M)
	local button = NewFrame("Button")
	SkinEntry(button)
	local group = Group("Quickdraw")
	if on then
		local entry = group and group.buttons[button]
		Check(entry and entry.parts.Icon == button.icon and entry.parts.Cooldown == button.cooldown and entry.kind == "Action",
			"Quickdraw: the entry with icon and cooldown")
		Check(not HasBox(button) and button.label and button.selected and button.subMark, "Quickdraw: no box; label, glow and chevron stay")
	else
		Check(group == nil and HasBox(button), "Quickdraw, switch off: no Masque, box stays")
	end
end

-- The modules re-skin once their buttons have a size, and offer the switch.
local function Has(text, first, last, needle, what)
	Check(Between(text, first, last, what):find(needle, 1, true) ~= nil, what)
end
Has(consumable, "function M:ApplySecure()", "-- Events and lifecycle", "E:MasqueReSkin(MASQUE_GROUP)", "Consumable Bar re-skins after sizing")
Has(totemBar, "function Bar:Apply()", "function Bar:Update()", "E:MasqueReSkin(M.MASQUE_TOTEMS)", "totem bar re-skins after sizing")
Has(totemCooldowns, "function CD:Apply()", "function CD:Update()", "E:MasqueReSkin(M.MASQUE_COOLDOWNS)", "cooldown bar re-skins after sizing")
Has(quickdraw, "local function FillPalette(", "\nend\n", "E:MasqueReSkin(MASQUE_GROUP)", "Quickdraw re-skins after sizing a palette")
for name, text in pairs({ ConsumableBar = consumable, Totems = totemOptions, Quickdraw = quickdraw }) do
	Check(text:find('key = "masque", label = "Use Masque", reload = true, desc = E.MASQUE_OPTION_DESC', 1, true) ~= nil,
		name .. ": offers the \"Use Masque\" switch (after a reload)")
end
Check(totemBar:find('"Totem Bar"', 1, true) and totemCooldowns:find("M.MASQUE_COOLDOWNS", 1, true), "Totems: both bars pass their group")

print(("%d checks passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
