-- EldoUI Unit Frames: player, target, target-of-target, focus, focus
-- target, pet, pet target, boss 1-5, party pets and party targets, built
-- from scratch with many style options so a layout preset can recreate very
-- different looks (portrait or not, text tags, class colors, power bar,
-- cast bar, buffs and debuffs, heal prediction, status icons, fading).
--
-- The same module also owns Blizzard's own frames for these units through
-- the per-element switches (Core/Blizzard.lua): player-frame,
-- target-focus-frames, pet-frame, boss-frames, player-cast-bar and
-- private-auras. With an element's master switch off, Blizzard's frame is
-- left exactly as Blizzard made it.
--
-- Shared engines (one copy for the whole UI):
--   texts      Core/Tags.lua (E:BindTag, E:RenderTag, E:RegisterTag)
--   fading     Core/Visibility.lua (E:AttachVisibility, E:VisibilityOptions)
--   auras      Core/AuraWidget.lua + Core/Filters.lua (E:AuraFilterGroups)
--   glows      Core/Glow.lua (E:RegisterGlowUser, E:ShowUserGlow)
--   effects    Core/UnitFX.lua (curves, gates, threat, low health, range,
--              important casts, the Effects tab and its presets) and
--              Core/FrameFX.lua (dead look, target flash, status pulse,
--              ready check fade, badges), shared with Party and Raid
--   portraits  Core/Portrait.lua (2D, 3D model, class icon), shared
--              with Party and Raid
--
-- WoW: Forever follows the Midnight rules: in combat some unit values are
-- "secret". Bars and font strings accept secret values directly; colors
-- come from curves or Blizzard flags; nothing here does math on, compares
-- or measures a value that may be secret. Dropped by rule: cutaway health,
-- range fading by spell range, health/power fade conditions, raid debuff
-- priority lists, arena frames (Forever has no arenas).
local _, E = ...
local L = E.L

---------------------------------------------------------------------------
-- Shared helpers for Blizzard frames (also used by ClassPower and Auras).
-- Every helper runs out of combat (callers use E:RunOutOfCombat), never
-- writes fields into Blizzard frames and only hooks with hooksecurefunc
-- or HookScript. Hooks stay installed but check the element switch every
-- time they run, so a switch turned off makes them do nothing.
---------------------------------------------------------------------------
local Blizz = {}
E.UFBlizzard = Blizz

local hider = CreateFrame("Frame")
hider:Hide()
Blizz.hider = hider

local hidden = setmetatable({}, { __mode = "k" })   -- frame -> element id
local stopped = setmetatable({}, { __mode = "k" })  -- frame -> true once its events were stopped
local goneUntilReload = {}                          -- element id -> true once one of its frames lost its events
local placed = setmetatable({}, { __mode = "k" })   -- frame -> { id, mover, scale }
local skinned = setmetatable({}, { __mode = "k" })  -- bar/frame -> element id
local hookedShow = setmetatable({}, { __mode = "k" })

local function Usable(frame)
	return type(frame) == "table" and type(frame.GetObjectType) == "function"
		and not E.FrameCheck(frame, "IsForbidden")
end
Blizz.Usable = Usable

-- Hide a Blizzard frame for element `id`: reparent to EldoUI's hidden frame
-- and (for unit frames) stop its events (Core/Blizzard.lua,
-- E:HideBlizzardFrame). Blizzard re-parents some of these frames later
-- (Edit Mode's BreakFromFrameManager, the managed frame containers); the
-- core's SetParent post-hook sends them back, after combat for protected
-- ones. Non-protected frames that show themselves again are hidden from an
-- OnShow hook. A frame that keeps its events comes back with Blizz.Unhide;
-- one whose events were stopped only comes back with a reload.
function Blizz.Hide(id, frame, keepEvents)
	if not Usable(frame) then return end
	hidden[frame] = id
	if not keepEvents then
		stopped[frame] = true
		goneUntilReload[id] = true
	end
	E:HideBlizzardFrame(frame, {
		events = not keepEvents,
		-- Master switch off: Blizzard may bring it back (a reload finishes that).
		check = function(self) return hidden[self] ~= nil and E:BlizzardAllowed(hidden[self]) end,
	})
	if not hookedShow[frame] and not E.FrameCheck(frame, "IsProtected") then
		hookedShow[frame] = true
		frame:HookScript("OnShow", function(self)
			local owner = hidden[self]
			if owner and E:BlizzardHidden(owner) then
				self:Hide()
			end
		end)
	end
end

function Blizz.IsHidden(frame)
	return hidden[frame] ~= nil
end

-- Element `id` gives its hidden frames back: every one that kept its
-- events returns to its own parent (out of combat). A frame whose events
-- were stopped stays out of sight until the next reload.
function Blizz.Unhide(id)
	for frame, owner in pairs(hidden) do
		if owner == id then
			hidden[frame] = nil
			if not stopped[frame] then E:UnhideBlizzardFrame(frame) end
		end
	end
end

-- Is Blizzard's version of element `id` out of sight? True while the
-- element is replaced or hidden, and after that until the next reload
-- when one of its frames lost its events (Replace).
function Blizz.OutOfSight(id)
	return E:BlizzardHidden(id) or goneUntilReload[id] == true
end

-- Put a Blizzard frame on an EldoUI mover (optionally under a new parent,
-- e.g. UIParent for frames that live inside a replaced player frame).
-- `moverName` may also be a frame to anchor to; `relPoint`, `x`, `y` place
-- `point` against another point of it (default: the same point, no offset).
-- Edit Mode (ApplySystemAnchor on every layout pass) and the managed frame
-- containers re-anchor and re-parent these frames; the core pin
-- (E:PinBlizzardFrame) puts them back with the plain widget methods, so
-- Edit Mode's own overrides never run from EldoUI.
local function PlacedTarget(info)
	local target = info.mover
	if type(target) ~= "table" then target = E.movers[target] end
	if Usable(target) then return target end
end

function Blizz.Place(id, frame, moverName, scale, point, parent, relPoint, x, y)
	if not Usable(frame) then return end
	local info = { id = id, mover = moverName, scale = scale, point = point, parent = parent,
		relPoint = relPoint, x = x, y = y }
	placed[frame] = info
	E:PinBlizzardFrame(frame, {
		active = function() return placed[frame] == info and E:BlizzardAllowed(info.id, "move") end,
		parent = parent,
		scale = scale,
		anchor = function()
			local target = PlacedTarget(info)
			if not target then return end
			local p = info.point or "CENTER"
			return p, target, info.relPoint or p, info.x or 0, info.y or 0
		end,
	})
end

function Blizz.Unplace(frame)
	if not placed[frame] then return end
	placed[frame] = nil
	-- Blizzard's next layout pass (or /reload) puts it in its own place.
	E:UnpinBlizzardFrame(frame, true)
end

---------------------------------------------------------------------------
-- Blizzard skin: flat bar textures, EldoUI fonts, optional flat frame art.
---------------------------------------------------------------------------
local function Allowed(bar)
	local id = skinned[bar]
	return id and E:BlizzardAllowed(id, "skin") and Blizz.SkinActive(id)
end

local function SkinFont(fontString, size)
	if Usable(fontString) and fontString.SetFont then E:SetFont(fontString, size) end
end

local barHooks = false
local function InstallBarHooks()
	if barHooks then return end
	barHooks = true
	-- Blizzard picks bar art per power type and colors health green; put
	-- the EldoUI texture (and class/reaction color) back after it did.
	if type(UnitFrameHealthBar_Update) == "function" then
		hooksecurefunc("UnitFrameHealthBar_Update", function(bar, unit)
			if not Allowed(bar) then return end
			bar:SetStatusBarTexture(E.media.statusbar)
			local ok, r, g, b = pcall(Blizz.HealthColor, unit or bar.unit, true)
			if ok and r then bar:SetStatusBarColor(r, g, b) end
		end)
	end
	if type(UnitFrameManaBar_UpdateType) == "function" then
		hooksecurefunc("UnitFrameManaBar_UpdateType", function(bar)
			if not Allowed(bar) then return end
			bar:SetStatusBarTexture(E.media.statusbar)
			bar:SetStatusBarColor(Blizz.PowerColor(bar.unit))
		end)
	end
end

function Blizz.SkinBar(id, bar)
	if not Usable(bar) or not bar.SetStatusBarTexture then return end
	skinned[bar] = id
	InstallBarHooks()
	bar:SetStatusBarTexture(E.media.statusbar)
	for _, key in ipairs({ "TextString", "LeftText", "RightText", "HealthBarText", "ManaBarText" }) do
		SkinFont(bar[key], 11)
	end
end

-- Skin a Blizzard unit frame (PlayerFrame, TargetFrame, Boss1TargetFrame ...).
function Blizz.SkinUnitFrame(id, frame, flatArt)
	if not Usable(frame) then return end
	skinned[frame] = id
	Blizz.SkinBar(id, frame.healthbar)
	Blizz.SkinBar(id, frame.manabar)
	if frame.healthbar and frame.unit then
		local ok, r, g, b = pcall(Blizz.HealthColor, frame.unit, true)
		if ok and r then frame.healthbar:SetStatusBarColor(r, g, b) end
	end
	if frame.manabar and frame.unit then frame.manabar:SetStatusBarColor(Blizz.PowerColor(frame.unit)) end
	-- The unit's name: the name font, so a name in another alphabet keeps its letters.
	if Usable(frame.name) and frame.name.SetFont then E:SetNameTextFont(frame.name, 12) end
	local name = frame.GetName and frame:GetName()
	if name then SkinFont(_G[name .. "LevelText"] or _G[name .. "TextureFrameLevelText"], 12) end
	Blizz.FlatArt(frame, flatArt)
end

-- Flat frame art: Blizzard's frame art at alpha 0 and a flat EldoUI box
-- behind each bar; off again puts the art back and hides the boxes.
-- Forever's player and target health bars are taller than what shows:
-- a mask cuts them to their container (HealthBarsContainer, which holds
-- the mask), so the box goes around the container when there is one.
local flatFrames = setmetatable({}, { __mode = "k" })  -- frame -> true while flat
Blizz.backdrops = Blizz.backdrops or setmetatable({}, { __mode = "k" })

local function FrameArt(frame)
	local container = frame.PlayerFrameContainer or frame.TargetFrameContainer
	if not container then return {} end
	return { container.FrameTexture, container.Flash, container.AlternatePowerFrameTexture, container.BossPortraitFrameTexture }
end

-- The part of a bar that shows: its container when the container holds
-- the bar's mask, else the bar itself.
function Blizz.BarArea(bar)
	local parent = bar.GetParent and bar:GetParent()
	if Usable(parent) and Usable(parent.HealthBarMask) and parent.HealthBar == bar then return parent end
	return bar
end

function Blizz.FlatArt(frame, on)
	if not Usable(frame) then return end
	local bars = { frame.healthbar, frame.manabar }
	if on then
		flatFrames[frame] = true
		E:SkinAlphaZero(unpack(FrameArt(frame)))
		for _, bar in ipairs(bars) do
			if Usable(bar) then
				local backdrop = Blizz.backdrops[bar]
				if not backdrop then
					backdrop = CreateFrame("Frame", nil, bar)
					backdrop:SetFrameLevel(math.max(bar:GetFrameLevel() - 1, 0))
					E:SetTemplate(backdrop)
					Blizz.backdrops[bar] = backdrop
				end
				local area = Blizz.BarArea(bar)
				backdrop:ClearAllPoints()
				backdrop:SetPoint("TOPLEFT", area, "TOPLEFT", -E.pixel, E.pixel)
				backdrop:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", E.pixel, -E.pixel)
				backdrop:Show()
			end
		end
	elseif flatFrames[frame] then
		flatFrames[frame] = nil
		for _, region in ipairs(FrameArt(frame)) do
			if Usable(region) and region.SetAlpha then region:SetAlpha(1) end
		end
		for _, bar in ipairs(bars) do
			local backdrop = Usable(bar) and Blizz.backdrops[bar]
			if backdrop then backdrop:Hide() end
		end
	end
end

-- A Blizzard casting bar (PlayerCastingBarFrame, TargetFrameSpellBar ...).
local castHooked = setmetatable({}, { __mode = "k" })
local castRestyling = setmetatable({}, { __mode = "k" })
function Blizz.SkinCastBar(id, bar)
	if not Usable(bar) then return end
	skinned[bar] = id
	E:SkinAlphaZero(bar.Border, bar.TextBorder, bar.BorderShield, bar.DropShadow, bar.Background)
	bar:SetStatusBarTexture(E.media.statusbar)
	bar:SetStatusBarColor(unpack(E.media.accentColor))
	SkinFont(bar.Text, 12)
	SkinFont(bar.CastTimeText, 12)
	if bar.Icon then E:TrimIcon(bar.Icon) end
	if not castHooked[bar] then
		castHooked[bar] = true
		local backdrop = CreateFrame("Frame", nil, bar)
		backdrop:SetPoint("TOPLEFT", -E.pixel, E.pixel)
		backdrop:SetPoint("BOTTOMRIGHT", E.pixel, -E.pixel)
		backdrop:SetFrameLevel(math.max(bar:GetFrameLevel() - 1, 0))
		E:SetTemplate(backdrop)
		Blizz.castBackdrops = Blizz.castBackdrops or {}
		Blizz.castBackdrops[bar] = backdrop
		-- The bar sets its own art per cast type; put ours back afterwards.
		-- That art can be hidden by the game (a secret value), so it is never
		-- looked at: a guard keeps our own call from running the hook again.
		hooksecurefunc(bar, "SetStatusBarTexture", function(self)
			if castRestyling[self] or not Allowed(self) then return end
			castRestyling[self] = true
			self:SetStatusBarTexture(E.media.statusbar)
			self:SetStatusBarColor(unpack(E.media.accentColor))
			castRestyling[self] = nil
		end)
	end
	Blizz.castBackdrops[bar]:SetShown(true)
end

---------------------------------------------------------------------------
-- Colors
---------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end

-- A yes/no flag from the game; false when it is secret or fails.
local function Flag(fn, ...)
	if not fn then return false end
	local ok, value = pcall(fn, ...)
	if not ok or issecret(value) then return false end
	return value and true or false
end

-- Whether the game handed a value at all. A secret counts as present (it
-- stands for a real name, target or duration) and is never truth-tested.
local function Present(value)
	if issecret(value) then return true end
	return value ~= nil
end

-- A plain value from the game, or nil when it is secret or fails.
local Plain = E.PlainCall

-- Raid marker icon. GetRaidTargetIndex is secret on Forever, so
-- the index goes straight to the texture: no test or math on it, only
-- whether there is one. Returns true when the icon shows.
local function SetRaidMarker(texture, unit)
	local ok, index = false, nil
	if GetRaidTargetIndex then ok, index = pcall(GetRaidTargetIndex, unit) end
	local shown = ok and (issecret(index) or type(index) == "number") and SetRaidTargetIconTexture
		and pcall(SetRaidTargetIconTexture, texture, index) and true or false
	texture:SetShown(shown)
	return shown
end

-- Reaction 1-8 through General > Colors: the player's picks,
-- the color-blind safe set, then the game's FACTION_BAR_COLORS.
local REACTION_FRIENDLY, REACTION_HOSTILE = 5, 2
local function ReactionColor(reaction)
	-- Core falls back to the game's standing colors itself; a reaction
	-- outside 1-8 shows neutral.
	local r, g, b = E:GetReactionColor(reaction)
	if r then return r, g, b end
	return E:GetReactionColor(4)
end
Blizz.ReactionColor = ReactionColor

-- Offline and tapped units take the General > Colors state colors
-- ("Unit states and effects"), shared with Party and Raid.
function Blizz.HealthColor(unit, classColor)
	if not unit or not UnitExists(unit) then return E:GetStatusColor("offline") end
	if not Flag(UnitIsConnected, unit) and UnitIsPlayer(unit) then return E:GetStatusColor("offline") end
	if classColor and E:UnitShowsClassColor(unit) then return E:ClassColor(unit) end
	if Flag(UnitIsTapDenied, unit) then return E:GetStatusColor("tapped") end
	local reaction = Plain(UnitReaction, unit, "player") or 4
	return ReactionColor(reaction)
end

function Blizz.PowerColor(unit)
	local _, token = UnitPowerType(unit or "player")
	local color = E:PowerColorObject(token)
	if color then return color.r, color.g, color.b end
	return 0.2, 0.4, 1
end

---------------------------------------------------------------------------
-- Units
---------------------------------------------------------------------------
-- count: several frames in one holder; token: their unit tokens.
-- polled: compound token without unit events, refreshed a few times a second.
-- small: a small frame (no cast bar, auras or private auras by default).
-- short: the test label when the frame's name area is too narrow for its title.
local UNITS = { "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "partypet", "partytarget" }
local INFO = {
	player = { title = "Player", mover = "EldoUI_Player", element = "player-frame",
		point = { "RIGHT", "UIParent", "CENTER", -239, -256 } },
	target = { title = "Target", mover = "EldoUI_Target", element = "target-focus-frames",
		point = { "LEFT", "UIParent", "CENTER", 239, -256 } },
	targettarget = { title = "Target of Target", short = E.Key("ToT"), mover = "EldoUI_ToT", element = "target-focus-frames", polled = true, small = true,
		point = { "CENTER", "UIParent", "CENTER", 460, -300 } },
	focus = { title = "Focus", mover = "EldoUI_Focus", element = "target-focus-frames",
		point = { "CENTER", "UIParent", "CENTER", -308, -360 } },
	focustarget = { sample = { kind = "unit" }, title = "Focus Target", mover = "EldoUI_FocusTarget", element = "target-focus-frames", polled = true, small = true,
		point = { "CENTER", "UIParent", "CENTER", -308, -410 } },
	pet = { title = "Pet", mover = "EldoUI_Pet", element = "pet-frame",
		point = { "CENTER", "UIParent", "CENTER", -460, -300 } },
	pettarget = { sample = { kind = "unit" }, title = "Pet Target", mover = "EldoUI_PetTarget", element = "pet-frame", polled = true, small = true,
		point = { "CENTER", "UIParent", "CENTER", -460, -340 } },
	boss = { title = "Boss", mover = "EldoUI_Boss", element = "boss-frames", count = 5, token = "boss%d",
		point = { "CENTER", "UIParent", "CENTER", 562, 242 } },
	partypet = { sample = { kind = "unit" }, title = "Party Pets", mover = "EldoUI_PartyPets", count = 4, token = "partypet%d", small = true,
		point = { "TOPLEFT", "UIParent", "LEFT", 220, 200 } },
	partytarget = { sample = { kind = "unit" }, title = "Party Targets", mover = "EldoUI_PartyTargets", count = 4, token = "party%dtarget", polled = true, small = true,
		point = { "TOPLEFT", "UIParent", "LEFT", 360, 200 } },
}
local GROUP_OF = {}  -- frame unit token -> unit key
for key, info in pairs(INFO) do
	if info.count then
		for index = 1, info.count do GROUP_OF[info.token:format(index)] = key end
	else
		GROUP_OF[key] = key
	end
end

local function Text(enabled, tag, anchor, x, y, size)
	return { enabled = enabled, preset = "custom", custom = tag, attach = "FRAME", anchor = anchor, x = x, y = y,
		size = size, font = "default", outline = "DEFAULT", justify = "AUTO" }
end

-- A buff or debuff block (two containers per frame).
local function AuraBlock(kind, preset, enabled, size, perRow, max, anchor, extra)
	local block = {
		enabled = enabled,
		filter = E:AuraFilterDefaults(kind, preset),
		size = size, perRow = perRow, max = max, spacing = 4,
		anchor = anchor,           -- TOP, BOTTOM, LEFT, RIGHT of the frame (or of the other block)
		attachTo = "FRAME",        -- FRAME, BUFFS or DEBUFFS
		growthX = "RIGHT", growthY = anchor == "TOP" and "UP" or "DOWN",
		x = 0, y = 0,
		sort = "TIME", sortReverse = false,
		ownFirst = false, desaturateOthers = false,
		duration = "SWIPE",        -- SWIPE (numbers), SWIPEONLY, TEXT, NONE
		durationSize = 0,          -- 0 = from the icon size
		countSize = 0,
		countPoint = "BOTTOMRIGHT", countX = -1, countY = 2,
		durationPoint = "CENTER", durationX = 0, durationY = 0,
		dispelBorder = kind == "HARMFUL",
		clickThrough = false,
		style = "ICONS",           -- ICONS or BARS
		barHeight = 18, barWidth = 0, barColor = "DISPEL",
	}
	for key, value in pairs(extra or {}) do block[key] = value end
	return block
end

local function CastDefaults(width, height, extra)
	local cast = {
		enabled = false, width = width, height = height or 18, offsetX = 0, offsetY = -6, detached = false,
		icon = true, iconPosition = "LEFT", iconAttach = "ATTACHED", iconSize = 0, iconX = 0, iconY = 0,
		time = true, timeFormat = "REMAINING", showName = true, nameLength = 0, nameSize = 0, timeSize = 0,
		spark = true, latency = false, spellTarget = true, targetClassColor = true,
		showInterrupted = true, holdTime = 0.5, reverse = false, ticks = true,
		colorMode = "ACCENT", color = { 0.95, 0.75, 0.25 }, lockedColor = { 0.45, 0.45, 0.45 },
		failedColor = { 1, 0.13, 0.13 }, customBackdrop = false, backdropColor = { 0.06, 0.06, 0.07 },
		-- After a cast: hold a finished cast in its own color, a short
		-- flash, and the feedback word (Done / Interrupted / Failed).
		showSuccess = false, successColor = { 0.25, 0.8, 0.35 }, flash = false, feedback = true,
		-- Other units' casts: hide uninterruptible ones, glow on important
		-- spells (the game's own flag), hide the rest, raid marker.
		hideLocked = false, hideUnimportant = false, raidMarker = false,
		-- Player bar on its own position: on its mover, or under/above the
		-- Cooldown Manager, optionally as wide as it.
		anchor = "MOVER", matchWidth = false, anchorGap = 4,
	}
	for key, value in pairs(extra or {}) do cast[key] = value end
	return cast
end

local function UnitDefaults(width, height, extra)
	local settings = {
		enabled = true,
		width = width,
		height = height,
		scale = 1,
		strata = "MEDIUM",
		level = 0,             -- 0 = automatic
		-- Health
		classColor = true,     -- players in class color, NPCs by reaction
		healthColor = "REACTION", -- REACTION, GRADIENT or CUSTOM
		healthCustomColor = { 0.3, 0.75, 0.35 },
		healthOrientation = "HORIZONTAL",
		healthReverse = false,
		healthBackdrop = "DEFAULT", -- DEFAULT, CLASS or CUSTOM
		healthBackdropColor = { 0.1, 0.1, 0.12 },
		healPrediction = true,
		absorbs = true,
		healAbsorbs = true,
		-- Shape (player): BARS, or ORB for a liquid orb of health and one of
		-- power (Core/Orb.lua), each in its own skin ring.
		shape = "BARS",
		orbMotion = true,      -- the liquid moves (with General > Animations on)
		orbStatues = true,     -- the skin's statues stand beside the orbs (skins that draw them)
		-- Power
		powerHeight = 6,       -- 0 hides the power bar
		powerStyle = "ATTACHED", -- ATTACHED, INSET or DETACHED (player)
		powerWidth = 0,        -- 0 = as wide as the frame (inset / detached)
		powerHideNPC = false,
		powerHealerOnly = false,
		powerHideOOC = false,
		powerReverse = false,
		powerPrediction = true,
		-- Portrait
		portrait = "none",     -- "none", "left", "right", "boxLeft", "boxRight" or "overlay"
		portraitStyle = "2D",  -- "2D", "3D" or "CLASS"
		portraitAlpha = 0.35,  -- overlay
		portraitWidth = 0,     -- portrait box width, 0 = square
		portraitFraming = "FACE", -- 3D camera: FACE, BUST or BODY
		portraitDistance = 1,  -- 3D camera distance
		portraitRotation = 0,  -- 3D, degrees
		portraitHeight = 0,    -- 3D model offset up or down
		portraitRaid2D = false, -- 2D picture instead of the model in raids
		portraitDeadGrey = true, -- gray while dead or offline (Effects: Dead and offline look)
		portraitDesaturate = false,
		graphics = "ALL",      -- frame art (Core/UnitGraphics.lua): ALL follows "all frames"
		-- Texts
		nameText = "LEFT",     -- "LEFT", "CENTER", "RIGHT", "TOP", "INFO" (info panel) or "NONE"
		nameTag = "[name]",
		nameSize = 0,          -- 0 = the frames' text size (fontSize)
		healthText = "BOTH",   -- "PERCENT", "CURRENT", "BOTH", "DEFICIT", "CUSTOM" or "NONE"
		healthTag = "[health:current] | [health:percent]",
		powerText = "NONE",    -- "PERCENT", "CURRENT", "BOTH", "CUSTOM" or "NONE"
		powerTag = "[power:current]",
		texts = { Text(false, "[level] [classification]", "TOPRIGHT", -2, 12, 11), Text(false, "[status]", "CENTER", 0, 0, 12) },
		infoPanel = { enabled = false, height = 14, transparent = false, position = "BOTTOM", tag = "" },
		-- Badges: a level badge and a class or role badge.
		badges = {
			level = { enabled = false, anchor = "PORTRAIT_TOP", size = 18 },
			class = { enabled = false, anchor = "OUTER_TOP", size = 20, mode = "CLASS" },
		},
		threatOn = "FRAME",    -- the threat border on the FRAME or the PORTRAIT box
		-- Cast bar, auras
		castbar = CastDefaults(width),
		buffs = AuraBlock("HELPFUL", "all", false, 22, 8, 16, "TOP"),
		debuffs = AuraBlock("HARMFUL", "mine", false, 26, 8, 16, "TOP"),
		privateAuras = { enabled = false, count = 2, size = 30, anchor = "LEFT" },
		-- Icons and highlights
		indicators = {
			combat = false, resting = false, leader = true, pvp = false, raidMarker = true,
			classification = false, role = false, phase = false, readyCheck = false, readyHold = 6,
			resurrect = true, summon = true, size = 16,
			combatStyle = "MODERN", combatColor = { 1, 1, 1 }, combatPoint = "BOTTOMLEFT", combatX = 2, combatY = 2, combatSize = 0,
			restingStyle = "CLASSIC", restingColor = { 1, 1, 1 }, restingPoint = "TOPLEFT", restingX = 2, restingY = 0, restingSize = 0,
		},
		highlight = true,      -- mouse-over highlight
		targetGlow = false,    -- glow while this unit is your target
		-- Fading
		fader = E:VisibilityDefaults({ casting = false, focus = false, resting = false }),
		spacing = 12,
		growth = "DOWN",
	}
	for key, value in pairs(extra or {}) do settings[key] = value end
	return settings
end

---------------------------------------------------------------------------
-- Effects: Core/UnitFX.lua drives them and builds the Effects tab.
-- Every frame has its own Effects block; three effect sets give each kind
-- of frame a preset that fits it: the player frame, the main frames of
-- other units (target, focus, boss) and the small frames.
---------------------------------------------------------------------------
local UFX = {}
UFX.SETS = {
	UnitFrames = { "auraPop", "auraExpiring", "statusPulse", "threat", "lowHealth", "lowPower", "deadLook" },
	["UnitFrames:target"] = { "fadeIn", "targetFlash", "auraPop", "auraExpiring", "statusPulse", "threat", "anotherTank",
		"lowHealth", "range", "deadLook", "importantGlow" },
	["UnitFrames:small"] = { "fadeIn", "targetFlash", "auraPop", "auraExpiring", "statusPulse", "threat", "range", "deadLook" },
}
UFX.ORDER = { "UnitFrames", "UnitFrames:target", "UnitFrames:small" }
UFX.OF = { player = "UnitFrames", target = "UnitFrames:target", focus = "UnitFrames:target", boss = "UnitFrames:target" }
function UFX.Consumer(key) return UFX.OF[key] or "UnitFrames:small" end
do
	-- Your own threat border is on from Subtle up on the player frame and on
	-- the frames of what you fight; the low-health warning only on your own.
	local threat = { enabled = true, style = "BORDER", pulse = false }
	local quiet = { enabled = false }
	E:RegisterUnitFXPresets("UnitFrames", { subtle = { threat = threat }, standard = { threat = threat } }, UFX.SETS.UnitFrames)
	E:RegisterUnitFXPresets("UnitFrames:target", {
		subtle = { threat = threat, lowHealth = quiet },
		standard = { lowHealth = quiet },
	}, UFX.SETS["UnitFrames:target"])
	E:RegisterUnitFXPresets("UnitFrames:small", {}, UFX.SETS["UnitFrames:small"])
end

local M = E:NewModule("UnitFrames", {
	title = "Unit Frames",
	desc = "Player, target, focus, pet, target-of-target, boss, party pet and party target frames, plus Blizzard's own unit frames and cast bar.",
	conflicts = { "EllesmereUIUnitFrames", "ElvUI", "ShadowedUnitFrames" },
	presets = { "Blizzard", "Classic", "Clean", "Healer", "Minimal", "Orbs", "Perl", "Portrait" },
	defaults = {
		hideBlizzard = true,   -- v0.5.0 switch, read once to migrate to the element switches
		fontSize = 14,
		smoothBars = "general",
		editUnit = "player",   -- the unit the option tabs edit
		-- "All frames" portrait style: the pick, and the shared style
		-- it was last synced to ("MIXED" while the frames differ).
		allFrames = { portraitStyle = "MIXED", synced = "MIXED", graphics = "FOLLOW" },
		editText = 1,          -- the extra text the Texts tab edits
		units = {
			player = UnitDefaults(277, 46, {
				castbar = CastDefaults(277, 20, { enabled = true, latency = true, spellTarget = false }),
				indicators = { combat = true, resting = true, leader = true, pvp = false, raidMarker = true,
					classification = false, role = true, phase = false, readyCheck = true, readyHold = 6,
					resurrect = true, summon = true, size = 16,
					combatStyle = "MODERN", combatColor = { 1, 1, 1 }, combatPoint = "BOTTOMLEFT", combatX = 2, combatY = 2, combatSize = 0,
					restingStyle = "CLASSIC", restingColor = { 1, 1, 1 }, restingPoint = "TOPLEFT", restingX = 2, restingY = 0, restingSize = 0 },
				privateAuras = { enabled = true, count = 2, size = 30, anchor = "LEFT" },
			}),
			target = UnitDefaults(277, 46, {
				castbar = CastDefaults(277, 20, { enabled = true }),
				debuffs = AuraBlock("HARMFUL", "mine", true, 26, 9, 18, "TOP"),
				buffs = AuraBlock("HELPFUL", "all", false, 22, 9, 18, "TOP", { attachTo = "DEBUFFS" }),
				texts = { Text(true, "[level:smart] [classification]", "TOPRIGHT", -2, 12, 11), Text(false, "[status]", "CENTER", 0, 0, 12) },
				indicators = { combat = false, resting = false, leader = true, pvp = false, raidMarker = true,
					classification = true, role = false, phase = true, readyCheck = false, readyHold = 6,
					resurrect = true, summon = true, size = 16,
					combatStyle = "MODERN", combatColor = { 1, 1, 1 }, combatPoint = "BOTTOMLEFT", combatX = 2, combatY = 2, combatSize = 0,
					restingStyle = "CLASSIC", restingColor = { 1, 1, 1 }, restingPoint = "TOPLEFT", restingX = 2, restingY = 0, restingSize = 0 },
			}),
			targettarget = UnitDefaults(140, 26, { powerHeight = 0, healthText = "NONE", nameText = "CENTER" }),
			focus = UnitDefaults(200, 36, {
				castbar = CastDefaults(200, 16, { enabled = true, offsetY = -4 }),
				indicators = { combat = false, resting = false, leader = false, pvp = false, raidMarker = true,
					classification = true, role = false, phase = false, readyCheck = false, readyHold = 6,
					resurrect = true, summon = true, size = 14,
					combatStyle = "MODERN", combatColor = { 1, 1, 1 }, combatPoint = "BOTTOMLEFT", combatX = 2, combatY = 2, combatSize = 0,
					restingStyle = "CLASSIC", restingColor = { 1, 1, 1 }, restingPoint = "TOPLEFT", restingX = 2, restingY = 0, restingSize = 0 },
				targetGlow = true,
			}),
			focustarget = UnitDefaults(140, 22, { enabled = false, powerHeight = 0, healthText = "NONE", nameText = "CENTER" }),
			pet = UnitDefaults(140, 26, {
				powerHeight = 4, healthText = "NONE",
				castbar = CastDefaults(140, 12, { offsetY = -4, time = false, spellTarget = false }),
				happiness = true, happinessBorder = false,
			}),
			pettarget = UnitDefaults(120, 20, { enabled = false, powerHeight = 0, healthText = "NONE", nameText = "CENTER" }),
			boss = UnitDefaults(220, 40, {
				castbar = CastDefaults(220, 14, { enabled = true, offsetY = -4 }),
				debuffs = AuraBlock("HARMFUL", "mine", false, 22, 6, 6, "TOP"),
				indicators = { combat = false, resting = false, leader = false, pvp = false, raidMarker = true,
					classification = false, role = false, phase = false, readyCheck = false, readyHold = 6,
					resurrect = false, summon = false, size = 14,
					combatStyle = "MODERN", combatColor = { 1, 1, 1 }, combatPoint = "BOTTOMLEFT", combatX = 2, combatY = 2, combatSize = 0,
					restingStyle = "CLASSIC", restingColor = { 1, 1, 1 }, restingPoint = "TOPLEFT", restingX = 2, restingY = 0, restingSize = 0 },
				targetGlow = true,
				spacing = 50,
			}),
			partypet = UnitDefaults(120, 20, { enabled = false, powerHeight = 0, healthText = "NONE", nameText = "CENTER", spacing = 30 }),
			partytarget = UnitDefaults(120, 20, { enabled = false, powerHeight = 0, healthText = "PERCENT", nameText = "LEFT", spacing = 30 }),
		},
		-- Settings for Blizzard's own frames, used while their element switch is on.
		blizzard = {
			scale = { ["player-frame"] = 1, ["target-focus-frames"] = 1, ["pet-frame"] = 1, ["boss-frames"] = 1, ["player-cast-bar"] = 1 },
			flatArt = false,           -- frame art made invisible, flat boxes behind the bars
			targetCastbar = "BLIZZARD", -- Blizzard's target/focus cast bars: "BLIZZARD" or "HIDDEN"
			petCastbar = true,         -- Blizzard's pet cast bar stays on
			privateWarning = true,     -- private boss emotes on the EldoUI mover (private-auras move)
		},
	},
})

M.frames = {}
M.holders = {}
M.INFO = INFO
M.UNITS = UNITS
M.UFX = UFX
for key, settings in pairs(M.defaults.units) do settings.effects = E:UnitFXDefaults(UFX.Consumer(key)) end

---------------------------------------------------------------------------
-- Text tags: Core/Tags.lua is the one engine. M.RenderTag stays for
-- callers from before (ClassPower); M.tags still takes plugin tags:
--   EldoUI:GetModule("UnitFrames").tags["mytag"] = function(unit) ... end
-- registers "[mytag]" with the shared engine (refreshed with the frame).
---------------------------------------------------------------------------
M.RenderTag = function(fontString, tagString, unit) E:RenderTag(fontString, tagString, unit, "UnitFrames") end

-- [name] in every unit frame text follows this override; the tag
-- engine re-renders bound texts when it changes.
E:RegisterNameFormatUser("UnitFrames", { title = "Unit frames", order = 10,
	desc = "Name format of [name] in the player, target, focus, party, boss and other unit frame texts." })
M.tags = setmetatable({}, {
	__index = function(_, name) local tag = E.tags[name]; return tag and tag.fn end,
	__newindex = function(_, name, fn)
		if type(fn) == "function" then
			E:RegisterTag(name, fn, nil, { category = "Other", desc = "Added by a plugin through the unit frames." })
		end
	end,
})

-- Dead, Ghost or Offline instead of a health number; the game's own
-- formatters otherwise ("[health:status:percent]").
local STATUS_FORMATS = {
	percent = "[health:percent]", current = "[health:current]", max = "[health:max]",
	["current-max"] = "[health:current-max]", ["current-percent"] = "[health:current-percent]",
	deficit = "[health:deficit]",
}
E:RegisterTag("health:status", function(unit, arg)
	if Flag(UnitIsPlayer, unit) and not Flag(UnitIsConnected, unit) then return PLAYER_OFFLINE or L["Offline"] end
	if Flag(UnitIsGhost, unit) then return L["Ghost"] end
	if Flag(UnitIsDead, unit) then return DEAD or L["Dead"] end
	return E:FormatTag(STATUS_FORMATS[arg or "percent"] or STATUS_FORMATS.percent, unit)
end, "UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION UNIT_FLAGS", { category = "Health", arg = true, example = "[health:status:percent]",
	desc = "Health, or Dead / Ghost / Offline when that applies. Formats: percent, current, max, current-max, current-percent, deficit." })

local HEALTH_TAGS = {
	PERCENT = "[health:status:percent]",
	CURRENT = "[health:status:current]",
	BOTH = "[health:status:current-percent]",
	DEFICIT = "[health:status:deficit]",
}
local POWER_TAGS = {
	PERCENT = "[power:percent]",
	CURRENT = "[power:current]",
	BOTH = "[power:current-percent]",
}

local function NameTag(db)
	if db.nameText == "NONE" then return "" end
	return (db.nameTag and db.nameTag ~= "") and db.nameTag or "[name]"
end

local function HealthTag(db)
	if db.healthText == "CUSTOM" then return db.healthTag or "" end
	return HEALTH_TAGS[db.healthText] or ""
end

local function PowerTag(db)
	if db.powerText == "CUSTOM" then return db.powerTag or "" end
	return POWER_TAGS[db.powerText] or ""
end

-- The tag string of an extra text (old saves kept the string in `tag`).
local function ExtraTag(settings)
	if not settings or settings.removed or not settings.enabled then return "" end
	if settings.preset == nil and settings.tag then return settings.tag end
	return E:TagForSlot(settings)
end

-- Heal prediction and absorbs: Core/UnitGraphics.lua reads Blizzard's
-- calculator and sets the bars, for unit and group frames alike.
local function UpdatePrediction(frame)
	local p = frame.prediction
	local db = frame.db
	if not p or not db or frame.testing or frame.orbShape then return end
	local unit = frame.unit
	local UG = E.UnitGraphics
	local detailed, all, mine, absorb, healAbsorb, overAbsorbed = UG.ReadPrediction(unit)
	if not detailed then
		all = UnitGetIncomingHeals and UnitGetIncomingHeals(unit)
		mine = UnitGetIncomingHeals and UnitGetIncomingHeals(unit, "player")
		absorb = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)
		healAbsorb = UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit)
	end
	local max = UnitHealthMax(unit)
	UG.SetPredictionBar(p.other, db.healPrediction, all, max)
	UG.SetPredictionBar(p.mine, db.healPrediction, mine, max)
	UG.SetPredictionBar(p.absorb, db.absorbs, absorb, max)
	UG.SetPredictionBar(p.healAbsorb, db.healAbsorbs, healAbsorb, max)
	-- Overshield marker: shown from Blizzard's own "clamped" flag.
	if db.absorbs and type(overAbsorbed) == "boolean" and p.overAbsorb.SetAlphaFromBoolean then
		p.overAbsorb:Show()
		pcall(p.overAbsorb.SetAlphaFromBoolean, p.overAbsorb, overAbsorbed, 1, 0)
	else
		p.overAbsorb:Hide()
	end
end

-- Where the prediction bars hang off the health fill, per orientation:
-- grow = the fill's growing edge, the bars continue past it; eat = the
-- heal absorb bar, which covers the fill from its edge backwards.
local function LayoutPrediction(frame, db, healthWidth, healthHeight)
	local p = frame.prediction
	local vertical = db.healthOrientation == "VERTICAL"
	local reverse = db.healthReverse and true or false
	local fill = frame.health:GetStatusBarTexture()
	local a1, b1, a2, b2       -- bar points, fill points (grow edge)
	if vertical then
		if reverse then a1, b1, a2, b2 = "TOPLEFT", "BOTTOMLEFT", "TOPRIGHT", "BOTTOMRIGHT"
		else a1, b1, a2, b2 = "BOTTOMLEFT", "TOPLEFT", "BOTTOMRIGHT", "TOPRIGHT" end
	else
		if reverse then a1, b1, a2, b2 = "TOPRIGHT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOMLEFT"
		else a1, b1, a2, b2 = "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" end
	end
	local orientation = vertical and "VERTICAL" or "HORIZONTAL"
	for _, key in ipairs({ "other", "mine", "absorb", "healAbsorb" }) do
		local bar = p[key]
		bar:ClearAllPoints()
		bar:SetOrientation(orientation)
		if vertical then
			bar:SetHeight(math.max(healthHeight, 1))
		else
			bar:SetWidth(math.max(healthWidth, 1))
		end
	end
	for _, key in ipairs({ "other", "mine" }) do
		p[key]:SetReverseFill(reverse)
		p[key]:SetPoint(a1, fill, b1)
		p[key]:SetPoint(a2, fill, b2)
	end
	p.absorb:SetReverseFill(reverse)
	p.absorb:SetPoint(a1, p.other:GetStatusBarTexture(), b1)
	p.absorb:SetPoint(a2, p.other:GetStatusBarTexture(), b2)
	-- The heal absorb covers the fill backwards from its growing edge.
	p.healAbsorb:SetReverseFill(not reverse)
	p.healAbsorb:SetPoint(b1, fill, b1)
	p.healAbsorb:SetPoint(b2, fill, b2)
	-- Overshield marker on the far edge of the bar.
	local edge = p.overAbsorb
	edge:ClearAllPoints()
	if vertical then
		local side = reverse and "BOTTOM" or "TOP"
		edge:SetPoint(side .. "LEFT", frame.health, side .. "LEFT")
		edge:SetPoint(side .. "RIGHT", frame.health, side .. "RIGHT")
		edge:SetHeight(2)
	else
		local side = reverse and "LEFT" or "RIGHT"
		edge:SetPoint("TOP" .. side, frame.health, "TOP" .. side)
		edge:SetPoint("BOTTOM" .. side, frame.health, "BOTTOM" .. side)
		edge:SetWidth(2)
	end
end

---------------------------------------------------------------------------
-- Health
---------------------------------------------------------------------------
local function Interpolation()
	return E:BarInterpolation(M.db.smoothBars)
end

-- An effect's settings from the frame's Effects block (nil when off).
function UFX.On(frame, key)
	local effects = frame.db and frame.db.effects
	local settings = effects and effects[key]
	if type(settings) == "table" and settings.enabled then return settings end
end

-- Dead, ghost and offline (Effects: Dead and offline look) and tapped
-- units take their General > Colors state color. Health by value
-- comes from the shared UnitFX gradient curve: the client turns the
-- health into the color, Lua never sees the percentage.
local function ColorHealth(frame)
	local unit, db, bar = frame.unit, frame.db, frame.health
	local sr, sg, sb = E.FrameFX.StateColor(unit, UFX.On(frame, "deadLook") and true or false)
	if sr then
		bar:SetStatusBarColor(sr, sg, sb)
		return
	end
	local player = E:UnitShowsClassColor(unit)
	if db.healthColor == "GRADIENT" then
		local color = E:UnitCurveHealth(unit, "healthGradient")
		if type(color) ~= "nil" and E:PaintColorResult(bar, color, "SetStatusBarColor") then return end
	end
	if db.healthColor == "CUSTOM" and not (db.classColor and player) then
		bar:SetStatusBarColor(unpack(db.healthCustomColor))
		return
	end
	local ok, r, g, b = pcall(Blizz.HealthColor, unit, db.classColor)
	if ok and r then bar:SetStatusBarColor(r, g, b) end
end

-- The empty part of the bar (the well): theme color, a dark class color
-- or custom, painted by the shared rule in Core/UnitGraphics.lua.
local function ColorHealthBackdrop(frame)
	local db = frame.db
	E.UnitGraphics:PaintWell(frame.health, db.healthBackdrop, frame.unit, db.healthBackdropColor)
end

local function RenderTexts(frame)
	if frame.testing then return end
	local unit = frame.unit
	E:RenderTag(frame.nameText, frame.tags.name, unit, "UnitFrames")
	E:RenderTag(frame.healthText, frame.tags.health, unit, "UnitFrames")
	-- The power text lives on the power bar and hides with it.
	E:RenderTag(frame.powerText, frame.tags.power, unit, "UnitFrames")
	for index, text in ipairs(frame.customTexts) do
		E:RenderTag(text, frame.tags[index] or "", unit, "UnitFrames")
	end
end

local function UpdateHealth(frame)
	if frame.testing then return end
	local unit = frame.unit
	local bar = frame.health
	pcall(bar.SetMinMaxValues, bar, 0, UnitHealthMax(unit))
	if not pcall(bar.SetValue, bar, UnitHealth(unit), Interpolation()) then pcall(bar.SetValue, bar, UnitHealth(unit)) end
	ColorHealth(frame)
	UpdatePrediction(frame)
	-- Low health warning: the game evaluates the health through a curve.
	E:UnitFXLowHealth(frame.lowHealthGate, unit, UFX.On(frame, "lowHealth"))
end

---------------------------------------------------------------------------
-- Power. The bar can hide by unit kind, role or combat; hiding is our own
-- non-protected bar, so it works in combat. Power prediction (player): the
-- cost of the spell being cast, as an overlay that hangs back from the end
-- of the fill (reverse fill), so no subtraction is ever done. The cost of
-- your own spell is plain data; a cost the game keeps secret shows nothing.
---------------------------------------------------------------------------
local function PowerWanted(frame)
	local db = frame.db
	if (db.powerHeight or 0) <= 0 then return false end
	local unit = frame.unit
	if db.powerHideNPC and not Flag(UnitIsPlayer, unit) then return false end
	if db.powerHealerOnly then
		local role = Plain(UnitGroupRolesAssigned, unit)
		if role and role ~= "NONE" and role ~= "HEALER" then return false end
	end
	if db.powerHideOOC and not Flag(UnitAffectingCombat, "player") then return false end
	return true
end

local function UpdatePowerVisibility(frame)
	if frame.testing then return frame.power:IsShown() end
	local wanted = PowerWanted(frame)
	if frame.power:IsShown() ~= wanted then
		frame.power:SetShown(wanted)
		-- An attached bar that comes or goes changes the health bar's room.
		-- Re-anchored at once: LayoutBars only moves the frame's own
		-- non-secure bars, never the secure frame itself, so it is safe in
		-- combat.
		if frame.db.powerStyle == "ATTACHED" or not frame.db.powerStyle then
			if frame.Relayout then frame:Relayout() end
		end
	end
	return wanted
end

local function UpdatePower(frame)
	if frame.testing then return end
	if not UpdatePowerVisibility(frame) then
		frame.powerText:SetText("")
		if frame.lowPowerGate then frame.lowPowerGate:Clear() end
		return
	end
	local unit = frame.unit
	local bar = frame.power
	pcall(bar.SetMinMaxValues, bar, 0, UnitPowerMax(unit))
	if not pcall(bar.SetValue, bar, UnitPower(unit), Interpolation()) then pcall(bar.SetValue, bar, UnitPower(unit)) end
	bar:SetStatusBarColor(Blizz.PowerColor(unit))
	E:UnitFXLowPower(frame.lowPowerGate, unit, UFX.On(frame, "lowPower"))
	if frame.powerCost and frame.powerCost:IsShown() then
		pcall(frame.powerCost.SetMinMaxValues, frame.powerCost, 0, UnitPowerMax(unit))
	end
end

local function HidePowerCost(frame)
	if frame.powerCost then frame.powerCost:Hide() end
end

local function ShowPowerCost(frame, spellID)
	local cost = frame.powerCost
	if not cost or not frame.db.powerPrediction or frame.orbShape or not frame.power:IsShown() then return end
	if issecret(spellID) or not spellID or not (C_Spell and C_Spell.GetSpellPowerCost) then return end
	local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
	if not ok or type(costs) ~= "table" then return end
	local current = Plain(UnitPowerType, "player")
	for _, entry in ipairs(costs) do
		local kind, amount = entry.type, entry.cost
		if not issecret(kind) and not issecret(amount) and kind == current and type(amount) == "number" and amount > 0 then
			pcall(cost.SetMinMaxValues, cost, 0, UnitPowerMax("player"))
			cost:SetValue(amount)
			cost:Show()
			return
		end
	end
end

---------------------------------------------------------------------------
-- Portrait: beside the bars, in its own box, or as an overlay
-- inside the health bar. Core/Portrait.lua decides between the 3D
-- model, the 2D picture and the class icon, and reloads a model only when
-- the unit changed or something forces it (no flicker on polls).
---------------------------------------------------------------------------
function UFX.PortraitOpts(frame)
	local db = frame.db
	local opts = frame.portraitOpts or {}
	frame.portraitOpts = opts
	local style = db.portraitStyle
	if style == "3D" and db.portraitRaid2D and Flag(IsInRaid) then style = "2D" end
	opts.style, opts.framing = style, db.portraitFraming
	opts.distance, opts.rotation, opts.height = db.portraitDistance, db.portraitRotation, db.portraitHeight
	opts.desaturate = db.portraitDesaturate
	opts.deadGrey = db.portraitDeadGrey ~= false and UFX.On(frame, "deadLook") and true or false
	opts.coords = UFX.PortraitCoords(frame)
	opts.test = frame.testing and true or nil
	return opts
end

-- A picture behind the unit graphics' square or round opening keeps its
-- aspect: the opening shows the square crop a square portrait shows.
function UFX.PortraitCoords(frame)
	local opening = E.UnitGraphics and E.UnitGraphics:PortraitOpening(frame)
	if not opening then return frame.portraitCoords end
	local crop = E.tokens.portraitCrop
	local keep = 0.5 - crop
	-- Round: the mask sits in the middle of the picture's box (width over
	-- height in portraitAspect, from the layout), so the long side reaches
	-- past the crop; only the middle shows.
	local aspect = opening == "round" and frame.portraitAspect or 1
	if aspect >= 1 then
		local half = keep * aspect
		return { 0.5 - half, 0.5 + half, crop, 1 - crop }
	end
	local half = keep / aspect
	return { crop, 1 - crop, 0.5 - half, 0.5 + half }
