-- EldoUI DBM: Deadly Boss Mods runs as it is, with an EldoUI touch on top.
--
-- EldoUI never ships, copies or patches DBM code (All Rights Reserved): it
-- only calls DBM's long-stable methods and writes the option keys DBM's own
-- options window writes. What it does, after the player opts in once
-- (installer "Other addons" step, the button on this module's page, the
-- EldoUI panel inside DBM's options or /eui dbm setup):
--   * DBM:CreateProfile / DBM:ApplyProfile an "EldoUI_<Layout>" profile, one
--     per layout. The player's own profile is remembered (per character)
--     and never written; "Switch back" applies it again.
--   * Positions: timers, enlarged timers, warnings, special warnings, the
--     info frame and the range frame go to the EldoUI movers of the active
--     layout (already scaled by layout fit), re-sent after every layout
--     click and mover drag (debounced, out of combat, never during an
--     encounter).
--   * Look: EldoUI font, bar texture, 1 px border, backdrop and accent on
--     the timer bars through DBT:SetOption, EldoUI font on warnings and the
--     info frame. Why options and not a DBT skin: DBT:SetSkin forks the bar
--     settings into a separate table per skin, DBM loads the "DBM" one at
--     every login (DBM-Core ADDON_LOADED -> DBT:LoadOptions("DBM")) and a
--     skin is only a set of option values anyway (no drawing hook). Writing
--     the same option keys into EldoUI's own DBM profile gives the identical
--     look, survives /reload by itself and needs no hook on DBM's bars.
--   * Quiet chat and role timing (bossmods-integration.md section 3).
--
-- Never written: sounds, voices, voice packs, countdowns, comms and syncs,
-- auto-accept, gossip, raid icons, yells, the pull timer, per-boss options,
-- DBM_UseDualProfile. A key is only written when DBM.DefaultOptions (or
-- DBT.DefaultOptions) still has it with the same type; anything renamed by
-- a DBM update is skipped and reported by /eui diag.
-- Nothing here reads encounter data; IsEncounterInProgress only delays our
-- own writes until the fight is over.
local _, E = ...
local L = E.L

local M = E:NewModule("DBM", {
	title = "Deadly Boss Mods",
	desc = "Deadly Boss Mods with an EldoUI touch: its own DBM profile per layout, timers and warnings placed by the layout, the EldoUI look and quiet chat. Your DBM profile, sounds and boss settings stay yours.",
	category = "Interface",
	frames = { "EldoUI_BossWarnings", "EldoUI_BossInfo" },
	movers = { "EldoUI_BossWarnings", "EldoUI_BossInfo" },
	blizzard = {},
	savedKeys = { "profile.modules.DBM", "private.dbm" },
	optionsPage = "module:DBM",
	presets = { "Full", "Look", "Off", "Positions", "Quiet" },
	reload = false,
	defaults = {
		enabled = true,
		place = true,   -- positions from the EldoUI layout
		skin = true,    -- EldoUI look on bars, warnings and the info frame
		quiet = true,   -- warnings not copied to chat, no flash for low-urgency warnings
		pro = true,     -- role timing
		role = "auto",  -- auto, TANK, HEALER, DAMAGER
	},
})

local PREFIX = "EldoUI_"          -- profile names; DBM rejects spaces
-- Checked against DBM 12.1.15 for WoW: Forever 1.60.1: DBM-Core needs
-- DBM-StatusBarTimers (the timer bars), and DBM-GUI (DBM's options window)
-- loads only when the player opens it, so the EldoUI panel inside it is
-- made then, once.
local TESTED = "12.1.15"          -- DBM.DisplayVersion this module was last checked against
M.TESTED = TESTED

E:RegisterPrivate("dbm", {
	optedIn = false,
	timelineFade = false,   -- the Encounter Timeline's bar fade (opacity), false while off
	fadeSaved = false,      -- DBT Alpha / HugeAlpha from before the fade
	previous = "",          -- the player's own DBM profile before EldoUI's
	applied = { skin = false, quiet = false, pro = false },
})

local function Char()
	return E:GetPrivate("dbm")
end

---------------------------------------------------------------------------
-- The keys EldoUI may write, with the type DBM must still give them.
---------------------------------------------------------------------------
local CORE_KEYS = {
	WarningPoint = "string", WarningX = "number", WarningY = "number",
	SpecialWarningPoint = "string", SpecialWarningX = "number", SpecialWarningY = "number",
	InfoFramePoint = "string", InfoFrameX = "number", InfoFrameY = "number",
	RangeFramePoint = "string", RangeFrameX = "number", RangeFrameY = "number",
	RangeFrameRadarPoint = "string", RangeFrameRadarX = "number", RangeFrameRadarY = "number",
	WarningFont = "string", SpecialWarningFont = "string", InfoFrameFont = "string",
	ShowWarningsInChat = "boolean", ShowSWarningsInChat = "boolean", ShowGuildMessages = "boolean",
	WarningIconChat = "boolean", SpecialWarningFlash1 = "boolean", SpecialWarningFlash2 = "boolean",
}
local BAR_KEYS = {
	TimerPoint = "string", TimerX = "number", TimerY = "number",
	HugeTimerPoint = "string", HugeTimerX = "number", HugeTimerY = "number",
	Width = "number", HugeWidth = "number",
	Texture = "string", Font = "string", FontSize = "number", FontFlag = "string",
	Scale = "number", HugeScale = "number", Height = "number", HugeHeight = "number",
	BorderEnabled = "boolean", BorderSize = "number", BorderColorR = "number", BorderColorG = "number",
	BorderColorB = "number", BorderAlpha = "number",
	HugeBorderEnabled = "boolean", HugeBorderSize = "number", HugeBorderColorR = "number",
	HugeBorderColorG = "number", HugeBorderColorB = "number", HugeBorderAlpha = "number",
	BackgroundColorR = "number", BackgroundColorG = "number", BackgroundColorB = "number", BackgroundAlpha = "number",
	HugeBackgroundColorR = "number", HugeBackgroundColorG = "number", HugeBackgroundColorB = "number",
	HugeBackgroundAlpha = "number",
	StartColorR = "number", StartColorG = "number", StartColorB = "number",
	EnlargeBarTime = "number", HideLongBars = "boolean", HiddenBarTime = "number",
}
-- Keys only newer DBM versions have (the Forever trash and boss alerts). An
-- older DBM simply lacks them: they are never written then, and never count
-- as settings that need an update.
local NEW_CORE_KEYS = {}
for _, area in ipairs({ "Dungeon", "Raid" }) do
	NEW_CORE_KEYS["GenericTrashForever" .. area .. "Channel"] = "boolean"
	NEW_CORE_KEYS["GenericTrashForever" .. area .. "StandardFilter"] = "string"
	NEW_CORE_KEYS["GenericTrashForever" .. area .. "EliteFilter"] = "string"
end
M.CORE_KEYS, M.BAR_KEYS, M.NEW_CORE_KEYS = CORE_KEYS, BAR_KEYS, NEW_CORE_KEYS

-- Belt and braces: whatever the tables above say, these never get written.
local FORBIDDEN = { "Sound", "Voice", "Count", "Pull", "Yell", "Say", "Whisper", "AutoAccept", "AutoRespond",
	"Gossip", "SetIcons", "Sync", "Comm", "Dual", "Hide.*Frame", "Debug" }

local function Forbidden(key)
	for _, pattern in ipairs(FORBIDDEN) do
		if key:find(pattern) then return true end
	end
	return false
end

-- Role timing (bossmods-integration.md 3.2). DBM has no "visible bars" cap;
-- long timers wait hidden until HiddenBarTime instead.
local ROLE_TIMING = {
	TANK = { EnlargeBarTime = 10, HiddenBarTime = 60 },
	HEALER = { EnlargeBarTime = 8, HiddenBarTime = 90 },
	DAMAGER = { EnlargeBarTime = 7, HiddenBarTime = 45 },
}
M.ROLE_TIMING = ROLE_TIMING

---------------------------------------------------------------------------
-- DBM access (all optional globals, looked up only while DBM is loaded)
---------------------------------------------------------------------------
local function Loaded()
	return C_AddOns.IsAddOnLoaded("DBM-Core") and true or false
end

local function Core()
	if not Loaded() then return end
	local dbm = _G.DBM
	if type(dbm) == "table" and type(dbm.Options) == "table" and type(dbm.DefaultOptions) == "table" then return dbm end
end

local function Bars()
	if not C_AddOns.IsAddOnLoaded("DBM-StatusBarTimers") then return end
	local dbt = _G.DBT
	if type(dbt) == "table" and type(dbt.Options) == "table" and type(dbt.DefaultOptions) == "table" then return dbt end
end

local function SavedProfiles()
	local saved = Loaded() and _G.DBM_AllSavedOptions
	return type(saved) == "table" and saved or {}
end

function M:IsLoaded()
	return Loaded()
end

function M:ActiveProfile()
	local name = Loaded() and _G.DBM_UsedProfile
	return type(name) == "string" and name or "Default"
end

function M:IsOurs(name)
	return type(name) == "string" and name:sub(1, #PREFIX) == PREFIX
end

function M:ProfileName(layoutKey)
	layoutKey = layoutKey or (E.db and E.db.general.layout) or "Layout"
	return PREFIX .. tostring(layoutKey):gsub("[^%w_]", "")
end

function M:ProfileExists(name)
	return SavedProfiles()[name] ~= nil
end

-- DBM runs, it has loaded its options, and the API EldoUI calls is there.
function M:Ready()
	local dbm, dbt = Core(), Bars()
	return self.dbmReady and dbm and dbt and type(dbm.CreateProfile) == "function"
		and type(dbm.ApplyProfile) == "function" and type(dbm.RepositionFrames) == "function"
		and type(dbt.SetOption) == "function" and type(dbt.Rearrange) == "function" and true or false
end

-- EldoUI writes only into its own profile, and only after the opt-in.
function M:Writable()
	local char = Char()
	return self:Ready() and char and char.optedIn and self:IsOurs(self:ActiveProfile()) and true or false
end

local function EncounterActive()
	local api = C_InstanceEncounter
	if api and type(api.IsEncounterInProgress) == "function" then
		local ok, active = pcall(api.IsEncounterInProgress)
		return ok and active == true
	end
	return false
end
M.EncounterActive = EncounterActive

---------------------------------------------------------------------------
-- Writing keys
---------------------------------------------------------------------------
M.skipped = {} -- "core.Key" / "bars.Key" -> true: keys this DBM version lacks

local function Skip(where, key)
	if not M.skipped[where .. "." .. key] then
		M.skipped[where .. "." .. key] = true
		M.skipNew = true
	end
end

-- One key into DBM.Options, only when DBM still has it with that type.
function M:WriteCore(key, value)
	local dbm = Core()
	local kind = CORE_KEYS[key] or NEW_CORE_KEYS[key]
	if not dbm or Forbidden(key) or kind == nil then return false end
	local default = dbm.DefaultOptions[key]
	if default == nil and NEW_CORE_KEYS[key] then return false end
	if default == nil or type(default) ~= kind or type(value) ~= kind then
		Skip("core", key)
		return false
	end
	dbm.Options[key] = value
	return true
end

-- One key into the timer bar options (DBT:SetOption, styling deferred).
function M:WriteBar(key, value)
	local dbt = Bars()
	if not dbt or Forbidden(key) or BAR_KEYS[key] == nil then return false end
	local default = dbt.DefaultOptions[key]
	if default == nil or type(default) ~= BAR_KEYS[key] or type(value) ~= BAR_KEYS[key] then
		Skip("bars", key)
		return false
	end
	dbt:SetOption(key, value, true)
	return true
end

-- Every key EldoUI relies on that this DBM version no longer has (for
-- /eui diag and the one-time note after a DBM update).
function M:MissingKeys()
	local missing = {}
	local dbm, dbt = Core(), Bars()
	if dbm then
		for key, kind in pairs(CORE_KEYS) do
			local default = dbm.DefaultOptions[key]
			if default == nil or type(default) ~= kind then missing[#missing + 1] = "DBM." .. key end
		end
	end
	if dbt then
		for key, kind in pairs(BAR_KEYS) do
			local default = dbt.DefaultOptions[key]
			if default == nil or type(default) ~= kind then missing[#missing + 1] = "DBT." .. key end
		end
	end
	table.sort(missing)
	return missing
end

-- Once per session: a quiet chat line and an error-log entry, so a DBM
-- update that renamed keys gets noticed and fixed.
function M:ReportMissing()
	local missing = self:MissingKeys()
	if #missing == 0 or self.reported then return end
	self.reported = true
	local dbm = Core()
	local version = dbm and tostring(dbm.DisplayVersion or "?") or "?"
	self:Print(L["EldoUI's DBM setup needs an update for DBM %s (%d settings skipped)."]:format(version, #missing))
	if E.errors and E.errors.Add then
		E.errors:Add("warning", ("EldoUI DBM module: DBM %s lacks %s (tested with %s)"):format(version, table.concat(missing, ", "), TESTED),
			"Interface/AddOns/EldoUI/Modules/DBM.lua")
	end
end

---------------------------------------------------------------------------
-- Positions from the EldoUI movers
---------------------------------------------------------------------------
-- Timer and message areas are the boss-mod movers the Integrations module
-- shares with BigWigs; the special warning and info spots are this
-- module's own movers.
local AREAS = {
	bars = { sample = { kind = "bars" }, mover = "EldoUI_BigWigsBars", width = 220, height = 160, point = { "CENTER", "UIParent", "CENTER", 520, 140 } },
	huge = { sample = { kind = "bars" }, mover = "EldoUI_BigWigsEmphasize", width = 260, height = 120, point = { "CENTER", "UIParent", "CENTER", 540, 300 } },
	warnings = { sample = { kind = "text" }, mover = "EldoUI_BigWigsMessages", width = 400, height = 60, point = { "TOP", "UIParent", "TOP", 0, -192 } },
	special = { sample = { kind = "text" }, mover = "EldoUI_BossWarnings", width = 400, height = 44, point = { "CENTER", "UIParent", "CENTER", 0, 370 } },
	info = { mover = "EldoUI_BossInfo", width = 220, height = 120, point = { "CENTER", "UIParent", "CENTER", 300, 295 } },
}
M.AREAS = AREAS

local measure -- an invisible frame that stands in for a mover nobody created

-- left, bottom, width, height of an area in UIParent units.
function M:AreaRect(key)
	local area = AREAS[key]
	local mover = E.movers[area.mover]
	if mover and mover:IsShown() and mover:GetLeft() then
		return mover:GetLeft(), mover:GetBottom(), mover:GetWidth(), mover:GetHeight()
	end
	-- No mover (Integrations off): the layout's point at the default size.
	if not measure then
		measure = CreateFrame("Frame", nil, UIParent)
		measure:Hide()
	end
	local point = E:GetMoverDefaultPoint(area.mover) or area.point
	local anchor = E.GetMoverAnchor and E:GetMoverAnchor(point[3]) or UIParent
	measure:ClearAllPoints()
	measure:SetSize(area.width, area.height)
	measure:SetPoint(point[1], anchor, point[3], point[4], point[5])
	return measure:GetLeft(), measure:GetBottom(), measure:GetWidth(), measure:GetHeight()
end

local function Round(value)
	return math.floor(value + 0.5)
end

-- The DBM keys for every area: all frames use UIParent offsets.
function M:PlacementPlan()
	local screenW, screenH = UIParent:GetSize()
	local plan = { core = {}, bars = {} }
	local function TopCentre(key)
		local left, bottom, width, height = self:AreaRect(key)
		if not left then return end
		return Round(left + width / 2 - screenW / 2), Round(bottom + height - screenH / 2), width
	end
	local x, y, width = TopCentre("bars")
	if x then
		local dbt = Bars()
		local scale = dbt and tonumber(dbt.Options.Scale) or 1
		plan.bars.TimerPoint, plan.bars.TimerX, plan.bars.TimerY = "CENTER", x, y
		plan.bars.Width = Round(width / (scale > 0 and scale or 1))
	end
	x, y, width = TopCentre("huge")
	if x then
		local dbt = Bars()
		local scale = dbt and tonumber(dbt.Options.HugeScale) or 1
		plan.bars.HugeTimerPoint, plan.bars.HugeTimerX, plan.bars.HugeTimerY = "CENTER", x, y
		plan.bars.HugeWidth = Round(width / (scale > 0 and scale or 1))
	end
	-- Warning texts hang down from a 1x1 frame: its center goes to the top
	-- center of the area.
	x, y = TopCentre("warnings")
	if x then plan.core.WarningPoint, plan.core.WarningX, plan.core.WarningY = "CENTER", x, y end
	x, y = TopCentre("special")
	if x then plan.core.SpecialWarningPoint, plan.core.SpecialWarningX, plan.core.SpecialWarningY = "CENTER", x, y end
	-- Info and range frames grow right and down from the area's top left.
	local left, bottom, _, height = self:AreaRect("info")
	if left then
		local ix, iy = Round(left), Round(bottom + height - screenH)
		plan.core.InfoFramePoint, plan.core.InfoFrameX, plan.core.InfoFrameY = "TOPLEFT", ix, iy
		plan.core.RangeFramePoint, plan.core.RangeFrameX, plan.core.RangeFrameY = "TOPLEFT", ix, iy
		plan.core.RangeFrameRadarPoint, plan.core.RangeFrameRadarX, plan.core.RangeFrameRadarY = "TOPLEFT", ix, iy
	end
	return plan
end

---------------------------------------------------------------------------
-- Look, quiet chat and role timing
---------------------------------------------------------------------------
local LOOK_CORE = { "WarningFont", "SpecialWarningFont", "InfoFrameFont" }
local LOOK_BARS = { "Texture", "Font", "FontSize", "FontFlag", "Scale", "HugeScale", "Height", "HugeHeight",
	"BorderEnabled", "BorderSize", "BorderColorR", "BorderColorG", "BorderColorB", "BorderAlpha",
	"HugeBorderEnabled", "HugeBorderSize", "HugeBorderColorR", "HugeBorderColorG", "HugeBorderColorB", "HugeBorderAlpha",
	"BackgroundColorR", "BackgroundColorG", "BackgroundColorB", "BackgroundAlpha",
	"HugeBackgroundColorR", "HugeBackgroundColorG", "HugeBackgroundColorB", "HugeBackgroundAlpha",
	"StartColorR", "StartColorG", "StartColorB" }
local QUIET_CORE = { "ShowWarningsInChat", "ShowSWarningsInChat", "ShowGuildMessages", "WarningIconChat",
	"SpecialWarningFlash1", "SpecialWarningFlash2" }
-- Trash and boss alerts stay on: quiet only keeps channeled casts out and
-- keeps the alerts to your target (DBM's own filter value).
local QUIET_TRASH = {}
for _, area in ipairs({ "Dungeon", "Raid" }) do
	for _, field in ipairs({ "Channel", "StandardFilter", "EliteFilter" }) do
		QUIET_TRASH[#QUIET_TRASH + 1] = "GenericTrashForever" .. area .. field
	end
end
local QUIET_ALL = {}
for _, key in ipairs(QUIET_CORE) do QUIET_ALL[#QUIET_ALL + 1] = key end
for _, key in ipairs(QUIET_TRASH) do QUIET_ALL[#QUIET_ALL + 1] = key end
local PRO_BARS = { "EnlargeBarTime", "HideLongBars", "HiddenBarTime" }
M.GROUPS = { skin = { core = LOOK_CORE, bars = LOOK_BARS }, quiet = { core = QUIET_ALL, bars = {} }, pro = { core = {}, bars = PRO_BARS } }

local FONT_SIZE = 12

-- DBM's own spelling for "no outline" is "None".
local function FontFlag()
	local outline = E.db and E.db.general.fontOutline or "OUTLINE"
	if outline == "" or outline == "NONE" then return "None" end
	return outline
end

local function FontUsable(path, size, flags)
	local dbm = Core()
	if type(path) ~= "string" or path == "" then return false end
	if dbm and type(dbm.IsFontValid) == "function" then
		local ok, valid = pcall(dbm.IsFontValid, dbm, path, nil, size, flags ~= "None" and flags or "")
		return ok and valid and true or false
	end
	return true
end

function M:LookPlan()
	local media = E.media
	local border, backdrop, accent = media.borderColor, media.backdropColor, media.accentColor
	local pixel = E.pixel or 1
	local plan = { core = {}, bars = {} }
	local bars = plan.bars
	bars.Texture = media.statusbar
	bars.Scale, bars.HugeScale = 1, 1
	bars.Height, bars.HugeHeight = 18, 22
	bars.BorderEnabled, bars.HugeBorderEnabled = true, true
	bars.BorderSize, bars.HugeBorderSize = pixel, pixel
	bars.BorderColorR, bars.BorderColorG, bars.BorderColorB, bars.BorderAlpha = border[1], border[2], border[3], border[4] or 1
	bars.HugeBorderColorR, bars.HugeBorderColorG, bars.HugeBorderColorB, bars.HugeBorderAlpha = border[1], border[2], border[3], border[4] or 1
	bars.BackgroundColorR, bars.BackgroundColorG, bars.BackgroundColorB, bars.BackgroundAlpha = backdrop[1], backdrop[2], backdrop[3], backdrop[4] or 0.8
	bars.HugeBackgroundColorR, bars.HugeBackgroundColorG, bars.HugeBackgroundColorB, bars.HugeBackgroundAlpha = backdrop[1], backdrop[2], backdrop[3], backdrop[4] or 0.8
	-- The accent fills the plain bars; the colors by type keep their meaning.
	bars.StartColorR, bars.StartColorG, bars.StartColorB = accent[1], accent[2], accent[3]
	-- A font DBM can't use would make DBM reset its own font settings.
	local flags = FontFlag()
	if FontUsable(media.font, FONT_SIZE, flags) then
		bars.Font, bars.FontSize, bars.FontFlag = media.font, FONT_SIZE, flags
		plan.core.WarningFont, plan.core.SpecialWarningFont, plan.core.InfoFrameFont = media.font, media.font, media.font
	else
		self.fontRefused = media.font
	end
	return plan
end

function M:QuietPlan()
	local core = {}
	for _, key in ipairs(QUIET_CORE) do core[key] = false end
	local dbm = Core()
	local defaults = dbm and dbm.DefaultOptions
	if defaults then
		for _, key in ipairs(QUIET_TRASH) do
			local default = defaults[key]
			if key:find("Channel$") then
				if default ~= nil then core[key] = false end
			elseif type(default) == "string" then
				core[key] = default
			end
		end
	end
	return { core = core, bars = {} }
end

-- The player's role: the setting, the group role the game gives, then the
-- role picked in EldoUI's installer (solo or before a role is assigned).
local EUI_ROLE = { tank = "TANK", healer = "HEALER", damage = "DAMAGER" }

function M:Role()
	local role = self.db.role
	if ROLE_TIMING[role] then return role end
	local ok, assigned = pcall(UnitGroupRolesAssigned, "player")
	if ok and not (issecretvalue and issecretvalue(assigned)) and type(assigned) == "string" and ROLE_TIMING[assigned] then
		return assigned
	end
	local own = E.GetRoleGroup and EUI_ROLE[E:GetRoleGroup()]
	if own and ROLE_TIMING[own] then return own end
	return "DAMAGER"
end

function M:ProPlan()
	local timing = ROLE_TIMING[self:Role()]
	return { core = {}, bars = { EnlargeBarTime = timing.EnlargeBarTime, HiddenBarTime = timing.HiddenBarTime, HideLongBars = true } }
end

-- DBM's own defaults for a group, written when the player switches it off.
function M:DefaultsPlan(group)
	local dbm, dbt = Core(), Bars()
	local plan = { core = {}, bars = {} }
	for _, key in ipairs(M.GROUPS[group].core) do
		if dbm and dbm.DefaultOptions[key] ~= nil then plan.core[key] = dbm.DefaultOptions[key] end
	end
	for _, key in ipairs(M.GROUPS[group].bars) do
		if dbt and dbt.DefaultOptions[key] ~= nil then plan.bars[key] = dbt.DefaultOptions[key] end
	end
	return plan
end

local function WritePlan(plan)
	local count = 0
	for key, value in pairs(plan.core) do
		if M:WriteCore(key, value) then count = count + 1 end
	end
	for key, value in pairs(plan.bars) do
		if M:WriteBar(key, value) then count = count + 1 end
	end
	return count
end

-- DBM moves and restyles its frames from the options just written.
local function Refresh()
	local dbm, dbt = Core(), Bars()
	if dbm and type(dbm.RepositionFrames) == "function" then dbm:RepositionFrames() end
	if dbt then
		if type(dbt.Rearrange) == "function" then dbt:Rearrange() end
		if type(dbt.UpdateBars) == "function" then dbt:UpdateBars(true) end
	end
end

---------------------------------------------------------------------------
-- Apply, switch, set up, undo
---------------------------------------------------------------------------
-- Positions only (mover drags, layout clicks).
function M:Place()
	if not (self:Writable() and self.db.place) then return 0 end
	local count = WritePlan(self:PlacementPlan())
	Refresh()
	self.lastPlace = count
	return count
end

-- Everything the settings ask for. A group the player switched off gets
-- DBM's own values back once, then is left alone.
function M:ApplyAll()
	if not self:Writable() then return 0 end
	local char = Char()
	local count = 0
	for _, group in ipairs({ "skin", "quiet", "pro" }) do
		if self.db[group] then
			local plan = group == "skin" and self:LookPlan() or group == "quiet" and self:QuietPlan() or self:ProPlan()
			count = count + WritePlan(plan)
			char.applied[group] = true
		elseif char.applied[group] then
			count = count + WritePlan(self:DefaultsPlan(group))
			char.applied[group] = false
		end
	end
	if self.db.place then count = count + WritePlan(self:PlacementPlan()) end
	-- A new layout profile gets the Encounter Timeline's fade too.
	if type(char.timelineFade) == "number" then self:ApplyTimelineFade() end
	Refresh()
	if self.skipNew then
		self.skipNew = false
		self:ReportMissing()
	end
	self.lastApply = count
	return count
end

-- Switch DBM to the layout's EldoUI profile (creating it from DBM's
-- defaults when it is new). Returns true when that profile is active.
function M:UseLayoutProfile(layoutKey)
	local dbm = Core()
	if not (dbm and self:Ready()) then return false end
	local target = self:ProfileName(layoutKey)
	if self:ActiveProfile() ~= target then
		if self:ProfileExists(target) then
			dbm:ApplyProfile(target)
		else
			dbm:CreateProfile(target)
		end
	end
	return self:ActiveProfile() == target
end

---------------------------------------------------------------------------
-- The Encounter Timeline's "Fade DBM's own bars": DBT Alpha and
-- HugeAlpha in EldoUI's own DBM profile, through the type-checked writer,
-- out of combat and outside encounters (M:Defer). The values from before
-- are kept and written back when the fade ends. DBM keeps drawing (and
-- publishing) its bars; HideDBMBars is never written.
---------------------------------------------------------------------------
-- The two keys of the fade, checked like WriteBar checks its keys (DBT
-- must still have them as numbers). Kept apart from BAR_KEYS: they are not
-- part of the look EldoUI sets up, and /eui diag needs them only while the
-- fade is on.
local FADE_KEYS = { "Alpha", "HugeAlpha" }

local function WriteFade(key, value)
	local dbt = Bars()
	if not dbt or type(value) ~= "number" or type(dbt.DefaultOptions[key]) ~= "number" then return false end
	dbt:SetOption(key, value, true)
	return true
end

function M:TimelineFadeActive()
	local char = Char()
	return char and type(char.timelineFade) == "number" or false
end

function M:ApplyTimelineFade()
	local char = Char()
	local dbt = Bars()
	if not (char and dbt and type(char.timelineFade) == "number" and self:Writable()) then return false end
	if type(char.fadeSaved) ~= "table" then
		char.fadeSaved = {}
		for _, key in ipairs(FADE_KEYS) do char.fadeSaved[key] = dbt.Options[key] end
	end
	local written = false
	for _, key in ipairs(FADE_KEYS) do
		if WriteFade(key, char.timelineFade) then written = true end
	end
	Refresh()
	return written
end

function M:RestoreTimelineFade()
	local char = Char()
	if not (char and type(char.fadeSaved) == "table") then return false end
	if not self:Writable() then return false end
	for _, key in ipairs(FADE_KEYS) do WriteFade(key, char.fadeSaved[key]) end
	char.fadeSaved = false
	Refresh()
	return true
end

-- alpha 0-0.8 fades the bars, nil brings them back.
function M:SetTimelineFade(alpha)
	local char = Char()
	if not char then return false end
	if type(alpha) == "number" then
		if not self:Writable() then return false end
		alpha = math.max(0, math.min(0.8, alpha))
		if char.timelineFade == alpha and type(char.fadeSaved) == "table" then return true end
		char.timelineFade = alpha
		self:Defer(function() M:ApplyTimelineFade() end)
	else
		if char.timelineFade == false and char.fadeSaved == false then return true end
		char.timelineFade = false
		self:Defer(function() M:RestoreTimelineFade() end)
	end
	return true
end

-- The opt-in: remember the player's profile, switch to EldoUI's, apply.
function M:Setup()
	if not self:Ready() then
		self:Print(self:IsLoaded() and L["DBM is still loading. Try again in a moment."] or L["Deadly Boss Mods is not loaded."])
		return false
	end
	if InCombatLockdown() or EncounterActive() then
		self:Print(L["DBM is set up when the fight is over."])
		self:Defer(function() M:Setup() end)
		return false
	end
	local char = Char()
	local active = self:ActiveProfile()
	if not self:IsOurs(active) then char.previous = active end
	if not self:UseLayoutProfile() then
		self:Print(L["DBM did not switch to the EldoUI profile; nothing was changed."])
		return false
	end
	char.optedIn = true
	self:ApplyAll()
	self:SyncMovers()
	self:Print(L["DBM uses the profile %s now. Your own profile (%s) is kept: switch back any time on this page or with /eui dbm undo."]:format(E:Highlight(self:ActiveProfile()), char.previous ~= "" and char.previous or "Default"))
	if E.RefreshConfig then E:RefreshConfig() end
	return true
end

-- Undo: back to the player's own profile. The EldoUI profiles stay, so
-- setting up again is one click.
function M:Undo()
	local dbm = Core()
	local char = Char()
	if not (dbm and self:Ready()) then
		self:Print(L["Deadly Boss Mods is not loaded."])
		return false
	end
	if InCombatLockdown() or EncounterActive() then
		self:Print(L["Your DBM profile comes back when the fight is over."])
		self:Defer(function() M:Undo() end)
		return false
	end
	local previous = char.previous ~= "" and char.previous or "Default"
	if not self:ProfileExists(previous) then previous = "Default" end
	char.optedIn = false
	if self:ActiveProfile() ~= previous and self:ProfileExists(previous) then dbm:ApplyProfile(previous) end
	self:SyncMovers()
	self:Print(L["DBM uses your profile %s again. The EldoUI profiles are kept for later."]:format(E:Highlight(self:ActiveProfile())))
	if E.RefreshConfig then E:RefreshConfig() end
	return true
end

-- After login or a layout click: the layout's profile, then everything.
function M:Sync()
	local char = Char()
	if not (self:Ready() and char and char.optedIn) then return end
	-- The player picked another profile in DBM: leave it alone.
	if not self:IsOurs(self:ActiveProfile()) then return end
	if self:UseLayoutProfile() then self:ApplyAll() end
end

function M:Reapply()
	if not self:Writable() then
		self:Print(L["Set DBM up for EldoUI first."])
		return false
	end
	if InCombatLockdown() or EncounterActive() then
		self:Defer(function() M:Reapply() end)
		return false
	end
	local count = self:ApplyAll()
	self:Print(L["EldoUI settings re-applied to the DBM profile %s (%d settings)."]:format(self:ActiveProfile(), count))
	return true
end

function M:Test()
	local dbm = Core()
	if not dbm or type(dbm.DemoMode) ~= "function" then
		self:Print(L["Deadly Boss Mods is not loaded."])
		return
	end
	if InCombatLockdown() then
		self:Print(L["The test timers run out of combat."])
		return
	end
	dbm:DemoMode()
end

---------------------------------------------------------------------------
-- Scheduling: debounced, out of combat, never during an encounter
---------------------------------------------------------------------------
local pending = {}
local timerRunning, waitingCombat, waitingEncounter = false, false, false
local deferred = {}

-- Runs fn once the player is out of combat and no encounter is running.
function M:Defer(fn)
	deferred[#deferred + 1] = fn
	self:Schedule()
end

function M:Flush()
	if InCombatLockdown() then
		if not waitingCombat then
			waitingCombat = true
			E:RunOutOfCombat(function()
				waitingCombat = false
				M:Flush()
			end)
		end
		return
	end
	if EncounterActive() then
		waitingEncounter = true
		return
	end
	waitingEncounter = false
	local work = pending
	pending = {}
	local calls = deferred
	deferred = {}
	if work.sync then
		self:Sync()
	elseif work.all then
		self:ApplyAll()
	elseif work.place then
		self:Place()
	end
	for _, fn in ipairs(calls) do
		local ok, err = pcall(fn)
		if not ok then geterrorhandler()(err) end
	end
end

-- kind: "place", "all" or "sync" (layout switch); nil only flushes.
function M:Schedule(kind)
	if kind then pending[kind] = true end
	if timerRunning then return end
	timerRunning = true
	C_Timer.After(0.2, function()
		timerRunning = false
		if M.active then M:Flush() end
	end)
end

function M:OnEncounterEnd()
	if waitingEncounter then self:Schedule() end
end

---------------------------------------------------------------------------
-- Movers: special warnings and info/range are this module's; the timer and
-- message movers are shared with BigWigs (Modules/Integrations.lua).
---------------------------------------------------------------------------
M.proxies = {}

-- The boss-mod movers are wanted while DBM is loaded and placed by EldoUI.
function M:WantsMovers()
	return self.active and Loaded() and self.db.place and true or false
end

local OWN = {
	{ key = "special", title = "Boss Special Warnings" },
	{ key = "info", title = "Boss Info and Range" },
}

function M:SyncMovers()
	local wanted = self:WantsMovers()
	for _, def in ipairs(OWN) do
		local area = AREAS[def.key]
		local proxy = self.proxies[area.mover]
		if wanted and not proxy then
			proxy = CreateFrame("Frame", area.mover, UIParent)
			proxy:SetSize(area.width, area.height)
			proxy:EnableMouse(false)
			self.proxies[area.mover] = proxy
			local previous = E.currentModule
			E.currentModule = self -- tag the mover with this module for exports
			E:CreateMover(proxy, area.mover, L[def.title], area.point, { sample = area.sample })
			E.currentModule = previous
		end
		if proxy then
			proxy:SetShown(wanted)
			if E.movers[area.mover] then E.movers[area.mover]:SetShown(wanted) end
		end
	end
	-- The shared timer and message movers live in Integrations.
	local integrations = E.modules.Integrations
	if integrations and integrations.active and integrations.SetupBigWigs then integrations:SetupBigWigs() end
end

local hooked = false
local function HookMovers()
	if hooked then return end
	hooked = true
	for _, area in pairs(AREAS) do
		E:RegisterMoverCallback(area.mover, function()
			if M.active then M:Schedule("place") end
		end)
	end
end

---------------------------------------------------------------------------
-- DBM loading
---------------------------------------------------------------------------
-- DBM runs its on-load callbacks just before it loads its options
-- (DBM-Core.lua ADDON_LOADED), or at once when it is already loaded; one
-- frame later the options are there either way.
function M:OnDBMLoaded()
	if self.dbmHooked then return end
	local dbm = Loaded() and _G.DBM
	if type(dbm) ~= "table" then return end
	self.dbmHooked = true
	local function Ready()
		C_Timer.After(0, function()
			M.dbmReady = true
			M:ReportMissing()
			if M.active then
				M:SyncMovers()
				M:Schedule("sync")
			end
		end)
	end
	if type(dbm.RegisterOnLoadCallback) == "function" then
		local ok = pcall(dbm.RegisterOnLoadCallback, dbm, Ready)
		if not ok then Ready() end
	else
		Ready()
	end
end

---------------------------------------------------------------------------
-- EldoUI panel inside DBM's own options (DBM-GUI is load on demand)
---------------------------------------------------------------------------
local ROLE_ORDER = { "auto", "TANK", "HEALER", "DAMAGER" }
local ROLE_NAMES = { auto = "Automatic (group role)", TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }
M.ROLE_NAMES = ROLE_NAMES

function M:StatusLines()
	local lines = {}
	local dbm = Core()
	if not dbm then
		lines[1] = L["Deadly Boss Mods is not loaded."]
		lines[2] = L["On WoW: Forever, DBM with DBM-Dungeons and DBM-Vanilla has the boss timers for the Forever and classic dungeons and raids. Install it like any addon; this page sets it up afterwards."]
		return lines
	end
	local char = Char()
	local active = self:ActiveProfile()
	lines[#lines + 1] = L["DBM %s (EldoUI checked against %s)"]:format(tostring(dbm.DisplayVersion or "?"), TESTED)
	lines[#lines + 1] = L["Active DBM profile: %s"]:format(active)
	if not (char and char.optedIn) then
		lines[#lines + 1] = L["Not set up: EldoUI changes nothing in DBM until you click \"Set up DBM for EldoUI\"."]
	elseif self:IsOurs(active) then
		lines[#lines + 1] = L["Set up: EldoUI keeps %s in line with your layout. Your own profile: %s."]:format(active, char.previous ~= "" and char.previous or "Default")
	else
		lines[#lines + 1] = L["You picked your own profile in DBM, so EldoUI leaves it alone. \"Set up\" switches back to EldoUI's."]
	end
	local missing = self:MissingKeys()
	if #missing > 0 then lines[#lines + 1] = L["Skipped (not in this DBM version): %s"]:format(table.concat(missing, ", ")) end
	if self.fontRefused then lines[#lines + 1] = L["DBM does not accept the EldoUI font on this client; DBM keeps its own font."] end
	return lines
end

function M:CreateDBMPanel()
	if self.dbmPanel or not C_AddOns.IsAddOnLoaded("DBM-GUI") then return end
	local gui = _G.DBM_GUI
	if type(gui) ~= "table" or type(gui.CreateNewPanel) ~= "function" then return end
	local ok, err = pcall(function()
		local panel = gui:CreateNewPanel("EldoUI", "option")
		M.dbmPanel = panel
		local area = panel:CreateArea("EldoUI")
		local status = area:CreateText("", nil, true)
		local checks = {}
		local function Check(label, key)
			local check = area:CreateCheckButton(label, true)
			check:SetScript("OnShow", function(button) button:SetChecked(M.db[key] and true or false) end)
			check:SetScript("OnClick", function(button)
				M.db[key] = button:GetChecked() and true or false
				M:OnProfileChanged()
				if E.RefreshConfig then E:RefreshConfig() end
			end)
			checks[#checks + 1] = check
			return check
		end
		Check(L["Place timers, warnings and the info frame with the EldoUI layout"], "place")
		Check(L["EldoUI look: font, bar texture, 1 px border, backdrop and accent"], "skin")
		Check(L["Quiet chat: no warning copies in chat, no screen flash for low-urgency warnings"], "quiet")
		Check(L["Role timing: enlarge and hide long timers for your role"], "pro")

		local buttons = panel:CreateArea(L["EldoUI actions"])
		local row, col = 0, 0
		local function Button(label, fn)
			local button = buttons:CreateButton(label, 250, 24, function()
				fn()
				M:RefreshDBMPanel()
			end)
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", buttons.frame, "TOPLEFT", 10 + col * 260, -10 - row * 30)
			button.myheight = col == 0 and 30 or 0
			col = col + 1
			if col > 1 then col, row = 0, row + 1 end
			return button
		end
		Button(L["Set up DBM for EldoUI"], function() M:Setup() end)
		Button(L["Switch back to my profile"], function() M:Undo() end)
		M.dbmRoleButton = Button(L["Role: %s"]:format(L[ROLE_NAMES[M.db.role]]), function()
			local index = 1
			for i, role in ipairs(ROLE_ORDER) do
				if role == M.db.role then index = i end
			end
			M.db.role = ROLE_ORDER[index % #ROLE_ORDER + 1]
			M:OnProfileChanged()
		end)
		Button(L["Show test timers"], function() M:Test() end)
		M.dbmStatus, M.dbmChecks = status, checks
		panel.frame:HookScript("OnShow", function() M:RefreshDBMPanel() end)
		M:RefreshDBMPanel()
	end)
	if not ok then geterrorhandler()(err) end
end

function M:RefreshDBMPanel()
	if self.dbmStatus then self.dbmStatus:SetText(table.concat(self:StatusLines(), "\n")) end
	if self.dbmRoleButton then self.dbmRoleButton:SetText(L["Role: %s"]:format(L[ROLE_NAMES[self.db.role] or self.db.role])) end
	for index, key in ipairs({ "place", "skin", "quiet", "pro" }) do
		local check = self.dbmChecks and self.dbmChecks[index]
		if check then check:SetChecked(self.db[key] and true or false) end
	end
end

---------------------------------------------------------------------------
-- Layout clicks, theme changes, diagnostics, slash command
---------------------------------------------------------------------------
E:RegisterLayoutCallback(function(_, _, silent)
	if not (M.active and Loaded()) then return end
	-- Installer previews only move things; the profile switch follows the
	-- layout the player keeps (next layout click or login).
	M:Schedule(silent and "place" or "sync")
end)

E:RegisterDiagnostics("DBM", function()
	if not Loaded() then return { "DBM: not loaded" } end
	local dbm, dbt = Core(), Bars()
	local char = Char()
	local lines = {}
	lines[#lines + 1] = ("DBM: %s (revision %s), checked against %s"):format(dbm and tostring(dbm.DisplayVersion or "?") or "?",
		dbm and tostring(dbm.Revision or "?") or "?", TESTED)
	lines[#lines + 1] = ("DBM profile: %s, EldoUI set up: %s, writing: %s"):format(M:ActiveProfile(),
		char and char.optedIn and "yes" or "no", M:Writable() and "yes" or "no")
	local api = {}
	for _, pair in ipairs({
		{ "DBM:CreateProfile", dbm and dbm.CreateProfile }, { "DBM:ApplyProfile", dbm and dbm.ApplyProfile },
		{ "DBM:RepositionFrames", dbm and dbm.RepositionFrames }, { "DBM:RegisterOnLoadCallback", dbm and dbm.RegisterOnLoadCallback },
		{ "DBT:SetOption", dbt and dbt.SetOption }, { "DBT:Rearrange", dbt and dbt.Rearrange },
		{ "DBT:RegisterSkin", dbt and dbt.RegisterSkin }, { "DBT:SetSkin", dbt and dbt.SetSkin },
	}) do
		if type(pair[2]) ~= "function" then api[#api + 1] = pair[1] end
	end
	local gui = C_AddOns.IsAddOnLoaded("DBM-GUI") and _G.DBM_GUI
	if gui and type(gui.CreateNewPanel) ~= "function" then api[#api + 1] = "DBM_GUI:CreateNewPanel" end
	lines[#lines + 1] = #api == 0 and "DBM API: complete" or ("DBM API missing: " .. table.concat(api, ", "))
	local missing = M:MissingKeys()
	lines[#lines + 1] = #missing == 0 and "DBM option keys: all present" or ("DBM option keys missing: " .. table.concat(missing, ", "))
	return lines
end)

E:AddCommand("dbm", "[setup | undo | apply | test]  Deadly Boss Mods: EldoUI profile, switch back, re-apply, test timers", function(arg)
	local word = strtrim((arg or ""):lower())
	if word == "setup" then
		M:Setup()
	elseif word == "undo" or word == "restore" then
		M:Undo()
	elseif word == "apply" then
		M:Reapply()
	elseif word == "test" then
		M:Test()
	else
		for _, line in ipairs(M:StatusLines()) do M:Print(line) end
	end
end, "Tools")

-- The installer's "Other addons" step: one tick sets DBM up.
E:RegisterAddonSetup("DBM", {
	title = "Deadly Boss Mods",
	available = function() return Loaded() and M.active and true or false end,
	profile = function() return "EldoUI" end, -- built by EldoUI, nothing to capture
	preselect = false, -- switching the DBM profile waits for the player's own tick
	missingHint = function()
		if Loaded() or C_AddOns.IsAddOnLoaded("BigWigs") then return nil end
		return L["Recommended: DBM (with DBM-Dungeons and DBM-Vanilla) has the boss timers for WoW: Forever."]
	end,
	import = function()
		if not M:Ready() then return false, L["DBM is still loading"] end
		return M:Setup()
	end,
})

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:OnInitialize()
	HookMovers()
end

function M:OnEnable()
	self:RegisterEvent("ADDON_LOADED", function(_, _, name)
		if name == "DBM-Core" or name == "DBM-StatusBarTimers" then
			M:OnDBMLoaded()
			M:SyncMovers()
		elseif name == "DBM-GUI" then
			M:CreateDBMPanel()
		end
	end)
	self:RegisterEvent("ENCOUNTER_END", function() M:OnEncounterEnd() end)
	if Loaded() then
		self:OnDBMLoaded()
		if self.dbmReady then self:Schedule("sync") end
	end
	self:SyncMovers()
	self:CreateDBMPanel()
end

function M:OnDisable()
	self:UnregisterEvent("ADDON_LOADED")
	self:UnregisterEvent("ENCOUNTER_END")
	self:SyncMovers()
end

-- Settings, style presets, accent, font or art style changed.
function M:OnProfileChanged()
	if not self.active then return end
	self:SyncMovers()
	if self:Writable() then self:Schedule("all") end
	self:RefreshDBMPanel()
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local function NotReady()
	if not Loaded() then return L["Deadly Boss Mods is not loaded"] end
	if not M:Ready() then return L["DBM is still loading"] end
end

local function NotSetUp()
	local reason = NotReady()
	if reason then return reason end
	local char = Char()
	if not (char and char.optedIn) then return L["Set DBM up for EldoUI first"] end
end

M.options = {
	{ type = "preview", label = "Status", height = 112,
		desc = "DBM's version, the DBM profile in use and what EldoUI does with it.",
		create = function(canvas)
			if not canvas then return end
			canvas.text = E:CreateText(canvas, E.tokens.size.label, "LEFT")
			canvas.text:SetPoint("TOPLEFT", 0, 0)
			canvas.text:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", 0, 0)
			canvas.text:SetWordWrap(true)
		end,
		update = function(canvas)
			if canvas and canvas.text then canvas.text:SetText(table.concat(M:StatusLines(), "\n")) end
		end },
	{ type = "header", label = "Setup" },
	{ type = "description", label = "\"Set up\" makes a DBM profile for your layout and switches DBM to it. Your own DBM profile is never changed and comes back in one click." },
	{ type = "execute", label = "Set up DBM for EldoUI", width = 220,
		desc = "Remembers your current DBM profile, switches DBM to the EldoUI profile of this layout (created on first use) and applies the settings below.",
		disabled = NotReady, func = function() M:Setup() end },
	{ type = "execute", label = "Re-apply EldoUI settings", width = 220,
		desc = "Writes the settings below into the EldoUI DBM profile again, for example after you changed something in DBM's own options.",
		disabled = NotSetUp, func = function() M:Reapply() end },
	{ type = "execute", label = "Switch back to my profile", width = 220,
		desc = "DBM uses the profile you had before the setup again. The EldoUI profiles stay in DBM's list, so setting up again is one click.",
		disabled = NotSetUp, func = function() M:Undo() end },
	{ type = "execute", label = "Test timers", width = 220,
		desc = "Runs DBM's test mode (/dbm test): bars, warnings and special warnings, to check the look and the positions.",
		disabled = NotReady, func = function() M:Test() end },
	{ type = "header", label = "What EldoUI sets in its DBM profile" },
	{ type = "toggle", key = "place", label = "Place with the layout",
		desc = "DBM's timers, warnings, info and range frames go to your layout's boss-mod movers, again after each layout click or drag (never during a fight)." },
	{ type = "toggle", key = "skin", label = "EldoUI look",
		desc = "EldoUI font, bar texture, 1 px border, backdrop and accent on DBM's timer bars, and the EldoUI font on warnings and the info frame. Off: DBM's own look comes back." },
	{ type = "toggle", key = "quiet", label = "Quiet chat",
		desc = "DBM stops copying warnings into chat and flashes the screen only for urgent ones (move, run away). Cast alerts stay on. Off puts DBM's own values back." },
	{ type = "toggle", key = "pro", label = "Role timing",
		desc = "Enlarges timers and keeps long timers hidden at the times that suit your role: tank 10 s and 60 s, healer 8 s and 90 s, damage 7 s and 45 s." },
	{ type = "select", key = "role", label = "Role", dependsOn = "pro",
		values = ROLE_NAMES,
		desc = "The role the timing follows. Automatic uses the group role the game gives you, and damage when you have none." },
	{ type = "description", label = "EldoUI never changes DBM's sounds, voices, comms, raid icons, pull timer or boss settings. Timer area sizes are on the Integrations page." },
}

---------------------------------------------------------------------------
-- Style presets
---------------------------------------------------------------------------
E:RegisterStyles("DBM", {
	{ key = "Full", title = "Full EldoUI", desc = "Layout positions, EldoUI look, quiet chat and role timing.",
		settings = { place = true, skin = true, quiet = true, pro = true } },
	{ mode = true, key = "Positions", title = "Positions only", desc = "DBM keeps its own look and chat; EldoUI only places its frames with the layout.",
		settings = { place = true, skin = false, quiet = false, pro = false } },
	{ key = "Look", title = "Look only", desc = "EldoUI look on DBM's bars and texts; DBM keeps its own positions.",
		settings = { place = false, skin = true, quiet = false, pro = false } },
	{ mode = true, key = "Quiet", title = "Quiet", desc = "Layout positions and quiet chat, with DBM's own look.",
		settings = { place = true, skin = false, quiet = true, pro = false } },
	{ mode = true, key = "Off", title = "Hands off", desc = "EldoUI sets nothing in its DBM profile; switch back to your own profile on this page.",
		settings = { place = false, skin = false, quiet = false, pro = false } },
})
