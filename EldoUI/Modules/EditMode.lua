-- EldoUI Edit Mode integration.
--
-- Blizzard's Edit Mode (Esc > Edit Mode) and EldoUI's own move mode both
-- place frames. This module makes them work together:
--   * Opening Blizzard's Edit Mode opens EldoUI's full move mode with it:
--     the EldoUI move panel docks beside Edit Mode's window and every EldoUI
--     frame can be dragged, snapping to Blizzard's grid when it is shown.
--     Leaving Edit Mode leaves EldoUI's move mode too.
--   * Or, with "Full EldoUI move tools" off, compact boxes over EldoUI's
--     frames with a small dialog for exact X/Y, nudging and reset (written
--     from scratch, no LibEditMode).
--   * A side panel next to Blizzard's Edit Mode window lists which Blizzard
--     frames EldoUI places, hides or replaces, and any conflicts, with an
--     "EldoUI options" button for EldoUI's Edit Mode settings.
--   * Blizzard frames that EldoUI hides or replaces, and the empty bars left
--     behind when EldoUI carries their buttons, lose their Edit Mode
--     selection box while Edit Mode is open, so they can't be grabbed.
--   * Optional: EldoUI positions follow the active Edit Mode layout, so
--     each Blizzard layout keeps its own EldoUI frame positions.
--   * Warnings when Blizzard's Edit Mode and EldoUI both place one frame.
--   * Labels in Edit Mode's check box columns that EldoUI's game fonts made
--     wider than their column are drawn smaller while Edit Mode is open.
--
-- Rules kept (taint):
--   * Edit Mode internals are never called and Edit Mode is never opened
--     from here. Layouts are only read with C_EditMode.GetLayouts() and
--     C_EditMode.GetAccountSettings(); Edit Mode enter/exit come from
--     EventRegistry callbacks. The one switch is Gamepad Mode UI's Restore
--     now (E:SetEditModeLayout): the player's click, after the game itself
--     set Modern on leaving its gamepad interface, runs one
--     C_EditMode.SetActiveLayout out of combat and never while Edit Mode
--     is open.
--   * Blizzard system frames are only read (GetPoint, IsShown). The
--     changes are SetAlpha/EnableMouse on the selection box of frames EldoUI
--     hides or replaces, and SetFont on check box labels too wide for their
--     column. Both start only while Edit Mode is open and out of combat, and
--     are undone when it closes. No field is ever written on Blizzard's frames.
--   * Edit Mode's window gets one HookScript (OnDragStop), so EldoUI's
--     panels dock again on the side with room after it was dragged.
--   * Everything else is EldoUI's own frames.
-- Every part checks the edit-mode element switch (Blizzard UI > Edit Mode
-- integration).
-- Written from scratch for EldoUI; no code or media from other addons.
local _, E = ...
local L = E.L

local M = E:NewModule("EditMode", {
	title = "Edit Mode",
	category = "Interface",
	desc = "EldoUI's frames inside Blizzard's Edit Mode, positions per Edit Mode layout, and warnings when both place the same frame.",
	frames = { "EldoUI_EditModePanel" },
	movers = {},
	blizzard = { "edit-mode" },
	savedKeys = { "profile.modules.EditMode" },
	optionsPage = "module:EditMode",
	presets = { "Clean", "Integrated", "PerLayout", "Precise", "Separate" },
	reload = false,
	defaults = {
		showMovers = true,     -- EldoUI frames inside Blizzard's Edit Mode
		fullTools = true,      -- EldoUI's full move mode and panel, not the compact boxes
		showLabels = true,     -- frame names on them
		panel = true,          -- EldoUI side panel next to Edit Mode's window
		snap = "both",         -- off | grid | frames | both
		snapDistance = 10,
		nudge = 1,             -- pixels per arrow click (Shift = x10)
		hideReplaced = true,   -- no selection box on Blizzard frames EldoUI hides or replaces
		tagMoved = true,       -- label Blizzard frames whose position EldoUI sets
		perLayout = false,     -- EldoUI positions per Edit Mode layout
		respect = true,        -- report EldoUI anchoring a frame whose Move switch is off
		warnConflicts = true,  -- say so in chat when Edit Mode opens
		layouts = {},          -- [layout key] = copy of the profile's mover positions
	},
})

---------------------------------------------------------------------------
-- Blizzard's Edit Mode systems, by EldoUI element (Data/BlizzardElements.lua).
-- system / index name the Enum.EditModeSystem value and its index enum;
-- frame is the global the system lives on. Names come from Blizzard's UI
-- source for WoW: Forever; frames that don't exist are skipped.
---------------------------------------------------------------------------
local UF, AB = "EditModeUnitFrameSystemIndices", "EditModeActionBarSystemIndices"
local SYSTEMS = {
	["player-frame"] = { { "UnitFrame", UF, "Player", "PlayerFrame" } },
	["target-focus-frames"] = { { "UnitFrame", UF, "Target", "TargetFrame" }, { "UnitFrame", UF, "Focus", "FocusFrame" } },
	["pet-frame"] = { { "UnitFrame", UF, "Pet", "PetFrame" } },
	["party-frames"] = { { "UnitFrame", UF, "Party", "PartyFrame" } },
	["raid-frames"] = { { "UnitFrame", UF, "Raid", "CompactRaidFrameContainer" } },
	["boss-frames"] = { { "UnitFrame", UF, "Boss", "BossTargetFrameContainer" } },
	["player-cast-bar"] = { { "CastBar", nil, nil, "PlayerCastingBarFrame" } },
	["class-resources"] = { { "PersonalResourceDisplay", nil, nil, "PersonalResourceDisplayFrame" } },
	["buffs-debuffs"] = {
		{ "AuraFrame", "EditModeAuraFrameSystemIndices", "BuffFrame", "BuffFrame" },
		{ "AuraFrame", "EditModeAuraFrameSystemIndices", "DebuffFrame", "DebuffFrame" },
	},
	["main-action-bar"] = { { "ActionBar", AB, "MainBar", "MainActionBar" } },
	["multi-action-bars"] = {
		{ "ActionBar", AB, "Bar2", "MultiBarBottomLeft" }, { "ActionBar", AB, "Bar3", "MultiBarBottomRight" },
		{ "ActionBar", AB, "RightBar1", "MultiBarRight" }, { "ActionBar", AB, "RightBar2", "MultiBarLeft" },
		{ "ActionBar", AB, "ExtraBar1", "MultiBar5" }, { "ActionBar", AB, "ExtraBar2", "MultiBar6" },
		{ "ActionBar", AB, "ExtraBar3", "MultiBar7" },
	},
	["pet-stance-bars"] = { { "ActionBar", AB, "PetActionBar", "PetActionBar" }, { "ActionBar", AB, "StanceBar", "StanceBar" } },
	["vehicle-possess-override"] = {
		{ "ActionBar", AB, "PossessActionBar", "PossessActionBar" },
		{ "VehicleLeaveButton", nil, nil, "MainMenuBarVehicleLeaveButton" },
		{ "VehicleSeatIndicator", nil, nil, "VehicleSeatIndicator" },
	},
	["extra-zone-ability"] = { { "ExtraAbilities", nil, nil, "ExtraAbilityContainer" } },
	["totem-bar"] = { { "TotemActionBar", nil, nil, "MultiCastActionBarFrame" } },
	["gamepad-hud"] = { { "GamepadMainActionBar", nil, nil, "GamepadMainActionBarFrame" } },
	["micro-menu"] = { { "MicroMenu", nil, nil, "MicroMenuContainer" } },
	["bag-bar"] = { { "Bags", nil, nil, "BagsBar" } },
	["status-tracking-bars"] = {
		{ "StatusTrackingBar", "EditModeStatusTrackingBarSystemIndices", "StatusTrackingBar1", "MainStatusTrackingBarContainer" },
		{ "StatusTrackingBar", "EditModeStatusTrackingBarSystemIndices", "StatusTrackingBar2", "SecondaryStatusTrackingBarContainer" },
	},
	["queue-status-button"] = { { "GroupFinder", nil, nil, "QueueStatusButton" } },
	["cooldown-viewer"] = {
		{ "CooldownViewer", "EditModeCooldownViewerSystemIndices", "Essential", "EssentialCooldownViewer" },
		{ "CooldownViewer", "EditModeCooldownViewerSystemIndices", "Utility", "UtilityCooldownViewer" },
		{ "CooldownViewer", "EditModeCooldownViewerSystemIndices", "BuffIcon", "BuffIconCooldownViewer" },
		{ "CooldownViewer", "EditModeCooldownViewerSystemIndices", "BuffBar", "BuffBarCooldownViewer" },
	},
	["damage-meter"] = { { "DamageMeter", nil, nil, "DamageMeter" } },
	["swing-timer"] = {
		{ "SwingTimer", "EditModeSwingTimerSystemIndices", "MainHand", "SwingTimerMainHandFrame" },
		{ "SwingTimer", "EditModeSwingTimerSystemIndices", "OffHand", "SwingTimerOffHandFrame" },
		{ "SwingTimer", "EditModeSwingTimerSystemIndices", "Ranged", "SwingTimerRangedFrame" },
	},
	["loss-of-control"] = { { "LossOfControl", nil, nil, "LossOfControlFrame" } },
	["mirror-quest-timers"] = { { "TimerBars", nil, nil, "MirrorTimerContainer" } },
	["talking-head"] = { { "TalkingHeadFrame", nil, nil, "TalkingHeadFrame" } },
	["raid-warning"] = { { "RaidWarning", nil, nil, "RaidWarningFrame" } },
	["minimap"] = { { "Minimap", nil, nil, "MinimapCluster" } },
	["objective-tracker"] = { { "ObjectiveTracker", nil, nil, "ObjectiveTrackerFrame" } },
	["ui-widgets"] = { { "EncounterBar", nil, nil, "EncounterBar" } },
	["chat-frames"] = { { "ChatFrame", nil, nil, "ChatFrame1" } },
	["tooltips"] = { { "HudTooltip", nil, nil, "GameTooltipDefaultContainer" } },
	["loot-window"] = { { "LootFrame", nil, nil, "LootFrame" } },
}
M.systems = SYSTEMS

