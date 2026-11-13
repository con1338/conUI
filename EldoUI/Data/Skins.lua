-- Skin manifests: what each skin is called, which art it draws (an art key of
-- Data/SkinData.lua), the accent and title font it brings, its bar texture
-- and which recipe paints each kind of surface. Core/Skins.lua registers them
-- at load; plugins add their own with E:RegisterSkin(id, manifest).
--
-- The five skins EldoUI had before (Modern, Blizzard, Classic, WoW Forever,
-- High contrast) are `legacy`: their painters stay the ones in Core/Media.lua,
-- so a profile on one of them looks exactly as it did.
--
-- Fields (all optional except title):
--   order        place in the skin list (lower first; High contrast is last)
--   title, short, desc   player texts
--   art          art key in E.skinData (nil for legacy skins)
--   legacy       true: the painter stays E.artStyles[id] from Core/Media.lua
--   accent       "RRGGBB" the skin brings; accentMode "bring" (replaces the
--                default or the layout's accent) or "soft" (replaces only the
--                default blue); both give it back when the player leaves
--   fonts.title  E.media.fonts name for window titles (General > Skin title font)
--   statusbar    bar texture name used while General > Bar texture is "Follow skin"
--   shadows      the skin draws frame shadows (General > Textures)
--   tint         the skin takes the panel tint (flat skins only)
--   recipes      surface kind -> painter (Core/Skins.lua) or unit graphics id
--   variants     looks of one skin that share every metric (Faction Heritage)
--   flags        small look choices modules ask for with E:SkinFlag(name):
--     bronze           what EldoUI's Bronze marks (Loot Guide pins and plate
--                      icons, the NPC dialog and Party Quests bronze looks) draw
--                      in: "accent" (the accent in use) or "skin" (the
--                      skin's own accent); nil keeps the Bronze color
--     selectedTabTint  selected tabs and look previews take the skin's tab
--                      fill (native skins with a tab color get it on their own)
--     tabFill          { r, g, b, a } the selected tab fill of a classic skin
--     pinShape         map note pins: "ring" or "atlas" (nil: tiles)
local _, E = ...
local L = E.L

local Key = E.Key
-- Every surface of a native skin: windows framed with corners, other panels
-- framed without, small boxes in the skin's colors, thin edges on bars.
local function Recipes(unit)
	return {
		window = "framed", panel = "framedThin", tooltip = "framedThin", chat = "framedThin",
		box = "palette", bar = "edge", castbar = "edge", button = "frame", minimap = "ring",
		icon = "iconRing", unitframe = unit, groupframe = unit,
	}
end

-- Legacy skins: their own painters; unit frames keep EldoUI's flat look.
local LEGACY_RECIPES = { unitframe = "MODERN", groupframe = "MODERN" }

E.skinManifests = {
	Modern = {
		order = 10, legacy = true, title = "Modern (flat)", shadows = true, tint = true,
		statusbar = "Smooth", recipes = LEGACY_RECIPES,
	},
	MinimalModern = {
		order = 15, art = "MINIMAL", title = "Minimal Modern",
		short = Key("Flat charcoal panels with one fine hairline."),
		desc = "Flat charcoal panels with one fine hairline and square corners, the quietest skin. Window titles use Inter.",
		fonts = { title = "Inter Medium" }, statusbar = "Minimal", shadows = true, tint = true,
		recipes = Recipes("MODERN"),
	},
	Blizzard = {
		order = 30, legacy = true, title = "Blizzard", tint = true,
		statusbar = "Smooth", recipes = LEGACY_RECIPES, flags = { pinShape = "atlas" },
	},
	Classic = {
		order = 40, legacy = true, title = "Classic",
		statusbar = "Smooth", recipes = LEGACY_RECIPES, flags = { pinShape = "ring" },
	},
	Forever = {
		order = 50, legacy = true, title = "WoW Forever", tint = true,
		accent = "DCA77F", accentMode = "bring",
		statusbar = "Smooth", recipes = LEGACY_RECIPES,
		-- The warm bronze of the WoW Forever client art.
		flags = { bronze = "accent", selectedTabTint = true, tabFill = { 0.36, 0.25, 0.14, 0.85 }, pinShape = "ring" },
	},
	VanillaOriginal = {
		order = 60, art = "VANILLA", title = "Vanilla Original",
		short = Key("Carved gray stone with a warm brass double line."),
		desc = "The game's own original frames: the classic player and target plates with the elite dragon (with the Classic frames unit style), the gryphon-capped action bar and the round minimap border. Windows get carved gray stone, a warm brass double line and stone clasps on their corners. Brings the Gold accent while yours is the default blue.",
		accent = "FFD100", accentMode = "soft", fonts = { title = "Cinzel" }, statusbar = "Vanilla",
		-- Unit frames wear the game's own classic plates (Core/UnitGraphics.lua).
		recipes = Recipes("VANILLA_ORIGINAL"),
	},
	VanillaRefined = {
		order = 70, art = "VANILLA_REFINED", title = "Vanilla Refined",
		short = Key("Satin graphite with a fine bronze edge."),
		desc = "The classic look tidied up: satin graphite, a fine bronze double edge and softened corners, with thin portrait rings. Brings the Sand accent while yours is the default blue.",
		accent = "DCA77F", accentMode = "soft", fonts = { title = "Marcellus" }, statusbar = "Vanilla Refined",
		flags = { bronze = "skin" },
		recipes = Recipes("VANILLA"),
	},
	Parchment = {
		order = 80, art = "PARCHMENT", title = "Warcraft Parchment",
		short = Key("Dark oak panels in a leather binding with paper trims."),
		desc = "Dark oak panels in a leather binding with paper trims and stitched seams, leather book corners and medallion portraits. Brings the Bronze accent while yours is the default blue.",
		accent = "C79C6E", accentMode = "soft", fonts = { title = "IM Fell English" }, statusbar = "Parchment",
		flags = { bronze = "skin" },
		recipes = Recipes("VANILLA"),
	},
	ForgedMetal = {
		order = 90, art = "FORGED", title = "Forged Metal",
		short = Key("Hammered iron with clipped steel rims."),
		desc = "Hammered iron with clipped steel rims, riveted corner plates and octagon portrait frames. Brass marks only what is selected. Brings the Sand accent while yours is the default blue.",
		accent = "DCA77F", accentMode = "soft", fonts = { title = "Barlow Condensed" }, statusbar = "Forged",
		flags = { bronze = "skin" },
		recipes = Recipes("PORTRAITBARS"),
	},
	PortraitClassic = {
		order = 100, art = "PORTRAIT_CLASSIC", title = "Portrait Classic",
		short = Key("Polished slate with layered silver lips."),
		desc = "Polished slate with layered silver lips, double medallion portrait rings and filigree corners: made for frames that lead with the portrait. Brings the Frost accent while yours is the default blue.",
		accent = "69CCF0", accentMode = "soft", fonts = { title = "Alegreya SC" }, statusbar = "Portrait",
		recipes = Recipes("VANILLA"),
	},
	FactionHeritage = {
		order = 110, art = "HERITAGE_NEUTRAL", title = "Faction Heritage",
		short = Key("Your faction's materials in one shared frame."),
		desc = "One frame in three materials: blue stone and brass for the Alliance, oxblood leather and iron for the Horde, weathered stone and steel otherwise. Follows your character's faction unless you pick one, and brings that faction's accent while yours is the default blue.",
		accent = "C79C6E", accentMode = "soft", fonts = { title = "Cinzel" }, statusbar = "Heritage",
		recipes = Recipes("PORTRAITBARS"),
		variants = {
			order = { "alliance", "horde", "neutral" },
			alliance = { title = "Alliance", art = "HERITAGE_ALLIANCE", accent = "69CCF0" },
			horde = { title = "Horde", art = "HERITAGE_HORDE", accent = "DCA77F" },
			neutral = { title = "Neutral", art = "HERITAGE_NEUTRAL", accent = "C79C6E" },
		},
	},
	Arcane = {
		order = 120, art = "ARCANE", title = "Arcane",
		short = Key("Obsidian glass with faceted silver edges."),
		desc = "Obsidian glass with faceted silver edges, engraved crystal corners and hexagon portrait frames. Nothing glows or moves. Brings the Lavender accent while yours is the default blue.",
		accent = "9482C9", accentMode = "soft", fonts = { title = "Marcellus SC" }, statusbar = "Arcane",
		recipes = Recipes("PORTRAITBARS"),
	},
	Infernal = {
		order = 130, art = "INFERNAL", title = "Infernal Stone",
		short = Key("Charred basalt with rusted iron and blood-red gems."),
		desc = "Charred basalt, rusted iron bands, pointed iron corner brackets and blood-red gems. Its clawed ring holds the liquid orbs of the Orbs unit frames. Window titles use a gothic letter. Brings the Garnet accent while yours is the default blue.",
		accent = "D24B3C", accentMode = "soft", fonts = { title = "Pirata One" }, statusbar = "Infernal",
		flags = { bronze = "skin" },
		recipes = Recipes("PORTRAITBARS"),
	},
	Contrast = {
		order = 1000, legacy = true, title = "High contrast",
		statusbar = "Smooth", recipes = LEGACY_RECIPES,
	},
}
