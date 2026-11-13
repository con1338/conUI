-- EldoUI cooldown rows: EldoUI's own
-- cooldown rows next to Blizzard's Cooldown Manager.
--   Main / Utility  a fallback for characters where Blizzard's Cooldown
--                   Manager has no spell data (reported for Forever
--                   classes). The player picks the spells.
--   Trinkets        the equipped trinkets (by default only those with a
--                   use effect, slots 13 and 14).
--   Mobility        movement and escape spells, a per-class default list
--                   (data below) that the player can replace.
--   Items           potions, healthstones and other on-use bag items the
--                   player lists, with the count in the bags.
-- A spell may sit in several rows, or twice in one row (copies).
-- Each icon shows the cooldown as the game draws it, read through the
-- combat kit's one cooldown source (K.Cooldowns in Kit.lua), which also
-- tells the rows when the game says a cooldown changed:
--   spells  the game's duration object (cooldown, or the next charge) ->
--           Cooldown:SetCooldownFromDurationObject
--   items   a duration object made from the game's start and duration,
--           passed on untouched
-- No cooldown is computed, compared or counted down by EldoUI, so secret
-- cooldowns in combat are fine. Charge counts go straight to SetText; the
-- countdown text is formatted by the client (a numeric rule formatter with
-- color bands, "only below N seconds" and M:SS rules).
--
-- State looks: alpha, gray and tint per state. The state comes only
-- from the game's own flags: SpellCooldownInfo.isActive / isOnGCD,
-- SpellChargeInfo.isActive, C_Spell.IsSpellUsable and C_Spell.IsSpellInRange
-- (SPELL_RANGE_CHECK_UPDATE). A flag that is secret leaves the icon in its
-- normal look; nothing is guessed from durations.
--
-- Glows go through Core/Glow.lua, one row each on General > Glows:
--   cooldownProc   Blizzard's spell alert (SPELL_ACTIVATION_OVERLAY_GLOW_*)
--   cooldownReady  while the game's cooldown flag says the spell is ready
--   cooldownAura   while your aura from the spell is up: an aura container
--                  slot per icon (your buff on you, your debuff on your
--                  target); the client shows the slot, Lua never reads the
--                  aura
-- Only the player's own spells and items; nothing is suggested or tracked
-- for others.
--
-- Main and Utility sit on the Cooldown Manager movers (EldoUI_Cooldowns and
-- EldoUI_CooldownsUtility) and use the same grid settings as Blizzard's
-- essential and utility viewers, so they replace them seamlessly. Trinkets,
-- Mobility and Items attach to the side of the essential row or use their
-- own movers (EldoUI_CooldownsTrinkets, EldoUI_CooldownsMobility,
-- EldoUI_CooldownsItems).
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local K = E.CombatKit
local M = E:GetModule("CooldownManager")

local GROUP = "cdmrows"
local CD = K.Cooldowns
local TRINKET_SLOTS = { 13, 14 } -- INVSLOT_TRINKET1, INVSLOT_TRINKET2

-- kind: "viewer" rows follow a Blizzard viewer; "extra" rows have own settings.
local ROWS = {
	{ key = "main", kind = "viewer", viewer = "essential", title = "Main row" },
	{ key = "utility", kind = "viewer", viewer = "utility", title = "Utility row" },
	{ key = "trinkets", kind = "extra", mover = "EldoUI_CooldownsTrinkets", title = "Cooldowns: Trinkets",
		label = "Trinket row", point = { "CENTER", "UIParent", "CENTER", 250, -229 } },
	{ key = "mobility", kind = "extra", mover = "EldoUI_CooldownsMobility", title = "Cooldowns: Mobility",
		label = "Mobility row", point = { "CENTER", "UIParent", "CENTER", -250, -229 } },
	{ key = "items", kind = "extra", mover = "EldoUI_CooldownsItems", title = "Cooldowns: Items",
		label = "Item row", point = { "CENTER", "UIParent", "CENTER", 0, -290 } },
}

