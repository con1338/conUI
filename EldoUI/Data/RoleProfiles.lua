-- EldoUI role and class profiles: small layers over the chosen
-- layout and styles. Read by Core/Roles.lua, the installer's Role step and
-- the Role page in /eui.
--
-- A role is not a layout. It moves a handful of frames (per layout when a
-- layout needs it) and changes a few look settings. The encounter zone (boss
-- frames, boss mod bars), the boss mod countdown and the cast bar never move
-- by role: players learn them once (placement matrix, section 9).
--
-- Shape of a role:
--   title, desc        what the installer and the Role page show
--   points             mover name -> point, on top of every layout
--   layouts            layout key -> { mover name -> point } for layouts
--                      whose frames sit somewhere else
--   settings           module -> nested table of settings, merged like a
--                      layout's `modules`; only keys the module has are used
--   clickCast          true: the click-cast suggestions are offered
-- Points use the layout format { point, relativeTo, relativePoint, x, y },
-- measured on the 1440-unit canvas the layouts use.
--
-- Four roles: Melee, Ranged, Healer and Tank. Older profiles saved one
-- "damage" role for melee and ranged alike. E.roleAliases keeps that name
-- readable, and Core/Roles.lua turns it into the class's own damage role
-- (E.roleClassDamage) once per profile. Data written for the three older
-- roles (class premades, keybind spells, talent paths) keeps "damage": it
-- stands for Melee and Ranged alike (E:RoleGroup).
--
-- The class layer (E.roleClassLayers) is per class and only for the
-- classes Forever has. The click-cast suggestions (E.roleClickCast) list
-- spell IDs; the first one the player knows is offered, by its name, so the
-- game casts the highest rank. Nothing is bound until the player ticks it.
local _, E = ...
local L = E.L

local Key = E.Key
E.roleOrder = { "melee", "ranged", "healer", "tank" }

-- Older role names a saved profile, a pack or a share string can hold:
-- name -> the role it reads as when the class gives no better answer.
E.roleAliases = { damage = "melee" }

-- What each role counts as for data written for the three older roles.
E.roleGroups = { melee = "damage", ranged = "damage", healer = "healer", tank = "tank" }

-- Never moved by a role: the encounter zone, the countdown and the cast bar.
E.roleProtectedMovers = {
	EldoUI_PlayerCastbar = true, EldoUI_Boss = true, EldoUI_EncounterBar = true, EldoUI_BGTimers = true,
	EldoUI_BigWigsBars = true, EldoUI_BigWigsEmphasize = true, EldoUI_BigWigsMessages = true,
	EldoUI_BigWigsCountdown = true, EldoUI_BossWarnings = true, EldoUI_BossInfo = true,
}

-- The healer grid: party and raid as close to the HUD column as each layout
-- allows, growing left and down, the bottom edge just above the side icons
-- of the cooldown row (mobility). The main tanks and group pets take the
-- raid's old place on the left edge. HEALER_SPOTS holds the spot per layout
-- (the top right corner, from the screen center on the 1440 canvas): the
-- closest free place to (-250, 188) for the party and (-250, 280) for the
-- raid, measured with every opt-in frame on at 1440p, 1080p and 3440x1440.
local HEALER_BASE = {
	EldoUI_Party = { "TOPRIGHT", "UIParent", "CENTER", -250, 188 },
	EldoUI_Raid = { "TOPRIGHT", "UIParent", "CENTER", -250, 280 },
	EldoUI_Tanks = { "TOPLEFT", "UIParent", "TOPLEFT", 19, -504 },
	EldoUI_GroupPets = { "TOPLEFT", "EldoUI_TanksMover", "TOPRIGHT", 8, 0 },
}

