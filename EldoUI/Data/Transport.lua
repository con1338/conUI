-- EldoUI transport data: boats, zeppelins, the tram and fixed
-- portals, for the Transport Maps module (Modules/Transport/Core.lua).
-- Flight masters are not listed here: they come from the game
-- (C_TaxiMap.GetTaxiNodesForMap).
--
-- Hand-entered by us (Apache-2.0) from public knowledge of the world and
-- of WoW: Forever's own routes. Coordinates are approximate: the docks of
-- Forever's new routes come from the Eldostar guide steps or, for the
-- Southshore and Feathermoon docks, from the client's transport anchors
-- (TaxiNodes and UiMapAssignment, build 1.60.1.70862). Every entry carries
-- `checked`, and an entry with checked = false has not been checked in
-- the WoW: Forever client yet. Its pin says so in the tooltip.
--
-- Each route:
--   kind      "boat" | "zeppelin" | "tram" | "portal" (an airship counts
--             as a zeppelin)
--   faction   "Alliance" | "Horde" | nil (anyone may use it)
--   stops     two ends { map = uiMapID, x, y (0-1 on that map), name }
--   oneWay    true when it only goes from the first stop to the second (a
--             loop is one one-way route per leg)
--   checked   true once the stop positions were checked in game
local _, E = ...

E.transportData = {
	version = 2,
	routes = {
		-- Boats
		{ kind = "boat", faction = "Alliance", checked = false, stops = {
			{ map = 1453, x = 0.227, y = 0.567, name = "Stormwind Harbor" },
			{ map = 1439, x = 0.308, y = 0.409, name = "Auberdine" } } },
		-- The Menethil ship runs a loop: Menethil Harbor, Southshore,
		-- Auberdine, and back to Menethil Harbor.
		{ kind = "boat", faction = "Alliance", oneWay = true, checked = false, stops = {
			{ map = 1437, x = 0.048, y = 0.570, name = "Menethil Harbor" },
			{ map = 1424, x = 0.505, y = 0.650, name = "Southshore" } } },
		{ kind = "boat", faction = "Alliance", oneWay = true, checked = false, stops = {
			{ map = 1424, x = 0.505, y = 0.650, name = "Southshore" },
			{ map = 1439, x = 0.324, y = 0.438, name = "Auberdine" } } },
		{ kind = "boat", faction = "Alliance", oneWay = true, checked = false, stops = {
			{ map = 1439, x = 0.324, y = 0.438, name = "Auberdine" },
			{ map = 1437, x = 0.048, y = 0.570, name = "Menethil Harbor" } } },
		{ kind = "boat", faction = "Alliance", checked = false, stops = {
			{ map = 1437, x = 0.050, y = 0.634, name = "Menethil Harbor" },
			{ map = 1445, x = 0.716, y = 0.564, name = "Theramore Isle" } } },
		{ kind = "boat", faction = "Alliance", checked = false, stops = {
			{ map = 1439, x = 0.332, y = 0.402, name = "Auberdine" },
			{ map = 1438, x = 0.549, y = 0.968, name = "Rut'theran Village" } } },
		{ kind = "boat", checked = false, stops = {
			{ map = 1434, x = 0.259, y = 0.731, name = "Booty Bay" },
			{ map = 1413, x = 0.637, y = 0.386, name = "Ratchet" } } },
		{ kind = "boat", faction = "Alliance", checked = false, stops = {
			{ map = 1444, x = 0.434, y = 0.427, name = "The Forgotten Coast" },
			{ map = 1444, x = 0.311, y = 0.397, name = "Feathermoon Stronghold" } } },
		{ kind = "boat", checked = false, stops = {
			{ map = 1446, x = 0.669, y = 0.213, name = "Steamwheedle Port" },
			{ map = 2548, x = 0.765, y = 0.518, name = "Powderfuse Port" } } },
		-- Zeppelins
		{ kind = "zeppelin", faction = "Horde", checked = false, stops = {
			{ map = 1411, x = 0.508, y = 0.138, name = "Orgrimmar zeppelin tower" },
			{ map = 1420, x = 0.607, y = 0.588, name = "Undercity zeppelin tower" } } },
		{ kind = "zeppelin", faction = "Horde", checked = false, stops = {
			{ map = 1411, x = 0.506, y = 0.126, name = "Orgrimmar zeppelin tower" },
			{ map = 1434, x = 0.314, y = 0.302, name = "Grom'gol Base Camp" } } },
		{ kind = "zeppelin", faction = "Horde", checked = false, stops = {
			{ map = 1420, x = 0.619, y = 0.591, name = "Undercity zeppelin tower" },
			{ map = 1434, x = 0.316, y = 0.291, name = "Grom'gol Base Camp" } } },
		-- Zephras Isle's skyboats: the Alliance skycutter to the Skyborne
		-- landing west of Dalaran, the Horde airship to northern Mulgore.
		{ kind = "zeppelin", faction = "Alliance", checked = false, stops = {
			{ map = 2521, x = 0.658, y = 0.834, name = "Valanaar Skydocks" },
			{ map = 1416, x = 0.125, y = 0.518, name = "Skyborne landing, Dalaran" } } },
		{ kind = "zeppelin", faction = "Horde", checked = false, stops = {
			{ map = 2521, x = 0.579, y = 0.808, name = "Valanaar Skydocks" },
			{ map = 1412, x = 0.343, y = 0.258, name = "Skywatcher Plateau" } } },
		-- Tram: both ends are where the client's tram entrances sit (its
		-- area table, build 1.60.1.70862), placed on each city map by the
		-- map's own world bounds.
		{ kind = "tram", checked = false, stops = {
			{ map = 1453, x = 0.696, y = 0.303, name = "Deeprun Tram (Stormwind)" },
			{ map = 1455, x = 0.780, y = 0.514, name = "Deeprun Tram (Ironforge)" } } },
		-- Portals
		{ kind = "portal", faction = "Alliance", checked = false, stops = {
			{ map = 1438, x = 0.559, y = 0.896, name = "Rut'theran Village" },
			{ map = 1457, x = 0.401, y = 0.832, name = "Darnassus" } } },
	},
}

