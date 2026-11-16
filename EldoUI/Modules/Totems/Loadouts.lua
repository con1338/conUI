-- EldoUI Shaman Totems: loadouts. Up to eight saved sets of four totems
-- (one per element). Right-click Drop All for the loadout menu: switch,
-- save your picks, rename, delete, share as a string, or take a starter
-- set for your role. A switch writes the bar's buttons and Call of the
-- Elements, so it waits until combat ends.
--
-- Optional content rule (off by default, it acts for you): a loadout per
-- kind of place (world, dungeon, raid, battleground or arena), switched
-- when you enter one, out of combat.
--
-- Public API (E.Totems, EldoUI.Totems for plugins):
--   Totems:Loadouts()            -> list of { index, name, EARTH, FIRE, WATER, AIR }
--   Totems:ApplyLoadout(index)   -> true, "queued" (in combat) or false
--   Totems:DefaultLoadout(role)  -> a starter set for "healer", "damage",
--                                   "tank" or "solo" (a copy)
--   Totems:LoadoutName(index)    -> its name, or nil
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local M = E:GetModule("ShamanTotems")
local D = E.ShamanData

local KIND = "totemloadout"
local PREFIX = "!EUTL1!" -- totem loadouts ("!EUT1!" is the talent plans' prefix)
local NAME_MAX = 24

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
local function Clean(set)
	if type(set) ~= "table" then return nil end
	local clean = { name = type(set.name) == "string" and set.name:gsub("|", ""):sub(1, NAME_MAX) or "" }
	local any = false
	for _, element in ipairs(D.ELEMENTS) do
		local key = set[element]
		local entry = type(key) == "string" and D.byKey[key]
		if entry and entry.element == element then
			clean[element] = key
			any = true
		else
			clean[element] = ""
		end
	end
	if not any then return nil end
	if clean.name == "" then clean.name = L["Loadout"] end
	return clean
end
M.CleanLoadout = Clean

function M:Loadouts()
	local list = {}
	for index = 1, self.MAX_LOADOUTS do
		local set = self.db.loadouts[index]
		if type(set) == "table" then
			local copy = Clean(set)
			if copy then
				copy.index = index
				list[#list + 1] = copy
			end
		end
	end
	return list
end

function M:LoadoutName(index)
	local set = type(index) == "number" and index > 0 and self.db and self.db.loadouts[index]
	return type(set) == "table" and set.name or nil
end

function M:DefaultLoadout(role)
	local base = D.DEFAULT_LOADOUTS[role] or D.DEFAULT_LOADOUTS.solo
	local copy = Clean(base)
	copy.name = L[base.name]
	return copy
end
-- L["Healing"], L["Damage"], L["Tanking"], L["Leveling"]

-- The totem keys of a set that you know; an unknown one keeps the
-- element's current pick.
local function Resolve(set)
	local picks = {}
	for _, element in ipairs(D.ELEMENTS) do
		local wanted = set[element]
		for _, item in ipairs(M:KnownTotems(element)) do
			if item.key == wanted then picks[element] = wanted break end
		end
	end
	return picks
end

local pending
-- Switch to a loadout (an index, or a set table). In combat the switch
-- waits for the fight to end.
function M:ApplyLoadout(which, quiet)
	local set = type(which) == "table" and Clean(which) or (type(which) == "number" and Clean(self.db.loadouts[which]))
	if not set then return false end
	local index = type(which) == "number" and which or 0
	local function Switch()
		pending = nil
		for element, key in pairs(Resolve(set)) do M.db.picks[element] = key end
		M.db.activeLoadout = index
		M:SyncCall()
		M:Refresh()
		if not quiet then E:Print(L["Totem loadout: %s"]:format(set.name)) end
	end
	if InCombatLockdown() then
		pending = set.name
		if not quiet then E:Print(L["The loadout %s switches when combat ends."]:format(set.name)) end
		E:RunOutOfCombat(Switch, "ShamanTotems:loadout")
		return "queued"
	end
	Switch()
	return true
end

function M:PendingLoadout() return pending end

-- Save the current picks into a slot (a free one when index is nil).
function M:SaveLoadout(index, name)
	if not index then
		for slot = 1, self.MAX_LOADOUTS do
			if type(self.db.loadouts[slot]) ~= "table" then index = slot break end
		end
	end
	if not index or index < 1 or index > self.MAX_LOADOUTS then return nil end
	local set = { name = name }
	for _, element in ipairs(D.ELEMENTS) do
		local pick = self:Pick(element)
		set[element] = pick and pick.key or ""
	end
	set = Clean(set)
	if not set then return nil end
	if not name or name == "" then set.name = L["Loadout %d"]:format(index) end
	self.db.loadouts[index] = set
	self.db.activeLoadout = index
	return index
end

function M:DeleteLoadout(index)
	if type(self.db.loadouts[index]) ~= "table" then return false end
	self.db.loadouts[index] = nil
	if self.db.activeLoadout == index then self.db.activeLoadout = 0 end
	for kind, slot in pairs(self.db.contentLoadouts) do
		if slot == index then self.db.contentLoadouts[kind] = 0 end
	end
	return true
end

function M:RenameLoadout(index, name)
	local set = self.db.loadouts[index]
	if type(set) ~= "table" or type(name) ~= "string" then return false end
	name = name:gsub("|", ""):sub(1, NAME_MAX)
	if name == "" then return false end
	set.name = name
	return true
end

---------------------------------------------------------------------------
-- Sharing: a loadout as a string (Import box, "Send to")
---------------------------------------------------------------------------
local function Describe(set)
	local parts = {}
	for _, element in ipairs(D.ELEMENTS) do
		local entry = D.byKey[set[element]]
		local name = entry and M.SpellName(entry.id)
		parts[#parts + 1] = ("%s: %s"):format(L[M.ELEMENT_TITLES[element]], name or "-")
	end
	return table.concat(parts, ", ")
end
M.DescribeLoadout = Describe

E:RegisterShareKind(KIND, {
	prefix = PREFIX,
	version = 1,
	title = function(data)
		local set = Clean(data)
		return set and L["Totem loadout: %s"]:format(set.name) or L["Totem loadout"]
	end,
	build = function(index)
		local set = Clean(M.db.loadouts[tonumber(index) or M.db.activeLoadout])
		if not set then
			set = { name = L["My totems"] }
			for _, element in ipairs(D.ELEMENTS) do
				local pick = M:Pick(element)
				set[element] = pick and pick.key or ""
			end
			set = Clean(set)
		end
		return set
	end,
	describe = function(data)
		local set = Clean(data)
		if not set then return { L["This loadout holds no totems."] } end
		return { Describe(set), L["It is saved as a new loadout; your bar switches only when you pick it."] }
	end,
	apply = function(data)
		local set = Clean(data)
		if not set then return end
		local index
		for slot = 1, M.MAX_LOADOUTS do
			if type(M.db.loadouts[slot]) ~= "table" then index = slot break end
		end
		if not index then
			E:Print(L["Every loadout slot is full. Delete one first."])
			return
		end
		M.db.loadouts[index] = set
		E:Print(L["Saved the totem loadout %s."]:format(set.name))
	end,
})

function M:ExportLoadout(index)
	E:ShowExport("share:" .. KIND .. ":" .. (index or self.db.activeLoadout or 0))
end

---------------------------------------------------------------------------
-- The menu (right-click Drop All)
---------------------------------------------------------------------------
local function AskName(text, accept)
	E:ShowConfirm({ key = "ELDOUI_TOTEM_LOADOUT", title = L["Totem loadout"], text = L["Name of the loadout:"],
		accept = E:GameText(ACCEPT, L["Accept"]), edit = { text = text or "", maxLetters = NAME_MAX },
		onAccept = function(_, typed) accept(typed or "") end })
end

-- A counter set: your picks with the counter totems a mob needs swapped in.
function M:CounterLoadout(kinds)
	local set = { name = L["Counter"] }
	for _, element in ipairs(D.ELEMENTS) do
		local pick = self:Pick(element)
		set[element] = pick and pick.key or ""
	end
	local any = false
	for kind in pairs(kinds or {}) do
		local entry = D.byKey[D.COUNTER_TOTEM[kind]]
		if entry and self:Known(entry.id) then
			set[entry.element] = entry.key
			any = true
		end
	end
	return any and set or nil
end

function M:OpenLoadoutMenu(owner)
	local Kit = E.UIKit
	Kit.ContextMenu(owner, function(_, root)
		root:CreateTitle(L["Totem loadouts"])
		local list = M:Loadouts()
		for _, set in ipairs(list) do
			local entry = root:CreateRadio(set.name, function() return M.db.activeLoadout == set.index end,
				function() M:ApplyLoadout(set.index) end)
			entry:SetTooltip(function(tooltip)
				Kit.TipTitle(tooltip, set.name)
				Kit.TipText(tooltip, Describe(set))
			end)
		end
		if #list == 0 then
			root:CreateButton(L["No loadouts yet"]):SetEnabled(false)
		end
		local counter = M.CounterKinds and M:CounterKinds()
		local counterSet = counter and M:CounterLoadout(counter)
		if counterSet then
			root:CreateDivider()
			root:CreateButton(L["Counter totems for your target"], function() M:ApplyLoadout(counterSet) end)
		end
		root:CreateDivider()
		local save = root:CreateButton(L["Save your picks"])
		save:CreateButton(L["As a new loadout"], function()
			AskName("", function(name)
				if not M:SaveLoadout(nil, name) then E:Print(L["Every loadout slot is full. Delete one first."]) end
			end)
		end)
		for _, set in ipairs(list) do
			save:CreateButton(L["Over %s"]:format(set.name), function() M:SaveLoadout(set.index, set.name) end)
		end
		local starter = root:CreateButton(L["Starter sets"])
		for _, role in ipairs({ "healer", "damage", "tank", "solo" }) do
			local set = M:DefaultLoadout(role)
			starter:CreateButton(set.name, function() M:ApplyLoadout(set) end)
		end
		if #list > 0 then
			local manage = root:CreateButton(L["Manage"])
			for _, set in ipairs(list) do
				local one = manage:CreateButton(set.name)
				one:CreateButton(L["Rename"], function()
					AskName(set.name, function(name) M:RenameLoadout(set.index, name) end)
				end)
				one:CreateButton(L["Share as a string"], function() M:ExportLoadout(set.index) end)
				one:CreateButton(L["Delete"], function() M:DeleteLoadout(set.index) end):SetDanger(true)
			end
		end
		root:CreateButton(L["Import a loadout"], function() E:ShowImport() end)
		root:CreateDivider()
		root:CreateButton(L["Shaman group panel"], function() M:OpenGroupWindow() end)
	end)
end

---------------------------------------------------------------------------
-- Content rule: a loadout per kind of place (acts for you; off by default)
---------------------------------------------------------------------------
function M:ContentKind()
	local inside, kind = IsInInstance()
	if E.Plain(inside) and (kind == "party" or kind == "raid") then return kind end
	if E.Plain(inside) and (kind == "pvp" or kind == "arena") then return "pvp" end
	return "world"
end

function M:ApplyContentRule()
	if not (self.db.contentRule and self:Drawing()) then return false end
	local index = self.db.contentLoadouts[self:ContentKind()] or 0
	if index <= 0 or index == self.db.activeLoadout or type(self.db.loadouts[index]) ~= "table" then return false end
	E:RunOutOfCombat(function() M:ApplyLoadout(index, true) end, "ShamanTotems:content")
	return true
end

local Rule = {}
M:AddPart("loadouts", Rule)
function Rule:OnEvent(event)
	if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then M:ApplyContentRule() end
end
