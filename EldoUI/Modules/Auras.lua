-- EldoUI Buffs and Debuffs: the player's own buff and debuff rows, with
-- right-click to cancel a buff, weapon enchant icons and slots for private
-- (boss mechanic) auras. It also owns Blizzard's buff and debuff frames
-- through the "buffs-debuffs" element switch (skin, move, hide, replace,
-- improve).
--
-- How: WoW: Forever does not load Blizzard's secure aura header and does
-- not let addon code read auras in combat. The rows are the game's own aura
-- containers (Core/AuraWidget.lua): the client filters, sorts, lays out,
-- shows tooltips and cancels a buff on right-click; EldoUI only dresses
-- each icon. Weapon enchants use the same container, one button per weapon
-- slot, so the game also shows their time and charges and removes one on
-- right-click inside its own code: removing a buff or an enchant is
-- something only the game's own code may do. Should the container offer
-- no enchant slots, plain icons fed from C_Item.GetWeaponEnchantInfo show
-- instead, for display only.
--
-- Which auras show comes from the shared filters (Core/Filters.lua,
-- presets or custom groups with spell lists), optionally your own first;
-- auras about to run out can blink, the time can take the shared cooldown
-- colors, a thin time bar can run under each icon, and the rows can be
-- timer bars instead of icons. The client does all timing: blink and colors
-- are curves it evaluates, so Lua never reads an aura's time.
local _, E = ...
local L = E.L

local Key = E.Key
local Blizz = E.UFBlizzard
local Widget = E.AuraWidget
local issecret = issecretvalue or function() return false end

local MAX_BUFFS = 40
local MAX_DEBUFFS = 16

-- Move mode's test frames: the client draws the auras inside its own
-- container, so the stand-in steps aside while you have one of the kind.
local function HasAura(filter)
	local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if not get then return true end
	return get("player", 1, filter) ~= nil
end

-- Settings both rows share.
local function RowDefaults(kind, extra)
	local row = {
		enabled = true,
		filter = E:AuraFilterDefaults(kind, "all"),
		style = "ICONS",      -- "ICONS" or "BARS" (timer bars with the spell name)
		size = 32,
		spacing = 4,
		perRow = 12,
		rows = 3,
		growth = "LEFT",      -- "LEFT" or "RIGHT"
		wrap = "DOWN",        -- "DOWN" or "UP"
		sort = "TIME",        -- "TIME", "NAME" or "INDEX"
		sortReverse = false,
		ownFirst = false,     -- your own auras first
		desaturateOthers = false,
		duration = "TEXT",    -- "TEXT", "SWIPE", "BOTH" or "NONE"
		durationSize = 11,
		durationPoint = "BELOW", durationX = 0, durationY = 0,
		countSize = 12,
		countPoint = "BOTTOMRIGHT", countX = -1, countY = 2,
		timeColors = false,   -- time text in the shared cooldown colors
		blink = 0,            -- seconds before running out the time blinks (0 = off)
		timeBar = 0,          -- height of a time bar under each icon (0 = off)
		barWidth = 200, barHeight = 20, barCount = 10,
	}
	for key, value in pairs(extra or {}) do row[key] = value end
	return row
end

local M = E:NewModule("Auras", {
	title = "Buffs and Debuffs",
	desc = "Your buffs (right-click to cancel), debuffs, weapon enchants and boss mechanic auras, plus Blizzard's buff frames.",
	conflicts = { "ElvUI", "BuffTimers", "ElkBuffBars" },
	frames = { "EldoUI_BuffsHolder", "EldoUI_DebuffsHolder", "EldoUI_TempEnchantsHolder" },
	movers = { "EldoUI_Buffs", "EldoUI_Debuffs", "EldoUI_TempEnchants" },
	blizzard = { "buffs-debuffs" },
	savedKeys = { "profile.modules.Auras" },
	optionsPage = "module:Auras",
	presets = { "Bars", "Compact", "GrowRight", "Large", "Minimal", "Standard", "Swipe" },
	defaults = {
		buffs = RowDefaults("HELPFUL", {
			cancel = true,        -- right-click cancels the buff
		}),
		debuffs = RowDefaults("HARMFUL", {
			size = 40,
			perRow = 8,
			rows = 2,
			durationSize = 12,
			countSize = 13,
			dispelBorder = true,
			barColor = "DISPEL",  -- timer bars by debuff type, or "ACCENT"
			barCount = 8,
		}),
		enchants = {
			enabled = true,
			size = 32,
			spacing = 4,
			growth = "LEFT",
			cancel = true,        -- right-click removes the enchant
			duration = "TEXT",
			durationSize = 11,    -- time text under the icon
			countSize = 12,       -- charges on the icon
		},
		privateAuras = {
			enabled = false,      -- Blizzard's buff frame or EldoUI's player frame usually shows them
			count = 2,
			size = 40,
			anchor = "LEFT",
		},
		blizzard = {
			scale = 1,
			durations = true,     -- improve: show the time left under Blizzard's buffs
		},
	},
})

---------------------------------------------------------------------------
-- Buff and debuff rows (game aura containers)
---------------------------------------------------------------------------
local function RowSettings(db, kind, max, extra)
	local bars = db.style == "BARS"
	local count = bars and math.min(db.barCount or 10, max) or math.min(db.perRow * db.rows, max)
	-- Filter groups; presets follow the row's own sort, custom groups
	-- keep theirs. "Yours first" splits each group in two.
	local groups = E:AuraFilterGroups(db.filter, kind, count)
	if type(db.filter) ~= "table" or db.filter.preset ~= "custom" then
		for _, group in ipairs(groups) do group.sortMethod, group.sortDirection = nil, nil end
	end
	groups = Widget.SplitOwn(groups, db.ownFirst, db.desaturateOthers)
	local settings = {
		unit = "player",
		groups = groups,
		max = count,
		perRow = bars and 1 or db.perRow,
		size = db.size,
		spacing = db.spacing,
		growth = db.growth,
		wrap = db.wrap,
		sort = db.sort,
		reverse = db.sortReverse,
		duration = db.duration,
		durationSize = db.durationSize,
		durationPoint = db.durationPoint, durationX = db.durationX, durationY = db.durationY,
		countSize = db.countSize,
		countPoint = db.countPoint, countX = db.countX, countY = db.countY,
		timeColors = db.timeColors and true or false,
		blink = (db.blink or 0) > 0 and db.blink or nil,
		timeBar = (db.timeBar or 0) > 0 and db.timeBar or nil,
		tooltipAnchor = "ANCHOR_BOTTOMLEFT",
	}
	if bars then
		settings.bar = { width = db.barWidth or 200, height = db.barHeight or 20,
			dispelColor = (kind == "HARMFUL" and db.barColor ~= "ACCENT") or nil }
	end
	for key, value in pairs(extra) do settings[key] = value end
	return settings
end

