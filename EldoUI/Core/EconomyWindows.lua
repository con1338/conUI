-- EldoUI economy windows: the small shared kit the Merchant, Mail, Auction
-- House and Trade modules use to place and skin Blizzard's windows.
-- It is not a module of its own; it only adds helpers to E.
--
--   local window = E:EconomyWindow({
--       id = "merchant",                       -- Blizzard element (Core/Blizzard.lua)
--       key = "merchant",                      -- window mover key (Data/MovableWindows.lua)
--       frame = function() return MerchantFrame end,
--       mover = "EldoUI_MerchantWindow",      -- EldoUI mover name (layout points)
--       title = "Merchant Window",
--       point = { "TOPLEFT", "UIParent", "TOPLEFT", 20, -150 },
--       active = function() return M.active end, -- the module is on
--   })
--   window:Apply()     -- after a switch or setting changed: place, or not
--   window:Restore()   -- the module or its switch went off: put it back
--   E:EconomySlot(button, icon)   -- a flat 1 px item slot (skins)
--
-- Two parts share the work, so these windows behave like every other
-- Blizzard window:
--   * The window mover (Core/WindowMover.lua, entries in
--     Data/MovableWindows.lua) drags them, scales them with the mouse wheel,
--     keeps the scale per profile and resets them ("Reset all scales" on
--     the Move windows page).
--   * This kit gives each window its home: an invisible EldoUI anchor with
--     a normal EldoUI mover, so /eui move, the nudge panel and the layout
--     presets say where the window opens until the player drags it. A
--     dragged window stays where it was dropped; "Blizzard's place" on the
--     Move windows page sends it home again.
-- How placing works (taint notes):
--   * Blizzard places these windows with its UI panel manager whenever one
--     opens or closes. EldoUI never changes UIPanelWindows or writes fields
--     into the frames; it lets Blizzard place the window and then anchors it
--     to the EldoUI anchor.
--   * None of these windows is protected. Anchoring still goes through
--     E:RunOutOfCombat when a frame reports itself protected, as a guard.
--   * With the element's "Move and scale" switch off (or the window unticked
--     on the Move windows page) nothing is touched, and the next time the window
--     opens Blizzard places it again.
--   * The module that owns a window passes `active`: while that module is
--     off its window is never placed, whatever the switches say.
--   * Each placing first notes where Blizzard put the window. Restore puts
--     an open window back on that spot at once, so turning the module or
--     the switch off never leaves the window where EldoUI placed it.
-- Written from scratch for EldoUI; no code or media from other addons.
local _, E = ...

local Window = {}
Window.__index = Window

local windows = {}          -- every handle, for the panel manager hooks
local hooked = false

local function Usable(frame)
	return type(frame) == "table" and type(frame.GetObjectType) == "function"
		and not E.FrameCheck(frame, "IsForbidden")
end

local function Guarded(frame, fn)
	if E.FrameCheck(frame, "IsProtected") then
		E:RunOutOfCombat(fn)
	else
		fn()
	end
end

function Window:Frame()
	local ok, frame = pcall(self.spec.frame)
	if ok and Usable(frame) then return frame end
end

-- The owning module, the element's Move switch, the Move windows page's tick
-- and its main switch.
function Window:Allowed()
	if self.spec.active and not self.spec.active() then return false end
	if not E:BlizzardAllowed(self.spec.id, "move") then return false end
	if self.spec.key and E.IsWindowAllowed then return E:IsWindowAllowed(self.spec.key) end
	return true
end

-- The window mover keeps the scale (mouse wheel, Move windows page).
function Window:Scale()
	local state = self.spec.key and E.GetWindowState and E:GetWindowState(self.spec.key)
	local scale = state and state.scale or 1
	if type(scale) ~= "number" or scale <= 0 then scale = 1 end
	return scale
end

