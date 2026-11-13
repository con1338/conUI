-- Story bank: every beat's definition and its Ledger line (the short row
-- voice: digits, game nouns, no period). English only; plain strings.
--
-- Portions adapted from Forever Journal by Ugge Zen, MIT License (see THIRD_PARTY_NOTICES.md):
-- the row texts of its 16 line kinds ("Reached level N in X",
-- "Died in X", "First time in X", "Defeated X", "Found X", "X now counts you
-- as Y", "Learned X (Rank N)", "Recipe: X", "Became a student of X", "X reached
-- N", "Mastered X", "New mount: X", "New companion: X", "Re-specced N talent
-- points", "Flight path: X", "Goal reached: X", "New chapter: X", "The journal
-- begins in X", "A quiet chapter."), with EldoUI's grammar fixes (articles,
-- plurals).
--
-- A beat: B:Define(id, { kind, ledger = { variants }, with = "companions",
--   common = true (6+ prose variants per tone), meta = true (a statement
--   about the record, present tense), sub = function(fact, Grammar) -> row
--   sub-line }). The prose tones (Banks/Chronicle.lua, Banks/Bard.lua) add
--   their variants by id; "<id>_with" variants are used when the companions
--   slot resolves and the "Name companions" setting is on.
local _, E = ...

local B = E.Story.Banks

local function BossSub(f)
	local kills = f.v.kills or 1
	if f.kind == "bossagain" then return nil end
	if kills > 1 then
		local again = kills - 1
		return again == 1 and "first kill · killed once since" or ("first kill · killed %d times since"):format(again)
	end
	return f.v.firstKnown and "first kill" or "first kill since the journal began"
end

local function PaceSub(f, G)
	return G.Duration(f.v.took, "ledger") .. ", " .. f.v.pace
end

-- The base line kinds ----------------------------------------------------------------
B:Define("level", { kind = "level", common = true,
	ledger = { "Reached level {level} {zone:in}", "Reached level {level} in an unknown place" } })
B:Define("zone", { kind = "zone", common = true, ledger = { "New chapter: {zone:head}" } })
B:Define("zone_begin", { kind = "zone", meta = true, ledger = { "The journal begins {zone:in}" } })
B:Define("dungeon", { kind = "dungeon", with = "companions", common = true,
	ledger = { "First time {instance:in}{since?}" }, sub = function(f, G) return f.v.duration and G.Duration(f.v.duration, "ledger") end })
B:Define("death", { kind = "death", common = true, ledger = { "Died {where}" } })
B:Define("boss", { kind = "boss", ledger = { "Defeated {boss}" }, sub = BossSub })
B:Define("loot", { kind = "loot", ledger = { "Found {item}" } })
B:Define("loot_epic", { kind = "loot", ledger = { "Found {item}" }, sub = function() return "first epic" end })
B:Define("rep", { kind = "rep", ledger = { "{faction:start} now {counts} you as {standing}" } })
B:Define("spell", { kind = "spell", ledger = { "Learned {spell}{rank?}" } })
B:Define("recipe", { kind = "recipe", ledger = { "Recipe: {recipe}" } })
B:Define("profession", { kind = "profession", ledger = { "Became a student of {profession}" } })
B:Define("skill", { kind = "skill", ledger = { "{profession} reached {skill}" } })
B:Define("skill_master", { kind = "skill", ledger = { "Mastered {profession}" } })
B:Define("mount", { kind = "mount", ledger = { "New mount: {mount}" } })
B:Define("mount_first", { kind = "mount", ledger = { "New mount: {mount}" }, sub = function() return "first mount" end })
B:Define("pet", { kind = "pet", ledger = { "New companion: {pet}" } })
B:Define("respec", { kind = "respec", ledger = { "Re-specced {n:count:talent point}" } })
B:Define("flight", { kind = "flight", ledger = { "Flight path: {place:head}", "New flight path" } })
B:Define("goal", { kind = "goal", ledger = { "Goal reached: {goal}" } })

-- New kinds from EldoUI's sources ---------------------------------------------------------
B:Define("raid", { kind = "raid", with = "companions", ledger = { "First raid{since?}: {instance:head}" } })
B:Define("raidboss", { kind = "raidboss", ledger = { "First raid boss{since?}: {boss:start}" }, sub = BossSub })
B:Define("bossagain", { kind = "bossagain", ledger = { "{boss:start} fell again · {kills:count:kill} in all" } })
B:Define("run", { kind = "run", with = "companions", common = true,
	ledger = { "Ran {instance:bare} again · {duration:ledger}", "Ran {instance:bare} again" } })
