-- EldoUI Bags, part two: Blizzard's own bag, bank and guild bank windows.
-- Modules/Bags/Core.lua decides "replace" and "hide"; this file does what the
-- Skin, Move and Improve switches of the Blizzard UI page allow:
--
--   Bags ("bags-containers")
--     skin     container windows in the EldoUI look: flat panel, flat slots
--              with game-colored quality borders, flat search box.
--     move     the bag stack sits on EldoUI's "Bags" mover (EldoUI_BagsAnchor)
--              with its own scale; Blizzard still stacks the other bags.
--     improve  item level, BoE/BoU and junk marks on the slots, and the
--              lock mark on items a quest or recipe of yours needs
--              (Bags > Protect quest and recipe items).
--     The "Blizzard's bag windows" option sets the game's combinedBags CVar.
--   Bank ("bank")
--     skin     the bank window, its tabs, bag slots and item slots; the guild
--              bank too when "Guild bank" is set to EldoUI skin.
--     move     the bank on the "Bank" mover (EldoUI_BankAnchor), the guild
--              bank on its own "Guild bank" mover (EldoUI_GuildBank).
--
-- Taint rules (Core/Skin.lua): Blizzard art only gets SetAlpha / texture
-- coordinates, extra visuals live in child frames EldoUI creates, per-button
-- state is kept in local weak tables, and every hook checks the switches
-- each time it runs. With an element's master switch off nothing here
-- touches Blizzard's frames. Skins are only fully undone by /reload (the
-- Blizzard UI page asks for one).
-- Written from scratch for EldoUI; no code or media from other addons.
local _, E = ...

local M = E:GetModule("Bags")
if not M then return end

local BAGS_ID, BANK_ID = "bags-containers", "bank"

local parts = setmetatable({}, { __mode = "k" })     -- Blizzard item button -> EldoUI overlay parts
local hooked = setmetatable({}, { __mode = "k" })    -- Blizzard object -> true once hooked
local iconSkins = setmetatable({}, { __mode = "k" }) -- Blizzard icon button -> edge frame
local moved = { bags = false, bank = false, guild = false }

---------------------------------------------------------------------------
-- Switch checks (every hook calls these each time it runs)
---------------------------------------------------------------------------
local function BagsShown()
	return M.active and E:BlizzardAllowed(BAGS_ID) and not E:BlizzardHidden(BAGS_ID)
end
local function SkinBags() return BagsShown() and E:BlizzardAllowed(BAGS_ID, "skin") end
local function ImproveBags() return BagsShown() and E:BlizzardAllowed(BAGS_ID, "improve") end
local function MoveBags() return BagsShown() and E:BlizzardAllowed(BAGS_ID, "move") end

local function BankShown()
	return M.active and E:BlizzardAllowed(BANK_ID) and not E:BlizzardHidden(BANK_ID)
end
local function SkinBank() return BankShown() and E:BlizzardAllowed(BANK_ID, "skin") end
local function MoveBank() return BankShown() and E:BlizzardAllowed(BANK_ID, "move") end

-- The guild bank has no EldoUI replacement, so the bank's Hide / Replace
-- switches leave it alone; "Guild bank: Blizzard" keeps it untouched.
local function GuildOn() return M.active and E:BlizzardAllowed(BANK_ID) and M.db.guildBank == "skin" end
local function SkinGuild() return GuildOn() and E:BlizzardAllowed(BANK_ID, "skin") end
local function MoveGuild() return GuildOn() and E:BlizzardAllowed(BANK_ID, "move") end

local function Alpha(region, alpha)
	if region and region.SetAlpha then region:SetAlpha(alpha) end
end

---------------------------------------------------------------------------
-- Item slots: an edge frame (skin) and an overlay frame (improve), both
-- children EldoUI creates; Blizzard's button only loses its art via alpha.
---------------------------------------------------------------------------
local function SlotIcon(button)
	local name = button.GetName and button:GetName()
	return button.icon or button.Icon or (name and _G[name .. "IconTexture"])
end