-- Preset layouts come before the saved ones in Edit Mode's layout list;
-- each exists when Blizzard defines its system map. Fields: the system
-- map, the global with the preset's name in the game's language, the
-- English name, and the preset's Enum.EditModePresetLayouts name, which
-- gives the saved-positions key ("preset:modern") the same in every
-- language.
local PRESETS = {
	{ "EDIT_MODE_MODERN_SYSTEM_MAP", "LAYOUT_STYLE_MODERN", "Modern", "Modern" },
	{ "EDIT_MODE_CLASSIC_SYSTEM_MAP", "LAYOUT_STYLE_CLASSIC", "Classic", "Classic" },
	{ "EDIT_MODE_GAMEPAD_SYSTEM_MAP", "LAYOUT_STYLE_GAMEPAD", "Gamepad", "Gamepad" },
}

-- Every name the game gives the three presets, in each of its languages.
-- Positions saved before 0.7.1000 sit under "preset:<that name>"; the
-- update below finds them by these names and copies them to the key that
-- no longer depends on the language.
local PRESET_LABELS = {
	modern = { "Modern", "Moderno", "Moderne", "Moderna", "최신", "Современный", "现代", "現代模式" },
	classic = { "Classic", "Klassisch", "Clásico", "Classique", "Classica", "클래식", "Clássico", "Классический", "经典", "傳統模式" },
	gamepad = { "Gamepad", "Controller", "Mando", "Control", "Manette", "게임패드", "Controle", "Контроллер", "游戏手柄", "控制器" },
}
local LABEL_PRESET = {}
for token, labels in pairs(PRESET_LABELS) do
	for _, label in ipairs(labels) do LABEL_PRESET[label] = token end
end
M.presetLabels = PRESET_LABELS

local SNAP_VALUES = { off = "Off", grid = "Grid", frames = "Other frames", both = "Grid and frames" }

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local inEditMode = false
local overlays = {}                                      -- mover -> our overlay button
local tags = setmetatable({}, { __mode = "k" })          -- Blizzard frame -> our "EldoUI places this" label
local faded = setmetatable({}, { __mode = "k" })         -- Blizzard selection box -> true while we faded it
local own = {}                                           -- side panel, dialog
local selected                                           -- mover the dialog works on
local currentLayout                                      -- layout key the movers belong to
local warned = false
local callbacksRegistered = false
local ownMove = false                                    -- EldoUI move mode started by Edit Mode
local placesOpen = false                                 -- side panel: "What EldoUI places" unfolded
local LIST_MAX = 180                                     -- side panel: largest height of that list
local doneInEditMode = false                             -- the player left it with Done this time
local fitted = setmetatable({}, { __mode = "k" })        -- Blizzard label -> its own font, while shrunk

local function Usable(frame)
	return type(frame) == "table" and type(frame.GetObjectType) == "function"
		and not E.FrameCheck(frame, "IsForbidden")
end

