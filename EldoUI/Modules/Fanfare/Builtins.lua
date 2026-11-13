-- Fanfare: the triggers that ship with EldoUI, and the style presets.
--
-- Built-in triggers are copied into the profile the first time (and when a
-- new EldoUI version adds more), after that they are the player's own: every
-- field can be edited, and "Delete" only hides a built-in so "Restore
-- built-ins" can bring it back. Styles change built-ins by id and never touch
-- triggers the player made.
--
-- Every sound has a fallback from EldoUI's own pack, so the presets work
-- without any SharedMedia addon. "lsm:" names are WeakAuras SharedMedia
-- sounds that are only used when that addon is installed.
local _, E = ...
local L = E.L

local Key = E.Key
local F = E.fanfare

-- Raise when the list below gains triggers; profiles then get the new ones.
F.BUILTIN_VERSION = 3 -- 2: raid warning and loss of control; 3: group member dings

-- The full shape of a trigger. Missing fields are filled from this, for
-- built-ins, new triggers and imported ones alike.
F.triggerDefaults = {
	name = Key("New trigger"),
	group = "Custom",
	enabled = true,
	source = "levelup",
	cooldown = 2,
	allowInCombat = false,
	conditions = {
		instance = "any", combat = "any", group = "any", resting = "any", zone = "",
		minQuality = 0, sender = "", minLevel = 0, maxLevel = 0, mounted = "any", chance = 100, who = "friends",
	},
	actions = {
		sound = { id = "none", fallback = "none", channel = "default" },
		splash = { enabled = false, text = "", sub = "", font = "default", size = 0, colorMode = "accent", color = { 1, 0.82, 0 }, hold = 0, anim = "default" },
		flash = { enabled = false, style = "default", colorMode = "accent", color = { 1, 0.82, 0 }, alpha = 0 },
		icon = { enabled = false, texture = "auto" },
		chat = { enabled = false, text = "" },
	},
}

local function T(id, name, source, group, spec)
	spec = spec or {}
	local trigger = {
		builtin = id, name = name, source = source, group = group,
		enabled = spec.enabled ~= false,
		cooldown = spec.cooldown or 2,
		allowInCombat = spec.allowInCombat or false,
		conditions = spec.conditions or {},
		actions = {
			sound = { id = spec.sound or "none", fallback = spec.fallback or "none", channel = "default" },
			splash = { enabled = spec.text ~= nil, text = spec.text or "", sub = spec.sub or "", colorMode = spec.color or "accent" },
			flash = { enabled = spec.flash ~= nil, style = spec.flash or "default", colorMode = spec.flashColor or spec.color or "accent" },
			icon = { enabled = spec.icon or false, texture = "auto" },
			chat = { enabled = false, text = spec.chat or "" },
		},
	}
	return id, trigger
end

-- The Subtle preset is the baseline: what a player gets when they switch
-- the module on.
F.builtins, F.builtinOrder = {}, {}
local function Add(...)
	local id, trigger = T(...)
	F.builtins[id] = trigger
	table.insert(F.builtinOrder, id)
end

