-- EldoUI Nameplates: plate size, click area and Situations.
-- Loaded right after Modules/Nameplates.lua; adds to the same module.
--
--   Plate size   Blizzard's real plate size (the clickable area and the
--                stacking room) through C_NamePlate.SetNamePlateSize. 0 x 0
--                leaves the game's size; the size the game had is kept and
--                put back. Blizzard sets the size again when its own plate
--                settings change (NamePlateDriverFrame:UpdateNamePlateSize),
--                so a post-hook queues ours again. The size Blizzard just
--                set is remembered first, so turning ours off puts back the
--                size the game uses now. Plates the game draws from script
--                are not sized by this call and keep Blizzard's size.
--   Click area   extra clickable width / height and "Friendly plates
--                click-through" through C_NamePlateManager's hit-test
--                insets (plain numbers only). The insets the game had are
--                kept for undo.
--   Situations   Blizzard's enemy / friendly plate and stacking settings per
--                kind of place (open world, dungeon, raid, battleground),
--                applied out of combat when you change zones.
--
-- Everything here is out of combat (E:RunOutOfCombat), needs the Move
-- switch (size, click area, stacking) or the Hide switch (which plates
-- show) of Blizzard UI > Nameplates, and checks each game call first: a
-- row whose call is missing stays hidden. While another plate addon is
-- loaded the module is off, so nothing here runs.
local _, E = ...
local L = E.L
local Key = E.Key
local M = E:GetModule("Nameplates")
if not M then return end

local ELEMENT = "nameplates"

local function Allowed(action) return E:BlizzardAllowed(ELEMENT, action) end

local IsSecret = E.Secret

local Plain = E.Plain

local function Number(value)
	value = Plain(value)
	return type(value) == "number" and value or nil
end

---------------------------------------------------------------------------
-- Plate size
---------------------------------------------------------------------------
local savedSize -- { width, height } the game had before EldoUI changed it
local HookDriver

local function SizeAPI()
	return C_NamePlate and C_NamePlate.SetNamePlateSize
end

local function WantedSize()
	local size = M.db and M.db.size
	local width = math.floor(tonumber(size and size.width) or 0)
	local height = math.floor(tonumber(size and size.height) or 0)
	if width <= 0 or height <= 0 then return nil end
	return width, height
end

-- The size the game uses right now (a plain pair), or nil.
local function GameSize()
	if not C_NamePlate.GetNamePlateSize then return nil end
	local ok, w, h = pcall(C_NamePlate.GetNamePlateSize)
	w, h = ok and Number(w), ok and Number(h)
	if w and h then return w, h end
end

local function SetSize()
	local api = SizeAPI()
	if not api then return end
	HookDriver()
	local width, height = WantedSize()
	local want = M.active and Allowed("move") and width
	if want then
		if not savedSize then
			local w, h = GameSize()
			if w then savedSize = { w, h } end
		end
		pcall(api, width, height)
	elseif savedSize then
		pcall(api, savedSize[1], savedSize[2])
		savedSize = nil
	end
end

function M:ApplyPlateSize()
	E:RunOutOfCombat(SetSize)
end

-- Blizzard sets its own size again after its plate settings change; ours
-- follows right after, out of combat. The size Blizzard just set becomes
-- the one to put back (reading it is allowed at any time). A size equal to
-- ours means Blizzard set none, so the remembered one stays.
local driverHooked = false
function HookDriver()
	local driver = _G.NamePlateDriverFrame
	if driverHooked or not (driver and type(driver.UpdateNamePlateSize) == "function") then return end
	driverHooked = true
	hooksecurefunc(driver, "UpdateNamePlateSize", function()
		local width, height = WantedSize()
		if not (M.active and Allowed("move") and width) then return end
		if savedSize then
			local w, h = GameSize()
			if w and not (w == width and h == height) then savedSize = { w, h } end
		end
		C_Timer.After(0, function() M:ApplyPlateSize() end)
	end)
