-- EldoUI QoL: small comforts in the spirit of all-in-one helper addons,
-- each with its own toggle. Anything that acts for the player is off by
-- default, and nothing acts in combat. One module, one page with the tabs
-- Interface, Social, Quests, Travel and Sound and misc. The quest helpers,
-- reward values, durability figure, edge panels and game setting rows
-- (the former Tweaks module) live in Modules/QoL/Tweaks.lua, the game
-- settings browser in Modules/QoL/CVars.lua; old Tweaks settings move
-- here once per profile (Modules/QoL/Tweaks.lua, MergeTweaks).
--
--   * Prompts: summons and resurrections get a clear EldoUI prompt with a
--     countdown, a sound and a taskbar flash. You still click Accept.
--   * Social blocks: decline duels, party invites, requests to join your
--     group, guild invites and shared quests from people who aren't friends
--     (out of combat only). Nothing is ever accepted for you.
--   * Chat: filter duel results and drunken messages.
--   * Look: the Blizzard bar's gryphons; XP bar text always on; quest text
--     size and instant quest text. (Zone text, boss banners, event toasts and
--     the cutscene skip moved to Alerts and Messages, Modules/Notifications.)
--   * Quest tracker: /eui tracker or a small button collapses it, per character.
--     The quest log gets a tick on each zone to track all its quests.
--   * Flight timer: learns how long each flight takes and shows the flight
--     as a route with its stops, time left and arrival time.
--   * Flight view (Modules/QoL/FlightView.lua, off by default): a calm
--     screen while on a taxi, on the AFK screen's shell.
--   * Sound and graphics: a volume panel (/eui volume), rested emote sounds
--     off, audio follows a new output device, mute your own list of sound
--     IDs, screen effects, weather.
--   * Wowhead: Ctrl+Alt-click a chat link, or /eui wowhead over a tooltip,
--     for a Wowhead address in a copy box.
--
-- Game settings (CVars) go through E:SetCVar with the owner "QoL", so the
-- player's own value comes back when an option goes off or with "Blizzard
-- default".
--
-- Written from scratch for EldoUI; no code, strings or data from other addons.
local _, E = ...
local L = E.L

local M = E:NewModule("QoL", {
	title = "Quality of Life",
	aliases = { "Tweaks" }, -- merged in: /eui tweaks and the search still find this page
	category = "Quality of Life",
	desc = "Summon and resurrection prompts, social blocks, quest helpers and reward values, flight timer, durability figure, screen edge panels, sound and game settings.",
	frames = { "EldoUI_Prompt", "EldoUI_Volume" },
	movers = { "EldoUI_Prompt", "EldoUI_FlightBar", "EldoUI_Volume" },
	blizzard = { "objective-tracker", "world-map-quest-log", "flight-map", "durability-figure" },
	savedKeys = { "profile.modules.QoL", "EldoUIDB.qol", "EldoUIDB.private.Tweaks" },
	optionsPage = "module:QoL",
	presets = { "Default", "Quiet", "Questing", "FastQuesting", "Clean", "Framed", "Minimal" },
	defaults = {
		-- Prompts (show only)
		summonPrompt = true,
		resPrompt = true,
		promptSound = "kit:READY_CHECK", -- media id, "none" for silence
		promptFlash = true,               -- flash the game in the taskbar
		-- Social blocks (act for the player: off)
		blockDuels = false,
		blockInvites = false,
		blockRequestedInvites = false,
		blockGuildInvites = false,
		blockSharedQuests = false,
		guildAreFriends = true,
		announceBlocks = true,
		-- Chat
		filterDuelSpam = false,
		filterDrunkSpam = false,
		-- Look (gryphons moved to Action Bars, quest text to NPC Windows)
		xpBarText = false,
		-- Quest tracker and log
		trackerButton = true,
		zoneTracking = true,
		-- Flight
		flightTimer = true,
		flightFade = true,      -- fade in at take-off, out on landing
		flightArrival = true,   -- arrival clock time after the time left
		flightStops = true,     -- name of the next stop
		flightWidth = 320,
		flightView = false,     -- calm full-screen view while on a taxi
		flightViewExitOnQueue = true, -- a queue pop brings the interface back
		flightViewDim = 0.2,    -- darkening of the world behind the view
		-- Sound and graphics
		silenceRestedEmotes = false,
		keepAudioSynced = false,
		muteSounds = "",
		noScreenEffects = false,
		noDrunkenHaze = true,
		weather = "game",       -- game, 0, 1, 2, 3
		volumePanel = false,    -- keep the volume panel on screen
		volumeChannels = false, -- also effects, music, ambience and dialog
		-- Wowhead
		wowheadLinks = true,    -- Ctrl+Alt-click a chat link
		wowheadSite = "classic",
		wowheadLanguage = "auto", -- "auto" follows the game's language, else a Wowhead language path
	},
})

local Secret = E.Secret

-- Game settings: E:SetCVar remembers the player's value; RestoreCVar puts
-- one setting back when its option goes off.
local CVAR_OWNER = "QoL"

local function CVarExists(name)
	return C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(name) ~= nil
end

local function SetCVarOwned(name, value)
	if CVarExists(name) then E:SetCVar(name, value, CVAR_OWNER) end
end

local function RestoreCVar(name)
	E:RestoreCVar(name, CVAR_OWNER)
end

-- Data that isn't a profile setting, account-wide in the saved file under
-- "qol" (the key it always had): tracker[character] (the quest tracker
-- folded), flights[route] (learned flight times in seconds at normal
-- flight speed, "From > To")
-- and activeFlight (the flight in the air, for a reload). Store() is the
-- only place that writes the key; other parts of EldoUI read it through
-- M.Store or M:GetFlightTime.
E:RegisterStore("qol", { owner = "QoL", accessor = "Store" })

local function Shape(store)
	store = type(store) == "table" and store or {}
	if store.tracker == nil then store.tracker = {} end
	if store.flights == nil then store.flights = {} end
	return store
end

local function Store()
	EldoUIDB.qol = Shape(EldoUIDB.qol)
	return EldoUIDB.qol
end
M.Store = Store

-- Forget drops the character's quest tracker fold.
E:RegisterCharacterForget(function(_, key)
	local tracker = Store().tracker
	if type(tracker) == "table" then tracker[key] = nil end
end)

-- Flat EldoUI button with the accent on hover (read when drawn).
-- The shared kit's button (E.UIKit.Button: hover and press look); `tip`
-- set on it later shows on hover.
local function FlatButton(parent, width, height, label)
	local button = E.UIKit.Button(parent, label, { width = width, height = height })
	button:HookScript("OnEnter", function(self)
		if self.tip then
			E.UIKit.AnchorTooltip(self)
			GameTooltip:SetText(self.tip)
			GameTooltip:Show()
		end
	end)
	button:HookScript("OnLeave", function() GameTooltip_Hide() end)
	return button
end

---------------------------------------------------------------------------
-- Friends: Battle.net and character friends, and guild members if wanted
---------------------------------------------------------------------------
local function ShortName(name)
	return name and name:match("^[^%-]+") or name
end

local function IsFriend(name)
	if Secret(name) or not name then return true end -- unknown: leave the popup alone
	local short = ShortName(name)
	for index = 1, C_FriendList.GetNumFriends() do
		local info = C_FriendList.GetFriendInfoByIndex(index)
		if info and ShortName(info.name) == short then return true end
	end
	if C_BattleNet and C_BattleNet.GetFriendAccountInfo then
		for index = 1, E:BNetFriendCount() do
			local account = C_BattleNet.GetFriendAccountInfo(index)
			local game = account and account.gameAccountInfo
			if game and game.characterName and ShortName(game.characterName) == short then return true end
		end
	end
	if M.db.guildAreFriends and IsInGuild() then
		if C_GuildInfo and C_GuildInfo.MemberExistsByName then
			if C_GuildInfo.MemberExistsByName(name) or C_GuildInfo.MemberExistsByName(short) then return true end
		else
			for index = 1, GetNumGuildMembers() do
				if ShortName(GetGuildRosterInfo(index)) == short then return true end
			end
		end
	end
	return false
end

local function Announce(text)
	if M.db.announceBlocks then M:Print(text) end
end

---------------------------------------------------------------------------
-- Summon and resurrection prompt: show only, the player clicks Accept.
---------------------------------------------------------------------------
local RES_POPUPS = { "RESURRECT", "RESURRECT_NO_SICKNESS", "RESURRECT_NO_TIMER" }

function M:CreatePrompt()
	local prompt = CreateFrame("Frame", "EldoUI_Prompt", UIParent)
	prompt:SetSize(320, 96)
	prompt:SetFrameStrata("DIALOG")
	prompt:Hide()
	E:SetPanelTemplate(prompt)
	-- The dialog shell's look: header-font title, body text, a primary
	-- Accept (the frame stays on its own mover).
	prompt.title = E.UIKit.Title(prompt, E.tokens.size.dialogTitle, "CENTER")
	prompt.title:SetPoint("TOP", 0, -10)
	prompt.text = E.UIKit.Text(prompt, E.tokens.size.body, "CENTER")
	prompt.text:SetPoint("TOP", prompt.title, "BOTTOM", 0, -6)
	prompt.text:SetWidth(296)
	prompt.timer = E:CreateStatusBar(prompt)
	prompt.timer:SetPoint("BOTTOMLEFT", 8, 40)
	prompt.timer:SetPoint("BOTTOMRIGHT", -8, 40)
	prompt.timer:SetHeight(4)
	prompt.accept = E.UIKit.Button(prompt, E:GameText(ACCEPT, L["Accept"]), { width = 140, large = true, kind = "primary" })
	prompt.accept:SetPoint("BOTTOMLEFT", 8, 8)
	prompt.decline = E.UIKit.Button(prompt, E:GameText(DECLINE, L["Decline"]), { width = 140, large = true })
	prompt.decline:SetPoint("BOTTOMRIGHT", -8, 8)
	prompt:SetScript("OnUpdate", function(dialog, elapsed)
		if dialog.stillValid then
			-- A resurrection has no countdown: check now and then that the
			-- offer is still there.
			dialog.checkIn = (dialog.checkIn or 0) - (elapsed or 0)
			if dialog.checkIn <= 0 then
				dialog.checkIn = 0.25
				if not dialog.stillValid() then
					M:HidePrompt()
					return
				end
			end
		end
		if not dialog.timeLeft then return end
		local left = dialog.timeLeft()
		if not left or left <= 0 then
			M:HidePrompt()
			return
		end
		dialog.timer:SetValue(left)
	end)
	-- The prompt can be built late (first summon or test), so name the owner.
	local previous = E.currentModule
	E.currentModule = self
	E:CreateMover(prompt, "EldoUI_Prompt", L["Summon and Resurrection Prompt"], { "TOP", "UIParent", "TOP", 0, -180 }, { sample = { kind = "toast" } })
	E.currentModule = previous
	self.prompt = prompt
