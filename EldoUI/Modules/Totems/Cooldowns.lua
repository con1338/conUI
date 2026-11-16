-- EldoUI Shaman Totems: the cooldown bar. Your shield (with its charges),
-- the weapon imbue on each hand, Reincarnation with your Ankh count and the
-- shaman cooldowns you know, plus optional ready icons for key spells.
-- Click an icon to cast it (shield, imbue, spell); right-click the shield
-- or an imbue to pick which one it casts. Spells you don't know never show.
--
-- How it reads the game:
--   * The shield is an aura slot of the game's own aura container: the
--     client shows the live shield (time and charges) over a faded copy of
--     its icon, so a missing shield shows faded in combat too, while EldoUI
--     never reads the aura. The missing glow needs a read, so it shows out
--     of combat only.
--   * Imbues come from the game's weapon enchant info, which stays
--     readable in combat; a secret answer leaves the icon as it was.
--   * Cooldowns are the game's duration objects drawn by the cooldown
--     widget; ready icons use the game's own "cooldown runs" flag.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local M = E:GetModule("ShamanTotems")
local D = E.ShamanData
local Try = M.Try
local Plain = E.Plain
local Secret = E.Secret

local CD = {}
M.Cooldowns = CD
-- Every cooldown read goes through EldoUI's one cooldown source.
local Source = E.CombatKit and E.CombatKit.Cooldowns
M:AddPart("cooldowns", CD)

local DEFAULT_POINT = { "CENTER", "UIParent", "CENTER", 0, -268 }
local MAX_ICONS = 14
local MAIN, OFF = INVSLOT_MAINHAND or 16, INVSLOT_OFFHAND or 17

E:RegisterGlowUser("totemMissing", {
	title = "Shaman Totems: missing shield or imbue",
	desc = "The shield or imbue icon of the shaman cooldown bar while it is missing (out of combat).",
	order = 48,
	button = true,
	default = { style = "pixel", colorMode = "custom", color = { 1, 0.27, 0.27 } },
})

---------------------------------------------------------------------------
-- What the bar shows, in order
---------------------------------------------------------------------------
-- The first known spell of a list, or the picked one when it is known.
local function FirstKnown(list, picked)
	local first
	for _, item in ipairs(list) do
		if M:Known(item.id) then
			if item.key == picked then return item end
			first = first or item
		end
	end
	return first
end
CD.FirstKnown = FirstKnown

local function HasOffHandWeapon()
	local id = GetInventoryItemID and Plain(Try(GetInventoryItemID, "player", OFF))
	if type(id) ~= "number" then return false end
	local _, _, _, _, _, classID = Try(C_Item.GetItemInfoInstant, id)
	return Plain(classID) == (Enum.ItemClass and Enum.ItemClass.Weapon or 2)
end
CD.HasOffHandWeapon = HasOffHandWeapon

---------------------------------------------------------------------------
-- Role sets: until the player ticks spells themselves, the bar shows the
-- set for their role (healer, melee or caster). The role comes from the
-- set picked in the options, else the Role page (or the role the game
-- gives the character), else the talents the character knows.
---------------------------------------------------------------------------
local ROLE_FROM_GAME = { healer = "healer", tank = "melee" }

-- The set the bar uses now: "healer", "melee" or "caster".
function M:CooldownRole()
	local choice = self.db.cooldowns.roleSet
	if choice == "healer" or choice == "melee" or choice == "caster" then return choice end
	local role = E.GetRole and E:GetRole() or "none"
	if role == "none" and E.DetectRole then
		local detected, source = E:DetectRole()
		-- The class alone says nothing about a shaman's way.
		if source ~= "class" then role = detected or "none" end
	end
	if ROLE_FROM_GAME[role] then return ROLE_FROM_GAME[role] end
	for _, talent in ipairs(D.ROLE_TALENTS) do
		if (role == "none" or talent.role ~= "healer") and self:Known(talent.id) then return talent.role end
	end
	return "melee"
end

local function InSet(spell, role)
	return spell.roles == "all" or spell.roles == role
end

-- spells and readySpells as the role set has them.
local function RoleTicks(role)
	local spells, ready = {}, {}
	for _, spell in ipairs(D.SPELLS) do spells[spell.key] = InSet(spell, role) end
	for _, spell in ipairs(D.READY) do ready[spell.key] = InSet(spell, role) end
	return spells, ready
end
CD.RoleTicks = RoleTicks

local function Same(ticks, saved)
	for key, on in pairs(ticks) do
		if (saved[key] and true or false) ~= on then return false end
	end
	return true
end

