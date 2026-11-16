-- EldoUI Ready Check Report: when a ready check starts, one local
-- panel lists what each group member is missing: class buffs, a flask or
-- elixir, food, and (from members who share it) durability and EldoUI
-- version. Window.lua draws the panel, Options.lua holds the options page
-- and the style presets.
--
-- How it stays within the rules (Midnight / Forever):
--   * Auras are read only out of combat, through C_UnitAuras on the group
--     units, and every read is wrapped in pcall. A secret aura, name or
--     spell ID makes that member's buffs "unknown"; nothing secret is ever
--     compared. When the client refuses aura access the row says so.
--   * Buffs match by the spell's own name from the client
--     (C_Spell.GetSpellName), so every rank and every language counts.
--   * Durability and version of other members come only from members who
--     turned on "Share my durability and version" (off by default). Each
--     client sends its own line once when a ready check starts, through
--     E:SendComm (one message, within the addon message limits). Nobody is
--     ever asked for data and nothing is answered automatically.
--   * Clicking a row targets nobody and sends nothing. "Post to group" is
--     one click, one chat line with the summary.
--   * Never in combat: the panel closes when combat starts (UIKit) and is
--     not opened or refreshed while InCombatLockdown() is true.
--
-- Data: the buff and consumable groups below are EldoUI's own table of
-- spell IDs (public game knowledge, hand-checked against the class buff
-- table in Modules/Reminders.lua). Only the names the client returns for
-- these IDs are used.
--
-- Public API (E.ReadyReport, also EldoUI.ReadyReport):
--   M:Collect()        -> rows, summary   one row per member (see Row below)
--   M:Summary(rows)    -> { { key, count, text } }, line
--   M:Open() / M:Close() / M:Toggle()
--   M:Post()           the summary as one chat line to the group
--   M:SharePayload()   the line this client sends when sharing is on
--   M:AddColumn(def)   one more column (see M.extraColumns)
-- Written from scratch for EldoUI; no code, strings or data from other addons.
local _, E = ...
local L = E.L

local PREFIX = "EUI_RR"
local FORMAT = "1"

local M = E:NewModule("ReadyReport", {
	title = "Ready Check Report",
	desc = "When a ready check starts, one panel shows what each member is missing: class buffs, flask or elixir, food, and durability and version from members who share them.",
	category = "Group",
	defaults = {
		openOn = "lead",          -- "always", "lead" (you lead or assist) or "never"
		autoClose = true,         -- close after the ready check ends
		closeDelay = 10,          -- seconds after the ready check ends
		answerLine = "lead",      -- one chat line with the answers after the check: "lead", "always" or "never"
		checks = { ready = true, buffs = true, flask = true, food = true, durability = true, version = true },
		buffs = { FORT = true, INT = true, MOTW = true, BLESSING = true, SPIRIT = false, SHADOW = false },
		onlyGivers = true,        -- a buff counts only when a class that gives it is in the group
		share = false,            -- show a Share mine button that sends my durability and version once per click
		postButton = true,
		layout = "grid",          -- "grid" (icons), "list" (names) or "summary"
		rowHeight = 20,
		transparent = false,
		classColors = true,
	},
})
E.ReadyReport = M
M.PREFIX = PREFIX

