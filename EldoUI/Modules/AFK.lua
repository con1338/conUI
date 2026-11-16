-- EldoUI AFK screen: while you are marked Away, the interface fades
-- and a panel shows your character, where you are, how long you have been
-- away and how many whispers came in.
--
-- Presentation only: it reacts to the game's own Away flag (/afk or the
-- game's idle timer) and never keeps you online, moves you or presses
-- anything. It closes at once when you come back, enter combat or click it.
-- The optional slow camera turn uses the camera API, off by default.
-- Whispers and guild chat that arrive while away are listed on the screen:
-- text only, nothing is answered, and the list is cleared when you
-- come back. Lines whose text or sender is a secret value are skipped.
--
-- Written from scratch for EldoUI; no code, strings or data from other addons.
local _, E = ...
local L = E.L

local M = E:NewModule("AFK", {
	title = "AFK Screen",
	category = "Interface",
	desc = "A calm screen with your character, zone, away time and whispers while you are marked Away.",
	frames = { "EldoUI_AFKScreen" },
	movers = {},
	blizzard = {},
	savedKeys = { "profile.modules.AFK", "EldoUIDB.screenFade" },
	optionsPage = "module:AFK",
	presets = { "Cinematic", "Default", "Minimal", "Portrait", "Streamer" },
	reload = false,
	defaults = {
		enabled = false,
		hideUI = true,          -- fade the whole interface while the screen shows
		model = true,           -- your character on the right
		whispers = true,        -- count whispers that arrive while away
		chatList = true,        -- list whispers that arrive while away
		chatGuild = true,       -- and guild chat
		chatLines = 6,          -- lines shown
		clock = true,
		inInstances = false,    -- also inside dungeons, raids and battlegrounds
		spin = false,           -- slow camera turn (camera API)
		spinSpeed = 0.05,
		panelHeight = 140,
		fontSize = 14,
		dim = 0.35,             -- darkening of the game world behind the panel
	},
})

local Secret = E.Secret

---------------------------------------------------------------------------
-- Screen shell, shared with the flight view (Modules/QoL/FlightView.lua):
-- a frame outside UIParent over the whole game world with a dim layer and
-- a bottom panel under an accent line, and the interface fade.
--
--   E.ScreenShell.Create(name, mouse)       the frame (hidden); Esc closes it
--   E.ScreenShell.Style(screen, dim, height) scale, dim and panel look
--   E.ScreenShell.FadeUI(owner, hide)       fade the interface out for
--                                            `owner`; it comes back when the
--                                            last owner lets go
--   E.ScreenShell.IsFaded()
--
-- Only UIParent's alpha changes, so there is one thing to put back. It
-- comes back at once when combat starts, and a fade left behind by a
-- reload or an error is undone at the next loading screen.
---------------------------------------------------------------------------
local Shell = {}
E.ScreenShell = Shell
local fadeOwners, savedAlpha = {}, nil

-- EldoUIDB.screenFade: true while a fade is up, so the next loading screen
-- can undo one a reload or an error left behind; cleared once undone.
E:RegisterStore("screenFade", { owner = "AFK", shape = "true while the screen is faded; nil otherwise" })

local function FadeMarker(on)
	if type(EldoUIDB) == "table" then EldoUIDB.screenFade = on or nil end
end

function Shell.Create(name, mouse)
	-- Not a child of UIParent, so it stays visible while the UI fades.
	local screen = CreateFrame("Frame", name, nil)
	screen:SetAllPoints(WorldFrame)
	screen:SetFrameStrata("FULLSCREEN")
	screen:EnableMouse(mouse and true or false)
	screen:Hide()

	screen.dim = screen:CreateTexture(nil, "BACKGROUND")
	screen.dim:SetAllPoints()

	local panel = CreateFrame("Frame", nil, screen)
	panel:SetPoint("BOTTOMLEFT", -E.pixel, -E.pixel)
	panel:SetPoint("BOTTOMRIGHT", E.pixel, -E.pixel)
	panel:EnableMouse(true)
	screen.panel = panel

	panel.line = panel:CreateTexture(nil, "ARTWORK")
	panel.line:SetPoint("TOPLEFT", 0, 0)
	panel.line:SetPoint("TOPRIGHT", 0, 0)
	if name then table.insert(UISpecialFrames, name) end
	return screen
