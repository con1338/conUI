-- EldoUI movable windows: every Blizzard window the window mover
-- (Core/WindowMover.lua) can drag, scale and reset on WoW: Forever.
--
-- Written for EldoUI from Blizzard's own UI source (wow-ui-source, branch
-- forever, 1.60.1) and the behavior notes in the project research. No list
-- or code from another addon. Frame names are Blizzard's own globals.
--
-- One entry per window:
--   key       save key (positions and scale live under it in the profile)
--   frame     Blizzard global, or a dotted path ("Parent.Child")
--   addon     load-on-demand Blizzard addon to wait for (nil = always there)
--   element   the Blizzard UI switch (Core/Blizzard.lua) whose "Move and
--             scale" rules this window; each element is opt-in
--   title     name in the options list
--   drag      the title strip EldoUI lays over the window:
--               nil       TitleContainer, else the dialog Header, else the top edge
--               "Header"  the dialog header
--               { left, right, top, height, width, level, parent }  offsets
--                         on the window (or on its parentKey `parent`)
--   handles   sub-frames that also drag the window ("anywhere" drag mode)
--   children  panels that Alt+drag detaches from the window
--   pin       Blizzard re-anchors this window on its own: keep it in place
--             with a guarded SetPoint post-hook
--   maximized the window can go full screen: leave it alone while it is
--   noAlpha   never fade it (it has its own fade)
--   protected Blizzard's window has secure parts: it moves out of combat only
--             (only for the option text; the check is made in the game)
--   unsure    may not exist on every Forever build
-- Missing frames are skipped without a message.
local _, E = ...

