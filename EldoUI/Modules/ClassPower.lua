-- EldoUI Player Power: the resource stack right under the character
-- (mover EldoUI_PlayerPower, which every layout already places). Rows, top
-- to bottom: combo points (pips in a row or on an arc), your health, your
-- power (mana, rage, energy) with the cost of the spell you are casting and
-- threshold lines, druid mana while in a form, and a global cooldown bar.
-- Your combo points can also sit on your target's nameplate.
-- It also owns Blizzard's class resource frames through the
-- "class-resources" element switch: combo points on the target frame, the
-- druid mana bar, the totem timers and the personal resource display.
--
-- Forever has no runes, holy power or soul shard bars (Blizzard does not
-- load those bars on Forever). Soul Shards are bag items there, so a
-- warlock can show how many are in the bags at the end of the mana bar
-- (the game's own item count).
--
-- Secret values: health and power can be secret in combat. Bars receive
-- them straight from the game (SetMinMaxValues / SetValue) and texts go
-- through the tag engine (E:RenderTag), which only uses the game's own
-- formatters. Combo points are drawn as one status bar per pip whose range
-- is [i-1, i], so a pip fills when the count reaches it without Lua ever
-- comparing the count. The spell cost overlay is a second bar with the
-- same range as the power bar whose value is the spell's fixed cost, hung
-- on the right edge of the power fill: the client draws the width, Lua
-- does no math with your power. Threshold lines come from fixed spell
-- costs and your maximum power, only when both are plain numbers. The GCD
-- bar runs on the game's own cooldown duration object.
-- Color ranges: up to five extra bars on top of the power bar, each
-- covering the part of the bar from its value to the maximum, with its
-- own color. The client draws each fill from your power,
-- so the color changes at 40 or 80 energy without Lua comparing power.
-- Combo points get a "full" layer the same way: one more bar per pip whose
-- range is [max-1, max], so it lights up only when every pip is filled.
-- Extra resource bars: up to four more bars (mana, rage, energy, combo
-- points), in the stack or on their own mover, e.g. a feral druid's mana
-- under energy and combo points.
-- Tick marks are fixed positions from the player's own numbers and the
-- (plain) maximum. "Hide when full" only acts on plain numbers; a secret
-- value keeps the bar shown.
-- Looks: a look sets only how the bars look (heights, texts, colors, pip
-- style), never where they sit; each talent group can switch to its own.
-- Dropped by rule: mana tick estimates (the five-second spark only uses
-- your own cast), "enough power" coloring (compares secret power), gain
-- forecasts from typed-in numbers (an estimate, not game data).
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local function ExtraBarDefaults(power)
	return {
		enabled = false, power = power, place = "STACK", width = 0, height = 6,
		text = "NONE", textSize = 10, color = "POWER", customColor = { 0.3, 0.6, 1 },
		onlyCurrent = false, hideFull = false,
	}
end

local M = E:NewModule("ClassPower", {
	title = "Class Resources",
	aliases = { "Player Power" }, -- earlier title, for search and /eui
	desc = "Health, power, combo points, druid mana and a GCD bar under your character, plus Blizzard's class resource frames.",
	conflicts = { "ElvUI" },
	frames = {
		"EldoUI_PlayerPowerHolder", "EldoUI_PlayerPowerBar1Holder", "EldoUI_PlayerPowerBar2Holder",
		"EldoUI_PlayerPowerBar3Holder", "EldoUI_PlayerPowerBar4Holder", "EldoUI_TotemHolder",
	},
	movers = {
		"EldoUI_PlayerPower", "EldoUI_PlayerPowerBar1", "EldoUI_PlayerPowerBar2", "EldoUI_PlayerPowerBar3",
		"EldoUI_PlayerPowerBar4", "EldoUI_Totems",
	},
	blizzard = { "class-resources" },
	savedKeys = { "profile.modules.ClassPower" },
	optionsPage = "module:ClassPower",
	presets = { "Chunky", "Faded", "Hybrid", "PipsOnly", "Slim", "Stack", "Standard" },
	defaults = {
		width = 277,
		attachTo = "MOVER",     -- "MOVER", "PLAYER" (EldoUI player frame) or "COOLDOWNS" (Cooldown Manager)
		syncWidth = false,      -- take the width of the Cooldown Manager's essential row
		gap = 3,                -- space between the rows
		visibility = E:VisibilityDefaults(),
		health = { enabled = false, height = 8, text = "NONE", textSize = 10, classColor = true },
		power = {
			enabled = true, height = 10, text = "CURRENT", textSize = 11, classColor = false, fiveSecond = false,
			cost = true,            -- spell cost prediction while you cast
			costColor = { 1, 1, 1 },
			thresholds = "",        -- spells (IDs or names, comma separated) whose cost gets a line
			thresholdColor = { 1, 1, 1 },
			smooth = false,         -- the game animates the fill
			hideFull = false,       -- hide while full (plain values only)
			rangesEnabled = false,  -- color ranges
			rangeMode = "VALUE",    -- "VALUE" (power points) or "PERCENT" (of the maximum)
			ranges = {
				value1 = 40, color1 = { 1, 0.62, 0.15 },
				value2 = 80, color2 = { 1, 0.3, 0.2 },
				value3 = 0, color3 = { 0.65, 0.4, 1 },
				value4 = 0, color4 = { 0.3, 0.85, 1 },
				value5 = 0, color5 = { 1, 1, 1 },
			},
			ticks = {
				enabled = false,
				-- Per power type: "40, 80", "50%", "every 20" or "every 25%".
				MANA = "every 25%", RAGE = "every 10", ENERGY = "every 20",
				color = { 1, 1, 1 }, alpha = 0.6, thickness = 1, height = 100,
			},
		},
		combo = {
			enabled = true, style = "PIPS", height = 8, spacing = 3, hideEmpty = false,
			arcRadius = 46, arcSize = 12,   -- "ARC" style
			onPlate = false, plateSize = 8, -- your combo points on the target's nameplate
			colorMode = "CLASS",            -- "CLASS" or "CUSTOM" (a color per pip)
			colors = {
				pip1 = { 1, 0.96, 0.41 }, pip2 = { 1, 0.85, 0.3 }, pip3 = { 1, 0.7, 0.2 },
				pip4 = { 1, 0.5, 0.15 }, pip5 = { 1, 0.3, 0.1 },
			},
			fullColorEnabled = false,       -- every pip turns this color when all are filled
			fullColor = { 1, 0.25, 0.25 },
		},
		-- Extra resource bars (in the stack under the druid mana, or on their
		-- own mover "Resource Bar N").
		bars = {
			bar1 = ExtraBarDefaults("MANA"),
			bar2 = ExtraBarDefaults("ENERGY"),
			bar3 = ExtraBarDefaults("RAGE"),
			bar4 = ExtraBarDefaults("COMBO"),
		},
		-- Looks per talent group: "" keeps the current look.
		looks = { group1 = "", group2 = "" },
		savedLooks = { A = {}, B = {} },
		appliedLook = "",               -- "<group>:<look>" last switched to
		-- "INSET" (a strip inside the bottom of the power bar), "STACK" (a
		-- row of its own) or "PLAYER" (under the player frame). Inside the
		-- power bar keeps a cat's combo points, energy and mana within the
		-- resource band the layouts keep between the cooldown rows.
		druidMana = { enabled = true, height = 3, attach = "INSET" },
		-- Warlocks: the Soul Shards in your bags at the end of the mana bar.
		soulShards = { enabled = false },
		gcd = { enabled = false, height = 3 },
		blizzard = {
			hideCombo = true,       -- Blizzard's combo points on the target frame
			hideDruidMana = true,   -- Blizzard's druid mana bar on the player frame
			hideTotems = false,     -- Blizzard's totem timers
			hidePRD = false,        -- the personal resource display
			totemScale = 1,
			totemAttach = "MOVER",  -- "MOVER" (Totem Timers mover) or "TOTEMBAR" (above the shaman totem bar)
		},
	},
})

local issecret = issecretvalue or function() return false end
local MAX_PIPS = 5
local MAX_THRESHOLDS = 6
local DOT = E.media.dot
local Blizz = E.UFBlizzard

local Plain = E.Plain

local MAX_RANGES = 5
local MAX_TICKS = 30
local MAX_EXTRA = 4

-- Power tokens (settings) to the game's power type numbers.
local POWER_ENUM = { MANA = "Mana", RAGE = "Rage", ENERGY = "Energy", COMBO = "ComboPoints" }
local function PowerEnum(token)
	local types = Enum and Enum.PowerType
	return types and POWER_ENUM[token] and types[POWER_ENUM[token]] or nil
end

local function PowerAllowed(token)
	if token == nil then local _, current = UnitPowerType("player") token = current end
	token = Plain(token)
	if type(token) ~= "string" then return false end
	if token ~= "MANA" and token ~= "RAGE" and token ~= "ENERGY" then return true end
	return not E:StandsBack(M, token)
end

-- A bar value with the module's smooth fill: the game animates the bar
-- (StatusBar:SetValue with an interpolation), so this works with secret
-- values too.
local function SetBarValue(bar, value)
	local interpolation = E:BarInterpolation(M.db.power.smooth and true or false)
	if not pcall(bar.SetValue, bar, value, interpolation) then pcall(bar.SetValue, bar, value) end
end

-- "Hide when full": only plain numbers are compared; a secret value or a
-- missing one keeps the bar shown.
local function FullAlpha(bar, enabled, current, max)
	local alpha = 1
	if enabled then
		current, max = Plain(current), Plain(max)
		if type(current) == "number" and type(max) == "number" and max > 0 and current >= max then alpha = 0 end
	end
	bar:SetAlpha(alpha)
end

local POWER_TAGS = {
	CURRENT = "[power:current]",
	PERCENT = "[power:percent]",
	BOTH = "[power:current] | [power:percent]",
}
local HEALTH_TAGS = {
	CURRENT = "[health:current]",
	PERCENT = "[health:percent]",
	BOTH = "[health:current-percent]",
}

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local function DotPip(parent)
	local pip = CreateFrame("StatusBar", nil, parent)
	pip:SetStatusBarTexture(DOT)
	pip.bg = pip:CreateTexture(nil, "BACKGROUND")
	pip.bg:SetAllPoints()
	pip.bg:SetTexture(DOT)
	return pip
end

-- The "full" layer of a pip: the same shape on top, filled only when every
-- pip is (range [max-1, max], set in Layout).
local function FullLayer(pip, dot)
	local full = CreateFrame("StatusBar", nil, pip)
	full:SetAllPoints()
	full:SetStatusBarTexture(dot and DOT or E.media.statusbar)
	if not dot then E.statusBars[full] = true end
	full:SetFrameLevel(pip:GetFrameLevel() + 1)
	full:Hide()
	pip.full = full
	return full
end

-- The trusted file order selects the mover authority before this module.
-- Geometry admission does not grant a row lease or module ownership.
local containerGeometrySource = rawget(E, "MoverAuthoritySource")
local containerGeometryAdmission
if not issecret(containerGeometrySource) and type(containerGeometrySource) == "function" then
	local _, _, _, _, _, _, admit = containerGeometrySource()
	if not issecret(admit) and type(admit) == "function" then containerGeometryAdmission = admit end
end
local function AdmitContainerGeometry(container)
	local source = rawget(E, "MoverAuthoritySource")
	if issecret(source) or not rawequal(source, containerGeometrySource)
		or type(containerGeometryAdmission) ~= "function" then return end
	local current, _, _, _, _, _, admit = containerGeometrySource()
	if issecret(current) or type(current) ~= "function" or issecret(admit)
		or not rawequal(admit, containerGeometryAdmission) then return end
	local valid = current()
	if issecret(valid) or valid ~= true then return end
	return containerGeometryAdmission(container)
end

local RowLayout = { frames = {}, started = false, constructed = false }
local function Build(self)
	if self.holder then return end
	RowLayout.frames = {};RowLayout.started = true;RowLayout.constructed = false
	RowLayout.holder, RowLayout.container = nil, nil
	local holder = CreateFrame("Frame", "EldoUI_PlayerPowerHolder", UIParent)
	holder:SetSize(self.db.width, 20)
	self.holder = holder
	RowLayout.holder = holder

	-- The bars live in a container so "attach to" can re-anchor them without
	-- moving the mover, and so the visibility rule can fade them. Nothing
	-- here is protected.
	local container = CreateFrame("Frame", nil, holder)
	self.container = container
	RowLayout.container = container

	self.health = E:CreateStatusBar(container)
	self.healthText = E:CreateText(self.health, E.tokens.size.tiny, "CENTER")
	self.healthText:SetPoint("CENTER")

	self.power = E:CreateStatusBar(container)
	-- Color ranges: one bar per range on top of the power fill.
	self.rangeBars = {}
	for index = 1, MAX_RANGES do
		local layer = CreateFrame("StatusBar", nil, self.power)
		layer:SetStatusBarTexture(E.media.statusbar)
		E.statusBars[layer] = true
		layer:Hide()
		self.rangeBars[index] = layer
	end
	-- Spell cost: a reverse-filled bar on the right edge of the power fill.
	local cost = CreateFrame("StatusBar", nil, self.power)
	cost:SetStatusBarTexture(E.media.flat)
	cost:SetReverseFill(true)
	cost:Hide()
	self.cost = cost
	local textLayer = CreateFrame("Frame", nil, self.power)
	textLayer:SetAllPoints()
	self.textLayer = textLayer
	self.thresholds = {}
	for index = 1, MAX_THRESHOLDS do
		local line = textLayer:CreateTexture(nil, "ARTWORK", nil, 2)
		line:SetTexture(E.media.flat)
		line:SetWidth(1)
		line:Hide()
		self.thresholds[index] = line
	end
	self.ticks = {}
	for index = 1, MAX_TICKS do
		local tick = textLayer:CreateTexture(nil, "ARTWORK", nil, 1)
		tick:SetTexture(E.media.flat)
		tick:Hide()
		self.ticks[index] = tick
	end
	self.powerText = E:CreateText(textLayer, E.tokens.size.small, "CENTER")
	self.powerText:SetPoint("CENTER")
	-- Soul Shards: the count and the shard's icon at the right end.
	local shards = CreateFrame("Frame", nil, textLayer)
	shards:SetPoint("TOPRIGHT")
	shards:SetPoint("BOTTOMRIGHT")
	shards.icon = shards:CreateTexture(nil, "OVERLAY")
	shards.icon:SetPoint("RIGHT", shards, "RIGHT", -2, 0)
	E:TrimIcon(shards.icon)
	shards.count = E:CreateText(shards, E.tokens.size.small, "RIGHT")
	shards.count:SetPoint("RIGHT", shards.icon, "LEFT", -2, 0)
	shards:Hide()
	self.shards = shards

	-- Five-second rule: a spark that crosses the bar in the 5 s after a spell
	-- with a mana cost, while mana regeneration from spirit is paused.
	local spark = textLayer:CreateTexture(nil, "OVERLAY")
	spark:SetColorTexture(1, 1, 1, 0.9)
	spark:SetWidth(2)
	spark:Hide()
	self.fsrSpark = spark

	self.pips, self.arcPips = {}, {}
	for index = 1, MAX_PIPS do
		local pip = E:CreateStatusBar(container)
		pip:SetMinMaxValues(index - 1, index)
		FullLayer(pip)
		self.pips[index] = pip
		local dot = DotPip(container)
		dot:SetMinMaxValues(index - 1, index)
		FullLayer(dot, true)
		self.arcPips[index] = dot
	end

	self.druidMana = E:CreateStatusBar(container)

	-- Extra resource bars. They stay children of the container (so the
	-- visibility rule fades them too) and are anchored to the stack or to
	-- their own mover.
	self.extraBars = {}
	for index = 1, MAX_EXTRA do
		local bar = E:CreateStatusBar(container)
		bar:Hide()
		bar.text = E:CreateText(bar, E.tokens.size.tiny, "CENTER")
		bar.text:SetPoint("CENTER")
		self.extraBars[index] = bar
		RowLayout.frames[index] = bar
	end

	local gcd = E:CreateStatusBar(container)
	gcd:Hide()
	self.gcd = gcd

	E:CreateMover(holder, "EldoUI_PlayerPower", L["Class Resources"], { "CENTER", "UIParent", "CENTER", 0, -187 },
		{ sizeKeys = { width = { key = "width", min = 100, max = 400 } } })
	AdmitContainerGeometry(container)

	-- Totem timers (Blizzard's TotemFrame) get their own mover.
	local totems = CreateFrame("Frame", "EldoUI_TotemHolder", UIParent)
	totems:SetSize(150, 38)
	self.totemHolder = totems
	E:CreateMover(totems, "EldoUI_Totems", L["Totem Timers"], { "CENTER", "UIParent", "CENTER", 0, -230 })
	RowLayout.constructed = true
end

local function ComboUser()
	if E:StandsBack(M, "combo") then return false end
	local _, class = UnitClass("player")
	if class == "ROGUE" then return true end
	if class == "DRUID" then
		local _, token = UnitPowerType("player")
		return token == "ENERGY"
	end
	return false
end

local function DruidManaShown(self)
	local _, class = UnitClass("player")
	if class ~= "DRUID" or not self.db.druidMana.enabled or not PowerAllowed("MANA") then return false end
	local powerType = UnitPowerType("player")
	if issecret(powerType) or powerType == Enum.PowerType.Mana then return false end
	local max = UnitPowerMax("player", Enum.PowerType.Mana)
	return not issecret(max) and max > 0
end

local function MaxPips()
	local okMax, max = pcall(UnitPowerMax, "player", Enum.PowerType.ComboPoints)
	if okMax and Plain(max) and max > 0 then return math.min(max, MAX_PIPS) end
	return MAX_PIPS
end

local function ComboPoints()
	local ok, points = pcall(GetComboPoints, "player", "target")
	if not ok then return 0 end
	-- A secret count goes to the pips as it is; only a plain one is checked.
	if issecret(points) then return points end
	return points or 0
end

-- The EldoUI player frame, when it is on and shown.
local function PlayerFrame()
	local uf = E:GetModule("UnitFrames")
	local frame = uf and uf.active and uf.frames and uf.frames.player
	if frame and frame:IsShown() then return frame end
end

-- Resource row writer lease.
do
	local current, revoked, inactive = nil, "pending", nil
	local function Public(v) return not issecret(v) end
	local function Same(a, b) return Public(a) and Public(b) and rawequal(a, b) end
	local function Table(v) return Public(v) and type(v) == "table" and type(getmetatable(v)) == "nil" end
	local function Value(v)
		if not Public(v) then return false end
		local kind = type(v)
		return kind == "nil" or kind == "string" or kind == "boolean"
			or (kind == "number" and v == v and math.abs(v) < math.huge)
	end
	local function Frames()
		local frames, bars = RowLayout.frames, rawget(M, "extraBars")
		if not RowLayout.constructed or not Table(frames) or not Table(bars)
			or not Same(RowLayout.container, rawget(M, "container")) or not Same(RowLayout.holder, rawget(M, "holder")) then return false end
		for _, list in ipairs({ frames, bars }) do
			local count = 0
			for key in pairs(list) do
				if not Public(key) or type(key) ~= "number" or key < 1 or key > MAX_EXTRA or key % 1 ~= 0 then return false end
				count = count + 1
			end
			if count ~= MAX_EXTRA then return false end
		end
		local seen = {}
		for index = 1, MAX_EXTRA do
			local frame = rawget(frames, index)
			if not Public(frame) or (type(frame) ~= "table" and type(frame) ~= "userdata") or seen[frame]
				or not Same(rawget(bars, index), frame) then return false end
			seen[frame] = true
		end
		return true
	end
	local function Fields(pass, object, names, parent, key)
		if not Table(object) then error("Unreadable resource layout settings") end
		local values = {}
		for name in names:gmatch("%S+") do
			local value = rawget(object, name)
			if not Value(value) then error("Unreadable resource layout setting") end
			values[name] = value
		end
		pass.settings[#pass.settings + 1] = { object = object, names = names, values = values, parent = parent, key = key }
	end
	function RowLayout.Begin()
		inactive = nil
		current = { phase = "building", rows = {}, settings = {} }
		return current
	end
	local function InactiveCurrent(pass)
		return Same(pass, inactive) and not current and revoked == "inactive" and Table(pass) and Frames()
			and Table(rawget(E, "modules")) and Same(rawget(E, "modules"), pass.modules)
			and Same(rawget(pass.modules, "ClassPower"), M) and Same(rawget(M, "active"), false)
			and Same(rawget(M, "db"), pass.db) and Table(pass.db) and Same(rawget(E, "db"), pass.root) and Table(pass.root)
			and Same(rawget(E, "profileName"), pass.profile) and Public(pass.profile) and type(pass.profile) == "string" and pass.profile ~= ""
			and Same(rawget(M, "container"), pass.container) and Same(rawget(M, "holder"), pass.holder)
	end
	function RowLayout.Revoke(state)
		current = nil;revoked = state;inactive = nil
		if state ~= "inactive" then return end
		-- Raw lifecycle custody only; no native getter runs before disable.
		local pass = { modules = rawget(E, "modules"), root = rawget(E, "db"), profile = rawget(E, "profileName"),
			db = rawget(M, "db"), container = rawget(M, "container"), holder = rawget(M, "holder"), phase = "building" }
		inactive = pass
		return pass
	end
	function RowLayout.Try(pass, fn, ...)
		if pass ~= current or pass.phase == "unavailable" then return end
		local ok, result = pcall(fn, pass, ...)
		if not ok then pass.phase = "unavailable"; return end
		return result
	end
	function RowLayout.Capture(pass, self)
		if not Same(self, M) or not Table(rawget(E, "modules")) or not Same(rawget(E.modules, "ClassPower"), M)
			or not Table(rawget(M, "db")) or not Table(rawget(E, "db")) or not Public(rawget(E, "profileName"))
			or type(rawget(E, "profileName")) ~= "string" or rawget(E, "profileName") == "" then error("Resource layout context changed") end
		pass.db, pass.root, pass.profile, pass.modules = M.db, E.db, E.profileName, E.modules
		pass.active, pass.container, pass.holder, pass.bars = M.active, M.container, M.holder, M.extraBars
		if not Public(pass.active) or type(pass.active) ~= "boolean" or not Public(pass.container) or not Public(pass.holder)
			or not Table(pass.bars) or not Table(rawget(pass.db, "bars")) then error("Unreadable resource layout owner") end
		pass.configs = pass.db.bars
		pass.origins = RowLayout.frames
		if not Frames() then error("Resource row constructor identity changed") end
		Fields(pass, pass.db, "width syncWidth attachTo gap", M, "db")
		for key, names in pairs({ combo = "enabled style spacing height arcRadius arcSize", health = "enabled height",
			power = "enabled height", druidMana = "enabled height attach", gcd = "enabled height" }) do
			Fields(pass, rawget(pass.db, key), names, pass.db, key)
		end
		for index = 1, MAX_EXTRA do
			Fields(pass, rawget(pass.configs, "bar" .. index), "enabled power place width height onlyCurrent", pass.configs, "bar" .. index)
		end
	end
	function RowLayout.Valid(pass)
		if not Same(pass, current) or pass.phase == "unavailable" or not Table(rawget(E, "modules"))
			or not Same(rawget(E, "modules"), pass.modules) or not Same(rawget(pass.modules, "ClassPower"), M)
			or not Same(rawget(M, "db"), pass.db) or not Table(pass.db) or not Same(rawget(E, "db"), pass.root)
			or not Same(rawget(E, "profileName"), pass.profile) or not Same(rawget(M, "active"), pass.active)
			or not Same(rawget(M, "container"), pass.container) or not Same(rawget(M, "holder"), pass.holder)
			or not Same(rawget(M, "extraBars"), pass.bars) or not Table(pass.bars)
			or not Same(rawget(pass.db, "bars"), pass.configs) or not Table(pass.configs)
			or not Same(RowLayout.frames, pass.origins) or not Frames() then return false end
		for _, item in ipairs(pass.settings) do
			if not Table(item.object) or not Same(rawget(item.parent, item.key), item.object) then return false end
			for name in item.names:gmatch("%S+") do if not Same(rawget(item.object, name), rawget(item.values, name)) then return false end end
		end
		for index, record in pairs(pass.rows) do
			if not Same(rawget(pass.bars, index), record.frame) or not Same(rawget(pass.configs, "bar" .. index), record.cfg)
				or not Public(record.frame) or type(record.frame) ~= "table" then return false end
			if not Same(rawget(record.frame, "cfg"), record.cfg) then return false end
			if record.point and (not Same(rawget(record.frame, "SetPoint"), record.rawSetter)
				or not Same(getmetatable(record.frame), record.meta)) then return false end
		end
		return true
	end
	function RowLayout.Prepare(pass, index, frame, cfg, shown)
		if not RowLayout.Valid(pass) or index < 1 or index > MAX_EXTRA or not Public(frame) or type(frame) ~= "table"
			or not Same(rawget(pass.bars, index), frame) or not Same(rawget(pass.configs, "bar" .. index), cfg)
			or not Same(rawget(frame, "cfg"), cfg) or not Public(shown) or type(shown) ~= "boolean" then error("Resource row owner changed") end
		local place = rawget(cfg, "place")
		if not Public(place) or (place ~= "STACK" and place ~= "MOVER") then error("Unreadable resource row placement") end
		pass.rows[index] = { frame = frame, cfg = cfg, kind = place == "MOVER" and "independent" or (shown and "pending" or "inactive") }
	end
	function RowLayout.Point(pass, frame, point, relative, relativePoint, x, y, setter, before)
		if not RowLayout.Valid(pass) then error("Resource row context changed") end
		for _, record in pairs(pass.rows) do
			if Same(record.frame, frame) and record.kind == "pending" then
				if before then
					record.setter, record.rawSetter, record.meta = setter, rawget(frame, "SetPoint"), getmetatable(frame)
					if not Public(setter) or type(setter) ~= "function" or not Public(record.rawSetter) or not Public(record.meta) then error("Resource row setter changed") end
				else
					if not Same(record.setter, setter) or not Same(record.rawSetter, rawget(frame, "SetPoint")) or not Same(record.meta, getmetatable(frame))
						or not Public(point) or not Public(relativePoint) or point ~= "TOPLEFT" or not Same(relative, pass.container) or relativePoint ~= "TOPLEFT"
						or not Value(x) or type(x) ~= "number" or x ~= 0 or not Value(y) or type(y) ~= "number" then error("Resource row write changed") end
					record.point = { point, relative, relativePoint, x, y };record.kind = "live"
				end
			end
		end
	end
	function RowLayout.Finish(pass)
		if not RowLayout.Valid(pass) then error("Resource layout context changed") end
		pass.phase = "ready"
	end
	function RowLayout.Read(index, frame)
		if not Public(index) or not Public(frame) then return "unavailable", nil, nil end
		local inventory = type(index) == "string" and index == "frames"
		local notice = type(index) == "string" and index == "notice"
		if inventory or notice then
			if type(frame) ~= "nil" then return "unavailable", nil, nil end
		elseif type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > MAX_EXTRA or type(frame) ~= "table" then return "unavailable", nil, nil end
		local modules, active = rawget(E, "modules"), rawget(M, "active")
		if not Table(modules) or not Same(rawget(modules, "ClassPower"), M) or not Table(rawget(M, "db"))
			or not Table(rawget(E, "db")) or not Public(rawget(E, "profileName")) or type(rawget(E, "profileName")) ~= "string"
			or rawget(E, "profileName") == "" or not Public(active) or type(active) ~= "boolean" then return "unavailable", nil, nil end
		if active == false then
			if notice then
				local pass = inactive
				if not pass or not InactiveCurrent(pass) or pass.phase ~= "ready" then return "unavailable", nil, nil end
				return "inactive", nil, function() return InactiveCurrent(pass) and pass.phase == "ready" end
			end
			return "inactive", nil, nil
		end
		local pass = current
		if not pass then
			if RowLayout.started and not Frames() then return "unavailable", nil, nil end
			return revoked, nil, nil
		end
		if not RowLayout.Valid(pass) then return "unavailable", nil, nil end
		if pass.active == false then return "inactive", nil, nil end
		if pass.phase == "building" then return "pending", nil, nil end
		if pass.phase ~= "ready" then return "unavailable", nil, nil end
		if inventory or notice then
			local frames = {};for i = 1, MAX_EXTRA do frames[i] = rawget(pass.origins, i) end
			return "live", { count = MAX_EXTRA, frames = frames }, function() return RowLayout.Valid(pass) and pass.phase == "ready" end
		end
		local record = pass.rows[index]
		if not record or not Same(record.frame, frame) then return "unavailable", nil, nil end
		if record.kind ~= "live" then return record.kind, nil, nil end
		local point = { unpack(record.point) }
		return "live", point, function() return RowLayout.Valid(pass) and pass.phase == "ready" and Same(pass.rows[index], record) end
	end
	function RowLayout.Admit()
		local register = rawget(E, "RefreshWideConsumableLayout")
		if Public(register) and type(register) == "function" then pcall(register, E, M, RowLayout.Read, MAX_EXTRA) end
	end
	function RowLayout.Notify(pass)
		if not pass or not RowLayout.Valid(pass) or pass.phase ~= "ready" then return end
		local register = rawget(E, "RefreshWideConsumableLayout")
		if Public(register) and type(register) == "function" then pcall(register, E, M, RowLayout.Read, MAX_EXTRA, true) end
	end
	function RowLayout.CompleteInactive(pass)
		if not pass or not InactiveCurrent(pass) then return end
		pass.phase = "ready"
		local register = rawget(E, "RefreshWideConsumableLayout")
		if Public(register) and type(register) == "function" then pcall(register, E, M, RowLayout.Read, MAX_EXTRA, true) end
	end
end

-- Rows top to bottom: combo, health, power, druid mana, GCD.
local function Layout(self, lease)
	local db = self.db
	local width = self:EffectiveWidth()
	local y = 0
	local gap = db.gap
	local container = self.container
	local function Row(frame, shown, height)
		frame:ClearAllPoints()
		frame:SetShown(shown)
		if not shown then return end
		local setter = frame.SetPoint
		if lease then RowLayout.Try(lease, RowLayout.Point, frame, "TOPLEFT", container, "TOPLEFT", 0, -y, setter, true) end
		setter(frame, "TOPLEFT", container, "TOPLEFT", 0, -y)
		if lease then RowLayout.Try(lease, RowLayout.Point, frame, "TOPLEFT", container, "TOPLEFT", 0, -y, setter, false) end
		frame:SetSize(width, height)
		y = y + height + gap
	end

	local combo = db.combo
	local comboShown = combo.enabled and ComboUser()
	local maxPips = MaxPips()
	local arc = combo.style == "ARC"
	local pipWidth = (width - combo.spacing * (maxPips - 1)) / maxPips
	for index = 1, MAX_PIPS do
		local pip, dot = self.pips[index], self.arcPips[index]
		local show = comboShown and index <= maxPips
		pip.full:SetMinMaxValues(maxPips - 1, maxPips)
		dot.full:SetMinMaxValues(maxPips - 1, maxPips)
		pip:ClearAllPoints()
		dot:ClearAllPoints()
		pip:SetShown(show and not arc)
		dot:SetShown(show and arc)
		if show and not arc then
			pip:SetSize(pipWidth, combo.height)
			pip:SetPoint("TOPLEFT", container, "TOPLEFT", (index - 1) * (pipWidth + combo.spacing), -y)
		elseif show then
			-- Evenly on the upper half of a circle, left to right. The
			-- positions come from settings only.
			local radius, size = combo.arcRadius, combo.arcSize
			local angle = math.pi - (index - 0.5) * math.pi / maxPips
			local x = width / 2 + math.cos(angle) * radius
			local top = radius - math.sin(angle) * radius
			dot:SetSize(size, size)
			dot:SetPoint("CENTER", container, "TOPLEFT", x, -(y + top + size / 2))
		end
	end
	if comboShown then
		y = y + (arc and (combo.arcRadius + combo.arcSize) or combo.height) + gap
	end

	Row(self.health, db.health.enabled, db.health.height)
	E:SetFont(self.healthText, db.health.textSize)
	self.healthText:SetShown(HEALTH_TAGS[db.health.text] ~= nil)

	local powerShown = db.power.enabled and PowerAllowed()
	Row(self.power, powerShown, db.power.height)
	if not powerShown then self:StopFiveSecond() end
	E:SetFont(self.powerText, db.power.textSize)
	self.powerText:SetShown(db.power.text ~= "NONE")
	self:LayoutShards()
	self.fsrSpark:SetHeight(db.power.height)
	self.cost:ClearAllPoints()
	self.cost:SetPoint("TOPRIGHT", self.power:GetStatusBarTexture(), "TOPRIGHT")
	self.cost:SetPoint("BOTTOMRIGHT", self.power:GetStatusBarTexture(), "BOTTOMRIGHT")
	self.cost:SetWidth(width)
	local c = db.power.costColor
	self.cost:SetStatusBarColor(c[1], c[2], c[3], 0.45)
	-- Layers on the power bar, bottom to top: color ranges, spell cost,
	-- lines and text.
	local level = self.power:GetFrameLevel()
	for index, layer in ipairs(self.rangeBars) do layer:SetFrameLevel(level + index) end
	self.cost:SetFrameLevel(level + MAX_RANGES + 1)
	self.textLayer:SetFrameLevel(level + MAX_RANGES + 2)

	-- Druid mana: a strip inside the power bar, a row in the stack, or a
	-- full-width strip under the player frame.
	local druid = DruidManaShown(self)
	local underPlayer = druid and db.druidMana.attach == "PLAYER" and db.attachTo ~= "PLAYER" and PlayerFrame()
	local inset = druid and db.druidMana.attach == "INSET" and powerShown
	local manaBar = self.druidMana
	if underPlayer then
		manaBar:ClearAllPoints()
		manaBar:Show()
		manaBar:SetPoint("TOPLEFT", underPlayer, "BOTTOMLEFT", 0, -2)
		manaBar:SetPoint("TOPRIGHT", underPlayer, "BOTTOMRIGHT", 0, -2)
		manaBar:SetHeight(db.druidMana.height)
	elseif inset then
		-- Over the power fill and under its text, never taller than half
		-- the power bar.
		manaBar:ClearAllPoints()
		manaBar:Show()
		manaBar:SetPoint("BOTTOMLEFT", self.power, "BOTTOMLEFT")
		manaBar:SetPoint("BOTTOMRIGHT", self.power, "BOTTOMRIGHT")
		manaBar:SetHeight(math.max(1, math.min(db.druidMana.height, math.floor(db.power.height / 2))))
		manaBar:SetFrameLevel(level + MAX_RANGES + 1)
	else
		Row(manaBar, druid, db.druidMana.height)
	end

	-- Extra resource bars: in the stack, or on their own mover.
	for index, bar in ipairs(self.extraBars) do
		local cfg = db.bars["bar" .. index]
		bar.cfg = cfg
		local shown = self:ExtraShown(cfg)
		if lease then RowLayout.Try(lease, RowLayout.Prepare, index, bar, cfg, shown) end
		if cfg.place == "MOVER" then
			bar:ClearAllPoints()
			bar:SetShown(shown)
			if shown then
				local holder = self:ExtraHolder(index)
				local barWidth = (cfg.width or 0) > 0 and cfg.width or width
				holder:SetSize(barWidth, cfg.height)
				bar:SetSize(barWidth, cfg.height)
				bar:SetPoint("CENTER", holder, "CENTER")
				E:AddMoverContent("EldoUI_PlayerPowerBar" .. index, bar)
			end
		else
			Row(bar, shown, cfg.height)
			E:AddMoverContent("EldoUI_PlayerPower", bar)
		end
		E:SetFont(bar.text, cfg.textSize)
		bar.text:SetShown(cfg.text ~= "NONE")
	end

	Row(self.gcd, db.gcd.enabled, db.gcd.height)
	if db.gcd.enabled then self.gcd:SetAlpha(0) end

	local height = math.max(y - gap, 1)
	container:SetSize(width, height)
	self.holder:SetSize(width, height)
	self.layoutWidth = width
	-- "kept": the stack can't be measured right now and the bar keeps the
	-- spot it has on it, so everything but the spot is still laid out.
	local attached, how = self:Attach(container, db)
	if attached == false and how ~= "kept" then return end
	self:LayoutThresholds()
	self:LayoutRanges()
	self:LayoutTicks()
	self:Update()
	self:UpdateVisibility()
	self:UpdatePlateCombo()
	if attached ~= false then RowLayout.Try(lease, RowLayout.Finish) end
	local stack = E.CombatKit and E.CombatKit.CooldownStack
	if stack then stack.Changed() end
end
function M:Layout()
	local lease = RowLayout.Begin()
	RowLayout.Try(lease, RowLayout.Capture, self)
	local ok, why = pcall(Layout, self, lease)
	if not ok or lease.phase == "building" then lease.phase = "unavailable" end
	if not ok then error(why, 0) end
	pcall(RowLayout.Notify, lease)
end

-- Width of the Cooldown Manager's essential row, when it is readable.
function M:EffectiveWidth()
	if not self.db.syncWidth then return self.db.width end
	local source = E.movers.EldoUI_Cooldowns or EssentialCooldownViewer
	if source and source.GetWidth then
		local ok, width = pcall(source.GetWidth, source)
		if ok and Plain(width) and width > 20 then return math.floor(width + 0.5) end
	end
	return self.db.width
end

local InitializeCooldownStack
do
local attachRequest = 0
local sourceStack, sourceOffset, sourceBody, sourceCurrent
local binding, interrupted = false, false
InitializeCooldownStack = function()
	if sourceStack then
		local ok, current = pcall(sourceCurrent)
		return ok and not issecret(current) and current == true, "unavailable"
	end
	if binding then interrupted = true; return false, "unavailable" end
	local kit, modules = E.CombatKit, E.modules
	if issecret(kit) then return false, "unavailable" end
	if type(kit) == "nil" then return false, "pending" end
	if type(kit) ~= "table" or type(getmetatable(kit)) ~= "nil" or issecret(modules)
		or type(modules) ~= "table" or type(getmetatable(modules)) ~= "nil" then return false, "unavailable" end
	local owner = rawget(modules, "CooldownManager")
	-- "absent": no Cooldown Manager offers a stack, so there is none to join.
	if type(owner) == "nil" then return false, "absent" end
	if issecret(owner) or type(owner) ~= "table" then return false, "unavailable" end
	local read = rawget(owner, "CooldownStackSource")
	if type(read) == "nil" then return false, "absent" end
	if issecret(read) or type(read) ~= "function" then return false, "unavailable" end
	binding, interrupted = true, false
	local values = { pcall(read, owner) }
	binding = false
	if interrupted or not values[1] or #values ~= 5 then return false, "unavailable" end
	local stack, offset, hasBody, current = unpack(values, 2)
	if issecret(stack) or issecret(offset) or issecret(hasBody) or issecret(current)
		or type(stack) ~= "table" or type(getmetatable(stack)) ~= "nil" or type(offset) ~= "function"
		or type(hasBody) ~= "function" or type(current) ~= "function" then return false, "unavailable" end
	local ok, valid = pcall(current)
	if not ok or issecret(valid) or valid ~= true or not rawequal(E.CombatKit, kit) or not rawequal(E.modules, modules)
		or not rawequal(rawget(modules, "CooldownManager"), owner) or not rawequal(rawget(owner, "CooldownStackSource"), read) then return false, "unavailable" end
	sourceStack, sourceOffset, sourceBody, sourceCurrent = stack, offset, hasBody, current
	return true
end
local function OrdinaryAttach(self)
	local container = self.container
	container:ClearAllPoints()
	local mode = self.db.attachTo
	if mode == "PLAYER" then
		local target = PlayerFrame()
		if target then container:SetPoint("TOP", target, "BOTTOM", 0, -6) return end
	elseif mode == "COOLDOWNS" then
		-- First above the main cooldown row on the cooldown stack.
		local stack = E.CombatKit and E.CombatKit.CooldownStack
		local target = E.movers.EldoUI_Cooldowns or EssentialCooldownViewer
		local offset = stack and stack.Offset("power") or 0
		if target then container:SetPoint("BOTTOM", target, "TOP", 0, 6 + offset) return end
	end
	container:SetPoint("CENTER", self.holder, "CENTER")
end

function M:Attach(expected, settings)
	if issecret(self.db) or type(self.db) ~= "table" or issecret(self.db.attachTo) then return false end
	if self.db.attachTo ~= "COOLDOWNS" then return OrdinaryAttach(self) end
	attachRequest = attachRequest + 1
	local request = attachRequest
	local container, db, holder, root, profile = self.container, self.db, self.holder, E.db, E.profileName
	local modules, movers, active = E.modules, E.movers, self.active
	local function Public(...)
		for i = 1, select("#", ...) do if issecret((select(i, ...))) then return false end end
		return true
	end
	local function Same(a, b) return Public(a, b) and rawequal(a, b) end
	if not Public(modules, movers, container) or type(modules) ~= "table" or type(movers) ~= "table" or not container then return false end
	local target = rawget(movers, "EldoUI_Cooldowns") or EssentialCooldownViewer
	if not Public(target) or (type(expected) ~= "nil" and not Same(expected, container))
		or (type(settings) ~= "nil" and not Same(settings, db)) then return false end
	-- No cooldown row to hang from: the bar stays on its own mover.
	if not target then return OrdinaryAttach(self) end
	local clear, set, count, point = container.ClearAllPoints, container.SetPoint, container.GetNumPoints, container.GetPoint
	local function EntryCurrent()
		return request == attachRequest and Same(self, M) and Same(E.modules, modules) and Same(rawget(modules, self.name), self)
			and Same(E.movers, movers) and Same(rawget(movers, "EldoUI_Cooldowns") or EssentialCooldownViewer, target)
			and Same(self.container, container) and Same(self.db, db) and Same(self.holder, holder) and Same(self.active, active)
			and Same(E.db, root) and Same(E.profileName, profile) and Public(db.attachTo) and db.attachTo == "COOLDOWNS"
			and Same(container.ClearAllPoints, clear) and Same(container.SetPoint, set)
			and Same(container.GetNumPoints, count) and Same(container.GetPoint, point)
	end
	if not EntryCurrent() then return false end
	local ready, state = InitializeCooldownStack()
	if not EntryCurrent() then return false end
	if not ready then if state == "pending" or state == "absent" then return OrdinaryAttach(self) end; return false end
	local ok, present = pcall(sourceBody)
	if not ok or issecret(present) or type(present) ~= "boolean" or not InitializeCooldownStack() or not EntryCurrent() then return false end
	if not present then return OrdinaryAttach(self) end
	local stack, offset = sourceStack, sourceOffset
	local function Current() return InitializeCooldownStack() and EntryCurrent() and Same(stack, sourceStack) and Same(stack.Offset, offset) end
	local function Points()
		if not Current() then return end
		local n = count(container)
		if not Current() or not Public(n) or type(n) ~= "number" or n < 0 or n > 2 or n ~= math.floor(n) then return end
		local list = { n = n }
		for i = 1, n do
			local p = { point(container, i) }
			if not Current() or not Public(unpack(p)) then return end
			list[i] = p
		end
		return list
	end
	local prior = Points()
	if not prior then return false end
	local amount, status = offset("power", container)
	if not Current() or not Public(amount, status) then return false end
	local after = Points()
	if not after or prior.n ~= after.n then return false end
	for i = 1, prior.n do for j = 1, 5 do if not Same(prior[i][j], after[i][j]) then return false end end end
	if status == "unavailable" then
		-- The stack can't be measured right now. A bar that already has a
		-- spot keeps it until the stack lays it again; a bar with no spot
		-- yet sits on its own mover.
		if prior.n > 0 then return false, "kept" end
		set(container, "CENTER", holder, "CENTER")
		return Current()
	end
	if type(amount) ~= "number" or amount ~= amount or amount <= -math.huge or amount >= math.huge then return false end
	clear(container)
	if not Current() then return false end
	local n = count(container)
	if not Current() or not Public(n) or n ~= 0 then return false end
	set(container, "BOTTOM", target, "TOP", 0, 6 + amount)
	return Current()
end
end

-- Player Power on the cooldown stack (Modules/CombatHUD/Kit.lua): above the
-- main cooldown row while attached to it. The stack's one width watcher
-- re-lays the bar when the row's width or the stack changes.
function M:RegisterCooldownStack()
	local stack = E.CombatKit and E.CombatKit.CooldownStack
	if not stack then return end
	if not stack.IsRegistered("totemTimers") then
		-- Not on the stack itself: the watcher only tells the totem timers
		-- kept on a totem bar to look again at which side of it is clear.
		stack.Register("totemTimers", {
			side = "ABOVE", order = 90,
			frame = function() return nil end,
			relayout = function()
				if not (M.active and M.totemSide) or InCombatLockdown() then return end
				local host = M:TotemTimersHost()
				if host and M:TotemTimersSide(host) ~= M.totemSide then M:ApplyBlizzard() end
			end,
		})
	end
	if stack.IsRegistered("power") then return end
	stack.Register("power", {
		frame = function()
			if not (M.active and M.db.attachTo == "COOLDOWNS" and M.container and M.container:IsShown()) then return nil end
			return M.container
		end,
		gap = function() return 6 end,
		relayout = function()
			if not M.active then return end
			if M.db.attachTo == "COOLDOWNS" or (M.db.syncWidth and M.lastWidth ~= M:EffectiveWidth()) then
				M.lastWidth = M:EffectiveWidth()
				M:Layout()
			end
		end,
	})
end

---------------------------------------------------------------------------
-- Threshold lines: where the fixed cost of a spell sits on a full bar.
-- Only plain numbers (spell data and your maximum power) are used; the
-- lines never move with your current power.
---------------------------------------------------------------------------
local function ParseSpells(text)
	local list = {}
	for token in tostring(text or ""):gmatch("[^,;]+") do
		local id = E.ResolveSpell and E:ResolveSpell(token)
		if id then list[#list + 1] = id end
		if #list >= MAX_THRESHOLDS then break end
	end
	return list
end

-- The plain cost of a spell in the power type the bar shows, or nil.
local function SpellCost(spellID, powerType)
	if not (C_Spell and C_Spell.GetSpellPowerCost) or not Plain(spellID) then return nil end
	local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
	if not ok or type(costs) ~= "table" then return nil end
	for _, cost in ipairs(costs) do
		if type(cost) == "table" and Plain(cost.type) == powerType then return cost.cost end
	end
	return nil
end

function M:LayoutThresholds()
	local db = self.db.power
	local lines = self.thresholds
	for _, line in ipairs(lines) do line:Hide() end
	if not (db.enabled and db.thresholds ~= "") then return end
	local powerType = Plain((UnitPowerType("player")))
	local max = Plain(UnitPowerMax("player"))
	if not powerType or not max or max <= 0 then return end
	local width = self.layoutWidth or self.db.width
	local color = db.thresholdColor
	for index, spellID in ipairs(ParseSpells(db.thresholds)) do
		local cost = Plain(SpellCost(spellID, powerType))
		local line = lines[index]
		if line and type(cost) == "number" and cost > 0 and cost < max then
			line:ClearAllPoints()
			line:SetPoint("TOP", self.power, "TOPLEFT", width * cost / max, 0)
			line:SetPoint("BOTTOM", self.power, "BOTTOMLEFT", width * cost / max, 0)
			line:SetVertexColor(color[1], color[2], color[3], 0.9)
			line:Show()
		end
	end
end

---------------------------------------------------------------------------
-- Color ranges: each range is a bar from its value to the maximum, laid
-- over that part of the power bar. Positions use your (plain) maximum;
-- the fills come from the game. With a secret maximum the ranges stay off
-- and the bar keeps its normal color.
---------------------------------------------------------------------------
function M:RangeList(max)
	local db = self.db.power
	local list = {}
	for index = 1, MAX_RANGES do
		local value = tonumber(db.ranges["value" .. index]) or 0
		local at = value
		if db.rangeMode == "PERCENT" then at = value <= 100 and max * value / 100 or max end
		if value > 0 and at < max then
			list[#list + 1] = { at = at, color = db.ranges["color" .. index] or { 1, 1, 1 } }
		end
	end
	table.sort(list, function(a, b) return a.at < b.at end)
	return list
end

function M:LayoutRanges()
	local layers = self.rangeBars
	for _, layer in ipairs(layers) do
		layer:Hide()
		layer.active = nil
	end
	local db = self.db.power
	if not (db.enabled and db.rangesEnabled) then return end
	local max = Plain(UnitPowerMax("player"))
	if type(max) ~= "number" or max <= 0 then return end
	local width = self.layoutWidth or self.db.width
	for index, entry in ipairs(self:RangeList(max)) do
		local layer = layers[index]
		layer:ClearAllPoints()
		layer:SetPoint("TOPLEFT", self.power, "TOPLEFT", width * entry.at / max, 0)
		layer:SetPoint("BOTTOMRIGHT", self.power, "BOTTOMRIGHT")
		layer:SetMinMaxValues(entry.at, max)
		local c = entry.color
		layer:SetStatusBarColor(c[1], c[2], c[3])
		layer.active = true
		layer:Show()
	end
end

---------------------------------------------------------------------------
-- Tick marks: fixed marks from the player's own list for the shown power
-- type. Value marks need a plain maximum; percent marks never do.
--   "40, 80"     at 40 and 80
--   "50%"        half way
--   "every 20"   at 20, 40, 60 ...
--   "every 25%"  at 25 %, 50 %, 75 %
---------------------------------------------------------------------------
function M.ParseTicks(text, max)
	local marks = {}
	local function Add(fraction)
		if fraction > 0 and fraction < 1 and #marks < MAX_TICKS then marks[#marks + 1] = fraction end
	end
	text = strtrim(tostring(text or "")):lower()
	local every, percent = text:match("^every%s*([%d%.]+)%s*(%%?)$")
	every = tonumber(every)
	if every then
		if percent == "%" then
			if every >= 1 then
				local at = every
				while at < 100 and #marks < MAX_TICKS do
					Add(at / 100)
					at = at + every
				end
			end
		elseif max and every >= 1 then
			local at = every
			while at < max and #marks < MAX_TICKS do
				Add(at / max)
				at = at + every
			end
		end
		return marks
	end
	for token in text:gmatch("[^,;%s]+") do
		local number, isPercent = token:match("^([%d%.]+)(%%?)$")
		number = tonumber(number)
		if number and isPercent == "%" then
			Add(number / 100)
		elseif number and max then
			Add(number / max)
		end
	end
	return marks
end

function M:LayoutTicks()
	local ticks = self.ticks
	for _, tick in ipairs(ticks) do tick:Hide() end
	local db = self.db.power
	local cfg = db.ticks
	if not (db.enabled and cfg.enabled) then return end
	local _, token = UnitPowerType("player")
	token = Plain(token)
	if not token or type(cfg[token]) ~= "string" then return end
	local max = Plain(UnitPowerMax("player"))
	if type(max) ~= "number" or max <= 0 then max = nil end
	local width = self.layoutWidth or self.db.width
	local height = math.max(db.height * (cfg.height or 100) / 100, 1)
	local c = cfg.color
	for index, fraction in ipairs(M.ParseTicks(cfg[token], max)) do
		local tick = ticks[index]
		tick:ClearAllPoints()
		tick:SetSize(math.max(cfg.thickness or 1, E.pixel), height)
		tick:SetPoint("CENTER", self.power, "LEFT", width * fraction, 0)
		tick:SetVertexColor(c[1], c[2], c[3], cfg.alpha or 0.6)
		tick:Show()
	end
end

---------------------------------------------------------------------------
-- Extra resource bars
---------------------------------------------------------------------------
function M:ExtraShown(cfg)
	if not (cfg and cfg.enabled) then return false end
	if cfg.power == "COMBO" then return ComboUser() end
	if not PowerAllowed(cfg.power) then return false end
	local enum = PowerEnum(cfg.power)
	if enum == nil then return false end
	if cfg.onlyCurrent then
		local current = Plain((UnitPowerType("player")))
		if current ~= enum then return false end
	end
	local ok, max = pcall(UnitPowerMax, "player", enum)
	if not ok then return false end
	if issecret(max) then return true end
	return type(max) == "number" and max > 0
end

-- A bar's own mover, made the first time it is used (a mover always shows
-- in move mode). The layouts hang bars 2-4 below the bar before them,
-- so that bar's mover is made first, hidden until it is used.
M.extraHolders = {}
function M:ExtraHolder(index, anchorOnly)
	local holder = self.extraHolders[index]
	if not holder then
		if index > 1 then self:ExtraHolder(index - 1, true) end
		holder = CreateFrame("Frame", "EldoUI_PlayerPowerBar" .. index .. "Holder", UIParent)
		holder:SetSize(self.db.width, 6)
		self.extraHolders[index] = holder
		-- Made later than the module's other movers: tag it with the module
		-- by hand, so move mode, profile exports and the module's switch
		-- know it is one of them.
		local previous = E.currentModule
		E.currentModule = M
		holder.mover = E:CreateMover(holder, "EldoUI_PlayerPowerBar" .. index, L["Resource Bar %d"]:format(index),
			{ "CENTER", "UIParent", "CENTER", 0, -212 - (index - 1) * 12 })
		E.currentModule = previous
		holder.mover:SetShown(not anchorOnly)
	elseif not anchorOnly and holder.mover then
		holder.mover:Show()
	end
	return holder
end

local function ExtraColor(cfg)
	if cfg.color == "CLASS" then return E:ClassColor("player") end
	if cfg.color == "CUSTOM" then
		local c = cfg.customColor
		return c[1], c[2], c[3]
	end
	if cfg.power == "COMBO" then return E:ClassColor("player") end
	local color = E:PowerColorObject(cfg.power)
	if color then return color.r, color.g, color.b end
	return 0.3, 0.6, 1
end

function M:UpdateExtra()
	for _, bar in ipairs(self.extraBars) do
		local cfg = bar.cfg
		if cfg and cfg.power ~= "COMBO" and not PowerAllowed(cfg.power) then bar:Hide() end
		if cfg and cfg.power == "COMBO" and not ComboUser() then
			bar:Hide()
		elseif cfg and bar:IsShown() then
			local current, max
			if cfg.power == "COMBO" then
				current, max = ComboPoints(), MaxPips()
			else
				local enum = PowerEnum(cfg.power)
				current, max = UnitPower("player", enum), UnitPowerMax("player", enum)
			end
			pcall(bar.SetMinMaxValues, bar, 0, max)
			SetBarValue(bar, current)
			bar:SetStatusBarColor(ExtraColor(cfg))
			FullAlpha(bar, cfg.hideFull, current, max)
			if cfg.text == "CURRENT" then
				bar.text:SetText(E:FormatNumber(current))
			elseif cfg.text == "PERCENT" and cfg.power ~= "COMBO" and UnitPowerPercent and CurveConstants and CurveConstants.ScaleTo100 then
				local ok, percent = pcall(UnitPowerPercent, "player", PowerEnum(cfg.power), false, CurveConstants.ScaleTo100)
				-- type() rather than a comparison: the percent can be secret.
				if ok and type(percent) ~= "nil" then
					pcall(bar.text.SetFormattedText, bar.text, "%d%%", percent)
				else
					bar.text:SetText("")
				end
			else
				bar.text:SetText("")
			end
		end
	end
end

---------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------
function M:UpdateHealth()
	local db = self.db.health
	if not db.enabled then return end
	local bar = self.health
	pcall(bar.SetMinMaxValues, bar, 0, UnitHealthMax("player"))
	SetBarValue(bar, UnitHealth("player"))
	if db.classColor then
		bar:SetStatusBarColor(E:ClassColor("player"))
	else
		bar:SetStatusBarColor(E:GetStatusColor("gradientHigh"))
	end
	local tag = HEALTH_TAGS[db.text]
	if tag then E:RenderTag(self.healthText, tag, "player") else self.healthText:SetText("") end
end

function M:UpdatePower()
	local db = self.db.power
	if not db.enabled then return end
	if not PowerAllowed() then self.power:Hide() self:StopFiveSecond() return end
	local bar = self.power
	local current, max = UnitPower("player"), UnitPowerMax("player")
	pcall(bar.SetMinMaxValues, bar, 0, max)
	SetBarValue(bar, current)
	pcall(self.cost.SetMinMaxValues, self.cost, 0, max)
	for _, layer in ipairs(self.rangeBars) do
		if layer.active then SetBarValue(layer, current) end
	end
	FullAlpha(bar, db.hideFull, current, max)
	if db.classColor then
		bar:SetStatusBarColor(E:ClassColor("player"))
	else
		bar:SetStatusBarColor(Blizz.PowerColor("player"))
	end
	local tag = POWER_TAGS[db.text]
	if tag then E:RenderTag(self.powerText, tag, "player") else self.powerText:SetText("") end
end

---------------------------------------------------------------------------
-- Soul Shards (warlocks): the item count the game reports for your bags.
---------------------------------------------------------------------------
local SOUL_SHARD = 6265
local SOUL_SHARD_ICON = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02"
M.SOUL_SHARD = SOUL_SHARD

local function IsWarlock()
	local _, class = UnitClass("player")
	return not issecret(class) and class == "WARLOCK"
end

function M:ShardsShown()
	local db = self.db
	return db.soulShards.enabled and db.power.enabled and IsWarlock() or false
end

function M.ShardCount()
	local ok, count = pcall(C_Item.GetItemCount, SOUL_SHARD)
	count = ok and Plain(count) or nil
	return type(count) == "number" and count or 0
end

function M:LayoutShards()
	local shards = self.shards
	if not shards then return end
	local shown = self:ShardsShown()
	shards:SetShown(shown)
	if not shown then return end
	local size = math.max(6, self.db.power.height - 2)
	shards.icon:SetSize(size, size)
	shards.icon:SetTexture(C_Item.GetItemIconByID and Plain(C_Item.GetItemIconByID(SOUL_SHARD)) or E:ClientIcon(SOUL_SHARD_ICON))
	E:SetFont(shards.count, self.db.power.textSize)
	shards:SetWidth(size + 30)
	self:UpdateShards()
end

function M:UpdateShards()
	if self.shards and self.shards:IsShown() then self.shards.count:SetText(M.ShardCount()) end
end

-- Color of pip `index`: the class color, or the player's color per pip.
local function PipColor(db, index)
	if db.colorMode == "CUSTOM" then
		local c = db.colors["pip" .. index]
		if c then return c[1], c[2], c[3] end
	end
	return E:ClassColor("player")
end

-- A pip's colors are set only when they change (settings, the class
-- color), not on every power tick.
local function FillPips(pips, points, db)
	for index, pip in ipairs(pips) do
		local r, g, b = PipColor(db, index)
		pcall(pip.SetValue, pip, points)
		if pip.pipR ~= r or pip.pipG ~= g or pip.pipB ~= b then
			pip.pipR, pip.pipG, pip.pipB = r, g, b
			pip:SetStatusBarColor(r, g, b)
			if pip.bg and pip.bg.SetVertexColor then pip.bg:SetVertexColor(r * 0.25, g * 0.25, b * 0.25, 0.8) end
		end
		local full = pip.full
		if full then
			-- The full layer fills only at the maximum: the client compares.
			full:SetShown(db.fullColorEnabled and true or false)
			if db.fullColorEnabled then
				local c = db.fullColor
				if full.fullR ~= c[1] or full.fullG ~= c[2] or full.fullB ~= c[3] then
					full.fullR, full.fullG, full.fullB = c[1], c[2], c[3]
					full:SetStatusBarColor(c[1], c[2], c[3])
				end
				pcall(full.SetValue, full, points)
			end
		end
	end
end

-- With no target, or no points (when readable).
local function ComboEmpty(points)
	return not UnitExists("target") or (Plain(points) ~= nil and points == 0)
end

function M:UpdateCombo()
	if not ComboUser() then
		for index = 1, MAX_PIPS do self.pips[index]:Hide() self.arcPips[index]:Hide() end
		return
	end
	if not (self.pips[1]:IsShown() or self.arcPips[1]:IsShown()) then return end
	local points = ComboPoints()
	FillPips(self.pips, points, self.db.combo)
	FillPips(self.arcPips, points, self.db.combo)
	local alpha = (self.db.combo.hideEmpty and ComboEmpty(points)) and 0 or 1
	for index = 1, MAX_PIPS do
		self.pips[index]:SetAlpha(alpha)
		self.arcPips[index]:SetAlpha(alpha)
	end
end

function M:UpdateDruidMana()
	if not PowerAllowed("MANA") then self.druidMana:Hide() return end
	if not self.druidMana:IsShown() then return end
	local bar = self.druidMana
	pcall(bar.SetMinMaxValues, bar, 0, UnitPowerMax("player", Enum.PowerType.Mana))
	SetBarValue(bar, UnitPower("player", Enum.PowerType.Mana))
	local color = E:PowerColorObject("MANA")
	if color then bar:SetStatusBarColor(color.r, color.g, color.b) end
end

function M:Update()
	self:UpdateHealth()
	self:UpdatePower()
	self:UpdateCombo()
	self:UpdateDruidMana()
	self:UpdateExtra()
end

---------------------------------------------------------------------------
-- Visibility: the shared rule block fades the whole stack.
---------------------------------------------------------------------------
function M:MigrateVisibility()
	local db = self.db
	if db.fadeOutOfCombat ~= nil then
		-- v0.5 "fade out of combat" faded with no combat and no target.
		if db.fadeOutOfCombat then
			db.visibility = E:VisibilityFromLegacy("combatOrTarget", db.outOfCombatAlpha or 0.4)
		end
		db.fadeOutOfCombat, db.outOfCombatAlpha = nil, nil
	end
end

function M:UpdateVisibility()
	if not self.container then return end
	if E:IsVisibilityAttached(self.container) then
		E:UpdateVisibility(self.container)
	else
		E:AttachVisibility(self.container, self.db.visibility, {
			forceShow = function() return E:IsMoveMode() end,
		})
	end
end

---------------------------------------------------------------------------
-- Spell cost prediction: the cost of the spell you are casting, taken
-- from the spell's own cost info, drawn at the end of the power fill.
---------------------------------------------------------------------------
function M:ShowCost(spellID)
	local cost = self.cost
	cost:Hide()
	local db = self.db.power
	if not (db.enabled and db.cost and self.power:IsShown()) then return end
	local powerType = Plain((UnitPowerType("player")))
	if not powerType then return end
	local amount = SpellCost(spellID, powerType)
	if amount == nil then return end
	if Plain(amount) and amount <= 0 then return end
	pcall(cost.SetMinMaxValues, cost, 0, UnitPowerMax("player"))
	if pcall(cost.SetValue, cost, amount) then cost:Show() end
end

function M:HideCost()
	self.cost:Hide()
end

---------------------------------------------------------------------------
-- GCD bar: the game's duration of the global cooldown, from the combat
-- kit's one cooldown source (K.Cooldowns in Modules/CombatHUD/Kit.lua),
-- which also says when the game reports a cooldown change.
---------------------------------------------------------------------------
local GCD_KEY = "ClassPower:gcd"

local function Cooldowns()
	return E.CombatKit and E.CombatKit.Cooldowns
end

local function GCDOnUpdate(bar, elapsed)
	bar.elapsed = (bar.elapsed or 0) + elapsed
	if bar.elapsed < 0.05 then return end
	bar.elapsed = 0
	local duration = bar.duration
	local ok, active = false, nil
	if duration then ok, active = pcall(duration.IsActive, duration) end
	if not ok then active = false end
	if issecret(active) then
		if not pcall(bar.SetAlphaFromBoolean, bar, active, 1, 0) then bar:SetAlpha(1) end
		return
	end
	if active then
		bar:SetAlpha(1)
	else
		bar:SetAlpha(0)
		bar.duration = nil
		bar:SetScript("OnUpdate", nil)
	end
end

function M:StartGCD()
	local bar = self.gcd
	if not (self.db.gcd.enabled and bar:IsShown()) then return end
	local source = Cooldowns()
	if not (source and bar.SetTimerDuration) then return end
	local duration = source.GCDDuration()
	if duration == nil then return end
	local direction = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
	if not pcall(bar.SetTimerDuration, bar, duration, nil, direction) then return end
	bar:SetStatusBarColor(E:ClassColor("player"))
	bar.duration = duration
	bar.elapsed = 1
	bar:SetScript("OnUpdate", GCDOnUpdate)
end

---------------------------------------------------------------------------
-- Five-second rule. The trigger is the player's own cast (never secret) of
-- a spell whose fixed cost is mana; the current mana is never read.
---------------------------------------------------------------------------
local FSR_TIME = 5
local fiveSecond

local function CostsMana(spellID)
	local amount = Plain(SpellCost(spellID, Enum.PowerType.Mana))
	return type(amount) == "number" and amount > 0
end

function M:FiveSecondAllowed()
	local db = self.db and self.db.power
	return self.active and db and db.enabled and db.fiveSecond and self.power and self.power:IsShown()
		and not E:StandsBack(self, "fiveSecond")
end

function M:StopFiveSecond()
	local own = fiveSecond
	if not own then return end
	fiveSecond = nil
	if Plain(self.fsrStart) == own.start then self.fsrStart = nil end
	if own.bar:GetScript("OnUpdate") == own.update then own.bar:SetScript("OnUpdate", nil) end
	if not fiveSecond and self.fsrSpark == own.spark then own.spark:Hide() end
end

function M:OnStandBack(feature)
	if feature == "fiveSecond" then self:StopFiveSecond()
	elseif feature == "combo" or feature == "MANA" or feature == "RAGE" or feature == "ENERGY" then self:Relayout() end
end

function M:StartFiveSecond()
	self:StopFiveSecond()
	if not self:FiveSecondAllowed() then return end
	local spark, bar = self.fsrSpark, self.power
	if not spark or bar:GetScript("OnUpdate") then return end
	local width = self.layoutWidth or self:EffectiveWidth()
	local own = { bar = bar, spark = spark, profile = self.db, settings = self.db.power, start = GetTime() }
	own.update = function()
		if fiveSecond ~= own then return end
		if M.db ~= own.profile or M.db.power ~= own.settings or M.power ~= bar or M.fsrSpark ~= spark
			or bar:GetScript("OnUpdate") ~= own.update or not M:FiveSecondAllowed() then
			M:StopFiveSecond()
			return
		end
		local progress = (GetTime() - own.start) / FSR_TIME
		if progress >= 1 then M:StopFiveSecond() return end
		spark:ClearAllPoints()
		spark:SetPoint("CENTER", bar, "LEFT", width * progress, 0)
	end
	fiveSecond = own
	self.fsrStart = own.start
	bar:SetScript("OnUpdate", own.update)
	if fiveSecond ~= own then return end
	if self.db ~= own.profile or self.db.power ~= own.settings or self.power ~= bar or self.fsrSpark ~= spark
		or bar:GetScript("OnUpdate") ~= own.update or not self:FiveSecondAllowed() then
		self:StopFiveSecond()
		return
	end
	spark:Show()
end

---------------------------------------------------------------------------
-- Combo points on the target's nameplate: a small pip row hung
-- under the plate. EldoUI plates hand us their own anchor; Blizzard plates
-- get the row under the plate frame. Forbidden plates are never touched.
---------------------------------------------------------------------------
function M:BuildPlateCombo()
	if self.plateCombo then return end
	local row = CreateFrame("Frame", nil, UIParent)
	row:Hide()
	row.pips = {}
	for index = 1, MAX_PIPS do
		local pip = E:CreateStatusBar(row)
		pip:SetMinMaxValues(index - 1, index)
		FullLayer(pip)
		row.pips[index] = pip
	end
	self.plateCombo = row
end

-- True while the Nameplates module reports plates through its callbacks.
function M:PlatesReport()
	local np = E:GetModule("Nameplates")
	return np and np.active and np.GetPlateMode and np:GetPlateMode() ~= "OFF" or false
end

-- The Nameplates module's plate callbacks (ADDED/REMOVED/LAYOUT/MODE):
-- the combo point row follows the target's plate.
local plateQueued = false
local function PlateComboNext()
	plateQueued = false
	if M.active then M:UpdatePlateCombo() end
end

local function OnPlateEvent(event, _, nameplate)
	if not M.active then return end
	if event == "MODE" then
		M:UpdatePlateCombo()
		return
	end
	-- Only a rogue or cat with combo points on the plate has work here.
	if not (M.db.combo.onPlate and ComboUser()) then return end
	-- Only the target's plate matters (frames compare, units may be secret).
	local row = M.plateCombo
	local ok, target = pcall(C_NamePlate.GetNamePlateForUnit, "target")
	local isTarget = ok and target ~= nil and target == nameplate
	if event == "LAYOUT" then
		if row and row:IsShown() and isTarget then M:UpdatePlateCombo() end
	elseif (isTarget or (row and row:GetParent() == nameplate)) and not plateQueued then
		-- The target's plate came or went: next frame, once.
		plateQueued = true
		C_Timer.After(0, PlateComboNext)
	end
end

function M:HookPlates()
	local np = E:GetModule("Nameplates")
	if np and np.RegisterPlateCallback then np:RegisterPlateCallback("ClassPower", OnPlateEvent) end
end

local function TargetPlateAnchor()
	local np = E:GetModule("Nameplates")
	if np and np.active and np.GetPlateAnchor then
		local frame, point, relPoint, y = np:GetPlateAnchor("target")
		if frame then return frame, point, relPoint, y end
	end
	if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
	if not ok or not plate or E.FrameCheck(plate, "IsForbidden") then return nil end
	return plate, "TOP", "BOTTOM", 0
end

function M:UpdatePlateCombo()
	local combo = self.db.combo
	if not (self.active and combo.onPlate and ComboUser()) then
		if self.plateCombo then self.plateCombo:Hide() end
		return
	end
	self:BuildPlateCombo()
	local row = self.plateCombo
	local anchor, point, relPoint, y = TargetPlateAnchor()
	if not anchor then
		row:Hide()
		return
	end
	local size, spacing, count = combo.plateSize, 2, MaxPips()
	row:SetParent(anchor)
	row:ClearAllPoints()
	row:SetPoint(point, anchor, relPoint, 0, y)
	row:SetSize(count * size * 1.6 + (count - 1) * spacing, size)
	row:SetFrameLevel(anchor:GetFrameLevel() + 10)
	for index, pip in ipairs(row.pips) do
		pip:ClearAllPoints()
		pip:SetShown(index <= count)
		pip:SetSize(size * 1.6, size)
		pip:SetPoint("LEFT", row, "LEFT", (index - 1) * (size * 1.6 + spacing), 0)
		pip.full:SetMinMaxValues(count - 1, count)
	end
	local points = ComboPoints()
	FillPips(row.pips, points, combo)
	row:SetAlpha((combo.hideEmpty and ComboEmpty(points)) and 0 or 1)
	row:Show()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local PLAYER_UNIT = {
	UNIT_POWER_UPDATE = true, UNIT_POWER_FREQUENT = true, UNIT_MAXPOWER = true, UNIT_DISPLAYPOWER = true,
	UNIT_HEALTH = true, UNIT_MAXHEALTH = true,
	UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true,
	UNIT_SPELLCAST_INTERRUPTED = true, UNIT_SPELLCAST_SUCCEEDED = true, UNIT_SPELLCAST_DELAYED = true,
}

local EVENTS = {
	UNIT_POWER_UPDATE = "power",
	UNIT_POWER_FREQUENT = "power",
	UNIT_HEALTH = "health",
	UNIT_MAXHEALTH = "health",
	UNIT_MAXPOWER = "layout",
	UNIT_DISPLAYPOWER = "layout",
	UPDATE_SHAPESHIFT_FORM = "layout",
	SPELLS_CHANGED = "thresholds",
	PLAYER_TARGET_CHANGED = "combo",
	COMBO_TARGET_CHANGED = "combo",
	UNIT_POWER_POINT_CHARGE = "combo",
	NAME_PLATE_UNIT_ADDED = "plate",
	NAME_PLATE_UNIT_REMOVED = "plate",
	UNIT_SPELLCAST_START = "cost",
	UNIT_SPELLCAST_DELAYED = "cost",
	UNIT_SPELLCAST_STOP = "nocost",
	UNIT_SPELLCAST_FAILED = "nocost",
	UNIT_SPELLCAST_INTERRUPTED = "nocost",
	UNIT_SPELLCAST_SUCCEEDED = "cast",
	PLAYER_REGEN_ENABLED = "regen",
	PLAYER_ENTERING_WORLD = "layout",
	ACTIVE_TALENT_GROUP_CHANGED = "looks",
	BAG_UPDATE_DELAYED = "shards",
}

local function OnEvent(_, event, unit, _, spellID)
	local self = M
	if not self.active then return end
	if PLAYER_UNIT[event] and unit ~= "player" then return end
	local kind = EVENTS[event]
	if kind == "power" then
		self:UpdatePower()
		self:UpdateCombo()
		self:UpdateDruidMana()
		self:UpdateExtra()
		if self.plateCombo and self.plateCombo:IsShown() then self:UpdatePlateCombo() end
	elseif kind == "health" then
		self:UpdateHealth()
	elseif kind == "combo" then
		self:UpdateCombo()
		self:UpdateExtra()
		self:UpdatePlateCombo()
	elseif kind == "plate" then
		-- The target's plate may have just appeared or gone; one frame later
		-- it is set up. EldoUI's plates report through their callback.
		if self:PlatesReport() then return end
		C_Timer.After(0, function() if M.active then M:UpdatePlateCombo() end end)
	elseif kind == "cost" then
		self:ShowCost(spellID)
	elseif kind == "nocost" then
		self:HideCost()
	elseif kind == "cast" then
		self:HideCost()
		self:StartGCD()
		if self:FiveSecondAllowed() and CostsMana(spellID) then
			self:StartFiveSecond()
		end
	elseif kind == "thresholds" then
		self:LayoutThresholds()
	elseif kind == "looks" then
		if self:CheckLook() then self:Relayout() end
	elseif kind == "shards" then
		self:UpdateShards()
	else
		-- "layout" (form, display power or maximum changed) and "regen".
		self:Relayout()
	end
end

-- Nothing in the stack is protected (see Build), so a druid shifting into
-- cat form mid-fight gets combo points and the druid mana row at once, and
-- a new maximum moves the ticks and threshold lines. Before the
-- first build (OnEnable waits for the end of combat) there is nothing to
-- lay out yet.
function M:Relayout()
	if self.container then self:Layout() end
end

---------------------------------------------------------------------------
-- Blizzard's class resources ("class-resources" element)
---------------------------------------------------------------------------
local ID = "class-resources"
local totemSkinned = setmetatable({}, { __mode = "k" })

local function SkinTotems()
	if not Blizz.Usable(TotemFrame) then return end
	for _, button in ipairs({ TotemFrame:GetChildren() }) do
		if not totemSkinned[button] and button.Icon then
			totemSkinned[button] = true
			E:SkinAlphaZero(button.Border)
			local icon = button.Icon
			if icon.TextureMask and icon.Texture and icon.Texture.RemoveMaskTexture then
				pcall(icon.Texture.RemoveMaskTexture, icon.Texture, icon.TextureMask)
			end
			if icon.Texture then E:TrimIcon(icon.Texture) end
			local backdrop = CreateFrame("Frame", nil, button)
			backdrop:SetPoint("TOPLEFT", icon, "TOPLEFT", -E.pixel, E.pixel)
			backdrop:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", E.pixel, -E.pixel)
			backdrop:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
			E:SetTemplate(backdrop)
			if button.Duration then E:SetFont(button.Duration, E.tokens.size.small) end
		end
	end
end

local prdHooked = setmetatable({}, { __mode = "k" })
local function SkinPRD()
	local prd = PersonalResourceDisplayFrame
	if not Blizz.Usable(prd) then return end
	local bars = { prd.HealthBarsContainer and prd.HealthBarsContainer.healthBar, prd.PowerBar, prd.AlternatePowerBar }
	for _, bar in ipairs(bars) do
		if Blizz.Usable(bar) then
			bar:SetStatusBarTexture(E.media.statusbar)
			for _, key in ipairs({ "TextString", "LeftText", "RightText" }) do
				if bar[key] then E:SetFont(bar[key], E.tokens.size.small) end
			end
			if not prdHooked[bar] then
				prdHooked[bar] = true
				-- The game's own art can be a secret value, so it is never
				-- compared: a guard keeps our own call from running the hook
				-- again (as the cast bars in UnitFrames do). Nothing happens
				-- while the module is off.
				hooksecurefunc(bar, "SetStatusBarTexture", function(self)
					if prdHooked[self] == "busy" or not (M.active and E:BlizzardAllowed(ID, "skin")) then return end
					prdHooked[self] = "busy"
					pcall(self.SetStatusBarTexture, self, E.media.statusbar)
					prdHooked[self] = true
				end)
			end
		end
	end
end

-- Action Bars v0.5.x had "Timers above the bar" (totem.attachTimers) for
-- the same TotemFrame. The timers are owned here now; carry the player's
-- choice over once per profile.
function M:MigrateTotemTimers()
	local db = self.db.blizzard
	local bars = E.db.modules and E.db.modules.ActionBars
	local totem = type(bars) == "table" and bars.totem
	if type(totem) == "table" and totem.attachTimers then
		db.totemAttach = "TOTEMBAR"
		totem.attachTimers = nil
	end
end

-- The totem bar the totem timers sit on: Shaman Totems' bar while it
-- draws, else Blizzard's totem bar while Action Bars holds it on its mover
-- (shown, not hidden). nil: the timers use their own mover.
function M:TotemTimersHost()
	if select(2, UnitClass("player")) ~= "SHAMAN" then
		-- The class bar takes the timers' spot for the other classes, as
		-- Shaman Totems' bar does for shamans.
		local classBar, own = E.ClassBar, _G.EldoUI_ClassBar
		if classBar and classBar.active and classBar.Drawing and classBar:Drawing() and own then return own end
		return nil
	end
	local totems = E.Totems
	local own = _G.EldoUI_ShamanTotems
	if totems and totems.Drawing and totems:Drawing() and own and own:IsShown() then return own end
	local bar, holder = MultiCastActionBarFrame, _G.EldoUI_TotemBar
	if not (bar and holder and Blizz.Usable(bar) and holder:IsShown()) then return nil end
	if not E:BlizzardAllowed("totem-bar", "move") or E:BlizzardHidden("totem-bar") then return nil end
	if totems and totems.HoldsBlizzard and totems:HoldsBlizzard(bar) then return nil end
	return holder
end

-- The totem timers' box for the placement rule: Blizzard's frame at the
-- chosen scale, never smaller than a full row of four timers.
local TOTEM_GAP = 4
local TOTEM_MIN_WIDTH, TOTEM_MIN_HEIGHT = 150, 38
-- side -> the timers' point, the bar's point, x, y
local TOTEM_SPOTS = {
	ABOVE = { "BOTTOM", "TOP", 0, TOTEM_GAP },
	BELOW = { "TOP", "BOTTOM", 0, -TOTEM_GAP },
	RIGHT = { "LEFT", "RIGHT", TOTEM_GAP, 0 },
	LEFT = { "RIGHT", "LEFT", -TOTEM_GAP, 0 },
}

function M:TotemTimersSide(host)
	local stack = E.CombatKit and E.CombatKit.CooldownStack
	if not (stack and stack.SideFor) then return "ABOVE" end
	local scale = tonumber(self.db.blizzard.totemScale) or 1
	local width, height = TOTEM_MIN_WIDTH, TOTEM_MIN_HEIGHT
	if TotemFrame and TotemFrame.GetSize then
		local ok, w, h = pcall(TotemFrame.GetSize, TotemFrame)
		if ok and Plain(w) and Plain(h) and type(w) == "number" and type(h) == "number" then
			width, height = math.max(width, w), math.max(height, h)
		end
	end
	return stack.SideFor(host, width * scale, height * scale, TOTEM_GAP)
end

function M:ApplyBlizzard()
	if not E:BlizzardAllowed(ID) then return end
	local db = self.db.blizzard
	local hide = E:BlizzardHidden(ID)
	if hide and db.hideCombo and Blizz.Usable(ComboFrame) then Blizz.Hide(ID, ComboFrame, true) end
	if hide and db.hideDruidMana and Blizz.Usable(AlternatePowerBar) then Blizz.Hide(ID, AlternatePowerBar) end
	if hide and db.hidePRD and Blizz.Usable(PersonalResourceDisplayFrame) then Blizz.Hide(ID, PersonalResourceDisplayFrame) end
	-- The Totem Timers box shows only while the timers sit on it.
	local onMover = false
	if hide and db.hideTotems and Blizz.Usable(TotemFrame) then
		Blizz.Hide(ID, TotemFrame, true)
	else
		if E:BlizzardAllowed(ID, "skin") then SkinTotems() end
		-- Moving the totem timers also takes them out of the player frame, so
		-- they stay visible when EldoUI replaces Blizzard's player frame.
		if E:BlizzardAllowed(ID, "move") and Blizz.Usable(TotemFrame) then
			-- "Totem bar": on the totem bar EldoUI places. Without
			-- one the timers use their own mover: they never follow a totem
			-- bar EldoUI doesn't place (hidden by Shaman Totems, or left
			-- where Blizzard puts it), which can sit in the chat.
			-- Shaman Totems' bar, and the class bar for the other classes,
			-- take the timers' own spot: timers kept with it always sit on it.
			local host = self:TotemTimersHost()
			if host and (db.totemAttach == "TOTEMBAR" or host == _G.EldoUI_ShamanTotems or host == _G.EldoUI_ClassBar) then
				-- Above the bar, else under it, else beside it: the first spot
				-- that keeps clear of the cooldown rows and the class
				-- resources (one rule for the whole cooldown area,
				-- Modules/CombatHUD/Kit.lua).
				self.totemSide = self:TotemTimersSide(host)
				local spot = TOTEM_SPOTS[self.totemSide] or TOTEM_SPOTS.ABOVE
				Blizz.Place(ID, TotemFrame, host, db.totemScale, spot[1], UIParent, spot[2], spot[3], spot[4])
			else
				self.totemSide = nil
				Blizz.Place(ID, TotemFrame, "EldoUI_Totems", db.totemScale, "CENTER", UIParent)
				local totems = E.Totems
				onMover = not (totems and totems.HoldsBlizzard and totems:HoldsBlizzard(TotemFrame))
			end
		end
	end
	-- Shown for every class otherwise: move mode keeps the spot visible.
	local mover = E.movers.EldoUI_Totems
	if mover and (select(2, UnitClass("player")) == "SHAMAN" or self.totemSide) then mover:SetShown(onMover) elseif mover then mover:Show() end
	if E:BlizzardAllowed(ID, "skin") and not (hide and db.hidePRD) then SkinPRD() end
end

E:RegisterBlizzardHandler(ID, {
	owner = "ClassPower",
	apply = function() M:ApplyBlizzard() end,
	undo = function()
		if TotemFrame then Blizz.Unplace(TotemFrame) end
	end,
	reload = { skin = true, hide = true, replace = true, move = true },
	install = { replace = true, skin = true, move = true },
	refreshModule = false,
})

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", OnEvent)

-- The player's own unit events come for the player only (the game filters,
-- so a raid's and the nameplates' health, power and casts never reach the
-- handler; its unit check stays as a guard). UNIT_POWER_FREQUENT already
-- sends every power change, so UNIT_POWER_UPDATE is left out while it is
-- there: one change, one refresh.
function M:RegisterEvents()
	local frequent = pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_POWER_FREQUENT", "player")
	for event in pairs(EVENTS) do
		if event == "UNIT_POWER_UPDATE" and frequent then
			pcall(eventFrame.UnregisterEvent, eventFrame, event)
		elseif PLAYER_UNIT[event] then
			pcall(eventFrame.RegisterUnitEvent, eventFrame, event, "player")
		else
			pcall(eventFrame.RegisterEvent, eventFrame, event)
		end
	end
end

function M:OnInitialize()
	InitializeCooldownStack()
	self:MigrateTotemTimers()
	self:MigrateVisibility()
	RowLayout.Admit()
end

function M:OnEnable()
	E:RunOutOfCombat(function()
		Build(self)
		self.holder:Show()
		self.totemHolder:Show()
		self:RegisterEvents()
		local source = Cooldowns()
		if source then
			source.Subscribe(GCD_KEY, function(changes)
				if M.active and changes.spells and M.gcd and M.gcd:IsShown() and not M.gcd.duration then M:StartGCD() end
			end)
		end
		self:CheckLook()
		self:Layout()
		self:ApplyBlizzard()
		if Blizz.Usable(TotemFrame) and type(TotemFrame.Update) == "function" and not self.totemHooked then
			-- New totem buttons appear the first time a totem goes down.
			self.totemHooked = true
			hooksecurefunc(TotemFrame, "Update", function()
				if M.active and E:BlizzardAllowed(ID, "skin") then SkinTotems() end
			end)
		end
		-- Width sync with the Cooldown Manager: its size changes with the
		-- number of tracked spells; the cooldown stack's watcher checks it.
		self:RegisterCooldownStack()
		self:HookPlates()
	end)
end

function M:OnDisable()
	local revoked = RowLayout.Revoke("inactive")
	self:StopFiveSecond()
	eventFrame:UnregisterAllEvents()
	local source = Cooldowns()
	if source then source.Unsubscribe(GCD_KEY) end
	if self.container then E:DetachVisibility(self.container) end
	if self.holder then self.holder:Hide() end
	if self.plateCombo then self.plateCombo:Hide() end
	if self.gcd then self.gcd:SetScript("OnUpdate", nil) end
	pcall(RowLayout.CompleteInactive, revoked)
end

function M:OnProfileChanged()
	RowLayout.Revoke("unavailable")
	self:StopFiveSecond()
	self:MigrateTotemTimers()
	self:MigrateVisibility()
	if self.active then
		E:RunOutOfCombat(function()
			self:CheckLook()
			self:Layout()
			self:ApplyBlizzard()
		end)
	end
end

---------------------------------------------------------------------------
-- Looks: how the bars look, never where they sit or which bars are on.
-- Each talent group can name a look; it is put on once when that group
-- becomes active (or when the choice changes), so later edits stay.
---------------------------------------------------------------------------
local LOOK_PATHS = {
	"power.height", "power.text", "power.textSize", "power.classColor", "power.smooth",
	"power.rangesEnabled", "power.rangeMode", "power.ranges", "power.ticks", "power.costColor", "power.thresholdColor",
	"combo.style", "combo.height", "combo.spacing", "combo.arcRadius", "combo.arcSize",
	"combo.colorMode", "combo.colors", "combo.fullColorEnabled", "combo.fullColor",
	"health.height", "health.text", "health.textSize", "health.classColor",
	"druidMana.height", "gcd.height",
}
M.LOOK_PATHS = LOOK_PATHS

local BASE_LOOK = {
	["power.text"] = "CURRENT", ["power.textSize"] = 11, ["power.classColor"] = false,
	["power.rangesEnabled"] = false, ["power.ticks.enabled"] = false,
	["combo.style"] = "PIPS", ["combo.colorMode"] = "CLASS", ["combo.fullColorEnabled"] = false,
}
local function Look(settings)
	local look = CopyTable(BASE_LOOK)
	for path, value in pairs(settings) do look[path] = value end
	return look
end

M.LOOKS = {
	{ key = "standard", title = "Standard", look = Look({ ["power.height"] = 10, ["combo.height"] = 8, ["combo.spacing"] = 3 }) },
	{ key = "slim", title = "Slim", look = Look({ ["power.height"] = 6, ["power.text"] = "NONE", ["combo.height"] = 6, ["combo.spacing"] = 2 }) },
	{ key = "chunky", title = "Chunky", look = Look({ ["power.height"] = 14, ["power.text"] = "BOTH", ["power.textSize"] = 12,
		["combo.height"] = 6, ["combo.spacing"] = 4 }) },
	{ key = "arc", title = "Arc of dots", look = Look({ ["power.height"] = 10, ["combo.style"] = "ARC", ["combo.arcRadius"] = 46, ["combo.arcSize"] = 12 }) },
	{ key = "zones", title = "Energy zones", look = Look({ ["power.height"] = 12, ["power.rangesEnabled"] = true, ["power.rangeMode"] = "VALUE",
		["power.ranges.value1"] = 40, ["power.ranges.value2"] = 80, ["power.ticks.enabled"] = true,
		["combo.height"] = 8, ["combo.spacing"] = 3, ["combo.fullColorEnabled"] = true }) },
	{ key = "caster", title = "Caster", look = Look({ ["power.height"] = 12, ["power.text"] = "BOTH", ["power.ticks.enabled"] = true,
		["power.ticks.MANA"] = "every 25%", ["combo.height"] = 6, ["combo.spacing"] = 2 }) },
}

local function SpecGroup()
	if C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup then
		local ok, group = pcall(C_SpecializationInfo.GetActiveSpecGroup)
		if ok and Plain(group) then return group end
	end
	return 1
end

function M:LookSettings(key)
	for _, look in ipairs(self.LOOKS) do
		if look.key == key then return look.look end
	end
	local saved = self.db.savedLooks[key]
	if type(saved) == "table" and next(saved) then return saved end
end

function M:ApplyLook(key)
	local look = self:LookSettings(key)
	if not look then return false end
	for path, value in pairs(look) do
		E.SetPath(self.db, path, type(value) == "table" and CopyTable(value) or value)
	end
	return true
end

function M:SaveLook(slot)
	local saved = {}
	for _, path in ipairs(LOOK_PATHS) do
		local value = E.GetPath(self.db, path)
		if value ~= nil then saved[path] = type(value) == "table" and CopyTable(value) or value end
	end
	self.db.savedLooks[slot] = saved
	E:Print(L["Class Resources: saved look %s."]:format(slot))
end

-- Puts on the active talent group's look once per change. True when the
-- settings changed.
function M:CheckLook()
	local group = SpecGroup()
	local key = self.db.looks["group" .. group] or ""
	local tag = key ~= "" and (group .. ":" .. key) or ""
	if tag == self.db.appliedLook then return false end
	self.db.appliedLook = tag
	if key == "" then return false end
	return self:ApplyLook(key)
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local function ElementOff() return not E:BlizzardAllowed(ID) end
local function Off(path)
	return function() return not E.GetPath(M.db, path) end
end
local function NotArc() return not M.db.combo.enabled or M.db.combo.style ~= "ARC" end
local function NotPips() return not M.db.combo.enabled or M.db.combo.style == "ARC" end
local function NotCustomPips() return not M.db.combo.enabled or M.db.combo.colorMode ~= "CUSTOM" end
local TEXT_VALUES = { NONE = "Hidden", CURRENT = "Current", PERCENT = "Percent", BOTH = "Current | percent" }

-- Preview card in the shared window look: five combo points with three lit
-- and the power bar under them, in the bars' width, heights and colors
-- (E:ConfigSample, Core/MoverSamples.lua), then a fold section for your
-- class with what the stack shows for it, as value rows. The card's text
-- is window text (no outline); the bars on screen keep the text outline
-- you picked.
local POWER_NAMES = { MANA = "Mana", RAGE = "Rage", ENERGY = "Energy" }
local COMBO_STYLES = { PIPS = "Pips in a row", ARC = "Arc of dots" }
local DRUID_MANA_PLACES = { INSET = "Inside the power bar", STACK = "In the stack", PLAYER = "Under the player frame" }
local PREVIEW_SAMPLE_HEIGHT = 34
local previewFolded = false

local function PlayerClassToken()
	local localized, class = UnitClass("player")
	if issecret(class) then return nil end
	return class, (not issecret(localized) and type(localized) == "string") and localized or class
end

-- The class section's rows: { label, value, kind }. Four rows for every
-- class, so the card keeps one height.
function M:PreviewRows()
	local db = self.db
	local class = PlayerClassToken()
	local rows = {}
	local _, token = UnitPowerType("player")
	token = (not issecret(token) and POWER_NAMES[token]) and token or (class == "WARRIOR" and "RAGE" or class == "ROGUE" and "ENERGY" or "MANA")
	if db.power.enabled then
		rows[1] = { L["Power bar"], L["%s, %d px"]:format(L[POWER_NAMES[token]], db.power.height) } -- no-plural
	else
		rows[1] = { L["Power bar"], L["Off"], "secondary" }
	end
	rows[2] = { L["Text on the bar"], L[TEXT_VALUES[db.power.text] or "Hidden"], db.power.text == "NONE" and "secondary" or nil }
	if class == "ROGUE" or class == "DRUID" then
		rows[3] = { L["Combo points"], db.combo.enabled and L[COMBO_STYLES[db.combo.style] or "Pips in a row"] or L["Off"], not db.combo.enabled and "secondary" or nil }
	else
		rows[3] = { L["Combo points"], L["Not used by your class"], "secondary" }
	end
	if class == "DRUID" then
		rows[4] = { L["Druid mana in forms"], db.druidMana.enabled and L[DRUID_MANA_PLACES[db.druidMana.attach] or "Inside the power bar"] or L["Off"],
			not db.druidMana.enabled and "secondary" or nil }
	elseif class == "WARLOCK" then
		if self:ShardsShown() then
			rows[4] = { L["Soul Shards"], E:Plural(M.ShardCount(), "%d in your bags", "%d in your bags"):format(M.ShardCount()) }
		else
			rows[4] = { L["Soul Shards"], L["Off"], "secondary" }
		end
	else
		rows[4] = { L["Global cooldown bar"], db.gcd.enabled and L["On"] or L["Off"], not db.gcd.enabled and "secondary" or nil }
	end
	return rows
end

local function UpdatePreview(canvas)
	local db = M.db
	if not (canvas and db and canvas.sample) then return end
	local combo, power = db.combo or {}, db.power or {}
	local class, className = PlayerClassToken()
	local classColor = { E:GetClassColor(class) }
	local powerColor = { E:GetPowerColor("MANA") }
	E:ConfigSample(canvas.sample, "pips", {
		count = 5, filled = 3, width = db.width, height = combo.enabled and combo.height or 0.01,
		spacing = combo.spacing, color = classColor[1] and classColor or nil,
		barHeight = power.enabled and power.height or 0,
		barColor = power.classColor and classColor[1] and classColor or (powerColor[1] and powerColor or nil),
	})
	canvas.fold:SetLabel(L["Your class: %s"]:format(className or "?"))
	for index, info in ipairs(M:PreviewRows()) do
		local row = canvas.rows[index]
		row:SetLabel(info[1])
		row:SetValue(info[2], info[3])
	end
end

local function CreatePreview(canvas)
	if not canvas then return end
	local Kit = E.UIKit
	local sample = CreateFrame("Frame", nil, canvas)
	sample:SetPoint("TOPLEFT")
	sample:SetPoint("TOPRIGHT")
	sample:SetHeight(PREVIEW_SAMPLE_HEIGHT)
	canvas.sample = sample
	local content = CreateFrame("Frame", nil, canvas)
	canvas.fold = Kit.FoldDivider(canvas, { label = "", content = content, folded = previewFolded,
		tip = L["What the stack shows for your class."], onToggle = function(folded) previewFolded = folded end })
	canvas.fold:SetPoint("TOPLEFT", sample, "BOTTOMLEFT", 0, -4)
	canvas.fold:SetPoint("TOPRIGHT", sample, "BOTTOMRIGHT", 0, -4)
	content:SetPoint("TOPLEFT", canvas.fold, "BOTTOMLEFT")
	content:SetPoint("TOPRIGHT", canvas.fold, "BOTTOMRIGHT")
	content:SetHeight(4 * E.tokens.height.row)
	canvas.rows = {}
	for index = 1, 4 do
		local row = Kit.ValueRow(content, {})
		row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * E.tokens.height.row)
		row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(index - 1) * E.tokens.height.row)
		canvas.rows[index] = row
	end
	UpdatePreview(canvas)
