-- EldoUI Combat Text: scrolling combat text in EldoUI's look, numbers
-- on enemy nameplates, and the home of Blizzard's own combat text options
-- and EldoUI's frame feedback (moved here from Combat HUD).
--
-- Files (TOC order):
--   Core.lua        module, settings, event list, migration, rollout, commands
--   Animations.lua  animation styles (scroll areas and plates)
--   Engine.lua      scroll areas, movers, line pool, merging, rate limits,
--                   formatting; public API E.CombatText:Show / :RegisterAnimation
--   Sources.lua     UNIT_COMBAT (player, pet, target), COMBAT_TEXT_UPDATE extras
--   Notify.lua      combat state, procs, resources, killing blows, XP, honor,
--                   reputation, skill, emotes, loot, money, currency, warnings
--   MoveAreas.lua   Combat Text's own move mode: start edge, samples, resize
--   Plates.lua      hit numbers on enemy nameplates
--   Blizzard.lua    Blizzard's floating combat text element + frame feedback
--   Options.lua     options page, event editor, style presets
--
-- Rules (Midnight / Forever): presentation only. The feed is UNIT_COMBAT,
-- the game's own per-unit hit events. Amounts and schools can be secret:
-- they go to FontString:SetFormattedText untouched (the game draws them),
-- with AbbreviateNumbers / BreakUpLargeNumbers, which accept secrets. Lua
-- only compares, sums or colors values that issecretvalue says are plain.
-- Nothing works out who hit whom: plate numbers are every hit the enemy
-- takes, and say so. COMBAT_LOG_EVENT* is never registered.
-- Written from scratch for EldoUI (no code from other addons).
local _, E = ...
local L = E.L

local Key = E.Key
local M = E:NewModule("CombatText", {
	title = "Combat Text",
	desc = "Scrolling combat text in EldoUI's look: damage and healing you take, notifications, loot and gains, and hit numbers on enemy nameplates, plus Blizzard's combat text options.",
	category = "Combat",
	frames = {},
	movers = { "EldoUI_SCTIncoming", "EldoUI_SCTTarget", "EldoUI_SCTNotify", "EldoUI_SCTStatic" }, -- and one per custom area (EldoUI_SCTCustom<n>)
	blizzard = { "floating-combat-text" },
	savedKeys = { "profile.modules.CombatText", "global.combatText" },
	optionsPage = "module:CombatText",
	presets = { "Blizzlike", "ClassicSCT", "Clean", "Large", "Minimal", "Plates", "Punchy" },
	defaults = {},
})
E.CombatText = M
M.issecret = issecretvalue or function() return false end

---------------------------------------------------------------------------
-- Scroll areas: four built in, up to four of the player's own.
---------------------------------------------------------------------------
M.AREA_KEYS = { "incoming", "target", "notify", "static" }
M.CUSTOM_MAX = 4
M.AREA_MOVERS = {
	incoming = "EldoUI_SCTIncoming", target = "EldoUI_SCTTarget",
	notify = "EldoUI_SCTNotify", static = "EldoUI_SCTStatic",
}
-- Fallback points when no layout preset names the mover (1440 units).
M.AREA_POINTS = {
	incoming = { "CENTER", "UIParent", "CENTER", -300, 60 },
	target = { "CENTER", "UIParent", "CENTER", 300, 60 },
	notify = { "CENTER", "UIParent", "CENTER", 0, 330 },
	static = { "CENTER", "UIParent", "CENTER", -796, -204 },
}

local function Area(enabled, title, width, height, animation, direction, curve, align, iconSide)
	return {
		enabled = enabled, title = title, width = width, height = height,
		animation = animation, direction = direction, curve = curve, sticky = "pop", shake = false,
		align = align, iconSide = iconSide, speed = 0, maxLines = 12, rate = 8,
		font = "default", fontSize = 0, critFontSize = 0, hideInGroup = false,
	}
end
M.NewArea = Area

-- The settings a new custom area starts with.
function M.CustomAreaDefaults(index)
	return Area(true, L["Area %d"]:format(index), 160, 200, "straight", "up", "left", "CENTER", "LEFT")
