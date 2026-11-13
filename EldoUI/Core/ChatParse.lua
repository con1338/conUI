-- EldoUI shared chat and system message parser (E.ChatParse).
--
-- The game prints gains, kills and instance notices as chat lines built
-- from its own localized format strings (LOOT_ITEM_SELF, YOU_LOOT_MONEY,
-- COMBATLOG_XPGAIN_FIRSTPERSON, INSTANCE_RESET_SUCCESS, ...). EldoUI turns
-- each of those strings into a Lua pattern once and matches lines against
-- it, never against English text, so parsing works in every client
-- language. A line that arrives as a secret value (chat messaging lockdown,
-- PvP matches) is never read: every call returns nil for it.
--
--   local P = E.ChatParse
--   local fields = P:Parse("item", text)        -- { link = ..., count = "2" } or nil
--   local kind, fields = P:Match(text, { "reset", "tooManyInstances" })
--   local copper = P:Money(fields.money)        -- coin words to copper
--   local args = P:MatchFormat(text, _G.ERR_AUCTION_SOLD_S) -- { "item" } in argument order
--
-- Kinds and their fields (numbers stay strings; tonumber them):
--   item              link, count (nil for one)
--   money             money (the coin text), guild (guild share text)
--   rep               faction, amount (gain) or loss
--   currency          link, count
--   skill             skill, rank
--   xpkill            mob (nil for an unnamed line), xp, extra, extraKind,
--                     group, raid
--   honor             victim, rank, honor, dishonor (true for a dishonorable kill)
--   reset             instance, result ("success", "failed", "zoning", "offline")
--   tooManyInstances  (no fields: a match returns an empty table)
-- Modules add kinds with E.ChatParse:AddKind(kind, list).
-- P:RisenSkills(owner) stands in for the skill line where the game hides it.
local _, E = ...

local P = {}
E.ChatParse = P

local IsSecret = E.Secret

-- The text of a chat event, or nil when it can't be read (secret, empty or
-- not a string).
function P:Readable(text)
	if IsSecret(text) or type(text) ~= "string" or text == "" then return nil end
	return text
end

---------------------------------------------------------------------------
-- Pattern building
---------------------------------------------------------------------------
local MAGIC = "([%(%)%.%%%+%-%*%?%[%]%^%$])"

local function Escape(text)
	return (text:gsub(MAGIC, "%%%1"))
end

