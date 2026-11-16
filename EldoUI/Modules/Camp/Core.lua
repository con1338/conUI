-- EldoUI Camp Helper: makes WoW: Forever camps easy to read.
--
--   * Tooltip: hovering a campfire shows its tier, the slots and the features
--     you have seen around it; hovering a feature shows its buff, whether you
--     have it and for how long, and which class buff blocks it.
--   * Camp panel (mover "Camp Panel"): your camp buffs with timers, the
--     shared feature cooldown and the tent lockout. It shows near a fire or
--     while a camp buff is on you.
--   * A warning before Camp Benefits runs out, and a short note when a camp
--     buff is gained.
--   * Announce: one click posts one line about the camp to /say or /party.
--   * Camp finder (Finder.lua, off by default): ask your guild or group for
--     a camp, or share yours, one click at a time; never answered by itself.
--
-- Game facts live in Data.lua.
--
-- Everything here only shows what the game tells the player: the player's
-- own auras and cooldowns, read out of combat, and objects the player
-- hovered. There is no way to list the objects at a camp, so the counter says
-- "seen", never "used". Nothing is done for the player: no sitting, placing,
-- buffing or chatting without a click.
local _, E = ...
local L = E.L
local D = E.CampData

local floor, max = math.floor, math.max

local M = E:NewModule("Camp", {
	title = "Camp Helper",
	category = "Quality of Life",
	desc = "Campfire help for WoW: Forever: what a fire and its features give, your camp buffs with timers, a warning before they run out, and which class buffs block them.",
	frames = { "EldoUI_CampPanel" },
	movers = { "EldoUI_CampPanel" },
	blizzard = {},
	savedKeys = { "profile.modules.Camp", "global.campObjects" },
	optionsPage = "module:Camp",
	presets = { "Always", "Icons", "Quiet", "Standard", "TooltipOnly" },
	reload = false,
	defaults = {
		tooltip = true,        -- camp lines on fire and feature tooltips
		clashMarks = true,     -- name the class buff that blocks a camp buff
		panel = true,
		panelAuto = true,      -- only near a fire or with a camp buff on
		panelIcons = false,    -- icons only, no text rows
		panelScale = 1,
		showCooldown = true,   -- the shared feature cooldown
		showNearby = true,
		warn = true,
		warnMinutes = 5,
		warnSound = "none",
		gainToast = true,
		announceChannel = "SAY",
		finder = false,        -- camp finder: ask and share camps (addon messages)
		finderChannel = "GUILD",
		finderAnswer = "ask",  -- "ask": a toast with a Send button; "never"
	},
})
E.Camp = M

local Clean = E.Plain

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d = pcall(fn, ...)
	if ok then return a, b, c, d end
end

local function Accent()
	local r, g, b = unpack(E.media.accentColor)
	return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

local function Clock(seconds)
	if not seconds then return "" end
	seconds = max(0, floor(seconds + 0.5))
	if seconds >= 3600 then return ("%dh %dm"):format(floor(seconds / 3600), floor(seconds % 3600 / 60)) end
	if seconds >= 60 then return ("%dm"):format(floor(seconds / 60 + 0.5)) end
	return ("%ds"):format(seconds)
end
M.Clock = Clock

---------------------------------------------------------------------------
-- Reading the player's camp auras (out of combat; frozen when secret)
---------------------------------------------------------------------------
local function AurasSecret()
	if InCombatLockdown and InCombatLockdown() then return true end
	local secrets = rawget(_G, "C_Secrets")
	if secrets and secrets.ShouldAurasBeSecret and Try(secrets.ShouldAurasBeSecret) then return true end
	return false
end

-- { expires, duration, points } or nil.
local function ReadAura(spellID)
	local auras = C_UnitAuras
	if not (auras and auras.GetPlayerAuraBySpellID) then return nil end
	local data = Try(auras.GetPlayerAuraBySpellID, spellID)
	if type(data) ~= "table" then return nil end
	local expires, duration = Clean(data.expirationTime), Clean(data.duration)
	return { expires = type(expires) == "number" and expires > 0 and expires or nil,
		duration = type(duration) == "number" and duration or nil }
end

M.state = { auras = {}, frozen = false }

