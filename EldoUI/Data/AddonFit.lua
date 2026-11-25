-- The slots and adapters of the addon fit (Core/AddonFit.lua): which spot
-- of the layout each kind of frame takes, and how the frames of each kind
-- of addon are put there. The design and the ground rules are in the
-- engine's header.
--
-- Adapters are named after the kind of addon they place (loot, bags, the
-- waypoint arrow). The addons themselves, with their folders, frames and
-- globals and the WoW: Forever 1.60.1 release each was checked against,
-- are listed once, in the detection data below. A newer release keeps
-- working as long as the frames and functions listed there are still
-- there; a missing one leaves that addon alone, and the Other addons page
-- says so.
--
-- EldoUI never copies or changes another addon's code. Live placement
-- only moves and sizes a frame; a change to the addon's own saved position
-- is written only when the player applies it, with Undo.
local _, E = ...
local L = E.L

local Key = E.Key
local Fit = E.addonFit

-- The layer addon's network (Modules/MinimapLayer.lua). EldoUI speaks the
-- same addon messages, written from scratch, so players of either can hop
-- through the other. Checked against release 1.14.25.
E.LayerNetwork = {
	folder = "LayerSwap", slash = "LAYERSWAP", prefix = "LayerSwap",
}

---------------------------------------------------------------------------
-- Slots: the mover whose spot it is, its size on the 1440 canvas while
-- that mover is missing, and where the spot is when no point is found.
---------------------------------------------------------------------------
local function Slot(key, mover, title, box, fallback, extra)
	local slot = { mover = mover, title = title, box = box, fallback = fallback }
	for field, value in pairs(extra or {}) do slot[field] = value end
	Fit:RegisterSlot(key, slot)
end

Slot("rare", "EldoUI_RareAlert", Key("Rare card"), { 280, 88 }, { "TOP", "UIParent", "TOP", -550, -196 })
Slot("arrow", "EldoUI_WaypointArrow", Key("Waypoint arrow"), { 160, 82 }, { "TOP", "UIParent", "TOP", 0, -120 })
Slot("bags", "EldoUI_BagsAnchor", Key("Bags"), { 520, 300 }, { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -19, 330 },
	{ corner = "BOTTOMRIGHT" })
Slot("bank", "EldoUI_BankAnchor", Key("Bank"), { 520, 300 }, { "TOPLEFT", "UIParent", "TOPLEFT", 20, -120 },
	{ corner = "TOPLEFT" })
Slot("lootWindow", "EldoUI_LootAnchor", Key("Loot window"), { 240, 40 }, { "LEFT", "UIParent", "LEFT", 380, 120 })
Slot("lootRolls", "EldoUI_LootRolls", Key("Loot rolls"), { 320, 40 }, { "TOP", "UIParent", "TOP", 0, -260 })
Slot("lootFeed", "EldoUI_LootFeed", Key("Loot feed"), { 280, 24 }, { "RIGHT", "UIParent", "RIGHT", -700, 0 })
Slot("drawer", "EldoUI_Minimap", Key("Minimap buttons"), { 237, 237 }, { "TOPRIGHT", "UIParent", "TOPRIGHT", -19, -51 })
Slot("edge", "EldoUI_InfoBar", Key("Data bar"), { 2560, 32 }, { "TOP", "UIParent", "TOP", 0, 0 })
Slot("party", "EldoUI_Party", Key("Party frames"), { 180, 236 }, { "TOPLEFT", "UIParent", "TOPLEFT", 530, -457 })
Slot("raid", "EldoUI_Raid", Key("Raid frames"), { 408, 334 }, { "TOPLEFT", "UIParent", "TOPLEFT", 19, -504 })
Slot("swingMain", "EldoUI_SwingMainHand", Key("Swing timer"), { 240, 14 }, { "CENTER", "UIParent", "CENTER", 0, -384 })
Slot("swingOff", "EldoUI_SwingOffHand", Key("Off hand swing timer"), { 240, 14 }, { "CENTER", "UIParent", "CENTER", 0, -404 })
Slot("swingRanged", "EldoUI_SwingRanged", Key("Ranged swing timer"), { 240, 14 }, { "CENTER", "UIParent", "CENTER", 0, -424 })
-- RestedXP's active items and targets: spots of their own, right of the
-- guide spot. Their movers are the Integrations module's (they hang on the
-- "RestedXP Guide" mover), so every layout puts them beside its guide.
Slot("rxpItems", "EldoUI_RXPItems", Key("RestedXP active items"), { 120, 40 }, { "TOPLEFT", "UIParent", "TOPLEFT", 330, -42 })
Slot("rxpTargets", "EldoUI_RXPTargets", Key("RestedXP targets"), { 180, 40 }, { "TOPLEFT", "UIParent", "TOPLEFT", 330, -90 })
for index = 1, 6 do
	Slot("aura" .. index, "EldoUI_AuraGroup" .. index, Key("Aura icons"), { 240, 60 },
		{ "CENTER", "UIParent", "CENTER", -320, 200 - (index - 1) * 64 })
end

---------------------------------------------------------------------------
-- Detection data: the addons the adapters place, by adapter. `folder` is
-- the addon's folder, `name` its name on the Other addons page, `version`
-- the release checked; the other fields are the globals, frames, modules
-- and functions the adapter reads (a `%s` or `%d` is filled in by it).
---------------------------------------------------------------------------
local ADDONS = {
	loot = { folder = "XLoot", name = "XLoot", version = "12.18.5",
		addon = "XLoot", window = "XLootFrame",
		-- The dependent toast part is inventoried under the same parent. It
		-- has no separate placement adapter or conflict row.
		parts = { window = "XLoot_Frame", rolls = "XLoot_Group", feed = "XLoot_Monitor", toasts = "XLoot_Toast" },
		modules = { window = "Frame", rolls = "Group", feed = "Monitor", toasts = "Toast" } },
	rarePopups = { folder = "SilverDragon", name = "SilverDragon", version = "v2026.37",
		addon = "SilverDragon", module = "ClickTarget" },
	bagList = { folder = "Bagnon", name = "Bagnon", version = "12.1.7",
		addon = "Bagnon" },
	bagWindows = { folder = "BetterBags", name = "BetterBags", version = "2026-10-25",
		bags = "BetterBagsBagBackpack", bank = "BetterBagsBagBank",
		addon = "BetterBags", events = "Events", bagKinds = { bags = "Backpack", bank = "Bank" } },
	bagViews = { folder = "Baganator", name = "Baganator", version = "856",
		addon = "Baganator", config = "BAGANATOR_CONFIG", profile = "BAGANATOR_CURRENT_PROFILE",
		window = "Baganator_%s%sViewFrame%s" },
	minimapButtons = { folder = "MinimapButtonButton", name = "MinimapButtonButton", version = "1.24.14",
		binButton = "MinimapButtonButtonButton" },
	auraIcons = { folder = "TellMeWhen", name = "TellMeWhen", version = "12.1.5",
		addon = "TMW", group = "TellMeWhen_Group%d" },
	waypointArrow = { folder = "TomTom", name = "TomTom", version = "v4.3.13",
		addon = "TomTom", arrow = "TomTomCrazyArrow", show = "ShowHideCrazyArrow" },
	dataBar = { folder = "Titan", name = "Titan Panel", version = "9.3.5",
		top = "Titan_Bar__Display_Bar", bottom = "Titan_Bar__Display_AuxBar",
		bars = "TitanBarDataVars", addon = "Titan_G" },
	groupFrames = { folder = "HealBot", name = "HealBot Continued", version = "26.10.23",
		frame = "f1_HealBot_Action", panel = 1, skins = "Healbot_Config_Skins", restore = "HealBot_Action_setPoint" },
	rareButton = { folder = "RareScanner", name = "RareScanner", version = "1.60.1.b15",
		addon = "RareScanner", foundButton = "RARESCANNER_BUTTON" },
	swingBars = { folder = "WeaponSwingTimer", name = "WeaponSwingTimer", version = "1.60.1",
		main = "WeaponSwingTimerPlayerFrame", ranged = "WeaponSwingTimerHunterAutoshotFrame",
		mainSettings = "character_player_settings", rangedSettings = "character_hunter_settings" },
	swingHands = { folder = "4everSwingTimer", name = "4everSwingTimer", version = "1.0.0-beta6",
		bar = "FourEverSwingTimerBar%s" },
	-- Placed by an EldoUI module of their own (the Integrations module and
	-- the boss warnings module); `placement` is that module's placement entry.
	damageMeter = { folder = "Details", name = "Details!", version = "Details.20261107.15402.172", placement = "details" },
	levelingGuide = { folder = "RXPGuides", name = "RestedXP", version = "v4.11.26", placement = "rxp",
		window = "RXPFrame", betaWindow = "RXPV2GuideWindow", steps = "RXPActiveStepsFrame%s" },
	-- The rest of RestedXP's classic window set; the adapter is below.
	guideParts = { folder = "RXPGuides", name = Key("RestedXP arrow and windows"), version = "v4.11.36",
		addon = "RXPGuides", arrow = "RXPG_ARROW", items = "RXPItemFrame", targets = "RXPTargetFrame",
		restore = "LoadFramePositions", resetArrow = "ResetArrowPosition" },
	stepGuide = { folder = "Guidelime", name = "Guidelime", version = "6.008", placement = "guidelime", saved = "GuidelimeDataChar" },
	bossTimers = { folder = "BigWigs", name = "BigWigs", version = "v427.6", placement = "bigwigs" },
	questHelper = { folder = "Questie", name = "Questie", version = "12.1.0", placement = "questie" },
	bossWarnings = { folder = "DBM-Core", name = "Deadly Boss Mods", version = "12.1.15", placement = "dbm" },
}

