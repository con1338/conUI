-- Other addons that do the same job as an EldoUI module or a part of it,
-- and the modules no other addon overlaps (Core/AddonConflicts.lua has
-- the fields). Module files keep their short `conflicts` lists; this file
-- holds the entries that need more: a part of a module, an `active` check,
-- how much of the addon's job EldoUI does (`covers`) or a note.
--
-- Two facts per entry, kept apart:
--   scope   what EldoUI does while the addon is loaded: "replace" (the
--           module stands back), "overlap" (one part stands back) or
--           "alongside" (both run; they never draw the same thing twice)
--   covers  how much of the addon's job EldoUI does: "full" (the player
--           can do without the addon) or "part"
--
-- An `active` check only reads the other addon's own saved settings (it
-- never writes them) and runs protected: when it can't read them, the
-- entry counts as overlapping, which is the safe side. Leatrix Plus keeps
-- its switches in LeaPlusDB as "On" / "Off"; ElvUI keeps them in
-- ElvUI[1].private (per character) and ElvUI[1].db (profile).
local _, E = ...
local L = E.L

local Key = E.Key
local function Add(info) E:RegisterCompetitor(info) end

---------------------------------------------------------------------------
-- Leatrix Plus: many small jobs, so only the parts both do stand back.
-- Without its saved settings, only repairs and junk selling stand back.
---------------------------------------------------------------------------
local function Leatrix(key, assumed)
	return function()
		local db = _G.LeaPlusDB
		if type(db) ~= "table" then return assumed end
		return db[key] == "On"
	end
end

local LEATRIX = {
	{ "Merchant", "selljunk", Key("Selling gray items"), "AutoSellJunk", true },
	{ "Merchant", "repair", Key("Repairing at vendors"), "AutoRepairGear", true },
	{ "Loot", "fastloot", Key("Faster auto loot"), "FasterLooting" },
	{ "QoL", "duels", Key("Declining duels"), "NoDuelRequests" },
	{ "QoL", "invites", Key("Declining group invites"), "NoPartyInvites" },
	{ "QoL", "sharedquests", Key("Declining shared quests"), "NoSharedQuests" },
	{ "QoL", "restedemotes", Key("Silencing emotes while resting"), "NoRestedEmotes" },
	{ "QoL", "audiosync", Key("Following a new audio device"), "KeepAudioSynced" },
	{ "QoL", "mutesounds", Key("Muting game sounds"), "MuteGameSounds" },
	{ "QoL", "weather", Key("Weather density"), "SetWeatherDensity" },
	{ "QoL", "volume", Key("Volume panel"), "ShowVolume" },
	{ "QoL", "wowhead", Key("Wowhead links"), "ShowWowheadLinks" },
	{ "Camera", "camera", Key("Maximum camera distance"), "MaxCameraZoom" },
}
for _, row in ipairs(LEATRIX) do
	Add({ addon = "Leatrix_Plus", module = row[1], feature = row[2], scope = "overlap", label = row[3],
		active = Leatrix(row[4], row[5] or false),
		note = ("Leatrix Plus option %s does the same job."):format(row[4]) }) -- no-L (maintainer note, never shown)
end

---------------------------------------------------------------------------
-- ElvUI: a whole UI, but each of its parts can be switched off in ElvUI.
-- EldoUI's module stands back only while ElvUI's own part is on.
---------------------------------------------------------------------------
local function Elv(read)
	return function()
		local addon = _G.ElvUI
		local core = type(addon) == "table" and addon[1]
		if type(core) ~= "table" then return nil end
		return read(core.private or {}, core.db or {})
	end
end

local ELVUI = {
	Bags = function(private) return private.bags.enable end,
	ActionBars = function(private) return private.actionbar.enable end,
	UnitFrames = function(private) return private.unitframe.enable end,
	GroupFrames = function(private) return private.unitframe.enable end,
	ClassPower = function(private) return private.unitframe.enable end,
	Nameplates = function(private) return private.nameplates.enable end,
	Auras = function(private) return private.auras.enable end,
	Tooltip = function(private) return private.tooltip.enable end,
	Chat = function(private) return private.chat.enable end,
	Minimap = function(private) return private.general.minimap.enable end,
	Skins = function(private) return private.skins.blizzard.enable end,
	Character = function(private) return private.skins.blizzard.enable and private.skins.blizzard.character end,
	Social = function(private) return private.skins.blizzard.enable and private.skins.blizzard.friends end,
	CooldownManager = function(private) return private.skins.blizzard.enable and private.skins.blizzard.cooldownManager end,
	AFK = function(_, db) return db.general.afk end,
}
for module, read in pairs(ELVUI) do
	Add({ addon = "ElvUI", module = module, scope = "replace", active = Elv(read),
		note = "ElvUI's part for the same frames is switched on in ElvUI." }) -- no-L (maintainer note, never shown)
end

