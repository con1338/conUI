-- EldoUI Shaman Totems: the group plan, the Ready Check Report columns
-- and the shaman group panel.
--
--   Group plan   who drops Mana Tide and which shaman covers fire, frost
--                and nature resistance. Set on the Group tab of the
--                options and sent to the group with one click (out of
--                combat). A shaman with EldoUI who gets a plan sees their
--                part on the Drop All tooltip and in one chat line.
--   Shaman columns in the Ready Check Report: the totems each shaman
--                carries, their Ankh count, shield, weapon imbue and mana.
--                Yours is read out of combat from your bags, auras,
--                weapons and mana; another shaman's comes only when they
--                click Share mine on their report.
--   Shaman group panel: every shaman of the group in one window, with
--                Mana Tide Totem and Reincarnation, their Ankhs and their
--                part of the plan. Your own cooldowns come from the game;
--                another shaman's show only after they click Share mine
--                on their panel, counting down from what they sent.
-- Messages are sent only on the player's click, never in combat, and say
-- "could not send" when the game refuses. Nothing is answered on its own.
-- Written from scratch for EldoUI.
-- The spell IDs here are checked against the WoW: Forever client tables of
-- build 1.60.1.70938.
local _, E = ...
local L = E.L
local M = E:GetModule("ShamanTotems")
local D = E.ShamanData
local Try = M.Try
local Plain = E.Plain
local Secret = E.Secret

local PREFIX = "EUI_TOT"
local FORMAT = "1"
M.PLAN_PREFIX = PREFIX

-- The plan's jobs, in order. key = what the payload and settings call it.
M.JOBS = {
	{ key = "manatide", title = "Mana Tide Totem", spell = 16190 },
	{ key = "FIRE", title = "Fire resistance", spell = 8184 },
	{ key = "FROST", title = "Frost resistance", spell = 8181 },
	{ key = "NATURE", title = "Nature resistance", spell = 10595 },
}
-- L["Mana Tide Totem"], L["Fire resistance"], L["Frost resistance"], L["Nature resistance"]

local function ShortName(name)
	if type(name) ~= "string" or Secret(name) then return nil end
	local short = name:gsub("%-.*$", "")
	return short ~= "" and short or nil
end

