-- Battleground Timers: EldoUI's own facts per battleground on WoW: Forever.
--
-- Battlegrounds are found by instance ID (GetInstanceInfo, 8th return),
-- never by name, so every client language works. uiMapID is the map the
-- POIs live on (C_Map.GetBestMapForUnit gives it in game; this is the
-- fallback). Instance and map IDs checked 2026-10-11.
--
-- Durations come from public battleground guides and still need a check
-- on Forever itself:
--   assault      seconds from an assault to the base flipping, used only
--                when the game does not report a POI time itself
--                (C_AreaPoiInfo.IsAreaPOITimed). An assault EldoUI sees
--                from start to flip, or one the game times, replaces it
--                with the time measured on this client (Captures.lua).
--   flagRespawn  seconds from a flag capture to the flags returning
--   timeLimit    match length in seconds, when the game has one
-- A nil duration means "unknown": the bar that needs it does not show
-- rather than show a guess.
--
-- assaultStates / settledStates: POI textureIndex values seen in game for
-- a base being taken or held, per side (filled from /eui probe bg; empty
-- until then, the capture engine then works from the icon name, POI
-- changes and timing).
-- resources: areaPoiIDs of mines and other resource nodes (owner chips);
-- resourceAtlas: a word in the game's icon name that marks one, so mines
-- are found without an ID list.
-- turnIns: AV hand-in items (item ID -> who takes them); the reminder only
-- counts them, it never hands anything in.
local _, E = ...
local L = E.L
local Key = E.Key
local M = E:GetModule("Battlegrounds")

M.MAPS = {
	-- Warsong Gulch: capture the flag, 3 captures (10+).
	[489] = {
		key = "wsg", uiMapID = 1460, name = Key("Warsong Gulch"),
		-- Both flags come back 12 seconds after a capture on this client.
		-- Older guides give 20 seconds; the bar is checked against a
		-- capture timed in game.
		flags = true, flagRespawn = 12,
		-- Retail stops the match after 20 minutes; Classic has no limit.
		-- Forever's limit is unknown, so the time left comes from the
		-- game's own clock widget when the match shows one.
		timeLimit = nil,
		scoreMax = 3,
	},
	-- Arathi Basin: five bases, first to the resource limit (20+).
	[529] = {
		key = "ab", uiMapID = 1461, name = Key("Arathi Basin"),
		-- An assaulted base turns after 60 seconds (Icy Veins Classic
		-- guide); needs an in-game check.
		assault = 60,
		predict = true,
		assaultStates = {}, settledStates = {},
	},
	-- Darkspear Islands: four capture points and a center flag, first to
	-- 2000 (30+). Flag captures make the score jump.
	[2997] = {
		key = "darkspear", uiMapID = 2524, name = Key("Darkspear Islands"),
		-- No public time yet: capture bars use the game's own POI time,
		-- or the time EldoUI measures on the first assault it sees.
		assault = nil,
		predict = true,
		assaultStates = {}, settledStates = {},
	},
	-- Alterac Valley: towers, graveyards, two mines (51+).
	[30] = {
		key = "av", uiMapID = 1459, name = Key("Alterac Valley"),
		-- A tower burns or a graveyard turns 4 minutes after the assault
		-- (Warcraft Wiki and Wowhead Classic guide); needs an in-game check.
		assault = 240,
		assaultStates = {}, settledStates = {},
		resources = {},                 -- mine areaPoiIDs, from /eui probe bg
		resourceAtlas = "mine",         -- or any POI whose icon name says mine
		turnIns = {
			-- itemID = role (Classic item IDs, as listed by Wowhead Classic;
			-- re-check in Forever's AV)
			[17422] = "blacksmith",       -- Armor Scraps
			[17522] = "quartermaster",    -- Irondeep Supplies
			[17542] = "quartermaster",    -- Coldtooth Supplies
			[17423] = "druid",            -- Storm Crystal
			[17306] = "druid",            -- Stormpike Soldier's Blood
			[17642] = "stables",          -- Alterac Ram Hide
			[17643] = "stables",          -- Frostwolf Hide
			[17326] = "commander",        -- Stormpike Soldier's Flesh
			[17327] = "commander",        -- Stormpike Lieutenant's Flesh
			[17328] = "commander",        -- Stormpike Commander's Flesh
			[17502] = "commander",        -- Frostwolf Soldier's Medal
			[17503] = "commander",        -- Frostwolf Lieutenant's Medal
			[17504] = "commander",        -- Frostwolf Commander's Medal
		},
	},
}

-- Who takes the AV turn-ins, for the reminder chip.
M.TURN_IN_ROLES = E:TranslateValues({
	blacksmith = E.Key("Blacksmith"),
	quartermaster = E.Key("Quartermaster"),
	druid = E.Key("Druid or Primalist"),
	stables = E.Key("Rider Commander"),
	commander = E.Key("Wing Commander"),
})

-- The facts for an instance ID (a copy with instanceID set). An unknown
-- battleground still gets the generic engines (game POI times, widgets).
function M:MapInfo(instanceID)
	local info = {}
	local known = instanceID and self.MAPS[instanceID]
	for key, value in pairs(known or {}) do info[key] = value end
	-- Names are kept in English and given in the language shown.
	info.name = E:Translate(info.name)
	info.instanceID = instanceID or 0
	info.known = known ~= nil
	if not info.name then
		local zone = GetRealZoneText()
		info.name = (type(zone) == "string" and not M.IsSecret(zone)) and zone or L["Battleground"]
	end
	return info
end