-- A window the player dragged stays where the window mover put it.
function Window:Dragged()
	local state = self.spec.key and E.GetWindowState and E:GetWindowState(self.spec.key)
	return state and state.pos ~= nil or false
end

-- The anchor and its mover are made the first time moving is allowed, so a
-- player who never turns "Move and scale" on never gets the mover.
function Window:Ensure(frame)
	if self.anchor then return self.anchor end
	local anchor = CreateFrame("Frame", self.spec.mover .. "Anchor", UIParent)
	local width, height = frame:GetSize()
	anchor:SetSize(math.max(width or 0, 100) * self:Scale(), math.max(height or 0, 100) * self:Scale())
	self.anchor = anchor
	self.moverFrame = E:CreateMover(anchor, self.spec.mover, E.L[self.spec.title], self.spec.point, { sample = false })
	return anchor
end

-- The mover takes the window's size (times the scale) so move mode shows
-- exactly where the window will open.
function Window:SizeAnchor(frame)
	if not self.anchor then return end
	local width, height = frame:GetSize()
	if width and width > 0 and height and height > 0 then
		self.anchor:SetSize(width * self:Scale(), height * self:Scale())
	end
end

local function Points(frame)
	local list = {}
	for i = 1, frame:GetNumPoints() do list[i] = { frame:GetPoint(i) } end
	return list
end

-- Where Blizzard put the window, noted whenever it is not on the anchor
-- (Blizzard places it again on every open).
function Window:NoteHome(frame)
	local _, relative = frame:GetPoint(1)
	if self.anchor and relative == self.anchor then return end
	self.home = Points(frame)
end

-- Puts the (shown) window on the EldoUI anchor, unless the player dragged
-- it somewhere else. The scale is the window mover's.
function Window:Place()
	local frame = self:Frame()
	if not frame or not self:Allowed() then return end
	local anchor = self:Ensure(frame)
	if self:Dragged() then
		self:SizeAnchor(frame)
		return
	end
	Guarded(frame, function()
		if not self:Allowed() or self:Dragged() then return end
		self:SizeAnchor(frame)
		self:NoteHome(frame)
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
		self.placed = true
	end)
end

-- Move mode shows the mover only while EldoUI may move the window, and
-- like every other box only in the views that take it: the Combat view
-- leaves these windows for All frames. A window EldoUI may not move has
-- its mover hidden, so no view brings its box back.
function Window:ShowMover()
	local mover = self.moverFrame
	if not mover then return end
	local allowed = self:Allowed()
	if allowed and not mover:IsShown() then
		mover:Show()
		E:RestoreMoverOverlay(mover)
	elseif not allowed then
		mover:Hide()
	end
	local on = E:IsMoveMode() and allowed and E:IsMoverActive(mover) and true or false
	mover.overlay:SetShown(on)
	mover:EnableMouse(on)
end

-- Back to Blizzard: the window mover gives the scale back at once, and an
-- open window that still sits on the EldoUI anchor goes back to the spot
-- Blizzard gave it. A closed window is placed by Blizzard when it opens.
function Window:Restore()
	local frame, home, anchor = self:Frame(), self.home, self.anchor
	self.placed = false
	if self.spec.key and E.WindowMoverApply then E:WindowMoverApply(self.spec.key) end
	if frame and home and anchor and frame:IsShown() and #home > 0 then
		Guarded(frame, function()
			local _, relative = frame:GetPoint(1)
			if relative ~= anchor or self:Allowed() then return end
			frame:ClearAllPoints()
			for _, point in ipairs(home) do
				frame:SetPoint(point[1], point[2] or UIParent, point[3], point[4], point[5])
			end
		end)
	end
	self:ShowMover()
end

function Window:Apply()
	local frame = self:Frame()
	if not frame then return end
	self:Hook(frame)
	if self:Allowed() then
		if frame:IsShown() then self:Place() else self:Ensure(frame) end
	else
		self:Restore()
	end
	self:ShowMover()
end

