-- EldoUI dungeon map list for E.DungeonMaps (Core/DungeonMaps.lua).
--
-- Written by us (Apache-2.0). It names, per Classic dungeon and raid, the
-- game map the instance runs on (GetInstanceInfo's instanceID) and the
-- folder names the client's own dungeon map art may sit under
-- (Interface\WorldMap\<folder>\<folder><floor>_<1-12>). The art itself is
-- never shipped; Core/DungeonMaps.lua asks the client which of these files
-- exist (GetFileIDFromPath) and how many floors they have. Floor edges in
-- world yards are in Data/DungeonFloorEdges.lua (generated from the client
-- tables of a later Classic build, kept only where they fit Forever's art
-- and creatures); else they come from the client's map API when it knows
-- the floor, from a plugin (E.DungeonMaps:Register), or are worked out from
-- where the creatures stand (a "layout", marked as approximate).
--
-- key: the EldoUI_LootData instance key where there is one, so the Loot
-- Guide and other modules share one name. wings: other keys that use the
-- same map (Scarlet Monastery, Dire Maul, Blackrock Spire, Stratholme).
local _, E = ...

E.DungeonFloorData = {
	ragefire = { map = 389, art = { "Ragefire", "RagefireChasm" } },
	wailing = { map = 43, art = { "WailingCaverns" } },
	deadmines = { map = 36, art = { "TheDeadmines", "Deadmines" } },
	shadowfang = { map = 33, art = { "ShadowfangKeep" } },
	blackfathom = { map = 48, art = { "BlackFathomDeeps", "BlackfathomDeeps" } },
	stockade = { map = 34, art = { "TheStockade", "Stormwindstockade" } },
	gnomeregan = { map = 90, art = { "Gnomeregan" } },
	kraul = { map = 47, art = { "RazorfenKraul" } },
	scarlet = { map = 189, art = { "ScarletMonasteryOld", "ScarletMonastery" }, wings = { "sm_gy", "sm_lib", "sm_arm", "sm_cath" } },
	downs = { map = 129, art = { "RazorfenDowns" } },
	uldaman = { map = 70, art = { "Uldaman" } },
	zulfarrak = { map = 209, art = { "ZulFarrak", "Zulfarrak" } },
	maraudon = { map = 349, art = { "Maraudon" } },
	sunken = { map = 109, art = { "TheTempleOfAtalHakkar", "TheTempleofAtalHakkar", "SunkenTemple" } },
	brd = { map = 230, art = { "BlackrockDepths" } },
	blackrockspire = { map = 229, art = { "BlackrockSpire" }, wings = { "lbrs", "ubrs" } },
	diremaul = { map = 429, art = { "DireMaul" }, wings = { "dm_east", "dm_west", "dm_north" } },
	scholomance = { map = 289, art = { "ScholomanceOld", "Scholomance" } },
	stratholme = { map = 329, art = { "Stratholme" }, wings = { "strat_live", "strat_ud" } },
	mc = { map = 409, art = { "MoltenCore" } },
	onyxia = { map = 249, art = { "OnyxiasLair" } },
	bwl = { map = 469, art = { "BlackwingLair" } },
	zg = { map = 309, art = { "ZulGurub", "ZulGurubOld" } },
	aq20 = { map = 509, art = { "RuinsofAhnQiraj", "RuinsOfAhnQiraj" } },
	aq40 = { map = 531, art = { "TempleofAhnQiraj", "AhnQiraj", "TempleOfAhnQiraj" } },
	naxx = { map = 533, art = { "Naxxramas" } },
}
