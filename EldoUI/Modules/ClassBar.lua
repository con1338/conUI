-- EldoUI Class Bar: one small bar for every class but the shaman (who has
-- the Shaman Totems cooldown bar). In order:
--   * upkeep icons: the class buffs, auras, armors and aspects you keep up,
--     with the same spell and rank pick as the Buff and Consumable
--     Reminders (one pick serves both; right-click an icon to change it).
--     Rogues get one icon per weapon for the poison picked for that hand.
--   * key cooldowns of the class, each once you know it;
--   * the reagents the class spends (Soul Shards, powders, candles,
--     symbols, seeds) and a hunter's ammo, with the count you carry.
-- Every icon can be switched off on the options page. Click an icon to
-- cast it; nothing is ever cast on its own.
--
-- How it reads the game:
--   * An upkeep buff is an aura slot of the game's own aura container: the
--     client draws the live buff (with its time) over a faded copy of the
--     icon, so a missing buff shows faded in combat too, while EldoUI never
--     reads auras in combat. The missing glow needs a read, so it shows out
--     of combat only.
--   * Poisons come from the game's weapon enchant info, which stays
--     readable in combat; a secret answer leaves the icon as it was.
--   * Cooldowns are the game's duration objects drawn by the cooldown
--     widget, through EldoUI's one cooldown source.
--   * Secure action buttons get their spells out of combat only.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local M = E:NewModule("ClassBar", {
	title = "Class Bar",
	category = "Combat",
	desc = "Every class but the shaman: one bar with the buffs you keep up (live, faded while missing), your key cooldowns and the reagents you spend. Click casts; right-click picks the spell and rank.",
	frames = { "EldoUI_ClassBarHolder", "EldoUI_ClassBar" },
	movers = { "EldoUI_ClassBar" },
	savedKeys = { "profile.modules.ClassBar", "private.classBarRanks" },
	optionsPage = "module:ClassBar",
	presets = { "Standard", "Compact", "Large", "Vertical", "Quiet" },
	reload = false,
	defaults = {
		enabled = false,     -- a new bar on screen: the player (or a class premade) turns it on
		size = 30,
		spacing = 4,
		vertical = false,
		perRow = 10,         -- icons before the next row: a full bar keeps clear of the unit frames
		upkeep = true,       -- the buffs you keep up
		cooldowns = true,    -- key cooldowns
		counts = true,       -- reagents and ammo
		missingGlow = true,  -- a soft glow on a missing buff or poison (out of combat)
		show = {},           -- [icon key] = false: that icon is switched off (filled below)
		visibility = E:VisibilityDefaults(),
	},
})
E.ClassBar = M
E:RegisterPrivate("classBarRanks", {})
E:RegisterVisibilityFacet("EldoUI_ClassBar", "rules", { module = "ClassBar", setting = "visibility" })

local D = E.ClassBarData or {}
local Plain = E.Plain
local Secret = E.Secret
local MAX_ICONS = 24
local DEFAULT_POINT = { "CENTER", "UIParent", "CENTER", 0, -268 }
local MAIN, OFF = INVSLOT_MAINHAND or 16, INVSLOT_OFFHAND or 17
local AMMO = INVSLOT_AMMO or 0
local AMMO_ICON = "Interface\\Icons\\INV_Ammo_Arrow_02"

E:RegisterGlowUser("classBarMissing", {
	title = "Class Bar: missing buff or poison",
	desc = "An upkeep icon of the class bar while its buff or poison is missing (out of combat).",
	order = 49,
	button = true,
	default = { style = "pixel", colorMode = "custom", color = { 1, 0.27, 0.27 } },
})

-- The option key of an icon: the reminder slot key, or "<class>_<key>".
local function SpellKey(class, item) return class:lower() .. "_" .. item.key end
M.SpellKey = SpellKey

for class, data in pairs(D) do
	for _, key in ipairs(data.upkeep or {}) do M.defaults.show[key] = true end
	for _, item in ipairs(data.spells or {}) do M.defaults.show[SpellKey(class, item)] = true end
	for _, item in ipairs(data.counts or {}) do M.defaults.show[SpellKey(class, item)] = true end
end

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
end

local function PlayerClass()
	local _, class = UnitClass("player")
	if Secret(class) then return nil end
	return class
end

-- On and drawing: the module is on and the class has a bar here.
function M:Drawing()
	local class = PlayerClass()
	return self.active and class ~= nil and class ~= "SHAMAN" and D[class] ~= nil
end

local function Reminders() return E.modules.Reminders end