E.movableWindowData = {
	-- Character and progression
	{ key = "character", frame = "CharacterFrame", element = "character-frame", title = "Character",
		handles = { "PaperDollFrame", "ReputationFrame", "TokenFrame" },
		children = { "ReputationFrame.ReputationDetailFrame", "CurrencyTransferLog" } },
	{ key = "currencyTransfer", frame = "CurrencyTransferMenu", element = "character-frame", title = "Currency transfer" },
	{ key = "inspect", frame = "InspectFrame", addon = "Blizzard_InspectUI", element = "inspect-frame", title = "Inspect",
		handles = { "InspectPaperDollFrame" } },
	{ key = "dressup", frame = "DressUpFrame", element = "dressing-room", title = "Dressing room",
		children = { "DressUpFrame.CustomSetDetailsPanel" } },
	{ key = "modelPreview", frame = "ModelPreviewFrame", element = "dressing-room", title = "Item preview" },
	{ key = "spells", frame = "PlayerSpellsFrame", addon = "Blizzard_PlayerSpells", element = "player-spells", title = "Spellbook and talents",
		protected = true },
	{ key = "professions", frame = "ProfessionsFrame", addon = "Blizzard_Professions", element = "professions", title = "Professions" },
	{ key = "inspectRecipe", frame = "InspectRecipeFrame", addon = "Blizzard_Professions", element = "professions", title = "Linked recipe" },
	{ key = "professionsBook", frame = "ProfessionsBookFrame", addon = "Blizzard_ProfessionsBook", element = "professions", title = "Professions book",
		protected = true },
	{ key = "customerOrders", frame = "ProfessionsCustomerOrdersFrame", addon = "Blizzard_ProfessionsCustomerOrders", element = "professions",
		title = "Crafting orders", unsure = true },
	{ key = "trainer", frame = "ClassTrainerFrame", addon = "Blizzard_TrainerUI", element = "class-trainer", title = "Trainer" },
	{ key = "legacy", frame = "LegacySystemFrame", addon = "Blizzard_LegacySystem", element = "legacy-achievements", title = "Legacy" },
	{ key = "achievements", frame = "AchievementFrame", addon = "Blizzard_AchievementUI", element = "legacy-achievements", title = "Achievements",
		drag = "Header" },
	{ key = "statistics", frame = "StatisticsFrame", addon = "Blizzard_Statistics", element = "legacy-achievements", title = "Statistics" },
	{ key = "collections", frame = "CollectionsJournal", addon = "Blizzard_Collections", element = "collections", title = "Collections",
		protected = true },
	{ key = "transmog", frame = "TransmogFrame", addon = "Blizzard_Transmog", element = "collections", title = "Transmogrify", unsure = true },
	{ key = "socketing", frame = "ItemSocketingFrame", addon = "Blizzard_ItemSocketingUI", element = "item-socketing", title = "Item socketing" },
	{ key = "interaction", frame = "ItemInteractionFrame", addon = "Blizzard_ItemInteractionUI", element = "item-socketing", title = "Item interaction" },
	{ key = "itemUpgrade", frame = "ItemUpgradeFrame", addon = "Blizzard_ItemUpgradeUI", element = "item-socketing", title = "Item upgrade",
		unsure = true },

	-- Social and group
	{ key = "friends", frame = "FriendsFrame", element = "friends-frame", title = "Friends",
		children = { "FriendsFrameBattlenetFrame.BroadcastFrame", "RaidInfoFrame" } },
	-- The social window, which holds the friends list when the client turns
	-- it on (C_SocialUI); otherwise it never shows.
	{ key = "social", frame = "SocialUIFrame", element = "friends-frame", title = "Social window", unsure = true },
	{ key = "channels", frame = "ChannelFrame", element = "friends-frame", title = "Chat channels" },
	{ key = "guild", frame = "CommunitiesFrame", element = "communities-guild", title = "Guild and communities",
		drag = { left = 60, right = 56 },
		children = { "CommunitiesFrame.GuildMemberDetailFrame" } },
	{ key = "guildLog", frame = "CommunitiesGuildLogFrame", element = "communities-guild", title = "Guild log" },
	{ key = "guildNewsFilters", frame = "CommunitiesGuildNewsFiltersFrame", element = "communities-guild", title = "Guild news filters" },
	{ key = "guildText", frame = "CommunitiesGuildTextEditFrame", element = "communities-guild", title = "Guild info editor" },
	{ key = "communitySettings", frame = "CommunitiesSettingsDialog", element = "communities-guild", title = "Community settings" },
	{ key = "guildRecruitment", frame = "CommunitiesFrame.RecruitmentDialog", element = "communities-guild", title = "Guild recruitment" },
	{ key = "guildRequest", frame = "ClubFinderGuildFinderFrame.RequestToJoinFrame", element = "communities-guild", title = "Request to join" },
	{ key = "guildControl", frame = "GuildControlUI", addon = "Blizzard_GuildControlUI", element = "communities-guild", title = "Guild control" },
	{ key = "guildRename", frame = "GuildRenameFrame", element = "communities-guild", title = "Guild rename", unsure = true },
	{ key = "guildInvite", frame = "GuildInviteFrame", element = "communities-guild", title = "Guild invitation" },
	{ key = "calendar", frame = "CalendarFrame", addon = "Blizzard_Calendar", element = "calendar", title = "Calendar",
		drag = { left = 12, top = -4, width = 220, height = 28 },
		children = { "CalendarCreateEventFrame", "CalendarViewEventFrame", "CalendarViewHolidayFrame", "CalendarViewRaidFrame" } },
	{ key = "lfg", frame = "LFGParentFrame", addon = "Blizzard_GroupFinder_VanillaStyle", element = "group-finder", title = "Group finder",
		drag = { left = 60, right = 28, level = 20 }, protected = true,
		handles = { "LFGBrowseFrame", "LFGListingFrame", "LFGWhoListFrame" } },
	{ key = "scoreboard", frame = "PVPMatchScoreboard", element = "pvp-match", title = "PvP scoreboard",
		drag = { left = 30, right = 44, height = 26 } },
	{ key = "results", frame = "PVPMatchResults", element = "pvp-match", title = "PvP results",
		drag = { left = 30, right = 44, height = 26 } },
	{ key = "readyCheck", frame = "ReadyCheckFrame", element = "ready-check-popups", title = "Ready check" },
	{ key = "rolePoll", frame = "RolePollPopup", element = "ready-check-popups", title = "Role check" },
	{ key = "lootHistory", frame = "GroupLootHistoryFrame", element = "group-loot-rolls", title = "Loot history", unsure = true },

	-- Maps
	{ key = "worldMap", frame = "WorldMapFrame", element = "world-map-quest-log", title = "World map and quest log",
		drag = { parent = "BorderFrame", left = 60, right = 64 }, pin = true, maximized = true, noAlpha = true },
	{ key = "questDetail", frame = "QuestLogPopupDetailFrame", element = "world-map-quest-log", title = "Quest details" },
	{ key = "taxi", frame = "TaxiFrame", element = "flight-map", title = "Taxi map", pin = true },
	{ key = "flightMap", frame = "FlightMapFrame", addon = "Blizzard_FlightMap", element = "flight-map", title = "Flight map",
		drag = { parent = "BorderFrame", left = 60, right = 64 }, pin = true },
	{ key = "timeManager", frame = "TimeManagerFrame", addon = "Blizzard_TimeManager", element = "minimap-buttons", title = "Clock and alarm" },

	-- Items, NPCs and economy
	{ key = "quest", frame = "QuestFrame", element = "quest-gossip-npc", title = "Quest" },
	{ key = "gossip", frame = "GossipFrame", element = "quest-gossip-npc", title = "Gossip" },
	{ key = "itemText", frame = "ItemTextFrame", element = "quest-gossip-npc", title = "Books and letters" },
	{ key = "tabard", frame = "TabardFrame", element = "quest-gossip-npc", title = "Tabard designer" },
	{ key = "guildRegistrar", frame = "GuildRegistrarFrame", element = "quest-gossip-npc", title = "Guild registrar" },
	{ key = "petition", frame = "PetitionFrame", element = "quest-gossip-npc", title = "Charter" },
	{ key = "playerChoice", frame = "PlayerChoiceFrame", addon = "Blizzard_PlayerChoice", element = "quest-gossip-npc", title = "Player choice" },
	{ key = "stable", frame = "PetStableFrame", addon = "Blizzard_StableUI", element = "pet-stable", title = "Pet stable" },
	{ key = "openMail", frame = "OpenMailFrame", element = "mail", title = "Open letter" },
	-- The economy windows open on their EldoUI mover (/eui move, layouts)
	-- until the player drags them (Core/EconomyWindows.lua).
	{ key = "merchant", frame = "MerchantFrame", element = "merchant", title = "Merchant" },
	{ key = "mail", frame = "MailFrame", element = "mail", title = "Mailbox" },
	{ key = "trade", frame = "TradeFrame", element = "trade", title = "Trade" },
	{ key = "auctionHouse", frame = "AuctionHouseFrame", addon = "Blizzard_AuctionHouseUI", element = "auction-house", title = "Auction house" },

	-- System and settings
	{ key = "gameMenu", frame = "GameMenuFrame", element = "game-menu", title = "Game menu", drag = "Header" },
	{ key = "settings", frame = "SettingsPanel", element = "settings-panel", title = "Settings" },
	{ key = "addonList", frame = "AddonList", element = "addon-list", title = "AddOn list" },
	{ key = "macro", frame = "MacroFrame", addon = "Blizzard_MacroUI", element = "macros-click-binding", title = "Macros",
		children = { "MacroPopupFrame" } },
	{ key = "clickBinding", frame = "ClickBindingFrame", addon = "Blizzard_ClickBindingUI", element = "macros-click-binding", title = "Click casting" },
	{ key = "chatConfig", frame = "ChatConfigFrame", element = "chat-frames", title = "Chat settings", drag = "Header" },
	{ key = "cooldownSettings", frame = "CooldownViewerSettings", element = "cooldown-viewer", title = "Cooldown Manager settings" },
	{ key = "deathRecap", frame = "DeathRecapFrame", addon = "Blizzard_DeathRecap", element = "death-recap-ghost", title = "Death recap" },
}
