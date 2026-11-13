-- luacheck settings for the addon folders (EldoUI and EldoUI_*).
--   luacheck EldoUI EldoUI_*        (from the repository root; tools/ci/check_all.sh runs it)
--
-- The check looks at globals only: a global EldoUI writes that isn't listed
-- below, or a name it reads that isn't in tools/ci/globals.lua (the WoW API
-- names the code used when the list was made). That catches a missing
-- "local" and a typo in an API name. Style warnings (unused variables,
-- shadowing, whitespace) stay off: the upstream code isn't written for them.
--
-- New WoW API name used on purpose? Run  python3 tools/ci/globals.py --update
-- and commit tools/ci/globals.lua with the change.
std = "lua51"
max_line_length = false
ignore = { "2", "3", "4", "5", "6" }

-- Globals EldoUI writes on purpose.
globals = {
	"EldoUI",                                     -- Core/Init.lua: the addon table for plugins
	"EldoUIDB", "EldoUIErrorsDB", "EldoUIMessagesDB", -- SavedVariables
	"EldoUI_GuideData", "EldoUI_LootData",        -- companion data addons
	"SLASH_ELDOUI1", "SLASH_ELDOUI2",
	"EldoUI_OnAddonCompartmentClick", "EldoUI_OnAddonCompartmentEnter", "EldoUI_OnAddonCompartmentLeave",
	"SlashCmdList", "StaticPopupDialogs",         -- Blizzard tables EldoUI adds entries to
}

-- WoW API and Blizzard names the code reads.
read_globals = dofile("tools/ci/globals.lua")

-- The offline tests and helper scripts under tools/ stub WoW globals;
-- tools/groupboard has its own, stricter settings.
exclude_files = { "tools/**" }