end

---------------------------------------------------------------------------
-- Events: what can show, where, and how it reads. Codes in templates:
-- {amount} {name} {spell} {type} {count} {item} {total} {text}
---------------------------------------------------------------------------
M.CATEGORIES = {
	{ key = "incoming", title = "Incoming" },
	{ key = "pet", title = "Pet" },
	{ key = "target", title = "Target Hits" },
	{ key = "notify", title = "Notifications" },
	{ key = "static", title = "Loot and info" },
	{ key = "warn", title = "Warnings" },
}

local RED, ORANGE, GREEN, WHITE = { 1, 0.27, 0.27 }, { 1, 0.55, 0.15 }, { 0.3, 1, 0.4 }, { 1, 1, 1 }
local GREY, YELLOW, BLUE, PURPLE = { 0.75, 0.75, 0.78 }, { 1, 0.85, 0.2 }, { 0.45, 0.7, 1 }, { 0.75, 0.5, 1 }

-- key, category, area, on, color, sticky, template, label, desc, extra
M.EVENTS = {
	{ "inDamage", "incoming", "incoming", true, RED, false, "-{amount}", Key("Damage taken"), Key("Hits you take."), { merge = true, school = true } },
	{ "inDamageCrit", "incoming", "incoming", true, RED, true, "-{amount}", Key("Critical damage taken"), Key("Critical hits you take. They pop out like other sticky lines."), { school = true } },
	{ "inAvoid", "incoming", "incoming", true, WHITE, false, "{type}", Key("Dodge, parry, miss"), Key("Attacks on you that miss, are dodged, parried, evaded, deflected, reflected or have no effect.") },
	{ "inMitigate", "incoming", "incoming", true, GREY, false, "{type}", Key("Block, absorb, resist"), Key("Hits that are fully blocked, absorbed or resisted.") },
	{ "inHeal", "incoming", "incoming", true, GREEN, false, "+{amount}", Key("Healing taken"), Key("Healing you receive."), { merge = true } },
	{ "inHealCrit", "incoming", "incoming", true, GREEN, true, "+{amount}", Key("Critical healing taken"), Key("Critical heals you receive.") },
	{ "petDamage", "pet", "incoming", false, ORANGE, false, Key("Pet -{amount}"), Key("Pet damage taken"), Key("Hits your pet takes."), { merge = true, school = true } },
	{ "petHeal", "pet", "incoming", false, GREEN, false, Key("Pet +{amount}"), Key("Pet healing taken"), Key("Healing your pet receives."), { merge = true } },
	{ "petAvoid", "pet", "incoming", false, WHITE, false, Key("Pet {type}"), Key("Pet dodge, parry, miss"), Key("Attacks on your pet that miss or are avoided.") },
	{ "tgtDamage", "target", "target", true, WHITE, false, "{amount}", Key("Hits on target"), Key("Every hit your target takes, from anyone. The game doesn't say who hit, so this is not only your damage."), { merge = true, school = true } },
	{ "tgtCrit", "target", "target", true, YELLOW, true, "{amount}", Key("Critical hits on target"), Key("Every critical hit your target takes, from anyone."), { school = true } },
	{ "tgtAvoid", "target", "target", true, GREY, false, "{type}", Key("Target dodge, parry, miss"), Key("Attacks on your target that miss or are avoided, from anyone.") },
	{ "tgtHeal", "target", "target", false, GREEN, false, "+{amount}", Key("Healing on target"), Key("Healing your target receives, from anyone."), { merge = true } },
	{ "combatIn", "notify", "notify", true, ORANGE, false, "{text}", Key("Entering combat"), Key("A short line when combat starts.") },
	{ "combatOut", "notify", "notify", true, GREEN, false, "{text}", Key("Leaving combat"), Key("A short line when combat ends.") },
	{ "proc", "notify", "notify", true, YELLOW, true, "{spell}!", Key("Spell alerts (procs)"), Key("When the game lights up one of your spells (the glow on the action button). In boss fights these move to the Incoming area so they don't cover boss warnings."), { icon = true, boss = true } },
	{ "buff", "notify", "notify", false, GREEN, false, "+{spell}", Key("Buff gained"), Key("Buffs you gain, from the game's own combat text feed."), { ctu = true } },
	{ "debuff", "notify", "notify", false, RED, false, "[{spell}]", Key("Debuff gained"), Key("Debuffs you gain, from the game's own combat text feed."), { ctu = true } },
	{ "fade", "notify", "notify", false, GREY, false, "-{spell}", Key("Aura faded"), Key("Buffs and debuffs that wear off, from the game's own combat text feed."), { ctu = true } },
	{ "extraAttack", "notify", "notify", false, YELLOW, false, Key("+{amount} extra attacks"), Key("Extra attacks"), Key("Extra attacks you gain, from the game's own combat text feed."), { ctu = true } },
	{ "energize", "notify", "notify", false, BLUE, false, "+{amount}", Key("Resource gains"), Key("Mana, rage and energy you gain from spells and items."), { merge = true } },
	{ "resource", "notify", "notify", true, YELLOW, false, "{amount} {type}", Key("Combo points"), Key("Your combo points when they change."), { combo = true } },
	{ "resourceFull", "notify", "notify", true, ORANGE, true, Key("{type} full"), Key("Combo points full"), Key("A sticky line when your combo points are full."), { combo = true } },
	{ "killingBlow", "notify", "notify", true, ORANGE, true, Key("Killing blow"), Key("Killing blows"), Key("When the game says you landed the killing blow. In boss fights these move to the Incoming area."), { boss = true } },
	{ "xp", "static", "static", false, PURPLE, false, Key("+{amount} XP"), Key("Experience"), Key("Experience from kills, from the game's chat line.") },
	{ "honor", "static", "static", true, YELLOW, false, Key("+{amount} Honor"), Key("Honor"), Key("Honor you gain, from the game's chat line.") },
	{ "rep", "static", "static", true, BLUE, false, "+{amount} {name}", Key("Reputation gained"), Key("Reputation you gain, from the game's chat line.") },
	{ "repLoss", "static", "static", true, RED, false, "-{amount} {name}", Key("Reputation lost"), Key("Reputation you lose, from the game's chat line.") },
	{ "skill", "static", "static", true, BLUE, false, "{name} {amount}", Key("Skill ups"), Key("Skill points you gain, from the game's chat line.") },
	{ "emote", "static", "static", true, ORANGE, false, "{text}", Key("Monster emotes"), Key("Emotes of your target (\"... becomes enraged!\"). Skipped while the game keeps chat hidden.") },
	{ "loot", "static", "static", true, WHITE, false, "+{item} {count} ({total})", Key("Items looted"), Key("Items you loot. Only while EldoUI's loot toasts are off, unless you check the option on the Loot and Info tab."), { icon = true, loot = true } },
	{ "money", "static", "static", true, YELLOW, false, "+{amount}", Key("Money looted"), Key("Money you loot. Only while EldoUI's loot toasts are off, unless you check the option on the Loot and Info tab."), { loot = true } },
	{ "currency", "static", "static", true, WHITE, false, "+{item} {count}", Key("Currency gained"), Key("Currencies you gain. Only while EldoUI's loot toasts are off, unless you check the option on the Loot and Info tab."), { icon = true, loot = true } },
	{ "itemReady", "static", "static", false, GREEN, false, Key("{item} ready"), Key("Item ready"), Key("Your watched items when their cooldown ends, when the game says so plainly."), { icon = true, ready = true } },
	{ "lowHealth", "warn", "notify", false, RED, true, Key("Low health"), Key("Low health"), Key("A line that shows while your health is below the percent on the Warnings tab. The game works out when; EldoUI only draws it. No sound."), { warn = "health" } },
	{ "lowMana", "warn", "notify", false, BLUE, true, Key("Low mana"), Key("Low mana"), Key("A line that shows while your mana is below the percent on the Warnings tab. No sound."), { warn = "mana" } },
	{ "lowPet", "warn", "notify", false, ORANGE, true, Key("Low pet health"), Key("Low pet health"), Key("A line that shows while your pet's health is below the percent on the Warnings tab. No sound."), { warn = "pet" } },
}
M.eventInfo = {}
M.eventOrder = {}
for index, row in ipairs(M.EVENTS) do
	local info = { key = row[1], category = row[2], area = row[3], on = row[4], color = row[5], sticky = row[6],
		text = row[7], label = row[8], desc = row[9], order = index }
	for field, value in pairs(row[10] or {}) do info[field] = value end
	M.eventInfo[info.key] = info
	M.eventOrder[index] = info.key
