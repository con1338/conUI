-- A player-selected mana display. Unit amounts go directly to presentation
-- setters. Membership and order only use readable group identity.
local _, E = ...
local L, M = E.L, E.modules.RaidTools
local Secret = E.Secret
local HEALER_CLASS = { PRIEST = true, DRUID = true, PALADIN = true, SHAMAN = true }
local POWER = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
local GAP = 4
local roster, selection, rows = {}, {}, {}
local composition, settingsOwner
local events

M.defaults.healerMana = {
	enabled = false, party = false, manual = false,
	width = 200, rowHeight = 24, columns = 1,
	range = { enabled = true, alpha = 0.45 },
	selection = {},
	fade = E:VisibilityDefaults(),
}
E:RegisterVisibilityFacet("EldoUI_HealerMana", "rules", { module = "RaidTools", setting = "healerMana.fade" })

local function Settings()
	return M.db and M.db.healerMana
end

local function PlainRead(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, value = pcall(fn, ...)
	if ok and not Secret(value) then return value end
end

local function Identity(unit)
	local guid = PlainRead(UnitGUID, unit)
	if type(guid) == "string" and guid ~= "" then return guid end
end

local function Current(row)
	return row.guid and Identity(row.unit) == row.guid
end

local function StillBound(row, unit, guid)
	if row.unit ~= unit or row.guid ~= guid then return false end
	if Identity(unit) ~= guid then
		row.unit, row.guid = nil, nil
		row:Hide()
		return false
	end
	return true
end

local function WantedGroup()
	local db = Settings()
	local raid = PlainRead(IsInRaid)
	if raid == true then return true end
	if raid ~= false then return nil end
	if not (db and db.party) then return false end
	local grouped = PlainRead(IsInGroup)
	if type(grouped) == "boolean" then return grouped end
end

local function ReadRoster()
	local result, seen = {}, {}
	local wanted = WantedGroup()
	if wanted == nil then return nil end
	if not wanted then return result end
	local raid = PlainRead(IsInRaid) == true
	local count = PlainRead(GetNumGroupMembers)
	if type(count) ~= "number" or count < 0 or count > 40 or count % 1 ~= 0 then return nil end
	for index = 1, math.min(40, count) do
		local unit = raid and "raid" .. index or (index == count and "player" or "party" .. index)
		local guid = Identity(unit)
		local name = PlainRead(UnitName, unit)
		local class
		if type(UnitClass) == "function" then
			local ok, _, value = pcall(UnitClass, unit)
			if ok and not Secret(value) then class = value end
		end
		local group = 1
		if raid and GetRaidRosterInfo then
			local ok, _, _, value = pcall(GetRaidRosterInfo, index)
			if not ok or Secret(value) or type(value) ~= "number" then return nil end
			group = value
		end
		if guid and not seen[guid] and type(name) == "string" and not Secret(class) and type(class) == "string" then
			seen[guid] = true
			result[#result + 1] = { unit = unit, guid = guid, name = name, class = class, group = group }
		else return nil end
	end
	table.sort(result, function(a, b)
		if a.group ~= b.group then return a.group < b.group end
		if a.name ~= b.name then return a.name < b.name end
		return a.guid < b.guid
	end)
	return result
end

local function RefreshRoster()
	local current = ReadRoster()
	if not current then return false end
	roster = current
	local ids = {}
	for _, entry in ipairs(roster) do ids[#ids + 1] = entry.guid end
	table.sort(ids)
	local key = table.concat(ids, "\n")
	if key ~= composition then
		local saved = Settings().selection
		local previous = type(saved) == "table" and saved.composition == key and type(saved.members) == "table" and saved.members or {}
		selection = {}
		for _, entry in ipairs(roster) do
			if type(previous[entry.guid]) == "boolean" then selection[entry.guid] = previous[entry.guid] end
		end
		composition = key
		Settings().selection = { composition = key, members = selection }
	end
	return true
end

local function DisplayName(entry)
	return E:DisplayName(entry.unit, "healerMana")
end

function M:RefreshHealerManaRow(row)
	local unit, guid = row.unit, row.guid
	if not Current(row) then
		row.unit, row.guid = nil, nil
		row:Hide()
		return
	end
	local name = DisplayName(row)
	local connected = PlainRead(UnitIsConnected, unit)
	local dead = PlainRead(UnitIsDeadOrGhost, unit)
	if not StillBound(row, unit, guid) then return end
	row.name:SetText(name)
	row.status:SetAlpha((connected == false or dead == true) and 0.4 or 1)
	E:UnitFXRange(row.range, row.unit, Settings().range)
	if connected == false or dead == true then
		row.bar:SetMinMaxValues(0, 1)
		row.bar:SetValue(0)
		row.amount:SetText(connected == false and L["Offline"] or L["Dead"])
	elseif type(UnitPower) == "function" and type(UnitPowerMax) == "function" then
		local ok, value = pcall(UnitPower, unit, POWER)
		local maxOK, maximum = pcall(UnitPowerMax, unit, POWER)
		if not StillBound(row, unit, guid) then return end
		if ok and maxOK and type(value) ~= "nil" and type(maximum) ~= "nil" then
			row.bar:SetMinMaxValues(0, maximum)
			row.bar:SetValue(value)
			row.amount:SetText(E.TagShort(value))
		else
			row.bar:SetMinMaxValues(0, 1)
			row.bar:SetValue(0)
			row.amount:SetText(L["Unavailable"])
		end
	else
		row.bar:SetMinMaxValues(0, 1)
		row.bar:SetValue(0)
		row.amount:SetText(L["Unavailable"])
	end
end

local function MakeRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row.range = CreateFrame("Frame", nil, row)
	row.range:SetAllPoints()
	row.status = CreateFrame("Frame", nil, row.range)
	row.status:SetAllPoints()
	E:SetTemplate(row.status)
	row.bar = CreateFrame("StatusBar", nil, row.status)
	row.bar:SetPoint("TOPLEFT", 1, -1)
	row.bar:SetPoint("BOTTOMRIGHT", -1, 1)
	row.bar:SetStatusBarTexture(E.media.blank)
	row.bar:SetStatusBarColor(E:GetPowerColor("MANA"))
	row.text = CreateFrame("Frame", nil, row.status)
	row.text:SetAllPoints()
	row.text:SetFrameLevel(row.bar:GetFrameLevel() + 1)
	row.amount = E:CreateText(row.text, E.tokens.size.small, "RIGHT")
	row.amount:SetPoint("RIGHT", -5, 0)
	row.amount:SetWidth(64)
	row.name = E:CreateText(row.text, E.tokens.size.small, "LEFT")
	row.name:SetPoint("LEFT", 5, 0)
	row.name:SetPoint("RIGHT", row.amount, "LEFT", -6, 0)
	row:EnableMouse(false)
	return row
end

local function CreateDisplay()
	if M.healerMana then return M.healerMana end
	local frame = CreateFrame("Frame", "EldoUI_HealerManaFrame", UIParent)
	frame:SetSize(200, 24)
	frame:SetClampedToScreen(true)
	frame:Hide()
	M.healerMana = frame
	E:CreateMover(frame, "EldoUI_HealerMana", L["Healer mana"],
		{ "TOPLEFT", "EldoUI_RaidToolsMover", "TOPRIGHT", 12, 0 },
		{ enabledPath = { "healerMana", "enabled" } })
	return frame
end

local function RefreshRows(unit)
	if not WantedGroup() then
		if M.healerMana then M.healerMana:Hide() end
		return
	end
	for _, row in ipairs(rows) do
		if row.unit and (not unit or row.unit == unit) then M:RefreshHealerManaRow(row) end
	end
end

function M:BuildHealerMana()
	if InCombatLockdown() then return end
	local db = Settings()
	if not self.active or not db or not db.enabled then return end
	if not RefreshRoster() then
		if self.healerMana then
			self.healerMana:Hide()
			E.Ticker:Unsubscribe(self.healerMana)
		end
		return
	end
	local frame = CreateDisplay()
	local selected = {}
	for _, entry in ipairs(roster) do
		local wanted = selection[entry.guid]
		if wanted == nil then wanted = not db.manual and HEALER_CLASS[entry.class] == true end
		if wanted then selected[#selected + 1] = entry end
	end
	local width = math.max(140, math.min(320, tonumber(db.width) or 200))
	local height = math.max(18, math.min(36, tonumber(db.rowHeight) or 24), E.tokens.size.small * E:TextScale() + 6)
	local columns = math.max(1, math.min(4, math.floor(tonumber(db.columns) or 1)))
	local screenRows = math.max(1, math.floor((UIParent:GetHeight() - 48) / (height + GAP)))
	columns = math.max(columns, math.ceil(#selected / screenRows))
	local perColumn = math.max(1, math.ceil(#selected / columns))
	local shownColumns = math.max(1, math.min(columns, #selected))
	frame:SetSize(shownColumns * (width + GAP) - GAP, perColumn * (height + GAP) - GAP)
	for index, entry in ipairs(selected) do
		local row = rows[index]
		if not row then row = MakeRow(frame) rows[index] = row end
		row.unit, row.guid, row.class = entry.unit, entry.guid, entry.class
		row:SetSize(width, height)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", math.floor((index - 1) / perColumn) * (width + GAP), -((index - 1) % perColumn) * (height + GAP))
		E:SetTemplate(row.status)
		row.bar:SetStatusBarColor(E:GetPowerColor("MANA"))
		E:SetFont(row.name, E.tokens.size.small)
		E:SetFont(row.amount, E.tokens.size.small)
		row.name:SetTextColor(E:GetClassColor(entry.class))
		row:Show()
		self:RefreshHealerManaRow(row)
	end
	for index = #selected + 1, #rows do
		rows[index].unit, rows[index].guid = nil, nil
		rows[index]:Hide()
	end
	self.healerManaRows = rows
	E:DetachVisibility(frame)
	if #selected > 0 then
		frame:Show()
		E:AttachVisibility(frame, db.fade, { module = "RaidTools", restoreShown = false })
	else frame:Hide() end
	E:ApplyMover("EldoUI_HealerMana")
	if #selected == 0 then
		E.Ticker:Unsubscribe(frame)
	elseif not E.Ticker:IsSubscribed(frame) then
		E.Ticker:Subscribe(frame, 0.5, function() RefreshRows() end, self)
	end
end

local function RosterChanged()
	-- In combat a reused token loses its old row immediately. New bindings
	-- wait for the next out-of-combat snapshot, including any manual picks.
	if InCombatLockdown() then RefreshRows() else M:BuildHealerMana() end
end

function M:StopHealerMana(keepSelection)
	if events then events:UnregisterAllEvents() end
	if self.healerMana then
		E.Ticker:Unsubscribe(self.healerMana)
		E:DetachVisibility(self.healerMana)
		self.healerMana:Hide()
	end
	for _, row in ipairs(rows) do row.unit, row.guid = nil, nil row:Hide() end
	roster = {}
	if not keepSelection then selection, composition = {}, nil end
end

function M:SyncHealerMana()
	self:StopHealerMana(true)
	local db = Settings()
	if settingsOwner ~= db then selection, composition, settingsOwner = {}, nil, db end
	if not self.active or not db or not db.enabled then
		selection, composition = {}, nil
		return
	end
	if not events then
		events = CreateFrame("Frame")
		events:SetScript("OnEvent", function(_, event, unit)
			if event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
				if not Secret(unit) and type(unit) == "string" then RefreshRows(unit) end
			elseif event == "UNIT_NAME_UPDATE" then
				if Secret(unit) or type(unit) ~= "string" then return end
				local kind, digits = unit:match("^(%a+)(%d+)$")
				local index = tonumber(digits)
				if unit == "player" or (kind == "party" and index and index >= 1 and index <= 4)
					or (kind == "raid" and index and index >= 1 and index <= 40) then RosterChanged() end
			elseif event == "UNIT_CONNECTION" or event == "UNIT_FLAGS" then
				if not Secret(unit) and type(unit) == "string" then RefreshRows(unit) end
			else RosterChanged() end
		end)
	end
	for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
		"UNIT_NAME_UPDATE", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_CONNECTION", "UNIT_FLAGS" }) do
		events:RegisterEvent(event)
	end
	if not InCombatLockdown() then self:BuildHealerMana() end
end

function M:ChooseHealerMana(owner)
	if InCombatLockdown() then return E:Print(L["After combat."]) end
	if not RefreshRoster() then return end
	local db = Settings()
	E.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(L["Choose healers"])
		if #roster == 0 then root:CreateTitle(L["Join a group to choose healers."]) end
		for _, member in ipairs(roster) do
			local entry, key = member, composition
			root:CreateCheckbox(DisplayName(entry), function()
				local picked = selection[entry.guid]
				if picked ~= nil then return picked end
				return not db.manual and HEALER_CLASS[entry.class] == true
			end, function()
				if InCombatLockdown() or db ~= Settings() or key ~= composition or not Current(entry) then return end
				local picked = selection[entry.guid]
				if picked == nil then picked = not db.manual and HEALER_CLASS[entry.class] == true end
				selection[entry.guid] = not picked
				M:BuildHealerMana()
			end)
		end
	end)
end

E:RegisterNameFormatUser("healerMana", { title = "Healer mana", order = 35,
	refresh = function() if M.healerMana then RefreshRows() end end })

local options = {
	{ type = "tab", label = "Healer mana" },
	{ type = "toggle", key = "healerMana.enabled", label = "Healer mana", desc = "Show a separate mana list for the healers in your raid." },
	{ type = "toggle", key = "healerMana.party", label = "Also in parties", desc = "Show the healer mana list in a party as well as a raid." },
	{ type = "toggle", key = "healerMana.manual", label = "Only chosen healers", desc = "Use only the members you choose. Otherwise priests, druids, paladins and shamans are included." },
	{ type = "execute", label = "Choose healers", desc = "Include or exclude members of this group. Choices reset when the group membership changes.", func = function(button) M:ChooseHealerMana(button) end },
	{ type = "range", key = "healerMana.width", label = "Row width", desc = "Width of each healer row.", min = 140, max = 320, step = 1, unit = "px" },
	{ type = "range", key = "healerMana.rowHeight", label = "Row height", desc = "Height of each healer row. Large text can increase the minimum.", min = 18, max = 36, step = 1, unit = "px" },
	{ type = "range", key = "healerMana.columns", label = "Columns", desc = "Number of healer columns. More columns are used if the list would exceed the screen height.", min = 1, max = 4, step = 1 },
	{ type = "toggle", key = "healerMana.range.enabled", label = "Fade out of range", desc = "Dim healers outside the game's group range." },
	{ type = "range", key = "healerMana.range.alpha", label = "Out of range opacity", desc = "Visibility of healer rows outside the game's group range.", min = 0.1, max = 1, step = 0.05, percent = true },
}
for _, row in ipairs(E:VisibilityOptions("healerMana.fade", { db = function() return M.db end })) do options[#options + 1] = row end
for _, row in ipairs(options) do M.options[#M.options + 1] = row end

E:OnThemeChanged("healerMana", function()
	if InCombatLockdown() then
		E:RunOutOfCombat(function() M:BuildHealerMana() end, "healerMana:theme")
	else M:BuildHealerMana() end
end)
