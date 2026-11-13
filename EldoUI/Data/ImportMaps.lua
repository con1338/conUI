-- EldoUI foreign import maps: which keys of another UI's profile string mean
-- which EldoUI frame or setting. Core/Import.lua reads these tables; nothing
-- here runs on its own.
--
-- The key names are facts about the other addons' saved data formats
-- (EllesmereUI `!EUI_` strings, ElvUI `!E1!`/`!E2!` profile strings), read
-- from strings players exported. No code, defaults or layouts of those
-- addons are copied: a key that isn't in the pasted string is simply not
-- imported, and EldoUI keeps its own value.
--
-- Positions:  { from = <source key or path>, mover = "EldoUI_<Name>", anchor = <anchor key>,
--               title = <the name the other UI shows for it> }
-- ElvUI movers: { <ElvUI mover key>, "EldoUI_<Name>", <the name ElvUI shows for it> }
-- Settings:   { path = <source path> or get = function(data) ... end,
--               module = "<EldoUI module>" or "general", key = "<dotted EldoUI key>",
--               kind = "size" (scaled by the import factor) | "number" | "bool" | "font" | "text",
--               title = <what the preview calls it>, min/max = <the EldoUI option's range>,
--               zero = true when 0 is a real value (else 0 means "the other UI's default") }
local _, E = ...

E.importMaps = {}

---------------------------------------------------------------------------
-- EllesmereUI (`!EUI_`)
---------------------------------------------------------------------------
local UF = "addons.EllesmereUIUnitFrames."
local AB = "addons.EllesmereUIActionBars."
local RF = "addons.EllesmereUIRaidFrames."
local RB = "addons.EllesmereUIResourceBars."
local CDM = "addons.EllesmereUICooldownManager."

