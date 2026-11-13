-- EldoUI Battleground Timers: one stack of countdown bars for
-- the timers the game already knows during battlegrounds: queue wait, time
-- to enter, the gates opening, base captures, the expected winner, the
-- match time left and the flag return. The bars come from E.TimerBars, so
-- they share the EldoUI look and follow the bar texture and art style.
--
-- Files (Modules/Battlegrounds/):
--   Battlegrounds.lua  module, settings, the bar stack, colors, zone switch,
--                      test bars, style presets
--   MapData.lua        EldoUI's own per-map facts (instance IDs, durations)
--   Queue.lua          queue, time to enter and battle start bars
--   Countdown.lua      Blizzard element "pvp-start-countdown"
--   Captures.lua       base, tower and graveyard captures from map POIs
--   Score.lua          expected winner, time left, flag back
--   Extras.lua         share to the chat box, AV turn-ins, mine owners
--   Probe.lua          /eui probe bg (widget and POI dump for in-game checks, the last 20 kept)
--   Options.lua        the options page
--
-- How it stays within the rules: presentation only. Every value comes from
-- a Blizzard API the game hands every addon (queue status, START_TIMER,
-- top-center widgets, map POIs, item counts). Values are checked with
-- issecretvalue before any math; a secret hides that bar. No combat log,
-- no scoreboard during a match (C_PvP score info is secret there), no
-- addon messages, no chat sends, no CVars. Nothing is queued, accepted,
-- released or handed in for the player.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local M = E:NewModule("Battlegrounds", {
	title = "Battleground Timers",
	desc = L["Timers for battleground queues, the gates opening, base captures and the expected winner. Only shows what the game reports."],
	category = "Combat",
	conflicts = { "Capping" },
	frames = { "EldoUI_BGTimers", "EldoUI_StartCountdown" },
	movers = { "EldoUI_BGTimers", "EldoUI_StartCountdown" },
	blizzard = { "pvp-start-countdown" },
	savedKeys = { "profile.modules.Battlegrounds", "EldoUIDB.bgProbe" },
	optionsPage = "module:Battlegrounds",
	presets = { "Accent", "Compact", "IconsRight", "Large", "Slim", "Standard" },
	defaults = {
		enabled = true,
		width = 220,
		height = 18,
		spacing = 4,
		growUp = false,
		maxBars = 8,
		icon = "LEFT",        -- LEFT | RIGHT | NONE
		showTime = true,
		fill = "drain",       -- drain | fill
		fontSize = 12,
		font = "THEME",
		texture = "default",
		background = true,
		colorMode = "faction", -- faction | accent | custom
		colors = {
			alliance = { 0.29, 0.33, 0.91 },
			horde = { 0.9, 0.05, 0.07 },
			queue = { 0.6, 0.6, 0.6 },
			other = { 0.2, 0.67, 1 },
		},
		queue = { wait = true, port = true },
		start = true,
		captures = true,
		predict = true,
		matchTime = true,
		flagRespawn = true,
		turnIns = true,
		owners = true,
		share = false,
		alongside = false,    -- keep the in-match bars while DBM-PvP runs
		countdownScale = 100, -- Blizzard element pvp-start-countdown, Move
		visibility = E:VisibilityDefaults(),
	},
})

-- Kinds of bars and the color slot each uses.
local COLOR_SLOT = { alliance = "alliance", horde = "horde", queue = "queue" }
-- Bars that keep their place at the top of the stack.
local PINNED = { queue = true, port = true, start = true }

local IsSecret = E.Secret
M.IsSecret = IsSecret