end

function M:HidePrompt(kind)
	local prompt = self.prompt
	if not prompt or (kind and prompt.kind ~= kind) then return end
	prompt.kind, prompt.stillValid, prompt.timeLeft = nil, nil, nil
	prompt:Hide()
end

-- kind: "summon", "res" or "test". stillValid (optional) is asked a few
-- times a second; the prompt closes once it returns false.
function M:ShowPrompt(title, text, timeLeft, onAccept, onDecline, kind, stillValid)
	if not self.prompt then self:CreatePrompt() end
	local prompt = self.prompt
	prompt.kind, prompt.stillValid, prompt.checkIn = kind, stillValid, 0.25
	local r, g, b = unpack(E.media.accentColor)
	prompt.title:SetText(title)
	prompt.text:SetText(text)
	prompt.timer:SetStatusBarColor(r, g, b)
	local total = timeLeft and timeLeft() or 0
	prompt.timer:SetMinMaxValues(0, math.max(total, 1))
	prompt.timer:SetShown(total > 0)
	prompt.timeLeft = total > 0 and timeLeft or nil
	prompt.accept:SetScript("OnClick", function() M:HidePrompt(); onAccept() end)
	prompt.decline:SetScript("OnClick", function() M:HidePrompt(); onDecline() end)
	E:SlideIn(prompt, "UP")
	E:PlayMedia(self.db.promptSound, "Master")
	if self.db.promptFlash and FlashClientIcon then FlashClientIcon() end
end

function M:OnSummon()
	if not self.db.summonPrompt or not C_SummonInfo then return end
	local summoner = C_SummonInfo.GetSummonConfirmSummoner()
	local area = C_SummonInfo.GetSummonConfirmAreaName()
	if Secret(summoner) or Secret(area) then return end
	self:ShowPrompt(L["Summon"], L["%s wants to summon you to %s."]:format(summoner or L["Someone"], area or "?"),
		C_SummonInfo.GetSummonConfirmTimeLeft,
		function()
			C_SummonInfo.ConfirmSummon()
			StaticPopup_Hide("CONFIRM_SUMMON")
		end,
		function()
			C_SummonInfo.CancelSummon()
			StaticPopup_Hide("CONFIRM_SUMMON")
		end, "summon")
end

local function AnyResPopup()
	if not StaticPopup_Visible then return false end
	for _, which in ipairs(RES_POPUPS) do
		if StaticPopup_Visible(which) then return true end
	end
	return false
end

-- The offer is gone once the player is alive again, or once Blizzard's own
-- resurrect popup (seen earlier) has closed: accepted or declined there, or
-- expired.
local function ResOfferValid()
	local prompt = M.prompt
	local dead = UnitIsDeadOrGhost("player")
	if not Secret(dead) and not dead then return false end
	if AnyResPopup() then
		prompt.sawPopup = true
	elseif prompt.sawPopup then
		return false
	end
	return true
end

function M:OnResurrect(offerer)
	if not self.db.resPrompt or Secret(offerer) then return end
	if not self.prompt then self:CreatePrompt() end
	self.prompt.sawPopup = false
	self:ShowPrompt(E:GameText(RESURRECT, L["Resurrection"]), L["%s wants to resurrect you."]:format(offerer or L["Someone"]),
		nil, -- resurrections have no countdown API: ResOfferValid closes it
		function()
			AcceptResurrect()
			for _, which in ipairs(RES_POPUPS) do StaticPopup_Hide(which) end
		end,
		function()
			DeclineResurrect()
			for _, which in ipairs(RES_POPUPS) do StaticPopup_Hide(which) end
		end, "res", ResOfferValid)
end

-- "Test prompt" on the options page: the prompt with a 15 second countdown,
-- so it can be seen and placed. Its buttons only close it.
function M:TestPrompt()
	local ends = GetTime() + 15
	self:ShowPrompt(L["Summon"], L["Test: someone wants to summon you to Ironforge."],
		function() return ends - GetTime() end, function() end, function() end, "test")
end

---------------------------------------------------------------------------
-- Another addon doing the same job: only that part stands back
-- (Data/Competitors.lua); everything else stays on.
---------------------------------------------------------------------------
local function Mine(feature)
	return not E:StandsBack(M, feature)
end
M.Mine = Mine

-- The note on an option row whose job another addon does.
local function HandledBy(feature)
	return function()
		local standing, _, title = E:StandsBack(M, feature)
		return standing and L["Handled by %s. Type %s to choose."]:format(title, E:Highlight("/eui addons")) or nil
	end
end
M.HandledBy = HandledBy

function M:OnStandBack()
	self:ApplySounds()
	self:ApplyGraphics()
	self:ApplyVolume()
	if self.flightBar and E:StandsBack(self, "flightbar") then self.flightBar:Hide() end
end

---------------------------------------------------------------------------
-- Social blocks (out of combat only; friends and guild exempt)
---------------------------------------------------------------------------
function M:OnDuel(name)
	if not self.db.blockDuels or not Mine("duels") or InCombatLockdown() or IsFriend(name) then return end
	CancelDuel()
	StaticPopup_Hide("DUEL_REQUESTED")
	Announce(L["Declined a duel from %s."]:format(name))
end

function M:OnPartyInvite(name)
	if not self.db.blockInvites or not Mine("invites") or InCombatLockdown() or IsFriend(name) then return end
	DeclineGroup()
	StaticPopup_Hide("PARTY_INVITE")
	Announce(L["Declined a group invite from %s."]:format(name))
end

-- Someone asks to join your group (or a member suggests someone): Blizzard
-- shows GROUP_INVITE_CONFIRMATION. Requests from strangers are declined;
-- suggestions and requests from friends are left to you.
function M:OnInviteConfirmation()
	if not self.db.blockRequestedInvites or not Mine("invites") or InCombatLockdown() then return end
	if not (GetNextPendingInviteConfirmation and GetInviteConfirmationInfo and RespondToInviteConfirmation) then return end
	local invite = GetNextPendingInviteConfirmation()
	if not invite then return end
	local kind, name = GetInviteConfirmationInfo(invite)
	if Secret(kind) or kind ~= _G.LE_INVITE_CONFIRMATION_REQUEST or IsFriend(name) then return end
	RespondToInviteConfirmation(invite, false)
	StaticPopup_Hide("GROUP_INVITE_CONFIRMATION")
	Announce(L["Declined a request to join your group from %s."]:format(name or "?"))
end

function M:OnGuildInvite(name, guild)
	if not self.db.blockGuildInvites or InCombatLockdown() or Secret(name) or IsFriend(name) then return end
	DeclineGuild()
	StaticPopup_Hide("GUILD_INVITE")
	if GuildInviteFrame and GuildInviteFrame:IsShown() then GuildInviteFrame:Hide() end
	Announce(L["Declined a guild invite from %s (%s)."]:format(name or "?", guild or "?"))
end

function M:OnQuestDetail()
	if not self.db.blockSharedQuests or not Mine("sharedquests") or InCombatLockdown() or not UnitIsPlayer("questnpc") then return end
	local name = UnitName("questnpc")
	if IsFriend(name) then return end
	DeclineQuest()
	Announce(L["Declined a quest shared by %s."]:format(name or "?"))
end

---------------------------------------------------------------------------
-- Chat filters
---------------------------------------------------------------------------
-- A Lua pattern for a game format string (positional arguments included).
local function ToPattern(format)
	local spec = E.ChatParse:BuildPattern(format)
	return spec and spec.pattern
end

