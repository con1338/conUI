-- EldoUI shipped addon profiles: export strings made in game with
-- /eui capture <addon>, copied here from EldoUIDB.captures.
-- Layout: E.profileStrings[setupName][key] = "export string"
--   Details:         key "<LayoutKey>" (EldoModern, EldoClassic, ...) for one
--                    layout, or "default" for every layout without its own
--   CooldownManager: key "<CLASS>-<specID>", e.g. "SHAMAN-264"
-- Only strings made from the player's own settings belong here.
--
-- E.profileVersions[setupName]: raise it whenever a shipped string (or a
-- profile EldoUI builds itself, BigWigs and DBM) changes. Players who
-- imported an older version are asked once whether to update.
local _, E = ...

E.profileStrings = {
	Details = {},
	CooldownManager = {},
}

E.profileVersions = {
	Details = 1,
	CooldownManager = 1,
	BigWigs = 1,
	DBM = 1,
}
