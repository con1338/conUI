-- EldoUI Raid Tools: a small movable bar for group leaders and assists:
-- ready check, role check, pull countdown, world markers
-- and raid target icons.
--
-- Every button is a plain click by the player. Ready check, role check and
-- the countdown call Blizzard's own functions (C_PartyInfo.DoReadyCheck,
-- InitiateRolePoll, C_PartyInfo.DoCountdown). World markers and target
-- icons are SecureActionButtons ("worldmarker" and "raidtarget" actions), so
-- they work in combat too. Nothing happens on its own.
--
-- A third row manages the group: convert party/raid, "everyone is
-- assistant", main tank and main assist on your target, Blizzard's raid
-- panel and leave group. Each is one click and one game call: convert and
-- assistants through C_PartyInfo, main tank / main assist as secure macro
-- buttons running Blizzard's own /mt, /ma commands (only out of combat),
-- the raid panel through ToggleRaidFrame, leave group after a confirmation.
-- "Reset" (off by default) calls ResetInstances on the leader's
-- click, the same as the portrait menu's "Reset all instances"; with the
-- Instances module's "Announce reset" on, a right-click sends the last
-- reset to the group (one line per click).
-- There is no "disband": that would remove every member from one click,
-- so the player uses leave group or Blizzard's raid panel instead.
--
-- The bar holds protected buttons, so it is built, laid out and shown or
-- hidden out of combat; in combat a state driver handles [group] and the
-- shared visibility rules (db.fade); a rule that fades to a visible
-- opacity only changes the alpha.
local _, E = ...
local L = E.L

local M = E:NewModule("RaidTools", {
	title = "Raid Tools",
	desc = "A bar with ready check, role check, pull countdown, world markers, target icons and group tools for leaders and assists.",
	category = "Group",
	frames = { "EldoUI_RaidToolsBar", "EldoUI_RaidToolsHolder" },
	movers = { "EldoUI_RaidTools" },
	savedKeys = { "profile.modules.RaidTools" },
	optionsPage = "module:RaidTools",
	presets = { "Column", "Compact", "Leader", "Markers", "Minimal" },
	reload = false,
	defaults = {
		visibility = "LEAD",      -- "ALWAYS", "GROUP", "RAID" or "LEAD" (in a group as leader or assist)
		fade = E:VisibilityDefaults(), -- the shared visibility rules
		orientation = "HORIZONTAL",
		buttonSize = 22,
		fontSize = 0,             -- text on the buttons; 0 follows the button size
		spacing = 2,
		backdrop = true,
		alpha = 1,
		readyCheck = true,
		rolePoll = true,
		countdown = true,
		countdownSeconds = 10,
		worldMarkers = true,
		clearMarkers = true,
		raidTargets = false,      -- second row: target icons on your target
		-- Third row: group management, each off until ticked.
		convertGroup = false,
		everyoneAssist = false,
		mainTank = false,
		mainAssist = false,
		raidPanel = false,
		leaveGroup = false,
		resetInstances = false,   -- ResetInstances on your click
		tooltips = true,
	},
})
E:RegisterVisibilityFacet("EldoUI_RaidTools", "rules", { module = "RaidTools", setting = "fade" })

-- World marker slots in Blizzard's order (skull first), with the raid
-- icon that matches each marker's color and shape.
local MARKER_ORDER = WORLD_RAID_MARKER_ORDER or { 8, 4, 1, 7, 2, 3, 6, 5 }
local MARKER_ICON = { [1] = 6, [2] = 4, [3] = 3, [4] = 7, [5] = 1, [6] = 2, [7] = 5, [8] = 8 }
local TARGET_ORDER = { 8, 7, 2, 1, 3, 4, 5, 6 }
local ICON_PATH = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"

local function MaxCountdown()
	return (Constants and Constants.PartyCountdownConstants and Constants.PartyCountdownConstants.MaxCountdownSeconds) or 3600
end

local function IsLead()
	if not IsInGroup() then return false end
	if not IsInRaid() then return true end -- in a party everyone may mark and count down
	return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

local function Notify(text)
	M:Print(text)
end

-- Call a Blizzard group function from the player's click.
local function CallGroup(fn, ...)
	if not fn then return Notify(L["Not available on this client."]) end
	local ok, result = pcall(fn, ...)
	if not ok then
		Notify(L["The game did not allow this right now."])
	elseif result == false then
		Notify(L["Only the group leader or an assist can do this."])
	end