end

---------------------------------------------------------------------------
-- Defaults
---------------------------------------------------------------------------
local defaults = M.defaults
defaults.handoffAsked = false
defaults.editArea = "incoming"
defaults.editCategory = "incoming"
defaults.scroll = {
	enabled = true, speed = 100, numbers = "short", icons = true, stickyCrits = true, sounds = true,
	schoolColors = true, merge = true, mergeWindow = 0.3, mergeCount = true, minAmount = 0,
	font = "THEME", fontSize = 18, critFont = "THEME", critFontSize = 26, outline = "OUTLINE", alpha = 100,
	-- The Punchy style's look (Options.lua); off in every other style.
	shadow = false, flash = false, countGray = false,
}
defaults.areas = {
	incoming = Area(true, Key("Incoming"), 160, 260, "arc", "down", "left", "RIGHT", "LEFT"),
	target = Area(false, Key("Target Hits"), 160, 260, "arc", "down", "right", "LEFT", "RIGHT"),
	notify = Area(true, Key("Notifications"), 360, 100, "straight", "up", "left", "CENTER", "LEFT"),
	static = Area(true, Key("Loot and Info"), 300, 110, "stack", "down", "left", "LEFT", "LEFT"),
}
defaults.events = {}
for _, key in ipairs(M.eventOrder) do
	local info = M.eventInfo[key]
	defaults.events[key] = { on = info.on, area = info.area, color = { unpack(info.color) }, sticky = info.sticky,
		sound = "none", fontSize = 0, text = info.text }
