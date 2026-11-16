-- EldoUI Nameplates options page, style filter rules and style presets.
-- Loaded right after Modules/Nameplates.lua and before Size.lua (which
-- adds its rows to the same page); adds to the same module.
--
--   Rule list       style filter rules: add, remove, move, export, import,
--                   check your target
--   Options         every tab of the Nameplates page (M.options)
--   Style presets   the Nameplates styles (E:RegisterStyles)
--
-- The helpers it shares with Modules/Nameplates.lua come through the
-- module table (M.inner), set at the end of that file. The profile is read
-- through M.inner.PlateDB() and never kept here: the plates swap it on a
-- profile change.
local _, E = ...
local L = E.L
local Key = E.Key
local M = E:GetModule("Nameplates")
if not M then return end

local inner = M.inner
local FX_CONSUMER, ELEMENT, MAX_RULES = inner.FX_CONSUMER, inner.ELEMENT, inner.MAX_RULES
local TYPES, TYPE_TITLES, TypeDefaults = inner.TYPES, inner.TYPE_TITLES, inner.TypeDefaults
local RULE_DEFAULTS, NormalizeRule, Rules = inner.RULE_DEFAULTS, inner.NormalizeRule, inner.Rules
local FilterContext, Matches = inner.FilterContext, inner.Matches
local pool, PlateFor, Friendly = inner.pool, inner.PlateFor, inner.Friendly
local Allowed, IsTankMode, Refresh = inner.Allowed, inner.IsTankMode, inner.Refresh
local PlateDB, UsePlateDB = inner.PlateDB, inner.UsePlateDB

