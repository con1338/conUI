-- EldoUI Talent Planner on Blizzard's talent window.
--
-- Only when the player lets EldoUI improve "Spellbook and talents"
-- (Blizzard UI page, E:BlizzardAllowed("player-spells", "improve")):
--   * an overlay on each talent button: your plan's rank for it in the
--     accent color, an accent ring on the next point of your plan, and
--     the pick order (the plan point that first takes the talent) when the
--     planner's "Pick order numbers" option is on;
--   * a "Planner" button on the talent page that opens EldoUI's planner,
--     and the build bar left of it (BuildBar.lua: category, Recommended
--     build, Import build), which only ever saves plans.
-- The overlay is EldoUI's own frames on top of Blizzard's buttons; nothing
-- of Blizzard's is changed, clicked or hooked into, and Blizzard's window
-- keeps doing all the learning it does. Everything is undone when the
-- switch goes off, and everything steps aside while the game's gamepad
-- interface is on (its controller cursor walks the window's buttons).
-- Out of combat only.
local _, E = ...
local L = E.L
local P = E.TalentPlan
local M = E.Talents
local Kit = E.UIKit

local ELEMENT = "player-spells"
local overlays = setmetatable({}, { __mode = "k" }) -- Blizzard talent button -> our overlay
local button                                        -- our "Planner" button
local buildBar                                      -- our build bar (BuildBar.lua)
local hooked

local function Allowed()
	return M.active and E:BlizzardAllowed(ELEMENT, "improve") and not E:GamepadUIActive()
end

local function TalentsFrame()
	local root = _G.PlayerSpellsFrame
	local frame = root and (root.TalentsFrame or root.ClassTalentsFrame)
	if frame and E.FrameCheck(frame, "IsForbidden") then return nil end
	return frame
end

local function Overlay(talentButton)
	local overlay = overlays[talentButton]
	if overlay then return overlay end
	overlay = CreateFrame("Frame", nil, talentButton)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(talentButton:GetFrameLevel() + 5)
	overlay:EnableMouse(false)
	overlay.ring = CreateFrame("Frame", nil, overlay)
	overlay.ring:SetPoint("TOPLEFT", -3, 3)
	overlay.ring:SetPoint("BOTTOMRIGHT", 3, -3)
	E:SetTemplate(overlay.ring, true)
	overlay.ring:SetBackdropColor(0, 0, 0, 0)
	overlay.ring:EnableMouse(false)
	overlay.badge = CreateFrame("Frame", nil, overlay)
	overlay.badge:SetSize(22, 13)
	overlay.badge:SetPoint("TOPLEFT", -4, 4)
	E:SetTemplate(overlay.badge)
	overlay.badge:EnableMouse(false)
	overlay.badge.text = Kit.Text(overlay.badge, 10, "CENTER")
	overlay.badge.text:SetPoint("CENTER")
	overlay.order = M:CreateOrderBadge(overlay)
	overlay.order:SetPoint("TOPRIGHT", 4, 4)
	overlays[talentButton] = overlay
	return overlay
end

local function HideOverlays()
	for _, overlay in pairs(overlays) do overlay:Hide() end
end

local function ButtonFor(frame, nodeID)
	if type(frame.GetTalentButtonByNodeID) ~= "function" then return nil end
	local ok, talentButton = pcall(frame.GetTalentButtonByNodeID, frame, nodeID)
	if ok and type(talentButton) == "table" and talentButton.GetFrameLevel then return talentButton end
end

function M:RefreshOverlay()
	-- Redrawn after combat (the module refreshes on PLAYER_REGEN_ENABLED).
	if InCombatLockdown() then return end
	local frame = TalentsFrame()
	if not frame then return end
	if not (Allowed() and self.db.blizzOverlay and frame:IsShown()) then
		HideOverlays()
		return
	end
	local tree = self:Tree()
	local group = E:TalentGroup()
	local plan = self:ActivePlan(group)
	HideOverlays()
	if not (tree and plan) then return end
	local planned = P.Count(tree, plan.order).ranks
	local live = self:LiveState(group)
	local next = self:OpenSteps(plan, group)[1]
	local picks = self:ShowsOrder() and P.Picks(plan.order) or {}
	local r, g, b = Kit.Accent()
	for nodeID, node in pairs(tree.nodes) do
		local talentButton = ButtonFor(frame, nodeID)
		local want = planned[nodeID] or 0
		local isNext = next and next.nodeID == nodeID
		-- Every talent of the plan keeps its pick number, learned or not; the
		-- plan rank shows only while the plan wants more than you have.
		if talentButton and (want > 0 or isNext) then
			local overlay = Overlay(talentButton)
			overlay.badge:SetShown(want > (live.ranks[nodeID] or 0))
			overlay.badge.text:SetText(("%d/%d"):format(want, node.maxRanks))
			overlay.badge.text:SetTextColor(r, g, b)
			overlay.ring:SetShown(isNext and true or false)
			overlay.ring:SetBackdropBorderColor(r, g, b)
			overlay.order:SetOrder(picks[nodeID] and picks[nodeID][1] or nil)
			overlay:Show()
		end
	end
end

-- Forever's talent window draws its own controls (tab strip, tree headers,
-- search box) at frame level 1010, far above the window's plain children.
-- The Planner button and the build bar sit just above that band, so the
-- window's art never covers them; they share the footer row with Apply and
-- never overlap it. Reapplied on every refresh: the window can re-level
-- its children.
local CONTROL_LEVEL = 1010
local function Raise(frame, level)
	frame:SetFrameLevel(level)
	for _, child in ipairs({ frame:GetChildren() }) do
		if child:GetFrameLevel() <= level then Raise(child, level + 1) end
	end
