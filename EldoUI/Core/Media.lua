-- EldoUI shared look: fonts, textures, colors and small styling helpers.
-- Every module styles its frames through these, so the whole UI stays one look.
--
-- Portions adapted from Forever Journal by Ugge Zen, MIT License (see
-- THIRD_PARTY_NOTICES.md): the paper ink values (E.tokens.paper).
--
-- MIT License
--
-- Copyright (c) 2026 Ugge Zen
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
local _, E = ...
local Key = E.Key

local MEDIA = "Interface\\AddOns\\EldoUI\\Media\\"

-- Barlow Condensed and Rajdhani have no Cyrillic or Asian glyphs, so those
-- locales keep the game's own font.
local LATIN_LOCALES = {
	enUS = true, enGB = true, deDE = true, frFR = true, esES = true,
	esMX = true, itIT = true, ptBR = true,
}
local useOwnFonts = LATIN_LOCALES[GetLocale()]

E.media = {
	font = useOwnFonts and (MEDIA .. "Fonts\\BarlowCondensed-SemiBold.ttf") or STANDARD_TEXT_FONT,
	fontHeader = useOwnFonts and (MEDIA .. "Fonts\\Rajdhani-Bold.ttf") or STANDARD_TEXT_FONT,
	-- Every font the font dropdowns offer. Latin-only fonts fall back to the
	-- game font in other locales. Licenses and sources: Media/LICENSES.md.
	-- The "(Blizzard)" entries point at fonts that ship with the game client.
	fonts = {
		["Alegreya Sans SC"] = MEDIA .. "Fonts\\AlegreyaSansSC-Medium.ttf",
		["Alegreya SC"] = MEDIA .. "Fonts\\AlegreyaSC-Bold.ttf",
		["Almendra"] = MEDIA .. "Fonts\\Almendra-Bold.ttf",
		["Anton"] = MEDIA .. "Fonts\\Anton-Regular.ttf",
		["Arial Narrow (Blizzard)"] = "Fonts\\ARIALN.TTF",
		["Barlow"] = MEDIA .. "Fonts\\Barlow-Medium.ttf",
		["Barlow Condensed"] = MEDIA .. "Fonts\\BarlowCondensed-SemiBold.ttf",
		["Barlow Condensed Bold"] = MEDIA .. "Fonts\\BarlowCondensed-Bold.ttf",
		["Barlow Semi Condensed"] = MEDIA .. "Fonts\\BarlowSemiCondensed-Medium.ttf",
		["Barlow Semi Condensed SemiBold"] = MEDIA .. "Fonts\\BarlowSemiCondensed-SemiBold.ttf",
		["Barlow SemiBold"] = MEDIA .. "Fonts\\Barlow-SemiBold.ttf",
		["Bebas Neue"] = MEDIA .. "Fonts\\BebasNeue-Regular.ttf",
		["Black Ops One"] = MEDIA .. "Fonts\\BlackOpsOne-Regular.ttf",
		["Chakra Petch"] = MEDIA .. "Fonts\\ChakraPetch-SemiBold.ttf",
		["Chakra Petch Bold"] = MEDIA .. "Fonts\\ChakraPetch-Bold.ttf",
		["Cinzel"] = MEDIA .. "Fonts\\Cinzel-Regular.ttf",
		["Cinzel Bold"] = MEDIA .. "Fonts\\Cinzel-Bold.ttf",
		["Cinzel Decorative"] = MEDIA .. "Fonts\\CinzelDecorative-Regular.ttf",
		["Cinzel Decorative Bold"] = MEDIA .. "Fonts\\CinzelDecorative-Bold.ttf",
		["EB Garamond"] = MEDIA .. "Fonts\\EBGaramond-SemiBold.ttf",
		["Exo 2"] = MEDIA .. "Fonts\\Exo2-SemiBold.ttf",
		["Exo 2 Bold"] = MEDIA .. "Fonts\\Exo2-Bold.ttf",
		["Fira Mono"] = MEDIA .. "Fonts\\FiraMono-Medium.ttf",
		["Fira Sans"] = MEDIA .. "Fonts\\FiraSans-Medium.ttf",
		["Fira Sans Condensed"] = MEDIA .. "Fonts\\FiraSansCondensed-Medium.ttf",
		["Fjalla One"] = MEDIA .. "Fonts\\FjallaOne-Regular.ttf",
		["Fondamento"] = MEDIA .. "Fonts\\Fondamento-Regular.ttf",
		["Friz Quadrata (Blizzard)"] = "Fonts\\FRIZQT__.TTF",
		["IBM Plex Mono"] = MEDIA .. "Fonts\\IBMPlexMono-Medium.ttf",
		["IBM Plex Sans Condensed"] = MEDIA .. "Fonts\\IBMPlexSansCondensed-SemiBold.ttf",
		["IM Fell English"] = MEDIA .. "Fonts\\IMFellEnglish-Regular.ttf",
		["IM Fell English SC"] = MEDIA .. "Fonts\\IMFellEnglishSC-Regular.ttf",
		["Inter"] = MEDIA .. "Fonts\\Inter-Regular.ttf",
		["Inter Medium"] = MEDIA .. "Fonts\\Inter-Medium.ttf",
		["JetBrains Mono"] = MEDIA .. "Fonts\\JetBrainsMono-Medium.ttf",
		["Lato Bold"] = MEDIA .. "Fonts\\Lato-Bold.ttf",
		["Macondo"] = MEDIA .. "Fonts\\Macondo-Regular.ttf",
		["Marcellus"] = MEDIA .. "Fonts\\Marcellus-Regular.ttf",
		["Marcellus SC"] = MEDIA .. "Fonts\\MarcellusSC-Regular.ttf",
		["MedievalSharp"] = MEDIA .. "Fonts\\MedievalSharp.ttf",
		["Montserrat"] = MEDIA .. "Fonts\\Montserrat-SemiBold.ttf",
		["Morpheus (Blizzard)"] = "Fonts\\MORPHEUS.ttf",
		["Noto Sans"] = MEDIA .. "Fonts\\NotoSans-Medium.ttf",
		["Open Sans"] = MEDIA .. "Fonts\\OpenSans-SemiBold.ttf",
		["Open Sans Bold"] = MEDIA .. "Fonts\\OpenSans-Bold.ttf",
		["Orbitron"] = MEDIA .. "Fonts\\Orbitron-Bold.ttf",
		["Oswald"] = MEDIA .. "Fonts\\Oswald-Medium.ttf",
		["Oswald Bold"] = MEDIA .. "Fonts\\Oswald-Bold.ttf",
		["Outfit"] = MEDIA .. "Fonts\\Outfit-Medium.ttf",
		["Outfit SemiBold"] = MEDIA .. "Fonts\\Outfit-SemiBold.ttf",
		["Philosopher"] = MEDIA .. "Fonts\\Philosopher-Bold.ttf",
		["Pirata One"] = MEDIA .. "Fonts\\PirataOne-Regular.ttf",
		["Play"] = MEDIA .. "Fonts\\Play-Regular.ttf",
		["Play Bold"] = MEDIA .. "Fonts\\Play-Bold.ttf",
		["Plus Jakarta Sans"] = MEDIA .. "Fonts\\PlusJakartaSans-Medium.ttf",
		["Poppins"] = MEDIA .. "Fonts\\Poppins-Medium.ttf",
		["PT Sans"] = MEDIA .. "Fonts\\PTSans-Regular.ttf",
		["PT Sans Narrow"] = MEDIA .. "Fonts\\PTSansNarrow-Bold.ttf",
		["Quantico"] = MEDIA .. "Fonts\\Quantico-Bold.ttf",
		["Rajdhani"] = MEDIA .. "Fonts\\Rajdhani-Bold.ttf",
		["Roboto"] = MEDIA .. "Fonts\\Roboto-Medium.ttf",
		["Roboto Condensed"] = MEDIA .. "Fonts\\RobotoCondensed-Bold.ttf",
		["Roboto Mono"] = MEDIA .. "Fonts\\RobotoMono-Medium.ttf",
		["Russo One"] = MEDIA .. "Fonts\\RussoOne-Regular.ttf",
		["Saira Condensed"] = MEDIA .. "Fonts\\SairaCondensed-SemiBold.ttf",
		["Saira Condensed Bold"] = MEDIA .. "Fonts\\SairaCondensed-Bold.ttf",
		["Share Tech"] = MEDIA .. "Fonts\\ShareTech-Regular.ttf",
		["Share Tech Mono"] = MEDIA .. "Fonts\\ShareTechMono-Regular.ttf",
		["Skurri (Blizzard)"] = "Fonts\\skurri.ttf",
		["Source Sans 3"] = MEDIA .. "Fonts\\SourceSans3-Semibold.ttf",
		["Space Mono"] = MEDIA .. "Fonts\\SpaceMono-Regular.ttf",
		["Titillium Web"] = MEDIA .. "Fonts\\TitilliumWeb-SemiBold.ttf",
		["Titillium Web Bold"] = MEDIA .. "Fonts\\TitilliumWeb-Bold.ttf",
		["Ubuntu"] = MEDIA .. "Fonts\\Ubuntu-Medium.ttf",
		["Ubuntu Condensed"] = MEDIA .. "Fonts\\UbuntuCondensed-Regular.ttf",
		["Ubuntu Mono"] = MEDIA .. "Fonts\\UbuntuMono-Regular.ttf",
		["Uncial Antiqua"] = MEDIA .. "Fonts\\UncialAntiqua-Regular.ttf",
		["UnifrakturMaguntia"] = MEDIA .. "Fonts\\UnifrakturMaguntia-Book.ttf",
	},
	flat = "Interface\\Buttons\\WHITE8X8",
	statusbar = MEDIA .. "Textures\\EldoSmooth.tga",
	statusbars = {
		Flat = MEDIA .. "Textures\\EldoFlat.tga",
		Smooth = MEDIA .. "Textures\\EldoSmooth.tga",
		Gloss = MEDIA .. "Textures\\EldoGloss.tga",
		Stripes = MEDIA .. "Textures\\EldoStripes.tga",
		Soft = MEDIA .. "Textures\\EldoSoft.tga",
		Matte = MEDIA .. "Textures\\EldoMatte.tga",
		Sheen = MEDIA .. "Textures\\EldoSheen.tga",
		Caps = MEDIA .. "Textures\\EldoCaps.tga",
		["Blizzard"] = "Interface\\TargetingFrame\\UI-StatusBar",
	},
	shadow = MEDIA .. "Textures\\EldoShadow.tga",
	glow = MEDIA .. "Textures\\EldoGlow.tga",
	logo = MEDIA .. "Textures\\EldoLogo.tga",
	icon = MEDIA .. "Textures\\EldoIcon.tga",

	backdropColor = { 0.06, 0.06, 0.08, 0.80 },
	borderColor = { 0, 0, 0, 1 },
	accentColor = { 0.20, 0.67, 1.00, 1 }, -- matches the |cff33aaff name color
	textColor = { 1, 1, 1, 1 },
}

