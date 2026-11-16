-- EldoUI Quality of Life, part two (the former Tweaks module, merged into
-- QoL): the small conveniences people usually install separate addons
-- for. Each one has its own tick in the options and only changes what the
-- player could click or set themselves. Anything that acts for the player
-- (quest accept and turn-in, gossip) is off by default. Its rows go on the
-- QoL page's Quests, Interface and Sound and misc tabs; its old settings
-- move into QoL's once per profile (MergeTweaks below).
--   * Quests: accept and turn in (never picks a reward), skip a lone vendor
--     gossip option, and the sell value of every quest reward. The accept
--     helper can leave gray (trivial) quests alone and take only one quest
--     per talk with an NPC.
--   * Durability figure (element "durability-figure"): Blizzard's
--     armor man on an EldoUI mover with a scale, or hidden.
--   * Screen edge panels: thin decorative bars across the top and
--     bottom edge of the screen, off by default.
--   * Camera and screenshots: max zoom (its range follows the largest
--     distance this client allows, see Modules/Camera.lua), zoom speed,
--     ActionCam (over-the-shoulder view whose offset eases in as you zoom
--     out, optional dynamic pitch), screenshot quality and format, each
--     only while its tick is on (game settings through E:SetCVar, so your own
--     value comes back when the tick goes off or with "Blizzard default").
--     ActionCam uses the game's experimental camera settings: the game asks
--     the player to confirm them with its own warning, and when the player
--     picks Disable there EldoUI turns ActionCam off too.
--   * Game settings: self-cast key, auto self-cast, new spells on the
--     bars, spell queue window, always compare items, the "screenshot
--     saved" message and the game's graphics quality step. Each row starts
--     at "Game setting" and is never written until the player picks a value;
--     the first change snapshots the player's own value (E:SetCVar), and
--     "Game setting" or "Restore game settings" puts it back. Rows whose
--     CVar this client lacks are hidden (requires probe); /eui gamesettings
--     lists which exist. No right-click guard: Forever has no game CVar for
--     it and EldoUI builds no secure driver of its own (dropped).
--   * Red error text filters moved to Messages (ui-errors switch);
--     filling in DELETE moved to System UI (dialogs switch).
local _, E = ...
local L = E.L

local M = E:GetModule("QoL")

