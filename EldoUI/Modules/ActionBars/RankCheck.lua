-- EldoUI Action Bars: spell rank check.
--
-- Shows which action buttons still hold a lower rank of a spell the player
-- knows at a higher rank:
--   * a glow on those buttons (General > Glows, "Lower spell ranks"), while
--     the spellbook is open, always, or never;
--   * a "Check ranks" button on the spellbook page: a left-click lists the
--     slots in chat and lights them up, a right-click opens the keys and
--     spells preview, where Apply moves them to the highest rank (the
--     upgrade in Ranks.lua);
--   * a button kept at its rank on purpose (the preview's "Keep this
--     rank") never glows;
--   * /eui rankcheck and "Check ranks now" on the options page do the same
--     check from anywhere;
--   * the chat report also lists each macro whose text names a lower rank
--     ("Frostbolt(Rank 3)"); the macro editor updates it on a click
--     (Modules/Macros/Ranks.lua).
--
-- Buttons: EldoUI's bars, every bar built on LibActionButton (Bartender4,
-- ElvUI), Dominos, and Blizzard's own bars, the gamepad bars included.
-- Blizzard's buttons glow only while Blizzard UI > "Action button look"
-- allows Improve, and the
-- spellbook button needs "Spellbook and talents": Improve.
--
-- Information only. It reads the player's spellbook and action slots, never
-- combat data, and changes nothing until the player clicks the upgrade.
-- Glows are EldoUI's own frames laid over a button: the button itself is
-- never moved, resized, shown, hidden or written to. Overlays are made out
-- of combat; in combat they are only shown or hidden.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local M = E:GetModule("ActionBars")

local issecret = issecretvalue or function() return false end

local FEATURE = "spellranks"
local GLOW_KEY = "spellRanks"
local SPELLS_ELEMENT = "player-spells"
local BUTTON_ELEMENT = "action-button-look"
-- A check from the command or the options page lights the buttons this long
-- when the spellbook is closed.
local CHECK_SECONDS = 30

E:RegisterFeatureConflicts(FEATURE, { "NovaSpellRankChecker" })

E:RegisterGlowUser(GLOW_KEY, {
	title = "Lower spell ranks",
	desc = "Action buttons that still hold a lower rank of a spell you know at a higher rank (Action Bars, Spell ranks).",
	order = 15,
	button = true,
	default = { style = "pixel", colorMode = "custom", color = { 1, 0.55, 0.1 } },
})

local function Settings()
	return M.db and M.db.ranks
end

local function Setting(key, default)
	local settings = Settings()
	local value = settings and settings[key]
	if value == nil then return default end
	return value
end

-- Game globals that may not exist on every client: read without warnings.
local function G(name)
	return rawget(_G, name)
end

---------------------------------------------------------------------------
-- What a slot holds
---------------------------------------------------------------------------
-- The spell on `slot`, and true when it comes from a macro. A macro counts
-- when the game says it shows a spell right now (subtype "spell").
local function SlotSpell(slot)
	if not GetActionInfo or type(slot) ~= "number" or issecret(slot) then return nil end
	local kind, id, subType = GetActionInfo(slot)
	if issecret(kind) or issecret(id) or type(id) ~= "number" then return nil end
	if kind == "spell" then return id, false end
	if kind == "macro" and subType == "spell" and Setting("macros", true) then return id, true end
	return nil
end

-- Bar names for the player's action pages, the way Blizzard numbers its
-- bars (EldoUI's bars use the same pages).
local PAGE_BARS = { [1] = 1, [2] = 1, [3] = 4, [4] = 5, [5] = 3, [6] = 2, [13] = 6, [14] = 7, [15] = 8 }

local function SlotLabel(slot)
	local gamepad = M:GamepadSlotIndex(slot)
	if gamepad then return L["Gamepad bars, button %d"]:format(gamepad) end
	local page = math.floor((slot - 1) / 12) + 1
	local index = (slot - 1) % 12 + 1
	local bar = PAGE_BARS[page]
	if page == 2 then
		return L["Bar %d page 2, button %d"]:format(bar, index)
	elseif bar then
		return L["Bar %d, button %d"]:format(bar, index)
	end
	return L["Bar 1 stance page %d, button %d"]:format(page - 6, index)
end

---------------------------------------------------------------------------
-- The buttons that can show a slot
---------------------------------------------------------------------------
local LAB_NAMES = { "LibActionButton-1.0", "LibActionButton-1.0-ElvUI" }
M.LAB_NAMES = LAB_NAMES -- the spell cues watch the same libraries

-- Blizzard's own player bars; other Blizzard-template buttons (override,
-- possess, pet, stance) are never lit. A gamepad button counts while it
-- shows one of the gamepad bars' own action slots.
local function IsBlizzardBarButton(name)
	return name:match("^ActionButton%d+$") or name:match("^MultiBar%a*Button%d+$")