-- Progress
Add("levelup", Key("Level up"), "levelup", "Progress", { sound = "eldo:Tada", fallback = "eldo:EldoChime", text = Key("LEVEL {level}!"), sub = "{zone}", icon = true })
Add("questdone", Key("Quest turned in"), "questdone", "Progress", { sound = "eldo:Glass", fallback = "eldo:EldoChime", cooldown = 1 })
Add("achievement", Key("Achievement"), "achievement", "Progress", { sound = "eldo:SynthChord", fallback = "eldo:EldoChime", text = "{achievement}", icon = true }) -- no-L: {token} only
Add("rested", Key("Rested"), "rested", "Progress", { enabled = false, sound = "eldo:Glass", text = Key("RESTED"), cooldown = 30 })
-- Loot
Add("loot", Key("Epic loot"), "loot", "Loot", { sound = "kit:UI_EPICLOOT_TOAST", fallback = "eldo:Guitar", text = "{item}", color = "quality", icon = true, cooldown = 1, conditions = { minQuality = 4 } }) -- no-L: {token} only
Add("rollwon", Key("Roll won"), "rollwon", "Loot", { sound = "eldo:Xylophone", fallback = "eldo:EldoChime", text = Key("WON {item}"), color = "quality", icon = true, cooldown = 1, conditions = { minQuality = 3 } })
Add("auctionsold", Key("Auction sold"), "auctionsold", "Loot", { sound = "eldo:Glass", fallback = "eldo:EldoChime", icon = true, cooldown = 3 })
Add("bagsfull", Key("Bags full"), "bagsfull", "Loot", { sound = "eldo:ErrorBeep", fallback = "eldo:EldoWarning", text = Key("BAGS FULL"), color = "warn", cooldown = 60 })
Add("durability", Key("Repair needed"), "durability", "Loot", { sound = "eldo:EldoWarning", text = Key("REPAIR"), sub = Key("{percent}% durability"), color = "warn", cooldown = 300 })
-- Social
Add("whisper", Key("Whisper"), "whisper", "Social", { sound = "eldo:Glass", fallback = "eldo:EldoChime", cooldown = 3 })
Add("partyinvite", Key("Group invite"), "partyinvite", "Social", { enabled = false, sound = "eldo:EldoChime", text = "{sender}", sub = Key("invites you"), cooldown = 3 }) -- no-L: {token} only
Add("trade", Key("Trade"), "trade", "Social", { enabled = false, sound = "eldo:EldoChime", cooldown = 3 })
Add("duel", Key("Duel request"), "duel", "Social", { enabled = false, sound = "eldo:EldoWarning", text = Key("DUEL"), sub = "{sender}", cooldown = 3 })
Add("mail", Key("New mail"), "mail", "Social", { sound = "eldo:Glass", fallback = "eldo:EldoChime", icon = true, cooldown = 30 })
-- Group
Add("readycheck", Key("Ready check"), "readycheck", "Group", { sound = "eldo:Brass", fallback = "eldo:EldoChime", text = Key("READY CHECK"), flash = "edges", allowInCombat = true })
Add("rolecheck", Key("Role check"), "rolecheck", "Group", { sound = "eldo:Brass", fallback = "eldo:EldoChime", text = Key("ROLE CHECK"), flash = "edges" })
Add("queuepop", Key("Queue pops"), "queuepop", "Group", { sound = "eldo:SynthChord", fallback = "eldo:EldoChime", text = Key("QUEUE READY"), sub = "{queue}", flash = "edges", icon = true, allowInCombat = true })
Add("summon", Key("Summon"), "summon", "Group", { sound = "eldo:EldoChime", text = Key("SUMMON"), sub = "{area}", cooldown = 3 })
Add("resurrect", Key("Resurrection"), "resurrect", "Group", { enabled = false, sound = "eldo:EldoChime", text = Key("RESURRECT"), sub = "{sender}", cooldown = 3 })
-- A party member levels up: a small notice, no sound by default.
Add("groupding", Key("Group member levels up"), "groupding", "Group", { text = "{sender}", sub = Key("reached level {level}"), icon = true, cooldown = 3 }) -- no-L: {token} only
Add("raidwarning", Key("Raid warning"), "raidwarning", "Group", { enabled = false, sound = "kit:RAID_WARNING", fallback = "eldo:EldoWarning", allowInCombat = true, cooldown = 2 })
Add("pull", Key("Pull timer"), "pull", "Group", { enabled = false, sound = "kit:RAID_WARNING", fallback = "eldo:EldoWarning", text = Key("PULL {seconds}"), color = "warn", flash = "edges", allowInCombat = true })
-- Instance
Add("bosskill", Key("Boss killed"), "bosskill", "Instance", { sound = "eldo:DrumRoll", fallback = "eldo:EldoChime", text = Key("{boss} DOWN"), color = "success", cooldown = 5 })
Add("wipe", Key("Wipe"), "wipe", "Instance", { sound = "eldo:OhNo", fallback = "eldo:EldoFail", text = Key("WIPE"), color = "danger", cooldown = 5 })
Add("death", Key("You died"), "death", "Instance", { sound = "eldo:OhNo", fallback = "eldo:EldoFail", flash = "vignette", flashColor = "danger", icon = true, cooldown = 5 })
Add("losscontrol", Key("Loss of control"), "losscontrol", "Instance", { enabled = false, sound = "eldo:EldoWarning", allowInCombat = true, cooldown = 2 })
Add("combatstart", Key("Enter combat"), "combatstart", "Instance", { enabled = false, sound = "eldo:Whoosh", cooldown = 2 })
Add("combatend", Key("Leave combat"), "combatend", "Instance", { enabled = false, sound = "eldo:Glass", cooldown = 2 })
-- PvP
Add("honorkill", Key("Honorable kill"), "honorkill", "PvP", { enabled = false, sound = "eldo:Xylophone", cooldown = 1 })
Add("bgstart", Key("Battleground starts"), "bgstart", "PvP", { enabled = false, sound = "eldo:Brass", text = Key("FIGHT!"), flash = "edges", allowInCombat = true })
Add("bgend", Key("Battleground ends"), "bgend", "PvP", { enabled = false, sound = "eldo:Tada", text = Key("MATCH OVER") })
-- World
Add("flightlanded", Key("Flight landed"), "flightlanded", "World", { enabled = false, sound = "eldo:Whoosh", text = "{zone}", cooldown = 5 }) -- no-L: {token} only
Add("rare", Key("Rare spotted"), "rare", "World", { sound = "eldo:ChickenAlarm", fallback = "eldo:EldoWarning", text = Key("RARE"), sub = "{name}", icon = true, cooldown = 10 })
Add("afk", Key("Gone AFK"), "afk", "Status", { enabled = false, sound = "eldo:Sheep", cooldown = 10 })

