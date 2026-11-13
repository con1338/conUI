-- EldoUI Action Bars: spell rank upgrades.
--
-- WoW: Forever has spell ranks. After the player learns a new rank, action
-- slots still hold the old one. EldoUI finds those slots and moves them to
-- the highest rank the player knows, one of two ways:
--
--   * The offer (on by default): after a new rank is learned, and once at
--     login when lower ranks are on the bars, a popup opens the keys and
--     spells preview (Core/KeybindPreview.lua). Nothing changes until the
--     player presses its Apply. The button on the options page, /eui ranks
--     and a right-click on Check ranks open the same preview.
--   * "Upgrade spell ranks automatically" (off by default; the player
--     turns it on on the options page or in the setup): after a new rank,
--     a spellbook change, a bar turned on and at login, EldoUI moves the
--     lower ranks on every bar the player uses (or only bars 1 to 3 and
--     the gamepad bars, when the player picks that) out of combat, writes
--     one chat line per spell, and keeps the last pass for Undo
--     (/eui ranks undo).
--
-- Both ways:
--   * Only plain spell slots of the player's own action bars (pages 1-10
--     and 13-15, the same slots Blizzard's and EldoUI's bars show, and the
--     gamepad bars' own slots). Macros, items, the pet bar and
--     possess/vehicle/override pages are never touched.
--   * Spells on the exclude list stay at their rank (a low-rank heal kept
--     on purpose for mana, for example), and so does a single button the
--     player marks "Keep this rank" in the preview or fills with a lower
--     rank by hand.
--   * Only upward, only to a rank the player knows. EldoUI never picks a
--     rank for the target or the player's mana: that choice is the
--     player's (a kept low rank on its own button is the way to have both).
--   * Out of combat only; a rank learned in combat moves after it.
--   * Reads the player's spellbook and action slots, no combat data. A slot
--     whose contents come back secret is skipped.
--   * While another addon that moves spell ranks is loaded, the offer and
--     the automatic upgrade leave it to that addon.
-- Works with Blizzard's bars and with EldoUI's: the slots are the same.
-- It also works while the Action Bars module is off (the option is on the
-- Action Bars page).
local _, E = ...
local L = E.L

local M = E:GetModule("ActionBars")

local issecret = issecretvalue or function() return false end

-- Player action slots: pages 1-10 (bars 1-5, stance and form pages) and
-- 13-15 (bars 6-8). Pages 11-12 and 16+ are possess, vehicle and override.
local SLOT_RANGES = { { 1, 120 }, { 145, 180 } }

-- The game's gamepad interface keeps its own action slots above those
-- pages (E:GamepadActionSlots, Core/GamepadMode.lua).
local function GamepadSlots()
	return E:GamepadActionSlots()
end

-- fn(slot) for every player action slot, the gamepad bars last.
function M:ForEachRankSlot(fn)
	for _, range in ipairs(SLOT_RANGES) do
		for slot = range[1], range[2] do fn(slot) end
	end
	for _, slot in ipairs(GamepadSlots() or {}) do fn(slot) end
end

