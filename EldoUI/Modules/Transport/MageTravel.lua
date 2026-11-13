-- EldoUI Mage Travel: one button that opens a list of the teleports and
-- portals you know (Data/Transport.lua, E.mageTravel), with how many runes
-- of each kind are in your bags. You click a row; the row casts that spell.
--
-- The rows are secure action buttons (type "spell") the game casts from
-- on your click, one cast per click. They are built and changed only out
-- of combat (E:RunOutOfCombat), and the list hides in combat (a state
-- driver); the button says so when it is clicked in a fight. Nothing is
-- cast on its own.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local M = E:NewModule("MageTravel", {
	title = "Mage Travel",
	category = "Quality of Life",
	desc = "Mages: one button that lists the teleports and portals you know, with your rune counts. Click a row to cast it.",
	frames = { "EldoUI_MageTravel", "EldoUI_MageTravelHolder", "EldoUI_MageTravelList" },
	movers = { "EldoUI_MageTravel" },
	savedKeys = { "profile.modules.MageTravel" },
	optionsPage = "module:MageTravel",
	presets = { "Standard", "Small", "Large", "Quiet", "OutOfCombat" },
	reload = false,
	defaults = {
		enabled = false,   -- a new button on screen: the player turns it on
		size = 36,
		counts = true,     -- rune counts on the rows and the button
		closeOnCast = true,
		visibility = E:VisibilityDefaults(), -- the shared visibility rules (the button)
	},
})
E.MageTravel = M
E:RegisterVisibilityFacet("EldoUI_MageTravel", "rules", { module = "MageTravel", setting = "visibility" })

-- The list hides in combat, so its secure rows never change or show during
-- a fight: a fixed rule the visibility engine turns into the state driver.
local LIST_RULE = E:VisibilityDefaults({ show = "nocombat" })

local Plain = E.Plain
local Secret = E.Secret
local DATA = E.mageTravel or { runes = {}, spells = {} }
local LAUNCHER_ICON = "Interface\\Icons\\Spell_Arcane_TeleportStormwind"
local LIST_WIDTH = 236
local PAD = 6

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
end

local function IsMage()
	local _, class = UnitClass("player")
	return not Secret(class) and class == "MAGE"
end
M.IsMage = IsMage

local function Known(id)
	local book = C_SpellBook
	if not book then return false end
	for _, check in ipairs({ book.IsSpellKnown, book.IsSpellInSpellBook }) do
		local known = Plain(Try(check, id))
		if known then return true end
	end
	return false
end

local function SpellName(id)
	local name = Plain(Try(C_Spell and C_Spell.GetSpellName, id))
	return type(name) == "string" and name ~= "" and name or nil
end

local function SpellIcon(id)
	return Plain(Try(C_Spell and C_Spell.GetSpellTexture, id))
end

local function RuneCount(kind)
	local id = DATA.runes[kind]
	local count = id and Plain(Try(C_Item.GetItemCount, id))
	return type(count) == "number" and count or 0
end
M.RuneCount = RuneCount

local function RuneName(kind)
	local id = DATA.runes[kind]
	local name = id and Plain(Try(C_Item.GetItemNameByID, id))
	if type(name) == "string" and name ~= "" then return name end
	if id then Try(C_Item.RequestLoadItemDataByID, id) end
	return kind == "portal" and L["Rune of Portals"] or L["Rune of Teleportation"]
end