-- Every tick on: what the bar showed before role sets, for a profile that
-- never had them.
local function AllOn(list)
	local ticks = {}
	for _, spell in ipairs(list) do ticks[spell.key] = true end
	return ticks
end

-- Fill the ticks with the role set while the player has not changed them.
-- db.filledFor remembers "<choice>:<role>" the ticks were last filled
-- for, or "<choice>:own" once the player changed one.
function CD:FillRoleSet()
	local db = M.db.cooldowns
	local choice = db.roleSet or "auto"
	local role = M:CooldownRole()
	local filled = db.filledFor or ""
	local filledChoice, filledRole = filled:match("^([^:]*):(.*)$")
	local own
	if filled == "" then
		-- Ticks from before role sets: anything off is the player's own pick.
		own = not (Same(AllOn(D.SPELLS), db.spells) and Same(AllOn(D.READY), db.readySpells))
	elseif filledChoice ~= choice or filled == "reset" then
		own = false -- a new set was picked: it replaces the ticks
	elseif filledRole == "own" then
		own = true
	else
		local spells, ready = RoleTicks(filledRole)
		own = not (Same(spells, db.spells) and Same(ready, db.readySpells))
	end
	if own then
		db.filledFor = choice .. ":own"
		return false
	end
	local spells, ready = RoleTicks(role)
	for key, on in pairs(spells) do db.spells[key] = on end
	for key, on in pairs(ready) do db.readySpells[key] = on end
	db.filledFor = choice .. ":" .. role
	return true
end

-- The player's own ticks give way to the role set again.
function CD:ResetRoleSet()
	M.db.cooldowns.filledFor = "reset"
	M:Refresh()
end

-- True while the ticks are the player's own.
function CD:OwnTicks()
	return (M.db.cooldowns.filledFor or ""):find(":own$") ~= nil
end

-- A new role on the Role page: the automatic set follows it.
if E.RegisterRoleCallback then
	E:RegisterRoleCallback(function()
		if M:Drawing() then M:Refresh() end
	end)
end

