-- Gamepad Mode UI's frame spots: where EldoUI's frames go while it is on
-- (Core/GamepadMode.lua, E:GetGamepadMoverPoint).
--
-- One overlay for every layout, not a layout of its own: the player and
-- target frames, the cast and resource bars and the cooldown row move into
-- one centered column above the game's gamepad bar, clear of its radial
-- menu (the right of the screen's center) and of the bar itself (656 x 202
-- at BOTTOM 0, 110, so its top is 408 below the center). The utility
-- cooldowns and the swing timers stack above that row, left of the radial
-- menu, so nothing that sat next to the column is covered by it. The text
-- lane in the middle moves up a little, and the Consumable Bar sits beside
-- the gamepad bar. Every other frame keeps its layout spot.
--
-- Points are in the layouts' 2560 x 1440 units, relative to UIParent, so
-- no point hangs from another frame; they scale with the screen like the
-- layout points do. Three variants: the center band (most layouts), Plates
-- (the player in the middle, no target frame) and Vanilla (frames in the
-- corners, so only the bars, the cooldowns and the lane move). A family not
-- listed uses the center band.
local _, E = ...

-- From the bottom up: the cast bar, the resource bar, then one row of the
-- cooldowns with the player frame to its left and the target to its right,
-- all below the radial menu's bottom edge. Above the row, kept left of the
-- radial menu: the utility cooldowns, then the three swing timers. Right of
-- the radial menu: the totem bar with the buff bars above it, the trinket
-- row on the row of the target of target and the mobility row right of the
-- extra ability, both free to grow to the right (the left of the column is
-- where layouts keep their focus and party frames). The pet frame sits under the player frame and
-- the target of target right of the target, whatever the layout hangs
-- them from (left of the player some layouts keep their party frames);
-- the extra ability sits below the target of target.
local CENTER = {
	EldoUI_Player = { "RIGHT", "UIParent", "CENTER", -210, -337 },
	EldoUI_Target = { "LEFT", "UIParent", "CENTER", 210, -337 },
	EldoUI_Pet = { "TOPLEFT", "UIParent", "CENTER", -487, -364 },
	EldoUI_ToT = { "LEFT", "UIParent", "CENTER", 495, -337 },
	EldoUI_PlayerCastbar = { "CENTER", "UIParent", "CENTER", 0, -392 },
	EldoUI_PlayerPower = { "CENTER", "UIParent", "CENTER", 0, -371 },
	EldoUI_Cooldowns = { "CENTER", "UIParent", "CENTER", 0, -337 },
	EldoUI_CooldownsUtility = { "BOTTOMRIGHT", "UIParent", "CENTER", 104, -308 },
	EldoUI_Totems = { "BOTTOMLEFT", "UIParent", "CENTER", 530, -308 },
	EldoUI_CooldownsBars = { "BOTTOMLEFT", "UIParent", "CENTER", 530, -264 },
	EldoUI_CooldownsTrinkets = { "LEFT", "UIParent", "CENTER", 643, -337 },
	EldoUI_CooldownsMobility = { "TOPLEFT", "UIParent", "CENTER", 784, -364 },
	EldoUI_SwingRanged = { "BOTTOM", "UIParent", "CENTER", -78, -266 },
	EldoUI_SwingOffHand = { "BOTTOM", "UIParent", "CENTER", -78, -246 },
	EldoUI_SwingMainHand = { "BOTTOM", "UIParent", "CENTER", -78, -226 },
	EldoUI_ExtraAbility = { "CENTER", "UIParent", "CENTER", 640, -424 },
	EldoUI_ProcOverlay = { "CENTER", "UIParent", "CENTER", 0, 80 },
	EldoUI_CooldownPulse = { "CENTER", "UIParent", "CENTER", 0, 160 },
	EldoUI_Reminders = { "CENTER", "UIParent", "CENTER", -128, 80 },
	EldoUI_ConsumableBar = { "BOTTOMRIGHT", "UIParent", "BOTTOM", -344, 110 },
}

-- The player frame takes the cooldowns' middle spot, and the cooldowns
-- move to its right, where these layouts have no target frame (to its left
-- they would meet the party frames). The pet frame takes the player's left,
-- since the cast bar sits under the player here, and the focus frame moves
-- left of the party frames, out of the utility row.
local PLATES = {
	EldoUI_Player = { "CENTER", "UIParent", "CENTER", 0, -337 },
	EldoUI_Pet = { "RIGHT", "UIParent", "CENTER", -146, -337 },
	EldoUI_Focus = { "RIGHT", "UIParent", "CENTER", -658, -260 },
	EldoUI_PlayerCastbar = CENTER.EldoUI_PlayerCastbar,
	EldoUI_PlayerPower = CENTER.EldoUI_PlayerPower,
	EldoUI_Cooldowns = { "LEFT", "UIParent", "CENTER", 150, -337 },
	EldoUI_CooldownsUtility = CENTER.EldoUI_CooldownsUtility,
	EldoUI_Totems = CENTER.EldoUI_Totems,
	EldoUI_SwingRanged = CENTER.EldoUI_SwingRanged,
	EldoUI_SwingOffHand = CENTER.EldoUI_SwingOffHand,
	EldoUI_SwingMainHand = CENTER.EldoUI_SwingMainHand,
	EldoUI_ExtraAbility = CENTER.EldoUI_ExtraAbility,
	EldoUI_ProcOverlay = CENTER.EldoUI_ProcOverlay,
	EldoUI_CooldownPulse = CENTER.EldoUI_CooldownPulse,
	EldoUI_Reminders = CENTER.EldoUI_Reminders,
	EldoUI_ConsumableBar = CENTER.EldoUI_ConsumableBar,
}

-- The unit frames stay in their corners; the cooldowns leave the radial
-- menu's area for the center row.
local VANILLA = {
	EldoUI_PlayerCastbar = { "BOTTOM", "UIParent", "BOTTOM", 0, 330 },
	EldoUI_Cooldowns = CENTER.EldoUI_Cooldowns,
	EldoUI_CooldownsUtility = CENTER.EldoUI_CooldownsUtility,
	EldoUI_Totems = CENTER.EldoUI_Totems,
	EldoUI_SwingRanged = CENTER.EldoUI_SwingRanged,
	EldoUI_SwingOffHand = CENTER.EldoUI_SwingOffHand,
	EldoUI_SwingMainHand = CENTER.EldoUI_SwingMainHand,
	EldoUI_ExtraAbility = { "BOTTOM", "UIParent", "BOTTOM", 468, 110 },
	EldoUI_ProcOverlay = CENTER.EldoUI_ProcOverlay,
	EldoUI_CooldownPulse = CENTER.EldoUI_CooldownPulse,
	EldoUI_Reminders = CENTER.EldoUI_Reminders,
	EldoUI_ConsumableBar = CENTER.EldoUI_ConsumableBar,
}

E.gamepadOverlay = {
	variants = { center = CENTER, plates = PLATES, vanilla = VANILLA },
	-- Layout family -> variant.
	families = { EldoPlates = "plates", EldoVanilla = "vanilla" },
	-- The game's gamepad bar and radial menu in the same units (centered
	-- box: left, right, bottom, top from the screen's center), for the
	-- clash check.
	keepClear = {
		bar = { -328, 328, -610, -408 },
		radial = { 112, 512, -295, 295 },
	},
}