local DEFAULTS = {
	autoAccept = false,
	autoTurnIn = false,
	pauseKey = "SHIFT",     -- hold to pause the quest helpers
	skipTrivial = true,     -- the accept helper leaves gray (trivial) quests alone
	oneQuestPerTalk = true, -- after one accepted quest, the NPC's other quests wait for you
	leaveRepeatable = true, -- repeatable quests (hand-ins, dailies) stay with the player
	skipGossip = false,
	rewardValue = true,     -- sell price on quest reward buttons
	combatAlert = false,
	-- Game settings: only changed while their tick is on.
	setMaxZoom = false,
	maxZoom = 2.6,
	setZoomSpeed = false,
	zoomSpeed = 20,         -- the game's default camera zoom speed
	actionCam = false,      -- over-the-shoulder view (game's experimental camera settings)
	shoulder = 1,           -- yards to the side at full distance
	shoulderEase = true,    -- the offset grows as you zoom out
	shoulderEaseDistance = 15,
	dynamicPitch = false,
	setScreenshots = false,
	screenshotQuality = 10,
	screenshotFormat = "png",
	-- Game settings. "game" = never written by EldoUI.
	selfCastKey = "game",     -- game | NONE | ALT | CTRL | SHIFT
	autoSelfCast = "game",    -- game | on | off
	autoPushSpells = "game",  -- game | on | off
	compareItems = "game",    -- game | on | off
	setSpellQueue = false,
	spellQueue = 400,         -- ms; only written while setSpellQueue is on
	hideScreenshotMsg = false,
	setGraphics = false,
	graphicsQuality = 5,      -- the game's 1-10 quality preset
	-- Durability figure (used while its Blizzard UI switches are on).
	durabilityScale = 1,
	-- Screen edge panels.
	edgeTop = false,
	edgeBottom = false,
	edgeHeight = 22,
	edgeTransparent = true,
	edgeAccent = true,
}
for key, value in pairs(DEFAULTS) do M.defaults[key] = value end

local function Paused()
	local key = M.db.pauseKey
	return (key == "SHIFT" and IsShiftKeyDown()) or (key == "CTRL" and IsControlKeyDown()) or (key == "ALT" and IsAltKeyDown())
end

---------------------------------------------------------------------------
-- Quests. A leveling guide addon drives quests itself, so these stay quiet
-- while it runs.
---------------------------------------------------------------------------
local function QuestHelpersOn()
	return not Paused() and not C_AddOns.IsAddOnLoaded("RXPGuides")
end

local VENDOR_ICON = 132060 -- Interface\\GossipFrame\\VendorGossipIcon

local function IsVendorOption(option)
	return option and (option.icon == VENDOR_ICON or option.type == "vendor")
end

local IsSecret = E.Secret

-- Gray quests: the game marks them trivial for your level.
local function QuestIsTrivial(questID)
	if not (questID and C_QuestLog and C_QuestLog.IsQuestTrivial) then return false end
	local ok, trivial = pcall(C_QuestLog.IsQuestTrivial, questID)
	return ok and trivial == true
end

-- One quest per talk: after the helper picked a quest from an NPC's list,
-- the list that comes back right after accepting it is left to the player.
-- Talking to the NPC again picks the next one.
local picked = { guid = nil, time = nil }

local function NpcGUID()
	local guid = UnitGUID("npc")
	if IsSecret(guid) then return nil end
	return guid
end

local function MayPick()
	local db = M.db
	if not db.oneQuestPerTalk then return true end
	local guid = NpcGUID()
	local same = guid and picked.guid == guid and (not picked.time or GetTime() - picked.time < 3)
	picked.guid, picked.time = nil, nil
	return not same
end

local function NotePick()
	picked.guid, picked.time = NpcGUID(), nil
end

-- The first quest of an NPC's gossip list the helper may take.
local function FirstGossipQuest(list)
	for _, quest in ipairs(list or {}) do
		local repeatable = M.db.leaveRepeatable and (quest.repeatable == true
			or (type(quest.frequency) == "number" and not E.Secret(quest.frequency) and quest.frequency > 0))
		if not repeatable and not (M.db.skipTrivial and (quest.isTrivial or QuestIsTrivial(quest.questID))) then return quest end
	end
end

-- The first quest of a quest-greeting list (older NPCs) the helper may take.
local function FirstGreetingQuest()
	for index = 1, GetNumAvailableQuests() do
		local trivial = false
		if M.db.skipTrivial then
			if GetAvailableQuestInfo then
				trivial = GetAvailableQuestInfo(index) and true or false
			elseif IsAvailableQuestTrivial then
				trivial = IsAvailableQuestTrivial(index) and true or false
			end
		end
		if not trivial then return index end
	end
end

-- A quest that costs gold to complete is always left to the player: the
-- quest window shows the cost and they decide.
local function CostsMoney()
	if not GetQuestMoneyToGet then return false end
	local ok, money = pcall(GetQuestMoneyToGet)
	return ok and not IsSecret(money) and type(money) == "number" and money > 0
end

-- Repeatable quests (reputation hand-ins, dailies), left to the player while
-- "Leave repeatable quests to you" is on, so a stack is never handed in at once.
local function Repeatable(questID)
	if IsSecret(questID) or not (M.db.leaveRepeatable and questID) then return false end
	if C_QuestLog and C_QuestLog.IsRepeatableQuest then
		local ok, repeatable = pcall(C_QuestLog.IsRepeatableQuest, questID)
		if ok and repeatable == true then return true end
	end
	return false
end

local function RepeatableGossip(quest)
	if not M.db.leaveRepeatable then return false end
	if quest.repeatable == true or (type(quest.frequency) == "number" and not IsSecret(quest.frequency) and quest.frequency > 0) then return true end
	return Repeatable(quest.questID)
end

local function ShownQuestID()
	local questID = GetQuestID and GetQuestID()
	if IsSecret(questID) then return nil end
	return questID
end

local function OnQuestEvent(_, event)
	local db = M.db
	if event == "QUEST_ACCEPTED" or event == "QUEST_FINISHED" then
		if picked.guid then picked.time = picked.time or GetTime() end
		return
	end
	if not QuestHelpersOn() then return end
	-- Quests shared by players are left to the player (and to QoL's blocker).
	if event == "QUEST_DETAIL" and db.autoAccept and not UnitIsPlayer("questnpc") then
		local questID = ShownQuestID()
		if db.skipTrivial and QuestIsTrivial(questID) then return end
		if Repeatable(questID) then return end
		if QuestGetAutoAccept and QuestGetAutoAccept() then
			if AcknowledgeAutoAcceptQuest then AcknowledgeAutoAcceptQuest() end
		else
			AcceptQuest()
		end
	elseif event == "QUEST_PROGRESS" and db.autoTurnIn then
		if IsQuestCompletable() and not CostsMoney() and not Repeatable(ShownQuestID()) then CompleteQuest() end
	elseif event == "QUEST_COMPLETE" and db.autoTurnIn then
		if CostsMoney() or Repeatable(ShownQuestID()) then return end
		-- Only when there is no reward to choose.
		local choices = GetNumQuestChoices()
		if choices <= 1 then GetQuestReward(choices) end
	elseif event == "QUEST_GREETING" then
		if db.autoTurnIn then
			for i = 1, GetNumActiveQuests() do
				local _, complete = GetActiveTitle(i)
				local questID = GetActiveQuestID and GetActiveQuestID(i)
				if complete and not Repeatable(questID) then return SelectActiveQuest(i) end
			end
		end
		if db.autoAccept and GetNumAvailableQuests() > 0 and MayPick() then
			local index = FirstGreetingQuest()
			if index then
				NotePick()
				SelectAvailableQuest(index)
			end
		end
	elseif event == "GOSSIP_SHOW" then
		if db.autoTurnIn then
			for _, quest in ipairs(C_GossipInfo.GetActiveQuests()) do
				if quest.isComplete and not RepeatableGossip(quest) then return C_GossipInfo.SelectActiveQuest(quest.questID) end
			end
		end
		if db.autoAccept and MayPick() then
			local quest = FirstGossipQuest(C_GossipInfo.GetAvailableQuests())
			if quest then
				NotePick()
				return C_GossipInfo.SelectAvailableQuest(quest.questID)
			end
		end
		-- Only a lone shop option with no quest attached; anything else stays.
		if db.skipGossip then
			local options = C_GossipInfo.GetOptions()
			if #options == 1 and #C_GossipInfo.GetActiveQuests() == 0 and #C_GossipInfo.GetAvailableQuests() == 0
				and IsVendorOption(options[1]) then
				C_GossipInfo.SelectOption(options[1].gossipOptionID)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Interface
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Quest reward values: the sell price on its own line at the bottom right
-- of each reward button on the accept and reward windows, inside the
-- button and clear of the icon; the item name keeps the space above it.
-- Shows only; never picks a reward.
---------------------------------------------------------------------------
local rewardTexts = {} -- reward button -> font string
local rewardNames = {} -- reward button -> the name's own points, while a value shows
local VALUE_INSET = 4    -- from the button's right and bottom edges
local VALUE_LINE = 12    -- the value line's height, kept free of the name

local function Money(copper)
	return E:FormatMoney(copper)
end

local function RewardButtons()
	local frame = QuestInfoRewardsFrame
	if frame and frame.RewardButtons then return frame.RewardButtons end
	local list = {}
	for index = 1, 10 do
		local button = _G["QuestInfoRewardsFrameQuestInfoItem" .. index]
		if button then list[#list + 1] = button end
	end
	return list
end

local function RewardIcon(button)
	return button.Icon or button.icon or _G[(button:GetName() or "") .. "IconTexture"]
end

local function RewardName(button)
	return button.Name or _G[(button:GetName() or "") .. "Name"]
end

-- The item name between the icon and the button's right edge, above the
-- value line (one or two lines; the game's font string cuts the rest).
local function MakeRoomForValue(button)
	local name, icon = RewardName(button), RewardIcon(button)
	if not (name and icon and name.GetNumPoints) or rewardNames[button] then return end
	local points = {}
	for index = 1, name:GetNumPoints() do points[index] = { name:GetPoint(index) } end
	rewardNames[button] = { points = points, width = name:GetWidth(), height = name:GetHeight() }
	name:ClearAllPoints()
	name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 5, 0)
	name:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -VALUE_INSET, VALUE_INSET + VALUE_LINE)
end

-- The name back where the game put it, once the button shows no value.
local function RestoreName(button)
	local saved, name = rewardNames[button], RewardName(button)
	rewardNames[button] = nil
	if not (saved and name) then return end
	name:ClearAllPoints()
	for _, point in ipairs(saved.points) do name:SetPoint(unpack(point)) end
	if saved.width and saved.width > 0 and saved.height and saved.height > 0 then name:SetSize(saved.width, saved.height) end
end

function M:UpdateRewardValues()
	if not (QuestFrame and QuestFrame:IsShown()) then return end
	local best, bestValue = nil, 0
	for _, button in ipairs(RewardButtons()) do
		local text = rewardTexts[button]
		if text then text:SetText("") end
		local shown = false
		local kind = button.type
		local index = button.GetID and button:GetID()
		if self.active and self.db.rewardValue and button:IsShown() and (kind == "choice" or kind == "reward") and index then
			local link = GetQuestItemLink(kind, index)
			local count = select(3, GetQuestItemInfo(kind, index)) or 1
			local price = link and select(11, C_Item.GetItemInfo(link)) or 0
			if price > 0 then
				if not text then
					text = E:CreateText(button, E.tokens.size.small, "RIGHT")
					text:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -VALUE_INSET, VALUE_INSET)
					text:SetWordWrap(false)
					rewardTexts[button] = text
				end
				local value = price * math.max(count, 1)
				text:SetText(Money(value))
				text:SetTextColor(unpack(E.media.text.body))
				MakeRoomForValue(button)
				shown = true
				if kind == "choice" and value > bestValue then best, bestValue = text, value end
			end
		end
		if not shown then RestoreName(button) end
	end
	-- The most valuable choice in the accent color; the choice stays yours.
	-- While Upgrades marks quest rewards (its arrow, or its coin on the
	-- best-selling one), it owns the marker: the reward is marked once.
	if best and GetNumQuestChoices() > 1 and not M:UpgradesMarksRewards() then best:SetTextColor(E:TokenColor("accent")) end
end

function M:UpgradesMarksRewards()
	local upgrades = E.modules and E.modules.Upgrades
	return (upgrades and upgrades.active and type(upgrades.db) == "table" and upgrades.db.questRewards) and true or false
end

local function CombatText(text, r, g, b)
	if not M.db.combatAlert then return end
	UIErrorsFrame:AddMessage(text, r, g, b)
end

---------------------------------------------------------------------------
-- Durability figure: Blizzard's armor man (DurabilityFrame, an
-- Edit Mode system) on the "Durability figure" mover with its own scale,
-- or hidden. Only while the element's switches are on; off = Blizzard's
-- Edit Mode position. Uses the combat kit's pins (SetPointBase, so Edit
-- Mode's own tables stay untouched) and its hidden parent.
---------------------------------------------------------------------------
local DURABILITY = "durability-figure"
local DURABILITY_MOVER = "EldoUI_Durability"
-- The game shows the figure only while gear is damaged: an event box.
E:RegisterVisibilityFacet(DURABILITY_MOVER, "event", { module = "QoL" })
local durabilityTouched = false
local durabilityPin
local durabilityLayoutHooks = setmetatable({}, { __mode = "k" })