end

function Shell.Style(screen, dim, height)
	screen:SetScale(UIParent:GetEffectiveScale())
	screen.dim:SetColorTexture(0, 0, 0, dim or 0)
	local panel = screen.panel
	panel:SetHeight(height)
	E:SetPanelTemplate(panel)
	panel.line:SetHeight(E.pixel * 2)
	E:AccentTexture(panel.line, 1)
end

local function Restore()
	if savedAlpha == nil then return end
	UIParent:SetAlpha(savedAlpha)
	savedAlpha = nil
	FadeMarker(false)
end

function Shell.FadeUI(owner, hide)
	if hide then
		fadeOwners[owner] = true
		-- Fading waits for the end of combat; the owner may be gone by then.
		E:RunOutOfCombat(function()
			if not next(fadeOwners) or savedAlpha ~= nil then return end
			savedAlpha = UIParent:GetAlpha()
			UIParent:SetAlpha(0)
			FadeMarker(true)
		end, "ScreenShell:fade")
	else
		fadeOwners[owner] = nil
		if not next(fadeOwners) then Restore() end
	end
end

function Shell.IsFaded()
	return savedAlpha ~= nil
end

-- Combat: the interface comes back at once (UIParent's alpha is not
-- protected), whoever faded it.
E:RegisterEvent("PLAYER_REGEN_DISABLED", function()
	wipe(fadeOwners)
	Restore()
end, Shell)

-- A fade that outlived its screen (a reload or an error while it showed):
-- the interface is put back at the next loading screen.
E:RegisterEvent("PLAYER_ENTERING_WORLD", function()
	if savedAlpha == nil and type(EldoUIDB) == "table" and EldoUIDB.screenFade then
		if UIParent:GetAlpha() < 0.01 then UIParent:SetAlpha(1) end
		FadeMarker(false)
	end
end, Shell)

---------------------------------------------------------------------------
-- Screen
---------------------------------------------------------------------------
local screen
local state = { started = nil, whispers = 0, spinning = false, lines = {} }
local MAX_LINES = 30   -- kept while away; the newest chatLines are shown

local function FormatTime(seconds) return E:FormatDuration(seconds, "clock") end

local function CreateScreen()
	screen = Shell.Create("EldoUI_AFKScreen", true)
	local panel = screen.panel

	panel.logo = panel:CreateTexture(nil, "ARTWORK")
	panel.logo:SetTexture(E.media.logo)
	panel.logo:SetPoint("LEFT", 24, 0)
	-- The logo is a 4:1 banner (troll and wordmark); a square box squashed
	-- it (0.6.5000 in game).
	panel.logo:SetSize(224, 56)

	panel.name = E:CreateText(panel, E.tokens.size.display, "LEFT")
	panel.name:SetPoint("TOPLEFT", panel.logo, "TOPRIGHT", 16, -2)
	panel.info = E:CreateText(panel, E.tokens.size.cardTitle, "LEFT")
	panel.info:SetPoint("TOPLEFT", panel.name, "BOTTOMLEFT", 0, -6)
	panel.guild = E:CreateText(panel, E.tokens.size.cardTitle, "LEFT")
	panel.guild:SetPoint("TOPLEFT", panel.info, "BOTTOMLEFT", 0, -4)
	panel.zone = E:CreateText(panel, E.tokens.size.cardTitle, "LEFT")
	panel.zone:SetPoint("TOPLEFT", panel.guild, "BOTTOMLEFT", 0, -4)

	panel.away = E:CreateText(panel, E.tokens.size.hero, "CENTER")
	panel.away:SetPoint("CENTER", 0, 10)
	panel.awayLabel = E:CreateText(panel, E.tokens.size.label, "CENTER")
	panel.awayLabel:SetPoint("BOTTOM", panel.away, "TOP", 0, 4)
	panel.whispers = E:CreateText(panel, E.tokens.size.body, "CENTER")
	panel.whispers:SetPoint("TOP", panel.away, "BOTTOM", 0, -6)

	panel.clock = E:CreateText(panel, E.tokens.size.hero, "RIGHT")
	panel.clock:SetPoint("TOPRIGHT", -24, -24)
	panel.date = E:CreateText(panel, E.tokens.size.body, "RIGHT")
	panel.date:SetPoint("TOPRIGHT", panel.clock, "BOTTOMRIGHT", 0, -4)
	panel.hint = E:CreateText(panel, E.tokens.size.small, "RIGHT")
	panel.hint:SetPoint("BOTTOMRIGHT", -24, 14)
	panel.hint:SetText(L["Click or press Esc to close. Moving clears Away."])

	-- "While you were away": whispers and guild lines, newest at the bottom.
	local chat = CreateFrame("Frame", nil, screen)
	chat:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 24, 16)
	chat:SetSize(460, 20)
	chat.title = E:CreateText(chat, E.tokens.size.body, "LEFT")
	chat.title:SetPoint("TOPLEFT", 0, 0)
	chat.rows = {}
	screen.chat = chat

	screen.model = CreateFrame("PlayerModel", nil, screen)
	screen.model:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", -80, -40)

	local elapsed = 0
	screen:SetScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		if elapsed < 0.5 then return end
		elapsed = 0
		M:UpdateTexts()
	end)
	screen:SetScript("OnMouseUp", function() M:Close() end)
	panel:SetScript("OnMouseUp", function() M:Close() end)
	-- Esc closes it like a click (and the game menu stays shut). However the
	-- screen goes away, the camera stops and the interface comes back.
	screen:SetScript("OnHide", function() M:ScreenHidden() end)
