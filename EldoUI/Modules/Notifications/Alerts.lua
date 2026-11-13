-- EldoUI Notifications: alerts, toasts and banners, the talking head
-- and EldoUI's own alert lane.
--
--   Skin     flat EldoUI box behind each alert, no glow or shine flash
--   Move     one "Alert lane" mover for every alert, growing up or down;
--            level-up/event toasts and boss banners on the "Banners" mover;
--            Battle.net toasts and the GM ticket status on their own mover
--   Hide     per type: achievements, loot won, money, recipes, collections,
--            instance completions, other, level-up, events, boss banner and
--            Battle.net toasts
--   Replace  EldoUI's own lane draws achievements, level-up, quest
--            complete, loot won, recipes, collections and boss kills
--
-- Taint notes: Blizzard's alert frames are not protected. EldoUI only
-- hooks (AddAlertFrame, UpdateAnchors, DisplayToast, PlayCurrent), changes
-- points, scale and alpha, and adds child frames. AlertFrame's own fields
-- (baseAnchorFrame, ...) are never written.
local _, E = ...
local L = E.L
local M = E:GetModule("Notifications")
local U = M.util

local ALERTS = "alert-toasts"
local HEAD = "talking-head"

---------------------------------------------------------------------------
-- Alert types
---------------------------------------------------------------------------
local SYSTEM_TYPES = {
	AchievementAlertSystem = "achievement", CriteriaAlertSystem = "achievement",
	GuildChallengeAlertSystem = "achievement", MonthlyActivityAlertSystem = "achievement",
	LootAlertSystem = "loot", LootUpgradeAlertSystem = "loot", LegendaryItemAlertSystem = "loot",
	MoneyWonAlertSystem = "money", HonorAwardedAlertSystem = "money",
	NewRecipeLearnedAlertSystem = "recipe", SkillLineSpecsUnlockedAlertSystem = "recipe",
	NewPetAlertSystem = "collection", NewMountAlertSystem = "collection", NewToyAlertSystem = "collection",
	NewCosmeticAlertFrameSystem = "collection", NewWarbandSceneAlertSystem = "collection",
	NewRuneforgePowerAlertSystem = "collection", HousingItemEarnedAlertFrameSystem = "collection",
	DungeonCompletionAlertSystem = "instance", ScenarioAlertSystem = "instance",
	InvasionAlertSystem = "instance", WorldQuestCompleteAlertSystem = "instance",
}
local typeOfSystem

local function AlertType(frame)
	if not typeOfSystem then
		typeOfSystem = {}
		for name, kind in pairs(SYSTEM_TYPES) do
			if type(_G[name]) == "table" then typeOfSystem[_G[name]] = kind end
		end
	end
	return frame and frame.queue and typeOfSystem[frame.queue] or "other"
end

-- Level-up toasts in the middle of the screen; everything else there
-- (quest and zone events) is "events".
local function EventToastType(info)
	local types = Enum and Enum.EventToastEventType
	local kind = info and U.Safe(info.eventType)
	if types and kind and (kind == types.LevelUp or kind == types.LevelUpSpell or kind == types.LevelUpDungeon
		or kind == types.LevelUpRaid or kind == types.LevelUpPvP) then
		return "levelup"
	end
	return "events"
end

-- Which of Blizzard's types EldoUI's own lane draws (Replace switch).
local LANE_KEY = { achievement = "achievement", loot = "loot", recipe = "recipe", collection = "collection", levelup = "levelup", bossBanner = "boss" }

local function LaneDraws(key)
	return U.Allowed(ALERTS, "replace") and LANE_KEY[key] and M.db.alerts.lane[LANE_KEY[key]] and true or false
end

-- True when Blizzard's alert of this type should not show.
local function TypeHidden(key)
	if not U.Allowed(ALERTS) then return false end
	if LaneDraws(key) then return true end
	local state = E:BlizzardState(ALERTS)
	return state.hide and M.db.alerts.hide[key] and true or false
end
M.AlertTypeHidden = TypeHidden

---------------------------------------------------------------------------
-- Skin for Blizzard's alert frames: art invisible, an EldoUI box behind.
---------------------------------------------------------------------------
local ALERT_ART = { "Background", "Background2", "Background3", "BGAtlas", "Border", "IconBorder", "BorderTexture",
	"GuildBanner", "GuildBorder", "Unlocked", "BackgroundFrame" }
local alertSkins = setmetatable({}, { __mode = "k" })

local function SkinAlert(frame, on)
	local parts = alertSkins[frame]
	if on and not parts then
		parts = { art = {} }
		for _, key in ipairs(ALERT_ART) do
			local region = frame[key]
			if type(region) == "table" and region.SetAlpha and region.IsObjectType and region:IsObjectType("Texture") then
				parts.art[#parts.art + 1] = region
			end
		end
		parts.bd = CreateFrame("Frame", nil, frame)
		parts.bd:SetPoint("TOPLEFT", 8, -8)
		parts.bd:SetPoint("BOTTOMRIGHT", -8, 8)
		parts.bd:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))
		alertSkins[frame] = parts
	end
	if not parts then return end
	if on then
		E:SetPanelTemplate(parts.bd, true)
		parts.bd:Show()
		for _, region in ipairs(parts.art) do U.SetAlpha(region, 0) end
	else
		parts.bd:Hide()
		for _, region in ipairs(parts.art) do U.RestoreAlpha(region) end
	end