end
M.CreatePreview = CreatePreview

M.options = {
	{ type = "tab", label = "Bars" },
	{ type = "preview", label = "Preview", height = 16 + PREVIEW_SAMPLE_HEIGHT + 4 + E.tokens.height.foldRow + 4 * E.tokens.height.row,
		create = CreatePreview, update = UpdatePreview,
		desc = "Sample combo points and power bar in your width, heights and colors, and what the stack shows for your class." },
	{ type = "header", label = "Position" },
	{ type = "select", key = "attachTo", label = "Attach to", values = { MOVER = "Its own mover", PLAYER = "Under the player frame", COOLDOWNS = "Above the Cooldown Manager" },
		desc = "Where the bars sit. Its own mover is Class Resources in move mode." },
	{ type = "range", unit = "px", key = "width", label = "Width", min = 100, max = 400, step = 1,
		desc = "Width of every row. While Match the Cooldown Manager width is on, used only when that row is hidden." },
	{ type = "toggle", key = "syncWidth", label = "Match the Cooldown Manager width", desc = "Take the width of the Cooldown Manager's essential row when it is shown." },
	{ type = "range", key = "gap", label = "Space between rows", min = 0, max = 12, step = 1, cog = true, desc = "Gap between combo points, health, power, druid mana and the GCD bar." },
	{ type = "header", label = "Power" },
	{ type = "toggle", key = "power.enabled", label = "Power bar", desc = "Your mana, rage or energy." },
	{ type = "range", unit = "px", key = "power.height", label = "Height", min = 4, max = 30, step = 1, desc = "How tall the mana, rage or energy bar is.", hidden = Off("power.enabled") },
	{ type = "select", key = "power.text", label = "Text", values = TEXT_VALUES, hidden = Off("power.enabled"),
		desc = "Number on the power bar, straight from the game." },
	{ type = "range", key = "power.textSize", label = "Text size", min = 8, max = 20, step = 1, cog = true, desc = "Font size of the power text.", hidden = Off("power.enabled") },
	{ type = "toggle", key = "power.classColor", label = "Class color", desc = "Class color instead of the power color (blue mana, red rage, yellow energy).", hidden = Off("power.enabled") },
	{ type = "toggle", key = "power.cost", label = "Spell cost while casting", desc = "While you cast, the part of the bar the spell will cost is lit up, from the spell's own cost.", hidden = Off("power.enabled") },
	{ type = "color", key = "power.costColor", label = "Spell cost color", cog = true, desc = "Color of the spell cost overlay.", hidden = Off("power.enabled") },
	{ type = "input", key = "power.thresholds", label = "Threshold lines", hidden = Off("power.enabled"),
		desc = "Spells (IDs or names, separated by commas, up to six) whose cost gets a thin line on the bar, e.g. 1752, Eviscerate. The lines sit where the cost is on a full bar." },
	{ type = "color", key = "power.thresholdColor", label = "Line color", cog = true, desc = "Color of the threshold lines.", hidden = Off("power.enabled") },
	{ type = "toggle", key = "power.fiveSecond", label = "Five-second rule spark", hidden = Off("power.enabled"),
		desc = "A spark crosses the mana bar during the 5 seconds after you cast a spell that costs mana (spirit regeneration is paused meanwhile)." },
	{ type = "toggle", key = "power.smooth", label = "Smooth fill", hidden = Off("power.enabled"),
		desc = "Every bar in the stack glides to its new value instead of jumping. The game animates the bar itself." },
	{ type = "toggle", key = "power.hideFull", label = "Hide when full", hidden = Off("power.enabled"),
		desc = "Hide the power bar while your mana or energy is full. While the game keeps your power secret (in some fights) the bar stays shown." },
	{ type = "toggle", key = "soulShards.enabled", label = "Soul Shard count",
		desc = "Warlocks: how many Soul Shards are in your bags, with the shard's icon, at the right end of the mana bar. It changes as soon as your bags do.",
		hidden = function() return not M.db.power.enabled or not IsWarlock() end },
	{ type = "header", label = "Combo points" },
	{ type = "toggle", key = "combo.enabled", label = "EldoUI combo points", desc = "Combo points for rogues and druids in cat form. Turn off to keep only Blizzard's." },
	{ type = "select", key = "combo.style", label = "Style", values = { PIPS = "Pips in a row", ARC = "Arc of dots" }, hidden = Off("combo.enabled"),
		desc = "Flat pips as wide as the bars, or round dots on an arc above them." },
	{ type = "range", unit = "px", key = "combo.height", label = "Pip height", min = 4, max = 30, step = 1, desc = "How tall each combo point is.", hidden = NotPips },
	{ type = "range", unit = "px", key = "combo.spacing", label = "Pip spacing", min = 0, max = 10, step = 1, cog = true, desc = "Gap between pips.", hidden = NotPips },
	{ type = "range", key = "combo.arcRadius", label = "Arc size", min = 20, max = 120, step = 1, desc = "Radius of the arc the dots sit on.", hidden = NotArc },
	{ type = "range", unit = "px", key = "combo.arcSize", label = "Dot size", min = 6, max = 30, step = 1, desc = "How big each combo point dot is.", hidden = NotArc },
	{ type = "toggle", key = "combo.hideEmpty", label = "Hide when empty", desc = "Hide the combo points with no target or no points.", hidden = Off("combo.enabled") },
	{ type = "select", key = "combo.colorMode", label = "Pip colors", values = { CLASS = "Class color", CUSTOM = "A color per pip" }, hidden = Off("combo.enabled"),
		desc = "Every pip in your class color, or each pip in its own color (set below)." },
	{ type = "color", key = "combo.colors.pip1", label = "Pip 1", desc = "Color of the first combo point.", hidden = NotCustomPips }, -- lint: unused-key ok (read as "pip" .. index)
	{ type = "color", key = "combo.colors.pip2", label = "Pip 2", desc = "Color of the second combo point.", hidden = NotCustomPips }, -- lint: unused-key ok (read as "pip" .. index)
	{ type = "color", key = "combo.colors.pip3", label = "Pip 3", desc = "Color of the third combo point.", hidden = NotCustomPips }, -- lint: unused-key ok (read as "pip" .. index)
	{ type = "color", key = "combo.colors.pip4", label = "Pip 4", desc = "Color of the fourth combo point.", hidden = NotCustomPips }, -- lint: unused-key ok (read as "pip" .. index)
	{ type = "color", key = "combo.colors.pip5", label = "Pip 5", desc = "Color of the fifth combo point.", hidden = NotCustomPips }, -- lint: unused-key ok (read as "pip" .. index)
	{ type = "toggle", key = "combo.fullColorEnabled", label = "Color when full", hidden = Off("combo.enabled"),
		desc = "Every pip turns one color when all your combo points are filled, so a finisher at five points stands out." },
	{ type = "color", key = "combo.fullColor", label = "Full color", desc = "Color of all pips at maximum combo points.",
		hidden = function() return not M.db.combo.enabled or not M.db.combo.fullColorEnabled end },
	{ type = "toggle", key = "combo.onPlate", label = "On the target's nameplate", desc = "Also show your combo points under your target's nameplate." },
	{ type = "range", unit = "px", key = "combo.plateSize", label = "Nameplate pip size", min = 4, max = 16, step = 1, cog = true, desc = "Height of the pips on the nameplate.", hidden = Off("combo.onPlate") },
	{ type = "header", label = "Health" },
	{ type = "toggle", key = "health.enabled", label = "Health bar", desc = "Your own health as a row in the stack." },
	{ type = "range", unit = "px", key = "health.height", label = "Height", min = 4, max = 30, step = 1, desc = "Health bar height.", hidden = Off("health.enabled") },
	{ type = "select", key = "health.text", label = "Text", values = TEXT_VALUES, hidden = Off("health.enabled"), desc = "Number on the health bar, straight from the game." },
	{ type = "range", key = "health.textSize", label = "Text size", min = 8, max = 20, step = 1, cog = true, desc = "Font size of the health text.", hidden = Off("health.enabled") },
	{ type = "toggle", key = "health.classColor", label = "Class color", desc = "Class color; off uses plain green.", hidden = Off("health.enabled") },
	{ type = "header", label = "Druid mana" },
	{ type = "toggle", key = "druidMana.enabled", label = "Druid mana in forms", desc = "A thin mana bar while you are in bear or cat form; the power bar shows the form's rage or energy." },
	{ type = "range", unit = "px", key = "druidMana.height", label = "Height", min = 2, max = 20, step = 1, desc = "Druid mana bar height.", hidden = Off("druidMana.enabled") },
	{ type = "select", key = "druidMana.attach", label = "Position", values = { INSET = "Inside the power bar", STACK = "In the stack", PLAYER = "Under the player frame" }, hidden = Off("druidMana.enabled"),
		desc = "Inside the power bar as a strip along its bottom edge, as its own row in the stack, or as a strip under EldoUI's player frame." },
	{ type = "header", label = "Global cooldown" },
	{ type = "toggle", key = "gcd.enabled", label = "GCD bar", desc = "A thin bar that runs down during the global cooldown after each spell, from the game's own cooldown." },
	{ type = "range", unit = "px", key = "gcd.height", label = "Height", min = 2, max = 12, step = 1, desc = "GCD bar height.", hidden = Off("gcd.enabled") },
}
for _, row in ipairs(E:VisibilityOptions("visibility", { db = function() return M.db end })) do
	table.insert(M.options, row)
