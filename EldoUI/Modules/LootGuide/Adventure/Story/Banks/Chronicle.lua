-- Story bank: Chronicle, the default tone. The
-- adventurer's log: sober, third person, past tense, written after the fact.
-- No color words, no feelings, no exclamations. Numbers: words for zero to
-- twelve through the slots, digits from 13; levels always digits. One
-- setting phrase (the zone epithet) per chapter at most. English only, plain
-- strings, our own text. Slots are described in Story/Render.lua.
local _, E = ...

E.Story.Banks:Tone("chronicle", {
	-- Levels and places -----------------------------------------------------------
	level = {
		"{name} reached level {level} {zone:in}.",
		"Level {level} came {zone:in}.",
		"{name:poss} level {level} came {zone:in}.",
		"{name} was {zone:in} on reaching level {level}.",
		"It was {zone:in} that {name} reached level {level}.",
		"{zone:start} was where {name} reached level {level}.",
		"Level {level} arrived while {name} was {zone:in}.",
	},
	maxlevel = {
		"{name} reached level 60 {zone:in} on {date}, after {played} of play.",
		"On {date}, {name} reached level 60 {zone:in}; it had taken {played} of play.",
		"Level 60 came {zone:in} on {date}, after {played} of play.",
		"After {played} of play, {name} reached level 60 {zone:in}.",
	},
	zone = {
		"{name} came {zone:to} at level {level}.",
		"At level {level}, {name} arrived {zone:in}.",
		"{name} first came to {zone:epithet} at level {level}.",
		"Level {level} brought {name} {zone:to}.",
		"{name} reached {zone:bare} at level {level}, on {date}.",
		"The road led {zone:to} at level {level}.",
		"At level {level}, {name} came to {zone:epithet}.",
		"{name} set foot {zone:in} {firsttime} at level {level}.",
		"{name} also reached {zone:bare}.{if:samelevel}",
		"The road then led {zone:to}.{if:samelevel}",
	},
	zone_begin = {
		"At level {level}, the journal found {name}, {me:desc}, in {zone:epithet}.",
		"At level {level}, the journal found {name} {zone:in}.",
		"The journal opens at level {level}, with {name} {zone:in}.",
		"The record begins {zone:in} on {date}, with {name} at level {level}.",
	},
	subzone = {
		"{name} first set foot {subzone:auto} at level {level}.",
		"At level {level}, the road passed {subzone:auto}.",
		"{subzone:start} was new ground for {name} at level {level}.",
		"{name} also passed {subzone:auto}.{if:samelevel}",
	},
	explored = {
		"By level {level}, {name} had explored all of {zone:bare}.",
		"Every corner of {zone:bare} was on the map by level {level}.",
		"{name} finished exploring {zone:bare} at level {level}.",
	},
	crossed = {
		"At level {level}, {name} crossed {continent:to}.",
		"The road crossed {continent:to} at level {level}, by {vehicle}.",
		"Level {level} saw the road cross {continent:to}, arriving {zone:in}.",
		"{name} crossed {continent:to} at level {level} and arrived {zone:in}.",
		"{name} then crossed {continent:to}.{if:samelevel}",
	},
	homezone = {
		"{zone:start} held {share} of the chapter's play.",
		"Of the chapter's play, {share} was spent {zone:in}.",
		"{zone:start} kept {share} of these levels' play.",
		"{zone:start} took {share} of the chapter's play.",
	},
	hearth = {
		"At level {level}, {name} set the hearthstone to {place:bare}.",
		"The hearthstone was bound to {place:bare} at level {level}.",
		"{name} made {place:bare} home for the hearthstone at level {level}.",
		"The hearthstone was then set to {place:bare}.{if:samelevel}",
	},
	flight = {
		"At level {level}, {name} learned the flight path {place:at}.",
		"A new flight path {place:at} was learned at level {level}.",
		"{name} added the flight path {place:at} at level {level}.",
		"{name} also learned the flight path {place:at}.{if:samelevel}",
	},

	-- Dungeons, raids and bosses ----------------------------------------------------------
	dungeon = {
		"At level {level}, {name} entered {instance:bare} {firsttime}{forever?}.",
		"{name} went into {instance:bare} at level {level}, {afirst}.",
		"The first dungeon run came at level {level}: {instance:bare}.{if:firstdungeon}",
		"{name} entered {instance:bare} {firsttime} at level {level}; the run took {duration}.",
		"Level {level} took {name} into {instance:bare} {firsttime}{forever?}.",
		"{instance:start} was a new dungeon for {name} at level {level}{forever?}.",
		"At level {level}, {name} made a first run through {instance:bare}.",
		"{name} then entered {instance:bare} {firsttime}.{if:samelevel}",
	},
	dungeon_with = {
		"At level {level}, {name} entered {instance:bare} {firsttime}, with {companions}.",
		"{name} went into {instance:bare} at level {level} with {companions}, {afirst}.",
		"With {companions}, {name} entered {instance:bare} {firsttime} at level {level}.",
		"Level {level} took {name} into {instance:bare} {firsttime}, with {companions}; the run took {duration}.",
		"Then, with {companions}, {name} entered {instance:bare} {firsttime}.{if:samelevel}",
	},
	raid = {
		"At level {level}, {name} went raiding {instance:in} {firsttime}.",
		"{name:poss} first raid was {instance:bare}, at level {level}.{if:firstraid}",
		"Level {level} took {name} raiding {instance:in}, {afirst}.",
		"{name} went into {instance:bare} {firsttime} at level {level}.",
	},
	raid_with = {
		"At level {level}, {name} entered {instance:bare} {firsttime}, with {companions}.",
		"With {companions}, {name} went raiding {instance:in} {firsttime}.",
		"{name} entered {instance:bare} at level {level} with {companions}, {afirst}.",
	},
	run = {
		"{name} ran {instance:bare} again at level {level}.",
		"At level {level}, {name} went back into {instance:bare}.",
		"Another run through {instance:bare} came at level {level}; it took {duration}.",
		"{instance:start} saw another run at level {level}.",
		"{name} returned to {instance:bare} at level {level}.",
		"Level {level} brought another run through {instance:bare}.",
		"{name} then ran {instance:bare} again.{if:samelevel}",
	},
	run_with = {
		"{name} ran {instance:bare} again at level {level}, with {companions}.",
		"At level {level}, {name} went back into {instance:bare} with {companions}.",
		"With {companions}, {name} returned to {instance:bare} at level {level}.",
		"{name} then ran {instance:bare} again with {companions}.{if:samelevel}",
	},
	runs = {
		"{name} went into {instance:bare} {n:times} {range}{with?}.",
		"{instance:start} was run {n:times} {range}{with?}.",
		"{range}, {name} ran {instance:bare} {n:times}{with?}.",
		"The journal counts {n:times} through {instance:bare} {range}.",
	},
	boss = {
		"{boss:start} fell {instance:in} at level {level}, {firstkill}.",
		"At level {level}, {name} defeated {boss:bare} {instance:in}.",
		"{name} defeated {boss:bare} {firsttime} at level {level}.",
		"{instance:start} saw {boss:bare} fall at level {level}.",
		"{boss:start} was defeated {instance:in} at level {level}.",
		"{name} then defeated {boss:bare} {instance:in}.{if:samelevel}",
	},
	raidboss = {
		"{boss:start} fell {instance:in} at level {level}, the first raid boss of the journey.{if:firstraidboss}",
		"At level {level}, {name} defeated the raid boss {boss:bare} {instance:in} {firsttime}.",
		"{name:poss} first raid boss was {boss:bare}, {instance:in}.{if:firstraidboss}",
		"{boss:start} was defeated {instance:in} on {date}.",
	},
	bossagain = {
		"{boss:start} fell again {instance:in}; the journal counts {kills:count:kill} in all.",
		"{name} defeated {boss:bare} again at level {level}.",
		"Another kill of {boss:bare} came at level {level}, {kills:count:kill} in all.",
	},
	attunestep = {
		"At level {level}, {name} finished step {step} of {total} for {attunement}.",
		"{attunement} moved on at level {level}: step {step} of {total} was done.",
		"Step {step} of {total} for {attunement} was done at level {level}.",
		"Step {step} of {total} for {attunement} was also done.{if:samelevel}",
	},
	attuned = {
		"On {date}, {name} was attuned to {instance:bare}.",
		"At level {level}, {name} became attuned to {instance:bare}.",
		"The attunement to {instance:bare} was done on {date}.",
		"{name} was attuned to {instance:bare} at level {level}.",
	},

	-- Deaths ----------------------------------------------------------------------------------
	death = {
		"{name} died at level {level}, {where}.",
		"At level {level}, {name} died {where}.",
		"A death came at level {level}, {where}.",
		"{name} died {where} at level {level}.",
		"Level {level} brought a death, {where}.",
		"The journal records a death {where}, at level {level}.",
		"In the same level, {name} died {where}.{if:samelevel}",
	},
	chdeaths = {
		"{name} died {n:times} {zone:in} in these levels.",
		"These levels held {n:count:death} {zone:in}.",
		"{name} died {n:times} in this chapter.",
		"The chapter counts {n:count:death}, all {zone:in}.{if:many}",
		"{zone:start} saw {name} die {n:times}.",
		"The journal records {n:count:death} in this chapter.",
		"In these levels, {name} died {n:times}.",
	},
	deathstreak = {
		"On the {daypart} of {date}, {name} died {n:times} in {window} {subzone:auto}.",
		"{name} died {n:times} in {window} {subzone:auto}, on the {daypart} of {date}.",
		"On {date}, {name} died {n:times} in {window} {zone:in}.",
		"{subzone:start} saw {n:count:death} in {window} on {date}.",
		"Within {window} on {date}, {name} died {n:times} {zone:in}.",
	},
	deathless = {
		"{name} went {n:count:level} without a death, {range}.",
		"No death came for {n:count:level}, {range}.",
		"{range}, {name} did not die once.",
		"The journal records no death for {n:count:level}, {range}.",
	},

	-- Finds, gear and keepsakes --------------------------------------------------------------
	loot = {
		"At level {level}, {item} dropped {place:in}.",
		"{name} found {item} {place:in} at level {level}.",
		"{item} came to {name} at level {level}, {place:in}.",
		"Level {level} brought {item}, found {place:in}.",
		"{name} also found {item} {place:in}.{if:samelevel}",
	},
	loot_epic = {
		"At level {level}, {item} dropped {place:in}, {name:poss} first epic.",
		"{name:poss} first epic, {item}, came {place:in} at level {level}.",
		"{item} was found {place:in} at level {level}: the first epic of the journey.",
	},
	gear = {
		"At level {level}, {name} equipped {item}, an upgrade of {gain} item score.",
		"{name} put on {item} at level {level}.",
		"{item} was equipped at level {level}, {gain} item score better than before.",
		"{name} also put on {item}.{if:samelevel}",
	},
	wish = {
		"At level {level}, {item} came off the wishlist and into the bags.",
		"{name} got {item} from the wishlist at level {level}.",
		"A wishlist item, {item}, was {name:poss} at level {level}.",
		"{item} also came off the wishlist.{if:samelevel}",
	},
	mount = {
		"At level {level}, {name} gained a new mount: {mount:a}.",
		"{mount:a} joined the stable at level {level}.",
		"{name:poss} new mount at level {level} was {mount:a}.",
		"{mount:a} also joined the stable.{if:samelevel}",
	},
	mount_first = {
		"{name:poss} first mount, {mount:a}, came on {date} at level {level}, {zone:in}.",
		"At level {level}, {name} gained a first mount: {mount:a}.",
		"The first mount of the journey, {mount:a}, came at level {level}.",
	},
	pet = {
		"At level {level}, {name} gained a new pet, {pet:a}.",
		"A new pet joined {name} at level {level}: {pet:a}.",
		"{name:poss} new pet at level {level} was {pet:a}.",
		"A new pet, {pet:a}, also joined {name}.{if:samelevel}",
	},
	title = {
		"At level {level}, {name} earned the title {title}.",
		"{name} earned the title {title} on {date}.",
		"The title {title} was earned at level {level}.",
		"{name} also earned the title {title}.{if:samelevel}",
	},
	note = {
		"A note from level {level} reads {note}.",
		"At level {level}, {name} pinned a note: {note}.",
		"The journal keeps a note from level {level}: {note}.",
		"The journal also keeps a note from then: {note}.{if:samelevel}",
	},
	goal = {
		"At level {level}, {name} reached the goal {goal}.",
		"The goal {goal} was met at level {level}.",
		"{name} finished the goal {goal} on {date}.",
		"{name} also reached the goal {goal}.{if:samelevel}",
	},

	-- Spells, professions and reputation ----------------------------------------------------------
	spell = {
		"At level {level}, {name} learned {spell}{rank?}.",
		"{name} learned {spell}{rank?} at level {level}.",
		"{spell}{rank?} was learned at level {level}.",
		"{name} also learned {spell}{rank?}.{if:samelevel}",
	},
	recipe = {
		"At level {level}, {name} learned the recipe {recipe}.",
		"{name} added the recipe {recipe} at level {level}.",
		"The recipe {recipe} was learned at level {level}.",
		"{name} also learned the recipe {recipe}.{if:samelevel}",
	},
	profession = {
		"At level {level}, {name} took up {profession:lower}.",
		"{name} became a student of {profession:lower} at level {level}.",
		"Level {level} saw {name} take up {profession:lower}.",
		"{name} also took up {profession:lower}.{if:samelevel}",
	},
	skill = {
		"{profession} reached {skill} at level {level}.",
		"At level {level}, {name:poss} {profession:lower} reached {skill}.",
		"{name} raised {profession:lower} to {skill} at level {level}.",
		"In the same level, {profession:lower} reached {skill}.{if:samelevel}",
	},
	skill_master = {
		"At level {level}, {name} mastered {profession:lower}.",
		"{name} mastered {profession:lower} on {date}.",
		"{profession} was mastered at level {level}.",
		"In the same level, {name} mastered {profession:lower}.{if:samelevel}",
	},
	respec = {
		"At level {level}, {name} re-specced {n:count:talent point}.",
		"{name} spent {n:count:talent point} anew at level {level}.",
		"Level {level} brought a respec of {n:count:talent point}.",
	},
	rep = {
		"At level {level}, {faction:bare} counted {name} as {standing}.",
		"{faction:start} counted {name} as {standing} at level {level}.",
		"{name} reached {standing} with {faction:bare} at level {level}.",
		"Standing with {faction:bare} reached {standing} at level {level}.",
		"In the same level, {faction:bare} came to count {name} as {standing}.{if:samelevel}",
	},
	challenge = {
		"On {date}, {name} completed the Legacy challenge {challenge}.",
		"The Legacy challenge {challenge} was done on {date}.",
		"{name} finished the Legacy challenge {challenge} at level {level}.",
	},
	legacylevel = {
		"{name:poss} Legacy reached level {n} on {date}.",
		"At level {level}, {name:poss} Legacy reached level {n}.",
		"Legacy level {n} came on {date}.",
	},

	-- Quests --------------------------------------------------------------------------------------------
	quest = {
		"{name} handed in {quest} {zone:in} at level {level}.",
		"At level {level}, {name} handed in {quest} {zone:in}.",
		"In {zone:bare}, {quest} was handed in at level {level}.",
		"Level {level} saw {quest} completed {zone:in}.",
		"{name} finished {quest} at level {level}.",
		"The quest {quest} was done at level {level}, {zone:in}.",
		"{name} also handed in {quest} {zone:in}.{if:samelevel}",
	},
	questchain = {
		"At level {level}, {name} finished the quest chain {chain}.",
		"The quest chain {chain} ended at level {level} with {quest}.",
		"{name} completed the quest chain {chain} at level {level}.",
		"{name} also finished the quest chain {chain}.{if:samelevel}",
	},
	dungeonquest = {
		"At level {level}, {name} handed in {quest}, a quest for {instance:bare}.",
		"{name} finished the {instance:core} quest {quest} at level {level}.",
		"The dungeon quest {quest} for {instance:bare} was done at level {level}.",
		"{name} also handed in {quest}, a quest for {instance:bare}.{if:samelevel}",
	},
	groupquest = {
		"{name} handed in {quest} with {companions} at level {level}.",
		"At level {level}, {name} handed in {quest}, with {companions}.",
		"{quest} was handed in at level {level}, with {companions}.",
		"{name} then handed in {quest} with {companions}.{if:samelevel}",
	},
	questburst = {
		"At level {level}, {name} handed in {n:count:quest}.",
		"Level {level} held {n:count:quest} handed in.",
		"{name} finished {n:count:quest} at level {level}, more than at the levels around it.",
	},
	chquests = {
		"These levels counted {n:count:quest} handed in, mostly {zone:in}.",
		"{name} handed in {n:count:quest} in this chapter.",
		"{zone:start} saw {n:count:quest} handed in during these levels.",
		"In these levels, {n:count:quest} were handed in.",
	},

	-- Companions and other players --------------------------------------------------------------
	met = {
		"At level {level}, {zone:in}, {name} met {fellow}, {fellow:desc}.",
		"{name} met {fellow}, {fellow:desc}, {zone:in} at level {level}.",
		"{fellow} joined {name} {zone:in} at level {level}.",
		"Level {level} brought a new companion {zone:in}: {fellow}.",
		"{name} also met {fellow}, {fellow:desc}.{if:samelevel}",
		"{fellow}, {fellow:desc}, was met there too.{if:samelevel}",
	},
	together = {
		"By level {level}, {name} and {fellow} had spent {duration} together.",
		"{fellow} had been at {name:poss} side for {duration} by level {level}.",
		"By level {level}, {fellow} and {name} had been on the road together for {duration}.",
		"By then, {name} and {fellow} had spent {duration} together.{if:samelevel}",
	},
	topfellow = {
		"{fellow} spent more time with {name} than anyone else: {duration}.",
		"No companion came along more often than {fellow}, with {duration} together.",
		"Of all the companions, {fellow} spent the most time with {name}: {duration}.",
	},
	guild = {
		"At level {level}, {name} joined {guild}.",
		"{name} became a member of {guild} on {date}.",
		"{guild} took {name} in at level {level}.",
		"{name} also joined {guild}.{if:samelevel}",
	},
	pvpwin = {
		"At level {level}, {name} won a battle {battleground:in}.",
		"{name} fought {battleground:in} at level {level} and won.",
		"A win {battleground:in} came at level {level}.",
	},
	pvploss = {
		"At level {level}, {name} fought {battleground:in}; the battle was lost.",
		"{name} lost a battle {battleground:in} at level {level}.",
		"A battle {battleground:in} at level {level} ended in a loss.",
	},

	-- World ------------------------------------------------------------------------------------------
	rare = {
		"At level {level}, {name} saw {rare} {zone:in}.",
		"{rare} was seen {zone:in} at level {level}.",
		"{name} came across {rare} {zone:in} at level {level}.",
		"{name} also saw {rare} {zone:in}.{if:samelevel}",
	},
	gather = {
		"{name} gathered {node} ×{n} {zone:in}.",
		"At level {level}, {name} gathered {node} {zone:in}, {n:times} in all.",
		"{zone:start} gave {name} {node} ×{n}.",
	},
	farm = {
		"{name} farmed {zone:bare} for {duration} and earned {gold}.",
		"At level {level}, {name} spent {duration} farming {zone:in}.",
		"A farming session {zone:in} took {duration} at level {level}.",
	},
	cinematic = {
		"At level {level}, {name} watched the {zone:core} cinematic.",
		"The {zone:core} cinematic played at level {level}.",
		"{name} watched the cinematic of {zone:bare} at level {level}.",
	},
	rested = {
		"At level {level}, {name} came back well rested.",
		"{name} logged in well rested at level {level}.",
		"Level {level} began with a well-rested login.",
	},

	-- Pace and the gaps ------------------------------------------------------------------------------
	fast = {
		"Level {level} took {took}, faster than usual.",
		"{name} spent only {took} at level {level}, faster than usual.",
		"At {took}, level {level} went faster than usual.",
		"Level {level} came and went in {took}, faster than usual.",
	},
	fast_rested = {
		"Level {level} took {took}, faster than usual{rested?}.",
		"{name} spent only {took} at level {level}, faster than usual{rested?}.",
		"At {took}, level {level} went faster than usual{rested?}.",
	},
	slow = {
		"Level {level} took {took}, slower than usual.",
		"{name} spent {took} at level {level}, slower than usual.",
		"At {took}, level {level} went slower than usual.",
		"Level {level} lasted {took}, slower than usual.",
	},
	gap = {
		"Then the journal fell silent: {days:count:day} passed between {startdate} and {stopdate}, at level {level}.",
		"{days:count:day} went by with no play between {startdate} and {stopdate}, at level {level}.",
		"At level {level}, the road paused for {days:count:day}, from {startdate} to {stopdate}.",
		"No page was written for {days:count:day}, between {startdate} and {stopdate}.",
	},
	unrecorded = {
		"{duration} of play went unrecorded at level {level}.",
		"At level {level}, {duration} of play went by without the journal.",
		"The journal missed {duration} of play at level {level}.",
		"In the same level, {duration} of play went unrecorded.{if:samelevel}",
	},
	sourceoff = {
		"{source} were not recorded for {levels}.",
		"For {levels}, the journal kept no record of {source:lower}.",
		"{source} went unrecorded for {levels}.",
	},
	rolled = {
		"The small moments of {levels} are kept as a summary: {spells:count:spell} learned and {finds:count:item} found.",
		"For {levels}, the journal keeps only a summary: {spells:count:spell} learned and {finds:count:item} found.",
		"A summary stands in for the small moments of {levels}: {spells:count:spell} learned and {finds:count:item} found.",
	},

	-- Chapter structure ---------------------------------------------------------------------------------
	chclose = {
		"The chapter closed at level {b} after {played} of play.",
		"These levels took {played} of play in all.",
		"By level {b}, the chapter had taken {played} of play.",
		"{played} of play carried the road through {levels}.",
		"The chapter came to {played} of play, ending at level {b}.",
		"In all, {levels} took {played} of play.",
	},
	chclose_now = {
		"The chapter is still open at level {b}, after {played} of play so far.",
		"So far, these levels have taken {played} of play.",
		"At level {b}, the chapter goes on, with {played} of play behind it.",
	},
	before = {
		"The journal begins at level {level} {zone:in}, on {date}. Of the road before, the game remembers {quests:count:quest} completed and {played} of play; where that road began is not recorded.",
		"Of the road before level {level}, the game remembers {quests:count:quest} completed and {played} of play. Where it began is not recorded.",
		"The game remembers {quests:count:quest} completed before the journal began at level {level}; the rest of that road is not recorded.",
		"Before level {level}, the journal kept no record; the game remembers only {quests:count:quest} completed.",
	},
	eraopen = {
		"{levels} took {played} of play, most of it {zone:in}.",
		"Over {levels}, {played} of play went by, most of it {zone:in}.",
		"These were {levels}: {played} of play, mostly {zone:in}.",
		"{levels} came to {played} of play.",
	},
	summary = {
		"Since level {since}, the journal has counted {gold} earned.",
		"The journal has counted {gold} earned since level {since}.",
		"From level {since} on, {gold} came in, by the journal's count.",
	},
	gamecount = {
		"The game counts {quests:count:quest} completed and {deaths:count:death} in all.",
		"In all, the game counts {quests:count:quest} completed and {deaths:count:death}.",
		"By the game's own count: {quests:count:quest} completed and {deaths:count:death}.",
	},

	-- The Journey's level chapters ---------------------------------------------------------------------
	lvopen_home = {
		"{zone:start} held most of level {level}.",
		"Most of level {level} was spent {zone:in}.",
		"Level {level} stayed mostly {zone:in}.",
		"Level {level} belonged mostly to {zone:bare}.",
		"{zone:start} kept most of level {level}.",
		"For most of level {level}, the road stayed {zone:in}.",
	},
	lvopen_deathstreak = {
		"{n:count:death} in one {daypart} {subzone:auto}.",
		"A hard {daypart} {subzone:auto}: {n:count:death} in {window}.",
		"{n:count:death} in {window} {zone:in}.",
	},
	lvopen_boss = {
		"{boss:start} fell {instance:in}.",
		"A boss kill {instance:in}: {boss:bare}.",
		"{boss:start} was defeated at this level.",
	},
	lvopen_raidboss = {
		"A raid boss fell: {boss:bare}.",
		"{boss:start} fell {instance:in}.",
		"{instance:start} saw {boss:bare} defeated.",
	},
	lvopen_dungeon = {
		"A new dungeon: {instance:bare}.",
		"{instance:start} was new to the journal at this level.",
		"{instance:start} was entered at this level, {firsttime}.",
	},
	lvopen_raid = {
		"A new raid: {instance:bare}.",
		"{instance:start} was entered {firsttime}.",
		"Raiding {instance:in} began at this level.",
	},
	lvopen_loot = {
		"{item} came at this level.",
		"This level brought {item}.",
		"A find at this level: {item}.",
	},
	lvopen_mount = {
		"A new mount: {mount:a}.",
		"{mount:a} joined the stable at this level.",
		"This level brought {mount:a}.",
	},
	lvopen_zone = {
		"New ground: {zone:bare}.",
		"The road reached {zone:bare}.",
		"{zone:start} came into the journal at this level.",
	},
	lvopen_rep = {
		"{faction:start} came to count {name} as {standing}.",
		"{standing} with {faction:bare}.",
		"Standing with {faction:bare} reached {standing}.",
	},
	lvopen_attuned = {
		"Attuned to {instance:bare}.",
		"The attunement to {instance:bare} was done.",
		"{instance:start} was open to {name} from this level on.",
	},
	lvopen_gap = {
		"Back after {days:count:day} away.",
		"The journal picks up again after {days:count:day}.",
		"A return after {days:count:day}.",
	},
	lvopen_title = {
		"A new title: {title}.",
		"The title {title} was earned at this level.",
		"This level brought the title {title}.",
	},
	lvopen_maxlevel = {
		"The road reached level 60.",
		"Level 60, {zone:in}.",
		"The last level of the road: 60.",
	},
	lvopen_crossed = {
		"The road crossed {continent:to}.",
		"A crossing {continent:to}.",
		"This level began a new continent: {continent:bare}.",
	},
	lvopen_runs = {
		"The last of {n:count:run} through {instance:bare} came at this level.",
		"{instance:start}, {n:times} {range}.",
		"{instance:start} was run {n:times} {range}, the last at this level.",
	},
	lvopen_slow = {
		"A long level: {took}.",
		"Level {level} took {took}, slower than usual.",
		"This level asked for {took}.",
	},
	lvopen_fast = {
		"A short level: {took}.",
		"Level {level} took {took}, faster than usual.",
		"This level went by in {took}.",
	},
	lvclose = {
		"Level {next} came {nexttook} later, still {zone:in}{pace?}.",
		"{nexttook} later, level {next} arrived {zone:in}{pace?}.",
		"Level {next} followed after {nexttook}{pace?}.",
		"After {nexttook}, the road reached level {next}{pace?}.",
		"It took {nexttook} to reach level {next}{pace?}.",
		"Level {next} was {nexttook} away{pace?}.",
	},
	lvclose_moved = {
		"Level {next} came {nexttook} later, {zone:in}{pace?}.",
		"{nexttook} later, level {next} arrived {zone:in}{pace?}.",
		"After {nexttook}, level {next} came {zone:in}{pace?}.",
	},
	lvclose_now = {
		"{took} at level {level} so far, and the road goes on.",
		"Level {level} has taken {took} so far.",
		"So far, {took} at level {level}; the road goes on.",
	},
	quiet = {
		"Nothing in the journal stood out at level {level}.",
		"Level {level} passed quietly in the journal.",
		"The journal holds no moments from level {level}.",
		"Level {level} went by without a mark in the journal.",
		"No moment of level {level} made it into the journal.",
		"Level {level} was a quiet one in the journal.",
	},

	chtitle = { "{place:head}" },
	chtitle_again = { "{place:head}, continued" },
	era1 = { "{place:head}: first steps", "Where it began: {place:head}", "Home ground" },
	era2 = { "The road {place:to}", "The road out" },
	era3 = { "The {place:core} road", "Into the middle lands" },
	era4 = { "The thirties: {place:head}", "Wild country" },
	era5 = { "The forties: {place:head}", "Far frontiers" },
	era6 = { "The last climb", "{place:head} and the last ten levels" },
	era7 = { "Sixty", "At the top of the road" },
})