-- Its enhanced minimap owns the map and header unless ElvUI owns them.
local leatrixMinimap, elvMinimap = Leatrix("MinimapModder", false), Elv(ELVUI.Minimap)
Add({ addon = "Leatrix_Plus", module = "Minimap", scope = "replace", covers = "part",
	active = function()
		if not leatrixMinimap() then return false end
		return not (C_AddOns.IsAddOnLoaded("ElvUI") and E.PlainCall(elvMinimap) == true)
	end,
	note = "Leatrix Plus MinimapModder owns the map and header unless the ElvUI minimap locks it." }) -- no-L (maintainer note, never shown)

-- The loaded player component owns its frame until reload. Its enable
-- option controls Blizzard's duplicate, not the component's own frame.
Add({ addon = "TPerl_Player", module = "UnitFrames", feature = "player", scope = "overlap", exclusive = true, covers = "part",
	label = Key("Player"), note = "TPerl's loaded player component owns the player frame." }) -- no-L (maintainer note, never shown)

---------------------------------------------------------------------------
-- TradeSkillMaster: Mail and Auction House stand back only for the parts
-- TSM brings its own screens for.
---------------------------------------------------------------------------
Add({ addon = "TradeSkillMaster", module = "Mail", feature = "openall", label = "Open all",
	note = "TSM's mailing tab opens and collects mail." }) -- no-L (maintainer note, never shown)
Add({ addon = "TradeSkillMaster", module = "Mail", feature = "send", label = "Address book and quick send",
	note = "TSM's mailing tab sends mail with its own recipient lists." }) -- no-L (maintainer note, never shown)
Add({ addon = "TradeSkillMaster", module = "Auction", feature = "tabs", label = "Shopping List, Quick Sell and Cancel Undercut tabs",
	note = "TSM's own auction house screens do the same." }) -- no-L (maintainer note, never shown)
Add({ addon = "TradeSkillMaster", module = "Auction", feature = "tooltip", label = "Auction price line",
	note = "TSM adds its own price lines to item tooltips." }) -- no-L (maintainer note, never shown)

---------------------------------------------------------------------------
-- Bar addons: the micro menu and bag bar are the same Blizzard buttons, so
-- only one addon may move them (exclusive). XP and reputation bars are
-- separate bars, so both can show when the player picks EldoUI's.
---------------------------------------------------------------------------
local function BartenderModule(name)
	return function()
		local addon = _G.Bartender4
		if type(addon) ~= "table" or not addon.GetModule then return nil end
		local module = addon:GetModule(name, true)
		if not module then return false end
		return module:IsEnabled()
	end
end

Add({ addon = "Bartender4", module = "MicroMenu", feature = "micro", scope = "overlap", exclusive = true,
	label = "Micro menu", active = BartenderModule("MicroMenu"), note = "Bartender4's MicroMenu bar moves the same buttons." }) -- no-L (maintainer note, never shown)
Add({ addon = "Bartender4", module = "MicroMenu", feature = "bags", scope = "overlap", exclusive = true,
	label = "Bag bar", active = BartenderModule("BagBar"), note = "Bartender4's BagBar moves the same buttons." }) -- no-L (maintainer note, never shown)
Add({ addon = "Bartender4", module = "StatusBars", feature = "xp", scope = "overlap",
	label = "Experience bar", active = BartenderModule("StatusTrackingBar"), note = "Bartender4 places Blizzard's own status bars." }) -- no-L (maintainer note, never shown)
Add({ addon = "Dominos", module = "MicroMenu", feature = "micro", scope = "overlap", exclusive = true,
	label = "Micro menu", note = "Dominos always has a menu bar of the same buttons." }) -- no-L (maintainer note, never shown)
Add({ addon = "Dominos", module = "MicroMenu", feature = "bags", scope = "overlap", exclusive = true,
	label = "Bag bar", note = "Dominos always has a bag bar of the same buttons." }) -- no-L (maintainer note, never shown)
Add({ addon = "Dominos_Progress", module = "StatusBars", feature = "xp", scope = "overlap", exclusive = true,
	label = "Experience bar", note = "Dominos Progress draws its own experience bar." }) -- no-L (maintainer note, never shown)
Add({ addon = "EasyExperienceBar", module = "StatusBars", feature = "xp", scope = "overlap", covers = "part",
	label = "Experience bar", note = "Draws its own experience bar and shows leveling progress." }) -- no-L (maintainer note, never shown)
Add({ addon = "Dominos_Progress", module = "StatusBars", feature = "rep", scope = "overlap", exclusive = true,
	label = "Reputation bar", note = "Dominos Progress draws its own reputation bar." }) -- no-L (maintainer note, never shown)
Add({ addon = "ElvUI", module = "MicroMenu", feature = "micro", scope = "overlap", exclusive = true, label = "Micro menu", covers = "full",
	active = Elv(function(private, db) return private.actionbar.enable and db.actionbar.microbar.enabled end),
	note = "ElvUI's micro bar moves the same buttons." }) -- no-L (maintainer note, never shown)
