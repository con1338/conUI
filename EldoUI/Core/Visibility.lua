-- EldoUI shared visibility rules: one "when is this frame shown"
-- block that every module reuses, so the labels, presets and behavior are
-- the same everywhere.
--
--   E:AttachVisibility(frame, block, opts)  start driving frame's alpha
--   E:UpdateVisibility(frame)               re-read the block (after a change)
--   E:DetachVisibility(frame)               full alpha again, driver removed
--   E:VisibilityOptions(prefix, opts)       the shared option rows
--   E:VisibilityDefaults(overrides)         a block for a module's defaults
--   E:ApplyVisibilityPreset(block, key)     write a preset's values
--   E:VisibilityFromLegacy(rule, alpha)     map an old per-module rule
--   E:VisibilityDriver(block)               macro string for secure frames
--   E:VisibilityIsPlain(block)              true when the block never hides
--   E:IsPlayerActive()                      the "When active" test
--   E:SetHUDHold(down)                      the Show HUD key: held = shown
--   E:VisibilityEntries()                   attached blocks, for General > Visibility
--   E:RegisterVisibilityFacet(mover, facet) how a box's frame is shown (below)
--
-- A block lives in the module's own settings:
--   { preset = "always", show = "always", fadedAlpha = 0, fadeTime = 0.2,
--     delay = 0, hideMounted = false, hideVehicle = false, groupSize = "any",
--     needFocus = "any", talentGroup = 0, hideResting = false,
--     instance = "same", fadeMoving = false }
-- (`groupOnly = true` from older profiles still works and becomes
-- groupSize = "group" the next time the block is normalized. The older
-- instance ticks hideInstance / instanceShow / fadeInstance become
-- instance = "hide" / "show" / "fade" the same way.)
--
-- How it decides: hard rules first (Never, hide while mounted / in a
-- vehicle / while resting, In instances: Hide or Only there, group size,
-- focus, talent group), then In instances: Always shown, then the Show
-- rule. In instances: Fade and "Fade while moving" fade a shown frame. Hovering a faded
-- frame shows it again (except "Never" and the hard rules).
--
-- Rules (Forever, docs/rules): every condition is the player's own,
-- non-secret state: the combat lockdown flag, UnitExists("target") and
-- UnitExists("focus"), IsMounted, UnitInVehicle, IsInGroup, IsInRaid,
-- IsInInstance, IsResting, the active talent group, IsPlayerMoving and
-- the mouse. No health, power or aura conditions. Alpha changes are allowed in combat;
-- a secure frame that must really hide gets a state driver, registered
-- out of combat through E:RunOutOfCombat.
--
-- "When active": shown in combat, with a target, while moving, casting or
-- looting, and for the idle delay (General > Visibility) after the last of
-- those ended. The Show HUD key brings every faded frame back while it is
-- held: alpha only, so it works in combat, and a protected frame its state
-- driver really hid stays hidden. A frame attached with opts.exempt (cast
-- bars, timers, alerts, windows) never follows "When active", the key or
-- the idle dim.
-- Idle dim (OLED care, Core/PixelShift.lua) lowers every other frame after
-- a long idle.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local issecret = issecretvalue or function() return false end

---------------------------------------------------------------------------
-- Rules, presets and defaults
---------------------------------------------------------------------------
-- Show rules in the order the dropdown lists them.
-- These three tables are select values, translated centrally by Config:
-- L["Always"], L["In combat"], L["Out of combat"], L["Mouse over"],
-- L["With a target"], L["In combat or with a target"], L["Never"], L["Any"],
-- L["Only when solo"], L["Only in a party"], L["Only in a raid"],
-- L["Only in a party or raid"], L["Only with a focus"], L["Only without a focus"],
-- L["When active"], L["Quiet"], L["Mouse over, out of combat"]
E.VISIBILITY_RULES = {
	always = "Always",
	combat = "In combat",
	nocombat = "Out of combat",
	mouseover = "Mouse over",
	mouseoverNoCombat = "Mouse over, out of combat",
	target = "With a target",
	combatOrTarget = "In combat or with a target",
	active = "When active",
	never = "Never",
}

local DEFAULTS = {
	preset = "always",
	show = "always",
	fadedAlpha = 0,
	fadeTime = 0.2,
	delay = 0,
	hideMounted = false,
	hideVehicle = false,
	groupOnly = false,      -- older key; read as groupSize = "group"
	groupSize = "any",      -- any | solo | party | raid | group
	needFocus = "any",      -- any | with | without
	talentGroup = 0,        -- 0 = both, 1 or 2 = only that talent group
	hideResting = false,
	instance = "same",      -- same | show | fade | hide | only (In instances)
	fadeMoving = false,
}

-- "In instances" choices, one select instead of three
-- ticks. Select values, translated centrally by Config:
-- L["Same as outside"], L["Always shown"], L["Fade"], L["Hide"], L["Only there"]
E.VISIBILITY_INSTANCE = {
	same = "Same as outside",
	show = "Always shown",
	fade = "Fade",
	hide = "Hide",
	only = "Only there",
}
local INSTANCE_ORDER = { "same", "show", "fade", "hide", "only" }

-- The block's In instances choice. Blocks from older profiles (or built
-- by hand, like the action bar driver's) may still carry the three older
-- ticks; they count until the block is normalized.
local function InstanceMode(block)
	if block.hideInstance == true then return "hide" end
	if block.instanceShow == true then return "show" end
	if block.fadeInstance == true then return "fade" end
	return E.VISIBILITY_INSTANCE[block.instance] and block.instance or "same"
end
function E:VisibilityInstanceMode(block)
	return type(block) == "table" and InstanceMode(block) or "same"
end

E.VISIBILITY_GROUP_SIZES = {
	any = "Any",
	solo = "Only when solo",
	party = "Only in a party",
	raid = "Only in a raid",
	group = "Only in a party or raid",
}
E.VISIBILITY_FOCUS = {
	any = "Any",
	with = "Only with a focus",
	without = "Only without a focus",
}