-- Positions are { point, relPoint, x, y } tables in EllesmereUI UIParent
-- units. `anchor` is the element's key in data.unlockLayout.anchors, used to
-- place elements that EllesmereUI attaches to another element. `when`
-- (optional) says whether the string shows that element at all; when two
-- entries feed one EldoUI frame, the first one that applies wins.
E.importMaps.euiPositions = {
	{ from = UF .. "positions.player", mover = "EldoUI_Player", anchor = "player", title = "Player Frame" },
	{ from = UF .. "positions.target", mover = "EldoUI_Target", anchor = "target", title = "Target Frame" },
	{ from = UF .. "positions.focus", mover = "EldoUI_Focus", anchor = "focus", title = "Focus Frame" },
	{ from = UF .. "positions.focustarget", mover = "EldoUI_FocusTarget", anchor = "focustarget", title = "Focus Target Frame" },
	{ from = UF .. "positions.pet", mover = "EldoUI_Pet", anchor = "pet", title = "Pet Frame" },
	{ from = UF .. "positions.targettarget", mover = "EldoUI_ToT", anchor = "targettarget", title = "Target of Target Frame" },
	{ from = UF .. "positions.boss", mover = "EldoUI_Boss", anchor = "boss", title = "Boss Frames" },
	-- The power bar of the resource bars, else the unit frames' class resource.
	{ from = RB .. "primary.unlockPos", mover = "EldoUI_PlayerPower", anchor = "ERB_Power", title = "Power Bar",
		when = function(data) return E.GetPath(data, RB .. "primary.enabled") == true end },
	{ from = UF .. "positions.classPower", mover = "EldoUI_PlayerPower", anchor = "classPower", title = "Class Resource" },
	-- The player cast bar: the unit frames' own one, else the resource bars' one.
	{ from = UF .. "positions.playerCastbar", mover = "EldoUI_PlayerCastbar", anchor = "playerCastbar", title = "Player Cast Bar",
		when = function(data) return E.GetPath(data, UF .. "player.showPlayerCastbar") == true end },
	{ from = RB .. "castBar.unlockPos", mover = "EldoUI_PlayerCastbar", anchor = "ERB_CastBar", title = "Cast Bar",
		when = function(data) return E.GetPath(data, RB .. "castBar.enabled") == true end },
	{ from = AB .. "barPositions.MainBar", mover = "EldoUI_ActionBar1", anchor = "MainBar", title = "Main Bar" },
	{ from = AB .. "barPositions.Bar2", mover = "EldoUI_ActionBar2", anchor = "Bar2", title = "Bar 2" },
	{ from = AB .. "barPositions.Bar3", mover = "EldoUI_ActionBar3", anchor = "Bar3", title = "Bar 3" },
	{ from = AB .. "barPositions.Bar4", mover = "EldoUI_ActionBar4", anchor = "Bar4", title = "Bar 4" },
	{ from = AB .. "barPositions.Bar5", mover = "EldoUI_ActionBar5", anchor = "Bar5", title = "Bar 5" },
	{ from = AB .. "barPositions.Bar6", mover = "EldoUI_ActionBar6", anchor = "Bar6", title = "Bar 6" },
	{ from = AB .. "barPositions.Bar7", mover = "EldoUI_ActionBar7", anchor = "Bar7", title = "Bar 7" },
	{ from = AB .. "barPositions.Bar8", mover = "EldoUI_ActionBar8", anchor = "Bar8", title = "Bar 8" },
	{ from = AB .. "barPositions.PetBar", mover = "EldoUI_PetBar", anchor = "PetBar", title = "Pet Bar" },
	{ from = AB .. "barPositions.StanceBar", mover = "EldoUI_StanceBar", anchor = "StanceBar", title = "Stance Bar" },
	{ from = AB .. "barPositions.ExtraActionButton", mover = "EldoUI_ExtraAbility", anchor = "ExtraActionButton", title = "Extra Action Button" },
	{ from = AB .. "barPositions.QueueStatus", mover = "EldoUI_QueueStatus", anchor = "QueueStatus", title = "Queue Status" },
	{ from = AB .. "barPositions.MicroBar", mover = "EldoUI_MicroMenu", anchor = "MicroBar", title = "Micro Bar" },
	{ from = AB .. "barPositions.BagBar", mover = "EldoUI_BagBar", anchor = "BagBar", title = "Bag Bar" },
	{ from = AB .. "barPositions.XPBar", mover = "EldoUI_XPBar", anchor = "XPBar", title = "XP Bar" },
	{ from = RF .. "partyUnlockPos", mover = "EldoUI_Party", anchor = "RF_PartyFrames", title = "Party Frames" },
	{ from = RF .. "unlockPos", mover = "EldoUI_Raid", anchor = "RF_RaidFrames", title = "Raid Frames" },
	{ from = "addons.EllesmereUIChat.chat.chatPosition", mover = "EldoUI_Chat", anchor = "ECHAT_MainChat", title = "Chat" },
	{ from = CDM .. "cdmBarPositions.cooldowns", mover = "EldoUI_Cooldowns", anchor = "CDM_cooldowns", title = "Cooldown Manager" },
	{ from = CDM .. "cdmBarPositions.utility", mover = "EldoUI_CooldownsUtility", anchor = "CDM_utility", title = "Utility Cooldowns" },
	{ from = CDM .. "cdmBarPositions.buffs", mover = "EldoUI_CooldownsBuffs", anchor = "CDM_buffs", title = "Tracked Buffs" },
	{ from = "addons.EllesmereUIMinimap.minimap.position", mover = "EldoUI_Minimap", anchor = "EBS_Minimap", title = "Minimap" },
	{ from = "addons.EllesmereUIAuraBuffReminders.unlockPos", mover = "EldoUI_Reminders", anchor = "EABR_Reminders", title = "Buff Reminders" },
}

