-- Combat Text notifications and loot: combat state, spell alerts,
-- combo points, killing blows, experience, honor, reputation, skill ups,
-- monster emotes, loot, money, currency, item ready and the low health /
-- mana / pet health lines.
--   * Chat lines are read with EldoUI's shared parser (E.ChatParse), which
--     matches the client's own localized strings and never reads a line
--     that arrives secret.
--   * Spell alerts come from SPELL_ACTIVATION_OVERLAY_GLOW_SHOW (a plain
--     spell ID: the name and icon come from the game).
--   * Warnings: the game evaluates a step curve on your health or mana and
--     the result becomes the line's alpha. Lua never compares the health.
-- Nothing here acts for the player; it only draws.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local M = E:GetModule("CombatText")
local issecret = M.issecret
local P = E.ChatParse

local listener = CreateFrame("Frame")
local handlers = {}

-- issecret first: comparing a secret with anything (nil included) errors.
local function Plain(value)
	if issecret(value) then return false end
	return type(value) ~= "nil"
end

---------------------------------------------------------------------------
-- Combat state
---------------------------------------------------------------------------
handlers.PLAYER_REGEN_DISABLED = function()
	M:Emit("combatIn", { text = L["+Combat"] })
end
handlers.PLAYER_REGEN_ENABLED = function()
	M:Emit("combatOut", { text = L["-Combat"] })
end

---------------------------------------------------------------------------
-- Spell alerts (procs)
---------------------------------------------------------------------------
local lastProc = {} -- spellID -> time it last showed (the glow can repeat)

handlers.SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = function(_, spellID)
	if not Plain(spellID) or type(spellID) ~= "number" then return end
	local now = GetTime()
	if lastProc[spellID] and now - lastProc[spellID] < 1 then return end
	lastProc[spellID] = now
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
	if not Plain(name) or name == "" then return end
	local icon = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
	M:Emit("proc", { spell = name, icon = Plain(icon) and icon or nil })
end

---------------------------------------------------------------------------
-- Combo points
---------------------------------------------------------------------------
local COMBO_CLASSES = { ROGUE = true, DRUID = true }
local lastCombo = 0

function M:HasComboPoints()
	local _, class = UnitClass("player")
	return COMBO_CLASSES[class] or false
end

local function ComboPoints()
	local kind = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4
	local points = UnitPower("player", kind)
	local max = UnitPowerMax("player", kind)
	if not (Plain(points) and Plain(max)) then return nil end
	return points, max
end

handlers.UNIT_POWER_UPDATE = function(_, unit, powerType)
	if unit ~= "player" or issecret(powerType) or powerType ~= "COMBO_POINTS" then return end
	local points, max = ComboPoints()
	if not points then return end
	local label = L["Combo points"]
	if points > lastCombo and points > 0 then
		if max and max > 0 and points >= max then
			M:Emit("resourceFull", { type = label, amount = points })
		else
			M:Emit("resource", { type = label, amount = points })
		end
	end
	lastCombo = points
end

---------------------------------------------------------------------------
-- Killing blows: the game's own event names the attacker.
---------------------------------------------------------------------------
handlers.PARTY_KILL = function(_, attacker)
	if not Plain(attacker) then return end
	local player = UnitGUID("player")
	if Plain(player) and attacker == player then M:Emit("killingBlow", {}) end
end

---------------------------------------------------------------------------
-- Chat gains
---------------------------------------------------------------------------
handlers.CHAT_MSG_COMBAT_XP_GAIN = function(_, text)
	local fields = P:Parse("xpkill", text)
	if fields and fields.xp then M:Emit("xp", { amount = tonumber(fields.xp), name = fields.mob }) end
end

handlers.CHAT_MSG_COMBAT_HONOR_GAIN = function(_, text)
	local fields = P:Parse("honor", text)
	if fields and fields.honor and not fields.dishonor then
		M:Emit("honor", { amount = tonumber(fields.honor), name = fields.victim })
	end
