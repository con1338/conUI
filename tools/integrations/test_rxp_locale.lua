-- Offline test for EldoUI/Modules/IntegrationsRXPLocale.lua: RestedXP's
-- English paid guides on a client in another language.
-- Run from the repository root:
--   lua5.1 tools/integrations/test_rxp_locale.lua
-- Found on 16.11.2026 in RestedXP Guides v4.11.36 on a German WoW: Forever
-- 1.60.1 (code read, the paid guides counted from the player's guide cache;
-- not yet seen in the game):
-- 1. 556 of the paid guides' target names differ in German and are not on
--    RestedXP's own list, so the target macro looked for English names.
-- 2. The free German guides end with "next guide" names that only exist in
--    English ("22-24 Hügellandhof" for the paid "22-24 Hillsbrad").
-- 3. RestedXP's German list names "RestedXP Forever Guide" "Dungeonführer"
--    and "RestedXP Forever Dungeon Guide" "Dungeon Dungeonführer"; its
--    default group came out as the free dungeon guide.
-- 4. The leveling report skips quest experience only by its English start.
-- This loads the real IntegrationsRXPLocale.lua into a model of RestedXP and
-- QuestieDB. The RestedXP functions here are stand-ins written after what
-- v4.11.36 does (named in each), not RestedXP's code: GetCreatureName
-- (locale/NPCnames.lua), GetGuideTable (RXPGuides.lua), the guide list and
-- GetActiveGuidesByGroupNameOrId with its translated group name
-- (GuideLoader.lua), the default group from the translated name
-- (DB/forever/db.lua), ScheduleTask and the tracker's XP handler
-- (LevelingTracker.lua).
-- Checked: target names come from QuestieDB once its names are read, in
-- steps and not during a fight, RestedXP's own list and same names stay,
-- the "*" mark, NPC ids, several NPCs with one English name, no QuestieDB or
-- the wrong contract; the guide chain into the paid guides by the known
-- names, by level range, never to a guide the player can't use or when two
-- fit; the guide assistant lists free and paid guides together; the group
-- names and default group are fixed only while they are RestedXP's wrong
-- ones and come back when switched off; quest experience in German leaves
-- the monster count; switched off, the module off or an English client:
-- RestedXP answers as before. A French client gets the names and the
-- leveling report, not the German guide data.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/integrations/") or "./"

local function ReadFile(path)
	local file = assert(io.open(ROOT .. path, "rb"), "can't open " .. path)
	local text = file:read("*a")
	file:close()
	return (text:gsub("\r\n", "\n"))
end

local SOURCE = ReadFile("EldoUI/Modules/IntegrationsRXPLocale.lua")

---------------------------------------------------------------------------
-- Model of the game, RestedXP and QuestieDB
---------------------------------------------------------------------------
local world

-- RestedXP's German texts for the four group names as v4.11.36 ships them.
local function ShippedTexts()
	return {
		["RestedXP Forever Guide (A)"] = "RestedXP Forever Dungeonführer (A)",
		["RestedXP Forever Guide (H)"] = "RestedXP Forever Dungeonführer (H)",
		["RestedXP Forever Dungeon Guide (A)"] = "RestedXP Forever Dungeon Dungeonführer (A)",
		["RestedXP Forever Dungeon Guide (H)"] = "RestedXP Forever Dungeon Dungeonführer (H)",
		["Go to "] = "Geht zu ",
	}
end

local FILLERS = 1200 -- more NPCs than one reading step takes

local function NewNpcs()
	local npcs = {
		[1] = { en = "Southsea Pirate", here = "Pirat der Südmeerfreibeuter" },
		[2] = { en = "Defias Thug", here = "Defias-Rohling (QuestieDB)" },
		[3] = { en = "Tideress", here = "Tideress" },
		[4] = { en = "Tortured Sentinel", here = "Gequälte Schildwache" },
		[5] = { en = "Tortured Sentinel", here = "Gequälter Schildwächter" },
		[6] = { en = "Tortured Sentinel", here = "Gequälte Schildwache" },
		[7] = { en = "Angerclaw Bear", here = "Wutklauenbär" },
		[8] = { en = "Furbolg", here = nil }, -- no German name in QuestieDB
		[2001] = { en = "Kobold Vermin", here = "Koboldgezücht" },
	}
	for i = 1, FILLERS do npcs[10000 + i] = { en = "Filler " .. i, here = "Füller " .. i } end
	return npcs
