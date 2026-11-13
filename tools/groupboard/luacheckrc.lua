-- luacheck settings for EldoUI_GroupBoard:
--   luacheck --config tools/groupboard/luacheckrc.lua EldoUI_GroupBoard
std = "lua51"
max_line_length = false
-- The WoW API and EldoUI names the plugin reads; it writes no globals.
read_globals = {
	"EldoUI", "CreateFrame", "GetTime", "C_Timer", "C_PartyInfo", "InCombatLockdown", "UnitLevel",
	"GetPlayerInfoByGUID", "Ambiguate", "GameTooltip", "wipe", "GetLFDChoiceOrder", "GetLFGDungeonInfo",
	"CLASS_ICON_TCOORDS", "ChatFrameUtil", "ChatFrame_SendTell", "InviteUnit",
}
-- Methods keep the colon form even when they don't use self.
ignore = { "212/self" }
-- The offline tests set the WoW globals they stub.
files["tools/groupboard/*.lua"] = { globals = { "EldoUI", "strtrim", "GetLocale", "wipe", "GetTime", "C_Timer",
	"C_PartyInfo", "InCombatLockdown", "UnitLevel", "GetPlayerInfoByGUID", "Ambiguate", "GameTooltip", "GetLFDChoiceOrder",
	"GetLFGDungeonInfo", "CLASS_ICON_TCOORDS", "ChatFrameUtil", "issecretvalue" } }