local function DurabilityAllowed(action)
	return M.active and E:BlizzardAllowed(DURABILITY, action)
end

-- Public native geometry, relative to the exact holder's center. An absent
-- participant and a participant whose current ownership is unknown differ.
function M:DurabilityLayoutBounds()
	if not self.active or DurabilityAllowed("hide") or not DurabilityAllowed("move") then return end
	local frame, K, owned = _G.DurabilityFrame, E.CombatKit, durabilityPin
	if E.modules.QoL ~= self or not (frame and K and owned and owned.frame == frame
		and owned.holder == K.GetHolder(DURABILITY_MOVER) and not K.EditModeActive() and K.IsPinned(frame)) then return nil, nil, "durability" end
	local pinned = false
	for target, spec in E:EachBlizzardPin() do if target == frame and spec == owned.spec then pinned = true end end
	if not pinned or owned.parent ~= UIParent or frame:GetParent() ~= owned.parent or frame:GetNumPoints() ~= 1 then return nil, nil, "pin" end
	local point, relative, relativePoint, x, y = frame:GetPoint(1)
	if not K.Plain(point, relative, relativePoint, x, y) or point ~= "CENTER" or relative ~= owned.holder or relativePoint ~= "CENTER" or x ~= 0 or y ~= 0 then return nil, nil, "pin" end
	local function Number(value, positive)
		return not E:IsSecret(value) and type(value) == "number" and value == value
			and math.abs(value) < math.huge and (not positive or value > 0)
	end
	local scale, expected = frame:GetScale(), self.db.durabilityScale
	local parentScale, frameScale = UIParent:GetEffectiveScale(), frame:GetEffectiveScale()
	if not (Number(scale, true) and Number(expected, true) and math.abs(scale - expected) <= 0.001
		and Number(parentScale, true) and Number(frameScale, true)) then return nil, nil, "scale" end
	if not frame:IsShown() then return end
	local k = frameScale / parentScale
	local width, height = frame:GetSize()
	if not (Number(width, true) and Number(height, true)) then return nil, nil, "size" end
	local root = { -width * k / 2, -height * k / 2, width * k / 2, height * k / 2 }
	local textures, known = {}, {}
	for _, suffix in ipairs({ "Head", "Shoulders", "Chest", "Waist", "Legs", "Feet", "Wrists", "Hands", "Weapon", "Shield", "OffWeapon", "Ranged" }) do
		local name = "Durability" .. suffix
		local texture = _G[name]
		if not (texture and texture:GetParent() == frame) then return nil, nil, "texture" end
		textures[name], known[texture] = texture, name
	end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:IsShown() and not known[region] then return nil, nil, "texture" end
	end
	local resolve = E:LayoutRectangles(function(name)
		local texture = textures[name]
		if not texture or texture:GetNumPoints() ~= 1 then return end
		local p, rel, rp, dx, dy = texture:GetPoint(1)
		local w, h = texture:GetSize()
		local s = texture:GetEffectiveScale()
		if not K.Plain(p, rel, rp) or not Number(s, true) or not Number(w, true) or not Number(h, true)
			or not (rel == frame or known[rel]) then return end
		return { p, "UIParent", rp, dx, dy }, w * s / parentScale, h * s / parentScale,
			known[rel], rel == frame and root or nil, s / parentScale
	end)
	local bounds = { root[1], root[2], root[3], root[4] }
	for name, texture in pairs(textures) do
		if texture:IsShown() then
			local rect = resolve(name)
			if not rect then return nil, nil, "texture" end
			bounds[1], bounds[2] = math.min(bounds[1], rect[1]), math.min(bounds[2], rect[2])
			bounds[3], bounds[4] = math.max(bounds[3], rect[3]), math.max(bounds[4], rect[4])
		end
	end
	return owned.holder, bounds
end

local function DurabilityLayoutChanged(frame)
	if not E.MinimapClusterEnabled or not E:MinimapClusterEnabled() then return end
	local owned = durabilityPin
	if frame ~= _G.DurabilityFrame or not owned or owned.frame ~= frame then return end
	local holder, _, reason = M:DurabilityLayoutBounds()
	if reason or not DurabilityAllowed("move") or DurabilityAllowed("hide") then return end
	if holder then E.CombatKit.FitHolder(holder, frame, 40, 40) end
	-- Finish the native resize before the layout measures the owned cluster.
	if E.RefreshMinimapCluster then E:RefreshMinimapCluster() end
end

