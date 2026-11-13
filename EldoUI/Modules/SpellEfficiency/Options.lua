-- EldoUI Spell Efficiency: options page and style presets.
local _, E = ...
local L = E.L
local M = E.SpellEfficiency

local function Off() return E:GetTooltipSectionMode("spellEfficiency") == "never" end

M.options = {
	{ type = "description", label = "Adds damage or healing per second and per mana under a spell's tooltip, read from the tooltip's own text. English and German clients." },
	{ type = "header", label = "When it shows" },
	{ type = "execute", label = "Tooltip line settings", func = function() E:ToggleConfig("module:Tooltip") end,
		desc = "Choose when spell tooltips get the efficiency line: Always, with Shift, Ctrl or Alt, or Never (Tooltip page, Spell efficiency)." },
	{ type = "header", label = "Values" },
	{ type = "toggle", key = "perSecond", label = "Per second", desc = "DPS or HPS: damage or healing per second of cast time (at least the global cooldown); a spell that only works over time uses its duration.", hidden = Off },
	{ type = "toggle", key = "perMana", label = "Per mana", desc = "DPM or HPM: damage or healing for each point of mana.", hidden = Off },
	{ type = "toggle", key = "manaShare", label = "Share of your mana", desc = "The mana cost as a percent of your maximum mana.", hidden = Off },
	{ type = "range", key = "decimals", label = "Decimals", min = 0, max = 2, step = 1, desc = "Digits after the decimal point.", hidden = Off },
	{ type = "toggle", key = "oneLine", label = "One line", desc = "All values in one line; off gives each value its own row.", hidden = Off },
	{ type = "toggle", key = "inputs", label = "Inputs with Shift", desc = "Hold Shift to see what the values come from: the average, the part over time, the time used and the mana cost.", hidden = Off },
	{ type = "toggle", key = "compareRanks", label = "Compare with your rank", desc = "On a rank you don't use (in the Training window, at a trainer or in a link), also show the values of the rank you know.", hidden = Off },
	{ less = true, type = "toggle", key = "accentValues", label = "Values in the accent color", desc = "Write the numbers in your accent color.", hidden = Off },
}

-- The line is part of the game's tooltip, so it needs Blizzard UI >
-- Tooltips: Improve; the rows say so while that is off.
do
	local needs = E:BlizzardNeeds("tooltips", "improve")
	for _, row in ipairs(M.options) do
		if row.key and not row.disabled then row.disabled = needs end
	end
end

E:RegisterStyles("SpellEfficiency", {
	{ key = "OneLine", title = L["One line"], desc = L["DPS, DPM and mana share in one line, one decimal, inputs with Shift."],
		settings = { perSecond = true, perMana = true, manaShare = true, decimals = 1, oneLine = true, inputs = true, compareRanks = true, accentValues = false } },
	{ key = "Detailed", title = L["Detailed"], desc = L["Each value on its own row with two decimals, inputs with Shift and your rank."],
		settings = { perSecond = true, perMana = true, manaShare = true, decimals = 2, oneLine = false, inputs = true, compareRanks = true, accentValues = false } },
	{ key = "NumbersOnly", title = L["Numbers only"], desc = L["One short line of whole numbers, no inputs and no rank compare."],
		settings = { perSecond = true, perMana = true, manaShare = false, decimals = 0, oneLine = true, inputs = false, compareRanks = false, accentValues = false } },
	{ key = "ManaFocus", title = L["Mana focus"], desc = L["Per mana and the share of your mana only, for long fights where mana runs out first."],
		settings = { perSecond = false, perMana = true, manaShare = true, decimals = 1, oneLine = true, inputs = true, compareRanks = true, accentValues = false } },
	{ key = "ForeverBronze", title = L["Forever bronze"], desc = L["One line with the numbers in your accent color (warm sand under the WoW Forever art style)."],
		settings = { perSecond = true, perMana = true, manaShare = true, decimals = 1, oneLine = true, inputs = true, compareRanks = true, accentValues = true } },
})