-- Unit keys shared by the size settings below (EldoUI uses the same keys).
local EUI_UNITS = {
	{ key = "player", title = "Player Frame", mover = "EldoUI_Player" },
	{ key = "target", title = "Target Frame", mover = "EldoUI_Target" },
	{ key = "focus", title = "Focus Frame", mover = "EldoUI_Focus" },
	{ key = "focustarget", title = "Focus Target Frame", mover = "EldoUI_FocusTarget" },
	{ key = "pet", title = "Pet Frame", mover = "EldoUI_Pet" },
	{ key = "targettarget", title = "Target of Target Frame", mover = "EldoUI_ToT" },
	{ key = "boss", title = "Boss Frames", mover = "EldoUI_Boss" },
}
E.importMaps.euiUnits = EUI_UNITS

local function Sum(data, a, b)
	local x, y = E.GetPath(data, a), E.GetPath(data, b)
	if type(x) ~= "number" then return nil end
	return x + (type(y) == "number" and y or 0)
end

-- Plain settings. `title` is what the preview shows; `min`/`max` keep the
-- value inside the EldoUI option's range.
E.importMaps.euiSettings = {
	-- Theme
	{ path = "fonts.global", module = "general", key = "font", kind = "font", title = "Font" },
	{ get = function(data)
		local accent = data.euiAccent
		if type(accent) ~= "table" then return nil end
		if accent.useClass then return "class" end
		if type(accent.r) == "number" and type(accent.g) == "number" and type(accent.b) == "number" then
			return ("%02X%02X%02X"):format(accent.r * 255, accent.g * 255, accent.b * 255)
		end
	end, from = "euiAccent", module = "general", key = "accent", kind = "text", title = "Accent color" },
	-- Chat
	{ path = "addons.EllesmereUIChat.chat.chatFontSize", module = "Chat", key = "fontSize", kind = "number", title = "Chat text size", min = 8, max = 24 },
	{ path = "addons.EllesmereUIChat.chat.chatSize.w", module = "Chat", key = "width", kind = "size", title = "Chat width", min = 300, max = 1200 },
	{ path = "addons.EllesmereUIChat.chat.chatSize.h", module = "Chat", key = "height", kind = "size", title = "Chat height", min = 120, max = 800 },
	{ path = "addons.EllesmereUIChat.chat.tabHeight", module = "Chat", key = "tabHeight", kind = "size", title = "Chat tab height", min = 18, max = 40 },
	{ path = "addons.EllesmereUIChat.chat.tabFontSize", module = "Chat", key = "tabFontSize", kind = "number", title = "Chat tab text size", min = 8, max = 18 },
	-- Party and raid frames
	{ path = RF .. "partyFrameWidth", module = "GroupFrames", key = "party.width", kind = "size", title = "Party frame width", min = 40, max = 300 },
	{ path = RF .. "partyFrameHeight", module = "GroupFrames", key = "party.height", kind = "size", title = "Party frame height", min = 16, max = 120 },
	{ path = RF .. "frameWidth", module = "GroupFrames", key = "raid.width", kind = "size", title = "Raid frame width", min = 40, max = 300 },
	{ path = RF .. "frameHeight", module = "GroupFrames", key = "raid.height", kind = "size", title = "Raid frame height", min = 16, max = 120 },
	{ path = RF .. "cellSpacing", module = "GroupFrames", key = "party.spacing", kind = "size", title = "Party frame spacing", min = 0, max = 30, zero = true },
	{ path = RF .. "cellSpacing", module = "GroupFrames", key = "raid.spacing", kind = "size", title = "Raid frame spacing", min = 0, max = 30, zero = true },
	{ path = RF .. "powerHeight", module = "GroupFrames", key = "party.powerHeight", kind = "size", title = "Party power bar height", min = 0, max = 12, zero = true },
	{ path = RF .. "powerHeight", module = "GroupFrames", key = "raid.powerHeight", kind = "size", title = "Raid power bar height", min = 0, max = 12, zero = true },
	{ get = function(data)
		local hide = E.GetPath(data, RF .. "partyHideSelf")
		if type(hide) == "boolean" then return not hide end
	end, from = RF .. "partyHideSelf", module = "GroupFrames", key = "party.showPlayer", kind = "bool", title = "Party frames show you" },
	{ path = RF .. "partyShowWhenSolo", module = "GroupFrames", key = "party.showSolo", kind = "bool", title = "Party frames while solo" },
	{ get = function(data)
		local horizontal = E.GetPath(data, RF .. "partyHorizontal")
		if type(horizontal) == "boolean" then return horizontal and "RIGHT" or "DOWN" end
	end, from = RF .. "partyHorizontal", module = "GroupFrames", key = "party.growth", kind = "text", title = "Party frames grow" },
	-- Nameplates (their own scale, so not multiplied)
	-- One source size applies to each native plate type. Use current paths
	-- so the plan and its saved layout survive the plate owner's migration.
	{ path = "addons.EllesmereUINameplates.healthBarWidth", module = "Nameplates", key = "types.enemyNPC.width", kind = "number", title = "Nameplate width", min = 60, max = 250 },
	{ path = "addons.EllesmereUINameplates.healthBarHeight", module = "Nameplates", key = "types.enemyNPC.height", kind = "number", title = "Nameplate height", min = 4, max = 30 },
	{ path = "addons.EllesmereUINameplates.healthBarWidth", module = "Nameplates", key = "types.enemyPlayer.width", kind = "number", title = "Nameplate width", min = 60, max = 250 },
	{ path = "addons.EllesmereUINameplates.healthBarHeight", module = "Nameplates", key = "types.enemyPlayer.height", kind = "number", title = "Nameplate height", min = 4, max = 30 },
	{ path = "addons.EllesmereUINameplates.healthBarWidth", module = "Nameplates", key = "types.friendlyNPC.width", kind = "number", title = "Nameplate width", min = 60, max = 250 },
	{ path = "addons.EllesmereUINameplates.healthBarHeight", module = "Nameplates", key = "types.friendlyNPC.height", kind = "number", title = "Nameplate height", min = 4, max = 30 },
	{ path = "addons.EllesmereUINameplates.healthBarWidth", module = "Nameplates", key = "types.friendlyPlayer.width", kind = "number", title = "Nameplate width", min = 60, max = 250 },
	{ path = "addons.EllesmereUINameplates.healthBarHeight", module = "Nameplates", key = "types.friendlyPlayer.height", kind = "number", title = "Nameplate height", min = 4, max = 30 },
	-- Minimap
	{ path = "addons.EllesmereUIMinimap.minimap.mapSize", module = "Minimap", key = "size", kind = "size", title = "Minimap size", min = 120, max = 400 },
	{ get = function(data)
		local shape = E.GetPath(data, "addons.EllesmereUIMinimap.minimap.shape")
		if shape == "square" then return "square" end
		if shape == "round" or shape == "circle" then return "round" end
	end, from = "addons.EllesmereUIMinimap.minimap.shape", module = "Minimap", key = "shape", kind = "text", title = "Minimap shape" },
	-- Resource bars: EldoUI's Class Resources stack
	{ path = RB .. "primary.enabled", module = "ClassPower", key = "power.enabled", kind = "bool", title = "Power bar" },
	{ path = RB .. "primary.width", module = "ClassPower", key = "width", kind = "size", title = "Resource bar width", min = 100, max = 400 },
	{ path = RB .. "primary.height", module = "ClassPower", key = "power.height", kind = "size", title = "Power bar height", min = 2, max = 40 },
	{ path = RB .. "health.enabled", module = "ClassPower", key = "health.enabled", kind = "bool", title = "Health bar" },
	{ path = RB .. "health.height", module = "ClassPower", key = "health.height", kind = "size", title = "Health bar height", min = 2, max = 40 },
	{ path = RB .. "secondary.enabled", module = "ClassPower", key = "combo.enabled", kind = "bool", title = "Combo points" },
	{ path = RB .. "secondary.pipHeight", module = "ClassPower", key = "combo.height", kind = "size", title = "Combo point height", min = 2, max = 40 },
}