function M:ApplyDurability()
	local frame = _G.DurabilityFrame
	local K = E.CombatKit
	if not (frame and K) then return end
	local hide = DurabilityAllowed("hide")
	local move = DurabilityAllowed("move") and not hide
	if not (hide or move or durabilityTouched) then return end
	durabilityTouched = hide or move
	if hide then K.Parent(frame, K.hider) else K.RestoreParent(frame) end
	if move then
		local holder = K.Holder(self, DURABILITY_MOVER, L["Durability Figure"], { "TOPRIGHT", "UIParent", "TOPRIGHT", -230, -230 }, 60, 75)
		local spec = {
			anchor = function() return "CENTER", holder, "CENTER", 0, 0 end,
			scale = function() return M.db.durabilityScale end,
			active = function() return DurabilityAllowed("move") and not DurabilityAllowed("hide") end,
		}
		K.Pin(frame, spec)
		K.FitHolder(holder, frame, 40, 40)
		durabilityPin = { frame = frame, holder = holder, spec = spec, parent = frame:GetParent() }
		if E.MinimapClusterEnabled and E:MinimapClusterEnabled() and not durabilityLayoutHooks[frame] and type(frame.SetAlerts) == "function" then
			durabilityLayoutHooks[frame] = true
			hooksecurefunc(frame, "SetAlerts", DurabilityLayoutChanged)
		end
	else
		durabilityPin = nil
		K.Unpin(frame)
	end
	if E.RefreshMinimapCluster then E:RefreshMinimapCluster() end
end

E:RegisterBlizzardHandler(DURABILITY, {
	owner = "QoL",
	apply = function() E:OnBlizzardAddOn("Blizzard_DurabilityFrame", function() M:ApplyDurability() end) end,
	undo = function() M:ApplyDurability() end,
	install = { move = true },
	legacy = function() return false end,
})

---------------------------------------------------------------------------
-- Screen edge panels: thin bars across the top and bottom edge of
-- the screen that frame the UI. Decoration only; layouts that want them
-- turn them on.
---------------------------------------------------------------------------
local edges = {}

local function EdgePanel(side)
	local panel = edges[side]
	if panel then return panel end
	panel = CreateFrame("Frame", nil, UIParent)
	panel:SetFrameStrata("BACKGROUND")
	panel:SetFrameLevel(0)
	panel:EnableMouse(false)
	panel.line = panel:CreateTexture(nil, "ARTWORK")
	panel.line:SetHeight(E.pixel)
	if side == "TOP" then
		panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -E.pixel, E.pixel)
		panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", E.pixel, E.pixel)
		panel.line:SetPoint("BOTTOMLEFT", 0, 0)
		panel.line:SetPoint("BOTTOMRIGHT", 0, 0)
	else
		panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -E.pixel, -E.pixel)
		panel:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", E.pixel, -E.pixel)
		panel.line:SetPoint("TOPLEFT", 0, 0)
		panel.line:SetPoint("TOPRIGHT", 0, 0)
	end
	edges[side] = panel
	return panel
end

function M:ApplyEdgePanels()
	local db = self.db
	for side, on in pairs({ TOP = db.edgeTop, BOTTOM = db.edgeBottom }) do
		local wanted = self.active and on
		if wanted or edges[side] then
			local panel = EdgePanel(side)
			if wanted then
				panel:SetHeight(math.max(4, db.edgeHeight))
				E:SetPanelTemplate(panel, db.edgeTransparent)
				E:AccentTexture(panel.line, 1)
				panel.line:SetShown(db.edgeAccent)
				panel:Show()
			else
				panel:Hide()
			end
		end
	end
end

-- The edge panels (read-only).
function M:EdgePanels()
	return edges.TOP, edges.BOTTOM
end