end

handlers.CHAT_MSG_COMBAT_FACTION_CHANGE = function(_, text)
	local fields = P:Parse("rep", text)
	if not fields then return end
	if fields.loss then
		M:Emit("repLoss", { amount = tonumber(fields.loss), name = fields.faction })
	else
		M:Emit("rep", { amount = tonumber(fields.amount), name = fields.faction })
	end
end

handlers.CHAT_MSG_SKILL = function(_, text)
	local fields = P:Parse("skill", text)
	if fields then M:Emit("skill", { name = fields.skill, amount = tonumber(fields.rank) }) end
end

-- In dungeons and raids the skill line is hidden: the skills list says it.
handlers.SKILL_LINES_CHANGED = function()
	for _, skill in ipairs(P:RisenSkills("combattext")) do M:Emit("skill", { name = skill.name, amount = skill.rank }) end
end

-- Emotes of your target ("... becomes enraged!").
handlers.CHAT_MSG_MONSTER_EMOTE = function(_, text, sender)
	if not (Plain(text) and Plain(sender)) or type(text) ~= "string" or type(sender) ~= "string" then return end
	if not UnitExists("target") then return end
	local name = UnitName("target")
	if not Plain(name) or name ~= sender then return end
	M:Emit("emote", { text = (text:gsub("%%s", function() return sender end)) })
end

---------------------------------------------------------------------------
-- Loot, money, currency: only while EldoUI's loot toasts are off (they
-- already show them), unless the player ticks "Also with loot toasts".
---------------------------------------------------------------------------
function M:LootToastsOn()
	local loot = E:GetModule("Loot")
	return loot and loot.active and loot.db and loot.db.toasts and true or false
end

local function LootAllowed()
	return M.db.loot.withToasts or not M:LootToastsOn()
end
M.LootAllowed = LootAllowed

-- "a, b, 123" -> set of lower-case names and item IDs.
local function List(text)
	local set = {}
	for entry in tostring(text or ""):gmatch("[^,;\n]+") do
		entry = strtrim(entry):lower()
		if entry ~= "" then set[entry] = true end
	end
	return set
end

-- Whether a looted item passes the filters (allow and exclude lists,
-- lowest quality, quest items).
function M:LootPasses(link)
	local loot = self.db.loot
	-- ID and name straight from the link (works before the item is cached).
	local itemID = tonumber(link:match("item:(%d+)"))
	local name = link:match("|h%[(.-)%]|h")
	local _, _, _, _, icon, classID = C_Item.GetItemInfoInstant(itemID or link)
	local function Listed(set)
		return (itemID and set[tostring(itemID)]) or (type(name) == "string" and set[name:lower()]) or false
	end
	if Listed(List(loot.exclude)) then return false, icon end
	if Listed(List(loot.allow)) then return true, icon end
	if loot.questItems and classID == (Enum.ItemClass and Enum.ItemClass.Questitem or 12) then return true, icon end
	local quality = itemID and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
	if type(quality) == "number" and quality < loot.minQuality then return false, icon end
	return true, icon
end

local function CountText(count)
	count = tonumber(count)
	if count and count > 1 then return "\195\151" .. count end
	return nil
end

handlers.CHAT_MSG_LOOT = function(_, text)
	if not LootAllowed() then return end
	local fields = P:Parse("item", text)
	if not (fields and fields.link) then return end
	local passes, icon = M:LootPasses(fields.link)
	if not passes then return end
	local total
	if M.db.loot.bagTotal and C_Item.GetItemCount then
		local count = C_Item.GetItemCount(fields.link)
		if Plain(count) and type(count) == "number" and count > 1 then total = count end
	end
	M:Emit("loot", { item = fields.link, count = CountText(fields.count), total = total, icon = icon })
end

handlers.CHAT_MSG_MONEY = function(_, text)
	if not LootAllowed() then return end
	local fields = P:Parse("money", text)
	if fields and fields.money then M:Emit("money", { amount = fields.money }) end
