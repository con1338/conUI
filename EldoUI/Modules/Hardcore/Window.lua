-- EldoUI Hardcore: the death log window. A UIKit window on its own
-- mover (EldoUI_DeathLog, top center): filter chips (all, guild, group,
-- you), a search box, Clear log, and one row per death (time, name, level,
-- zone, cause, where it came from). A row's tooltip shows the game's own
-- line; a click does nothing else.
local _, E = ...
local L = E.L
local Kit = E.UIKit
local M = E.Hardcore

local MOVER = "EldoUI_DeathLog"
local SIZE = { 520, 340 }
local POINT = { "TOP", "UIParent", "TOP", 0, -132 }

local function Grey(text) return E:TokenHex(Kit.SECONDARY) .. text .. "|r" end

local SOURCE_TEXT = { game = "Game", guild = "Guild note", both = "Game and note" }
local REL_TEXT = { self = "You", group = "Group", guild = "Guild", realm = "Realm" }

local function TimeText(t)
	if type(t) ~= "number" then return "" end
	return E:When(t)
end

local function NameText(entry)
	local name = entry.name or "?"
	if M.db.classColors and entry.class then return E:WrapClassColor(entry.class, name) end
	return name
end

function M:Columns()
	return {
		{ key = "t", title = L["Time"], width = 64, value = function(entry) return entry.t or 0 end,
			text = function(entry) return Grey(TimeText(entry.t)) end },
		{ key = "name", title = L["Name"], width = 110, value = function(entry) return entry.name or "" end, text = NameText },
		{ key = "level", title = L["Level"], width = 44, align = "RIGHT", value = function(entry) return entry.level or 0 end,
			text = function(entry) return entry.level and tostring(entry.level) or Grey("?") end },
		{ key = "zone", title = L["Zone"], width = 120, value = function(entry) return entry.zone or "" end,
			text = function(entry) return entry.zone or Grey(L["unknown"]) end },
		{ key = "cause", title = L["Cause"], value = function(entry) return M.CauseText(entry) end,
			text = function(entry)
				local cause = M.CauseText(entry)
				return cause ~= "" and cause or Grey(L["not given"])
			end },
		{ key = "rel", title = L["Who"], width = 58, value = function(entry) return entry.rel or "" end,
			text = function(entry) return L[REL_TEXT[entry.rel] or "Realm"] end,
			desc = L["You, a group member, a guild member, or anyone else on the realm."] },
	}
end

local filteredCache, statisticsCache, zoneCache
local zoneNotices = {}
local zoneNoticeKey

local function ReadableEntry(entry)
	return not E.Secret(entry) and type(entry) == "table" and (not canaccesstable or canaccesstable(entry))
end

function M.PublicLevel(value)
	if not E.Secret(value) and type(value) == "number" and value >= 1 and value <= 1000 and value % 1 == 0 then return value end
end

function M:StatisticsLevel()
	return M.PublicLevel(self.observedLevel) or M.PublicLevel(E.PlainCall(UnitLevel, "player"))
end

function M:InvalidateDeathStatistics()
	self.deathLogRevision = (self.deathLogRevision or 0) + 1
	filteredCache, statisticsCache, zoneCache = nil, nil, nil
end