end

local function StopAlert(frame)
	if frame.animIn then frame.animIn:Stop() end
	if frame.glow and frame.glow.animIn then frame.glow.animIn:Stop() end
	if frame.shine and frame.shine.animIn then frame.shine.animIn:Stop() end
	if frame.waitAndAnimOut then frame.waitAndAnimOut:Stop() end
	frame:Hide()
end

function M:OnBlizzardAlert(frame)
	if not frame or not U.Allowed(ALERTS) then return end
	local kind = AlertType(frame)
	if TypeHidden(kind) then
		StopAlert(frame)
		return
	end
	local skin = U.Allowed(ALERTS, "skin")
	SkinAlert(frame, skin)
	if skin and self.db.alerts.hideGlow then
		if frame.glow then frame.glow:Hide() end
		if frame.shine then frame.shine:Hide() end
	end
	if U.Allowed(ALERTS, "move") then
		U.SetScale(frame, self.db.alerts.scale)
	else
		U.RestoreScale(frame)
	end
end

local function EachBlizzardAlert(fn)
	if not (AlertFrame and type(AlertFrame.alertFrameSubSystems) == "table") then return end
	for _, system in ipairs(AlertFrame.alertFrameSubSystems) do
		local pool = system.alertFramePool
		if pool and pool.EnumerateActive then
			for frame in pool:EnumerateActive() do fn(frame) end
		end
	end
end

---------------------------------------------------------------------------
-- The lane: talking head (when it lives there), EldoUI's toasts, then
-- Blizzard's alerts, one chain from the "Alert lane" mover.
---------------------------------------------------------------------------
local toasts = {}      -- EldoUI toasts on screen, oldest first
local laying = false

local function HeadInLane()
	return U.Allowed(HEAD, "move") and not U.Allowed(HEAD, "hide") and M.db.talkingHead.anchor == "lane"
end