-- Mage teleports and portals for the Mage Travel button
-- (Modules/Transport/MageTravel.lua): the trainer spells of
-- Data/Training/Mage.lua, in the order the list shows them. Names and icons
-- come from the game. Each kind uses its rune (Rune of Teleportation,
-- Rune of Portals).
E.mageTravel = {
	runes = { teleport = 17031, portal = 17032 },
	spells = {
		{ kind = "teleport", id = 3561, faction = "Alliance" },  -- Stormwind
		{ kind = "teleport", id = 3562, faction = "Alliance" },  -- Ironforge
		{ kind = "teleport", id = 3565, faction = "Alliance" },  -- Darnassus
		{ kind = "teleport", id = 3567, faction = "Horde" },     -- Orgrimmar
		{ kind = "teleport", id = 3563, faction = "Horde" },     -- Undercity
		{ kind = "teleport", id = 3566, faction = "Horde" },     -- Thunder Bluff
		{ kind = "teleport", id = 1297659 },                     -- Dalaran (both sides, level 50)
		{ kind = "portal", id = 10059, faction = "Alliance" },   -- Stormwind
		{ kind = "portal", id = 11416, faction = "Alliance" },   -- Ironforge
		{ kind = "portal", id = 11419, faction = "Alliance" },   -- Darnassus
		{ kind = "portal", id = 11417, faction = "Horde" },      -- Orgrimmar
		{ kind = "portal", id = 11418, faction = "Horde" },      -- Undercity
		{ kind = "portal", id = 11420, faction = "Horde" },      -- Thunder Bluff
	},
}
