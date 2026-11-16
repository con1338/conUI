-- EldoUI Split Timer: options page and style presets.
local _, E = ...
local L = E.L
local M = E.SplitTimer

local function TimerOff() return not M.db.timer end
local function NotRecording()
	if M:Recording() then return nil end
	return L["Needs the Alts module: it records your levels and played time."]
end

local function CharacterValues()
	local values = {}
	local store = E.Characters
	for _, key in ipairs(M:OtherKeys()) do
		local record = store:Get(key)
		values[key] = ("%s (%d)"):format(record.name or key, record.level or 0)
	end
	if not next(values) then values[""] = L["No other character with splits yet"] end
	return values
end

M.options = {
	{ type = "description", label = "The timer turns green when you are ahead of your reference and red when behind. Times come from /played, recorded by the Alts module." },
	{ type = "description", label = function() return E:ModuleOffNote("Characters", L["The Split Timer records no levels without it."]) end, hidden = function() return M:Recording() end },
	{ type = "tab", label = "Timer" },
	{ type = "header", label = "Timer" },
	{ type = "toggle", key = "timer", label = "Show the timer", disabled = NotRecording,
		desc = "The small timer on screen. Move it with /eui move." },
	{ type = "select", key = "reference", label = "Compare with", values = { best = "Best of all", pb = "Personal best", char = "A character" },
		order = { "best", "pb", "char" }, disabled = NotRecording,
		desc = "Best of all: the best time per level over all your other characters. Personal best: the character that reached your next level in the least played time. A character: one you pick." },
	{ type = "select", key = "refChar", label = "Character", values = CharacterValues, hidden = function() return M.db.reference ~= "char" end,
		desc = "The character to race. Without one, Personal best is used." },
	{ type = "toggle", key = "showTotal", label = "Total played", hidden = TimerOff,
		desc = "Your total played time next to the difference." },
	{ type = "toggle", key = "hideAtMax", label = "Hide at the level cap", hidden = TimerOff,
		desc = "No timer once the character is at the highest level." },
	{ type = "header", label = "Level-up" },
	{ type = "toggle", key = "dingCard", label = "Level-up card", disabled = NotRecording,
		desc = "A card at each level-up: how long the level took and the difference to your reference." },
	{ type = "tab", label = "Look" },
	{ type = "header", label = "Timer look" },
	{ type = "toggle", key = "oneLine", label = "One line", desc = "Level, time and difference on one line, without the total.", hidden = TimerOff },
	{ type = "toggle", key = "showLabel", label = "Labels", desc = "Show \"Level 23\" and \"vs best\" next to the numbers.", hidden = TimerOff },
	{ type = "toggle", key = "panel", label = "Panel", desc = "A panel behind the timer; off shows the text alone.", hidden = TimerOff },
	{ less = true, type = "toggle", key = "accentTime", label = "Time in the accent color", desc = "Write the level time in your accent color.", hidden = TimerOff },
	{ type = "range", key = "fontSize", label = "Time size", min = 12, max = 28, step = 1, desc = "Font size of the level time.", hidden = TimerOff },
	{ type = "range", key = "smallSize", label = "Text size", min = 9, max = 16, step = 1, desc = "Font size of the other lines.", hidden = TimerOff },
	{ type = "range", unit = "px", key = "width", label = "Width", min = 100, max = 260, step = 10, desc = "Width of the timer.", hidden = TimerOff },
}

-- The shared visibility rows, at the end of the Timer tab.
do
	local at = #M.options + 1
	for index, row in ipairs(M.options) do
		if row.type == "header" and row.label == "Level-up" then at = index break end
	end
	for _, row in ipairs(E:VisibilityOptions("visibility", { db = function() return M.db end, hidden = TimerOff })) do
		table.insert(M.options, at, row)
		at = at + 1
	end
end

local function Look(base)
	local out = { oneLine = false, showLabel = true, panel = true, accentTime = false, fontSize = 16, smallSize = 11, width = 180, showTotal = true }
	for key, value in pairs(base) do out[key] = value end
	return out
end

E:RegisterStyles("SplitTimer", {
	{ key = "Speedrun", title = L["Speedrun"], desc = L["Big digits for the level time, the difference and your total under it."],
		settings = Look({ fontSize = 18, smallSize = 11, width = 190 }) },
	{ key = "Compact", title = L["Compact"], desc = L["Level, time and difference on one small line."],
		settings = Look({ oneLine = true, fontSize = 13, smallSize = 11, width = 170, showTotal = false }) },
	{ key = "TextOnly", title = L["Text only"], desc = L["The same lines without a panel."],
		settings = Look({ panel = false }) },
	{ key = "ForeverBronze", title = L["Forever bronze"], desc = L["The level time in your accent color (warm sand under the WoW Forever art style)."],
		settings = Look({ accentTime = true }) },
	{ key = "Minimal", title = L["Minimal"], desc = L["Just the time and the difference, no labels, no total, no panel."],
		settings = Look({ showLabel = false, showTotal = false, panel = false, width = 120, fontSize = 14 }) },
	{ key = "Large", title = L["Large"], desc = L["Bigger text for a high resolution or a far screen."],
		settings = Look({ fontSize = 20, smallSize = 12, width = 210 }) },
})
