-- EldoUI micro menu and bag bar.
--
-- Blizzard's own micro buttons and bag buttons stay in charge (they open
-- the right windows, follow game rules, show alerts and Forever's keyring);
-- EldoUI only changes where they sit and how they look. Two Blizzard UI
-- elements decide what EldoUI may do:
--
--   "micro-menu"  skin     flat boxes instead of the round button art
--                 move     EldoUI_MicroMenu mover: rows, spacing, size, growth
--                          direction, visibility rules, single buttons hidden
--                 hide     the micro menu hidden (keybinds keep working)
--                 replace  hidden, with the "Menu" datatext on the Info Bar instead
--   "bag-bar"     skin     flat slots
--                 move     EldoUI_BagBar mover: size, spacing, direction, only backpack,
--                          keyring button, visibility rules
--                 hide     the bag bar hidden
--                 replace  the bag buttons docked on top of EldoUI's bag window
--
-- How it stays out of Blizzard's way: the micro menu frame (MicroMenu) is
-- re-parented into an EldoUI holder, so Blizzard's MicroMenuContainer keeps
-- its size and Blizzard's action bar 1, which Forever anchors to that
-- container, never moves. Blizzard's own layout runs as before; a
-- hooksecurefunc on it places the buttons in EldoUI's grid afterwards.
-- Vehicles take the micro menu onto their bar (Blizzard's
-- OverrideMicroMenuPosition); EldoUI waits and takes it back afterwards.
-- Nothing here is a secure frame, but every change still runs out of combat.
-- Fading uses the shared visibility block (Core/Visibility.lua): the same
-- presets and rules as every other EldoUI frame, on EldoUI's own holders.
local _, E = ...
local L = E.L

local MICRO, BAGS = "micro-menu", "bag-bar"

local M = E:NewModule("MicroMenu", {
	title = "Micro Menu and Bag Bar",
	aliases = { "Micro Menu and Bags" }, -- earlier title, for search and /eui
	desc = "Move, resize and restyle Blizzard's micro menu and bag bar, or fold them into the Info Bar and bag window.",
	category = "Interface",
	frames = { "EldoUI_MicroMenu", "EldoUI_BagBar" },
	movers = { "EldoUI_MicroMenu", "EldoUI_BagBar" },
	blizzard = { "micro-menu", "bag-bar" },
	savedKeys = { "profile.modules.MicroMenu" },
	optionsPage = "module:MicroMenu",
	presets = { "Block", "Hover", "Large", "Minimal", "Strip" },
	defaults = {
		micro = {
			scale = 80,         -- percent of Blizzard's size (v0.7 and older: 0.4-1.5)
			perRow = 14,
			spacing = 2,
			growth = "rightDown", -- rightDown | leftDown | rightUp | leftUp
			visibility = E:VisibilityDefaults(),
			hide = {},          -- [button name] = true
			menuAdded = false,  -- the Menu datatext was put on the Info Bar once
		},
		bags = {
			scale = 70,         -- percent of Blizzard's 45 px buttons (v0.7 and older: `size` in pixels)
			spacing = 3,
			vertical = false,
			reverse = false,    -- backpack last instead of first
			onlyBackpack = false,
			keyring = true,
			freeSlots = "blizzard", -- blizzard (leave the game setting), show, hide
			visibility = E:VisibilityDefaults(),
		},
	},
})

-- Blizzard's micro buttons on Forever, in Blizzard's order
-- (Blizzard_MicroMenu/Camelot/MicroMenuContainerOverrides.lua).
local MICRO_BUTTONS = {
	{ "CharacterMicroButton", E.Key("Character") },
	{ "ProfessionMicroButton", E.Key("Professions") },
	{ "SpellbookMicroButton", E.Key("Spellbook") },
	{ "TalentMicroButton", E.Key("Talents") },
	{ "LegacyMicroButton", E.Key("Legacy") },
	{ "QuestLogMicroButton", E.Key("Quest log") },
	{ "HousingMicroButton", E.Key("Housing") },
	{ "GuildMicroButton", E.Key("Guild and communities") },
	{ "LFDMicroButton", E.Key("Group finder") },
	{ "CollectionsMicroButton", E.Key("Collections") },
	{ "EJMicroButton", E.Key("Adventure guide") },
	{ "HelpMicroButton", E.Key("Help") },
	{ "StoreMicroButton", E.Key("Shop") },
	{ "MainMenuMicroButton", E.Key("Game menu") },
}

-- The core's hidden parent (Core/Blizzard.lua). The micro menu itself is
-- not kept there by force: Blizzard moves it onto the vehicle bar and back
-- (ResetMicroMenuPosition, hooked below), and that must keep working.
local hider = E.BlizzardKeep.hider
local Keep = E.BlizzardKeep

---------------------------------------------------------------------------
-- Remember where Blizzard had a frame, to put it back.
---------------------------------------------------------------------------
local saved = {}

local function Remember(frame)
	if saved[frame] then return end
	local points = {}
	for index = 1, frame:GetNumPoints() do points[index] = { frame:GetPoint(index) } end
	saved[frame] = { parent = frame:GetParent(), points = points, scale = frame:GetScale() }
end

-- Plain widget methods (SetPointBase ... on the Edit Mode systems), so
-- Edit Mode's overrides never run from EldoUI.
local function Restore(frame)
	local state = saved[frame]
	if not state then return end
	saved[frame] = nil
	E:UnhideBlizzardFrame(frame, state.parent)
	frame:SetParent(state.parent)
	Keep.SetScale(frame, state.scale)
	Keep.ClearAllPoints(frame)
	for _, point in ipairs(state.points) do Keep.SetPoint(frame, unpack(point)) end
end

local function Usable(frame)
	return frame and not E.FrameCheck(frame, "IsForbidden")
end

-- While EldoUI's holder carries the buttons, Blizzard's bar is an empty
-- shell at its old place: Edit Mode drops its box there (Modules/EditMode.lua).
local function StandIn(id, holder)
	if E.SetEditModeStandIn then E:SetEditModeStandIn(id, holder) end
end

---------------------------------------------------------------------------
-- Skin helpers: Blizzard art goes to alpha 0, EldoUI boxes are our own
-- child frames (Core/Skin.lua rules: no fields written into Blizzard frames).
---------------------------------------------------------------------------
local boxes = {}       -- Blizzard button -> { bd, hover }
local alphaZero = {}   -- Blizzard region -> true while EldoUI keeps it invisible

local function Fade(region)
	if region and region.SetAlpha then
		alphaZero[region] = true
		region:SetAlpha(0)
	end
end

local function Box(button)
	local parts = boxes[button]
	if not parts then
		parts = {}
		parts.bd = CreateFrame("Frame", nil, button)
		parts.bd:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
		parts.hover = button:CreateTexture(nil, "HIGHLIGHT")
		parts.hover:SetPoint("TOPLEFT", E.pixel, -E.pixel)
		parts.hover:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
		E:AccentTexture(parts.hover, 0.2)
		boxes[button] = parts
	end
	E:SetTemplate(parts.bd, true)
	parts.bd:Show()
	parts.hover:Show()
	return parts
end

local function Unbox(button)
	local parts = boxes[button]
	if parts then
		parts.bd:Hide()
		parts.hover:Hide()
	end
end

local function UnfadeAll()
	for region in pairs(alphaZero) do region:SetAlpha(1) end
	wipe(alphaZero)
end

local function Unfade(region)
	if region and alphaZero[region] then
		alphaZero[region] = nil
		region:SetAlpha(1)
	end
end