-- A pattern from a printf-style global string ("%s", "%d", "%.1f",
-- positional "%1$s"). For each capture it records which argument of the
-- format it is, so translations that reorder their arguments still map to
-- the right field.
function P:BuildPattern(format)
	if type(format) ~= "string" or IsSecret(format) or format == "" then return nil end
	local parts, order, pos, count = {}, {}, 1, 0
	while pos <= #format do
		local s, e, position, conversion = format:find("%%(%d*%$?)[%-%.%d]*([sdfi%%])", pos)
		if not s then break end
		parts[#parts + 1] = Escape(format:sub(pos, s - 1))
		if conversion == "%" then
			parts[#parts + 1] = "%%"
		else
			count = count + 1
			order[count] = tonumber(position:match("^(%d+)%$")) or count
			if conversion == "s" then
				parts[#parts + 1] = "(.-)"
			elseif conversion == "f" then
				parts[#parts + 1] = "([%d%.,]+)"
			else
				parts[#parts + 1] = "(%-?%d+)"
			end
		end
		pos = e + 1
	end
	parts[#parts + 1] = Escape(format:sub(pos))
	return { pattern = "^" .. table.concat(parts) .. "$", order = order }
end

-- Captures of `text` against a built pattern, in argument order.
local function MatchSpec(text, spec)
	local captures = { text:match(spec.pattern) }
	if #captures == 0 then
		-- A format without arguments matches as a whole line.
		if #spec.order == 0 and text:find(spec.pattern) then return {} end
		return nil
	end
	local args = {}
	for index, argument in ipairs(spec.order) do args[argument] = captures[index] end
	return args
end

-- The arguments of `text` matched against a printf-style format string
-- (usually a game GlobalString), in argument order: args[1] is the format's
-- first argument even when a translation moves it ("%2$s ... %1$s"). nil
-- when the line doesn't match or can't be read. Each format is turned into
-- a pattern once; a format that changes simply builds a new one.
local formatSpecs = {}
function P:MatchFormat(text, format)
	text = self:Readable(text)
	if not text or type(format) ~= "string" or IsSecret(format) then return nil end
	local spec = formatSpecs[format]
	if spec == nil then
		spec = self:BuildPattern(format) or false
		formatSpecs[format] = spec
	end
	if not spec then return nil end
	return MatchSpec(text, spec)
end

---------------------------------------------------------------------------
-- Kinds: { global string name, field name of each argument in order,
-- fixed fields added to every match }. More specific strings first.
---------------------------------------------------------------------------
local XP_FIELDS = { "mob", "xp", "extra", "extraKind" }
local KINDS = {
	item = {
		{ "LOOT_ITEM_SELF_MULTIPLE", { "link", "count" } },
		{ "LOOT_ITEM_PUSHED_SELF_MULTIPLE", { "link", "count" } },
		{ "LOOT_ITEM_CREATED_SELF_MULTIPLE", { "link", "count" } },
		{ "LOOT_ITEM_SELF", { "link" } },
		{ "LOOT_ITEM_PUSHED_SELF", { "link" } },
		{ "LOOT_ITEM_CREATED_SELF", { "link" } },
	},
	money = {
		{ "YOU_LOOT_MONEY", { "money" } },
		{ "LOOT_MONEY_SPLIT", { "money" } },
		{ "YOU_LOOT_MONEY_GUILD", { "money", "guild" } },
		{ "LOOT_MONEY_SPLIT_GUILD", { "money", "guild" } },
	},
	rep = {
		{ "FACTION_STANDING_INCREASED_DOUBLE_BONUS", { "faction", "amount" } },
		{ "FACTION_STANDING_INCREASED_ACH_BONUS", { "faction", "amount" } },
		{ "FACTION_STANDING_INCREASED_BONUS", { "faction", "amount" } },
		{ "FACTION_STANDING_INCREASED", { "faction", "amount" } },
		{ "FACTION_STANDING_DECREASED", { "faction", "loss" } },
		{ "FACTION_STANDING_INCREASED_GENERIC", { "faction" } },
		{ "FACTION_STANDING_DECREASED_GENERIC", { "faction" } },
	},
	currency = {
		{ "CURRENCY_GAINED_MULTIPLE_BONUS", { "link", "count" } },
		{ "CURRENCY_GAINED_MULTIPLE", { "link", "count" } },
		{ "CURRENCY_GAINED", { "link" } },
	},
	skill = {
		{ "SKILL_RANK_UP", { "skill", "rank" } },
	},
	-- Experience from a kill (CHAT_MSG_COMBAT_XP_GAIN). Rested bonus and
	-- penalty lines first, then group and raid lines, then the plain ones.
	xpkill = {
		{ "COMBATLOG_XPGAIN_EXHAUSTION1_GROUP", { "mob", "xp", "extra", "extraKind", "group" } },
		{ "COMBATLOG_XPGAIN_EXHAUSTION1_RAID", { "mob", "xp", "extra", "extraKind", "raid" } },
		{ "COMBATLOG_XPGAIN_EXHAUSTION1", XP_FIELDS },
		{ "COMBATLOG_XPGAIN_EXHAUSTION2_GROUP", { "mob", "xp", "extra", "extraKind", "group" } },
		{ "COMBATLOG_XPGAIN_EXHAUSTION2_RAID", { "mob", "xp", "extra", "extraKind", "raid" } },
		{ "COMBATLOG_XPGAIN_EXHAUSTION2", XP_FIELDS },
		{ "COMBATLOG_XPGAIN_EXHAUSTION4_GROUP", { "mob", "xp", "extra", "extraKind", "group" } },
		{ "COMBATLOG_XPGAIN_EXHAUSTION4_RAID", { "mob", "xp", "extra", "extraKind", "raid" } },
		{ "COMBATLOG_XPGAIN_EXHAUSTION4", XP_FIELDS },
		{ "COMBATLOG_XPGAIN_EXHAUSTION5_GROUP", { "mob", "xp", "extra", "extraKind", "group" } },
		{ "COMBATLOG_XPGAIN_EXHAUSTION5_RAID", { "mob", "xp", "extra", "extraKind", "raid" } },
		{ "COMBATLOG_XPGAIN_EXHAUSTION5", XP_FIELDS },
		{ "COMBATLOG_XPGAIN_FIRSTPERSON_GROUP", { "mob", "xp", "group" } },
		{ "COMBATLOG_XPGAIN_FIRSTPERSON_RAID", { "mob", "xp", "raid" } },
		{ "COMBATLOG_XPGAIN_FIRSTPERSON", { "mob", "xp" } },
		{ "COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_GROUP", { "xp", "group" } },
		{ "COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_RAID", { "xp", "raid" } },
		{ "COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED", { "xp" } },
	},
	-- Honor (CHAT_MSG_COMBAT_HONOR_GAIN).
	honor = {
		{ "COMBATLOG_HONORGAIN", { "victim", "rank", "honor" } },
		{ "COMBATLOG_HONORGAIN_NO_RANK", { "victim", "honor" } },
		{ "COMBATLOG_HONORAWARD", { "honor" } },
		{ "COMBATLOG_DISHONORGAIN", { "victim" }, { dishonor = true } },
	},
	-- Instance resets (CHAT_MSG_SYSTEM).
	reset = {
		{ "INSTANCE_RESET_SUCCESS", { "instance" }, { result = "success" } },
		{ "INSTANCE_RESET_FAILED_ZONING", { "instance" }, { result = "zoning" } },
		{ "INSTANCE_RESET_FAILED_OFFLINE", { "instance" }, { result = "offline" } },
		{ "INSTANCE_RESET_FAILED", { "instance" }, { result = "failed" } },
	},
	-- The hourly instance cap (CHAT_MSG_SYSTEM, SYSMSG or UI_ERROR_MESSAGE).
	tooManyInstances = {
		{ "TRANSFER_ABORT_TOO_MANY_INSTANCES", {} },
	},
}
local KIND_ORDER = { "item", "money", "rep", "currency", "skill", "xpkill", "honor", "reset", "tooManyInstances" }

local built = {} -- kind -> list of specs, built on first use
local coins      -- { spec, copper per unit } for gold, silver, copper

local function BuildKind(kind)
	local list = {}
	for _, entry in ipairs(KINDS[kind] or {}) do
		local spec = P:BuildPattern(_G[entry[1]])
		if spec then
			spec.name = entry[1]
			spec.fields = entry[2]
			spec.fixed = entry[3]
			list[#list + 1] = spec
		end
	end
	built[kind] = list
	return list
end

local function Specs(kind)
	return built[kind] or BuildKind(kind)
end

-- Forget every built pattern (after the client's strings change, and for
-- tests that swap them).
function P:Rebuild()
	wipe(built)
	coins = nil
end

-- Add a kind (or more strings to one). list: { { "GLOBAL_STRING", { field, ... }, { fixed = value } }, ... }
function P:AddKind(kind, list)
	if type(kind) ~= "string" or type(list) ~= "table" then return end
	if not KINDS[kind] then
		KINDS[kind] = {}
		KIND_ORDER[#KIND_ORDER + 1] = kind
	end
	for _, entry in ipairs(list) do
		if type(entry) == "table" and type(entry[1]) == "string" then
			table.insert(KINDS[kind], { entry[1], entry[2] or {}, entry[3] })
		end
	end
	built[kind] = nil
end

function P:Kinds()
	local list = {}
	for index, kind in ipairs(KIND_ORDER) do list[index] = kind end
	return list
end

---------------------------------------------------------------------------
-- Parsing
---------------------------------------------------------------------------
-- The first string of a kind that matches the whole line: a table of named
-- fields, or nil. Secret or unreadable text returns nil.
function P:Parse(kind, text)
	text = self:Readable(text)
	if not text then return nil end
	for _, spec in ipairs(Specs(kind)) do
		local args = MatchSpec(text, spec)
		if args then
			local fields = {}
			for index, name in ipairs(spec.fields) do fields[name] = args[index] end
			if spec.fixed then
				for key, value in pairs(spec.fixed) do fields[key] = value end
			end
			return fields, spec.name
		end
	end
	return nil
end

-- Try several kinds (all of them when `kinds` is nil): kind, fields, string name.
function P:Match(text, kinds)
	text = self:Readable(text)
	if not text then return nil end
	for _, kind in ipairs(kinds or KIND_ORDER) do
		local fields, name = self:Parse(kind, text)
		if fields then return kind, fields, name end
	end
	return nil
end

-- Copper from a money text in the client's own coin words ("1 Gold,
-- 20 Silver"). nil when no coin word is found or the text is secret.
function P:Money(text)
	text = self:Readable(text)
	if not text then return nil end
	if not coins then
		coins = {
			{ self:BuildPattern(_G.GOLD_AMOUNT), 10000 },
			{ self:BuildPattern(_G.SILVER_AMOUNT), 100 },
			{ self:BuildPattern(_G.COPPER_AMOUNT), 1 },
		}
	end
	local total, found = 0, false
	for _, coin in ipairs(coins) do
		local spec = coin[1]
		if spec then
			-- The coin words sit anywhere in the line: search without anchors.
			local inner = spec.pattern:sub(2, -2)
			for amount in text:gmatch(inner) do
				local value = tonumber(amount)
				if value then
					total = total + value * coin[2]
					found = true
				end
			end
		end
	end
	return found and total or nil
end

---------------------------------------------------------------------------
-- Skill-ups while chat is held back
---------------------------------------------------------------------------
-- In dungeons and raids the game hides its "Your skill in ... has
-- increased" line from addons. The skills list itself stays readable, so
-- a rank that went up there stands in for the line, only while lines are
-- held back (the line itself reports it otherwise, never both).
--   local risen = P:RisenSkills("loot")   -- { { name = "Swords", rank = 61 } }
-- Each caller keeps its own last look; the first call only takes one.
local skillLooks = {}

local function SkillRanks()
	local info = C_SkillInfo
	if not (info and info.GetNumSkillLines and info.GetSkillLineInfo) then return nil end
	local ok, count = pcall(info.GetNumSkillLines)
	if not ok or IsSecret(count) or type(count) ~= "number" then return nil end
	local ranks = {}
	for index = 1, count do
		local fine, line = pcall(info.GetSkillLineInfo, index)
		if fine and type(line) == "table" and not line.isHeader then
			local name, rank = line.name, line.rank
			if not IsSecret(name) and type(name) == "string" and name ~= "" and not IsSecret(rank) and type(rank) == "number" then
				ranks[name] = rank
			end
		end
	end
	return ranks
end

function P:RisenSkills(owner)
	local now = SkillRanks()
	if not now then return {} end
	local before = skillLooks[owner]
	skillLooks[owner] = now
	local risen = {}
	if not before or not (E.CommRestricted and E:CommRestricted()) then return risen end
	for name, rank in pairs(now) do
		if before[name] and rank > before[name] then risen[#risen + 1] = { name = name, rank = rank } end
	end
	table.sort(risen, function(a, b) return a.name < b.name end)
	return risen
end