---------------------------------------------------------------------------
-- Style presets. Each one sets the module's look and the built-in triggers
-- it names; everything else keeps the player's values.
---------------------------------------------------------------------------
local ALL = {}
for _, id in ipairs(F.builtinOrder) do ALL[id] = true end

-- spec.on: ids switched on (others off); spec.sounds: id -> { sound, fallback };
-- spec.splash / spec.flash / spec.icon: ids with that effect (others off).
local function Style(spec)
	local triggers = {}
	for _, id in ipairs(F.builtinOrder) do
		local t = { actions = {} }
		if spec.on then t.enabled = spec.on[id] and true or false end
		local sound = spec.sounds and spec.sounds[id]
		if spec.silent then
			t.actions.sound = { id = "none" }
		elseif sound then
			t.actions.sound = { id = sound[1], fallback = sound[2] or "none" }
		end
		if spec.splash then t.actions.splash = { enabled = spec.splash[id] and true or false } end
		if spec.flash then t.actions.flash = { enabled = spec.flash[id] and true or false } end
		if spec.icon then t.actions.icon = { enabled = spec.icon[id] and true or false } end
		if spec.chat then t.actions.chat = { enabled = spec.chat[id] and true or false } end
		if spec.texts and spec.texts[id] then
			t.actions.splash = t.actions.splash or {}
			t.actions.splash.text = spec.texts[id]
		end
		-- Empty tables would replace the player's whole table when merged.
		if next(t.actions) == nil then t.actions = nil end
		if spec.cooldownScale then t.cooldown = math.max(1, (F.builtins[id].cooldown or 2) * spec.cooldownScale) end
		triggers[id] = t
	end
	local settings = { splash = spec.look, flash = spec.flashLook, icon = spec.iconLook, combatGimmicks = spec.combat or false, triggers = triggers }
	return settings
end

local function Set(...)
	local set = {}
	for i = 1, select("#", ...) do set[select(i, ...)] = true end
	return set
end

local SUBTLE_ON = Set("levelup", "questdone", "achievement", "loot", "rollwon", "auctionsold", "bagsfull", "durability",
	"whisper", "mail", "readycheck", "rolecheck", "queuepop", "summon", "bosskill", "wipe", "death", "rare", "groupding")
local SUBTLE_SPLASH = Set("levelup", "achievement", "loot", "rollwon", "bagsfull", "durability", "readycheck", "rolecheck",
	"queuepop", "summon", "bosskill", "wipe", "rare", "groupding")

local function Copy(set, ...)
	local out = CopyTable(set)
	for i = 1, select("#", ...) do out[select(i, ...)] = true end
	return out
end