-- Camera and screenshot settings through E:SetCVar (owner "Tweaks", the
-- name these rows had before the merge, so values EldoUI saved then still
-- come back; QoL's own rows use the owner "QoL"): the player's own value
-- is remembered and put back when a tick goes off.
local CVAR_OWNER = "Tweaks"

local function SetOwned(name, value)
	if C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(name) ~= nil then E:SetCVar(name, value, CVAR_OWNER) end
end

local function Restore(name)
	E:RestoreCVar(name, CVAR_OWNER)
end

-- Can the game take this setting now? Missing or read-only settings never;
-- settings the game guards in combat wait until it ends.
local function CVarInfo(name)
	if not (C_CVar and C_CVar.GetCVarInfo) then
		return C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(name) ~= nil, false, false
	end
	local ok, value, _, _, _, locked, secure, readOnly = pcall(C_CVar.GetCVarInfo, name)
	if not ok or value == nil then return false, false, false end
	return true, (locked or readOnly) and true or false, secure and true or false
end

-- `done` runs right after the value was written. A protected setting
-- refuses an addon's write, so it is left alone.
local function SetCamera(name, value, done)
	local exists, blocked, secure = CVarInfo(name)
	if not exists or blocked or secure then return end
	SetOwned(name, value)
	if done then done() end
end

---------------------------------------------------------------------------
-- ActionCam: the shoulder offset eases in as the camera zooms out. A light
-- tick on the shared ticker reads the camera distance and writes the offset only when it
-- moved; if the setting changed under it (the game's experimental warning,
-- Disable), ActionCam turns off and stays off.
---------------------------------------------------------------------------
local SHOULDER_CVAR, PITCH_CVAR = "test_cameraOverShoulder", "test_cameraDynamicPitch"
local SHOULDER_TICK = "QoL:shoulder"
local lastShoulder

local function Round(value)
	return math.floor(value * 20 + 0.5) / 20
end

function M:ShoulderOffset()
	local db = self.db
	local full = tonumber(db.shoulder) or 0
	if not db.shoulderEase then return Round(full) end
	local zoom = E.PlainCall(GetCameraZoom)
	if type(zoom) ~= "number" then return Round(full) end
	local reach = math.max(1, tonumber(db.shoulderEaseDistance) or 15)
	return Round(full * math.max(0, math.min(1, zoom / reach)))
end

local function StopShoulder()
	E.Ticker:Unsubscribe(SHOULDER_TICK)
	lastShoulder = nil
end

-- The game (or the player) put the offset back: leave ActionCam off.
local function ShoulderReset()
	if lastShoulder == nil then return false end
	local now = tonumber(E.Plain(C_CVar.GetCVar(SHOULDER_CVAR)))
	return now ~= nil and math.abs(now - lastShoulder) > 0.01
end

function M:UpdateShoulder()
	if not (self.active and self.db.actionCam) then return StopShoulder() end
	if ShoulderReset() then
		self.db.actionCam = false
		StopShoulder()
		E:RestoreCVar(SHOULDER_CVAR, CVAR_OWNER)
		E:RestoreCVar(PITCH_CVAR, CVAR_OWNER)
		E:Print(L["ActionCam is off: the game's camera settings were put back."])
		if E.RefreshConfig then E:RefreshConfig() end
		return
	end
	local offset = self:ShoulderOffset()
	if offset ~= lastShoulder then
		SetCamera(SHOULDER_CVAR, offset)
		lastShoulder = tonumber(E.Plain(C_CVar.GetCVar(SHOULDER_CVAR))) or offset
	end
end

function M:ApplyActionCam()
	local db, on = self.db, self.active
	if not (on and db.actionCam and CVarInfo(SHOULDER_CVAR)) then
		StopShoulder()
		Restore(SHOULDER_CVAR)
		Restore(PITCH_CVAR)
		return
	end
	if db.dynamicPitch then SetCamera(PITCH_CVAR, 1) else Restore(PITCH_CVAR) end
	self:UpdateShoulder()
	if db.actionCam and db.shoulderEase then
		if not E.Ticker:IsSubscribed(SHOULDER_TICK) then E.Ticker:Subscribe(SHOULDER_TICK, 0.1, function() M:UpdateShoulder() end, M) end
	else
		E.Ticker:Unsubscribe(SHOULDER_TICK)
	end
end

-- A camera addon that sets these itself (Modules/Camera.lua): EldoUI
-- neither sets nor puts back the camera settings while it is loaded.
local function CameraAddon()
	if E.FeatureConflict then return E:FeatureConflict("camera") end
end

function M:ApplyCVars()
	local db, on = self.db, self.active
	if CameraAddon() then
		StopShoulder()
	elseif on and db.setMaxZoom then
		local cap = E.CameraZoomCap and E:CameraZoomCap() or 2.6
		local wanted = math.max(1, math.min(tonumber(db.maxZoom) or cap, cap))
		-- What the game kept tells the real limit.
		SetCamera("cameraDistanceMaxZoomFactor", wanted, function()
			if E.NoteCameraZoom then E:NoteCameraZoom(wanted) end
		end)
	else
		Restore("cameraDistanceMaxZoomFactor")
	end
	if not CameraAddon() then
		if on and db.setZoomSpeed then SetCamera("cameraZoomSpeed", math.max(1, math.min(50, tonumber(db.zoomSpeed) or 20))) else Restore("cameraZoomSpeed") end
	end
	if on and db.setScreenshots then
		SetOwned("screenshotQuality", db.screenshotQuality)
		SetOwned("screenshotFormat", db.screenshotFormat)
	else
		Restore("screenshotQuality")
		Restore("screenshotFormat")
	end
	if not CameraAddon() then self:ApplyActionCam() end
end

-- "Use the largest distance this client allows": read the limit from the
-- game, then keep the max distance there.
function M:UseLargestZoom()
	if not E.ProbeCameraZoomCap or CameraAddon() then return end
	local function Go()
		local cap = E:ProbeCameraZoomCap()
		if not cap then return end
		self.db.setMaxZoom = true
		self.db.maxZoom = math.floor(cap * 10 + 0.0001) / 10
		self:ApplyCVars()
		local text = L["Max camera distance: %.1f (%d yd), the largest this client allows."]:format(self.db.maxZoom, math.floor(E:CameraYards(self.db.maxZoom)))
		if E.ConfigNotice then E:ConfigNotice(text) else E:Print(text) end
		if E.RefreshConfig then E:RefreshConfig() end
	end
	if not E:RunOutOfCombat(Go, "qol:largestzoom") then E:Print(L["The camera distance is set after combat."]) end
end

---------------------------------------------------------------------------
-- Game setting shortcuts
---------------------------------------------------------------------------
local function CVarExists(name)
	if C_CVar and C_CVar.GetCVarInfo then
		local ok, value = pcall(C_CVar.GetCVarInfo, name)
		return ok and value ~= nil
	end
	return C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(name) ~= nil or false
end

local function CVarValue(name)
	if not (C_CVar and C_CVar.GetCVar) then return nil end
	return C_CVar.GetCVar(name)
end

-- On/off CVars shown as a three-way choice: the game's value, on, off.
local SWITCH_CVARS = {
	{ key = "autoSelfCast", cvar = "autoSelfCast" },
	{ key = "autoPushSpells", cvar = "AutoPushSpellToActionBar" },
	{ key = "compareItems", cvar = "alwaysCompareItems" },
}

-- The self-cast modifier is a key binding setting, not a CVar. The
-- player's own key is kept per character (EldoUI's private settings) the
-- first time EldoUI changes it, and put back on "Game setting".
local MODIFIERS = { NONE = true, ALT = true, CTRL = true, SHIFT = true }

-- The per-character store keeps its "Tweaks" name from before the merge.
E:RegisterPrivate("Tweaks", {})

local function TweaksPrivate()
	return E.private and E:GetPrivate("Tweaks") or nil
end

local function SaveModifierBindings()
	if SaveBindings and GetCurrentBindingSet then pcall(SaveBindings, GetCurrentBindingSet()) end
end

local function SetSelfCastKey(key)
	if not (GetModifiedClick and SetModifiedClick) then return end
	E:RunOutOfCombat(function()
		local current = GetModifiedClick("SELFCAST")
		local private = TweaksPrivate()
		if key == "game" then
			local saved = private and private.selfCastKey
			if saved and saved ~= "" then
				if current ~= saved then
					SetModifiedClick("SELFCAST", saved)
					SaveModifierBindings()
				end
				private.selfCastKey = nil
			end
			return
		end
		if not MODIFIERS[key] or current == key then return end
		if private and not private.selfCastKey then private.selfCastKey = current end
		SetModifiedClick("SELFCAST", key)
		SaveModifierBindings()
	end)
end

-- "Screenshot saved": Blizzard's ActionStatus frame shows it on
-- SCREENSHOT_SUCCEEDED. Hiding it takes the frame off that one event (no
-- frame code is changed); switching back registers the event again.
local screenshotMuted = false

local function MuteScreenshotMessage(mute)
	local frame = _G.ActionStatus
	if not (frame and frame.UnregisterEvent) then return end
	if mute and not screenshotMuted then
		frame:UnregisterEvent("SCREENSHOT_SUCCEEDED")
		screenshotMuted = true
	elseif not mute and screenshotMuted then
		frame:RegisterEvent("SCREENSHOT_SUCCEEDED")
		screenshotMuted = false
	end
end

local function Clamp(value, low, high, fallback)
	value = tonumber(value) or fallback
	return math.floor(math.max(low, math.min(high, value)) + 0.5)
end

function M:ApplyGameSettings()
	local db, on = self.db, self.active
	for _, row in ipairs(SWITCH_CVARS) do
		local value = on and db[row.key] or "game"
		if value == "on" or value == "off" then
			SetOwned(row.cvar, value == "on" and 1 or 0)
		else
			Restore(row.cvar)
		end
	end
	if on and db.setSpellQueue then SetOwned("SpellQueueWindow", Clamp(db.spellQueue, 0, 400, 400)) else Restore("SpellQueueWindow") end
	if on and db.setGraphics then SetOwned("graphicsQuality", Clamp(db.graphicsQuality, 1, 10, 5)) else Restore("graphicsQuality") end
	SetSelfCastKey(on and db.selfCastKey or "game")
	if on and db.hideScreenshotMsg then
		E:OnBlizzardAddOn("Blizzard_ActionStatus", function() MuteScreenshotMessage(M.active and M.db.hideScreenshotMsg) end)
	else
		MuteScreenshotMessage(false)
	end
end

