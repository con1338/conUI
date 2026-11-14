-- EldoUI World Buffs: your world buffs and the time they have left, a
-- warning before one runs out, and who in your group has which.
--
--   * Info Bar block "World buffs": how many you have and the shortest time
--     left; its tooltip lists each one with its time, and in a group the
--     members' world buffs (out of combat).
--   * A local chat line when one of yours has a few minutes left (5 by
--     default, once per buff), never sent to anyone.
--   * Ready Check Report: a "World buffs" column (off by default) with each
--     member's count.
--
-- Which buffs: the world buffs of the classic world (Rallying Cry of the
-- Dragonslayer, Warchief's Blessing, Spirit of Zandalar, Songflower
-- Serenade, Sayge's Dark Fortune and the three Dire Maul tributes). An aura
-- counts by its spell ID or by the name the client gives for one of these
-- IDs, so a client with its own IDs for the same buff, and every language,
-- still matches; the names come from the client, never from EldoUI.
--
-- Rules (Midnight / Forever): auras are read through C_UnitAuras, every
-- read in pcall. Other members' auras only out of combat; a secret aura,
-- name or time is left out, never compared. Times come from the aura's own
-- expiration time; in combat they may be hidden and then show without a
-- time.
local _, E = ...
local L = E.L

local M = E:NewModule("WorldBuffs", {
	title = "World Buffs",
	category = "Group",
	desc = "Your world buffs with the time they have left, a warning before one runs out, and who in your group has which.",
	defaults = {
		warn = true,          -- a chat line before one of yours runs out
		warnMinutes = 5,
		readyColumn = false,  -- a column in the Ready Check Report
	},
})
E.WorldBuffs = M

local Secret = E.Secret
local function Plain(value)
	if Secret(value) then return nil end
	return value
end

---------------------------------------------------------------------------
-- The buffs (spell IDs; names come from the client)
---------------------------------------------------------------------------
M.BUFFS = {
	{ key = "DRAGONSLAYER", spells = { 22888 } },  -- Rallying Cry of the Dragonslayer (Onyxia, Nefarian)
	{ key = "WARCHIEF", spells = { 16609 } },      -- Warchief's Blessing (Rend)
	{ key = "ZANDALAR", spells = { 24425 } },      -- Spirit of Zandalar (Hakkar)
	{ key = "SONGFLOWER", spells = { 15366 } },    -- Songflower Serenade
	{ key = "DARKMOON", spells = { 23735, 23736, 23737, 23738, 23766, 23767, 23768, 23769 } }, -- Sayge's Dark Fortune of ...
	{ key = "FENGUS", spells = { 22817 } },        -- Fengus' Ferocity (Dire Maul)
	{ key = "MOLDAR", spells = { 22818 } },        -- Mol'dar's Moxie (Dire Maul)
	{ key = "SLIPKIK", spells = { 22820 } },       -- Slip'kik's Savvy (Dire Maul)
}

local lookup -- { ids = { [id] = key }, names = { [name] = key } }, built on first use

local function SpellName(id)
	local spell = C_Spell
	if not (spell and spell.GetSpellName) then return nil end
	local ok, name = pcall(spell.GetSpellName, id)
	name = ok and Plain(name) or nil
	if type(name) ~= "string" or name == "" then return nil end
	return name
end

function M.Lookup()
	if lookup then return lookup end
	lookup = { ids = {}, names = {} }
	for _, buff in ipairs(M.BUFFS) do
		for _, id in ipairs(buff.spells) do
			lookup.ids[id] = buff.key
			local name = SpellName(id)
			if name then lookup.names[name] = buff.key end
		end
	end
	return lookup
end

-- Which world buff an aura is (its key), or nil.
function M.Kind(aura)
	local set = M.Lookup()
	local id, name = Plain(aura.spellId), Plain(aura.name)
	if type(id) == "number" and set.ids[id] then return set.ids[id] end
	if type(name) == "string" and set.names[name] then return set.names[name] end
	return nil
end

-- A unit's world buffs: list of { key, name, left (seconds or nil), expires,
-- id }, or nil plus a reason ("combat", "restricted").
function M.Read(unit)
	if unit ~= "player" and InCombatLockdown() then return nil, "combat" end
	local auras = C_UnitAuras
	if not (auras and auras.GetAuraDataByIndex) then return nil, "restricted" end
	local list, now = {}, GetTime()
	for index = 1, 80 do
		local ok, aura = pcall(auras.GetAuraDataByIndex, unit, index, "HELPFUL")
		if not ok or Secret(aura) then return nil, "restricted" end
		if type(aura) ~= "table" then break end
		local key = M.Kind(aura)
		if key then
			local expires = Plain(aura.expirationTime)
			local left = type(expires) == "number" and expires > 0 and math.max(0, expires - now) or nil
			list[#list + 1] = { key = key, name = Plain(aura.name) or key, left = left, expires = expires,
				id = Plain(aura.spellId) }
		end
	end
	table.sort(list, function(a, b) return (a.left or math.huge) < (b.left or math.huge) end)
	return list
end

-- "1h 12m", "14m", "45s".
function M.Duration(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	if seconds >= 3600 then return L["%dh %dm"]:format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)) end
	if seconds >= 60 then return L["%dm"]:format(math.floor(seconds / 60)) end
	return L["%ds"]:format(seconds)
end