F.styles = {
	{ key = "Subtle", title = "Subtle", desc = "Notice without fuss: EldoUI's soft sounds, a clean banner, a flash only when a queue pops or a ready check starts.",
		settings = Style({
			on = SUBTLE_ON, splash = SUBTLE_SPLASH, flash = Set("readycheck", "rolecheck", "queuepop", "death"),
			icon = Set("levelup", "achievement", "loot", "rollwon", "auctionsold", "mail", "queuepop", "death", "rare"),
			sounds = {
				levelup = { "eldo:Tada" }, questdone = { "eldo:Glass" }, achievement = { "eldo:SynthChord" }, loot = { "kit:UI_EPICLOOT_TOAST", "eldo:Guitar" },
				whisper = { "eldo:Glass" }, readycheck = { "eldo:Brass" }, queuepop = { "eldo:SynthChord" }, death = { "eldo:OhNo" },
			},
			look = { font = "Bebas Neue", size = 44, banner = true, hold = 1.4, anim = "slide" },
			flashLook = { style = "edges", alpha = 0.25 }, iconLook = { size = 48 },
		}) },
	{ key = "Arcade", title = "Arcade", desc = "Game-show fun: big pop-in text, fanfares and flashes on every win. Uses WeakAuras SharedMedia sounds when installed.",
		settings = Style({
			on = Copy(SUBTLE_ON, "partyinvite", "duel", "bgstart", "bgend", "flightlanded"),
			splash = Copy(SUBTLE_SPLASH, "questdone", "partyinvite", "duel", "bgstart", "bgend", "flightlanded", "mail", "auctionsold"),
			flash = Set("levelup", "queuepop", "readycheck", "bosskill", "bgstart"),
			icon = ALL,
			sounds = {
				levelup = { "lsm:Tada Fanfare", "eldo:Tada" }, loot = { "lsm:Kaching", "eldo:Guitar" }, rollwon = { "lsm:Xylophone", "eldo:Xylophone" },
				whisper = { "lsm:Robot Blip", "eldo:Glass" }, bosskill = { "lsm:Applause", "eldo:DrumRoll" }, achievement = { "lsm:Tada Fanfare", "eldo:SynthChord" },
				queuepop = { "lsm:Boxing Arena Gong", "eldo:Brass" },
			},
			look = { font = "Russo One", size = 64, banner = false, hold = 1.6, anim = "pop" },
			flashLook = { style = "edges", alpha = 0.35 }, iconLook = { size = 64 },
		}) },
	{ key = "RaidLeader", title = "Raid leader", desc = "Loud and clear for group admin: ready checks, queues, pulls and wipes. Only you see and hear it; nothing is sent to chat.",
		settings = Style({
			on = Set("readycheck", "rolecheck", "queuepop", "pull", "bosskill", "wipe", "death", "whisper", "summon", "resurrect"),
			splash = Set("readycheck", "rolecheck", "queuepop", "pull", "bosskill", "wipe", "summon", "resurrect"),
			flash = Set("readycheck", "rolecheck", "queuepop", "pull", "wipe"),
			icon = {},
			sounds = {
				readycheck = { "kit:READY_CHECK", "eldo:Brass" }, rolecheck = { "kit:READY_CHECK", "eldo:Brass" }, queuepop = { "kit:PVP_THROUGH_QUEUE", "eldo:SynthChord" },
				pull = { "kit:RAID_WARNING", "eldo:EldoWarning" }, wipe = { "eldo:EldoFail" }, bosskill = { "eldo:Brass" },
			},
			look = { font = "Anton", size = 60, banner = true, hold = 2.0, anim = "pop" },
			flashLook = { style = "edges", alpha = 0.35 }, iconLook = { size = 48 },
		}) },
	{ key = "SilentVisual", title = "Silent visual", desc = "No sounds at all: banners, a soft edge flash and a line in your own chat. For streaming or late nights.",
		settings = Style({
			on = Copy(SUBTLE_ON, "partyinvite", "trade", "duel"),
			silent = true,
			splash = Copy(SUBTLE_SPLASH, "whisper", "mail", "partyinvite", "trade", "duel", "questdone"),
			flash = Set("whisper", "queuepop", "readycheck"),
			icon = ALL,
			chat = Set("whisper", "queuepop"),
			look = { font = "Bebas Neue", size = 52, banner = true, hold = 1.8, anim = "slide" },
			flashLook = { style = "edges", alpha = 0.3 }, iconLook = { size = 48 },
		}) },
	{ key = "ClassicHero", title = "Classic hero", desc = "2004 nostalgia: the game's own sounds and a gold fantasy font, no banner.",
		settings = Style({
			on = Set("levelup", "loot", "queuepop", "readycheck", "death", "achievement", "questdone", "bosskill"),
			splash = Set("levelup", "loot", "queuepop", "readycheck", "achievement", "bosskill"),
			flash = Set("death"),
			icon = Set("levelup", "loot", "achievement"),
			sounds = {
				levelup = { "eldo:Tada", "eldo:EldoChime" }, loot = { "kit:UI_EPICLOOT_TOAST", "eldo:Guitar" }, queuepop = { "kit:PVP_THROUGH_QUEUE", "eldo:SynthChord" },
				readycheck = { "kit:READY_CHECK", "eldo:Brass" }, achievement = { "kit:ACHIEVEMENT_MENU_OPEN", "eldo:SynthChord" }, questdone = { "kit:IG_QUEST_LIST_COMPLETE", "eldo:Glass" },
				death = { "eldo:EldoFail" }, bosskill = { "kit:LFG_REWARDS", "eldo:Brass" },
			},
			look = { font = "Cinzel Decorative Bold", size = 56, banner = false, hold = 1.8, anim = "slide" },
			flashLook = { style = "vignette", alpha = 0.3 }, iconLook = { size = 56 },
		}) },
	{ key = "Meme", title = "Meme", desc = "Pure fun: huge white captions and silly sounds, some only half the time. Never in combat. Funniest with WeakAuras SharedMedia installed.",
		settings = Style({
			on = Copy(SUBTLE_ON, "duel", "flightlanded", "afk"),
			splash = Copy(SUBTLE_SPLASH, "death", "whisper", "afk", "duel"),
			flash = Set("levelup", "death"),
			icon = ALL,
			texts = { levelup = Key("DING!"), death = Key("OOF"), wipe = Key("WELP"), loot = Key("LOOT GOBLIN"), whisper = Key("PSST"), afk = Key("BRB"), rare = Key("SHINY!") },
			sounds = {
				levelup = { "lsm:Air Horn", "eldo:Tada" }, death = { "lsm:Cartoon Voice Baritone", "eldo:OhNo" }, wipe = { "lsm:Cartoon Voice Baritone", "eldo:OhNo" },
				whisper = { "lsm:Squeaky Toy Short", "eldo:SqueakyToy" }, loot = { "lsm:Kaching", "eldo:Rooster" }, rare = { "eldo:ChickenAlarm" },
				afk = { "eldo:Sheep" }, mail = { "eldo:Goat" }, duel = { "lsm:Roaring Lion", "eldo:EldoWarning" },
			},
			cooldownScale = 2,
			look = { font = "Anton", size = 72, banner = false, hold = 1.4, anim = "bounce", outline = "THICKOUTLINE" },
			flashLook = { style = "full", alpha = 0.2 }, iconLook = { size = 72 },
		}) },
	{ key = "MinimalCues", title = "Minimal cues", desc = "Short sounds only, nothing on screen.",
		settings = Style({
			on = Set("levelup", "loot", "whisper", "readycheck", "queuepop", "pull", "death", "mail"),
			splash = {}, flash = {}, icon = {},
			sounds = {
				levelup = { "eldo:EldoChime" }, loot = { "eldo:Glass" }, whisper = { "eldo:Glass" }, readycheck = { "eldo:EldoChime" },
				queuepop = { "eldo:EldoChime" }, pull = { "eldo:EldoWarning" }, death = { "eldo:EldoFail" }, mail = { "eldo:Glass" },
			},
			look = { hold = 1.4 },
		}) },
}

-- Meme stays out of combat, and rolls the dice on whispers and loot.
for _, style in ipairs(F.styles) do
	if style.key == "Meme" then
		style.settings.triggers.whisper.conditions = { chance = 50 }
		style.settings.triggers.loot.conditions = { chance = 50 }
		for _, t in pairs(style.settings.triggers) do t.allowInCombat = false end
	end
end

E:RegisterStyles("Fanfare", F.styles, { restoresOnly = true })
