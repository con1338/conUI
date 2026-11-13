-- Story bank: Bard, the tavern song. Warm and
-- heroic, never false: third person, past tense, one image per sentence,
-- number words through the slots, levels as "at nineteen". Color words come
-- only from the bound lexicon (Story/Voice.lua), scenes only from the noun
-- table (Data/StoryWorld.lua); Story/Honesty.lua rejects a variant whose
-- words have no fact behind them, and the next variant is tried. No invented
-- danger, no enemies the facts don't name. English only, our own text.
local _, E = ...

E.Story.Banks:Tone("bard", {
	-- Levels and places -----------------------------------------------------------
	level = {
		"Level {level} found {name} {zone:in}.",
		"{name} rose to level {level} {zone:in}.",
		"At {level:word}, the road was still {zone:in}.",
		"{zone:start} saw {name} rise to level {level}.",
		"Another level won {zone:in}: {level:word}.",
		"{name} climbed to level {level} {zone:in}.",
		"The road reached {level:word} {zone:in}, and {name} with it.",
	},
	maxlevel = {
		"In {zone:scene}, on {date}, {name} stood at level 60, {played} into the road.",
		"After {played} on the road, {name} reached level 60 {zone:in} on {date}.",
		"On {date}, {zone:in}, {name} reached the end of the road to 60, after {played} of play.",
		"{name} reached level 60 {zone:in} on {date}, and the song had its summit.",
	},
	zone = {
		"Level {level} carried {name} into {zone:scene}.",
		"At {level:word}, the road turned {zone:to}.",
		"{name} came to {zone:scene} at {level:word}.",
		"New country at level {level}: {zone:bare}.",
		"The road bent toward {zone:bare}, and {name} followed it at {level:word}.",
		"At {level:word}, {name} walked into {zone:scene}.",
		"{zone:start} opened before {name} at level {level}.",
		"Then the road turned {zone:to}.{if:samelevel}",
	},
	zone_begin = {
		"The journal finds {name}, {me:bard}, in {zone:scene} at level {level}.",
		"The tale opens {zone:in}, at level {level}, with {name}, {me:bard}.",
		"Here the song begins: {zone:bare}, level {level}, and {name}.",
		"Our story picks up {zone:in} at level {level}, where {name} already walked.",
	},
	subzone = {
		"At {level:word}, {name} found the way {subzone:to}.",
		"{subzone:start} was new ground at level {level}.",
		"The road wound past {subzone:bare} at {level:word}.",
		"The road wound past {subzone:bare} as well.{if:samelevel}",
	},
	explored = {
		"By {level:word}, {name} had walked every corner of {zone:bare}.",
		"No corner of {zone:bare} was left unwalked by level {level}.",
		"{zone:start} gave up all its corners to {name} by {level:word}.",
	},
	crossed = {
		"At {level:word}, the road crossed the sea {continent:to}.",
		"The road crossed {continent:to} by {vehicle} at {level:word}.",
		"Over the water went {name}, at {level:word}, to the shores of {continent:bare}.",
		"At level {level}, a new continent waited: {continent:bare}.",
		"Then the road crossed {continent:to}.{if:samelevel}",
	},
	homezone = {
		"{zone:start} claimed {share} of the play in this verse.",
		"Most of these levels belonged to {zone:scene}.{if:most}",
		"{zone:start} held {share} of this verse's play.",
		"Of all the roads here, {zone:bare} took {share} of the play.",
	},
	hearth = {
		"At {level:word}, {name} named {place:bare} home.",
		"The hearthstone was set to {place:bare} at level {level}, a hearth to come back to.",
		"{place:start} became the hearth of the road at {level:word}.",
		"Then {place:bare} became the hearth of the road.{if:samelevel}",
	},
	flight = {
		"{place:at}, a {beast} road was {name:poss}.",
		"At {level:word}, {name} won the flight path {place:at}.",
		"A new road through the sky opened {place:at} at {level:word}.",
		"Level {level} gave {name} wings {place:at}.",
		"Another road through the sky opened {place:at}.{if:samelevel}",
	},

	-- Dungeons, raids and bosses ----------------------------------------------------------
	dungeon = {
		"At {level:word}, the {instance:entrance} of {instance:bare} opened, and {name} walked in {firsttime}.",
		"{instance:start} opened its {instance:entrance} to {name} {firsttime} at level {level}{forever?}.",
		"Into {instance:scene} went {name} at {level:word}, {firsttime}.",
		"At {level:word}, {name} dared {instance:bare} {firsttime}{forever?}.",
		"{name} crossed the {instance:entrance} of {instance:bare} at {level:word}, {afirst}.",
		"A new road at {level:word}: {instance:bare}{forever?}, and {name} took it.",
		"Level {level} brought {name} to {instance:scene}, {afirst}.",
		"Then {name} dared {instance:bare} {firsttime}.{if:samelevel}",
	},
	dungeon_with = {
		"At {level:word}, the {instance:entrance} of {instance:bare} opened, and {name} walked in with {companions}.",
		"With {companions} alongside, {name} went into {instance:scene} {firsttime}.",
		"{name} dared {instance:bare} at {level:word} with {companions}, {afirst}.",
		"At {level:word}, {name} followed the road into {instance:bare} with {companions}, {firsttime}.",
		"Then, with {companions}, {name} dared {instance:bare} {firsttime}.{if:samelevel}",
	},
	raid = {
		"At {level:word}, {instance:scene} opened to {name} {firsttime}.",
		"The great halls of {instance:bare} took {name} in at level {level}, {afirst}.",
		"{name:poss} first raid was {instance:bare}, at {level:word}.{if:firstraid}",
		"At {level:word}, {name} stepped into {instance:bare} {firsttime}.",
	},
	raid_with = {
		"With {companions}, {name} went into {instance:scene} {firsttime}.",
		"At {level:word}, {instance:bare} opened to {name}, with {companions} alongside, {afirst}.",
		"{name} stepped into {instance:bare} {firsttime}, with {companions} alongside.",
	},
	run = {
		"{name} went back into {instance:bare} at {level:word}.",
		"Once more {instance:bare} called, and at {level:word} {name} answered.",
		"At level {level}, the road led into {instance:bare} again.",
		"{instance:start} saw {name} return at {level:word}.",
		"Another run through {instance:scene} came at {level:word}.",
		"At {level:word}, {name} took the road into {instance:bare} once more.",
		"Then {instance:bare} called once more, and {name} answered.{if:samelevel}",
	},
	run_with = {
		"With {companions}, {name} went back into {instance:bare} at {level:word}.",
		"At {level:word}, {name} ran {instance:bare} once more, with {companions}.",
		"Once more into {instance:bare}, at {level:word}, with {companions}.",
		"Then {name} ran {instance:bare} once more, with {companions}.{if:samelevel}",
	},
	runs = {
		"Again and again {name} went into {instance:scene}, {n:times} {range}{with?}.",
		"{n:times} {name} went into {instance:bare} {range}{with?}.",
		"{instance:start} saw {name} {n:times} {range}{with?}.",
		"Again and again the road ran through {instance:bare}: {n:times}, {range}.",
	},
	boss = {
		"In {instance:bare}, at {level:word}, {boss:bare} lay defeated, {firstkill}.",
		"{boss:start} fell before {name} {instance:in}, {firstkill}.",
		"At {level:word}, {name} brought down {boss:bare} {instance:in}.",
		"{instance:start} rang with a victory at {level:word}: {boss:bare} fell.",
		"Before the run was over, {boss:bare} lay defeated, {firstkill}.",
		"Then {boss:bare} fell before {name} {instance:in}.{if:samelevel}",
	},
	raidboss = {
		"{boss:start} fell {instance:in}, the first raid boss of the song.{if:firstraidboss}",
		"In {instance:scene}, {boss:bare} fell before {name} {firsttime}.",
		"At {level:word}, {boss:bare} was brought down {instance:in}, {afirst}.",
		"{instance:start} saw {boss:bare} fall on {date}.",
	},
	bossagain = {
		"{boss:start} fell again {instance:in}, {kills:count:kill} in all.",
		"Once more {boss:bare} lay defeated, at {level:word}.",
		"{instance:start} saw {boss:bare} fall again: {kills:count:kill} now.",
	},
	attunestep = {
		"At {level:word}, {name} took step {step} of {total} on the road of {attunement}.",
		"{attunement} drew nearer at level {level}: step {step} of {total}.",
		"Step {step} of {total} for {attunement} was {name:poss} at {level:word}.",
		"Step {step} of {total} for {attunement} followed.{if:samelevel}",
	},
	attuned = {
		"On {date}, the way into {instance:scene} opened to {name}.",
		"At {level:word}, {name} was attuned to {instance:bare}, and its {instance:entrance} stood open.",
		"{instance:start} would keep no door shut to {name} after {date}.",
		"The long-awaited attunement to {instance:bare} came on {date}.",
	},

	-- Deaths ----------------------------------------------------------------------------------
	death = {
		"{name} fell at level {level}, {where}, and rose again.",
		"At {level:word}, {name} fell {where}.",
		"A fall came at level {level}, {where}.",
		"{name} fell {where} at {level:word}.",
		"Level {level} brought a fall, {where}.",
		"Even the bold fall: at {level:word}, {name} fell {where}.",
		"At the same level, {name} fell {where}, and rose again.{if:samelevel}",
	},
	chdeaths = {
		"{name} fell {n:times} {zone:in} in these levels, and rose each time.",
		"These levels held {n:count:fall} {zone:in}.",
		"{n:times} {name} fell in this verse, and rose again.",
		"The road counted {n:count:fall} here, all {zone:in}.{if:many}",
		"{zone:start} saw {name} fall {n:times}.",
		"In these levels, {name} fell {n:times}, and stood up {n:times}.",
	},
	deathstreak = {
		"One grim {daypart} {subzone:auto} brought {n:count:fall} in {window}.",
		"{n:times} the ground {subzone:auto} took {name}, and {n:times} {name} rose.",
		"A bitter {daypart} {zone:in}: {n:count:fall} in {window}.",
		"In {window} on a grim {daypart}, {name} fell {n:times} {subzone:auto}.",
		"The {daypart} of {date} was grim: {n:count:fall} {zone:in} in {window}.",
	},
	deathless = {
		"For {n:count:level}, {range}, the road ran unbroken.",
		"{n:count:level} passed untouched by any fall, {range}.",
		"Not one fall in {n:count:level}: {range}, the road was unbroken.",
		"{range}, {name} walked {n:count:level} untouched.",
	},

	-- Finds, gear and keepsakes --------------------------------------------------------------
	loot = {
		"At {level:word}, {place:in}, {item} was {name:poss}.",
		"{item} was the prize {place:in} at level {level}.",
		"{place:start} gave up {item} at {level:word}.",
		"At level {level}, {name} won {item} {place:in}.",
		"{item} was {name:poss} as well, won {place:in}.{if:samelevel}",
	},
	loot_epic = {
		"At {level:word}, {place:in}, {name} won {item}, a first epic and a prized one.",
		"{item} was the prize {place:in} at level {level}, the first epic of the song.",
		"A first epic, prized above the rest: {item}, won {place:in} at {level:word}.",
	},
	gear = {
		"At {level:word}, {name} took up {item}.",
		"{item} was {name:poss} to wear from level {level} on.",
		"Level {level} brought better gear: {item}.",
		"{item} was {name:poss} to wear as well.{if:samelevel}",
	},
	wish = {
		"The wish came true at {level:word}: {item}.",
		"{item}, from the wishlist, was {name:poss} at level {level}.",
		"The wishlist gave up {item} at {level:word}.",
		"The wishlist gave up {item} as well.{if:samelevel}",
	},
	mount = {
		"At {level:word}, {name} rode out on {mount:a}.",
		"{mount:a} came to {name} at level {level}, and the road grew shorter.",
		"A new mount at {level:word}: {mount:a}.",
		"{mount:a} came to {name} as well.{if:samelevel}",
	},
	mount_first = {
		"After the long quiet, a long-awaited mount: at level {level}, {zone:in}, {mount:a} was {name:poss}.",
		"At {level:word}, {zone:in}, {name:poss} first mount came: {mount:a}.",
		"The first mount of the song, {mount:a}, carried {name} from level {level} on.",
		"On {date}, {mount:a} was {name:poss}, the first mount of the road.",
	},
	pet = {
		"At {level:word}, a new pet joined {name}: {pet:a}.",
		"{pet:a} came along from level {level} on.",
		"The road gained a small companion at {level:word}: {pet:a}.",
		"A small companion came along as well: {pet:a}.{if:samelevel}",
	},
	title = {
		"At {level:word}, {name} earned a proud title: {title}.",
		"From {date} on, {name} carried the title {title}.",
		"The title {title} was {name:poss} at level {level}.",
		"{name} won a title as well: {title}.{if:samelevel}",
	},
	note = {
		"A note from level {level}, kept for the song: {note}.",
		"At {level:word}, {name} wrote it down: {note}.",
		"The journal keeps a line from level {level}: {note}.",
		"The journal keeps a line from then as well: {note}.{if:samelevel}",
	},
	goal = {
		"At {level:word}, {name} reached the goal {goal}.",
		"The goal {goal} was won at level {level}.",
		"On {date}, {name} reached the goal {goal}.",
		"The goal {goal} was won as well.{if:samelevel}",
	},

	-- Spells, professions and reputation ----------------------------------------------------------
	spell = {
		"At {level:word}, {name} learned {spell}{rank?}.",
		"{spell}{rank?} was {name:poss} from level {level} on.",
		"A new spell for the road at {level:word}: {spell}{rank?}.",
		"{spell}{rank?} was {name:poss} as well.{if:samelevel}",
	},
	recipe = {
		"At {level:word}, {name} learned to make {recipe}.",
		"The recipe {recipe} was {name:poss} at level {level}.",
		"A new recipe at {level:word}: {recipe}.",
		"{name} learned to make {recipe} as well.{if:samelevel}",
	},
	profession = {
		"At {level:word}, {name} took up {profession:lower}.",
		"{name} began the craft of {profession:lower} at level {level}.",
		"A new trade at {level:word}: {profession:lower}.",
		"{name} took up {profession:lower} as well.{if:samelevel}",
	},
	skill = {
		"At {level:word}, {name:poss} {profession:lower} reached {skill}.",
		"{profession} grew to {skill} at level {level}.",
		"Skill in {profession:lower} reached {skill} at {level:word}.",
		"{profession} grew to {skill} as well.{if:samelevel}",
	},
	skill_master = {
		"At {level:word}, {name} mastered {profession:lower}.",
		"{profession} was mastered at level {level}.",
		"On {date}, {name} became a master of {profession:lower}.",
		"{name} mastered {profession:lower} as well.{if:samelevel}",
	},
	respec = {
		"At {level:word}, {name} set {n:count:talent point} anew.",
		"Level {level} brought a new path: {n:count:talent point} spent again.",
		"{name} chose again at {level:word}, with {n:count:talent point}.",
	},
	rep = {
		"At {level:word}, {faction:bare} named {name} {standing}.",
		"{faction:start} counted {name} as {standing} at level {level}.",
		"{standing} with {faction:bare}: so it stood for {name} at {level:word}.",
		"At level {level}, {faction:bare} came to count {name} as {standing}.",
		"{faction:start} came to count {name} as {standing} as well.{if:samelevel}",
	},
	challenge = {
		"On {date}, {name} won the Legacy challenge {challenge}.",
		"The Legacy challenge {challenge} fell to {name} on {date}.",
		"At {level:word}, {name} completed the Legacy challenge {challenge}.",
	},
	legacylevel = {
		"On {date}, {name:poss} Legacy rose to level {n}.",
		"{name:poss} Legacy reached level {n} at {level:word}.",
		"Legacy level {n} was reached on {date}.",
	},

	-- Quests --------------------------------------------------------------------------------------------
	quest = {
		"At {level:word}, {name} handed in {quest} {zone:in}.",
		"{quest} was done {zone:in} at level {level}.",
		"In {zone:bare}, {quest} was seen through at {level:word}.",
		"{name} saw {quest} to its end at level {level}.",
		"Level {level} brought {quest} home {zone:in}.",
		"Another quest done {zone:in} at {level:word}: {quest}.",
		"{quest} was done {zone:in} as well.{if:samelevel}",
	},
	questchain = {
		"At {level:word}, {name} saw the quest chain {chain} to its end.",
		"The long tale of {chain} ended at level {level}.",
		"With {quest}, the quest chain {chain} was done at {level:word}.",
		"The quest chain {chain} came to its end as well.{if:samelevel}",
	},
	dungeonquest = {
		"At {level:word}, {name} carried {quest} out of {instance:bare}.",
		"The {instance:core} quest {quest} was done at level {level}.",
		"{quest} came home from {instance:bare} at {level:word}.",
		"{quest} came home from {instance:bare} as well.{if:samelevel}",
	},
	groupquest = {
		"With {companions}, {name} handed in {quest} at {level:word}.",
		"{name} saw {quest} through at level {level}, with {companions}.",
		"At {level:word}, {quest} was done with {companions}.",
		"Then, with {companions}, {name} saw {quest} through.{if:samelevel}",
	},
	questburst = {
		"Level {level} was a busy one: {n:count:quest} handed in.",
		"At {level:word}, {name} handed in {n:count:quest}.",
		"{n:count:quest} at level {level}: the quest log ran hot.",
	},
	chquests = {
		"{n:count:quest} were handed in across these levels, most {zone:in}.",
		"The quest log closed {n:count:quest} in this verse.",
		"In these levels, {name} saw {n:count:quest} through.",
		"{zone:start} kept the quest log busy: {n:count:quest} handed in.",
	},

	-- Companions and other players --------------------------------------------------------------
	met = {
		"{zone:start} brought a new companion at {level:word}: {fellow}, {fellow:desc}.",
		"At level {level}, {zone:in}, {name} met {fellow}, {fellow:desc}.",
		"{fellow} joined the road {zone:in} at {level:word}.",
		"At {level:word}, {name} and {fellow} met {zone:in}.",
		"{fellow}, {fellow:desc}, joined the road as well.{if:samelevel}",
	},
	together = {
		"By {level:word}, {fellow} was a trusted friend, with {duration} on the road together.",
		"{duration} at {name:poss} side by level {level}: {fellow}.",
		"{fellow} and {name} had shared {duration} of the road by {level:word}.",
		"An old friend by now: {fellow}, with {duration} together.",
		"By then, {fellow} and {name} had shared {duration} of the road.{if:samelevel}",
	},
	topfellow = {
		"No one walked beside {name} longer than {fellow}: {duration} together.",
		"{fellow} was the trusted friend of the song, {duration} at {name:poss} side.",
		"Of all who came along, {fellow} stayed the longest: {duration}.",
	},
	guild = {
		"At {level:word}, {name} found a guild: {guild}.",
		"{guild} took {name} in at level {level}.",
		"On {date}, {name} joined {guild}.",
		"{name} found a guild as well: {guild}.{if:samelevel}",
	},
	pvpwin = {
		"At {level:word}, {battleground:in}, it was a win for {side}.",
		"{name} fought {battleground:in} at level {level}, and {side} won the day.",
		"{battleground:start} saw a win for {side} at {level:word}.",
	},
	pvploss = {
		"At {level:word}, {name} fought {battleground:in}, and the day was lost.",
		"{battleground:start} went against {side} at level {level}.",
		"Not every battle is won: {battleground:bare}, at {level:word}.",
	},

	-- World ------------------------------------------------------------------------------------------
	rare = {
		"At {level:word}, {zone:in}, {name} crossed paths with {rare}.",
		"{rare} was seen {zone:in} at level {level}.",
		"{zone:start} showed {name} a rare sight at {level:word}: {rare}.",
		"{rare} crossed the road as well, {zone:in}.{if:samelevel}",
	},
	gather = {
		"{zone:start} gave {name} {node} ×{n}.",
		"At {level:word}, {name} gathered {node} {zone:in}, {n:times} in all.",
		"{node} ×{n}, gathered {zone:in}.",
	},
	farm = {
		"{name} worked {zone:bare} for {duration}, and it paid {gold}.",
		"At {level:word}, {duration} of farming {zone:in}.",
		"{zone:start} gave up {gold} in {duration} of farming.",
	},
	cinematic = {
		"At {level:word}, {name} watched the {zone:core} cinematic.",
		"The {zone:core} cinematic played at level {level}.",
		"{name} paused for the tale of {zone:bare} at {level:word}.",
	},
	rested = {
		"At {level:word}, {name} came back well rested.",
		"A long rest, and {name} returned at level {level}.",
		"Level {level} began with a well-rested return.",
	},

	-- Pace and the gaps ------------------------------------------------------------------------------
	fast = {
		"Level {level} flew by in {took}, swift as the wind.",
		"A swift level: {level:word} took only {took}.",
		"At {level:word}, the road ran quick: {took}.",
		"Swiftly went level {level}, in {took}.",
	},
	fast_rested = {
		"Level {level} flew by in {took}, swift as the wind{rested?}.",
		"A swift level: {level:word} took only {took}{rested?}.",
		"Swiftly went level {level}, in {took}{rested?}.",
	},
	slow = {
		"Level {level} was hard-won, {took} in the making.",
		"A hard-won level: {level:word} took {took}.",
		"At {level:word}, the road climbed slowly: {took}.",
		"Level {level} asked for {took}, and {name} gave it.",
	},
	gap = {
		"Then came a long quiet: {days:count:day} with no page written.",
		"The road rested for {days:count:day}, from {startdate} to {stopdate}.",
		"For {days:count:day}, between {startdate} and {stopdate}, the song fell silent.",
		"At level {level}, the journal waited {days:count:day} for {name} to return.",
	},
	unrecorded = {
		"{duration} of the road went unsung at level {level}.",
		"At level {level}, {duration} of play went by without the journal.",
		"The journal missed {duration} of the road at level {level}.",
		"In the same level, {duration} of play went by without the journal.{if:samelevel}",
	},
	sourceoff = {
		"{source} went unsung for {levels}.",
		"For {levels}, the journal kept no record of {source:lower}.",
		"{source} were not recorded for {levels}.",
	},
	rolled = {
		"The small moments of {levels} live on as a summary: {spells:count:spell} learned and {finds:count:item} found.",
		"For {levels}, only a summary remains: {spells:count:spell} learned and {finds:count:item} found.",
		"Of {levels}, the journal keeps the sum: {spells:count:spell} learned and {finds:count:item} found.",
	},

	-- Chapter structure ---------------------------------------------------------------------------------
	chclose = {
		"So the verse ended at level {b}, after {played} on the road.",
		"{played} of the road carried {name} through {levels}.",
		"The verse closed at {b:word}, {played} in the making.",
		"{levels}: {played} on the road, and the song went on.",
		"When the verse ended at level {b}, {played} had passed on the road.",
		"Through {levels}, the road took {played}.",
	},
	chclose_now = {
		"The verse is still being sung at level {b}, {played} so far.",
		"So far, {played} on the road in these levels, and the song goes on.",
		"At level {b}, the verse goes on, with {played} behind it.",
	},
	before = {
		"Every song has a first verse that nobody wrote down. The journal opens at level {level} {zone:in}; of the road before, the game recalls only {quests:count:quest} and {played} of travel.",
		"Before level {level}, no one kept the song; the game recalls only {quests:count:quest} and {played} on the road.",
		"Of the road before level {level}, the game remembers {quests:count:quest}, and nothing of where it began.",
		"The early verses are lost; the game remembers {quests:count:quest} before the journal began at level {level}.",
	},
	eraopen = {
		"{levels}: {played} of the road, and most of it {zone:in}.",
		"Over {levels}, the road took {played}, most of it {zone:in}.",
		"{played} on the road through {levels}, mostly {zone:in}.",
		"{levels} took {played} of the road.",
	},
	summary = {
		"Since level {since}, the journal has counted {gold} won on the road.",
		"From level {since} on, {gold} came into the purse, by the journal's count.",
		"The journal counts {gold} earned since level {since}: the song so far.",
	},
	gamecount = {
		"{quests:count:quest}, {deaths:count:fall}: the game keeps the count.",
		"The game counts {quests:count:quest} done and {deaths:count:fall} in all.",
		"In all, the game remembers {quests:count:quest} and {deaths:count:fall}.",
	},

	-- The Journey's level chapters ---------------------------------------------------------------------
	lvopen_home = {
		"{zone:start} held most of level {level}.",
		"Most of level {level} was spent in {zone:scene}.",
		"Level {level} belonged to {zone:bare}.",
		"The road stayed {zone:in} for most of {level:word}.",
		"{zone:start} kept {name} for most of level {level}.",
		"At {level:word}, the road lingered {zone:in}.",
	},
	lvopen_deathstreak = {
		"A grim {daypart} {subzone:auto}: {n:count:fall} in {window}.",
		"{n:times} the ground took {name} {subzone:auto}.",
		"One bitter {daypart} {zone:in}.",
	},
	lvopen_boss = {
		"{boss:start} fell {instance:in}.",
		"A victory {instance:in}: {boss:bare}.",
		"{boss:start} lay defeated.",
	},
	lvopen_raidboss = {
		"A raid boss fell: {boss:bare}.",
		"In {instance:scene}, {boss:bare} fell.",
		"{boss:start} was brought down.",
	},
	lvopen_dungeon = {
		"Into {instance:scene}.",
		"{instance:start} opened its {instance:entrance}.",
		"A new road: {instance:bare}.",
	},
	lvopen_raid = {
		"Into {instance:scene}.",
		"{instance:start} opened its {instance:entrance}.",
		"The great halls of {instance:bare}.",
	},
	lvopen_loot = {
		"A prize: {item}.",
		"{item} was won at this level.",
		"This level gave up {item}.",
	},
	lvopen_mount = {
		"A new mount: {mount:a}.",
		"{mount:a} joined the road.",
		"At this level, {name} rode out on {mount:a}.",
	},
	lvopen_zone = {
		"Into {zone:scene}.",
		"New country: {zone:bare}.",
		"The road turned {zone:to}.",
	},
	lvopen_rep = {
		"{faction:start} named {name} {standing}.",
		"{standing} with {faction:bare}.",
		"{faction:start} counted {name} as {standing}.",
	},
	lvopen_attuned = {
		"The way into {instance:bare} stood open.",
		"Attuned to {instance:bare}.",
		"{instance:start} opened its {instance:entrance}.",
	},
	lvopen_gap = {
		"Back on the road after {days:count:day}.",
		"After {days:count:day} of quiet, the song resumes.",
		"The road waited {days:count:day}.",
	},
	lvopen_title = {
		"A proud new title: {title}.",
		"The title {title} was won.",
		"From here on, {name} carried the title {title}.",
	},
	lvopen_maxlevel = {
		"The road reached sixty.",
		"Sixty, {zone:in}.",
		"At the top of the road: level 60.",
	},
	lvopen_crossed = {
		"Over the sea {continent:to}.",
		"A new continent: {continent:bare}.",
		"The road crossed {continent:to}.",
	},
	lvopen_runs = {
		"Again and again into {instance:bare}: {n:times}, and the last of them at this level.",
		"{instance:start} called, and {name} answered.",
		"The last run of {n:count:run} through {instance:scene} came at this level.",
	},
	lvopen_slow = {
		"A hard-won level: {took}.",
		"Level {level} took {took}, and the road went on.",
		"The road climbed slowly here: {took}.",
	},
	lvopen_fast = {
		"A swift level: {took}.",
		"Level {level} flew by in {took}.",
		"Quick work: {took}.",
	},
	lvclose = {
		"Level {next} came {nexttook} later, still {zone:in}{pace?}.",
		"{nexttook} later, {next:word} was won {zone:in}{pace?}.",
		"After {nexttook}, the road reached {next:word}{pace?}.",
		"Level {next} waited {nexttook} down the road{pace?}.",
		"It took {nexttook} to win level {next}{pace?}.",
		"{nexttook} on, level {next} was {name:poss}{pace?}.",
	},
	lvclose_moved = {
		"Level {next} came {nexttook} later, {zone:in}{pace?}.",
		"{nexttook} later, {next:word} was won {zone:in}{pace?}.",
		"After {nexttook}, the road reached {next:word} {zone:in}{pace?}.",
	},
	lvclose_now = {
		"{took} at level {level} so far, and the road goes on.",
		"Level {level} has taken {took} so far; the song goes on.",
		"So far, {took} at {level:word}, and more road ahead.",
	},
	quiet = {
		"A quiet verse: level {level} left no mark in the journal.",
		"Level {level} passed in peace, with nothing for the song.",
		"No tale was told at level {level}.",
		"The road was quiet at level {level}.",
		"Level {level} went by without a line in the song.",
		"Nothing at level {level} made the journal.",
	},

	chtitle = { "{place:head}", "The road {place:to}", "Into {place:bare}" },
	chtitle_again = { "{place:head}, once more" },
	era1 = { "{place:head}: first steps", "Where it began: {place:head}", "Home ground" },
	era2 = { "The road {place:to}", "The road out" },
	era3 = { "The {place:core} road", "Into the middle lands" },
	era4 = { "The thirties: {place:head}", "Wild country" },
	era5 = { "The forties: {place:head}", "Far frontiers" },
	era6 = { "The last climb", "{place:head} and the last ten levels" },
	era7 = { "Sixty", "At the top of the road" },
})