local function HolderSize(settings)
	if settings.bar then
		return settings.bar.width, math.max(settings.max * (settings.bar.height + settings.spacing) - settings.spacing, 1)
	end
	local columns = math.max(math.min(settings.max, settings.perRow), 1)
	local rows = math.max(math.ceil(settings.max / math.max(settings.perRow, 1)), 1)
	local room = Widget.TextRoom(settings)
	return columns * settings.size + (columns - 1) * settings.spacing,
		rows * settings.size + (rows - 1) * (settings.spacing + room) + room
end

-- (Re)build one row when its settings changed. Out of combat only.
local function BuildRow(self, key, holder, settings, enabled)
	local row = self.rows[key]
	holder:SetSize(HolderSize(settings))
	holder:SetShown(enabled)
	local signature = enabled and Widget.Signature(settings) or nil
	if row.signature == signature then return end
	Widget.Release(row.container)
	row.container, row.signature = nil, nil
	if not enabled then return end
	row.container = Widget.Create(holder, settings)
	if row.container then
		row.signature = signature
		E:AddMoverContent(key == "buffs" and "EldoUI_Buffs" or "EldoUI_Debuffs", row.container)
	elseif not self.warned then
		self.warned = true
		E:Print(L["Buffs and Debuffs: this client refused the aura display; Blizzard's buff frame stays your aura display."])
	end
end

local privateLayoutLease
local privateLayoutProducer, privateLayoutRelease = Blizz.SetPrivateAnchors, Blizz.RemovePrivateAnchors

local function PrivateLayoutOwned(self)
	local lease = privateLayoutLease
	if not lease or lease.failed or lease.module ~= self or E.modules.Auras ~= self or self.debuffHolder ~= lease.owner
		or E.movers.EldoUI_Debuffs ~= lease.mover or lease.mover.frame ~= lease.owner
		or lease.owner.privateAnchors ~= lease.array then return false end
	for index, entry in pairs(lease.array) do
		if lease.entries[index] ~= entry then return false end
	end
	for index, slot in pairs(lease.proof.slots) do
		local entry, holder = lease.array[index], slot.holder
		if entry ~= lease.entries[index] or entry.holder ~= holder or holder:GetParent() ~= lease.owner then return false end
		local width, height = holder:GetSize()
		local scale, count, shown = holder:GetScale(), holder:GetNumPoints(), holder:IsShown()
		if issecret(width) or issecret(height) or issecret(scale) or issecret(count) or issecret(shown)
			or width ~= slot.width or height ~= slot.height or scale ~= slot.scale or shown ~= slot.shown or count ~= #slot.point / 5 then return false end
		if count == 1 then
			local point = { holder:GetPoint(1) }
			for p = 1, 5 do if issecret(point[p]) or point[p] ~= slot.point[p] then return false end end
		end
	end
	return true
end

function M:PrivateLayoutGeometry()
	local db, lease = self.db.privateAuras, privateLayoutLease
	if not self.active or (not issecret(db.enabled) and not db.enabled) then return end
	if not PrivateLayoutOwned(self) or self.db ~= lease.db or E.db ~= lease.profile or db ~= lease.settings then return nil, "private" end
	if Blizz.SetPrivateAnchors ~= privateLayoutProducer or Blizz.RemovePrivateAnchors ~= privateLayoutRelease then return nil, "private" end
	local proof = lease.proof
	if not proof.geometryComplete or issecret(db.enabled) or issecret(db.size) or issecret(db.count) or issecret(db.anchor)
		or db.enabled ~= proof.enabled or db.size ~= proof.size or db.count ~= proof.count or db.anchor ~= proof.growth then return nil, "private" end
	return proof
end

-- A layout that failed is tried again only while the holder, its slot list
-- and every slot in it are still the ones that layout worked with.
local function PrivateLayoutRetry(self, lease)
	if not lease.retry or lease.module ~= self or E.modules.Auras ~= self or self.debuffHolder ~= lease.owner then return false end
	local array, made = lease.owner.privateAnchors, Blizz.privateSlotOwners
	if issecret(array) or issecret(made) or type(made) ~= "table" then return false end
	if type(array) == "nil" then return true end
	if type(array) ~= "table" or array ~= lease.array then return false end
	for _, entry in pairs(array) do
		if issecret(entry) or type(entry) ~= "table" or issecret(entry.holder) or type(entry.holder) == "nil"
			or made[entry.holder] ~= lease.owner then return false end
	end
	return true
end

function M:LayoutPrivate()
	local lease = privateLayoutLease
	local retry = lease and lease.failed and PrivateLayoutRetry(self, lease)
	if lease and not retry and not PrivateLayoutOwned(self) then return end
	local settings, owner = self.db.privateAuras, self.debuffHolder
	local enabledGeometry = not issecret(settings.enabled) and settings.enabled == true
	if not lease and not enabledGeometry and (not E.MinimapClusterEnabled or not E:MinimapClusterEnabled()) then
		Blizz.SetPrivateAnchors(owner, "player", settings, owner, settings.anchor)
		return
	end
	if Blizz.SetPrivateAnchors ~= privateLayoutProducer or Blizz.RemovePrivateAnchors ~= privateLayoutRelease then return end
	if not lease and owner.privateAnchors and next(owner.privateAnchors) ~= nil then
		privateLayoutLease = { failed = true }
		return
	end
	local db, profile, mover = self.db, E.db, E.movers.EldoUI_Debuffs
	local enabled, size, count, growth = settings.enabled, settings.size, settings.count, settings.anchor
	local before = owner.privateAnchors
	local proof = Blizz.SetPrivateAnchors(owner, "player", settings, owner, growth, true)
	-- Failed: the next layout tries again if this one kept to its own slots.
	local after = owner.privateAnchors
	privateLayoutLease = { failed = true, module = self, owner = owner, array = after,
		retry = (type(before) == "nil" or rawequal(before, after)) or nil }
	if not proof or E.modules.Auras ~= self or self.db ~= db or E.db ~= profile or self.debuffHolder ~= owner
		or Blizz.SetPrivateAnchors ~= privateLayoutProducer or Blizz.RemovePrivateAnchors ~= privateLayoutRelease
		or self.db.privateAuras ~= settings or E.movers.EldoUI_Debuffs ~= mover or not mover or mover.frame ~= owner
		or issecret(settings.enabled) or issecret(settings.size) or issecret(settings.count) or issecret(settings.anchor)
		or settings.enabled ~= enabled or settings.size ~= size or settings.count ~= count or settings.anchor ~= growth then return end
	local entries = {}
	for index in pairs(proof.slots) do entries[index] = owner.privateAnchors[index] end
	privateLayoutLease = { module = self, owner = owner, mover = mover, array = owner.privateAnchors, entries = entries,
		proof = proof, db = db, profile = profile, settings = settings }
	if not PrivateLayoutOwned(self) then privateLayoutLease.failed, privateLayoutLease.retry = true, true end
end