end

-- Color ranges and tick marks.
local function NoRanges() return not M.db.power.enabled or not M.db.power.rangesEnabled end
local function NoTicks() return not M.db.power.enabled or not M.db.power.ticks.enabled end
local function Add(row) table.insert(M.options, row) end
Add({ type = "tab", label = "Ranges and ticks" })
Add({ type = "description", label = "Color ranges and tick marks go on the power bar. Turn the power bar on (Bars tab) to use them.", hidden = function() return M.db.power.enabled end })
Add({ type = "header", label = "Color ranges", hidden = Off("power.enabled") })
Add({ type = "toggle", key = "power.rangesEnabled", label = "Enable", hidden = Off("power.enabled"),
	desc = "Change the bar color above chosen values: the part of the bar past each value takes that value's color, e.g. energy past 40 turns orange." })
Add({ type = "select", key = "power.rangeMode", label = "Values are", hidden = NoRanges,
	values = { VALUE = "Power points (rage, energy)", PERCENT = "Percent of the maximum (mana)" },
	desc = "Read the values below as power points, or as a percent of your maximum power (better for mana, which grows with your level)." })
for index = 1, MAX_RANGES do
	Add({ type = "range", key = "power.ranges.value" .. index, label = "Range %d from", labelFill = index, min = 0, max = 200, step = 1, hidden = NoRanges,
		zeroText = "Off", desc = "Value where this color starts. Values at or past your maximum are skipped." })
	Add({ type = "color", key = "power.ranges.color" .. index, label = "Range %d color", labelFill = index, hidden = NoRanges,
		desc = "Color of the bar past this value." })