-- Call fn(...) safely; nil when it fails or the first value is secret.
function M.Read(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d, e, f = pcall(fn, ...)
	if not ok or IsSecret(a) then return nil end
	return a, b, c, d, e, f
end

---------------------------------------------------------------------------
-- Parts: each file adds one with M:AddPart(part). A part may have
--   Enable()          module switched on (register events)
--   Disable()         module switched off
--   Enter(map)        the player entered a battleground (map from MapData)
--   Leave()           the player left it
--   Refresh()         settings changed
---------------------------------------------------------------------------
M.parts = {}

function M:AddPart(part)
	self.parts[#self.parts + 1] = part
	return part
end

function M:EachPart(method, ...)
	for _, part in ipairs(self.parts) do
		if part[method] then
			local ok, err = pcall(part[method], part, ...)
			if not ok then geterrorhandler()(err) end
		end
	end
end

---------------------------------------------------------------------------
-- Colors: faction colors, the accent, or the player's own.
---------------------------------------------------------------------------
local function Accent()
	local r, g, b = unpack(E.media.accentColor)
	return { r, g, b }
end

-- The faction colors: Blizzard's own values (Mainline
-- PLAYER_FACTION_COLORS; the Forever client has no such table, so EldoUI
-- keeps the same values in its defaults).
local function GameFactionColor(kind)
	local color = M.defaults.colors[kind]
	return { color[1], color[2], color[3] }
end

-- { r, g, b } for a bar kind (alliance, horde, queue, port, start, other).
function M:Color(kind)
	local db = self.db
	local slot = COLOR_SLOT[kind] or "other"
	if db.colorMode == "accent" then return Accent() end
	if db.colorMode == "custom" then
		local color = db.colors[slot]
		if type(color) == "table" then return { color[1] or color.r, color[2] or color.g, color[3] or color.b } end
	end
	if slot == "alliance" or slot == "horde" then return GameFactionColor(slot) end
	if slot == "queue" then return { 0.6, 0.6, 0.6 } end
	return Accent()
end

-- "alliance" / "horde" from a faction group name, a faction ID (469, 67)
-- or a widget side index (1 = left = Alliance, 2 = right = Horde).
function M.Side(value)
	if value == "Alliance" or value == 469 or value == 1 or value == "alliance" then return "alliance" end
	if value == "Horde" or value == 67 or value == 2 or value == "horde" then return "horde" end
end

function M:SideName(side)
	if side == "alliance" then return _G["FACTION_ALLIANCE"] or L["Alliance"] end
	if side == "horde" then return _G["FACTION_HORDE"] or L["Horde"] end
	return ""
end

-- Faction banner icons, also used when a bar has no icon of its own.
local FACTION_ICON = {
	alliance = "Interface\\Icons\\INV_BannerPVP_02",
	horde = "Interface\\Icons\\INV_BannerPVP_01",
}
function M:FactionIcon(side)
	side = side or self.Side(M.Read(UnitFactionGroup, "player"))
	return FACTION_ICON[side] or FACTION_ICON.alliance
end

---------------------------------------------------------------------------
-- The bar stack
---------------------------------------------------------------------------
local function RowHeight(db)
	local textRoom = db.height < 10 and (db.fontSize + 2) or 0
	return db.height + textRoom
end

function M:CreateStack()
	if self.holder then return end
	local db = self.db
	local holder = CreateFrame("Frame", "EldoUI_BGTimers", UIParent)
	holder:SetFrameStrata("MEDIUM")
	holder:SetSize(db.width, db.maxBars * (RowHeight(db) + db.spacing))
	self.holder = holder
	self.group = E.TimerBars:CreateGroup(holder, { width = db.width, height = db.height, options = { page = "module:Battlegrounds" } })
	E:CreateMover(holder, "EldoUI_BGTimers", L["Battleground Timers"], { "CENTER", "UIParent", "CENTER", 520, 140 })
end

-- The stack shares its spot with the boss mod's timer bars, which never
-- show in a battleground. When the player keeps the bars next to a boss
-- mod's own battleground timers, those timers take that spot, so the
-- stack moves to the boss frames' spot of the layout, which no boss uses
-- in a battleground. (An addon that turns the whole module off never
-- gets here: the module is not active then.) A position the player
-- dragged stays where it is.
function M:BesideBossModTimers()
	return self.active and self.db and self.db.alongside and E:CompetitorLoaded("Battlegrounds", "bgtimers") ~= nil or false
end
E:RegisterLayoutSpotRule("EldoUI_BGTimers", function() return M:BesideBossModTimers() and "EldoUI_Boss" or nil end)

-- Re-place the stack when that answer changes (the switch, the boss mod
-- loading as a battleground starts).
function M:PlaceStack()
	local beside = self:BesideBossModTimers()
	if self.placedBeside ~= nil and beside == self.placedBeside then return end
	self.placedBeside = beside
	E:ApplyMover("EldoUI_BGTimers")
end

-- The look from the settings onto the stack.
function M:ApplyLook()
	local db = self.db
	local holder, group = self.holder, self.group
	if not holder then return end
	holder:SetSize(db.width, db.maxBars * (RowHeight(db) + db.spacing))
	group:ClearAllPoints()
	if db.growUp then
		group:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT")
	else
		group:SetPoint("TOPLEFT", holder, "TOPLEFT")
	end
	group:SetLook({
		width = db.width,
		height = db.height,
		spacing = db.spacing,
		growth = db.growUp and "UP" or "DOWN",
		max = db.maxBars,
		icon = db.icon ~= "NONE",
		iconSide = db.icon == "RIGHT" and "RIGHT" or "LEFT",
		fontSize = db.fontSize,
		font = db.font,
		texture = db.texture,
		background = db.background,
		mouse = self:BarsTakeMouse(),
	})
	-- Colors and fill follow the settings too.
	for key, bar in pairs(group.bars) do
		local data = bar.data
		if data and data.kind then self:Decorate(data) end
		group:Update(key, {})
	end
end

-- Bars take the mouse (tooltips, Shift-click) only while sharing is on,
-- so the stack never blocks clicks into the world otherwise.
function M:BarsTakeMouse()
	return self.db.share and true or false
end

-- Fill in color, fill direction, time text and click handler for a bar.
function M:Decorate(data)
	local db = self.db
	data.color = self:Color(data.kind)
	data.borderColor = nil
	if db.colorMode == "accent" and (data.kind == "alliance" or data.kind == "horde") then
		data.borderColor = GameFactionColor(data.kind)
	end
	data.fill = db.fill
	data.pinned = PINNED[data.kind] or false
	if data.frozenText then
		data.timeText = db.showTime and data.frozenText or ""
	else
		data.timeText = (not db.showTime) and "" or nil
	end
	data.onClick = self.OnBarClick
	return data
end

-- Start (or update) a bar. data: label, kind, duration or expires, icon,
-- frozenText (no countdown), side ("alliance" / "horde", for sharing),
-- tooltip.
function M:Bar(key, data)
	if not self.group or type(data) ~= "table" then return nil end
	if IsSecret(data.label) or IsSecret(data.duration) or IsSecret(data.expires) then
		self.group:Stop(key)
		return nil
	end
	self:Decorate(data)
	return self.group:Start(key, data)
end

-- A bar with no countdown ("-" or a count).
function M:Freeze(key, data, text)
	data.frozenText = text or "-"
	data.duration, data.expires = nil, nil
	return self:Bar(key, data)
end

function M:Stop(key)
	if self.group then self.group:Stop(key) end
end

-- The data of a running bar, or nil.
function M:Get(key)
	local bar = self.group and self.group:Get(key)
	return bar and bar.data
end

function M:Remaining(key)
	return self.group and self.group:Remaining(key)
end

function M:HasBar(key)
	return self.group and self.group:Get(key) ~= nil
end

-- Stop every bar whose key starts with prefix ("poi:", "queue:").
function M:StopPrefix(prefix)
	if not self.group then return end
	local list = {}
	for key in pairs(self.group.bars) do
		if type(key) == "string" and key:sub(1, #prefix) == prefix then list[#list + 1] = key end
	end
	for _, key in ipairs(list) do self.group:Stop(key) end
end

-- Restart a running bar only when its time moved by more than `slack`
-- seconds, so small drifts don't make the bar jump.
function M:BarNear(key, seconds, slack)
	local left = self:Remaining(key)
	return left ~= nil and math.abs(left - seconds) <= (slack or 1)
end

-- Shift-click handler (set up by Extras.lua).
function M.OnBarClick(key, data, button)
	if M.ShareBar then M:ShareBar(key, data, button) end
end

-- DBM-PvP draws its own capture and score bars. The in-match bars stand
-- back while it runs, unless the player wants both (queue and start bars
-- stay). Capping turns the whole module off (conflicts above).
function M:StandBack()
	-- "Show next to DBM-PvP" is the registry's "show both" switch too.
	if self.db.alongside then return false end
	return (E:StandsBack(self, "bgtimers"))
end

---------------------------------------------------------------------------
-- Zone switch
---------------------------------------------------------------------------
-- The map we are in when it is a battleground, else nil.
function M:CurrentBattleground()
	local inInstance, kind = IsInInstance()
	if IsSecret(inInstance) or IsSecret(kind) or not inInstance or kind ~= "pvp" then return nil end
	local instanceID = select(8, GetInstanceInfo())
	if IsSecret(instanceID) then instanceID = nil end
	return self:MapInfo(instanceID)
end

function M:CheckZone()
	self:PlaceStack()
	local map = self:CurrentBattleground()
	local wasIn = self.map
	if map and (not wasIn or wasIn.instanceID ~= map.instanceID) then
		if wasIn then self:EachPart("Leave") end
		self.map = map
		self:EachPart("Enter", map)
	elseif not map and wasIn then
		self.map = nil
		self:EachPart("Leave")
	end
end

---------------------------------------------------------------------------
-- Test bars
---------------------------------------------------------------------------
function M:ShowTestBars()
	if not self.active then
		E:Print(L["Turn Battleground Timers on first (Modules page)."])
		return
	end
	self:Bar("test:queue", { kind = "queue", label = L["Warsong Gulch"], duration = 30, icon = self:FactionIcon(),
		tooltip = L["Test bar: the game's estimated queue wait."] })
	self:Bar("test:start", { kind = "start", label = L["Battle begins"], duration = 28,
		tooltip = L["Test bar: time until the gates open."] })
	self:Bar("test:alliance", { kind = "alliance", label = L["Stables"], duration = 26, icon = self:FactionIcon("alliance"),
		tooltip = L["Test bar: a base the Alliance is taking."] })
	self:Bar("test:horde", { kind = "horde", label = L["Lumber Mill"], duration = 24, icon = self:FactionIcon("horde"),
		tooltip = L["Test bar: a base the Horde is taking."] })
	self:Bar("test:predict", { kind = "horde", label = L["Horde wins 2000-1430"], duration = 30, icon = self:FactionIcon("horde"),
		tooltip = L["Test bar: estimate from the current score."] })
end

function M:HideTestBars()
	self:StopPrefix("test:")
end

---------------------------------------------------------------------------
-- Visibility
---------------------------------------------------------------------------
function M:UpdateVisibility()
	if not self.holder then return end
	if E:IsVisibilityAttached(self.holder) then
		E:UpdateVisibility(self.holder)
	else
		E:AttachVisibility(self.holder, self.db.visibility, {
			forceShow = function() return E:IsMoveMode() end,
		})
	end
end

---------------------------------------------------------------------------
-- Enable / disable
---------------------------------------------------------------------------
function M:OnEnable()
	self:CreateStack()
	self.holder:Show()
	self:ApplyLook()
	self:UpdateVisibility()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() M:CheckZone() end)
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() M:CheckZone() end)
	self:EachPart("Enable")
	self:CheckZone()