for _, unit in ipairs(EUI_UNITS) do
	local base = UF .. unit.key .. "."
	local target = "units." .. unit.key .. "."
	table.insert(E.importMaps.euiSettings, { path = base .. "frameWidth", module = "UnitFrames", key = target .. "width", kind = "size",
		title = unit.title .. ": width", min = 60, max = 600 })
	table.insert(E.importMaps.euiSettings, {
		get = function(data) return Sum(data, base .. "healthHeight", base .. "powerHeight") end,
		from = base .. "healthHeight + powerHeight", module = "UnitFrames", key = target .. "height", kind = "size",
		title = unit.title .. ": height", min = 14, max = 120,
	})
	table.insert(E.importMaps.euiSettings, { path = base .. "powerHeight", module = "UnitFrames", key = target .. "powerHeight", kind = "size",
		title = unit.title .. ": power bar height", min = 0, max = 30, zero = true })
end

-- Cast bars of the other unit frames: shown or not, and their size.
for _, key in ipairs({ "target", "focus", "boss" }) do
	local base = UF .. key .. "."
	local title = key == "boss" and "Boss cast bars" or (key:gsub("^%l", string.upper) .. " cast bar")
	table.insert(E.importMaps.euiSettings, { path = base .. "showCastbar", module = "UnitFrames", key = "units." .. key .. ".castbar.enabled", kind = "bool",
		title = title })
	table.insert(E.importMaps.euiSettings, { path = base .. "castbarWidth", module = "UnitFrames", key = "units." .. key .. ".castbar.width", kind = "size",
		title = title .. ": width", min = 60, max = 600 })
	table.insert(E.importMaps.euiSettings, { path = base .. "castbarHeight", module = "UnitFrames", key = "units." .. key .. ".castbar.height", kind = "size",
		title = title .. ": height", min = 8, max = 40 })