-- The spells you know, teleports first: { { id, kind, name, icon } }.
function M:KnownSpells()
	local list = {}
	for _, spell in ipairs(DATA.spells) do
		if Known(spell.id) then
			list[#list + 1] = { id = spell.id, kind = spell.kind, name = SpellName(spell.id) or tostring(spell.id), icon = SpellIcon(spell.id) }
		end
	end
	return list
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local function LauncherTooltip(button)
	local Kit = E.UIKit
	GameTooltip:SetOwner(button, "ANCHOR_TOP")
	Kit.TipTitle(GameTooltip, L["Mage Travel"])
	local spells = M:KnownSpells()
	if #spells == 0 then
		Kit.TipText(GameTooltip, L["You know no teleport or portal yet. Mages learn them from level 20."])
	else
		Kit.TipText(GameTooltip, E:Plural(#spells, "%d teleport or portal you know.", "%d teleports and portals you know."):format(#spells))
	end
	if M.db.counts then
		Kit.TipPair(GameTooltip, RuneName("teleport"), RuneCount("teleport"))
		Kit.TipPair(GameTooltip, RuneName("portal"), RuneCount("portal"))
	end
	Kit.TooltipHint(GameTooltip, { L["Click"], L["open the list"] })
	GameTooltip:Show()
end

function M:Build()
	if self.launcher then return end
	local Kit = E.UIKit
	local launcher = CreateFrame("Button", "EldoUI_MageTravel", UIParent)
	launcher:SetFrameStrata("LOW")
	launcher:RegisterForClicks("LeftButtonUp")
	E:SetTemplate(launcher)
	launcher.icon = launcher:CreateTexture(nil, "ARTWORK")
	launcher.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	launcher.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(launcher.icon)
	launcher.count = E:CreateText(launcher, E.tokens.size.small, "RIGHT")
	launcher.count:SetPoint("BOTTOMRIGHT", -2, 2)
	local highlight = launcher:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints(launcher.icon)
	highlight:SetColorTexture(1, 1, 1, E.tokens.hover.control)
	launcher:SetScript("OnClick", function(button, mouse)
		if E:IsOptionsLinkClick(button, mouse) then return end
		M:Toggle()
	end)
	launcher:SetScript("OnEnter", LauncherTooltip)
	launcher:SetScript("OnLeave", GameTooltip_Hide)
	E:BindOptionsLink(launcher, { page = "module:MageTravel" })
	self.launcher = launcher
	E:CreateMover(launcher, "EldoUI_MageTravel", L["Mage Travel"], { "BOTTOM", "UIParent", "BOTTOM", 470, 240 })

	-- The list lives in a secure holder that hides in combat (LIST_RULE).
	local holder = CreateFrame("Frame", "EldoUI_MageTravelHolder", UIParent, "SecureHandlerStateTemplate")
	holder:SetAllPoints(UIParent)
	holder:SetFrameStrata("DIALOG")
	E:AttachVisibility(holder, LIST_RULE, { secure = true, exempt = true, watch = false, module = "MageTravel" })
	self.holder = holder
	local list = CreateFrame("Frame", "EldoUI_MageTravelList", holder)
	list:SetSize(LIST_WIDTH, 40)
	list:EnableMouse(true)
	E:SetPanelTemplate(list)
	list:Hide()
	self.list = list
	list.labels = {
		teleport = Kit.SectionLabel(list, L["Teleports"]),
		portal = Kit.SectionLabel(list, L["Portals"]),
	}
	list.empty = Kit.Text(list, E.tokens.size.label, "LEFT", "secondary")
	list.empty:SetPoint("TOPLEFT", PAD + 2, -PAD - 2)
	list.empty:SetWidth(LIST_WIDTH - 2 * PAD - 4)
	list.empty:SetWordWrap(true)
	list.empty:SetText(L["You know no teleport or portal yet. Mages learn them from level 20."])
	self.rows = {}
end

local function RowTooltip(row)
	if not row.spellID then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(row.spellID) end
	E.UIKit.TooltipHint(GameTooltip, { L["Click"], L["cast it"] })
	GameTooltip:Show()
end

-- A row: a secure spell button dressed as a two-line list row (made out
-- of combat only).
function M:Row(index)
	local row = self.rows[index]
	if row then return row end
	row = CreateFrame("Button", "EldoUI_MageTravelRow" .. index, self.list, "SecureActionButtonTemplate")
	-- Act on the release: with the game's "cast on key press" setting a
	-- secure button otherwise waits for a press it never receives.
	row:RegisterForClicks("LeftButtonUp")
	row:SetAttribute("useOnKeyDown", false)
	row:SetAttribute("type", "spell")
	row:SetHeight(E.UIKit.TwoLineRowHeight())
	E.UIKit.DressListRow2(row)
	row:HookScript("PostClick", function()
		if M.db.closeOnCast then M:Close() end
	end)
	row:HookScript("OnEnter", RowTooltip)
	row:HookScript("OnLeave", GameTooltip_Hide)
	self.rows[index] = row
	return row
end

-- The rows' text: the rune count of each kind, dimmed with none.
function M:UpdateCounts()
	if not self.launcher then return end
	local counts = self.db.counts
	for _, row in ipairs(self.rows or {}) do
		if row.spellID and row.data then
			local count = RuneCount(row.kind)
			row.data.sub = counts and ("%s: %d"):format(RuneName(row.kind), count) or nil
			row.data.dimmed = counts and count == 0 or false
			row:SetRow(row.data)
		end
	end
	local teleports = RuneCount("teleport")
	self.launcher.count:SetText((counts and IsMage()) and tostring(teleports) or "")
end

-- The button follows the shared visibility rules (alpha only; the list
-- under it keeps its own rule).
function M:ApplyVisibility()
	local launcher = self.launcher
	if not launcher then return end
	local block = self.db.visibility
	if type(block) ~= "table" then
		block = E:VisibilityDefaults()
		self.db.visibility = block
	end
	if self.visibilityBlock ~= block then E:DetachVisibility(launcher) end
	if E:IsVisibilityAttached(launcher) then
		E:UpdateVisibility(launcher)
	else
		E:AttachVisibility(launcher, block, { forceShow = function() return E:IsMoveMode() end })
	end
	self.visibilityBlock = block
end

-- Rows for the spells you know, under their section labels. Out of combat.
function M:Layout()
	if not self.launcher then return end
	local db, list = self.db, self.list
	local shown = self.active and IsMage()
	self.launcher:SetSize(db.size, db.size)
	self.launcher:SetShown(shown or (E.IsMoveMode and E:IsMoveMode()) or false)
	local spells = shown and self:KnownSpells() or {}
	self.launcher.icon:SetTexture(spells[1] and spells[1].icon or E:ClientIcon(LAUNCHER_ICON))
	local y = PAD
	local labels = list.labels
	labels.teleport:Hide()
	labels.portal:Hide()
	local lastKind
	local rowHeight = E.UIKit.TwoLineRowHeight()
	for index, spell in ipairs(spells) do
		if spell.kind ~= lastKind then
			lastKind = spell.kind
			local label = labels[spell.kind]
			label:ClearAllPoints()
			label:SetPoint("TOPLEFT", list, "TOPLEFT", PAD + 4, -(y + 4))
			label:Show()
			y = y + (E.UIKit.CARD_LABEL or 22)
		end
		local row = self:Row(index)
		row:SetAttribute("spell", spell.id)
		row.spellID, row.kind = spell.id, spell.kind
		row.data = { icon = spell.icon, name = spell.name }
		row:ClearAllPoints()
		row:SetHeight(rowHeight)
		row:SetPoint("TOPLEFT", list, "TOPLEFT", PAD, -y)
		row:SetPoint("TOPRIGHT", list, "TOPRIGHT", -PAD, -y)
		row:Show()
		y = y + rowHeight
	end
	for index = #spells + 1, #self.rows do
		local row = self.rows[index]
		row:Hide()
		row:SetAttribute("spell", nil)
		row.spellID, row.data = nil, nil
	end
	list.empty:SetShown(#spells == 0)
	if #spells == 0 then y = y + (list.empty:GetStringHeight() or 14) + 4 end
	list:SetHeight(y + PAD)
	list:ClearAllPoints()
	list:SetPoint("BOTTOMLEFT", self.launcher, "TOPLEFT", 0, 4)
	self.shownSpells = #spells
	self:UpdateCounts()
end

function M:Refresh()
	E:RunOutOfCombat(function() M:Layout() end, "MageTravel:Layout")
end

function M:Open()
	if not (self.list and self.active and IsMage()) then return end
	if InCombatLockdown() then
		E.UIKit.Toast(self.launcher, L["The travel list opens when combat ends."])
		return
	end
	self:Layout()
	self.list:Show()
end

function M:Close()
	if not self.list then return end
	E:RunOutOfCombat(function() if M.list then M.list:Hide() end end, "MageTravel:Close")
end

function M:Toggle()
	if self.list and self.list:IsShown() and not InCombatLockdown() then
		self.list:Hide()
	else
		self:Open()
	end
end

---------------------------------------------------------------------------
-- Events and lifecycle
---------------------------------------------------------------------------
function M:OnEnable()
	self:Build()
	self:RegisterEvent("SPELLS_CHANGED", function() M:Refresh() end)
	self:RegisterEvent("PLAYER_LEVEL_UP", function() M:Refresh() end)
	self:RegisterEvent("BAG_UPDATE_DELAYED", function() M:UpdateCounts() end)
	self:RegisterEvent("GET_ITEM_INFO_RECEIVED", function() M:UpdateCounts() end)
	-- A list left open closes when a fight starts (it hides with its holder
	-- and stays closed afterwards).
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function() M:Close() end)
	self:Refresh()
	self:ApplyVisibility()
end

function M:OnDisable()
	self:Close()
	if self.launcher then E:DetachVisibility(self.launcher) end
	self.visibilityBlock = nil
	E:RunOutOfCombat(function()
		if M.launcher then M.launcher:Hide() end
	end, "MageTravel:Off")
end

function M:OnProfileChanged()
	if not self.active then return end
	self:Refresh()
	self:ApplyVisibility()
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
M.options = {
	{ type = "description", label = "Only for mages: your character is not a mage, so the button stays hidden.", tone = "warning", hidden = IsMage },
	{ type = "description", label = "One button lists the teleports and portals you know; click a row to cast it. The list hides in combat." },
	{ type = "header", label = "Button" },
	{ type = "range", key = "size", label = "Button size", min = 24, max = 56, step = 1, desc = "Size of the travel button." },
	{ type = "toggle", key = "counts", label = "Rune counts", desc = "How many Runes of Teleportation and Runes of Portals you carry: on the button and under each row. A kind you have none of is grayed out." },
	{ type = "toggle", key = "closeOnCast", label = "Close after a click", desc = "The list closes once you click a spell in it." },
	{ type = "execute", label = "Move", desc = "Unlock EldoUI frames to drag the travel button (mover \"Mage Travel\").", func = function() E:MoveFrame("EldoUI_MageTravel") end },
}
for _, row in ipairs(E:VisibilityOptions("visibility", { db = function() return M.db end })) do
	M.options[#M.options + 1] = row
end

---------------------------------------------------------------------------
-- Style presets: the button's size, the rune counts and when it shows.
-- None moves the button or changes which spells it lists.
---------------------------------------------------------------------------
E:RegisterStyles("MageTravel", {
	{ key = "Standard", title = L["Standard"], desc = L["A 36 px button with rune counts; the list closes after a cast."],
		settings = { size = 36, counts = true, closeOnCast = true, visibility = E:VisibilityDefaults() } },
	{ key = "Small", title = L["Small"], desc = L["A 28 px button without rune counts."],
		settings = { size = 28, counts = false, closeOnCast = true, visibility = E:VisibilityDefaults() } },
	{ key = "Large", title = L["Large"], desc = L["A 46 px button with rune counts, easy to hit."],
		settings = { size = 46, counts = true, closeOnCast = true, visibility = E:VisibilityDefaults() } },
	{ key = "Quiet", title = L["Quiet"], desc = L["A 32 px button that fades until the mouse is on it."],
		settings = { size = 32, counts = true, closeOnCast = true, visibility = E:VisibilityDefaults({ show = "mouseover" }) } },
	{ key = "OutOfCombat", title = L["Out of combat"], desc = L["The 36 px button hides in combat, like its list."],
		settings = { size = 36, counts = true, closeOnCast = true, visibility = E:VisibilityDefaults({ show = "nocombat" }) } },
})