-- Registers an adapter with its addon from the detection data; `names` is
-- that entry, for the adapter's own reads and for the checks.
local function Register(id, adapter)
	local addon = ADDONS[id]
	adapter.folder, adapter.title, adapter.version, adapter.names = addon.folder, addon.name, addon.version, addon
	return E:RegisterAddonFit(id, adapter)
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Loaded(folder)
	return C_AddOns.IsAddOnLoaded(folder) and true or false
end

local function Global(name)
	return name and rawget(_G, name) or nil
end

-- An Ace3 addon object, by its registered name.
local function AceAddon(name)
	local lib = _G.LibStub and _G.LibStub("AceAddon-3.0", true)
	if not (lib and lib.GetAddon) then return nil end
	local ok, addon = pcall(lib.GetAddon, lib, name, true)
	return ok and addon or nil
end

local function AceModule(addon, name)
	if not (addon and type(addon.GetModule) == "function") then return nil end
	local ok, module = pcall(addon.GetModule, addon, name, true)
	return ok and module or nil
end

-- The profile an AceDB database uses for this character and how many other
-- characters use it too.
local function AceProfile(db)
	if type(db) ~= "table" or type(db.GetCurrentProfile) ~= "function" then return "", 0 end
	local ok, name = pcall(db.GetCurrentProfile, db)
	if not ok or type(name) ~= "string" then return "", 0 end
	local shared = 0
	local keys = type(db.sv) == "table" and type(db.sv.profileKeys) == "table" and db.sv.profileKeys or {}
	for _, profile in pairs(keys) do
		if profile == name then shared = shared + 1 end
	end
	return name, math.max(0, shared - 1)
end

local function Round(value) return math.floor(value * 10 + 0.5) / 10 end
local function RoundScale(value) return math.floor(value * 100 + 0.5) / 100 end

-- The left and top of a frame placed by the fit, in its own units (what an
-- addon saves after its own drag), or nil.
local function OwnLeftTop(frame)
	if not (frame and Fit.Usable(frame)) then return nil end
	local left, top = E.PlainCall(frame.GetLeft, frame), E.PlainCall(frame.GetTop, frame)
	if type(left) ~= "number" or type(top) ~= "number" then return nil end
	return Round(left), Round(top)
end

local function Placed(id)
	local adapter = Fit.adapters[id]
	return adapter ~= nil and adapter.state.status == "placed"
end

-- A frame's width and height in its own units, or nil while secret.
local function SizeOf(frame)
	if not (frame and Fit.Usable(frame)) then return nil end
	local width, height = E.PlainCallAll(frame.GetSize, frame)
	if type(width) ~= "number" or type(height) ~= "number" then return nil end
	return width, height
end

-- Where a frame sits, saved the way most addons save their own windows:
-- the screen corner nearest to it and the offset from that corner, in the
-- frame's own units at the given scale.
local function CornerSpot(frame, scale)
	local left, bottom, width, height = Fit.RectOf(frame)
	local screenWidth, screenHeight = E.PlainCallAll(UIParent.GetSize, UIParent)
	if not left or type(screenWidth) ~= "number" or type(screenHeight) ~= "number" then return nil end
	local xPoint, x = "LEFT", left
	if left + width / 2 > screenWidth / 2 then xPoint, x = "RIGHT", left + width - screenWidth end
	local yPoint, y = "BOTTOM", bottom
	if bottom + height / 2 > screenHeight / 2 then yPoint, y = "TOP", bottom + height - screenHeight end
	return yPoint .. xPoint, Round(x / scale), Round(y / scale)
end

-- A frame's center against the screen's center, in its own units at the
-- given scale.
local function CenterSpot(frame, scale)
	local left, bottom, width, height = Fit.RectOf(frame)
	local screenWidth, screenHeight = E.PlainCallAll(UIParent.GetSize, UIParent)
	if not left or type(screenWidth) ~= "number" or type(screenHeight) ~= "number" then return nil end
	return Round((left + width / 2 - screenWidth / 2) / scale), Round((bottom + height / 2 - screenHeight / 2) / scale)
end

-- A named frame of a loaded addon, or nil.
local function GlobalFrame(folder, name)
	return function()
		if not Loaded(folder) then return nil end
		local frame = Global(name)
		return frame and Fit.Usable(frame) and frame or nil
	end
end

