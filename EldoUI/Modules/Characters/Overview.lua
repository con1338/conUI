-- EldoUI Characters: the Overview tab, column sets and filters,
-- the character tooltip and the Lockouts tab.
local _, E = ...
local L = E.L
local Key = E.Key
local Kit = E.UIKit
local M = E:GetModule("Characters")
if not M then return end

local function Store() return E.Characters end

---------------------------------------------------------------------------
-- Columns: every one the Overview can show. A style picks a set; the
-- Columns button adds or removes single ones.
---------------------------------------------------------------------------
-- The game lists professions as two primary, First Aid, Fishing, Cooking.
local PROF_SLOT = { prof1 = 1, prof2 = 2, firstAid = 3, fishing = 4, cooking = 5 }

local function Prof(record, slot)
	for name, entry in pairs(type(record.profs) == "table" and record.profs or {}) do
		if entry.slot == slot then return name, entry end
	end
end

local function ProfText(record, slot)
	local name, entry = Prof(record, slot)
	if not name then return "" end
	local text = ("%s %d"):format(name, entry.rank or 0)
	if slot >= PROF_SLOT.firstAid then text = tostring(entry.rank or 0) end
	return text
end

local function ReadyCooldowns(record)
	local now, ready, total = Store().Now(), 0, 0
	for _, cd in pairs(type(record.cooldowns) == "table" and record.cooldowns or {}) do
		total = total + 1
		if (cd.readyAt or 0) <= now then ready = ready + 1 end
	end
	return ready, total
end
M.ReadyCooldowns = ReadyCooldowns

local function XPPercent(record)
	if not record.xpMax or record.xpMax <= 0 or (record.level or 0) >= Store().MaxLevel() then return nil end
	return math.floor((record.xp or 0) / record.xpMax * 100)
end

local function Grey(text) return M.Grey(text) end

local MARKS = { general = Key("Bank"), prof = Key("Crafting bank") }

local function MarkText(key)
	local mark = M.db.bankMarks[key]
	if type(mark) ~= "string" then return "" end
	local prof = mark:match("^prof:(.+)$")
	if prof then return prof end
	return L[MARKS[mark] or mark]
end
M.MarkText = MarkText

-- Talent plans saved for the whole account (Talent Planner), by class.
function M.TalentPlans(class)
	if type(class) ~= "string" then return {} end
	local store = E:GetGlobal("talentPlans")
	local classes = type(store) == "table" and type(store.classes) == "table" and store.classes or nil
	local data = classes and classes[class]
	local plans = type(data) == "table" and type(data.plans) == "table" and data.plans or nil
	return plans or {}
end

-- Opens the Talent Planner on that class's plans (only while it is on).
function M.OpenTalentPlans(class)
	local T = E.Talents
	if not (T and T.active and type(T.OpenPlanner) == "function") then return false end
	if type(T.SetViewClass) == "function" then T:SetViewClass(class) end
	return T:OpenPlanner("plans") and true or false
end

