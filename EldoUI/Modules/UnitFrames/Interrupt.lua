-- The player's interrupt beside an active target or focus cast.
local _, E = ...
local M = E:GetModule("UnitFrames")
local CastX = M.CastX
local units = { "target", "focus" }
local ranks = {
	ROGUE = { 1769, 1768, 1767, 1766 },
	WARRIOR = { 6554, 6552, 1672, 1671, 72 },
	MAGE = { 2139 },
	SHAMAN = { 10414, 10413, 10412, 8046, 8045, 8044, 8042 },
}
local listening = false

local function Read(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, value = pcall(fn, ...)
	if ok then return value end
end

local function Number(value)
	return not E.Secret(value) and type(value) == "number" and value == value
		and value > 0 and value < math.huge and value == math.floor(value)
end

local function Interrupt()
	local _, class = UnitClass("player")
	if E.Secret(class) or type(class) ~= "string" then return end
	local book = C_SpellBook
	if not book then return end
	for _, spell in ipairs(ranks[class] or {}) do
		local known = Read(book.IsSpellKnown, spell)
		if not E.Secret(known) and known == true then return spell end
	end
	if class ~= "WARLOCK" then return end
	local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
	local count = Read(book.HasPetSpells)
	if not bank or not Number(count) then return end
	for slot = count, 1, -1 do
		local info = Read(book.GetSpellBookItemInfo, slot, bank)
		if not E.Secret(info) and type(info) == "table" and (not canaccesstable or canaccesstable(info)) then
			local spell = info.spellID
			if Number(spell) and (spell == 19647 or spell == 19244) then
				return spell, slot, bank
			end
		end
	end
end

local function RestoreText(castbar)
	if not castbar.interruptTextEnd then return end
	castbar.textEnd = castbar.interruptTextEnd
	castbar.interruptTextEnd = nil
	if castbar.interruptTargetWidth then
		castbar.targetWidth = castbar.interruptTargetWidth
		castbar.interruptTargetWidth = nil
		castbar.target:SetWidth(castbar.targetWidth)
	end
	castbar.target:ClearAllPoints()
	castbar.target:SetPoint("RIGHT", castbar, "RIGHT", castbar.textEnd, 0)
	CastX.AnchorCastText(castbar)
end

local function Hide(castbar)
	if castbar.myInterrupt then
		castbar.myInterrupt.cooldown:Clear()
		castbar.myInterrupt:Hide()
	end
	RestoreText(castbar)
end

local function Enabled(castbar)
	local frame = castbar and castbar.owner
	return M.active and frame and frame.db and frame.db.enabled and M.OwnFrameAllowed(frame.key)
		and castbar.enabled and castbar.settings.showMyInterrupt == true
end

local function CreateIcon(castbar)
	local icon = E.UIKit.Icon(castbar)
	icon:EnableMouse(false)
	local cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
	cooldown:SetAllPoints(icon.icon)
	cooldown:SetDrawEdge(false)
	cooldown:SetHideCountdownNumbers(true)
	icon.cooldown = cooldown
	icon:Hide()
	castbar.myInterrupt = icon
end

local function Update(castbar)
	if not Enabled(castbar) or not castbar.interruptCasting or not castbar:IsShown() then
		if castbar then Hide(castbar) end
		return
	end
	local spell, slot, bank = Interrupt()
	local durationAPI
	if slot then durationAPI = C_SpellBook.GetSpellBookItemCooldownDuration
	else durationAPI = C_Spell and C_Spell.GetSpellCooldownDuration end
	local iconAPI = C_Spell and C_Spell.GetSpellTexture
	if not spell or type(durationAPI) ~= "function" or type(iconAPI) ~= "function" then
		Hide(castbar)
		return
	end
	local texture = Read(iconAPI, spell)
	if E.Secret(texture) or not Number(texture) then Hide(castbar) return end
	local size = math.max(castbar.barHeight or castbar:GetHeight(), 1)
	local right = castbar.interruptTextEnd or castbar.textEnd or -4
	local left = castbar.textLeft or 4
	if castbar.marker:IsShown() then left = left + (castbar.markerSize or 0) + 3 end
	local targetGap = castbar.targetShown and 6 or 0
	local available = (castbar.barWidth or 0) + right - left
	if available < size + 4 + targetGap + 1 then Hide(castbar) return end
	local icon = castbar.myInterrupt
	if not icon then return end
	castbar.interruptTextEnd = right
	castbar.interruptTargetWidth = castbar.interruptTargetWidth or castbar.targetWidth
	icon:SetSize(size, size)
	icon:ClearAllPoints()
	icon:SetPoint("RIGHT", castbar, "RIGHT", right, 0)
	icon:SetFrameLevel(castbar:GetFrameLevel() + 1)
	E:SetTemplate(icon)
	icon:SetIcon(E:ClientIcon(texture))
	castbar.textEnd = right - size - 4
	castbar.targetWidth = math.min(castbar.interruptTargetWidth or 0, (available - size - 4 - targetGap) * 0.35)
	castbar.target:SetWidth(castbar.targetWidth)
	castbar.target:ClearAllPoints()
	castbar.target:SetPoint("RIGHT", castbar, "RIGHT", castbar.textEnd, 0)
	CastX.AnchorCastText(castbar)
	local duration
	if slot then duration = Read(durationAPI, slot, bank, true)
	else duration = Read(durationAPI, spell, true) end
	local drawn = false
	if type(duration) ~= "nil" and icon.cooldown.SetCooldownFromDurationObject then
		drawn = pcall(icon.cooldown.SetCooldownFromDurationObject, icon.cooldown, duration, true)
	end
	if not drawn then icon.cooldown:Clear() end
	icon:Show()
end

local function Refresh()
	for _, unit in ipairs(units) do
		local frame = M.frames[unit]
		if frame then Update(frame.castbar) end
	end
end

local function Listen()
	local wanted = false
	for _, unit in ipairs(units) do
		local frame = M.frames[unit]
		if frame and Enabled(frame.castbar) then wanted = true end
	end
	if wanted == listening then return end
	listening = wanted
	for _, event in ipairs({ "SPELLS_CHANGED", "SPELL_UPDATE_COOLDOWN", "PET_BAR_UPDATE_COOLDOWN" }) do
		if wanted then M:RegisterEvent(event, Refresh) else M:UnregisterEvent(event) end
	end
	if wanted then M:RegisterUnitEvent("UNIT_PET", "player", Refresh)
	else M:UnregisterUnitEvent("UNIT_PET", "player") end
end

function M:StopInterruptIcons()
	for _, unit in ipairs(units) do
		local frame = self.frames[unit]
		if frame and frame.castbar then
			frame.castbar.interruptCasting = nil
			Hide(frame.castbar)
		end
	end
	Listen()
end

CastX.RegisterCastHook(function(event, castbar, unit)
	if E.Secret(unit) or (unit ~= "target" and unit ~= "focus") then return end
	if event == "layout" then
		castbar.interruptTextEnd = nil
		castbar.interruptTargetWidth = nil
		if Enabled(castbar) and not castbar.myInterrupt then CreateIcon(castbar) end
		if not castbar.interruptHiddenHook then
			castbar.interruptHiddenHook = true
			castbar:HookScript("OnHide", function(self)
				self.interruptCasting = nil
				Hide(self)
			end)
		end
	elseif event == "start" or event == "delayed" or event == "channelUpdate" then
		castbar.interruptCasting = true
	elseif event == "stop" or event == "fail" or event == "interrupted" or event == "hold" then
		castbar.interruptCasting = nil
	end
	Listen()
	Update(castbar)
end)