function M:ReleasePrivateLayout()
	if privateLayoutLease then
		if not PrivateLayoutOwned(self) or Blizz.RemovePrivateAnchors ~= privateLayoutRelease then return end
		local removed = Blizz.RemovePrivateAnchors(self.debuffHolder, function(phase, entry)
			if not PrivateLayoutOwned(self) then return false end
			if phase == "hide" then
				for _, slot in pairs(privateLayoutLease.proof.slots) do
					if slot.holder == entry.holder then slot.shown = false;return true end
				end
				return false
			end
			return true
		end)
		if not removed or not PrivateLayoutOwned(self) then privateLayoutLease.failed = true end
		return
	end
	Blizz.RemovePrivateAnchors(self.debuffHolder)
end

function M:LayoutRows()
	local buffs = self.db.buffs
	local debuffs = self.db.debuffs
	BuildRow(self, "buffs", self.buffHolder,
		RowSettings(buffs, "HELPFUL", MAX_BUFFS, { cancel = buffs.cancel, dispelBorder = false }), buffs.enabled)
	BuildRow(self, "debuffs", self.debuffHolder,
		RowSettings(debuffs, "HARMFUL", MAX_DEBUFFS, { cancel = false, dispelBorder = debuffs.dispelBorder }), debuffs.enabled)
	-- Boss mechanic auras sit next to the debuffs (anchored to the holder,
	-- never to the container).
	self:LayoutPrivate()
end

---------------------------------------------------------------------------
-- Weapon enchants (poisons, oils, sharpening stones, shaman weapon imbues)
---------------------------------------------------------------------------
local WEAPON_SLOTS = {}
if Enum and Enum.WeaponSlot then
	for _, value in pairs(Enum.WeaponSlot) do table.insert(WEAPON_SLOTS, value) end
	table.sort(WEAPON_SLOTS)
end
local INVENTORY_SLOT = { [1] = 16, [2] = 17, [3] = 18 }

local function FormatTime(seconds)
	if seconds >= 3600 then return ("%dh"):format(math.ceil(seconds / 3600)) end
	if seconds >= 60 then return ("%dm"):format(math.ceil(seconds / 60)) end
	return ("%d"):format(math.ceil(seconds))
end

-- Plain icons for a client whose aura container has no enchant slots:
-- display only, since removing an enchant is left to the game's own code.
local function CreateEnchantIcon(parent)
	local button = CreateFrame("Button", nil, parent)
	button:RegisterForClicks()
	E:SetTemplate(button)
	button.texture = button:CreateTexture(nil, "ARTWORK")
	button.texture:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	button.texture:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(button.texture)
	button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.cooldown:SetAllPoints(button.texture)
	button.cooldown:SetDrawEdge(false)
	button.cooldown:SetReverse(true)
	button.count = E:CreateText(button, E.tokens.size.label, "RIGHT")
	button.count:SetPoint("BOTTOMRIGHT", -1, 2)
	button.duration = E:CreateText(button, E.tokens.size.small, "CENTER")
	button.duration:SetPoint("TOP", button, "BOTTOM", 0, -2)
	button:Hide()
	return button
end

local function EnchantTooltip(button)
	if not button.slot then return end
	GameTooltip:SetOwner(button, "ANCHOR_BOTTOMLEFT")
	pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", button.slot)
	GameTooltip:Show()
end

local function Readable(value, kind)
	return not issecret(value) and type(value) == kind
end

