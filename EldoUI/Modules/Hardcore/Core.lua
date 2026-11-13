-- EldoUI Hardcore: a death log, death alerts, the own-death "Tell the
-- guild" card, PvP-flag warnings and rule reminders. Active only on a
-- Hardcore character (C_GameRules.IsHardcoreActive, or the Hardcore
-- ruleset rule as Core/Database.lua reads it).
--
--   Death log      Deaths the game announces (HARDCORE_DEATHS, the event
--                  behind Blizzard's own red death warnings) and deaths
--                  guild members running EldoUI tell their guild about.
--                  The game message is read with the game's own
--                  HARDCORE_CAUSEOFDEATH_* strings (every locale): name,
--                  level, zone and cause. A message EldoUI can't read is
--                  kept as it came.
--   Death alerts   A card in the alert lane for guild, group or all
--                  announced deaths (option), with a sound.
--   Tell the guild After your own death a card with one button that writes
--                  one line in guild chat (and, when on, one addon message
--                  so guild members' EldoUI can log class and cause).
--                  Nothing is ever sent without that click.
--   PvP warning    A warning card and sound when your target is flagged for
--                  PvP and attacking or helping it would flag you, and when
--                  you become flagged yourself.
--   Reminders      A short notice at the mailbox, auction house and trade
--                  window while the game's Self-Found rule is on for you.
--
-- How it stays within the rules (Midnight / Forever):
--   * Only what the game tells: its death messages, unit flags and rules.
--     No combat log, nothing inferred. Secret values are skipped.
--   * Messages go out only on the player's click (one click, one line).
--     Incoming addon messages are accepted from guild members only and
--     never answered.
-- Written from scratch for EldoUI; no code, strings or data from other addons.
local _, E = ...
local L = E.L

local PREFIX = "EUI_HC"
local LOG_LIMITS = { min = 50, max = 1000 }

local M = E:NewModule("Hardcore", {
	title = "Hardcore",
	desc = "For Hardcore characters: a log of announced deaths, death alerts, a Tell the guild card after your own death, PvP-flag warnings and Self-Found reminders.",
	category = "Quality of Life",
	frames = {},
	movers = { "EldoUI_DeathLog" },
	blizzard = {},
	savedKeys = { "profile.modules.Hardcore", "global.hardcoreDeaths" },
	optionsPage = "module:Hardcore",
	presets = { "ForeverBronze", "LogOnly", "Minimal", "Quiet", "Stark" },
	reload = false,
	themed = "ApplyLook",
	defaults = {
		alerts = true,              -- death alert cards
		alertScope = "guild",       -- "guild" (guild and group), "group" or "all"
		alertTitle = "bad",         -- title color: "bad" (red), "accent" or "plain"
		alertSound = "eldo:EldoWarning",
		ownCard = true,             -- the Tell the guild card after your own death
		tellAddon = true,           -- the click also sends one addon message to the guild
		listen = true,              -- log deaths guild members' EldoUI sends
		pvpTarget = true,           -- warn on a flagged target
		pvpSelf = true,             -- warn when you get flagged
		pvpSound = "eldo:EldoAlarm",
		reminders = true,           -- Self-Found notices at mail, auction house, trade
		logMax = 300,               -- entries kept
		rowHeight = 20,
		transparent = false,
		classColors = true,
	},
})
E.Hardcore = M
M.PREFIX = PREFIX

local Secret = E.Secret
M.Secret = Secret

local Read = E.PlainCall

local function ShortName(name)
	if type(name) ~= "string" then return nil end
	return (name:gsub("%-.*$", ""))
end
M.ShortName = ShortName

---------------------------------------------------------------------------
-- Is this a Hardcore character?
---------------------------------------------------------------------------
function M.IsHardcore()
	local rules = C_GameRules
	if rules and type(rules.IsHardcoreActive) == "function" then
		local on = Read(rules.IsHardcoreActive)
		if on ~= nil then return on and true or false end
	end
	return E.RulesetName ~= nil and E:RulesetName() == "HC"
end

-- On, and on a Hardcore character.
function M:Live()
	return self.active and M.IsHardcore()
end

function M.NotHardcoreReason()
	if M.IsHardcore() then return nil end
	return L["Only on a Hardcore character."]
end

---------------------------------------------------------------------------
-- The game's death messages
---------------------------------------------------------------------------
-- The fields of each HARDCORE_CAUSEOFDEATH_* string, in argument order
-- (%1$s, %2$s, ...). Some translations move the arguments around in the
-- text (ptBR names the killer first), so each capture is read by the
-- position number it carries, not by where it sits in the line.
M.CAUSES = {
	{ key = "CREATURE", fields = { "link", "name", "killer", "zone", "level" } },
	{ key = "PVP", fields = { "link", "name", "killer", "zone", "level" } },
	{ key = "DUEL", fields = { "link", "name", "killer", "zone", "level" } },
	{ key = "DROWNING", fields = { "link", "name", "zone", "level" } },
	{ key = "FALLING", fields = { "link", "name", "zone", "level" } },
	{ key = "FATIGUE", fields = { "link", "name", "zone", "level" } },
	{ key = "FIRE", fields = { "link", "name", "zone", "level" } },
	{ key = "LAVA", fields = { "link", "name", "zone", "level" } },
	{ key = "SLIME", fields = { "link", "name", "zone", "level" } },
	{ key = "NONE", fields = { "link", "name", "level" } },
}

M.CAUSE_TEXT = {
	CREATURE = "Slain by %s", PVP = "Slain by %s", DUEL = "Lost a duel to the death to %s",
	DROWNING = "Drowned", FALLING = "Fell to their death", FATIGUE = "Died of fatigue",
	FIRE = "Burned by fire", LAVA = "Burned by lava", SLIME = "Slimed", NONE = "Died",
}

-- A format string ("%s", "%d", "%3$s", "|3-1(%s)") as a Lua pattern;
-- returns the pattern, how many values it captures, and for each capture
-- the argument it holds (the n of "%n$s", or its place in the line).
function M.FormatToPattern(fmt)
	if type(fmt) ~= "string" or Secret(fmt) or fmt == "" then return nil end
	local out, order, count, i = { "^" }, {}, 0, 1
	while i <= #fmt do
		local grammar, gPosition = fmt:match("^(|3%-%d+%(%%(%d*)%$?s%))", i)
		local spec, sPosition = fmt:match("^(%%(%d*)%$?[sd])", i)
		if grammar then
			out[#out + 1] = "(.-)"
			count = count + 1
			order[count] = tonumber(gPosition) or count
			i = i + #grammar
		elseif spec then
			out[#out + 1] = spec:sub(-1) == "d" and "(%d+)" or "(.-)"
			count = count + 1
			order[count] = tonumber(sPosition) or count
			i = i + #spec
		else
			local char = fmt:sub(i, i)
			out[#out + 1] = char:find("[%^%$%(%)%%%.%[%]%*%+%-%?]") and ("%" .. char) or char
			i = i + 1
		end
	end
	return table.concat(out), count, order
end

local patterns
local function Patterns()
	if patterns then return patterns end
	patterns = {}
	for _, cause in ipairs(M.CAUSES) do
		local fmt = rawget(_G, "HARDCORE_CAUSEOFDEATH_" .. cause.key)
		local pattern, count, order = M.FormatToPattern(fmt)
		if pattern and count >= 3 then
			patterns[#patterns + 1] = { key = cause.key, pattern = pattern, fields = cause.fields, count = count, order = order }
		end
	end
	-- Longest first, so "slain in a duel by" wins over "slain by".
	table.sort(patterns, function(a, b) return #a.pattern > #b.pattern end)
	return patterns
end
function M.ResetPatterns() patterns = nil end

-- A death message -> { name, level, zone, cause, killer, text } or nil.
function M.ParseMessage(message)
	if type(message) ~= "string" or Secret(message) or message == "" then return nil end
	for _, entry in ipairs(Patterns()) do
		local values = { message:match(entry.pattern) }
		if values[1] ~= nil then
			local death = { cause = entry.key, text = message }
			for index = 1, entry.count do
				local field = entry.fields[entry.order[index]]
				if field then death[field] = values[index] end
			end
			death.level = tonumber(death.level)
			if death.name == "" then death.name = nil end
			death.name = death.name or ShortName(death.link)
			if death.name then return death end
		end
	end
	-- Unknown wording: keep the text; the name comes from the player link.
	local link = message:match("|Hplayer:([^|:]+)")
	return { text = message, name = ShortName(link), raw = true }
end

---------------------------------------------------------------------------
-- The log (account wide)
---------------------------------------------------------------------------
E:RegisterGlobal("hardcoreDeaths", { list = {} }, {
	title = "Hardcore death log", desc = "Deaths the game announced and deaths guild members told you about.",
})

local function Store()
	local data = E:GetGlobal("hardcoreDeaths")
	if type(data) ~= "table" then return nil end
	if type(data.list) ~= "table" then data.list = {} end
	return data
end
M.Store = Store

function M:Log()
	local data = Store()
	return data and data.list or {}
end

function M:LogMax()
	local n = tonumber(self.db and self.db.logMax) or 300
	return math.max(LOG_LIMITS.min, math.min(LOG_LIMITS.max, math.floor(n)))
end

-- Where the death comes from: "self", "group", "guild" or "realm".
function M.Relation(name)
	if type(name) ~= "string" or Secret(name) then return "realm" end
	local me = Read(UnitName, "player")
	if me and ShortName(name) == me then return "self" end
	if E:CommTrusted(name, "group") then return "group" end
	if E:CommTrusted(name, "guild") then return "guild" end
	return "realm"
end

-- The class file of a unit or a group member's name, or nil.
local function ClassOf(unit)
	if not unit then return nil end
	local ok, _, class = pcall(UnitClass, unit)
	if ok and type(class) == "string" and not Secret(class) then return class end
end
M.ClassOf = ClassOf

local function GroupClass(name)
	if name and (UnitInParty(name) or UnitInRaid(name)) then return ClassOf(name) end
end

-- Adds a death, or fills in the one just logged for the same name (the
-- game's line and a guild member's note for one death). Returns the entry
-- and whether it is new.
function M:AddDeath(death)
	if type(death) ~= "table" or not death.name then return nil end
	local list = self:Log()
	local now = time()
	local short = ShortName(death.name)
	for index = #list, math.max(1, #list - 20), -1 do
		local old = list[index]
		if old.name == short and math.abs(now - (old.t or 0)) <= 120 then
			-- The game's own line wins over what EldoUI read at PLAYER_DEAD.
			local game = death.source == "game" and death.cause ~= nil
			for _, field in ipairs({ "level", "zone", "cause", "killer", "class", "text" }) do
				if death[field] ~= nil and (old[field] == nil or (game and field ~= "class")) then old[field] = death[field] end
			end
			old.source = old.source == death.source and old.source or "both"
			return old, false
		end
	end
	local entry = {
		t = now, name = short, level = death.level, zone = death.zone, cause = death.cause,
		killer = death.killer, class = death.class or GroupClass(short), text = death.text,
		source = death.source or "game", rel = death.rel or M.Relation(death.name),
		realm = E.RealmKey and E:RealmKey() or nil,
	}
	list[#list + 1] = entry
	local cap = self:LogMax()
	while #list > cap do table.remove(list, 1) end
	if self.window then self:RefreshWindow() end
	return entry, true
end

function M:ClearLog()
	local data = Store()
	if data then wipe(data.list) end
	if self.window then self:RefreshWindow() end
end

function M.CauseText(entry)
	if not entry or not entry.cause then return "" end
	local text = M.CAUSE_TEXT[entry.cause]
	if not text then return "" end
	if text:find("%s", 1, true) then return L[text]:format(entry.killer or "?") end
	return L[text]
end

---------------------------------------------------------------------------
-- Alerts
---------------------------------------------------------------------------
-- A card shows its title in the accent color unless it is told another,
-- so "plain" names the body text color.
local function TitleColor(text)
	local look = M.db.alertTitle
	if look == "bad" then return E:TokenHex(E.UIKit.BAD) .. text .. "|r" end
	if look == "accent" then return E.UIKit.AccentHex() .. text .. "|r" end
	return E:TokenHex(E.tokens.text.body) .. text .. "|r"
end
M.TitleColor = TitleColor

function M:WantsAlert(entry)
	if not self.db.alerts or entry.rel == "self" then return false end
	local scope = self.db.alertScope
	if scope == "all" then return true end
	if scope == "group" then return entry.rel == "group" end
	return entry.rel == "group" or entry.rel == "guild"
end

function M.AlertText(entry)
	local who = entry.level and L["%s (%d)"]:format(entry.name, entry.level) or entry.name
	if entry.zone and entry.zone ~= "" then return L["%s died in %s"]:format(who, entry.zone) end
	return L["%s died"]:format(who)
end

function M:Alert(entry)
	if not self:WantsAlert(entry) then return false end
	local cause = M.CauseText(entry)
	M:PushAlert({
		title = TitleColor(L["Hardcore death"]),
		text = cause ~= "" and (M.AlertText(entry) .. "\n" .. cause) or M.AlertText(entry),
		icon = 237542, key = "hcdeath:" .. entry.name,
	})
	E:PlayMedia(self.db.alertSound)
	return true
end

---------------------------------------------------------------------------
-- Incoming deaths
---------------------------------------------------------------------------
M.seen = { messages = 0, unread = 0, notes = 0 }

function M:OnGameDeath(message)
	if not self:Live() then return end
	if type(message) ~= "string" or Secret(message) then
		M.seen.unread = M.seen.unread + 1
		return
	end
	M.seen.messages = M.seen.messages + 1
	M.lastMessage = message
	local death = M.ParseMessage(message)
	if not death or not death.name then
		M.seen.unread = M.seen.unread + 1
		return
	end
	death.source = "game"
	local entry, new = self:AddDeath(death)
	if entry and entry.rel == "self" then self.ownEntry = entry end
	if entry and new then self:Alert(entry) end
end

-- "1;<level>;<class>;<cause>;<killer>;<zone>" from a guild member about
-- their own death.
local function Clean(text, limit)
	text = tostring(text or ""):gsub("[;|\n\r]", " ")
	return E:Utf8Clip(text, limit or 60)
end

function M:NotePayload(level, class, cause, killer, zone)
	return ("1;%d;%s;%s;%s;%s"):format(tonumber(level) or 0, Clean(class, 16), Clean(cause, 12), Clean(killer), Clean(zone))
end

function M:OnNote(payload, sender)
	if not (self:Live() and self.db.listen) then return end
	if type(payload) ~= "string" or Secret(payload) or type(sender) ~= "string" or Secret(sender) then return end
	local level, class, cause, killer, zone = payload:match("^1;(%d+);([%u]*);([%u]*);([^;]*);([^;]*)$")
	if not level then return end
	level = tonumber(level)
	if not level or level < 1 or level > 100 then return end
	M.seen.notes = M.seen.notes + 1
	local death = {
		name = ShortName(sender), level = level, class = class ~= "" and class or nil,
		cause = M.CAUSE_TEXT[cause] and cause or nil, killer = killer ~= "" and killer or nil,
		zone = zone ~= "" and zone or nil, source = "guild",
	}
	local entry, new = self:AddDeath(death)
	if entry and new then self:Alert(entry) end
end

---------------------------------------------------------------------------
-- Your own death: the Tell the guild card
---------------------------------------------------------------------------
function M:OwnDeath()
	if not self:Live() then return end
	local level = Read(UnitLevel, "player")
	local zone = Read(GetRealZoneText)
	local entry = self:AddDeath({
		name = Read(UnitName, "player"), level = level, zone = zone, rel = "self",
		class = ClassOf("player"), source = "game",
	})
	self.ownEntry = entry
	self.told = false
	-- The game's own line (with the cause) comes a moment after PLAYER_DEAD.
	C_Timer.After(1.5, function() M:ShowOwnCard() end)
end

function M:TellText(entry)
	entry = entry or self.ownEntry or {}
	local where = entry.zone and entry.zone ~= "" and entry.zone or nil
	local text
	if where then
		text = L["I died at level %d in %s."]:format(entry.level or 0, where)
	else
		text = L["I died at level %d."]:format(entry.level or 0)
	end
	local cause = M.CauseText(entry)
	if cause ~= "" and entry.cause ~= "NONE" then text = text .. " (" .. cause .. ")" end
	return text
end

function M:ShowOwnCard()
	if not (self:Live() and self.db.ownCard) or not self.ownEntry then return false end
	local entry = self.ownEntry
	local text = M.AlertText(entry)
	local cause = M.CauseText(entry)
	if cause ~= "" and entry.cause ~= "NONE" then text = text .. "\n" .. cause end
	local actions
	if IsInGuild() then
		actions = {
			{ label = L["Tell the guild"], tip = L["Write one line about your death in guild chat."], func = function() M:TellGuild() end },
			{ label = L["Close"] },
		}
	end
	M:PushAlert({ title = TitleColor(L["You died"]), text = text, icon = 237542, key = "hcown", actions = actions, closable = true })
	return true
end

-- One click, one guild chat line (and one addon message when on).
function M:TellGuild()
	if not self:Live() or self.told or not IsInGuild() then return false end
	local entry = self.ownEntry
	if not entry then return false end
	if not E:TryChatPost(self:TellText(entry), "GUILD") then
		E:Print(E:ChatRefusedText())
		return false
	end
	self.told = true
	if self.db.tellAddon then
		E:SendComm(PREFIX, self:NotePayload(entry.level, entry.class, entry.cause, entry.killer, entry.zone), "GUILD")
	end
	return true
end

---------------------------------------------------------------------------
-- PvP-flag warnings
---------------------------------------------------------------------------
local warnedAt = {}

local IdentitySecret = E.IdentitySecret

local function Flagged(unit)
	return (Read(UnitIsPVP, unit) or Read(UnitIsPVPFreeForAll, unit)) and true or false
end
M.Flagged = Flagged

-- "attack", "help" or nil for the target.
function M.TargetRisk(unit)
	unit = unit or "target"
	if not Read(UnitExists, unit) or IdentitySecret(unit) then return nil end
	if Read(UnitIsUnit, unit, "player") then return nil end
	if not Flagged(unit) or Flagged("player") then return nil end
	if Read(UnitCanAttack, "player", unit) then return "attack" end
	if Read(UnitIsPlayer, unit) then return "help" end
	return nil
end

function M:Warn(key, title, text)
	local now = GetTime()
	if warnedAt[key] and now - warnedAt[key] < 30 then return false end
	warnedAt[key] = now
	M:PushAlert({ title = TitleColor(title), text = text, icon = 132485, key = "hcpvp" })
	E:PlayMedia(self.db.pvpSound)
	return true
end
function M.ResetWarnings() wipe(warnedAt) end

function M:CheckTarget()
	if not (self:Live() and self.db.pvpTarget) then return false end
	local risk = M.TargetRisk("target")
	if not risk then return false end
	local name = Read(UnitName, "target") or L["this target"]
	local guid = Read(UnitGUID, "target") or name
	if risk == "attack" then
		return self:Warn("t:" .. guid, L["PvP target"], L["%s is flagged for PvP. Attacking flags you too."]:format(name))
	end
	return self:Warn("t:" .. guid, L["PvP target"], L["%s is flagged for PvP. Healing or buffing them flags you too."]:format(name))
end

function M:CheckSelf()
	local now = Flagged("player")
	local was = self.selfFlagged
	self.selfFlagged = now
	if not (self:Live() and self.db.pvpSelf) then return false end
	if now and was == false then
		return self:Warn("self", L["You are flagged for PvP"], L["Players of the other faction can attack you now."])
	end
	return false
end

---------------------------------------------------------------------------
-- Rule reminders (from the game's rules, never a fixed list of realms)
---------------------------------------------------------------------------
local function SelfFound()
	local info = C_PlayerInfo
	return info and Read(info.IsSelfFoundActive) == true
end
M.SelfFound = SelfFound

M.REMINDERS = {
	mail = { rule = SelfFound, text = "Self-Found is on for this character: mail from other players can't be used." }, -- no-L (translated where shown)
	auction = { rule = SelfFound, text = "Self-Found is on for this character: the auction house can't be used." }, -- no-L (translated where shown)
	trade = { rule = SelfFound, text = "Self-Found is on for this character: trading with other players is blocked." }, -- no-L (translated where shown)
}

function M:Remind(place)
	if not (self:Live() and self.db.reminders) then return false end
	local reminder = M.REMINDERS[place]
	if not (reminder and reminder.rule()) then return false end
	M:PushAlert({ title = L["Rule reminder"], text = L[reminder.text], icon = 136243, key = "hcrule:" .. place })
	return true
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function M:OnEnable()
	self.selfFlagged = Flagged("player")
	-- The window (and its mover) exists from the start, so the mover can be
	-- placed and checked in every layout like any other.
	self:BuildWindow()
	self:RegisterEvent("HARDCORE_DEATHS", function(_, _, message) M:OnGameDeath(message) end)
	self:RegisterEvent("PLAYER_DEAD", function() M:OwnDeath() end)
	self:RegisterEvent("PLAYER_TARGET_CHANGED", function() M:CheckTarget() end)
	self:RegisterUnitEvent("PLAYER_FLAGS_CHANGED", "player", function() M:CheckSelf() end)
	self:RegisterUnitEvent("UNIT_FACTION", "player", function() M:CheckSelf() end)
	self:RegisterEvent("MAIL_SHOW", function() M:Remind("mail") end)
	self:RegisterEvent("AUCTION_HOUSE_SHOW", function() M:Remind("auction") end)
	self:RegisterEvent("TRADE_SHOW", function() M:Remind("trade") end)
	E:RegisterComm(PREFIX, function(payload, sender) M:OnNote(payload, sender) end, { trusted = "guild" })
end

function M:OnDisable()
	E:UnregisterComm(PREFIX)
	if self.window then self.window:Close() end
end

function M:OnProfileChanged()
	if self.active and self.window then self:ApplyLook() end
end

E:AddCommand("deaths", "open the Hardcore death log", function()
	if not M.active then
		E:Print(E:ModuleOffHint("Hardcore"))
		return
	end
	M:Toggle()
end, "Tools")

E:RegisterProbe("hardcore", "what the game reports for Hardcore death messages", function()
	local cvar = C_CVar and C_CVar.GetCVar
	E:Print(("Hardcore: %s, Self-Found: %s"):format(tostring(M.IsHardcore()), tostring(SelfFound()))) -- no-L
	E:Print(("hardcoreDeathAlertType=%s hardcoreDeathChatType=%s"):format( -- no-L
		tostring(cvar and Read(cvar, "hardcoreDeathAlertType")), tostring(cvar and Read(cvar, "hardcoreDeathChatType"))))
	E:Print(("%d death patterns from the game, %d messages, %d unread, %d guild notes"):format( -- no-L
		#Patterns(), M.seen.messages, M.seen.unread, M.seen.notes))
	if M.lastMessage then
		local death = M.ParseMessage(M.lastMessage) or {}
		E:Print(("last: %s -> %s, %s, %s, %s"):format(M.lastMessage:gsub("|", "||"), tostring(death.name), -- no-L
			tostring(death.level), tostring(death.zone), tostring(death.cause)))
	end
end)

E:RegisterDiagnostics("Hardcore", function()
	if not M.initialized then return {} end
	return { ("   Hardcore: %s, Hardcore character %s, %d logged, %d messages, %d unread, %d guild notes"):format( -- no-L
		M.active and "on" or "off", tostring(M.IsHardcore()), #M:Log(), M.seen.messages, M.seen.unread, M.seen.notes) }
end)
