-- Default changes between saved data versions.
--
-- EldoUI saves only the settings that differ from their defaults, so a
-- default that changes in an update would silently change the setting of
-- every player who had the old value. Each changed default gets one row
-- here instead:
--
--   { schema = 2, path = "modules.Minimap.size", from = 140, to = 160, keep = true },
--
--   schema  the profile version (E.PROFILE_SCHEMA) that ships the change
--   path    where the setting sits in a profile, dot separated
--   from    the old default
--   to      the new default
--   keep    true: profiles from before the change that hold no value of
--           their own get `from` written in, so the player keeps what they
--           saw (the new default is one "Reset to default" away);
--           false: a correction every player gets, named in the release notes
--
-- A release whose defaults changed without a row here is refused by the
-- release checks.
local _, E = ...

E.defaultChanges = {
	-- EldoUI Center is the default layout for new profiles; a profile from
	-- before keeps the layout it used.
	{ schema = 1, path = "general.layout", from = "EldoModern", to = "EldoCenter", keep = true },
	-- The offer to upgrade spell ranks is on for every player: it only
	-- asks, and nothing moves until the player applies the preview.
	{ schema = 2, path = "modules.ActionBars.ranks.offer", from = false, to = true, keep = false },
	-- The second info bar on its own mover takes the free stretch of the
	-- top edge instead of the full width, where it covered the minimap, the
	-- buffs, the farming bar and the mirror timers. A width the player set
	-- stays theirs.
	{ schema = 3, path = "modules.InfoBar.bar2.width", from = 0, to = 390, keep = false },
	-- The addon button bin is on in every layout: a click drawer that
	-- opens toward the middle of the screen keeps the minimap tidy. A
	-- profile from before keeps how it gathered the buttons.
	{ schema = 3, path = "modules.Minimap.binMode", from = "off", to = "drawer", keep = true },
	{ schema = 3, path = "modules.Minimap.binSide", from = "BOTTOM", to = "AUTO", keep = true },
	-- Existing profiles keep their selected placement when a family gains a new version.
	{ schema = 4, path = "general.layout", from = "EldoCenter", to = "EldoCenter1000", keep = true },
	-- A new whisper opens its window (out of combat; after the fight when it
	-- arrives in combat), so it is no longer missed in the dock.
	{ schema = 5, path = "modules.Messages.openOnReceive", from = "dock", to = "window", keep = false },
}
