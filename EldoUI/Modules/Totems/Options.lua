-- EldoUI Shaman Totems: options and style presets.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local M = E:GetModule("ShamanTotems")
local D = E.ShamanData

local function NotShaman() return not M:IsShaman() end
local function CooldownsOff() return not M.db.cooldowns.enabled end
local function NotReady() return CooldownsOff() or not M.db.cooldowns.ready end

-- A totem select for one element: the totems you know.
local function TotemValues(element)
	return function()
		local values = { [""] = "First one you know" }
		for _, item in ipairs(M:KnownTotems(element)) do values[item.key] = item.name or item.key end
		return values
	end
end

local function SpellValues(list, empty)
	return function()
		local values = { [""] = empty }
		for _, item in ipairs(list) do
			if M:Known(item.id) then values[item.key] = M.SpellName(item.id) or item.key end
		end
		return values
	end
end

local function LoadoutValues()
	local values = { [0] = "None" }
	for _, set in ipairs(M:Loadouts()) do values[set.index] = set.name end
	return values
end

local function ShamanValues()
	local values = { [""] = "Nobody" }
	for _, name in ipairs(M:GroupShamans()) do values[name] = name end
	local plan = M.db.plan
	for _, job in ipairs(M.JOBS) do
		local name = plan[job.key]
		if type(name) == "string" and name ~= "" then values[name] = values[name] or name end
	end
	return values
end

-- The set the cooldown bar's ticks follow now, after the section title.
local SET_TITLES = { healer = "Healer set", melee = "Melee set", caster = "Caster set" }
-- L["Healer set"], L["Melee set"], L["Caster set"]
local function RoleSetStatus()
	if not M:IsShaman() then return "" end
	if M.Cooldowns:OwnTicks() then return L["Your own picks"] end
	return L[SET_TITLES[M:CooldownRole()] or "Melee set"]
end

-- Row labels of the cooldown and ready spells: each row shows the spell as
-- the game names it, and these English names stand in until the game has it.
local SPELL_LABELS = {
	recall = "Totemic Recall", reincarnation = "Reincarnation", swiftness = "Nature's Swiftness",
	manatide = "Mana Tide Totem", mastery = "Lightning Mastery", rage = "Rage of the Farseer",
	earthshock = "Earth Shock", stormstrike = "Stormstrike", riptide = "Riptide",
	firenova = "Fire Nova",
}