---------------------------------------------------------------------------
-- Design tokens (DESIGN.md §2-3). Every look value lives here: text
-- colors by meaning, hover and pressed strengths, the type ramp, control
-- heights and panel opacity. Core, kits and modules read them instead of
-- writing their own numbers, so one change retunes every window.
--   E.tokens.text.secondary   { r, g, b }   also E.media.text
--   E.tokens.hover.row        white alpha of a hovered list row
--   E.tokens.size.windowTitle header-font size of a window title
---------------------------------------------------------------------------
E.tokens = {
	text = {
		body = { 0.92, 0.92, 0.94 },
		secondary = { 0.65, 0.65, 0.70 },   -- hints, captions, descriptions
		dim = { 0.45, 0.45, 0.48 },         -- placeholders, disabled text
		-- good leans blue-green so it stays apart from warn and bad for
		-- red-green color blindness. bad is a light red so it still reads
		-- on a see-through panel over a bright world.
		good = { 0.05, 0.92, 0.62 },
		warn = { 1, 0.75, 0.2 },
		bad = { 1, 0.47, 0.42 },
		-- The game's own gold (NORMAL_FONT_COLOR): text that sits in or
		-- next to Blizzard's frames and keeps their look.
		gold = { 1, 0.82, 0 },
	},
	-- Coin colors of money text (E:FormatMoney): gold, silver, copper.
	money = { gold = { 1, 0.82, 0 }, silver = { 0.78, 0.78, 0.81 }, copper = { 0.93, 0.65, 0.37 } },
	-- White overlay alpha: a hovered list row, a hovered control, a hovered
	-- HUD slot (action buttons, bag and character slots).
	hover = { row = 0.06, control = 0.10, hud = 0.15 },
	pressed = 0.25,                          -- accent alpha of a selected or pressed item
	disabledAlpha = 0.4,
	-- label: 12, between body and small (labels of values, short status lines).
	-- pageTitle: the page title of the full windows with a sidebar (the
	-- options window and the installer), a step above window titles.
	-- cardTitle: 14, a card title or a panel's lead line (setup cards, the
	-- options window's module off panel), a step above body.
	-- tiny: 10, the smallest text: badges, counts, item levels and pin or
	-- tick labels on icons and bars. display: 18, a large banner or notice
	-- line over the game world (the keybind banner title, a reminder notice).
	-- hero: 28, the large numbers of a full-screen panel (the away screen's
	-- clock and away timer).
	size = { windowTitle = 20, dialogTitle = 16, pageTitle = 24, hero = 28, display = 18, cardTitle = 14, section = 13, body = 13, label = 12, small = 11, tiny = 10 },
	-- twoLineRow: a list row with a name line and a muted second line
	-- (friends, guild, alts); foldRow: a fold divider over its rows.
	height = { button = 22, buttonLarge = 26, row = 20, settingsRow = 32, tab = 24, twoLineRow = 34, foldRow = 22 },
	-- The slim icon rail on a window's edge (chat, minimap): its width,
	-- its square buttons and the gap between them.
	rail = { width = 22, button = 18, gap = 4 },
	-- panel: alpha is the default opacity; minAlpha the lowest General >
	-- Panel opacity goes; a see-through panel is alpha x transparentFactor
	-- and never under transparentFloor. Secondary and red text keep
	-- contrast 4.5 down to the floor, over a bright world too.
	panel = { alpha = 0.92, minAlpha = 0.80, transparentFactor = 0.87, transparentFloor = 0.80 },
	-- A soft drop shadow for text on see-through panels without an outline
	-- (General > Text shadow off), so a busy world behind stays apart.
	softShadow = { offset = 1, alpha = 0.5 },
	-- The shadow of window text, which has no outline (E:SetWindowFont).
	windowShadow = { offset = 1, alpha = 0.6 },
	-- White text on a light bar fill (a priest's class-colored health
	-- bar): a thick dark outline and a full dark shadow, whatever the
	-- outline setting, so it reads over the light fill and the dark empty
	-- part of the bar alike (E:SetTextOnLightFill). A fill is light when
	-- white text on it stays under contrast `contrast`.
	lightFillText = { outline = "THICKOUTLINE", offset = 1, alpha = 1, contrast = 4.5 },
	-- window: a window's hairline; divider: lines between groups, under
	-- headers and tabs, over footers; hud: the HUD frame border.
	-- blizzard and classic: the tooltip-border edge of those art styles.
	-- control: the resting edge of buttons and check boxes, so they stand
	-- out from the panel (contrast 3.0, tools/design/contrast.py); an art
	-- style may set its own in controlStyles, a drawn skin uses its edge
	-- color (E:ControlEdgeColor).
	edge = { window = { 1, 1, 1, 0.4 }, divider = { 1, 1, 1, 0.08 }, hud = { 0, 0, 0, 1 },
		blizzard = { 0.6, 0.6, 0.65, 1 }, classic = { 0.85, 0.7, 0.4, 1 }, control = { 1, 1, 1, 0.36 },
		controlStyles = { Blizzard = { 0.6, 0.6, 0.65, 1 }, Classic = { 0.85, 0.7, 0.4, 1 }, Contrast = { 1, 1, 1, 1 } } },
	inset = { 0, 0, 0, 0.25 },
	-- The dim shade over a window behind a question asked inside it.
	shade = { 0, 0, 0, 0.6 },
	-- A thin track under a moving part: scroll bar tracks, progress lines.
	track = { 1, 1, 1, 0.06 },
	-- Section card (E.UIKit.SectionCard): the box that holds one section's
	-- rows in the options window and the installer. fill is laid over the
	-- panel (a dark tint, so text keeps its contrast over a bright world),
	-- edge is its 1 px border and stripe the white alpha of every second
	-- row. An art style may set its own values; what it leaves out comes
	-- from the values above it.
	card = {
		fill = { 0, 0, 0, 0.25 },
		edge = { 1, 1, 1, 0.08 },
		stripe = 0.03,
		styles = {
			Blizzard = { edge = { 0.6, 0.6, 0.65, 0.30 } },
			Classic = { fill = { 0, 0, 0, 0.30 }, edge = { 0.85, 0.7, 0.4, 0.30 } },
			Forever = { edge = { 0.85, 0.7, 0.4, 0.25 } },
			Contrast = { fill = { 0, 0, 0, 0 }, edge = { 1, 1, 1, 0.6 }, stripe = 0.08 },
		},
	},
	-- Every scroll thumb: color at rest, accent alpha on hover or drag,
	-- drawn width, shortest length, and the width of the bar it sits in
	-- (its hit area).
	scrollThumb = { color = { 0.45, 0.45, 0.48, 0.9 }, hover = 1, width = 5, min = 24, bar = 8 },
	-- Flat sliders: how much lighter the thumb gets on hover or drag, and
	-- the accent alpha of the filled part of the track.
	slider = { hoverLighten = 0.15, fill = 0.45 },
	-- The resize grip in a window's corner: its drawn size and the alpha of
	-- its secondary-gray steps at rest (the accent on hover or drag).
	grip = { size = 16, rest = 0.9 },
	-- Motion (seconds): duration of a show or hide, and of a hover fade.
	-- With General > Animations off everything changes at once.
	motion = { duration = 0.22, hover = 0.15 },
	-- Accent alpha of the soft glow behind a page title (the options
	-- window and the installer).
	headerGlow = 0.08,
	-- Accent alpha of the two thin lines of a fold divider (stats, tracker).
	foldLine = 0.6,
	-- The Loot Guide journal (My Adventure): textStep is how many points its
	-- small, label, body and section texts sit above the shared sizes.
	journal = { textStep = 2 },
	iconCoords = { 0.08, 0.92, 0.08, 0.92 },
	portraitCrop = 0.15,                     -- share cut from each edge of a 2D unit portrait
	-- Inks of the parchment page (My Adventure's Storybook style and the
	-- Book's Parchment look), under the MIT License notice at the top of
	-- this file. Dark ink on light paper, so texts drop their shadow there.
	--   fill       page color when the parchment atlas is missing
	--   card       card fill over the paper (alpha), rule its edges and dividers
	--   body/ink   body text; head titles and chapter names; secondary
	--              captions and times; dim placeholders; link links (hover
	--              is the accent); good, warn and bad status words
	--   quality    item names by quality (0-7), darker so they read on paper
	paper = {
		fill = { 0.86, 0.78, 0.62 },
		card = { 1, 0.97, 0.90, 0.25 },
		body = { 0.11, 0.07, 0.02 },
		head = { 0.23, 0.10, 0.02 },
		secondary = { 0.29, 0.20, 0.09 },
		dim = { 0.35, 0.24, 0.12 },
		link = { 0.29, 0.09, 0.01 },
		-- Teal, olive brown and wine: dark enough for the paper and still
		-- apart for every common kind of color blindness.
		good = { 0.15, 0.35, 0.35 },
		warn = { 0.40, 0.30, 0.00 },
		bad = { 0.45, 0.00, 0.15 },
		rule = { 0.45, 0.30, 0.12, 0.45 },
		tint = { 1, 0.95, 0.85 },  -- warm tint over a tiled paper background
		wash = 0.35,               -- the paper color over the parchment texture under reading text (alpha)
		quality = {
			[0] = { 0.35, 0.35, 0.35 }, [1] = { 0.29, 0.17, 0.06 }, [2] = { 0.12, 0.43, 0.00 }, [3] = { 0.04, 0.29, 0.60 },
			[4] = { 0.42, 0.12, 0.63 }, [5] = { 0.60, 0.29, 0.00 }, [6] = { 0.48, 0.39, 0.13 }, [7] = { 0.00, 0.42, 0.53 },
		},
	},
	-- The Book (My Adventure's story view): page margin
	-- and spread gutter, drop cap height in lines and its box fill (accent
	-- alpha), leading and paragraph spacing, and the era hues: the accent's
	-- hue turned in eraStep degrees at eraSaturation, worked out when drawn
	-- so they follow the accent.
	book = { margin = 24, gutter = 32, dropCapLines = 3, dropCapAlpha = 0.18, lineGap = 3, paraGap = 6,
		eraSaturation = 0.55, eraStep = 50 },
	-- Bar parts that have no setting of their own: the rested part of an
	-- experience bar, the latency zone at the end of a cast bar.
	-- tag: the value tag beside an upright XP or reputation bar: the
	-- pointer glyph's size and how far it tucks under the tag (the glyph
	-- has a clear margin), the gap to the bars, the padding around its text.
	bar = { rested = { 0.3, 0.5, 1 }, latency = { 0.85, 0.2, 0.2 },
		tag = { pointer = 12, tuck = 3, gap = 0, padX = 4, padY = 2 } },
	-- Map art: unexplored areas shown dimmed (Maps).
	map = { unexplored = { 0.62, 0.62, 0.66 } },
	-- Color sets. safe: the Okabe-Ito colors, which stay apart for every
	-- kind of color blindness (the Beacon nameplate style, color-blind safe
	-- options). Anything colored this way also carries a word or a shape.
	palette = {
		safe = {
			orange = { 0.90, 0.62, 0.00 }, sky = { 0.34, 0.71, 0.91 }, green = { 0.00, 0.62, 0.45 },
			yellow = { 0.94, 0.89, 0.26 }, blue = { 0.00, 0.45, 0.70 }, vermilion = { 0.84, 0.37, 0.00 },
			purple = { 0.80, 0.47, 0.65 }, gray = { 0.42, 0.42, 0.44 },
		},
		-- The named Bronze accent (General > Accent color, C79C6E): the
		-- "Forever bronze" looks of Zone Quests, Party Quests and NPC Dialog.
		bronze = { 199 / 255, 156 / 255, 110 / 255 },
		-- The High contrast art style: black, opaque panels with
		-- white borders.
		contrast = { backdrop = { 0, 0, 0, 1 }, border = { 1, 1, 1, 1 } },
		-- Panel tints (General > Textures > Panel tint), a design decision:
		-- a hue mixed into the dark panel background at `strength`, so a
		-- panel turns a deep blue, green, wine or violet while text keeps
		-- its contrast (tools/design/contrast.py checks every tint in every
		-- art style it applies to).
		tint = {
			strength = 0.12,
			midnight = { 0.20, 0.40, 0.90 },
			pine = { 0.10, 0.62, 0.42 },
			wine = { 0.78, 0.16, 0.30 },
			dusk = { 0.52, 0.30, 0.86 },
		},
	},
	-- Frame shadows (General > Textures, Modern art style): the default
	-- strength and size, and the range the sliders offer.
	shadow = { alpha = 0.6, size = 4, minAlpha = 0.2, minSize = 2, maxSize = 12 },
	-- Native skins (Core/Skins.lua, Data/SkinData.lua). Small boxes take the
	-- skin's panel color at boxAlpha and its edge darkened to borderShade; a
	-- selected tab mixes tabMix of the edge into the second panel color at
	-- tabAlpha; a section card's edge is the skin edge at cardEdge. tile: the
	-- units one panel texture tile covers; corner: the size of a window corner
	-- ornament, shown from cornerMin (width, height) up; edgeThin: the thin
	-- edge on bars; hoverAlpha: the button hover overlay in the highlight color;
	-- iconRing: the ring on aura and cooldown icons, drawn from iconMin up.
	-- seeThrough (set below): see-through panels are never lighter than the
	-- flat panel, so text keeps its contrast over a bright world.
	skin = { boxAlpha = 0.86, borderShade = 0.45, tabMix = 0.3, tabAlpha = 0.85, cardEdge = 0.30,
		tile = 64, corner = 32, cornerMin = { 96, 64 }, edgeThin = 3, hoverAlpha = 0.45, iconRing = 2, iconMin = 20 },
}
E.tokens.paper.ink = E.tokens.paper.body
E.tokens.skin.seeThrough = { E.media.backdropColor[1], E.media.backdropColor[2], E.media.backdropColor[3] }
E.media.text = E.tokens.text

-- A color token as a |cff escape, for text built from parts.
function E:TokenHex(color)
	return ("|cff%02x%02x%02x"):format(color[1] * 255 + 0.5, color[2] * 255 + 0.5, color[3] * 255 + 0.5)
end

-- The accent as a text color: the same color, lightened toward white just
-- enough to read on the darkest panel (contrast 4.5 over the brightest game
-- world, DESIGN.md §2). Light accents stay as they are; fills, borders and
-- swatches keep the accent itself. E:UpdateAccent keeps it current.
local function Linear(c)
	if c <= 0.04045 then return c / 12.92 end
	return ((c + 0.055) / 1.055) ^ 2.4
end
local function Luminance(r, g, b)
	return 0.2126 * Linear(r) + 0.7152 * Linear(g) + 0.0722 * Linear(b)
end
function E:AccentTextColor(r, g, b)
	local back, alpha = self.media.backdropColor, self.tokens.panel.alpha
	-- The panel over a bright world (0.85 gray) is the lightest it gets.
	local panel = Luminance(back[1] * alpha + 0.85 * (1 - alpha), back[2] * alpha + 0.85 * (1 - alpha),
		back[3] * alpha + 0.85 * (1 - alpha))
	local need = 4.5 * (panel + 0.05) - 0.05
	local t = 0
	while t < 1 do
		local tr, tg, tb = r + (1 - r) * t, g + (1 - g) * t, b + (1 - b) * t
		if Luminance(tr, tg, tb) >= need then return tr, tg, tb end
		t = t + 0.02
	end
	return 1, 1, 1
end
E.media.accentText = { E:AccentTextColor(unpack(E.media.accentColor)) }
E.media.accentText[4] = 1

-- A text token as r, g, b for SetTextColor, SetColorTexture or a tooltip
-- line: E:TokenColor("secondary"). `kind` is a key of E.tokens.text, or
-- "accent". `extra` is passed on after b: the alpha of a texture, or the
-- wrap flag of GameTooltip:AddLine.
function E:TokenColor(kind, extra)
	local c = kind == "accent" and self.media.accentText or self.tokens.text[kind] or self.tokens.text.body
	if extra ~= nil then return c[1], c[2], c[3], extra end
	return c[1], c[2], c[3]
end

-- A text token (or "accent") as a |cff escape: E:TextHex("secondary").
-- Read when the text is built, so the accent is the current one.
function E:TextHex(kind)
	return self:TokenHex(kind == "accent" and self.media.accentText or self.tokens.text[kind] or self.tokens.text.body)
end

-- The accent text color as a |cff escape (E:UpdateAccent keeps it current).
E.color = E:TokenHex(E.media.accentText)

-- A word the player should notice (a slash command, a name): accent color
-- instead of literal yellow or gold.
function E:Highlight(text)
	return self:TokenHex(self.media.accentText) .. tostring(text) .. "|r"
end

-- Crop an icon's default border with the shared coordinates. `zoom` (0-0.4)
-- crops further, as the action bars' icon zoom does.
function E:TrimIcon(texture, zoom)
	local c = self.tokens.iconCoords
	local z = (zoom or 0) / 2
	texture:SetTexCoord(c[1] + z, c[2] - z, c[3] + z, c[4] - z)
	return texture
end

-- Coordinates of an icon cut `crop` (share of each edge, default the token
-- crop) and trimmed further on the long sides so a button that is not
-- square shows the icon unstretched: left, right, top, bottom.
function E:IconCoords(crop, width, height)
	crop = math.max(0, math.min(0.45, tonumber(crop) or self.tokens.iconCoords[1]))
	local left, right, top, bottom = crop, 1 - crop, crop, 1 - crop
	local ratio = (width and height and height > 0) and width / height or 1
	if ratio > 1 then
		local keep = (bottom - top) / ratio
		top = 0.5 - keep / 2
		bottom = 0.5 + keep / 2
	elseif ratio < 1 then
		local keep = (right - left) * ratio
		left = 0.5 - keep / 2
		right = 0.5 + keep / 2
	end
	return left, right, top, bottom
end

-- A see-through background's opacity for a given opacity: transparentFactor
-- of it, never under transparentFloor.
function E:SeeThroughAlpha(alpha)
	local panel = self.tokens.panel
	return math.max(panel.transparentFloor, alpha * panel.transparentFactor)
end

-- Opacity of a window or panel background (General > Panel opacity), at
-- least panel.minAlpha. The see-through variant never goes under
-- panel.transparentFloor, where secondary and red text still read on a
-- bright world (tools/design/contrast.py checks both).
E.defaults.general.panelAlpha = E.tokens.panel.alpha
-- The resting edge of buttons and check boxes in the art style in use.
function E:ControlEdgeColor()
	local edge = self.tokens.edge
	local style = self.db and self.ArtStyle and self:ArtStyle() or "Modern"
	local own = edge.controlStyles[style]
	if own then return own end
	local m = self.SkinManifest and self:SkinManifest(style)
	local skinEdge = m and not m.legacy and m.data and m.data.colors and m.data.colors.edge
	if skinEdge then return { skinEdge[1], skinEdge[2], skinEdge[3], 1 } end
	return edge.control
end

function E:PanelAlpha(transparent)
	-- High contrast: panels are fully opaque.
	if self.db and self.ArtStyle and self:ArtStyle() == "Contrast" then return 1 end
	local general = self.db and self.db.general
	local alpha = tonumber(general and general.panelAlpha) or self.tokens.panel.alpha
	alpha = math.min(1, math.max(self.tokens.panel.minAlpha, alpha))
	if transparent then alpha = self:SeeThroughAlpha(alpha) end
	return alpha
end

-- A Panel opacity saved under the lowest the slider now offers comes up to it.
E:RegisterProfileMigration(function(profile)
	local general = type(profile.general) == "table" and profile.general
	local alpha = general and tonumber(general.panelAlpha)
	if alpha and alpha < E.tokens.panel.minAlpha then general.panelAlpha = E.tokens.panel.minAlpha end
end, "general:panelAlphaMin", 1)

E.defaults.general.fontSize = 14
-- "Skin": the bar texture of the skin in use (Smooth for the flat skins).
E.defaults.general.statusbar = "Skin"
-- Art style and accent: Modern with the blue accent, or the client's own
-- look on WoW: Forever (E:ApplyClientLookDefaults, below).
E.defaults.general.artStyle = "Modern"  -- Modern, Blizzard, Classic or Forever (E.artStyleOrder)
E.defaults.general.font = "Barlow Condensed"
E.defaults.general.accent = "33AAFF"
E.defaults.general.accentCustom = { 0.2, 0.67, 1 } -- hex color, or "class" for the class color

-- Copy the profile's accent into E.media.accentColor (in place, so every
-- reference to the table sees the change).
function E:UpdateAccent()
	local accent = self.db.general.accent
	local r, g, b
	if accent == "class" then
		r, g, b = self:ClassColor("player")
	elseif accent == "custom" and type(self.db.general.accentCustom) == "table" then
		r, g, b = unpack(self.db.general.accentCustom)
	elseif type(accent) == "string" and accent:match("^%x%x%x%x%x%x$") then
		r = tonumber(accent:sub(1, 2), 16) / 255
		g = tonumber(accent:sub(3, 4), 16) / 255
		b = tonumber(accent:sub(5, 6), 16) / 255
	end
	-- Game fonts work in every locale; bundled fonts only where they have the glyphs.
	local font = self.media.fonts[self.db.general.font]
	if font and not useOwnFonts and not font:find("^Fonts") then font = nil end
	-- Fonts and bars from SharedMedia packs come through the media registry.
	if not font and self.FetchMedia then font = self:FetchMedia("font", self.db.general.font) end
	if font then self.media.font = font end
	self.media.statusbar = self.media.statusbars[self.db.general.statusbar]
		or (self.FetchMedia and self:FetchMedia("statusbar", self.db.general.statusbar))
		or self.media.statusbars.Smooth
	if self.UpdateStylePalette then self:UpdateStylePalette() end
	if r then
		local color = self.media.accentColor
		color[1], color[2], color[3] = r, g, b
		local text = self.media.accentText
		text[1], text[2], text[3] = self:AccentTextColor(r, g, b)
		self.color = self:TokenHex(text)
	end
	-- Color tables, number format, cooldown and game fonts (below) follow
	-- the profile too.
	if self.UpdateColors then self:UpdateColors() end
	if self.UpdateNumberFormat then self:UpdateNumberFormat() end
	if self.UpdateCooldownFont then self:UpdateCooldownFont() end
	if self.UpdateGameFonts then self:UpdateGameFonts() end
end
E.defaults.general.fontOutline = "OUTLINE"

-- One physical pixel in UIParent units, set by Core/Scale.lua.
E.pixel = 1

-- The class color of a unit (the player's own, or custom ones from the
-- Colors page), or the accent color when the class is unknown.
function E:ClassColor(unit)
	local _, class = UnitClass(unit or "player")
	if class and self.GetClassColor then
		local r, g, b = self:GetClassColor(class)
		if r then return r, g, b end
	end
	local color = class and C_ClassColor.GetClassColor(class)
	if color then return color.r, color.g, color.b end
	return unpack(self.media.accentColor)
end

---------------------------------------------------------------------------
-- Theme refresh. E:SetFont, E:SetHeaderFont and E:SetTemplate
-- remember what they applied (weak tables, nothing kept alive), and
-- E:UpdateArtStyle re-applies it after the font, outline, accent or art
-- style changed, so text and small boxes follow the theme without a
-- reload. A text or box a module colored or re-fonted on its own (a
-- quality border, a hover accent, a picked media font) no longer matches
-- what was recorded and is left to that module's OnProfileChanged.
---------------------------------------------------------------------------
local themedFonts = setmetatable({}, { __mode = "k" })     -- fontString -> { path, size, outline, header }
-- Texts that draw a character's name in the name font (a font family, see
-- "Name fonts" below): fontString -> { font, path, size, flags, theme }.
local nameFonts = setmetatable({}, { __mode = "k" })
-- Texts marked with E:UseNameFont: every font EldoUI sets on them becomes
-- the name font of that font, size and outline.
local nameTexts = setmetatable({}, { __mode = "k" })
local themedBoxes = setmetatable({}, { __mode = "k" })     -- frame -> { transparent, bg = {}, border = {} }
local pixelEdges = setmetatable({}, { __mode = "k" })      -- frame -> edge size it got from E.pixel

-- Is the frame's size secret right now? The game sizes some frames from
-- secret values (nameplate health areas, aura buttons, unit frames in
-- combat), and every frame anchored to them reads a secret width.
function E:SizeIsSecret(frame)
	if not (frame and frame.GetWidth) then return false end
	return self:IsSecret(frame:GetWidth()) or self:IsSecret(frame:GetHeight())
end

-- The backdrop's texture coordinates follow the frame's size. Blizzard's
-- backdrop code does math on the width and height, which addon code may
-- not do with a secret size, so a secret size keeps the coordinates it had
-- (flat edges look the same at any size) until the size reads again.
-- Boxes whose first backdrop waits for a readable size (E:SetTemplate):
-- frame -> transparent. They get it on their next readable size change or
-- when combat ends, whichever comes first.
local waitingBoxes = setmetatable({}, { __mode = "k" })
local waitingEvents

local function ApplyWaiting()
	for frame, transparent in pairs(waitingBoxes) do
		if not E:SizeIsSecret(frame) then E:SetTemplate(frame, transparent) end
	end
end

local function WaitForSize(frame, transparent)
	waitingBoxes[frame] = transparent and true or false
	if not waitingEvents then
		waitingEvents = true
		E:RegisterEvent("PLAYER_REGEN_ENABLED", ApplyWaiting, waitingBoxes)
	end
end

local function BackdropSizeChanged(frame, width, height)
	if E:IsSecret(width) or E:IsSecret(height) or E:SizeIsSecret(frame) then return end
	if waitingBoxes[frame] ~= nil then
		E:SetTemplate(frame, waitingBoxes[frame])
		return
	end
	if not frame.OnBackdropSizeChanged then return end
	frame:OnBackdropSizeChanged()
end

-- Give one of EldoUI's own frames the backdrop methods (SetBackdrop and
-- the rest) and keep its edges in step with its size. Never use it on a
-- Blizzard frame.
function E:AddBackdrop(frame)
	if frame.SetBackdrop then return frame end
	Mixin(frame, BackdropTemplateMixin)
	frame:HookScript("OnSizeChanged", BackdropSizeChanged)
	return frame
end