Add({ addon = "ElvUI", module = "StatusBars", feature = "xp", scope = "overlap", label = "Experience bar", covers = "full",
	active = Elv(function(_, db) return db.databars.experience.enable end), note = "ElvUI's data bars draw their own experience bar." }) -- no-L (maintainer note, never shown)
Add({ addon = "ElvUI", module = "StatusBars", feature = "rep", scope = "overlap", label = "Reputation bar", covers = "full",
	active = Elv(function(_, db) return db.databars.reputation.enable end), note = "ElvUI's data bars draw their own reputation bar." }) -- no-L (maintainer note, never shown)

---------------------------------------------------------------------------
-- Parts that already had a "show both" switch.
---------------------------------------------------------------------------
-- Item counts per character on tooltips. Baganator (with Syndicator) and
-- BagSync keep the whole inventory of every character, which the Alts
-- window and the Bags counts do in full; Bagnon and ArkInventory only add
-- the counts to their bag addon, the part Alts does (their bags are a
-- Bags `conflicts` entry).
local COUNTS_COVER = { Baganator = "full", Syndicator = "full", BagSync = "full", Bagnon = "part", ArkInventory = "part" }
for _, addon in ipairs({ "Baganator", "Bagnon", "ArkInventory", "Syndicator", "BagSync" }) do
	Add({ addon = addon, module = "Characters", feature = "bagcounts", scope = "overlap", label = "Item counts on tooltips", covers = COUNTS_COVER[addon],
		setting = { "Characters", "countsWithBagAddons" }, note = "The addon shows its own item counts per character." }) -- no-L (maintainer note, never shown)
end
Add({ addon = "DBM-PvP", module = "Battlegrounds", feature = "bgtimers", scope = "overlap", label = "Capture and score bars",
	setting = { "Battlegrounds", "alongside" }, note = "DBM-PvP draws its own capture and score bars." }) -- no-L (maintainer note, never shown)
Add({ addon = "Capping", module = "Battlegrounds", feature = "bgtimers", scope = "overlap", label = "Capture and score bars",
	note = "Capping draws its own battleground bars (the whole module stands back for it)." }) -- no-L (maintainer note, never shown)

-- Addons that keep the minimap buttons in one place: the button bin
-- stands back while one is loaded, so the two never fight over a button.
for _, addon in ipairs({ "MinimapButtonButton", "HidingBar" }) do
	Add({ addon = addon, module = "Minimap", feature = "buttonbin", scope = "overlap", exclusive = true, covers = "full",
		label = Key("Addon button bin"), note = "Gathers the minimap buttons into its own bar." }) -- no-L (maintainer note, never shown)
end

-- Swing timer addons: Blizzard's swing bars, as EldoUI skins and places
-- them, stand back while one is kept, and the addon's own bars take the
-- layout's swing rows (Data/AddonFit.lua).
for _, row in ipairs({
	{ "WeaponSwingTimer", "Draws its own player, target and ranged swing bars." },
	{ "4everSwingTimer", "Draws its own main hand, off hand and ranged swing bars." },
}) do
	Add({ addon = row[1], module = "CombatHUD", feature = "swing", scope = "overlap", covers = "full", label = Key("Swing timer"), note = row[2] }) -- no-L (maintainer note, never shown)
end

Add({ addon = "ThreatClassic2", module = "CombatHUD", feature = "threat", scope = "overlap", covers = "part", label = Key("Threat"),
	note = "Draws its own threat meter." }) -- no-L (maintainer note, never shown)

local function CastSparkEnabled()
	local db = rawget(_G, "FiveSecondRule_Character")
	if E:IsSecret(db) or type(db) ~= "table" then return nil end
	local enabled = rawget(db, "enabled")
	if E:IsSecret(enabled) or type(enabled) ~= "boolean" then return nil end
	return enabled
end
Add({ addon = "FiveSecondRule", module = "ClassPower", feature = "fiveSecond", scope = "overlap", covers = "part",
	label = Key("Five-second rule spark"), active = CastSparkEnabled,
	note = "Draws its own five-second rule timer." }) -- no-L (maintainer note, never shown)