-- Default mobility and escape spells per class (spell IDs of rank 1; the
-- player's own rank is looked up by name). Only spells the character knows
-- are shown. Shipped as data so a class list can change without code.
local MOBILITY = {
	WARRIOR = { 100, 20252 },         -- Charge, Intercept
	ROGUE = { 2983, 1856 },           -- Sprint, Vanish
	MAGE = { 1953 },                  -- Blink
	HUNTER = { 781, 5384 },           -- Disengage, Feign Death
	DRUID = { 1850, 16979 },          -- Dash, Feral Charge
	PALADIN = { 1044, 642 },          -- Blessing of Freedom, Divine Shield
	PRIEST = { 586 },                 -- Fade
	SHAMAN = { 2645 },                -- Ghost Wolf
	WARLOCK = { 6789 },              -- Death Coil
}

local ROW_BY_KEY = {}
for _, row in ipairs(ROWS) do ROW_BY_KEY[row.key] = row end

local CLASS_NAME, CLASS = UnitClass("player")
CLASS = CLASS or "ALL"

-- Own groups (CooldownGroups.lua) replace the fixed rows while they
-- are on: M.GroupRows() then returns the group rows, built by the same
-- code below. A group row: { key, kind = "group", from (the fixed row it
-- stands in for, keeping that row's mover, grid and rule), lookKey, db,
-- entries(), layout(shown, frame, grid), holder(), dress(button, entry) }.
local seenRows, seenOrder = {}, {}   -- every row built so far, to hide and walk them

local function RowList()
	local list = M.GroupRows and M.GroupRows()
	return list or ROWS
end

-- The rows on show now first, then every other row ever built (hidden).
local function AllRows(selected)
	local list, done = {}, {}
	for _, row in ipairs(selected or RowList()) do
		list[#list + 1] = row
		done[row.key] = true
	end
	for _, row in ipairs(ROWS) do
		if not done[row.key] then list[#list + 1] = row done[row.key] = true end
	end
	for _, key in ipairs(seenOrder) do
		if not done[key] then list[#list + 1] = seenRows[key] done[key] = true end
	end
	return list
end

local function Extra(side, perRow, extra)
	local settings = { enabled = false, size = 36, spacing = 4, perRow = perRow, attach = "essential", side = side, gap = 6 }
	for key, value in pairs(extra or {}) do settings[key] = value end
	return settings
end

-- Look of one row: state looks and text.
local function Look()
	return {
		cdAlpha = 100, cdDesat = true,
		rechargeAlpha = 100, rechargeDesat = false,
		unusableAlpha = 100, unusableDesat = false, unusableTint = false, unusableColor = { 0.4, 0.4, 1 },
		timeFormat = "short", timeBelow = 0, timeColors = true, timeColor = { 1, 1, 1 }, timePoint = "CENTER",
		countPoint = "BOTTOMRIGHT", countColor = { 1, 1, 1 },
	}
end

M.defaults.rows = {
	mode = "auto",      -- off | auto (when Blizzard's has nothing) | always
	lists = {},         -- [CLASS] = { main = "spell, spell", utility = "...", mobility = "..." }
	items = Extra("BOTTOM", 8, { list = "", empty = "dim" }),
	trinkets = Extra("RIGHT", 4, { onUseOnly = true }),
	mobility = Extra("LEFT", 4),
	gcd = true,         -- hide the swipe while only the global cooldown runs
	swipe = { reverse = false, color = { 0, 0, 0 }, alpha = 70, edge = false, bling = true, inset = 0 },
	range = { enabled = false, color = { 1, 0.25, 0.25 }, shadow = false },
	edit = "main",      -- the row the Row look tab edits
	looks = { main = Look(), utility = Look(), trinkets = Look(), mobility = Look(), items = Look() },
}

E:RegisterGlowUser("cooldownProc", {
	title = "Cooldown rows: proc",
	desc = "Icons in EldoUI's cooldown rows whose spell the game lights up (a proc or a reactive spell). Only the game's own spell alert starts it.",
	order = 20,
	button = true,
	default = { style = "blizzard", colorMode = "custom", color = { 1, 0.82, 0 } },
})
E:RegisterGlowUser("cooldownReady", {
	title = "Cooldown rows: ready",
	desc = "Icons in EldoUI's cooldown rows while the game says the spell is off cooldown. Off by default.",
	order = 21,
	button = true,
	default = { style = "none", colorMode = "accent" },
})
E:RegisterGlowUser("cooldownAura", {
	title = "Cooldown rows: aura active",
	desc = "Cooldown row icons glow while their spell's buff is on you or its debuff is on your target, as the game reports it. Off by default.",
	order = 22,
	button = true,
	default = { style = "none", colorMode = "custom", color = { 0.3, 1, 0.4 } },
})

local rowFrames = {}                                     -- key -> container
local rowOrigins = setmetatable({}, { __mode = "k" })
local rowCommit = { phase = "pending", serial = 0 }
local nativeBody, nativeWatched = nil, setmetatable({}, { __mode = "k" })
local rowAnchors = setmetatable({}, { __mode = "k" })
local readingBody, bodyReads = false, 0
local ObserveRowGeometry

local icons = {}                                          -- key -> { icon, ... }
local auraSlots = {}                                      -- key -> { sig, player, target }
local chargeSpell = {}                                    -- spellID -> true when it has more than one charge
local rangeChecked = {}                                   -- spellID -> true while EldoUI asked for range updates
local IsSpellOverlayed = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed

---------------------------------------------------------------------------
-- Which spells and items
---------------------------------------------------------------------------
local function ListText(rowKey)
	local lists = M.db.rows.lists
	local own = lists[CLASS]
	return own and own[rowKey] or ""
end

local function Known(id)
	local book = C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook
	if not book then return true end
	local ok, known = pcall(book, id)
	if not ok or not K.Plain(known) then return true end
	return known and true or false
end

-- The player's own rank of a spell: by name, which the game resolves to the
-- known rank (or override).
local function OwnSpell(id)
	local name = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
	local resolved = name and C_Spell.GetSpellIDForSpellIdentifier and C_Spell.GetSpellIDForSpellIdentifier(name)
	if K.Plain(resolved) and resolved and Known(resolved) then return resolved end
	if Known(id) then return id end
end

-- "Fireball, 133, Frost Nova" -> { spellID, ... } (spells the player knows),
-- in the order typed. A spell typed twice shows twice (a copy).
local function ParseList(text)
	local ids = {}
	for word in tostring(text or ""):gmatch("[^,;\n]+") do
		word = strtrim(word)
		if word ~= "" then
			local id = tonumber(word) or tonumber(word:match("|Hspell:(%d+)"))
				or (C_Spell.GetSpellIDForSpellIdentifier and C_Spell.GetSpellIDForSpellIdentifier(word))
			id = K.Plain(id) and id and OwnSpell(id) or nil
			if id and C_Spell.GetSpellTexture(id) then ids[#ids + 1] = id end
		end
	end
	return ids
end

-- "Major Healing Potion, 5512" -> { itemID, ... } in the order typed.
local function ParseItems(text)
	local ids = {}
	for word in tostring(text or ""):gmatch("[^,;\n]+") do
		word = strtrim(word)
		if word ~= "" then
			local id = tonumber(word) or tonumber(word:match("|Hitem:(%d+)"))
			if not id and C_Item.GetItemInfoInstant then
				local ok, found = pcall(C_Item.GetItemInfoInstant, word)
				if ok and K.Plain(found) then id = tonumber(found) end
			end
			if id and id > 0 then ids[#ids + 1] = id end
		end
	end
	return ids
end

local function MobilityList()
	local text = ListText("mobility")
	if strtrim(text) ~= "" then return ParseList(text) end
	local ids = {}
	for _, id in ipairs(MOBILITY[CLASS] or {}) do ids[#ids + 1] = id end
	return ParseList(table.concat(ids, ","))
end

-- Equipped trinkets: { itemID, slot } entries. With onUseOnly (default)
-- only trinkets that have a use effect.
local function TrinketList()
	local list = {}
	local onUseOnly = M.db.rows.trinkets.onUseOnly ~= false
	for _, slot in ipairs(TRINKET_SLOTS) do
		local itemID = GetInventoryItemID("player", slot)
		if K.Plain(itemID) and itemID then
			local spellName = C_Item.GetItemSpell and C_Item.GetItemSpell(itemID)
			if spellName or not onUseOnly then list[#list + 1] = { item = itemID, slot = slot } end
		end
	end
	return list
end

local function ItemCount(itemID)
	if not C_Item.GetItemCount then return nil end
	local ok, count = pcall(C_Item.GetItemCount, itemID, false, true)
	if ok and K.Plain(count) then return tonumber(count) end
end

-- Charge spells are noted out of combat, while charge info is readable.
local function NoteCharges(spellID)
	if InCombatLockdown() then return end
	local info = CD.SpellCharges(spellID)
	local max = info and info.maxCharges
	chargeSpell[spellID] = (max and K.Plain(max) and max > 1) or nil
end

-- Blizzard's viewer has items to show for this row.
local function BlizzardHasData(row)
	if C_CooldownViewer and C_CooldownViewer.IsCooldownViewerAvailable then
		local ok, available = pcall(C_CooldownViewer.IsCooldownViewerAvailable)
		if ok and K.Plain(available) and not available then return false end
	end
	local viewer = _G[M.VIEWERS[row.viewer].global]
	local pool = viewer and viewer.itemFramePool
	if not pool then return false end
	local count = pool:GetNumActive()
	return K.Plain(count) and count > 0
end

local function RowWanted(row, current)
	if not M.active or current == false then return false end
	if row.kind == "group" then
		-- A group standing in for a fixed row keeps that row's rule.
		if row.from then return RowWanted(ROW_BY_KEY[row.from]) end
		return true
	end
	if row.kind == "extra" then return M.db.rows[row.key].enabled and true or false end
	local mode = M.db.rows.mode
	if mode == "off" then return false end
	if mode == "always" then return true end
	return not BlizzardHasData(row)
end

local function LookOf(rowKey)
	local looks = M.db.rows.looks
	return looks and looks[rowKey] or M.defaults.rows.looks.main
end

---------------------------------------------------------------------------
-- Glows (Core/Glow.lua): proc on the icon itself, ready on a child frame,
-- aura active on the aura slot's own button.
---------------------------------------------------------------------------
local function HideProc(button)
	if button.procLit then
		button.procLit = nil
		E:HideGlow(button)
	end
end

local function ShowProc(button)
	if button.procLit and E:IsGlowShown(button) then return end
	button.procLit = true
	E:ShowUserGlow(button, "cooldownProc")
end

local function RefreshProc(button)
	local id = button.spellID
	if id and IsSpellOverlayed then
		local ok, lit = pcall(IsSpellOverlayed, id)
		if ok and K.Plain(lit) and lit then ShowProc(button) return end
	end
	HideProc(button)
end

local function SetReady(button, ready)
	if ready and E:GlowSettings("cooldownReady") ~= "none" then
		if not (button.readyLit and E:IsGlowShown(button.readyHost)) then
			button.readyLit = true
			E:ShowUserGlow(button.readyHost, "cooldownReady")
		end
	elseif button.readyLit then
		button.readyLit = nil
		E:HideGlow(button.readyHost)
	end
end

---------------------------------------------------------------------------
-- Countdown numbers: a numeric rule formatter the client runs.
--   short  "5", "12", "2m", "1h" with the shared cooldown color bands
--   mmss   "5", "59", "1:30", "12:05" (minutes and seconds under an hour)
-- timeBelow hides the number while more than that many seconds are left;
-- timeColors off uses one color (timeColor) for every band.
---------------------------------------------------------------------------
local formatters = {}

local function Hex(color, fallback)
	color = type(color) == "table" and color or fallback
	return ("|cff%02x%02x%02x"):format(
		math.floor((color[1] or 1) * 255 + 0.5),
		math.floor((color[2] or 1) * 255 + 0.5),
		math.floor((color[3] or 1) * 255 + 0.5))
end

local function RowFormatter(look)
	if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Enum.NumericRuleFormatRounding) then return nil end
	local widget = E.AuraWidget
	local shared = widget and widget.CooldownLook and widget.CooldownLook() or {}
	local expiring = math.max(0, math.min(60, tonumber(shared.expiring) or 5))
	local tenths = math.max(0, math.min(expiring > 0 and expiring or 10, tonumber(shared.tenths) or 0))
	local normal, seconds, soon
	if look.timeColors ~= false then
		normal = Hex(shared.color, { 1, 1, 1 })
		seconds = Hex(shared.secondsColor, { 1, 1, 1 })
		soon = Hex(shared.expiringColor, { 1, 0.3, 0.3 })
	else
		normal = Hex(look.timeColor, { 1, 1, 1 })
		seconds, soon = normal, normal
	end
	local below = math.max(0, math.min(3600, tonumber(look.timeBelow) or 0))
	local mmss = look.timeFormat == "mmss"
	local key = table.concat({ expiring, tenths, normal, seconds, soon, below, tostring(mmss) }, ":")
	if formatters[key] ~= nil then return formatters[key] or nil end

	local up, down = Enum.NumericRuleFormatRounding.Up, Enum.NumericRuleFormatRounding.Down
	local rules = {}
	local function Add(rule)
		if below > 0 and rule.threshold >= below then return end
		rules[#rules + 1] = rule
	end
	if tenths > 0 then Add({ threshold = 0, step = 0.1, rounding = up, format = soon .. "%.1f|r" }) end
	if expiring > tenths then Add({ threshold = tenths, step = 1, rounding = up, format = soon .. "%.0f|r" }) end
	Add({ threshold = expiring, step = 1, rounding = up, format = seconds .. "%.0f|r" })
	if mmss then
		Add({ threshold = 60, step = 1, rounding = up, format = normal .. "%d:%02d|r",
			components = { { div = 60, step = 1, rounding = down }, { mod = 60, step = 1, rounding = down } } })
	else
		Add({ threshold = 60, format = normal .. "%.0fm|r", components = { { div = 60, step = 1, rounding = up } } })
	end
	Add({ threshold = 3600, format = normal .. "%.0fh|r", components = { { div = 3600, step = 1, rounding = up } } })
	Add({ threshold = 86400, format = normal .. "%.0fd|r", components = { { div = 86400, step = 1, rounding = up } } })
	-- Above the limit: no number (the client formats an empty text).
	if below > 0 then rules[#rules + 1] = { threshold = below, format = "" } end

	local ok, formatter = pcall(function()
		local f = C_StringUtil.CreateNumericRuleFormatter()
		f:SetBreakpoints(rules)
		return f
	end)
	formatters[key] = ok and formatter or false
	return ok and formatter or nil
end

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------
local function CreateIcon(container)
	local button = CreateFrame("Frame", nil, container)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	-- Dark shadow over the icon while the target is out of range.
	button.shadow = button:CreateTexture(nil, "ARTWORK", nil, 2)
	button.shadow:SetAllPoints(button.icon)
	button.shadow:SetColorTexture(0, 0, 0, 0.5)
	button.shadow:Hide()
	button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.cooldown:SetAllPoints()
	button.cooldown:SetSwipeTexture(E.media.flat)
	local overlay = CreateFrame("Frame", nil, button)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(button.cooldown:GetFrameLevel() + 2)
	button.count = overlay:CreateFontString(nil, "OVERLAY")
	button.count:SetPoint("BOTTOMRIGHT", -2, 2)
	button.keybind = overlay:CreateFontString(nil, "OVERLAY")
	-- The ready glow lives on its own frame, so it can show together with
	-- the proc glow on the icon.
	button.readyHost = CreateFrame("Frame", nil, button)
	button.readyHost:SetAllPoints()
	E:SetTemplate(button)
	button:SetScript("OnEnter", function(self)
		if self.noTooltip then return end -- a group icon set to no tooltip
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.slot then
			GameTooltip:SetInventoryItem("player", self.slot)
		elseif self.itemID then
			GameTooltip:SetItemByID(self.itemID)
		elseif self.spellID then
			GameTooltip:SetSpellByID(self.spellID)
		else
			return
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	E:BindOptionsLink(button, { page = "module:CooldownManager", key = "rows.mode" })
	-- The game's ping key over the icon pings this spell or item (Messages > Pings).
	if E.SetPingable then E:SetPingable(button, function(self) return (self.itemID and { itemID = self.itemID }) or (self.spellID and { spellID = self.spellID }) or nil end) end
	return button
end

-- The game's cooldown flags for a spell (K.SpellFlags; secret values stay
-- nil). Charges are only asked for spells noted as charge spells.
--   active   the spell's own cooldown runs (no charge left)
--   gcd      the running cooldown is only the global cooldown
--   charging a charge is coming back while at least one is left
local function SpellFlags(id)
	local active, gcd, charging = K.SpellFlags(id, not chargeSpell[id])
	return active, gcd, charging
end

local function ItemActive(itemID)
	return K.ItemActive(itemID)
end

local function UpdateCooldown(button)
	if button.itemID then
		-- Item cooldowns: the game's start and duration, passed on as they are.
		CD.DrawItem(button.cooldown, button.itemID)
		if button.bagItem then
			local count = ItemCount(button.itemID)
			button.count:SetText(count or "")
		else
			button.count:SetText("")
		end
		return
	end
	local id = button.spellID
	if not id then return end
	-- "Hide the global cooldown": no swipe while only the global cooldown
	-- runs (the game's own flag).
	CD.DrawSpell(button.cooldown, id, { charge = chargeSpell[id], hideGCD = M.db.rows.gcd and not chargeSpell[id] })
	if chargeSpell[id] then
		local info = CD.SpellCharges(id)
		-- The count may be secret in combat: no boolean test on it, the
		-- FontString shows it as it is (nil clears the text).
		if info then
			button.count:SetText(info.currentCharges)
		else
			button.count:SetText("")
		end
	else
		button.count:SetText("")
	end
end

-- Out of range: the game's answer for the current target (nil = no range).
local function InRange(button)
	if not (button.spellID and M.db.rows.range.enabled and C_Spell.IsSpellInRange) then return nil end
	if not UnitExists("target") then return nil end
	local ok, inRange = pcall(C_Spell.IsSpellInRange, button.spellID, "target")
	if not ok or not K.Plain(inRange) or inRange == nil then return nil end
	return inRange and true or false
end

-- Alpha, gray and tint from the game's flags.
local function UpdateState(button)
	local look = LookOf(button.rowKey)
	local state, ready
	if button.spellID then
		local active, gcd, charging = SpellFlags(button.spellID)
		local usable = C_Spell.IsSpellUsable and C_Spell.IsSpellUsable(button.spellID)
		if usable ~= nil and K.Plain(usable) and not usable then
			state = "unusable"
		elseif active and not gcd then
			state = "cooldown"
		elseif charging then
			state = "recharging"
		end
		ready = active == false or (active and gcd) or false
	elseif button.itemID then
		if button.bagItem and button.count0 and M.db.rows.items.empty == "dim" then
			state = "empty"
		elseif ItemActive(button.itemID) then
			state = "cooldown"
		end
	end
	local alpha, desat, r, g, b = 1, false, 1, 1, 1
	if state == "cooldown" then
		alpha, desat = (look.cdAlpha or 100) / 100, look.cdDesat and true or false
	elseif state == "recharging" then
		alpha, desat = (look.rechargeAlpha or 100) / 100, look.rechargeDesat and true or false
	elseif state == "unusable" then
		alpha, desat = (look.unusableAlpha or 100) / 100, look.unusableDesat and true or false
		if look.unusableTint then
			local c = look.unusableColor or { 0.4, 0.4, 1 }
			r, g, b = c[1] or 1, c[2] or 1, c[3] or 1
		end
	elseif state == "empty" then
		alpha, desat = 0.4, true
	end
	local outside = InRange(button) == false
	if outside then
		local c = M.db.rows.range.color or { 1, 0.25, 0.25 }
		r, g, b = c[1] or 1, c[2] or 1, c[3] or 1
	end
	button.icon:SetDesaturated(desat)
	button.icon:SetVertexColor(r, g, b)
	button.shadow:SetShown(outside and M.db.rows.range.shadow and true or false)
	button:SetAlpha(alpha)
	button.state = state
	SetReady(button, button.spellID and ready)
end

-- Display settings of a row: the viewer it stands in for, or its own.
local function RowDB(row)
	if row.db then return row.db end
	if row.kind == "viewer" then return M.db.viewers[row.viewer] end
	return M.db.rows[row.key]
end

local POINTS = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
	TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }

local function Nudge(point)
	local x = point:find("LEFT") and 2 or (point:find("RIGHT") and -2 or 0)
	local y = point:find("TOP") and -2 or (point:find("BOTTOM") and 2 or 0)
	return x, y
end

local function StyleIcon(button, db)
	local inset = E.pixel
	local look = LookOf(button.rowKey)
	button.icon:ClearAllPoints()
	button.icon:SetPoint("TOPLEFT", inset, -inset)
	button.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
	button.icon:SetTexCoord(E:IconCoords((M.db.zoom or 8) / 100))
	-- Swipe: direction, color, edge, bling, inset.
	local swipe = M.db.rows.swipe
	local cooldown = button.cooldown
	local swipeInset = (tonumber(swipe.inset) or 0) * E.pixel + inset
	cooldown:ClearAllPoints()
	cooldown:SetPoint("TOPLEFT", swipeInset, -swipeInset)
	cooldown:SetPoint("BOTTOMRIGHT", -swipeInset, swipeInset)
	cooldown:SetReverse(swipe.reverse and true or false)
	local c = swipe.color or { 0, 0, 0 }
	cooldown:SetSwipeColor(c[1] or 0, c[2] or 0, c[3] or 0, math.max(0, math.min(100, tonumber(swipe.alpha) or 70)) / 100)
	cooldown:SetDrawEdge(swipe.edge and true or false)
	if cooldown.SetDrawBling then cooldown:SetDrawBling(swipe.bling ~= false) end
	-- Text: font and size from the row, place and color per row.
	local font, outline = M.FontFile(), M.Outline()
	local countPoint = POINTS[look.countPoint] and look.countPoint or "BOTTOMRIGHT"
	button.count:ClearAllPoints()
	button.count:SetPoint(countPoint, button, countPoint, Nudge(countPoint))
	button.count:SetFont(font, db.countSize or E.tokens.size.label, outline)
	local countColor = look.countColor or { 1, 1, 1 }
	button.count:SetTextColor(countColor[1] or 1, countColor[2] or 1, countColor[3] or 1)
	if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(false) end
	local formatter = RowFormatter(look)
	if cooldown.SetCountdownFormatter then pcall(cooldown.SetCountdownFormatter, cooldown, formatter) end
	if not formatter and look.timeFormat == "mmss" and cooldown.SetCountdownAbbrevThreshold then
		pcall(cooldown.SetCountdownAbbrevThreshold, cooldown, 3600)
	end
	if cooldown.GetCountdownFontString then
		local text = cooldown:GetCountdownFontString()
		if text then
			text:SetFont(font, db.countdownSize or math.max(10, math.floor(db.size * 0.36)), outline)
			local timePoint = POINTS[look.timePoint] and look.timePoint or "CENTER"
			text:ClearAllPoints()
			text:SetPoint(timePoint, button, timePoint, Nudge(timePoint))
			local tc = look.timeColors == false and look.timeColor or { 1, 1, 1 }
			text:SetTextColor(tc[1] or 1, tc[2] or 1, tc[3] or 1)
		end
	end
	local point = M.db.keybindPoint or "TOPRIGHT"
	button.keybind:ClearAllPoints()
	button.keybind:SetPoint(point, button, point, Nudge(point))
	button.keybind:SetFont(font, db.keybindSize or E.tokens.size.small, outline)
	button.keybind:SetTextColor(unpack(M.db.keybindColor))
	-- Extra rows have no key text setting of their own: they follow Essential.
	local own = db.keyText ~= nil or db.keybinds ~= nil
	local mode = M.KeyTextMode(own and db or M.db.viewers.essential)
	local keys = (mode ~= "off" and button.spellID) and true or false
	button.keybind:SetShown(keys)
	button.keybind:SetText(keys and M.SpellKeyBinding(button.spellID, mode) or "")
	if button.procLit then E:UpdateGlowLayout(button) end
end

---------------------------------------------------------------------------
-- Aura active glow: one aura slot per spell icon, on the player (your buff)
-- and on the target (your debuff). The slot's button covers the icon and
-- carries the glow; the client shows it only while the aura is up.
---------------------------------------------------------------------------
local AURA_LANES = {
	{ unit = "player", kind = "HELPFUL" },
	{ unit = "target", kind = "HARMFUL" },
}

local function ReleaseAuraSlots(entry)
	local widget = E.AuraWidget
	for _, lane in ipairs(AURA_LANES) do
		if entry[lane.unit] and widget then widget.Release(entry[lane.unit]) end
		entry[lane.unit] = nil
	end
	entry.sig = nil
end

local function BuildAuraSlots(row, shown)
	local entry = auraSlots[row.key] or {}
	auraSlots[row.key] = entry
	local widget = E.AuraWidget
	local parts = {}
	if E:GlowSettings("cooldownAura") ~= "none" and widget and widget.SlotsAvailable() then
		for index, button in ipairs(shown) do
			if button.spellID then parts[#parts + 1] = index .. "=" .. button.spellID end
		end
	end
	local sig = table.concat(parts, ",") .. ":" .. (E.pixel or 1)
	if entry.sig == sig then return end
	-- Containers are made out of combat; the row is rebuilt after combat.
	if InCombatLockdown() then return end
	ReleaseAuraSlots(entry)
	entry.sig = sig
	if #parts == 0 then return end
	for _, lane in ipairs(AURA_LANES) do
		local slots = {}
		for index, button in ipairs(shown) do
			local filter, candidateFilters
			if button.spellID then filter, candidateFilters = E:AuraSpellSlotSpec(button.spellID, lane.kind, true) end
			if filter then
				slots[#slots + 1] = {
					key = "cd" .. index, filter = filter, candidateFilters = candidateFilters,
					initialize = widget.SlotGlow(button, "cooldownAura"),
				}
			end
		end
		if #slots > 0 then entry[lane.unit] = widget.CreateSlots(rowFrames[row.key], { unit = lane.unit, slots = slots }) end
	end
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
-- Constructor-owned handles stay private; no public binding table is retained.
local parentPlain, parentAuthority = rawget(K, "Plain"), rawget(E, "MoverAuthoritySource")
local parentBinding
local function ParentConstructorCurrent()
	local plain, authority = rawget(K, "Plain"), rawget(E, "MoverAuthoritySource")
	return type(parentPlain) == "function" and parentPlain(plain, authority)
		and rawequal(plain, parentPlain) and rawequal(authority, parentAuthority)
end
local function CaptureParentSource(frame)
	if not ParentConstructorCurrent() then return false end
	if type(parentBinding) == "nil" and type(parentAuthority) == "function" then
		local _, _, _, _, _, bind = parentAuthority()
		if not ParentConstructorCurrent() or not parentPlain(bind) then return false end
		parentBinding = type(bind) == "function" and bind or false
	end
	if type(parentBinding) ~= "function" then return nil end
	local binding = parentBinding(frame)
	if not ParentConstructorCurrent() or not parentPlain(binding) then return false end
	if type(binding) == "nil" then return nil end
	if type(binding) ~= "table" or type(getmetatable(binding)) ~= "nil" then return false end
	local native, getters = rawget(binding, "native"), rawget(binding, "getters")
	local source, capture = rawget(binding, "source"), rawget(binding, "capture")
	if not parentPlain(native, getters, source, capture) then return false end
	if native ~= true then return nil end
	if type(getters) ~= "table" or type(getmetatable(getters)) ~= "nil"
		or type(source) ~= "function" or type(capture) ~= "function" then return false end
	local getter = rawget(getters, "GetParent")
	if not parentPlain(getter) or type(getter) ~= "function" then return false end
	local current = source("GetParent")
	if not ParentConstructorCurrent() or not parentPlain(current) or current ~= true then return false end
	return { plain = parentPlain, authority = parentAuthority, getter = getter, source = source, capture = capture }
end

local function Container(row)
	if not ParentConstructorCurrent() then error("Cooldown row read source changed") end
	local frame = rowFrames[row.key]
	if not frame then
		frame = CreateFrame("Frame", nil, UIParent)
		frame:SetSize(1, 1)
		rowFrames[row.key] = frame
		local geometry = ObserveRowGeometry and ObserveRowGeometry(frame)
		local parentSource = CaptureParentSource(frame)
		if parentSource == false then error("Cooldown row read source changed") end
		local getter = frame.GetParent
		local current = parentSource and parentSource.source("GetParent")
		if not ParentConstructorCurrent() or (parentSource and (not parentPlain(getter, current)
			or not rawequal(getter, parentSource.getter) or current ~= true)) then error("Cooldown row read source changed") end
		rowOrigins[frame] = { key = row.key, getParent = getter, geometry = geometry, parentSource = parentSource }
		icons[row.key] = {}
	end
	if not rowOrigins[frame] or rowOrigins[frame].key ~= row.key then error("Cooldown row ownership changed") end
	return frame
end

-- Entries of a row: { spell }, { item, slot } or { item, bag }.
local function Entries(row)
	if row.entries then return row.entries() end
	local list = {}
	if row.key == "trinkets" then
		for _, entry in ipairs(TrinketList()) do list[#list + 1] = { item = entry.item, slot = entry.slot } end
	elseif row.key == "items" then
		local hideEmpty = M.db.rows.items.empty == "hide"
		for _, id in ipairs(ParseItems(M.db.rows.items.list)) do
			local count = ItemCount(id)
			if not (hideEmpty and count == 0) then list[#list + 1] = { item = id, bag = true, empty = count == 0 } end
		end
	elseif row.key == "mobility" then
		for _, id in ipairs(MobilityList()) do list[#list + 1] = { spell = id } end
	else
		for _, id in ipairs(ParseList(ListText(row.key))) do list[#list + 1] = { spell = id } end
	end
	return list
end

local function PlainTable(value)
	return K.Plain(value) and type(value) == "table" and type(getmetatable(value)) == "nil"
end
local readPlain, readAuthority = rawget(K, "Plain"), rawget(E, "MoverAuthoritySource")
local function ParentReadContextCurrent()
	local plain, authority = rawget(K, "Plain"), rawget(E, "MoverAuthoritySource")
	return type(readPlain) == "function" and readPlain(plain, authority)
		and rawequal(plain, readPlain) and rawequal(authority, readAuthority)
end
local function Same(a, b)
	local plain = rawget(K, "Plain")
	return readPlain(plain, a, b) and rawequal(plain, readPlain) and rawequal(a, b)
end
local function Number(value)
	return K.Plain(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local ROW_GEOMETRY = { "enabled", "size", "spacing", "perRow", "growth", "wrap", "attach", "attachSide", "attachGap", "side", "gap" }
local function ParentReadSourceCurrent(read)
	if not ParentReadContextCurrent() then return false end
	local ok, current = pcall(read.source, "GetParent")
	return ok and ParentReadContextCurrent() and readPlain(current) and current == true
end
local function ParentReadEpochCurrent(read)
	local epoch = read.epoch
	if not ParentReadContextCurrent() or not readPlain(epoch) then return false end
	if type(epoch) == "nil" then return true end
	if type(epoch) ~= "function" then return false end
	local ok, current = pcall(epoch)
	return ok and ParentReadContextCurrent() and readPlain(current) and current == true
end
local function CurrentCommitData(commit)
	if not PlainTable(commit) or not Same(rowCommit, commit) then return false end
	local db, modules = rawget(M, "db"), rawget(E, "modules")
	if not PlainTable(db) or not Same(db, rawget(commit, "db"))
		or not Same(rawget(E, "db"), rawget(commit, "root")) or not Same(rawget(E, "profileName"), rawget(commit, "profile"))
		or not PlainTable(modules) or not Same(rawget(modules, "CooldownManager"), M)
		or not Same(rawget(M, "active"), rawget(commit, "active"))
		or not PlainTable(rawget(db, "rows")) or not PlainTable(rawget(db, "viewers"))
		or not Same(rawget(db, "rows"), rawget(commit, "rows"))
		or not Same(rawget(db, "viewers"), rawget(commit, "viewers"))
		or not Same(rawget(M, "GroupRows"), rawget(commit, "groups"))
		or not PlainTable(rawget(commit, "settings")) or not PlainTable(rawget(commit, "records")) then return false end
	for _, item in ipairs(rawget(commit, "settings")) do
		if not PlainTable(item) or not PlainTable(rawget(item, "db"))
			or not PlainTable(rawget(item, "values")) or not PlainTable(rawget(item, "base")) then return false end
		local settings, values, base = rawget(item, "db"), rawget(item, "values"), rawget(item, "base")
		for _, key in ipairs(ROW_GEOMETRY) do if not Same(rawget(settings, key), rawget(values, key)) then return false end end
		local kind, key = rawget(base, "kind"), rawget(base, "viewer")
		if not K.Plain(kind, key, rawget(base, "key")) then return false end
		if kind == "viewer" and not Same(rawget(rawget(db, "viewers"), key), settings) then return false end
		if kind == "extra" and not Same(rawget(rawget(db, "rows"), rawget(base, "key")), settings) then return false end
	end
	return true
end
local function ValidateCommit(commit, capture, check)
	if not ParentReadContextCurrent() or not CurrentCommitData(commit) then return false end
	local records, settings, serial, phase = rawget(commit, "records"), rawget(commit, "settings"), rawget(commit, "serial"), rawget(commit, "phase")
	local selected = {}
	for key, record in pairs(records) do
		if not K.Plain(key) or type(key) ~= "string" or not PlainTable(record) then return false end
		local frame = rawget(record, "frame")
		if not K.Plain(frame) or (type(frame) ~= "table" and type(frame) ~= "userdata") then return false end
		local origin = rowOrigins[frame]
		if not PlainTable(origin) or not Same(rowFrames[key], frame) or not Same(rawget(origin, "key"), key) then return false end
		local tableFrame = type(frame) == "table"
		local getParent, method, meta = rawget(origin, "getParent"), tableFrame and rawget(frame, "GetParent"), getmetatable(frame)
		if not K.Plain(getParent, method, meta) or type(getParent) ~= "function" then return false end
		local proof, read = rawget(origin, "parentSource"), nil
		if not K.Plain(proof) then return false end
		if type(proof) ~= "nil" then
			if not PlainTable(proof) or not Same(rawget(proof, "plain"), readPlain)
				or not Same(rawget(proof, "authority"), readAuthority) or not Same(rawget(proof, "getter"), getParent) then return false end
			local source, epoch = rawget(proof, "source"), rawget(proof, "capture")
			if not K.Plain(source, epoch) or type(source) ~= "function" or type(epoch) ~= "function" then return false end
			read = { proof = proof, source = source, capture = epoch }
			if not ParentReadSourceCurrent(read) then return false end
		end
		local ok, current = pcall(function() return frame.GetParent end)
		if not ok or not ParentReadContextCurrent() or not Same(current, getParent) then return false end
		selected[#selected + 1] = { key = key, record = record, frame = frame, origin = origin, native = read,
			parent = rawget(record, "parent"), getParent = getParent, method = method, meta = meta, tableFrame = tableFrame }
	end
	local function CurrentData()
		if not ParentReadContextCurrent() then check.invalid = true; return false end
		if check.invalid or not CurrentCommitData(commit) or not Same(rawget(commit, "records"), records)
			or not Same(rawget(commit, "settings"), settings) or not Same(rawget(commit, "serial"), serial)
			or not Same(rawget(commit, "phase"), phase) then return false end
		local count = 0;for _ in pairs(records) do count = count + 1 end
		if count ~= #selected then return false end
		for _, item in ipairs(selected) do
			if not Same(rawget(records, item.key), item.record) or not PlainTable(item.record)
				or not Same(rawget(item.record, "frame"), item.frame) or not Same(rawget(item.record, "parent"), item.parent)
				or not Same(rowFrames[item.key], item.frame) or not Same(rowOrigins[item.frame], item.origin)
				or not PlainTable(item.origin) or not Same(rawget(item.origin, "key"), item.key)
				or not Same(rawget(item.origin, "getParent"), item.getParent)
				or (item.tableFrame and not Same(rawget(item.frame, "GetParent"), item.method))
				or not Same(getmetatable(item.frame), item.meta) then return false end
			local read = item.native
			if not Same(rawget(item.origin, "parentSource"), read and read.proof or nil) then return false end
			if read and (not Same(rawget(item.origin, "parentSource"), read.proof)
				or not Same(rawget(read.proof, "source"), read.source) or not Same(rawget(read.proof, "capture"), read.capture)
				or not Same(rawget(read.proof, "getter"), item.getParent) or not Same(rawget(read.proof, "plain"), readPlain)
				or not Same(rawget(read.proof, "authority"), readAuthority)) then return false end
			if read and (not ParentReadSourceCurrent(read) or not ParentReadEpochCurrent(read)) then check.invalid = true; return false end
		end
		return true
	end
	if not CurrentData() then return false end
	for _, item in ipairs(selected) do
		if item.native then
			if not ParentReadSourceCurrent(item.native) then return false end
			local epoch = item.native.capture(false)
			if not ParentReadContextCurrent() or not readPlain(epoch) or type(epoch) ~= "function" then return false end
			item.native.epoch = epoch
		end
	end
	local native = #selected > 0
	for _, item in ipairs(selected) do if not item.native then native = false end end
	if native then
		for _, item in ipairs(selected) do
			if not ParentReadSourceCurrent(item.native) then return false end
			local ok, parent = pcall(item.getParent, item.frame)
			if not ok or not ParentReadSourceCurrent(item.native) or not Same(parent, item.parent) then return false end
			local valid, method = pcall(function() return item.frame.GetParent end)
			if not valid or not ParentReadSourceCurrent(item.native) or not Same(method, item.getParent) then return false end
		end
	else
	for _, item in ipairs(selected) do
		local ok, parent = pcall(item.getParent, item.frame)
		if not ok or not Same(parent, item.parent) or not CurrentData() then return false end
		local valid, method = pcall(function() return item.frame.GetParent end)
		if not valid or not Same(method, item.getParent) or not CurrentData() then return false end
	end
	end
	local current = CurrentData()
	if current and K.Plain(capture) and type(capture) == "table" then capture.current = CurrentData end
	return current
end
local checkingCommit
local function CurrentCommit(commit, capture)
	if checkingCommit then checkingCommit.invalid = true; return false end
	local check = {};checkingCommit = check
	local ok, current = pcall(ValidateCommit, commit, capture, check)
	checkingCommit = nil
	return ok and current == true and not check.invalid
end
local function Measure(frame, current, expected)
	if not K.Plain(frame) or (type(frame) ~= "table" and type(frame) ~= "userdata") then return end
	local methods = {}
	for _, key in ipairs({ "GetRect", "GetEffectiveScale", "GetParent", "IsShown", "IsVisible", "GetNumPoints", "GetPoint" }) do
		local fn = frame[key]
		if not K.Plain(fn) or type(fn) ~= "function" then return end
		methods[key] = fn
	end
	local function Valid()
		if not current() then return false end
		for key, fn in pairs(methods) do if not Same(frame[key], fn) then return false end end
		return true
	end
	local function Read(key, ...)
		if not Valid() then error("Cooldown geometry owner changed") end
		local out = { methods[key](frame, ...) }
		if not Valid() then error("Cooldown geometry owner changed") end
		return unpack(out)
	end
	local ok, result = pcall(function()
		local parent = Read("GetParent")
		local count = Read("GetNumPoints")
		if not Number(count) or count ~= 1 then return end
		local point = { Read("GetPoint", 1) }
		if not K.Plain(unpack(point)) then return end
		if expected then for i = 1, 5 do if not Same(point[i], expected[i]) then return end end end
		local l, b, w, h = Read("GetRect")
		local scale = Read("GetEffectiveScale")
		local rootMethod = UIParent.GetEffectiveScale
		if not K.Plain(rootMethod) or type(rootMethod) ~= "function" then return end
		local rootScale = rootMethod(UIParent)
		local shown, visible = Read("IsShown"), Read("IsVisible")
		if not Number(l) or not Number(b) or not Number(w) or not Number(h) or w <= 0 or h <= 0
			or not Number(scale) or scale <= 0 or not Number(rootScale) or rootScale <= 0
			or not K.Plain(shown, visible) or type(shown) ~= "boolean" or type(visible) ~= "boolean" then return end
		if not Same(Read("GetParent"), parent) or not Same(Read("GetNumPoints"), count) then return end
		local after = { Read("GetPoint", 1) }
		for i = 1, 5 do if not Same(point[i], after[i]) then return end end
		if not Same(UIParent.GetEffectiveScale, rootMethod) or not Valid() then return end
		local ratio = scale / rootScale
		local box = { l = l * ratio, b = b * ratio, r = (l + w) * ratio, t = (b + h) * ratio,
			frame = frame, ratio = ratio, shown = shown, visible = visible, parent = parent }
		if not Number(box.l) or not Number(box.b) or not Number(box.r) or not Number(box.t) then return end
		return box
	end)
	if ok then return result end
end
local function Outset(a, b)
	if math.abs(a - b) <= 4 * 2^-52 * math.max(1, math.abs(a), math.abs(b)) then return 0 end
	return math.max(a - b, 0)
end
local function Body(attachment)
	bodyReads = bodyReads + 1
	if readingBody then return { kind = "unavailable" } end
	local serial = bodyReads
	readingBody = true
	local ok, result = pcall(function()
	local commit = rowCommit
	if not K.Plain(M.active) or type(M.active) ~= "boolean" then return { kind = "unavailable" } end
	if M.active ~= true then return { kind = "inactive", above = 0, below = 0, current = function() return K.Plain(M.active) and M.active == false end } end
	if commit.phase == "inactive" then
		local db, root, profile = M.db, E.db, E.profileName
		return { kind = "inactive", above = 0, below = 0, current = function()
			return Same(rowCommit, commit) and Same(M.db, db) and Same(E.db, root) and Same(E.profileName, profile)
		end }
	end
	if commit.phase == "pending" or commit.phase == "building" or (commit.phase == "attaching" and not attachment) then return { kind = "pending" } end
	if (commit.phase ~= "ready" and commit.phase ~= "attaching") or commit.ambiguous then return { kind = "unavailable" } end
	if not CurrentCommit(commit) then return { kind = "unavailable" } end
	local phase, seal = commit.phase, {}
	local current = function()
		seal.current = nil
		return CurrentCommit(commit, seal) and commit.phase == phase
	end
	local item = commit.records.main
	local frame, kind
	if item and item.active then
		if not Same(rowFrames.main, item.frame) or (not rowOrigins[item.frame] or rowOrigins[item.frame].key ~= "main") then return { kind = "unavailable" } end
		frame, kind = item.frame, "own"
	elseif nativeBody then
		local saved = nativeBody
		if not Same(saved.db, M.db) or not Same(saved.root, E.db) or not Same(saved.profile, E.profileName)
			or not Same(rawget(_G, M.VIEWERS.essential.global), saved.frame)
			or not K.IsPinned(saved.frame, saved.pin) or not E:BlizzardAllowed("cooldown-viewer", "move")
			or not M.db.viewers.essential.enabled then return { kind = "unavailable" } end
		frame, kind = saved.frame, "native"
		local previous = current
		current = function()
			return previous() and Same(nativeBody, saved) and Same(rawget(_G, M.VIEWERS.essential.global), frame)
				and K.IsPinned(frame, saved.pin) and E:BlizzardAllowed("cooldown-viewer", "move") == true
		end
	else
		if E:BlizzardAllowed("cooldown-viewer", "move") then return { kind = "unavailable" } end
		return { kind = "inactive", above = 0, below = 0, current = current }
	end
	local holder = K.GetHolder("EldoUI_Cooldowns")
	local mover = E.movers and E.movers.EldoUI_Cooldowns
	if not K.Plain(holder, mover) or not holder or not mover or not Same(mover.frame, holder) or not Same(mover.module, M.name) then return { kind = "unavailable" } end
	local before = current
	current = function() return before() and Same(K.GetHolder("EldoUI_Cooldowns"), holder)
		and E.movers and Same(E.movers.EldoUI_Cooldowns, mover) and Same(mover.frame, holder)
		and type(seal.current) == "function" and seal.current() end
	local box, anchor = Measure(frame, current, item and item.anchor), Measure(mover, current)
	if not box or not anchor then return { kind = "unavailable" } end
	if not box.shown then return { kind = "inactive", above = 0, below = 0, current = current } end
	local parts = {}
	if not attachment then
		for key, extra in pairs(commit.records) do
			local db = RowDB(extra.row)
			if extra.active and extra.base.kind == "extra" and db.attach == "essential" then
				local rect = Measure(extra.frame, current, extra.anchor)
				if not rect then return { kind = "unavailable" } end
				rect.key = key;parts[#parts + 1] = rect
			end
		end
		table.sort(parts, function(a, b) return a.key < b.key end)
	end
	return { kind = "live", source = kind, frame = frame, anchor = mover, rect = box, parts = parts,
		above = Outset(box.t, anchor.t), below = Outset(anchor.b, box.b), current = current }
	end)
	readingBody = false
	if not ok or serial ~= bodyReads then return { kind = "unavailable" } end
	return result
end
-- Provenance only: available after Kit loads, before rows or profiles.
do
	local stack, offset, hasBody, plain = K.CooldownStack, K.CooldownStack.Offset, K.CooldownStack.HasBodySource, K.Plain
	local admission
	local function Current()
		if not plain(E.modules, E.CombatKit, K, stack) or type(E.modules) ~= "table"
			or type(getmetatable(E.modules)) ~= "nil" or type(getmetatable(K)) ~= "nil"
			or type(getmetatable(stack)) ~= "nil" then return false end
		local owner, currentStack = rawget(E.modules, "CooldownManager"), rawget(K, "CooldownStack")
		local currentOffset, currentBody, currentRead = rawget(stack, "Offset"), rawget(stack, "HasBodySource"), rawget(M, "CooldownStackSource")
		if not plain(owner, currentStack, currentOffset, currentBody, currentRead) then return false end
		return rawequal(owner, M) and rawequal(E.CombatKit, K) and rawequal(currentStack, stack)
			and rawequal(currentOffset, offset) and rawequal(currentBody, hasBody) and rawequal(currentRead, admission)
	end
	admission = function(self)
		if plain(self) and rawequal(self, M) and Current() then return stack, offset, hasBody, Current end
	end
	M.CooldownStackSource = admission
end
function M:CooldownBodyBounds() return Body() end
local function PublishRows()
	K.CooldownStack.Changed()
	if E.RefreshWideConsumableLayout then E:RefreshWideConsumableLayout(M) end
end

local OPPOSITE = { TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT" }
local SIDE_GROWTH = { LEFT = "LEFT", RIGHT = "RIGHT", TOP = "CENTER", BOTTOM = "CENTER" }
local SIDE_WRAP = { TOP = "UP", BOTTOM = "DOWN", LEFT = "DOWN", RIGHT = "DOWN" }

-- Grid settings for an extra row (growth follows the side it sits on).
local function ExtraGrid(db)
	local attached = db.attach == "essential"
	return {
		size = db.size, spacing = db.spacing, perRow = db.perRow,
		growth = attached and SIDE_GROWTH[db.side] or "CENTER",
		wrap = attached and SIDE_WRAP[db.side] or "DOWN",
	}
end

local function PlaceExtra(row, frame, grid, body)
	local db = RowDB(row)
	local holder = K.GetHolder(row.mover)
	local essential = K.GetHolder("EldoUI_Cooldowns")
	if holder then
		-- The mover holds a full row, so the space a layout gives the row is
		-- the space it fills once the player has that many icons.
		local across = math.max(1, db.perRow)
		holder:SetSize(across * db.size + (across - 1) * db.spacing, db.size)
	end
	frame:ClearAllPoints()
	if db.attach == "essential" and essential then
		local side = db.side or "RIGHT"
		local gap = db.gap or 0
		local x = side == "LEFT" and -gap or (side == "RIGHT" and gap or 0)
		local y = side == "BOTTOM" and -gap or (side == "TOP" and gap or 0)
		frame:SetPoint(OPPOSITE[side], body or essential, side, x, y)
		rowAnchors[frame] = { OPPOSITE[side], body or essential, side, x, y }
	elseif holder then
		local corner = M.StartCorner(grid)
		frame:SetPoint(corner, holder, corner, 0, 0)
	end
end

-- Range updates for the spells on show (the game sends
-- SPELL_RANGE_CHECK_UPDATE for each spell asked for).
local function UpdateRangeChecks()
	local enable = C_Spell.EnableSpellRangeCheck
	if not enable then return end
	local wanted = {}
	if M.active and M.db.rows.range.enabled then
		for _, row in ipairs(AllRows()) do
			local frame = rowFrames[row.key]
			if frame and frame:IsShown() then
				for _, button in ipairs(icons[row.key]) do
					if button:IsShown() and button.spellID then wanted[button.spellID] = true end
				end
			end
		end
	end
	for id in pairs(rangeChecked) do
		if not wanted[id] then
			pcall(enable, id, false)
			rangeChecked[id] = nil
		end
	end
	for id in pairs(wanted) do
		if not rangeChecked[id] then
			pcall(enable, id, true)
			rangeChecked[id] = true
		end
	end
end

-- The holder (mover frame) a row sits on: the viewer's or extra row's
-- own; a group row standing in for one uses that row's.
local function RowHolder(row, create)
	local base = row.from and ROW_BY_KEY[row.from] or row
	if base.kind == "viewer" then return K.GetHolder(M.VIEWERS[base.viewer].mover) end
	if base.kind == "extra" then return K.GetHolder(base.mover) end
	if create and row.holder then return row.holder() end
	return row.holderName and K.GetHolder(row.holderName)
end

-- A spot kept for an icon that can't show now (spell not known, item not
-- in the bags, trinket without a use effect): own groups with gaps kept,
-- or move mode with placeholders. Seen only in move mode.
local PLACEHOLDER_ICON = 134400 -- INV_Misc_QuestionMark

local function Placeholder(button, entry, db)
	button.placeholder = true
	button.spellID, button.itemID, button.slot, button.bagItem = nil, nil, nil, nil
	button.icon:SetTexture(entry.texture or PLACEHOLDER_ICON)
	StyleIcon(button, db)
	button.cooldown:Clear()
	button.count:SetText("")
	button.shadow:Hide()
	HideProc(button)
	SetReady(button, false)
	button.icon:SetDesaturated(true)
	button.icon:SetVertexColor(1, 1, 1)
	button:SetAlpha(E:IsMoveMode() and 0.4 or 0)
end

-- Own groups: an icon keeps its button when the list changes, so
-- it can slide from its old spot to the new one. Reorders the pool to the
-- list's order; buttons no entry wants go to the end.
local function KeepButtons(pool, list, frame)
	local byToken, used, ordered = {}, {}, {}
	for _, button in ipairs(pool) do
		if button.token and not byToken[button.token] then byToken[button.token] = button end
	end
	for index, entry in ipairs(list) do
		local button = entry.token and byToken[entry.token]
		if button and not used[button] then
			ordered[index] = button
			used[button] = true
		end
	end
	local spare = {}
	for _, button in ipairs(pool) do
		if not used[button] then spare[#spare + 1] = button end
	end
	local nextSpare = 1
	for index = 1, #list do
		if not ordered[index] then
			ordered[index] = spare[nextSpare] or CreateIcon(frame)
			if spare[nextSpare] then nextSpare = nextSpare + 1 end
		end
	end
	for index = nextSpare, #spare do ordered[#ordered + 1] = spare[index] end
	for index = 1, math.max(#pool, #ordered) do pool[index] = ordered[index] end
end

local function BuildRow(row, current)
	local frame = Container(row)
	local base = row.from and ROW_BY_KEY[row.from] or row
	local wanted = RowWanted(row, current)
	local holder = RowHolder(row, wanted)
	wanted = wanted and holder ~= nil
	if base.kind == "extra" and holder then
		-- The own mover only matters while the row is on and not attached.
		holder:SetShown(wanted and RowDB(base).attach ~= "essential" or false)
	elseif base.kind == "group" and holder then
		holder:SetShown(wanted and true or false)
	end
	if not wanted then
		frame:Hide()
		K.StopVisibility("cdmrow-" .. row.key)
		if auraSlots[row.key] and not InCombatLockdown() then ReleaseAuraSlots(auraSlots[row.key]) end
		for _, button in ipairs(icons[row.key]) do
			HideProc(button)
			SetReady(button, false)
		end
		return
	end
	if row.kind == "group" and not seenRows[row.key] then seenOrder[#seenOrder + 1] = row.key end
	if row.kind == "group" then seenRows[row.key] = row end
	local db = RowDB(row)
	local list = Entries(row)
	local pool = icons[row.key]
	if row.kind == "group" then KeepButtons(pool, list, frame) end
	local shown = {}
	for index, entry in ipairs(list) do
		local button = pool[index] or CreateIcon(frame)
		pool[index] = button
		button.rowKey = row.lookKey or row.key
		button.token, button.listIndex, button.groupKey = entry.token, entry.index, row.kind == "group" and row.key or nil
		if entry.missing then
			Placeholder(button, entry, db)
		else
			button.placeholder = nil
			button.spellID, button.itemID, button.slot = entry.spell, entry.item, entry.slot
			button.bagItem, button.count0 = entry.bag, entry.empty
			if entry.slot then
				button.icon:SetTexture(GetInventoryItemTexture("player", entry.slot) or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(entry.item)))
			elseif entry.item then
				button.icon:SetTexture(C_Item.GetItemIconByID and C_Item.GetItemIconByID(entry.item))
			else
				button.icon:SetTexture(C_Spell.GetSpellTexture(entry.spell))
				NoteCharges(entry.spell)
			end
			StyleIcon(button, db)
			UpdateCooldown(button)
			UpdateState(button)
			RefreshProc(button)
		end
		if row.dress then
			row.dress(button, entry, row)
		elseif button.groupDressed and M.UndressIcon then
			M.UndressIcon(button)
		end
		button:Show()
		shown[#shown + 1] = button
	end
	for index = #list + 1, #pool do
		local button = pool[index]
		button.spellID, button.itemID, button.slot, button.bagItem = nil, nil, nil, nil
		button.placeholder, button.token, button.listIndex = nil, nil, nil
		HideProc(button)
		SetReady(button, false)
		if row.dress then row.dress(button, nil, row) end
		button:Hide()
	end
	local Layout = row.layout or M.Grid
	local placed
	if base.kind == "viewer" then
		M.PlaceHolder(M.VIEWERS[base.viewer])
		Layout(shown, frame, db)
		local corner = M.StartCorner(db)
		frame:ClearAllPoints()
		frame:SetPoint(corner, holder, corner, 0, 0)
		placed = { corner, holder, corner, 0, 0 }
	elseif base.kind == "extra" then
		local grid = ExtraGrid(db)
		Layout(shown, frame, grid)
		PlaceExtra(base, frame, grid)
	else
		-- An own group or a free icon: its own mover, sized like the icons.
		Layout(shown, frame, db)
		local corner = M.StartCorner(db)
		local width, height = frame:GetSize()
		holder:SetSize(math.max(width, 8), math.max(height, 8))
		frame:ClearAllPoints()
		frame:SetPoint(corner, holder, corner, 0, 0)
	end
	-- A group with its own visibility block uses it. Otherwise the
	-- rows follow the visibility rule of the viewer they stand in for; the
	-- extra rows, own groups and free icons follow the essential viewer.
	local fader
	if type(row.visibility) == "table" then
		fader = K.Visibility("cdmrow-" .. row.key, frame, row.visibility)
	else
		local vis = base.kind == "viewer" and db or M.db.viewers.essential
		fader = K.Visibility("cdmrow-" .. row.key, frame, type(vis.fade) == "table" and vis.fade or "always")
	end
	if ObserveRowGeometry then ObserveRowGeometry(fader, true) end
	frame:SetParent(fader)
	frame:SetShown(#shown > 0)
	BuildAuraSlots(row, shown)
	local pass = rowCommit
	if pass.phase == "building" and pass.current and pass.current[row.key] and CurrentCommit(pass)
		and Same(rowFrames[row.key], frame) and rowOrigins[frame] and rowOrigins[frame].key == row.key then
		pass.records[row.key] = { row = row, base = base, frame = frame, active = #shown > 0,
			parent = fader, anchor = placed or (rowAnchors[frame] and { unpack(rowAnchors[frame]) }) }
	end
end

local function ForEachIcon(fn)
	for _, row in ipairs(AllRows()) do
		local frame = rowFrames[row.key]
		if frame and frame:IsShown() then
			for _, button in ipairs(icons[row.key]) do
				if button:IsShown() and not button.placeholder then fn(button) end
			end
		end
	end
end

local ROW_EVENTS = { "SPELL_UPDATE_USABLE", "SPELLS_CHANGED",
	"PLAYER_REGEN_ENABLED", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED",
	"SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "PLAYER_TARGET_CHANGED",
	"SPELL_RANGE_CHECK_UPDATE" }

local function GlowEvent(_, event, spellID)
	if not spellID or not K.Plain(spellID) then return end
	ForEachIcon(function(button)
		if button.spellID == spellID then
			if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then ShowProc(button) else HideProc(button) end
		end
	end)
end

local function RangeEvent(_, _, spellIdentifier)
	if not K.Plain(spellIdentifier) then return end
	local id = tonumber(spellIdentifier)
	ForEachIcon(function(button)
		if not id or button.spellID == id then UpdateState(button) end
	end)
end

local function TargetChanged()
	-- The target's auras: the slot containers read the new target.
	for _, entry in pairs(auraSlots) do
		if entry.target and E.AuraWidget then E.AuraWidget.Refresh(entry.target) end
	end
	ForEachIcon(UpdateState)
end

-- Old single glow setting (rows.glow) -> the Cooldown rows: proc row on
-- General > Glows.
local function Migrate()
	local old = M.db.rows.glow
	if old == nil then return end
	M.db.rows.glow = nil
	local glows = E.db and E.db.glows
	local proc = glows and glows.cooldownProc
	if not proc then return end
	if old == "none" then proc.style = "none" elseif old == "pixel" then proc.style = "pixel" end
end

function M:ApplyRows()
	Migrate()
	local selected, current = RowList(), {}
	local pass = { serial = rowCommit.serial + 1, phase = "building", db = M.db, root = E.db,
		profile = E.profileName, active = M.active, rows = M.db.rows, viewers = M.db.viewers, groups = M.GroupRows,
		records = {}, settings = {}, current = current }
	rowCommit = pass
	for _, row in ipairs(selected) do
		if current[row.key] then pass.ambiguous = true end
		current[row.key] = true
		local base = row.from and ROW_BY_KEY[row.from] or row
		local db, values = RowDB(row), {}
		for _, key in ipairs(ROW_GEOMETRY) do values[key] = rawget(db, key) end
		pass.settings[#pass.settings + 1] = { db = db, base = base, values = values }
	end
	for _, row in ipairs(AllRows(selected)) do
		if not CurrentCommit(pass) then return end
		BuildRow(row, current[row.key] or false)
		if not CurrentCommit(pass) then return end
	end
	pass.phase = "attaching"
	local body = Body(true)
	pass.pending = 0
	if body.kind == "live" then
		for _, item in pairs(pass.records) do
			local db = RowDB(item.row)
			if item.active and item.base.kind == "extra" and db.attach == "essential" then pass.pending = pass.pending + 1 end
		end
		for _, item in pairs(pass.records) do
			local db = RowDB(item.row)
			if item.active and item.base.kind == "extra" and db.attach == "essential" then
				local frame = item.frame
				local function Owns()
					return CurrentCommit(pass) and Same(rowFrames[item.row.key], frame)
						and rowOrigins[frame] and rowOrigins[frame].key == item.row.key and db.attach == "essential" and body.current()
				end
				local clear, set, count, point, parent = frame.ClearAllPoints, frame.SetPoint, frame.GetNumPoints, frame.GetPoint, frame.GetParent
				local function Current()
					return Owns() and Same(frame.ClearAllPoints, clear) and Same(frame.SetPoint, set)
						and Same(frame.GetNumPoints, count) and Same(frame.GetPoint, point) and Same(frame.GetParent, parent)
				end
				local function Invalidate() if CurrentCommit(pass) then pass.phase = "unavailable" end end
				K.Safe(frame, function()
					if not Current() then return end
					local n = count(frame)
					local actual = { point(frame, 1) }
					if not Number(n) or n ~= 1 or not Same(parent(frame), item.parent) or not Current() or not item.anchor then Invalidate(); return end
					for i = 1, 5 do if not Same(actual[i], item.anchor[i]) then Invalidate(); return end end
					local side = db.side or "RIGHT"
					local gap = db.gap or 0
					if not K.Plain(side) or not Number(gap) then return end
					clear(frame)
					if not Current() then return end
					local remaining = count(frame)
					if not Number(remaining) or remaining ~= 0 or not Current() then Invalidate(); return end
					local x = side == "LEFT" and -gap or (side == "RIGHT" and gap or 0)
					local y = side == "BOTTOM" and -gap or (side == "TOP" and gap or 0)
					set(frame, OPPOSITE[side], body.frame, side, x, y)
					if Current() then
						rowAnchors[frame] = { OPPOSITE[side], body.frame, side, x, y }
						item.anchor = { unpack(rowAnchors[frame]) }
						pass.pending = pass.pending - 1
						if pass.pending == 0 then pass.phase = "ready"; PublishRows() end
					end
				end)
			end
		end
	end
	if pass.phase == "attaching" and pass.pending == 0 then pass.phase = "ready" end
	local any = false
	for _, row in ipairs(AllRows(selected)) do
		if rowFrames[row.key] and rowFrames[row.key]:IsShown() then any = true end
	end
	if any then
		-- Own owner key: the module's own SPELLS_CHANGED handler stays.
		local function Update() M:UpdateRowCooldowns() end
		local function Rebuild() C_Timer.After(0.2, function() M:ApplyRows() end) end
		-- Cooldowns and charges come from the combat kit's cooldown source.
		CD.Subscribe(GROUP, Update)
		E:RegisterEvent("SPELL_UPDATE_USABLE", Update, GROUP)
		E:RegisterEvent("BAG_UPDATE_DELAYED", function()
			-- Items that ran out (or came back) change the row with "Hide".
			if M.db.rows.items.enabled and M.db.rows.items.empty == "hide" then Rebuild() else Update() end
		end, GROUP)
		E:RegisterEvent("SPELLS_CHANGED", Rebuild, GROUP)
		E:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", Rebuild, GROUP)
		E:RegisterEvent("PLAYER_REGEN_ENABLED", function() M:ApplyRows() end, GROUP)
		E:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", GlowEvent, GROUP)
		E:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", GlowEvent, GROUP)
		E:RegisterEvent("PLAYER_TARGET_CHANGED", TargetChanged, GROUP)
		if M.db.rows.range.enabled then
			E:RegisterEvent("SPELL_RANGE_CHECK_UPDATE", RangeEvent, GROUP)
		else
			E:UnregisterEvent("SPELL_RANGE_CHECK_UPDATE", GROUP)
		end
	else
		for _, event in ipairs(ROW_EVENTS) do E:UnregisterEvent(event, GROUP) end
		CD.Unsubscribe(GROUP)
	end
	UpdateRangeChecks()
	PublishRows()
	if not E.Tour:Seen("cooldowns:rows") and not M.rowsHelpWaiting then
		-- Blizzard's viewers fill in a moment after login: ask again then.
		M.rowsHelpWaiting = true
		C_Timer.After(5, function()
			M.rowsHelpWaiting = nil
			E.Tour:Offer("cooldowns:rows")
		end)
	end
end

-- Tour help: the first time EldoUI's main row stands in for Blizzard's
-- empty Cooldown Manager while no spells are picked for it (once per
-- account).
local function EmptyStandIn()
	if not (M.active and M.db.rows.mode == "auto") then return false end
	if M.db.cdgroups and M.db.cdgroups.enabled then return false end
	if ListText("main") ~= "" or ListText("utility") ~= "" then return false end
	return not BlizzardHasData(ROW_BY_KEY.main)
end

local function MainHolder()
	local holder = K.GetHolder(M.VIEWERS.essential.mover)
	if holder and holder:IsVisible() then return holder end
end

E.Tour:Register("cooldowns:rows", {
	form = "spot", word = "cooldowns",
	offer = function(_, force)
		if not EmptyStandIn() then return false end
		return E.Tour:Spot("cooldowns:rows", {
			force = force, target = MainHolder() and MainHolder or nil,
			title = L["Your cooldown rows"],
			text = L["Blizzard's Cooldown Manager shows no spells here, so EldoUI's own cooldown rows take its place. They stay empty until you pick your spells for the Main and Utility rows in /eui cooldownmanager."],
		})
	end,
	replay = function(def)
		if not EmptyStandIn() then
			E:Print(L["This help shows while EldoUI's cooldown rows stand in for Blizzard's and have no spells yet."])
			return
		end
		def.offer(def, true)
	end,
})

function M:UpdateRowCooldowns()
	ForEachIcon(function(button)
		if button.bagItem then
			local count = ItemCount(button.itemID)
			button.count0 = count == 0
		end
		UpdateCooldown(button)
		UpdateState(button)
	end)
end

function M:UpdateRowKeybinds()
	for _, row in ipairs(AllRows()) do
		local db = RowDB(row)
		for _, button in ipairs(icons[row.key] or {}) do
			if button.spellID or button.itemID then StyleIcon(button, db) end
		end
	end
end

-- Read-only views of the rows.
M.rowIcons, M.rowAuraSlots, M.CountdownFormatter = icons, auraSlots, RowFormatter
M.rowFrames = rowFrames

-- Shared with Cooldown Groups (CooldownGroups.lua), which turns the
-- fixed rows into groups and builds group rows from the same pieces.
M.RowParts = {
	ROWS = ROWS, CLASS = CLASS, MOBILITY = MOBILITY,
	ListText = ListText, OwnSpell = OwnSpell, ItemCount = ItemCount, TrinketList = TrinketList,
	Placeholder = PLACEHOLDER_ICON,
}

function M:HideRows()
	rowCommit = { serial = rowCommit.serial + 1, phase = "inactive" }
	nativeBody = nil
	for _, row in ipairs(AllRows()) do
		if rowFrames[row.key] then rowFrames[row.key]:Hide() end
		if row.kind == "extra" and K.GetHolder(row.mover) then K.GetHolder(row.mover):Hide() end
		if row.holderName and K.GetHolder(row.holderName) then K.GetHolder(row.holderName):Hide() end
		for _, button in ipairs(icons[row.key] or {}) do
			HideProc(button)
			SetReady(button, false)
		end
		K.StopVisibility("cdmrow-" .. row.key)
		if auraSlots[row.key] then
			local entry = auraSlots[row.key]
			E:RunOutOfCombat(function() ReleaseAuraSlots(entry) end)
		end
	end
	for _, event in ipairs(ROW_EVENTS) do E:UnregisterEvent(event, GROUP) end
	CD.Unsubscribe(GROUP)
	UpdateRangeChecks()
	PublishRows()
end

-- The item row, attached under the main row, is the first piece below it
-- on the cooldown stack (K.CooldownStack): the tracking bars and the
-- player cast bar hang under it instead of over it.
K.CooldownStack.Register("items", {
	frame = function()
		local db = M.db and M.db.rows and M.db.rows.items
		local frame = rowFrames.items
		if not (M.active and db and frame and frame:IsShown()) then return nil end
		if db.attach ~= "essential" or db.side ~= "BOTTOM" then return nil end
		return frame
	end,
	gap = function() return M.db.rows.items.gap or 0 end,
})

K.CooldownStack.RegisterBodySource(M, Body, function(observe) ObserveRowGeometry = observe end)
if E.RefreshWideConsumableLayout then E:RefreshWideConsumableLayout(M) end
hooksecurefunc(M, "Apply", function()
	nativeBody = nil
	if not (M.active and M.db and E:BlizzardAllowed("cooldown-viewer", "move") and M.db.viewers.essential.enabled) then return end
	local frame = rawget(_G, M.VIEWERS.essential.global)
	if not frame or not K.IsPinned(frame) then return end
	local pin = E.BlizzardKeep.pins[frame]
	nativeBody = { frame = frame, pin = pin, db = M.db, root = E.db, profile = E.profileName }
	if not nativeWatched[frame] then
		local function Changed()
			if nativeBody and Same(nativeBody.frame, frame) and K.IsPinned(frame, nativeBody.pin) then PublishRows() end
		end
		for _, method in ipairs({ "SetSize", "SetWidth", "SetHeight" }) do hooksecurefunc(frame, method, Changed) end
		nativeWatched[frame] = ObserveRowGeometry and ObserveRowGeometry(frame)
		if type(nativeWatched[frame]) ~= "function" then nativeBody = nil;return end
	end
	PublishRows()
end)

-- A glow row changed on General > Glows: the ready and aura glows may have
-- been switched on or off.
hooksecurefunc(E, "RefreshGlows", function()
	if M.active and M.db then M:ApplyRows() end
end)

-- Movers for the extra rows (created with the viewer holders).
hooksecurefunc(M, "CreateHolders", function(self)
	for _, row in ipairs(ROWS) do
		if row.kind == "extra" and not K.GetHolder(row.mover) then
			local db = self.db.rows[row.key]
			K.Holder(self, row.mover, L[row.title], row.point, 2 * db.size + db.spacing, db.size):Hide()
		end
	end
end)

-- Blizzard's viewers fill a moment after login; check "auto" again then.
E:RegisterEvent("PLAYER_ENTERING_WORLD", function()
	C_Timer.After(2, function()
		if M.active then M:ApplyRows() end
	end)
end, GROUP)

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local function NoRows() return M.db.rows.mode == "off" end
-- Own groups on: the icons are listed per group on the Groups tab.
local function GroupsOn() return M.db.cdgroups and M.db.cdgroups.enabled and true or false end
local function NoLists() return NoRows() or GroupsOn() end
local CLASS_LABEL = type(CLASS_NAME) == "string" and CLASS_NAME or CLASS
local SIDES = { LEFT = "Left of it", RIGHT = "Right of it", TOP = "Above", BOTTOM = "Below" }
local TEXT_POINTS = { CENTER = "Center", TOP = "Top", BOTTOM = "Bottom", LEFT = "Left", RIGHT = "Right",
	TOPLEFT = "Top left", TOPRIGHT = "Top right", BOTTOMLEFT = "Bottom left", BOTTOMRIGHT = "Bottom right" }

local rowsOptions = {
	{ type = "tab", label = "Own rows" },
	{ type = "description",
		label = "EldoUI's own cooldown rows. The game draws each cooldown; EldoUI picks what shows and where. Their glows are on the Glows page." },
	{ type = "header", label = "Main and utility rows" },
	{ type = "select", key = "rows.mode", label = "Own rows",
		values = { off = "Off", auto = "When Blizzard's is empty", always = "Always" },
		desc = "When Blizzard's Cooldown Manager has no spells for your class, these rows stand in for its viewers. Always: they always show (hide Blizzard's viewers if both show)." },
	{ type = "description", label = "Own groups are on: the icons of every row are listed on the Groups tab.", hidden = function() return not GroupsOn() end },
	{ type = "input", key = "rows.lists." .. CLASS .. ".main", label = "Main row", hidden = NoLists,
		desc = "Spell names or IDs for %s, separated by commas, in the order they should show. Type a spell twice to show it twice.", descFill = CLASS_LABEL },
	{ type = "input", key = "rows.lists." .. CLASS .. ".utility", label = "Utility row", hidden = NoLists,
		desc = "Spell names or IDs for %s for the second row (defensives, interrupts, movement). A spell may also be in the main row.", descFill = CLASS_LABEL },
}

for _, row in ipairs(ROWS) do
	if row.kind == "extra" then
		local p = "rows." .. row.key .. "."
		local function Off() return not M.db.rows[row.key].enabled end
		local function NotAttached() return Off() or M.db.rows[row.key].attach ~= "essential" end
		local title = row.label
		table.insert(rowsOptions, { type = "header", label = title })
		local descs = {
			trinkets = L["Your equipped trinkets, with their cooldowns."],
			mobility = L["Movement and escape spells of your class (Charge, Blink, Sprint, ...), with their cooldowns."],
			items = L["Potions, healthstones and other items from your bags that you list, with how many you carry and their cooldowns."],
		}
		table.insert(rowsOptions, { type = "toggle", key = p .. "enabled", label = "Enable", desc = descs[row.key] })
		if row.key == "mobility" then
			table.insert(rowsOptions, { type = "input", key = "rows.lists." .. CLASS .. ".mobility", label = "Spells", hidden = function() return Off() or GroupsOn() end,
				desc = "Spell names or IDs for %s. Empty uses EldoUI's list for your class.", descFill = CLASS_LABEL })
		elseif row.key == "trinkets" then
			table.insert(rowsOptions, { type = "toggle", key = p .. "onUseOnly", label = "Only trinkets with a use effect", hidden = Off,
				desc = "On: trinkets without a use effect stay out of the row. Off: both trinket slots always show." })
		elseif row.key == "items" then
			table.insert(rowsOptions, { type = "input", key = p .. "list", label = "Items", hidden = function() return Off() or GroupsOn() end,
				desc = "Item names or IDs, separated by commas, in the order they should show (for example Major Healing Potion, 5512). Names work for items in your bags." })
			table.insert(rowsOptions, { type = "select", key = p .. "empty", label = "When none are left", hidden = Off,
				values = { dim = "Show it faded", hide = "Hide it" },
				desc = "What an item looks like when your bags hold none of it." })
		end
		table.insert(rowsOptions, { type = "select", key = p .. "attach", label = "Position", hidden = Off,
			values = function() return { essential = L["Next to the essential row"], mover = L["Own mover"] } end,
			desc = "Next to the essential row follows it; own mover can be dragged in move mode." })
		table.insert(rowsOptions, { type = "select", key = p .. "side", label = "Side", values = SIDES, hidden = NotAttached,
			desc = "Which side of the essential row the icons sit on." })
		table.insert(rowsOptions, { type = "range", key = p .. "gap", label = "Gap", min = 0, max = 40, step = 1, hidden = NotAttached,
			desc = "Space to the essential row." })
		table.insert(rowsOptions, { type = "range", key = p .. "size", label = "Icon size", min = 20, max = 64, step = 1, hidden = Off,
			desc = "Width and height of each icon." })
		table.insert(rowsOptions, { type = "range", key = p .. "perRow", label = "Icons per row", min = 4, max = 16, step = 1, hidden = Off,
			desc = "Icons in one row before a new one starts." })
		table.insert(rowsOptions, { type = "range", key = p .. "spacing", label = "Spacing", min = 0, max = 20, step = 1, hidden = Off,
			desc = "Space between icons." })
	end
end

-- Row look: one row at a time (Row), the rest edits that row.
local ROW_VALUES = {}
for _, row in ipairs(ROWS) do ROW_VALUES[row.key] = row.label or row.title end
local function LookKey(field)
	return function()
		local key = M.db and M.db.rows.edit
		if not ROW_VALUES[key] then key = "main" end
		return "rows.looks." .. key .. "." .. field
	end
end
local function EditLook() return LookOf(M.db.rows.edit) end
local function NoRange() return not M.db.rows.range.enabled end

local lookOptions = {
	{ type = "tab", label = "Row look" },
	{ type = "description", label = "How icons in EldoUI's rows look in each state the game reports: on cooldown, recharging, not usable or out of range." },
	{ type = "select", key = "rows.edit", label = "Row", values = ROW_VALUES,
		desc = "The row the settings below change. Each row has its own look." },
	{ type = "header", label = "On cooldown", fold = true },
	{ type = "range", key = LookKey("cdAlpha"), label = "Opacity", unit = "%", min = 0, max = 100, step = 5,
		desc = "How visible an icon is while its spell or item is on cooldown. 100 = fully visible." },
	{ type = "toggle", key = LookKey("cdDesat"), label = "Gray",
		desc = "Show the icon in gray while it is on cooldown." },
	{ type = "header", label = "Recharging", fold = true },
	{ type = "range", key = LookKey("rechargeAlpha"), label = "Opacity", unit = "%", min = 0, max = 100, step = 5,
		desc = "Spells with charges: how visible the icon is while a charge comes back and at least one is left." },
	{ type = "toggle", key = LookKey("rechargeDesat"), label = "Gray",
		desc = "Spells with charges: gray while a charge comes back." },
	{ type = "header", label = "Not usable", fold = true },
	{ type = "range", key = LookKey("unusableAlpha"), label = "Opacity", unit = "%", min = 0, max = 100, step = 5,
		desc = "How visible an icon is while the game says you can't cast it (not enough mana, rage or energy, or a missing requirement)." },
	{ type = "toggle", key = LookKey("unusableDesat"), label = "Gray",
		desc = "Show the icon in gray while you can't cast it." },
	{ type = "toggle", key = LookKey("unusableTint"), label = "Tint",
		desc = "Color the icon while you can't cast it, like action buttons without enough mana." },
	{ type = "color", key = LookKey("unusableColor"), label = "Tint color",
		hidden = function() return not EditLook().unusableTint end,
		desc = "The color for icons you can't cast." },
	{ type = "header", label = "Countdown", fold = true },
	{ type = "select", key = LookKey("timeFormat"), label = "Format", values = { short = "Short (12, 2m)", mmss = "Minutes and seconds (1:30)" },
		desc = "How the time left is written. The game formats it; EldoUI only picks the format." },
	{ type = "range", key = LookKey("timeBelow"), label = "Only below", unit = "s", min = 0, max = 600, step = 5,
		zeroText = "Always", desc = "Show the countdown only once fewer seconds than this are left." },
	{ type = "toggle", key = LookKey("timeColors"), label = "Color by time left",
		desc = "Use the shared cooldown colors (Fonts and text > Cooldown numbers): one for minutes, one for seconds, red near the end." },
	{ type = "color", key = LookKey("timeColor"), label = "Color",
		hidden = function() return EditLook().timeColors ~= false end,
		desc = "One color for the countdown when Color by time left is off." },
	{ type = "select", key = LookKey("timePoint"), label = "Position", values = TEXT_POINTS,
		desc = "Where the countdown sits on the icon." },
	{ type = "header", label = "Charges and item count", fold = true },
	{ type = "select", key = LookKey("countPoint"), label = "Position", values = TEXT_POINTS,
		desc = "Where the charge count (or the item count in the item row) sits on the icon." },
	{ type = "color", key = LookKey("countColor"), label = "Color",
		desc = "Color of the charge or item count." },
	{ type = "header", label = "Cooldown swipe (all rows)", fold = true },
	{ type = "toggle", key = "rows.gcd", label = "Hide the global cooldown",
		desc = "No swipe while only the global cooldown runs after a cast, so the rows show real cooldowns only. The game flags the global cooldown itself." },
	{ type = "toggle", key = "rows.swipe.reverse", label = "Reverse swipe",
		desc = "The dark part shows the time that has passed instead of the time left." },
	{ type = "color", key = "rows.swipe.color", label = "Swipe color",
		desc = "Color of the dark cooldown swipe." },
	{ type = "range", key = "rows.swipe.alpha", label = "Swipe darkness", unit = "%", min = 0, max = 100, step = 5,
		zeroText = "Off", desc = "How dark the swipe is." },
	{ type = "toggle", key = "rows.swipe.edge", label = "Bright edge", cog = true,
		desc = "A bright line along the edge of the swipe." },
	{ type = "toggle", key = "rows.swipe.bling", label = "Flash when ready", cog = true,
		desc = "The game's short flash when a cooldown ends." },
	{ type = "range", key = "rows.swipe.inset", label = "Swipe inset", min = 0, max = 6, step = 1, cog = true,
		desc = "Keeps the swipe this many pixels inside the icon edge." },
	{ type = "header", label = "Out of range (all rows)", fold = true },
	{ type = "toggle", key = "rows.range.enabled", label = "Mark out of range",
		desc = "Tint spells red while the game says your target is out of their range." },
	{ type = "color", key = "rows.range.color", label = "Color", hidden = NoRange,
		desc = "Tint for spells your target is out of range of." },
	{ type = "toggle", key = "rows.range.shadow", label = "Dark shadow", hidden = NoRange,
		desc = "Also darken the icon while the target is out of range." },
}

for _, option in ipairs(rowsOptions) do
	table.insert(M.options, option)
end
for _, option in ipairs(lookOptions) do
	table.insert(M.options, option)
end