local function Parts(button)
	local p = parts[button]
	if p then return p end
	p = {}
	local edge = CreateFrame("Frame", nil, button)
	edge:SetAllPoints()
	edge:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
	E:SetTemplate(edge)
	edge:SetBackdropColor(0, 0, 0, 0.35)
	edge:Hide()
	p.edge = edge

	local over = CreateFrame("Frame", nil, button)
	over:SetAllPoints()
	over:SetFrameLevel(button:GetFrameLevel() + 3)
	over:Hide()
	p.over = over
	-- Item level and bind text follow the text settings of the Slots tab.
	p.level = E:CreateText(over, E.tokens.size.label, "LEFT")
	M:StyleSlotText(p.level, "level", over)
	p.bind = E:CreateText(over, E.tokens.size.tiny, "LEFT")
	p.bind:SetPoint("BOTTOMLEFT", 2, 2)
	M:StyleSlotText(p.bind, "bind", over)
	p.bind:SetTextColor(E:TokenColor("secondary"))
	p.coin = over:CreateTexture(nil, "OVERLAY")
	p.coin:SetSize(12, 12)
	p.coin:SetPoint("TOPLEFT", 2, -2)
	p.coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
	-- Lock mark, the same mark and corner as EldoUI's own bags.
	p.lock = over:CreateTexture(nil, "OVERLAY")
	p.lock:SetSize(12, 12)
	p.lock:SetPoint("TOPRIGHT", -2, -2)
	p.lock:SetTexture(E.ItemProtect and E.ItemProtect.LOCK_ICON)
	p.lock:Hide()
	-- Junk "darken" is a shade over the icon, so Blizzard's own icon
	-- coloring (locked, unusable) is never overwritten.
	p.dim = over:CreateTexture(nil, "ARTWORK")
	p.dim:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	p.dim:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	p.dim:SetColorTexture(0, 0, 0, 0.4)
	parts[button] = p
	return p
end

local function SkinSlotArt(button, p)
	if p.skinned then return end
	p.skinned = true
	Alpha(button.GetNormalTexture and button:GetNormalTexture(), 0)
	Alpha(button.IconBorder, 0)
	Alpha(button.Background, 0)
	local icon = SlotIcon(button)
	if icon then
		E:TrimIcon(icon)
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
		icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	end
end

-- Best effort back to Blizzard's look (a /reload is exact).
local function UnskinSlotArt(button, p)
	if not p.skinned then return end
	p.skinned = nil
	Alpha(button.GetNormalTexture and button:GetNormalTexture(), 1)
	Alpha(button.IconBorder, 1)
	Alpha(button.Background, 1)
	local icon = SlotIcon(button)
	if icon then
		icon:SetTexCoord(0, 1, 0, 1)
		icon:ClearAllPoints()
		icon:SetAllPoints(button)
	end
end

local function ResetSlot(button)
	local p = parts[button]
	if not p then return end
	p.edge:Hide()
	p.over:Hide()
	UnskinSlotArt(button, p)
end

-- Lock mark: the Bags switch and Core/ItemProtect.lua decide.
local function Protected(itemID, bag, slot)
	if not (M.db.protectItems and E.IsItemProtected and itemID) then return false end
	local ok, protected = pcall(E.IsItemProtected, E, itemID, bag, slot)
	return ok and protected and true or false
end
M.BlizzardSlotProtected = Protected
-- The overlay parts of one Blizzard slot (plugins read them).
function M.BlizzardSlotParts(button) return parts[button] end

-- data: quality, link, bound (false = not bound yet), quest, empty, protected.
local function PaintSlot(button, skin, improve, quality, link, bound, quest, empty, protected)
	if not (skin or improve) then
		ResetSlot(button)
		return
	end
	local p = Parts(button)
	if skin then
		SkinSlotArt(button, p)
		if empty then
			p.edge:SetBackdropBorderColor(unpack(E.media.borderColor))
		else
			p.edge:SetBackdropBorderColor(M.BorderColor(quality, quest))
		end
	end
	p.edge:SetShown(skin and true or false)
	if not improve or empty then
		p.over:Hide()
		return
	end
	p.over:Show()
	p.level:SetText(M.ItemLevelText(link, quality))
	p.level:SetTextColor(M:ItemLevelColor(quality))
	p.bind:SetText(M.BindText(link, bound))
	local coin, dim = M.JunkMarks(quality)
	p.coin:SetShown(coin and true or false)
	p.dim:SetShown(dim and true or false)
	-- The warn color is read when drawn, so the safe palette reaches it.
	local warn = E.tokens.text.warn
	p.lock:SetVertexColor(warn[1], warn[2], warn[3])
	p.lock:SetShown(protected and true or false)