local function ComboDisplayEnabled()
	local core = rawget(_G, "NugComboBar")
	if E:IsSecret(core) or type(core) ~= "table" then return nil end
	local getter = rawget(core, "IsDisabled")
	if type(getter) ~= "function" then return nil end
	local disabled = getter(core)
	if E:IsSecret(disabled) or type(disabled) ~= "boolean" then return nil end
	if disabled then return false end
	local _, class = UnitClass("player")
	if E:IsSecret(class) or type(class) ~= "string" then return nil end
	local db = rawget(core, "db")
	if E:IsSecret(db) or type(db) ~= "table" then return nil end
	local global = rawget(db, "global")
	if E:IsSecret(global) or type(global) ~= "table" then return nil end
	local configs = rawget(global, "classConfig")
	if E:IsSecret(configs) or type(configs) ~= "table" then return nil end
	local row = rawget(configs, class)
	if E:IsSecret(row) or type(row) ~= "table" then return nil end
	-- Forever selects the first configuration slot.
	local config = rawget(row, 1)
	if E:IsSecret(config) or type(config) ~= "string" then return nil end
	if config == "ComboPointsRogueClassic" or config == "ComboPointsDruid" then return true end
	if config == "ShapeshiftDruid" then
		local getForm = rawget(_G, "GetShapeshiftFormID")
		if type(getForm) ~= "function" then return nil end
		local form = getForm()
		local cat = rawget(_G, "DRUID_CAT_FORM") or rawget(_G, "CAT_FORM") or 1
		if E:IsSecret(form) or E:IsSecret(cat) or type(form) ~= "number" or type(cat) ~= "number" then return nil end
		if form == cat then return true end
	end
	return nil
end
Add({ addon = "NugComboBar", module = "ClassPower", feature = "combo", scope = "overlap", covers = "part",
	label = Key("Combo points"), active = ComboDisplayEnabled,
	note = "Draws the selected combo-point display; other resources stay independent." }) -- no-L (maintainer note, never shown)

local RESOURCE_FILTERS = {
	MANA = "Mana", RAGE = "Rage", ENERGY = "Energy", FOCUS = "Focus", RUNIC_POWER = "RunicPower",
	FURY = "Fury", INSANITY = "Insanity", MAELSTROM = "Maelstrom", LUNAR_POWER = "LunarPower",
}
local function ResourceDisplayEnabled(token)
	return function()
		local core = rawget(_G, "NugEnergy")
		if E:IsSecret(core) or type(core) ~= "table" then return nil end
		local isDisabled, getFilter = rawget(core, "IsDisabled"), rawget(core, "GetPowerFilter")
		if type(isDisabled) ~= "function" then return nil end
		local disabled = isDisabled(core)
		if E:IsSecret(disabled) or type(disabled) ~= "boolean" then return nil end
		if disabled then return false end
		if type(getFilter) ~= "function" then return nil end
		local filter, index = getFilter(core)
		if E:IsSecret(filter) or E:IsSecret(index) or type(filter) ~= "string" or type(index) ~= "number" then return nil end
		local enumKey = RESOURCE_FILTERS[filter]
		local types = Enum and Enum.PowerType
		local expected = types and enumKey and types[enumKey]
		if E:IsSecret(expected) or type(expected) ~= "number" or index ~= expected then return nil end
		return filter == token
	end
end
for _, row in ipairs({ { "MANA", "Mana" }, { "RAGE", "Rage" }, { "ENERGY", "Energy" } }) do
	Add({ addon = "NugEnergy", module = "ClassPower", feature = row[1], scope = "overlap", covers = "part",
		label = Key(row[2]), active = ResourceDisplayEnabled(row[1]),
		note = "Draws the selected resource; other resource types stay independent." }) -- no-L (maintainer note, never shown)
end
-- A resource bar addon that draws the class's own resource: each resource
-- bar it can draw stands back while it is kept.
for _, row in ipairs({ { "MANA", "Mana" }, { "RAGE", "Rage" }, { "ENERGY", "Energy" } }) do
	Add({ addon = "TwintopInsanityBar", module = "ClassPower", feature = row[1], scope = "overlap", covers = "part",
		label = Key(row[2]), note = "Draws its own resource bars for the class." }) -- no-L (maintainer note, never shown)
end

-- A flight timer addon: the flight bar stands back while it is kept; the
-- flight times are still learned.
Add({ addon = "InFlight", module = "QoL", feature = "flightbar", scope = "overlap", covers = "full", label = Key("Flight Timer"),
	note = "Draws its own flight time bar." }) -- no-L (maintainer note, never shown)

---------------------------------------------------------------------------
-- More parts that stand back (the same job done twice would show twice).
---------------------------------------------------------------------------
local function ProcButtonGlowEnabled()
	local db = rawget(_G, "SpellActivationOverlayDB")
	if E:IsSecret(db) or type(db) ~= "table" then return nil end
	local glow = rawget(db, "glow")
	if E:IsSecret(glow) or type(glow) ~= "table" then return nil end
	local enabled = rawget(glow, "enabled")
	if E:IsSecret(enabled) or type(enabled) ~= "boolean" then return nil end
	return enabled
end
Add({ addon = "SpellActivationOverlay", module = "ActionBars", feature = "procGlow", scope = "overlap", covers = "part",
	label = Key("Action bar procs"), active = ProcButtonGlowEnabled,
	note = "Draws its own action-button proc glows; central alerts are independent." }) -- no-L (maintainer note, never shown)