end

-- Action bars: EllesmereUI bar keys to EldoUI bar numbers. Core/Import.lua
-- reads each bar's shape, size, direction and visibility as a whole.
E.importMaps.euiBars = {
	{ key = "MainBar", index = 1, title = "Main Bar" },
	{ key = "Bar2", index = 2, title = "Bar 2" },
	{ key = "Bar3", index = 3, title = "Bar 3" },
	{ key = "Bar4", index = 4, title = "Bar 4" },
	{ key = "Bar5", index = 5, title = "Bar 5" },
	{ key = "Bar6", index = 6, title = "Bar 6" },
	{ key = "Bar7", index = 7, title = "Bar 7" },
	{ key = "Bar8", index = 8, title = "Bar 8" },
}
-- Pet and stance bars: EldoUI's special bars (`max` buttons at most).
E.importMaps.euiSpecialBars = {
	{ key = "PetBar", setting = "pet", title = "Pet Bar", max = 10, buttons = true },
	{ key = "StanceBar", setting = "stance", title = "Stance Bar", max = 10 },
}
-- Other bars: when they show (`fade`, a visibility block) and whether
-- they are on at all (`enabled`).
E.importMaps.euiOtherBars = {
	{ key = "MicroBar", module = "MicroMenu", fade = "micro.visibility", title = "Micro Bar" },
	{ key = "BagBar", module = "MicroMenu", fade = "bags.visibility", title = "Bag Bar" },
	{ key = "XPBar", module = "StatusBars", enabled = "xp.enabled", fade = "visibility", title = "XP Bar" },
	{ key = "RepBar", module = "StatusBars", enabled = "rep.enabled", title = "Reputation Bar" },
}
-- Bars EldoUI has no counterpart for.
E.importMaps.euiExtraBars = {
	{ key = "Bar9", title = "Bar 9" },
	{ key = "Bar10", title = "Bar 10" },
	{ key = "EncounterBar", title = "Encounter Bar" },
	{ key = "FavorBar", title = "Favor Bar" },
}