---------------------------------------------------------------------------
-- The warning before one of yours runs out
---------------------------------------------------------------------------
M.warned = {} -- "id:expires" -> true, this session

function M:CheckWarnings()
	if not (self.active and self.db.warn) or InCombatLockdown() then return end
	local list = M.Read("player")
	if not list then return end
	local limit = math.max(1, tonumber(self.db.warnMinutes) or 5) * 60
	for _, buff in ipairs(list) do
		if buff.left and buff.left > 0 and buff.left <= limit then
			local key = tostring(buff.id or buff.key) .. ":" .. tostring(buff.expires)
			if not M.warned[key] then
				M.warned[key] = true
				E:Print(L["%s runs out in %s."]:format(buff.name, M.Duration(buff.left)))
			end
		end
	end
end

---------------------------------------------------------------------------
-- Info Bar block
---------------------------------------------------------------------------
local function Grey(text) return E:TextHex("secondary") .. text .. "|r" end

-- The group's other members, as units (the player is listed apart).
function M.GroupUnits()
	local units = {}
	if IsInRaid() then
		for index = 1, GetNumGroupMembers() do
			local unit = "raid" .. index
			if not UnitIsUnit(unit, "player") then units[#units + 1] = unit end
		end
	elseif IsInGroup() then
		for index = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. index end
	end
	return units
end

function M.BlockText()
	if not M.active then return Grey(L["Off"]) end
	local list = M.Read("player")
	if not list or #list == 0 then return Grey("0") end
	local first = list[1]
	if first.left then return ("%d  %s"):format(#list, M.Duration(first.left)) end
	return tostring(#list)
end

function M.BlockTooltip(tooltip)
	if not M.active then
		tooltip:AddLine(L["Off"])
		return
	end
	local list = M.Read("player")
	if not list or #list == 0 then
		tooltip:AddLine(L["You have no world buffs."], 1, 1, 1)
	else
		for _, buff in ipairs(list) do
			E.UIKit.TipPair(tooltip, buff.name, buff.left and M.Duration(buff.left) or "?")
		end
	end
	local units = M.GroupUnits()
	if #units == 0 then return end
	tooltip:AddLine(" ")
	tooltip:AddLine(L["Group"], 1, 0.82, 0)
	if InCombatLockdown() then
		tooltip:AddLine(L["Buffs are read out of combat only."], 0.7, 0.7, 0.7, true)
		return
	end
	local rows = {}
	for _, unit in ipairs(units) do
		local name = Plain(UnitName(unit))
		local buffs, reason = M.Read(unit)
		if type(name) == "string" then rows[#rows + 1] = { name = name, count = buffs and #buffs or nil, reason = reason } end
	end
	table.sort(rows, function(a, b)
		if (a.count or -1) ~= (b.count or -1) then return (a.count or -1) > (b.count or -1) end
		return a.name < b.name
	end)
	for index = 1, math.min(#rows, 15) do
		local row = rows[index]
		E.UIKit.TipPair(tooltip, row.name, row.count and tostring(row.count) or "?")
	end
	if #rows > 15 then tooltip:AddLine(L["+%d more"]:format(#rows - 15), 0.7, 0.7, 0.7) end
end

if E.RegisterDataText then
	E:RegisterDataText("WorldBuffs", {
		title = "World buffs", -- no-L (translated where shown)
		icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
		events = { "UNIT_AURA", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED" },
		poll = true,
		interval = 15,
		text = M.BlockText,
		tooltip = M.BlockTooltip,
	})
end

---------------------------------------------------------------------------
-- Ready Check Report column
---------------------------------------------------------------------------
local report = E:GetModule("ReadyReport")
if report and report.AddColumn then
	report:AddColumn({
		key = "worldbuffs", title = L["World buffs"], width = 60, align = "RIGHT",
		desc = L["How many world buffs the member has (World Buffs module)."],
		shown = function() return M.active and M.db.readyColumn and true or false end,
		value = function(row)
			local list = row.unit and M.Read(row.unit)
			return list and #list or -1
		end,
		text = function(row)
			local list = row.unit and M.Read(row.unit)
			if not list then return Grey("?") end
			return #list > 0 and tostring(#list) or Grey("0")
		end,
	})
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:OnEnable()
	-- Your own auras only: a raid's aura changes never wake this.
	E:RegisterUnitEvent("UNIT_AURA", "player", function() M:CheckWarnings() end, self)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() M:CheckWarnings() end)
	E.Ticker:Subscribe("WorldBuffs:warn", 30, function() M:CheckWarnings() end, self)
	self:CheckWarnings()
end

function M:OnDisable()
	E.Ticker:Unsubscribe("WorldBuffs:warn")
end

M.options = {
	{ type = "description", label = "Your world buffs show in the Info Bar block \"World buffs\" (pick it for a slot on the Info Bar page), with the time each one has left." },
	{ type = "toggle", key = "warn", label = "Warn before one runs out", desc = "One chat line, only for you, when one of your world buffs has this many minutes left." },
	{ type = "range", key = "warnMinutes", label = "Minutes before", min = 1, max = 30, step = 1, hidden = function() return not M.db.warn end,
		desc = "How many minutes before the end the warning comes." },
	{ type = "toggle", key = "readyColumn", label = "Column in the Ready Check Report", desc = "A \"World buffs\" column with each member's count in the Ready Check Report." },
}