end

-- force: a new unit, a new model or new settings; polls pass nothing.
local function UpdatePortrait(frame, force)
	if not frame.portraitShown then return end
	if frame.testing and not force then return end
	local opts = UFX.PortraitOpts(frame)
	frame.portraitCoordsShown = opts.coords
	E.Portrait:Update(frame, frame.unit, opts, force and true or false)
end

function UFX.ForcePortrait(frame) UpdatePortrait(frame, true) end

local function SameCoords(a, b)
	if a == nil or b == nil then return a == b end
	for index = 1, 4 do
		if math.abs(a[index] - b[index]) > 0.0001 then return false end
	end
	return true
end

-- The frame art over the finished layout; when the picture's box or the
-- art's opening changed its coordinates, the picture takes them at once.
local function PaintArt(frame, db)
	if E.UnitGraphics then E.UnitGraphics:Apply(frame, db, "unit") end
	if frame.portraitShown and not SameCoords(UFX.PortraitCoords(frame), frame.portraitCoordsShown) then
		UpdatePortrait(frame, true)
	end
end

---------------------------------------------------------------------------
-- Status icons: combat, resting, leader / assistant, main
-- tank / main assist, PvP, raid marker, classification, phase, ready
-- check, resurrection and summon. All from the game's own flags.
---------------------------------------------------------------------------
local GROUP_ICONS = {
	leader = "Interface\\GroupFrame\\UI-Group-LeaderIcon",
	assist = "Interface\\GroupFrame\\UI-Group-AssistantIcon",
	maintank = "Interface\\GroupFrame\\UI-Group-MainTankIcon",
	mainassist = "Interface\\GroupFrame\\UI-Group-MainAssistIcon",
}
local READY_TEXTURES = {
	ready = READY_CHECK_READY_TEXTURE or "Interface\\RaidFrame\\ReadyCheck-Ready",
	notready = READY_CHECK_NOT_READY_TEXTURE or "Interface\\RaidFrame\\ReadyCheck-NotReady",
	waiting = READY_CHECK_WAITING_TEXTURE or "Interface\\RaidFrame\\ReadyCheck-Waiting",
}
local STATUS_ATLAS = {
	summonPending = "RaidFrame-Icon-SummonPending",
	summonAccepted = "RaidFrame-Icon-SummonAccepted",
	summonDeclined = "RaidFrame-Icon-SummonDeclined",
	resurrect = "RaidFrame-Icon-Rez",
	phase = "RaidFrame-Icon-Phasing",
}
-- Combat and resting icon looks.
local COMBAT_STYLES = {
	MODERN = { atlas = "UI-HUD-UnitFrame-Player-CombatIcon" },
	CLASSIC = { texture = "Interface\\CharacterFrame\\UI-StateIcon", coords = { 0.5, 1, 0, 0.484375 } },
}
local RESTING_STYLES = {
	CLASSIC = { texture = "Interface\\CharacterFrame\\UI-StateIcon", coords = { 0, 0.5, 0, 0.421875 } },
}

local function AtlasExists(atlas)
	return atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil
end

local function ApplyIconStyle(texture, style)
	if style.atlas and AtlasExists(style.atlas) then
		texture:SetAtlas(style.atlas)
		texture:SetTexCoord(0, 1, 0, 1)
	elseif style.texture then
		texture:SetTexture(style.texture)
		texture:SetTexCoord(unpack(style.coords))
	else
		texture:SetTexture(COMBAT_STYLES.CLASSIC.texture)
		texture:SetTexCoord(unpack(COMBAT_STYLES.CLASSIC.coords))
	end
end

