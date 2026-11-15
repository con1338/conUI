-- Offline test for DKP and EPGP standings from the guild notes (review
-- verbesserungen.md, B3).
-- Run from the repository root:
--   lua5.1 tools/raidloot/test_points.lua
-- It loads EldoUI/Modules/RaidLoot/Points.lua as it is and cuts the name
-- lines of EldoUI/Modules/RaidLoot/Core.lua out of the file (between fixed
-- markers, so a renamed part makes the test fail instead of testing a stale
-- copy). Around them: a guild roster, units and the Info Bar.
-- Checked: which notes count as EPGP or DKP in each mode, the priority with
-- the guild's base GP, alts by EPGP's rule, which note is read, the officer
-- note only when the game shows it; the roster read, redraws only on a
-- change; standings after the names on the SR and TMB lines but never in
-- the chat post; the tooltip line for guild members only; the Info Bar
-- block; the options before "Posting".
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/raidloot/") or "./"

local function ReadFile(path)
	local file = assert(io.open(ROOT .. path, "rb"), "can't open " .. path)
	local text = file:read("*a")
	file:close()
	return (text:gsub("\r\n", "\n"))
end

-- The text from `first` up to (not including) `last`.
local function Between(text, first, last, where)
	local from = text:find(first, 1, true)
	assert(from, where .. ": marker not found: " .. first)
	local to = text:find(last, from + #first, true)
	assert(to, where .. ": end marker not found after " .. first .. ": " .. last)
	return text:sub(from, to - 1)
end

local core = ReadFile("EldoUI/Modules/RaidLoot/Core.lua")
local coreChunk = assert(loadstring(table.concat({
	"local E, M, L = ...",
	"local Clean = E.Plain",
	Between(core, "local function Me()", "-- Posting: one click, one line", "RaidLoot/Core.lua"),
}, "\n"), "=RaidLoot/Core.lua parts"))
local pointsChunk = assert(loadstring(ReadFile("EldoUI/Modules/RaidLoot/Points.lua"), "=Points.lua"))

---------------------------------------------------------------------------
-- The game and EldoUI around it
---------------------------------------------------------------------------
local SECRET = { secret = true }
local function Secret(value) return type(value) == "table" and value.secret == true end
local world

IsInGuild = function() return world.inGuild end
IsInGroup = function() return world.group ~= nil end
IsInRaid = function() return false end
GetNumGuildMembers = function() return #world.roster end
GetGuildRosterInfo = function(index)
	local row = world.roster[index]
	if not row then return nil end
	return row.name, "Member", 3, 60, "Mage", "Orgrimmar", row.publicNote, row.officerNote
end
CanViewOfficerNote = function() return world.officer end
-- WoW: Forever blocks these guild functions in combat; any call there is
-- counted and fails the combat checks.
local function Guarded(fn)
	return function(...)
		if world.combat then world.combatCalls = world.combatCalls + 1 end
		return fn(...)
	end
end
GetGuildInfoText = Guarded(function() return world.info end)
GetNumGuildMembers = Guarded(GetNumGuildMembers)
GetGuildRosterInfo = Guarded(GetGuildRosterInfo)
C_GuildInfo = { GuildRoster = Guarded(function() world.rosterRequests = world.rosterRequests + 1 end) }
InCombatLockdown = function() return world.combat == true end
UnitName = function(unit)
	if unit == "player" then return "Mira" end
	local name = world.units[unit] and world.units[unit].name
	if name then return name end
	local index = unit:match("^party(%d)$")
	return index and world.group and world.group[tonumber(index)] or nil
end
UnitIsPlayer = function(unit) return world.units[unit] and world.units[unit].player or false end
UnitIsInMyGuild = function(unit) return world.units[unit] and world.units[unit].guild or false end
C_Item = {}

local function NewTooltip()
	local tooltip = { lines = {} }
	function tooltip:AddLine(text) table.insert(self.lines, text) end
	return tooltip
end

local ROSTER = {
	{ name = "Mira-Realm", officerNote = "1250,830", publicNote = "Healer" },
	{ name = "Joe-Realm", officerNote = "", publicNote = "Net:350 Tot:1200 Hrs:42" },
	{ name = "Bob-Realm", officerNote = "Mira", publicNote = "" },
	{ name = "Ann-Realm", officerNote = "0,0" },
	{ name = "Lee-Realm", officerNote = "Tank" },
}

local function Setup(options)
	options = options or {}
	world = { inGuild = options.inGuild ~= false, officer = options.officer ~= false, info = options.info or "",
		roster = options.roster or ROSTER, rosterRequests = 0, events = {}, units = {}, group = options.group,
		changed = 0, refreshed = 0, combat = options.combat, combatCalls = 0 }
	local L = setmetatable({}, { __index = function(_, key) return key end })
	local dataTexts, sections = {}, {}
	local E = { L = L, Secret = Secret, media = { accentText = { 1, 0.8, 0 } },
		tokens = { text = { secondary = { 0.6, 0.6, 0.6 }, body = { 1, 1, 1 } } },
		UIKit = { TipPair = function(tooltip, left, right) tooltip:AddLine(left .. ": " .. right) end },
		modules = { InfoBar = { RefreshDataText = function(_, key) if key == "GuildPoints" then world.refreshed = world.refreshed + 1 end end } } }
	function E.Plain(value) if Secret(value) then return nil end return value end
	function E:PlayerName() return "Mira" end
	function E:TextHex() return "|cff999999" end
	function E:TokenHex() return "|cffffcc00" end
	function E:RegisterEvent(event, fn, owner) world.events[event] = { fn = fn, owner = owner } end
	function E:UnregisterEvent(event, owner) if world.events[event] and world.events[event].owner == owner then world.events[event] = nil end end
	function E:RegisterDataText(name, definition) dataTexts[name] = definition end
	function E:RegisterTooltipSection(key, definition) sections[key] = definition end
	local M = {
		active = true,
		defaults = {},
		db = { points = options.points or "auto", pointsNote = options.note or "officer", pointsInLines = options.inLines ~= false,
			showSR = true, showTMB = true, maxNames = 5, highlightMe = false, onlyGroup = false },
		options = {
			{ type = "header", label = "Where they show" },
			{ type = "header", label = "Posting" },
			{ type = "toggle", key = "allowPosting" },
		},
	}
	function M:Changed() world.changed = world.changed + 1 end
	function M:Data()
		return { sr = { items = { [123] = { { name = "Mira", plus = 2 }, { name = "Joe" } } } },
			tmb = { items = { [123] = { { name = "Bob", prio = 1 } } } } }
	end
	E.RaidLoot = M
	coreChunk(E, M, L)
	pointsChunk(nil, E)
	return { E = E, M = M, P = M.Points, dataTexts = dataTexts, sections = sections }
end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
local passed, failed = 0, 0
local function Check(ok, what)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. what) end
end

