-- EldoUI text tags: one tag language for every text EldoUI draws
-- about a unit (unit frames, group frames, nameplates, tooltips).
--
--   E:RegisterTag(name, fn, events, info)  add a tag (plugins too)
--   E:FormatTag(tagString, unit, nameUser) the text (may be a secret string)
--   E:RenderTag(fontString, tagString, unit, nameUser)  set it on a FontString now
--   E:BindTag(fontString, tagString, unit, nameUser)    render now and again
--                                          whenever one of its tags' events fires
--   E:TagNameUser()                        inside a tag: the nameUser it renders for
--   E:UnbindTag(fontString)
--   E:TagEvents(tagString)                 the events a string listens to
--   E:TagSlotOptions(prefix, opts)         preset dropdown + custom input
--   E:TagForSlot(block)                    the tag string a slot uses
--
-- A tag string is text with tags in brackets: "[name:short] [health:percent]".
-- Tags may take an argument after a colon ("[name:12]"). Color tags
-- ("[classcolor]") color the text after them up to "[close]". Unknown tags
-- stay visible, so typos are easy to spot.
--
-- nameUser (optional) is the key a module registered with
-- E:RegisterNameFormatUser (Core/Names.lua): [name] in its texts follows
-- that module's Name format override.
--
-- Secret values (Forever / Midnight rules): every tag hands the client's
-- value on as it came. Numbers go through the game's own formatters
-- (AbbreviateNumbers, UnitHealthPercent with a curve) and string.format,
-- and the result goes straight to FontString:SetText. No arithmetic,
-- comparison or concatenation is ever done on a value that may be secret;
-- a "hide when full / zero" variant only hides when the value is plain.
-- Identity tags show whatever the client gives (in instances names can be
-- secret); nothing is guessed. Dropped by rule: distance and speed of other
-- units, threat percentages (only the threat status is shown).
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local issecret = issecretvalue or function() return false end

E.tags = {}
local tags = E.tags

local CATEGORY_ORDER = { "Names", "Health", "Power", "Identity", "Status", "Group", "Colors", "Pet", "Experience", "Other" }
-- Shown as header labels, translated centrally: L["Names"], L["Health"], L["Power"],
-- L["Identity"], L["Status"], L["Group"], L["Colors"], L["Pet"], L["Experience"], L["Other"]

---------------------------------------------------------------------------
-- Registry
---------------------------------------------------------------------------
-- events: "EVENT EVENT" or a list. Events named UNIT_* refresh only the
-- texts of the unit they fire for; others refresh every text using the tag.
-- info: desc, category, timer (seconds: refreshed by the shared ticker),
--       arg = true (the tag takes ":<argument>"), example.
local compiled = {}

