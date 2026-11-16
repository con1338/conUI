-- Nemesis keeps per-character encounters and confirmed opposing-player kills.
local _, E = ...
local L, Kit = E.L, E.UIKit
local Read = E.PlainCall

local M = E:NewModule("Nemesis", {
	title = "Nemesis",
	desc = "Keep a history of opposing players you encounter and your confirmed kills and deaths against them.",
	category = "Combat",
	frames = { "EldoUI_Nemesis" },
	movers = {},
	blizzard = {},
	savedKeys = { "profile.modules.Nemesis", "private.nemesis", "private.nemesisPriority" },
	optionsPage = "module:Nemesis",
	presets = { "Standard", "Compact", "Readable", "SeeThrough", "Focused" },
	reload = false,
	themed = "ApplyLook",
	defaults = { enabled = true, alerts = false, rowHeight = 26, classColors = true, transparent = false, window = {} },
})

local ALERT = "nemesis"
local THRESHOLD, REPEAT = 3, 30
local visible, notified = {}, {}
local noticeGUID, selectedGUID
local activeOwner, activePrivate
E:RegisterPrivate("nemesis", {})
E:RegisterPrivate("nemesisPriority", {})

local function Text(value)
	return not E.Secret(value) and type(value) == "string" and value ~= "" and value or nil
end

local function PlayerGUID(value)
	local guid = Text(value)
	return guid and guid:match("^Player%-%d+%-%x+$") and guid or nil
end

local function Count(value)
	return not E.Secret(value) and type(value) == "number" and value > 0 and value < math.huge and value % 1 == 0 and value or 0
end

local function Qualifies(kills, deaths)
	return kills >= THRESHOLD or deaths >= THRESHOLD
end

local function Owner()
	return PlayerGUID(Read(UnitGUID, "player"))
end

local function Own(namespace, owner, create)
	local store = owner and E:GetPrivate(namespace)
	if not store then return end
	local rows = store[owner]
	if type(rows) == "table" then return rows end
	if create then
		rows = {}
		store[owner] = rows
		return rows
	end
end

local function PlainTable(value)
	return not E.Secret(value) and type(value) == "table"
		and (not canaccesstable or canaccesstable(value))
end

local function Opponent(unit)
	if not Text(unit) or E.IdentitySecret(unit) or Read(UnitIsPlayer, unit) ~= true
		or Read(UnitIsVisible, unit) ~= true then return end
	if unit:match("^nameplate%d+$") then
		local plate = C_NamePlate and Read(C_NamePlate.GetNamePlateForUnit, unit)
		if not plate or E.FrameCheck(plate, "IsForbidden") or Read(plate.IsShown, plate) ~= true then return end
	end
	local mine, theirs = Read(UnitFactionGroup, "player"), Read(UnitFactionGroup, unit)
	if not ((mine == "Alliance" and theirs == "Horde") or (mine == "Horde" and theirs == "Alliance")) then return end
	return PlayerGUID(Read(UnitGUID, unit))
end