end

local function IsLeader()
	return IsInGroup() and UnitIsGroupLeader("player")
end

-- A ready check or role check needs the leader in a party, the leader or
-- an assist in a raid. The game ignores anyone else without a word.
local function CanPoll()
	if not IsInGroup() then return false end
	if IsInRaid() then return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") end
	return UnitIsGroupLeader("player")
end

local function Poll(fn)
	if not CanPoll() then
		return Notify(IsInRaid() and L["Only the group leader or an assist can do this."] or L["Only the group leader can do this."])
	end
	CallGroup(fn)
end

---------------------------------------------------------------------------
-- Pull countdown: the Pull button and /eui pull call these, one
-- C_PartyInfo.DoCountdown per click or typed command. Nothing starts a
-- countdown from an event or a timer. The Encounter Timeline shows the
-- running countdown as one icon (START_PLAYER_COUNTDOWN).
---------------------------------------------------------------------------
local function CountdownAPI()
	return C_PartyInfo and C_PartyInfo.DoCountdown
end

local function EncounterRunning()
	local api = C_InstanceEncounter
	if api and type(api.IsEncounterInProgress) == "function" then
		local ok, running = pcall(api.IsEncounterInProgress)
		return ok and running == true
	end
	return false
end

-- Why a countdown can't start now, or nil.
function M:PullBlocked()
	if not CountdownAPI() then return L["Not available on this client."] end
	if not IsInGroup() then return L["The pull countdown needs a group."] end
	local ok, lead = pcall(IsLead)
	local secret = ok and issecretvalue and issecretvalue(lead)
	if not ok or secret or not lead then return L["Only the group leader or an assist can do this."] end
	if InCombatLockdown() then return L["Not in combat."] end
	if EncounterRunning() then return L["Not while a boss fight is running."] end
	return nil
end

-- seconds: nil uses the Countdown seconds setting.
function M:StartPull(seconds)
	local blocked = self:PullBlocked()
	if blocked then
		Notify(blocked)
		return false
	end
	seconds = tonumber(seconds) or self.db.countdownSeconds
	seconds = math.floor(math.max(1, math.min(seconds, MaxCountdown())))
	CallGroup(CountdownAPI(), seconds)
	return true
end

function M:CancelPull()
	local api = CountdownAPI()
	if not api then
		Notify(L["Not available on this client."])
		return false
	end
	if not IsInGroup() then
		Notify(L["The pull countdown needs a group."])
		return false
	end
	CallGroup(api, 0)
	return true
end

E:AddCommand("pull", "[seconds | cancel]  start or cancel the group pull countdown (leader or assist)", function(arg)
	local word = tostring(arg or ""):lower():match("^%s*(%S*)")
	if word == "cancel" or word == "stop" then
		M:CancelPull()
	elseif word == "" then
		M:StartPull()
	elseif tonumber(word) then
		M:StartPull(tonumber(word))
	else
		Notify(L["Type /eui pull, /eui pull 8 or /eui pull cancel."])
	end
end, "Tools")

-- Blizzard's own slash command (localized) for a secure macro button.
local function Slash(key, fallback)
	local text = _G["SLASH_" .. key .. "1"]
	return type(text) == "string" and text or fallback
end

local function LeaveGroup()
	local leave = (C_PartyInfo and C_PartyInfo.LeaveParty) or _G.LeaveParty
	if leave then pcall(leave) end
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
local function ShowTip(button)
	if not M.db.tooltips or not button.tip then return end
	GameTooltip:SetOwner(button, "ANCHOR_BOTTOMRIGHT")
	GameTooltip:SetText(button.tip[1], 1, 1, 1)
	-- Text lines first, then the click hints ({ action, what }).
	local hints = {}
	for index = 2, #button.tip do
		local line = button.tip[index]
		if type(line) == "table" then hints[#hints + 1] = line else E.UIKit.TipText(GameTooltip, line) end
	end
	E:TooltipHint(GameTooltip, unpack(hints))
	GameTooltip:Show()
end

local function HideTip(button)
	if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end

local function AddTip(button, ...)
	button.tip = { ... }
	button:HookScript("OnEnter", ShowTip)
	button:HookScript("OnLeave", HideTip)
	-- Ctrl-click opens the Raid Tools options (secure buttons are skipped).
	E:BindOptionsLink(button, { page = "module:RaidTools" })
end

-- A plain button with a text label (ready, roles, pull).
local function TextButton(parent, label, onClick)
	local button = CreateFrame("Button", nil, parent)
	E:SetTemplate(button)
	button.text = E:CreateText(button, E.tokens.size.small, "CENTER")
	button.text:SetPoint("CENTER")
	button.text:SetText(label)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetScript("OnClick", function(self, mouse, ...)
		if E:IsOptionsLinkClick(self, mouse) then return end
		onClick(self, mouse, ...)
	end)
	button:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(E.media.accentColor)) end)
	button:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(E.media.borderColor)) end)
	return button