-- When an EllesmereUI element shows (barVisibility and friends) as an
-- EldoUI Show rule (Core/Visibility.lua). Missing values mean EldoUI has
-- no such rule.
E.importMaps.euiShow = {
	always = "always", mouseover = "mouseover", never = "never",
	in_combat = "combat", incombat = "combat", combat = "combat",
	out_of_combat = "nocombat", outofcombat = "nocombat", ooc = "nocombat",
	target = "target", has_target = "target",
}

-- Cooldown Manager bars: EllesmereUI bar key to EldoUI viewer.
E.importMaps.euiCooldownBars = {
	cooldowns = { viewer = "essential", title = "Essential cooldowns" },
	utility = { viewer = "utility", title = "Utility cooldowns" },
	buffs = { viewer = "buffIcons", title = "Tracked buffs" },
}

-- EllesmereUI data bar blocks and the EldoUI datatext that shows the same
-- thing. A function picks one from the block's own settings. Blocks
-- missing here have no EldoUI datatext and are listed as not imported.
E.importMaps.euiDataBlocks = {
	clock = "Time",
	fps = "FPS",
	ms = "Latency",
	gold = "Gold",
	durability = "Durability",
	travel = "Hearthstone",
	profession = "Profession",
	profession2 = "Profession",
	spec = "Spec",
	ilvl = "ItemLevel",
	supplies = "Ammo",
	spacer = "Spacer",
	micromenu = "Menu",
	xprep = function(settings)
		local mode = type(settings) == "table" and settings.mode
		if mode == "rep" or mode == "reputation" then return "Reputation" end
		return "XP"
	end,
}

-- EllesmereUI parts by folder, in the words the preview uses. `why` says
-- why a part isn't imported; parts without it are read above.
E.importMaps.euiModules = {
	EllesmereUIActionBars = { title = "Action bars" },
	EllesmereUIUnitFrames = { title = "Unit frames" },
	EllesmereUIRaidFrames = { title = "Party and raid frames" },
	EllesmereUIChat = { title = "Chat" },
	EllesmereUIMinimap = { title = "Minimap" },
	EllesmereUIResourceBars = { title = "Resource bars" },
	EllesmereUICooldownManager = { title = "Cooldown Manager" },
	EllesmereUINameplates = { title = "Nameplates" },
	EllesmereUIDataBars = { title = "Data bars", why = "the string has no data bars with blocks EldoUI shows" },
	EllesmereUIDamageMeters = { title = "Damage meter", why = "EldoUI places the damage meter window only" },
	EllesmereUIAuraBuffReminders = { title = "Buff reminders", why = "EldoUI places the reminders only" },
	EllesmereUIBags = { title = "Bags", why = "EldoUI's bags keep their own look" },
	EllesmereUIQoL = { title = "Quality of life extras", why = "no matching EldoUI part" },
	EllesmereUIQuestTracker = { title = "Quest tracker", why = "EldoUI's quest tracker keeps its own look" },
	EllesmereUIQuickdraw = { title = "Quickdraw", why = "EldoUI's Quickdraw keeps its own settings" },
	EllesmereUIFriends = { title = "Friends list", why = "no matching EldoUI part" },
	EllesmereUIDragonRiding = { title = "Skyriding bar", why = "no matching EldoUI part" },
	EllesmereUIMythicTimer = { title = "Mythic+ timer", why = "no matching EldoUI part" },
}

-- Parts of an EllesmereUI string that are never imported, and why.
E.importMaps.euiSkipped = {
	cdmSpells = { title = "Cooldown spell lists", why = "spell lists are EllesmereUI's own" },
	specOverrides = { title = "Per-specialization layouts", why = "EldoUI keeps one layout per profile" },
	condOverrides = { title = "Conditional layouts", why = "EldoUI keeps one layout per profile" },
	customColors = { title = "Custom colors", why = "EldoUI uses its own color tokens" },
	unlockOverrideAnchors = { title = "Extra anchor overrides", why = "EldoUI places frames from their saved positions" },
}