local function ReadName(unit)
	local first, last = E.PlainCallEach(UnitNameUnmodified, unit)
	first, last = Text(first), Text(last)
	if first then return first, last end

	first, last = E.PlainCallEach(UnitName, unit)
	first, last = Text(first), Text(last)
	if not first then return end
	local names = Constants and Constants.CharacterNameSeparatorConsts
	local separator = names and names.CHARACTERNAME_SURNAME_SEPARATOR or " "
	local split = first:find(separator, 1, true)
	if split then
		local base, suffix = Text(first:sub(1, split - 1)), Text(first:sub(split + #separator))
		if base and suffix and (not last or suffix == last) then return base, suffix end
	end
	return first, last
end

local function Remember(unit, guid, owner, record)
	local first, surname = ReadName(unit)
	local className, class, classID = E.PlainCallEach(UnitClass, unit)
	local race, _, raceID = E.PlainCallEach(UnitRace, unit)
	classID = Count(classID) > 0 and classID or nil
	raceID = Count(raceID) > 0 and raceID or nil
	class, className, race = Text(class), Text(className), Text(race)
	local region = Text(Read(GetCurrentRegionName))
	local aliasKey = Text(Read(E.UnitNameKey, E, unit, true))
	if Opponent(unit) ~= guid or Owner() ~= owner then return end
	if not first or first == record.first then surname = surname or record.surname end
	local changed = first and (first ~= record.first or surname ~= record.surname)
		or class and class ~= record.class or className and className ~= record.className
		or classID and classID ~= record.classID or race and race ~= record.race
		or raceID and raceID ~= record.raceID or region and region ~= record.region
		or aliasKey and aliasKey ~= record.aliasKey
	if first then record.first, record.surname = first, surname end
	record.class, record.className, record.classID = class or record.class, className or record.className, classID or record.classID
	record.race, record.raceID, record.region = race or record.race, raceID or record.raceID, region or record.region
	record.aliasKey = aliasKey or record.aliasKey
	return true, changed and true or false
end

local function ClassName(record)
	local names = LOCALIZED_CLASS_NAMES_MALE
	local class = record and Text(record.class)
	return class and names and names[class] or (record and Text(record.className))
end

local function RaceName(record)
	local id = record and Count(record.raceID)
	local info = id and id > 0 and C_CreatureInfo and Read(C_CreatureInfo.GetRaceInfo, id)
	return (PlainTable(info) and Text(info.raceName)) or (record and Text(record.race))
end

local function LiveUnit(guid)
	for token, seen in pairs(visible) do
		if seen == guid and Opponent(token) == guid then return token end
	end
end

function M:DisplayName(record, unit)
	if type(record) ~= "table" then return L["Unknown player"], false end
	local streamer = E.modules.Streamer
	local first, surname = Text(record.first), Text(record.surname)
	if streamer and streamer.Streaming() and streamer.db.frames then
		local guid = PlayerGUID(record.guid)
		unit = unit or (guid and LiveUnit(guid))
		local alias = unit and E:NameAlias(unit, "Nemesis")
		if not alias then
			local key = streamer.Key(Text(record.aliasKey) or first)
			alias = streamer:OtherAlias(key, ClassName(record))
		end
		if alias then return alias, true end
	end
	if not first then return L["Unknown player"], false end
	return E:FormatName(first, surname, E:NameFormat("Nemesis")), false
end

function M:IsNameMasked(record)
	local _, masked = self:DisplayName(record)
	return masked
end

local function EligibleArea()
	return Read(IsInInstance) == false and Read(IsOutdoors) == true
end

local function Dismiss()
	if noticeGUID then
		noticeGUID = nil
		E:DismissAlert(ALERT)
	end
end

local function ClearEncounterState()
	Dismiss()
	wipe(visible)
	wipe(notified)
	selectedGUID = nil
	M:ClearModelView()
	M:RefreshArmoryCopy()
end

local function UpdateOwner()
	local owner, private = Owner(), E.private
	if owner == activeOwner and private == activePrivate then return owner end
	activeOwner, activePrivate = owner, private
	ClearEncounterState()
	return owner
end

local function Alertable(guid, unit)
	return EligibleArea() and Opponent(unit) == guid and Read(UnitIsEnemy, "player", unit) == true
		and Read(UnitIsDeadOrGhost, unit) == false
end

local function RevalidateNotice()
	if noticeGUID and not Alertable(noticeGUID, LiveUnit(noticeGUID)) then Dismiss() end
end

function M:TryAlert(guid, unit, record)
	if not self.db.alerts or not Alertable(guid, unit) then return end
	local deaths = Own("pvpDeaths", Owner())
	local killed, died = Count(record.kills), deaths and Count(deaths[guid]) or 0
	if not Qualifies(killed, died) then return end
	local now = Read(GetTime)
	if type(now) ~= "number" then return end
	for saved, at in pairs(notified) do
		if now - at >= REPEAT then notified[saved] = nil end
	end
	if notified[guid] then return end
	notified[guid] = now
	Dismiss()
	noticeGUID = guid
	local shown = self:DisplayName(record, unit)
	self:PushAlert({
		key = ALERT, title = L["Nemesis: %s"]:format(shown),
		text = L["You killed them: %d. They killed you: %d."]:format(killed, died),
		icon = "Interface\\Icons\\Ability_DualWield",
	})
end

function M:RefreshWindow()
	if self.window and self.window:IsOpen() then self.window:Refresh() end
end

function M:OnPvPDeathCountChanged(owner, guid)
	if self.active and PlayerGUID(guid) and Owner() == owner then self:RefreshWindow() end
end

E:RegisterNameFormatUser("Nemesis", {
	title = "Nemesis", order = 70, desc = "Name format in the Nemesis history and alerts.",
	refresh = function()
		Dismiss()
		wipe(notified)
		M:RefreshArmoryCopy()
		M:RefreshWindow()
	end,
})

function M:UpdateSelectedModel(force)
	if not (selectedGUID and self.window and self.window:IsOpen()) then return end
	local rows = Own("nemesis", Owner())
	local record = rows and rows[selectedGUID]
	self:UpdateModel(record, LiveUnit(selectedGUID), force)
end

function M:Visible(unit)
	if not Text(unit) then return end
	local owner = UpdateOwner()
	local guid, old = Opponent(unit), visible[unit]
	visible[unit] = guid
	if old and noticeGUID == old then RevalidateNotice() end
	local changed
	if guid then
		local rows = Own("nemesis", owner, true)
		if rows then
			local record = rows[guid]
			local new = type(record) ~= "table"
			if new then record = { guid = guid } end
			local admitted, updated = Remember(unit, guid, owner, record)
			if admitted then
				changed = new or updated
				rows[guid] = record
				self:TryAlert(guid, unit, record)
			end
		end
	end
	if changed then self:RefreshWindow()
	elseif selectedGUID and (selectedGUID == guid or selectedGUID == old) then self:UpdateSelectedModel() end
end

function M:RemoveVisible(unit)
	if not Text(unit) then return end
	local guid = visible[unit]
	visible[unit] = nil
	if guid and noticeGUID == guid then RevalidateNotice() end
	if guid and selectedGUID == guid then self:UpdateSelectedModel() end
end

function M:OwnKill(attacker, victim)
	local owner, guid = UpdateOwner(), PlayerGUID(victim)
	if not (owner and PlayerGUID(attacker) == owner and guid and guid ~= owner) then return end
	local unit = LiveUnit(guid)
	if not unit then return end
	local rows = Own("nemesis", owner, true)
	if not rows then return end
	local record = rows[guid]
	if type(record) ~= "table" then record = { guid = guid } end
	if not Remember(unit, guid, owner, record) then return end
	record.kills = Count(record.kills) + 1
	rows[guid] = record
	if noticeGUID == guid then Dismiss() end
	self:RefreshWindow()
end

local function PriorityOrder(owner)
	local saved = Own("nemesisPriority", owner)
	local order, ranks = {}, {}
	if PlainTable(saved) then
		for _, item in ipairs(saved) do
			local guid = PlayerGUID(item)
			if guid and guid ~= owner and not ranks[guid] then
				order[#order + 1] = guid
				ranks[guid] = #order
			end
		end
	end
	return order, ranks
end

local function ChangePriority(guid, action)
	local owner = UpdateOwner()
	if not M.active or not owner or guid ~= selectedGUID or not PlayerGUID(guid) or guid == owner then return end
	local store = E:GetPrivate("nemesisPriority")
	if not store then return end
	local order, ranks = PriorityOrder(owner)
	local rank = ranks[guid]
	if action == "toggle" then
		if rank then
			table.remove(order, rank)
		else
			local opponents, deaths = Own("nemesis", owner), Own("pvpDeaths", owner)
			if not (opponents and PlainTable(opponents[guid])) and not (deaths and Count(deaths[guid]) > 0) then return end
			order[#order + 1] = guid
		end
	elseif rank then
		local other = rank + action
		if other < 1 or other > #order then return end
		order[rank], order[other] = order[other], order[rank]
	else
		return
	end
	store[owner] = order
	M:RefreshWindow()
end

function M:Rows(priorityOnly)
	local owner = Owner()
	local opponents, deaths = Own("nemesis", owner) or {}, Own("pvpDeaths", owner) or {}
	local order, ranks = PriorityOrder(owner)
	local rows = {}
	local function Add(guid)
		local record = opponents[guid]
		if not PlainTable(record) then record = nil end
		rows[#rows + 1] = {
			guid = guid, record = record, name = self:DisplayName(record), rank = ranks[guid],
			kills = record and Count(record.kills) or 0, deaths = Count(deaths[guid]),
		}
	end
	if priorityOnly then
		for _, guid in ipairs(order) do Add(guid) end
	else
		for guid, record in pairs(opponents) do
			if PlayerGUID(guid) and PlainTable(record) then Add(guid) end
		end
		for guid, count in pairs(deaths) do
			if PlayerGUID(guid) and not PlainTable(opponents[guid]) and Count(count) > 0 then Add(guid) end
		end
	end
	return rows
end

local function Select(panel, row)
	selectedGUID = row and row.guid or nil
	local record = row and row.record
	local rank = row and row.rank
	panel.name:SetText(row and row.name or L["Select a player"])
	panel.armory:SetEnabled(M:ArmoryURL(record) ~= nil)
	panel.priority:SetText(rank and L["Remove from priority list"] or L["Add to priority list"])
	Kit.RefitButton(panel.priority)
	panel.priority:SetEnabled(row ~= nil)
	if panel.up then
		panel.up:SetEnabled(rank ~= nil and rank > 1)
		panel.down:SetEnabled(rank ~= nil and rank < panel.total)
	end
	M.modelView = panel.model
	M:UpdateModel(record, selectedGUID and LiveUnit(selectedGUID))
end

local function Draw(panel)
	local rows, selected = M:Rows(panel.priorityOnly)
	panel.total = #rows
	for _, row in ipairs(rows) do
		if row.guid == selectedGUID then selected = row break end
	end
	panel.list:SetData(rows)
	Select(panel, selected)
end

local function CreatePanel(parent, priorityOnly)
	local panel = CreateFrame("Frame", nil, parent)
	panel:SetAllPoints()
	panel.priorityOnly = priorityOnly
	local detail = CreateFrame("Frame", nil, panel)
	detail:SetPoint("TOPRIGHT")
	detail:SetPoint("BOTTOMRIGHT")
	detail:SetWidth(190)
	local name = Kit.Text(detail, E.tokens.size.body, "CENTER")
	name:SetPoint("TOPLEFT", 8, -4)
	name:SetPoint("TOPRIGHT", -8, -4)
	panel.name = name
	local button = Kit.Button(detail, L["Copy Armory link"], 178, nil, function()
		local rows = Own("nemesis", Owner())
		M:CopyArmory(rows and rows[selectedGUID])
	end, L["Copy Armory link"], L["Copy a browser link to the selected player."])
	button:SetPoint("BOTTOM", 0, 8)
	panel.armory = button
	local priority = Kit.Button(detail, L["Add to priority list"], 178, nil, function()
		ChangePriority(selectedGUID, "toggle")
	end)
	priority:SetPoint("BOTTOM", button, "TOP", 0, 6)
	panel.priority = priority
	local bottom = priority
	if priorityOnly then
		panel.up = Kit.Button(detail, L["Move up"], 86, nil, function() ChangePriority(selectedGUID, -1) end)
		panel.down = Kit.Button(detail, L["Move down"], 86, nil, function() ChangePriority(selectedGUID, 1) end)
		panel.up:SetPoint("BOTTOMLEFT", priority, "TOPLEFT", 0, 6)
		panel.down:SetPoint("BOTTOMRIGHT", priority, "TOPRIGHT", 0, 6)
		bottom = panel.down
	end
	local model = M:CreateModelView(detail)
	panel.model = model
	model:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -8)
	model:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", 0, 8)
	local columns = {
		{ key = "name", title = L["Name"], text = function(row)
			local class = M.db.classColors and row.record and row.record.class
			local text = class and E:WrapClassColor(class, row.name) or row.name
			local mark = Qualifies(row.kills, row.deaths) and E:TextHex("accent") .. L["Nemesis"] .. "|r"
			return mark and (text .. " · " .. mark) or text
		end },
		{ key = "race", title = L["Race"], width = 122, value = function(row) return RaceName(row.record) end },
		{ key = "class", title = L["Class"], width = 102, value = function(row) return ClassName(row.record) end },
		{ key = "kills", title = L["You killed"], width = 96, align = "RIGHT" },
		{ key = "deaths", title = L["Killed you"], width = 92, align = "RIGHT" },
	}
	local empty = { L["No opposing players recorded"], L["Opposing players appear here after you encounter them."] }
	if priorityOnly then
		table.insert(columns, 1, { key = "rank", title = L["Rank"], width = 64, align = "RIGHT" })
		empty = { L["No priority players"], L["Select a player in History and add them to your priority list."] }
	end
	local list = Kit.CreateTable(panel, columns, {
		sortKey = priorityOnly and "rank" or "name", rowHeight = function() return M.db.rowHeight end, empty = empty,
		onClick = function(row, buttonName) if buttonName == "LeftButton" then Select(panel, row) end end,
	})
	if priorityOnly then
		for index, header in ipairs(list.headerButtons) do
			header:SetScript("OnClick", nil)
			Kit.Tooltip(header, columns[index].title, columns[index].desc)
		end
	end
	list:SetPoint("TOPLEFT")
	list:SetPoint("BOTTOMRIGHT", detail, "BOTTOMLEFT", -8, 0)
	panel.list = list
	return panel
end

function M:Open(tab)
	if not self.active or InCombatLockdown() then return false end
	if not self.window then
		self.window = Kit.CreateTabbedWindow({
			name = "EldoUI_Nemesis", title = L["Nemesis"], width = 944, height = 486,
			options = { page = "module:Nemesis" },
			store = function() return M.db.window end,
			transparent = function() return M.db.transparent end,
			tabs = {
				{ key = "history", title = L["History"], create = CreatePanel, show = Draw, refresh = Draw },
				{ key = "priority", title = L["Priority"], create = function(parent) return CreatePanel(parent, true) end,
					show = Draw, refresh = Draw },
			},
		})
	end
	return self.window:Open(tab)
end

function M:ApplyLook()
	if self.window and self.window.frame then self.window:Restyle() end
	self:RefreshWindow()
end

function M:OnProfileChanged()
	UpdateOwner()
	if not self.db.alerts then
		Dismiss()
		wipe(notified)
	end
	if self.window and self.window:IsOpen() then self.window:ApplyPosition() end
	self:ApplyLook()
end

function M:OnEnable()
	UpdateOwner()
	self:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, _, unit) M:Visible(unit) end)
	self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, _, unit) M:RemoveVisible(unit) end)
	self:RegisterEvent("PLAYER_TARGET_CHANGED", function() M:Visible("target") end)
	self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", function() M:Visible("mouseover") end)
	self:RegisterEvent("PARTY_KILL", function(_, _, attacker, victim) M:OwnKill(attacker, victim) end)
	self:RegisterEvent("UNIT_MODEL_CHANGED", function(_, _, unit)
		if Text(unit) and selectedGUID and visible[unit] == selectedGUID then M:UpdateSelectedModel(true) end
	end)
	local function UnitChanged(_, _, unit)
		if not Text(unit) or not visible[unit] then return end
		RevalidateNotice()
		if visible[unit] == selectedGUID then M:UpdateSelectedModel() end
	end
	self:RegisterEvent("UNIT_FLAGS", UnitChanged)
	self:RegisterEvent("UNIT_FACTION", UnitChanged)
	self:RegisterEvent("UNIT_PHASE", UnitChanged)
	local function Zone()
		RevalidateNotice()
		M:UpdateSelectedModel()
	end
	self:RegisterEvent("ZONE_CHANGED", Zone)
	self:RegisterEvent("ZONE_CHANGED_INDOORS", Zone)
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", Zone)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		UpdateOwner()
		Dismiss()
		wipe(visible)
		M:Visible("target")
		M:Visible("mouseover")
		M:RefreshWindow()
	end)
	self:RegisterEvent("PLAYER_ALIVE", function() M:RefreshWindow() end)
	self:RegisterEvent("PLAYER_UNGHOST", function() M:RefreshWindow() end)
	M:Visible("target")
	M:Visible("mouseover")