-- Two blocks (rule list and options, then styles), each with its own
-- helpers.
local SuggestedStyle
do
---------------------------------------------------------------------------
-- Style filter rule list: add, remove, move, export, import, check.
---------------------------------------------------------------------------
local function EditIndex()
	local rules = Rules()
	local index = tonumber(PlateDB().styleFilters.edit) or 1
	return math.max(1, math.min(index, math.max(#rules, 1)))
end

local function Changed()
	if M.active then E:RunOutOfCombat(Refresh) end
	if E.RefreshConfig then E:RefreshConfig() end
end

function M:AddRule(template)
	local db = UsePlateDB()
	local rules = Rules()
	if #rules >= MAX_RULES then
		E:Print(L["Nameplates: at most %d style filter rules."]:format(MAX_RULES))
		return
	end
	local rule = NormalizeRule(CopyTable(template or {}))
	if template then rule.name = L[template.name] else rule.name = L["Rule %d"]:format(#rules + 1) end
	table.insert(rules, rule)
	db.styleFilters.edit = #rules
	Changed()
end

function M:RemoveRule()
	local db = UsePlateDB()
	local rules = Rules()
	if #rules == 0 then return end
	table.remove(rules, EditIndex())
	db.styleFilters.edit = math.max(1, math.min(EditIndex(), #rules))
	Changed()
end

function M:MoveRule(step)
	local db = UsePlateDB()
	local rules = Rules()
	local index = EditIndex()
	local other = index + step
	if not rules[index] or not rules[other] then return end
	rules[index], rules[other] = rules[other], rules[index]
	db.styleFilters.edit = other
	Changed()
end

-- Rules as text: "!EUIPF1!" then "index.key=value" entries separated by
-- ";". Values: b:1/b:0, n:<number>, c:r,g,b, s:<text with %XX escapes>.
-- Read back by our own parser; nothing is ever run as code.
local EXPORT_PREFIX = "!EUIPF1!"

local function Escape(text)
	return (tostring(text):gsub("[%%;=\n|]", function(c) return ("%%%02X"):format(c:byte()) end))
end

local function Unescape(text)
	return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

function M:ExportRules()
	local db = UsePlateDB()
	local parts = {}
	for index, rule in ipairs(Rules()) do
		local keys = {}
		for key in pairs(RULE_DEFAULTS) do keys[#keys + 1] = key end
		table.sort(keys)
		for _, key in ipairs(keys) do
			local value, default = rule[key], RULE_DEFAULTS[key]
			local encoded
			if type(value) == "table" then
				if not E.DeepEqual(value, default) then encoded = ("c:%.3f,%.3f,%.3f"):format(value[1] or 1, value[2] or 1, value[3] or 1) end
			elseif value ~= default or key == "name" then
				if type(value) == "boolean" then
					encoded = value and "b:1" or "b:0"
				elseif type(value) == "number" then
					encoded = "n:" .. tostring(value)
				else
					encoded = "s:" .. Escape(value)
				end
			end
			if encoded then parts[#parts + 1] = ("%d.%s=%s"):format(index, key, encoded) end
		end
	end
	return EXPORT_PREFIX .. table.concat(parts, ";")
end

-- Adds the rules in `text` after the current ones. Returns the number
-- added, or nil and a reason.
function M:ImportRules(text)
	local db = UsePlateDB()
	if type(text) ~= "string" then return nil, L["That is not a style filter string."] end
	text = strtrim(text)
	if text:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then return nil, L["That is not an EldoUI nameplate style filter string."] end
	local found = {}
	for entry in text:sub(#EXPORT_PREFIX + 1):gmatch("[^;]+") do
		local index, key, kind, raw = entry:match("^(%d+)%.(%w+)=(%a):(.*)$")
		index = tonumber(index)
		local default = key and RULE_DEFAULTS[key]
		if index and index <= MAX_RULES and default ~= nil then
			local value
			if kind == "b" then
				value = raw == "1"
			elseif kind == "n" then
				value = tonumber(raw)
			elseif kind == "c" then
				local r, g, b = raw:match("^([%d%.]+),([%d%.]+),([%d%.]+)$")
				if r then value = { tonumber(r), tonumber(g), tonumber(b) } end
			elseif kind == "s" then
				value = Unescape(raw)
			end
			if value ~= nil and type(value) == type(default) then
				found[index] = found[index] or {}
				found[index][key] = value
			end
		end
	end
	local rules = Rules()
	local added = 0
	for index = 1, MAX_RULES do
		local rule = found[index]
		if rule and #rules < MAX_RULES then
			table.insert(rules, NormalizeRule(rule))
			added = added + 1
		end
	end
	if added == 0 then return nil, L["No rules found in that string."] end
	db.styleFilters.edit = #rules
	Changed()
	return added
end

-- Which rules match your target right now (out of combat).
function M:CheckTarget()
	local db = UsePlateDB()
	local nameplate = PlateFor("target")
	local plate = nameplate and pool[nameplate]
	if not (plate and plate.unit and (plate.baseKind == "FULL" or plate.baseKind == "NAME")) then
		E:Print(L["Nameplates: target a unit that has an EldoUI plate first."])
		return
	end
	local ctx = FilterContext()
	local names = {}
	for index, rule in ipairs(Rules()) do
		if rule.enabled and Matches(rule, plate, ctx) then names[#names + 1] = ("%d. %s"):format(index, rule.name) end
	end
	if #names == 0 then
		E:Print(L["Nameplates: no style filter rule matches your target."])
	else
		E:Print(L["Nameplates: rules matching your target: %s"]:format(table.concat(names, ", ")))
	end
end

-- Starter rules the "Add example" picker offers. A rule name is the
-- player's own text once added, so it is stored in their language.
local EXAMPLES = {
	elites = { name = Key("Elites stand out"), reaction = "hostile", unitType = "npc", classification = "elite", raise = true, glow = "glow" },
	totems = { name = Key("Enemy totems small"), creature = "totem", scale = 0.7 },
	quest = { name = Key("Quest mobs bright"), quest = "yes", nameColorOn = true, nameColor = { 1, 0.82, 0 } },
	pets = { name = Key("Fade enemy pets"), reaction = "hostile", creature = "pet", alpha = 0.5, scale = 0.8 },
	behind = { name = Key("Hide plates behind the camera"), behindCamera = "yes", hide = true },
	tankThreat = { name = Key("Tank: lost threat glow"), role = "TANK", reaction = "hostile", unitCombat = "yes", threatBorder = "glow" },
	bossExecute = { name = Key("Execute shade only on bosses"), classification = "worldboss", execute = "on" },
	-- Totems: an enemy shaman's totems easy to spot, your group's out of the way.
	-- `desc` is only the button's tooltip; the rule itself keeps no text.
	enemyTotems = { name = Key("Enemy totems: name on top"), reaction = "hostile", creature = "totem", nameOnly = true, raise = true,
		nameColorOn = true, nameColor = { 1, 0.5, 0.25 },
		desc = "Adds a ready-made rule at the end of the list: enemy totems show as an orange name above other plates. It stands down in dungeons and raids." },
	groupTotems = { name = Key("Friendly totems: small name"), reaction = "friendly", creature = "totem", nameOnly = true, scale = 0.7,
		desc = "Adds a ready-made rule at the end of the list: your group's totems show as a small name. Needs friendly minion plates (Game settings tab); stands down in instances." },
}

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
-- Bar texture and font rows are media rows (the registry's live list).

local function SetMode(enabled, replace)
	E:SetBlizzardElement(ELEMENT, "enabled", enabled)
	if enabled then
		E:SetBlizzardElement(ELEMENT, "replace", replace)
		if not replace then E:SetBlizzardElement(ELEMENT, "skin", true) end
	end
	if E.RefreshConfig then E:RefreshConfig() end
end

-- The nameplate style the current layout names (Core/Layout.lua `suggest`).
function SuggestedStyle()
	local layout = E.db and E.db.general and E.db.general.layout
	local info = layout and E.LayoutRecord and E:LayoutRecord(layout)
	local key = info and info.suggest and info.suggest.Nameplates
	if type(key) ~= "string" then return nil end
	for _, style in ipairs(E.styles and E.styles.Nameplates or {}) do
		if style.key == key then return key end
	end
end

-- `hidden` for the "needs this switch" notes: hidden once the switch is on.
local function HasSwitch(action)
	return function() return Allowed(action) end
end

local SHOW_VALUES = { KEEP = "Game setting", ON = "On", OFF = "Off" }
local STACK_VALUES = { KEEP = "Game setting", STACK = "Stacking", OVERLAP = "Overlapping" }
local function DB() return M.db end

-- One tab per plate type.
local function TypeOptions(key)
	local p = "types." .. key .. "."
	local npc = key == "enemyNPC" or key == "friendlyNPC"
	local player = not npc
	local enemy = key == "enemyNPC" or key == "enemyPlayer"
	local function Type() return M.db.types[key] end
	local function Off() return not Type().enabled end
	local function NameOnly() return Off() or Type().nameOnly end
	local function CastOff() return NameOnly() or not Type().castbar.enabled end
	local copyValues = {}
	for _, other in ipairs(TYPES) do copyValues["types." .. other] = TYPE_TITLES[other] end
	local rows = {
		{ type = "tab", label = TYPE_TITLES[key] },
		{ type = "header", label = TYPE_TITLES[key] },
		E:CopySettingsOptions({ path = "types." .. key, values = copyValues,
			desc = "Copy every setting on this tab from another plate type, with a preview of what changes first. This type's on/off switch stays as it is." })[1],
		{ type = "toggle", key = p .. "enabled", label = "EldoUI plates for this type",
			desc = "Off leaves these plates exactly as Blizzard draws them. Friendly plates inside instances always stay Blizzard's." },
		{ type = "toggle", key = p .. "nameOnly", label = "Name only", hidden = Off,
			desc = "Just the name in class or reaction color, no bar." },
		{ type = "execute", label = "Reset this type", confirm = true,
			desc = "Put this tab's settings back to EldoUI's defaults. This type's on/off switch stays as it is.",
			func = function() M:ResetType(key) end },
		{ type = "header", label = "Size", hidden = NameOnly },
		{ type = "range", unit = "px", key = p .. "width", label = "Width", min = 60, max = 250, step = 1, hidden = NameOnly,
			desc = "Width of the health bar in pixels." },
		{ type = "range", unit = "px", key = p .. "height", label = "Height", min = 4, max = 30, step = 1, hidden = NameOnly,
			desc = "Height of the health bar in pixels." },
		{ type = "range", key = p .. "combatWidth", label = "Width in combat", unit = "px", zeroText = "Same", min = 0, max = 250, step = 1, cog = true,
			hidden = NameOnly, desc = "Plate width in pixels while you are in combat." },
		{ type = "range", key = p .. "combatHeight", label = "Height in combat", unit = "px", zeroText = "Same", min = 0, max = 30, step = 1, cog = true,
			hidden = NameOnly, desc = "Plate height in pixels while you are in combat." },
		{ type = "toggle", key = p .. "power", label = "Power bar", hidden = NameOnly,
			desc = "A thin bar with the unit's mana, rage or energy under the health bar." },
		{ type = "range", unit = "px", key = p .. "powerHeight", label = "Power bar height", min = 2, max = 10, step = 1, cog = true,
			hidden = function() return NameOnly() or not Type().power end, desc = "Height of the power bar." },
		{ type = "header", label = "Text" },
		{ type = "select", key = p .. "nameText", label = "Name position", values = { LEFT = "Left", CENTER = "Center", NONE = "Hidden" },
			hidden = NameOnly, desc = "Where the unit's name sits above the bar." },
		{ type = "select", key = p .. "healthPosition", label = "Health text position", values = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" },
			order = { "LEFT", "CENTER", "RIGHT" }, hidden = NameOnly, desc = "Where the health text sits inside the bar." },
		{ type = "range", unit = "px", key = p .. "healthSize", label = "Health text size", min = 0, max = 20, step = 1, zeroText = "Auto",
			hidden = NameOnly, desc = "Size of the health text. Auto uses the plate text size, smaller on a thin bar so it stays inside." },
	}
	local function Add(list)
		for _, row in ipairs(list) do rows[#rows + 1] = row end
	end
	Add(E:TagSlotOptions(p .. "nameTag", { label = "Name text", db = DB, hidden = Off,
		presets = { "name", "namelevel", "off" } }))
	Add(E:TagSlotOptions(p .. "healthTag", { label = "Health text", db = DB, hidden = NameOnly,
		presets = { "healthpercent", "healthcurrent", "healthcurrentpercent", "healthcurrentmax", "off" } }))
	Add(E:TagSlotOptions(p .. "levelTag", { label = "Level text", db = DB, hidden = NameOnly,
		presets = { "platelevel", "off" } }))
	if npc then
		Add({ { type = "toggle", key = p .. "title", label = "NPC title", hidden = Off,
			desc = "The NPC's title (Innkeeper, Flight Master) as the game shows it. Outside instances only." } })
	end
	Add({
		{ type = "header", label = "Icons", hidden = Off },
		{ type = "toggle", key = p .. "raidMarker", label = "Raid marker", hidden = NameOnly, desc = "Raid target marker left of the bar." },
		{ type = "toggle", key = p .. "portrait", label = player and L["Class icon"] or L["Portrait"], hidden = NameOnly,
			desc = player and L["The player's class icon left of the bar."] or L["The unit's portrait left of the bar."] },
		{ type = "toggle", key = p .. "icons", label = "Elite, quest and totem icons", hidden = Off,
			desc = "The extra icons from the Indicators tab on this type." },
	})
	if player then
		Add({ { type = "select", key = p .. "pvp", label = "PvP badge", hidden = Off,
			values = { NONE = "Off", PVP = "When flagged for PvP", FACTION = "Always the faction" },
			desc = "Alliance, Horde or free-for-all badge by the name." } })
	end
	Add({
		{ type = "header", label = "Cast bar", hidden = NameOnly },
		{ type = "toggle", key = p .. "castbar.enabled", label = "Enable", hidden = NameOnly, desc = "Show this type's casts under the plate. Display only." },
		{ type = "range", unit = "px", key = p .. "castbar.height", label = "Height", min = 4, max = 20, step = 1, hidden = CastOff, desc = "Height of the cast bar." },
		{ type = "select", key = p .. "castbar.icon", label = "Spell icon", values = { LEFT = "Left", RIGHT = "Right", NONE = "Hidden" },
			hidden = CastOff, desc = "Which side of the cast bar the spell icon sits on." },
		{ type = "range", unit = "px", key = p .. "castbar.iconSize", label = "Icon size", zeroText = "Bar height", min = 0, max = 40, step = 1, cog = true,
			hidden = CastOff, desc = "Size of the spell icon." },
		{ type = "select", key = p .. "castbar.time", label = "Time", values = { REMAINING = "Time left", TOTAL = "Time left / total", NONE = "Hidden" },
			hidden = CastOff, desc = "The cast time on the right of the bar." },
		{ type = "range", key = p .. "castbar.nameSize", label = "Spell name size", min = 6, max = 20, step = 1, cog = true,
			hidden = CastOff, desc = "Font size of the spell name." },
		{ type = "range", key = p .. "castbar.timeSize", label = "Time size", min = 6, max = 20, step = 1, cog = true,
			hidden = CastOff, desc = "Font size of the cast time." },
		{ type = "range", key = p .. "castbar.hold", label = "\"Interrupted\" shown for", unit = "s", min = 0.2, max = 2, step = 0.1, cog = true,
			hidden = CastOff, desc = "How long the interrupted strip stays." },
		{ type = "header", label = "Auras", hidden = NameOnly },
		{ type = "toggle", key = p .. "debuffs.enabled", label = "Debuffs", hidden = NameOnly, desc = "The debuffs picked by the Auras tab filter, above the plate." },
		{ type = "range", key = p .. "debuffs.size", label = "Debuff size", min = 10, max = 40, step = 1,
			hidden = function() return NameOnly() or not Type().debuffs.enabled end, desc = "Size of the debuff icons." },
		{ type = "range", key = p .. "debuffs.max", label = "Maximum debuffs", min = 1, max = 10, step = 1, cog = true,
			hidden = function() return NameOnly() or not Type().debuffs.enabled end, desc = "At most this many debuffs." },
	})
	if enemy then
		Add({
			{ type = "toggle", key = p .. "buffs.enabled", label = "Buffs", hidden = NameOnly, desc = "The enemy's buffs picked on the Auras tab." },
			{ type = "range", key = p .. "buffs.size", label = "Buff size", min = 10, max = 40, step = 1,
				hidden = function() return NameOnly() or not Type().buffs.enabled end, desc = "Size of the buff icons." },
			{ type = "range", key = p .. "buffs.max", label = "Maximum buffs", min = 1, max = 8, step = 1, cog = true,
				hidden = function() return NameOnly() or not Type().buffs.enabled end, desc = "At most this many buffs." },
		})
	end
	return rows
end

-- Rule editor rows: their keys follow the rule picked in "Edit rule".
local function NoRules() return #Rules() == 0 end
local function R(field)
	return function() return ("styleFilters.rules.%d.%s"):format(EditIndex(), field) end
end
local function RuleField(field)
	local rule = Rules()[EditIndex()]
	return rule and rule[field]
end
local ANY_YES_NO = { any = "Don't care", yes = "Yes", no = "No" }

local function RuleValues()
	local values = {}
	for index, rule in ipairs(Rules()) do
		values[index] = rule.enabled == false and L["%d. %s (off)"]:format(index, tostring(rule.name)) or ("%d. %s"):format(index, tostring(rule.name))
	end
	if next(values) == nil then values[1] = L["No rules yet"] end
	return values
end

local function FilterOptions()
	local hiddenRule = NoRules
	local function Trigger(field, label, values, desc, cog)
		return { type = "select", key = R(field), label = label, values = values, desc = desc, hidden = hiddenRule, cog = cog }
	end
	local list = {
		{ type = "tab", label = "Style filters" },
		{ type = "description", label = "Rules that change how some EldoUI plates look. For each action, the first matching rule wins. Rules use only what the game shows you." },
		{ type = "toggle", key = "styleFilters.enabled", label = "Use style filters", desc = "Turn every rule on or off at once." },
		{ type = "header", label = "Rules" },
		{ type = "select", key = "styleFilters.edit", label = "Edit rule", values = RuleValues,
			desc = "The rule the rows below change. Rules higher in the list win." },
		{ type = "execute", label = "New rule", desc = "Add an empty rule at the end of the list.", func = function() M:AddRule() end },
		{ type = "execute", label = "Delete this rule", confirm = L["Delete this rule? This can't be undone."], desc = "Remove the rule shown below.", hidden = hiddenRule, func = function() M:RemoveRule() end },
		{ type = "execute", label = "Move up", desc = "Higher in the list: this rule wins over the ones below.", hidden = hiddenRule, func = function() M:MoveRule(-1) end },
		{ type = "execute", label = "Move down", desc = "Lower in the list.", hidden = hiddenRule, func = function() M:MoveRule(1) end },
		{ type = "execute", label = "Check your target", desc = "Shows which rules match your current target (out of combat).", hidden = hiddenRule,
			testSafe = true, func = function() M:CheckTarget() end },
		{ type = "execute", label = "Export rules", desc = "A text string with every rule, to share or keep.", testSafe = true,
			func = function() E:ShowCopyBox(L["Export nameplate style filters"], L["Copy this string (Ctrl+C)."], M:ExportRules()) end },
		{ type = "execute", label = "Import rules", desc = "Paste a style filter string. Its rules are added after yours; nothing is overwritten.",
			func = function()
				E:ShowPasteBox(L["Import nameplate style filters"], L["Paste a style filter string (Ctrl+V) and click Save."], function(text)
					local added, err = M:ImportRules(text)
					E:Print(added and L["Nameplates: %d style filter rules imported."]:format(added) or err)
				end)
			end },
		{ type = "header", label = "Rule", hidden = hiddenRule },
		{ type = "toggle", key = R("enabled"), label = "Rule on", desc = "Use this rule.", hidden = hiddenRule },
		{ type = "input", key = R("name"), label = "Name", desc = "A name for the rule list.", hidden = hiddenRule },
		{ type = "header", label = "When", hidden = hiddenRule },
		Trigger("reaction", "Reaction", { any = "Don't care", hostile = "Hostile", neutral = "Neutral", friendly = "Friendly" }, E.Key("How the unit stands towards you.")),
		Trigger("unitType", "Unit", { any = "Don't care", player = "Player", npc = "NPC" }, E.Key("Players or NPCs.")),
		Trigger("classification", E.Key("Classification"), { any = "Don't care", normal = "Normal", elite = "Elite", rare = "Rare", rareelite = "Rare elite", worldboss = "Boss", minus = "Minor" },
			E.Key("The game's classification (the dragon on the target frame).")),
		Trigger("target", E.Key("Is your target"), ANY_YES_NO, E.Key("The plate belongs to your target.")),
		Trigger("focus", E.Key("Is your focus"), ANY_YES_NO, E.Key("The plate belongs to your focus."), true),
		Trigger("mouseover", E.Key("Under the mouse"), ANY_YES_NO, E.Key("The mouse is over the unit."), true),
		Trigger("playerCombat", E.Key("You are in combat"), ANY_YES_NO, E.Key("Your own combat state.")),
		Trigger("unitCombat", E.Key("Unit in combat"), ANY_YES_NO, E.Key("The unit's combat state, when the game shows it."), true),
		Trigger("quest", "Quest mob", ANY_YES_NO, E.Key("The game marks the unit for one of your quests. Outside instances only.")),
		Trigger("creature", E.Key("Totem or pet"), { any = "Don't care", totem = "Totem", pet = "Pet or guardian" }, E.Key("Totems, or units a player controls that are not players."), true),
		Trigger("behindCamera", E.Key("Behind the camera"), ANY_YES_NO, E.Key("The unit is behind your camera."), true),
		Trigger("role", E.Key("Your role"), { any = "Don't care", TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }, E.Key("Your group role, or your spec's role."), true),
		{ type = "select", key = R("spec"), label = "Your talent group", values = { [0] = "Don't care", [1] = "First", [2] = "Second" },
			desc = "Which of your talent groups is active.", hidden = hiddenRule, cog = true },
		Trigger("instance", "Where you are", { any = "Don't care", none = "Open world", party = "Dungeon", raid = "Raid", pvp = "Battleground", arena = "Arena" },
			E.Key("The kind of place you are in."), true),
		{ type = "range", key = R("levelMin"), label = "Level from", zeroText = "Any", min = 0, max = 63, step = 1, cog = true, hidden = hiddenRule,
			desc = "Lowest unit level. Bosses (??) count as very high. Skipped when the game hides the level." },
		{ type = "range", key = R("levelMax"), label = "Level up to", zeroText = "Any", min = 0, max = 63, step = 1, cog = true, hidden = hiddenRule,
			desc = "Highest unit level." },
		{ type = "input", key = R("names"), label = "Names or NPC IDs", cog = true, hidden = hiddenRule,
			desc = "Unit names or NPC IDs, separated by commas. Only outside instances: inside, the game keeps who a unit is secret, so the rule doesn't match there." },
		Trigger("casting", E.Key("Is casting"), ANY_YES_NO, E.Key("The unit is casting or channeling a spell right now.")),
		Trigger("castImportant", E.Key("Cast is important"), { any = "Don't care", yes = "Yes" },
			E.Key("The rule's border color and glow show while the unit casts a spell the game marks as important. The game decides, even where the flag is secret."), true),
		Trigger("executeZone", E.Key("In execute range"), { any = "Don't care", yes = "Yes" },
			E.Key("The rule's border color and glow show while the unit's health is under the percent below."), true),
		{ type = "range", key = R("executeLower"), label = "Execute range below", unit = "%", min = 5, max = 50, step = 1, cog = true,
			hidden = function() return NoRules() or RuleField("executeZone") ~= "yes" end,
			desc = "The health percent \"In execute range\" starts at." },
		{ type = "header", label = "Then", hidden = hiddenRule },
		{ type = "toggle", key = R("healthColorOn"), label = "Color the bar", desc = "Give the health bar the color below.", hidden = hiddenRule },
		{ type = "color", key = R("healthColor"), label = "Bar color", desc = "The health bar color while this filter matches.", hidden = function() return NoRules() or not RuleField("healthColorOn") end },
		{ type = "toggle", key = R("borderColorOn"), label = "Color the border", desc = "Give the plate border the color below (the target highlight still wins).", hidden = hiddenRule },
		{ type = "color", key = R("borderColor"), label = "Border color", desc = "The plate border color while this filter matches.", hidden = function() return NoRules() or not RuleField("borderColorOn") end },
		{ type = "toggle", key = R("nameColorOn"), label = "Color the name", desc = "Give the name the color below.", hidden = hiddenRule },
		{ type = "color", key = R("nameColor"), label = "Name color", desc = "The name color while this filter matches.", hidden = function() return NoRules() or not RuleField("nameColorOn") end },
		{ type = "media", mediaKind = "statusbar", key = R("texture"), label = "Bar texture", default = "", defaultLabel = L["Keep the plate texture"],
			cog = true, hidden = hiddenRule, desc = "A different health bar texture." },
		{ type = "range", percent = true, key = R("scale"), label = "Scale", min = 0.5, max = 2, step = 0.05, hidden = hiddenRule, desc = "Grow or shrink the plate. 1 keeps the size." },
		{ type = "range", key = R("alpha"), label = "Opacity", percent = true, zeroText = "Normal", min = 0, max = 1, step = 0.05, hidden = hiddenRule,
			desc = "The plate's opacity. Normal keeps the usual opacity (and the non-target fade)." },
		{ type = "toggle", key = R("hide"), label = "Hide the plate", hidden = hiddenRule, desc = "Make the EldoUI plate invisible. You can still click where it is." },
		{ type = "toggle", key = R("nameOnly"), label = "Name only", hidden = hiddenRule, desc = "Show just the name, no bar." },
		{ type = "select", key = R("glow"), label = "Glow", values = { none = "None", glow = "Glow (Glows page)", flash = "Pulse" }, hidden = hiddenRule,
			desc = "Light the plate up. Glow uses the look on the Glows page (Nameplate style filters); Pulse breathes slowly, static with animations off." },
		{ type = "toggle", key = R("raise"), label = "Draw over other plates", cog = true, hidden = hiddenRule, desc = "Put this plate above overlapping plates." },
		{ type = "select", key = R("threatBorder"), label = "Threat border", hidden = hiddenRule,
			values = { keep = "As on the Effects tab", border = "Border", glow = "Glow", off = "Off" },
			desc = "The threat border on these plates, in the game's threat color. As on the Effects tab keeps your normal setting." },
		{ type = "select", key = R("execute"), label = "Execute shade", hidden = hiddenRule, cog = true,
			values = { keep = "As on the Effects tab", on = "On", off = "Off" },
			desc = "Turn the execute shade on or off for these plates only, with the range from the Effects tab." },
		{ type = "range", unit = "px", key = R("sizeWidth"), label = "Width", zeroText = "Keep", min = 0, max = 250, step = 1, cog = true, hidden = hiddenRule,
			desc = "Plate width in pixels for these plates. 0 keeps the type's width." },
		{ type = "range", unit = "px", key = R("sizeHeight"), label = "Height", zeroText = "Keep", min = 0, max = 30, step = 1, cog = true, hidden = hiddenRule,
			desc = "Plate height in pixels for these plates. 0 keeps the type's height." },
		{ type = "toggle", key = R("castTarget"), label = "Show the cast target", hidden = hiddenRule,
			desc = "The name of the spell's target under the cast bar." },
		{ type = "toggle", key = R("dim"), label = "Dim the plate", hidden = hiddenRule,
			desc = "A dark overlay over the bar that keeps the name readable." },
	}
	-- One "Add example" button per starter rule, right after "New rule".
	local at = 1
	for i, row in ipairs(list) do
		if row.label == "New rule" then at = i + 1 break end
	end
	local keys = {}
	for key in pairs(EXAMPLES) do keys[#keys + 1] = key end
	table.sort(keys)
	for i, key in ipairs(keys) do
		local template = EXAMPLES[key]
		table.insert(list, at + i - 1, { type = "execute", label = "Example: %s", labelFill = template.name, cog = true,
			desc = template.desc or E.Key("Add this ready-made rule at the end of the list. Change it like any other rule."),
			func = function() M:AddRule(template) end })
	end
	return list
end

-- Preview: one plate of the test plate's type, in its size, text size
-- and cast bar (E:ConfigSample, Core/MoverSamples.lua).
local function UpdatePreview(canvas)
	local settings = M.db
	local t = settings and settings.types and settings.types[settings.testType or "enemyNPC"]
	if not (canvas and t) then return end
	local enemy = settings.testType == "enemyNPC" or settings.testType == "enemyPlayer"
	local cast = t.castbar or {}
	E:ConfigSample(canvas, "plate", {
		width = t.width, height = t.nameOnly and 0.01 or t.height, fontSize = settings.fontSize,
		name = UnitName("player"), health = 0.65, color = { E:GetReactionColor(enemy and 2 or 5) },
		castHeight = cast.enabled and not t.nameOnly and cast.height or 0, castText = L["Casting"],
		castColor = settings.castbar and settings.castbar.color,
	})
end

M.options = {
	{ type = "tab", label = "General" },
	{ type = "preview", label = "Preview", height = 64, create = UpdatePreview, update = UpdatePreview,
		desc = "A plate of the test plate's type, in its size, text size and cast bar." },
	{ type = "header", label = "Mode" },
	-- The mode that draws the plates right now, so the three buttons below
	-- never leave it to guesswork.
	{ type = "description", label = function()
		if not M.active then return L["Showing now: Blizzard's plates (the Nameplates module is off)."] end
		local mode = M:GetPlateMode()
		if mode == "ELDOUI" then return L["Showing now: EldoUI plates. Blizzard's plate is faded out under them."] end
		if mode == "BLIZZARD" then return L["Showing now: Blizzard plates with EldoUI's look."] end
		return L["Showing now: Blizzard default plates."]
	end },
	{ type = "description", hidden = function() return Allowed() end,
		label = "Nameplates are Blizzard default right now. EldoUI leaves the plates and their settings alone until you pick a mode below.", tone = "warning" },
	{ type = "description", label = "EldoUI plates draw EldoUI's own bar, set per unit type in the next tabs. Blizzard plates keep their layout with EldoUI's texture and font." },
	{ type = "execute", label = "Use EldoUI plates", desc = "Replaces every nameplate with EldoUI's own bars, set up on the tabs below.",
		func = function() SetMode(true, true) end },
	{ type = "execute", label = "Use Blizzard plates", desc = "Keeps the game's nameplates and gives them EldoUI's texture, border, font and extra icons.",
		func = function() SetMode(true, false) end },
	{ type = "execute", label = "Blizzard default", desc = "Puts the game's nameplates and your own nameplate settings back. Asks for a reload.",
		func = function() SetMode(false) end },

	{ type = "header", label = "Look" },
	{ type = "media", mediaKind = "statusbar", key = "texture", label = "Bar texture", default = "theme", defaultLabel = Key("Theme texture"),
		desc = "Texture of the health, power and cast bars, also used on Blizzard's plates in Blizzard mode. Theme texture follows the General page." },
	{ type = "media", mediaKind = "font", key = "font", label = "Font", default = "THEME", defaultLabel = Key("Theme font"),
		desc = "Font for names, health and cast text. Theme font follows the General page." },
	{ type = "select", key = "fontOutline", label = "Outline", desc = "Outline for nameplate text. Theme follows the General page.",
		values = { THEME = "Theme", NONE = "None", OUTLINE = "Outline", THICKOUTLINE = "Thick outline" } },
	{ type = "range", key = "fontSize", label = "Text size", desc = "Size of names and health text.", min = 6, max = 24, step = 1 },
	{ type = "select", key = "nameColor", label = "Name color", desc = "White, or class color for players and reaction color for NPCs.", values = { WHITE = "White", REACTION = "Class / reaction" } },
	{ type = "range", unit = "px", key = "offsetY", label = "Y offset", desc = "Moves the EldoUI plate up or down on Blizzard's plate.", min = -40, max = 40, step = 1, cog = true },
	{ type = "range", key = "raidMarkerSize", label = "Raid marker size", desc = "Size of the raid marker in pixels.", min = 10, max = 40, step = 1, cog = true },
	{ type = "range", key = "minorScale", label = "Minor units scale", unit = "%", min = 50, max = 100, step = 5,
		desc = "Shrinks plates of minor (trivial) units. 100 keeps the size." },
	{ type = "range", key = "petScale", label = "Pets and guardians scale", unit = "%", min = 50, max = 100, step = 5, cog = true,
		desc = "Shrinks plates of pets, guardians and summons. 100 keeps the size." },
	-- (one "Your layout suggests ..." line per style is added after the styles below)
	{ type = "execute", label = "Use the suggested style", hidden = function() return not SuggestedStyle() end,
		desc = "Apply the nameplate style your layout names (Layouts page). Your other settings stay.",
		func = function()
			local key = SuggestedStyle()
			if key then E:ApplyStyle("Nameplates", key) end
			if E.RefreshConfig then E:RefreshConfig() end
		end },

	{ type = "header", label = "Preview" },
	{ type = "select", key = "testType", label = "Test plate type", values = TYPE_TITLES,
		desc = "Which plate type the test plate shows. It uses your own character's name and health." },
	{ type = "execute", label = "Test plate", desc = "A plate near the middle of the screen that follows your settings as you change them.",
		testSafe = true, func = function() M:ToggleTestPlate() end },
	{ type = "execute", label = "Show effects on the test plate",
		desc = "Plays every effect in turn on the test plate (threat, important cast, interrupted, execute shade, absorb, quest pop) so you can judge the look.",
		testSafe = true, func = function() M:PlayTestEffects() end },
}

local function Append(rows)
	for _, row in ipairs(rows) do table.insert(M.options, row) end
end

for _, key in ipairs(TYPES) do Append(TypeOptions(key)) end

Append({
	{ type = "tab", label = "Target" },
	{ type = "header", label = "Target" },
	{ type = "select", key = "targetIndicator", label = "Target highlight", desc = "How your target's plate is marked.",
		values = { BORDER = "Border", GLOW = "Glow", BOTH = "Border and glow", ARROWS = "Arrows", UNDERLINE = "Underline",
			OVERLAY = "Overlay", PULSE = "Pulse glow", NONE = "None" },
		valueDescs = { OVERLAY = E.Key("A light sheen on your target's bar."),
			PULSE = E.Key("A slow glow. Its look is on the Glows page (Nameplates: target).") } },
	{ less = true, type = "toggle", key = "targetAccent", label = "Highlight in the accent color", desc = "Use the EldoUI accent color for the target highlight." },
	{ type = "color", key = "targetColor", label = "Highlight color", desc = "Used when the accent color is off.", hidden = function() return M.db.targetAccent end },
	{ type = "range", key = "targetScale", label = "Target scale", unit = "%", desc = "Your target's plate grows by this much.", min = 100, max = 200, step = 5 },
	{ type = "select", key = "othersMode", label = "Others step back", values = { FADE = "Fade", DIM = "Dim", OFF = "Off" }, order = { "FADE", "DIM", "OFF" },
		desc = "How plates other than your target step back while you have one: lower opacity, or a dark overlay that keeps names readable." },
	{ type = "range", key = "nonTargetAlpha", label = "Other plates' opacity", unit = "%", desc = "Only while you have a target.", min = 20, max = 100, step = 5,
		hidden = function() return M.db.othersMode ~= "FADE" end },
	{ type = "toggle", key = "focusAsTarget", label = "Focus counts as target", cog = true,
		desc = "Your focus is not faded or dimmed either." },
	{ type = "toggle", key = "targetDetails", label = "Target plate details",
		desc = "Your target's plate also shows power, level, health and the cast target, whatever its type tab says. For layouts without a target frame." },
	{ type = "header", label = "Focus and mouse-over" },
	{ type = "toggle", key = "focusIndicator", label = "Focus border", desc = "Color the border of your focus target's plate." },
	{ type = "color", key = "focusColor", label = "Focus color", desc = "Border color of your focus target's plate.", hidden = function() return not M.db.focusIndicator end },
	{ type = "toggle", key = "mouseoverHighlight", label = "Mouse-over highlight", desc = "Brighten the plate under the mouse." },
	{ type = "toggle", key = "softTargetHighlight", label = "Highlight your soft target",
		desc = "With action targeting or a gamepad, the enemy the game picked for you gets the mouse-over look." },

	{ type = "tab", label = "Colors" },
	{ type = "header", label = "Color by" },
	{ type = "description", label = "When several colors apply, the first one in this list wins:" },
	{ type = "description", label = "Style filter, tapped, another tank, threat, health, class, friendly, boss, rare elite, miniboss, rare, quest, elite, reaction." },
	{ type = "toggle", key = "colors.classHostile", label = "Class colors for enemy players", desc = "Enemy players' bars in their class color." },
	{ type = "toggle", key = "colors.classFriendly", label = "Class colors for friendly players", desc = "Friendly players' bars in their class color." },
	{ type = "toggle", key = "colors.playerBorder", label = "Class color border on players", desc = "Players' plates get a border in their class color, so they stand out from NPCs and pets. Target, focus and rule borders come first." },
	{ type = "toggle", key = "colors.byClassification", label = "Color by elite, rare and boss", desc = "Uses the game's classification (the dragon on the target frame)." },
	{ type = "toggle", key = "colors.byQuest", label = "Color quest mobs", desc = "Mobs the game marks as part of one of your active quests." },
	{ type = "toggle", key = "colors.casters", label = "Color mana users (casters)", desc = "NPCs with a mana bar. Skipped when the game hides the power type." },
	{ type = "toggle", key = "colors.byMiniboss", label = "Miniboss / lieutenant", desc = "Mobs the game marks as lieutenants get their own color." },
	{ type = "color", key = "colors.miniboss", dependsOn = "colors.byMiniboss", label = "Miniboss color", cog = true, desc = "Bar color of lieutenants." },
	{ type = "toggle", key = "colors.byHealth", label = "Color by health",
		desc = "The bar fades from the high to the low health color as the unit loses health. Set both colors on the Colors page." },
	{ type = "header", label = "Colors" },
	{ type = "select", key = "colors.reactionSource", label = "Hostile, neutral and friendly",
		values = { general = "Colors page", own = "Own colors for nameplates" },
		desc = "Where hostile, neutral and friendly colors come from. Colors page: the Reaction colors the unit frames use too. Own colors: the three below, on nameplates only." },
	{ type = "color", key = "colors.hostile", label = "Hostile", hidden = function() return PlateDB().colors.reactionSource ~= "own" end, desc = "Hostile units, with own colors for nameplates." },
	{ type = "color", key = "colors.neutral", label = "Neutral", hidden = function() return PlateDB().colors.reactionSource ~= "own" end, desc = "Neutral units, with own colors for nameplates." },
	{ type = "color", key = "colors.friendly", label = "Friendly", hidden = function() return PlateDB().colors.reactionSource ~= "own" end, desc = "Friendly units, with own colors for nameplates." },
	{ type = "color", key = "colors.tapped", label = "Tapped by others", desc = "Mobs another player has tagged." },
	{ type = "color", key = "colors.elite", dependsOn = "colors.byClassification", label = "Elite", desc = "Bar color for elite mobs." },
	{ type = "color", key = "colors.rare", dependsOn = "colors.byClassification", label = "Rare", desc = "Bar color for rare mobs." },
	{ type = "color", key = "colors.rareElite", dependsOn = "colors.byClassification", label = "Rare elite", desc = "Bar color for rare elite mobs." },
	{ type = "color", key = "colors.boss", dependsOn = "colors.byClassification", label = "Boss", desc = "World bosses and bosses." },
	{ type = "color", key = "colors.minor", dependsOn = "colors.byClassification", label = "Minor", desc = "Minor (trivial) mobs." },
	{ type = "color", key = "colors.caster", dependsOn = "colors.casters", label = "Mana user (caster)", desc = "NPCs with a mana bar." },
	{ type = "color", key = "colors.quest", dependsOn = "colors.byQuest", label = "Quest mob", desc = "Mobs for one of your active quests." },
	{ type = "header", label = "Threat" },
	{ type = "description", label = "Uses the game's own threat state. If the game hides it, the plate keeps its normal color." },
	{ type = "toggle", key = "threat.enabled", label = "Color by threat", desc = "Color enemy NPC bars by your threat on them." },
	{ type = "select", key = "threat.mode", dependsOn = "threat.enabled", label = "Mode", desc = "Tanks want threat, damage dealers and healers don't.", values = { AUTO = "By group role", TANK = "Tank", DPS = "Damage / healer" } },
	{ type = "toggle", key = "threat.custom", dependsOn = "threat.enabled", label = "Own threat colors",
		desc = "Off: the threat colors of the Colors page, shared with the unit frames. On: the three colors below on nameplates only." },
	{ type = "color", key = "threat.good", label = "Safe", desc = "Tank: you have threat. Others: you don't.", hidden = function() return not M.db.threat.custom end },
	{ type = "color", key = "threat.transition", label = "Changing", desc = "Threat is about to change.", hidden = function() return not M.db.threat.custom end },
	{ type = "color", key = "threat.bad", label = "Danger", desc = "Tank: you lost threat. Others: the mob is on you.", hidden = function() return not M.db.threat.custom end },

	{ type = "tab", label = "Cast bar" },
	{ type = "header", label = "Cast bar" },
	{ type = "description", label = "Size, icon side and time format are set per plate type on the type tabs." },
	{ type = "range", unit = "px", key = "castbar.gap", label = "Gap below the health bar", desc = "Space between health and cast bar.", min = 0, max = 10, step = 1 },
	{ type = "toggle", key = "castbar.spellName", label = "Spell name", desc = "Spell name inside the cast bar." },
	{ type = "toggle", key = "castbar.targetName", label = "Spell target", desc = "Name of the spell's target under the cast bar." },
	{ type = "toggle", key = "castbar.inFront", label = "Casts in front", desc = "While a unit casts, its cast bar draws over the plates around it, so stacked casters stay readable." },
	{ type = "header", label = "Interrupts" },
	{ type = "description", label = "These use only the game's own flags: whether the cast can be interrupted and whether it is a channel. EldoUI keeps no spell lists." },
	{ type = "color", key = "castbar.color", label = "Interruptible", desc = "Cast bar color when the cast can be interrupted." },
	{ type = "color", key = "castbar.uninterruptibleColor", label = "Can't be interrupted", desc = "Cast bar color when the game says the cast can't be interrupted." },
	{ type = "toggle", key = "castbar.shield", label = "Shield on uninterruptible casts", desc = "Blizzard's shield icon over the spell icon when the cast can't be interrupted." },
	{ type = "toggle", key = "castbar.channelColorOn", label = "Own color for channels", desc = "Channeled spells get the color below instead of the normal cast color." },
	{ type = "color", key = "castbar.channelColor", dependsOn = "castbar.channelColorOn", label = "Channel color", cog = true, desc = "Cast bar color while the unit channels." },
	{ type = "description", label = "The important cast glow, the interrupter's name and the important cast sound are on the Effects tab." },
	{ type = "toggle", key = "castbar.showInterrupted", label = "Show \"Interrupted\"", desc = "A short strip when a cast is interrupted." },
	{ type = "color", key = "castbar.interruptedColor", label = "Interrupted color", desc = "Color of the interrupted strip.", hidden = function() return not M.db.castbar.showInterrupted end },

	{ type = "tab", label = "Effects" },
	{ type = "description", label = "Motion and warnings on the plates, shared with the unit frames. Every animation follows General > Animations." },
})
Append(E:UnitFXOptions("effects", { consumer = FX_CONSUMER, db = DB,
	hidden = { anotherTank = function() return not IsTankMode() end } }))
Append({
	{ type = "range", key = "outOfCombatAlpha", label = "Fade units out of combat", unit = "%", min = 0, max = 100, step = 5,
		desc = "Enemies that are not fighting fade to this opacity. 0 turns it off. Uses the game's combat flag only." },

	{ type = "tab", label = "Auras" },
})
Append(E:AuraFilterOptions("debuffs.filter", { kind = "HARMFUL", db = DB, label = "Debuffs",
	presets = { "mine", "important", "cc", "dispellable", "all" } }))
Append({
	{ type = "toggle", key = "debuffs.blizzardFilter", label = "Only Blizzard's nameplate debuffs", cog = true,
		desc = "Of those, show only the debuffs the game itself marks for nameplates." },
	{ type = "range", unit = "px", key = "debuffs.spacing", label = "Spacing", desc = "Gap between debuff icons.", min = 0, max = 8, step = 1, cog = true },
	{ type = "toggle", key = "debuffs.timer", label = "Countdown numbers", desc = "Seconds left on each debuff." },
	{ type = "range", unit = "px", key = "auraCountSize", label = "Stack number size", min = 0, max = 24, step = 1, zeroText = "Auto",
		desc = "Size of the stack number on debuff, buff and crowd control icons. Auto grows it with the icon." },
	{ type = "range", unit = "px", key = "auraTimerSize", label = "Countdown size", min = 0, max = 24, step = 1, zeroText = "Auto",
		desc = "Size of the countdown numbers on plate auras. Auto grows them with the icon." },
	{ type = "header", label = "Enemy buffs" },
	{ type = "select", key = "buffs.mode", label = "Show", desc = "Which buffs on enemies to show, picked by Blizzard's own filters. Defensives: big defensive cooldowns. Size and number are set per type.",
		values = { OFF = "Off", DISPELLABLE = "Purge, steal, enrage", IMPORTANT = "Important (Blizzard)", DEFENSIVES = "Defensives (Blizzard)", ALL = "All" } },
	{ type = "select", key = "buffs.position", label = "Position", desc = "Right of the bar, or a row above your debuffs.", values = { RIGHT = "Right of the bar", ABOVE = "Above the debuffs" } },
	{ type = "range", unit = "px", key = "buffs.spacing", label = "Spacing", desc = "Gap between buff icons.", min = 0, max = 8, step = 1, cog = true },
	{ type = "toggle", key = "buffs.timer", label = "Countdown numbers", desc = "Seconds left on each buff." },
	{ type = "toggle", key = "buffs.highlight", label = "Color the border", desc = "Border color for stealable buffs, enrage and magic." },
	{ type = "color", key = "buffs.stealableColor", label = "Stealable", desc = "Border of buffs a mage can steal.", hidden = function() return not M.db.buffs.highlight end },
	{ type = "color", key = "buffs.enrageColor", label = "Enrage", desc = "Border of enrage effects.", hidden = function() return not M.db.buffs.highlight end },
	{ type = "header", label = "Crowd control" },
	{ type = "toggle", key = "cc.enabled", label = "Crowd control icon", desc = "The unit's crowd control effect (stun, fear, sheep ...) left of the plate, picked by Blizzard's filter." },
	{ type = "range", unit = "px", key = "cc.size", dependsOn = "cc.enabled", label = "Icon size", desc = "Size of the crowd control icon.", min = 12, max = 48, step = 1 },

	{ type = "tab", label = "Indicators" },
	{ type = "header", label = "Extra icons" },
	{ type = "description", label = "Each plate type turns these on or off on its own tab. On Blizzard plates they need Blizzard UI > Nameplates: Improve." },
	{ type = "toggle", key = "icons.classification", label = "Elite and rare icon", desc = "Gold dragon for elites and bosses, silver for rare elites, a star for rares." },
	{ type = "range", unit = "px", key = "icons.classificationSize", dependsOn = "icons.classification", label = "Elite icon size", desc = "Size of the elite and rare icon.", min = 8, max = 32, step = 1, cog = true },
	{ type = "toggle", key = "icons.quest", label = "Quest mob icon", desc = "A quest icon on mobs the game marks for one of your active quests." },
	{ type = "toggle", key = "icons.questProgress", dependsOn = "icons.quest", label = "Quest progress", desc = "Show the first unfinished objective count (for example 3/8) next to the quest icon, as the unit tooltip reports it." },
	{ type = "range", unit = "px", key = "icons.questSize", dependsOn = "icons.quest", label = "Quest icon size", desc = "Size of the quest icon.", min = 8, max = 32, step = 1, cog = true },
	{ type = "toggle", key = "icons.totem", label = "Totem icon", desc = "The totem's picture on totem plates." },
	{ type = "range", unit = "px", key = "icons.totemSize", dependsOn = "icons.totem", label = "Totem icon size", desc = "Size of the totem icon.", min = 12, max = 48, step = 1, cog = true },
	{ type = "toggle", key = "icons.totemOnly", dependsOn = "icons.totem", label = "Totems: icon only", desc = "Totem plates show only the icon, no bar or name." },
	{ type = "range", key = "icons.pvpSize", label = "PvP badge size", desc = "Size of the PvP badge on player plates.", min = 10, max = 32, step = 1, cog = true },
	{ type = "toggle", key = "icons.pet", label = "Pet indicator", desc = "A small paw by pets and guardians." },
})
Append(FilterOptions())
Append({
	{ type = "tab", label = "Game settings" },
	{ type = "description", label = "Blizzard's nameplate settings. \"Game setting\" leaves yours alone; other values are put back when nameplates return to Blizzard default." },
	{ type = "header", label = "Which plates show" },
	{ type = "description", hidden = HasSwitch("hide"), label = function() return E:BlizzardNeedsReason("nameplates", "hide") or "" end, tone = "warning" },
	{ type = "toggle", key = "cvars.enemiesInCombatOnly", label = "Enemy plates only in combat",
		desc = "Hide enemy plates out of combat and show them when combat starts. While this is on it decides \"Enemy plates\" below, which is grayed out." },
})
-- "Enemy plates only in combat" takes over the Enemy plates setting.
local function CombatOnlyReason()
	return M.db and M.db.cvars.enemiesInCombatOnly and L["Controlled by \"Enemy plates only in combat\""] or false
end
for _, entry in ipairs(M.VISIBILITY_CVARS) do
	table.insert(M.options, { type = "select", key = "cvars." .. entry.key, label = entry.label, desc = entry.desc, values = SHOW_VALUES,
		disabled = entry.key == "showEnemies" and CombatOnlyReason or nil })
end
Append({
	{ type = "header", label = "Stacking", hidden = function() return not M.HasStacking() end },
	{ type = "description", hidden = function() return not M.HasStacking() or Allowed("move") end,
		label = function() return E:BlizzardNeedsReason("nameplates", "move") or "" end, tone = "warning" },
	{ type = "select", key = "cvars.stacking", label = "Enemy plates", desc = "Stacking keeps enemy plates from overlapping; overlapping keeps them over the unit.",
		values = STACK_VALUES, hidden = function() return not M.HasStacking() end },
	{ type = "select", key = "cvars.friendlyStacking", label = "Friendly plates", desc = "Stacking or overlapping for friendly plates.",
		values = STACK_VALUES, hidden = function() return not M.HasStacking() end },
})
-- Modules/Nameplates/Size.lua adds Size and click area, Situations and
-- the protected settings note to this tab.
end

do
---------------------------------------------------------------------------
-- Style presets. Each one sets the whole look (colors and every plate
-- type too), so switching between them never leaves a mix behind.
---------------------------------------------------------------------------
local BASE = {
	texture = "theme", font = "THEME", fontOutline = "THEME", fontSize = 11, nameColor = "WHITE",
	targetIndicator = "BORDER", targetAccent = true, targetScale = 115, nonTargetAlpha = 75,
	othersMode = "FADE", outOfCombatAlpha = 0, minorScale = 100, petScale = 85, raidMarkerSize = 18,
	colors = {
		byClassification = true, casters = true, byQuest = true, classHostile = true, classFriendly = true, playerBorder = true,
		reactionSource = "general", hostile = { 0.80, 0.14, 0.14 }, neutral = { 0.81, 0.72, 0.19 }, friendly = { 0.17, 0.75, 0.29 },
	},
	threat = { enabled = false, mode = "AUTO", custom = false, good = { 0.20, 0.80, 0.20 }, transition = { 1.00, 0.60, 0.00 }, bad = { 1.00, 0.10, 0.10 } },
	castbar = { gap = 2, spellName = true, color = { 1.00, 0.80, 0.00 }, uninterruptibleColor = { 0.45, 0.45, 0.45 } },
	debuffs = { blizzardFilter = false, spacing = 2 },
	buffs = { mode = "DISPELLABLE" },
	cc = { size = 24 },
	icons = { classification = true, quest = true, totem = true, classificationSize = 14, questSize = 14 },
}

local function Merge(target, source)
	for key, value in pairs(source) do
		if type(value) == "table" and #value == 0 and type(target[key]) == "table" then
			Merge(target[key], value)
		else
			target[key] = type(value) == "table" and CopyTable(value) or value
		end
	end
	return target
end

-- Each style names an effects preset (plan 4). The block leaves out the
-- opt-in effects (execute shade, important cast sound): a style never
-- turns them on or off.
local function Effects(preset, changes)
	local block = E:UnitFXDefaults(FX_CONSUMER, preset)
	for key in pairs(block) do
		local effect = E:UnitFXEffect(key)
		if effect and effect.optIn then block[key] = nil end
	end
	for key, fields in pairs(changes or {}) do
		block[key] = block[key] or {}
		for field, value in pairs(fields) do block[key][field] = value end
	end
	-- A changed row means the block matches no preset any more.
	if changes then block.preset = "custom" end
	return block
end

-- look: the base keys to change; plate: the per-type values every type
-- gets (friendly: extra values for the two friendly types).
local function Look(width, height, look, plate, friendly)
	local settings = Merge(CopyTable(BASE), look or {})
	settings.types = {}
	for _, key in ipairs(TYPES) do
		local t = Merge(TypeDefaults(key), { width = width, height = height })
		Merge(t, plate or {})
		if Friendly(key) then Merge(t, friendly or {}) end
		settings.types[key] = t
	end
	return settings
end

-- Style keys that were renamed: old key = new key. A profile that saved an
-- old key gets the new one once, so the picked style stays the same.
M.RENAMED_STYLES = { Jundies = "TwilightSlim" }
function M.MigrateStyleKeys(profile)
	local modules = type(profile) == "table" and type(profile.modules) == "table" and profile.modules
	local saved = modules and type(modules.Nameplates) == "table" and modules.Nameplates
	if not saved then return end
	local new = type(saved.style) == "string" and M.RENAMED_STYLES[saved.style]
	if new then saved.style = new end
end
E:RegisterProfileMigration(M.MigrateStyleKeys, "Nameplates:styleKeys", 1)

-- Beacon's colors are the color-blind safe set (E.tokens.palette.safe);
-- applying a style copies them into the settings.
local SAFE = E.tokens.palette.safe
E:RegisterStyles("Nameplates", {
	{ key = "EldoUI", title = "EldoUI", desc = "140 x 12 bars, name left, percent, accent border on the target, other plates faded. Effects: Subtle.",
		settings = Look(140, 12, { effects = Effects("subtle") }) },
	{ key = "TwilightSlim", title = "Twilight slim", desc = "Slim dark bars colored by mob type, name centered above, a pulsing glow on the target, other plates dimmed. Effects: Standard.",
		settings = Look(130, 8, {
			texture = "Flat", fontSize = 10, targetIndicator = "PULSE", targetScale = 110, nonTargetAlpha = 60, othersMode = "DIM",
			effects = Effects("standard"),
			-- Side icons in proportion to the slim bar.
			raidMarkerSize = 14, cc = { size = 18 }, icons = { classificationSize = 12, questSize = 12 },
		}, {
			nameText = "CENTER", healthTag = { preset = "off" },
			castbar = { height = 8, time = "NONE", nameSize = 9, timeSize = 9 },
			debuffs = { size = 18, max = 5 },
		}) },
	{ key = "Slim", title = "Whisper", desc = "Thin 100 x 5 lines with small text and few icons, smaller minor units and pets. Good in big pulls. Effects: Off.",
		settings = Look(100, 5, {
			texture = "Flat", fontSize = 9, targetScale = 110, nonTargetAlpha = 80, castbar = { gap = 1 }, debuffs = { spacing = 1 },
			minorScale = 80, petScale = 70, effects = Effects("off"),
			raidMarkerSize = 12, cc = { size = 14 }, icons = { classificationSize = 10, questSize = 10 },
		}, {
			healthTag = { preset = "off" },
			castbar = { height = 6, icon = "NONE", time = "NONE", nameSize = 8, timeSize = 8 },
			debuffs = { size = 16, max = 3 }, buffs = { size = 14, max = 2 },
		}) },
	{ key = "Big", title = "Beacon", desc = "186 x 16 bars, big thick-outlined text and color-blind safe colors (Okabe-Ito), also for the threat border. Effects: Standard.",
		settings = Look(186, 16, {
			fontSize = 13, fontOutline = "THICKOUTLINE", targetIndicator = "BOTH", targetScale = 120, nonTargetAlpha = 70,
			threat = { custom = true, good = SAFE.green, transition = SAFE.orange, bad = SAFE.vermilion },
			effects = Effects("standard"),
			colors = { hostile = SAFE.orange, friendly = SAFE.blue, neutral = SAFE.yellow },
			castbar = { gap = 3, color = SAFE.yellow, uninterruptibleColor = SAFE.gray },
			debuffs = { spacing = 3 },
		}, {
			healthTag = { preset = "healthcurrentpercent" }, levelTag = { preset = "platelevel" },
			castbar = { height = 16, nameSize = 12, timeSize = 12 },
			debuffs = { size = 26, max = 6 }, buffs = { size = 22 },
		}) },
	{ key = "Blizzard", title = "Old road", desc = "Classic look: reaction colors only, name centered, level shown, white border on the target, no fading. Effects: Off.",
		settings = Look(140, 10, {
			texture = "Gloss", targetAccent = false, targetColor = { 1, 1, 1 }, targetScale = 100, nonTargetAlpha = 100,
			othersMode = "OFF", effects = Effects("off"),
			colors = { byClassification = false, casters = false, byQuest = false },
			debuffs = { blizzardFilter = true },
			buffs = { mode = "OFF" },
		}, {
			nameText = "CENTER", healthTag = { preset = "off" }, levelTag = { preset = "platelevel" },
			castbar = { time = "NONE" }, debuffs = { size = 20 },
		}) },
	{ key = "Tank", title = "Bastion", desc = "Tank plates: 186 x 15 (200 x 16 in combat), threat colors by role, a border that pulses when you lose aggro, another tank's mobs in a calm color, stacking on.",
		settings = Look(186, 15, {
			targetScale = 120, nonTargetAlpha = 85, othersMode = "DIM",
			threat = { enabled = true, mode = "AUTO" },
			cvars = { stacking = "STACK" },
			effects = Effects("vivid", { threat = { enabled = true, style = "BORDER", pulse = true }, anotherTank = { enabled = true } }),
		}, {
			castbar = { height = 12 }, debuffs = { size = 20, max = 5 }, combatWidth = 200, combatHeight = 16,
		}) },
	{ key = "Headline", title = "Headline", desc = "Friendly units as names only (class and reaction colors) with NPC titles, enemies as slim EldoUI plates that fade while not fighting. Effects: Subtle.",
		settings = Look(132, 10, {
			texture = "Flat", nameColor = "REACTION", targetIndicator = "GLOW", nonTargetAlpha = 70, outOfCombatAlpha = 70,
			effects = Effects("subtle", { questPop = { enabled = true } }),
		}, nil, { nameOnly = true, title = true }) },
})

-- "Your layout suggests the <style> style." on the General tab, one line
-- per style, shown for the style the current layout names.
do
	local at
	for index, row in ipairs(M.options) do
		if row.label == "Use the suggested style" then at = index break end
	end
	for offset, style in ipairs(E.styles.Nameplates or {}) do
		local key = style.key
		table.insert(M.options, at + offset - 1, { type = "description",
			label = "Your layout suggests the %s nameplate style.", labelFill = style.title,
			hidden = function() return SuggestedStyle() ~= key end })
	end
end
end