-- The same cached rows feed the list and statistics, newest first.
function M:FilteredLog()
	local filter = self.filter or "all"
	local query = self.query and E:FoldText(self.query) or ""
	local level = self:StatisticsLevel()
	local near = self.nearLevel == true
	local list, revision, language = self:Log(), self.deathLogRevision or 0, E:GetLanguage()
	if filteredCache and filteredCache.list == list and filteredCache.count == #list
		and filteredCache.revision == revision and filteredCache.filter == filter and filteredCache.query == query
		and filteredCache.near == near and filteredCache.level == level and filteredCache.language == language then
		return filteredCache.rows
	end
	local rows = {}
	for index = #list, 1, -1 do
		local entry = list[index]
		local readable = ReadableEntry(entry)
		local pass = readable and (filter == "all" or entry.rel == filter
			or (filter == "guild" and entry.source ~= "game" and entry.rel ~= "self"))
		if pass and near then
			local ownLevel = M.PublicLevel(entry.level)
			pass = level ~= nil and ownLevel ~= nil and math.abs(ownLevel - level) <= 3
		end
		if pass and query ~= "" then
			local hay = E:FoldText((entry.name or "") .. " " .. (entry.zone or "") .. " " .. M.CauseText(entry))
			pass = hay:find(query, 1, true) ~= nil
		end
		if pass then rows[#rows + 1] = entry end
	end
	filteredCache = { list = list, count = #list, revision = revision, filter = filter, query = query,
		near = near, level = level, language = language, rows = rows }
	return rows
end

local function KnownText(value)
	if not E.Secret(value) and type(value) == "string" and value:find("%S") then return value end
	return L["not given"]
end

local function AddGroup(groups, name, cause)
	local group = groups[name]
	if not group then group = { name = name, count = 0, causes = {} } groups[name] = group end
	group.count = group.count + 1
	if cause then group.causes[cause] = (group.causes[cause] or 0) + 1 end
end

local function GroupRows(groups, limit)
	local rows = {}
	for _, group in pairs(groups) do
		local best, most = nil, 0
		for cause, count in pairs(group.causes) do
			if count > most or (count == most and (not best or cause < best)) then best, most = cause, count end
		end
		group.cause = best
		rows[#rows + 1] = group
	end
	table.sort(rows, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.name < b.name
	end)
	while #rows > limit do table.remove(rows) end
	return rows
end

function M:DeathStatistics()
	local rows = self:FilteredLog()
	if statisticsCache and statisticsCache.rows == rows then return statisticsCache end
	local zones, causes, bands = {}, {}, {}
	for _, entry in ipairs(rows) do
		local cause = KnownText(M.CauseText(entry))
		AddGroup(zones, KnownText(entry.zone), cause)
		AddGroup(causes, cause)
		local level = M.PublicLevel(entry.level)
		local band = level and math.floor((level - 1) / 10) * 10 + 1 or 0
		bands[band] = (bands[band] or 0) + 1
	end
	local level = self:StatisticsLevel()
	local current = level and math.floor((level - 1) / 10) * 10 + 1
	local bandRows = {}
	for start, count in pairs(bands) do
		bandRows[#bandRows + 1] = { first = start, count = count, current = start == current,
			name = start == 0 and L["not given"] or ("%d-%d"):format(start, start + 9) }
	end
	table.sort(bandRows, function(a, b) return a.first < b.first end)
	statisticsCache = { rows = rows, total = #rows, zones = GroupRows(zones, 10), causes = GroupRows(causes, 10), bands = bandRows }
	return statisticsCache
end

function M:ClearZoneNote()
	if zoneNoticeKey then E:DismissAlert(zoneNoticeKey) end
	zoneNoticeKey = nil
end

function M:CheckZoneNote()
	if not self:Live() or not self.db.zoneNote or E.PlainCall(InCombatLockdown) ~= false
		or E.PlainCall(IsInInstance) ~= false or E.PlainCall(UnitAffectingCombat, "player") ~= false then
		self:ClearZoneNote()
		return false
	end
	local zone = E.PlainCall(GetRealZoneText)
	if E.IdentitySecret("player") then self:ClearZoneNote() return false end
	local level, owner = self:StatisticsLevel(), E.PlainCall(UnitGUID, "player")
	if not level or type(zone) ~= "string" or zone == "" or type(owner) ~= "string" or owner == "" then
		self:ClearZoneNote()
		return false
	end
	local key = "hc-zone:" .. owner .. ":" .. zone
	if zoneNoticeKey and zoneNoticeKey ~= key then self:ClearZoneNote() end
	local shown = zoneNotices[owner]
	if shown and shown[zone] then return false end
	local list, revision = self:Log(), self.deathLogRevision or 0
	if not zoneCache or zoneCache.list ~= list or zoneCache.count ~= #list or zoneCache.level ~= level
		or zoneCache.revision ~= revision or zoneCache.language ~= E:GetLanguage() then
		local groups = {}
		for _, entry in ipairs(list) do
			local at = ReadableEntry(entry) and M.PublicLevel(entry.level)
			if at and math.abs(at - level) <= 3 then AddGroup(groups, KnownText(entry.zone), KnownText(M.CauseText(entry))) end
		end
		zoneCache = { list = list, count = #list, level = level, revision = revision,
			language = E:GetLanguage(), groups = {} }
		for _, row in ipairs(GroupRows(groups, math.huge)) do zoneCache.groups[row.name] = row end
	end
	local group = zoneCache.groups[zone]
	if not group or group.count < 10 then return false end
	shown = shown or {}
	zoneNotices[owner] = shown
	local notice = self:PushAlert({ title = L["Deaths near your level"], icon = 237542, key = key,
		text = E:Plural(group.count, "%s: %d death near your level in your log. Most common cause: %s.",
			"%s: %d deaths near your level in your log. Most common cause: %s."):format(zone, group.count, group.cause) })
	if not notice then return false end
	zoneNoticeKey = key
	shown[zone] = true
	return true
end

local function Body(wrap)
	local c = E.tokens.text.body
	return c[1], c[2], c[3], wrap
end

local function RowTooltip(entry)
	GameTooltip:AddLine(NameText(entry))
	if entry.level then GameTooltip:AddLine(L["Level %d"]:format(entry.level), unpack(Kit.SECONDARY)) end
	local cause = M.CauseText(entry)
	if cause ~= "" then GameTooltip:AddLine(cause, Body(true)) end
	if entry.text and not entry.cause then GameTooltip:AddLine(entry.text, Body(true)) end
	GameTooltip:AddLine(L["From: %s"]:format(L[SOURCE_TEXT[entry.source] or "Game"]), unpack(Kit.SECONDARY))
	if type(entry.t) == "number" then GameTooltip:AddLine(E:ShortDate(entry.t), unpack(Kit.SECONDARY)) end
end

local function CreateTab(content)
	local frame = CreateFrame("Frame", nil, content)
	frame:SetAllPoints()
	frame.toolbar = CreateFrame("Frame", nil, frame)
	frame.toolbar:SetPoint("TOPLEFT")
	frame.toolbar:SetPoint("TOPRIGHT")
	frame.toolbar:SetHeight(E.tokens.height.button * 2 + 8)
	frame.chips = Kit.ChipBar(frame.toolbar, {
		chips = {
			{ "all", L["All"], L["Every death in the log."] },
			{ "guild", L["Guild"], L["Guild members, also those who told the guild themselves."] },
			{ "group", L["Group"], L["Members of your party or raid."] },
			{ "self", L["You"], L["Your own deaths."] },
		},
		selected = M.filter or "all",
		onChange = function(selected)
			M.filter = next(selected) or "all"
			M:RefreshWindow()
		end,
	})
	frame.chips:SetPoint("TOPLEFT", 0, 0)
	frame.clear = Kit.Button(frame.toolbar, L["Clear log"], 90, nil, function(button)
		if button.armed then
			button.armed = nil
			button:SetText(L["Clear log"])
			M:ClearLog()
		else
			button.armed = true
			button:SetText(L["Click again"])
			C_Timer.After(4, function()
				if button.armed then
					button.armed = nil
					button:SetText(L["Clear log"])
				end
			end)
		end
	end, L["Clear log"], L["Remove every entry from the death log. Click twice to confirm."])
	frame.clear:SetPoint("TOPRIGHT", 0, 0)
	frame.status = Kit.Text(frame.toolbar, E.tokens.size.small, "RIGHT", "secondary")
	frame.status:SetPoint("RIGHT", frame.clear, "LEFT", -8, 0)
	frame.status:SetPoint("LEFT", frame.chips, "RIGHT", 8, 0)
	frame.view = Kit.ChipBar(frame.toolbar, {
		chips = { { "list", L["List"] }, { "statistics", L["Statistics"] } },
		selected = M.deathView or "list",
		onChange = function(selected)
			M.deathView = next(selected) or "list"
			M:RefreshWindow()
		end,
	})
	frame.view:SetPoint("BOTTOMLEFT")
	frame.near = Kit.Check(frame.toolbar, L["Near my level"],
		L["Only deaths within three levels of your character, in both views."], function(on)
			M.nearLevel = on
			M:RefreshWindow()
		end)
	frame.near:SetPoint("LEFT", frame.view, "RIGHT", 18, 0)
	frame:SetScript("OnSizeChanged", function() frame.statsLook = nil M:RefreshWindow() end)
	return frame
end

local function BuildTable(frame)
	if frame.tbl then
		frame.tbl:Hide()
		frame.tbl:SetParent(nil)
		frame.tbl = nil
	end
	local tbl = Kit.CreateTable(frame, M:Columns(), {
		sortKey = "t", sortDown = true, rowHeight = M.db.rowHeight,
		empty = { L["No deaths logged"], L["Deaths the game announces, and deaths guild members tell the guild about, show here."] },
		createRow = function(row)
			row:HookScript("OnEnter", function(own)
				if not own.item then return end
				GameTooltip:SetOwner(own, "ANCHOR_RIGHT")
				RowTooltip(own.item)
				GameTooltip:Show()
			end)
			row:HookScript("OnLeave", GameTooltip_Hide)
		end,
	})
	tbl:SetPoint("TOPLEFT", frame.toolbar, "BOTTOMLEFT", 0, -8)
	tbl:SetPoint("BOTTOMRIGHT")
	frame.tbl = tbl
	frame.rowHeight = M.db.rowHeight
end

local function DrawStatistics(frame, stats)
	if not frame.statistics then
		frame.statistics = Kit.ScrollArea(frame)
		frame.statistics:SetPoint("TOPLEFT", frame.toolbar, "BOTTOMLEFT", 0, -8)
		frame.statistics:SetPoint("BOTTOMRIGHT")
		frame.statRows = {}
	end
	frame.statistics:Update()
	local parent = frame.statistics.child
	local index, y = 0, 0
	local function Line(name, value, count, maximum, heading)
		index = index + 1
		local row = frame.statRows[index]
		if not row then
			row = Kit.ValueRow(parent, { label = "", value = "" })
			row.bar = row:CreateTexture(nil, "BACKGROUND")
			row.bar:SetPoint("BOTTOMLEFT", 0, 1)
			row.bar:SetHeight(3)
			frame.statRows[index] = row
		end
		local height = math.max(E.tokens.height.row, E.tokens.size.body + 12)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
		row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -y)
		row:SetLabel(name)
		row:SetValue(value or "", heading and "accent" or "body")
		local valueWidth = math.max(100, parent:GetWidth() * 0.58)
		row.value:SetWidth(valueWidth)
		row.value:SetWordWrap(true)
		row.label:SetWordWrap(true)
		height = math.max(height, Kit.TextHeight(value or "", valueWidth, E.tokens.size.label) + 10,
			Kit.TextHeight(name, math.max(parent:GetWidth() - valueWidth - 16, 1), E.tokens.size.label) + 10)
		row:SetHeight(height)
		if count and maximum > 0 then
			row.bar:SetColorTexture(E:TokenColor("accent"))
			row.bar:SetWidth(math.max(1, parent:GetWidth() * count / maximum))
			row.bar:Show()
		else row.bar:Hide() end
		row:Show()
		y = y + height + (heading and 4 or 0)
	end
	Line(L["Zones"], "", nil, nil, true)
	for _, row in ipairs(stats.zones) do
		Line(row.name, tostring(row.count) .. " · " .. row.cause, row.count, stats.total)
	end
	Line(L["Level bands"], "", nil, nil, true)
	for _, row in ipairs(stats.bands) do
		local name = row.current and L["%s (you)"]:format(row.name) or row.name
		Line(name, tostring(row.count), row.count, stats.total)
	end
	Line(L["Causes"], "", nil, nil, true)
	for _, row in ipairs(stats.causes) do Line(row.name, tostring(row.count), row.count, stats.total) end
	if stats.total == 0 then Line(L["No deaths logged"], "") end
	for unused = index + 1, #frame.statRows do frame.statRows[unused]:Hide() end
	parent:SetHeight(math.max(y, 1))
	frame.statistics:Update()
end

local function UpdateTab(frame)
	if not frame.tbl or frame.rowHeight ~= M.db.rowHeight then BuildTable(frame) end
	frame.chips:SetSelected(M.filter or "all")
	frame.view:SetSelected(M.deathView or "list")
	frame.near:SetChecked(M.nearLevel == true)
	local rows = M:FilteredLog()
	local statistics = M.deathView == "statistics"
	frame.tbl:SetShown(not statistics)
	if statistics then
		local stats = M:DeathStatistics()
		local width = frame:GetWidth()
		local look = table.concat({ tostring(width), tostring(E.tokens.size.body), tostring(E:ArtStyle()) }, ":")
		if frame.statsSnapshot ~= stats or frame.statsLook ~= look then
			DrawStatistics(frame, stats)
			frame.statsSnapshot, frame.statsLook = stats, look
		end
		frame.statistics:Show()
	elseif frame.statistics then frame.statistics:Hide() end
	if not statistics then frame.tbl:SetData(rows) end
	frame.status:SetText(L["%d of %d"]:format(#rows, #M:Log()))
end

function M:BuildWindow()
	if self.window then return self.window end
	local win = Kit.CreateTabbedWindow({
		name = "EldoUI_DeathLogWindow",
		options = { page = "module:Hardcore" },
		title = L["Death Log"],
		width = SIZE[1], height = SIZE[2],
		transparent = function() return M.db.transparent end,
		search = { onSearch = function(text) M.query = text M:RefreshWindow() end,
			tip = L["Find a name, zone or cause. Press Enter; an empty search shows all."] },
		tabs = {
			{ key = "log", title = L["Deaths"], desc = L["Deaths announced on your realm and told by your guild."],
				create = CreateTab, show = UpdateTab, refresh = UpdateTab },
		},
		help = { text = L["The game announces Hardcore deaths as its own death alert setting allows (guild or all). Guild members who use EldoUI and click Tell the guild add their class and cause. Nothing here is sent anywhere."] },
		footer = function() return M.IsHardcore() and "" or L["Only on a Hardcore character."] end,
	})
	self.window = win
	-- The window sits on its mover; dragging the top bar moves the mover.
	function win.ApplyPosition(own)
		local frame = own.frame
		if not frame then return end
		if not own.mover then own.mover = E:CreateMover(frame, MOVER, L["Death Log"], POINT, { sample = false }) end
		frame:SetScale(own:Scale())
		frame:ClearAllPoints()
		frame:SetPoint("TOP", own.mover, "TOP")
	end
	function win.SavePosition(own)
		local frame, mover = own.frame, own.mover
		if not (frame and mover) then return end
		local left, top = frame:GetLeft(), frame:GetTop()
		if not (left and top) then return end
		local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
		E:SaveMoverFromRect(mover, left * scale, top * scale - mover:GetHeight())
	end
	function win.ResetPosition(own)
		E.db.movers[MOVER] = nil
		E:ApplyMover(MOVER)
		own:ResetSize()
		own:ApplyPosition()
	end
	win:Build()
	if win.mover then win.mover:SetSize(SIZE[1], SIZE[2]) end
	return win
end

function M:ApplyLook()
	local win = self.window
	if not (win and win.frame) then return end
	win:Restyle()
	local tab = win:GetTab("log")
	if tab and tab.frame then tab.frame.statsLook = nil end
	if win:IsOpen() then win:Refresh() end
end

function M:RefreshWindow()
	local win = self.window
	if win and win:IsOpen() then win:Refresh() end
end

function M:IsOpen()
	return self.window ~= nil and self.window:IsOpen()
end

function M:Open()
	if not self.active or InCombatLockdown() then return false end
	return self:BuildWindow():Open("log")
end

function M:Close()
	if self.window then self.window:Close() end
end

function M:Toggle()
	if self:IsOpen() then self:Close() else self:Open() end
end