end

-- A secure button with a text label (main tank, main assist).
local function SecureTextButton(parent, name, label, attributes)
	local button = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
	E:SetTemplate(button)
	-- Act on the release: with the game's "cast on key press" setting a
	-- secure button otherwise waits for a press it never receives.
	button:RegisterForClicks("AnyUp")
	button:SetAttribute("useOnKeyDown", false)
	for key, value in pairs(attributes) do button:SetAttribute(key, value) end
	button.text = E:CreateText(button, E.tokens.size.small, "CENTER")
	button.text:SetPoint("CENTER")
	button.text:SetText(label)
	button:HookScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(E.media.accentColor)) end)
	button:HookScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(E.media.borderColor)) end)
	return button
end

-- A secure icon button; attributes say what a click does.
local function SecureIconButton(parent, name, texture, attributes)
	local button = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
	E:SetTemplate(button)
	-- Act on the release: with the game's "cast on key press" setting a
	-- secure button otherwise waits for a press it never receives.
	button:RegisterForClicks("AnyUp")
	button:SetAttribute("useOnKeyDown", false)
	for key, value in pairs(attributes) do button:SetAttribute(key, value) end
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", E.pixel * 2, -E.pixel * 2)
	button.icon:SetPoint("BOTTOMRIGHT", -E.pixel * 2, E.pixel * 2)
	button.icon:SetTexture(texture)
	button:HookScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(E.media.accentColor)) end)
	button:HookScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(E.media.borderColor)) end)
	return button
end