-- Every game setting back to the player's own value, and every row back to
-- "Game setting" (camera and screenshot ticks included).
function M:RestoreGameSettings()
	local db = self.db
	for _, row in ipairs(SWITCH_CVARS) do db[row.key] = "game" end
	db.selfCastKey = "game"
	db.setSpellQueue, db.setGraphics, db.hideScreenshotMsg = false, false, false
	db.setMaxZoom, db.setScreenshots, db.setZoomSpeed, db.actionCam = false, false, false, false
	StopShoulder()
	E:RestoreCVars(CVAR_OWNER)
	SetSelfCastKey("game")
	MuteScreenshotMessage(false)
	self:RunParts("restore")
	if E.RefreshConfig then E:RefreshConfig() end
end

-- Which of the settings this client has, for bug reports (/eui gamesettings
-- and /eui diag).
local DIAG_CVARS = { "autoSelfCast", "AutoPushSpellToActionBar", "SpellQueueWindow", "alwaysCompareItems",
	"graphicsQuality", "cameraDistanceMaxZoomFactor", "cameraZoomSpeed", "test_cameraOverShoulder", "test_cameraDynamicPitch",
	"screenshotQuality", "screenshotFormat" }

function M:GameSettingLines()
	local lines = { "   " .. E:TextHex("accent") .. "Game settings (Quality of Life)|r" }
	for _, name in ipairs(DIAG_CVARS) do
		local value
		if CVarExists(name) then
			local owned = E.CVarOwner and E:CVarOwner(name) == CVAR_OWNER
			value = tostring(CVarValue(name)) .. (owned and " " .. E:TextHex("good") .. "(set by EldoUI)|r" or "")
		else
			value = E:TextHex("secondary") .. "not on this client|r"
		end
		lines[#lines + 1] = ("   %s: %s"):format(name, value)
	end
	local key = GetModifiedClick and GetModifiedClick("SELFCAST")
	lines[#lines + 1] = ("   Self-cast key: %s"):format(key and tostring(key) or E:TextHex("secondary") .. "not on this client|r")
	lines[#lines + 1] = ("   Screenshot message frame: %s"):format(_G.ActionStatus and "found" or E:TextHex("secondary") .. "not loaded|r")
	return lines
end

E:AddCommand("gamesettings", "list the game settings Quality of Life can change and whether this client has them", function()
	for _, line in ipairs(M:GameSettingLines()) do E:Print(line) end
end, "Tools")

-- The same rows at the end of /eui diag.
E:RegisterDiagnostics("Quality of Life", function() return M:GameSettingLines() end)

---------------------------------------------------------------------------
-- The merge into Quality of Life: a profile's Tweaks settings move into
-- QoL's once (E:RegisterProfileMigration runs it whenever a profile is
-- used, copied in or brought up to date after login; it does nothing once
-- modules.Tweaks is gone). Both modules were on by default. When one of
-- them was off, its features stay off in the merged module, so nothing
-- starts acting after the update: Tweaks off -> its rows go to their off
-- values; QoL off and Tweaks on -> the module stays on with QoL's own
-- features off. The per-character on/off (Profiles > per character)
-- follows the same rule, for each character when it logs in. The private
-- per-character store keeps its "Tweaks" name, and so do the CVar owner
-- and the durability figure's mover.
---------------------------------------------------------------------------
local TWEAKS_OFF = {
	autoAccept = false, autoTurnIn = false, skipGossip = false, rewardValue = false, combatAlert = false,
	setMaxZoom = false, setScreenshots = false, setZoomSpeed = false, actionCam = false, selfCastKey = "game", autoSelfCast = "game", autoPushSpells = "game",
	compareItems = "game", setSpellQueue = false, hideScreenshotMsg = false, setGraphics = false,
	edgeTop = false, edgeBottom = false,
}
local QOL_OFF = {
	summonPrompt = false, resPrompt = false, blockDuels = false, blockInvites = false, blockRequestedInvites = false,
	blockGuildInvites = false, blockSharedQuests = false, filterDuelSpam = false, filterDrunkSpam = false,
	xpBarText = false, trackerButton = false, zoneTracking = false, flightTimer = false, silenceRestedEmotes = false,
	keepAudioSynced = false, muteSounds = "", noScreenEffects = false, weather = "game", volumePanel = false,
	wowheadLinks = false,
}

local function MergeStates()
	local private = E.private and E:GetPrivate("profiles")
	local states = private and private.moduleStates
	if type(states) == "table" and states.Tweaks ~= nil then
		if states.Tweaks and states.QoL == false then states.QoL = true end
		states.Tweaks = nil
	end
end

function M.MergeTweaks(profile)
	MergeStates()
	local modules = type(profile) == "table" and type(profile.modules) == "table" and profile.modules
	local old = modules and modules.Tweaks
	if type(old) ~= "table" then return false end
	local qol = type(modules.QoL) == "table" and modules.QoL or {}
	modules.QoL = qol
	local tweaksOn, qolOn = old.enabled ~= false, qol.enabled ~= false
	-- Every key, older ones too (Messages and System UI pick those up);
	-- the style preset name meant Tweaks' own list, so it stays behind.
	for key, value in pairs(old) do
		if key ~= "enabled" and key ~= "style" and qol[key] == nil then
			qol[key] = type(value) == "table" and CopyTable(value) or value
		end
	end
	if not tweaksOn then
		for key, value in pairs(TWEAKS_OFF) do qol[key] = value end
		for _, row in ipairs(M.HIDDEN_CVARS or {}) do
			if row.kind == "range" then qol["set" .. row.key] = false else qol[row.key] = "game" end
		end
		-- The figure's switches only worked while Tweaks was on.
		local figure = type(profile.blizzard) == "table" and profile.blizzard[DURABILITY]
		if type(figure) == "table" then figure.enabled = false end
	elseif not qolOn then
		qol.enabled = true
		for key, value in pairs(QOL_OFF) do qol[key] = value end
	end
	modules.Tweaks = nil
	return true
end
E:RegisterProfileMigration(M.MergeTweaks)

local QUEST_EVENTS = { "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_GREETING", "GOSSIP_SHOW",
	"QUEST_ACCEPTED", "QUEST_FINISHED" }

-- This part's place in the module's life cycle (Modules/QoL.lua, AddPart).
local Part = {}

function Part.enable(self)
	for _, event in ipairs(QUEST_EVENTS) do self:RegisterEvent(event, OnQuestEvent) end
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function() CombatText(L["+ Combat"], 1, 0.3, 0.3) end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() CombatText(L["- Combat"], 0.3, 1, 0.3) end)
	if not self.rewardHooked and QuestInfo_Display then
		hooksecurefunc("QuestInfo_Display", function() if M.active then M:UpdateRewardValues() end end)
		self.rewardHooked = true
	end
	self:ApplyCVars()
	self:ApplyGameSettings()
	self:ApplyEdgePanels()
	E:OnBlizzardAddOn("Blizzard_DurabilityFrame", function() M:ApplyDurability() end)
end

function Part.disable(self)
	for _, event in ipairs(QUEST_EVENTS) do self:UnregisterEvent(event) end
	self:UnregisterEvent("PLAYER_REGEN_DISABLED")
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	self:UpdateRewardValues()
	self:ApplyCVars()
	self:ApplyGameSettings()
	self:ApplyEdgePanels()
	self:ApplyDurability()
end

function Part.profile(self)
	self:ApplyCVars()
	self:ApplyGameSettings()
	self:ApplyEdgePanels()
	self:ApplyDurability()
end

M:AddPart("Tweaks", Part)

M:AddOptions("Quests", {
	{ type = "header", label = "Quest helpers" },
	{ type = "description", label = "Paused while RestedXP is loaded, because its guide handles quests. Hold the pause key to do a quest by hand." },
	{ type = "toggle", acts = true, key = "autoAccept", label = "Accept quests automatically",
		desc = "Accepts quests from NPCs when their window opens. Quests shared by other players are never accepted. Off by default." },
	{ type = "toggle", acts = true, key = "autoTurnIn", label = "Turn in quests automatically",
		desc = "Hands in finished quests. Stops when there is a reward to choose or the quest costs gold, so you decide yourself. Off by default." },
	{ type = "toggle", key = "leaveRepeatable", label = "Leave repeatable quests to you",
		desc = "The quest helpers skip repeatable quests, such as reputation hand-ins, so a stack is never handed in at once." },
	{ type = "toggle", acts = true, key = "skipGossip", label = "Skip the chat at plain vendors",
		desc = "When an NPC's only option is their shop and they have no quest for you, the shop opens straight away. Off by default." },
	{ type = "toggle", key = "skipTrivial", label = "Leave gray quests alone", dependsOn = "autoAccept",
		desc = "The accept helper skips quests the game shows in gray (too low for your level). You can still take them yourself." },
	{ type = "toggle", key = "oneQuestPerTalk", label = "One quest per talk", dependsOn = "autoAccept",
		desc = "After the helper takes one quest from an NPC, their other quests wait until you talk to them again." },
	{ type = "select", key = "pauseKey", label = "Hold to pause", desc = "Hold this key while talking to an NPC to stop the quest helpers.",
		values = { SHIFT = "Shift", CTRL = "Ctrl", ALT = "Alt" } },
	{ type = "header", label = "Rewards" },
	{ type = "toggle", key = "rewardValue", label = "Sell value on quest rewards",
		desc = "The vendor price in the corner of each reward; the most valuable choice in your accent color, unless Upgrades already marks quest rewards. You still pick." },
})

-- The quest helpers act for the player: listed for the setup's Convenience
-- step and the Conveniences page (Core/Conveniences.lua), off until
-- ticked, and recommended while the character is still leveling.
do
	local Leveling = E.ConvenienceRules.BelowLevelCap
	E:RegisterConvenience({ id = "autoAccept", module = "QoL", setting = "autoAccept", order = 60,
		label = "Accept quests automatically",
		desc = "Acts for you: accepts quests from NPCs when their window opens, never quests other players share.",
		suits = Leveling })
	E:RegisterConvenience({ id = "autoTurnIn", module = "QoL", setting = "autoTurnIn", order = 70,
		label = "Turn in quests automatically",
		desc = "Acts for you: hands in finished quests and stops when there is a reward to choose, so you always pick it.",
		suits = Leveling })
	E:RegisterConvenience({ id = "skipGossip", module = "QoL", setting = "skipGossip", order = 80,
		label = "Skip the chat at plain vendors",
		desc = "Acts for you: when an NPC only has a shop and no quest for you, the shop opens at once.",
		suits = Leveling })
end

-- After the Interface tab's "Screen" section (Modules/QoL.lua).
M:AddOptions("Interface", {
	{ type = "toggle", key = "combatAlert", label = "Show +Combat / -Combat", desc = "A short message when you enter and leave combat." },
	{ type = "header", label = "Durability figure" },
	{ type = "description", label = "The armor figure that shows when your gear is damaged. Move, scale or hide it with its switches on the Blizzard UI page." },
	{ type = "execute", label = "Open Blizzard UI switches", desc = "Choose whether EldoUI moves, scales or hides the durability figure.",
		func = function() E:ToggleConfig("blizzard") end },
	{ type = "range", percent = true, key = "durabilityScale", label = "Durability figure scale", min = 0.5, max = 2, step = 0.05,
		desc = "Size of the figure while EldoUI moves it (switch \"Move and scale\").",
		hidden = function() return not E:BlizzardAllowed("durability-figure", "move") end },
	{ type = "header", label = "Screen edge panels" },
	{ type = "toggle", key = "edgeTop", label = "Top edge panel", desc = "A thin bar across the top edge of the screen that frames the interface." },
	{ type = "toggle", key = "edgeBottom", label = "Bottom edge panel", desc = "A thin bar across the bottom edge of the screen that frames the interface." },
	{ type = "range", unit = "px", key = "edgeHeight", label = "Panel height", min = 4, max = 60, step = 1, desc = "Height of the edge panels.",
		hidden = function() return not (M.db.edgeTop or M.db.edgeBottom) end },
	{ type = "toggle", key = "edgeTransparent", label = "See-through background", desc = "The panels let the game show through a little. How much: General > Panel opacity.",
		hidden = function() return not (M.db.edgeTop or M.db.edgeBottom) end },
	{ less = true, type = "toggle", key = "edgeAccent", label = "Accent line", desc = "A thin line in your accent color on the inner edge of each panel.",
		hidden = function() return not (M.db.edgeTop or M.db.edgeBottom) end },
})

-- Rows for settings this client may lack are hidden when it does.
local function HasCVar(cvar)
	return function() return CVarExists(cvar) end
end

-- The max distance slider ends where this client stops (Modules/Camera.lua);
-- a distance in yards ends at the yards that limit gives.
local function CapSlider(rows)
	local cap = E.CameraZoomCap and E:CameraZoomCap() or 2.6
	local yards = E.CameraYards and math.floor(E:CameraYards(cap)) or 39
	for _, row in ipairs(rows) do
		if row.zoomCap then row.max = cap end
		if row.zoomYards then row.max = yards end
		if row.cog then CapSlider(row.cog) end
	end
	return rows
end

-- While a camera addon is loaded the camera rows say why they are off.
local function CameraRowsOff()
	local addon, title = CameraAddon()
	if not addon then return nil end
	return L["%s handles the camera settings while it is loaded."]:format(title)
end

local CAMERA_OPTIONS = {
	{ type = "header", label = "Camera and screenshots" },
	{ type = "toggle", key = "setMaxZoom", label = "Set the max camera distance", disabled = CameraRowsOff, desc = "EldoUI sets how far the camera can zoom out. Off puts your own value back." },
	{ type = "range", key = "maxZoom", label = "Max camera distance", min = 1, max = 2.6, step = 0.1, zoomCap = true, disabled = CameraRowsOff,
		desc = function()
			local db = M.db
			local yards = E.CameraYards and math.floor(E:CameraYards(db and db.maxZoom or 2.6)) or 39
			return L["How far the camera can zoom out (game setting): now about %d yd. The range follows what this client allows."]:format(yards)
		end,
		hidden = function() return not M.db.setMaxZoom end },
	{ type = "execute", label = "Use the largest distance", requiresAPI = "C_CVar.GetCVar", disabled = CameraRowsOff,
		desc = "Reads the largest camera distance this client allows from the game and sets the max camera distance to it. Off (the tick above) puts your own value back.",
		func = function() M:UseLargestZoom() end },
	{ type = "toggle", key = "setZoomSpeed", label = "Set the zoom speed", requires = HasCVar("cameraZoomSpeed"), disabled = CameraRowsOff,
		desc = "EldoUI sets how fast the camera zooms with the mouse wheel. Off puts your own value back." },
	{ type = "range", key = "zoomSpeed", label = "Zoom speed", min = 1, max = 50, step = 1, requires = HasCVar("cameraZoomSpeed"), dependsOn = "setZoomSpeed",
		desc = "Higher zooms faster; the game's default is 20 (game setting)." },
	{ type = "toggle", key = "actionCam", label = "ActionCam", requires = HasCVar("test_cameraOverShoulder"), disabled = CameraRowsOff,
		desc = "An over-the-shoulder view. It uses the game's experimental camera settings: the game asks you once to confirm them, and Disable there turns ActionCam off. Off puts your own values back.",
		cog = {
			{ type = "range", key = "shoulder", label = "Shoulder offset", unit = "yd", min = -2, max = 2, step = 0.1,
				desc = "How far the camera sits to the side of your character; below 0 is the left shoulder." },
			{ type = "toggle", key = "shoulderEase", label = "Ease in with zoom",
				desc = "The offset grows as you zoom out and is gone up close, so the character stays in the middle when you zoom in." },
			{ type = "range", key = "shoulderEaseDistance", label = "Full offset from", unit = "yd", min = 2, max = 39, step = 1, zoomYards = true, dependsOn = "shoulderEase",
				desc = "The camera distance where the whole offset applies." },
			{ type = "toggle", key = "dynamicPitch", label = "Dynamic pitch", requires = HasCVar("test_cameraDynamicPitch"),
				desc = "The camera tilts up a little as you zoom out, so you see more ahead of you." },
		} },
	{ type = "toggle", key = "setScreenshots", label = "Set screenshot quality and format", desc = "EldoUI sets the screenshot settings below. Off puts your own values back." },
	{ type = "range", key = "screenshotQuality", label = "Screenshot quality", desc = "10 is the best quality (game setting).", min = 1, max = 10, step = 1,
		hidden = function() return not M.db.setScreenshots end },
	{ type = "select", key = "screenshotFormat", label = "Screenshot format", desc = "File type of screenshots (game setting).", values = { png = "PNG", jpg = "JPG", tga = "TGA" },
		hidden = function() return not M.db.setScreenshots end },
}
M:AddOptions(E.Key("Sound and misc"), CapSlider(CAMERA_OPTIONS))
-- A limit read from the game later resizes the slider.
if E.Camera then E.Camera.OnCapChanged = function() CapSlider(CAMERA_OPTIONS) end end

-- "Game setting (now on)" as the first choice of a three-way row.
local function SwitchValues(cvar)
	return function()
		local value = CVarValue(cvar)
		local now = value == "1" and L["on"] or value == "0" and L["off"] or tostring(value or "?")
		return { game = L["Game setting (now %s)"]:format(now), on = "On", off = "Off" }
	end
end

local function Requires(cvar)
	return function() return CVarExists(cvar) end
end

local GAME_OPTIONS = {
	{ type = "header", label = "Game settings" },
	{ type = "description", label = "Shortcuts to the game's settings. EldoUI writes a row only once you pick a value; \"Game setting\" brings your own value back." },
	{ type = "select", key = "selfCastKey", label = "Self-cast key", requiresAPI = { "GetModifiedClick", "SetModifiedClick" },
		values = function()
			local now = GetModifiedClick and GetModifiedClick("SELFCAST")
			return { game = L["Game setting (now %s)"]:format(now and tostring(now):lower() or "?"),
				NONE = "None", ALT = "Alt", CTRL = "Ctrl", SHIFT = "Shift" }
		end,
		desc = "Hold this key while casting a helpful spell to cast it on yourself (the game's key binding setting)." },
	{ type = "select", key = "autoSelfCast", label = "Auto self-cast", requires = Requires("autoSelfCast"), values = SwitchValues("autoSelfCast"),
		desc = "Helpful spells cast without a friendly target land on you (game setting)." },
	{ type = "select", key = "autoPushSpells", label = "Put new spells on the bars", requires = Requires("AutoPushSpellToActionBar"),
		values = SwitchValues("AutoPushSpellToActionBar"),
		desc = "When you learn a spell, the game places it on a free action button by itself (game setting). EldoUI keeps it off while new spells go to their key automatically." },
	{ type = "select", key = "compareItems", label = "Always compare items", requires = Requires("alwaysCompareItems"), values = SwitchValues("alwaysCompareItems"),
		desc = "Item tooltips always show what you wear in that slot beside them, without holding Shift (game setting)." },
	{ type = "toggle", key = "setSpellQueue", label = "Set the spell queue window", requires = Requires("SpellQueueWindow"),
		desc = function()
			return L["How early you can queue your next spell before the current cast or global cooldown ends (\"lag tolerance\"). Off keeps the game's value (now %s ms)."]:format(tostring(CVarValue("SpellQueueWindow") or "?"))
		end },
	{ type = "range", key = "spellQueue", label = "Spell queue window", unit = "ms", min = 0, max = 400, step = 10, requires = Requires("SpellQueueWindow"),
		dependsOn = "setSpellQueue",
		desc = "Lower values suit a low latency; the game's default is 400 ms. Only written while the box above is checked." },
	{ type = "toggle", key = "hideScreenshotMsg", label = "Hide \"screenshot saved\"",
		desc = "No \"Screen captured\" text in the middle of the screen after a screenshot. A failed screenshot still says so." },
	{ type = "toggle", key = "setGraphics", label = "Set graphics quality", requires = Requires("graphicsQuality"),
		desc = "Pick one of the game's own graphics quality steps with the gear. Off keeps your own graphics settings.",
		cog = {
			{ type = "range", key = "graphicsQuality", label = "Graphics quality", min = 1, max = 10, step = 1, requires = Requires("graphicsQuality"),
				desc = "The game's quality preset: 1 is fastest, 10 looks best. The detailed graphics settings follow the step, as in the game's own menu." },
		} },
	{ type = "execute", label = "Restore game settings",
		desc = "Puts every game setting EldoUI changed (these rows, camera and screenshots) back to your own values and sets the rows to \"Game setting\".",
		func = function() M:RestoreGameSettings() end },
}
M:AddOptions(E.Key("Sound and misc"), GAME_OPTIONS)