end

local function NewWorld(opts)
	opts = opts or {}
	world = {
		locale = opts.locale or "deDE",
		combat = false,
		tickers = {},
		loaded = { RXPGuides = true, QuestieDB = opts.questie ~= false },
		contract = opts.contract or 4,
		npcs = NewNpcs(),
		texts = ShippedTexts(),
		gets = 0,
	}
	if world.loaded.QuestieDB then
		local ids = {}
		for id in pairs(world.npcs) do ids[#ids + 1] = id end
		table.sort(ids)
		_G.LibQuestieDB = {
			RequireContract = function(version) return version <= world.contract and version >= 3 end,
			Npc = {
				GetAllIds = function() return ids end,
				GetRaw = function(id, key)
					assert(key == "name")
					return world.npcs[id] and world.npcs[id].en
				end,
				Get = function(id, key)
					assert(key == "name")
					world.gets = world.gets + 1
					local npc = world.npcs[id]
					return npc and (npc.here or npc.en)
				end,
			},
		}
	else
		_G.LibQuestieDB = nil
	end
end

function GetLocale() return world.locale end
function InCombatLockdown() return world.combat end
C_AddOns = { IsAddOnLoaded = function(name) return world.loaded[name] or false end }
C_Timer = {
	NewTicker = function(_, fn)
		local ticker = { fn = fn }
		function ticker.Cancel(self) self.cancelled = true end
		world.tickers[#world.tickers + 1] = ticker
		return ticker
	end,
}

local function Tick(rounds)
	for _ = 1, rounds or 1 do
		for _, ticker in ipairs(world.tickers) do
			if not ticker.cancelled then ticker.fn() end
		end
	end
end

-- RestedXP as the player has it: free German guides, paid English ones.
local function NewRXP()
	local rxp = { guides = {}, guideList = {}, scheduled = {}, tracker = {}, mobXP = 0 }
	rxp.npcNames = { ["Defias Thug"] = "Rohling der Defias" } -- locale/NPCnames.lua, deDE
	function rxp.GetCreatureName(name)
		return rxp.npcNames and rxp.npcNames[name] or name
	end
	-- addon.locale.Get: the text, else the English one.
	function rxp.L(text) return world.texts[text] or text end
	function rxp.Add(group, name, active)
		local guide = { group = group, name = name, active = active ~= false }
		rxp.guides[group .. "||" .. name] = guide
		local list = rxp.guideList[group] or { names_ = {} }
		rxp.guideList[group] = list
		list.names_[#list.names_ + 1] = { name = name, group = group }
		return guide
	end
	function rxp.GetGuideTable(group, name)
		local index = group and name and (group .. "||" .. name) or group or 0
		return rxp.guides[index]
	end
	function rxp.IsGuideActive(guide) return guide.active end
	-- GuideLoader.lua: each identity through addon.GetGuideTable, and a
	-- group also by its translated name.
	function rxp.GetActiveGuidesInGroup(display)
		local list, guides = rxp.guideList[display], {}
		for _, identity in ipairs(list and list.names_ or {}) do
			local guide = rxp.GetGuideTable(identity.group, identity.name)
			if guide and rxp.IsGuideActive(guide) then guides[#guides + 1] = guide end
		end
		return guides
	end
	function rxp.GetActiveGuidesByGroupNameOrId(groupName)
		local guides, seen = {}, {}
		if not groupName then return guides end
		local translated = rxp.L(groupName)
		for display in pairs(rxp.guideList) do
			if display == groupName or display == translated then
				for _, guide in ipairs(rxp.GetActiveGuidesInGroup(display)) do
					if not seen[guide] then
						seen[guide] = true
						guides[#guides + 1] = guide
					end
				end
			end
		end
		return guides
	end
	function rxp.ScheduleTask(self, ref)
		assert(self == rxp, "ScheduleTask is called with RestedXP as self")
		rxp.scheduled[#rxp.scheduled + 1] = ref
	end
	rxp.targeting = { UpdateUnitList = function() end }
	-- LevelingTracker.lua: the quest's message is skipped by its English start.
	function rxp.tracker:CHAT_MSG_COMBAT_XP_GAIN(_, text)
		if text:sub(1, 3) == "You" then return end
		rxp.mobXP = rxp.mobXP + tonumber(text:match("%d+"))
	end
	-- DB/forever/db.lua (Horde): the default group from the translated name.
	rxp.defaultGroup = rxp.L("RestedXP Forever Guide (H)")
	rxp.defaultGroupHC = rxp.L("RestedXP Forever Guide (H)")

	local g = {}
	g.barrens = rxp.Add("RestedXP Forever Route (H)", "17-22 Steinkrallengebirge/Brachland/Eschental")
	g.darkshore = rxp.Add("RestedXP Forever Route (A)", "19-21 Dunkelküste/Eschental")
	g.wailing = rxp.Add("RestedXP Forever Dungeonführer (H)", "21-22 Die Höhlen des Wehklagens")
	g.mageFree = rxp.Add("RestedXP Horde Magier AoE", "17-21 Steinkrallengebirge/Brachland AoE")
	g.hillsbrad = rxp.Add("RestedXP Forever Guide (H)", "22-24 Hillsbrad")
	g.southern = rxp.Add("RestedXP Forever Guide (H)", "24-26 Southern Barrens/Stonetalon")
	g.ashenvale = rxp.Add("RestedXP Forever Guide (A)", "21-23 Ashenvale/Stonetalon")
	g.stonetalon = rxp.Add("RestedXP Forever Guide (A)", "21-23 Stonetalon/Ashenvale")
	g.wetlands = rxp.Add("RestedXP Forever Guide (A)", "23-24 Wetlands")
	g.wetlandsHunter = rxp.Add("RestedXP Forever Guide (A)", "23-24 Wetlands Hunter", false)
	g.dungeonHillsbrad = rxp.Add("RestedXP Forever Dungeon Guide (H)", "22-24 Hillsbrad")
	g.sfk = rxp.Add("RestedXP Forever Dungeon Guide (H)", "24-25 Shadowfang Keep")
	g.magePaid = rxp.Add("RestedXP Horde Mage AoE", "21-30 Silverpine/Hillsbrad AoE")
	rxp.g = g
	return rxp
end

LibStub = function(major)
	if major == "AceAddon-3.0" then
		return { GetAddon = function(_, name) return world.addons[name] end }
	elseif major == "AceLocale-3.0" then
		return { GetLocale = function(_, app) return app == "RXPGuides" and world.texts or nil end }
	end
end

-- The game's texts in German, as RestedXP gets them.
_G.COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED = "Ihr bekommt %d Erfahrung."
_G.COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_GROUP = "Ihr bekommt %d Erfahrung. (+%d Gruppenbonus)"
_G.COMBATLOG_XPGAIN_QUEST = "Ihr erhaltet %1$d Erfahrung für die Quest."

-- The real file, loaded fresh for each world: it reads the client language
-- once. Returns the module and RestedXP.
local function Load(opts)
	NewWorld(opts)
	local rxp = NewRXP()
	world.addons = { RXPGuides = rxp }
	local M = { active = true, db = { enabled = true, rxp = { enabled = true, locale = true } } }
	local E = {
		L = setmetatable({}, { __index = function(_, key) return key end }),
		GetModule = function(_, name)
			assert(name == "Integrations")
			return M
		end,
	}
	local chunk = assert(loadstring(SOURCE, "@EldoUI/Modules/IntegrationsRXPLocale.lua"))
	chunk("EldoUI", E)
	return M, rxp
end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
local passed, failed = 0, 0
local function Check(name, ok, detail)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL " .. name .. (detail and (": " .. tostring(detail)) or ""))
	end
end
local function Equal(name, got, want) Check(name, got == want, ("got %s, want %s"):format(tostring(got), tostring(want))) end

local function Has(list, guide)
	for _, each in ipairs(list) do if each == guide then return true end end
	return false
end
local function Count(list, guide)
	local n = 0
	for _, each in ipairs(list) do if each == guide then n = n + 1 end end
	return n
end

-- Target names --------------------------------------------------------------
do
	local M, rxp = Load()
	local own = rxp.GetCreatureName
	M:SetupRXPLocale()
	Check("names: GetCreatureName is wrapped", rxp.GetCreatureName ~= own)
	Equal("names: before reading, RestedXP's answer", rxp.GetCreatureName("Southsea Pirate"), "Southsea Pirate")
	Equal("names: an NPC id needs no reading", rxp.GetCreatureName("2001"), "Koboldgezücht")
	Check("names: the status says it is reading", M:RXPLocaleStatus():find("reading QuestieDB's NPC names (0%)", 1, true),
		M:RXPLocaleStatus())
	Tick(1)
	Equal("names: one step reads 500 NPCs", M.rxpLocaleNames.done, 500)
	Check("names: the status shows the share", M:RXPLocaleStatus():find("(41%)", 1, true), M:RXPLocaleStatus())
	world.combat = true
	Tick(3)
	Equal("names: no reading during a fight", M.rxpLocaleNames.done, 500)
	world.combat = false
	Equal("names: still English while reading", rxp.GetCreatureName("Southsea Pirate"), "Southsea Pirate")
	Check("names: no target refresh before the end", #rxp.scheduled == 1, #rxp.scheduled) -- the one from switching on
	Tick(5)
	Equal("names: all read", M.rxpLocaleNames.state, "ready")
	Equal("names: the target list is built again", rxp.scheduled[#rxp.scheduled], rxp.targeting.UpdateUnitList)
	Equal("names: from QuestieDB", rxp.GetCreatureName("Southsea Pirate"), "Pirat der Südmeerfreibeuter")
	Equal("names: RestedXP's own list first", rxp.GetCreatureName("Defias Thug"), "Rohling der Defias")
	Equal("names: the same name stays", rxp.GetCreatureName("Tideress"), "Tideress")
	Equal("names: no German name stays English", rxp.GetCreatureName("Furbolg"), "Furbolg")
	Equal("names: unknown stays", rxp.GetCreatureName("Nobody Known"), "Nobody Known")
	Equal("names: the name most NPCs have", rxp.GetCreatureName("Tortured Sentinel"), "Gequälte Schildwache")
	Equal("names: the mark stays on a translated name", rxp.GetCreatureName("*Angerclaw Bear"), "*Wutklauenbär")
	Equal("names: the mark with RestedXP's own list", rxp.GetCreatureName("*Defias Thug"), "*Rohling der Defias")
	Equal("names: a non-name passes", rxp.GetCreatureName(nil), nil)
	Check("names: the status counts the names", M:RXPLocaleStatus():find("Target names: ", 1, true)
		and M:RXPLocaleStatus():find("translated with QuestieDB", 1, true), M:RXPLocaleStatus())
	local gets = world.gets
	rxp.GetCreatureName("Southsea Pirate")
	Equal("names: a name is looked up once", world.gets, gets)
	local wrapper = rxp.GetCreatureName
	M:SetupRXPLocale()
	Equal("names: wrapped once", rxp.GetCreatureName, wrapper)
	Equal("names: read once", #world.tickers, 1)
	M.db.rxp.locale = false
	M:SetupRXPLocale()
	Equal("names: switched off, RestedXP's answer", rxp.GetCreatureName("Southsea Pirate"), "Southsea Pirate")
	Equal("names: switched off, no status", M:RXPLocaleStatus(), "")
	M.db.rxp.locale = true
	M.active = false
	Equal("names: module off, RestedXP's answer", rxp.GetCreatureName("Southsea Pirate"), "Southsea Pirate")
	M.active = true
	M.db.rxp.enabled = false
	Equal("names: integration off, RestedXP's answer", rxp.GetCreatureName("Southsea Pirate"), "Southsea Pirate")
end

do -- switched off while reading: it starts over when on again
	local M, rxp = Load()
	M:SetupRXPLocale()
	Tick(1)
	M.db.rxp.locale = false
	M:SetupRXPLocale()
	Tick(1)
	Equal("names: off while reading stops", M.rxpLocaleNames.state, "idle")
	M.db.rxp.locale = true
	M:SetupRXPLocale()
	Tick(10)
	Equal("names: on again reads them all", M.rxpLocaleNames.state, "ready")
	Equal("names: and they work", rxp.GetCreatureName("Southsea Pirate"), "Pirat der Südmeerfreibeuter")
end

do -- no QuestieDB, then QuestieDB with the wrong contract
	local M, rxp = Load({ questie = false })
	M:SetupRXPLocale()
	Equal("no QuestieDB: RestedXP's answer", rxp.GetCreatureName("Southsea Pirate"), "Southsea Pirate")
	Equal("no QuestieDB: nothing read", #world.tickers, 0)
	Check("no QuestieDB: the status says so", M:RXPLocaleStatus():find("QuestieDB is not loaded", 1, true), M:RXPLocaleStatus())
	Equal("no QuestieDB: the guide chain still works",
		rxp.GetGuideTable("RestedXP Forever Route (H)", "22-24 Hügellandhof"), rxp.g.hillsbrad)
	M, rxp = Load({ contract = 2 })
	M:SetupRXPLocale()
	Equal("old contract: not used", #world.tickers, 0)
	Equal("old contract: RestedXP's answer", rxp.GetCreatureName("2001"), "2001")
end

-- The guide chain ---------------------------------------------------------------
do
	local M, rxp = Load()
	local g = rxp.g
	Equal("chain: RestedXP alone finds nothing", rxp.GetGuideTable("RestedXP Forever Route (H)", "22-24 Hügellandhof"), nil)
	M:SetupRXPLocale()
	Equal("chain: Horde route into the paid guide",
		rxp.GetGuideTable("RestedXP Forever Route (H)", "22-24 Hügellandhof"), g.hillsbrad)
	Equal("chain: Horde dungeon guide into the paid dungeon guide",
		rxp.GetGuideTable("RestedXP Forever Dungeonführer (H)", "22-24 Hügellandhof"), g.dungeonHillsbrad)
	Equal("chain: Alliance, Ashenvale first",
		rxp.GetGuideTable("RestedXP Forever Route (A)", "21-23 Eschental/Steinkrallengebirge"), g.ashenvale)
	Equal("chain: Alliance, Stonetalon first",
		rxp.GetGuideTable("RestedXP Forever Route (A)", "21-23 Steinkrallengebirge/Ashenvale"), g.stonetalon)
	Equal("chain: mage guide",
		rxp.GetGuideTable("RestedXP Horde Magier AoE", "21-30 Silberwald/Hillsbrad AoE"), g.magePaid)
	Equal("chain: an unknown name by its level range",
		rxp.GetGuideTable("RestedXP Forever Route (H)", "24-26 Südliches Brachland/Steinkrallengebirge"), g.southern)
	Equal("chain: by range only to a guide the player can use",
		rxp.GetGuideTable("RestedXP Forever Route (A)", "23-24 Sumpfland"), g.wetlands)
	Equal("chain: two guides for that range, none picked",
		rxp.GetGuideTable("RestedXP Forever Route (A)", "21-23 Anderswo"), nil)
	Equal("chain: no paid guide for that range",
		rxp.GetGuideTable("RestedXP Forever Route (H)", "12-14 Silberwald"), nil)
	Equal("chain: a guide RestedXP has stays",
		rxp.GetGuideTable("RestedXP Forever Route (H)", "17-22 Steinkrallengebirge/Brachland/Eschental"), g.barrens)
	Equal("chain: the English group finds the free guide",
		rxp.GetGuideTable("RestedXP Forever Guide (H)", "17-22 Steinkrallengebirge/Brachland/Eschental"), g.barrens)
	Equal("chain: other groups as before", rxp.GetGuideTable("RestedXP Horde 22-30", "22-24 Hügellandhof"), nil)
	Equal("chain: a group alone as before", rxp.GetGuideTable("RestedXP Forever Route (H)"), nil)
	M.db.rxp.locale = false
	Equal("chain: switched off, as before", rxp.GetGuideTable("RestedXP Forever Route (H)", "22-24 Hügellandhof"), nil)
end

-- The guide assistant's lists -------------------------------------------------
do
	local M, rxp = Load()
	local g = rxp.g
	-- As shipped: the dungeon route asks for a group nobody has.
	local asked = rxp.L("RestedXP Forever Dungeon Guide (H)")
	Equal("lists: RestedXP alone, dungeon route empty", #rxp.GetActiveGuidesByGroupNameOrId(asked), 0)
	local open = rxp.GetActiveGuidesByGroupNameOrId(rxp.defaultGroup)
	Check("lists: RestedXP alone, open world shows the dungeon guide", Has(open, g.wailing) and not Has(open, g.barrens))
	M:SetupRXPLocale()
	asked = rxp.L("RestedXP Forever Dungeon Guide (H)")
	Equal("lists: the dungeon route asks for the free dungeon group", asked, "RestedXP Forever Dungeonführer (H)")
	local dungeon = rxp.GetActiveGuidesByGroupNameOrId(asked)
	Check("lists: dungeon route, free and paid", Has(dungeon, g.wailing) and Has(dungeon, g.dungeonHillsbrad) and Has(dungeon, g.sfk))
	Check("lists: dungeon route, no open-world guides", not Has(dungeon, g.hillsbrad) and not Has(dungeon, g.barrens))
	open = rxp.GetActiveGuidesByGroupNameOrId(rxp.defaultGroup)
	Check("lists: open world, free and paid", Has(open, g.barrens) and Has(open, g.hillsbrad) and Has(open, g.southern))
	Check("lists: open world, no dungeon guides", not Has(open, g.wailing) and not Has(open, g.dungeonHillsbrad))
	local english = rxp.GetActiveGuidesByGroupNameOrId("RestedXP Forever Guide (H)")
	Check("lists: by the English name too", Has(english, g.barrens) and Has(english, g.hillsbrad))
	Equal("lists: each guide once", Count(english, g.barrens) + Count(english, g.hillsbrad), 2)
	Check("lists: an inactive guide stays out",
		not Has(rxp.GetActiveGuidesByGroupNameOrId("RestedXP Forever Route (A)"), g.wetlandsHunter))
	Equal("lists: other groups as before", #rxp.GetActiveGuidesByGroupNameOrId("RestedXP Horde 22-30"), 0)
	M.db.rxp.locale = false
	M:SetupRXPLocale()
	Equal("lists: switched off, as shipped", #rxp.GetActiveGuidesByGroupNameOrId(rxp.L("RestedXP Forever Dungeon Guide (H)")), 0)
end

-- RestedXP's group names --------------------------------------------------------
do
	local M, rxp = Load()
	world.texts["RestedXP Forever Guide (A)"] = "RestedXP Forever Route (A)" -- as if RestedXP fixed it itself
	M:SetupRXPLocale()
	Equal("texts: open world", world.texts["RestedXP Forever Guide (H)"], "RestedXP Forever Route (H)")
	Equal("texts: dungeon (A)", world.texts["RestedXP Forever Dungeon Guide (A)"], "RestedXP Forever Dungeonführer (A)")
	Equal("texts: dungeon (H)", world.texts["RestedXP Forever Dungeon Guide (H)"], "RestedXP Forever Dungeonführer (H)")
	Equal("texts: one RestedXP fixed itself stays", world.texts["RestedXP Forever Guide (A)"], "RestedXP Forever Route (A)")
	Equal("texts: other texts stay", world.texts["Go to "], "Geht zu ")
	Equal("texts: the default group", rxp.defaultGroup, "RestedXP Forever Route (H)")
	Equal("texts: the hardcore default group", rxp.defaultGroupHC, "RestedXP Forever Route (H)")
	M:SetupRXPLocale()
	Equal("texts: twice changes nothing more", world.texts["RestedXP Forever Guide (H)"], "RestedXP Forever Route (H)")
	rxp.defaultGroupHC = "RestedXP Something Else" -- changed since by someone else
	M.db.rxp.locale = false
	M:SetupRXPLocale()
	Equal("texts: off, RestedXP's text again", world.texts["RestedXP Forever Guide (H)"], "RestedXP Forever Dungeonführer (H)")
	Equal("texts: off, dungeon again", world.texts["RestedXP Forever Dungeon Guide (H)"], "RestedXP Forever Dungeon Dungeonführer (H)")
	Equal("texts: off, the one it didn't change", world.texts["RestedXP Forever Guide (A)"], "RestedXP Forever Route (A)")
	Equal("texts: off, the default group back", rxp.defaultGroup, "RestedXP Forever Dungeonführer (H)")
	Equal("texts: off, a later change stays", rxp.defaultGroupHC, "RestedXP Something Else")
	M.db.rxp.locale = true
	M:SetupRXPLocale()
	Equal("texts: on again", world.texts["RestedXP Forever Guide (H)"], "RestedXP Forever Route (H)")
end

-- The leveling report -----------------------------------------------------------
do
	local M, rxp = Load()
	M:SetupRXPLocale()
	local tracker = rxp.tracker
	tracker:CHAT_MSG_COMBAT_XP_GAIN("CHAT_MSG_COMBAT_XP_GAIN", "Ihr bekommt 360 Erfahrung.")
	tracker:CHAT_MSG_COMBAT_XP_GAIN("CHAT_MSG_COMBAT_XP_GAIN", "Ihr bekommt 120 Erfahrung. (+12 Gruppenbonus)")
	tracker:CHAT_MSG_COMBAT_XP_GAIN("CHAT_MSG_COMBAT_XP_GAIN", "Ihr erhaltet 80 Erfahrung für die Quest.")
	Equal("report: quest experience leaves the monster count", rxp.mobXP, 0)
	tracker:CHAT_MSG_COMBAT_XP_GAIN("CHAT_MSG_COMBAT_XP_GAIN", "Kobold stirbt, Ihr bekommt 45 Erfahrung.")
	Equal("report: a monster still counts", rxp.mobXP, 45)
	M.db.rxp.locale = false
	tracker:CHAT_MSG_COMBAT_XP_GAIN("CHAT_MSG_COMBAT_XP_GAIN", "Ihr bekommt 360 Erfahrung.")
	Equal("report: switched off, as before", rxp.mobXP, 405)
end

-- Other languages and the English client --------------------------------------
do
	local M, rxp = Load({ locale = "enUS" })
	local own = {
		names = rxp.GetCreatureName, guides = rxp.GetGuideTable, lists = rxp.GetActiveGuidesByGroupNameOrId,
		xp = rxp.tracker.CHAT_MSG_COMBAT_XP_GAIN,
	}
	M:SetupRXPLocale()
	Check("English: nothing wrapped", rxp.GetCreatureName == own.names and rxp.GetGuideTable == own.guides
		and rxp.GetActiveGuidesByGroupNameOrId == own.lists and rxp.tracker.CHAT_MSG_COMBAT_XP_GAIN == own.xp)
	Equal("English: texts as they are", world.texts["RestedXP Forever Guide (H)"], "RestedXP Forever Dungeonführer (H)")
	Equal("English: nothing read", #world.tickers, 0)
	Equal("English: no switch", M:RXPLocaleShown(), false)

	M, rxp = Load({ locale = "frFR" })
	M:SetupRXPLocale()
	Equal("French: the switch shows", M:RXPLocaleShown(), true)
	Tick(10)
	Equal("French: names from QuestieDB", rxp.GetCreatureName("Southsea Pirate"), "Pirat der Südmeerfreibeuter")
	Equal("French: no German guide data", rxp.GetGuideTable("RestedXP Forever Route (H)", "22-24 Hügellandhof"), nil)
	Equal("French: texts as they are", world.texts["RestedXP Forever Guide (H)"], "RestedXP Forever Dungeonführer (H)")
	Check("French: the status has only the names", not M:RXPLocaleStatus():find("group names", 1, true), M:RXPLocaleStatus())

	M, rxp = Load()
	world.loaded.RXPGuides = false
	M:SetupRXPLocale()
	Equal("no RestedXP: nothing", #world.tickers, 0)
	Equal("no RestedXP: no switch", M:RXPLocaleShown(), false)
end

print(("RestedXP language fit: %d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