function M:CreateBar()
	if self.bar then return self.bar end
	local bar = CreateFrame("Frame", "EldoUI_RaidToolsBar", UIParent, "SecureHandlerStateTemplate")
	bar:SetSize(200, 24)
	bar.bg = CreateFrame("Frame", nil, bar)
	bar.bg:SetAllPoints()
	bar.bg:SetFrameLevel(math.max(bar:GetFrameLevel() - 1, 0))
	E:SetTemplate(bar.bg, true)
	E:SetStyleEdge(bar.bg) -- WoW Forever art style frame line
	self.bar = bar

	self.holder = CreateFrame("Frame", "EldoUI_RaidToolsHolder", UIParent)
	self.holder:SetSize(200, 24)
	E:CreateMover(self.holder, "EldoUI_RaidTools", L["Raid Tools"], { "TOPLEFT", "UIParent", "TOPLEFT", 19, -324 })
	bar:SetPoint("TOPLEFT", self.holder, "TOPLEFT")
	E:AddMoverContent("EldoUI_RaidTools", bar)

	-- Text buttons
	bar.ready = TextButton(bar, L["Ready"], function() Poll(C_PartyInfo and C_PartyInfo.DoReadyCheck) end)
	AddTip(bar.ready, L["Ready check"], L["Asks everyone in the group whether they are ready."])
	bar.roles = TextButton(bar, L["Roles"], function() Poll(InitiateRolePoll) end)
	AddTip(bar.roles, L["Role check"], L["Asks everyone to confirm tank, healer or damage."])
	bar.pull = TextButton(bar, L["Pull"], function(_, mouse)
		if mouse == "RightButton" then
			M:CancelPull()
		else
			M:StartPull()
		end
	end)
	AddTip(bar.pull, L["Pull countdown"], { L["Left-click"], L["start the group countdown"] }, { L["Right-click"], L["cancel it"] })

	-- World markers: left-click places (or removes) on the ground, right-click clears.
	bar.markers = {}
	for index, marker in ipairs(MARKER_ORDER) do
		local button = SecureIconButton(bar, "EldoUI_RaidToolsMarker" .. index, ICON_PATH:format(MARKER_ICON[marker] or marker), {
			type = "worldmarker", marker = marker, action1 = "toggle", action2 = "clear",
		})
		AddTip(button, L["World marker"], { L["Left-click"], L["place it where you click next, or remove it"] }, { L["Right-click"], L["remove it"] })
		bar.markers[index] = button
	end
	bar.clearMarkers = SecureIconButton(bar, "EldoUI_RaidToolsClearMarkers", "Interface\\Buttons\\UI-GroupLoot-Pass-Up", {
		type = "worldmarker", action = "clear",
	})
	AddTip(bar.clearMarkers, L["Clear world markers"], L["Removes all world markers."])

	-- Raid target icons on your current target.
	bar.targets = {}
	for index, icon in ipairs(TARGET_ORDER) do
		local button = SecureIconButton(bar, "EldoUI_RaidToolsTarget" .. index, ICON_PATH:format(icon), {
			type = "raidtarget", marker = icon, unit = "target", action1 = "toggle", action2 = "clear",
		})
		AddTip(button, L["Target icon"], { L["Left-click"], L["put this icon on your target, or take it off"] }, { L["Right-click"], L["clear your target's icon"] })
		bar.targets[index] = button
	end
	bar.clearTargets = SecureIconButton(bar, "EldoUI_RaidToolsClearTargets", "Interface\\Buttons\\UI-GroupLoot-Pass-Up", {
		type = "raidtarget", action = "clear-all",
	})
	AddTip(bar.clearTargets, L["Clear target icons"], L["Removes every raid target icon."])

	-- Group management (third row).
	bar.convert = TextButton(bar, L["Raid"], function()
		if not IsLeader() then return Notify(L["Only the group leader can do this."]) end
		if IsInRaid() then
			CallGroup(C_PartyInfo and C_PartyInfo.ConvertToParty)
		else
			CallGroup(C_PartyInfo and C_PartyInfo.ConvertToRaid)
		end
	end)
	AddTip(bar.convert, L["Convert group"], L["Turns your party into a raid, or a raid of five or fewer back into a party."])
	bar.assist = TextButton(bar, L["Assist"], function()
		if not (IsInRaid() and UnitIsGroupLeader("player")) then return Notify(L["Only the raid leader can do this."]) end
		local on = IsEveryoneAssistant and IsEveryoneAssistant()
		CallGroup(C_PartyInfo and C_PartyInfo.SetEveryoneIsAssistant, not on)
	end)
	AddTip(bar.assist, L["Everyone is assistant"], L["Gives every raid member assistant rights, or takes them back."], L["Accent border: on."])
	bar.assist:HookScript("OnLeave", function() M:UpdateGroupButtons() end)
	bar.mainTank = SecureTextButton(bar, "EldoUI_RaidToolsMainTank", L["MT"], {
		type = "macro",
		macrotext1 = Slash("MAINTANKON", "/maintank") .. " [nocombat] target",
		macrotext2 = Slash("MAINTANKOFF", "/maintankoff") .. " [nocombat] target",
	})
	AddTip(bar.mainTank, L["Main tank"], { L["Left-click"], L["make your target a main tank"] }, { L["Right-click"], L["remove it (out of combat only)"] })
	bar.mainAssist = SecureTextButton(bar, "EldoUI_RaidToolsMainAssist", L["MA"], {
		type = "macro",
		macrotext1 = Slash("MAINASSISTON", "/mainassist") .. " [nocombat] target",
		macrotext2 = Slash("MAINASSISTOFF", "/mainassistoff") .. " [nocombat] target",
	})
	AddTip(bar.mainAssist, L["Main assist"], { L["Left-click"], L["make your target a main assist"] }, { L["Right-click"], L["remove it (out of combat only)"] })
	bar.raidPanel = TextButton(bar, L["Panel"], function()
		if InCombatLockdown() then return Notify(L["After combat."]) end
		if ToggleRaidFrame then
			local ok = pcall(ToggleRaidFrame)
			if not ok then Notify(L["The game did not allow this right now."]) end
		else
			Notify(L["Not available on this client."])
		end
	end)
	AddTip(bar.raidPanel, L["Raid panel"], L["Opens Blizzard's raid window (Social > Raid) with groups, roles and leader tools."])
	bar.leave = TextButton(bar, L["Leave"], function()
		if not IsInGroup() then return Notify(L["You are not in a group."]) end
		E:ShowConfirm({ key = "ELDOUI_RAIDTOOLS_LEAVE", title = L["Leave group"], text = L["Leave your group?"],
			accept = YES or L["Yes"], cancel = NO or L["No"], danger = true, onAccept = LeaveGroup })
	end)
	AddTip(bar.leave, L["Leave group"], L["Asks first, then you leave the group."])
	bar.reset = TextButton(bar, L["Reset"], function(_, mouse)
		local instances = E:GetModule("Instances")
		if mouse == "RightButton" then
			if instances and instances.active and instances.AnnounceReset then
				instances:AnnounceReset()
			else
				Notify(L["Turn on the Instances module and its \"Announce reset\" option to announce resets."])
			end
			return
		end
		if IsInGroup() and not UnitIsGroupLeader("player") then return Notify(L["Only the group leader can reset instances."]) end
		if instances and instances.active and instances.ResetInstancesClick then
			instances:ResetInstancesClick()
		elseif ResetInstances then
			CallGroup(ResetInstances)
		end
	end)
	AddTip(bar.reset, L["Reset instances"], { L["Left-click"], L["reset all your instances (leader, or alone), like the portrait menu"] },
		{ L["Right-click"], L["announce the last reset to the group (Instances > Resets > Announce reset)"] })
	return bar