-- M.laneTail: the last frame of the chain after each layout (nil when the
-- lane is empty or not EldoUI's), so EldoUI's alert cards can line up
-- after it without looking at any other frame.
function M:LayoutLane()
	if laying then return end
	if not self.active then self.laneTail = nil return end
	local moveAlerts = U.Allowed(ALERTS, "move")
	local ownLane = U.Allowed(ALERTS, "replace")
	if not (moveAlerts or ownLane or HeadInLane()) then self.laneTail = nil return end
	laying = true
	local lane = U.Holder("AlertLane")
	local down = self.db.alerts.growth == "DOWN"
	local spacing = self.db.alerts.spacing or 4
	local previous
	local function Place(frame, gap)
		frame:ClearAllPoints()
		if not previous then
			if down then frame:SetPoint("TOP", lane, "TOP", 0, 0) else frame:SetPoint("BOTTOM", lane, "BOTTOM", 0, 0) end
		elseif down then
			frame:SetPoint("TOP", previous, "BOTTOM", 0, -gap)
		else
			frame:SetPoint("BOTTOM", previous, "TOP", 0, gap)
		end
		previous = frame
	end
	-- The talking head is pinned; it only starts the chain.
	if HeadInLane() and TalkingHeadFrame and TalkingHeadFrame:IsShown() then
		U.Pin(TalkingHeadFrame, lane, down and "TOP" or "BOTTOM", down and "TOP" or "BOTTOM", 0, 0, HeadInLane)
		previous = TalkingHeadFrame
	end
	if ownLane then
		for _, toast in ipairs(toasts) do Place(toast, spacing) end
	end
	if moveAlerts then
		-- Blizzard's own gap between alerts is 10 px; the alert art has
		-- empty edges, so the setting is added to a smaller base.
		EachBlizzardAlert(function(frame) Place(frame, spacing) end)
	end
	self.laneTail = previous
	laying = false
end

---------------------------------------------------------------------------
-- Banners: level-up / event toasts and the boss banner.
---------------------------------------------------------------------------
local function BannersMoved() return U.Allowed(ALERTS, "move") end

function M:OnEventToast()
	local manager = EventToastManagerFrame
	if not manager or not U.Allowed(ALERTS) then return end
	local toast = manager.currentDisplayingToast
	if not toast then return end
	if TypeHidden(EventToastType(toast.toastInfo)) then
		U.SetAlpha(manager, 0)
		manager:CloseActiveToasts()
	else
		U.RestoreAlpha(manager)
	end
end

---------------------------------------------------------------------------
-- Apply / restore
---------------------------------------------------------------------------
local hooked = false

local function Hook()
	if hooked then return end
	hooked = true
	if AlertFrame and type(AlertFrame.AddAlertFrame) == "function" then
		hooksecurefunc(AlertFrame, "AddAlertFrame", function(_, frame) M:OnBlizzardAlert(frame) end)
	end
	if AlertFrame and type(AlertFrame.UpdateAnchors) == "function" then
		hooksecurefunc(AlertFrame, "UpdateAnchors", function() M:LayoutLane() end)
	end
	if EventToastManagerFrame and EventToastManagerFrame.DisplayToast then
		hooksecurefunc(EventToastManagerFrame, "DisplayToast", function() M:OnEventToast() end)
	end
end

local CVAR_NAMES = { "enableLootToasts", "enableCollectionToasts", "enableLearnedRecipeToasts",
	"showToastOnline", "showToastOffline", "showToastBroadcast", "showToastFriendRequest" }

local function ApplyCVars(on)
	local cvars = M.db.alerts.cvars
	for _, name in ipairs(CVAR_NAMES) do
		local value = on and cvars[name]
		if value == "on" or value == "off" then
			U.SetCVar(name, value == "on" and 1 or 0, ALERTS)
		else
			U.RestoreCVar(name, ALERTS)
		end
	end
	local hideBNet = on and TypeHidden("bnet")
	if hideBNet then U.SetCVar("showToastWindow", 0, ALERTS) else U.RestoreCVar("showToastWindow", ALERTS) end
end

-- Ticket boxes that already restack the toast, kept per box, so a ticket
-- box the game makes again gets its own hooks.
local hookedTickets = setmetatable({}, { __mode = "k" })

local function ApplyAlerts(state)
	Hook()
	local db = M.db.alerts
	-- Move: AlertFrame, banners and every visible alert.
	if state.move then
		local lane = U.Holder("AlertLane")
		lane:SetScale(1)
		if AlertFrame then U.Pin(AlertFrame, lane, "BOTTOM", "BOTTOM", 0, 0, BannersMoved) end
		local banners = U.Holder("Banners")
		if EventToastManagerFrame then
			U.Pin(EventToastManagerFrame, banners, "TOP", "TOP", 0, 0, BannersMoved)
			U.SetScale(EventToastManagerFrame, db.bannerScale)
		end
		if BossBanner then
			U.Pin(BossBanner, banners, "TOP", "TOP", 0, 0, BannersMoved)
			U.SetScale(BossBanner, db.bannerScale)
		end
		-- Battle.net toasts (ChatAlertFrame anchors them to the chat) and
		-- the GM ticket status box (StatusTrayManager, top right) share the
		-- "Battle.net Toasts" mover; a toast goes above an open ticket box.
		-- Both boxes are looked up before either is pinned, so each pin sees
		-- the other.
		local social = U.Holder("SocialToasts")
		local ticket = E:SkinUsable(_G.TicketStatusFrame) and _G.TicketStatusFrame or nil
		local toast = E:SkinUsable(_G.BNToastFrame) and _G.BNToastFrame or nil
		if ticket then
			U.Pin(ticket, social, "BOTTOMLEFT", "BOTTOMLEFT", 0, 0, BannersMoved)
			-- Its 75 px box fits the 60 px mover.
			U.SetScale(ticket, 0.8)
		end
		if toast then
			U.Pin(toast, social, "BOTTOMLEFT", "BOTTOMLEFT", 0, 0, BannersMoved, function()
				if ticket and ticket:IsShown() and U.IsPinned(ticket) then return "BOTTOMLEFT", ticket, "TOPLEFT", 0, 8 end
			end)
			if ticket and not hookedTickets[ticket] then
				hookedTickets[ticket] = true
				-- The toast moves when the ticket box opens or closes.
				local function Restack()
					if U.IsPinned(_G.BNToastFrame) then E.BlizzardKeep.ApplyPin(_G.BNToastFrame) end
				end
				ticket:HookScript("OnShow", Restack)
				ticket:HookScript("OnHide", Restack)
			end
		end
	else
		U.Unpin(AlertFrame)
		U.Unpin(EventToastManagerFrame)
		U.Unpin(BossBanner)
		U.Unpin(_G.BNToastFrame)
		U.Unpin(_G.TicketStatusFrame)
		U.RestoreScale(_G.TicketStatusFrame)
		U.RestoreScale(EventToastManagerFrame)
		U.RestoreScale(BossBanner)
	end
	U.Park(BossBanner, TypeHidden("bossBanner"))
	-- Re-apply skin, scale and type filters on alerts already showing.
	EachBlizzardAlert(function(frame)
		if TypeHidden(AlertType(frame)) then
			StopAlert(frame)
		else
			SkinAlert(frame, state.skin)
			if state.move then U.SetScale(frame, db.scale) else U.RestoreScale(frame) end
		end
	end)
	if EventToastManagerFrame and not EventToastManagerFrame.currentDisplayingToast then U.RestoreAlpha(EventToastManagerFrame) end
	ApplyCVars(true)
	M:UpdateOwnLane()
	if AlertFrame and AlertFrame.UpdateAnchors then
		EachBlizzardAlert(function(frame) frame:ClearAllPoints() end)
		AlertFrame:UpdateAnchors()
	end
end

local function RestoreAlerts()
	U.Unpin(AlertFrame)
	U.Unpin(EventToastManagerFrame)
	U.Unpin(BossBanner)
	U.Unpin(_G.BNToastFrame)
	U.Unpin(_G.TicketStatusFrame)
	U.RestoreScale(_G.TicketStatusFrame)
	U.RestoreScale(EventToastManagerFrame)
	U.RestoreScale(BossBanner)
	U.RestoreAlpha(EventToastManagerFrame)
	U.Park(BossBanner, false)
	EachBlizzardAlert(function(frame)
		SkinAlert(frame, false)
		U.RestoreScale(frame)
		frame:ClearAllPoints()
	end)
	ApplyCVars(false)
	M:UpdateOwnLane()
	if AlertFrame and AlertFrame.UpdateAnchors then AlertFrame:UpdateAnchors() end
end

U.Element(ALERTS, {
	apply = ApplyAlerts,
	restore = RestoreAlerts,
	handler = {
		reload = { skin = true },
		install = { skin = true, move = true },
	},
})

---------------------------------------------------------------------------
-- Talking head
---------------------------------------------------------------------------
local headParts
local headHooked = false

local function HeadSkin()
	local frame = TalkingHeadFrame
	if not headParts then
		headParts = {}
		headParts.bd = CreateFrame("Frame", nil, frame)
		headParts.bd:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -14)
		headParts.bd:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)
		headParts.bd:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))
		headParts.line = headParts.bd:CreateTexture(nil, "ARTWORK")
		headParts.line:SetPoint("TOPLEFT", E.pixel, -E.pixel)
		headParts.line:SetPoint("BOTTOMLEFT", E.pixel, E.pixel)
		headParts.line:SetWidth(E.pixel * 2)
	end
	return headParts