end

-- Small icon buttons (bank bag slots, bank tabs, guild bank tabs): flat edge.
local function SkinIconButton(button)
	if not E:SkinUsable(button) or iconSkins[button] then return end
	Alpha(button.GetNormalTexture and button:GetNormalTexture(), 0)
	Alpha(button.Border, 0)
	Alpha(button.Background, 0)
	Alpha(button.IconBorder, 0)
	local icon = button.Icon or button.icon or button.IconTexture
	if icon and icon.SetTexCoord then
		E:TrimIcon(icon)
	end
	local edge = CreateFrame("Frame", nil, button)
	edge:SetAllPoints(icon or button)
	edge:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
	E:SetTemplate(edge)
	edge:SetBackdropColor(0, 0, 0, 0.35)
	iconSkins[button] = edge
end

---------------------------------------------------------------------------
-- Bags: Blizzard's container windows
---------------------------------------------------------------------------
local function PaintContainer(frame)
	if not (frame and frame.EnumerateValidItems) then return end
	local skin, improve = SkinBags(), ImproveBags()
	for _, button in frame:EnumerateValidItems() do
		if button and (skin or improve or parts[button]) then
			local bag, slot = button:GetBagID(), button:GetID()
			local info = bag and C_Container.GetContainerItemInfo(bag, slot)
			local quest = false
			if info and C_Container.GetContainerItemQuestInfo then
				local questInfo = C_Container.GetContainerItemQuestInfo(bag, slot)
				quest = questInfo and (questInfo.isQuestItem or questInfo.questID) and true or false
			end
			if info then
				PaintSlot(button, skin, improve, info.quality, info.hyperlink, info.isBound and true or false, quest, false,
					improve and Protected(info.itemID, bag, slot))
			else
				PaintSlot(button, skin, improve, nil, nil, nil, false, true)
			end
		end
	end
end

local function SkinContainer(frame)
	if not SkinBags() then return end
	E:SkinPanel(frame)
	-- The portrait is the bag's menu (filters, cleanup): keep it visible.
	Alpha(frame.PortraitContainer, 1)
	Alpha(frame.PortraitButton, 1)
end

local function HookContainer(frame)
	if hooked[frame] or not frame.UpdateItems then return end
	hooked[frame] = true
	hooksecurefunc(frame, "UpdateItems", function(self)
		SkinContainer(self)
		PaintContainer(self)
	end)
end

-- The first bag of Blizzard's stack is the one anchored to its parent.
local function FirstBag()
	for _, frame in ipairs(M.BlizzardBagFrames()) do
		if frame:IsShown() then
			local _, relativeTo = frame:GetPoint(1)
			if relativeTo == frame:GetParent() then return frame end
		end
	end
end

local function PlaceBags()
	if not MoveBags() then return end
	local anchor = _G.EldoUI_BagsAnchor
	if not anchor then return end
	local scale = (M.db.blizzard and M.db.blizzard.scale) or 1
	local first = FirstBag()
	if not first then return end
	if E.FrameCheck(first, "IsProtected") and InCombatLockdown() then return end
	-- Blizzard just set every bag's scale; the EldoUI scale multiplies it.
	if scale ~= 1 then
		for _, frame in ipairs(M.BlizzardBagFrames()) do
			if frame:IsShown() then frame:SetScale(frame:GetScale() * scale) end
		end
	end
	first:ClearAllPoints()
	first:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
	moved.bags = true
end

local function ApplyCombined()
	local want = M.db.blizzard and M.db.blizzard.combined or "game"
	if not BagsShown() then return end
	if want == "game" then
		E:RestoreCVars(BAGS_ID)
	else
		E:SetCVar("combinedBags", want == "combined" and "1" or "0", BAGS_ID)
	end
end

