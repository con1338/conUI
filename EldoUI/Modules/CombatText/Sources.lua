-- Combat Text feeds.
--   UNIT_COMBAT   the main feed, for the player, the pet and the target
--                 (Forever: unitTarget, event, flagText, amount, schoolMask).
--                 The action and flag pick the event when plain; with a
--                 secret action the hit is skipped, never guessed. A secret
--                 amount or school is passed on untouched.
--   COMBAT_TEXT_UPDATE  an optional extra for auras and extra attacks. The
--                 game sends it only while its own floating combat text is
--                 on; its payload (C_CombatText.GetCurrentEventInfo) is
--                 always secret, so it only ever goes to the text as is.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local M = E:GetModule("CombatText")
local issecret = M.issecret

-- Words for an action or flag (DODGE, PARRY, ...): the game's own table
-- of feedback words when it has one, else EldoUI's translations.
local WORDS = E:TranslateValues({
	DODGE = E.Key("Dodge"), PARRY = E.Key("Parry"), MISS = E.Key("Miss"), EVADE = E.Key("Evade"), IMMUNE = E.Key("Immune"),
	DEFLECT = E.Key("Deflect"), REFLECT = E.Key("Reflect"), BLOCK = E.Key("Block"), ABSORB = E.Key("Absorb"), RESIST = E.Key("Resist"),
})
function M.Word(action)
	if type(action) ~= "string" then return nil end
	local list = rawget(_G, "CombatFeedbackText")
	return (type(list) == "table" and list[action]) or WORDS[action]
end

local MITIGATE = { ABSORB = true, BLOCK = true, RESIST = true }
local AVOID = { DODGE = true, PARRY = true, MISS = true, EVADE = true, IMMUNE = true, DEFLECT = true, REFLECT = true }

-- One UNIT_COMBAT hit -> kind, payload.
--   kind: damage, crit, mitigate, avoid, heal, healCrit, energize (or nil)
-- Shared by the scroll areas, the plate numbers and frame feedback.
function M.ParseUnitCombat(action, flags, amount, school)
	if issecret(action) or type(action) ~= "string" then return nil end
	if issecret(flags) or type(flags) ~= "string" then flags = "" end
	local crit = flags == "CRITICAL"
	local secretAmount = issecret(amount)
	if action == "WOUND" then
		if secretAmount or (type(amount) == "number" and amount ~= 0) then
			return crit and "crit" or "damage", { amount = amount, school = school, crit = crit }
		end
		if MITIGATE[flags] then return "mitigate", { type = M.Word(flags) or flags } end
		return "avoid", { type = M.Word("MISS") or "Miss" }
	elseif action == "HEAL" then
		if not secretAmount and type(amount) ~= "number" then return nil end
		return crit and "healCrit" or "heal", { amount = amount, crit = crit }
	elseif action == "ENERGIZE" then
		if not secretAmount and type(amount) ~= "number" then return nil end
		return "energize", { amount = amount }
	elseif MITIGATE[action] then
		return "mitigate", { type = M.Word(action) or action }
	elseif AVOID[action] then
		return "avoid", { type = M.Word(action) or action }
	end
	return nil
end

local PLAYER_EVENTS = { damage = "inDamage", crit = "inDamageCrit", mitigate = "inMitigate", avoid = "inAvoid",
	heal = "inHeal", healCrit = "inHealCrit", energize = "energize" }
local PET_EVENTS = { damage = "petDamage", crit = "petDamage", mitigate = "petAvoid", avoid = "petAvoid",
	heal = "petHeal", healCrit = "petHeal" }
local TARGET_EVENTS = { damage = "tgtDamage", crit = "tgtCrit", mitigate = "tgtAvoid", avoid = "tgtAvoid",
	heal = "tgtHeal", healCrit = "tgtHeal" }
local MAPS = { player = PLAYER_EVENTS, pet = PET_EVENTS, target = TARGET_EVENTS }

local function OnUnitCombat(_, _, unit, action, flags, amount, school)
	local map = MAPS[unit]
	if not map then return end
	if unit == "player" then
		local probe = M.probe
		probe.seen = probe.seen + 1
		probe.secret = issecret(amount)
	end
	local kind, payload = M.ParseUnitCombat(action, flags, amount, school)
	local key = kind and map[kind]
	if key then M:Emit(key, payload) end
end

local unitListener = CreateFrame("Frame")
unitListener:SetScript("OnEvent", OnUnitCombat)
local targetListener = CreateFrame("Frame")
targetListener:SetScript("OnEvent", OnUnitCombat)

---------------------------------------------------------------------------
-- COMBAT_TEXT_UPDATE extras
---------------------------------------------------------------------------
local CTU_EVENTS = {
	AURA_START = "buff", AURA_START_HARMFUL = "debuff",
	AURA_END = "fade", AURA_END_HARMFUL = "fade",
	EXTRA_ATTACKS = "extraAttack",
}

local ctuListener = CreateFrame("Frame")
ctuListener:SetScript("OnEvent", function(_, _, kind)
	if issecret(kind) then return end
	local key = CTU_EVENTS[kind]
	if not key then return end
	local info = C_CombatText and C_CombatText.GetCurrentEventInfo
	if not info then return end
	local data = info()
	-- The payload is secret: test issecret before any comparison (nil included).
	if not issecret(data) and type(data) == "nil" then return end
	if key == "extraAttack" then
		M:Emit(key, { amount = data })
	else
		M:Emit(key, { spell = data })
	end
end)

-- True when the game's own floating combat text runs, so it sends
-- COMBAT_TEXT_UPDATE at all.
function M:GameTextFeedOn()
	return C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("enableFloatingCombatText") == "1" or false
end

-- True when one of these events is on and its area shows.
local function AnyOn(keys)
	for _, key in ipairs(keys) do
		local ev = M.db.events[key]
		local area = ev and ev.on and M.db.areas[ev.area]
		if area and area.enabled then return true end
	end
	return false
end

local function Register()
	unitListener:UnregisterAllEvents()
	targetListener:UnregisterAllEvents()
	ctuListener:UnregisterAllEvents()
	if not M:ScrollRunning() then return end
	local pet = AnyOn({ "petDamage", "petHeal", "petAvoid" })
	if pet then
		unitListener:RegisterUnitEvent("UNIT_COMBAT", "player", "pet")
	else
		unitListener:RegisterUnitEvent("UNIT_COMBAT", "player")
	end
	if AnyOn({ "tgtDamage", "tgtCrit", "tgtAvoid", "tgtHeal" }) then
		targetListener:RegisterUnitEvent("UNIT_COMBAT", "target")
	end
	if AnyOn({ "buff", "debuff", "fade", "extraAttack" }) then
		ctuListener:RegisterEvent("COMBAT_TEXT_UPDATE")
	end
end
M.RegisterSources = Register

M:AddPart("Sources", {
	enable = Register,
	refresh = Register,
	disable = function()
		unitListener:UnregisterAllEvents()
		targetListener:UnregisterAllEvents()
		ctuListener:UnregisterAllEvents()
	end,
})