-- Which notes hold what.
do
	local P = Setup().P
	local function Is(note, format, kind, a, b)
		local got = P.Parse(note, format)
		local ok
		if kind == nil then
			ok = got == nil
		elseif kind == "epgp" then
			ok = got and got.kind == "epgp" and got.ep == a and got.gp == b
		else
			ok = got and got.kind == "dkp" and got.dkp == a
		end
		Check(ok, ("Parse(%q, %s) -> %s %s %s"):format(tostring(note), format, tostring(kind), tostring(a), tostring(b)))
	end
	Is("1250,830", "auto", "epgp", 1250, 830)
	Is(" 1250 , 830 ", "auto", "epgp", 1250, 830)
	Is("-50,100", "auto", "epgp", -50, 100)
	Is("1250,830", "epgp", "epgp", 1250, 830)
	Is("1250,830", "dkp", nil)
	Is("Net:350 Tot:1200 Hrs:42", "auto", "dkp", 350)
	Is("DKP: 350", "auto", "dkp", 350)
	Is("dkp=12.5", "auto", "dkp", 12.5)
	Is("350 DKP", "auto", "dkp", 350)
	Is("Net:350", "epgp", nil)
	Is("350", "auto", nil)
	Is("350", "epgp", nil)
	Is("350", "dkp", "dkp", 350)
	Is("Healer, 60 hunter", "dkp", nil)
	Is("Alt of Bob", "auto", nil)
	Is("", "auto", nil)
	Is(nil, "auto", nil)
	Is(SECRET, "auto", nil)
	Is("1250,830", "off", nil)
	Check(P.BaseGP("-EPGP-\n@BASE_GP:1000\n@MIN_EP:0") == 1000, "base GP from the guild information")
	Check(P.BaseGP("Raid Tuesday") == 0 and P.BaseGP(nil) == 0 and P.BaseGP(SECRET) == 0, "no base GP: 0")
	Check(P.Key("Mira-Realm") == "mira" and P.Key("Mira") == "mira" and P.Key("") == nil and P.Key(SECRET) == nil, "keys")
