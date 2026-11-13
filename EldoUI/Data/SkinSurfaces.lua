-- Skin surfaces: every place of the UI a skin may draw on, and how.
--
-- One row per surface. E:SkinSurfaceReport([skin]) (Core/Skins.lua) reads
-- this list and says for each row what a skin draws there, so the list is
-- also the contract for plugins: E:RegisterSkinSurface(id, info) adds a
-- row for a plugin's own surface.
--
-- Fields:
--   family   action, unit, class, timers, progress, chat, world, windows
--   module   the module that owns the surface ("Core" for the shared kits)
--   kind     the surface kind a skin's recipes name (Data/Skins.lua recipes);
--            nil when the surface keeps its own look (see stock)
--   part     the skin part it draws in (E:SkinPart: a part's own pick wins,
--            the Components tab offers some of them); nil follows the skin
--   via      how the skin reaches it:
--              kit       the shared panel, box and bar painters (every
--                        window, panel, box and bar made with them)
--              surface   E:PaintSurface on the module's own frame
--              graphics  the unit-frame graphics of the skin
--              windows   the Blizzard windows choice (General > Skin > Windows)
--              flag      a skin flag the module reads (E:SkinFlag)
--   flag     with via = flag: the flag's name
--   compact  what small or dense copies draw:
--              thin      no corner ornaments below the corner size
--              keyline   the flat keyline only below the icon ring size
--              compact   the compact frame art (raid frames)
--   stock    why the surface keeps its own look in every skin ("Game-owned:"
--            when the game draws it and offers no way to retexture it)
--   original how the Vanilla Original skin uses the game's own art there
--            (E.skinOriginal in Data/SkinData.lua; E:OriginalSurfaceState
--            in Core/Media.lua says how its files draw on this client):
--              drawn     the client's own files, drawn by their path
--              mapped    the classic slots are listed; the surface wears the
--                        Vanilla material until it draws them
--              material  no single classic file: the Vanilla material and
--                        the classic control set
--              none      no 2004 original (E.skinOriginal.none or the stock
--                        reason says why)
local _, E = ...