---------------------------------------------------------------------------
-- Loot: the loot window, the roll bars and the loot feed, one module each.
-- Each module keeps its spot in its own AceDB namespace: the window's left
-- and top (`frame_position_x`, `frame_position_y`, used only while "snap to
-- cursor" is off), and the roll and feed anchors' left and top (`x`, `y`).
-- The window follows the cursor by default; the fit places it only while
-- the player has turned that off, and never turns it off.
---------------------------------------------------------------------------
do
	local N = ADDONS.loot

	local function Module(part)
		return AceModule(AceAddon(N.addon), N.modules[part])
	end

	local function Window()
		return Loaded(N.parts.window) and Global(N.window) or nil
	end

	local function Snaps()
		local frame = Window()
		return frame ~= nil and type(frame.opt) == "table" and frame.opt.frame_snap ~= false
	end

	local function Rolls()
		local group = Loaded(N.parts.rolls) and Module("rolls")
		return group and group.anchor or nil
	end

	-- The anchors grow up or down from their bar, as the player set them.
	local function AnchorSide(anchor)
		local data = anchor and type(anchor.data) == "table" and anchor.data or {}
		if data.direction == "down" then return "TOPLEFT", "TOPLEFT" end
		return "BOTTOMLEFT", "BOTTOMLEFT"
	end

	local function Target(part, field)
		return function()
			local module = Module(part)
			local opt = module and type(module.opt) == "table" and module.opt
			local target = opt and (field and opt[field] or opt)
			if type(target) ~= "table" then return nil end
			local addon = AceAddon(N.addon)
			return target, AceProfile(addon and addon.db)
		end
	end

	local function Apply(part)
		return function()
			local module = Module(part)
			if module and type(module.ApplyOptions) == "function" then module:ApplyOptions() end
		end
	end

	Register("loot", {
		job = "Loot",
		frames = {
			{ slot = "lootWindow", frame = Window, noScale = true,
				point = function(frame)
					local up = type(frame.opt) == "table" and frame.opt.frame_grow_upwards
					return up and "BOTTOMLEFT" or "TOPLEFT", up and "BOTTOMLEFT" or "TOPLEFT"
				end,
				free = function() if Snaps() then return Key("its window follows the cursor (its own setting)") end end },
			{ slot = "lootRolls", frame = Rolls, noScale = true, point = AnchorSide },
		},
		changes = {
			window = {
				title = Key("Loot window on the layout's loot spot"),
				On = function() return Window() ~= nil and not Snaps() and Placed("loot") end,
				Target = Target("window"),
				Wanted = function()
					local frame = Window()
					local left, top = OwnLeftTop(frame)
					if not left then return nil end
					local up = type(frame.opt) == "table" and frame.opt.frame_grow_upwards
					local bottom = up and Round(E.PlainCall(frame.GetBottom, frame) or 0) or nil
					return { frame_position_x = left, frame_position_y = up and bottom or top }
				end,
				labels = { frame_position_x = Key("Window across"), frame_position_y = Key("Window up and down") },
				Refresh = Apply("window"),
			},
			rolls = {
				title = Key("Roll bars on the layout's roll spot"),
				On = function() return Rolls() ~= nil and Placed("loot") end,
				Target = Target("rolls", "roll_anchor"),
				Wanted = function()
					local left, top = OwnLeftTop(Rolls())
					if not left then return nil end
					return { x = left, y = top }
				end,
				labels = { x = Key("Roll bars across"), y = Key("Roll bars up and down") },
				Refresh = Apply("rolls"),
			},
			feed = {
				title = Key("Loot feed on the layout's loot feed spot"),
				On = function() return Loaded(N.parts.feed) and Module("feed") ~= nil and Fit:AddonOn("loot") and Fit:Kept(Fit.adapters.loot) end,
				Target = Target("feed", "anchor"),
				-- The feed's bar has no name to place live: the spot is worked
				-- out from the slot, in the bar's own scale.
				Wanted = function()
					local module = Module("feed")
					local data = module and type(module.opt) == "table" and module.opt.anchor
					if type(data) ~= "table" then return nil end
					local frame = Fit:LaySlot("lootFeed")
					local left, bottom = Fit.RectOf(frame)
					if not left then return nil end
					local scale = tonumber(data.scale) or 1
					local down = data.direction == "down"
					local top = down and (bottom + select(4, Fit.RectOf(frame))) or (bottom + 20 * scale)
					return { x = Round(left / scale), y = Round(top / scale) }
				end,
				labels = { x = Key("Loot feed across"), y = Key("Loot feed up and down") },
				Refresh = Apply("feed"),
			},
		},
	})
end

---------------------------------------------------------------------------
-- Rare popups: they hang on one anchor a module of the addon places
-- through LibWindow-1.1 and saves in its AceDB namespace (`anchor`: point,
-- x, y, scale). The anchor has no name, so the fit reaches it through the
-- module. Popups are 276 x 96 at the anchor's scale; the box rule scales
-- them through their own post-hooked reflow (the module's public Reflow),
-- out of combat.
---------------------------------------------------------------------------
do
	local N = ADDONS.rarePopups

	local function Module()
		return AceModule(Global(N.addon), N.module)
	end

	local function Anchor()
		local module = Module()
		return module and module.anchor or nil
	end

	local function AnchorScale()
		local module = Module()
		local db = module and module.db
		local anchor = db and type(db.profile) == "table" and db.profile.anchor
		return type(anchor) == "table" and tonumber(anchor.scale) or 1
	end

	local fit, hooked = 1, false
	local function ScalePopups()
		if InCombatLockdown() then return end
		local module = Module()
		for _, popup in ipairs(module and type(module.stack) == "table" and module.stack or {}) do
			if Fit.Usable(popup) then popup:SetScale(AnchorScale() * fit) end
		end
	end

	Register("rarePopups", {
		job = "RareScanner",
		frames = {
			{ slot = "rare", frame = Anchor,
				measure = function() local scale = AnchorScale() return 276 * scale, 96 * scale end,
				scale = function(_, value)
					fit = value
					local module = Module()
					if not hooked and module and type(module.Reflow) == "function" then
						hooked = true
						hooksecurefunc(module, "Reflow", ScalePopups)
					end
					ScalePopups()
				end },
		},
		changes = {
			popup = {
				title = Key("Rare popups on the layout's rare card"),
				On = function() return Anchor() ~= nil and Placed("rarePopups") end,
				Target = function()
					local module = Module()
					local db = module and module.db
					local data = db and type(db.profile) == "table" and db.profile.anchor
					if type(data) ~= "table" then return nil end
					local addon = Global(N.addon)
					return data, AceProfile(type(addon) == "table" and addon.db)
				end,
				-- What LibWindow itself would save for the anchor where the fit
				-- put it: saved into a scratch table, then the real one again.
				Wanted = function()
					local anchor, lib = Anchor(), _G.LibStub and _G.LibStub("LibWindow-1.1", true)
					local module = Module()
					local data = module and module.db and module.db.profile and module.db.profile.anchor
					if not (anchor and lib and type(lib.RegisterConfig) == "function" and type(lib.SavePosition) == "function" and type(data) == "table") then return nil end
					local scratch = { scale = data.scale }
					local ok = pcall(lib.RegisterConfig, anchor, scratch)
					ok = ok and pcall(lib.SavePosition, anchor)
					pcall(lib.RegisterConfig, anchor, data)
					if not ok or type(scratch.point) ~= "string" then return nil end
					return { point = scratch.point, x = scratch.x, y = scratch.y, scale = Round((tonumber(data.scale) or 1) * fit * 100) / 100 }
				end,
				labels = { point = Key("Popup corner"), x = Key("Popup across"), y = Key("Popup up and down"), scale = Key("Popup scale") },
				Refresh = function()
					local module = Module()
					if module and type(module.RefreshConfig) == "function" then module:RefreshConfig() end
				end,
			},
		},
	})
end

---------------------------------------------------------------------------
-- Bags reached through a frame list: the bag and bank windows are built
-- the first time they open and reached through the addon's frame list
-- (`Frames:Get(id)`). Each keeps its spot and scale in its profile
-- (`point`, `x`, `y`, `scale`) and puts itself back there with its own
-- UpdatePosition, after which the fit places it again. The bags take the
-- layout's bag corner, the bank its bank corner.
---------------------------------------------------------------------------
do
	local N = ADDONS.bagList

	local function Window(id)
		return function()
			local addon = Global(N.addon)
			local frames = type(addon) == "table" and addon.Frames
			if type(frames) ~= "table" or type(frames.Get) ~= "function" then return nil end
			local ok, frame = pcall(frames.Get, frames, id)
			if ok and type(frame) == "table" and frame[0] and type(frame.profile) == "table" then return frame end
		end
	end

	local function OwnScale(frame)
		return tonumber(frame.profile.scale) or 1
	end

	local function Row(slot, id)
		return { slot = slot, frame = Window(id), after = { "UpdatePosition" },
			measure = function(frame)
				local width, height = SizeOf(frame)
				if not width then return nil end
				local scale = OwnScale(frame)
				return width * scale, height * scale
			end,
			scale = function(frame, fit)
				frame:SetScale(OwnScale(frame) * fit)
			end }
	end

	local function Change(slot, id, row, title)
		local Frame = Window(id)
		return {
			title = title,
			On = function() return Frame() ~= nil and Placed("bagList") and Fit.placed[slot] == "bagList" end,
			Target = function()
				local frame = Frame()
				if not frame then return nil end
				return frame.profile, "", 0
			end,
			Wanted = function()
				local frame = Frame()
				if not frame then return nil end
				local fits = Fit.adapters.bagList.state.fits
				local scale = RoundScale(OwnScale(frame) * (fits and fits[row] or 1))
				local point, x, y = CornerSpot(frame, scale)
				if not point then return nil end
				return { point = point, x = x, y = y, scale = scale }
			end,
			labels = { point = Key("Window corner"), x = Key("Window across"), y = Key("Window up and down"), scale = Key("Window scale") },
			Refresh = function()
				local frame = Frame()
				if frame and type(frame.Update) == "function" then frame:Update() end
			end,
		}
	end

	Register("bagList", {
		job = "Bags",
		frames = { Row("bags", "inventory"), Row("bank", "bank") },
		watch = { "ToggleAllBags", "OpenAllBags", "ToggleBackpack" },
		changes = {
			bags = Change("bags", "inventory", 1, Key("Bags on the layout's bag corner")),
			bank = Change("bank", "bank", 2, Key("Bank on the layout's bank corner")),
		},
	})
end

---------------------------------------------------------------------------
-- Named bag windows finish their layout after showing. A scoped public
-- notification and the bank's completed-load method place the finished window,
-- then update its live anchor cache. No saved position is written.
---------------------------------------------------------------------------
do
	local N = ADDONS.bagWindows
	local adapter, current
	local hooked = setmetatable({}, { __mode = "k" })
	local entries = {}
	local function Same(a, b)
		if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then return false end
		for i, value in ipairs(a) do
			if type(value) == "table" and i == 6 then
				if #value ~= #b[i] then return false end
				for j, point in ipairs(value) do
					for k = 1, 5 do if point[k] ~= b[i][j][k] then return false end end
				end
			elseif value ~= b[i] then return false end
		end
		return true
	end
	local function Pose(frame)
		if not Fit.Usable(frame) then return nil end
		local width, height, _, scale = Fit.Measure(frame)
		local parent = E.PlainCall(frame.GetParent, frame)
		local shown = E.PlainCall(frame.IsShown, frame)
		local count = E.PlainCall(frame.GetNumPoints, frame)
		if not width or shown ~= true or type(count) ~= "number" or count < 0 or count ~= math.floor(count)
			or width == math.huge or height == math.huge or scale == math.huge then return nil end
		local points = count == 0 and {} or Fit.PointsOf(frame)
		if not points then return nil end
		return { width, height, scale, parent, shown, points }
	end
	local function Bag(row)
		local addon = AceAddon(N.addon)
		local bags = type(addon) == "table" and addon.Bags
		local bag = type(bags) == "table" and bags[N.bagKinds[row.slot]]
		if E:IsSecret(bag) or type(bag) ~= "table" then return nil end
		if bag.frame ~= Global(N[row.slot]) or type(bag.KeepPlace) ~= "function"
			or (row.slot == "bank" and type(bag.OnBankLoaded) ~= "function") then return nil end
		return bag, addon
	end
	local function Source(scope)
		local addon, events = AceAddon(N.addon), AceModule(scope.addon, N.events)
		return addon == scope.addon and events == scope.events and type(E.db) == "table"
			and E.db == scope.db and E.profileName == scope.profile and E.db.movers == scope.movers
	end
	local function Context(scope)
		return Source(scope) and Fit:Blocked(adapter) == nil and current == scope and scope.active
	end
	local function Own(entry, release)
		local bag, addon = Bag(entry.row)
		return bag == entry.bag and addon == entry.addon and bag and bag.KeepPlace == entry.keep
			and (not hooked[bag] or hooked[bag] == bag.OnBankLoaded)
			and entry.scope and Source(entry.scope) and (release or Context(entry.scope)) and not entry.transferred
	end
	local function MoverState(row)
		local mover = E.db.movers[Fit.slots[row.slot].mover]
		if E:IsSecret(mover) then return nil end
		return { mover = mover, point = type(mover) == "table" and { unpack(mover) } or {},
			ratio = E.GetLayoutRatio and E:GetLayoutRatio() or 1 }
	end
	local function SameMover(row, saved)
		local now = MoverState(row)
		return saved and now and now.mover == saved.mover and now.ratio == saved.ratio and Same(now.point, saved.point)
	end
	local function Transfer(entry)
		entry.transferred, entry.pending, entry.write = true, nil, nil
		return false
	end
	local function Queue(bag)
		local scope = current
		if not scope or not Context(scope) then return end
		for _, entry in ipairs(entries) do
			if Bag(entry.row) == bag and not entry.transferred then
				entry.bag, entry.addon, entry.keep, entry.scope = bag, scope.addon, bag.KeepPlace, scope
				local pose = Pose(bag.frame)
				if not pose then return end
				local mover = E.db.movers[Fit.slots[entry.row.slot].mover]
				local token = { pose = pose, mover = mover, point = type(mover) == "table" and { unpack(mover) } or {} }
				if entry.pending then
					for key, value in pairs(token) do entry.pending[key] = value end
					return
				end
				entry.pending = token
				C_Timer.After(0, function()
					E:RunOutOfCombat(function()
						if entry.pending ~= token then return end
						entry.pending = nil
						if not Own(entry) then return end
						if not Same(Pose(bag.frame), token.pose)
							or E.db.movers[Fit.slots[entry.row.slot].mover] ~= token.mover
							or (type(token.mover) == "table" and not Same(token.mover, token.point)) then Transfer(entry); return end
						if Fit.encounter then return end
						Fit:PlaceAdapter(adapter, entry.row)
					end)
				end)
				return
			end
		end
	end
	local function Observe(on)
		local addon = AceAddon(N.addon)
		local events = AceModule(addon, N.events)
		if current and (not on or not Context(current)) then
			current.active = false
			current.scope:Disable()
			current = nil
			for _, entry in ipairs(entries) do entry.pending = nil end
		end
		if not on then return true end
		if current then return true end
		if not (events and type(events.NewScope) == "function" and type(events.InScope) == "function"
			and type(events.RegisterMessage) == "function") then return false end
		local scope = events:NewScope("EldoUI bag placement")
		if type(scope) ~= "table" or type(scope.Disable) ~= "function" then return false end
		local lease = { active = true, scope = scope, events = events, addon = addon,
			db = E.db, profile = E.profileName, movers = E.db.movers }
		current = lease
		for _, entry in ipairs(entries) do entry.transferred = nil end
		local ok = pcall(events.InScope, events, scope, function()
			events:RegisterMessage("bag/Rendered", function(_, bag) -- no-L: event identifier
				if not Context(lease) or E:IsSecret(bag) or type(bag) ~= "table" then return end
				-- One post-hook per native object; disabled scopes leave it inert.
				if bag == Bag(entries[2].row) and type(bag.OnBankLoaded) == "function" then
					if not hooked[bag] then
						hooksecurefunc(bag, "OnBankLoaded", Queue)
						hooked[bag] = bag.OnBankLoaded
					elseif hooked[bag] ~= bag.OnBankLoaded then return end
				end
				Queue(bag)
			end)
		end)
		if not ok then lease.active = false; scope:Disable(); current = nil; return false end
		return true
	end
	local function Row(slot)
		local row = { slot = slot, frame = GlobalFrame(N.folder, N[slot]) }
		local entry = { row = row }
		entries[#entries + 1] = entry
		row.ready = function(frame)
			local bag, addon = Bag(row)
			if not (current and Context(current) and bag and bag.frame == frame) then return false end
			entry.bag, entry.addon, entry.keep, entry.scope = bag, addon, bag.KeepPlace, current
			return not entry.transferred and Pose(frame) ~= nil
		end
		row.guard = function(frame, phase, value)
			local release = phase == "release" or entry.releasing
			if not Own(entry, release) then return Transfer(entry) end
			if phase == "begin" or phase == "release" then
				local pose = Pose(frame)
				if not pose or (phase == "release" and not Same(pose, entry.owned)) then return Transfer(entry) end
				if phase == "release" and not SameMover(row, entry.ownedContext) then return Transfer(entry) end
				entry.write, entry.releasing, entry.writeContext = pose, phase == "release", MoverState(row)
				return entry.writeContext ~= nil
			end
			if not SameMover(row, entry.writeContext) then return Transfer(entry) end
			local expected = entry.write
			if not expected then return false end
			if phase == "scale" then expected[3] = value
			elseif phase == "clear" then expected[6] = {}
			elseif phase == "point" then expected[6][#expected[6] + 1] = value end
			if not Same(Pose(frame), expected) then return Transfer(entry) end
			return true
		end
		local function Remember(frame)
			if not Own(entry, entry.releasing) or not SameMover(row, entry.writeContext) or not Same(Pose(frame), entry.write) then return Transfer(entry) end
			entry.keep(entry.bag)
			if not Own(entry, entry.releasing) or not SameMover(row, entry.writeContext) or not Same(Pose(frame), entry.write) then return Transfer(entry) end
			entry.owned, entry.ownedContext, entry.write, entry.releasing = Pose(frame), entry.writeContext, nil, nil
			return true
		end
		row.afterPlace, row.afterRelease = Remember, Remember
		return row
	end
	adapter = Register("bagWindows", {
		job = "Bags", observe = Observe,
		frames = { Row("bags"), Row("bank") },
		watch = { "ToggleAllBags", "OpenAllBags", "ToggleBackpack" },
	})
end

---------------------------------------------------------------------------
-- Minimap buttons: one button that opens the gathered minimap buttons. It
-- takes the corner of the minimap where EldoUI's own button bin sits (the
-- bin stands back while this addon is loaded). It restores its saved spot
-- only at login, so live placement is all it needs; a drag of the button
-- never moves the minimap.
---------------------------------------------------------------------------
do
	local N = ADDONS.minimapButtons
	Register("minimapButtons", {
		job = "Minimap.buttonbin",
		frames = {
			{ slot = "drawer", frame = GlobalFrame(N.folder, N.binButton), noScale = true, noPull = true,
				point = function() return "BOTTOMRIGHT", "BOTTOMRIGHT", -2, 2 end },
		},
	})
end

---------------------------------------------------------------------------
-- Aura icons: the first six icon groups of the addon's profile on the
-- layout's six aura icon spots. A group keeps its spot and scale in the
-- profile (`Groups[n].Point`: point, relativeTo, relativePoint, x, y;
-- `Scale`) and puts itself back there on each Setup, after which the fit
-- places it again. EldoUI's own aura groups run next to it: a spot whose
-- EldoUI group shows spells stays theirs. A group the player anchored to
-- another group is left alone: it follows the group it hangs on.
---------------------------------------------------------------------------
do
	local N = ADDONS.auraIcons
	local TITLES = {
		Key("Icon group 1 on the layout's first aura icons"),
		Key("Icon group 2 on the layout's second aura icons"),
		Key("Icon group 3 on the layout's third aura icons"),
		Key("Icon group 4 on the layout's fourth aura icons"),
		Key("Icon group 5 on the layout's fifth aura icons"),
		Key("Icon group 6 on the layout's sixth aura icons"),
	}

	local function Settings(index)
		local addon = Global(N.addon)
		local db = type(addon) == "table" and addon.db
		local groups = type(db) == "table" and type(db.profile) == "table" and db.profile.Groups
		local settings = type(groups) == "table" and groups[index]
		return type(settings) == "table" and settings or nil
	end

	local function OwnScale(index)
		local settings = Settings(index)
		return settings and tonumber(settings.Scale) or 1
	end

	-- On the screen itself (or on its aura spot already), not hung on another group.
	local function OnScreen(index)
		local settings = Settings(index)
		local point = settings and settings.Point
		if type(point) ~= "table" then return false end
		local to = point.relativeTo
		return to == nil or to == "UIParent" or to == "EldoUI_FitAura" .. index
	end

	-- EldoUI's aura groups run next to this addon, so an aura spot is free
	-- only while its EldoUI group is off or shows no spells.
	local function SpotUsed(index)
		local module = E.modules.AuraGroups
		if not (module and module.active and type(module.db) == "table" and type(module.db.groups) == "table") then return false end
		local group = module.db.groups["g" .. index]
		if type(group) ~= "table" or type(module.Spells) ~= "function" then return false end
		local ok, spells = pcall(module.Spells, group)
		return ok and type(spells) == "table" and #spells > 0
	end

	local function Row(index)
		return { slot = "aura" .. index, frame = GlobalFrame(N.folder, N.group:format(index)), after = { "Setup" },
			ready = function() return Settings(index) ~= nil and Settings(index).Enabled ~= false and OnScreen(index) end,
			free = function() if SpotUsed(index) then return false end end,
			measure = function(frame)
				local width, height = SizeOf(frame)
				if not width then return nil end
				local scale = OwnScale(index)
				return width * scale, height * scale
			end,
			scale = function(frame, fit)
				frame:SetScale(OwnScale(index) * fit)
			end }
	end

	local function Change(index)
		local Frame = GlobalFrame(N.folder, N.group:format(index))
		return {
			title = TITLES[index],
			On = function() return Frame() ~= nil and OnScreen(index) and Placed("auraIcons") and Fit.placed["aura" .. index] == "auraIcons" end,
			Target = function()
				local settings = Settings(index)
				if not (settings and type(settings.Point) == "table") then return nil end
				local addon = Global(N.addon)
				return settings.Point, AceProfile(type(addon) == "table" and addon.db)
			end,
			-- The center the fit gave the group, against the screen's center,
			-- at the group's own scale: it stays there without EldoUI too.
			Wanted = function()
				local x, y = CenterSpot(Frame(), OwnScale(index))
				if not x then return nil end
				return { point = "CENTER", relativePoint = "CENTER", x = x, y = y }
			end,
			labels = { point = Key("Icon group anchor"), relativePoint = Key("Icon group anchor on the screen"),
				x = Key("Icon group across"), y = Key("Icon group up and down") },
			Refresh = function()
				local addon = Global(N.addon)
				if type(addon) == "table" and type(addon.Update) == "function" then addon:Update() end
			end,
		}
	end

	local rows, changes = {}, {}
	for index = 1, 6 do
		rows[index] = Row(index)
		changes["group" .. index] = Change(index)
	end
	Register("auraIcons", { frames = rows, changes = changes })
end

---------------------------------------------------------------------------
-- Waypoint arrow: the arrow on the layout's arrow spot, its top on the
-- spot's top so the distance text below it stays inside. The addon keeps
-- the arrow's spot in its profile (`arrow.position`: point, nil, relative
-- point, x, y, against the screen) and its size in `arrow.scale`; it
-- restores the spot only on a loading screen and the scale whenever the
-- arrow shows, so the fit puts its own scale back after that.
---------------------------------------------------------------------------
do
	local N = ADDONS.waypointArrow

	local function Saved()
		local addon = Global(N.addon)
		local profile = type(addon) == "table" and type(addon.profile) == "table" and addon.profile
		return profile and type(profile.arrow) == "table" and profile.arrow or nil
	end

	local function OwnScale()
		local arrow = Saved()
		return arrow and tonumber(arrow.scale) or 1
	end

	local fit, hooked = 1, false
	local function ScaleArrow()
		local frame = Global(N.arrow)
		if InCombatLockdown() or not (frame and Fit.Usable(frame)) then return end
		frame:SetScale(OwnScale() * fit)
	end

	Register("waypointArrow", {
		job = "Waypoints",
		frames = {
			{ slot = "arrow", frame = GlobalFrame(N.folder, N.arrow), point = "TOP",
				measure = function(frame)
					local width, height = SizeOf(frame)
					if not width then return nil end
					return width * OwnScale(), height * OwnScale()
				end,
				scale = function(_, value)
					fit = value
					local addon = Global(N.addon)
					if not hooked and type(addon) == "table" and type(addon[N.show]) == "function" then
						hooked = true
						hooksecurefunc(addon, N.show, ScaleArrow)
					end
					ScaleArrow()
				end },
		},
		changes = {
			arrow = {
				title = Key("Arrow on the layout's waypoint arrow spot"),
				On = function() return Global(N.arrow) ~= nil and Fit.placed.arrow == "waypointArrow" end,
				Target = function()
					local arrow = Saved()
					if not (arrow and type(arrow.position) == "table") then return nil end
					local addon = Global(N.addon)
					return arrow.position, AceProfile(type(addon) == "table" and addon.db)
				end,
				-- The arrow's center against the screen's center, at its own scale.
				Wanted = function()
					local x, y = CenterSpot(Global(N.arrow), OwnScale())
					if not x then return nil end
					return { [1] = "CENTER", [3] = "CENTER", [4] = x, [5] = y }
				end,
				labels = { [1] = Key("Arrow anchor"), [3] = Key("Arrow anchor on the screen"), [4] = Key("Arrow across"), [5] = Key("Arrow up and down") },
			},
		},
	})
end

---------------------------------------------------------------------------
-- Bags in views: the backpack and bank windows. Both views of each (a
-- single list and categories) exist from login, named after the view and
-- the skin; the one the player uses shows. Each pair keeps one spot in the
-- profile (`bag_view_position`, `bank_view_position`: corner, x, y against
-- the screen, at the window's scale). The addon has no window scale of its
-- own, so the box rule scales the window live and the saved spot keeps
-- only the corner.
---------------------------------------------------------------------------
do
	local N = ADDONS.bagViews
	local adapter, callbacks
	local frames = {}
	local owner = {}

	local function ReadableTable(value)
		return type(value) == "table" and not E:IsSecret(value) and (not canaccesstable or canaccesstable(value))
	end

	local function Profile()
		local config = Global(N.config)
		local current = Global(N.profile)
		if not ReadableTable(config) or not ReadableTable(config.Profiles) or E:IsSecret(current) then return end
		local profiles = config.Profiles
		local selected = type(current) == "string" and profiles[current]
		if E:IsSecret(selected) then return end
		if type(selected) == "table" then
			if ReadableTable(selected) then return selected, current end
			return
		end
		if ReadableTable(profiles.DEFAULT) then return profiles.DEFAULT, "DEFAULT" end
	end

	local function Window(profile, kind, viewKey)
		if not profile then return nil end
		local skin, view = profile.current_skin, profile[viewKey]
		if E:IsSecret(skin) or E:IsSecret(view) then return nil end
		if type(skin) ~= "string" or skin == "" then skin = "blizzard" end
		view = view == "category" and "CategoryView" or "SingleView"
		local frame = Global(N.window:format(view, kind, skin))
		return not E:IsSecret(frame) and Fit.Usable(frame) and frame or nil
	end

	local function Observe(on)
		local addon = on and Global(N.addon)
		local registry = ReadableTable(addon) and addon.CallbackRegistry or nil
		if not ReadableTable(registry) or type(E:Readable(registry.RegisterCallback)) ~= "function"
			or type(E:Readable(registry.UnregisterCallback)) ~= "function" then
			registry = nil
		end
		if not E:SafeEquals(callbacks, registry) then
			local previous = callbacks
			callbacks = registry
			if ReadableTable(previous) then
				local unregister = E:Readable(previous.UnregisterCallback)
				E.PlainCall(unregister, previous, "FrameGroupSwapped", owner)
				E.PlainCall(unregister, previous, "SettingChanged", owner)
			end
			if registry then
				-- A new skin group signals before its frames are built.
				local function Schedule() if E:SafeEquals(callbacks, registry) then Fit:Schedule(0) end end
				E.PlainCall(registry.RegisterCallback, registry, "FrameGroupSwapped", Schedule, owner)
				E.PlainCall(registry.RegisterCallback, registry, "SettingChanged", function(_, key)
					if not E:IsSecret(key) and (key == "bag_view_type" or key == "bank_view_type") then Schedule() end
				end, owner)
			end
		end
		if not on then return true end

		local profile = Profile()
		local bags = Window(profile, "Backpack", "bag_view_type")
		local bank = Window(profile, "Bank", "bank_view_type")
		if bags ~= frames.bags or bank ~= frames.bank then
			-- Release while each row still points at the frame whose original
			-- position and scale the fit saved.
			if adapter.state.base then Fit:Release(adapter) end
			frames.bags, frames.bank = bags, bank
		end
		return true
	end

	local function Change(slot, kind, viewKey, key, title)
		local function PlacedWindow()
			local frame = Window(Profile(), kind, viewKey)
			return frame and frames[slot] == frame and Fit.placed[slot] == "bagViews" and frame or nil
		end
		return {
			title = title,
			On = function() return PlacedWindow() ~= nil end,
			Target = function()
				local profile, name = Profile()
				local spot = profile and profile[key]
				if not ReadableTable(spot) then return nil end
				return spot, name, 0
			end,
			-- At the window's own scale: the addon shows it at 1 without EldoUI.
			Wanted = function()
				local frame = PlacedWindow()
				if not frame then return nil end
				local point, x, y = CornerSpot(frame, 1)
				if not point then return nil end
				return { [1] = point, [2] = x, [3] = y }
			end,
			labels = { [1] = Key("Window corner"), [2] = Key("Window across"), [3] = Key("Window up and down") },
			Refresh = function()
				local addon = Global(N.addon)
				local registry = ReadableTable(addon) and addon.CallbackRegistry
				if ReadableTable(registry) then
					E.PlainCall(E:Readable(registry.TriggerEvent), registry, "SettingChanged", key)
				end
			end,
		}
	end

	adapter = Register("bagViews", {
		job = "Bags", observe = Observe,
		frames = {
			{ slot = "bags", frame = function() return frames.bags end },
			{ slot = "bank", frame = function() return frames.bank end },
		},
		changes = {
			bags = Change("bags", "Backpack", "bag_view_type", "bag_view_position", Key("Bags on the layout's bag corner")),
			bank = Change("bank", "Bank", "bank_view_type", "bank_view_position", Key("Bank on the layout's bank corner")),
		},
	})
end

---------------------------------------------------------------------------
-- Data bar: full-width bars pinned to the top or the bottom edge, 24 high.
-- They cannot be moved, and the release checked no longer pushes other
-- frames aside. Every layout keeps the bottom edge free for its data bar,
-- so the layout's spot for this addon is its bottom bar: Save the spot
-- turns that one on and the top one off (each bar's `show` in the
-- character's bar settings), with Undo.
---------------------------------------------------------------------------
do
	local N = ADDONS.dataBar

	local function Bar(name)
		local vars = Global(N.bars)
		local bar = type(vars) == "table" and vars[name]
		return type(bar) == "table" and bar or nil
	end

	local function Shown(name)
		local bar = Bar(name)
		return bar ~= nil and bar.show and true or false
	end

	local function Redraw()
		local addon = Global(N.addon)
		local bars = type(addon) == "table" and type(addon.bars) == "table" and addon.bars
		if bars and type(bars.DisplayBarsWanted) == "function" then bars.DisplayBarsWanted("EldoUI layout") end
	end

	local function Change(name, show, title, label)
		return {
			title = title,
			On = function() return Loaded(N.folder) and Bar(name) ~= nil and Fit:AddonOn("dataBar") and Fit:Kept(Fit.adapters.dataBar) end,
			Target = function()
				local bar = Bar(name)
				if not bar then return nil end
				return bar, "", 0
			end,
			Wanted = function() return { show = show } end,
			labels = { show = label },
			Describe = function(value) return value and L["On"] or L["Off"] end,
			character = true,
			Refresh = Redraw,
		}
	end

	Register("dataBar", {
		job = "InfoBar",
		frames = {
			{ slot = "edge", frame = GlobalFrame(N.folder, N.bottom), noScale = true, noPull = true,
				free = function()
					if Shown(N.top) or not Shown(N.bottom) then
						return Key("its bar is on the top edge; Save the spot moves it to the layout's data bar edge")
					end
				end,
				-- The addon keeps its bar on the bottom edge itself.
				place = function() return true end },
		},
		changes = {
			bottom = Change(N.bottom, true, Key("Bar on the layout's data bar edge"), Key("Bottom bar")),
			top = Change(N.top, false, Key("No bar on the top edge"), Key("Top bar")),
		},
	})
end

---------------------------------------------------------------------------
-- Group frames: the addon's first frame holds the party and the raid, so
-- it takes the layout's party spot in a party and the raid spot in a raid.
-- Its frames are secure: they move only out of combat. The addon keeps the
-- spot per skin (`Anchors[<skin>][1]`: FRAME, the anchor's code, 1 for
-- TOPLEFT; X and Y, percent of the screen from its lower left) and puts
-- the frame back there with its own global function, after which the fit
-- places it again. A drag of it never moves the layout's spot.
---------------------------------------------------------------------------
do
	local N = ADDONS.groupFrames

	local function Anchor()
		local skins = Global(N.skins)
		if type(skins) ~= "table" or type(skins.Anchors) ~= "table" then return nil end
		local skin = skins.Current_Skin
		local anchors = skin ~= nil and skins.Anchors[skin]
		local anchor = type(anchors) == "table" and anchors[1]
		return type(anchor) == "table" and anchor or nil, skin
	end

	local function Row(slot, raid)
		return { slot = slot, frame = GlobalFrame(N.folder, N.frame), point = "TOPLEFT", noPull = true,
			ready = function() return (IsInRaid() and true or false) == raid end }
	end

	Register("groupFrames", {
		job = "GroupFrames",
		frames = { Row("party", false), Row("raid", true) },
		watch = { N.restore },
		changes = {
			group = {
				title = Key("Group frame on the layout's party or raid spot"),
				On = function() return Global(N.frame) ~= nil and Placed("groupFrames") end,
				Target = function()
					local anchor, skin = Anchor()
					if not anchor then return nil end
					return anchor, tostring(skin), 0
				end,
				Wanted = function()
					local left, bottom, _, height = Fit.RectOf(Global(N.frame))
					local screenWidth, screenHeight = E.PlainCallAll(UIParent.GetSize, UIParent)
					if not left or type(screenWidth) ~= "number" or type(screenHeight) ~= "number" then return nil end
					local wanted = { FRAME = 1, X = Round(left / screenWidth * 1000) / 10, Y = Round((bottom + height) / screenHeight * 1000) / 10 }
					local anchor = Anchor()
					if anchor and anchor.RealFixed then wanted.RealFixed = false end
					return wanted
				end,
				labels = { FRAME = Key("Frame anchor"), X = Key("Frame across (percent of the screen)"), Y = Key("Frame up and down (percent of the screen)"),
					RealFixed = Key("Fixed pixel spot") },
				Describe = function(value)
					if value == 1 then return "TOPLEFT" end
					if type(value) == "boolean" then return value and L["On"] or L["Off"] end
					return tostring(value)
				end,
				Refresh = function()
					local restore = Global(N.restore)
					local frame = Global(N.frame)
					if type(restore) == "function" and frame and not InCombatLockdown() then pcall(restore, N.panel) end
				end,
			},
		},
	})
end

---------------------------------------------------------------------------
-- Rare button: the found button, 200 x 50 at its own scale (`display.scale`,
-- 0.8; it ignores the UI scale), on the layout's rare card. It is a secure
-- button, so it moves only out of combat. The addon keeps its left and
-- bottom in its own scale (`scannerXPos`, `scannerYPos`) and restores them
-- only at login; it sets its scale on every show, so the fit places it
-- again then.
---------------------------------------------------------------------------
do
	local N = ADDONS.rareButton

	local function Saved()
		local addon = AceAddon(N.addon)
		local db = addon and addon.db
		return type(db) == "table" and type(db.profile) == "table" and db.profile or nil, db
	end

	local function OwnScale()
		local profile = Saved()
		local display = profile and type(profile.display) == "table" and profile.display
		return display and tonumber(display.scale) or 0.8
	end

	Register("rareButton", {
		job = "RareScanner.rarealert",
		frames = {
			{ slot = "rare", frame = GlobalFrame(N.folder, N.foundButton),
				scale = function(frame, fit) frame:SetScale(OwnScale() * fit) end },
		},
		changes = {
			button = {
				title = Key("Rare button on the layout's rare card"),
				On = function() return Global(N.foundButton) ~= nil and Fit.placed.rare == "rareButton" end,
				Target = function()
					local profile, db = Saved()
					if not profile then return nil end
					return profile, AceProfile(db)
				end,
				-- Its left and bottom in its own scale, which ignores the UI scale.
				Wanted = function()
					local left, bottom = Fit.RectOf(Global(N.foundButton))
					local uiScale = E.PlainCall(UIParent.GetEffectiveScale, UIParent)
					if not left or type(uiScale) ~= "number" then return nil end
					local scale = OwnScale()
					return { scannerXPos = Round(left * uiScale / scale), scannerYPos = Round(bottom * uiScale / scale) }
				end,
				labels = { scannerXPos = Key("Button across"), scannerYPos = Key("Button up and down") },
			},
		},
	})
end

---------------------------------------------------------------------------
-- Swing bars: the player's bar on the layout's main hand row and the
-- ranged bar on its ranged row. Its target bar and cast bar have no row
-- yet and keep their own spot. Each bar keeps its spot and width in the
-- character's settings (point, rel_point, x_offset, y_offset, width,
-- against the screen); there is no scale, so Save the spot writes the
-- fitted width.
---------------------------------------------------------------------------
do
	local N = ADDONS.swingBars

	local function Change(slot, frameName, settings, title)
		local Frame = GlobalFrame(N.folder, frameName)
		return {
			title = title,
			On = function() return Frame() ~= nil and Fit.placed[slot] == "swingBars" end,
			Target = function()
				local target = Global(settings)
				if type(target) ~= "table" then return nil end
				return target, "", 0
			end,
			Wanted = function()
				local frame = Frame()
				local x, y = CenterSpot(frame, 1)
				local width = SizeOf(frame)
				if not (x and width) then return nil end
				local fits = Fit.adapters.swingBars.state.fits
				local fit = fits and fits[slot == "swingMain" and 1 or 2] or 1
				return { point = "CENTER", rel_point = "CENTER", x_offset = x, y_offset = y, width = math.floor(width * fit + 0.5) }
			end,
			labels = { point = Key("Bar anchor"), rel_point = Key("Bar anchor on the screen"), x_offset = Key("Bar across"),
				y_offset = Key("Bar up and down"), width = Key("Bar width") },
			character = true,
		}
	end

	Register("swingBars", {
		job = "CombatHUD.swing",
		frames = {
			{ slot = "swingMain", frame = GlobalFrame(N.folder, N.main) },
			{ slot = "swingRanged", frame = GlobalFrame(N.folder, N.ranged) },
		},
		changes = {
			main = Change("swingMain", N.main, N.mainSettings, Key("Player swing bar on the layout's main hand row")),
			ranged = Change("swingRanged", N.ranged, N.rangedSettings, Key("Ranged swing bar on the layout's ranged row")),
		},
	})
end

---------------------------------------------------------------------------
-- Swing bars per hand: one bar per hand (main hand, off hand, ranged),
-- built at login, on the layout's three swing rows. The addon keeps their
-- spots per Edit Mode layout and moves them only in Edit Mode, putting
-- them back after each scale change; the fit sets the scale first and the
-- spot after, so live placement is all it needs.
---------------------------------------------------------------------------
do
	local N = ADDONS.swingHands
	Register("swingHands", {
		job = "CombatHUD.swing",
		frames = {
			{ slot = "swingMain", frame = GlobalFrame(N.folder, N.bar:format("mainhand")) },
			{ slot = "swingOff", frame = GlobalFrame(N.folder, N.bar:format("offhand")) },
			{ slot = "swingRanged", frame = GlobalFrame(N.folder, N.bar:format("ranged")) },
		},
	})
end

---------------------------------------------------------------------------
-- RestedXP's arrow, active items and targets, while the Integrations
-- module places RestedXP's guide window ("RestedXP Guide" mover): with the
-- integration off, another guide picked or "Place with the layout" off,
-- EldoUI leaves all of RestedXP alone, as its page says. The arrow goes
-- right under the layout's waypoint arrow spot: EldoUI's own arrow keeps
-- that spot (a /way waypoint, Eldostar's goal, the corpse arrow of a
-- ghost), so the two never cover each other. TomTom, registered before,
-- keeps the spot when the player picked it for waypoints; RestedXP's arrow
-- then goes back where RestedXP put it. The item and target windows go on
-- their spots right of the guide, not while the guide still waits under
-- the player frame for the setup. RestedXP keeps each frame's spot in its
-- profile (`framePositions`, saved from the live points at logout and
-- when the player drags one, put back at login and on a profile switch
-- with settings:LoadFramePositions), so the fit places again after each
-- restore. A frame the player dragged before the fit placed it stays
-- where they put it until they choose the layout's spot on the Other
-- addons page. The item and target windows hold secure buttons: like
-- every move here, they wait for the end of a fight. RestedXP makes all
-- three with either of its guide windows.
---------------------------------------------------------------------------
do
	local N = ADDONS.guideParts

	local function Addon()
		local AceAddon = _G.LibStub and _G.LibStub("AceAddon-3.0", true)
		if not AceAddon then return nil end
		local ok, addon = pcall(AceAddon.GetAddon, AceAddon, N.addon, true)
		return ok and type(addon) == "table" and addon or nil
	end

	-- RestedXP putting its saved spots back: the fit places once more.
	local hooked = false
	local function Ready()
		if hooked then return true end
		local addon = Addon()
		local settings = addon and rawget(addon, "settings")
		if type(settings) ~= "table" then return true end
		hooked = true
		local function Again() Fit:Schedule(0) end
		if type(settings[N.restore]) == "function" then hooksecurefunc(settings, N.restore, Again) end
		if type(addon[N.resetArrow]) == "function" then hooksecurefunc(addon, N.resetArrow, Again) end
		return true
	end

	-- The target window has no size before its first target.
	local function ReadyWithSize(frame)
		if not Ready() then return false end
		local width, height = SizeOf(frame)
		return width ~= nil and width > 1 and height > 1
	end

	local KEPT = Key("kept where RestedXP puts it, like its guide window")

	local function Integrations()
		return E.modules and E.modules.Integrations
	end

	-- Only while the Integrations module places the guide window.
	local function GuidePlaced()
		local integrations = Integrations()
		if integrations and integrations.RXPWanted and integrations:RXPWanted() and E.movers.EldoUI_RXP then return nil end
		return KEPT
	end

	-- Beside the guide: also not while the guide waits under the player
	-- frame for the setup (its spot is empty then).
	local function BesideGuide()
		local kept = GuidePlaced()
		if kept then return kept end
		local integrations = Integrations()
		if integrations and integrations.rxpHeld then return Key("placed once the setup is done, like the guide window") end
		return nil
	end

	-- The arrow's top a little under the waypoint arrow spot.
	local function UnderSpot() return "TOP", "BOTTOM", 0, -4 end

	local adapter = Register("guideParts", {
		frames = {
			{ slot = "arrow", frame = GlobalFrame(N.folder, N.arrow), point = UnderSpot, noScale = true,
				ready = Ready, free = GuidePlaced },
			{ slot = "rxpItems", frame = GlobalFrame(N.folder, N.items), point = "TOPLEFT", noScale = true,
				ready = Ready, free = BesideGuide },
			{ slot = "rxpTargets", frame = GlobalFrame(N.folder, N.targets), point = "TOPLEFT", noScale = true,
				ready = ReadyWithSize, free = BesideGuide },
		},
	})
	-- Its name in the language shown ("RestedXP arrow and windows").
	if adapter then E:TranslateFields({ adapter }, "title") end
end

---------------------------------------------------------------------------
-- Addons a module places itself (the Integrations module and the boss
-- warnings module): the damage meter, the leveling and quest guides and the boss warnings.
-- They keep their own switches (the Integrations and boss warnings pages,
-- the setup's Other addons step); the fit only lists them with their
-- state, so the Other addons page shows every addon the layouts place.
---------------------------------------------------------------------------
local function PlacementEntry(key)
	for _, entry in ipairs(E.addonPlacements or {}) do
		if entry.key == key then return entry end
	end
end

local function Managed(key)
	return function()
		local entry = PlacementEntry(key)
		if entry and E:AddonPlacementShown(entry) then
			if key == "guidelime" or key == "rxp" then return E:AddonPlacementStatus(entry) end
			if E:GetAddonPlacement(entry) then return "managed" end
		end
		return "off"
	end
end

for _, id in ipairs({ "damageMeter", "levelingGuide", "stepGuide", "bossTimers", "questHelper", "bossWarnings" }) do
	Register(id, { managed = Managed(ADDONS[id].placement) })
end