end
Add({ type = "header", label = "Tick marks", hidden = Off("power.enabled") })
Add({ type = "toggle", key = "power.ticks.enabled", label = "Enable", hidden = Off("power.enabled"),
	desc = "Thin marks on the power bar at the values you choose for each power type." })

Add({ type = "input", key = "power.ticks.MANA", label = "Mana marks", hidden = NoTicks, desc = "Marks while the bar shows mana. Write values (40, 80), percents (50%), every N (every 20) or every N percent (every 25%). Empty = no marks." })
Add({ type = "input", key = "power.ticks.RAGE", label = "Rage marks", hidden = NoTicks, desc = "Marks while the bar shows rage. Write values (40, 80), percents (50%), every N (every 20) or every N percent (every 25%). Empty = no marks." })
Add({ type = "input", key = "power.ticks.ENERGY", label = "Energy marks", hidden = NoTicks, desc = "Marks while the bar shows energy. Write values (40, 80), percents (50%), every N (every 20) or every N percent (every 25%). Empty = no marks." })
Add({ type = "color", key = "power.ticks.color", label = "Mark color", hidden = NoTicks, desc = "Color of the tick marks." })
Add({ type = "range", percent = true, key = "power.ticks.alpha", label = "Mark opacity", min = 0.1, max = 1, step = 0.05, cog = true, hidden = NoTicks, desc = "How solid the marks are." })
Add({ type = "range", unit = "px", key = "power.ticks.thickness", label = "Mark width", min = 1, max = 4, step = 1, hidden = NoTicks, desc = "Width of each mark in pixels." })
Add({ type = "range", unit = "%", key = "power.ticks.height", label = "Mark height", min = 20, max = 100, step = 5, hidden = NoTicks, desc = "Height of the marks as a percent of the bar's height (centered)." })

