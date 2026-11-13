-- EldoUI Cooldown Manager: skins and places
-- Blizzard's own Cooldown Manager viewers. Blizzard keeps tracking every
-- cooldown, aura and charge; EldoUI never rebuilds or reads that data. It
-- only changes how the four viewers look and where they sit:
--   Essential   EssentialCooldownViewer   mover EldoUI_Cooldowns
--   Utility     UtilityCooldownViewer     mover EldoUI_CooldownsUtility
--   Buff icons  BuffIconCooldownViewer    mover EldoUI_CooldownsBuffs
--   Buff bars   BuffBarCooldownViewer     mover EldoUI_CooldownsBars
--
-- Element switch "cooldown-viewer" (Core/Blizzard.lua):
--   skin     square icons, 1 px borders, theme fonts, flat bars
--   move     EldoUI movers, attach points and the icon grid (size, spacing,
--            per row, growth)
--   hide     hide the viewers ticked under "Hide this viewer"
--   improve  keybind text on the icons and the visibility rules
--
-- Taint and secret values:
--   * Viewer methods (RefreshLayout, RefreshData, ...) are never called:
--     they work on secret cooldown data, which only Blizzard's untainted
--     code may touch. EldoUI runs after Blizzard's own Layout (hooksecurefunc)
--     and only moves, sizes and skins the item frames.
--   * Item frames come from viewer.itemFramePool, never GetLayoutChildren
--     (that walks IsShown, which can carry a secret in combat).
--   * Keybind text comes from the item's spell id (cooldown settings data,
--     not combat data), C_ActionBar.FindSpellActionButtons and GetBindingKey.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local K = E.CombatKit

local ID = "cooldown-viewer"
local GROUP = "cdm"
local OVERLAY_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"
local BLIZZARD_SWIPE = "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe"

local VIEWERS = {
	{ key = "essential", global = "EssentialCooldownViewer", mover = "EldoUI_Cooldowns", title = "Cooldowns: Essential",
		point = { "CENTER", "UIParent", "CENTER", 0, -229 }, base = 50 },
	{ key = "utility", global = "UtilityCooldownViewer", mover = "EldoUI_CooldownsUtility", title = "Cooldowns: Utility",
		point = { "CENTER", "UIParent", "CENTER", 0, -280 }, base = 30 },
	{ key = "buffIcons", global = "BuffIconCooldownViewer", mover = "EldoUI_CooldownsBuffs", title = "Cooldowns: Buff Icons",
		point = { "CENTER", "UIParent", "CENTER", 0, -120 }, base = 40 },
	{ key = "buffBars", global = "BuffBarCooldownViewer", mover = "EldoUI_CooldownsBars", title = "Cooldowns: Buff Bars",
		point = { "CENTER", "UIParent", "CENTER", -420, -200 }, bars = true },
}
local BY_KEY = {}
for _, def in ipairs(VIEWERS) do BY_KEY[def.key] = def end

local function IconViewer(size, perRow, growth, wrap, extra)
	local settings = {
		enabled = true, hide = true, layout = true,
		size = size, spacing = 4, perRow = perRow, growth = growth, wrap = wrap,
		attach = "mover", attachSide = "BOTTOM", attachGap = 6,
		fade = E:VisibilityDefaults(), -- the shared visibility rules
		-- Key text: all | hidden (only spells on buttons you can't see) | off
		keyText = "hidden", keybindSize = 12, countdownSize = 16, countSize = 13,
	}
	for key, value in pairs(extra or {}) do settings[key] = value end
	return settings
end

local M = E:NewModule("CooldownManager", {
	title = "Cooldown Manager",
	desc = "Skins and places Blizzard's Cooldown Manager, which keeps tracking every cooldown, and adds EldoUI's own rows that you can arrange into groups with their own looks.",
	category = "Combat",
	frames = {},
	movers = { -- and one per cooldown group and free icon the player makes
		"EldoUI_Cooldowns", "EldoUI_CooldownsUtility", "EldoUI_CooldownsBuffs", "EldoUI_CooldownsBars",
		"EldoUI_CooldownsTrinkets", "EldoUI_CooldownsMobility", "EldoUI_CooldownsItems",
	},
	blizzard = { "cooldown-viewer" },
	savedKeys = { "profile.modules.CooldownManager" },
	optionsPage = "module:CooldownManager",
	presets = { "CenteredGroups", "Clean", "Combat", "Compact", "FixedRows", "Large", "LeftGroups" },
	defaults = {
		turnOn = true,
		zoom = 8,
		borders = true,
		squareSwipe = true,
		font = "THEME",
		fontOutline = "OUTLINE",
		keybindPoint = "TOPRIGHT",
		keybindColor = { 1, 1, 1 },
		viewers = {
			essential = IconViewer(46, 8, "CENTER", "DOWN"),
			utility = IconViewer(36, 10, "CENTER", "DOWN", { keybindSize = 10, countdownSize = 13, countSize = 11 }),
			buffIcons = IconViewer(34, 12, "CENTER", "UP", { keyText = "off", countdownSize = 12, countSize = 12 }),
			buffBars = {
				enabled = true, hide = true, layout = true,
				width = 220, height = 20, spacing = 2, growth = "UP",
				attach = "mover", attachSide = "LEFT", attachGap = 6,
				fade = E:VisibilityDefaults(),
				keyText = "off", keybindSize = 10, nameSize = 12, durationSize = 12, countSize = 11,
			},
		},
		bars = {
			texture = "",
			colorMode = "blizzard",
			color = { 0.2, 0.67, 1 },
			spark = true,
			showIcon = true,
		},
	},
})

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local hookedViewers = {}
local laying = {}                                           -- viewer key -> true while EldoUI arranges it
local keybindText = setmetatable({}, { __mode = "k" })      -- item -> FontString
local keybindSpell = setmetatable({}, { __mode = "k" })     -- item -> spell its keybind text was made for
local keybindVersion = setmetatable({}, { __mode = "k" })   -- item -> settings version of that text
local skinnedAt = setmetatable({}, { __mode = "k" })        -- item -> settings version it was skinned with
local itemLists = setmetatable({}, { __mode = "k" })        -- viewer -> reused list of its items
local settingsVersion = 1                                   -- goes up with every apply and profile change
local bindingCache = {}                                     -- spellID -> text or false
local rankCache = {}                                        -- spell name -> its spellbook ranks

local function Viewer(def) return _G[def.global] end
local function VDB(def) return M.db.viewers[def.key] end

local function Allowed(action)
	return M.active and E:BlizzardAllowed(ID, action)
end

-- EldoUI looks after this viewer at all.
local function Handles(def)
	return M.active and E:BlizzardAllowed(ID) and VDB(def).enabled and Viewer(def) ~= nil
end

local function ByLayoutIndex(a, b)
	local ia, ib = a.layoutIndex, b.layoutIndex
	if not (K.Plain(ia, ib) and ia and ib) then return false end
	return ia < ib
end

-- Active item frames of a viewer, in Blizzard's order. The list is the
-- viewer's own reused table: read it before the next call.
local function Items(viewer)
	local pool = viewer and viewer.itemFramePool
	if not pool then return {} end
	local list = itemLists[viewer]
	if list then wipe(list) else
		list = {}
		itemLists[viewer] = list
	end
	for item in pool:EnumerateActive() do
		list[#list + 1] = item
	end
	table.sort(list, ByLayoutIndex)
	return list
end

local function FontFile()
	return K.FontPath(M.db.font)
end

local function Outline()
	local outline = M.db.fontOutline
	if outline == "NONE" then return "" end
	return outline or E.db.general.fontOutline
end

---------------------------------------------------------------------------
-- Keybind text
---------------------------------------------------------------------------
-- Action slot ranges and the binding command that presses them.
local SLOT_BINDINGS = {
	{ 1, 12, "ACTIONBUTTON" },
	{ 25, 36, "MULTIACTIONBAR3BUTTON" },
	{ 37, 48, "MULTIACTIONBAR4BUTTON" },
	{ 49, 60, "MULTIACTIONBAR2BUTTON" },
	{ 61, 72, "MULTIACTIONBAR1BUTTON" },
	{ 73, 120, "ACTIONBUTTON" },   -- stance, form and stealth pages of bar 1
	{ 145, 156, "MULTIACTIONBAR5BUTTON" },
	{ 157, 168, "MULTIACTIONBAR6BUTTON" },
	{ 169, 180, "MULTIACTIONBAR7BUTTON" },
}

local function SlotCommand(slot)
	for _, range in ipairs(SLOT_BINDINGS) do
		if slot >= range[1] and slot <= range[2] then
			return range[3] .. ((slot - range[1]) % 12 + 1)
		end
	end
	-- Page 2 of bar 1 (slots 13-24) only uses ACTIONBUTTON while it is showing.
	-- C_ActionBar first: the old global name exists only while the game
	-- loads its deprecation fallbacks.
	local page = C_ActionBar and C_ActionBar.GetActionBarPage or GetActionBarPage
	if slot >= 13 and slot <= 24 and type(page) == "function" and page() == 2 then
		return "ACTIONBUTTON" .. (slot - 12)
	end
end

local function ShortKey(key)
	key = key:upper()
	key = key:gsub("SHIFT%-", "S"):gsub("CTRL%-", "C"):gsub("ALT%-", "A"):gsub("META%-", "M")
	key = key:gsub("MOUSEWHEELUP", "WU"):gsub("MOUSEWHEELDOWN", "WD"):gsub("BUTTON(%d+)", "M%1")
	key = key:gsub("NUMPAD", "N"):gsub("SPACE", "Sp"):gsub("PAGEUP", "PU"):gsub("PAGEDOWN", "PD")
	return key
end

-- Key text modes: every spell with a key, only spells whose action
-- buttons the player can't see (a bar turned off or shortened, or one
-- that hides in a fight; Action Bars, M:SlotButtonHidden), or none.
local KEY_TEXT = { all = "All", hidden = "Only hidden buttons", off = "Off" }

-- The key text mode of a viewer's (or row's) settings. A profile from
-- before the mode still carries its "Keybinds" tick until its update
-- runs (M.MigrateKeyText): off there reads as off.
local function KeyTextMode(db)
	if type(db) ~= "table" or db.keybinds == false then return "off" end
	local mode = db.keyText
	return KEY_TEXT[mode] and mode or "hidden"