---------------------------------------------------------------------------
-- ElvUI (`!E1!` legacy, `!E2!` current)
---------------------------------------------------------------------------
-- profile.movers[<ElvUI mover>] = "POINT,relativeFrame,relativePoint,x,y".
-- Several ElvUI movers can feed one EldoUI mover; the first one present wins.
E.importMaps.elvMovers = {
	{ "ElvUF_PlayerMover", "EldoUI_Player", "Player Frame" },
	{ "ElvUF_TargetMover", "EldoUI_Target", "Target Frame" },
	{ "ElvUF_TargetTargetMover", "EldoUI_ToT", "Target of Target Frame" },
	{ "ElvUF_FocusMover", "EldoUI_Focus", "Focus Frame" },
	{ "ElvUF_PetMover", "EldoUI_Pet", "Pet Frame" },
	{ "BossHeaderMover", "EldoUI_Boss", "Boss Frames" },
	{ "ElvUF_PartyMover", "EldoUI_Party", "Party Frames" },
	{ "ElvUF_RaidMover", "EldoUI_Raid", "Raid Frames" },
	{ "ElvUF_Raid1Mover", "EldoUI_Raid", "Raid Frames 1" },
	{ "ElvUF_Raid2Mover", "EldoUI_Raid", "Raid Frames 2" },
	{ "ElvUF_Raid3Mover", "EldoUI_Raid", "Raid Frames 3" },
	{ "ElvUF_Raid40Mover", "EldoUI_Raid", "Raid-40 Frames" },
	{ "ElvUF_TankMover", "EldoUI_Tanks", "Tank Frames" },
	{ "ElvAB_1", "EldoUI_ActionBar1", "Action Bar 1" },
	{ "ElvAB_2", "EldoUI_ActionBar2", "Action Bar 2" },
	{ "ElvAB_3", "EldoUI_ActionBar3", "Action Bar 3" },
	{ "ElvAB_4", "EldoUI_ActionBar4", "Action Bar 4" },
	{ "ElvAB_5", "EldoUI_ActionBar5", "Action Bar 5" },
	{ "ElvAB_6", "EldoUI_ActionBar6", "Action Bar 6" },
	{ "ElvAB_7", "EldoUI_ActionBar7", "Action Bar 7" },
	{ "ElvAB_8", "EldoUI_ActionBar8", "Action Bar 8" },
	{ "PetAB", "EldoUI_PetBar", "Pet Bar" },
	{ "ShiftAB", "EldoUI_StanceBar", "Stance Bar" },
	{ "BossButton", "EldoUI_ExtraAbility", "Boss Button" },
	{ "MicrobarMover", "EldoUI_MicroMenu", "Micro Bar" },
	{ "BagsBarMover", "EldoUI_BagBar", "Bags Bar" },
	{ "LeftChatMover", "EldoUI_Chat", "Left Chat" },
	{ "RightChatMover", "EldoUI_Details", "Right Chat" },
	{ "MinimapMover", "EldoUI_Minimap", "Minimap" },
	{ "MinimapClusterMover", "EldoUI_Minimap", "Minimap Cluster" },
	{ "BuffsMover", "EldoUI_Buffs", "Player Buffs" },
	{ "ObjectiveFrameMover", "EldoUI_Quests", "Objective Frame" },
	{ "ExperienceBarMover", "EldoUI_XPBar", "Experience Bar" },
	{ "ClassBarMover", "EldoUI_PlayerPower", "Class Bar" },
	{ "AdditionalPowerMover", "EldoUI_PlayerPower", "Additional Power" },
	{ "TooltipMover", "EldoUI_Tooltip", "Tooltip" },
	{ "ElvUIBagMover", "EldoUI_BagsAnchor", "Bags" },
	{ "ElvUIBankMover", "EldoUI_BankAnchor", "Bank" },
	{ "LootFrameMover", "EldoUI_LootAnchor", "Loot Frame" },
	{ "AlertFrameMover", "EldoUI_LootToasts", "Alert Frames" },
}