end
defaults.loot = { minQuality = 1, questItems = true, bagTotal = true, withToasts = false, allow = "", exclude = "" }
defaults.warn = { health = 35, mana = 25, pet = 30 }
defaults.plates = {
	enabled = true, units = "target", inGroup = false, style = "rise", fontSize = 16, critScale = 140,
	offsetY = 6, maxPerPlate = 4, followPlate = true, words = true, heals = false, colorMode = "school",
	font = "THEME", outline = "OUTLINE", shadow = false, flash = false,
}

---------------------------------------------------------------------------
-- State helpers
---------------------------------------------------------------------------
-- The name and title of a loaded combat text addon that does this job.
function M:Conflict()
	return E:FeatureConflict("combattext")
end

-- True while EldoUI's own scrolling text runs (module on, switched on, no
-- other combat text addon loaded).
function M:ScrollRunning()
	return self.active and self.db.scroll.enabled and not self:Conflict() and true or false
end

function M:PlatesRunning()
	return self.active and self.db.plates.enabled and not self:Conflict() and true or false
end

-- In a boss encounter (procs and killing blows move to Incoming).
function M:InEncounter()
	if self.encounter then return true end
	local probe = C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress
	if probe then
		local ok, value = pcall(probe)
		if ok and not M.issecret(value) and value then return true end
	end
	return false
end