local function ProcAlertEnabled()
	local db = rawget(_G, "SpellActivationOverlayDB")
	if E:IsSecret(db) or type(db) ~= "table" then return nil end
	local alert = rawget(db, "alert")
	if E:IsSecret(alert) or type(alert) ~= "table" then return nil end
	local enabled = rawget(alert, "enabled")
	if E:IsSecret(enabled) or type(enabled) ~= "boolean" then return nil end
	return enabled
end
Add({ addon = "SpellActivationOverlay", module = "ActionBars", feature = "procOverlay", scope = "overlap", covers = "part",
	label = Key("Proc Alerts"), active = ProcAlertEnabled,
	note = "Uses central proc alerts; the game's alert placement and action-button glows stay separate." }) -- no-L (maintainer note, never shown)

Add({ addon = "MaxDps", module = "ActionBars", feature = "cues", scope = "overlap", covers = "part", label = Key("Spell cues"),
	note = "Draws its own overlays on the action buttons; EldoUI's spell cues stay off while it runs." }) -- no-L (maintainer note, never shown)
Add({ addon = "AutoSpellRanks", module = "ActionBars", feature = "spellranks", scope = "overlap",
	note = "Moves bars to the highest rank by itself, so the rank check has nothing to show." }) -- no-L (maintainer note, never shown)
Add({ addon = "LootPro", module = "CombatText", feature = "combattext", scope = "overlap",
	note = "Replaces the scrolling combat and loot text with its own two feeds." }) -- no-L (maintainer note, never shown)
Add({ addon = "MakeRoomClassic", module = "Merchant", feature = "selljunk", scope = "overlap", label = Key("Selling gray items"),
	note = "Sells gray items at a vendor." }) -- no-L (maintainer note, never shown)

---------------------------------------------------------------------------
-- More whole-module entries (one job, the same frames or windows):
-- { addon folder, module, covers, note }.
---------------------------------------------------------------------------
local MORE = {
	{ "NovaInstanceTracker", "Instances", "full", "Counts the hourly instance limit and logs runs." },
	{ "SavedInstances", "Instances", "full", "Lists saved instances and lockouts." },
	{ "Molinari", "BagActions", "full", "One-click milling, prospecting, disenchanting and lockpicking." },
	{ "Doom_CooldownPulse", "CooldownPulse", "full", "Shows a ready spell's icon in the middle of the screen." },
	{ "CooldownAlert", "CooldownPulse", "full", "Shows a ready spell's icon in the middle of the screen." },
	{ "MacroToolkit", "Macros", "full", "Its own macro editor window." },
	{ "!KalielsTracker", "ObjectiveTracker", "full", "Replaces the quest and objective tracker." },
	{ "OPie", "Quickdraw", "full", "Rings of spells, items and macros on a held key." },
	{ "Mapster", "Maps", "full", "World map look, size and position." },
	{ "Leatrix_Maps", "Maps", "full", "World map look, size and position." },
	{ "Carbonite", "Maps", "part", "Replaces the world map; its quest, notes and gathering parts go further than EldoUI." },
	{ "Titan", "InfoBar", "full", "A data bar along the screen edge." },
	{ "ChocolateBar", "InfoBar", "full", "A data bar along the screen edge." },
	{ "XPBarNone", "StatusBars", "full", "Its own experience and reputation bar." },
	{ "TipTop", "Tooltip", "full", "Tooltip look and position." },
	{ "ManiaTip", "Tooltip", "full", "Tooltip look and position." },
	{ "PitBull4", "UnitFrames", "full", "Player, target and party frames." },
	{ "XPerl", "UnitFrames", "full", "Player, target and party frames." },
	{ "Neuron", "ActionBars", "full", "Replaces the action bars." },
	{ "HealBot", "GroupFrames", "full", "Party and raid frames for healers." },
	{ "DandersFrames", "GroupFrames", "full", "Party and raid frames." },
	{ "NeatPlates", "Nameplates", "full", "Replaces the nameplates." },
	{ "Platynator", "Nameplates", "full", "Replaces the nameplates." },
	{ "BetterBlizzPlates", "Nameplates", "part", "Restyles the nameplates; EldoUI draws its own, not every one of its tweaks." },
	{ "Aurarium", "Auras", "full", "Its own buff and debuff frames." },
	{ "BasicMinimap", "Minimap", "part", "Moves and restyles the same minimap and its buttons." },
	{ "Skinner", "Skins", "part", "Skins the same Blizzard windows, as well as other addons." },
	{ "Chattynator", "Chat", "part", "Its own chat display uses the same chat input and buttons." },
	{ "LootsUI", "Loot", "full", "Its own loot window." },
	{ "WaypointUI", "Waypoints", "full", "Its own waypoint arrow and navigation." },
	{ "Chattery", "Chat", "full", "Restyles and reworks the chat windows." },
	{ "XanChat", "Chat", "full", "Restyles and reworks the chat windows." },
	{ "TransmogLootHelper", "Appearances", "full", "Marks the appearances you still need on items and tooltips." },
	{ "DarkMode", "Skins", "part", "Darkens Blizzard's windows; Window Skins restyle them." },
	{ "ShamanForever", "ShamanTotems", "part", "Its own shaman HUD with a totem bar." },
	{ "ForeverTotems", "ShamanTotems", "part", "Its own totem bar with timers and sets." },
	{ "ForeverQuestTint", "QuestTint", "part", "Marks new WoW: Forever quests in the quest windows." },
	-- A whole UI: each EldoUI module that draws the same frames.
	{ "AzeriteUI5_JuNNeZ_Edition", "UnitFrames", "full", "A whole UI with its own unit frames." },
	{ "AzeriteUI5_JuNNeZ_Edition", "ActionBars", "full", "A whole UI with its own action bars." },
	{ "AzeriteUI5_JuNNeZ_Edition", "Nameplates", "full", "A whole UI with its own nameplates." },
	{ "AzeriteUI5_JuNNeZ_Edition", "Minimap", "full", "A whole UI with its own minimap." },
	{ "AzeriteUI5_JuNNeZ_Edition", "Chat", "full", "A whole UI that restyles the chat windows." },
	{ "AzeriteUI5_JuNNeZ_Edition", "Tooltip", "full", "A whole UI with its own tooltips." },
	{ "AzeriteUI5_JuNNeZ_Edition", "Auras", "full", "A whole UI with its own buff frames." },
	{ "AzeriteUI5_JuNNeZ_Edition", "ObjectiveTracker", "full", "A whole UI that places the quest tracker." },
}
for _, row in ipairs(MORE) do
	Add({ addon = row[1], module = row[2], scope = "replace", covers = row[3], note = row[4] })