end

-- The art Blizzard sets again on every line (PlayCurrent): textures go,
-- colors and fonts change, after each call.
local function HeadArt()
	local frame = TalkingHeadFrame
	return {
		frame.BackgroundFrame and frame.BackgroundFrame.TextBackground,
		frame.PortraitFrame and frame.PortraitFrame.Portrait,
		frame.MainFrame and frame.MainFrame.Model and frame.MainFrame.Model.PortraitBg,
		frame.MainFrame and frame.MainFrame.Sheen,
		frame.MainFrame and frame.MainFrame.TextSheen,
		frame.MainFrame and frame.MainFrame.Overlay and frame.MainFrame.Overlay.Glow_TopBar,
		frame.MainFrame and frame.MainFrame.Overlay and frame.MainFrame.Overlay.Glow_LeftBar,
		frame.MainFrame and frame.MainFrame.Overlay and frame.MainFrame.Overlay.Glow_RightBar,
		frame.MainFrame and frame.MainFrame.Overlay and frame.MainFrame.Overlay.Glow_BottomBar,
	}
end

function M:StyleTalkingHead()
	local frame = TalkingHeadFrame
	if not frame or not U.Allowed(HEAD) then return end
	if U.Allowed(HEAD, "hide") and self.db.talkingHead.hideMode == "frame" then
		U.SetAlpha(frame, 0)
		frame:EnableMouse(false)
		return
	end
	local skin = U.Allowed(HEAD, "skin")
	local parts = HeadSkin()
	if skin then
		for _, region in pairs(HeadArt()) do
			if region and region.SetTexture then region:SetTexture(nil) end
		end
		E:SetPanelTemplate(parts.bd, true)
		E:AccentTexture(parts.line, 1)
		parts.bd:Show()
		local name, text = frame.NameFrame and frame.NameFrame.Name, frame.TextFrame and frame.TextFrame.Text
		local size = self.db.talkingHead.textSize
		if name then
			U.SkinFont(name, size > 0 and size + 4 or nil)
			name:SetTextColor(E:TokenColor("accent"))
			name:SetShadowColor(0, 0, 0, 0)
		end
		if text then
			U.SkinFont(text, size > 0 and size or nil)
			text:SetTextColor(1, 1, 1)
			text:SetShadowColor(0, 0, 0, 0)
		end
		if frame.MainFrame and frame.MainFrame.CloseButton then E:SkinCloseButton(frame.MainFrame.CloseButton) end
	elseif headParts then
		headParts.bd:Hide()
		U.RestoreFont(frame.NameFrame and frame.NameFrame.Name)
		U.RestoreFont(frame.TextFrame and frame.TextFrame.Text)
	end
end