end
E:OnBlizzardAddOn("Blizzard_NamePlates", HookDriver)

---------------------------------------------------------------------------
-- Click area
---------------------------------------------------------------------------
local FRIENDLY_THROUGH = 10000 -- insets large enough that nothing is left to click
local savedInsets = {}

local function InsetAPI()
	local api = C_NamePlateManager
	return api and api.SetNamePlateHitTestInsets and Enum and Enum.NamePlateType and api or nil
end

local function SaveInsets(api, kind)
	if savedInsets[kind] or not api.GetNamePlateHitTestInsets then return end
	local ok, left, right, top, bottom = pcall(api.GetNamePlateHitTestInsets, kind)
	if ok and Number(left) and Number(right) and Number(top) and Number(bottom) then
		savedInsets[kind] = { left, right, top, bottom }
	end
end

local function SetClickArea()
	local api = InsetAPI()
	if not api then return end
	local click = M.db and M.db.click or {}
	local width, height = tonumber(click.width) or 0, tonumber(click.height) or 0
	local on = M.active and Allowed("move")
	local friendly = Enum.NamePlateType.Friendly
	for _, kind in pairs({ Enum.NamePlateType.Enemy, friendly }) do
		local through = on and click.friendlyThrough and kind == friendly
		if through then
			SaveInsets(api, kind)
			pcall(api.SetNamePlateHitTestInsets, kind, FRIENDLY_THROUGH, FRIENDLY_THROUGH, FRIENDLY_THROUGH, FRIENDLY_THROUGH)
		elseif on and (width ~= 0 or height ~= 0) then
			SaveInsets(api, kind)
			local base = savedInsets[kind] or { 0, 0, 0, 0 }
			pcall(api.SetNamePlateHitTestInsets, kind,
				base[1] - width / 2, base[2] - width / 2, base[3] - height / 2, base[4] - height / 2)
		elseif savedInsets[kind] then
			pcall(api.SetNamePlateHitTestInsets, kind, unpack(savedInsets[kind]))
			savedInsets[kind] = nil
		end
	end
end

function M:ApplyClickArea()
	if InCombatLockdown() then
		E:RunOutOfCombat(SetClickArea)
	else
		SetClickArea()
	end
end

---------------------------------------------------------------------------
-- Situations
---------------------------------------------------------------------------
local PLACES = { none = "world", party = "dungeon", raid = "raid", pvp = "battleground", arena = "battleground" }

-- This place's values, or nil when Situations are off (or the Hide switch
-- is). Only the game's plain answer counts; unknown means no override.
function M:SituationValues()
	local situations = self.db and self.db.situations
	if not (situations and situations.enabled and Allowed("hide")) then return nil end
	local ok, inside, kind = pcall(IsInInstance)
	if not ok or IsSecret(inside) or IsSecret(kind) then return nil end
	local place = PLACES[inside and kind or "none"]
	return place and situations[place] or nil
end

---------------------------------------------------------------------------
-- /eui probe plates
---------------------------------------------------------------------------
local function Has(path)
	local value = _G
	for part in path:gmatch("[^%.]+") do
		if type(value) ~= "table" then return false end
		value = value[part]
	end
	return type(value) == "function"
end