B:Define("runs", { kind = "runs", ledger = { "Ran {instance:bare} {n:times} · {levels}" } })
B:Define("pvpwin", { kind = "pvpwin", ledger = { "Won {battleground:bare}" } })
B:Define("pvploss", { kind = "pvploss", ledger = { "Lost {battleground:bare}" } })
B:Define("quest", { kind = "quest", common = true, ledger = { "Handed in {quest:q}" } })
B:Define("questchain", { kind = "questchain", ledger = { "Finished the quest chain {chain:q}" } })
B:Define("dungeonquest", { kind = "dungeonquest", ledger = { "Dungeon quest: {quest:q} ({instance:head})" } })
B:Define("groupquest", { kind = "groupquest", ledger = { "Handed in {quest:q} with {companions}", "Handed in {quest:q}" } })
B:Define("questburst", { kind = "questburst", ledger = { "{n:count:quest} at level {level}" } })
B:Define("attunestep", { kind = "attunestep", ledger = { "{attunement}: step {step} of {total} done" } })
B:Define("attuned", { kind = "attuned", ledger = { "Attuned to {instance:bare}" } })
B:Define("challenge", { kind = "challenge", ledger = { "Legacy challenge: {challenge}" } })
B:Define("legacylevel", { kind = "legacylevel", ledger = { "Legacy level {n}" } })
B:Define("title", { kind = "title", ledger = { "Earned the title {title}" } })
B:Define("explored", { kind = "explored", ledger = { "Explored all of {zone:bare}" } })
B:Define("subzone", { kind = "subzone", ledger = { "First steps {subzone:auto}" } })
B:Define("hearth", { kind = "hearth", ledger = { "Hearthstone set to {place:bare}" } })
B:Define("gear", { kind = "gear", ledger = { "Equipped {item} · +{gain} item score", "Equipped {item}" } })
B:Define("wish", { kind = "wish", ledger = { "From your wishlist: {item}" } })
B:Define("met", { kind = "met", ledger = { "Met {fellow} ({fclass}) {zone:in}", "Met {fellow} {zone:in}", "Met {fellow}" } })
B:Define("together", { kind = "together", ledger = { "{duration:ledger} with {fellow} so far" } })
B:Define("rested", { kind = "rested", ledger = { "Came back well rested · {pct} of a level", "Came back well rested" } })
B:Define("gather", { kind = "gather", ledger = { "{node} ×{n} {zone:in}" } })
B:Define("farm", { kind = "farm", ledger = { "Farmed {zone:bare} for {duration:ledger} · {gold:ledger}", "Farmed {zone:bare} for {duration:ledger}" } })
B:Define("rare", { kind = "rare", ledger = { "Saw {rare}" } })
B:Define("cinematic", { kind = "cinematic", ledger = { "Watched the {zone:core} cinematic" } })
B:Define("guild", { kind = "guild", ledger = { "Joined {guild}" } })
B:Define("note", { kind = "note", ledger = { "{note}" } })

-- Derived kinds ----------------------------------------------------------------------------
B:Define("maxlevel", { kind = "maxlevel", ledger = { "Reached level 60 after {played:ledger} of play", "Reached level 60" } })
B:Define("deathstreak", { kind = "deathstreak", ledger = { "{n:count:death} in {window:ledger}" },
	sub = function(f, G)
		local where = (f.s and f.z and f.s ~= f.z) and (f.s .. ", " .. G.Place(f.z, "head", true)) or G.Place(f.s or f.z or "", "head", true)
		local range = f.v.start and f.v.stop and (G.Date(f.v.start, "short") .. ", " .. (date or os.date)(G.utc and "!%H:%M" or "%H:%M", f.v.start)
			.. "-" .. (date or os.date)(G.utc and "!%H:%M" or "%H:%M", f.v.stop))
		if where and range then return where .. " · " .. range end
		return where or range
	end })
B:Define("deathless", { kind = "deathless", ledger = { "{n:count:level} without a death · {levels}" } })
B:Define("fast", { kind = "fast", ledger = { "Level {level} took {took:ledger}, faster than usual" }, sub = PaceSub })
B:Define("fast_rested", { kind = "fast", ledger = { "Level {level} took {took:ledger}, faster than usual{rested?}" }, sub = PaceSub })
B:Define("slow", { kind = "slow", ledger = { "Level {level} took {took:ledger}, slower than usual" }, sub = PaceSub })
B:Define("topfellow", { kind = "topfellow", ledger = { "Most time with {fellow}: {duration:ledger}" } })
B:Define("homezone", { kind = "homezone", ledger = { "{zone:head} · {share} of the chapter" } })
B:Define("crossed", { kind = "crossed", ledger = { "Crossed to {continent:bare} by {vehicle}", "Crossed to {continent:bare}" } })
B:Define("gap", { kind = "gap", ledger = { "{days:count:day} away" } })
B:Define("unrecorded", { kind = "unrecorded", meta = true, ledger = { "{duration:ledger} of play not recorded" } })
B:Define("sourceoff", { kind = "sourceoff", meta = true, ledger = { "{source} not recorded for {levels}" } })
B:Define("rolled", { kind = "rolled", meta = true, ledger = { "Kept as a summary for {levels}: {spells:count:spell} learned, {finds:count:item} found" } })