local options = {
	{ type = "description", label = "A totem bar for shamans: one button per element drops your pick, pointing at it lists its totems, and Drop All drops the whole set." },
	{ type = "description", tone = "warning", hidden = function() return M:IsShaman() end,
		label = "This character is not a shaman, so the bars stay hidden. The \"Totem buffs on you\" example in Aura Groups works for every class." },

	{ type = "tab", label = "Totem bar" },
	{ type = "header", label = "Your totems" },
	{ type = "select", key = "picks.EARTH", label = "Earth", values = TotemValues("EARTH"), hidden = NotShaman,
		desc = "The earth totem the earth button drops. Right-click a totem in the button's picker does the same." },
	{ type = "select", key = "picks.FIRE", label = "Fire", values = TotemValues("FIRE"), hidden = NotShaman,
		desc = "The fire totem the fire button drops." },
	{ type = "select", key = "picks.WATER", label = "Water", values = TotemValues("WATER"), hidden = NotShaman,
		desc = "The water totem the water button drops." },
	{ type = "select", key = "picks.AIR", label = "Air", values = TotemValues("AIR"), hidden = NotShaman,
		desc = "The air totem the air button drops." },
	{ type = "header", label = "Buttons" },
	{ type = "select", key = "dropAll", label = "Drop All uses", values = {
		call = "Call of the Elements",
		sequence = "One totem per press",
	}, desc = "Call of the Elements drops all four picks at once, once you know it. One totem per press drops them in order, starting over after 15 seconds or when combat ends." },
	{ type = "select", key = "flyout", label = "Pickers open", values = { UP = "Up", DOWN = "Down", LEFT = "Left", RIGHT = "Right" },
		order = { "UP", "DOWN", "LEFT", "RIGHT" },
		desc = "The side each element's picker opens toward when you point at its button." },
	{ type = "toggle", key = "showKeys", label = "Key bindings", desc = "Show each button's key (Key Bindings > AddOns > EldoUI Shaman Totems)." },
	{ type = "toggle", key = "tremorHint", label = "Tremor hint while feared", desc = "Light the earth button while you are feared and know Tremor Totem. The game tells EldoUI you lost control; nothing else is read." },
	{ type = "header", label = "Timers" },
	{ type = "toggle", key = "timerText", label = "Time left as numbers", desc = "The game's countdown numbers on each running totem." },
	{ type = "toggle", key = "timerBars", label = "Timer bars", desc = "A thin bar under each button that empties as its totem runs out." },
	{ type = "toggle", key = "emptyFade", label = "Fade empty elements", desc = "Dim an element with no totem down. Nothing fades while the game hides which totem is down." },
	{ type = "toggle", key = "elementColors", label = "Element colors", desc = "A thin edge in the element's color under each button: green earth, orange fire, blue water, light blue air." },
	{ type = "header", label = "Look" },
	{ type = "range", unit = "px", key = "size", label = "Button size", min = 20, max = 48, step = 1, desc = "Size of each totem button." },
	{ type = "range", unit = "px", key = "spacing", label = "Spacing", min = 0, max = 12, step = 1, desc = "Space between the buttons." },
	{ type = "toggle", key = "vertical", label = "Vertical", desc = "Stack the buttons top to bottom (both bars)." },
	{ type = "header", label = "Blizzard" },
	{ type = "toggle", key = "hideBlizzard", label = "Hide Blizzard's totem bar", desc = "Hide the game's own totem bar and totem timers while this bar is on, so there is one totem bar." },
	{ type = "toggle", key = "keepTimers", label = "Keep Blizzard's totem timers", dependsOn = "hideBlizzard",
		desc = "Keep the game's totem timers next to the player frame anyway." },

	{ type = "tab", label = "Cooldowns" },
	{ type = "toggle", key = "cooldowns.enabled", label = "Cooldown bar", desc = "A second bar with your shield, weapon imbues and shaman cooldowns. Click an icon to cast it." },
	{ type = "header", label = "Shield and imbues" },
	{ type = "toggle", key = "cooldowns.shield", label = "Shield", dependsOn = "cooldowns.enabled",
		desc = "Your shield with its time and charges, drawn by the game; faded while it is not on you." },
	{ type = "select", key = "cooldowns.shieldPick", label = "Which shield", dependsOn = "cooldowns.shield", hidden = NotShaman,
		values = SpellValues(D.SHIELDS, "First one you know"), desc = "The shield the icon casts." },
	{ type = "toggle", key = "cooldowns.imbueMain", label = "Main-hand imbue", dependsOn = "cooldowns.enabled",
		desc = "Your main-hand weapon imbue with the time it has left." },
	{ type = "select", key = "cooldowns.imbuePick", label = "Main-hand imbue spell", dependsOn = "cooldowns.imbueMain", hidden = NotShaman,
		values = SpellValues(D.IMBUES, "First one you know"), desc = "The imbue the main-hand icon casts." },
	{ type = "toggle", key = "cooldowns.imbueOff", label = "Off-hand imbue", dependsOn = "cooldowns.enabled",
		desc = "The off-hand imbue, while your off hand holds a weapon." },
	{ type = "select", key = "cooldowns.imbueOffPick", label = "Off-hand imbue spell", dependsOn = "cooldowns.imbueOff", hidden = NotShaman,
		values = SpellValues(D.IMBUES, "Same as the main hand"), desc = "The imbue the off-hand icon casts (it then goes on the off-hand weapon)." },
	{ type = "toggle", key = "cooldowns.missingGlow", label = "Glow when missing", dependsOn = "cooldowns.enabled",
		desc = "A glow on the shield or an imbue while it is missing. The shield's glow shows out of combat only: the game hides your auras from addons in combat (the faded icon still shows)." },
	{ type = "header", label = "Cooldowns", status = RoleSetStatus },
	{ type = "description", label = "The bar starts with your role's spells, plus Totemic Recall, Reincarnation and Earth Shock. Your own ticks stay; unknown spells never show." },
	{ type = "select", key = "cooldowns.roleSet", label = "Spell set", dependsOn = "cooldowns.enabled",
		values = { auto = "Automatic", healer = "Healer", melee = "Melee", caster = "Caster" }, order = { "auto", "healer", "melee", "caster" },
		desc = "Which role's spells the bar starts with. Automatic follows the Role page, else your talents. Picking a set replaces your own ticks below." },
	{ type = "execute", label = "Use the role set again", dependsOn = "cooldowns.enabled", noUndo = true,
		disabled = function() return not M.Cooldowns:OwnTicks() and L["The ticks already follow the role set."] or false end,
		desc = "Your own ticks below give way to the spells of the role set.",
		func = function() M.Cooldowns:ResetRoleSet() end },
}
for _, spell in ipairs(D.SPELLS) do
	options[#options + 1] = { type = "toggle", key = "cooldowns.spells." .. spell.key, label = SPELL_LABELS[spell.key],
		gameName = function() return M.SpellName(spell.id) end, dependsOn = "cooldowns.enabled",
		desc = spell.passive and E.Key("Its cooldown and how many Ankhs you carry.") or E.Key("Its cooldown; click to cast it.") }
