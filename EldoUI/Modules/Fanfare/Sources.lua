-- Fanfare: the situations a trigger can react to ("When").
--
-- Every source only presents something the game already tells the player
-- (a level up, a whisper, a ready check). None reads the combat log, other
-- units' health, auras or casts, and none acts in the game. A trigger picks
-- a source by key from this list; there are no raw event names and no code.
--
-- A source:
--   key, label, group   shown in the editor
--   events              game events it listens to (registered only while a
--                       trigger uses the source)
--   payload(event, ...) returns a table of values for text tokens, or nil
--                       to ignore this event
--   conditions          extra "Only if" checks that make sense for it
--   tokens              text tokens it fills, shown in the editor
--   icon                default icon for the "auto" icon pop
--   sample              payload for the Test button
--   prime()             optional: reads what the game already shows when a
--                       trigger starts using the source, so only a change
--                       made after that fires (friends, skills, factions)
local _, E = ...
local L = E.L

E.fanfare = E.fanfare or {}
local F = E.fanfare

local Secret = E.Secret

-- Plain text only: secret values and non-strings give nil.
local function Plain(value)
	if Secret(value) then return nil end
	if type(value) == "string" or type(value) == "number" then return value end
end

-- "You receive loot: %s." style lines, matched with the client's own
-- strings (also the numbered "%1$s" forms some translations use). Returns
-- the line's arguments in argument order from the first string that fits.
local function MatchAny(text, ...)
	for i = 1, select("#", ...) do
		local args = E.ChatParse:MatchFormat(text, (select(i, ...)))
		if args then return args end
	end
end