end

function M:StyleScreen()
	local db = self.db
	Shell.Style(screen, db.dim, db.panelHeight)
	local panel = screen.panel
	-- The character's and the guild's names, in the name font.
	E:SetNameTextFont(panel.name, db.fontSize + 8)
	E:SetFont(panel.info, db.fontSize)
	E:SetNameTextFont(panel.guild, db.fontSize)
	E:SetFont(panel.zone, db.fontSize)
	panel.info:SetTextColor(unpack(E.media.text.secondary))
	panel.guild:SetTextColor(unpack(E.media.text.secondary))
	panel.zone:SetTextColor(1, 1, 1)
	panel.awayLabel:SetTextColor(unpack(E.media.text.secondary))
	panel.awayLabel:SetText(L["Away"])
	panel.away:SetTextColor(E:TokenColor("accent"))
	panel.date:SetTextColor(unpack(E.media.text.secondary))
	panel.hint:SetTextColor(unpack(E.media.text.secondary))
	panel.clock:SetShown(db.clock)
	panel.date:SetShown(db.clock)
	panel.whispers:SetShown(db.whispers)
	self:LayoutChat()
	local height = math.max(UIParent:GetHeight() * 0.55, 300)
	screen.model:SetSize(height * 0.7, height)
	screen.model:SetShown(db.model)
end

---------------------------------------------------------------------------
-- Chat that arrived while away
---------------------------------------------------------------------------
local function ChatRow(index)
	local chat = screen.chat
	local row = chat.rows[index]
	if row then return row end
	row = CreateFrame("Frame", nil, chat)
	row.time = E:CreateText(row, E.tokens.size.label, "LEFT")
	row.time:SetPoint("LEFT", 0, 0)
	row.time:SetWidth(44)
	row.sender = E:CreateText(row, E.tokens.size.label, "LEFT")
	row.sender:SetPoint("LEFT", row.time, "RIGHT", 4, 0)
	row.sender:SetWidth(120)
	row.text = E:CreateText(row, E.tokens.size.label, "LEFT")
	row.text:SetPoint("LEFT", row.sender, "RIGHT", 6, 0)
	row.text:SetPoint("RIGHT", 0, 0)
	chat.rows[index] = row
	return row
end

