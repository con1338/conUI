-- EldoUI Flight Games (on by default): quick arcade games for the time on
-- a flight path.
--
--   Launcher   While you fly a flight path a small "Games" box shows
--              (EldoUI_FlightGamesLauncher, drag it where you like). It
--              shows the time left of the flight when the flight timer
--              knows the route. A click opens the game window; a
--              right-click puts the box away for this flight.
--   Window     EldoUI_FlightGames: a picker with every game and your best
--              score, and the play area. Keys and the mouse play; the
--              window takes only the keys the game in front of you uses,
--              every other key goes on to the game client as usual.
--   Games      Modules/FlightGames/Games/*.lua, each one registered with
--              M:RegisterGame (the fields are listed there).
--
-- Presentation only: nothing here acts in the game world. The window is
-- an EldoUI window with no protected frames. It pauses and closes when
-- combat starts and, by default, when you land; the best score of each
-- game is kept for the account. Off a flight path the window still opens
-- from its options page or with /eui games.
--
-- Written from scratch for EldoUI; the art is the game's own (icons and
-- creature models) and EldoUI's design tokens.
local _, E = ...
local L = E.L

local LAUNCHER = "EldoUI_FlightGamesLauncher"
local WINDOW = "EldoUI_FlightGames"
local LAUNCHER_POINT = { "TOP", "UIParent", "TOP", 0, -132 }
local STEP_MAX = 0.05 -- the longest step a game takes in one frame
local FRAME_MAX = 1 -- the most game time one frame can add
local PICK_COLUMNS = 4
local RECENT_MAX = 6  -- the last games the box offers

local M = E:NewModule("FlightGames", {
	title = "Flight Games",
	desc = "Games for a flight path: arcade, puzzles, cards, dice and board games, and quizzes. A small Games box opens the games while you fly. Use the keyboard and mouse to play. Landing or combat closes them.",
	category = "Quality of Life",
	frames = { WINDOW, LAUNCHER },
	savedKeys = { "profile.modules.FlightGames", "global.FlightGames" },
	optionsPage = "module:FlightGames",
	presets = { "Standard", "Compact", "Large", "Accent", "Calm" },
	reload = false,
	defaults = {
		enabled = true,
		launcher = true,          -- the Games box on a flight path
		launcherTime = true,      -- the time left of the flight on the box
		autoOpen = false,         -- open the games at take-off
		closeOnLanding = true,    -- landing closes the window
		sounds = true,            -- short sounds for points and game over
		models = true,            -- creature and character models in the games
		palette = "safe",         -- "safe", "class" or "accent": the colors of pieces
		gridLines = true,         -- a faint line between the cells of a board
		scale = 1,                -- the window's size
		lastGame = "",            -- the game the window opens on
		launcherPoint = false,    -- { point, x, y } after a drag, else the default
		windowPoint = false,      -- { left, top } after a drag, else centered
		speed = "normal",         -- "relaxed", "normal" or "fast": the games' pace
		modes = {},               -- game key -> the mode picked (board size, level)
		recent = {},              -- the last games played, newest first (the box's icons)
	},
})
E.FlightGames = M
M.LAUNCHER, M.WINDOW, M.LAUNCHER_POINT = LAUNCHER, WINDOW, LAUNCHER_POINT

---------------------------------------------------------------------------
-- Small helpers shared by the games
---------------------------------------------------------------------------
-- The random source; the test kit replaces it for repeatable boards.
M.Random = function(a, b)
	if b then return math.random(a, b) end
	return math.random(a)
end

local SPEED = { relaxed = 0.8, normal = 1, fast = 1.25 }
function M:Pace()
	return SPEED[self.db and self.db.speed] or 1
end

-- Piece colors: the color-blind safe set (default), the game's class
-- colors, or shades of the player's accent. Seven colors in a fixed order.
local SAFE_ORDER = { "sky", "orange", "green", "yellow", "purple", "vermilion", "blue" }
local CLASS_ORDER = { "MAGE", "DRUID", "HUNTER", "ROGUE", "PALADIN", "WARRIOR", "SHAMAN" }

function M:Palette()
	local kind = self.db and self.db.palette or "safe"
	local out = {}
	if kind == "class" then
		local colors = RAID_CLASS_COLORS
		for index, class in ipairs(CLASS_ORDER) do
			local c = type(colors) == "table" and colors[class]
			out[index] = c and { c.r, c.g, c.b } or nil
		end
	elseif kind == "accent" then
		local r, g, b = unpack(E.media.accentColor)
		for index = 1, #SAFE_ORDER do
			local shade = 0.45 + (index - 1) * 0.09
			out[index] = { math.min(1, r * shade + (1 - shade) * 0.35), math.min(1, g * shade + (1 - shade) * 0.35), math.min(1, b * shade + (1 - shade) * 0.35) }
		end
	end
	local safe = E.tokens.palette.safe
	for index, name in ipairs(SAFE_ORDER) do
		if not out[index] then out[index] = safe[name] end
	end
	return out
end

-- A text token as a color table: "accent", "body", "secondary", "dim",
-- "good", "warn", "bad", "gold".
function M.Color(kind)
	if kind == "accent" then return E.media.accentColor end
	return E.tokens.text[kind] or E.tokens.text.body
end

-- Sounds from the game's own sound kit, only while sounds are on.
local SOUNDS = {
	point = "kit:IG_MAINMENU_OPTION_CHECKBOX_ON",
	turn = "kit:U_CHAT_SCROLL_BUTTON",
	best = "kit:LEVELUPSOUND",
	over = "kit:IG_QUEST_FAILED",
	start = "kit:IG_MAINMENU_OPEN",
}
function M:Sound(kind)
	if not (self.db and self.db.sounds) then return end
	local id = SOUNDS[kind]
	if id then pcall(E.PlayMedia, E, id) end
end

local function OnTaxi()
	if type(UnitOnTaxi) ~= "function" then return false end
	local ok, on = pcall(UnitOnTaxi, "player")
	if not ok or E.Secret(on) then return false end
	return on and true or false
end
M.OnTaxi = OnTaxi

---------------------------------------------------------------------------
-- The games
---------------------------------------------------------------------------
-- M:RegisterGame{
--   key      "snake": saved scores and the last game use it
--   order    the place in the picker
--   group    the picker's group: "arcade", "puzzle", "board" or "quiz"
--   title    "Snake" (an English key; shown through L)
--   desc     one line for the picker card
--   controls the keys and clicks, shown under the window title
--   icon     a game icon path for the card
--   width, height  the play area in window units, or Size(mode) -> w, h
--   lower    true when a lower score is better (a time, a count of moves)
--   modes    optional { { key, title }, ... }: board sizes or levels; the
--            footer switches them and each mode keeps its own best
--   unit     "points" (default), "seconds", "moves", "guesses" or "shots":
--            how the score reads
--   typing   true when the game takes letters: P goes to the game, and
--            the Pause button pauses
--   theme    the table under the game: "felt", "wood", "stone" or "night"
--            (else the group's table)
--   wins     true when a game can be won (wins and streaks are counted);
--            by default the puzzle and board games
--   actions  optional { { key = "U", label = "Undo" }, ... }: footer
--            buttons that send that key to the game
--   New(host, mode) -> game with Start(), Update(dt), Key(key) -> handled,
--            optional KeyUp(key), Press(button, x, y), Stop(); x and y count from the
--            play area's top left corner, y downward.
-- }
M.games, M.gameByKey = {}, {}

function M:RegisterGame(def)
	if type(def) ~= "table" or type(def.key) ~= "string" or self.gameByKey[def.key] then return end
	def.order = def.order or (#self.games + 1) * 10
	def.unit = def.unit or "points"
	table.insert(self.games, def)
	table.sort(self.games, function(a, b) return a.order < b.order end)
	self.gameByKey[def.key] = def
	return def
end

---------------------------------------------------------------------------
-- Scores: the best and the number of games per game, for the account
---------------------------------------------------------------------------
local STAT_FIELDS = { "won", "streak", "topStreak", "time" }
local function Scores()
	local store = E:GetGlobal("FlightGames")
	if type(store) ~= "table" then return nil end
	if type(store.best) ~= "table" then store.best = {} end
	if type(store.played) ~= "table" then store.played = {} end
	for _, field in ipairs(STAT_FIELDS) do
		if type(store[field]) ~= "table" then store[field] = {} end
	end
	return store
end

-- True when a game can be won, so wins and streaks mean something.
local function CountsWins(def)
	if def.wins ~= nil then return def.wins and true or false end
	return def.group == "puzzle" or def.group == "board"
end
M.CountsWins = CountsWins

-- What the account did in a game (and mode): games played and won, the
-- current and the longest run of wins, the time played and the best.
function M:Stats(key)
	local store, def = Scores(), self.gameByKey[key]
	if not (store and def) then return nil end
	local id = self:SlotOf(def)
	return {
		played = tonumber(store.played[id]) or 0,
		won = tonumber(store.won[id]) or 0,
		streak = tonumber(store.streak[id]) or 0,
		topStreak = tonumber(store.topStreak[id]) or 0,
		time = tonumber(store.time[id]) or 0,
		best = self:Best(id),
		wins = CountsWins(def),
	}
end

-- Adds a finished game to the wins, the streaks and the time played.
function M:RecordResult(key, won, seconds)
	local store, def = Scores(), self.gameByKey[key]
	if not (store and def) then return end
	local id = self:SlotOf(def)
	store.time[id] = (tonumber(store.time[id]) or 0) + math.max(0, math.floor((tonumber(seconds) or 0) + 0.5))
	if not CountsWins(def) then return end
	if won then
		store.won[id] = (tonumber(store.won[id]) or 0) + 1
		local streak = (tonumber(store.streak[id]) or 0) + 1
		store.streak[id] = streak
		if streak > (tonumber(store.topStreak[id]) or 0) then store.topStreak[id] = streak end
	else
		store.streak[id] = 0
	end
end

-- The mode a game plays in (its first mode when none was picked).
function M:ModeOf(def)
	if type(def) == "string" then def = self.gameByKey[def] end
	if not (def and def.modes and def.modes[1]) then return nil end
	local picked = type(self.db.modes) == "table" and self.db.modes[def.key]
	for _, mode in ipairs(def.modes) do
		if mode.key == picked then return mode end
	end
	return def.modes[1]
end

-- The key a score is saved under: the game, plus its mode.
function M:ScoreKey(def)
	if type(def) == "string" then def = self.gameByKey[def] end
	if not def then return nil end
	local mode = self:ModeOf(def)
	return mode and (def.key .. ":" .. mode.key) or def.key
end

function M:CycleMode()
	local def = self.current
	if not (def and def.modes and #def.modes > 1) then return end
	local mode = self:ModeOf(def)
	local next = def.modes[1]
	for index, entry in ipairs(def.modes) do
		if entry == mode then next = def.modes[index % #def.modes + 1] break end
	end
	-- The running game is kept under the size it was played in.
	self:Park()
	self.parked = true
	if type(self.db.modes) ~= "table" then self.db.modes = {} end
	self.db.modes[def.key] = next.key
	self:Select(def.key)
end

function M:Best(key)
	local store = Scores()
	local best = store and store.best[key]
	return type(best) == "number" and best or nil
end

function M:Played(key)
	local store = Scores()
	return store and tonumber(store.played[key]) or 0
end

-- Keeps a finished game's score; true when it is a new best.
function M:RecordScore(key, score)
	local def, store = self.gameByKey[key], Scores()
	if not (def and store) or type(score) ~= "number" then return false end
	key = self:SlotOf(def)
	store.played[key] = (tonumber(store.played[key]) or 0) + 1
	local best = store.best[key]
	local better
	if def.lower then
		better = score > 0 and (type(best) ~= "number" or score < best)
	else
		better = score > 0 and (type(best) ~= "number" or score > best)
	end
	if better then store.best[key] = score end
	return better and true or false
end

function M:ResetScores()
	local store = Scores()
	if not store then return end
	for _, field in ipairs({ "best", "played", "won", "streak", "topStreak", "time" }) do
		if type(store[field]) == "table" then wipe(store[field]) end
	end
	if self.window and self.window:IsShown() then self:Render() end
end

---------------------------------------------------------------------------
-- Games in progress: kept for the account, one per game and board size,
-- and back (paused) the next time that game opens, on the next flight or
-- after a reload. A game opts in with Save() -> a plain table and
-- Load(table) -> true; a finished game or a new one forgets it.
---------------------------------------------------------------------------
local SAVE_VERSION = 1

local function Saved()
	local store = Scores()
	if not store then return nil end
	if type(store.saved) ~= "table" then store.saved = {} end
	return store.saved
end

-- A game's save: its own Save(), or a copy of the fields named in its
-- saveKeys list.
local function SaveOf(game)
	if game.Save then return game:Save() end
	if type(game.saveKeys) ~= "table" then return nil end
	local out = {}
	for _, key in ipairs(game.saveKeys) do out[key] = M.Board.Copy(game[key]) end
	return out
end

local function LoadInto(game, data)
	if game.Load then return game:Load(data) end
	if type(game.saveKeys) ~= "table" then return false end
	for _, key in ipairs(game.saveKeys) do game[key] = M.Board.Copy(data[key]) end
	if game.Loaded then game:Loaded() end
	if game.Draw then game:Draw() end
	return true
end

-- A save fits a game when both the module's and the game's own save
-- version match; a game that changes what it keeps raises its saveVersion,
-- and only its own saves are dropped.
local function Fits(entry, def)
	return type(entry) == "table" and entry.v == SAVE_VERSION and (tonumber(entry.gv) or 1) == (def and def.saveVersion or 1)
end

-- The save slot of the game in front of you: the game and board size it
-- was opened with, even when the size or the profile changed since.
function M:SlotOf(def)
	if def and def == self.current and self.currentId then return self.currentId end
	return self:ScoreKey(def)
end

-- Keeps the game in front of you while it is in progress.
function M:Park()
	local game, def = self.game, self.current
	if not (game and def and (game.Save or game.saveKeys) and (self.state == "play" or self.state == "pause")) then return end
	local saved = Saved()
	if not saved then return end
	local ok, data = pcall(SaveOf, game)
	if ok and type(data) == "table" then
		saved[self:SlotOf(def)] = { v = SAVE_VERSION, gv = def.saveVersion or 1, score = self.score or 0, clock = self.clock or 0, data = data }
	end
end

function M:Forget(def)
	local saved = Saved()
	if saved and def then saved[self:SlotOf(def)] = nil end
end

-- True when a game (in its current board size) waits to be played on.
function M:HasSaved(def)
	if type(def) == "string" then def = self.gameByKey[def] end
	local saved = Saved()
	local entry = saved and def and saved[self:ScoreKey(def)]
	return Fits(entry, def)
end

-- Puts a saved game back; true when it came back.
local function Restore(game, id, def)
	local saved = Saved()
	local entry = saved and saved[id]
	if type(entry) ~= "table" then return false end
	if not Fits(entry, def) or type(entry.data) ~= "table" or not (game.Load or game.saveKeys) then
		saved[id] = nil
		return false
	end
	local ok, loaded = pcall(LoadInto, game, entry.data)
	if not (ok and loaded) then
		saved[id] = nil
		return false
	end
	return true, tonumber(entry.score) or 0, tonumber(entry.clock) or 0
end

-- "1,240", "1:05" or "34 moves".
function M:FormatScore(def, score)
	if type(score) ~= "number" then return "-" end
	if def and def.unit == "seconds" then return E:FormatDuration(score, "clock") end
	if def and def.unit == "moves" then return E:Plural(score, "%d move", "%d moves"):format(score) end
	if def and def.unit == "guesses" then return E:Plural(score, "%d guess", "%d guesses"):format(score) end
	if def and def.unit == "shots" then return E:Plural(score, "%d shot", "%d shots"):format(score) end
	return BreakUpLargeNumbers and BreakUpLargeNumbers(math.floor(score)) or tostring(math.floor(score))
end

---------------------------------------------------------------------------
-- The flight: the launcher shows while on a flight path
---------------------------------------------------------------------------
-- Put away by a right-click (or by closing the window) for this flight only.
M.dismissed = false
-- The keys a game took and still holds down.
M.held = {}

local function FlightLeft()
	local qol = E.modules and E.modules.QoL
	local flight = qol and qol.active and qol.CurrentFlight and qol:CurrentFlight()
	local known = flight and tonumber(flight.known)
	if not (known and known > 0 and flight.started) then return nil end
	return math.max(known - (GetTime() - flight.started), 0)
end
M.FlightLeft = FlightLeft

function M:UpdateFlight()
	if not self.active then return end
	local flying = OnTaxi()
	if flying and not self.flying then
		self.flying = true
		self.dismissed = false
		if self.db.autoOpen and not InCombatLockdown() then self:Open() end
	elseif not flying and self.flying then
		self.flying = false
		self.dismissed = false
		if self.db.closeOnLanding and self.window and self.window:IsShown() and self.openedInFlight then
			self:Close("landed")
		end
	end
	self:UpdateLauncher()
end

---------------------------------------------------------------------------
-- The launcher box
---------------------------------------------------------------------------
local function SavePoint(frame, key)
	local point, _, _, x, y = frame:GetPoint(1)
	if point and x and y then M.db[key] = { point, math.floor(x + 0.5), math.floor(y + 0.5) } end
end

local function PlaceLauncher(box)
	box:ClearAllPoints()
	local saved = M.db.launcherPoint
	if type(saved) == "table" and type(saved[1]) == "string" and tonumber(saved[2]) and tonumber(saved[3]) then
		box:SetPoint(saved[1], UIParent, saved[1], saved[2], saved[3])
	else
		box:SetPoint(LAUNCHER_POINT[1], UIParent, LAUNCHER_POINT[3], LAUNCHER_POINT[4], LAUNCHER_POINT[5])
	end
end

-- The box (design decision): the Games title and the time left, a row
-- with the last games played (a click opens that game) and All games, a
-- cross that puts the box away for this flight, and a line that turns
-- the box off for every flight.
local BOX_ICON, BOX_GAP, BOX_PAD, BOX_MIN_W = 26, 4, 8, 196

local function RecentTip(button)
	return function(tooltip)
		local def = M.gameByKey[button.key]
		if not def then return end
		E.UIKit.TipText(tooltip, M.CardLine(def))
		E.UIKit.TooltipHint(tooltip, { L["Click"], L["play this game"] })
	end
end

function M:CreateLauncher()
	if self.launcher then return self.launcher end
	local Kit, size = E.UIKit, E.tokens.size
	local box = CreateFrame("Button", LAUNCHER, UIParent, "BackdropTemplate")
	box:SetSize(BOX_MIN_W, 96)
	box:SetFrameStrata("MEDIUM")
	box:SetClampedToScreen(true)
	box:SetMovable(true)
	box:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	box:RegisterForDrag("LeftButton")
	box.icon = box:CreateTexture(nil, "ARTWORK")
	box.icon:SetSize(28, 28)
	box.icon:SetPoint("TOPLEFT", BOX_PAD, -BOX_PAD)
	E:SetClientFile(box.icon, "Interface\\Icons\\INV_Misc_Ticket_Darkmoon_01", "Interface\\Icons\\INV_Misc_QuestionMark")
	E:TrimIcon(box.icon)
	box.close = Kit.IconButton(box, 16, "cross", function()
		M.dismissed = true
		M:UpdateLauncher()
	end, L["Put away"], L["The box goes away for this flight."])
	box.close:SetPoint("TOPRIGHT", -6, -6)
	box.title = E:CreateText(box, size.cardTitle, "LEFT")
	box.title:SetPoint("TOPLEFT", box.icon, "TOPRIGHT", 8, 0)
	box.title:SetPoint("RIGHT", box.close, "LEFT", -4, 0)
	box.title:SetWordWrap(false)
	box.line = E:CreateText(box, size.small, "LEFT")
	box.line:SetPoint("BOTTOMLEFT", box.icon, "BOTTOMRIGHT", 8, 0)
	box.line:SetPoint("RIGHT", -6, 0)
	box.line:SetWordWrap(false)
	box.divider = Kit.Divider(box)
	box.divider:SetPoint("TOPLEFT", box.icon, "BOTTOMLEFT", 0, -6)
	box.divider:SetPoint("RIGHT", -BOX_PAD, 0)
	-- The last games, then All games.
	box.recent = {}
	for index = 1, RECENT_MAX do
		local button = Kit.IconButton(box, BOX_ICON, "Interface\\Icons\\INV_Misc_QuestionMark", function(clicked)
			if InCombatLockdown() then return end
			M:Open(clicked.key)
		end, nil, nil, nil, { plain = true })
		button:Hide()
		box.recent[index] = button
	end
	box.all = Kit.IconButton(box, BOX_ICON, "Interface\\Icons\\INV_Misc_Book_09", function()
		if InCombatLockdown() then return end
		M:Open()
		if M:IsOpen() then M:ShowPicker() end
	end, L["All games"], L["Pick any game."], nil, { plain = true })
	-- Off for every flight; the options turn it back on.
	box.off = CreateFrame("Button", nil, box)
	box.off.text = Kit.Text(box.off, size.small, "LEFT", "secondary")
	box.off.text:SetPoint("LEFT", 0, 0)
	box.off.text:SetText(L["Don't show on flights"])
	box.off:SetSize(math.ceil((box.off.text:GetStringWidth() or 120) + 4), 16)
	box.off:SetPoint("BOTTOMLEFT", BOX_PAD, 6)
	box.off:SetScript("OnEnter", function(link) link.text:SetTextColor(Kit.Accent()) end)
	box.off:SetScript("OnLeave", function(link) link.text:SetTextColor(E:TokenColor("secondary")) end)
	box.off:SetScript("OnClick", function()
		M.db.launcher = false
		M:UpdateLauncher()
		E:Print(L["The Games box is off for every flight. Turn it back on in the Flight Games options; /eui games still opens the games."])
	end)
	Kit.Tooltip(box.off, L["Don't show on flights"], L["Turns the box off for every flight. The Flight Games options turn it back on."])
	box:SetScript("OnDragStart", function(frame) if not InCombatLockdown() then frame:StartMoving() end end)
	box:SetScript("OnDragStop", function(frame)
		frame:StopMovingOrSizing()
		SavePoint(frame, "launcherPoint")
	end)
	box:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			M.dismissed = true
			M:UpdateLauncher()
		else
			M:Toggle()
		end
	end)
	Kit.Tooltip(box, L["Flight Games"], L["Click: open the games. Right-click: put the box away for this flight. Drag: move it."])
	local since = 0
	box:SetScript("OnUpdate", function(_, elapsed)
		since = since + (elapsed or 0)
		if since < 1 then return end
		since = 0
		M:DrawLauncher()
	end)
	self.launcher = box
	self:StyleLauncher()
	return box
end

function M:StyleLauncher()
	local box = self.launcher
	if not box then return end
	E:SetPanelTemplate(box, true)
	box.title:SetTextColor(E:TokenColor("body"))
	box.line:SetTextColor(E:TokenColor("secondary"))
	box.off.text:SetTextColor(E:TokenColor("secondary"))
	PlaceLauncher(box)
end

-- The icon row: the last games played, then All games.
function M:LayoutLauncher()
	local box = self.launcher
	if not box then return end
	local recent = self:Recent()
	local x = BOX_PAD
	local top = -(BOX_PAD + 28 + 12)
	for index, button in ipairs(box.recent) do
		local key = recent[index]
		local def = key and self.gameByKey[key]
		button.key = key
		button:SetShown(def ~= nil)
		if def then
			E:SetClientFile(button.icon, def.icon or "Interface\\Icons\\INV_Misc_QuestionMark", "Interface\\Icons\\INV_Misc_QuestionMark")
			E:TrimIcon(button.icon)
			E.UIKit.Tooltip(button, L[def.title], RecentTip(button))
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", box, "TOPLEFT", x, top)
			x = x + BOX_ICON + BOX_GAP
		end
	end
	box.all:ClearAllPoints()
	box.all:SetPoint("TOPLEFT", box, "TOPLEFT", x, top)
	x = x + BOX_ICON + BOX_PAD
	box:SetSize(math.max(BOX_MIN_W, x, (box.off:GetWidth() or 0) + BOX_PAD * 2), BOX_PAD + 28 + 12 + BOX_ICON + 8 + 16 + 6)
end

function M:DrawLauncher()
	local box = self.launcher
	if not box then return end
	box.title:SetText(L["Games"])
	local left = self.db.launcherTime and FlightLeft()
	if left then
		box.line:SetText(L["Lands in %s"]:format(E:FormatDuration(left, "clock")))
	else
		box.line:SetText(L["Play while you fly"])
	end
end

function M:LauncherWanted()
	return self.active and self.db.launcher and self.flying and not self.dismissed
		and not (self.window and self.window:IsShown()) and not InCombatLockdown()
end

function M:UpdateLauncher()
	if not self:LauncherWanted() then
		if self.launcher then self.launcher:Hide() end
		return
	end
	local box = self:CreateLauncher()
	self:StyleLauncher()
	self:LayoutLauncher()
	self:DrawLauncher()
	box:Show()
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
-- The host a game draws in and reports to.
local function NewHost(window)
	local host = { area = window.area, module = M }
	-- Saves keep player/computer sides as 1/-1. Their faction is presentation.
	local playerFaction = "Alliance"
	if type(UnitFactionGroup) == "function" then
		local ok, faction = pcall(UnitFactionGroup, "player")
		if ok and not E.Secret(faction) and faction == "Horde" then playerFaction = "Horde" end
	end
	local function Faction(side)
		if side == 1 then return playerFaction end
		return playerFaction == "Horde" and "Alliance" or "Horde"
	end
	function host.FactionName(side)
		if Faction(side) == "Horde" then return E:GameText(FACTION_HORDE, L["Horde"]) end
		return E:GameText(FACTION_ALLIANCE, L["Alliance"])
	end
	function host.FactionColor(side, palette)
		return (palette or M:Palette())[Faction(side) == "Horde" and 6 or 7]
	end
	function host.FactionIcon(side)
		return Faction(side) == "Horde" and "Interface\\Icons\\INV_BannerPVP_01" or "Interface\\Icons\\INV_BannerPVP_02"
	end
	host.Random = function(a, b) return M.Random(a, b) end
	host.Palette = function() return M:Palette() end
	host.Color = M.Color
	host.Pace = function() return M:Pace() end
	host.Models = function() return M.db.models end
	host.GridLines = function() return M.db.gridLines end
	host.Sound = function(kind) M:Sound(kind) end
	function host.Score(value)
		M.score = value
		M:DrawStatus()
	end
	function host.Over(won)
		M:GameOver(won)
	end
	-- The pointer in play-area units from the area's top left corner.
	function host.Cursor()
		local area = window.area
		local x, y = GetCursorPosition()
		local scale = area:GetEffectiveScale()
		local left, top = area:GetLeft(), area:GetTop()
		if not (x and y and scale and scale > 0 and left and top) then return 0, 0 end
		return x / scale - left, top - y / scale
	end
	return host
end

-- The picker's groups, in their order.
local GROUPS = {
	{ key = "arcade", title = "Arcade" },
	{ key = "puzzle", title = "Puzzles" },
	{ key = "board", title = "Cards, dice and board" },
	{ key = "quiz", title = "Words and quiz" },
}
local CARD_H, CARD_GAP, GROUP_H = 96, 8, 30
local PICK_W, PICK_H = 860, 640
-- The play view: the window fits the game with this much room around it.
local STAGE_PAD, PLAY_MIN_W = 14, 600
local CHEER_W, CHEER_H = 110, 120
local CHROME_W, CHROME_H = 32, 148
-- The line over the play area: this round's time and the account's record.
local STATS_H = 26
local AREA_TOP = STATS_H + 8

-- The card over the play area: ready, paused and game over.
local function OverlayText(window, title, line, hint, icon, cheer)
	local over = window.overlay
	local card = over.card
	local areaWidth = window.area:GetWidth() or 320
	local width = math.max(220, math.min(360, areaWidth - 40))
	card:SetWidth(width)
	over.title:SetWidth(width - 32)
	over.line:SetWidth(width - 32)
	over.hint:SetWidth(width - 32)
	over.title:SetText(title or "")
	over.line:SetText(line or "")
	over.hint:SetText(hint or "")
	local top = 20
	window.cheer:Hide()
	if cheer and pcall(window.cheer.SetUnit, window.cheer, "player") then
		pcall(window.cheer.SetAnimation, window.cheer, M.Board.ANIM.dance)
		window.cheer:Show()
		over.icon:Hide()
		over.iconRing:Hide()
		top = CHEER_H + 14
	elseif icon then
		top = 70
		E:SetClientFile(over.icon, icon, "Interface\\Icons\\INV_Misc_QuestionMark")
		E:TrimIcon(over.icon)
		over.icon:Show()
		over.iconRing:Show()
	else
		over.icon:Hide()
		over.iconRing:Hide()
	end
	over.title:SetPoint("TOP", over.card, "TOP", 0, -top)
	local height = top + (over.title:GetStringHeight() or 20) + 8
		+ (over.line:GetStringHeight() or 14) + 12 + (over.hint:GetStringHeight() or 12) + 20
	card:SetHeight(math.floor(height + 0.5))
	over:Show()
end

local function CreatePicker(window)
	local Kit = E.UIKit
	local picker = CreateFrame("Frame", nil, window.content)
	picker:SetAllPoints()
	picker.scroll = Kit.ScrollArea(picker, { step = 60 })
	picker.scroll:SetAllPoints()
	picker.cards, picker.heads = {}, {}
	window.picker = picker
	return picker
end

local function Head(picker, index)
	local head = picker.heads[index]
	if head then return head end
	local child = picker.scroll.child
	head = CreateFrame("Frame", nil, child)
	head:SetHeight(GROUP_H - 6)
	head.text = E.UIKit.Text(head, E.tokens.size.section, "LEFT", "secondary")
	head.text:SetPoint("BOTTOMLEFT", 0, 6)
	head.line = head:CreateTexture(nil, "ARTWORK")
	head.line:SetColorTexture(unpack(E.tokens.edge.divider))
	E:Hairline(head.line, "h", 1)
	head.line:SetPoint("BOTTOMLEFT", 0, 0)
	head.line:SetPoint("BOTTOMRIGHT", 0, 0)
	picker.heads[index] = head
	return head
end

local function Card(picker, index)
	local card = picker.cards[index]
	if card then return card end
	local size = E.tokens.size
	card = CreateFrame("Button", nil, picker.scroll.child, "BackdropTemplate")
	card:SetHeight(CARD_H)
	E:SetTemplate(card, true)
	card.icon = card:CreateTexture(nil, "ARTWORK")
	card.icon:SetSize(38, 38)
	card.icon:SetPoint("TOPLEFT", 12, -12)
	card.ring = card:CreateTexture(nil, "OVERLAY")
	card.ring:SetPoint("TOPLEFT", card.icon, "TOPLEFT", -3, 3)
	card.ring:SetPoint("BOTTOMRIGHT", card.icon, "BOTTOMRIGHT", 3, -3)
	card.title = E.UIKit.Text(card, size.cardTitle, "LEFT", "title")
	card.title:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -2)
	card.title:SetPoint("RIGHT", -10, 0)
	card.title:SetWordWrap(false)
	card.best = E.UIKit.Text(card, size.small, "LEFT", "secondary")
	card.best:SetPoint("BOTTOMLEFT", card.icon, "BOTTOMRIGHT", 10, 2)
	card.best:SetPoint("RIGHT", -10, 0)
	card.best:SetWordWrap(false)
	card.desc = E.UIKit.Text(card, size.small, "LEFT", "secondary")
	card.desc:SetPoint("TOPLEFT", card.icon, "BOTTOMLEFT", 0, -8)
	card.desc:SetPoint("RIGHT", -12, 0)
	card.desc:SetJustifyV("TOP")
	card.desc:SetWordWrap(true)
	card.desc:SetMaxLines(2)
	card.hover = card:CreateTexture(nil, "HIGHLIGHT")
	card.hover:SetAllPoints()
	card.hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	card:SetScript("OnEnter", function(self)
		E.UIKit.FadeBorderColor(self, E.UIKit.Accent())
	end)
	card:SetScript("OnLeave", function(self)
		if self.key == M.db.lastGame then
			E.UIKit.FadeBorderColor(self, E.UIKit.Accent())
		else
			local r, g, b, a = unpack(E.media.borderColor)
			E.UIKit.FadeBorderColor(self, r, g, b, a)
		end
	end)
	card:SetScript("OnClick", function(self) M:Select(self.key) end)
	picker.cards[index] = card
	return card
end

-- "Best 1,240 · 12 games" under a card's title.
local function CardLine(def)
	local key = M:ScoreKey(def)
	local best, played = M:Best(key), M:Played(key)
	local text
	if not best and played == 0 then
		text = L["Not played yet"]
	else
		text = best and L["Best: %s"]:format(E:Highlight(M:FormatScore(def, best))) or L["No best yet"]
		if played > 0 then text = text .. "  ·  " .. E:Plural(played, "%d game", "%d games"):format(played) end
	end
	-- A game left in progress says so first.
	if M:HasSaved(def) then text = E:Highlight(L["In progress"]) .. "  ·  " .. text end
	return text
end

M.CardLine = CardLine

local function DrawPicker(window)
	local picker = window.picker
	local scroll = picker.scroll
	local width = (scroll.scroll:GetWidth() or 0)
	if width <= 0 then width = (window.content:GetWidth() or PICK_W - CHROME_W) - 12 end
	local cardWidth = math.max(150, math.floor((width - CARD_GAP * (PICK_COLUMNS - 1)) / PICK_COLUMNS))
	local y, cardIndex, headIndex = 0, 0, 0
	local accent = { E.UIKit.Accent() }
	for _, group in ipairs(GROUPS) do
		local members = {}
		for _, def in ipairs(M.games) do
			if (def.group or "arcade") == group.key then members[#members + 1] = def end
		end
		if #members > 0 then
			headIndex = headIndex + 1
			local head = Head(picker, headIndex)
			head:ClearAllPoints()
			head:SetPoint("TOPLEFT", scroll.child, "TOPLEFT", 0, -y)
			head:SetWidth(width)
			head.text:SetText(L[group.title])
			head:Show()
			y = y + GROUP_H
			for slot, def in ipairs(members) do
				cardIndex = cardIndex + 1
				local card = Card(picker, cardIndex)
				card.key = def.key
				card:SetWidth(cardWidth)
				card:ClearAllPoints()
				local column, row = (slot - 1) % PICK_COLUMNS, math.floor((slot - 1) / PICK_COLUMNS)
				card:SetPoint("TOPLEFT", scroll.child, "TOPLEFT", column * (cardWidth + CARD_GAP), -(y + row * (CARD_H + CARD_GAP)))
				E:SetClientFile(card.icon, def.icon or "Interface\\Icons\\INV_Misc_QuestionMark", "Interface\\Icons\\INV_Misc_QuestionMark")
				E:TrimIcon(card.icon)
				M.Board.Art(card.ring, "Ring", accent, def.key == M.db.lastGame and 0.9 or 0.35)
				card.title:SetText(L[def.title])
				card.desc:SetText(L[def.desc])
				card.best:SetText(CardLine(def))
				E:SetTemplate(card, true)
				if def.key == M.db.lastGame then
					card:SetBackdropBorderColor(E.UIKit.Accent())
				end
				card:Show()
			end
			y = y + math.ceil(#members / PICK_COLUMNS) * (CARD_H + CARD_GAP) + 6
		end
	end
	for index = cardIndex + 1, #picker.cards do picker.cards[index]:Hide() end
	for index = headIndex + 1, #picker.heads do picker.heads[index]:Hide() end
	scroll.child:SetHeight(math.max(1, y))
	scroll:Update()
end

-- The window fits what it shows: the picker, or the game with its stage.
local function FitWindow(window, width, height)
	if width then
		local wide = math.max(PLAY_MIN_W, (window.footerNeed or 0) + CHROME_W, width + CHROME_W + STAGE_PAD * 2)
		window:SetSize(wide, height + CHROME_H + AREA_TOP + STAGE_PAD)
	else
		window:SetSize(PICK_W, PICK_H)
	end
	-- The screen fit follows the new size.
	if window:IsShown() then E.WindowKit.ApplyScale(window) end
end

function M:CreateWindow()
	if self.window then return self.window end
	local Kit = E.UIKit
	local window = E.WindowKit.CreateWindow(WINDOW, { width = PICK_W, height = PICK_H, footer = 40,
		options = { page = "module:FlightGames" } })
	window:SetFrameStrata("DIALOG")

	-- The stage: a card that frames the play area.
	local stage = CreateFrame("Frame", nil, window.content, "BackdropTemplate")
	stage:SetPoint("TOP", 0, 0)
	E:SetTemplate(stage, true)
	stage.glow = stage:CreateTexture(nil, "BORDER")
	stage.glow:SetPoint("TOPLEFT", 1, -1)
	stage.glow:SetPoint("TOPRIGHT", -1, -1)
	stage.glow:SetHeight(48)
	stage.line = stage:CreateTexture(nil, "ARTWORK")
	E:Hairline(stage.line, "h", 2)
	stage.line:SetPoint("TOPLEFT", 1, -1)
	stage.line:SetPoint("TOPRIGHT", -1, -1)
	window.stage = stage

	-- The play area sits centered on the stage; each game sizes it.
	local area = CreateFrame("Frame", nil, stage)
	area:SetPoint("TOP", stage, "TOP", 0, -AREA_TOP)
	area:SetSize(400, 400)
	area:EnableMouse(true)
	area:SetClipsChildren(true)
	area.bg = area:CreateTexture(nil, "BACKGROUND", nil, -8)
	area.bg:SetAllPoints()
	area.bg:SetColorTexture(unpack(E.tokens.inset))
	-- The table the game is laid on (tiles of one texture, the last row
	-- and column cut to fit), and a soft shadow round its edge.
	area.tables = {}
	area.vignette = area:CreateTexture(nil, "BACKGROUND", nil, -4)
	area.vignette:SetAllPoints()
	M.Board.Art(area.vignette, "Vignette")
	window.area = area

	-- Over the play area: this round's time on the left, the account's
	-- games, wins and streak on the right.
	local stats = CreateFrame("Frame", nil, stage)
	stats:SetPoint("TOPLEFT", stage, "TOPLEFT", STAGE_PAD, -6)
	stats:SetPoint("TOPRIGHT", stage, "TOPRIGHT", -STAGE_PAD, -6)
	stats:SetHeight(STATS_H - 4)
	stats.clock = Kit.Text(stats, E.tokens.size.body, "LEFT", "body")
	stats.clock:SetPoint("LEFT", 0, 0)
	stats.record = Kit.Text(stats, E.tokens.size.small, "RIGHT", "secondary")
	stats.record:SetPoint("RIGHT", 0, 0)
	stats.record:SetPoint("LEFT", stats.clock, "RIGHT", 12, 0)
	stats.record:SetWordWrap(false)
	window.stats = stats
	area:SetScript("OnMouseDown", function(_, button) M:Press(button) end)

	-- Ready, paused and game over: a shade over the play area and a card
	-- with the game's icon, the score and what starts the next round.
	local overlay = CreateFrame("Frame", nil, area)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(area:GetFrameLevel() + 20)
	overlay.shade = overlay:CreateTexture(nil, "BACKGROUND")
	overlay.shade:SetAllPoints()
	overlay.shade:SetColorTexture(unpack(E.tokens.shade))
	local card = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
	card:SetPoint("CENTER", 0, 6)
	card:SetSize(300, 160)
	E:SetPanelTemplate(card, true)
	card.line = card:CreateTexture(nil, "ARTWORK")
	E:Hairline(card.line, "h", 2)
	card.line:SetPoint("TOPLEFT", 1, -1)
	card.line:SetPoint("TOPRIGHT", -1, -1)
	overlay.card = card
	overlay.icon = card:CreateTexture(nil, "ARTWORK")
	overlay.icon:SetSize(40, 40)
	overlay.icon:SetPoint("TOP", 0, -18)
	overlay.iconRing = card:CreateTexture(nil, "OVERLAY")
	overlay.iconRing:SetPoint("TOPLEFT", overlay.icon, "TOPLEFT", -4, 4)
	overlay.iconRing:SetPoint("BOTTOMRIGHT", overlay.icon, "BOTTOMRIGHT", 4, -4)
	overlay.title = Kit.Text(card, E.tokens.size.display, "CENTER", "title")
	overlay.title:SetPoint("TOP", card, "TOP", 0, -20)
	overlay.line = Kit.Text(card, E.tokens.size.body, "CENTER")
	overlay.line:SetWordWrap(true)
	overlay.line:SetPoint("TOP", overlay.title, "BOTTOM", 0, -8)
	overlay.hint = Kit.Text(card, E.tokens.size.small, "CENTER", "secondary")
	overlay.hint:SetWordWrap(true)
	overlay.hint:SetPoint("TOP", overlay.line, "BOTTOM", 0, -12)
	overlay:Hide()
	window.overlay = overlay

	-- At a new best the player's own character dances on the card, in
	-- the place of the game's icon.
	window.cheer = CreateFrame("PlayerModel", nil, card)
	window.cheer:SetSize(CHEER_W, CHEER_H)
	window.cheer:SetPoint("TOP", card, "TOP", 0, -8)
	window.cheer:Hide()

	CreatePicker(window)

	local footer = window.footer
	window.back = Kit.Button(footer, { text = L["All games"], width = 110, onClick = function() M:ShowPicker() end })
	window.back:SetPoint("LEFT", 0, -2)
	window.new = Kit.Button(footer, { text = L["New game"], width = 110, kind = "primary", onClick = function() M:NewGame() end })
	window.new:SetPoint("RIGHT", 0, -2)
	window.pause = Kit.Button(footer, { text = L["Pause"], width = 90, onClick = function() M:TogglePause() end })
	window.pause:SetPoint("RIGHT", window.new, "LEFT", -8, 0)
	window.mode = Kit.Button(footer, { text = "", width = 130, onClick = function() M:CycleMode() end,
		tip = { L["Board"], L["Click: the next board size or level. Each one keeps its own best."] } })
	window.mode:SetPoint("LEFT", window.back, "RIGHT", 8, 0)
	-- A game's own footer buttons (Undo, Hint, ...), one set per game.
	window.actions = {}
	-- The score and the best sit on the header's right, on the title's line.
	window.status = Kit.Text(window.header, E.tokens.size.cardTitle, "RIGHT", "secondary")
	window.status:SetPoint("TOPRIGHT", window.headerRight, "TOPRIGHT", 0, -4)
	window.status:SetWordWrap(false)

	-- Keys: only out of combat (the key pass-through is restricted in
	-- combat); a key the game does not use goes on to the client.
	-- A used key swallows only its own key-down: pass-through is handed
	-- back right after, so its key-up and every other key reach the client.
	window:EnableKeyboard(false)
	window:SetScript("OnKeyDown", function(frame, key)
		if InCombatLockdown() then return end
		local handled = M:Key(key)
		frame:SetPropagateKeyboardInput(not handled)
		if handled then
			M.held[key] = true
			C_Timer.After(0, function()
				if not InCombatLockdown() then frame:SetPropagateKeyboardInput(true) end
			end)
		end
	end)
	window:SetScript("OnKeyUp", function(frame, key)
		if InCombatLockdown() then return end
		frame:SetPropagateKeyboardInput(true)
		M.held[key] = nil
		M:KeyUp(key)
	end)
	window:SetScript("OnUpdate", function(_, elapsed) M:Step(elapsed) end)
	window:HookScript("OnShow", function(frame)
		frame:EnableKeyboard(not InCombatLockdown())
		M:UpdateLauncher()
	end)
	window:HookScript("OnHide", function(frame)
		frame:EnableKeyboard(false)
		M:ReleaseKeys()
		if M.state == "play" then M:SetPaused(true) end
		M:Park()
		if frame.cheer then frame.cheer:Hide() end
		-- Closed by the player in the air: the box stays away for this
		-- flight too.
		if M.flying and (not M.closingFor or M.closingFor == "player") then M.dismissed = true end
		M:UpdateLauncher()
	end)
	local function Save() M:SaveWindowPoint() end
	window:HookScript("OnDragStop", Save)
	window.header:HookScript("OnDragStop", Save)

	window.host = NewHost(window)
	self.window = window
	return window
end

function M:SaveWindowPoint()
	local window = self.window
	local left, top = window and window:GetLeft(), window and window:GetTop()
	if left and top then self.db.windowPoint = { math.floor(left + 0.5), math.floor(top + 0.5) } end
end

local function PlaceWindow(window)
	window:ClearAllPoints()
	local point = M.db.windowPoint
	if type(point) == "table" and tonumber(point[1]) and tonumber(point[2]) then
		window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", point[1], point[2])
	else
		window:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	end
end

-- The accent touches of the stage and the overlay card.
local function PaintAccents(window)
	local r, g, b = E.UIKit.Accent()
	window.stage.line:SetColorTexture(r, g, b, 0.85)
	window.overlay.card.line:SetColorTexture(r, g, b, 0.85)
	local glow = window.stage.glow
	glow:SetColorTexture(1, 1, 1, 1)
	if CreateColor then
		glow:SetGradient("VERTICAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, E.tokens.headerGlow))
	else
		glow:SetColorTexture(r, g, b, E.tokens.headerGlow / 2)
	end
	M.Board.Art(window.overlay.iconRing, "Ring", { r, g, b }, 0.9)
end

-- The tables (design decision): a tiled light map in a tint taken from
-- the theme's tokens. A game names its table, else its group's is used.
local TABLES = {
	felt = { art = "TableFelt", tint = function() return E.tokens.palette.tint.pine end, light = 0.4 },
	wood = { art = "TableWood", tint = function() return E.tokens.palette.bronze end, light = 0.34 },
	stone = { art = "TableStone", tint = function() return E.tokens.palette.tint.dusk end, light = 0.34, gray = 0.6 },
	-- The night sky fades toward the horizon, so it is stretched, not tiled.
	night = { art = "TableNight", tint = function() return E.tokens.palette.tint.midnight end, light = 0.22, stretch = true },
}
local GROUP_TABLE = { arcade = "night", puzzle = "stone", board = "felt", quiz = "wood" }
local TABLE_TILE = 256

function M:TableOf(def)
	local name = def and (TABLES[def.theme] and def.theme or GROUP_TABLE[def.group or "arcade"]) or "night"
	return name, TABLES[name] or TABLES.night
end

local function PaintTable(window, def)
	local area = window.area
	local _, look = M:TableOf(def)
	local tint = look.tint()
	local light, gray = look.light, look.gray or 0
	local r = (tint[1] * (1 - gray) + gray * 0.5) * light
	local g = (tint[2] * (1 - gray) + gray * 0.5) * light
	local b = (tint[3] * (1 - gray) + gray * 0.5) * light
	local width, height = area:GetWidth() or TABLE_TILE, area:GetHeight() or TABLE_TILE
	local tile = look.stretch and math.max(width, height) or TABLE_TILE
	local count = 0
	for top = 0, height - 1, tile do
		for left = 0, width - 1, tile do
			count = count + 1
			local tex = area.tables[count]
			if not tex then
				tex = area:CreateTexture(nil, "BACKGROUND", nil, -6)
				area.tables[count] = tex
			end
			local w, h = math.min(tile, width - left), math.min(tile, height - top)
			tex:SetTexture(M.Board.ART[look.art])
			if look.stretch then
				tex:SetTexCoord(0, 1, 0, 1)
			else
				tex:SetTexCoord(0, w / tile, 0, h / tile)
			end
			tex:SetSize(w, h)
			tex:ClearAllPoints()
			tex:SetPoint("TOPLEFT", area, "TOPLEFT", left, -top)
			tex:SetVertexColor(r * 2, g * 2, b * 2, 1)
			tex:Show()
		end
	end
	for index = count + 1, #area.tables do area.tables[index]:Hide() end
	area.vignette:SetVertexColor(1, 1, 1, 0.75)
end
M.PaintTable = PaintTable

-- The game's own footer buttons: each sends its key to the game, and
-- they sit after the board button.
local function ActionButtons(window, def)
	local list = window.actions[def.key]
	if list then return list end
	list = {}
	for index, action in ipairs(def.actions or {}) do
		local button = E.UIKit.Button(window.footer, { text = L[action.label], minWidth = 70,
			onClick = function() M:Action(action.key) end,
			tip = { L[action.label], L["Key: %s"]:format(action.key) } })
		button.actionKey = action.key
		list[index] = button
	end
	window.actions[def.key] = list
	return list
end

-- Places the footer for a game (or the picker) and keeps how wide it is.
local function LayoutFooter(window, def, picking)
	for key, list in pairs(window.actions) do
		for _, button in ipairs(list) do button:SetShown(not picking and def and key == def.key or false) end
	end
	local need = (window.back:GetWidth() or 110) + 24 + (window.pause:GetWidth() or 90) + 8 + (window.new:GetWidth() or 110)
	local anchor = window.back
	if window.mode:IsShown() then
		anchor = window.mode
		need = need + 8 + (window.mode:GetWidth() or 130)
	end
	if not picking and def then
		for _, button in ipairs(ActionButtons(window, def)) do
			button:ClearAllPoints()
			button:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
			button:Show()
			button:SetEnabled(M.state == "play")
			anchor = button
			need = need + 8 + (button:GetWidth() or 80)
		end
	end
	window.footerNeed = need
end

function M:Action(key)
	if self.state ~= "play" or not (self.game and self.game.Key) then return end
	self:Call(self.game.Key, self.game, key)
end

-- Reports a game's error to the error log; a game that keeps failing ends.
local FAULT_LIMIT = 3
function M:Fault(err)
	if E.errors and E.errors.Add then E.errors:Add("error", "EldoUI Flight Games: " .. tostring(err)) end
	self.faults = (self.faults or 0) + 1
	if self.faults >= FAULT_LIMIT then self:GameOver(false) end
end

-- Calls into the game; the results, or nothing after an error.
function M:Call(fn, ...)
	local result = { pcall(fn, ...) }
	if not result[1] then
		self:Fault(result[2])
		return
	end
	return unpack(result, 2)
end

-- Lets go of every key a game holds (on pause, closing and combat), so
-- nothing moves on its own when play goes on.
function M:ReleaseKeys()
	local game = self.game
	for key in pairs(self.held) do
		self.held[key] = nil
		if game and game.KeyUp then pcall(game.KeyUp, game, key) end
	end
	if game and game.ReleaseKeys then pcall(game.ReleaseKeys, game) end
end

function M:StyleWindow()
	local window = self.window
	if not window then return end
	window.userScale = tonumber(self.db.scale) or 1
	E.WindowKit.ApplyScale(window)
	PaintAccents(window)
end

---------------------------------------------------------------------------
-- Open, close and the game's life cycle
--   state: "pick" (the picker), "ready" (a game waits for its start),
--   "play", "pause", "over"
---------------------------------------------------------------------------
function M:Open(key)
	if not self.active or InCombatLockdown() then return end
	local window = self:CreateWindow()
	if window:IsShown() and (not key or (self.current and self.current.key == key)) then
		-- Already open: only its place changes; the game goes on.
		PlaceWindow(window)
		return
	end
	self.openedInFlight = self.flying and true or false
	PlaceWindow(window)
	self:StyleWindow()
	window:Show()
	key = key or (self.state == "pause" and self.current and self.current.key) or self.db.lastGame
	if self.current and self.state == "pause" and self.current.key == key then
		self:Render()
	elseif key and self.gameByKey[key] then
		self:Select(key)
	else
		self:ShowPicker()
	end
end

function M:Close(reason)
	local window = self.window
	if not (window and window:IsShown()) then return end
	self.closingFor = reason
	window:Hide()
	self.closingFor = nil
	if reason == "landed" or reason == "off" then self:StopGame() end
end

function M:Toggle()
	if self.window and self.window:IsShown() then self:Close("player") else self:Open() end
end

function M:IsOpen()
	return self.window ~= nil and self.window:IsShown()
end

function M:StopGame()
	self:ReleaseKeys()
	if not self.parked then self:Park() end
	self.parked = nil
	if self.game and self.game.Stop then pcall(self.game.Stop, self.game) end
	self.game, self.current, self.currentId, self.score = nil, nil, nil, nil
	self.state = "pick"
end

function M:ShowPicker()
	self:StopGame()
	self:Render()
end

-- Opens a game and waits for its start (a key or a click). A game saved in
-- progress comes back paused, unless `fresh` asks for a new one.
function M:Select(key, fresh)
	local def = self.gameByKey[key]
	if not def then return self:ShowPicker() end
	local window = self:CreateWindow()
	self:ReleaseKeys()
	if not self.parked then self:Park() end
	self.parked = nil
	if self.game and self.game.Stop then pcall(self.game.Stop, self.game) end
	self.db.lastGame = key
	self.current = def
	local width, height = def.width or 400, def.height or 400
	if def.Size then width, height = def.Size(self:ModeOf(def)) end
	window.area:SetSize(width, height)
	window.stage:SetSize(width + STAGE_PAD * 2, height + AREA_TOP + STAGE_PAD)
	local modes = def.modes and #def.modes > 1
	window.mode:SetShown(modes and true or false)
	LayoutFooter(window, def, false)
	FitWindow(window, width, height)
	PaintTable(window, def)
	self:Remember(key)
	-- One board per game and mode, made the first time and kept: each
	-- game draws in its own frame over the play area.
	self.instances = self.instances or {}
	local id = self:ScoreKey(def)
	for _, entry in pairs(self.instances) do entry.root:Hide() end
	local entry = self.instances[id]
	if not entry then
		local root = CreateFrame("Frame", nil, window.area)
		root:SetAllPoints()
		local host = setmetatable({ area = root }, { __index = window.host })
		local ok, made = pcall(def.New, host, self:ModeOf(def))
		if not ok or type(made) ~= "table" then
			root:Hide()
			if E.errors and E.errors.Add then E.errors:Add("error", ("EldoUI Flight Games: %s did not start: %s"):format(key, tostring(made))) end
			self.current = nil
			return self:ShowPicker()
		end
		entry = { root = root, game = made }
		self.instances[id] = entry
	end
	entry.root:Show()
	local game = entry.game
	self.game = game
	self.currentId = id
	self.score = 0
	self.clock = 0
	self.faults = 0
	self.state = "ready"
	self.restored = nil
	if fresh then
		self:Forget(def)
	else
		local back, score, clock = Restore(game, id, def)
		if back then
			self.score = score
			self.clock = clock
			self.state = "pause"
			self.restored = true
		end
	end
	self:Render()
end

-- The box's icons: the last games played, newest first.
function M:Remember(key)
	local recent = { key }
	if type(self.db.recent) == "table" then
		for _, other in ipairs(self.db.recent) do
			if #recent >= RECENT_MAX then break end
			if other ~= key and self.gameByKey[other] then recent[#recent + 1] = other end
		end
	end
	self.db.recent = recent
end

function M:Recent()
	local out = {}
	if type(self.db.recent) == "table" then
		for _, key in ipairs(self.db.recent) do
			if self.gameByKey[key] and #out < RECENT_MAX then out[#out + 1] = key end
		end
	end
	return out
end

-- A new game of the game in front of you (or of the last one).
function M:NewGame()
	local key = self.current and self.current.key or self.db.lastGame
	if not self.gameByKey[key] then key = self.games[1] and self.games[1].key end
	if not key then return end
	if not (self.current and self.current.key == key and self.state == "ready") then self:Select(key, true) end
	self:Begin()
end

-- The last game: on where it was left, else a new one.
function M:PlayLast()
	local key = self.db.lastGame
	if not self.gameByKey[key] then key = self.games[1] and self.games[1].key end
	if not key then return end
	self:Select(key)
	if self.state == "ready" then self:Begin() end
end

function M:Begin()
	if not (self.game and self.state == "ready") then return end
	self:Forget(self.current)
	self.state = "play"
	self.score = 0
	self.clock = 0
	self.newBest = nil
	self.faults = 0
	local ok, err = pcall(self.game.Start, self.game)
	if not ok and E.errors and E.errors.Add then E.errors:Add("error", "EldoUI Flight Games: " .. tostring(err)) end
	self:Sound("start")
	self:Render()
end

function M:SetPaused(paused)
	if paused and self.state == "play" then
		self.state = "pause"
		self:ReleaseKeys()
	elseif not paused and self.state == "pause" then
		self.state = "play"
		self.restored = nil
	else
		return
	end
	self:Render()
end

function M:TogglePause()
	if self.state == "play" then self:SetPaused(true) elseif self.state == "pause" then self:SetPaused(false) end
end

function M:GameOver(won)
	if not (self.current and (self.state == "play" or self.state == "pause")) then return end
	self.state = "over"
	self.won = won and true or false
	self.restored = nil
	self:Forget(self.current)
	local score = self.score or 0
	if self.current.lower and not won then
		-- A lower-is-better game that was lost keeps no score.
		self.newBest = false
		self:RecordScore(self.current.key, -1)
	else
		self.newBest = self:RecordScore(self.current.key, score)
	end
	self:RecordResult(self.current.key, won, self.clock)
	self:Sound(self.newBest and "best" or "over")
	self:Render()
end

-- One frame of the game in front of you. A slow frame is played as
-- several short steps, so the clock, timed scores and the action keep the
-- real time; a stall longer than FRAME_MAX (a loading screen) counts as
-- FRAME_MAX.
function M:Step(elapsed)
	if self.state ~= "play" or not self.game then return end
	local total = math.min(math.max(tonumber(elapsed) or 0, 0), FRAME_MAX)
	self.clock = (self.clock or 0) + total
	if math.floor(self.clock) ~= self.shownSecond then
		self.shownSecond = math.floor(self.clock)
		self:DrawStats()
	end
	local game = self.game
	if not game.Update then return end
	local steps = math.max(1, math.ceil(total / STEP_MAX - 1e-9))
	local dt = total / steps
	for _ = 1, steps do
		local ok, err = pcall(game.Update, game, dt)
		if not ok then
			if E.errors and E.errors.Add then E.errors:Add("error", "EldoUI Flight Games: " .. tostring(err)) end
			self:GameOver(false)
			return
		end
		if self.state ~= "play" or self.game ~= game then return end
	end
end

-- Keys: the window's own keys first, then the game's. True when used.
-- Space and Enter start or resume a game only while the pointer is on the
-- window; otherwise they stay the client's (jump, chat).
local START_KEYS = { SPACE = true, ENTER = true }
local function Starts(key)
	local window = M.window
	return START_KEYS[key] and window and window:IsShown() and window:IsMouseOver() and true or false
end
M.Starts = Starts
function M:Key(key)
	if type(key) ~= "string" or key == "ESCAPE" then return false end
	local state = self.state
	if state == "pick" then
		if Starts(key) then
			self:PlayLast()
			return true
		end
		return false
	end
	local typing = state == "play" and self.current and self.current.typing
	if key == "P" and not typing and (state == "play" or state == "pause") then
		self:TogglePause()
		return true
	end
	if state == "ready" or state == "over" then
		if Starts(key) then
			self:NewGame()
			return true
		end
		return false
	end
	if state == "pause" then
		if Starts(key) then
			self:SetPaused(false)
			return true
		end
		return false
	end
	if self.game and self.game.Key then
		return self:Call(self.game.Key, self.game, key) and true or false
	end
	return false
end

-- A key let go: games that move while a key is held stop.
function M:KeyUp(key)
	if self.game and self.game.KeyUp then pcall(self.game.KeyUp, self.game, key) end
end

-- A click in the play area: starts a waiting game, resumes a paused one,
-- otherwise goes to the game.
function M:Press(button, x, y)
	local state = self.state
	if state == "ready" or state == "over" then
		if button == "LeftButton" then self:NewGame() end
		return
	end
	if state == "pause" then
		self:SetPaused(false)
		return
	end
	if state ~= "play" or not (self.game and self.game.Press) then return end
	if not (x and y) and self.window then x, y = self.window.host.Cursor() end
	self:Call(self.game.Press, self.game, button, x, y)
end

---------------------------------------------------------------------------
-- Drawing the window
---------------------------------------------------------------------------
function M:DrawStatus()
	local window = self.window
	if not window then return end
	local def = self.current
	if not def then
		local left = FlightLeft()
		window.status:SetText(left and L["Lands in %s"]:format(E:FormatDuration(left, "clock")) or "")
		return
	end
	local best = self:Best(self:SlotOf(def))
	local text = L["Score: %s"]:format(E:Highlight(self:FormatScore(def, self.score or 0)))
	if best then text = text .. "     " .. L["Best: %s"]:format(self:FormatScore(def, best)) end
	window.status:SetText(text)
end

-- The line over the play area.
function M:DrawStats()
	local window = self.window
	local def = self.current
	if not (window and def) then return end
	local stats = window.stats
	stats.clock:SetText(L["Time %s"]:format(E:FormatDuration(self.clock or 0, "clock")))
	local record = self:Stats(def.key)
	if not record then
		stats.record:SetText("")
		return
	end
	local parts = { E:Plural(record.played, "%d game", "%d games"):format(record.played) }
	if record.wins and record.played > 0 then
		local share = math.floor(record.won / record.played * 100 + 0.5)
		parts[#parts + 1] = L["Won %d of %d (%d%%)"]:format(record.won, record.played, share)
		if record.topStreak > 0 then
			parts[#parts + 1] = L["Streak %d, best %d"]:format(record.streak, record.topStreak)
		end
	end
	if record.time > 0 then
		parts[#parts + 1] = L["Time played %s"]:format(E:FormatDuration(record.time, "long"))
	end
	stats.record:SetText(table.concat(parts, "  ·  "))
end

function M:Render()
	local window = self.window
	if not window then return end
	local def, state = self.current, self.state or "pick"
	local picking = state == "pick" or not def
	window.picker:SetShown(picking)
	window.stage:SetShown(not picking)
	if picking then FitWindow(window) end
	window.back:SetShown(not picking)
	window.pause:SetShown(not picking)
	window.pause:SetEnabled(state == "play" or state == "pause")
	window.pause:SetText(state == "pause" and L["Resume"] or L["Pause"])
	local mode = not picking and self:ModeOf(def)
	window.mode:SetShown(mode and #def.modes > 1 and true or false)
	if mode then window.mode:SetText(L[mode.title]) end
	LayoutFooter(window, def, picking)
	window.cheer:Hide()
	if picking then
		window:SetTitle(L["Flight Games"], L["Pick a game. Space or Enter starts the last one."])
		window.overlay:Hide()
		DrawPicker(window)
		self:DrawStatus()
		return
	end
	local modeNow = self:ModeOf(def)
	window:SetTitle(modeNow and (L[def.title] .. " · " .. L[modeNow.title]) or L[def.title], L[def.controls])
	local overlay = window.overlay
	if state == "ready" then
		OverlayText(window, L[def.title], L[def.desc], L["Space, Enter or a click starts. P pauses."], def.icon)
	elseif state == "pause" and self.restored then
		OverlayText(window, L["Saved game"], L["Score: %s"]:format(self:FormatScore(def, self.score or 0)),
			L["Space, Enter, P or a click plays on where you left off. New game starts over."], def.icon)
	elseif state == "pause" then
		OverlayText(window, L["Paused"], L["Score: %s"]:format(self:FormatScore(def, self.score or 0)), L["Space, Enter, P or a click plays on."])
	elseif state == "over" then
		local title = self.won and L["Well played!"] or L["Game over"]
		local line = L["Score: %s"]:format(self:FormatScore(def, self.score or 0))
		if self.current.lower and not self.won then line = L["No score this time."] end
		-- A game may sum up its round ("7 of 10 right").
		local summed, summary = false, nil
		if self.game and self.game.Summary then summed, summary = pcall(self.game.Summary, self.game) end
		if summed and type(summary) == "string" and summary ~= "" then line = summary .. "\n" .. line end
		if self.newBest then
			line = line .. "\n" .. E:Highlight(L["New best!"])
		else
			local best = self:Best(self:SlotOf(def))
			if best then line = line .. "\n" .. L["Best: %s"]:format(self:FormatScore(def, best)) end
		end
		OverlayText(window, title, line, L["Space, Enter or a click plays again."], def.icon, self.newBest and self.db.models)
	else
		overlay:Hide()
	end
	self:DrawStatus()
	self:DrawStats()
end

---------------------------------------------------------------------------
-- Life cycle
---------------------------------------------------------------------------
-- What the boards are drawn with; a change draws them again.
local function LookKey(db)
	return ("%s/%s/%s"):format(tostring(db.palette), tostring(db.gridLines), tostring(db.models))
end

local function OnControl() C_Timer.After(0.5, function() M:UpdateFlight() end) end

function M:OnInitialize()
	E:RegisterGlobal("FlightGames", { best = {}, played = {} })
end

function M:OnEnable()
	self.state = self.state or "pick"
	self.flying = false
	self.look = LookKey(self.db)
	self:RegisterEvent("PLAYER_CONTROL_LOST", OnControl)
	self:RegisterEvent("PLAYER_CONTROL_GAINED", OnControl)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() M:UpdateFlight() end)
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
		-- Combat: the game pauses and the window goes; it never blocks a key.
		if M.window then M.window:EnableKeyboard(false) end
		M:Close("combat")
		M:UpdateLauncher()
	end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() M:UpdateLauncher() end)
	-- A game in progress is kept when the session ends.
	self:RegisterEvent("PLAYER_LOGOUT", function() M:Park() end)
	self:UpdateFlight()
end

function M:OnDisable()
	self:Close("off")
	self:StopGame()
	self.flying = false
	if self.launcher then self.launcher:Hide() end
end

function M:OnProfileChanged()
	if not self.active then return end
	local look = LookKey(self.db)
	if self.look and self.look ~= look and self.Rebuild then self.Rebuild() end
	self.look = look
	self:StyleLauncher()
	self:UpdateLauncher()
	if self.window and self.window:IsShown() then
		self:StyleWindow()
		self:Render()
	end
end

-- /eui games: the game menu anywhere, on a flight path or not. A second
-- /eui games closes it again. Typed in combat, the menu opens as soon as
-- the fight is over.
local function ToggleGames()
	if not M.active then
		E:Print(E:ModuleOffHint("FlightGames"))
		return
	end
	if InCombatLockdown() then
		E:Print(L["The games open once combat ends."])
		E:RunOutOfCombat(function()
			if M.active and not M:IsOpen() then M:Open() end
		end, "FlightGames:open")
		return
	end
	M:Toggle()
end
E:AddCommand("games", "open or close the Flight Games, on a flight path or not", ToggleGames, "Tools")
E:AddCommand("fg", "open or close the Flight Games, on a flight path or not", ToggleGames, "Tools")