-- A preset writes these keys; every other key keeps the player's value.
E.VISIBILITY_PRESETS = {
	always = { title = "Always", show = "always", fadedAlpha = 0, fadeTime = 0.2, delay = 0 },
	combat = { title = "Combat only", show = "combat", fadedAlpha = 0, fadeTime = 0.2, delay = 0 },
	mouseover = { title = "Mouse over", show = "mouseover", fadedAlpha = 0, fadeTime = 0.2, delay = 0.5 },
	minimal = { title = "Minimal", show = "combatOrTarget", fadedAlpha = 0.15, fadeTime = 0.3, delay = 1 },
	quiet = { title = "Quiet", show = "active", fadedAlpha = 0.2, fadeTime = 0.6, delay = 0 },
}
local PRESET_KEYS = { "show", "fadedAlpha", "fadeTime", "delay" }

-- A fresh block, optionally with a few values changed (module defaults).
function E:VisibilityDefaults(overrides)
	local block = CopyTable(DEFAULTS)
	for key, value in pairs(overrides or {}) do block[key] = value end
	if overrides and overrides.show and not overrides.preset then
		block.preset = "custom"
		for key, preset in pairs(E.VISIBILITY_PRESETS) do
			local same = true
			for _, field in ipairs(PRESET_KEYS) do
				if preset[field] ~= block[field] then same = false break end
			end
			if same then block.preset = key break end
		end
	end
	return block
end

-- Old per-module values ("combat", fade alpha 0-1) as a block. Modules
-- call it once from their settings migration.
local LEGACY = { combatOrTarget = "combatOrTarget", mouseover = "mouseover", combat = "combat",
	target = "target", always = "always", never = "never", ooc = "nocombat", nocombat = "nocombat",
	outOfCombat = "nocombat", hover = "mouseover" }
function E:VisibilityFromLegacy(rule, fadedAlpha)
	return self:VisibilityDefaults({ show = LEGACY[rule] or "always", fadedAlpha = tonumber(fadedAlpha) or 0 })
end

-- True when the block never hides or fades the frame (Always, no hard
-- rule, no instance or movement rule): a module can leave its frame alone.
function E:VisibilityIsPlain(block)
	if type(block) ~= "table" then return true end
	if (block.show or "always") ~= "always" then return false end
	if block.hideMounted or block.hideVehicle or block.hideResting or block.fadeMoving or block.groupOnly then return false end
	if (block.groupSize or "any") ~= "any" or (block.needFocus or "any") ~= "any" then return false end
	if (tonumber(block.talentGroup) or 0) ~= 0 then return false end
	return InstanceMode(block) == "same"
end

function E:ApplyVisibilityPreset(block, key)
	local preset = E.VISIBILITY_PRESETS[key]
	if type(block) ~= "table" or not preset then return false end
	for _, field in ipairs(PRESET_KEYS) do block[field] = preset[field] end
	block.preset = key
	return true
end

local function Fill(block)
	for key, value in pairs(DEFAULTS) do
		if block[key] == nil then block[key] = value end
	end
	if not E.VISIBILITY_RULES[block.show] then block.show = "always" end
	if not E.VISIBILITY_GROUP_SIZES[block.groupSize] then block.groupSize = "any" end
	if not E.VISIBILITY_FOCUS[block.needFocus] then block.needFocus = "any" end
	local talent = tonumber(block.talentGroup)
	block.talentGroup = (talent == 1 or talent == 2) and talent or 0
	-- Older "Only in a group" toggle: now one choice of the group size.
	if block.groupOnly == true then
		if block.groupSize == "any" then block.groupSize = "group" end
		block.groupOnly = false
	end
	-- Older instance ticks (they excluded each other): one choice now.
	-- A tick set later (an older plugin) still wins, then goes away.
	block.instance = InstanceMode(block)
	block.hideInstance, block.instanceShow, block.fadeInstance = nil, nil, nil
end

-- The preset dropdown writes the raw keys; a raw key changed by hand turns
-- the dropdown to "Custom". `applied` remembers the preset each block was
-- last brought in line with (runtime only, nothing extra is saved).
local applied = setmetatable({}, { __mode = "k" })

local function MatchesPreset(block, key)
	local preset = E.VISIBILITY_PRESETS[key]
	if not preset then return false end
	for _, field in ipairs(PRESET_KEYS) do
		if preset[field] ~= block[field] then return false end
	end
	return true
end

function E:NormalizeVisibility(block)
	if type(block) ~= "table" then return end
	Fill(block)
	local preset = block.preset
	if E.VISIBILITY_PRESETS[preset] and applied[block] ~= nil and applied[block] ~= preset then
		-- The dropdown just changed: write the preset.
		E:ApplyVisibilityPreset(block, preset)
	elseif not (E.VISIBILITY_PRESETS[preset] and MatchesPreset(block, preset)) then
		-- A raw value changed by hand (or an older profile): Custom, unless
		-- the values happen to be exactly another preset.
		block.preset = "custom"
		for key in pairs(E.VISIBILITY_PRESETS) do
			if MatchesPreset(block, key) then
				block.preset = key
				break
			end
		end
	end
	applied[block] = block.preset
end

---------------------------------------------------------------------------
-- State the rules read (all non-secret)
---------------------------------------------------------------------------
local function Bool(value)
	if issecret(value) then return nil end
	return value and true or false
end

local function InCombat()
	return InCombatLockdown() and true or false
end

local function HasTarget(hostileOnly)
	if not UnitExists("target") then return false end
	if not hostileOnly then return true end
	local hostile = Bool(UnitCanAttack("player", "target"))
	if hostile == nil then return true end
	return hostile
end

local function Mounted()
	return IsMounted and Bool(IsMounted()) or false
end

local function InVehicle()
	if UnitHasVehicleUI and Bool(UnitHasVehicleUI("player")) then return true end
	return UnitInVehicle and Bool(UnitInVehicle("player")) or false
end

local function Grouped()
	return IsInGroup and Bool(IsInGroup()) or false
end

local function InRaid()
	return IsInRaid and Bool(IsInRaid()) or false
end

