-- Controller spells: where each key map button's spell goes on the game's
-- controller bars (Core/GamepadSpells.lua).
--
-- The controller follows the key map's grid, so a spell keeps its place
-- in the order with keys or with a controller: the fight's spells (bars 1
-- and 2) sit on the first page, the box between pulls (bar 3) on the
-- second, as on the keyboard. Bar 3's keys 10 to 12 press the Consumable
-- Bar, which keeps its own spot on screen, so they have no controller
-- slot.
--
-- The game's controller bars have two groups of four buttons each and are
-- named here by the first of their page slot ids: top 1, left 9, right
-- 17, bottom 25. The top bar's right group (5 to 8) is the game's own.
-- Page 1's bottom bar keeps its last four buttons free for the player.
local _, E = ...

local function Row(page, bar, count)
	local list = {}
	for button = 1, count do list[#list + 1] = { page, bar, button } end
	return list
end

local function Join(...)
	local out = {}
	for _, list in ipairs({ ... }) do
		for _, entry in ipairs(list) do out[#out + 1] = entry end
	end
	return out
end

E.gamepadBindings = {
	bars = { top = 1, left = 9, right = 17, bottom = 25 },
	-- Key map bar -> per button { page, controller bar, button on it }.
	grid = {
		-- Bar 1: the core, interrupt, movement and control on page 1's
		-- right bar; defensive, emergency, sustain and cooldown on its top
		-- bar.
		Join(Row(1, "right", 8), Row(1, "top", 4)),
		-- Bar 2: the second row on page 1's left bar; group defensive,
		-- cleanse, purge and support on its bottom bar.
		Join(Row(1, "left", 8), Row(1, "bottom", 4)),
		-- Bar 3, the box: page 2's left bar and its top bar's first button.
		Join(Row(2, "left", 8), Row(2, "top", 1)),
	},
	-- The game's stance bar (Stance, Stealth and forms) takes the place of
	-- one bar while a stance is on: its setting's value -> page and bar.
	-- 1 is off; 3 (page 1's right bar) is the game's default.
	stanceBar = {
		[2] = { 1, "left" }, [3] = { 1, "right" }, [4] = { 1, "bottom" },
		[5] = { 2, "top" }, [6] = { 2, "left" }, [7] = { 2, "right" }, [8] = { 2, "bottom" },
		[9] = { 3, "top" }, [10] = { 3, "left" }, [11] = { 3, "right" }, [12] = { 3, "bottom" },
	},
	stanceDefault = 3,
	-- How many of bar 1's buttons the stance bar holds.
	stanceButtons = 8,
}