-- Extra resource bars.
Add({ type = "tab", label = "Extra bars" })
Add({ type = "description", label = "More bars for other resources, such as mana in cat form. A bar shows only while you have that resource; placed on its own, it gets a mover." })
local POWER_VALUES = { MANA = "Mana", RAGE = "Rage", ENERGY = "Energy", COMBO = "Combo points" }
for index = 1, MAX_EXTRA do
	local base = "bars.bar" .. index .. "."
	local function Cfg() return M.db.bars["bar" .. index] end
	local function BarOff() return not Cfg().enabled end
	Add({ type = "header", label = "Resource bar %d", labelFill = index })
	Add({ type = "toggle", key = base .. "enabled", label = "Show this bar", desc = "Turn this extra resource bar on." })
	Add({ type = "select", key = base .. "power", label = "Resource", values = POWER_VALUES, hidden = BarOff,
		desc = "What the bar shows. Combo points show as one bar that fills per point." })
	Add({ type = "select", key = base .. "place", label = "Position", values = { STACK = "In the stack", MOVER = "Its own position" }, hidden = BarOff,
		desc = "In the stack with the other bars, or on its own mover (Resource Bar %d in move mode).", descFill = index })
	Add({ type = "range", unit = "px", key = base .. "width", label = "Width", min = 0, max = 400, step = 1, zeroText = "Stack", desc = "Width on its own position. Stack is as wide as the stack.",
		hidden = function() return BarOff() or Cfg().place ~= "MOVER" end })
	Add({ type = "range", unit = "px", key = base .. "height", label = "Height", min = 2, max = 30, step = 1, hidden = BarOff, desc = "How tall this bar is in its stack or on its own." })
	Add({ type = "select", key = base .. "text", label = "Text", values = { NONE = "Hidden", CURRENT = "Current", PERCENT = "Percent" }, hidden = BarOff,
		desc = "Number on the bar, straight from the game. Percent is not shown for combo points." })
	Add({ type = "range", key = base .. "textSize", label = "Text size", min = 8, max = 20, step = 1, cog = true, desc = "Font size of the text.",
		hidden = function() return BarOff() or Cfg().text == "NONE" end })
	Add({ type = "select", key = base .. "color", label = "Color", values = { POWER = "Power color", CLASS = "Class color", CUSTOM = "Own color" }, hidden = BarOff,
		desc = "Color of the fill: the resource's own color (blue mana, red rage, yellow energy), your class color or one you pick." })
	Add({ type = "color", key = base .. "customColor", label = "Own color", desc = "The bar's color when Color is set to Own color.",
		hidden = function() return BarOff() or Cfg().color ~= "CUSTOM" end })
	Add({ type = "toggle", key = base .. "onlyCurrent", label = "Only while it is your power", cog = true,
		desc = "Show the bar only while this is the power your character uses right now (a druid's energy only in cat form).",
		hidden = function() return BarOff() or Cfg().power == "COMBO" end })
	Add({ type = "toggle", key = base .. "hideFull", label = "Hide when full", cog = true, hidden = BarOff,
		desc = "Hide this bar while it is full. While the game keeps the value secret the bar stays shown." })