-- Frames ElvUI anchors to that are the screen itself.
E.importMaps.elvScreen = { UIParent = true, ElvUIParent = true }

E.importMaps.elvSettings = {
	{ path = "general.font", module = "general", key = "font", kind = "font" },
	{ path = "general.fontSize", module = "general", key = "fontSize", kind = "number" },
	{ path = "general.minimap.size", module = "Minimap", key = "size", kind = "size" },
	{ path = "chat.panelWidth", module = "Chat", key = "width", kind = "size" },
	{ path = "chat.panelHeight", module = "Chat", key = "height", kind = "size" },
	{ path = "chat.fontSize", module = "Chat", key = "fontSize", kind = "number" },
	{ path = "chat.tabFontSize", module = "Chat", key = "tabFontSize", kind = "number" },
	{ path = "unitframe.fontSize", module = "UnitFrames", key = "fontSize", kind = "number" },
	{ path = "unitframe.units.party.width", module = "GroupFrames", key = "party.width", kind = "size" },
	{ path = "unitframe.units.party.height", module = "GroupFrames", key = "party.height", kind = "size" },
	{ get = function(data)
		for _, key in ipairs({ "raid", "raid1" }) do
			local value = E.GetPath(data, "unitframe.units." .. key .. ".width")
			if type(value) == "number" then return value end
		end
	end, from = "unitframe.units.raid(1).width", module = "GroupFrames", key = "raid.width", kind = "size" },
	{ get = function(data)
		for _, key in ipairs({ "raid", "raid1" }) do
			local value = E.GetPath(data, "unitframe.units." .. key .. ".height")
			if type(value) == "number" then return value end
		end
	end, from = "unitframe.units.raid(1).height", module = "GroupFrames", key = "raid.height", kind = "size" },
	{ path = "nameplates.plateSize.enemyWidth", module = "Nameplates", key = "width", kind = "number" },
	{ path = "nameplates.plateSize.enemyHeight", module = "Nameplates", key = "height", kind = "number" },
	{ path = "actionbar.fontSize", module = "ActionBars", key = "fontSize", kind = "number" },
}

local UNITS = { "player", "target", "focus", "pet", "targettarget", "boss" }
for _, unit in ipairs(UNITS) do
	local base = "unitframe.units." .. unit .. "."
	table.insert(E.importMaps.elvSettings, { path = base .. "width", module = "UnitFrames", key = "units." .. unit .. ".width", kind = "size" })
	table.insert(E.importMaps.elvSettings, { path = base .. "height", module = "UnitFrames", key = "units." .. unit .. ".height", kind = "size" })
	table.insert(E.importMaps.elvSettings, { path = base .. "enable", module = "UnitFrames", key = "units." .. unit .. ".enabled", kind = "bool" })
end

for index = 1, 8 do
	local base = "actionbar.bar" .. index .. "."
	local target = "bars." .. index .. "."
	-- ElvUI renamed some keys over the years; the first one present wins.
	local function First(...)
		local names = { ... }
		return function(data)
			for _, name in ipairs(names) do
				local value = E.GetPath(data, base .. name)
				if value ~= nil then return value end
			end
		end
	end
	table.insert(E.importMaps.elvSettings, { path = base .. "enabled", module = "ActionBars", key = target .. "enabled", kind = "bool" })
	table.insert(E.importMaps.elvSettings, { get = First("buttonSize", "buttonsize"), from = base .. "buttonSize", module = "ActionBars", key = target .. "size", kind = "size" })
	table.insert(E.importMaps.elvSettings, { get = First("buttonSpacing", "buttonspacing"), from = base .. "buttonSpacing", module = "ActionBars", key = target .. "spacing", kind = "size" })
	table.insert(E.importMaps.elvSettings, { path = base .. "buttons", module = "ActionBars", key = target .. "buttons", kind = "number" })
	table.insert(E.importMaps.elvSettings, { path = base .. "buttonsPerRow", module = "ActionBars", key = target .. "perRow", kind = "number" })
end