local function Try(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then geterrorhandler()(err) end
	return ok
end

local function Allowed(action)
	return M.active and E:BlizzardAllowed("edit-mode", action)
end

local function AccentHex()
	local c = E.media.accentText
	return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

local function EnumValue(group, name)
	local enum = Enum and Enum[group]
	return enum and enum[name]
end

local function ElementTitle(id)
	local data = E.blizzardElements[id]
	return data and data.title and L[data.title] or id
end

---------------------------------------------------------------------------
-- Public API for modules
---------------------------------------------------------------------------
-- True while Blizzard's Edit Mode is open.
function E:IsEditModeActive()
	return inEditMode
end

-- True when Blizzard's Edit Mode decides where element `id` sits: EldoUI's
-- Move switch for it is off and EldoUI does not hide or replace it.
-- Modules that only skin an element leave its position alone then.
function E:EditModeOwnsPosition(id)
	return not self:BlizzardAllowed(id, "move") and not self:BlizzardHidden(id)
end

---------------------------------------------------------------------------
-- Reading Blizzard's layouts (C_EditMode only)
---------------------------------------------------------------------------
-- The presets the game defines: their names in the game's language and,
-- in the same order, their language-neutral tokens ("modern").
local function PresetNames()
	local names, tokens = {}, {}
	for _, preset in ipairs(PRESETS) do
		if _G[preset[1]] then
			names[#names + 1] = _G[preset[2]] or preset[3]
			tokens[#tokens + 1] = preset[4]:lower()
		end
	end
	return names, tokens
end

-- The active layout: key for saving positions, display name, saved layout
-- table (nil for a preset). A preset's key is the same in every language
-- ("preset:classic"); a saved layout's key holds the name the player gave it.
local function ActiveLayout()
	if not (C_EditMode and C_EditMode.GetLayouts) then return end
	local ok, info = pcall(C_EditMode.GetLayouts)
	if not ok or type(info) ~= "table" or type(info.activeLayout) ~= "number" then return end
	local presets, tokens = PresetNames()
	local index = info.activeLayout
	if index <= #presets then
		if not presets[index] then return end
		return "preset:" .. tokens[index], presets[index]
	end
	local layout = info.layouts and info.layouts[index - #presets]
	if type(layout) ~= "table" or type(layout.layoutName) ~= "string" then return end
	local characterType = Enum.EditModeLayoutType and Enum.EditModeLayoutType.Character
	if characterType and layout.layoutType == characterType then
		return "character:" .. (E.charKey or "") .. ":" .. layout.layoutName, layout.layoutName, layout
	end
	return "account:" .. layout.layoutName, layout.layoutName, layout
end

-- The key EldoUI keeps the active Edit Mode layout's positions under, and
-- its name in the game's language; nil when the game gives no layout. It
-- only reads: nothing switches a layout here.
function E:EditModeLayoutKey()
	return ActiveLayout()
end

-- The index C_EditMode.SetActiveLayout takes for a key from
-- E:EditModeLayoutKey, and the layout's name in the game's language; nil
-- when the game has no such layout (a saved layout was deleted).
function E:EditModeLayoutIndex(key)
	if type(key) ~= "string" or not (C_EditMode and C_EditMode.GetLayouts) then return nil end
	local ok, info = pcall(C_EditMode.GetLayouts)
	if not ok or type(info) ~= "table" then return nil end
	local presets, tokens = PresetNames()
	local token = key:match("^preset:(.+)$")
	if token then
		for index, value in ipairs(tokens) do
			if value == token then return index, presets[index] end
		end
		return nil
	end
	local characterType = Enum.EditModeLayoutType and Enum.EditModeLayoutType.Character
	for index, layout in ipairs(info.layouts or {}) do
		if type(layout) == "table" and type(layout.layoutName) == "string" then
			local perCharacter = characterType and layout.layoutType == characterType
			local mine = perCharacter and ("character:" .. (E.charKey or "") .. ":" .. layout.layoutName) or ("account:" .. layout.layoutName)
			if mine == key then return #presets + index, layout.layoutName end
		end
	end
	return nil
end

-- Restore now (Core/GamepadMode.lua): switch Edit Mode to the layout of
-- `key`. Returns true, or false and why: "combat", "editmode" or "missing".
function E:SetEditModeLayout(key)
	if InCombatLockdown() then return false, "combat" end
	if inEditMode then return false, "editmode" end
	local index = self:EditModeLayoutIndex(key)
	if not (index and C_EditMode.SetActiveLayout) then return false, "missing" end
	local ok, err = pcall(C_EditMode.SetActiveLayout, index)
	if not ok then
		geterrorhandler()(err)
		return false, "missing"
	end
	return true
end

-- Did the player move this system away from its default in the active layout?
local function MovedInEditMode(layout, entry)
	if not layout or type(layout.systems) ~= "table" then return false end
	local system = EnumValue("EditModeSystem", entry[1])
	if system == nil then return false end
	local index = entry[2] and EnumValue(entry[2], entry[3])
	for _, info in ipairs(layout.systems) do
		if info.system == system and (index == nil or info.systemIndex == index) then
			return info.isInDefaultPosition == false
		end
	end
	return false
end

local function AccountSetting(setting)
	if not (C_EditMode and C_EditMode.GetAccountSettings and Enum.EditModeAccountSetting) then return end
	local id = Enum.EditModeAccountSetting[setting]
	local ok, list = pcall(C_EditMode.GetAccountSettings)
	if not ok or type(list) ~= "table" then return end
	for _, info in ipairs(list) do
		if info.setting == id then return info.value end
	end
end

---------------------------------------------------------------------------
-- Conflicts
---------------------------------------------------------------------------
local function AnchoredToEldoUI(frame)
	if not Usable(frame) then return false end
	local parent = frame:GetParent()
	local parentName = parent and parent.GetName and parent:GetName()
	if type(parentName) == "string" and parentName:find("^EldoUI") then return true end
	for i = 1, frame:GetNumPoints() do
		local ok, _, relativeTo = pcall(frame.GetPoint, frame, i)
		local name = ok and relativeTo and relativeTo.GetName and relativeTo:GetName()
		if type(name) == "string" and name:find("^EldoUI") then return true end
	end
	return false
end

-- Lines describing where Blizzard and EldoUI disagree, in catalog order.
function M:Conflicts()
	local list = {}
	local _, _, layout = ActiveLayout()
	for _, id in ipairs(E.blizzardElementOrder) do
		local entries = SYSTEMS[id]
		if entries then
			local eldoMoves = E:BlizzardAllowed(id, "move") and not E:BlizzardHidden(id)
			local reported = false
			for _, entry in ipairs(entries) do
				if not reported and eldoMoves and MovedInEditMode(layout, entry) then
					list[#list + 1] = L["%s: moved in Edit Mode too. EldoUI's position wins; turn its Move switch off to use Edit Mode's."]:format(ElementTitle(id))
					reported = true
				end
				if not reported and self.db.respect and E:EditModeOwnsPosition(id) and AnchoredToEldoUI(_G[entry[4]]) then
					list[#list + 1] = L["%s: anchored to an EldoUI frame although its Move switch is off."]:format(ElementTitle(id))
					reported = true
				end
			end
		end
	end
	return list
end

-- What EldoUI does with each Edit Mode system, for the side panel.
local function Summary()
	local placed, hidden = {}, {}
	for _, id in ipairs(E.blizzardElementOrder) do
		if SYSTEMS[id] then
			if E:BlizzardHidden(id) then
				hidden[#hidden + 1] = ElementTitle(id)
			elseif E:BlizzardAllowed(id, "move") then
				placed[#placed + 1] = ElementTitle(id)
			end
		end
	end
	return placed, hidden
end

-- The conflict count as one line.
function M:ConflictSummary(list)
	list = list or self:Conflicts()
	if #list == 0 then return L["Edit Mode and EldoUI agree: no frame is placed by both."] end
	return (#list > 1 and L["%d frames are placed by both Edit Mode and EldoUI:"] or L["%d frame is placed by both Edit Mode and EldoUI:"]):format(#list)
end

-- The count and every frame, as one message (in the options window it
-- shows there; from /eui editmode it goes to chat).
function M:PrintConflicts()
	local list = self:Conflicts()
	local lines = { self:ConflictSummary(list) }
	for _, line in ipairs(list) do lines[#lines + 1] = "   " .. line end
	E:Print(table.concat(lines, "\n"))
end

---------------------------------------------------------------------------
-- Positions per Edit Mode layout
---------------------------------------------------------------------------
local function StoreLayout(key)
	if key then M.db.layouts[key] = CopyTable(E.db.movers) end
end

local function LoadLayout(key)
	local saved = M.db.layouts[key]
	if not saved then return false end
	wipe(E.db.movers)
	for name, point in pairs(saved) do E.db.movers[name] = CopyTable(point) end
	E:RefreshMovers()
	return true
end

function M:SyncLayout()
	if not (Allowed("move") and self.db.perLayout) then
		currentLayout = nil
		return
	end
	local key, name = ActiveLayout()
	if not key then return end
	if currentLayout == nil then
		-- The profile's positions belong to the layout that is active now.
		currentLayout = key
		StoreLayout(key)
		return
	end
	if key == currentLayout then return end
	StoreLayout(currentLayout)
	currentLayout = key
	if LoadLayout(key) then
		E:Print(L["Edit Mode layout %s: EldoUI frames moved to their spots for it."]:format(E:Highlight(name)))
	else
		StoreLayout(key)
	end
end

-- Positions saved before 0.7.1000 under a preset's name in one language
-- ("preset:Klassisch") are copied to its neutral key ("preset:classic"),
-- once per profile, after the profile's backup (profile version 3). The
-- old keys stay. A neutral key that is already there is never replaced.
-- When several old names of one preset hold different positions, the one
-- in the game's current language wins; with none of them, nothing is
-- copied and the first layout sync saves the key as before.
function M.MigratePresetKeys(profile)
	local modules = type(profile) == "table" and profile.modules
	local db = type(modules) == "table" and modules.EditMode
	local layouts = type(db) == "table" and db.layouts
	if type(layouts) ~= "table" then return end
	local found = {}
	for key, saved in pairs(layouts) do
		local label = type(key) == "string" and type(saved) == "table" and key:match("^preset:(.+)$")
		local token = label and LABEL_PRESET[label]
		if token then
			found[token] = found[token] or {}
			found[token][#found[token] + 1] = label
		end
	end
	-- The names in the game's language (global strings, there at login).
	local current = {}
	for _, preset in ipairs(PRESETS) do current[preset[4]:lower()] = _G[preset[2]] or preset[3] end
	for token, labels in pairs(found) do
		local neutral = "preset:" .. token
		if layouts[neutral] == nil then
			local pick = labels[1]
			for index = 2, #labels do
				if not E.DeepEqual(layouts["preset:" .. labels[index]], layouts["preset:" .. pick]) then
					pick = nil
					for _, label in ipairs(labels) do
						if label == current[token] then pick = label end
					end
					break
				end
			end
			if pick then layouts[neutral] = CopyTable(layouts["preset:" .. pick]) end
		end
	end
end
E:RegisterProfileMigration(M.MigratePresetKeys, "EditMode:presetKeys", 1)

-- A key saved before 0.7.1000 under a preset's name in one language.
function M:IsOlderLayoutKey(key)
	local label = type(key) == "string" and key:match("^preset:(.+)$")
	return label ~= nil and LABEL_PRESET[label] ~= nil
end

function M:ForgetLayouts()
	wipe(self.db.layouts)
	currentLayout = nil
	self:SyncLayout()
end

-- The button and /eui editmode forget ask first: the saved positions of
-- every other Edit Mode layout are gone for good.
function M:ConfirmForgetLayouts()
	if not next(self.db.layouts) then
		E:ConfigNotice(L["No EldoUI positions are saved for other Edit Mode layouts."])
		return
	end
	E:ShowConfirm({ title = L["Forget other layouts"], accept = L["Forget"], danger = true,
		text = L["Forget the EldoUI positions saved for your other Edit Mode layouts? The current positions stay."],
		onAccept = function()
			M:ForgetLayouts()
			E:ConfigNotice(L["Saved EldoUI positions for other Edit Mode layouts forgotten."])
		end })
end

---------------------------------------------------------------------------
-- Snapping and saving an EldoUI mover dragged inside Edit Mode
---------------------------------------------------------------------------
local function GridSpacing()
	if AccountSetting("ShowGrid") == 1 then
		local spacing = AccountSetting("GridSpacing")
		if type(spacing) == "number" and spacing >= 4 then return spacing end
	end
	return E.db.general.gridSize or 32
end

local function Nearest(value, candidates, distance)
	local best, bestDistance
	for _, candidate in ipairs(candidates) do
		local d = math.abs(candidate[1] - value)
		if d <= distance and (not bestDistance or d < bestDistance) then
			best, bestDistance = candidate[2], d
		end
	end
	return best
end

-- Pull the left/bottom edge onto a grid line or another frame's edge.
local function Snap(mover, left, bottom)
	local mode = M.db.snap
	if mode == "off" or IsAltKeyDown() then return left, bottom end
	local width, height = mover:GetSize()
	local distance = M.db.snapDistance or 10
	local xs, ys = {}, {}
	if mode == "frames" or mode == "both" then
		for _, other in pairs(E.movers) do
			if other ~= mover and other.frame and other.frame:IsShown() and other:GetLeft() then
				local oL, oR, oB, oT = other:GetLeft(), other:GetRight(), other:GetBottom(), other:GetTop()
				for _, edge in ipairs({ oL, oR }) do
					xs[#xs + 1] = { edge, edge }
					xs[#xs + 1] = { edge - width, edge - width }
				end
				for _, edge in ipairs({ oB, oT }) do
					ys[#ys + 1] = { edge, edge }
					ys[#ys + 1] = { edge - height, edge - height }
				end
			end
		end
	end
	local newLeft = Nearest(left, xs, distance) or Nearest(left + width, xs, distance)
	local newBottom = Nearest(bottom, ys, distance) or Nearest(bottom + height, ys, distance)
	if (mode == "grid" or mode == "both") then
		local grid = GridSpacing()
		local cx, cy = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
		if not newLeft then
			local line = cx + math.floor((left - cx) / grid + 0.5) * grid
			if math.abs(line - left) <= distance then newLeft = line end
		end
		if not newBottom then
			local line = cy + math.floor((bottom - cy) / grid + 0.5) * grid
			if math.abs(line - bottom) <= distance then newBottom = line end
		end
	end
	return newLeft or left, newBottom or bottom
end

-- Saved by Core/Movers.lua (anchored to the screen third it sits in, safe
-- area aware, onMoved callbacks fired), so Edit Mode and move mode store
-- the same thing. The layout copy is taken after the save has run.
local function SaveMover(mover, left, bottom)
	E:SaveMoverFromRect(mover, left, bottom)
	local layout = currentLayout
	if layout then E:RunOutOfCombat(function() StoreLayout(layout) end) end
end

local function ResetMover(mover)
	E.db.movers[mover.name] = nil
	E:RefreshMovers()
	if currentLayout then StoreLayout(currentLayout) end
end

---------------------------------------------------------------------------
-- Selected-frame dialog: exact X/Y, nudge, reset, settings
---------------------------------------------------------------------------
local UpdateDialog

local function Nudge(dx, dy)
	if not selected or InCombatLockdown() or not selected:GetLeft() then return end
	local step = M.db.nudge or 1
	if IsShiftKeyDown() then step = step * 10 end
	SaveMover(selected, selected:GetLeft() + dx * step, selected:GetBottom() + dy * step)
	UpdateDialog()
end

-- The kit's dialog shell (header-font title, accent line, Escape closes
-- it) with the position boxes and nudge arrows as its body.
local DIALOG_WIDTH = 250

local function Dialog()
	if own.dialog then return own.dialog end
	local Kit = E.UIKit
	local dialog = Kit.CreateDialog("EldoUI_EditModeDialog", { width = DIALOG_WIDTH, strata = "DIALOG", closeButton = true })
	dialog:SetFrameLevel(200)
	-- Escape or the X: nothing selected any more.
	dialog:HookScript("OnHide", function()
		if selected then M:Select(nil) end
	end)
	-- The boxes and arrows hang from a body frame placed under the header,
	-- so a taller title (Large text) moves them down with the accent line.
	local body = CreateFrame("Frame", nil, dialog)
	body:SetPoint("TOPLEFT", 0, -Kit.DIALOG_HEADER)
	body:SetPoint("TOPRIGHT", 0, -Kit.DIALOG_HEADER)
	body:SetHeight(1)
	dialog.body = body
	local top = 12

	local function Box(label, x, index)
		local text = Kit.Text(dialog, E.tokens.size.label, "RIGHT", "secondary")
		text:SetPoint("TOPLEFT", body, "TOPLEFT", x, -(top + 4))
		text:SetText(label)
		local box = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
		box:SetSize(54, E.tokens.height.button)
		box:SetPoint("LEFT", text, "RIGHT", 10, 0)
		box:SetAutoFocus(false)
		box:SetScript("OnEnterPressed", function(b)
			local value = tonumber(b:GetText())
			b:ClearFocus()
			if not selected or not value or InCombatLockdown() then return end
			if not E.db.movers[selected.name] and selected:GetLeft() then
				SaveMover(selected, selected:GetLeft(), selected:GetBottom())
			end
			local pos = E.db.movers[selected.name]
			if pos then
				pos[index] = math.floor(value + 0.5)
				E:RefreshMovers()
				if currentLayout then StoreLayout(currentLayout) end
			end
			UpdateDialog()
		end)
		-- Escape in a box leaves the box first; a second Escape closes the dialog.
		box:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
		E:SkinEditBox(box, { size = E.tokens.size.label })
		return box
	end
	dialog.x = Box("X", Kit.DIALOG_PAD, 4)
	dialog.y = Box("Y", 128, 5)

	-- Nudge arrows: the kit chevrons in a flat box (no letter glyphs).
	local arrowTop = top + E.tokens.height.button + 12
	local function Arrow(dir, x, y, dx, dy)
		local button = Kit.IconButton(dialog, 22, "chevron-" .. dir, function() Nudge(dx, dy) end)
		button:SetSize(28, 22)
		button:SetPoint("TOP", body, "TOP", x, -(arrowTop + y))
		E:SetTemplate(button, true)
		dialog.arrows = dialog.arrows or {}
		dialog.arrows[dir] = button
	end
	Arrow("up", 0, 0, 0, 1)
	Arrow("left", -32, 24, -1, 0)
	Arrow("right", 32, 24, 1, 0)
	Arrow("down", 0, 48, 0, -1)
	local bodyHeight = arrowTop + 48 + 22

	-- The body is fixed: the height is the header, the body and the button row.
	function dialog:Layout()
		local header = self:HeaderHeight()
		local edge = E:PixelFor(self)
		self.headerLine:ClearAllPoints()
		self.headerLine:SetPoint("TOPLEFT", edge, -header)
		self.headerLine:SetPoint("TOPRIGHT", -edge, -header)
		body:ClearAllPoints()
		body:SetPoint("TOPLEFT", 0, -header)
		body:SetPoint("TOPRIGHT", 0, -header)
		self:SetHeight(math.ceil((header + bodyHeight + Kit.DIALOG_PAD + E.tokens.height.buttonLarge + Kit.DIALOG_PAD) / 4) * 4)
	end
	dialog:SetButtons({
		{ RESET or L["Reset"], keepOpen = true, kind = "secondary", onClick = function()
			if selected and not InCombatLockdown() then
				ResetMover(selected)
				UpdateDialog()
			end
		end },
	})
	Kit.Tooltip(dialog.buttons[1], RESET or L["Reset"], L["Back to the position of the active EldoUI layout."])

	dialog:Hide()
	own.dialog = dialog
	return dialog
end

UpdateDialog = function()
	local dialog = own.dialog
	if not dialog then return end
	if not selected or not inEditMode then
		dialog:Hide()
		return
	end
	dialog:SetTitle(selected.title or selected.name)
	local pos = E.db.movers[selected.name] or E:GetMoverDefaultPoint(selected.name)
	dialog.x:SetText(pos and tostring(pos[4]) or "")
	dialog.y:SetText(pos and tostring(pos[5]) or "")
	dialog:ClearAllPoints()
	if own.panel and own.panel:IsShown() then
		dialog:SetPoint("TOPLEFT", own.panel, "BOTTOMLEFT", 0, -6)
	else
		dialog:SetPoint("TOPLEFT", selected, "TOPRIGHT", 8, 0)
	end
	dialog:Show()
end

---------------------------------------------------------------------------
-- Overlays on EldoUI's movers while Edit Mode is open
---------------------------------------------------------------------------
local function OverlayColor(overlay, mover)
	local r, g, b = unpack(E.media.accentColor)
	local alpha = (mover == selected) and 0.45 or (overlay.hover and 0.35 or 0.22)
	overlay:SetBackdropColor(r, g, b, alpha)
	if mover == selected then
		overlay:SetBackdropBorderColor(1, 1, 1, 1)
	else
		overlay:SetBackdropBorderColor(r, g, b, 0.9)
	end
end

local function RefreshOverlayColors()
	for mover, overlay in pairs(overlays) do OverlayColor(overlay, mover) end
end

function M:Select(mover)
	selected = mover
	RefreshOverlayColors()
	if mover then Dialog() end
	UpdateDialog()
end

-- Edit Mode's own window and its settings dialog are DIALOG frames: while
-- Edit Mode is open, EldoUI's boxes, compact boxes and labels sit one
-- strata lower (HIGH) so they never cover it, and go back after.
local function BoxStrata()
	return inEditMode and "HIGH" or "DIALOG"
end

local function ApplyBoxStrata()
	local strata = BoxStrata()
	for _, mover in pairs(E.movers or {}) do
		if mover.overlay then mover.overlay:SetFrameStrata(strata) end
	end
	for _, overlay in pairs(overlays) do overlay:SetFrameStrata(strata) end
	for _, tag in pairs(tags) do tag:SetFrameStrata(strata) end
end

-- A frame made while Edit Mode is open (a window opened later) takes the
-- same strata as the others.
hooksecurefunc(E, "CreateMover", function(_, _, name)
	local mover = inEditMode and name and E.movers[name]
	if mover and mover.overlay then mover.overlay:SetFrameStrata(BoxStrata()) end
end)

-- Blizzard's Edit Mode window and its settings dialog have a see-through
-- background: EldoUI's labels under a shown one fade, so the dialog reads
-- clean, and come back when it closes or moves. Their place and shown
-- state are only read, a few times a second while Edit Mode is open.
local DIM_ALPHA = 0.1
local dimTicker
local function DialogRects()
	local rects = {}
	for _, name in ipairs({ "EditModeManagerFrame", "EditModeSystemSettingsDialog" }) do
		local frame = _G[name]
		if Usable(frame) and frame:IsShown() then
			local left, bottom, width, height = frame:GetRect()
			if left and width then rects[#rects + 1] = { left, bottom, left + width, bottom + height } end
		end
	end
	return rects
end

local function Under(frame, rects)
	local left, bottom, width, height = frame:GetRect()
	if not (left and width) then return false end
	for _, rect in ipairs(rects) do
		if left < rect[3] and left + width > rect[1] and bottom < rect[4] and bottom + height > rect[2] then return true end
	end
	return false
end

local function DimLabels()
	local rects = inEditMode and DialogRects() or {}
	local function Fade(region, frame)
		if region then region:SetAlpha(#rects > 0 and Under(frame, rects) and DIM_ALPHA or 1) end
	end
	for _, mover in pairs(E.movers or {}) do
		local overlay = mover.overlay
		if overlay then
			Fade(overlay.text, mover)
			if overlay.tab then Fade(overlay.tab, overlay.tab) end
		end
	end
	for _, overlay in pairs(overlays) do Fade(overlay.label, overlay) end
	for _, tag in pairs(tags) do Fade(tag.text, tag.text) end
end

local function WatchDialogs(on)
	if dimTicker then
		dimTicker:Cancel()
		dimTicker = nil
	end
	if on and C_Timer and C_Timer.NewTicker then dimTicker = C_Timer.NewTicker(0.2, DimLabels) end
	DimLabels()
end

local function Overlay(mover)
	local overlay = overlays[mover]
	if overlay then return overlay end
	overlay = CreateFrame("Button", nil, UIParent)
	overlay:SetFrameStrata(BoxStrata())
	overlay:SetFrameLevel(2)
	overlay:SetAllPoints(mover)
	overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	E:SetTemplate(overlay)
	overlay.label = E:CreateText(overlay, E.tokens.size.label)
	overlay.label:SetPoint("CENTER")
	overlay:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" or InCombatLockdown() then return end
		self.dragging = true
		mover:StartMoving()
	end)
	overlay:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then
			if not InCombatLockdown() then ResetMover(mover) end
			M:Select(mover)
			return
		end
		if not self.dragging then return end
		self.dragging = false
		mover:StopMovingOrSizing()
		local left, bottom = mover:GetLeft(), mover:GetBottom()
		if left then
			left, bottom = Snap(mover, left, bottom)
			SaveMover(mover, left, bottom)
		end
		M:Select(mover)
	end)
	overlay:SetScript("OnEnter", function(self)
		self.hover = true
		OverlayColor(self, mover)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(AccentHex() .. "EldoUI|r " .. (mover.title or mover.name))
		E.UIKit.TipText(GameTooltip, L["Drag to move. Right-click resets it to the layout position."])
		E.UIKit.TipText(GameTooltip, L["Saved at once: Edit Mode's Revert does not undo EldoUI frames."])
		if not mover.frame:IsShown() then
			E.UIKit.TipText(GameTooltip, L["Hidden right now (shown while you move it)."])
		end
		GameTooltip:Show()
	end)
	overlay:SetScript("OnLeave", function(self)
		self.hover = false
		OverlayColor(self, mover)
		GameTooltip:Hide()
	end)
	overlay:Hide()
	overlays[mover] = overlay
	return overlay
end

-- Movers of modules that are switched off have nothing to place.
local function MoverInUse(mover)
	if not mover.module then return true end
	local module = E:GetModule(mover.module)
	return module and module.active
end

local function HideOverlays()
	for mover, overlay in pairs(overlays) do
		if overlay.dragging then
			overlay.dragging = false
			mover:StopMovingOrSizing()
		end
		overlay:Hide()
	end
end

-- A compact box's label: in the box, wrapped to it, or just above a box
-- too narrow for its longest word (Core/Movers.lua's rule).
local function PlaceLabel(overlay, text, width)
	local label = overlay.label
	label:ClearAllPoints()
	if text ~= "" and E:FitBoxLabel(label, text, width) == "outside" then
		label:SetWidth(0)
		label:SetWordWrap(false)
		label:SetText(text)
		label:SetPoint("BOTTOM", overlay, "TOP", 0, 2)
	else
		label:SetPoint("CENTER")
	end
end

local function ShowOverlays()
	-- EldoUI's own move mode draws its boxes while it runs.
	if not (inEditMode and Allowed("improve") and M.db.showMovers) or InCombatLockdown() or E:IsMoveMode() then
		HideOverlays()
		return
	end
	-- Frames on one spot (the windows that open at one point) share one
	-- box with every name; the first drags, and once it is moved off the
	-- spot the next one has its box.
	local spots, order = {}, {}
	for _, mover in pairs(E.movers) do
		local overlay = Overlay(mover)
		if MoverInUse(mover) then
			local left, bottom, width, height = mover:GetRect()
			local spot = left and ("%d:%d:%d:%d"):format(math.floor(left + 0.5), math.floor(bottom + 0.5), math.floor(width + 0.5), math.floor(height + 0.5)) or mover
			if not spots[spot] then
				spots[spot] = {}
				order[#order + 1] = spot
			end
			table.insert(spots[spot], mover)
		else
			overlay:Hide()
		end
	end
	for _, spot in ipairs(order) do
		local group = spots[spot]
		table.sort(group, function(a, b)
			if a == selected then return true end
			if b == selected then return false end
			local ta, tb = L[a.title or a.name], L[b.title or b.name]
			if ta ~= tb then return ta < tb end
			return a.name < b.name
		end)
		local names = {}
		for index, mover in ipairs(group) do
			names[index] = L[mover.title or mover.name]
			if index > 1 then overlays[mover]:Hide() end
		end
		local lead = group[1]
		local overlay = overlays[lead]
		local text = M.db.showLabels and table.concat(names, ", ") or ""
		PlaceLabel(overlay, text, lead:GetWidth())
		overlay:SetAlpha(lead.frame:IsShown() and 1 or 0.6)
		OverlayColor(overlay, lead)
		overlay:Show()
	end
end

---------------------------------------------------------------------------
-- EldoUI's full move mode with Blizzard's Edit Mode
---------------------------------------------------------------------------
local function WantFullTools()
	return inEditMode and Allowed("improve") and M.db.showMovers and M.db.fullTools
		and not doneInEditMode and not InCombatLockdown()
end

-- Blizzard's grid, when it is shown, is the one move mode snaps to; EldoUI
-- then draws none of its own.
local function EditModeGrid()
	if AccountSetting("ShowGrid") ~= 1 then return nil end
	return { size = GridSpacing(), hidden = true }
end

-- The move panel docks on the left of Edit Mode's window; when the
-- window sits too close to the screen's left edge for that, on its right.
local DOCK_GAP = 6

local function DockSide(manager)
	local movePanel = _G.EldoUI_Nudge
	local width = Usable(movePanel) and movePanel:GetWidth() or 0
	local left = manager:GetLeft()
	if left and left < width + DOCK_GAP then return "RIGHT" end
	return "LEFT"
end

local function UpdateMoveTools()
	local manager = _G.EditModeManagerFrame
	if WantFullTools() and Usable(manager) then
		if not E:IsMoveMode() then
			ownMove = true
			E:ToggleMoveMode(true)
		end
		if E:IsMoveMode() then
			ownMove = true
			E:SetMoveGridOverride(EditModeGrid())
			E:DockMovePanel(manager, DockSide(manager))
		end
	elseif ownMove then
		ownMove = false
		if E:IsMoveMode() and not InCombatLockdown() then E:ToggleMoveMode(false) end
		E:SetMoveGridOverride(nil)
		E:DockMovePanel(nil)
	end
end

-- Done in the move panel (a toggle, state nil) ends only EldoUI's part:
-- the compact boxes take over until Edit Mode opens again. Combat and
-- leaving Edit Mode pass false and don't count.
hooksecurefunc(E, "ToggleMoveMode", function(_, state)
	if not ownMove or E:IsMoveMode() then return end
	ownMove = false
	E:SetMoveGridOverride(nil)
	E:DockMovePanel(nil)
	if state == nil and inEditMode then
		doneInEditMode = true
		M:Refresh()
	end
end)

---------------------------------------------------------------------------
-- Check box labels in Blizzard's Edit Mode window
---------------------------------------------------------------------------
-- Edit Mode's check boxes sit in columns of a fixed width with a label of
-- natural width, so a bigger or wider game font runs it into the next
-- column. While Edit Mode is open, a label too wide for its column gets a
-- smaller size of its own font; its own font comes back on exit.
local function FitsLabels()
	return Allowed("improve") or (E.db.general and E.db.general.gameFonts)
end

local function FitLabel(row)
	local label, button, width = row.Label, row.Button, row.fixedWidth
	if type(width) ~= "number" or not Usable(button) or type(label) ~= "table"
		or type(label.GetStringWidth) ~= "function" or fitted[label] then return end
	local room = width - button:GetWidth() - 7
	local textWidth = label:GetStringWidth()
	if type(textWidth) ~= "number" or room <= 0 or textWidth <= room then return end
	local path, size, flags = label:GetFont()
	if not path or not size then return end
	fitted[label] = { object = label:GetFontObject(), path = path, size = size, flags = flags }
	label:SetFont(path, math.max(8, math.floor(size * room / textWidth * 10) / 10), flags or "")
end

local function FitLabels()
	local manager = _G.EditModeManagerFrame
	if not (inEditMode and FitsLabels() and Usable(manager)) or InCombatLockdown() then return end
	local function Walk(frame, depth)
		for _, child in ipairs({ frame:GetChildren() }) do
			if Usable(child) then
				FitLabel(child)
				if depth < 8 then Walk(child, depth + 1) end
			end
		end
	end
	Walk(manager, 1)
end

local function RestoreLabels()
	for label, font in pairs(fitted) do
		if font.object then
			label:SetFontObject(font.object)
		else
			label:SetFont(font.path, font.size, font.flags or "")
		end
		fitted[label] = nil
	end
end
M.FitLabels, M.RestoreLabels = FitLabels, RestoreLabels

---------------------------------------------------------------------------
-- Blizzard system frames while Edit Mode is open
---------------------------------------------------------------------------
-- Blizzard bars whose buttons ride in a frame of EldoUI's own (the micro
-- menu, the bag bar): Blizzard's bar stays behind as an empty shell, and
-- EldoUI's frame, with its own box, is where the buttons are.
local standIns = {}

-- id: a Blizzard UI element; holder: EldoUI's frame carrying its buttons,
-- or nil once Blizzard's bar has them back.
function E:SetEditModeStandIn(id, holder)
	if standIns[id] == holder then return end
	standIns[id] = holder or nil
	if inEditMode and M.active then M:Refresh() end
end

function E:EditModeStandIn(id)
	return standIns[id]
end

-- No selection box on frames EldoUI hides or replaces, nor on the empty
-- shells EldoUI's own frames stand in for: dragging one would move nothing.
local function FadeSelections()
	local fade = inEditMode and Allowed("improve") and M.db.hideReplaced and not InCombatLockdown()
	for _, id in ipairs(E.blizzardElementOrder) do
		local entries = SYSTEMS[id]
		if entries then
			local hide = fade and (E:BlizzardHidden(id) or standIns[id] ~= nil)
			for _, entry in ipairs(entries) do
				local frame = _G[entry[4]]
				local selection = Usable(frame) and frame.Selection
				if Usable(selection) and not (E.FrameCheck(selection, "IsProtected") and InCombatLockdown()) then
					if hide and not faded[selection] then
						faded[selection] = true
						selection:SetAlpha(0)
						selection:EnableMouse(false)
					elseif not hide and faded[selection] then
						faded[selection] = nil
						selection:SetAlpha(1)
						selection:EnableMouse(true)
					end
				end
			end
		end
	end
end

local function RestoreSelections()
	for selection in pairs(faded) do
		if Usable(selection) and not (E.FrameCheck(selection, "IsProtected") and InCombatLockdown()) then
			selection:SetAlpha(1)
			selection:EnableMouse(true)
			faded[selection] = nil
		end
	end
end

-- "EldoUI places this" on Blizzard frames whose position EldoUI sets, so
-- nobody wonders why an Edit Mode drag doesn't stick.
local function Tag(frame)
	local tag = tags[frame]
	if tag then return tag end
	tag = CreateFrame("Frame", nil, UIParent)
	tag:SetFrameStrata(BoxStrata())
	tag:SetFrameLevel(1)
	tag:EnableMouse(false)
	tag.text = E:CreateText(tag, E.tokens.size.small)
	tag.text:SetPoint("BOTTOM", tag, "TOP", 0, 2)
	tag.bg = tag:CreateTexture(nil, "BACKGROUND")
	tag.bg:SetPoint("TOPLEFT", tag.text, "TOPLEFT", -4, 2)
	tag.bg:SetPoint("BOTTOMRIGHT", tag.text, "BOTTOMRIGHT", 4, -2)
	tag.bg:SetColorTexture(0, 0, 0, 0.7)
	tags[frame] = tag
	return tag
end

local function UpdateTags()
	local show = inEditMode and Allowed("improve") and M.db.tagMoved
	local wanted = {}
	if show then
		for _, id in ipairs(E.blizzardElementOrder) do
			local entries = SYSTEMS[id]
			-- A faded shell has no box left to explain: EldoUI's own box
			-- over its frame is the one to drag.
			local shell = standIns[id] and M.db.hideReplaced
			if entries and E:BlizzardAllowed(id, "move") and not E:BlizzardHidden(id) and not shell then
				for _, entry in ipairs(entries) do
					local frame = _G[entry[4]]
					if Usable(frame) and frame:IsShown() then wanted[frame] = true end
				end
			end
		end
	end
	for frame in pairs(wanted) do
		local tag = Tag(frame)
		tag:ClearAllPoints()
		tag:SetAllPoints(frame)
		tag.text:SetText(AccentHex() .. L["EldoUI places this"] .. "|r")
		tag:Show()
	end
	for frame, tag in pairs(tags) do
		if not wanted[frame] then tag:Hide() end
	end
end

---------------------------------------------------------------------------
-- Side panel next to Blizzard's Edit Mode window
---------------------------------------------------------------------------
local UpdatePanel

-- The panel and its rows. Labels wrap inside the panel and each row grows
-- with its label, so no text runs past the panel at any text size.
local PANEL_WIDTH, PANEL_PAD, CHECK_SIZE = 280, 10, 22
local LABEL_WIDTH = PANEL_WIDTH - PANEL_PAD - CHECK_SIZE - 6 - PANEL_PAD

local function Check(panel, label, key, desc, needsMove)
	local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	check:SetSize(CHECK_SIZE, CHECK_SIZE)
	E:SkinCheckBox(check)
	check.text = E:CreateText(check, E.tokens.size.label, "LEFT")
	check.text:SetPoint("TOPLEFT", check, "TOPRIGHT", 6, -4)
	check.text:SetWidth(LABEL_WIDTH)
	check.text:SetWordWrap(true)
	check.text:SetJustifyV("TOP")
	check.text:SetText(label)
	-- A click on the words toggles too.
	check:SetHitRectInsets(0, -(LABEL_WIDTH + 6), 0, 0)
	check:SetScript("OnClick", function(self, button)
		-- Ctrl-click opens the setting instead: the box keeps its state.
		if E:IsOptionsLinkClick(self, button) then
			self:SetChecked(M.db[key] and true or false)
			return
		end
		M.db[key] = self:GetChecked() and true or false
		M:Refresh()
	end)
	check:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(label)
		E.UIKit.TipText(GameTooltip, desc)
		local reason = needsMove and not Allowed("move") and E:BlizzardNeedsReason("edit-mode", "move")
		if reason then GameTooltip:AddLine(reason, E:TokenColor("warn", true)) end
		GameTooltip:Show()
	end)
	check:SetScript("OnLeave", function() GameTooltip:Hide() end)
	E:BindOptionsLink(check, { page = "module:EditMode", key = key })
	check.key = key
	check.needsMove = needsMove
	return check
end

local function Panel()
	if own.panel then return own.panel end
	local panel = CreateFrame("Frame", "EldoUI_EditModePanel", UIParent)
	-- Escape closes it like Blizzard's Edit Mode window beside it.
	table.insert(UISpecialFrames, "EldoUI_EditModePanel")
	panel:SetWidth(PANEL_WIDTH)
	panel:SetFrameStrata("DIALOG")
	panel:SetFrameLevel(150)
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	E:SetPanelTemplate(panel)

	panel.title = E.UIKit.Title(panel, E.tokens.size.dialogTitle)
	panel.title:SetPoint("TOPLEFT", PANEL_PAD, -8)
	panel.title:SetPoint("TOPRIGHT", -PANEL_PAD, -8)
	panel.title:SetJustifyH("LEFT")
	panel.title:SetWordWrap(false)
	local line = panel:CreateTexture(nil, "ARTWORK")
	line:SetPoint("TOPLEFT", E.pixel, -30)
	line:SetPoint("TOPRIGHT", -E.pixel, -30)
	line:SetHeight(E.pixel * 2)
	E:AccentTexture(line, 1)
	panel.line = line

	panel.checks = {
		Check(panel, L["Show EldoUI frames"], "showMovers", L["EldoUI's frames get a box you can drag, like Blizzard's."]),
		Check(panel, L["Full EldoUI move tools"], "fullTools", L["EldoUI's move mode opens with Edit Mode: its panel beside this window, with search, exact X and Y, lock, attach, match size and test frames. Off: compact boxes with a small X and Y dialog."]),
		Check(panel, L["Names on EldoUI frames"], "showLabels", L["Show each EldoUI frame's name on its box."]),
		Check(panel, L["Mark frames EldoUI places"], "tagMoved", L["Blizzard frames whose position EldoUI sets get a label: dragging them in Edit Mode won't stick."]),
		Check(panel, L["Positions per Edit Mode layout"], "perLayout", L["Each Edit Mode layout keeps its own EldoUI frame positions."], true),
	}
	panel.body = E:CreateText(panel, E.tokens.size.small, "LEFT")
	panel.body:SetPoint("TOPLEFT", PANEL_PAD + 2, 0)
	panel.body:SetJustifyV("TOP")
	panel.body:SetWordWrap(true)
	panel.body:SetSpacing(2)

	-- "What EldoUI places": a section that folds, closed by default. Open,
	-- its lists sit in a scroll area of a fixed largest height, so a long
	-- list never runs out of the panel.
	local places = CreateFrame("Button", nil, panel)
	places:SetHeight(E.tokens.height.button)
	places:SetPoint("LEFT", PANEL_PAD - 2, 0)
	places:SetPoint("RIGHT", -(PANEL_PAD - 2), 0)
	places.text = E.UIKit.Text(places, E.tokens.size.label, "LEFT", "secondary")
	places.text:SetPoint("LEFT", 2, 0)
	places.text:SetPoint("RIGHT", -18, 0)
	places.text:SetWordWrap(false)
	places.chevron = E.UIKit.Chevron(places, "right", 10)
	places.chevron:SetPoint("RIGHT", -4, 0)
	places.hover = places:CreateTexture(nil, "BACKGROUND")
	places.hover:SetAllPoints()
	places.hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	places.hover:Hide()
	E.UIKit.Tooltip(places, L["What EldoUI places"], L["The Blizzard frames whose place EldoUI sets, hides or replaces. Click to show or hide the list."])
	places:HookScript("OnEnter", function(self) self.hover:Show() end)
	places:HookScript("OnLeave", function(self) self.hover:Hide() end)
	places:SetScript("OnClick", function(self, button)
		if E:IsOptionsLinkClick(self, button) then return end
		placesOpen = not placesOpen
		UpdatePanel()
	end)
	E:BindOptionsLink(places, { page = "module:EditMode" })
	panel.places = places
	local placeList = E.UIKit.ScrollArea(panel)
	placeList:SetPoint("LEFT", PANEL_PAD + 2, 0)
	placeList:SetPoint("RIGHT", -(PANEL_PAD - 2), 0)
	placeList.text = E:CreateText(placeList.child, E.tokens.size.small, "LEFT")
	placeList.text:SetPoint("TOPLEFT")
	placeList.text:SetJustifyV("TOP")
	placeList.text:SetWordWrap(true)
	placeList.text:SetSpacing(2)
	placeList:Hide()
	panel.list = placeList

	-- The one way from Edit Mode into EldoUI's settings: their Edit Mode
	-- page (design decision; the settings otherwise open only from /eui and
	-- the Game Menu). In combat they open when combat ends, after EldoUI's
	-- move tools are back: those starting would close them again.
	panel.options = E.UIKit.Button(panel, { text = L["EldoUI options"], minWidth = 116,
		tip = { L["EldoUI options"], L["EldoUI's Edit Mode settings: snapping, nudge step, conflicts and style presets."] },
		onClick = function()
			if not InCombatLockdown() then
				E:OpenConfigFromEditMode()
				return
			end
			E:Print(L["The config window opens after combat."])
			E:RunOutOfCombat(function()
				if inEditMode then M:Refresh() end
				E:OpenConfigFromEditMode()
			end, "config:open")
		end })

	-- The panel lists the result; the toast confirms the check ran. A list
	-- longer than the panel shows goes to chat in full.
	panel.check = E.UIKit.Button(panel, { text = L["Check again"], minWidth = 116,
		onClick = function()
			UpdatePanel()
			local list = M:Conflicts()
			E.UIKit.Toast(panel, M:ConflictSummary(list), { warn = #list > 0 })
			if #list > 6 then M:PrintConflicts() end
		end })

	panel:Hide()
	own.panel = panel
	return panel
end

-- Rows from the top: each check is as tall as its (wrapped) label.
-- The accent line sits 8 px under the title, never above 30 (Large text
-- makes the title taller); the rows start 8 px under the line.
local function LayoutChecks(panel)
	local header = math.max(30, 8 + math.ceil(panel.title:GetStringHeight() or 0) + 8)
	panel.line:ClearAllPoints()
	panel.line:SetPoint("TOPLEFT", E.pixel, -header)
	panel.line:SetPoint("TOPRIGHT", -E.pixel, -header)
	local y = header + 8
	for _, check in ipairs(panel.checks) do
		check:ClearAllPoints()
		check:SetPoint("TOPLEFT", PANEL_PAD - 2, -y)
		local height = math.max(CHECK_SIZE, math.ceil(check.text:GetStringHeight()) + 8)
		y = y + height + 2
	end
	return y + 6
end

-- The footer: both buttons in one row when they fit side by side, else
-- one above the other (Large text). Returns the footer's height.
local function LayoutFooter(panel)
	local options, check = panel.options, panel.check
	options:ClearAllPoints()
	check:ClearAllPoints()
	check:SetPoint("BOTTOMRIGHT", -8, 8)
	if options:GetWidth() + 8 + check:GetWidth() <= PANEL_WIDTH - 16 then
		options:SetPoint("BOTTOMLEFT", 8, 8)
		return math.max(options:GetHeight(), check:GetHeight())
	end
	options:SetPoint("BOTTOMRIGHT", check, "TOPRIGHT", 0, 6)
	return options:GetHeight() + 6 + check:GetHeight()
end

UpdatePanel = function()
	local frame = _G.EditModeManagerFrame
	local show = inEditMode and Allowed("improve") and M.db.panel and Usable(frame)
	if not show then
		if own.panel then own.panel:Hide() end
		return
	end
	local panel = Panel()
	panel.title:SetText(L["EldoUI and Edit Mode"])
	for _, check in ipairs(panel.checks) do
		check:SetChecked(M.db[check.key] and true or false)
		local usable = (not check.needsMove or Allowed("move")) and (check.key ~= "fullTools" or M.db.showMovers)
		check:SetEnabled(usable)
		check.text:SetAlpha(usable and 1 or 0.45)
	end
	local top = LayoutChecks(panel)
	panel.body:SetPoint("TOPLEFT", PANEL_PAD + 2, -top)
	local lines = {}
	local _, layoutName = ActiveLayout()
	if layoutName then lines[#lines + 1] = E:TextHex("secondary") .. L["Layout:"] .. "|r " .. layoutName end
	local conflicts = M:Conflicts()
	if #conflicts > 0 then
		lines[#lines + 1] = E:TextHex("warn") .. L["Placed by both:"] .. "|r"
		for i, line in ipairs(conflicts) do
			if i > 6 then
				lines[#lines + 1] = E:TextHex("secondary") .. L["... and %d more (Check again prints all)"]:format(#conflicts - 6) .. "|r"
				break
			end
			lines[#lines + 1] = E:TextHex("accent") .. "-|r " .. line
		end
	else
		lines[#lines + 1] = E:TextHex("good") .. L["No frame is placed by both."] .. "|r"
	end
	-- A set width, so the height is measured with the wrap the panel shows.
	panel.body:SetWidth(PANEL_WIDTH - 2 * (PANEL_PAD + 2))
	panel.body:SetText(table.concat(lines, "\n"))
	local y = top + math.max(panel.body:GetStringHeight(), 14) + 8

	-- The folding list of what EldoUI places, hides or replaces.
	local placed, hidden = Summary()
	local places, list = panel.places, panel.list
	places.text:SetText(("%s (%d)"):format(L["What EldoUI places"]:upper(), #placed + #hidden))
	E.UIKit.SetGlyph(places.chevron, placesOpen and "chevron-down" or "chevron-right")
	places:ClearAllPoints()
	places:SetPoint("TOPLEFT", PANEL_PAD - 2, -y)
	places:SetPoint("TOPRIGHT", -(PANEL_PAD - 2), -y)
	y = y + places:GetHeight() + 2
	if placesOpen then
		local items = {}
		if #placed > 0 then items[#items + 1] = E:TextHex("secondary") .. L["EldoUI places:"] .. "|r " .. table.concat(placed, ", ") end
		if #hidden > 0 then items[#items + 1] = E:TextHex("secondary") .. L["EldoUI hides or replaces:"] .. "|r " .. table.concat(hidden, ", ") end
		if #items == 0 then items[1] = E:TextHex("secondary") .. L["Nothing yet: EldoUI leaves every Edit Mode frame to Blizzard."] .. "|r" end
		list.text:SetWidth(PANEL_WIDTH - 2 * PANEL_PAD - E.UIKit.SCROLL_WIDTH - 8)
		list.text:SetText(table.concat(items, "\n"))
		local textHeight = math.ceil(list.text:GetStringHeight() or 0)
		list.child:SetHeight(math.max(textHeight, 1))
		local height = math.min(textHeight, LIST_MAX)
		list:ClearAllPoints()
		list:SetPoint("TOPLEFT", PANEL_PAD + 2, -y)
		list:SetPoint("TOPRIGHT", -(PANEL_PAD - 2), -y)
		list:SetHeight(math.max(height, 14))
		list:Show()
		list:Update()
		y = y + list:GetHeight() + 6
	else
		list:Hide()
	end
	panel:SetHeight(math.ceil(y + 8 + LayoutFooter(panel) + 8))
	-- Placement: under EldoUI's move panel when that is docked beside Edit
	-- Mode's window, so all three sit in two columns and none covers
	-- another; else beside Edit Mode's window, on whichever side has room.
	panel:ClearAllPoints()
	local movePanel = _G.EldoUI_Nudge
	if ownMove and E:IsMoveMode() and Usable(movePanel) and movePanel:IsShown() then
		if DockSide(frame) == "RIGHT" then
			panel:SetPoint("TOPLEFT", movePanel, "BOTTOMLEFT", 0, -DOCK_GAP)
		else
			panel:SetPoint("TOPRIGHT", movePanel, "BOTTOMRIGHT", 0, -DOCK_GAP)
		end
	elseif (frame:GetRight() or 0) + DOCK_GAP + PANEL_WIDTH > UIParent:GetWidth() then
		panel:SetPoint("TOPRIGHT", frame, "TOPLEFT", -DOCK_GAP, 0)
	else
		panel:SetPoint("TOPLEFT", frame, "TOPRIGHT", DOCK_GAP, 0)
	end
	-- An open list gives up height when the panel would reach past the
	-- bottom of the screen; it scrolls either way.
	local bottom = placesOpen and panel:GetBottom()
	if bottom and bottom < 0 then
		local height = math.max(14, list:GetHeight() + bottom)
		panel:SetHeight(panel:GetHeight() - (list:GetHeight() - height))
		list:SetHeight(height)
		list:Update()
	end
	panel:SetShown(not E:IsMoveOverlayHidden())
end

-- The move panel's Hide boxes and Peek take this panel along.
E:RegisterMoveOverlayListener(function()
	if inEditMode then Try(UpdatePanel) end
end)

---------------------------------------------------------------------------
-- Edit Mode enter / exit (EventRegistry callbacks; Blizzard's code is not called)
---------------------------------------------------------------------------
function M:Refresh()
	Try(UpdateMoveTools)
	Try(ShowOverlays)
	Try(FadeSelections)
	Try(UpdateTags)
	Try(UpdatePanel)
	Try(UpdateDialog)
end

-- Edit Mode's window dragged somewhere else: EldoUI's panels dock again
-- on the side that has room (a hook; Blizzard's handler runs unchanged).
local dragHooked = false
local function HookManagerDrag()
	local manager = _G.EditModeManagerFrame
	if dragHooked or not Usable(manager) then return end
	dragHooked = true
	manager:HookScript("OnDragStop", function()
		if inEditMode and M.active and not InCombatLockdown() then
			Try(UpdateMoveTools)
			Try(UpdatePanel)
		end
	end)
end

function M:OnEditModeEnter()
	inEditMode = true
	doneInEditMode = false
	E:RunOutOfCombat(ApplyBoxStrata)
	WatchDialogs(true)
	if not self.active then return end
	HookManagerDrag()
	Try(FitLabels)
	if not Allowed() then return end
	-- EldoUI's move mode goes along with Edit Mode (or makes way for the
	-- compact boxes); keybind mode makes way.
	if E:IsMoveMode() and not WantFullTools() then E:ToggleMoveMode(false) end
	if E.IsKeybindMode and E:IsKeybindMode() then E:ToggleKeybindMode(false, true) end
	self:Refresh()
	-- The first time: a tour help on EldoUI's panel beside Edit Mode.
	if not E.Tour:Seen("editmode:with") then
		C_Timer.After(0.5, function()
			if inEditMode then E.Tour:Offer("editmode:with") end
		end)
	end
	if self.db.warnConflicts and not warned then
		local conflicts = self:Conflicts()
		if #conflicts > 0 then
			warned = true
			E:Print((#conflicts > 1 and L["%d frames are placed by both Edit Mode and EldoUI. The EldoUI panel next to Edit Mode lists them."]
				or L["%d frame is placed by both Edit Mode and EldoUI. The EldoUI panel next to Edit Mode lists them."]):format(#conflicts))
		end
	end
end

function M:OnEditModeExit()
	inEditMode = false
	E:RunOutOfCombat(ApplyBoxStrata)
	WatchDialogs(false)
	selected = nil
	HideOverlays()
	Try(RestoreSelections)
	Try(RestoreLabels)
	self:Refresh()
	doneInEditMode = false
	-- A layout picked inside Edit Mode becomes active on exit.
	Try(self.SyncLayout, self)
end

-- Tour help: what EldoUI adds to Blizzard's Edit Mode, shown once per
-- account on EldoUI's panel beside Edit Mode's window.
local function ShownPanel()
	local panel = own.panel
	if inEditMode and panel and panel:IsVisible() then return panel end
end

E.Tour:Register("editmode:with", {
	form = "spot", word = "editmode",
	offer = function(_, force)
		if not ShownPanel() then return false end
		local text
		if ownMove and E:IsMoveMode() then
			text = L["EldoUI's frames move here too: drag them like Blizzard's, with EldoUI's move panel beside Edit Mode's window."]
				.. " " .. L["This panel sets how they show in Edit Mode, and What EldoUI places lists the Blizzard frames EldoUI places, hides or replaces."]
		elseif M.db.showMovers then
			text = L["EldoUI's frames move here too: drag a box, or click it for exact X and Y."]
				.. " " .. L["This panel sets how they show in Edit Mode, and What EldoUI places lists the Blizzard frames EldoUI places, hides or replaces."]
		else
			text = L["This panel sets how EldoUI's frames show in Edit Mode, and What EldoUI places lists the Blizzard frames EldoUI places, hides or replaces."]
		end
		return E.Tour:Spot("editmode:with", {
			force = force, target = ShownPanel,
			title = L["EldoUI and Edit Mode"],
			text = text,
		})
	end,
	replay = function(def)
		if not ShownPanel() then
			E:Print(L["This help shows while Blizzard's Edit Mode is open with EldoUI's panel beside it."])
			return
		end
		def.offer(def, true)
	end,
})

local function RegisterCallbacks()
	if callbacksRegistered or not EventRegistry then return end
	callbacksRegistered = true
	EventRegistry:RegisterCallback("EditMode.Enter", function() M:OnEditModeEnter() end, M)
	EventRegistry:RegisterCallback("EditMode.Exit", function() M:OnEditModeExit() end, M)
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:Apply()
	-- Edit Mode enter/exit are followed even without the Edit Mode switch:
	-- labels that EldoUI's game fonts made too wide still need to fit.
	RegisterCallbacks()
	if Allowed() then
		self:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", function()
			C_Timer.After(0, function() Try(M.SyncLayout, M) if inEditMode then UpdatePanel() end end)
		end)
		self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
			HideOverlays()
			Try(RestoreSelections)
			if own.dialog then own.dialog:Hide() end
		end)
		self:RegisterEvent("PLAYER_REGEN_ENABLED", function() if inEditMode then M:Refresh() end end)
		self:RegisterEvent("PLAYER_LOGOUT", function() if currentLayout then StoreLayout(currentLayout) end end)
		-- Opened before EldoUI started listening (e.g. switched on inside Edit Mode).
		local frame = _G.EditModeManagerFrame
		if Usable(frame) and frame:IsShown() then inEditMode = true end
	else
		self:UnregisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
		self:UnregisterEvent("PLAYER_REGEN_DISABLED")
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
		self:UnregisterEvent("PLAYER_LOGOUT")
	end
	Try(self.SyncLayout, self)
	self:Refresh()
	if not inEditMode or not Allowed("improve") then Try(RestoreSelections) end
end

function M:OnEnable()
	E:OnBlizzardAddOn("Blizzard_EditMode", function()
		if M.active then E:RunOutOfCombat(function() M:Apply() end) end
	end)
end

function M:OnDisable()
	HideOverlays()
	Try(RestoreSelections)
	Try(RestoreLabels)
	Try(UpdateMoveTools)
	currentLayout = nil
	for _, tag in pairs(tags) do tag:Hide() end
	if own.panel then own.panel:Hide() end
	if own.dialog then own.dialog:Hide() end
	self:UnregisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
	self:UnregisterEvent("PLAYER_REGEN_DISABLED")
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	self:UnregisterEvent("PLAYER_LOGOUT")
end

function M:OnProfileChanged()
	if not self.active then return end
	-- Another profile has its own positions: start a fresh layout link.
	currentLayout = nil
	E:RunOutOfCombat(function() if M.active then M:Apply() end end)
end

E:RegisterBlizzardHandler("edit-mode", {
	owner = "EditMode",
	apply = function() M:Apply() end,
	undo = function()
		HideOverlays()
		Try(RestoreSelections)
		M:Refresh()
	end,
	install = { improve = true },
})

E:AddCommand("editmode", "[conflicts | layouts | forget]  Edit Mode and EldoUI: conflicts, saved layouts, forget saved layouts", function(arg)
	arg = (arg or ""):lower()
	if arg == "layouts" then
		local key, name = ActiveLayout()
		local perLayout = M.db and M.db.perLayout and Allowed("move")
		E:Print((perLayout and L["Active Edit Mode layout: %s"] or L["Active Edit Mode layout: %s (positions per layout are off)"])
			:format(name or L["unknown"]))
		for saved in pairs(M.db.layouts) do
			local note = ""
			if saved == key then
				note = "  " .. E:TextHex("good") .. L["(active)"] .. "|r"
			elseif M:IsOlderLayoutKey(saved) then
				note = "  " .. E:TextHex("secondary") .. L["(from an older version)"] .. "|r"
			end
			print("   " .. saved .. note)
		end
	elseif arg == "forget" then
		M:ConfirmForgetLayouts()
	elseif arg == "" or arg == "conflicts" then
		M:PrintConflicts()
	else
		E:Print(L["Use %s, %s or %s."]:format(E:Highlight("/eui editmode conflicts"), E:Highlight("/eui editmode layouts"), E:Highlight("/eui editmode forget")))
	end
end, "Layout & frames")

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
M.options = {
	{ type = "tab", label = "Edit Mode" },
	{ type = "description", label = "Edit Mode brings EldoUI's move tools along, so Blizzard's and EldoUI's frames are placed in one go. /eui move has the same tools." },
	{ type = "execute", label = "Open Blizzard UI switches", width = 200,
		desc = "Open Blizzard UI > System and settings windows, where 'Edit Mode integration' is switched on.",
		func = function() E:ToggleConfig("blizzard") end },
	{ type = "header", label = "Inside Edit Mode" },
	{ type = "toggle", key = "showMovers", label = "Show EldoUI frames",
		desc = L["EldoUI's frames can be dragged inside Blizzard's Edit Mode."], disabled = E:BlizzardNeeds("edit-mode", "improve") },
	{ type = "toggle", key = "fullTools", label = "Full EldoUI move tools",
		desc = L["EldoUI's move mode opens with Edit Mode: its panel beside Edit Mode's window, with search, exact X and Y, lock, attach, match size and test frames. Off: compact boxes with a small X and Y dialog."],
		disabled = E:BlizzardNeeds("edit-mode", "improve", function() return not M.db.showMovers and L["Needs Show EldoUI frames"] end) },
	{ type = "toggle", key = "showLabels", label = "Names on EldoUI frames",
		desc = L["Show each EldoUI frame's name on its box."], disabled = E:BlizzardNeeds("edit-mode", "improve") },
	{ type = "toggle", key = "panel", label = "EldoUI panel next to Edit Mode",
		desc = L["Lists which Blizzard frames EldoUI places, hides or replaces, and any conflicts."], disabled = E:BlizzardNeeds("edit-mode", "improve") },
	{ type = "toggle", key = "hideReplaced", label = "No selection box on replaced frames",
		desc = L["Blizzard frames that EldoUI hides or replaces can't be grabbed in Edit Mode, nor the empty Blizzard bar left behind when EldoUI carries the micro menu or bag buttons. Drag EldoUI's own box instead."], disabled = E:BlizzardNeeds("edit-mode", "improve") },
	{ type = "toggle", key = "tagMoved", label = "Mark frames EldoUI places",
		desc = L["Blizzard frames whose position EldoUI sets get a label, so you know an Edit Mode drag won't stick."], disabled = E:BlizzardNeeds("edit-mode", "improve") },
	{ type = "select", key = "snap", label = "Snap EldoUI frames to", values = SNAP_VALUES,
		desc = "For the compact boxes: edges snap to Edit Mode's grid (when it is shown, else EldoUI's grid) and to other EldoUI frames. The full move tools use Snap in their own panel. Hold Alt to place freely." },
	{ type = "range", key = "snapDistance", label = "Snap distance", min = 2, max = 30, step = 1,
		desc = "How close an edge must come before it snaps, in pixels." },
	{ type = "range", key = "nudge", label = "Nudge step", min = 1, max = 10, step = 1,
		desc = "Pixels per arrow click in the compact boxes' dialog. Hold Shift for ten times as much." },
	{ type = "header", label = "Positions" },
	{ type = "toggle", key = "perLayout", label = "Positions per Edit Mode layout",
		desc = L["Each Edit Mode layout keeps its own EldoUI frame positions. Switching layouts in Edit Mode moves EldoUI's frames too."], disabled = E:BlizzardNeeds("edit-mode", "move") },
	{ type = "execute", label = "Forget other layouts", width = 200,
		desc = "Drop the EldoUI positions saved for Edit Mode layouts; the current positions stay.",
		func = function() M:ConfirmForgetLayouts() end },
	{ type = "header", label = "Conflicts" },
	{ type = "toggle", key = "respect", label = "Keep Edit Mode's positions",
		desc = "For Blizzard frames whose Move switch is off, Edit Mode decides where they sit. EldoUI reports any frame that is anchored to an EldoUI frame anyway." },
	{ type = "toggle", key = "warnConflicts", label = "Warn when both place a frame",
		desc = "A chat line when Edit Mode opens and a frame is placed by both EldoUI and Edit Mode." },
	{ type = "execute", label = "Check now", width = 200,
		desc = "List every frame placed by both, in chat (also /eui editmode).",
		func = function() M:PrintConflicts() end },
}

---------------------------------------------------------------------------
-- Style presets: they change how Edit Mode and EldoUI share the screen,
-- so the Presets tab shows each one's line under its button.
---------------------------------------------------------------------------
E:RegisterStyles("EditMode", {
	{ key = "Integrated", title = "Integrated", desc = "EldoUI's frames, panel and labels inside Blizzard's Edit Mode; snaps to grid and frames.",
		settings = { showMovers = true, fullTools = true, showLabels = true, panel = true, hideReplaced = true, tagMoved = true,
			snap = "both", snapDistance = 10, nudge = 1, warnConflicts = true } },
	{ key = "PerLayout", title = "Per layout", desc = "Integrated, and each Edit Mode layout keeps its own EldoUI positions.",
		settings = { showMovers = true, fullTools = true, showLabels = true, panel = true, hideReplaced = true, tagMoved = true,
			snap = "both", perLayout = true, warnConflicts = true } },
	{ key = "Clean", title = "Clean", desc = "Compact boxes for EldoUI's frames inside Edit Mode, without names, labels or side panel.",
		settings = { showMovers = true, fullTools = false, showLabels = false, panel = false, hideReplaced = true, tagMoved = false,
			snap = "grid", warnConflicts = false } },
	{ key = "Precise", title = "Precise", desc = "Compact boxes, no snapping, 1-pixel nudges: place every EldoUI frame by hand.",
		settings = { showMovers = true, fullTools = false, showLabels = true, panel = true, snap = "off", nudge = 1 } },
	{ key = "Separate", title = "Separate", desc = "Blizzard's Edit Mode for Blizzard's frames only; EldoUI's frames move with /eui move.",
		settings = { showMovers = false, panel = true, hideReplaced = true, tagMoved = true, warnConflicts = true } },
}, { describe = true })
