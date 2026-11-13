-- EldoUI Map Notes: the button on the world map and its menu.
--
-- A small EldoUI box at the top right of the map canvas. Click: a menu with
-- "Show map notes" (every EldoUI pin, Core/MapPins.lua), one tick per
-- group with its count on this map, and "Also on continent maps" with one
-- tick per group that may show there. Shift-click: show or hide everything.
-- The same ticks also go into the world map's own filter menu through
-- Menu.ModifyMenu, Blizzard's public hook for addon menu entries.
--
-- The button is our own frame parented to WorldMapFrame; nothing is added
-- to Blizzard's tables (no AddOverlayFrame, which taints). If another addon
-- already has a button in that corner (HandyNotes plugins do), ours steps
-- left of it.
local _, E = ...
local L = E.L
local M = E.MapNotes

local Try = M.Try
local BUTTON = 26

---------------------------------------------------------------------------
-- Menu (shared by the button and the map's filter menu)
---------------------------------------------------------------------------
local function ShownMap()
	local map = M.WorldMap and M.WorldMap()
	local id = map and map.GetMapID and map:GetMapID()
	if issecretvalue and issecretvalue(id) then return end
	return id
end

local function GroupLabel(layer, uiMapID)
	local label = E:Translate(layer.title) or layer.id
	-- No count for a group this continent or world map doesn't draw.
	if uiMapID and not E:MapPinGroupOnMap(layer.id, uiMapID) then return label end
	if layer.count and uiMapID then
		local ok, n = pcall(layer.count, uiMapID)
		if ok and type(n) == "number" and n > 0 then label = ("%s  " .. E:TextHex("secondary") .. "%d|r"):format(label, n) end
	end
	return label
end

function M:BuildMenu(root, uiMapID, compact)
	if not compact then root:CreateTitle(M.AccentHex() .. L["Map Notes"] .. "|r") end
	root:CreateCheckbox(L["Show map notes"], function() return E:MapPinsShown() end, function()
		M:Toggle(not E:MapPinsShown())
	end)
	root:CreateDivider()
	for _, layer in ipairs(E:MapPinLayers()) do
		local ok, available = pcall(layer.available or function() return true end)
		if ok and available then
			local id = layer.id
			root:CreateCheckbox(GroupLabel(layer, uiMapID), function()
				local groups = M.db.groups
				return not (type(groups) == "table" and groups[id] == false)
			end, function()
				local groups = M.db.groups
				local on = type(groups) == "table" and groups[id] == false
				E:SetMapPinGroupShown(id, on)
				M:UpdateButton()
			end)
		end
	end
	local continent
	for _, layer in ipairs(E:MapPinLayers()) do
		local ok, available = pcall(layer.available or function() return true end)
		if ok and available and E:MapPinGroupWideTick(layer.id) then
			local id = layer.id
			continent = continent or root:CreateButton(L["Also on continent maps"])
			continent:CreateCheckbox(E:Translate(layer.title) or id, function() return E:MapPinGroupOnWideMaps(id) end, function()
				E:SetMapPinGroupOnWideMaps(id, not E:MapPinGroupOnWideMaps(id))
			end)
		end
	end
	root:CreateDivider()
	root:CreateCheckbox(L["On the minimap"], function() return M.db.minimapPins end, function()
		M.db.minimapPins = not M.db.minimapPins
		E:RefreshAllMapPins()
	end)
	root:CreateCheckbox(L["Hide completed"], function() return M.db.hideDone end, function()
		M.db.hideDone = not M.db.hideDone
		E:RefreshAllMapPins()
	end)
	local hidden = M:HiddenCount()
	if hidden > 0 then
		root:CreateButton((L["Show hidden points again (%d)"]):format(hidden), function() M:ResetHidden() end)
	end
	if not compact then
		if M.HandyNotes and M:HandyNotes() then
			root:CreateButton(L["Open HandyNotes settings"], function() M:OpenHandyNotes() end)
		end
	end
end

---------------------------------------------------------------------------
-- Button
---------------------------------------------------------------------------
local button

local function Container(map)
	return map.ScrollContainer or (map.GetCanvasContainer and map:GetCanvasContainer())
end

-- Step left of other addons' buttons in the top right corner.
local function Place()
	local map = M.WorldMap and M.WorldMap()
	if not (button and map) then return end
	local container = Container(map)
	if not container then return end
	local top, right = container:GetTop(), container:GetRight()
	local offset = 4
	if top and right then
		local leftmost = right - offset
		local function Scan(parent)
			for _, child in ipairs({ parent:GetChildren() }) do
				if child ~= button and child.IsShown and child:IsShown() and child.GetTop then
					local ct, cr, cl = child:GetTop(), child:GetRight(), child:GetLeft()
					local w, h = child:GetWidth() or 0, child:GetHeight() or 0
					if ct and cr and cl and w > 0 and w <= 48 and h <= 48 and math.abs(ct - top) <= 40 and cr > leftmost - 4 and cr <= right + 4 then
						leftmost = math.min(leftmost, cl - 4)
					end
				end
			end
		end
		Scan(map)
		Scan(container)
		offset = right - leftmost
	end
	button:ClearAllPoints()
	button:SetPoint("TOPRIGHT", container, "TOPRIGHT", -offset, -4)
end

function M:UpdateButton()
	if not button then return end
	local show = self.active and self.db.mapButton
	button:SetShown(show and true or false)
	if not show then return end
	local on = E:MapPinsShown()
	button.underline:SetShown(on)
	button.icon:SetDesaturated(not on)
	button.icon:SetAlpha(on and 1 or 0.45)
	local c = E.media.accentColor
	button.underline:SetColorTexture(c[1], c[2], c[3], 1)
end

function M:CreateButton(map)
	if button or not map then return end
	local container = Container(map)
	if not container then return end
	button = CreateFrame("Button", "EldoUI_MapNotesButton", map)
	button:SetSize(BUTTON, BUTTON)
	button:SetFrameStrata("HIGH")
	button:SetFrameLevel((container:GetFrameLevel() or 1) + 60)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	E:SetTemplate(button)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", 3, -3)
	button.icon:SetPoint("BOTTOMRIGHT", -3, 3)
	E:SetClientAtlas(button.icon, "VignetteLoot", "Interface\\Icons\\INV_Misc_Map_01")
	button.underline = button:CreateTexture(nil, "OVERLAY")
	button.underline:SetHeight(2 * (E.pixel or 1))
	button.underline:SetPoint("BOTTOMLEFT", E.pixel or 1, E.pixel or 1)
	button.underline:SetPoint("BOTTOMRIGHT", -(E.pixel or 1), E.pixel or 1)
	button.hover = button:CreateTexture(nil, "HIGHLIGHT")
	button.hover:SetAllPoints()
	button.hover:SetColorTexture(1, 1, 1, E.tokens.hover.control)
	button:SetScript("OnClick", function(owner, mouse)
		if E:IsOptionsLinkClick(owner, mouse) then return end
		if IsShiftKeyDown and IsShiftKeyDown() then
			M:Toggle(not E:MapPinsShown())
			return
		end
		E.UIKit.ContextMenu(owner, function(_, root) M:BuildMenu(root, ShownMap()) end, { at = "owner" })
	end)
	button:SetScript("OnEnter", function(owner)
		GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
		E.UIKit.TipTitle(GameTooltip, L["Map Notes"])
		E.UIKit.TipText(GameTooltip, E:MapPinsShown() and L["Your EldoUI map pins are shown."] or L["Your EldoUI map pins are hidden."])
		E:TooltipHint(GameTooltip, { L["Click"], L["groups and settings"] })
		E:TooltipHint(GameTooltip, { L["Shift-click"], L["show or hide everything"] })
		local key = GetBindingKey and GetBindingKey("ELDOUI_MAPNOTES_TOGGLE")
		if key then E.UIKit.TipText(GameTooltip, (L["Key: %s"]):format(key)) end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	E:BindOptionsLink(button, { page = "module:MapNotes" })
	map:HookScript("OnShow", function()
		if C_Timer and C_Timer.After then C_Timer.After(0, Place) else Place() end
	end)
	if map.OnMapChanged then hooksecurefunc(map, "OnMapChanged", function()
		if C_Timer and C_Timer.After then C_Timer.After(0, Place) else Place() end
	end) end
	Place()
	self:UpdateButton()
	self:HookFilterMenu()
end

-- The world map's own filter menu (the tag Blizzard's code gives it).
local filterHooked
function M:HookFilterMenu()
	local menu = rawget(_G, "Menu")
	if filterHooked or not (menu and menu.ModifyMenu) then return end
	filterHooked = true
	menu.ModifyMenu("MENU_WORLD_MAP_TRACKING", function(_, root)
		if not (M.active and M.db.filterMenu) then return end
		if E.BlizzardAllowed and not E:BlizzardAllowed("world-map-quest-log", "improve") then return end
		root:CreateDivider()
		root:CreateTitle(L["EldoUI map notes"])
		M:BuildMenu(root, ShownMap(), true)
	end)
end

function M:EnableButton()
	self:UpdateButton()
end

function M:DisableButton()
	if button then button:Hide() end
end

-- Key binding (Core/Bindings.lua calls this).
function M:BindingToggle()
	if not self.active then
		E:Print(E:ModuleOffHint("MapNotes"))
		return
	end
	self:Toggle(not E:MapPinsShown(), true)
end