-- The shamans in your group (names), you first.
function M:GroupShamans()
	local list, seen = {}, {}
	local function Add(unit)
		local _, class = Try(UnitClass, unit)
		if Secret(class) or class ~= "SHAMAN" then return end
		local name = ShortName(Plain(Try(UnitName, unit)))
		if name and not seen[name] then
			seen[name] = true
			list[#list + 1] = name
		end
	end
	Add("player")
	local raid = Plain(Try(IsInRaid))
	local count = Plain(Try(GetNumGroupMembers)) or 0
	if type(count) ~= "number" then count = 0 end
	for index = 1, math.min(count, 40) do
		Add(raid and ("raid" .. index) or ("party" .. index))
	end
	return list
end

---------------------------------------------------------------------------
-- The plan
---------------------------------------------------------------------------
function M:PlanPayload()
	local plan = self.db.plan
	local parts = { "P", FORMAT }
	for _, job in ipairs(self.JOBS) do
		local name = ShortName(plan[job.key]) or ""
		parts[#parts + 1] = name:gsub("[;=]", "")
	end
	return table.concat(parts, ";")
end

-- Send the plan to the group (the player's click). True when it went out.
function M:SendPlan()
	if InCombatLockdown() then
		E:Print(L["The group plan can be sent out of combat."])
		return false
	end
	if not Plain(Try(IsInGroup)) then
		E:Print(L["You are not in a group."])
		return false
	end
	local ok = (not E:CommRestricted()) and E:SendComm(PREFIX, self:PlanPayload(), "GROUP")
	if ok then
		E:Print(L["Totem plan sent to the group."])
		return true
	end
	E:Print(L["Could not send the totem plan: the game doesn't allow addon messages right now."])
	return false
end

-- Your part of a plan, as text lines (nil when none).
function M:MyJobs(plan)
	local me = ShortName(Plain(Try(UnitName, "player")))
	if not (me and type(plan) == "table") then return nil end
	local jobs = {}
	for _, job in ipairs(self.JOBS) do
		if plan[job.key] == me then jobs[#jobs + 1] = L[job.title] end
	end
	return #jobs > 0 and jobs or nil
end

function M:OnPlan(fields, sender)
	if not self:IsShaman() then return end
	local plan = { from = ShortName(sender) }
	for index, job in ipairs(self.JOBS) do
		local name = fields[index]
		plan[job.key] = (type(name) == "string" and name ~= "" and #name <= 24) and name or nil
	end
	self.received = plan
	local jobs = self:MyJobs(plan)
	if jobs then
		E:Print(L["Totem plan from %s: you have %s."]:format(plan.from or "?", table.concat(jobs, ", ")))
	end
end

---------------------------------------------------------------------------
-- The shaman column (Ready Check Report)
---------------------------------------------------------------------------
M.shared = {} -- short name -> { totems = { EARTH = bool, ... }, ankh = number }

local function ItemCount(id)
	local count = C_Item and C_Item.GetItemCount and Plain(Try(C_Item.GetItemCount, id))
	return type(count) == "number" and count or nil
end

-- The shield on you: its key, "" for none, nil when the game doesn't say
-- (in combat, or a secret answer).
function M:OwnShield()
	if InCombatLockdown() then return nil end
	local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
	if not get then return nil end
	for _, shield in ipairs(D.SHIELDS) do
		local ids = { shield.id }
		local best = self:Spell(shield.id).id
		if best ~= shield.id then ids[#ids + 1] = best end
		for _, id in ipairs(shield.auras or {}) do ids[#ids + 1] = id end
		for _, id in ipairs(ids) do
			local ok, aura = pcall(get, id)
			if not ok or Secret(aura) then return nil end
			if aura then return shield.key end
		end
	end
	return ""
end

-- A hand's imbue as the payload carries it: minutes left ("1" to "30"),
-- "n" for none, "" when the game doesn't say or the hand holds no weapon.
local function ImbueField(slot)
	local enchant = M.Cooldowns and M.Cooldowns.Enchant
	if not enchant then return "" end
	local has, left = enchant(slot)
	if has == nil then return "" end
	if not has then return "n" end
	if type(left) ~= "number" then return "1" end
	return tostring(math.max(1, math.min(30, math.ceil(left / 60))))
end

-- Your mana in percent (0 to 100), or nil when the game keeps it secret.
-- The game scales the value itself where it can (its 0-100 curve).
function M:OwnManaPercent()
	local power = Enum.PowerType and Enum.PowerType.Mana or 0
	if UnitPowerPercent then
		local curve = CurveConstants and CurveConstants.ScaleTo100
		local ok, value = pcall(UnitPowerPercent, "player", power, false, curve)
		value = ok and Plain(value)
		if type(value) == "number" then
			if not curve then value = value * 100 end
			return math.max(0, math.min(100, math.floor(value + 0.5)))
		end
		return nil
	end
	local current, most = Plain(Try(UnitPower, "player", power)), Plain(Try(UnitPowerMax, "player", power))
	if type(current) == "number" and type(most) == "number" and most > 0 then
		return math.max(0, math.min(100, math.floor(current / most * 100 + 0.5)))
	end
	return nil
end

-- What you carry and wear: { totems = { EARTH = true, ... }, ankh = n,
-- shield = key or "", main = imbue field, off = imbue field, mana = n }.
-- Shield and mana are read out of combat only.
function M:OwnKit()
	local kit = { totems = {} }
	for element, id in pairs(D.TOTEM_ITEMS) do
		local count = ItemCount(id)
		kit.totems[element] = count and count > 0 or false
	end
	local reincarnation = D.SPELLS[2]
	kit.ankh = self:Known(reincarnation.id) and ItemCount(reincarnation.item) or nil
	kit.shield = self:OwnShield()
	kit.main = ImbueField(INVSLOT_MAINHAND or 16)
	local cooldowns = self.Cooldowns
	kit.off = cooldowns and cooldowns.HasOffHandWeapon and cooldowns.HasOffHandWeapon() and ImbueField(INVSLOT_OFFHAND or 17) or ""
	kit.mana = not InCombatLockdown() and self:OwnManaPercent() or nil
	return kit
end

-- K;1;<totems>;<ankh>;<shield>;<main>;<off>;<mana>. The fields after the
-- Ankh count came later: older versions read the first two and skip the rest.
function M:KitPayload()
	local kit = self:OwnKit()
	local bits = {}
	for _, element in ipairs(D.ELEMENTS) do bits[#bits + 1] = kit.totems[element] and "1" or "0" end
	return ("K;%s;%s;%s;%s;%s;%s;%s"):format(FORMAT, table.concat(bits), kit.ankh and tostring(math.min(kit.ankh, 99)) or "",
		kit.shield or "?", kit.main or "", kit.off or "", kit.mana and tostring(kit.mana) or "")
end

local SHIELD_KEYS = {}
for _, shield in ipairs(D.SHIELDS) do SHIELD_KEYS[shield.key] = shield end

local function ImbueFrom(text)
	if text == "n" then return "n" end
	local minutes = type(text) == "string" and text:match("^(%d%d?)$")
	minutes = tonumber(minutes)
	if minutes and minutes >= 1 and minutes <= 30 then return tostring(minutes) end
	return ""
end

function M:OnKit(fields, sender)
	local bits, ankh = fields[1], fields[2]
	local name = ShortName(sender)
	if not (name and type(bits) == "string" and bits:match("^[01][01][01][01]$")) then return end
	local kit = { totems = {} }
	for index, element in ipairs(D.ELEMENTS) do kit.totems[element] = bits:sub(index, index) == "1" end
	kit.ankh = tonumber(ankh)
	-- Newer senders add shield, imbues and mana; anything else is dropped.
	local shield = fields[3]
	if shield == "" or SHIELD_KEYS[shield] then kit.shield = shield end
	kit.main, kit.off = ImbueFrom(fields[4]), ImbueFrom(fields[5])
	local mana = tonumber(type(fields[6]) == "string" and fields[6]:match("^(%d%d?%d?)$") or nil)
	kit.mana = mana and mana <= 100 and mana or nil
	self.shared[name] = kit
	local report = E.ReadyReport
	if report and report.QueueRefresh then report:QueueRefresh() end
end

local function KitText(kit)
	if not kit then return "" end
	local missing = {}
	for _, element in ipairs(D.ELEMENTS) do
		if kit.totems[element] == false then missing[#missing + 1] = L[M.ELEMENT_TITLES[element]] end
	end
	local text = #missing == 0 and L["All totems"] or L["No %s"]:format(table.concat(missing, ", "))
	if kit.ankh then text = text .. " · " .. L["Ankh %d"]:format(kit.ankh) end
	return text
end
M.KitText = KitText

local function ImbueText(field)
	if field == "n" then return L["none"] end
	if field and field ~= "" then return L["%dm"]:format(tonumber(field)) end
	return nil
end

-- "Lightning Shield · Imbue 25m / none"; "" when nothing is known.
local function GearText(kit)
	if not kit then return "" end
	local parts = {}
	local shield = kit.shield and SHIELD_KEYS[kit.shield]
	if shield then
		parts[#parts + 1] = M.SpellName(shield.id) or L["Shield"]
	elseif kit.shield == "" then
		parts[#parts + 1] = L["No shield"]
	end
	local main, off = ImbueText(kit.main), ImbueText(kit.off)
	if main and off then
		parts[#parts + 1] = L["Imbue %s / %s"]:format(main, off)
	elseif main then
		parts[#parts + 1] = kit.main == "n" and L["No imbue"] or L["Imbue %s"]:format(main)
	end
	return table.concat(parts, " · ")
end
M.GearText = GearText

local function ManaText(kit)
	return kit and kit.mana and ("%d%%"):format(kit.mana) or ""
end
M.ManaText = ManaText

function M:KitOf(row)
	if not (row and row.class == "SHAMAN") then return nil end
	if row.unit and Plain(Try(UnitIsUnit, row.unit, "player")) then return self:OwnKit() end
	return self.shared[ShortName(row.name) or ""]
end

local report = E.ReadyReport
if report and report.AddColumn then
	report:AddColumn({
		key = "shaman", title = "Shaman", width = 130,
		desc = L["The totems each shaman carries and their Ankh count. Yours comes from your bags; another shaman's when they click Share mine."],
		shown = function() return M.db and M.db.plan.share and #M:GroupShamans() > 0 end,
		value = function(row) local kit = M:KitOf(row) return kit and KitText(kit) or "" end,
		text = function(row) return KitText(M:KitOf(row)) end,
	})
	local function Shown() return M.db and M.db.plan.share and #M:GroupShamans() > 0 end
	report:AddColumn({
		key = "shamanGear", title = "Shield and imbue", width = 150,
		desc = L["Each shaman's shield and the minutes left on their weapon imbues (main hand / off hand). Yours is read out of combat; another shaman's when they click Share mine."],
		shown = Shown,
		value = function(row) return GearText(M:KitOf(row)) end,
		text = function(row) return GearText(M:KitOf(row)) end,
	})
	report:AddColumn({
		key = "shamanMana", title = "Mana", width = 50, align = "RIGHT",
		desc = L["Each shaman's mana. Yours is read out of combat; another shaman's when they click Share mine."],
		shown = Shown,
		value = function(row) local kit = M:KitOf(row) return kit and kit.mana or -1 end,
		text = function(row) return ManaText(M:KitOf(row)) end,
	})
	-- Share mine also sends your shaman line (the same click), once per
	-- ready check and only when the report itself was shared.
	hooksecurefunc(report, "OnReadyCheck", function() M.kitSharedThisCheck = false end)
	hooksecurefunc(report, "SendShare", function()
		if not (M.db and M.db.plan.share and M:IsShaman()) or InCombatLockdown() then return end
		if not report.sharedThisCheck or M.kitSharedThisCheck then return end
		if E:SendComm(PREFIX, M:KitPayload(), "GROUP") then
			M.kitSharedThisCheck = true
		else
			E:Print(L["Could not send your totems to the group."])
		end
	end)
end

---------------------------------------------------------------------------
-- Messages in
---------------------------------------------------------------------------
E:RegisterComm(PREFIX, function(payload, sender)
	if type(payload) ~= "string" or Secret(payload) or #payload > 200 then return end
	local fields = { strsplit(";", payload) }
	local kind, format = fields[1], fields[2]
	if format ~= FORMAT then return end
	table.remove(fields, 1)
	table.remove(fields, 1)
	if kind == "P" and M.db and M.db.plan.enabled then
		M:OnPlan(fields, sender)
	elseif kind == "K" and M.db and M.db.plan.share then
		M:OnKit(fields, sender)
	elseif kind == "C" and M.db then
		M:OnCooldowns(fields, sender)
	end
end, { trusted = "group" })

---------------------------------------------------------------------------
-- Shaman group panel: the group's shaman cooldowns in one window
---------------------------------------------------------------------------
-- The cooldowns it lists, in column order.
M.GROUP_COOLDOWNS = {
	{ key = "manatide", spell = 16190 }, -- Mana Tide Totem
	{ key = "reincarnation", spell = 20608 }, -- Reincarnation
}
local MAX_LEFT = 2 * 60 * 60 -- the longest cooldown a message may carry (seconds)
M.sharedCooldowns = {} -- short name -> { manatide = s, reincarnation = s, ankh = n, at = time }

-- Seconds left on one of your spells (0 = ready), false when you don't
-- know it, nil when the game doesn't say (in combat, secret values).
function M:OwnCooldown(spell)
	if not self:Known(spell) then return false end
	if InCombatLockdown() then return nil end
	-- Plain times only, from EldoUI's one cooldown source.
	local source = E.CombatKit and E.CombatKit.Cooldowns
	local start, duration
	if source then start, duration = source.PlainSpellTimes(self:Spell(spell).id) end
	if type(start) ~= "number" or type(duration) ~= "number" then return nil end
	-- A global cooldown is not the spell's own.
	if duration <= 2 or start <= 0 then return 0 end
	return math.max(0, math.min(MAX_LEFT, start + duration - GetTime()))
end

-- C;1;<Mana Tide left>;<Reincarnation left>;<Ankhs>: seconds, "" for a
-- spell the shaman doesn't know, "?" when the game didn't say.
function M:CooldownPayload()
	local parts = { "C", FORMAT }
	for _, cooldown in ipairs(self.GROUP_COOLDOWNS) do
		local left = self:OwnCooldown(cooldown.spell)
		parts[#parts + 1] = left == false and "" or type(left) == "number" and tostring(math.floor(left)) or "?"
	end
	local ankh = self:Known(20608) and ItemCount(D.SPELLS[2].item) or nil
	parts[#parts + 1] = ankh and tostring(math.min(ankh, 99)) or ""
	return table.concat(parts, ";")
end

function M:OnCooldowns(fields, sender)
	local name = ShortName(sender)
	if not name then return end
	local entry = { at = GetTime() }
	for index, cooldown in ipairs(self.GROUP_COOLDOWNS) do
		local field = fields[index]
		local seconds = tonumber(type(field) == "string" and field:match("^(%d+)$") or nil)
		if seconds then
			entry[cooldown.key] = math.min(seconds, MAX_LEFT)
		elseif field == "" then
			entry[cooldown.key] = false
		end
	end
	local ankh = tonumber(type(fields[3]) == "string" and fields[3]:match("^(%d%d?)$") or nil)
	entry.ankh = ankh
	self.sharedCooldowns[name] = entry
	if self.groupWindow then self.groupWindow:Refresh() end
end

-- Share your cooldowns with the group (the player's click, out of combat).
function M:ShareCooldowns()
	if InCombatLockdown() then
		E:Print(L["Your cooldowns can be shared out of combat."])
		return false
	end
	if not Plain(Try(IsInGroup)) then
		E:Print(L["You are not in a group."])
		return false
	end
	if not E:CommRestricted() and E:SendComm(PREFIX, self:CooldownPayload(), "GROUP") then
		E:Print(L["Your shaman cooldowns were sent to the group."])
		return true
	end
	E:Print(L["Could not send your cooldowns: the game doesn't allow addon messages right now."])
	return false
end

-- The plan in use: the one you got, else the one you set.
function M:PlanInUse()
	if self.received then return self.received end
	if self.db.plan.enabled then return self.db.plan end
	return nil
end

-- One row per shaman of the group: { name, me, manatide, reincarnation,
-- ankh, jobs, shared (seconds since they shared, nil for none) }.
-- A cooldown is seconds left, false (not known) or nil (not shared).
function M:GroupRows()
	local rows, plan = {}, self:PlanInUse()
	local me = ShortName(Plain(Try(UnitName, "player")))
	for _, name in ipairs(self:GroupShamans()) do
		local row = { name = name, me = name == me, jobs = {} }
		if row.me then
			for _, cooldown in ipairs(self.GROUP_COOLDOWNS) do row[cooldown.key] = self:OwnCooldown(cooldown.spell) end
			row.ankh = self:Known(20608) and ItemCount(D.SPELLS[2].item) or nil
		else
			local shared = self.sharedCooldowns[name]
			if shared then
				local since = math.max(0, GetTime() - shared.at)
				for _, cooldown in ipairs(self.GROUP_COOLDOWNS) do
					local left = shared[cooldown.key]
					row[cooldown.key] = type(left) == "number" and math.max(0, left - since) or left
				end
				row.ankh, row.shared = shared.ankh, since
			end
		end
		for _, job in ipairs(self.JOBS) do
			if plan and plan[job.key] == name then row.jobs[#row.jobs + 1] = L[job.title] end
		end
		rows[#rows + 1] = row
	end
	return rows
end

local function LeftText(left)
	if left == false then return E:TokenHex(E.UIKit.SECONDARY) .. L["not learned"] .. "|r" end
	if left == nil then return E:TokenHex(E.UIKit.SECONDARY) .. "?" .. "|r" end
	if left <= 0 then return E:TokenHex(E.UIKit.GOOD) .. L["Ready"] .. "|r" end
	if left < 60 then return L["%ds"]:format(math.ceil(left)) end
	return L["%dm"]:format(math.ceil(left / 60))
end
M.LeftText = LeftText

local function SortLeft(left)
	if left == false then return 1e9 end
	if left == nil then return 1e8 end
	return left
end

local function GroupColumns()
	return {
		{ key = "name", title = L["Shaman"], width = 120,
			value = function(row) return row.name end,
			text = function(row) return E:WrapClassColor("SHAMAN", row.name) end },
		{ key = "manatide", title = L["Mana Tide Totem"], width = 110,
			value = function(row) return SortLeft(row.manatide) end,
			text = function(row) return LeftText(row.manatide) end },
		{ key = "reincarnation", title = L["Reincarnation"], width = 120,
			value = function(row) return SortLeft(row.reincarnation) end,
			text = function(row)
				local text = LeftText(row.reincarnation)
				if row.ankh then text = text .. " · " .. L["Ankh %d"]:format(row.ankh) end
				return text
			end },
		{ key = "jobs", title = L["Plan"],
			value = function(row) return table.concat(row.jobs, ", ") end,
			text = function(row) return table.concat(row.jobs, ", ") end },
		{ key = "shared", title = L["Shared"], width = 80, align = "RIGHT",
			value = function(row) return row.me and -1 or row.shared or 1e9 end,
			text = function(row)
				if row.me then return L["You"] end
				if not row.shared then return E:TokenHex(E.UIKit.SECONDARY) .. L["not yet"] .. "|r" end
				return L["%dm ago"]:format(math.floor(row.shared / 60))
			end },
	}
end

local function CreateGroupTab(content)
	local Kit = E.UIKit
	local frame = CreateFrame("Frame", nil, content)
	frame:SetAllPoints()
	frame.toolbar = CreateFrame("Frame", nil, frame)
	frame.toolbar:SetPoint("TOPLEFT")
	frame.toolbar:SetPoint("TOPRIGHT")
	frame.toolbar:SetHeight(E.tokens.height.button)
	frame.share = Kit.Button(frame.toolbar, L["Share mine"], 96, nil, function() M:ShareCooldowns() end,
		L["Share mine"], L["Send your Mana Tide Totem and Reincarnation cooldowns and your Ankh count to the group, once per click, so their panel shows them."])
	frame.share:SetPoint("LEFT", 0, 0)
	frame.plan = Kit.Button(frame.toolbar, L["Send the plan"], 110, nil, function() M:SendPlan() end,
		L["Send the plan"], L["Send the group plan from the Shaman Totems options to the group. One click, one message."])
	frame.plan:SetPoint("LEFT", frame.share, "RIGHT", 6, 0)
	frame.status = Kit.Text(frame.toolbar, E.tokens.size.small, "RIGHT", "secondary")
	frame.status:SetPoint("LEFT", frame.plan, "RIGHT", 8, 0)
	frame.status:SetPoint("RIGHT", -4, 0)
	frame.tbl = Kit.CreateTable(frame, GroupColumns(), {
		sortKey = "name", rowHeight = 20,
		empty = { L["No shamans here"], L["Join a group with a shaman to see the group's shaman cooldowns."] },
	})
	frame.tbl:SetPoint("TOPLEFT", frame.toolbar, "BOTTOMLEFT", 0, -8)
	frame.tbl:SetPoint("BOTTOMRIGHT")
	return frame
end

local function UpdateGroupTab(frame)
	local rows = M:GroupRows()
	local inGroup = Plain(Try(IsInGroup)) and true or false
	frame.share:SetShown(M:IsShaman())
	frame.share:SetEnabled(inGroup and not InCombatLockdown())
	frame.plan:SetShown(M.db.plan.enabled)
	frame.plan:SetEnabled(inGroup and not InCombatLockdown())
	frame.status:SetText(E:Plural(#rows, "%d shaman", "%d shamans"):format(#rows))
	frame.tbl:SetData(rows)
end

function M:BuildGroupWindow()
	if self.groupWindow then return self.groupWindow end
	local win = E.UIKit.CreateTabbedWindow({
		name = "EldoUI_ShamanGroupWindow",
		title = L["Shaman group"],
		width = 600, height = 260,
		store = function()
			self.db.groupWindow = type(self.db.groupWindow) == "table" and self.db.groupWindow or {}
			return self.db.groupWindow
		end,
		tabs = {
			{ key = "cooldowns", title = L["Cooldowns"], desc = L["Mana Tide Totem, Reincarnation and the plan for every shaman of the group."],
				create = CreateGroupTab, show = UpdateGroupTab, refresh = UpdateGroupTab },
		},
		help = { text = L["Your own cooldowns come from the game, out of combat. Another shaman's show only after they click Share mine on their own panel; their times count down from what they sent. The plan column shows the group plan you sent or got. Nothing is sent on its own."] },
	})
	self.groupWindow = win
	win:Build()
	return win
end

local GROUP_TICK = "ShamanTotems:group"

-- Open the panel (out of combat; the window waits for the fight's end).
function M:OpenGroupWindow()
	local win = self:BuildGroupWindow()
	local opened = win:Open("cooldowns")
	-- Times count down while the panel is open (the shared ticker; it
	-- ends when the panel closes or the module goes off).
	if E.Ticker and not E.Ticker:IsSubscribed(GROUP_TICK) then
		E.Ticker:Subscribe(GROUP_TICK, 1, function()
			if win:IsOpen() and M.active then
				win:Refresh()
			else
				E.Ticker:Unsubscribe(GROUP_TICK)
			end
		end, M)
	end
	return opened
end