end

function M:OnDisable()
	self.placedBeside = nil
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	self:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
	if self.map then
		self.map = nil
		self:EachPart("Leave")
	end
	self:EachPart("Disable")
	if self.group then self.group:StopAll() end
	if self.holder then
		E:DetachVisibility(self.holder)
		self.holder:Hide()
	end
end

-- Re-apply size, fonts, colors and every part's settings.
function M:OnProfileChanged()
	if not self.active then return end
	self:ApplyLook()
	self:UpdateVisibility()
	self:PlaceStack()
	self:EachPart("Refresh")
end

---------------------------------------------------------------------------
-- Style presets: looks only, never positions.
---------------------------------------------------------------------------
E:RegisterStyles("Battlegrounds", {
	{ key = "Standard", title = L["Standard"], desc = L["220 px bars with the icon left and the time right."],
		settings = { width = 220, height = 18, spacing = 4, icon = "LEFT", fontSize = 12, background = true, fill = "drain", colorMode = "faction" } },
	{ key = "Compact", title = L["Compact"], desc = L["Narrow 170 px bars, small text, no icons."],
		settings = { width = 170, height = 14, spacing = 3, icon = "NONE", fontSize = 11, background = true, fill = "drain", colorMode = "faction" } },
	{ key = "Large", title = L["Large"], desc = L["Wide 280 px bars with 14 pt text for big screens."],
		settings = { width = 280, height = 24, spacing = 4, icon = "LEFT", fontSize = 14, background = true, fill = "drain", colorMode = "faction" } },
	{ key = "Slim", title = L["Slim"], desc = L["Thin 6 px bars with the text above them."],
		settings = { width = 220, height = 6, spacing = 4, icon = "LEFT", fontSize = 11, background = false, fill = "drain", colorMode = "faction" } },
	{ key = "Accent", title = L["Accent"], desc = L["Every bar in the EldoUI accent color; the faction shows on the icon border."],
		settings = { width = 220, height = 18, spacing = 4, icon = "LEFT", fontSize = 12, background = true, fill = "drain", colorMode = "accent" } },
	{ key = "IconsRight", title = L["Icons right"], desc = L["The icon on the right of each bar, for a stack on the right side of the screen."],
		settings = { width = 220, height = 18, spacing = 4, icon = "RIGHT", fontSize = 12, background = true, fill = "drain", colorMode = "faction" } },
})