local function HookHead()
	if headHooked or not TalkingHeadFrame then return end
	headHooked = true
	if TalkingHeadFrame.PlayCurrent then
		hooksecurefunc(TalkingHeadFrame, "PlayCurrent", function() M:StyleTalkingHead() end)
	end
	TalkingHeadFrame:HookScript("OnShow", function() if HeadInLane() then M:LayoutLane() end end)
	TalkingHeadFrame:HookScript("OnHide", function() if HeadInLane() then M:LayoutLane() end end)
end

local headEventOff = false

local function ApplyHead(state)
	local frame = TalkingHeadFrame
	if not frame then return end
	HookHead()
	local db = M.db.talkingHead
	-- Hide: no talking head at all (no voice either), or the frame only.
	local hideAll = state.hide and db.hideMode == "all"
	if hideAll and not headEventOff then
		frame:UnregisterEvent("TALKINGHEAD_REQUESTED")
		headEventOff = true
		if frame:IsShown() and frame.CloseImmediately then frame:CloseImmediately() end
	elseif not hideAll and headEventOff then
		frame:RegisterEvent("TALKINGHEAD_REQUESTED")
		headEventOff = false
	end
	if not (state.hide and db.hideMode == "frame") then
		U.RestoreAlpha(frame)
		frame:EnableMouse(true)
	end
	-- Move: into the alert lane or onto its own mover.
	if state.move and not state.hide then
		if db.anchor == "lane" then
			U.Unpin(frame)
			M:LayoutLane()
		else
			U.Pin(frame, U.Holder("TalkingHead"), "CENTER", "CENTER", 0, 0,
				function() return U.Allowed(HEAD, "move") and M.db.talkingHead.anchor ~= "lane" end)
		end
		U.SetScale(frame, db.scale)
	else
		U.Unpin(frame)
		U.RestoreScale(frame)
	end
	M:StyleTalkingHead()
	M:LayoutLane()
end

local function RestoreHead()
	local frame = TalkingHeadFrame
	if not frame then return end
	if headEventOff then
		frame:RegisterEvent("TALKINGHEAD_REQUESTED")
		headEventOff = false
	end
	U.RestoreAlpha(frame)
	frame:EnableMouse(true)
	U.Unpin(frame)
	U.RestoreScale(frame)
	if headParts then headParts.bd:Hide() end
	U.RestoreFont(frame.NameFrame and frame.NameFrame.Name)
	U.RestoreFont(frame.TextFrame and frame.TextFrame.Text)
	M:LayoutLane()
end

U.Element(HEAD, {
	apply = ApplyHead,
	restore = RestoreHead,
	handler = {
		reload = { skin = true, move = true },
		install = { skin = true, move = true },
	},
})

---------------------------------------------------------------------------
-- EldoUI's own alert lane (Replace switch): achievements, level-up, quest
-- complete, loot won, recipes, collections and boss kills.
---------------------------------------------------------------------------
local pool = {}

local function LaneOn(kind)
	return U.Allowed(ALERTS, "replace") and M.db.alerts.lane[kind]
end