local HEALER_SPOTS = {
	-- layout = { party x, party y, raid x, raid y }
	EldoCenter = { -218, 188, -250, 280 },
	EldoModern = { -250, 188, -250, 280 },
	EldoClassic = { -218, 200, -250, 288 },
	EldoClean = { -218, 188, -250, 280 },
	EldoCookies = { -218, 188, -250, 280 },
	EldoZen = { -218, 188, -250, 280 },
	EldoWide = { -218, 188, -250, 280 },
	EldoBlizz = { -218, 188, -250, 280 },
	EldoSyntax = { -210, 188, -250, 280 },
	EldoCompact = { -218, 188, -250, 280 },
	EldoJoe = { -250, 188, -250, 280 },
	EldoHeritage = { -250, 188, -250, 280 },
	EldoHunter = { -218, 188, -250, 280 },
	EldoDark = { -210, 188, -250, 280 },
	EldoCozy = { -250, 202, -250, 284 },
	EldoViolet = { -218, 188, -250, 280 },
	EldoPlates = { -250, 188, -246, 352 },
	EldoSanctum = { -218, 188, -250, 280 },
	EldoZerby = { -250, 188, -250, 304 },
	EldoVanilla = { -250, 188, -250, 280 },
	EldoVanillaCompact = { -250, 188, -250, 280 },
	EldoVanillaFocus = { -250, 188, -250, 280 },
}

-- Classic keeps action bar 4 on the left edge: the tanks take the raid's
-- old spot right of it, the group pets go under them.
-- Heritage and Plates keep the reminders left of the countdown (left of the
-- ready check in their 2000 versions), where the healer grid goes: they move
-- left of the proc overlay, like the other layouts.
local HEALER_EXTRA = {
	EldoClassic = {
		EldoUI_Tanks = { "TOPLEFT", "UIParent", "TOPLEFT", 71, -400 },
		EldoUI_GroupPets = { "TOPLEFT", "EldoUI_TanksMover", "BOTTOMLEFT", 0, -12 },
	},
	EldoHeritage = {
		EldoUI_Reminders = { "CENTER", "UIParent", "CENTER", -128, 0 },
	},
	EldoPlates = {
		EldoUI_Reminders = { "CENTER", "UIParent", "CENTER", -128, 0 },
	},
	EldoVanillaFocus = {
		EldoUI_GroupPets = { "TOPLEFT", "UIParent", "CENTER", -692, -190 },
	},
}