end

handlers.CHAT_MSG_CURRENCY = function(_, text)
	if not LootAllowed() then return end
	local fields = P:Parse("currency", text)
	if not (fields and fields.link) then return end
	local icon
	local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfoFromLink and C_CurrencyInfo.GetCurrencyInfoFromLink(fields.link)
	if type(info) == "table" and Plain(info.iconFileID) then icon = info.iconFileID end
	M:Emit("currency", { item = fields.link, count = CountText(fields.count), icon = icon })
end

---------------------------------------------------------------------------
-- Item ready: only through the cooldown ready service, which
-- reports an item only when the game says plainly that its cooldown ended.
---------------------------------------------------------------------------
function M:ReadyServiceAvailable()
	return type(E.RegisterCooldownReady) == "function"
end

local readyHooked = false
local function HookReady()
	if readyHooked or not M:ReadyServiceAvailable() then return end
	readyHooked = true
	E:RegisterCooldownReady("CombatText", function(info)
		if type(info) ~= "table" or info.kind ~= "item" then return end
		M:Emit("itemReady", { item = info.name or info.link, icon = info.icon })
	end)
end

-- Off or disabled: the listener goes, so the service stops scanning for us.
local function UnhookReady()
	if not readyHooked then return end
	readyHooked = false
	if type(E.UnregisterCooldownReady) == "function" then E:UnregisterCooldownReady("CombatText") end
end
M.ReadyHooked = function() return readyHooked end

---------------------------------------------------------------------------
-- Warnings: one line per kind, its alpha from the game's curve result.
---------------------------------------------------------------------------
local WARN_UNIT = { health = "player", mana = "player", pet = "pet" }
local WARN_EVENT = { health = "lowHealth", mana = "lowMana", pet = "lowPet" }
local warnLines = {}  -- kind -> { frame, text, curve, threshold }

local function WarnLine(kind)
	local line = warnLines[kind]
	if line then return line end
	line = { frame = CreateFrame("Frame", nil, UIParent) }
	line.frame:SetSize(200, 30)
	line.text = line.frame:CreateFontString(nil, "OVERLAY")
	line.text:SetPoint("CENTER")
	line.frame:Hide()
	warnLines[kind] = line
	return line
end

local function Curve(line, threshold)
	if line.curve and line.threshold == threshold then return line.curve end
	if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
	local curve = C_CurveUtil.CreateCurve()
	if Enum and Enum.LuaCurveType and curve.SetType then curve:SetType(Enum.LuaCurveType.Step) end
	curve:AddPoint(0, 1)
	curve:AddPoint(threshold / 100, 0)
	line.curve, line.threshold = curve, threshold
	return curve
end

-- The game's answer for one warning: a number or a secret number 0-1.
local function WarnValue(kind, curve)
	local unit = WARN_UNIT[kind]
	if not UnitExists(unit) then return 0 end
	if kind == "mana" then
		if not UnitPowerPercent then return nil end
		return UnitPowerPercent(unit, Enum and Enum.PowerType and Enum.PowerType.Mana or 0, false, curve)
	end
	if not UnitHealthPercent then return nil end
	return UnitHealthPercent(unit, true, curve)
end