-- Buttons a Masque skin draws (Core/Masque.lua): their E:SetTemplate box
-- goes and stays gone. A later E:SetTemplate (a module's repaint), a new
-- UI scale or a theme change would otherwise draw it over the skin.
local droppedBoxes = setmetatable({}, { __mode = "k" })

function E:DropTemplate(frame)
	droppedBoxes[frame] = true
	themedBoxes[frame], pixelEdges[frame], waitingBoxes[frame] = nil, nil, nil
	if frame.SetBackdrop then frame:SetBackdrop(nil) end
end

function E:TemplateDropped(frame)
	return droppedBoxes[frame] == true
end

local function SamePath(a, b)
	if type(a) ~= "string" or type(b) ~= "string" then return false end
	return a:lower():gsub("/", "\\") == b:lower():gsub("/", "\\")
end

-- Texts that sit on a see-through panel (E:SetSeeThroughText, or found
-- through their parents); weak, so nothing is kept alive.
local seeThroughTexts = setmetatable({}, { __mode = "k" })

local function OnSeeThrough(fontString)
	if seeThroughTexts[fontString] then return true end
	local panels = E.panels
	local frame = panels and fontString.GetParent and fontString:GetParent()
	for _ = 1, 4 do
		if not frame then return false end
		if panels[frame] == "transparent" then return true end
		frame = frame.GetParent and frame:GetParent()
	end
	return false
end

-- General > Text shadow: a 1-pixel drop shadow, full strength on text
-- without an outline and softer under an outline. With it off, text on a
-- see-through panel without an outline still gets the soft shadow
-- (tokens.softShadow), so the world behind never runs into the letters.
E.defaults.general.fontShadow = false
local windowTexts = setmetatable({}, { __mode = "k" }) -- font string -> true (E:SetWindowFont)

-- Texts marked with E:SetTextOnLightFill (fontString -> true): they wear
-- the light-fill halo (tokens.lightFillText) over every font EldoUI sets.
local lightFillTexts = setmetatable({}, { __mode = "k" })

-- The outline a text gets: the halo's on a light fill, else the one asked
-- for (or the profile's).
local function TextFlags(fontString, flags)
	if not lightFillTexts[fontString] then return flags end
	local outline = E.tokens.lightFillText.outline
	if type(flags) == "string" and flags:find("MONOCHROME", 1, true) then return outline .. ", MONOCHROME" end
	return outline
end

function E:ApplyFontShadow(fontString, flags)
	local general = self.db and self.db.general or self.defaults.general
	local outlined = flags and flags ~= ""
	if lightFillTexts[fontString] then
		local halo = self.tokens.lightFillText
		fontString:SetShadowOffset(halo.offset, -halo.offset)
		fontString:SetShadowColor(0, 0, 0, halo.alpha)
	elseif windowTexts[fontString] and not outlined then
		-- Window text keeps its soft shadow, full strength with Text shadow on.
		local soft = self.tokens.windowShadow
		fontString:SetShadowOffset(soft.offset, -soft.offset)
		fontString:SetShadowColor(0, 0, 0, general.fontShadow and 1 or soft.alpha)
	elseif general.fontShadow then
		fontString:SetShadowOffset(1, -1)
		fontString:SetShadowColor(0, 0, 0, outlined and 0.6 or 1)
	elseif not outlined and OnSeeThrough(fontString) then
		local soft = self.tokens.softShadow
		fontString:SetShadowOffset(soft.offset, -soft.offset)
		fontString:SetShadowColor(0, 0, 0, soft.alpha)
	else
		fontString:SetShadowOffset(0, 0)
	end
end

-- Mark a text as sitting on a see-through panel (one deeper than four
-- frames under it, or on a panel made after the text), and apply the
-- shadow at once.
function E:SetSeeThroughText(fontString, on)
	if not fontString then return end
	seeThroughTexts[fontString] = on ~= false or nil
	local _, _, flags = fontString:GetFont()
	self:ApplyFontShadow(fontString, flags)
end

-- General > Accessibility > Large text: one scale for every EldoUI
-- text, 1 to 1.6.
E.defaults.general.textScale = 1
function E:TextScale()
	local general = self.db and self.db.general
	local scale = tonumber(general and general.textScale) or 1
	return math.max(1, math.min(1.6, scale))
end

local function ApplyFont(fontString, header, size, outline, font)
	-- font: an own font path, or a function that returns one (re-read on each
	-- theme refresh); nil follows the theme font.
	local path = font
	if type(path) == "function" then path = path() end
	if type(path) ~= "string" or path == "" then path = header and E.media.fontHeader or E.media.font end
	local general = E.db and E.db.general or E.defaults.general
	local realSize = (size or general.fontSize) * E:TextScale()
	local flags = TextFlags(fontString, outline or general.fontOutline)
	-- An own font the client refuses (a pack that is gone) falls back to the theme.
	if fontString:SetFont(path, realSize, flags) == false and font then
		path = header and E.media.fontHeader or E.media.font
		fontString:SetFont(path, realSize, flags)
	end
	E:ApplyFontShadow(fontString, flags)
	local record = themedFonts[fontString] or {}
	record.path, record.size, record.realSize, record.outline, record.header = path, size, realSize, outline, header
	record.font = font
	themedFonts[fontString] = record
	-- A plain font replaces a name font set before; a name text takes the
	-- name font of what was just set.
	nameFonts[fontString] = nil
	if nameTexts[fontString] and E.SetNameFont then
		E:SetNameFont(fontString, path, realSize, flags, not font)
	end
end

-- Apply the EldoUI font to a FontString. Size defaults to the profile size,
-- the outline to the profile's outline. font (optional) is an own font path
-- or a function returning one; the text still follows the size, outline,
-- shadow and Large text settings.
function E:SetFont(fontString, size, outline, font)
	ApplyFont(fontString, false, size, outline, font)
end

-- Is a bar fill of this color light, so white text on it needs the halo?
-- True when white stays under the token's contrast against it (WCAG
-- luminance, as E:AccentTextColor). A color addon code may not read (a
-- secret one) counts as light, so the text always reads.
function E:IsLightFill(r, g, b)
	if self:IsSecret(r) or self:IsSecret(g) or self:IsSecret(b) then return true end
	if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return true end
	return 1.05 / (Luminance(r, g, b) + 0.05) < self.tokens.lightFillText.contrast
end

-- Mark a text that sits on a light bar fill (on = true) or no longer does:
-- its font is set again at once with the halo or without it, and every
-- later font EldoUI sets on it keeps that.
function E:SetTextOnLightFill(fontString, on)
	if not fontString then return end
	on = on and true or nil
	if lightFillTexts[fontString] == on then return end
	lightFillTexts[fontString] = on
	local record = themedFonts[fontString]
	if record then
		ApplyFont(fontString, record.header, record.size, record.outline, record.font)
	else
		local _, _, flags = fontString:GetFont()
		self:ApplyFontShadow(fontString, flags)
	end
end

-- A text that shows a character's name or what another player typed: the
-- same as E:SetFont, in the name font (E:UseNameFont), so every alphabet
-- keeps its letters.
function E:SetNameTextFont(fontString, size, outline, font)
	if not fontString then return end
	nameTexts[fontString] = true
	ApplyFont(fontString, false, size, outline, font)
end

-- Is this text marked to keep the name font?
function E:UsesNameFont(fontString)
	return nameTexts[fontString] == true
end

-- The header font (window titles) with the theme outline.
function E:SetHeaderFont(fontString, size, outline, font)
	ApplyFont(fontString, true, size, outline, font)
end

-- Window text (the kits' texts, titles and paragraphs, like the options
-- window): the theme font without an outline and with a soft shadow, so it
-- stays crisp at 11 to 14 px. The outline setting stays for HUD text over
-- bars. header = true takes the header font.
function E:SetWindowFont(fontString, size, header, font)
	windowTexts[fontString] = true
	ApplyFont(fontString, header and true or false, size, "", font)
end

-- Is this text window text (E:SetWindowFont)?
function E:IsWindowText(fontString)
	return windowTexts[fontString] == true
end

---------------------------------------------------------------------------
-- Name fonts: player and NPC names in every alphabet
--
-- Many of EldoUI's own fonts have Latin letters only, so a name in Cyrillic,
-- Korean or Chinese would show empty boxes in them. A name font is a font
-- family: Latin letters take the picked font, the other alphabets take the
-- game's own font for them, read from the game's own name font (the game's
-- known font for that alphabet when the client gives none). The game picks
-- the member for the text, so the name itself is never read. When the game
-- refuses a new family, the name font is a copy of one of the game's own
-- font families with the picked font in its Latin slot.
-- One name font per font, size and outline, made once and kept.
--   E:NameFontObject(path, size, flags) -> font object, or nil
--   E:SetNameFont(fontString, path, size, flags) -> true when the family is on
---------------------------------------------------------------------------
do
	local ALPHABETS = { "russian", "korean", "simplifiedchinese", "traditionalchinese" }
	-- The game's font objects that carry a font per alphabet, best first.
	local SOURCES = { "SystemFont_NamePlate", "SystemFont_NamePlateFixed", "GameFontNormal" }
	-- The game's own font for each alphabet, as its name plate font family
	-- lists them (Blizzard_Fonts_Shared): used when the font objects above
	-- give no usable font for an alphabet.
	local GAME_FILES = {
		russian = "Fonts\\FRIZQT___CYR.TTF", korean = "Fonts\\2002.TTF",
		simplifiedchinese = "Fonts\\ARKai_T.ttf", traditionalchinese = "Fonts\\blei00d.TTF",
	}
	-- Game fonts with Latin letters only: never the font of another alphabet.
	local LATIN_ONLY = { ["fonts\\frizqt__.ttf"] = true, ["fonts\\skurri.ttf"] = true, ["fonts\\morpheus.ttf"] = true }
	-- The game's font families a name font is copied from when a family
	-- can't be made: the copy keeps the game's font for every alphabet.
	local COPY_SOURCES = { "SystemFont_Med1", "Tooltip_Med", "SystemFont_NamePlate" }
	local families, made, session, reported = {}, 0, nil, false
	-- How each name font was made: "family", or the game font it copies.
	local madeHow = setmetatable({}, { __mode = "k" })

	local function FileKey(path) return (path:lower():gsub("/", "\\")) end

	-- The game's own font for an alphabet. A font with Latin letters only
	-- (the standard font of a Latin client, or an EldoUI font a game font
	-- object took) would draw that alphabet as empty boxes, so the game's
	-- known font for it takes its place.
	local function ClientFont(alphabet)
		for _, name in ipairs(SOURCES) do
			local object = _G[name]
			local getMember = type(object) == "table" and object.GetFontObjectForAlphabet
			if getMember then
				local ok, member = pcall(getMember, object, alphabet)
				if ok and type(member) == "table" and member.GetFont then
					local okFont, path = pcall(member.GetFont, member)
					if okFont and type(path) == "string" and path ~= "" then
						local key = FileKey(path)
						if not LATIN_ONLY[key] and not key:find("^interface\\addons\\") then return path end
					end
				end
			end
		end
		return GAME_FILES[alphabet] or STANDARD_TEXT_FONT
	end
	-- The font a name font uses for an alphabet (exposed for inspection).
	function E:NameFontAlphabetFile(alphabet) return ClientFont(alphabet) end

	-- A font object name no earlier font of this game session has: the
	-- count starts again after a reload, so each load adds its own mark.
	local function NextName()
		if not session then
			local now = type(GetTime) == "function" and tonumber(GetTime()) or 0
			session = math.floor(now * 1000) % 2147483647
		end
		local name
		repeat
			made = made + 1
			name = ("EldoUI_NameFont%d_%d"):format(session, made)
		until rawget(_G, name) == nil
		return name
	end

	local function Report(why)
		if reported then return end
		reported = true
		E:Debug("Name font: no font family,", tostring(why))
	end

	-- The name font as a font family: the picked font for Latin letters,
	-- the game's own font for each other alphabet. A refused family is
	-- tried once more under a new name.
	local function MadeFamily(path, size, flags)
		if type(CreateFontFamily) ~= "function" then return nil end
		local members = { { alphabet = "roman", file = path, height = size, flags = flags } }
		for _, alphabet in ipairs(ALPHABETS) do
			members[#members + 1] = { alphabet = alphabet, file = ClientFont(alphabet), height = size, flags = flags }
		end
		local why
		for _ = 1, 2 do
			local ok, object = pcall(CreateFontFamily, NextName(), members)
			if ok and type(object) == "table" then
				madeHow[object] = "family"
				return object
			end
			why = object
		end
		Report(why)
		return nil
	end

	-- The same through a copy of one of the game's own font families: the
	-- copy keeps the game's font for every alphabet, and on a Latin client
	-- SetFont puts the picked font in its Latin slot, as the game's chat
	-- windows take a new font size. A client in another alphabet keeps the
	-- game's font, so its own letters never turn into boxes.
	local function CopiedFamily(path, size, flags)
		if type(CreateFont) ~= "function" then return nil end
		for _, name in ipairs(COPY_SOURCES) do
			local source = _G[name]
			if type(source) == "table" and source.GetFont then
				local ok, font = pcall(CreateFont, NextName())
				if not (ok and type(font) == "table" and font.CopyFontObject and pcall(font.CopyFontObject, font, source)) then
					return nil
				end
				if not E.LatinNameClient or E.LatinNameClient() then
					local okSet, set = pcall(font.SetFont, font, path, size, flags)
					if not okSet or set == false then return nil end
				end
				pcall(font.SetTextColor, font, 1, 1, 1, 1)
				pcall(font.SetShadowOffset, font, 0, 0)
				madeHow[font] = name
				return font
			end
		end
		return nil
	end

	-- How a name font was made: "family" (CreateFontFamily), the name of
	-- the game font family it copies, or nil for any other font.
	function E:NameFontSource(font) return font and madeHow[font] end

	function E:NameFontObject(path, size, flags)
		if type(path) ~= "string" or path == "" then return nil end
		size = math.floor((tonumber(size) or 12) * 10 + 0.5) / 10
		flags = flags or ""
		local key = path:lower() .. "|" .. size .. "|" .. flags
		local font = families[key]
		if font ~= nil then return font or nil end
		families[key] = MadeFamily(path, size, flags) or CopiedFamily(path, size, flags) or false
		return families[key] or nil
	end

	-- theme: true when `path` is the theme font, so a theme refresh draws
	-- the name in the new theme font (read from the path when not given).
	function E:SetNameFont(fontString, path, size, flags, theme)
		local font = fontString and self:NameFontObject(path, size, flags)
		if not font then return false end
		fontString:SetFontObject(font)
		fontString:SetShadowOffset(0, 0)
		-- A name on a light fill keeps the halo's shadow.
		if lightFillTexts[fontString] then self:ApplyFontShadow(fontString, flags) end
		if theme == nil then theme = SamePath(path, self.media.font) end
		nameFonts[fontString] = { font = font, path = path, size = size, flags = flags, theme = theme and true or false }
		return true
	end

	-- Mark a text that draws a character's name (unit and group frame
	-- names): from now on every font EldoUI sets on it is the name font,
	-- so names in other alphabets keep their letters. on = false unmarks.
	function E:UseNameFont(fontString, on)
		if not fontString then return end
		nameTexts[fontString] = on ~= false or nil
		local record = themedFonts[fontString]
		if on ~= false and record then
			self:SetNameFont(fontString, record.path, record.realSize, TextFlags(fontString, record.outline or (self.db and self.db.general.fontOutline)), not record.font)
		end
	end

	function E:IsNameFontText(fontString)
		return nameFonts[fontString] ~= nil
	end

	-- Chat lines, message windows and the bubble font: a chat frame or a
	-- font object takes the name font of the chat font, so a message in
	-- another alphabet keeps its letters; the plain font when no family can
	-- be made. Not recorded: the chat modules set it again on every look
	-- change. True when a font is on.
	function E:SetMessageFont(target, path, size, flags)
		if not target then return false end
		local family = self:NameFontObject(path, size, flags)
		if family then
			local isFont = target.GetObjectType and target:GetObjectType() == "Font"
			local set = isFont and target.CopyFontObject or target.SetFontObject
			if set and pcall(set, target, family) then return true end
		end
		return target:SetFont(path, size, flags) and true or false
	end
end

-- Re-apply the theme font to every text set through E:SetFont /
-- E:SetHeaderFont that still shows what EldoUI put on it. A name text
-- that still shows its name font gets the name font again (in the new
-- theme font when it followed the theme), so it keeps every alphabet.
function E:RefreshThemedFonts()
	for fontString, record in pairs(themedFonts) do
		if not nameFonts[fontString] then
			local ok, path, size = pcall(fontString.GetFont, fontString)
			if ok and (path == nil or (SamePath(path, record.path) and (size == nil or math.abs(size - record.realSize) < 0.5))) then
				ApplyFont(fontString, record.header, record.size, record.outline, record.font)
			end
		end
	end
	local names = {}
	for fontString, named in pairs(nameFonts) do names[fontString] = named end
	for fontString, named in pairs(names) do
		local ok, object = pcall(fontString.GetFontObject, fontString)
		if ok and object == named.font then
			local record = themedFonts[fontString]
			if nameTexts[fontString] and record then
				-- A marked text follows the profile's size and outline too.
				ApplyFont(fontString, record.header, record.size, record.outline, record.font)
			else
				self:SetNameFont(fontString, named.theme and self.media.font or named.path, named.size, named.flags, named.theme)
			end
		end
	end
end

-- A string for the look that is baked into frames when they are built
-- (aura icons): it changes whenever the art style or its variant, accent,
-- panel colors, font, outline or bar texture do.
function E:ThemeKey()
	local m = self.media
	local general = self.db and self.db.general or {}
	local function C(c) return ("%.3f,%.3f,%.3f,%.3f"):format(c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1) end
	return table.concat({ tostring(self.ArtStyle and self.db and self:ArtStyle() or ""), C(m.accentColor), C(m.backdropColor),
		C(m.borderColor), tostring(m.font), tostring(m.fontHeader), tostring(general.fontOutline), tostring(general.fontShadow), tostring(m.statusbar),
		tostring(self.Skins and self.Skins.VariantKey and self.db and self.Skins.VariantKey(self:ArtStyle()) or "") }, "|")
end

function E:CreateText(parent, size, justify, layer)
	local text = parent:CreateFontString(nil, layer or "OVERLAY")
	self:SetFont(text, size)
	text:SetJustifyH(justify or "CENTER")
	text:SetWordWrap(false)
	return text
end

-- The border of E:SetTemplate boxes and pixel-edged panels: one screen
-- pixel, two under the high contrast art style.
function E:EdgeSize()
	local pixel = self.pixel or 1
	if self.db and self.ArtStyle and self:ArtStyle() == "Contrast" then return pixel * 2 end
	return pixel
end

-- Dark flat background with a 1-pixel black border, the core EldoUI look.
-- Used for small things (slots, bars, buttons); they stay pixel-sharp in
-- every art style.
-- The color of a see-through box: the panel color, or under a skin with
-- art its see-through color (its panel darkened to the flat panel's
-- luminance), so muted text keeps its contrast over a bright world.
function E:SeeThroughColor()
	local skins = self.Skins
	local palette = skins and skins.PaletteOf and self.db and self.ArtStyle and skins.PaletteOf(self:ArtStyle())
	local c = palette and palette.seeThrough
	if c then return c[1], c[2], c[3] end
	local back = self.media.backdropColor
	return back[1], back[2], back[3]
end

function E:SetTemplate(frame, transparent)
	if droppedBoxes[frame] then return end
	self:AddBackdrop(frame)
	local edge = self:EdgeSize()
	-- Applying a backdrop measures the frame. A box whose size is secret
	-- right now keeps the edges it has and still takes the new colors; a
	-- box that has none yet gets them once its size reads again.
	if not frame.backdropInfo and self:SizeIsSecret(frame) then
		WaitForSize(frame, transparent)
		return
	end
	waitingBoxes[frame] = nil
	if not (frame.backdropInfo and self:SizeIsSecret(frame)) then
		frame:SetBackdrop({
			bgFile = self.media.flat,
			edgeFile = self.media.flat,
			edgeSize = edge,
		})
		pixelEdges[frame] = edge
	end
	local r, g, b, a = unpack(self.media.backdropColor)
	-- High contrast keeps every box opaque.
	if transparent and a < 1 then
		a = self:SeeThroughAlpha(a)
		r, g, b = self:SeeThroughColor()
	end
	frame:SetBackdropColor(r, g, b, a)
	local br, bg, bb, ba = unpack(self.media.borderColor)
	frame:SetBackdropBorderColor(br, bg, bb, ba)
	local record = themedBoxes[frame] or { bg = {}, border = {} }
	record.transparent = transparent and true or false
	record.bg[1], record.bg[2], record.bg[3], record.bg[4] = r, g, b, a
	record.border[1], record.border[2], record.border[3], record.border[4] = br, bg, bb, ba or 1
	themedBoxes[frame] = record
end

-- A color the game keeps secret is never compared: that box keeps it, and
-- its module puts its own color back.
local function SameColor(c, r, g, b, a)
	if E:IsSecret(r) or E:IsSecret(g) or E:IsSecret(b) or E:IsSecret(a) then return false end
	if type(r) ~= "number" then return false end
	return math.abs(c[1] - r) < 0.005 and math.abs(c[2] - (g or 0)) < 0.005 and math.abs(c[3] - (b or 0)) < 0.005
		and math.abs((c[4] or 1) - (a or 1)) < 0.005
end

-- A panel's background opacity (E:PanelAlpha), remembered so a theme
-- refresh keeps it.
function E:SetTemplateAlpha(frame, alpha)
	local record = themedBoxes[frame]
	if not record then return end
	record.panel = true
	record.bg[4] = alpha
	frame:SetBackdropColor(record.bg[1], record.bg[2], record.bg[3], alpha)
end

-- Re-color every E:SetTemplate box with the palette in effect. A color
-- the box's module set itself (quality, hover, a highlight) is kept; the
-- module re-applies it in OnProfileChanged.
function E:RefreshTemplates()
	local backdrop, border = self.media.backdropColor, self.media.borderColor
	for frame, record in pairs(themedBoxes) do
		if frame.GetBackdropColor then
			local okBg, r, g, b, a = pcall(frame.GetBackdropColor, frame)
			if okBg and SameColor(record.bg, r, g, b, a) then
				local alpha = (record.transparent and backdrop[4] < 1) and E:SeeThroughAlpha(backdrop[4]) or backdrop[4]
				if record.fixedAlpha then
					alpha = record.fixedAlpha
				elseif record.panel then
					alpha = E:PanelAlpha(record.transparent)
				end
				local fr, fg, fb = backdrop[1], backdrop[2], backdrop[3]
				if record.transparent and alpha < 1 then fr, fg, fb = E:SeeThroughColor() end
				frame:SetBackdropColor(fr, fg, fb, alpha)
				record.bg[1], record.bg[2], record.bg[3], record.bg[4] = fr, fg, fb, alpha
			end
			local okBorder, br, bg, bb, ba = pcall(frame.GetBackdropBorderColor, frame)
			if okBorder and SameColor(record.border, br, bg, bb, ba) then
				-- A window panel keeps the light window edge (E:SetWindowEdge).
				local edge = record.windowEdge and E.tokens.edge.window or border
				frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1)
				record.border[1], record.border[2], record.border[3], record.border[4] = edge[1], edge[2], edge[3], edge[4] or 1
			end
		end
	end