end

local function IsGamepadBarButton(name, slot)
	return name:match("^Gamepad") and M:GamepadSlotIndex(slot) ~= nil
end

local function IsOtherBlizzardButton(name)
	return name:match("^Override") or name:match("^Possess") or name:match("^Pet")
		or name:match("^Stance") or name:match("^Gamepad") or name:match("^Extra")
		or name:match("^MainMenuBar") or name:match("^Vehicle")
end

local function Usable(button)
	return type(button) == "table" and button.GetObjectType and not E.FrameCheck(button, "IsForbidden")
end

local function NumberOrNil(value)
	if type(value) == "number" and not issecret(value) then return value end
end

-- The action slot a LibActionButton button shows now.
local function LabSlot(button)
	local kind = button._state_type
	if issecret(kind) or kind ~= "action" then return nil end
	return NumberOrNil(button._state_action)
end

-- fn(button, slot, own) for every button that shows an action slot now;
-- own is true for EldoUI's buttons. `others` (default: the rank check's
-- own setting) takes in the buttons of other bar addons too.
local function ForEachActionButton(fn, others)
	local own = {}
	for _, header in pairs(M.bars or {}) do
		for _, button in ipairs(header.buttons or {}) do own[button] = true end
	end
	if others == nil then others = Setting("otherBars", true) end
	local seen = {}
	for _, libName in ipairs(LAB_NAMES) do
		local lib = LibStub and LibStub(libName, true)
		if lib and lib.GetAllButtons then
			for button in pairs(lib:GetAllButtons()) do
				if not seen[button] and Usable(button) and (own[button] or others) then
					seen[button] = true
					local slot = LabSlot(button)
					if slot then fn(button, slot, own[button] or false) end
				end
			end
		end
	end
	local events = G("ActionBarButtonEventsFrame")
	if type(events) == "table" and type(events.frames) == "table" then
		local blizzard = E:BlizzardAllowed(BUTTON_ELEMENT, "improve")
		for _, button in pairs(events.frames) do
			if not seen[button] and Usable(button) then
				seen[button] = true
				local name = button.GetName and button:GetName()
				if type(name) == "string" and not issecret(name) then
					local action = NumberOrNil(button.action)
					local allowed
					if IsBlizzardBarButton(name) or (action and IsGamepadBarButton(name, action)) then
						allowed = blizzard
					elseif not IsOtherBlizzardButton(name) then
						allowed = others   -- Dominos and other bar addons
					end
					if allowed and action then fn(button, action, false) end
				end
			end
		end
	end
end
-- Shared with the spell cues (Cues.lua).
M.ForEachActionButton = ForEachActionButton

---------------------------------------------------------------------------
-- Glows
---------------------------------------------------------------------------
-- button -> our overlay frame. The glow sits on the overlay, so a proc glow
-- on the same button keeps its own holder.
local overlays = setmetatable({}, { __mode = "k" })
local lit = setmetatable({}, { __mode = "k" })   -- overlay -> true while glowing
local checkButton                                -- the spellbook button

local function Overlay(button)
	local overlay = overlays[button]
	if overlay or InCombatLockdown() then return overlay end
	overlay = CreateFrame("Frame", nil, button)
	overlay:SetAllPoints(button)
	overlay:EnableMouse(false)
	overlays[button] = overlay
	return overlay
end

local function ClearGlows()
	for overlay in pairs(lit) do
		E:HideGlow(overlay)
		lit[overlay] = nil
	end
end

local spellbookOpen = false
local checkUntil = 0

local function Mode()
	local mode = Setting("highlight", "spellbook")
	if mode ~= "off" and mode ~= "always" and mode ~= "spellbook" then mode = "spellbook" end
	return mode
end

-- Should glows show right now?
local function Showing()
	if E:FeatureConflict(FEATURE) then return false end
	local mode = Mode()
	if mode == "off" then return false end
	if mode == "always" or spellbookOpen then return true end
	return GetTime() < checkUntil
end

function M:RefreshRankGlows()
	if not Showing() then
		ClearGlows()
		return 0
	end
	local scan = self:RankScan()
	local keep, count, deferred = {}, 0, false
	if next(scan.best) then
		ForEachActionButton(function(button, slot)
			local spellID = SlotSpell(slot)
			if spellID and self:LowRankTarget(scan, spellID) and not self:RankKept(slot, spellID) then
				local overlay = Overlay(button)
				if overlay then
					keep[overlay] = true
					count = count + 1
					if not lit[overlay] then
						E:ShowUserGlow(overlay, GLOW_KEY)
						lit[overlay] = true
					end
				else
					deferred = true
				end
			end
		end)
	end
	for overlay in pairs(lit) do
		if not keep[overlay] then
			E:HideGlow(overlay)
			lit[overlay] = nil
		end
	end
	-- A button met for the first time in combat gets its overlay after it.
	if deferred then E:RunOutOfCombat(function() M:RefreshRankGlows() end) end
	return count