end

-- Only the party, pet, role and raid-group windows overlap Group Frames.
-- Separate self, target, focus and friends windows keep their own job.
local function HealingGroupWindows()
	local db = rawget(_G, "Healium")
	if E:IsSecret(db) or type(db) ~= "table" then return nil end
	local unknown = false
	for _, key in ipairs({ "ShowPartyFrame", "ShowPetsFrame", "ShowDamagersFrame", "ShowHealersFrame", "ShowTanksFrame" }) do
		local value = rawget(db, key)
		if E:IsSecret(value) then
			unknown = true
		elseif value == true then
			return true
		elseif value ~= false then
			unknown = true
		end
	end
	local groups = rawget(db, "ShowGroupFrames")
	if E:IsSecret(groups) or type(groups) ~= "table" then return nil end
	for index = 1, 8 do
		local value = rawget(groups, index)
		if E:IsSecret(value) then
			unknown = true
		elseif value == true then
			return true
		elseif value ~= nil and value ~= false then
			unknown = true
		end
	end
	if unknown then return nil end
	return false
end
Add({ addon = "Healium", module = "GroupFrames", scope = "replace", covers = "part", active = HealingGroupWindows,
	note = "Party and raid healing windows with their own spell buttons." }) -- no-L (maintainer note, never shown)

-- `conflicts` entries of a module where EldoUI does only part of the job.
Add({ addon = "AllTheThings", module = "Appearances", covers = "part",
	note = "Tracks every collectible; EldoUI covers appearances, zone quests and the loot journal." }) -- no-L (maintainer note, never shown)