E:RegisterProbe("plates", Key("what the game reports about nameplate size, stacking and effects"), function()
	E:Print(L["Nameplates probe:"])
	if C_NamePlate and C_NamePlate.GetNamePlateSize then
		local ok, w, h = pcall(C_NamePlate.GetNamePlateSize)
		print(("  plate size: %s x %s%s"):format(tostring(ok and Number(w) or "?"), tostring(ok and Number(h) or "?"),
			ok and (IsSecret(w) or IsSecret(h)) and " (secret)" or ""))
	else
		print("  plate size: no C_NamePlate.GetNamePlateSize")
	end
	local stacking = "missing"
	if C_CVar and C_CVar.GetCVar then
		local ok, value = pcall(C_CVar.GetCVar, "nameplateStackingTypes")
		if ok and type(value) ~= "nil" then stacking = tostring(Plain(value) or "secret") end
	end
	print(("  nameplateStackingTypes: %s, stacking rows %s"):format(stacking, M.HasStacking and M.HasStacking() and "shown" or "hidden"))
	for _, path in ipairs({ "C_NamePlate.SetNamePlateSize", "C_NamePlateManager.SetNamePlateHitTestInsets",
		"C_NamePlateManager.SetNamePlateSimplified", "UnitNameplateShowsWidgetsOnly", "UnitWidgetSet",
		"CreateUnitHealPredictionCalculator", "C_CurveUtil.CreateColorCurve", "UnitHealthPercent", "C_Spell.IsSpellImportant" }) do
		print(("  %s: %s"):format(path, Has(path) and "yes" or "no"))
	end
	local okThreat, status = pcall(UnitThreatSituation, "player", "target")
	local threat = not okThreat and "error" or IsSecret(status) and "secret" or tostring(status)
	print(("  threat on your target: %s"):format(threat))
	print(("  mode %s, effects preset %s"):format(tostring(M.GetPlateMode and M:GetPlateMode() or "?"),
		tostring(M.db and M.db.effects and M.db.effects.preset or "?")))
end)

---------------------------------------------------------------------------
-- Game settings rows: size and click area, Situations, protected settings
---------------------------------------------------------------------------
local SHOW_VALUES = { KEEP = "Game setting", ON = "On", OFF = "Off" }
local STACK_VALUES = { KEEP = "Game setting", STACK = "Stacking", OVERLAP = "Overlapping" }
local function NoMove() return not Allowed("move") end
local function MoveReason()
	return NoMove() and E:BlizzardNeedsReason(ELEMENT, "move") or false
end
local function NoHide() return not Allowed("hide") end
local function SituationsOff() return NoHide() or not (M.db and M.db.situations.enabled) end
local function NoStacking() return SituationsOff() or not (M.HasStacking and M.HasStacking()) or NoMove() end

local rows = {
	{ type = "header", label = "Size and click area" },
	{ type = "description", hidden = function() return Allowed("move") end,
		label = function() return E:BlizzardNeedsReason(ELEMENT, "move") or "" end, tone = "warning" },
	{ type = "range", unit = "px", key = "size.width", label = "Plate width", zeroText = "Game setting", min = 0, max = 300, step = 2,
		requiresAPI = "C_NamePlate.SetNamePlateSize", disabled = MoveReason,
		desc = "The real clickable plate size Blizzard uses, in pixels. Also the room plates take when they stack. 0 keeps the game's. Applied out of combat." },
	{ type = "range", unit = "px", key = "size.height", label = "Plate height", zeroText = "Game setting", min = 0, max = 100, step = 1,
		requiresAPI = "C_NamePlate.SetNamePlateSize", disabled = MoveReason,
		desc = "The real clickable plate height Blizzard uses, in pixels. Width and height both need a value. Applied out of combat." },
	{ type = "range", unit = "px", key = "click.width", label = "Extra clickable width", min = -40, max = 80, step = 2,
		requiresAPI = "C_NamePlateManager.SetNamePlateHitTestInsets", disabled = MoveReason,
		desc = "Grow (or shrink) the area you can click to target a plate." },
	{ type = "range", unit = "px", key = "click.height", label = "Extra clickable height", min = -20, max = 60, step = 2, cog = true,
		requiresAPI = "C_NamePlateManager.SetNamePlateHitTestInsets", disabled = MoveReason,
		desc = "Grow (or shrink) the clickable area up and down." },
	{ type = "toggle", key = "click.friendlyThrough", label = "Friendly plates click-through",
		requiresAPI = "C_NamePlateManager.SetNamePlateHitTestInsets", disabled = MoveReason,
		desc = "Clicks pass through friendly plates to the world behind them, so they never get in the way of a click." },
	{ type = "toggle", key = "simplifyMinor", label = "Simple plates for minor units",
		desc = "Minor (trivial) units get a name-only plate. On Blizzard plates this uses Blizzard's own simplified plate." },

	{ type = "header", label = "Situations" },
	{ type = "description", hidden = function() return Allowed("hide") end,
		label = function() return E:BlizzardNeedsReason(ELEMENT, "hide") or "" end, tone = "warning" },
	{ type = "toggle", key = "situations.enabled", label = "Settings per kind of place", hidden = NoHide,
		desc = "Blizzard's plate settings per kind of place: enemy plates, friendly plates and stacking. They win over the rows above while you are there. Applied out of combat when you change zones." },
}