end

-- Looks per talent group.
local function LookValues()
	local values = { [""] = "Keep the current look" }
	for _, look in ipairs(M.LOOKS) do values[look.key] = look.title end
	values.A = "Saved look A"
	values.B = "Saved look B"
	return values
end
Add({ type = "tab", label = "Look" })
Add({ type = "description", label = "A look sets how the bars look, never where they sit. Pick one per talent group to switch with your talents; save your own into slot A or B." })
Add({ type = "header", label = "Talent groups" })
Add({ type = "select", key = "looks.group1", label = "Talent group 1", values = LookValues, -- lint: unused-key ok (read as "group" .. talent group)
	desc = "Look to put on when your first talent group becomes active." })
Add({ type = "select", key = "looks.group2", label = "Talent group 2", values = LookValues, -- lint: unused-key ok (read as "group" .. talent group)
	desc = "Look to put on when your second talent group becomes active." })
Add({ type = "header", label = "Your looks" })
Add({ type = "execute", label = "Save look A", testSafe = true, func = function() M:SaveLook("A") end,
	desc = "Save how the bars look now as Saved look A." })
Add({ type = "execute", label = "Save look B", testSafe = true, func = function() M:SaveLook("B") end,
	desc = "Save how the bars look now as Saved look B." })
for _, row in ipairs({
	{ type = "tab", label = "Blizzard" },
	{ type = "description", label = "For Class resources in Blizzard UI. Hide and Replace hide what is checked here; Move puts the totem timers on their own mover." },
	{ type = "toggle", key = "blizzard.hideCombo", label = "Hide Blizzard's combo points", desc = "The combo points on Blizzard's target frame.", hidden = ElementOff },
	{ type = "toggle", key = "blizzard.hideDruidMana", label = "Hide Blizzard's druid mana bar", desc = "The extra mana bar on Blizzard's player frame.", hidden = ElementOff },
	{ type = "toggle", key = "blizzard.hideTotems", label = "Hide totem timers", desc = "Blizzard's totem timers (the totem bar for placing totems is under Action Bars).", hidden = ElementOff },
	{ type = "toggle", key = "blizzard.hidePRD", label = "Hide the personal resource display", desc = "Blizzard's bars under your character (Edit Mode: Personal Resource Display). Skin restyles it instead.", hidden = ElementOff },
	{ type = "range", percent = true, key = "blizzard.totemScale", label = "Totem timer scale", min = 0.5, max = 2, step = 0.05, desc = "Scale of the totem timers while EldoUI moves them.", hidden = ElementOff },
	{ type = "select", key = "blizzard.totemAttach", label = "Totem timers position", values = { MOVER = "Own mover", TOTEMBAR = "With the totem bar" },
		desc = "Where Move puts Blizzard's totem timers. Own mover gives them their own box in move mode; With the totem bar keeps them next to the shaman totem bar. Other classes use the mover.", hidden = ElementOff },
}) do
	table.insert(M.options, row)