-- Re-read every camp aura. Returns the auras that are new since last time.
function M:ReadState()
	local state = self.state
	if AurasSecret() then
		state.frozen = true
		return {}
	end
	state.frozen = false
	local old, now = state.auras, {}
	now[D.BENEFITS] = ReadAura(D.BENEFITS)
	now[D.WELCOMING] = ReadAura(D.WELCOMING)
	now[D.NEARBY] = ReadAura(D.NEARBY)
	for _, feature in ipairs(D.FEATURES) do now[feature.aura] = ReadAura(feature.aura) end
	local gained = {}
	for id in pairs(now) do
		if not old[id] then gained[#gained + 1] = id end
	end
	state.auras = now
	state.read = true
	return gained
end

function M:HasAura(spellID)
	return self.state.auras[spellID]
end

function M:Remaining(spellID)
	local aura = self.state.auras[spellID]
	if not (aura and aura.expires) then return nil end
	return max(0, aura.expires - GetTime())
end

function M:NearFire()
	return self.state.auras[D.NEARBY] ~= nil
end

function M:AnyCampAura()
	local auras = self.state.auras
	if auras[D.BENEFITS] or auras[D.WELCOMING] then return true end
	for _, feature in ipairs(D.FEATURES) do
		if auras[feature.aura] then return true end
	end
	return false
end

-- A feature spell the player knows (they all share one cooldown), looked up
-- again when the spell book changes.
local function KnownPlaceSpell()
	if M.placeSpell ~= nil then return M.placeSpell or nil end
	M.placeSpell = false
	local book = rawget(_G, "C_SpellBook")
	local isKnown = book and book.IsSpellKnown
	if type(isKnown) ~= "function" then return nil end
	for _, id in ipairs(D.PLACE_SPELLS) do
		if Try(isKnown, id) then
			M.placeSpell = id
			break
		end
	end
	return M.placeSpell or nil
end

-- The shared cooldown on placing a feature (1 h). nil when ready, unknown or
-- not readable. Read out of combat only, through the combat kit's one
-- cooldown source (Modules/CombatHUD/Kit.lua), which gives plain values only.
function M:FeatureCooldown()
	local source = E.CombatKit and E.CombatKit.Cooldowns
	if AurasSecret() or not (source and source.PlainSpellTimes) then return nil end
	local id = KnownPlaceSpell()
	if not id then return nil end
	local start, duration = source.PlainSpellTimes(id)
	if type(start) == "number" and type(duration) == "number" and duration > 2 then
		return max(0, start + duration - GetTime())
	end
	return nil
end

---------------------------------------------------------------------------
-- Clashes: a camp buff and its class buff never stack
---------------------------------------------------------------------------
local nameCache = {}
local function SpellName(id, fallback)
	if nameCache[id] then return nameCache[id] end
	local name = C_Spell and C_Spell.GetSpellName and Clean(Try(C_Spell.GetSpellName, id))
	name = type(name) == "string" and name ~= "" and name or fallback
	nameCache[id] = name
	return name
end

-- Names of the helpful auras on the player (out of combat).
function M:PlayerBuffNames()
	local names = {}
	if AurasSecret() or not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return names end
	for i = 1, 40 do
		local data = Try(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if type(data) ~= "table" then break end
		local name = Clean(data.name)
		if type(name) == "string" then names[name] = true end
	end
	return names
end

-- The class buff on the player that blocks this feature's buff, or nil.
function M:Clash(feature, buffs)
	buffs = buffs or self:PlayerBuffNames()
	for _, entry in ipairs(feature.clash) do
		local name = SpellName(entry[1], entry[2])
		if buffs[name] then return name end
	end
	return nil
end

-- All class buffs that can block the feature, as one line.
function M:ClashNames(feature)
	local list = {}
	for _, entry in ipairs(feature.clash) do list[#list + 1] = SpellName(entry[1], entry[2]) end
	return table.concat(list, ", ")
end

---------------------------------------------------------------------------
-- What the player has seen at camps (hovered objects, own fire casts)
---------------------------------------------------------------------------
M.seen = {}   -- feature key or utility name -> { time, name, tier }
M.fire = nil  -- { tier info, time, mapID, x, y }

local function ObjectEntry(guid)
	guid = Clean(guid)
	if type(guid) ~= "string" then return nil end
	local kind, _, _, _, _, entry = strsplit("-", guid)
	if kind ~= "GameObject" then return nil end
	return tonumber(entry)
end

local function PruneSeen()
	local now = GetTime()
	for key, info in pairs(M.seen) do
		if now - info.time > D.FEATURE_LIFETIME then M.seen[key] = nil end
	end
	if M.fire and now - M.fire.time > D.FIRE_LIFETIME * 1.5 then M.fire = nil end
end

local function PlayerMap()
	local mapID = C_Map and C_Map.GetBestMapForUnit and Clean(Try(C_Map.GetBestMapForUnit, "player"))
	if not mapID then return nil end
	local pos = C_Map.GetPlayerMapPosition and Try(C_Map.GetPlayerMapPosition, mapID, "player")
	if type(pos) ~= "table" or not pos.GetXY then return mapID end
	local x, y = pos:GetXY()
	return mapID, Clean(x), Clean(y)
end

local function LowerSpellName(id)
	local name = C_Spell and C_Spell.GetSpellName and Clean(Try(C_Spell.GetSpellName, id))
	if type(name) == "string" and name ~= "" then return name:lower() end
end

-- Feature names as the client spells them: the name of each placing spell,
-- read from the game in the player's language. Built on first use, again
-- after a miss.
local spellObjects
local function SpellObjects()
	if spellObjects and next(spellObjects) then return spellObjects end
	spellObjects = {}
	for _, feature in ipairs(D.FEATURES) do
		for index, id in ipairs(feature.spells) do
			local name = LowerSpellName(id)
			if name then spellObjects[name] = { feature = feature, tier = D.SpellTier(feature, index) } end
		end
	end
	return spellObjects
end

-- Fire names as the client spells them: each fire kit spell's name.
local fireSpells
local function FireSpells()
	if fireSpells and next(fireSpells) then return fireSpells end
	fireSpells = {}
	for _, fire in ipairs(D.FIRES) do
		local name = LowerSpellName(fire.kit)
		if name then fireSpells[#fireSpells + 1] = { name = name, fire = fire } end
	end
	return fireSpells
end

-- A fire known only by its name (no GUID): the kit spell's name first, the
-- whole name, then a name that holds it or is part of it; the English word last.
local function FireByName(lower)
	local spells = FireSpells()
	for _, spell in ipairs(spells) do
		if spell.name == lower then return true, spell.fire end
	end
	local best, part, parts
	for _, spell in ipairs(spells) do
		if lower:find(spell.name, 1, true) and (not best or #spell.name > #best.name) then best = spell end
		if spell.name:find(lower, 1, true) then part, parts = spell, (parts or 0) + 1 end
	end
	if best then return true, best.fire end
	if part then return true, parts == 1 and part.fire or nil end
	if lower:find("campfire", 1, true) or lower:find("camp fire", 1, true) then
		for _, fire in ipairs(D.FIRES) do
			if lower:find(fire.name:lower(), 1, true) then return true, fire end
		end
		return true, nil
	end
	return false
end

function M:ResetNameCache()
	wipe(nameCache)
	spellObjects, fireSpells = nil, nil
end

-- Entries this account has recognized once: entry -> "feature:key:tier:name"
-- (the English object name when it is known) or "utility:name". Plain numbers
-- and words only.
E:RegisterGlobal("campObjects", {})

-- Rows saved before the data of a feature was corrected (an older version
-- than its RELEARN version) are dropped, so the entry is learned again with
-- the right tier. Older rows without the object's name get it when their
-- tier has only one object.
local function Upgrade(saved)
	if saved.version == D.OBJECTS_VERSION then return end
	local version = tonumber(saved.version) or 0
	for entry, value in pairs(saved) do
		if type(entry) == "number" and type(value) == "string" then
			local kind, key, tier, object = strsplit(":", value)
			local feature = kind == "feature" and D.featureByKey[key]
			tier = tonumber(tier)
			if kind == "feature" and D.RELEARN[key] and version < D.RELEARN[key] then
				saved[entry] = nil
			elseif feature and tier and not object and D.ObjectCount(feature, tier) == 1 then
				saved[entry] = ("%s:%s"):format(value, D.ObjectName(feature, tier))
			end
		end
	end
	saved.version = D.OBJECTS_VERSION
end

local function Learned()
	local saved = E:GetGlobal("campObjects")
	if type(saved) ~= "table" then return nil end
	Upgrade(saved)
	return saved
end

local function FromLearned(entry, name)
	local saved = Learned()
	local value = saved and saved[entry]
	if type(value) ~= "string" then return nil end
	local kind, key, tier, object = strsplit(":", value)
	if kind == "feature" then
		local feature = D.featureByKey[key]
		tier = tonumber(tier)
		if feature and tier and tier >= 1 and tier <= 3 then
			if object == "" then object = nil end
			return "feature", { feature = feature, tier = tier, name = name or object or D.ObjectName(feature, tier) }
		end
	elseif kind == "utility" and key and key ~= "" then
		return "utility", key
	end
	return nil
end

local function Learn(entry, kind, info)
	local saved = entry and Learned()
	if not saved then return end
	if kind == "feature" then
		-- The English object name, when the tooltip showed it.
		local object = info.name and D.featureByObject[info.name:lower()]
		local known = object and object.feature == info.feature and object.tier == info.tier and object.name
		saved[entry] = ("feature:%s:%d"):format(info.feature.key, info.tier) .. (known and (":" .. known) or "")
	elseif kind == "utility" then
		saved[entry] = "utility:" .. info
	end
end

-- name: the tooltip's first line; data: the tooltip data (guid).
-- Returns "fire", fireInfo | "feature", objectInfo | "utility", name | nil.
-- Objects are known by their entry first, so every client language works;
-- names are the fallback, and a name match teaches the entry.
function M:Identify(name, data)
	local entry = type(data) == "table" and ObjectEntry(data.guid)
	if entry and D.fireByEntry[entry] then return "fire", D.fireByEntry[entry] end
	name = Clean(name)
	if type(name) ~= "string" or name == "" then name = nil end
	if entry then
		local known = D.featureByEntry[entry]
		if known then
			return "feature", { feature = known.feature, tier = known.tier, name = name or known.name }
		end
		if D.utilityByEntry[entry] then return "utility", D.utilityByEntry[entry] end
		local kind, info = FromLearned(entry, name)
		if kind then return kind, info end
	end
	if not name then return nil end
	local lower = name:lower()
	local object = D.featureByObject[lower]
	if object then
		Learn(entry, "feature", object)
		return "feature", object
	end
	if D.utilityByObject[lower] then
		Learn(entry, "utility", D.utilityByObject[lower])
		return "utility", D.utilityByObject[lower]
	end
	local spell = SpellObjects()[lower]
	if spell then
		local info = { feature = spell.feature, tier = spell.tier, name = name }
		Learn(entry, "feature", info)
		return "feature", info
	end
	-- A known entry that is no player fire is some other object (a cooking
	-- fire in the world, say), whatever its name.
	if entry then return nil end
	local isFire, fire = FireByName(lower)
	if isFire then return "fire", fire end
	return nil
end

function M:Remember(kind, info, name)
	if kind == "feature" then
		self.seen[info.feature.key] = { time = GetTime(), name = info.name, tier = info.tier }
	elseif kind == "utility" then
		self.seen[info] = { time = GetTime(), name = name or info, utility = true }
	elseif kind == "fire" then
		local fire = self.fire
		if not fire or GetTime() - fire.time > D.FIRE_LIFETIME or (info and fire.info ~= info) then
			local mapID, x, y = PlayerMap()
			self.fire = { info = info or (fire and fire.info), time = GetTime(), mapID = mapID, x = x, y = y }
		elseif info then
			fire.info = info
		end
	end
	self:RefreshPanel()
end

function M:SeenCount()
	PruneSeen()
	local count = 0
	for _ in pairs(self.seen) do count = count + 1 end
	return count
end

---------------------------------------------------------------------------
-- Tooltip section
---------------------------------------------------------------------------
local GOOD, BAD, DIM
E:OnStatusColors(function() GOOD, BAD, DIM = E:TextHex("good"), E:TextHex("bad"), E:TextHex("secondary") end)

function M:FeatureLine(feature, buffs)
	local have = self:HasAura(feature.aura)
	if have then
		local left = self:Remaining(feature.aura)
		return GOOD .. L["You have it"] .. "|r" .. (left and (" " .. DIM .. Clock(left) .. "|r") or "")
	end
	if self.db.clashMarks and not self.state.frozen then
		local clash = self:Clash(feature, buffs)
		if clash then return BAD .. (L["Blocked by %s"]):format(clash) .. "|r" end
	end
	return nil
end

-- A creature's ID from a unit the player hovers or targets: only while the
-- game shows the unit's identity, and only from plain values. When the
-- tooltip names a GUID too, it must be this unit's (a token can point at
-- another unit by the time the tooltip asks).
local function CreatureID(unit, data)
	if type(unit) ~= "string" or E.IdentitySecret(unit) then return nil end
	if E.PlainCall(UnitIsPlayer, unit) then return nil end
	local guid = Clean(Try(UnitGUID, unit))
	local shown = type(data) == "table" and Clean(data.guid)
	if type(guid) == "string" and type(shown) == "string" and guid ~= shown then return nil end
	local id = Clean(Try(UnitCreatureID, unit))
	if type(id) == "number" then return id end
	if type(guid) ~= "string" then return nil end
	local kind, _, _, _, _, field = strsplit("-", guid)
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
	return tonumber(field)
end
M.CreatureID = CreatureID

-- The camp bots are summoned creatures: known by creature ID in every client
-- language, by their English name when the game shows no ID.
function M:IdentifyUnit(unit, data)
	if type(unit) ~= "string" or E.IdentitySecret(unit) then return nil end
	local id = CreatureID(unit, data)
	if id then
		local name = D.utilityByCreature[id]
		if name then return "utility", name end
		return nil
	end
	if E.PlainCall(UnitIsPlayer, unit) then return nil end
	local name = Clean(Try(UnitName, unit))
	local utility = type(name) == "string" and D.utilityByObject[name:lower()]
	for _, object in ipairs(D.UTILITY) do
		if object.creature and object.name == utility then return "utility", utility end
	end
	return nil
end

function M:TooltipUnit(unit, add, data)
	if not (self.active and self.db.tooltip) then return end
	local kind, info = self:IdentifyUnit(unit, data)
	if not kind then return end
	self:TooltipRows(kind, info, Clean(Try(UnitName, unit)), add)
end

function M:TooltipObject(name, add, data)
	if not (self.active and self.db.tooltip) then return end
	local kind, info = self:Identify(name, data)
	if not kind then return end
	self:TooltipRows(kind, info, name, add)
end

function M:TooltipRows(kind, info, name, add)
	self:Remember(kind, info, name)
	if not self.state.frozen then self:ReadState() end
	local buffs = (self.db.clashMarks and not self.state.frozen) and self:PlayerBuffNames() or {}
	if kind == "fire" then
		local slots = info and info.slots
		add(Accent() .. L["Camp"] .. "|r", info and L["%s fire"]:format(info.name) or nil)
		add(L["Features seen"], ("%d / %s"):format(self:SeenCount(), slots or "?"))
		for _, feature in ipairs(D.FEATURES) do
			local seen = self.seen[feature.key]
			if seen then
				local status = self:FeatureLine(feature, buffs) or (GOOD .. L["Sit by the fire"] .. "|r")
				add("  " .. seen.name, status)
			end
		end
		for _, seen in pairs(self.seen) do
			if seen.utility then add("  " .. seen.name, DIM .. L["utility"] .. "|r") end
		end
		local benefits = self:Remaining(D.BENEFITS)
		if benefits then
			add(L["Camp Benefits"], Clock(benefits))
		elseif self:HasAura(D.WELCOMING) then
			add(L["Camp Benefits"], L["starting"])
		end
	elseif kind == "feature" then
		local feature = info.feature
		add(Accent() .. L["Camp feature"] .. "|r", feature.effect)
		local line = self:FeatureLine(feature, buffs)
		if line then add(line) end
		if self.db.clashMarks and #feature.clash > 0 then
			add(DIM .. (L["Does not stack with %s"]):format(self:ClashNames(feature)) .. "|r")
		end
	else
		add(Accent() .. L["Camp feature"] .. "|r", DIM .. L["utility"] .. "|r")
	end
end

function M:RegisterTooltip()
	if self.tooltipRegistered or not E.RegisterTooltipSection then return end
	self.tooltipRegistered = true
	E:RegisterTooltipSection("camp", {
		order = 40,
		title = "Camp",
		desc = "Campfire and camp feature lines: slots, features seen, your camp buffs and clashes.",
		object = function(_, name, add, data) M:TooltipObject(name, add, data) end,
		unit = function(_, unit, add, data) M:TooltipUnit(unit, add, data) end,
	})
end

---------------------------------------------------------------------------
-- Camp panel
---------------------------------------------------------------------------
local ROW_HEIGHT, PANEL_WIDTH, ICON = 16, 200, 22

function M:BuildPanel()
	if self.panel then return end
	local panel = CreateFrame("Frame", "EldoUI_CampPanel", UIParent)
	panel:SetSize(PANEL_WIDTH, 60)
	panel:SetFrameStrata("MEDIUM")
	E:SetTemplate(panel, true)
	panel.title = E:CreateText(panel, E.tokens.size.label, "LEFT")
	panel.title:SetPoint("TOPLEFT", 6, -5)
	panel.rows, panel.icons = {}, {}
	local button = CreateFrame("Button", nil, panel)
	button:SetSize(54, 14)
	button:SetPoint("TOPRIGHT", -4, -4)
	button.text = E:CreateText(button, E.tokens.size.small)
	button.text:SetPoint("CENTER")
	button.text:SetText(L["Announce"])
	E:SetTemplate(button)
	button:SetScript("OnClick", function(b, mouse)
		if E:IsOptionsLinkClick(b, mouse) then return end
		M:Announce()
	end)
	E.UIKit.Tooltip(button, L["Announce this camp"], L["Posts one line with the features you have seen and the free slots."])
	E:BindOptionsLink(button, { page = "module:Camp", key = "announceChannel" })
	panel.announce = button
	-- Camp finder: Share while you know a fire, else Ask.
	local finder = CreateFrame("Button", nil, panel)
	finder:SetSize(54, 14)
	finder:SetPoint("RIGHT", button, "LEFT", -4, 0)
	finder.text = E:CreateText(finder, E.tokens.size.small)
	finder.text:SetPoint("CENTER")
	E:SetTemplate(finder)
	finder:SetScript("OnClick", function(b, mouse)
		if E:IsOptionsLinkClick(b, mouse) then return end
		if M:ShareableFire() then M:FinderShare() else M:FinderAsk() end
	end)
	E.UIKit.Tooltip(finder, nil, function(tip)
		local Kit = E.UIKit
		if M:ShareableFire() then
			Kit.TipTitle(tip, L["Share this camp"])
			Kit.TipText(tip, L["Sends the place and tier of this fire to your guild or group (camp finder settings). Only members who use EldoUI see it."])
		else
			Kit.TipTitle(tip, L["Ask for a camp"])
			Kit.TipText(tip, L["Asks your guild or group for a camp. Members who use EldoUI choose whether to answer."])
		end
	end)
	E:BindOptionsLink(finder, { page = "module:Camp", key = "finder" })
	finder:Hide()
	panel.finder = finder
	panel:Hide()
	self.panel = panel
	E:CreateMover(panel, "EldoUI_CampPanel", L["Camp Panel"], { "TOPRIGHT", "UIParent", "TOPRIGHT", -230, -240 }, { sample = { kind = "panel" } })
	E:RegisterHideable(panel, "EldoUI_CampPanel", { mouse = true })
end

local function Row(panel, index)
	local row = panel.rows[index]
	if row then return row end
	row = CreateFrame("Frame", nil, panel)
	row:SetSize(PANEL_WIDTH - 12, ROW_HEIGHT)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ROW_HEIGHT - 2, ROW_HEIGHT - 2)
	row.icon:SetPoint("LEFT")
	E:TrimIcon(row.icon)
	row.label = E:CreateText(row, E.tokens.size.small, "LEFT")
	row.label:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
	row.value = E:CreateText(row, E.tokens.size.small, "RIGHT")
	row.value:SetPoint("RIGHT")
	row.label:SetPoint("RIGHT", row.value, "LEFT", -4, 0)
	-- A shared camp's row: click for a waypoint.
	row:SetScript("OnMouseUp", function(self)
		if self.find then M:PinFind(self.find) end
	end)
	row:SetScript("OnEnter", function(self)
		if not self.find then return end
		local Kit = E.UIKit
		Kit.AnchorTooltip(self)
		Kit.TipTitle(GameTooltip, M:FindText(self.find))
		Kit.TooltipHint(GameTooltip, { L["Click"], L["a waypoint to this camp"] })
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	panel.rows[index] = row
	return row
end

local function Icon(panel, index)
	local icon = panel.icons[index]
	if icon then return icon end
	icon = CreateFrame("Frame", nil, panel)
	icon:SetSize(ICON, ICON)
	E:SetTemplate(icon)
	icon.tex = icon:CreateTexture(nil, "ARTWORK")
	icon.tex:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	icon.tex:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(icon.tex)
	icon.time = E:CreateText(icon, E.tokens.size.small, "CENTER")
	icon.time:SetPoint("TOP", icon, "BOTTOM", 0, -1)
	panel.icons[index] = icon
	return icon
end

local function SpellIcon(id)
	local icon = C_Spell and C_Spell.GetSpellTexture and Clean(Try(C_Spell.GetSpellTexture, id))
	return icon or 134400
end

-- The rows the panel shows: { icon, label, value, color = text token
-- kind, find = a shared camp }.
function M:PanelRows()
	local rows = {}
	local benefits = self:Remaining(D.BENEFITS)
	if self:HasAura(D.BENEFITS) then
		local warn = benefits and benefits <= self.db.warnMinutes * 60
		rows[#rows + 1] = { SpellIcon(D.BENEFITS), L["Camp Benefits"], Clock(benefits), color = warn and "bad" or "body" }
	elseif self:HasAura(D.WELCOMING) then
		rows[#rows + 1] = { SpellIcon(D.WELCOMING), L["Camp Benefits"], (L["in %s"]):format(Clock(self:Remaining(D.WELCOMING))), color = "body" }
	elseif self:NearFire() then
		rows[#rows + 1] = { SpellIcon(D.NEARBY), L["Sit by the fire"], "", color = "warn" }
	end
	for _, feature in ipairs(D.FEATURES) do
		if not feature.rest and self:HasAura(feature.aura) then
			rows[#rows + 1] = { SpellIcon(feature.aura), feature.effect, Clock(self:Remaining(feature.aura)), color = "body" }
		end
	end
	if self:HasAura(D.BOOSTED) then
		rows[#rows + 1] = { SpellIcon(D.BOOSTED), L["Next tent rest"], Clock(self:Remaining(D.BOOSTED)), color = "secondary" }
	end
	if self.db.showCooldown then
		local cd = self:FeatureCooldown()
		if cd and cd > 0 then rows[#rows + 1] = { 133743, L["Next feature"], Clock(cd), color = "secondary" } end
	end
	if self.db.showNearby and self.fire and self:NearFire() then
		local slots = self.fire.info and self.fire.info.slots
		rows[#rows + 1] = { 135805, L["Features seen"], ("%d / %s"):format(self:SeenCount(), slots or "?"), color = "secondary" }
	end
	if self.FinderRows then
		for _, row in ipairs(self:FinderRows()) do rows[#rows + 1] = row end
	end
	return rows
end

function M:PanelWanted()
	if not (self.active and self.db.panel) then return false end
	if not self.db.panelAuto then return true end
	if E.IsMoveMode and E:IsMoveMode() then return true end
	return self:NearFire() or self:AnyCampAura() or self:HasFinds()
end

-- Shared camps from the camp finder (Finder.lua) are on show.
function M:HasFinds()
	return self.Finds ~= nil and #self:Finds() > 0
end

function M:RefreshPanel()
	local panel = self.panel
	if not panel then return end
	if not self:PanelWanted() then
		panel:Hide()
		return
	end
	panel:SetScale(self.db.panelScale or 1)
	local rows = self:PanelRows()
	panel.title:SetText(Accent() .. L["Camp"] .. "|r" .. (self.state.frozen and (" " .. DIM .. L["(combat)"] .. "|r") or ""))
	panel.announce:SetShown(self.fire ~= nil or self:NearFire())
	local finderOn = self.db.finder and self.FinderShare ~= nil
	panel.finder:SetShown(finderOn)
	if finderOn then
		panel.finder.text:SetText(self:ShareableFire() and L["Share"] or L["Ask"])
		panel.finder:ClearAllPoints()
		if panel.announce:IsShown() then
			panel.finder:SetPoint("RIGHT", panel.announce, "LEFT", -4, 0)
		else
			panel.finder:SetPoint("TOPRIGHT", -4, -4)
		end
	end
	for _, row in ipairs(panel.rows) do row:Hide() end
	for _, icon in ipairs(panel.icons) do icon:Hide() end
	if self.db.panelIcons then
		panel.title:Hide()
		panel.announce:Hide()
		panel.finder:Hide()
		for i, data in ipairs(rows) do
			local icon = Icon(panel, i)
			icon:ClearAllPoints()
			icon:SetPoint("TOPLEFT", 4 + (i - 1) * (ICON + 4), -4)
			icon.tex:SetTexture(data[1])
			icon.time:SetText(data[3])
			icon:Show()
		end
		panel:SetSize(max(1, #rows) * (ICON + 4) + 4, ICON + 18)
		E:SetTemplate(panel, true)
		panel:SetBackdropColor(0, 0, 0, 0)
		panel:SetBackdropBorderColor(0, 0, 0, 0)
		E:SetStyleEdge(panel, false)
	else
		panel.title:Show()
		E:SetTemplate(panel, true)
		E:SetStyleEdge(panel) -- WoW Forever art style frame line
		local y = -22
		if #rows == 0 then rows[1] = { 135805, L["No camp buffs"], "", color = "secondary" } end
		for i, data in ipairs(rows) do
			local row = Row(panel, i)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 6, y)
			row.icon:SetTexture(data[1])
			row.label:SetText(data[2])
			row.label:SetTextColor(E:TokenColor(data.color or "body"))
			row.value:SetText(data[3])
			row.find = data.find
			row:EnableMouse(data.find ~= nil)
			row:Show()
			y = y - ROW_HEIGHT - 1
		end
		panel:SetSize(PANEL_WIDTH, -y + 4)
	end
	panel:Show()
end

---------------------------------------------------------------------------
-- Warnings and notes
---------------------------------------------------------------------------
function M:Tick()
	self:OnGained(self:ReadState())
	self:CheckExpiry()
	self:RefreshPanel()
	self:UpdateTicker()
end

-- Timers run down without an event, so a once-a-second ticker keeps the
-- panel's clocks and the expiry warning going, also with the panel off.
-- It runs only while there is something to time: a camp buff, a fire
-- nearby, Camp Benefits that just ended, or the panel on screen.
function M:TickerWanted()
	if not self.active then return false end
	return self:AnyCampAura() or self:NearFire() or self.hadBenefits or (self.panel and self.panel:IsShown()) or self:HasFinds()
end

function M:UpdateTicker()
	if self:TickerWanted() then
		if not self.ticker and C_Timer and C_Timer.NewTicker then
			self.ticker = C_Timer.NewTicker(1, function() M:Tick() end)
		end
	elseif self.ticker then
		self.ticker:Cancel()
		self.ticker = nil
	end
end

function M:OnGained(gained)
	if not (self.db.gainToast and gained and #gained > 0 and self.initialRead) then
		self.initialRead = true
		return
	end
	for _, id in ipairs(gained) do
		local feature = D.featureByAura[id]
		if feature and not feature.rest then
			M:PushAlert({ key = "camp-gain-" .. id, title = L["Camp buff"], text = feature.effect, icon = SpellIcon(id), duration = 5 })
		elseif id == D.BENEFITS then
			M:PushAlert({ key = "camp-gain-benefits", title = L["Camp Benefits"], text = L["Your camp buffs are active for 1 hour."], icon = SpellIcon(id), duration = 5 })
		end
	end
end

function M:CheckExpiry()
	if not self.db.warn or self.state.frozen then return end
	local left = self:Remaining(D.BENEFITS)
	if left then
		self.hadBenefits = true
		if left <= self.db.warnMinutes * 60 and left > 0 then
			if not self.warned then
				self.warned = true
				M:PushAlert({ key = "camp-expiry", title = L["Camp Benefits"], text = (L["Ends in %s. Sit by a campfire to renew it."]):format(Clock(left)),
					icon = SpellIcon(D.BENEFITS), duration = 10 })
				if self.db.warnSound and self.db.warnSound ~= "none" then E:PlayMedia(self.db.warnSound) end
			end
		else
			self.warned = false
		end
	elseif self.hadBenefits and not self:HasAura(D.WELCOMING) then
		self.hadBenefits, self.warned = false, false
		if self:NearFire() then
			M:PushAlert({ key = "camp-expiry", title = L["Camp Benefits"], text = L["Your camp buffs ended. Sit by the fire to get them back."],
				icon = SpellIcon(D.BENEFITS), duration = 10 })
		end
	end
end

---------------------------------------------------------------------------
-- Announce: one click, one line, to the channel the player picked
---------------------------------------------------------------------------
function M:AnnounceText()
	PruneSeen()
	local names = {}
	for _, feature in ipairs(D.FEATURES) do
		local seen = self.seen[feature.key]
		if seen then names[#names + 1] = seen.name end
	end
	for _, seen in pairs(self.seen) do
		if seen.utility then names[#names + 1] = seen.name end
	end
	table.sort(names)
	local slots = self.fire and self.fire.info and self.fire.info.slots
	local free = slots and max(0, slots - #names)
	local text = L["Camp here"]
	if #names > 0 then text = text .. ": " .. table.concat(names, ", ") end
	if free then text = text .. (" (%d slot%s free)"):format(free, free == 1 and "" or "s") end
	return text
end

function M:Announce()
	local channel = self.db.announceChannel
	if channel == "PARTY" and not (IsInGroup and IsInGroup()) then
		E:Print(L["You are not in a group."])
		return false
	end
	if not E:TryChatPost(self:AnnounceText(), channel) then
		E:Print(E:ChatRefusedText())
		return false
	end
	return true
end

---------------------------------------------------------------------------
-- Events and commands
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit, _, spellID)
	if not M.active then return end
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		spellID = Clean(spellID)
		local fire = spellID and D.fireByKit[spellID]
		if fire then
			wipe(M.seen)
			M.fire = nil
			M:Remember("fire", fire)
		end
		return
	end
	if event == "SPELLS_CHANGED" then
		M.placeSpell = nil
		return
	end
	if event == "UNIT_AURA" and unit ~= "player" then return end
	if event == "PLAYER_REGEN_DISABLED" then
		M.state.frozen = true
		M:RefreshPanel()
		return
	end
	M:Tick()
end)

function M:Status()
	self:ReadState()
	if self.state.frozen then E:Print(L["Camp buffs can't be read in combat."]) return end
	local rows = self:PanelRows()
	if #rows == 0 then E:Print(L["No camp buffs on you."]) return end
	for _, row in ipairs(rows) do E:Print(("%s %s"):format(row[2], row[3])) end
end

function M:Command(arg)
	arg = (arg or ""):lower():match("^%s*(.-)%s*$")
	if arg == "announce" then
		self:Announce()
	elseif arg == "ask" then
		self:FinderAsk()
	elseif arg == "share" then
		self:FinderShare()
	elseif arg == "finds" then
		self:ListFinds()
	elseif arg == "panel" then
		self.db.panel = not self.db.panel
		self:RefreshPanel()
		E:Print(self.db.panel and L["Camp panel on."] or L["Camp panel off."])
	elseif arg == "" or arg == "status" then
		self:Status()
	else
		E:Print(L["/eui camp [status | panel | announce | ask | share | finds]"])
	end
end

E:AddCommand("camp", "[status | panel | announce | ask | share | finds]  campfire buffs, the camp panel, a one-line camp announce and the camp finder", function(arg)
	if M.active then M:Command(arg) else E:Print(E:ModuleOffHint("Camp")) end
end)

-- The object entries this account has learned, one line each, written as
-- the object's record in the camp data, so they can be added for every player.
function M:LearnedLines()
	local saved, keys, lines = Learned(), {}, {}
	for entry in pairs(saved or {}) do
		if type(entry) == "number" then keys[#keys + 1] = entry end
	end
	table.sort(keys)
	for _, entry in ipairs(keys) do
		local value = tostring(saved[entry])
		local kind, key, tier, object = strsplit(":", value)
		if kind == "feature" and tonumber(tier) then
			lines[#lines + 1] = ('{ name = "%s", tier = %d, entry = %d }, -- %s%s'):format(object or "?", tonumber(tier), entry, key,
				object and "" or ", name unknown: hover it on an English client")
		elseif kind == "utility" and key then
			lines[#lines + 1] = ('{ name = "%s", entry = %d }, -- utility'):format(key, entry)
		else
			lines[#lines + 1] = ("-- %d = %s"):format(entry, value)
		end
	end
	return lines
end

E:RegisterProbe("camp", "the camp object entries this account has recognized", function()
	local lines = M:LearnedLines()
	E:Print(("Camp: %d learned object entries"):format(#lines)) -- no-L
	for _, line in ipairs(lines) do print(line) end
end)

function M:OnEnable()
	self:RegisterTooltip()
	self:BuildPanel()
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "SPELLS_CHANGED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	pcall(events.RegisterUnitEvent, events, "UNIT_AURA", "player")
	pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_SUCCEEDED", "player")
	self.initialRead = false
	self:EnableFinder()
	self:Tick()
end

function M:OnDisable()
	events:UnregisterAllEvents()
	E:UnregisterComm(self.FINDER_PREFIX)
	wipe(self.finds)
	if self.ticker then
		self.ticker:Cancel()
		self.ticker = nil
	end
	if self.panel then self.panel:Hide() end
end

function M:OnProfileChanged()
	if self.active then
		self:EnableFinder()
		self:RefreshPanel()
	end
end

---------------------------------------------------------------------------
-- Options and styles
---------------------------------------------------------------------------
M.options = {
	{ type = "description", label = "Camp Helper reads your camp buffs and the campfire objects you hover; \"features seen\" counts the ones you hovered. Also: /eui camp." },
	{ type = "header", label = "Tooltip" },
	{ type = "toggle", key = "tooltip", label = "Camp lines on tooltips", desc = "Hovering a campfire shows its tier, slots and the features you have seen; hovering a feature shows its buff and whether you have it." },
	{ type = "toggle", key = "clashMarks", label = "Class buff clashes", desc = "Name the class buff on you that stops a camp buff (they never stack), e.g. Arcane Intellect and the Incense Candle." },
	{ type = "header", label = "Camp panel" },
	{ type = "toggle", key = "panel", label = "Enable", desc = "A small panel with your camp buffs and their timers. Move it in move mode (Camp Panel)." },
	{ type = "toggle", key = "panelAuto", label = "Only near a camp", desc = "Show the panel only near a campfire or while a camp buff is on you.", dependsOn = "panel" },
	{ type = "toggle", key = "panelIcons", label = "Icons only", desc = "Show the buffs as icons with timers instead of rows.", dependsOn = "panel" },
	{ type = "range", percent = true, key = "panelScale", label = "Scale", min = 0.6, max = 1.6, step = 0.05, desc = "Size of the camp panel.", dependsOn = "panel" },
	{ type = "toggle", key = "showCooldown", label = "Feature cooldown", desc = "Show when you can place your next camp feature (one per hour, shared by all features).", dependsOn = "panel" },
	{ type = "toggle", key = "showNearby", label = "Features seen", desc = "Show how many features you have seen at this camp and the fire's slots.", dependsOn = "panel" },
	{ type = "select", key = "announceChannel", label = "Announce to", values = { SAY = "Say", PARTY = "Party" }, desc = "Where the panel's Announce button posts its one line. It only posts when you click it." },
	{ type = "header", label = "Notes" },
	{ type = "toggle", key = "warn", label = "Warn before Camp Benefits ends", desc = "A note before your camp buffs run out, and one when they end while you are still near a fire." },
	{ type = "range", key = "warnMinutes", label = "Warn this many minutes before", min = 1, max = 15, step = 1, desc = "How early the warning comes.", dependsOn = "warn" },
	{ type = "media", key = "warnSound", label = "Warning sound", mediaKind = "sound", none = true, desc = "A sound with the warning. None for silence.", dependsOn = "warn" },
	{ type = "toggle", key = "gainToast", label = "Note when a camp buff starts", desc = "A short note naming a camp buff when you gain it." },
	{ type = "header", label = "Camp finder" },
	{ type = "toggle", key = "finder", label = "Ask and share camps",
		desc = "Ask your guild or group for a camp and share yours, with members who use EldoUI. Nothing is sent until you click Ask or Share, and nothing is answered for you.",
		cog = {
			{ type = "select", key = "finderChannel", label = "Ask and share with", values = { GUILD = "Guild", GROUP = "Group" }, order = { "GUILD", "GROUP" },
				desc = "Who gets your Ask and Share. A reply to someone who asked always goes to them alone.", hidden = function() return not M.db.finder end },
			{ type = "select", key = "finderAnswer", label = "When someone asks", values = { ask = "Ask me", never = "Never" }, order = { "ask", "never" },
				desc = "Ask me: while you know a fire, a toast lets you send it with one click. Never: requests are ignored.", hidden = function() return not M.db.finder end },
		} },
	{ type = "execute", label = "Ask for a camp", testSafe = true, func = function() M:FinderAsk() end,
		hidden = function() return not M.db.finder end,
		disabled = function() return M.FinderChannelReason and M:FinderChannelReason() or false end,
		desc = "Asks your guild or group for a camp now. Members who use EldoUI choose whether to answer." },
	{ type = "execute", label = "Share this camp", testSafe = true, func = function() M:FinderShare() end,
		hidden = function() return not M.db.finder end,
		disabled = function()
			local reason = M.FinderChannelReason and M:FinderChannelReason()
			if reason then return reason end
			return not M:ShareableFire() and L["Hover a campfire first."]
		end,
		desc = "Sends the place and tier of the fire you last hovered or lit, to your guild or group." },
}

E:RegisterStyles("Camp", {
	{ key = "Standard", title = "Standard", desc = "Tooltip lines, the panel near camps, a warning 5 minutes before the end and gain notes.",
		settings = { tooltip = true, clashMarks = true, panel = true, panelAuto = true, panelIcons = false, warn = true, warnMinutes = 5, gainToast = true } },
	{ key = "Icons", title = "Icons only", desc = "The panel as a row of buff icons with timers.",
		settings = { panel = true, panelIcons = true } },
	{ key = "Always", title = "Always shown", desc = "The panel stays on screen, also away from camps.",
		settings = { panel = true, panelAuto = false } },
	{ key = "Quiet", title = "Quiet", desc = "Tooltip lines and the panel, no notes or warnings.",
		settings = { warn = false, gainToast = false } },
	{ key = "TooltipOnly", title = "Tooltip only", desc = "Just the camp lines on tooltips.",
		settings = { panel = false, warn = false, gainToast = false } },
})