M.COLUMNS = {
	{ key = "name", title = "Name", desc = "Character name in class color. Right-click for groups, bank marks and Forget.",
		value = function(r) return r.name or "" end,
		text = function(r, key) return M.ClassIcon(r.class, 14) .. M.ClassName(r) .. (key == E.charKey and Grey(" *") or "") end },
	{ key = "level", title = "Level", width = 44, align = "RIGHT", desc = "Character level.",
		value = function(r) return r.level or 0 end },
	{ key = "xp", title = "XP", width = 50, align = "RIGHT", desc = "Experience through the current level.",
		value = function(r) return XPPercent(r) or -1 end,
		text = function(r) local p = XPPercent(r) return p and (p .. "%") or "" end },
	{ key = "rested", title = "Rested", width = 62, align = "RIGHT",
		desc = "Rested XP as a share of a level: up to 150 %, more with the Legacy talent Well Rested. ~ marks an estimate for a character that is offline.",
		value = function(r) return M.RestedPercent(r) or -1 end,
		text = function(r)
			if (r.level or 0) >= Store().MaxLevel() then return "" end
			local pct, estimated = M.RestedPercent(r)
			if not pct then return "" end
			local text = (estimated and "~" or "") .. pct .. "%"
			if M.FullyRested(r) then return M.Good(text) end
			return text
		end },
	{ key = "fullRest", title = "Full in", width = 70, align = "RIGHT", desc = "Estimated time until the rested bar is full.",
		value = function(r) return Store():FullyRestedIn(r) or math.huge end,
		text = function(r) local s = Store():FullyRestedIn(r) if s == nil then return "" end return s == 0 and L["full"] or M.Duration(s) end },
	{ key = "gold", title = "Gold", width = 96, align = "RIGHT", desc = "Gold on the character the last time it was online.",
		value = function(r) return r.money or 0 end, text = function(r) return M.Money(r.money, true) end },
	{ key = "played", title = "Played", width = 74, align = "RIGHT", desc = "Total played time, as the game last reported it.",
		value = function(r) return Store():Played(r) or 0 end, text = function(r) return M.Duration(Store():Played(r)) end },
	{ key = "ilvl", title = "iLvl", width = 46, align = "RIGHT", desc = "Average item level of the gear the character owns.",
		value = function(r) return r.gear and r.gear.ilvl or 0 end,
		text = function(r) return r.gear and r.gear.ilvl and ("%.0f"):format(r.gear.ilvl) or "" end },
	{ key = "seen", title = "Seen", width = 56, align = "RIGHT", desc = "When the character was last online.",
		value = function(r, key) return key == E.charKey and math.huge or (r.loggedOut or r.seen or 0) end,
		text = function(r) return M.Ago(r) end },
	{ key = "zone", title = "Zone", width = 120, desc = "Where the character logged out.", value = function(r) return r.zone or "" end },
	{ key = "hearth", title = "Hearth", width = 110, desc = "Where the hearthstone is set.", value = function(r) return r.hearth or "" end },
	{ key = "guild", title = "Guild", width = 110, desc = "Guild and rank.", value = function(r) return r.guild and r.guild.name or "" end },
	{ key = "durability", title = "Dur.", width = 44, align = "RIGHT", desc = "Durability of the equipped gear (average).",
		value = function(r) return r.durability and r.durability.pct or 101 end,
		text = function(r)
			local pct = r.durability and r.durability.pct
			if not pct then return "" end
			if pct < 25 then return M.Bad(pct .. "%") end
			if pct < 50 then return M.Warn(pct .. "%") end
			return pct .. "%"
		end },
	{ key = "lockouts", title = "Locks", width = 46, align = "RIGHT", desc = "Saved instances that have not reset yet.",
		value = function(r) return M.LockoutCount(r) end, text = function(r) local n = M.LockoutCount(r) return n > 0 and tostring(n) or "" end },
	{ key = "bagsFree", title = "Bags", width = 48, align = "RIGHT", desc = "Free bag slots.",
		value = function(r) return r.slots and r.slots.bagsFree or -1 end,
		text = function(r) return r.slots and r.slots.bagsFree and tostring(r.slots.bagsFree) or "" end },
	{ key = "bankFree", title = "Bank", width = 48, align = "RIGHT", desc = "Free bank slots, from the last bank visit.",
		value = function(r) return r.slots and r.slots.bankFree or -1 end,
		text = function(r) return r.slots and r.slots.bankFree and tostring(r.slots.bankFree) or "" end },
	{ key = "mail", title = "Mail", width = 48, align = "RIGHT", desc = "Items waiting in the mailbox; red when a mail returns or is deleted within 5 days.",
		value = function(r) return (M.MailInfo(r)) end,
		text = function(r)
			local items, soon = M.MailInfo(r, 5)
			if items == 0 and soon == 0 then return "" end
			return soon > 0 and M.Bad(items) or tostring(items)
		end },
	{ key = "auctions", title = "AH", width = 44, align = "RIGHT", desc = "Running auctions, from the last auction house visit.",
		value = function(r) return r.auctions and r.auctions.list and #r.auctions.list or 0 end,
		text = function(r) local n = r.auctions and r.auctions.list and #r.auctions.list or 0 return n > 0 and tostring(n) or "" end },
	{ key = "prof1", title = "Profession", width = 110, desc = "First profession and its skill.",
		value = function(r) return ProfText(r, 1) end, text = function(r) return ProfText(r, 1) end },
	{ key = "prof2", title = "Profession", width = 110, desc = "Second profession and its skill.",
		value = function(r) return ProfText(r, 2) end, text = function(r) return ProfText(r, 2) end },
	{ key = "cooking", title = "Cook", width = 44, align = "RIGHT", desc = "Cooking skill.", value = function(r) return ProfText(r, PROF_SLOT.cooking) end },
	{ key = "firstAid", title = "Aid", width = 44, align = "RIGHT", desc = "First Aid skill.", value = function(r) return ProfText(r, PROF_SLOT.firstAid) end },
	{ key = "fishing", title = "Fish", width = 44, align = "RIGHT", desc = "Fishing skill.", value = function(r) return ProfText(r, PROF_SLOT.fishing) end },
	{ key = "cooldowns", title = "CDs", width = 48, align = "RIGHT", desc = "Profession cooldowns ready now, of those recorded.",
		value = function(r) return (ReadyCooldowns(r)) end,
		text = function(r) local ready, total = ReadyCooldowns(r) if total == 0 then return "" end return ("%d/%d"):format(ready, total) end },
	{ key = "mark", title = "Mark", width = 80, desc = "Bank mark you gave the character (right-click a name).",
		value = function(_, key) return MarkText(key) end },
	{ key = "race", title = "Race", width = 80, desc = "Race.", value = function(r) return r.race or "" end },
	{ key = "plans", title = "Plans", width = 46, align = "RIGHT",
		desc = "Talent plans saved on the account for the character's class. Hover a row for their names; right-click a name to open them in the Talent Planner.",
		value = function(r) return #M.TalentPlans(r.class) end,
		text = function(r) local n = #M.TalentPlans(r.class) return n > 0 and tostring(n) or "" end },
}
M.COLUMN_BY_KEY = {}
for _, column in ipairs(M.COLUMNS) do M.COLUMN_BY_KEY[column.key] = column end

-- Style presets: column sets and the tab the window opens on.
E:RegisterStyles("Characters", {
	{ key = "Overview", title = "Overview", desc = "Name, level, rested, gold, played, item level and last seen. Opens on the Overview.",
		settings = { columns = { "name", "level", "rested", "gold", "played", "ilvl", "seen" }, rowHeight = 18, chips = true, openTab = "overview" } },
	{ key = "Compact", title = "Compact", desc = "Name, level and gold in small rows, without filter chips.",
		settings = { columns = { "name", "level", "gold", "seen" }, rowHeight = 16, chips = false, openTab = "overview" } },
	{ key = "Leveling", title = "Leveling", desc = "XP, rested (with estimates), time to a full rested bar, zone, hearth and the talent plans saved for each class.",
		settings = { columns = { "name", "level", "xp", "rested", "fullRest", "zone", "hearth", "plans" }, rowHeight = 18, chips = true, restedEstimate = true, openTab = "overview" } },
	{ key = "MaxLevel", title = "Max level", desc = "Item level, durability, lockouts and gold. Opens on the Lockouts tab.",
		settings = { columns = { "name", "level", "ilvl", "durability", "lockouts", "gold", "seen" }, rowHeight = 18, chips = true, openTab = "lockouts" } },
	{ key = "Crafter", title = "Crafter", desc = "Both professions, cooking, first aid, fishing and cooldowns.",
		settings = { columns = { "name", "prof1", "prof2", "cooking", "firstAid", "fishing", "cooldowns" }, rowHeight = 18, chips = true, openTab = "overview" } },
	{ key = "Banker", title = "Banker", desc = "Free bag and bank slots, mail, auctions, bank marks and gold.",
		settings = { columns = { "name", "bagsFree", "bankFree", "mail", "auctions", "mark", "gold" }, rowHeight = 18, chips = true, openTab = "overview" } },
	{ key = "Full", title = "Full", desc = "As many columns as fit: level, XP, rested, gold, played, item level, durability, lockouts, bags, mail, professions and last seen.",
		settings = { columns = { "name", "level", "xp", "rested", "gold", "played", "ilvl", "durability", "lockouts", "bagsFree", "mail", "prof1", "prof2", "seen" }, rowHeight = 18, chips = true, openTab = "overview" } },
})

-- The columns of the active set, widths fitted to the space there is.
local function ActiveColumns(width)
	local list, fixed = {}, 0
	local seen = {}
	for _, key in ipairs(M.db.columns) do
		local column = M.COLUMN_BY_KEY[key]
		if column and not seen[key] then
			seen[key] = true
			list[#list + 1] = column
			fixed = fixed + (column.width or 0)
		end
	end
	if not seen.name then
		table.insert(list, 1, M.COLUMN_BY_KEY.name)
	end
	local room = (width or 790) - 140
	local factor = fixed > room and room / fixed or 1
	local columns = {}
	for _, column in ipairs(list) do
		local copy = {}
		for k, v in pairs(column) do copy[k] = v end
		copy.title = L[column.title]
		copy.desc = L[column.desc]
		if copy.width then copy.width = math.max(math.floor(copy.width * factor), 34) end
		local value, text = column.value, column.text
		copy.value = function(item) return value(item.record, item.key) end
		copy.text = function(item)
			if text then return text(item.record, item.key) end
			local v = value(item.record, item.key)
			return v ~= nil and tostring(v) or ""
		end
		columns[#columns + 1] = copy
	end
	return columns
end

---------------------------------------------------------------------------
-- The character tooltip: rows, the datatext and other tabs use it.
---------------------------------------------------------------------------
-- The class reagents of the 1.x game, by item ID (editable: Characters
-- page, "More reagents").
local REAGENTS = {
	MAGE = { 17020, 17031, 17032, 17056 },
	PRIEST = { 17028, 17029, 17056 },
	PALADIN = { 21177, 17033 },
	DRUID = { 17021, 17026, 17034, 17035, 17036, 17037, 17038 },
	ROGUE = { 5140, 5530, 2928, 8924 },
	SHAMAN = { 17030, 17057, 17058 },
	WARLOCK = { 6265, 5565, 16583 },
}
M.REAGENTS = REAGENTS

local function ItemCount(record, id)
	local entry = record.counts and record.counts[id]
	if not entry then return 0 end
	return (entry[1] or 0) + (entry[2] or 0) + (entry[3] or 0) + (entry[4] or 0)
end

function M:ReagentLines(record)
	local ids = {}
	for _, id in ipairs(REAGENTS[record.class or ""] or {}) do ids[#ids + 1] = id end
	for id in tostring(self.db.reagentsExtra or ""):gmatch("%d+") do ids[#ids + 1] = tonumber(id) end
	local lines = {}
	for _, id in ipairs(ids) do
		local count = ItemCount(record, id)
		if count > 0 then
			local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
			if not name and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
			lines[#lines + 1] = { name or L["item %d"]:format(id), count }
		end
	end
	return lines
end

local function Header(tooltip, text)
	tooltip:AddLine(" ")
	tooltip:AddLine(text, Kit.Accent())
end

function M:CharacterTooltip(tooltip, key)
	local record = Store():Get(key)
	if not record then return end
	local S = Kit.SECONDARY
	tooltip:AddLine(M.ClassIcon(record.class, 16) .. M.ClassName(record, true))
	local race = record.race and (record.race .. " ") or ""
	tooltip:AddLine(L["Level %d %s"]:format(record.level or 0, race .. (record.class and (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[record.class] or record.class) or "")), S[1], S[2], S[3])
	if record.guild and record.guild.name then
		tooltip:AddLine(("<%s> %s"):format(record.guild.name, record.guild.rank or ""), S[1], S[2], S[3])
	end
	tooltip:AddDoubleLine(L["Last seen"], M.Ago(record), S[1], S[2], S[3], 1, 1, 1)
	if record.zone then tooltip:AddDoubleLine(L["Zone"], record.zone, S[1], S[2], S[3], 1, 1, 1) end
	if record.hearth then tooltip:AddDoubleLine(L["Hearthstone"], record.hearth, S[1], S[2], S[3], 1, 1, 1) end
	tooltip:AddDoubleLine(L["Gold"], M.Money(record.money), S[1], S[2], S[3], 1, 1, 1)
	local played = Store():Played(record)
	if played then tooltip:AddDoubleLine(L["Played"], M.Duration(played), S[1], S[2], S[3], 1, 1, 1) end
	local xp = XPPercent(record)
	if xp then
		tooltip:AddDoubleLine(L["XP"], ("%d%%  (%s / %s)"):format(xp, BreakUpLargeNumbers(record.xp or 0), BreakUpLargeNumbers(record.xpMax or 0)), S[1], S[2], S[3], 1, 1, 1)
		local pct, estimated = M.RestedPercent(record)
		if pct then
			local bubbles = math.floor(pct / 5)
			tooltip:AddDoubleLine(L["Rested"], (estimated and "~" or "") .. L["%d%% (%d bubbles)"]:format(pct, bubbles) .. (estimated and (" " .. L["estimated"]) or ""), S[1], S[2], S[3], 0.4, 0.7, 1)
		end
	end
	if record.durability and record.durability.pct then
		tooltip:AddDoubleLine(L["Durability"], record.durability.pct .. "%", S[1], S[2], S[3], 1, 1, 1)
	end
	if record.slots and record.slots.bags then
		tooltip:AddDoubleLine(L["Bag slots free"], ("%d / %d"):format(record.slots.bagsFree or 0, record.slots.bags or 0), S[1], S[2], S[3], 1, 1, 1)
	end
	-- Professions and cooldowns.
	local profs = {}
	for name, entry in pairs(type(record.profs) == "table" and record.profs or {}) do profs[#profs + 1] = { name = name, entry = entry } end
	table.sort(profs, function(a, b) return (a.entry.slot or 9) < (b.entry.slot or 9) end)
	if #profs > 0 then
		Header(tooltip, L["Professions"])
		for _, prof in ipairs(profs) do
			tooltip:AddDoubleLine(prof.name, ("%d / %d"):format(prof.entry.rank or 0, prof.entry.max or 0), 1, 1, 1, 1, 1, 1)
		end
		local now = Store().Now()
		for _, cd in pairs(type(record.cooldowns) == "table" and record.cooldowns or {}) do
			local left = (cd.readyAt or 0) - now
			tooltip:AddDoubleLine("  " .. (cd.name or "?"), left <= 0 and M.Good(L["Ready"]) or M.Duration(left), S[1], S[2], S[3], 1, 1, 1)
		end
	end
	-- Reagents, ammo and pet.
	local reagents = self:ReagentLines(record)
	if #reagents > 0 then
		Header(tooltip, L["Reagents"])
		for _, line in ipairs(reagents) do tooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 1, 1, 1) end
	end
	if record.class == "HUNTER" and (record.ammo or record.pet) then
		Header(tooltip, L["Hunter"])
		if record.ammo then tooltip:AddDoubleLine(L["Ammo"], record.ammo, 1, 1, 1, 1, 1, 1) end
		if record.pet and record.pet.name then
			tooltip:AddDoubleLine(L["Pet"], ("%s (%s %s)"):format(record.pet.name, record.pet.family or "", record.pet.level or ""), 1, 1, 1, 1, 1, 1)
		end
	end
	-- Lockouts with time to reset.
	local locks = {}
	local now = Store().Now()
	for _, lock in pairs(type(record.lockouts) == "table" and record.lockouts or {}) do
		if (lock.resetAt or 0) > now then locks[#locks + 1] = lock end
	end
	table.sort(locks, function(a, b) return a.resetAt < b.resetAt end)
	if #locks > 0 then
		Header(tooltip, L["Saved instances"])
		for _, lock in ipairs(locks) do
			local progress = lock.total and lock.total > 0 and (" " .. Grey(("%d/%d"):format(lock.done or 0, lock.total))) or ""
			tooltip:AddDoubleLine(lock.name .. progress, M.Duration(lock.resetAt - now), 1, 1, 1, 1, 1, 1)
		end
	end
	-- Talent plans for the class, saved on the account.
	local plans = M.TalentPlans(record.class)
	if #plans > 0 then
		Header(tooltip, E:Plural(#plans, "%d talent plan", "%d talent plans"):format(#plans))
		for index = 1, math.min(#plans, 5) do
			local plan = plans[index]
			Kit.TipTitle(tooltip, type(plan) == "table" and type(plan.name) == "string" and plan.name or L["Talent plan"])
		end
		if #plans > 5 then tooltip:AddLine(E:Plural(#plans - 5, "%d more plan", "%d more plans"):format(#plans - 5), S[1], S[2], S[3]) end
	end
	local items, soon = M.MailInfo(record, 5)
	if soon > 0 then
		tooltip:AddLine(" ")
		tooltip:AddLine(L["%d mails return or are deleted within 5 days."]:format(soon), E:TokenColor("bad"))
	elseif items > 0 then
		tooltip:AddLine(" ")
		tooltip:AddLine(E:Plural(items, "%d item in the mailbox.", "%d items in the mailbox."):format(items), S[1], S[2], S[3])
	end
end

---------------------------------------------------------------------------
-- Filters
---------------------------------------------------------------------------
local CHIPS = {
	{ "Alliance", FACTION_ALLIANCE or Key("Alliance"), Key("Only Alliance characters.") },
	{ "Horde", FACTION_HORDE or Key("Horde"), Key("Only Horde characters.") },
	{ "max", Key("Max level"), Key("Only characters at the highest level.") },
	{ "leveling", Key("Leveling"), Key("Only characters below the highest level.") },
	{ "rested", Key("Fully rested"), Key("Only characters whose rested bar is full (estimate for offline characters).") },
	{ "mail", Key("Mail"), Key("Only characters with items in the mailbox.") },
	{ "expiring", Key("Mail expiring"), Key("Only characters with mail that returns or is deleted within 5 days.") },
	{ "locked", Key("Lockouts"), Key("Only characters saved to an instance.") },
}

local function Passes(record, selected)
	if selected.Alliance or selected.Horde then
		if not selected[record.faction or ""] then return false end
	end
	local max = (record.level or 0) >= Store().MaxLevel()
	if selected.max and not max then return false end
	if selected.leveling and max then return false end
	if selected.rested then
		if max or not M.FullyRested(record) then return false end
	end
	local items, soon = M.MailInfo(record, 5)
	if selected.mail and items == 0 then return false end
	if selected.expiring and soon == 0 then return false end
	if selected.locked and M.LockoutCount(record) == 0 then return false end
	return true
end

-- The Filter menu's picks: class, profession, bank mark (key needed).
local function PassesMore(record, more, key)
	if not more then return true end
	if more.class and record.class ~= more.class then return false end
	if more.prof and not (type(record.profs) == "table" and record.profs[more.prof]) then return false end
	if more.mark and M.db.bankMarks[key] ~= more.mark then return false end
	return true
end

M.FilterPasses = function(record, selected, more, key)
	return Passes(record, selected) and PassesMore(record, more, key)
end

---------------------------------------------------------------------------
-- Groups and bank marks in the row menu
---------------------------------------------------------------------------
local function AddGroup(key, text)
	local name = strtrim(text or "")
	if name ~= "" then
		M.db.groups[name] = M.db.groups[name] or {}
		if key then M.db.groups[name][key] = true end
		M:Refresh()
	end
end

-- Talent plans of the character's class: opens the Talent Planner there.
M:AddMenuEntry(function(root, _, record)
	local count = #M.TalentPlans(record.class)
	local T = E.Talents
	if count == 0 or not (T and T.active) then return end
	root:CreateButton(E:Plural(count, "Talent plan (%d)", "Talent plans (%d)"):format(count), function() M.OpenTalentPlans(record.class) end)
end)

M:AddMenuEntry(function(root, key, record)
	local groups = root:CreateButton(L["Groups"])
	local names = {}
	for name in pairs(M.db.groups) do names[#names + 1] = name end
	table.sort(names)
	for _, name in ipairs(names) do
		groups:CreateCheckbox(name, function() return M.db.groups[name] and M.db.groups[name][key] end, function()
			local members = M.db.groups[name]
			members[key] = not members[key] or nil
			M:Refresh()
		end)
	end
	groups:CreateButton(L["New group..."], function()
		E:ShowConfirm({ key = "ELDOUI_ALTS_NEW_GROUP", title = L["Alts"], text = L["Name of the new group:"],
			accept = E:GameText(OKAY, L["OK"]), edit = { maxLetters = 32 }, data = key, onAccept = AddGroup })
	end)
	local marks = root:CreateButton(L["Bank mark"])
	marks:CreateRadio(L["None"], function() return M.db.bankMarks[key] == nil end, function() M.db.bankMarks[key] = nil M:Refresh() end)
	marks:CreateRadio(L["Bank"], function() return M.db.bankMarks[key] == "general" end, function() M.db.bankMarks[key] = "general" M:Refresh() end)
	for name in pairs(type(record.profs) == "table" and record.profs or {}) do
		local value = "prof:" .. name
		marks:CreateRadio(L["Crafting bank: %s"]:format(name), function() return M.db.bankMarks[key] == value end, function()
			M.db.bankMarks[key] = value
			M:Refresh()
		end)
	end
end)

---------------------------------------------------------------------------
-- "Could be stored on": bank marks in item tooltips. Trade goods
-- and recipes go to the crafting bank of their profession, everything
-- else to characters marked as a bank.
---------------------------------------------------------------------------
-- Trade goods subclass -> recipe subclasses (the professions using it).
local TRADE_PROFESSIONS = {
	[1] = { 3 }, [2] = { 3 }, [3] = { 3 }, [4] = { 10 }, [5] = { 2 }, [6] = { 1 },
	[7] = { 4, 3 }, [8] = { 5 }, [9] = { 6 }, [10] = { 6, 4, 1, 2 }, [12] = { 8 },
}

local function ProfessionsOf(item)
	local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(item)
	local names = {}
	local ItemClass = Enum.ItemClass or {}
	local recipeClass = ItemClass.Recipe or 9
	if classID == recipeClass then
		local name = C_Item.GetItemSubClassInfo and C_Item.GetItemSubClassInfo(recipeClass, subclassID)
		if name then names[name] = true end
	elseif classID == (ItemClass.Tradegoods or 7) then
		for _, recipeSub in ipairs(TRADE_PROFESSIONS[subclassID] or {}) do
			local name = C_Item.GetItemSubClassInfo and C_Item.GetItemSubClassInfo(recipeClass, recipeSub)
			if name then names[name] = true end
		end
	end
	return names, classID ~= nil
end

-- Characters (this realm) whose bank mark fits the item.
function M:StorageKeys(item)
	if item == nil then return {} end
	local profs, valid = ProfessionsOf(item)
	if not valid then return {} end
	local crafting, general = {}, {}
	for _, key in ipairs(Store():Keys("realm")) do
		local mark = self.db.bankMarks[key]
		if type(mark) == "string" then
			local prof = mark:match("^prof:(.+)$")
			if prof and profs[prof] then
				crafting[#crafting + 1] = key
			elseif mark == "general" then
				general[#general + 1] = key
			end
		end
	end
	return #crafting > 0 and crafting or general
end

local function HookStorageTooltip()
	if M.storageHooked or not E.RegisterTooltipSection then return end
	M.storageHooked = true
	E:RegisterTooltipSection("altStorage", { order = 43, title = "Alts: could be stored on", default = "never",
		desc = "Names the characters you marked as a bank (right-click a character in the Alts window) that suit the item: the crafting bank of its profession, else your general bank.",
		item = function(_, link, itemID, add)
			if not M.active then return end
			local keys = M:StorageKeys(link or itemID)
			if #keys == 0 then return end
			local parts = {}
			for _, key in ipairs(keys) do parts[#parts + 1] = M.ClassName(Store():Get(key)) end
			add(L["Could be stored on"], table.concat(parts, ", "))
		end })
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
local function Items(keys)
	local list = {}
	for _, key in ipairs(keys) do
		local record = Store():Get(key)
		if record then list[#list + 1] = { key = key, record = record } end
	end
	return list
end

local function BuildTable(frame)
	if frame.tbl then frame.tbl:Hide() end
	frame.columnSet = table.concat(M.db.columns, ",") .. ":" .. M.db.rowHeight
	local width = frame:GetWidth()
	if not width or width < 100 then width = 804 end
	local saved = frame.sort or {}
	frame.tbl = Kit.CreateTable(frame, ActiveColumns(width), {
		rowHeight = M.db.rowHeight,
		sortKey = saved.key or "name", sortDown = saved.down,
		onSort = function(key, down) frame.sort = { key = key, down = down } end,
		onClick = function(item, button, row)
			if button == "RightButton" then
				M:ShowCharacterMenu(row, item.key)
			elseif M.window and M.window:GetTab("character") then
				M:Open("character", item.key)
			end
		end,
		createRow = function(row)
			row:HookScript("OnEnter", function(own)
				if not own.item then return end
				GameTooltip:SetOwner(own, "ANCHOR_RIGHT")
				M:CharacterTooltip(GameTooltip, own.item.key)
				GameTooltip:Show()
			end)
			row:HookScript("OnLeave", function() GameTooltip:Hide() end)
		end,
		empty = { L["No characters"], L["No character matches the filters."] },
	})
	frame.tbl:SetPoint("TOPLEFT", frame.chips:IsShown() and frame.chips or frame.toolbar, "BOTTOMLEFT", 0, -6)
	frame.tbl:SetPoint("BOTTOMRIGHT")
end

local function Update(frame)
	frame.chips:SetShown(M.db.chips)
	if frame.columnSet ~= table.concat(M.db.columns, ",") .. ":" .. M.db.rowHeight then BuildTable(frame) end
	frame.tbl:ClearAllPoints()
	frame.tbl:SetPoint("TOPLEFT", M.db.chips and frame.chips or frame.toolbar, "BOTTOMLEFT", 0, -6)
	frame.tbl:SetPoint("BOTTOMRIGHT")
	local selected = M.db.chips and frame.chips:GetSelected() or {}
	local list = {}
	frame.more = frame.more or {}
	for _, item in ipairs(Items(M:Keys())) do
		if Passes(item.record, selected) and PassesMore(item.record, frame.more, item.key) then list[#list + 1] = item end
	end
	frame.items = list
	frame.tbl:SetData(list)
	frame.count:SetText(E:Plural(#list, "%d character", "%d characters"):format(#list))
	local picks = 0
	for _ in pairs(frame.more) do picks = picks + 1 end
	frame.filterButton:SetText(picks > 0 and L["Filter (%d)"]:format(picks) or L["Filter"])
end
M.UpdateOverview = Update

-- Class, profession and bank-mark filters (session only).
function M:ShowFilterMenu(anchor, frame)
	frame.more = frame.more or {}
	local classes, profs = {}, {}
	for _, key in ipairs(M:Keys()) do
		local record = Store():Get(key)
		if record.class then classes[record.class] = true end
		for name in pairs(type(record.profs) == "table" and record.profs or {}) do profs[name] = true end
	end
	local function Section(root, title, field, values, label)
		local sub = root:CreateButton(title)
		sub:CreateRadio(L["Any"], function() return frame.more[field] == nil end, function() frame.more[field] = nil Update(frame) end)
		local list = {}
		for value in pairs(values) do list[#list + 1] = value end
		table.sort(list)
		for _, value in ipairs(list) do
			sub:CreateRadio(label and label(value) or value, function() return frame.more[field] == value end, function()
				frame.more[field] = value
				Update(frame)
			end)
		end
	end
	E.UIKit.ContextMenu(anchor, function(_, root)
		root:CreateTitle(L["Filter"])
		Section(root, L["Class"], "class", classes, function(class)
			return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
		end)
		Section(root, L["Profession"], "prof", profs)
		local marks = { general = true }
		for _, mark in pairs(M.db.bankMarks) do marks[mark] = true end
		Section(root, L["Bank mark"], "mark", marks, function(mark)
			return mark == "general" and L["Bank"] or L["Crafting bank: %s"]:format(mark:match("^prof:(.+)$") or mark)
		end)
		root:CreateDivider()
		root:CreateButton(L["Clear filters"], function()
			wipe(frame.more)
			Update(frame)
		end)
	end, { at = "owner" })
end

function M:ShowColumnMenu(anchor)
	E.UIKit.ContextMenu(anchor, function(_, root)
		root:CreateTitle(L["Columns"])
		for _, column in ipairs(M.COLUMNS) do
			if column.key ~= "name" then
				root:CreateCheckbox(L[column.title] .. (column.key == "prof2" and " 2" or ""), function()
					return tContains(M.db.columns, column.key)
				end, function()
					local list = {}
					local found = false
					for _, key in ipairs(M.db.columns) do
						if key == column.key then found = true else list[#list + 1] = key end
					end
					if not found then list[#list + 1] = column.key end
					M.db.columns = list
					M:Refresh()
				end)
			end
		end
	end, { at = "owner" })
end

M:AddTab({
	key = "overview", order = 10, title = "Overview",
	desc = "One row per character: sort by any column, filter with the chips, hover for details, right-click for groups, bank marks and Forget.",
	create = function(content)
		local frame = CreateFrame("Frame", nil, content)
		frame:SetAllPoints()
		frame.toolbar = CreateFrame("Frame", nil, frame)
		frame.toolbar:SetPoint("TOPLEFT")
		frame.toolbar:SetPoint("TOPRIGHT")
		frame.toolbar:SetHeight(22)
		frame.count = Kit.Text(frame.toolbar, 12, "LEFT", "secondary")
		frame.count:SetPoint("LEFT", 2, 0)
		frame.columnsButton = Kit.Button(frame.toolbar, L["Columns"], 90, 20, function(button) M:ShowColumnMenu(button) end,
			L["Columns"], L["Add or remove columns. The styles on the Alts page set a good mix."])
		frame.columnsButton:SetPoint("RIGHT")
		frame.filterButton = Kit.Button(frame.toolbar, L["Filter"], 90, 20, function(button) M:ShowFilterMenu(button, frame) end,
			L["Filter"], L["Show only one class, characters with one profession, or characters with one bank mark."])
		frame.filterButton:SetPoint("RIGHT", frame.columnsButton, "LEFT", -6, 0)
		frame.chips = Kit.ChipBar(frame, {
			multi = true,
			chips = (function()
				local list = {}
				for _, chip in ipairs(CHIPS) do list[#list + 1] = { chip[1], L[chip[2]], L[chip[3]] } end
				return list
			end)(),
			onChange = function() Update(frame) end,
		})
		frame.chips:SetPoint("TOPLEFT", frame.toolbar, "BOTTOMLEFT", 0, -4)
		BuildTable(frame)
		return frame
	end,
	show = function(frame) Update(frame) end,
	refresh = function(frame) Update(frame) end,
	restyle = function(frame) frame.columnSet = nil end,
	enable = function() HookStorageTooltip() end,
	empty = function()
		local keys = M:Keys("account", "")
		if #keys <= 1 then
			return L["Only this character so far"], L["Log in on your other characters once; each one records itself and shows up here."], E.media.icon
		end
	end,
})

---------------------------------------------------------------------------
-- Lockouts tab: every character's saved instances.
---------------------------------------------------------------------------
local function LockoutItems()
	local list = {}
	local now = Store().Now()
	for _, key in ipairs(M:Keys()) do
		local record = Store():Get(key)
		for _, lock in pairs(type(record.lockouts) == "table" and record.lockouts or {}) do
			if (lock.resetAt or 0) > now then list[#list + 1] = { key = key, record = record, lock = lock } end
		end
	end
	return list
end
M.LockoutItems = LockoutItems

M:AddTab({
	key = "lockouts", order = 60, title = "Lockouts",
	desc = "Every character's saved instances with boss progress and the time to reset.",
	count = function() return #LockoutItems() end,
	create = function(content)
		local frame = CreateFrame("Frame", nil, content)
		frame:SetAllPoints()
		frame.tbl = Kit.CreateTable(frame, {
			{ key = "name", title = L["Character"], width = 180, value = function(item) return item.record.name or "" end,
				text = function(item) return M.ClassIcon(item.record.class, 14) .. M.ClassName(item.record) end },
			{ key = "instance", title = L["Instance"], value = function(item) return item.lock.name or "" end,
				text = function(item) return item.lock.name .. (item.lock.difficulty and Grey(" " .. item.lock.difficulty) or "") end },
			{ key = "progress", title = L["Bosses"], width = 80, align = "RIGHT", value = function(item) return item.lock.done or 0 end,
				text = function(item) return item.lock.total and item.lock.total > 0 and ("%d/%d"):format(item.lock.done or 0, item.lock.total) or "" end },
			{ key = "reset", title = L["Resets in"], width = 110, align = "RIGHT", value = function(item) return item.lock.resetAt end,
				text = function(item) return M.Duration(item.lock.resetAt - Store().Now()) .. (item.lock.extended and Grey(" +") or "") end },
		}, { sortKey = "reset", rowHeight = 18,
			onClick = function(item, button, row) if button == "RightButton" then M:ShowCharacterMenu(row, item.key) end end,
			empty = { L["No lockouts"], L["None of your characters is saved to an instance right now. Lockouts show here after each character logs in (or opens the raid info)."] } })
		frame.tbl:SetAllPoints()
		return frame
	end,
	show = function(frame) frame.tbl:SetData(LockoutItems()) end,
	refresh = function(frame) frame.tbl:SetData(LockoutItems()) end,
})