end

-- A roster's standings.
do
	local P = Setup().P
	local cache = P.Build(ROSTER, "auto", "officer", 0)
	Check(cache.mira and cache.mira.kind == "epgp" and math.abs(cache.mira.pr - 1250 / 830) < 1e-9 and cache.mira.name == "Mira",
		"officer note: EPGP with its priority")
	Check(cache.joe == nil, "officer note only: the public note is not read")
	Check(cache.bob and cache.bob.main == "Mira" and cache.bob.pr == cache.mira.pr and cache.bob.name == "Bob", "an alt shows its main's standing")
	Check(cache.ann and cache.ann.pr == nil, "GP 0: no priority")
	Check(cache.lee == nil, "a one-word note that is no member's name: nothing")
	local based = P.Build(ROSTER, "auto", "officer", 170)
	Check(math.abs(based.mira.pr - 1.25) < 1e-9, "the base GP counts in the priority")
	local both = P.Build(ROSTER, "auto", "both", 0)
	Check(both.joe and both.joe.dkp == 350 and both.mira.kind == "epgp", "both notes: officer note first, then the public one")
	local public = P.Build(ROSTER, "auto", "public", 0)
	Check(public.mira == nil and public.joe and public.joe.dkp == 350, "public note only")
	Check(next(P.Build(ROSTER, "off", "officer", 0)) == nil, "off: nothing")
	Check(P.Short(cache.mira) == "PR 1.51" and P.Detail(cache.mira) == "1250 / 830, PR 1.51", "EPGP texts")
	Check(P.Detail(cache.bob) == "1250 / 830, PR 1.51 (from Mira)", "an alt's text names the main")
	Check(P.Short(cache.ann) == "0 / 0", "no priority: EP / GP")
	Check(P.Short(both.joe) == "350 DKP" and P.Detail(both.joe) == "350", "DKP texts")
	Check(P.Short({ kind = "dkp", dkp = 12.5 }) == "12.5 DKP", "DKP with a fraction")
	Check(P.Label(cache.mira) == "EPGP" and P.Label(both.joe) == "DKP", "labels")
end

