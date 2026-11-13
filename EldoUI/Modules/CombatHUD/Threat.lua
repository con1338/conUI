-- Combat HUD: threat meter (plan §3.17).
-- EldoUI's own small window that lists everyone in your group who is on the
-- threat table of your target (or focus), one bar per player. Off by default.
--
-- This file is the single source of threat data for EldoUI:
--   E:GetThreat(unit, mob)       status, percent, scaledPercent, isTanking, threat
--   E:GetThreatColor(unit, mob)  r, g, b of the game's threat color, or nil
-- Unit frames, group frames, the status-bar stack and the color tags
-- read these instead of calling the API themselves.
--
-- Data rules (Forever / Midnight):
--   * Values come straight from UnitDetailedThreatSituation and
--     UnitThreatSituation, as the game hands them out. Nothing is estimated.
--   * Every value is tested with issecretvalue before any math, compare or
--     sort. A unit whose numbers are secret is left out of the list; if the
--     game makes threat secret everywhere (C_Secrets.ShouldUnitThreatValuesBeSecret),
--     the window says so instead of guessing.
--   * The pull-aggro line uses Blizzard's published rule (110 % in melee,
--     130 % at range) or, on "Automatic", the ratio of the two percentages
--     the game gives for you (raw / scaled), which is that same rule.
--   * The warning only plays a sound and tints your bar; it never acts.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local K = E.CombatKit
local M = E.CombatHUD

local issecret = issecretvalue or function() return false end
local MOVER = "EldoUI_ThreatMeter"
local MAX_ROWS = 10
local HEADER = 18

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
local function Exists(unit)
	local exists = UnitExists(unit)
	if issecret(exists) then return true end
	return exists and true or false
end

local function Hostile(unit)
	local hostile = UnitCanAttack("player", unit)
	if issecret(hostile) then return true end
	return hostile and true or false
end

