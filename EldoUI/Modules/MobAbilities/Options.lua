-- EldoUI Cast Tooltips and Mob Abilities: options page and style presets.
local _, E = ...
local L = E.L
local M = E.MobAbilities


M.options = {
	{ type = "description", label = "Hover a cast bar for the spell's tooltip; a mob's tooltip lists the abilities it cast in front of you and where reputation tokens go." },
	{ type = "header", label = "Cast bar tooltip" },
	{ type = "toggle", key = "castTooltip", label = "Spell tooltip on the target cast bar", desc = "Mouse over the target's cast bar on EldoUI's unit frames to see the tooltip of the spell it casts. Clicks still go to the unit frame." },
	{ type = "toggle", key = "castFocus", label = "Also on the focus cast bar", desc = "The same tooltip on the focus frame's cast bar.", dependsOn = "castTooltip" },
	{ type = "select", key = "castAnchor", label = "Tooltip place", values = { bar = "Above the cast bar", cursor = "At the mouse" }, order = { "bar", "cursor" },
		desc = "Where the spell tooltip opens.", dependsOn = "castTooltip" },
	{ type = "header", label = "Ability log" },
	{ type = "toggle", key = "log", label = "Remember mob abilities", desc = "Remember the spells hostile mobs cast while they are your target, your focus or show a nameplate. Kept for your account; skipped wherever the game hides the mob." },
	{ type = "toggle", key = "logNameplates", label = "Also from nameplates", desc = "Also remember casts of mobs that only show a nameplate.", dependsOn = "log" },
	{ type = "toggle", key = "tooltipRow", label = "Show on the mob's tooltip", desc = "An \"Abilities seen\" row on a hostile mob's tooltip, from what the log remembered. Hold Shift to see all of them." },
	{ type = "range", key = "maxNames", label = "Abilities before \"more\"", min = 1, max = 8, step = 1, desc = "How many abilities the row names before it shows (+N).", dependsOn = "tooltipRow" },
	{ type = "toggle", key = "showNames", label = "Spell names", desc = "Write the spell names in the row; off with icons on shows icons only.", dependsOn = "tooltipRow" },
	{ type = "toggle", key = "showIcons", label = "Spell icons", desc = "A small spell icon before each ability.", dependsOn = "tooltipRow" },
	{ type = "toggle", key = "showCounts", label = "Times seen", desc = "In the Shift list, how many times you saw each ability.", dependsOn = "tooltipRow" },
	{ type = "execute", label = "Forget the ability log", desc = "Clear every ability EldoUI remembered, for all mobs and all your characters.", confirm = true,
		func = function()
			M:Forget()
			if E.ConfigNotice then E:ConfigNotice(L["The ability log is empty again."]) end
		end },
	{ type = "header", label = "Reputation tokens" },
	{ type = "toggle", key = "tokenRow", label = "Turn-in info on tokens", desc = "On items a reputation quest asks for (Valor Tokens, Scourgestones, Insignia): who takes them and how much reputation they give. Needs the Loot Guide's data." },
	{ type = "toggle", key = "tokenStanding", label = "Your standing", desc = "Add your current standing with the faction.", dependsOn = "tokenRow" },
	{ type = "header", label = "Rows" },
	{ less = true, type = "toggle", key = "accentLabels", label = "Labels in the accent color", desc = "Write the row labels in your accent color instead of gray." },
}

-- Looks of the tooltip rows (never the log itself).
E:RegisterStyles("MobAbilities", {
	{ key = "Compact", title = L["Compact"], desc = L["Three ability names in one row, gray labels."],
		settings = { castTooltip = true, tooltipRow = true, tokenRow = true, maxNames = 3, showNames = true, showIcons = false, showCounts = false, accentLabels = false } },
	{ key = "Detailed", title = L["Detailed"], desc = L["Icons and names, five before more, times seen in the Shift list, your standing on tokens."],
		settings = { castTooltip = true, tooltipRow = true, tokenRow = true, tokenStanding = true, maxNames = 5, showNames = true, showIcons = true, showCounts = true, accentLabels = false } },
	{ key = "IconsOnly", title = L["Icons only"], desc = L["Only spell icons in the ability row, up to eight."],
		settings = { castTooltip = true, tooltipRow = true, tokenRow = true, maxNames = 8, showNames = false, showIcons = true, showCounts = false, accentLabels = false } },
	{ key = "ForeverBronze", title = L["Forever bronze"], desc = L["Names with icons and labels in the accent color (warm sand under the WoW Forever art style)."],
		settings = { castTooltip = true, tooltipRow = true, tokenRow = true, maxNames = 4, showNames = true, showIcons = true, showCounts = false, accentLabels = true } },
	{ key = "Off", title = L["Off"], desc = L["No rows and no cast bar tooltip; the log keeps remembering."],
		settings = { castTooltip = false, tooltipRow = false, tokenRow = false } },
})