E.skinSurfaceList = {
	-- Action bars
	{ id = "actionbuttons", family = "action", module = "ActionBars", kind = "button", part = "actionbuttons", via = "surface", original = "mapped" },
	{ id = "actionbar-background", family = "action", module = "ActionBars", kind = "panel", part = "actionbuttons", via = "surface", compact = "thin", original = "drawn" },
	{ id = "pet-stance-buttons", family = "action", module = "ActionBars", kind = "button", part = "actionbuttons", via = "surface", original = "mapped" },
	{ id = "vehicle-exit", family = "action", module = "ActionBars", kind = "box", via = "kit", original = "none" },
	{ id = "micromenu", family = "action", module = "MicroMenu", kind = "panel", via = "kit", compact = "thin", original = "drawn" },

	-- Unit frames, casts and auras
	{ id = "unitframes", family = "unit", module = "UnitFrames", kind = "unitframe", part = "unitGraphics", via = "graphics", original = "drawn" },
	{ id = "groupframes", family = "unit", module = "GroupFrames", kind = "groupframe", part = "groupGraphics", via = "graphics", compact = "compact", original = "none" },
	{ id = "castbars", family = "unit", module = "UnitFrames", kind = "castbar", via = "kit", original = "mapped" },
	{ id = "aura-icons", family = "unit", module = "Auras", kind = "icon", part = "auras", via = "surface", compact = "keyline", original = "material" },
	-- EldoUI's own plates follow the unit-frame graphics: the thin edge a
	-- small unit frame wears and the unit frames' well. Your own border
	-- colors (target, focus, style filters) still win over the edge.
	{ id = "nameplates", family = "unit", module = "Nameplates", kind = "unitframe", part = "unitGraphics", via = "graphics", original = "none" },
	{ id = "blizzard-nameplates", family = "unit", module = "Nameplates",
		stock = "Game-owned: plates Blizzard draws (the Blizzard plate style, widget-only units, friendly plates inside instances) keep the game's art; on the Blizzard plate style EldoUI only adds its bar texture, border and font.", original = "none" },

	-- Class resources and totems
	{ id = "classpower", family = "class", module = "ClassPower", kind = "bar", via = "kit", original = "material" },
	{ id = "totem-bar", family = "class", module = "ShamanTotems", kind = "box", via = "kit", original = "material" },

	-- Cooldowns, timers and alerts
	{ id = "cooldown-icons", family = "timers", module = "CooldownManager", kind = "icon", part = "cooldowns", via = "surface", compact = "keyline", original = "none" },
	{ id = "loss-of-control", family = "timers", module = "CombatHUD", kind = "icon", part = "cooldowns", via = "surface", compact = "keyline", original = "none" },
	{ id = "timer-bars", family = "timers", module = "CombatHUD", kind = "bar", via = "kit", original = "none" },
	{ id = "split-timer", family = "timers", module = "SplitTimer", kind = "panel", via = "kit", compact = "thin", original = "none" },
	{ id = "encounter-timeline", family = "timers", module = "EncounterTimeline", kind = "bar", via = "kit", original = "none" },
	{ id = "boss-addon-timers", family = "timers", module = "DBM",
		stock = "Bars of a loaded boss addon stay that addon's own; EldoUI never draws a second timer for them.", original = "none" },
	{ id = "alerts", family = "timers", module = "Notifications", kind = "panel", via = "kit", compact = "thin", original = "none" },
	{ id = "combat-text", family = "timers", module = "CombatText",
		stock = "Floating numbers are text only: they follow the font and its outline, not the skin.", original = "none" },

	-- Experience, reputation and breath
	{ id = "status-bars", family = "progress", module = "StatusBars", kind = "bar", via = "kit", original = "mapped" },

	-- Chat and tooltips
	{ id = "chat-panels", family = "chat", module = "Chat", kind = "chat", via = "kit", compact = "thin", original = "material" },
	{ id = "chat-tabs", family = "chat", module = "Chat", via = "flag", flag = "selectedTabTint", original = "material" },
	{ id = "tooltips", family = "chat", module = "Tooltip", kind = "tooltip", via = "kit", compact = "thin", original = "mapped" },

	-- Minimap, maps and world helpers
	{ id = "minimap", family = "world", module = "Minimap", kind = "minimap", part = "minimap", via = "surface", original = "drawn" },
	{ id = "minimap-buttons", family = "world", module = "Minimap", kind = "box", via = "kit", original = "mapped" },
	{ id = "infobar", family = "world", module = "InfoBar", kind = "panel", via = "kit", compact = "thin", original = "material" },
	{ id = "map-note-pins", family = "world", module = "MapNotes", via = "flag", flag = "pinShape", original = "material" },
	{ id = "zone-quest-pins", family = "world", module = "ZoneQuests", via = "flag", flag = "bronze", original = "material" },
	{ id = "quest-drop-icons", family = "world", module = "QuestDrops", via = "flag", flag = "bronze", original = "material" },
	{ id = "npc-dialog", family = "world", module = "Dialogue", kind = "window", via = "kit", original = "material" }, -- spelling: ok (module name)
	{ id = "party-quests", family = "world", module = "PartyQuests", kind = "panel", via = "kit", compact = "thin", original = "material" },
	{ id = "world-markers", family = "world", module = "Core",
		stock = "Game-owned: raid target markers, on the ground and over units, are the game's own art and the game offers no way to retexture them, so they look the same in every skin.", original = "none" },

	-- Windows
	{ id = "windows", family = "windows", module = "Core", kind = "window", via = "kit", original = "mapped" },
	{ id = "options-window", family = "windows", module = "Core", kind = "window", part = "config", via = "kit", original = "material" },
	{ id = "boxes", family = "windows", module = "Core", kind = "box", via = "kit", original = "material" },
	{ id = "blizzard-windows", family = "windows", module = "Core", kind = "window", via = "windows", original = "material" },
}