---------------------------------------------------------------------------
-- Vanilla Original: the game's own classic micro buttons and bag slots
-- (E:SetOriginalArt, Core/Media.lua) on the buttons the classic client had,
-- for a skin that draws the original art. The client's own art of those
-- buttons is faded; buttons the classic client never had keep the client's
-- look. Our own textures on the button (no fields written into Blizzard
-- frames); a missing client file draws the skin's material instead.
---------------------------------------------------------------------------
local CLASSIC_MICRO = {
	CharacterMicroButton = "character", SpellbookMicroButton = "spellbook", TalentMicroButton = "talents",
	QuestLogMicroButton = "quest", GuildMicroButton = "socials", HelpMicroButton = "help", MainMenuMicroButton = "mainmenu",
}
M.CLASSIC_MICRO = CLASSIC_MICRO -- exposed for inspection
local classic = {} -- Blizzard button -> { art, glow, portrait, pushed, slot, on, down }

local function OriginalOn()
	return E.OriginalArtSkin and E:OriginalArtSkin(E:SkinPart()) or false
end
M.OriginalOn = OriginalOn

local function ClientArt(button)
	return { button.Background, button.PushedBackground, button.Shadow, button.PushedShadow, button:GetNormalTexture(),
		button:GetPushedTexture(), button.GetDisabledTexture and button:GetDisabledTexture(), button:GetHighlightTexture() }
end

-- The state a classic button shows: up, down (pressed, or its window open)
-- or disabled.
local function ClassicState(button)
	local parts = classic[button]
	if not (parts and parts.on and parts.micro) then return end
	local state = "up"
	if button.IsEnabled and not button:IsEnabled() then
		state = "disabled"
	elseif parts.down or (button.GetButtonState and button:GetButtonState() == "PUSHED") then
		state = "down"
	end
	E:SetOriginalArt(parts.art, ("micro-%s-%s"):format(parts.slot, state))
	if parts.portrait then
		local shade = state == "up" and 1 or 0.5
		parts.portrait:SetVertexColor(shade, shade, shade)
	end
end

local function HookClassic(button, parts, update)
	if parts.hooked then return end
	parts.hooked = true
	button:HookScript("OnMouseDown", function(b) if classic[b] then classic[b].down = true update(b) end end)
	button:HookScript("OnMouseUp", function(b) if classic[b] then classic[b].down = false update(b) end end)
	button:HookScript("OnEnable", update)
	button:HookScript("OnDisable", update)
	if button.SetButtonState then hooksecurefunc(button, "SetButtonState", update) end
end

local function ClassicMicro(button, slot)
	local parts = classic[button]
	if not parts then
		parts = { slot = slot, micro = true }
		parts.art = button:CreateTexture(nil, "BORDER")
		parts.art:SetAllPoints()
		parts.glow = button:CreateTexture(nil, "HIGHLIGHT")
		parts.glow:SetAllPoints()
		if slot == "character" then
			-- The classic button framed your portrait.
			parts.portrait = button:CreateTexture(nil, "ARTWORK")
			parts.portrait:SetTexCoord(0.2, 0.8, 0.0666, 0.9)
		end
		classic[button] = parts
		HookClassic(button, parts, ClassicState)
	end
	for _, region in ipairs(ClientArt(button)) do Fade(region) end
	parts.on = true
	E:SetOriginalArt(parts.glow, "micro-highlight")
	parts.art:Show()
	parts.glow:Show()
	if parts.portrait then
		local width, height = button:GetSize()
		parts.portrait:ClearAllPoints()
		parts.portrait:SetPoint("TOP", button, "TOP", 0, -height * 5 / 37)
		parts.portrait:SetSize(width * 18 / 29, height * 25 / 37)
		if SetPortraitTexture then pcall(SetPortraitTexture, parts.portrait, "player") end
		parts.portrait:Show()
	end
	ClassicState(button)
end

-- The classic bag slot: the round stone frame round the icon, its pressed
-- and hover looks; the key ring its own up, down and hover art.
local function BagState(button)
	local parts = classic[button]
	if not (parts and parts.on and not parts.micro) then return end
	if parts.key then
		E:SetOriginalArt(parts.art, parts.down and "keyring-down" or "keyring-up")
	else
		parts.pushed:SetShown(parts.down and true or false)
	end
end

local function ClassicBag(button)
	local parts = classic[button]
	local key = button == _G.KeyRingButton
	if not parts then
		parts = { key = key }
		if key then
			parts.art = button:CreateTexture(nil, "BORDER")
			parts.art:SetAllPoints()
		else
			parts.art = button:CreateTexture(nil, "OVERLAY")
			parts.art:SetPoint("CENTER", button, "CENTER", 0, -1)
			parts.pushed = button:CreateTexture(nil, "OVERLAY", nil, 1)
			parts.pushed:SetAllPoints()
		end
		parts.glow = button:CreateTexture(nil, "HIGHLIGHT")
		parts.glow:SetAllPoints()
		classic[button] = parts
		HookClassic(button, parts, BagState)
	end
	Fade(button:GetNormalTexture())
	Fade(button:GetPushedTexture())
	Fade(button:GetHighlightTexture())
	parts.on = true
	if key then
		E:SetOriginalArt(parts.glow, "keyring-highlight")
	else
		local width = button:GetWidth()
		parts.art:SetSize(width * 64 / 37, width * 64 / 37)
		E:SetOriginalArt(parts.art, "bagslot-frame")
		E:SetOriginalArt(parts.pushed, "bagslot-pushed")
		E:SetOriginalArt(parts.glow, "bagslot-highlight")
	end
	parts.art:Show()
	parts.glow:Show()
	BagState(button)
end

-- Back to the client's art (or the next skin's look).
local function Unclassic(button)
	local parts = classic[button]
	if not (parts and parts.on) then return end
	parts.on = false
	parts.art:Hide()
	parts.glow:Hide()
	if parts.pushed then parts.pushed:Hide() end
	if parts.portrait then parts.portrait:Hide() end
	for _, region in ipairs(ClientArt(button)) do Unfade(region) end
end
M.ClassicParts = function(button) return classic[button] end -- exposed for inspection

---------------------------------------------------------------------------
-- Micro menu
---------------------------------------------------------------------------
local placingMicro = false