end

-- E.pixel changed (UI scale or screen size, Core/Scale.lua): every 1-pixel
-- border made with E:SetTemplate or a pixel-edged panel gets the new size.
-- Colors stay as they are; a box whose border a module set to another
-- size since is left alone.
function E:RefreshPixelEdges()
	local pixel = self:EdgeSize()
	for frame, size in pairs(pixelEdges) do
		local info = frame.GetBackdrop and frame:GetBackdrop()
		if type(info) == "table" and info.edgeFile == self.media.flat and math.abs((tonumber(info.edgeSize) or 0) - size) < 0.00001 then
			-- Applying a backdrop measures the frame: a frame whose size is
			-- secret right now, or reads no number (a pooled row laid out
			-- nowhere), keeps its edge until the next refresh.
			if not self:SizeIsSecret(frame) and type(frame:GetWidth()) == "number" and type(frame:GetHeight()) == "number" then
				if math.abs(size - pixel) > 0.00001 then
					local okBg, r, g, b, a = pcall(frame.GetBackdropColor, frame)
					local okBorder, br, bg, bb, ba = pcall(frame.GetBackdropBorderColor, frame)
					local copy = {}
					for key, value in pairs(info) do copy[key] = type(value) == "table" and CopyTable(value) or value end
					copy.edgeSize = pixel
					frame:SetBackdrop(copy)
					if okBg and type(r) == "number" then frame:SetBackdropColor(r, g, b, a) end
					if okBorder and type(br) == "number" then frame:SetBackdropBorderColor(br, bg, bb, ba) end
				end
				pixelEdges[frame] = pixel
			end
		else
			pixelEdges[frame] = nil
		end
	end
end

-- The edge size E:RefreshPixelEdges keeps in step (read-only).
function E:GetPixelEdge(frame)
	return pixelEdges[frame]
end

---------------------------------------------------------------------------
-- Art styles: windows and panels (bags, loot, chat, mail, tooltips, config)
-- follow the chosen style; E:SetPanelTemplate remembers each panel so a
-- style change re-skins them all at once.
--   Modern   flat dark panel, 1-pixel border, accent line
--   Blizzard dark panel with the game's rounded tooltip border
--   Classic  stone background with a gold-tinted border
--   Forever  warm dark panel inside the bronze frame line of the WoW:
--            Forever HUD, cut at runtime from the client's
--            own atlas. Falls back to Blizzard when the atlas is missing.
---------------------------------------------------------------------------
E.artStyleOrder = { "Modern", "Blizzard", "Classic", "Forever", "Contrast" }
E.artStyleInfo = {
	Modern = { title = "Modern (flat)", desc = "Flat dark panels with a 1-pixel border and an accent line." },
	Blizzard = { title = "Blizzard", desc = "Dark panels with the game's rounded tooltip border." },
	Classic = { title = "Classic", desc = "Stone background with a gold-tinted border." },
	Forever = { title = "WoW Forever", short = "Warm dark panels in the bronze frame line of the WoW: Forever bars.", desc = "Warm dark panels in the bronze frame line of the WoW: Forever action bars and micro menu, drawn from the game's own art. The accent turns Sand when it was still the default blue." },
	Contrast = { title = "High contrast", desc = "Black panels with bright 2-pixel borders and no transparency, for low vision (Accessibility page)." },
}

-- Colors that change with the art style. E.media.backdropColor and
-- E.media.borderColor are updated in place, so E:SetTemplate boxes (slots,
-- buttons, bars) pick up the warm Forever tones too.
local PALETTE = {
	-- The starting values of E.media: one literal, not two.
	default = { backdrop = { unpack(E.media.backdropColor) }, border = { unpack(E.media.borderColor) } },
	Forever = { backdrop = { 0.075, 0.063, 0.052, 0.86 }, border = { 0.29, 0.21, 0.13, 1 } },
	-- High contrast: black, opaque, with white borders.
	Contrast = E.tokens.palette.contrast,
}

---------------------------------------------------------------------------
-- The Forever frame line. The atlas is the filled square behind the
-- Forever action bar and micro menu. EldoUI measures it at runtime with
-- C_Texture.GetAtlasInfo (its own slice margins when the client gives
-- them, otherwise FOREVER_CORNER of each side) and cuts it into a hollow
-- ring: four corners at the art's own size and four stretched edges. The
-- center is never drawn; the panel's own backdrop shows through.
-- Frames too small for the corners (bars, tabs, strips) get only the four
-- edges, cut from the art's outer band and drawn FOREVER_THIN units thick.
-- Nothing is copied from another addon; no texture file ships with EldoUI.
---------------------------------------------------------------------------
local FOREVER_ATLAS = "UI-HUD-ActionBar-Frame"
local FOREVER_CORNER = 0.26  -- share of each side that holds a corner (no slice data)
local FOREVER_OUTSET = 0.4   -- share of the frame line that sits outside the frame
local FOREVER_THIN = 3       -- edge thickness on thin frames, UI units
local FOREVER_BAND = 0.45    -- share of the margin sampled for thin edges

local foreverArt -- nil = not probed yet, false = missing on this client
local foreverWarned = false
local foreverSelection = {}
local atlasSecret, atlasEqual = issecretvalue, rawequal
local atlasNamespace = C_Texture
local atlasRead = atlasNamespace and atlasNamespace.GetAtlasInfo
local atlasMeta = type(atlasNamespace) == "table" and getmetatable(atlasNamespace) or nil
local atlasIndex = type(atlasMeta) == "table" and rawget(atlasMeta, "__index") or nil
local atlasDirect = type(atlasNamespace) == "table" and rawget(atlasNamespace, "GetAtlasInfo") or nil
local atlasGlobal = rawget(_G, "C_Texture")
local function AtlasSame(value, expected) return not (atlasSecret and atlasSecret(value)) and atlasEqual(value, expected) end
local function AtlasSource()
	return AtlasSame(rawget(_G, "C_Texture"), atlasGlobal) and type(atlasNamespace) == "table"
		and AtlasSame(getmetatable(atlasNamespace), atlasMeta) and AtlasSame(rawget(atlasNamespace, "GetAtlasInfo"), atlasDirect)
		and (type(atlasMeta) ~= "table" or AtlasSame(rawget(atlasMeta, "__index"), atlasIndex))
end

local function Number(value)
	if type(value) ~= "number" or (issecretvalue and issecretvalue(value)) then return nil end
	return value
end

-- The measured Forever art, or nil when this client has no such atlas.
-- refresh: probe again (tests, or after the client loaded more art).
function E:ForeverArt(refresh)
	if refresh then foreverArt = nil;foreverSelection = {} end
	if foreverArt == nil then
		foreverArt = false;foreverSelection = {}
		local request = foreverSelection
		atlasNamespace, atlasGlobal = C_Texture, rawget(_G, "C_Texture")
		atlasRead = not (atlasSecret and atlasSecret(atlasNamespace)) and type(atlasNamespace) == "table" and atlasNamespace.GetAtlasInfo or nil
		atlasMeta = type(atlasNamespace) == "table" and getmetatable(atlasNamespace) or nil
		atlasIndex = type(atlasMeta) == "table" and rawget(atlasMeta, "__index") or nil
		atlasDirect = type(atlasNamespace) == "table" and rawget(atlasNamespace, "GetAtlasInfo") or nil
		local get = AtlasSource() and atlasRead
		local ok, info = false, nil
		if not (atlasSecret and atlasSecret(get)) and type(get) == "function" then ok, info = pcall(get, FOREVER_ATLAS) end
		if not atlasEqual(foreverSelection, request) or not AtlasSource() then return foreverArt or nil end
		if ok and not (atlasSecret and atlasSecret(info)) and type(info) == "table" and getmetatable(info) == nil then
			local file = info.file or info.filename
			local w, h = Number(info.width), Number(info.height)
			local l, r = Number(info.leftTexCoord), Number(info.rightTexCoord)
			local t, b = Number(info.topTexCoord), Number(info.bottomTexCoord)
			if not (atlasSecret and atlasSecret(file)) and (type(file) == "string" or Number(file)) and file ~= "" and file ~= 0 and w and h and w >= 8 and h >= 8
				and l and r and t and b and r > l and b > t then
				if (atlasSecret and atlasSecret(info.sliceData)) or (type(info.sliceData) ~= "nil" and (type(info.sliceData) ~= "table" or getmetatable(info.sliceData) ~= nil)) then return nil end
				local slice = info.sliceData or {}
				for _, field in ipairs({ "marginLeft", "marginRight", "marginTop", "marginBottom" }) do
					if atlasSecret and atlasSecret(rawget(slice, field)) then return nil end
				end
				local function Margin(value, side)
					value = Number(value)
					if value and value >= 2 and value < side / 2 then return value end
					return math.max(2, math.floor(side * FOREVER_CORNER + 0.5))
				end
				foreverArt = {
					file = file, w = w, h = h, l = l, r = r, t = t, b = b,
					left = Margin(slice.marginLeft, w), right = Margin(slice.marginRight, w),
					top = Margin(slice.marginTop, h), bottom = Margin(slice.marginBottom, h),
				}
				foreverSelection = {}
			end
		end
	end
	return foreverArt or nil
end

do
	local owner, consumer, binding
	local original = E.ForeverArt
	local function Capture(used)
		local token, art, fields = foreverSelection, foreverArt, {}
		if type(art) == "table" then for _, key in ipairs({ "file", "w", "h", "l", "r", "t", "b", "left", "right", "top", "bottom" }) do fields[key] = rawget(art, key) end end
		return function()
			if not used then return AtlasSame(rawget(E, "ForeverArt"), original) end
			if not atlasEqual(token, foreverSelection) or not AtlasSame(foreverArt, art) or not AtlasSame(rawget(E, "ForeverArt"), original) or not AtlasSource() then return false end
			if type(art) == "table" then for key, value in pairs(fields) do if not AtlasSame(rawget(art, key), value) then return false end end end
			return true
		end
	end
	function E:BindSkinSelectionRead(source, accept)
		if binding or not atlasEqual(self, E) or not AtlasSame(source, rawget(E, "Skins")) or type(source) ~= "table" or type(accept) ~= "function" then return false end
		if owner then return atlasEqual(owner, source) and atlasEqual(consumer, accept) end
		binding = true
		local ok = pcall(accept, Capture)
		binding = nil
		if not ok then return false end
		owner, consumer = source, accept
		return true
	end
end

-- The art style in effect: the profile's choice, with WoW Forever turning
-- into Blizzard on a client without the Forever art.
function E:ArtStyle(style)
	style = style or (self.db and self.db.general.artStyle)
	if not self.artStyles[style] then return "Modern" end
	if style == "Forever" and not self:ForeverArt() then
		if not foreverWarned and self.errors and self.errors.Add then
			foreverWarned = true
			self.errors:Add("warning", ("EldoUI: the atlas %s is missing on this client, so the WoW Forever skin uses the Blizzard look."):format(FOREVER_ATLAS))
		end
		return "Blizzard"
	end
	return style
end

-- Values for an art style dropdown. WoW Forever is listed on the Forever
-- client (or when a profile already uses it).
function E:ArtStyleValues(extra)
	local values = {}
	for _, key in ipairs(self.artStyleOrder) do
		if key ~= "Forever" or self:ForeverArt() or (self.db and self.db.general.artStyle == "Forever") then
			values[key] = self.artStyleInfo[key].title
		end
	end
	for key, title in pairs(extra or {}) do values[key] = title end
	return values
end

local rings = setmetatable({}, { __mode = "k" })       -- frame -> { pieces, thin }
local ringHooked = setmetatable({}, { __mode = "k" })
local PIECES = { "tl", "t", "tr", "l", "r", "bl", "b", "br" }

local function U(art, x) return art.l + (art.r - art.l) * x / art.w end
local function V(art, y) return art.t + (art.b - art.t) * y / art.h end

local function Piece(ring, frame, key, art)
	local tex = ring[key]
	if not tex then
		tex = frame:CreateTexture(nil, "ARTWORK", nil, 7)
		if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
		if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
		ring[key] = tex
	end
	tex:SetTexture(art.file)
	tex:SetVertexColor(1, 1, 1, 1)
	tex:ClearAllPoints()
	return tex
end

local function LayoutRing(frame)
	local ring = rings[frame]
	local art = foreverArt
	if not (ring and ring.shown and art) then return end
	local width, height = frame:GetSize()
	width, height = Number(width) or 0, Number(height) or 0
	local L, R, T, B = art.left, art.right, art.top, art.bottom
	local thin = width < L + R + 4 or height < T + B + 4
	for _, key in ipairs(PIECES) do Piece(ring, frame, key, art) end
	if thin then
		local o, s = math.floor(FOREVER_THIN / 2), FOREVER_THIN
		local bandT, bandB = math.max(1, T * FOREVER_BAND), math.max(1, B * FOREVER_BAND)
		local bandL, bandR = math.max(1, L * FOREVER_BAND), math.max(1, R * FOREVER_BAND)
		ring.tl:Hide(); ring.tr:Hide(); ring.bl:Hide(); ring.br:Hide()
		ring.t:SetPoint("TOPLEFT", frame, "TOPLEFT", -o, o)
		ring.t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", o, o)
		ring.t:SetHeight(s)
		ring.t:SetTexCoord(U(art, L), U(art, art.w - R), V(art, 0), V(art, bandT))
		ring.b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -o, -o)
		ring.b:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", o, -o)
		ring.b:SetHeight(s)
		ring.b:SetTexCoord(U(art, L), U(art, art.w - R), V(art, art.h - bandB), V(art, art.h))
		ring.l:SetPoint("TOPLEFT", ring.t, "BOTTOMLEFT")
		ring.l:SetPoint("BOTTOMLEFT", ring.b, "TOPLEFT")
		ring.l:SetWidth(s)
		ring.l:SetTexCoord(U(art, 0), U(art, bandL), V(art, T), V(art, art.h - B))
		ring.r:SetPoint("TOPRIGHT", ring.t, "BOTTOMRIGHT")
		ring.r:SetPoint("BOTTOMRIGHT", ring.b, "TOPRIGHT")
		ring.r:SetWidth(s)
		ring.r:SetTexCoord(U(art, art.w - bandR), U(art, art.w), V(art, T), V(art, art.h - B))
	else
		local oL, oR = math.floor(L * FOREVER_OUTSET + 0.5), math.floor(R * FOREVER_OUTSET + 0.5)
		local oT, oB = math.floor(T * FOREVER_OUTSET + 0.5), math.floor(B * FOREVER_OUTSET + 0.5)
		ring.tl:SetPoint("TOPLEFT", frame, "TOPLEFT", -oL, oT)
		ring.tl:SetSize(L, T)
		ring.tl:SetTexCoord(U(art, 0), U(art, L), V(art, 0), V(art, T))
		ring.tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT", oR, oT)
		ring.tr:SetSize(R, T)
		ring.tr:SetTexCoord(U(art, art.w - R), U(art, art.w), V(art, 0), V(art, T))
		ring.bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -oL, -oB)
		ring.bl:SetSize(L, B)
		ring.bl:SetTexCoord(U(art, 0), U(art, L), V(art, art.h - B), V(art, art.h))
		ring.br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", oR, -oB)
		ring.br:SetSize(R, B)
		ring.br:SetTexCoord(U(art, art.w - R), U(art, art.w), V(art, art.h - B), V(art, art.h))
		ring.t:SetPoint("TOPLEFT", ring.tl, "TOPRIGHT")
		ring.t:SetPoint("BOTTOMRIGHT", ring.tr, "BOTTOMLEFT")
		ring.t:SetTexCoord(U(art, L), U(art, art.w - R), V(art, 0), V(art, T))
		ring.b:SetPoint("TOPLEFT", ring.bl, "TOPRIGHT")
		ring.b:SetPoint("BOTTOMRIGHT", ring.br, "BOTTOMLEFT")
		ring.b:SetTexCoord(U(art, L), U(art, art.w - R), V(art, art.h - B), V(art, art.h))
		ring.l:SetPoint("TOPLEFT", ring.tl, "BOTTOMLEFT")
		ring.l:SetPoint("BOTTOMRIGHT", ring.bl, "TOPRIGHT")
		ring.l:SetTexCoord(U(art, 0), U(art, L), V(art, T), V(art, art.h - B))
		ring.r:SetPoint("TOPLEFT", ring.tr, "BOTTOMLEFT")
		ring.r:SetPoint("BOTTOMRIGHT", ring.br, "TOPRIGHT")
		ring.r:SetTexCoord(U(art, art.w - R), U(art, art.w), V(art, T), V(art, art.h - B))
		ring.tl:Show(); ring.tr:Show(); ring.bl:Show(); ring.br:Show()
	end
	ring.t:Show(); ring.b:Show(); ring.l:Show(); ring.r:Show()
	ring.thin = thin
end

local function ShowRing(frame)
	if not (frame and frame.CreateTexture and E:ForeverArt()) then return false end
	local ring = rings[frame]
	if not ring then
		ring = {}
		rings[frame] = ring
	end
	ring.shown = true
	if not ringHooked[frame] and frame.HookScript then
		ringHooked[frame] = true
		frame:HookScript("OnSizeChanged", LayoutRing)
	end
	LayoutRing(frame)
	return true
end

local function HideRing(frame)
	local ring = frame and rings[frame]
	if not ring then return end
	ring.shown = false
	for _, key in ipairs(PIECES) do
		if ring[key] then ring[key]:Hide() end
	end
end

-- Remove the WoW Forever frame line from a frame (the native skin painters
-- call it before they draw their own frame).
function E:HideStyleRing(frame)
	HideRing(frame)