end

-- Labels and the accent state of the group row follow the group.
function M:UpdateGroupButtons()
	local bar = self.bar
	if not bar or not bar.convert then return end
	bar.convert.text:SetText(IsInRaid() and L["Party"] or L["Raid"])
	-- Ready and Roles dim for a player the game would ignore.
	local poll = CanPoll() and 1 or E.tokens.disabledAlpha
	bar.ready:SetAlpha(poll)
	bar.roles:SetAlpha(poll)
	local on = IsInRaid() and IsEveryoneAssistant and IsEveryoneAssistant()
	if on then
		bar.assist:SetBackdropBorderColor(unpack(E.media.accentColor))
	else
		bar.assist:SetBackdropBorderColor(unpack(E.media.borderColor))
	end
end

---------------------------------------------------------------------------
-- Layout and visibility (out of combat)
---------------------------------------------------------------------------
function M:Layout()
	if InCombatLockdown() then
		E:RunOutOfCombat(function() self:Layout() end)
		return
	end
	local bar = self.bar
	local db = self.db
	local size = math.max(14, db.buttonSize)
	local gap = math.max(0, db.spacing)
	local pad = db.backdrop and 3 or 0
	local vertical = db.orientation == "VERTICAL"
	local textWidth = vertical and size * 2 or math.floor(size * 2.4)
	local textSize = self:TextSize()

	-- Rows (or columns when vertical): commands + world markers, then targets.
	local rows = { {}, {}, {} }
	local function Use(button, wanted, width, row)
		button:SetShown(wanted)
		if wanted then
			button:SetSize(width, size)
			if button.text then E:SetFont(button.text, textSize) end
			table.insert(rows[row], button)
		end
	end
	Use(bar.ready, db.readyCheck, textWidth, 1)
	Use(bar.roles, db.rolePoll, textWidth, 1)
	Use(bar.pull, db.countdown, textWidth, 1)
	for _, button in ipairs(bar.markers) do Use(button, db.worldMarkers, size, 1) end
	Use(bar.clearMarkers, db.worldMarkers and db.clearMarkers, size, 1)
	for _, button in ipairs(bar.targets) do Use(button, db.raidTargets, size, 2) end
	Use(bar.clearTargets, db.raidTargets and db.clearMarkers, size, 2)
	Use(bar.convert, db.convertGroup, textWidth, 3)
	Use(bar.assist, db.everyoneAssist, textWidth, 3)
	Use(bar.mainTank, db.mainTank, textWidth, 3)
	Use(bar.mainAssist, db.mainAssist, textWidth, 3)
	Use(bar.raidPanel, db.raidPanel, textWidth, 3)
	Use(bar.leave, db.leaveGroup, textWidth, 3)
	Use(bar.reset, db.resetInstances, textWidth, 3)

	local length, lines = 0, 0
	for _, row in ipairs(rows) do
		if #row > 0 then
			local offset = 0
			for _, button in ipairs(row) do
				button:ClearAllPoints()
				local along = vertical and size or button:GetWidth()
				if vertical then
					button:SetPoint("TOPLEFT", bar, "TOPLEFT", pad + lines * (textWidth + gap), -(pad + offset))
				else
					button:SetPoint("TOPLEFT", bar, "TOPLEFT", pad + offset, -(pad + lines * (size + gap)))
				end
				offset = offset + along + gap
			end
			length = math.max(length, offset - gap)
			lines = lines + 1
		end
	end
	if lines == 0 then lines, length = 1, size end
	local across = vertical and (lines * textWidth + (lines - 1) * gap) or (lines * size + (lines - 1) * gap)
	local width = (vertical and across or length) + pad * 2
	local height = (vertical and length or across) + pad * 2
	bar:SetSize(width, height)
	self.holder:SetSize(width, height)
	bar.bg:SetShown(db.backdrop)
	E:SetStyleEdge(bar.bg, db.backdrop)
	if E:IsVisibilityAttached(bar) then E:UpdateVisibility(bar) end
	self:UpdateGroupButtons()