end

local function RowLevel(host)
	local level = CONTROL_LEVEL
	local apply = host.ApplyButton
	if apply and apply.GetFrameLevel then level = math.max(level, apply:GetFrameLevel()) end
	return level + 5
end

function M:UpdateBlizzardButton()
	-- Redrawn after combat, like the overlay.
	if InCombatLockdown() then return end
	local frame = TalentsFrame()
	if not frame then return end
	local show = Allowed() and self.db.blizzButton
	if not show then
		if button then button:Hide() end
		if buildBar then buildBar:Hide() end
		return
	end
	-- Made once per talent window (EldoUI's own frames on top of it).
	if not button or button.host ~= frame then
		if button then button:Hide() end
		if buildBar then buildBar:Hide() end
		button = Kit.Button(frame, L["Planner"], 90, 22, function() M:TogglePlanner() end, L["EldoUI Talent Planner"],
			L["Opens EldoUI's planner: plan your talents level by level and learn the next point with one click."])
		button.host = frame
		local apply = frame.ApplyButton
		if apply and apply.GetLeft then
			button:SetPoint("RIGHT", apply, "LEFT", -8, 0)
		else
			button:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
		end
		-- The build bar, left of the Planner button: always your own class
		-- and the talent group in use.
		buildBar = M:CreateBuildBar(frame, { compact = true, group = function() return E:TalentGroup() end })
		buildBar:SetPoint("RIGHT", button, "LEFT", -8, 0)
	end
	local level = RowLevel(frame)
	Raise(button, level)
	Raise(buildBar, level)
	button:Show()
	buildBar:Update()
	buildBar:Show()
	M:FitBlizzardRow(frame)
end

-- The row runs leftwards from Apply. On a narrow window or with large text
-- it could pass the window's left edge: then the row shrinks to fit, down to
-- MIN_ROW_SCALE, and when even that is too wide the build bar steps aside
-- (the planner's own Trees tab has the same bar). Returns the scale used.
local ROW_MARGIN, MIN_ROW_SCALE = 12, 0.75

function M:FitBlizzardRow(frame)
	frame = frame or TalentsFrame()
	if not (frame and button and buildBar) then return 1 end
	button:SetScale(1)
	buildBar:SetScale(1)
	buildBar:Show()
	local left, right = frame:GetLeft(), button:GetRight()
	if not (left and right) then return 1 end
	local room = right - (left + ROW_MARGIN)
	local width = (button:GetWidth() or 0) + 8 + (buildBar:GetWidth() or 0)
	if room <= 0 or width <= room then return 1 end
	local scale = room / width
	if scale < MIN_ROW_SCALE then
		buildBar:Hide()
		return 0
	end
	-- Both hang from their right edge, so the row keeps its place by Apply.
	button:SetScale(scale)
	buildBar:SetScale(scale)
	return scale
end

local function HookFrame()
	if hooked then return end
	local frame = TalentsFrame()
	if not frame then return end
	hooked = true
	local function Update()
		if not M.active then return end
		M:RefreshOverlay()
		M:UpdateBlizzardButton()
	end
	frame:HookScript("OnShow", function()
		M:Invalidate()
		Update()
	end)
	frame:HookScript("OnHide", HideOverlays)
end

-- Hooks go in only once the switch is on; off leaves Blizzard's window as
-- Blizzard made it.
function M:ApplyBlizzard()
	if not Allowed() then return self:RestoreBlizzard() end
	if C_AddOns.IsAddOnLoaded("Blizzard_PlayerSpells") then
		HookFrame()
		self:RefreshOverlay()
		self:UpdateBlizzardButton()
		return
	end
	if self.waitingSpellbook then return end
	self.waitingSpellbook = true
	E:OnBlizzardAddOn("Blizzard_PlayerSpells", function()
		M.waitingSpellbook = false
		if not Allowed() then return end
		HookFrame()
		M:RefreshOverlay()
		M:UpdateBlizzardButton()
	end)
end

function M:RestoreBlizzard()
	HideOverlays()
	if button then button:Hide() end
	if buildBar then buildBar:Hide() end
end

-- The Talent Planner owns "Spellbook and talents". Training (its spellbook
-- tab) and Skins (the window look) join its hook list: they apply after the
-- planner and come off before it, in whatever order they were turned on.
E:RegisterBlizzardHandler(ELEMENT, {
	owner = "Talents",
	owns = true,
	apply = function() if M.active then M:ApplyBlizzard() end end,
	undo = function() M:RestoreBlizzard() end,
	install = { improve = true },
	-- New: nothing put a planner on the talent window before.
	legacy = function() return false end,
})

-- Why the Planner button, the build bar and the plan marks are missing from
-- Blizzard's talent window, or nil when nothing keeps them away. Shown on
-- the options page and under the planner; it only explains, it changes no
-- switch.
function M:BlizzardRowHint()
	if not self.active or E:BlizzardAllowed(ELEMENT, "improve") then return nil end
	return L["The Planner button and your plan on Blizzard's talent window need Blizzard UI > Spellbook and talents with Improve on."]
end

-- For diagnostics: our overlay on one Blizzard talent button,
-- and the Planner button.
function M:OverlayFor(talentButton)
	return overlays[talentButton]
end

function M:BlizzardPlannerButton()
	return button
end

function M:BlizzardBuildBar()
	return buildBar
end