end

-- Is the action button of `slot` out of the player's sight? true, false,
-- or nil for a slot no EldoUI bar shows. With Action Bars off every slot
-- counts as shown (Blizzard's bars show them). While EldoUI's bars step
-- aside for the game's gamepad interface they count as shown too: the
-- controller has no use for a keyboard key.
local function SlotHidden(slot)
	local bars = E.modules and E.modules.ActionBars
	if not (bars and bars.SlotButtonHidden) then return false end
	if bars.HiddenForGamepad and bars.active and bars:HiddenForGamepad() then return false end
	return bars:SlotButtonHidden(slot)
end

-- The action slots that hold a spell and the key each one is bound to
-- (false for none), read once until the bars or bindings change.
local function SpellSlots(spellID)
	local cached = bindingCache[spellID]
	if cached then return cached end
	local list = {}
	local find = C_ActionBar and C_ActionBar.FindSpellActionButtons
	if find then
		local ok, slots = pcall(find, spellID)
		if ok and type(slots) == "table" then
			for _, slot in ipairs(slots) do
				if K.Plain(slot) and type(slot) == "number" then
					local command = SlotCommand(slot)
					local key = command and GetBindingKey(command)
					list[#list + 1] = { slot = slot, key = key and ShortKey(key) or false }
				end
			end
		end
	end
	bindingCache[spellID] = list
	return list
end

-- The key of a spell's action slot. mode "hidden": the key of a slot on
-- a button the player can't see, and nil with true as a second value when
-- the spell also sits on a button they can see (that button shows its own
-- key). Any other mode: the first slot with a key.
local function SpellBinding(spellID, mode)
	if not spellID or not K.Plain(spellID) then return nil end
	local text
	for _, entry in ipairs(SpellSlots(spellID)) do
		if mode == "hidden" then
			local hidden = SlotHidden(entry.slot)
			if hidden == false then return nil, true end
			if hidden and not text then text = entry.key or nil end
		elseif entry.key then
			return entry.key
		end
	end
	return text
end

-- The spells to look up on the action bars, best first. On Forever a
-- cooldown item's spellID is the key every rank of a spell shares, which
-- is often not the rank on the bar. In order: the override spell, the rank
-- the game reports when it gives one (displaySpellID), the item's linked
-- spells, the rank the player knows by the spell's name, spellID, and last
-- the other ranks of that name in the spellbook (a lower rank kept on the
-- bar on purpose). Every id is checked for secrecy before any test on it.
local MAX_LINKED = 10
local PLAYER_BANK = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
local SPELL_ITEM = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell

local function SpellName(spellID)
	local get = C_Spell and C_Spell.GetSpellInfo
	if not get then return nil end
	local ok, info = pcall(get, spellID)
	local name = ok and type(info) == "table" and info.name
	if K.Plain(name) and type(name) == "string" and name ~= "" then return name end
end

local function KnownRank(name)
	local ok, found = pcall(C_Spell.GetSpellInfo, name)
	local id = ok and type(found) == "table" and found.spellID
	if K.Plain(id) and type(id) == "number" then return id end
end

-- The spellbook's ranks of a spell, by its name, at most MAX_LINKED; read
-- once until the bars or spells change.
local function SpellbookRanks(name)
	local cached = rankCache[name]
	if cached then return cached end
	local list = {}
	local book = C_SpellBook
	if book and book.GetNumSpellBookSkillLines and book.GetSpellBookSkillLineInfo and book.GetSpellBookItemInfo then
		local ok, lines = pcall(book.GetNumSpellBookSkillLines)
		lines = ok and K.Plain(lines) and type(lines) == "number" and lines or 0
		for line = 1, lines do
			local got, info = pcall(book.GetSpellBookSkillLineInfo, line)
			local offset = got and type(info) == "table" and info.itemIndexOffset
			local count = got and type(info) == "table" and info.numSpellBookItems
			if K.Plain(offset) and K.Plain(count) and type(count) == "number" then
				for slot = (tonumber(offset) or 0) + 1, (tonumber(offset) or 0) + count do
					local read, item = pcall(book.GetSpellBookItemInfo, slot, PLAYER_BANK)
					local id = read and type(item) == "table" and item.spellID
					local itemName = id and item.name
					if K.Plain(id) and type(id) == "number" and K.Plain(itemName) and itemName == name
						and not (K.Plain(item.isPassive) and item.isPassive)
						and (not SPELL_ITEM or not K.Plain(item.itemType) or item.itemType == SPELL_ITEM) then
						list[#list + 1] = id
						if #list >= MAX_LINKED then break end
					end
				end
			end
			if #list >= MAX_LINKED then break end
		end
	end
	rankCache[name] = list
	return list
end

local function Collector()
	local list, seen = {}, {}
	return list, function(id)
		if K.Plain(id) and type(id) == "number" and not seen[id] then
			seen[id] = true
			list[#list + 1] = id
		end
	end
end

-- A spell's ranks to look up, after the ones already added: the rank the
-- player knows by the spell's name, the spell itself, then the other ranks
-- of that name in the spellbook.
local function AddRanks(Add, base)
	if not (K.Plain(base) and type(base) == "number") then return end
	local name = SpellName(base)
	if name then Add(KnownRank(name)) end
	Add(base)
	if name then
		for _, id in ipairs(SpellbookRanks(name)) do Add(id) end
	end
end

local function ItemSpells(item)
	local info = item.GetCooldownInfo and item:GetCooldownInfo()
	if type(info) ~= "table" then return nil end
	local list, Add = Collector()
	Add(info.overrideSpellID)
	Add(info.displaySpellID)
	local linked = info.linkedSpellIDs
	if K.Plain(linked) and type(linked) == "table" then
		for index = 1, math.min(#linked, MAX_LINKED) do Add(linked[index]) end
	end
	AddRanks(Add, info.spellID)
	return list
end

-- The key of the first of `spells` that has one. In mode "hidden" none
-- when any of them sits on a button the player can see.
local function FirstBinding(spells, lookup, mode)
	lookup = lookup or SpellBinding
	local found
	for _, spellID in ipairs(spells or {}) do
		local text, seen = lookup(spellID, mode)
		if seen then return nil end
		if text then
			if mode ~= "hidden" then return text end
			found = found or text
		end
	end
	return found
end

-- The keybind of the first of the item's spells that sits on a bar.
local function ItemBinding(item, mode)
	return FirstBinding(ItemSpells(item), nil, mode)
end

-- The keybind of a spell on EldoUI's own cooldown rows and groups: the
-- spell's own slot first, else a slot that holds another rank of it (the
-- key the game shows for that slot; nothing is guessed).
local function SpellKeyBinding(spellID, mode)
	if not (spellID and K.Plain(spellID)) then return nil end
	local list, Add = Collector()
	Add(spellID)
	AddRanks(Add, spellID)
	return FirstBinding(list, M.SpellBinding or SpellBinding, mode)
end

-- The spell an item shows now (its keybind text follows it).
local function ItemSpell(item)
	local info = item.GetCooldownInfo and item:GetCooldownInfo()
	local spellID = type(info) == "table" and info.spellID or nil
	return K.Plain(spellID) and spellID or nil
end

local function UpdateKeybind(def, item)
	M.keybindUpdates = (M.keybindUpdates or 0) + 1
	keybindSpell[item], keybindVersion[item] = ItemSpell(item), settingsVersion
	local db = VDB(def)
	local mode = KeyTextMode(db)
	local show = Allowed("improve") and mode ~= "off"
	local text = keybindText[item]
	if not show then
		if text then text:Hide() end
		return
	end
	if not text then
		local holder = CreateFrame("Frame", nil, item)
		holder:SetAllPoints(def.bars and item.Icon or item)
		holder:SetFrameLevel(item:GetFrameLevel() + 10)
		text = holder:CreateFontString(nil, "OVERLAY")
		keybindText[item] = text
	end
	local point = M.db.keybindPoint or "TOPRIGHT"
	local inset = 2
	local x = point:find("LEFT") and inset or (point:find("RIGHT") and -inset or 0)
	local y = point:find("TOP") and -inset or (point:find("BOTTOM") and inset or 0)
	text:ClearAllPoints()
	text:SetPoint(point, text:GetParent(), point, x, y)
	E:SetFont(text, db.keybindSize or E.tokens.size.small, Outline(), FontFile)
	text:SetTextColor(unpack(M.db.keybindColor))
	text:SetText(ItemBinding(item, mode) or "")
	text:Show()
end

local function UpdateAllKeybinds()
	for _, def in ipairs(VIEWERS) do
		if Handles(def) then
			for _, item in ipairs(Items(Viewer(def))) do UpdateKeybind(def, item) end
		end
	end
end

local refreshQueued = false
local function QueueKeybinds()
	wipe(bindingCache)
	wipe(rankCache)
	if refreshQueued then return end
	refreshQueued = true
	C_Timer.After(0.1, function()
		refreshQueued = false
		UpdateAllKeybinds()
		if M.UpdateRowKeybinds then M:UpdateRowKeybinds() end
	end)
end

---------------------------------------------------------------------------
-- Skin
---------------------------------------------------------------------------
local function HideOverlay(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:IsObjectType("Texture") and region.GetAtlas and region:GetAtlas() == OVERLAY_ATLAS then
			K.Alpha0(GROUP, region)
		end
	end
end

local function SkinIcon(frame, icon)
	if not icon then return end
	K.RemoveMasks(GROUP, frame, icon)
	HideOverlay(frame)
	K.TexCoord(GROUP, icon, (M.db.zoom or 8) / 100)
	if M.db.borders then
		K.Backdrop(GROUP, frame, icon)
	elseif K.GetBackdrop(frame) then
		K.GetBackdrop(frame):Hide()
	end
end

local swipeSet = setmetatable({}, { __mode = "k" })

local function SkinCooldown(cooldown, size)
	if not cooldown then return end
	if M.db.squareSwipe and cooldown.SetSwipeTexture then
		if not swipeSet[cooldown] then
			swipeSet[cooldown] = true
			cooldown:SetSwipeTexture(E.media.flat)
		end
	elseif swipeSet[cooldown] then
		swipeSet[cooldown] = nil
		cooldown:SetSwipeTexture(BLIZZARD_SWIPE)
	end
	local text = cooldown.GetCountdownFontString and cooldown:GetCountdownFontString()
	if text then K.Font(GROUP, text, size, Outline(), FontFile()) end
end

local function SkinIconItem(def, item)
	local db = VDB(def)
	SkinIcon(item, item.Icon)
	SkinCooldown(item.Cooldown, db.countdownSize)
	if item.ChargeCount and item.ChargeCount.Current then
		K.Font(GROUP, item.ChargeCount.Current, db.countSize, Outline(), FontFile())
	end
	if item.Applications and item.Applications.Applications then
		K.Font(GROUP, item.Applications.Applications, db.countSize, Outline(), FontFile())
	end
end

-- Blizzard colors the bars once from the template; EldoUI remembers that
-- color so "Blizzard" and Restore can put it back.
local barColors = setmetatable({}, { __mode = "k" })

local function BarColor(bar)
	if not barColors[bar] then
		local r, g, b = bar:GetStatusBarColor()
		if K.Plain(r, g, b) then barColors[bar] = { r, g, b } end
	end
	local mode = M.db.bars.colorMode
	if mode == "accent" then
		bar:SetStatusBarColor(unpack(E.media.accentColor, 1, 3))
	elseif mode == "class" then
		bar:SetStatusBarColor(E:ClassColor("player"))
	elseif mode == "custom" then
		bar:SetStatusBarColor(unpack(M.db.bars.color))
	elseif barColors[bar] then
		bar:SetStatusBarColor(unpack(barColors[bar]))
	end
end

local function SkinBarItem(def, item)
	local db = VDB(def)
	local bars = M.db.bars
	local iconFrame = item.Icon
	if iconFrame then SkinIcon(iconFrame, iconFrame.Icon) end
	if iconFrame and iconFrame.Applications then
		K.Font(GROUP, iconFrame.Applications, db.countSize, Outline(), FontFile())
	end
	local bar = item.Bar
	if not bar then return end
	K.BarTexture(GROUP, bar, K.TexturePath(bars.texture ~= "" and bars.texture or nil))
	if bar.BarBG then K.Alpha0(GROUP, bar.BarBG) end
	K.Backdrop(GROUP, bar, bar, E.pixel, true)
	if bar.Pip then
		K.Alpha0(GROUP, bar.Pip)
		if bars.spark then bar.Pip:SetAlpha(1) end
	end
	if bar.Name then K.Font(GROUP, bar.Name, db.nameSize, Outline(), FontFile()) end
	if bar.Duration then K.Font(GROUP, bar.Duration, db.durationSize, Outline(), FontFile()) end
	BarColor(bar)
end

-- Everything the skin changed, back to Blizzard's look.
local function Unskin()
	K.Undo(GROUP)
	settingsVersion = settingsVersion + 1
	for cooldown in pairs(swipeSet) do
		cooldown:SetSwipeTexture(BLIZZARD_SWIPE)
		swipeSet[cooldown] = nil
	end
	for bar, color in pairs(barColors) do
		bar:SetStatusBarColor(unpack(color))
		barColors[bar] = nil
	end
end

-- An item keeps its skin until the settings change (M:Apply).
local function SkinItem(def, item)
	if not Allowed("skin") or skinnedAt[item] == settingsVersion then return end
	skinnedAt[item] = settingsVersion
	M.itemSkins = (M.itemSkins or 0) + 1
	if def.bars then
		SkinBarItem(def, item)
	else
		SkinIconItem(def, item)
	end
end

---------------------------------------------------------------------------
-- Placement: holder + mover per viewer, and EldoUI's own icon grid.
---------------------------------------------------------------------------
-- Where the first item sits, by growth direction and wrap.
local function StartCorner(db, bars)
	if bars then return db.growth == "DOWN" and "TOP" or "BOTTOM" end
	local growth, up = db.growth, db.wrap == "UP"
	if growth == "LEFT" then return up and "BOTTOMRIGHT" or "TOPRIGHT" end
	if growth == "CENTER" then return up and "BOTTOM" or "TOP" end
	if growth == "UP" then return "BOTTOMLEFT" end
	return up and "BOTTOMLEFT" or "TOPLEFT" -- RIGHT and DOWN
end

-- Size of one full row (the holder and mover show this).
local function RowSize(def)
	local db = VDB(def)
	if def.bars then return db.width, db.height end
	local length = db.perRow * db.size + (db.perRow - 1) * db.spacing
	if db.growth == "UP" or db.growth == "DOWN" then return db.size, length end
	return length, db.size
end

local function AttachTarget(def)
	local target = VDB(def).attach
	if target == "player" then return E.movers.EldoUI_Player or PlayerFrame end
	if target == "bar1" then return E.movers.EldoUI_ActionBar1 or MainActionBar end
	if target == "power" then return E.movers.EldoUI_PlayerPower end
	if target == "essential" and def.key ~= "essential" then return K.GetHolder("EldoUI_Cooldowns") end
end

local OPPOSITE = { TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT" }

local function PlaceHolder(def)
	local holder = K.GetHolder(def.mover)
	local mover = E.movers[def.mover]
	if not holder or not mover then return end
	local db = VDB(def)
	holder:SetSize(RowSize(def))
	holder:ClearAllPoints()
	local target = Allowed("move") and AttachTarget(def)
	if target and target ~= holder then
		local side = db.attachSide or "BOTTOM"
		local gap = db.attachGap or 0
		local x = side == "LEFT" and -gap or (side == "RIGHT" and gap or 0)
		local y = side == "BOTTOM" and -gap or (side == "TOP" and gap or 0)
		holder:SetPoint(OPPOSITE[side] or "TOP", target, side, x, y)
	else
		holder:SetPoint("CENTER", mover, "CENTER")
	end
end

-- EldoUI's icon grid: places `items` inside `container` by the size,
-- spacing, per-row, growth and wrap settings in `db`, and sizes the
-- container to the used area. Also used by the own cooldown rows.
function M.Grid(items, container, db)
	local count = #items
	local size, spacing, perRow = db.size, db.spacing, math.max(db.perRow, 1)
	local step = size + spacing
	local vertical = db.growth == "UP" or db.growth == "DOWN"
	local anchor = StartCorner(db)
	local xDir = db.growth == "LEFT" and -1 or 1
	local yDir = (db.wrap == "UP" or db.growth == "UP") and 1 or -1
	for index, item in ipairs(items) do
		local i = index - 1
		local line, slot = math.floor(i / perRow), i % perRow
		local x, y
		if vertical then
			x, y = line * step, slot * step * yDir
		elseif db.growth == "CENTER" then
			local inLine = math.min(perRow, count - line * perRow)
			x, y = (slot - (inLine - 1) / 2) * step, line * step * yDir
		else
			x, y = slot * step * xDir, line * step * yDir
		end
		item:SetScale(1)
		item:SetSize(size, size)
		item:ClearAllPoints()
		item:SetPoint(anchor, container, anchor, x, y)
	end
	local lines = math.max(math.ceil(count / perRow), 1)
	local across = math.max(math.min(count, perRow), 1)
	local long, short = across * size + (across - 1) * spacing, lines * size + (lines - 1) * spacing
	if vertical then container:SetSize(short, long) else container:SetSize(long, short) end
end


-- EldoUI's grid: called after every Blizzard Layout pass of the viewer.
local function Arrange(def, items)
	local viewer = Viewer(def)
	if not viewer or K.EditModeActive() then return end
	local db = VDB(def)
	items = items or Items(viewer)
	local count = #items
	if def.bars then
		local step = db.height + db.spacing
		local anchor = StartCorner(db, true)
		local direction = anchor == "TOP" and -1 or 1
		for index, item in ipairs(items) do
			item:SetScale(1)
			item:SetSize(db.width, db.height)
			if item.Icon then
				item.Icon:SetSize(db.height, db.height)
				item.Icon:SetShown(M.db.bars.showIcon)
			end
			if item.Bar then item.Bar:SetHeight(db.height) end
			item:ClearAllPoints()
			item:SetPoint(anchor, viewer, anchor, 0, direction * (index - 1) * step)
		end
		viewer:SetSize(db.width, math.max(count * step - db.spacing, db.height))
		return
	end
	M.Grid(items, viewer, db)
end

local function PinViewer(def)
	local viewer = Viewer(def)
	local holder = K.GetHolder(def.mover)
	if not viewer or not holder then return end
	K.Pin(viewer, {
		anchor = function()
			local corner = StartCorner(VDB(def), def.bars)
			return corner, holder, corner, 0, 0
		end,
		active = function() return Handles(def) and Allowed("move") end,
	})
end

---------------------------------------------------------------------------
-- Visibility and hiding
---------------------------------------------------------------------------
local function ApplyVisibility(def)
	local viewer = Viewer(def)
	if not viewer then return end
	local db = VDB(def)
	local fadeKey = "cdm-" .. def.key
	if Handles(def) and E:BlizzardHidden(ID) and db.hide then
		K.StopVisibility(fadeKey)
		K.Parent(viewer, K.hider)
	elseif Handles(def) and Allowed("improve") and not E:VisibilityIsPlain(db.fade) then
		local fader = K.Visibility(fadeKey, viewer, db.fade)
		K.Parent(viewer, fader)
	else
		K.StopVisibility(fadeKey)
		K.RestoreParent(viewer)
	end
end

---------------------------------------------------------------------------
-- One viewer, after Blizzard laid it out or a setting changed
---------------------------------------------------------------------------
local function Refresh(def)
	local viewer = Viewer(def)
	if not viewer or laying[def.key] then return end
	if not Handles(def) then return end
	laying[def.key] = true
	M.refreshes = (M.refreshes or 0) + 1
	local ok, err = pcall(function()
		local items = Items(viewer)
		if Allowed("move") and VDB(def).layout then Arrange(def, items) end
		for _, item in ipairs(items) do
			SkinItem(def, item)
			-- Binding, slot and page events redo every keybind
			-- (QueueKeybinds); a layout pass only fills new items, items
			-- that show another spell now, and new settings.
			if not keybindText[item] or keybindVersion[item] ~= settingsVersion or keybindSpell[item] ~= ItemSpell(item) then
				UpdateKeybind(def, item)
			end
		end
	end)
	laying[def.key] = nil
	if not ok then geterrorhandler()(err) end
end

-- Blizzard can lay a viewer out several times in one frame (auras coming
-- and going): the first pass is followed at once, the others share one
-- more refresh on the next frame.
local lastRefresh, refreshLater = {}, {}
local function LayoutDone(def)
	local now = GetTime()
	if lastRefresh[def.key] ~= now then
		lastRefresh[def.key] = now
		Refresh(def)
		return
	end
	if refreshLater[def.key] then return end
	refreshLater[def.key] = true
	C_Timer.After(0, function()
		refreshLater[def.key] = nil
		lastRefresh[def.key] = GetTime()
		Refresh(def)
	end)
end

local function HookViewer(def)
	local viewer = Viewer(def)
	if not viewer or hookedViewers[def.key] then return end
	hookedViewers[def.key] = true
	if type(viewer.Layout) == "function" then
		hooksecurefunc(viewer, "Layout", function() LayoutDone(def) end)
	end
end

---------------------------------------------------------------------------
-- Apply and restore
---------------------------------------------------------------------------
-- "Match size" in move mode: the settings that give each holder its
-- width and height (RowSize). A bar is one bar wide and tall; an icon row
-- is one icon across its growth, and as long as its icons along it, which
-- no single setting sets.
local function SizeKeys(def)
	local p = "viewers." .. def.key .. "."
	if def.bars then
		return { width = { key = p .. "width", min = 80, max = 400 }, height = { key = p .. "height", min = 10, max = 40 } }
	end
	local function Across(vertical)
		return function()
			local growth = VDB(def).growth
			if (growth == "UP" or growth == "DOWN") == vertical then return { key = p .. "size", min = 16, max = 80 } end
		end
	end
	return { width = Across(true), height = Across(false) }
end

-- Move mode's stand-in for an empty viewer: a few sample spells in the
-- viewer's size, spacing, zoom, borders and keybinds, starting where the
-- first real icon sits (the growth direction).
local GROWTH_START = { LEFT = "RIGHT", RIGHT = "LEFT", CENTER = "CENTER", UP = "BOTTOM", DOWN = "TOP" }
local function StandIn(def)
	if def.bars then return nil end
	return function()
		local db, viewer = M.db, VDB(def)
		if not (db and viewer) then return nil end
		local vertical = viewer.growth == "UP" or viewer.growth == "DOWN"
		local count = math.min(viewer.perRow or 6, 6)
		return "icons", {
			count = count, columns = vertical and 1 or count, size = viewer.size, spacing = viewer.spacing,
			keys = viewer.keybinds, fontSize = viewer.keybindSize, zoom = db.zoom, borders = db.borders,
			pool = def.key == "buffIcons" and "buffs" or "spells", align = GROWTH_START[viewer.growth] or "CENTER",
		}
	end
end

function M:CreateHolders()
	for _, def in ipairs(VIEWERS) do
		if not K.GetHolder(def.mover) then
			local w, h = RowSize(def)
			local sample = StandIn(def)
			K.Holder(self, def.mover, L[def.title], def.point, w, h, { sizeKeys = SizeKeys(def), sample = sample and { config = sample } or nil })
		end
	end
end

function M:Apply()
	if not self.active then return end
	settingsVersion = settingsVersion + 1
	K.BindSwitches(self)
	if self.ApplyRows then self:ApplyRows() end
	if not E:BlizzardAllowed(ID) then
		self:Restore()
		return
	end
	if self.db.turnOn then E:SetCVar("cooldownViewerEnabled", "1", ID) end
	if not Allowed("skin") then Unskin() end
	wipe(bindingCache)
	wipe(rankCache)
	for _, def in ipairs(VIEWERS) do
		local viewer = Viewer(def)
		if viewer then
			HookViewer(def)
			PlaceHolder(def)
			if Handles(def) and Allowed("move") then
				PinViewer(def)
			else
				K.Unpin(viewer)
			end
			ApplyVisibility(def)
			Refresh(def)
		end
	end
end

-- Back to Blizzard: unpin, unparent, unskin. Item positions settle on
-- Blizzard's next layout pass (a /reload at the latest).
function M:Restore()
	for _, def in ipairs(VIEWERS) do
		local viewer = Viewer(def)
		if viewer then
			K.Unpin(viewer)
			K.StopVisibility("cdm-" .. def.key)
			K.RestoreParent(viewer)
			for _, item in ipairs(Items(viewer)) do
				if keybindText[item] then keybindText[item]:Hide() end
			end
		end
	end
	Unskin()
end

-- Shared with Modules/CombatHUD/CooldownRows.lua.
M.VIEWERS = BY_KEY
M.StartCorner = StartCorner
M.PlaceHolder = PlaceHolder
M.FontFile = FontFile
M.Outline = Outline
M.SpellBinding = SpellBinding
M.ItemBinding = ItemBinding
M.SpellKeyBinding = SpellKeyBinding
M.KeyTextMode = KeyTextMode
M.LayoutDone = LayoutDone
function M.ResetKeybindCache()
	wipe(bindingCache)
	wipe(rankCache)
end

---------------------------------------------------------------------------
-- Saved sets per class and spec: the player's own layout, captured as
-- Blizzard's layout string (see Modules/Setups.lua) and shown again for
-- Blizzard's Import box.
---------------------------------------------------------------------------
local function Setup()
	return E.addonSetups and E.addonSetups.CooldownManager
end

-- The class and spec in plain words ("Arms Warrior").
local function SpecName(setup)
	return setup and setup.keyLabel and setup.keyLabel() or L["this spec"]
end

-- Why Import can't show anything yet, or nil when a set is saved.
function M:ImportBlocked()
	local setup = Setup()
	if not setup then return L["Blizzard's Cooldown Manager isn't loaded."] end
	if not E:GetAddonProfileString(setup) then
		return L["No saved set for %s yet. Use Capture this spec's set first."]:format(SpecName(setup))
	end
end

function M:ImportSet()
	local setup = Setup()
	if not setup then return end
	if not setup.available() then
		self:Print(L["Blizzard's Cooldown Manager isn't loaded."])
		return
	end
	local data = E:GetAddonProfileString(setup)
	if not data then
		self:Print(L["No saved set for %s yet. Set it up in Blizzard's Cooldown Manager, then use Capture this spec's set (or %s)."]
			:format(SpecName(setup), E:Highlight("/eui cdm capture")))
		return
	end
	setup.import(data)
end

function M:OpenBlizzardSettings()
	if InCombatLockdown() then
		self:Print(L["Blizzard's Cooldown Manager settings open after combat."])
		return
	end
	if CooldownViewerSettings and CooldownViewerSettings.TogglePanel then
		CooldownViewerSettings:TogglePanel()
	else
		self:Print(L["Blizzard's Cooldown Manager isn't available on this character."])
	end
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
-- Settings before the shared visibility rules: each viewer's "Show" rule
-- and faded opacity (0-100) become its visibility block, once.
function M:MigrateVisibility()
	local viewers = type(self.db) == "table" and self.db.viewers
	if type(viewers) ~= "table" then return end
	for _, def in ipairs(VIEWERS) do
		local db = viewers[def.key]
		if type(db) == "table" and (db.visibility ~= nil or db.fadeAlpha ~= nil) then
			if type(db.visibility) == "string" and db.visibility ~= "always" then
				db.fade = E:VisibilityFromLegacy(db.visibility, (tonumber(db.fadeAlpha) or 0) / 100)
			end
			E:NormalizeVisibility(db.fade)
			db.visibility, db.fadeAlpha = nil, nil
		end
	end
end

-- The "Keybinds" tick became the Key text choice: a tick turned off reads
-- as Off, and a tick turned on where it used to be off by default (the
-- buff viewers) as All. Essential and Utility otherwise take the new
-- default, Only hidden buttons.
local KEYBINDS_WERE_OFF = { buffIcons = true, buffBars = true }
function M.MigrateKeyText(profile)
	local modules = type(profile) == "table" and type(profile.modules) == "table" and profile.modules
	local own = modules and type(modules.CooldownManager) == "table" and modules.CooldownManager
	local viewers = own and type(own.viewers) == "table" and own.viewers
	if not viewers then return end
	for key, db in pairs(viewers) do
		if type(db) == "table" and db.keybinds ~= nil then
			if db.keyText == nil then
				if db.keybinds == false then
					db.keyText = "off"
				elseif db.keybinds == true and KEYBINDS_WERE_OFF[key] then
					db.keyText = "all"
				end
			end
			db.keybinds = nil
		end
	end
end
E:RegisterProfileMigration(M.MigrateKeyText, "CooldownManager:keyText", 1)

-- "Only hidden buttons" follows the action bars: a layout switch, a bar
-- turned on or off, its button count or Show rule, and the Action Bars
-- module itself turning on or off refresh the key texts.
local function BarsChanged()
	if M.active then QueueKeybinds() end
end
E:RegisterLayoutCallback(BarsChanged)
do
	local bars = E.modules and E.modules.ActionBars
	if bars then
		for _, method in ipairs({ "Apply", "ApplyChanges", "OnDisable" }) do
			if type(bars[method]) == "function" then hooksecurefunc(bars, method, BarsChanged) end
		end
	end
end

function M:OnInitialize()
	K.BindSwitches(self)
	self:MigrateVisibility()
end

function M:OnEnable()
	K.BindSwitches(self)
	self:MigrateVisibility()
	self:CreateHolders()
	for _, event in ipairs({ "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "SPELLS_CHANGED", "INPUT_DEVICE_INTERFACE_TRANSITION" }) do
		self:RegisterEvent(event, QueueKeybinds)
	end
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() M:Apply() end)
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("EditMode.Exit", function()
			C_Timer.After(0, function() M:Apply() end)
		end, self)
	end
	self:Apply()
end

function M:OnDisable()
	for _, event in ipairs({ "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "SPELLS_CHANGED", "INPUT_DEVICE_INTERFACE_TRANSITION", "PLAYER_ENTERING_WORLD" }) do
		self:UnregisterEvent(event)
	end
	if EventRegistry and EventRegistry.UnregisterCallback then
		EventRegistry:UnregisterCallback("EditMode.Exit", self)
	end
	self:Restore()
	if self.HideRows then self:HideRows() end
end

function M:OnProfileChanged()
	K.BindSwitches(self)
	self:MigrateVisibility()
	if self.active then self:Apply() end
end

E:RegisterBlizzardHandler(ID, {
	owner = "CooldownManager",
	apply = function() M:Apply() end,
	undo = function() M:Restore() end,
	reload = { skin = true, move = true },
	install = { skin = true, move = true, improve = true },
	-- v0.5.0 never touched the Cooldown Manager.
	legacy = function() return false end,
})

E:AddCommand("cdm", "[settings | import | capture]  Cooldown Manager: EldoUI options, Blizzard's settings, import or capture this spec's set", function(arg)
	arg = (arg or ""):lower()
	if arg == "settings" then
		M:OpenBlizzardSettings()
	elseif arg == "import" then
		M:ImportSet()
	elseif arg == "capture" then
		E:CaptureAddon("CooldownManager")
	else
		E:ToggleConfig("module:CooldownManager")
	end
end, "Layout & frames")

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local GROWTH = { RIGHT = "Right", LEFT = "Left", CENTER = "From the center", UP = "Up (columns)", DOWN = "Down (columns)" }
local WRAP = { DOWN = "New rows below", UP = "New rows above" }
local ATTACH = { mover = "Own mover", player = "Player frame", bar1 = "Action bar 1", power = "Resource bar", essential = "Essential cooldowns" }
local ATTACH_ESSENTIAL = { mover = "Own mover", player = "Player frame", bar1 = "Action bar 1", power = "Resource bar" }
local SIDES = { TOP = "Above", BOTTOM = "Below", LEFT = "Left of it", RIGHT = "Right of it" }
local OUTLINES = { NONE = "None", OUTLINE = "Outline", THICKOUTLINE = "Thick outline" }

local function Textures()
	local values = K.TextureValues()
	values[""] = L["Theme texture"]
	return values
end

local function NotMove() return not E:BlizzardAllowed(ID, "move") end
local function NotImprove() return not E:BlizzardAllowed(ID, "improve") end
local function NotSkin() return not E:BlizzardAllowed(ID, "skin") end
local function NotHide() return not E:BlizzardHidden(ID) end
local function Off() return not E:BlizzardAllowed(ID) end

-- Rows that wait on a switch stay on screen, grayed, and say which switch
-- they need: a tab never opens blank.
local function NeedSwitch(label) return L["Turn on \"%s\" on the General tab first."]:format(L[label]) end
local function WaitOff() if Off() then return NeedSwitch(L["Let EldoUI change this"]) end end
-- The switch names come from the shared labels, so they always match the
-- rows on the General tab.
local SWITCH = E.BLIZZARD_ACTION_LABEL
local function WaitSkin() return WaitOff() or (NotSkin() and NeedSwitch(SWITCH.skin)) or nil end
local function WaitMove() return WaitOff() or (NotMove() and NeedSwitch(SWITCH.move)) or nil end
local function WaitImprove() return WaitOff() or (NotImprove() and NeedSwitch(SWITCH.improve)) or nil end
local function WaitHide() return WaitOff() or (NotHide() and NeedSwitch(SWITCH.hide)) or nil end

-- Preview: a trimmed row of sample spells in the essential viewer's size,
-- spacing, zoom, borders and keybinds (E:ConfigSample,
-- Core/MoverSamples.lua).
function M.UpdatePreview(canvas)
	local db = M.db
	local viewer = db and db.viewers and db.viewers.essential
	if not (canvas and viewer) then return end
	E:ConfigSample(canvas, "icons", {
		count = math.min(viewer.perRow or 8, 8), size = viewer.size, spacing = viewer.spacing,
		keys = KeyTextMode(viewer) ~= "off", fontSize = viewer.keybindSize, zoom = db.zoom, borders = db.borders, cooldown = 0.5,
	})
end

local options = {
	{ type = "tab", label = "General" },
}
K.SwitchOptions(options, ID, {
	skin = L["Square icons, 1 px borders, theme fonts and flat bars."],
	move = L["EldoUI movers, attach points and the icon grid below. Off keeps Blizzard's Edit Mode position and layout."],
	hide = L["Hide the viewers checked under \"Hide this viewer\"."],
	improve = L["Keybind text on the icons and the visibility rules."],
})
for _, row in ipairs({
	{ type = "toggle", key = "turnOn", label = "Turn the Cooldown Manager on", disabled = WaitOff,
		desc = "Sets Blizzard's own Cooldown Manager option (CVar cooldownViewerEnabled) while the master switch is on. The old value comes back with Blizzard default." },
	{ type = "header", label = "Sets per class and spec" },
	{ type = "description",
		label = "Capture saves your Cooldown Manager layout for this class and spec. Import shows it as Blizzard's import string, ready to paste." },
	{ type = "execute", label = "Import this spec's set", width = 200, disabled = function() return WaitOff() or M:ImportBlocked() end,
		desc = "Shows the set you captured for this class and spec, ready to paste into Blizzard's Import box.",
		func = function() M:ImportSet() end },
	{ type = "execute", label = "Capture this spec's set", width = 200, disabled = WaitOff,
		desc = "Saves your current Cooldown Manager layout as the set for this class and spec (/eui capture CooldownManager).",
		func = function() E:CaptureAddon("CooldownManager") end },
	{ type = "execute", label = "Blizzard's settings", width = 200, disabled = WaitOff,
		desc = "Opens Blizzard's Cooldown Manager settings: which spells show in which viewer.",
		func = function() M:OpenBlizzardSettings() end },
	{ type = "tab", label = "Look" },
	{ type = "preview", label = "Preview", height = 72, create = function(canvas) M.UpdatePreview(canvas) end,
		update = function(canvas) M.UpdatePreview(canvas) end,
		desc = "A sample essential row in its icon size, spacing, zoom, borders and keybinds." },
	{ type = "header", label = "Icons", fold = true },
	{ type = "range", key = "zoom", label = "Icon zoom", min = 0, max = 20, step = 1, unit = "%", disabled = WaitSkin,
		desc = "How much of each icon edge is cut away, in percent. 8 is EldoUI's default." },
	{ type = "toggle", key = "borders", label = "1 px borders", disabled = WaitSkin,
		desc = "A flat EldoUI border behind every icon." },
	{ type = "toggle", key = "squareSwipe", label = "Square cooldown swipe", disabled = WaitSkin,
		desc = "The dark cooldown swipe fills the square icon instead of Blizzard's rounded shape." },
	{ type = "header", label = "Text", fold = true },
	{ type = "media", mediaKind = "font", default = "THEME", defaultLabel = "Theme font", key = "font", label = "Font", disabled = WaitSkin,
		desc = "Font of the countdown, charges, stacks, bar texts and keybinds." },
	{ type = "select", key = "fontOutline", label = "Outline", values = OUTLINES, disabled = WaitSkin,
		desc = "Outline of the cooldown texts." },
	{ type = "header", label = "Keybinds", fold = true },
	{ type = "select", key = "keybindPoint", label = "Keybind position", values = K.ANCHORS, disabled = WaitImprove,
		desc = "Corner of the icon the keybind sits in." },
	{ type = "color", key = "keybindColor", label = "Keybind color", disabled = WaitImprove,
		desc = "Color of the keybind text." },
	{ type = "header", label = "Buff bars", fold = true },
	{ type = "select", key = "bars.texture", label = "Bar texture", values = Textures, disabled = WaitSkin,
		desc = "Texture of the buff bars." },
	{ type = "select", key = "bars.colorMode", label = "Bar color", disabled = WaitSkin,
		values = { blizzard = "Blizzard", accent = "Accent color", class = "Class color", custom = "Custom color" },
		desc = "Color of the buff bars." },
	{ type = "color", key = "bars.color", label = "Custom bar color", disabled = WaitSkin,
		desc = "Used when the bar color is set to Custom color." },
	{ type = "toggle", key = "bars.spark", label = "Spark", disabled = WaitSkin,
		desc = "Blizzard's bright tip at the end of each buff bar." },
	{ type = "toggle", key = "bars.showIcon", label = "Bar icons", disabled = WaitMove,
		desc = "The spell icon in front of each buff bar." },
}) do
	table.insert(options, row)
end

local VIEWER_TITLES = { essential = "Essential", utility = E.Key("Utility"), buffIcons = "Buff icons", buffBars = "Buff bars" }
local VIEWER_OFF_DESC = {
	essential = L["Off leaves Blizzard's essential viewer exactly as Blizzard made it."],
	utility = L["Off leaves Blizzard's utility viewer exactly as Blizzard made it."],
	buffIcons = L["Off leaves Blizzard's buff icons viewer exactly as Blizzard made it."],
	buffBars = L["Off leaves Blizzard's buff bars viewer exactly as Blizzard made it."],
}

for _, def in ipairs(VIEWERS) do
	local p = "viewers." .. def.key .. "."
	local name = VIEWER_TITLES[def.key]
	local function ViewerDB() return M.db.viewers[def.key] end
	-- The reason a row of this tab waits, or nil: the General tab's
	-- switches first, then this tab's own "EldoUI handles this viewer".
	local function WaitHandled()
		return WaitOff() or (not ViewerDB().enabled and L["Turn on \"%s\" first."]:format(L["EldoUI handles this viewer"])) or nil
	end
	local function WaitMoveHere() return WaitMove() or WaitHandled() end
	local function WaitGrid()
		return WaitMoveHere() or (not ViewerDB().layout and L["Turn on \"%s\" first."]:format(L["EldoUI layout"])) or nil
	end
	local function WaitAttached()
		return WaitMoveHere() or (ViewerDB().attach == "mover" and L["Pick a frame under \"%s\" first."]:format(L["Attach to"])) or nil
	end
	local function WaitImproveHere() return WaitImprove() or WaitHandled() end
	local function WaitSkinHere() return WaitSkin() or WaitHandled() end
	table.insert(options, { type = "tab", label = name })
	table.insert(options, { type = "toggle", key = p .. "enabled", label = "EldoUI handles this viewer", disabled = WaitOff,
		desc = VIEWER_OFF_DESC[def.key] })
	table.insert(options, { type = "toggle", key = p .. "hide", label = "Hide this viewer", disabled = function() return WaitHide() or WaitHandled() end,
		desc = "Hidden while the element's Hide switch is on." })
	table.insert(options, { type = "header", label = "Position", fold = true })
	table.insert(options, { type = "select", key = p .. "attach", label = "Attach to", disabled = WaitMoveHere,
		values = def.key == "essential" and ATTACH_ESSENTIAL or ATTACH,
		desc = "Own mover: drag it in move mode (%s). Otherwise the viewer follows the chosen frame.", descFill = def.title })
	table.insert(options, { type = "select", key = p .. "attachSide", label = "Side", values = SIDES, disabled = WaitAttached,
		desc = "Which side of the chosen frame the viewer sits on." })
	table.insert(options, { type = "range", key = p .. "attachGap", label = "Gap", min = 0, max = 40, step = 1, unit = "px", disabled = WaitAttached,
		desc = "Space between the viewer and the chosen frame." })
	table.insert(options, { type = "header", label = "Layout", fold = true })
	table.insert(options, { type = "toggle", key = p .. "layout", label = "EldoUI layout", disabled = WaitMoveHere,
		desc = "Arrange the items with the settings below. Off keeps Blizzard's layout from Edit Mode." })
	if def.bars then
		table.insert(options, { type = "range", key = p .. "width", label = "Width", min = 80, max = 400, step = 1, unit = "px", disabled = WaitGrid,
			desc = "Width of each buff bar." })
		table.insert(options, { type = "range", key = p .. "height", label = "Height", min = 10, max = 40, step = 1, unit = "px", disabled = WaitGrid,
			desc = "Height of each buff bar; the icon matches it." })
		table.insert(options, { type = "range", key = p .. "spacing", label = "Spacing", min = 0, max = 20, step = 1, unit = "px", disabled = WaitGrid,
			desc = "Space between bars." })
		table.insert(options, { type = "select", key = p .. "growth", label = "Growth direction", values = { UP = "Up", DOWN = "Down" }, disabled = WaitGrid,
			desc = "Direction new bars are added in." })
	else
		table.insert(options, { type = "range", key = p .. "size", label = "Icon size", min = 16, max = 80, step = 1, unit = "px", disabled = WaitGrid,
			desc = "Width and height of each icon." })
		table.insert(options, { type = "range", key = p .. "spacing", label = "Spacing", min = 0, max = 20, step = 1, unit = "px", disabled = WaitGrid,
			desc = "Space between icons." })
		table.insert(options, { type = "range", key = p .. "perRow", label = "Icons per row", min = 1, max = 24, step = 1, disabled = WaitGrid,
			desc = "Icons in one row (or column) before a new one starts." })
		table.insert(options, { type = "select", key = p .. "growth", label = "Growth direction", values = GROWTH, disabled = WaitGrid,
			desc = "Direction icons are added in. From the center keeps every row centered." })
		table.insert(options, { type = "select", key = p .. "wrap", label = "New rows", values = WRAP, disabled = WaitGrid,
			desc = "Where a new row starts when one is full." })
	end
	table.insert(options, { type = "header", label = "Visibility and text", fold = true })
	-- The shared visibility rows. Blizzard's own visibility setting (Edit
	-- Mode) still applies on top.
	for _, row in ipairs(E:VisibilityOptions(p .. "fade", { db = function() return M.db end, label = false, disabled = WaitImproveHere })) do
		table.insert(options, row)
	end
	table.insert(options, { type = "select", key = p .. "keyText", label = "Key text", values = KEY_TEXT,
		order = { "all", "hidden", "off" }, disabled = WaitImproveHere,
		desc = "The key of the action button that holds the spell. Only hidden buttons: just for spells on buttons you can't see, such as a bar that is off, shortened or shown only on mouse over." })
	table.insert(options, { type = "range", key = p .. "keybindSize", label = "Keybind size", min = 6, max = 24, step = 1,
		disabled = WaitImproveHere, desc = "Font size of the keybind text." })
	if def.bars then
		table.insert(options, { type = "range", key = p .. "nameSize", label = "Name size", min = 6, max = 24, step = 1,
			disabled = WaitSkinHere, desc = "Font size of the spell name." })
		table.insert(options, { type = "range", key = p .. "durationSize", label = "Time size", min = 6, max = 24, step = 1,
			disabled = WaitSkinHere, desc = "Font size of the remaining time." })
	else
		table.insert(options, { type = "range", key = p .. "countdownSize", label = "Countdown size", min = 6, max = 32, step = 1,
			disabled = WaitSkinHere, desc = "Font size of the cooldown countdown." })
	end
	table.insert(options, { type = "range", key = p .. "countSize", label = "Charges and stacks size", min = 6, max = 24, step = 1,
		disabled = WaitSkinHere, desc = "Font size of charges and stacks." })
end
M.options = options

---------------------------------------------------------------------------
-- Style presets
---------------------------------------------------------------------------
-- Seven looks (DESIGN.md section 5). Bar colors and fading out of combat
-- are options of their own. The key "Clean" stays as saved in
-- profiles; the player reads "Centered".
E:RegisterStyles("CooldownManager", {
	{ key = "Clean", title = "Centered", desc = "Square 46 px essential icons, 36 px utility, centered rows, key text for spells on buttons you can't see.",
		settings = { zoom = 8, borders = true, squareSwipe = true,
			viewers = { essential = { size = 46, spacing = 4, perRow = 8, growth = "CENTER", wrap = "DOWN", keyText = "hidden" },
				utility = { size = 36, spacing = 4, perRow = 10, growth = "CENTER", wrap = "DOWN", keyText = "hidden" },
				buffIcons = { size = 34, spacing = 4, perRow = 12, growth = "CENTER", wrap = "UP" } } } },
	{ key = "Compact", title = "Compact", desc = "Small 36 px icons with 2 px gaps for a tight center.",
		settings = { zoom = 10, rows = { trinkets = { size = 28, spacing = 2 }, mobility = { size = 28, spacing = 2 } },
			viewers = { essential = { size = 36, spacing = 2, perRow = 10, countdownSize = 13 },
				utility = { size = 28, spacing = 2, perRow = 12, countdownSize = 11 },
				buffIcons = { size = 28, spacing = 2 },
				buffBars = { width = 180, height = 16, spacing = 1 } } } },
	{ key = "Large", title = "Large", desc = "Big 56 px essential icons for a cooldown-centered HUD.",
		settings = { viewers = { essential = { size = 56, spacing = 5, perRow = 7, countdownSize = 20, keybindSize = 14 },
			utility = { size = 40, spacing = 4, perRow = 9 }, buffIcons = { size = 40 } } } },
	{ mode = true, key = "Combat", title = "Combat only", desc = "The viewers fade out of combat unless you have a hostile target or mouse over them.",
		settings = { viewers = { essential = { fade = { show = "combatOrTarget", fadedAlpha = 0 } },
			utility = { fade = { show = "combatOrTarget", fadedAlpha = 0 } }, buffIcons = { fade = { show = "combat" } },
			buffBars = { fade = { show = "combat" } } } } },
	-- Cooldown groups (CooldownGroups.lua): how EldoUI's own icons are
	-- arranged. The groups' own growth is set by M.GROUP_STYLES there.
	-- mode = true: a switch between the fixed rows and own groups, not a
	-- look, so on a fresh profile it may equal another preset (Centered
	-- groups has the Centered look with own groups on).
	{ key = "FixedRows", title = "Fixed rows (own groups off)", desc = "Turns your own groups off: EldoUI's own icons go back to the fixed rows (Main, Utility, Trinkets, Mobility, Items). Your groups are kept for later.",
		mode = true, settings = { cdgroups = { enabled = false } } },
	{ mode = true, key = "CenteredGroups", title = "Centered groups", desc = "Own groups on; every group and row lines its icons up from the center.",
		settings = { cdgroups = { enabled = true },
			viewers = { essential = { growth = "CENTER", wrap = "DOWN" }, utility = { growth = "CENTER", wrap = "DOWN" } } } },
	{ key = "LeftGroups", title = "Left groups", desc = "Own groups on; every group and row starts at the left edge of its mover and grows to the right.",
		settings = { cdgroups = { enabled = true },
			viewers = { essential = { growth = "RIGHT", wrap = "DOWN" }, utility = { growth = "RIGHT", wrap = "DOWN" } },
			rows = { trinkets = { side = "BOTTOM" }, mobility = { side = "BOTTOM" } } } },
}, { restores = {
	"viewers.essential.fade", "viewers.utility.fade", "viewers.buffIcons.fade", "viewers.buffBars.fade"
} })