-- Temporary enchants only: permanent enchants are part of the item.
local function TemporaryEnchants(slot)
	local result = {}
	if not (C_Item and C_Item.GetWeaponEnchantInfo) then return result end
	local ok, list = pcall(C_Item.GetWeaponEnchantInfo, slot)
	if not ok or type(list) ~= "table" then return result end
	local permanent = Enum.ItemEnchantType and Enum.ItemEnchantType.Permanent
	for _, enchant in ipairs(list) do
		local has, kind = enchant.hasEnchant, enchant.enchantType
		if Readable(has, "boolean") and has and not (permanent and Readable(kind, "number") and kind == permanent) then
			result[#result + 1] = enchant
		end
	end
	return result
end

-- The container's enchant slots (main hand, off hand, ranged), or nil
-- when this client's aura container has none.
local function EnchantSlots()
	local slots = _G.AuraContainerItemEnchantmentSlot
	if type(slots) ~= "table" then return nil end
	local list = {}
	for _, value in pairs(slots) do
		if type(value) == "number" then list[#list + 1] = value end
	end
	table.sort(list)
	return list[1] and list or nil
end

-- True when this client's aura container can show weapon enchants.
local canAddEnchants
local function EnchantContainerAvailable()
	if not (EnchantSlots() and Widget.Available()) then return false end
	if canAddEnchants == nil then
		canAddEnchants = false
		local ok, probe = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
		if ok and probe then
			canAddEnchants = type(probe.AddItemEnchantment) == "function"
			Widget.Release(probe)
		end
	end
	return canAddEnchants
end

local function Try(object, method, ...)
	local fn = object[method]
	if type(fn) ~= "function" then return false end
	return (pcall(fn, object, ...))
end

local function EnchantSettings(db)
	local slots = math.max(#(EnchantSlots() or {}), 2)
	return {
		unit = "player",
		size = db.size, spacing = db.spacing, perRow = slots, max = slots,
		growth = db.growth, wrap = "DOWN",
		duration = db.duration, durationSize = db.durationSize or 11,
		countSize = db.countSize or 12,
		cancel = db.cancel and true or false,
		tooltipAnchor = "ANCHOR_BOTTOMLEFT",
	}
end

-- One container button per weapon slot: the client shows it while the
-- slot has a temporary enchant (permanent ones are part of the item),
-- fills in icon, time, charges and tooltip, and on right-click removes
-- the enchant itself.
local function CreateEnchantContainer(holder, settings)
	-- A container released by an earlier layout with the same settings
	-- comes back from the shared pool (the client never frees a frame).
	local key = "enchants:" .. Widget.Signature(settings)
	local reused = Widget.FromPool(key, holder)
	if reused then
		local corner = Widget.Corner(settings)
		reused:ClearAllPoints()
		reused:SetPoint(corner, holder, corner)
		reused:Show()
		Try(reused, "SetUnit", "player")
		return reused
	end
	local ok, container = pcall(CreateFrame, "AuraContainer", nil, holder, "CustomAuraContainerTemplate")
	if not ok or not container then return nil end
	for _, slot in ipairs(EnchantSlots()) do
		local options = { initializeFrame = Widget.SlotIcon(settings), hidePermanent = true }
		if not pcall(container.AddItemEnchantment, container, slot, options) then
			Widget.Release(container)
			return nil
		end
	end
	Try(container, "SetItemEnchantmentLayout", {
		elementWidth = settings.size, elementHeight = settings.size,
		elementSpacing = settings.spacing, lineSpacing = settings.spacing + Widget.TextRoom(settings),
	})
	local flow = AnchorUtil and AnchorUtil.FlowDirection
	Try(container, "SetFlowLayoutPadding", 0, 0, 0, 0)
	if flow then
		Try(container, "SetFlowLayoutGrowthDirection", settings.growth == "LEFT" and flow.Left or flow.Right, flow.Down)
	end
	local corner = Widget.Corner(settings)
	Try(container, "SetFlowLayoutAnchorPoint", corner)
	Try(container, "SetFlowLayoutMaximumLineSize", settings.perRow * (settings.size + settings.spacing))
	container:ClearAllPoints()
	container:SetPoint(corner, holder, corner)
	container:Show()
	Try(container, "SetUnit", "player")
	Widget.PoolAs(container, key)
	return container
end

-- Ctrl-left-click on the enchant icons opens their options. The icons are
-- the game's own aura buttons, which take no hooks, so a plain frame lies
-- over them: it takes no hover (the game's tooltips stay), lets the right
-- click through to the game's button (which removes the enchant) and keeps
-- only the left click. Built out of combat; a client that refuses the
-- pass-through gets no such frame, so the right click is never caught.
local ENCHANT_LINK = { page = "module:Auras", key = "enchants.enabled" }

function M:EnchantLink()
	if self.enchantLink == nil and self.enchantHolder and not InCombatLockdown() then
		local link = CreateFrame("Frame", nil, self.enchantHolder)
		link:SetAllPoints(self.enchantHolder)
		if link.SetPassThroughButtons and pcall(link.SetPassThroughButtons, link, "RightButton") then
			link:SetMouseClickEnabled(true)
			link:SetMouseMotionEnabled(false)
			E:BindOptionsLink(link, ENCHANT_LINK)
			self.enchantLink = link
		else
			link:Hide()
			self.enchantLink = false
		end
	end
	return self.enchantLink or nil
end

-- The link frame lies only over icons the game shows: with no temporary
-- enchant it hides, so an empty corner never catches a click.
function M:UpdateEnchantLink()
	local link = self.enchantLink
	if not link then return end
	local any = false
	if self.enchantContainer then
		for _, slot in ipairs(WEAPON_SLOTS) do
			if #TemporaryEnchants(slot) > 0 then any = true break end
		end
	end
	link:SetShown(any)
end

-- (Re)build the enchant container when its settings changed. Out of
-- combat only. False when the client refused it (plain icons then).
function M:LayoutEnchantContainer(settings, enabled)
	local signature = enabled and Widget.Signature(settings) or nil
	if self.enchantSignature == signature and (signature == nil or self.enchantContainer) then return true end
	Widget.Release(self.enchantContainer)
	self.enchantContainer, self.enchantSignature = nil, nil
	if self.enchantLink then self.enchantLink:Hide() end
	if not enabled then return true end
	self.enchantContainer = CreateEnchantContainer(self.enchantHolder, settings)
	if not self.enchantContainer then return false end
	self.enchantSignature = signature
	E:AddMoverContent("EldoUI_TempEnchants", self.enchantContainer)
	local link = self:EnchantLink()
	if link then
		link:SetFrameLevel(self.enchantContainer:GetFrameLevel() + 10)
		self:UpdateEnchantLink()
	end
	return true
end

function M:UpdateEnchants()
	if not self.enchantHolder or not self.db.enchants.enabled or self.enchantContainer then return end
	local db = self.db.enchants
	local used = 0
	local now = GetTime()
	for _, slot in ipairs(WEAPON_SLOTS) do
		for _, enchant in ipairs(TemporaryEnchants(slot)) do
			if used < #self.enchantButtons then
				used = used + 1
				local button = self.enchantButtons[used]
				button.weaponSlot = slot
				button.enchantType = Readable(enchant.enchantType, "number") and enchant.enchantType or 0
				button.slot = INVENTORY_SLOT[slot]
				button.texture:SetTexture((button.slot and GetInventoryItemTexture("player", button.slot)) or enchant.enchantIconID)
				local charges = enchant.charges
				button.count:SetText((Readable(charges, "number") and charges > 1) and charges or "")
				button.expires = nil
				button.cooldown:Clear()
				local left = enchant.timeLeft
				if Readable(left, "number") and left > 0 then
					local seconds = left / 1000
					if db.duration == "TEXT" or db.duration == "BOTH" then button.expires = now + seconds end
					if db.duration == "SWIPE" or db.duration == "BOTH" then
						-- The game reports only the time left, so the swipe runs over that.
						button.cooldown:SetCooldown(now, seconds)
					end
				end
				if not button.expires then button.duration:SetText("") end
				button:Show()
			end
		end
	end
	for index = used + 1, #self.enchantButtons do
		local button = self.enchantButtons[index]
		button.weaponSlot, button.slot, button.expires = nil, nil, nil
		button:Hide()
	end
end

function M:LayoutEnchants()
	local db = self.db.enchants
	local holder = self.enchantHolder
	if EnchantContainerAvailable() then
		local settings = EnchantSettings(db)
		holder:SetSize(HolderSize(settings))
		holder:SetShown(db.enabled)
		if self:LayoutEnchantContainer(settings, db.enabled) then
			for _, button in ipairs(self.enchantButtons) do
				button.weaponSlot, button.slot, button.expires = nil, nil, nil
				button:Hide()
			end
			return
		end
	end
	-- Plain icons from here on.
	Widget.Release(self.enchantContainer)
	self.enchantContainer, self.enchantSignature = nil, nil
	local slots = math.max(#WEAPON_SLOTS, 2)
	local settings = { size = db.size, spacing = db.spacing, perRow = slots, max = slots, duration = db.duration, durationSize = db.durationSize or E.tokens.size.small }
	holder:SetSize(HolderSize(settings))
	local corner = db.growth == "RIGHT" and "TOPLEFT" or "TOPRIGHT"
	local direction = db.growth == "RIGHT" and 1 or -1
	for index = 1, slots do
		local button = self.enchantButtons[index]
		if not button then
			button = CreateEnchantIcon(holder)
			button:SetScript("OnEnter", EnchantTooltip)
			button:SetScript("OnLeave", GameTooltip_Hide)
			E:BindOptionsLink(button, { page = "module:Auras", key = "enchants.enabled" })
			self.enchantButtons[index] = button
		end
		button:SetSize(db.size, db.size)
		button:ClearAllPoints()
		button:SetPoint(corner, holder, corner, direction * (index - 1) * (db.size + db.spacing), 0)
		button.cooldown:SetDrawSwipe(db.duration == "SWIPE" or db.duration == "BOTH")
		-- Countdown numbers in the one shared look.
		if db.duration == "SWIPE" and E.StyleCooldownText and E.CooldownLook then
			E:StyleCooldownText(button.cooldown, E:CooldownLook(math.max(math.floor(db.size * 0.45), 8)))
		end
		button.cooldown:SetHideCountdownNumbers(db.duration ~= "SWIPE")
		button.duration:SetShown(db.duration == "TEXT" or db.duration == "BOTH")
		E:SetFont(button.count, db.countSize or E.tokens.size.label)
		E:SetFont(button.duration, db.durationSize or E.tokens.size.small)
		button:SetBackdropBorderColor(unpack(E.media.accentColor or E.media.borderColor))
	end
	holder:SetShown(db.enabled)
	self:UpdateEnchants()
end

---------------------------------------------------------------------------
-- Sample auras in a row's size, spacing, time text and look: the options
-- preview and move mode's stand-in draw a row of eight, the stand-in
-- starting where the real first aura sits (E:ConfigSample).
---------------------------------------------------------------------------
local function RowSample(which, count)
	local db = M.db and M.db[which]
	if not db then return nil end
	local kind = which == "buffs" and "HELPFUL" or "HARMFUL"
	local pool = E.ConfigSampleIcons[kind == "HELPFUL" and "buffs" or "debuffs"]
	local vertical = db.wrap == "UP" and "BOTTOM" or "TOP"
	if db.style == "BARS" then
		local rows = {}
		for index = 1, math.min(db.barCount or 3, 3) do rows[index] = { pool[index], ("%ds"):format(40 - index * 12) } end
		return "feed", { width = db.barWidth, rowHeight = db.barHeight, items = rows, align = vertical }
	end
	local edges
	if kind == "HARMFUL" and db.dispelBorder then
		edges = {}
		for index, dispel in ipairs({ "Magic", "Curse", "Poison", "Disease" }) do edges[index] = { E:GetDispelColor(dispel) } end
	end
	return "icons", {
		count = math.min(db.perRow or 8, count), size = db.size, spacing = db.spacing, pool = kind == "HELPFUL" and "buffs" or "debuffs",
		timers = db.duration ~= "NONE", counts = true, fontSize = db.durationSize, edges = edges,
		align = vertical .. (db.growth == "RIGHT" and "LEFT" or "RIGHT"),
	}
end
local function StandIn(which)
	return function() return RowSample(which, 8) end
end

---------------------------------------------------------------------------
-- Build and events
---------------------------------------------------------------------------
function M:Build()
	if self.buffHolder then return end
	self.rows = { buffs = {}, debuffs = {} }
	self.enchantButtons = {}

	self.buffHolder = CreateFrame("Frame", "EldoUI_BuffsHolder", UIParent)
	self.buffHolder:SetSize(400, 80)
	E:CreateMover(self.buffHolder, "EldoUI_Buffs", L["Buffs"], { "TOPRIGHT", "UIParent", "TOPRIGHT", -250, -20 },
		{ enabledPath = { "buffs", "enabled" }, sample = { config = StandIn("buffs"), shows = function() return HasAura("HELPFUL") end } })

	self.debuffHolder = CreateFrame("Frame", "EldoUI_DebuffsHolder", UIParent)
	self.debuffHolder:SetSize(350, 100)
	E:CreateMover(self.debuffHolder, "EldoUI_Debuffs", L["Debuffs"], { "TOPRIGHT", "EldoUI_BuffsMover", "BOTTOMRIGHT", 0, -40 },
		{ enabledPath = { "debuffs", "enabled" }, sample = { config = StandIn("debuffs"), shows = function() return HasAura("HARMFUL") end } })

	self.enchantHolder = CreateFrame("Frame", "EldoUI_TempEnchantsHolder", UIParent)
	self.enchantHolder:SetSize(80, 40)
	E:CreateMover(self.enchantHolder, "EldoUI_TempEnchants", L["Weapon Enchants"], { "TOPRIGHT", "EldoUI_BuffsMover", "TOPLEFT", -12, 0 },
		{ enabledPath = { "enchants", "enabled" }, options = ENCHANT_LINK })
end

-- Weapon enchants count down without an event. While one shows, its time
-- text (every 0.25 s, readable in combat on Forever), the options link and
-- the icons (every 5 s) are kept current on the shared ticker; with no
-- enchant shown nothing runs, and the game's enchant events start it again.
local ENCHANT_TICK = "Auras:enchants"
local ENCHANT_REFRESH = 5
local sinceRefresh = 0

function M:EnchantsShown()
	if not (self.enchantHolder and self.enchantHolder:IsShown()) then return false end
	if self.enchantContainer then
		for _, slot in ipairs(WEAPON_SLOTS) do
			if #TemporaryEnchants(slot) > 0 then return true end
		end
		return false
	end
	for _, button in ipairs(self.enchantButtons or {}) do
		if button:IsShown() then return true end
	end
	return false
end

local function EnchantTick(elapsed)
	sinceRefresh = sinceRefresh + (elapsed or 0)
	if sinceRefresh >= ENCHANT_REFRESH then
		sinceRefresh = 0
		M:UpdateEnchants()
	end
	M:UpdateEnchantLink()
	local now = GetTime()
	for _, button in ipairs(M.enchantButtons) do
		if button.expires and button:IsShown() then
			button.duration:SetText(FormatTime(math.max(button.expires - now, 0)))
		end
	end
	if not (M.active and M:EnchantsShown()) then E.Ticker:Unsubscribe(ENCHANT_TICK) end
end

-- Start the countdown while an enchant shows, end it when none does.
function M:WatchEnchants()
	if self.active and self:EnchantsShown() then
		if not E.Ticker:IsSubscribed(ENCHANT_TICK) then
			sinceRefresh = 0
			E.Ticker:Subscribe(ENCHANT_TICK, 0.25, EnchantTick, self)
		end
	else
		E.Ticker:Unsubscribe(ENCHANT_TICK)
	end
end

function M:Layout()
	self:LayoutRows()
	self:LayoutEnchants()
	if E.RefreshMinimapCluster then E:RefreshMinimapCluster() end
end

local eventFrame = CreateFrame("Frame")

eventFrame:SetScript("OnEvent", function(_, event, unit)
	local self = M
	if not self.active then return end
	if event == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then return end
	self:UpdateEnchants()
	self:UpdateEnchantLink()
	self:WatchEnchants()
end)

local EVENTS = { "UNIT_INVENTORY_CHANGED", "WEAPON_ENCHANT_CHANGED", "PLAYER_ENTERING_WORLD" }

---------------------------------------------------------------------------
-- Blizzard's buff and debuff frames ("buffs-debuffs" element)
---------------------------------------------------------------------------
local ID = "buffs-debuffs"
local skinnedButtons = setmetatable({}, { __mode = "k" })
local hookedFrames = setmetatable({}, { __mode = "k" })

local function SkinAuraButton(button)
	if skinnedButtons[button] or not Blizz.Usable(button) or not button.Icon then return end
	skinnedButtons[button] = true
	E:TrimIcon(button.Icon)
	local backdrop = CreateFrame("Frame", nil, button)
	backdrop:SetPoint("TOPLEFT", button.Icon, "TOPLEFT", -E.pixel, E.pixel)
	backdrop:SetPoint("BOTTOMRIGHT", button.Icon, "BOTTOMRIGHT", E.pixel, -E.pixel)
	backdrop:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
	E:SetTemplate(backdrop)
	if button.Duration then E:SetFont(button.Duration, E.tokens.size.small) end
	if button.Count then E:SetFont(button.Count, E.tokens.size.label) end
end

local function SkinAuraFrame(frame)
	if not E:BlizzardAllowed(ID, "skin") or E:BlizzardHidden(ID) then return end
	for _, button in ipairs(frame.auraFrames or {}) do SkinAuraButton(button) end
end

function M:ApplyBlizzard()
	if not E:BlizzardAllowed(ID) then return end
	local frames = { { BuffFrame, "EldoUI_Buffs", "TOPRIGHT" }, { DebuffFrame, "EldoUI_Debuffs", "TOPRIGHT" } }
	for _, entry in ipairs(frames) do
		local frame = entry[1]
		if Blizz.Usable(frame) then
			if E:BlizzardHidden(ID) then
				Blizz.Hide(ID, frame)
			else
				if E:BlizzardAllowed(ID, "skin") then
					SkinAuraFrame(frame)
					if not hookedFrames[frame] and type(frame.UpdateAuraButtons) == "function" then
						hookedFrames[frame] = true
						hooksecurefunc(frame, "UpdateAuraButtons", SkinAuraFrame)
					end
				end
				if E:BlizzardAllowed(ID, "move") then
					Blizz.Place(ID, frame, entry[2], self.db.blizzard.scale, entry[3])
				end
			end
		end
	end
	if E:BlizzardAllowed(ID, "improve") and self.db.blizzard.durations then
		E:SetCVar("buffDurations", "1", ID)
	else
		-- Turned off (or Improve off): the player's own setting comes back.
		E:RestoreCVar("buffDurations", ID)
	end
end

E:RegisterBlizzardHandler(ID, {
	owner = "Auras",
	apply = function() E:OnBlizzardAddOn("Blizzard_BuffFrame", function() M:ApplyBlizzard() end) end,
	undo = function()
		if BuffFrame then Blizz.Unplace(BuffFrame) end
		if DebuffFrame then Blizz.Unplace(DebuffFrame) end
	end,
	reload = { skin = true, hide = true, replace = true, move = true },
	install = { replace = true, skin = true, move = true, improve = true },
	refreshModule = false,
})

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:OnEnable()
	E:RunOutOfCombat(function()
		self:Build()
		for _, event in ipairs(EVENTS) do
			-- Only the player's own gear: in a raid, everyone's changes woke it.
			if event == "UNIT_INVENTORY_CHANGED" and eventFrame.RegisterUnitEvent then
				pcall(eventFrame.RegisterUnitEvent, eventFrame, event, "player")
			else
				pcall(eventFrame.RegisterEvent, eventFrame, event)
			end
		end
		self:Layout()
		if E:BlizzardAllowed(ID) then
			E:OnBlizzardAddOn("Blizzard_BuffFrame", function() M:ApplyBlizzard() end)
		end
		self:UpdateEnchantLink()
		self:WatchEnchants()
	end)
end

function M:OnDisable()
	eventFrame:UnregisterAllEvents()
	E.Ticker:Unsubscribe(ENCHANT_TICK)
	E:RunOutOfCombat(function()
		for _, holder in ipairs({ self.buffHolder, self.debuffHolder, self.enchantHolder }) do
			if holder then holder:Hide() end
		end
		if self.debuffHolder then self:ReleasePrivateLayout() end
		for _, row in pairs(self.rows or {}) do
			Widget.Release(row.container)
			row.container, row.signature = nil, nil
		end
		Widget.Release(self.enchantContainer)
		self.enchantContainer, self.enchantSignature = nil, nil
		if E.RefreshMinimapCluster then E:RefreshMinimapCluster() end
	end)
end

function M:OnProfileChanged()
	if not self.active then return end
	E:RunOutOfCombat(function()
		self:Layout()
		self:WatchEnchants()
		if E:BlizzardAllowed(ID) then self:ApplyBlizzard() end
	end)
end

-- Spell lists changed (General > Aura filters): rebuild the rows.
E:OnAuraFiltersChanged(M, function()
	if not M.active or not M.rows then return end
	E:RunOutOfCombat(function()
		for _, row in pairs(M.rows) do row.signature = "changed" end
		M:LayoutRows()
	end)
end)

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local GROWTH = { LEFT = "To the left", RIGHT = "To the right" }
local WRAP = { DOWN = "New rows below", UP = "New rows above" }
local DURATION = { TEXT = "Text", SWIPE = "Swipe with numbers", BOTH = "Swipe and text", NONE = "Hidden" }
local POINTS = { TOPLEFT = "Top left", TOP = "Top", TOPRIGHT = "Top right", LEFT = "Left", CENTER = "Center", RIGHT = "Right",
	BOTTOMLEFT = "Bottom left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom right" }
local TIME_POINTS = CopyTable(POINTS)
TIME_POINTS.BELOW = "Under the icon"
TIME_POINTS.ABOVE = "Over the icon"
local function ElementOff() return not E:BlizzardAllowed(ID) end
local function EnchantsOff() return not M.db.enchants.enabled end
local function PrivateOff() return not M.db.privateAuras.enabled end

M.options = {}

-- Whole sentences per row, so translations never glue words together.
local ROW_TEXTS = {
	buffs = {
		enabled = Key("EldoUI buffs"), enabledDesc = Key("Show your buffs in EldoUI's buff frame (mover: Buffs)."),
		size = Key("Size of each buff icon."), perRow = Key("How many buffs fit in one row."),
		rows = Key("Number of rows (up to %d buffs in total)."), growth = Key("Direction new buffs are added in a row."),
		sort = Key("Order of the buffs (the game sorts them, also in combat). Custom filter groups have their own sort."),
		own = Key("Buffs you cast first, then everyone else's (the game tells which are yours)."),
		grey = Key("Show buffs other people cast in gray (puts yours first too)."), which = Key("Which buffs"),
	},
	debuffs = {
		enabled = Key("EldoUI debuffs"), enabledDesc = Key("Show your debuffs in EldoUI's debuff frame (mover: Debuffs)."),
		size = Key("Size of each debuff icon."), perRow = Key("How many debuffs fit in one row."),
		rows = Key("Number of rows (up to %d debuffs in total)."), growth = Key("Direction new debuffs are added in a row."),
		sort = Key("Order of the debuffs (the game sorts them, also in combat). Custom filter groups have their own sort."),
		own = Key("Debuffs you cast first, then everyone else's (the game tells which are yours)."),
		grey = Key("Show debuffs other people cast in gray (puts yours first too)."), which = Key("Which debuffs"),
	},
}

-- One tab per row; both rows have the same settings.
local function RowOptions(which, title, kind, maxIcons)
	local texts = ROW_TEXTS[which]
	local function Add(option)
		option.key = option.key and (which .. "." .. option.key)
		M.options[#M.options + 1] = option
	end
	local function Off() return not M.db[which].enabled end
	local function When(test) return function() return Off() or test(M.db[which]) end end
	local Icons = When(function(db) return db.style == "BARS" end)
	local Bars = When(function(db) return db.style ~= "BARS" end)
	local NoTime = When(function(db) return db.duration == "NONE" end)
	M.options[#M.options + 1] = { type = "tab", label = title }
	-- Preview: one row of sample auras in this row's size, spacing, time
	-- text and look (E:ConfigSample, Core/MoverSamples.lua).
	local function UpdatePreview(canvas)
		local sampleKind, spec = RowSample(which, 8)
		if not (canvas and sampleKind) then return end
		spec.align = nil -- the strip shows it in the middle
		E:ConfigSample(canvas, sampleKind, spec)
	end
	Add({ type = "preview", label = "Preview", height = 76, create = UpdatePreview, update = UpdatePreview,
		desc = "Sample auras in this row's size, spacing and look." })
	Add({ type = "toggle", key = "enabled", label = texts.enabled, desc = texts.enabledDesc })
	if kind == "HELPFUL" then
		Add({ type = "toggle", key = "cancel", label = "Right-click to cancel", desc = "Right-click a buff to remove it, also in combat.", hidden = Off })
	else
		Add({ type = "toggle", key = "dispelBorder", label = "Color border by type",
			desc = "Magic, curse, disease and poison colors on the border, as the game reports them.", hidden = Icons })
	end
	Add({ type = "select", key = "style", label = "Look", values = { ICONS = "Icons", BARS = "Timer bars" },
		desc = "Icons in rows, or one timer bar per aura with its icon, name and time.", hidden = Off })

	Add({ type = "header", label = "Size and layout", hidden = Off })
	Add({ type = "range", key = "size", label = "Icon size", min = 16, max = 72, step = 1, desc = texts.size, hidden = Icons })
	Add({ type = "range", key = "perRow", label = "Icons per row", min = 1, max = maxIcons, step = 1, desc = texts.perRow, hidden = Icons })
	Add({ type = "range", key = "rows", label = "Rows", min = 1, max = kind == "HELPFUL" and 6 or 4, step = 1,
		desc = texts.rows, descFill = maxIcons, hidden = Icons })
	Add({ type = "range", key = "barCount", label = "Bars", min = 1, max = maxIcons, step = 1, desc = "How many timer bars at most.", hidden = Bars })
	Add({ type = "range", key = "barWidth", label = "Bar width", min = 80, max = 400, step = 1, desc = "Width of each timer bar, icon included.", hidden = Bars })
	Add({ type = "range", key = "barHeight", label = "Bar height", min = 10, max = 40, step = 1, desc = "Height of each timer bar.", hidden = Bars })
	if kind == "HARMFUL" then
		Add({ type = "select", key = "barColor", label = "Bar color", values = { DISPEL = "By debuff type", ACCENT = "Theme accent" },
			desc = "Color the bars by magic, curse, disease, poison or bleed (the game picks the color), or use the accent color.", hidden = Bars })
	end
	Add({ type = "range", key = "spacing", label = "Spacing", min = 0, max = 16, step = 1, cog = true, desc = "Gap between icons or bars.", hidden = Off })
	Add({ type = "select", key = "growth", label = "Growth direction", values = GROWTH, desc = texts.growth, hidden = Icons })
	Add({ type = "select", key = "wrap", label = "New rows", values = WRAP, desc = "Where the next row (or bar) goes.", hidden = Off })

	Add({ type = "header", label = "Order", hidden = Off })
	Add({ type = "select", key = "sort", label = "Sort by", values = { TIME = "Time left", NAME = "Name", INDEX = "Order gained" },
		desc = texts.sort, hidden = Off })
	Add({ type = "toggle", key = "sortReverse", label = "Reverse order", cog = true, desc = "Turn the sort order around.", hidden = Off })
	Add({ type = "toggle", key = "ownFirst", label = "Yours first",
		desc = texts.own, hidden = Off })
	Add({ type = "toggle", key = "desaturateOthers", label = "Gray out others'",
		desc = texts.grey, hidden = Off })

	Add({ type = "header", label = "Time left", hidden = Off })
	Add({ type = "select", key = "duration", label = "Show as", values = DURATION,
		desc = "How the time left is shown. The game formats it; EldoUI never reads the time.", hidden = Off })
	Add({ type = "range", key = "durationSize", label = "Time text size", min = 8, max = 20, step = 1, desc = "Font size of the time left.", hidden = NoTime })
	Add({ type = "select", key = "durationPoint", label = "Time position", values = TIME_POINTS, cog = true,
		desc = "Where the time text sits: under or over the icon, or on it.", hidden = When(function(db) return db.style == "BARS" or db.duration == "NONE" end) })
	Add({ type = "range", key = "durationX", label = "Time X offset", min = -30, max = 30, step = 1, cog = true, desc = "Horizontal shift of the time text.",
		hidden = When(function(db) return db.style == "BARS" or db.duration == "NONE" end) })
	Add({ type = "range", key = "durationY", label = "Time Y offset", min = -30, max = 30, step = 1, cog = true, desc = "Vertical shift of the time text.",
		hidden = When(function(db) return db.style == "BARS" or db.duration == "NONE" end) })
	Add({ type = "toggle", key = "timeColors", label = "Color by time left",
		desc = "The time text in the shared cooldown colors (Fonts and text > Cooldown numbers): changes color as the aura runs out. Applies to Text and Swipe and text.",
		hidden = NoTime })
	Add({ type = "range", key = "blink", label = "Blink when expiring", min = 0, max = 30, step = 0.5,
		zeroText = "Never", desc = "Seconds before an aura runs out that its time starts to blink. The game evaluates the blink from the aura's time.", hidden = NoTime })
	Add({ type = "range", key = "timeBar", label = "Time bar under icons", min = 0, max = 8, step = 1,
		zeroText = "Off", desc = "Height of a thin bar under each icon that empties as the aura runs out.", hidden = When(function(db) return db.style == "BARS" or db.duration == "NONE" end) })

	Add({ type = "header", label = "Stacks", hidden = Off })
	Add({ type = "range", key = "countSize", label = "Stack text size", min = 8, max = 20, step = 1, desc = "Font size of the stack count.", hidden = Off })
	Add({ type = "select", key = "countPoint", label = "Stack position", values = POINTS, cog = true, desc = "Where the stack count sits on the icon.", hidden = Icons })
	Add({ type = "range", key = "countX", label = "Stack X offset", min = -30, max = 30, step = 1, cog = true, desc = "Horizontal shift of the stack count.", hidden = Icons })
	Add({ type = "range", key = "countY", label = "Stack Y offset", min = -30, max = 30, step = 1, cog = true, desc = "Vertical shift of the stack count.", hidden = Icons })

	for _, row in ipairs(E:AuraFilterOptions(which .. ".filter", { kind = kind, db = function() return M.db end, label = texts.which })) do
		local hidden = row.hidden
		row.hidden = function()
			if Off() then return true end
			if type(hidden) == "function" then return hidden() end
			return hidden and true or false
		end
		M.options[#M.options + 1] = row
	end
end
RowOptions("buffs", "Buffs", "HELPFUL", MAX_BUFFS)
RowOptions("debuffs", "Debuffs", "HARMFUL", MAX_DEBUFFS)

for _, option in ipairs({
	{ type = "tab", label = "Enchants and boss auras" },
	{ type = "header", label = "Weapon enchants" },
	{ type = "toggle", key = "enchants.enabled", label = "Enable", desc = "Poisons, oils, stones and weapon imbues as icons (mover: Weapon Enchants)." },
	{ type = "toggle", key = "enchants.cancel", label = "Right-click to remove", desc = "Right-click an enchant to remove it, as on Blizzard's buff frame.",
		hidden = function() return EnchantsOff() or not EnchantContainerAvailable() end },
	{ type = "range", key = "enchants.size", label = "Icon size", min = 16, max = 64, step = 1, desc = "Size of the enchant icons.", hidden = EnchantsOff },
	{ type = "range", key = "enchants.spacing", label = "Spacing", min = 0, max = 16, step = 1, desc = "Gap between the icons.", hidden = EnchantsOff },
	{ type = "select", key = "enchants.growth", label = "Growth direction", values = GROWTH, desc = "Direction the icons are added.", hidden = EnchantsOff },
	{ type = "select", key = "enchants.duration", label = "Show as", values = DURATION, desc = "How the time left is shown.", hidden = EnchantsOff },
	{ type = "range", key = "enchants.durationSize", label = "Time text size", min = 8, max = 20, step = 1, desc = "Font size of the time left under each enchant icon.",
		hidden = function() return EnchantsOff() or M.db.enchants.duration == "NONE" or M.db.enchants.duration == "SWIPE" end },
	{ type = "range", key = "enchants.countSize", label = "Charges text size", min = 8, max = 20, step = 1, desc = "Font size of the charges left (poisons, stones) on the icon.", hidden = EnchantsOff },
	{ type = "header", label = "Boss mechanic auras" },
	{ type = "description", label = "Boss mechanics only the game may draw. Turn these on when Blizzard's buff frame and EldoUI's player frame are both off." },
	{ type = "toggle", key = "privateAuras.enabled", label = "Slots next to the debuffs", desc = "Let Blizzard draw private auras next to EldoUI's debuffs." },
	{ type = "range", key = "privateAuras.count", label = "How many", min = 1, max = 4, step = 1, desc = "Number of private aura slots.", hidden = PrivateOff },
	{ type = "range", key = "privateAuras.size", label = "Size", min = 16, max = 72, step = 1, desc = "Icon size of the private auras.", hidden = PrivateOff },
	{ type = "select", key = "privateAuras.anchor", label = "Attach to", values = { LEFT = "Left of the debuffs", RIGHT = "Right of the debuffs", DOWN = "Below the debuffs", UP = "Above the debuffs" },
		desc = "Where the private aura slots sit.", hidden = PrivateOff },

	{ type = "tab", label = "Blizzard" },
	{ type = "description", label = "For Player buffs and debuffs in Blizzard UI. Move puts Blizzard's frames on EldoUI's movers; Improve shows the time left." },
	{ type = "range", percent = true, key = "blizzard.scale", label = "Scale", min = 0.5, max = 2, step = 0.05, desc = "Scale of Blizzard's buff and debuff frames while EldoUI moves them.", hidden = ElementOff },
	{ type = "toggle", key = "blizzard.durations", label = "Time left under Blizzard's buffs", desc = "Improve: turn on the game's buff duration display.", hidden = ElementOff },
}) do M.options[#M.options + 1] = option end

---------------------------------------------------------------------------
-- Style presets (top right, left of the minimap)
---------------------------------------------------------------------------
local function Look(extra)
	local look = { style = "ICONS", ownFirst = false, desaturateOthers = false, timeColors = false, blink = 0, timeBar = 0,
		durationPoint = "BELOW", durationX = 0, durationY = 0 }
	for key, value in pairs(extra) do look[key] = value end
	return look
end

E:RegisterStyles("Auras", {
	{ key = "Standard", title = "Standard", desc = "32 px buffs in rows of 12 with time under them, 40 px debuffs below.",
		settings = { buffs = Look({ size = 32, perRow = 12, rows = 3, spacing = 4, duration = "TEXT", growth = "LEFT", wrap = "DOWN" }),
			debuffs = Look({ size = 40, perRow = 8, rows = 2, duration = "TEXT", growth = "LEFT", wrap = "DOWN" }) } },
	{ key = "Compact", title = "Compact", desc = "Small 26 px icons, 16 per row.",
		settings = { buffs = Look({ size = 26, perRow = 16, rows = 3, spacing = 3, duration = "TEXT", durationSize = 10 }),
			debuffs = Look({ size = 32, perRow = 10, rows = 2, spacing = 3, duration = "TEXT", durationSize = 11 }) } },
	{ key = "Large", title = "Large", desc = "Big 40 px buffs and 52 px debuffs, your own buffs first, colored time that blinks in the last 5 seconds.",
		settings = { buffs = Look({ size = 40, perRow = 10, rows = 3, spacing = 5, duration = "TEXT", durationSize = 13,
				ownFirst = true, timeColors = true, blink = 5 }),
			debuffs = Look({ size = 52, perRow = 6, rows = 2, spacing = 5, duration = "TEXT", durationSize = 14, timeColors = true, blink = 5 }) } },
	{ key = "Bars", title = "Timer bars", desc = "Buffs and debuffs as timer bars with name and time, yours first, debuffs colored by type.",
		settings = { buffs = Look({ style = "BARS", barWidth = 220, barHeight = 20, barCount = 10, spacing = 2, duration = "TEXT", wrap = "DOWN", ownFirst = true, blink = 5 }),
			debuffs = Look({ style = "BARS", barWidth = 220, barHeight = 22, barCount = 6, spacing = 2, duration = "TEXT", wrap = "DOWN", barColor = "DISPEL", blink = 5 }) } },
	{ key = "Swipe", title = "Swipe", desc = "Cooldown swipe with numbers on the icon and a thin time bar under it.",
		settings = { buffs = Look({ size = 32, perRow = 12, rows = 3, spacing = 3, duration = "SWIPE", timeBar = 3 }),
			debuffs = Look({ size = 40, perRow = 8, rows = 2, spacing = 3, duration = "SWIPE", timeBar = 3 }) } },
	{ key = "Minimal", title = "Minimal", desc = "Small icons without time left, sorted by order gained.",
		settings = { buffs = Look({ size = 24, perRow = 20, rows = 2, spacing = 2, duration = "NONE", sort = "INDEX" }),
			debuffs = Look({ size = 30, perRow = 10, rows = 1, spacing = 2, duration = "NONE" }) } },
	{ key = "GrowRight", title = "Grows right", desc = "For buffs on the left side of the screen: rows fill to the right.",
		settings = { buffs = { growth = "RIGHT", wrap = "DOWN" }, debuffs = { growth = "RIGHT", wrap = "DOWN" }, enchants = { growth = "RIGHT" } } },
})