local PLACE_ROWS = {
	{ key = "world", label = "Open world" },
	{ key = "dungeon", label = "Dungeons" },
	{ key = "raid", label = "Raids" },
	{ key = "battleground", label = "Battlegrounds and arenas" },
}
for _, place in ipairs(PLACE_ROWS) do
	local p = "situations." .. place.key .. "."
	rows[#rows + 1] = { type = "select", key = p .. "enemies", label = "%s: enemy plates", labelFill = place.label,
		values = SHOW_VALUES, hidden = SituationsOff,
		desc = "Blizzard's \"Enemy units\" plate setting in this kind of place. Game setting uses the row above." }
	rows[#rows + 1] = { type = "select", key = p .. "friends", label = "%s: friendly player plates", labelFill = place.label,
		values = SHOW_VALUES, hidden = SituationsOff, cog = true,
		desc = "Blizzard's \"Friendly players\" plate setting in this kind of place." }
	rows[#rows + 1] = { type = "select", key = p .. "stacking", label = "%s: enemy stacking", labelFill = place.label,
		values = STACK_VALUES, hidden = NoStacking, cog = true,
		desc = "Stacking or overlapping enemy plates in this kind of place." }
end

-- Plate distance (nameplateMaxDistance) is a secure CVar on Forever: an
-- addon can't set it (C_CVar.SetCVar refuses secure CVars), but the
-- player's own /console command can. The row only reads the value and
-- builds that command for the player to paste; EldoUI never sends it.
local DISTANCE_CVAR = "nameplateMaxDistance"
local function DistanceNow()
	if not (C_CVar and C_CVar.GetCVar) then return nil end
	local ok, value = pcall(C_CVar.GetCVar, DISTANCE_CVAR)
	value = ok and not IsSecret(value) and tonumber(value) or nil
	return value and math.floor(value + 0.5) or nil
end
local function DistanceCommand()
	local yards = M.db and tonumber(M.db.distance) or 41
	return ("/console %s %d"):format(DISTANCE_CVAR, math.floor(yards + 0.5))
end

rows[#rows + 1] = { type = "header", label = "Plate distance" }
rows[#rows + 1] = { type = "description",
	label = "Plate distance is a protected game setting: no addon can change it, but your own chat command can. Pick the yards, then copy the command." }
rows[#rows + 1] = { type = "description", hidden = function() return not DistanceNow() end,
	label = function()
		local yards = DistanceNow() or 0
		return E:Plural(yards, "Plate distance in the game now: %d yard.", "Plate distance in the game now: %d yards."):format(yards)
	end }
rows[#rows + 1] = { type = "range", key = "distance", label = "Distance", min = 10, max = 60, step = 1,
	desc = "Yards for the command below. The game keeps the value within its own limit and remembers it for this character." }
rows[#rows + 1] = { type = "execute", label = "Copy command",
	desc = "Shows the chat command for the distance above, selected for copying. Paste it in chat and press Enter.",
	func = function()
		E:ShowCopyBox(L["Plate distance"], L["Press Ctrl+C, open chat, paste the command and press Enter."], DistanceCommand())
	end }
rows[#rows + 1] = { type = "header", label = "Protected settings" }
rows[#rows + 1] = { type = "description",
	label = "Opacity behind walls and similar plate settings are protected; set them in the game's Options > Nameplates." }

for _, row in ipairs(rows) do table.insert(M.options, row) end
