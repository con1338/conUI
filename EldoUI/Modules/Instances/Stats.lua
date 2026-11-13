-- EldoUI Instances: what happens inside a run.
--
-- While you are inside, the open run collects:
--   xp        the PLAYER_XP_UPDATE delta (UnitXP / UnitXPMax across level-ups)
--   kills     "XP kills": CHAT_MSG_COMBAT_XP_GAIN lines that match the game's
--             own "<mob> dies, you gain" strings (E.ChatParse "xpkill"), so
--             quest XP is not counted; at max level there are none
--   money     looted coins (CHAT_MSG_MONEY with the game's coin words); the
--             money change from entering to leaving is the fallback
--   rep       faction-change lines, summed per faction
--   currency  CURRENCY_DISPLAY_UPDATE gains, per currency
--   group     everyone the roster snapshots saw (name, level, class,
--             guild, role, realm) out of combat
--
-- No combat log: kills are XP events, not deaths. Chat text that arrives
-- as a secret value (chat messaging lockdown in a boss fight) is skipped,
-- so a count may come out low; the tooltip says it is an XP-kill count.
--
-- It also writes the stat lines the datatext, the log tooltip and the
-- end-of-run summary in your own chat use, and the plain text a "Post"
-- click sends (never the gold).
local _, E = ...
local L = E.L
local M = E.Instances
local P = E.ChatParse

local floor, max = math.floor, math.max
local IsSecret, Plain = M.IsSecret, M.Plain
local GREY = M.COLORS.GREY

local function Number(text)
	if type(text) ~= "string" then return nil end
	return tonumber((text:gsub("[^%d]", "")))
end

local function Big(value)
	value = floor(value or 0)
	if BreakUpLargeNumbers then
		local ok, text = pcall(BreakUpLargeNumbers, value)
		if ok and type(text) == "string" then return text end
	end
	return tostring(value)
end
M.Big = Big

---------------------------------------------------------------------------
-- Collecting
---------------------------------------------------------------------------
local base = {} -- level, xp, xpMax at the last XP update

local function Baseline()
	base.level, base.xp, base.xpMax = M.PlayerXP()
end

function M:OnCurrentChanged(run)
	if run then Baseline() end
end

local function OnXP(_, unit)
	local run = M.current
	if not run or unit ~= "player" then return end
	local level, xp, xpMax = M.PlayerXP()
	if not (level and xp) then return end
	local delta
	if base.level and base.xp then
		if level == base.level then
			delta = xp - base.xp
		elseif level > base.level and base.xpMax then
			delta = (base.xpMax - base.xp) + xp
		end
	end
	if delta and delta > 0 then run.xp = (run.xp or 0) + delta end
	base.level, base.xp, base.xpMax = level, xp, xpMax
end

local function OnXPLine(_, text)
	local run = M.current
	if not run or run.kind == "pvp" then return end
	-- Only lines naming a mob: "You gain N experience." is quest or
	-- exploration XP.
	local fields = P:Parse("xpkill", text)
	if fields and fields.mob and fields.mob ~= "" then run.kills = (run.kills or 0) + 1 end
end

local function OnMoney(_, text)
	local run = M.current
	if not run or run.kind == "pvp" then return end
	local fields = P:Parse("money", text)
	local copper = fields and P:Money(fields.money)
	if copper and copper > 0 then run.money = (run.money or 0) + copper end
end

local function OnRep(_, text)
	local run = M.current
	if not run then return end
	local fields = P:Parse("rep", text)
	if not (fields and type(fields.faction) == "string") then return end
	local amount = Number(fields.amount) or (fields.loss and -(Number(fields.loss) or 0))
	if not amount or amount == 0 then return end
	run.rep = run.rep or {}
	run.rep[fields.faction] = (run.rep[fields.faction] or 0) + amount
end

local function OnCurrency(_, currencyID, _, change)
	local run = M.current
	if not run then return end
	currencyID, change = Plain(currencyID), Plain(change)
	if type(currencyID) ~= "number" or type(change) ~= "number" or change <= 0 then return end
	if M.IsHonorCurrency and M:IsHonorCurrency(currencyID) then return end
	local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and M.Try(C_CurrencyInfo.GetCurrencyInfo, currencyID)
	local name = type(info) == "table" and Plain(info.name)
	if type(name) ~= "string" or name == "" then return end
	run.currency = run.currency or {}
	local entry = run.currency[currencyID] or { name = name, icon = Plain(info.iconFileID), count = 0 }
	entry.count = (entry.count or 0) + change
	run.currency[currencyID] = entry
end

-- Party or raid members now (out of combat): everyone seen during the run
-- stays in run.group (a member who left keeps the time last seen, one who
-- joined late is added). Per member: level, class, guild, the role the game
-- assigned (never guessed), the realm when it is another one, the
-- companion key My Adventure uses, first and last seen; your own entry is
-- marked `me`. Unknown values never overwrite what was seen before, and a
-- member whose name is secret is skipped for that snapshot. Raids keep
-- every member by name too. Battlegrounds and arenas keep nothing about
-- the other players.
local PARTY_UNITS, RAID_UNITS = { "player" }, {}
for index = 1, 4 do PARTY_UNITS[#PARTY_UNITS + 1] = "party" .. index end
for index = 1, 40 do RAID_UNITS[index] = "raid" .. index end

local function OwnRealm(realm)
	local normalized = Plain(GetNormalizedRealmName and GetNormalizedRealmName())
	local name = Plain(GetRealmName and GetRealmName())
	return realm == normalized or realm == name or (type(name) == "string" and realm == name:gsub("[%s%-]", ""))
end

local function SeeMember(seen, unit, mine, now)
	local exists = UnitExists(unit)
	if IsSecret(exists) or not exists then return end
	-- Name, or Name-Realm for another realm; never the surname.
	local name = E:UnitNameKey(unit)
	if type(name) ~= "string" or name == UNKNOWN then return end
	local entry = seen[name]
	if not entry then
		entry = { first = now }
		seen[name] = entry
	end
	entry.last = now
	local guid = Plain(UnitGUID(unit))
	if unit == "player" or (mine and guid == mine) then entry.me = true end
	local level = Plain(UnitLevel(unit))
	if type(level) == "number" and level > 0 then entry.level = level end
	local _, class = UnitClass(unit)
	class = Plain(class)
	if type(class) == "string" and class ~= "" then entry.class = class end
	local guild = Plain((GetGuildInfo(unit)))
	if type(guild) == "string" and guild ~= "" then entry.guild = guild end
	local role = UnitGroupRolesAssigned and Plain(UnitGroupRolesAssigned(unit))
	if type(role) == "string" and role ~= "" and role ~= "NONE" then entry.role = role end
	if not entry.me then
		local _, realm = E:UnitNameRealm(unit, true)
		if type(realm) == "string" and realm ~= "" and not OwnRealm(realm) then entry.realm = realm end
		local J = E.Journal
		local key = J and J.Key and J:Key(unit)
		if type(key) == "string" then entry.key = key end
	end
end

function M:SnapshotGroup()
	local run = self.current
	if not run or run.kind == "pvp" then return end
	if InCombatLockdown() then
		self.rosterAfterCombat = true
		return
	end
	self.rosterAfterCombat = nil
	local raid = IsInRaid() and true or false
	run.group = run.group or {}
	local seen, now = run.group, self:Now()
	local mine = Plain(UnitGUID("player"))
	for _, unit in ipairs(raid and RAID_UNITS or PARTY_UNITS) do SeeMember(seen, unit, mine, now) end
	if raid then
		local members = 0
		for _ in pairs(seen) do members = members + 1 end
		run.groupSize = math.max(members, tonumber(run.groupSize) or 0)
	end
end

-- Roster changes in a burst are one snapshot two seconds later.
local rosterQueued = false
local function RosterSnapshot()
	rosterQueued = false
	M:SnapshotGroup()
end

local function OnRoster()
	if rosterQueued then return end
	rosterQueued = true
	C_Timer.After(2, RosterSnapshot)
end

local function OnCombatEnd()
	if M.rosterAfterCombat then OnRoster() end
end

function M:OnRunStarted(run)
	Baseline()
	for _, delay in ipairs({ 1, 30 }) do
		C_Timer.After(delay, function()
			if M.current == run then M:SnapshotGroup() end
		end)
	end
end

M:Listen("PLAYER_XP_UPDATE", "stats", OnXP)
M:Listen("CHAT_MSG_COMBAT_XP_GAIN", "stats", OnXPLine)
M:Listen("CHAT_MSG_MONEY", "stats", OnMoney)
M:Listen("CHAT_MSG_COMBAT_FACTION_CHANGE", "stats", OnRep)
M:Listen("CURRENCY_DISPLAY_UPDATE", "stats", OnCurrency)
M:Listen("GROUP_ROSTER_UPDATE", "stats", OnRoster)
M:Listen("PLAYER_REGEN_ENABLED", "stats", OnCombatEnd)

---------------------------------------------------------------------------
-- Stat lines
---------------------------------------------------------------------------
function M:RunDuration(run, now)
	local stop = run.leave or now or self:Now()
	return max(0, stop - (run.enter or stop))
end

function M:GroupLevel(run)
	local total, count = tonumber(run.groupLevelSum) or 0, tonumber(run.groupLevelCount) or 0
	for _, info in pairs(run.group or {}) do
		if type(info.level) == "number" then
			total, count = total + info.level, count + 1
		end
	end
	if count == 0 then return nil end
	return total / count, count
end

-- The looted gold, or the money change when no loot line was readable.
function M:RunMoney(run)
	if (run.money or 0) > 0 then return run.money, false end
	if run.kind ~= "pvp" and run.enterMoney and run.leaveMoney and run.leaveMoney > run.enterMoney then
		return run.leaveMoney - run.enterMoney, true
	end
	return 0, false
end

function M:HasActivity(run)
	return (run.xp or 0) > 0 or (run.kills or 0) > 0 or (run.money or 0) > 0 or (run.honor or 0) > 0
		or next(run.rep or {}) ~= nil or next(run.currency or {}) ~= nil
end

-- Pieces of the stat line: { key, text }. opts.all ignores the toggles,
-- opts.plain leaves out colors and the gold (for posting).
function M:StatPieces(run, opts)
	opts = opts or {}
	local show = self.db.show or {}
	local function On(key) return opts.all or show[key] end
	local pieces = {}
	local function Add(key, text) pieces[#pieces + 1] = { key, text } end
	local duration = self:RunDuration(run)
	if On("time") then Add("time", self:Duration(duration)) end
	if run.kind == "pvp" then
		if self.PvPPieces then self:PvPPieces(run, Add, On, opts) end
		return pieces
	end
	local xp, kills = run.xp or 0, run.kills or 0
	if On("kills") and kills > 0 then Add("kills", (L["%d XP kills"]):format(kills)) end
	if On("xp") and xp > 0 then
		local text = (L["%s XP"]):format(Big(xp))
		if On("xpPercent") and (run.enterXPMax or 0) > 0 then
			text = text .. " " .. (L["(%d%% of a level)"]):format(floor(xp / run.enterXPMax * 100 + 0.5))
		end
		Add("xp", text)
	end
	if On("xpHour") and xp > 0 and duration >= 60 then Add("xpHour", (L["%s XP/h"]):format(Big(xp / duration * 3600))) end
	if On("xpKill") and xp > 0 and kills > 0 then Add("xpKill", (L["%s XP per kill"]):format(Big(xp / kills))) end
	if On("runsLevel") and xp > 0 and (run.enterXPMax or 0) > 0 then
		Add("runsLevel", (L["%.1f runs per level"]):format(run.enterXPMax / xp))
	end
	if On("runsNext") and xp > 0 and run.leaveXPMax and run.leaveXP and run.leaveXPMax > run.leaveXP then
		Add("runsNext", (L["%.1f runs to level %d"]):format((run.leaveXPMax - run.leaveXP) / xp, (run.leaveLevel or 0) + 1))
	end
	if On("gold") and not opts.plain then
		local money, change = self:RunMoney(run)
		if money > 0 then Add("gold", change and (L["%s money change"]):format(self:Money(money)) or self:Money(money)) end
	end
	if On("rep") then
		for faction, amount in pairs(run.rep or {}) do
			Add("rep", ("%s%s %s"):format(amount >= 0 and "+" or "", Big(amount), faction))
		end
	end
	if On("currency") then
		for _, entry in pairs(run.currency or {}) do
			Add("currency", ("+%s %s"):format(Big(entry.count or 0), entry.name or "?"))
		end
	end
	if On("groupLevel") then
		local average, count = self:GroupLevel(run)
		if average and count > 1 then Add("groupLevel", (L["group level %.1f"]):format(average)) end
	end
	return pieces
end

function M:StatLine(run, opts)
	local texts = {}
	for _, piece in ipairs(self:StatPieces(run, opts)) do texts[#texts + 1] = piece[2] end
	return table.concat(texts, " · ")
end

-- The open run's block in the datatext tooltip (live), or a row's details.
function M:AddRunStats(tooltip, run, live)
	local function Line(label, value)
		E.UIKit.TipPair(tooltip, label, value)
	end
	if run.kind == "pvp" then
		if self.AddPvPStats then self:AddPvPStats(tooltip, run) end
		return
	end
	local duration = self:RunDuration(run)
	if (run.kills or 0) > 0 then
		Line(L["XP kills"], tostring(run.kills))
	elseif run.maxLevel then
		Line(L["XP kills"], "–")
	end
	if (run.xp or 0) > 0 then
		local text = Big(run.xp)
		if (run.enterXPMax or 0) > 0 then text = text .. GREY .. (" (%d%%)"):format(floor(run.xp / run.enterXPMax * 100 + 0.5)) .. "|r" end
		Line(L["XP"], text)
		if duration >= 60 then Line(L["XP per hour"], Big(run.xp / duration * 3600)) end
		if (run.kills or 0) > 0 then Line(L["XP per kill"], Big(run.xp / run.kills)) end
	end
	local money, change = self:RunMoney(run)
	if money > 0 then Line(change and L["Money change"] or L["Gold from mobs"], self:Money(money)) end
	if not live then return end
	for faction, amount in pairs(run.rep or {}) do Line(faction, (amount >= 0 and "+" or "") .. Big(amount)) end
	for _, entry in pairs(run.currency or {}) do Line(entry.name or "?", "+" .. Big(entry.count or 0)) end
end

---------------------------------------------------------------------------
-- End-of-run summary (own chat), printing and posting a run
---------------------------------------------------------------------------
function M:OnRunLeft(run)
	if not self.db.summary then return end
	if run.kind == "pvp" and self.PvPSummary then return self:PvPSummary(run) end
	if self.db.summaryOnlyActivity and not self:HasActivity(run) then return end
	local line = self:StatLine(run)
	if line == "" then return end
	self:Notice((L["Left %s: %s"]):format(self:RunTitle(run), line))
end

function M:PrintRun(id)
	local run = self:FindRun(id)
	if not run then return end
	local line = self:StatLine(run, { all = true })
	self:Notice(("%s, %s: %s"):format(self:RunTitle(run), self:ShortName(run), line ~= "" and line or L["nothing recorded"]))
end

-- Plain text for a chat message: no color codes or links, no gold, at
-- most 255 characters.
function M:PostText(run)
	local text = ("%s: %s"):format(self:RunTitle(run), self:StatLine(run, { all = true, plain = true })) -- no-L: punctuation only, sent to chat
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|H.-|h(.-)|h", "%1")
	if #text > 255 then text = E:Utf8Clip(text, 252) .. "..." end
	return text
end

-- Where a post can go now: "INSTANCE_CHAT" in a battleground or finder
-- group (RAID and PARTY don't reach it there), else "RAID", "PARTY" or nil.
-- LE_PARTY_CATEGORY_INSTANCE may be missing on Forever: its value is 2.
local INSTANCE_CATEGORY = rawget(_G, "LE_PARTY_CATEGORY_INSTANCE") or 2

function M:GroupChannel()
	local instance = M.Try(IsInGroup, INSTANCE_CATEGORY)
	if not IsSecret(instance) and instance then return "INSTANCE_CHAT" end
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
end


-- Sends one chat message. Only ever called from a click (a menu entry,
-- a button or a typed command), and only with "Allow posting" on.
function M:Say(text, channel)
	if not self.db.allowPosting then
		self:Notice(L["Posting is off. Turn on \"Allow posting\" under Instances > Sharing first."])
		return false
	end
	if channel == "GROUP" then channel = self:GroupChannel() end
	if channel == "GUILD" and not IsInGuild() then channel = nil end
	if not channel then
		self:Notice(L["You are not in a group."])
		return false
	end
	if not E:TryChatPost(text, channel) then
		self:Notice(E:ChatRefusedText())
		return false
	end
	return true
end

function M:PostRun(id, channel)
	local run = self:FindRun(id)
	if not run then return false end
	return self:Say(self:PostText(run), channel)
end

-- /eui instances stats [party | raid | guild | group]: the newest run.
function M:StatsCommand(rest)
	local run = self.current or self:LastRun()
	if not run then
		self:Notice(L["No runs logged yet."])
		return
	end
	local channel = (rest or ""):upper()
	if channel == "" or channel == "SELF" then
		self:PrintRun(run.id)
	elseif channel == "PARTY" or channel == "RAID" or channel == "GROUP" or channel == "GUILD" or channel == "INSTANCE" then
		self:PostRun(run.id, channel == "INSTANCE" and "GROUP" or channel)
	else
		self:Notice(L["Use /eui instances stats, or stats party, raid, group or guild."])
	end
end