end

-- Is the rank glow showing on `button`?
function M:RankGlowShown(button)
	local overlay = overlays[button]
	return overlay and lit[overlay] and true or false
end

-- The spellbook's Check ranks button, once it exists.
function M:RankCheckButton()
	return checkButton
end

local function QueueRefresh()
	E:Debounce("bars:rankglows", 0.2, function() M:RefreshRankGlows() end)
end

---------------------------------------------------------------------------
-- The check and its chat report
---------------------------------------------------------------------------
local function SpellLink(spellID, name)
	local link = C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(spellID)
	if type(link) == "string" and not issecret(link) then return link end
	return name
end

local function RankText(spellID)
	local rank = C_Spell and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(spellID)
	if type(rank) == "string" and not issecret(rank) and rank ~= "" then return rank end
end

-- Every player slot holding a lower rank, spells and macros alike:
-- { slot, from, to, name, macro }.
function M:FindRankCheckSlots(scan)
	local found = {}
	scan = scan or self:RankScan()
	if not next(scan.best) then return found end
	self:ForEachRankSlot(function(slot)
		local spellID, macro = SlotSpell(slot)
		local target, name = self:LowRankTarget(scan, spellID)
		if target and not self:RankKept(slot, spellID) then
			found[#found + 1] = { slot = slot, from = spellID, to = target, name = name, macro = macro }
		end
	end)
	return found
end

-- Check the bars: report in chat (when that option is on) and light the
-- buttons. `quiet` skips the chat lines (the spellbook opening).
function M:CheckRanks(quiet)
	if E:FeatureConflict(FEATURE) then
		local _, title = E:FeatureConflict(FEATURE)
		E:Print(L["%s already checks spell ranks, so EldoUI leaves it to that addon."]:format(title))
		return 0
	end
	local list = self:FindRankCheckSlots()
	if not spellbookOpen then checkUntil = GetTime() + CHECK_SECONDS end
	self:RefreshRankGlows()
	if quiet or not Setting("report", true) then return #list end
	-- Macros whose text names a lower rank, on the bars or not.
	local texts = Setting("macros", true) and E.MacroRankUpdates and E:MacroRankUpdates() or {}
	for _, macro in ipairs(texts) do
		local parts = {}
		for _, change in ipairs(macro.changes) do
			parts[#parts + 1] = L["%s to %s"]:format(("%s(%s)"):format(change.name, E:MacroRankText(change, change.rank)),
				E:MacroRankText(change))
		end
		E:Print(L["Macro %s names a lower rank: %s. Update it in /eui macros."]:format(macro.name, table.concat(parts, ", ")))
	end
	if #list == 0 then
		if #texts == 0 then
			E:Print(L["Every spell on your action bars uses the highest rank you know."])
		end
		return 0
	end
	local macros = 0
	for _, entry in ipairs(list) do
		local rank = RankText(entry.from)
		local text = SpellLink(entry.from, entry.name)
		if rank then text = ("%s (%s)"):format(text, rank) end
		local line = L["%s: %s, highest known: %s"]:format(SlotLabel(entry.slot), text, M.RankLabel(entry.to, entry.name))
		if entry.macro then
			line = line .. " " .. L["(macro)"]
			macros = macros + 1
		end
		E:Print(line)
	end
	local summary = #list == 1 and L["%d action slot holds a lower spell rank."] or L["%d action slots hold a lower spell rank."]
	summary = summary:format(#list)
	if #list > macros then
		summary = summary .. " " .. L["Right-click Check ranks in the spellbook or type /eui ranks to upgrade."]
	end
	if macros > 0 then
		summary = summary .. " " .. L["Macros change only when you click Update in /eui macros."]
	end
	E:Print(summary)
	return #list
end

---------------------------------------------------------------------------
-- Spellbook button
---------------------------------------------------------------------------

local function Book()
	local root = G("PlayerSpellsFrame")
	return root, root and root.SpellBookFrame
end

-- The button steps aside while the game's gamepad interface is on.
local function ButtonAllowed()
	return Setting("spellbookButton", true) and E:BlizzardAllowed(SPELLS_ELEMENT, "improve")
		and not E:FeatureConflict(FEATURE) and not E:GamepadUIActive()
end

local function CreateCheckButton()
	if checkButton then return checkButton end
	local _, book = Book()
	if not book then return nil end
	checkButton = E.UIKit.Button(book, { text = L["Check ranks"], minWidth = 100 })
	checkButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	checkButton:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" then
			M:UpgradeRanks()
		else
			M:CheckRanks()
		end
	end)
	checkButton:SetScript("OnEnter", function(self)
		if E.FrameCheck(GameTooltip, "IsForbidden") then return end
		E.UIKit.AnchorTooltip(self)
		GameTooltip:AddLine(L["Check ranks"])
		E.UIKit.TipText(GameTooltip, L["Lists the action buttons that hold a lower rank of a spell you know and lights them up."])
		E:TooltipHint(GameTooltip, { L["Click"], L["check the action bars"] },
			{ L["Right-click"], L["show the changes, then move them to the highest rank you know with Apply (macros change in /eui macros)"] })
		GameTooltip:Show()
	end)
	checkButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
	checkButton:Hide()
	return checkButton
end

-- Left of the spellbook's search box when it can be found, otherwise in the
-- page's top right corner.
local function PlaceCheckButton(book)
	checkButton:ClearAllPoints()
	local search = book.SearchBox
	if type(search) == "table" and search.GetLeft and search:GetLeft() then
		checkButton:SetPoint("RIGHT", search, "LEFT", -12, 0)
	else
		checkButton:SetPoint("TOPRIGHT", book, "TOPRIGHT", -340, -24)
	end
end

local function UpdateCheckButton()
	local _, book = Book()
	if not book then return end
	if not ButtonAllowed() then
		if checkButton then checkButton:Hide() end
		return
	end
	if not CreateCheckButton() then return end
	PlaceCheckButton(book)
	checkButton:SetShown(book:IsShown())
end

---------------------------------------------------------------------------
-- Spellbook open and closed. Blizzard's own EventRegistry signals and
-- HookScript only: nothing in Blizzard's spellbook is changed.
---------------------------------------------------------------------------
local hookedBook

local function SpellbookChanged()
	local _, book = Book()
	local open = book and book:IsShown() and true or false
	if open ~= spellbookOpen then
		spellbookOpen = open
		if not open then checkUntil = 0 end
		QueueRefresh()
	end
	UpdateCheckButton()
end

local function HookSpellbook()
	local root, book = Book()
	if not (root and book) or hookedBook == book then return end
	local first = hookedBook == nil
	hookedBook = book
	if first and EventRegistry and EventRegistry.RegisterCallback then
		for _, event in ipairs({ "PlayerSpellsFrame.SpellBookFrame.Show", "PlayerSpellsFrame.SpellBookFrame.Hide" }) do
			EventRegistry:RegisterCallback(event, SpellbookChanged, M.rankCheckOwner)
		end
	end
	book:HookScript("OnShow", SpellbookChanged)
	book:HookScript("OnHide", SpellbookChanged)
	root:HookScript("OnHide", SpellbookChanged)
	SpellbookChanged()
end

M.rankCheckOwner = {}

-- Settings changed (options page, profile switch, a Blizzard UI switch).
function M:ApplyRankCheck()
	HookSpellbook()
	UpdateCheckButton()
	QueueRefresh()
end

---------------------------------------------------------------------------
-- Events. Registered on our own owner key, so the check works while the
-- Action Bars module is off (like the upgrade).
---------------------------------------------------------------------------
local owner = M.rankCheckOwner

local function Refresh()
	if Mode() ~= "off" then QueueRefresh() end
end

for _, event in ipairs({ "ACTIONBAR_SLOT_CHANGED", "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE",
	"ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD" }) do
	E:RegisterEvent(event, Refresh, owner)
end

E:RegisterEvent("ADDON_LOADED", function(_, _, name)
	if name == "Blizzard_PlayerSpells" then M:ApplyRankCheck() end
end, owner)

-- The gamepad and mouse interfaces swap: the spellbook button follows.
E:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION", function() UpdateCheckButton() end, owner)

E:RegisterEvent("PLAYER_LOGIN", function()
	if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_PlayerSpells") then M:ApplyRankCheck() end
end, owner)

E:AddCommand("rankcheck", "list and light up the action buttons that hold a lower spell rank", function()
	M:CheckRanks()
end, "Keys and spells")

-- The spellbook button follows "Spellbook and talents": Improve, the glows
-- on Blizzard's bars "Action button look": Improve. Either switch changing
-- shows or hides them at once.
for _, element in ipairs({ SPELLS_ELEMENT, BUTTON_ELEMENT }) do
	E:RegisterBlizzardHandler(element, {
		apply = function() M:ApplyRankCheck() end,
		undo = function() M:ApplyRankCheck() end,
	})
end