-- The list of icons: { kind, item (data entry), spell (highest rank) }.
function CD:Items()
	local db = M.db.cooldowns
	self:FillRoleSet()
	local items = {}
	if db.shield then
		local shield = FirstKnown(D.SHIELDS, db.shieldPick)
		if shield then items[#items + 1] = { kind = "shield", item = shield } end
	end
	local imbue = FirstKnown(D.IMBUES, db.imbuePick)
	if imbue then
		if db.imbueMain then items[#items + 1] = { kind = "imbue", item = imbue, slot = MAIN } end
		if db.imbueOff and HasOffHandWeapon() then
			local off = FirstKnown(D.IMBUES, db.imbueOffPick) or imbue
			items[#items + 1] = { kind = "imbue", item = off, slot = OFF }
		end
	end
	for _, spell in ipairs(D.SPELLS) do
		if db.spells[spell.key] and M:Known(spell.id) then items[#items + 1] = { kind = "spell", item = spell } end
	end
	if db.ready then
		for _, spell in ipairs(D.READY) do
			if db.readySpells[spell.key] and M:Known(spell.id) then items[#items + 1] = { kind = "ready", item = spell } end
		end
	end
	for _, entry in ipairs(items) do
		local info = M:Spell(entry.item.id)
		entry.spell, entry.name, entry.icon = info.id, info.name, info.icon
	end
	return items
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function IconTip(button, tooltip)
	local entry = button.entry
	if not entry then return end
	if tooltip.SetSpellByID and entry.spell then tooltip:SetSpellByID(entry.spell) end
	if entry.kind == "imbue" then
		E.UIKit.TipText(tooltip, entry.slot == OFF and L["Off-hand weapon"] or L["Main-hand weapon"])
	elseif entry.kind == "ready" then
		E.UIKit.TipText(tooltip, L["Lit while it is ready to cast."])
	end
	local pick = entry.kind == "shield" or entry.kind == "imbue"
	if entry.item.passive then
		E.UIKit.TipText(tooltip, L["The game uses it on its own; the number is how many you carry."])
	elseif InCombatLockdown() then
		if pick then E.UIKit.TipText(tooltip, L["Picks change out of combat."]) end
	elseif pick then
		E:TooltipHint(tooltip, { L["Click"], L["cast it"] },
			{ L["Right-click"], entry.kind == "shield" and L["pick the shield"] or L["pick the imbue"] })
	else
		E:TooltipHint(tooltip, { L["Click"], L["cast it"] })
	end
end

-- The setting a shield or imbue icon's pick lives in.
local function PickField(entry)
	if entry.kind == "shield" then return "shieldPick", D.SHIELDS end
	if entry.kind == "imbue" then return entry.slot == OFF and "imbueOffPick" or "imbuePick", D.IMBUES end
end

-- Right-click on the shield or an imbue icon: the ones you know, to pick
-- the one the icon casts. Out of combat only, like every pick.
function CD:OpenPickMenu(button)
	local entry = button and button.entry
	if not entry or InCombatLockdown() then return end
	local field, list = PickField(entry)
	if not field then return end
	local db = M.db.cooldowns
	local Kit = E.UIKit
	local function Pick(key)
		db[field] = key
		M:Refresh()
	end
	Kit.ContextMenu(button, function(_, root)
		root:CreateTitle(entry.kind == "shield" and L["Which shield"]
			or (entry.slot == OFF and L["Off-hand imbue spell"] or L["Main-hand imbue spell"]))
		root:CreateRadio(field == "imbueOffPick" and L["Same as the main hand"] or L["First one you know"],
			function() return (db[field] or "") == "" end, function() Pick("") end)
		for _, item in ipairs(list) do
			if M:Known(item.id) then
				root:CreateRadio(M.SpellName(item.id) or item.key, function() return db[field] == item.key end,
					function() Pick(item.key) end)
			end
		end
	end)
end
CD.PickField = PickField

local function PickClick(button, mouse, down)
	if mouse ~= "RightButton" or down then return end
	CD:OpenPickMenu(button)
end

function CD:Build()
	if self.frame then return end
	local holder = CreateFrame("Frame", "EldoUI_ShamanCooldownsHolder", UIParent, "SecureHandlerStateTemplate")
	holder:SetAllPoints(UIParent)
	holder:SetFrameStrata("LOW")
	self.holder = holder
	local frame = CreateFrame("Frame", "EldoUI_ShamanCooldowns", holder)
	frame:SetSize(220, 28)
	frame:SetFrameStrata("LOW")
	self.frame = frame
	self.buttons = {}
	for index = 1, MAX_ICONS do
		local button = M.NewButton(frame, "EldoUI_ShamanCooldown" .. index, "SecureActionButtonTemplate", M.MASQUE_COOLDOWNS)
		button:RegisterForClicks("AnyUp", "AnyDown")
		button:SetAttribute("type", nil)
		button.tip = IconTip
		button:HookScript("PostClick", PickClick)
		button:HookScript("OnEnter", M.ShowTip)
		button:HookScript("OnLeave", GameTooltip_Hide)
		-- A thin bar under an imbue icon: the time the imbue has left.
		button.bar = E:CreateStatusBar(button)
		button.bar:SetHeight(3)
		button.bar:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -1)
		button.bar:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -1)
		button.bar:SetMinMaxValues(0, 1)
		button.bar:Hide()
		E:SetTemplate(button.bar, true)
		button:Hide()
		self.buttons[index] = button
	end
	E:CreateMover(frame, "EldoUI_ShamanCooldowns", L["Shaman Cooldowns"], DEFAULT_POINT,
		{ layoutAlias = "EldoUI_TotemBar", combat = true, sample = { kind = "icons", count = 6 } })
end

-- The shield's aura slot: the client's button over the shield icon. It
-- passes clicks through to the icon (which casts the shield).
local function ShieldSlot(button, ids, size)
	local W = E.AuraWidget
	if not (W and W.SlotsAvailable and W.SlotsAvailable()) then return nil end
	local filter = "HELPFUL|PLAYER"
	local include = {}
	for _, id in ipairs(ids) do include[id] = true end
	local settings = { size = size, duration = "SWIPE", durationSize = math.max(math.floor(size * 0.38), 9),
		countSize = math.max(math.floor(size * 0.42), 10), tooltip = false }
	local sorted = { unpack(ids) }
	table.sort(sorted)
	return W.CreateSlots(button, { unit = "player", poolKey = ("shield:%s:%s:%s"):format(tostring(button:GetName() or button), size,
		table.concat(sorted, ",")), slots = { {
		key = "shield", filter = filter, candidateFilters = { includeSpellIDs = include },
		initialize = W.SlotIcon(settings, function(aura)
			aura:ClearAllPoints()
			aura:SetPoint("CENTER", button, "CENTER")
			aura:SetFrameLevel(button:GetFrameLevel() + 3)
		end, function(aura)
			pcall(aura.SetMouseClickEnabled, aura, false)
			pcall(aura.SetMouseMotionEnabled, aura, false)
		end),
	} } })
end

-- Every rank's spell ID of the known shields (rank 1, the one you cast and
-- any other ID its aura can carry).
local function ShieldIds()
	local ids, seen = {}, {}
	local function Add(id)
		if not seen[id] then seen[id] = true ids[#ids + 1] = id end
	end
	for _, shield in ipairs(D.SHIELDS) do
		Add(shield.id)
		Add(M:Spell(shield.id).id)
		for _, id in ipairs(shield.auras or {}) do Add(id) end
	end
	table.sort(ids)
	return ids
end

---------------------------------------------------------------------------
-- Layout and secure attributes (out of combat)
---------------------------------------------------------------------------
function CD:Apply()
	local db = M.db.cooldowns
	if not (M:Drawing() and db.enabled) then
		self:Disable()
		return
	end
	self:Build()
	local size, spacing = db.size, db.spacing
	local items = self:Items()
	self.items = items
	local shown = math.min(#items, MAX_ICONS)
	for index, button in ipairs(self.buttons) do
		local entry = items[index]
		button.entry = entry
		M.PaintButton(button)
		if entry then
			button:SetSize(size, size)
			button:ClearAllPoints()
			local offset = (index - 1) * (size + spacing)
			if M.db.vertical then
				button:SetPoint("TOP", self.frame, "TOP", 0, -offset)
			else
				button:SetPoint("LEFT", self.frame, "LEFT", offset, 0)
			end
			button.icon:SetTexture(entry.icon)
			local castable = not entry.item.passive and entry.name
			if entry.kind == "imbue" and entry.slot == OFF and castable then
				-- An off-hand imbue: cast it, then put it on the off hand.
				button:SetAttribute("type1", "macro")
				button:SetAttribute("macrotext1", ("/cast %s\n/use %d"):format(entry.name, OFF))
				button:SetAttribute("spell", nil)
			else
				button:SetAttribute("type1", castable and "spell" or nil)
				button:SetAttribute("spell", castable and entry.name or nil)
				button:SetAttribute("macrotext1", nil)
			end
			local color = E.media.accentColor
			button.bar:SetStatusBarColor(color[1], color[2], color[3], 1)
			button:Show()
		else
			button:SetAttribute("type1", nil)
			button:SetAttribute("spell", nil)
			button:SetAttribute("macrotext1", nil)
			button:Hide()
		end
	end
	-- The shield's aura slot (rebuilt when the shield or the size changes).
	local shieldButton = items[1] and items[1].kind == "shield" and self.buttons[1] or nil
	local signature = shieldButton and (table.concat(ShieldIds(), ",") .. ":" .. size .. ":" .. (E.AuraWidget and E.AuraWidget.ThemeKey and E.AuraWidget.ThemeKey() or "")) or nil
	if signature ~= self.shieldSignature then
		if self.shieldSlot then E.AuraWidget.Release(self.shieldSlot) end
		self.shieldSlot = shieldButton and ShieldSlot(shieldButton, ShieldIds(), size) or nil
		self.shieldSignature = signature
	end
	if M.db.masque then E:MasqueReSkin(M.MASQUE_COOLDOWNS) end
	local length = shown > 0 and (shown * size + (shown - 1) * spacing) or size
	if M.db.vertical then self.frame:SetSize(size, length) else self.frame:SetSize(length, size + 4) end
	self.frame:SetShown(shown > 0)
	self:UpdateVisibility()
	local mover = E.movers.EldoUI_ShamanCooldowns
	if mover then mover:Show() end
end

function CD:UpdateVisibility()
	if not self.holder then return end
	if self.visibilityBlock ~= M.db.visibility then E:DetachVisibility(self.holder) end
	if E:IsVisibilityAttached(self.holder) then
		E:UpdateVisibility(self.holder)
	else
		self.visibilityBlock = M.db.visibility
		E:AttachVisibility(self.holder, M.db.visibility, {
			watch = self.frame,
			secure = true,
			forceShow = function() return E.IsMoveMode and E:IsMoveMode() end,
		})
	end
end

---------------------------------------------------------------------------
-- Display (in combat too)
---------------------------------------------------------------------------
-- { has, secondsLeft } of a hand's temporary enchant; nil when the game
-- doesn't say.
local function Enchant(slot)
	if not (C_Item and C_Item.GetWeaponEnchantInfo) then return nil end
	local weaponSlot = Enum.WeaponSlot and (slot == OFF and Enum.WeaponSlot.OffHand or Enum.WeaponSlot.MainHand)
	local list = Try(C_Item.GetWeaponEnchantInfo, weaponSlot or slot)
	if type(list) ~= "table" then return nil end
	local permanent = Enum.ItemEnchantType and Enum.ItemEnchantType.Permanent
	for _, enchant in ipairs(list) do
		local has, kind, left = enchant.hasEnchant, enchant.enchantType, enchant.timeLeft
		if Secret(has) or Secret(kind) or Secret(left) then return nil end
		if has and not (permanent and kind == permanent) then
			return true, type(left) == "number" and left / 1000 or nil
		end
	end
	return false
end
CD.Enchant = Enchant

-- Is one of your shields on you? Out of combat only (nil otherwise).
local function ShieldUp()
	if InCombatLockdown() then return nil end
	local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
	if not get then return nil end
	for _, id in ipairs(ShieldIds()) do
		local ok, aura = pcall(get, id)
		if not ok or Secret(aura) then return nil end
		if aura then return true end
	end
	return false
end
CD.ShieldUp = ShieldUp

local function SetGlow(button, on)
	on = on and M.db.cooldowns.missingGlow and true or false
	if on == (button.glowing or false) then return end
	button.glowing = on
	if on then E:ShowUserGlow(button, "totemMissing") else E:HideGlow(button) end
end

local IMBUE_LENGTH = 30 * 60 -- a weapon imbue lasts 30 minutes

local function UpdateSpell(button, entry)
	local cooldown = button.cooldown
	if not (Source and Source.DrawSpell(cooldown, entry.spell)) then cooldown:Clear() end
	local active = Source and Source.SpellFlags(entry.spell, true)
	if entry.kind == "ready" then
		-- Lit while ready; dim while its own cooldown runs; as is when unknown.
		button.icon:SetDesaturated(active == true)
		button.icon:SetAlpha(active == true and 0.5 or 1)
	end
	if entry.item.item then
		local count = C_Item and C_Item.GetItemCount and Plain(Try(C_Item.GetItemCount, entry.item.item))
		button.count:SetText(type(count) == "number" and tostring(count) or "")
	else
		button.count:SetText("")
	end
end

function CD:Update()
	if not (self.frame and self.items and M:Drawing() and M.db.cooldowns.enabled) then return end
	for index, entry in ipairs(self.items) do
		local button = self.buttons[index]
		if not button then break end
		if entry.kind == "shield" then
			-- The live shield draws itself over this faded icon.
			button.icon:SetDesaturated(self.shieldSlot ~= nil)
			button.icon:SetAlpha(self.shieldSlot and 0.45 or 1)
			button.count:SetText("")
			local up = ShieldUp()
			if up ~= nil then SetGlow(button, not up) elseif not InCombatLockdown() then SetGlow(button, false) end
		elseif entry.kind == "imbue" then
			local has, left = Enchant(entry.slot)
			if has ~= nil then
				button.icon:SetDesaturated(not has)
				button.icon:SetAlpha(has and 1 or 0.45)
				SetGlow(button, not has)
				local bar = button.bar
				if has and left and left > 0 then
					bar:SetValue(math.min(left / IMBUE_LENGTH, 1))
					bar:SetShown(true)
					button.count:SetText(left < 60 and ("%d"):format(left) or ("%dm"):format(math.ceil(left / 60)))
				else
					bar:Hide()
					button.count:SetText("")
				end
			end
		else
			UpdateSpell(button, entry)
		end
	end
end

function CD:Tick() self:Update() end

-- Does a weapon imbue count down on its bar? (The tick runs for it.) An
-- answer the game hides counts as yes.
function CD:ImbueRunning()
	if not (self.items and M.db.cooldowns.enabled) then return false end
	for _, entry in ipairs(self.items) do
		if entry.kind == "imbue" then
			local has = Enchant(entry.slot)
			if has ~= false then return true end
		end
	end
	return false
end

function CD:OnEvent(event)
	if event == "UNIT_INVENTORY_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" then
		-- An off-hand weapon came or went: the list changes (out of combat).
		E:RunOutOfCombat(function() CD:Apply() end, "ShamanTotems:cooldowns")
	end
end

function CD:Enable() end

function CD:Disable()
	if not self.frame then
		local mover = E.movers.EldoUI_ShamanCooldowns
		if mover then mover:Hide() end
		return
	end
	E:DetachVisibility(self.holder)
	self.visibilityBlock = nil
	for _, button in ipairs(self.buttons) do SetGlow(button, false) end
	E:RunOutOfCombat(function()
		if CD.shieldSlot then E.AuraWidget.Release(CD.shieldSlot) end
		CD.shieldSlot, CD.shieldSignature = nil, nil
		CD.frame:Hide()
		local mover = E.movers.EldoUI_ShamanCooldowns
		if mover then mover:Hide() end
	end, "ShamanTotems:CooldownsOff")
end
