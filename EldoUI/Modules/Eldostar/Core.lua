-- EldoUI Eldostar: EldoUI's own leveling guide. The engine: the guide
-- data, the guide in use and its progress, goal tracking, conditions and
-- the waypoint. The window is Window.lua, the guide list in the Journal
-- is Picker.lua, the options page Options.lua.
--
-- Where things come from
--   * The guides are community guides, kept upstream with their credits.
--     They ship in their own load-on-demand folder, EldoUI_GuideData,
--     which assigns one table, EldoUI_GuideData = { schema, source,
--     guides }. It is loaded only while Eldostar is the guide provider
--     (Modules/Integrations.lua, E:GuideProvider), out of combat. Only
--     the addon load runs anything: the table is read as data, field by
--     field, with rawget; a table with a metatable, a value of the wrong
--     type, an id that is not a whole number or a coordinate outside 0 to
--     100 is dropped. Guide text is shown as written, with no color,
--     texture or link codes.
--   * Quest givers, enders and spawns come from the Loot Guide's own data
--     (LG:Quest, LG:SpawnPoints, LG:PointFor); a goal's own map and
--     coordinates come first.
--   * Progress reads only what the game tells: the quest log and its
--     events, bag counts, level, money, reputation, profession skill and
--     known spells. What the client cannot report is a goal the player
--     ticks. Nothing here accepts, turns in, buys, talks or targets.
--
-- Progress is kept per character, by the guide's stable id: the step,
-- the steps skipped, the goals ticked and an undo history, with the
-- guide's version. A new guide version keeps the player near the same
-- step (by its label, then its title, then its number) and says so.
--
-- Conditions (the guide data's schema, tools/guidedata/README.md)
--   only    { classes, exceptClasses, races, factions } on a guide, step or
--           goal: a step or goal for another character is passed over
--   when    a list of predicates that must all hold: level, onquest,
--           complete, turnedin, available, has, zone, subzone, bound, each
--           but level with `negate`. A false one passes the step over; one
--           the client cannot answer counts as true, and the step can still
--           be skipped.
--   along   a step done on the way: its goals show under the next stops
--           (up to the step its alongUntil names) and never hold them up
--   loop    the step's goto points are where to search for its goals; the
--           waypoint goes round them
--   label, skipto  a step's name, and the step a finished step jumps to
--   nextOptions    the guide after this one: the first that fits
--
-- Off (another provider, or none): no data loaded, no events, no ticker,
-- no waypoint, no frame shown. Every side effect has one teardown, Stop.
local _, E = ...
local L = E.L
local Key = E.Key

local Plain = E.Plain
local PlainCall = E.PlainCall

local ADDON = "EldoUI_GuideData"
local SCHEMA = 1
local MOVER = "EldoUI_Eldostar"
local MAX_TEXT = 1000
local HISTORY_MAX = 30
local MAX_ID = 2147483647

local M = E:NewModule("Eldostar", {
	title = "Eldostar",
	desc = "EldoUI's own leveling guide: community guides step by step in an EldoUI window on the layout's guide spot, with goals that tick from your quest log, bags and level, and one waypoint to the next goal.",
	category = "Quality of Life",
	frames = { MOVER },
	movers = { MOVER },
	blizzard = {},
	savedKeys = { "profile.modules.Eldostar", "private.eldostar" },
	optionsPage = "module:Eldostar",
	presets = { "Compact", "Glass", "Minimal", "Roomy", "Standard" },
	reload = false,
	themed = "ApplyLook",
	defaults = {
		provider = "auto",      -- auto, eldostar, rxp, guidelime, off (read by E:GuideProvider)
		view = "standard",      -- standard or compact
		fontSize = 13,
		showTip = true,         -- the step's tip under its title
		showAlong = true,       -- goals along the way
		autoAdvance = true,     -- a finished step moves on to the next one
		waypoint = true,        -- the arrow points at the current goal (Waypoints module)
		transparent = false,
		-- The shared visibility rules; in instances the guide window hides.
		visibility = E:VisibilityDefaults({ instance = "hide" }),
		locked = false,         -- the window keeps its place and size
		window = {},            -- w, h of the standard view (the resize grip)
	},
})
E.Eldostar = M
E:RegisterVisibilityFacet(MOVER, "rules", { module = "Eldostar", setting = "visibility" })
M.ADDON, M.SCHEMA, M.MOVER = ADDON, SCHEMA, MOVER

-- Per character: the guide in use, progress per guide, the window closed.
E:RegisterPrivate("eldostar", { progress = {} })

local function Store()
	local store = E:GetPrivate("eldostar")
	if type(store) ~= "table" then return { progress = {} } end
	if type(store.progress) ~= "table" then store.progress = {} end
	return store
end
M.Store = Store

---------------------------------------------------------------------------
-- Reading the data: plain values only
---------------------------------------------------------------------------
local KINDS = {}
for _, kind in ipairs({ "accept", "turnin", "complete", "abandon", "goto", "explore", "sethome", "hearth", "getfp",
	"fly", "enter", "talk", "train", "vendor", "buy", "collect", "interact", "use", "kill", "level", "money",
	"skill", "learn", "craft", "rep", "cast", "destroy", "task", "note" }) do
	KINDS[kind] = true
end
M.KINDS = KINDS

-- Standings and profession ranks as the guides write them.
local STANDINGS = { Hated = 1, Hostile = 2, Unfriendly = 3, Neutral = 4, Friendly = 5, Honored = 6, Revered = 7, Exalted = 8 }
local RANK_CAPS = { Apprentice = 75, Journeyman = 150, Expert = 225, Artisan = 300 }
local QUALITIES = { poor = true, common = true, uncommon = true, rare = true, epic = true, legendary = true,
	artifact = true, heirloom = true }
local OPS = { ["<"] = true, ["<="] = true, [">"] = true, [">="] = true }
M.STANDINGS, M.RANK_CAPS = STANDINGS, RANK_CAPS

-- What the last read left out: guides, steps and goals, and each field it
-- could not read, by "level.field" (an unknown field, or a value of the
-- wrong type or range). The options page and the data checks read it.
local issues
local function NewIssues() return { guides = 0, steps = 0, goals = 0, fields = {} } end
issues = NewIssues()
local function Issue(where)
	issues.fields[where] = (issues.fields[where] or 0) + 1
end
function M.ReadIssues() return issues end

local function Table(value)
	if type(value) ~= "table" or getmetatable(value) ~= nil then return nil end
	return value
end

local function Text(value, max)
	if type(value) ~= "string" or value == "" then return nil end
	max = max or MAX_TEXT
	if #value > max then value = E:Utf8Clip(value, max) end
	-- Shown as written: the data writes a "|" doubled; a single one never
	-- starts a color, texture or link code either.
	return (value:gsub("||", "|"):gsub("|", "||"))
end

local function Id(value)
	if type(value) ~= "number" or value ~= value or value < 1 or value > MAX_ID or value % 1 ~= 0 then return nil end
	return value
end

local function Count(value, max)
	if type(value) ~= "number" or value ~= value or value < 0 or value > (max or MAX_ID) then return nil end
	return math.floor(value)
end

local function Number(value, low, high)
	if type(value) ~= "number" or value ~= value or value < low or value > high then return nil end
	return value
end

local function Coord(value) return Number(value, 0, 100) end

local function Bool(value)
	if value == true then return true end
end

-- "Night Elf", "NightElf" and "NIGHTELF" are one name; "Scourge" is the
-- game's own name for Undead.
local function NameKey(text)
	if type(text) ~= "string" then return nil end
	local key = text:upper():gsub("[^%a]", "")
	if key == "SCOURGE" then key = "UNDEAD" end
	return key ~= "" and key or nil
end
M.NameKey = NameKey

local function NameSet(value)
	value = Table(value)
	if not value or #value == 0 then return nil end
	local set = {}
	for index = 1, #value do
		local key = NameKey(rawget(value, index))
		if not key then return nil end
		set[key] = true
	end
	return set
end

local function List(reader)
	return function(value)
		value = Table(value)
		if not value or #value == 0 then return nil end
		local out = {}
		for index = 1, #value do
			local item = reader(rawget(value, index))
			if item == nil then return nil end
			out[index] = item
		end
		return out
	end
end

local function Faction(value)
	if value == "Alliance" or value == "Horde" then return value end
end

local function GuideId(value)
	if type(value) ~= "string" or #value > 200 or not value:find("^[%w][%w%-_/%.]*$") then return nil end
	return value
end

local function Max(max) return function(value) return Text(value, max) end end
local function Up(max) return function(value) return Count(value, max) end end
local function From(low, high) return function(value) return Number(value, low, high) end end
local function OneOf(set) return function(value) if type(value) == "string" and set[value] then return value end end end

-- Copies the fields a spec knows from raw into out. A spec entry of true
-- is read by the caller. Every other field, and every value its reader
-- turns down, is counted as an issue under level.
local function ReadFields(raw, spec, level, out)
	for key, value in pairs(raw) do
		local read = type(key) == "string" and spec[key]
		if read and read ~= true then
			local got = read(value)
			if got == nil then Issue(level .. "." .. key) else out[key] = got end
		elseif not read then
			Issue(level .. "." .. tostring(key))
		end
	end
	return out
end

local function Spec(level, spec)
	return function(value)
		value = Table(value)
		if not value then return nil end
		return ReadFields(value, spec, level, {})
	end
end

-- `only`: classes, races and factions each OR together, the groups AND;
-- exceptClasses names the classes left out.
local ReadOnly = Spec("only", {
	classes = NameSet, exceptClasses = NameSet, races = NameSet, factions = NameSet,
})

-- `when`: a list of predicates that must all hold.
local WHEN_TESTS = {
	level = { op = OneOf(OPS), level = From(1, 100), levelXp = Up(10000000) },
	onquest = { quests = List(Id), negate = Bool },
	complete = { quest = Id, negate = Bool },
	turnedin = { quest = Id, negate = Bool },
	available = { quest = Id, negate = Bool },
	has = { item = Id, count = Up(100000), negate = Bool },
	zone = { name = Max(120), negate = Bool },
	subzone = { name = Max(120), negate = Bool },
	bound = { name = Max(120), negate = Bool },
}
-- The field each test cannot do without.
local WHEN_NEEDS = { level = "level", onquest = "quests", complete = "quest", turnedin = "quest", available = "quest",
	has = "item", zone = "name", subzone = "name", bound = "name" }

local function ReadPredicate(raw)
	raw = Table(raw)
	if not raw then return nil end
	local test = rawget(raw, "test")
	local fields = type(test) == "string" and WHEN_TESTS[test]
	-- A test the engine does not know is one it cannot answer: the step
	-- still shows and can be skipped.
	if not fields then
		Issue("when." .. tostring(test))
		return { unknown = true }
	end
	local spec = { test = true }
	for key, read in pairs(fields) do spec[key] = read end
	local pred = ReadFields(raw, spec, "when", { test = test })
	if pred[WHEN_NEEDS[test]] == nil or (test == "level" and not pred.op) then return { unknown = true } end
	return pred
end
local ReadWhen = List(ReadPredicate)

-- Rewards: { item, name, quality, choice }, { spell, name } or { text }.
local ReadReward = Spec("reward", {
	item = Id, spell = Id, name = Max(200), quality = OneOf(QUALITIES), choice = Bool, text = Max(200),
})
local function Reward(value)
	local reward = ReadReward(value)
	if reward and (reward.item or reward.spell or reward.text) then return reward end
end

local function Group(value)
	if value == true then return true end
	return Number(value, 2, 40) and math.floor(value) or nil
end

local GOAL = {
	kind = true, optional = Bool, only = ReadOnly, group = Group, note = Max(MAX_TEXT), text = Max(MAX_TEXT),
	map = Id, x = Coord, y = Coord, frame = OneOf({ live = true, era = true }), radius = From(0.1, 500),
	quest = Id, npc = Id, object = Id, item = Id, spell = Id, factionId = Id,
	title = Max(200), name = Max(200), label = Max(200), place = Max(200), factionName = Max(200),
	profession = Max(60), rank = OneOf(RANK_CAPS), standing = OneOf(STANDINGS),
	count = Up(100000), objective = Up(50), value = Up(1000), untilSkill = Up(1000),
	level = From(1, 100), levelXp = Up(10000000), minLevel = Up(100),
	xp = Up(10000000), money = Up(10000000000), direct = Bool, nearest = Bool, classTrainer = Bool,
	choose = List(Reward), rewards = List(Reward),
}

local function ReadGoal(raw)
	raw = Table(raw)
	local kind = raw and rawget(raw, "kind")
	if type(kind) ~= "string" or not KINDS[kind] then return nil end
	local goal = ReadFields(raw, GOAL, "goal", { kind = kind })
	-- A place needs all three; one without them is still shown.
	if not (goal.map and goal.x and goal.y) then
		if goal.map or goal.x or goal.y then Issue("goal.map") end
		goal.map, goal.x, goal.y, goal.frame = nil, nil, nil, nil
	end
	if goal.count == 0 then goal.count = nil end
	return goal
end

local function ReadGoals(raw)
	raw = Table(raw)
	local goals = {}
	if not raw then return goals, 0 end
	local dropped = 0
	for index = 1, #raw do
		local goal = ReadGoal(rawget(raw, index))
		if goal then
			goal.index = index
			goals[#goals + 1] = goal
		else
			dropped = dropped + 1
		end
	end
	issues.goals = issues.goals + dropped
	return goals, dropped
end

local STEP = {
	title = Max(200), tip = Max(MAX_TEXT * 2), label = Max(120), skipto = Max(120), alongUntil = Max(120),
	zone = Id, only = ReadOnly, when = ReadWhen, along = Bool, loop = Bool, goals = true,
}

local function ReadStep(raw, number)
	raw = Table(raw)
	if not raw then return nil end
	local step = ReadFields(raw, STEP, "step", {})
	step.goals, step.dropped = ReadGoals(rawget(raw, "goals"))
	step.title = step.title or L["Step %d"]:format(number)
	return step
end

local NextOption = Spec("nextOption", { id = GuideId, when = ReadWhen })

local GUIDE = {
	id = true, steps = true, faction = Faction, races = NameSet, classes = NameSet, levels = true,
	title = Max(120), category = Max(60), folder = Max(120), author = Max(120), why = Max(MAX_TEXT), pitch = Max(MAX_TEXT),
	zone = Id, next = GuideId, version = Id, keywords = List(Max(60)), collects = List(Id), rewards = List(Reward),
	pros = List(Max(MAX_TEXT)), cons = List(Max(MAX_TEXT)), nextOptions = List(NextOption),
}

local function ReadGuide(raw)
	raw = Table(raw)
	if not raw then return nil end
	local id = GuideId(rawget(raw, "id"))
	local steps = Table(rawget(raw, "steps"))
	if not (id and steps and #steps > 0) then return nil end
	local guide = ReadFields(raw, GUIDE, "guide", { id = id, rawSteps = steps, count = #steps })
	guide.title = guide.title or id
	guide.category = guide.category or "Leveling"
	guide.version = guide.version or 1
	guide.only = {
		factions = guide.faction and { [NameKey(guide.faction)] = true } or nil,
		races = guide.races, classes = guide.classes,
	}
	local levels = Table(rawget(raw, "levels"))
	local low, high = levels and Count(rawget(levels, 1), 100), levels and Count(rawget(levels, 2), 100)
	if low and high and low <= high then
		guide.levels = { low, high }
	elseif levels ~= nil then
		Issue("guide.levels")
	end
	-- The words the guide list searches.
	local words = { guide.title, guide.category }
	if guide.folder then words[#words + 1] = guide.folder end
	if guide.author then words[#words + 1] = guide.author end
	for _, word in ipairs(guide.keywords or {}) do words[#words + 1] = word end
	guide.search = table.concat(words, " ")
	return guide
end

-- The steps of a guide, read once on first use. A guide whose steps
-- cannot be read at all is marked broken and never started.
--
-- An `along` step is no stop on the route: its goals are done on the way
-- and show under each stop from the next one up to the step its
-- alongUntil names (without one, the next stop only).
function M:Steps(guide)
	if not guide then return nil end
	if guide.steps then return guide.steps end
	local steps, labels, dropped = {}, {}, 0
	for index = 1, guide.count do
		local step = ReadStep(rawget(guide.rawSteps, index), index)
		if step then
			steps[#steps + 1] = step
			dropped = dropped + step.dropped
			if step.label and not labels[step.label] then labels[step.label] = #steps end
		else
			dropped = dropped + 1
			issues.steps = issues.steps + 1
		end
	end
	for index, step in ipairs(steps) do
		if step.along then
			local last = step.alongUntil and labels[step.alongUntil]
			if not (last and last > index) then
				last = nil
				for later = index + 1, #steps do
					if not steps[later].along then
						last = later
						break
					end
				end
			end
			step.alongLast = last
		end
	end
	guide.steps, guide.labels, guide.dropped = steps, labels, dropped
	guide.broken = #steps == 0
	return steps
end

-- Reads the whole table: the guide list and its metadata. Steps wait for
-- first use. Returns the data state and the list.
function M.ReadData(data)
	issues = NewIssues()
	data = Table(data)
	if not data then return "invalid" end
	local schema = rawget(data, "schema")
	if type(schema) ~= "number" then return "invalid" end
	if schema > SCHEMA then return "newer" end
	if schema < SCHEMA then return "older" end
	local list = Table(rawget(data, "guides"))
	if not list then return "invalid" end
	local guides, byId, skipped = {}, {}, 0
	for index = 1, #list do
		local guide = ReadGuide(rawget(list, index))
		if guide and not byId[guide.id] then
			guides[#guides + 1] = guide
			byId[guide.id] = guide
		else
			skipped = skipped + 1
		end
	end
	issues.guides = skipped
	if #guides == 0 then return "invalid" end
	local source = Table(rawget(data, "source"))
	local info = source and {
		repository = Text(rawget(source, "repository"), 200),
		tag = Text(rawget(source, "tag"), 60),
		commit = Text(rawget(source, "commit"), 60),
	}
	return "ready", { guides = guides, byId = byId, skipped = skipped, source = info }
end

---------------------------------------------------------------------------
-- Loading EldoUI_GuideData
-- dataState: "unloaded" (not asked yet), "waiting" (asked in combat, loads
-- after it), "ready", "missing", "disabled", "failed", "newer", "older",
-- "invalid".
---------------------------------------------------------------------------
M.dataState = "unloaded"

local function Adopt(raw)
	if M.ApplyCorrections then M.ApplyCorrections(raw) end
	local state, data = M.ReadData(raw)
	M.dataState = state
	M.data = data
	return state == "ready"
end

function M:LoadData()
	if self.data then return true end
	if not self:IsLive() then return false end
	local raw = rawget(_G, ADDON)
	if raw ~= nil then return Adopt(raw) end
	if InCombatLockdown() then
		self.dataState = "waiting"
		E:RunOutOfCombat(function()
			if M:IsLive() and not M.data then
				M:LoadData()
				M:Changed()
			end
		end, "Eldostar:load")
		return false
	end
	local name, _, _, _, reason = C_AddOns.GetAddOnInfo(ADDON)
	if not name then
		self.dataState = "missing"
		return false
	end
	if reason == "DISABLED" or reason == "DEP_DISABLED" then
		self.dataState = "disabled"
		return false
	end
	local loaded, why = C_AddOns.LoadAddOn(ADDON)
	raw = rawget(_G, ADDON)
	if raw ~= nil then return Adopt(raw) end
	self.dataState = "failed"
	self.loadReason = (not loaded and type(why) == "string") and why or nil
	return false
end

local STATE_TEXT = {
	unloaded = Key("The guides load when Eldostar starts."),
	waiting = Key("The guides load after combat."),
	ready = Key("The guides are loaded."),
	missing = Key("The guide data is not installed. It comes with EldoUI as the EldoUI_GuideData folder; install EldoUI again to get it."),
	disabled = Key("EldoUI_GuideData is switched off in the game's addon list. Turn it on there and reload."),
	failed = Key("The game could not load EldoUI_GuideData."),
	newer = Key("The guide data is newer than this EldoUI. Update EldoUI to read it."),
	older = Key("The guide data is older than this EldoUI. Install EldoUI again to update it."),
	invalid = Key("The guide data could not be read. Install EldoUI again to repair it."),
}

function M:DataStateText()
	local text = L[STATE_TEXT[self.dataState] or STATE_TEXT.invalid]
	if self.dataState == "failed" and self.loadReason then text = ("%s (%s)"):format(text, self.loadReason) end
	return text
end

-- The data's own source line, for the options page.
function M:SourceText()
	local source = self.data and self.data.source
	if not source then return nil end
	local parts = {}
	if source.tag then parts[#parts + 1] = source.tag end
	if source.commit then parts[#parts + 1] = source.commit:sub(1, 10) end
	if #parts == 0 then return nil end
	return L["Community guides, release %s."]:format(table.concat(parts, " "))
end

---------------------------------------------------------------------------
-- The player and the guides that fit
---------------------------------------------------------------------------
function M.PlayerFacts()
	local _, raceFile = UnitRace("player")
	local _, classFile = UnitClass("player")
	local faction = Plain(UnitFactionGroup("player"))
	return {
		faction = faction,
		factionKey = NameKey(faction),
		race = NameKey(Plain(raceFile)),
		class = NameKey(Plain(classFile)),
		level = tonumber(Plain(UnitLevel("player"))) or 1,
	}
end

local function Fits(rule, facts)
	if not rule then return true end
	if rule.factions and facts.factionKey and not rule.factions[facts.factionKey] then return false end
	if rule.races and facts.race and not rule.races[facts.race] then return false end
	if rule.classes and facts.class and not rule.classes[facts.class] then return false end
	if rule.exceptClasses and facts.class and rule.exceptClasses[facts.class] then return false end
	return true
end
M.Fits = Fits

function M:Guides()
	return self.data and self.data.guides or {}
end

function M:Guide(id)
	return self.data and self.data.byId[id] or nil
end

function M:GuideFits(guide, facts)
	return guide and Fits(guide.only, facts or M.PlayerFacts()) or false
end

-- "now" (the level is in its range), "later", "past" or nil (no range).
function M.LevelFit(guide, level)
	local range = guide and guide.levels
	if not range then return nil end
	if level < range[1] then return "later" end
	if level > range[2] then return "past" end
	return "now"
end

-- The guide after a finished one: the first route choice whose condition
-- holds and that fits the character, else the guide's own next one.
function M:NextGuide(guide, facts)
	if not guide then return nil end
	facts = facts or M.PlayerFacts()
	for _, option in ipairs(guide.nextOptions or {}) do
		local after = self:Guide(option.id)
		if after and self:GuideFits(after, facts) and M.When(option.when, facts) ~= false then return after end
	end
	local after = self:Guide(guide.next)
	if after and self:GuideFits(after, facts) then return after end
end

-- A guide this character finished (read only: no record is made).
local function Finished(guide)
	local record = Store().progress[guide.id]
	return type(record) == "table" and record.done and true or false
end

-- The guide to suggest: the current guide's next one, else the first
-- guide for this character whose levels hold the player's level.
function M:Suggest()
	local facts = M.PlayerFacts()
	local current = self:Guide(Store().guide)
	local after = current and Finished(current) and self:NextGuide(current, facts)
	if after then return after end
	local best
	for _, guide in ipairs(self:Guides()) do
		if guide ~= current and self:GuideFits(guide, facts) and M.LevelFit(guide, facts.level) == "now"
			and not Finished(guide) then
			if not best or (guide.category == "Leveling" and best.category ~= "Leveling") then best = guide end
		end
	end
	return best
end

---------------------------------------------------------------------------
-- Progress per character
---------------------------------------------------------------------------
-- progress[guide id] = { v = version, s = step, skip = { [step] = true },
--   tick = { ["step:goal"] = true }, hist = { ... }, t = step title,
--   l = step label, done = true once finished }
local function NewProgress(guide)
	return { v = guide.version, s = 1, skip = {}, tick = {}, hist = {} }
end

local function Clean(record)
	if type(record.skip) ~= "table" then record.skip = {} end
	if type(record.tick) ~= "table" then record.tick = {} end
	if type(record.hist) ~= "table" then record.hist = {} end
	if type(record.s) ~= "number" or record.s < 1 then record.s = 1 end
end

-- A new guide version: the same step by label, then by title (the one
-- nearest the old number), else the old number within the new length.
function M:Migrate(guide, record)
	local steps = self:Steps(guide)
	local count = #steps
	local index
	if record.l and guide.labels[record.l] then index = guide.labels[record.l] end
	if not index and record.t then
		local best
		for i, step in ipairs(steps) do
			if step.title == record.t and (not best or math.abs(i - record.s) < math.abs(best - record.s)) then best = i end
		end
		index = best
	end
	index = math.max(1, math.min(index or record.s, count))
	local old = record.v
	record.v, record.s = guide.version, index
	record.skip, record.tick, record.hist, record.done = {}, {}, {}, nil
	self.migrated = { guide = guide.id, from = old, to = guide.version, step = index }
	return record
end

function M:Progress(guide)
	local all = Store().progress
	local record = all[guide.id]
	if type(record) ~= "table" then
		record = NewProgress(guide)
		all[guide.id] = record
		return record
	end
	Clean(record)
	if record.v ~= guide.version and not self.migrating then
		self.migrating = true
		self:Migrate(guide, record)
		self.migrating = nil
	end
	return record
end

-- The guide in use and its progress, or nil.
function M:Current()
	local guide = self:Guide(Store().guide)
	if not guide then return nil end
	local steps = self:Steps(guide)
	if guide.broken then return nil end
	local record = self:Progress(guide)
	if record.s > #steps then record.s = #steps end
	return guide, record, steps
end

local function Remember(record, steps)
	local step = steps[record.s]
	record.t, record.l = step and step.title or nil, step and step.label or nil
end

local function Push(record, entry)
	local hist = record.hist
	hist[#hist + 1] = entry
	while #hist > HISTORY_MAX do table.remove(hist, 1) end
end

---------------------------------------------------------------------------
-- What the game tells (each answer true, false or a number; nil when the
-- client cannot tell)
---------------------------------------------------------------------------
local function QuestDone(id)
	if not (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) then return nil end
	local done = PlainCall(C_QuestLog.IsQuestFlaggedCompleted, id)
	if done == nil then return nil end
	return done and true or false
end

local function OnQuest(id)
	if not (C_QuestLog and C_QuestLog.IsOnQuest) then return nil end
	local on = PlainCall(C_QuestLog.IsOnQuest, id)
	if on == nil then return nil end
	return on and true or false
end

local function ItemCount(id)
	if not (C_Item and C_Item.GetItemCount) then return nil end
	return tonumber(PlainCall(C_Item.GetItemCount, id))
end

local function Standing(faction)
	if not (C_Reputation and C_Reputation.GetFactionDataByID) then return nil end
	local data = PlainCall(C_Reputation.GetFactionDataByID, faction)
	return type(data) == "table" and tonumber(Plain(data.reaction)) or nil
end

-- The skill lines of the professions the guides name.
local SKILL_LINES = {
	Alchemy = 171, Blacksmithing = 164, Enchanting = 333, Engineering = 202, Herbalism = 182, Leatherworking = 165,
	Mining = 186, Skinning = 393, Tailoring = 197, Cooking = 185, Fishing = 356, ["First Aid"] = 129,
}

-- skill, the most the current rank allows; 0, 0 when the character has not
-- learned the profession; nil when the client cannot tell.
local function Profession(name)
	local line = SKILL_LINES[name]
	if not (line and GetProfessions and GetProfessionInfo) then return nil end
	local slots = { pcall(GetProfessions) }
	if not slots[1] then return nil end
	for index = 2, 6 do -- after pcall's flag: five slots, any may be empty
		local slot = slots[index]
		if slot then
			local ok, _, _, rank, most, _, _, skillLine = pcall(GetProfessionInfo, slot)
			if ok and tonumber(Plain(skillLine)) == line then
				return tonumber(Plain(rank)) or 0, tonumber(Plain(most)) or 0
			end
		end
	end
	return 0, 0
end

local function SpellKnown(spell)
	local book = C_SpellBook
	if not (book and book.IsSpellKnown) then return nil end
	local known = PlainCall(book.IsSpellKnown, spell)
	if known == nil then return nil end
	return known and true or false
end

local function QuestComplete(quest)
	if QuestDone(quest) then return true end
	if not OnQuest(quest) then return false end
	local log = C_QuestLog
	local ready = log and log.ReadyForTurnIn and PlainCall(log.ReadyForTurnIn, quest)
	if ready then return true end
	local complete = log and log.IsComplete and PlainCall(log.IsComplete, quest)
	return complete and true or false
end

-- -1, 0 or 1: the player's level and experience against a level, which
-- may be a fraction (12.5 is halfway through 12) or carry the experience
-- into it.
local function LevelOrder(level, levelXp)
	local have = tonumber(Plain(UnitLevel("player"))) or 1
	local whole = math.floor(level)
	if have ~= whole then return have < whole and -1 or 1 end
	local xp = tonumber(Plain(UnitXP("player"))) or 0
	local need = levelXp
	if not need then
		if level == whole then return 0 end
		local most = tonumber(Plain(UnitXPMax("player"))) or 0
		if most <= 0 then return 0 end
		need = (level - whole) * most
	end
	if xp == need then return 0 end
	return xp < need and -1 or 1
end
M.LevelOrder = LevelOrder

-- Zone names are compared as the guides write them: in English, so on a
-- client in another language the answer is unknown.
local function PlaceIs(current, name)
	local locale = GetLocale and GetLocale()
	if locale ~= "enUS" and locale ~= "enGB" then return nil end
	current = Plain(current)
	if type(current) ~= "string" then return nil end
	return E:FoldText(current) == E:FoldText(name)
end

local function BindIs(name)
	return PlaceIs(GetBindLocation and PlainCall(GetBindLocation), name)
end

local PREDICATES = {
	level = function(pred)
		local order = LevelOrder(pred.level, pred.levelXp)
		if pred.op == "<" then return order < 0 end
		if pred.op == "<=" then return order <= 0 end
		if pred.op == ">" then return order > 0 end
		return order >= 0
	end,
	onquest = function(pred)
		local answer = false
		for _, quest in ipairs(pred.quests) do
			local on = OnQuest(quest)
			if on then return true end
			if on == nil then answer = nil end
		end
		return answer
	end,
	complete = function(pred) return QuestComplete(pred.quest) end,
	turnedin = function(pred) return QuestDone(pred.quest) end,
	available = function(pred)
		local done, on = QuestDone(pred.quest), OnQuest(pred.quest)
		if done == nil or on == nil then return nil end
		return not done and not on
	end,
	has = function(pred)
		local have = ItemCount(pred.item)
		if have == nil then return nil end
		return have >= (pred.count or 1)
	end,
	zone = function(pred) return PlaceIs(GetRealZoneText and PlainCall(GetRealZoneText), pred.name) end,
	subzone = function(pred) return PlaceIs(GetSubZoneText and PlainCall(GetSubZoneText), pred.name) end,
	bound = function(pred) return BindIs(pred.name) end,
}

-- `when`: true when every predicate holds, false when one does not, nil
-- when the client cannot tell (the step then shows and can be skipped).
local function When(list, facts)
	if not list then return true end
	local answer = true
	for _, pred in ipairs(list) do
		local test = not pred.unknown and PREDICATES[pred.test]
		local value
		if test then
			value = test(pred, facts)
			if value ~= nil and pred.negate then value = not value end
		end
		if value == false then return false end
		if value == nil then answer = nil end
	end
	return answer
end
M.When = When

-- A step this character can do: `only` fits and `when` is not false.
local function ForMe(step, facts)
	if not Fits(step.only, facts) then return false end
	return When(step.when, facts) ~= false
end

-- A stop on the route for this character: a step it can do that is not
-- one done along the way.
function M:Applicable(step, facts)
	if not step or step.along then return false end
	return ForMe(step, facts)
end

---------------------------------------------------------------------------
-- Goals
---------------------------------------------------------------------------
local function Objective(quest, index)
	if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return nil end
	local list = PlainCall(C_QuestLog.GetQuestObjectives, quest)
	local entry = type(list) == "table" and list[index]
	if type(entry) ~= "table" then return nil end
	local have, need = tonumber(Plain(entry.numFulfilled)), tonumber(Plain(entry.numRequired))
	local finished = Plain(entry.finished)
	return finished and true or false, have, need, Plain(entry.text)
end

-- Kinds whose places, in a `loop` step, are its `goto` goals.
local SEARCHED = { kill = true, collect = true, interact = true, use = true }

-- done, have, need, auto (the client answered). key: the tick's key.
-- Only the game's own answers count; what it cannot tell is ticked.
function M:GoalState(goal, key, record)
	local ticked = record and record.tick[key] and true or false
	local kind = goal.kind
	if kind == "note" then return true, nil, nil, true end
	local quest = goal.quest
	if quest and kind == "accept" then
		return ticked or QuestDone(quest) or OnQuest(quest) or false, nil, nil, true
	end
	if quest and kind == "turnin" then
		return ticked or QuestDone(quest) or false, nil, nil, true
	end
	if quest and kind == "abandon" then
		return ticked or OnQuest(quest) == false, nil, nil, true
	end
	if quest and goal.objective then
		if QuestDone(quest) then return true, goal.count, goal.count, true end
		local finished, have, need = Objective(quest, goal.objective)
		if finished ~= nil then return ticked or finished, have, need, true end
		if OnQuest(quest) == false then return ticked, nil, goal.count, true end
	end
	if quest and kind == "complete" then
		return ticked or QuestComplete(quest), nil, nil, true
	end
	if goal.item and (kind == "collect" or kind == "buy") then
		if quest and QuestDone(quest) then return true, goal.count, goal.count, true end
		local need = goal.count or 1
		local have = ItemCount(goal.item)
		if have then return ticked or have >= need, math.min(have, need), need, true end
	end
	if kind == "level" and goal.level then
		return ticked or LevelOrder(goal.level, goal.levelXp) >= 0, nil, nil, true
	end
	if kind == "money" and goal.money then
		local money = tonumber(PlainCall(GetMoney)) or 0
		return ticked or money >= goal.money, nil, nil, true
	end
	if kind == "rep" and goal.factionId and goal.standing then
		local standing = Standing(goal.factionId)
		if standing then return ticked or standing >= STANDINGS[goal.standing], nil, nil, true end
	end
	if kind == "skill" and goal.profession and goal.value then
		local rank = Profession(goal.profession)
		if rank then return ticked or rank >= goal.value, math.min(rank, goal.value), goal.value, true end
	end
	if kind == "train" and goal.profession then
		local rank, most = Profession(goal.profession)
		if rank then return ticked or most >= (goal.rank and RANK_CAPS[goal.rank] or 1), nil, nil, true end
	end
	if (kind == "learn" or kind == "train") and goal.spell then
		local known = SpellKnown(goal.spell)
		if known ~= nil then return ticked or known, nil, nil, true end
	end
	if kind == "sethome" and goal.place then
		local bound = BindIs(goal.place)
		if bound ~= nil then return ticked or bound, nil, nil, true end
	end
	return ticked, nil, goal.count, false
end

-- Goals that hold a step up: not notes, not optional ones and not the
-- places of a `loop` step (those are only where to search).
local function Counts(goal, step)
	if goal.kind == "note" or goal.optional then return false end
	if step and step.loop and goal.kind == "goto" then return false end
	return true
end
M.Counts = Counts

-- Goals that follow a quest's accept: its turn-in, completion, objectives
-- and abandon.
local FOLLOWS_ACCEPT = { turnin = true, complete = true, abandon = true }

-- A quest the character never took because every accept for it so far on
-- the route was optional, skipped or for someone else: its later goals go
-- with it and don't hold a step, while the quest is neither in the log
-- nor turned in. Taking it after all makes them count again. A quest with
-- no accept in the guide (taken somewhere else) still counts.
function M:QuestLeftOut(quest, index, record, steps, facts)
	if OnQuest(quest) or QuestDone(quest) then return false end
	local seen = false
	for i = 1, math.min(index, #steps) do
		local step = steps[i]
		for _, goal in ipairs(step.goals) do
			if goal.kind == "accept" and goal.quest == quest then
				seen = true
				if not goal.optional and not record.skip[i] and ForMe(step, facts) and Fits(goal.only, facts) then
					return false
				end
			end
		end
	end
	return seen
end

-- The objective lines of a quest in the log, in the game's words with
-- their counts: { text, done } each (only the open ones when asked).
local function Objectives(quest, openOnly)
	local lines = {}
	local list = C_QuestLog and C_QuestLog.GetQuestObjectives and PlainCall(C_QuestLog.GetQuestObjectives, quest)
	for _, objective in ipairs(type(list) == "table" and list or {}) do
		local text = type(objective) == "table" and Plain(objective.text)
		local finished = type(objective) == "table" and Plain(objective.finished) and true or false
		if type(text) == "string" and text ~= "" and not (openOnly and finished) then
			lines[#lines + 1] = { text = text, done = finished }
		end
	end
	return lines
end

-- A turn-in of a quest in the log whose work is not done: its open
-- objective lines (`openWork`), so the goal can say so and the waypoint
-- can lead to the work instead of the quest ender.
local function Entry(goal, key, record, along)
	local done, have, need, auto = M:GoalState(goal, key, record)
	local entry = { goal = goal, key = key, done = done and true or false, have = have, need = need, auto = auto, along = along }
	if not entry.done and goal.kind == "turnin" and goal.quest and OnQuest(goal.quest) and not QuestComplete(goal.quest) then
		entry.openWork = Objectives(goal.quest, true)
	elseif not entry.done and goal.kind == "complete" and goal.quest and OnQuest(goal.quest) then
		entry.objectives = Objectives(goal.quest)
	end
	return entry
end

-- The goals of a step for this character with their state: { goal, key,
-- done, have, need, auto }, then the goals done along the way to it (from
-- the `along` steps before it), and those steps' tips. A goal's key is its
-- own step and place in the guide, so a tick stays with it.
function M:StepGoals(index, record, steps, facts)
	local step = steps and steps[index]
	local out, along, notes = {}, {}, {}
	if not step then return out, along, notes end
	facts = facts or M.PlayerFacts()
	for _, goal in ipairs(step.goals) do
		if Fits(goal.only, facts) then
			local entry = Entry(goal, index .. ":" .. goal.index, record)
			entry.counts = Counts(goal, step)
			if entry.counts and not entry.done and goal.quest and (FOLLOWS_ACCEPT[goal.kind] or goal.objective)
				and self:QuestLeftOut(goal.quest, index, record, steps, facts) then
				entry.counts, entry.leftOut = false, true
			end
			out[#out + 1] = entry
		end
	end
	-- Goals along the way stay listed up to the step their list ends at,
	-- and after it while their quest is in the log with work still open.
	for earlier = 1, index - 1 do
		local source = steps[earlier]
		if source.along and source.alongLast and ForMe(source, facts) then
			local current = source.alongLast >= index
			if current and source.tip then notes[#notes + 1] = source.tip end
			for _, goal in ipairs(source.goals) do
				if Fits(goal.only, facts) and (current or (goal.quest and OnQuest(goal.quest) and not QuestComplete(goal.quest))) then
					along[#along + 1] = Entry(goal, earlier .. ":" .. goal.index, record, true)
				end
			end
		end
	end
	return out, along, notes
end

-- The open work of a quest whose turn-in waits: its goals along the way
-- and its search and objective goals in the steps up to this one, those
-- not done yet.
function M:QuestWork(quest, index, record, steps, facts)
	local work = {}
	facts = facts or M.PlayerFacts()
	for earlier = 1, math.min(index, #steps) do
		local source = steps[earlier]
		if ForMe(source, facts) then
			for _, goal in ipairs(source.goals) do
				if goal.quest == quest and (SEARCHED[goal.kind] or goal.objective) and Fits(goal.only, facts) then
					local entry = Entry(goal, earlier .. ":" .. goal.index, record, earlier < index or nil)
					if not entry.done then work[#work + 1] = entry end
				end
			end
		end
	end
	return work
end

-- A step is finished when every goal that counts is done; a step without
-- one only waits for Next (unless its goals were left out, see below).
function M:StepDone(index, record, steps)
	local goals = self:StepGoals(index, record, steps)
	local counted, leftOut = 0, false
	for _, entry in ipairs(goals) do
		if entry.counts then
			counted = counted + 1
			if not entry.done then return false end
		elseif entry.leftOut then
			leftOut = true
		end
	end
	-- A step whose goals all belong to a quest this character never took
	-- is done too: there is nothing left in it to do.
	return counted > 0 or leftOut
end

---------------------------------------------------------------------------
-- Moving through the guide
---------------------------------------------------------------------------
-- The next step this character does after `from`: skipped steps and
-- steps for others are passed over; a step with `skipto` jumps to its
-- label. nil after the last step.
function M:NextIndex(guide, record, steps, from, facts)
	facts = facts or M.PlayerFacts()
	local index = from
	local jump = steps[from] and steps[from].skipto
	if jump and guide.labels[jump] and guide.labels[jump] > from then
		index = guide.labels[jump] - 1
	end
	for i = index + 1, #steps do
		if not record.skip[i] and self:Applicable(steps[i], facts) then return i end
	end
	return nil
end

function M:PrevIndex(record, steps, from, facts)
	facts = facts or M.PlayerFacts()
	for i = from - 1, 1, -1 do
		if self:Applicable(steps[i], facts) then return i end
	end
	return nil
end

local function SetStep(record, steps, index)
	record.s = index
	Remember(record, steps)
	M.hold = nil
end

-- Finished: the record keeps its last step, and the window offers the
-- next guide.
local function Finish(record)
	record.done = true
	M.hold = nil
end

-- Moves on from the current step. kind: "next" (the button), "skip"
-- (marks the step skipped), "auto" (it finished). Done steps after it are
-- passed over too, so a returning player catches up at once.
function M:Advance(kind)
	local guide, record, steps = self:Current()
	if not guide then return false end
	if record.done then return false end
	local facts = M.PlayerFacts()
	local from = record.s
	Push(record, { k = kind, s = from })
	if kind == "skip" then record.skip[from] = true end
	local index = self:NextIndex(guide, record, steps, from, facts)
	local guard = #steps
	while index and self.db.autoAdvance and self:StepDone(index, record, steps) and guard > 0 do
		guard = guard - 1
		index = self:NextIndex(guide, record, steps, index, facts)
	end
	if index then SetStep(record, steps, index) else Finish(record) end
	self:Changed()
	return true
end

function M:Next() return self:Advance("next") end
function M:Skip() return self:Advance("skip") end

function M:Prev()
	local guide, record, steps = self:Current()
	if not guide then return false end
	local index = record.done and record.s or self:PrevIndex(record, steps, record.s)
	if not index then return false end
	Push(record, { k = "prev", s = record.s, done = record.done or nil })
	record.done = nil
	SetStep(record, steps, index)
	-- The player went back on purpose: it stays until they move on.
	self.hold = index
	self:Changed()
	return true
end

-- Ticks or unticks a goal the client cannot answer.
function M:ToggleGoal(key)
	local guide, record = self:Current()
	if not (guide and type(key) == "string") then return false end
	local was = record.tick[key] and true or false
	Push(record, { k = "tick", s = record.s, g = key, was = was })
	record.tick[key] = (not was) or nil
	-- The last goal ticked finishes the step.
	self:Evaluate()
	return true
end

function M:CanUndo()
	local guide, record = self:Current()
	return guide ~= nil and #record.hist > 0
end

-- Takes back the last move, skip or check-off.
function M:Undo()
	local guide, record, steps = self:Current()
	if not guide then return false end
	local entry = table.remove(record.hist)
	if type(entry) ~= "table" then return false end
	if entry.k == "tick" and type(entry.g) == "string" then
		record.tick[entry.g] = entry.was and true or nil
	end
	if entry.k == "skip" and type(entry.s) == "number" then record.skip[entry.s] = nil end
	if entry.k == "prev" then record.done = entry.done and true or nil else record.done = nil end
	if type(entry.s) == "number" and steps[entry.s] then SetStep(record, steps, entry.s) end
	-- A step the player came back to stays until they move on.
	self.hold = record.s
	self:Changed()
	return true
end

-- Starts (or goes back to) a guide. Its saved progress stays.
function M:StartGuide(id)
	local guide = self:Guide(id)
	if not guide then return false end
	local steps = self:Steps(guide)
	if guide.broken then return false end
	Store().guide = id
	local record = self:Progress(guide)
	local facts = M.PlayerFacts()
	if not self:Applicable(steps[record.s], facts) then
		local index = self:NextIndex(guide, record, steps, record.s, facts)
		if index then SetStep(record, steps, index) end
	end
	Remember(record, steps)
	self.hold = nil
	Store().hidden = nil
	-- A guide in use: the window and the rest come now.
	self:Wake()
	self:Changed()
	-- Steps already done (quests turned in before) are passed at once.
	self:Evaluate()
	return true
end

-- Starts the guide over: its progress for this character is cleared.
function M:ResetGuide(id)
	local guide = self:Guide(id or Store().guide)
	if not guide then return false end
	Store().progress[guide.id] = NewProgress(guide)
	if Store().guide == guide.id then
		self.hold = nil
		self:Changed()
		self:Evaluate()
	end
	return true
end

function M:StopGuide()
	Store().guide = nil
	self:Changed()
end

-- The current step, after the game changed something: a finished step
-- moves on (when that option is on), and the window and the waypoint
-- follow.
function M:Evaluate()
	if not self:IsLive() then return end
	local guide, record, steps = self:Current()
	if guide and not record.done and self.db.autoAdvance and self.hold ~= record.s
		and self:StepDone(record.s, record, steps) then
		self:Advance("auto")
		return
	end
	self:Changed(true)
end

-- Many events come at once (a turn-in fires several): one evaluation.
function M:Queue()
	if self.queued or not self:IsLive() then return end
	self.queued = true
	C_Timer.After(0.2, function()
		M.queued = nil
		M:Evaluate()
	end)
end

---------------------------------------------------------------------------
-- The waypoint: one, through the Waypoints module
---------------------------------------------------------------------------
local function LootGuide()
	local LG = E.LootGuide
	if LG and LG.HasData and LG:HasData() then return LG end
end

-- A creature or object's camps, largest first, without its stray spots:
-- a camp of one or two spawns is left out when the largest camp has at
-- least four times as many.
local STRAY_SHARE = 4
local function Camps(kind, id, out)
	local LG = LootGuide()
	if not (LG and id) then return out end
	local camps = LG:SpawnPoints(kind, id)
	local most = camps[1] and camps[1].count or 0
	for _, camp in ipairs(camps) do
		if not ((camp.count or 1) <= 2 and most >= STRAY_SHARE * (camp.count or 1)) then out[#out + 1] = camp end
	end
	return out
end

local function PlaceCamps(place, out)
	if not place then return out end
	return Camps(place.kind == "object" and "object" or "npc", place.id, out)
end

local function PlayerWorld()
	local WP = E.Waypoints
	if not (WP and WP.PlayerPos) then return nil end
	local _, _, _, continent, north, west = (WP.SharedPlayerPos or WP.PlayerPos)()
	return continent, north, west
end

-- True when a map is the zone or lies inside it (a town or cave map).
local function InZone(uiMapID, zone)
	for _ = 1, 4 do
		if not uiMapID then return false end
		if uiMapID == zone then return true end
		local info = C_Map and C_Map.GetMapInfo and PlainCall(C_Map.GetMapInfo, uiMapID)
		uiMapID = type(info) == "table" and Plain(info.parentMapID) or nil
	end
	return false
end

-- The camp to go to: on the step's zone when one is there, nearest to
-- the player (by the camp's world position, on the player's continent);
-- where the game hides the position, the largest. Returns the point and
-- its distance in yards (nil when the position is hidden).
local function NearestCamp(camps, step)
	local LG = LootGuide()
	if not (LG and camps[1]) then return nil end
	local points = {}
	for _, camp in ipairs(camps) do
		local point = LG:PointFor(camp)
		if point and point.uiMapID then points[#points + 1] = { camp = camp, point = point } end
	end
	local zone = step and step.zone
	if zone then
		local inZone = {}
		for _, entry in ipairs(points) do
			if InZone(entry.point.uiMapID, zone) then inZone[#inZone + 1] = entry end
		end
		if inZone[1] then points = inZone end
	end
	if not points[1] then return nil end
	local continent, north, west = PlayerWorld()
	local best, bestYards
	if continent then
		for _, entry in ipairs(points) do
			local camp = entry.camp
			if camp.map == continent then
				local dn, dw = camp.x - north, camp.y - west
				local yards = math.sqrt(dn * dn + dw * dw)
				if not bestYards or yards < bestYards then best, bestYards = entry, yards end
			end
		end
	end
	return (best or points[1]).point, bestYards
end
M.NearestCamp = NearestCamp

local function PlacesPoint(places, step)
	local camps = {}
	for _, place in ipairs(places or {}) do PlaceCamps(place, camps) end
	return NearestCamp(camps, step)
end

-- A goal's own place. The guides write points in the original game's map
-- frame unless they say `frame = "live"`. The original zones (the zone
-- facts in Data/Zones.lua) are used as written; on a map WoW: Forever
-- added, a point in the original frame has no known match, so it gets no
-- waypoint and the goal shows without one.
local function EraMapKnown(map)
	local zones = E.zoneData and E.zoneData.zones
	return zones and zones[map] ~= nil or false
end
M.EraMapKnown = EraMapKnown

local function OwnPoint(goal)
	if not (goal.map and goal.x and goal.y) then return nil end
	if goal.frame ~= "live" and not EraMapKnown(goal.map) then return nil end
	return { uiMapID = goal.map, x = goal.x / 100, y = goal.y / 100 }
end
M.OwnPoint = OwnPoint

-- { uiMapID, x, y (0-1) } of a goal and its distance in yards: its own
-- place, else the quest giver or ender, else the creature or object it
-- names (the Loot Guide's data, placed by the game's own map). With
-- several camps or givers, the nearest one on the step's zone.
function M:GoalPoint(goal, step)
	local own = OwnPoint(goal)
	if own then return own end
	local LG = LootGuide()
	-- Every quest the Journal knows: the open data's dungeon and reward
	-- quests and its journey quests, the WoW: Forever overlay, and the
	-- givers you have seen yourself.
	local quest = LG and goal.quest and (LG.JourneyQuest and LG:JourneyQuest(goal.quest) or LG:Quest(goal.quest))
	local function Known(place)
		if type(place) == "table" and place.map and place.x and place.y then
			return { uiMapID = place.map, x = place.x, y = place.y }
		end
	end
	if quest and goal.kind == "accept" then
		local seen = Known(quest.giver)
		if seen then return seen end
		local point, yards = PlacesPoint(quest.starts, step)
		if point then return point, yards end
	elseif quest and goal.kind == "turnin" then
		local seen = Known(quest.ender)
		if seen then return seen end
		local point, yards = PlacesPoint(quest.ends, step)
		if point then return point, yards end
	end
	if goal.npc then
		local point, yards = NearestCamp(Camps("npc", goal.npc, {}), step)
		if point then return point, yards end
	end
	if goal.object then return NearestCamp(Camps("object", goal.object, {}), step) end
end

local function Waypoints()
	local WP = E.Waypoints
	if WP and WP.active and WP.Add then return WP end
end

function M:ClearWaypoint()
	local own = self.waypoint
	self.waypoint = nil
	local WP = E.Waypoints
	if own and own.uid and own.created and WP and WP.Get and WP:Get(own.uid) then WP:Remove(own.uid, true) end
end

-- The places of a `loop` step, in order: where to search for its goals
-- that have no place of their own.
local function LoopPlaces(step)
	local places = {}
	if not (step and step.loop) then return places end
	for _, goal in ipairs(step.goals) do
		local point = goal.kind == "goto" and OwnPoint(goal)
		if point then places[#places + 1] = { goal = goal, point = point } end
	end
	return places
end

-- The place in a loop step the player searches now (the loop goes round).
function M:LoopPlace(index, step)
	local places = LoopPlaces(step)
	if #places == 0 then return nil end
	local guide, record = self:Current()
	local loop = self.loop
	if not (loop and loop.guide == guide and loop.record == record
		and loop.definition == step and loop.step == index) then
		loop = { guide = guide, record = record, definition = step, step = index, at = 1 }
		self.loop = loop
	end
	if loop.at > #places then loop.at = 1 end
	return places[loop.at], #places
end

-- Switching to another search goal takes a clearly nearer one: 20 %
-- and 30 yards nearer than the goal aimed at now.
local SWITCH_SHARE, SWITCH_YARDS = 0.8, 30

-- Of the open search goals of a step (kill, collect, use), the nearest:
-- the one aimed at stays while it is open and none is clearly nearer, and
-- in combat the aim does not move at all.
function M:NearestSearch(goals, step, stepIndex)
	local aim = self.aim
	if not (aim and aim.step == stepIndex and aim.definition == step) then aim = nil end
	local options, kept = {}, nil
	for _, entry in ipairs(goals) do
		if not entry.done and entry.counts and SEARCHED[entry.goal.kind] then
			local point, yards = self:GoalPoint(entry.goal, step)
			if point then
				local option = { point = point, entry = entry, yards = yards }
				options[#options + 1] = option
				if aim and aim.key == entry.key then kept = option end
			end
		end
	end
	if not options[1] then return nil end
	local best = options[1]
	for _, option in ipairs(options) do
		if option.yards and (not best.yards or option.yards < best.yards) then best = option end
	end
	if kept and kept ~= best then
		local inCombat = InCombatLockdown and InCombatLockdown()
		if inCombat or not (kept.yards and best.yards)
			or not (best.yards <= kept.yards * SWITCH_SHARE and kept.yards - best.yards >= SWITCH_YARDS) then
			best = kept
		end
	end
	self.aim = { step = stepIndex, definition = step, key = best.entry.key }
	return best.point, best.entry
end

-- The current goal: the first one not done that has a place; among open
-- search goals, the nearest (see M:NearestSearch).
function M:WaypointTarget()
	local guide, record, steps = self:Current()
	if not guide or record.done then return nil end
	local step = steps[record.s]
	local goals = self:StepGoals(record.s, record, steps)
	for _, entry in ipairs(goals) do
		if not entry.done and entry.counts then
			local goal = entry.goal
			if step.loop and SEARCHED[goal.kind] and not OwnPoint(goal) then
				local place = self:LoopPlace(record.s, step)
				if place then return place.point, entry end
			end
			if SEARCHED[goal.kind] and not step.loop then
				local point, aimed = self:NearestSearch(goals, step, record.s)
				if point then return point, aimed end
			end
			if entry.openWork then
				-- Not at the quest ender yet: to the nearest open work.
				local best, bestYards, bestEntry
				for _, work in ipairs(self:QuestWork(goal.quest, record.s, record, steps)) do
					local point, yards = self:GoalPoint(work.goal, step)
					if point and (not best or (yards and (not bestYards or yards < bestYards))) then
						best, bestYards, bestEntry = point, yards, work
					end
				end
				if best then return best, bestEntry end
			else
				local point = self:GoalPoint(goal, step)
				if point then return point, entry end
			end
		end
	end
end

function M:UpdateWaypoint()
	if not (self.awake and self:IsLive() and self.db.waypoint) then
		self:ClearWaypoint()
		return
	end
	local WP = Waypoints()
	local point, entry = self:WaypointTarget()
	if not (WP and point) then
		self:ClearWaypoint()
		return
	end
	local key = ("%d:%.4f:%.4f"):format(point.uiMapID, point.x, point.y)
	local own = self.waypoint
	local title = M.GoalText(entry.goal)
	if own and own.key == key and own.uid and WP:Get(own.uid) then
		if own.created and own.title ~= title then
			WP:Add(point.uiMapID, point.x, point.y,
				{ title = title, persistent = false, silent = true, source = "eldostar", noArrow = true, noSave = true })
			own.title = title
		end
		return
	end
	self:ClearWaypoint()
	local before = #WP.order
	local uid = WP:Add(point.uiMapID, point.x, point.y,
		{ title = title, persistent = false, silent = true, source = "eldostar" })
	if uid then self.waypoint = { uid = uid, key = key, title = title, created = #WP.order > before or nil } end
end

---------------------------------------------------------------------------
-- Arriving at a place: a goal to go to or explore is ticked when the
-- player stands within its radius, and a loop step's waypoint moves on to
-- its next place (the open world only: the game hides the position in
-- instances).
---------------------------------------------------------------------------
local ARRIVE_YARDS = 8

local ARRIVE_KINDS = { ["goto"] = true, explore = true }

local function Near(goal, point, continent, north, west)
	local c, n, w = E.Waypoints.WorldPos(point.uiMapID, point.x, point.y)
	if not (c and c == continent) then return false end
	local dn, dw = n - north, w - west
	return math.sqrt(dn * dn + dw * dw) <= (goal.radius or ARRIVE_YARDS)
end

-- The goals of the current step that arriving ticks.
local function Arrivals(record, step)
	local out = {}
	if step.loop then return out end
	for _, goal in ipairs(step.goals) do
		local key = record.s .. ":" .. goal.index
		if ARRIVE_KINDS[goal.kind] and not record.tick[key] then
			local point = OwnPoint(goal)
			if point then out[#out + 1] = { goal = goal, key = key, point = point } end
		end
	end
	return out
end

function M:CheckArrival()
	local guide, record, steps = self:Current()
	if not guide or record.done then return false end
	local step = steps[record.s]
	local WP = E.Waypoints
	if not (step and WP and WP.WorldPos) then return false end
	local continent, north, west = PlayerWorld()
	if not continent then return false end
	local changed = false
	for _, arrival in ipairs(Arrivals(record, step)) do
		if Near(arrival.goal, arrival.point, continent, north, west) then
			record.tick[arrival.key] = true
			changed = true
		end
	end
	if changed then
		self:Evaluate()
		return true
	end
	local place = step.loop and self:LoopPlace(record.s, step)
	if place and self.waypoint and Near(place.goal, place.point, continent, north, west) then
		self.loop.at = self.loop.at + 1
		self:UpdateWaypoint()
		return true
	end
	return false
end

-- The arrival check runs once a second, only while the current step has a
-- place to arrive at.
function M:UpdateArrivalWatch()
	local want = false
	local guide, record, steps = self:Current()
	if self.awake and self:IsLive() and guide and not record.done then
		local step = steps[record.s]
		want = #Arrivals(record, step) > 0 or (step.loop and #LoopPlaces(step) > 0)
	end
	if want then
		E.Ticker:Subscribe("Eldostar:arrive", 1, function() M:CheckArrival() end, M)
	else
		E.Ticker:Unsubscribe("Eldostar:arrive")
	end
end

---------------------------------------------------------------------------
-- Goals the game reports by a window or a landing, on the current step
-- only and only from what the game shows (nothing here opens, picks,
-- trains or buys): a flight that lands ticks `fly`, a merchant window
-- `vendor`, a closed trainer window `train` (a class trainer, or the
-- goal's trainer), and a gossip or quest window `talk` at the goal's NPC.
-- The goals stay clickable by hand. The events are listened to only while
-- the current step has such a goal.
---------------------------------------------------------------------------
local SEEN_EVENTS = {
	"MERCHANT_SHOW", "TRAINER_SHOW", "TRAINER_CLOSED", "GOSSIP_SHOW", "QUEST_DETAIL", "QUEST_GREETING",
	"QUEST_PROGRESS", "QUEST_COMPLETE", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
}
local TALK_EVENTS = { GOSSIP_SHOW = true, QUEST_DETAIL = true, QUEST_GREETING = true, QUEST_PROGRESS = true, QUEST_COMPLETE = true }

-- The class trainers' titles in the Loot Guide's data are English.
local CLASS_WORDS = {
	WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
	SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}

-- The kind of report a goal waits for, or nil.
local function SeenKind(goal)
	local kind = goal.kind
	if kind == "fly" or kind == "vendor" then return kind end
	if kind == "train" and not goal.spell and not goal.profession and (goal.classTrainer or goal.npc) then return kind end
	if kind == "talk" and goal.npc and not goal.quest then return kind end
end
M.SeenKind = SeenKind

local function SeenGoals(record, step)
	local out = {}
	if not step then return out end
	local facts = M.PlayerFacts()
	for _, goal in ipairs(step.goals) do
		local key = record.s .. ":" .. goal.index
		local kind = SeenKind(goal)
		if kind and not record.tick[key] and Fits(goal.only, facts) then out[#out + 1] = { goal = goal, key = key, kind = kind } end
	end
	return out
end

-- The creature whose window is open (out of combat, as the game shows it).
local function WindowNpc()
	if InCombatLockdown() then return nil end
	local guid = PlainCall(UnitGUID, "npc")
	if type(guid) ~= "string" then return nil end
	local unitType, _, _, _, _, id = strsplit("-", guid)
	if unitType == "Creature" then return tonumber(id) end
end

-- True when the Loot Guide's data names this NPC a trainer of the
-- player's class; nil when it cannot tell.
local function ClassTrainer(npc)
	local LG = LootGuide()
	local LD = LG and LG.DataStatus and select(3, LG:DataStatus())
	local services = type(LD) == "table" and LD.services
	local text = type(services) == "table" and npc and services[npc]
	if type(text) ~= "string" then return nil end
	local kinds, subname = text:match("^(%a+)|.*|([^|]*)$")
	local word = CLASS_WORDS[select(2, UnitClass("player")) or ""]
	return (kinds and word and kinds:find("c", 1, true) and subname:find(word, 1, true)) and true or false
end
M.ClassTrainer = ClassTrainer

-- Ticks the current step's goals of one kind that `fits` accepts.
function M:TickSeen(kind, fits)
	local guide, record, steps = self:Current()
	if not guide or record.done then return false end
	local changed = false
	for _, seen in ipairs(SeenGoals(record, steps[record.s])) do
		if seen.kind == kind and fits(seen.goal) then
			record.tick[seen.key] = true
			changed = true
		end
	end
	if changed then self:Evaluate() end
	return changed
end

function M:OnSeen(event)
	if event == "PLAYER_CONTROL_LOST" then
		-- The taxi state can come a moment after the control.
		self.flying = PlainCall(UnitOnTaxi, "player") and true or nil
		if not self.flying then
			C_Timer.After(1, function()
				if PlainCall(UnitOnTaxi, "player") then M.flying = true end
			end)
		end
		return
	end
	if event == "PLAYER_CONTROL_GAINED" then
		if not self.flying then return end
		self.flying = nil
		self:TickSeen("fly", function() return true end)
		return
	end
	local npc = WindowNpc()
	if event == "MERCHANT_SHOW" then
		self:TickSeen("vendor", function(goal) return not goal.npc or goal.npc == npc end)
	elseif event == "TRAINER_SHOW" then
		self.trainerAt = npc
	elseif event == "TRAINER_CLOSED" then
		local at = self.trainerAt
		self.trainerAt = nil
		if not at then return end
		self:TickSeen("train", function(goal)
			if goal.npc then return goal.npc == at end
			return goal.classTrainer and ClassTrainer(at) == true
		end)
	elseif TALK_EVENTS[event] and npc then
		self:TickSeen("talk", function(goal) return goal.npc == npc end)
	end
end

function M:UpdateSeenWatch()
	local want = false
	local guide, record, steps = self:Current()
	if self.awake and self:IsLive() and guide and not record.done then
		want = #SeenGoals(record, steps[record.s]) > 0
	end
	if want == (self.seenWatch or false) then return end
	self.seenWatch = want
	for _, event in ipairs(SEEN_EVENTS) do
		if want then
			self:RegisterEvent(event, function(_, name) M:OnSeen(name) end)
		else
			self:UnregisterEvent(event)
		end
	end
	if not want then self.flying, self.trainerAt = nil, nil end
end

---------------------------------------------------------------------------
-- Texts of goals (EldoUI's words around the guide's own names)
---------------------------------------------------------------------------
local KIND_TEXT = {
	accept = Key("Accept %s"), turnin = Key("Turn in %s"), complete = Key("Complete %s"), abandon = Key("Abandon %s"),
	["goto"] = Key("Go to %s"), explore = Key("Explore %s"), sethome = Key("Make %s your home"), hearth = Key("Hearth to %s"),
	getfp = Key("Get the flight path at %s"), fly = Key("Fly to %s"), enter = Key("Enter %s"), talk = Key("Talk to %s"),
	train = Key("Train %s"), vendor = Key("Visit %s"), buy = Key("Buy %s"), collect = Key("Collect %s"),
	interact = Key("Use %s"), use = Key("Use %s"), kill = Key("Kill %s"), level = Key("Reach level %s"),
	money = Key("Have %s"), skill = Key("Raise %s"), learn = Key("Learn %s"), craft = Key("Craft %s"),
	rep = Key("Earn %s"), cast = Key("Cast %s"), destroy = Key("Destroy %s"),
}
M.KIND_TEXT = KIND_TEXT

-- Texts of goals that name nothing more.
local BARE_TEXT = {
	sethome = Key("Make the nearest inn your home"), hearth = Key("Use your hearthstone"), vendor = Key("Visit a vendor"),
	train = Key("Train at your class trainer"),
}

local function QuestName(id)
	local LG = E.LootGuide
	local name = LG and LG.QuestTitle and LG:QuestTitle(id)
	if type(name) ~= "string" and C_QuestLog and C_QuestLog.GetTitleForQuestID then
		name = Plain(PlainCall(C_QuestLog.GetTitleForQuestID, id))
	end
	return type(name) == "string" and name ~= "" and Text(name, 200) or nil
end

local function ItemName(id)
	local LG = LootGuide()
	local record = LG and LG:ItemRecord(id)
	local name = record and record.name
	if type(name) ~= "string" and C_Item and C_Item.GetItemNameByID then name = Plain(PlainCall(C_Item.GetItemNameByID, id)) end
	return type(name) == "string" and name ~= "" and Text(name, 200) or nil
end

local function NpcName(id)
	local LG = LootGuide()
	local mob = LG and LG:Mob(id)
	return mob and type(mob.name) == "string" and Text(mob.name, 200) or nil
end

local function ObjectName(id)
	local LG = LootGuide()
	local name = LG and LG:ObjectName(id)
	return type(name) == "string" and Text(name, 200) or nil
end

local function SpellName(id)
	local name = C_Spell and C_Spell.GetSpellName and Plain(PlainCall(C_Spell.GetSpellName, id))
	return type(name) == "string" and name ~= "" and Text(name, 200) or nil
end

local function FactionName(id)
	if not (C_Reputation and C_Reputation.GetFactionDataByID) then return nil end
	local data = PlainCall(C_Reputation.GetFactionDataByID, id)
	local name = type(data) == "table" and Plain(data.name)
	return type(name) == "string" and name ~= "" and Text(name, 200) or nil
end

local function LevelText(goal)
	local level = goal.level
	local text = level % 1 == 0 and tostring(level) or ("%.1f"):format(level)
	if goal.levelXp then text = L["%s plus %d XP"]:format(text, goal.levelXp) end
	return text
end

local QUEST_KINDS = { accept = true, turnin = true, complete = true, abandon = true }

-- What the goal is about, in the game's or the guide's words.
local function Subject(goal)
	local kind = goal.kind
	if goal.quest and QUEST_KINDS[kind] then return QuestName(goal.quest) or goal.title or L["quest %d"]:format(goal.quest) end
	if kind == "level" and goal.level then return LevelText(goal) end
	if kind == "rep" then
		local faction = (goal.factionId and FactionName(goal.factionId)) or goal.factionName
			or (goal.factionId and L["faction %d"]:format(goal.factionId))
		if faction and goal.standing then return L["%s with %s"]:format(goal.standing, faction) end
		return faction
	end
	if kind == "skill" and goal.profession then
		return goal.value and L["%s to %d"]:format(goal.profession, goal.value) or goal.profession
	end
	if kind == "train" and goal.profession then
		return goal.rank and ("%s %s"):format(goal.rank, goal.profession) or goal.profession
	end
	if goal.label then return goal.label end
	if goal.place then return goal.place end
	if goal.item then return ItemName(goal.item) or goal.name or L["item %d"]:format(goal.item) end
	if goal.spell then return SpellName(goal.spell) or goal.name or L["spell %d"]:format(goal.spell) end
	if goal.npc then return NpcName(goal.npc) or goal.name or L["creature %d"]:format(goal.npc) end
	if goal.object then return ObjectName(goal.object) or goal.name or L["object %d"]:format(goal.object) end
	if goal.name then return goal.name end
	if goal.quest and goal.objective then
		local _, _, _, text = Objective(goal.quest, goal.objective)
		if type(text) == "string" and text ~= "" then return Text(text, 200) end
		return QuestName(goal.quest) or goal.title
	end
	if kind == "money" and goal.money then return GetMoneyString and GetMoneyString(goal.money) or tostring(goal.money) end
	if goal.map and goal.x then return ("%.1f, %.1f"):format(goal.x, goal.y) end
	return nil
end

function M.GoalText(goal)
	local kind = goal.kind
	local text = goal.text
	if not text and (kind == "note" or kind == "task") then text = goal.note or goal.title or goal.label end
	local note = goal.note
	if text then
		if note == text then note = nil end
	else
		local subject = Subject(goal)
		if kind == "craft" and goal.untilSkill then
			text = L["Craft %s until your skill is %d"]:format(subject or "", goal.untilSkill)
		elseif subject then
			text = L[KIND_TEXT[kind]]:format(subject)
		elseif BARE_TEXT[kind] and (kind ~= "train" or goal.classTrainer) and (kind ~= "sethome" or goal.nearest) then
			text = L[BARE_TEXT[kind]]
		else
			text, note = note or L["Do this step"], nil
		end
	end
	-- The guide's own note follows.
	if note then text = ("%s (%s)"):format(text, note) end
	if goal.optional then text = L["%s (optional)"]:format(text) end
	return text
end

-- A goal's line in the window: a turn-in with work still open says so,
-- with the quest log's open objective lines under it, and a goal to
-- complete a quest in the log lists its objective lines, the finished
-- ones dimmed. One line (the compact view): the turn-in's note, or the
-- first open objective after the goal.
function M.EntryText(entry, oneLine)
	local text = M.GoalText(entry.goal)
	local lines = entry.openWork or entry.objectives
	if entry.openWork then text = L["%s (objectives still open)"]:format(text) end
	if not lines then return text end
	if oneLine then
		if entry.openWork then return text end
		for _, line in ipairs(lines) do
			if not line.done then return ("%s: %s"):format(text, line.text) end
		end
		return text
	end
	local dim = E:TokenHex(E.tokens.text.secondary)
	for _, line in ipairs(lines) do
		text = text .. "|n" .. (line.done and (dim .. "- " .. line.text .. "|r") or ("- " .. line.text))
	end
	return text
end

-- More about a goal, for its tooltip: lines in the guide's own facts.
local function RewardNames(list)
	local names = {}
	for _, reward in ipairs(list or {}) do
		local name = reward.item and (ItemName(reward.item) or reward.name)
			or reward.spell and (SpellName(reward.spell) or reward.name) or reward.text
		if name then names[#names + 1] = name end
	end
	return #names > 0 and table.concat(names, ", ") or nil
end
M.RewardNames = RewardNames

function M.GoalDetails(goal)
	local lines = {}
	if goal.minLevel then lines[#lines + 1] = L["From level %d."]:format(goal.minLevel) end
	if goal.group == true then
		lines[#lines + 1] = L["Best done in a group."]
	elseif goal.group then
		lines[#lines + 1] = L["Best done in a group of %d."]:format(goal.group)
	end
	local choose = RewardNames(goal.choose)
	if choose then lines[#lines + 1] = L["Choose one: %s"]:format(choose) end
	local rewards = RewardNames(goal.rewards)
	if rewards then lines[#lines + 1] = L["Rewards: %s"]:format(rewards) end
	if goal.xp then lines[#lines + 1] = L["%d experience"]:format(goal.xp) end
	if goal.money and goal.kind ~= "money" and GetMoneyString then lines[#lines + 1] = GetMoneyString(goal.money) end
	if goal.optional then lines[#lines + 1] = L["Optional: it never holds the step up."] end
	if goal.map and not OwnPoint(goal) then lines[#lines + 1] = L["No waypoint: the guide's coordinates for this map are not confirmed yet."] end
	return lines
end

---------------------------------------------------------------------------
-- What the window shows: one table, built on each change
---------------------------------------------------------------------------
-- state: "off", the data states, "choose" (no guide yet), "broken",
-- "finished" or "step".
function M:View()
	if not self:IsLive() then return { state = "off" } end
	if not self.data then return { state = self.dataState, text = self:DataStateText() } end
	local guide, record, steps = self:Current()
	if not guide then
		return { state = "choose", suggest = self:Suggest() }
	end
	local view = { guide = guide, record = record, total = #steps }
	if self.migrated and self.migrated.guide == guide.id then
		view.notice = L["This guide was updated. You are at step %d of the new version."]:format(self.migrated.step)
	end
	if record.done then
		view.state = "finished"
		view.suggest = self:NextGuide(guide) or self:Suggest()
		return view
	end
	view.state = "step"
	view.index = record.s
	view.step = steps[record.s]
	view.goals, view.along, view.alongNotes = self:StepGoals(record.s, record, steps)
	view.canUndo = #record.hist > 0
	view.canPrev = self:PrevIndex(record, steps, record.s) ~= nil
	return view
end

---------------------------------------------------------------------------
-- Provider, start and stop
---------------------------------------------------------------------------
function M:IsLive()
	return self.active and self.started and true or false
end

local EVENTS = {
	QUEST_ACCEPTED = "Queue", QUEST_TURNED_IN = "Queue", QUEST_REMOVED = "Queue", QUEST_LOG_UPDATE = "Queue",
	UNIT_QUEST_LOG_CHANGED = "Queue", BAG_UPDATE_DELAYED = "Queue", PLAYER_LEVEL_UP = "Queue",
	PLAYER_MONEY = "Queue", UPDATE_FACTION = "Queue", SKILL_LINES_CHANGED = "Queue",
	LEARNED_SPELL_IN_SKILL_LINE = "Queue",
}

-- The flight master's map opened while a "get the flight path" goal is
-- the current one: the game learned the flight path at that moment.
function M:OnTaxiMap()
	local guide, record, steps = self:Current()
	if not guide or record.done then return end
	for _, goal in ipairs(steps[record.s].goals) do
		if goal.kind == "getfp" then record.tick[record.s .. ":" .. goal.index] = true end
	end
	self:Evaluate()
end

-- A character at the level cap with no guide in use gets nothing until it
-- asks for a guide: the Journal's Guides page stays there and loads the
-- data when it opens, and starting a guide (or /eui eldostar, or Show the
-- window) wakes the rest. Below the cap, or with a guide in use, Eldostar
-- wakes at once.
function M:Waiting()
	return self:IsLive() and not self.awake
end

function M:WakeWanted()
	if Store().guide ~= nil then return true end
	return not E:AtMaxLevel()
end

function M:Start()
	if self.started then return end
	self.started = true
	self:RegisterPicker()
	if self:WakeWanted() then self:Wake() end
end

-- Shows the window on the player's word, waking Eldostar if it waits.
function M:ShowNow()
	Store().hidden = nil
	self:Wake()
	self:ShowWindow()
end

-- The events, the data, the window and the waypoint.
function M:Wake()
	if self.awake or not self:IsLive() then return end
	self.awake = true
	for event, method in pairs(EVENTS) do
		self:RegisterEvent(event, function() M[method](M) end)
	end
	self:RegisterEvent("TAXIMAP_OPENED", function() M:OnTaxiMap() end)
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() M:Queue() end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() M:Queue() end)
	-- Quest givers and spawns come once the Loot Guide's data is there.
	local LG = E.LootGuide
	if LG and LG.On then
		LG:On("eldostar", function(changed)
			if changed.data then M:UpdateWaypoint() end
		end)
	end
	self:LoadData()
	self:ShowWindow()
	self:Evaluate()
end

function M:Stop()
	if not self.started then return end
	self.started = false
	if self.awake then
		self.awake = false
		for event in pairs(EVENTS) do self:UnregisterEvent(event) end
		for _, event in ipairs({ "TAXIMAP_OPENED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
			self:UnregisterEvent(event)
		end
		local LG = E.LootGuide
		if LG and LG.Off then LG:Off("eldostar") end
	end
	E.Ticker:Unsubscribe("Eldostar:arrive")
	self:UpdateSeenWatch()
	E:CancelOutOfCombat("Eldostar:load")
	self:ClearWaypoint()
	self:UnregisterPicker()
	self:HideWindow()
end

-- Starts or stops with the provider choice (E:GuideProvider). The data is
-- kept once loaded: the game cannot unload an addon.
function M:UpdateProvider()
	self.lastProvider = E:GuideProvider()
	local live = self.active and self.lastProvider == "eldostar"
	if live then self:Start() else self:Stop() end
end

-- Something changed: the window, the waypoint and the arrival watch.
function M:Changed(soft)
	if not self:IsLive() then return end
	self:Refresh(soft)
	if self.awake then
		self:UpdateWaypoint()
		self:UpdateArrivalWatch()
		self:UpdateSeenWatch()
	end
	if self.RefreshPicker then self:RefreshPicker() end
end

function M:Refresh()
	if self.UpdateWindow then self:UpdateWindow() end
end

function M:OnEnable()
	self:UpdateProvider()
end

function M:OnDisable()
	self:Stop()
end

function M:OnProfileChanged()
	if not self.active then return end
	-- A new pick also reaches the other guide on the guide spot.
	if E:GuideProvider() ~= self.lastProvider then
		E:GuideProviderChanged()
	else
		self:UpdateProvider()
	end
	self:ApplyLook()
	self:Changed()
end

E:AddCommand("eldostar", "[show | hide | guides]  the Eldostar guide window, or the guide list in the Journal", function(arg)
	arg = strtrim((arg or ""):lower())
	if not M.active then
		E:Print(E:ModuleOffHint("Eldostar"))
		return
	end
	if not M:IsLive() then
		E:Print(E:GuideProviderStatus())
		return
	end
	if arg == "guides" then
		if not M:OpenPicker() then E:Print(L["The guide list is in the Journal, under My Adventure. Turn My Adventure on to browse the guides."]) end
		return
	end
	local store = Store()
	if arg == "hide" or (arg == "" and M.awake and not store.hidden) then
		store.hidden = true
		M:ShowWindow()
	else
		M:ShowNow()
	end
end)