function M:ApplyBlizzardBags()
	if not E:BlizzardAllowed(BAGS_ID) then return end
	for _, frame in ipairs(self.BlizzardBagFrames()) do HookContainer(frame) end
	if not hooked.anchors and UpdateContainerFrameAnchors then
		hooked.anchors = true
		hooksecurefunc("UpdateContainerFrameAnchors", PlaceBags)
	end
	if SkinBags() then
		E:SkinEditBox(_G.BagItemSearchBox)
	end
	E:RunOutOfCombat(function()
		ApplyCombined()
		for _, frame in ipairs(self.BlizzardBagFrames()) do
			if frame:IsShown() then
				SkinContainer(frame)
				PaintContainer(frame)
			end
		end
		-- Re-stack so Move and the scale take effect (or go back to Blizzard's place).
		if (MoveBags() or moved.bags) and UpdateContainerFrameAnchors then
			moved.bags = false
			UpdateContainerFrameAnchors()
		end
	end)
end

-- A quest picked up or dropped changes the lock marks: repaint the shown
-- Blizzard bags (only EldoUI's own overlay textures change).
function M:RepaintBlizzardBags()
	if not ImproveBags() then return end
	for _, frame in ipairs(self.BlizzardBagFrames()) do
		if frame:IsShown() then PaintContainer(frame) end
	end
end

function M:RestoreBlizzardBags()
	for _, frame in ipairs(self.BlizzardBagFrames()) do
		if frame.EnumerateItems and frame.Items then
			for _, button in frame:EnumerateItems() do ResetSlot(button) end
		end
	end
	if moved.bags and UpdateContainerFrameAnchors then
		E:RunOutOfCombat(function()
			moved.bags = false
			UpdateContainerFrameAnchors()
		end)
	end
end

---------------------------------------------------------------------------
-- Bank: Blizzard's bank window (Forever's tab bank)
---------------------------------------------------------------------------
local function PaintBankButton(button)
	if not (button and button.GetBankTabID) then return end
	local skin = SkinBank()
	if not (skin or parts[button]) then return end
	local tab, slot = button:GetBankTabID(), button:GetContainerSlotID()
	local info = tab and slot and C_Container.GetContainerItemInfo(tab, slot)
	if info then
		local quest = false
		if C_Container.GetContainerItemQuestInfo then
			local questInfo = C_Container.GetContainerItemQuestInfo(tab, slot)
			quest = questInfo and (questInfo.isQuestItem or questInfo.questID) and true or false
		end
		PaintSlot(button, skin, false, info.quality, info.hyperlink, info.isBound and true or false, quest, false)
	else
		PaintSlot(button, skin, false, nil, nil, nil, false, true)
	end
end

local function PaintBankItems(panel)
	if not (panel and panel.EnumerateValidItems) then return end
	for button in panel:EnumerateValidItems() do
		if not hooked[button] and button.Refresh then
			hooked[button] = true
			hooksecurefunc(button, "Refresh", PaintBankButton)
		end
		PaintBankButton(button)
	end
end

local function SkinPool(pool)
	if not (pool and pool.EnumerateActive) then return end
	for button in pool:EnumerateActive() do SkinIconButton(button) end
end

local function SkinBankFrame()
	local frame = _G.BankFrame
	if not (frame and SkinBank()) then return end
	E:SkinPanel(frame)
	E:SkinEditBox(frame.BankItemSearchBox or _G.BankItemSearchBox)
	if frame.TabSystem and frame.TabSystem.tabs then
		E:SkinTabs(frame.TabSystem.tabs, { isSelected = function(tab) return tab.IsSelected and tab:IsSelected() or false end })
	end
	local panel = frame.BankPanel
	if panel then
		Alpha(panel.NineSlice, 0)
		Alpha(panel.EdgeShadows, 0)
		if panel.MoneyFrame then
			Alpha(panel.MoneyFrame.Border, 0)
			E:SkinButton(panel.MoneyFrame.WithdrawButton)
			E:SkinButton(panel.MoneyFrame.DepositButton)
		end
		if panel.AutoDepositFrame then E:SkinButton(panel.AutoDepositFrame.DepositButton) end
		local prompt = panel.PurchasePrompt
		if prompt and prompt.TabCostFrame then E:SkinButton(prompt.TabCostFrame.PurchaseButton) end
		SkinPool(panel.bankTabPool)
		if panel.PurchaseTab then SkinIconButton(panel.PurchaseTab) end
	end
	E:SkinButton(_G.BankFramePurchaseButton)
	SkinPool(frame.itemButtonBagPool)
	SkinPool(frame.bankPageTabPool)
end

local function PlaceBank()
	local frame, anchor = _G.BankFrame, _G.EldoUI_BankAnchor
	if not (frame and anchor and MoveBank() and frame:IsShown()) then return end
	if InCombatLockdown() and E.FrameCheck(frame, "IsProtected") then return end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
	frame:SetScale((M.db.blizzard and M.db.blizzard.bankScale) or 1)
	moved.bank = true
end
M.PlaceBlizzardBank = function() PlaceBank() end

local function HookBank()
	local frame = _G.BankFrame
	if not frame or hooked[frame] then return end
	hooked[frame] = true
	frame:HookScript("OnShow", function()
		SkinBankFrame()
		-- The panel manager places the frame after it is shown.
		C_Timer.After(0, PlaceBank)
	end)
	if frame.RefreshBagButtons then
		hooksecurefunc(frame, "RefreshBagButtons", function(self) if SkinBank() then SkinPool(self.itemButtonBagPool) end end)
	end
	if frame.RefreshPageTabs then
		hooksecurefunc(frame, "RefreshPageTabs", function(self) if SkinBank() then SkinPool(self.bankPageTabPool) end end)
	end
	local panel = frame.BankPanel
	if panel then
		for _, method in ipairs({ "GenerateItemSlotsForSelectedTab", "RefreshAllItemsForSelectedTab" }) do
			if panel[method] then hooksecurefunc(panel, method, PaintBankItems) end
		end
		if panel.RefreshBankTabs then
			hooksecurefunc(panel, "RefreshBankTabs", function(self) if SkinBank() then SkinPool(self.bankTabPool) end end)
		end
	end
end

---------------------------------------------------------------------------
-- Guild bank (Blizzard_GuildBankUI loads on demand)
---------------------------------------------------------------------------
local GUILD_ART = { "RedMarbleBG", "BlackBG", "TabTitleBG", "TabTitleBGLeft", "TabTitleBGRight",
	"TabLimitBG", "TabLimitBGLeft", "TabLimitBGRight" }

local function GuildButtons(frame)
	local list = {}
	for _, column in ipairs(frame.Columns or {}) do
		for _, button in ipairs(column.Buttons or {}) do list[#list + 1] = button end
	end
	return list
end

local function PaintGuild(frame)
	frame = frame or _G.GuildBankFrame
	if not frame or not GetCurrentGuildBankTab then return end
	local skin = SkinGuild()
	local tab = GetCurrentGuildBankTab()
	for _, button in ipairs(GuildButtons(frame)) do
		if skin or parts[button] then
			local texture, _, _, _, quality = GetGuildBankItemInfo(tab, button:GetID())
			if texture then
				PaintSlot(button, skin, false, quality, GetGuildBankItemLink(tab, button:GetID()), nil, false, false)
			else
				PaintSlot(button, skin, false, nil, nil, nil, false, true)
			end
		end
	end
end

local function SkinGuildFrame()
	local frame = _G.GuildBankFrame
	if not (frame and SkinGuild()) then return end
	E:SkinPanel(frame)
	for _, key in ipairs(GUILD_ART) do Alpha(frame[key], 0) end
	for _, column in ipairs(frame.Columns or {}) do Alpha(column.Background, 0) end
	if frame.MoneyFrameBG then E:StripTextures(frame.MoneyFrameBG) end
	local tabs = {}
	for i = 1, 4 do tabs[#tabs + 1] = _G["GuildBankFrameTab" .. i] end
	E:SkinTabs(tabs, { owner = frame })
	for i = 1, (MAX_GUILDBANK_TABS or 8) do
		local side = _G["GuildBankTab" .. i]
		if side then
			E:StripTextures(side)
			SkinIconButton(side.Button)
		end
	end
	E:SkinButton(frame.DepositButton)
	E:SkinButton(frame.WithdrawButton)
	if frame.BuyInfo then E:SkinButton(frame.BuyInfo.PurchaseButton) end
	if frame.Info then
		E:SkinButton(frame.Info.SaveButton)
		if frame.Info.ScrollFrame then E:SkinScrollBar(frame.Info.ScrollFrame.ScrollBar) end
	end
	if frame.Log then E:SkinScrollBar(frame.Log.ScrollBar) end
end

local guildAnchor

local function GuildAnchor()
	if guildAnchor then return guildAnchor end
	guildAnchor = _G.EldoUI_GuildBankAnchor or CreateFrame("Frame", "EldoUI_GuildBankAnchor", UIParent)
	local frame = _G.GuildBankFrame
	local width, height = 760, 440
	if frame then
		local w, h = frame:GetSize()
		if w and w > 0 then width, height = w, h end
	end
	guildAnchor:SetSize(width, height)
	if not E.movers.EldoUI_GuildBank then
		E:CreateMover(guildAnchor, "EldoUI_GuildBank", E.L["Guild Bank"], { "TOPLEFT", "UIParent", "TOPLEFT", 20, -120 }, { sample = false })
	end
	return guildAnchor
end

M.GuildAnchor = GuildAnchor

local function PlaceGuild()
	local frame = _G.GuildBankFrame
	if not (frame and MoveGuild() and frame:IsShown()) then return end
	if InCombatLockdown() and E.FrameCheck(frame, "IsProtected") then return end
	local anchor = GuildAnchor()
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
	frame:SetScale((M.db.blizzard and M.db.blizzard.bankScale) or 1)
	moved.guild = true
end

local function SetupGuild()
	local frame = _G.GuildBankFrame
	if not frame or hooked[frame] then return end
	hooked[frame] = true
	frame:HookScript("OnShow", function(self)
		SkinGuildFrame()
		PaintGuild(self)
		C_Timer.After(0, PlaceGuild)
	end)
	if frame.Update then hooksecurefunc(frame, "Update", PaintGuild) end
	if frame:IsShown() then
		SkinGuildFrame()
		PaintGuild(frame)
		PlaceGuild()
	end
end

---------------------------------------------------------------------------
-- Bank element: apply / restore
---------------------------------------------------------------------------
function M:ApplyBlizzardBank()
	if not E:BlizzardAllowed(BANK_ID) then return end
	HookBank()
	if not hooked.panels and UpdateUIPanelPositions then
		-- Panels are re-placed when another one opens or closes.
		hooked.panels = true
		hooksecurefunc("UpdateUIPanelPositions", function()
			PlaceBank()
			PlaceGuild()
		end)
	end
	if GuildOn() then
		if MoveGuild() then GuildAnchor() end
		if not hooked.guildAddon then
			hooked.guildAddon = true
			E:OnBlizzardAddOn("Blizzard_GuildBankUI", SetupGuild)
		end
	end
	E:RunOutOfCombat(function()
		SkinBankFrame()
		local frame = _G.BankFrame
		if frame and frame.BankPanel and frame:IsShown() then PaintBankItems(frame.BankPanel) end
		PlaceBank()
		if _G.GuildBankFrame and _G.GuildBankFrame:IsShown() then
			SkinGuildFrame()
			PaintGuild()
			PlaceGuild()
		end
	end)
end

function M:RestoreBlizzardBank()
	local frame = _G.BankFrame
	if frame and frame.BankPanel and frame.BankPanel.EnumerateValidItems then
		for button in frame.BankPanel:EnumerateValidItems() do ResetSlot(button) end
	end
	if _G.GuildBankFrame then
		for _, button in ipairs(GuildButtons(_G.GuildBankFrame)) do ResetSlot(button) end
	end
	-- Moved windows go back to the game's place the next time they open.
	E:RunOutOfCombat(function()
		if moved.bank and frame then frame:SetScale(1) end
		if moved.guild and _G.GuildBankFrame then _G.GuildBankFrame:SetScale(1) end
		moved.bank, moved.guild = false, false
	end)
end

-- Module switched off: back to Blizzard as far as possible without a reload.
function M:DisableBlizzard()
	self:RestoreBlizzardBags()
	self:RestoreBlizzardBank()
end