end

-- Read-only: the frame line's state on a frame (tests, plugins).
-- Returns "full", "thin" or nil.
function E:StyleEdgeState(frame)
	local ring = frame and rings[frame]
	if not (ring and ring.shown) then return nil end
	return ring.thin and "thin" or "full"
end

-- The art style's frame line around a frame that is not a panel: info
-- bars, XP bars, meter windows, strips. Shows only under WoW Forever (the
-- other styles keep the frame's own 1-pixel border). show = false removes
-- it again. Remembered, so a later art style change updates the frame.
local edgeFrames = setmetatable({}, { __mode = "k" })
function E:SetStyleEdge(frame, show)
	if not frame then return end
	edgeFrames[frame] = show ~= false
	local style = self:ArtStyle()
	if edgeFrames[frame] and style == "Forever" then
		ShowRing(frame)
		return
	end
	HideRing(frame)
	-- A native skin draws its own thin edge (Core/Skins.lua).
	local skins = self.Skins
	if skins and not (edgeFrames[frame] and skins.ShowEdge(frame, style)) and not self.panels[frame] then skins.Release(frame) end
end

-- Windows (E:SetWindowEdge) draw the light window edge under Modern; HUD
-- frames and small boxes keep the black edge (tokens.edge.hud).
local windowEdges = setmetatable({}, { __mode = "k" })

E.artStyles = {
	Modern = function(frame, transparent)
		HideRing(frame)
		E:SetTemplate(frame, transparent)
		E:SetTemplateAlpha(frame, E:PanelAlpha(transparent))
		local record = themedBoxes[frame]
		if record then record.windowEdge = windowEdges[frame] or nil end
		if windowEdges[frame] then
			local edge = E.tokens.edge.window
			frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4])
			if record then record.border[1], record.border[2], record.border[3], record.border[4] = edge[1], edge[2], edge[3], edge[4] end
		end
		E:UpdateShadow(frame, E.db.general.shadows)
	end,
	Blizzard = function(frame, transparent)
		HideRing(frame)
		frame:SetBackdrop({
			bgFile = E.media.flat,
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = false, edgeSize = 14,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		-- The small-box palette, so panels and boxes match.
		local bg, edge = PALETTE.default.backdrop, E.tokens.edge.blizzard
		local r, g, b = E:TintBackdrop(bg[1], bg[2], bg[3], nil, "Blizzard")
		frame:SetBackdropColor(r, g, b, E:PanelAlpha(transparent))
		frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4])
	end,
	Classic = function(frame, transparent)
		HideRing(frame)
		frame:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 32, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		frame:SetBackdropColor(1, 1, 1, transparent and 0.7 or 1)
		local edge = E.tokens.edge.classic
		frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4])
	end,
	Forever = function(frame, transparent)
		if not E:ForeverArt() then return E.artStyles.Blizzard(frame, transparent) end
		local p = PALETTE.Forever
		frame:SetBackdrop({ bgFile = E.media.flat, edgeFile = E.media.flat, edgeSize = E.pixel })
		pixelEdges[frame] = E.pixel
		local r, g, b = E:TintBackdrop(p.backdrop[1], p.backdrop[2], p.backdrop[3], nil, "Forever")
		frame:SetBackdropColor(r, g, b, E:PanelAlpha(transparent))
		frame:SetBackdropBorderColor(0, 0, 0, 1)
		ShowRing(frame)
	end,
	Contrast = function(frame)
		HideRing(frame)
		local p = PALETTE.Contrast
		local edge = E:EdgeSize()
		frame:SetBackdrop({ bgFile = E.media.flat, edgeFile = E.media.flat, edgeSize = edge })
		pixelEdges[frame] = edge
		frame:SetBackdropColor(p.backdrop[1], p.backdrop[2], p.backdrop[3], 1)
		frame:SetBackdropBorderColor(p.border[1], p.border[2], p.border[3], 1)
	end,
}
E.panels = setmetatable({}, { __mode = "k" })
local panelAlphas = setmetatable({}, { __mode = "k" }) -- frame -> its own background opacity

-- alpha (optional): the panel's own background opacity (a module's
-- "Background opacity" option), kept through art style and theme changes;
-- false goes back to General > Panel opacity. Every style keeps
-- its own background color: the Classic stone stays untinted.
function E:SetPanelTemplate(frame, transparent, alpha)
	self:AddBackdrop(frame)
	self.panels[frame] = transparent and "transparent" or true
	if alpha ~= nil then panelAlphas[frame] = alpha or nil end
	local style = self.artStyles[self:ArtStyle()]
	-- Shadows belong to the flat skins; the others bring their own edge.
	if not self:SkinAllowsShadows() then self:UpdateShadow(frame, false) end
	-- A native skin's pieces go when another painter takes over (Core/Skins.lua).
	if self.Skins then self.Skins.Release(frame) end
	style(frame, transparent)
	-- High contrast stays opaque whatever the panel asks for. A window
	-- (E:SetWindowEdge) is opaque too, so no window shows another through
	-- it; General > Panel opacity is for the panels on the screen.
	local own = style ~= self.artStyles.Contrast and panelAlphas[frame] or nil
	if own == nil and windowEdges[frame] and not transparent then own = 1 end
	local record = themedBoxes[frame]
	if record then record.fixedAlpha = style == self.artStyles.Modern and own or nil end
	if own then
		if style == self.artStyles.Modern then
			self:SetTemplateAlpha(frame, own)
		else
			-- type() reads a secret color too, and the setter takes it back.
			local r, g, b = frame:GetBackdropColor()
			if type(r) == "number" then frame:SetBackdropColor(r, g, b, own) end
		end
	end
	-- A material skin keeps the opacity on its fill texture.
	if self.Skins then self.Skins.SyncAlpha(frame) end
end

-- Does the skin (default: the one in effect) draw frame shadows? Modern and
-- Minimal Modern do; the skins with a frame of their own do not.
function E:SkinAllowsShadows(style)
	style = style or (self.db and self:ArtStyle() or "Modern")
	if style == "Modern" then return true end
	local m = self.SkinManifest and self:SkinManifest(style)
	return m ~= nil and m.shadows == true
end

-- Mark a panel as a window (EldoUI's own windows and dialogs, the kit
-- shells): under the Modern art style its 1-pixel edge is the light window
-- edge (tokens.edge.window) instead of black. The other art styles keep
-- their own edges. on = false gives the panel the black edge again.
function E:SetWindowEdge(frame, on)
	if not frame then return end
	windowEdges[frame] = on ~= false or nil
	local kind = self.panels[frame]
	if kind then self:SetPanelTemplate(frame, kind == "transparent") end
end

-- Does the panel draw the window edge (E:SetWindowEdge)?
function E:IsWindowEdge(frame)
	return windowEdges[frame] == true
end

-- The opacity a panel keeps of its own (E:SetPanelTemplate), or nil.
function E:PanelOwnAlpha(frame)
	return panelAlphas[frame]
end

---------------------------------------------------------------------------
-- Panel tint (General > Textures): a named hue from tokens.palette.tint
-- mixed into the panel background of the Modern, Blizzard and WoW Forever
-- art styles, and into the small boxes that share their palette. Classic
-- keeps its stone and High contrast its black.
---------------------------------------------------------------------------
E.defaults.general.panelTint = "none"
E.panelTintOrder = { "none", "midnight", "pine", "wine", "dusk" }
E.panelTintNames = { none = "None", midnight = "Midnight", pine = "Pine", wine = "Wine", dusk = "Dusk" }

-- Does the tint apply under this art style (default: the one in effect)?
function E:PanelTintApplies(style)
	style = style or (self.db and self:ArtStyle() or "Modern")
	if style == "Classic" or style == "Contrast" then return false end
	-- Native skins: only the flat ones (a material keeps its own color).
	if self.Skins and self.Skins.IsNative(style) then return self:SkinManifest(style).tint == true end
	return true
end

-- The tint's hue, or nil for None, an unknown name or a style without tints.
function E:PanelTintColor(name, style)
	if name == nil then name = self.db and self.db.general.panelTint end
	if type(name) ~= "string" or name == "none" or name == "strength" or not self:PanelTintApplies(style) then return nil end
	local hue = self.tokens.palette.tint[name]
	if type(hue) ~= "table" then return nil end
	return hue
end

-- r, g, b of a background color with the tint mixed in. The mix keeps
-- the color's luminance, so a tinted panel is exactly as dark as the plain
-- one and every text keeps its contrast; only the hue changes.
local function Gamma(c)
	if c <= 0.0031308 then return c * 12.92 end
	return 1.055 * c ^ (1 / 2.4) - 0.055
end

function E:TintBackdrop(r, g, b, name, style)
	local hue = self:PanelTintColor(name, style)
	if not hue then return r, g, b end
	local s = self.tokens.palette.tint.strength
	local mr, mg, mb = r + (hue[1] - r) * s, g + (hue[2] - g) * s, b + (hue[3] - b) * s
	local want, got = Luminance(r, g, b), Luminance(mr, mg, mb)
	if got <= 0 then return r, g, b end
	local k = want / got
	return math.min(1, Gamma(Linear(mr) * k)), math.min(1, Gamma(Linear(mg) * k)), math.min(1, Gamma(Linear(mb) * k))
end

-- r, g, b of an art style's panel background with a tint (default: the
-- profile's tint and the style in effect), for samples such as the tint
-- cards on the Textures page.
function E:PanelBackdropColor(name, style)
	style = style or (self.db and self:ArtStyle() or "Modern")
	local base = (self.Skins and self.Skins.PaletteOf(style) or PALETTE[style] or PALETTE.default).backdrop
	return self:TintBackdrop(base[1], base[2], base[3], name, style)
end

-- A skin's panel and box colors (Core/Skins.lua registers the native skins).
function E:RegisterStylePalette(style, backdrop, border)
	if type(style) ~= "string" or type(backdrop) ~= "table" or type(border) ~= "table" then return end
	PALETTE[style] = {
		backdrop = { backdrop[1], backdrop[2], backdrop[3], backdrop[4] or 1 },
		border = { border[1], border[2], border[3], border[4] or 1 },
	}
end

-- The window title font of a skin (default: the one in effect): its own
-- title font while General > Skin title font is on, else Rajdhani. Locales
-- without Latin letters keep the game font.
local DEFAULT_HEADER = E.media.fontHeader
function E:SkinTitleFont(style)
	local general = self.db and self.db.general
	if not useOwnFonts or (general and general.skinTitleFont == false) then return DEFAULT_HEADER end
	local m = self.SkinManifest and self:SkinManifest(style)
	local name = m and m.fonts and m.fonts.title
	return name and self.media.fonts[name] or DEFAULT_HEADER
end

-- E.media.backdropColor / borderColor for the art style in effect, the
-- window title font and the "Follow skin" bar texture.
function E:UpdateStylePalette()
	local style = self.db and self:ArtStyle() or "Modern"
	local palette = (self.Skins and self.Skins.PaletteOf(style)) or PALETTE[style] or PALETTE.default
	local backdrop, border = self.media.backdropColor, self.media.borderColor
	for i = 1, 4 do
		backdrop[i] = palette.backdrop[i]
		border[i] = palette.border[i]
	end
	backdrop[1], backdrop[2], backdrop[3] = self:TintBackdrop(backdrop[1], backdrop[2], backdrop[3], nil, style)
	self.media.fontHeader = self:SkinTitleFont(style)
	if self.SkinBarTexture then
		local bar = self:SkinBarTexture(style)
		local entry = self.GetMedia and self:GetMedia("statusbar", "Skin")
		if entry then entry.value = bar end
		if self.db and self.db.general.statusbar == "Skin" then self.media.statusbar = bar end
	end
end

---------------------------------------------------------------------------
-- Theme registry: the one list of what follows the theme. Kits
-- and modules register their repaint here instead of hooking RefreshTheme
-- or UpdateArtStyle (or keeping a list of their own); E:UpdateArtStyle,
-- which E:RefreshTheme runs, calls each once after the panels, bars, boxes
-- and fonts below, so one change repaints everything one time.
--   E:OnThemeChanged(key, fn)     a kit-wide repaint, fn(); in the order added,
--                                 a second call with the same key replaces it
--   E:RegisterThemed(object, fn)  one object's repaint, fn(object); weak, so
--                                 nothing is kept alive
--   E:UnregisterThemed(object)
---------------------------------------------------------------------------
local themeRefreshers = {}                               -- { key, fn } in order
local themedObjects = setmetatable({}, { __mode = "k" }) -- object -> fn(object)

function E:OnThemeChanged(key, fn)
	for _, entry in ipairs(themeRefreshers) do
		if entry.key == key then
			entry.fn = fn
			return
		end
	end
	themeRefreshers[#themeRefreshers + 1] = { key = key, fn = fn }
end

function E:RegisterThemed(object, fn)
	if object and type(fn) == "function" then themedObjects[object] = fn end
end

function E:UnregisterThemed(object)
	if object then themedObjects[object] = nil end
end

-- Read-only: how many objects have a repaint registered (tests).
function E:ThemedObjectCount()
	local count = 0
	for _ in pairs(themedObjects) do count = count + 1 end
	return count
end

-- Read-only: how many kit-wide repaints are registered. The count stays the
-- same however often the look changes (tests).
function E:ThemeRefresherCount()
	return #themeRefreshers
end

-- Read-only: the keys of the kit-wide repaints, in the order they run.
function E:ThemeRefresherKeys()
	local keys = {}
	for i, entry in ipairs(themeRefreshers) do keys[i] = entry.key end
	return keys
end

local function Report(ok, err)
	if not ok then geterrorhandler()(err) end
end

-- One pass over the registry. A repaint that asks for another theme change
-- while the pass runs gets one more pass after it (at most one), never a nested one.
local refreshing, refreshAgain = false, false

function E:RunThemeRefresh()
	if refreshing then
		refreshAgain = true
		return
	end
	refreshing = true
	local passes = 0
	repeat
		refreshAgain = false
		passes = passes + 1
		for _, entry in ipairs(themeRefreshers) do Report(pcall(entry.fn)) end
		for object, fn in pairs(themedObjects) do Report(pcall(fn, object)) end
	until not refreshAgain or passes >= 2
	refreshing = false
end

-- Re-skin every panel, status bar, small box and EldoUI text after the art
-- style, accent, font or texture changes.
function E:UpdateArtStyle()
	self:UpdateStylePalette()
	for frame, kind in pairs(self.panels) do
		self:SetPanelTemplate(frame, kind == "transparent")
	end
	for frame, show in pairs(edgeFrames) do
		self:SetStyleEdge(frame, show)
	end
	for bar in pairs(self.statusBars) do
		bar:SetStatusBarTexture(self.media.statusbar)
	end
	-- Small boxes and texts made before the change; the border
	-- width follows the style too (2 pixels under high contrast).
	self:RefreshPixelEdges()
	self:RefreshTemplates()
	self:RefreshThemedFonts()
	-- Kits and modules that registered a repaint (above).
	self:RunThemeRefresh()
end

-- The fill color of a selected tab: the skin's own tab fill (WoW Forever's
-- warm bronze, Data/Skins.lua), otherwise a dark tint of the accent. Used by
-- E:SkinTabs and the chat tabs.
function E:SelectedTabColor(alpha)
	local fill = self.SkinFlag and self:SkinFlag("tabFill")
	if type(fill) == "table" then return fill[1], fill[2], fill[3], alpha or fill[4] end
	-- High contrast: the accent itself, half strength, fully opaque.
	if self:ArtStyle() == "Contrast" then
		local r, g, b = unpack(self.media.accentColor)
		return r * 0.5, g * 0.5, b * 0.5, 1
	end
	-- A native skin: its own tab color (Core/Skins.lua).
	local tab = self.Skins and self.Skins.PaletteOf(self:ArtStyle())
	tab = tab and tab.selectedTab
	if tab then return tab[1], tab[2], tab[3], alpha or tab[4] end
	local r, g, b = unpack(self.media.accentColor)
	return 0.10 + r * 0.08, 0.10 + g * 0.08, 0.12 + b * 0.08, alpha or 0.85
end