end

function M:OnDisable()
	activeOwner, activePrivate = nil, nil
	ClearEncounterState()
	if self.window then self.window:Close() end
end

M.options = {
	{ type = "execute", label = "Open Nemesis", desc = "Show opposing players and your history with them.",
		func = function() M:Open() end, disabled = function()
			if not M.active then return E:ModuleOffNote("Nemesis") end
			if InCombatLockdown() then return L["Opens after combat."] end
		end },
	{ type = "toggle", key = "alerts", label = "Nemesis alerts",
		desc = "Alert outdoors when you see an opposing player after three confirmed kills in either direction. Off by default." },
	{ type = "range", key = "rowHeight", label = "Row height", unit = "px", min = 18, max = 36, step = 2,
		desc = "The height of each row in the history." },
	{ type = "toggle", key = "classColors", label = "Class colors", desc = "Color player names by class in the history." },
	{ type = "toggle", key = "transparent", label = "See-through window", desc = "The window lets the game show through a little. How much: General > Panel opacity." },
}

E:RegisterStyles("Nemesis", {
	{ key = "Standard", title = "Standard", desc = "Class colors and comfortable rows.",
		settings = { rowHeight = 26, classColors = true, transparent = false } },
	{ key = "Compact", title = "Compact", desc = "Shorter rows show more players.",
		settings = { rowHeight = 18, classColors = true, transparent = false } },
	{ key = "Readable", title = "Roomy", desc = "Taller rows give each player more space.",
		settings = { rowHeight = 34, classColors = true, transparent = false } },
	{ key = "SeeThrough", title = "See-through", desc = "Class colors and a see-through window.",
		settings = { rowHeight = 26, classColors = true, transparent = true } },
	{ key = "Focused", title = "Plain names", desc = "Taller rows with one color for all names.",
		settings = { rowHeight = 30, classColors = false, transparent = false } },
})

E:AddCommand("nemesis", "open the Nemesis history", function()
	if M.window and M.window:IsOpen() then M.window:Close() else M:Open() end
end)