---------------------------------------------------------------------------
-- Spell knowledge
---------------------------------------------------------------------------
local function KnownId(id)
	local book = C_SpellBook
	if type(id) ~= "number" or not book then return false end
	for _, check in ipairs({ book.IsSpellKnown, book.IsSpellInSpellBook }) do
		if Plain(Try(check, id)) then return true end
	end
	return false
end

local function SpellFits(spell)
	if not spell.race then return true end
	local _, _, race = Try(UnitRace, "player")
	return Plain(race) == spell.race
end

local function SpellName(id)
	local name = C_Spell and C_Spell.GetSpellName and Plain(Try(C_Spell.GetSpellName, id))
	if type(name) == "string" and name ~= "" then return name end
	local info = C_Spell and C_Spell.GetSpellInfo and Try(C_Spell.GetSpellInfo, id)
	name = type(info) == "table" and Plain(info.name)
	return type(name) == "string" and name ~= "" and name or nil
end

local function SpellIcon(id)
	local icon = C_Spell and C_Spell.GetSpellTexture and Plain(Try(C_Spell.GetSpellTexture, id))
	if icon then return icon end
	local info = C_Spell and C_Spell.GetSpellInfo and Try(C_Spell.GetSpellInfo, id)
	return type(info) == "table" and Plain(info.iconID) or nil
end

-- The highest rank of a rank 1 spell you know (its ID), or nil. The game's
-- spell info for a name is the rank in your spellbook.
local function KnownSpell(id)
	local best = KnownId(id) and id or nil
	local name = SpellName(id)
	local info = name and C_Spell and C_Spell.GetSpellInfo and Try(C_Spell.GetSpellInfo, name)
	local byName = type(info) == "table" and Plain(info.spellID)
	if type(byName) == "number" and byName ~= id and SpellName(byName) == name and KnownId(byName) then best = byName end
	return best, name
end
M.KnownSpell = KnownSpell

local function RankPicks()
	local picks = E:GetPrivate("classBarRanks")
	return not Secret(picks) and type(picks) == "table" and picks or nil
end

local function CooldownSpell(key)
	if Secret(key) or type(key) ~= "string" then return nil end
	local class = PlayerClass()
	for _, spell in ipairs(class and D[class] and D[class].spells or {}) do
		if SpellKey(class, spell) == key and SpellFits(spell) then return spell end
	end
end

-- A chosen rank stays exact while known; otherwise the usual highest rank wins.
local function ChosenSpell(spell, key)
	local best, name = KnownSpell(spell.id)
	local picks = RankPicks()
	local picked = picks and Plain(picks[key])
	if best and name and KnownId(picked) and SpellName(picked) == name then return picked, name, true end
	return best, name, false
end

local function RankNumber(id)
	local bars = E.modules.ActionBars
	local rank = bars and Plain(Try(bars.SpellRankNumber, id))
	if type(rank) == "number" and rank > 0 and rank % 1 == 0 then return rank end
end