-- The block's group size, with the older groupOnly toggle read as "group"
-- for a block nobody normalized yet (a module's own driver, a fresh style).
local function GroupSize(block)
	local size = block.groupSize
	if (size == nil or size == "any") and block.groupOnly == true then return "group" end
	return E.VISIBILITY_GROUP_SIZES[size] and size or "any"
end

local function GroupMatches(size)
	if size == "any" then return true end
	if size == "solo" then return not Grouped() end
	if size == "raid" then return InRaid() end
	if size == "party" then return Grouped() and not InRaid() end
	return Grouped() -- "group"
end

local function HasFocus()
	return UnitExists and Bool(UnitExists("focus")) or false
end

local function FocusMatches(rule)
	if rule == "with" then return HasFocus() end
	if rule == "without" then return not HasFocus() end
	return true
end

-- The active talent group (dual specialization): 1 or 2.
local function ActiveTalentGroup()
	local group
	if C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup then
		group = C_SpecializationInfo.GetActiveSpecGroup()
	elseif _G.GetActiveTalentGroup then
		group = _G.GetActiveTalentGroup()
	end
	if issecret(group) then return 1 end
	return tonumber(group) or 1
end

local function NumTalentGroups()
	local count = GetNumSpecGroups and GetNumSpecGroups() or nil
	if issecret(count) then return 1 end
	if type(count) == "nil" and _G.GetNumTalentGroups then count = _G.GetNumTalentGroups() end
	if issecret(count) then return 1 end
	return tonumber(count) or 1
end

local function TalentMatches(block)
	local wanted = tonumber(block.talentGroup) or 0
	return wanted == 0 or ActiveTalentGroup() == wanted
end

local function Resting()
	return IsResting and Bool(IsResting()) or false
end

local function InInstance()
	if not IsInInstance then return false end
	local inside, kind = IsInInstance()
	if issecret(inside) then return false end
	return inside and kind ~= "none" or false
end

---------------------------------------------------------------------------
-- Activity: the player's own state only. Casting and looting come
-- from the player's own cast and loot events; nothing about other units.
---------------------------------------------------------------------------
E.defaults.general.quietHUD = {
	idleDelay = 6,        -- seconds "When active" stays shown after activity
	idleAlpha = 0.2,      -- faded opacity "When active" for all writes
	holdKey = true,       -- the Show HUD key binding works
	pixelShift = false,   -- OLED care (Core/PixelShift.lua), off by default
	shiftInterval = 3,    -- minutes between steps
	shiftRange = 2,       -- screen pixels, 1 or 2
	idleDim = false,      -- dim the HUD after a long idle
	idleDimAfter = 5,     -- minutes
	idleDimAlpha = 0.5,   -- share of the normal opacity while dimmed
}

local activity = { casting = false, looting = false, last = nil, hold = false, dimmed = false }
E.hudActivity = activity

local function QuietSettings()
	local general = E.db and E.db.general
	local quiet = general and general.quietHUD
	return type(quiet) == "table" and quiet or E.defaults.general.quietHUD
end
E.QuietSettings = QuietSettings

local function Now()
	return GetTime and GetTime() or 0
end

-- Active this moment, before the idle delay.
local function ActiveNow()
	if InCombatLockdown() then return true end
	if UnitExists("target") then return true end
	if IsPlayerMoving and Bool(IsPlayerMoving()) then return true end
	return activity.casting or activity.looting
end

-- Seconds left until "When active" fades, 0 when it already has.
local function ActiveLeft()
	if ActiveNow() then return math.huge end
	local last = activity.last
	if not last then return 0 end
	local delay = tonumber(QuietSettings().idleDelay) or 0
	return math.max(0, last + delay - Now())
end

function E:IsPlayerActive()
	return ActiveLeft() > 0
end

-- Minutes without any activity (idle dim).
function E:IdleSeconds()
	if ActiveNow() then return 0 end
	return math.max(0, Now() - (activity.last or activity.start or Now()))
end

-- opts.inInstance lets a module decide which instances count (the quest
-- tracker's instance type ticks).
local function EntryInInstance(entry)
	if entry.inInstance then return entry.inInstance() and true or false end
	return InInstance()
end

local function Moving()
	return IsPlayerMoving and Bool(IsPlayerMoving()) or false
end

-- `keepInVehicle` (per frame) beats "Hide in a vehicle", e.g. action bar 1
-- while it shows the vehicle's actions.
local function KeepInVehicle(entry)
	local keep = entry.keepInVehicle
	if type(keep) == "function" then return keep() and true or false end
	return keep and true or false
end

---------------------------------------------------------------------------
-- Attached frames
---------------------------------------------------------------------------
local entries = {}   -- frame -> entry
local driver = CreateFrame("Frame")
driver:Hide()

local function Animations()
	return E.db and E.db.general and E.db.general.animations ~= false
end

local function MouseOver(entry)
	if entry.alsoOver then
		local ok, over = pcall(entry.alsoOver)
		if ok and over then return true end
	end
	local watch = entry.watch
	if type(watch) == "table" and watch.IsMouseOver then
		return watch:IsVisible() and watch:IsMouseOver() and true or false
	end
	if type(watch) == "table" then
		for _, frame in ipairs(watch) do
			if frame.IsMouseOver and frame:IsVisible() and frame:IsMouseOver() then return true end
		end
	end
	return false
end

-- 1 = shown, "faded" = the rule says fade, 0 = hard hidden.
local function Wanted(entry)
	local block = entry.block
	local show = block.show
	if show == "never" then return 0 end
	-- "Mouse over, out of combat": gone in combat (a protected frame is
	-- hidden by its state driver), so the mouse never brushes it in a fight.
	if show == "mouseoverNoCombat" and InCombat() then return 0 end
	if show == "active" and entry.exempt then show = "always" end
	if entry.forceShow and entry.forceShowFirst and entry.forceShow() then return 1 end
	if block.hideMounted and Mounted() then return 0 end
	if block.hideVehicle and InVehicle() and not KeepInVehicle(entry) then return 0 end
	local instance = InstanceMode(block)
	if instance == "hide" and EntryInInstance(entry) then return 0 end
	if instance == "only" and not EntryInInstance(entry) then return 0 end
	if not GroupMatches(GroupSize(block)) then return 0 end
	if not FocusMatches(block.needFocus) then return 0 end
	if not TalentMatches(block) then return 0 end
	if block.hideResting and Resting() then return 0 end
	if entry.forceShow and entry.forceShow() then return 1 end
	-- The Show HUD key: everything the hard rules left shown comes back.
	if activity.hold and not entry.exempt then return 1 end
	if instance == "show" and EntryInInstance(entry) then return 1 end
	if MouseOver(entry) then return 1 end
	if instance == "fade" and EntryInInstance(entry) then return "faded" end
	if block.fadeMoving and Moving() then return "faded" end
	if show == "always" then return 1 end
	local combat = InCombat()
	if show == "combat" and combat then return 1 end
	if show == "nocombat" and not combat then return 1 end
	if show == "target" and HasTarget(entry.hostileTarget) then return 1 end
	if show == "combatOrTarget" and (combat or HasTarget(entry.hostileTarget)) then return 1 end
	if show == "active" and E:IsPlayerActive() then return 1 end
	return "faded"
end

local function FullAlpha(entry)
	local alpha = entry.alpha
	if type(alpha) == "function" then alpha = alpha() end
	return tonumber(alpha) or 1
end

-- Click-through while faded out: a frame at alpha 0 shows nothing, so it
-- and its children stop taking the mouse, and take it back once they show.
-- "Mouse over" keeps the mouse, since the player reaches for those frames;
-- "Mouse over, out of combat" keeps it only out of combat.
-- Protected frames are left alone (they could not take the mouse back in
-- combat; rules that fade them to nothing hide them with a state driver),
-- and so are frames named by others (Blizzard frames under a fader).
local function MouseWanted(entry)
	local show = entry.block.show
	if show == "mouseoverNoCombat" and InCombat() then return false end
	return show == "mouseover" or show == "mouseoverNoCombat" or (entry.current or 1) > 0.01
end

local function OwnFrame(frame, root)
	if frame == root then return true end
	local name = frame.GetName and frame:GetName()
	return type(name) ~= "string" or name:find("^EldoUI") ~= nil
end

-- A frame the game hides from addons (its mouse state reads as a secret
-- value) counts as not taking the mouse, so it is left alone.
local function MuteMouse(entry, frame, depth)
	if depth > 12 or not OwnFrame(frame, entry.frame) then return end
	if E.FrameMouse(frame, "IsMouseEnabled") and not E.FrameCheck(frame, "IsProtected") then
		frame:EnableMouse(false)
		entry.muted = entry.muted or {}
		entry.muted[frame] = true
	end
	if frame.GetChildren then
		for _, child in ipairs({ frame:GetChildren() }) do MuteMouse(entry, child, depth + 1) end
	end
end

local function ApplyMouse(entry, restore)
	if not restore and not MouseWanted(entry) then
		MuteMouse(entry, entry.frame, 0)
	elseif entry.muted then
		for frame in pairs(entry.muted) do frame:EnableMouse(true) end
		entry.muted = nil
	end
end

local function SetAlpha(entry, alpha)
	entry.current = alpha
	entry.frame:SetAlpha(alpha)
	if entry.onAlpha then entry.onAlpha(entry.frame, alpha) end
	local shown = alpha > 0.01
	if entry.mouseShown ~= shown then
		entry.mouseShown = shown
		ApplyMouse(entry)
	end
end

local function Retarget(entry, now)
	-- The out-of-combat hover rule takes the mouse away when a fight starts,
	-- also while the frame already sat faded out.
	if entry.block.show == "mouseoverNoCombat" then
		local fight = InCombat()
		if entry.mouseFight ~= fight then
			entry.mouseFight = fight
			ApplyMouse(entry)
		end
	end
	local wanted = Wanted(entry)
	local full = FullAlpha(entry)
	local target
	if wanted == 1 then
		target = full
	elseif wanted == 0 then
		target = 0
	else
		target = math.max(0, math.min(1, tonumber(entry.block.fadedAlpha) or 0)) * full
	end
	-- Idle dim (OLED care): a shown frame goes down to its share.
	if activity.dimmed and not entry.exempt and target > 0 and not activity.hold then
		target = target * math.max(0, math.min(1, tonumber(QuietSettings().idleDimAlpha) or 1))
	end
	if entry.target == target and not now then return end
	entry.target = target
	local current = entry.current or entry.frame:GetAlpha()
	if issecret(current) then current = full end
	local fadeTime = tonumber(entry.block.fadeTime) or 0
	if now or not Animations() or fadeTime <= 0 or current == target then
		entry.fade = nil
		SetAlpha(entry, target)
		return
	end
	-- Fading out waits for the delay; fading in starts at once.
	local delay = target < current and (tonumber(entry.block.delay) or 0) or 0
	entry.fade = { from = current, to = target, time = -delay, duration = fadeTime }
	driver:Show()
end

local function NeedsPolling(entry)
	local show = entry.block.show
	if show == "never" or entry.watch == nil then return false end
	return show ~= "always" or (entry.block.fadeMoving or InstanceMode(entry.block) == "fade") and true or false
end

local pollElapsed = 0
driver:SetScript("OnUpdate", function(self, elapsed)
	local busy = false
	for _, entry in pairs(entries) do
		local fade = entry.fade
		if fade then
			fade.time = fade.time + elapsed
			if fade.time >= 0 then
				local progress = math.min(fade.time / fade.duration, 1)
				SetAlpha(entry, fade.from + (fade.to - fade.from) * progress)
				if progress >= 1 then entry.fade = nil end
			end
			busy = true
		end
	end
	-- Mouse over is polled a few times a second, only while a rule needs it.
	pollElapsed = pollElapsed + elapsed
	local polling = false
	for _, entry in pairs(entries) do
		if NeedsPolling(entry) then polling = true break end
	end
	if polling and pollElapsed >= 0.1 then
		pollElapsed = 0
		for _, entry in pairs(entries) do
			if NeedsPolling(entry) then Retarget(entry) end
		end
	end
	if not busy and not polling then self:Hide() end
end)

local function UpdateAll()
	for _, entry in pairs(entries) do Retarget(entry) end
	driver:Show()
end

---------------------------------------------------------------------------
-- Secure frames: a state driver hides them for real (an invisible action
-- button would still take clicks). Only rules a macro conditional can
-- express go into the driver; mouse over stays alpha-only so the frame can
-- still notice the cursor.
---------------------------------------------------------------------------
local CONDITION = {
	combat = "[combat] show; hide",
	nocombat = "[combat] hide; show",
	mouseoverNoCombat = "[combat] hide; show",
	target = "[@target,exists] show; hide",
	combatOrTarget = "[combat] show; [@target,exists] show; hide",
}

local GROUP_CONDITION = {
	solo = "[group] hide",
	party = "[nogroup] hide; [group:raid] hide",
	raid = "[nogroup:raid] hide",
	group = "[nogroup] hide",
}
local FOCUS_CONDITION = {
	with = "[@focus,noexists] hide",
	without = "[@focus,exists] hide",
}

-- Talent group and resting have no macro conditional. They only change
-- with an event, so a driver can carry their current state ("hide" now)
-- and be rebuilt when they change: opts.staticState. Attached secure
-- frames get that automatically; a module with its own drivers rebuilds
-- them on ACTIVE_TALENT_GROUP_CHANGED and PLAYER_UPDATE_RESTING when
-- E:VisibilityUsesState(block) is true.
function E:VisibilityUsesState(block)
	if type(block) ~= "table" then return false end
	return (tonumber(block.talentGroup) or 0) ~= 0 or block.hideResting == true
end

local function StateHides(block)
	return not TalentMatches(block) or (block.hideResting and Resting()) or false
end

-- opts.keepInVehicle leaves "Hide in a vehicle" out (see AttachVisibility).
-- opts.staticState puts the talent group and resting state in the driver.
-- opts.condition: the frame's own macro clauses, put before the block's
-- rules ("[@pet,noexists] hide"); "show" keeps the frame shown whatever
-- the block says (a preview), "hide" keeps it hidden.
function E:VisibilityDriver(block, opts)
	if type(block) ~= "table" then return nil end
	local condition = opts and opts.condition
	if condition == "show" or condition == "hide" then return condition end
	if block.show == "never" then return "hide" end
	if opts and opts.staticState and StateHides(block) then return "hide" end
	local parts = {}
	if type(condition) == "string" and condition ~= "" then parts[1] = condition end
	if block.hideVehicle and not (opts and opts.keepInVehicle) then parts[#parts + 1] = "[vehicleui][overridebar] hide" end
	if block.hideMounted then parts[#parts + 1] = "[mounted] hide" end
	local group = GROUP_CONDITION[GroupSize(block)]
	if group then parts[#parts + 1] = group end
	local focus = FOCUS_CONDITION[block.needFocus]
	if focus then parts[#parts + 1] = focus end
	-- A rule fades to nothing: hide for real. Instances and movement can't
	-- be tested by a macro conditional, so any In instances choice but
	-- "Same as outside", and "Fade while moving", keep alpha only.
	local rule = CONDITION[block.show]
	if block.show == "mouseoverNoCombat" then
		-- Hidden in combat for real, whatever the faded opacity: out of
		-- combat the hover fade is alpha only.
		parts[#parts + 1] = rule
	elseif rule and (tonumber(block.fadedAlpha) or 0) <= 0 and InstanceMode(block) == "same" and not block.fadeMoving then
		parts[#parts + 1] = rule
	elseif #parts > 0 then
		parts[#parts + 1] = "show"
	else
		return nil
	end
	return table.concat(parts, "; ")
end

-- The frame's own condition (opts.condition of AttachVisibility), read now.
local function Condition(entry)
	local condition = entry.condition
	if type(condition) == "function" then condition = condition() end
	return type(condition) == "string" and condition or nil
end

local function DriverText(entry)
	if not entry.secure then return nil end
	return E:VisibilityDriver(entry.block, { keepInVehicle = KeepInVehicle(entry), staticState = true, condition = Condition(entry) })
end

local function ApplyDriver(entry)
	local frame = entry.frame
	local text = DriverText(entry)
	if text == entry.driverText then return end
	E:RunOutOfCombat(function()
		if entries[frame] ~= entry then return end
		local now = DriverText(entry)
		if now == entry.driverText then return end
		if entry.driverText and UnregisterStateDriver then UnregisterStateDriver(frame, "visibility") end
		entry.driverText = now
		if now and RegisterStateDriver then
			RegisterStateDriver(frame, "visibility", now)
		elseif entry.restoreShown then
			frame:Show()
		end
	end)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
-- frame: the frame whose alpha follows the rule (your own frame or holder;
--   for Blizzard frames use a fader parent, see CombatHUD/Kit.lua).
-- block: the visibility block in your settings (read live).
-- opts.watch:   frame (or list) the mouse-over test looks at; default frame
-- opts.alsoOver: function; true counts as the mouse on the frame too (a
--               flyout of the frame's buttons that sits outside it)
-- opts.alpha:   full alpha as a number or function (default 1)
-- opts.secure:  true for protected frames: hard rules use a state driver
-- opts.hostileTarget: "target" rules count hostile targets only
-- opts.forceShow: function; true keeps the frame shown (e.g. move mode)
-- opts.forceShowFirst: forceShow also beats the hard rules (mounted,
--   vehicle, instance, group); "Never" still hides
-- opts.keepInVehicle: true or function; ignore "Hide in a vehicle" while
--   true (also left out of the secure driver)
-- opts.onAlpha: function(frame, alpha) after every alpha change
-- opts.inInstance: function; true while the frame counts as "in an
--   instance" (default: any dungeon, raid, battleground, arena, scenario)
-- opts.exempt: true for frames the idle rule must never fade (windows,
--   cast bars, timers, alerts): "When active" reads as Always, and the
--   Show HUD key and the idle dim leave them alone
-- opts.module: module name for General > Visibility (default: the module
--   that is enabling)
-- opts.condition: with opts.secure, the frame's own macro clauses (a
--   string, or a function returning one) put before the block's rules in
--   the one state driver, such as "[@pet,noexists][@pet,dead] hide";
--   "show" or "hide" settle it (see E:VisibilityDriver). A module whose
--   condition changes calls E:UpdateVisibility(frame).
-- opts.restoreShown: false leaves the frame hidden when it is detached
function E:AttachVisibility(frame, block, opts)
	if type(frame) ~= "table" or not frame.SetAlpha then return end
	opts = opts or {}
	self:NormalizeVisibility(block)
	local entry = entries[frame]
	if not entry then
		entry = { frame = frame }
		entries[frame] = entry
	end
	entry.block = block
	entry.watch = opts.watch or frame
	if opts.watch == false then entry.watch = nil end
	entry.alsoOver = type(opts.alsoOver) == "function" and opts.alsoOver or nil
	entry.alpha = opts.alpha
	entry.secure = opts.secure and true or false
	entry.hostileTarget = opts.hostileTarget
	entry.forceShow = opts.forceShow
	entry.forceShowFirst = opts.forceShowFirst and true or false
	entry.keepInVehicle = opts.keepInVehicle
	entry.onAlpha = opts.onAlpha
	entry.inInstance = type(opts.inInstance) == "function" and opts.inInstance or nil
	entry.restoreShown = opts.restoreShown ~= false
	entry.exempt = opts.exempt and true or false
	entry.condition = opts.condition
	entry.module = opts.module or (E.currentModule and E.currentModule.name) or entry.module
	entry.target = nil
	ApplyDriver(entry)
	Retarget(entry)
	ApplyMouse(entry)
	driver:Show()
	return frame
end

function E:UpdateVisibility(frame, now)
	local entry = entries[frame]
	if not entry then return end
	self:NormalizeVisibility(entry.block)
	ApplyDriver(entry)
	entry.target = nil
	Retarget(entry, now)
	ApplyMouse(entry)
	driver:Show()
end

function E:RefreshVisibility()
	for frame in pairs(entries) do self:UpdateVisibility(frame) end
end

function E:IsVisibilityAttached(frame)
	return entries[frame] ~= nil
end

function E:DetachVisibility(frame)
	local entry = entries[frame]
	if not entry then return end
	entries[frame] = nil
	entry.fade = nil
	ApplyMouse(entry, true)
	if entry.driverText then
		local text = entry.driverText
		entry.driverText = nil
		E:RunOutOfCombat(function()
			if entries[frame] then return end -- attached again meanwhile
			if text and UnregisterStateDriver then UnregisterStateDriver(frame, "visibility") end
			if entry.restoreShown then frame:Show() end
		end)
	end
	local full = FullAlpha(entry)
	frame:SetAlpha(full)
	if entry.onAlpha then entry.onAlpha(frame, full) end
end

-- Events that change a condition. All exist on Forever (API docs).
-- Talent group and resting are carried in secure drivers, so those
-- drivers are rebuilt (out of combat) when they change.
local STATE_EVENTS = { ACTIVE_TALENT_GROUP_CHANGED = true, PLAYER_UPDATE_RESTING = true, PLAYER_ENTERING_WORLD = true }
for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED",
	"PLAYER_FOCUS_CHANGED", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_MOUNT_DISPLAY_CHANGED",
	"UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "UPDATE_OVERRIDE_ACTIONBAR", "ZONE_CHANGED_NEW_AREA",
	"PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_UPDATE_RESTING" }) do
	E:RegisterEvent(event, function(_, name, unit)
		if (name == "UNIT_ENTERED_VEHICLE" or name == "UNIT_EXITED_VEHICLE") and unit ~= "player" then return end
		E:NoteActivity()
		if not next(entries) then return end
		if STATE_EVENTS[name] then
			for _, entry in pairs(entries) do
				if entry.secure then ApplyDriver(entry) end
			end
		end
		UpdateAll()
	end, entries)
end

---------------------------------------------------------------------------
-- Activity events. Any change of the "active now" state stamps the
-- time; when it ends, one timer re-checks the frames after the idle delay.
---------------------------------------------------------------------------
local wasActive = false
local timerToken = 0

local function UsesActive()
	for _, entry in pairs(entries) do
		if entry.block.show == "active" and not entry.exempt then return true end
	end
	return false
end

function E:NoteActivity()
	local now = ActiveNow()
	if now or wasActive then activity.last = Now() end
	if now and activity.dimmed then
		activity.dimmed = false
		if next(entries) then UpdateAll() end
	end
	if wasActive and not now and UsesActive() and C_Timer and C_Timer.After then
		timerToken = timerToken + 1
		local token = timerToken
		local delay = (tonumber(QuietSettings().idleDelay) or 0) + 0.05
		C_Timer.After(delay, function()
			if token == timerToken then UpdateAll() end
		end)
	end
	wasActive = now
end

-- The idle dim (OLED care): Core/PixelShift.lua checks it now and then.
function E:SetIdleDimmed(on)
	on = on and true or false
	if activity.dimmed == on then return end
	activity.dimmed = on
	if next(entries) then UpdateAll() end
end

function E:IsIdleDimmed()
	return activity.dimmed
end

-- The Show HUD key (Bindings.xml, runOnUp): shown while held. Alpha only,
-- so it is allowed in combat; fading back starts on release.
function E:SetHUDHold(down)
	down = down and true or false
	if down and QuietSettings().holdKey == false then down = false end
	if activity.hold == down then return end
	activity.hold = down
	if down then activity.dimmed = false end
	activity.last = Now()
	if next(entries) then UpdateAll() end
end

function E:IsHUDHeld()
	return activity.hold
end

-- Attached blocks, for General > Visibility: { frame, block, module, exempt }.
function E:VisibilityEntries()
	local list = {}
	for frame, entry in pairs(entries) do
		list[#list + 1] = { frame = frame, block = entry.block, module = entry.module, exempt = entry.exempt }
	end
	return list
end

---------------------------------------------------------------------------
-- The visibility facet: how the frame behind each box (mover) is shown,
-- so every HUD piece follows the same engine.
--   "rules"   a HUD piece: it follows a visibility block in its module's
--             settings, made with E:VisibilityDefaults in the module's
--             defaults and attached with E:AttachVisibility. A protected
--             frame passes opts.secure, and a condition of its own (only
--             with a pet, only for leaders) goes in opts.condition, so the
--             engine registers the one state driver; a module registers
--             no visibility state driver itself.
--   "event"   shows only while it has something to show (an alert, a
--             toast, a prompt, a cast bar, a running timer); the HUD
--             rules, the Show HUD key and the idle dim leave it alone.
--   "window"  a window the player opens and closes.
--   E:RegisterVisibilityFacet(mover, facet[, info])
--       info.module   the module the box belongs to
--       info.setting  "rules": the block's dotted path in the module's
--                     settings, such as "visibility"
--   E:VisibilityFacet(mover)  facet, info: as declared; a box nobody
--       declared counts as "rules" while its frame is attached
--   E:VisibilityFacetBlock(mover)  the block a "rules" box follows
--   E:VisibilityFacets()  mover -> info, every declared facet
---------------------------------------------------------------------------
E.VISIBILITY_FACETS = { rules = true, event = true, window = true }
local facets = {}

function E:RegisterVisibilityFacet(mover, facet, info)
	assert(type(mover) == "string", "EldoUI:RegisterVisibilityFacet(mover, facet, info): mover must be a name")
	assert(E.VISIBILITY_FACETS[facet], "EldoUI:RegisterVisibilityFacet: facet is rules, event or window")
	local record = { facet = facet }
	for key, value in pairs(info or {}) do record[key] = value end
	facets[mover] = record
	return record
end

-- Boxes of modules that do not declare their facet in their own files yet;
-- a module's own declaration replaces its line here.
local SHARED_FACETS = {
	event = {
		Notifications = { "EldoUI_AlertLane", "EldoUI_Banners", "EldoUI_TalkingHead", "EldoUI_RaidWarning", "EldoUI_Errors",
			"EldoUI_ZoneText", "EldoUI_ReadyCheck", "EldoUI_SocialToasts", "EldoUI_PingFeed" },
		QoL = { "EldoUI_Prompt", "EldoUI_FlightBar" },
		RareScanner = { "EldoUI_RareAlert" },
		SystemUI = { "EldoUI_Popups" },
		Tooltip = { "EldoUI_Tooltip" },
		UnitFrames = { "EldoUI_PlayerCastbar", "EldoUI_BossEmote" },
		ZoneInfo = { "EldoUI_ZoneToast" },
	},
	window = {
		QoL = { "EldoUI_Volume" },
		RaidLoot = { "EldoUI_GDKPLedger" },
		ReadyReport = { "EldoUI_ReadyReport" },
		Talents = { "EldoUI_TalentPlanner" },
		Trade = { "EldoUI_TradeWindow" },
		Training = { "EldoUI_TrainingWindow" },
	},
}
for facet, byModule in pairs(SHARED_FACETS) do
	for module, movers in pairs(byModule) do
		for _, mover in ipairs(movers) do E:RegisterVisibilityFacet(mover, facet, { module = module }) end
	end
end
E:RegisterVisibilityFacet("EldoUI_ShoppingList", "rules", { module = "ProfessionPlanner", setting = "visibility" })
for unit, mover in pairs({ player = "EldoUI_Player", target = "EldoUI_Target", targettarget = "EldoUI_ToT", focus = "EldoUI_Focus",
	focustarget = "EldoUI_FocusTarget", pet = "EldoUI_Pet", pettarget = "EldoUI_PetTarget", boss = "EldoUI_Boss",
	partypet = "EldoUI_PartyPets", partytarget = "EldoUI_PartyTargets" }) do
	E:RegisterVisibilityFacet(mover, "rules", { module = "UnitFrames", setting = "units." .. unit .. ".fader" })
end
-- The detached power bar fades with the player frame.
E:RegisterVisibilityFacet("EldoUI_PlayerFramePower", "rules", { module = "UnitFrames", setting = "units.player.fader" })

function E:VisibilityFacet(mover)
	local record = facets[mover]
	if record then return record.facet, record end
	local box = E.movers and E.movers[mover]
	local entry = box and box.frame and entries[box.frame]
	if entry then return "rules", { facet = "rules", module = entry.module, attached = true } end
	return nil
end

-- A dotted path in a settings table ("units.player.fader").
local function AtPath(db, path)
	local node = db
	for key in path:gmatch("[^%.]+") do
		if type(node) ~= "table" then return nil end
		node = node[key]
	end
	return node
end

function E:VisibilityFacetBlock(mover)
	local facet, record = self:VisibilityFacet(mover)
	if facet ~= "rules" then return nil end
	if record.attached then
		local entry = entries[E.movers[mover].frame]
		return entry and entry.block
	end
	local module = record.module and E.modules[record.module]
	local db = module and module.db
	if type(db) ~= "table" or type(record.setting) ~= "string" then return nil end
	local block = AtPath(db, record.setting)
	return type(block) == "table" and block or nil
end

function E:VisibilityFacets()
	local list = {}
	for mover, record in pairs(facets) do list[mover] = record end
	return list
end

-- The player's own casts only: the game filters the unit (Core/Init.lua).
local function OnCast(_, event)
	activity.casting = event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START"
	E:NoteActivity()
	if next(entries) then UpdateAll() end
end
for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
	E:RegisterUnitEvent(event, "player", OnCast, activity)
end
for _, event in ipairs({ "LOOT_OPENED", "LOOT_CLOSED" }) do
	E:RegisterEvent(event, function(_, name)
		activity.looting = name == "LOOT_OPENED"
		E:NoteActivity()
		if next(entries) then UpdateAll() end
	end, activity)
end
E:RegisterEvent("PLAYER_LOGIN", function()
	activity.start = Now()
end, activity, "engines")
-- A loading screen ends any cast or loot window whose closing event was lost.
E:RegisterEvent("PLAYER_ENTERING_WORLD", function()
	activity.casting, activity.looting = false, false
	activity.last = Now()
end, activity)

---------------------------------------------------------------------------
-- Option rows: one shared block for every module page.
--   prefix:  dotted path of the block in the module's settings
--   opts.label   section header (default "Visibility"; false for none)
--   opts.secure  mention that the frame really hides (protected frames)
--   opts.rules   list of rule keys to offer (default all)
--   opts.hidden  function: hide every row (e.g. the feature is off)
--   opts.db      function returning the module settings (recommended)
--   opts.instanceText  which instances count, for the row texts (with
--                AttachVisibility's opts.inInstance)
--   opts.exempt  the frame is attached with opts.exempt: no "When active"
--   opts.disabled  function returning a reason (or nil): grays every row
-- Rare settings carry `cog = true` and come right after "Show", so the
-- options window folds them into the gear of the Show row.
---------------------------------------------------------------------------
local function Values(source, keys)
	if not keys then return source end
	local out = {}
	for _, key in ipairs(keys) do out[key] = source[key] end
	return out
end

function E:VisibilityOptions(prefix, opts)
	opts = opts or {}
	local p = prefix .. "."
	local parentHidden = opts.hidden
	-- opts.db: function returning the module's settings; lets rows hide
	-- what has no effect and keeps the preset dropdown in sync.
	local function Block()
		local db = opts.db and opts.db()
		local block = db and E.GetPath and E.GetPath(db, prefix)
		if type(block) == "table" then
			E:NormalizeVisibility(block)
			return block
		end
	end
	local function Hidden(test)
		return function()
			if parentHidden and parentHidden() then return true end
			local block = Block()
			return block and test and test(block) or false
		end
	end
	-- Translated centrally with the select values: L["Custom"]
	-- "Custom" is only a name for values that match no preset: it shows
	-- while the block is custom and is never a choice of its own.
	local presetChoices = {}
	for key, preset in pairs(E.VISIBILITY_PRESETS) do
		if not (opts.exempt and preset.show == "active") then presetChoices[key] = preset.title end
	end
	local function PresetValues()
		local block = Block()
		if not (block and block.preset == "custom") then return presetChoices end
		local values = { custom = "Custom" }
		for key, title in pairs(presetChoices) do values[key] = title end
		return values
	end
	local rows = {}
	if opts.label ~= false then
		rows[#rows + 1] = { type = "header", label = opts.label or "Visibility", hidden = parentHidden }
	end
	rows[#rows + 1] = { type = "select", key = p .. "preset", label = "Visibility preset", values = PresetValues,
		desc = "Always: never fades. Combat only: in combat. Mouse over: while the mouse is on it. Minimal: in combat or with a target. Quiet: while you are active. A change below makes it Custom.",
		hidden = Hidden() }
	-- opts.exempt: a window the idle rule leaves alone offers no "When active".
	local ruleValues = Values(E.VISIBILITY_RULES, opts.rules)
	if opts.exempt then
		local copy = {}
		for key, value in pairs(ruleValues) do
			if key ~= "active" then copy[key] = value end
		end
		ruleValues = copy
	end
	rows[#rows + 1] = { type = "select", key = p .. "show", label = "Show", values = ruleValues,
		desc = opts.secure
			and E.Key("When the frame is shown. Outside the rule it fades to the faded alpha; at 0 it is hidden for real, so it takes no clicks (When active only fades it, so it still takes clicks). Hovering shows it again.")
			or E.Key("When the frame is shown. Outside the rule it fades to the faded alpha. Hovering a faded frame shows it again."),
		hidden = Hidden() }
	local function Constant(block) return block.show == "always" or block.show == "never" end
	-- Fading matters for a rule that hides, or for In instances: Fade /
	-- "Fade while moving".
	local function NoFade(block)
		return block.show == "never" or (block.show == "always" and not block.fadeMoving and block.instance ~= "fade")
	end
	-- The rare settings go in the gear of "Show" (cog rows fold into the
	-- row above them), so they stay reachable while Show is Always and
	-- Faded alpha is hidden.
	rows[#rows + 1] = { type = "range", unit = "s", key = p .. "fadeTime", label = "Fade time", min = 0, max = 1, step = 0.05, cog = true, zeroText = "Instant",
		desc = "Seconds a fade takes. With animations off (General) every change is instant.", hidden = Hidden(NoFade) }
	rows[#rows + 1] = { type = "range", unit = "s", key = p .. "delay", label = "Delay before fading", min = 0, max = 3, step = 0.1, cog = true,
		desc = "Seconds the frame stays visible after the rule stops applying, e.g. after combat ends or the mouse leaves.",
		hidden = Hidden(NoFade) }
	rows[#rows + 1] = { type = "toggle", key = p .. "hideMounted", label = "Hide while mounted", cog = true,
		desc = "Hidden while you ride a mount, whatever the rule says.", hidden = Hidden() }
	rows[#rows + 1] = { type = "toggle", key = p .. "hideVehicle", label = "Hide in a vehicle", cog = true,
		desc = "Hidden while you control a vehicle or have an override bar.", hidden = Hidden() }
	rows[#rows + 1] = { type = "select", key = p .. "groupSize", label = "Group", cog = true, values = E.VISIBILITY_GROUP_SIZES,
		desc = "Shown only in this kind of group, whatever the rule says. A party is a group that is not a raid.", hidden = Hidden() }
	rows[#rows + 1] = { type = "select", key = p .. "needFocus", label = "Focus", cog = true, values = E.VISIBILITY_FOCUS,
		desc = "Shown only while you have a focus target, or only while you have none.", hidden = Hidden() }
	-- Only useful with a second talent group; a value set earlier stays
	-- reachable so it can be put back to Both.
	rows[#rows + 1] = { type = "select", key = p .. "talentGroup", label = "Talent group", cog = true,
		values = { [0] = "Both", [1] = "Talent group 1 only", [2] = "Talent group 2 only" },
		desc = "Shown only while this talent group (dual specialization) is active.",
		hidden = Hidden(function(block) return block.talentGroup == 0 and NumTalentGroups() < 2 end) }
	rows[#rows + 1] = { type = "toggle", key = p .. "hideResting", label = "Hide while resting", cog = true,
		desc = opts.secure
			and E.Key("Hidden while you rest in an inn or a city. If you start or stop resting during a fight, the frame follows once combat ends.")
			or E.Key("Hidden while you rest in an inn or a city."),
		hidden = Hidden() }
	-- In instances: one select instead of three ticks. A macro
	-- conditional can't test instances, so protected frames (which must
	-- really hide, not only turn invisible) offer only Same as outside and
	-- Always shown; Always shown means nothing while the rule is Always.
	local instances = opts.instanceText or E.Key("dungeons, raids, battlegrounds and arenas")
	local secureInstance = { same = E.VISIBILITY_INSTANCE.same, show = E.VISIBILITY_INSTANCE.show }
	rows[#rows + 1] = { type = "select", key = p .. "instance", label = "In instances", cog = true,
		values = opts.secure and secureInstance or E.VISIBILITY_INSTANCE, order = INSTANCE_ORDER,
		desc = opts.secure
			and E.Key("In %s. Same as outside: the rule above applies. Always shown: stays shown there.")
			or E.Key("In %s. Same as outside: the rule above applies. Always shown: stays shown. Fade: fades until hovered. Hide: hidden there. Only there: hidden elsewhere."),
		descFill = instances,
		hidden = Hidden(function(block)
			return block.show == "never" or (opts.secure and block.show == "always" and block.instance ~= "show")
		end) }
	rows[#rows + 1] = { type = "toggle", key = p .. "fadeMoving", label = "Fade while moving", cog = true,
		desc = "Fades to the faded alpha while your character moves and comes back when you stop. Hovering shows it again.",
		hidden = Hidden(function(block) return block.show == "never" end) }
	rows[#rows + 1] = { type = "range", percent = true, key = p .. "fadedAlpha", label = "Faded opacity", min = 0, max = 1, step = 0.05, zeroText = "Invisible",
		desc = "How visible the frame stays while the rule says hide.", hidden = Hidden(NoFade) }
	if opts.disabled then
		for _, row in ipairs(rows) do
			if row.type ~= "header" then row.disabled = opts.disabled end
		end
	end
	return rows
end