-- A toast is one row (icon, title, text, sub line); a toast with `lines`
-- (the level-up toast's new spells) grows a list below that row.
local function ToastSize(toast)
	local lane = M.db.alerts.lane
	local head = lane.iconSize + 12
	-- The width comes first: the list wraps to it before the height is known.
	toast:SetSize(lane.width, head)
	toast.icon:SetSize(lane.iconSize, lane.iconSize)
	toast.iconBorder:SetSize(lane.iconSize + 2 * E.pixel, lane.iconSize + 2 * E.pixel)
	E:SetFont(toast.title, math.max(lane.fontSize - 2, 9))
	E:SetFont(toast.text, lane.fontSize)
	E:SetFont(toast.sub, math.max(lane.fontSize - 2, 9))
	E:SetFont(toast.list, math.max(lane.fontSize - 2, 9))
	toast.sub:ClearAllPoints()
	toast.sub:SetPoint("BOTTOMLEFT", toast.iconBorder, "BOTTOMRIGHT", 8, 1)
	toast.sub:SetPoint("BOTTOMRIGHT", toast, "TOPRIGHT", -8, -(head - 7 + E.pixel))
	local lines = toast.data and toast.data.lines
	if type(lines) == "table" and #lines > 0 then
		toast.list:ClearAllPoints()
		toast.list:SetPoint("TOPLEFT", toast.iconBorder, "BOTTOMLEFT", 0, -6)
		toast.list:SetPoint("TOPRIGHT", toast, "TOPRIGHT", -8, -(head + E.pixel))
		toast.list:SetText(table.concat(lines, "|n"))
		toast.list:Show()
		toast:SetHeight(head + math.ceil(toast.list:GetStringHeight()) + 10)
	else
		toast.list:SetText("")
		toast.list:Hide()
	end
end

local function ReleaseToast(toast)
	local found = false
	for index, active in ipairs(toasts) do
		if active == toast then table.remove(toasts, index) found = true break end
	end
	if not found then return end
	toast:Hide()
	toast.data, toast.closing = nil, nil
	table.insert(pool, toast)
	M:LayoutLane()
	-- Its place in the lane is free: the next waiting toast comes in.
	E:NoticeClosed(toast)
end

local function DismissToast(toast, now)
	if now then
		toast.closing = true
		ReleaseToast(toast)
		return
	end
	if toast.closing then return end
	toast.closing = true
	E:SlideOut(toast, M.db.alerts.growth == "DOWN" and "UP" or "DOWN", function() ReleaseToast(toast) end)
end

local function CreateToast()
	local toast = CreateFrame("Button", nil, UIParent)
	toast:SetFrameStrata("DIALOG")
	E:AddMoverContent("EldoUI_AlertLane", toast)
	toast:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	E:SetPanelTemplate(toast, false)
	toast.iconBorder = CreateFrame("Frame", nil, toast)
	toast.iconBorder:SetPoint("TOPLEFT", 6 - E.pixel, -(6 - E.pixel))
	E:SetTemplate(toast.iconBorder)
	toast.icon = toast.iconBorder:CreateTexture(nil, "ARTWORK")
	toast.icon:SetPoint("CENTER")
	E:TrimIcon(toast.icon)
	toast.title = E:CreateText(toast, E.tokens.size.small, "LEFT")
	toast.title:SetPoint("TOPLEFT", toast.iconBorder, "TOPRIGHT", 8, -1)
	toast.title:SetPoint("TOPRIGHT", -8, -(7 - E.pixel))
	toast.text = E:CreateText(toast, E.tokens.size.body, "LEFT")
	toast.text:SetPoint("LEFT", toast.iconBorder, "RIGHT", 8, 0)
	toast.text:SetPoint("RIGHT", -8, 0)
	toast.sub = E:CreateText(toast, E.tokens.size.small, "LEFT")
	toast.sub:SetPoint("BOTTOMLEFT", toast.iconBorder, "BOTTOMRIGHT", 8, 1)
	toast.sub:SetPoint("BOTTOMRIGHT", -8, 7 - E.pixel)
	toast.sub:SetTextColor(unpack(E.media.text.secondary))
	toast.list = E:CreateText(toast, E.tokens.size.small, "LEFT")
	toast.list:SetJustifyV("TOP")
	toast.list:SetWordWrap(true)
	toast.list:Hide()
	toast:SetScript("OnClick", function(self, button)
		if E:IsOptionsLinkClick(self, button) then return end
		if button == "RightButton" then
			if not E:CloseNotice(self) then DismissToast(self) end
		elseif self.data and self.data.onClick then
			self.data.onClick()
		end
	end)
	-- The tooltip: the item's own for a loot toast, then what the clicks do.
	toast:SetScript("OnEnter", function(self)
		self:SetBackdropBorderColor(U.Accent())
		local data = self.data
		if not data then return end
		E.UIKit.AnchorTooltip(self)
		if data.link then GameTooltip:SetHyperlink(data.link) end
		E:TooltipHint(GameTooltip, data.onClick and { L["Click"], data.clickHint or L["open it"] } or nil,
			{ L["Right-click"], L["close it"] })
		GameTooltip:Show()
	end)
	-- Ctrl-click: the toast's own settings, else the alert lane's.
	E:BindOptionsLink(toast, function(own)
		local data = own.data
		return data and data.options or { page = "module:Notifications", key = "alerts.lane.duration" }
	end)
	toast:SetScript("OnLeave", function(self)
		E:SetPanelTemplate(self, false)
		GameTooltip_Hide()
	end)
	return toast
end

local function FillToast(toast, data)
	toast.data = data
	ToastSize(toast)
	E:SetPanelTemplate(toast, false)
	if data.atlas then toast.icon:SetAtlas(data.atlas) else toast.icon:SetTexture(data.icon or E.media.icon) end
	toast.title:SetText(data.title or "")
	toast.title:SetTextColor(E:TokenColor("accent"))
	toast.text:SetText(data.text or "")
	toast.sub:SetText(data.sub or "")
	if data.color then toast.text:SetTextColor(data.color[1], data.color[2], data.color[3]) else toast.text:SetTextColor(1, 1, 1) end
	local border = data.border
	if border then toast.iconBorder:SetBackdropBorderColor(border[1], border[2], border[3]) else toast.iconBorder:SetBackdropBorderColor(unpack(E.media.borderColor)) end
end

local function ShowToast(data)
	local toast = table.remove(pool) or CreateToast()
	toast.closing = nil
	FillToast(toast, data)
	table.insert(toasts, toast)
	M:LayoutLane()
	E:SlideIn(toast, M.db.alerts.growth == "DOWN" and "UP" or "DOWN")
	M:PlayLaneSound()
	return toast
end

-- The toast sound (the Sound switch and Toast sound of the alert lane),
-- on the effects channel.
function M:PlayLaneSound()
	local lane = self.db.alerts.lane
	if not lane.sound then return end
	E:PlayMedia(lane.soundID, "SFX", { fallback = "kit:UI_EPICLOOT_TOAST" })
end

-- The lane is a holder of EldoUI's one notice queue (Core/Alerts.lua):
-- the queue says when a toast shows, how long it stays (the lane's "Show
-- for" time, longer while the mouse is over it) and what waits. While
-- "Wait until combat ends" is on, toasts wait for the end of the fight; a
-- toast that waited longer than two minutes drops away (it is in the chat
-- anyway), and toasts with the same key are shown once.
local LANE_WAIT = 120

E:RegisterNoticeHolder("lane", {
	usable = function() return M.active and true or false end,
	slots = function() return M.db.alerts.lane.max end,
	ready = function()
		local lane = M.db.alerts.lane
		return not (lane.holdInCombat and InCombatLockdown())
	end,
	duration = function() return M.db.alerts.lane.duration end,
	wait = LANE_WAIT,
	show = ShowToast,
	refresh = function(toast, data)
		FillToast(toast, data)
		M:LayoutLane()
	end,
	hide = function(toast, _, now) DismissToast(toast, now) end,
})

function M:PushToast(data)
	if type(data) ~= "table" then return nil end
	return E:PushNotice("lane", data)
end

function M:UpdateOwnLane()
	if U.Allowed(ALERTS, "replace") then
		for _, toast in ipairs(toasts) do ToastSize(toast) end
		self:LayoutLane()
		return
	end
	-- The lane is not EldoUI's any more: what waits goes, what shows goes
	-- at once.
	E:DropNotices("lane", true)
	for index = #toasts, 1, -1 do DismissToast(toasts[index], true) end
end

-- Sources -----------------------------------------------------------------
local function QualityColor(link)
	local quality = link and C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(link)
	if quality and C_Item.GetItemQualityColor then
		local r, g, b = C_Item.GetItemQualityColor(quality)
		return { r, g, b }
	end
end

U.On("ACHIEVEMENT_EARNED", function(_, id, alreadyEarned)
	if not LaneOn("achievement") or not id or alreadyEarned then return end
	local _, name, points, _, _, _, _, description, _, icon = GetAchievementInfo(id)
	if not U.Safe(name) then return end
	M:PushToast({
		title = L["Achievement"],
		text = name,
		sub = (points and points > 0) and L["%d points"]:format(points) or U.Safe(description),
		icon = icon,
		onClick = function()
			if not (AchievementFrame and AchievementFrame:IsShown()) and ToggleAchievementFrame then ToggleAchievementFrame() end
			if AchievementFrame_SelectAchievement then AchievementFrame_SelectAchievement(id) end
		end,
	})
end)

U.On("PLAYER_LEVEL_UP", function(_, level)
	if not LaneOn("levelup") or not U.Safe(level) then return end
	-- One card per level: the Talent Planner's level-up reminder or the
	-- Journal's level moment, when one of them shows it.
	local talents = E.Talents
	if talents and type(talents.OwnsLevelUp) == "function" and talents:OwnsLevelUp() then return end
	local moments = E.Adventure and E.Adventure.Moments
	if moments and type(moments.ShowsLevel) == "function" and moments:ShowsLevel() then return end
	local data = { title = L["Level up!"], text = L["Level %d"]:format(level), sub = UnitClass("player"), icon = E.media.icon }
	M:AddLevelSpells(data, level)
	M:PushToast(data)
end)

-- The level-up toast's new spells: what your class trainer teaches from
-- this level that you don't know yet, new spells and new ranks, from the
-- Training module's trainer data for your class, race and faction. A
-- level with nothing new keeps the plain toast; so does a character whose
-- Training module is off. A click opens the Training window's spell list.
local LEVEL_SPELLS_SHOWN = 6

local function OpenSpellsToTrain()
	local T = E.Training
	if T and T.active and T.Show then T:Show("spells") end
end

function M:LevelSpells(level)
	local T = E.Training
	if not (self.db.alerts.lane.levelupSpells and T and T.active and type(T.SpellsAt) == "function") then return nil end
	local ok, spells = pcall(T.SpellsAt, T, level)
	if not ok or type(spells) ~= "table" or #spells == 0 then return nil end
	return spells
end

function M:AddLevelSpells(data, level)
	local spells = self:LevelSpells(level)
	if not spells then return data end
	local size = math.max(self.db.alerts.lane.fontSize - 2, 9) + 2
	local lines = {}
	for index = 1, math.min(#spells, LEVEL_SPELLS_SHOWN) do
		local spell = spells[index]
		local name = spell.rank and ("%s (%s)"):format(spell.name, spell.rank) or spell.name
		lines[index] = spell.icon and ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t %s"):format(tostring(spell.icon), size, size, name) or name
	end
	if #spells > LEVEL_SPELLS_SHOWN then
		lines[#lines + 1] = E:Plural(#spells - LEVEL_SPELLS_SHOWN, "and %d more", "and %d more"):format(#spells - LEVEL_SPELLS_SHOWN)
	end
	data.sub = M:LevelSpellsCount(spells)
	data.lines = lines
	data.onClick = OpenSpellsToTrain
	data.clickHint = L["open the spells to train"]
	return data
end

function M:LevelSpellsCount(spells)
	return E:Plural(#spells, "%d new spell or rank at your trainer", "%d new spells and ranks at your trainer"):format(#spells)
end

-- The other level-up card (the Journal's chapter card) asks here, so a
-- level-up lists the same spells under the same option whichever card
-- shows it: nil, or the count line, the names line and the click.
function E:LevelUpSpells(level)
	if not (M.active and M.db) then return nil end
	local spells = M:LevelSpells(level)
	if not spells then return nil end
	local names = {}
	for index = 1, math.min(#spells, 4) do
		local spell = spells[index]
		names[index] = spell.rank and ("%s (%s)"):format(spell.name, spell.rank) or spell.name
	end
	if #spells > 4 then names[#names + 1] = E:Plural(#spells - 4, "and %d more", "and %d more"):format(#spells - 4) end
	return { count = #spells, line = M:LevelSpellsCount(spells), names = table.concat(names, ", "), open = OpenSpellsToTrain }
end

U.On("QUEST_TURNED_IN", function(_, questID, xp, money)
	if not LaneOn("quest") or not questID then return end
	local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
	if not U.Safe(title) then return end
	local parts = {}
	if U.Safe(xp) and xp > 0 then parts[#parts + 1] = L["%s XP"]:format(BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or xp) end
	if U.Safe(money) and money > 0 then parts[#parts + 1] = E:FormatMoney(money) end
	local hasAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("QuestTurnin")
	M:PushToast({
		title = L["Quest complete"],
		text = title,
		sub = table.concat(parts, "  "),
		atlas = hasAtlas and "QuestTurnin" or nil,
		icon = E.media.icon,
	})
end)

U.On("LOOT_ITEM_ROLL_WON", function(_, link, quantity)
	if not LaneOn("loot") or not U.Safe(link) then return end
	local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(link)
	local color = QualityColor(link)
	M:PushToast({
		title = L["You won"],
		text = (U.Safe(quantity) and quantity > 1) and ("%s x%d"):format(link, quantity) or link,
		icon = icon,
		border = color,
		link = link,
	})
end)

U.On("NEW_RECIPE_LEARNED", function(_, recipeID)
	if not LaneOn("recipe") or not recipeID then return end
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(recipeID)
	if not U.Safe(name) then return end
	M:PushToast({
		title = L["New recipe learned"],
		text = name,
		icon = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(recipeID),
	})
end)

local function Collected(title, name, icon)
	if not LaneOn("collection") or not U.Safe(name) then return end
	M:PushToast({ title = title, text = name, icon = icon, sub = L["Collected"] })
end

U.On("NEW_MOUNT_ADDED", function(_, mountID)
	if not (mountID and C_MountJournal and C_MountJournal.GetMountInfoByID) then return end
	local name, _, icon = C_MountJournal.GetMountInfoByID(mountID)
	Collected(L["Mount"], name, icon)
end)

U.On("NEW_PET_ADDED", function(_, guid)
	if not (guid and C_PetJournal and C_PetJournal.GetPetInfoByPetID) then return end
	local _, customName, _, _, _, _, _, name, icon = C_PetJournal.GetPetInfoByPetID(guid)
	Collected(L["Pet"], U.Safe(customName) or name, icon)
end)

U.On("NEW_TOY_ADDED", function(_, itemID)
	if not (itemID and C_ToyBox and C_ToyBox.GetToyInfo) then return end
	local _, name, icon = C_ToyBox.GetToyInfo(itemID)
	Collected(L["Toy"], name, icon)
end)

U.On("BOSS_KILL", function(_, _, name)
	if not LaneOn("boss") or not U.Safe(name) then return end
	M:PushToast({ title = L["Boss defeated"], text = name, icon = E.media.icon })
end)

U.OnDisable(function() M:UpdateOwnLane() end)

M.tests.lane = function()
	if not U.Allowed(ALERTS, "replace") then
		E:Print(L["Turn on Blizzard UI > Alerts, toasts and banners > Replace with EldoUI's frame to see the EldoUI lane."])
		return
	end
	M:PushToast({ title = L["Achievement"], text = L["Test achievement"], sub = L["%d points"]:format(10), icon = E.media.icon })
	-- The level-up sample shows your next level, with the spells it brings.
	local level = (tonumber(U.Safe(UnitLevel("player"))) or 1) + 1
	M:PushToast(M:AddLevelSpells({ title = L["Level up!"], text = L["Level %d"]:format(level), sub = UnitClass("player"), icon = E.media.icon }, level))
	M:PushToast({ title = L["Quest complete"], text = L["A test quest"], sub = L["%s XP"]:format("1,250"), icon = E.media.icon })
end