-- Opt-in frames the grid (or the combat text below) would cover step
-- aside to the nearest free place, measured with every module and opt-in
-- part on: aura groups 1 and 4 (groups 2-3 and 5-6 hang under them), the
-- ping feed, the level-up fanfare, the zone toast, the vehicle seats,
-- action bars 6 and 8, the data panel column (panels 2-4 hang under panel
-- 1), the loot window's spot, and in the Vanilla layouts the alert lane
-- with the journal moments on it, the loot toasts and the battleground map
-- (with the ping feed under it), and in Blizzard-like, Hunter and Sanctum the
-- Party Quests panel, 38 units higher, clear of bar 8. Only the ones a
-- layout needs are listed, as their top left corner from the screen
-- center. While those frames are off, the points only wait in the profile.
local HEALER_ASIDE = {
	EldoCenter = {
		AuraGroup1 = { -778, 34 }, AuraGroup4 = { -398, 412 }, PingFeed = { -1165, -128 },
		Fanfare = { -244, 384 }, ActionBar8 = { -1112, -258 }, DataPanel1 = { 512, -248 }
	},
	EldoModern = {
		AuraGroup1 = { -766, -90 }, AuraGroup4 = { -550, -492 }, PingFeed = { -1049, -264 },
		Fanfare = { -244, 384 }, ZoneToast = { 144, -140 }, ActionBar8 = { 396, -50 }
	},
	EldoClassic = {
		AuraGroup1 = { -802, -42 }, AuraGroup4 = { -882, -92 }, Fanfare = { -244, 384 },
		DataPanel1 = { -680, 536 }
	},
	EldoClean = {
		AuraGroup1 = { -634, -138 }, AuraGroup4 = { -398, 412 }, PingFeed = { -1141, -128 },
		Fanfare = { -244, 384 }, ActionBar6 = { -1090, -260 }, DataPanel1 = { 494, -572 }
	},
	EldoCookies = {
		AuraGroup1 = { -726, -138 }, PingFeed = { -646, -238 }, Fanfare = { -244, 384 },
		VehicleSeat = { -832, 8 }, ActionBar6 = { -642, 362 }, ActionBar8 = { -1136, -270 }
	},
	EldoZen = {
		AuraGroup1 = { -778, 34 }, AuraGroup4 = { -398, 412 }, PingFeed = { -1165, -128 },
		Fanfare = { -244, 384 }, ActionBar8 = { -1112, -258 }, DataPanel1 = { 434, -240 }
	},
	EldoWide = { AuraGroup1 = { -766, -98 }, PingFeed = { -1233, -160 }, Fanfare = { -244, 384 }, LootAnchor = { -1108, 80 } },
	EldoBlizz = { AuraGroup1 = { -634, -98 }, PingFeed = { -1165, -228 }, Fanfare = { -244, 384 }, ActionBar8 = { -648, 362 }, PartyQuests = { -632, 608 }, EIM = { -925, 142 } },
	EldoSyntax = {
		AuraGroup1 = { -666, -98 }, AuraGroup4 = { -810, 8 }, PingFeed = { -1240, -128 },
		Fanfare = { -244, 384 }, ActionBar8 = { -648, 362 }
	},
	EldoCompact = {
		AuraGroup1 = { -682, -138 }, AuraGroup4 = { -398, 412 }, PingFeed = { -1141, -128 },
		Fanfare = { -244, 384 }, ActionBar8 = { -1088, -258 }, DataPanel1 = { 494, -236 }
	},
	EldoJoe = {
		AuraGroup1 = { -794, 6 }, AuraGroup4 = { -922, -96 }, PingFeed = { -1205, -216 },
		Fanfare = { -244, 384 }, ActionBar8 = { -648, 362 }
	},
	EldoHeritage = { AuraGroup1 = { -850, 102 }, AuraGroup4 = { -922, -264 }, PingFeed = { -1161, -124 }, ActionBar8 = { -1164, -254 } },
	EldoHunter = { AuraGroup1 = { -634, -138 }, Fanfare = { -244, 384 }, ActionBar6 = { -1094, -258 }, ActionBar8 = { -648, 362 }, PartyQuests = { -632, 608 }, LootAnchor = { -1108, 80 } },
	EldoSanctum = { AuraGroup1 = { -292, -172 }, Fanfare = { -244, 384 }, ActionBar6 = { -1094, -258 }, ActionBar8 = { -648, 362 }, PartyQuests = { -632, 608 }, LootAnchor = { -1108, 80 } },
	EldoDark = { AuraGroup1 = { -758, -226 }, PingFeed = { -1105, -124 }, Fanfare = { -244, 384 }, ActionBar8 = { -648, 360 }, LootAnchor = { -1108, 80 } },
	EldoCozy = { AuraGroup1 = { -922, -94 }, AuraGroup4 = { -674, -304 }, PingFeed = { -1097, -228 }, Fanfare = { -244, 384 }, LootAnchor = { -1108, 80 } },
	EldoViolet = {
		AuraGroup1 = { -314, -150 }, PingFeed = { -1141, -228 }, Fanfare = { -244, 384 },
		ActionBar8 = { -1088, -148 }, EIM = { -1261, -178 }
	},
	EldoPlates = {
		AuraGroup1 = { -722, -202 }, AuraGroup4 = { -1078, -132 }, Fanfare = { -240, 425 },
		ZoneToast = { -244, 304 }, ActionBar8 = { -1244, -258 }
	},
	EldoZerby = {
		AuraGroup1 = { -786, 26 }, AuraGroup4 = { -398, 436 }, PingFeed = { -1141, -128 },
		Fanfare = { -244, 384 }, DataPanel1 = { 490, -232 }
	},
	EldoVanilla = {
		AuraGroup1 = { -314, -142 }, AlertLane = { -732, 340 }, JournalMoments = { -732, 340 },
		Fanfare = { -244, 384 }, ActionBar8 = { -644, -94 }, DataPanel1 = { -796, 460 },
		BattlefieldMap = { -950, -122 }, PingFeed = { -944, -326 }
	},
	EldoVanillaCompact = {
		AuraGroup1 = { -618, -90 }, AlertLane = { -732, 340 }, JournalMoments = { -732, 340 }, LootToasts = { 550, -108 },
		Fanfare = { -244, 384 }, DataPanel1 = { -796, 460 },
		BattlefieldMap = { -950, -122 }, PingFeed = { -944, -326 }
	},
	EldoVanillaFocus = { AuraGroup1 = { -314, -142 }, Fanfare = { -244, 384 } },
}