function M:UpdateWarning(kind)
	local key = WARN_EVENT[kind]
	local ev = self.db.events[key]
	local line = warnLines[kind]
	local areaKey = ev and ev.area
	local area = areaKey and self.db.areas[areaKey]
	local holder = areaKey and self.GetAreaFrame and self:GetAreaFrame(areaKey)
	if not (self:ScrollRunning() and ev and ev.on and area and area.enabled and holder) then
		if line then line.frame:Hide() end
		return
	end
	line = WarnLine(kind)
	local curve = Curve(line, self.db.warn[kind])
	local value = curve and WarnValue(kind, curve)
	if not (issecret(value) or type(value) == "number") then
		line.frame:Hide()
		return
	end
	local size = (ev.fontSize > 0 and ev.fontSize) or self.db.scroll.critFontSize
	local index = ({ health = 0, mana = 1, pet = 2 })[kind]
	line.frame:SetParent(holder)
	line.frame:SetFrameLevel(holder:GetFrameLevel() + 6)
	line.frame:SetSize(area.width, size + 6)
	line.frame:ClearAllPoints()
	line.frame:SetPoint("TOP", holder, "TOP", 0, -index * (size + 6))
	E:SetMediaFont(line.text, self.db.scroll.critFont, size, self.db.scroll.outline == "NONE" and "" or self.db.scroll.outline)
	line.text:SetText(ev.text)
	line.text:SetTextColor(ev.color[1], ev.color[2], ev.color[3])
	line.frame:SetAlpha(value)
	line.frame:Show()
end

local function UpdateWarnings()
	for kind in pairs(WARN_UNIT) do M:UpdateWarning(kind) end
end
M.UpdateWarnings = UpdateWarnings

handlers.UNIT_HEALTH = function(_, unit)
	if unit == "player" then M:UpdateWarning("health") elseif unit == "pet" then M:UpdateWarning("pet") end
end
handlers.UNIT_MAXHEALTH = handlers.UNIT_HEALTH
handlers.UNIT_PET = function() M:UpdateWarning("pet") end
local powerHandler = handlers.UNIT_POWER_UPDATE
handlers.UNIT_POWER_UPDATE = function(event, unit, powerType)
	powerHandler(event, unit, powerType)
	if unit == "player" and not issecret(powerType) and powerType == "MANA" then M:UpdateWarning("mana") end
end

---------------------------------------------------------------------------
-- Registration: only the events a switched-on event needs.
---------------------------------------------------------------------------
local NEEDS = {
	PLAYER_REGEN_DISABLED = { "combatIn" }, PLAYER_REGEN_ENABLED = { "combatOut" },
	SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = { "proc" },
	UNIT_POWER_UPDATE = { "resource", "resourceFull", "lowMana" },
	PARTY_KILL = { "killingBlow" },
	CHAT_MSG_COMBAT_XP_GAIN = { "xp" }, CHAT_MSG_COMBAT_HONOR_GAIN = { "honor" },
	CHAT_MSG_COMBAT_FACTION_CHANGE = { "rep", "repLoss" }, CHAT_MSG_SKILL = { "skill" }, SKILL_LINES_CHANGED = { "skill" },
	CHAT_MSG_MONSTER_EMOTE = { "emote" },
	CHAT_MSG_LOOT = { "loot" }, CHAT_MSG_MONEY = { "money" }, CHAT_MSG_CURRENCY = { "currency" },
	UNIT_HEALTH = { "lowHealth", "lowPet" }, UNIT_MAXHEALTH = { "lowHealth", "lowPet" }, UNIT_PET = { "lowPet" },
}

listener:SetScript("OnEvent", function(_, event, ...)
	local handler = handlers[event]
	if handler then handler(event, ...) end
end)

local function Register()
	listener:UnregisterAllEvents()
	if not M:ScrollRunning() then
		UnhookReady()
		UpdateWarnings()
		return
	end
	local events = M.db.events
	for event, keys in pairs(NEEDS) do
		for _, key in ipairs(keys) do
			if events[key] and events[key].on then
				listener:RegisterEvent(event)
				break
			end
		end
	end
	if events.skill and events.skill.on then P:RisenSkills("combattext") end
	local combo = M:HasComboPoints() and ComboPoints()
	lastCombo = combo or 0
	if events.itemReady.on then HookReady() else UnhookReady() end
	UpdateWarnings()
end
M.RegisterNotify = Register

M:AddPart("Notify", {
	enable = Register,
	refresh = Register,
	disable = function()
		listener:UnregisterAllEvents()
		UnhookReady()
		for _, line in pairs(warnLines) do line.frame:Hide() end
	end,
})