---------------------------------------------------------------------------
-- Addons that run alongside: EldoUI does the same job (in full or in
-- part) on other frames, so nothing stands back and both stay on. The
-- Other addons page says so: { addon folder, module, covers, note }.
---------------------------------------------------------------------------
local ALONGSIDE = {
	{ "EasyFind", "Finder", "full", "One search box for the game's panels." },
	{ "BankStack", "Bags", "full", "Sorts and stacks bags and bank." },
	{ "BagSync", "Bags", "full", "Counts items across characters; EldoUI's bags count them too." },
	{ "BugSack", "Chat", "full", "Keeps Lua errors out of chat; EldoUI's error log passes errors on to it." },
	{ "CharacterNotes", "PlayerNotes", "full", "Notes on other players." },
	{ "Myslot", "Snapshots", "part", "Manual import and export of bars, macros and bindings; neither restores without the player choosing it." },
	{ "AccWideUILayoutSelection", "Snapshots", "part", "Synchronizes character settings account-wide. Snapshots provides player-controlled copies." },
	{ "iWillRemember", "PlayerNotes", "full", "Marks on players you grouped with." },
	{ "LagBar", "InfoBar", "full", "Latency and frame rate." },
	{ "xanDurability", "InfoBar", "full", "Durability." },
	{ "RepairBroker", "Merchant", "full", "Repairs at vendors." },
	{ "RepairBroker", "InfoBar", "full", "Repair cost on a data bar." },
	{ "xanGoldMine", "Counters", "full", "Gold earned and spent." },
	{ "xanEXP", "StatusBars", "full", "An experience display." },
	{ "xanEXP", "Farming", "full", "Experience per hour." },
	{ "MuteSoundFile", "QoL", "full", "Mutes sounds by id." },
	{ "TargetPercent", "UnitFrames", "full", "Target health in percent on Blizzard's frame." },
	{ "VitalFrame", "ClassPower", "full", "Health and power near the character." },
	{ "WorldMapPin", "Waypoints", "full", "Pins on the world map." },
	{ "Breakables", "BagActions", "full", "A bar of mill, prospect and disenchant buttons." },
	{ "MerchantPlus", "Merchant", "full", "A bigger vendor window; EldoUI's item list only changes the window when the player allows it." },
	{ "idTip", "Tooltip", "full", "Ids in tooltips." },
	{ "VendorPricePlus", "Tooltip", "full", "Vendor prices in tooltips." },
	{ "ArcLFGFilter", "Social", "full", "Group finder filters; EldoUI's filters only dim listings." },
	{ "AzeriteUI5_JuNNeZ_Edition", "Bags", "full", "A whole UI; its bags sit next to EldoUI's." },
	{ "AzeriteUI5_JuNNeZ_Edition", "Maps", "full", "A whole UI; its map changes sit next to EldoUI's." },
	{ "AllTheThings", "ZoneQuests", "part", "Quests per zone, among every collectible." },
	{ "AllTheThings", "LootGuide", "part", "Loot per boss, among every collectible." },
	{ "AtlasLootClassic", "LootGuide", "part", "Loot per boss and set in its own window." },
	{ "Hardcore", "Hardcore", "part", "Its own Hardcore run rules, checks and windows." },
	{ "EnhanceQoL", "QoL", "part", "Many small conveniences, some of them the same as EldoUI's." },
	{ "BetterBlizzAddons", "SystemUI", "part", "Sorts the AddOn list." },
	{ "BetterBlizzFrames", "UnitFrames", "part", "Tweaks Blizzard's unit frames, which EldoUI replaces." },
	{ "BetterBags_Bound", "Bags", "part", "Bound and bind-on-equip categories for its bag addon." },
	{ "BlizzHUDTweaks", "ActionBars", "part", "Fades Blizzard's HUD." },
	{ "CanOpener", "BagActions", "part", "Opens lockboxes and containers." },
	{ "Carbonite", "MapNotes", "part", "Notes on the map." },
	{ "Carbonite", "Gathering", "part", "Gathering nodes on the map." },
	{ "Carbonite", "Waypoints", "part", "Waypoints on the map." },
	{ "EditModeExpanded", "EditMode", "part", "More frames in Edit Mode." },
	{ "EquipRecommendedGear", "Upgrades", "part", "Equips the best gear in one click; EldoUI only marks upgrades." },
	{ "Farmer", "Farming", "part", "Loot and currency while farming." },
	{ "Farmer", "CombatText", "part", "Loot and currency messages." },
	{ "GatheringTracker", "Farming", "part", "Gathered materials per session." },
	{ "GatheringTracker", "Counters", "part", "Gathered material totals." },
	{ "IceHUD", "ClassPower", "part", "Curved bars around the character." },
	{ "LootPro", "Loot", "part", "Loot toasts." },
	{ "LootPro", "Merchant", "part", "Gray item selling." },
	{ "MapPinTimers", "Waypoints", "part", "Travel time to the map pin." },
	{ "MoveAny", "EditMode", "part", "Moves and scales any frame." },
	{ "NiceDamage", "CombatText", "part", "The damage text font." },
	{ "Questie", "ZoneQuests", "part", "Quest givers on the map; EldoUI's pins are off until the player turns them on." },
	{ "RightClickSelfCast", "QoL", "part", "Self cast with a right click." },
	{ "RPGLootFeed", "CombatText", "part", "A scrolling loot feed." },
	{ "RPGLootFeed", "Loot", "part", "Loot messages." },
	{ "RXPGuides", "Eldostar", "part", "Leveling guides with other guide content." },
	{ "SealTimersForever", "TrackingBars", "part", "Seal and self-buff timers." },
	{ "ShamanForever", "CombatHUD", "part", "Shields, imbues and a swing timer." },
	{ "SimpleItemLevel", "Bags", "part", "Item levels on gear icons." },
	{ "SlackersTweakSuite", "Merchant", "part", "A bigger merchant list, among other tweaks." },
	{ "TellMeWhen", "AuraGroups", "part", "Icons for buffs and procs." },
	{ "TellMeWhen", "TrackingBars", "part", "Bars for auras and cooldowns." },
	{ "TellMeWhen", "CooldownManager", "part", "Icons for cooldowns." },
	{ "TerribleBuffTracker", "Reminders", "part", "Missing buff reminders." },
	{ "TerribleBuffTracker", "Auras", "part", "A buff display." },
	{ "TitanReputation", "StatusBars", "part", "Reputation on a data bar." },
	{ "xanBuffTimers", "Auras", "part", "Buff timer bars." },
	{ "xanBuffTimers", "TrackingBars", "part", "Bars for buffs." },
}
for _, row in ipairs(ALONGSIDE) do
	Add({ addon = row[1], module = row[2], scope = "alongside", covers = row[3], note = row[4] })