-- Pick an art style (General page, installer). A skin can bring an accent
-- (its manifest's accent, Data/Skins.lua):
--   bring  (WoW Forever, Sand) when the accent is still the default blue or
--          the one the layout in use brings;
--   soft   (the native skins) only when the accent is the default blue.
-- Leaving the skin puts back the layout's accent (blue when it has none),
-- unless the player picked another accent in between.
local SAND, BLUE = "DCA77F", "33AAFF"
E.defaults.general.accentFromArt = false

-- The accent a skin brings and its mode, or nil (Core/Skins.lua).
local function SkinAccent(style)
	if E.SkinAccent and type(style) == "string" and E.artStyles[style] then return E:SkinAccent(style) end
	return nil
end

function E:ArtStyleAccent(old, new)
	local general = self.db.general
	local layout = self.layouts and self.layouts[general.layout]
	local layoutAccent = layout and layout.accent
	local newAccent, newMode = SkinAccent(new)
	local oldAccent = SkinAccent(old)
	if new ~= old then
		if oldAccent and general.accentFromArt and general.accent == oldAccent then
			general.accent = newMode == "bring" and newAccent or (layoutAccent or BLUE)
			general.accentFromArt = false
		end
		local accent = general.accent
		local takes = accent == BLUE
		if newMode == "bring" then
			takes = takes or accent == self.defaults.general.accent or (layoutAccent ~= nil and accent == layoutAccent)
		end
		if newAccent and takes then
			general.accent = newAccent
			general.accentFromArt = true
		end
	end
	if general.accent ~= (newAccent or SAND) then general.accentFromArt = false end
end

---------------------------------------------------------------------------
-- The client's own look (design decision): on WoW: Forever a new profile
-- starts with the WoW Forever art style and the Sand accent, the bronze
-- of the game's own frames. Other clients start with Modern and the blue
-- accent. Only the defaults change: a profile saved before keeps the look
-- it had (E:PinClientLook).
---------------------------------------------------------------------------
local CLASSIC_LOOK = { artStyle = "Modern", accent = BLUE, accentFromArt = false }
local FOREVER_LOOK = { artStyle = "Forever", accent = SAND, accentFromArt = true }
local LOOK_MARK = "clientLook"

-- WoW: Forever, by its project id (never by the expansion level or the
-- interface number, which changes with every patch). The one client check
-- every file uses (the look defaults, the ruleset key of saved data).
-- The game named its project constant after the beta name "Camelot" and
-- may rename it, so every known name counts, and the id itself (18) when
-- the client defines none of them. A rename never moves anyone's saved
-- data or look.
local FOREVER_PROJECT_ID = 18
local FOREVER_PROJECT_NAMES = { "WOW_PROJECT_CAMELOT", "WOW_PROJECT_FOREVER" }

function E:IsForeverClient()
	local id = _G.WOW_PROJECT_ID
	if id == nil then return false end
	-- Any of the names the client defines may be the live one (a renamed
	-- constant can stay beside the old name); the id is the fallback only
	-- while the client defines none of them.
	local named = false
	for _, name in ipairs(FOREVER_PROJECT_NAMES) do
		local value = _G[name]
		if value ~= nil then
			named = true
			if id == value then return true end
		end
	end
	if named then return false end
	return id == FOREVER_PROJECT_ID
end

-- The look a new profile starts with on this client: { artStyle, accent, accentFromArt }.
function E:ClientLook()
	return CopyTable(self:IsForeverClient() and FOREVER_LOOK or CLASSIC_LOOK)
end

function E:ApplyClientLookDefaults()
	local general = self.defaults.general
	for key, value in pairs(self:ClientLook()) do general[key] = value end
end
E:ApplyClientLookDefaults()

-- Run on a saved profile before the defaults fill it. A setting that was
-- left at the old default was never saved, so a profile from before the
-- client look gets the old look written in once; a profile made now
-- (`fresh`) only gets the mark and starts on the client look.
function E:PinClientLook(profile, fresh)
	if type(profile) ~= "table" or profile[LOOK_MARK] then return end
	profile[LOOK_MARK] = 1
	if fresh then return end
	if type(profile.general) ~= "table" then profile.general = {} end
	for key, value in pairs(CLASSIC_LOOK) do
		if profile.general[key] == nil then profile.general[key] = value end
	end
end

-- The named accent colors (General > Accent color, the installer's full looks).
E.accentNames = {
	["33AAFF"] = "Eldo blue", ["0CD29D"] = "Turquoise", ["C41F3B"] = "Crimson",
	["DCA77F"] = "Sand", ["7900D9"] = "Violet", ["C79C6E"] = "Bronze", class = "Class color",
	["FF7D0A"] = "Ember", ["ABD473"] = "Moss", ["F58CBA"] = "Rose", ["FFD100"] = "Gold",
	["69CCF0"] = "Frost", ["9482C9"] = "Lavender", ["E6E6E6"] = "Silver", ["D24B3C"] = "Garnet",
	custom = "Custom color",
}

-- The accent of a full look: Sand with the WoW Forever art style, else
-- the layout's own accent (or the blue one). Returns the accent and
-- whether the art style brought it.
function E:FullLookAccent(art, layoutAccent)
	local accent, mode = SkinAccent(art)
	if accent and (mode == "bring" or not layoutAccent) then return accent, true end
	return layoutAccent or BLUE, false
end

-- A layout preset brings its own accent. Under WoW Forever the Sand accent
-- the art style gave stays. Returns true when the accent changed, so the
-- caller can repaint everything (E:RefreshTheme).
function E:SetLayoutAccent(hex)
	local general = self.db.general
	local old = general.accent
	local skinAccent, mode = SkinAccent(general.artStyle)
	if general.accentFromArt and mode == "bring" and general.accent == skinAccent then return false end
	general.accent = hex or self.defaults.general.accent
	return general.accent ~= old
end

function E:SetArtStyle(style)
	if not self.artStyles[style] then return end
	local old = self.db.general.artStyle
	-- An explicit pick stops following the layout's skin (Core/Skins.lua).
	self.db.general.skinFollow = false
	self.db.general.artStyle = style
	self:ArtStyleAccent(old, style)
	if self.RefreshTheme then self:RefreshTheme() else self:UpdateAccent(); self:UpdateArtStyle() end
end

-- A small sample panel drawn in one art style, whatever the profile uses:
-- the installer's style cards and the General page preview. Not in
-- E.panels, so it keeps its style; call it again to repaint.
function E:PaintArtStyleSample(frame, style)
	style = self:ArtStyle(style)
	-- Native skins draw their own sample (Core/Skins.lua).
	if self.Skins and self.Skins.IsNative(style) then return self:PaintSkinSample(frame, style) end
	self:AddBackdrop(frame)
	self:UpdateShadow(frame, false)
	self.artStyles[style](frame)
	return style
end

---------------------------------------------------------------------------
-- Client art helpers. The Forever client does not ship every icon
-- and atlas the Retail UI names. Modules ask through these:
--   E:ClientAtlas(atlas[, fallback])          atlas, true  or  fallback, false
--   E:SetClientAtlas(texture, atlas[, fallback[, useSize]])
--   E:ClientIcon(fileID[, fallback])           a file ID or path this client has
-- A missing atlas is written to the error log once (as a warning). Bundled
-- glyphs stand in for the common ones; anything else falls back to the
-- given texture or the question mark icon.
---------------------------------------------------------------------------
local TEXTURES = "Interface\\AddOns\\EldoUI\\Media\\Textures\\"
local QUESTION_MARK = 134400 -- INV_Misc_QuestionMark, in every client
E.media.cross = TEXTURES .. "EldoCross.tga"
E.media.check = TEXTURES .. "EldoCheck.tga"

-- atlas -> bundled glyph (white, tint with SetVertexColor)
E.atlasFallbacks = {
	["common-icon-delete"] = E.media.cross,
	["common-icon-redx"] = E.media.cross,
	["common-icon-checkmark"] = E.media.check,
	["common-icon-checkmark-yellow"] = E.media.check,
}
-- file ID -> file ID (or path) of a vanilla-era icon this client ships.
-- Add pairs here as they are found in game (/eui errors lists misses).
E.iconFallbacks = {}

local atlasKnown = {}
local function AtlasExists(atlas)
	if atlasKnown[atlas] == nil then
		local get = C_Texture and C_Texture.GetAtlasInfo
		local ok, info = false, nil
		if get then ok, info = pcall(get, atlas) end
		atlasKnown[atlas] = (ok and type(info) == "table" and (info.file or info.filename)) and true or false
		if not atlasKnown[atlas] and E.errors and E.errors.Add then
			E.errors:Add("warning", ("EldoUI: atlas %s is missing on this client; a fallback is shown."):format(tostring(atlas)))
		end
	end
	return atlasKnown[atlas]
end

function E:ClientAtlas(atlas, fallback)
	if type(atlas) ~= "string" or atlas == "" then return fallback, false end
	if AtlasExists(atlas) then return atlas, true end
	return fallback or self.atlasFallbacks[atlas], false
end

-- Sets an atlas, or the fallback texture (path or file ID) when the client
-- lacks it. Returns true when the atlas itself is shown.
function E:SetClientAtlas(texture, atlas, fallback, useSize)
	if not (texture and texture.SetTexture) then return false end
	local value, isAtlas = self:ClientAtlas(atlas, fallback)
	if isAtlas then
		texture:SetAtlas(value, useSize)
		return true
	end
	texture:SetTexture(value or QUESTION_MARK)
	if texture.SetTexCoord then texture:SetTexCoord(0, 1, 0, 1) end
	return false
end

-- Sets a game texture file, or the fallback when the client lacks the file
-- (GetFileIDFromPath answers nil): a bundled glyph name (E.UIKit.SetGlyph,
-- such as "play" or "chevron-right"), a texture path, or nothing. The miss
-- goes to the error log once per file. Returns true when the file is shown.
local filesWarned = {}
function E:SetClientFile(texture, file, fallback)
	if not (texture and texture.SetTexture) then return false end
	local missing = false
	if GetFileIDFromPath then
		local ok, id = pcall(GetFileIDFromPath, file)
		missing = ok and id == nil
	end
	if not missing then
		texture:SetTexture(file)
		if texture.SetRotation then texture:SetRotation(0) end
		return true
	end
	if not filesWarned[file] and self.errors and self.errors.Add then
		filesWarned[file] = true
		self.errors:Add("warning", ("EldoUI: texture %s is missing on this client; a fallback is shown."):format(tostring(file)))
	end
	local Kit = self.UIKit
	if not (Kit and Kit.IsGlyph(fallback) and Kit.SetGlyph(texture, fallback)) then
		texture:SetTexture(fallback)
		if texture.SetRotation then texture:SetRotation(0) end
	end
	return false
end

---------------------------------------------------------------------------
-- Original game art (the Vanilla Original skin): texture files the game
-- client ships, by slot (E.skinOriginal in Data/SkinData.lua). EldoUI never
-- redraws them; it draws the client's own file by its path, with the
-- coordinates of the classic frames, and keeps every piece movable.
--   E:OriginalArt(slot)            the slot's row (file, coords, size, ...) or nil
--   E:OriginalArtState(slot)       how the slot draws on this client:
--       "present"                  the client file, checked to be the original picture
--       "present-pending"          the client file; the picture check is still open
--       "present-but-different"    the client file is not the original picture
--       "missing"                  no client file: the slot's fallback draws
--       "unprobed"                 not looked up yet (no lookup on this client)
--       nil                        no such slot
--   E:SetOriginalArt(texture, slot[, material])  draw a slot on a texture:
--       the client file with its coordinates and blend mode, else its
--       fallback (another slot, or a file of the skin's material: material
--       is an art key of E.skinData, VANILLA by default). Returns true when
--       the client's original file shows.
--   E:OriginalArtSkin([id])        true when a skin (default: the one in use)
--                                  draws the original art
--   E:OriginalArtReport()          every slot, sorted: { slot, surface, state, file }
--   E:OriginalSurfaceState(surface)  one state for a skin surface (a row of
--       E.skinSurfaceList): its weakest slot, in the order missing,
--       present-but-different, present-pending, unprobed, present; nil when
--       the surface has no original slots. The second value counts the
--       slots by state.
---------------------------------------------------------------------------
local originalLive = {} -- slot -> "present" / "missing" (this client's answer)

function E:OriginalArt(slot)
	local data = self.skinOriginal
	return data and data.slots and data.slots[slot] or nil
end

-- The client's own answer for a file, once per slot.
local function OriginalOnClient(slot, row)
	local known = originalLive[slot]
	if known then return known end
	if not GetFileIDFromPath then return nil end
	local ok, id = pcall(GetFileIDFromPath, row.file)
	if not ok then return nil end
	known = id == nil and "missing" or "present"
	originalLive[slot] = known
	return known
end

function E:OriginalArtState(slot)
	local row = self:OriginalArt(slot)
	if not row then return nil end
	if row.probe == "missing" then return "missing" end
	local live = OriginalOnClient(slot, row)
	if live == "missing" then return "missing" end
	if row.probe == "unprobed" and live == nil then return "unprobed" end
	if row.fidelity == "matching" then return "present" end
	if row.fidelity == "different" then return "present-but-different" end
	return "present-pending"
end

local function MaterialFile(key, material)
	local data = E.skinData and (E.skinData[material or "VANILLA"] or E.skinData.VANILLA)
	return data and data.files and data.files[key] or nil
end

function E:SetOriginalArt(texture, slot, material, depth)
	if not (texture and texture.SetTexture) then return false end
	local row = self:OriginalArt(slot)
	if not row then return false end
	local state = self:OriginalArtState(slot)
	local shown = false
	if row.shipped and (state == "present-but-different" or state == "missing") then
		-- A shipped copy of the original picture (Media/Textures/Skins/VANILLA/original).
		texture:SetTexture(row.shipped)
		shown = true
	elseif state ~= "missing" then
		shown = self:SetClientFile(texture, row.file, nil)
		if not shown then originalLive[slot] = "missing" end
	end
	if shown then
		local c = row.coords
		if c then texture:SetTexCoord(c[1], c[2], c[3], c[4]) else texture:SetTexCoord(0, 1, 0, 1) end
		if texture.SetBlendMode then texture:SetBlendMode(row.blend or "BLEND") end
		if texture.SetDesaturated then texture:SetDesaturated(false) end
		return true
	end
	local fallback = row.fallback
	local other = type(fallback) == "string" and fallback:match("^slot:(.+)$")
	if other and (depth or 0) < 2 then
		local ok = self:SetOriginalArt(texture, other, material, (depth or 0) + 1)
		if row.desaturate and texture.SetDesaturated then texture:SetDesaturated(true) end
		return false, ok
	end
	texture:SetTexture(fallback and MaterialFile(fallback, material) or nil)
	texture:SetTexCoord(0, 1, 0, 1)
	if texture.SetBlendMode then texture:SetBlendMode("BLEND") end
	if texture.SetDesaturated then texture:SetDesaturated(false) end
	return false
end

function E:OriginalArtSkin(id)
	local data = self.skinOriginal
	if not (data and data.art and self.SkinManifest) then return false end
	local m = self:SkinManifest(id)
	return m ~= nil and m.art ~= nil and data.art[m.art] == true
end

function E:OriginalArtReport()
	local data = self.skinOriginal
	local list = {}
	for slot, row in pairs(data and data.slots or {}) do
		list[#list + 1] = { slot = slot, surface = row.surface, state = self:OriginalArtState(slot), file = row.file }
	end
	table.sort(list, function(a, b)
		if a.surface ~= b.surface then return a.surface < b.surface end
		return a.slot < b.slot
	end)
	return list
end

local SURFACE_ORDER = { "missing", "present-but-different", "present-pending", "unprobed", "present" }

function E:OriginalSurfaceState(surface)
	local data = self.skinOriginal
	local list = data and data.surfaces and data.surfaces[surface]
	if not list or #list == 0 then return nil end
	local counts = {}
	for _, slot in ipairs(list) do
		local state = self:OriginalArtState(slot) or "missing"
		counts[state] = (counts[state] or 0) + 1
	end
	for _, state in ipairs(SURFACE_ORDER) do
		if counts[state] then return state, counts end
	end
end

function E:ClientIcon(icon, fallback)
	if issecretvalue and issecretvalue(icon) then return icon end
	if type(icon) == "nil" or icon == 0 or icon == "" then return fallback or QUESTION_MARK end
	local swap = self.iconFallbacks[icon]
	if swap then return swap end
	return icon
end

-- Test hook: forget what was probed, and that the missing art was
-- reported (a fresh probe reports it again).
function E:ResetClientArt()
	wipe(atlasKnown)
	wipe(originalLive)
	foreverArt = nil
	foreverWarned = false
end

-- A flat StatusBar with a templated background, used by bars and unit frames.
E.statusBars = setmetatable({}, { __mode = "k" })

function E:CreateStatusBar(parent, name)
	local bar = CreateFrame("StatusBar", name, parent)
	bar:SetStatusBarTexture(self.media.statusbar)
	bar.bg = CreateFrame("Frame", nil, bar)
	bar.bg:SetPoint("TOPLEFT", -self.pixel, self.pixel)
	bar.bg:SetPoint("BOTTOMRIGHT", self.pixel, -self.pixel)
	bar.bg:SetFrameLevel(math.max(bar:GetFrameLevel() - 1, 0))
	self:SetTemplate(bar.bg)
	self.statusBars[bar] = true
	return bar
end

-- The bar texture on a status bar or a plain texture (a fill drawn by
-- hand) that keeps following General > Textures > Bar texture.
function E:UseBarTexture(object)
	if object.SetStatusBarTexture then
		object:SetStatusBarTexture(self.media.statusbar)
		self.statusBars[object] = true
	else
		object:SetTexture(self.media.statusbar)
		self:RegisterThemed(object, function(texture) texture:SetTexture(E.media.statusbar) end)
	end
	return object
end

---------------------------------------------------------------------------
-- Frame shadows (Modern art style, General > Textures). A soft dark edge
-- outside a panel; kept in a weak table, never as a field on the frame.
-- Shadow strength and Shadow size set its opacity and how far it reaches.
-- A frame with its own shadow switch (tooltips, cooldown icons) may keep
-- its own strength and size: pass them as `own` = { alpha = , size = }.
---------------------------------------------------------------------------
E.defaults.general.shadows = false
E.defaults.general.shadowAlpha = E.tokens.shadow.alpha
E.defaults.general.shadowSize = E.tokens.shadow.size
local shadows = setmetatable({}, { __mode = "k" })

-- The shadow's opacity and size: the frame's own when it has them, else
-- the profile's, kept inside the sliders' range.
function E:ShadowLook(own)
	local look, general = self.tokens.shadow, self.db and self.db.general or {}
	own = type(own) == "table" and own or {}
	local alpha = tonumber(own.alpha) or tonumber(general.shadowAlpha) or look.alpha
	local size = tonumber(own.size) or tonumber(general.shadowSize) or look.size
	alpha = math.max(look.minAlpha, math.min(1, alpha))
	size = math.max(look.minSize, math.min(look.maxSize, math.floor(size + 0.5)))
	return alpha, size
end

-- Read-only: the shadow frame of a frame, or nil (tests).
function E:ShadowOf(frame)
	return shadows[frame]
end

function E:UpdateShadow(frame, show, own)
	local shadow = shadows[frame]
	if not show then
		if shadow then shadow:Hide() end
		return
	end
	if not shadow then
		shadow = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		shadows[frame] = shadow
	end
	local alpha, size = self:ShadowLook(own)
	shadow:ClearAllPoints()
	shadow:SetPoint("TOPLEFT", -size, size)
	shadow:SetPoint("BOTTOMRIGHT", size, -size)
	shadow:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))
	shadow:SetBackdrop({ edgeFile = self.media.shadow, edgeSize = size })
	shadow:SetBackdropBorderColor(0, 0, 0, alpha)
	shadow:Show()
end

---------------------------------------------------------------------------
-- Smooth bars (General > Textures). The game animates the bar itself
-- (StatusBar:SetValue with an interpolation), so this also works with
-- secret values; EldoUI does no math on them.
--   bar:SetValue(value, E:BarInterpolation())
---------------------------------------------------------------------------
E.defaults.general.smoothBars = true

-- `override`: a module's own setting: true/"on", false/"off", or nil/"general"
-- to follow General (the unit and group frame "Smooth bars" select).
function E:BarInterpolation(override)
	local interpolation = Enum.StatusBarInterpolation
	if not interpolation then return nil end
	local smooth = override
	if smooth == "on" then smooth = true elseif smooth == "off" then smooth = false elseif smooth == "general" then smooth = nil end
	if smooth == nil then smooth = self.db.general.smoothBars end
	return smooth and interpolation.ExponentialEaseOut or interpolation.Immediate
end

---------------------------------------------------------------------------
-- Color tables (General > Colors). Every color starts as the game's own
-- and can be changed per profile. Modules read them here instead of
-- keeping their own copies:
--   E:GetClassColor("MAGE")      r, g, b
--   E:GetPowerColor("RAGE")      r, g, b
--   E:GetReactionColor(4)        r, g, b   (1 hated ... 8 exalted)
--   E:GetDispelColor("Magic")    r, g, b   ("Magic", "Curse", "Disease", "Poison", "Bleed", "None")
--   E:GetThreatStatusColor(3)    r, g, b   (0 low ... 3 tanking)
--   E:GetStatusColor("dead")     r, g, b   unit states and effects (Core/UnitFX.lua): dead, ghost,
--                                          offline, tapped, lowHealth, lowPower, trail, execute, offTank,
--                                          gradientLow, gradientMid, gradientHigh
--   E:GetPredictionColor("absorb") r, g, b healMine, healOther, absorb, healAbsorb, overAbsorb
--   E:DispelColorMap()           { Magic = ColorMixin, ... } for aura containers
--   E.colors.class.MAGE etc.     { r, g, b, r = , g = , b = } (rebuilt on change)
-- Colors are fixed values handed to the widget: a secret value (a unit's
-- reaction in combat, a dispel type) is never used as a key here; callers
-- check issecretvalue first and let the game color those (color curves).
---------------------------------------------------------------------------
E.defaults.general.colors = {
	blizzardClass = true,  -- use the game's class colors
	class = {}, power = {}, reaction = {}, dispel = {}, threat = {}, status = {}, prediction = {}, difficulty = {},
}

-- What each table lists, in display order. Labels prefer the game's own
-- translated strings.
E.colorGroups = {
	{ key = "power", title = "Power", list = {
		{ "MANA", rawget(_G, "MANA") or Key("Mana") }, { "RAGE", rawget(_G, "RAGE") or Key("Rage") }, { "ENERGY", rawget(_G, "ENERGY") or Key("Energy") },
		{ "FOCUS", rawget(_G, "FOCUS") or Key("Focus") }, { "RUNIC_POWER", rawget(_G, "RUNIC_POWER") or Key("Runic Power") },
		{ "COMBO_POINTS", rawget(_G, "COMBO_POINTS") or Key("Combo Points") }, { "HAPPINESS", Key("Pet happiness") },
	} },
	{ key = "reaction", title = "Reaction", list = {
		{ 1, rawget(_G, "FACTION_STANDING_LABEL1") or Key("Hated") }, { 2, rawget(_G, "FACTION_STANDING_LABEL2") or Key("Hostile") },
		{ 3, rawget(_G, "FACTION_STANDING_LABEL3") or Key("Unfriendly") }, { 4, rawget(_G, "FACTION_STANDING_LABEL4") or Key("Neutral") },
		{ 5, rawget(_G, "FACTION_STANDING_LABEL5") or Key("Friendly") }, { 6, rawget(_G, "FACTION_STANDING_LABEL6") or Key("Honored") },
		{ 7, rawget(_G, "FACTION_STANDING_LABEL7") or Key("Revered") }, { 8, rawget(_G, "FACTION_STANDING_LABEL8") or Key("Exalted") },
	} },
	{ key = "dispel", title = "Dispel types", list = {
		{ "Magic", Key("Magic") }, { "Curse", Key("Curse") }, { "Disease", Key("Disease") },
		{ "Poison", Key("Poison") }, { "Bleed", Key("Bleed") }, { "None", Key("Physical / no type") },
	} },
	-- The game's level difficulty steps, from a level far below yours to
	-- one far above (quests, creatures, zones, trainer rows).
	{ key = "difficulty", title = "Level difficulty", list = {
		{ "trivial", Key("Trivial") }, { "standard", Key("Easy") }, { "difficult", Key("Fair") },
		{ "verydifficult", Key("Hard") }, { "impossible", Key("Very hard") },
	} },
	{ key = "threat", title = "Threat", list = {
		{ 0, Key("Low threat") }, { 1, Key("Gaining threat") }, { 2, Key("Losing aggro") }, { 3, Key("Tanking") },
	} },
	-- Unit states and effects (Core/UnitFX.lua): fixed colors the
	-- effects hand to the game's curves; the game never reports these.
	-- `inUse`: the Colors page shows the group only once a module uses
	-- the effects (E:RegisterUnitFXPresets), so no row does nothing.
	{ key = "status", title = "Unit states and effects", inUse = function() return E:UnitFXInUse() end, list = {
		{ "dead", Key("Dead") }, { "ghost", Key("Ghost") }, { "offline", Key("Offline") }, { "tapped", Key("Tapped by someone else") },
		{ "lowHealth", Key("Low health warning") }, { "lowPower", Key("Low power warning") },
		{ "trail", Key("Damage trail") }, { "execute", Key("Execute shade") }, { "offTank", Key("Another tank has it") },
		{ "gradientLow", Key("Health gradient: empty") }, { "gradientMid", Key("Health gradient: half") },
		{ "gradientHigh", Key("Health gradient: full") },
	} },
	{ key = "prediction", title = "Heal prediction", inUse = function() return E:UnitFXInUse() end, list = {
		{ "healMine", Key("Your incoming heals") }, { "healOther", Key("Others' incoming heals") },
		{ "absorb", Key("Absorb shield") }, { "healAbsorb", Key("Heal absorb") }, { "overAbsorb", Key("Shield beyond full health") },
	} },
}

local function Unpack(color)
	if type(color) ~= "table" then return nil end
	if color.r then return color.r, color.g, color.b end
	return color[1], color[2], color[3]
end

-- The game's own color for an entry.
local DISPEL_GLOBAL = { Magic = "MAGIC", Curse = "CURSE", Disease = "DISEASE", Poison = "POISON", Bleed = "BLEED", None = "NONE" }
local FALLBACK = {
	dispel = { Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0, 1 }, Disease = { 0.6, 0.4, 0 }, Poison = { 0, 0.6, 0 }, Bleed = { 0.8, 0, 0 }, None = { 0.8, 0, 0 } },
	threat = { [0] = { 0.69, 0.69, 0.69 }, { 1, 1, 0.47 }, { 1, 0.6, 0 }, { 1, 0, 0 } },
	-- The game's QuestDifficultyColors, for a client without them.
	difficulty = { trivial = { 0.5, 0.5, 0.5 }, standard = { 0.25, 0.75, 0.25 }, difficult = { 1, 0.82, 0 },
		verydifficult = { 1, 0.5, 0.25 }, impossible = { 1, 0.1, 0.1 } },
	power = { HAPPINESS = { 0, 1, 1 } },
	-- The game's standing colors (FACTION_BAR_COLORS), for a client
	-- without them: 1 hated ... 8 exalted.
	reaction = { { 0.8, 0.3, 0.22 }, { 0.8, 0.3, 0.22 }, { 0.75, 0.27, 0 }, { 0.9, 0.7, 0 },
		{ 0, 0.6, 0.1 }, { 0, 0.6, 0.1 }, { 0, 0.6, 0.1 }, { 0, 0.6, 0.1 } },
	status = {
		dead = { 0.5, 0.5, 0.5 }, ghost = { 0.6, 0.65, 0.8 }, offline = { 0.45, 0.45, 0.48 }, tapped = { 0.55, 0.55, 0.55 },
		lowHealth = { 0.9, 0.1, 0.1 }, lowPower = { 1, 0.55, 0.1 }, trail = { 0.95, 0.3, 0.2 },
		execute = { 1, 0.55, 0.2 }, offTank = { 0.5, 0.5, 0.95 },
		gradientLow = { 0.85, 0.15, 0.15 }, gradientMid = { 1, 0.82, 0 }, gradientHigh = { 0.1, 0.8, 0.1 },
	},
	prediction = {
		healMine = { 0.3, 0.95, 0.45 }, healOther = { 0.2, 0.75, 0.35 }, absorb = { 1, 1, 1 },
		healAbsorb = { 0.7, 0.1, 0.1 }, overAbsorb = { 1, 1, 1 },
	},
}
function E:GameColor(group, key)
	local r, g, b
	if group == "class" then
		local color = C_ClassColor and C_ClassColor.GetClassColor(key)
		if color then r, g, b = color.r, color.g, color.b end
	elseif group == "power" then
		r, g, b = Unpack(PowerBarColor and PowerBarColor[key])
	elseif group == "reaction" then
		r, g, b = Unpack(FACTION_BAR_COLORS and FACTION_BAR_COLORS[key])
	elseif group == "dispel" then
		r, g, b = Unpack(DISPEL_GLOBAL[key] and _G["DEBUFF_TYPE_" .. DISPEL_GLOBAL[key] .. "_COLOR"])
	elseif group == "threat" and GetThreatStatusColor then
		r, g, b = GetThreatStatusColor(key)
	elseif group == "difficulty" then
		local colors = rawget(_G, "QuestDifficultyColors")
		r, g, b = Unpack(type(colors) == "table" and colors[key])
	end
	if r then return r, g, b end
	return Unpack(FALLBACK[group] and FALLBACK[group][key])
end

local function Override(group, key)
	local colors = E.db and E.db.general.colors
	if not colors then return nil end
	if group == "class" and colors.blizzardClass then return nil end
	local list = colors[group]
	return type(list) == "table" and list[key] or nil
end

function E:GetColor(group, key)
	if (issecretvalue and issecretvalue(key)) or type(key) == "nil" then return nil end
	local custom = Override(group, key)
	if custom then return Unpack(custom) end
	-- Color-blind safe colors (General > Accessibility) come before
	-- the game's own; the player's own picks above still win.
	local safe = self.colorBlindPalette and self.colorBlindPalette[group]
	if safe and safe[key] then return Unpack(safe[key]) end
	return self:GameColor(group, key)
end

function E:GetClassColor(classFile) return self:GetColor("class", classFile) end
function E:GetPowerColor(token) return self:GetColor("power", token) end
function E:GetReactionColor(reaction) return self:GetColor("reaction", reaction) end
function E:GetDispelColor(dispelType) return self:GetColor("dispel", dispelType or "None") end
function E:GetThreatStatusColor(status) return self:GetColor("threat", status) end
function E:GetStatusColor(key) return self:GetColor("status", key) end
function E:GetPredictionColor(key) return self:GetColor("prediction", key) end

-- Level difficulty: the step of a color the game hands out
-- (GetQuestDifficultyColor, GetCreatureDifficultyColor), and that color
-- through the player's picks and the color-blind safe ramp. A color that
-- matches no step comes back as it is.
local DIFFICULTY_KEYS = { "trivial", "standard", "difficult", "verydifficult", "impossible" }
function E:DifficultyKey(color)
	if type(color) ~= "table" or type(color.r) ~= "number" then return nil end
	for _, key in ipairs(DIFFICULTY_KEYS) do
		local r, g, b = self:GameColor("difficulty", key)
		if r and math.abs(r - color.r) < 0.01 and math.abs(g - color.g) < 0.01 and math.abs(b - color.b) < 0.01 then return key end
	end
	return nil
end

-- Only the player's pick or the safe step for a difficulty, else nil.
function E:DifficultyOverride(key)
	local custom = Override("difficulty", key)
	if custom then return Unpack(custom) end
	local safe = self.colorBlindPalette and self.colorBlindPalette.difficulty
	if safe and safe[key] then return Unpack(safe[key]) end
	return nil
end

function E:DifficultyColor(color)
	local key = self:DifficultyKey(color)
	if not key then return color end
	local r, g, b = self:GetColor("difficulty", key)
	if not r then return color end
	return { r = r, g = g, b = b }
end

-- Class files of this client, for the Colors page.
function E:ClassList()
	if self.classList then return self.classList end
	local list = {}
	if C_CreatureInfo and C_CreatureInfo.GetClassInfo then
		for id = 1, 30 do
			local info = C_CreatureInfo.GetClassInfo(id)
			if type(info) == "table" and type(info.classFile) == "string" then
				list[#list + 1] = { info.classFile, info.className or info.classFile }
			end
		end
	end
	table.sort(list, function(a, b) return a[2] < b[2] end)
	self.classList = list
	return list
end

E.colors = { class = {}, power = {}, reaction = {}, dispel = {}, threat = {}, status = {}, prediction = {}, difficulty = {} }

local function Fill(target, r, g, b)
	target[1], target[2], target[3] = r, g, b
	target.r, target.g, target.b = r, g, b
	return target
end

-- Rebuild E.colors (tables are reused, so references stay valid).
function E:UpdateColors()
	for _, class in ipairs(self:ClassList()) do
		local r, g, b = self:GetClassColor(class[1])
		if r then self.colors.class[class[1]] = Fill(self.colors.class[class[1]] or {}, r, g, b) end
	end
	for _, group in ipairs(self.colorGroups) do
		for _, entry in ipairs(group.list) do
			local r, g, b = self:GetColor(group.key, entry[1])
			if r then self.colors[group.key][entry[1]] = Fill(self.colors[group.key][entry[1]] or {}, r, g, b) end
		end
	end
	self.dispelMap = nil
	-- Kept texts that carry these colors check this to start over.
	self.colorsVersion = (self.colorsVersion or 0) + 1
end

-- Dispel colors as ColorMixin objects keyed by dispel name, the format
-- aura containers take (customDispelColorMap).
function E:DispelColorMap()
	if self.dispelMap then return self.dispelMap end
	if not CreateColor then return nil end
	local map = {}
	for key in pairs(DISPEL_GLOBAL) do
		local r, g, b = self:GetDispelColor(key)
		if r then map[key] = CreateColor(r, g, b, 1) end
	end
	self.dispelMap = map
	return map
end

---------------------------------------------------------------------------
-- Number format (General > Fonts and Text). One style for every big number
-- EldoUI shows (tags, datatexts, tooltips):
--   E:FormatNumber(value)   "1.2k" / "1,234" / ... ; secret values go
--   through the game's own formatter, so the result may be a secret string
--   that only FontString:SetText can show.
---------------------------------------------------------------------------
E.defaults.general.numberStyle = "short"
E.defaults.general.numberDecimals = 1

E.numberStyles = {
	short = Key("1.2k  3.4m  5.6b"),
	upper = Key("1.2K  3.4M  5.6B"),
	metric = Key("1.2k  3.4M  5.6G"),
	word = Key("1.2 thousand"),
	full = Key("1,234,567"),
	game = Key("The game's style for your language"),
}

local UNITS = {
	short = { { 1e12, "t" }, { 1e9, "b" }, { 1e6, "m" }, { 1e3, "k" } },
	upper = { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } },
	metric = { { 1e12, "T" }, { 1e9, "G" }, { 1e6, "M" }, { 1e3, "k" } },
}

local numberOptions  -- options table for AbbreviateNumbers
local numberStyle, numberDecimals

local function Units(style)
	if style == "word" then
		local L = E.L
		return { { 1e12, " " .. L["trillion"] }, { 1e9, " " .. L["billion"] }, { 1e6, " " .. L["million"] }, { 1e3, " " .. L["thousand"] } }
	end
	return UNITS[style]
end

function E:UpdateNumberFormat()
	local general = self.db.general
	numberStyle = E.numberStyles[general.numberStyle] and general.numberStyle or "short"
	numberDecimals = math.max(0, math.min(2, math.floor(tonumber(general.numberDecimals) or 1)))
	numberOptions = nil
	local units = Units(numberStyle)
	if units then
		local fraction = 10 ^ numberDecimals
		local data = {}
		for _, unit in ipairs(units) do
			data[#data + 1] = { breakpoint = unit[1], abbreviation = unit[2], abbreviationIsGlobal = false,
				significandDivisor = unit[1] / fraction, fractionDivisor = fraction }
		end
		numberOptions = { breakpointData = data }
		if CreateAbbreviateConfig then
			local ok, config = pcall(CreateAbbreviateConfig, data)
			if ok and config then numberOptions.config = config end
		end
	end
end

-- Plain Lua for readable numbers (also the fallback when the game's
-- formatter is missing).
local function FormatPlain(value, style, decimals)
	if style == "full" or style == "game" then
		if BreakUpLargeNumbers then return BreakUpLargeNumbers(value) end
		return tostring(math.floor(value + 0.5))
	end
	local units = Units(style) or UNITS.short
	local negative = value < 0
	local abs = negative and -value or value
	for index, unit in ipairs(units) do
		if abs >= unit[1] then
			local shown = ("%." .. decimals .. "f"):format(abs / unit[1])
			-- 999.95k rounds to 1000.0k: show 1m instead.
			if tonumber(shown) >= 1000 and units[index - 1] then
				unit = units[index - 1]
				shown = ("%." .. decimals .. "f"):format(abs / unit[1])
			end
			if decimals > 0 then shown = E:LocalDecimals((shown:gsub("%.?0+$", ""))) end
			return (negative and "-" or "") .. shown .. unit[2]
		end
	end
	return tostring(math.floor(value + 0.5))
end

function E:FormatNumber(value, style, decimals)
	if type(value) == "nil" then return "" end
	if not numberStyle then self:UpdateNumberFormat() end
	style = style or numberStyle
	decimals = decimals or numberDecimals
	local secret = issecretvalue and issecretvalue(value)
	if not secret then
		if type(value) ~= "number" then return tostring(value) end
		if style == "game" and AbbreviateNumbers then return AbbreviateNumbers(value) end
		return FormatPlain(value, style, decimals)
	end
	-- A secret number: only the game may format it (EldoUI never reads
	-- it); the result is a secret string for FontString:SetText.
	if style == "full" and BreakUpLargeNumbers then return BreakUpLargeNumbers(value) end
	if not AbbreviateNumbers then return "" end
	if numberOptions and style == numberStyle and decimals == numberDecimals then
		local ok, text = pcall(AbbreviateNumbers, value, numberOptions)
		if ok and type(text) ~= "nil" then return text end
	end
	return AbbreviateNumbers(value)
end

---------------------------------------------------------------------------
-- Money: one formatter, one coin color set
-- (E.tokens.money) and one Money style (Fonts and text page,
-- E.db.general.moneyStyle) for every window. A window with its own choice
-- passes it; "general" or nil follows the Money style. Styles:
--   "icons"    the game's coin string
--   "letters"  the units that are not zero: 12g 5c
--   "full"     every unit from the largest down: 12g 0s 5c
--   "two"      the two largest units: 12g 34s, 34s 5c, 5c
--   "short"    the largest unit only: 12g
-- Each amount is in its coin color; gold takes the thousands separator.
---------------------------------------------------------------------------
local function Coin(amount, unit, kind)
	return E:TokenHex(E.tokens.money[kind]) .. amount .. unit .. "|r"
end

E.defaults.general.moneyStyle = "icons"

-- The choices of the Money style, and of a window's own choice
-- (withGeneral adds "Use general setting").
function E:MoneyStyleValues(withGeneral)
	local L = self.L
	local values = { icons = L["Coin icons"], letters = L["Letters (12g 34s)"], short = L["Largest coin only (12g)"] }
	if withGeneral then values.general = L["Use general setting"] end
	return values
end

---------------------------------------------------------------------------
-- Durations: one formatter for the clock and long forms.
--   E:FormatDuration(seconds, style, rule)
--   style  "clock"    1:05:09, or 5:09 under an hour (default)
--          "minutes"  65:09, minutes and seconds only
--          "long"     2d 3h 5m, 3h 5m or 5m (localized)
--   rule   "floor" (default, time passed) or "round" (an estimate)
-- Negative times read as 0.
---------------------------------------------------------------------------
function E:FormatDuration(seconds, style, rule)
	seconds = tonumber(seconds) or 0
	seconds = math.max(0, rule == "round" and math.floor(seconds + 0.5) or math.floor(seconds))
	if style == "long" then
		local L = self.L
		local days, hours, minutes = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600), math.floor(seconds % 3600 / 60)
		if days > 0 then return L["%dd %dh %dm"]:format(days, hours, minutes) end
		if hours > 0 then return L["%dh %dm"]:format(hours, minutes) end
		return L["%dm"]:format(minutes)
	end
	local hours = math.floor(seconds / 3600)
	if style ~= "minutes" and hours > 0 then
		return ("%d:%02d:%02d"):format(hours, math.floor(seconds % 3600 / 60), seconds % 60)
	end
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