end
for _, row in ipairs({
	{ type = "header", label = "Ready icons" },
	{ type = "toggle", key = "cooldowns.ready", label = "Show ready icons", dependsOn = "cooldowns.enabled",
		desc = "Icons for key spells, lit while they are off cooldown and dim while it runs. Off by default." },
}) do options[#options + 1] = row end
for _, spell in ipairs(D.READY) do
	options[#options + 1] = { type = "toggle", key = "cooldowns.readySpells." .. spell.key, label = SPELL_LABELS[spell.key],
		gameName = function() return M.SpellName(spell.id) end, hidden = NotReady, desc = "A ready icon for this spell, once you know it." }
end
for _, row in ipairs({
	{ type = "header", label = "Look" },
	{ type = "range", unit = "px", key = "cooldowns.size", label = "Icon size", min = 18, max = 48, step = 1, dependsOn = "cooldowns.enabled", desc = "Width and height of each totem cooldown icon." },
	{ type = "range", unit = "px", key = "cooldowns.spacing", label = "Spacing", min = 0, max = 12, step = 1, dependsOn = "cooldowns.enabled", desc = "Space between the icons." },

	{ type = "tab", label = "Loadouts" },
	{ type = "description", label = "A loadout is a saved set of four totems. Right-click Drop All to switch, save, rename, share or delete. A switch waits for out of combat." },
	{ type = "execute", label = "Save your picks as a loadout", hidden = NotShaman, noUndo = true,
		desc = "Saves the four totems you picked now as a new loadout (up to 8).",
		func = function()
			if not M:SaveLoadout(nil) then E:Print(L["Every loadout slot is full. Delete one first."]) end
		end },
	{ type = "execute", label = "Import a loadout", noUndo = true, desc = "Paste a totem loadout string someone shared.",
		func = function() E:ShowImport() end },
	{ type = "header", label = "By content" },
	{ type = "toggle", key = "contentRule", acts = true, label = "Switch loadout by content",
		desc = "When you enter the world, a dungeon, a raid or a battleground, the bar switches to the loadout picked below (out of combat). This acts for you. Off by default." },
	{ type = "select", key = "contentLoadouts.world", label = "Open world", values = LoadoutValues, dependsOn = "contentRule", desc = "The loadout outside instances." },
	{ type = "select", key = "contentLoadouts.party", label = "Dungeons", values = LoadoutValues, dependsOn = "contentRule", desc = "The loadout in dungeons." },
	{ type = "select", key = "contentLoadouts.raid", label = "Raids", values = LoadoutValues, dependsOn = "contentRule", desc = "The loadout in raids." },
	{ type = "select", key = "contentLoadouts.pvp", label = "Battlegrounds and arenas", values = LoadoutValues, dependsOn = "contentRule", desc = "The loadout in battlegrounds and arenas." },

	{ type = "tab", label = "Group" },
	{ type = "header", label = "Who your totems reach" },
	{ type = "toggle", key = "squares", label = "Squares on party frames", desc = "A small square on party frames per running buff totem: filled when the member has it, hollow when not, ? in combat (the game hides it then)." },
	{ type = "range", key = "squareSize", label = "Square size", unit = "px", min = 4, max = 12, step = 1, dependsOn = "squares", desc = "Width and height of each square on the party frames." },
	{ type = "toggle", key = "coverageTip", label = "On the totem tooltips", desc = "In a group, a totem button's tooltip names the members its buff doesn't reach (out of combat)." },
	{ type = "toggle", key = "counterHint", label = "Counter totems on mob tooltips", desc = "On a mob's tooltip, Tremor, Poison Cleansing or Disease Cleansing Totem when the Mob Abilities log saw it cast fear, poison or disease. The loadout menu offers the swap. Out of combat." },
	{ type = "header", label = "Group plan" },
	{ type = "toggle", key = "plan.enabled", label = "Use a group plan", desc = "Plan who drops Mana Tide Totem and each resistance totem, and send it to your group. Shamans with EldoUI see their part on the Drop All tooltip." },
}) do options[#options + 1] = row end
for _, job in ipairs(M.JOBS) do
	options[#options + 1] = { type = "select", key = "plan." .. job.key, label = job.title, values = ShamanValues, dependsOn = "plan.enabled",
		desc = "The shaman in your group who drops it." }
end
for _, row in ipairs({
	{ type = "execute", label = "Send the plan to the group", dependsOn = "plan.enabled", noUndo = true,
		desc = "One addon message to your group, out of combat. Nothing is sent on its own.",
		func = function() M:SendPlan() end },
	{ type = "toggle", key = "plan.share", label = "Shaman columns in the Ready Check Report",
		desc = "The totems each shaman carries, their Ankh count, shield, weapon imbues and mana in the Ready Check Report. Yours is read out of combat; Share mine sends yours along." },
	{ type = "header", label = "Shaman group panel" },
	{ type = "description", label = "Every shaman of your group in one window: Mana Tide, Reincarnation, Ankhs and their part of the plan, once they click Share mine." },
	{ type = "execute", label = "Open the shaman group panel", noUndo = true, testSafe = true,
		desc = "Opens the panel (out of combat). Right-click Drop All opens it too.",
		func = function() M:OpenGroupWindow() end },
}) do options[#options + 1] = row end

for _, row in ipairs(E:VisibilityOptions("visibility", { db = function() return M.db end, secure = true })) do
	options[#options + 1] = row
end
M.options = options

-- Switching loadouts acts for the player: listed for shamans on the setup's
-- Convenience step and the Conveniences page (Core/Conveniences.lua), off
-- until ticked and never recommended (it needs loadouts picked first).
E:RegisterConvenience({ id = "totemContentRule", module = "ShamanTotems", setting = "contentRule", order = 180,
	label = "Switch totem loadout by content",
	desc = "Acts for you: when you enter the world, a dungeon, a raid or a battleground, the totem bar switches to the loadout you picked for it, out of combat.",
	available = E.ConvenienceRules.Class("SHAMAN") })

E:RegisterStyles("ShamanTotems", {
	{ key = "Standard", title = "Standard", desc = "28 px buttons in a row with timers as numbers, the cooldown bar and element edges.",
		settings = { size = 28, spacing = 4, vertical = false, timerText = true, timerBars = false, elementColors = true, emptyFade = true,
			cooldowns = { enabled = true, size = 28, spacing = 4 },
			visibility = { preset = "always", show = "always", fadedAlpha = 0, fadeTime = 0.2, delay = 0 } } },
	{ key = "Compact", title = "Compact", desc = "Small 22 px buttons close together, small cooldown icons.",
		settings = { size = 22, spacing = 2, vertical = false, timerText = true, timerBars = false,
			cooldowns = { enabled = true, size = 22, spacing = 2 } } },
	{ key = "Large", title = "Large", desc = "Big 36 px buttons, easy to read and click.",
		settings = { size = 36, spacing = 5, vertical = false, timerText = true,
			cooldowns = { enabled = true, size = 32, spacing = 4 } } },
	{ key = "TimerBars", title = "Timer bars", desc = "A thin timer bar under each button instead of countdown numbers.",
		settings = { timerText = false, timerBars = true, elementColors = false } },
	{ key = "IconsOnly", title = "Icons only", desc = "Just the totem bar: no cooldown bar, no key labels, no edges.",
		settings = { showKeys = false, elementColors = false, cooldowns = { enabled = false } } },
	{ key = "Vertical", title = "Vertical", desc = "Both bars as columns at the side of the screen, pickers opening sideways.",
		settings = { vertical = true, flyout = "RIGHT" } },
	{ key = "CombatOnly", title = "Combat only", desc = "Both bars show only in combat (and in move mode).",
		settings = { visibility = { preset = "combat", show = "combat", fadedAlpha = 0, fadeTime = 0.2, delay = 0 } } },
}, { restores = { "cooldowns.enabled", "showKeys" } })

-- For every class: the Aura Groups example that shows the totem buffs on you.
local auraGroups = E.modules and E.modules.AuraGroups
if auraGroups and auraGroups.AddExample then
	local ids = {}
	for _, list in pairs(D.TOTEMS) do
		for _, entry in ipairs(list) do
			if entry.buff then ids[#ids + 1] = entry.buff end
		end
	end
	table.sort(ids)
	local spells = {}
	for _, id in ipairs(ids) do spells[#spells + 1] = tostring(id) end
	auraGroups:AddExample("totemBuffs", {
		title = "Totem buffs on you",
		desc = "The totem buffs a shaman's totems give you. The group dims a step for each shaman in your party who is out of range, and fully when all of them are.",
		name = "Totem buffs",
		unit = "player", kind = "HELPFUL", mine = false,
		spells = table.concat(spells, ", "),
		-- The range dim follows every layout of a group this example fills.
		onLayout = function(_, index) M.TotemBuffRange.UpdateGroup(index) end,
	})
end