local function UpdateIndicators(frame)
	local ind = frame.indicators
	local db = frame.db and frame.db.indicators
	local unit = frame.unit
	if not ind or not db or frame.testing then return end
	UFX.UpdateCircle(frame)
	ind.combat:SetShown(db.combat and Flag(UnitAffectingCombat, unit))
	local resting = db.resting and unit == "player" and Flag(IsResting)
	if db.restingStyle == "TEXT" then
		ind.resting:Hide()
		ind.restingText:SetShown(resting)
	else
		ind.restingText:Hide()
		ind.resting:SetShown(resting)
	end
	local leaderTexture
	if db.leader then
		if Flag(UnitIsGroupLeader, unit) then
			leaderTexture = GROUP_ICONS.leader
		elseif IsInRaid() and Flag(UnitIsGroupAssistant, unit) then
			leaderTexture = GROUP_ICONS.assist
		end
	end
	ind.leader:SetTexture(leaderTexture)
	ind.leader:SetShown(leaderTexture ~= nil)
	local roleTexture
	if db.role and GetPartyAssignment and IsInRaid() then
		if Flag(GetPartyAssignment, "MAINTANK", unit) then
			roleTexture = GROUP_ICONS.maintank
		elseif Flag(GetPartyAssignment, "MAINASSIST", unit) then
			roleTexture = GROUP_ICONS.mainassist
		end
	end
	ind.role:SetTexture(roleTexture)
	ind.role:SetShown(roleTexture ~= nil)
	if db.pvp and Flag(UnitIsPVPFreeForAll, unit) then
		ind.pvp:SetAtlas("UI-HUD-UnitFrame-Player-PVP-FFAIcon")
		ind.pvp:Show()
	elseif db.pvp and Flag(UnitIsPVP, unit) then
		local faction = Plain(UnitFactionGroup, unit)
		ind.pvp:SetAtlas(faction == "Horde" and "UI-HUD-UnitFrame-SmallCircle-Horde" or "UI-HUD-UnitFrame-SmallCircle-Alliance")
		ind.pvp:Show()
	else
		ind.pvp:Hide()
	end
	if db.raidMarker then
		SetRaidMarker(ind.raidMarker, unit)
	else
		ind.raidMarker:Hide()
	end
	local rank = Plain(UnitClassification, unit)
	local class = db.classification and rank
	-- The Vanilla graphics' crest on the portrait follows the same rank.
	if E.UnitGraphics then E.UnitGraphics:Classify(frame, rank) end
	if class == "elite" or class == "worldboss" then
		ind.classification:SetAtlas("nameplates-icon-elite-gold")
		ind.classification:Show()
	elseif class == "rare" or class == "rareelite" then
		ind.classification:SetAtlas("nameplates-icon-elite-silver")
		ind.classification:Show()
	else
		ind.classification:Hide()
	end
	-- Ready check (fades out a few seconds after the check ends).
	local ready = db.readyCheck and Plain(GetReadyCheckStatus, unit)
	local readyTexture = ready and READY_TEXTURES[ready]
	if readyTexture then
		E.FrameFX.CancelFade(ind.readyCheck)
		ind.readyCheck:SetTexture(readyTexture)
		ind.readyCheck:Show()
		frame.readyHold = nil
	elseif not frame.readyHold then
		ind.readyCheck:Hide()
	end
	-- Summon first, then resurrection, then phasing (Blizzard's order).
	local atlas
	if db.summon and C_IncomingSummon and Flag(C_IncomingSummon.HasIncomingSummon, unit) then
		local status = Plain(C_IncomingSummon.IncomingSummonStatus, unit)
		local states = Enum.SummonStatus or {}
		if status == states.Pending then
			atlas = STATUS_ATLAS.summonPending
		elseif status == states.Accepted then
			atlas = STATUS_ATLAS.summonAccepted
		elseif status == states.Declined then
			atlas = STATUS_ATLAS.summonDeclined
		end
	end
	if not atlas and db.resurrect and Flag(UnitHasIncomingResurrection, unit) then atlas = STATUS_ATLAS.resurrect end
	if not atlas and db.phase and Flag(UnitPhaseReason, unit) then atlas = STATUS_ATLAS.phase end
	if atlas and AtlasExists(atlas) then
		ind.status:SetAtlas(atlas)
		ind.status:Show()
	else
		ind.status:Hide()
	end
	-- A resurrection or summon on its way breathes (Effects: status pulse).
	E.FrameFX.Pulse(ind.status, atlas ~= nil and atlas ~= STATUS_ATLAS.phase and UFX.On(frame, "statusPulse") and true or false)
end

-- After a ready check the result stays a few seconds, then fades out.
local function HoldReadyCheck(frame)
	local icon = frame.indicators and frame.indicators.readyCheck
	if not icon or not icon:IsShown() then return end
	frame.readyHold = true
	E.FrameFX.FadeOut(icon, frame.db and frame.db.indicators.readyHold, function()
		frame.readyHold = nil
	end)
end

-- Threat through Core/UnitFX.lua: a border, glow or
-- tint in the threat color, painted by the game's color curve, so it
-- shows even while the threat state is secret. The player frame shows your
-- highest threat on anything; another unit's frame your threat on it, or
-- your lead over second place when you are the tank. "Another tank has it" lays a calm
-- color over the mobs the group's other tank holds.
function UFX.PlayerTank()
	return E:PlayerIsTank()
end

function UFX.OtherTank()
	local raid = Flag(IsInRaid)
	for index = 1, raid and 40 or 4 do
		local unit = (raid and "raid%d" or "party%d"):format(index)
		if Flag(UnitExists, unit) and not Flag(UnitIsUnit, unit, "player") and Plain(UnitGroupRolesAssigned, unit) == "TANK" then
			return unit
		end
	end
end

local function UpdateThreat(frame)
	local gate = frame.threatGate
	if not gate then return end
	local settings = not frame.testing and UFX.On(frame, "threat") or nil
	local thickness = 2
	if frame.unit == "player" then
		E:UnitFXThreat(gate, "player", settings, { thickness = thickness })
		return
	end
	local tank = UFX.PlayerTank()
	local shown = E:UnitFXThreat(gate, "player", settings, { other = frame.unit, role = tank and "tank" or "dps", thickness = thickness })
	local other = shown and tank and UFX.On(frame, "anotherTank") and UFX.OtherTank()
	local offTank = frame.offTankGate
	if other then
		local r, g, b = E:GetStatusColor("offTank")
		local calm = { r or 0.5, g or 0.5, b or 1 }
		E:UnitFXThreat(offTank, other, settings, { other = frame.unit, thickness = thickness, mark = false,
			colors = { [0] = false, [1] = false, [2] = calm, [3] = calm } })
	elseif offTank then
		offTank:Clear()
	end
end

-- Hunter pet happiness: Blizzard's own indicator template does the work
-- (icon and tooltip); the optional border color reads the same data.
local HAPPINESS_COLORS = { { 0.85, 0.2, 0.2 }, { 0.9, 0.75, 0.2 }, { 0.25, 0.8, 0.3 } }
local function UpdateHappiness(frame)
	if frame.unit ~= "pet" then return end
	local db = frame.db
	-- Blizzard's indicator shows itself on its own events, so it is faded
	-- out (not hidden) when switched off.
	if frame.happiness then
		frame.happiness:SetAlpha(db.happiness and 1 or 0)
		frame.happiness:EnableMouse(db.happiness and true or false)
	end
	if not db.happinessBorder then
		frame:SetBackdropBorderColor(unpack(E.media.borderColor))
		return
	end
	local happiness = C_PetInfo and C_PetInfo.GetPetHappiness and Plain(C_PetInfo.GetPetHappiness)
	local color = happiness and HAPPINESS_COLORS[happiness]
	if color then frame:SetBackdropBorderColor(unpack(color)) else frame:SetBackdropBorderColor(unpack(E.media.borderColor)) end
end

-- Target glow: the shared glow look (General > Glows) on a frame
-- whose unit is your current target, e.g. one of the boss frames.
E:RegisterGlowUser("unitframeTarget", {
	title = "Unit frames: your target",
	desc = "Glows round a unit frame (boss, focus, party pet ...) while that unit is your target.",
	order = 40,
	default = { style = "pixel", colorMode = "accent", lines = 8, speed = 0.25, thickness = 1, inset = 0 },
})

-- Target change flash (Effects): the target and focus frames flash when
-- their unit changes, the other frames when their unit becomes your target.
function UFX.Flash(frame)
	if frame.testing or not frame:IsVisible() then return end
	E.FrameFX.Flash(frame.art, frame.art, UFX.On(frame, "targetFlash"))
end

local function UpdateTargetGlow(frame)
	local db = frame.db
	local targeted = not frame.testing and frame.key ~= "target" and frame.key ~= "targettarget"
		and Flag(UnitExists, "target") and Flag(UnitIsUnit, frame.unit, "target")
	if targeted and not frame.wasTargeted then UFX.Flash(frame) end
	frame.wasTargeted = targeted
	local on = db and db.targetGlow and targeted
	if on then
		if not frame.glowing then
			frame.glowing = true
			E:ShowUserGlow(frame, "unitframeTarget")
		end
	elseif frame.glowing then
		frame.glowing = nil
		E:HideGlow(frame)
	end
end

---------------------------------------------------------------------------
-- Buffs and debuffs: two aura containers per frame, each with its
-- own filter (Core/Filters.lua), size, layout and look. The client keeps
-- them updated in combat; a new unit in the frame needs a refresh.
---------------------------------------------------------------------------
local function UpdateAuras(frame)
	for _, which in ipairs({ "buffs", "debuffs" }) do
		local aura = frame.auras and frame.auras[which]
		if aura and aura.container then E.AuraWidget.Refresh(aura.container) end
	end
end

-- UNIT_AURA: the containers apply the added, changed and removed auras
-- the event names themselves (a partial update, nothing to rebuild here);
-- only a full update (no update info, or the game says so) rebuilds every
-- icon. M.auraUpdates counts both kinds, for the diagnostics.
M.auraUpdates = { partial = 0, full = 0 }
local function OnAura(frame, _, updateInfo)
	local full = type(updateInfo) ~= "table"
	if not full then
		local flag = updateInfo.isFullUpdate
		full = issecret(flag) or flag == true
	end
	if full then
		M.auraUpdates.full = M.auraUpdates.full + 1
		UpdateAuras(frame)
	else
		M.auraUpdates.partial = M.auraUpdates.partial + 1
	end
end

---------------------------------------------------------------------------
-- Cast bar. Other units' cast times are secret in combat (Midnight), so
-- when the client offers duration objects the bar runs on those and Lua
-- never does math on the times. The player's own casts are not secret:
-- only there the latency zone, channel ticks and power cost are shown,
-- and only after issecretvalue.
---------------------------------------------------------------------------
local function CastColor(castbar, unit)
	local cast = castbar.settings
	local mode = cast and cast.colorMode or "ACCENT"
	if mode == "CUSTOM" then return unpack(cast.color) end
	if mode == "CLASS" and E:UnitShowsClassColor(unit) then return E:ClassColor(unit) end
	if mode == "REACTION" or mode == "CLASS" then
		local ok, r, g, b = pcall(Blizz.HealthColor, unit, false)
		if ok and r then return r, g, b end
	end
	return unpack(E.media.accentColor)
end

local function ColorCast(castbar, notInterruptible, unit)
	local r, g, b = CastColor(castbar, unit or castbar.unit)
	castbar.normalColor:SetRGB(r, g, b)
	local locked = castbar.settings and castbar.settings.lockedColor or { 0.45, 0.45, 0.45 }
	castbar.lockedColor:SetRGB(locked[1], locked[2], locked[3])
	if C_CurveUtil and C_CurveUtil.EvaluateColorFromBoolean then
		local ok, color = pcall(C_CurveUtil.EvaluateColorFromBoolean, notInterruptible, castbar.lockedColor, castbar.normalColor)
		if ok and color then
			pcall(castbar.SetStatusBarColor, castbar, color:GetRGB())
			return
		end
	end
	local isLocked = false
	pcall(function() isLocked = notInterruptible and true or false end)
	castbar:SetStatusBarColor((isLocked and castbar.lockedColor or castbar.normalColor):GetRGB())
end

-- Cast bar extras, in one table to keep the file's locals down.
local CastX = {}
M.CastX = CastX

---------------------------------------------------------------------------
-- Cast hooks (for cast bar effects such as CastFX): EldoUI's unit frame
-- cast bars report what they do.
--   CastX.RegisterCastHook(fn) -> handle;  CastX.UnregisterCastHook(handle)
--   fn(event, castbar, unit, info)
-- events:
--   start          a cast or channel started (info.channel)
--   delayed        the cast was pushed back (UNIT_SPELLCAST_DELAYED)
--   channelUpdate  the channel changed (UNIT_SPELLCAST_CHANNEL_UPDATE)
--   stop           the cast finished
--   fail           the cast failed (info.reason)
--   interrupted    the cast was interrupted (info.reason)
--   hold           the ended bar is held a moment (info.color, info.word, info.hold)
--   layout         the bar was laid out (info.enabled, info.width, info.height)
-- Cast info (start, delayed, channelUpdate, and the ends of the bar's
-- current cast): name, texture, spellID, castID, castBarID, channel,
-- isTradeskill and notInterruptible. The game may hand any of these as
-- secret values (notInterruptible often is): hooks pass them on to the
-- client (SetAlphaFromBoolean and friends) and never test or compare them.
-- A hook that errors is reported and the cast bar carries on.
---------------------------------------------------------------------------
local castHooks = {}

function CastX.RegisterCastHook(fn)
	if type(fn) ~= "function" then error("RegisterCastHook(fn): fn must be a function", 2) end
	local handle = { fn = fn }
	castHooks[#castHooks + 1] = handle
	return handle
end

function CastX.UnregisterCastHook(handle)
	for index = #castHooks, 1, -1 do
		if castHooks[index] == handle or castHooks[index].fn == handle then table.remove(castHooks, index) end
	end
end

function CastX.FireCastHook(event, castbar, unit, info)
	if #castHooks == 0 then return end
	for _, handle in ipairs({ unpack(castHooks) }) do
		local ok, err = pcall(handle.fn, event, castbar, unit, info)
		if not ok then geterrorhandler()(err) end
	end
end

-- The cast the bar shows, as a hook's info table.
function CastX.CastInfo(castbar, extra)
	local info = {
		name = castbar.castName, texture = castbar.castTexture, spellID = castbar.spellID, castID = castbar.castID,
		castBarID = castbar.castBarID, channel = castbar.channel and true or false,
		isTradeskill = castbar.isTradeskill, notInterruptible = castbar.notInterruptible,
	}
	for key, value in pairs(extra or {}) do info[key] = value end
	return info
end

-- Hide casts that can't be interrupted: the cast bar sits in a
-- "gate" frame whose alpha the client sets from the game's (possibly
-- secret) flag. Lua never tests a secret flag.
function CastX.GateCast(castbar, notInterruptible, unit)
	local gate = castbar.gate
	if unit == "player" or not castbar.settings.hideLocked then
		gate:SetAlpha(1)
		return
	end
	-- Secret test first: comparing or testing a secret flag errors.
	if issecret(notInterruptible) then
		if gate.SetAlphaFromBoolean and pcall(gate.SetAlphaFromBoolean, gate, notInterruptible, 0, 1) then return end
		gate:SetAlpha(1)
		return
	end
	if type(notInterruptible) == "nil" then
		gate:SetAlpha(1)
		return
	end
	gate:SetAlpha(notInterruptible and 0 or 1)
end

-- Important casts: C_Spell.IsSpellImportant is the game's own flag
-- (it may be secret). The glow frame and the bar take their alpha from it
-- through SetAlphaFromBoolean, so Lua never reads the answer.
-- The castImportant glow user is registered by Core/UnitFX.lua.

function CastX.ImportantAPI() return C_Spell and C_Spell.IsSpellImportant end

function CastX.AlphaFrom(frame, flag)
	if frame.SetAlphaFromBoolean and pcall(frame.SetAlphaFromBoolean, frame, flag, 1, 0) then return end
	frame:SetAlpha((not issecret(flag) and flag) and 1 or 0)
end

function CastX.HideCastGlow(castbar)
	if castbar.glow then castbar.glow:Clear() end
end

-- The glow is the shared UnitFX driver (Effects: Important cast glow) on
-- a gate over the bar; the game's flag opens the gate.
function CastX.ImportantCast(castbar, spellID, unit)
	local cast = castbar.settings
	local mine = unit == "player"
	local frame = castbar.owner
	local glow = not mine and frame and UFX.On(frame, "importantGlow") or nil
	local important = E:UnitFXImportantCast(castbar.glow, spellID, glow)
	local wantHide = not mine and cast.hideUnimportant and CastX.ImportantAPI()
	if wantHide and type(important) == "nil" and type(spellID) ~= "nil" then
		local ok, value = pcall(C_Spell.IsSpellImportant, spellID)
		if ok then important = value end
	end
	if wantHide and type(important) ~= "nil" then
		CastX.AlphaFrom(castbar, important)
	else
		castbar:SetAlpha(1)
	end
end

-- The spell name ends before the cast target (when one shows) and the
-- room kept for the cast time, so a long name is cut with "..." and never
-- runs under the time or past the bar. The room comes from the time's font
-- size, as on name plates: the texts may be secret, so nothing measures them.
-- The target's share is the width the layout gave it, never read back from
-- the text: a text holding a secret name answers with a secret width.
function CastX.AnchorCastText(castbar)
	local right = castbar.textEnd or -4
	if castbar.targetShown then right = right - (castbar.targetWidth or 0) - 6 end
	castbar.text:SetPoint("RIGHT", castbar, "RIGHT", right, 0)
end

-- The cast target, in its own share at the right of the name. Small bars
-- (target of target, pets, party targets) have no room for it.
function CastX.SetCastTarget(castbar, name, r, g, b)
	local shown = castbar.targetRoom and name and true or false
	castbar.targetShown = shown
	castbar.target:SetText(shown and name or "")
	if shown and r then castbar.target:SetTextColor(r, g, b) end
	castbar.target:SetShown(shown)
	CastX.AnchorCastText(castbar)
end

-- Raid marker on a target/focus/boss cast bar, from the game's
-- raid target index (secret or not, passed straight to the texture).
function CastX.UpdateCastMarker(castbar, unit)
	local marker = castbar.marker
	local shown = false
	if castbar.settings.raidMarker and unit and unit ~= "player" then
		shown = SetRaidMarker(marker, unit)
	else
		marker:Hide()
	end
	local left = castbar.textLeft or 4
	castbar.text:ClearAllPoints()
	castbar.text:SetPoint("LEFT", shown and (left + (castbar.markerSize or 0) + 3) or left, 0)
	CastX.AnchorCastText(castbar)
end

local function UpdateLatency(castbar, unit, startMS, endMS)
	local zone = castbar.latency
	if not castbar.showLatency or unit ~= "player" or not GetNetStats then zone:Hide() return end
	if issecret(startMS) or issecret(endMS) or not startMS or not endMS then zone:Hide() return end
	local _, _, home, world = GetNetStats()
	local latency = math.max(home or 0, world or 0)
	local total = endMS - startMS
	if total <= 0 or latency <= 0 then zone:Hide() return end
	local width = castbar.barWidth * math.min(latency / total, 1)
	-- The zone sits where the cast ends: the far end of the fill direction
	-- (channels run backwards).
	local atEnd = castbar.channel and castbar.reverse or (not castbar.channel and not castbar.reverse)
	zone:ClearAllPoints()
	if atEnd then
		zone:SetPoint("TOPRIGHT")
		zone:SetPoint("BOTTOMRIGHT")
	else
		zone:SetPoint("TOPLEFT")
		zone:SetPoint("BOTTOMLEFT")
	end
	zone:SetWidth(math.max(width, 1))
	zone:Show()
end

-- Channel ticks for your own channels. Our own small table of
-- classic channeled spells: rank 1 spell ID -> number of ticks. The names
-- come from the client, so every rank and every language matches.
local CHANNEL_TICKS = {
	[689] = 5,     -- Drain Life
	[1120] = 5,    -- Drain Soul
	[5138] = 5,    -- Drain Mana
	[755] = 10,    -- Health Funnel
	[5740] = 4,    -- Rain of Fire
	[1949] = 15,   -- Hellfire
	[15407] = 3,   -- Mind Flay
	[5143] = 5,    -- Arcane Missiles
	[10] = 8,      -- Blizzard
	[12051] = 4,   -- Evocation
	[740] = 5,     -- Tranquility
	[16914] = 10,  -- Hurricane
	[1510] = 6,    -- Volley
}
local ticksByName
local function ChannelTicks(spellID, name)
	if not issecret(spellID) and spellID and CHANNEL_TICKS[spellID] then return CHANNEL_TICKS[spellID] end
	if not ticksByName then
		ticksByName = {}
		for id, ticks in pairs(CHANNEL_TICKS) do
			local spellName = C_Spell and C_Spell.GetSpellName and Plain(C_Spell.GetSpellName, id)
			if type(spellName) == "string" then ticksByName[spellName] = ticks end
		end
	end
	if type(name) == "string" and not issecret(name) then return ticksByName[name] end
end

local function HideTicks(castbar)
	for _, tick in ipairs(castbar.ticks or {}) do tick:Hide() end
end

local function ShowTicks(castbar, count)
	HideTicks(castbar)
	if not count or count < 2 then return end
	castbar.ticks = castbar.ticks or {}
	for index = 1, count - 1 do
		local tick = castbar.ticks[index]
		if not tick then
			tick = castbar:CreateTexture(nil, "OVERLAY", nil, 2)
			tick:SetColorTexture(1, 1, 1, 0.6)
			castbar.ticks[index] = tick
		end
		tick:ClearAllPoints()
		tick:SetSize(math.max(E.pixel, 1), castbar.barHeight or 1)
		tick:SetPoint("CENTER", castbar, "LEFT", castbar.barWidth * index / count, 0)
		tick:Show()
	end
end

local function CastName(castbar, name)
	local cast = castbar.settings
	if not cast.showName then return "" end
	local length = tonumber(cast.nameLength) or 0
	if length > 0 and type(name) == "string" and not issecret(name) then return E:Utf8Sub(name, length) end
	return name
end

local function StartCast(frame, channel, reason)
	local castbar = frame.castbar
	if not castbar.enabled or frame.testing then return end
	local info = channel and UnitChannelInfo or UnitCastingInfo
	-- UnitCastingInfo: ..., isTradeskill 6th, castID 7th, notInterruptible
	-- 8th, spellID 9th, castBarID 10th. UnitChannelInfo: ..., isTradeskill
	-- 6th, notInterruptible 7th, spellID 8th, castBarID 11th (no castID).
	local ok, name, _, texture, startMS, endMS, isTradeskill, seventh, eighth, ninth, tenth, eleventh = pcall(info, frame.unit)
	if not ok or not Present(name) then
		castbar:Hide()
		return
	end
	local notInterruptible, castID, spellID, castBarID
	if channel then
		notInterruptible, spellID, castBarID = seventh, eighth, eleventh
	else
		castID, notInterruptible, spellID, castBarID = seventh, eighth, ninth, tenth
	end
	-- Remember which cast the bar shows, so a failed or interrupted attempt
	-- at another spell does not hide it.
	castbar.castID, castbar.spellID, castbar.castBarID = castID, spellID, castBarID
	castbar.castName, castbar.castTexture, castbar.isTradeskill = name, texture, isTradeskill
	castbar.ended = nil
	castbar.channel = channel
	castbar.unit = frame.unit
	castbar.text:SetText(CastName(castbar, name))
	castbar.icon:SetTexture(texture)
	castbar.notInterruptible = notInterruptible
	ColorCast(castbar, notInterruptible, frame.unit)
	CastX.GateCast(castbar, notInterruptible, frame.unit)
	CastX.ImportantCast(castbar, spellID, frame.unit)
	CastX.UpdateCastMarker(castbar, frame.unit)
	castbar.flash:SetAlpha(0)
	CastX.SetCastTarget(castbar, nil)
	-- The game's plain presence flag comes before its possibly secret name.
	if castbar.showTarget and UnitSpellTargetName and Flag(UnitShouldDisplaySpellTargetName, frame.unit) then
		local okTarget, targetName = pcall(UnitSpellTargetName, frame.unit)
		if okTarget and Present(targetName) then
			local class = castbar.settings.targetClassColor and UnitSpellTargetClass and Plain(UnitSpellTargetClass, frame.unit)
			local color = E:ClassColorObject(class)
			if color then
				CastX.SetCastTarget(castbar, targetName, color.r, color.g, color.b)
			else
				CastX.SetCastTarget(castbar, targetName, unpack(E.media.text.secondary))
			end
		end
	end
	castbar.duration, castbar.startTime, castbar.endTime = nil, nil, nil
	UpdateLatency(castbar, frame.unit, startMS, endMS)
	if channel and frame.unit == "player" and castbar.settings.ticks then
		ShowTicks(castbar, ChannelTicks(spellID, name))
	else
		HideTicks(castbar)
	end
	if frame.unit == "player" and not channel then ShowPowerCost(frame, spellID) else HidePowerCost(frame) end

	local durationFn = channel and UnitChannelDuration or UnitCastingDuration
	if durationFn and castbar.SetTimerDuration then
		local okDuration, duration = pcall(durationFn, frame.unit)
		if okDuration and Present(duration) then
			castbar.duration = duration
			local direction = channel and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
			if not pcall(castbar.SetTimerDuration, castbar, duration, nil, direction) then
				pcall(castbar.SetTimerDuration, castbar, duration)
			end
			castbar:Show()
			CastX.CastShown(castbar)
			CastX.FireCastHook(reason or "start", castbar, frame.unit, CastX.CastInfo(castbar))
			return
		end
	end
	-- Fallback: plain numbers (never secret for the player's own casts).
	local okTimes = not issecret(startMS) and not issecret(endMS) and pcall(function()
		castbar.startTime = startMS / 1000
		castbar.endTime = endMS / 1000
		castbar:SetMinMaxValues(0, castbar.endTime - castbar.startTime)
	end)
	if okTimes then
		castbar:Show()
		CastX.CastShown(castbar)
		CastX.FireCastHook(reason or "start", castbar, frame.unit, CastX.CastInfo(castbar))
	else
		castbar:Hide()
	end
end

-- Time text in the chosen format; secret durations are formatted by the
-- client ("%s / %s" joins two formatted strings, no math).
local function DurationText(castbar, duration)
	local format = castbar.settings.timeFormat
	local formatter = castbar.formatter
	if formatter and duration.FormatRemainingDuration then
		if format == "ELAPSED" and duration.FormatElapsedDuration then
			castbar.time:SetText(duration:FormatElapsedDuration(formatter))
		elseif format == "REMAININGMAX" and duration.FormatTotalDuration then
			castbar.time:SetFormattedText("%s / %s", duration:FormatRemainingDuration(formatter), duration:FormatTotalDuration(formatter))
		else
			castbar.time:SetText(duration:FormatRemainingDuration(formatter))
		end
	elseif format == "ELAPSED" and duration.GetElapsedDuration then
		castbar.time:SetFormattedText("%.1f", duration:GetElapsedDuration())
	else
		castbar.time:SetFormattedText("%.1f", duration:GetRemainingDuration())
	end
end

local function CastOnUpdate(castbar, elapsed)
	castbar.throttle = (castbar.throttle or 0) + elapsed
	-- The duration object may be secret (StartCast keeps it via Present()):
	-- a plain truth test here would fail on every tick.
	if Present(castbar.duration) then
		if castbar.throttle < 0.05 then return end
		castbar.throttle = 0
		if not castbar.showTime then castbar.time:SetText("") return end
		local duration = castbar.duration
		pcall(DurationText, castbar, duration)
		return
	end
	local now = GetTime()
	if not castbar.endTime or now >= castbar.endTime then
		castbar:Hide()
		return
	end
	local total = castbar.endTime - castbar.startTime
	local spent = now - castbar.startTime
	castbar:SetValue(castbar.channel and (total - spent) or spent)
	if not castbar.showTime then
		castbar.time:SetText("")
	elseif castbar.settings.timeFormat == "ELAPSED" then
		castbar.time:SetFormattedText("%.1f", spent)
	elseif castbar.settings.timeFormat == "REMAININGMAX" then
		castbar.time:SetFormattedText("%.1f / %.1f", castbar.endTime - now, total)
	else
		castbar.time:SetFormattedText("%.1f", castbar.endTime - now)
	end
end

-- One updater for every cast bar, on the shared ticker (Core/Ticker.lua):
-- it runs only while a cast bar is in sight and stops with the last one.
-- A bar that leaves sight with its frame drops out; showing again
-- (OnShow, or a new cast) brings it back.
local castBars = {} -- castbar -> true while in sight
local CAST_TICK = "UnitFrames:cast"
local function CastTick(elapsed)
	for castbar in pairs(castBars) do
		if not castbar:IsVisible() then
			castBars[castbar] = nil
		elseif not castbar.owner.testing then
			CastOnUpdate(castbar, elapsed)
		end
	end
	if not next(castBars) then E.Ticker:Unsubscribe(CAST_TICK) end
end

function CastX.CastShown(castbar)
	castBars[castbar] = true
	if not E.Ticker:IsSubscribed(CAST_TICK) then E.Ticker:Subscribe(CAST_TICK, 0, CastTick, M) end
end

function CastX.CastHidden(castbar)
	castBars[castbar] = nil
	if not next(castBars) then E.Ticker:Unsubscribe(CAST_TICK) end
end

-- Every cast bar stops (module off).
function CastX.StopCastTicks()
	wipe(castBars)
	E.Ticker:Unsubscribe(CAST_TICK)
end

-- Read-only (diagnostics): how many cast bars the updater runs now.
function CastX.RunningCasts()
	local count = 0
	for _ in pairs(castBars) do count = count + 1 end
	return count
end

-- A seconds formatter for the cast time (Blizzard formats secret durations).
local function CastFormatter()
	if M.castFormatter == nil then
		M.castFormatter = false
		if C_StringUtil and C_StringUtil.CreateSecondsFormatter then
			pcall(function()
				local formatter = C_StringUtil.CreateSecondsFormatter()
				if Enum.SecondsFormatterInterval then formatter:SetMinInterval(Enum.SecondsFormatterInterval.Seconds) end
				if Enum.SecondsFormatterAbbreviation then formatter:SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.OneLetter) end
				if formatter.SetDesiredUnitCount then formatter:SetDesiredUnitCount(1) end
				M.castFormatter = formatter
			end)
		end
	end
	return M.castFormatter or nil
end

-- True when a cast event is about the cast the bar shows. The player presses
-- another spell during a cast and the client fires UNIT_SPELLCAST_FAILED for
-- that attempt ("Another action is in progress"); those must not hide the
-- bar. castBarID is never secret; the cast GUID and spell ID are compared
-- only when readable. When nothing can be compared, the event counts.
local function Readable(a, b)
	return not issecret(a) and not issecret(b) and type(a) ~= "nil" and type(b) ~= "nil"
end

local function IsShownCast(castbar, castGUID, spellID, castBarID)
	if Readable(castBarID, castbar.castBarID) then return castBarID == castbar.castBarID end
	if Readable(castGUID, castbar.castID) then return castGUID == castbar.castID end
	if castbar.channel and Readable(spellID, castbar.spellID) then return spellID == castbar.spellID end
	return true
end

-- A short white flash over the bar when a cast ends.
CastX.FLASH_TIME = 0.35
function CastX.FlashCast(castbar)
	local flash = castbar.flash
	if not (E.db.general.animations and flash.anim) then return false end
	flash.anim:Stop()
	flash:SetAlpha(0)
	flash.anim:Play()
	return true
end

-- The cast ended: the bar stays a moment full in `color` with the
-- feedback word, then hides. Hold time 0 and no flash hide it at once.
function CastX.HoldCast(castbar, color, word)
	local cast = castbar.settings
	HideTicks(castbar)
	CastX.HideCastGlow(castbar)
	local hold = tonumber(cast.holdTime) or 0.5
	local flashed = cast.flash and CastX.FlashCast(castbar)
	if hold <= 0 and not flashed then
		castbar:Hide()
		return
	end
	CastX.FireCastHook("hold", castbar, castbar.unit, CastX.CastInfo(castbar, { color = color, word = word, hold = hold, flashed = flashed and true or false }))
	castbar.ended = true
	castbar.duration, castbar.startTime, castbar.endTime = nil, nil, nil
	castbar:SetMinMaxValues(0, 1)
	castbar:SetValue(1)
	castbar:SetStatusBarColor(unpack(color))
	if cast.feedback ~= false and word then castbar.text:SetText(word) end
	castbar.time:SetText("")
	if castbar.latency then castbar.latency:Hide() end
	local token = {}
	castbar.endToken = token
	C_Timer.After(math.max(hold, flashed and CastX.FLASH_TIME or 0), function()
		if castbar.endToken == token and castbar.ended then
			castbar.ended = nil
			castbar:Hide()
		end
	end)
end

-- The cast finished: hidden at once, or held in the success color.
local function EndCast(frame, castGUID, spellID, castBarID)
	local castbar = frame.castbar
	if frame.unit == "player" then HidePowerCost(frame) end
	if not castbar:IsShown() or castbar.ended then return end
	if IsShownCast(castbar, castGUID, spellID, castBarID) then
		CastX.FireCastHook("stop", castbar, frame.unit, CastX.CastInfo(castbar))
		if castbar.settings.showSuccess then
			CastX.HoldCast(castbar, castbar.settings.successColor, _G.DONE or L["Done"])
		else
			HideTicks(castbar)
			CastX.HideCastGlow(castbar)
			castbar:Hide()
		end
	end
end

-- A failed or interrupted cast: the bar stays a moment in the failed
-- color with the reason ("Interrupted"/"Failed"), then hides.
local function FailCast(frame, reason, castGUID, spellID, castBarID, event)
	local castbar = frame.castbar
	if not castbar:IsShown() or castbar.ended then return end
	if not IsShownCast(castbar, castGUID, spellID, castBarID) then return end
	CastX.FireCastHook(event or "fail", castbar, frame.unit, CastX.CastInfo(castbar, { reason = reason }))
	if frame.unit == "player" then HidePowerCost(frame) end
	if not castbar.showInterrupted then
		HideTicks(castbar)
		CastX.HideCastGlow(castbar)
		castbar:Hide()
		return
	end
	CastX.HoldCast(castbar, castbar.settings.failedColor, reason)
end

local function UpdateCast(frame)
	if not frame.castbar.enabled or frame.testing then return end
	-- The cast's name may be secret: Present(), never a truth test.
	local okCast, casting = pcall(UnitCastingInfo, frame.unit)
	if okCast and Present(casting) then
		StartCast(frame, false)
		return
	end
	local okChannel, channeling = pcall(UnitChannelInfo, frame.unit)
	if okChannel and Present(channeling) then
		StartCast(frame, true)
	else
		frame.castbar:Hide()
	end
end

-- Out-of-range fade (Effects): group members only, on the inner art frame
-- (the fader owns the frame's own alpha). The game answers the range.
function UFX.Range(frame)
	local art = frame.art
	if not art then return end
	local unit = frame.unit
	local settings = not frame.testing and unit ~= "player" and UFX.On(frame, "range") or nil
	local member = settings and (Flag(UnitPlayerOrPetInParty, unit) or Flag(UnitPlayerOrPetInRaid, unit))
	if not member then
		art:SetAlpha(1)
		return
	end
	E:UnitFXRange(art, unit, settings)
end

-- Badges: the level text and the class or role icon.
function UFX.UpdateBadges(frame)
	local badges, db = frame.badges, frame.db and frame.db.badges
	if not (badges and db) then return end
	UFX.UpdateCircle(frame)
	if db.class and db.class.enabled and not frame.testing then
		badges.class:SetShown(E.FrameFX.BadgeClass(badges.class, frame.unit, db.class.mode))
	end
end

-- Size, shape and place of both badges. Round only in the Blizzard and
-- Classic art styles; a square box (E:SetTemplate) in Modern. The frame
-- edge spots are on the side away from the portrait (the right without one).
UFX.LEVEL_TAG = "[difficultycolor][level:smart]"
-- The player's own frame always shows the player's level, as the game's
-- frames do (the smart level is empty for a player of your own level,
-- which would leave an empty badge).
UFX.PLAYER_LEVEL_TAG = "[level]"
-- A badge on "Classic frame circle" sits in the small level circle of the
-- frame's classic plate (Core/UnitGraphics.lua), as large as the circle
-- and with no box of its own; without a plate it sits on the portrait's
-- bottom edge. Badges draw over the frame art and the portrait.
function UFX.LayoutBadges(frame, db)
	local badges, settings = frame.badges, db.badges
	if not (badges and settings) then return end
	local FX = E.FrameFX
	local round = FX.RoundArt()
	local portrait = db.portrait or "none"
	local outer = (portrait == "boxRight" or portrait == "right") and "LEFT" or "RIGHT"
	local holder = frame.portraitShown and portrait ~= "overlay" and frame.portraitHolder or nil
	local spot, spotScale
	if E.UnitGraphics and E.UnitGraphics.LevelSpot then spot, spotScale = E.UnitGraphics:LevelSpot(frame) end
	for key, badge in pairs(badges) do
		local block = settings[key]
		local on = block and block.enabled and db.enabled and true or false
		local circle = on and block.anchor == "PLATE_CIRCLE" and spot or nil
		if on then
			FX.StyleBadge(badge, circle and circle:GetWidth() or math.max(block.size or 18, 8), key == "class" and round, circle ~= nil)
			FX.PlaceBadge(badge, block.anchor, frame, holder, outer, circle)
			badge:SetFrameLevel(frame.textLayer:GetFrameLevel() + 1)
		end
		badge.spot, badge.spotScale = circle, circle and spotScale or nil
		if key == "level" then
			badge.icon:Hide()
			E:BindTag(badge.text, on and not frame.testing and (frame.unit == "player" and UFX.PLAYER_LEVEL_TAG or UFX.LEVEL_TAG) or nil, frame.unit, "UnitFrames")
			badge:SetShown(on)
		elseif not on then
			badge:Hide()
		end
	end
	-- The circle's icon takes the new size and place (none on test frames).
	badges.level.circleState = false
	UFX.UpdateCircle(frame)
	if frame.testing then UFX.TestBadges(frame) else UFX.UpdateBadges(frame) end
end

-- The level circle shows what the classic frames show there, from the
-- game's own state. The player: the rest icon while resting, else the
-- attack icon in combat, each over the level. Other units: the skull in
-- place of the level for a corpse or a level too high to tell.
local CIRCLE_ICONS = { rest = "state-rest", combat = "state-attack" }
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local SKULL_SIZE = 16 -- in classic frame units, as the classic target frame draws it

function UFX.CircleState(frame)
	local badge = frame.badges and frame.badges.level
	if frame.testing or not (badge and badge.spot and badge:IsShown()) then return nil end
	local unit = frame.unit
	if not Flag(UnitExists, unit) then return nil end
	if unit == "player" then
		if Flag(IsResting) then return "rest" end
		if Flag(UnitAffectingCombat, unit) then return "combat" end
		return nil
	end
	if Flag(UnitIsCorpse, unit) then return "skull" end
	local level = Plain(UnitLevel, unit)
	if type(level) == "number" and level <= 0 then return "skull" end
	return nil
end

function UFX.UpdateCircle(frame)
	local badge = frame.badges and frame.badges.level
	if not badge then return end
	local state = UFX.CircleState(frame)
	if state == badge.circleState then return end
	badge.circleState = state
	local icon = badge.stateIcon
	if not state then
		if icon then icon:Hide() end
		badge.text:SetAlpha(1)
		return
	end
	if not icon then
		badge.stateLayer = CreateFrame("Frame", nil, badge)
		badge.stateLayer:SetAllPoints(badge)
		badge.stateLayer:EnableMouse(false)
		icon = badge.stateLayer:CreateTexture(nil, "OVERLAY")
		icon:SetPoint("CENTER", badge, "CENTER", 0, 0)
		badge.stateIcon = icon
	end
	-- Over the level text, whatever level the badge moved to.
	badge.stateLayer:SetFrameLevel(badge:GetFrameLevel() + 1)
	local scale = badge.spotScale or 1
	local shown
	if state == "skull" then
		shown = E:SetClientFile(icon, SKULL)
		icon:SetTexCoord(0, 1, 0, 1)
		icon:SetSize(SKULL_SIZE * scale, SKULL_SIZE * scale)
	else
		local slot = CIRCLE_ICONS[state]
		shown = E:SetOriginalArt(icon, slot)
		local size = E:OriginalArt(slot).size
		icon:SetSize(size[1] * scale, size[2] * scale)
	end
	icon:SetShown(shown and true or false)
	-- The skull takes the level's place; the state icons cover it.
	badge.text:SetAlpha((state == "skull" and shown) and 0 or 1)
end

-- Test frames: the level and the player's own class, so the look shows.
function UFX.TestBadges(frame)
	local badges, settings = frame.badges, frame.db and frame.db.badges
	if not (badges and settings) then return end
	E:UnbindTag(badges.level.text)
	if settings.level and settings.level.enabled then badges.level.text:SetText("60") end
	if settings.class and settings.class.enabled then
		badges.class:SetShown(E.FrameFX.BadgeClass(badges.class, "player", settings.class.mode))
	end
end

-- changed: a different unit is now in the frame (or it just showed).
local function UpdateAll(frame, changed)
	if frame.testing or not frame.db then return end
	if not UnitExists(frame.unit) then return end
	UpdateHealth(frame)
	ColorHealthBackdrop(frame)
	UpdatePower(frame)
	UpdatePortrait(frame, changed)
	UFX.Range(frame)
	UFX.UpdateBadges(frame)
	UpdateAuras(frame)
	UpdateIndicators(frame)
	UpdateThreat(frame)
	UpdateHappiness(frame)
	UpdateTargetGlow(frame)
	UpdateCast(frame)
	RenderTexts(frame)
end
M.UpdateAll = UpdateAll

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local UNIT_EVENTS = {
	-- A unit that died shows the skull in the level circle.
	UNIT_HEALTH = function(frame) UpdateHealth(frame) UFX.UpdateCircle(frame) end,
	UNIT_LEVEL = UFX.UpdateCircle,
	UNIT_MAXHEALTH = UpdateHealth,
	-- Offline, phased or out of view: the dead look and the portrait follow.
	UNIT_CONNECTION = function(frame) UpdateHealth(frame) UpdatePortrait(frame) UFX.Range(frame) end,
	UNIT_FACTION = function(frame) UpdateHealth(frame) UpdateIndicators(frame) end,
	UNIT_IN_RANGE_UPDATE = function(frame) UFX.Range(frame) end,
	UNIT_HEAL_PREDICTION = UpdatePrediction,
	UNIT_ABSORB_AMOUNT_CHANGED = UpdatePrediction,
	UNIT_HEAL_ABSORB_AMOUNT_CHANGED = UpdatePrediction,
	UNIT_POWER_UPDATE = UpdatePower,
	UNIT_MAXPOWER = UpdatePower,
	UNIT_DISPLAYPOWER = UpdatePower,
	UNIT_CLASSIFICATION_CHANGED = UpdateIndicators,
	UNIT_FLAGS = function(frame) UpdateIndicators(frame) UpdateHealth(frame) UpdatePortrait(frame) end,
	UNIT_PHASE = function(frame) UpdateIndicators(frame) UpdatePortrait(frame) end,
	UNIT_PORTRAIT_UPDATE = UFX.ForcePortrait,
	UNIT_MODEL_CHANGED = UFX.ForcePortrait,
	UNIT_AURA = OnAura,
	UNIT_THREAT_SITUATION_UPDATE = UpdateThreat,
	UNIT_THREAT_LIST_UPDATE = UpdateThreat,
	UNIT_HAPPINESS = UpdateHappiness,
	UNIT_SPELLCAST_START = function(frame) StartCast(frame, false) end,
	UNIT_SPELLCAST_CHANNEL_START = function(frame) StartCast(frame, true) end,
	UNIT_SPELLCAST_DELAYED = function(frame) StartCast(frame, false, "delayed") end,
	UNIT_SPELLCAST_CHANNEL_UPDATE = function(frame) StartCast(frame, true, "channelUpdate") end,
	UNIT_SPELLCAST_INTERRUPTIBLE = function(frame)
		ColorCast(frame.castbar, false, frame.unit)
		CastX.GateCast(frame.castbar, false, frame.unit)
	end,
	UNIT_SPELLCAST_NOT_INTERRUPTIBLE = function(frame)
		ColorCast(frame.castbar, true, frame.unit)
		CastX.GateCast(frame.castbar, true, frame.unit)
	end,
	-- Payload: unit, castGUID, spellID[, interruptedBy], castBarID.
	UNIT_SPELLCAST_STOP = function(frame, _, castGUID, spellID, castBarID)
		EndCast(frame, castGUID, spellID, castBarID)
	end,
	UNIT_SPELLCAST_CHANNEL_STOP = function(frame, _, castGUID, spellID, _, castBarID)
		EndCast(frame, castGUID, spellID, castBarID)
	end,
	UNIT_SPELLCAST_FAILED = function(frame, _, castGUID, spellID, castBarID)
		FailCast(frame, _G.FAILED or L["Failed"], castGUID, spellID, castBarID)
	end,
	UNIT_SPELLCAST_INTERRUPTED = function(frame, _, castGUID, spellID, _, castBarID)
		FailCast(frame, _G.INTERRUPTED or L["Interrupted"], castGUID, spellID, castBarID, "interrupted")
	end,
}
-- These handlers get the event payload; every other one only the frame.
local CAST_ENDS = {
	UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_CHANNEL_STOP = true,
	UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true,
	UNIT_AURA = true,
}

-- Events that are not tied to the frame's unit.
local GLOBAL_EVENTS = {
	PLAYER_ENTERING_WORLD = function(frame) UpdateAll(frame, true) end,
	RAID_TARGET_UPDATE = function(frame)
		UpdateIndicators(frame)
		if frame.castbar:IsShown() and not frame.testing then CastX.UpdateCastMarker(frame.castbar, frame.unit) end
	end,
	PARTY_LEADER_CHANGED = UpdateIndicators,
	PLAYER_ROLES_ASSIGNED = function(frame) UpdateIndicators(frame) UpdatePower(frame) end,
	PLAYER_UPDATE_RESTING = UpdateIndicators,
	PLAYER_REGEN_DISABLED = function(frame) UpdateIndicators(frame) UpdatePower(frame) end,
	PLAYER_REGEN_ENABLED = function(frame) UpdateIndicators(frame) UpdatePower(frame) end,
	PLAYER_TARGET_CHANGED = UpdateTargetGlow,
	READY_CHECK = UpdateIndicators,
	READY_CHECK_CONFIRM = UpdateIndicators,
	READY_CHECK_FINISHED = function(frame) HoldReadyCheck(frame) end,
	INCOMING_RESURRECT_CHANGED = UpdateIndicators,
	INCOMING_SUMMON_CHANGED = UpdateIndicators,
}
-- A burst of roster updates (a raid forming, a battleground filling)
-- refreshes each frame once, 0.1 s after the first.
do
	local waiting = {}
	local function Flush()
		for frame in pairs(waiting) do
			waiting[frame] = nil
			if M.active and frame:IsEventRegistered("GROUP_ROSTER_UPDATE") then UpdateAll(frame) end
		end
	end
	GLOBAL_EVENTS.GROUP_ROSTER_UPDATE = function(frame)
		waiting[frame] = true
		E:Debounce("UnitFrames:roster", 0.1, Flush)
	end
end

-- Events that mean "a different unit is now in this frame".
local CHANGE_EVENTS = {
	target = { "PLAYER_TARGET_CHANGED" },
	targettarget = { "PLAYER_TARGET_CHANGED", "UNIT_TARGET", owner = "target" },
	focus = { "PLAYER_FOCUS_CHANGED" },
	focustarget = { "PLAYER_FOCUS_CHANGED", "UNIT_TARGET", owner = "focus" },
	pet = { "UNIT_PET", owner = "player" },
	pettarget = { "UNIT_PET", owner = "player" },
	boss = { "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "UNIT_TARGETABLE_CHANGED" },
	partypet = { "UNIT_PET", owner = function(unit) return (unit:gsub("^partypet", "party")) end },
	partytarget = { "UNIT_TARGET", owner = function(unit) return (unit:gsub("target$", "")) end },
}
-- `owner`: the unit whose UNIT_PET or UNIT_TARGET changes the frame's
-- unit, so the game sends the event only for that one (party pet N follows
-- party N, party N's target follows party N), not for every unit in the game.

local function OnEvent(frame, event, ...)
	local changes = CHANGE_EVENTS[frame.key]
	if changes and tContains(changes, event) then
		UpdateAll(frame, true)
		-- The target and focus frames flash for their new unit.
		if (frame.key == "target" or frame.key == "focus") and Flag(UnitExists, frame.unit) then UFX.Flash(frame) end
		return
	end
	local handler = UNIT_EVENTS[event] or GLOBAL_EVENTS[event]
	if CAST_ENDS[event] then
		handler(frame, ...)
	elseif handler then
		handler(frame)
	else
		UpdateAll(frame)
	end
end


---------------------------------------------------------------------------
-- Frame construction
---------------------------------------------------------------------------
-- Colors from General > Colors (Heal prediction), set by FrameFX.
local function CreatePredictionBar(parent, reverse)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(E.media.statusbar)
	bar:SetReverseFill(reverse and true or false)
	bar:Hide()
	E.statusBars[bar] = true
	return bar
end

-- Mouse-over highlight: our own texture, shown from the frame's
-- enter and leave scripts.
local function OnEnter(self)
	if self.highlight and self.db and self.db.highlight then self.highlight:Show() end
	if UnitFrame_OnEnter then UnitFrame_OnEnter(self) end
end

local function OnLeave(self)
	if self.highlight then self.highlight:Hide() end
	if UnitFrame_OnLeave then UnitFrame_OnLeave(self) end
end

local function CreateUnitFrame(unit, name, parent)
	local frame = CreateFrame("Button", name, parent or UIParent, "SecureUnitButtonTemplate")
	frame.unit = unit
	frame.key = GROUP_OF[unit]
	frame.polled = INFO[frame.key].polled
	frame:SetAttribute("unit", unit)
	frame:SetAttribute("*type1", "target")
	frame:SetAttribute("*type2", "togglemenu")
	frame:RegisterForClicks("AnyUp")
	frame:SetScript("OnEnter", OnEnter)
	frame:SetScript("OnLeave", OnLeave)
	E:SetTemplate(frame)

	-- Everything drawn sits on an inner art frame: the range fade and
	-- the fade-in work on its alpha, the fader on the frame's own.
	local art = CreateFrame("Frame", nil, frame)
	art:SetAllPoints()
	frame.art = art

	-- Portrait: beside the bars, in its own box, or over the health bar.
	frame.portraitHolder = CreateFrame("Frame", nil, art)
	E.Portrait:Attach(frame, frame.portraitHolder)

	frame.health = E:CreateStatusBar(art)
	frame.health:SetClipsChildren(true)
	frame.power = E:CreateStatusBar(art)
	-- The power text sits on the power bar and hides with it.
	frame.powerLayer = CreateFrame("Frame", nil, frame.power)
	frame.powerLayer:SetAllPoints()
	-- Power prediction (player): the cost of the spell being cast.
	if unit == "player" then
		local cost = CreateFrame("StatusBar", nil, frame.power)
		cost:SetStatusBarTexture(E.media.statusbar)
		cost:SetStatusBarColor(1, 1, 1, 0.35)
		cost:SetReverseFill(true)
		cost:SetAllPoints(frame.power:GetStatusBarTexture())
		cost:Hide()
		E.statusBars[cost] = true
		frame.powerCost = cost
	end

	-- Heal prediction and absorbs live inside the (clipping) health bar.
	local p = {}
	p.other = CreatePredictionBar(frame.health)
	p.mine = CreatePredictionBar(frame.health)
	p.absorb = CreatePredictionBar(frame.health)
	p.healAbsorb = CreatePredictionBar(frame.health, true)
	p.overAbsorb = frame.health:CreateTexture(nil, "OVERLAY")
	p.overAbsorb:Hide()
	frame.prediction = p
	E.FrameFX.ColorPrediction(p)

	-- Info panel: a strip under the bars, or the name bar over them.
	frame.infoPanel = CreateFrame("Frame", nil, art)
	E:SetTemplate(frame.infoPanel)
	frame.infoPanel:Hide()

	local textLayer = CreateFrame("Frame", nil, art)
	textLayer:SetAllPoints()
	frame.textLayer = textLayer
	frame.nameText = E:CreateText(textLayer)
	frame.infoText = E:CreateText(textLayer, E.tokens.size.small, "RIGHT")
	frame.healthText = E:CreateText(textLayer, nil, "RIGHT")
	frame.powerText = E:CreateText(frame.powerLayer, E.tokens.size.tiny, "RIGHT")
	frame.customTexts = {}
	frame.tags = {}

	frame.highlight = textLayer:CreateTexture(nil, "BACKGROUND")
	frame.highlight:SetColorTexture(1, 1, 1, 0.1)
	frame.highlight:SetAllPoints(frame.health)
	frame.highlight:Hide()

	-- Status icons.
	local ind = {}
	for _, key in ipairs({ "combat", "resting", "leader", "role", "pvp", "raidMarker", "classification", "readyCheck", "status" }) do
		ind[key] = textLayer:CreateTexture(nil, "OVERLAY")
		ind[key]:Hide()
	end
	ind.raidMarker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	ind.restingText = E:CreateText(textLayer, E.tokens.size.small)
	ind.restingText:SetText("zzz")
	ind.restingText:Hide()
	frame.indicators = ind

	-- Danger gates (Core/UnitFX.lua): threat on the frame or the portrait
	-- box, "another tank has it" over it, low health on the health bar and
	-- low power on the power bar. Badges for the Boxed look.
	frame.threatGate = E:CreateGate(art, M.LEVELS.threat - M.LEVELS.art)
	frame.offTankGate = E:CreateGate(art, M.LEVELS.offTank - M.LEVELS.art)
	frame.lowHealthGate = E:CreateGate(frame.health, 3)
	frame.lowPowerGate = E:CreateGate(frame.power, 3)
	frame.badges = { level = E.FrameFX.Badge(textLayer), class = E.FrameFX.Badge(textLayer) }
	-- The frame art drew, moved or dropped the plate's level circle.
	frame.OnLevelSpot = function(self) if self.db then UFX.LayoutBadges(self, self.db) end end

	-- Cast bar, inside its gate frame (alpha for "hide casts that can't be
	-- interrupted"; the bar's own alpha is for "hide unimportant casts").
	local gate = CreateFrame("Frame", nil, frame)
	gate:SetAllPoints(frame)
	local castbar = E:CreateStatusBar(gate)
	castbar.gate = gate
	castbar:Hide()
	castbar.iconFrame = CreateFrame("Frame", nil, castbar)
	E:SetTemplate(castbar.iconFrame)
	castbar.icon = castbar.iconFrame:CreateTexture(nil, "ARTWORK")
	castbar.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	castbar.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(castbar.icon)
	castbar.text = E:CreateText(castbar, E.tokens.size.body, "LEFT")
	castbar.target = E:CreateText(castbar, E.tokens.size.small, "LEFT")
	castbar.target:SetTextColor(unpack(E.media.text.secondary))
	castbar.time = E:CreateText(castbar, E.tokens.size.body, "RIGHT")
	castbar.spark = castbar:CreateTexture(nil, "OVERLAY")
	castbar.spark:SetColorTexture(1, 1, 1, 0.9)
	castbar.spark:SetWidth(2)
	castbar.latency = castbar:CreateTexture(nil, "OVERLAY")
	castbar.latency:SetColorTexture(E.tokens.bar.latency[1], E.tokens.bar.latency[2], E.tokens.bar.latency[3], 0.45)
	castbar.latency:Hide()
	castbar.marker = castbar:CreateTexture(nil, "OVERLAY", nil, 3)
	castbar.marker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	castbar.marker:Hide()
	castbar.flash = castbar:CreateTexture(nil, "OVERLAY", nil, 4)
	castbar.flash:SetAllPoints()
	castbar.flash:SetColorTexture(1, 1, 1, 1)
	castbar.flash:SetBlendMode("ADD")
	castbar.flash:SetAlpha(0)
	if castbar.flash.CreateAnimationGroup then
		local anim = castbar.flash:CreateAnimationGroup()
		local fade = anim:CreateAnimation("Alpha")
		fade:SetFromAlpha(0.7)
		fade:SetToAlpha(0)
		fade:SetDuration(CastX.FLASH_TIME)
		anim:SetScript("OnFinished", function() castbar.flash:SetAlpha(0) end)
		castbar.flash.anim = anim
	end
	castbar.glow = E:CreateGate(castbar, 4)
	castbar.owner = frame
	castbar.normalColor = CreateColor(1, 1, 1, 1)
	castbar.lockedColor = CreateColor(0.45, 0.45, 0.45, 1)
	castbar.settings = CastDefaults(200)
	castbar.barWidth = 200
	castbar:HookScript("OnShow", CastX.CastShown)
	castbar:HookScript("OnHide", CastX.CastHidden)
	frame.castbar = castbar

	-- Hunter pet happiness: Blizzard's own indicator template.
	if unit == "pet" then
		local ok, happiness = pcall(CreateFrame, "Frame", nil, textLayer, "PetFrameHappinessTemplate")
		if ok and happiness then
			happiness:SetPoint("LEFT", frame, "RIGHT", 4, 0)
			frame.happiness = happiness
		end
	end

	frame.auras = {}
	frame:SetScript("OnEvent", OnEvent)
	-- A frame that shows (a new target, focus or boss) reloads its portrait
	-- and fades in (Effects: Fade in when shown).
	frame:SetScript("OnShow", function(self)
		UpdateAll(self, true)
		if not self.testing and self.key ~= "player" then E:UnitFXFadeIn(self.art, UFX.On(self, "fadeIn")) end
		if self.polled then UFX.WatchPolled() end
	end)
	-- Click-casting (Modules/ClickCast.lua) binds its clicks to every frame.
	if E.RegisterClickCastFrame then E:RegisterClickCastFrame(frame, "unit") end
	return frame
end

-- Private aura anchors: Blizzard draws private auras (boss mechanics) into
-- frames EldoUI gives it. Nothing about them can be read or restyled.
local function RemovePrivateAnchors(frame, guard)
	if not frame.privateAnchors then
		if guard then return true end
		return
	end
	for _, entry in ipairs(frame.privateAnchors) do
		if guard and not guard("before", entry) then return false end
		if entry.id and C_UnitAuras.RemovePrivateAuraAnchor then pcall(C_UnitAuras.RemovePrivateAuraAnchor, entry.id) end
		if guard and not guard("removed", entry) then return false end
		entry.id = nil
		if guard and not guard("hide", entry) then return false end
		entry.holder:Hide()
		if guard and not guard("hidden", entry) then return false end
	end
	if guard then return true end
end

-- The slot holders made below, each with the frame it was made for: a
-- layout that failed may take its own slots up again, never anyone else's.
Blizz.privateSlotOwners = setmetatable({}, { __mode = "k" })

function Blizz.SetPrivateAnchors(owner, unit, settings, anchorTo, growth, geometry)
	owner.privateAnchors = owner.privateAnchors or {}
	local proof, matches, states, finish
	if geometry == true then
		local module, profile = E.modules.Auras, E.db
		local mover = E.movers.EldoUI_Debuffs
		if not (module and module.active and module.debuffHolder == owner and mover and mover.frame == owner
			and module.db and module.db.privateAuras == settings and anchorTo == owner) then return end
		local db = module.db
		if E:IsSecret(owner.privateAnchors) or type(owner.privateAnchors) ~= "table" or E:IsSecret(growth) then return end
		local function Number(value)
			return not E:IsSecret(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
		end
		if type(settings) ~= "table" or E:IsSecret(settings.enabled) or type(settings.enabled) ~= "boolean"
			or not Number(settings.size) or settings.size < 16 or settings.size > 72
			or not Number(settings.count) or settings.count < 1 or settings.count > 4 or settings.count % 1 ~= 0
			or (growth ~= "LEFT" and growth ~= "RIGHT" and growth ~= "UP" and growth ~= "DOWN") then return end
		proof = { owner = owner, anchor = anchorTo, settings = settings, array = owner.privateAnchors,
			enabled = settings.enabled, size = settings.size, count = settings.count, growth = growth, slots = {} }
		states = {}
		local function State(holder)
			if E:IsSecret(holder) or not holder then return end
			local parent, points, shown = holder:GetParent(), holder:GetNumPoints(), holder:IsShown()
			if E:IsSecret(parent) or parent ~= owner or not Number(points) or points < 0 or points > 1 or E:IsSecret(shown) then return end
			local width, height = holder:GetSize()
			local scale = holder:GetScale()
			if not Number(width) or not Number(height) or not Number(scale) or scale <= 0 then return end
			local point = { holder:GetPoint(1) }
			for index = 1, #point do if E:IsSecret(point[index]) then return end end
			return { width = width, height = height, scale = scale, point = point, shown = shown }
		end
		proof.Snapshot = State
		matches = function()
			if E.modules.Auras ~= module or E.db ~= profile or module.db ~= db or not module.active or module.debuffHolder ~= owner
				or E.movers.EldoUI_Debuffs ~= mover or mover.frame ~= owner or db.privateAuras ~= settings
				or owner.privateAnchors ~= proof.array or E:IsSecret(settings.enabled) or E:IsSecret(settings.size) or E:IsSecret(settings.count) or E:IsSecret(settings.anchor)
				or settings.enabled ~= proof.enabled or settings.size ~= proof.size or settings.count ~= proof.count or settings.anchor ~= proof.growth then return false end
			for index, entry in pairs(proof.array) do
				local slot = proof.slots[index]
				if not slot or slot.entry ~= entry or entry.holder ~= slot.holder then return false end
			end
			for index, slot in pairs(proof.slots) do
				if proof.array[index] ~= slot.entry or slot.entry.holder ~= slot.holder then return false end
				local actual, expected = State(slot.holder), states[slot.holder]
				if not actual or not expected or actual.width ~= expected.width or actual.height ~= expected.height
					or actual.scale ~= expected.scale or actual.shown ~= expected.shown or #actual.point ~= #expected.point then return false end
				for p = 1, #actual.point do if actual.point[p] ~= expected.point[p] then return false end end
			end
			return true
		end
		for index, entry in pairs(proof.array) do
			if type(index) ~= "number" or index < 1 or index > 4 or index % 1 ~= 0 or type(entry) ~= "table" then return end
			local state = State(entry.holder)
			if not state then return end
			proof.slots[index], states[entry.holder] = { entry = entry, holder = entry.holder }, state
		end
		finish = function()
			if not matches() then return end
			for _, slot in pairs(proof.slots) do
				local state = states[slot.holder]
				slot.entry, slot.point, slot.width, slot.height, slot.scale, slot.shown = nil, state.point, state.width, state.height, state.scale, state.shown
			end
			proof.array, proof.settings, proof.Snapshot = nil, nil, nil
			return proof
		end
	end
	local removed = RemovePrivateAnchors(owner, proof and function(phase, entry)
		if not matches() then return false end
		if phase == "hide" then states[entry.holder].shown = false end
		return true
	end)
	if proof and not removed then return end
	if matches and not matches() then return end
	if not settings or not settings.enabled or not E:BlizzardAllowed("private-auras", "improve") then
		if finish then return finish() end
		return
	end
	if not (C_UnitAuras and C_UnitAuras.AddPrivateAuraAnchor) then
		if finish then return finish() end
		return
	end
	local size = settings.size or 30
	for index = 1, settings.count or 2 do
		local entry = owner.privateAnchors[index]
		if not entry then
			entry = { holder = CreateFrame("Frame", nil, owner) }
			Blizz.privateSlotOwners[entry.holder] = owner
			owner.privateAnchors[index] = entry
		end
		local holder = entry.holder
		if proof then
			local state = proof.Snapshot(holder)
			if not state then return end
			proof.slots[index], states[holder] = { entry = entry, holder = holder }, state
			if not matches() then return end
			state.width, state.height = size, size
		end
		holder:SetSize(size, size)
		if matches and not matches() then return end
		if proof then states[holder].point = {} end
		holder:ClearAllPoints()
		if matches and not matches() then return end
		local step = (index - 1) * (size + 4)
		if proof then
			states[holder].point = growth == "LEFT" and { "RIGHT", anchorTo, "LEFT", -4 - step, 0 }
				or (growth == "UP" and { "BOTTOM", anchorTo, "TOP", 0, 4 + step }
				or (growth == "DOWN" and { "TOP", anchorTo, "BOTTOM", 0, -4 - step } or { "LEFT", anchorTo, "RIGHT", 4 + step, 0 }))
		end
		if growth == "LEFT" then
			holder:SetPoint("RIGHT", anchorTo, "LEFT", -4 - step, 0)
		elseif growth == "UP" then
			holder:SetPoint("BOTTOM", anchorTo, "TOP", 0, 4 + step)
		elseif growth == "DOWN" then
			holder:SetPoint("TOP", anchorTo, "BOTTOM", 0, -4 - step)
		else
			holder:SetPoint("LEFT", anchorTo, "RIGHT", 4 + step, 0)
		end
		if matches and not matches() then return end
		if proof then states[holder].shown = true end
		holder:Show()
		if matches and not matches() then return end
		local ok, id = pcall(C_UnitAuras.AddPrivateAuraAnchor, {
			unitToken = unit,
			auraIndex = index,
			parent = holder,
			showCooldownFrame = true,
			showCooldownEdge = false,
			showCountdownNumbers = true,
			showDispelIcon = false,
			isContainer = false,
			iconInfo = {
				iconAnchor = { point = "CENTER", relativeTo = holder, relativePoint = "CENTER", offsetX = 0, offsetY = 0 },
				iconWidth = size,
				iconHeight = size,
			},
		})
		entry.id = ok and id or nil
		if matches and not matches() then return end
		if proof and not ok then proof.geometryComplete = false;return finish() end
	end
	if finish then proof.geometryComplete = true;return finish() end
end
Blizz.RemovePrivateAnchors = RemovePrivateAnchors

---------------------------------------------------------------------------
-- Styling (out of combat only)
---------------------------------------------------------------------------
local TEXT_POINTS = {
	TOPLEFT = "TOPLEFT", TOP = "TOP", TOPRIGHT = "TOPRIGHT", LEFT = "LEFT", CENTER = "CENTER",
	RIGHT = "RIGHT", BOTTOMLEFT = "BOTTOMLEFT", BOTTOM = "BOTTOM", BOTTOMRIGHT = "BOTTOMRIGHT",
}
local OUTLINES = { NONE = "", OUTLINE = "OUTLINE", THICKOUTLINE = "THICKOUTLINE", MONOCHROME = "MONOCHROME,OUTLINE" }

local function Outline(value)
	if value == nil or value == "DEFAULT" then return nil end
	return OUTLINES[value]
end

-- Polled units have no unit events: no cast bar and no aura containers.
local function HasCastbar(key) return not INFO[key].polled end
local function HasAuras(key) return not INFO[key].polled end
M.HasCastbar, M.HasAuras = HasCastbar, HasAuras

-- Child frame levels from the frame's own level, so a changed frame level
-- (General tab) keeps the parts in order. Every part sits on a level of its
-- own above the art frame: the game draws two frames on the same level in
-- no fixed order, so the frame graphics' material (painted on the art
-- frame) could otherwise cover the health bar and leave only a dark bar.
-- Bottom to top: the art frame with its material, the empty health well,
-- the health fill, heal prediction, the power bar, the frame graphics'
-- border (Core/UnitGraphics.lua) and the texts. The bar parts follow the
-- order the group frames share (E.UnitGraphics.BAR_LEVELS).
local BAR_LEVELS = E.UnitGraphics.BAR_LEVELS
M.LEVELS = {
	art = BAR_LEVELS.art, well = BAR_LEVELS.well, health = BAR_LEVELS.fill, prediction = BAR_LEVELS.prediction,
	predictionMine = BAR_LEVELS.predictionMine, portrait = 2, portraitOverlay = 6,
	powerWell = 6, power = 7, powerCost = 8, powerText = 9, infoPanel = 2, castbar = 8, auras = 4,
	graphics = 10, text = 11, threat = 12, offTank = 13,
}
local function SetLevels(frame, db)
	local base, level = frame:GetFrameLevel(), M.LEVELS
	local overlay = db.portrait == "overlay"
	frame.art:SetFrameLevel(base + level.art)
	frame.health:SetFrameLevel(base + level.health)
	frame.health.bg:SetFrameLevel(base + level.well)
	for _, key in ipairs({ "other", "absorb", "healAbsorb" }) do frame.prediction[key]:SetFrameLevel(base + level.prediction) end
	frame.prediction.mine:SetFrameLevel(base + level.predictionMine)
	frame.portraitHolder:SetFrameLevel(base + (overlay and level.portraitOverlay or level.portrait))
	if frame.model then frame.model:SetFrameLevel(frame.portraitHolder:GetFrameLevel()) end
	if frame.power:GetParent() == frame.art then
		frame.power:SetFrameLevel(base + level.power)
		frame.power.bg:SetFrameLevel(base + level.powerWell)
		frame.powerLayer:SetFrameLevel(base + level.powerText)
		if frame.powerCost then frame.powerCost:SetFrameLevel(base + level.powerCost) end
	end
	frame.infoPanel:SetFrameLevel(base + level.infoPanel)
	frame.textLayer:SetFrameLevel(base + level.text)
	-- The gates follow their anchors' new levels; threat sits on the frame
	-- or on the portrait box.
	local threatOn = db.threatOn == "PORTRAIT" and frame.portraitShown and db.portrait ~= "overlay" and frame.portraitHolder or frame.art
	frame.threatGate:SetAnchor(threatOn)
	frame.offTankGate:SetAnchor(threatOn)
	frame.lowHealthGate:SetAnchor(frame.health)
	frame.lowPowerGate:SetAnchor(frame.power)
end

-- The detached player power bar has its own mover, made the first
-- time the style is picked (a mover always shows in move mode).
local function PowerHolder()
	if not M.powerHolder then
		local holder = CreateFrame("Frame", "EldoUI_PlayerFramePowerHolder", UIParent)
		holder:SetSize(277, 8)
		M.powerHolder = holder
		-- Made outside OnEnable: tag the mover with this module (exports, layout chains).
		local previous = E.currentModule
		E.currentModule = M
		E:CreateMover(holder, "EldoUI_PlayerFramePower", L["Player Frame Power Bar"], { "CENTER", "UIParent", "CENTER", -378, -225 })
		E.currentModule = previous
		-- The cast bar on the player frame steps under the power bar while
		-- it hangs from the frame (CastX.PowerBelow), and back when it moves.
		E:RegisterMoverCallback("EldoUI_PlayerFramePower", function()
			local frame = M.frames and M.frames.player
			if frame and frame.db and CastX.LayoutCastbar and not E:StandsBack(M, "player") then
				local profile, rootDB, profileName, settings, layout = M.db, E.db, E.profileName, frame.db, CastX.LayoutCastbar
				E:RunOutOfCombat(function()
					if M.active and M.db == profile and E.db == rootDB and E.profileName == profileName and M.frames.player == frame
						and frame.db == settings and CastX.LayoutCastbar == layout and not E:StandsBack(M, "player") then layout(frame, settings) end
				end, "UnitFrames:castUnderPower")
			end
		end)
	end
	return M.powerHolder
end

-- Orbs are for the player frame: health in one orb, power in a second one
-- on the detached power bar's mover.
local function IsOrb(frame, db)
	return frame.unit == "player" and type(db) == "table" and db.shape == "ORB"
end
M.IsOrb = IsOrb

-- The orb shape: the frame's own box and the health well give way to the
-- orbs, the highlight takes the orb's round shape, and the incoming heal
-- bars (straight bars) stay hidden. Leaving it brings every box back.
local ORB = E.Orb
local function LayoutOrbs(frame, db)
	local orb = IsOrb(frame, db)
	frame.orbShape = orb or nil
	if orb then
		local size = math.min(db.width, db.height)
		-- The statues stand on the outer sides: left of health, right of power.
		local statues = db.orbStatues ~= false
		ORB:Attach(frame.health, frame, size, { motion = db.orbMotion, statue = statues and "LEFT" or nil })
		local powerSize = math.min(db.powerWidth > 0 and db.powerWidth or size, math.max(db.powerHeight or 0, 1))
		if M.powerHolder then
			M.powerHolder:SetSize(powerSize, powerSize)
			ORB:Attach(frame.power, M.powerHolder, powerSize, { motion = db.orbMotion, statue = statues and "RIGHT" or nil })
		end
		-- Texts and status icons above the ring, where the icons sit (LayoutIndicators).
		local ring = ORB.State(frame.health)
		if ring and ring.holderFrame then
			frame.textLayer:SetFrameLevel(math.max(frame.textLayer:GetFrameLevel(), ring.holderFrame:GetFrameLevel() + 1))
		end
		if frame.GetBackdrop and frame:GetBackdrop() ~= nil then
			frame:SetBackdropColor(0, 0, 0, 0)
			frame:SetBackdropBorderColor(0, 0, 0, 0)
			frame:SetBackdrop(nil)
		end
		frame.boxCleared = true
		frame.highlight:SetTexture(E.skinOrb and E.skinOrb.files.fill or E.media.flat)
		frame.highlight:SetVertexColor(1, 1, 1, 0.12)
		for _, key in ipairs({ "other", "mine", "absorb", "healAbsorb" }) do frame.prediction[key]:Hide() end
		frame.prediction.overAbsorb:Hide()
		return
	end
	ORB:Detach(frame.health)
	ORB:Detach(frame.power)
	if frame.boxCleared then
		frame.boxCleared = nil
		E:SetTemplate(frame)
		frame.highlight:SetColorTexture(1, 1, 1, 0.1)
	end
end

local function PowerStyle(frame, db)
	if IsOrb(frame, db) then return "DETACHED" end
	local style = db.powerStyle or "ATTACHED"
	if style == "DETACHED" and frame.unit ~= "player" then style = "INSET" end
	return style
end

-- Bars, portrait and info panel. Runs from StyleFrame and again when an
-- attached power bar comes or goes (also in combat: only non-secure
-- children of the frame are touched here, never the frame itself).
local function LayoutBars(frame)
	local db = frame.db
	if not db then return end
	local inset = E.pixel
	local width, height = db.width, db.height
	local info = db.infoPanel or {}
	local infoHeight = info.enabled and math.max(info.height or 14, 4) or 0
	local infoTop = infoHeight > 0 and info.position == "TOP"
	local holder = frame.portraitHolder
	holder:ClearAllPoints()
	holder:SetAlpha(1)
	frame.portraitShown = db.portrait ~= "none"
	holder:SetShown(frame.portraitShown)

	-- Portrait box: its own bordered box at the outer edge, as tall
	-- as the whole frame, sharing its inner edge with the bars' border.
	local left, right = inset, -inset
	local box = db.portrait == "boxLeft" or db.portrait == "boxRight"
	local boxWidth = 0
	if box then
		boxWidth = (db.portraitWidth or 0) > 0 and db.portraitWidth or height
		boxWidth = math.max(math.min(boxWidth, width - 24), 8)
		local side = db.portrait == "boxLeft" and "LEFT" or "RIGHT"
		holder:SetPoint("TOP" .. side, frame, "TOP" .. side, 0, 0)
		holder:SetPoint("BOTTOM" .. side, frame, "BOTTOM" .. side, 0, 0)
		holder:SetWidth(boxWidth)
		E:SetTemplate(holder)
		if side == "LEFT" then left = boxWidth else right = -boxWidth end
	elseif holder.SetBackdrop then
		holder:SetBackdrop(nil)
	end
	-- Inside a box the picture keeps clear of its 1-px border.
	-- The bars' column, from the settings: the texts on it keep inside it.
	frame.areaWidths = frame.areaWidths or {}
	frame.areaWidths.info = width + right - left
	local px = box and E:PixelFor(holder) or 0
	frame.portrait:ClearAllPoints()
	frame.portrait:SetPoint("TOPLEFT", holder, "TOPLEFT", px, -px)
	frame.portrait:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -px, px)
	if frame.model then
		frame.model:ClearAllPoints()
		frame.model:SetPoint("TOPLEFT", holder, "TOPLEFT", px, -px)
		frame.model:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -px, px)
	end

	-- Info panel: under the bars, or the name bar over them (TOP). Beside a
	-- portrait box it spans the bars only.
	local top, bottom = inset, inset
	frame.infoPanel:ClearAllPoints()
	if infoHeight > 0 then
		if infoTop then
			frame.infoPanel:SetPoint("TOPLEFT", left, -inset)
			frame.infoPanel:SetPoint("TOPRIGHT", right, -inset)
			top = inset + infoHeight + inset
		else
			frame.infoPanel:SetPoint("BOTTOMLEFT", left, inset)
			frame.infoPanel:SetPoint("BOTTOMRIGHT", right, inset)
			bottom = inset + infoHeight + inset
		end
		frame.infoPanel:SetHeight(infoHeight)
		E:SetTemplate(frame.infoPanel, info.transparent)
		frame.infoPanel:Show()
	else
		frame.infoPanel:Hide()
	end

	-- Portrait beside the bars (as tall as the bar area) or over the health.
	local barsHeight = height - top - bottom + 2 * inset
	local portraitSize = math.max(barsHeight - 2 * inset, 1)
	if db.portrait == "left" then
		holder:SetPoint("TOPLEFT", left, -top)
		holder:SetSize(portraitSize, portraitSize)
		left = left + portraitSize + inset
	elseif db.portrait == "right" then
		holder:SetPoint("TOPRIGHT", right, -top)
		holder:SetSize(portraitSize, portraitSize)
		right = right - portraitSize - inset
	end

	-- Power bar.
	local style = PowerStyle(frame, db)
	local power = frame.power
	local powerHeight = math.max(db.powerHeight or 0, 1)
	local healthWidth = width + right - left
	frame.areaWidths.health, frame.areaWidths.left = healthWidth, left
	power:ClearAllPoints()
	power:SetOrientation("HORIZONTAL")
	power:SetReverseFill(db.powerReverse and true or false)
	if style == "DETACHED" then
		local powerHolder = PowerHolder()
		powerHolder:SetSize(db.powerWidth > 0 and db.powerWidth or width, powerHeight)
		powerHolder:Show()
		power:SetParent(powerHolder)
		power:SetAllPoints(powerHolder)
		power:SetFrameLevel(powerHolder:GetFrameLevel() + 2)
		power.bg:SetFrameLevel(powerHolder:GetFrameLevel() + 1)
		frame.powerLayer:SetFrameLevel(powerHolder:GetFrameLevel() + 4)
		if frame.powerCost then frame.powerCost:SetFrameLevel(powerHolder:GetFrameLevel() + 3) end
	else
		if frame.unit == "player" and M.powerHolder then M.powerHolder:Hide() end
		power:SetParent(frame.art)
		if style == "INSET" then
			-- Centered on the bottom edge of the bars, over the health bar.
			local powerWidth = db.powerWidth > 0 and db.powerWidth or math.max(healthWidth - 20, 10)
			power:SetSize(powerWidth, powerHeight)
			power:SetPoint("CENTER", frame, "BOTTOM", (left + right) / 2, bottom)
		else
			power:SetPoint("BOTTOMLEFT", left, bottom)
			power:SetPoint("BOTTOMRIGHT", right, bottom)
			power:SetHeight(powerHeight)
		end
	end

	-- Health fills the rest (an attached power bar takes its room).
	local health = frame.health
	health:ClearAllPoints()
	health:SetPoint("TOPLEFT", left, -top)
	health:SetPoint("TOPRIGHT", right, -top)
	local healthBottom = bottom
	if style == "ATTACHED" and power:IsShown() and (db.powerHeight or 0) > 0 then
		health:SetPoint("BOTTOM", power, "TOP", 0, inset)
		healthBottom = bottom + powerHeight + inset
	else
		health:SetPoint("BOTTOM", frame, "BOTTOM", 0, bottom)
	end
	health:SetOrientation(db.healthOrientation == "VERTICAL" and "VERTICAL" or "HORIZONTAL")
	health:SetReverseFill(db.healthReverse and true or false)
	local healthHeight = height - top - healthBottom

	-- Overlay portrait: inside the health bar, cropped to its shape.
	local crop = E.tokens.portraitCrop
	local keep = 0.5 - crop
	frame.portraitAspect = 1
	if db.portrait == "overlay" then
		holder:SetAllPoints(health)
		holder:SetAlpha(math.max(0, math.min(db.portraitAlpha or 0.35, 1)))
		local ratio = math.max(healthHeight, 1) / math.max(healthWidth, 1)
		local half = math.min(keep * ratio, keep)
		frame.portraitCoords = { crop, 1 - crop, 0.5 - half, 0.5 + half }
	elseif box then
		-- A box wider (or taller) than square crops the picture to its shape.
		local ratio = math.max(height - 2 * px, 1) / math.max(boxWidth - 2 * px, 1)
		frame.portraitAspect = 1 / ratio
		if ratio < 1 then
			local half = keep * ratio
			frame.portraitCoords = { crop, 1 - crop, 0.5 - half, 0.5 + half }
		else
			local half = keep / ratio
			frame.portraitCoords = { 0.5 - half, 0.5 + half, crop, 1 - crop }
		end
	else
		frame.portraitCoords = nil
	end
	if frame.portraitShown and db.portraitStyle == "3D" and not frame.model then
		E.Portrait.Model(frame)
		frame.model:ClearAllPoints()
		frame.model:SetPoint("TOPLEFT", holder, "TOPLEFT", px, -px)
		frame.model:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -px, px)
	end
	if not frame.portraitShown then E.Portrait:Release(frame) end

	-- Prediction bars are as big as the health bar (computed from the
	-- settings, never measured from a bar that may hold a secret).
	LayoutPrediction(frame, db, healthWidth, healthHeight)
	SetLevels(frame, db)
	LayoutOrbs(frame, db)
end

-- On an orb the frame's corners are empty air, so an icon set on a corner
-- or edge sits on the ring instead: at that point's angle, half over the
-- ring's outer edge, still moved by the player's own offset. `step` moves it
-- along the ring toward the top instead, in icon widths (the leader and role
-- icons line up beside the resting icon).
local RING_ANGLES = { TOPLEFT = 135, TOP = 90, TOPRIGHT = 45, LEFT = 180, RIGHT = 0,
	BOTTOMLEFT = 225, BOTTOM = 270, BOTTOMRIGHT = 315 }
local function PlaceIcon(region, frame, db, point, x, y, step)
	local angle = frame.orbShape and RING_ANGLES[point]
	if not angle then
		region:SetPoint("CENTER", frame, point, x, y)
		return
	end
	local size = db.indicators.size or 16
	local radius = math.min(db.width, db.height) / 2 - size / 4
	if step then
		angle = angle + (angle > 90 and angle < 270 and -1 or 1) * math.deg(step * (size + 2) / radius)
		x, y = 0, 0
	end
	local rad = math.rad(angle)
	region:SetPoint("CENTER", frame, "CENTER", radius * math.cos(rad) + x, radius * math.sin(rad) + y)
end

local function LayoutIndicators(frame, db)
	local ind = frame.indicators
	local settings = db.indicators
	local size = settings.size or 16
	for key, texture in pairs(ind) do
		if key ~= "restingText" then
			texture:SetSize(size, size)
			texture:ClearAllPoints()
		end
	end
	local combatSize = (settings.combatSize or 0) > 0 and settings.combatSize or size
	ind.combat:SetSize(combatSize, combatSize)
	ApplyIconStyle(ind.combat, COMBAT_STYLES[settings.combatStyle] or COMBAT_STYLES.MODERN)
	ind.combat:SetVertexColor(unpack(settings.combatColor or { 1, 1, 1 }))
	local combatPoint = TEXT_POINTS[settings.combatPoint] or "BOTTOMLEFT"
	PlaceIcon(ind.combat, frame, db, combatPoint, settings.combatX or 0, settings.combatY or 0)

	local restingSize = (settings.restingSize or 0) > 0 and settings.restingSize or size
	ind.resting:SetSize(restingSize, restingSize)
	ApplyIconStyle(ind.resting, RESTING_STYLES.CLASSIC)
	ind.resting:SetVertexColor(unpack(settings.restingColor or { 1, 1, 1 }))
	local restingPoint = TEXT_POINTS[settings.restingPoint] or "TOPLEFT"
	PlaceIcon(ind.resting, frame, db, restingPoint, settings.restingX or 0, settings.restingY or 0)
	E:SetFont(ind.restingText, math.max(math.floor(restingSize * 0.75), 8), "OUTLINE")
	ind.restingText:SetTextColor(unpack(settings.restingColor or { 1, 1, 1 }))
	ind.restingText:ClearAllPoints()
	PlaceIcon(ind.restingText, frame, db, restingPoint, settings.restingX or 0, settings.restingY or 0)

	PlaceIcon(ind.leader, frame, db, "TOPLEFT", size + 2, 0, 1)
	PlaceIcon(ind.role, frame, db, "TOPLEFT", 2 * size + 4, 0, 2)
	PlaceIcon(ind.pvp, frame, db, "TOPRIGHT", -2, 0)
	PlaceIcon(ind.raidMarker, frame, db, "TOP", 0, 0)
	PlaceIcon(ind.classification, frame, db, "TOPRIGHT", -size - 2, 0, 1)
	local big = math.floor(size * 1.5)
	ind.readyCheck:SetSize(big, big)
	ind.readyCheck:SetPoint("CENTER", frame.health, "CENTER")
	ind.status:SetSize(big, big)
	ind.status:SetPoint("CENTER", frame.health, "CENTER", -big - 2, 0)
end

-- How far the info bar's text keeps from its top corner on one side:
-- 4 units, or more where a badge or an indicator sits on that corner (half
-- of it reaches into the frame, plus 4 units of air). Only the corner away
-- from the portrait touches the info bar; the other one is the portrait's.
local function CornerInset(db, side)
	local inset = 4
	local portrait = db.portrait or "none"
	local outer = (portrait == "boxRight" or portrait == "right") and "LEFT" or "RIGHT"
	if outer ~= side then return inset end
	for _, key in ipairs({ "class", "level" }) do
		local block = db.badges and db.badges[key]
		if block and block.enabled and (block.anchor or "OUTER_TOP") == "OUTER_TOP" then
			inset = math.max(inset, math.max(block.size or 18, 8) / 2 + 4)
		end
	end
	-- The PvP and elite marks sit on the top right corner (LayoutIndicators).
	local settings = db.indicators
	if side == "RIGHT" and settings then
		local size = settings.size or 16
		if settings.pvp then inset = math.max(inset, 2 + size / 2 + 4) end
		if settings.classification then inset = math.max(inset, size + 2 + size / 2 + 4) end
	end
	return inset
end

-- Name, health and power texts plus any number of extra texts.
local function LayoutTexts(frame, db, fontSize)
	E:SetNameTextFont(frame.nameText, (db.nameSize or 0) > 0 and db.nameSize or fontSize)
	E:SetFont(frame.healthText, fontSize)
	E:SetFont(frame.powerText, math.max(fontSize - 3, 8))
	frame.nameText:ClearAllPoints()
	frame.healthText:ClearAllPoints()
	frame.healthText:SetPoint("RIGHT", frame.health, "RIGHT", -6, 0)
	-- Texts outside the frame's edge: the unit-frame graphics move them out
	-- by what they paint there (Core/UnitGraphics.lua).
	local lift = frame.graphicsLift or {}
	frame.graphicsLift = lift
	wipe(lift)
	local position = db.nameText
	frame.nameText:SetShown(position ~= "NONE")
	if position == "TOP" then
		-- Above the bars, not above a portrait beside them.
		local x = ((frame.areaWidths and frame.areaWidths.left) or 0) + 2
		frame.nameText:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", x, 4)
		lift[#lift + 1] = { frame.nameText, "BOTTOMLEFT", frame, "TOPLEFT", x, 4, 1 }
	elseif position == "CENTER" then
		frame.nameText:SetPoint("CENTER", frame.health, "CENTER")
	elseif position == "INFO" and frame.infoPanel:IsShown() then
		frame.nameText:SetPoint("LEFT", frame.infoPanel, "LEFT", CornerInset(db, "LEFT"), 0)
	elseif position == "RIGHT" then
		frame.nameText:SetPoint("RIGHT", frame.health, "RIGHT", -6, 0)
		frame.healthText:ClearAllPoints()
		frame.healthText:SetPoint("LEFT", frame.health, "LEFT", 6, 0)
	else
		frame.nameText:SetPoint("LEFT", frame.health, "LEFT", 6, 0)
	end
	-- The name never reaches past the area it sits in (the game cuts it
	-- with "..."): the name panel less its corners and the panel's own
	-- right-hand text, the bars above the frame, the health bar when it is
	-- centered, and 60 % of the health bar beside the health text.
	local areas = frame.areaWidths or {}
	local nameWidth
	if position == "INFO" and frame.infoPanel:IsShown() and areas.info then
		local reserve = 0
		if db.infoPanel and (db.infoPanel.tag or "") ~= "" then reserve = areas.info * 0.4 end
		nameWidth = areas.info - CornerInset(db, "LEFT") - CornerInset(db, "RIGHT") - reserve
	elseif position == "TOP" then
		nameWidth = (areas.health or db.width) - 4
	elseif position == "CENTER" and areas.health then
		nameWidth = areas.health - 12
	elseif areas.health then
		nameWidth = areas.health * 0.6
	end
	frame.nameText:SetWidth(math.max(nameWidth or db.width * 0.6, 20))
	frame.powerText:ClearAllPoints()
	frame.powerText:SetPoint("RIGHT", frame.power, "RIGHT", -4, 0)
	frame.powerText:SetShown((db.powerHeight or 0) >= 8)
	-- Orbs: the values in the middle of each orb, the name over the health orb.
	if IsOrb(frame, db) then
		frame.healthText:ClearAllPoints()
		frame.healthText:SetPoint("CENTER", frame.health, "CENTER", 0, 0)
		frame.healthText:SetJustifyH("CENTER")
		frame.powerText:ClearAllPoints()
		frame.powerText:SetPoint("CENTER", frame.power, "CENTER", 0, 0)
		frame.powerText:SetJustifyH("CENTER")
		E:SetFont(frame.powerText, fontSize)
		frame.powerText:SetShown(true)
		if position == "TOP" then
			frame.nameText:ClearAllPoints()
			frame.nameText:SetPoint("BOTTOM", frame, "TOP", 0, 4)
		end
	else
		frame.healthText:SetJustifyH("RIGHT")
		frame.powerText:SetJustifyH("RIGHT")
	end

	-- The info panel's own right-hand text (the Boxed name bar: race and class).
	local infoShown = frame.infoPanel:IsShown()
	E:SetFont(frame.infoText, math.max(fontSize - 3, 8))
	frame.infoText:ClearAllPoints()
	frame.infoText:SetPoint("RIGHT", frame.infoPanel, "RIGHT", -CornerInset(db, "RIGHT"), 0)
	frame.infoText:SetShown(infoShown)
	frame.tags = { name = NameTag(db), health = HealthTag(db), power = PowerTag(db),
		info = infoShown and db.infoPanel and db.infoPanel.tag or "" }
	local count = #(db.texts or {})
	for index = #frame.customTexts + 1, count do
		frame.customTexts[index] = E:CreateText(frame.textLayer, E.tokens.size.small, "CENTER")
		-- An extra text can show a name ([name] and the other tags).
		E:UseNameFont(frame.customTexts[index])
	end
	for index, text in ipairs(frame.customTexts) do
		local settings = db.texts and db.texts[index]
		local tag = ExtraTag(settings)
		frame.tags[index] = tag
		text:ClearAllPoints()
		if tag ~= "" then
			local point = TEXT_POINTS[settings.anchor] or "CENTER"
			E:SetMediaFont(text, settings.font, settings.size or 11, Outline(settings.outline))
			local justify = settings.justify
			if justify ~= "LEFT" and justify ~= "RIGHT" and justify ~= "CENTER" then
				justify = point:find("LEFT") and "LEFT" or point:find("RIGHT") and "RIGHT" or "CENTER"
			end
			text:SetJustifyH(justify)
			local anchorTo = frame
			if settings.attach == "HEALTH" then
				anchorTo = frame.health
			elseif settings.attach == "POWER" and frame.power:GetParent() == frame.art then
				anchorTo = frame.power
			elseif settings.attach == "INFO" and frame.infoPanel:IsShown() then
				anchorTo = frame.infoPanel
			end
			local y = settings.y or 0
			text:SetPoint(point, anchorTo, point, settings.x or 0, y)
			-- Above the top edge or under the bottom edge of the frame.
			local side = anchorTo == frame and (point:find("TOP") and y > 0 and 1 or point:find("BOTTOM") and y < 0 and -1)
			if side then lift[#lift + 1] = { text, point, frame, point, settings.x or 0, y, side } end
			text:Show()
		else
			text:SetText("")
			text:Hide()
		end
	end
end

-- The Cooldown Manager the detached player cast bar can hang on.
function CastX.CooldownAnchor()
	return E.movers.EldoUI_Cooldowns or EssentialCooldownViewer
end

-- Width of the detached player bar: its own, or the Cooldown Manager's
-- (when readable) with "match width".
function CastX.CastWidth(frame, cast)
	if frame.unit == "player" and cast.detached and (cast.anchor or "MOVER") ~= "MOVER" and cast.matchWidth then
		local anchor = CastX.CooldownAnchor()
		local width = anchor and Plain(anchor.GetWidth, anchor)
		if type(width) == "number" and width > 20 then return math.floor(width + 0.5) end
	end
	return cast.width
end

-- The detached player cast bar as a member of the cooldown stack
-- (Modules/CombatHUD/Kit.lua): under the row ("cast") or above it
-- ("castAbove"), after the pieces that sit closer to the row.
function CastX.StackedCastbar(side)
	local frame = M.active and M.frames and M.frames.player
	local cast = frame and frame.db and frame.db.castbar
	if not (cast and cast.enabled and cast.detached and frame.castbar.enabled and not E:StandsBack(M, "player")) then return nil end
	local anchor = cast.anchor or "MOVER"
	if (side == "ABOVE" and anchor ~= "COOLDOWNS_ABOVE") or (side == "BELOW" and anchor ~= "COOLDOWNS_BELOW") then return nil end
	return frame.castbar
end

function CastX.RegisterCooldownStack()
	local stack = E.CombatKit and E.CombatKit.CooldownStack
	if not stack or stack.IsRegistered("cast") then return end
	local function Relayout()
		local frame = M.frames.player
		if not (M.active and frame and frame.db and not E:StandsBack(M, "player")) then return end
		local cast = frame.db.castbar
		if cast.detached and (cast.anchor or "MOVER") ~= "MOVER" then CastX.LayoutCastbar(frame, frame.db) end
	end
	local function Gap()
		local frame = M.frames.player
		return frame and frame.db and frame.db.castbar.anchorGap or 4
	end
	stack.Register("cast", { frame = function() return CastX.StackedCastbar("BELOW") end, gap = Gap, relayout = Relayout })
	stack.Register("castAbove", { frame = function() return CastX.StackedCastbar("ABOVE") end, gap = Gap, relayout = Relayout })
end

-- How far the player's power bar on its own mover reaches under the player
-- frame when it hangs from the frame's bottom edge (every layout puts it
-- there): the cast bar on the frame hangs under it instead of over it.
function CastX.PowerBelow()
	local holder, mover = M.powerHolder, E.movers.EldoUI_PlayerFramePower
	local player = E.movers.EldoUI_Player
	if not (holder and mover and player) then return 0 end
	local point, rel, relPoint, _, y = mover:GetPoint(1)
	if rel ~= player or type(point) ~= "string" or type(relPoint) ~= "string" then return 0 end
	if not (point:find("^TOP") and relPoint:find("^BOTTOM")) or (y or 0) > 0 then return 0 end
	return -(y or 0) + (holder:GetHeight() or 0)
end

local InitializeCooldownStack
do
local layoutRequest = 0
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
-- The detached player cast bar and its gate are EldoUI's own frames: admit
-- them once to the shared geometry reader, so the cooldown stack can measure
-- the bar and place it above or below the cooldowns like the other members.
CastX.admittedGeometry = setmetatable({}, { __mode = "k" })
function CastX.AdmitCastbarGeometry(castbar)
	if issecret(castbar) or type(castbar) ~= "table" then return end
	local source = rawget(E, "MoverAuthoritySource")
	if issecret(source) or type(source) ~= "function" then return end
	local ok, _, _, _, _, _, _, admit = pcall(source)
	if not ok or issecret(admit) or type(admit) ~= "function" then return end
	local gate = rawget(castbar, "gate")
	for _, object in ipairs({ gate, castbar }) do
		if not issecret(object) and type(object) == "table" and not CastX.admittedGeometry[object] then
			local admitted, read = pcall(admit, object, true)
			if admitted and read ~= nil then CastX.admittedGeometry[object] = true end
		end
	end
end

local function LayoutCastbar(frame, db)
	-- The cast target's share of the bar, and the narrowest bar that shows it.
	local CAST_TARGET_SHARE, CAST_TARGET_MIN_BAR = 0.35, 140
	local castbar = frame.castbar
	local cast = db.castbar
	local valid, amount, phase, fallback
	local stack, usesBody, entryRequest, entryCurrent
	if not issecret(frame.unit) and frame.unit == "player" and not issecret(cast.detached) and cast.detached
		and not issecret(cast.anchor) and (cast.anchor == "COOLDOWNS_ABOVE" or cast.anchor == "COOLDOWNS_BELOW") then
		-- Before the methods below are captured: admission hooks them once.
		CastX.AdmitCastbarGeometry(castbar)
		layoutRequest = layoutRequest + 1
		entryRequest = layoutRequest
		local root, profile, settings, frames, active = E.db, E.profileName, M.db, M.frames, M.active
		local gate, holder, unit = castbar.gate, M.castHolder, frame.unit
		local saved, keys = {}, { "enabled", "detached", "anchor", "anchorGap", "width", "height", "syncWidth", "icon", "iconSize", "iconAttach", "iconPosition" }
		for _, key in ipairs(keys) do
			if issecret(cast[key]) then return end
			saved[key] = cast[key]
		end
		local methods = { castbar.ClearAllPoints, castbar.SetPoint, castbar.GetNumPoints, castbar.GetPoint,
			gate.ClearAllPoints, gate.SetParent, gate.SetAllPoints, holder and holder.SetSize }
		local function Same(a, b) return not issecret(a) and not issecret(b) and rawequal(a, b) end
		entryCurrent = function()
			if entryRequest ~= layoutRequest or not Same(E.db, root) or not Same(E.profileName, profile)
				or not Same(M.db, settings) or not Same(M.active, active) or not Same(M.frames, frames)
				or not Same(frames.player, frame) or not Same(frame.unit, unit) or not Same(frame.db, db) or not Same(db.castbar, cast)
				or not Same(frame.castbar, castbar) or not Same(castbar.gate, gate) or not Same(M.castHolder, holder)
				or not Same(castbar.ClearAllPoints, methods[1]) or not Same(castbar.SetPoint, methods[2])
				or not Same(castbar.GetNumPoints, methods[3]) or not Same(castbar.GetPoint, methods[4])
				or not Same(gate.ClearAllPoints, methods[5]) or not Same(gate.SetParent, methods[6])
				or not Same(gate.SetAllPoints, methods[7]) or (holder and not Same(holder.SetSize, methods[8])) then return false end
			for _, key in ipairs(keys) do if not Same(cast[key], saved[key]) then return false end end
			return true
		end
		if not entryCurrent() then return end
		local ready, state = InitializeCooldownStack()
		if not entryCurrent() or (not ready and state ~= "pending" and state ~= "absent") then return end
		if ready then
			local ok, present = pcall(sourceBody)
			if not ok or issecret(present) or type(present) ~= "boolean" or not InitializeCooldownStack() or not entryCurrent() then return end
			usesBody = present
		end
	end
	if usesBody then
		stack = sourceStack
		if not rawequal(stack, sourceStack) or not rawequal(stack.Offset, sourceOffset) then return end
		local request = entryRequest
		local root, profile, settings, frames, gate, holder, active = E.db, E.profileName, M.db, M.frames, castbar.gate, M.castHolder, M.active
		local anchor = CastX.CooldownAnchor()
		local saved, keys = {}, { "enabled", "detached", "anchor", "anchorGap", "width", "height", "syncWidth", "icon", "iconSize", "iconAttach", "iconPosition" }
		local function Same(a, b) return not issecret(a) and not issecret(b) and rawequal(a, b) end
		for _, key in ipairs(keys) do
			if issecret(cast[key]) then return end
			saved[key] = cast[key]
		end
		local clear, set, count, point = castbar.ClearAllPoints, castbar.SetPoint, castbar.GetNumPoints, castbar.GetPoint
		local getOffset = stack.Offset
		local gateMethods = { clear = gate.ClearAllPoints, parent = gate.SetParent, all = gate.SetAllPoints }
		local holderSize = holder and holder.SetSize
		phase = "before"
		local initial
		valid = function(checkPoints)
			if not InitializeCooldownStack() or not entryCurrent() or request ~= layoutRequest or not Same(E.db, root) or not Same(E.profileName, profile)
				or not Same(M.db, settings) or not Same(M.active, active) or not Same(M.frames, frames) or not Same(frames.player, frame)
				or not Same(frame.db, db) or not Same(frame.castbar, castbar) or not Same(db.castbar, cast)
				or not Same(castbar.gate, gate) or not Same(M.castHolder, holder)
				or not Same(gate.ClearAllPoints, gateMethods.clear) or not Same(gate.SetParent, gateMethods.parent)
				or not Same(gate.SetAllPoints, gateMethods.all) or (holder and not Same(holder.SetSize, holderSize))
				or not Same(stack, sourceStack) or not Same(stack.Offset, getOffset)
				or not Same(CastX.CooldownAnchor(), anchor) or not Same(castbar.ClearAllPoints, clear)
				or not Same(castbar.SetPoint, set) or not Same(castbar.GetNumPoints, count) or not Same(castbar.GetPoint, point) then return false end
			for _, key in ipairs(keys) do if not Same(cast[key], saved[key]) then return false end end
			if E:StandsBack(M, "player") then return false end
			if checkPoints then
				local n = count(castbar)
				if issecret(n) or type(n) ~= "number" or n < 0 or n > 2 or n ~= math.floor(n) then return false end
				if phase == "cleared" then return n == 0 end
				local points = { n = n }
				for i = 1, n do
					points[i] = { point(castbar, i) }
					for j = 1, 5 do if issecret(points[i][j]) then return false end end
				end
				if initial then
					if initial.n ~= n then return false end
					for i = 1, n do for j = 1, 5 do if not Same(initial[i][j], points[i][j]) then return false end end end
				else initial = points end
			end
			if request ~= layoutRequest or not Same(frame.castbar, castbar) or not Same(E.db, root) or not Same(M.db, settings)
				or not Same(db.castbar, cast) or not Same(M.active, active) or not Same(M.castHolder, holder) then return false end
			for _, key in ipairs(keys) do if not Same(cast[key], saved[key]) then return false end end
			return InitializeCooldownStack()
		end
		if not valid(true) then return end
	end
	castbar.settings = cast
	-- The player's cast bar also waits until Blizzard's is out of sight.
	castbar.enabled = cast.enabled and HasCastbar(frame.key)
		and (frame.key ~= "player" or Blizz.OutOfSight("player-cast-bar")) and true or false
	castbar.showTime = cast.time
	castbar.showLatency = cast.latency
	castbar.showTarget = cast.spellTarget
	castbar.showInterrupted = cast.showInterrupted ~= false
	castbar.reverse = cast.reverse and true or false
	castbar.formatter = CastFormatter()
	local height = cast.height
	local iconSize = (cast.iconSize or 0) > 0 and cast.iconSize or height
	local attach = cast.iconAttach or "ATTACHED"
	local onRight = cast.iconPosition == "RIGHT"
	local besides = cast.icon and attach == "ATTACHED"
	if besides then iconSize = height end
	if valid then
		local status
		amount, status = stack.Offset(cast.anchor == "COOLDOWNS_ABOVE" and "castAbove" or "cast", castbar)
		if not valid(true) or issecret(amount) or issecret(status) then return end
		if status == "unavailable" then
			-- The stack can't be measured right now. A bar that already has
			-- a spot keeps it until the stack lays it again; a bar with no
			-- spot yet sits on its own mover.
			fallback = castbar:GetNumPoints() > 0 and CastX.CooldownAnchor() and "keep" or "mover"
			amount = nil
			if not valid(true) then return end
		elseif type(amount) ~= "number" or amount ~= amount or amount <= -math.huge or amount >= math.huge then return end
	end
	local totalWidth = CastX.CastWidth(frame, cast)
	if valid and not valid(true) then return end
	castbar.matchedWidth = totalWidth
	castbar.barWidth = math.max(totalWidth - (besides and (iconSize + E.pixel) or 0), 10)
	if fallback ~= "keep" then
		castbar:ClearAllPoints()
		if valid then phase = "cleared"; if not valid(true) then return end end
	end
	castbar.barHeight = height
	castbar:SetSize(castbar.barWidth, height)
	if valid and not valid(true) then return end
	castbar:SetReverseFill(castbar.reverse)
	if valid and not valid(true) then return end
	local holder = frame.unit == "player" and cast.detached and M.castHolder
	local shift = (besides and onRight) and -(iconSize + E.pixel) or 0
	local gate = castbar.gate
	if valid and not valid(true) then return end
	gate:ClearAllPoints()
	if valid and not valid(true) then return end
	if holder then
		gate:SetParent(holder)
		if valid and not valid(true) then return end
		gate:SetAllPoints(holder)
		if valid and not valid(true) then return end
		holder:SetSize(cast.width, height)
		if valid and not valid(true) then return end
		local anchorTo = cast.anchor or "MOVER"
		local cooldowns = anchorTo ~= "MOVER" and CastX.CooldownAnchor()
		-- The bar's far end lines up with the anchor; the icon side is the
		-- free end, so bar and icon together are the matched width.
		local side = onRight and "LEFT" or "RIGHT"
		if cooldowns and not fallback then
			-- On the cooldown stack: past the power bar above the row, or past
			-- the item row and tracking bars below it.
			local gap = cast.anchorGap or 4
			local castStack = E.CombatKit and E.CombatKit.CooldownStack
			if anchorTo == "COOLDOWNS_ABOVE" then
				local offset = amount or (castStack and castStack.Offset("castAbove") or 0)
				if valid and not valid(true) then return end
				castbar:SetPoint("BOTTOM" .. side, cooldowns, "TOP" .. side, 0, gap + offset)
			else
				local offset = amount or (castStack and castStack.Offset("cast") or 0)
				if valid and not valid(true) then return end
				castbar:SetPoint("TOP" .. side, cooldowns, "BOTTOM" .. side, 0, -gap - offset)
			end
		elseif fallback ~= "keep" then
			-- On its own mover; a kept spot on the cooldown stack stays as it is.
			castbar:SetPoint(side, holder, side)
		end
		if valid and not valid(false) then return end
		castbar:SetFrameLevel(holder:GetFrameLevel() + 2)
	else
		gate:SetParent(frame)
		gate:SetAllPoints(frame)
		local y = cast.offsetY or -6
		if frame.unit == "player" and PowerStyle(frame, db) == "DETACHED" then y = y - CastX.PowerBelow() end
		castbar:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", (cast.offsetX or 0) + shift, y)
		castbar:SetFrameLevel(frame:GetFrameLevel() + M.LEVELS.castbar)
	end
	-- Settings that only apply to other units start clean on the player.
	if frame.unit == "player" then gate:SetAlpha(1) end
	castbar.bg:SetFrameLevel(math.max(castbar:GetFrameLevel() - 1, 0))
	if cast.customBackdrop then
		local c = cast.backdropColor or { 0.06, 0.06, 0.07 }
		castbar.bg:SetBackdropColor(c[1], c[2], c[3], 1)
	else
		castbar.bg:SetBackdropColor(unpack(E.media.backdropColor))
	end

	-- Icon: beside the bar, inside it, or free with its own offsets.
	local iconFrame = castbar.iconFrame
	iconFrame:ClearAllPoints()
	iconFrame:SetSize(iconSize, iconSize)
	iconFrame:SetShown(cast.icon and true or false)
	local textLeft, textRight = 4, -4
	if attach == "INSIDE" then
		iconFrame:SetSize(height, height)
		if onRight then
			iconFrame:SetPoint("RIGHT", castbar, "RIGHT")
			textRight = -(height + 4)
		else
			iconFrame:SetPoint("LEFT", castbar, "LEFT")
			textLeft = height + 4
		end
		if not cast.icon then textLeft, textRight = 4, -4 end
	elseif attach == "DETACHED" then
		if onRight then
			iconFrame:SetPoint("LEFT", castbar, "RIGHT", 4 + (cast.iconX or 0), cast.iconY or 0)
		else
			iconFrame:SetPoint("RIGHT", castbar, "LEFT", -4 + (cast.iconX or 0), cast.iconY or 0)
		end
	else
		if onRight then
			iconFrame:SetPoint("LEFT", castbar, "RIGHT", E.pixel, 0)
		else
			iconFrame:SetPoint("RIGHT", castbar, "LEFT", -E.pixel, 0)
		end
	end
	iconFrame:SetFrameLevel(castbar:GetFrameLevel() + 1)

	-- Texts.
	local auto = math.max(math.min(height - 6, 13), 9)
	local nameSize = (cast.nameSize or 0) > 0 and cast.nameSize or auto
	local timeSize = (cast.timeSize or 0) > 0 and cast.timeSize or auto
	E:SetFont(castbar.text, nameSize)
	E:SetFont(castbar.time, timeSize)
	E:SetNameTextFont(castbar.target, math.max(nameSize - 2, 8))
	castbar.textLeft = textLeft
	castbar.marker:ClearAllPoints()
	castbar.markerSize = math.max(height - 4, 8)
	castbar.marker:SetSize(castbar.markerSize, castbar.markerSize)
	castbar.marker:SetPoint("LEFT", textLeft, 0)
	castbar.text:ClearAllPoints()
	castbar.text:SetPoint("LEFT", textLeft, 0)
	castbar.text:SetShown(cast.showName ~= false)
	if not cast.raidMarker then castbar.marker:Hide() end
	castbar.time:ClearAllPoints()
	castbar.time:SetPoint("RIGHT", textRight, 0)
	-- "1.4 / 2.5" needs about five font sizes of room, "1.4" three.
	local timeRoom = cast.time and math.ceil(timeSize * (cast.timeFormat == "REMAININGMAX" and 5 or 3)) + 4 or 0
	castbar.textEnd = textRight - timeRoom
	-- The cast target takes a fixed share left of the time, cut with "...";
	-- the name ends before it (CastX.AnchorCastText).
	castbar.target:ClearAllPoints()
	castbar.target:SetPoint("RIGHT", castbar, "RIGHT", castbar.textEnd, 0)
	castbar.targetWidth = math.floor(castbar.barWidth * CAST_TARGET_SHARE)
	castbar.target:SetWidth(castbar.targetWidth)
	castbar.target:SetJustifyH("RIGHT")
	castbar.targetRoom = castbar.barWidth >= CAST_TARGET_MIN_BAR
	if not castbar.targetRoom then castbar.targetShown = false; castbar.target:Hide() end
	CastX.AnchorCastText(castbar)

	-- Spark on the growing edge of the fill.
	local fill = castbar:GetStatusBarTexture()
	castbar.spark:ClearAllPoints()
	local edge = castbar.reverse and "LEFT" or "RIGHT"
	castbar.spark:SetPoint("TOP", fill, "TOP" .. edge)
	castbar.spark:SetPoint("BOTTOM", fill, "BOTTOM" .. edge)
	castbar.spark:SetShown(cast.spark and true or false)
	if not castbar.enabled then castbar:Hide() end
	CastX.FireCastHook("layout", castbar, frame.unit, { enabled = castbar.enabled, width = totalWidth, height = height })
end
CastX.LayoutCastbar = LayoutCastbar
end

---------------------------------------------------------------------------
-- Buffs and debuffs layout. Each block gets its own holder (our frame) and
-- a container inside it; a block can sit on the frame or on the other
-- block ("attach to"), so buffs can stack above debuffs.
---------------------------------------------------------------------------
local AURA_KIND = { buffs = "HELPFUL", debuffs = "HARMFUL" }
local OTHER = { buffs = "debuffs", debuffs = "buffs" }

local function AuraWidgetSettings(frame, which, block)
	local kind = AURA_KIND[which]
	local size = block.size
	local bars = block.style == "BARS"
	local groups = E:AuraFilterGroups(block.filter, kind, block.max)
	if type(block.filter) ~= "table" or block.filter.preset ~= "custom" then
		-- Presets follow the block's own sort; custom groups keep theirs.
		for _, group in ipairs(groups) do group.sortMethod, group.sortDirection = nil, nil end
	end
	groups = E.AuraWidget.SplitOwn(groups, block.ownFirst, block.desaturateOthers)
	local settings = {
		unit = frame.unit,
		groups = groups,
		max = block.max,
		perRow = bars and 1 or block.perRow,
		size = size,
		spacing = block.spacing or 4,
		growth = block.growthX == "LEFT" and "LEFT" or "RIGHT",
		wrap = block.growthY == "UP" and "UP" or "DOWN",
		sort = block.sort or "TIME",
		reverse = block.sortReverse and true or false,
		duration = block.duration or "SWIPE",
		durationSize = (block.durationSize or 0) > 0 and block.durationSize or math.max(math.floor(size * 0.45), 8),
		countSize = (block.countSize or 0) > 0 and block.countSize or math.max(math.floor(size * 0.45), 9),
		countPoint = block.countPoint, countX = block.countX, countY = block.countY,
		durationPoint = block.durationPoint, durationX = block.durationX, durationY = block.durationY,
		dispelBorder = block.dispelBorder and true or false,
		cancel = false,
		tooltip = not block.clickThrough,
	}
	if bars then
		settings.bar = {
			width = (block.barWidth or 0) > 0 and block.barWidth or frame.db.width,
			height = block.barHeight or 18,
			dispelColor = kind == "HARMFUL" and block.barColor == "DISPEL" or nil,
		}
	end
	-- Effects: aura pop-in and the expiring pulse or red time.
	settings.fx = E.FrameFX.AuraFX(frame.db.effects)
	return settings
end

-- The holder's size from the settings (the container sizes itself).
local function HolderSize(settings)
	if settings.bar then
		return settings.bar.width, math.max(settings.max * (settings.bar.height + settings.spacing) - settings.spacing, 1)
	end
	local perRow = math.max(math.min(settings.perRow, settings.max), 1)
	local rows = math.max(math.ceil(settings.max / math.max(settings.perRow, 1)), 1)
	local rowHeight = settings.size + settings.spacing + E.AuraWidget.TextRoom(settings)
	return perRow * (settings.size + settings.spacing) - settings.spacing, rows * rowHeight - settings.spacing
end

local function AnchorHolder(frame, which, block, fontSize)
	local holder = frame.auras[which].holder
	local db = frame.db
	local target, onFrame = frame, true
	local other = OTHER[which]
	local otherBlock = db[other]
	if block.attachTo == other:upper() and otherBlock.enabled and otherBlock.attachTo ~= which:upper() then
		target, onFrame = frame.auras[other].holder, false
	end
	local gap = 4
	local x, y = block.x or 0, block.y or 0
	local right = block.growthX == "LEFT"
	holder:ClearAllPoints()
	if block.anchor == "BOTTOM" then
		local drop = 0
		local cast = db.castbar
		if onFrame and cast.enabled and HasCastbar(frame.key) and not (frame.unit == "player" and cast.detached) then
			drop = cast.height - (cast.offsetY or -6)
		end
		holder:SetPoint(right and "TOPRIGHT" or "TOPLEFT", target, right and "BOTTOMRIGHT" or "BOTTOMLEFT", x, y - gap - drop)
	elseif block.anchor == "LEFT" then
		holder:SetPoint("TOPRIGHT", target, "TOPLEFT", x - gap, y)
	elseif block.anchor == "RIGHT" then
		holder:SetPoint("TOPLEFT", target, "TOPRIGHT", x + gap, y)
	else
		local lift = (onFrame and db.nameText == "TOP") and (fontSize + 4) or 0
		holder:SetPoint(right and "BOTTOMRIGHT" or "BOTTOMLEFT", target, right and "TOPRIGHT" or "TOPLEFT", x, y + gap + lift)
	end
end

local function ReleaseAuras(frame)
	for _, aura in pairs(frame.auras or {}) do
		if aura.container then
			E.AuraWidget.Release(aura.container)
			aura.container, aura.signature = nil, nil
		end
	end
end

local function LayoutAuras(frame, db, fontSize)
	local widget = E.AuraWidget
	-- The game's aura container: keeps working in combat, when addon code
	-- may not read auras. If the containers cannot be used, no frame auras
	-- show.
	if not (widget and widget.Available()) then return end
	for which in pairs(AURA_KIND) do
		local aura = frame.auras[which]
		if not aura then
			aura = { holder = CreateFrame("Frame", nil, frame) }
			frame.auras[which] = aura
		end
		local block = db[which]
		local settings = AuraWidgetSettings(frame, which, block)
		aura.holder:SetSize(HolderSize(settings))
		aura.holder:SetFrameLevel(frame:GetFrameLevel() + M.LEVELS.auras)
		aura.settings = settings
	end
	for which in pairs(AURA_KIND) do
		local aura, block = frame.auras[which], db[which]
		AnchorHolder(frame, which, block, fontSize)
		local on = block.enabled and db.enabled and HasAuras(frame.key) and not frame.testing
		local signature = on and widget.Signature(aura.settings) or nil
		if aura.signature ~= signature then
			widget.Release(aura.container)
			aura.container = signature and widget.Create(aura.holder, aura.settings) or nil
			aura.signature = aura.container and signature or nil
		end
		aura.holder:SetShown(on and true or false)
	end
end

-- Unit frames stay under Blizzard's menus and dialogs (the Game Menu and
-- the popups sit at DIALOG, the Settings window at HIGH): "High" is the
-- highest layer offered, and an older "Highest" setting draws as High.
local UnitStrata
do
local UNIT_STRATA = { BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true }
UnitStrata = function(db)
	local strata = db and db.strata
	if UNIT_STRATA[strata] then return strata end
	return strata == nil and "MEDIUM" or "HIGH"
end

end

local function StyleFrame(frame, db, fontSize)
	frame.db = db
	frame:SetSize(db.width, db.height)
	frame:SetScale(db.scale or 1)
	frame:SetFrameStrata(UnitStrata(db))
	frame.baseLevel = frame.baseLevel or frame:GetFrameLevel()
	frame:SetFrameLevel((db.level or 0) > 0 and db.level or frame.baseLevel)
	if not frame.testing then frame.power:SetShown(PowerWanted(frame)) end
	LayoutBars(frame)
	LayoutTexts(frame, db, fontSize)
	LayoutIndicators(frame, db)
	UFX.LayoutBadges(frame, db)
	E.FrameFX.ColorPrediction(frame.prediction)
	CastX.LayoutCastbar(frame, db)
	LayoutAuras(frame, db, fontSize)
	if frame.happiness then
		frame.happiness:SetSize(math.min(db.height, 24), math.min(db.height, 24))
	end
	if not db.highlight then frame.highlight:Hide() end
	-- A scaled frame keeps its 1-pixel edges one screen pixel wide. The
	-- full form (which also re-applies every hairline in the UI) runs once,
	-- so E:RefreshPixel knows the frame; later refreshes walk this frame
	-- only (the badge hairline is set when the badge is styled).
	if frame.eldoSnapped then
		E:SnapBorders(frame, true)
	else
		frame.eldoSnapped = true
		E:SnapBorders(frame)
	end
	-- Private auras: only the player, target and focus frames carry them.
	if frame.unit == "player" or frame.unit == "target" or frame.unit == "focus" then
		local pa = db.privateAuras
		Blizz.SetPrivateAnchors(frame, frame.unit, pa, frame, pa and pa.anchor)
	end
	-- Frame art (Unit-frame graphics): paint only, last, over the finished layout.
	PaintArt(frame, db)
end

-- Re-anchor after the attached power bar came or went. The frame art goes
-- over the new layout again (a plate's portrait and boxes follow it).
local function Relayout(frame)
	if not frame.db then return end
	LayoutBars(frame)
	PaintArt(frame, frame.db)
end

local function RegisterFrameEvents(frame, unit)
	frame:UnregisterAllEvents()
	if not frame.polled then
		for event in pairs(UNIT_EVENTS) do
			pcall(frame.RegisterUnitEvent, frame, event, unit)
		end
	end
	for event in pairs(GLOBAL_EVENTS) do pcall(frame.RegisterEvent, frame, event) end
	local changes = CHANGE_EVENTS[frame.key]
	local owner = changes and changes.owner
	if type(owner) == "function" then owner = type(unit) == "string" and owner(unit) or nil end
	for _, event in ipairs(changes or {}) do
		if owner and (event == "UNIT_PET" or event == "UNIT_TARGET") then
			pcall(frame.RegisterUnitEvent, frame, event, owner)
		else
			pcall(frame.RegisterEvent, frame, event)
		end
	end
end

-- Texts follow their tags' events (Core/Tags.lua); UpdateAll renders them
-- too, for polled units and a new unit in the frame.
local function BindTexts(frame)
	local unit = frame.unit
	E:BindTag(frame.nameText, frame.tags.name, unit, "UnitFrames")
	E:BindTag(frame.healthText, frame.tags.health, unit, "UnitFrames")
	E:BindTag(frame.powerText, frame.tags.power, unit, "UnitFrames")
	E:BindTag(frame.infoText, frame.tags.info, unit, "UnitFrames")
	for index, text in ipairs(frame.customTexts) do E:BindTag(text, frame.tags[index] or "", unit, "UnitFrames") end
end

local function UnbindTexts(frame)
	E:UnbindTag(frame.nameText)
	E:UnbindTag(frame.healthText)
	E:UnbindTag(frame.powerText)
	E:UnbindTag(frame.infoText)
	for _, text in ipairs(frame.customTexts) do E:UnbindTag(text) end
end

---------------------------------------------------------------------------
-- Fading: the shared visibility rules on the frame (or the
-- holder of a group of frames). Alpha only: a faded frame still takes
-- clicks, and frames show in move mode and test mode. The detached cast
-- bar and power bar follow the player frame.
---------------------------------------------------------------------------
local function FaderTarget(frame)
	local info = INFO[frame.key]
	return info.count and M.holders[frame.key] or frame
end

local function ForceShow(key)
	return function()
		if M.testMode or E:IsMoveMode() then return true end
		local db = M.db and M.db.units[key]
		local fader = db and db.fader
		if not fader then return false end
		if fader.casting then
			for unit, frame in pairs(M.frames) do
				if frame.key == key and (frame.castbar:IsShown() or (unit == "player" and Plain(UnitCastingInfo, "player"))) then return true end
			end
		end
		if fader.focus and Flag(UnitExists, "focus") then return true end
		if fader.resting and Flag(IsResting) then return true end
		return false
	end
end

local function FollowPlayer(_, alpha)
	if M.castHolder then M.castHolder:SetAlpha(alpha) end
	if M.powerHolder then M.powerHolder:SetAlpha(alpha) end
end

local function AttachFader(key)
	local db = M.db.units[key]
	local info = INFO[key]
	local target, watch
	if info.count then
		target = M.holders[key]
		watch = {}
		for index = 1, info.count do watch[index] = M.frames[info.token:format(index)] end
	else
		target = M.frames[key]
		watch = target
	end
	if not target then return end
	E:AttachVisibility(target, db.fader, {
		watch = watch,
		forceShow = ForceShow(key),
		onAlpha = key == "player" and FollowPlayer or nil,
	})
end

local function DetachFader(key)
	local info = INFO[key]
	local target = info.count and M.holders[key] or M.frames[key]
	if target then E:DetachVisibility(target) end
end

---------------------------------------------------------------------------
-- Test frames: every enabled frame with sample values, so they can be
-- placed and styled. Out of combat only; combat ends the test.
---------------------------------------------------------------------------
local function ShowTest(frame, index)
	frame.testing = true
	UnbindTexts(frame)
	UnregisterUnitWatch(frame)
	frame:Show()
	local percent = 100 - index * 12
	frame.health:SetMinMaxValues(0, 100)
	frame.health:SetValue(percent)
	if frame.db.healthColor == "CUSTOM" then
		frame.health:SetStatusBarColor(unpack(frame.db.healthCustomColor))
	elseif frame.key == "player" or frame.key == "pet" or frame.key == "partypet" then
		frame.health:SetStatusBarColor(ReactionColor(REACTION_FRIENDLY))
	else
		frame.health:SetStatusBarColor(ReactionColor(REACTION_HOSTILE))
	end
	frame.power:SetShown((frame.db.powerHeight or 0) > 0)
	frame.power:SetMinMaxValues(0, 100)
	frame.power:SetValue(60)
	local manaR, manaG, manaB = E:GetPowerColor("MANA")
	if manaR then frame.power:SetStatusBarColor(manaR, manaG, manaB) end
	Relayout(frame)
	local info = INFO[frame.key]
	frame.nameText:SetText(info.count and ("%s %d"):format(L[info.title], index) or L[info.title])
	-- A small frame whose name area is too narrow for its title shows the
	-- short form, so the test label is never cut.
	if info.short and frame.nameText:GetUnboundedStringWidth() > frame.nameText:GetWidth() then
		frame.nameText:SetText(L[info.short])
	end
	frame.healthText:SetFormattedText("%d%%", percent)
	frame.powerText:SetText("60")
	-- The info panel's tags read from your own character in test mode.
	local infoOk, infoSample = pcall(E.FormatTag, E, frame.tags.info or "", "player", "UnitFrames")
	frame.infoText:SetText(infoOk and type(infoSample) == "string" and not E:IsSecret(infoSample) and infoSample or "")
	for listIndex, text in ipairs(frame.customTexts) do
		text:SetText((frame.tags[listIndex] or "") ~= "" and L["Text %d"]:format(listIndex) or "")
	end
	for _, key in ipairs({ "other", "mine", "absorb", "healAbsorb" }) do frame.prediction[key]:Hide() end
	frame.prediction.overAbsorb:Hide()
	for key, texture in pairs(frame.indicators) do
		if key ~= "raidMarker" then texture:Hide() end
	end
	frame.threatGate:Clear()
	frame.offTankGate:Clear()
	frame.lowHealthGate:Clear()
	frame.lowPowerGate:Clear()
	frame.art:SetAlpha(1)
	E.FrameFX.Pulse(frame.indicators.status, false)
	-- The portrait shows the player's own model (or picture), the badges
	-- the player's level and class.
	UpdatePortrait(frame, true)
	UFX.TestBadges(frame)
	if frame.glowing then
		frame.glowing = nil
		E:HideGlow(frame)
	end
	for _, aura in pairs(frame.auras) do aura.holder:Hide() end
	local castbar = frame.castbar
	if castbar.enabled and index == 1 then
		castbar.duration, castbar.endTime, castbar.ended = nil, nil, nil
		castbar:SetMinMaxValues(0, 1)
		castbar:SetValue(0.6)
		ColorCast(castbar, false, frame.unit)
		castbar.text:SetText(L["Sample cast"])
		castbar.time:SetText(castbar.showTime and "1.2" or "")
		CastX.SetCastTarget(castbar, nil)
		castbar.icon:SetTexture(136243)
		castbar.latency:Hide()
		HideTicks(castbar)
		CastX.HideCastGlow(castbar)
		castbar.gate:SetAlpha(1)
		castbar:SetAlpha(1)
		castbar.flash:SetAlpha(0)
		castbar.marker:Hide()
		castbar:Show()
	end
end

local function EndTest(frame)
	frame.testing = nil
	frame.castbar:Hide()
end

function M:SetTestMode(state)
	if InCombatLockdown() then
		E:Print(L["Test frames can't be shown in combat."])
		return
	end
	self.testMode = state and true or nil
	for unit, frame in pairs(self.frames) do
		local db = self.db.units[frame.key]
		if state and db.enabled then
			local index = tonumber(unit:match("(%d+)")) or 1
			ShowTest(frame, index)
		elseif frame.testing then
			EndTest(frame)
		end
	end
	if state then
		E:RefreshVisibility()
	else
		self:Build()
		self:Activate()
	end
end

E:RegisterEvent("PLAYER_REGEN_DISABLED", function()
	if M.testMode then
		M.testMode = nil
		E:RunOutOfCombat(function() M:SetTestMode(false) end)
	end
end, M)

---------------------------------------------------------------------------
-- Old settings: the single aura block (older versions) becomes the buffs and
-- debuffs blocks; extra texts with a raw tag become custom tag texts.
---------------------------------------------------------------------------
local OLD_AURAS = {
	default = { enabled = false, size = 26, perRow = 8, max = 16, filter = "HARMFUL|PLAYER", anchor = "TOP", durationText = true, dispelBorder = true },
	target = { enabled = true, perRow = 9, max = 18 },
	boss = { size = 22, perRow = 6, max = 6 },
}
local OLD_FILTERS = {
	["HARMFUL|PLAYER"] = { "debuffs", "mine" },
	HARMFUL = { "debuffs", "all" },
	["HARMFUL|RAID"] = { "debuffs", "dispellable" },
	HELPFUL = { "buffs", "all" },
	["HELPFUL|PLAYER"] = { "buffs", "mine" },
	["HELPFUL|RAID"] = { "buffs", "custom" },
}

local function MigrateAuras(key, db)
	local old = db.auras
	if type(old) ~= "table" then return end
	db.auras = nil
	local merged = CopyTable(OLD_AURAS.default)
	for field, value in pairs(OLD_AURAS[key] or {}) do merged[field] = value end
	for field, value in pairs(old) do merged[field] = value end
	local function Apply(block, preset)
		block.enabled = merged.enabled and true or false
		block.size, block.perRow, block.max = merged.size, merged.perRow, merged.max
		block.anchor = merged.anchor == "BOTTOM" and "BOTTOM" or "TOP"
		block.growthY = block.anchor == "BOTTOM" and "DOWN" or "UP"
		block.duration = merged.durationText == false and "SWIPEONLY" or "SWIPE"
		block.dispelBorder = merged.dispelBorder and true or false
		block.filter.preset = preset
		if preset == "custom" then
			block.filter.groups[1].enabled = true
			block.filter.groups[1].raid = true
		end
	end
	if merged.filter == "BOTH" then
		Apply(db.debuffs, "all")
		Apply(db.buffs, "all")
		db.buffs.attachTo = "DEBUFFS"
		db.debuffs.attachTo = "FRAME"
		return
	end
	local map = OLD_FILTERS[merged.filter] or OLD_FILTERS["HARMFUL|PLAYER"]
	local which, other = map[1], OTHER[map[1]]
	Apply(db[which], map[2])
	db[which].attachTo = "FRAME"
	db[other].enabled = false
end

local function MigrateTexts(db)
	for _, text in ipairs(db.texts or {}) do
		if type(text) == "table" and text.tag ~= nil then
			text.custom = text.tag
			text.preset = "custom"
			text.tag = nil
		end
	end
end

-- Older versions: the tapped and offline colors lived here (now General >
-- Colors > Status), the threat border was an icon tick and the important
-- cast glow a cast bar tick (both now Effects). Only a value the player
-- changed is carried over: saved settings keep only what differs from the
-- old defaults.
UFX.OLD_STATUS = { tapped = "tapped", disconnected = "offline" }
function UFX.MigrateEffects(db)
	if type(db.effects) ~= "table" then db.effects = {} end
	local ind, cast = db.indicators, db.castbar
	if type(ind) == "table" and type(ind.threat) == "boolean" then
		db.effects.threat = type(db.effects.threat) == "table" and db.effects.threat or {}
		db.effects.threat.enabled = ind.threat
		ind.threat = nil
	end
	if type(cast) == "table" and type(cast.importantGlow) == "boolean" then
		db.effects.importantGlow = type(db.effects.importantGlow) == "table" and db.effects.importantGlow or {}
		db.effects.importantGlow.enabled = cast.importantGlow
		cast.importantGlow = nil
	end
end

local function Migrate()
	-- The old "Copy settings from" picker kept a value until the next
	-- refresh; the copy is a row with a preview now.
	if rawget(M.db, "copyFrom") ~= nil then M.db.copyFrom = nil end
	local old = rawget(M.db, "colors")
	if type(old) == "table" then
		local status = E.db.general.colors.status
		for from, to in pairs(UFX.OLD_STATUS) do
			if type(old[from]) == "table" and type(status[to]) ~= "table" then status[to] = CopyTable(old[from]) end
		end
		M.db.colors = nil
		E:UpdateColors()
	end
	-- 0.7.1000: the small Classic frames' names got a size of their own
	-- (Name size). A profile that applied the Classic frames earlier takes
	-- the style's sizes once; after that the setting is the player's.
	if not rawget(M.db, "smallNameSize") then
		M.db.smallNameSize = true
		local classic
		for _, entry in ipairs(E.styles and E.styles.UnitFrames or {}) do
			if entry.key == "Classic" then classic = entry.settings end
		end
		if M.db.style == "Classic" and classic then
			for key, unit in pairs(classic.units or {}) do
				local db = M.db.units[key]
				if unit.nameSize and type(db) == "table" and (db.nameSize or 0) == 0 then db.nameSize = unit.nameSize end
			end
		end
	end
	for key, db in pairs(M.db.units) do
		if type(db) == "table" and INFO[key] then
			MigrateAuras(key, db)
			MigrateTexts(db)
			UFX.MigrateEffects(db)
			E:NormalizeUnitFX(db.effects, UFX.Consumer(key))
		end
	end
end
M.Migrate = Migrate

-- "Copy settings from" (E:CopySettingsOptions on the unit tabs): another
-- unit's settings onto the edited unit, keeping its on/off switch. Only
-- the player cast bar can be detached and only the player power bar.
function M.AfterCopy(_, _, to)
	local target = type(to) == "string" and to:match("^units%.(.+)$")
	local db = target and M.db.units[target]
	if type(db) ~= "table" or target == "player" then return end
	if type(db.castbar) == "table" then db.castbar.detached = false end
	if db.powerStyle == "DETACHED" then db.powerStyle = "INSET" end
end

---------------------------------------------------------------------------
-- Build and activate
---------------------------------------------------------------------------
local function ToName(key)
	return "EldoUI_" .. key:gsub("^%l", string.upper) .. "Frame"
end

function M:Build()
	local units = self.db.units
	-- The player cast bar has its own mover: EldoUI's detached bar and
	-- Blizzard's cast bar (when moved) sit on it.
	if not self.castHolder then
		local holder = CreateFrame("Frame", "EldoUI_PlayerCastbarHolder", UIParent)
		holder:SetSize(units.player.castbar.width, units.player.castbar.height)
		self.castHolder = holder
		E:CreateMover(holder, "EldoUI_PlayerCastbar", L["Player Cast Bar"], { "CENTER", "UIParent", "CENTER", 0, -327 },
			{ sizeKeys = { width = { key = "units.player.castbar.width", min = 60, max = 600 },
				height = { key = "units.player.castbar.height", min = 8, max = 40 } } })
	end
	for _, key in ipairs(UNITS) do
		local db = units[key]
		local info = INFO[key]
		if info.count then
			local holder = self.holders[key]
			if not holder then
				holder = CreateFrame("Frame", "EldoUI_" .. key:gsub("^%l", string.upper) .. "Holder", UIParent)
				self.holders[key] = holder
				for index = 1, info.count do
					local unit = info.token:format(index)
					self.frames[unit] = CreateUnitFrame(unit, "EldoUI_" .. key:gsub("^%l", string.upper) .. index, holder)
					self.frames[unit].Relayout = Relayout
				end
				holder:SetSize(db.width, db.height)
				-- The group's height follows its count, so only the width matches.
				E:CreateMover(holder, info.mover, L[info.title], info.point, { enabledPath = { "units", key, "enabled" }, sample = info.sample,
					sizeKeys = { width = { key = "units." .. key .. ".width", min = 60, max = 600 } } })
			end
			local spacing = db.spacing or 12
			holder:SetSize(db.width * (db.scale or 1), (db.height * info.count + spacing * (info.count - 1)) * (db.scale or 1))
			holder:SetFrameStrata(UnitStrata(db))
			for index = 1, info.count do
				local frame = self.frames[info.token:format(index)]
				StyleFrame(frame, db, self.db.fontSize)
				frame:ClearAllPoints()
				local offset = (index - 1) * (db.height + spacing)
				if db.growth == "UP" then
					frame:SetPoint("BOTTOM", holder, "BOTTOM", 0, offset)
				else
					frame:SetPoint("TOP", holder, "TOP", 0, -offset)
				end
			end
		else
			local frame = self.frames[key]
			if not frame then
				frame = CreateUnitFrame(key, ToName(key))
				frame.Relayout = Relayout
				self.frames[key] = frame
				StyleFrame(frame, db, self.db.fontSize)
				E:CreateMover(frame, info.mover, L[info.title], info.point, { enabledPath = { "units", key, "enabled" }, sample = info.sample,
					sizeKeys = { width = { key = "units." .. key .. ".width", min = 60, max = 600 },
						height = { key = "units." .. key .. ".height", min = 14, max = 120 } } })
			else
				StyleFrame(frame, db, self.db.fontSize)
			end
		end
	end
	self:PlaceTopNeighbors()
end

-- Never two frames for one unit (design decision): an EldoUI frame for
-- a unit Blizzard draws too shows only while Blizzard's is out of sight
-- (its element replaced or hidden). Units Blizzard has no frame for
-- (pet target, party pets and targets) are left alone.
local function Duplicates(key)
	return key ~= "pettarget" and INFO[key] and INFO[key].element or nil
end

local function OwnFrameAllowed(key)
	if key == "player" and E:StandsBack(M, "player") then return false end
	local element = Duplicates(key)
	return not element or Blizz.OutOfSight(element)
end
M.OwnFrameAllowed = OwnFrameAllowed

-- A frame placed on top of a unit frame (the target of target above the
-- target) keeps its gap above the frame's name when the name sits above
-- the bars: how far the name reaches above the frame's box, in UIParent
-- units. The name's line is measured from its font size, so an empty name
-- (no target yet) reaches as high as a written one.
function M:TopReach(key)
	local info, frame = INFO[key], self.frames[key]
	local db = frame and frame.db
	if not (self.active and info and not info.count and db and db.enabled and db.nameText == "TOP") then return 0 end
	if not OwnFrameAllowed(key) then return 0 end
	local mover, name = E.movers[info.mover], frame.nameText
	if not (mover and name and name:IsShown()) then return 0 end
	local _, size = name:GetFont()
	local bottom, top = name:GetBottom(), mover:GetTop()
	if E:IsSecret(size) or E:IsSecret(bottom) or E:IsSecret(top) then return 0 end
	if type(size) ~= "number" or type(bottom) ~= "number" or type(top) ~= "number" then return 0 end
	local root = UIParent:GetEffectiveScale()
	local reach = (bottom + size) * name:GetEffectiveScale() / root - top * mover:GetEffectiveScale() / root
	if reach <= 0 then return 0 end
	return self:TopRoom(info, mover, reach, root)
end

-- Blizzard's totem bar, when Action Bars moves it, can sit right above a
-- frame placed on top of a unit frame (the target of target): the frame
-- then rises only as far as the bar leaves room for, 4 units under it, so
-- it never covers the totem buttons. Measured from where the frame stands
-- without the lift.
function M:TopRoom(info, mover, reach, root)
	local bar = E.movers.EldoUI_TotemBar
	if not (bar and bar:IsShown()) then return reach end
	local barScale = bar:GetEffectiveScale() / root
	local barLeft, barRight, barBottom = bar:GetLeft(), bar:GetRight(), bar:GetBottom()
	local top = mover:GetTop()
	if E:IsSecret(barLeft) or E:IsSecret(barRight) or E:IsSecret(barBottom) or E:IsSecret(top) then return reach end
	if type(barLeft) ~= "number" or type(barRight) ~= "number" or type(barBottom) ~= "number" or type(top) ~= "number" then return reach end
	barLeft, barRight, barBottom = barLeft * barScale, barRight * barScale, barBottom * barScale
	top = top * mover:GetEffectiveScale() / root
	local anchor = info.mover .. "Mover"
	for name, other in pairs(E.movers) do
		local point = other ~= bar and E:SavedMoverPosition(name, true) == nil and E:GetLayoutPoint(name)
		local own, relative = point and tostring(point[1] or ""), point and tostring(point[3] or point[1] or "")
		if point and point[2] == anchor and own:find("BOTTOM") and relative:find("TOP") and other:IsShown() then
			local scale = other:GetEffectiveScale() / root
			local left, right, height = other:GetLeft(), other:GetRight(), other:GetHeight()
			if type(left) == "number" and type(right) == "number" and type(height) == "number" and not E:IsSecret(left)
				and not E:IsSecret(right) and not E:IsSecret(height) then
				left, right, height = left * scale, right * scale, height * scale
				local unlifted = top + (tonumber(point[5]) or 0) + height
				if math.min(right, barRight) - math.max(left, barLeft) > 1 and barBottom >= unlifted then
					reach = math.min(reach, math.max(0, barBottom - 4 - unlifted))
				end
			end
		end
	end
	return reach
end

M.topReach = {}   -- unit key -> the reach its neighbors were placed with
M.topAnchors = {} -- unit frame mover name -> unit key
for key, info in pairs(INFO) do
	if not info.count then
		M.topAnchors[info.mover .. "Mover"] = key
		E:RegisterMoverTopReach(info.mover .. "Mover", function() return M:TopReach(key) end)
	end
end

-- A layout, a setup or a profile places every frame again, sometimes
-- before a unit frame has drawn its name: on the next frame, the frames on
-- top of a unit frame get the lift its name has then.
if E.RefreshMovers then
	hooksecurefunc(E, "RefreshMovers", function()
		if M.topPending or not M.active then return end
		M.topPending = true
		C_Timer.After(0, function()
			M.topPending = false
			if M.active then M:PlaceTopNeighbors() end
		end)
	end)
end

-- A frame placed on top of a unit frame whose own spot is no longer the
-- point it would get now (its vertical offset differs).
local function StandsApart(mover, point)
	local own, relative = tostring(point[1] or ""), tostring(point[3] or point[1] or "")
	if not (own:find("BOTTOM") and relative:find("TOP")) then return false end
	if mover:GetNumPoints() ~= 1 then return false end
	local _, anchor, _, _, y = mover:GetPoint(1)
	if not (anchor and anchor.GetName and anchor:GetName() == point[2]) then return false end
	if E:IsSecret(y) or type(y) ~= "number" then return false end
	return math.abs(y - (tonumber(point[5]) or 0)) > 0.5
end

-- The frames placed on top of a unit frame follow when its name moved up
-- or down (name position, font size, frame art); a dragged frame stays.
function M:PlaceTopNeighbors()
	local changed
	for key, info in pairs(INFO) do
		if not info.count then
			local reach = math.floor(self:TopReach(key) + 0.5)
			if self.topReach[key] ~= reach then
				self.topReach[key] = reach
				changed = changed or {}
				changed[info.mover .. "Mover"] = true
			end
		end
	end
	for name, mover in pairs(E.movers) do
		if E:SavedMoverPosition(name, true) == nil then
			local point = E:GetMoverDefaultPoint(name)
			if type(point) == "table" and type(point[2]) == "string" then
				if changed and changed[point[2]] then
					E:ApplyMover(name)
				elseif self.topReach[self.topAnchors[point[2]] or ""] and StandsApart(mover, point) then
					-- Placed while the name had another height (a layout
					-- applied before the frame drew its name): place it again.
					E:ApplyMover(name)
				end
			end
		end
	end
end

-- What OwnFrameAllowed answered for every element at the last refresh, so
-- a switch change rebuilds the frames only when the answer changed.
local function OwnFrameSignature()
	local parts = {}
	for _, id in ipairs({ "player-frame", "target-focus-frames", "pet-frame", "boss-frames", "player-cast-bar" }) do
		parts[#parts + 1] = Blizz.OutOfSight(id) and "1" or "0"
	end
	return table.concat(parts)
end

-- Compound units (target of target, focus target, party targets) have no
-- events of their own: the visible ones refresh a few times a second on
-- the shared ticker, which stops while none of them shows.
local POLL_TICK, POLL_PERIOD = "UnitFrames:poll", 0.25
local function PolledShown()
	for _, frame in pairs(M.frames) do
		if frame.polled and not frame.testing and frame:IsVisible() then return true end
	end
	return false
end

local function Poll()
	local any = false
	if M.active then
		for _, frame in pairs(M.frames) do
			if frame.polled and not frame.testing and frame:IsVisible() then
				any = true
				UpdateAll(frame)
			end
		end
	end
	if not any then E.Ticker:Unsubscribe(POLL_TICK) end
end

-- Starts the poll when a polled frame shows (and none ran).
function UFX.WatchPolled()
	if M.active and PolledShown() and not E.Ticker:IsSubscribed(POLL_TICK) then
		E.Ticker:Subscribe(POLL_TICK, POLL_PERIOD, Poll, M)
	end
end

local function EnabledFor(units, frame)
	local db = units[frame.key]
	return db and db.enabled and OwnFrameAllowed(frame.key)
end


do
-- A part choice releases only the player's own presentation. Other units
-- keep their watches, tags, cast updates, and visibility rules.
local partInactive = setmetatable({}, { __mode = "k" })
local partRequest = 0

local function ReleasePlayer(frame, check)
	partInactive[frame] = true
	local bar = frame.castbar
	bar:Hide()
	check()
	CastX.CastHidden(bar)
	check()
	bar.enabled = false
	bar.gate:Hide()
	check()
	CastX.HideCastGlow(bar)
	check()
	HideTicks(bar)
	check()
	HidePowerCost(frame)
	check()
	if bar.flash.anim then
		bar.flash.anim:Stop()
		check()
	end
	bar.flash:SetAlpha(0)
	check()
	if M.castHolder then M.castHolder:Hide(); check() end
	if M.powerHolder then M.powerHolder:Hide(); check() end
	DetachFader("player")
	check()
	E.Portrait:Release(frame)
	check()
	for _, gate in ipairs({ frame.threatGate, frame.offTankGate, frame.lowHealthGate, frame.lowPowerGate }) do
		gate:Clear()
		check()
	end
end

local function PrivateRemovalGuard(frame, check)
	local array = frame.privateAnchors
	if not array then return function() check(); return true end end
	local slots = {}
	for index, entry in ipairs(array) do
		assert(not E:IsSecret(entry.id), "Private registration token unavailable")
		slots[index] = { entry = entry, holder = entry.holder, id = entry.id,
			parent = entry.holder:GetParent(), shown = entry.holder:IsShown() }
	end
	return function(phase, entry)
		check()
		assert(frame.privateAnchors == array and #array == #slots, "Private anchor ownership changed")
		for index, slot in ipairs(slots) do
			assert(array[index] == slot.entry and slot.entry.holder == slot.holder and not E:IsSecret(slot.entry.id)
				and slot.entry.id == slot.id and slot.holder:GetParent() == slot.parent
				and slot.holder:IsShown() == slot.shown, "Private anchor ownership changed")
		end
		for _, slot in ipairs(slots) do
			if slot.entry == entry then
				if phase == "removed" then slot.id = nil end
				if phase == "hide" then slot.shown = false end
			end
		end
		return true
	end
end

local function AuraReleaseLease(frame, check)
	local array, slots = frame.auras, {}
	for key, entry in pairs(array or {}) do
		slots[key] = { entry = entry, holder = entry.holder, container = entry.container }
	end
	local function Matches()
		if frame.auras ~= array then return false end
		for key, entry in pairs(array or {}) do
			local slot = slots[key]
			if not slot or slot.entry ~= entry or slot.holder ~= entry.holder or slot.container ~= entry.container then return false end
		end
		for key, slot in pairs(slots) do if array[key] ~= slot.entry then return false end end
		return true
	end
	local function Release()
		for _, slot in pairs(slots) do
			check()
			if slot.container then
				E.AuraWidget.Release(slot.container)
				check()
				slot.entry.container, slot.entry.signature = nil, nil
				slot.container = nil
				check()
			end
		end
	end
	return Matches, Release
end

local function ActivateFrame(frame, unit, units, guard)
	local auraMatches, releaseAuras
	local function Check()
		if guard and not guard() then error("Player part ownership changed", 0) end
		if auraMatches and not auraMatches() then error("Player aura ownership changed", 0) end
	end
	local playerPart = frame.key == "player" and (guard or partInactive[frame] or E:StandsBack(M, "player"))
	if playerPart and not EnabledFor(units, frame) then auraMatches, releaseAuras = AuraReleaseLease(frame, Check) end
	Check()
	local privateGuard = playerPart and PrivateRemovalGuard(frame, Check)
	-- Frames in test mode are left alone until the test ends.
	if not frame.testing then
		if EnabledFor(units, frame) then
			if frame.key == "player" and partInactive[frame] then
				StyleFrame(frame, units.player, M.db.fontSize)
				Check()
				frame.castbar.gate:Show()
				Check()
				partInactive[frame] = nil
			end
			RegisterFrameEvents(frame, unit)
			if unit == "player" then
				UnregisterUnitWatch(frame)
				frame:Show()
				Check()
			else
				RegisterUnitWatch(frame)
			end
			BindTexts(frame)
			Check()
			UpdateAll(frame)
			Check()
		else
			if playerPart then ReleasePlayer(frame, Check) end
			UnregisterUnitWatch(frame)
			frame:UnregisterAllEvents()
			frame:Hide()
			Check()
			UnbindTexts(frame)
			RemovePrivateAnchors(frame, privateGuard)
			if releaseAuras then releaseAuras() else ReleaseAuras(frame) end
			if frame.glowing then
				frame.glowing = nil
				E:HideGlow(frame)
			end
		end
	end
end

local function PlayerPartGuard(frame, request)
	local desired = E:StandsBack(M, "player")
	local rootDB, profileName, modules = E.db, E.profileName, E.db.modules
	local handler = M.OnStandBack
	local profile, frames, units = M.db, M.frames, M.db.units
	local settings, bar, castHolder, powerHolder = units.player, frame.castbar, M.castHolder, M.powerHolder
	local enabled, allowed = settings.enabled, OwnFrameAllowed("player")
	local parent, gateParent = frame:GetParent(), bar.gate:GetParent()
	local hide, barHide = frame.Hide, bar.Hide
	local function Valid()
		return partRequest == request and E:StandsBack(M, "player") == desired
			and E.db == rootDB and E.profileName == profileName and rootDB.modules == modules and modules.UnitFrames == profile
			and M.OnStandBack == handler and E.modules.UnitFrames == M and M.active and M.db == profile and M.frames == frames
			and profile.units == units and units.player == settings and frames.player == frame
			and settings.enabled == enabled and OwnFrameAllowed("player") == allowed
			and frame.castbar == bar and M.castHolder == castHolder and M.powerHolder == powerHolder
			and frame:GetParent() == parent and bar.gate:GetParent() == gateParent and frame.Hide == hide and bar.Hide == barHide
	end
	return Valid
end

function M:Activate()
	local units = self.db.units
	for unit, frame in pairs(self.frames) do
		local guard
		if frame.key == "player" and (partInactive[frame] or E:StandsBack(M, "player")) then
			partRequest = partRequest + 1
			guard = PlayerPartGuard(frame, partRequest)
		end
		ActivateFrame(frame, unit, units, guard)
	end
	for _, key in ipairs(UNITS) do
		if units[key].enabled and (key ~= "player" or not E:StandsBack(M, "player")) then AttachFader(key) else DetachFader(key) end
	end
	-- The detached cast and power bars follow the player frame's fading.
	if not units.player.enabled then FollowPlayer(nil, 1) end
	UFX.WatchPolled()
	-- The detached player cast bar on the Cooldown Manager: its width and
	-- the pieces stacked on it change; the cooldown stack's watcher calls back.
	CastX.RegisterCooldownStack()
end

function M:OnStandBack(feature)
	if feature ~= "player" then return end
	partRequest = partRequest + 1
	if not self.active then return end
	local frame = self.frames and self.frames.player
	if not frame then return end
	local valid, units = PlayerPartGuard(frame, partRequest), self.db.units
	E:RunOutOfCombat(function()
		if not valid() then return end
		ActivateFrame(frame, "player", units, valid)
		if not valid() then return end
		if EnabledFor(units, frame) then AttachFader("player") else DetachFader("player") end
	end, "UnitFrames:player-part")
end
end

-- Spell lists changed (General > Aura filters): rebuild the containers.
E:OnAuraFiltersChanged(M, function()
	if M.active then
		E:RunOutOfCombat(function()
			-- The module may have been switched off before combat ended.
			if not M.active then return end
			for _, frame in pairs(M.frames) do
				for _, aura in pairs(frame.auras or {}) do aura.signature = "changed" end
			end
			M:Build()
			M:Activate()
		end)
	end
end)

---------------------------------------------------------------------------
-- Blizzard's own frames: one handler per element.
---------------------------------------------------------------------------
local ELEMENT_FRAMES = {
	["player-frame"] = function() return { { PlayerFrame, "EldoUI_Player" } } end,
	["target-focus-frames"] = function()
		return { { TargetFrame, "EldoUI_Target" }, { FocusFrame, "EldoUI_Focus" },
			{ _G.TargetFrameToT, "EldoUI_ToT", true }, { _G.FocusFrameToT, "EldoUI_FocusTarget", true } }
	end,
	["pet-frame"] = function() return { { PetFrame, "EldoUI_Pet" } } end,
	["boss-frames"] = function() return { { BossTargetFrameContainer, "EldoUI_Boss" } } end,
	["player-cast-bar"] = function() return { { PlayerCastingBarFrame, "EldoUI_PlayerCastbar" } } end,
}

local function BlizzardScale(id)
	local scale = M.db.blizzard.scale
	return scale and scale[id] or 1
end

-- The skin of an element is recorded (Core/Skin.lua, E:SkinRecord): every
-- texture, color, font and alpha it changes on Blizzard's frames goes back
-- when the element or the module is switched off, without a reload.
local function SkinKey(id) return "UnitFrames:" .. id end

function Blizz.SkinActive(id)
	return M.active and E:SkinRecordState(SkinKey(id)) ~= "off"
end

local function Skin(id, root, fn, ...)
	local key = SkinKey(id)
	if E:SkinRecordState(key) == "off" then E:SkinRecordOn(key) end
	E:SkinRecord(key, root, fn, ...)
end

-- Replace stops a hidden frame's events (it is EldoUI's frame now); Hide
-- alone keeps them, so the frame can come straight back.
local function KeepEvents(id)
	return id == "player-cast-bar" or not E:BlizzardAllowed(id, "replace")
end

function M:ApplyBlizzard(id)
	local list = ELEMENT_FRAMES[id] and ELEMENT_FRAMES[id]() or {}
	local flat = self.db.blizzard.flatArt
	for _, entry in ipairs(list) do
		local frame, moverName, noMove = entry[1], entry[2], entry[3]
		if Usable(frame) then
			if E:BlizzardHidden(id) then
				Blizz.Hide(id, frame, KeepEvents(id))
			else
				if E:BlizzardAllowed(id, "skin") then
					if id == "player-cast-bar" then
						Skin(id, frame, Blizz.SkinCastBar, id, frame)
					elseif id == "boss-frames" then
						for index = 1, 5 do
							local boss = _G["Boss" .. index .. "TargetFrame"]
							if Usable(boss) then Skin(id, boss, Blizz.SkinUnitFrame, id, boss, flat) end
						end
					else
						Skin(id, frame, Blizz.SkinUnitFrame, id, frame, flat)
					end
				end
				if E:BlizzardAllowed(id, "move") and not noMove then
					Blizz.Place(id, frame, moverName, BlizzardScale(id))
				end
			end
		end
	end
	-- Extras per element.
	if id == "target-focus-frames" then
		for _, bar in ipairs({ _G.TargetFrameSpellBar, _G.FocusFrameSpellBar }) do
			if Usable(bar) then
				if self.db.blizzard.targetCastbar == "HIDDEN" and not E:BlizzardHidden(id) then
					Blizz.Hide(id, bar, true)
				elseif E:BlizzardAllowed(id, "skin") then
					Skin(id, bar, Blizz.SkinCastBar, id, bar)
				end
			end
		end
	elseif id == "pet-frame" then
		if Usable(PetCastingBarFrame) then
			if E:BlizzardHidden(id) or not self.db.blizzard.petCastbar then
				Blizz.Hide(id, PetCastingBarFrame, true)
			elseif E:BlizzardAllowed(id, "skin") then
				Skin(id, PetCastingBarFrame, Blizz.SkinCastBar, id, PetCastingBarFrame)
			end
		end
	elseif id == "boss-frames" and E:BlizzardAllowed(id, "skin") and not E:BlizzardHidden(id) then
		for index = 1, 5 do
			local bar = _G["Boss" .. index .. "TargetFrameSpellBar"]
			if Usable(bar) then Skin(id, bar, Blizz.SkinCastBar, id, bar) end
		end
	elseif id == "player-cast-bar" and E:BlizzardHidden(id) and Usable(OverlayPlayerCastingBarFrame) then
		-- The overlay bar only shows with Blizzard's cast bar locked to the
		-- personal resource display; it goes with the player cast bar.
		Blizz.Hide(id, OverlayPlayerCastingBarFrame, true)
	end
end

-- Private auras element: anchors on EldoUI frames (improve) and the
-- private boss emote text on an EldoUI mover (move).
function M:ApplyPrivateAuras()
	if self.active then
		for _, key in ipairs({ "player", "target", "focus" }) do
			local frame = self.frames[key]
			if frame and frame.db and EnabledFor(self.db.units, frame) then
				Blizz.SetPrivateAnchors(frame, key, frame.db.privateAuras, frame, frame.db.privateAuras.anchor)
			end
		end
	end
	local holder = self.warningHolder
	local moveWarning = E:BlizzardAllowed("private-auras", "move") and self.db.blizzard.privateWarning
	if not holder and moveWarning then
		holder = CreateFrame("Frame", "EldoUI_PrivateWarningHolder", UIParent)
		holder:SetSize(400, 40)
		self.warningHolder = holder
		E:CreateMover(holder, "EldoUI_BossEmote", L["Private Boss Warnings"], { "TOP", "UIParent", "TOP", 0, -300 }, { sample = { kind = "text" } })
	end
	if C_UnitAuras and C_UnitAuras.SetPrivateWarningTextAnchor then
		if moveWarning and holder then
			pcall(C_UnitAuras.SetPrivateWarningTextAnchor, holder,
				{ point = "TOP", relativeTo = holder, relativePoint = "TOP", offsetX = 0, offsetY = 0 })
			self.warningMoved = true
		elseif self.warningMoved then
			self:RestorePrivateAuras()
		end
	end
end

function M:RestorePrivateAuras()
	for _, key in ipairs({ "player", "target", "focus" }) do
		local frame = self.frames[key]
		if frame then RemovePrivateAnchors(frame) end
	end
	if self.warningMoved and C_UnitAuras and C_UnitAuras.SetPrivateWarningTextAnchor and Usable(PrivateRaidBossEmoteFrameAnchor) then
		pcall(C_UnitAuras.SetPrivateWarningTextAnchor, PrivateRaidBossEmoteFrameAnchor,
			{ point = "TOP", relativeTo = PrivateRaidBossEmoteFrameAnchor, relativePoint = "TOP", offsetX = 0, offsetY = 0 })
	end
	self.warningMoved = nil
end

-- Element `id` back to Blizzard's own frames, by what was recorded: the
-- skin's changes go back, the flat art comes off, the frames leave
-- EldoUI's movers (Edit Mode positions apply again) and hidden frames come
-- back. Only a frame Replace took the events from waits for a reload
-- (the handlers' `reload` flag says so).
local function Restore(id)
	local list = ELEMENT_FRAMES[id] and ELEMENT_FRAMES[id]() or {}
	for _, entry in ipairs(list) do
		if entry[1] then Blizz.Unplace(entry[1]) end
		if id == "boss-frames" then
			for index = 1, 5 do Blizz.FlatArt(_G["Boss" .. index .. "TargetFrame"], false) end
		elseif entry[1] then
			Blizz.FlatArt(entry[1], false)
		end
	end
	E:SkinRecordOff(SkinKey(id))
	Blizz.Unhide(id)
end
M.RestoreBlizzard = Restore

-- v0.5.0 hid Blizzard's frame for every enabled EldoUI unit when
-- hideBlizzard was on; keep that after the update to the element switches.
local function Legacy(...)
	local keys = { ... }
	return function()
		local db = M.db
		if not db or not db.enabled or not db.hideBlizzard then return false end
		for _, key in ipairs(keys) do
			local unit = db.units[key]
			if unit and unit.enabled then return true end
		end
		return false
	end
end

local HANDLERS = {
	["player-frame"] = Legacy("player"),
	["target-focus-frames"] = Legacy("target", "focus"),
	["pet-frame"] = Legacy("pet"),
	["boss-frames"] = Legacy("boss"),
	["player-cast-bar"] = function()
		local db = M.db
		return db and db.enabled and db.hideBlizzard and db.units.player.enabled and db.units.player.castbar.enabled or false
	end,
}

-- A switch that changes which side draws a unit rebuilds the frames.
local function Reconcile()
	if M.active and M.ownSignature ~= OwnFrameSignature() then M:OnProfileChanged() end
end

for id, legacy in pairs(HANDLERS) do
	E:RegisterBlizzardHandler(id, {
		owner = "UnitFrames",
		apply = function() M:ApplyBlizzard(id); Reconcile() end,
		undo = function() Restore(id); Reconcile() end,
		reload = { replace = true },
		install = { replace = true, skin = false, move = false, improve = true },
		legacy = legacy,
		refreshModule = false,
	})
end

E:RegisterBlizzardHandler("private-auras", {
	owner = "UnitFrames",
	apply = function() M:ApplyPrivateAuras() end,
	undo = function() M:RestorePrivateAuras() end,
	install = { improve = true, move = true },
	legacy = function() return M.db and M.db.enabled and M.db.units.player.enabled end,
	refreshModule = false,
})

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- "All frames": one portrait style for every unit frame with a
-- portrait and for the party frames (Group Frames). The select shows the
-- shared style, or Mixed while they differ; Mixed is a state, not a pick.
---------------------------------------------------------------------------
function UFX.PortraitOwners()
	local list = {}
	for _, key in ipairs(UNITS) do
		local db = M.db.units[key]
		if db and db.portrait ~= "none" then list[#list + 1] = { db = db, field = "portraitStyle" } end
	end
	local gf = E:GetModule("GroupFrames")
	local party = gf and gf.db and gf.db.party
	if party and party.portrait and party.portrait ~= "NONE" then list[#list + 1] = { db = party, field = "portrait", group = gf } end
	return list
end

function UFX.SharedPortrait(list)
	return E.FrameFX.Shared(list, function(owner) return owner.db[owner.field] end) or "MIXED"
end

-- A new pick (it differs from the last sync) is written to every owner;
-- then the select follows the shared style again.
function UFX.SyncAllFrames(apply)
	local all = M.db and M.db.allFrames
	if type(all) ~= "table" then return end
	local list = UFX.PortraitOwners()
	local pick = all.portraitStyle
	local group
	if apply and pick ~= "MIXED" and pick ~= all.synced then
		for _, owner in ipairs(list) do
			owner.db[owner.field] = pick
			group = group or owner.group
		end
	end
	all.portraitStyle = UFX.SharedPortrait(list)
	all.synced = all.portraitStyle
	if group and group.active and group.OnProfileChanged then group:OnProfileChanged() end
end
M.SyncAllFrames = UFX.SyncAllFrames

local function Refresh(self)
	if not self.active then return end
	Migrate()
	UFX.SyncAllFrames(true)
	if self.testMode then
		for _, frame in pairs(self.frames) do
			if frame.testing then EndTest(frame) end
		end
	end
	self.ownSignature = OwnFrameSignature()
	self:Build()
	self:Activate()
	for id in pairs(HANDLERS) do
		if E:BlizzardAllowed(id) then self:ApplyBlizzard(id) end
	end
	self:ApplyPrivateAuras()
	if self.testMode then self:SetTestMode(true) end
end

-- "Smooth bars" was an on/off tick before it could follow General.
local function MigrateSmooth(db)
	if db and type(db.smoothBars) == "boolean" then db.smoothBars = db.smoothBars and "general" or "off" end
end

function M:OnInitialize()
	InitializeCooldownStack()
	MigrateSmooth(self.db)
end

function M:OnEnable()
	E:RunOutOfCombat(function() Refresh(self) end)
end

function M:OnDisable()
	E.Ticker:Unsubscribe(POLL_TICK)
	CastX.StopCastTicks()
	E:RunOutOfCombat(function()
		self.testMode = nil
		for _, frame in pairs(self.frames) do
			frame.testing = nil
			UnregisterUnitWatch(frame)
			frame:UnregisterAllEvents()
			frame:Hide()
			UnbindTexts(frame)
			RemovePrivateAnchors(frame)
			ReleaseAuras(frame)
			E.Portrait:Release(frame)
			for _, gate in ipairs({ frame.threatGate, frame.offTankGate, frame.lowHealthGate, frame.lowPowerGate }) do gate:Clear() end
			if frame.glowing then
				frame.glowing = nil
				E:HideGlow(frame)
			end
		end
		for _, key in ipairs(UNITS) do DetachFader(key) end
		if self.powerHolder then self.powerHolder:Hide() end
		-- Blizzard's own frames come back by the recorded undo; a frame
		-- Replace took the events from needs the reload the core asks for.
		for id in pairs(HANDLERS) do Restore(id) end
		self:RestorePrivateAuras()
	end)
end

function M:OnProfileChanged()
	MigrateSmooth(self.db)
	if self.active then
		E:RunOutOfCombat(function() Refresh(self) end)
	end
end

E:AddCommand("testframes", "[on | off | toggle]  show every enabled unit frame with sample values to place and style them", function(arg)
	arg = strtrim(arg or ""):lower()
	local state = not M.testMode
	if arg == "on" then state = true
	elseif arg == "off" then state = false
	elseif arg ~= "" and arg ~= "toggle" then
		E:Print(L["Usage: /eui testframes [on | off | toggle]"])
		return
	end
	if not M.active then
		E:Print(E:ModuleOffHint("UnitFrames"))
		return
	end
	M:SetTestMode(state)
end, "Layout & frames")

-- Helpers the options page (Modules/UnitFrames/Options.lua) shares with
-- this file, read through the module table: it loads right after it.
M.inner = {
	Text = Text, ExtraTag = ExtraTag,
	AURA_KIND = AURA_KIND, OTHER = OTHER,
}