-- Chapter structure -------------------------------------------------------------------------
B:Define("chdeaths", { kind = "chdeaths", common = true, ledger = { "{n:count:death} {zone:in}", "{n:count:death}" } })
B:Define("chquests", { kind = "chquests", ledger = { "{zone:head}: {n:count:quest} handed in", "{n:count:quest} handed in" } })
B:Define("chclose", { kind = "chclose", common = true, ledger = { "{levels} · {played:ledger}" } })
B:Define("chclose_now", { kind = "chclose", ledger = { "{levels} so far · {played:ledger}" } })
B:Define("before", { kind = "before", meta = true,
	ledger = { "Before the journal: the game remembers {quests:count:quest} completed and {played:ledger} played",
		"Before the journal: the game remembers {quests:count:quest} completed" } })
B:Define("eraopen", { kind = "eraspan", ledger = { "{levels} · {played:ledger} · mostly {zone:in}", "{levels} · {played:ledger}" } })
B:Define("summary", { kind = "totals", meta = true, ledger = { "Since level {since}: {gold:ledger} earned" } })
B:Define("gamecount", { kind = "gametotals", meta = true,
	ledger = { "The game counts {quests:count:quest} completed and {deaths:count:death}", "The game counts {quests:count:quest} completed" } })

-- The Journey's level chapters: opening, closing and the quiet chapter.
B:Define("lvopen_home", { kind = "lvhome", common = true, ledger = { "Mostly {zone:in}" } })
B:Define("lvopen_deathstreak", { kind = "deathstreak", ledger = { "{n:count:death} in {window:ledger} {subzone:auto}", "{n:count:death} in {window:ledger}" } })
B:Define("lvopen_boss", { kind = "boss", ledger = { "{boss:start} fell" } })
B:Define("lvopen_raidboss", { kind = "raidboss", ledger = { "A raid boss fell: {boss:bare}" } })
B:Define("lvopen_dungeon", { kind = "dungeon", ledger = { "New dungeon: {instance:head}" } })
B:Define("lvopen_raid", { kind = "raid", ledger = { "New raid: {instance:head}" } })
B:Define("lvopen_loot", { kind = "loot", ledger = { "{item}" } })
B:Define("lvopen_mount", { kind = "mount", ledger = { "{mount}" } })
B:Define("lvopen_zone", { kind = "zone", ledger = { "{zone:head}" } })
B:Define("lvopen_rep", { kind = "rep", ledger = { "{faction:start}: {standing}" } })
B:Define("lvopen_attuned", { kind = "attuned", ledger = { "Attuned to {instance:bare}" } })
B:Define("lvopen_gap", { kind = "gap", ledger = { "Back after {days:count:day}" } })
B:Define("lvopen_title", { kind = "title", ledger = { "{title}" } })
B:Define("lvopen_maxlevel", { kind = "maxlevel", ledger = { "Level 60" } })
B:Define("lvopen_crossed", { kind = "crossed", ledger = { "To {continent:bare}" } })
B:Define("lvopen_runs", { kind = "runs", ledger = { "{instance:start} {n:times}" } })
B:Define("lvopen_slow", { kind = "slow", ledger = { "Slow level: {took:ledger}" } })
B:Define("lvopen_fast", { kind = "fast", ledger = { "Fast level: {took:ledger}" } })
B:Define("lvclose", { kind = "level", common = true, ledger = { "Level {next} · {nexttook:ledger} later{pace?}" } })
B:Define("lvclose_moved", { kind = "level", ledger = { "Level {next} · {nexttook:ledger} later {zone:in}{pace?}" } })
B:Define("lvclose_now", { kind = "level", ledger = { "{took:ledger} at level {level} so far" } })
B:Define("quiet", { kind = "level", common = true, ledger = { "A quiet chapter." } })

-- Titles. Story chapters take the lead's place; eras take the era's main
-- zone (Render fills {place:mode} with the plain place forms).
B:Tone("ledger", {
	chtitle = { "{place:head}" },
	chtitle_again = { "{place:head}, continued" },
	era1 = { "{place:head}: first steps", "Home ground" },
	era2 = { "The road {place:to}", "The road out" },
	era3 = { "The {place:core} road", "Into the middle lands" },
	era4 = { "The thirties: {place:head}", "Wild country" },
	era5 = { "The forties: {place:head}", "Far frontiers" },
	era6 = { "The last climb" },
	era7 = { "Sixty" },
})