end
-- Core parts that are no module: moving Blizzard's windows (only for the
-- windows the player allows) and the UI scale.
Add({ addon = "BlizzMove", feature = "windowmover", scope = "alongside", covers = "full", label = Key("Move and scale"),
	note = "Drags and scales Blizzard's windows." }) -- no-L (maintainer note, never shown)
Add({ addon = "MoveAny", feature = "windowmover", scope = "alongside", covers = "part", label = Key("Move and scale"),
	note = "Moves and scales any frame." }) -- no-L (maintainer note, never shown)
Add({ addon = "PixelPerfectUIScale", feature = "uiscale", scope = "alongside", covers = "full", label = Key("UI scale"),
	note = "Sets a pixel-perfect UI scale; the last one to set it wins." }) -- no-L (maintainer note, never shown)

-- Controller addons bind the controller's buttons themselves. While one is
-- loaded, Gamepad Mode UI only places frames: no question when a
-- controller is used, no controller key and no controller spell
-- (E:ControllerAddon, feature "controller"). ConsolePort's bar part draws
-- its own action bars, as EldoUI's Action Bars do.
Add({ addon = "ConsolePort", feature = "controller", scope = "alongside", covers = "part", label = Key("Controller play"),
	note = "Binds the controller's buttons and adds its own cursor and menus; Gamepad Mode UI only places frames." }) -- no-L (maintainer note, never shown)
Add({ addon = "ConsolePort_Bar", module = "ActionBars", scope = "replace", covers = "part",
	note = "Its own controller action bars in place of Blizzard's bars." }) -- no-L (maintainer note, never shown)

-- Rival records are independent and each addon keeps its own history.
Add({ addon = "KillOnSight", module = "Nemesis", scope = "alongside", covers = "part",
	note = "Keeps its own opposing-player list and encounter statistics." }) -- no-L (maintainer note, never shown)
Add({ addon = "WarStats", module = "Nemesis", scope = "alongside", covers = "part",
	note = "Tracks its own rivals, encounters, and combat history." }) -- no-L (maintainer note, never shown)
Add({ addon = "WarlordsForever", module = "Nemesis", scope = "alongside", covers = "part",
	note = "Keeps its own opposing-player lists and kill records." }) -- no-L (maintainer note, never shown)

-- Games on a flight path: both boxes can show; each keeps its own games.
Add({ addon = "FojjiCore_Games", module = "FlightGames", scope = "alongside", covers = "part",
	note = "Its own games box on a flight path; EldoUI's Games box shows next to it." }) -- no-L (maintainer note, never shown)

---------------------------------------------------------------------------
-- Modules no other addon overlaps, and the ones made to work with them.
---------------------------------------------------------------------------
local NONE = {
	Camp = "Forever's campfires; no other addon covers them.",
	CastFX = "Effects on EldoUI's or Blizzard's own cast bars only.",
	ChatInput = "Long messages in parts, undo and drafts; no other Forever addon does this.",
	ConsumableBar = "A one-click bar of the player's own consumables.",
	DungeonRoutes = "Classic dungeon routes; no Forever addon draws them.",
	Fanfare = "EldoUI's own sounds and effects for moments in the game.",
	Legacy = "Forever's Legacy points; no other addon plans them.",
	MageTravel = "A mage's own teleports and portals in one list.",
	MobAbilities = "What a mob cast in front of the player, from the game's own spell data.",
	Notifications = "Places and styles Blizzard's own toasts and banners.",
	RaidTools = "A bar of the game's own group tools; it shows next to any raid addon.",
	ReadyReport = "A panel of what each member is missing at a ready check.",
	SpellEfficiency = "Worked out from the spell tooltip's own numbers.",
	SplitTimer = "A leveling timer against the player's own best.",
	Streamer = "Aliases on EldoUI's own frames and chat.",
	Trade = "Trade window look and a gold trade log.",
	Transport = "Flight masters, boats and portals on the world map.",
	ZoneInfo = "Zone levels and gathering ranges on the world map.",
	ChatBubbles = "Flat speech bubbles in the EldoUI look; no Forever addon restyles them.",
	ClassBar = "One bar of the player's own class buffs, cooldowns and reagents for every class; no Forever addon draws one.",
}
for module, reason in pairs(NONE) do E:NoKnownCompetitor(module, reason) end

-- Made to work with other addons: they never stand back for them (an
-- addon that runs alongside one of them is listed above).
for _, module in ipairs({ "Integrations", "DBM", "SystemUI", "Eldostar" }) do E:MarkCompanion(module) end