end

-- Text size on the buttons: the setting, or half the button height (11 at
-- the default 22 px) so big buttons get readable labels.
function M:TextSize()
	local chosen = tonumber(self.db.fontSize) or 0
	if chosen > 0 then return math.max(8, math.min(24, chosen)) end
	return math.max(10, math.min(20, math.floor(math.max(14, tonumber(self.db.buttonSize) or 22) / 2)))
end

-- Who the bar is for, as the first clauses of its state driver: "show"
-- while previewed, "hide" for a member who leads nothing.
local function ShownFor()
	if M.preview then return "show" end
	local who = M.db.visibility
	if who == "RAID" then return "[nogroup:raid] hide" end
	if who == "LEAD" then return IsLead() and "[nogroup] hide" or "hide" end
	if who ~= "ALWAYS" then return "[nogroup] hide" end
	return nil
end

-- The visibility engine shows the bar: one state driver from who the bar
-- is for and the shared rules (talent group and resting as their current
-- state; the events below rebuild it), and the alpha part (faded opacity,
-- mouse over, the bar's own opacity). Leadership is read out of combat.
function M:UpdateVisibility()
	if InCombatLockdown() then
		E:RunOutOfCombat(function() self:UpdateVisibility() end, "raidTools:visibility")
		return
	end
	local bar = self.bar
	if not bar then return end
	if not self.active then
		E:DetachVisibility(bar)
		self.fadeBlock = nil
		bar:Hide()
		return
	end
	local block = self.db.fade
	if self.fadeBlock ~= block then E:DetachVisibility(bar) end
	if E:IsVisibilityAttached(bar) then
		E:UpdateVisibility(bar)
	else
		self.fadeBlock = block
		E:AttachVisibility(bar, block, {
			secure = true,
			condition = ShownFor,
			alpha = function() return tonumber(M.db.alpha) or 1 end,
			forceShow = function() return M.preview and true or false end,
		})
	end
	-- No driver needed (shown for everyone, rules that never hide): shown.
	if not E:VisibilityDriver(block, { staticState = true, condition = ShownFor() }) then bar:Show() end
end

-- Settings before the shared visibility rules: "Hide in combat" becomes
-- the Out of combat rule, once.
function M:MigrateVisibility()
	local db = self.db
	if type(db) ~= "table" or db.hideInCombat == nil then return end
	if db.hideInCombat then db.fade = E:VisibilityDefaults({ show = "nocombat" }) end
	E:NormalizeVisibility(db.fade)
	db.hideInCombat = nil
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:OnInitialize()
	self:MigrateVisibility()
end

function M:OnEnable()
	self:MigrateVisibility()
	self:CreateBar()
	self:Layout()
	self:UpdateVisibility()
	local function Refresh()
		self:UpdateVisibility()
		self:UpdateGroupButtons()
	end
	self:RegisterEvent("GROUP_ROSTER_UPDATE", Refresh)
	self:RegisterEvent("PARTY_LEADER_CHANGED", Refresh)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", Refresh)
	-- Talent group and resting live in the driver as their current state.
	self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", function() self:UpdateVisibility() end)
	self:RegisterEvent("PLAYER_UPDATE_RESTING", function()
		if E:VisibilityUsesState(self.db.fade) then self:UpdateVisibility() end
	end)
end

function M:OnDisable()
	for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "PLAYER_ENTERING_WORLD",
		"ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_UPDATE_RESTING" }) do
		self:UnregisterEvent(event)
	end
	self:UpdateVisibility()
end

