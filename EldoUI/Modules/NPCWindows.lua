-- EldoUI NPC windows: Blizzard's quest, gossip and other NPC dialogs, the
-- pet stable and the barber shop, in the EldoUI look.
--
-- Three Blizzard elements belong to this module (Core/Blizzard.lua):
--   quest-gossip-npc QuestFrame, GossipFrame, ItemTextFrame (books and
--                    letters), TabardFrame, GuildRegistrarFrame, PetitionFrame
--                    and PlayerChoiceFrame.
--                    Skin: EldoUI panels, light text on a dark page (the
--                    game's own "quest text contrast" setting), flat buttons
--                    and reward slots.
--                    Move: the window mover (Core/WindowMover.lua) drags and
--                    scales each dialog; it reopens where you left it.
--                    Improve: quest text size and instant quest text. Upgrade
--                    arrows and the best-reward mark come from Upgrades,
--                    reward sell values from Quality of Life.
--   pet-stable PetStableFrame. Skin, move, and happiness, level and
--                    loyalty on every stable slot (Improve).
--   barber-shop A light skin of the barber shop buttons only; the
--                    full-screen scene stays Blizzard's.
-- With an element's master switch off this module leaves it exactly as
-- Blizzard made it. Every skin here is recorded (E:SkinRecord in
-- Core/Skin.lua): switching Skin off puts the dialogs back at once. It never accepts, declines, picks or completes
-- anything: quest helpers that act for you live in Quality of Life and are off.
-- Written from scratch for EldoUI; no code or media from other addons.
local _, E = ...
local L = E.L

local QUEST_ID, STABLE_ID, BARBER_ID = "quest-gossip-npc", "pet-stable", "barber-shop"
-- The dark quest page has a record of its own: "Dark page, light text"
-- switches without the rest of the skin.
local PAGE_KEY = "quest-gossip-npc:page"

local M = E:NewModule("NPCWindows", {
	title = "NPC Windows",
	desc = "Quest, gossip and other NPC dialogs, the pet stable and the barber shop in the EldoUI look.",
	category = "Interface",
	conflicts = { "Immersion" },
	defaults = {
		transparent = false,    -- see-through panels
		lightText = true,       -- dark page with light text (the game's quest text contrast setting)
		questFontSize = 0,      -- 0 keeps the game's size
		instantQuestText = false,
		stableHappiness = true, -- happiness face on every stable slot
		stableLevel = true,     -- pet level on every stable slot
		stableTooltip = true,   -- loyalty and happiness in the slot tooltip
	},
})

-- Dialogs of the quest-gossip-npc element that are skinned and dragged.
local QUEST_FRAMES = { "QuestFrame", "GossipFrame", "ItemTextFrame", "TabardFrame", "GuildRegistrarFrame", "PetitionFrame" }
local QUEST_SCROLLS = { "QuestDetailScrollFrame", "QuestRewardScrollFrame", "QuestProgressScrollFrame", "QuestGreetingScrollFrame", "ItemTextScrollFrame" }
local QUEST_PANELS = { "QuestFrameDetailPanel", "QuestFrameRewardPanel", "QuestFrameProgressPanel", "QuestFrameGreetingPanel" }

-- Runs fn now when a load-on-demand Blizzard addon is loaded, else once when
-- it loads (fn reads the switches then, so repeated calls queue only one).
local queued = {}
local function WhenLoaded(addon, fn)
	if C_AddOns.IsAddOnLoaded(addon) then
		fn()
	elseif not queued[addon] then
		queued[addon] = true
		E:OnBlizzardAddOn(addon, function()
			queued[addon] = nil
			fn()
		end)
	end
end

-- Every UIPanelButtonTemplate button (Left/Middle/Right art) under a frame.
local function SkinButtonsIn(frame, depth)
	depth = depth or 0
	if depth > 3 or not frame or not frame.GetChildren then return end
	for _, child in ipairs({ frame:GetChildren() }) do
		if child:IsObjectType("Button") and child.Left and child.Middle and child.Right then
			E:SkinButton(child)
		elseif child:IsObjectType("EditBox") then
			E:SkinEditBox(child)
		end
		SkinButtonsIn(child, depth + 1)
	end
end

---------------------------------------------------------------------------
-- Skin: quest and gossip dialogs
---------------------------------------------------------------------------
local skinnedRewards = setmetatable({}, { __mode = "k" })
local skinned = {}

local function DarkPage()
	return M.db.lightText
end

local function SkinRewardButton(button)
	if skinnedRewards[button] or not button then return end
	skinnedRewards[button] = true
	E:SkinCapture(button)
	E:SkinAlphaZero(button.NameFrame, _G[(button:GetName() or "") .. "NameFrame"])
	local icon = button.Icon or button.icon
	if icon and icon.SetTexCoord then
		E:TrimIcon(icon)
		local box = CreateFrame("Frame", nil, button)
		box:SetPoint("TOPLEFT", icon, "TOPLEFT", -E.pixel, E.pixel)
		box:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", E.pixel, -E.pixel)
		box:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
		E:SetTemplate(box)
	end
	local bg = CreateFrame("Frame", nil, button)
	bg:SetPoint("TOPLEFT", icon or button, "TOPRIGHT", 2, 0)
	bg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
	bg:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
	E:SetTemplate(bg, true)
end

local function SkinRewards()
	if not (M.active and E:BlizzardAllowed(QUEST_ID, "skin")) then return end
	local rewards = QuestInfoRewardsFrame
	if rewards and rewards.RewardButtons then
		for _, button in ipairs(rewards.RewardButtons) do E:SkinRecord(QUEST_ID, button, SkinRewardButton, button) end
	end
	for index = 1, 6 do
		local button = _G["QuestProgressItem" .. index]
		if button then E:SkinRecord(QUEST_ID, button, SkinRewardButton, button) end
	end
end

local function SkinQuestFrame()
	local frame = QuestFrame
	if not frame or skinned.QuestFrame then return end
	skinned.QuestFrame = true
	E:SkinPanel(frame, { transparent = M.db.transparent })
	for _, name in ipairs(QUEST_SCROLLS) do
		local scroll = _G[name]
		if scroll and scroll.ScrollBar then E:SkinScrollBar(scroll.ScrollBar) end
	end
	SkinButtonsIn(frame)
	if QuestInfo_Display then
		hooksecurefunc("QuestInfo_Display", function() C_Timer.After(0, SkinRewards) end)
	end
end

-- The dark page: the parchment and material art of the quest and gossip
-- pages go, so the light text sits on the dark panel.
local function SkinDarkPage()
	for _, name in ipairs(QUEST_PANELS) do
		local panel = _G[name]
		if panel then
			E:SkinAlphaZero(panel.Bg, panel.MaterialTopLeft, panel.MaterialTopRight, panel.MaterialBotLeft, panel.MaterialBotRight,
				_G[name .. "Bg"], _G[name .. "MaterialTopRight"], _G[name .. "MaterialBotLeft"], _G[name .. "MaterialBotRight"])
		end
	end
	if QuestFrame then E:SkinAlphaZero(QuestFrame.SealMaterialBG) end
	local gossip = GossipFrame
	if gossip then
		E:SkinAlphaZero(gossip.Background)
		if gossip.GreetingPanel then E:StripTextures(gossip.GreetingPanel) end
	end
end

-- Switch one record to what is wanted: built the first time, then off and on.
local function Want(key, roots, want, build)
	if not want then
		E:SkinRecordOff(key)
	elseif E:SkinRecordState(key) == nil then
		E:SkinRecord(key, roots, build)
	else
		E:SkinRecordOn(key)
	end
end

local function QuestRoots()
	local roots = {}
	for _, name in ipairs(QUEST_FRAMES) do
		if _G[name] then roots[#roots + 1] = _G[name] end
	end
	return roots
end

local function SkinGossipFrame()
	local frame = GossipFrame
	if not frame or skinned.GossipFrame then return end
	skinned.GossipFrame = true
	E:SkinPanel(frame, { transparent = M.db.transparent })
	local panel = frame.GreetingPanel
	if panel then
		E:SkinButton(panel.GoodbyeButton)
		E:SkinScrollBar(panel.ScrollBar)
	end
	SkinButtonsIn(frame)
end

local function SkinItemText()
	local frame = ItemTextFrame
	if not frame or skinned.ItemTextFrame then return end
	skinned.ItemTextFrame = true
	-- Books and letters keep their page (parchment, stone, marble ...), so the
	-- game's text colors stay readable.
	local keep = {}
	for _, name in ipairs({ "ItemTextFramePageBg", "ItemTextMaterialTopLeft", "ItemTextMaterialTopRight",
		"ItemTextMaterialBotLeft", "ItemTextMaterialBotRight" }) do
		if _G[name] then keep[_G[name]] = true end
	end
	E:SkinPanel(frame, { transparent = M.db.transparent, keep = keep })
	if ItemTextScrollFrame and ItemTextScrollFrame.ScrollBar then E:SkinScrollBar(ItemTextScrollFrame.ScrollBar) end
end

-- Tabard, guild registrar and petition: frame, title, close and buttons.
-- Their content art stays, so the game's text colors stay readable.
local function SkinSimple(name)
	local frame = _G[name]
	if not frame or skinned[name] then return end
	skinned[name] = true
	E:SkinPanel(frame, { transparent = M.db.transparent, strip = false })
	SkinButtonsIn(frame)
end

function M:ApplyQuestSkin()
	if not (self.active and E:BlizzardAllowed(QUEST_ID, "skin")) then
		E:SkinRecordOff(QUEST_ID)
		E:SkinRecordOff(PAGE_KEY)
		E:RestoreCVar("QuestTextContrast", QUEST_ID)
		return
	end
	E:SkinRecordOn(QUEST_ID)
	E:SkinRecord(QUEST_ID, QuestRoots(), function()
		SkinQuestFrame()
		SkinGossipFrame()
		SkinItemText()
		for _, name in ipairs({ "TabardFrame", "GuildRegistrarFrame", "PetitionFrame" }) do SkinSimple(name) end
		for _, name in ipairs(QUEST_FRAMES) do
			local frame = _G[name]
			if frame then E:SetPanelTransparent(frame, self.db.transparent) end
		end
	end)
	Want(PAGE_KEY, QuestRoots(), DarkPage(), SkinDarkPage)
	-- Light text on the dark page: the game's own accessibility setting does it.
	if self.db.lightText then
		E:SetCVar("QuestTextContrast", 4, QUEST_ID)
	else
		E:RestoreCVar("QuestTextContrast", QUEST_ID)
	end
	SkinRewards()
end

---------------------------------------------------------------------------
-- Improve: quest text size and instant quest text
---------------------------------------------------------------------------
local QUEST_FONTS = {
	{ "QuestFont", 0 }, { "QuestFontLeft", 0 }, { "QuestFontHighlight", 0 },
	{ "QuestFontNormalSmall", -2 }, { "QuestTitleFont", 4 }, { "QuestTitleFontBlackShadow", 4 },
}
local savedFonts = {}

local function SetQuestFonts(size)
	for _, entry in ipairs(QUEST_FONTS) do
		local font = _G[entry[1]]
		if type(font) == "table" and font.GetFont then
			if not savedFonts[entry[1]] then savedFonts[entry[1]] = { font:GetFont() } end
			local saved = savedFonts[entry[1]]
			if saved[1] then
				if size and size > 0 then
					font:SetFont(saved[1], size + entry[2], saved[3] or "")
				else
					font:SetFont(saved[1], saved[2], saved[3] or "")
				end
			end
		end
	end
	if not size or size <= 0 then wipe(savedFonts) end
end

-- Quest text below this size can't be read; 1 to 7 show as 8.
local MIN_QUEST_FONT = 8

function M:ApplyQuestImprove()
	local allowed = self.active and E:BlizzardAllowed(QUEST_ID, "improve")
	local size = tonumber(self.db.questFontSize) or 0
	if allowed and size > 0 then
		SetQuestFonts(math.max(MIN_QUEST_FONT, size))
	elseif next(savedFonts) then
		SetQuestFonts(0)
	end
	if allowed and self.db.instantQuestText then
		E:SetCVar("instantQuestText", 1, QUEST_ID)
	else
		E:RestoreCVar("instantQuestText", QUEST_ID)
	end
end

---------------------------------------------------------------------------
-- Pet stable
---------------------------------------------------------------------------
local HAPPINESS_ATLAS = { "UI-PetMad", "UI-PetNeutral", "UI-PetHappiness" }
local slotParts = setmetatable({}, { __mode = "k" }) -- slot button -> { face, level }
local slotLines = setmetatable({}, { __mode = "k" }) -- slot button -> accent line under the selected slot (skin)
local stableHooked = false

local function StableSlots()
	local list = {}
	if _G.PetStableCurrentPet then list[#list + 1] = _G.PetStableCurrentPet end
	for index = 1, 10 do
		local slot = _G["PetStableStabledPet" .. index]
		if not slot then break end
		list[#list + 1] = slot
	end
	return list
end

local function PetInfo(slot)
	if not (C_StableInfo and C_StableInfo.GetStablePetInfo) then return end
	local ok, info = pcall(C_StableInfo.GetStablePetInfo, slot:GetID())
	if ok and type(info) == "table" then return info end
end

local function SlotParts(slot)
	local parts = slotParts[slot]
	if parts then return parts end
	local holder = CreateFrame("Frame", nil, slot)
	holder:SetAllPoints()
	holder:SetFrameLevel(slot:GetFrameLevel() + 3)
	parts = { holder = holder }
	parts.face = holder:CreateTexture(nil, "OVERLAY")
	parts.face:SetSize(14, 14)
	parts.face:SetPoint("BOTTOMLEFT", -2, -2)
	parts.level = E:CreateText(holder, E.tokens.size.small, "RIGHT")
	parts.level:SetPoint("TOPRIGHT", -1, -1)
	slotParts[slot] = parts
	return parts
end

local function UpdateStable()
	local improve = M.active and E:BlizzardAllowed(STABLE_ID, "improve")
	for _, slot in ipairs(StableSlots()) do
		-- The accent line under the selected slot (skin) follows the checked state.
		local selected = slotLines[slot]
		if selected and not E:SkinRecordIsOff(selected) then selected:SetShown(slot.GetChecked and slot:GetChecked() and true or false) end
		local info = improve and PetInfo(slot)
		if info then
			local parts = SlotParts(slot)
			local atlas = M.db.stableHappiness and HAPPINESS_ATLAS[info.happinessLevel or 0]
			if atlas then parts.face:SetAtlas(atlas) end
			parts.face:SetShown(atlas and true or false)
			parts.level:SetText(M.db.stableLevel and info.level or "")
			parts.holder:Show()
		elseif slotParts[slot] then
			slotParts[slot].holder:Hide()
		end
	end
end

-- Loyalty and happiness in the slot's tooltip, from C_StableInfo.
local function SlotTooltip(slot)
	if not (M.active and M.db.stableTooltip and E:BlizzardAllowed(STABLE_ID, "improve")) then return end
	if not GameTooltip:IsOwned(slot) then return end
	local info = PetInfo(slot)
	if not info then return end
	if info.happinessLevel and _G["PET_HAPPINESS" .. info.happinessLevel] then
		GameTooltip:AddLine(_G["PET_HAPPINESS" .. info.happinessLevel], unpack(E.UIKit.TEXT))
	end
	if info.loyaltyName and info.loyaltyName ~= "" then
		local loyalty = info.loyaltyLevel and LOYALTY_LEVEL and LOYALTY_LEVEL:format(info.loyaltyLevel)
		E.UIKit.TipText(GameTooltip, loyalty and (info.loyaltyName .. " (" .. loyalty .. ")") or info.loyaltyName)
	end
	GameTooltip:Show()
end

local function SkinStable()
	local frame = _G.PetStableFrame
	if not frame or skinned.PetStableFrame then return end
	skinned.PetStableFrame = true
	E:SkinPanel(frame, { transparent = M.db.transparent })
	if frame.modelScene then E:SkinInset(frame.modelScene.Inset) end
	E:SkinButton(frame.purchaseButton)
	for _, slot in ipairs(StableSlots()) do
		local name = slot:GetName()
		local icon = name and _G[name .. "IconTexture"]
		if icon then E:TrimIcon(icon) end
		E:SkinAlphaZero(slot.background, slot:GetNormalTexture())
		local box = CreateFrame("Frame", nil, slot)
		box:SetAllPoints()
		box:SetFrameLevel(math.max(slot:GetFrameLevel() - 1, 0))
		E:SetTemplate(box)
		local checked = slot.GetCheckedTexture and slot:GetCheckedTexture()
		if checked then
			E:SkinColorTexture(checked, 1, 1, 1, 0)
			local line = slot:CreateTexture(nil, "OVERLAY")
			line:SetPoint("BOTTOMLEFT", E.pixel, E.pixel)
			line:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
			line:SetHeight(E.pixel * 2)
			E:AccentTexture(line, 1)
			line:Hide()
			slot:HookScript("OnClick", function() C_Timer.After(0, UpdateStable) end)
			slotLines[slot] = line
		end
	end
end

function M:ApplyStable()
	WhenLoaded("Blizzard_StableUI", function()
		local frame = _G.PetStableFrame
		if not frame then return end
		Want(STABLE_ID, frame, M.active and E:BlizzardAllowed(STABLE_ID, "skin"), SkinStable)
		if M.active and E:BlizzardAllowed(STABLE_ID, "improve") and not stableHooked then
			stableHooked = true
			if frame.Update then hooksecurefunc(frame, "Update", UpdateStable) end
			frame:HookScript("OnShow", function() C_Timer.After(0, UpdateStable) end)
			for _, slot in ipairs(StableSlots()) do slot:HookScript("OnEnter", SlotTooltip) end
		end
		if frame:IsShown() then UpdateStable() end
	end)
end

---------------------------------------------------------------------------
-- Barber shop: a light skin of its buttons
---------------------------------------------------------------------------
local function SkinBarber()
	local frame = _G.BarberShopFrame
	for _, key in ipairs({ "AcceptButton", "CancelButton", "ResetButton" }) do
		E:SkinButton(frame[key], { size = 14 })
	end
	E:SkinCheckBox(frame.SDToggleButton)
end

function M:ApplyBarber()
	if not (self.active and E:BlizzardAllowed(BARBER_ID, "skin")) then
		E:SkinRecordOff(BARBER_ID)
		return
	end
	WhenLoaded("Blizzard_BarbershopUI", function()
		local frame = _G.BarberShopFrame
		if not frame then return end
		Want(BARBER_ID, frame, M.active and E:BlizzardAllowed(BARBER_ID, "skin"), SkinBarber)
	end)
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:Apply()
	self:ApplyQuestSkin()
	self:ApplyQuestImprove()
	self:ApplyStable()
	self:ApplyBarber()
end

-- Quality of Life v0.5.x had its own "Quest text size" (questTextSize) and
-- "Instant quest text" for the same fonts and CVar. They live here now:
-- carry the player's choice over once per profile, and hand over the
-- remembered game value of instantQuestText so turning it off here still
-- puts the player's own value back.
function M:MigrateFromQoL()
	local qol = E.db.modules and E.db.modules.QoL
	if type(qol) ~= "table" then return end
	if qol.instantQuestText ~= nil then
		if qol.instantQuestText then self.db.instantQuestText = true end
		qol.instantQuestText = nil
	end
	if qol.questTextSize ~= nil then
		local size = tonumber(qol.questTextSize) or 0
		if size > 0 and (self.db.questFontSize or 0) == 0 then self.db.questFontSize = size end
		qol.questTextSize = nil
	end
	-- The owner is read through the game settings store; handing it over
	-- still writes the one remembered entry.
	if E.CVarOwner and E:CVarOwner("instantQuestText") == "QoL" then
		local saved = EldoUIDB.cvarSnapshot.instantQuestText
		saved.owner = QUEST_ID
	end
end

function M:OnInitialize()
	self:MigrateFromQoL()
end

function M:OnEnable()
	self:Apply()
	self:RegisterEvent("PET_STABLE_UPDATE", function() C_Timer.After(0, UpdateStable) end)
end

function M:OnDisable()
	self:UnregisterEvent("PET_STABLE_UPDATE")
	for _, key in ipairs({ QUEST_ID, PAGE_KEY, STABLE_ID, BARBER_ID }) do E:SkinRecordOff(key) end
	if next(savedFonts) then SetQuestFonts(0) end
	E:RestoreCVar("QuestTextContrast", QUEST_ID)
	E:RestoreCVar("instantQuestText", QUEST_ID)
	UpdateStable()
end

function M:OnProfileChanged()
	self:MigrateFromQoL()
	if self.active then self:Apply() end
end

---------------------------------------------------------------------------
-- Blizzard element handlers (Blizzard UI page)
---------------------------------------------------------------------------
-- The skins are recorded, so Skin off needs no reload.
E:RegisterBlizzardHandler(QUEST_ID, {
	owner = "NPCWindows",
	apply = function() if M.active then M:Apply() end end,
	undo = function()
		E:SkinRecordOff(QUEST_ID)
		E:SkinRecordOff(PAGE_KEY)
		if next(savedFonts) then SetQuestFonts(0) end
	end,
	install = { skin = true, improve = true },
})

E:RegisterBlizzardHandler(STABLE_ID, {
	owner = "NPCWindows",
	apply = function() if M.active then M:Apply() end end,
	undo = function()
		E:SkinRecordOff(STABLE_ID)
		UpdateStable()
	end,
	install = { skin = true, improve = true },
})

E:RegisterBlizzardHandler(BARBER_ID, {
	owner = "NPCWindows",
	apply = function() if M.active then M:ApplyBarber() end end,
	undo = function() E:SkinRecordOff(BARBER_ID) end,
	-- The barber skin is recorded and comes off without a reload too.
	restore = { skin = true },
})

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local ACTION_NAMES = { skin = "Skin", improve = "Improve (extra info)" }
-- Grayed with the switch a quest row needs, like the stable rows below.
local function QuestWait(action)
	return function()
		if E:BlizzardAllowed(QUEST_ID, action) then return nil end
		return L["Turn on \"%s\" with \"%s\" on the Blizzard UI page first."]:format(L["Quest, gossip and NPC dialogs"], L[ACTION_NAMES[action]])
	end
end
-- The stable rows stay on screen, grayed, and say which switch they need:
-- the tab never opens blank.
local function StableWait()
	if E:BlizzardAllowed(STABLE_ID, "improve") then return nil end
	return L["Turn on \"%s\" with \"%s\" on the Blizzard UI page first."]:format(L["Pet stable"], L["Improve (extra info)"])
end
local function SkinWait()
	if E:BlizzardAllowed(QUEST_ID, "skin") or E:BlizzardAllowed(STABLE_ID, "skin") then return nil end
	return L["Turn on \"%s\" for the quest dialogs or the pet stable on the Blizzard UI page first."]:format(L["Skin"])
end

M.options = {
	{ type = "tab", label = "Quests and gossip" },
	{ type = "description", label = "What EldoUI may do with each window is set on the Blizzard UI page. The settings below work once its switch is on." },
	{ type = "header", label = "Look" },
	{ type = "toggle", key = "lightText", label = "Dark page, light text", disabled = QuestWait("skin"),
		desc = "Quest and gossip text in light letters on the dark EldoUI panel, using the game's own quest text contrast setting. Off keeps the parchment page and dark text." },
	{ type = "toggle", key = "transparent", label = "See-through windows", disabled = SkinWait,
		desc = "The dialogs' EldoUI panels let the game show through a little. How much: General > Panel opacity." },
	{ type = "header", label = "Text" },
	{ type = "range", key = "questFontSize", label = "Quest text size", min = 0, max = 20, step = 1, zeroText = "Game", disabled = QuestWait("improve"),
		desc = "Size of quest and gossip text, from 8 up; titles are 4 points larger. Game keeps the game's size." },
	{ type = "toggle", key = "instantQuestText", label = "Instant quest text", disabled = QuestWait("improve"),
		desc = "Quest text shows at once instead of fading in line by line (the game's instantQuestText setting)." },
	{ type = "header", label = "Rewards and quest helpers" },
	{ type = "description", label = "Upgrade arrows come from Upgrades, sell values from Quality of Life. Quest helpers are in Quality of Life > Quests, off by default." },
	{ type = "execute", label = "Upgrades settings", desc = "Arrows and the best-choice mark on quest rewards.",
		func = function() E:ToggleConfig("module:Upgrades") end },
	{ type = "execute", label = "Quality of Life settings", desc = "Reward sell values and the quest helpers (off by default).",
		func = function() E:ToggleConfig("module:QoL") end },
	{ type = "header", label = "Position and size" },
	{ type = "execute", label = "Open Windows", desc = "Dragging, the mouse wheel scale and the reset of every dialog are on the Move windows page, with every other Blizzard window.",
		func = function() E:ToggleConfig("windows") end },

	{ type = "tab", label = "Pet stable" },
	{ type = "header", label = "Stable slots" },
	{ type = "toggle", key = "stableHappiness", label = "Happiness on every slot", disabled = StableWait,
		desc = "The game's happy, content or unhappy face in the corner of every stabled pet." },
	{ type = "toggle", key = "stableLevel", label = "Level on every slot", disabled = StableWait,
		desc = "Each pet's level in the corner of its slot." },
	{ type = "toggle", key = "stableTooltip", label = "Loyalty in the tooltip", disabled = StableWait,
		desc = "Happiness and loyalty (with its level) when you point at a slot." },
}

---------------------------------------------------------------------------
-- Style presets
---------------------------------------------------------------------------
E:RegisterStyles("NPCWindows", {
	{ key = "EldoUI", title = "EldoUI", desc = "Dark panels with light text, the game's text size, quest text at the game's pace.",
		settings = { lightText = true, transparent = false, questFontSize = 0, instantQuestText = false } },
	{ key = "Parchment", title = "Parchment", desc = "EldoUI frames around Blizzard's parchment pages and dark text.",
		settings = { lightText = false, transparent = false, questFontSize = 0 } },
	{ key = "Glass", title = "Glass", desc = "See-through dark panels with light text.",
		settings = { lightText = true, transparent = true, questFontSize = 0 } },
	{ key = "Reader", title = "Reader", desc = "Larger quest text that shows at once.",
		settings = { lightText = true, questFontSize = 16, instantQuestText = true } },
	{ key = "Compact", title = "Compact", desc = "Smaller quest text for small screens. Window sizes are on the Move windows page.",
		settings = { lightText = true, questFontSize = 12 } },
})
