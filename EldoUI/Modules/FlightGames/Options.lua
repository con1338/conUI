-- EldoUI Flight Games: options page and style presets.
local _, E = ...
local L = E.L
local M = E.FlightGames

-- A look change restyles the boards already made and draws them again;
-- the game in front of you goes on.
local function Rebuild()
	M.Board.Restyle()
	for _, entry in pairs(M.instances or {}) do
		local game = entry.game
		if game.Draw then pcall(game.Draw, game) end
	end
	if M.window and M.window:IsShown() then
		M:StyleWindow()
		M:Render()
	end
end
M.Rebuild = Rebuild

-- The count line on top of the page; the picker names every game.
local function Games()
	local count = #M.games
	return E:Plural(count, "%d game in four groups: arcade, puzzles, cards, dice and board, and words and quiz.",
		"%d games in four groups: arcade, puzzles, cards, dice and board, and words and quiz."):format(count)
end

M.options = {
	{ type = "description", label = Games },
	{ type = "tab", label = "Flights" },
	{ type = "header", label = "On a flight path" },
	{ type = "toggle", key = "launcher", label = "Games box while flying",
		desc = "A small Games box shows while you fly a flight path. Click it to open the games; right-click puts it away for this flight." },
	{ type = "toggle", key = "launcherTime", label = "Time left on the box", dependsOn = "launcher",
		desc = "The box shows when you land, once the flight timer knows the route." },
	{ type = "toggle", key = "autoOpen", label = "Open the games at take-off",
		desc = "The game window opens on your last game as soon as the flight starts." },
	{ type = "toggle", key = "closeOnLanding", label = "Close the games when you land",
		desc = "Landing closes the window it opened in flight; your best score is kept. Off: play on after landing." },
	{ type = "execute", label = "Play now",
		desc = "Opens the games here and now, on a flight path or not. Typing /eui games does the same.",
		func = function() M:Open() end },
	{ type = "tab", label = "Games" },
	{ type = "header", label = "Play" },
	{ type = "select", key = "speed", label = "Pace", values = { relaxed = "Relaxed", normal = "Normal", fast = "Fast" },
		order = { "relaxed", "normal", "fast" },
		desc = "How fast the action games run (Snake, Rune Stack, Gryphon Glide and Brick Breaker) and how long WoW Trivia gives you for each question." },
	{ type = "toggle", key = "sounds", label = "Sounds",
		desc = "Short sounds from the game for points, a new best and the end of a game." },
	{ type = "header", label = "Best scores" },
	{ type = "execute", label = "Clear the best scores", confirm = L["Clear the best score of every game on this account? This can't be undone."],
		desc = "Forgets every best score and game count, for all characters on this account.",
		func = function() M:ResetScores() end },
	{ type = "tab", label = "Look" },
	{ type = "header", label = "Look" },
	{ type = "select", key = "palette", label = "Piece colors", values = { safe = "Color-blind safe", class = "Class colors", accent = "Accent shades" },
		order = { "safe", "class", "accent" },
		desc = "The colors of the blocks, tiles and bricks. Color-blind safe keeps every color apart for all kinds of color blindness." },
	{ type = "toggle", key = "gridLines", label = "Lines between cells",
		desc = "A thin gap between the cells of a board." },
	{ type = "toggle", key = "models", label = "Creature models",
		desc = "The games use the game's own creature models (the gryphon in Gryphon Glide), and your character dances at a new best. Off: icons only." },
	{ type = "range", percent = true, key = "scale", label = "Window size", min = 0.7, max = 1.5, step = 0.05,
		desc = "The size of the game window." },
	{ type = "execute", label = "Reset the positions",
		desc = "Puts the Games box and the game window back in their first place.",
		func = function()
			M.db.launcherPoint, M.db.windowPoint = false, false
			M:StyleLauncher()
			if M.window and M.window:IsShown() then M:Open() end
		end },
}

local function Look(base)
	local out = { palette = "safe", gridLines = true, models = true, scale = 1, launcherTime = true }
	for key, value in pairs(base) do out[key] = value end
	return out
end

E:RegisterStyles("FlightGames", {
	{ key = "Standard", title = L["Standard"], desc = L["Color-blind safe pieces, lines between cells, creature models and the time left on the box."],
		settings = Look({}) },
	{ key = "Compact", title = L["Compact"], desc = L["A smaller game window and a box without the time left."],
		settings = Look({ scale = 0.85, launcherTime = false }) },
	{ key = "Large", title = L["Large"], desc = L["A bigger game window for a high resolution or a far screen."],
		settings = Look({ scale = 1.25 }) },
	{ key = "Accent", title = L["Accent"], desc = L["Pieces in shades of your accent color."],
		settings = Look({ palette = "accent" }) },
	{ key = "Calm", title = L["Calm"], desc = L["Class colors, solid boards without cell lines and icons instead of models."],
		settings = Look({ palette = "class", gridLines = false, models = false }) },
})