function M:OnProfileChanged()
	self:MigrateVisibility()
	if not self.active or not self.bar then return end
	self:Layout()
	self:UpdateVisibility()
end

-- Show the bar for a minute outside a group, to place and try it.
function M:Preview()
	if not self.active then return E:Print(E:ModuleOffHint("RaidTools")) end
	if InCombatLockdown() then return E:Print(L["After combat."]) end
	self.preview = true
	self:UpdateVisibility()
	if self.previewTimer then self.previewTimer:Cancel() end
	self.previewTimer = C_Timer.NewTimer(60, function()
		self.preview = nil
		self:UpdateVisibility()
	end)
end

E:AddCommand("raidtools", "show the raid tools bar for a minute", function() M:Preview() end, "Layout & frames")

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
M.options = {
	{ type = "tab", label = "General" },
	{ type = "description", label = "Buttons for group leaders: ready check, role check, pull countdown, world markers and target icons. Every action runs only when you click." },
	{ type = "execute", label = "Show for a minute", desc = "Shows the bar outside a group so you can place and try it. Also /eui raidtools.", func = function() M:Preview() end },
	{ type = "select", key = "visibility", label = "Show for", desc = "Who sees the bar: everyone, anyone in a group, anyone in a raid, or only the leader and assists. Leader or assist is checked out of combat. The Visibility rules below apply on top.",
		values = { ALWAYS = "Always", GROUP = "In a group", RAID = "In a raid", LEAD = "As leader or assist (any party)" } },
	{ type = "toggle", key = "tooltips", label = "Tooltips", desc = "Explain each button on hover." },
	{ type = "header", label = "Buttons" },
	{ type = "toggle", key = "readyCheck", label = "Ready check", desc = "Asks the group whether everyone is ready." },
	{ type = "toggle", key = "rolePoll", label = "Role check", desc = "Asks everyone to confirm their role." },
	{ type = "toggle", key = "countdown", label = "Pull countdown", desc = "Left-click starts the group countdown, right-click cancels it." },
	{ type = "range", unit = "s", key = "countdownSeconds", dependsOn = "countdown", label = "Countdown seconds", min = 3, max = 30, step = 1, desc = "Length of the pull countdown." },
	{ type = "toggle", key = "worldMarkers", label = "World markers", desc = "Eight buttons that place or remove the colored ground markers." },
	{ type = "toggle", key = "clearMarkers", label = "Clear buttons", desc = "A button that removes all world markers (and all target icons on the icon row).",
		disabled = function() return not (M.db.worldMarkers or M.db.raidTargets) and L["Turn on \"World markers\" or \"Target icon row\" first."] end },
	{ type = "toggle", key = "raidTargets", label = "Target icon row", desc = "A second row that puts skull, cross and the other icons on your target." },
	{ type = "header", label = "Group" },
	{ type = "description", label = "A third row for running the group. Each button is one click; nothing happens on its own." },
	{ type = "toggle", key = "convertGroup", label = "Party / raid", desc = "Turns your party into a raid, or a small raid back into a party (group leader)." },
	{ type = "toggle", key = "everyoneAssist", label = "Everyone is assistant", desc = "Gives every raid member assistant rights, or takes them back (raid leader). The border turns accent while it is on." },
	{ type = "toggle", key = "mainTank", label = "Main tank", desc = "Left-click makes your target a main tank, right-click removes it (Blizzard's /mt, out of combat)." },
	{ type = "toggle", key = "mainAssist", label = "Main assist", desc = "Left-click makes your target a main assist, right-click removes it (Blizzard's /ma, out of combat)." },
	{ type = "toggle", key = "raidPanel", label = "Raid panel", desc = "Opens Blizzard's raid window, where the leader can move members between groups or remove them." },
	{ type = "toggle", key = "leaveGroup", label = "Leave group", desc = "Leaves the group after you confirm. There is no disband button: removing everyone at once would be many actions from one click." },
	{ type = "toggle", key = "resetInstances", label = "Reset instances", desc = "Left-click resets all your instances (group leader, or alone), the same as the portrait menu. Right-click announces the last reset when the Instances module allows it. Only ever on your click." },
	{ type = "header", label = "Look" },
	{ type = "select", key = "orientation", label = "Direction", desc = "A row across or a column down.", values = { HORIZONTAL = "Across", VERTICAL = "Down" } },
	{ type = "range", key = "buttonSize", label = "Button size", min = 14, max = 40, step = 1, desc = "Height of every button; text buttons are wider." },
	{ type = "range", key = "fontSize", label = "Text size", min = 0, max = 20, step = 1, zeroText = "Auto",
		desc = "Size of the labels on Ready, Roles, Pull and the group buttons. Auto follows the button size." },
	{ type = "range", key = "spacing", label = "Spacing", min = 0, max = 10, step = 1, desc = "Gap between buttons." },
	{ type = "toggle", key = "backdrop", label = "Background", desc = "A panel behind the buttons." },
	{ type = "range", percent = true, key = "alpha", label = "Opacity", min = 0.2, max = 1, step = 0.05, desc = "How solid the bar looks." },
	{ type = "execute", label = "Move", desc = "Unlock EldoUI frames to drag the bar. Show for a minute (top of the page) makes it visible outside a group.",
		func = function() E:ToggleMoveMode() end },
}