-- Combat Text sits where the healer frames go: its incoming and
-- static text move to the nearest spot that is free with every opt-in frame
-- on (aura groups, ping feed, extra cooldown rows, resource bars, the
-- gamepad and zone ability buttons), left of the center where the layout
-- has room. Hunter has none there: its incoming text sits right of the HUD
-- column, under the target's combat text. Without Combat Text these points
-- only wait in the profile.
local HEALER_SCT = {
	-- layout = { incoming x, incoming y, static x, static y }
	EldoCenter = { -792, -220, -504, 476 },
	EldoModern = { -1152, -244, -920, -196 },
	EldoClassic = { -972, -100, -556, -564 },
	EldoClean = { -768, -256, -502, 477 },
	EldoCookies = { -820, -256, -1064, -216 },
	EldoZen = { -792, -220, -504, 476 },
	EldoWide = { -780, 32, -408, 477 },
	EldoBlizz = { -792, -220, -1028, -168 },
	EldoSyntax = { -820, -256, -504, 477 },
	EldoCompact = { -768, -256, -308, -400 },
	EldoJoe = { -752, -256, -499, 480 },
	EldoHeritage = { -752, -256, -504, 476 },
	EldoHunter = { -780, 4, -704, -328 },
	EldoDark = { -780, 52, -936, -328 },
	EldoCozy = { -780, 36, -1076, -168 },
	EldoViolet = { -768, -256, -499, 480 },
	EldoPlates = { -560, -172, -804, -144 },
	EldoSanctum = { -780, 4, -704, -328 },
	EldoZerby = { -768, -264, -536, -360 },
	EldoVanilla = { 568, -238, 310, -385 },
	EldoVanillaCompact = { 568, -238, 310, -385 },
	EldoVanillaFocus = { -780, -130, 446, -197 },
}

-- A spot measured from the screen center keeps the anchor of its part of
-- the screen: on a screen taller than the 1440 canvas (16:10 at Auto) the
-- top and bottom parts move apart from the middle, and the frame moves with
-- its neighbors there. `edge` is true when y is the frame's top edge.
local function Spot(point, x, y, edge)
	if y > (edge and 400 or 360) then return { point, "UIParent", "TOP", x, y - 720 } end
	if y < -360 then return { point, "UIParent", "BOTTOM", x, y + 720 } end
	return { point, "UIParent", "CENTER", x, y }
end

local function HealerLayouts()
	local list = {}
	for key, spot in pairs(HEALER_SPOTS) do
		list[key] = {
			EldoUI_Party = { "TOPRIGHT", "UIParent", "CENTER", spot[1], spot[2] },
			EldoUI_Raid = { "TOPRIGHT", "UIParent", "CENTER", spot[3], spot[4] },
		}
		for name, point in pairs(HEALER_EXTRA[key] or {}) do list[key][name] = point end
		for name, at in pairs(HEALER_ASIDE[key] or {}) do
			list[key]["EldoUI_" .. name] = Spot("TOPLEFT", at[1], at[2], true)
		end
		local sct = HEALER_SCT[key]
		if sct then
			list[key].EldoUI_SCTIncoming = Spot("CENTER", sct[1], sct[2])
			list[key].EldoUI_SCTStatic = Spot("CENTER", sct[3], sct[4])
		end
	end
	return list
end
local HEALER_LAYOUTS = HealerLayouts()