function E:RegisterTag(name, fn, events, info)
	assert(type(name) == "string" and name ~= "", "EldoUI:RegisterTag(name, fn, events, info): name must be a string")
	assert(type(fn) == "function", "EldoUI:RegisterTag(name, fn, events, info): fn must be a function")
	info = info or {}
	local list = {}
	if type(events) == "string" then
		for event in events:gmatch("%S+") do list[#list + 1] = event end
	elseif type(events) == "table" then
		for _, event in ipairs(events) do list[#list + 1] = event end
	end
	tags[name] = {
		name = name, fn = fn, events = list, desc = info.desc,
		category = (info.category == "Colours" and "Colors") or info.category or "Other", -- the old (British) name still files under Colors
		timer = info.timer, arg = info.arg, example = info.example, color = info.color,
	}
	wipe(compiled) -- a string compiled before may now know this tag
end

---------------------------------------------------------------------------
-- Helpers (secret-safe)
---------------------------------------------------------------------------
local function Plain(value)
	-- issecret first: comparing a secret value, even with nil, errors in the client.
	return not issecret(value) and value ~= nil
end

-- A big number in the General > Fonts and Text "Big numbers" style through
-- E:FormatNumber. Secret values go through the game's own
-- formatter there, so the result may be a secret string for SetText.
local function Short(value)
	if type(value) == "nil" then return "" end
	if E.FormatNumber then
		local ok, text = pcall(E.FormatNumber, E, value)
		if ok and type(text) ~= "nil" then return text end
	end
	if AbbreviateNumbers then
		local ok, text = pcall(AbbreviateNumbers, value)
		if ok and type(text) ~= "nil" then return text end
	end
	return value
end
E.TagShort = Short

local function Format(pattern, ...)
	local ok, text = pcall(string.format, pattern, ...)
	if ok then return text end
	return ""
end

local function ScaleTo100()
	return CurveConstants and CurveConstants.ScaleTo100
end

-- UTF-8 safe cut to `count` characters through E:Utf8Sub
-- (Core/Init.lua). A secret name is passed through whole: it can't be cut.
local function Utf8Sub(text, count)
	if not Plain(text) or type(text) ~= "string" then return text end
	return E:Utf8Sub(text, count)
end

local function ColorCode(r, g, b)
	if not (Plain(r) and Plain(g) and Plain(b)) then return "" end
	return ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function ColorOf(color)
	if type(color) ~= "table" then return "" end
	if color.GetRGB then return ColorCode(color:GetRGB()) end
	return ColorCode(color.r or color[1], color.g or color[2], color.b or color[3])
end

-- Colors the game defines (semantic: danger, warning, good).
local function GameColor(name, r, g, b)
	local color = _G[name]
	if type(color) == "table" and color.r then return color end
	return { r = r, g = g, b = b }
end

---------------------------------------------------------------------------
-- Names (Forever surnames). Core/Names.lua splits and formats them;
-- [name] and the target tags follow the Name format (General page), or
-- the override of the module that draws the text (E:BindTag's nameUser).
-- [name:first] / [name:last] / [name:full] always show that part.
---------------------------------------------------------------------------
local nameUser -- the registered name user rendering right now (or nil)

-- The name user of the text being rendered, for plugin tags that draw a
-- name: E:DisplayName(unit, E:TagNameUser()).
function E:TagNameUser()
	return nameUser
end

local function ShownName(unit)
	if E.DisplayName then return E:DisplayName(unit, nameUser) end
	return (UnitName(unit))
end

local NAME_LENGTH = { short = 10, medium = 15, long = 20 }

local function Abbreviate(name)
	if not Plain(name) or type(name) ~= "string" then return name end
	local words = {}
	for word in name:gmatch("%S+") do words[#words + 1] = word end
	if #words < 2 then return name end
	for i = 1, #words - 1 do words[i] = Utf8Sub(words[i], 1) .. "." end
	return table.concat(words, " ")
end

local NAME_EVENTS = "UNIT_NAME_UPDATE"

-- Format first, then cut: a length counts the letters that are shown.
local function NameTag(unit, arg)
	local name = ShownName(unit)
	if arg then
		local count = tonumber(arg) or NAME_LENGTH[arg]
		if count then return Utf8Sub(name, math.max(1, math.min(count, 60))) end
		if arg == "abbrev" then return Abbreviate(name) end
	end
	return name
end

E:RegisterTag("name", NameTag, NAME_EVENTS, { category = "Names", arg = true, example = "[name:12]",
	desc = "The unit's name in the Name format (General page, or this module's own choice there). [name:short] / [name:medium] / [name:long] cut it to 10 / 15 / 20 letters, [name:N] to N letters (counted after the format; accents and other alphabets are kept whole), [name:abbrev] shortens all but the last word (\"C. K. Seaclaw\")." })
-- Older tag strings: [name:format] and [name:format:12] are [name] now.
E:RegisterTag("name:format", NameTag, NAME_EVENTS, { category = "Names", arg = true, example = "[name:format:12]",
	desc = "Same as [name] (kept for older tag strings)." })

local function Parts(unit)
	if E.NameParts then return E:NameParts(unit, true) end
	return (UnitName(unit)), nil
end

E:RegisterTag("name:first", function(unit) return (Parts(unit)) end, NAME_EVENTS,
	{ category = "Names", desc = "First name only, whatever the Name format says." })
E:RegisterTag("name:last", function(unit)
	local _, last = Parts(unit)
	return last or ""
end, NAME_EVENTS, { category = "Names", desc = "The Forever surname, empty when the character has none (or it is your own and the game hides it)." })
E:RegisterTag("name:full", function(unit)
	local first, last = Parts(unit)
	if last and E.FormatName then return E:FormatName(first, last, "full") end
	return first
end, NAME_EVENTS, { category = "Names", desc = "First name and surname, whatever the Name format says." })
E:RegisterTag("name:realm", function(unit)
	local alias = E.NameAlias and E:NameAlias(unit)
	if alias then return alias end
	local name, realm = UnitNameUnmodified(unit)
	if Plain(realm) and realm ~= "" then return Format("%s-%s", name, realm) end
	return name
end, NAME_EVENTS, { category = "Names", desc = "Name with the realm for characters from another realm." })
E:RegisterTag("realm", function(unit)
	local _, realm = UnitNameUnmodified(unit)
	return realm or ""
end, NAME_EVENTS, { category = "Identity", desc = "The character's realm when it differs from yours." })

E:RegisterTag("target", function(unit)
	local name = ShownName(unit .. "target")
	if type(name) == "nil" then return "" end
	return name
end, "UNIT_TARGET PLAYER_TARGET_CHANGED", { category = "Names", desc = "Name of what the unit is targeting. Use [target:class] for it in class color." })
E:RegisterTag("target:class", function(unit)
	local target = unit .. "target"
	local name = ShownName(target)
	if type(name) == "nil" then return "" end
	local _, class = UnitClass(target)
	local color = Plain(class) and E:UnitShowsClassColor(target) and E:ClassColorObject(class) -- custom class colors
	if color then return Format("%s%s|r", ColorOf(color), name) end
	return name
end, "UNIT_TARGET PLAYER_TARGET_CHANGED", { category = "Names", desc = "Name of the unit's target, in its class color for players." })

---------------------------------------------------------------------------
-- Health (secret-safe: formatters only)
---------------------------------------------------------------------------
local HEALTH_EVENTS = "UNIT_HEALTH UNIT_MAXHEALTH"

local function HealthPercent(unit)
	if UnitHealthPercent and ScaleTo100() then
		local ok, value = pcall(UnitHealthPercent, unit, true, ScaleTo100())
		if ok and type(value) ~= "nil" then return Format("%d%%", value) end
	end
	return ""
end

local function HealthPercentNumber(unit)
	if UnitHealthPercent and ScaleTo100() then
		local ok, value = pcall(UnitHealthPercent, unit, true, ScaleTo100())
		if ok and type(value) ~= "nil" then return Format("%d", value) end
	end
	return ""
end

-- True only when the game says (in plain values) that health is full.
local function KnownFull(unit)
	if not UnitHealthMissing then return false end
	local missing = UnitHealthMissing(unit, true)
	return Plain(missing) and missing == 0
end

local function Dead(unit)
	local dead = UnitIsDeadOrGhost(unit)
	return Plain(dead) and dead
end

E:RegisterTag("health:current", function(unit) return Short(UnitHealth(unit)) end, HEALTH_EVENTS,
	{ category = "Health", desc = "Current health, shortened (12.3K)." })
E:RegisterTag("health:max", function(unit) return Short(UnitHealthMax(unit)) end, HEALTH_EVENTS,
	{ category = "Health", desc = "Maximum health, shortened." })
E:RegisterTag("health:percent", HealthPercent, HEALTH_EVENTS,
	{ category = "Health", desc = "Health in percent with the % sign (75%)." })
E:RegisterTag("health:percent-nosign", HealthPercentNumber, HEALTH_EVENTS,
	{ category = "Health", desc = "Health in percent without the % sign (75)." })
E:RegisterTag("health:current-max", function(unit)
	return Format("%s / %s", Short(UnitHealth(unit)), Short(UnitHealthMax(unit)))
end, HEALTH_EVENTS, { category = "Health", desc = "Current and maximum health (12.3K / 20K)." })
E:RegisterTag("health:current-percent", function(unit)
	return Format("%s | %s", Short(UnitHealth(unit)), HealthPercent(unit))
end, HEALTH_EVENTS, { category = "Health", desc = "Current health and percent (12.3K | 75%)." })
E:RegisterTag("health:percent-hidefull", function(unit)
	if KnownFull(unit) then return "" end
	return HealthPercent(unit)
end, HEALTH_EVENTS, { category = "Health", desc = "Percent, empty at full health. When the game keeps health hidden (often in combat) it always shows." })
E:RegisterTag("health:current-hidefull", function(unit)
	if KnownFull(unit) then return "" end
	return Short(UnitHealth(unit))
end, HEALTH_EVENTS, { category = "Health", desc = "Current health, empty at full health (when the game shows the value)." })
E:RegisterTag("health:deficit", function(unit)
	if not UnitHealthMissing then return "" end
	local missing = UnitHealthMissing(unit, true)
	if Plain(missing) and missing == 0 then return "" end
	return Format("-%s", Short(missing))
end, HEALTH_EVENTS, { category = "Health", desc = "Missing health (-3.2K), empty at full health when the game shows the value." })
E:RegisterTag("health:absorbs", function(unit)
	if not UnitGetTotalAbsorbs then return "" end
	local amount = UnitGetTotalAbsorbs(unit)
	if type(amount) == "nil" or (Plain(amount) and amount == 0) then return "" end
	return Format("+%s", Short(amount))
end, "UNIT_ABSORB_AMOUNT_CHANGED UNIT_MAXHEALTH", { category = "Health", desc = "Damage absorb shields on the unit (+4K), as the game reports them." })
E:RegisterTag("health:healabsorbs", function(unit)
	if not UnitGetTotalHealAbsorbs then return "" end
	local amount = UnitGetTotalHealAbsorbs(unit)
	if type(amount) == "nil" or (Plain(amount) and amount == 0) then return "" end
	return Format("-%s", Short(amount))
end, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED UNIT_MAXHEALTH", { category = "Health", desc = "Heal absorbs on the unit (healing that is eaten first)." })
E:RegisterTag("health:incoming", function(unit)
	if not UnitGetIncomingHeals then return "" end
	local amount = UnitGetIncomingHeals(unit)
	if type(amount) == "nil" or (Plain(amount) and amount == 0) then return "" end
	return Format("+%s", Short(amount))
end, "UNIT_HEAL_PREDICTION UNIT_MAXHEALTH", { category = "Health", desc = "Heals on the way to the unit, from the game's heal prediction." })

---------------------------------------------------------------------------
-- Power
---------------------------------------------------------------------------
local POWER_EVENTS = "UNIT_POWER_UPDATE UNIT_MAXPOWER UNIT_DISPLAYPOWER"

local function PowerPercent(unit)
	if UnitPowerPercent and ScaleTo100() then
		local ok, value = pcall(UnitPowerPercent, unit, nil, false, ScaleTo100())
		if ok and type(value) ~= "nil" then return Format("%d%%", value) end
	end
	return ""
end

E:RegisterTag("power:current", function(unit) return Short(UnitPower(unit)) end, POWER_EVENTS,
	{ category = "Power", desc = "Current mana, rage, energy or focus, shortened." })
E:RegisterTag("power:max", function(unit) return Short(UnitPowerMax(unit)) end, POWER_EVENTS,
	{ category = "Power", desc = "Maximum power, shortened." })
E:RegisterTag("power:percent", PowerPercent, POWER_EVENTS,
	{ category = "Power", desc = "Power in percent (80%)." })
E:RegisterTag("power:current-max", function(unit)
	return Format("%s / %s", Short(UnitPower(unit)), Short(UnitPowerMax(unit)))
end, POWER_EVENTS, { category = "Power", desc = "Current and maximum power." })
E:RegisterTag("power:current-percent", function(unit)
	return Format("%s | %s", Short(UnitPower(unit)), PowerPercent(unit))
end, POWER_EVENTS, { category = "Power", desc = "Current power and percent." })
E:RegisterTag("power:deficit", function(unit)
	if not UnitPowerMissing then return "" end
	local missing = UnitPowerMissing(unit)
	if Plain(missing) and missing == 0 then return "" end
	return Format("-%s", Short(missing))
end, POWER_EVENTS, { category = "Power", desc = "Missing power (-120), empty when full and the game shows the value." })
E:RegisterTag("power:current-hidezero", function(unit)
	local power = UnitPower(unit)
	if Plain(power) and power == 0 then return "" end
	return Short(power)
end, POWER_EVENTS, { category = "Power", desc = "Current power, empty at zero (rage and energy out of combat) when the game shows the value." })
E:RegisterTag("mana:alt", function(unit)
	local powerType = UnitPowerType(unit)
	local mana = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
	if not Plain(powerType) or powerType == mana then return "" end
	if not Plain(UnitPowerMax(unit, mana)) or UnitPowerMax(unit, mana) == 0 then return "" end
	return Short(UnitPower(unit, mana))
end, POWER_EVENTS, { category = "Power", desc = "Mana while the unit shows another power, e.g. a druid in bear or cat form. Empty otherwise." })

---------------------------------------------------------------------------
-- Identity
---------------------------------------------------------------------------
local CLASSIFICATION = { elite = ELITE or "Elite", rareelite = "Rare Elite", rare = ITEM_QUALITY3_DESC or "Rare", worldboss = BOSS or "Boss" }
local CLASSIFICATION_SHORT = { elite = "+", rareelite = "R+", rare = "R", worldboss = "B" }

local function Classification(unit)
	local value = UnitClassification(unit)
	if not Plain(value) then return nil end
	return value
end

E:RegisterTag("level", function(unit)
	local level = UnitLevel(unit)
	if not Plain(level) then return level end
	return (level and level > 0) and tostring(level) or "??"
end, "UNIT_LEVEL PLAYER_LEVEL_UP", { category = "Identity", desc = "The unit's level; ?? when the game hides it." })
E:RegisterTag("level:smart", function(unit)
	local level = UnitLevel(unit)
	if not Plain(level) then return level end
	if Classification(unit) == "worldboss" or not level or level <= 0 then return "??" end
	if UnitIsPlayer(unit) and level == UnitLevel("player") then return "" end
	return tostring(level)
end, "UNIT_LEVEL PLAYER_LEVEL_UP UNIT_CLASSIFICATION_CHANGED", { category = "Identity", desc = "Level, empty for players of your own level, ?? for bosses." })
E:RegisterTag("classification", function(unit) return CLASSIFICATION[Classification(unit) or ""] or "" end,
	"UNIT_CLASSIFICATION_CHANGED", { category = "Identity", desc = "Elite, Rare, Rare Elite or Boss; empty for normal units." })
E:RegisterTag("classification:short", function(unit) return CLASSIFICATION_SHORT[Classification(unit) or ""] or "" end,
	"UNIT_CLASSIFICATION_CHANGED", { category = "Identity", desc = "One symbol: + elite, R rare, R+ rare elite, B boss." })
E:RegisterTag("class", function(unit)
	if not UnitIsPlayer(unit) then return "" end
	return (UnitClass(unit)) or ""
end, nil, { category = "Identity", desc = "The class of a player; empty for NPCs." })
E:RegisterTag("class:smart", function(unit)
	if UnitIsPlayer(unit) then return (UnitClass(unit)) or "" end
	return UnitCreatureType(unit) or ""
end, nil, { category = "Identity", desc = "Class for players, creature type (Beast, Humanoid ...) for NPCs." })
E:RegisterTag("creature", function(unit) return UnitCreatureType(unit) or "" end, nil,
	{ category = "Identity", desc = "Creature type for NPCs (Beast, Undead ...)." })
E:RegisterTag("race", function(unit)
	if not UnitIsPlayer(unit) then return "" end
	return (UnitRace(unit)) or ""
end, nil, { category = "Identity", desc = "A player's race." })
E:RegisterTag("faction", function(unit)
	local _, localized = UnitFactionGroup(unit)
	return localized or ""
end, "UNIT_FACTION", { category = "Identity", desc = "Alliance or Horde." })
E:RegisterTag("guild", function(unit)
	if not (GetGuildInfo and UnitIsPlayer(unit)) then return "" end
	return (GetGuildInfo(unit)) or ""
end, "PLAYER_GUILD_UPDATE UNIT_NAME_UPDATE", { category = "Identity", desc = "A player's guild name." })
E:RegisterTag("guild:rank", function(unit)
	if not (GetGuildInfo and UnitIsPlayer(unit)) then return "" end
	local _, rank = GetGuildInfo(unit)
	return rank or ""
end, "PLAYER_GUILD_UPDATE UNIT_NAME_UPDATE", { category = "Identity", desc = "A player's rank in their guild." })
E:RegisterTag("title", function(unit)
	if not UnitIsPlayer(unit) then return "" end
	local alias = E.NameAlias and E:NameAlias(unit)
	if alias then return alias end
	return UnitPVPName(unit) or ""
end, "UNIT_NAME_UPDATE KNOWN_TITLES_UPDATE", { category = "Identity", desc = "A player's name with their chosen title." })

-- NPC title ("Innkeeper") from the game's own unit tooltip data, outside
-- instances only. The level line is skipped by the game's own level text.
-- The title is kept per unit (by its GUID, with the name it was read
-- under), so a text that also shows health or power does not read the
-- tooltip again on every one of their events. A name update, a loading
-- screen or a full list starts over.
do
	local TITLE_KEEP = 300 -- titles kept at most; then the list starts over
	local titleOf, nameOf, kept = {}, {}, 0

	local function LevelPrefix()
		local template = _G.TOOLTIP_UNIT_LEVEL
		if type(template) ~= "string" then return nil end
		return (template:match("^(.-)%%"))
	end

	local function Forget()
		wipe(titleOf)
		wipe(nameOf)
		kept = 0
	end

	local function ReadTitle(unit)
		local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
		local line = ok and type(data) == "table" and data.lines and data.lines[2]
		local text = line and line.leftText
		if not Plain(text) or type(text) ~= "string" or text == "" then return "" end
		local prefix = LevelPrefix()
		if prefix and prefix ~= "" and text:sub(1, #prefix) == prefix then return "" end
		return text
	end

	-- A plain GUID and name, or nil when either is secret or missing.
	local function Identity(unit)
		local okGUID, guid = pcall(UnitGUID, unit)
		if not okGUID or not Plain(guid) or type(guid) ~= "string" then return nil end
		local okName, name = pcall(UnitName, unit)
		if not okName or not Plain(name) or type(name) ~= "string" then return nil end
		return guid, name
	end

	E:RegisterTag("npctitle", function(unit)
		if UnitIsPlayer(unit) or not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return "" end
		local inside = IsInInstance()
		if not Plain(inside) or inside then return "" end
		local guid, name = Identity(unit)
		if guid and nameOf[guid] == name then return titleOf[guid] end
		local text = ReadTitle(unit)
		if guid then
			if nameOf[guid] == nil then
				if kept >= TITLE_KEEP then Forget() end
				kept = kept + 1
			end
			titleOf[guid], nameOf[guid] = text, name
		end
		return text
	end, "UNIT_NAME_UPDATE", { category = "Identity", desc = "An NPC's title (Innkeeper, Flight Master). Outside instances only." })

	-- Made before any text is bound, so it hears a name update before the
	-- texts that show the title render again.
	local forget = CreateFrame("Frame")
	forget:RegisterEvent("PLAYER_ENTERING_WORLD")
	forget:RegisterEvent("UNIT_NAME_UPDATE")
	forget:SetScript("OnEvent", function(_, event, unit)
		if event == "UNIT_NAME_UPDATE" and unit then
			local okGUID, guid = pcall(UnitGUID, unit)
			if okGUID and Plain(guid) and type(guid) == "string" then
				if nameOf[guid] ~= nil then
					titleOf[guid], nameOf[guid] = nil, nil
					kept = kept - 1
				end
				return
			end
		end
		Forget()
	end)

	-- Read-only: how many titles are kept.
	function E:NPCTitlesKept() return kept end
end

---------------------------------------------------------------------------
-- Status, with our own timers (the time we first saw the state; not
-- combat data). Refreshed by the shared ticker.
---------------------------------------------------------------------------
local since = {}   -- "<guid>:<state>" -> GetTime() when first seen

local function Since(unit, state, active)
	local guid = UnitGUID(unit)
	if not Plain(guid) then return nil end
	local key = guid .. ":" .. state
	if not active then
		since[key] = nil
		return nil
	end
	since[key] = since[key] or GetTime()
	return GetTime() - since[key]
end

local function Clock(seconds)
	if not seconds then return "" end
	return E:FormatDuration(seconds, "clock")
end

local function Flag(fn, unit)
	if not fn then return false end
	local value = fn(unit)
	return Plain(value) and value and true or false
end

local function StatusText(unit, withTimer)
	local offline = not Flag(UnitIsConnected, unit)
	local offTime = Since(unit, "offline", offline and UnitIsPlayer(unit))
	if offline and UnitIsPlayer(unit) then
		return withTimer and Format("%s %s", PLAYER_OFFLINE or "Offline", Clock(offTime)) or (PLAYER_OFFLINE or "Offline")
	end
	if Flag(UnitIsGhost, unit) then return "Ghost" end
	if Flag(UnitIsDead, unit) then return DEAD or "Dead" end
	local afk = Flag(UnitIsAFK, unit)
	local afkTime = Since(unit, "afk", afk)
	if afk then return withTimer and Format("%s %s", "AFK", Clock(afkTime)) or "AFK" end
	local dnd = Flag(UnitIsDND, unit)
	local dndTime = Since(unit, "dnd", dnd)
	if dnd then return withTimer and Format("%s %s", "DND", Clock(dndTime)) or "DND" end
	return ""
end

local STATUS_EVENTS = "PLAYER_FLAGS_CHANGED UNIT_CONNECTION UNIT_HEALTH UNIT_FLAGS"
E:RegisterTag("status", function(unit) return StatusText(unit, false) end, STATUS_EVENTS,
	{ category = "Status", desc = "Offline, Dead, Ghost, AFK or DND; empty otherwise. Refreshes on its own when the state changes." })
E:RegisterTag("status:timer", function(unit) return StatusText(unit, true) end, STATUS_EVENTS,
	{ category = "Status", timer = 1, desc = "Like [status], with how long the unit has been AFK, DND or offline since EldoUI saw it change (3:12)." })
E:RegisterTag("dead", function(unit)
	if Flag(UnitIsGhost, unit) then return "Ghost" end
	if Flag(UnitIsDead, unit) then return DEAD or "Dead" end
	return ""
end, "UNIT_HEALTH UNIT_FLAGS", { category = "Status", desc = "Dead or Ghost; empty while alive." })
E:RegisterTag("resting", function(unit)
	if not UnitIsUnit(unit, "player") then return "" end
	return IsResting() and "zzz" or ""
end, "PLAYER_UPDATE_RESTING", { category = "Status", desc = "zzz while you rest in an inn or city (your own frame only)." })
E:RegisterTag("combat", function(unit)
	local value = UnitAffectingCombat(unit)
	if not Plain(value) then return "" end
	return value and (_G.COMBAT or "Combat") or ""
end, "UNIT_FLAGS PLAYER_REGEN_DISABLED PLAYER_REGEN_ENABLED", { category = "Status", desc = "Combat while the unit is in combat (when the game shows it)." })
E:RegisterTag("pvp", function(unit)
	if Flag(UnitIsPVPFreeForAll, unit) then return "FFA" end
	if Flag(UnitIsPVP, unit) then return PVP or "PvP" end
	return ""
end, "UNIT_FACTION UNIT_FLAGS", { category = "Status", desc = "PvP when the unit is flagged for PvP, FFA in free-for-all areas." })
E:RegisterTag("threat", function(unit)
	if not UnitThreatSituation or UnitIsUnit(unit, "player") then return "" end
	local status = UnitThreatSituation("player", unit)
	if not Plain(status) or type(status) ~= "number" then return "" end
	return ({ [1] = L["High threat"], [2] = L["Losing aggro"], [3] = L["Tanking"] })[status] or ""
end, "UNIT_THREAT_SITUATION_UPDATE UNIT_THREAT_LIST_UPDATE", { category = "Status", desc = "Your threat state on this unit as the game reports it (no numbers)." })

---------------------------------------------------------------------------
-- Group
---------------------------------------------------------------------------
E:RegisterTag("group", function(unit)
	if not IsInRaid() then return "" end
	local index = UnitInRaid(unit)
	if not Plain(index) or not index then return "" end
	local _, _, subgroup = GetRaidRosterInfo(index)
	return Plain(subgroup) and subgroup and tostring(subgroup) or ""
end, "GROUP_ROSTER_UPDATE", { category = "Group", desc = "The unit's raid group number (1-8); empty outside raids." })
E:RegisterTag("leader", function(unit)
	if Flag(UnitIsGroupLeader, unit) then return "L" end
	if IsInRaid() and Flag(UnitIsGroupAssistant, unit) then return "A" end
	return ""
end, "PARTY_LEADER_CHANGED GROUP_ROSTER_UPDATE", { category = "Group", desc = "L for the group leader, A for raid assistants." })
E:RegisterTag("role", function(unit)
	local role = UnitGroupRolesAssigned(unit)
	if not Plain(role) then return "" end
	if role == "TANK" then return TANK or "Tank" end
	if role == "HEALER" then return HEALER or "Healer" end
	if role == "DAMAGER" then return DAMAGER or "Damage" end
	return ""
end, "PLAYER_ROLES_ASSIGNED GROUP_ROSTER_UPDATE", { category = "Group", desc = "The role picked in the group: Tank, Healer or Damage." })

---------------------------------------------------------------------------
-- Colors: each returns a color code; [close] ends the color. A color
-- the game keeps secret gives no code (the text keeps its normal color).
-- Class, reaction and power colors come from E:ClassColorObject and
-- friends (Core/Safe.lua), so custom colors from the Colors page apply.
---------------------------------------------------------------------------
E:RegisterTag("classcolor", function(unit)
	if not E:UnitShowsClassColor(unit) then return "" end
	local _, class = UnitClass(unit)
	if not Plain(class) then return "" end
	return ColorOf(E:ClassColorObject(class))
end, nil, { category = "Colors", color = true, desc = "Text after it in the player's class color." })
E:RegisterTag("reactioncolor", function(unit)
	local reaction = UnitReaction(unit, "player")
	if not Plain(reaction) or not reaction then return "" end
	return ColorOf(E:ReactionColorObject(reaction))
end, "UNIT_FACTION", { category = "Colors", color = true, desc = "Text after it in the reaction color: red hostile, yellow neutral, green friendly." })
E:RegisterTag("difficultycolor", function(unit)
	local level = UnitEffectiveLevel and UnitEffectiveLevel(unit) or UnitLevel(unit)
	if not Plain(level) or not GetCreatureDifficultyColor then return "" end
	if level <= 0 then level = 999 end
	return ColorOf(GetCreatureDifficultyColor(level))
end, "UNIT_LEVEL PLAYER_LEVEL_UP", { category = "Colors", color = true, desc = "Text after it in the level difficulty color (gray, green, yellow, orange, red)." })
E:RegisterTag("powercolor", function(unit)
	local _, token = UnitPowerType(unit)
	if not Plain(token) then return "" end
	return ColorOf(E:PowerColorObject(token))
end, "UNIT_DISPLAYPOWER", { category = "Colors", color = true, desc = "Text after it in the color of the unit's power (mana blue, rage red ...)." })
E:RegisterTag("classificationcolor", function(unit)
	local class = Classification(unit)
	if class == "worldboss" then return ColorOf(GameColor("RED_FONT_COLOR", 1, 0.13, 0.13)) end
	if class == "rare" or class == "rareelite" then return ColorOf(GameColor("LIGHTGRAY_FONT_COLOR", 0.8, 0.8, 0.8)) end
	if class == "elite" then return ColorOf(GameColor("NORMAL_FONT_COLOR", 1, 0.82, 0)) end
	return ""
end, "UNIT_CLASSIFICATION_CHANGED", { category = "Colors", color = true, desc = "Text after it in gold for elites, silver for rares, red for bosses." })

-- Threat color: your threat on the unit, from E:GetThreat("player", unit)
-- when that helper is loaded, otherwise the game's threat status (never a
-- percentage). Nothing on your own frame.
local THREAT_COLOR = {
	[1] = { "YELLOW_FONT_COLOR", 1, 1, 0.47 },
	[2] = { "ORANGE_FONT_COLOR", 1, 0.6, 0 },
	[3] = { "RED_FONT_COLOR", 1, 0.13, 0.13 },
}
E:RegisterTag("threatcolor", function(unit)
	local status
	if not unit or UnitIsUnit(unit, "player") then return "" end
	if E.GetThreat then
		local ok, info = pcall(E.GetThreat, E, "player", unit)
		if ok and type(info) == "table" then
			if info.color then return ColorOf(info.color) end
			status = info.status
		elseif ok then
			status = info
		end
	elseif UnitThreatSituation then
		status = UnitThreatSituation("player", unit)
	end
	if not Plain(status) then return "" end
	local entry = THREAT_COLOR[status]
	return entry and ColorOf(GameColor(entry[1], entry[2], entry[3], entry[4])) or ""
end, "UNIT_THREAT_SITUATION_UPDATE UNIT_THREAT_LIST_UPDATE", { category = "Colors", color = true, desc = "Text after it in your threat color on this unit: yellow, orange, red as the game reports it." })

-- Health color through a color curve: the client turns health percent
-- into a color. As the first tag of a string it colors the whole text
-- with SetTextColor (works with hidden values); later in a string it only
-- colors when the game shows the value.
local healthCurve
local function HealthCurve()
	if healthCurve ~= nil then return healthCurve or nil end
	healthCurve = false
	if C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor then
		local ok, curve = pcall(C_CurveUtil.CreateColorCurve)
		if ok and curve then
			local low = GameColor("RED_FONT_COLOR", 1, 0.13, 0.13)
			local mid = GameColor("YELLOW_FONT_COLOR", 1, 1, 0.47)
			local high = GameColor("GREEN_FONT_COLOR", 0.1, 1, 0.1)
			local added = pcall(function()
				curve:AddPoint(0, CreateColor(low.r, low.g, low.b, 1))
				curve:AddPoint(0.5, CreateColor(mid.r, mid.g, mid.b, 1))
				curve:AddPoint(1, CreateColor(high.r, high.g, high.b, 1))
			end)
			if added then healthCurve = curve end
		end
	end
	return healthCurve or nil
end

local ColorResult = {}   -- marker metatable for color objects
E:RegisterTag("healthcolor", function(unit)
	local curve = HealthCurve()
	if not (curve and UnitHealthPercent) then return "" end
	local ok, color = pcall(UnitHealthPercent, unit, true, curve)
	if not ok or type(color) == "nil" then return "" end
	return setmetatable({ color = color }, ColorResult)
end, HEALTH_EVENTS, { category = "Colors", color = true, desc = "Text after it colored by health: green full, yellow half, red low. Works best as the first tag." })

E:RegisterTag("close", function() return "|r" end, nil, { category = "Colors", color = true, desc = "Ends a color tag. [|r] works too." })
tags["|r"] = tags.close
tags["||r"] = tags.close

---------------------------------------------------------------------------
-- Pet (Forever hunter pets), quest
---------------------------------------------------------------------------
local PET_EVENTS = "UNIT_HAPPINESS PET_UI_UPDATE UNIT_PET"
E:RegisterTag("pet:happiness", function()
	local happiness = C_PetInfo and C_PetInfo.GetPetHappiness and C_PetInfo.GetPetHappiness()
	if not Plain(happiness) or type(happiness) ~= "number" then return "" end
	return _G["PET_HAPPINESS" .. happiness] or ""
end, PET_EVENTS, { category = "Pet", desc = "Your hunter pet's happiness as the game names it." })
E:RegisterTag("pet:loyalty", function()
	local loyalty = C_PetInfo and C_PetInfo.GetPetLoyalty and C_PetInfo.GetPetLoyalty()
	if not Plain(loyalty) or type(loyalty) ~= "string" then return "" end
	return loyalty
end, PET_EVENTS, { category = "Pet", desc = "Your hunter pet's loyalty level." })
E:RegisterTag("pet:diet", function()
	local foods = C_PetInfo and C_PetInfo.GetPetFoodTypes and C_PetInfo.GetPetFoodTypes()
	if type(foods) ~= "table" or #foods == 0 then return "" end
	for _, food in ipairs(foods) do
		if not Plain(food) then return "" end
	end
	return table.concat(foods, ", ")
end, PET_EVENTS, { category = "Pet", desc = "The food types your hunter pet eats." })

---------------------------------------------------------------------------
-- Experience: your own XP, from UnitXP, UnitXPMax and
-- GetXPExhaustion. Only for the player unit; empty at max level and while
-- XP gain is turned off. Numbers follow the "Big numbers" style. Math is
-- only done on plain values (XP is never secret, but checked anyway).
---------------------------------------------------------------------------
local XP_EVENTS = "PLAYER_XP_UPDATE UPDATE_EXHAUSTION PLAYER_LEVEL_UP ENABLE_XP_GAIN DISABLE_XP_GAIN"

local function PlainNumber(value)
	if issecret(value) or type(value) ~= "number" then return nil end
	return value
end

local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, value = pcall(fn, ...)
	if ok then return PlainNumber(value) end
	return nil
end

local function IsPlayerUnit(unit)
	if unit == "player" then return true end
	if not UnitIsUnit then return false end
	local ok, same = pcall(UnitIsUnit, unit, "player")
	return ok and not issecret(same) and same == true
end

-- xp, xpMax as plain numbers while the player can still gain XP, else nil.
local function PlayerXP(unit)
	if not IsPlayerUnit(unit) then return nil end
	if IsXPUserDisabled then
		local ok, disabled = pcall(IsXPUserDisabled)
		if ok and not issecret(disabled) and disabled then return nil end
	end
	local level = Call(UnitLevel, "player")
	local maxLevel = Call(rawget(_G, "GetMaxLevelForPlayerExpansion")) or Call(rawget(_G, "GetMaxPlayerLevel"))
	if level and maxLevel and maxLevel > 0 and level >= maxLevel then return nil end
	local xp, xpMax = Call(UnitXP, "player"), Call(UnitXPMax, "player")
	if not xp or not xpMax or xpMax <= 0 then return nil end
	return xp, xpMax
end

E:RegisterTag("xp:percent", function(unit)
	local xp, xpMax = PlayerXP(unit)
	if not xp then return "" end
	return Format("%d%%", math.floor(xp / xpMax * 100))
end, XP_EVENTS, { category = "Experience", desc = "Your experience toward the next level in percent (45%). Empty at max level." })
E:RegisterTag("xp:remaining", function(unit)
	local xp, xpMax = PlayerXP(unit)
	if not xp then return "" end
	return Short(math.max(xpMax - xp, 0))
end, XP_EVENTS, { category = "Experience", desc = "Experience still needed for the next level, shortened. Empty at max level." })
E:RegisterTag("xp:rested", function(unit)
	if not PlayerXP(unit) then return "" end
	local rested = Call(GetXPExhaustion)
	if not rested or rested <= 0 then return "" end
	return Short(rested)
end, XP_EVENTS, { category = "Experience", desc = "Your rested experience, shortened. Empty when you are not rested or at max level." })

E:RegisterTag("quest", function(unit)
	if not (C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest) or UnitIsPlayer(unit) then return "" end
	local inside = IsInInstance()
	if not Plain(inside) or inside then return "" end
	local related = C_QuestLog.UnitIsRelatedToActiveQuest(unit)
	if not Plain(related) then return "" end
	return related and "Quest" or ""
end, "QUEST_LOG_UPDATE UNIT_QUEST_LOG_CHANGED", { category = "Other", desc = "Quest when the unit is part of one of your quests (outside instances)." })

---------------------------------------------------------------------------
-- Compile and render
---------------------------------------------------------------------------
local function Lookup(content)
	local tag = tags[content]
	if tag then return tag, nil end
	local base, arg = content:match("^(.-):([^:]+)$")
	tag = base and tags[base]
	if tag and tag.arg then return tag, arg end
	-- name:short etc. are arguments of [name].
	return nil
end

local function Compile(tagString)
	tagString = tagString or ""
	local cached = compiled[tagString]
	if cached then return cached end
	local format, parts, events = {}, {}, {}
	local timer
	local position = 1
	local literalBefore = false
	while true do
		local first, last, content = tagString:find("%[([^%[%]]+)%]", position)
		if not first then break end
		local literal = tagString:sub(position, first - 1)
		if literal ~= "" then literalBefore = true end
		format[#format + 1] = (literal:gsub("%%", "%%%%"))
		local tag, arg = Lookup(content)
		if tag then
			format[#format + 1] = "%s"
			parts[#parts + 1] = { tag = tag, arg = arg, lead = (#parts == 0 and not literalBefore) }
			for _, event in ipairs(tag.events) do events[event] = true end
			if tag.timer then timer = math.min(timer or tag.timer, tag.timer) end
		else
			format[#format + 1] = (("[" .. content .. "]"):gsub("%%", "%%%%"))
			literalBefore = true
		end
		position = last + 1
	end
	format[#format + 1] = (tagString:sub(position):gsub("%%", "%%%%"))
	cached = { format = table.concat(format), parts = parts, events = events, timer = timer }
	compiled[tagString] = cached
	return cached
end

local values = {}

-- Returns the text and, when the first tag is [healthcolor], the color
-- object for SetTextColor.
local function Build(tagString, unit, user)
	local tag = Compile(tagString)
	local leadColor
	local outerUser = nameUser
	nameUser = user
	for index, part in ipairs(tag.parts) do
		local ok, value = pcall(part.tag.fn, unit, part.arg)
		if not ok or type(value) == "nil" then
			value = ""
		-- type() first: getmetatable on a secret string is an error.
		elseif type(value) == "table" and getmetatable(value) == ColorResult then
			local color = value.color
			value = ""
			if part.lead then
				leadColor = color
			elseif type(color) == "table" and color.GetRGB then
				value = ColorCode(color:GetRGB())
			end
		end
		values[index] = value
	end
	nameUser = outerUser
	local ok, text = pcall(string.format, tag.format, unpack(values, 1, #tag.parts))
	for index = 1, #tag.parts do values[index] = nil end
	return ok and text or "", leadColor
end

function E:FormatTag(tagString, unit, user)
	if not tagString or tagString == "" or not unit then return "" end
	return (Build(tagString, unit, user))
end

local colored = setmetatable({}, { __mode = "k" })   -- fontString -> true while [healthcolor] tints it

function E:RenderTag(fontString, tagString, unit, user)
	if not fontString then return end
	if not tagString or tagString == "" or not unit or not UnitExists(unit) then
		fontString:SetText("")
		return
	end
	local text, color = Build(tagString, unit, user)
	fontString:SetText(text)
	if color and color.GetRGB then
		if pcall(fontString.SetTextColor, fontString, color:GetRGB()) then colored[fontString] = true end
	elseif colored[fontString] then
		colored[fontString] = nil
		fontString:SetTextColor(1, 1, 1)
	end
end

function E:TagEvents(tagString)
	local list = {}
	for event in pairs(Compile(tagString).events) do list[#list + 1] = event end
	table.sort(list)
	return list
end

-- Names of the tags used in a string that the engine knows.
function E:TagUsesTimer(tagString)
	return Compile(tagString).timer ~= nil
end

---------------------------------------------------------------------------
-- Bound texts: refreshed by their own tags' events and the shared ticker.
---------------------------------------------------------------------------
local bindings = setmetatable({}, { __mode = "k" })   -- fontString -> { tagString, unit, user, compiled }
local byEvent = {}     -- event -> set of fontStrings
-- UNIT_ events also by unit: event -> unit (false: none) -> set, so a
-- raid member's health wakes only the texts bound to that unit.
local byUnit = {}
local timed = setmetatable({}, { __mode = "k" })      -- fontString -> true
local eventFrame = CreateFrame("Frame")
local ticker

local function Render(fontString, binding)
	E:RenderTag(fontString, binding.tagString, binding.unit, binding.user)
end

local function RemoveEvents(fontString, binding)
	for event in pairs(binding.compiled.events) do
		local units = byUnit[event]
		local bucket = units and units[binding.unit or false]
		if bucket then
			bucket[fontString] = nil
			if next(bucket) == nil then units[binding.unit or false] = nil end
		end
		local set = byEvent[event]
		if set then
			set[fontString] = nil
			if next(set) == nil then
				byEvent[event] = nil
				byUnit[event] = nil
				eventFrame:UnregisterEvent(event)
			end
		end
	end
end

local function UpdateTicker()
	local need = next(timed) ~= nil
	if need and not ticker then
		ticker = C_Timer.NewTicker(0.5, function()
			for fontString in pairs(timed) do
				local binding = bindings[fontString]
				if binding and fontString:IsVisible() then Render(fontString, binding) end
			end
			if next(timed) == nil and ticker then
				ticker:Cancel()
				ticker = nil
			end
		end)
	elseif not need and ticker then
		ticker:Cancel()
		ticker = nil
	end
end

eventFrame:SetScript("OnEvent", function(_, event, unit)
	local set = byEvent[event]
	if not set then return end
	-- A unit event reaches only its unit's texts; the player's UNIT_PET
	-- (a new pet) and the other events reach every bound text.
	local units = byUnit[event]
	if units and not (unit == "player" and event == "UNIT_PET") then
		set = units[unit or false]
		if not set then return end
	end
	for fontString in pairs(set) do
		local binding = bindings[fontString]
		if binding then Render(fontString, binding) end
	end
end)

function E:BindTag(fontString, tagString, unit, user)
	if not fontString then return end
	local old = bindings[fontString]
	if old then RemoveEvents(fontString, old) end
	if not tagString or tagString == "" then
		bindings[fontString] = nil
		timed[fontString] = nil
		UpdateTicker()
		fontString:SetText("")
		return
	end
	local binding = { tagString = tagString, unit = unit, user = user, compiled = Compile(tagString) }
	bindings[fontString] = binding
	for event in pairs(binding.compiled.events) do
		if not byEvent[event] then
			byEvent[event] = {}
			eventFrame:RegisterEvent(event)
		end
		byEvent[event][fontString] = true
		if event:sub(1, 5) == "UNIT_" then
			local units = byUnit[event]
			if not units then
				units = {}
				byUnit[event] = units
			end
			local key = unit or false
			units[key] = units[key] or {}
			units[key][fontString] = true
		end
	end
	timed[fontString] = binding.compiled.timer and true or nil
	UpdateTicker()
	Render(fontString, binding)
end

function E:UnbindTag(fontString)
	local binding = bindings[fontString]
	if not binding then return end
	RemoveEvents(fontString, binding)
	bindings[fontString] = nil
	timed[fontString] = nil
	UpdateTicker()
end

-- Re-render every bound text (of one unit, or all).
function E:UpdateTags(unit)
	for fontString, binding in pairs(bindings) do
		if not unit or binding.unit == unit then Render(fontString, binding) end
	end
end

E:RegisterEvent("PLAYER_ENTERING_WORLD", function() E:UpdateTags() end, bindings)

---------------------------------------------------------------------------
-- Text slots: a preset dropdown, with a custom tag string for those who
-- want one (rare, so it carries `cog = true`).
--   block = { preset = "name", custom = "" }
---------------------------------------------------------------------------
E.TAG_PRESETS = {
	name = { title = "Name", tag = "[name]" },
	-- Older profiles: "Name (name format)" is what [name] does now. Not
	-- offered any more; E:TagForSlot moves a saved one to "name".
	nameformat = { title = "Name", tag = "[name]" },
	namelevel = { title = "Name + level", tag = "[difficultycolor][level:smart][close] [name]" },
	healthpercent = { title = "Health %", tag = "[health:percent]" },
	healthcurrent = { title = "Health current", tag = "[health:current]" },
	healthdeficit = { title = "Missing health", tag = "[health:deficit]" },
	healthcurrentmax = { title = "Health current / max", tag = "[health:current-max]" },
	healthcurrentpercent = { title = "Health current | %", tag = "[health:current-percent]" },
	powerpercent = { title = "Power %", tag = "[power:percent]" },
	status = { title = "Status (AFK, dead ...)", tag = "[status]" },
	platelevel = { title = "Level + elite mark", tag = "[difficultycolor][level:smart][classification:short][close]" },
	off = { title = "Off", tag = "" },
}

function E:TagForSlot(block)
	if type(block) ~= "table" then return "" end
	if block.preset == "nameformat" then block.preset = "name" end
	if block.preset == "custom" then return block.custom or "" end
	local preset = self.TAG_PRESETS[block.preset]
	return preset and preset.tag or ""
end

-- prefix: dotted path of the slot block; opts.label, opts.presets (list of
-- preset keys to offer), opts.hidden, opts.db (function: module settings).
function E:TagSlotOptions(prefix, opts)
	opts = opts or {}
	local choices = { custom = "Custom tags" }
	for _, key in ipairs(opts.presets or { "name", "namelevel", "healthpercent", "healthcurrentmax", "off" }) do
		choices[key] = self.TAG_PRESETS[key] and self.TAG_PRESETS[key].title
	end
	local function Block()
		local db = opts.db and opts.db()
		return db and E.GetPath and E.GetPath(db, prefix)
	end
	return {
		{ type = "select", key = prefix .. ".preset", label = opts.label or "Text", values = choices, hidden = opts.hidden,
			desc = "What this text shows. Custom tags lets you write your own, e.g. [name:short] [health:percent]; the Text tags page lists every tag." },
		{ type = "input", key = prefix .. ".custom", label = "Custom tags", cog = true,
			desc = "Your own tag string, used when the text is set to Custom tags. Example: [classcolor][name:medium][close] [level]",
			hidden = function()
				if opts.hidden and opts.hidden() then return true end
				local block = Block()
				return block ~= nil and block.preset ~= "custom"
			end },
	}
end

---------------------------------------------------------------------------
-- General > Text tags: the reference, with a live preview.
---------------------------------------------------------------------------
local preview = { sample = "[classcolor][name:medium][close] [level:smart] [health:percent]" }
local previewProxy = setmetatable({}, {
	__index = function(_, key)
		if key == "sample" then return preview.sample end
		if key == "player" or key == "target" then
			if not UnitExists(key) then return "" end
			local text = E:FormatTag(preview.sample, key)
			if not Plain(text) then return L["(the game hides this right now)"] end
			return text
		end
	end,
	__newindex = function(_, key, value)
		if key == "sample" then preview.sample = tostring(value or "") end
	end,
})

local function ReferenceOptions()
	local options = {
		{ type = "description", label = "Text tags decide what a unit frame, group frame or nameplate text shows. Mix them with your own text: \"[name:short] [health:percent]\"." },
		{ type = "header", label = "Try it" },
		{ type = "input", key = "sample", label = "Try tags", desc = "Type tags and press Enter to see the result below." },
		{ type = "input", key = "player", label = "On you (read only)", desc = "What the tag string shows on your own character right now. Typing here changes nothing.",
			hidden = function() return false end },
		{ type = "input", key = "target", label = "On your target (read only)", desc = "What the tag string shows on your target. Target something to see it.",
			hidden = function() return not UnitExists("target") end },
	}
	local byCategory = {}
	for name, tag in pairs(tags) do
		if name == tag.name then
			byCategory[tag.category] = byCategory[tag.category] or {}
			table.insert(byCategory[tag.category], tag)
		end
	end
	local order = {}
	for _, category in ipairs(CATEGORY_ORDER) do order[#order + 1] = category end
	for category in pairs(byCategory) do
		if not tContains(order, category) then order[#order + 1] = category end
	end
	for _, category in ipairs(order) do
		local list = byCategory[category]
		if list then
			table.sort(list, function(a, b) return a.name < b.name end)
			table.insert(options, { type = "header", label = category })
			-- One term per tag: the renderer draws the tag in body text and
			-- its meaning in the secondary color.
			-- A description is plain text: a bar in it (12.3K | 75%) is doubled
			-- so the text shows it instead of reading it as a text code.
			local terms = {}
			for _, tag in ipairs(list) do
				local desc = tag.desc and L[tag.desc] or ""
				terms[#terms + 1] = { tag.example or ("[" .. tag.name .. "]"), (desc:gsub("|", "||")) }
			end
			table.insert(options, { type = "description", terms = terms })
		end
	end
	return options
end

E:RegisterEvent("PLAYER_LOGIN", function()
	local page = E:RegisterConfigPage("tags", E.Key("Text tags"), ReferenceOptions(), function() return previewProxy end, function() end, 1.3)
	page.desc = L["Every text tag with what it shows, and a place to try tag strings."]
end, preview, "pages")