local function StripLink(link)
	return (link:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", ""))
end

local function ItemPayload(link, count)
	local name, _, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(link)
	return {
		item = name or StripLink(link), link = link, quality = quality or 1,
		count = tonumber(count) or 1, icon = texture,
	}
end

local function ShortName(name)
	if Secret(name) then return name end
	if type(name) ~= "string" then return nil end
	return Ambiguate and Ambiguate(name, "short") or name
end

-- Fires once when a check turns true, not on every event while it stays true.
local edges = {}
local function Edge(key, now)
	local was = edges[key]
	edges[key] = now and true or false
	return now and not was
end
F.ResetEdges = function() wipe(edges) end

local CLASS_ICON = "Interface\\Icons\\ClassIcon_%s"
local function ClassIcon()
	local _, class = UnitClass("player")
	return class and CLASS_ICON:format(class:sub(1, 1) .. class:sub(2):lower()) or nil
end

-- What the change-watching sources saw last. Each one fires only
-- when a value it already knew rises; a value seen for the first time is
-- only noted, so logging in, zoning, a new group member or a header
-- expanded in the reputation list never fires. Plain values only: a
-- secret one is skipped, never compared.
local seen = { party = {}, skills = {}, factions = {}, friends = {}, guild = {} }
F.ResetSeen = function()
	for _, list in pairs(seen) do wipe(list) end
end

-- Notes value under key; true when it rose from a value seen before.
local function Rose(list, key, value)
	if key == nil or value == nil then return false end
	local was = list[key]
	list[key] = value
	return was ~= nil and value > was
end

local function PartyUnits()
	local units = {}
	for i = 1, 4 do units[#units + 1] = "party" .. i end
	return units
end

local function NoteParty()
	for _, unit in ipairs(PartyUnits()) do
		if UnitExists(unit) then
			local guid, level = Plain(UnitGUID(unit)), Plain(UnitLevel(unit))
			if guid and type(level) == "number" and level > 0 and seen.party[guid] == nil then seen.party[guid] = level end
		end
	end
end

-- Profession and secondary skills only (the skill line categories 11 and
-- 9); weapon, armor and language skills rise too often to celebrate.
local SKILL_CATEGORIES = { [9] = true, [11] = true }
local function ReadSkills(fire)
	local info = C_SkillInfo
	if not (info and info.GetNumSkillLines and info.GetSkillLineInfo) then return nil end
	local found
	for i = 1, Plain(info.GetNumSkillLines()) or 0 do
		local line = info.GetSkillLineInfo(i)
		if type(line) == "table" and not line.isHeader and SKILL_CATEGORIES[Plain(line.skillLineCategoryID) or 0] then
			local id, rank = Plain(line.skillID), Plain(line.rank)
			if type(id) == "number" and type(rank) == "number" and Rose(seen.skills, id, rank) and fire and not found then
				found = { skill = Plain(line.name) or "", rank = rank }
			end
		end
	end
	return found
end

local function StandingLabel(reaction)
	local label = rawget(_G, "FACTION_STANDING_LABEL" .. tostring(reaction))
	return type(label) == "string" and label or tostring(reaction)
end

local function ReadFactions(fire)
	local rep = C_Reputation
	if not (rep and rep.GetNumFactions and rep.GetFactionDataByIndex) then return nil end
	local found
	for i = 1, Plain(rep.GetNumFactions()) or 0 do
		local data = rep.GetFactionDataByIndex(i)
		if type(data) == "table" and (not data.isHeader or data.isHeaderWithRep) then
			local id, reaction = Plain(data.factionID), Plain(data.reaction)
			if type(id) == "number" and type(reaction) == "number" and Rose(seen.factions, id, reaction) and fire and not found then
				found = { faction = Plain(data.name) or "", standing = StandingLabel(reaction) }
			end
		end
	end
	return found
end

-- Friends on the friend list (not the "has come online" chat line, which
-- is secret during chat lockdown): online true / false by name.
local function ReadFriends(fire)
	local list = C_FriendList
	if not (list and list.GetNumFriends and list.GetFriendInfoByIndex) then return nil end
	local found
	for i = 1, Plain(list.GetNumFriends()) or 0 do
		local info = list.GetFriendInfoByIndex(i)
		local name = type(info) == "table" and Plain(info.name)
		if type(name) == "string" and name ~= "" and not Secret(info.connected) then
			local online = info.connected and 1 or 0
			if Rose(seen.friends, name, online) and fire and not found then
				found = { sender = ShortName(name) or name, level = Plain(info.level) or "", area = Plain(info.area) or "", who = "friend" }
			end
		end
	end
	return found
end

-- Guild members on the guild roster ("Who" = Guild or both): the
-- same online diff as friends, never the "has come online" chat line.
local function ReadGuild(fire)
	if not (IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo) then return nil end
	local found
	for i = 1, Plain(GetNumGuildMembers()) or 0 do
		local name, _, _, level, _, zone, _, _, online = GetGuildRosterInfo(i)
		name = Plain(name)
		if type(name) == "string" and name ~= "" and not Secret(online) and not E:IsMe(ShortName(name)) then
			if Rose(seen.guild, name, online and 1 or 0) and fire and not found then
				found = { sender = ShortName(name) or name, level = Plain(level) or "", area = Plain(zone) or "", who = "guild" }
			end
		end
	end
	return found
end

-- Flight masters this character has seen, saved per character, so a new
-- one fires even after a /reload.
E:RegisterPrivate("fanfare", { taxiNodes = {} })
local function TaxiStore()
	local store = E.GetPrivate and E:GetPrivate("fanfare")
	if type(store) ~= "table" then return nil end
	if type(store.taxiNodes) ~= "table" then store.taxiNodes = {} end
	return store
end

local function ReadTaxiNodes()
	local store = TaxiStore()
	local map = C_TaxiMap
	if not (store and map and map.GetAllTaxiNodes) then return nil end
	local mapID = Plain(GetTaxiMapID and GetTaxiMapID())
	if type(mapID) ~= "number" then return nil end
	local nodes = map.GetAllTaxiNodes(mapID)
	if type(nodes) ~= "table" then return nil end
	local unreachable = Enum.FlightPathState and Enum.FlightPathState.Unreachable or 2
	local known, first = store.taxiNodes, next(store.taxiNodes) == nil
	local found
	for _, node in ipairs(nodes) do
		local id, state = Plain(node.nodeID), Plain(node.state)
		if type(id) == "number" and state ~= nil and state ~= unreachable and not known[id] then
			known[id] = true
			-- The first flight map of a character only learns what it knows.
			if not first and not found then found = { zone = Plain(node.name) or "" } end
		end
	end
	return found
end

F.groupOrder = { "Progress", "Loot", "Social", "Group", "Instance", "PvP", "World", "Status" }

-- Conditions every source supports; sources add their own.
F.commonConditions = { instance = true, combat = true, group = true, resting = true, zone = true,
	minLevel = true, maxLevel = true, mounted = true, chance = true }

F.sources = {
	-- Progress
	levelup = {
		label = "Level up", group = "Progress", events = { "PLAYER_LEVEL_UP" },
		payload = function(_, level) return { level = Plain(level) or UnitLevel("player"), icon = ClassIcon() } end,
		tokens = { "level" }, sample = { level = 42 },
	},
	questdone = {
		label = "Quest turned in", group = "Progress", events = { "QUEST_TURNED_IN" },
		payload = function(_, questID)
			local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and Plain(C_QuestLog.GetTitleForQuestID(questID))
			return { quest = title or "" }
		end,
		tokens = { "quest" }, icon = "Interface\\GossipFrame\\ActiveQuestIcon", sample = { quest = "The Defias Brotherhood" },
	},
	achievement = {
		label = "Achievement earned", group = "Progress", events = { "ACHIEVEMENT_EARNED" },
		payload = function(_, id)
			local _, name, _, _, _, _, _, _, _, icon = GetAchievementInfo(id)
			return { achievement = Plain(name) or "", icon = icon }
		end,
		tokens = { "achievement" }, sample = { achievement = "Level 40" },
	},
	-- My Adventure's moment cards: no game event of its own. The
	-- journal hands each moment over (F:EmitMoment) once it shows it, so a
	-- trigger here plays or shows with that card. While such a trigger has
	-- a sound the card stays quiet: one moment, one sound.
	journalmoment = {
		label = "Journal moment", group = "Progress", events = {},
		payload = function() return nil end,
		tokens = { "title", "text", "kind" }, icon = "Interface\\Icons\\INV_Misc_Book_09",
		sample = { title = "Chapter 24", text = "Westfall", kind = "level" }, -- no-L
	},
	skillup = {
		label = "A profession skill rises", group = "Progress", events = { "SKILL_LINES_CHANGED" },
		payload = function() return ReadSkills(true) end,
		prime = function() ReadSkills(false) end,
		tokens = { "skill", "rank" }, icon = "Interface\\Icons\\INV_Misc_Note_01", sample = { skill = "Mining", rank = 75 },
	},
	repup = {
		label = "A reputation standing rises", group = "Progress", events = { "UPDATE_FACTION" },
		payload = function() return ReadFactions(true) end,
		prime = function() ReadFactions(false) end,
		tokens = { "faction", "standing" }, icon = "Interface\\Icons\\INV_Misc_Note_02", sample = { faction = "Stormwind", standing = "Honored" },
	},
	newspell = {
		label = "You learn a new spell", group = "Progress", events = { "LEARNED_SPELL_IN_SKILL_LINE" },
		payload = function(_, spellID, _, guildPerk)
			spellID = Plain(spellID)
			if type(spellID) ~= "number" or guildPerk == true then return nil end
			local spell = C_Spell and C_Spell.GetSpellName and Plain(C_Spell.GetSpellName(spellID))
			if not spell then return nil end
			return { spell = spell, icon = C_Spell.GetSpellTexture and Plain(C_Spell.GetSpellTexture(spellID)) or nil }
		end,
		tokens = { "spell" }, icon = "Interface\\Icons\\INV_Misc_Book_11", sample = { spell = "Frostbolt", icon = "Interface\\Icons\\Spell_Frost_FrostBolt02" },
	},
	rested = {
		label = "Became rested", group = "Progress", events = { "PLAYER_UPDATE_RESTING", "PLAYER_ENTERING_WORLD" },
		payload = function(event)
			local now = IsResting()
			if event == "PLAYER_ENTERING_WORLD" then Edge("rested", now); return nil end
			if Edge("rested", now) then return {} end
		end,
		icon = "Interface\\Icons\\Spell_Nature_Sleep", sample = {},
	},

	-- Loot
	wishdrop = {
		label = "A wishlist item drops", group = "Loot", events = { "CHAT_MSG_LOOT" },
		-- Your own loot of an item on the Loot Guide wishlist (Loot Guide on).
		payload = function(_, text)
			local LG = E.LootGuide
			if not (LG and LG.active and LG.IsWished) or Secret(text) or type(text) ~= "string" then return nil end
			local args = MatchAny(text, LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF_MULTIPLE, LOOT_ITEM_SELF, LOOT_ITEM_PUSHED_SELF)
			local link = args and args[1]
			if not link then return nil end
			local itemID = C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(link)
			if Plain(itemID) and LG:IsWished(itemID) then return ItemPayload(link, args[2]) end
			return nil
		end,
		tokens = { "item", "count" }, icon = "Interface\\Icons\\INV_Misc_Bag_10",
		sample = { item = "Lionheart Helm", quality = 4, count = 1, icon = "Interface\\Icons\\INV_Helmet_36" },
	},
	loot = {
		label = "You loot an item", group = "Loot", events = { "CHAT_MSG_LOOT" },
		payload = function(_, text)
			if Secret(text) or type(text) ~= "string" then return nil end
			local args = MatchAny(text, LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF_MULTIPLE, LOOT_ITEM_SELF, LOOT_ITEM_PUSHED_SELF)
			if args and args[1] then return ItemPayload(args[1], args[2]) end
		end,
		conditions = { minQuality = true }, tokens = { "item", "count" },
		sample = { item = "Thunderfury", quality = 5, count = 1, icon = "Interface\\Icons\\INV_Sword_39" },
	},
	rollwon = {
		label = "You win a loot roll", group = "Loot", events = { "CHAT_MSG_LOOT" },
		payload = function(_, text)
			if Secret(text) or type(text) ~= "string" then return nil end
			local args = MatchAny(text, LOOT_ROLL_YOU_WON)
			if args and args[1] then return ItemPayload(args[1], 1) end
		end,
		conditions = { minQuality = true }, tokens = { "item" },
		sample = { item = "Hand of Ragnaros", quality = 4, count = 1, icon = "Interface\\Icons\\INV_Hammer_Unique_Sulfuras" },
	},
	auctionsold = {
		label = "Auction sold", group = "Loot", events = { "CHAT_MSG_SYSTEM" },
		payload = function(_, text)
			if Secret(text) or type(text) ~= "string" then return nil end
			local args = MatchAny(text, ERR_AUCTION_SOLD_S)
			if args and args[1] then return { item = StripLink(args[1]) } end
		end,
		tokens = { "item" }, icon = "Interface\\Icons\\INV_Misc_Coin_02", sample = { item = "Linen Cloth" },
	},
	bagsfull = {
		label = "Bags are full", group = "Loot", events = { "BAG_UPDATE_DELAYED" },
		payload = function()
			local free = 0
			for bag = 0, NUM_BAG_SLOTS or 4 do
				local slots = C_Container.GetContainerNumFreeSlots(bag)
				free = free + (Plain(slots) or 0)
			end
			if Edge("bagsfull", free == 0) then return {} end
		end,
		icon = "Interface\\Icons\\INV_Misc_Bag_08", sample = {},
	},
	durability = {
		label = "Gear needs repair", group = "Loot", events = { "UPDATE_INVENTORY_DURABILITY" },
		payload = function()
			local lowest = 1
			for slot = 1, 19 do
				local current, maximum = GetInventoryItemDurability(slot)
				current, maximum = Plain(current), Plain(maximum)
				if current and maximum and maximum > 0 then lowest = math.min(lowest, current / maximum) end
			end
			if Edge("durability", lowest < 0.2) then return { percent = math.floor(lowest * 100) } end
		end,
		tokens = { "percent" }, icon = "Interface\\Icons\\Trade_BlackSmithing", sample = { percent = 15 },
	},

	-- Social
	whisper = {
		label = "Whisper", group = "Social", events = { "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER" },
		-- The sender may be secret during chat lockdown: it is still shown,
		-- but a "From" condition can't read it and doesn't fire.
		payload = function(_, _, sender) return { sender = ShortName(sender) or "" } end,
		conditions = { sender = true }, tokens = { "sender" },
		icon = "Interface\\ChatFrame\\UI-ChatWhisperIcon", sample = { sender = "Thrall" },
	},
	partyinvite = {
		label = "Group invite", group = "Social", events = { "PARTY_INVITE_REQUEST" },
		payload = function(_, sender) return { sender = ShortName(sender) or "" } end,
		conditions = { sender = true }, tokens = { "sender" }, icon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend", sample = { sender = "Jaina" },
	},
	trade = {
		label = "Trade window opens", group = "Social", events = { "TRADE_SHOW" },
		payload = function() return { sender = ShortName(UnitName("NPC")) or "" } end,
		conditions = { sender = true }, tokens = { "sender" }, icon = "Interface\\Icons\\INV_Misc_Coin_01", sample = { sender = "Garrosh" },
	},
	duel = {
		label = "Duel request", group = "Social", events = { "DUEL_REQUESTED" },
		payload = function(_, sender) return { sender = ShortName(sender) or "" } end,
		conditions = { sender = true }, tokens = { "sender" }, icon = "Interface\\Icons\\Ability_Warrior_Challange", sample = { sender = "Varian" },
	},
	friendonline = {
		label = "A friend comes online", group = "Social", events = { "FRIENDLIST_UPDATE", "GUILD_ROSTER_UPDATE" },
		payload = function(event)
			if event == "GUILD_ROSTER_UPDATE" then return ReadGuild(true) end
			return ReadFriends(true)
		end,
		prime = function() ReadFriends(false); ReadGuild(false) end,
		conditions = { sender = true, who = true }, tokens = { "sender", "area" },
		icon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend", sample = { sender = "Jaina", level = 60, area = "Ironforge" },
	},
	mail = {
		label = "New mail", group = "Social", events = { "UPDATE_PENDING_MAIL" },
		payload = function()
			if Edge("mail", HasNewMail() and true or false) then return {} end
		end,
		icon = "Interface\\Icons\\INV_Letter_15", sample = {},
	},

	-- Group
	readycheck = {
		label = "Ready check", group = "Group", events = { "READY_CHECK" },
		payload = function(_, initiator) return { sender = ShortName(initiator) or "" } end,
		tokens = { "sender" }, icon = "Interface\\RaidFrame\\ReadyCheck-Waiting", sample = { sender = "Anduin" },
	},
	groupding = {
		label = "A group member levels up", group = "Group", events = { "UNIT_LEVEL", "GROUP_ROSTER_UPDATE" },
		payload = function(event, unit)
			if event == "GROUP_ROSTER_UPDATE" then NoteParty(); return nil end
			if Secret(unit) or type(unit) ~= "string" or not unit:match("^party[1-4]$") then return nil end
			local guid, level = Plain(UnitGUID(unit)), Plain(UnitLevel(unit))
			if not guid or type(level) ~= "number" or level <= 0 then return nil end
			if Rose(seen.party, guid, level) then return { sender = ShortName(UnitName(unit)) or "", level = level } end
		end,
		prime = NoteParty,
		conditions = { sender = true }, tokens = { "sender", "level" },
		icon = "Interface\\Icons\\Achievement_Level_10", sample = { sender = "Anduin", level = 30 },
	},
	-- The moment only: the warning's text may be secret during chat
	-- lockdown and is never read.
	raidwarning = {
		label = "Raid warning", group = "Group", events = { "CHAT_MSG_RAID_WARNING" },
		payload = function() return {} end, icon = "Interface\\Icons\\Ability_Warrior_Challange", sample = {},
	},
	rolecheck = {
		label = "Role check", group = "Group", events = { "LFG_ROLE_CHECK_SHOW" },
		payload = function() return {} end, icon = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES", sample = {},
	},
	queuepop = {
		label = "Queue pops", group = "Group", events = { "LFG_PROPOSAL_SHOW", "UPDATE_BATTLEFIELD_STATUS" },
		payload = function(event, index)
			if event == "LFG_PROPOSAL_SHOW" then return { queue = L["Dungeon"] } end
			local status = index and GetBattlefieldStatus and GetBattlefieldStatus(index)
			if Edge("bg" .. tostring(index), status == "confirm") then return { queue = L["Battleground"] } end
		end,
		tokens = { "queue" }, icon = "Interface\\LFGFrame\\LFG-Eye", sample = { queue = E.Key("Dungeon") },
	},
	summon = {
		label = "Summon offered", group = "Group", events = { "CONFIRM_SUMMON" },
		payload = function()
			local info = C_SummonInfo
			return {
				sender = info and ShortName(info.GetSummonConfirmSummoner()) or "",
				area = info and Plain(info.GetSummonConfirmAreaName()) or "",
			}
		end,
		tokens = { "sender", "area" }, icon = "Interface\\Icons\\Spell_Shadow_Twilight", sample = { sender = "Khadgar", area = "Ironforge" },
	},
	resurrect = {
		label = "Resurrection offered", group = "Group", events = { "RESURRECT_REQUEST" },
		payload = function(_, sender) return { sender = ShortName(sender) or "" } end,
		tokens = { "sender" }, icon = "Interface\\Icons\\Spell_Holy_Resurrection", sample = { sender = "Velen" },
	},
	pull = {
		label = "Pull timer starts", group = "Group", events = { "START_TIMER" },
		-- Only a player's countdown (/countdown, raid tools), not the
		-- battleground gate timer or the other countdowns on this event.
		payload = function(_, timerType, timeRemaining)
			local wanted = Enum.StartTimerType and Enum.StartTimerType.PlayerCountdown or 2
			if not Plain(timerType) or timerType ~= wanted then return nil end
			return { seconds = Plain(timeRemaining) or "" }
		end,
		tokens = { "seconds" }, icon = "Interface\\Icons\\Ability_Warrior_Charge", sample = { seconds = 10 },
	},

	-- Instance
	bosskill = {
		label = "Boss killed", group = "Instance", events = { "ENCOUNTER_END" },
		payload = function(_, _, name, _, _, success)
			if success == 1 or success == true then return { boss = Plain(name) or "" } end
		end,
		tokens = { "boss" }, icon = "Interface\\Icons\\Achievement_Boss_Ragnaros", sample = { boss = "Ragnaros" },
	},
	wipe = {
		label = "Boss wipe", group = "Instance", events = { "ENCOUNTER_END" },
		payload = function(_, _, name, _, _, success)
			if success == 0 or success == false then return { boss = Plain(name) or "" } end
		end,
		tokens = { "boss" }, icon = "Interface\\Icons\\Ability_Rogue_FeignDeath", sample = { boss = "Onyxia" },
	},
	death = {
		label = "You die", group = "Instance", events = { "PLAYER_DEAD" },
		payload = function() return {} end, icon = "Interface\\Icons\\Ability_Rogue_FeignDeath", sample = {},
	},
	-- The game's own loss of control alert on you.
	losscontrol = {
		label = "You lose control", group = "Instance", events = { "LOSS_OF_CONTROL_ADDED" },
		payload = function(_, unit)
			if Secret(unit) or unit ~= "player" then return nil end
			return {}
		end,
		icon = "Interface\\Icons\\Spell_Nature_Sleep", sample = {},
	},
	combatstart = {
		label = "Enter combat", group = "Instance", events = { "PLAYER_REGEN_DISABLED" },
		payload = function() return {} end, icon = "Interface\\Icons\\Ability_DualWield", sample = {},
	},
	combatend = {
		label = "Leave combat", group = "Instance", events = { "PLAYER_REGEN_ENABLED" },
		payload = function() return {} end, icon = "Interface\\Icons\\Ability_Rogue_Sprint", sample = {},
	},

	-- PvP
	honorkill = {
		label = "Honorable kill", group = "PvP", events = { "CHAT_MSG_COMBAT_HONOR_GAIN" },
		payload = function() return {} end, icon = "Interface\\Icons\\Achievement_PVP_A_01", sample = {},
	},
	bgstart = {
		label = "Battleground starts", group = "PvP", events = { "PVP_MATCH_ACTIVE" },
		payload = function() return {} end, icon = "Interface\\Icons\\INV_BannerPVP_02", sample = {},
	},
	bgend = {
		label = "Battleground ends", group = "PvP", events = { "PVP_MATCH_COMPLETE" },
		payload = function() return {} end, icon = "Interface\\Icons\\INV_BannerPVP_01", sample = {},
	},

	-- World
	flightlanded = {
		label = "Flight landed", group = "World", events = { "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED" },
		payload = function(event)
			if event == "PLAYER_CONTROL_LOST" then
				-- The taxi flag is set just after control is lost.
				C_Timer.After(1, function() if UnitOnTaxi("player") then edges.taxi = true end end)
				return nil
			end
			if edges.taxi then
				edges.taxi = nil
				return { zone = Plain(GetRealZoneText()) or "" }
			end
		end,
		tokens = { "zone" }, icon = "Interface\\Icons\\Ability_Mount_Gryphon_01", sample = { zone = "Stormwind City" },
	},
	newflight = {
		label = "You find a new flight path", group = "World", events = { "TAXIMAP_OPENED" },
		payload = function() return ReadTaxiNodes() end,
		tokens = { "zone" }, icon = "Interface\\Icons\\Ability_Mount_Gryphon_01", sample = { zone = "Sentinel Hill, Westfall" },
	},
	zone = {
		label = "Enter a new zone", group = "World", events = { "ZONE_CHANGED_NEW_AREA" },
		payload = function() return { zone = Plain(GetRealZoneText()) or "" } end,
		tokens = { "zone" }, icon = "Interface\\Icons\\INV_Misc_Map_01", sample = { zone = "Elwynn Forest" },
	},
	rare = {
		label = "Rare spotted", group = "World", events = { "VIGNETTE_MINIMAP_UPDATED" },
		payload = function(_, guid, onMinimap)
			-- Rare Alerts on: it feeds this source itself (M:Emit) from
			-- every source, after its own dedupe, so one rare = one alert.
			local scanner = E.RareScanner
			if scanner and scanner.active then return nil end
			if not onMinimap or Secret(guid) or IsInInstance() then return nil end
			local info = C_VignetteInfo and C_VignetteInfo.GetVignetteInfo(guid)
			if not info or Secret(info.atlasName) or type(info.atlasName) ~= "string" then return nil end
			if not info.atlasName:find("VignetteKill") then return nil end
			-- One alert per rare until it leaves the minimap list.
			if edges["rare" .. guid] then return nil end
			edges["rare" .. guid] = true
			return { name = Plain(info.name) or "" }
		end,
		tokens = { "name" }, icon = "Interface\\Icons\\Ability_Hunter_SniperShot", sample = { name = "Time-Lost Proto-Drake" },
	},
	login = {
		label = "Log in", group = "World", events = { "PLAYER_ENTERING_WORLD" },
		payload = function(_, isLogin) if isLogin then return {} end end,
		icon = "Interface\\Icons\\Achievement_Character_Human_Male", sample = {}, noGrace = true,
	},

	-- Status
	afk = {
		label = "You go AFK", group = "Status", events = { "PLAYER_FLAGS_CHANGED" },
		payload = function(_, unit)
			if unit ~= "player" then return nil end
			local afk = UnitIsAFK("player")
			if Secret(afk) then return nil end
			if Edge("afk", afk and true or false) then return {} end
		end,
		icon = "Interface\\Icons\\Spell_Nature_Sleep", sample = {},
	},
}

-- Sorted source keys for the editor, by group then label.
function F:SourceValues()
	local values = {}
	for key, source in pairs(self.sources) do
		values[key] = ("%s " .. E:TextHex("secondary") .. "· %s|r"):format(L[source.label], L[source.group])
	end
	return values
end

function F:SourceAllows(key, condition)
	local source = self.sources[key]
	if not source then return false end
	if self.commonConditions[condition] then return true end
	return source.conditions and source.conditions[condition] or false
end

-- What Fanfare already does for a source, for other modules that
-- would otherwise play or show the same moment twice: sound is true
-- when an enabled trigger on it plays a sound (and sounds are not muted),
-- text when one shows its big text or icon. Both false while the module
-- is off.
function F:Covers(key)
	local M = self.module
	if not (M and M.active and type(M.db) == "table" and type(M.db.triggers) == "table") or not self.sources[key] then
		return false, false
	end
	local sound, text = false, false
	for _, trigger in pairs(M.db.triggers) do
		local actions = type(trigger) == "table" and trigger.actions
		if type(actions) == "table" and not trigger.deleted and trigger.enabled and trigger.source == key then
			if type(actions.sound) == "table" and actions.sound.id and actions.sound.id ~= "none" and not M.db.mute then sound = true end
			if (type(actions.splash) == "table" and actions.splash.enabled) or (type(actions.icon) == "table" and actions.icon.enabled) then
				text = true
			end
		end
	end
	return sound, text
end

function E:FanfareCovers(key)
	return F:Covers(key)
end

-- A My Adventure moment for the "Journal moment" triggers: data = { kind,
-- title, text, icon }, plain strings only. Returns how many triggers fired.
function F:EmitMoment(data)
	local M = self.module
	if not (M and M.active and type(M.Emit) == "function") or type(data) ~= "table" then return 0 end
	return M:Emit("journalmoment", {
		kind = Plain(data.kind) or "", title = Plain(data.title) or "", text = Plain(data.text) or "", icon = data.icon,
	})
end