end

---------------------------------------------------------------------------
-- Style presets
---------------------------------------------------------------------------
-- Looks only: where the bar sits is the "Attach to" option and the layout,
-- so no preset moves it. Every style fits the resource band the layouts
-- keep between the main cooldown row and the totem timers: 22 units, combo
-- points (and a druid's mana, inside the power bar) included.
local STYLES = {
	{ key = "Standard", title = "Standard", desc = "277 px power bar with pips on top, the current value and the spell cost while casting.",
		settings = { width = 277, attachTo = "MOVER", health = { enabled = false }, gcd = { enabled = false },
			power = { enabled = true, height = 10, text = "CURRENT", cost = true }, combo = { enabled = true, style = "PIPS", height = 8, spacing = 3 } } },
	{ key = "Slim", title = "Slim", desc = "Thin 6 px bar, no text, small pips.",
		settings = { width = 240, attachTo = "MOVER", health = { enabled = false }, gcd = { enabled = false },
			power = { enabled = true, height = 6, text = "NONE" }, combo = { enabled = true, style = "PIPS", height = 6, spacing = 2 } } },
	{ key = "Stack", title = "Resource stack", desc = "Thin health, power and GCD bars stacked under you, combo pips on top.",
		settings = { width = 260, attachTo = "MOVER", gap = 1, health = { enabled = true, height = 5, text = "NONE" }, gcd = { enabled = true, height = 2 },
			power = { enabled = true, height = 8, text = "CURRENT", textSize = 10, cost = true }, combo = { enabled = true, style = "PIPS", height = 4, spacing = 2 } } },
	{ key = "Chunky", title = "Chunky", desc = "Tall bar with current and percent, wide pips.",
		settings = { width = 300, attachTo = "MOVER", gap = 2, health = { enabled = false }, gcd = { enabled = false },
			power = { enabled = true, height = 14, text = "BOTH", textSize = 12 }, combo = { enabled = true, style = "PIPS", height = 6, spacing = 4 } } },
	{ key = "PipsOnly", title = "Pips only", desc = "Only combo points, no power bar (Blizzard's player frame or EldoUI's shows power).",
		settings = { width = 200, attachTo = "MOVER", health = { enabled = false }, gcd = { enabled = false },
			power = { enabled = false }, combo = { enabled = true, style = "PIPS", height = 10, spacing = 4 } } },
	{ key = "Hybrid", title = "Hybrid (druid)", desc = "Combo points, energy or rage, and your mana always below them as a second bar, e.g. a feral druid.",
		settings = { width = 277, attachTo = "MOVER", gap = 1, druidMana = { enabled = false },
			power = { enabled = true, height = 10, text = "CURRENT", cost = true }, combo = { enabled = true, style = "PIPS", height = 5, spacing = 3 },
			bars = { bar1 = { enabled = true, power = "MANA", place = "STACK", height = 4, text = "NONE", color = "POWER", onlyCurrent = false } } } },
	{ mode = true, key = "Faded", title = "Fades out of combat", desc = "Standard bars that fade when you are idle (no combat, no target).",
		settings = { width = 277, attachTo = "MOVER", visibility = E:VisibilityDefaults({ show = "combatOrTarget", fadedAlpha = 0.3 }),
			power = { enabled = true, height = 10, text = "CURRENT" } } },
}
-- Every style sets the whole visibility block, so a faded style never
-- leaves its fade behind when another one is picked.
-- The same for the health and GCD rows: off unless the style asks for them.
for _, style in ipairs(STYLES) do
	local settings = style.settings
	settings.visibility = settings.visibility or E:VisibilityDefaults()
	settings.health = settings.health or { enabled = false }
	settings.gcd = settings.gcd or { enabled = false }
	settings.gap = settings.gap or 3
	-- Hybrid swaps the druid mana row for extra bar 1; the others swap back.
	settings.druidMana = settings.druidMana or { enabled = true }
	settings.bars = settings.bars or { bar1 = { enabled = false } }
end
E:RegisterStyles("ClassPower", STYLES)
