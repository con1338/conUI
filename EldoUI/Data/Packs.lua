-- EldoUI preset packs: a whole UI in one click, one pack per kind of
-- player. A pack names a layout, a skin and accent, a style per part of
-- the UI, a role, the Blizzard UI mode, the Blizzard windows look and the
-- chat setup. The setup's
-- Welcome step shows them as cards; "Apply" runs every step with the
-- pack's picks (the same steps and undo as walking through them), and
-- "Customize" opens the steps with the picks filled in.
--
--   {
--       key, title, desc,
--       layout   = "<layout key>",        -- nil: EldoUI's suggestion for the screen
--       artStyle = "<skin key>",          -- nil: the layout's own skin
--       skinVariant = "alliance" | "horde" | "neutral",  -- nil: your faction
--       graphics = "<unit-frame graphics>",  -- nil: follow the skin
--       accent   = "RRGGBB" or "class",   -- nil: the skin's, else the layout's
--       styles   = { UnitFrames = "<style key>", ... },  -- on top of the layout's suggestions
--       role     = "melee" | "ranged" | "healer" | "tank",  -- nil: detected from the talents
--       blizzard = "recommended",         -- a mode of the Blizzard UI step, nil: keep
--       blizzardWindows = "layout" | "original" | "match",  -- nil: keep
--       chat     = "tabs",                -- "tabs" or nil (keep)
--       modules  = { ModuleName = true },  -- modules the pack turns on (nil: keep)
--       uiAmount = "essential" | "moderate" | "full",  -- UI amount (Data/UIAmounts.lua), nil: keep
--       keymap   = { preset = "<key set>" | "none", newSpells, alts, showKeys },
--                  -- the setup's Keys and spells picks (Core/KeymapSync.lua);
--                  -- nil: the recommended key set, and keys shown on bars
--                  -- 1 to 3 when the pack's style hides them
--   }
-- Structured, Focus and Portrait Forge are complete looks: one layout, one
-- skin and one UI amount each. The Overview page and the setup apply them
-- the same way as every other pack.
-- Packs only use layouts, styles and modes that exist (a pack whose layout
-- is missing is left out, Core/Packs.lua); the layout and style checks keep
-- every shipped pack free of overlapping frames.
local _, E = ...

E.packs = E.packs or {}
E.packOrder = E.packOrder or {}

local function Add(pack)
	E.packs[pack.key] = pack
	table.insert(E.packOrder, pack.key)
end

-- EldoUI's own look: the recommended layout for the screen, its skin and
-- the layout's suggested styles, with keybinds and macro names on the
-- action buttons.
Add({
	key = "Modern", title = "Modern",
	desc = "EldoUI's own look: the layout picked for your screen, clean unit frames and the layout's own skin.",
	blizzard = "recommended", chat = "tabs",
	styles = { ActionBars = "Macros" },
})

-- The classic Blizzard shape: frames on the bar stack, portraits, gold.
Add({
	key = "Classic", title = "Classic",
	desc = "Blizzard's shape in EldoUI's frames: portraits, the bars in a block at the bottom and macro names on the buttons.",
	layout = "EldoBlizz1000", artStyle = "Blizzard",
	blizzard = "recommended", chat = "tabs",
	styles = { UnitFrames = "Blizzard", GroupFrames = "Blizzard", ActionBars = "Macros" },
	-- Bar 1 on the number row, as the game sets it.
	keymap = { preset = "numbers" },
})

-- The familiar original screen: portraits in the corners, a round minimap,
-- one bar row along the bottom, the layout's skin and Blizzard's own windows.
Add({
	key = "Vanilla", title = "Vanilla",
	desc = "The familiar original layout: portraits in the corners, a round minimap, one bar row along the bottom and Blizzard's own windows.",
	layout = "EldoVanilla1000",
	blizzard = "recommended", blizzardWindows = "layout", chat = "tabs",
	styles = {},
	keymap = { preset = "numbers" },
})

-- Healers: wide tiles for the group, the healer role layer. The group
-- spots come from the healer role on the Compact HUD layout.
Add({
	key = "Healer", title = "Healer",
	desc = "Big group tiles with heals on the way, unit frames close to the center and the healer role with click-casting suggestions.",
	layout = "EldoZen1000", role = "healer",
	blizzard = "recommended", chat = "tabs",
	styles = { GroupFrames = "Healer", UnitFrames = "Clean", ActionBars = "Clean" },
})

-- As little as possible: thin frames, no keybind text, a quiet info bar.
Add({
	key = "Minimal", title = "Minimal",
	desc = "A quiet screen: thin unit and group frames, no keybind text, a small minimap and a quiet info bar.",
	layout = "EldoZen1000",
	blizzard = "recommended", chat = "tabs",
	styles = { UnitFrames = "Minimal", GroupFrames = "Minimal", ActionBars = "Clean", Minimap = "Minimal", InfoBar = "Quiet" },
	-- No keybind text is the point of this pack.
	keymap = { showKeys = false },
})

-- Complete looks. Structured: the broad modern screen, quiet flat panels.
Add({
	key = "Structured", title = "Structured",
	desc = "A tidy modern screen: everything under your character, quiet flat panels with a fine edge and EldoUI's helpers.",
	layout = "EldoModern2000", artStyle = "MinimalModern", uiAmount = "moderate",
	blizzard = "recommended", chat = "tabs",
	styles = {},
})

-- Focus: an open middle and only what you need to play.
Add({
	key = "Focus", title = "Focus",
	desc = "An open middle and a quiet screen: high frames, the quietest skin and only what you need to play.",
	layout = "EldoZen1000", artStyle = "MinimalModern", uiAmount = "essential",
	blizzard = "recommended", chat = "tabs",
	styles = {},
})

-- Portrait Forge: classic portraits in round medallions, the bar block
-- (Blizzard Bottom Block).
Add({
	key = "PortraitForge", title = "Portrait Forge",
	desc = "Classic portraits in round medallions, the bars in a block at the bottom and EldoUI's helpers.",
	layout = "EldoBlizz1000", artStyle = "PortraitClassic", uiAmount = "moderate",
	blizzard = "recommended", chat = "tabs",
	styles = {},
})