-- Reading the roster, redraws, switching off.
do
	local test = Setup()
	local M = test.M
	M:EnablePoints()
	Check(world.events.GUILD_ROSTER_UPDATE and world.events.PLAYER_GUILD_UPDATE, "the roster events are registered")
	Check(world.rosterRequests == 1, "the game is asked for the roster")
	Check(M.PointsEntry("Mira") and M.PointsEntry("Mira-OtherRealm"), "a member is found by name, with or without realm")
	Check(world.changed == 1 and world.refreshed == 1, "the first read redraws the lines and the block")
	world.events.GUILD_ROSTER_UPDATE.fn()
	Check(world.changed == 1, "the same roster again: no redraw")
	world.roster = { { name = "Mira-Realm", officerNote = "1300,830" } }
	world.events.GUILD_ROSTER_UPDATE.fn()
	Check(world.changed == 2 and M.PointsEntry("Mira").ep == 1300, "a changed note: read again and redrawn")
	M:DisablePoints()
	Check(world.events.GUILD_ROSTER_UPDATE == nil and M.PointsEntry("Mira") == nil, "off: events and standings gone")

	test = Setup({ officer = false })
	test.M:EnablePoints()
	Check(test.M.PointsEntry("Mira") == nil, "officer notes the game hides are not read")
	test = Setup({ inGuild = false })
	test.M:EnablePoints()
	Check(next(test.M.points) == nil and world.rosterRequests == 0, "no guild: nothing read, nothing asked")
	test = Setup({ info = "@BASE_GP:170" })
	test.M:EnablePoints()
	Check(math.abs(test.M.PointsEntry("Mira").pr - 1.25) < 1e-9, "the roster read uses the guild's base GP")
	test = Setup({ points = "off" })
	test.M:EnablePoints()
	Check(next(test.M.points) == nil, "Read standings off: nothing")
end

-- In combat: no guild function is called; the read waits for the fight's
-- end (in the game GetGuildInfoText was blocked there, B3).
do
	local test = Setup()
	local M = test.M
	M:EnablePoints()
	Check(world.events.PLAYER_REGEN_ENABLED and world.events.PLAYER_REGEN_ENABLED.owner == "RaidLootPoints",
		"the end of combat is listened to")
	world.combat = true
	world.roster = { { name = "Mira-Realm", officerNote = "1300,830" } }
	world.events.GUILD_ROSTER_UPDATE.fn()
	world.events.PLAYER_GUILD_UPDATE.fn()
	Check(world.combatCalls == 0, "a roster update in combat calls no guild function (got " .. world.combatCalls .. ")")
	Check(M.PointsEntry("Mira").ep == 1250 and world.changed == 1, "in combat the old standings stay, nothing is redrawn")
	world.combat = false
	local requests = world.rosterRequests
	world.events.PLAYER_REGEN_ENABLED.fn()
	Check(M.PointsEntry("Mira").ep == 1300 and world.changed == 2, "after the fight the roster is read and redrawn")
	Check(world.rosterRequests == requests + 1, "after the fight the game is asked for the roster again")
	world.events.PLAYER_REGEN_ENABLED.fn()
	Check(world.rosterRequests == requests + 1 and world.changed == 2, "a fight without a roster update: nothing to do afterwards")

	-- The module comes on in combat (a reload in a fight).
	test = Setup({ combat = true })
	M = test.M
	M:EnablePoints()
	Check(world.combatCalls == 0 and world.rosterRequests == 0 and next(M.points) == nil,
		"on in combat: nothing asked, nothing read")
	world.combat = false
	world.events.PLAYER_REGEN_ENABLED.fn()
	Check(world.rosterRequests == 1 and M.PointsEntry("Mira") and M.PointsEntry("Mira").ep == 1250,
		"on in combat: asked and read after the fight")

	-- Switched off with a read waiting.
	test = Setup()
	M = test.M
	M:EnablePoints()
	world.combat = true
	world.events.GUILD_ROSTER_UPDATE.fn()
	M:DisablePoints()
	Check(world.events.PLAYER_REGEN_ENABLED == nil and not M.pointsPending, "off: the wait for the fight's end is gone")
end

-- The SR and TMB lines; the chat post.
do
	local test = Setup()
	local M = test.M
	M:EnablePoints()
	local lines = M:Lines(123)
	Check(lines[1][1] == "SR" and lines[1][2] == "Mira (+2) |cff999999[PR 1.51]|r, Joe", "SR line: standing after the name (got " .. tostring(lines[1][2]) .. ")")
	Check(lines[2][2] == "Bob (prio 1) |cff999999[PR 1.51]|r", "TMB line: an alt's standing (got " .. tostring(lines[2][2]) .. ")")
	local post = M:PostText(123, "[Item]")
	Check(post and not post:find("PR", 1, true) and post:find("Mira (+2)", 1, true), "the chat post never carries standings")
	M.db.pointsInLines = false
	Check(M:Lines(123)[1][2] == "Mira (+2), Joe", "\"After the names\" off: plain names")
	M.db.pointsInLines = true
	M.active = false
	Check(M:Lines(123)[1][2] == "Mira (+2), Joe", "module off: plain names")