-- Reuse the action bars' spellbook scan; only known ranks of this spell appear.
function M:CooldownRanks(key)
	local spell = CooldownSpell(key)
	local name = spell and SpellName(spell.id)
	local bars = E.modules.ActionBars
	local scan = name and bars and Plain(Try(bars.RankScan, bars))
	local ids = type(scan) == "table" and Plain(scan.ids)
	local list = type(ids) == "table" and Plain(ids[name])
	local ranks, seen = {}, {}
	local function Add(id)
		id = Plain(id)
		if not KnownId(id) or seen[id] or SpellName(id) ~= name then return end
		local rank = RankNumber(id)
		if not rank then return end
		seen[id] = true
		ranks[#ranks + 1] = { id = id, rank = rank }
	end
	for _, id in ipairs(type(list) == "table" and list or {}) do Add(id) end
	if spell then Add((KnownSpell(spell.id))) end
	table.sort(ranks, function(a, b)
		if a.rank ~= b.rank then return a.rank < b.rank end
		return a.id < b.id
	end)
	return ranks
end

-- nil chooses the highest rank again. Secure attributes follow the same
-- out-of-combat refresh as a learned spell or another Class Bar setting.
function M:SetCooldownRank(key, rank)
	if Secret(key) or type(key) ~= "string" or Secret(rank)
		or (rank ~= nil and type(rank) ~= "number") then return false end
	local spell, picks = CooldownSpell(key), RankPicks()
	local name = spell and SpellName(spell.id)
	if not (spell and picks and name and KnownSpell(spell.id)) then return false end
	if rank ~= nil and (not KnownId(rank) or SpellName(rank) ~= name) then return false end
	local previous, character = rawget(picks, key), E.charKey
	if Secret(previous) then return false end
	E:RunOutOfCombat(function()
		if E.charKey ~= character or RankPicks() ~= picks or Secret(rawget(picks, key))
			or not rawequal(rawget(picks, key), previous) or CooldownSpell(key) ~= spell then return end
		if not KnownSpell(spell.id) or (rank ~= nil and (not KnownId(rank) or SpellName(rank) ~= name)) then return end
		picks[key] = rank
		M:Refresh()
	end, "ClassBar:rank:" .. key)
	return true
end

local function AnyKnown(list)
	for _, id in ipairs(list or {}) do
		if KnownSpell(id) then return true end
	end
	return false
end

local function ItemCount(items)
	local total = 0
	for _, id in ipairs(items or {}) do
		local count = C_Item and C_Item.GetItemCount and Plain(Try(C_Item.GetItemCount, id))
		if type(count) == "number" then total = total + count end
	end
	return total
end

local function ItemIcon(id)
	return id and C_Item and C_Item.GetItemIconByID and Plain(Try(C_Item.GetItemIconByID, id)) or nil
end

local function AmmoItem()
	local id = GetInventoryItemID and Plain(Try(GetInventoryItemID, "player", AMMO))
	return type(id) == "number" and id or nil
end

local function HasOffHandWeapon()
	local id = GetInventoryItemID and Plain(Try(GetInventoryItemID, "player", OFF))
	if type(id) ~= "number" then return false end
	if not (C_Item and C_Item.GetItemInfoInstant) then return false end
	local ok, _, _, _, _, _, classID = pcall(C_Item.GetItemInfoInstant, id)
	return ok and Plain(classID) == (Enum.ItemClass and Enum.ItemClass.Weapon or 2)
end

---------------------------------------------------------------------------
-- What the bar shows, in order
---------------------------------------------------------------------------
-- Every rank of the lines that meet an upkeep slot (its aura can carry
-- any of them).
local function UpkeepIds(counts)
	local ids, seen = {}, {}
	for _, ranks in pairs(counts or {}) do
		for _, id in ipairs(ranks) do
			if not seen[id] then
				seen[id] = true
				ids[#ids + 1] = id
			end
		end
	end
	table.sort(ids)
	return ids
end

local function Shown(key)
	return M.db.show[key] ~= false
end

-- The list of icons: { kind ("upkeep", "poison", "spell", "count"), key,
-- spell, name, icon, ... }.
function M:Items()
	local class = PlayerClass()
	local data = class and D[class]
	local items = {}
	if not data then return items end
	local db, R = self.db, Reminders()
	if db.upkeep and R and R.SlotByKey then
		for _, key in ipairs(data.upkeep or {}) do
			local slot = R.SlotByKey(key)
			if slot and Shown(key) and (not R.SlotFits or R.SlotFits(slot)) then
				if slot.poison then
					local hand = slot.weapon
					if hand == "main" or HasOffHandWeapon() then
						local line = R:PoisonPick(hand)
						local item = line and R.BestPoison(line)
						items[#items + 1] = { kind = "poison", key = key, slot = slot, hand = hand, line = line, item = item,
							icon = ItemIcon(item or (line and line.items[#line.items])) or SpellIcon(slot.spells[1][1]),
							name = SpellName(slot.spells[1][1]) }
					end
				else
					local names, best, counts = R.SlotInfo(slot)
					if names then
						items[#items + 1] = { kind = "upkeep", key = key, slot = slot, spell = best, name = SpellName(best),
							icon = SpellIcon(best), ids = UpkeepIds(counts) }
					end
				end
			end
		end
	end
	if db.cooldowns then
		for _, spell in ipairs(data.spells or {}) do
			local key = SpellKey(class, spell)
			if SpellFits(spell) and Shown(key) then
				local best, name, picked = ChosenSpell(spell, key)
				if best then
					items[#items + 1] = { kind = "spell", key = key, spell = best, name = name, icon = SpellIcon(best),
						base = spell.id, picked = picked }
				end
			end
		end
	end
	if db.counts then
		for _, count in ipairs(data.counts or {}) do
			local key = SpellKey(class, count)
			if Shown(key) then
				if count.ammo then
					local ammo = AmmoItem()
					if ammo then
						items[#items + 1] = { kind = "count", key = key, ammo = true, item = ammo, icon = ItemIcon(ammo) or E:ClientIcon(AMMO_ICON) }
					end
				elseif (count.spells and AnyKnown(count.spells)) or (not count.spells and ItemCount(count.items) > 0) then
					items[#items + 1] = { kind = "count", key = key, items = count.items, item = count.items[1], icon = ItemIcon(count.items[1]) }
				end
			end
		end
	end
	return items
end

---------------------------------------------------------------------------
-- Tooltips and picks
---------------------------------------------------------------------------
local function HasPick(entry)
	if entry and entry.kind == "spell" then return true end
	local R = Reminders()
	if not (entry and R) then return false end
	if entry.kind == "poison" then return true end
	return entry.kind == "upkeep" and R.HasChoice and R.HasChoice(entry.slot) or false
end

local function ShowTip(button)
	local entry = button.entry
	if not entry then return end
	local tip = GameTooltip
	tip:SetOwner(button, "ANCHOR_TOP")
	if entry.kind == "count" or (entry.kind == "poison" and entry.item) then
		if entry.item and tip.SetItemByID then tip:SetItemByID(entry.item) end
	elseif entry.spell and tip.SetSpellByID then
		tip:SetSpellByID(entry.spell)
	end
	if entry.kind == "spell" then
		local rank, highest = RankNumber(entry.spell), RankNumber((KnownSpell(entry.base)))
		if rank and highest then E.UIKit.TipText(tip, L["Rank %d of %d"]:format(rank, highest)) end
	end
	if entry.kind == "count" then
		E.UIKit.TipText(tip, L["%d in your bags"]:format(entry.ammo and ItemCount({ entry.item }) or ItemCount(entry.items)))
	elseif entry.kind == "poison" then
		E.UIKit.TipText(tip, entry.hand == "off" and L["Off-hand poison"] or L["Main-hand poison"])
		if not entry.line then E.UIKit.TipText(tip, L["Right-click to pick the poison this hand gets."]) end
	end
	if entry.kind ~= "count" and not InCombatLockdown() then
		local click = (entry.kind ~= "poison" or entry.item) and { L["Click"], entry.kind == "poison" and L["use it"] or L["cast it"] } or nil
		local pick = HasPick(entry) and { L["Right-click"], entry.kind == "poison" and L["pick the poison"] or L["pick the spell and rank"] } or nil
		if click and pick then
			E:TooltipHint(tip, click, pick)
		elseif click or pick then
			E:TooltipHint(tip, click or pick)
		end
	elseif HasPick(entry) and InCombatLockdown() then
		E.UIKit.TipText(tip, L["Picks change out of combat."])
	end
	tip:Show()
end

function M:OpenCooldownMenu(owner, key)
	if InCombatLockdown() or not (owner and E.UIKit and E.UIKit.ContextMenu) then return end
	local spell = CooldownSpell(key)
	if not (spell and KnownSpell(spell.id)) then return end
	local ranks = self:CooldownRanks(key)
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(L["Spell and rank"])
		root:CreateRadio(L["Highest rank (follows new ranks)"], function()
			local _, _, picked = ChosenSpell(spell, key)
			return not picked
		end, function() M:SetCooldownRank(key, nil) end)
		for index = #ranks, 1, -1 do
			local rank = ranks[index]
			root:CreateRadio(L["Rank %d"]:format(rank.rank), function()
				local id, _, picked = ChosenSpell(spell, key)
				return picked and id == rank.id
			end, function() M:SetCooldownRank(key, rank.id) end)
		end
	end)
end

-- Right-click: cooldown ranks, or the reminder's spell and poison menus.
local function PickClick(button, mouse, down)
	if mouse ~= "RightButton" or down or InCombatLockdown() then return end
	local entry = button.entry
	if entry and entry.kind == "spell" then return M:OpenCooldownMenu(button, entry.key) end
	local R = Reminders()
	if not (entry and R and HasPick(entry)) then return end
	if entry.kind == "poison" then
		R:OpenPoisonMenu(button, entry.hand)
	else
		R:OpenBuffMenu(button, entry.key)
	end
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function NewButton(parent, name)
	local button = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
	E:SetTemplate(button)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	button.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(button.icon)
	button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.cooldown:SetAllPoints(button.icon)
	if button.cooldown.SetDrawEdge then button.cooldown:SetDrawEdge(false) end
	button.count = E:CreateText(button, E.tokens.size.small, "RIGHT")
	button.count:SetPoint("BOTTOMRIGHT", -2, 2)
	E:SkinHudButton(button, button.icon)
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:HookScript("PostClick", PickClick)
	button:HookScript("OnEnter", ShowTip)
	button:HookScript("OnLeave", GameTooltip_Hide)
	E:BindOptionsLink(button, { page = "module:ClassBar" })
	button:Hide()
	return button
end

function M:Build()
	if self.frame then return end
	local holder = CreateFrame("Frame", "EldoUI_ClassBarHolder", UIParent, "SecureHandlerStateTemplate")
	holder:SetAllPoints(UIParent)
	holder:SetFrameStrata("LOW")
	self.holder = holder
	local frame = CreateFrame("Frame", "EldoUI_ClassBar", holder)
	frame:SetSize(220, 30)
	frame:SetFrameStrata("LOW")
	self.frame = frame
	self.buttons = {}
	for index = 1, MAX_ICONS do
		self.buttons[index] = NewButton(frame, "EldoUI_ClassBarButton" .. index)
	end
	E:CreateMover(frame, "EldoUI_ClassBar", L["Class Bar"], DEFAULT_POINT,
		{ layoutAlias = "EldoUI_Totems", combat = true, sample = { kind = "icons", count = 6 } })
end

-- The live buff of an upkeep icon: an aura slot of the game's aura
-- container over the faded icon. It passes clicks through to the icon.
local function UpkeepSlot(button, ids, size)
	local W = E.AuraWidget
	if not (W and W.SlotsAvailable and W.SlotsAvailable()) or #ids == 0 then return nil end
	local include = {}
	for _, id in ipairs(ids) do include[id] = true end
	local settings = { size = size, duration = "SWIPE", durationSize = math.max(math.floor(size * 0.38), 9),
		countSize = math.max(math.floor(size * 0.42), 10), tooltip = false }
	local sorted = { unpack(ids) }
	table.sort(sorted)
	return W.CreateSlots(button, { unit = "player", poolKey = ("classbar:%s:%s:%s"):format(tostring(button:GetName()), size,
		table.concat(sorted, ",")), slots = { {
		key = "upkeep", filter = "HELPFUL|PLAYER", candidateFilters = { includeSpellIDs = include },
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

local function ReleaseSlot(button)
	if button.slot then
		E.AuraWidget.Release(button.slot)
		button.slot, button.slotKey = nil, nil
	end
end

-- The secure click of an icon.
local function Action(entry)
	if entry.kind == "upkeep" then return "spell", entry.spell end
	if entry.kind == "spell" then return "spell", entry.picked and entry.spell or entry.name or entry.spell end
	if entry.kind == "poison" and entry.item then
		return "macro", nil, ("/use item:%d\n/use %d"):format(entry.item, entry.hand == "off" and OFF or MAIN)
	end
end

---------------------------------------------------------------------------
-- Layout and secure attributes (out of combat)
---------------------------------------------------------------------------
function M:Apply()
	if not self:Drawing() then
		self:Hide()
		return
	end
	self:Build()
	local db = self.db
	local size, spacing = db.size, db.spacing
	local perRow = math.max(1, math.floor(tonumber(db.perRow) or MAX_ICONS))
	local items = self:Items()
	self.items = items
	local shown = math.min(#items, MAX_ICONS)
	local r, g, b = unpack(E.media.accentColor)
	local theme = E.AuraWidget and E.AuraWidget.ThemeKey and E.AuraWidget.ThemeKey() or ""
	for index, button in ipairs(self.buttons) do
		local entry = items[index]
		button.entry = entry
		E:SetTemplate(button)
		E:SetFont(button.count, E.tokens.size.small)
		if entry then
			button:SetSize(size, size)
			button:ClearAllPoints()
			-- Rows of perRow icons (columns when vertical).
			local along = ((index - 1) % perRow) * (size + spacing)
			local across = math.floor((index - 1) / perRow) * (size + spacing)
			if db.vertical then
				button:SetPoint("TOPLEFT", self.frame, "TOPLEFT", across, -along)
			else
				button:SetPoint("TOPLEFT", self.frame, "TOPLEFT", along, -across)
			end
			button.icon:SetTexture(entry.icon)
			button.icon:SetDesaturated(false)
			button.icon:SetAlpha(1)
			local kind, spell, macro = Action(entry)
			button:SetAttribute("type1", kind)
			button:SetAttribute("spell", spell)
			button:SetAttribute("macrotext1", macro)
			button:SetAttribute("unit", kind == "spell" and entry.kind == "upkeep" and "player" or nil)
			local signature = entry.kind == "upkeep" and (table.concat(entry.ids, ",") .. ":" .. size .. ":" .. theme) or nil
			if signature ~= button.slotKey then
				ReleaseSlot(button)
				button.slot = signature and UpkeepSlot(button, entry.ids, size) or nil
				button.slotKey = signature
			end
			button:Show()
		else
			ReleaseSlot(button)
			button:SetAttribute("type1", nil)
			button:SetAttribute("spell", nil)
			button:SetAttribute("macrotext1", nil)
			button:SetAttribute("unit", nil)
			button:Hide()
		end
	end
	local count = math.max(1, math.min(shown, perRow))
	local lines = math.max(1, math.ceil(shown / perRow))
	local length = count * size + (count - 1) * spacing
	local depth = lines * size + (lines - 1) * spacing
	if db.vertical then self.frame:SetSize(depth, length) else self.frame:SetSize(length, depth) end
	self.frame:SetShown(shown > 0)
	self:ApplyVisibility()
	local mover = E.movers.EldoUI_ClassBar
	if mover then mover:Show() end
	self:PlaceTimers()
end

-- The bar takes the totem timers' spot, as Shaman Totems' bar does:
-- Player Power places the timers beside it again whenever the bar comes or
-- goes.
function M:PlaceTimers()
	local shown = self.active and self.frame and self:Drawing() and true or false
	if shown == self.timersHost then return end
	self.timersHost = shown
	local power = E.modules.ClassPower
	if power and power.active and power.ApplyBlizzard then
		local ok, err = pcall(power.ApplyBlizzard, power)
		if not ok then geterrorhandler()(err) end
	end
end

function M:ApplyVisibility()
	if not self.holder then return end
	if self.visibilityBlock ~= self.db.visibility then E:DetachVisibility(self.holder) end
	if E:IsVisibilityAttached(self.holder) then
		E:UpdateVisibility(self.holder)
	else
		self.visibilityBlock = self.db.visibility
		E:AttachVisibility(self.holder, self.db.visibility, {
			watch = self.frame,
			secure = true,
			forceShow = function() return E.IsMoveMode and E:IsMoveMode() end,
		})
	end
end

function M:Hide()
	if self.buttons then
		for _, button in ipairs(self.buttons) do
			if button.glowing then
				button.glowing = false
				E:HideGlow(button)
			end
		end
	end
	if not self.frame then
		local mover = E.movers.EldoUI_ClassBar
		if mover then mover:Hide() end
		return
	end
	E:DetachVisibility(self.holder)
	self.visibilityBlock = nil
	E:RunOutOfCombat(function()
		for _, button in ipairs(M.buttons) do ReleaseSlot(button) end
		M.frame:Hide()
		local mover = E.movers.EldoUI_ClassBar
		if mover then mover:Hide() end
		M:PlaceTimers()
	end, "ClassBar:hide")
end

---------------------------------------------------------------------------
-- Display (in combat too)
---------------------------------------------------------------------------
-- { has, secondsLeft } of a hand's temporary enchant; nil when the game
-- doesn't say.
local function Enchant(hand)
	if not (C_Item and C_Item.GetWeaponEnchantInfo) then return nil end
	local weaponSlot = Enum.WeaponSlot and (hand == "off" and Enum.WeaponSlot.OffHand or Enum.WeaponSlot.MainHand)
	local list = Try(C_Item.GetWeaponEnchantInfo, weaponSlot or (hand == "off" and OFF or MAIN))
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
M.Enchant = Enchant

-- Is one of the buff's ranks on you? Out of combat only (nil otherwise).
local function BuffUp(ids)
	if InCombatLockdown() then return nil end
	local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
	if not get then return nil end
	for _, id in ipairs(ids) do
		local ok, aura = pcall(get, id)
		if not ok or Secret(aura) then return nil end
		if aura then return true end
	end
	return false
end
M.BuffUp = BuffUp

local function SetGlow(button, on)
	on = on and M.db.missingGlow and true or false
	if on == (button.glowing or false) then return end
	button.glowing = on
	if on then E:ShowUserGlow(button, "classBarMissing") else E:HideGlow(button) end
end

local Source = E.CombatKit and E.CombatKit.Cooldowns

function M:Update()
	if not (self.frame and self.items and self:Drawing()) then return end
	for index, entry in ipairs(self.items) do
		local button = self.buttons[index]
		if not button then break end
		if entry.kind == "upkeep" then
			-- The live buff draws itself over this faded icon.
			button.icon:SetDesaturated(button.slot ~= nil)
			button.icon:SetAlpha(button.slot and 0.45 or 1)
			button.count:SetText("")
			local up = BuffUp(entry.ids)
			if up ~= nil then SetGlow(button, not up) elseif not InCombatLockdown() then SetGlow(button, false) end
		elseif entry.kind == "poison" then
			local has, left = Enchant(entry.hand)
			if has ~= nil then
				button.icon:SetDesaturated(not has)
				button.icon:SetAlpha(has and 1 or 0.45)
				SetGlow(button, not has)
				button.count:SetText(has and left and (left < 60 and ("%d"):format(left) or ("%dm"):format(math.ceil(left / 60))) or "")
			end
		elseif entry.kind == "spell" then
			if not (Source and Source.DrawSpell(button.cooldown, entry.spell)) then button.cooldown:Clear() end
			button.count:SetText("")
		else
			local count = entry.ammo and ItemCount({ entry.item }) or ItemCount(entry.items)
			button.count:SetText(tostring(count))
			button.icon:SetDesaturated(count == 0)
			button.icon:SetAlpha(count == 0 and 0.45 or 1)
		end
	end
end

-- Layout and secure attributes out of combat; the display at once.
function M:Refresh()
	E:RunOutOfCombat(function() M:Apply() end, "ClassBar:refresh")
	self:Update()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
local EVENTS = {
	"SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
	"PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "UNIT_AURA", "UNIT_INVENTORY_CHANGED",
}
-- The list of icons may change: a spell learned, a weapon or ammo swapped,
-- reagents bought or used up.
local RELIST = { SPELLS_CHANGED = true, LEARNED_SPELL_IN_SKILL_LINE = true, PLAYER_LEVEL_UP = true, PLAYER_ENTERING_WORLD = true,
	PLAYER_REGEN_ENABLED = true, PLAYER_EQUIPMENT_CHANGED = true, BAG_UPDATE_DELAYED = true, UNIT_INVENTORY_CHANGED = true }
events:SetScript("OnEvent", function(_, event)
	if not M.active then return end
	if RELIST[event] then
		E:Debounce("ClassBar:relist", 0, function() if M.active then M:Refresh() end end)
	else
		M:Update()
	end
end)

-- A slow tick for the poison times, only while a poison icon shows.
local TICK = "ClassBar:tick"
function M:UpdateTicker()
	local ticker = E.Ticker
	if not ticker then return end
	local poison = false
	for _, entry in ipairs(self.active and self:Drawing() and self.items or {}) do
		if entry.kind == "poison" then poison = true end
	end
	if poison then
		if not ticker:IsSubscribed(TICK) then ticker:Subscribe(TICK, 1, function() M:Update() end, M) end
	else
		ticker:Unsubscribe(TICK)
	end
end

local COOLDOWNS = "ClassBar"
local function OnCooldowns()
	if M.active then M:Update() end
end

function M:OnEnable()
	for _, event in ipairs(EVENTS) do
		if event == "UNIT_AURA" or event == "UNIT_INVENTORY_CHANGED" then
			pcall(events.RegisterUnitEvent, events, event, "player")
		else
			pcall(events.RegisterEvent, events, event)
		end
	end
	if Source then Source.Subscribe(COOLDOWNS, OnCooldowns) end
	E:RunOutOfCombat(function()
		M:Apply()
		M:Update()
		M:UpdateTicker()
	end, "ClassBar:refresh")
end

function M:OnDisable()
	events:UnregisterAllEvents()
	if Source then Source.Unsubscribe(COOLDOWNS) end
	if E.Ticker then E.Ticker:UnsubscribeOwner(M) end
	self:Hide()
end

function M:OnProfileChanged()
	if not self.active then return end
	self:Refresh()
end

-- Every Apply ends with the ticker following the icons.
local apply = M.Apply
function M:Apply()
	apply(self)
	self:UpdateTicker()
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local function NotDrawn()
	local class = PlayerClass()
	return class ~= "SHAMAN" and D[class] ~= nil
end

M.options = {
	{ type = "description", label = "Shamans have the cooldown bar of Shaman Totems instead, so this bar stays hidden.", tone = "warning", hidden = NotDrawn },
	{ type = "description", label = "One bar with the buffs you keep up, your key cooldowns and the reagents you spend. Each icon shows once you know its spell." },
	{ type = "header", label = "Bar" },
	{ type = "range", unit = "px", key = "size", label = "Icon size", min = 20, max = 48, step = 1, desc = "Width and height of each buff, cooldown and reagent icon." },
	{ type = "range", unit = "px", key = "spacing", label = "Spacing", min = 0, max = 12, step = 1, desc = "Space between icons." },
	{ type = "toggle", key = "vertical", label = "Vertical", desc = "Stack the icons top to bottom." },
	{ type = "range", key = "perRow", label = "Icons per row", min = 4, max = 24, step = 1,
		desc = "More icons than this start a new row (a new column when vertical), so a full bar keeps clear of the player and target frames." },
	{ type = "toggle", key = "missingGlow", label = "Glow while missing", desc = "A soft glow on a buff or poison icon while it is missing (out of combat; the game hides auras from addons in combat)." },
	{ type = "execute", label = "Move", desc = "Unlock EldoUI frames to drag the class bar (mover \"Class Bar\").", func = function() E:MoveFrame("EldoUI_ClassBar") end },
	{ type = "header", label = "What it shows" },
	{ type = "toggle", key = "upkeep", label = "Buffs you keep up", desc = "Your class buffs, auras, armors, aspects or poisons: live with their time, faded while missing. Right-click one to pick the spell and rank; the reminders keep the same pick." },
	{ type = "toggle", key = "cooldowns", label = "Key cooldowns", desc = "Your class's key cooldowns, with the game's cooldown swipe. A click casts the highest rank you know unless you pick a rank with right-click. Each character keeps its own picks." },
	{ type = "toggle", key = "counts", label = "Reagents and ammo", desc = "How many of the reagents your class spends you carry, and a hunter's ammo." },
}

-- One switch per icon of your class, under its group.
local function ClassRows(class, data)
	local function Other() return PlayerClass() ~= class end
	local R = Reminders()
	for _, key in ipairs(data.upkeep or {}) do
		local slot = R and R.SlotByKey and R.SlotByKey(key)
		if slot then
			M.options[#M.options + 1] = {
				type = "toggle", key = "show." .. key, label = R.SlotTitle and R.SlotTitle(slot) or key,
				gameName = function() return R.SlotSpellName and R.SlotSpellName(slot) end,
				desc = E.Key("Show this buff on the bar."), dependsOn = "upkeep", hidden = Other,
			}
		end
	end
	for _, spell in ipairs(data.spells or {}) do
		M.options[#M.options + 1] = {
			type = "toggle", key = "show." .. SpellKey(class, spell), label = spell.name,
			gameName = function() return SpellName(spell.id) end,
			desc = E.Key("Show this cooldown on the bar once you know it."), dependsOn = "cooldowns",
			hidden = function() return Other() or not SpellFits(spell) end,
		}
	end
	for _, count in ipairs(data.counts or {}) do
		M.options[#M.options + 1] = {
			type = "toggle", key = "show." .. SpellKey(class, count),
			label = count.ammo and E.Key("Ammo") or count.name,
			gameName = not count.ammo and #count.items == 1 and function()
				local id = count.items[1]
				return id and C_Item and C_Item.GetItemNameByID and Plain(Try(C_Item.GetItemNameByID, id)) or nil
			end or nil,
			desc = count.ammo and E.Key("The ammo in your ammo slot, with how many you carry.") or E.Key("How many of this reagent you carry."),
			dependsOn = "counts", hidden = Other,
		}
	end
end
local classes = {}
for class in pairs(D) do classes[#classes + 1] = class end
table.sort(classes)
for _, class in ipairs(classes) do ClassRows(class, D[class]) end

for _, row in ipairs(E:VisibilityOptions("visibility", { db = function() return M.db end })) do
	M.options[#M.options + 1] = row
end

---------------------------------------------------------------------------
-- Style presets: size, spacing and direction. None moves the bar or
-- changes which icons it shows.
---------------------------------------------------------------------------
E:RegisterStyles("ClassBar", {
	{ key = "Standard", title = L["Standard"], desc = L["30 px icons in a row, glow while a buff is missing."],
		settings = { size = 30, spacing = 4, vertical = false, missingGlow = true, visibility = E:VisibilityDefaults() } },
	{ key = "Compact", title = L["Compact"], desc = L["Small 24 px icons, close together."],
		settings = { size = 24, spacing = 2, vertical = false, missingGlow = true, visibility = E:VisibilityDefaults() } },
	{ key = "Large", title = L["Large"], desc = L["Big 38 px icons, easy to hit."],
		settings = { size = 38, spacing = 6, vertical = false, missingGlow = true, visibility = E:VisibilityDefaults() } },
	{ key = "Vertical", title = L["Vertical"], desc = L["30 px icons stacked top to bottom."],
		settings = { size = 30, spacing = 4, vertical = true, missingGlow = true, visibility = E:VisibilityDefaults() } },
	{ key = "Quiet", title = L["Quiet"], desc = L["28 px icons without the glow, faded until the mouse is on the bar."],
		settings = { size = 28, spacing = 4, vertical = false, missingGlow = false, visibility = E:VisibilityDefaults({ show = "mouseover" }) } },
})