function M:LayoutChat()
	local chat = screen and screen.chat
	if not chat then return end
	local db = self.db
	local size = math.max(10, db.fontSize - 2)
	local height = size + 6
	E:SetFont(chat.title, size + 1)
	chat.title:SetTextColor(E:TokenColor("accent"))
	chat.title:SetText(L["While you were away"])
	for index = 1, math.max(db.chatLines, #chat.rows) do
		local row = ChatRow(index)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", chat.title, "BOTTOMLEFT", 0, -4 - (index - 1) * height)
		row:SetSize(chat:GetWidth(), height)
		E:SetFont(row.time, size)
		E:SetNameTextFont(row.sender, size)
		E:SetNameTextFont(row.text, size)
		row.time:SetTextColor(unpack(E.media.text.secondary))
		row.text:SetTextColor(1, 1, 1)
	end
	chat:SetHeight(size + 8 + db.chatLines * height)
	self:UpdateChat()
end

function M:UpdateChat()
	local chat = screen and screen.chat
	if not chat then return end
	local db = self.db
	local lines = state.lines
	local shown = db.chatList and #lines > 0
	chat:SetShown(shown)
	if not shown then return end
	local first = math.max(1, #lines - db.chatLines + 1)
	for index, row in ipairs(chat.rows) do
		local line = index <= db.chatLines and lines[first + index - 1]
		if line then
			row.time:SetText(line.time)
			row.sender:SetText(line.sender)
			row.sender:SetTextColor(line.r, line.g, line.b)
			row.text:SetText(line.text)
			row:Show()
		else
			row:Hide()
		end
	end
end

-- A whisper or guild line while away (display only). Secret text or
-- senders are skipped: they would only be shown, never read, but Blizzard's
-- chat already has them.
function M:AddChatLine(kind, text, sender, guid)
	if not state.started or not self.db.chatList then return end
	if kind == "guild" and not self.db.chatGuild then return end
	if Secret(text) or Secret(sender) or type(text) ~= "string" or type(sender) ~= "string" then return end
	local name = sender
	if kind ~= "bnet" and Ambiguate then name = Ambiguate(sender, "short") end
	-- The player's own chat colors for whispers, Battle.net and guild.
	local info = _G.ChatTypeInfo and _G.ChatTypeInfo[kind == "bnet" and "BN_WHISPER" or kind == "guild" and "GUILD" or "WHISPER"]
	local r, g, b = 1, 1, 1
	if info and info.r then r, g, b = info.r, info.g, info.b end
	if kind ~= "bnet" and not Secret(guid) and type(guid) == "string" and GetPlayerInfoByGUID then
		local _, classFile = GetPlayerInfoByGUID(guid)
		local color = E:ClassColorObject(classFile)
		if color then r, g, b = color.r, color.g, color.b end
	end
	local lines = state.lines
	lines[#lines + 1] = { time = E:FormatTime(), sender = kind == "guild" and L["[G] %s"]:format(name) or name, text = text, r = r, g = g, b = b }
	while #lines > MAX_LINES do table.remove(lines, 1) end
	self:UpdateChat()
end

function M:UpdateTexts()
	if not screen or not screen:IsShown() then return end
	local panel = screen.panel
	panel.away:SetText(FormatTime(GetTime() - (state.started or GetTime())))
	if self.db.clock then
		panel.clock:SetText(E:FormatTime())
		panel.date:SetText(E:LongDay(time(), true))
	end
	if self.db.whispers then
		panel.whispers:SetText(state.whispers == 1 and L["1 whisper"] or L["%d whispers"]:format(state.whispers))
	end
end

function M:FillInfo()
	local panel = screen.panel
	local name = UnitName("player")
	local r, g, b = E:ClassColor("player")
	panel.name:SetText(name or "")
	panel.name:SetTextColor(r, g, b)
	local race = UnitRace("player")
	local class = UnitClass("player")
	panel.info:SetText(L["Level %d %s %s"]:format(UnitLevel("player"), race or "", class or ""))
	local guild, rank = GetGuildInfo("player")
	panel.guild:SetText(guild and ("<%s> %s"):format(guild, rank or "") or "")
	local zone, sub = GetRealZoneText(), GetSubZoneText()
	if sub and sub ~= "" and sub ~= zone then
		panel.zone:SetText(("%s, %s"):format(sub, zone or ""))
	else
		panel.zone:SetText(zone or "")
	end
	if self.db.model then
		screen.model:SetUnit("player")
		screen.model:SetFacing(-0.4)
		screen.model:SetCamDistanceScale(1.1)
	end
end

---------------------------------------------------------------------------
-- Show and close
---------------------------------------------------------------------------
local function SetSpin(on)
	if on and not state.spinning and MoveViewLeftStart then
		MoveViewLeftStart(M.db.spinSpeed)
		state.spinning = true
	elseif not on and state.spinning then
		if MoveViewLeftStop then MoveViewLeftStop() end
		state.spinning = false
	end
end

local function SetUIHidden(hide)
	Shell.FadeUI("AFK", hide)
end

local function InteractionOpen()
	for _, name in ipairs({ "CinematicFrame", "MovieFrame", "BarberShopFrame" }) do
		local frame = rawget(_G, name)
		if frame and E.FrameCheck(frame, "IsShown") then return true end
	end
	-- An NPC window (vendor, trainer, bank ...) counts while the game says it
	-- is open: the interaction events below track it.
	return M.interacting == true
end

function M:CanShow()
	if not self.active or InCombatLockdown() or UnitAffectingCombat("player") or InteractionOpen() then return false end
	if C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() then return false end
	if not self.db.inInstances and IsInInstance() then return false end
	return true
end

function M:Open()
	if not self:CanShow() then return end
	if not screen then CreateScreen() end
	state.started = state.started or GetTime()
	self:StyleScreen()
	self:FillInfo()
	E:SlideIn(screen, "DOWN")
	self:UpdateTexts()
	if self.db.hideUI then SetUIHidden(true) end
	if self.db.spin then SetSpin(true) end
end

-- Every way the screen goes (Esc, a click, combat, moving) ends here too.
function M:ScreenHidden()
	SetSpin(false)
	SetUIHidden(false)
end

function M:Close()
	self:ScreenHidden()
	if screen and screen:IsShown() then E:SlideOut(screen, "DOWN") end
end

local function IsAway()
	local away = UnitIsAFK("player")
	if Secret(away) then return nil end
	return away and true or false
end

function M:Check()
	local away = IsAway()
	if away == nil then return end
	if away then
		if not self:CanShow() then self:Close() return end
		if not state.started then
			state.started = GetTime()
			state.whispers = 0
		end
		if not (screen and screen:IsShown()) then self:Open() end
	else
		state.started = nil
		wipe(state.lines)
		self:UpdateChat()
		self:Close()
	end
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:OnInitialize()
	E:AddCommand("afk", "test  show the AFK screen for a moment (click to close)", function()
		if not M.active then
			E:Print(E:ModuleOffHint("AFK"))
			return
		end
		state.started = GetTime()
		state.whispers = 0
		wipe(state.lines)
		M:Open()
	end, "Layout & frames")
end

local function InteractionStarted(_, event)
	if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then M.interacting = true end
	M:ScreenHidden()
	if screen then
		for _, animation in pairs(screen.eldoAnim or {}) do animation:Stop() end
		screen:Hide()
	end
end

local function InteractionEnded(_, event)
	if event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then M.interacting = nil end
	C_Timer.After(0, function() if M.active then M:Check() end end)
end

function M:OnEnable()
	self:RegisterUnitEvent("PLAYER_FLAGS_CHANGED", "player", function() M:Check() end)
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
		-- Combat: get out of the way at once (UIParent's alpha is not
		-- protected, so restoring it in combat is fine).
		SetSpin(false)
		SetUIHidden(false)
		if screen then screen:Hide() end
	end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() M:Check() end)
	for _, event in ipairs({ "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "CINEMATIC_START", "PLAY_MOVIE" }) do
		self:RegisterEvent(event, InteractionStarted)
	end
	for _, event in ipairs({ "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "CINEMATIC_STOP", "STOP_MOVIE" }) do
		self:RegisterEvent(event, InteractionEnded)
	end
	local function Whisper(_, event, text, sender, ...)
		if screen and screen:IsShown() then state.whispers = state.whispers + 1 end
		if event == "CHAT_MSG_BN_WHISPER" then
			M:AddChatLine("bnet", text, sender)
		else
			M:AddChatLine("whisper", text, sender, (select(10, ...)))
		end
	end
	self:RegisterEvent("CHAT_MSG_WHISPER", Whisper)
	self:RegisterEvent("CHAT_MSG_BN_WHISPER", Whisper)
	self:RegisterEvent("CHAT_MSG_GUILD", function(_, _, text, sender, ...)
		M:AddChatLine("guild", text, sender, (select(10, ...)))
	end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() M:Close() end)
	self:Check()
end

function M:OnDisable()
	self:Close()
end

function M:OnProfileChanged()
	if screen and screen:IsShown() then
		self:StyleScreen()
		self:FillInfo()
		-- Restart the turn so a new speed applies at once.
		SetSpin(false)
		if self.db.spin then SetSpin(true) end
		SetUIHidden(self.db.hideUI and true or false)
	end
end

M.options = {
	{ type = "header", label = "AFK screen" },
	{ type = "description", label = "Shows while the game marks you Away (/afk, or after a few idle minutes). You stay Away until you move or type, as always." },
	{ type = "toggle", key = "hideUI", label = "Fade the interface", desc = "The rest of the interface turns invisible while the screen shows, and comes back when you return." },
	{ type = "toggle", key = "model", label = "Show your character", desc = "Your character on the right side of the screen." },
	{ type = "toggle", key = "whispers", label = "Count whispers", desc = "How many whispers arrived while you were away. Read them in chat when you're back." },
	{ type = "toggle", key = "chatList", label = "List whispers", desc = "Whispers that arrive while you are away, listed on the screen (time, sender, text). Cleared when you come back; they stay in chat as always." },
	{ type = "toggle", key = "chatGuild", label = "Include guild chat", desc = "Guild chat lines join the list.", dependsOn = "chatList" },
	{ type = "range", key = "chatLines", label = "Lines shown", desc = "How many of the newest lines the list shows.", min = 3, max = 12, step = 1, dependsOn = "chatList" },
	{ type = "toggle", key = "clock", label = "Clock and date", desc = "Your computer's time and date." },
	{ type = "toggle", key = "inInstances", label = "Also in instances", desc = "Show it inside dungeons, raids and battlegrounds too." },
	{ type = "toggle", key = "spin", label = "Slow camera turn", desc = "The camera slowly circles your character." },
	{ type = "range", key = "spinSpeed", label = "Turn speed", desc = "How fast the camera turns.", min = 0.01, max = 0.2, step = 0.01, hidden = function() return not M.db.spin end },
	{ type = "range", percent = true, key = "dim", label = "Darken the world", desc = "How dark the game world behind the panel gets.", min = 0, max = 0.8, step = 0.05 },
	{ type = "range", unit = "px", key = "panelHeight", label = "Panel height", desc = "Height of the info panel at the bottom.", min = 100, max = 220, step = 5 },
	{ type = "range", key = "fontSize", label = "Text size", desc = "Size of the info text; the name is a little bigger.", min = 10, max = 20, step = 1 },
	{ type = "execute", label = "Test", desc = "Shows the screen now (/eui afk test). Click to close.", func = function() if M.active then state.started = GetTime(); M:Open() end end },
}

E:RegisterStyles("AFK", {
	{ key = "Default", title = "Default", desc = "Fade the UI, show your character, clock and whispers.",
		settings = { hideUI = true, model = true, whispers = true, chatList = true, clock = true, spin = false, dim = 0.35, panelHeight = 140, fontSize = 14 } },
	{ key = "Cinematic", title = "Cinematic", desc = "Slow camera turn, darker world, tall panel.",
		settings = { hideUI = true, model = false, spin = true, spinSpeed = 0.04, dim = 0.5, panelHeight = 170, fontSize = 15 } },
	{ key = "Minimal", title = "Minimal", desc = "Just the panel; the UI and world stay as they are.",
		settings = { hideUI = false, model = false, spin = false, dim = 0, panelHeight = 110, fontSize = 13 } },
	{ key = "Portrait", title = "Portrait", desc = "Your character large on screen, no camera turn.",
		settings = { hideUI = true, model = true, spin = false, dim = 0.6, panelHeight = 140, fontSize = 14 } },
	{ key = "Streamer", title = "Streamer", desc = "Big text and clock, whispers and chat hidden.",
		settings = { hideUI = true, model = true, whispers = false, chatList = false, clock = true, dim = 0.3, panelHeight = 200, fontSize = 18 } },
})