-- Every area key that exists in the profile (built in + custom ones).
function M:AreaKeys()
	local keys = { unpack(self.AREA_KEYS) }
	for index = 1, self.CUSTOM_MAX do
		if type(self.db.areas["custom" .. index]) == "table" then keys[#keys + 1] = "custom" .. index end
	end
	return keys
end

function M:AreaTitle(key)
	local area = self.db and self.db.areas[key]
	-- L at display: default titles are English keys; a player's own name passes through.
	if area and area.title and area.title ~= "" then return L[area.title] end
	return key
end

---------------------------------------------------------------------------
-- Migration (once per profile): Combat HUD's "text" and "feedback" tables
-- move to `blizzard` and `feedback` here. Only changed values are saved,
-- so the raw tables hold exactly what the player set.
---------------------------------------------------------------------------
local function MergeInto(target, source)
	for key, value in pairs(source) do
		if type(value) == "table" and type(target[key]) == "table" then
			MergeInto(target[key], value)
		elseif type(value) == "table" then
			target[key] = CopyTable(value)
		else
			target[key] = value
		end
	end
	return target
end

-- Runs once per profile (the profile keeps the version it reached, see
-- E:RegisterProfileMigration). Returns true when it moved something.
local MIGRATION = "CombatText:hud"

function M.MigrateProfile(profile)
	if type(profile) ~= "table" then return false end
	profile.modules = profile.modules or {}
	local own = profile.modules.CombatText
	own = type(own) == "table" and own or {}
	profile.modules.CombatText = own
	-- Profiles from before the version stamp carry their own mark: done.
	if own.migrated ~= nil then
		local done = own.migrated == 1
		own.migrated = nil
		if done then return false end
	end
	local moved = false
	local hud = profile.modules.CombatHUD
	if type(hud) == "table" then
		if type(hud.text) == "table" then
			own.blizzard = MergeInto(type(own.blizzard) == "table" and own.blizzard or {}, hud.text)
			hud.text = nil
			moved = true
		end
		if type(hud.feedback) == "table" then
			own.feedback = MergeInto(type(own.feedback) == "table" and own.feedback or {}, hud.feedback)
			hud.feedback = nil
			moved = true
		end
	end
	return moved
end
-- The profile in use moves when it loads; every other saved profile moves
-- in the update pass a few seconds after login, or when it is first used.
E:RegisterProfileMigration(M.MigrateProfile, MIGRATION, 1)

-- The Minimal and Blizzard-like styles used to turn the Incoming area to
-- scroll up, which starts its lines at the bottom edge of the box instead
-- of the top: the text dropped by the box's height, below where the layout
-- put it. Styles no longer change the direction; a profile one of them
-- turned goes back to the layout's start edge once.
function M.MigrateStartEdge(profile)
	local own = type(profile) == "table" and type(profile.modules) == "table" and profile.modules.CombatText
	if type(own) ~= "table" or (own.style ~= "Minimal" and own.style ~= "Blizzlike") then return false end
	local incoming = type(own.areas) == "table" and own.areas.incoming
	if type(incoming) ~= "table" or incoming.direction ~= "up" then return false end
	incoming.direction = "down"
	return true
end
E:RegisterProfileMigration(M.MigrateStartEdge, "CombatText:startEdge", 1)

---------------------------------------------------------------------------
-- Rollout (design decision): on for new installs; profiles that
-- existed before this version keep EldoUI's scrolling text and plate text
-- off, with one notice that says how to turn them on.
---------------------------------------------------------------------------
local function ExistingAccount()
	return type(EldoUIDB) == "table" and type(EldoUIDB.installed) == "table" and next(EldoUIDB.installed) ~= nil
end

function M:Rollout()
	local store = E:RegisterGlobal("combatText", { rollout = 0 }, { title = L["Combat Text"] })
	if not store or store.rollout == 1 then return end
	store.rollout = 1
	if not ExistingAccount() then return end
	for _, profile in pairs(EldoUIDB.profiles or {}) do
		if type(profile) == "table" then
			profile.modules = profile.modules or {}
			local own = profile.modules.CombatText or {}
			profile.modules.CombatText = own
			own.scroll = type(own.scroll) == "table" and own.scroll or {}
			own.plates = type(own.plates) == "table" and own.plates or {}
			own.scroll.enabled = false
			own.plates.enabled = false
		end
	end
	self.rolloutNotice = true
end

function M:ShowRolloutNotice()
	if not self.rolloutNotice then return end
	self.rolloutNotice = nil
	M:PushAlert({
		key = "combattext-new",
		title = L["Combat Text"],
		text = L["New: EldoUI's own scrolling combat text and nameplate hit numbers. They are off in the profiles you already had."],
		actions = {
			{ label = L["Turn on"], func = function()
				M.db.scroll.enabled = true
				M.db.plates.enabled = true
				E:RunOutOfCombat(function() M:OnProfileChanged() end)
			end },
		},
	})
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
-- Parts (Engine, Sources, Notify, Plates, Blizzard) register here:
--   M:AddPart(name, { enable = fn, disable = fn, refresh = fn })
M.parts = {}
function M:AddPart(name, part)
	part.name = name
	self.parts[#self.parts + 1] = part
	return part
end

local function CallParts(method)
	for _, part in ipairs(M.parts) do
		local fn = part[method]
		if fn then
			local ok, err = pcall(fn, part)
			if not ok then geterrorhandler()(("EldoUI Combat Text %s:%s: %s"):format(part.name, method, tostring(err))) end
		end
	end
end
M.CallParts = CallParts

function M:OnInitialize()
	E.CombatKit.BindSwitches(self)
	self:Rollout()
end

function M:OnEnable()
	E.CombatKit.BindSwitches(self)
	self:RegisterEvent("ENCOUNTER_START", function() M.encounter = true end)
	self:RegisterEvent("ENCOUNTER_END", function() M.encounter = nil end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() M.encounter = nil end)
	CallParts("enable")
	if self.rolloutNotice then C_Timer.After(6, function() M:ShowRolloutNotice() end) end
end

function M:OnDisable()
	self:UnregisterEvent("ENCOUNTER_START")
	self:UnregisterEvent("ENCOUNTER_END")
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	CallParts("disable")
end

function M:OnProfileChanged()
	E.CombatKit.BindSwitches(self)
	if self.ApplyMoveAll then self:ApplyMoveAll() end
	if self.active then CallParts("refresh") end
end

-- Option changes while the module is off: the Blizzard element still
-- follows its switches (handled by Core), nothing else runs.
M.refreshWhenOff = false

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
E:AddCommand("sct", "[test|move]  Combat Text settings, sample lines in every area, or move the scroll areas", function(arg)
	arg = (arg or ""):lower():match("^%s*(%S*)")
	if arg == "test" then
		M:Test()
	elseif arg == "move" then
		M:MoveAreas()
	else
		E:ToggleConfig("module:CombatText")
	end
end, "Layout & frames")

-- Sample lines in every area and on the target's plate. Out of combat only.
function M:Test()
	if InCombatLockdown() then
		E:Print(L["The Combat Text test runs out of combat only."])
		return false
	end
	if not self.active then
		E:Print(E:ModuleOffHint("CombatText"))
		return false
	end
	local conflict, title = self:Conflict()
	if conflict then
		E:Print(L["%s is loaded, so EldoUI's scrolling text stays off."]:format(title))
		return false
	end
	if self.RunTest then self:RunTest() end
	if self.PlateTest then self:PlateTest() end
	return true
end

---------------------------------------------------------------------------
-- /eui diag: what the game hands out right now.
---------------------------------------------------------------------------
M.probe = { seen = 0, secret = nil, plates = 0 }

local function Mark(flag, seen)
	if not seen or seen == 0 then return E:TextHex("secondary") .. L["not seen yet"] .. "|r" end
	return flag and (E:TextHex("warn") .. L["secret"] .. "|r") or (E:TextHex("good") .. L["readable"] .. "|r")
end

E:RegisterDiagnostics("CombatText", function()
	if not M.active then return {} end
	local probe = M.probe
	local lines = { "   " .. E:TextHex("accent") .. L["Combat Text"] .. "|r" }
	lines[#lines + 1] = ("   UNIT_COMBAT: %d, %s"):format(probe.seen, Mark(probe.secret, probe.seen))
	lines[#lines + 1] = ("   %s: %d"):format(L["Plate hits"], probe.plates)
	local conflict, title = M:Conflict()
	if conflict then lines[#lines + 1] = "   " .. L["%s is loaded, so EldoUI's scrolling text stays off."]:format(title) end
	return lines
end)