-- The button number of a gamepad action slot (1 for the first), or nil
-- when `slot` is not one of the gamepad bars.
function M:GamepadSlotIndex(slot)
	if type(slot) ~= "number" or slot <= SLOT_RANGES[#SLOT_RANGES][2] then return nil end
	local slots, first = GamepadSlots()
	if not slots then return nil end
	for _, valid in ipairs(slots) do
		if valid == slot then return slot - first + 1 end
	end
	return nil
end

local PLAYER_BANK = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
local SPELL_TYPE = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell

local function Settings()
	return M.db and M.db.ranks
end

-- Buttons kept at their rank on purpose, per character: action slot ->
-- the spell kept there. A button that holds another spell later is
-- upgraded again as usual.
E:RegisterPrivate("rankKeep", {})

local function KeptSlots()
	local store = E:GetPrivate("rankKeep")
	return type(store) == "table" and store or {}
end

-- Is `slot` kept at the rank of `spellID` on purpose?
function M:RankKept(slot, spellID)
	return spellID ~= nil and KeptSlots()[slot] == spellID
end

-- Keep (spellID) or stop keeping (nil) a button at its rank.
function M:KeepRank(slot, spellID)
	local store = E:GetPrivate("rankKeep")
	if type(store) ~= "table" or type(slot) ~= "number" then return end
	store[slot] = spellID
end

-- Lower-case names of the spells the player keeps at a low rank.
local function Excluded()
	local list = {}
	local text = Settings() and Settings().exclude
	if type(text) ~= "string" then return list end
	for name in text:gmatch("[^,\n]+") do
		name = strtrim(name):lower()
		if name ~= "" then list[name] = true end
	end
	return list
end

-- Is the spell known? A client without the check says "not known", so a
-- rank is never offered that the player may not have.
local function Known(spellID)
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
		if ok and not issecret(known) then return known and true or false end
	end
	return false
end

local function IsLowRank(slot, bank)
	if not (C_SpellBook and C_SpellBook.IsSpellBookItemLowRank) then return false end
	local ok, low = pcall(C_SpellBook.IsSpellBookItemLowRank, slot, bank)
	return ok and not issecret(low) and low and true or false
end

local function SpellName(spellID)
	if C_Spell and C_Spell.GetSpellName then
		local name = C_Spell.GetSpellName(spellID)
		if type(name) == "string" and not issecret(name) then return name end
	end
end

-- The rank number of a spell: the game's own rank of the ability, else the
-- number in its rank text ("Rank 4" in every client language); nil when
-- the spell has no ranks.
local function RankNumber(spellID)
	if type(spellID) ~= "number" or issecret(spellID) then return nil end
	if C_Spell and C_Spell.GetSpellSkillLineAbilityRank then
		local ok, rank = pcall(C_Spell.GetSpellSkillLineAbilityRank, spellID)
		if ok and type(rank) == "number" and not issecret(rank) and rank > 0 then return rank end
	end
	if C_Spell and C_Spell.GetSpellSubtext then
		local ok, text = pcall(C_Spell.GetSpellSubtext, spellID)
		if ok and type(text) == "string" and not issecret(text) then
			local rank = tonumber(text:match("(%d+)"))
			if rank and rank > 0 then return rank end
		end
	end
	return nil
end

-- Does `a` stand above `b`? By rank number when both have one, otherwise
-- the later spellbook entry wins (the spellbook lists ranks in order).
local function Above(a, b)
	if a.rank and b.rank then return a.rank > b.rank end
	return a.order > b.order
end

-- One pass over the player's spellbook:
--   best[name] = the highest known rank's spell ID
--   low[spellID] = true for ranks below that one (the game's low-rank flag,
--     or a smaller rank number than the best)
--   rank[spellID] = its rank number, when it has one
--   ids[name] = every spell ID of that name in the book (all its ranks)
local function ScanSpellBook()
	local best, low, rank, ids = {}, {}, {}, {}
	if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo) then return best, low, rank, ids end
	local byName, order = {}, 0
	for line = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if type(info) == "table" and not info.isGuild and info.offSpecID == nil then
			local first = (info.itemIndexOffset or 0) + 1
			for slot = first, first + (info.numSpellBookItems or 0) - 1 do
				local item = C_SpellBook.GetSpellBookItemInfo(slot, PLAYER_BANK)
				local spellID = type(item) == "table" and item.spellID
				if not issecret(spellID) and spellID and (not SPELL_TYPE or item.itemType == SPELL_TYPE)
					and not item.isPassive and type(item.name) == "string" and not issecret(item.name) then
					order = order + 1
					local entry = { id = spellID, rank = RankNumber(spellID), low = IsLowRank(slot, PLAYER_BANK), order = order }
					rank[spellID] = entry.rank
					local list = byName[item.name]
					if not list then
						list = {}
						byName[item.name] = list
					end
					list[#list + 1] = entry
				end
			end
		end
	end
	for name, list in pairs(byName) do
		local all = {}
		for _, entry in ipairs(list) do all[#all + 1] = entry.id end
		ids[name] = all
		local top
		for _, entry in ipairs(list) do
			if not entry.low and Known(entry.id) and (not top or Above(entry, top)) then top = entry end
		end
		-- The game's own lookup by name returns the highest rank it knows;
		-- it counts only when that spell is known and outranks the book.
		local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(name)
		local byLookup = type(info) == "table" and info.spellID
		if type(byLookup) == "number" and not issecret(byLookup) and (not top or byLookup ~= top.id)
			and SpellName(byLookup) == name and Known(byLookup) then
			local entry = { id = byLookup, rank = RankNumber(byLookup), order = order + 1 }
			if top and entry.rank and top.rank and entry.rank > top.rank then top = entry end
		end
		if top then
			best[name] = top.id
			for _, entry in ipairs(list) do
				if entry.id ~= top.id and (entry.low or (entry.rank and top.rank and entry.rank < top.rank)) then
					low[entry.id] = true
				end
			end
		end
	end
	return best, low, rank, ids
end

-- Is `spellID` (not in the scanned spellbook list) a lower rank?
local function LowRankByID(spellID)
	if not (C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell) then return false end
	local ok, slot, bank = pcall(C_SpellBook.FindSpellBookSlotForSpell, spellID, true, false)
	if not ok or issecret(slot) or not slot then return false end
	return IsLowRank(slot, bank or PLAYER_BANK)
end

-- One look at the spellbook, shared by the upgrade, the rank check
-- (RankCheck.lua) and the macro rank check: the highest known rank per
-- name, the ranks below it, rank numbers, and the spells the player keeps
-- at their rank.
function M:RankScan()
	local best, low, rank, ids = ScanSpellBook()
	return { best = best, low = low, rank = rank, ids = ids, excluded = Excluded(), checked = {} }
end

-- The rank number of a spell, or nil (see RankNumber above).
function M.SpellRankNumber(spellID)
	return RankNumber(spellID)
end

-- The highest rank of `spellID`'s spell the player knows, its name and its
-- rank number when `spellID` is a lower rank, otherwise nil. Never a
-- downgrade, never an unknown spell, never another spell of the same rank.
-- The exclude list is not applied here (see LowRankTarget).
function M:HighestKnownRank(spellID, scan)
	if type(spellID) ~= "number" or issecret(spellID) then return nil end
	scan = scan or self:RankScan()
	local name = SpellName(spellID)
	local target = name and scan.best[name]
	if not target or target == spellID then return nil end
	local from, to = scan.rank[spellID] or RankNumber(spellID), scan.rank[target] or RankNumber(target)
	if from and to and from >= to then return nil end
	if scan.low[spellID] or LowRankByID(spellID) or (from and to and from < to) then
		return target, name, to
	end
	return nil
end

-- The highest known rank of `spellID` and the spell's name when `spellID`
-- is a lower rank that should move up (not on the exclude list),
-- otherwise nil.
function M:LowRankTarget(scan, spellID)
	if type(spellID) ~= "number" or issecret(spellID) then return nil end
	local cached = scan.checked[spellID]
	if cached ~= nil then
		if cached then return cached[1], cached[2] end
		return nil
	end
	local target, name = self:HighestKnownRank(spellID, scan)
	if target and not scan.excluded[name:lower()] then
		scan.checked[spellID] = { target, name }
		return target, name
	end
	scan.checked[spellID] = false
	return nil
end

-- Every action slot that holds a lower rank: { slot, from, to, name }.
function M:FindLowRankSlots(scan)
	local found = {}
	if not GetActionInfo then return found end
	scan = scan or self:RankScan()
	if not next(scan.best) then return found end
	self:ForEachRankSlot(function(slot)
		local kind, id = GetActionInfo(slot)
		if not issecret(kind) and not issecret(id) and kind == "spell" and type(id) == "number" then
			local target, name = self:LowRankTarget(scan, id)
			if target and not self:RankKept(slot, id) then
				found[#found + 1] = { slot = slot, from = id, to = target, name = name }
			end
		end
	end)
	return found
end

-- Every button that holds a lower rank, for the keys and spells preview,
-- with what may happen to it: { slot, from, to, name, status, macro }.
-- status: "upgrade" (a plain spell that can move up), "excluded" (its
-- spell is on the exclude list), "kept" (this button is kept at its rank),
-- "macro" (a macro shows it: macros are never changed here).
function M:RankPlan(scan)
	local list = {}
	if not GetActionInfo then return list end
	scan = scan or self:RankScan()
	if not next(scan.best) then return list end
	self:ForEachRankSlot(function(slot)
		local kind, id, subType = GetActionInfo(slot)
		if not issecret(kind) and not issecret(id) and type(id) == "number"
			and (kind == "spell" or (kind == "macro" and subType == "spell")) then
			local target, name = self:HighestKnownRank(id, scan)
			if target then
				local status = "upgrade"
				if kind == "macro" then
					status = "macro"
				elseif scan.excluded[name:lower()] then
					status = "excluded"
				elseif self:RankKept(slot, id) then
					status = "kept"
				end
				list[#list + 1] = { slot = slot, from = id, to = target, name = name, status = status, macro = kind == "macro" }
			end
		end
	end)
	return list
end

function M.RankLabel(spellID, name)
	local rank = C_Spell and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(spellID)
	if type(rank) == "string" and not issecret(rank) and rank ~= "" then
		return ("%s (%s)"):format(name, rank)
	end
	return name
end

-- Another addon that moves spell ranks on its own: while one is loaded,
-- the automatic upgrade and the offer stand down (the glows and Check
-- ranks keep working).
local UPGRADE_FEATURE = "spellrankupgrade"
E:RegisterFeatureConflicts(UPGRADE_FEATURE, { "AutoSpellRanks", "MooseMode" })

-- The addon's title while another addon moves spell ranks, otherwise nil.
function M:RankUpgradeConflict()
	local addon, title = E:FeatureConflict(UPGRADE_FEATURE)
	if addon then return title or addon end
	return nil
end

-- Move the listed slots to their highest rank: the keys and spells
-- preview's Apply calls this with the buttons the player ticked. Called
-- without a list (the options button, /eui ranks, the spellbook button),
-- it opens that preview instead, so the player sees every button first.
-- Out of combat only.
function M:UpgradeRanks(list)
	if list == nil and E.OpenKeysAndSpells then
		E:OpenKeysAndSpells("ranks")
		return 0
	end
	if InCombatLockdown() then
		E:Print(L["Spell ranks can be upgraded after combat."])
		return 0
	end
	if GetCursorInfo and GetCursorInfo() then
		E:Print(L["Put down what is on your cursor first, then upgrade the spell ranks."])
		return 0
	end
	local place = E.PremadeSlots and E.PremadeSlots.Place
	if not place then return 0 end
	list = list or {}
	local done, spells = 0, {}
	for _, entry in ipairs(list) do
		-- The slot may have changed since the list was made.
		local kind, id = GetActionInfo(entry.slot)
		if not issecret(kind) and not issecret(id) and kind == "spell" and id == entry.from and not self:RankKept(entry.slot, id)
			and place(entry.slot, entry.to) then
			done = done + 1
			if not spells[entry.to] then
				spells[entry.to] = true
				spells[#spells + 1] = M.RankLabel(entry.to, entry.name)
			end
		end
	end
	local settings = Settings()
	if done > 0 and (not settings or settings.chat ~= false) then
		local text = done == 1 and L["%d action slot upgraded: %s."] or L["%d action slots upgraded: %s."]
		E:Print(text:format(done, table.concat(spells, ", ")))
	elseif done == 0 and #list > 0 then
		E:Print(L["Every spell on your action bars already uses its highest rank."])
	end
	return done
end

---------------------------------------------------------------------------
-- The automatic upgrade (only when the player turned it on)
---------------------------------------------------------------------------
-- The last automatic pass, per character, for Undo: { slots = { { slot,
-- from, to, name } }, time }.
E:RegisterPrivate("rankAuto", {})

-- A placement the game refused stops the automatic pass until the next
-- login, so a broken slot never repeats its error.
local stoodDown = false

-- The bar number (1-8) of a player action slot: bar 1 owns its bar page
-- 2 and its stance, form and stealth pages (7-10).
local function SlotBar(slot)
	if type(slot) ~= "number" then return nil end
	local page = math.floor((slot - 1) / 12) + 1
	if page == 2 or (page >= 7 and page <= 10) then return 1 end
	for index, info in ipairs(M.BARS or {}) do
		if info.page == page then return index end
	end
	return nil
end

-- Blizzard's bar of that number is on: the game shows it (its own "Action
-- Bar" setting) and EldoUI has not put it out of sight for its own bar.
local function BlizzardBarOn(index)
	local info = M.BARS and M.BARS[index]
	local bar = info and rawget(_G, info.blizzard)
	if type(bar) ~= "table" or type(bar.IsShown) ~= "function" then return false end
	if M.BlizzardBarShown and not M:BlizzardBarShown(index) then return false end
	local ok, shown = pcall(bar.IsShown, bar)
	return ok and not issecret(shown) and shown and true or false
end

-- Does the player use bar `index`? Bar 1 always. Bars 2 to 8 while they
-- are on: EldoUI's bar by its On switch (a bar the layout hides still
-- counts: its actions and keys stay in use), Blizzard's bar while the game
-- shows it. While another bar addon draws the bars, EldoUI cannot see
-- which of its bars are on, so every bar counts.
function M:RankBarInUse(index)
	if index == 1 then return true end
	if E.GetModuleConflict and E:GetModuleConflict(self) then return true end
	if self.active then
		local bar = self.db and self.db.bars and self.db.bars[index]
		if type(bar) == "table" and bar.enabled then return true end
	end
	return BlizzardBarOn(index)
end

-- Which slots the automatic pass may change. The gamepad bars always.
--   "used" (the default): every bar the player uses (M:RankBarInUse)
--   "main": bars 1 to 3, the bars the key set sets up (the same buttons
--     the preview ticks)
function M:RankAutoSlot(slot)
	if self:GamepadSlotIndex(slot) then return true end
	local settings = Settings()
	if settings and settings.scope == "main" then
		if E.KeybindSlotBar then
			local _, managed = E:KeybindSlotBar(slot)
			return managed and true or false
		end
		return slot <= 12 or (slot >= 49 and slot <= 120)
	end
	local bar = SlotBar(slot)
	return bar ~= nil and self:RankBarInUse(bar)
end

-- Profiles from before "Every bar I use": the old default (bars 1 to 3)
-- and the old "All my bars" both move to it once. "Bars 1 to 3" can be
-- picked again on the options page.
E:RegisterProfileMigration(function(profile)
	local modules = type(profile) == "table" and profile.modules
	local bars = type(modules) == "table" and modules.ActionBars
	local ranks = type(bars) == "table" and bars.ranks
	if type(ranks) == "table" and (ranks.scope == "main" or ranks.scope == "all") then ranks.scope = "used" end
end, "rankScopeUsed", 1)

local function AutoOn()
	local settings = Settings()
	return settings and settings.auto and not M:RankUpgradeConflict() and true or false
end

-- One chat line per spell: "Spell rank upgraded: Frostbolt (Rank 4) on 2
-- buttons."
local function ReportAuto(done)
	local settings = Settings()
	if settings and settings.chat == false then return end
	local order, counts = {}, {}
	for _, entry in ipairs(done) do
		if not counts[entry.to] then
			counts[entry.to] = 0
			order[#order + 1] = entry
		end
		counts[entry.to] = counts[entry.to] + 1
	end
	for _, entry in ipairs(order) do
		local count = counts[entry.to]
		E:Print(E:Plural(count, "Spell rank upgraded: %s on %d button.", "Spell rank upgraded: %s on %d buttons.")
			:format(M.RankLabel(entry.to, entry.name), count))
	end
end

-- Move every lower rank in scope to the highest rank the player knows.
-- Out of combat, with an empty cursor (a busy cursor tries again a moment
-- later and never drops what the player holds). Returns how many buttons
-- moved.
function M:AutoUpgradeRanks()
	if not AutoOn() or stoodDown then return 0 end
	if InCombatLockdown() then
		E:RunOutOfCombat(function() M:AutoUpgradeRanks() end, "ActionBars:autoRanks")
		return 0
	end
	if GetCursorInfo and GetCursorInfo() then
		E:Debounce("bars:ranks:cursor", 2, function() M:AutoUpgradeRanks() end)
		return 0
	end
	local place = E.PremadeSlots and E.PremadeSlots.Place
	if not place then return 0 end
	local done = {}
	for _, entry in ipairs(self:FindLowRankSlots()) do
		if self:RankAutoSlot(entry.slot) then
			local ok, why = place(entry.slot, entry.to)
			if ok then
				done[#done + 1] = entry
			elseif why == "cursor" or why == "combat" then
				E:Debounce("bars:ranks:cursor", 2, function() M:AutoUpgradeRanks() end)
				break
			else
				stoodDown = true
				E:Print(L["EldoUI could not move a spell rank on your action bars and stops upgrading them automatically until you log in again."])
				break
			end
		end
	end
	if #done > 0 then
		local record = E:GetPrivate("rankAuto")
		if type(record) == "table" then
			record.slots, record.time = done, time()
		end
		ReportAuto(done)
		if self.RefreshRankGlows then self:RefreshRankGlows() end
	end
	return #done
end

-- Something to put back from the last automatic pass.
function M:HasRankUndo()
	local record = E:GetPrivate("rankAuto")
	return type(record) == "table" and type(record.slots) == "table" and #record.slots > 0 or false
end

-- Put back the spells the last automatic pass changed, on the buttons that
-- still hold the upgraded spell, and keep those buttons at that rank (so
-- the next pass leaves them alone). Out of combat only.
function M:UndoRankUpgrade()
	if not self:HasRankUndo() then
		E:Print(L["There is no automatic spell rank upgrade to undo."])
		return 0
	end
	if InCombatLockdown() then
		E:Print(L["Spell ranks can be put back after combat."])
		return 0
	end
	if GetCursorInfo and GetCursorInfo() then
		E:Print(L["Put down what is on your cursor first, then upgrade the spell ranks."])
		return 0
	end
	local place = E.PremadeSlots and E.PremadeSlots.Place
	if not place then return 0 end
	local record = E:GetPrivate("rankAuto")
	local count = 0
	for _, entry in ipairs(record.slots) do
		local kind, id = GetActionInfo(entry.slot)
		if not issecret(kind) and not issecret(id) and kind == "spell" and id == entry.to and place(entry.slot, entry.from) then
			self:KeepRank(entry.slot, entry.from)
			count = count + 1
		end
	end
	record.slots, record.time = nil, nil
	E:Print(E:Plural(count, "%d button put back at its old rank and kept there.", "%d buttons put back at their old rank and kept there."):format(count))
	if self.RefreshRankGlows then self:RefreshRankGlows() end
	return count
end

---------------------------------------------------------------------------
-- The offer after a new rank is learned (when automatic is off)
---------------------------------------------------------------------------
local function Offer()
	local settings = Settings()
	if not (settings and settings.offer) or settings.auto or M:RankUpgradeConflict() then return end
	local list = M:FindLowRankSlots()
	if #list == 0 then return end
	local names, seen = {}, {}
	for _, entry in ipairs(list) do
		if not seen[entry.name] then
			seen[entry.name] = true
			names[#names + 1] = entry.name
		end
	end
	local text = E:Plural(#list, "EldoUI: %d action slot holds a lower rank of %s. Look at the change before it happens?",
		"EldoUI: %d action slots hold a lower rank of %s. Look at the changes before they happen?"):format(#list, table.concat(names, ", "))
	E:ShowConfirm({ key = "ELDOUI_RANK_UPGRADE", title = L["Action bars"], text = text, accept = L["Show the changes"], cancel = L["Not now"],
		onAccept = function() if E.OpenKeysAndSpells then E:OpenKeysAndSpells("ranks") end end })
end

-- What happens after a change to the spellbook: the automatic pass when
-- it is on, otherwise the offer (only for a newly learned rank or at
-- login, never on every spellbook refresh).
local function Pass(offer)
	if AutoOn() then
		M:AutoUpgradeRanks()
	elseif offer then
		Offer()
	end
end

-- A trainer teaches several ranks at once: wait a moment, then act once,
-- out of combat.
-- In combat the pass waits in the out-of-combat queue right away, once.
local function OfferPass() Pass(true) end
local function AutoPass() Pass(false) end
local function Learned()
	if InCombatLockdown() then
		E:RunOutOfCombat(OfferPass, "ActionBars:rankOffer")
		return
	end
	E:Debounce("bars:ranks", 1, function()
		E:RunOutOfCombat(OfferPass, "ActionBars:rankOffer")
	end)
end

local function SpellsChanged()
	if not AutoOn() then return end
	if InCombatLockdown() then
		E:RunOutOfCombat(AutoPass, "ActionBars:autoRanks")
		return
	end
	E:Debounce("bars:ranks:book", 1, function()
		E:RunOutOfCombat(AutoPass, "ActionBars:autoRanks")
	end)
end

-- A bar turned on (Action Bars options, a layout or a profile): its lower
-- ranks move a moment later, out of combat.
function M:RankBarsChanged()
	if not AutoOn() then return end
	E:Debounce("bars:ranks:book", 1, function()
		E:RunOutOfCombat(AutoPass, "ActionBars:autoRanks")
	end)
end

---------------------------------------------------------------------------
-- A lower rank put on a button by hand stays there
---------------------------------------------------------------------------
-- The player drags a lower rank from the spellbook or from another button
-- onto a button: that button is kept at that rank, the same as "Keep this
-- rank" in the preview, so the automatic pass never moves it back up. The
-- cursor tells it was the player's hand: the spell was on the cursor when
-- the slot changed, or left it a moment before. EldoUI's own writes (the
-- upgrade, Undo, the keys and spells setup, a snapshot) note themselves
-- first (E:NoteActionWrite) and never count.
local HAND_SECONDS = 1
local cursorSpell                  -- the spell on the cursor now
local leftCursor = {}              -- spellID -> when it left the cursor

local function CursorSpell()
	if not GetCursorInfo then return nil end
	local ok, kind, _, _, spellID = pcall(GetCursorInfo)
	if not ok or issecret(kind) or kind ~= "spell" or issecret(spellID) or type(spellID) ~= "number" then return nil end
	return spellID
end

local function CursorChanged()
	local spellID = CursorSpell()
	if cursorSpell and cursorSpell ~= spellID then leftCursor[cursorSpell] = GetTime() end
	cursorSpell = spellID
end

local function ByHand(spellID)
	if spellID == cursorSpell then return true end
	local left = leftCursor[spellID]
	return left ~= nil and GetTime() - left <= HAND_SECONDS
end

local function SlotChanged(_, _, slot)
	if type(slot) ~= "number" or issecret(slot) or slot < 1 or not GetActionInfo then return end
	local kind, id = GetActionInfo(slot)
	if issecret(kind) or issecret(id) or kind ~= "spell" or type(id) ~= "number" then return end
	local wrote = E.RecentActionWrite and E:RecentActionWrite(slot, id, HAND_SECONDS)
	if not ByHand(id) then return end
	leftCursor[id] = nil
	if wrote then return end
	if M:RankKept(slot, id) then return end
	local target, name = M:HighestKnownRank(id)
	if not target then return end
	M:KeepRank(slot, id)
	local settings = Settings()
	if AutoOn() and not (settings and settings.chat == false) then
		E:Print(L["%s stays at its rank on that button, because you put it there yourself."]:format(M.RankLabel(id, name)))
	end
end

-- At login and after a reload: ranks learned while EldoUI was off are
-- upgraded (automatic) or offered (the offer), a few seconds in, once the
-- spellbook and bars have loaded.
local LOGIN_DELAY = 3
local function EnteringWorld(_, _, isLogin, isReload)
	if not (isLogin or isReload) then return end
	stoodDown = false
	if C_Timer then
		C_Timer.After(LOGIN_DELAY, function()
			E:RunOutOfCombat(function() Pass(true) end, "ActionBars:rankOffer")
		end)
	end
end

local owner = {}   -- event owner key: works while the module is off
E:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE", Learned, owner)
E:RegisterEvent("SPELLS_CHANGED", SpellsChanged, owner)
E:RegisterEvent("PLAYER_ENTERING_WORLD", EnteringWorld, owner)
E:RegisterEvent("CURSOR_CHANGED", CursorChanged, owner)
E:RegisterEvent("ACTIONBAR_SLOT_CHANGED", SlotChanged, owner)

-- When the game draws the bars, its visibility update can show an extra
-- bar without going through EldoUI's settings: with the module off, and
-- with it on for a bar EldoUI leaves to Blizzard. RankBarsChanged checks
-- the automatic upgrade and the scope, and a burst of updates makes one
-- pass.
function M:BlizzardBarsDrawn()
	self:RankBarsChanged()
end
if type(MultiActionBar_Update) == "function" then
	hooksecurefunc("MultiActionBar_Update", function() M:BlizzardBarsDrawn() end)
end

E:AddCommand("ranks", "  move lower spell ranks on your action bars to the highest rank you know (undo: put back the last automatic upgrade)", function(args)
	if type(args) == "string" and strtrim(args):lower() == "undo" then
		E:RunOutOfCombat(function() M:UndoRankUpgrade() end, "ActionBars:rankUndo")
		return
	end
	M:UpgradeRanks()
end, "Tools")