-- Re-place after every Blizzard positioning pass.
local function PlaceShown()
	for _, window in ipairs(windows) do
		local frame = window:Frame()
		if frame and frame:IsShown() and window:Allowed() then window:Place() end
	end
end

function Window:Hook(frame)
	if self.hookedFrame == frame then return end
	self.hookedFrame = frame
	-- Blizzard shows the window first and positions it right after; the
	-- next frame catches both orders.
	frame:HookScript("OnShow", function()
		if not self:Allowed() then return end
		self:Place()
		C_Timer.After(0, function() if frame:IsShown() then self:Place() end end)
	end)
	if not hooked then
		hooked = true
		for _, name in ipairs({ "UpdateUIPanelPositions", "ShowUIPanel", "HideUIPanel" }) do
			if type(_G[name]) == "function" then hooksecurefunc(name, PlaceShown) end
		end
	end
end

function E:EconomyWindow(spec)
	local window = setmetatable({ spec = spec }, Window)
	windows[#windows + 1] = window
	return window
end

-- "Blizzard's place" on the Move windows page (or Shift+right-click on the
-- title bar) sends an economy window back to its EldoUI anchor.
hooksecurefunc(E, "ResetWindow", function(_, key, what)
	if what == "scale" then return end
	for _, window in ipairs(windows) do
		if window.spec.key == key then
			local frame = window:Frame()
			if frame and frame:IsShown() then window:Place() end
		end
	end
end)

-- Move mode shows only the movers of windows the player lets EldoUI move.
hooksecurefunc(E, "ToggleMoveMode", function()
	for _, window in ipairs(windows) do window:ShowMover() end
end)

---------------------------------------------------------------------------
-- Skin helpers shared by the economy windows
---------------------------------------------------------------------------
local slots = setmetatable({}, { __mode = "k" })

-- A flat item slot: Blizzard's slot art invisible, the icon trimmed inside
-- a 1 px EldoUI border. The icon border (quality color) stays the game's.
function E:EconomySlot(button, icon, keep)
	if not Usable(button) or slots[button] then return slots[button] end
	keep = keep or {}
	icon = icon or button.icon or button.Icon
	if icon then keep[icon] = true end
	for _, key in ipairs({ "IconBorder", "IconOverlay", "IconOverlay2", "Count", "Stock", "searchOverlay", "IconQuestTexture" }) do
		if button[key] then keep[button[key]] = true end
	end
	local normal = button.GetNormalTexture and button:GetNormalTexture()
	if normal then normal:SetAlpha(0) end
	local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
	for _, region in ipairs({ button:GetRegions() }) do
		if region:IsObjectType("Texture") and not keep[region] and region ~= highlight then region:SetAlpha(0) end
	end
	if highlight then highlight:SetColorTexture(1, 1, 1, 0.15) end
	if icon then
		E:TrimIcon(icon)
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
		icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	end
	if button.IconBorder then
		button.IconBorder:ClearAllPoints()
		button.IconBorder:SetAllPoints(button)
	end
	local border = CreateFrame("Frame", nil, button)
	border:SetAllPoints()
	border:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
	E:SetTemplate(border)
	slots[button] = border
	return border
end

-- Every texture of a frame (and its named globals) invisible; content kept.
function E:EconomyStrip(frame, ...)
	if not Usable(frame) then return end
	local keep = {}
	for i = 1, select("#", ...) do
		local region = select(i, ...)
		if region then keep[region] = true end
	end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:IsObjectType("Texture") and not keep[region] and region:GetDrawLayer() ~= "HIGHLIGHT" then
			region:SetAlpha(0)
		end
	end
end

-- Money in the Money style (Fonts and text page): E:FormatMoney (Core/Media.lua).
function E:EconomyMoney(copper)
	return self:FormatMoney(copper or 0)
end

---------------------------------------------------------------------------
-- "Already known": recipes, mounts, pets and toys you already
-- have. Only what the game itself reports: the mount and pet journals, the
-- toy box, and the tooltip's own "Already known" line. Results are cached
-- per item and cleared when you learn or collect something.
-- Written from scratch for EldoUI; no code from other addons.
---------------------------------------------------------------------------
local knownCache = {}
local KNOWN_LINE = ITEM_SPELL_KNOWN

local IsSecret = E.Secret

local function TooltipSaysKnown(data)
	if type(data) ~= "table" or type(data.lines) ~= "table" or not KNOWN_LINE then return false end
	for _, line in ipairs(data.lines) do
		local text = line.leftText
		if type(text) == "string" and not IsSecret(text) and text == KNOWN_LINE then return true end
	end
	return false
end

-- More than the one "retrieving item information" line.
local function TooltipComplete(data)
	return type(data) == "table" and type(data.lines) == "table" and #data.lines > 1
end

-- item: link or item ID. Returns true when you already know or own it.
function E:IsItemKnown(item)
	if IsSecret(item) or type(item) == "nil" then return false end
	local cached = knownCache[item]
	if cached ~= nil then return cached end
	local itemID = C_Item.GetItemInfoInstant(item)
	if not itemID then return false end
	local known
	if C_MountJournal and C_MountJournal.GetMountFromItem then
		local ok, mountID = pcall(C_MountJournal.GetMountFromItem, itemID)
		if ok and mountID then
			local isCollected = select(11, C_MountJournal.GetMountInfoByID(mountID))
			known = isCollected and true or false
			knownCache[item] = known
			return known
		end
	end
	if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
		local ok, _, _, _, _, _, _, _, _, _, _, _, speciesID = pcall(C_PetJournal.GetPetInfoByItemID, itemID)
		if ok and speciesID then
			local owned = C_PetJournal.GetNumCollectedInfo(speciesID)
			known = type(owned) == "number" and owned > 0
			knownCache[item] = known
			return known
		end
	end
	if PlayerHasToy and C_ToyBox and C_ToyBox.GetToyInfo and C_ToyBox.GetToyInfo(itemID) then
		known = PlayerHasToy(itemID) and true or false
		knownCache[item] = known
		return known
	end
	-- Recipes and other "teaches you" items: the tooltip says so.
	local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(item)
	if classID == (Enum.ItemClass and Enum.ItemClass.Recipe) or classID == (Enum.ItemClass and Enum.ItemClass.Miscellaneous) then
		local cachedBefore = C_Item.IsItemDataCachedByID and C_Item.IsItemDataCachedByID(itemID) == true
		local ok, data
		if C_TooltipInfo and C_TooltipInfo.GetHyperlink and type(item) == "string" then
			ok, data = pcall(C_TooltipInfo.GetHyperlink, item)
		elseif C_TooltipInfo and C_TooltipInfo.GetItemByID then
			ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
		end
		E.knownTooltipReads = (E.knownTooltipReads or 0) + 1
		known = ok and TooltipSaysKnown(data) or false
		-- Tooltip data can be incomplete before the item is cached: a "no"
		-- is remembered only from a complete tooltip.
		if known or (ok and (cachedBefore or TooltipComplete(data))) then knownCache[item] = known end
		return known
	end
	knownCache[item] = false
	return false
end

-- The tint EldoUI uses for known items (soft green, readable on any skin).
E.knownTint = { 0.35, 0.9, 0.45 }

local knownWatcher = CreateFrame("Frame")
for _, event in ipairs({ "NEW_RECIPE_LEARNED", "NEW_MOUNT_ADDED", "NEW_PET_ADDED", "PET_JOURNAL_LIST_UPDATE",
	"TOYS_UPDATED", "LEARNED_SPELL_IN_TAB", "SKILL_LINES_CHANGED" }) do
	if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(event) then
		pcall(knownWatcher.RegisterEvent, knownWatcher, event)
	end
end
knownWatcher:SetScript("OnEvent", function() wipe(knownCache) end)