-- The game's threat for `unit` on `mob` (default: player on target).
-- Returns status (0-3), percent (raw, 100 = the tank's threat), scaled
-- percent (100 = you pull aggro), isTanking and the raw threat value.
-- Any value the game made secret comes back nil. With no detailed values,
-- only the status is returned (when it is readable).
function E:GetThreat(unit, mob)
	unit, mob = unit or "player", mob or "target"
	if not (Exists(unit) and Exists(mob)) then return nil end
	local ok, isTanking, status, scaled, percent, threat = pcall(UnitDetailedThreatSituation, unit, mob)
	if ok and not issecret(status) and status ~= nil then
		if issecret(isTanking) then isTanking = nil end
		if issecret(scaled) then scaled = nil end
		if issecret(percent) then percent = nil end
		if issecret(threat) then threat = nil end
		return status, percent, scaled, isTanking, threat
	end
	local okState, state = pcall(UnitThreatSituation, unit, mob)
	if okState and not issecret(state) and state ~= nil then return state end
	return nil
end

-- Color of the game's threat status (yellow, orange, red), or nil when
-- there is none to show.
function E:GetThreatColor(unit, mob)
	local status = self:GetThreat(unit, mob)
	if not status or status == 0 then return nil end
	-- The shared color table (General > Colors) when present, else the game's.
	if self.GetThreatStatusColor then
		local r, g, b = self:GetThreatStatusColor(status)
		if r then return r, g, b end
	end
	if not GetThreatStatusColor then return nil end
	return GetThreatStatusColor(status)
end

-- True when the game says threat values are secret for this pair right now.
local function ValuesSecret(unit, mob)
	local secrets = C_Secrets and C_Secrets.ShouldUnitThreatValuesBeSecret
	if not secrets then return false end
	local ok, secret = pcall(secrets, unit, mob)
	if not ok or issecret(secret) then return false end
	return secret and true or false
end
M.ThreatValuesSecret = ValuesSecret

---------------------------------------------------------------------------
-- Feature
---------------------------------------------------------------------------
local F = { key = "threat", title = "Threat" }
F.defaults = {
	enabled = false,
	source = "target",        -- target | focus
	pets = false,
	show = "auto",            -- auto (only with threat) | combat | always
	grow = "DOWN",            -- DOWN: highest at the top; UP: highest at the bottom
	rows = 5,
	value = "percent",        -- percent | threat | both
	classNames = true,
	barColor = "class",       -- class | status | accent
	ownColor = false, ownColorValue = { 0.2, 0.67, 1 },
	tankColor = true, tankColorValue = { 0.85, 0.25, 0.2 },
	pullLine = true, pullMode = "auto", pullColor = { 1, 1, 1 },
	warn = false, warnAt = 90, warnSound = "none",
	width = 220, barHeight = 14, spacing = 1,
	texture = "", font = "THEME", fontSize = 11,
	header = true, borders = true, background = 60,
}

local window, rows = nil, {}
local state = { mob = nil, list = {}, warned = false, secret = false }

local function DB() return M.db.threat end
local function Active() return M.active and DB().enabled and not E:StandsBack(M, F.key) end

local function FontFile()
	return K.FontPath(DB().font)
end

-- The mob whose threat table is shown. A friendly target (a healer on the
-- tank) shows that friend's target instead.
local function MobUnit()
	local unit = DB().source == "focus" and "focus" or "target"
	if not Exists(unit) then return nil end
	if Hostile(unit) then return unit end
	local through = unit .. "target"
	if Exists(through) and Hostile(through) then return through end
	return nil
end

-- Units that can be on the table: the group (with pets when wanted).
local function GroupUnits()
	local list = {}
	local pets = DB().pets
	if IsInRaid() then
		for index = 1, GetNumGroupMembers() do
			list[#list + 1] = "raid" .. index
			if pets then list[#list + 1] = "raidpet" .. index end
		end
	else
		list[#list + 1] = "player"
		if pets then list[#list + 1] = "pet" end
		for index = 1, GetNumSubgroupMembers() do
			list[#list + 1] = "party" .. index
			if pets then list[#list + 1] = "partypet" .. index end
		end
	end
	return list
end

local function IsMe(unit)
	if unit == "player" then return true end
	local same = UnitIsUnit(unit, "player")
	return not issecret(same) and same and true or false
end

-- Collect readable rows; sorting only happens on plain numbers.
local function Collect(mob)
	local list, anySecret = {}, false
	for _, unit in ipairs(GroupUnits()) do
		if Exists(unit) then
			local ok, isTanking, status, scaled, percent, threat = pcall(UnitDetailedThreatSituation, unit, mob)
			if ok then
				if not K.Plain(isTanking, status, scaled, percent, threat) then
					anySecret = true
				elseif status ~= nil and percent and threat then
					list[#list + 1] = { unit = unit, tanking = isTanking, status = status, scaled = scaled,
						percent = percent, threat = threat, me = IsMe(unit) }
				end
			end
		end
	end
	table.sort(list, function(a, b)
		if a.threat ~= b.threat then return a.threat > b.threat end
		return a.unit < b.unit
	end)
	return list, anySecret
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function ValueText(entry)
	local mode = DB().value
	local percent = ("%d%%"):format(math.floor(entry.percent + 0.5))
	if mode == "percent" then return percent end
	-- The game reports threat in hundredths.
	local amount = E:FormatNumber(entry.threat / 100)
	if mode == "threat" then return amount end
	return ("%s  %s"):format(amount, percent)
end

local function BarColor(entry)
	local db = DB()
	if entry.me and db.ownColor then return unpack(db.ownColorValue) end
	if entry.tanking and db.tankColor then return unpack(db.tankColorValue) end
	if db.barColor == "status" and GetThreatStatusColor then
		return GetThreatStatusColor(entry.status or 0)
	elseif db.barColor == "accent" then
		local r, g, b = unpack(E.media.accentColor)
		return r, g, b
	end
	local _, class = UnitClass(entry.unit)
	local color = E:ClassColorObject(class)
	if color then return color.r, color.g, color.b end
	return 0.6, 0.6, 0.6
end

-- Where you pull aggro, in raw percent of the tank's threat.
local function PullPoint(list)
	local mode = DB().pullMode
	if mode == "melee" then return 110 end
	if mode == "ranged" then return 130 end
	for _, entry in ipairs(list) do
		if entry.me and not entry.tanking and entry.scaled and entry.scaled > 0 and entry.percent > 0 then
			local point = entry.percent / entry.scaled * 100
			return math.max(100, math.min(130, point))
		end
	end
	return 110
end

local function BarMax()
	return DB().pullLine and 130 or 100
end

local function CreateRow(index)
	local row = CreateFrame("Frame", nil, window.body)
	row.bar = E:CreateStatusBar(row)
	row.bar:SetAllPoints()
	E.statusBars[row.bar] = nil -- own texture choice below
	row.name = E:CreateText(row.bar, E.tokens.size.small, "LEFT")
	row.name:SetPoint("LEFT", 4, 0)
	row.value = E:CreateText(row.bar, E.tokens.size.small, "RIGHT")
	row.value:SetPoint("RIGHT", -4, 0)
	row.name:SetPoint("RIGHT", row.value, "LEFT", -4, 0)
	rows[index] = row
	return row
end

local function StyleRow(row)
	local db = DB()
	row.bar:SetStatusBarTexture(K.TexturePath(db.texture ~= "" and db.texture or nil))
	row.bar.bg:SetShown(db.borders)
	E:SetNameTextFont(row.name, db.fontSize, nil, FontFile)
	E:SetFont(row.value, db.fontSize, nil, FontFile)
end

local function PlaceRows(count)
	local db = DB()
	local step = db.barHeight + db.spacing
	for index = 1, MAX_ROWS do
		local row = rows[index]
		if row then
			row:ClearAllPoints()
			if index <= count then
				local offset = (index - 1) * step
				if db.grow == "UP" then
					row:SetPoint("BOTTOMLEFT", window.body, "BOTTOMLEFT", 0, offset)
					row:SetPoint("BOTTOMRIGHT", window.body, "BOTTOMRIGHT", 0, offset)
				else
					row:SetPoint("TOPLEFT", window.body, "TOPLEFT", 0, -offset)
					row:SetPoint("TOPRIGHT", window.body, "TOPRIGHT", 0, -offset)
				end
				row:SetHeight(db.barHeight)
			end
		end
	end
end

local function WindowSize()
	local db = DB()
	local body = db.rows * db.barHeight + (db.rows - 1) * db.spacing
	local header = db.header and HEADER or 0
	return db.width, body + header + 4
end

local function Warn(list)
	local db = DB()
	local mine
	for _, entry in ipairs(list) do
		if entry.me then mine = entry break end
	end
	local tank = (mine and mine.tanking) or E:PlayerIsTank()
	local hot = db.warn and mine and not tank and mine.scaled and mine.scaled >= db.warnAt
	if hot and not state.warned then
		state.warned = true
		if db.warnSound and db.warnSound ~= "none" then E:PlayMedia(db.warnSound) end
	elseif not hot and state.warned and (not mine or not mine.scaled or mine.scaled < db.warnAt - 10) then
		-- A little hysteresis so the sound does not repeat at the edge.
		state.warned = false
	end
	-- The word and its mark (DESIGN.md "Never color alone"), read when shown
	-- so the Shape marks switch and the safe colors apply.
	if hot then window.warning:SetText(E:StatusText("bad", L["Close to pulling aggro"])) end
	window.warning:SetShown(hot and true or false)
	return hot
end

local function ShouldShow(count)
	local show = DB().show
	if show == "always" then return true end
	if show == "combat" then
		local combat = UnitAffectingCombat("player")
		return issecret(combat) or combat or count > 0
	end
	return count > 0 or state.secret
end

function M:UpdateThreat()
	if not window or not Active() then return end
	local db = DB()
	local mob = MobUnit()
	local list, anySecret = {}, false
	if mob then list, anySecret = Collect(mob) end
	state.mob, state.list = mob, list
	state.secret = mob and (#list == 0) and (anySecret or ValuesSecret("player", mob)) or false
	local count = math.min(#list, db.rows)
	local hot = Warn(list)
	local max = BarMax()
	for index = 1, count do
		local entry = list[index]
		local row = rows[index] or CreateRow(index)
		if not row.styled then StyleRow(row) row.styled = true end
		row.bar:SetMinMaxValues(0, max)
		row.bar:SetValue(math.min(entry.percent, max))
		local r, g, b = BarColor(entry)
		if entry.me and hot then r, g, b = 1, 0.2, 0.2 end
		row.bar:SetStatusBarColor(r, g, b)
		local unitName = UnitName(entry.unit)
		if issecret(unitName) then row.name:SetText(unitName) else row.name:SetText(unitName or "") end
		local nr, ng, nb = 1, 1, 1
		if db.classNames and db.barColor ~= "class" then
			local _, class = UnitClass(entry.unit)
			local color = E:ClassColorObject(class)
			if color then nr, ng, nb = color.r, color.g, color.b end
		end
		row.name:SetTextColor(nr, ng, nb)
		row.value:SetText(ValueText(entry))
		row:Show()
	end
	for index = count + 1, MAX_ROWS do
		if rows[index] then rows[index]:Hide() end
	end
	PlaceRows(count)
	-- Pull-aggro line across the bars.
	if db.pullLine and count > 0 then
		local point = PullPoint(list)
		local width = window.body:GetWidth()
		if not width or width <= 0 then width = db.width - 4 end
		local x = width * point / max
		-- As tall as the bars that show.
		window.pull:ClearAllPoints()
		window.pull:SetHeight(count * db.barHeight + (count - 1) * db.spacing)
		if db.grow == "UP" then
			window.pull:SetPoint("BOTTOM", window.body, "BOTTOMLEFT", x, 0)
		else
			window.pull:SetPoint("TOP", window.body, "TOPLEFT", x, 0)
		end
		window.pull:SetColorTexture(unpack(db.pullColor))
		window.pull:Show()
	else
		window.pull:Hide()
	end
	if mob then
		local name = UnitName(mob)
		if issecret(name) then window.title:SetText(name) else window.title:SetText(name or "") end
	else
		window.title:SetText(db.source == "focus" and (_G.FOCUS or L["Focus"]) or (TARGET or L["Target"]))
	end
	window.empty:SetShown(count == 0)
	window.empty:SetText(state.secret and L["Threat is hidden by the game here"] or L["No threat"])
	window:SetShown(ShouldShow(count))
end

-- Several events arrive in one frame (a pull): draw once.
local function Queue()
	E:Debounce("hud:threat", 0.1, function()
		if Active() then M:UpdateThreat() end
	end)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", Queue)
local EVENTS = { "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
	"GROUP_ROSTER_UPDATE", "UNIT_PET", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function ToggleSource()
	local db = DB()
	db.source = db.source == "focus" and "target" or "focus"
	window.source:SetText(db.source == "focus" and "F" or "T")
	M:UpdateThreat()
end

function F:Setup()
	local db = DB()
	-- Its height comes from the rows, so only the width can be matched.
	local width, height = WindowSize()
	local holder = K.Holder(M, MOVER, L["Threat Meter"], { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -474, 22 }, width, height,
		{ sizeKeys = { width = { key = "threat.width", min = 120, max = 400 } } })
	holder:Hide() -- shown while the meter is on
	window = CreateFrame("Frame", nil, holder)
	window:SetAllPoints(holder)
	window.holder = holder
	-- A meter window: the small box plus the art style's frame line, like
	-- the damage meter (DESIGN.md §1), not the panel template.
	E:SetTemplate(window, true)
	E:SetStyleEdge(window, db.borders)

	window.header = CreateFrame("Frame", nil, window)
	window.header:SetPoint("TOPLEFT", 2, -2)
	window.header:SetPoint("TOPRIGHT", -2, -2)
	window.header:SetHeight(HEADER)
	window.title = E:CreateText(window.header, E.tokens.size.small, "LEFT")
	window.title:SetPoint("LEFT", 4, 0)
	window.title:SetPoint("RIGHT", -24, 0)
	-- Target / focus switch.
	local switch = CreateFrame("Button", nil, window.header)
	switch:SetSize(18, 14)
	switch:SetPoint("RIGHT", -2, 0)
	E:SetTemplate(switch, true)
	window.source = E:CreateText(switch, E.tokens.size.tiny)
	window.source:SetPoint("CENTER")
	window.source:SetText(db.source == "focus" and "F" or "T")
	switch:SetScript("OnClick", function(button, mouse)
		if E:IsOptionsLinkClick(button, mouse) then return end
		ToggleSource()
	end)
	switch:SetScript("OnEnter", function(button)
		GameTooltip:SetOwner(button, "ANCHOR_TOP")
		GameTooltip:SetText(L["Threat source"])
		E:TooltipHint(GameTooltip, { L["Click"], L["switch between your target (T) and your focus (F)"] })
		GameTooltip:Show()
	end)
	switch:SetScript("OnLeave", GameTooltip_Hide)
	E:BindOptionsLink(switch, { page = "module:CombatHUD", key = "threat.source" })
	window.switch = switch
	window.underline = window.header:CreateTexture(nil, "ARTWORK")
	window.underline:SetPoint("BOTTOMLEFT")
	window.underline:SetPoint("BOTTOMRIGHT")
	window.underline:SetHeight(E.pixel)
	E:AccentTexture(window.underline, 0.6)

	window.body = CreateFrame("Frame", nil, window)
	window.pull = window.body:CreateTexture(nil, "OVERLAY", nil, 7)
	window.pull:SetWidth(math.max(1, E.pixel * 2))
	window.empty = E:CreateText(window.body, E.tokens.size.small)
	window.empty:SetPoint("CENTER")
	window.empty:SetTextColor(unpack(E.media.text.secondary))
	window.warning = E:CreateText(window, E.tokens.size.label)
	window.warning:SetPoint("BOTTOM", window, "TOP", 0, 4)
	window.warning:SetTextColor(unpack(E.media.text.bad))
	window.warning:SetText(L["Close to pulling aggro"])
	window.warning:Hide()
	window:Hide()
end

function F:Apply(db)
	local holder = window.holder
	holder:Show()
	holder:SetSize(WindowSize())
	E:SetTemplate(window, true)
	local r, g, b = window:GetBackdropColor()
	window:SetBackdropColor(r, g, b, db.background / 100)
	if not db.borders then window:SetBackdropBorderColor(0, 0, 0, 0) end
	E:SetStyleEdge(window, db.borders)
	window.header:SetShown(db.header)
	E:SetFont(window.title, db.fontSize, nil, FontFile)
	window.source:SetText(db.source == "focus" and "F" or "T")
	window.body:ClearAllPoints()
	window.body:SetPoint("TOPLEFT", 2, db.header and -(HEADER + 2) or -2)
	window.body:SetPoint("BOTTOMRIGHT", -2, 2)
	for _, row in pairs(rows) do StyleRow(row) row.styled = true end
	events:UnregisterAllEvents()
	for _, event in ipairs(EVENTS) do events:RegisterEvent(event) end
	-- A friend's target changes without a target event of our own.
	events:RegisterUnitEvent("UNIT_TARGET", "target", "focus")
	M:UpdateThreat()
end

function F:Restore()
	events:UnregisterAllEvents()
	state.warned = false
	if window then
		window:Hide()
		window.holder:Hide()
	end
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local function Off() return not (M.db and M.db.threat and M.db.threat.enabled) end
local function Textures() local v = K.TextureValues(); v[""] = L["Theme texture"]; return v end

F.note = L["Lists your group on the threat table of your target or focus, as the game reports it. Where the game hides threat, the window says so."]
F.options = {
	{ type = "toggle", key = "threat.enabled", label = "Threat meter", desc = "A small window with one bar per group member on your target's threat table." },
	{ type = "header", label = "What it shows", hidden = Off },
	{ type = "select", key = "threat.source", label = "Source", hidden = Off,
		values = { target = "Target", focus = "Focus" },
		desc = "Whose threat table is listed. The T/F button in the window header switches it too. A friendly target shows the threat on that friend's target." },
	{ type = "toggle", key = "threat.pets", label = "Include pets", hidden = Off, desc = "Pets on the threat table get a bar too." },
	{ type = "select", key = "threat.show", label = "Show", hidden = Off,
		values = { auto = "Only when there is threat", combat = "In combat", always = "Always" },
		desc = "When the window is on screen." },
	{ type = "range", key = "threat.rows", label = "Rows", min = 3, max = 10, step = 1, hidden = Off, desc = "Most bars the window shows." },
	{ type = "select", key = "threat.grow", label = "Highest threat", hidden = Off,
		values = { DOWN = "At the top", UP = "At the bottom" }, desc = "Where the player with the most threat sits." },
	{ type = "select", key = "threat.value", label = "Value", hidden = Off,
		values = { percent = "Threat %", threat = "Raw threat", both = "Both" },
		desc = "Threat % is the share of the tank's threat, as Blizzard shows it on the target frame." },
	{ type = "header", label = "Colors", hidden = Off },
	{ type = "select", key = "threat.barColor", label = "Bar color", hidden = Off,
		values = { class = "Class color", status = L["Threat status color"], accent = "Accent color" },
		desc = "Color of each bar. Threat status uses the game's yellow, orange and red." },
	{ type = "toggle", key = "threat.classNames", label = "Class-colored names", hidden = function() return Off() or M.db.threat.barColor == "class" end,
		desc = "Names in their class color (the bars are not class colored)." },
	{ type = "toggle", key = "threat.ownColor", label = "Own bar color", hidden = Off, desc = "Your own bar in a fixed color." },
	{ type = "color", key = "threat.ownColorValue", label = "Own color", hidden = function() return Off() or not M.db.threat.ownColor end,
		desc = "Color of your own bar." },
	{ type = "toggle", key = "threat.tankColor", label = "Tank color", hidden = Off, desc = "The player who has aggro gets a fixed color." },
	{ type = "color", key = "threat.tankColorValue", label = "Tank bar color", hidden = function() return Off() or not M.db.threat.tankColor end,
		desc = "Color of the bar of the player who has aggro." },
	{ type = "header", label = "Pull aggro line and warning", hidden = Off },
	{ type = "toggle", key = "threat.pullLine", label = "Pull aggro line", hidden = Off,
		desc = "A line where you would take aggro: 110 % of the tank's threat in melee, 130 % at range (Blizzard's rule)." },
	{ type = "select", key = "threat.pullMode", label = "Line at", hidden = function() return Off() or not M.db.threat.pullLine end,
		values = { auto = "Automatic", melee = "110 % (melee)", ranged = "130 % (ranged)" },
		desc = "Automatic reads where you pull from the two threat numbers the game gives for you." },
	{ type = "color", key = "threat.pullColor", label = "Line color", hidden = function() return Off() or not M.db.threat.pullLine end,
		desc = "Color of the pull aggro line." },
	{ type = "toggle", key = "threat.warn", label = "Warning", hidden = Off,
		desc = "Your bar turns red and a note shows when you get close to pulling aggro. Never while you are the tank." },
	{ type = "range", key = "threat.warnAt", label = "Warn at", unit = "%", min = 50, max = 100, step = 5, hidden = function() return Off() or not M.db.threat.warn end,
		desc = "How close to pulling aggro, in percent of the point where you would pull." },
	{ type = "media", key = "threat.warnSound", label = "Warning sound", mediaKind = "sound", hidden = function() return Off() or not M.db.threat.warn end,
		desc = "Sound played once when the warning starts. None plays nothing." },
	{ type = "header", label = "Look", hidden = Off },
	{ type = "range", key = "threat.width", label = "Width", min = 120, max = 400, step = 1, hidden = Off, desc = "Width of the window." },
	{ type = "range", key = "threat.barHeight", label = "Bar height", min = 10, max = 30, step = 1, hidden = Off, desc = "Height of each bar." },
	{ type = "range", key = "threat.spacing", label = "Spacing", min = 0, max = 6, step = 1, hidden = Off, desc = "Space between bars." },
	{ type = "select", key = "threat.texture", label = "Bar texture", values = Textures, hidden = Off, desc = "Texture of the bars." },
	{ type = "media", mediaKind = "font", default = "THEME", defaultLabel = "Theme font", key = "threat.font", label = "Font", hidden = Off, desc = "Font of names and values." },
	{ type = "range", key = "threat.fontSize", label = "Text size", min = 8, max = 18, step = 1, hidden = Off, desc = "Size of names and values." },
	{ type = "toggle", key = "threat.header", label = "Header", hidden = Off, desc = "The title line with the mob's name and the target/focus switch." },
	{ type = "toggle", key = "threat.borders", label = "Borders", hidden = Off, desc = "1 px borders around the window and each bar." },
	{ type = "range", key = "threat.background", label = "Background opacity", unit = "%", min = 0, max = 100, step = 5, hidden = Off,
		desc = "Opacity of the window background, in percent." },
}

M:AddFeature(F)

E:AddCommand("threat", "[on | off | focus | target]  EldoUI threat meter", function(arg)
	local db = M.db and M.db.threat
	if not db then return end
	if not M.active then E:Print(E:ModuleOffHint("CombatHUD")) return end
	arg = (arg or ""):lower()
	if arg == "focus" or arg == "target" then
		db.source = arg
	elseif arg == "on" then
		db.enabled = true
	elseif arg == "off" then
		db.enabled = false
	elseif arg == "" or arg == "toggle" then
		db.enabled = not db.enabled
	else
		E:Print(L["Usage: /eui threat [on | off | focus | target]"])
		return
	end
	M:ApplyFeature(F)
	local source = db.source == "focus" and L["focus"] or L["target"]
	E:Print((db.enabled and L["Threat meter on (%s)."] or L["Threat meter off (%s)."]):format(source))
end, "Tools")