-- Visibility: who the bar is for, then the shared rules (a protected bar,
-- so instance rules that would only make it invisible are left out).
do
	local showFor, at
	for index, row in ipairs(M.options) do
		if row.key == "visibility" then showFor = table.remove(M.options, index) break end
	end
	for index, row in ipairs(M.options) do
		if row.key == "tooltips" then at = index + 1 break end
	end
	local rows = E:VisibilityOptions("fade", { db = function() return M.db end, secure = true })
	if showFor then table.insert(rows, 2, showFor) end
	at = at or #M.options + 1
	for _, row in ipairs(rows) do
		table.insert(M.options, at, row)
		at = at + 1
	end
end

---------------------------------------------------------------------------
-- Style presets
---------------------------------------------------------------------------
-- The group row's buttons, for the presets that promise "only" some buttons.
local function WithoutGroupRow(settings)
	for _, key in ipairs({ "convertGroup", "everyoneAssist", "mainTank", "mainAssist", "raidPanel", "leaveGroup", "resetInstances" }) do
		settings[key] = false
	end
	return settings
end

E:RegisterStyles("RaidTools", {
	{ key = "Leader", title = "Raid leader", desc = "Every leader button and the target icon row, without Leave group.",
		settings = { visibility = "LEAD", fade = { preset = "always", show = "always", fadedAlpha = 0, fadeTime = 0.2, delay = 0 }, orientation = "HORIZONTAL", buttonSize = 22, spacing = 2,
			backdrop = true, alpha = 1, readyCheck = true, rolePoll = true, countdown = true, worldMarkers = true, clearMarkers = true, raidTargets = true,
			convertGroup = true, everyoneAssist = true, mainTank = true, mainAssist = true, raidPanel = true, leaveGroup = false, resetInstances = true } },
	{ key = "Compact", title = "Compact", desc = "Small buttons, only ready check, pull and markers.",
		settings = WithoutGroupRow({ visibility = "LEAD", orientation = "HORIZONTAL", buttonSize = 18, spacing = 1, backdrop = true, alpha = 1,
			readyCheck = true, rolePoll = false, countdown = true, worldMarkers = true, clearMarkers = true, raidTargets = false }) },
	{ key = "Column", title = "Column", desc = "An upright column of large buttons.",
		settings = { orientation = "VERTICAL", buttonSize = 26, spacing = 2, backdrop = true, alpha = 1,
			readyCheck = true, rolePoll = true, countdown = true, worldMarkers = true, clearMarkers = true, raidTargets = false } },
	{ key = "Markers", title = "Markers only", desc = "Just the world markers, for anyone who places them.",
		settings = WithoutGroupRow({ visibility = "GROUP", readyCheck = false, rolePoll = false, countdown = false, worldMarkers = true,
			clearMarkers = true, raidTargets = false, buttonSize = 22, backdrop = false }) },
	{ key = "Minimal", title = "Minimal", desc = "No background, faded, hidden in combat.",
		settings = { visibility = "LEAD", fade = { preset = "custom", show = "nocombat", fadedAlpha = 0 }, backdrop = false, alpha = 0.6, buttonSize = 20, spacing = 2,
			readyCheck = true, rolePoll = true, countdown = true, worldMarkers = true, clearMarkers = false, raidTargets = false } },
}, { restores = {
	"alpha", "visibility", "convertGroup", "everyoneAssist", "mainTank", "mainAssist", "raidPanel",
	"leaveGroup", "resetInstances"
} })