-- The bottom-center healer spot (the healer role's "Group frames" choice):
-- the party as one row of five and a raid of up to ten as two rows, centered
-- under the HUD column, between the bar block (with the pet, stance and
-- totem bars above it) and the cast bar. The cast bar and the cooldown rows
-- keep their places, so the band is low: the frames are compact (80 wide,
-- 44 tall in a party, 34 in a raid), so the grid also fits a 16:10 screen.
-- From eleven members the raid uses the Mid raid settings and the side spot
-- above, so a large raid never runs into the HUD. HEALER_BOTTOM holds the bottom edge of the frames per layout
-- family (from the screen bottom on the 1440 canvas); a layout without a row
-- keeps the side spot. HEALER_BOTTOM_ASIDE lists the frames in that band
-- that step aside (top left corner from the screen center, like
-- HEALER_ASIDE), measured with every opt-in frame on.
E.HEALER_BOTTOM_UP_TO = 10
local HEALER_BOTTOM = {
	EldoVanilla = 316, EldoCenter = 302, EldoModern = 256, EldoBlizz = 324, EldoHeritage = 270,
	EldoZen = 302, EldoWide = 262, EldoCozy = 262, EldoHunter = 286, EldoPlates = 262,
}

local HEALER_BOTTOM_ASIDE = {
	EldoVanilla = { SwingMainHand = { 82, -143 }, SCTStatic = { -510, 14 } },
	EldoCenter = { SwingMainHand = { -384, -143 }, PlayerPowerBar1 = { 154, -299 } },
	EldoModern = { SwingMainHand = { 202, -335 }, PlayerPowerBar1 = { -490, -51 } },
	EldoBlizz = { SwingMainHand = { 240, -309 }, ShamanCooldowns = { 208, -332 } },
	EldoHeritage = { SwingMainHand = { 144, -143 } },
	EldoZen = { SwingMainHand = { -448, -335 }, PlayerPowerBar1 = { 150, -299 } },
	EldoCozy = { PlayerPowerBar1 = { -490, -35 } },
	EldoHunter = { SwingMainHand = { 144, -143 }, PlayerPowerBar1 = { -278, -439 }, PetBar = { -544, -366 }, PossessBar = { -210, -330 } },
	EldoPlates = { SwingMainHand = { 202, -181 } },
}

local function HealerBottomLayouts(side)
	local list = {}
	for key, bottom in pairs(HEALER_BOTTOM) do
		local spots = {}
		for name, point in pairs(side[key] or {}) do spots[name] = point end
		spots.EldoUI_Party = { "BOTTOM", "UIParent", "BOTTOM", 0, bottom }
		spots.EldoUI_Raid = { "BOTTOM", "UIParent", "BOTTOM", 0, bottom }
		for name, at in pairs(HEALER_BOTTOM_ASIDE[key] or {}) do
			spots["EldoUI_" .. name] = Spot("TOPLEFT", at[1], at[2], true)
		end
		list[key] = spots
	end
	return list
end

-- Ranged spots: every layout already keeps the cast bar, the pet frame and
-- the mana bar where a caster or a hunter reads them, so no row moves a
-- frame yet. There is one row per layout family and per legacy layout. A
-- legacy layout's row equals what the older damage role moved there
-- (nothing), so a player on it sees no change. A spot added later goes
-- into its layout's row as mover name -> point.
local RANGED_SPOTS = {
	-- Layout families
	EldoVanilla = {}, EldoCenter = {}, EldoModern = {}, EldoBlizz = {}, EldoHeritage = {}, EldoZen = {},
	EldoWide = {}, EldoCozy = {}, EldoHunter = {}, EldoPlates = {}, EldoSanctum = {},
	-- Legacy layouts
	EldoClassic = {}, EldoClean = {}, EldoCookies = {}, EldoSyntax = {}, EldoCompact = {}, EldoJoe = {},
	EldoDark = {}, EldoViolet = {}, EldoZerby = {}, EldoVanillaCompact = {}, EldoVanillaFocus = {},
	EldoSanctum1000 = {},
}

E.roleProfiles = {
	melee = {
		title = "Melee",
		desc = "Close-range damage. Frames stay where the layout puts them, party frames are a little more compact.",
		settings = {
			GroupFrames = { party = { height = 40 } },
		},
	},
	ranged = {
		title = "Ranged",
		desc = "Casters and hunters. Frames stay where the layout puts them, party frames are a little more compact, and the mana bar shows the five-second rule.",
		layouts = RANGED_SPOTS,
		settings = {
			GroupFrames = { party = { height = 40 } },
			ClassPower = { power = { fiveSecond = true } },
		},
	},
	healer = {
		title = "Healer",
		desc = "Party and raid frames move next to the center and grow, with dispel and boss debuff highlights, heal prediction and HoT squares. Frames in their way step aside: aura groups, the ping feed, combat text and the optional bars and panels. Click-casting on group frames is offered as a choice.",
		points = HEALER_BASE,
		layouts = HEALER_LAYOUTS,
		settings = {
			GroupFrames = {
				-- The role owns the size and shape of these parts (a style keeps
				-- only its look there), so it names the whole shape: a style
				-- picked before cannot leave its columns behind.
				party = { width = 200, height = 52, spacing = 4, growth = "DOWN", unitsPerColumn = 5, buffs = { style = "SQUARES" } },
				raid = { width = 88, height = 44, spacing = 2, growth = "RIGHT", unitsPerColumn = 5, maxColumns = 8, buffs = { style = "SQUARES" } },
				-- The Mid and Large raid settings take over from 11 and 26
				-- members when they are on, so they get the same shape: a
				-- healer keeps the larger frames in every raid size. The grid
				-- is the Raid tab's, so the frames fill the same space.
				raid25 = { width = 88, height = 44, spacing = 2, growth = "RIGHT", unitsPerColumn = 5, maxColumns = 8, buffs = { style = "SQUARES" } },
				raid40 = { width = 88, height = 44, spacing = 2, growth = "RIGHT", unitsPerColumn = 5, maxColumns = 8, buffs = { style = "SQUARES" } },
				dispel = { enabled = true, mine = true },
				bossGlow = true,
				prediction = { heals = true, absorbs = true, healAbsorbs = true },
			},
			ClassPower = { power = { fiveSecond = true } },
		},
		clickCast = true,
		-- Where the group frames go: "side" (the points above) or "bottom"
		-- (general.healerSpot). A spot's layouts and settings go on top of
		-- the role's own.
		spotOrder = { "side", "bottom" },
		spots = {
			side = { title = "Beside the center", desc = "Party and raid left of the center column, growing left and down." },
			bottom = {
				title = "Bottom center",
				desc = "The party as one row and a raid of up to ten as two rows, under the center column above your bars. A larger raid moves beside the center.",
				layouts = HealerBottomLayouts(HEALER_LAYOUTS),
				settings = {
					GroupFrames = {
						party = { width = 80, height = 44, spacing = 2, growth = "RIGHT", unitsPerColumn = 5 },
						raid = { width = 80, height = 34, spacing = 2, growth = "RIGHT", unitsPerColumn = 5, maxColumns = 2 },
						-- From eleven members the raid takes the Mid raid settings
						-- and the side spot.
						raid25 = { enabled = true, minMembers = E.HEALER_BOTTOM_UP_TO + 1 },
					},
				},
			},
		},
	},
	tank = {
		title = "Tank",
		desc = "Threat colors on nameplates and EldoUI's threat meter at its placed spot. Main tank frames show in raids. Nothing else moves.",
		settings = {
			Nameplates = { threat = { enabled = true, mode = "TANK" } },
			CombatHUD = { threat = { enabled = true } },
			GroupFrames = { tanks = { enabled = true } },
		},
	},
}

-- Class layer: every class has a premade (Data/ClassPremades.lua), which
-- fills its entry in. Every layer changes at least one value from the module
-- defaults (installer2 checks it), so ticking "Class details" always does
-- something.
E.roleClassLayers = E.roleClassLayers or {}

-- Click-cast suggestions for healers: { mods, key, spell IDs (first known wins), what }.
-- Plain left and right click stay target and menu.
E.roleClickCast = {
	PRIEST = {
		{ mods = "SHIFT-", key = "BUTTON1", spells = { 2061, 2050 }, what = Key("Fast heal") },
		{ mods = "ALT-", key = "BUTTON1", spells = { 2060, 2054, 2050 }, what = Key("Big heal") },
		{ mods = "CTRL-", key = "BUTTON1", spells = { 139 }, what = Key("Heal over time") },
		{ mods = "SHIFT-", key = "BUTTON2", spells = { 17 }, what = Key("Shield") },
		{ mods = "CTRL-", key = "BUTTON2", spells = { 527 }, what = Key("Dispel magic") },
		{ mods = "ALT-", key = "BUTTON2", spells = { 552, 528 }, what = Key("Cure disease") },
	},
	DRUID = {
		{ mods = "SHIFT-", key = "BUTTON1", spells = { 8936, 5185 }, what = Key("Fast heal") },
		{ mods = "ALT-", key = "BUTTON1", spells = { 5185 }, what = Key("Big heal") },
		{ mods = "CTRL-", key = "BUTTON1", spells = { 774 }, what = Key("Heal over time") },
		{ mods = "CTRL-", key = "BUTTON2", spells = { 2782 }, what = Key("Remove curse") },
		{ mods = "ALT-", key = "BUTTON2", spells = { 2893, 8946 }, what = Key("Cure poison") },
	},
	SHAMAN = {
		{ mods = "SHIFT-", key = "BUTTON1", spells = { 8004, 331 }, what = Key("Fast heal") },
		{ mods = "ALT-", key = "BUTTON1", spells = { 331 }, what = Key("Big heal") },
		{ mods = "CTRL-", key = "BUTTON1", spells = { 1064 }, what = Key("Chain heal") },
		{ mods = "CTRL-", key = "BUTTON2", spells = { 526 }, what = Key("Cure poison") },
		{ mods = "ALT-", key = "BUTTON2", spells = { 2870 }, what = Key("Cure disease") },
	},
	PALADIN = {
		{ mods = "SHIFT-", key = "BUTTON1", spells = { 19750, 635 }, what = Key("Fast heal") },
		{ mods = "ALT-", key = "BUTTON1", spells = { 635 }, what = Key("Big heal") },
		{ mods = "CTRL-", key = "BUTTON2", spells = { 4987, 1152 }, what = Key("Cleanse") },
		{ mods = "SHIFT-", key = "BUTTON2", spells = { 1022 }, what = Key("Protection") },
	},
}

-- Classes that can only take some roles on Forever (pre-selection only).
E.roleClassDefault = {
	WARRIOR = "melee", ROGUE = "melee", HUNTER = "ranged", MAGE = "ranged", WARLOCK = "ranged",
}

-- The damage role of each class: what a saved "damage" role becomes, and
-- what the game's damage role suggests. Shamans and druids most often
-- level in close combat; for Elemental or Balance they pick Ranged.
E.roleClassDamage = {
	WARRIOR = "melee", ROGUE = "melee", PALADIN = "melee", SHAMAN = "melee", DRUID = "melee",
	HUNTER = "ranged", MAGE = "ranged", WARLOCK = "ranged", PRIEST = "ranged",
}

-- Current family versions keep the role placements their family offers.
for _, slot in ipairs(E.layoutFamilies or {}) do
	local key = E:FamilyLayoutKey(slot.key)
	if key and key ~= slot.key then
		for _, profile in pairs(E.roleProfiles) do
			if profile.layouts and profile.layouts[slot.key] and not profile.layouts[key] then
				profile.layouts[key] = CopyTable(profile.layouts[slot.key])
			end
			for _, spot in pairs(profile.spots or {}) do
				if spot.layouts and spot.layouts[slot.key] and not spot.layouts[key] then
					spot.layouts[key] = CopyTable(spot.layouts[slot.key])
				end
			end
		end
	end
end