function E:FormatMoney(copper, style)
	copper = math.floor((tonumber(copper) or 0) + 0.5)
	if style == nil or style == "general" then
		local general = self.db and self.db.general
		style = general and general.moneyStyle or "icons"
	end
	if style == "icons" then
		if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
			return C_CurrencyInfo.GetCoinTextureString(copper)
		end
		return GetCoinTextureString(copper)
	end
	local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local goldText = BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or tostring(gold)
	local G, S, C = Coin(goldText, "g", "gold"), Coin(silver, "s", "silver"), Coin(rest, "c", "copper")
	if style == "short" then
		if gold > 0 then return G end
		if silver > 0 then return S end
		return C
	elseif style == "two" then
		if gold > 0 then return G .. " " .. S end
		if silver > 0 then return S .. " " .. C end
		return C
	end
	local parts = {}
	if gold > 0 then parts[#parts + 1] = G end
	if silver > 0 or (style == "full" and gold > 0) then parts[#parts + 1] = S end
	if rest > 0 or style == "full" or #parts == 0 then parts[#parts + 1] = C end
	return table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- Cooldown numbers (General > Fonts and Text): one font object every
-- cooldown swipe can use for its countdown text.
--   E:ApplyCooldownFont(cooldown)   cooldown:SetCountdownFont(...)
---------------------------------------------------------------------------
E.defaults.general.cooldownFont = "THEME"  -- "THEME" = the theme font
E.defaults.general.cooldownFontSize = 16
E.defaults.general.cooldownFontOutline = "OUTLINE"
-- The cooldown-number look every module shares (E:CooldownLook):
-- seconds below which the expiring color and tenths show, and the colors
-- of minutes and hours, seconds and the last seconds.
E.defaults.general.cooldownExpiring = 5
E.defaults.general.cooldownTenths = 3
E.defaults.general.cooldownColor = { 1, 1, 1 }
E.defaults.general.cooldownSecondsColor = { 1, 0.9, 0.4 }
E.defaults.general.cooldownExpiringColor = { 1, 0.3, 0.3 }
E.cooldownFontName = "EldoUICooldownFont"
local cooldownFont = CreateFont and CreateFont(E.cooldownFontName)

function E:CooldownFont()
	local general = self.db.general
	local id = general.cooldownFont
	local theme = id == nil or id == "" or id == "default" or id == "THEME"
	local path = not theme and self.FetchMedia and self:FetchMedia("font", id) or nil
	return path or self.media.font, general.cooldownFontSize, general.cooldownFontOutline
end

function E:UpdateCooldownFont()
	if not cooldownFont then return end
	local path, size, outline = self:CooldownFont()
	if not cooldownFont:SetFont(path, size, outline) then
		cooldownFont:SetFont(self.media.font, size, outline)
	end
end

function E:ApplyCooldownFont(cooldown)
	if cooldownFont and cooldown and cooldown.SetCountdownFont then
		cooldown:SetCountdownFont(self.cooldownFontName)
	end
end

---------------------------------------------------------------------------
-- Game fonts (General > Fonts and Text). Off by default: the
-- game's font objects stay exactly as Blizzard made them. On, the theme
-- font is set on the client's own font objects (system text, tooltips,
-- quests, mail, error and zone text, the chat font face), sizes times a
-- scale. Switching it off restores every font object; text that already
-- copied the font keeps it until a reload (the option asks for one).
--
-- Names over heads (UNIT_NAME_FONT) and floating combat text
-- (DAMAGE_TEXT_FONT) are read by the client when the world loads, so
-- those two take effect after logging out and back in.
---------------------------------------------------------------------------
E.defaults.general.gameFonts = false
E.defaults.general.gameFontScale = 1
E.defaults.general.worldFont = "none"       -- names over heads; "none" = Blizzard's
E.defaults.general.combatTextFont = "none"  -- floating combat text; "none" = Blizzard's

-- The client's base font objects (Blizzard_Fonts_Shared on Forever) and
-- the common styles built on them. Nameplate, chat bubble and world text
-- fonts are left to their modules.
local GAME_FONTS = {
	system = {
		"SystemFont_Tiny2", "SystemFont_Tiny", "SystemFont_Shadow_Small", "SystemFont_Shadow_Outline_Small", "Game10Font_o1",
		"SystemFont_Small", "SystemFont_Small2", "SystemFont_Shadow_Small2", "SystemFont_Shadow_Med1_Outline", "SystemFont_Shadow_Med1",
		"SystemFont_Shadow_Med2", "SystemFont_Outline_Med2", "SystemFont_Med2", "SystemFont_Med3", "SystemFont_Shadow_Med3",
		"SystemFont_Large", "SystemFont_Shadow_Outline_Large", "SystemFont_Shadow_Large_Outline", "SystemFont_Shadow_Large",
		"SystemFont_Shadow_Large2", "SystemFont_Shadow_Huge1", "SystemFont_Huge2", "SystemFont_Outline_Slug_Huge2", "SystemFont_Shadow_Huge2",
		"SystemFont_Shadow_Huge3", "SystemFont_Shadow_Outline_Huge3", "SystemFont_Huge4", "SystemFont_Shadow_Huge4",
		"SystemFont_Shadow_Huge4_Outline", "SystemFont_Med1", "SystemFont_WTF2", "SystemFont_Outline_WTF2", "SystemFont22_Shadow_Outline",
		"System15Font", "System15Font_Shadow", "Game15Font_Shadow", "Game16Font", "Game22Font", "Game30Font", "Game32Font_Shadow2",
		"Game36Font_Shadow2", "Game40Font_Shadow2", "Game60Font", "Game72Font", "FriendsFont_Small", "FriendsFont_Normal",
		"FriendsFont_Large", "UserScaledFontSystem_Header", "UserScaledFontSystem_Body", "SystemFont_InverseShadow_Small",
		"SystemFont_Huge1", "SystemFont_Huge1_Outline", "SystemFont_Huge1_Outline_Slug", "NumberFont_GameNormal", "NumberFont_GameLarge",
		"Number12Font", "NumberFont_Outline_Huge", "Game11Font", "Game12Font", "Game13Font", "Game13FontShadow", "Game15Font",
		"Game18Font", "Game20Font", "Game24Font", "Game27Font", "Game32Font", "Game36Font", "Game42Font", "Game46Font", "Game48Font",
		"Game48FontShadow", "Game120Font", "Game11Font_o1", "Game12Font_o1", "Game13Font_o1", "Game15Font_o1", "Fancy12Font",
		"Fancy14Font", "Fancy16Font", "Fancy18Font", "Fancy20Font", "Fancy22Font", "Fancy24Font", "Fancy27Font", "Fancy30Font",
		"Fancy32Font", "Fancy48Font", "SplashHeaderFont", "DestinyFontMed", "DestinyFontLarge", "DestinyFontHuge", "CoreAbilityFont",
		"SpellFont_Small", "AchievementFont_Small", "ReputationDetailFont", "GameFont_Gigantic", "SystemFont_Shadow_Small_Outline",
		"SystemFont_Shadow_Small2_Outline", "SystemFont_Shadow_Med3_Outline", "SystemFont_Shadow_Med2_Outline", "SystemFont_Large2",
		"SystemFont_Outline_Slug_Large2", "SystemFont_Shadow_Large2_Outline", "Game17Font_Shadow", "SystemFont_Shadow_Huge1_Outline",
		"SystemFont_Shadow_Huge2_Outline", "SystemFont22_Outline", "SystemFont16_Shadow_ThickOutline", "SystemFont18_Shadow_ThickOutline",
		"SystemFont22_Shadow_ThickOutline", "Game46Font_Shadow2", "Game52Font_Shadow2", "Game58Font_Shadow2", "Game69Font_Shadow2",
		"Game72Font_Shadow", "FriendsFont_11", "FriendsFont_UserText", "NumberFont_Shadow_Tiny", "NumberFont_Shadow_Small",
		"NumberFont_Shadow_Med", "NumberFont_Shadow_Large", "NumberFont_Normal_Med", "NumberFont_Outline_Med", "NumberFont_Outline_Large",
		"NumberFont_Outline_Large2", "SystemFont_Outline_Small", "SystemFont_Outline", "PriceFont", "NumberFont_OutlineThick_Mono_Small",
		"NumberFont_Small", "Number11Font", "Number12FontOutline", "Number13Font", "Number15Font", "Number16Font", "Number18Font",
		"Number12Font_o1", "Game11Font_Shadow", "Game19Font", "Game21Font", "Game40Font", "Fancy36Font", "Fancy40Font",
		"OrderHallTalentRowFont",
		-- Common styles, in case a style doesn't follow its base font.
		"GameFontNormal", "GameFontHighlight", "GameFontDisable", "GameFontNormalSmall", "GameFontHighlightSmall",
		"GameFontDisableSmall", "GameFontNormalLarge", "GameFontHighlightLarge", "GameFontNormalHuge", "NumberFontNormal",
		"NumberFontNormalSmall",
	},
	tooltip = { "GameTooltipHeader", "Tooltip_Med", "Tooltip_Small", "GameTooltipHeaderText", "GameTooltipText", "GameTooltipTextSmall" },
	quest = {
		"QuestFont_Large", "QuestFont_Huge", "QuestFont_39", "QuestFont_30", "QuestFont_Shadow_Small", "QuestFont_Outline_Huge",
		"QuestFont_Super_Huge", "QuestFont_Super_Huge_Outline", "QuestFont_Enormous", "QuestFont", "QuestTitleFont", "QuestFontNormalSmall",
	},
	mail = { "MailFont_Large", "InvoiceFont_Med", "InvoiceFont_Small", "MailTextFontNormal" },
	errors = { "ErrorFont" },
	zone = { "ZoneTextFont", "SubZoneTextFont", "PVPInfoTextFont" },
	-- Chat keeps its sizes (each chat window sets its own); only the face changes.
	chat = { "ChatFontNormal", "ChatFontSmall" },
}
local GROUP_ORDER = { "system", "tooltip", "quest", "mail", "errors", "zone", "chat" }

local originalFonts = {}   -- font object -> { path, size, flags }
local gameFontsApplied = false

local function EachGameFont(fn)
	for _, group in ipairs(GROUP_ORDER) do
		for _, name in ipairs(GAME_FONTS[group]) do
			local object = _G[name]
			if type(object) == "table" and object.GetFont and object.SetFont then fn(object, group) end
		end
	end
end

-- The Blizzard element switch for game fonts, once the catalog has one.
local function GameFontsAllowed()
	if not E.db.general.gameFonts then return false end
	if E.blizzardElements and E.blizzardElements["game-fonts"] then return E:BlizzardAllowed("game-fonts", "skin") end
	return true
end

local function ApplyGameFonts()
	if GameFontsAllowed() then
		-- Remember every original before changing any (styles may follow
		-- their base font).
		EachGameFont(function(object)
			if not originalFonts[object] then
				local path, size, flags = object:GetFont()
				if path then originalFonts[object] = { path, size, flags } end
			end
		end)
		local scale = math.max(0.5, math.min(2, tonumber(E.db.general.gameFontScale) or 1))
		EachGameFont(function(object, group)
			local original = originalFonts[object]
			if original then
				local size = original[2] or 12
				if group ~= "chat" then size = size * scale end
				object:SetFont(E.media.font, size, original[3] or "")
			end
		end)
		gameFontsApplied = true
	elseif gameFontsApplied then
		for object, original in pairs(originalFonts) do object:SetFont(original[1], original[2], original[3] or "") end
		gameFontsApplied = false
	end
end

function E:UpdateGameFonts()
	if not self.db then return end
	self:RunOutOfCombat(ApplyGameFonts)
	self:UpdateWorldFonts()
end

-- UNIT_NAME_FONT / DAMAGE_TEXT_FONT: client globals read when the world
-- loads. Only written when the player picked a font; the game's own value
-- is kept to put back.
local worldOriginal = {}
local function SetWorldFont(global, id)
	if id == nil or id == "none" then
		if worldOriginal[global] then
			_G[global] = worldOriginal[global]
			worldOriginal[global] = nil
		end
		return
	end
	local path = E.FetchMedia and E:FetchMedia("font", id)
	if not path then return end
	if worldOriginal[global] == nil then worldOriginal[global] = _G[global] end
	if _G[global] ~= path then _G[global] = path end
end

-- Names over heads work like the name font: the picked font draws Latin
-- letters, the game keeps its own font for every other alphabet. EldoUI's
-- fonts have Latin letters only, so a client in another alphabet keeps its
-- own name font and only its Latin slot takes the pick; the game's fonts
-- for Cyrillic, Korean and Chinese names are never replaced.
local NON_LATIN_CLIENTS = { ruRU = true, koKR = true, zhCN = true, zhTW = true }
local function LatinClient()
	local locale = type(GetLocale) == "function" and GetLocale()
	return not NON_LATIN_CLIENTS[locale]
end
E.LatinNameClient = LatinClient -- exposed for inspection

function E:UpdateWorldFonts()
	local nameFont = self.db.general.worldFont
	SetWorldFont("UNIT_NAME_FONT", LatinClient() and nameFont or "none")
	-- The Latin slot of the game's name fonts, where the client has one.
	if type(worldOriginal.UNIT_NAME_FONT_ROMAN or _G.UNIT_NAME_FONT_ROMAN) == "string" then
		SetWorldFont("UNIT_NAME_FONT_ROMAN", nameFont)
	end
	SetWorldFont("DAMAGE_TEXT_FONT", self.db.general.combatTextFont)
end

---------------------------------------------------------------------------
-- Shared settings several modules read (General page): one durability
-- pair and one clock format, so the same gear is "low" everywhere and
-- every EldoUI clock writes the time the same way.
---------------------------------------------------------------------------
E.defaults.general.durabilityWarn = 50  -- percent: at or below, worn (yellow)
E.defaults.general.durabilityLow = 25   -- percent: at or below, low (red)
E.defaults.general.clock24 = "game"     -- game (the game's own setting), 24, 12

-- "ok", "warn" or "low" for a durability percent (nil for no gear).
function E:DurabilityLevel(percent)
	if type(percent) ~= "number" then return nil end
	local general = self.db and self.db.general or self.defaults.general
	local low = tonumber(general.durabilityLow) or self.defaults.general.durabilityLow
	local warn = tonumber(general.durabilityWarn) or self.defaults.general.durabilityWarn
	if percent <= low then return "low" end
	if percent <= warn then return "warn" end
	return "ok"
end

-- "Low" stays below "Worn": the one the player did not just move makes
-- room (5 points), so both colors stay reachable.
local lastWarn
function E:KeepDurabilityOrder()
	local general = self.db and self.db.general
	if not general then return end
	local warn = tonumber(general.durabilityWarn) or self.defaults.general.durabilityWarn
	local low = tonumber(general.durabilityLow) or self.defaults.general.durabilityLow
	if low >= warn then
		if lastWarn ~= nil and warn ~= lastWarn then
			general.durabilityLow = math.max(0, warn - 5)
		else
			general.durabilityWarn = math.min(90, low + 5)
		end
	end
	lastWarn = general.durabilityWarn
end
E:RegisterEvent("PLAYER_LOGIN", function()
	lastWarn = E.db and E.db.general and E.db.general.durabilityWarn
	-- Another profile brings its own values.
	hooksecurefunc(E, "SetProfile", function()
		lastWarn = E.db and E.db.general and E.db.general.durabilityWarn
	end)
end, {}, "engines")

-- True when clocks show 24-hour time.
function E:Clock24()
	local mode = self.db and self.db.general and self.db.general.clock24
	if mode == "24" then return true end
	if mode == "12" then return false end
	if C_CVar and C_CVar.GetCVarBool then
		local ok, on = pcall(C_CVar.GetCVarBool, "timeMgrUseMilitaryTime")
		if ok and on ~= nil then return on and true or false end
	end
	return true
end

-- The clock and date formats live in Core/Dates.lua.

-- Profiles from before: the module rows these replaced move here once. A
-- value a player set wins over a default; the first module that has one
-- wins when several do.
local function ModuleValue(profile, module, key, oldDefault)
	local modules = type(profile.modules) == "table" and profile.modules or nil
	local db = modules and type(modules[module]) == "table" and modules[module] or nil
	if not db then return nil end
	local value = db[key]
	db[key] = nil
	if value ~= nil and value ~= oldDefault then return value end
	return nil
end

E:RegisterProfileMigration(function(profile)
	if type(profile.general) ~= "table" then profile.general = {} end
	local general = profile.general
	local warn = ModuleValue(profile, "InfoBar", "durabilityWarn", 50)
	local ready = ModuleValue(profile, "ReadyReport", "durabilityWarn", 50)
	local low = ModuleValue(profile, "InfoBar", "durabilityBad", 25)
	local sheet = ModuleValue(profile, "Character", "durabilityThreshold", 30)
	warn = tonumber(warn or ready)
	low = tonumber(low or sheet)
	if warn and (general.durabilityWarn == nil or general.durabilityWarn == E.defaults.general.durabilityWarn) then general.durabilityWarn = warn end
	if low and (general.durabilityLow == nil or general.durabilityLow == E.defaults.general.durabilityLow) then general.durabilityLow = low end
end, "general:durability", 1)

-- Reminders kept its own "Warn at" (20 by default). A value the player
-- picked there moves to Worn gear once, unless General has its own; Low
-- durability makes room below it, so both colors stay reachable.
E:RegisterProfileMigration(function(profile)
	if type(profile.general) ~= "table" then profile.general = {} end
	local general = profile.general
	local old = tonumber(ModuleValue(profile, "Reminders", "durabilityPercent", 20))
	if not old then return end
	if general.durabilityWarn ~= nil and general.durabilityWarn ~= E.defaults.general.durabilityWarn then return end
	local warn = math.max(10, math.min(90, old))
	general.durabilityWarn = warn
	local low = tonumber(general.durabilityLow) or E.defaults.general.durabilityLow
	if low >= warn then general.durabilityLow = math.max(0, warn - 5) end
end, "general:durability:reminders", 1)

E:RegisterProfileMigration(function(profile)
	if type(profile.general) ~= "table" then profile.general = {} end
	local general = profile.general
	-- Both rows were on (24-hour) unless the player turned them off.
	local bar = ModuleValue(profile, "InfoBar", "time24", true)
	local map = ModuleValue(profile, "Minimap", "clock24", true)
	if general.clock24 ~= nil and general.clock24 ~= "game" then return end
	if bar ~= nil or map ~= nil then
		general.clock24 = "12"
	elseif not profile.needsSetup then
		-- A profile set up before keeps the 24-hour clock it showed.
		general.clock24 = "24"
	end
end, "general:clock", 1)

-- Bags, Auction House, Merchant and Trade each had their own money row.
-- They now follow the Money style: coin icons (each one's old default)
-- become "Use general setting", and a text choice stays as that window's
-- own choice, in the shared style names.
E:RegisterProfileMigration(function(profile)
	local modules = type(profile.modules) == "table" and profile.modules or nil
	if not modules then return end
	local function Move(module, key, map)
		local db = type(modules[module]) == "table" and modules[module] or nil
		if not db or db[key] == nil then return end
		local value = map[db[key]]
		if value == nil then return end
		db[key] = value ~= false and value or nil
	end
	Move("Bags", "moneyFormat", { icons = false, letters = "letters", short = "short" })
	Move("Auction", "moneyStyle", { icons = false, text = "letters" })
	Move("Merchant", "listMoney", { icons = false, text = "letters" })
	Move("Trade", "valueMoney", { [true] = false, [false] = "letters" })
end, "general:money", 1)

-- Every font row follows the theme font with "THEME". Rows that were
-- plain lists saved "" or "default" for the same thing. Each path is a
-- module, an optional table inside it, and the font keys (default "font").
-- Version 2 adds the encounter timeline, macros, battlegrounds and the
-- combat text scroll fonts; running the first paths again changes nothing.
local THEME_FONT_PATHS = {
	{ "CombatHUD", "meter" }, { "CombatHUD", "combattimer" }, { "CombatHUD", "loc" },
	{ "CombatHUD", "swing" }, { "CombatHUD", "threat" }, { "CombatHUD", "timers" },
	{ "CooldownManager" }, { "CombatText", "blizzard" }, { "CombatText", "feedback" },
	{ "EncounterTimeline" }, { "Macros" }, { "Battlegrounds" },
	{ "CombatText", "scroll", { "font", "critFont" } },
}
local function ThemeFont(db, key)
	if type(db) == "table" and (db[key] == "" or db[key] == "default") then db[key] = "THEME" end
end
E:RegisterProfileMigration(function(profile)
	ThemeFont(profile.general, "cooldownFont")
	local modules = type(profile.modules) == "table" and profile.modules or nil
	if not modules then return end
	for _, path in ipairs(THEME_FONT_PATHS) do
		local db = modules[path[1]]
		if path[2] then db = type(db) == "table" and db[path[2]] or nil end
		for _, key in ipairs(path[3] or { "font" }) do ThemeFont(db, key) end
	end
end, "fonts:theme", 2)