local function MicroButtons()
	local list = {}
	for _, info in ipairs(MICRO_BUTTONS) do
		local button = _G[info[1]]
		if Usable(button) then list[#list + 1] = button end
	end
	return list
end

function M:CreateMicroHolder()
	local holder = CreateFrame("Frame", "EldoUI_MicroMenu", UIParent)
	holder:SetSize(300, 40)
	holder:SetFrameStrata("MEDIUM")
	self.microHolder = holder
	-- Bottom right corner above a bottom info bar.
	-- The box has the size the scaled menu shows on screen.
	E:CreateMover(holder, "EldoUI_MicroMenu", L["Micro Menu"], { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -19, 36 }, { scaled = true })
end

---------------------------------------------------------------------------
-- Layout choices in the boxes' right-click menus (Core/MoveSetup.lua).
-- Each one writes the settings of the options page below (buttons per row,
-- Vertical, the Blizzard UI switch), so the page and the menu agree.
---------------------------------------------------------------------------
local Layouts = {}
M.Layouts = Layouts -- exposed for inspection

-- How many micro buttons show: the last grid pass, else all of them.
function Layouts.MicroCount()
	return math.max(1, M.microShown or #MicroButtons())
end

function Layouts.Micro()
	if not E:BlizzardAllowed(MICRO, "move") then return "blizzard" end
	local perRow = M.db.micro.perRow or 14
	if perRow <= 1 then return "vertical" end
	if perRow >= Layouts.MicroCount() then return "horizontal" end
	return "grid"
end

-- EldoUI places the bar again (the Blizzard UI switch for Move and scale).
local function TakeOver(id)
	if E:BlizzardAllowed(id, "move") then return end
	E:SetBlizzardElement(id, "enabled", true)
	E:SetBlizzardElement(id, "move", true)
end

function Layouts.SetMicro(key)
	if key == "blizzard" then
		if E:BlizzardAllowed(MICRO, "move") then
			E:SetBlizzardElement(MICRO, "move", false)
			E:Print(L["The micro menu is Blizzard's again, placed by the game's Edit Mode. %s on its options page brings EldoUI's layout back."]:format(E:Highlight(L["Let EldoUI place the micro menu"])))
		end
		return
	end
	TakeOver(MICRO)
	local db = M.db.micro
	if key == "vertical" then
		db.perRow = 1
	elseif key == "horizontal" then
		db.perRow = #MICRO_BUTTONS
	else
		db.perRow = math.max(2, math.ceil(Layouts.MicroCount() / 2))
	end
	M:Apply()
end

function Layouts.Bags()
	return M.db.bags.vertical and "vertical" or "horizontal"
end

function Layouts.SetBags(key)
	M.db.bags.vertical = key == "vertical"
	M:Apply()
end

Layouts.MICRO = {
	{ key = "blizzard", label = "Blizzard default", desc = "The game's own micro menu, placed by Blizzard's Edit Mode. EldoUI stops moving it, and this box leaves move mode; \"Let EldoUI place the micro menu\" on its options page brings EldoUI's layout back." },
	{ key = "horizontal", label = "Horizontal", desc = "All buttons in one row." },
	{ key = "vertical", label = "Vertical", desc = "All buttons in one column." },
	{ key = "grid", label = "Grid", desc = "Two rows of buttons. Buttons per row on the options page sets any other grid." },
}
Layouts.BAGS = {
	{ key = "horizontal", label = "Horizontal", desc = "The bag buttons side by side." },
	{ key = "vertical", label = "Vertical", desc = "The bag buttons top to bottom." },
}

-- Size and Spacing submenus: the page's Scale and Spacing settings in a
-- few common steps.
Layouts.SCALES = { 50, 60, 70, 80, 90, 100, 120 }
Layouts.SPACINGS = { 0, 1, 2, 3, 4, 6 }
local function Percent(value) return L["%d %%"]:format(value) end
local function Pixels(value) return L["%d px"]:format(value) end

local function Steps(key)
	local function Setter(field)
		return function(value)
			M.db[key][field] = value
			M:Apply()
		end
	end
	local function Getter(field)
		return function() return tonumber(M.db[key][field]) end
	end
	return {
		{ label = "Size", values = Layouts.SCALES, get = Getter("scale"), set = Setter("scale"), format = Percent },
		{ label = "Spacing", values = Layouts.SPACINGS, get = Getter("spacing"), set = Setter("spacing"), format = Pixels },
	}
end

-- "Undo changes" in move mode: the rows, size and spacing, and for the
-- micro menu who places it (Blizzard default is a choice of its own).
local MICRO_KEYS = { "perRow", "scale", "spacing" }
function Layouts.MicroSnapshot()
	local state = { move = E:BlizzardAllowed(MICRO, "move") and true or false }
	for _, field in ipairs(MICRO_KEYS) do state[field] = M.db.micro[field] end
	return state
end

function Layouts.MicroRestore(state)
	for _, field in ipairs(MICRO_KEYS) do M.db.micro[field] = state[field] end
	if state.move then
		TakeOver(MICRO)
	elseif E:BlizzardAllowed(MICRO, "move") then
		E:SetBlizzardElement(MICRO, "move", false, true)
	end
	M:Apply()
end

E:SetMoverLayouts("EldoUI_MicroMenu", { get = Layouts.Micro, set = Layouts.SetMicro, choices = Layouts.MICRO,
	steps = Steps("micro"), snapshot = Layouts.MicroSnapshot, restore = Layouts.MicroRestore,
	options = { page = "module:MicroMenu", key = "micro.perRow" } })
E:SetMoverLayouts("EldoUI_BagBar", { get = Layouts.Bags, set = Layouts.SetBags, choices = Layouts.BAGS,
	steps = Steps("bags"),
	store = function() return M.db.bags end, keys = { "vertical", "scale", "spacing" }, apply = function() M:Apply() end,
	options = { page = "module:MicroMenu", key = "bags.vertical" } })

-- The visibility rule fades EldoUI's holder (never a Blizzard frame); the
-- whole holder counts for mouse-over. Move mode keeps it fully shown.
local function InMoveMode() return E:IsMoveMode() end

function M:UpdateMicroVisibility()
	local holder = self.microHolder
	if not holder then return end
	if self.active and holder:IsShown() and E:BlizzardAllowed(MICRO, "move") then
		E:AttachVisibility(holder, self.db.micro.visibility, { watch = holder, forceShow = InMoveMode })
	elseif E:IsVisibilityAttached(holder) then
		E:DetachVisibility(holder)
	end
end

-- EldoUI's grid, run after Blizzard's own MicroMenu:Layout().
function M:PlaceMicroButtons()
	local holder = self.microHolder
	if placingMicro or not holder or MicroMenu:GetParent() ~= holder then return end
	placingMicro = true
	local db = self.db.micro
	local shown = {}
	for _, button in ipairs(MicroButtons()) do
		local hiddenByPlayer = db.hide[button:GetName()]
		if hiddenByPlayer then
			Remember(button)
			button:SetParent(hider)
		else
			if saved[button] and button:GetParent() == hider then button:SetParent(MicroMenu) end
			if button:IsShown() and button:GetParent() == MicroMenu then shown[#shown + 1] = button end
		end
	end
	local perRow = math.max(1, db.perRow)
	-- Growth: which corner the first button sits in, and which way rows run.
	local growth = db.growth or "rightDown"
	local left = growth == "leftDown" or growth == "leftUp"
	local up = growth == "rightUp" or growth == "leftUp"
	local corner = (up and "BOTTOM" or "TOP") .. (left and "RIGHT" or "LEFT")
	local sx, sy = left and -1 or 1, up and 1 or -1
	local width, height = 0, 0
	local x, y, rowHeight = 0, 0, 0
	for index, button in ipairs(shown) do
		if index > 1 and (index - 1) % perRow == 0 then
			x = 0
			y = y + rowHeight + db.spacing
			rowHeight = 0
		end
		button:ClearAllPoints()
		button:SetPoint(corner, holder, corner, sx * x, sy * y)
		x = x + button:GetWidth() + db.spacing
		rowHeight = math.max(rowHeight, button:GetHeight())
		width = math.max(width, x - db.spacing)
		height = math.max(height, y + rowHeight)
	end
	holder:SetSize(math.max(width, 1), math.max(height, 1))
	self.microShown = #shown
	-- The holder is drawn at the menu's scale: its box in move mode (and the
	-- spot a layout gives it) is the size the player sees.
	local mover = E.movers and E.movers.EldoUI_MicroMenu
	local scale = holder:GetScale()
	if mover then mover:SetSize(math.max(width, 1) * scale, math.max(height, 1) * scale) end
	placingMicro = false
end

function M:SkinMicro(on)
	local original = on and OriginalOn()
	for _, button in ipairs(MicroButtons()) do
		local slot = CLASSIC_MICRO[button:GetName() or ""]
		if original then
			-- Vanilla Original: the classic buttons, the client's look on the others.
			Unbox(button)
			if slot then
				ClassicMicro(button, slot)
			else
				Unclassic(button)
				for _, region in ipairs(ClientArt(button)) do Unfade(region) end
			end
		elseif on then
			Unclassic(button)
			Fade(button.Background)
			Fade(button.PushedBackground)
			Fade(button.Shadow)
			Fade(button.PushedShadow)
			Fade(button:GetHighlightTexture())
			Box(button)
		else
			Unclassic(button)
			Unbox(button)
		end
	end
	if on then
		Fade(MicroMenu.BorderArt)
		Fade(MicroMenu.BackgroundArt)
	end
end

function M:HookMicro()
	if self.microHooked then return end
	self.microHooked = true
	if type(MicroMenu.Layout) == "function" then
		hooksecurefunc(MicroMenu, "Layout", function()
			if M.active and E:BlizzardAllowed(MICRO, "move") then M:PlaceMicroButtons() end
		end)
	end
	if type(UpdateMicroButtons) == "function" then
		hooksecurefunc("UpdateMicroButtons", function()
			if M.active and E:BlizzardAllowed(MICRO, "move") then M:PlaceMicroButtons() end
		end)
	end
	-- After a vehicle or pet battle Blizzard puts the menu back into its container.
	if MicroMenu.ResetMicroMenuPosition then
		hooksecurefunc(MicroMenu, "ResetMicroMenuPosition", function()
			if M.active and E:BlizzardAllowed(MICRO) then
				E:RunOutOfCombat(function() M:ApplyMicro() end)
			end
		end)
	end
	for _, button in ipairs(MicroButtons()) do
		-- Buttons Blizzard or another part of EldoUI shows or hides later (the
		-- shop button behind System's shop/help switch): close the gap.
		button:HookScript("OnShow", function() M:QueueMicroLayout() end)
		button:HookScript("OnHide", function() M:QueueMicroLayout() end)
	end
end

-- One grid pass per frame, out of combat, only while EldoUI places the buttons.
function M:QueueMicroLayout()
	if placingMicro or self.microQueued or not self.active then return end
	if not E:BlizzardAllowed(MICRO, "move") then return end
	self.microQueued = true
	C_Timer.After(0, function()
		M.microQueued = false
		if M.active and E:BlizzardAllowed(MICRO, "move") then
			E:RunOutOfCombat(function() M:PlaceMicroButtons() end)
		end
	end)
end

-- The micro menu is on a vehicle bar right now: leave it there.
local function MicroOverridden()
	local parent = MicroMenu:GetParent()
	return parent ~= MicroMenuContainer and parent ~= M.microHolder and parent ~= hider
end

-- Another bar addon can own the same Blizzard buttons. While one does
-- (Data/Competitors.lua), EldoUI leaves that bar alone: two addons never
-- move the same buttons.
function M:OnStandBack()
	self:Apply()
end

function M:ApplyMicro()
	if not Usable(MicroMenu) or not MicroMenuContainer then return end
	if not E:BlizzardAllowed(MICRO) then return end
	if E:StandsBack(self, "micro") then
		self:RestoreMicro()
		return
	end
	self:HookMicro()
	if MicroOverridden() then return end
	local hidden = E:BlizzardHidden(MICRO)
	local moved = E:BlizzardAllowed(MICRO, "move")
	if hidden then
		Remember(MicroMenu)
		MicroMenu:SetParent(hider)
		StandIn(MICRO, nil)
		if self.microHolder then self.microHolder:Hide() end
		self:ShowMicroMover(false)
		self:UpdateMicroVisibility()
		if E:BlizzardAllowed(MICRO, "replace") then self:AddMenuDataText() end
	elseif moved then
		if not self.microHolder then self:CreateMicroHolder() end
		Remember(MicroMenu)
		for _, button in ipairs(MicroButtons()) do Remember(button) end
		self.microHolder:Show()
		self.microHolder:SetScale(self:ScaleOf("micro"))
		MicroMenu:SetParent(self.microHolder)
		MicroMenu:ClearAllPoints()
		MicroMenu:SetPoint("TOPLEFT", self.microHolder, "TOPLEFT")
		self:PlaceMicroButtons()
		self:KeepSavedCenter("EldoUI_MicroMenu", self.microHolder)
		self:UpdateMicroVisibility()
		StandIn(MICRO, self.microHolder)
		self:ShowMicroMover(true)
	else
		self:RestoreMicro(true)
	end
	self:SkinMicro(E:BlizzardAllowed(MICRO, "skin"))
	self:OfferTourHelp()
end

-- The micro menu's box takes part in move mode only while EldoUI places
-- the menu; with Blizzard's own placement there is nothing for it to move.
function M:ShowMicroMover(shown)
	local mover = E.movers and E.movers.EldoUI_MicroMenu
	if mover then mover:SetShown(shown and true or false) end
end

function M:RestoreMicro(keepSkin)
	StandIn(MICRO, nil)
	self:ShowMicroMover(false)
	if self.microHolder then
		self.microHolder:Hide()
		if E:IsVisibilityAttached(self.microHolder) then E:DetachVisibility(self.microHolder) end
	end
	for _, button in ipairs(MicroButtons()) do Restore(button) end
	-- Buttons and menu go back to the anchors Blizzard's grid gave them.
	if saved[MicroMenu] then Restore(MicroMenu) end
	if not keepSkin then self:SkinMicro(false) end
end

-- Replace: make sure the Info Bar has the Menu datatext (once, on the right).
function M:AddMenuDataText()
	local db = self.db.micro
	if db.menuAdded then return end
	local infoBar = E:GetModule("InfoBar")
	if not infoBar or not infoBar.db then return end
	db.menuAdded = true
	for _, side in ipairs({ "left", "center", "right" }) do
		if tContains(infoBar.db[side], "Menu") then return end
	end
	table.insert(infoBar.db.right, "Menu")
	if infoBar.active and infoBar.OnProfileChanged then infoBar:OnProfileChanged() end
	E:Print(L["The micro menu is now the %s block on the Info Bar."]:format(E:Highlight(L["Menu"])))
end

---------------------------------------------------------------------------
-- "Menu" datatext: every micro button as one drop-down list. Each entry
-- clicks Blizzard's own button, so game rules and Forever's windows
-- (Legacy, the Vanilla-style group finder) behave as on the micro menu.
-- Out of combat only, like every datatext click.
---------------------------------------------------------------------------
local function MicroLabel(button, fallback)
	local text = button.tooltipText
	if type(text) == "string" and text ~= "" then return text end
	return L[fallback]
end

-- EldoUI windows in the list, after Blizzard's (My Adventure):
--   E:RegisterMenuEntry(key, { text = string | fn, order, shown = fn, func = fn })
-- `text` is shown as given (pass it through L[]). Never a Blizzard micro
-- button: each entry opens EldoUI's own window.
local menuEntries, menuEntryOrder = {}, {}

function E:RegisterMenuEntry(key, def)
	if type(key) ~= "string" or type(def) ~= "table" or type(def.func) ~= "function" then return end
	if not menuEntries[key] then menuEntryOrder[#menuEntryOrder + 1] = key end
	menuEntries[key] = { key = key, text = def.text, order = tonumber(def.order) or 50, shown = def.shown, func = def.func }
	table.sort(menuEntryOrder, function(a, b)
		if menuEntries[a].order ~= menuEntries[b].order then return menuEntries[a].order < menuEntries[b].order end
		return a < b
	end)
end

function E:UnregisterMenuEntry(key)
	if not menuEntries[key] then return end
	menuEntries[key] = nil
	for index, name in ipairs(menuEntryOrder) do
		if name == key then table.remove(menuEntryOrder, index) break end
	end
end

-- The entries shown now: { { key, text, func }, ... }.
function E:MenuEntries()
	local list = {}
	for _, key in ipairs(menuEntryOrder) do
		local def = menuEntries[key]
		local ok, shown = true, true
		if type(def.shown) == "function" then ok, shown = pcall(def.shown) end
		if ok and shown then
			local text = def.text
			if type(text) == "function" then
				local fine, value = pcall(text)
				text = fine and value or nil
			end
			if type(text) == "string" and text ~= "" then list[#list + 1] = { key = key, text = text, func = def.func } end
		end
	end
	return list
end

-- The Menu block's entries click the game's own micro buttons. The quest
-- log sits on the world map: a click on its button from EldoUI's code runs
-- the map's code as EldoUI's, the map's state stays tainted, and the game's
-- later opens of it (L, M, Escape) get their map pins blocked
-- ("SetPassThroughButtons()"; review/fehler.md F29). That entry asks the
-- game to open the map instead (E:OpenWorldMapAt), like the Info Bar's
-- Quests block without its secure overlay.
local GAME_REQUESTS = {
	QuestLogMicroButton = function() return E:OpenWorldMapAt() end,
}
M.GAME_REQUESTS = GAME_REQUESTS -- exposed for inspection

local function OpenFromMenu(name, button)
	if InCombatLockdown() then return end
	local request = GAME_REQUESTS[name]
	if request then
		request()
	else
		button:Click()
	end
end
M.OpenFromMenu = OpenFromMenu

E:RegisterDataText("Menu", {
	text = function()
		local r, g, b = unpack(E.media.accentColor)
		return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, E:GameText(MAINMENU_BUTTON, L["Menu"]))
	end,
	tooltip = function(tooltip)
		E:TooltipHint(tooltip, { L["Click"], L["open any game window from a list"] })
		E.UIKit.TipText(tooltip, L["Same entries as Blizzard's micro menu."])
	end,
	onClick = function(owner)
		E.UIKit.ContextMenu(owner, function(_, root)
			root:CreateTitle(E:GameText(MAINMENU_BUTTON, L["Menu"]))
			for _, info in ipairs(MICRO_BUTTONS) do
				local button = _G[info[1]]
				local inMenu = Usable(button) and (button:GetParent() == MicroMenu or (saved[button] and saved[button].parent == MicroMenu))
				if inMenu then
					local entry = root:CreateButton(MicroLabel(button, info[2]), function()
						OpenFromMenu(info[1], button)
					end)
					if entry and entry.SetEnabled then entry:SetEnabled(button:IsEnabled()) end
				end
			end
			-- EldoUI's Talent Planner, while that module is on.
			local planner = E.Talents
			if planner and planner.active then
				root:CreateButton(E.L["Talent Planner"], function() planner:TogglePlanner() end)
			end
			for _, entry in ipairs(E:MenuEntries()) do
				root:CreateButton(entry.text, function() entry.func() end)
			end
		end)
	end,
})

---------------------------------------------------------------------------
-- Bag bar
---------------------------------------------------------------------------
local placingBags = false

local function BagButtons()
	local list = { MainMenuBarBackpackButton }
	for index = 0, (NUM_BAG_SLOTS or 4) - 1 do list[#list + 1] = _G["CharacterBag" .. index .. "Slot"] end
	list[#list + 1] = _G.CharacterReagentBag0Slot
	list[#list + 1] = _G.KeyRingButton
	local usable = {}
	for _, button in ipairs(list) do
		if Usable(button) then usable[#usable + 1] = button end
	end
	return usable
end

local function IsBagSlot(button)
	return button ~= MainMenuBarBackpackButton and button ~= _G.KeyRingButton
end

function M:CreateBagHolder()
	local holder = CreateFrame("Frame", "EldoUI_BagBar", UIParent)
	holder:SetSize(200, 40)
	holder:SetFrameStrata("MEDIUM")
	self.bagHolder = holder
	-- Bottom right, left of the micro menu.
	-- The box has the size the scaled bar shows on screen, so it drags and
	-- snaps with the buttons' own edges.
	E:CreateMover(holder, "EldoUI_BagBar", L["Bag Bar"], { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -19, 84 }, { scaled = true })
end

-- Docked on the bag window the bar shows with the window, so no rule applies.
function M:UpdateBagVisibility()
	local holder = self.bagHolder
	if not holder then return end
	if self.active and holder:IsShown() and not self.docked then
		E:AttachVisibility(holder, self.db.bags.visibility, { watch = holder, forceShow = InMoveMode })
	elseif E:IsVisibilityAttached(holder) then
		E:DetachVisibility(holder)
	end
end

function M:PlaceBagButtons()
	local holder = self.bagHolder
	if placingBags or not holder or not holder:IsShown() then return end
	placingBags = true
	local db = self.db.bags
	local shown = {}
	for _, button in ipairs(BagButtons()) do
		local hide = (db.onlyBackpack and IsBagSlot(button)) or (button == _G.KeyRingButton and not db.keyring)
		if hide then
			button:SetParent(hider)
		else
			button:SetParent(holder)
			if button:IsShown() then shown[#shown + 1] = button end
		end
	end
	if db.reverse then
		local reversed = {}
		for index = #shown, 1, -1 do reversed[#reversed + 1] = shown[index] end
		shown = reversed
	end
	local offset, across = 0, 0
	for _, button in ipairs(shown) do
		button:ClearAllPoints()
		if db.vertical then
			button:SetPoint("TOP", holder, "TOP", 0, -offset)
			offset = offset + button:GetHeight() + db.spacing
			across = math.max(across, button:GetWidth())
		else
			button:SetPoint("LEFT", holder, "LEFT", offset, 0)
			offset = offset + button:GetWidth() + db.spacing
			across = math.max(across, button:GetHeight())
		end
	end
	offset = math.max(1, offset - db.spacing)
	if db.vertical then holder:SetSize(math.max(across, 1), offset) else holder:SetSize(offset, math.max(across, 1)) end
	placingBags = false
end

function M:SkinBags(on)
	local original = on and OriginalOn()
	for _, button in ipairs(BagButtons()) do
		if original then
			-- Vanilla Original: the classic bag slots round the client's icons.
			Unbox(button)
			ClassicBag(button)
		elseif on then
			Unclassic(button)
			Fade(button:GetNormalTexture())
			Fade(button:GetPushedTexture())
			Fade(button:GetHighlightTexture())
			local icon = button.icon or button.Icon
			if icon then
				if button.SquareMask and icon.RemoveMaskTexture then icon:RemoveMaskTexture(button.SquareMask) end
				E:TrimIcon(icon)
				icon:ClearAllPoints()
				icon:SetPoint("TOPLEFT", E.pixel * 2, -E.pixel * 2)
				icon:SetPoint("BOTTOMRIGHT", -E.pixel * 2, E.pixel * 2)
			end
			Box(button)
		else
			Unclassic(button)
			Unbox(button)
		end
	end
	if on and BagsBar then Fade(BagsBar.BorderArt) end
end

-- The bag window may not exist yet; it is created the first time it opens.
local function BagWindow()
	local bags = E:GetModule("Bags")
	if not (bags and bags.active) then return nil end
	return _G.EldoUI_Bags
end

function M:DockBags()
	local window = BagWindow()
	local holder = self.bagHolder
	if window then
		self.docked = true
		holder:SetParent(window)
		holder:SetScale(self:ScaleOf("bags"))
		holder:ClearAllPoints()
		holder:SetPoint("BOTTOMRIGHT", window, "TOPRIGHT", 0, 4)
		holder:SetFrameStrata(window:GetFrameStrata())
	else
		self:UndockBags()
		-- Retry once EldoUI's bag window has been built.
		local bags = E:GetModule("Bags")
		if bags and bags.CreateWindow and not self.bagWindowHooked then
			self.bagWindowHooked = true
			hooksecurefunc(bags, "CreateWindow", function(_, kind)
				if kind ~= "bank" and M.active and E:BlizzardAllowed(BAGS, "replace") then
					E:RunOutOfCombat(function() M:ApplyBags() end)
				end
			end)
		end
	end
end

function M:UndockBags()
	local holder = self.bagHolder
	if not self.docked then return end
	self.docked = false
	holder:SetParent(UIParent)
	holder:SetFrameStrata("MEDIUM")
	holder:ClearAllPoints()
	local mover = E.movers and E.movers.EldoUI_BagBar
	if mover then holder:SetPoint("CENTER", mover, "CENTER") end
end

function M:HookBags()
	if self.bagsHooked or not BagsBar then return end
	self.bagsHooked = true
	if type(BagsBar.Layout) == "function" then
		hooksecurefunc(BagsBar, "Layout", function()
			if M.active and M.bagHolder and M.bagHolder:IsShown() and (E:BlizzardAllowed(BAGS, "move") or E:BlizzardAllowed(BAGS, "replace")) then
				E:RunOutOfCombat(function() M:PlaceBagButtons() end)
			end
		end)
	end
end

function M:ApplyBags()
	if not Usable(BagsBar) then return end
	if not E:BlizzardAllowed(BAGS) then return end
	if E:StandsBack(self, "bags") then
		self:RestoreBags()
		return
	end
	self:HookBags()
	local db = self.db.bags
	-- Blizzard's "show free bag slots" game setting, only when the player picked one.
	if db.freeSlots ~= "blizzard" then
		E:SetCVar("displayFreeBagSlots", db.freeSlots == "show" and 1 or 0, BAGS)
	else
		E:RestoreCVar("displayFreeBagSlots", BAGS)
	end
	local replace = E:BlizzardAllowed(BAGS, "replace")
	local hidden = E:BlizzardAllowed(BAGS, "hide") and not replace
	local moved = E:BlizzardAllowed(BAGS, "move") or replace
	if hidden then
		self:RestoreBagButtons()
		Remember(BagsBar)
		-- Kept hidden when Edit Mode re-parents it (core SetParent hook).
		E:HideBlizzardFrame(BagsBar, { check = function() return M.active and saved[BagsBar] ~= nil end })
		if self.bagHolder then self.bagHolder:Hide() end
		self:UpdateBagVisibility()
	elseif moved then
		if saved[BagsBar] then Restore(BagsBar) end
		if not self.bagHolder then self:CreateBagHolder() end
		for _, button in ipairs(BagButtons()) do Remember(button) end
		-- Blizzard's empty bar (frame art and dividers) stays in place, invisible.
		BagsBar:SetAlpha(0)
		self.bagHolder:Show()
		if replace then
			self:DockBags()
		else
			self:UndockBags()
			self.bagHolder:SetScale(self:ScaleOf("bags"))
		end
		self:PlaceBagButtons()
		if not self.docked then self:KeepSavedCenter("EldoUI_BagBar", self.bagHolder) end
		self:UpdateBagVisibility()
		StandIn(BAGS, self.bagHolder)
	else
		self:RestoreBagButtons()
		if saved[BagsBar] then Restore(BagsBar) end
	end
	self:SkinBags(E:BlizzardAllowed(BAGS, "skin"))
end

function M:RestoreBagButtons()
	StandIn(BAGS, nil)
	if self.bagHolder then
		self:UndockBags()
		self.bagHolder:Hide()
		self:UpdateBagVisibility()
	end
	-- Every button goes back to Blizzard's parent and anchors.
	for _, button in ipairs(BagButtons()) do Restore(button) end
	if BagsBar then BagsBar:SetAlpha(1) end
end

function M:RestoreBags()
	self:RestoreBagButtons()
	if BagsBar and saved[BagsBar] then Restore(BagsBar) end
	self:SkinBags(false)
	E:RestoreCVars(BAGS)
end

---------------------------------------------------------------------------
-- Blizzard UI element handlers
---------------------------------------------------------------------------
E:RegisterBlizzardHandler(MICRO, {
	owner = "MicroMenu",
	apply = function() M:ApplyMicro() end,
	undo = function() M:RestoreMicro() end,
	reload = { skin = true, move = true },
	install = { skin = true, move = true },
	legacy = function() return false end,
})

E:RegisterBlizzardHandler(BAGS, {
	owner = "MicroMenu",
	apply = function() M:ApplyBags() end,
	undo = function() M:RestoreBags() end,
	reload = { skin = true, move = true, replace = true },
	install = { skin = true, move = true },
	legacy = function() return false end,
})

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
-- v0.6 and older: "Show on mouseover" + faded opacity (0-100) per bar. They
-- become the shared visibility block once per profile; the old keys go.
function M:MigrateVisibility()
	for _, key in ipairs({ "micro", "bags" }) do
		local db = self.db[key]
		if type(db) == "table" and (db.mouseover ~= nil or db.fadeAlpha ~= nil) then
			if db.mouseover then
				db.visibility = E:VisibilityFromLegacy("mouseover", (tonumber(db.fadeAlpha) or 0) / 100)
			end
			db.mouseover, db.fadeAlpha = nil, nil
		end
	end
end

-- Scale is a percent on every page. Older profiles kept the micro
-- menu as a factor (0.4-1.5) and the bag bar as a button size in pixels
-- (Blizzard's are 45); both move to percent once.
function M:MigrateScale()
	local micro, bags = self.db.micro, self.db.bags
	if type(micro) == "table" and tonumber(micro.scale) and tonumber(micro.scale) <= 2 then
		micro.scale = math.floor(tonumber(micro.scale) * 100 + 0.5)
	end
	if type(bags) == "table" and bags.size ~= nil then
		local size = tonumber(bags.size)
		if size then bags.scale = math.floor(size / 45 * 100 + 0.5) end
		bags.size = nil
	end
end

-- The micro menu used to sit in the top row in every layout, as small rows
-- of seven (Eldo-Classic: five) at 60 %. Now each layout places it along the
-- bottom next to the bag bar, with its own rows and size. A profile that
-- still has the old top settings and never moved the menu takes the size
-- and rows its layout gives the new spot, once. A spot the player dragged
-- the menu to, or a size the player picked, stays as it is.
function M.MigrateBottomSpot(profile)
	local modules = type(profile) == "table" and type(profile.modules) == "table" and profile.modules
	local own = modules and type(modules.MicroMenu) == "table" and modules.MicroMenu
	local micro = own and type(own.micro) == "table" and own.micro
	if not micro then return end
	if type(profile.movers) == "table" and profile.movers.EldoUI_MicroMenu ~= nil then return end
	if tonumber(micro.scale) ~= 60 or (micro.perRow ~= 7 and micro.perRow ~= 5) then return end
	local general = type(profile.general) == "table" and profile.general
	local layout = general and E.layouts and E.layouts[general.layout]
	local values = layout and layout.modules and layout.modules.MicroMenu and layout.modules.MicroMenu.micro
	if type(values) ~= "table" then return end
	for key, value in pairs(values) do micro[key] = value end
end
E:RegisterProfileMigration(M.MigrateBottomSpot, "MicroMenu:bottom", 1)

-- Older versions drew the micro menu's box (before 0.6.6002) and the bag
-- bar's box (before 0.6.6005) at the unscaled size, with the smaller,
-- scaled bar in its middle. A spot saved then names the corner of that
-- larger box, so the true-size box of today puts the bar a little nearer
-- that corner. Each saved spot from those versions is marked once here and
-- moved back to its old visible center the first time the bar is laid out
-- (its size is known only then). Spots saved since, attached to another
-- frame, or from a profile of a newer version stay as they are.
M.CENTER_SINCE = { EldoUI_MicroMenu = "0.6.6002", EldoUI_BagBar = "0.6.6005" }

-- The EldoUI version that ran before this one, read once before login
-- writes the new one (Core/Config.lua, the update note).
function M.PreviousVersion()
	if M.previousVersion == nil then
		local window = type(EldoUIDB) == "table" and type(EldoUIDB.configWindow) == "table" and EldoUIDB.configWindow
		M.previousVersion = window and type(window.seenVersion) == "string" and window.seenVersion or false
	end
	return M.previousVersion or nil
end

function M.MigrateCenters(profile)
	local movers = type(profile) == "table" and type(profile.movers) == "table" and profile.movers
	local seen = M.PreviousVersion()
	if not movers or not seen then return end
	local pending
	for name, since in pairs(M.CENTER_SINCE) do
		local pos = movers[name]
		if type(pos) == "table" and pos.link == nil and (pos[2] == nil or pos[2] == "UIParent")
			and type(pos[1]) == "string" and tonumber(pos[4]) and tonumber(pos[5])
			and E:CompareVersions(seen, since) == -1 then
			pending = pending or {}
			pending[name] = true
		end
	end
	if not pending then return end
	if type(profile.modules) ~= "table" then profile.modules = {} end
	if type(profile.modules.MicroMenu) ~= "table" then profile.modules.MicroMenu = {} end
	profile.modules.MicroMenu.centerPending = pending
end
E:RegisterProfileMigration(M.MigrateCenters, "MicroMenu:center", 1)

-- The saved spot of `name`, moved so the bar's center stays where the old
-- box showed it. `holder` is laid out at its scale already.
function M:KeepSavedCenter(name, holder)
	local pending = self.db and self.db.centerPending
	if type(pending) ~= "table" or not pending[name] then return end
	pending[name] = nil
	if next(pending) == nil then self.db.centerPending = nil end
	local pos = E.db.movers and E.db.movers[name]
	if type(pos) ~= "table" or pos.link ~= nil or (pos[2] ~= nil and pos[2] ~= "UIParent") then return end
	local point, x, y = pos[1], tonumber(pos[4]), tonumber(pos[5])
	if type(point) ~= "string" or not (x and y) then return end
	local width, height = holder:GetSize()
	local scale = holder:GetScale() or 1
	local dx, dy = (1 - scale) * width / 2, (1 - scale) * height / 2
	if point:find("LEFT") then x = x + dx elseif point:find("RIGHT") then x = x - dx end
	if point:find("BOTTOM") then y = y + dy elseif point:find("TOP") then y = y - dy end
	E:SaveMoverPosition(name, point, "UIParent", pos[3] or point, x, y)
end

local SCALE_MIN, SCALE_MAX = 40, 150

-- The holder scale for "micro" or "bags", from the percent setting.
function M:ScaleOf(key)
	local value = tonumber(self.db[key] and self.db[key].scale) or (key == "micro" and 80 or 70)
	return math.max(SCALE_MIN, math.min(SCALE_MAX, value)) / 100
end

function M:Apply()
	E:RunOutOfCombat(function()
		M:ApplyMicro()
		M:ApplyBags()
	end)
end

function M:OnInitialize()
	M.PreviousVersion()
	self:MigrateVisibility()
	self:MigrateScale()
end

function M:OnEnable()
	-- Blizzard_MicroMenu and Blizzard_MainMenuBarBagButtons load with the
	-- UI; the element handlers run at login. Re-apply once the world is in,
	-- since Edit Mode lays out its systems after PLAYER_LOGIN.
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		if M.active then M:Apply() end
	end)
	-- Every Blizzard layout pass (Edit Mode's UpdateLayoutInfo, loading
	-- screens, leaving a vehicle): Core/Blizzard.lua, out of combat.
	E:OnBlizzardRelayout(self, function()
		if M.active then M:Apply() end
	end)
end

function M:OnDisable()
	E:OffBlizzardRelayout(self)
	E:RunOutOfCombat(function()
		if M.active then return end
		M:RestoreMicro()
		M:RestoreBags()
		M:UpdateBagVisibility()
		UnfadeAll()
	end)
end

function M:OnProfileChanged()
	self:MigrateVisibility()
	self:MigrateScale()
	if not self.active then return end
	self:Apply()
	if self.microHolder and E:IsVisibilityAttached(self.microHolder) then E:UpdateVisibility(self.microHolder) end
	if self.bagHolder and E:IsVisibilityAttached(self.bagHolder) then E:UpdateVisibility(self.bagHolder) end
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local function Allowed(id, action)
	return function() return not E:BlizzardAllowed(id, action) end
end

-- Bag bar rows only where they do something: layout and buttons
-- while EldoUI places the bar (Move, or Replace docking it on the bag
-- window), visibility only while it sits free on its own mover.
local function BagsPlaced()
	return E:BlizzardAllowed(BAGS, "move") or E:BlizzardAllowed(BAGS, "replace")
end
local function BagsLayoutHidden() return not BagsPlaced() end
local function BagsVisibilityHidden()
	return not E:BlizzardAllowed(BAGS, "move") or E:BlizzardAllowed(BAGS, "replace")
end

local function SwitchButton(id, action, label, desc)
	return { type = "execute", label = label, desc = desc,
		hidden = function() return E:BlizzardAllowed(id, action) end,
		func = function()
			E:SetBlizzardElement(id, "enabled", true)
			E:SetBlizzardElement(id, action, true)
			if E.RefreshConfig then E:RefreshConfig() end
		end }
end

M.options = {
	{ type = "tab", label = "Micro menu" },
	{ type = "description", label = "For Blizzard's micro menu, once it is on in Blizzard UI. Move and scale gives it a mover; Replace puts a Menu block on the Info Bar." },
	SwitchButton(MICRO, "move", "Let EldoUI place the micro menu", E.Key("Turns on the Blizzard UI switch for the micro menu with Move and scale.")),
	{ type = "header", label = "Layout", hidden = Allowed(MICRO, "move") },
	{ type = "range", key = "micro.scale", label = "Scale", unit = "%", desc = "Size of the micro buttons in percent (100 = Blizzard's size).", min = SCALE_MIN, max = SCALE_MAX, step = 5,
		hidden = Allowed(MICRO, "move") },
	{ type = "range", key = "micro.perRow", label = "Buttons per row", desc = "How many buttons before a new row starts.", min = 1, max = 14, step = 1,
		hidden = Allowed(MICRO, "move") },
	{ type = "range", unit = "px", key = "micro.spacing", label = "Spacing", desc = "Gap between buttons.", min = 0, max = 12, step = 1,
		hidden = Allowed(MICRO, "move") },
	{ type = "select", key = "micro.growth", label = "Growth direction", desc = "Which corner the first button sits in and which way new buttons and rows are added.",
		values = { rightDown = "Right, rows down", leftDown = "Left, rows down", rightUp = "Right, rows up", leftUp = "Left, rows up" },
		hidden = Allowed(MICRO, "move") },
	{ type = "header", label = "Buttons", hidden = Allowed(MICRO, "move") },
	{ type = "description", label = "Hidden buttons still work through their keybinds and the Info Bar Menu block.",
		hidden = Allowed(MICRO, "move") },
}
for _, info in ipairs(MICRO_BUTTONS) do
	table.insert(M.options, { type = "toggle", key = "micro.hide." .. info[1], label = "Hide %s", labelFill = info[2],
		desc = "Takes the %s button off the micro menu.", descFill = function() return L[info[2]]:lower() end, hidden = Allowed(MICRO, "move") })
end
-- Shared visibility block: presets, show rule, faded alpha; the rare
-- settings sit behind the cog.
for _, row in ipairs(E:VisibilityOptions("micro.visibility", { label = "Visibility", hidden = Allowed(MICRO, "move"),
	db = function() return M.db end })) do
	table.insert(M.options, row)
end

local BAG_OPTIONS = {
	{ type = "tab", label = "Bag bar" },
	{ type = "description", label = "For Blizzard's bag bar, once it is on in Blizzard UI. Move and scale gives it a mover; Replace docks the bag buttons on EldoUI's bag window." },
	SwitchButton(BAGS, "move", E.Key("Let EldoUI place the bag bar"), E.Key("Turns on the Blizzard UI switch for the bag bar with Move and scale.")),
	{ type = "header", label = "Layout", hidden = BagsLayoutHidden },
	{ type = "range", key = "bags.scale", label = "Scale", unit = "%", desc = "Size of the bag buttons in percent (100 = Blizzard's size).", min = SCALE_MIN, max = SCALE_MAX, step = 5, hidden = BagsLayoutHidden },
	{ type = "range", unit = "px", key = "bags.spacing", label = "Spacing", desc = "Gap between bag buttons.", min = 0, max = 12, step = 1, hidden = BagsLayoutHidden },
	{ type = "toggle", key = "bags.vertical", label = "Vertical", desc = "Stack the bag buttons top to bottom.", hidden = BagsLayoutHidden },
	{ type = "toggle", key = "bags.reverse", label = "Backpack last", desc = "Put the backpack at the end of the row instead of the start.", hidden = BagsLayoutHidden },
	{ type = "header", label = "Buttons", hidden = BagsLayoutHidden },
	{ type = "toggle", key = "bags.onlyBackpack", label = "Only the backpack", desc = "Hide the four bag slots; the backpack button stays.", hidden = BagsLayoutHidden },
	{ type = "toggle", key = "bags.keyring", label = "Keyring button", desc = "Forever's keyring button next to the bags (when the game offers it).", hidden = BagsLayoutHidden },
	{ type = "select", key = "bags.freeSlots", label = "Free slots on the backpack", desc = "Blizzard's free bag slot count on the backpack button (a game setting). \"Leave as it is\" never changes it.",
		values = { blizzard = "Leave as it is", show = "Show", hide = "Hide" } },
}
for _, row in ipairs(E:VisibilityOptions("bags.visibility", { label = "Visibility", hidden = BagsVisibilityHidden,
	db = function() return M.db end })) do
	table.insert(BAG_OPTIONS, row)
end
local function BagsOff() return not E:BlizzardAllowed(BAGS) end
for _, option in ipairs(BAG_OPTIONS) do
	if option.key and not option.hidden then
		option.hidden = BagsOff
	elseif option.key or option.type == "header" then
		local own = option.hidden
		option.hidden = function() return BagsOff() or (own and own() or false) end
	end
	table.insert(M.options, option)
end
table.insert(M.options, { type = "execute", label = "Open Blizzard UI switches", desc = "Open the switches for the micro menu and the bag bar.",
	func = function() if E.ToggleConfig then E:ToggleConfig("blizzard") end end })

---------------------------------------------------------------------------
-- Style presets (the layout places both bars)
---------------------------------------------------------------------------
-- A visibility preset written out in full, so it holds before the bar was
-- ever shown.
local function Vis(key)
	local preset = E.VISIBILITY_PRESETS[key]
	return { preset = key, show = preset.show, fadedAlpha = preset.fadedAlpha, fadeTime = preset.fadeTime, delay = preset.delay }
end

E:RegisterStyles("MicroMenu", {
	{ key = "Strip", title = "One strip", desc = "All buttons in one row, bags above them.",
		settings = { micro = { scale = 80, perRow = 14, spacing = 2, growth = "rightDown", visibility = Vis("always") }, bags = { scale = 70, vertical = false, onlyBackpack = false, visibility = Vis("always") } } },
	{ key = "Block", title = "Two rows", desc = "A compact 7 x 2 block with the bags on top.",
		settings = { micro = { scale = 80, perRow = 7, spacing = 2, growth = "rightDown", visibility = Vis("always") }, bags = { scale = 70, vertical = false } } },
	{ key = "Hover", title = "Mouse-over", desc = "Both bars invisible until you point at them; any other style shows them again.",
		settings = { micro = { scale = 80, perRow = 14, visibility = Vis("mouseover") }, bags = { scale = 70, visibility = Vis("mouseover") } } },
	{ key = "Minimal", title = "Minimal", desc = "Small buttons, only the backpack, no shop or help.",
		settings = { micro = { scale = 60, perRow = 14, spacing = 1, hide = { StoreMicroButton = true, HelpMicroButton = true } },
			bags = { scale = 60, onlyBackpack = true } } },
	{ key = "Large", title = "Large", desc = "Blizzard-sized buttons with wider gaps.",
		settings = { micro = { scale = 100, perRow = 14, spacing = 3 }, bags = { scale = 90, spacing = 4 } } },
}, { restores = { "micro.visibility", "bags.visibility", "micro.hide", "bags.onlyBackpack" } })

---------------------------------------------------------------------------
-- Tour help: where the micro menu went, once for each case (scope):
--   replace    the micro menu is the Menu block on the Info Bar
--   mouseover  the micro menu shows only while the mouse is over it
---------------------------------------------------------------------------
-- The Menu block on screen, on any Info Bar or panel.
local function MenuBlock()
	local infoBar = E.modules.InfoBar
	if not (infoBar and infoBar.active) then return nil end
	for _, list in ipairs({ infoBar.bars or {}, infoBar.panelFrames or {} }) do
		for _, holder in ipairs(list) do
			for _, button in ipairs(holder.buttons or {}) do
				if button.dataName == "Menu" and button:IsVisible() then return button end
			end
		end
	end
end

local function OnMouseover(db)
	return type(db) == "table" and type(db.visibility) == "table" and db.visibility.show == "mouseover"
end

-- The bars that show on mouse-over now: the micro menu, and the bag bar
-- when it sits on its own mover with the same rule.
local function MouseoverBars()
	local holder = M.microHolder
	if not (holder and holder:IsShown() and E:BlizzardAllowed(MICRO, "move") and OnMouseover(M.db.micro)) then return nil end
	local bags = M.bagHolder and M.bagHolder:IsShown() and E:BlizzardAllowed(BAGS, "move")
		and not E:BlizzardAllowed(BAGS, "replace") and OnMouseover(M.db.bags)
	return holder, bags and true or false
end

E.Tour:Register("micromenu", {
	form = "spot", word = "micromenu",
	offer = function(_, scope, force)
		if scope == "replace" then
			local infoBar = E.modules.InfoBar
			if not E:BlizzardAllowed(MICRO, "replace") or not (infoBar and infoBar.active) then return false end
			-- Built Info Bars without a Menu block: nothing to point at.
			if not MenuBlock() and #(infoBar.bars or {}) > 0 and not force then return false end
			return E.Tour:Spot("micromenu", {
				-- Offered again at the next redraw, so it never waits in the queue.
				force = force, now = true, scope = scope, target = MenuBlock,
				title = L["Micro menu"],
				text = L["The game menu buttons are in the Menu block on the Info Bar now. To get the micro menu back, turn off \"Replace with EldoUI's frame\" for it on the Blizzard UI page in /eui."],
			})
		end
		local holder, bags = MouseoverBars()
		if not holder then return false end
		return E.Tour:Spot("micromenu", {
			-- Offered again at the next redraw, so it never waits in the queue.
			force = force, now = true, scope = "mouseover", target = holder,
			title = L["Micro menu"],
			text = bags and L["The micro menu and the bag bar show when you point at their spot."]
				or L["The micro menu shows when you point at its spot."],
			buttons = { { bags and L["Always show them"] or L["Always show it"], function()
				E:ApplyVisibilityPreset(M.db.micro.visibility, "always")
				if bags then E:ApplyVisibilityPreset(M.db.bags.visibility, "always") end
				E:RunOutOfCombat(function()
					if M.active then M:OnProfileChanged() end
					if E.RefreshConfig then E:RefreshConfig() end
				end, "MicroMenu:tour")
			end, L["Visibility on the Micro Menu and Bag Bar page changes it again."] } },
		})
	end,
	replay = function(def)
		if E:BlizzardAllowed(MICRO, "replace") then
			def.offer(def, "replace", true)
		else
			def.offer(def, "mouseover", true)
		end
	end,
})

-- After every placement pass (out of combat): the help for the case in use.
function M:OfferTourHelp()
	if E:BlizzardAllowed(MICRO, "replace") then
		E.Tour:Offer("micromenu", "replace")
	elseif MouseoverBars() then
		E.Tour:Offer("micromenu", "mouseover")
	end
end