end

-- A guild member's tooltip.
do
	local test = Setup()
	test.M:EnablePoints()
	test.M:InitPoints()
	local section = test.sections.guildPoints
	Check(section and section.unit and section.module == "RaidLoot", "the tooltip section is registered for units")
	local rows = {}
	local function add(left, right) rows[#rows + 1] = { left, right } end
	world.units.target = { name = "Mira", player = true, guild = true }
	world.units.focus = { name = "Mira", player = true, guild = false }
	world.units.mouseover = { name = "Mira", player = false, guild = false }
	section.unit(nil, "target", add)
	Check(#rows == 1 and rows[1][1] == "EPGP" and rows[1][2] == "1250 / 830, PR 1.51", "guild member: EPGP row")
	section.unit(nil, "focus", add)
	section.unit(nil, "mouseover", add)
	section.unit(nil, SECRET, add)
	Check(#rows == 1, "someone else of that name, an NPC or a hidden unit: no row")
end

-- The Info Bar block.
do
	local test = Setup({ group = { "Joe", "Bob" } })
	local block = test.dataTexts.GuildPoints
	Check(block and block.title == "Guild points", "the Info Bar block is registered")
	test.M:EnablePoints()
	Check(block.text() == "PR 1.51", "the block shows your standing")
	local tooltip = NewTooltip()
	block.tooltip(tooltip)
	local text = table.concat(tooltip.lines, "\n")
	Check(text:find("EPGP: 1250 / 830, PR 1.51", 1, true) and text:find("Your group", 1, true), "tooltip: yours and your group")
	Check(text:find("Bob: 1250 / 830, PR 1.51 (from Mira)", 1, true) and text:find("Mira: ", 1, true), "tooltip: group members with standings")
	Check(not text:find("Ann", 1, true), "tooltip: no one outside the group")
	world.group = nil
	tooltip = NewTooltip()
	block.tooltip(tooltip)
	text = table.concat(tooltip.lines, "\n")
	Check(text:find("Guild", 1, true) and text:find("Ann: 0 / 0", 1, true), "no group: the guild's standings")
	local order = text:find("Mira: ", 1, true) < text:find("Ann: ", 1, true)
	Check(order, "highest first")
	test = Setup({ inGuild = false })
	tooltip = NewTooltip()
	test.dataTexts.GuildPoints.tooltip(tooltip)
	Check(tooltip.lines[1] == "You are not in a guild.", "no guild: says so")
	test = Setup({ roster = { { name = "Mira-Realm", officerNote = "Healer" } } })
	test.M:EnablePoints()
	Check(test.dataTexts.GuildPoints.text() == "|cff999999-|r", "no standing: a gray dash")
	tooltip = NewTooltip()
	test.dataTexts.GuildPoints.tooltip(tooltip)
	Check(tooltip.lines[#tooltip.lines] == "No DKP or EPGP standings in the guild notes.", "no standings: says so")
	test.M.db.points = "off"
	Check(test.dataTexts.GuildPoints.text() == "|cff999999Off|r", "off: the block says Off")
end

-- The options sit before "Posting".
do
	local test = Setup()
	local labels = {}
	for _, option in ipairs(test.M.options) do labels[#labels + 1] = option.label or option.key end
	local joined = table.concat(labels, "|")
	Check(joined:find("Guild points|Read standings|From the note|After the names|Posting", 1, true) ~= nil,
		"options: Guild points before Posting (got " .. joined .. ")")
	Check(test.M.defaults.points == "auto" and test.M.defaults.pointsNote == "officer" and test.M.defaults.pointsInLines == true, "defaults")
end

print(("%d checks passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
