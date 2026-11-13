-- EldoUI Quest Starter Drops: the nameplate icon.
--
-- Hung on each plate through the Nameplates module's plate callbacks
-- (ADDED, LAYOUT, REMOVED, MODE) and GetPlateAnchor, so it follows the
-- plate's scale and alpha in every plate style. Positions: above the name,
-- left of the bar (outside the raid marker) or right of the bar (after the
-- elite and quest icons). The plate's GUID is read only when the game
-- shows it; a secret GUID shows nothing. Looks: Scroll, Exclamation, Dot,
-- Forever bronze and Color-blind safe (the style presets).
local _, E = ...
local L = E.L
local Key = E.Key
local QD = E:GetModule("QuestDrops")

local SCROLL = "Interface\\Icons\\INV_Scroll_03"
local EXCLAMATION = "Interface\\GossipFrame\\AvailableQuestIcon"
-- EldoUI's named Bronze accent (General > Accent color).
local BRONZE = "C79C6E"

local icons = {}     -- unit token -> icon frame (shown or not)
local free = {}

local function NP()
	local module = E.modules.Nameplates
	if module and module.active and module.RegisterPlateCallback then return module end
end

local function HexColor(hex)
	return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

local function NewIcon()
	local icon = table.remove(free)
	if icon then return icon end
	icon = CreateFrame("Frame", nil, UIParent)
	icon:SetFrameStrata("MEDIUM")
	E:SetTemplate(icon)
	icon.texture = icon:CreateTexture(nil, "ARTWORK")
	icon.texture:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	icon.texture:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	icon.mark = E:CreateText(icon, E.tokens.size.tiny, "CENTER")
	icon.mark:SetPoint("CENTER", 0, 0)
	icon:EnableMouse(false)
	icon:Hide()
	return icon
end

-- Paint an icon in the chosen look; colors read when drawn.
function QD:PaintIcon(icon)
	local look = self.db.plateLook
	local size = self.db.plateSize or 14
	icon:SetSize(size, size)
	icon.mark:SetText("")
	icon.texture:SetVertexColor(1, 1, 1)
	E:SetTemplate(icon)
	if look == "scroll" or look == "bronze" then
		icon.texture:SetTexture(SCROLL)
		E:TrimIcon(icon.texture)
		if look == "bronze" then
			local r, g, b = HexColor(BRONZE)
			if E:SkinFlag("bronze") then r, g, b = E:SkinBronze() end
			icon:SetBackdropBorderColor(r, g, b, 1)
		end
	elseif look == "exclamation" then
		icon.texture:SetTexture(EXCLAMATION)
		icon.texture:SetTexCoord(0, 1, 0, 1)
		icon:SetBackdropBorderColor(0, 0, 0, 0)
		icon:SetBackdropColor(0, 0, 0, 0)
	elseif look == "dot" then
		icon.texture:SetColorTexture(unpack(E.media.accentColor))
		icon:SetSize(math.max(6, math.floor(size * 0.6)), math.max(6, math.floor(size * 0.6)))
	else -- safe: a color-blind safe yellow square with a mark, so the shape carries it too
		icon.texture:SetColorTexture(unpack(E.tokens.palette.safe.yellow))
		icon.mark:SetText("!")
		icon.mark:SetTextColor(0, 0, 0)
	end
end

-- Right of the bar: after the plate's elite and quest icons.
local function RightOffset()
	local module = E.modules.Nameplates
	local db = module and module.db and module.db.icons
	local x = 3
	if type(db) == "table" then
		if db.classification then x = x + (tonumber(db.classificationSize) or 14) + 2 end
		if db.quest then x = x + (tonumber(db.questSize) or 14) + 2 end
	end
	return x
end

function QD:PlaceIcon(icon, unit)
	local module = NP()
	if not module then return false end
	icon:ClearAllPoints()
	local position = self.db.platePosition
	if position == "top" then
		local frame, _, _, offset = module:GetPlateAnchor(unit, "text")
		if not frame then return false end
		icon:SetParent(frame)
		icon:SetPoint("BOTTOM", frame, "TOP", 0, (offset or 0) + 2)
	else
		local frame = module:GetPlateAnchor(unit)
		if not frame then return false end
		icon:SetParent(frame)
		if position == "left" then
			icon:SetPoint("RIGHT", frame, "LEFT", -22, 0)
		else
			icon:SetPoint("LEFT", frame, "RIGHT", RightOffset(), 0)
		end
	end
	icon:SetFrameLevel(icon:GetParent():GetFrameLevel() + 5)
	return true
end

function QD:ReleaseIcon(unit)
	local icon = icons[unit]
	if not icon then return end
	icons[unit] = nil
	icon:Hide()
	icon:ClearAllPoints()
	icon:SetParent(UIParent)
	free[#free + 1] = icon
end

-- Show or hide the icon on one plate.
function QD:UpdateUnit(unit, repaint)
	if not (self:Running() and self.db.plates) then
		self:ReleaseIcon(unit)
		return
	end
	local hints = self:HintsForUnit(unit)
	if not hints or #hints == 0 then
		self:ReleaseIcon(unit)
		return
	end
	local icon = icons[unit]
	local fresh = not icon
	if fresh then
		icon = NewIcon()
		icons[unit] = icon
	end
	if fresh or repaint then self:PaintIcon(icon) end
	if self:PlaceIcon(icon, unit) then
		icon:Show()
	else
		self:ReleaseIcon(unit)
	end
end

function QD:IconFor(unit)
	return icons[unit]
end

local function OnPlate(event, unit)
	if event == "ADDED" or event == "LAYOUT" then
		if unit then QD:UpdateUnit(unit, event == "LAYOUT") end
	elseif event == "REMOVED" then
		if unit then QD:ReleaseIcon(unit) end
	elseif event == "MODE" then
		for token in pairs(icons) do QD:ReleaseIcon(token) end
	end
end
QD.OnPlate = OnPlate

-- Every plate again (quest log, bags or settings changed).
function QD:RefreshPlates(repaint)
	for token in pairs(icons) do self:UpdateUnit(token, repaint) end
	if not (self:Running() and self.db.plates and NP()) then return end
	for i = 1, 40 do
		local unit = "nameplate" .. i
		if not icons[unit] and UnitExists(unit) then self:UpdateUnit(unit, true) end
	end
end

local registered = false
function QD:StartPlates()
	local module = E.modules.Nameplates
	if module and module.RegisterPlateCallback then
		module:RegisterPlateCallback("QuestDrops", OnPlate)
		registered = true
	end
	self:RefreshPlates(true)
end

function QD:StopPlates()
	local module = E.modules.Nameplates
	if registered and module and module.UnregisterPlateCallback then module:UnregisterPlateCallback("QuestDrops") end
	registered = false
	for token in pairs(icons) do self:ReleaseIcon(token) end
end

QD.PLATE_LOOK_TITLE = E:TranslateValues({ scroll = E.Key("Scroll"), exclamation = E.Key("Exclamation mark"), dot = E.Key("Dot"), bronze = E.Key("Forever bronze"),
	safe = E.Key("Color-blind safe") })