local duelPatterns, drunkPatterns = {}, {}
local function BuildPatterns()
	if #duelPatterns > 0 then return end
	for _, name in ipairs({ "DUEL_WINNER_KNOCKOUT", "DUEL_WINNER_RETREAT" }) do
		duelPatterns[#duelPatterns + 1] = ToPattern(_G[name])
	end
	for index = 1, 4 do
		drunkPatterns[#drunkPatterns + 1] = ToPattern(_G["DRUNK_MESSAGE_OTHER" .. index])
		drunkPatterns[#drunkPatterns + 1] = ToPattern(_G["DRUNK_MESSAGE_ITEM_OTHER" .. index])
	end
end

local function SystemFilter(_, _, message)
	if not M.active or type(message) ~= "string" or Secret(message) then return false end
	if M.db.filterDuelSpam then
		for _, pattern in ipairs(duelPatterns) do
			if message:find(pattern) then return true end
		end
	end
	if M.db.filterDrunkSpam then
		for _, pattern in ipairs(drunkPatterns) do
			if message:find(pattern) then return true end
		end
	end
	return false
end

---------------------------------------------------------------------------
-- Look: XP text. Gryphons belong to Action Bars ("Main bar end caps") and
-- quest text size / instant quest text to NPC Windows (element "Quest,
-- gossip and NPC dialogs"); see MigrateMoved below.
---------------------------------------------------------------------------
function M:ApplyLook()
	if self.active and self.db.xpBarText then SetCVarOwned("xpBarText", 1) else RestoreCVar("xpBarText") end
end

-- v0.5.x settings that now live with their owner. Gryphons go to Action
-- Bars here (it loads before QoL); quest text is picked up by NPC Windows
-- itself (it loads after QoL). Runs once per profile: the old key is gone
-- afterwards.
function M:MigrateMoved()
	local db = self.db
	-- The prompt sound used to be one tick for sound and taskbar flash.
	if type(db.promptSound) == "boolean" then
		db.promptFlash = db.promptSound
		db.promptSound = db.promptSound and "kit:READY_CHECK" or "none"
	end
	if db.hideGryphons ~= nil then
		local bars = E.db.modules and E.db.modules.ActionBars
		if db.hideGryphons and type(bars) == "table" then bars.endCaps = "hide" end
		db.hideGryphons = nil
	end
end

---------------------------------------------------------------------------
-- Quest tracker: collapse with /eui tracker or the small button, per character.
---------------------------------------------------------------------------
local function Tracker()
	return ObjectiveTrackerFrame or _G.QuestWatchFrame
end

-- The tracker belongs to Blizzard UI > Objective / quest tracker; QoL's
-- collapse is one of its "Improve" extras.
local TRACKER = "objective-tracker"

local function TrackerAllowed()
	return M.active and E:BlizzardAllowed(TRACKER, "improve")
end

-- Blizzard's own fold (SetCollapsed) runs the tracker's layout; called from
-- addon code that layout and every later update of the tracker would run
-- tainted. So EldoUI never calls it: the Quest Tracker module parks the
-- tracker off screen, and without that module the tracker is faded out.
local fallbackFold
local fallbackMouse = setmetatable({}, { __mode = "k" })

local function ApplyFallbackMouse(tracker)
	local mouse = fallbackMouse[tracker]
	if not mouse then
		mouse = {}
		fallbackMouse[tracker] = mouse
	end
	-- Keep the native mouse flag until an open state can actually restore
	-- it. An open and refold in combat share this frame's pending update.
	E:RunOutOfCombat(function()
		if fallbackMouse[tracker] ~= mouse then return end
		if fallbackFold and fallbackFold.tracker == tracker and Tracker() == tracker then
			if mouse.enabled == nil then mouse.enabled = E.FrameMouse(tracker, "IsMouseEnabled") end
			if mouse.enabled ~= nil then tracker:EnableMouse(false) end
		else
			if mouse.enabled ~= nil and E.FrameMouse(tracker, "IsMouseEnabled") == false then
				tracker:EnableMouse(mouse.enabled)
			end
			fallbackMouse[tracker] = nil
		end
	end, mouse)
end

local function RestoreFallbackFold()
	local old = fallbackFold
	if not old then return end
	fallbackFold = nil
	if old.alpha ~= nil and E.PlainCall(old.tracker.GetAlpha, old.tracker) == 0 then old.tracker:SetAlpha(old.alpha) end
	ApplyFallbackMouse(old.tracker)
end

local function SetTrackerCollapsed(collapsed)
	local tracker = Tracker()
	local owner = E:GetModule("ObjectiveTracker")
	if owner and owner.active and owner.SetUserCollapsed and tracker == _G.ObjectiveTrackerFrame then
		RestoreFallbackFold()
		owner:SetUserCollapsed(collapsed)
		return
	end
	if not collapsed or not tracker or (fallbackFold and fallbackFold.tracker ~= tracker) then RestoreFallbackFold() end
	if not (tracker and collapsed) then return end
	if not fallbackFold then fallbackFold = { tracker = tracker, alpha = E.PlainCall(tracker.GetAlpha, tracker) } end
	if fallbackFold.alpha ~= nil then tracker:SetAlpha(0) end
	ApplyFallbackMouse(tracker)
end

-- The button sits on the tracker's own top row, left of Blizzard's fold
-- button (and of its filter button while that shows), so it never reaches
-- above the tracker onto the frame placed there (the Split Timer under the
-- minimap).
local filterHooked = false
local function PlaceTrackerButton(button, tracker)
	-- A folded tracker is off screen: the button stays where its corner was.
	local owner = E:GetModule("ObjectiveTracker")
	local spot = owner and owner.FoldSpot and owner:FoldSpot()
	if spot then
		button:ClearAllPoints()
		button:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", spot[1] - 24, spot[2])
		return
	end
	local header = tracker.Header
	local fold = header and header.MinimizeButton
	local filter = header and header.FilterButton
	if filter and filter.HookScript and not filterHooked then
		filterHooked = true
		local function Replace()
			if button:IsShown() then PlaceTrackerButton(button, tracker) end
		end
		filter:HookScript("OnShow", Replace)
		filter:HookScript("OnHide", Replace)
	end
	if filter and filter.IsShown and filter:IsShown() then fold = filter end
	button:ClearAllPoints()
	if fold and fold.GetLeft then
		button:SetPoint("RIGHT", fold, "LEFT", -4, 0)
	elseif header and header.GetRight then
		button:SetPoint("RIGHT", header, "RIGHT", -4, 0)
	else
		button:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", 0, 0)
	end
end

function M:ApplyTracker()
	local collapsed = Store().tracker[E.charKey] and true or false
	local allowed = TrackerAllowed()
	SetTrackerCollapsed(allowed and collapsed)
	local tracker = Tracker()
	if allowed and self.db.trackerButton and tracker and not self.trackerButton then
		local button = FlatButton(UIParent, 18, 18, "")
		button:SetFrameStrata("MEDIUM")
		button.tip = L["Show or hide the quest tracker (/eui tracker)"]
		button:SetScript("OnClick", function(clicked, mouse)
			if E:IsOptionsLinkClick(clicked, mouse) then return end
			M:ToggleTracker()
		end)
		E:BindOptionsLink(button, { page = "module:QoL", key = "trackerButton" })
		self.trackerButton = button
	end
	local button = self.trackerButton
	if button then
		local shown = self.db.trackerButton and allowed and tracker and true or false
		if shown then PlaceTrackerButton(button, tracker) end
		button:SetShown(shown)
		button.text:SetText(collapsed and "+" or "-")
		-- The Quest Tracker's header lines end before the button.
		local owner = E:GetModule("ObjectiveTracker")
		if owner and owner.SetHeaderControl then owner:SetHeaderControl(shown and button or nil) end
	end
end

function M:ToggleTracker()
	local store = Store().tracker
	store[E.charKey] = not store[E.charKey] or nil
	self:ApplyTracker()
end

---------------------------------------------------------------------------
-- Quest log: a tick on each zone header tracks or untracks all its quests.
---------------------------------------------------------------------------
local zoneChecks = {} -- header button -> check button

local function ZoneQuests(headerIndex)
	local list = {}
	for index = headerIndex + 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(index)
		if not info or info.isHeader then break end
		if info.questID and not info.isHidden then list[#list + 1] = info.questID end
	end
	return list
end

local function AllWatched(quests)
	if #quests == 0 then return false end
	for _, questID in ipairs(quests) do
		if not C_QuestLog.GetQuestWatchType(questID) then return false end
	end
	return true
end

local function AttachZoneCheck(header, logIndex)
	if not header or not logIndex then return end
	local check = zoneChecks[header]
	if not check then
		check = CreateFrame("CheckButton", nil, header, "UICheckButtonTemplate")
		check:SetSize(20, 20)
		check:SetPoint("RIGHT", header, "RIGHT", -2, 0)
		if E.SkinCheckBox then E:SkinCheckBox(check) end
		check:SetScript("OnClick", function(self, mouse)
			-- Ctrl-click opens the setting instead: the box keeps its state.
			if E:IsOptionsLinkClick(self, mouse) then
				self:SetChecked(AllWatched(ZoneQuests(self.logIndex)))
				return
			end
			local quests = ZoneQuests(self.logIndex)
			local watch = self:GetChecked()
			for _, questID in ipairs(quests) do
				if watch then C_QuestLog.AddQuestWatch(questID) else C_QuestLog.RemoveQuestWatch(questID) end
			end
		end)
		check:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(L["Track every quest in this zone"])
			GameTooltip:Show()
		end)
		check:SetScript("OnLeave", GameTooltip_Hide)
		E:BindOptionsLink(check, { page = "module:QoL", key = "zoneTracking" })
		zoneChecks[header] = check
	end
	check.logIndex = logIndex
	check:SetChecked(AllWatched(ZoneQuests(logIndex)))
	check:SetShown(M.active and M.db.zoneTracking and E:BlizzardAllowed("world-map-quest-log", "improve") and true or false)
end

function M:UpdateZoneChecks()
	-- Modern quest log (world map side panel).
	local scroll = QuestScrollFrame
	local pool = scroll and scroll.headerFramePool
	if pool and pool.EnumerateActive then
		for header in pool:EnumerateActive() do AttachZoneCheck(header, header.questLogIndex) end
	end
	-- Classic quest log window.
	for index = 1, (_G.QUESTS_DISPLAYED or 0) do
		local title = _G["QuestLogTitle" .. index]
		if title and title:IsShown() then
			local logIndex = title:GetID()
			local info = logIndex and C_QuestLog.GetInfo(logIndex)
			if info and info.isHeader then
				AttachZoneCheck(title, logIndex)
			elseif zoneChecks[title] then
				zoneChecks[title]:Hide()
			end
		end
	end
end

function M:HookQuestLog()
	if self.questLogHooked then return end
	local hooked = false
	for _, name in ipairs({ "QuestLogQuests_Update", "QuestLog_Update" }) do
		if type(_G[name]) == "function" then
			hooksecurefunc(name, function()
				if M.active and E:BlizzardAllowed("world-map-quest-log", "improve") then
					M:UpdateZoneChecks()
				else
					for _, check in pairs(zoneChecks) do check:Hide() end
				end
			end)
			hooked = true
		end
	end
	self.questLogHooked = hooked
end

---------------------------------------------------------------------------
-- Flight timer: learns each route's duration from your own flights
-- and shows the flight as a route: a thin track from start to destination,
-- the stops on the way as ticks, a "you" marker moving along it, the time
-- left and the arrival time. It fades in at take-off and out on landing.
-- Where the stops sit on the track comes from the taxi map's own node
-- positions at take-off; nothing is shipped as a data table. A reload in
-- mid-air picks the flight up again (the start time is kept in the saved
-- variables until you land).
---------------------------------------------------------------------------
local flight -- { key, from, destination, known, stops, marks, started, startedAt }

local ROUTE_WIDTH, ROUTE_HEIGHT = 320, 40
local SAMPLE = { destination = "Ironforge", known = 24, stops = { "Thelsamar" }, marks = { 0.55 } }

local function CurrentNode()
	for index = 1, NumTaxiNodes() do
		if TaxiNodeGetType(index) == "CURRENT" then return TaxiNodeName(index) end
	end
end

local function Clock(seconds) return E:FormatDuration(seconds, "minutes", "round") end

-- The stops of the route to taxi node `index` and where each sits on the
-- way (0-1), from the node positions the taxi map gives. Even spacing when
-- the client gives no positions.
local function RouteStops(index)
	local hops = GetNumRoutes and GetNumRoutes(index) or 1
	if type(hops) ~= "number" or hops < 2 or not TaxiGetNodeSlot then return {}, {} end
	local lengths, total = {}, 0
	local stops = {}
	for hop = 1, hops do
		local src, dst = TaxiGetNodeSlot(index, hop, true), TaxiGetNodeSlot(index, hop, false)
		local x1, y1, x2, y2
		if src and dst and TaxiNodePosition then
			x1, y1 = TaxiNodePosition(src)
			x2, y2 = TaxiNodePosition(dst)
		end
		local length = 1
		if type(x1) == "number" and type(y1) == "number" and type(x2) == "number" and type(y2) == "number" then
			length = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
		end
		if length <= 0 then length = 1 end
		lengths[hop] = length
		total = total + length
		if hop < hops then stops[#stops + 1] = dst and TaxiNodeName(dst) or "?" end
	end
	local marks, run = {}, 0
	for hop = 1, hops - 1 do
		run = run + lengths[hop]
		marks[hop] = run / total
	end
	return stops, marks
end

-- One route display (the flight bar and the sample on the options page).
local function CreateRoute(parent, name)
	local route = CreateFrame("Frame", name, parent)
	route:SetSize(ROUTE_WIDTH, ROUTE_HEIGHT)
	route.title = E:CreateText(route, E.tokens.size.section, "LEFT")
	route.title:SetPoint("TOPLEFT", 8, -6)
	route.time = E:CreateText(route, E.tokens.size.label, "RIGHT")
	route.time:SetPoint("TOPRIGHT", -8, -6)
	route.track = route:CreateTexture(nil, "ARTWORK")
	route.track:SetPoint("LEFT", route, "BOTTOMLEFT", 10, 10)
	route.track:SetPoint("RIGHT", route, "BOTTOMRIGHT", -10, 10)
	route.track:SetHeight(2)
	route.track:SetColorTexture(unpack(E.tokens.track))
	route.fill = route:CreateTexture(nil, "ARTWORK", nil, 1)
	route.fill:SetPoint("LEFT", route.track, "LEFT")
	route.fill:SetHeight(2)
	route.next = E:CreateText(route, E.tokens.size.tiny, "RIGHT")
	route.next:SetPoint("BOTTOMRIGHT", route.track, "TOPRIGHT", 0, 4)
	route.next:SetTextColor(unpack(E.media.text.secondary))
	route.ends = {}
	for index, point in ipairs({ "LEFT", "RIGHT" }) do
		local dot = route:CreateTexture(nil, "OVERLAY")
		dot:SetSize(4, 8)
		dot:SetPoint("CENTER", route.track, point)
		route.ends[index] = dot
	end
	route.ticks = {}
	route.you = CreateFrame("Frame", nil, route)
	route.you:SetSize(8, 8)
	route.you:SetFrameLevel(route:GetFrameLevel() + 2)
	E:SetTemplate(route.you)
	return route
end

local function Tick(route, index)
	local tick = route.ticks[index]
	if not tick then
		tick = route:CreateTexture(nil, "OVERLAY")
		tick:SetSize(3, 7)
		route.ticks[index] = tick
	end
	return tick
end

-- Draw `data` ({ destination, known, stops, marks }) `elapsed` seconds in.
local GREY = { 0.8, 0.8, 0.82, 1 }

local function DrawRoute(route, data, elapsed)
	local db = M.db
	local r, g, b = unpack(E.media.accentColor)
	route.title:SetText(data.destination or "")
	route.fill:SetColorTexture(r, g, b, 0.9)
	route.you:SetBackdropColor(r, g, b, 1)
	local width = route.track:GetWidth()
	if not width or width <= 0 then width = route:GetWidth() - 20 end
	local known = data.known
	local progress = known and known > 0 and math.min(elapsed / known, 1) or 0
	route.fill:SetWidth(math.max(progress * width, 0.01))
	route.fill:SetShown(known ~= nil)
	route.you:ClearAllPoints()
	route.you:SetPoint("CENTER", route.track, "LEFT", progress * width, 0)
	route.you:SetShown(known ~= nil)
	for index, dot in ipairs(route.ends) do
		if (index == 1 and known) or progress >= 1 then dot:SetColorTexture(r, g, b, 1) else dot:SetColorTexture(unpack(GREY)) end
	end
	-- Stops: passed ones in the accent color; the next one named.
	local marks, stops = data.marks or {}, data.stops or {}
	local nextStop
	for index = 1, math.max(#marks, #route.ticks) do
		local tick = Tick(route, index)
		local mark = marks[index]
		if mark then
			tick:ClearAllPoints()
			tick:SetPoint("CENTER", route.track, "LEFT", mark * width, 0)
			if known and progress >= mark then
				tick:SetColorTexture(r, g, b, 1)
			else
				tick:SetColorTexture(unpack(GREY))
				nextStop = nextStop or stops[index]
			end
			tick:Show()
		else
			tick:Hide()
		end
	end
	route.next:SetText(db.flightStops and nextStop and L["Next: %s"]:format(nextStop) or "")
	if known then
		local left = math.max(known - elapsed, 0)
		local text = Clock(left)
		if db.flightArrival then
			text = ("%s  " .. E:TextHex("secondary") .. "%s|r"):format(text, E:FormatTime(time() + math.floor(left + 0.5)))
		end
		route.time:SetText(text)
	else
		route.time:SetText(Clock(elapsed) .. " " .. E:TextHex("secondary") .. L["(learning)"] .. "|r")
	end
end

local FLIGHT_REDRAW = 0.1

function M:CreateFlightBar()
	local bar = CreateRoute(UIParent, "EldoUI_FlightBar")
	bar:SetFrameStrata("MEDIUM")
	bar:Hide()
	E:SetPanelTemplate(bar, true)
	-- Redrawn ten times a second, not every frame (the clock shows
	-- seconds; the fill and the ticks move smoothly enough at that rate).
	bar:SetScript("OnUpdate", function(frame, elapsed)
		if not flight or not flight.started then return frame:Hide() end
		frame.sinceDraw = (frame.sinceDraw or FLIGHT_REDRAW) + (elapsed or 0)
		if frame.sinceDraw < FLIGHT_REDRAW then return end
		frame.sinceDraw = 0
		DrawRoute(frame, flight, GetTime() - flight.started)
	end)
	bar:HookScript("OnShow", function(frame) frame.sinceDraw = nil end)
	local previous = E.currentModule
	E.currentModule = self
	E:CreateMover(bar, "EldoUI_FlightBar", L["Flight Timer"], { "TOP", "UIParent", "TOP", 0, -120 }, { sample = { kind = "bar" } })
	E.currentModule = previous
	self.flightBar = bar
end

-- While the second info bar has a box of its own at the screen edge, the
-- flight timer takes the farming bar's spot: the two never show together,
-- and the layouts keep that spot clear of the second bar (Vanilla Original
-- puts the flight timer where the second bar goes).
E:RegisterLayoutSpotRule("EldoUI_FlightBar", function()
	local info = E.modules.InfoBar
	return info and info.Bar2HasBox and info:Bar2HasBox() and "EldoUI_FarmBar" or nil
end)

-- How long a flight takes for this character against normal flight speed.
-- The Legacy talent Frequent Flier makes flight-master flights 20 percent
-- faster, so a route takes 1 / 1.2 of its time. Learned times are kept at
-- normal speed and shown at the character's own.
local FREQUENT_FLIER = 1225490
function E:FlightTimeFactor()
	local known = C_SpellBook and C_SpellBook.IsSpellKnown
	if type(known) ~= "function" then return 1 end
	local ok, has = pcall(known, FREQUENT_FLIER)
	if ok and not E:IsSecret(has) and has == true then return 1 / 1.2 end
	return 1
end

-- Learned flight time in seconds for a route (node names as the taxi map
-- shows them) at this character's flight speed, or nil. Maps shows it on
-- the flight map's tooltips.
function M:GetFlightTime(from, to)
	if not from or not to then return nil end
	local base = Store().flights[from .. " > " .. to]
	return base and math.floor(base * E:FlightTimeFactor() + 0.5) or nil
end

-- The bar is one of Blizzard UI > Flight map's "Improve" extras; learning
-- goes on either way so the times are there when it is switched on.
-- A kept flight timer addon draws its own bar (Data/Competitors.lua).
local function FlightBarAllowed()
	return M.db.flightTimer and E:BlizzardAllowed("flight-map", "improve") and not E:StandsBack(M, "flightbar")
end

local function ShowBar(bar)
	if M.db.flightFade then
		E:SlideIn(bar, "UP")
	else
		bar:SetAlpha(1)
		bar:Show()
	end
end

local function HideBar(bar)
	if not bar:IsShown() then return end
	if M.db.flightFade then E:SlideOut(bar, "UP") else bar:Hide() end
end

function M:OnTakeTaxi(index)
	if not (self.active and (self.db.flightTimer or self.db.flightView)) then return end
	local from, to = CurrentNode(), TaxiNodeName(index)
	if not from or not to then return end
	local key = from .. " > " .. to
	local stops, marks = RouteStops(index)
	flight = { key = key, from = from, destination = to, known = self:GetFlightTime(from, to), factor = E:FlightTimeFactor(),
		stops = stops, marks = marks, chosenAt = GetTime() }
	self:WatchFlight()
end

-- Takeoff and landing are read from the taxi state itself, twice a second
-- while a flight is chosen or in the air: the control events can come
-- before the game's taxi state changes, and a landing missed that way
-- would never keep its time. A chosen flight that never takes off is
-- dropped after TAKEOFF_WAIT seconds.
local FLIGHT_WATCH = "QoL:flight"
local TAKEOFF_WAIT = 30
local function FlightWatch()
	if not flight then return E.Ticker:Unsubscribe(FLIGHT_WATCH) end
	local onTaxi = UnitOnTaxi("player") and true or false
	local started = flight.started ~= nil
	if onTaxi ~= started or (not started and GetTime() - (flight.chosenAt or 0) > TAKEOFF_WAIT) then M:UpdateFlight() end
end

function M:WatchFlight()
	if flight and self.active then
		if not E.Ticker:IsSubscribed(FLIGHT_WATCH) then E.Ticker:Subscribe(FLIGHT_WATCH, 0.5, FlightWatch, self) end
	else
		E.Ticker:Unsubscribe(FLIGHT_WATCH)
	end
end

-- The bar for the flight in `flight`, `flight.started` already set.
function M:ShowFlight()
	if not FlightBarAllowed() then return end
	if not self.flightBar then self:CreateFlightBar() end
	E:SetPanelTemplate(self.flightBar, true)
	self.flightBar:SetWidth(self.db.flightWidth or ROUTE_WIDTH)
	DrawRoute(self.flightBar, flight, GetTime() - flight.started)
	ShowBar(self.flightBar)
end

function M:UpdateFlight()
	local store = Store()
	if not flight and UnitOnTaxi("player") and type(store.activeFlight) == "table" then
		-- Reloaded in mid-air: pick the flight up where it is.
		local saved = store.activeFlight
		local since = time() - (tonumber(saved.startedAt) or time())
		if since >= 0 and since < (tonumber(saved.known) or 1800) + 300 then
			flight = { key = saved.key, from = saved.from, destination = saved.destination, known = saved.known,
				factor = tonumber(saved.factor) or 1, stops = saved.stops or {}, marks = saved.marks or {},
				started = GetTime() - since, startedAt = saved.startedAt, resumed = true }
			self:ShowFlight()
			self:WatchFlight()
			self:UpdateFlightView()
			return
		end
	end
	if not flight then
		if not UnitOnTaxi("player") then store.activeFlight = nil end
		self:WatchFlight()
		self:UpdateFlightView()
		return
	end
	if UnitOnTaxi("player") then
		if not flight.started then
			flight.started = GetTime()
			flight.startedAt = time()
			store.activeFlight = { key = flight.key, from = flight.from, destination = flight.destination, known = flight.known,
				factor = flight.factor, stops = flight.stops, marks = flight.marks, startedAt = flight.startedAt }
			self:ShowFlight()
		end
	elseif flight.started then
		-- Landed: remember the time of a full flight (not a resumed one, whose
		-- start is only known to the second), at normal flight speed.
		local duration = (GetTime() - flight.started) / (flight.factor or 1)
		if duration > 5 and not flight.resumed then
			local known = store.flights[flight.key]
			store.flights[flight.key] = known and math.floor((known + duration) / 2 + 0.5) or math.floor(duration + 0.5)
		end
		flight = nil
		store.activeFlight = nil
		if self.flightBar then HideBar(self.flightBar) end
	elseif GetTime() - (flight.chosenAt or GetTime()) > TAKEOFF_WAIT then
		-- Chosen but never taken off (the flight was canceled).
		flight = nil
	end
	self:WatchFlight()
	self:UpdateFlightView()
end

-- The flight in the air, for the flight view: { destination, known, stops,
-- marks, started, ... } or nil.
function M:CurrentFlight()
	return flight
end

-- The route display and its sample, shared with the flight view.
M.CreateRoute, M.DrawRoute, M.FlightSample = CreateRoute, DrawRoute, SAMPLE

-- Options page: a sample flight that loops, drawn by the same code.
local function FlightPreview()
	return { type = "preview", height = ROUTE_HEIGHT + 16,
		create = function(frame)
			if not frame then return end
			local route = CreateRoute(frame)
			route:SetPoint("CENTER")
			E:SetPanelTemplate(route, true)
			frame.route = route
			local start = GetTime()
			route:SetScript("OnUpdate", function(self)
				local elapsed = (GetTime() - start) % (SAMPLE.known + 3)
				DrawRoute(self, SAMPLE, math.min(elapsed, SAMPLE.known))
			end)
		end,
		update = function(frame)
			if frame and frame.route then frame.route:SetWidth(M.db.flightWidth or ROUTE_WIDTH) end
		end }
end

---------------------------------------------------------------------------
-- Sound and graphics
---------------------------------------------------------------------------
local muted = {}

function M:ApplySounds()
	for id in pairs(muted) do
		if UnmuteSoundFile then UnmuteSoundFile(id) end
		muted[id] = nil
	end
	if self.active and MuteSoundFile and Mine("mutesounds") then
		for id in (self.db.muteSounds or ""):gmatch("%d+") do
			id = tonumber(id)
			MuteSoundFile(id)
			muted[id] = true
		end
	end
	if self.active and self.db.silenceRestedEmotes and Mine("restedemotes") and IsResting() then
		SetCVarOwned("Sound_EnableEmoteSounds", 0)
	else
		RestoreCVar("Sound_EnableEmoteSounds")
	end
end

local HAZE_CVAR = "ffxGlow"

local function HazeWritable()
	local cvar = C_CVar
	if not (cvar and cvar.GetCVar and cvar.SetCVar) then return false end
	local value = E.PlainCall(cvar.GetCVar, HAZE_CVAR)
	if type(value) ~= "string" then return false end
	if not cvar.GetCVarInfo then return true end
	local info, _, _, _, locked, secure, readOnly = E.PlainCallAll(cvar.GetCVarInfo, HAZE_CVAR)
	return type(info) == "string" and locked == false and secure == false and readOnly == false
end

local function ApplyHaze()
	E:RunOutOfCombat(function()
		if not HazeWritable() then return end
		local owner = E.CVarOwner and E:CVarOwner(HAZE_CVAR)
		if M.active and M.db.noScreenEffects and M.db.noDrunkenHaze then
			if not owner or owner == CVAR_OWNER then
				E:SetCVar(HAZE_CVAR, 0, CVAR_OWNER, function(current) return tonumber(current) ~= nil end)
			end
		elseif owner == CVAR_OWNER then
			RestoreCVar(HAZE_CVAR)
		end
	end, "QoL:drunken-haze")
end

function M:ApplyGraphics()
	local db = self.db
	if self.active and db.noScreenEffects then
		SetCVarOwned("ffxDeath", 0)
		SetCVarOwned("ffxNether", 0)
	else
		RestoreCVar("ffxDeath")
		RestoreCVar("ffxNether")
	end
	ApplyHaze()
	if self.active and db.weather ~= "game" and Mine("weather") then SetCVarOwned("weatherDensity", db.weather) else RestoreCVar("weatherDensity") end
end

---------------------------------------------------------------------------
-- Volume panel (/eui volume): sliders for the game's own volume settings.
-- Every change goes through E:SetCVar, so "Blizzard default" puts the
-- volume back where it was before EldoUI first changed it.
---------------------------------------------------------------------------
local VOLUME_CHANNELS = {
	{ cvar = "Sound_MasterVolume", label = "Master" },
	{ cvar = "Sound_SFXVolume", label = "Effects", extra = true },
	{ cvar = "Sound_MusicVolume", label = "Music", extra = true },
	{ cvar = "Sound_AmbienceVolume", label = "Ambience", extra = true },
	{ cvar = "Sound_DialogVolume", label = "Dialog", extra = true },
}

local function VolumeSlider(parent, channel)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(220, 20)
	row.label = E:CreateText(row, E.tokens.size.label, "LEFT")
	row.label:SetPoint("LEFT", 0, 0)
	row.label:SetWidth(60)
	row.label:SetText(L[channel.label])
	row.value = E:CreateText(row, E.tokens.size.label, "RIGHT")
	row.value:SetPoint("RIGHT", 0, 0)
	row.value:SetWidth(36)
	-- The kit's slider (flat track, accent fill and thumb); a drag or the
	-- wheel sets the CVar, the panel's own refresh does not.
	local slider = E.UIKit.Slider(row, { min = 0, max = 1, step = 0.05,
		onChange = function(value) SetCVarOwned(channel.cvar, ("%.2f"):format(value)) end })
	slider:ClearAllPoints()
	slider:SetPoint("LEFT", row.label, "RIGHT", 4, 0)
	slider:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
	slider:HookScript("OnValueChanged", function(_, value)
		row.value:SetText(("%d%%"):format(math.floor(value * 100 + 0.5)))
	end)
	row.slider = slider
	row.channel = channel
	return row
end

function M:CreateVolumePanel()
	local panel = CreateFrame("Frame", "EldoUI_Volume", UIParent)
	panel:SetFrameStrata("MEDIUM")
	panel:Hide()
	panel.title = E.UIKit.Text(panel, E.tokens.size.body, "LEFT", "header")
	panel.title:SetPoint("TOPLEFT", 8, -7)
	panel.title:SetText(L["Volume"])
	panel.close = E.UIKit.IconButton(panel, 16, "cross", function() M:ToggleVolume(false) end, L["Close (/eui volume)"])
	panel.close:SetPoint("TOPRIGHT", -5, -5)
	panel.rows = {}
	for index, channel in ipairs(VOLUME_CHANNELS) do
		panel.rows[index] = VolumeSlider(panel, channel)
	end
	local previous = E.currentModule
	E.currentModule = self
	E:CreateMover(panel, "EldoUI_Volume", L["Volume"], { "TOPRIGHT", "UIParent", "TOPRIGHT", -15, -300 }, { sample = false })
	E.currentModule = previous
	self.volumePanel = panel
end

function M:UpdateVolumePanel()
	local panel = self.volumePanel
	if not panel then return end
	E:SetPanelTemplate(panel)
	local y, shown = -26, 0
	for _, row in ipairs(panel.rows) do
		local visible = CVarExists(row.channel.cvar) and (not row.channel.extra or self.db.volumeChannels)
		row:SetShown(visible and true or false)
		if visible then
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 8, y)
			y = y - 22
			shown = shown + 1
			row.slider:SetQuiet(tonumber(C_CVar.GetCVar(row.channel.cvar)) or 0)
		end
	end
	panel:SetSize(236, 30 + shown * 22)
end

function M:ToggleVolume(show)
	if not self.volumePanel then self:CreateVolumePanel() end
	if show == nil then show = not self.volumePanel:IsShown() end
	self:UpdateVolumePanel()
	if show then E:SlideIn(self.volumePanel, "UP") else self.volumePanel:Hide() end
end

-- The "Show the volume panel" switch shows the panel when it turns on and
-- hides it when it turns off. In between, the X and /eui volume decide, so
-- an unrelated setting change never brings a closed panel back.
function M:ApplyVolume()
	local wanted = self.active and self.db.volumePanel and Mine("volume") and true or false
	if wanted and not self.volumeWanted then
		self:ToggleVolume(true)
	elseif self.volumePanel then
		if not self.active or (self.volumeWanted and not wanted) then self.volumePanel:Hide() end
		self:UpdateVolumePanel()
	end
	self.volumeWanted = wanted
end

---------------------------------------------------------------------------
-- Wowhead links: Ctrl+Alt-click a chat link, or /eui wowhead while a
-- tooltip shows (bind a key to a "/eui wowhead" macro to use it on hover).
-- The address opens in a copy box; nothing leaves the game by itself.
---------------------------------------------------------------------------
local WOWHEAD_SITES = { classic = "https://www.wowhead.com/classic/", retail = "https://www.wowhead.com/" }
-- Wowhead's own languages: a path after the site ("classic/de/item=..."),
-- none for English. "auto" takes the game's language, so the page names
-- things the way the game does; a language Wowhead has no page for
-- (zhTW, and English) gets the English page.
local WOWHEAD_LANGUAGES = { de = true, es = true, fr = true, it = true, pt = true, ru = true, ko = true, cn = true }
local WOWHEAD_CLIENT = { deDE = "de", esES = "es", esMX = "es", frFR = "fr", itIT = "it", ptBR = "pt", ptPT = "pt",
	ruRU = "ru", koKR = "ko", zhCN = "cn" }

local function WowheadLanguage(choice)
	if choice == nil or choice == "auto" then
		local client = type(GetLocale) == "function" and GetLocale() or nil
		choice = WOWHEAD_CLIENT[client]
	end
	return WOWHEAD_LANGUAGES[choice] and choice or nil
end

local function WowheadURL(kind, id)
	local language = WowheadLanguage(M.db.wowheadLanguage)
	return (WOWHEAD_SITES[M.db.wowheadSite] or WOWHEAD_SITES.classic) .. (language and (language .. "/") or "") .. kind .. "=" .. id
end
M.WowheadURL = WowheadURL -- tools/qol/test_wowhead.lua

local LINK_KINDS = { item = "item", quest = "quest", spell = "spell", enchant = "spell", achievement = "achievement",
	currency = "currency", npc = "npc", mount = "spell" }

local function ShowWowhead(kind, id, name)
	kind = LINK_KINDS[kind]
	id = tonumber(id)
	if not kind or not id then return false end
	local url = WowheadURL(kind, id)
	E:ShowCopyBox("Wowhead", L["%s: press Ctrl+C, then paste it in your browser."]:format(name or (kind .. " " .. id)), url) -- no-L: "Wowhead" is a site name
	return true
end
M.ShowWowhead = ShowWowhead -- the Loot Guide item menu's "Copy Wowhead link"

local function NpcFromGUID(guid)
	if Secret(guid) or not guid then return nil end
	local unitType, _, _, _, _, npcID = strsplit("-", guid)
	if unitType == "Creature" or unitType == "Vehicle" then return tonumber(npcID) end
end

local function FromTooltip()
	local tip = GameTooltip
	if not (tip and tip:IsShown()) then return end
	local types = Enum and Enum.TooltipDataType
	local data = tip.GetPrimaryTooltipData and tip:GetPrimaryTooltipData()
	if data and types and not Secret(data.type) and not Secret(data.id) then
		local map = { [types.Item or -1] = "item", [types.Spell or -1] = "spell", [types.Quest or -1] = "quest",
			[types.Achievement or -1] = "achievement", [types.Currency or -1] = "currency", [types.Mount or -1] = "spell" }
		if data.type == types.Unit then
			local npc = NpcFromGUID(data.guid)
			if npc then return "npc", npc end
		elseif map[data.type] and data.id then
			return map[data.type], data.id
		end
	end
	local _, link = tip:GetItem()
	if not Secret(link) and link then
		local id = link:match("item:(%d+)")
		if id then return "item", id end
	end
	local _, spellID = tip:GetSpell()
	if not Secret(spellID) and spellID then return "spell", spellID end
	local _, unit = tip:GetUnit()
	if unit then
		local npc = NpcFromGUID(UnitGUID(unit))
		if npc then return "npc", npc end
	end
end

function M:WowheadLookup()
	local kind, id = FromTooltip()
	if not kind and UnitExists("target") and not UnitIsPlayer("target") then
		kind, id = "npc", NpcFromGUID(UnitGUID("target"))
	end
	if not (kind and ShowWowhead(kind, id)) then
		self:Print(L["Hover an item, spell, quest or creature (or target a creature), then type /eui wowhead. Ctrl+Alt-click works on chat links."])
	end
end

local function OnItemRef(link)
	if not (M.active and M.db.wowheadLinks and Mine("wowhead") and IsControlKeyDown() and IsAltKeyDown()) then return end
	if type(link) ~= "string" or Secret(link) then return end
	local kind, id = link:match("^(%a+):(%d+)")
	ShowWowhead(kind, id)
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
local EVENTS = {
	CONFIRM_SUMMON = function() M:OnSummon() end,
	RESURRECT_REQUEST = function(_, _, offerer) M:OnResurrect(offerer) end,
	-- Revived (any way), released, or died again: an open resurrection
	-- prompt is stale.
	PLAYER_ALIVE = function() M:HidePrompt("res") end,
	PLAYER_UNGHOST = function() M:HidePrompt("res") end,
	PLAYER_DEAD = function() M:HidePrompt("res") end,
	DUEL_REQUESTED = function(_, _, name) M:OnDuel(name) end,
	PARTY_INVITE_REQUEST = function(_, _, name) M:OnPartyInvite(name) end,
	GROUP_INVITE_CONFIRMATION = function() C_Timer.After(0, function() M:OnInviteConfirmation() end) end,
	GUILD_INVITE_REQUEST = function(_, _, name, guild) M:OnGuildInvite(name, guild) end,
	QUEST_DETAIL = function() M:OnQuestDetail() end,
	PLAYER_UPDATE_RESTING = function() M:ApplySounds() end,
	VOICE_CHAT_OUTPUT_DEVICES_UPDATED = function()
		if M.db.keepAudioSynced and Mine("audiosync") and Sound_GameSystem_RestartSoundSystem then Sound_GameSystem_RestartSoundSystem() end
	end,
	CVAR_UPDATE = function(_, _, name)
		if M.volumePanel and M.volumePanel:IsShown() and type(name) == "string" and name:find("^Sound_") then M:UpdateVolumePanel() end
	end,
	PLAYER_CONTROL_LOST = function() C_Timer.After(0.5, function() M:UpdateFlight() end) end,
	PLAYER_CONTROL_GAINED = function() C_Timer.After(0.5, function() M:UpdateFlight() end) end,
	PLAYER_ENTERING_WORLD = function() M:ApplyTracker(); M:UpdateFlight() end,
}

-- The other files of the page (Modules/QoL/*.lua) join the module's life
-- cycle as parts instead of wrapping its functions:
--   M:AddPart(name, { enable, disable, profile, restore })
-- enable and disable run after the module's own, in the order the parts
-- were added; profile runs only while the module is on; restore runs from
-- "Restore game settings". One part that errors does not stop the others.
local parts = {}

function M:AddPart(name, hooks)
	hooks.name = name
	parts[#parts + 1] = hooks
end

function M:RunParts(step)
	for _, part in ipairs(parts) do
		local fn = part[step]
		if fn then
			local ok, err = pcall(fn, self)
			if not ok then geterrorhandler()(err) end
		end
	end
end

-- Chat filters: added while the module is on, taken off when it goes off.
local CHAT_FILTER_EVENTS = { "CHAT_MSG_SYSTEM", "CHAT_MSG_TEXT_EMOTE" }
local filtersAdded = false

local function SetChatFilters(on)
	if on == filtersAdded then return end
	local util = ChatFrameUtil
	local add = util and util.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
	local remove = util and util.RemoveMessageEventFilter or ChatFrame_RemoveMessageEventFilter
	local fn = on and add or remove
	if type(fn) ~= "function" then return end
	for _, event in ipairs(CHAT_FILTER_EVENTS) do fn(event, SystemFilter) end
	filtersAdded = on
end

local function Inactive()
	if M.active then return false end
	E:Print(E:ModuleOffHint("QoL"))
	return true
end

function M:OnInitialize()
	self:MigrateMoved()
	self:FillMinimalStyle()
	E:AddCommand("tracker", "on | off | toggle  show or hide the quest tracker", function(arg)
		if Inactive() then return end
		if not TrackerAllowed() then
			E:Print(L["Turn on Blizzard UI > Objective / quest tracker > Improve to fold the tracker from EldoUI."])
			return
		end
		local word = arg and arg:lower():match("^%s*(%a+)")
		local store = Store().tracker
		if word == "on" or word == "show" then store[E.charKey] = nil
		elseif word == "off" or word == "hide" then store[E.charKey] = true
		elseif not word or word == "toggle" then store[E.charKey] = not store[E.charKey] or nil
		else
			E:Print(L["Usage: /eui tracker on | off | toggle"])
			return
		end
		M:ApplyTracker()
	end, "Layout & frames")
	E:AddCommand("volume", "show or hide the volume panel", function()
		if Inactive() then return end
		M:ToggleVolume()
	end, "Tools")
	E:AddCommand("wowhead", "Wowhead address for what the tooltip shows (or your target)", function()
		if Inactive() then return end
		M:WowheadLookup()
	end, "Tools")
end

function M:OnEnable()
	for event, handler in pairs(EVENTS) do self:RegisterEvent(event, handler) end
	-- Created hidden now, so move mode and the layouts can place them from
	-- login (and the movers carry the module).
	if not self.prompt then self:CreatePrompt() end
	if not self.flightBar then self:CreateFlightBar() end
	-- A hook can't be taken off again, so each one is added once and does
	-- nothing while the module is off (OnTakeTaxi and OnItemRef check it).
	if not self.hooked then
		BuildPatterns()
		if TakeTaxiNode then
			hooksecurefunc("TakeTaxiNode", function(index) M:OnTakeTaxi(index) end)
		end
		if type(SetItemRef) == "function" then hooksecurefunc("SetItemRef", OnItemRef) end
		self.hooked = true
	end
	SetChatFilters(true)
	self:HookQuestLog()
	self:ApplyLook()
	self:ApplyTracker()
	self:ApplySounds()
	self:ApplyGraphics()
	self:ApplyVolume()
	self:EnableFlightView()
	self:UpdateFlight()
	self:RunParts("enable")
end

function M:OnDisable()
	for event in pairs(EVENTS) do self:UnregisterEvent(event) end
	E.Ticker:Unsubscribe(FLIGHT_WATCH)
	SetChatFilters(false)
	self:ApplyLook()
	self:ApplyTracker()
	if self.trackerButton then self.trackerButton:Hide() end
	for _, check in pairs(zoneChecks) do check:Hide() end
	if self.flightBar then self.flightBar:Hide() end
	self:DisableFlightView()
	self:HidePrompt()
	self:ApplySounds()
	self:ApplyGraphics()
	self:ApplyVolume()
	self:RunParts("disable")
end

function M:OnProfileChanged()
	self:MigrateMoved()
	if not self.active then return end
	self:ApplyLook()
	self:ApplyTracker()
	self:ApplySounds()
	self:ApplyGraphics()
	self:ApplyVolume()
	if not E:BlizzardAllowed("world-map-quest-log", "improve") then
		for _, check in pairs(zoneChecks) do check:Hide() end
	end
	if self.flightBar then
		self.flightBar:SetWidth(self.db.flightWidth or 320)
		if self.flightBar:IsShown() and not FlightBarAllowed() then self.flightBar:Hide() end
	end
	self:RefreshFlightView()
	self:RunParts("profile")
end

-- A warning line that shows while a switch the rows below need is off.
local function Needs(id, action)
	return { type = "description", tone = "warning", label = function() return E:BlizzardNeedsReason(id, action) or "" end,
		hidden = function() return E:BlizzardAllowed(id, action) end }
end

-- The page: these tabs in this order. This file and Modules/QoL/*.lua add
-- their sections with M:AddOptions(tab, rows); the page is put together
-- when it first opens.
local TABS = { "Interface", "Social", "Quests", "Travel", E.Key("Sound and misc") }
local tabRows = {}
for _, tab in ipairs(TABS) do tabRows[tab] = {} end

-- The page as one table, laid out again each time a section is added.
M.options = {}
local tabHeaders = {}

function M:AddOptions(tab, rows)
	local list = assert(tabRows[tab], "QoL: unknown tab")
	for _, row in ipairs(rows) do list[#list + 1] = row end
	local options = self.options
	wipe(options)
	for _, name in ipairs(TABS) do
		if #tabRows[name] > 0 then
			tabHeaders[name] = tabHeaders[name] or { type = "tab", label = name }
			options[#options + 1] = tabHeaders[name]
			for _, row in ipairs(tabRows[name]) do options[#options + 1] = row end
		end
	end
end

-- Every switch of the page in one list, in page order: { key, label, tab,
-- acts (does something for the player), default }. Setup and UI amount
-- screens read it to show the optional comforts; a look, layout or style
-- never switches one of them on by itself.
function M:OptionalCatalog()
	local list = {}
	for _, name in ipairs(TABS) do
		for _, row in ipairs(tabRows[name]) do
			if row.type == "toggle" and type(row.key) == "string" then
				list[#list + 1] = { key = row.key, label = row.label, tab = name, acts = row.acts and true or false,
					default = self.defaults[row.key] }
			end
		end
	end
	return list
end

M:AddOptions("Interface", {
	{ type = "header", label = "Wowhead" },
	{ type = "toggle", key = "wowheadLinks", disabled = HandledBy("wowhead"), label = "Ctrl+Alt-click a link", desc = "Ctrl+Alt-click an item, quest, spell or achievement link in chat for its Wowhead address in a copy box." },
	{ type = "select", key = "wowheadSite", label = "Wowhead site", desc = "Which Wowhead the address points to. /eui wowhead (or a macro with it on a key) works on whatever the tooltip shows.",
		values = { classic = "Classic", retail = "Retail" } },
	{ type = "select", key = "wowheadLanguage", label = "Wowhead language", desc = "The language of the Wowhead page. Game language follows your game client, so the page names items, quests and creatures the way the game does.",
		values = { auto = "Game language", en = "English", de = "Deutsch", fr = "Français", es = "Español", it = "Italiano",
			pt = "Português", ru = "Русский", ko = "한국어", cn = "简体中文" }, -- each language in its own name
		order = { "auto", "en", "de", "fr", "es", "it", "pt", "ru", "ko", "cn" } },
	{ type = "header", label = "Screen" },
	{ type = "toggle", key = "xpBarText", label = "XP bar text always visible", desc = "Shows the numbers on the experience bar without hovering (game setting; off puts your own value back)." },
})

M:AddOptions("Social", {
	{ type = "header", label = "Summons and resurrections" },
	{ type = "toggle", key = "summonPrompt", label = "Summon prompt",
		desc = "A clear EldoUI prompt with who, where and a countdown. You still click Accept; nothing is accepted for you." },
	{ type = "toggle", key = "resPrompt", label = "Resurrection prompt", desc = "The same prompt for resurrections. You still click Accept." },
	{ type = "media", key = "promptSound", label = "Prompt sound", mediaKind = "sound", none = true,
		desc = "The sound when a summon or resurrection prompt appears. None for silence.", hidden = function() return not (M.db.summonPrompt or M.db.resPrompt) end },
	{ type = "toggle", key = "promptFlash", label = "Flash the taskbar", desc = "Flashes the game in the taskbar when a prompt appears, so you notice it while tabbed out.",
		hidden = function() return not (M.db.summonPrompt or M.db.resPrompt) end },
	{ type = "execute", label = "Test prompt", desc = "Shows the prompt for 15 seconds with test text, so you can see it and place it (/eui move: \"Summon and Resurrection Prompt\"). Its buttons only close it.",
		func = function() if M.active then M:TestPrompt() end end, hidden = function() return not (M.db.summonPrompt or M.db.resPrompt) end },
	{ type = "header", label = "Blocks (out of combat, friends exempt)" },
	{ type = "description", label = "These decline a popup for you, so they are off by default. Friends (and, if you like, guild members) are never blocked." },
	{ type = "toggle", acts = true, key = "blockDuels", disabled = HandledBy("duels"), label = "Decline duels", desc = "Duel requests from people who aren't friends are declined. Off by default." },
	{ type = "toggle", acts = true, key = "blockInvites", disabled = HandledBy("invites"), label = "Decline group invites from strangers", desc = "Group invites from people who aren't friends are declined. Off by default." },
	{ type = "toggle", acts = true, key = "blockRequestedInvites", disabled = HandledBy("invites"), label = "Decline requests to join your group",
		desc = "When someone who isn't a friend asks to join your group, the request is declined. Suggestions from your group members still ask you. Off by default." },
	{ type = "toggle", acts = true, key = "blockGuildInvites", label = "Decline guild invites", desc = "Guild invites from anyone but your friends are declined. Off by default." },
	{ type = "toggle", acts = true, key = "blockSharedQuests", disabled = HandledBy("sharedquests"), label = "Decline quests shared by strangers", desc = "Quests shared by people who aren't friends are declined. Off by default." },
	{ type = "toggle", key = "guildAreFriends", label = "Treat guild members as friends", desc = "Guild members are exempt from the blocks above." },
	{ type = "toggle", key = "announceBlocks", label = "Say in chat what was declined", desc = "One line per declined request, so nothing disappears silently." },
	{ type = "header", label = "Chat" },
	{ type = "toggle", key = "filterDuelSpam", label = "Hide duel results", desc = "Hides \"X has defeated Y in a duel\" system messages." },
	{ type = "toggle", key = "filterDrunkSpam", label = "Hide drunken messages", desc = "Hides other players' \"X seems a little tipsy\" messages." },
})

-- The blocks act for the player: listed for the setup's Convenience step and
-- the Conveniences page (Core/Conveniences.lua), off until ticked and never
-- recommended (whether to decline strangers is the player's call).
E:RegisterConvenience({ id = "blockDuels", module = "QoL", setting = "blockDuels", order = 90,
	label = "Decline duels",
	desc = "Acts for you: declines duel requests from people who aren't your friends, out of combat.",
	blocked = HandledBy("duels") })
E:RegisterConvenience({ id = "blockInvites", module = "QoL", setting = "blockInvites", order = 100,
	label = "Decline group invites from strangers",
	desc = "Acts for you: declines group invites from people who aren't your friends, out of combat.",
	blocked = HandledBy("invites") })
E:RegisterConvenience({ id = "blockRequestedInvites", module = "QoL", setting = "blockRequestedInvites", order = 110,
	label = "Decline requests to join your group",
	desc = "Acts for you: declines requests to join your group from people who aren't your friends, out of combat.",
	blocked = HandledBy("invites") })
E:RegisterConvenience({ id = "blockGuildInvites", module = "QoL", setting = "blockGuildInvites", order = 120,
	label = "Decline guild invites",
	desc = "Acts for you: declines guild invites from anyone but your friends, out of combat." })
E:RegisterConvenience({ id = "blockSharedQuests", module = "QoL", setting = "blockSharedQuests", order = 130,
	label = "Decline quests shared by strangers",
	desc = "Acts for you: declines quests shared by people who aren't your friends, out of combat.",
	blocked = HandledBy("sharedquests") })

M:AddOptions("Quests", {
	{ type = "header", label = "Quest tracker and log" },
	{ type = "toggle", key = "trackerButton", label = "Quest tracker button", disabled = E:BlizzardNeeds("objective-tracker", "improve"),
		desc = "A small +/- button on the quest tracker's top row to fold it away; /eui tracker does the same. Remembered per character." },
	{ type = "toggle", key = "zoneTracking", label = "Track a whole zone in the quest log", disabled = E:BlizzardNeeds("world-map-quest-log", "improve"),
		desc = "A tick on each zone header tracks or untracks every quest in that zone." },
})

M:AddOptions("Travel", {
	FlightPreview(),
	{ type = "header", label = "Flight timer" },
	{ type = "toggle", key = "flightTimer", label = "Learn and show flight times", desc = "Learns how long each route takes from your own flights. While you fly, the route shows with its stops, the time left and the arrival time; Maps shows the times on the flight map." },
	Needs("flight-map", "improve"),
	{ type = "toggle", key = "flightFade", label = "Fade in and out", desc = "The route fades in at take-off and out on landing. Off shows and hides it at once.", dependsOn = "flightTimer" },
	{ type = "toggle", key = "flightArrival", label = "Arrival time", desc = "The clock time you land, after the time left.", dependsOn = "flightTimer" },
	{ type = "toggle", key = "flightStops", label = "Next stop", desc = "The name of the next stop on the way, above the track.", dependsOn = "flightTimer" },
	{ type = "range", unit = "px", key = "flightWidth", label = "Width", desc = "Width of the route in pixels. Move it with /eui move (\"Flight Timer\").", min = 200, max = 600, step = 10, dependsOn = "flightTimer" },
	{ type = "description", label = "A new route shows the time so far with \"learning\"; the next flight on it shows the full time. Times come from your flights only." },
})

M:AddOptions(E.Key("Sound and misc"), {
	{ type = "header", label = "Volume" },
	{ type = "toggle", key = "volumePanel", disabled = HandledBy("volume"), label = "Show the volume panel", desc = "A small panel with a master volume slider (mouse wheel works too). /eui volume shows or hides it; move it with /eui move." },
	{ type = "toggle", key = "volumeChannels", label = "All channels", desc = "Also sliders for effects, music, ambience and dialog." },
	{ type = "execute", label = "Show volume panel", desc = "Shows or hides the panel now (/eui volume).", func = function() if M.active then M:ToggleVolume() end end },
	{ type = "header", label = "Sound" },
	{ type = "toggle", key = "silenceRestedEmotes", disabled = HandledBy("restedemotes"), label = "Silence emotes while resting", desc = "Turns off emote sounds in inns and cities (game setting; your own value comes back outside)." },
	{ type = "toggle", key = "keepAudioSynced", disabled = HandledBy("audiosync"), label = "Follow a new audio device", desc = "Restarts the game's sound when Windows switches the output device (headset plugged in)." },
	{ type = "input", key = "muteSounds", disabled = HandledBy("mutesounds"), label = "Mute sound file IDs", desc = "Sound file IDs separated by commas. They stay muted while this module is on." },
	{ type = "header", label = "Graphics" },
	{ type = "toggle", key = "noScreenEffects", label = "Disable screen effects", desc = "Turns off the gray screen while dead, the nether effect, and drunken haze. Off puts your own game settings back.",
		cog = { { type = "toggle", key = "noDrunkenHaze", label = "Suppress drunken haze", dependsOn = "noScreenEffects",
			desc = "Also turns off the game's full-screen glow setting. On by default when Disable screen effects is on.",
			disabled = function() return not HazeWritable() end } } },
	{ type = "select", key = "weather", disabled = HandledBy("weather"), label = "Weather density", desc = "How thick rain and snow are. \"Game setting\" puts your own value back.",
		values = { game = "Game setting", ["0"] = "Off", ["1"] = "Low", ["2"] = "Medium", ["3"] = "High" } },
})

-- Style presets of the whole page, the former Tweaks parts included
-- (registered here; Modules/QoL/Tweaks.lua defines those settings).
E:RegisterStyles("QoL", {
	{ mode = true, key = "Default", title = "Default", desc = "Prompts and reward values on; no blocks, no quest helpers; game, sound and graphics settings left alone.",
		settings = { summonPrompt = true, resPrompt = true, promptSound = "kit:READY_CHECK", promptFlash = true, blockDuels = false, blockInvites = false, blockRequestedInvites = false,
			blockGuildInvites = false, blockSharedQuests = false, filterDuelSpam = false, filterDrunkSpam = false, noScreenEffects = false, weather = "game",
			autoAccept = false, autoTurnIn = false, skipGossip = false, rewardValue = true, combatAlert = false, setMaxZoom = false, setScreenshots = false,
			edgeTop = false, edgeBottom = false } },
	{ acts = true, mode = true, key = "Quiet", title = "Quiet", desc = "Acts for you. Strangers' duels, invites, join requests and shared quests declined; duel and drunk spam hidden.",
		settings = { blockDuels = true, blockInvites = true, blockRequestedInvites = true, blockSharedQuests = true, guildAreFriends = true,
			announceBlocks = true, filterDuelSpam = true, filterDrunkSpam = true, silenceRestedEmotes = true } },
	{ mode = true, key = "Questing", title = "Questing", desc = "XP numbers always shown, reward values, tracker button, zone tracking and flight timer. Quests stay yours to accept.",
		settings = { xpBarText = true, rewardValue = true, trackerButton = true, zoneTracking = true, flightTimer = true } },
	{ acts = true, mode = true, key = "FastQuesting", title = "Fast questing", desc = "Acts for you. Accept and turn in quests (never picks a reward) and skip plain vendor chat. Hold Shift to pause.",
		settings = { autoAccept = true, autoTurnIn = true, skipGossip = true, pauseKey = "SHIFT", rewardValue = true } },
	{ mode = true, key = "Clean", title = "Clean screen", desc = "Fewer screen effects, light weather, and combat alerts.",
		settings = { noScreenEffects = true, weather = "1", combatAlert = true } },
	{ key = "Framed", title = "Framed screen", desc = "Thin see-through panels across the top and bottom edge with an accent line, and the volume panel.",
		settings = { edgeTop = true, edgeBottom = true, edgeHeight = 22, edgeTransparent = true, edgeAccent = true, volumePanel = true } },
	{ mode = true, key = "Minimal", title = "Minimal", desc = "Only the summon and resurrection prompts; everything else as Blizzard made it.",
		settings = { summonPrompt = true, resPrompt = true, trackerButton = false, zoneTracking = false, flightTimer = false,
			volumePanel = false, wowheadLinks = false, filterDuelSpam = false, filterDrunkSpam = false,
			autoAccept = false, autoTurnIn = false, skipGossip = false, rewardValue = false, combatAlert = false, setMaxZoom = false, setScreenshots = false,
			edgeTop = false, edgeBottom = false } },
})

-- Minimal promises "everything else as Blizzard made it", from any earlier
-- state: every switch of the page goes back to its default (blocks and
-- helpers off), every game setting to "Game setting" and the muted sounds
-- list is emptied. Tuned numbers and choices (flight bar width, zoom
-- distance, prompt sound ...) stay for when their switch goes on again.
-- Filled once every part of the page has added its defaults.
function M:FillMinimalStyle()
	for _, style in ipairs(E.styles.QoL or {}) do
		if style.key == "Minimal" then
			for key, value in pairs(self.defaults) do
				local reset = type(value) == "boolean" or value == "game" or key == "muteSounds"
				-- Page view choices (the CVar list filters) stay.
				if reset and style.settings[key] == nil and key ~= "enabled" and not key:find("^cvar") then
					style.settings[key] = value
				end
			end
		end
	end
end