-- More columns from other parts of EldoUI (the shaman column of Shaman
-- Totems): { key, title, width, align, desc, value = fn(row), text =
-- fn(row), shown = fn() }.
M.extraColumns = {}
function M:AddColumn(column)
	self.extraColumns[#self.extraColumns + 1] = column
end

---------------------------------------------------------------------------
-- Data: buff groups and consumables (spell IDs, names come from the client)
---------------------------------------------------------------------------
-- giver: the class that casts it. spells: rank 1 of the single and the
-- group version (every rank has the same name).
M.BUFFS = {
	{ key = "FORT", giver = "PRIEST", label = "Fortitude", spells = { 1243, 21562 } },         -- Power Word / Prayer of Fortitude
	{ key = "INT", giver = "MAGE", label = "Intellect", spells = { 1459, 23028 } },            -- Arcane Intellect / Brilliance
	{ key = "MOTW", giver = "DRUID", label = "Mark of the Wild", spells = { 1126, 21849 } },    -- Mark / Gift of the Wild
	{ key = "SPIRIT", giver = "PRIEST", label = "Spirit", spells = { 14752, 27681 } },         -- Divine Spirit / Prayer of Spirit
	{ key = "SHADOW", giver = "PRIEST", label = "Shadow Protection", spells = { 976, 27683 } }, -- Shadow Protection / Prayer of
	{ key = "BLESSING", giver = "PALADIN", label = "Blessing", spells = {
		19740, 19742, 20217,                          -- Might, Wisdom, Kings
		25782, 25894, 25898,                          -- the Greater versions
	} },
}
-- Lists of spell IDs, one row per line.
local function Flat(rows)
	local out = {}
	for _, row in ipairs(rows) do
		for _, id in ipairs(row) do out[#out + 1] = id end
	end
	return out
end
-- Flasks (the aura has the flask's own name). WoW: Forever adds the
-- Natural flasks (client tables of build 1.60.1.70938).
M.FLASKS = Flat({
	{ 17626, 17627, 17628, 17629, 17624 },            -- Titans, Distilled Wisdom, Supreme Power, Chromatic Resistance, Petrification
	{ 1293740, 1293741, 1293742, 1293743, 1293562 },  -- Natural Accuracy, Aggression, Precision, Swiftness (and its name)
})
-- Elixirs that give a lasting aura, then WoW: Forever's own elixirs, whose
-- aura is named after the elixir (build 1.60.1.70938).
M.ELIXIRS = Flat({
	{ 17538, 17539, 11405, 11390, 11474, 26276 },     -- Mongoose, Greater Arcane, Giants, Arcane, Shadow Power, Greater Firepower
	{ 21920, 11334, 3593, 17537, 24363, 24382 },      -- Frost Power, Greater Agility, Fortitude, Brute Force, Mageblood, Spirit of Zanza
	{ 1250918, 1250920, 1250922, 1250924, 1250925 },  -- Cunning, Phalanx, Minor, Lesser and plain Cleric's Elixir
	{ 1250926, 1250928, 1250931, 1250932, 1250940 },  -- Greater Cleric's, Fortitude, Greater Fortitude, Wicked Regeneration, Owl
	{ 1250941, 1250942, 1250944, 1250948, 1250971 },  -- Sages, Minor, Lesser and Greater Mageblood, Lesser Arcane
	{ 1250972, 1250974, 1250976, 1250978, 1250979 },  -- Nature Power, Minor, Lesser, plain and Greater Spirit
	{ 1250981, 1250984, 1250985, 1250986, 1250988 },  -- Whale, Strength, Ferocity, Grizzly, Lesser Intellect
	{ 1250989 },                                      -- Intellect
})
M.WELL_FED = 19705 -- any "Well Fed" aura; its name stands for the rest
-- Food auras by spell ID: the "Well Fed" ones of WoW: Forever, then the
-- stat foods whose aura has another name (Increased Stamina, Agility and
-- Spirit, Nightfin Soup's Mana Regeneration, Runn Tum Tuber Surprise's
-- Increased Intellect, Dirge's Kickin' Chimaerok Chops' Increased Stamina).
M.FOOD = Flat({
	{ 19705, 19706, 19708, 19709, 19710, 19711, 24799, 24870, 25694, 25941 },
	{ 1225778, 1225779, 1225780, 1225782, 1248406, 1248420, 1248421, 1248422 },
	{ 1248688, 1249519, 1249520, 1249521, 1249523, 1249907, 1249926, 1249927 },
	{ 1283082, 1294007, 1302064, 1319310 },
	{ 18191, 18192, 18193, 18194, 22730, 25661 },
})
-- Potions whose aura has a class buff's name (Shadow Protection Potion and
-- its Greater version): never read as the buff.
M.LOOKALIKES = { 7242, 17548 }

local Secret = E.Secret
M.Secret = Secret

local function SpellName(id)
	if not (C_Spell and C_Spell.GetSpellName) then return nil end
	local ok, name = pcall(C_Spell.GetSpellName, id)
	if not ok or Secret(name) or type(name) ~= "string" or name == "" then return nil end
	return name
end

local function SpellIcon(id)
	if not (C_Spell and C_Spell.GetSpellTexture) then return nil end
	local ok, icon = pcall(C_Spell.GetSpellTexture, id)
	if not ok or Secret(icon) then return nil end
	return icon
end

-- Names resolve once per session (the client knows them from the start;
-- an unknown ID simply has no name and is left out).
local names
function M.ResetNames() names = nil end
local function IdSet(...)
	local set = {}
	for index = 1, select("#", ...) do
		for _, id in ipairs((select(index, ...))) do set[id] = true end
	end
	return set
end
local function Names()
	if names then return names end
	names = { buffs = {}, flask = {}, elixir = {}, food = SpellName(M.WELL_FED),
		eating = SpellName(433), drinking = SpellName(430),
		flaskIds = IdSet(M.FLASKS), elixirIds = IdSet(M.ELIXIRS), foodIds = IdSet(M.FOOD),
		notBuff = IdSet(M.FLASKS, M.ELIXIRS, M.FOOD, M.LOOKALIKES) }
	for _, buff in ipairs(M.BUFFS) do
		local set = {}
		for _, id in ipairs(buff.spells) do
			local name = SpellName(id)
			if name then set[name] = true end
		end
		names.buffs[buff.key] = set
	end
	for _, id in ipairs(M.FLASKS) do
		local name = SpellName(id)
		if name then names.flask[name] = true end
	end
	for _, id in ipairs(M.ELIXIRS) do
		local name = SpellName(id)
		if name then names.elixir[name] = true end
	end
	return names
end
M.Names = Names

function M.BuffIcon(buff)
	return SpellIcon(buff.spells[1]) or 136243
end

function M.BuffByKey(key)
	for _, buff in ipairs(M.BUFFS) do
		if buff.key == key then return buff end
	end
end

---------------------------------------------------------------------------
-- Reads (secret-safe)
---------------------------------------------------------------------------
-- fn(...), or nothing when it fails or any answer is secret.
local Read = E.PlainCallAll
M.Read = Read

local function ShortName(name)
	if type(name) ~= "string" or Secret(name) then return nil end
	-- UnitName gives the name without the realm: match on that.
	local short = name:gsub("%-.*$", "")
	if short == "" then return nil end
	return short
end
M.ShortName = ShortName

-- The group's units, the player first.
function M.Units()
	local units = { "player" }
	if IsInRaid() then
		units = {}
		for index = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. index end
	elseif IsInGroup() then
		for index = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. index end
	end
	return units
end

-- Helpful aura names of a unit, or nil plus a reason when they can't be
-- read: "combat" (never read in combat), "restricted" (the client refuses
-- access or hides a value). The third value lists each aura as
-- { name, id }; id is nil when the spell ID can't be read, and the name
-- then decides alone.
function M.AuraNames(unit)
	if InCombatLockdown() then return nil, "combat" end
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil, "restricted" end
	local list, entries = {}, {}
	for index = 1, 80 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, "HELPFUL")
		if not ok or Secret(aura) then return nil, "restricted" end
		if type(aura) ~= "table" then break end
		local name = aura.name
		if Secret(name) then return nil, "restricted" end
		if type(name) == "string" then
			list[name] = true
			local id = aura.spellId
			if Secret(id) or type(id) ~= "number" then id = nil end
			entries[#entries + 1] = { name = name, id = id }
		end
	end
	return list, nil, entries
end

-- What one aura is: "flask", "elixir", "food", "eating" or nil. A readable spell ID
-- decides; without one the name does (a name two consumables share is
-- read as the listed one).
function M.AuraKind(set, aura)
	local id, name = aura.id, aura.name
	if id then
		if set.flaskIds[id] then return "flask" end
		if set.elixirIds[id] then return "elixir" end
		if set.foodIds[id] then return "food" end
		-- Every "Well Fed" is food, a newer one too.
		if set.food and name == set.food then return "food" end
		if (set.eating and name == set.eating) or (set.drinking and name == set.drinking) then return "eating" end
		return nil
	end
	if set.flask[name] then return "flask" end
	if set.elixir[name] then return "elixir" end
	if set.food and name == set.food then return "food" end
	if (set.eating and name == set.eating) or (set.drinking and name == set.drinking) then return "eating" end
	return nil
end

-- The player's lowest item durability in percent, or nil without any.
function M.OwnDurability()
	if type(GetInventoryItemDurability) ~= "function" then return nil end
	local lowest
	for slot = 1, 18 do
		local current, maximum = Read(GetInventoryItemDurability, slot)
		if type(current) == "number" and type(maximum) == "number" and maximum > 0 then
			local percent = current / maximum * 100
			if not lowest or percent < lowest then lowest = percent end
		end
	end
	return lowest and math.floor(lowest + 0.5) or nil
end

---------------------------------------------------------------------------
-- Shared lines (opt-in comms)
---------------------------------------------------------------------------
M.shared = {} -- short name -> { durability, version, at } (this session only)

function M:SharePayload()
	local durability = M.OwnDurability()
	local version = type(E.version) == "string" and E.version:gsub("[;%s]", "") or ""
	return ("%s;%s;%s"):format(FORMAT, durability and tostring(durability) or "", version)
end

-- Only from the player's click on Share mine (Forever forbids automated
-- communication), and once per ready check so a double click sends one line.
function M:SendShare()
	if not (self.active and self.db.share) then return false end
	if not IsInGroup() or self.sharedThisCheck then return false end
	local ok = E:SendComm(PREFIX, self:SharePayload(), "GROUP") and true or false
	if ok then
		self.sharedThisCheck = true
		self:Toast(L["Durability and version shared with the group."])
	end
	self:QueueRefresh()
	return ok
end

function M:OnShare(payload, sender)
	if type(payload) ~= "string" or Secret(payload) or #payload > 64 then return end
	local format, durability, version = payload:match("^(%d+);(%d*);([%w%.%-_]*)$")
	if format ~= FORMAT then return end
	local name = ShortName(sender)
	if not name then return end
	durability = tonumber(durability)
	if durability then durability = math.max(0, math.min(100, durability)) end
	self.shared[name] = { durability = durability, version = version ~= "" and version or nil, at = GetTime() }
	self:QueueRefresh()
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
-- Row = { unit, name, class, ready ("ready" / "notready" / "waiting" / nil),
--   state ("ok" / "offline" / "dead" / "combat" / "restricted"),
--   missing = { buffKey, ... }, flask, elixirs, food, durability, version,
--   shared (true when durability and version came from the member) }
local function ReadyState(unit)
	if type(GetReadyCheckStatus) ~= "function" then return nil end
	local status = Read(GetReadyCheckStatus, unit)
	if status == "ready" or status == "notready" or status == "waiting" then return status end
	return nil
end

-- Classes in the group (non-secret only).
local function GroupClasses(units)
	local classes = {}
	for _, unit in ipairs(units) do
		local _, class = Read(UnitClass, unit)
		if type(class) == "string" then classes[class] = true end
	end
	return classes
end

function M:WantedBuffs(classes)
	local list = {}
	for _, buff in ipairs(M.BUFFS) do
		if self.db.buffs[buff.key] and (not self.db.onlyGivers or classes[buff.giver]) then
			list[#list + 1] = buff
		end
	end
	return list
end

function M:Row(unit, wanted)
	if not Read(UnitExists, unit) then return nil end
	local name = Read(UnitName, unit)
	if type(name) ~= "string" then return nil end
	local _, class = Read(UnitClass, unit)
	local row = { unit = unit, name = name, class = class, ready = ReadyState(unit), missing = {} }
	local isPlayer = Read(UnitIsUnit, unit, "player")
	if Read(UnitIsConnected, unit) == false then
		row.state = "offline"
	elseif Read(UnitIsDeadOrGhost, unit) then
		row.state = "dead"
	else
		local auras, reason, entries = M.AuraNames(unit)
		if not auras then
			row.state = reason
		else
			row.state = "ok"
			local set = Names()
			-- Class buffs go by name (every rank shares it), leaving out a
			-- consumable that has the same name.
			local buffNames = {}
			for _, aura in ipairs(entries) do
				if not (aura.id and set.notBuff[aura.id]) then buffNames[aura.name] = true end
			end
			for _, buff in ipairs(wanted) do
				local has = false
				for buffName in pairs(set.buffs[buff.key] or {}) do
					if buffNames[buffName] then has = true break end
				end
				if not has then row.missing[#row.missing + 1] = buff.key end
			end
			row.elixirs, row.food, row.eating = 0, false, false
			for _, aura in ipairs(entries) do
				local kind = M.AuraKind(set, aura)
				if kind == "flask" then row.flask = true
				elseif kind == "elixir" then row.elixirs = row.elixirs + 1
				elseif kind == "food" then row.food = true
				elseif kind == "eating" then row.eating = true end
			end
		end
	end
	if isPlayer then
		row.durability = M.OwnDurability()
		row.version = E.version
		row.shared = true
	else
		local entry = self.shared[ShortName(name) or ""]
		if entry then
			row.durability, row.version, row.shared = entry.durability, entry.version, true
		end
	end
	return row
end

function M:Collect()
	local units = M.Units()
	local wanted = self:WantedBuffs(GroupClasses(units))
	local rows = {}
	for _, unit in ipairs(units) do
		local row = self:Row(unit, wanted)
		if row then rows[#rows + 1] = row end
	end
	self.wanted = wanted
	return rows, self:Summary(rows)
end

-- Counts for the summary line, in a fixed order.
function M:Summary(rows)
	local db = self.db
	local counts, order = {}, {}
	local function Add(key, text)
		if not counts[key] then
			counts[key] = { key = key, count = 0, text = text }
			order[#order + 1] = counts[key]
		end
		counts[key].count = counts[key].count + 1
	end
	local unknown = 0
	for _, row in ipairs(rows) do
		if row.state == "ok" then
			if db.checks.buffs then
				for _, key in ipairs(row.missing) do
					local buff = M.BuffByKey(key)
					Add("buff:" .. key, L[buff.label])
				end
			end
			if db.checks.flask and not row.flask and (row.elixirs or 0) == 0 then Add("flask", L["flask or elixir"]) end
			if db.checks.food and not row.food and not row.eating then Add("food", L["food"]) end
		elseif row.state == "combat" or row.state == "restricted" then
			unknown = unknown + 1
		end
		if db.checks.durability and row.durability and (E:DurabilityLevel(row.durability) or "ok") ~= "ok" then
			Add("durability", L["durability"])
		end
	end
	local parts = {}
	for _, item in ipairs(order) do
		local text
		if item.key:find("^buff:") then
			text = L["%d missing %s"]:format(item.count, item.text)
		elseif item.key == "durability" then
			text = L["%d at or below %d%% durability"]:format(item.count, E.db.general.durabilityWarn)
		else
			text = L["%d without %s"]:format(item.count, item.text)
		end
		item.line = text
		parts[#parts + 1] = text
	end
	local line
	if #rows == 0 then
		line = L["Nobody to check."]
	elseif #parts == 0 then
		line = L["Nothing missing."]
	else
		line = table.concat(parts, ", ")
	end
	if unknown > 0 then
		line = line .. " " .. L["(%d not readable)"]:format(unknown)
	end
	return order, line, unknown
end

---------------------------------------------------------------------------
-- Post (one click, one chat line)
---------------------------------------------------------------------------
-- Forever has no instance groups (no LE_PARTY_CATEGORY_INSTANCE): raid or party.
function M.GroupChannel()
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
end

function M:PostText()
	-- After a check: its answers. Before or during one: what is missing.
	if self.answers and not self.checking then return self.answers end
	local _, line = self:Summary(self.rows or {})
	return L["Ready check: %s"]:format(line)
end

function M:Post()
	if not self.active then return false end
	if InCombatLockdown() then return false end
	local channel = M.GroupChannel()
	if not channel then
		self:Toast(L["You are not in a group."], true)
		return false
	end
	if not E:TryChatPost(self:PostText(), channel) then
		self:Toast(E:ChatRefusedText(), true)
		return false
	end
	self:Toast(L["Summary posted to the group."])
	return true
end

---------------------------------------------------------------------------
-- When to open
---------------------------------------------------------------------------
local function IsLead()
	if not IsInGroup() then return false end
	if not IsInRaid() then return Read(UnitIsGroupLeader, "player") and true or false end
	return (Read(UnitIsGroupLeader, "player") or Read(UnitIsGroupAssistant, "player")) and true or false
end
M.IsLead = IsLead

function M:ShouldOpen()
	local mode = self.db.openOn
	if mode == "never" then return false end
	if InCombatLockdown() then return false end
	if self:PullCountdownActive() then return false end
	if mode == "lead" then return IsLead() end
	return true
end

-- Only automatic ready-check opening waits for a public pull countdown.
-- The player's explicit Open remains available, so both windows can show.
-- Expiry is read lazily, so no extra timer can reopen a window.
function M:PullCountdownActive()
	local untilTime = self.pullUntil
	if not untilTime then return false end
	if GetTime() < untilTime then return true end
	self.pullUntil = nil
	return false
end

function M:OnReadyCheck()
	self.checking = true
	self.closeAt = nil
	self.answers = nil
	local rows = {}
	for _, unit in ipairs(M.Units()) do
		local name = Read(UnitName, unit)
		if type(name) == "string" then
			rows[#rows + 1] = {
				unit = unit, name = name, guid = Read(UnitGUID, unit), ready = ReadyState(unit),
				fullName = Read(E.UnitWhisperName, E, unit),
				state = Read(UnitIsConnected, unit) == false and "offline" or nil,
			}
		end
	end
	self.answerRows = rows
	-- The time-left bar runs from the check's own length.
	self.checkLength = nil
	if type(GetReadyCheckTimeLeft) == "function" then
		local ok, left = pcall(GetReadyCheckTimeLeft)
		if ok and not E.Secret(left) and type(left) == "number" and left > 0 then self.checkLength = left end
	end
	-- Nothing is sent here: sharing waits for the player's click on Share mine.
	self.sharedThisCheck = false
	if self:ShouldOpen() then self:Open() else self:QueueRefresh() end
end

function M:OnReadyCheckConfirm(unit, ready)
	if self.answerRows and not Secret(unit) and type(unit) == "string"
		and not Secret(ready) and type(ready) == "boolean" then
		local guid, fullName = Read(UnitGUID, unit), Read(E.UnitWhisperName, E, unit)
		for _, row in ipairs(self.answerRows) do
			local same = row.guid and guid and row.guid == guid
			if same or ((not row.guid or not guid) and fullName and fullName == row.fullName
				and (row.unit == unit or Read(UnitIsUnit, row.unit, unit))) then
				row.unit = unit
				row.ready = ready and "ready" or "notready"
				break
			end
		end
	end
	self:QueueRefresh()
end

-- The answers of a finished check as one line: who is ready, who said not
-- ready, who never answered and who is offline. A secret answer counts as
-- unknown and is left out.
function M:AnswerLine(rows)
	local ready, notReady, waiting, offline = 0, {}, {}, {}
	for _, row in ipairs(rows or {}) do
		if row.state == "offline" then
			offline[#offline + 1] = row.name
		elseif row.ready == "ready" then
			ready = ready + 1
		elseif row.ready == "notready" then
			notReady[#notReady + 1] = row.name
		elseif row.ready == "waiting" then
			waiting[#waiting + 1] = row.name
		end
	end
	local parts = { L["Ready check: %d ready."]:format(ready) }
	if #notReady > 0 then parts[#parts + 1] = L["Not ready: %s."]:format(table.concat(notReady, ", ")) end
	if #waiting > 0 then parts[#parts + 1] = L["No answer: %s."]:format(table.concat(waiting, ", ")) end
	if #offline > 0 then parts[#parts + 1] = L["Offline: %s."]:format(table.concat(offline, ", ")) end
	return table.concat(parts, " ")
end

function M:WantsAnswerLine()
	local mode = self.db.answerLine
	if mode == "always" then return true end
	return mode == "lead" and M.IsLead()
end

function M:OnReadyCheckFinished(preempted)
	self.checking = false
	-- The answers stay readable after the check: printed here for you, and
	-- sent by Post to group only on a click. They come from the rows read
	-- during the check; once it ends the game no longer gives the answers.
	local rows = self.answerRows
	self.answerRows = nil
	if rows and #rows > 0 and not Secret(preempted) and not preempted then
		local unitsByGUID = {}
		for _, unit in ipairs(M.Units()) do
			local guid = Read(UnitGUID, unit)
			if type(guid) == "string" then unitsByGUID[guid] = unit end
		end
		for _, row in ipairs(rows) do
			local unit = row.guid and unitsByGUID[row.guid]
			if not row.guid and row.fullName and Read(E.UnitWhisperName, E, row.unit) == row.fullName then unit = row.unit end
			if unit then
				local connected = Read(UnitIsConnected, unit)
				if connected == false then row.state = "offline" end
				if connected == true then row.state = nil end
			end
		end
		self.answers = self:AnswerLine(rows)
		if self:WantsAnswerLine() then self:Print(self.answers) end
	end
	self:QueueRefresh()
	if not self.db.autoClose or not self:IsOpen() then return end
	local token = {}
	self.closeToken = token
	C_Timer.After(math.max(0, tonumber(self.db.closeDelay) or 0), function()
		if self.closeToken == token and not self.checking then self:Close() end
	end)
end

-- The pinned Forever UI source's WorldStateInfoDocumentation: timeRemaining is the
-- second START_PLAYER_COUNTDOWN argument. The event can carry secrets during
-- chat messaging lockdown: discard them before comparison or arithmetic.
-- Manual opening stays allowed; a later ready check does not reopen it.
function M:OnPullCountdown(timeRemaining)
	self.closeToken = nil
	if not Secret(timeRemaining) and type(timeRemaining) == "number"
		and timeRemaining == timeRemaining and timeRemaining > 0 and timeRemaining < math.huge then
		self.pullUntil = GetTime() + timeRemaining
	end
	if self:IsOpen() then self:Close() end
end

function M:ClearPullCountdown()
	self.pullUntil = nil
end

-- Many UNIT_AURA and comm events in a raid: one redraw a moment later.
function M:QueueRefresh()
	if self.refreshQueued or not self:IsOpen() then return end
	self.refreshQueued = true
	C_Timer.After(0.5, function()
		self.refreshQueued = false
		if self.active and not InCombatLockdown() then self:Refresh() end
	end)
end

function M:Command(arg)
	arg = (arg or ""):lower()
	if arg == "post" then
		self.rows = self:Collect()
		self:Post()
	else
		self:Toggle()
	end
end

-- Aura changes are heard only while the report is open, and only for the
-- group's own units, two units per registration (the game's limit), so the
-- auras of nameplates, targets and other players never wake the report.
-- The list follows the roster.
local auraUnits = {} -- "unit1,unit2" -> { unit1, unit2 }

local function OnAura()
	M:QueueRefresh()
end

function M:SyncAuraUnits()
	local wanted = {}
	if self.active and self:IsOpen() then
		local units = M.Units()
		for index = 1, #units, 2 do
			local pair = { units[index], units[index + 1] }
			wanted[table.concat(pair, ",")] = pair
		end
	end
	for key, pair in pairs(auraUnits) do
		if not wanted[key] then
			E:UnregisterUnitEvent("UNIT_AURA", pair, M)
			auraUnits[key] = nil
		end
	end
	for key, pair in pairs(wanted) do
		if not auraUnits[key] and E:RegisterUnitEvent("UNIT_AURA", pair, OnAura, M) then auraUnits[key] = pair end
	end
end

-- The units the report listens to for aura changes, for the checks.
function M:AuraUnits()
	local list = {}
	for _, pair in pairs(auraUnits) do
		for _, unit in ipairs(pair) do list[#list + 1] = unit end
	end
	table.sort(list)
	return list
end

function M:OnEnable()
	self:BuildWindow()
	self:RegisterEvent("READY_CHECK", function() M:OnReadyCheck() end)
	self:RegisterEvent("READY_CHECK_CONFIRM", function(_, _, unit, ready) M:OnReadyCheckConfirm(unit, ready) end)
	self:RegisterEvent("READY_CHECK_FINISHED", function(_, _, preempted) M:OnReadyCheckFinished(preempted) end)
	self:RegisterEvent("START_PLAYER_COUNTDOWN", function(_, _, _, timeRemaining) M:OnPullCountdown(timeRemaining) end)
	self:RegisterEvent("CANCEL_PLAYER_COUNTDOWN", function() M:ClearPullCountdown() end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() M:ClearPullCountdown() end)
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function() M:ClearPullCountdown() end)
	self:RegisterEvent("GROUP_ROSTER_UPDATE", function()
		M:SyncAuraUnits()
		M:QueueRefresh()
	end)
	self:SyncAuraUnits()
	self:RegisterEvent("UPDATE_INVENTORY_DURABILITY", function() M:QueueRefresh() end)
	E:RegisterComm(PREFIX, function(payload, sender) M:OnShare(payload, sender) end, { trusted = "group" })
end

function M:OnDisable()
	E:UnregisterComm(PREFIX)
	self:SyncAuraUnits()
	self.checking = false
	self.answerRows = nil
	self.closeToken = nil
	self:ClearPullCountdown()
	self:Close()
end

function M:OnProfileChanged()
	if self.active then self:ApplyLook() end
end

E:AddCommand("readycheck", "[post]  open the ready check report, or post its summary to the group", function(arg)
	if not M.active then
		E:Print(E:ModuleOffHint("ReadyReport"))
		return
	end
	M:Command(arg)
end, "Tools")

E:RegisterDiagnostics("ReadyReport", function()
	if not M.initialized then return {} end
	local rows = M.rows or {}
	return { ("   Ready Check Report: %s, %d rows, sharing %s, %d shared lines"):format( -- no-L
		M.active and "on" or "off", #rows, M.db.share and "on" or "off", (function() local n = 0 for _ in pairs(M.shared) do n = n + 1 end return n end)()) }
end)
